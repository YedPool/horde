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
    param([string]$Outcome = "done", [string]$Journal, [int]$Links = 1, [int]$DelayMs = 0)
    $ready = New-Object System.Threading.ManualResetEventSlim($false)
    $counter = [hashtable]::Synchronized(@{ views = 0; acts = 0 })
    $ps = [PowerShell]::Create()
    [void]$ps.AddCommand((Join-Path $fxs "serve-peer.ps1")).AddParameter("Root", $root).AddParameter("Endpoint", $device).AddParameter("ViewPath", (Join-Path $fxs "view.json")).AddParameter("JournalRoot", $Journal).AddParameter("MaxLinks", $Links).AddParameter("Counter", $counter).AddParameter("Ready", $ready).AddParameter("ActOutcome", $Outcome).AddParameter("ActDelayMs", $DelayMs)
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
Check ((Format-HordeHubActAnswer -Res $st -RequestId "status-request-of-its-own") -clike ("DONE session.spawn request " + $rid + "*")) "and the person reads the request it was asked about, not the status request's own id"
Stop-ActNode $node

Write-Host ""
Write-Host "--- a close is built from the process the spawn's answer named ---" -ForegroundColor Cyan
$sp = Find-HordeHubSpawn -Dir $acts -SessionId "aaaaaaaa-1111-4222-8333-444444444444"
Check ($sp.state -eq "known" -and $sp.value.answer.expect.pid -eq 4242 -and "$($sp.value.answer.expect.procStart)" -ceq "134350994347710308" -and "$($sp.value.answer.expect.ns.device)" -ceq $device) "the hub finds the spawn that started the session, with its process and namespace"
Write-HordeHubActRecord -Dir $acts -Record ([pscustomobject][ordered]@{ requestId = (New-HordeLinkFrameId); verb = "session.spawn"; deviceId = $device; issuedAt = $issued; args = $spawnArgs; answer = [pscustomobject]@{ state = "refused"; verb = "session.spawn"; sessionId = "cccccccc-1111-4222-8333-444444444444"; reason = "the fixture node refused" }; error = $null; sentAt = @($issued) })
Check ((Find-HordeHubSpawn -Dir $acts -SessionId "cccccccc-1111-4222-8333-444444444444").state -eq "absent") "a spawn the node refused started nothing: there is nothing to close by it"
Check ((Find-HordeHubSpawn -Dir $acts -SessionId "bbbbbbbb-1111-4222-8333-444444444444").state -eq "absent") "a session the hub did not start is absent: there is nothing to close it by"
Write-HordeHubActRecord -Dir $acts -Record ([pscustomobject][ordered]@{ requestId = (New-HordeLinkFrameId); verb = "session.spawn"; deviceId = $device; issuedAt = $issued; args = $spawnArgs; answer = $r1.result.value; error = $null; sentAt = @() })
Check ((Find-HordeHubSpawn -Dir $acts -SessionId "aaaaaaaa-1111-4222-8333-444444444444").state -eq "unknown") "two records claiming one session are unknown, never one picked"

Write-Host ""
Write-Host "--- review of #126: what a close may be sent for, and to whom ---" -ForegroundColor Cyan
$acts2 = Join-Path $env:TEMP ("horde-hub-acts-" + [guid]::NewGuid().ToString("N"))
$ex = [pscustomobject]@{ ns = [pscustomobject]@{ device = $device; space = "windows" }; pid = 4343; procStart = "134350994347710400" }
function Spawned { param([string]$State, [string]$Sid, $Expect) Write-HordeHubActRecord -Dir $acts2 -Record ([pscustomobject][ordered]@{ requestId = (New-HordeLinkFrameId); verb = "session.spawn"; deviceId = $device; issuedAt = $issued; args = $spawnArgs; answer = [pscustomobject]@{ state = $State; verb = "session.spawn"; sessionId = $Sid; expect = $Expect; reason = "x" }; error = $null; sentAt = @($issued) }) }
Spawned "failed" "dddddddd-1111-4222-8333-444444444444" $ex
$f1 = Find-HordeHubSpawn -Dir $acts2 -SessionId "dddddddd-1111-4222-8333-444444444444"
Check ($f1.state -eq "known" -and $f1.value.answer.expect.pid -eq 4343) "a spawn answered failed WITH its process - running at a level not asked, or without its work - can be closed with that process (F1)"
Spawned "failed" "eeeeeeee-1111-4222-8333-444444444444" $null
Check ((Find-HordeHubSpawn -Dir $acts2 -SessionId "eeeeeeee-1111-4222-8333-444444444444").state -eq "absent") "a failed spawn with no process started nothing to close"
Spawned "refused" "ffffffff-1111-4222-8333-444444444444" $ex
Check ((Find-HordeHubSpawn -Dir $acts2 -SessionId "ffffffff-1111-4222-8333-444444444444").state -eq "absent") "a refused spawn is never closable, whatever it carries"
[System.IO.File]::WriteAllText((Join-Path $acts2 "torn.json"), "{ torn")
$f2 = Find-HordeHubSpawn -Dir $acts2 -SessionId "dddddddd-1111-4222-8333-444444444444"
Check ($f2.state -eq "unknown" -and $f2.reason -like "*torn.json cannot be read*") ("a record that cannot be read makes the lookup unknown, naming it: it could be a second claim (" + $f2.reason + ")")
Remove-Item -LiteralPath (Join-Path $acts2 "torn.json")
$regs = @([pscustomobject]@{ deviceId = $device; deviceName = "box" }, [pscustomobject]@{ deviceId = "22222222-3333-4444-8555-666666666666"; deviceName = "laptop" })
$sp1 = $f1.value
Check ((Resolve-HordeHubCloseTarget -Spawn $sp1 -Node "" -Entries $regs).value -ceq $device) "a close goes to the node that started the session"
Check ((Resolve-HordeHubCloseTarget -Spawn $sp1 -Node "box" -Entries $regs).value -ceq $device) "CONTROL: naming that node by name is the same node"
$ct = Resolve-HordeHubCloseTarget -Spawn $sp1 -Node "laptop" -Entries $regs
Check ($ct.state -eq "unknown" -and $ct.reason -like ("*started on node " + $device + "*-Node names laptop (22222222-3333-4444-8555-666666666666)*")) ("a close naming another node is refused by the hub, naming both (" + $ct.reason + ")")

Write-Host ""
Write-Host "--- review of #126: a request the contract refuses is refused by the hub, nothing sent ---" -ForegroundColor Cyan
$badArgs = [pscustomobject][ordered]@{ label = "E"; role = "orc"; runId = "20261005-120000-act"; profile = "alpha"; repoId = "github.com/example/app"; prompt = [pscustomobject]@{ text = "read the plan" }; closeOn = "proof"; permission = "Bypass" }
Check ((Test-HordeHubActArgs -Contract $contract -Verb "session.spawn" -Arguments $badArgs) -ne "") "a permission level the contract does not take is refused by the hub's own check"
Check ((Test-HordeHubActArgs -Contract $contract -Verb "session.spawn" -Arguments $spawnArgs) -eq "") "CONTROL: the good arguments pass it"
$nowhere = [pscustomobject]@{ deviceId = $device; endpoint = "33333333-2222-4333-8444-555555555555"; transport = (Get-HordeTransport -Name "memory"); transportError = "" }
$lr = Invoke-HordeHubAct -Entry $nowhere -Hub $hub -Contract $contract -Verb "session.spawn" -Arguments $badArgs -RequestId (New-HordeLinkFrameId) -IssuedAt (Get-HordeLinkTime) -TimeoutMs 2000
Check ($lr.refusedHere -and -not $lr.answered -and $lr.reason -like "*contract refuses*" -and $lr.reason -notlike "*could not open a link*") ("and Invoke refuses it before opening any link (" + $lr.reason + ")")
Check ((Format-HordeHubActAnswer -Res $lr -RequestId "r9") -clike "REFUSED request r9 (by the hub, nothing sent):*") "the person reads REFUSED, never UNKNOWN with a resend that cannot succeed"

Write-Host ""
Write-Host "--- review of #126: a spawn names its node ---" -ForegroundColor Cyan
. (Join-Path $root "test\lib\Cli.ps1")
$cliHome = Join-Path $env:TEMP ("horde-hub-acts-" + [guid]::NewGuid().ToString("N"))
$cr = Invoke-HordeCliProcess -Root $root -HordeArgs @("session", "spawn", "-Label", "E", "-Run", "20261005-120000-act", "-Profile", "alpha", "-Repo", "github.com/example/app", "-Prompt", "x") -Env @{ HORDE_HOME = $cliHome }
Check ($cr.code -ne 0 -and ("" + $cr.out + $cr.err) -like "*needs -Node*" -and -not (Test-Path -LiteralPath (Join-Path $cliHome "hub\acts"))) ("horde session spawn with no -Node is refused before anything is written (exit " + $cr.code + ")")

$cr = Invoke-HordeCliProcess -Root $root -HordeArgs @("session", "spawn", "-Node", "11111111-2222-4333-8444-555555555555", "-Label", "RS", "-Run", "20261005-120000-act", "-Profile", "alpha", "-Repo", "github.com/example/app", "-Prompt", "x") -Env @{ HORDE_HOME = $cliHome }
Check ($cr.code -ne 0 -and ("" + $cr.out) -like "*the label RS is reserved*" -and -not (Test-Path -LiteralPath (Join-Path $cliHome "hub\acts"))) ("horde session spawn with a reserved label is refused where the hub hands the label out, before anything is written (exit " + $cr.code + ")")

Write-Host ""
Write-Host "--- a spawn whose prompt never became a turn reads FAILED, with why, to a person (issue #214) ---" -ForegroundColor Cyan
$why = "prompt-not-submitted: the line naming the prompt file was typed but never became a turn: no turn holding the typed line reached the session's transcript within 20 s; its input box still held the line, so ONE more Enter was pressed, and no turn came in 10 s more; session s214 is LEFT RUNNING in pane 4242.1.17 at the level asked for: press Enter in that pane, or close it with this process"
$stuck = [pscustomobject]@{ answered = $true; error = $null; reason = ""; result = [pscustomobject]@{ state = "known"; reason = ""; value = [pscustomobject]@{ state = "failed"; verb = "session.spawn"; requestId = "r214"; sessionId = "s214"; expect = [pscustomobject]@{ pid = 5000; procStart = "134000000000005000" }; reason = $why } } }
$said = Format-HordeHubActAnswer -Res $stuck -RequestId "r214"
Check ($said -ceq ("FAILED session.spawn request r214 session s214 pid 5000 procStart 134000000000005000: " + $why)) ("the person reads FAILED, the session, its process and the whole reason, never DONE (" + $said + ")")

Write-Host ""
Write-Host "--- a node that cannot be reached leaves the request unknown ---" -ForegroundColor Cyan
$gone = Invoke-HordeHubAct -Entry ([pscustomobject]@{ deviceId = $device; endpoint = "11111111-2222-4333-8444-555555555555"; transport = (Get-HordeTransport -Name "memory"); transportError = "" }) -Hub $hub -Contract $contract -Verb "session.spawn" -Arguments $spawnArgs -RequestId (New-HordeLinkFrameId) -IssuedAt (Get-HordeLinkTime) -TimeoutMs 3000
Check (-not $gone.answered -and $gone.reason -like "*could not open a link*") "no listener: the request is unanswered, with the reason"
Check ((Format-HordeHubActAnswer -Res $gone -RequestId "x") -clike "UNKNOWN request x:*") "and the person reads UNKNOWN, never refused or done"
$none = Invoke-HordeHubAct -Entry ([pscustomobject]@{ deviceId = $device; endpoint = $device; transport = $null; transportError = "no such transport" }) -Hub $hub -Contract $contract -Verb "session.spawn" -Arguments $spawnArgs -RequestId (New-HordeLinkFrameId) -IssuedAt (Get-HordeLinkTime)
Check (-not $none.answered -and $none.reason -like "*no transport*") "a node with no transport is unanswered, with the reason"
$bad = Invoke-HordeHubAct -Entry $entry -Hub $hub -Contract $contract -Verb "session.deliver" -Arguments $spawnArgs -RequestId (New-HordeLinkFrameId) -IssuedAt (Get-HordeLinkTime)
Check (-not $bad.answered -and $bad.reason -like "*does not send session.deliver*") "the hub sends only the act verbs of this step and request.status"

Write-Host ""
Write-Host "--- the wrong node, and an answer that never arrives ---" -ForegroundColor Cyan
$jr2 = Join-Path $env:TEMP ("horde-hub-act-" + [guid]::NewGuid().ToString("N"))
Initialize-HordeJournal -Root $jr2 -Kind "request" | Out-Null
$slow = Start-ActNode -Journal $jr2 -Links 2 -DelayMs 4000
Check ($slow.up -eq $true) "a second node is listening, slow to act"
$other = Invoke-HordeHubAct -Entry ([pscustomobject]@{ deviceId = "22222222-3333-4444-8555-666666666666"; endpoint = $device; transport = (Get-HordeTransport -Name "memory"); transportError = "" }) -Hub $hub -Contract $contract -Verb "session.spawn" -Arguments $spawnArgs -RequestId (New-HordeLinkFrameId) -IssuedAt (Get-HordeLinkTime)
Check (-not $other.answered -and $other.reason -like "*answered as device $device*" -and [int]$slow.counter["acts"] -eq 0) ("a node answering as another device is refused before anything is asked (" + $other.reason + ")")
$lost = Invoke-HordeHubAct -Entry $entry -Hub $hub -Contract $contract -Verb "session.spawn" -Arguments $spawnArgs -RequestId (New-HordeLinkFrameId) -IssuedAt (Get-HordeLinkTime) -TimeoutMs 1500
Check (-not $lost.answered -and $lost.reason -like "*whether the node acted is unknown*") ("an answer that does not arrive leaves the request unanswered, the node's act unknown (" + $lost.reason + ")")
Stop-ActNode $slow
} finally {
    foreach ($d in @($jr, $jr2, $acts, $acts2, $cliHome)) { if ((Split-Path -Leaf $d) -match '^horde-hub-acts?-[0-9a-f]{32}$') { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}

Complete-HordeSuite -Success "the hub asks a node to act once per request, keeps what it answered, and closes by what it kept"
