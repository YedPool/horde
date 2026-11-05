# IS A NOTICE FROM THE SUPERVISOR OF SERVICES DELIVERED ONLY WHEN THE WARCHIEF'S OWN SESSION TOOK IT (T-0391, slice 6 of 6)?
#
# cli/ServicesTell.ps1 (Send-HordeServiceNotices, Invoke-HordeServiceTellTakenTick), cli/ServicesTend.ps1 (Send-HordeServicePending and
# the pass's look at the awaiting list) and decisions/NoticeTaken.ps1, held without any real messenger, session or service: a stand-in
# messenger and a stand-in seat. The bug: the supervisor counted a post the messenger ACCEPTED as the warchief being told and forgot the
# notice for good; the session may never have been prompted, and nothing asked. The same cure as the routed answers', the doorbell's, the
# photo notice's and the relay-full notice's:
#   - MARK FIRST, THEN POST: an unusable list means no post, a stated reason, and the notice kept waiting.
#   - A KNOWN refusal takes the mark off; an UNKNOWN result keeps it.
#   - POSTED, NOT DELIVERED: only the session's own TAKEN (handed-over, seen) is delivered.
#   - ONE ALARM at takenAlarmSeconds, a re-ask cadence after it (kept across the supervisor's one-process-a-minute passes), and a 7-day
#     give-up with an ALARM.
#   - A RESTART neither posts a second message (same notice id) nor alarms twice (the alarm is in the mark).
#   - Every line the list has reaches the pass's output (the supervisor's lines).
# Its mutation specs: test\mutations\services-tell-taken.psd1 and services-tend-taken.psd1 (and decisions-route-taken.psd1 for the shared
# engine).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }

$work = Join-Path $env:TEMP ("horde-services-tell-taken-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$keepHome = $env:HORDE_HOME
$keepFleet = $env:WEZFLEET_ROOT
$env:WEZFLEET_ROOT = Join-Path $work "no-fleet"
try {
foreach ($f in @("Tristate", "Home", "ModuleSettings", "Heartbeat", "Services", "ServicesFiles", "ServiceHostPort", "SessionSeat", "Device")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "messengers\Port.ps1")
foreach ($f in @("ServicesAct", "ServicesTend", "ServicesTell")) { . (Join-Path $root ("cli\" + $f + ".ps1")) }
. (Join-Path $root "channels\chat\Taken.ps1")
$fx = Join-Path $here "fixtures\services-tell-taken"
# NO REAL MESSENGER IS EVER ASKED: only the folder of this suite's own is registered.
Check (@(Get-HordeMessengerNames).Count -eq 0) "CONTROL: no messenger is loaded until this suite registers its own"

# THE STAND-IN MESSENGER: every post, one record per messageId (idempotent), and an answer this suite chooses.
$script:posts = New-Object System.Collections.ArrayList
$script:postSays = "accepted"
# Ids the messenger already holds: a repost of one answers already-posted with the first copy's stage and wakes nobody, as wezfleet
# does (lib/MailPost.ps1).
$script:held = @{}
$stubPost = {
    param($Message)
    [void]$script:posts.Add($Message)
    $mid = "$($Message.messageId)"
    if ($script:held.ContainsKey($mid) -and $script:postSays -ceq "accepted") {
        return (New-HordeKnown -Value ([pscustomobject]@{ messageId = $mid; stage = "handed-over"; at = [datetime]::UtcNow; reason = "already-posted: already posted; nothing written and nobody woken again" }) -ObservedAt ([datetime]::UtcNow))
    }
    if ($script:postSays -ceq "accepted") { $script:held[$mid] = $true }
    if ($script:postSays -ceq "unknown") { return (New-HordeUnknown -Reason "the stand-in could not tell") }
    return (New-HordeKnown -Value ([pscustomobject]@{ messageId = $mid; stage = $script:postSays; at = [datetime]::UtcNow; reason = $(if ($script:postSays -ceq "held") { "the stand-in refused it" } else { "" }) }) -ObservedAt ([datetime]::UtcNow))
}
# WHAT THE WARCHIEF'S OWN SIDE SAYS OF A POST, BY THE MESSENGER'S ID: nothing is "taken" until a test sets the stage, as the session's own
# hook does. A notice not named keeps no status (absent).
$script:stages = @{}
$script:askedIds = @{}
$stubStatus = {
    param($MessageId)
    $script:askedIds["$MessageId"] = 1 + [int]$script:askedIds["$MessageId"]
    $st = "$($script:stages["$MessageId"])"
    if ($st -ceq "") { return (New-HordeAbsent -Note "the stand-in keeps no status") }
    return (New-HordeKnown -Value ([pscustomobject]@{ messageId = "$MessageId"; stage = $st; at = [datetime]::UtcNow; reason = $(if ($st -ceq "held") { "the stand-in holds it" } else { "" }) }))
}
$null = Register-HordeMessenger -Folder (Join-Path $fx "svctell") -Post $stubPost -Status $stubStatus
$seat = { return (New-HordeKnown -Value ([pscustomobject]@{ sessionId = "warchief-session-1"; pane = "3"; instance = "t1" })) }
# A folder that is not above the suite's homes, so they are not taken for a test's (A TEST'S HOME TELLS NOBODY).
$notTemp = Join-Path $env:TEMP ("horde-services-tell-taken-elsewhere-" + [guid]::NewGuid().ToString("N"))
$t0 = [datetime]::new(2026, 10, 13, 12, 0, 0, [System.DateTimeKind]::Utc)
$pol = [pscustomobject]@{ fromLabel = "SV"; tellWarchief = $true; takenAlarmSeconds = 90; takenAfterAlarmSeconds = 60 }

function New-Home {
    $h = Join-Path $work ("home-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path (Join-Path $h "settings") -Force | Out-Null
    return $h
}
function New-Notice {
    param([string]$Id, [string]$What = "failing", [string]$Kind = "escalate")
    return [pscustomobject]@{ id = $Id; kind = $Kind; text = "ignored: a notice is told by fixed words"; at = $t0; service = "svc"; what = $What }
}
function Send-One {
    # One notice posted at -Sec seconds after t0: the answer of Send-HordeServiceNotices.
    param([string]$Home_, [string]$Id, [double]$Sec = 0)
    return (Send-HordeServiceNotices -Notices @(New-Notice $Id) -HordeHome $Home_ -Policy $pol -Seat $seat -TempRoot $notTemp -Now $t0.AddSeconds($Sec))
}
function Tick {
    # One look at the awaiting list at -Sec seconds after t0, in a new process each time (the supervisor's pass is one): the lines, joined.
    param([string]$Home_, [double]$Sec, [double]$Alarm = 90, [double]$After = 60)
    return (@(Invoke-HordeServiceTellTakenTick -HordeHome $Home_ -Now $t0.AddSeconds($Sec) -AlarmSeconds $Alarm -AfterAlarmSeconds $After) -join " | ")
}
function Get-Marks {
    param([string]$Home_)
    $r = Read-HordeTakenLedgerFile -Path (Join-Path $Home_ "services\tell-taken.json") -What "the services notices" -Noun "notice"
    if ($r.state -cne "known") { return @() }
    return @(@($r.value.awaiting) | ForEach-Object { ConvertFrom-HordeChatTakenMark -Mark $_ })
}
function Marks-Of { param([string]$Home_, [string]$Id) return @(Get-Marks $Home_ | Where-Object { $_.messengerId -ceq $Id }) }
function Posts-Of { param([string]$Id) return @($script:posts.ToArray() | Where-Object { "$($_.messageId)" -ceq $Id }).Count }
function Alarms-In { param([string]$Text) return ([regex]::Matches($Text, "ALARM: services notice")).Count }
function New-Id { return [guid]::NewGuid().ToString() }

Write-Host ""
Write-Host "--- the settings: two numbers a person may tune ---" -ForegroundColor Cyan
$hS = New-Home
$d = (Get-HordeServiceSettings -HordeHome $hS).values
Check ($d.takenAlarmSeconds -eq 90 -and $d.takenAfterAlarmSeconds -eq 300) "takenAlarmSeconds 90 and takenAfterAlarmSeconds 300 by default, the chat's and the doorbell's own"
[System.IO.File]::WriteAllText((Join-Path $hS "settings\services.json"), '{"schemaVersion":1,"settings":{"takenAlarmSeconds":5}}')
$bad = Get-HordeServiceSettings -HordeHome $hS
Check ($bad.state -ceq "refused" -and "$($bad.findings -join ' ')".Contains("takenAlarmSeconds")) ("an alarm limit under 10 s refuses the file, by name (" + ($bad.findings -join " ") + ")")

Write-Host ""
Write-Host "--- BUG: accepted by the messenger is not delivered; the alarm, the re-ask, the restart ---" -ForegroundColor Cyan
$H1 = New-Home
$id1 = New-Id
$s = Send-One $H1 $id1 0
$m = @(Marks-Of $H1 $id1)
Check (@($s.told) -ccontains $id1 -and (Posts-Of $id1) -eq 1 -and $m.Count -eq 1 -and -not $m[0].alarmed) ("BUG: the notice is posted once and sits on the awaiting list (" + ($s.lines -join " ") + $s.problem + ")")
Check ($m.Count -eq 1 -and $m[0].session -ceq "warchief-session-1") "the mark names the warchief's session"
Check ($script:posts[0].messageId -ceq $id1) "the notice id is the one the notice has in its state file"
$l = Tick $H1 0
Check ($l -ceq "" -and $script:askedIds[$id1] -eq 1) ("a first look says nothing, and asks the messenger once (" + $l + ")")
$l = Tick $H1 60
Check ((Alarms-In $l) -eq 0) ("no alarm before takenAlarmSeconds (" + $l + ")")
$l = Tick $H1 100
Check ((Alarms-In $l) -eq 1 -and $l.Contains("NOT TAKEN") -and @(Marks-Of $H1 $id1 | Where-Object { $_.alarmed }).Count -eq 1) ("ONE ALARM once it is not taken in time, kept in the mark (" + $l + ")")
$asks = [int]$script:askedIds[$id1]
$l = Tick $H1 112
Check ((Alarms-In $l) -eq 0 -and [int]$script:askedIds[$id1] -eq $asks) "no second alarm, and (a new process each look) it is not asked again before takenAfterAlarmSeconds"
$l = Tick $H1 170
Check ((Alarms-In $l) -eq 0 -and [int]$script:askedIds[$id1] -eq ($asks + 1) -and (Posts-Of $id1) -eq 1) "after the alarm it is asked again at the cadence, and still posted once"
Check ([System.IO.File]::Exists((Join-Path $H1 "services\tell-taken-asked.txt"))) "when each mark was last asked is kept in the home between passes"
# RESTART: the supervisor posts the same notice again (its state file still holds it); the same home.
$keep = @(Marks-Of $H1 $id1)[0]
$s = Send-One $H1 $id1 240
$m = @(Marks-Of $H1 $id1)
Check (@($s.told) -ccontains $id1 -and $m.Count -eq 1 -and $m[0].postedMs -eq $keep.postedMs -and $m[0].alarmed) "RESTART: the mark keeps its first clock and its alarm"
Check ((Posts-Of $id1) -eq 2 -and @($script:posts | Where-Object { "$($_.messageId)" -cne $id1 }).Count -eq 0 -and $s.lines.Count -eq 0) "RESTART: the notice is posted under the same id (the messenger keeps one message), and no other"
$l = Tick $H1 300
Check ((Alarms-In $l) -eq 0) ("RESTART: no second alarm (" + $l + ")")
# DELIVERED ONLY ON THE TAKEN.
$script:stages[$id1] = "handed-over"
$l = Tick $H1 400
Check ($l.Contains("TAKEN: services notice " + $id1) -and $l.Contains("after the alarm") -and $l.Contains("delivered") -and @(Marks-Of $H1 $id1).Count -eq 0) ("TAKEN is said, after the alarm, and the mark is gone (" + $l + ")")
Check (-not [System.IO.File]::Exists((Join-Path $H1 "services\tell-taken-asked.txt"))) "and the cadence file forgets a notice that is over"
$l = Tick $H1 500
Check ($l -ceq "") ("nothing is said again (" + $l + ")")

Write-Host ""
Write-Host "--- seen is taken too ---" -ForegroundColor Cyan
$H2 = New-Home
$id2 = New-Id
$null = Send-One $H2 $id2 0
$script:stages[$id2] = "seen"
$l = Tick $H2 20
Check ($l.Contains("TAKEN: services notice " + $id2) -and @(Marks-Of $H2 $id2).Count -eq 0) ("TWIN: seen is taken too (" + $l + ")")

Write-Host ""
Write-Host "--- a notice the session already has is delivered in the next look; a full list is said ---" -ForegroundColor Cyan
$H9 = New-Home
$id9 = New-Id
$script:stages[$id9] = "handed-over"
$null = Send-One $H9 $id9 0
$l = Tick $H9 1
Check ($l.Contains("TAKEN: services notice " + $id9) -and @(Marks-Of $H9 $id9).Count -eq 0) ("a notice already taken is delivered at the first look (" + $l + ")")
$H10 = New-Home
$id10 = New-Id
$old = @(1..200 | ForEach-Object { ConvertTo-HordeChatTakenMark -Entry ([pscustomobject]@{ messageId = ("{0:x32}" -f $_); messengerId = ("00000000-0000-4000-8000-{0:x12}" -f $_); postedMs = [long]((Get-HordeDecisionNoticeTakenNowMs -Now $t0) - 1000); from = "00000000000000000000000000000000"; seq = [long]0; alarmed = $false; woken = $false; session = "" }) })
Write-HordeTakenLedgerFile -Path (Join-Path $H10 "services\tell-taken.json") -Ledger ([pscustomobject]@{ awaiting = $old }) -TempPrefix "test"
$s = Send-One $H10 $id10 0
$l = $s.lines -join " | "
Check ($l.Contains("ALARM: services notice 00000000-0000-4000-8000-000000000001") -and $l.Contains("left the awaiting list because it is full") -and @(Marks-Of $H10 $id10).Count -eq 1) ("a full awaiting list gives up its oldest mark WITH a line the caller can say (" + $l + ")")

Write-Host ""
Write-Host "--- ALREADY POSTED with a brand-new mark is never counted as delivered ---" -ForegroundColor Cyan
$H12 = New-Home
$idC = New-Id
$script:held[$idC] = $true
$script:stages[$idC] = "seen"
$s = Send-One $H12 $idC 0
$l = $s.lines -join " | "
Check ($l.Contains("was NOT sent again") -and @(Marks-Of $H12 $idC).Count -eq 0 -and @($s.told) -ccontains $idC) ("the messenger answered already-posted for a mark this pass just wrote: said plainly, no mark, not posted again (" + $l + ")")
$l = Tick $H12 30
Check (-not $l.Contains("TAKEN:") -and (Posts-Of $idC) -eq 1) ("and the next look logs no delivery either (" + $l + ")")
$H13 = New-Home
$idD = New-Id
$null = Send-One $H13 $idD 0
$s = Send-One $H13 $idD 30
Check (@($s.told) -ccontains $idD -and @(Marks-Of $H13 $idD).Count -eq 1 -and ($s.lines -join " ") -notlike "*NOT sent again*") "CONTROL: a repost of a notice already on the list (a restart) keeps its mark and is counted"

Write-Host ""
Write-Host "--- the alarm limit is the setting's ---" -ForegroundColor Cyan
$H3 = New-Home
$id3 = New-Id
$null = Send-One $H3 $id3 0
$l = Tick $H3 40 30
Check ((Alarms-In $l) -eq 1) ("an alarm limit of 30 s alarms at 40 s (" + $l + ")")

Write-Host ""
Write-Host "--- MARK FIRST: a list that cannot be read means no post, the reason said, the notice kept ---" -ForegroundColor Cyan
$H4 = New-Home
$id4 = New-Id
$ledger = Join-Path $H4 "services\tell-taken.json"
New-Item -ItemType Directory -Path (Split-Path -Parent $ledger) -Force | Out-Null
[System.IO.File]::WriteAllText($ledger, "this is not an awaiting list")
$s = Send-One $H4 $id4 0
Check ((Posts-Of $id4) -eq 0 -and @($s.told).Count -eq 0 -and $s.problem.Contains("cannot be awaited")) ("UNUSABLE LIST: nothing is posted, nothing is told, and the reason is given (" + $s.problem + ")")
Remove-Item -LiteralPath $ledger -Force
$s = Send-One $H4 $id4 60
Check ((Posts-Of $id4) -eq 1 -and @($s.told) -ccontains $id4 -and @(Marks-Of $H4 $id4).Count -eq 1) "TWIN: once the list is usable the notice is marked, then posted"
# Through the supervisor's own pending step: the notice stays in its state file.
$H4b = New-Home
$id4b = New-Id
$st = New-HordeServiceState -Name "svc"
$st.notices = @(New-Notice $id4b)
Write-HordeServiceState -State $st -HordeHome $H4b
New-Item -ItemType Directory -Path (Join-Path $H4b "services") -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $H4b "services\tell-taken.json"), "this is not an awaiting list")
$tellAll = { param($Notices, $HordeHome, $Policy) return (Send-HordeServiceNotices -Notices $Notices -HordeHome $HordeHome -Policy $Policy -Seat $seat -TempRoot $notTemp -Now $t0) }
$defs = @([pscustomobject]@{ name = "svc" })
$out = @(Send-HordeServicePending -Definitions $defs -Tools @{ TellAll = $tellAll } -Policy $pol -HordeHome $H4b) -join " | "
Check ((Posts-Of $id4b) -eq 0 -and $out.Contains("wait untold") -and $out.Contains("cannot be awaited") -and @((Read-HordeServiceState -Name "svc" -HordeHome $H4b).value.notices).Count -eq 1) ("PENDING: an unusable list leaves the notice in the state file and says why (" + $out + ")")
Remove-Item -LiteralPath (Join-Path $H4b "services\tell-taken.json") -Force
$out = @(Send-HordeServicePending -Definitions $defs -Tools @{ TellAll = $tellAll } -Policy $pol -HordeHome $H4b) -join " | "
Check ((Posts-Of $id4b) -eq 1 -and @((Read-HordeServiceState -Name "svc" -HordeHome $H4b).value.notices).Count -eq 0 -and $out.Contains("posted (escalate)") -and -not $out.Contains("told (") -and @(Marks-Of $H4b $id4b).Count -eq 1) ("PENDING: posted and awaiting is not 'told'; the notice leaves the state file only now (" + $out + ")")

Write-Host ""
Write-Host "--- the teller's own lines reach the pass ---" -ForegroundColor Cyan
$H14 = New-Home
$st = New-HordeServiceState -Name "svc"
$st.notices = @(New-Notice (New-Id))
Write-HordeServiceState -State $st -HordeHome $H14
Write-HordeTakenLedgerFile -Path (Join-Path $H14 "services\tell-taken.json") -Ledger ([pscustomobject]@{ awaiting = $old }) -TempPrefix "test"
$out = @(Send-HordeServicePending -Definitions $defs -Tools @{ TellAll = $tellAll } -Policy $pol -HordeHome $H14) -join " | "
Check ($out.Contains("left the awaiting list because it is full")) ("PENDING: a mark given up because the list is full is in the pass's lines (" + $out + ")")

Write-Host ""
Write-Host "--- a KNOWN refusal removes the mark; an UNKNOWN result keeps it ---" -ForegroundColor Cyan
$H5 = New-Home
$id5 = New-Id
$script:postSays = "held"
$s = Send-One $H5 $id5 0
Check (@(Marks-Of $H5 $id5).Count -eq 0 -and (Posts-Of $id5) -eq 1 -and @($s.told).Count -eq 0 -and $s.problem.Contains("answered held")) ("REFUSED: a post the messenger refused leaves no mark and is not told (" + $s.problem + ")")
$l = Tick $H5 300
Check ((Alarms-In $l) -eq 0) "and a refused post never alarms 'not taken' for something that was never sent"
$script:postSays = "accepted"
$s = Send-One $H5 $id5 400
Check (@(Marks-Of $H5 $id5).Count -eq 1 -and @($s.told) -ccontains $id5) "TWIN: the next accepted post of the same notice is marked and told"
$H6 = New-Home
$id6 = New-Id
$script:postSays = "unknown"
$s = Send-One $H6 $id6 0
Check (@(Marks-Of $H6 $id6).Count -eq 1 -and @($s.told).Count -eq 0 -and $s.problem.Contains("did not take it")) ("UNKNOWN: a post whose result is not known keeps its mark (it may have landed) and is not counted told (" + $s.problem + ")")
$l = Tick $H6 100
Check ((Alarms-In $l) -eq 1 -and $l.Contains($id6)) ("and, never taken, it alarms (" + $l + ")")
$script:postSays = "accepted"

Write-Host ""
Write-Host "--- GIVE-UP: held for good, and 7 days without a TAKEN, each with an ALARM ---" -ForegroundColor Cyan
$H7 = New-Home
$id7 = New-Id
$null = Send-One $H7 $id7 0
$script:stages[$id7] = "held"
$l = Tick $H7 20
Check ($l.Contains("ALARM:") -and $l.Contains("holds it for good") -and @(Marks-Of $H7 $id7).Count -eq 0) ("HELD: a notice the messenger holds for good alarms and is no longer watched (" + $l + ")")
$H8 = New-Home
$id8 = New-Id
$null = Send-One $H8 $id8 0
$null = Tick $H8 100
$l = Tick $H8 (604800 + 200)
Check ($l.Contains("NOT DELIVERED, given up") -and $l.Contains("ALARM:") -and @(Marks-Of $H8 $id8).Count -eq 0) ("GIVE-UP: a notice not taken in 7 days is given up with an ALARM (" + $l + ")")

Write-Host ""
Write-Host "--- THE PASS: the lines of the look reach the supervisor's own lines ---" -ForegroundColor Cyan
$HP = New-Home
$idP = New-Id
$null = Send-HordeServiceNotices -Notices @(New-Notice $idP) -HordeHome $HP -Policy $pol -Seat $seat -TempRoot $notTemp -Now ([datetime]::UtcNow.AddSeconds(-1000))
$tellTaken = { param($HordeHome, $Policy) return @(Invoke-HordeServiceTellTakenTick -HordeHome $HordeHome -Now ([datetime]::UtcNow) -AlarmSeconds ([double]$Policy.takenAlarmSeconds) -AfterAlarmSeconds ([double]$Policy.takenAfterAlarmSeconds)) }
$passTools = @{ Now = { return [datetime]::UtcNow }; TellTaken = $tellTaken }
$r = Invoke-HordeServiceSupervisor -HordeHome $HP -Tools $passTools
Check ($r.ran -and (Alarms-In ($r.lines -join " | ")) -eq 1) ("the ALARM of a notice not taken is among the pass's lines (" + ($r.lines -join " | ") + ")")
$r = Invoke-HordeServiceSupervisor -HordeHome $HP -Tools $passTools
Check ((Alarms-In ($r.lines -join " | ")) -eq 0) "and the next pass does not say it again"
$script:stages[$idP] = "seen"
$r = Invoke-HordeServiceSupervisor -HordeHome $HP -Tools @{ Now = { return [datetime]::UtcNow }; TellTaken = { param($HordeHome, $Policy) return @(Invoke-HordeServiceTellTakenTick -HordeHome $HordeHome -Now ([datetime]::UtcNow.AddSeconds(400)) -AlarmSeconds 90 -AfterAlarmSeconds 60) } }
Check (($r.lines -join " | ").Contains("TAKEN: services notice " + $idP) -and @(Marks-Of $HP $idP).Count -eq 0) ("and the TAKEN is among them (" + ($r.lines -join " | ") + ")")
# A pass that throws is a failed check, not a broken suite (tools/Mutate.ps1 counts only a failed check as a catch).
try { $boom = Invoke-HordeServiceSupervisor -HordeHome $HP -Tools @{ Now = { return [datetime]::UtcNow }; TellTaken = { param($HordeHome, $Policy) throw "the look fell over" } } }
catch { $boom = [pscustomobject]@{ ran = $false; lines = @("IT THREW: " + $_.Exception.Message) } }
Check ($boom.ran -and ($boom.lines -join " ").Contains("the awaiting notices could not be asked: the look fell over")) "a look that throws costs the look, not the pass"

Write-Host ""
Write-Host "--- a test's home still tells nobody; the quiet pass pays for nothing ---" -ForegroundColor Cyan
$tempTell = Send-HordeServiceNotices -Notices @(New-Notice (New-Id)) -HordeHome $H1 -Policy $pol -Seat { throw "the seat must not be read for a home under the temp folder" }
Check (@($tempTell.told).Count -eq 0 -and $tempTell.problem.Contains("a test's") -and @($tempTell.lines).Count -eq 0) "A TEST'S HOME TELLS NOBODY: refused before any messenger, seat or list is looked for"
Check (-not (Test-HordeServiceTellAwaiting -HordeHome (New-Home))) "a home with no awaiting list has nothing to ask about"
Check (Test-HordeServiceTellAwaiting -HordeHome $H1) "and a home with one has"
}
finally {
    $env:HORDE_HOME = $keepHome
    $env:WEZFLEET_ROOT = $keepFleet
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-HordeSuite -Success "a services notice is delivered only on the warchief's own TAKEN, alarms once when it is not taken in time, is never dropped, and its lines reach the pass"
