# DOES THE HUB ASK A NODE TO ACT ONCE PER REQUEST, KEEP WHAT IT ANSWERED, AND CLOSE BY WHAT IT KEPT?
#
# cli/HubAct.ps1 (the act path's A4). The hub's side of session.spawn, session.close and request.status
# over one link each, against cli/NodeServe.ps1's real loop on the in-process memory transport, with a
# fixture act on the node side that counts itself (test/fixtures/node-serve/serve-peer.ps1). Proven:
#   - a spawn is answered with the node's journal entry, and the hub's record keeps it;
#   - the same request sent again (same id, same issue time) is answered from the node's journal and
#     the node acts once;
#   - a close is built from the process the spawn's answer named;
#   - a node that cannot be reached leaves the request "unknown", never refused or done.
# The real CLI over the real local pipe is transports/local/test/test-hub-act-local.ps1.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "Platform", "Namespace")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "transports\Port.ps1")
foreach ($t in @(Get-HordeTransportFiles)) { . $t }
. (Join-Path $root "remote\NodeServe.ps1")
. (Join-Path $root "cli\NodeServe.ps1")
. (Join-Path $root "cli\HubAct.ps1")

$fxs = Join-Path $root "test\fixtures\node-serve"
$device = "0f8fad5b-d9cb-469f-a165-70867728950e"
$contract = Get-HordeLinkContract
$hub = [pscustomobject]@{ id = "7c9e6679-7425-40de-944b-e07fc1f90ae7"; name = "fixture-hub"; hordeVersion = "0.1.0" }
$entry = [pscustomobject]@{ deviceId = $device; endpoint = $device; transport = (Get-HordeTransport -Name "memory"); transportError = "" }
function Start-ActNode {
    param([string]$Outcome = "done", [string]$Journal, [int]$Links = 1)
    $ready = New-Object System.Threading.ManualResetEventSlim($false)
    $counter = [hashtable]::Synchronized(@{ views = 0; acts = 0 })
    $ps = [PowerShell]::Create()
    [void]$ps.AddCommand((Join-Path $fxs "serve-peer.ps1")).AddParameter("Root", $root).AddParameter("Endpoint", $device).AddParameter("ViewPath", (Join-Path $fxs "view.json")).AddParameter("JournalRoot", $Journal).AddParameter("MaxLinks", $Links).AddParameter("Counter", $counter).AddParameter("Ready", $ready).AddParameter("ActOutcome", $Outcome)
    $h = $ps.BeginInvoke()
    $up = $ready.Wait(30000)
    return [pscustomobject]@{ ps = $ps; h = $h; counter = $counter; up = $up }
}
function Stop-ActNode { param($Node) if ($Node.h.AsyncWaitHandle.WaitOne(40000)) { try { $null = $Node.ps.EndInvoke($Node.h) } catch { } } else { try { $Node.ps.Stop() } catch { } }; $Node.ps.Dispose() }
$spawnArgs = [pscustomobject][ordered]@{ label = "E"; role = "orc"; runId = "20261005-120000-act"; profile = "alpha"; repoId = "github.com/example/app"; prompt = [pscustomobject]@{ text = "read the plan" }; closeOn = "proof"; title = "client search orc"; permission = "bypass" }

$jr = Join-Path $env:TEMP ("horde-hub-act-" + [guid]::NewGuid().ToString("N"))
$acts = Join-Path $env:TEMP ("horde-hub-acts-" + [guid]::NewGuid().ToString("N"))
Initialize-HordeJournal -Root $jr -Kind "request" | Out-Null
try {
Write-Host ""
Write-Host "--- a spawn, answered and kept; sent again, acted on once ---" -ForegroundColor Cyan
$node = Start-ActNode -Journal $jr -Links 3
Check ($node.up -eq $true) "the node is listening, serving acts"
$rid = New-HordeLinkFrameId
$issued = Get-HordeLinkTime
$r1 = Invoke-HordeHubAct -Entry $entry -Hub $hub -Contract $contract -Verb "session.spawn" -Arguments $spawnArgs -RequestId $rid -IssuedAt $issued -TimeoutMs 30000
Check ($r1.answered -and "$($r1.result.state)" -ceq "known" -and "$($r1.result.value.state)" -ceq "done" -and "$($r1.result.value.sessionId)" -ceq "aaaaaaaa-1111-4222-8333-444444444444") "the node's answer arrives: done, with the session it started"
$line = Format-HordeHubActAnswer -Res $r1 -RequestId $rid
Check ($line -clike "DONE session.spawn request $rid session aaaaaaaa-1111-4222-8333-444444444444 pid 4242 procStart 134350994347710308*") ("the person reads what was done, the session and its process (" + $line + ")")
$rec = [pscustomobject][ordered]@{ requestId = $rid; verb = "session.spawn"; deviceId = $device; issuedAt = $issued; args = $spawnArgs; answer = $r1.result.value; error = $null; sentAt = @($issued) }
Write-HordeHubActRecord -Dir $acts -Record $rec
$r2 = Invoke-HordeHubAct -Entry $entry -Hub $hub -Contract $contract -Verb "session.spawn" -Arguments $spawnArgs -RequestId $rid -IssuedAt $issued -TimeoutMs 30000
Check ($r2.answered -and "$($r2.result.value.state)" -ceq "done" -and [int]$node.counter["acts"] -eq 1) ("sent again with the same id and issue time, it is answered from the node's journal: the node acted once (" + $node.counter["acts"] + ")")
$st = Invoke-HordeHubAct -Entry $entry -Hub $hub -Contract $contract -Verb "request.status" -Arguments ([pscustomobject]@{ requestId = $rid }) -RequestId (New-HordeLinkFrameId) -IssuedAt (Get-HordeLinkTime) -TimeoutMs 30000
Check ($st.answered -and "$($st.result.value.state)" -ceq "done" -and "$($st.result.value.sessionId)" -ceq "aaaaaaaa-1111-4222-8333-444444444444") "request.status reports the spawn's outcome"
Stop-ActNode $node

Write-Host ""
Write-Host "--- a close is built from the process the spawn's answer named ---" -ForegroundColor Cyan
$sp = Find-HordeHubSpawn -Dir $acts -SessionId "aaaaaaaa-1111-4222-8333-444444444444"
Check ($sp.state -eq "known" -and $sp.value.answer.expect.pid -eq 4242 -and "$($sp.value.answer.expect.procStart)" -ceq "134350994347710308" -and "$($sp.value.answer.expect.ns.device)" -ceq $device) "the hub finds the spawn that started the session, with its process and namespace"
Check ((Find-HordeHubSpawn -Dir $acts -SessionId "bbbbbbbb-1111-4222-8333-444444444444").state -eq "absent") "a session the hub did not start is absent: there is nothing to close it by"
Write-HordeHubActRecord -Dir $acts -Record ([pscustomobject][ordered]@{ requestId = (New-HordeLinkFrameId); verb = "session.spawn"; deviceId = $device; issuedAt = $issued; args = $spawnArgs; answer = $r1.result.value; error = $null; sentAt = @() })
Check ((Find-HordeHubSpawn -Dir $acts -SessionId "aaaaaaaa-1111-4222-8333-444444444444").state -eq "unknown") "two records claiming one session are unknown, never one picked"

Write-Host ""
Write-Host "--- a node that cannot be reached leaves the request unknown ---" -ForegroundColor Cyan
$gone = Invoke-HordeHubAct -Entry ([pscustomobject]@{ deviceId = $device; endpoint = "11111111-2222-4333-8444-555555555555"; transport = (Get-HordeTransport -Name "memory"); transportError = "" }) -Hub $hub -Contract $contract -Verb "session.spawn" -Arguments $spawnArgs -RequestId (New-HordeLinkFrameId) -IssuedAt (Get-HordeLinkTime) -TimeoutMs 3000
Check (-not $gone.answered -and $gone.reason -like "*could not open a link*") "no listener: the request is unanswered, with the reason"
Check ((Format-HordeHubActAnswer -Res $gone -RequestId "x") -clike "UNKNOWN request x:*") "and the person reads UNKNOWN, never refused or done"
$none = Invoke-HordeHubAct -Entry ([pscustomobject]@{ deviceId = $device; endpoint = $device; transport = $null; transportError = "no such transport" }) -Hub $hub -Contract $contract -Verb "session.spawn" -Arguments $spawnArgs -RequestId (New-HordeLinkFrameId) -IssuedAt (Get-HordeLinkTime)
Check (-not $none.answered -and $none.reason -like "*no transport*") "a node with no transport is unanswered, with the reason"
$bad = Invoke-HordeHubAct -Entry $entry -Hub $hub -Contract $contract -Verb "session.deliver" -Arguments $spawnArgs -RequestId (New-HordeLinkFrameId) -IssuedAt (Get-HordeLinkTime)
Check (-not $bad.answered -and $bad.reason -like "*does not send session.deliver*") "the hub sends only the act verbs of this step and request.status"
} finally {
    foreach ($d in @($jr, $acts)) { if ((Split-Path -Leaf $d) -match '^horde-hub-acts?-[0-9a-f]{32}$') { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}

Complete-HordeSuite -Success "the hub asks a node to act once per request, keeps what it answered, and closes by what it kept"
