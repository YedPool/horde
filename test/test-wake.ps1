# DOES THE WAKE WATCHER NUDGE EXACTLY THE SESSIONS IT SHOULD, AND NEVER ONE IT COULD NOT READ?
#
# core/Wake.ps1, driven through the in-process waker (wakers/memory) and a clock this suite moves by
# hand, so every rule is replayed second by second and nothing here waits or reads this machine:
#   - THE SIX CONDITIONS. A session is nudged only when it is reachable, has unread mail old enough, is
#     idle, has an empty input box, is not mid-turn and is past its back-off. Each condition is broken
#     alone, and each "could not tell" is held to wait - never read as permission.
#   - BACK-OFF, AND HEALING. 5, 15, 45, 135, then 300 s for good; mail taken resets it; a session that
#     was woken and still has its mail is asked again.
#   - A RESTORE OF EVERYTHING is ten sessions with unread mail: one nudge a pass, the warchief first,
#     and nobody asked twice before everybody was asked once.
#   - SHADOW rings nobody and posts nothing.
#   - THE RESTORE SOURCE, on a replay of a real timeline: twelve sessions restarted inside 150 s. Orcs
#     are told to resume at once, their subsessions when their orc has moved or after 180 s, and the
#     warchief is told at 300 s when nothing moved - each mail under an id that never changes.
#   - AN ADAPTER THAT THROWS OR ANSWERS RUBBISH is unknown, and never a nudge.
# The files (journal, heartbeat, ledger) are written under a home this suite made and removes.

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
. (Join-Path $root "core\Wake.ps1")
. (Join-Path $root "wakers\memory\Waker.ps1")

$memory = Get-HordeWaker -Name "memory"
$settings = Get-HordeWakeSettings
$t0 = New-Object System.DateTime(2026, 10, 12, 8, 0, 0, [System.DateTimeKind]::Utc)
$script:ledger = @{}

function At { param([double]$Seconds) return $t0.AddSeconds($Seconds) }
function Sid { param([int]$N) return ("0a000000-0000-4000-8000-" + $N.ToString("000000000000")) }
function Start-Case {
    # A clean waker and an empty ledger: no case sees another's sessions or back-off.
    Reset-HordeMemoryWaker
    $script:ledger = @{}
}
function Seat {
    # One session that qualifies for a nudge - reachable, one unread mail a minute old, idle, empty box,
    # not mid-turn - with -Change laid over it, so each case breaks exactly the one thing it is about.
    param([int]$N = 1, [hashtable]$Change = @{})
    $p = @{ Id = (Sid $N); Role = "orc"; UnreadCount = 1; OldestUnreadAt = (At -60) }
    foreach ($k in $Change.Keys) { $p[$k] = $Change[$k] }
    Set-HordeMemoryWakerSession @p
}
function Pass {
    # One pass at t0 + -Seconds, carrying the ledger on. Returns the pass's result.
    param([double]$Seconds = 0, [switch]$Shadow, $Using = $settings)
    Set-HordeMemoryWakerClock (At $Seconds)
    $r = Invoke-HordeWakePass -Waker $memory -Now (At $Seconds) -Settings $Using -Ledger $script:ledger -Shadow:$Shadow
    $script:ledger = $r.ledger
    return $r
}
function Decided { param($Result, [int]$N = 1) return @($Result.decisions | Where-Object { $_.id -ceq (Sid $N) }) | Select-Object -First 1 }
function Rang { param([int]$N = 0) if ($N -gt 0) { return @(Get-HordeMemoryWakerNudges -Id (Sid $N)).Count }; return @(Get-HordeMemoryWakerNudges).Count }
function Kinds { param($Result) return (@($Result.entries | ForEach-Object { $_.kind }) -join ",") }
function Test-Held {
    # The one seated session was not nudged, was told to wait for -Like, and nothing was rung.
    param($Result, [string]$Like)
    $d = Decided $Result
    return ($null -ne $d -and $d.action -ceq "wait" -and "$($d.reason)".Contains($Like) -and (Rang) -eq 0 -and @($Result.entries | Where-Object { $_.kind -ceq "nudge" }).Count -eq 0)
}

try {

Write-Host ""
Write-Host "--- the six conditions: a session is nudged only when every one holds ---" -ForegroundColor Cyan

Start-Case; Seat
$r = Pass
$d = Decided $r
Check ($d.action -ceq "nudge" -and (Rang 1) -eq 1) "an idle session with an empty box and old unread mail is nudged"
Check ((Kinds $r) -ceq "nudge" -and $r.entries[0].id -ceq (Sid 1) -and $r.entries[0].outcome -ceq "woken" -and $r.entries[0].at -eq $t0) "and the pass journals one nudge, its session, its outcome and its time"

Start-Case; Seat -Change @{ MidTurn = "yes" }
Check (Test-Held (Pass) "midTurn is yes") "a session in the middle of a turn is not nudged"
Start-Case; Seat -Change @{ MidTurn = "unknown" }
Check (Test-Held (Pass) "midTurn is unknown") "a session whose turn could not be read is not nudged: unknown is not permission"
Start-Case; Seat -Change @{ BoxEmpty = "no" }
Check (Test-Held (Pass) "boxEmpty is no") "a session with text in its input box is not nudged"
Start-Case; Seat -Change @{ BoxEmpty = "unknown" }
Check (Test-Held (Pass) "boxEmpty is unknown") "a session whose input box could not be read is not nudged: unknown is not permission"
Start-Case; Seat -Change @{ Idle = "unknown" }
Check (Test-Held (Pass) "idle is unknown") "a session whose idleness could not be read is not nudged: unknown is not permission"
Start-Case; Seat -Change @{ Idle = "no" }
Check (Test-Held (Pass) "idle is no") "a session that is not idle is not nudged"
Start-Case; Seat -Change @{ Reachable = "no" }
Check (Test-Held (Pass) "reachable is no") "a session that cannot be reached is not nudged"
Start-Case; Seat -Change @{ Reachable = "unknown" }
Check (Test-Held (Pass) "reachable is unknown") "a session whose reach could not be told is not nudged: unknown is not permission"
Start-Case; Seat -Change @{ OldestUnreadAt = (At -2) }
Check (Test-Held (Pass) "younger than 3 s") "a session whose mail is younger than minUnreadSeconds is not nudged yet"
Start-Case; Seat -Change @{ OldestUnreadAt = (At -3) }
$r = Pass
Check ((Decided $r).action -ceq "nudge" -and (Rang 1) -eq 1) "and at exactly minUnreadSeconds it is"
Start-Case; Seat -Change @{ UnreadCount = 0; OldestUnreadAt = $null }
$r = Pass
Check ((Decided $r).action -ceq "skip" -and (Decided $r).reason -ceq "no unread mail" -and (Rang) -eq 0 -and @($r.entries).Count -eq 0) "a session with no unread mail is skipped, and nothing is journaled for it"
Start-Case; Seat -Change @{ UnreadCount = 0; OldestUnreadAt = $null; BoxEmpty = "unknown"; Idle = "unknown" }
Check ((Decided (Pass)).action -ceq "skip") "with no mail there is nothing to wait for, whatever could not be read"

Write-Host ""
Write-Host "--- back-off: 5, 15, 45, 135, then 300 s for good ---" -ForegroundColor Cyan

Start-Case; Seat -Change @{ Outcome = "busy"; OutcomeReason = "it began a turn as the nudge arrived" }
$times = New-Object System.Collections.ArrayList
for ($s = 0; $s -le 810; $s++) {
    $r = Pass $s
    foreach ($e in @($r.entries | Where-Object { $_.kind -ceq "nudge" })) { [void]$times.Add($s) }
}
$gaps = @(); for ($i = 1; $i -lt $times.Count; $i++) { $gaps += ($times[$i] - $times[$i - 1]) }
Check (($gaps -join "/") -ceq "5/15/45/135/300/300") ("a session that answers busy every time is asked again after 5, 15, 45, 135, 300 and 300 s (" + ($gaps -join "/") + ")")
Check ($script:ledger[(Sid 1)].attempts -eq 7 -and $script:ledger[(Sid 1)].lastOutcome -ceq "busy" -and $script:ledger[(Sid 1)].lastAttemptAt -eq (At 800)) "the ledger holds its attempts, its last outcome and when"
$r = Pass 811
Check ((Decided $r).action -ceq "wait" -and "$((Decided $r).reason)".Contains("back-off")) "and between attempts it waits, saying it is backing off"
Check ((Get-HordeWakeBackoffSeconds -Attempts 0 -Settings $settings) -eq 0 -and (Get-HordeWakeBackoffSeconds -Attempts 1 -Settings $settings) -eq 5 -and (Get-HordeWakeBackoffSeconds -Attempts 5 -Settings $settings) -eq 300 -and (Get-HordeWakeBackoffSeconds -Attempts 99 -Settings $settings) -eq 300) "the wait is none before any attempt, 5 s after the first, and capped at 300 s"

Write-Host ""
Write-Host "--- mail taken resets the back-off; a missed wake heals ---" -ForegroundColor Cyan

Start-Case; Seat -Change @{ Outcome = "busy"; OutcomeReason = "busy" }
$null = Pass 0; $null = Pass 5; $null = Pass 20
Check ($script:ledger.ContainsKey((Sid 1)) -and $script:ledger[(Sid 1)].attempts -eq 3) "CONTROL: three attempts are in the ledger"
Seat -Change @{ UnreadCount = 0; OldestUnreadAt = $null }
$null = Pass 21
Check (-not $script:ledger.ContainsKey((Sid 1))) "when the mail is taken the session leaves the ledger"
Seat -Change @{ OldestUnreadAt = (At 22) }
$r = Pass 25
Check ((Decided $r).action -ceq "nudge" -and (Rang 1) -eq 1 -and $script:ledger[(Sid 1)].attempts -eq 1) "and its next mail is knocked for at once, as a first attempt"

Start-Case; Seat
$r0 = Pass 0
$r3 = Pass 3
$r5 = Pass 5
Check ($r0.entries[0].outcome -ceq "woken" -and (Decided $r3).action -ceq "wait" -and (Rang 1) -eq 2 -and (Decided $r5).action -ceq "nudge") "a session that was woken and still has its mail is nudged again after its back-off: a missed wake heals"
$r6 = Pass 6
Check ((Decided $r6).action -ceq "wait" -and (Rang 1) -eq 2) "and not again before the next step of its back-off"

Start-Case; Seat -Change @{ Outcome = "busy"; OutcomeReason = "busy" }
$null = Pass 0
Seat -Change @{ Outcome = "nothing"; OutcomeReason = "its mail was taken before the nudge" }
$r = Pass 5
Check ((Kinds $r) -ceq "nudge" -and $r.entries[0].outcome -ceq "nothing" -and $r.entries[0].reason -ceq "its mail was taken before the nudge") "a nudge the waker answers nothing - the mail was taken first - is journaled as a nudge whose outcome is nothing"
Check ($script:ledger[(Sid 1)].attempts -eq 1 -and $script:ledger[(Sid 1)].lastOutcome -ceq "busy" -and $script:ledger[(Sid 1)].lastAttemptAt -eq (At 0)) "and it is not an attempt: the ledger's attempts, last outcome and time are as they were"
Start-Case; Seat -Change @{ Outcome = "nothing"; OutcomeReason = "taken" }
$null = Pass 0
Check (-not $script:ledger.ContainsKey((Sid 1))) "a first nudge answered nothing leaves no ledger entry, so no back-off starts"

$before = @{}; $before[(Sid 1)] = [pscustomobject]@{ attempts = 2; lastAttemptAt = (At 0); lastOutcome = "busy" }
$after = Update-HordeWakeLedger -Ledger $before -Decisions @([pscustomobject]@{ id = (Sid 1); action = "nudge"; reason = "" }) -Outcomes @{ (Sid 1) = "woken" } -States @{} -Now (At 50)
Check ($after[(Sid 1)].attempts -eq 3 -and $before[(Sid 1)].attempts -eq 2) "updating the ledger returns a new one and leaves the one it was given as it was"
$after = Update-HordeWakeLedger -Ledger $before -Decisions @([pscustomobject]@{ id = (Sid 1); action = "wait"; reason = "" }) -Outcomes @{ (Sid 1) = "woken" } -States @{} -Now (At 50)
Check ($after[(Sid 1)].attempts -eq 2) "an outcome for a session that was not decided nudge is not counted as an attempt"
$after = Update-HordeWakeLedger -Ledger $before -Decisions @() -Outcomes @{} -States @{} -Now (At 86401)
Check (-not $after.ContainsKey((Sid 1))) "an entry nothing has touched for a day is dropped"

Write-Host ""
Write-Host "--- ten sessions all pending (a restore of everything): one a pass, the warchief first, everyone once before anyone twice ---" -ForegroundColor Cyan

Start-Case
# Seated in an order that is NOT the order they must be served in.
Seat 5 @{ Role = "goblin"; OldestUnreadAt = (At -50) }
Seat 6 @{ Role = "goblin"; OldestUnreadAt = (At -90) }
Seat 2 @{ Role = "orc"; OldestUnreadAt = (At -30) }
Seat 9 @{ Role = "unknown"; OldestUnreadAt = (At -500) }
Seat 1 @{ Role = "warchief"; OldestUnreadAt = (At -10) }
Seat 3 @{ Role = "orc"; OldestUnreadAt = (At -40) }
Seat 7 @{ Role = "goblin"; OldestUnreadAt = (At -70) }
Seat 4 @{ Role = "orc"; OldestUnreadAt = (At -20) }
Seat 8 @{ Role = "goblin"; OldestUnreadAt = (At -60) }
Seat 10 @{ Role = "unknown"; OldestUnreadAt = (At -400) }
$first = Pass 0
Check (@($first.decisions | Where-Object { $_.action -ceq "nudge" }).Count -eq 1 -and @($first.decisions | Where-Object { $_.action -ceq "wait" -and $_.reason -ceq "rate limit" }).Count -eq 9) "in one pass one session is nudged and the other nine wait for the rate limit"
for ($i = 1; $i -lt 10; $i++) { $null = Pass ($i * 3) }
$order = @(Get-HordeMemoryWakerNudges | ForEach-Object { $_.id })
$want = @(1, 3, 2, 4, 6, 7, 8, 5, 9, 10 | ForEach-Object { Sid $_ })
Check ($order[0] -ceq (Sid 1)) "the warchief is nudged first"
Check (($order -join ",") -ceq ($want -join ",")) "then the orcs, then the goblins, then the sessions of no known role - within a role, the oldest unread mail first"
Check ($order.Count -eq 10 -and @($order | Sort-Object -Unique).Count -eq 10) "after ten passes every session was nudged exactly once"
for ($i = 10; $i -lt 20; $i++) { $null = Pass ($i * 3) }
$order = @(Get-HordeMemoryWakerNudges | ForEach-Object { $_.id })
$perSession = @($order | Group-Object | ForEach-Object { $_.Count } | Sort-Object -Unique)
Check ($order.Count -eq 20 -and ($perSession -join ",") -ceq "2") "after ten more, every session was nudged exactly twice: nobody is asked a third time while another waits for its second"
Check ($order[10] -ceq (Sid 1)) "and the second round began with the warchief again"
Start-Case
foreach ($n in 1..5) { Seat $n }
$r = Pass 0 -Using (Get-HordeWakeSettings -Overrides @{ maxNudgesPerPass = 3 })
Check ((Rang) -eq 3 -and @($r.decisions | Where-Object { $_.reason -ceq "rate limit" }).Count -eq 2) "maxNudgesPerPass is the limit: with 3, three of five are nudged in a pass"

Write-Host ""
Write-Host "--- shadow: what it would do is journaled, and none of it is done ---" -ForegroundColor Cyan

Start-Case
foreach ($n in 1..10) { Seat $n }
$script:posts = 0
$restored = @(1..5 | ForEach-Object { [pscustomobject]@{ id = (Sid $_); role = "orc"; parent = ""; startedAt = (At ($_ * 10)); lastChangeAt = (At ($_ * 10 + 2)) } })
$posted = @{}
$kinds = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt 40; $i++) {
    $now = At (400 + $i * 3)
    $r = Invoke-HordeWakePass -Waker $memory -Now $now -Settings $settings -Ledger $script:ledger -Shadow -RestoreSessions $restored -Post { param($m) $script:posts++; New-HordeKnown -Value $true } -Posted $posted
    $script:ledger = $r.ledger; $posted = $r.posted
    foreach ($e in @($r.entries)) { [void]$kinds.Add($e.kind) }
}
Check ((Rang) -eq 0) "forty shadow passes over ten pending sessions send zero nudges"
Check ($script:posts -eq 0) "and post zero mails, with a restore found and a poster in hand"
Check (@($kinds | Where-Object { $_ -notlike "would-*" }).Count -eq 0 -and @($kinds | Where-Object { $_ -ceq "would-nudge" }).Count -ge 10 -and @($kinds | Where-Object { $_ -ceq "would-post" }).Count -eq 5 -and @($kinds | Where-Object { $_ -ceq "would-stall" }).Count -eq 1) ("every journal line says would: would-nudge for each session, would-post once for each of the five restored orcs, would-stall once (" + (@($kinds | Group-Object | ForEach-Object { $_.Name + " x" + $_.Count }) -join ", ") + ")")
Check ($script:ledger.Count -eq 10 -and @($script:ledger.Values | Where-Object { $_.lastOutcome -cne "would-nudge" }).Count -eq 0) "a would-nudge still counts as an attempt, so the journal keeps a live run's rhythm"

Write-Host ""
Write-Host "--- the restore source: a replay of twelve sessions restarted inside 150 s ---" -ForegroundColor Cyan

# One warchief (1), three orcs (2 to 4), eight goblins (5 to 12: 5 to 7 under orc 2, 8 to 10 under orc 3,
# 11 and 12 under orc 4). Each started 13 s after the last, and wrote its status once, 4 s after starting.
function New-Restored {
    param([hashtable]$MovedAfter = @{})
    $out = @()
    for ($n = 1; $n -le 12; $n++) {
        $role = "goblin"; $parent = ""
        if ($n -eq 1) { $role = "warchief" } elseif ($n -le 4) { $role = "orc"; $parent = Sid 1 }
        elseif ($n -le 7) { $parent = Sid 2 } elseif ($n -le 10) { $parent = Sid 3 } else { $parent = Sid 4 }
        $start = At (($n - 1) * 13)
        $change = $start.AddSeconds(4)
        if ($MovedAfter.ContainsKey($n)) { $change = $start.AddSeconds($MovedAfter[$n]) }
        $out += [pscustomobject]@{ id = (Sid $n); role = $role; parent = $parent; startedAt = $start; lastChangeAt = $change }
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
$shifted = @($fleet | ForEach-Object { [pscustomobject]@{ id = $_.id; role = $_.role; parent = $_.parent; startedAt = $_.startedAt.AddMinutes(7); lastChangeAt = $_.lastChangeAt.AddMinutes(7) } })
$f7 = Get-HordeRestoreFinding -Sessions $shifted -Now (At 2000) -Settings $settings
Check ($f7.state -ceq "known" -and $f7.value.restoreId -cne $f.value.restoreId) "a restore that began in another minute has another id"

$plan = @(Get-HordeResumePlan -Finding $f -Now (At ($end + 10)) -Settings $settings)
$orcs = @(2, 3, 4 | ForEach-Object { Sid $_ })
Check ((@($plan | ForEach-Object { $_.to } | Sort-Object) -join ",") -ceq ($orcs -join ",") -and @($plan | Where-Object { $_.kind -cne "resume" }).Count -eq 0) "all three orcs are told to resume at once, and nobody else"
Check (@($plan | Where-Object { $_.body -cne $settings.resumeText }).Count -eq 0 -and $settings.resumeText.StartsWith("RESUME. Every session on this machine was restored")) "each with the resume text"
$plan179 = @(Get-HordeResumePlan -Finding $f -Now (At ($end + 179)) -Settings $settings)
Check ($plan179.Count -eq 3) "the goblins are still held 179 s after the last start, while no orc has moved"
$oneMoved = Get-HordeRestoreFinding -Sessions (New-Restored -MovedAfter @{ 2 = 90 }) -Now (At ($end + 100)) -Settings $settings
$planMoved = @(Get-HordeResumePlan -Finding $oneMoved -Now (At ($end + 100)) -Settings $settings)
Check ((@($planMoved | ForEach-Object { $_.to } | Sort-Object) -join ",") -ceq (@(3, 4, 5, 6, 7 | ForEach-Object { Sid $_ }) -join ",")) "once an orc has moved, its own goblins are told - not that orc again, and not the goblins of an orc still asleep"
Check (@($oneMoved.value.notMoved).Count -eq 11 -and @($oneMoved.value.members | Where-Object { $_.moved }).Count -eq 1) "a member has moved when its status changed at least movedSeconds after it started"
$barely = Get-HordeRestoreFinding -Sessions (New-Restored -MovedAfter @{ 2 = 59 }) -Now (At ($end + 100)) -Settings $settings
Check (@($barely.value.notMoved).Count -eq 12) "and has not at 59 s"
$plan180 = @(Get-HordeResumePlan -Finding $f -Now (At ($end + 180)) -Settings $settings)
Check ($plan180.Count -eq 11 -and @($plan180 | Where-Object { $_.to -ceq (Sid 1) }).Count -eq 0) "at 180 s every goblin is told too, whether or not its orc has moved - and the warchief is never told to resume"

$plan299 = @(Get-HordeResumePlan -Finding $f -Now (At ($end + 299)) -Settings $settings)
Check (@($plan299 | Where-Object { $_.kind -ceq "stall" }).Count -eq 0) "there is no stall notice 299 s after the last start"
$plan300 = @(Get-HordeResumePlan -Finding $f -Now (At ($end + 300)) -Settings $settings)
$stall = @($plan300 | Where-Object { $_.kind -ceq "stall" })
Check ($stall.Count -eq 1 -and $stall[0].to -ceq (Sid 1) -and $stall[0].body -ceq $settings.stallText) "at 300 s, with nothing moved, the warchief is told the restore has stalled"
$planLate = @(Get-HordeResumePlan -Finding (Get-HordeRestoreFinding -Sessions (New-Restored -MovedAfter @{ 7 = 200 }) -Now (At ($end + 400)) -Settings $settings) -Now (At ($end + 400)) -Settings $settings)
Check (@($planLate | Where-Object { $_.kind -ceq "stall" }).Count -eq 0) "and it is not, at any time, once one member has moved"
$noChief = Get-HordeRestoreFinding -Sessions @($fleet | Where-Object { $_.role -cne "warchief" }) -Now (At ($end + 300)) -Settings $settings
$stallNobody = @(@(Get-HordeResumePlan -Finding $noChief -Now (At ($end + 300)) -Settings $settings) | Where-Object { $_.kind -ceq "stall" })
Check ($stallNobody.Count -eq 1 -and $stallNobody[0].to -ceq "") "with no warchief among the restored sessions the stall notice is addressed to nobody, and says so"

$ids1 = (@($plan300 | Sort-Object to | ForEach-Object { $_.to + "=" + $_.messageId }) -join ";")
$ids2 = (@(Get-HordeResumePlan -Finding $again -Now (At ($end + 300)) -Settings $settings | Sort-Object to | ForEach-Object { $_.to + "=" + $_.messageId }) -join ";")
Check ($ids1 -ceq $ids2 -and $plan300.Count -eq 12) "a plan made again names every mail by the same messageId"
Check (@($plan300 | ForEach-Object { $_.messageId } | Sort-Object -Unique).Count -eq 12 -and @($plan300 | Where-Object { $_.messageId -cnotmatch '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z' }).Count -eq 0) "each mail has an id of its own, a lowercase uuid"
$orcId = @($plan | Where-Object { $_.to -ceq (Sid 2) })[0].messageId
Check (@($plan300 | Where-Object { $_.to -ceq (Sid 2) })[0].messageId -ceq $orcId) "and an orc's resume mail has the id at 300 s that it had at 10 s"

Write-Host ""
Write-Host "--- the restore source in a pass: posted once, retried when the post could not say ---" -ForegroundColor Cyan

Start-Case
$script:mails = New-Object System.Collections.ArrayList
$script:postWorks = $true
$poster = { param($m) [void]$script:mails.Add($m); if ($script:postWorks) { New-HordeKnown -Value $true } else { New-HordeUnknown -Reason "the mailbox is locked" } }
$r = Invoke-HordeWakePass -Waker $null -Now (At ($end + 10)) -Settings $settings -Ledger @{} -RestoreSessions $fleet -Post $poster -Posted @{}
Check ($script:mails.Count -eq 3 -and (Kinds $r) -ceq "post,post,post" -and @($r.entries | Where-Object { $_.outcome -cne "posted" -or $_.messageId -eq "" }).Count -eq 0) "with no waker at all the restore half still runs: three resume mails are posted, each journaled with its messageId"
$r2 = Invoke-HordeWakePass -Waker $null -Now (At ($end + 13)) -Settings $settings -Ledger @{} -RestoreSessions $fleet -Post $poster -Posted $r.posted
Check ($script:mails.Count -eq 3 -and @($r2.entries).Count -eq 0) "the next pass posts none of them again"
$script:postWorks = $false
$r3 = Invoke-HordeWakePass -Waker $null -Now (At ($end + 180)) -Settings $settings -Ledger @{} -RestoreSessions $fleet -Post $poster -Posted $r2.posted
Check ($script:mails.Count -eq 11 -and @($r3.entries | Where-Object { $_.outcome -ceq "unknown" -and $_.reason -ceq "the mailbox is locked" }).Count -eq 8 -and $r3.posted.Count -eq 3) "a post that could not say is journaled unknown with its reason, and is not marked posted"
$script:postWorks = $true
$r4 = Invoke-HordeWakePass -Waker $null -Now (At ($end + 183)) -Settings $settings -Ledger @{} -RestoreSessions $fleet -Post $poster -Posted $r3.posted
Check ($script:mails.Count -eq 19 -and $r4.posted.Count -eq 11) "so the next pass tries those eight again, under the same ids"
$r5 = Invoke-HordeWakePass -Waker $null -Now (At ($end + 300)) -Settings $settings -Ledger @{} -RestoreSessions $fleet -Post { param($m) throw "the poster fell over" } -Posted $r4.posted
Check ((Kinds $r5) -ceq "stall" -and $r5.entries[0].outcome -ceq "unknown" -and "$($r5.entries[0].reason)".Contains("fell over")) "a poster that throws is an unknown outcome, never a throw of the pass"
$r6 = Invoke-HordeWakePass -Waker $null -Now (At ($end + 300)) -Settings $settings -Ledger @{} -RestoreSessions $fleet -Posted $r4.posted
Check ((Kinds $r6) -ceq "stall" -and $r6.entries[0].outcome -ceq "unposted") "and a live pass given nothing to post through says the mail was not posted"
$r7 = Invoke-HordeWakePass -Waker $null -Now (At ($end + 10)) -Settings $settings -Ledger @{}
Check (@($r7.entries).Count -eq 0) "a pass given no sessions leaves the restore half out"

Write-Host ""
Write-Host "--- no restore: a quiet night, one restarted session, too few, too small a share ---" -ForegroundColor Cyan

$quiet = @(1..10 | ForEach-Object { [pscustomobject]@{ id = (Sid $_); role = "goblin"; parent = ""; startedAt = (At ($_ * -7200)); lastChangeAt = (At ($_ * -7200 + 3)) } })
$f = Get-HordeRestoreFinding -Sessions $quiet -Now $t0 -Settings $settings
Check ($f.state -ceq "absent" -and "$($f.reason)" -ne "") "a quiet night, with start times hours apart, is no restore, and the answer says why"
Check (@(Get-HordeResumePlan -Finding $f -Now $t0 -Settings $settings).Count -eq 0) "and nothing is planned for it"
$oneBack = @($quiet | ForEach-Object { $_ })
$oneBack[4] = [pscustomobject]@{ id = (Sid 5); role = "goblin"; parent = ""; startedAt = (At -30); lastChangeAt = (At -28) }
Check ((Get-HordeRestoreFinding -Sessions $oneBack -Now $t0 -Settings $settings).state -ceq "absent") "one restarted session among ten is no restore"
$two = @(1, 2 | ForEach-Object { [pscustomobject]@{ id = (Sid $_); role = "orc"; parent = ""; startedAt = (At ($_ * -5)); lastChangeAt = (At ($_ * -5 + 1)) } })
Check ((Get-HordeRestoreFinding -Sessions $two -Now $t0 -Settings $settings).state -ceq "absent") "two sessions that started together are fewer than a restore takes"
$twoOfThree = @($two) + [pscustomobject]@{ id = (Sid 3); role = "orc"; parent = ""; startedAt = (At -90000); lastChangeAt = (At -80000) }
Check ((Get-HordeRestoreFinding -Sessions $twoOfThree -Now $t0 -Settings $settings).state -ceq "absent") "two of three together is a large share and still fewer than a restore takes"
function New-Mixed { param([int]$Together) return @(1..10 | ForEach-Object { if ($_ -le $Together) { [pscustomobject]@{ id = (Sid $_); role = "orc"; parent = ""; startedAt = (At (-100 + $_)); lastChangeAt = (At (-98 + $_)) } } else { [pscustomobject]@{ id = (Sid $_); role = "orc"; parent = ""; startedAt = (At ($_ * -7200)); lastChangeAt = (At ($_ * -7200 + 900)) } } }) }
Check ((Get-HordeRestoreFinding -Sessions (New-Mixed 5) -Now $t0 -Settings $settings).state -ceq "absent") "five of ten together is under the share a restore takes"
$six = Get-HordeRestoreFinding -Sessions (New-Mixed 6) -Now $t0 -Settings $settings
Check ($six.state -ceq "known" -and @($six.value.members).Count -eq 6) "six of ten together is a restore, of those six"
$wide = @(1..4 | ForEach-Object { [pscustomobject]@{ id = (Sid $_); role = "orc"; parent = ""; startedAt = (At ($_ * 300)); lastChangeAt = (At ($_ * 300 + 1)) } })
$w = Get-HordeRestoreFinding -Sessions $wide -Now (At 2000) -Settings $settings
Check ($w.state -ceq "known" -and @($w.value.members).Count -eq 3 -and $w.value.windowStart -eq (At 300)) "the window is restoreWindowSeconds long: of four sessions 300 s apart, three fall in one"
Check ((Get-HordeRestoreFinding -Sessions $fleet -Now (At ($end + 86401)) -Settings $settings).state -ceq "absent") "a restore more than a day old is history"
Check ((Get-HordeRestoreFinding -Sessions @() -Now $t0 -Settings $settings).state -ceq "absent") "no sessions at all is no restore"

Write-Host ""
Write-Host "--- an adapter that throws or answers rubbish is unknown, and never a nudge ---" -ForegroundColor Cyan

foreach ($kind in @("throw", "garbage")) {
    Start-Case; Seat
    Set-HordeMemoryWakerFault -Call "targets" -Kind $kind
    $r = Pass
    Check ((Kinds $r) -ceq "skip-unknown" -and $r.entries[0].id -ceq "" -and (Rang) -eq 0 -and $script:ledger.Count -eq 0) ("targets (" + $kind + "): the pass journals that the targets are unknown, and nudges nobody")
    Start-Case; Seat
    Set-HordeMemoryWakerFault -Call "state" -Kind $kind
    $r = Pass
    Check ((Kinds $r) -ceq "skip-unknown" -and $r.entries[0].id -ceq (Sid 1) -and (Decided $r).action -ceq "wait" -and "$((Decided $r).reason)".Contains("unknown") -and (Rang) -eq 0) ("state (" + $kind + "): the session waits, the pass journals that its state is unknown, and nudges nobody")
    Start-Case; Seat
    Set-HordeMemoryWakerFault -Call "nudge" -Kind $kind
    $r = Pass
    Check ((Kinds $r) -ceq "nudge" -and $r.entries[0].outcome -ceq "unknown" -and (Rang) -eq 0 -and $script:ledger[(Sid 1)].lastOutcome -ceq "unknown") ("nudge (" + $kind + "): the outcome is unknown, and it counts as an attempt so a failing waker is not hammered")
}
Start-Case; Seat 1; Seat 2 -Change @{ UnreadCount = 2; OldestUnreadAt = $null }
$r = Pass
Check ((Decided $r 2).action -ceq "wait" -and (Decided $r 1).action -ceq "nudge" -and (Rang 2) -eq 0) "one session whose state the port refused does not stop another from being nudged"
$d = @(Get-HordeWakeDecisions -Targets @([pscustomobject]@{ id = (Sid 1); label = ""; role = "orc"; parent = ""; reachable = "yes" }) -States @{} -Ledger @{} -Now $t0 -Settings $settings)
Check ($d.Count -eq 1 -and $d[0].action -ceq "wait" -and "$($d[0].reason)".Contains("unknown")) "a target with no state answer at all waits: missing is unknown"
Check (Throws { Get-HordeWakeSettings -Overrides @{ maxNudgePerPass = 9 } } "not a wake setting") "a setting that is not one is refused, not silently left at its default"

Write-Host ""
Write-Host "--- the journal says an unknown once, not every pass ---" -ForegroundColor Cyan

$u1 = New-HordeWakeEntry -At $t0 -Kind "skip-unknown" -Id (Sid 1) -Outcome "unknown" -Reason "locked"
$n1 = New-HordeWakeEntry -At $t0 -Kind "would-nudge" -Id (Sid 2) -Outcome "would-nudge" -Reason "x"
$s1 = Select-HordeWakeNewEntries -Entries @($u1, $n1) -Unknown @{}
Check (@($s1.entries).Count -eq 2 -and $s1.unknown[(Sid 1)] -ceq "locked") "an unknown that starts is written, with everything else"
$s2 = Select-HordeWakeNewEntries -Entries @($u1, $n1) -Unknown $s1.unknown
Check (@($s2.entries).Count -eq 1 -and $s2.entries[0].kind -ceq "would-nudge") "the same unknown on the next pass is not written again; a nudge always is"
$u2 = New-HordeWakeEntry -At $t0 -Kind "skip-unknown" -Id (Sid 1) -Outcome "unknown" -Reason "gone"
Check (@((Select-HordeWakeNewEntries -Entries @($u2) -Unknown $s2.unknown).entries).Count -eq 1) "a new reason is written"
$s3 = Select-HordeWakeNewEntries -Entries @() -Unknown $s2.unknown
Check (@((Select-HordeWakeNewEntries -Entries @($u1) -Unknown $s3.unknown).entries).Count -eq 1) "and an unknown that ended and came back is written again"

Write-Host ""
Write-Host "--- the files: journal, heartbeat and ledger, under a home of this suite's ---" -ForegroundColor Cyan

$wakeDir = Get-HordeWakeFolder
Check ($wakeDir -ceq (Join-Path $pinned.home "wake") -and -not (Test-Path -LiteralPath $wakeDir)) "CONTROL: the wake folder is in this suite's home, and reading where it is did not make it"
Check ((Read-HordeWakeHeartbeat).state -ceq "absent") "with no heartbeat the watcher has never run here: absent"
Check (@(Read-HordeWakeJournalTail).Count -eq 0) "and the journal has no lines"
Check ((Read-HordeWakeLedger).state -ceq "absent") "and no ledger was saved"
Check ((Write-HordeWakeJournal -Entries @()) -eq 0 -and -not (Test-Path -LiteralPath $wakeDir)) "journaling nothing writes nothing"
$entries = @(1..12 | ForEach-Object { New-HordeWakeEntry -At (At $_) -Kind "would-nudge" -Id (Sid $_) -Outcome "would-nudge" -Reason "unread mail, idle, empty box" })
$entries += New-HordeWakeEntry -At (At 13) -Kind "would-post" -Id (Sid 2) -Outcome "would-post" -Reason "restore x" -MessageId "0d000000-0000-4000-8000-000000000001"
Check ((Write-HordeWakeJournal -Entries $entries) -eq 13) "thirteen entries are thirteen journal lines"
$tail = @(Read-HordeWakeJournalTail -Count 10)
$last = $tail[9] | ConvertFrom-Json
$firstOfTail = $tail[0] | ConvertFrom-Json
Check ($tail.Count -eq 10 -and $firstOfTail.id -ceq (Sid 4) -and $last.kind -ceq "would-post" -and $last.messageId -ceq "0d000000-0000-4000-8000-000000000001" -and $last.at -ceq "2026-10-12T08:00:13.0000000Z") "the tail is the last ten, each a line of JSON with its time in UTC, and a mail's line carries its messageId"
Check ($null -eq $firstOfTail.PSObject.Properties["messageId"]) "a nudge's line carries none"
$null = Write-HordeWakeJournal -Entries @($entries[0])
Check (@(Read-HordeWakeJournalTail -Count 100).Count -eq 14) "the journal is appended to, never replaced"

Write-HordeWakeHeartbeat -At (At 5) -ProcessId 4242 -Pass 7 -Shadow
$beat = Read-HordeWakeHeartbeat
Check ($beat.state -ceq "known" -and $beat.value.at -eq (At 5) -and $beat.value.pid -eq 4242 -and $beat.value.pass -eq 7 -and $beat.value.shadow -eq $true) "a heartbeat reads back as it was written: when, which process, which pass, and that it was shadow"
Write-HordeWakeHeartbeat -At (At 8) -ProcessId 4242 -Pass 8
$beat = Read-HordeWakeHeartbeat
Check ($beat.value.pass -eq 8 -and $beat.value.shadow -eq $false -and @(Get-ChildItem -LiteralPath $wakeDir -Filter "*.tmp").Count -eq 0) "the next one replaces it whole, and leaves no temporary file"
[System.IO.File]::WriteAllText((Join-Path $wakeDir "heartbeat.json"), "{ not json")
Check ((Read-HordeWakeHeartbeat).state -ceq "unknown") "a heartbeat that cannot be read is unknown, not absent"
Check ((Get-HordeWakeStaleSeconds) -eq 120) "a heartbeat is stale after 120 s"

$keep = @{}
$keep[(Sid 1)] = [pscustomobject]@{ attempts = 4; lastAttemptAt = (At 200); lastOutcome = "busy" }
$keep[(Sid 2)] = [pscustomobject]@{ attempts = 1; lastAttemptAt = (At 3); lastOutcome = "would-nudge" }
Save-HordeWakeLedger -Ledger $keep -Posted @{ "0d000000-0000-4000-8000-000000000001" = $true }
$back = Read-HordeWakeLedger
Check ($back.state -ceq "known" -and $back.value.ledger.Count -eq 2 -and $back.value.ledger[(Sid 1)].attempts -eq 4 -and $back.value.ledger[(Sid 1)].lastAttemptAt -eq (At 200) -and $back.value.ledger[(Sid 1)].lastOutcome -ceq "busy" -and $back.value.posted.ContainsKey("0d000000-0000-4000-8000-000000000001")) "a saved ledger reads back: each session's attempts, time and outcome, and the mails already posted"
Start-Case; Seat -Change @{ Outcome = "busy"; OutcomeReason = "busy" }
$script:ledger = $back.value.ledger
$r = Pass 300
Check ((Decided $r).action -ceq "wait" -and "$((Decided $r).reason)".Contains("back-off")) "so a watcher that was restarted keeps the back-off it had"
Save-HordeWakeLedger -Ledger @{} -Posted @{}
$back = Read-HordeWakeLedger
Check ($back.state -ceq "known" -and $back.value.ledger.Count -eq 0 -and $back.value.posted.Count -eq 0) "an empty ledger saves and reads back empty"
[System.IO.File]::WriteAllText((Join-Path $wakeDir "ledger.json"), '{"schemaVersion":1,"sessions":[{"id":"x"}],"posted":[]}')
Check ((Read-HordeWakeLedger).state -ceq "unknown") "a saved ledger with a broken entry is unknown, never half a ledger"

Write-Host ""
Write-Host "--- the running sessions, from the two stores handed in ---" -ForegroundColor Cyan

function New-Record {
    param($StartedAt, $StatusAt, [string]$Agent = "agent-one")
    $fields = @{}
    $fields["agent"] = New-HordeKnown -Value $Agent
    $fields["startedAt"] = $(if ($null -ne $StartedAt) { New-HordeKnown -Value $StartedAt } else { New-HordeUnknown -Reason "the agent writes no start" })
    $fields["liveStatus"] = $(if ($null -ne $StatusAt) { New-HordeKnown -Value "idle" -ObservedAt $StatusAt } else { New-HordeUnknown -Reason "the process is gone" })
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
$records[(Sid 2)] = New-Record (At 13) (At 80)
$records[(Sid 3)] = New-Record (At 26) $null
$records[(Sid 4)] = New-Record $null (At 30)
$records[(Sid 5)] = New-Record (At 39) (At 41) "agent-two"
$registry = New-Registry @{ (Sid 1) = @{ role = "master" }; (Sid 2) = @{ role = "orchestrator"; parent = (Sid 1) }; (Sid 5) = @{ parent = (Sid 2); role = "" } }
$a = Get-HordeRestoreSessions -Identity (New-Listing $records) -Registry $registry
Check ($a.state -ceq "known" -and @($a.leftOut).Count -eq 0) "with every listing whole nothing is left out"
$got = @()
if ($a.state -ceq "known") { $got = @($a.value | Sort-Object id) }
Check ($a.state -ceq "known" -and (@($got | ForEach-Object { $_.id }) -join ",") -ceq (@(1, 2, 5 | ForEach-Object { Sid $_ }) -join ",")) "only a session whose start and live status are both known is a running session"
Check ($got.Count -eq 3 -and $got[0].role -ceq "warchief" -and $got[1].role -ceq "orc" -and $got[1].parent -ceq (Sid 1) -and $got[0].parent -ceq "") "role and parent come from the registry record, the stored role names read as Horde's"
Check ($got.Count -eq 3 -and $got[2].role -ceq "unknown" -and $got[2].parent -ceq (Sid 2)) "a record with no role is unknown, never guessed"
Check ($got.Count -eq 3 -and $got[1].startedAt -eq (At 13) -and $got[1].lastChangeAt -eq (At 80)) "startedAt is the session's own, and lastChangeAt is when its live status was written"
$a = Get-HordeRestoreSessions -Identity (New-Listing $records -Whole (New-HordeUnknown -Reason "one control file could not be read")) -Registry $registry
$got = @()
if ($a.state -ceq "known") { $got = @($a.value | Sort-Object id) }
Check ($a.state -ceq "known" -and (@($got | ForEach-Object { $_.id }) -join ",") -ceq (@(1, 2 | ForEach-Object { Sid $_ }) -join ",")) "with one agent's listing whole and the other's not, the answer is known, with the whole one's sessions and none of the other's"
Check ($a.state -ceq "known" -and @($a.leftOut).Count -eq 1 -and $a.leftOut[0].agent -ceq "agent-two" -and $a.leftOut[0].reason -ceq "one control file could not be read") "and it names the agent it left out, and why"
Check ((Get-HordeRestoreFinding -Sessions $a.value -Now (At 100) -Settings (Get-HordeWakeSettings -Overrides @{ restoreMinSessions = 2 })).state -ceq "known") "its value is still the plain list the restore finding takes"
$a = Get-HordeRestoreSessions -Identity (New-Listing $records -Whole (New-HordeUnknown -Reason "one control file could not be read") -WholeOne (New-HordeUnknown -Reason "there is no control directory")) -Registry $registry
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("agent-one: there is no control directory") -and "$($a.reason)".Contains("agent-two: one control file could not be read")) "with no agent's listing whole the answer is unknown, naming each and why"
$a = Get-HordeRestoreSessions -Identity (New-Listing $records) -Registry (New-Registry @{} -Whole (New-HordeUnknown -Reason "there is no registry"))
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("registry")) "and so is a registry that is not whole"
$a = Get-HordeRestoreSessions -Identity (New-Listing @{}) -Registry (New-Registry @{})
Check ($a.state -ceq "known" -and @($a.value).Count -eq 0) "an empty fleet is a known empty list"

} finally {
    Reset-HordeMemoryWaker
    Exit-HordeTestPinnedHome -State $pinned
    Exit-HordeTestEmptyFleet -Pin $fleetPin
}

Complete-HordeSuite -Success "the watcher nudges only what it could read and should wake, backs off, heals, queues a restore fairly, and in shadow does nothing"
