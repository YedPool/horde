# DOES THE RESTORE SOURCE POST EXACTLY THE RESUME MAILS IT SHOULD, ONCE EACH, AND NONE IN SHADOW?
#
# core/RestoreSource.ps1 - the sender that tells the orcs to resume after every session was started or
# restored together. It only posts; the wake watcher (core/Wake.ps1, test/test-wake.ps1) is what knocks
# for that mail. Replayed on a clock this suite moves by hand, with a poster of this suite's:
#   - A REPLAY of a real timeline: twelve sessions restarted inside 150 s. Orcs are told to resume at
#     once; a subsession, or a session of no known role, never is - an orc mails the ones it still
#     needs; and the warchief is told at 300 s when nothing moved - each mail under an id that never
#     changes.
#   - NO RESTORE: a quiet night, one restarted session, too few, too small a share.
#   - A PASS posts each mail once, tries again what the poster could not take, and in shadow posts none.
#   - THE POSTER hands each mail to the messenger port: through the in-process messenger each mail is
#     one record holding the resume text, a pass repeated with its state lost adds none, and with no
#     messenger that may be picked nothing is posted and nothing is marked posted.
#   - THE RUNNING SESSIONS are read from the two stores handed in, never from this machine.
# The file (restore.json) is written under a home this suite made and removes.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "test\lib\FleetPin.ps1")
. (Join-Path $root "test\lib\MessengerPins.ps1")
# PINNED FIRST: an empty fleet and a home of this suite's, so nothing below can read or write the real ones.
$fleetPin = Enter-HordeTestEmptyFleet
$pinned = Enter-HordeTestPinnedHome -Root $root
. (Join-Path $root "core\RestoreSource.ps1")
# The in-process test messenger, and no other: what the poster posts through below, handed to it.
. (Join-Path $root "messengers\memory\Messenger.ps1")

# THE SETTLE TIME IS SET TO 0 FOR THE TIMELINES BELOW, which are about who is mailed and under which id,
# and say "at once" for it. The settle time itself, at its default, has a section of its own.
$settings = Get-HordeRestoreSettings -Overrides @{ restoreSettleSeconds = 0 }
$t0 = New-Object System.DateTime(2026, 10, 12, 8, 0, 0, [System.DateTimeKind]::Utc)

function At { param([double]$Seconds) return $t0.AddSeconds($Seconds) }
function Sid { param([int]$N) return ("0a000000-0000-4000-8000-" + $N.ToString("000000000000")) }
function Kinds { param($Result) return (@($Result.entries | ForEach-Object { $_.kind }) -join ",") }

try {
Write-Host ""
Write-Host "--- the restore source: a replay of twelve sessions restarted inside 150 s ---" -ForegroundColor Cyan

# One warchief (1), three orcs (2 to 4), eight wargs (5 to 12: 5 to 7 under orc 2, 8 to 10 under orc 3,
# 11 and 12 under orc 4). Each started 13 s after the last, and wrote its status once, 4 s after starting.
function New-Restored {
    param([hashtable]$MovedAfter = @{}, [hashtable]$Status = @{}, [hashtable]$FirstSeen = @{})
    $out = @()
    for ($n = 1; $n -le 12; $n++) {
        $role = "warg"; $parent = ""
        if ($n -eq 1) { $role = "warchief" } elseif ($n -le 4) { $role = "orc"; $parent = Sid 1 }
        elseif ($n -le 7) { $parent = Sid 2 } elseif ($n -le 10) { $parent = Sid 3 } else { $parent = Sid 4 }
        $start = At (($n - 1) * 13)
        $change = $start.AddSeconds(4)
        if ($MovedAfter.ContainsKey($n)) { $change = $start.AddSeconds($MovedAfter[$n]) }
        $out += [pscustomobject]@{ id = (Sid $n); role = $role; parent = $parent; startedAt = $start; lastChangeAt = $change; status = $(if ($Status.ContainsKey($n)) { $Status[$n] } else { "idle" }); firstSeenAt = $(if (-not $FirstSeen.ContainsKey($n)) { $start.AddHours(-1) } elseif ($null -eq $FirstSeen[$n]) { $null } else { $start.AddSeconds(-1 * $FirstSeen[$n]) }) }
    }
    return $out
}
$end = 143
$fleet = New-Restored
$f = Get-HordeRestoreFinding -Sessions $fleet -Now (At ($end + 10)) -Settings $settings
Check ($f.state -ceq "known") "twelve sessions that started inside 150 s are a restore"
Check ($f.state -ceq "known" -and $f.value.windowStart -eq $t0 -and $f.value.windowEnd -eq (At $end) -and @($f.value.members).Count -eq 12 -and @($f.value.notMoved).Count -eq 12) "its window runs from the first start to the last, with all twelve as members and none moved"
Check ($f.state -ceq "known" -and $f.value.restoreId -cmatch '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z') "its id is a lowercase uuid"
$again = Get-HordeRestoreFinding -Sessions $fleet -Now (At ($end + 250)) -Settings $settings
Check ($again.state -ceq "known" -and $again.value.restoreId -ceq $f.value.restoreId) "and the same id on a later pass"
$shifted = @($fleet | ForEach-Object { [pscustomobject]@{ id = $_.id; role = $_.role; parent = $_.parent; startedAt = $_.startedAt.AddMinutes(7); lastChangeAt = $_.lastChangeAt.AddMinutes(7); status = "idle"; firstSeenAt = ($_.startedAt.AddMinutes(7)).AddHours(-1) } })
$f7 = Get-HordeRestoreFinding -Sessions $shifted -Now (At 2000) -Settings $settings
Check ($f7.state -ceq "known" -and $f7.value.restoreId -cne $f.value.restoreId) "a restore that began in another minute has another id"


# THE EARLIEST MEMBER CLOSES. This fleet's first session started at 08:06:50 and its second at 08:07:03,
# so without the first the window begins in another minute.
$shifted = @($fleet | ForEach-Object { [pscustomobject]@{ id = $_.id; role = $_.role; parent = $_.parent; startedAt = $_.startedAt.AddSeconds(410); lastChangeAt = $_.lastChangeAt.AddSeconds(410); status = "idle"; firstSeenAt = $_.firstSeenAt } })
$f7 = Get-HordeRestoreFinding -Sessions $shifted -Now (At 2000) -Settings $settings
$late = @($shifted | Where-Object { $_.id -cne (Sid 1) })
$f7late = Get-HordeRestoreFinding -Sessions $late -Now (At 2100) -Settings $settings
Check ($f7late.state -ceq "known" -and $f7late.value.restoreId -cne $f7.value.restoreId) "CONTROL: with nothing saved, a restore whose earliest member closed would be named anew"
$f7kept = Get-HordeRestoreFinding -Sessions $late -Now (At 2100) -Settings $settings -Known @($f7.value.anchor)
Check ($f7kept.state -ceq "known" -and $f7kept.value.restoreId -ceq $f7.value.restoreId) "given the restore that was saved, a window that overlaps it keeps its id when its earliest member has closed"
Check ($f7kept.value.anchor.windowStart -eq $f7.value.windowStart -and $f7kept.value.anchor.windowEnd -eq $f7.value.windowEnd -and $f7kept.value.windowStart -gt $f7.value.windowStart) "and what it hands back to save covers both windows, while its own window is the one it found"
$idsBefore = (@(Get-HordeResumePlan -Finding $f7 -Now (At 2100) -Settings $settings | Where-Object { $_.kind -ceq "resume" } | Sort-Object to | ForEach-Object { $_.messageId }) -join ",")
$idsAfter = (@(Get-HordeResumePlan -Finding $f7kept -Now (At 2100) -Settings $settings | Where-Object { $_.kind -ceq "resume" } | Sort-Object to | ForEach-Object { $_.messageId }) -join ",")
Check ($idsBefore -ceq $idsAfter -and $idsBefore -ne "") "so every resume mail keeps its messageId, and nobody is mailed again"

# A SECOND RESTORE THAT BEGINS INSIDE THE FIRST ONE'S WINDOW: every session is brought back again 100 s
# after the first restore began, so the new window (100 to 243 s) overlaps the saved one (0 to 143 s).
$secondTime = @($fleet | ForEach-Object { [pscustomobject]@{ id = $_.id; role = $_.role; parent = $_.parent; startedAt = $_.startedAt.AddSeconds(100); lastChangeAt = $_.lastChangeAt.AddSeconds(100); status = "idle"; firstSeenAt = $_.firstSeenAt } })
$f2 = Get-HordeRestoreFinding -Sessions $secondTime -Now (At 300) -Settings $settings -Known @($f.value.anchor)
Check ($f2.state -ceq "known" -and $f2.value.restoreId -cne $f.value.restoreId) "a second restore that begins inside the first one's window is a NEW restore: every session it shares with the saved one has a later start"
$ids2 = (@(Get-HordeResumePlan -Finding $f2 -Now (At 300) -Settings $settings | Where-Object { $_.kind -ceq "resume" } | Sort-Object to | ForEach-Object { $_.messageId }) -join ",")
$ids1st = (@(Get-HordeResumePlan -Finding $f -Now (At 300) -Settings $settings | Where-Object { $_.kind -ceq "resume" } | Sort-Object to | ForEach-Object { $_.messageId }) -join ",")
Check ($ids2 -ne "" -and $ids2 -cne $ids1st) "so its resume mails have ids of their own, and the orcs are told again"
$f2again = Get-HordeRestoreFinding -Sessions $secondTime -Now (At 330) -Settings $settings -Known @($f.value.anchor, $f2.value.anchor)
Check ($f2again.state -ceq "known" -and $f2again.value.restoreId -ceq $f2.value.restoreId) "and on the next pass, with both saved, it is the second restore and keeps the second one's id"
$sameMinute = @($fleet | ForEach-Object { [pscustomobject]@{ id = $_.id; role = $_.role; parent = $_.parent; startedAt = $_.startedAt.AddSeconds(20); lastChangeAt = $_.lastChangeAt.AddSeconds(20); status = "idle"; firstSeenAt = $_.firstSeenAt } })
$f3 = Get-HordeRestoreFinding -Sessions $sameMinute -Now (At 300) -Settings $settings -Known @($f.value.anchor)
Check ($f3.state -ceq "known" -and $f3.value.restoreId -cne $f.value.restoreId) "even a second restore that begins in the first one's minute gets an id of its own"
# FEWER THAN MOST: five of the twelve were restarted by hand since; the other seven are the same lives.
$fewAgain = @($fleet | ForEach-Object { if (@(8, 9, 10, 11, 12 | ForEach-Object { Sid $_ }) -ccontains $_.id) { [pscustomobject]@{ id = $_.id; role = $_.role; parent = $_.parent; startedAt = $_.startedAt.AddSeconds(100); lastChangeAt = $_.lastChangeAt.AddSeconds(100); status = "idle"; firstSeenAt = $_.firstSeenAt } } else { $_ } })
$f4 = Get-HordeRestoreFinding -Sessions $fewAgain -Now (At 300) -Settings $settings -Known @($f.value.anchor)
Check ($f4.state -ceq "known" -and $f4.value.restoreId -ceq $f.value.restoreId) "when most of the saved members that are still running have the start they had, it is the same restore, whatever a few did since"
# MOST WERE RESTORED AGAIN: nine of the twelve have a later start, three are the same lives.
$mostAgain = @($fleet | ForEach-Object { if (@(1, 2, 3 | ForEach-Object { Sid $_ }) -ccontains $_.id) { $_ } else { [pscustomobject]@{ id = $_.id; role = $_.role; parent = $_.parent; startedAt = $_.startedAt.AddSeconds(100); lastChangeAt = $_.lastChangeAt.AddSeconds(100); status = "idle"; firstSeenAt = $_.firstSeenAt } } })
$fMost = Get-HordeRestoreFinding -Sessions $mostAgain -Now (At 300) -Settings $settings -Known @($f.value.anchor)
Check ($fMost.state -ceq "known" -and $fMost.value.restoreId -cne $f.value.restoreId) "when most of them have a later start it is a new restore, though a few are the same lives"
# THE WINDOW MUST OVERLAP TOO. The twelve are still running, untouched, and a day later twenty other
# sessions are restored: the saved restore's members are all present with the starts it recorded, and
# it is still not this restore, whose window is a day away.
$dayLater = @($fleet) + @(21..40 | ForEach-Object { [pscustomobject]@{ id = (Sid $_); role = "orc"; parent = ""; startedAt = (At (86400 + $_ * 5)); lastChangeAt = (At (86400 + $_ * 5 + 2)); status = "idle"; firstSeenAt = (At -90000) } })
$fDay = Get-HordeRestoreFinding -Sessions $dayLater -Now (At (86400 + 400)) -Settings $settings -Known @($f.value.anchor)
Check ($fDay.state -ceq "known" -and @($fDay.value.members).Count -eq 20 -and $fDay.value.restoreId -cne $f.value.restoreId) "a restore whose window does not overlap a saved one is not that restore, even while every member of the saved one is still running as it was"
$strangers = @($fleet | ForEach-Object { [pscustomobject]@{ id = ("0b" + $_.id.Substring(2)); role = $_.role; parent = ""; startedAt = $_.startedAt.AddSeconds(50); lastChangeAt = $_.lastChangeAt.AddSeconds(50); status = "idle"; firstSeenAt = $_.firstSeenAt } })
$f5 = Get-HordeRestoreFinding -Sessions $strangers -Now (At 300) -Settings $settings -Known @($f.value.anchor)
Check ($f5.state -ceq "known" -and $f5.value.restoreId -cne $f.value.restoreId) "a window that overlaps a saved restore none of whose members is still running shares no session with it, and is a new restore"
$legacy = [pscustomobject]@{ restoreId = $f.value.restoreId; windowStart = $f.value.windowStart; windowEnd = $f.value.windowEnd }
$f6 = Get-HordeRestoreFinding -Sessions $fleet -Now (At 300) -Settings $settings -Known @($legacy)
Check ($f6.state -ceq "known" -and $f6.value.restoreId -cne $f.value.restoreId) "a restore saved before members were recorded matches nothing: its window alone is not enough"
Check ($f.value.anchor.members.Count -eq 12 -and $f.value.anchor.members[(Sid 2)] -eq (At 13)) "what is handed back to save holds each member's start"

$nextDay = @($fleet | ForEach-Object { [pscustomobject]@{ id = $_.id; role = $_.role; parent = $_.parent; startedAt = $_.startedAt.AddDays(1); lastChangeAt = $_.lastChangeAt.AddDays(1); status = "idle"; firstSeenAt = $_.firstSeenAt } })
$fNext = Get-HordeRestoreFinding -Sessions $nextDay -Now (At (86400 + 200)) -Settings $settings -Known @($f.value.anchor)
Check ($fNext.state -ceq "known" -and $fNext.value.restoreId -cne $f.value.restoreId) "a restore the next day overlaps no saved one, and is a new restore with a new id"

$plan = @(Get-HordeResumePlan -Finding $f -Now (At ($end + 10)) -Settings $settings)
$orcs = @(2, 3, 4 | ForEach-Object { Sid $_ })
Check ((@($plan | ForEach-Object { $_.to } | Sort-Object) -join ",") -ceq ($orcs -join ",") -and @($plan | Where-Object { $_.kind -cne "resume" }).Count -eq 0) "all three orcs are told to resume at once, and nobody else"
Check (@($plan | Where-Object { $_.body -cne $settings.resumeText }).Count -eq 0 -and $settings.resumeText.StartsWith("AUTOMATED, from the restore source: START OR RESTORE. Every session on this machine was started or restored together") -and $settings.resumeText.EndsWith("mail the subsessions you still need: they are not woken unless you ask.")) "each with the resume text, which covers a start as well as a restore and tells an orc its subsessions are not woken unless it asks"
$unroled = @($fleet | ForEach-Object { if ($_.id -ceq (Sid 12)) { [pscustomobject]@{ id = $_.id; role = "unknown"; parent = $_.parent; startedAt = $_.startedAt; lastChangeAt = $_.lastChangeAt; status = "idle"; firstSeenAt = ($_.startedAt).AddHours(-1) } } else { $_ } })
foreach ($after in @(0, 180, 600)) {
    $planAt = @(Get-HordeResumePlan -Finding $f -Now (At ($end + $after)) -Settings $settings | Where-Object { $_.kind -ceq "resume" })
    Check ((@($planAt | ForEach-Object { $_.to } | Sort-Object) -join ",") -ceq ($orcs -join ",")) ("" + $after + " s after the last start, with no orc moved, the orcs are told and no warg is")
    $planAt = @(Get-HordeResumePlan -Finding (Get-HordeRestoreFinding -Sessions $unroled -Now (At ($end + $after)) -Settings $settings) -Now (At ($end + $after)) -Settings $settings | Where-Object { $_.kind -ceq "resume" })
    Check ($planAt.Count -eq 3 -and @($planAt | Where-Object { $_.to -ceq (Sid 12) }).Count -eq 0) ("" + $after + " s after it, a session of no known role is not told either")
}
$oneMoved = Get-HordeRestoreFinding -Sessions (New-Restored -MovedAfter @{ 2 = 90 }) -Now (At ($end + 100)) -Settings $settings
$planMoved = @(Get-HordeResumePlan -Finding $oneMoved -Now (At ($end + 100)) -Settings $settings)
Check ((@($planMoved | ForEach-Object { $_.to } | Sort-Object) -join ",") -ceq (@(3, 4 | ForEach-Object { Sid $_ }) -join ",")) "once an orc has moved it is not told again - and its wargs are still not told: it mails the ones it needs"
$planMoved600 = @(Get-HordeResumePlan -Finding (Get-HordeRestoreFinding -Sessions (New-Restored -MovedAfter @{ 2 = 90 }) -Now (At ($end + 600)) -Settings $settings) -Now (At ($end + 600)) -Settings $settings)
Check ((@($planMoved600 | ForEach-Object { $_.to } | Sort-Object) -join ",") -ceq (@(3, 4 | ForEach-Object { Sid $_ }) -join ",")) "nor are they at 600 s"
Check (@($oneMoved.value.notMoved).Count -eq 11 -and @($oneMoved.value.members | Where-Object { $_.moved -ceq "yes" }).Count -eq 1 -and @($oneMoved.value.members | Where-Object { $_.moved -ceq "no" }).Count -eq 11) "a member has moved when its status changed at least movedSeconds after it started"
foreach ($word in @("busy", "waiting")) {
    $inTurn = Get-HordeRestoreFinding -Sessions (New-Restored -Status @{ 2 = $word }) -Now (At ($end + 100)) -Settings $settings
    $planTurn = @(Get-HordeResumePlan -Finding $inTurn -Now (At ($end + 100)) -Settings $settings)
    Check (@($inTurn.value.notMoved).Count -eq 11 -and (@($planTurn | ForEach-Object { $_.to } | Sort-Object) -join ",") -ceq (@(3, 4 | ForEach-Object { Sid $_ }) -join ",")) ("an orc that is " + $word + " now, its status last changed 4 s after it started, is not known to be unmoved: it is not told to resume")
}
$untold = Get-HordeRestoreFinding -Sessions (New-Restored -Status @{ 2 = "unknown"; 3 = "" }) -Now (At ($end + 100)) -Settings $settings
$planUntold = @(Get-HordeResumePlan -Finding $untold -Now (At ($end + 100)) -Settings $settings)
Check (@($untold.value.notMoved).Count -eq 10 -and $planUntold.Count -eq 1 -and $planUntold[0].to -ceq (Sid 4)) "an orc whose status is not known is never 'not moved': unknown means no mail"
$planUntold300 = @(Get-HordeResumePlan -Finding (Get-HordeRestoreFinding -Sessions (New-Restored -Status @{ 7 = "busy" }) -Now (At ($end + 300)) -Settings $settings) -Now (At ($end + 300)) -Settings $settings)
Check (@($planUntold300 | Where-Object { $_.kind -ceq "stall" }).Count -eq 0) "and one session in a turn is something moving: there is no stall notice"
$barely = Get-HordeRestoreFinding -Sessions (New-Restored -MovedAfter @{ 2 = 29 }) -Now (At ($end + 100)) -Settings $settings
$just = Get-HordeRestoreFinding -Sessions (New-Restored -MovedAfter @{ 2 = 30 }) -Now (At ($end + 100)) -Settings $settings
Check (@($barely.value.notMoved).Count -eq 12 -and @($just.value.notMoved).Count -eq 11 -and (Get-HordeRestoreSettings).movedSeconds -eq 30) "movedSeconds is 30: a status changed 29 s after the start is not a move, and one at 30 s is"
$quick = Get-HordeRestoreFinding -Sessions (New-Restored -MovedAfter @{ 2 = 11 }) -Now (At ($end + 100)) -Settings $settings
Check (@($quick.value.notMoved | Where-Object { $_ -ceq (Sid 2) }).Count -eq 1) "the limit that remains: an idle orc whose status changed 11 s after its start - as it does for one that never took a turn - reads as not moved"

# THREE ANSWERS. Each row: the status now, how long after its start it last changed, and what moved is.
foreach ($case in @(
        @{ status = "busy"; after = 4; moved = "yes"; what = "busy now, whenever that began" },
        @{ status = "idle"; after = 90; moved = "yes"; what = "idle, its status changed long after its start: it took a turn and came back" },
        @{ status = "waiting"; after = 90; moved = "yes"; what = "waiting, since long after its start: it took a turn and asked something" },
        @{ status = "idle"; after = 4; moved = "no"; what = "idle, its status as old as its start" },
        @{ status = "waiting"; after = 4; moved = "neither"; what = "waiting since it started: stuck on a prompt it met at once" },
        @{ status = "ended"; after = 4; moved = "neither"; what = "ended" },
        @{ status = "ended"; after = 90; moved = "neither"; what = "ended, long after its start" },
        @{ status = "unknown"; after = 90; moved = "neither"; what = "a status that is not known" },
        @{ status = ""; after = 4; moved = "neither"; what = "no status at all" })) {
    $one = Get-HordeRestoreFinding -Sessions (New-Restored -MovedAfter @{ 2 = $case.after } -Status @{ 2 = $case.status }) -Now (At ($end + 300)) -Settings $settings
    $got = @($one.value.members | Where-Object { $_.id -ceq (Sid 2) })[0].moved
    $planOne = @(Get-HordeResumePlan -Finding $one -Now (At ($end + 300)) -Settings $settings)
    $mailed = (@($planOne | Where-Object { $_.kind -ceq "resume" -and $_.to -ceq (Sid 2) }).Count -eq 1)
    $stalled = (@($planOne | Where-Object { $_.kind -ceq "stall" }).Count -eq 1)
    Check ($got -ceq $case.moved -and $mailed -eq ($case.moved -ceq "no") -and $stalled -eq ($case.moved -cne "yes")) ("an orc that is " + $case.what + ": moved is " + $case.moved + " (got " + $got + "); it is mailed only when no, and the stall notice is suppressed only when yes")
}
$dead = Get-HordeRestoreFinding -Sessions (New-Restored -Status @{ 1 = "ended"; 2 = "waiting"; 3 = "ended"; 4 = "unknown"; 5 = "ended"; 6 = "ended"; 7 = "ended"; 8 = "ended"; 9 = "ended"; 10 = "ended"; 11 = "ended"; 12 = "ended" }) -Now (At ($end + 300)) -Settings $settings
$planDead = @(Get-HordeResumePlan -Finding $dead -Now (At ($end + 300)) -Settings $settings)
Check ((Kinds ([pscustomobject]@{ entries = $planDead })) -ceq "stall" -and @($dead.value.notMoved).Count -eq 0) "a fleet where every session ended or is stuck waiting is a dead fleet: nobody is mailed to resume, and the warchief IS told"
$plan180 = @(Get-HordeResumePlan -Finding $f -Now (At ($end + 180)) -Settings $settings)
Check ($plan180.Count -eq 3 -and @($plan180 | Where-Object { $_.to -ceq (Sid 1) }).Count -eq 0) "and the warchief is never told to resume"

$plan299 = @(Get-HordeResumePlan -Finding $f -Now (At ($end + 299)) -Settings $settings)
Check (@($plan299 | Where-Object { $_.kind -ceq "stall" }).Count -eq 0) "there is no stall notice 299 s after the last start"
$plan300 = @(Get-HordeResumePlan -Finding $f -Now (At ($end + 300)) -Settings $settings)
$stall = @($plan300 | Where-Object { $_.kind -ceq "stall" })
Check ($stall.Count -eq 1 -and $stall[0].to -ceq (Sid 1) -and $stall[0].body -ceq $settings.stallText) "at 300 s, with nothing moved, the warchief is told the restore has stalled"
Check ($settings.stallText.StartsWith("AUTOMATED, from the restore source: ") -and $settings.resumeText.StartsWith("AUTOMATED, from the restore source: ")) "both mails say first that they are automated, and from what"
. (Join-Path $root "core\ReservedLabels.ps1")
Check ($settings.fromLabel -ceq "RS" -and (Test-HordeLabelReserved $settings.fromLabel)) "the label they wear, RS, is one no session may be given"
$planLate = @(Get-HordeResumePlan -Finding (Get-HordeRestoreFinding -Sessions (New-Restored -MovedAfter @{ 7 = 200 }) -Now (At ($end + 400)) -Settings $settings) -Now (At ($end + 400)) -Settings $settings)
Check (@($planLate | Where-Object { $_.kind -ceq "stall" }).Count -eq 0) "and it is not, at any time, once one member has moved"
$noChief = Get-HordeRestoreFinding -Sessions @($fleet | Where-Object { $_.role -cne "warchief" }) -Now (At ($end + 300)) -Settings $settings
$stallNobody = @(@(Get-HordeResumePlan -Finding $noChief -Now (At ($end + 300)) -Settings $settings) | Where-Object { $_.kind -ceq "stall" })
Check ($stallNobody.Count -eq 1 -and $stallNobody[0].to -ceq "") "with no warchief among the restored sessions the stall notice is addressed to nobody, and says so"

$ids1 = (@($plan300 | Sort-Object to | ForEach-Object { $_.to + "=" + $_.messageId }) -join ";")
$ids2 = (@(Get-HordeResumePlan -Finding $again -Now (At ($end + 300)) -Settings $settings | Sort-Object to | ForEach-Object { $_.to + "=" + $_.messageId }) -join ";")
Check ($ids1 -ceq $ids2 -and $plan300.Count -eq 4) "a plan made again names every mail by the same messageId: three orcs and the stall notice"
Check (@($plan300 | ForEach-Object { $_.messageId } | Sort-Object -Unique).Count -eq 4 -and @($plan300 | Where-Object { $_.messageId -cnotmatch '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z' }).Count -eq 0) "each mail has an id of its own, a lowercase uuid"
$orcId = @($plan | Where-Object { $_.to -ceq (Sid 2) })[0].messageId
Check (@($plan300 | Where-Object { $_.to -ceq (Sid 2) })[0].messageId -ceq $orcId) "and an orc's resume mail has the id at 300 s that it had at 10 s"

Write-Host ""
Write-Host "--- the restore source in a pass: posted once, retried when the post could not say ---" -ForegroundColor Cyan

$script:mails = New-Object System.Collections.ArrayList
$script:postWorks = $true
$poster = { param($m) [void]$script:mails.Add($m); if ($script:postWorks) { New-HordeKnown -Value $true } else { New-HordeUnknown -Reason "the mailbox is locked" } }
$r = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 10)) -Settings $settings -Post $poster -Posted @{}
Check ($script:mails.Count -eq 3 -and (Kinds $r) -ceq "post,post,post" -and @($r.entries | Where-Object { $_.outcome -cne "posted" -or $_.messageId -eq "" }).Count -eq 0) "three resume mails are posted, each journaled with its messageId"
Check (@($r.known).Count -eq 1 -and $r.known[0].restoreId -ceq $f.value.restoreId -and $r.known[0].windowStart -eq $t0 -and $r.known[0].windowEnd -eq (At $end)) "and the pass hands back the restore it found, to be saved"
$closed = @($fleet | Where-Object { $_.id -cne (Sid 1) })
$rc = Invoke-HordeRestoreSourcePass -Sessions $closed -Now (At ($end + 11)) -Settings $settings -Post $poster -Posted $r.posted -Known $r.known
Check ($script:mails.Count -eq 3 -and @($rc.entries).Count -eq 0 -and @($rc.known).Count -eq 1 -and $rc.known[0].restoreId -ceq $f.value.restoreId) "a pass after the earliest member closed posts nothing again: the saved restore kept its id"
$r2 = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 13)) -Settings $settings -Post $poster -Posted $r.posted
Check ($script:mails.Count -eq 3 -and @($r2.entries).Count -eq 0) "the next pass posts none of them again"
$r180 = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 180)) -Settings $settings -Post $poster -Posted $r2.posted
Check ($script:mails.Count -eq 3 -and @($r180.entries).Count -eq 0) "nor, at 180 s, anything to a warg"
$script:postWorks = $false
$script:mails.Clear()
$r3 = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 10)) -Settings $settings -Post $poster -Posted @{}
Check ($script:mails.Count -eq 3 -and @($r3.entries | Where-Object { $_.outcome -ceq "unknown" -and $_.reason -ceq "the mailbox is locked" }).Count -eq 3 -and $r3.posted.Count -eq 0) "a post that could not say is journaled unknown with its reason, and is not marked posted"
$script:postWorks = $true
$r4 = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 13)) -Settings $settings -Post $poster -Posted $r3.posted
$sameIds = ((@($script:mails[0..2] | ForEach-Object { $_.messageId } | Sort-Object) -join ",") -ceq (@($script:mails[3..5] | ForEach-Object { $_.messageId } | Sort-Object) -join ","))
Check ($script:mails.Count -eq 6 -and $r4.posted.Count -eq 3 -and $sameIds) "so the next pass tries those three again, under the same ids"
$r5 = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 300)) -Settings $settings -Post { param($m) throw "the poster fell over" } -Posted $r4.posted
Check ((Kinds $r5) -ceq "stall" -and $r5.entries[0].outcome -ceq "unknown" -and "$($r5.entries[0].reason)".Contains("fell over")) "a poster that throws is an unknown outcome, never a throw of the pass"
$r6 = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 300)) -Settings $settings -Posted $r4.posted
Check ((Kinds $r6) -ceq "stall" -and $r6.entries[0].outcome -ceq "unposted") "and a live pass given nothing to post through says the mail was not posted"

Write-Host ""
Write-Host "--- no restore: a quiet night, one restarted session, too few, too small a share ---" -ForegroundColor Cyan

$quiet = @(1..10 | ForEach-Object { [pscustomobject]@{ id = (Sid $_); role = "warg"; parent = ""; startedAt = (At ($_ * -7200)); lastChangeAt = (At ($_ * -7200 + 3)); status = "idle"; firstSeenAt = ((At ($_ * -7200))).AddHours(-1) } })
$f = Get-HordeRestoreFinding -Sessions $quiet -Now $t0 -Settings $settings
Check ($f.state -ceq "absent" -and "$($f.reason)" -ne "") "a quiet night, with start times hours apart, is no restore, and the answer says why"
Check (@(Get-HordeResumePlan -Finding $f -Now $t0 -Settings $settings).Count -eq 0) "and nothing is planned for it"
$oneBack = @($quiet | ForEach-Object { $_ })
$oneBack[4] = [pscustomobject]@{ id = (Sid 5); role = "warg"; parent = ""; startedAt = (At -30); lastChangeAt = (At -28); status = "idle"; firstSeenAt = ((At -30)).AddHours(-1) }
Check ((Get-HordeRestoreFinding -Sessions $oneBack -Now $t0 -Settings $settings).state -ceq "absent") "one restarted session among ten is no restore"
$two = @(1, 2 | ForEach-Object { [pscustomobject]@{ id = (Sid $_); role = "orc"; parent = ""; startedAt = (At ($_ * -5)); lastChangeAt = (At ($_ * -5 + 1)); status = "idle"; firstSeenAt = ((At ($_ * -5))).AddHours(-1) } })
Check ((Get-HordeRestoreFinding -Sessions $two -Now $t0 -Settings $settings).state -ceq "absent") "two sessions that started together are fewer than a restore takes"
$twoOfThree = @($two) + [pscustomobject]@{ id = (Sid 3); role = "orc"; parent = ""; startedAt = (At -90000); lastChangeAt = (At -80000); status = "idle"; firstSeenAt = ((At -90000)).AddHours(-1) }
Check ((Get-HordeRestoreFinding -Sessions $twoOfThree -Now $t0 -Settings $settings).state -ceq "absent") "two of three together is a large share and still fewer than a restore takes"

Write-Host ""
Write-Host "--- the settle time: nobody is mailed for two minutes, so a person restarting sessions by hand can reach them ---" -ForegroundColor Cyan

$byDefault = Get-HordeRestoreSettings
Check ($byDefault.restoreSettleSeconds -eq 120 -and $byDefault.stallSeconds -eq 300) "the settle time is 120 s by default, and the stall notice's 300 s is as it was"
# THE HAND RESTART: five long-lived sessions, three of them restarted by hand inside ten minutes.
function New-ByHand {
    param([hashtable]$MovedAfter = @{})
    $rows = @()
    foreach ($n in 1..5) {
        $start = At (-90000 - $n * 7200)
        $change = $start.AddSeconds(900)
        if ($n -le 3) { $start = At ($n * 200); $change = $start.AddSeconds(3); if ($MovedAfter.ContainsKey($n)) { $change = $start.AddSeconds($MovedAfter[$n]) } }
        $rows += [pscustomobject]@{ id = (Sid $n); role = "orc"; parent = ""; startedAt = $start; lastChangeAt = $change; status = "idle"; firstSeenAt = (At -200000) }
    }
    return $rows
}
$handEnd = 600
$hand = Get-HordeRestoreFinding -Sessions (New-ByHand) -Now (At ($handEnd + 10)) -Settings $byDefault
Check ($hand.state -ceq "known" -and @($hand.value.members).Count -eq 3 -and $hand.value.windowEnd -eq (At $handEnd)) "three long-lived sessions of five, restarted by hand within ten minutes, ARE a restore by the numbers"
foreach ($after in @(0, 10, 119)) {
    Check (@(Get-HordeResumePlan -Finding $hand -Now (At ($handEnd + $after)) -Settings $byDefault).Count -eq 0) ("" + $after + " s after the last of them started, nobody is mailed: the settle time has not passed")
}
$handLater = Get-HordeRestoreFinding -Sessions (New-ByHand) -Now (At ($handEnd + 120)) -Settings $byDefault
$planHand = @(Get-HordeResumePlan -Finding $handLater -Now (At ($handEnd + 120)) -Settings $byDefault)
Check ((@($planHand | ForEach-Object { $_.to } | Sort-Object) -join ",") -ceq (@(1, 2, 3 | ForEach-Object { Sid $_ }) -join ",") -and @($planHand | Where-Object { $_.kind -cne "resume" }).Count -eq 0) "at 120 s the orcs nobody came back to are mailed"
$typedTo = Get-HordeRestoreFinding -Sessions (New-ByHand -MovedAfter @{ 1 = 420; 2 = 250; 3 = 45 }) -Now (At ($handEnd + 120)) -Settings $byDefault
Check (@(Get-HordeResumePlan -Finding $typedTo -Now (At ($handEnd + 120)) -Settings $byDefault).Count -eq 0 -and @($typedTo.value.notMoved).Count -eq 0) "when the person typed to each of them inside the settle time, they read as moved and nobody is mailed, then or later"
$oneLeft = Get-HordeRestoreFinding -Sessions (New-ByHand -MovedAfter @{ 1 = 420; 3 = 45 }) -Now (At ($handEnd + 130)) -Settings $byDefault
$planOneLeft = @(Get-HordeResumePlan -Finding $oneLeft -Now (At ($handEnd + 130)) -Settings $byDefault)
Check ($planOneLeft.Count -eq 1 -and $planOneLeft[0].to -ceq (Sid 2)) "and when one was left untouched, that one alone is mailed once the time is up"
$quietHand = Get-HordeRestoreFinding -Sessions (New-ByHand) -Now (At ($handEnd + 300)) -Settings $byDefault
Check (@(Get-HordeResumePlan -Finding $quietHand -Now (At ($handEnd + 299)) -Settings $byDefault | Where-Object { $_.kind -ceq "stall" }).Count -eq 0 -and @(Get-HordeResumePlan -Finding $quietHand -Now (At ($handEnd + 300)) -Settings $byDefault | Where-Object { $_.kind -ceq "stall" }).Count -eq 1) "the stall notice keeps its own time: not at 299 s, at 300 s, whatever the settle time is"
$longSettle = Get-HordeRestoreSettings -Overrides @{ restoreSettleSeconds = 900 }
$planLong = @(Get-HordeResumePlan -Finding $quietHand -Now (At ($handEnd + 300)) -Settings $longSettle)
Check ((Kinds ([pscustomobject]@{ entries = $planLong })) -ceq "stall") "a settle time longer than the stall time holds back the resume mails and not the stall notice"

Write-Host ""
Write-Host "--- only a session with an earlier life can have been restored ---" -ForegroundColor Cyan

function New-Fresh { param([int]$N, [double]$Start, [string]$Role = "warg", $SeenAfter = 5) return [pscustomobject]@{ id = (Sid $N); role = $Role; parent = ""; startedAt = (At $Start); lastChangeAt = (At ($Start + 2)); status = "idle"; firstSeenAt = $(if ($null -eq $SeenAfter) { $null } else { At ($Start + $SeenAfter) }) } }
$old = @(1, 2 | ForEach-Object { [pscustomobject]@{ id = (Sid $_); role = "orc"; parent = ""; startedAt = (At ($_ * -7200)); lastChangeAt = (At ($_ * -7200 + 900)); status = "idle"; firstSeenAt = (At ($_ * -7200 - 3600)) } })
$spawned = $old + @((New-Fresh 3 -500), (New-Fresh 4 -300), (New-Fresh 5 -100))
$f = Get-HordeRestoreFinding -Sessions $spawned -Now $t0 -Settings $settings
Check ($f.state -ceq "absent" -and "$($f.reason)".Contains("earlier life")) "three subsessions spawned within ten minutes in a fleet of five are no restore: none has an earlier life"
$spawnedOrcs = $old + @((New-Fresh 3 -500 "orc"), (New-Fresh 4 -300 "orc"), (New-Fresh 5 -100 "orc" $null))
Check ((Get-HordeRestoreFinding -Sessions $spawnedOrcs -Now $t0 -Settings $settings).state -ceq "absent") "nor are three spawned orcs, one of them with no first-seen time at all"
$around = @($fleet) + @(13..32 | ForEach-Object { New-Fresh $_ ($_ * 5) "orc" })
$f = Get-HordeRestoreFinding -Sessions $around -Now (At ($end + 100)) -Settings $settings
$planAround = @(Get-HordeResumePlan -Finding $f -Now (At ($end + 100)) -Settings $settings)
Check ($f.state -ceq "known" -and @($f.value.members).Count -eq 12) "twenty sessions spawned around a real restore neither hide it nor join it: the share is taken among the sessions that have an earlier life"
Check ((@($planAround | ForEach-Object { $_.to } | Sort-Object) -join ",") -ceq ($orcs -join ",")) "and no spawned orc is told to resume"
$noRecord = Get-HordeRestoreFinding -Sessions (New-Restored -FirstSeen @{ 2 = $null }) -Now (At ($end + 100)) -Settings $settings
Check ($noRecord.state -ceq "known" -and @($noRecord.value.members).Count -eq 11 -and @($noRecord.value.members | Where-Object { $_.id -ceq (Sid 2) }).Count -eq 0) "a session with no first-seen time is unknown: not a member, so never mailed"
$margin59 = Get-HordeRestoreFinding -Sessions (New-Restored -FirstSeen @{ 2 = 59 }) -Now (At ($end + 100)) -Settings $settings
$margin60 = Get-HordeRestoreFinding -Sessions (New-Restored -FirstSeen @{ 2 = 60 }) -Now (At ($end + 100)) -Settings $settings
Check (@($margin59.value.members).Count -eq 11 -and @($margin60.value.members).Count -eq 12) "an earlier life is a record first seen at least 60 s before the start: 59 s is not one, 60 s is"
$morning = @(1..6 | ForEach-Object { [pscustomobject]@{ id = (Sid $_); role = "orc"; parent = ""; startedAt = (At ($_ * 20)); lastChangeAt = (At ($_ * 20 + 3)); status = "idle"; firstSeenAt = (At -50000) } })
Check ((Get-HordeRestoreFinding -Sessions $morning -Now (At 200) -Settings $settings).state -ceq "known") "a fleet of existing sessions brought back up in the morning has an earlier life, and is handled like a restore"

function New-Mixed { param([int]$Together) return @(1..10 | ForEach-Object { if ($_ -le $Together) { [pscustomobject]@{ id = (Sid $_); role = "orc"; parent = ""; startedAt = (At (-100 + $_)); lastChangeAt = (At (-98 + $_)); status = "idle"; firstSeenAt = ((At (-100 + $_))).AddHours(-1) } } else { [pscustomobject]@{ id = (Sid $_); role = "orc"; parent = ""; startedAt = (At ($_ * -7200)); lastChangeAt = (At ($_ * -7200 + 900)); status = "idle"; firstSeenAt = ((At ($_ * -7200))).AddHours(-1) } } }) }
Check ((Get-HordeRestoreFinding -Sessions (New-Mixed 5) -Now $t0 -Settings $settings).state -ceq "absent") "five of ten together is under the share a restore takes"
$six = Get-HordeRestoreFinding -Sessions (New-Mixed 6) -Now $t0 -Settings $settings
Check ($six.state -ceq "known" -and @($six.value.members).Count -eq 6) "six of ten together is a restore, of those six"
$wide = @(1..4 | ForEach-Object { [pscustomobject]@{ id = (Sid $_); role = "orc"; parent = ""; startedAt = (At ($_ * 300)); lastChangeAt = (At ($_ * 300 + 1)); status = "idle"; firstSeenAt = ((At ($_ * 300))).AddHours(-1) } })
$w = Get-HordeRestoreFinding -Sessions $wide -Now (At 2000) -Settings $settings
Check ($w.state -ceq "known" -and @($w.value.members).Count -eq 3 -and $w.value.windowStart -eq (At 300)) "the window is restoreWindowSeconds long: of four sessions 300 s apart, three fall in one"
Check ((Get-HordeRestoreFinding -Sessions $fleet -Now (At ($end + 86401)) -Settings $settings).state -ceq "absent") "a restore more than a day old is history"
Check ((Get-HordeRestoreFinding -Sessions @() -Now $t0 -Settings $settings).state -ceq "absent") "no sessions at all is no restore"


Write-Host ""
Write-Host "--- shadow: what it would post is journaled, and none of it is posted ---" -ForegroundColor Cyan

$script:posts = 0
$posted = @{}
$kinds = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt 40; $i++) {
    $r = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 250 + $i * 3)) -Settings $settings -Shadow -Post { param($m) $script:posts++; New-HordeKnown -Value $true } -Posted $posted
    $posted = $r.posted
    foreach ($e in @($r.entries)) { [void]$kinds.Add($e.kind) }
}
Check ($script:posts -eq 0) "forty shadow passes over a restore post zero mails, with a poster in hand"
Check ((@($kinds | Sort-Object) -join ",") -ceq "would-post,would-post,would-post,would-stall") ("the journal says would-post once for each of the three orcs and would-stall once, not once a pass (" + ($kinds -join ",") + ")")
Check (Throws { Get-HordeRestoreSettings -Overrides @{ stallSecond = 9 } } "not a restore setting") "a setting that is not one is refused, not silently left at its default"

Write-Host ""
Write-Host "--- the poster: each mail through the messenger port, once ---" -ForegroundColor Cyan

$inProcess = Get-HordeMessenger -Name "memory"
$watch = & (Join-Path $root "messengers\memory\test\Fixture.ps1") -Root $root
$box = & $watch.New
try {
    $through = { param($m) Send-HordeRestoreMail -Mail $m -Settings $settings -Messenger $inProcess -HordeHome $pinned.home }
    $sent = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 10)) -Settings $settings -Post $through -Posted @{}
    $sentIds = @($sent.entries | ForEach-Object { $_.messageId })
    Check ((Kinds $sent) -ceq "post,post,post" -and @($sent.entries | Where-Object { $_.outcome -cne "posted" }).Count -eq 0 -and $sent.posted.Count -eq 3) "a live pass posts the three orcs their resume mail through the messenger port, and marks each posted"
    $seen = @($sentIds | ForEach-Object { & $watch.Observe $box $_ })
    Check (@($seen | Where-Object { $_.records -ne 1 -or "$(@($_.bodies)[0])" -cne $settings.resumeText -or @($_.typed).Count -ne 0 }).Count -eq 0) "each is one record in the messenger's store, holding the resume text, and nothing was typed"
    $where = @($sentIds | ForEach-Object { Get-HordeMessengerStatus -Messenger $inProcess -MessageId $_ })
    Check (@($where | Where-Object { $_.state -cne "known" -or $_.value.stage -cne "accepted" }).Count -eq 0) "and the port says each is accepted: in the session's mailbox"
    $lost = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 40)) -Settings $settings -Post $through -Posted @{}
    $seen = @($sentIds | ForEach-Object { & $watch.Observe $box $_ })
    Check ((@($lost.entries | ForEach-Object { $_.messageId } | Sort-Object) -join ",") -ceq (@($sentIds | Sort-Object) -join ",") -and @($seen | Where-Object { $_.records -ne 1 }).Count -eq 0) "a pass that lost what it had posted posts the same ids again, and the messenger keeps each as the one message it has"
    $one = Send-HordeRestoreMail -Mail ([pscustomobject]@{ kind = "resume"; to = (Sid 2); messageId = "0d000000-0000-4000-8000-0000000000aa"; body = $settings.resumeText }) -Settings $settings -Messenger $inProcess -HordeHome $pinned.home
    Check ($one.state -ceq "known" -and $one.value.messageId -ceq "0d000000-0000-4000-8000-0000000000aa" -and $one.value.stage -ceq "accepted" -and $one.value.messenger -ceq "memory") "one mail's answer says which message, how far it got, and through which messenger"
    # NO MESSENGER THAT MAY BE PICKED: only the in-process one is loaded, and it declines what the
    # source requires, so the port finds none - which is what keeps it out of a production run.
    $unsent = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 50)) -Settings $settings -Post { param($m) Send-HordeRestoreMail -Mail $m -Settings $settings -HordeHome $pinned.home } -Posted @{}
    Check (@($unsent.entries | Where-Object { $_.outcome -ceq "unknown" -and "$($_.reason)".Contains("no messenger to post through") -and "$($_.reason)".Contains("receipt.receiver") }).Count -eq 3 -and $unsent.posted.Count -eq 0) "left to find a messenger itself, the source does not pick the in-process one: nothing is posted, nothing is marked posted, and each entry says why"
    $badLabel = Send-HordeRestoreMail -Mail ([pscustomobject]@{ kind = "resume"; to = (Sid 3); messageId = "0d000000-0000-4000-8000-0000000000ab"; body = "x" }) -Settings (Get-HordeRestoreSettings -Overrides @{ fromLabel = "not a label" }) -Messenger $inProcess -HordeHome $pinned.home
    Check ($badLabel.state -ceq "unknown" -and (& $watch.Observe $box "0d000000-0000-4000-8000-0000000000ab").records -eq 0) "a mail the port refuses - a sender label that is not one - is unknown, and never reaches the messenger"
    $noTarget = Send-HordeRestoreMail -Mail ([pscustomobject]@{ kind = "stall"; to = ""; messageId = "0d000000-0000-4000-8000-0000000000ac"; body = "x" }) -Settings $settings -Messenger $inProcess -HordeHome $pinned.home
    Check ($noTarget.state -ceq "unknown" -and (& $watch.Observe $box "0d000000-0000-4000-8000-0000000000ac").records -eq 0) "and so is a mail addressed to nobody"
    # A MESSENGER THAT HOLDS THE MAIL: known not delivered. Registered from the messenger port suite's own
    # fixture folder, with a post of this suite's.
    $holder = Register-HordeMessenger -Folder (Join-Path $root "test\fixtures\messenger\caps\fixture-good") -Post { param($m) New-HordeKnown -Value ([pscustomobject]@{ messageId = $m.messageId; stage = "held"; at = [datetime]::UtcNow; reason = "its mailbox is full" }) } -Status { param($id) New-HordeAbsent -Note "the fixture knows nothing" }
    $heldBack = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 60)) -Settings $settings -Post { param($m) Send-HordeRestoreMail -Mail $m -Settings $settings -Messenger $holder -HordeHome $pinned.home } -Posted @{}
    Check (@($heldBack.entries | Where-Object { $_.outcome -ceq "unknown" -and "$($_.reason)".Contains("held") -and "$($_.reason)".Contains("its mailbox is full") }).Count -eq 3 -and $heldBack.posted.Count -eq 0) "a mail the messenger holds is not posted: the entry says held and why, and it is not marked posted"
    $hush = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 300)) -Settings $settings -Shadow -Post $through -Posted @{}
    $stallId = @($hush.entries | Where-Object { $_.kind -ceq "would-stall" } | ForEach-Object { $_.messageId })[0]
    Check ((& $watch.Observe $box $stallId).records -eq 0) "in shadow, with this poster in hand, the stall notice reaches no messenger"
} finally { & $watch.Remove $box }

Write-Host ""
Write-Host "--- the file: what was posted, under a home of this suite's ---" -ForegroundColor Cyan

Check ((Read-HordeRestoreState -Mode "live").state -ceq "absent") "with nothing saved the state is absent"
# WHAT A SHADOW RUN WOULD HAVE POSTED IS NOT POSTED FOR A LIVE RUN. The shadow passes above marked four
# mails; saved as a shadow run saves them, a live run that starts afterwards reads none and posts all.
Save-HordeRestoreState -Posted $posted -Known $r.known -Shadow
Check ((Read-HordeRestoreState -Mode "live").state -ceq "absent" -and (Read-HordeRestoreState -Shadow).value.posted.Count -eq 4) "a shadow run's state is a file of its own, and the live state is still absent"
$liveStart = Read-HordeRestoreState -Mode "live"
$livePosted = @{}
if ($liveStart.state -ceq "known") { $livePosted = $liveStart.value.posted }
$script:mails.Clear()
$live = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 400)) -Settings $settings -Post $poster -Posted $livePosted
Check ($script:mails.Count -eq 4 -and @($live.entries | Where-Object { $_.outcome -ceq "posted" }).Count -eq 4) "so a live run started after a shadow run posts every mail the shadow run only would have"
Save-HordeRestoreState -Mode "live" -Posted @{ "0d000000-0000-4000-8000-000000000001" = (At 7); "0d000000-0000-4000-8000-000000000002" = $true } -Known @($f.value.anchor)
$back = Read-HordeRestoreState -Mode "live"
Check ($back.state -ceq "known" -and $back.value.posted.Count -eq 2 -and $back.value.posted["0d000000-0000-4000-8000-000000000001"] -eq (At 7) -and $null -eq $back.value.posted["0d000000-0000-4000-8000-000000000002"]) "the mails already posted save and read back, each with when it was posted where that is known"

$aged = @{ "0d000000-0000-4000-8000-000000000003" = (At -86401); "0d000000-0000-4000-8000-000000000004" = (At -86400); "0d000000-0000-4000-8000-000000000005" = $true }
$oldRestore = [pscustomobject]@{ restoreId = "0d000000-0000-4000-8000-00000000000a"; windowStart = (At -90000); windowEnd = (At -86401) }
$recent = [pscustomobject]@{ restoreId = "0d000000-0000-4000-8000-00000000000b"; windowStart = (At -9000); windowEnd = (At -8000) }
$pruned = Invoke-HordeRestoreSourcePass -Sessions @() -Now $t0 -Settings $settings -Posted $aged -Known @($oldRestore, $recent)
Check ($pruned.posted.Count -eq 2 -and -not $pruned.posted.ContainsKey("0d000000-0000-4000-8000-000000000003") -and $pruned.posted["0d000000-0000-4000-8000-000000000005"] -eq $t0) "a posted id older than a restore can be is dropped; one with no time is stamped now and kept"
Check (@($pruned.known).Count -eq 1 -and $pruned.known[0].restoreId -ceq $recent.restoreId) "and so is a saved restore whose window ended longer ago than that"
Check ($back.state -ceq "known" -and @($back.value.known).Count -eq 1 -and $back.value.known[0].restoreId -ceq $f.value.restoreId -and $back.value.known[0].windowStart -eq $f.value.windowStart -and $back.value.known[0].windowEnd -eq $f.value.windowEnd) "and so do the restores already found, with their ids and windows"
Check ($back.value.known[0].members.Count -eq 12 -and $back.value.known[0].members[(Sid 12)] -eq (At 143)) "and each member's start"
$readBack = Get-HordeRestoreFinding -Sessions $fleet -Now (At 300) -Settings $settings -Known $back.value.known
Check ($readBack.state -ceq "known" -and $readBack.value.restoreId -ceq $f.value.restoreId) "so a source that is restarted reads the restore back and knows it for the same one"
[System.IO.File]::WriteAllText((Join-Path (Get-HordeWakeFolder) "restore-live.json"), '{"schemaVersion":1,"posted":[],"restores":[{"restoreId":"x","windowStart":"2026-10-12T08:00:00.0000000Z","windowEnd":"2026-10-12T08:02:00.0000000Z","members":[{"id":"y"}]}]}')
Check ((Read-HordeRestoreState -Mode "live").state -ceq "unknown") "a saved member with no start is unknown, never half a state"
[System.IO.File]::WriteAllText((Join-Path (Get-HordeWakeFolder) "restore-live.json"), '{"schemaVersion":1,"posted":[{"at":"2026-10-12T08:00:00.0000000Z"}],"restores":[]}')
Check ((Read-HordeRestoreState -Mode "live").state -ceq "unknown") "a saved posted mail with no id is unknown"
[System.IO.File]::WriteAllText((Join-Path (Get-HordeWakeFolder) "restore-live.json"), '{"schemaVersion":1,"posted":[],"restores":[{"restoreId":"x"}]}')
Check ((Read-HordeRestoreState -Mode "live").state -ceq "unknown") "a saved restore with no window is unknown, never half a state"
[System.IO.File]::WriteAllText((Join-Path (Get-HordeWakeFolder) "restore-live.json"), "{ not json")
Check ((Read-HordeRestoreState -Mode "live").state -ceq "unknown") "a saved state that cannot be read is unknown, not absent"

Write-Host ""
Write-Host "--- the running sessions, from the two stores handed in ---" -ForegroundColor Cyan

function New-Record {
    param($StartedAt, $StatusAt, [string]$Agent = "agent-one", [string]$Word = "idle")
    $fields = @{}
    $fields["agent"] = New-HordeKnown -Value $Agent
    $fields["startedAt"] = $(if ($null -ne $StartedAt) { New-HordeKnown -Value $StartedAt } else { New-HordeUnknown -Reason "the agent writes no start" })
    $fields["liveStatus"] = $(if ($null -ne $StatusAt) { New-HordeKnown -Value $Word -ObservedAt $StatusAt } else { New-HordeUnknown -Reason "the process is gone" })
    return [pscustomobject]@{ fields = $fields }
}
function New-Listing {
    param([hashtable]$Records, $Whole = (New-HordeKnown -Value $true), $WholeOne = (New-HordeKnown -Value $true))
    $complete = [ordered]@{ "agent-one" = $WholeOne; "agent-two" = $Whole }
    return [pscustomobject]@{ records = $Records; complete = $complete }
}
function New-Registry {
    param([hashtable]$Records, $Whole = (New-HordeKnown -Value $true))
    $held = @{}
    foreach ($k in $Records.Keys) { $held[$k] = [pscustomobject]@{ id = $k; record = [pscustomobject]$Records[$k] } }
    return [pscustomobject]@{ records = $held; complete = $Whole }
}
$records = @{}
$records[(Sid 1)] = New-Record (At 0) (At 4)
$records[(Sid 2)] = New-Record (At 13) (At 80) -Word "busy"
$records[(Sid 3)] = New-Record (At 26) $null
$records[(Sid 4)] = New-Record $null (At 30)
$records[(Sid 5)] = New-Record (At 39) (At 41) "agent-two"
$registry = New-Registry @{ (Sid 1) = @{ role = "master"; firstSeen = "2026-10-11T07:00:00.0000000Z" }; (Sid 2) = @{ role = "orchestrator"; parent = (Sid 1); firstSeen = "yesterday" }; (Sid 5) = @{ parent = (Sid 2); role = "" } }
$a = Get-HordeRestoreSessions -Identity (New-Listing $records) -Registry $registry
Check ($a.state -ceq "known" -and @($a.leftOut).Count -eq 0) "with every listing whole nothing is left out"
$got = @()
if ($a.state -ceq "known") { $got = @($a.value | Sort-Object id) }
Check ($a.state -ceq "known" -and (@($got | ForEach-Object { $_.id }) -join ",") -ceq (@(1, 2, 5 | ForEach-Object { Sid $_ }) -join ",")) "only a session whose start and live status are both known is a running session"
Check ($got.Count -eq 3 -and $got[0].role -ceq "warchief" -and $got[1].role -ceq "orc" -and $got[1].parent -ceq (Sid 1) -and $got[0].parent -ceq "") "role and parent come from the registry record, the stored role names read as Horde's"
Check ($got.Count -eq 3 -and $got[2].role -ceq "unknown" -and $got[2].parent -ceq (Sid 2)) "a record with no role is unknown, never guessed"
Check ($got.Count -eq 3 -and $got[1].startedAt -eq (At 13) -and $got[1].lastChangeAt -eq (At 80)) "startedAt is the session's own, and lastChangeAt is when its live status was written"
Check ($got.Count -eq 3 -and $got[0].firstSeenAt -eq (New-Object System.DateTime(2026, 10, 11, 7, 0, 0, [System.DateTimeKind]::Utc)) -and $null -eq $got[1].firstSeenAt -and $null -eq $got[2].firstSeenAt) "firstSeenAt is the record's first-seen time, and nothing where the record has none or it is not a time"
Check ($got.Count -eq 3 -and $got[0].status -ceq "idle" -and $got[1].status -ceq "busy") "and each carries its live status word"
$a = Get-HordeRestoreSessions -Identity (New-Listing $records -Whole (New-HordeUnknown -Reason "one control file could not be read")) -Registry $registry
$got = @()
if ($a.state -ceq "known") { $got = @($a.value | Sort-Object id) }
Check ($a.state -ceq "known" -and (@($got | ForEach-Object { $_.id }) -join ",") -ceq (@(1, 2 | ForEach-Object { Sid $_ }) -join ",")) "with one agent's listing whole and the other's not, the answer is known, with the whole one's sessions and none of the other's"
Check ($a.state -ceq "known" -and @($a.leftOut).Count -eq 1 -and $a.leftOut[0].agent -ceq "agent-two" -and $a.leftOut[0].reason -ceq "one control file could not be read") "and it names the agent it left out, and why"
Check ((Get-HordeRestoreFinding -Sessions $a.value -Now (At 100) -Settings (Get-HordeRestoreSettings -Overrides @{ restoreMinSessions = 1 })).state -ceq "known") "its value is still the plain list the restore finding takes"
$a = Get-HordeRestoreSessions -Identity (New-Listing $records -Whole (New-HordeUnknown -Reason "one control file could not be read") -WholeOne (New-HordeUnknown -Reason "there is no control directory")) -Registry $registry
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("agent-one: there is no control directory") -and "$($a.reason)".Contains("agent-two: one control file could not be read")) "with no agent's listing whole the answer is unknown, naming each and why"
$a = Get-HordeRestoreSessions -Identity (New-Listing $records) -Registry (New-Registry @{} -Whole (New-HordeUnknown -Reason "there is no registry"))
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("registry")) "and so is a registry that is not whole"
$a = Get-HordeRestoreSessions -Identity (New-Listing @{}) -Registry (New-Registry @{})
Check ($a.state -ceq "known" -and @($a.value).Count -eq 0) "an empty fleet is a known empty list"

Write-Host ""
Write-Host "--- T-0116: a duplicated session does not blind the source, and does not fake a restore or a stall ---" -ForegroundColor Cyan

function New-DupIdentity {
    # An identity as core/Identity.ps1 answers it for one agent short only by duplicates (agent-one), and one
    # that is never whole (agent-two): complete says unknown for both, wholeButDuplicates says why.
    param($Records, [bool]$OneDupOnly = $true, $Dups = @())
    $complete = [ordered]@{ "agent-one" = (New-HordeUnknown -Reason "the listing omits some sessions, each named by more than one control file"); "agent-two" = (New-HordeUnknown -Reason "there is no control directory") }
    return [pscustomobject]@{ records = $Records; complete = $complete; wholeButDuplicates = [ordered]@{ "agent-one" = $OneDupOnly; "agent-two" = $false }; duplicates = @($Dups) }
}
$dupRecords = @{}
$dupRecords[(Sid 1)] = New-Record (At 0) (At 4)
$dupRecords[(Sid 2)] = New-Record (At 13) (At 80) -Word "busy"
$oneDup = [pscustomobject]@{ sessionId = (Sid 9); agents = @("agent-one"); sources = @("c\501.json", "c\502.json") }
$dupRegistry = New-Registry @{ (Sid 1) = @{ role = "master" }; (Sid 2) = @{ role = "orchestrator" } }
$d = Get-HordeRestoreSessions -Identity (New-DupIdentity $dupRecords -Dups @($oneDup)) -Registry $dupRegistry
Check ($d.state -ceq "known" -and (@($d.value | ForEach-Object { $_.id } | Sort-Object) -join ",") -ceq ((Sid 1) + "," + (Sid 2))) "one duplicate no longer blinds the source: the agent short only by it is taken as whole, and its other sessions are listed"
Check ($d.state -ceq "known" -and @($d.leftOut).Count -eq 1 -and $d.leftOut[0].agent -ceq "agent-two") "the agent that is never whole is still left out, and named"
Check ($d.state -ceq "known" -and @($d.duplicates).Count -eq 1 -and $d.duplicates[0].sessionId -ceq (Sid 9) -and @($d.duplicates[0].sources).Count -eq 2) "and the duplicate is named in the answer, with its files, for the caller to journal"
Check ($d.state -ceq "known" -and @($d.value | Where-Object { $_.id -ceq (Sid 9) }).Count -eq 0) "none of a duplicate's two copies is chosen"
$otherFault = Get-HordeRestoreSessions -Identity (New-DupIdentity $dupRecords -OneDupOnly $false -Dups @($oneDup)) -Registry $dupRegistry
Check ($otherFault.state -ceq "unknown") "an agent short for another fault as well as a duplicate is still left out: with none whole the answer is unknown"
$allDup = Get-HordeRestoreSessions -Identity (New-DupIdentity @{} -Dups @(1..12 | ForEach-Object { [pscustomobject]@{ sessionId = (Sid (100 + $_)); agents = @("agent-one"); sources = @("a", "b") } })) -Registry $dupRegistry
Check ($allDup.state -ceq "known" -and @($allDup.value).Count -eq 0 -and @($allDup.duplicates).Count -eq 12) "every session doubled (as on 10-16): a known empty list, each of the twelve named"
$noMember = [pscustomobject]@{ records = $dupRecords; complete = [ordered]@{ "agent-one" = (New-HordeUnknown -Reason "x"); "agent-two" = (New-HordeUnknown -Reason "y") } }
Check ((Get-HordeRestoreSessions -Identity $noMember -Registry $dupRegistry).state -ceq "unknown") "an identity without the new member reads as it always did"

# A FALSE RESTORE: 3 of 6 together is under the 0.6 share. Drop the three others as duplicates and it is 3 of 3.
$threeTogether = @(1..3 | ForEach-Object { [pscustomobject]@{ id = (Sid $_); role = "orc"; parent = ""; startedAt = (At (-100 + $_)); lastChangeAt = (At (-98 + $_)); status = "idle"; firstSeenAt = ((At (-100 + $_))).AddHours(-1) } })
Check ((Get-HordeRestoreFinding -Sessions $threeTogether -Now $t0 -Settings $settings).state -ceq "known") "CONTROL: three sessions alone, with nothing uncounted, are a restore"
$noFake = Get-HordeRestoreFinding -Sessions $threeTogether -Now $t0 -Settings $settings -UncountedDuplicates 3
Check ($noFake.state -ceq "absent" -and "$($noFake.reason)".Contains("3 of the 6")) "three of six, the other three dropped as duplicates, is no restore: duplicates count in the denominator and can only lower the share"
Check ((Get-HordeRestoreFinding -Sessions $threeTogether -Now $t0 -Settings $settings -UncountedDuplicates 2).state -ceq "known") "three of five is the share, and a restore"
# A GENUINE RESTORE with duplicates outside it is still found when the share allows.
$twelve = New-Restored
$g2 = Get-HordeRestoreFinding -Sessions $twelve -Now (At ($end + 100)) -Settings $settings -UncountedDuplicates 2
Check ($g2.state -ceq "known" -and @($g2.value.members).Count -eq 12 -and $g2.value.uncountedDuplicates -eq 2) "twelve restored sessions and two duplicates (12 of 14) are a restore, which carries the number uncounted"
Check ((Get-HordeRestoreFinding -Sessions (New-Mixed 7) -Now $t0 -Settings $settings -UncountedDuplicates 1).state -ceq "known" -and (Get-HordeRestoreFinding -Sessions @(New-Mixed 7)[0..6] -Now $t0 -Settings $settings -UncountedDuplicates 5).state -ceq "absent") "the share is the edge: 7 of 11 is a restore and 7 of 12 is not"
# THE MINIMUMS STAY ON REAL MEMBERS: duplicates never make up the numbers of a restore.
$two = Get-HordeRestoreFinding -Sessions @($threeTogether[0..1]) -Now $t0 -Settings $settings -UncountedDuplicates 5
Check ($two.state -ceq "absent" -and "$($two.reason)".Contains("running sessions have an earlier life, fewer than the 3")) "two real sessions with five duplicates are too few: the minimum counts real members only (found when the duplicates clear, inside restoreMaxAgeSeconds)"
# EVERY SESSION DOUBLED: no members, no finding, no crash, no restore.
$none = Get-HordeRestoreFinding -Sessions @() -Now $t0 -Settings $settings -UncountedDuplicates 12
Check ($none.state -ceq "absent") "no running session counted and twelve duplicates is an absent finding, not a throw and not a restore"
$noneP = Invoke-HordeRestoreSourcePass -Sessions @() -Now $t0 -Settings $settings -Post { param($m) throw "nothing may be posted" } -UncountedDuplicates 12
Check (@($noneP.entries).Count -eq 0 -and @($noneP.known).Count -eq 0) "and a pass over it journals and posts nothing"

# A FALSE STALL: the duplicate may be the one that moved.
$held = Get-HordeRestoreFinding -Sessions $fleet -Now (At ($end + 300)) -Settings $settings -UncountedDuplicates 1
$planHeld = @(Get-HordeResumePlan -Finding $held -Now (At ($end + 300)) -Settings $settings)
Check (@($planHeld | Where-Object { $_.kind -ceq "stall" }).Count -eq 0 -and @($planHeld | Where-Object { $_.kind -ceq "stall-held" }).Count -eq 1 -and @($planHeld | Where-Object { $_.kind -ceq "resume" }).Count -eq 3) "with a duplicate uncounted and nothing moved at 300 s there is no stall notice, one held line, and the resume mails to unmoved orcs are as ever"
$script:postWorks = $true
$script:mails.Clear()
$h1 = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 300)) -Settings $settings -Post $poster -Posted @{} -UncountedDuplicates 1
$heldLines = @($h1.entries | Where-Object { $_.outcome -ceq "held" })
Check ($heldLines.Count -eq 1 -and $heldLines[0].kind -ceq "stall" -and "$($heldLines[0].reason)".Contains("more than one control file")) "the pass says once that the stall notice is held back, and why"
Check (@($script:mails | Where-Object { $_.kind -ceq "stall" }).Count -eq 0 -and @($script:mails).Count -eq 3) "and posts no stall notice, only the three resume mails"
$h2 = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 330)) -Settings $settings -Post $poster -Posted $h1.posted -Known $h1.known -UncountedDuplicates 1
Check (@($h2.entries).Count -eq 0) "the next pass says nothing more of it"
$h3 = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 360)) -Settings $settings -Post $poster -Posted $h2.posted -Known $h2.known -UncountedDuplicates 0
Check ((Kinds $h3) -ceq "stall" -and $h3.entries[0].outcome -ceq "posted" -and @($script:mails | Where-Object { $_.kind -ceq "stall" }).Count -eq 1) "once the duplicate clears, the stall notice comes, if still true"
$hs = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 300)) -Settings $settings -Shadow -UncountedDuplicates 1
Check ((@($hs.entries | ForEach-Object { $_.kind }) -contains "would-stall") -eq $false -and @($hs.entries | Where-Object { $_.outcome -ceq "held" }).Count -eq 1) "in shadow the held stall is journaled held, not would-stall"

} finally {
    Exit-HordeTestPinnedHome -State $pinned
    Exit-HordeTestEmptyFleet -Pin $fleetPin
}

Complete-HordeSuite -Success "the restore source finds a restore, posts each orc its resume mail once, tells the warchief when nothing moved, and in shadow posts nothing"
