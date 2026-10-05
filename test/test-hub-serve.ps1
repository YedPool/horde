# DOES THE HUB PULL EACH NODE'S INVENTORY OVER THE LINK, AND KEEP IT IN A MIRROR FILE IT CAN TRUST?
#
# Remote plan step R13a. cli/HubServe.ps1 holds `horde hub serve`'s loop and the mirror files; the rules
# of what the hub may say from a mirror are remote/Mirror.ps1's (test/test-hub-mirror.ps1). This suite,
# without a pipe:
#   - the mirror files: a mirror written is read back the same; nothing is left beside it; a file that
#     is not JSON, fails schema/node-mirror.v1, or holds an inventory the link contract refuses is
#     unknown with the reason, never a guessed mirror; no file is absent;
#   - one pull from cli/NodeServe.ps1's real loop, in a second runspace on the in-process memory
#     transport, answering from a fixed view: hello, a ping for the clock, sessions.list and a bye;
#   - every way a pull fails is a reason, not a crash: no node listening, a node answering as another
#     device, a node whose sessions.list is an error, a transport the hub could not pick;
#   - the loop over rounds: a node heard in the first round and gone in the second leaves a mirror whose
#     sessions are unknown, "node D unreachable since T";
#   - the registry: the hub's own node, by its device id, over the local link;
#   - `horde nodes`' report: answers as records, unknowns with their reasons.
# The same loop over the real local pipe, started through the real horde CLI, is
# transports/local/test/test-hub-serve-local.ps1, which needs this machine's interactive logon.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "Platform", "Namespace")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "transports\Port.ps1")
foreach ($t in @(Get-HordeTransportFiles)) { . $t }
. (Join-Path $root "remote\NodeServe.ps1")
. (Join-Path $root "remote\Mirror.ps1")
. (Join-Path $root "cli\HubServe.ps1")

$fx = Join-Path $root "test\fixtures\node-serve"
$viewPath = Join-Path $fx "view.json"
$device = "0f8fad5b-d9cb-469f-a165-70867728950e"
$other = "9b2e4c1a-3f5d-4e6a-8b7c-0d1e2f3a4b5c"
$hubId = "7c9e6679-7425-40de-944b-e07fc1f90ae7"
$hub = [pscustomobject]@{ id = $hubId; name = "fixture-hub"; hordeVersion = "0.1.0" }
$contract = Get-HordeLinkContract
$mem = Get-HordeTransport -Name "memory"
$work = Join-Path $env:TEMP ("horde-hub-serve-" + [guid]::NewGuid().ToString("N"))
$mirrorRoot = Join-Path $work "mirror"
New-Item -ItemType Directory -Path $mirrorRoot | Out-Null
# The fixture view as a node would build it now: the same sessions, observed this minute. The fixture
# itself was observed on 2026-10-02, and an inventory that old is stale on the hub's clock, as it should be.
$freshView = Join-Path $work "view-now.json"
$fixtureAt = "2026-10-02T12:00:00.000Z"
[System.IO.File]::WriteAllText($freshView, [System.IO.File]::ReadAllText($viewPath).Replace($fixtureAt, (Get-HordeLinkTime)))

function Start-Node {
    # cli/NodeServe.ps1's real loop in a second runspace, on the memory transport (test-node-serve's peer).
    param([int]$MaxLinks = 1, [switch]$ThrowOnView, [string]$View = $viewPath)
    $ready = New-Object System.Threading.ManualResetEventSlim($false)
    $ps = [PowerShell]::Create()
    [void]$ps.AddCommand((Join-Path $fx "serve-peer.ps1")).AddParameter("Root", $root).AddParameter("Endpoint", $device).AddParameter("ViewPath", $View).AddParameter("MaxLinks", $MaxLinks).AddParameter("IdleTimeoutMs", 30000).AddParameter("Ready", $ready)
    if ($ThrowOnView) { [void]$ps.AddParameter("ThrowOnView", $true) }
    $h = $ps.BeginInvoke()
    $up = $ready.Wait(30000)
    return [pscustomobject]@{ ps = $ps; h = $h; up = $up }
}
function Stop-Node {
    param($Node)
    $out = $null
    if ($Node.h.AsyncWaitHandle.WaitOne(40000)) { try { $out = @($Node.ps.EndInvoke($Node.h)) } catch { Write-Host ("         node side: " + $_.Exception.Message) -ForegroundColor Red } } else { try { $Node.ps.Stop() } catch { } }
    $Node.ps.Dispose()
    return (@($out | Where-Object { $null -ne $_ -and $null -ne $_.PSObject.Properties["served"] }) | Select-Object -First 1)
}
function Entry {
    param([string]$Expect = $device, $Transport = $mem, [string]$TransportError = "")
    return [pscustomobject]@{ deviceId = $Expect; deviceName = "fixture-node"; endpoint = $device; transport = $Transport; transportError = $TransportError }
}
function Utc { return [datetime]::UtcNow }

try {
    Write-Host ""
    Write-Host "--- the mirror files ---" -ForegroundColor Cyan
    $m = New-HordeNodeMirror -DeviceId $device -DeviceName "fixture-node"
    $path = Write-HordeHubMirror -Root $mirrorRoot -Mirror $m -Contract $contract
    Check ($path -ceq (Get-HordeHubMirrorPath -Root $mirrorRoot -DeviceId $device) -and (Split-Path -Leaf $path) -ceq ($device + ".json")) "a mirror is written to <root>\<deviceId>.json"
    $back = Read-HordeHubMirror -Path $path -Contract $contract
    Check ($back.state -ceq "known" -and $back.value.deviceId -ceq $device -and $back.value.deviceName -ceq "fixture-node") "and reads back as the same mirror"
    Check (@(Get-ChildItem -LiteralPath $mirrorRoot -Force).Count -eq 1) "nothing is left beside it: the write went through a temporary file that became it"
    $none = Read-HordeHubMirror -Path (Get-HordeHubMirrorPath -Root $mirrorRoot -DeviceId $other) -Contract $contract
    Check ($none.state -ceq "absent") "a node with no mirror file has none: absent"
    $bad = Join-Path $mirrorRoot "bad.json"
    [System.IO.File]::WriteAllText($bad, "{ not json")
    $r = Read-HordeHubMirror -Path $bad -Contract $contract
    Check ($r.state -ceq "unknown" -and $r.reason -clike "*could not be read*") ("a file that is not JSON is unknown, never a guessed mirror (" + $r.reason + ")")
    [System.IO.File]::WriteAllText($bad, '{"schemaVersion":1,"deviceId":"' + $device + '","deviceName":"x","extra":1}')
    $r = Read-HordeHubMirror -Path $bad -Contract $contract
    Check ($r.state -ceq "unknown" -and $r.reason -clike "*node-mirror.v1*extra*") ("a file that fails schema/node-mirror.v1 is unknown, naming the finding (" + $r.reason + ")")
    [System.IO.File]::WriteAllText($bad, '{"schemaVersion":1,"deviceId":"' + $device + '","deviceName":"x"}')
    Check ((Read-HordeHubMirror -Path $bad -Contract $contract).state -ceq "known") "CONTROL: the same file without the extra member reads"
    # An inventory the link contract refuses: a session whose role answer is known with no value.
    $view = [System.IO.File]::ReadAllText($viewPath) | ConvertFrom-Json
    $ns = New-HordeNamespace -Device $device -Space "windows"
    $list = ConvertTo-HordeMirrorObject (Get-HordeNodeSessionList -View $view -Namespace $ns -Contract $contract)
    $good = Update-HordeNodeMirror -Mirror $m -List $list -NodeSentAt (Utc) -ReceivedAt (Utc)
    $gp = Write-HordeHubMirror -Root $mirrorRoot -Mirror $good -Contract $contract
    Check ((Read-HordeHubMirror -Path $gp -Contract $contract).state -ceq "known") "CONTROL: a mirror holding the node's real list reads"
    $text = [System.IO.File]::ReadAllText($gp)
    $broken = $text.Replace('"role":{"state":"known","value":"goblin"', '"role":{"state":"known"')
    Check ($broken -cne $text) "CONTROL: the fixture's role answer is there to break"
    [System.IO.File]::WriteAllText($bad, $broken)
    $r = Read-HordeHubMirror -Path $bad -Contract $contract
    Check ($r.state -ceq "unknown" -and $r.reason -clike "*link contract*") ("an inventory the link contract refuses is unknown, naming the contract (" + $r.reason + ")")
    $carriedBroken = $good | ConvertTo-Json -Depth 40 | ConvertFrom-Json
    $carriedBroken.inventory.carried = @([pscustomobject]@{ lastSeenAt = "2026-10-05T12:00:00Z"; session = [pscustomobject]@{ sessionId = "x" } })
    $threw = $false; try { $null = Write-HordeHubMirror -Root $mirrorRoot -Mirror $carriedBroken -Contract $contract } catch { $threw = $true }
    Check $threw "a mirror whose carried sessions the contract refuses is never written"
    Remove-Item -LiteralPath $bad -Force

    Write-Host ""
    Write-Host "--- one pull, from the node's real loop ---" -ForegroundColor Cyan
    $node = Start-Node
    Check ($node.up -eq $true) "the node is listening"
    $p = Invoke-HordeHubPull -Entry (Entry) -Hub $hub -Contract $contract -TimeoutMs 30000
    $served = Stop-Node $node
    Check ($p.ok -eq $true -and "$($p.reason)" -eq "") ("the pull succeeds (" + $p.reason + ")")
    Check (@($p.list.sessions).Count -eq 2 -and $p.list.complete.value -eq $false) "it brings the node's sessions.list: two sessions, complete known false as the fixture view says"
    Check ($p.nodeName -ceq "fixture-node" -and (Test-HordeClockUtc $p.nodeSentAt) -and (Test-HordeClockUtc $p.receivedAt)) "the node's name from its hello, and the node's send time and the hub's receive time, both UTC"
    Check ($p.clock.state -ceq "known" -and [math]::Abs([double]$p.clock.value.offsetSeconds) -lt 5) ("a ping gives a clock sample: one process, so no offset to speak of (" + $p.clock.value.offsetSeconds + " s)")
    Check ($null -ne $served -and $served.served -eq 1 -and "$(@($served.endings)[0])" -clike "*closed by the protocol*") "the node served one link and the hub ended it with a bye"
    $old = Update-HordeNodeMirror -Mirror (New-HordeNodeMirror -DeviceId $device -DeviceName "fixture-node") -List $p.list -NodeSentAt $p.nodeSentAt -ReceivedAt $p.receivedAt
    $stale = @(Get-HordeMirrorRows -Mirror $old -Now (Utc))
    Check ($stale.Count -eq 2 -and @($stale | Where-Object { $_.presence.state -ceq "unknown" -and $_.presence.reason -clike "stale*" }).Count -eq 2) ("an inventory the node says it observed days ago is stale on the hub's clock, though just received (" + $stale[0].presence.reason + ")")

    $node = Start-Node
    $p = Invoke-HordeHubPull -Entry (Entry -Expect $other) -Hub $hub -Contract $contract -TimeoutMs 30000
    $served = Stop-Node $node
    Check ($p.ok -eq $false -and $p.reason -clike ("*answered as device " + $device + "*not " + $other + "*")) ("a node that answers as another device is refused, naming both (" + $p.reason + ")")
    Check ($null -ne $served -and $served.served -eq 1 -and "$(@($served.endings)[0])" -clike "*closed by the protocol*") "and the hub says bye rather than ask it anything"

    $node = Start-Node -ThrowOnView
    $p = Invoke-HordeHubPull -Entry (Entry) -Hub $hub -Contract $contract -TimeoutMs 30000
    $null = Stop-Node $node
    Check ($p.ok -eq $false -and $p.reason -clike "*sessions.list*internal*could not build its view*") ("a node whose sessions.list is an error fails the pull with the node's reason (" + $p.reason + ")")

    $began = Utc
    $p = Invoke-HordeHubPull -Entry (Entry) -Hub $hub -Contract $contract -TimeoutMs 30000
    Check ($p.ok -eq $false -and $p.reason -clike "*could not open a link*" -and ((Utc) - $began).TotalSeconds -lt 20) ("with nobody listening the pull fails at once, saying so (" + $p.reason + ")")
    $p = Invoke-HordeHubPull -Entry (Entry -Transport $null -TransportError "the transport declines auth.peer") -Hub $hub -Contract $contract -TimeoutMs 30000
    Check ($p.ok -eq $false -and $p.reason -clike "*declines auth.peer*") "a node whose transport the hub could not pick fails with that reason"

    Write-Host ""
    Write-Host "--- the loop: a node heard, then gone ---" -ForegroundColor Cyan
    Remove-Item -LiteralPath (Get-HordeHubMirrorPath -Root $mirrorRoot -DeviceId $device) -Force -ErrorAction SilentlyContinue
    $node = Start-Node -MaxLinks 1 -View $freshView
    $rounds = @(Invoke-HordeHubServe -Nodes @(Entry) -Root $mirrorRoot -Hub $hub -Contract $contract -Rounds 1 -IntervalMs 0 -TimeoutMs 30000)
    $null = Stop-Node $node
    $after1 = Read-HordeHubMirror -Path (Get-HordeHubMirrorPath -Root $mirrorRoot -DeviceId $device) -Contract $contract
    Check ($rounds.Count -eq 1 -and $after1.state -ceq "known" -and $null -ne (Get-HordeLinkProp $after1.value "heardAt") -and @($after1.value.inventory.list.sessions).Count -eq 2) "round one writes a mirror with the node's two sessions"
    $rows = @(Get-HordeMirrorRows -Mirror $after1.value -Now (Utc))
    Check ($rows.Count -eq 2 -and @($rows | Where-Object { $_.presence.state -ceq "known" -and $_.device -ceq $device }).Count -eq 2) "CONTROL: and its sessions are known present, on the node's device"
    $t2 = Utc
    $rounds = @(Invoke-HordeHubServe -Nodes @(Entry) -Root $mirrorRoot -Hub $hub -Contract $contract -Rounds 1 -IntervalMs 0 -TimeoutMs 30000)
    $after2 = Read-HordeHubMirror -Path (Get-HordeHubMirrorPath -Root $mirrorRoot -DeviceId $device) -Contract $contract
    $lost = Get-HordeLinkProp $after2.value "lost"
    Check ($after2.state -ceq "known" -and $null -ne $lost -and (ConvertFrom-HordeMirrorTime $lost.since) -ge $t2.AddSeconds(-1)) "round two, with the node gone, marks the mirror lost since that round"
    Check (@($after2.value.inventory.list.sessions).Count -eq 2) "and keeps the last inventory as last-known"
    $rows = @(Get-HordeMirrorRows -Mirror $after2.value -Now (Utc))
    Check ($rows.Count -eq 2 -and @($rows | Where-Object { $_.presence.state -ceq "unknown" -and $_.presence.reason -clike ("node fixture-node (" + $device + ") unreachable since " + $lost.since + "*") }).Count -eq 2) ("its sessions are unknown, 'node D unreachable since T' (" + $rows[0].presence.reason + ")")
    Check ("$(@($rounds)[0].outcomes[0])" -clike "*unreachable*could not open a link*") ("the round says what happened to the node (" + "$(@($rounds)[0].outcomes[0])" + ")")

    $corrupt = Get-HordeHubMirrorPath -Root $mirrorRoot -DeviceId $device
    [System.IO.File]::WriteAllText($corrupt, "garbage")
    $rounds = @(Invoke-HordeHubServe -Nodes @(Entry -Transport $null -TransportError "no transport") -Root $mirrorRoot -Hub $hub -Contract $contract -Rounds 1 -IntervalMs 0 -TimeoutMs 30000)
    $after3 = Read-HordeHubMirror -Path $corrupt -Contract $contract
    Check ($after3.state -ceq "known" -and "$((Get-HordeLinkProp $after3.value 'lost').reason)" -clike "*no transport*") "an unreadable mirror is started afresh, never a crash, and the round's failure is recorded in it"
    Check ("$(@($rounds)[0].outcomes[0])" -clike "*mirror*could not be read*") ("and the round says the old mirror was unreadable (" + "$(@($rounds)[0].outcomes[0])" + ")")

    # A fault while pulling is that node's outcome, recorded in its mirror, never the end of the hub (as
    # the node's own loop answers a fault rather than crash): a contract the link's writer cannot use
    # makes the hub's first send throw, after the link to a live node is open.
    $node = Start-Node
    $brokenContract = [pscustomobject]@{ frame = $null; verbs = $null; limits = @{} }
    $rounds = @(Invoke-HordeHubServe -Nodes @(Entry) -Root $mirrorRoot -Hub $hub -Contract $brokenContract -Rounds 1 -IntervalMs 0 -TimeoutMs 30000)
    $null = Stop-Node $node
    $after4 = Read-HordeHubMirror -Path $corrupt -Contract $contract
    Check ("$(@($rounds)[0].outcomes[0])" -clike "*unreachable: the hub failed while pulling*") ("a throw while pulling is the node's outcome (" + "$(@($rounds)[0].outcomes[0])" + ")")
    Check ($after4.state -ceq "known" -and "$((Get-HordeLinkProp $after4.value 'lost').reason)" -clike "*failed while pulling*") "and is recorded in its mirror, so its sessions read unknown"

    Write-Host ""
    Write-Host "--- the registry ---" -ForegroundColor Cyan
    $reg = @(Get-HordeHubRegistry -Node ([pscustomobject]@{ deviceId = $device; deviceName = "this-box" }))
    Check ($reg.Count -eq 1 -and $reg[0].deviceId -ceq $device -and $reg[0].endpoint -ceq $device -and $reg[0].deviceName -ceq "this-box") "the registry is the hub's own node, dialled at its device id: the hub is always also a node"
    Check ($reg[0].transportName -ceq "local") "over the local link, the one transport a node is served on before enrolment (R17)"

    Write-Host ""
    Write-Host "--- horde nodes' report ---" -ForegroundColor Cyan
    $fleet = Get-HordeFleetView -Mirrors @($after2.value) -Now (Utc)
    $rep = ConvertTo-HordeNodesReport -Fleet $fleet
    $json = $rep | ConvertTo-Json -Depth 40 | ConvertFrom-Json
    Check (@($json.nodes).Count -eq 1 -and $json.nodes[0].heard.state -ceq "unknown" -and $json.nodes[0].heard.reason -clike "*unreachable since*") "each node's answer is a record: state and reason"
    Check (@($json.sessions).Count -eq 2 -and @($json.sessions | Where-Object { $_.presence.state -ceq "unknown" -and $_.fields.role.state -ceq "unknown" -and $_.device -ceq $device }).Count -eq 2) "each session row carries its device, its presence and its fields as records"
    Check (@($json.sessions | Where-Object { "$($_.lastKnown.role.value)" -ceq "goblin" }).Count -ge 1) "and its last-known copy while it is not current"
    $text = @(Format-HordeNodesText -Report $rep)
    Check (@($text | Where-Object { $_ -clike "*fixture-node*$device*unreachable since*" }).Count -eq 1) ("the text names the node and why it is not heard (" + ($text -join " | ") + ")")
    $fleet = Get-HordeFleetView -Mirrors @($after1.value) -Now (Utc)
    $text = @(Format-HordeNodesText -Report (ConvertTo-HordeNodesReport -Fleet $fleet))
    Check (@($text | Where-Object { $_ -clike "*fixture-node*heard*2 session(s)*partial*" }).Count -eq 1) ("CONTROL: a heard node's line says so, with its count and that its inventory is partial (" + ($text -join " | ") + ")")
} finally {
    if ((Split-Path -Leaf $work) -match '^horde-hub-serve-[0-9a-f]{32}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

Complete-HordeSuite -Success "the hub pulls each node's inventory over the link, keeps it in a mirror file checked by the contract, and turns a node it cannot reach into unknown, never absent"
