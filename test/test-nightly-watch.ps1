# DOES THE NIGHTLY WATCHER HEAR A NIGHT THAT DID NOT RUN? T-0397.
#
# tools/nightly/NightlyWatch.ps1 and the deciding in core/NightlyNet.ps1 (Get-HordeNightlyWatch*): on 2026-11-01 to 11-03 the
# nightly task fired an hour early, the net refused and nobody heard. The watcher is a separate checker, run each morning,
# that judges the night that began yesterday at 22:00 by the evidence on disk and raises it on two channels. The first
# half drives the pure functions; the second drives the REAL script with a temp work folder, a stand-in tell program, a
# stand-in horde script, task XML in a file (never the real scheduler) and -AtTime for the clock.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\NightlyNet.ps1")

# A member read that never raises: a mutant that drops a field must fail a named check, not break the suite.
function G { param($Obj, [string]$Path) return (Get-HordeTestMember -Object $Obj -Path $Path) }
function Joined { param($Obj) return ((@($Obj) | ForEach-Object { "" + $_ }) -join " | ") }

$goodXml = '<?xml version="1.0"?><Task xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"><Triggers><CalendarTrigger><StartBoundary>2026-11-04T22:00:00</StartBoundary><Enabled>true</Enabled><ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay></CalendarTrigger></Triggers><Settings><Enabled>true</Enabled></Settings></Task>'
function Get-XmlWith { param([string]$Boundary = "2026-11-04T22:00:00", [string]$SettingsEnabled = "true", [string]$TriggerEnabled = "true", [bool]$Trigger = $true)
    $t = $(if ($Trigger) { '<Triggers><CalendarTrigger><StartBoundary>' + $Boundary + '</StartBoundary><Enabled>' + $TriggerEnabled + '</Enabled></CalendarTrigger></Triggers>' } else { '<Triggers/>' })
    return ('<?xml version="1.0"?><Task xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">' + $t + '<Settings><Enabled>' + $SettingsEnabled + '</Enabled></Settings></Task>')
}

function RanLog { param([string]$D, [string]$Next)
    return @(($D + "T22:00:05 nightly net " + $D + ": window open, cutoff " + $Next + "T06:15:00, repos a"), ($Next + "T06:20:00 report written: x"), ($Next + "T06:20:30 report sent to M (exit 0)"))
}

Write-Host ""
Write-Host "--- the night to judge: the one that began yesterday at 22:00, by the calendar ---" -ForegroundColor Cyan
$n = Get-HordeNightlyWatchNight -Now ([datetime]"2026-11-04 07:15")
Check ((G $n "date") -ceq "2026-11-03") ("07:15 on 11-04 judges the night of 11-03 (" + (G $n "date") + ")")
Check ((G $n "start") -eq [datetime]"2026-11-03 22:00" -and (G $n "end") -eq [datetime]"2026-11-04 06:30") "it began at 22:00 and ended at 06:30"
Check ((G (Get-HordeNightlyWatchNight -Now ([datetime]"2026-11-02 07:15")) "date") -ceq "2026-11-01") "clock-change night: 07:15 on 11-02 (after the fall-back) judges 11-01, the 25-hour night"
Check ((G (Get-HordeNightlyWatchNight -Now ([datetime]"2026-11-01 07:15")) "date") -ceq "2026-10-31") "and on the 25-hour day itself it judges 10-31"
Check ((G (Get-HordeNightlyWatchNight -Now ([datetime]"2026-03-09 07:15")) "date") -ceq "2026-03-08") "spring forward: 07:15 on 03-09 judges 03-08, the 23-hour night"
Check ((G (Get-HordeNightlyWatchNight -Now ([datetime]"2026-01-01 07:15")) "date") -ceq "2025-12-31") "across a new year"
Check ((G (Get-HordeNightlyWatchNight -Now ([datetime]"2026-03-01 07:15")) "date") -ceq "2026-02-28") "across a month end"
Check ((G (Get-HordeNightlyWatchNight -Now ([datetime]"2026-11-04 05:00")) "date") -ceq "2026-11-02") "before 06:30 last night is still running, so the one before is judged"
Check ((G (Get-HordeNightlyWatchNight -Now ([datetime]"2026-11-04 06:30")) "date") -ceq "2026-11-03") "at 06:30 the night is over"
Check ((Joined (Get-HordeNightlyWatchDates -Date "2026-11-02" -Count 4)) -ceq "2026-11-02 | 2026-11-01 | 2026-10-31 | 2026-10-30") "dates walk back one calendar day at a time across the clock change"
Check (@(Get-HordeNightlyWatchDates -Date "2026-11-02" -Count 14).Count -eq 14) "and as many as asked for"
Check ((Get-HordeNightlyTaskBoundary -Date ([datetime]"2026-11-05") -Hour 7 -Minute 15) -ceq "2026-11-05T07:15:00") "the watch task boundary is 07:15 wall-clock with no offset"
Check ((Get-HordeNightlyTaskBoundary -Date ([datetime]"2026-11-05") -Hour 22) -ceq "2026-11-05T22:00:00") "and the nightly boundary is unchanged"

Write-Host ""
Write-Host "--- every state of a night, from the evidence only ---" -ForegroundColor Cyan
$D = "2026-11-03"
$ran = (RanLog $D "2026-11-04") -join "`n"
$v = Get-HordeNightlyWatchVerdict -Date $D -LogText $ran -ReportNames @("2026-11-03.txt") -ReportText "Nightly net 2026-11-03: 0 newly red across 2 repos. COMPLETE."
Check ((G $v "status") -ceq "RAN" -and (G $v "missed") -eq $false) "RAN: window open, report exists, report sent"
Check ((G $v "incomplete") -eq $false) "and a COMPLETE headline is no note"
$v = Get-HordeNightlyWatchVerdict -Date $D -LogText $ran -ReportNames @("2026-11-03.txt") -ReportText "Nightly net 2026-11-03: 0 newly red across 2 repos. INCOMPLETE: 3 units not run. GUARDS RED in x.`nREPO a"
Check ((G $v "status") -ceq "RAN" -and (G $v "missed") -eq $false -and (G $v "incomplete") -eq $true) "RAN but INCOMPLETE is a note, not a miss"
Check ((G $v "incompleteWhy") -like "INCOMPLETE: 3 units not run.*" -and (G $v "incompleteWhy") -notlike "*GUARDS*") "and it says why in the headline's own words"
$thinText = "Nightly net 2026-11-03: 0 newly red across 2 repos. BELOW THE COVERAGE FLOOR of 90 percent: a/b ran 10 of 476 units (2 percent), a/b ran no guards. INCOMPLETE: 466 units not run.`nREPO a"
$v = Get-HordeNightlyWatchVerdict -Date $D -LogText $ran -ReportNames @("2026-11-03.txt") -ReportText $thinText
Check ((G $v "status") -ceq "TOO FEW" -and (G $v "missed") -eq $true) "a night below the coverage floor is a miss, TOO FEW, though it ran and was told"
Check ((G $v "detail") -like "*a/b ran 10 of 476 units (2 percent)*") ("and it says the numbers (" + (G $v "detail") + ")")
$thinDecision = Get-HordeNightlyWatchDecision -Verdict $v -Streak 1 -State (Read-HordeNightlyWatchState -Text "")
Check ((G $thinDecision "kind") -ceq "alarm") "so it alarms, where a RAN night with a note would not"
$thinMsg = Format-HordeNightlyWatchMessage -Decision $thinDecision -Verdict $v -Lookback 14
Check ((G $thinMsg "founder") -like "*ran too few tests to count as a pass*" -and (G $thinMsg "founder") -notlike "*did not run*") ("the phone says what happened (" + (G $thinMsg "founder") + ")")
$v = Get-HordeNightlyWatchVerdict -Date $D -LogText $ran -ReportNames @("2026-11-03.txt") -ReportText "Nightly net 2026-11-03: x. COMPLETE.`na unit says BELOW THE COVERAGE FLOOR: not the headline"
Check ((G $v "status") -ceq "RAN") "only the headline line counts as below the floor"
$v = Get-HordeNightlyWatchVerdict -Date $D -LogText $ran -ReportNames @("2026-11-03.txt") -ReportText "Nightly net 2026-11-03: x. COMPLETE.`nunit says INCOMPLETE: not the headline"
Check ((G $v "incomplete") -eq $false) "only the headline line counts as INCOMPLETE"
$v = Get-HordeNightlyWatchVerdict -Date "2026-11-01" -LogText ("2026-11-01T21:00:03 nightly net 2026-11-01: window CLOSED, cutoff 2026-11-01T06:15:00, repos a`n2026-11-01T21:00:03 outside the night window (22:00 to 06:30): nothing run") -ReportNames @("2026-11-01-REFUSED.txt")
Check ((G $v "status") -ceq "REFUSED" -and (G $v "missed") -eq $true) "11-01 as it really was: a window CLOSED line at 21:00, a REFUSED file, no report, is REFUSED"
$v = Get-HordeNightlyWatchVerdict -Date "2026-11-01" -LogText "2026-11-01T21:00:03 nightly net 2026-11-01: window CLOSED, x" -ReportNames @()
Check ((G $v "status") -ceq "REFUSED") "a window CLOSED line alone is REFUSED"
$v = Get-HordeNightlyWatchVerdict -Date "2026-11-01" -LogText "" -ReportNames @("2026-11-01-refused.txt")
Check ((G $v "status") -ceq "REFUSED") "a REFUSED file alone is REFUSED"
$v = Get-HordeNightlyWatchVerdict -Date $D -LogText "2026-11-03T22:00:05 nightly net 2026-11-03: window open, x" -ReportNames @("2026-11-03-FAILED.txt")
Check ((G $v "status") -ceq "FAILED" -and (G $v "missed") -eq $true) "FAILED: its report file, and no report"
$v = Get-HordeNightlyWatchVerdict -Date $D -LogText "2026-11-03T22:00:05 nightly net 2026-11-03: window open, x" -ReportNames @("2026-11-03-BUSY.txt")
Check ((G $v "status") -ceq "BUSY" -and (G $v "missed") -eq $true) "BUSY: its report file, and no report"
$v = Get-HordeNightlyWatchVerdict -Date $D -LogText "2026-11-03T22:00:05 nightly net 2026-11-03: window open, x`n2026-11-03T23:00:00 order: a" -ReportNames @()
Check ((G $v "status") -ceq "NOT REPORTED" -and (G $v "missed") -eq $true) "NOT REPORTED: it started, there is no report"
$v = Get-HordeNightlyWatchVerdict -Date $D -LogText "2026-11-02T22:00:05 nightly net 2026-11-02: window open, x`n2026-11-03T06:00:00 report sent to M (exit 0)" -ReportNames @("2026-11-02.txt")
Check ((G $v "status") -ceq "NOT STARTED" -and (G $v "missed") -eq $true) "NOT STARTED: the log has lines for other nights only"
$v = Get-HordeNightlyWatchVerdict -Date $D -LogText "2026-11-03T21:00:00 nightly net 2026-11-03: window CLOSED, x`n2026-11-03T22:00:05 nightly net 2026-11-03: window open, x" -ReportNames @()
Check ((G $v "status") -ceq "NOT REPORTED") "a run that did start is judged by its start, whatever refused earlier"
$tellLog = "2026-11-03T22:00:05 nightly net 2026-11-03: window open, x`n2026-11-04T06:20:00 report written: x`n2026-11-04T06:20:10 the tell to M failed with exit 1 (try 3 of 3), the report is at x"
$v = Get-HordeNightlyWatchVerdict -Date $D -LogText $tellLog -ReportNames @("2026-11-03.txt")
Check ((G $v "status") -ceq "NOT TOLD" -and (G $v "missed") -eq $true -and (G $v "detail") -like "*tell failed*") "NOT TOLD: the report exists, the log has no report sent line, the tell failed"
$v = Get-HordeNightlyWatchVerdict -Date $D -LogText "2026-11-03T22:00:05 nightly net 2026-11-03: window open, x" -ReportNames @("2026-11-03.txt") -PendingCount 3
Check ((G $v "status") -ceq "NOT TOLD" -and (G $v "detail") -like "*3 findings*pending*") "NOT TOLD with pending findings names them"
$v = Get-HordeNightlyWatchVerdict -Date $D -LogText "2026-11-03T22:00:05 nightly net 2026-11-03: window open, x" -ReportNames @("2026-11-03.txt")
Check ((G $v "status") -ceq "NOT TOLD" -and (G $v "detail") -like "*no report sent line*") "NOT TOLD with no sign either way still says so"
$twoNights = "2026-11-02T22:00:05 nightly net 2026-11-02: window open, x`n2026-11-02T23:00:00 order: a`n2026-11-03T22:00:05 nightly net 2026-11-03: window open, x`n2026-11-04T06:20:30 report sent to M (exit 0)"
$v = Get-HordeNightlyWatchVerdict -Date "2026-11-02" -LogText $twoNights -ReportNames @("2026-11-02.txt", "2026-11-03.txt")
Check ((G $v "status") -ceq "NOT TOLD") "a sent line belongs to its own night's run, never to the night before"
$v = Get-HordeNightlyWatchVerdict -Date $D -LogText "" -ReportNames @() -FolderMissing $true
Check ((G $v "status") -ceq "NOT STARTED" -and (G $v "missed") -eq $true -and (G $v "detail") -like "*work folder does not exist*") "a missing work folder is a finding, not silence"
$v = Get-HordeNightlyWatchVerdict -Date $D -LogText "" -ReportNames @()
Check ((G $v "status") -ceq "NOT STARTED" -and (G $v "detail") -like "*holds no log and no report*") "an empty work folder is a finding too"
$v = Get-HordeNightlyWatchVerdict -Date $D -LogText $ran -ReportNames @("2026-11-03.txt") -ReportText "x"
Check (((G $v "detail") -cmatch '^[\x20-\x7E]*$') -and (G $v "detail") -notmatch '["<>;]') "verdict text is plain ASCII with no quote, semicolon or angle bracket"
$vs = @((Get-HordeNightlyWatchVerdict -Date "a" -LogText "" -ReportNames @()), (Get-HordeNightlyWatchVerdict -Date "b" -LogText "" -ReportNames @()), (Get-HordeNightlyWatchVerdict -Date $D -LogText $ran -ReportNames @("2026-11-03.txt")), (Get-HordeNightlyWatchVerdict -Date "d" -LogText "" -ReportNames @()))
Check ((Get-HordeNightlyWatchStreak -Verdicts $vs) -eq 2) "the streak counts the leading missed nights, newest first"
Check ((Get-HordeNightlyWatchStreak -Verdicts @($vs[2], $vs[0])) -eq 0) "and is 0 when the newest ran"

Write-Host ""
Write-Host "--- the scheduled task itself, from injected XML ---" -ForegroundColor Cyan
Check (@(Get-HordeNightlyWatchTaskFindings -TaskXml $goodXml).Count -eq 0) "a good task has no finding"
Check ((Joined (Get-HordeNightlyWatchTaskFindings -TaskXml "")) -like "*missing*") "no XML means the task is missing"
Check ((Joined (Get-HordeNightlyWatchTaskFindings -TaskXml (Get-XmlWith -SettingsEnabled "false"))) -like "*disabled*") "a disabled task is a finding"
Check ((Joined (Get-HordeNightlyWatchTaskFindings -TaskXml (Get-XmlWith -TriggerEnabled "false"))) -like "*trigger*disabled*") "a disabled trigger is a finding"
Check ((Joined (Get-HordeNightlyWatchTaskFindings -TaskXml (Get-XmlWith -Boundary "2026-10-23T21:00:00-05:00"))) -like "*offset*-05:00*") "an offset in the StartBoundary is a finding (the 11-01 cause)"
Check ((Joined (Get-HordeNightlyWatchTaskFindings -TaskXml (Get-XmlWith -Boundary "2026-10-23T21:00:00Z"))) -like "*offset*") "and so is a Z"
Check ((Joined (Get-HordeNightlyWatchTaskFindings -TaskXml (Get-XmlWith -Boundary "2026-10-23T21:00:00+01:00"))) -like "*offset*") "and a positive offset"
Check ((Joined (Get-HordeNightlyWatchTaskFindings -TaskXml (Get-XmlWith -Trigger $false))) -like "*no trigger*") "a task with no trigger is a finding"
Check ((Joined (Get-HordeNightlyWatchTaskFindings -TaskXml "not xml at all")) -like "*could not be parsed*") "unreadable XML is a finding"
Check (@(Get-HordeNightlyWatchTaskFindings -TaskXml (Get-XmlWith -SettingsEnabled "false" -Boundary "2026-10-23T21:00:00-05:00")).Count -eq 2) "two faults are two findings"

Write-Host ""
Write-Host "--- the memory, and what each morning does ---" -ForegroundColor Cyan
$empty = Read-HordeNightlyWatchState -Text ""
Check ((G $empty "problem") -eq $false -and (G $empty "signature") -ceq "") "no memory is the empty state"
$bad = Read-HordeNightlyWatchState -Text "{ this is not json"
Check ((G $bad "problem") -eq $false -and (G $bad "delivered") -eq $false) "corrupt memory is the empty state, not an error"
$miss = Get-HordeNightlyWatchVerdict -Date $D -LogText "" -ReportNames @()
$okv = Get-HordeNightlyWatchVerdict -Date $D -LogText $ran -ReportNames @("2026-11-03.txt")
$incv = Get-HordeNightlyWatchVerdict -Date $D -LogText $ran -ReportNames @("2026-11-03.txt") -ReportText "Nightly net x. INCOMPLETE: 1 units not run."
$a1 = Get-HordeNightlyWatchDecision -Verdict $miss -Streak 1 -State $empty
Check ((G $a1 "kind") -ceq "alarm") "a missed night alarms"
$s1 = Update-HordeNightlyWatchState -Decision $a1 -Verdict $miss -State $empty -Delivered $true
Check ((G $s1 "problem") -eq $true -and (G $s1 "delivered") -eq $true) "and is remembered as a problem that got through"
$a2 = Get-HordeNightlyWatchDecision -Verdict $miss -Streak 1 -State $s1
Check ((G $a2 "kind") -ceq "duplicate") "the same morning does not alarm twice"
$s1b = Update-HordeNightlyWatchState -Decision $a1 -Verdict $miss -State $empty -Delivered $false
Check ((G (Get-HordeNightlyWatchDecision -Verdict $miss -Streak 1 -State $s1b) "kind") -ceq "alarm") "but an alarm that did not get through is sent again"
$miss2 = Get-HordeNightlyWatchVerdict -Date "2026-11-04" -LogText "" -ReportNames @()
$a3 = Get-HordeNightlyWatchDecision -Verdict $miss2 -Streak 2 -State $s1
Check ((G $a3 "kind") -ceq "alarm") "the next morning, still missed, alarms again"
Check ((G $a3 "signature") -cne (G $a1 "signature")) "with a signature of its own (the date and the streak)"
$a3b = Get-HordeNightlyWatchDecision -Verdict $miss -Streak 2 -State $s1
Check ((G $a3b "kind") -ceq "alarm") "the same night with a longer streak alarms again"
$r1 = Get-HordeNightlyWatchDecision -Verdict $okv -Streak 0 -State $s1
Check ((G $r1 "kind") -ceq "recovered") "a night that ran after a problem is a recovery"
$s2 = Update-HordeNightlyWatchState -Decision $r1 -Verdict $okv -State $s1 -Delivered $true
Check ((G $s2 "problem") -eq $false) "said once: the problem is cleared"
Check ((G (Get-HordeNightlyWatchDecision -Verdict $okv -Streak 0 -State $s2) "kind") -ceq "quiet") "and the next ran night is quiet"
$s2b = Update-HordeNightlyWatchState -Decision $r1 -Verdict $okv -State $s1 -Delivered $false
Check ((G $s2b "problem") -eq $true) "a recovery that did not get through is said again next time"
Check ((G (Get-HordeNightlyWatchDecision -Verdict $okv -Streak 0 -State $empty) "kind") -ceq "quiet") "a ran night with no problem before is quiet"
$nt = Get-HordeNightlyWatchDecision -Verdict $incv -Streak 0 -State $empty
Check ((G $nt "kind") -ceq "note" -and (G $nt "problem") -eq $false) "a ran-but-incomplete night is a note and not a problem"
$sn = Update-HordeNightlyWatchState -Decision $nt -Verdict $incv -State $empty -Delivered $true
Check ((G (Get-HordeNightlyWatchDecision -Verdict $incv -Streak 0 -State $sn) "kind") -ceq "duplicate") "and the note is sent once"
Check ((G $sn "problem") -eq $false) "and does not turn into a problem"
$tf = Get-HordeNightlyWatchDecision -Verdict $okv -Streak 0 -TaskFindings @("the scheduled task is disabled") -State $empty
Check ((G $tf "kind") -ceq "alarm" -and (G $tf "problem") -eq $true) "a task finding on a night that ran is an alarm"
$okv2 = Get-HordeNightlyWatchVerdict -Date "2026-11-04" -LogText ((RanLog "2026-11-04" "2026-11-05") -join "`n") -ReportNames @("2026-11-04.txt")
$stf = Update-HordeNightlyWatchState -Decision $tf -Verdict $okv -State $empty -Delivered $true
Check ((G (Get-HordeNightlyWatchDecision -Verdict $okv -Streak 0 -TaskFindings @("the scheduled task is disabled") -State $stf) "kind") -ceq "duplicate") "the same task finding the same morning is not repeated"
Check ((G (Get-HordeNightlyWatchDecision -Verdict $okv2 -Streak 0 -TaskFindings @("the scheduled task is disabled") -State $stf) "kind") -ceq "alarm") "but a task still wrong the next morning alarms again"
$stf2 = Update-HordeNightlyWatchState -Decision $tf -Verdict $okv -State $empty -Delivered $false
Check ((G $stf2 "problem") -eq $true) "a task finding is remembered as a problem even when it did not get through"
Check ((G (Get-HordeNightlyWatchDecision -Verdict $okv2 -Streak 0 -State $stf) "kind") -ceq "recovered") "and once the task is right and the night ran, that is a recovery"

Write-Host ""
Write-Host "--- the texts: plain, one phone line, never a claim of proof ---" -ForegroundColor Cyan
$msg = Format-HordeNightlyWatchMessage -Decision (Get-HordeNightlyWatchDecision -Verdict $miss -Streak 3 -State $empty) -Verdict $miss -Lookback 14
Check ((G $msg "m") -like "*NIGHTLY WATCH 2026-11-03: MISSED, NOT STARTED*" -and (G $msg "m") -like "*3 nights in a row*") "M is told which night, how, and how many nights in a row"
Check ((G $msg "founder") -like "*did not run*2026-11-03*3 nights in a row*" -and (G $msg "founder") -notmatch "`n") "the phone gets one plain line with the same facts"
Check ((G $msg "m") -like "*only says whether a run happened*" -and (G $msg "m") -notmatch '(?i)\b(proves|proved|verified|passed)\b') "the watcher says it only reports whether a run happened"
$bodies = (G $msg "m") + (G $msg "founder")
Check ($bodies -cmatch '^[\x20-\x7E\n]*$' -and $bodies -notmatch '["<>;]') "ASCII with no double quote, semicolon or angle bracket"
$msgLong = Format-HordeNightlyWatchMessage -Decision (Get-HordeNightlyWatchDecision -Verdict $miss -Streak 14 -State $empty) -Verdict $miss -Lookback 14
Check ((G $msgLong "m") -like "*14 nights in a row or more*") "a streak as long as the look-back is said as 'or more'"
$msgR = Format-HordeNightlyWatchMessage -Decision $r1 -Verdict $okv -Prior 3 -Lookback 14
Check ((G $msgR "m") -like "*RECOVERED*3 nights in a row*" -and (G $msgR "founder") -like "*ran again*3 missed nights*") "a recovery says so and how long it was broken"
$msgN = Format-HordeNightlyWatchMessage -Decision $nt -Verdict $incv -Lookback 14
Check ((G $msgN "founder") -ceq "" -and (G $msgN "m") -like "*NOTE for M only, not a miss*INCOMPLETE*") "an incomplete night goes to M only, as a note"
$msgT = Format-HordeNightlyWatchMessage -Decision $tf -Verdict $okv -Lookback 14
Check ((G $msgT "m") -like "*the night ran, but the scheduled task looks wrong*TASK: the scheduled task is disabled*" -and (G $msgT "founder") -like "*scheduled task looks wrong*disabled*") "a task finding on a ran night is told as such"
# The phone sentence is true for each way a night can be missed (T-0397): a night whose tests ran must not be called a night they did not run.
$phoneCases = @(
    @{ status = "NOT STARTED"; log = ""; names = @(); say = "*did not run for the night of 2026-11-03*"; not = "*started*" },
    @{ status = "REFUSED"; log = "2026-11-03T21:00:00 nightly net 2026-11-03: window CLOSED, x"; names = @(); say = "*did not run for the night of 2026-11-03*outside*hours*"; not = "*started but*" },
    @{ status = "BUSY"; log = "2026-11-03T22:00:05 nightly net 2026-11-03: window open, x"; names = @("2026-11-03-BUSY.txt"); say = "*did not run for the night of 2026-11-03*still*"; not = "*started but*" },
    @{ status = "FAILED"; log = "2026-11-03T22:00:05 nightly net 2026-11-03: window open, x"; names = @("2026-11-03-FAILED.txt"); say = "*started on the night of 2026-11-03*failed*"; not = "*did not run*" },
    @{ status = "NOT REPORTED"; log = "2026-11-03T22:00:05 nightly net 2026-11-03: window open, x"; names = @(); say = "*started on the night of 2026-11-03 but did not finish*"; not = "*did not run*" },
    @{ status = "NOT TOLD"; log = "2026-11-03T22:00:05 nightly net 2026-11-03: window open, x"; names = @("2026-11-03.txt"); say = "*ran on the night of 2026-11-03*report did not reach M*"; not = "*did not run*" }
)
foreach ($pc in $phoneCases) {
    $pv = Get-HordeNightlyWatchVerdict -Date $D -LogText $pc.log -ReportNames $pc.names
    $pm = Format-HordeNightlyWatchMessage -Decision (Get-HordeNightlyWatchDecision -Verdict $pv -Streak 1 -State $empty) -Verdict $pv -Lookback 14
    $pf = G $pm "founder"
    Check ((G $pv "status") -ceq $pc.status) ("phone wording: the case really is " + $pc.status)
    Check ($pf -like $pc.say -and $pf -notlike $pc.not -and $pf -like "*Details are with M.") ("phone wording for " + $pc.status + " is true and plain: " + $pf)
    Check ($pf -cmatch '^[\x20-\x7E]*$' -and $pf -notmatch '["<>;]') ("phone wording for " + $pc.status + " is ASCII with no double quote, semicolon or angle bracket")
}

Write-Host ""
Write-Host "--- a NOT REPORTED night and the PC's last boot (T-0397) ---" -ForegroundColor Cyan
# The real shape of 2026-11-04: window open 22:00:02, last line 22:57:17, the PC restarted at 23:02:20, no report.
$killedLog = "2026-11-04T22:00:02 nightly net 2026-11-04: window open, cutoff 2026-11-05T06:15:00, repos a`n2026-11-04T22:57:17 order: a"
function KillVerdict { param($Boot, [string[]]$Names = @()) return (Get-HordeNightlyWatchVerdict -Date "2026-11-04" -LogText $killedLog -ReportNames $Names -BootTime $Boot) }
$kv = KillVerdict ([datetime]"2026-11-04 23:02:20")
Check ((G $kv "status") -ceq "NOT REPORTED" -and (G $kv "detail") -like "*the PC restarted at 23:02 and killed the run*" -and (G $kv "rebootAt") -ceq "23:02") "a boot inside the run says the PC restarted at that time"
$kmsg = Format-HordeNightlyWatchMessage -Decision (Get-HordeNightlyWatchDecision -Verdict $kv -Streak 1 -State $empty) -Verdict $kv -Lookback 14
Check ((G $kmsg "founder") -like "*started on the night of 2026-11-04 but the PC restarted at 23:02 and stopped them*" -and (G $kmsg "founder") -notlike "*did not run*" -and (G $kmsg "m") -like "*the PC restarted at 23:02*") "and the phone and M say so, never 'did not run'"
Check (((G $kmsg "founder") + (G $kmsg "m")) -cmatch '^[\x20-\x7E\n]*$' -and ((G $kmsg "founder") + (G $kmsg "m")) -notmatch '["<>;]') "in plain ASCII with no double quote, semicolon or angle bracket"
Check ((G (KillVerdict ([datetime]"2026-11-05 02:10:00")) "rebootAt") -ceq "02:10") "a boot after midnight, still in the window, counts"
Check ((G (KillVerdict ([datetime]"2026-11-05 06:30:00")) "rebootAt") -ceq "06:30") "and so does a boot at the window's end"
foreach ($b in @("2026-11-04 21:40:00", "2026-11-04 22:00:01", "2026-11-05 06:30:01", "2026-11-05 14:00:00", "2026-11-06 03:00:00")) {
    $nv = KillVerdict ([datetime]$b)
    Check ((G $nv "rebootAt") -ceq "" -and (G $nv "detail") -like "*killed or crashed midway*" -and (G $nv "detail") -notlike "*restarted*") ("a boot at " + $b + " is no evidence for this run and claims no restart")
}
$nv = KillVerdict $null
Check ((G $nv "rebootAt") -ceq "" -and (G $nv "detail") -like "*killed or crashed midway*") "an unknown boot time claims nothing"
$nv = Get-HordeNightlyWatchVerdict -Date "2026-11-04" -LogText $killedLog -ReportNames @()
Check ((G $nv "rebootAt") -ceq "") "and so does leaving the boot time out"
$nv = Get-HordeNightlyWatchVerdict -Date "2026-11-04" -LogText $killedLog -ReportNames @("2026-11-04.txt") -BootTime ([datetime]"2026-11-04 23:02:20")
Check ((G $nv "status") -ceq "NOT TOLD" -and (G $nv "rebootAt") -ceq "" -and (G $nv "detail") -notlike "*restarted*") "a night with a report is not blamed on a restart"
$nv = Get-HordeNightlyWatchVerdict -Date "2026-11-04" -LogText "" -ReportNames @() -BootTime ([datetime]"2026-11-04 23:02:20")
Check ((G $nv "status") -ceq "NOT STARTED" -and (G $nv "rebootAt") -ceq "") "a night that never started is not blamed on a restart"

Write-Host ""
Write-Host "--- two channels, each tried whatever the other did ---" -ForegroundColor Cyan
$said = @()
$seen = @()
$chOk = [pscustomobject]@{ name = "one"; send = { param($r) $true } }; $chOk2 = [pscustomobject]@{ name = "two"; send = { param($r) $true } }
$chBad = [pscustomobject]@{ name = "bad"; send = { param($r) $false } }
$chThrow = [pscustomobject]@{ name = "boom"; send = { param($r) throw "channel down" } }
$chSee = [pscustomobject]@{ name = "see"; send = { param($r) $script:seen = @($r.Keys | ForEach-Object { $_ + "=" + $r[$_] }); $true } }
$sr = Invoke-HordeNightlyWatchSend -Channels @($chOk, $chOk2) -Say { param($l) }
Check ((G $sr "ok") -eq 2 -and (G $sr "allFailed") -eq $false) "both sent"
$sr = Invoke-HordeNightlyWatchSend -Channels @($chBad, $chOk) -Say { param($l) }
Check ((G $sr "ok") -eq 1 -and (G $sr "allFailed") -eq $false) "a failing first channel leaves the second sending"
$sr = Invoke-HordeNightlyWatchSend -Channels @($chThrow, $chOk) -Say { param($l) $script:said += $l }
Check ((G $sr "ok") -eq 1 -and (G $sr "allFailed") -eq $false -and (@($said | Where-Object { $_ -like "*boom threw*channel down*" }).Count -eq 1)) "a channel that throws is a failure, said, and the next still sends"
$sr = Invoke-HordeNightlyWatchSend -Channels @($chOk, $chBad) -Say { param($l) }
Check ((G $sr "ok") -eq 1 -and (G $sr "allFailed") -eq $false) "a failing last channel leaves the first sent"
$sr = Invoke-HordeNightlyWatchSend -Channels @($chBad, $chThrow) -Say { param($l) }
Check ((G $sr "ok") -eq 0 -and (G $sr "allFailed") -eq $true) "all failed only when every one failed"
$sr = Invoke-HordeNightlyWatchSend -Channels @() -Say { param($l) }
Check ((G $sr "allFailed") -eq $false) "no channel attempted is not 'all failed'"
$sr = Invoke-HordeNightlyWatchSend -Channels @($chBad, $chSee) -Say { param($l) }
Check ((Joined $seen) -ceq "bad=False") "a channel is given what the earlier ones did"

# ---------------------------------------------------------------------------------------------------------------
$exe = (Get-Process -Id $PID).Path
$watch = Join-Path $root "tools\nightly\NightlyWatch.ps1"
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-nightly-watch-" + [guid]::NewGuid().ToString("N"))
[void][System.IO.Directory]::CreateDirectory($work)
$secretWord = "SECRET-WORD-" + [guid]::NewGuid().ToString("N")
try {
    $xmlGood = Join-Path $work "good.xml"; [System.IO.File]::WriteAllText($xmlGood, $goodXml)
    $xmlOffset = Join-Path $work "offset.xml"; [System.IO.File]::WriteAllText($xmlOffset, (Get-XmlWith -Boundary "2026-10-23T21:00:00-05:00"))
    $xmlOff = Join-Path $work "disabled.xml"; [System.IO.File]::WriteAllText($xmlOff, (Get-XmlWith -SettingsEnabled "false"))
    $xmlNone = Join-Path $work "no-such-task.xml"
    $secret = Join-Path $work "service.secret"; [System.IO.File]::WriteAllText($secret, $secretWord)
    $script:cnt = 0

    function New-Rig {
        # A work folder, a stand-in tell program and a stand-in horde script that record what they are given.
        param([int]$TellExit = 0, [int]$HordeExit = 0)
        $script:cnt++
        $d = Join-Path $work ("rig" + $script:cnt); $w = Join-Path $d "work"; $s = Join-Path $d "stub"
        [void][System.IO.Directory]::CreateDirectory((Join-Path $w "reports")); [void][System.IO.Directory]::CreateDirectory($s)
        [System.IO.File]::WriteAllText((Join-Path $s "tell.cmd"), "@echo off`r`necho TELL %*>>`"%~dp0rec.txt`"`r`ntype %~6 >>`"%~dp0body.txt`"`r`nexit /b $TellExit`r`n")
        [System.IO.File]::WriteAllText((Join-Path $s "horde.ps1"), "param([string]`$Verb, [string]`$Service, [string]`$SecretFile, [string]`$Text)`r`nAdd-Content -LiteralPath (Join-Path `$PSScriptRoot 'hrec.txt') -Value ('notify ' + `$Service + ' ' + `$SecretFile + ' | ' + `$Text)`r`nexit $HordeExit`r`n")
        return [pscustomobject]@{ work = $w; stub = $s; tell = (Join-Path $s "tell.cmd"); horde = (Join-Path $s "horde.ps1"); rec = (Join-Path $s "rec.txt"); hrec = (Join-Path $s "hrec.txt"); body = (Join-Path $s "body.txt") }
    }
    function Add-Night { param($Rig, [string]$D, [string]$Next, [string]$Headline = "COMPLETE.")
        Add-Content -LiteralPath (Join-Path $Rig.work "nightly.log") -Value (RanLog $D $Next) -Encoding Ascii
        [System.IO.File]::WriteAllText((Join-Path $Rig.work ("reports\" + $D + ".txt")), ("Nightly net " + $D + ": 0 newly red across 2 repos. " + $Headline + "`n"))
    }
    function Invoke-Watch { param($Rig, [string]$At, [string]$Xml = $xmlGood, [bool]$Founder = $false, [string[]]$More = @(), [string]$Boot = "none")
        $a = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $watch, "-WorkRoot", $Rig.work, "-AtTime", $At, "-BootTime", $Boot, "-TellProgram", $Rig.tell, "-HordeScript", $Rig.horde, "-TellRetrySeconds", "0", "-TellTries", "1", "-TaskXmlFile", $Xml)
        if ($Founder) { $a += @("-NoticeService", "nightly-watch", "-NoticeSecretFile", $secret) }
        $o = @(& $exe @a @More)
        return [pscustomobject]@{ code = $LASTEXITCODE; out = ($o -join "`n") }
    }
    function Lines { param([string]$P) if (Test-Path -LiteralPath $P) { return ,@(Get-Content -LiteralPath $P) } else { return ,@() } }
    function AlarmText { param($Rig, [string]$D) $p = Join-Path $Rig.work ("reports\" + $D + "-WATCH.txt"); if (Test-Path -LiteralPath $p) { return [System.IO.File]::ReadAllText($p) } else { return "" } }

    Write-Host ""
    Write-Host "--- the real script: a night that ran is silent ---" -ForegroundColor Cyan
    $rig = New-Rig
    Add-Night $rig "2026-11-03" "2026-11-04"
    $r = Invoke-Watch $rig "2026-11-04 07:15" -Founder $true
    Check ($r.code -eq 0) ("a ran night exits 0 (" + $r.code + ")")
    Check ((Lines $rig.rec).Count -eq 0 -and (Lines $rig.hrec).Count -eq 0) "and tells nobody"
    Check ((AlarmText $rig "2026-11-03") -eq "") "and leaves no alarm file"
    # TWO THIN NIGHTS IN A ROW are a streak of 2: the watcher must read each night's own report, not only the judged one's.
    $thinRig = New-Rig
    $thinLine = "BELOW THE COVERAGE FLOOR of 90 percent: a/b ran 1 of 9 units (11 percent). INCOMPLETE: 8 units not run."
    Add-Night $thinRig "2026-11-01" "2026-11-02"
    Add-Night $thinRig "2026-11-02" "2026-11-03" -Headline $thinLine
    Add-Night $thinRig "2026-11-03" "2026-11-04" -Headline $thinLine
    $r = Invoke-Watch $thinRig "2026-11-04 07:15" -More @("-Plan")
    Check ($r.out -like "*night 2026-11-03 is TOO FEW*streak 2,*") ("two thin nights after a whole one are a streak of 2 (" + $r.out + ")")
    $r = Invoke-Watch $rig "2026-11-04 07:15" -Plan:$false -More @("-Plan")
    Check ($r.code -eq 0 -and $r.out -like "*PLAN night 2026-11-03: RAN*") "-Plan prints the judgement"

    Write-Host ""
    Write-Host "--- the real script: 11-01 as it was, a window CLOSED line at 21:00 and no report ---" -ForegroundColor Cyan
    $rig = New-Rig
    Add-Night $rig "2026-10-31" "2026-11-01"
    Add-Content -LiteralPath (Join-Path $rig.work "nightly.log") -Value @("2026-11-01T21:00:03 nightly net 2026-11-01: window CLOSED, cutoff 2026-11-01T06:15:00, repos a", "2026-11-01T21:00:03 outside the night window (22:00 to 06:30): nothing run") -Encoding Ascii
    [System.IO.File]::WriteAllText((Join-Path $rig.work "reports\2026-11-01-REFUSED.txt"), "NIGHTLY NET 2026-11-01: NOT RUN`n")
    $r = Invoke-Watch $rig "2026-11-02 07:15" -Founder $true
    $alarm = AlarmText $rig "2026-11-01"
    Check ($r.code -eq 0) ("both channels got it, exit 0 (" + $r.code + ")")
    Check ($alarm -like "*NIGHTLY WATCH 2026-11-01: MISSED, REFUSED*" -and $alarm -notlike "*in a row*") "the alarm file names the night and REFUSED, and a single night is not a streak"
    Check ((Lines $rig.rec).Count -eq 1 -and (Lines $rig.rec)[0] -like "*tell M -Kind report -MessageFile*" ) "M was told with the message file"
    $h = Lines $rig.hrec
    Check ($h.Count -eq 1 -and $h[0] -like "notify nightly-watch *service.secret | Nightly tests did not run for the night of 2026-11-01: they were started outside their allowed hours.*") ("the phone line went through horde notify -Service with the secret FILE path (" + ($h -join " / ") + ")")
    $everything = (Get-ChildItem -LiteralPath $rig.work -Recurse -File | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) -join "`n"
    Check ($everything -notlike ("*" + $secretWord + "*") -and $r.out -notlike ("*" + $secretWord + "*")) "the secret's content is never read, logged or sent"
    Check ((Get-Content -LiteralPath (Join-Path $rig.work "nightly-watch.log") -Raw) -notlike "*nightly net 20*: window*" -and (Get-Content -LiteralPath (Join-Path $rig.work "nightly.log") -Raw) -notlike "*watch*") "the watcher keeps to its own log: nightly.log stays the net's evidence"
    $body = (Lines $rig.body) -join " "
    Check ($alarm -like "*the founder phone notice was sent*") "M is told that the phone notice was sent"

    Write-Host ""
    Write-Host "--- the real script: a PC that was off, an empty folder, no folder ---" -ForegroundColor Cyan
    $rig = New-Rig
    $r = Invoke-Watch $rig "2026-11-04 07:15"
    Check ($r.code -eq 0 -and (AlarmText $rig "2026-11-03") -like "*NOT STARTED*holds no log and no report*") "an empty work folder is an alarm, not silence"
    Check ((Lines $rig.rec).Count -eq 1 -and ((AlarmText $rig "2026-11-03") -like "*the founder phone channel is not configured*")) "M is told when the founder channel is off"
    Check ((Lines $rig.hrec).Count -eq 0) "and the phone is not called without a service and a secret file"
    $rig = New-Rig
    Remove-Item -LiteralPath $rig.work -Recurse -Force
    $r = Invoke-Watch $rig "2026-11-04 07:15"
    Check ($r.code -eq 0 -and (AlarmText $rig "2026-11-03") -like "*NOT STARTED*work folder does not exist*") "a work folder that does not exist is an alarm, and the alarm file is still left"
    Check ((Lines $rig.rec).Count -eq 1) "and M is told"

    Write-Host ""
    Write-Host "--- the real script: killed midway, report not told ---" -ForegroundColor Cyan
    $rig = New-Rig
    Add-Night $rig "2026-11-02" "2026-11-03"
    Add-Content -LiteralPath (Join-Path $rig.work "nightly.log") -Value @("2026-11-03T22:00:05 nightly net 2026-11-03: window open, x", "2026-11-03T23:00:00 order: a") -Encoding Ascii
    $r = Invoke-Watch $rig "2026-11-04 07:15"
    Check ((AlarmText $rig "2026-11-03") -like "*MISSED, NOT REPORTED*") "a run killed midway is NOT REPORTED"
    $rig = New-Rig
    Add-Night $rig "2026-11-02" "2026-11-03"
    Add-Content -LiteralPath (Join-Path $rig.work "nightly.log") -Value @("2026-11-03T22:00:05 nightly net 2026-11-03: window open, x", "2026-11-04T06:20:10 the tell to M failed with exit 1 (try 3 of 3), the report is at x") -Encoding Ascii
    [System.IO.File]::WriteAllText((Join-Path $rig.work "reports\2026-11-03.txt"), "Nightly net 2026-11-03: 1 newly red across 2 repos. COMPLETE.`n")
    $sd = Join-Path $rig.work "Fix__Hord"; [void][System.IO.Directory]::CreateDirectory($sd)
    [System.IO.File]::WriteAllText((Join-Path $sd "state.json"), '{ "lastTip": "", "units": {}, "pending": [ "2026-11-03: RED x", "2026-11-03: RED y" ] }')
    $r = Invoke-Watch $rig "2026-11-04 07:15"
    Check ((AlarmText $rig "2026-11-03") -like "*MISSED, NOT TOLD*tell failed*2 findings*pending*") "a report whose tell failed is NOT TOLD, with the pending findings counted"

    Write-Host ""
    Write-Host "--- the real script: ran but INCOMPLETE is a note to M only ---" -ForegroundColor Cyan
    $rig = New-Rig
    Add-Night $rig "2026-11-03" "2026-11-04" "INCOMPLETE: 4 units not run."
    $r = Invoke-Watch $rig "2026-11-04 07:15" -Founder $true
    Check ($r.code -eq 0 -and (Lines $rig.rec).Count -eq 1 -and (Lines $rig.hrec).Count -eq 0) "M hears the note and the phone does not"
    Check ((AlarmText $rig "2026-11-03") -like "*NOTE for M only, not a miss*INCOMPLETE: 4 units not run*") "and it says it is not a miss"
    $r = Invoke-Watch $rig "2026-11-04 08:00" -Founder $true
    Check ((Lines $rig.rec).Count -eq 1) "the same morning does not repeat the note"

    Write-Host ""
    Write-Host "--- the real script: the task itself, even on a night that ran ---" -ForegroundColor Cyan
    foreach ($case in @(@("offset", $xmlOffset, "*offset*"), @("disabled", $xmlOff, "*disabled*"), @("missing", $xmlNone, "*missing*"))) {
        $rig = New-Rig
        Add-Night $rig "2026-11-03" "2026-11-04"
        $r = Invoke-Watch $rig "2026-11-04 07:15" -Xml $case[1] -Founder $true
        Check ($r.code -eq 0 -and (AlarmText $rig "2026-11-03") -like ("*the night ran, but the scheduled task looks wrong*TASK:" + $case[2])) ("a " + $case[0] + " task on a ran night alarms")
        Check ((Lines $rig.rec).Count -eq 1 -and (Lines $rig.hrec).Count -eq 1) ("and reaches M and the phone (" + $case[0] + ")")
    }

    Write-Host ""
    Write-Host "--- the real script: one channel failing leaves the other, all failing is non-zero ---" -ForegroundColor Cyan
    $rig = New-Rig -HordeExit 1
    $r = Invoke-Watch $rig "2026-11-04 07:15" -Founder $true
    Check ($r.code -eq 0 -and (Lines $rig.rec).Count -eq 1) ("the phone failing leaves M sent, exit 0 (" + $r.code + ")")
    Check ((AlarmText $rig "2026-11-03") -like "*founder phone notice FAILED*") "and M is told the phone failed"
    $rig = New-Rig -TellExit 1
    $r = Invoke-Watch $rig "2026-11-04 07:15" -Founder $true
    Check ($r.code -eq 0 -and (Lines $rig.hrec).Count -eq 1) ("M failing leaves the phone sent, exit 0 (" + $r.code + ")")
    $rig = New-Rig -TellExit 1 -HordeExit 1
    $r = Invoke-Watch $rig "2026-11-04 07:15" -Founder $true
    Check ($r.code -eq 3) ("every channel failing exits 3 (" + $r.code + ")")
    Check ((AlarmText $rig "2026-11-03") -like "*MISSED, NOT STARTED*") "and the alarm file is the last resort"
    $r = Invoke-Watch $rig "2026-11-04 07:20" -Founder $true
    Check ($r.code -eq 3 -and (Lines $rig.rec).Count -eq 2) "an alarm that did not get through is tried again at the next run"
    $rig = New-Rig -TellExit 1
    $r = Invoke-Watch $rig "2026-11-04 07:15"
    Check ($r.code -eq 3) "with only M configured, M failing is all failed"

    Write-Host ""
    Write-Host "--- the real script: dedup, a streak, recovery, a corrupt memory ---" -ForegroundColor Cyan
    $rig = New-Rig
    Add-Night $rig "2026-10-31" "2026-11-01"
    $r1 = Invoke-Watch $rig "2026-11-02 07:15"
    $r1b = Invoke-Watch $rig "2026-11-02 07:20"
    Check ((Lines $rig.rec).Count -eq 1) "the same morning alarms once"
    $r2 = Invoke-Watch $rig "2026-11-03 07:15"
    Check ((Lines $rig.rec).Count -eq 2 -and (AlarmText $rig "2026-11-02") -like "*2 nights in a row*") "the next morning, still missed, alarms again and counts two nights in a row"
    $r3 = Invoke-Watch $rig "2026-11-04 07:15"
    Check ((Lines $rig.rec).Count -eq 3 -and (AlarmText $rig "2026-11-03") -like "*3 nights in a row*") "and the third says three"
    Add-Night $rig "2026-11-04" "2026-11-05"
    $r4 = Invoke-Watch $rig "2026-11-05 07:15" -Founder $true
    $rec4 = Lines $rig.rec
    Check ($rec4.Count -eq 4 -and (AlarmText $rig "2026-11-04") -like "*RECOVERED*3 nights in a row*") "a night that ran after three missed says so"
    Check ((Lines $rig.hrec).Count -eq 1 -and (Lines $rig.hrec)[0] -like "*ran again*3 missed nights*") "and tells the phone once"
    Add-Night $rig "2026-11-05" "2026-11-06"
    $r5 = Invoke-Watch $rig "2026-11-06 07:15" -Founder $true
    Check ((Lines $rig.rec).Count -eq 4 -and (Lines $rig.hrec).Count -eq 1) "recovery is said once: the next ran morning is quiet"
    $rig = New-Rig
    [System.IO.File]::WriteAllText((Join-Path $rig.work "watch-state.json"), "{ garbage ][")
    $r = Invoke-Watch $rig "2026-11-04 07:15"
    Check ($r.code -eq 0 -and (Lines $rig.rec).Count -eq 1) "a corrupt memory does not silence the alarm"
    $rig = New-Rig
    [System.IO.File]::WriteAllText((Join-Path $rig.work "watch-state.json"), "")
    $r = Invoke-Watch $rig "2026-11-04 07:15"
    Check ((Lines $rig.rec).Count -eq 1) "nor does an empty one"
    Write-Host ""
    Write-Host "--- the real script: a restart that killed the run is named (T-0397) ---" -ForegroundColor Cyan
    $rig = New-Rig
    Add-Content -LiteralPath (Join-Path $rig.work "nightly.log") -Value @("2026-11-03T22:00:02 nightly net 2026-11-03: window open, cutoff 2026-11-04T06:15:00, repos a", "2026-11-03T22:57:17 order: a") -Encoding Ascii
    $r = Invoke-Watch $rig "2026-11-04 07:15" -Founder $true -Boot "2026-11-03 23:02:20"
    Check ((AlarmText $rig "2026-11-03") -like "*NOT REPORTED*the PC restarted at 23:02 and killed the run*") "M is told the PC restarted at the boot time"
    Check ((Lines $rig.hrec).Count -eq 1 -and (Lines $rig.hrec)[0] -like "*the PC restarted at 23:02*" -and (Lines $rig.hrec)[0] -notlike "*did not run*") "and so is the phone"
    $rig = New-Rig
    Add-Content -LiteralPath (Join-Path $rig.work "nightly.log") -Value @("2026-11-03T22:00:02 nightly net 2026-11-03: window open, cutoff 2026-11-04T06:15:00, repos a", "2026-11-03T22:57:17 order: a") -Encoding Ascii
    $r = Invoke-Watch $rig "2026-11-04 07:15" -Boot "2026-11-04 06:45:00"
    Check ((AlarmText $rig "2026-11-03") -like "*NOT REPORTED*killed or crashed midway*" -and (AlarmText $rig "2026-11-03") -notlike "*restarted*") "a boot after the window is not blamed"


    Write-Host ""
    Write-Host "--- the real script: the dry run writes and sends nothing ---" -ForegroundColor Cyan
    $rig = New-Rig
    $r = Invoke-Watch $rig "2026-11-04 07:15" -More @("-Plan")
    Check ($r.code -eq 0 -and (Lines $rig.rec).Count -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $rig.work "watch-state.json")) -and (AlarmText $rig "2026-11-03") -eq "") "-Plan on a missed night sends nothing and leaves no file"
    Check ($r.out -like "*PLAN night 2026-11-03: NOT STARTED*" -and $r.out -like "*PLAN founder channel: OFF*") "and prints the judgement and the channel state"

    Write-Host ""
    Write-Host "--- the registration, dry ---" -ForegroundColor Cyan
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\nightly\Register-NightlyWatchTask.ps1") -Plan -HordeRoot $root)
    $txt = $o -join "`n"
    Check ($LASTEXITCODE -eq 0 -and $txt -like "*dry run: nothing registered*") ("-Plan registers nothing (" + $LASTEXITCODE + ")")
    Check ($txt -match '<StartBoundary>\d{4}-\d\d-\d\dT07:15:00</StartBoundary>' -and $txt -notmatch 'T07:15:00(Z|[+-]\d\d)') "the boundary is 07:15 with no offset"
    Check ($txt -like "*StartWhenAvailable*" -and $txt -like "*no wake*") "and says it runs when the PC is next on, without waking it"
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\nightly\Register-NightlyWatchTask.ps1") -WhatIf -HordeRoot $root -NoticeService nightly-watch -NoticeSecretFile $secret)
    $txt = $o -join "`n"
    Check ($LASTEXITCODE -eq 0 -and $txt -like "*dry run*" -and $txt -like "*founder phone channel ON*" -and $txt -notlike ("*" + $secretWord + "*")) "-WhatIf registers nothing and shows the channel on, never the secret"
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\nightly\Register-NightlyWatchTask.ps1") -Plan -HordeRoot $root -NoticeService nightly-watch)
    Check ($LASTEXITCODE -ne 0) "a service without its secret file is refused"

    Write-Host ""
    Write-Host "--- T-0460: the watcher also runs at logon (a restart left the PC at the lock screen, 2026-11-10) ---" -ForegroundColor Cyan
    # The real trigger objects, built and read, never registered: New-ScheduledTaskTrigger does not touch the scheduler.
    $tr = @()
    try { $tr = @(New-HordeNightlyWatchTriggers -First ([datetime]"2026-11-12") -UserId "HOST\someone") } catch { Write-Host ("  triggers: " + $_.Exception.Message) }
    $daily = @($tr | Where-Object { $_.CimClass.CimClassName -eq "MSFT_TaskDailyTrigger" })
    $logon = @($tr | Where-Object { $_.CimClass.CimClassName -eq "MSFT_TaskLogonTrigger" })
    Check ($tr.Count -eq 2 -and $daily.Count -eq 1 -and $logon.Count -eq 1) ("two triggers: daily and at logon (" + $tr.Count + ")")
    Check ($daily.Count -eq 1 -and ("" + $daily[0].StartBoundary) -ceq "2026-11-12T07:15:00") "the daily one is 07:15 wall-clock with no offset"
    Check ($logon.Count -eq 1 -and ("" + $logon[0].UserId) -ceq "HOST\someone") "the logon one is for that user only, not every logon"
    Check ($logon.Count -eq 1 -and ("" + $logon[0].Delay) -ceq "PT5M") "and waits 5 minutes after the logon, so the tell can land"
    $refused = $false
    try { [void](New-HordeNightlyWatchTriggers -First ([datetime]"2026-11-12") -UserId "") } catch { $refused = $true }
    Check $refused "no user is refused: a logon trigger for every logon is never built"
    $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\nightly\Register-NightlyWatchTask.ps1") -Plan -HordeRoot $root)
    $txt = $o -join "`n"
    Check ($LASTEXITCODE -eq 0 -and $txt -match 'trigger: at logon of \S+ after PT5M') "-Plan prints the logon trigger it would register"
    Check ($txt -match 'trigger: daily, <StartBoundary>\d{4}-\d\d-\d\dT07:15:00</StartBoundary>') "and the daily trigger, read from the same task object"
    # The morning of 2026-11-11: the 07:15 run never happened, the first logon was 11:12. Run at that logon, the watcher judges
    # the night of 11-10 (not today's), says it did not start and that the PC restarted, and a second logon says nothing new.
    $lr = New-Rig
    Add-Night $lr "2026-11-09" "2026-11-10"
    $r = Invoke-Watch $lr "2026-11-11 11:17" -Boot "2026-11-10 20:32:57"
    Check ($r.code -eq 0 -and (AlarmText $lr "2026-11-10") -like "*NOT STARTED*") ("a logon run at 11:17 judges the night of 11-10 and alarms NOT STARTED (" + $r.code + ")")
    $n1 = (Lines $lr.rec).Count
    $r = Invoke-Watch $lr "2026-11-11 14:02" -Boot "2026-11-10 20:32:57"
    Check ($r.code -eq 0 -and $n1 -ge 1 -and (Lines $lr.rec).Count -eq $n1) ("a second logon the same day sends nothing new (" + $n1 + " then " + (Lines $lr.rec).Count + ")")
    $r = Invoke-Watch $lr "2026-11-12 02:10" -Boot "2026-11-10 20:32:57" -More @("-Plan")
    Check ($r.code -eq 0 -and $r.out -like "*PLAN night 2026-11-10:*") "a logon at 02:10 judges the last FINISHED night, never the one still running"
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "the watcher judges the night that began yesterday by calendar, tells RAN from NOT STARTED, REFUSED, FAILED, BUSY, NOT REPORTED and NOT TOLD from the evidence alone, reads the task XML for a missing, disabled or offset task, alarms once a morning with a streak and a recovery, keeps each of two channels independent, exits non-zero only when all fail, never silences itself on an empty folder or a corrupt memory, and is registered to run at its user's logon too, judging the last finished night once"
