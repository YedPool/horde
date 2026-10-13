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
#   - SHADOW rings nobody.
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
Check ($script:ledger[(Sid 1)].attempts -eq 0 -and $script:ledger[(Sid 1)].nothingAt -eq (At 0)) "a first nudge answered nothing is no attempt, and is recorded as a hold"

Write-Host ""
Write-Host "--- a session that answers nothing while its state still shows unread mail does not hold the slot ---" -ForegroundColor Cyan

Start-Case
Seat 1 @{ Role = "warchief"; Outcome = "nothing"; OutcomeReason = "its mailbox is empty" }
$lines = 0
for ($i = 0; $i -lt 20; $i++) { $r = Pass ($i * 3); $lines += @($r.entries).Count }
$asked = @(Get-HordeMemoryWakerAsks)
Check ($asked.Count -eq 10) ("over twenty passes, 3 s apart, it is asked on every other one, not on every one: it is held for the first step of the back-off (" + $asked.Count + ")")
Check ($lines -eq 1) ("and the run of nothings is journaled once, not every pass (" + $lines + ")")
Check ($script:ledger[(Sid 1)].attempts -eq 0) "it is still no attempt: nothing escalates"
$held = Pass 58
Check ((Decided $held 1).action -ceq "wait" -and "$((Decided $held 1).reason)".Contains("held")) "while it is held it waits, and says it is held"
# Two others turn up while it is ready again: one never asked, one asked once and past its back-off.
Seat 2 @{ Role = "goblin" }
Seat 3 @{ Role = "goblin" }
$script:ledger[(Sid 3)] = [pscustomobject]@{ attempts = 1; lastAttemptAt = (At 0); lastOutcome = "busy" }
$r = Pass 63
Check ((Decided $r 2).action -ceq "nudge" -and (Decided $r 1).reason -ceq "rate limit") "a session never asked goes ahead of it, warchief or not"
$r = Pass 66
Check ((Decided $r 3).action -ceq "nudge" -and (Decided $r 1).reason -ceq "rate limit") "and so does one asked before: it is behind every other ready session, so it starves nobody"
Seat 2 @{ Role = "goblin"; UnreadCount = 0; OldestUnreadAt = $null }
Seat 3 @{ Role = "goblin"; UnreadCount = 0; OldestUnreadAt = $null }
Seat 1 @{ Role = "warchief" }
$r = Pass 69
Check ((Kinds $r) -ceq "nudge" -and $r.entries[0].outcome -ceq "woken" -and $null -eq (Get-HordeWakeNothingAt $script:ledger[(Sid 1)]) -and $script:ledger[(Sid 1)].attempts -eq 1) "a real attempt ends the hold, and counts as the first"
Seat 1 @{ Role = "warchief"; Outcome = "nothing"; OutcomeReason = "its mailbox is empty" }
$r = Pass 80
Check ((Kinds $r) -ceq "nudge" -and $r.entries[0].outcome -ceq "nothing") "and a new run of nothings is journaled again, once"
Save-HordeWakeLedger -Ledger $script:ledger
$back = Read-HordeWakeLedger
Check ($back.state -ceq "known" -and (Get-HordeWakeNothingAt $back.value.ledger[(Sid 1)]) -eq (At 80) -and $back.value.ledger[(Sid 1)].attempts -eq 1 -and -not $back.value.ledger.ContainsKey((Sid 2))) "the hold is saved with the ledger and read back, and a session with none has none"
Remove-Item -LiteralPath (Get-HordeWakeFolder) -Recurse -Force

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
$kinds = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt 40; $i++) {
    $r = Pass (400 + $i * 3) -Shadow
    foreach ($e in @($r.entries)) { [void]$kinds.Add($e.kind) }
}
Check ((Rang) -eq 0) "forty shadow passes over ten pending sessions send zero nudges"
Check (@($kinds | Where-Object { $_ -cne "would-nudge" }).Count -eq 0 -and $kinds.Count -ge 10) ("every journal line says would-nudge, at least one for each session (" + $kinds.Count + ")")
Check ($script:ledger.Count -eq 10 -and @($script:ledger.Values | Where-Object { $_.lastOutcome -cne "would-nudge" }).Count -eq 0) "a would-nudge still counts as an attempt, so the journal keeps a live run's rhythm"

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
Write-Host "--- mail nobody can read: said once, when it lasts two passes, and never a reason not to nudge ---" -ForegroundColor Cyan

Start-Case; Seat -Change @{ UnreadableCount = 1 }
$r = Pass 0
Check ((Decided $r).action -ceq "nudge" -and (Rang 1) -eq 1 -and $r.unreadable[(Sid 1)] -eq 1) "a session with good mail and one record nobody can read is nudged for the good mail, and the pass hands the count on"
Start-Case; Seat -Change @{ UnreadableCount = 0 }
Check ((Pass 0).unreadable.Count -eq 0) "a session with no such record is not handed on"
$b1 = Update-HordeWakeBadMail -Seen @{} -Unreadable @{ (Sid 1) = 2 } -Now (At 0)
Check (@($b1.entries).Count -eq 0 -and $b1.seen[(Sid 1)].passes -eq 1) "seen on one pass, nothing is said yet: a record being written is unreadable for a moment"
$b2 = Update-HordeWakeBadMail -Seen $b1.seen -Unreadable @{ (Sid 1) = 2 } -Now (At 3)
Check (@($b2.entries).Count -eq 1 -and $b2.entries[0].kind -ceq "bad-mail" -and $b2.entries[0].id -ceq (Sid 1) -and $b2.entries[0].outcome -ceq "unreadable" -and "$($b2.entries[0].reason)".StartsWith("2 record(s)") -and $b2.entries[0].at -eq (At 3)) "seen on two passes in a row, one bad-mail entry is made, naming the session and how many"
$b3 = Update-HordeWakeBadMail -Seen $b2.seen -Unreadable @{ (Sid 1) = 2 } -Now (At 6)
$b4 = Update-HordeWakeBadMail -Seen $b3.seen -Unreadable @{ (Sid 1) = 5 } -Now (At 9)
Check (@($b3.entries).Count -eq 0 -and @($b4.entries).Count -eq 0) "and no other while it lasts, whatever the count becomes"
$b5 = Update-HordeWakeBadMail -Seen $b4.seen -Unreadable @{} -Now (At 12)
Check ($b5.seen.Count -eq 0) "a pass on which it shows none forgets it"
$b6 = Update-HordeWakeBadMail -Seen $b5.seen -Unreadable @{ (Sid 1) = 1 } -Now (At 15)
$b7 = Update-HordeWakeBadMail -Seen $b6.seen -Unreadable @{ (Sid 1) = 1 } -Now (At 18)
Check (@($b6.entries).Count -eq 0 -and @($b7.entries).Count -eq 1) "so one that comes back is told again, after two passes again"
$gap = Update-HordeWakeBadMail -Seen (Update-HordeWakeBadMail -Seen $b1.seen -Unreadable @{} -Now (At 3)).seen -Unreadable @{ (Sid 1) = 2 } -Now (At 6)
Check (@($gap.entries).Count -eq 0) "two sightings with a clear pass between them are not two in a row"
$two = Update-HordeWakeBadMail -Seen (Update-HordeWakeBadMail -Seen @{} -Unreadable @{ (Sid 1) = 1; (Sid 2) = 0 } -Now (At 0)).seen -Unreadable @{ (Sid 1) = 1; (Sid 2) = 3 } -Now (At 3)
Check (@($two.entries).Count -eq 1 -and $two.entries[0].id -ceq (Sid 1)) "each session is counted by itself, and a count of 0 is not a sighting"

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
Check ((Get-HordeWakeStaleSeconds) -eq 120 -and (Get-HordeWakeStaleSeconds -TickSeconds 3) -eq 120 -and (Get-HordeWakeStaleSeconds -TickSeconds 40) -eq 120) "a heartbeat is stale after 120 s, for any tick up to 40 s"
Check ((Get-HordeWakeStaleSeconds -TickSeconds 41) -eq 123 -and (Get-HordeWakeStaleSeconds -TickSeconds 300) -eq 900) "and after three ticks for a slower watcher: stale is relative to how often it beats"
Write-HordeWakeHeartbeat -At (At 9) -ProcessId 4242 -Pass 9 -TickSeconds 60
Check ((Read-HordeWakeHeartbeat).value.tickSeconds -eq 60) "the heartbeat carries the tick, so a reader knows what stale is for this watcher"
[System.IO.File]::WriteAllText((Join-Path $wakeDir "heartbeat.json"), '{"at":"2026-10-12T08:00:05.0000000Z","pid":1,"pass":2,"shadow":true}')
Check ((Read-HordeWakeHeartbeat).value.tickSeconds -eq 0) "a heartbeat written before it carried one reads as no tick, which is the 120 s floor"

# THE JOURNAL IS BOUNDED: at the cap it is set aside, once, and the tail still reads across the two.
$small = Join-Path $pinned.home "rotate"
$line = New-HordeWakeEntry -At (At 1) -Kind "would-nudge" -Id (Sid 1) -Outcome "would-nudge" -Reason ("x" * 100)
foreach ($n in 1..6) { $null = Write-HordeWakeJournal -Entries @($line) -HordeHome $small -MaxBytes 400 }
$files = @(Get-ChildItem -LiteralPath (Join-Path $small "wake") | ForEach-Object { $_.Name } | Sort-Object)
Check (($files -join ",") -ceq "journal.1.jsonl,journal.jsonl") ("past its cap the journal is set aside as journal.1.jsonl, and there are never more than the two (" + ($files -join ",") + ")")
Check ((Get-Item -LiteralPath (Join-Path $small "wake\journal.jsonl")).Length -lt 800) "the journal that is written to stays under twice the cap"
$last = New-HordeWakeEntry -At (At 2) -Kind "would-nudge" -Id (Sid 9) -Outcome "would-nudge" -Reason "the newest"
foreach ($n in 1..3) { $null = Write-HordeWakeJournal -Entries @($line) -HordeHome $small -MaxBytes 400 }
$null = Write-HordeWakeJournal -Entries @($last) -HordeHome $small -MaxBytes 400
$tail = @(Read-HordeWakeJournalTail -Count 4 -HordeHome $small)
Check ($tail.Count -eq 4 -and ($tail[3] | ConvertFrom-Json).reason -ceq "the newest") "the tail is still the newest lines, filled from the journal set aside when the new one is short"

$keep = @{}
$keep[(Sid 1)] = [pscustomobject]@{ attempts = 4; lastAttemptAt = (At 200); lastOutcome = "busy" }
$keep[(Sid 2)] = [pscustomobject]@{ attempts = 1; lastAttemptAt = (At 3); lastOutcome = "would-nudge" }
Save-HordeWakeLedger -Ledger $keep
$back = Read-HordeWakeLedger
Check ($back.state -ceq "known" -and $back.value.ledger.Count -eq 2 -and $back.value.ledger[(Sid 1)].attempts -eq 4 -and $back.value.ledger[(Sid 1)].lastAttemptAt -eq (At 200) -and $back.value.ledger[(Sid 1)].lastOutcome -ceq "busy") "a saved ledger reads back: each session's attempts, time and outcome"
Start-Case; Seat -Change @{ Outcome = "busy"; OutcomeReason = "busy" }
$script:ledger = $back.value.ledger
$r = Pass 300
Check ((Decided $r).action -ceq "wait" -and "$((Decided $r).reason)".Contains("back-off")) "so a watcher that was restarted keeps the back-off it had"
Save-HordeWakeLedger -Ledger @{}
$back = Read-HordeWakeLedger
Check ($back.state -ceq "known" -and $back.value.ledger.Count -eq 0) "an empty ledger saves and reads back empty"
Save-HordeWakeLedger -Ledger $keep -Shadow
Check ((Test-Path -LiteralPath (Join-Path $wakeDir "ledger-shadow.json") -PathType Leaf) -and (Read-HordeWakeLedger).value.ledger.Count -eq 0 -and (Read-HordeWakeLedger -Shadow).value.ledger.Count -eq 2) "a shadow run's ledger is a file of its own: saving it leaves the live ledger as it was, and each reads back its own"
[System.IO.File]::WriteAllText((Join-Path $wakeDir "ledger.json"), '{"schemaVersion":1,"sessions":[{"id":"x"}]}')
Check ((Read-HordeWakeLedger).state -ceq "unknown") "a saved ledger with a broken entry is unknown, never half a ledger"

} finally {
    Reset-HordeMemoryWaker
    Exit-HordeTestPinnedHome -State $pinned
    Exit-HordeTestEmptyFleet -Pin $fleetPin
}

Complete-HordeSuite -Success "the watcher nudges only what it could read and should wake, backs off, heals, queues a restore fairly, and in shadow does nothing"
