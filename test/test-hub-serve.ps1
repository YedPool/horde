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
foreach ($f in @("Tristate", "Platform", "Namespace", "ReadShared", "FileAtomic")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
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
# Stamped where it is used, not at the suite's start: on a loaded machine the sections before the loop
# took more than the 60 s TTL, and the loop's control then read the sessions as stale (measured
# 2026-10-07: "observed 66s ago, past its 60s TTL").
$freshView = Join-Path $work "view-now.json"
$fixtureAt = "2026-10-02T12:00:00.000Z"
$freshAt = ""
function Update-FreshView {
    $script:freshAt = Get-HordeLinkTime
    [System.IO.File]::WriteAllText($freshView, [System.IO.File]::ReadAllText($viewPath).Replace($fixtureAt, $script:freshAt))
}

function Start-Node {
    # cli/NodeServe.ps1's real loop in a second runspace, on the memory transport (test-node-serve's peer).
    param([int]$MaxLinks = 1, [switch]$ThrowOnView, [string]$View = $viewPath, [string]$At = $device, [int]$ViewDelayMs = 0)
    $ready = New-Object System.Threading.ManualResetEventSlim($false)
    $ps = [PowerShell]::Create()
    [void]$ps.AddCommand((Join-Path $fx "serve-peer.ps1")).AddParameter("Root", $root).AddParameter("Endpoint", $At).AddParameter("ViewPath", $View).AddParameter("ViewDelayMs", $ViewDelayMs).AddParameter("MaxLinks", $MaxLinks).AddParameter("IdleTimeoutMs", 30000).AddParameter("Ready", $ready)
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
    param([string]$Expect = $device, $Transport = $mem, [string]$TransportError = "", [string]$At = $device)
    return [pscustomobject]@{ deviceId = $Expect; deviceName = "fixture-node"; endpoint = $At; transport = $Transport; transportError = $TransportError }
}
function Utc { return [datetime]::UtcNow }

try {
    Write-Host ""
    Write-Host "--- the mirror files ---" -ForegroundColor Cyan
    $m = New-HordeNodeMirror -DeviceId $device -DeviceName "fixture-node"
    $path = Write-HordeHubMirror -Root $mirrorRoot -Mirror $m -Contract $contract
    Check ($path -ceq (Get-HordeHubMirrorPath -Root $mirrorRoot -DeviceId $device) -and (Split-Path -Leaf $path) -ceq ($device + ".json")) "a mirror is written to <root>\<deviceId>.json"
    $back = Read-HordeHubMirror -Path $path -DeviceId $device -Contract $contract
    Check ($back.state -ceq "known" -and $back.value.deviceId -ceq $device -and $back.value.deviceName -ceq "fixture-node") "and reads back as the same mirror"
    Check (@(Get-ChildItem -LiteralPath $mirrorRoot -Force).Count -eq 1) "nothing is left beside it: the write went through a temporary file that became it"
    $none = Read-HordeHubMirror -Path (Get-HordeHubMirrorPath -Root $mirrorRoot -DeviceId $other) -DeviceId $other -Contract $contract
    Check ($none.state -ceq "absent") "a node with no mirror file has none: absent"
    $bad = Join-Path $mirrorRoot "bad.json"
    [System.IO.File]::WriteAllText($bad, "{ not json")
    $r = Read-HordeHubMirror -Path $bad -DeviceId $device -Contract $contract
    Check ($r.state -ceq "unknown" -and $r.reason -clike "*could not be read*") ("a file that is not JSON is unknown, never a guessed mirror (" + $r.reason + ")")
    [System.IO.File]::WriteAllText($bad, '{"schemaVersion":1,"deviceId":"' + $device + '","deviceName":"x","extra":1}')
    $r = Read-HordeHubMirror -Path $bad -DeviceId $device -Contract $contract
    Check ($r.state -ceq "unknown" -and $r.reason -clike "*node-mirror.v1*extra*") ("a file that fails schema/node-mirror.v1 is unknown, naming the finding (" + $r.reason + ")")
    [System.IO.File]::WriteAllText($bad, '{"schemaVersion":1,"deviceId":"' + $device + '","deviceName":"x"}')
    Check ((Read-HordeHubMirror -Path $bad -DeviceId $device -Contract $contract).state -ceq "known") "CONTROL: the same file without the extra member reads"
    # An inventory the link contract refuses: a session whose role answer is known with no value.
    $view = [System.IO.File]::ReadAllText($viewPath) | ConvertFrom-Json
    $ns = New-HordeNamespace -Device $device -Space "windows"
    $list = ConvertTo-HordeMirrorObject (Get-HordeNodeSessionList -View $view -Namespace $ns -Contract $contract)
    $good = Update-HordeNodeMirror -Mirror $m -List $list -NodeSentAt (Utc) -ReceivedAt (Utc)
    $gp = Write-HordeHubMirror -Root $mirrorRoot -Mirror $good -Contract $contract
    Check ((Read-HordeHubMirror -Path $gp -DeviceId $device -Contract $contract).state -ceq "known") "CONTROL: a mirror holding the node's real list reads"
    $text = [System.IO.File]::ReadAllText($gp)
    $broken = $text.Replace('"role":{"state":"known","value":"goblin"', '"role":{"state":"known"')
    Check ($broken -cne $text) "CONTROL: the fixture's role answer is there to break"
    [System.IO.File]::WriteAllText($bad, $broken)
    $r = Read-HordeHubMirror -Path $bad -DeviceId $device -Contract $contract
    Check ($r.state -ceq "unknown" -and $r.reason -clike "*link contract*") ("an inventory the link contract refuses is unknown, naming the contract (" + $r.reason + ")")
    $carriedBroken = $good | ConvertTo-Json -Depth 40 | ConvertFrom-Json
    $carriedBroken.inventory.carried = @([pscustomobject]@{ lastSeenAt = "2026-10-05T12:00:00Z"; session = [pscustomobject]@{ sessionId = "x" } })
    $threw = $false; try { $null = Write-HordeHubMirror -Root $mirrorRoot -Mirror $carriedBroken -Contract $contract } catch { $threw = $true }
    Check $threw "a mirror whose carried sessions the contract refuses is never written"
    Remove-Item -LiteralPath $bad -Force

    Write-Host ""
    Write-Host "--- the write path (review of PR #86, F1, F3, F5 and F6) ---" -ForegroundColor Cyan
    # F1, the reviewer's shape, through the real write: a complete list of 90 large sessions, then a
    # partial list of 90 others, then a partial list of one. Each list fits a frame; the carried union of
    # the first two did not, and the mirror could never be written again.
    $big = Join-Path $work "big"
    function Large {
        param([string]$Id)
        $at = Get-HordeLinkTime
        $why = "r" + ("x" * 900)
        $ns = [pscustomobject][ordered]@{ device = $device; space = "windows" }
        $u = { [pscustomobject][ordered]@{ state = "unknown"; reason = $why } }
        $placed = { [pscustomobject][ordered]@{ state = "unknown"; reason = $why; ns = $ns } }
        return [pscustomobject][ordered]@{ sessionId = $Id; agent = [pscustomobject][ordered]@{ state = "known"; value = "harness-a"; reason = ""; observedAt = $at }; fleetSessionId = (& $u); role = [pscustomobject][ordered]@{ state = "known"; value = "goblin"; reason = ""; observedAt = $at }; label = (& $u); parent = (& $u); liveStatus = (& $u); workState = (& $u); startedAt = (& $u); lastActivity = (& $u); retired = (& $u); pid = (& $placed); procStart = (& $placed); projectCwd = (& $placed) }
    }
    function BigList {
        param([object[]]$Sessions, [bool]$Complete)
        $at = Get-HordeLinkTime
        $c = [pscustomobject][ordered]@{ state = "known"; value = $Complete; reason = ""; observedAt = $at }
        if (-not $Complete) { $c.reason = "not complete: a store was locked" }
        return (ConvertTo-HordeMirrorObject ([pscustomobject][ordered]@{ complete = $c; sessions = @($Sessions); observedAt = $at }))
    }
    $bm = New-HordeNodeMirror -DeviceId $device -DeviceName "fixture-node"
    $bm = Update-HordeNodeMirror -Mirror $bm -List (BigList @(1..90 | ForEach-Object { Large ("a-" + $_) }) $true) -NodeSentAt (Utc) -ReceivedAt (Utc)
    $e1 = ""; try { $null = Write-HordeHubMirror -Root $big -Mirror $bm -Contract $contract } catch { $e1 = $_.Exception.Message }
    $bm = Update-HordeNodeMirror -Mirror $bm -List (BigList @(1..90 | ForEach-Object { Large ("b-" + $_) }) $false) -NodeSentAt (Utc) -ReceivedAt (Utc)
    $e2 = ""; try { $null = Write-HordeHubMirror -Root $big -Mirror $bm -Contract $contract } catch { $e2 = $_.Exception.Message }
    Check ($e1 -eq "" -and $e2 -eq "" -and @($bm.inventory.carried).Count -eq 90) ("CONTROL: the first two writes succeed, with 90 large sessions carried (" + $e1 + $e2 + ")")
    $bm = Update-HordeNodeMirror -Mirror $bm -List (BigList @((Large "c-1")) $false) -NodeSentAt (Utc) -ReceivedAt (Utc)
    $e3 = ""; try { $null = Write-HordeHubMirror -Root $big -Mirror $bm -Contract $contract } catch { $e3 = $_.Exception.Message }
    $back = Read-HordeHubMirror -Path (Get-HordeHubMirrorPath -Root $big -DeviceId $device) -DeviceId $device -Contract $contract
    Check ($e3 -eq "" -and $back.state -ceq "known" -and @($back.value.inventory.carried).Count -lt 180 -and @($back.value.inventory.carried).Count -ge 90) ("the third write succeeds: the carried sessions were cut to fit one frame (" + @($bm.inventory.carried).Count + " kept; " + $e3 + ")")
    Check ([int]$contract.limits["frameBytes"] -eq $script:HordeMirrorFrameBytes) "the mirror's frame budget is the contract's frameBytes"

    # F3. MEASURED HERE, 2026-10-05: MoveFileEx's rename over the mirror fails "Access is denied" for as
    # long as any handle is open on it, delete sharing or not; Move-HordeFileAtomic tries again for 2 s.
    # So a reader that holds the mirror briefly - one `horde nodes` read - costs the write a retry, not
    # the round; a reader that holds it past 2 s makes that write fail, and the write leaves nothing.
    $mp = Get-HordeHubMirrorPath -Root $big -DeviceId $device
    $opened = New-Object System.Threading.ManualResetEventSlim($false)
    $brief = [PowerShell]::Create()
    [void]$brief.AddScript({ param($Path, $Opened) $s = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)); $Opened.Set(); Start-Sleep -Milliseconds 500; $s.Dispose() }).AddArgument($mp).AddArgument($opened)
    $h = $brief.BeginInvoke()
    $null = $opened.Wait(10000)
    $e4 = ""; $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try { $null = Write-HordeHubMirror -Root $big -Mirror $bm -Contract $contract } catch { $e4 = $_.Exception.Message }
    $sw.Stop()
    $null = $h.AsyncWaitHandle.WaitOne(10000); $brief.Dispose()
    Check ($e4 -eq "") ("a write begun while a reader holds the mirror for half a second waits it out and succeeds (" + [math]::Round($sw.Elapsed.TotalSeconds, 2) + " s; " + $e4 + ")")
    $long = [System.IO.File]::Open($mp, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
    $e5 = ""
    try { $null = Write-HordeHubMirror -Root $big -Mirror $bm -Contract $contract } catch { $e5 = $_.Exception.Message } finally { $long.Dispose() }
    Check ($e5 -ne "") ("CONTROL: a reader that holds it past the 2 s retry makes that write fail (" + $e5 + ")")
    Check (@(Get-HordeHubMirrorTemps -Root $big -DeviceId $device).Count -eq 0) "and the failed write leaves no temporary file behind"
    Check ((Read-HordeHubMirror -Path $mp -DeviceId $device -Contract $contract).state -ceq "known") "and the mirror it could not replace is still whole"
    $writer = [System.IO.File]::Open($mp, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::ReadWrite)
    $r6 = $null; $e6 = ""
    try {
        $r6 = Read-HordeHubMirror -Path $mp -DeviceId $device -Contract $contract
        try { $null = [System.IO.File]::ReadAllText($mp) } catch { $e6 = $_.Exception.Message }
    } finally { $writer.Dispose() }
    Check ($null -ne $r6 -and $r6.state -ceq "known") "Read-HordeHubMirror reads while another process holds the mirror open for writing"
    Check ($e6 -ne "") ("CONTROL: ReadAllText cannot (" + $e6 + ")")

    # The temporary files a killed write leaves: recovered when the mirror is gone, removed otherwise.
    $name = Split-Path -Leaf $mp
    $orphan = Join-Path $big ($name + "." + [guid]::NewGuid().ToString("N") + ".tmp")
    [System.IO.File]::Copy($mp, $orphan)
    $other1 = Join-Path $big "unrelated.json.tmp"
    [System.IO.File]::WriteAllText($other1, "not ours")
    $lines = @(Clear-HordeHubMirrorTemps -Root $big -DeviceId $device -Contract $contract)
    Check (-not (Test-Path -LiteralPath $orphan) -and (Test-Path -LiteralPath $mp) -and $lines.Count -eq 1 -and $lines[0] -clike "removed *") ("with the mirror whole, a left-behind temporary file is removed (" + ($lines -join "; ") + ")")
    Check (Test-Path -LiteralPath $other1) "and a file that is not one of its temporary files is left alone"
    [System.IO.File]::Copy($mp, $orphan)
    $junk = Join-Path $big ($name + "." + [guid]::NewGuid().ToString("N") + ".tmp")
    [System.IO.File]::WriteAllText($junk, "half a mirror")
    Remove-Item -LiteralPath $mp -Force
    $lines = @(Clear-HordeHubMirrorTemps -Root $big -DeviceId $device -Contract $contract)
    $rec = Read-HordeHubMirror -Path $mp -DeviceId $device -Contract $contract
    Check ($rec.state -ceq "known" -and @($lines | Where-Object { $_ -clike "recovered *" }).Count -eq 1) ("with the mirror gone, a whole temporary mirror is recovered into its place (" + ($lines -join "; ") + ")")
    Check (@(Get-HordeHubMirrorTemps -Root $big -DeviceId $device).Count -eq 0) "and the torn one is removed"

    # F5: only a device id names a mirror file; F6: a file holding another device's mirror is refused.
    $threw = 0
    foreach ($badId in @(("..\" + $device), $device.ToUpperInvariant(), ($device + "\x"))) { try { $null = Get-HordeHubMirrorPath -Root $big -DeviceId $badId } catch { $threw++ } }
    Check ($threw -eq 3) "a mirror path is only ever named by a lower-case device id: no '..', no upper case, nothing after it"
    $impostor = New-HordeNodeMirror -DeviceId $other -DeviceName "impostor"
    [System.IO.File]::WriteAllText($mp, ($impostor | ConvertTo-Json -Compress))
    $r7 = Read-HordeHubMirror -Path $mp -DeviceId $device -Contract $contract
    Check ($r7.state -ceq "unknown" -and $r7.reason -clike ("*holds the mirror of device " + $other + ", not " + $device + "*")) ("a mirror file holding another device's mirror is refused, naming both (" + $r7.reason + ")")
    Check ((Read-HordeHubMirror -Path $mp -DeviceId $other -Contract $contract).state -ceq "known") "CONTROL: read as the device it names, the same file is a mirror"

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
    Check ($p.ok -eq $false -and $p.reason -clike ("*claims device '" + $device + "'*enrolled for device " + $other + "*")) ("a node that answers as another device is refused, naming both (" + $p.reason + ")")
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
    Update-FreshView
    $node = Start-Node -MaxLinks 1 -View $freshView
    $rounds = @(Invoke-HordeHubServe -Nodes @(Entry) -Root $mirrorRoot -Hub $hub -Contract $contract -Rounds 1 -IntervalMs 0 -TimeoutMs 30000)
    $null = Stop-Node $node
    # Checked here, at the first round, so a hub that kept its run lock fails a check rather than every
    # later round with "another hub is running" (issue #87, F9).
    $free = $null; try { $free = [System.IO.File]::Open((Get-HordeHubLockPath -Root $mirrorRoot), [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None) } catch { } finally { if ($null -ne $free) { $free.Dispose() } }
    Check ($null -ne $free) "the hub lets its run lock go when it returns"
    $after1 = Read-HordeHubMirror -Path (Get-HordeHubMirrorPath -Root $mirrorRoot -DeviceId $device) -DeviceId $device -Contract $contract
    Check ($rounds.Count -eq 1 -and $after1.state -ceq "known" -and $null -ne (Get-HordeLinkProp $after1.value "heardAt") -and @($after1.value.inventory.list.sessions).Count -eq 2) "round one writes a mirror with the node's two sessions"
    $rows = @(Get-HordeMirrorRows -Mirror $after1.value -Now (Utc))
    Check ($rows.Count -eq 2 -and @($rows | Where-Object { $_.presence.state -ceq "known" -and $_.device -ceq $device }).Count -eq 2) ("CONTROL: and its sessions are known present, on the node's device (" + (@($rows | ForEach-Object { "$($_.presence.state) $($_.presence.reason)" }) -join " | ") + "; view observed " + $freshAt + ", now " + (Get-HordeLinkTime) + ")")
    $t2 = Utc
    $rounds = @(Invoke-HordeHubServe -Nodes @(Entry) -Root $mirrorRoot -Hub $hub -Contract $contract -Rounds 1 -IntervalMs 0 -TimeoutMs 30000)
    $after2 = Read-HordeHubMirror -Path (Get-HordeHubMirrorPath -Root $mirrorRoot -DeviceId $device) -DeviceId $device -Contract $contract
    $lost = Get-HordeLinkProp $after2.value "lost"
    Check ($after2.state -ceq "known" -and $null -ne $lost -and (ConvertFrom-HordeMirrorTime $lost.since) -ge $t2.AddSeconds(-1)) "round two, with the node gone, marks the mirror lost since that round"
    Check (@($after2.value.inventory.list.sessions).Count -eq 2) "and keeps the last inventory as last-known"
    $rows = @(Get-HordeMirrorRows -Mirror $after2.value -Now (Utc))
    Check ($rows.Count -eq 2 -and @($rows | Where-Object { $_.presence.state -ceq "unknown" -and $_.presence.reason -clike ("node fixture-node (" + $device + ") unreachable since " + $lost.since + "*") }).Count -eq 2) ("its sessions are unknown, 'node D unreachable since T' (" + $rows[0].presence.reason + ")")
    Check ("$(@($rounds)[0].outcomes[0])" -clike "*unreachable*could not open a link*") ("the round says what happened to the node (" + "$(@($rounds)[0].outcomes[0])" + ")")

    $corrupt = Get-HordeHubMirrorPath -Root $mirrorRoot -DeviceId $device
    [System.IO.File]::WriteAllText($corrupt, "garbage")
    # And a temporary file a killed write left: the hub clears it before its first round reads a mirror.
    $left = $corrupt + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    [System.IO.File]::WriteAllText($left, "half a mirror")
    $rounds = @(Invoke-HordeHubServe -Nodes @(Entry -Transport $null -TransportError "no transport") -Root $mirrorRoot -Hub $hub -Contract $contract -Rounds 1 -IntervalMs 0 -TimeoutMs 30000)
    $after3 = Read-HordeHubMirror -Path $corrupt -DeviceId $device -Contract $contract
    Check ($after3.state -ceq "known" -and "$((Get-HordeLinkProp $after3.value 'lost').reason)" -clike "*no transport*") "an unreadable mirror is started afresh, never a crash, and the round's failure is recorded in it"
    Check ("$(@($rounds)[0].outcomes[0])" -clike "*mirror*could not be read*") ("and the round says the old mirror was unreadable (" + "$(@($rounds)[0].outcomes[0])" + ")")
    Check (-not (Test-Path -LiteralPath $left) -and @(@($rounds)[0].outcomes | Where-Object { $_ -clike "*removed *.tmp" }).Count -eq 1) "the hub cleared the temporary file a killed write left, and said so"

    # A fault while pulling is that node's outcome, recorded in its mirror, never the end of the hub (as
    # the node's own loop answers a fault rather than crash): a contract the link's writer cannot use
    # makes the hub's first send throw, after the link to a live node is open.
    $node = Start-Node
    $brokenContract = [pscustomobject]@{ frame = $null; verbs = $null; limits = @{} }
    $rounds = @(Invoke-HordeHubServe -Nodes @(Entry) -Root $mirrorRoot -Hub $hub -Contract $brokenContract -Rounds 1 -IntervalMs 0 -TimeoutMs 30000)
    $null = Stop-Node $node
    $after4 = Read-HordeHubMirror -Path $corrupt -DeviceId $device -Contract $contract
    Check ("$(@($rounds)[0].outcomes[0])" -clike "*unreachable: the hub failed while pulling*") ("a throw while pulling is the node's outcome (" + "$(@($rounds)[0].outcomes[0])" + ")")
    Check ($after4.state -ceq "known" -and "$((Get-HordeLinkProp $after4.value 'lost').reason)" -clike "*failed while pulling*") "and is recorded in its mirror, so its sessions read unknown"

    Write-Host ""
    Write-Host "--- a mirror the hub cannot use is kept aside (issue #87, F8) ---" -ForegroundColor Cyan
    $f8 = Join-Path $work "f8"
    New-Item -ItemType Directory -Path $f8 | Out-Null
    $f8Path = Get-HordeHubMirrorPath -Root $f8 -DeviceId $device
    [System.IO.File]::WriteAllText($f8Path, "garbage that was a mirror")
    $rounds = @(Invoke-HordeHubServe -Nodes @(Entry -Transport $null -TransportError "no transport") -Root $f8 -Hub $hub -Contract $contract -Rounds 1 -IntervalMs 0 -TimeoutMs 30000)
    $aside = @(Get-ChildItem -LiteralPath $f8 -File | Where-Object { $_.Name -cmatch ('\A' + [regex]::Escape($device) + '\.json\.bad-[0-9]{8}T[0-9]{9}Z\z') })
    Check ($aside.Count -eq 1 -and [System.IO.File]::ReadAllText($aside[0].FullName) -ceq "garbage that was a mirror") ("an unreadable mirror is renamed aside as <id>.json.bad-<stamp>, its bytes kept (" + (@($aside | ForEach-Object { $_.Name }) -join ", ") + ")")
    Check (@($rounds[0].outcomes | Where-Object { $_ -clike ("*kept aside as " + $aside[0].Name + "*") }).Count -eq 1) ("and the round says where (" + ($rounds[0].outcomes -join " | ") + ")")
    Check ((Read-HordeHubMirror -Path $f8Path -DeviceId $device -Contract $contract).state -ceq "known") "a fresh mirror takes its place"
    Remove-Item -LiteralPath $f8Path -Force
    $rounds = @(Invoke-HordeHubServe -Nodes @(Entry -Transport $null -TransportError "no transport") -Root $f8 -Hub $hub -Contract $contract -Rounds 1 -IntervalMs 0 -TimeoutMs 30000)
    Check (@($rounds[0].outcomes | Where-Object { $_ -clike "*no mirror file was there; started afresh*" }).Count -eq 1) ("a missing mirror is said, not silently started afresh (" + ($rounds[0].outcomes -join " | ") + ")")
    $rounds = @(Invoke-HordeHubServe -Nodes @(Entry -Transport $null -TransportError "no transport") -Root $f8 -Hub $hub -Contract $contract -Rounds 1 -IntervalMs 0 -TimeoutMs 30000)
    Check (@($rounds[0].outcomes | Where-Object { $_ -clike "*afresh*" -or $_ -clike "*kept aside*" }).Count -eq 0 -and @(Get-ChildItem -LiteralPath $f8 -File -Filter "*.bad-*").Count -eq 1) "CONTROL: a readable mirror is used as it is: no note, nothing new kept aside"

    # A GOOD MIRROR HELD OPEN IS NOT A BAD ONE (review of PR #88): a reader that holds the file without
    # sharing read made it unreadable for a moment, and the round moved the good mirror aside and wrote
    # a fresh one over its name. Held without read share, or with nothing shared, the file is left as
    # it is and the node's round is skipped, said so; nothing is moved aside.
    $marker = [System.IO.File]::ReadAllText($f8Path)
    foreach ($share in @([System.IO.FileShare]::Delete, [System.IO.FileShare]::None)) {
        $held = [System.IO.File]::Open($f8Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
        try { $rounds = @(Invoke-HordeHubServe -Nodes @(Entry -Transport $null -TransportError "no transport") -Root $f8 -Hub $hub -Contract $contract -Rounds 1 -IntervalMs 0 -TimeoutMs 30000) } finally { $held.Dispose() }
        Check (@($rounds[0].outcomes | Where-Object { $_ -clike "*held open*left as it is*" }).Count -eq 1) ("a mirror held open (share " + $share + ") is left as it is, and the round says so (" + ($rounds[0].outcomes -join " | ") + ")")
        Check (@(Get-ChildItem -LiteralPath $f8 -File -Filter "*.bad-*").Count -eq 1 -and [System.IO.File]::ReadAllText($f8Path) -ceq $marker) "and nothing is moved aside or written over it"
    }

    # HELD IS A SHARING VIOLATION, NOTHING ELSE (re-review of PR #88, F1): any access or I/O failure
    # was read as "held open by another process", so a mirror its ACL denied was skipped every round
    # under that wrong reason (probe P7acl: 3 of 3 rounds). Only ERROR_SHARING_VIOLATION or
    # ERROR_LOCK_VIOLATION is held; anything else is refused, naming its own cause, and left as it is.
    $none = [System.IO.File]::Open($f8Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
    try { $r = Read-HordeHubMirror -Path $f8Path -DeviceId $device -Contract $contract } finally { $none.Dispose() }
    Check ($r.state -ceq "unknown" -and $r.held -eq $true -and $r.refused -eq $false) "CONTROL: a mirror held with no sharing reads as held, not refused"
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $denyRule = New-Object System.Security.AccessControl.FileSystemAccessRule($me, "ReadData", "Deny")
    $acl = Get-Acl -LiteralPath $f8Path
    $acl.AddAccessRule($denyRule)
    Set-Acl -LiteralPath $f8Path -AclObject $acl
    try {
        $r = Read-HordeHubMirror -Path $f8Path -DeviceId $device -Contract $contract
        $rounds = @(Invoke-HordeHubServe -Nodes @(Entry -Transport $null -TransportError "no transport") -Root $f8 -Hub $hub -Contract $contract -Rounds 1 -IntervalMs 0 -TimeoutMs 30000)
    } finally {
        $acl = Get-Acl -LiteralPath $f8Path
        [void]$acl.RemoveAccessRule($denyRule)
        Set-Acl -LiteralPath $f8Path -AclObject $acl
    }
    Check ($r.state -ceq "unknown" -and $r.held -eq $false -and $r.refused -eq $true) ("a mirror its ACL denies is refused, not held (held=" + $r.held + ", refused=" + $r.refused + ")")
    $deniedOut = @($rounds[0].outcomes | Where-Object { $_ -clike "*its mirror could not be opened:*denied*left as it is*" })
    Check ($deniedOut.Count -eq 1 -and @($rounds[0].outcomes | Where-Object { $_ -clike "*held open*" }).Count -eq 0) ("and the round names that cause, never 'held open' (" + ($rounds[0].outcomes -join " | ") + ")")
    Check (@(Get-ChildItem -LiteralPath $f8 -File -Filter "*.bad-*").Count -eq 1 -and [System.IO.File]::ReadAllText($f8Path) -ceq $marker) "and the denied mirror is neither moved aside nor written over"

    # A MOVE ASIDE THAT FAILS IS SAID, NOT THROWN (re-review of PR #88, F2): a reader sharing read but
    # not delete lets the hub read the bad file and refuses the rename. The round says the copy could
    # not be kept aside; it is never a bare failure that hides why.
    [System.IO.File]::WriteAllText($f8Path, "garbage held by a reader")
    $reader = [System.IO.File]::Open($f8Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try { $rounds = @(Invoke-HordeHubServe -Nodes @(Entry -Transport $null -TransportError "no transport") -Root $f8 -Hub $hub -Contract $contract -Rounds 1 -IntervalMs 0 -TimeoutMs 30000) } finally { $reader.Dispose() }
    Check (@($rounds[0].outcomes | Where-Object { $_ -clike "*could not be kept aside*" }).Count -eq 1) ("a mirror that cannot be renamed aside is said so (" + ($rounds[0].outcomes -join " | ") + ")")
    Check ([System.IO.File]::ReadAllText($f8Path) -ceq "garbage held by a reader" -and @(Get-ChildItem -LiteralPath $f8 -File -Filter "*.bad-*").Count -eq 1) "CONTROL: the rename really failed: the file is where it was, and no new copy is aside"
    [System.IO.File]::WriteAllText($f8Path, $marker)

    # KEPT ASIDE, BUT NOT WITHOUT END (review of PR #88): a mirror unreadable round after round left one
    # more copy each round (5 rounds, 5 copies). The newest three are kept; older ones are removed, said so.
    foreach ($i in 1..5) {
        [System.IO.File]::WriteAllText($f8Path, ("garbage " + $i))
        $rounds = @(Invoke-HordeHubServe -Nodes @(Entry -Transport $null -TransportError "no transport") -Root $f8 -Hub $hub -Contract $contract -Rounds 1 -IntervalMs 0 -TimeoutMs 30000)
        Start-Sleep -Milliseconds 20
    }
    $kept = @(Get-ChildItem -LiteralPath $f8 -File -Filter "*.bad-*" | Sort-Object Name)
    Check ($kept.Count -eq 3) ("five unreadable rounds keep the newest three copies aside, not six (" + $kept.Count + ")")
    Check ($kept.Count -ge 1 -and [System.IO.File]::ReadAllText($kept[-1].FullName) -ceq "garbage 5") "the newest copy is the last one moved aside"
    Check (@($rounds[0].outcomes | Where-Object { $_ -clike "*older cop*removed*" }).Count -eq 1) ("and the round says older copies were removed (" + ($rounds[0].outcomes -join " | ") + ")")

    Write-Host ""
    Write-Host "--- one hub at a time (issue #87, F9) ---" -ForegroundColor Cyan
    $f9 = Join-Path $work "f9"
    $f9Mirror = Join-Path $f9 "mirror"
    New-Item -ItemType Directory -Path $f9Mirror | Out-Null
    $lockPath = Join-Path $f9 "serve.lock"
    Check ((Get-HordeHubLockPath -Root $f9Mirror) -ceq $lockPath) "the run lock is <hub>\serve.lock, beside the mirror folder"
    $held = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    $busy = ""
    try { $null = Invoke-HordeHubServe -Nodes @(Entry -Transport $null -TransportError "no transport") -Root $f9Mirror -Hub $hub -Contract $contract -Rounds 1 -IntervalMs 0 -TimeoutMs 30000 } catch { $busy = $_.Exception.Message } finally { $held.Dispose() }
    Check ($busy -clike "*another horde hub serve is running*") ("while another hub holds the run lock, hub serve refuses to start (" + $busy + ")")
    Check (@(Get-ChildItem -LiteralPath $f9Mirror -File).Count -eq 0) "and writes no mirror"
    $rounds = @(Invoke-HordeHubServe -Nodes @(Entry -Transport $null -TransportError "no transport") -Root $f9Mirror -Hub $hub -Contract $contract -Rounds 1 -IntervalMs 0 -TimeoutMs 30000)
    Check ($rounds.Count -eq 1 -and @(Get-ChildItem -LiteralPath $f9Mirror -File).Count -eq 1) "CONTROL: with the lock free, the same call runs its round"
    $again = $null; try { $again = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None) } catch { } finally { if ($null -ne $again) { $again.Dispose() } }
    Check ($null -ne $again) "and it lets the lock go when it returns"
    # TWO HUBS, NOT A HUB AND A STRANGER (re-review of PR #88, F2): the check above holds the lock with
    # no sharing itself, which refuses any second open whatever share the hub asks for. Here the first
    # holder is the hub's own Enter-HordeHubLock. Sharing is decided per handle, the same within one
    # process as across two (a lock taken this way refused 7 of 8 processes in the review's probe).
    $first = Enter-HordeHubLock -Path $lockPath
    $busy = ""
    try { $null = Invoke-HordeHubServe -Nodes @(Entry -Transport $null -TransportError "no transport") -Root $f9Mirror -Hub $hub -Contract $contract -Rounds 1 -IntervalMs 0 -TimeoutMs 30000 } catch { $busy = $_.Exception.Message } finally { $first.Dispose() }
    Check ($busy -clike "*another horde hub serve is running*") ("while one hub holds the run lock, a second hub is refused (" + $busy + ")")
    $second = $null; try { $second = Enter-HordeHubLock -Path $lockPath } finally { if ($null -ne $second) { $second.Dispose() } }
    Check ($null -ne $second) "CONTROL: once the first hub lets it go, the second takes it"
    $denied = Join-Path $f9 "denied"
    New-Item -ItemType Directory -Path (Join-Path $denied "serve.lock") -Force | Out-Null
    $other = ""
    try { $null = Invoke-HordeHubServe -Nodes @() -Root (Join-Path $denied "mirror") -Hub $hub -Contract $contract -Rounds 1 -IntervalMs 0 } catch { $other = $_.Exception.Message }
    Check ($other -clike "*the hub's run lock could not be opened*" -and $other -cnotlike "*another horde hub serve*") ("a lock that cannot be opened for another reason says so, never 'busy' (" + $other + ")")

    Write-Host ""
    Write-Host "--- one slow node does not hold the round (issue #87, F10) ---" -ForegroundColor Cyan
    $slowDev = "1b4e28ba-2fa1-4d3b-a3f5-ef19b5a7633b"
    $slowRoot = Join-Path $work "f10"
    $slow = Start-Node -At $slowDev -ViewDelayMs 8000
    $fast = Start-Node
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $rounds = @(Invoke-HordeHubServe -Nodes @((Entry -Expect $slowDev -At $slowDev), (Entry)) -Root $slowRoot -Hub $hub -Contract $contract -Rounds 1 -IntervalMs 0 -TimeoutMs 30000 -NodeBudgetMs 3000)
    $sw.Stop()
    $null = Stop-Node $slow
    $null = Stop-Node $fast
    $outs = @($rounds[0].outcomes)
    Check (@($outs | Where-Object { $_ -clike ("*(" + $slowDev + "): unreachable: *past its 3 s bound*") }).Count -eq 1) ("a node slower than its bound is cut off at the bound (" + ($outs -join " | ") + ")")
    # A failure a few ms short of the deadline is the bound's: a wait cut to the bound can end there,
    # the clock moving in steps (remote run c2-dial, 2026-10-07: "no frame within 2767 ms" on 3 s).
    $edge = [pscustomobject]@{ deadline = [datetime]::UtcNow.AddMilliseconds(20); seconds = 3 }
    Check ((Get-HordeHubPastBound -Bound $edge -Reason "no frame") -clike "*past its 3 s bound: no frame") "a step that fails 20 ms before the deadline is said as the bound"
    $early = [pscustomobject]@{ deadline = [datetime]::UtcNow.AddMilliseconds(5000); seconds = 3 }
    Check ((Get-HordeHubPastBound -Bound $early -Reason "no frame") -ceq "no frame") "CONTROL: one that fails seconds before it is said as itself"
    Check (@($outs | Where-Object { $_ -clike ("*(" + $device + "): heard, 2 session(s)*") }).Count -eq 1) "the node after it is still pulled in the same round"
    Check ($sw.Elapsed.TotalSeconds -lt 7) ("and the round took " + [math]::Round($sw.Elapsed.TotalSeconds, 1) + " s, not the slow node's 8 s plus the rest")
    $slow = Start-Node -At $slowDev -ViewDelayMs 3000
    $rounds = @(Invoke-HordeHubServe -Nodes @((Entry -Expect $slowDev -At $slowDev)) -Root $slowRoot -Hub $hub -Contract $contract -Rounds 1 -IntervalMs 0 -TimeoutMs 30000 -NodeBudgetMs 15000)
    $null = Stop-Node $slow
    Check (@($rounds[0].outcomes | Where-Object { $_ -clike "*heard, 2 session(s)*" }).Count -eq 1) ("CONTROL: the same slow node inside a bound it fits is heard (" + ($rounds[0].outcomes -join " | ") + ")")

    # OPENING COUNTS AGAINST THE BOUND (re-review of PR #88, F2): the open is the first wait of a node's
    # part, so it is asked to wait no longer than the bound has left, not the 15 s open timeout.
    $asked = @{ ms = -1 }
    $slowOpen = $mem.PSObject.Copy()
    $slowOpen.open = { param($Endpoint, $TimeoutMs) $asked.ms = $TimeoutMs; throw ("no node answered within " + $TimeoutMs + " ms") }.GetNewClosure()
    $null = @(Invoke-HordeHubServe -Nodes @(Entry -Transport $slowOpen) -Root $slowRoot -Hub $hub -Contract $contract -Rounds 1 -IntervalMs 0 -TimeoutMs 30000 -NodeBudgetMs 2000)
    Check ($asked.ms -gt 0 -and $asked.ms -le 2000) ("with a 2 s bound, the open is asked to wait at most 2000 ms (" + $asked.ms + ")")
    $asked.ms = -1
    $null = @(Invoke-HordeHubServe -Nodes @(Entry -Transport $slowOpen) -Root $slowRoot -Hub $hub -Contract $contract -Rounds 1 -IntervalMs 0 -TimeoutMs 30000 -NodeBudgetMs 0)
    Check ($asked.ms -eq 15000) ("CONTROL: with no bound, the same open is asked to wait its own 15000 ms (" + $asked.ms + ")")

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
