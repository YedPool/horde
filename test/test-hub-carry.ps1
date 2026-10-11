# DOES THE HUB CARRY `horde session`'S REQUESTS TO A NODE THAT DIALS IN, ONCE EACH, AND WRITE BACK WHAT THE
# NODE ANSWERED - AND NEVER SEND ONE BLIND, NOR TO A NODE IT NO LONGER ADMITS?
#
# Mesh v1, remote plan R19 over R17c (cli/HubCarry.ps1). A node behind NAT dials the hub; the hub, after
# its pull on that link, sends every act request written down for the node and writes each answer into
# the request's record. The rules attacked here, each with its control:
#   - one link carries any number of sessions: twelve spawns on one dialled link, twelve sessions;
#   - the node's own daily cap refuses a spawn above it, and the refusal comes back, never sent again;
#   - a request id sent again is answered from the node's journal and acted on once; the same id with
#     other arguments is refused by the node;
#   - an answer lost mid-spawn (a partition) leaves the request UNKNOWN; the next link asks
#     request.status and settles it from the node's journal, never sending the spawn again;
#   - a request the node never recorded (absent) is sent again under the same id, and acted on once;
#   - a device revoked mid-carry is cut before its next request; what was never sent is refused BY
#     THE HUB, what was sent is left for the node to say;
#   - only records marked dialled, for this device, still waiting, are carried; one that cannot be
#     read is said and skipped;
#   - `horde session` resolves a node in the hub's register, refuses an unknown or revoked one before
#     anything is written, and queues for a live one; `horde nodes` marks each live dialled node
#     with its enrolment (Get-HordeHubListedNodes, the one listing).
#
# Without a server or a pipe: both ends on the in-process memory transport, the node in a second
# runspace (test/fixtures/node-serve/dial-peer.ps1) acting through the REAL act path over the fakes of
# test/fixtures/node-serve/act-world.ps1. No terminal, no harness. The same path over a real transport
# listener and the real CLI is that transport's own machine-bound test-mesh-act-local.ps1.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "Platform", "Namespace", "ReadShared", "FileAtomic", "Schema", "ListenAddress")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "transports\Port.ps1")
foreach ($t in @(Get-HordeTransportFiles)) { . $t }
. (Join-Path $root "remote\NodeServe.ps1")
. (Join-Path $root "remote\Mirror.ps1")
. (Join-Path $root "remote\Journal.ps1")
. (Join-Path $root "cli\NodeServe.ps1")
. (Join-Path $root "cli\HubServe.ps1")
. (Join-Path $root "cli\HubRegistry.ps1")
. (Join-Path $root "test\lib\Cli.ps1")

$fx = Join-Path $root "test\fixtures\node-serve"
$viewPath = Join-Path $fx "view.json"
$device = "0f8fad5b-d9cb-469f-a165-70867728950e"
$other = "9b2e4c1a-3f5d-4e6a-8b7c-0d1e2f3a4b5c"
$hubId = "7c9e6679-7425-40de-944b-e07fc1f90ae7"
$hub = [pscustomobject]@{ id = $hubId; name = "fixture-hub"; hordeVersion = "0.1.0" }
$contract = Get-HordeLinkContract
$mem = Get-HordeTransport -Name "memory"
$work = Join-Path $env:TEMP ("horde-hub-carry-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$admitDevice = { param($D) if ($D -ceq $device) { return "" } return ("device " + $D + " is not enrolled in this fixture") }

function New-NodeHome {
    # A node home with a policy naming the fixture repository and profile; -Cap, when not -1, its daily cap.
    param([int]$Cap = -1)
    $h = Join-Path $work ("node-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    $clone = Join-Path $h "code\app"
    New-Item -ItemType Directory -Path $clone, (Join-Path $h "node") -Force | Out-Null
    $capText = ""; if ($Cap -ge 0) { $capText = ', "dailySpawnCap": ' + $Cap }
    [System.IO.File]::WriteAllText((Join-Path $h "node\policy.json"), ('{ "schemaVersion": 1, "repos": [ { "repoId": "github.com/example/app", "path": "' + $clone.Replace([string][char]92, ([string][char]92) * 2) + '" } ], "profiles": ["alpha"]' + $capText + ' }'))
    $j = Join-Path $h "node\requests"
    Initialize-HordeJournal -Root $j -Kind "request" | Out-Null
    return [pscustomobject]@{ home = $h; journal = $j }
}
function Start-Dialler {
    # The node's dialling loop in a second runspace, acting through the real act path; it dials at once.
    param([string]$HubEndpoint, $NodeHome, [int]$MaxDials = 1, [int]$ActDelayMs = 0, $Counter)
    $ps = [PowerShell]::Create()
    [void]$ps.AddCommand((Join-Path $fx "dial-peer.ps1")).AddParameter("Root", $root).AddParameter("HubEndpoint", $HubEndpoint).AddParameter("DeviceId", $device).AddParameter("ViewPath", $viewPath).AddParameter("Preamble", ("horde-attach 1 " + $device)).AddParameter("MaxDials", $MaxDials).AddParameter("IdleTimeoutMs", 20000).AddParameter("JournalRoot", $NodeHome.journal).AddParameter("ActWorldHome", $NodeHome.home).AddParameter("ActDelayMs", $ActDelayMs).AddParameter("IntervalMs", 200).AddParameter("Counter", $Counter)
    return [pscustomobject]@{ ps = $ps; h = $ps.BeginInvoke() }
}
function Stop-Dialler {
    param($Node)
    $out = $null
    if ($Node.h.AsyncWaitHandle.WaitOne(60000)) { try { $out = @($Node.ps.EndInvoke($Node.h)) } catch { Write-Host ("         node side: " + $_.Exception.Message) -ForegroundColor Red } } else { try { $Node.ps.Stop() } catch { } }
    foreach ($e in @($Node.ps.Streams.Error)) { Write-Host ("         node side error: " + $e) -ForegroundColor DarkYellow }
    $Node.ps.Dispose()
    return (@($out | Where-Object { $null -ne $_ -and $null -ne $_.PSObject.Properties["dials"] }) | Select-Object -First 1)
}
function Invoke-Rounds {
    # The hub's serve loop for -Rounds rounds against a node that dials -MaxDials times: { outs; node; acts }.
    param($NodeHome, [string]$ActDir, [int]$Rounds = 1, [int]$MaxDials = 1, [int]$IntervalMs = 3000, [int]$WindowMs = 3000, [int]$ActDelayMs = 0, [int]$ActTimeoutMs = 30000, $Admit = $admitDevice)
    $ep = "hub-carry-" + [guid]::NewGuid().ToString("N").Substring(0, 12)
    $l = Start-HordeTransportListener -Transport $mem -Endpoint $ep
    if ($l.state -cne "known") { throw ("the test hub could not listen: " + $l.reason) }
    $count = [hashtable]::Synchronized(@{ acts = 0 })
    $mr = Join-Path $work ("mirror-" + [guid]::NewGuid().ToString("N").Substring(0, 6))
    try {
        $node = Start-Dialler -HubEndpoint $ep -NodeHome $NodeHome -MaxDials $MaxDials -ActDelayMs $ActDelayMs -Counter $count
        $served = @(Invoke-HordeHubServe -Nodes @() -Root $mr -Hub $hub -Contract $contract -Rounds $Rounds -IntervalMs $IntervalMs -DialWindowMinMs $WindowMs -TimeoutMs 20000 -Listener $l.value -Admit $Admit -ActDir $ActDir -ActTimeoutMs $ActTimeoutMs)
        $nd = Stop-Dialler $node
    } finally { Stop-HordeTransportListener -Listener $l.value }
    # Every outcome a round reports is one line of text, as hub serve prints them (never an array in one).
    $raw = @($served | ForEach-Object { $_.outcomes })
    return [pscustomobject]@{ outs = @($raw | ForEach-Object { $_ }); lines = (@($raw | Where-Object { $_ -isnot [string] }).Count -eq 0); node = $nd; acts = [int]$count["acts"]; mirror = $mr }
}
function Spawn-Args { param([string]$Label = "E") return [pscustomobject][ordered]@{ label = $Label; role = "orc"; runId = "20261011-120000-carry"; profile = "alpha"; repoId = "github.com/example/app"; prompt = [pscustomobject]@{ text = "read the plan" }; closeOn = "proof"; title = "carried orc"; permission = "edits" } }
function Queue { param([string]$Dir, [string]$Verb, $Arguments, [string]$To = $device, [string]$Id = "") $r = New-HordeHubActRecord -Verb $Verb -DeviceId $To -Arguments $Arguments -Via "dialled"; if ($Id -ne "") { $r.requestId = $Id }; Write-HordeHubActRecord -Dir $Dir -Record $r; return $r }
function Rec { param([string]$Dir, $R) return (Read-HordeHubActRecord -Dir $Dir -RequestId "$($R.requestId)") }
function Labels { param([int]$N) return @(1..$N | ForEach-Object { "A" + $_ }) }

try {
    Write-Host ""
    Write-Host "--- one dialled link carries any number of sessions ---" -ForegroundColor Cyan
    $nh = New-NodeHome
    $acts = Join-Path $work "acts-many"
    $queued = @(Labels 12 | ForEach-Object { Queue $acts "session.spawn" (Spawn-Args $_) })
    $r = Invoke-Rounds -NodeHome $nh -ActDir $acts
    $recs = @($queued | ForEach-Object { Rec $acts $_ })
    $done = @($recs | Where-Object { "$($_.answer.state)" -ceq "done" -and "$($_.answer.sessionId)" -ne "" })
    $sids = @($done | ForEach-Object { "$($_.answer.sessionId)" } | Sort-Object -Unique)
    Check ($done.Count -eq 12 -and $sids.Count -eq 12) ("twelve spawns written down for the node are twelve sessions, each with its own id (" + $done.Count + " done, " + $sids.Count + " ids; " + (($r.outs | Select-Object -Last 3) -join " | ") + ")")
    Check ($null -ne $r.node -and $r.node.dials -eq 1 -and $r.node.served -eq 1) ("all twelve on ONE link the node dialled (" + "$($r.node.dials) dial(s), $($r.node.served) link(s)" + ")")
    Check ($r.acts -eq 12 -and @($queued | Where-Object { (Get-HordeJournalEntry -Root $nh.journal -Id $_.requestId).state -ceq "known" }).Count -eq 12) ("the node acted twelve times and journaled twelve requests (" + $r.acts + " acts)")
    Check (@($r.outs | Where-Object { $_ -clike ("*(" + $device + "): DONE session.spawn request *") }).Count -eq 12) "the round says each one, under the node it went to"
    Check ($r.lines) "and each is one line of text, as hub serve prints it"
    Check (@($recs | Where-Object { @($_.sentAt).Count -eq 1 }).Count -eq 12) "each record says it was sent once"
    $m = Read-HordeHubMirror -Path (Get-HordeHubMirrorPath -Root $r.mirror -DeviceId $device) -DeviceId $device -Contract $contract
    Check ($m.state -ceq "known" -and $null -ne (Get-HordeLinkProp $m.value "inventory")) "CONTROL: the pull before the carry still wrote the node's mirror"
    # The next round has nothing to carry: every request is settled.
    $r2 = Invoke-Rounds -NodeHome $nh -ActDir $acts
    Check ($r2.acts -eq 0 -and @($r2.outs | Where-Object { $_ -clike "*session.spawn request*" }).Count -eq 0) ("a settled request is never carried again (" + $r2.acts + " acts)")

    Write-Host ""
    Write-Host "--- a close goes by the process the spawn's answer named ---" -ForegroundColor Cyan
    $sp = Find-HordeHubSpawn -Dir $acts -SessionId $sids[0]
    Check ($sp.state -ceq "known") "the hub finds the carried spawn that started the session"
    $cq = Queue $acts "session.close" (New-HordeHubCloseArgs -Spawn $sp.value -Reason "done with it")
    $r3 = Invoke-Rounds -NodeHome $nh -ActDir $acts
    $c = Rec $acts $cq
    Check ("$($c.answer.state)" -ceq "done" -and "$($c.answer.sessionId)" -ceq $sids[0] -and $r3.acts -eq 1) ("the close is carried and done, for that session (" + "$($c.answer.state) $($c.answer.reason)$($c.error.reason)" + ")")
    $bad = New-HordeHubCloseArgs -Spawn $sp.value
    $bad.expect.procStart = "134000000000000001"
    $cb = Queue $acts "session.close" $bad
    $null = Invoke-Rounds -NodeHome $nh -ActDir $acts
    $cbr = Rec $acts $cb
    Check ("$($cbr.answer.state)" -cne "done" -and ("$($cbr.answer.state)$($cbr.error.code)") -ne "") ("CONTROL: a close naming another start time than the node's view is not done (" + "$($cbr.answer.state): $($cbr.answer.reason)$($cbr.error.reason)" + ")")

    Write-Host ""
    Write-Host "--- the node's own daily cap: a spawn above it is refused by the node, and never sent again ---" -ForegroundColor Cyan
    $capped = New-NodeHome -Cap 2
    $acts = Join-Path $work "acts-cap"
    # Their ids sort AGAINST the order they were issued in, so only the issue order puts them in line.
    $ids = @("cccccccc-1111-4222-8333-444444444444", "bbbbbbbb-1111-4222-8333-444444444444", "aaaaaaaa-1111-4222-8333-444444444444")
    $three = @(0..2 | ForEach-Object { $x = Queue $acts "session.spawn" (Spawn-Args ("C" + ($_ + 1))) $device $ids[$_]; Start-Sleep -Milliseconds 20; $x })
    $r = Invoke-Rounds -NodeHome $capped -ActDir $acts
    $st = @($three | ForEach-Object { "$((Rec $acts $_).answer.state)" })
    Check (($st -join ",") -ceq "done,done,refused") ("with a cap of 2, the first two are done and the third refused (" + ($st -join ",") + ")")
    $third = Rec $acts $three[2]
    Check ("$($third.answer.reason)" -clike "*daily spawn cap of 2 is reached*") ("and its record keeps the node's reason (" + $third.answer.reason + ")")
    Check (@($r.outs | Where-Object { $_ -clike "*REFUSED session.spawn request $($three[2].requestId)*daily spawn cap*" }).Count -eq 1) "the round says it was refused, and why"
    $r2 = Invoke-Rounds -NodeHome $capped -ActDir $acts
    Check ($r2.acts -eq 0 -and @((Rec $acts $three[2]).sentAt).Count -eq 1) ("a refusal is final: the next link sends nothing (" + $r2.acts + " acts)")
    $nocap = New-NodeHome
    $acts = Join-Path $work "acts-nocap"
    $q = @(Labels 3 | ForEach-Object { Queue $acts "session.spawn" (Spawn-Args $_) })
    $null = Invoke-Rounds -NodeHome $nocap -ActDir $acts
    Check (@($q | Where-Object { "$((Rec $acts $_).answer.state)" -ceq "done" }).Count -eq 3) "CONTROL: a policy that names no cap (the default, 32) starts all three"

    Write-Host ""
    Write-Host "--- a record the hub could never send is refused by the hub, and blocks nothing behind it ---" -ForegroundColor Cyan
    $nh = New-NodeHome
    $acts = Join-Path $work "acts-unsendable"
    $badLabel = Queue $acts "session.spawn" (Spawn-Args "C0")
    Start-Sleep -Milliseconds 20
    $badVerb = Queue $acts "session.deliver" (Spawn-Args "X")
    Start-Sleep -Milliseconds 20
    $good = Queue $acts "session.spawn" (Spawn-Args "Y")
    $r = Invoke-Rounds -NodeHome $nh -ActDir $acts
    $b1 = Rec $acts $badLabel; $b2 = Rec $acts $badVerb; $g = Rec $acts $good
    Check ("$($b1.error.reason)" -clike "by the hub, never sent: the link contract refuses the request:*" -and @($b1.sentAt).Count -eq 0) ("arguments the link contract refuses are refused by the hub, never sent (" + $b1.error.reason + ")")
    Check ("$($b2.error.reason)" -clike "by the hub, never sent: the hub does not carry session.deliver*") ("a verb the hub does not carry is refused by the hub (" + $b2.error.reason + ")")
    Check ("$($g.answer.state)" -ceq "done" -and $r.acts -eq 1) ("and the request behind them is carried on the same link (" + "$($g.answer.state)" + ", " + $r.acts + " act)")

    Write-Host ""
    Write-Host "--- a request id sent again is acted on once; the same id with other arguments is refused ---" -ForegroundColor Cyan
    $nh = New-NodeHome
    $acts = Join-Path $work "acts-dup"
    $q1 = Queue $acts "session.spawn" (Spawn-Args "D")
    $null = Invoke-Rounds -NodeHome $nh -ActDir $acts
    $first = Rec $acts $q1
    Check ("$($first.answer.state)" -ceq "done") "CONTROL: the spawn is done"
    # Written down again as waiting, as a resend would be: same id, same issue time, same arguments.
    $again = Rec $acts $q1; $again.answer = $null; $again.sentAt = @()
    Write-HordeHubActRecord -Dir $acts -Record $again
    $r = Invoke-Rounds -NodeHome $nh -ActDir $acts
    $back = Rec $acts $q1
    Check ($r.acts -eq 0 -and "$($back.answer.state)" -ceq "done" -and "$($back.answer.sessionId)" -ceq "$($first.answer.sessionId)") ("sent again, it is answered from the node's journal with the same session, and the node does not act (" + $r.acts + " acts)")
    $reused = Rec $acts $q1; $reused.answer = $null; $reused.sentAt = @(); $reused.args.label = "DD"
    Write-HordeHubActRecord -Dir $acts -Record $reused
    $r = Invoke-Rounds -NodeHome $nh -ActDir $acts
    $rb = Rec $acts $q1
    Check ($r.acts -eq 0 -and "$($rb.error.code)" -ceq "refused" -and "$($rb.error.reason)" -clike "*other arguments*") ("the same id with other arguments is refused by the node, and nothing acts (" + "$($rb.error.code): $($rb.error.reason)" + ")")

    Write-Host ""
    Write-Host "--- an answer lost mid-spawn: unknown, then settled by request.status, never sent blind ---" -ForegroundColor Cyan
    $nh = New-NodeHome
    $acts = Join-Path $work "acts-partition"
    $qp = Queue $acts "session.spawn" (Spawn-Args "P")
    Start-Sleep -Milliseconds 20
    $qn = Queue $acts "session.spawn" (Spawn-Args "R")
    # The node takes 4 s over its first act; the hub waits 1 s for an answer. The node redials after its link ends.
    $r = Invoke-Rounds -NodeHome $nh -ActDir $acts -Rounds 2 -MaxDials 2 -IntervalMs 4000 -ActDelayMs 4000 -ActTimeoutMs 1000
    $pr = Rec $acts $qp
    $nr = Rec $acts $qn
    Check (@($r.outs | Where-Object { $_ -clike "*UNKNOWN*" }).Count -eq 1 -and "$($nr.answer.state)" -ceq "done" -and "$($nr.note)" -eq "" -and @($nr.sentAt).Count -eq 1) ("after a lost answer nothing more goes on that link: the request behind it waits for the next link and is answered there, plainly (" + "$($nr.answer.state) sent " + @($nr.sentAt).Count + "; $($nr.note)" + ")")
    Check (@($r.outs | Where-Object { $_ -clike "*UNKNOWN session.spawn request $($qp.requestId)*never sends it blind*" }).Count -eq 1) ("the lost answer is said UNKNOWN, and that it will not be sent blind (" + (@($r.outs | Where-Object { $_ -clike "*$($qp.requestId)*" }) -join " | ") + ")")
    Check ("$($pr.answer.state)" -ceq "done" -and "$($pr.note)" -clike "*settled from the node's journal*") ("the next link asks request.status and settles it from the node's journal (" + "$($pr.answer.state); $($pr.note)" + ")")
    Check ($r.acts -eq 2 -and @($pr.sentAt).Count -eq 1) ("and the node acted ONCE on it: the spawn was sent once, never again (" + $r.acts + " acts for the two, sent " + @($pr.sentAt).Count + " time(s))")
    Check ($null -ne $r.node -and $r.node.served -eq 2) ("over two links the node dialled (" + "$($r.node.served)" + ")")

    Write-Host ""
    Write-Host "--- a request the node never recorded is sent again under the same id ---" -ForegroundColor Cyan
    $nh = New-NodeHome
    $acts = Join-Path $work "acts-absent"
    $qa = Queue $acts "session.spawn" (Spawn-Args "Q")
    # As a hub that stopped right after writing the send time down leaves it: sent, never received.
    $qa.sentAt = @(Get-HordeLinkTime); Write-HordeHubActRecord -Dir $acts -Record $qa
    $r = Invoke-Rounds -NodeHome $nh -ActDir $acts
    $ar = Rec $acts $qa
    Check (@($r.outs | Where-Object { $_ -clike "*node never recorded session.spawn request $($qa.requestId)*same id*" }).Count -eq 1) "request.status says the node never recorded it, and the hub says it sends it again"
    Check ("$($ar.answer.state)" -ceq "done" -and $r.acts -eq 1 -and @($ar.sentAt).Count -eq 2) ("sent again under the same id, it is done, acted on once (" + $r.acts + " acts, sent " + @($ar.sentAt).Count + " times)")
    Check ((Get-HordeJournalEntry -Root $nh.journal -Id $qa.requestId).state -ceq "known") "and the node's journal holds it under the hub's id"

    Write-Host ""
    Write-Host "--- a status asked for by horde session is a read: carried, its result kept, whatever it is ---" -ForegroundColor Cyan
    $sq = Queue $acts "request.status" ([pscustomobject]@{ requestId = $qa.requestId })
    $nq = Queue $acts "request.status" ([pscustomobject]@{ requestId = "99999999-1111-4222-8333-444444444444" })
    $r = Invoke-Rounds -NodeHome $nh -ActDir $acts
    $s1 = Rec $acts $sq; $s2 = Rec $acts $nq
    Check ("$($s1.result.state)" -ceq "known" -and "$($s1.answer.state)" -ceq "done" -and (Format-HordeHubCarriedRecord -Record $s1) -clike ("DONE session.spawn request " + $qa.requestId + "*")) ("a status of a done request is the node's journal entry, read as the request it names (" + (Format-HordeHubCarriedRecord -Record $s1) + ")")
    Check ("$($s2.result.state)" -ceq "absent" -and -not (Test-HordeHubActPending -Record $s2) -and $r.acts -eq 0) ("a status of a request the node never had is answered absent and settled, nothing acted (" + (Format-HordeHubCarriedRecord -Record $s2) + ")")

    Write-Host ""
    Write-Host "--- the node holds a request with no outcome yet: the hub waits, and never sends it again ---" -ForegroundColor Cyan
    $nh = New-NodeHome
    $acts = Join-Path $work "acts-accepted"
    $qw = Queue $acts "session.spawn" (Spawn-Args "W")
    # As a node that stopped mid-act leaves its journal: the request recorded, no outcome.
    $o = Open-HordeJournalEntry -Root $nh.journal -Id $qw.requestId -Verb "session.spawn" -Arguments $qw.args -IssuedAt ([datetime]::Parse("$($qw.issuedAt)", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal))
    Check ("$($o.decision)" -ceq "act") "CONTROL: the node's journal recorded the request"
    $qw.sentAt = @(Get-HordeLinkTime); Write-HordeHubActRecord -Dir $acts -Record $qw
    $r = Invoke-Rounds -NodeHome $nh -ActDir $acts
    $wr = Rec $acts $qw
    Check (@($r.outs | Where-Object { $_ -clike "*WAITING session.spawn request $($qw.requestId)*no outcome yet*" }).Count -eq 1 -and (Test-HordeHubActPending -Record $wr) -and "$($wr.note)" -clike "*has no outcome for it yet*") ("request.status finds it held with no outcome: the hub says WAITING and keeps it open (" + "$($wr.note)" + ")")
    Check ($r.acts -eq 0 -and @($wr.sentAt).Count -eq 1) ("and sends nothing again: no act, still sent once (" + $r.acts + " acts)")
    # The same held request, written down as never sent: the node's journal cannot say, so it is not
    # acted on, and the hub keeps it open with the node's word for it.
    $wr.sentAt = @(); $wr.note = ""; Write-HordeHubActRecord -Dir $acts -Record $wr
    $r = Invoke-Rounds -NodeHome $nh -ActDir $acts
    $wr2 = Rec $acts $qw
    Check ($r.acts -eq 0 -and (Test-HordeHubActPending -Record $wr2) -and "$($wr2.note)" -clike "the node could not say what happened:*") ("sent to a node that holds it with no outcome, it is not acted on and stays open, saying why (" + "$($wr2.note)" + ")")

    Write-Host ""
    Write-Host "--- revoked mid-carry: cut before its next request; unsent refused BY THE HUB, nothing guessed ---" -ForegroundColor Cyan
    $nh = New-NodeHome
    $acts = Join-Path $work "acts-revoke"
    $four = @(Labels 4 | ForEach-Object { Queue $acts "session.spawn" (Spawn-Args $_) })
    # Admitted at the preamble, before the ping, before the list and before the first two requests;
    # revoked before the third.
    $calls = [hashtable]::Synchronized(@{ n = 0 })
    $revokeAfterFive = { param($D) $calls["n"] = [int]$calls["n"] + 1; if ([int]$calls["n"] -le 5) { return "" } return ("device " + $D + " was revoked at 2026-10-11T00:00:00Z") }
    $r = Invoke-Rounds -NodeHome $nh -ActDir $acts -Admit $revokeAfterFive
    $states = @($four | ForEach-Object { $x = Rec $acts $_; if ($null -ne $x.error) { "hub-" + $x.error.code } else { "$($x.answer.state)" } })
    Check (($states -join ",") -ceq "done,done,hub-refused,hub-refused") ("two carried, the two after the revoke refused by the hub (" + ($states -join ",") + ")")
    Check ($r.acts -eq 2) ("the node acted on two only (" + $r.acts + ")")
    $r3 = Rec $acts $four[2]
    Check ("$($r3.error.reason)" -clike "by the hub, never sent: *no longer admitted*was revoked*" -and @($r3.sentAt).Count -eq 0) ("the refusal says the hub never sent it, and why (" + $r3.error.reason + ")")
    Check ($null -ne $r.node -and "$(@($r.node.endings)[0])" -ceq "closed by the protocol") ("the node was told in a bye (" + "$(@($r.node.endings) -join ' | ')" + ")")
    # Sent, answer lost, then revoked: left for the node to say, never settled by the hub.
    $nh = New-NodeHome
    $acts = Join-Path $work "acts-revoke-sent"
    $qs = Queue $acts "session.spawn" (Spawn-Args "S")
    $qs.sentAt = @(Get-HordeLinkTime); Write-HordeHubActRecord -Dir $acts -Record $qs
    $calls["n"] = 0
    $revokeAfterThree = { param($D) $calls["n"] = [int]$calls["n"] + 1; if ([int]$calls["n"] -le 3) { return "" } return "revoked" }
    $r = Invoke-Rounds -NodeHome $nh -ActDir $acts -Admit $revokeAfterThree
    $sr = Rec $acts $qs
    Check ($null -eq $sr.error -and $null -eq $sr.answer -and $r.acts -eq 0) ("a request already sent is not refused by the hub when the device is revoked: what the node did is the node's to say (" + "$($sr.error.reason)" + ")")
    Check (@($r.outs | Where-Object { $_ -clike "*$($qs.requestId)*" }).Count -eq 0) "and the hub asked it nothing more: not even request.status went on the revoked link"

    Write-Host ""
    Write-Host "--- what is carried: dialled, for this device, still waiting; an unreadable record is said ---" -ForegroundColor Cyan
    $acts = Join-Path $work "acts-filter"
    $mine = Queue $acts "session.spawn" (Spawn-Args "M")
    $theirs = Queue $acts "session.spawn" (Spawn-Args "T") $other
    $direct = New-HordeHubActRecord -Verb "session.spawn" -DeviceId $device -Arguments (Spawn-Args "U"); Write-HordeHubActRecord -Dir $acts -Record $direct
    $answered = Queue $acts "session.spawn" (Spawn-Args "V"); $answered.answer = [pscustomobject]@{ state = "done"; sessionId = "x" }; Write-HordeHubActRecord -Dir $acts -Record $answered
    [System.IO.File]::WriteAllText((Join-Path $acts "torn.json"), "{ torn")
    $q = Get-HordeHubCarryQueue -Dir $acts -DeviceId $device
    Check ((@($q.records | ForEach-Object { "$($_.requestId)" }) -join ",") -ceq $mine.requestId) ("only the waiting dialled request for this device is queued (" + @($q.records).Count + ")")
    Check (@($q.skipped | Where-Object { $_ -clike "*torn.json cannot be read, so it is not carried*" }).Count -eq 1) "a record that cannot be read is said, never carried"
    $renamed = Queue $acts "session.spawn" (Spawn-Args "W")
    Move-Item -LiteralPath (Join-Path $acts ($renamed.requestId + ".json")) -Destination (Join-Path $acts "11111111-2222-4333-8444-555555555555.json")
    $q = Get-HordeHubCarryQueue -Dir $acts -DeviceId $device
    Check (@($q.skipped | Where-Object { $_ -clike "*names request $($renamed.requestId), so it is not carried*" }).Count -eq 1 -and @($q.records).Count -eq 1) "a record under another request's file name is not carried"

    Write-Host ""
    Write-Host "--- which node a request goes to (Resolve-HordeHubActTarget) ---" -ForegroundColor Cyan
    $pulled = @([pscustomobject]@{ deviceId = $hubId; deviceName = "HUBPC" })
    $enr = @([pscustomobject]@{ deviceId = $device; deviceName = "OFFICE1"; live = $true; reason = "" }, [pscustomobject]@{ deviceId = $other; deviceName = "OFFICE2"; live = $false; reason = ("device " + $other + " was revoked at 2026-10-11T00:00:00Z") })
    $t = Resolve-HordeHubActTarget -Target "OFFICE1" -Pulled $pulled -Enrolled $enr
    Check ($t.state -ceq "known" -and $t.value.deviceId -ceq $device -and $t.value.route -ceq "dialled") "an enrolled node, by the name its mirror heard, is dialled"
    $t = Resolve-HordeHubActTarget -Target $device -Pulled $pulled -Enrolled $enr
    Check ($t.state -ceq "known" -and $t.value.route -ceq "dialled") "and by its device id"
    $t = Resolve-HordeHubActTarget -Target "HUBPC" -Pulled $pulled -Enrolled $enr
    Check ($t.state -ceq "known" -and $t.value.route -ceq "pulled") "CONTROL: the hub's own node is pulled"
    $t = Resolve-HordeHubActTarget -Target "OFFICE2" -Pulled $pulled -Enrolled $enr
    Check ($t.state -ceq "unknown" -and $t.reason -clike "*not enrolled live*was revoked*") ("a revoked node is refused, saying why (" + $t.reason + ")")
    $t = Resolve-HordeHubActTarget -Target "NOWHERE" -Pulled $pulled -Enrolled $enr
    Check ($t.state -ceq "unknown" -and $t.reason -clike "*no registered or enrolled node 'NOWHERE'*OFFICE1 ($device, dialled)*") ("an unknown node is refused, listing the known ones (" + $t.reason + ")")
    $twin = @($enr + @([pscustomobject]@{ deviceId = "22222222-3333-4444-8555-666666666666"; deviceName = "OFFICE1"; live = $true; reason = "" }))
    $t = Resolve-HordeHubActTarget -Target "OFFICE1" -Pulled $pulled -Enrolled $twin
    Check ($t.state -ceq "unknown" -and $t.reason -clike "*names 2 nodes*") "a name two nodes answer to is refused, never one picked"
    $t = Resolve-HordeHubActTarget -Target "office1" -Pulled $pulled -Enrolled $enr
    Check ($t.state -ceq "unknown") "names are matched exactly"
    $unnamed = @([pscustomobject]@{ deviceId = $device; deviceName = ""; live = $true; reason = "" })
    Check ((Resolve-HordeHubActTarget -Target "" -Pulled @() -Enrolled $unnamed).state -ceq "unknown") "an empty name never matches a node whose mirror named it nothing"

    Write-Host ""
    Write-Host "--- what the person reads: horde nodes for a heard dialled node; the wait for a carried answer ---" -ForegroundColor Cyan
    $heardRep = [ordered]@{ nodes = @([ordered]@{ deviceId = $device; deviceName = "OFFICE1"; route = "dialled"; heard = [ordered]@{ state = "known"; value = $true }; heardAt = "2026-10-11T12:00:00.000Z"; complete = [ordered]@{ state = "known"; value = $true }; listed = 2; carried = 0; clockFault = [ordered]@{ state = "known"; value = $false }; enrolment = [ordered]@{ expires = "20271011"; address = "192.168.1.156" } }); faults = @() }
    $ht = @(Format-HordeNodesText -Report $heardRep)
    Check ($ht.Count -eq 1 -and $ht[0].Contains("OFFICE1 ($device): heard at") -and $ht[0].EndsWith("[dialled, enrolled until 20271011, from 192.168.1.156]")) ("a heard dialled node's line ends with its enrolment (" + ($ht -join " | ") + ")")
    $wd = Join-Path $work "acts-wait"
    $pend = Queue $wd "session.spawn" (Spawn-Args "Z")
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $w = Wait-HordeHubCarried -Dir $wd -RequestId $pend.requestId -TimeoutMs 600 -PollMs 50
    $sw.Stop()
    Check ($null -ne $w -and (Test-HordeHubActPending -Record $w) -and $sw.ElapsedMilliseconds -ge 550) ("a request still waiting is waited for to the end of the bound, then returned as it is (" + $sw.ElapsedMilliseconds + " ms)")
    $pend.answer = [pscustomobject]@{ state = "done"; sessionId = "x" }; Write-HordeHubActRecord -Dir $wd -Record $pend
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $w = Wait-HordeHubCarried -Dir $wd -RequestId $pend.requestId -TimeoutMs 5000 -PollMs 50
    $sw.Stop()
    Check ($null -ne $w -and "$($w.answer.state)" -ceq "done" -and $sw.ElapsedMilliseconds -lt 2000) ("CONTROL: an answered one is returned at once (" + $sw.ElapsedMilliseconds + " ms)")

    Write-Host ""
    Write-Host "--- horde session and horde nodes, as a user runs them, against the register ---" -ForegroundColor Cyan
    $hh = Join-Path $work "hub-home"
    New-Item -ItemType Directory -Path $hh | Out-Null
    $key = "key-type AAAAC3NzaC1lZDI1NTE5AAAAIOv3m0yS1n1pWz3k8ZQ8ZJ4vK2yM0mW3cE7uY5qX1aBc"
    $null = Add-HordeHubEnrolment -HordeHome $hh -DeviceId $device -Transport "fixture-link" -Key $key -Expires "20991231" -Address "192.168.1.156"
    $null = Add-HordeHubEnrolment -HordeHome $hh -DeviceId $other -Transport "fixture-link" -Key $key -Expires "20991231"
    Check ((Set-HordeHubEnrolmentRevoked -HordeHome $hh -DeviceId $other) -eq "") "CONTROL: the second node is enrolled, then revoked"
    $base = @("session", "spawn", "-Label", "E", "-Run", "20261011-120000-carry", "-Profile", "alpha", "-Repo", "github.com/example/app", "-Prompt", "x", "-Permission", "edits")
    $cr = Invoke-HordeCliProcess -Root $root -HordeArgs @($base + @("-Node", "33333333-2222-4333-8444-555555555555")) -Env @{ HORDE_HOME = $hh }
    Check ($cr.code -ne 0 -and $cr.out -clike "*no registered or enrolled node '33333333-2222-4333-8444-555555555555'*" -and -not (Test-Path -LiteralPath (Join-Path $hh "hub\acts"))) ("an unknown node is refused before anything is written (exit " + $cr.code + ")")
    $cr = Invoke-HordeCliProcess -Root $root -HordeArgs @($base + @("-Node", $other)) -Env @{ HORDE_HOME = $hh }
    Check ($cr.code -ne 0 -and $cr.out -clike "*not enrolled live*was revoked*" -and -not (Test-Path -LiteralPath (Join-Path $hh "hub\acts"))) ("a revoked node is refused before anything is written (exit " + $cr.code + ")")
    $cr = Invoke-HordeCliProcess -Root $root -HordeArgs @($base + @("-Node", $device, "-TimeoutSeconds", "1")) -Env @{ HORDE_HOME = $hh }
    $written = @(Get-ChildItem -LiteralPath (Join-Path $hh "hub\acts") -Filter "*.json" -File -ErrorAction SilentlyContinue)
    $wr = $null; if ($written.Count -eq 1) { $wr = [System.IO.File]::ReadAllText($written[0].FullName) | ConvertFrom-Json }
    Check ($cr.code -eq 0 -and $cr.out -clike "QUEUED session.spawn request * for node $device*dials in*" -and $cr.out -clike "*horde session status -RequestId*") ("a live enrolled node's spawn is queued for the hub to carry, and the person is told how to ask again (" + $cr.out.Trim() + ")")
    Check ($null -ne $wr -and "$($wr.via)" -ceq "dialled" -and "$($wr.deviceId)" -ceq $device -and @($wr.sentAt).Count -eq 0 -and "$($wr.args.permission)" -ceq "edits") "its record is written down, marked dialled, never sent by the CLI"
    $cr = Invoke-HordeCliProcess -Root $root -HordeArgs @("session", "status", "-RequestId", "$($wr.requestId)", "-TimeoutSeconds", "1") -Env @{ HORDE_HOME = $hh }
    Check ($cr.code -eq 0 -and $cr.out -clike "QUEUED session.spawn request $($wr.requestId)*" -and @(Get-ChildItem -LiteralPath (Join-Path $hh "hub\acts") -Filter "*.json" -File).Count -eq 1) ("status of a queued request reads its record, writing nothing more (" + $cr.out.Trim() + ")")
    $wr.answer = [pscustomobject]@{ requestId = $wr.requestId; verb = "session.spawn"; state = "done"; sessionId = "aaaaaaaa-1111-4222-8333-444444444444"; expect = [pscustomobject]@{ ns = [pscustomobject]@{ device = $device; space = "windows" }; pid = 4242; procStart = "134350994347710308" } }
    $wr.sentAt = @(Get-HordeLinkTime)
    Write-HordeHubActRecord -Dir (Join-Path $hh "hub\acts") -Record $wr
    $cr = Invoke-HordeCliProcess -Root $root -HordeArgs @("session", "status", "-RequestId", "$($wr.requestId)", "-TimeoutSeconds", "1") -Env @{ HORDE_HOME = $hh }
    Check ($cr.out -clike "DONE session.spawn request $($wr.requestId) session aaaaaaaa-1111-4222-8333-444444444444 pid 4242*") ("once the hub has carried it, status prints the node's answer (" + $cr.out.Trim() + ")")
    $cr = Invoke-HordeCliProcess -Root $root -HordeArgs @("session", "close", "-SessionId", "aaaaaaaa-1111-4222-8333-444444444444", "-TimeoutSeconds", "1") -Env @{ HORDE_HOME = $hh }
    $closes = @(Get-ChildItem -LiteralPath (Join-Path $hh "hub\acts") -Filter "*.json" -File | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) | ConvertFrom-Json } | Where-Object { "$($_.verb)" -ceq "session.close" })
    Check ($cr.out -clike "QUEUED session.close request * for node $device*" -and $closes.Count -eq 1 -and "$($closes[0].via)" -ceq "dialled" -and [long]$closes[0].args.expect.pid -eq 4242) ("a close of a dialled node's session is queued with the process its spawn named (" + $cr.out.Trim() + ")")
    $nj = Invoke-HordeCliProcess -Root $root -HordeArgs @("nodes", "-Json") -Env @{ HORDE_HOME = $hh }
    $rep = $null; try { $rep = (($nj.out -split "`n") | Where-Object { $_.Trim().StartsWith("{") } | Select-Object -First 1) | ConvertFrom-Json } catch { }
    $dn = @($rep.nodes | Where-Object { "$($_.deviceId)" -ceq $device })
    $on = @($rep.nodes | Where-Object { "$($_.deviceId)" -ceq $other })
    Check ($dn.Count -eq 1 -and "$($dn[0].route)" -ceq "dialled" -and "$($dn[0].enrolment.expires)" -ceq "20991231" -and "$($dn[0].enrolment.address)" -ceq "192.168.1.156" -and "$($dn[0].heard.state)" -ceq "unknown") ("horde nodes lists the enrolled node, dialled, with its enrolment, never heard yet (" + $nj.code + ")")
    Check ($on.Count -eq 0) "and not the revoked one: horde nodes lists what the register holds live (Get-HordeHubListedNodes)"
    Check (@($rep.nodes | Where-Object { "$($_.route)" -ceq "pulled" }).Count -eq 1) "CONTROL: beside the hub's own node, pulled"
    $nt = Invoke-HordeCliProcess -Root $root -HordeArgs @("nodes") -Env @{ HORDE_HOME = $hh }
    Check ($nt.out.Contains("[dialled, enrolled until 20991231, from 192.168.1.156]")) ("and as text, each dialled node's enrolment is said (" + $nt.out.Trim() + ")")
} finally {
    if ((Split-Path -Leaf $work) -match '^horde-hub-carry-[0-9a-f]{32}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

Complete-HordeSuite -Success "the hub carries a dialled node's requests over its link, once each, settles a lost answer by request.status, and sends nothing to a node it no longer admits"
