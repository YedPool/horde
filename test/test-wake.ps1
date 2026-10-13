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
    $r = Invoke-HordeWakePass -Waker $memory -Now (At $Seconds) -Settings $Using -Ledger $script:ledger -Send:(-not $Shadow)
    $script:ledger = $r.ledger
    return $r
}
function Decided { param($Result, [int]$N = 1) return @($Result.decisions | Where-Object { $_.id -ceq (Sid $N) }) | Select-Object -First 1 }
function Rang { param([int]$N = 0) if ($N -gt 0) { return @(Get-HordeMemoryWakerNudges -Id (Sid $N)).Count }; return @(Get-HordeMemoryWakerNudges).Count }
function Kinds { param($Result) return (@($Result.entries | ForEach-Object { $_.kind }) -join ",") }
function Test-Held2 {
    # Like Test-Held, for a session that has been rung before: it waits for -Like, and this pass rang nobody.
    param($Result, [string]$Like)
    $d = Decided $Result
    return ($null -ne $d -and $d.action -ceq "wait" -and "$($d.reason)".Contains($Like) -and @($Result.entries | Where-Object { $_.kind -ceq "nudge" }).Count -eq 0)
}
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
Check ((Get-HordeMemoryWakerBegins) -eq 1) "the pass told the waker once that a pass begins"
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
# The cap on nudges for one mail is lifted for this one case, which is about the back-off's own shape.
$uncapped = Get-HordeWakeSettings -Overrides @{ maxNudgesPerMail = 99 }
for ($s = 0; $s -le 810; $s++) {
    $r = Pass $s -Using $uncapped
    foreach ($e in @($r.entries | Where-Object { $_.kind -ceq "nudge" })) { [void]$times.Add($s) }
}
$gaps = @(); for ($i = 1; $i -lt $times.Count; $i++) { $gaps += ($times[$i] - $times[$i - 1]) }
Check (($gaps -join "/") -ceq "5/15/45/135/300/300") ("a session that answers busy every time is asked again after 5, 15, 45, 135, 300 and 300 s (" + ($gaps -join "/") + ")")
Check ($script:ledger[(Sid 1)].attempts -eq 7 -and $script:ledger[(Sid 1)].lastOutcome -ceq "busy" -and $script:ledger[(Sid 1)].lastAttemptAt -eq (At 800)) "the ledger holds its attempts, its last outcome and when"
$r = Pass 811 -Using $uncapped
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
Seat 2 @{ Role = "warg" }
Seat 3 @{ Role = "warg" }
$script:ledger[(Sid 3)] = [pscustomobject]@{ attempts = 1; lastAttemptAt = (At 0); lastOutcome = "busy" }
$r = Pass 63
Check ((Decided $r 2).action -ceq "nudge" -and (Decided $r 1).reason -ceq "rate limit") "a session never asked goes ahead of it, warchief or not"
$r = Pass 66
Check ((Decided $r 3).action -ceq "nudge" -and (Decided $r 1).reason -ceq "rate limit") "and so does one asked before: it is behind every other ready session, so it starves nobody"
Seat 2 @{ Role = "warg"; UnreadCount = 0; OldestUnreadAt = $null }
Seat 3 @{ Role = "warg"; UnreadCount = 0; OldestUnreadAt = $null }
Seat 1 @{ Role = "warchief" }
$r = Pass 69
Check ((Kinds $r) -ceq "nudge" -and $r.entries[0].outcome -ceq "woken" -and $null -eq (Get-HordeWakeNothingAt $script:ledger[(Sid 1)]) -and $script:ledger[(Sid 1)].attempts -eq 1) "a real attempt ends the hold, and counts as the first"
Seat 1 @{ Role = "warchief"; Outcome = "nothing"; OutcomeReason = "its mailbox is empty" }
$r = Pass 80
Check ((Kinds $r) -ceq "nudge" -and $r.entries[0].outcome -ceq "nothing") "and a new run of nothings is journaled again, once"
Save-HordeWakeLedger -Mode "live" -Ledger $script:ledger
$back = Read-HordeWakeLedger -Mode "live"
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
Seat 5 @{ Role = "warg"; OldestUnreadAt = (At -50) }
Seat 6 @{ Role = "warg"; OldestUnreadAt = (At -90) }
Seat 2 @{ Role = "orc"; OldestUnreadAt = (At -30) }
Seat 9 @{ Role = "unknown"; OldestUnreadAt = (At -500) }
Seat 1 @{ Role = "warchief"; OldestUnreadAt = (At -10) }
Seat 3 @{ Role = "orc"; OldestUnreadAt = (At -40) }
Seat 7 @{ Role = "warg"; OldestUnreadAt = (At -70) }
Seat 4 @{ Role = "orc"; OldestUnreadAt = (At -20) }
Seat 8 @{ Role = "warg"; OldestUnreadAt = (At -60) }
Seat 10 @{ Role = "unknown"; OldestUnreadAt = (At -400) }
$first = Pass 0
Check (@($first.decisions | Where-Object { $_.action -ceq "nudge" }).Count -eq 1 -and @($first.decisions | Where-Object { $_.action -ceq "wait" -and $_.reason -ceq "rate limit" }).Count -eq 9) "in one pass one session is nudged and the other nine wait for the rate limit"
for ($i = 1; $i -lt 10; $i++) { $null = Pass ($i * 3) }
$order = @(Get-HordeMemoryWakerNudges | ForEach-Object { $_.id })
$want = @(1, 3, 2, 4, 6, 7, 8, 5, 9, 10 | ForEach-Object { Sid $_ })
Check ($order[0] -ceq (Sid 1)) "the warchief is nudged first"
Check (($order -join ",") -ceq ($want -join ",")) "then the orcs, then the wargs, then the sessions of no known role - within a role, the oldest unread mail first"
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
$d = @(Get-HordeWakeDecisions -Targets @([pscustomobject]@{ id = (Sid 1); label = ""; role = "orc"; parent = ""; reachable = "yes"; retired = "no" }) -States @{} -Ledger @{} -Now $t0 -Settings $settings)
Check ($d.Count -eq 1 -and $d[0].action -ceq "wait" -and "$($d[0].reason)".Contains("unknown")) "a target with no state answer at all waits: missing is unknown"
Check (Throws { Get-HordeWakeSettings -Overrides @{ maxNudgePerPass = 9 } } "not a wake setting") "a setting that is not one is refused, not silently left at its default"

Write-Host ""
Write-Host "--- the cap: six nudges for one mail, then one gave-up line and silence until the mail changes ---" -ForegroundColor Cyan

# A SESSION THAT ANSWERS WOKEN AND NEVER TAKES ITS MAIL.
Start-Case; Seat -Change @{ OldestUnreadAt = (At -60) }
$nudges = New-Object System.Collections.ArrayList
$gave = New-Object System.Collections.ArrayList
for ($s = 0; $s -le 3600; $s += 3) {
    $r = Pass $s
    foreach ($e in @($r.entries)) { if ($e.kind -ceq "nudge") { [void]$nudges.Add($s) } elseif ($e.kind -ceq "gave-up") { [void]$gave.Add($e) } }
}
Check ((Rang 1) -eq 6 -and $nudges.Count -eq 6) ("in an hour it is nudged six times, not the fifteen it was before the cap (" + (Rang 1) + ")")
Check ($gave.Count -eq 1 -and $gave[0].id -ceq (Sid 1) -and $gave[0].outcome -ceq "gave-up" -and "$($gave[0].reason)".StartsWith("6 nudges for its mail unread since 2026-10-12T07:59:00Z") -and "$($gave[0].reason)".Contains("the last answered woken")) "and ONE gave-up line is journaled, on the pass of the sixth nudge, saying how many, for which mail and what the last answered"
Check ($gave[0].at -eq (At $nudges[5])) "at the time of that sixth nudge"
$r = Pass 3603
Check ((Decided $r).action -ceq "wait" -and "$((Decided $r).reason)".StartsWith("gave up after 6 nudges") -and @($r.entries).Count -eq 0 -and @($r.gaveUp).Count -eq 0) "after it the session waits, saying it was given up on, and nothing more is journaled"
Check ($script:ledger[(Sid 1)].gaveUp -eq $true -and $script:ledger[(Sid 1)].mailAt -eq (At -60) -and $script:ledger[(Sid 1)].attempts -eq 6) "the ledger holds that it was given up on, and for which mail"
# ANOTHER MAIL BECOMES THE OLDEST: the session took the one it was asked about, and a new one waits.
Seat -Change @{ OldestUnreadAt = (At 3600) }
$r = Pass 3606
Check ((Decided $r).action -ceq "nudge" -and (Rang 1) -eq 7 -and $script:ledger[(Sid 1)].attempts -eq 1 -and $script:ledger[(Sid 1)].mailAt -eq (At 3600) -and $null -eq (Get-HordeWakeEntryValue $script:ledger[(Sid 1)] "gaveUp")) "when another mail becomes its oldest unread it is nudged at once, as a first attempt for that mail: nothing is held against the new one"
# THE MAIL IS TAKEN, AND A LATER ONE ARRIVES.
Start-Case; Seat -Change @{ Outcome = "busy"; OutcomeReason = "busy" }
$capOne = Get-HordeWakeSettings -Overrides @{ maxNudgesPerMail = 1 }
$r = Pass 0 -Using $capOne
Check ((Kinds $r) -ceq "nudge,gave-up" -and @($r.gaveUp).Count -eq 1 -and $r.gaveUp[0].id -ceq (Sid 1) -and $r.gaveUp[0].attempts -eq 1 -and $r.gaveUp[0].mailAt -eq (At -60)) "maxNudgesPerMail is the cap: with 1, the first nudge is the last, and the pass hands on who was given up on"
$r = Pass 600 -Using $capOne
Check ((Rang) -eq 0 -and @($r.entries).Count -eq 0) "ten minutes on it is still not asked, and not said again"
Seat -Change @{ UnreadCount = 0; OldestUnreadAt = $null }
$null = Pass 603 -Using $capOne
Seat
$r = Pass 606 -Using $capOne
Check ((Decided $r).action -ceq "nudge") "once the mail is taken the session starts again from nothing"
# WHAT DOES NOT COUNT. nothing is no attempt, so a session whose waker keeps answering nothing is never given up on.
Start-Case; Seat -Change @{ Outcome = "nothing"; OutcomeReason = "its mailbox is empty" }
$gaveLines = 0
for ($s = 0; $s -le 600; $s += 3) { $r = Pass $s; $gaveLines += @($r.entries | Where-Object { $_.kind -ceq "gave-up" }).Count }
Check ($gaveLines -eq 0 -and $script:ledger[(Sid 1)].attempts -eq 0) "a session whose waker answers nothing is not given up on: nothing was tried"
# SHADOW COUNTS WHAT IT WOULD HAVE DONE, so its journal shows the cap too.
Start-Case; Seat
$kindsSeen = New-Object System.Collections.ArrayList
for ($s = 0; $s -le 3600; $s += 3) { $r = Pass $s -Shadow; foreach ($e in @($r.entries)) { [void]$kindsSeen.Add($e.kind) } }
Check ((@($kindsSeen) -join ",") -ceq "would-nudge,would-nudge,would-nudge,would-nudge,would-nudge,would-nudge,gave-up" -and (Rang) -eq 0) "a shadow run journals six would-nudges and then that it would give up, and rings nobody"
$gu = Update-HordeWakeGaveUp -Ledger @{ (Sid 1) = [pscustomobject]@{ attempts = 6; lastAttemptAt = (At 0); lastOutcome = "busy" }; (Sid 2) = [pscustomobject]@{ attempts = 5; lastAttemptAt = (At 0); lastOutcome = "busy" } } -Now (At 9) -Settings $settings
Check (@($gu.entries).Count -eq 1 -and $gu.entries[0].id -ceq (Sid 1) -and $gu.ledger[(Sid 1)].gaveUp -eq $true -and $null -eq (Get-HordeWakeEntryValue $gu.ledger[(Sid 2)] "gaveUp")) "an entry written before entries recorded their mail is capped all the same, and one below the cap is not"
Save-HordeWakeLedger -Mode "live" -Ledger $gu.ledger
$back = Read-HordeWakeLedger -Mode "live"
Check ($back.state -ceq "known" -and $back.value.ledger[(Sid 1)].gaveUp -eq $true -and $null -eq (Get-HordeWakeEntryValue $back.value.ledger[(Sid 2)] "gaveUp")) "that a session was given up on is saved with the ledger, so a restarted watcher does not say it again"
Save-HordeWakeLedger -Mode "live" -Ledger @{ (Sid 3) = (New-HordeWakeLedgerRow -Attempts 2 -LastAttemptAt (At 1) -LastOutcome "busy" -MailAt (At -60)) }
Check ((Read-HordeWakeLedger -Mode "live").value.ledger[(Sid 3)].mailAt -eq (At -60)) "and so is the mail an entry is for"
Remove-Item -LiteralPath (Get-HordeWakeFolder) -Recurse -Force

Write-Host ""
Write-Host "--- a nudge the waker had to kill: its own loud line, and the longest back-off at once ---" -ForegroundColor Cyan

Start-Case; Seat -Change @{ Outcome = "killed"; OutcomeReason = "nudge-killed: stopped after 90 s; its box may now hold the unsent line" }
$r = Pass 0
Check ((Kinds $r) -ceq "nudge-killed" -and $r.entries[0].outcome -ceq "killed" -and "$($r.entries[0].reason)".StartsWith("nudge-killed: ")) "a nudge the waker stopped part-way is journaled as nudge-killed, not as one more nudge"
Check ($script:ledger[(Sid 1)].attempts -eq 5 -and $script:ledger[(Sid 1)].lastOutcome -ceq "killed") "and the session is put on the longest back-off at once: its box may hold text"
Seat
$r = Pass 299
Check ((Decided $r).action -ceq "wait" -and "$((Decided $r).reason)".Contains("back-off") -and (Rang) -eq 0) "it is not asked again 299 s later, though it is idle with an empty box"
$r = Pass 300
Check ((Decided $r).action -ceq "nudge" -and (Rang 1) -eq 1) "and is at 300 s"
$after = Update-HordeWakeLedger -Ledger @{ (Sid 1) = [pscustomobject]@{ attempts = 7; lastAttemptAt = (At 0); lastOutcome = "busy" } } -Decisions @([pscustomobject]@{ id = (Sid 1); action = "nudge"; reason = "" }) -Outcomes @{ (Sid 1) = "killed" } -States @{} -Now (At 9) -Settings $settings
Check ($after[(Sid 1)].attempts -eq 8) "a session already past every step is counted one more, never set back"

# HOW LONG A REAL NUDGE TOOK is journaled when the waker timed it.
$timed = New-HordeWakeEntry -At $t0 -Kind "nudge" -Id (Sid 1) -Outcome "woken" -ElapsedMs 2150
$untimed = New-HordeWakeEntry -At $t0 -Kind "nudge" -Id (Sid 1) -Outcome "woken"
Check ($timed.elapsedMs -eq 2150 -and $null -eq $untimed.PSObject.Properties["elapsedMs"] -and $null -eq (New-HordeWakeEntry -At $t0 -Kind "nudge" -ElapsedMs "soon").PSObject.Properties["elapsedMs"]) "a journal line carries elapsedMs when it is given a whole number, and not otherwise"
$null = Write-HordeWakeJournal -Mode "live" -Entries @($timed, $untimed)
$written = @(Read-HordeWakeJournalTail -Mode "live" -Count 2 | ForEach-Object { $_ | ConvertFrom-Json })
Check ($null -ne $written[0].PSObject.Properties["elapsedMs"] -and $written[0].elapsedMs -eq 2150 -and $null -eq $written[1].PSObject.Properties["elapsedMs"]) "and it is written to the journal with the line"
Remove-Item -LiteralPath (Get-HordeWakeFolder) -Recurse -Force

# A PROOF RUN'S FILES ARE ITS OWN, by the mode's word; and a word that is no mode names no file.
$h7 = Join-Path $pinned.home ("modes-" + [guid]::NewGuid().ToString("N")); New-Item -ItemType Directory -Path $h7 | Out-Null
Check ((Split-Path -Leaf (Get-HordeWakeModeFile -Stem "journal" -Extension ".jsonl" -Mode "proof" -HordeHome $h7)) -ceq "journal-proof.jsonl" -and (Split-Path -Leaf (Get-HordeWakeStateFile -Name "ledger" -Mode "proof" -HordeHome $h7)) -ceq "ledger-proof.json" -and (Split-Path -Leaf (Get-HordeWakeStateFile -Name "ledger" -Mode "shadow" -HordeHome $h7)) -ceq "ledger-shadow.json" -and (Split-Path -Leaf (Get-HordeWakeStateFile -Name "ledger" -Mode "live" -HordeHome $h7)) -ceq "ledger-live.json") "each of the three modes names its own journal and state files"
$threw = 0; foreach ($word in @("LIVE", "prove", "both")) { try { $null = Get-HordeWakeStateFile -Name "ledger" -Mode $word -HordeHome $h7 } catch { $threw++ } }
Check ($threw -eq 3) "a word that is no mode - another casing, a near miss - names no file: it is refused"
Write-HordeWakeHeartbeat -At $t0 -ProcessId 7 -Pass 1 -Mode "proof" -TickSeconds 3 -HordeHome $h7
$pb = Read-HordeWakeHeartbeat -Mode "proof" -HordeHome $h7
Check ($pb.state -ceq "known" -and $pb.value.mode -ceq "proof" -and $pb.value.shadow -eq $false -and (Read-HordeWakeHeartbeat -Mode "live" -HordeHome $h7).state -ceq "absent" -and (Read-HordeWakeHeartbeat -Shadow -HordeHome $h7).state -ceq "absent") "a proof run's heartbeat says proof, is read back by that mode only, and is neither the live one nor the shadow one"
Write-HordeWakeHeartbeat -At $t0 -ProcessId 7 -Pass 1 -Shadow -HordeHome $h7
Write-HordeWakeHeartbeat -Mode "live" -At $t0 -ProcessId 7 -Pass 1 -HordeHome $h7
Check ((Read-HordeWakeHeartbeat -Shadow -HordeHome $h7).value.mode -ceq "shadow" -and (Read-HordeWakeHeartbeat -Shadow -HordeHome $h7).value.shadow -eq $true -and (Read-HordeWakeHeartbeat -Mode "live" -HordeHome $h7).value.mode -ceq "live") "and the shadow and the live heartbeat each say theirs"

Write-Host ""
Write-Host "--- the look comes last: a session's box is read only when it is about to be nudged ---" -ForegroundColor Cyan

# A WAKER WHOSE STATE IS CHEAP: the box and the turn are unknown until it is asked to look.
Start-Case; Set-HordeMemoryWakerCheap $true
foreach ($n in 1..5) { Seat $n }
$r = Pass 0
Check ((@(Get-HordeMemoryWakerLooks) -join ",") -ceq (Sid 1) -and (Rang 1) -eq 1 -and (Rang) -eq 1) "of five sessions with unread mail, one is looked at - the one that is nudged - and no other"
Check (@($r.decisions | Where-Object { $_.reason -ceq "rate limit" }).Count -eq 4 -and @($r.decisions | Where-Object { $_.action -ceq "look" }).Count -eq 0) "the other four wait for the rate limit unlooked, and no decision is left as look"
$r = Pass 3
Check ((@(Get-HordeMemoryWakerLooks) -join ",") -ceq ((Sid 1) + "," + (Sid 2)) -and (Decided $r 1).action -ceq "wait" -and "$((Decided $r 1).reason)".Contains("back-off")) "on the next pass the session that is backing off is NOT looked at again: the look is the next session's"
Start-Case; Set-HordeMemoryWakerCheap $true
Seat 1 -Change @{ Role = "warchief"; BoxEmpty = "no" }; Seat 2 -Change @{ MidTurn = "yes" }; Seat 3; Seat 4
$r = Pass 0
Check ((@(Get-HordeMemoryWakerLooks) -join ",") -ceq (@(1, 2, 3 | ForEach-Object { Sid $_ }) -join ",") -and (Rang 3) -eq 1 -and (Rang) -eq 1) "a session the look rules out - text in its box, or mid-turn - gives its place to the next, which is looked at in turn until one is nudged"
Check ((Decided $r 1).reason -ceq "boxEmpty is no" -and (Decided $r 2).reason -ceq "midTurn is yes" -and (Decided $r 4).reason -ceq "rate limit") "each says why it was not nudged, and the one behind the nudged session was never looked at"
Start-Case; Set-HordeMemoryWakerCheap $true
foreach ($n in 1..5) { Seat $n -Change @{ BoxEmpty = "no" } }
$r = Pass 0
Check (@(Get-HordeMemoryWakerLooks).Count -eq 3 -and (Rang) -eq 0) "at most maxConfirmsPerPass sessions are looked at in one pass: three of five whose boxes all hold text"
Check (@($r.decisions | Where-Object { "$($_.reason)".Contains("looks were used up") }).Count -eq 1 -and @($r.decisions | Where-Object { $_.action -ceq "look" }).Count -eq 0 -and @($r.decisions | Where-Object { $_.reason -ceq "rate limit" }).Count -eq 1) "the next in line waits, saying the pass's looks were used up, and is looked at next pass"
$r = Pass 0 -Using (Get-HordeWakeSettings -Overrides @{ maxConfirmsPerPass = 1 })
Check (@(Get-HordeMemoryWakerLooks).Count -eq 4) "maxConfirmsPerPass is the limit: with 1, one more look"
Start-Case; Set-HordeMemoryWakerCheap $true
foreach ($n in 1..5) { Seat $n -Change @{ BoxEmpty = "no" } }
$r = Pass 0 -Using (Get-HordeWakeSettings -Overrides @{ maxNudgesPerPass = 2 })
Check (@(Get-HordeMemoryWakerLooks).Count -eq 3 -and (Rang) -eq 0) "with two nudges a pass allowed the looks go two at a time, and still stop at three: the third is the last, in the middle of a pair"
# A LOOK THAT STILL CANNOT SAY - the box is unknown even to the full reading - is made once, and the
# next session has the next look.
Start-Case; Set-HordeMemoryWakerCheap $true
Seat 1 -Change @{ BoxEmpty = "unknown" }; Seat 2
$r = Pass 0
Check ((@(Get-HordeMemoryWakerLooks) -join ",") -ceq ((Sid 1) + "," + (Sid 2)) -and (Rang 2) -eq 1 -and (Decided $r 1).action -ceq "wait") ("a session whose look still cannot read its box is looked at once, waits, and the next is looked at and nudged (" + (@(Get-HordeMemoryWakerLooks) -join ",") + ")")
Start-Case; Set-HordeMemoryWakerCheap $true
Seat 1 -Change @{ Idle = "no" }; Seat 2 -Change @{ Reachable = "no" }; Seat 3 -Change @{ OldestUnreadAt = (At -1) }; Seat 4 -Change @{ UnreadCount = 0; OldestUnreadAt = $null }
$r = Pass 0
Check (@(Get-HordeMemoryWakerLooks).Count -eq 0 -and (Rang) -eq 0) "a session that is not idle, out of reach, whose mail is too young or that has none is never looked at: its box decides nothing"
Start-Case
Seat 1 -Change @{ BoxEmpty = "no" }; Seat 2 -Change @{ MidTurn = "yes" }
$r = Pass 0
Check (@(Get-HordeMemoryWakerLooks).Count -eq 0) "a waker whose state already says the box holds text, or a turn is under way, is not asked to look"
Start-Case; Set-HordeMemoryWakerCheap $true
Seat 1
$d = @(Get-HordeWakeDecisions -Targets @([pscustomobject]@{ id = (Sid 1); label = ""; role = "orc"; parent = ""; reachable = "yes"; retired = "no" }) -States @{ (Sid 1) = (Get-HordeWakeState -Waker $memory -Id (Sid 1)) } -Ledger @{} -Now $t0 -Settings $settings)
Check ($d[0].action -ceq "wait" -and $d[0].reason -ceq "midTurn is unknown") "without a waker that can look, an unread box or turn is wait, as it always was"
$d = @(Get-HordeWakeDecisions -Targets @([pscustomobject]@{ id = (Sid 1); label = ""; role = "orc"; parent = ""; reachable = "yes"; retired = "no" }) -States @{ (Sid 1) = (Get-HordeWakeState -Waker $memory -Id (Sid 1)) } -Ledger @{} -Now $t0 -Settings $settings -CanLook)
Check ($d[0].action -ceq "look") "with one, it is look: everything else holds, go and read the session"
Reset-HordeMemoryWaker

Write-Host ""
Write-Host "--- a session given up on is not forgotten after a day ---" -ForegroundColor Cyan

Start-Case; Seat 1
$capOne = Get-HordeWakeSettings -Overrides @{ maxNudgesPerMail = 1 }
$null = Pass 0 -Using $capOne
Check ((Rang) -eq 1 -and (Get-HordeWakeEntryValue $script:ledger[(Sid 1)] "gaveUp") -eq $true) "CONTROL: with a cap of one, the session is nudged once and given up on"
$again = 0; $said = 0
foreach ($day in 1..5) { foreach ($s in @(0, 3, 6)) { $p = Pass ($day * 86400 + 60 + $s) -Using $capOne; $said += @($p.entries | Where-Object { $_.kind -ceq "gave-up" }).Count } }
Check ((Rang) -eq 1 -and $said -eq 0 -and $script:ledger.ContainsKey((Sid 1)) -and (Get-HordeWakeEntryValue $script:ledger[(Sid 1)] "gaveUp") -eq $true) ("five days on, with the same mail still unread, it has not been nudged again and has not been given up on a second time: the entry is not dropped at 24 hours (" + (Rang) + " nudges)")
Seat 1 @{ OldestUnreadAt = (At 500000) }
$p = Pass 500100 -Using $capOne
Check ((Rang) -eq 2) "another mail becoming its oldest unread is a new mail, knocked for from nothing"
Start-Case; Seat 1
$null = Pass 0 -Using $capOne
Reset-HordeMemoryWaker
$p = Pass 86500 -Using $capOne
Check ($script:ledger.Count -eq 0) "the entry of a session that is gone from the fleet still ages out after a day: it is not kept for ever"
Start-Case; Seat 1
$null = Pass 0 -Using $capOne
Set-HordeMemoryWakerFault -Call "state" -Kind "throw"
$p = Pass 86500 -Using $capOne
Check ($script:ledger.Count -eq 1 -and (Get-HordeWakeEntryValue $script:ledger[(Sid 1)] "gaveUp") -eq $true) "but NOT the entry of a session whose state could not be read this pass: an unknown state is no evidence that its mail was taken"
Set-HordeMemoryWakerFault -Call "state" -Kind ""
# A GAVE-UP ENTRY IS DROPPED ONLY ON EVIDENCE. Three sessions given up on more than a day ago; a fourth, ready.
function New-GaveUpLedger {
    $l = @{}
    foreach ($n in 1..3) { $l[(Sid $n)] = New-HordeWakeLedgerRow -Attempts 6 -LastAttemptAt (At -90000) -LastOutcome "woken" -MailAt (At -100000) -GaveUp $true }
    return $l
}
function Seat-GaveUp { Start-Case; foreach ($n in 1..3) { Seat $n @{ OldestUnreadAt = (At -100000) } }; Seat 4 }
function Get-GaveUp { param($Ledger) return (@(1..3 | Where-Object { $Ledger.ContainsKey((Sid $_)) -and (Get-HordeWakeEntryValue $Ledger[(Sid $_)] "gaveUp") -eq $true }) -join ",") }
Seat-GaveUp
Set-HordeMemoryWakerClock $t0
$r = Invoke-HordeWakePass -Send -Waker $memory -Now $t0 -Settings $settings -Ledger (New-GaveUpLedger) -Only (Sid 4)
Check ((Get-GaveUp $r.ledger) -ceq "1,2,3" -and (Rang 4) -eq 1 -and (Rang) -eq 1) ("a PROOF pass on a fourth session reads no state of the three given up on more than a day ago, and all three entries are still there: what a pass did not read, it does not forget (" + (Get-GaveUp $r.ledger) + ")")
Seat-GaveUp
Set-HordeMemoryWakerClock $t0
$r = Invoke-HordeWakePass -Waker $memory -Now $t0 -Settings $settings -Ledger (New-GaveUpLedger) -Only (Sid 4)
Check ((Get-GaveUp $r.ledger) -ceq "1,2,3") "and so in shadow"
Seat-GaveUp
Set-HordeMemoryWakerFault -Call "state" -Kind "throw"
Set-HordeMemoryWakerClock $t0
$r = Invoke-HordeWakePass -Send -Waker $memory -Now $t0 -Settings $settings -Ledger (New-GaveUpLedger)
Check ((Get-GaveUp $r.ledger) -ceq "1,2,3" -and (Rang) -eq 0) "a LIVE pass in which their states read unknown keeps all three: a state that passed through unknown is not evidence"
Set-HordeMemoryWakerFault -Call "state" -Kind ""
Seat-GaveUp
Set-HordeMemoryWakerFault -Call "targets" -Kind "throw"
Set-HordeMemoryWakerClock $t0
$r = Invoke-HordeWakePass -Send -Waker $memory -Now $t0 -Settings $settings -Ledger (New-GaveUpLedger)
Check ((Get-GaveUp $r.ledger) -ceq "1,2,3") "a pass whose LISTING could not be read keeps all three: an unreadable listing is no evidence that anybody is gone"
Set-HordeMemoryWakerFault -Call "targets" -Kind ""
$kept = Update-HordeWakeLedger -Ledger (New-GaveUpLedger) -Decisions @() -Outcomes @{} -States @{} -Now $t0 -Settings $settings
Check ((Get-GaveUp $kept) -ceq "1,2,3") "and a caller that hands in no listing at all drops nobody for being gone"
# THE TWO KINDS OF EVIDENCE.
Seat-GaveUp
Seat 2 @{ UnreadCount = 0; OldestUnreadAt = $null }
Seat 3 @{ OldestUnreadAt = (At -50) }
Set-HordeMemoryWakerClock $t0
$r = Invoke-HordeWakePass -Waker $memory -Now $t0 -Settings $settings -Ledger (New-GaveUpLedger)
Check ((Get-GaveUp $r.ledger) -ceq "1") ("evidence: a session whose mail was taken, and one whose oldest unread mail is now another, are no longer held as given up on; the one whose mail is still there is (" + (Get-GaveUp $r.ledger) + ")")
Start-Case; Seat 1 @{ OldestUnreadAt = (At -100000) }; Seat 4
Set-HordeMemoryWakerClock $t0
$r = Invoke-HordeWakePass -Waker $memory -Now $t0 -Settings $settings -Ledger (New-GaveUpLedger)
Check ((Get-GaveUp $r.ledger) -ceq "1") ("evidence: two sessions that a WHOLE listing no longer names are gone, and their old entries are dropped (" + (Get-GaveUp $r.ledger) + ")")
$r = Invoke-HordeWakePass -Send -Waker $memory -Now $t0 -Settings $settings -Ledger (New-GaveUpLedger) -Only (Sid 4)
Check ((Get-GaveUp $r.ledger) -ceq "1") "and that holds for a proof pass too: gone is judged against the whole listing, not the one session the pass was cut down to"
$young = @{ (Sid 2) = (New-HordeWakeLedgerRow -Attempts 6 -LastAttemptAt (At -100) -LastOutcome "woken" -MailAt (At -100000) -GaveUp $true) }
$r = Invoke-HordeWakePass -Waker $memory -Now $t0 -Settings $settings -Ledger $young
Check ($r.ledger.ContainsKey((Sid 2))) "a gave-up entry less than a day old is kept even for a session the listing no longer names: a session that blinks out of a listing is not gone"
Reset-HordeMemoryWaker
Start-Case; Seat 1
$null = Pass 0
$p = Pass 86500
Check ((Rang) -eq 2) "CONTROL: an ordinary entry, of a session not given up on, is dropped after a day as before"
Reset-HordeMemoryWaker

Write-Host ""
Write-Host "--- idle by the between-turns rule: the journal says which rule let a nudge through ---" -ForegroundColor Cyan

Start-Case; Seat 1 @{ BetweenTurns = "yes"; Rule = "between-turns-background-work" }
$r = Pass 0 -Shadow
Check ((Kinds $r) -ceq "would-nudge" -and "$($r.entries[0].reason)" -ceq "unread mail, idle by the between-turns rule (between-turns-background-work), empty box") ("a would-nudge of a session that is idle by the between-turns rule says so, with the rule's word (" + $r.entries[0].reason + ")")
Start-Case; Seat 1 @{ BetweenTurns = "yes"; Rule = "between-turns-background-work" }
$r = Pass 0
Check ((Kinds $r) -ceq "nudge" -and (Rang) -eq 1 -and "$($r.entries[0].reason)".Contains("sent because: unread mail, idle by the between-turns rule (between-turns-background-work), empty box") -and "$($r.entries[0].reason)".Contains("the waker says the rule that let it type was between-turns-background-work")) ("a real nudge of it says why it was sent, and the rule the waker itself names in its answer (" + $r.entries[0].reason + ")")
Start-Case; Seat 1
$r = Pass 0 -Shadow
$r2 = $null; Start-Case; Seat 1; $r2 = Pass 0
Check ("$($r.entries[0].reason)" -ceq "unread mail, idle, empty box" -and -not "$($r2.entries[0].reason)".Contains("rule")) "CONTROL: a session idle by its own word is journaled as before, with no rule named"
foreach ($word in @("no", "unknown")) {
    Start-Case; Seat 1 @{ BetweenTurns = $word }
    Check ("$((Pass 0 -Shadow).entries[0].reason)" -ceq "unread mail, idle, empty box") ("betweenTurns " + $word + " names no rule")
}
# THE BOX IS STILL READ BEFORE ANY NUDGE, rule or no rule: the rule says idle, never "the box is empty".
Start-Case; Set-HordeMemoryWakerCheap $true; Seat 1 @{ BetweenTurns = "yes" }
$r = Pass 0
Check ((@(Get-HordeMemoryWakerLooks) -join ",") -ceq (Sid 1) -and (Rang) -eq 1) "a session idle by the between-turns rule, whose box the cheap reading does not say, is LOOKED AT before it is nudged"
Start-Case; Set-HordeMemoryWakerCheap $true; Seat 1 @{ BetweenTurns = "yes"; BoxEmpty = "no" }
$r = Pass 0
Check ((Rang) -eq 0 -and (Decided $r).reason -ceq "boxEmpty is no") "and one whose box that look finds holding text is not nudged, between turns or not"
Start-Case; Seat 1 @{ BetweenTurns = "yes"; BoxEmpty = "unknown" }
$r = Pass 0
Check ((Rang) -eq 0 -and (Decided $r).action -ceq "wait") "nor one whose box nobody could read: unknown is never permission"
Reset-HordeMemoryWaker

Write-Host ""
Write-Host "--- mail handed over is not mail to nudge for, and the journal says so ---" -ForegroundColor Cyan

Start-Case; Seat 1 @{ UnreadCount = 0; OldestUnreadAt = $null; HandedOverCount = 2; OldestHandedOverAt = (At -30) }
$r = Pass 0
Check ((Rang) -eq 0 -and (Decided $r).action -ceq "skip" -and (Decided $r).reason -ceq "no unread mail: 2 handed over and not yet acknowledged") "a session with two mails handed over and none unread is not nudged, and the decision names the handed-over mail"
Check ($r.held.ContainsKey((Sid 1)) -and "$($r.held[(Sid 1)])".StartsWith("handed-over mail: 2 handed over to it and not yet acknowledged, and none unread") -and @($r.entries).Count -eq 0 -and -not $script:ledger.ContainsKey((Sid 1))) "the pass hands it on to be journaled once as held: no attempt is counted for it"
Start-Case; Seat 1 @{ UnreadCount = 0; OldestUnreadAt = $null; HandedOverCount = 2; OldestHandedOverAt = (At -3000) }
$r = Pass 0
Check ((Rang) -eq 0 -and $r.held.ContainsKey((Sid 1))) "however long ago it was handed over: when handed-over mail counts as unread again is the fleet's to say, by unreadCount, and is not worked out here"
Start-Case; Seat 1 @{ UnreadCount = 1; HandedOverCount = 2; OldestHandedOverAt = (At -30) }
$r = Pass 0
Check ((Rang) -eq 1 -and -not $r.held.ContainsKey((Sid 1))) "CONTROL: one unread beside two handed over is nudged for, and nothing is held"
Start-Case; Seat 1 @{ UnreadCount = 0; OldestUnreadAt = $null }
$r = Pass 0
Check ((Decided $r).reason -ceq "no unread mail" -and $r.held.Count -eq 0) "CONTROL: nothing unread and nothing handed over is plain no unread mail, with nothing to say"
Start-Case; Seat 1 @{ UnreadCount = 0; OldestUnreadAt = $null; HandedOverCount = $null }
$r = Pass 0
Check ((Decided $r).reason -ceq "no unread mail" -and $r.held.Count -eq 0) "a waker that cannot say what was handed over has nothing said for it: unknown is not a count"
foreach ($case in @(@{ what = "a retired session"; seat = @{ Retired = "yes" } }, @{ what = "a reserved label"; seat = @{ Label = "RS" } })) {
    Start-Case; $seat = @{ UnreadCount = 0; OldestUnreadAt = $null; HandedOverCount = 1 }; foreach ($k in $case.seat.Keys) { $seat[$k] = $case.seat[$k] }; Seat 1 $seat
    Check ((Pass 0).held.Count -eq 0) ("handed-over mail of " + $case.what + " is not said to be held: it would never have been nudged")
}
Start-Case; Seat 1 @{ UnreadCount = 0; OldestUnreadAt = $null; HandedOverCount = 1 }
$r = Invoke-HordeWakePass -Send -Waker $memory -Now (At 0) -Settings $settings -Ledger @{} -Self (Sid 1)
Check ($r.held.Count -eq 0) "nor that of the watcher's own session"
Reset-HordeMemoryWaker

Write-Host ""
Write-Host "--- a retired session is never nudged ---" -ForegroundColor Cyan

Start-Case; Seat 1 @{ Retired = "yes" }
$r = Pass 0
Check ((Decided $r).action -ceq "skip" -and "$((Decided $r).reason)".StartsWith("retired") -and (Rang) -eq 0 -and $script:ledger.Count -eq 0) "a retired session that is reachable, idle, with old unread mail and an empty box - everything a nudge asks for - is skipped: retired is asked first"
Check ("$($r.never[(Sid 1)])".StartsWith("retired, with 1 unread") -and $r.held.Count -eq 0 -and @($r.entries).Count -eq 0) "the pass says who it holds for being retired, for the tick to journal once, and journals nothing itself"
$rung = 0; $lines = 0; foreach ($s in 1..400) { $p = Pass ($s * 3); $rung += (Rang); $lines += @($p.entries).Count }
Check ($rung -eq 0 -and $lines -eq 0 -and $script:ledger.Count -eq 0) "twenty minutes on it has never been nudged, nothing is counted against it, and it is never given up on: it is nothing, not a failure"
Start-Case; Seat 1 @{ Retired = "unknown" }
$r = Pass 0
Check ((Decided $r).action -ceq "wait" -and "$((Decided $r).reason)".StartsWith("retired is unknown") -and (Rang) -eq 0 -and $script:ledger.Count -eq 0 -and "$($r.held[(Sid 1)])".StartsWith("it could not be told whether this session is retired")) "a session the waker cannot say is retired or not is held: unknown never reads as permission"
Start-Case; Seat 1 @{ Retired = "yes"; UnreadCount = 0; OldestUnreadAt = $null }; Seat 2
$r = Pass 0
Check ($r.held.Count -eq 0 -and $r.never.Count -eq 0 -and (Rang 2) -eq 1) "a retired session with no mail has nothing to be said of it, and the session beside it is nudged as ever"
Start-Case; Seat 1 @{ Retired = "yes"; Role = "warchief" }; Seat 2
Set-HordeMemoryWakerCheap $true
$r = Pass 0
Check ((Rang 2) -eq 1 -and (@(Get-HordeMemoryWakerLooks) -join ",") -ceq (Sid 2)) "a retired warchief does not take the pass's nudge or its look from the session behind it"
$d = @(Get-HordeWakeDecisions -Targets @([pscustomobject]@{ id = (Sid 1); label = ""; role = "orc"; parent = ""; reachable = "yes" }) -States @{ (Sid 1) = (Get-HordeWakeState -Waker $memory -Id (Sid 1) -Full) } -Ledger @{} -Now $t0 -Settings $settings)
Check ($d[0].action -ceq "wait" -and "$($d[0].reason)".StartsWith("retired is unknown")) "a target that does not say whether it is retired at all is held like one that says unknown"
# SAID ONCE: the tick's once-rule, for any standing fact.
$o1 = Update-HordeWakeSaidOnce -Seen @{} -Said @{ (Sid 1) = "retired, with 1 unread" } -Known @((Sid 1)) -Now (At 0) -Kind "held" -Outcome "held"
$o2 = Update-HordeWakeSaidOnce -Seen $o1.seen -Said @{ (Sid 1) = "retired, with 1 unread" } -Known @((Sid 1)) -Now (At 3) -Kind "held" -Outcome "held"
$o3 = Update-HordeWakeSaidOnce -Seen $o2.seen -Said @{ (Sid 1) = "retired, with 2 unread" } -Known @((Sid 1)) -Now (At 6) -Kind "held" -Outcome "held"
Check (@($o1.entries).Count -eq 1 -and $o1.entries[0].kind -ceq "held" -and $o1.entries[0].outcome -ceq "held" -and $o1.entries[0].id -ceq (Sid 1) -and $o1.entries[0].reason -ceq "retired, with 1 unread" -and @($o2.entries).Count -eq 0 -and @($o3.entries).Count -eq 1) "a session held for being retired is journaled once, not again on the next pass, and again when what there is to say changes"
Reset-HordeMemoryWaker

Write-Host ""
Write-Host "--- shadow is the default at every level: sending, and the sending run's files, are asked for by name ---" -ForegroundColor Cyan

Start-Case; Seat 1 @{ Role = "warchief" }; Seat 2; Seat 3
Set-HordeMemoryWakerClock $t0
$r = Invoke-HordeWakePass -Waker $memory -Now $t0 -Settings $settings -Ledger @{}
Check ((Rang) -eq 0 -and @(Get-HordeMemoryWakerAsks).Count -eq 0 -and (Kinds $r) -ceq "would-nudge") ("a pass over a ready fleet, given no word about sending, is a SHADOW pass: it asks for no nudge and journals what it would do (" + (Kinds $r) + ")")
$r = Invoke-HordeWakePass -Waker $memory -Now $t0 -Settings $settings -Ledger @{} -Only ""
Check ((Rang) -eq 0 -and @(Get-HordeMemoryWakerAsks).Count -eq 0) "and so is one given an empty -Only: no one session and no word about sending is never a live pass over the fleet"
$r = Invoke-HordeWakePass -Waker $memory -Now $t0 -Settings $settings -Ledger @{} -Send:$false
Check ((Rang) -eq 0) "-Send:`$false is shadow"
$r = Invoke-HordeWakePass -Waker $memory -Now $t0 -Settings $settings -Ledger @{} -Send
Check ((Rang) -eq 1 -and (Kinds $r) -ceq "nudge") "CONTROL: asked to send, it sends"
$hd = Join-Path $pinned.home ("default-" + [guid]::NewGuid().ToString("N")); New-Item -ItemType Directory -Path $hd | Out-Null
Check ((Get-HordeWakeSendWord -Mode "proof") -ceq "live" -and (Get-HordeWakeSendWord -Mode "live") -ceq "live" -and (Get-HordeWakeSendWord -Mode "shadow") -ceq "shadow" -and (Get-HordeWakeSendWord) -ceq "shadow") "the runs that send - proof and live - share one word for their lock and their ledger; shadow, and a caller that names no mode, have shadow's"
Check ((Get-HordeWakeModeWord) -ceq "shadow" -and (Get-HordeWakeModeWord -Shadow) -ceq "shadow" -and (Get-HordeWakeModeWord -Mode "live") -ceq "live" -and (Get-HordeWakeModeWord -Mode "proof") -ceq "proof") "a mode's files are the shadow run's when no mode is named: the sending run's are asked for by name"
Check ((Split-Path -Leaf (Get-HordeWakeStateFile -Name "ledger" -HordeHome $hd)) -ceq "ledger-shadow.json" -and (Split-Path -Leaf (Get-HordeWakeModeFile -Stem "journal" -Extension ".jsonl" -HordeHome $hd)) -ceq "journal-shadow.jsonl") "so a state file and a journal named with no mode are the shadow ones"
Save-HordeWakeLedger -Ledger @{ (Sid 1) = (New-HordeWakeLedgerRow -Attempts 1 -LastAttemptAt $t0 -LastOutcome "would-nudge") } -HordeHome $hd
Write-HordeWakeHeartbeat -At $t0 -ProcessId 1 -Pass 1 -HordeHome $hd
$null = Write-HordeWakeJournal -Entries @((New-HordeWakeEntry -At $t0 -Kind "would-nudge" -Id (Sid 1) -Outcome "would-nudge")) -HordeHome $hd
$lk = Enter-HordeWakeLock -ProcessId 1 -HordeHome $hd
if ($null -ne $lk) { $lk.Dispose() }
$made = @(Get-ChildItem -LiteralPath (Join-Path $hd "wake") | ForEach-Object { $_.Name } | Sort-Object)
Check (($made -join ",") -ceq "heartbeat-shadow.json,journal-shadow.jsonl,ledger-shadow.json,run-shadow.lock") ("a ledger, a heartbeat, a journal and a lock written with no mode named are all the shadow run's: nothing of the sending run is touched by a caller that left a word out (" + ($made -join ",") + ")")
Check ((Read-HordeWakeLedger -Mode "live" -HordeHome $hd).state -ceq "absent" -and (Read-HordeWakeHeartbeat -Mode "live" -HordeHome $hd).state -ceq "absent" -and (Read-HordeWakeLedger -HordeHome $hd).state -ceq "known") "and read back the same way"
Reset-HordeMemoryWaker

Write-Host ""
Write-Host "--- a sender's label and the watcher's own session are never nudged, in any mode ---" -ForegroundColor Cyan

foreach ($label in @("RS", "WW", "SV")) {
    Start-Case; Seat 1 @{ Label = $label; Role = "warchief" }; Seat 2 @{ Label = "A" }
    Set-HordeMemoryWakerClock $t0
    $r = Invoke-HordeWakePass -Send -Waker $memory -Now $t0 -Settings $settings -Ledger @{}
    Check ((Rang 1) -eq 0 -and (Rang 2) -eq 1 -and (Decided $r 1).action -ceq "skip" -and "$((Decided $r 1).reason)".Contains("reserved") -and "$($r.never[(Sid 1)])".Contains($label) -and $r.ledger.Count -eq 1) ("a session labelled " + $label + " - ready in every other way, and the warchief - is skipped by a pass that sends, and the session behind it is nudged")
    $r = Invoke-HordeWakePass -Waker $memory -Now $t0 -Settings $settings -Ledger @{}
    Check ((Decided $r 1).action -ceq "skip" -and @($r.entries | Where-Object { $_.id -ceq (Sid 1) }).Count -eq 0) "and by a shadow pass: not even a would-nudge is journaled for it"
    Start-Case; Seat 1 @{ Label = $label }
    Set-HordeMemoryWakerClock $t0
    $r = Invoke-HordeWakePass -Send -Waker $memory -Now $t0 -Settings $settings -Ledger @{} -Only (Sid 1)
    Check ((Rang) -eq 0 -and (Decided $r 1).action -ceq "skip") "and by a pass given that one session: a proof cannot be aimed at it either"
}
Start-Case; Seat 1 @{ Label = "RS1" }; Seat 2 @{ Label = "R" }
$r = Pass 0
Check ((Decided $r 1).action -cne "skip" -and (Decided $r 2).action -cne "skip") "RS1 and R are other labels, and ordinary sessions"
Start-Case; Seat 1 @{ Role = "warchief" }; Seat 2
Set-HordeMemoryWakerClock $t0
$r = Invoke-HordeWakePass -Send -Waker $memory -Now $t0 -Settings $settings -Ledger @{} -Self (Sid 1)
Check ((Rang 1) -eq 0 -and (Rang 2) -eq 1 -and (Decided $r 1).action -ceq "skip" -and "$((Decided $r 1).reason)".Contains("started from") -and "$($r.never[(Sid 1)])".Contains("started from")) "the session the watcher was started from is skipped, though it is ready and first in the fair order, and the next is nudged"
$r = Invoke-HordeWakePass -Send -Waker $memory -Now $t0 -Settings $settings -Ledger @{} -Only (Sid 1) -Self (Sid 1)
Check ((Rang 1) -eq 0) "a pass given that one session does not nudge it either"
Start-Case; Seat 1
Set-HordeMemoryWakerClock $t0
$r = Invoke-HordeWakePass -Send -Waker $memory -Now $t0 -Settings $settings -Ledger @{} -Self ""
Check ((Rang) -eq 1) "CONTROL: a watcher started from no session holds nobody back for that"
Reset-HordeMemoryWaker

Write-Host ""
Write-Host "--- one session, and no other: a pass cut down to the session it was given ---" -ForegroundColor Cyan

Start-Case
Seat 1 @{ Role = "warchief"; OldestUnreadAt = (At -600) }; Seat 2 @{ OldestUnreadAt = (At -300) }; Seat 3 @{ Role = "warg" }
Set-HordeMemoryWakerClock $t0
$r = Invoke-HordeWakePass -Send -Waker $memory -Now $t0 -Settings $settings -Ledger @{} -Only (Sid 3)
Check ((@(Get-HordeMemoryWakerNudges | ForEach-Object { $_.id }) -join ",") -ceq (Sid 3) -and (@(Get-HordeMemoryWakerAsks) -join ",") -ceq (Sid 3)) "of three ready sessions, a pass given the one the fair order serves last nudges that one and no other"
Check ((@(Get-HordeMemoryWakerReads | Sort-Object -Unique) -join ",") -ceq (Sid 3) -and @($r.decisions).Count -eq 1 -and $r.decisions[0].id -ceq (Sid 3) -and $r.ledger.Count -eq 1) "the other two were never read and never decided on: the pass was cut down before the first state was read"
Check ($r.warchief -ceq (Sid 1)) "who the warchief is is still known, from the listing alone"
Start-Case
Seat 1 @{ Role = "warchief" }; Seat 2
Set-HordeMemoryWakerClock $t0
$r = Invoke-HordeWakePass -Send -Waker $memory -Now $t0 -Settings $settings -Ledger @{} -Only (Sid 9)
Check ((Rang) -eq 0 -and @(Get-HordeMemoryWakerReads).Count -eq 0 -and @($r.decisions).Count -eq 0 -and (Kinds $r) -ceq "proof-target-absent" -and $r.entries[0].id -ceq (Sid 9)) "a pass given a session the fleet does not list nudges nobody and reads nobody: it never falls back to whoever is ready"
foreach ($near in @(((Sid 1).Substring(0, 8)), ((Sid 1).ToUpperInvariant()), "A")) {
    Start-Case; Seat 1 @{ Role = "warchief"; Label = "A" }
    Set-HordeMemoryWakerClock $t0
    $r = Invoke-HordeWakePass -Send -Waker $memory -Now $t0 -Settings $settings -Ledger @{} -Only $near
    Check ((Rang) -eq 0 -and (Kinds $r) -ceq "proof-target-absent") ("'" + $near + "' - a part of the id, its other casing, the session's label - is not the session: nobody is nudged")
}
Start-Case; Seat 1
Set-HordeMemoryWakerFault -Call "targets" -Kind "throw"
$r = Invoke-HordeWakePass -Send -Waker $memory -Now $t0 -Settings $settings -Ledger @{} -Only (Sid 1)
Check ((Kinds $r) -ceq "skip-unknown,proof-target-absent" -and (Rang) -eq 0) "with a listing that cannot be read, the pass says its one session was not found"
# A PASS GIVEN ONE SESSION SENDS NO PROBE: a limited session is not typed into on a timer read from a ledger.
Start-Case; Seat 1 @{ Limited = "yes" }
$stale = @{ (Sid 1) = (New-HordeWakeLedgerRow -Attempts 0 -LastAttemptAt (At -9000) -LastOutcome "limited" -MailAt (At -60) -ProbeAt (At -9000)) }
Set-HordeMemoryWakerClock $t0
$r = Invoke-HordeWakePass -Send -Waker $memory -Now $t0 -Settings $settings -Ledger $stale -Only (Sid 1)
Check ((Rang) -eq 0 -and @($r.decisions | Where-Object { $_.action -ceq "wait" -and "$($_.reason)".Contains("sends no probe") }).Count -eq 1) "a session limited with no known end, whose hourly probe is long due by the ledger, is NOT nudged by a pass given that one session"
$r = Invoke-HordeWakePass -Send -Waker $memory -Now $t0 -Settings $settings -Ledger $stale
Check ((Rang) -eq 1) "CONTROL: the watcher's own pass, over the whole fleet, does send the probe that is due"
Start-Case; Seat 1; Seat 2
Check ((Rang) -eq 0 -and @((Pass 0).decisions).Count -eq 2) "CONTROL: a pass given no one session is a pass over them all"
Reset-HordeMemoryWaker

Write-Host ""
Write-Host "--- a usage limit: a session that cannot answer is not knocked for, and no attempt is spent on it ---" -ForegroundColor Cyan

# 1. THE LIMIT ENDS AT A KNOWN TIME STILL AHEAD: no knock, no attempt, until then.
Start-Case; Seat 1 @{ Limited = "yes"; LimitedUntil = (At 600) }
$r = Pass 0
Check ((Test-Held $r "usage limit until 2026-10-12T08:10:00Z") -and $script:ledger.Count -eq 0 -and "$($r.limited[(Sid 1)])" -ceq "usage limit until 2026-10-12T08:10:00Z" -and $r.mail[(Sid 1)] -eq (At -60)) "a session limited until a time still ahead is not nudged: it waits, saying until when, and nothing is held against it"
$rung = 0; foreach ($s in 1..199) { $null = Pass ($s * 3); $rung += (Rang) }
Check ($rung -eq 0 -and $script:ledger.Count -eq 0) "for the ten minutes of the limit - two hundred passes - it is never nudged and never counted"
$r = Pass 600
Check ((Decided $r).action -ceq "nudge" -and (Rang) -eq 1 -and $script:ledger[(Sid 1)].attempts -eq 0 -and $r.limited.Count -eq 0) "at the time the limit ends it is knocked for, once and uncounted"
# 2. THE LIMIT IS OVER: the waker still says limited, with a time that has passed. ONE knock, uncounted;
#    then the normal rules.
Start-Case; Seat 1 @{ Limited = "yes"; LimitedUntil = (At -10) }
$r = Pass 0
Check ((Decided $r).action -ceq "nudge" -and (Rang) -eq 1 -and $script:ledger[(Sid 1)].attempts -eq 0 -and (Get-HordeWakeEntryValue $script:ledger[(Sid 1)] "freeFor") -eq (At -10) -and $r.limited.Count -eq 0) "a session whose limit is over - the waker still says limited, with a time that has passed - is knocked for once, and that knock is NOT counted"
$r = Pass 3
Check ((Test-Held2 $r "back-off") -and (Rang) -eq 1) "it is not knocked for again at once: the first step of the back-off runs from the free knock"
$r = Pass 6
Check ((Decided $r).action -ceq "nudge" -and (Rang) -eq 2 -and $script:ledger[(Sid 1)].attempts -eq 1) "its next knock is an ordinary attempt, counted as the first"
foreach ($s in @(30, 80, 250, 600, 1000, 1400, 1800, 2200)) { $null = Pass $s }
Check ((Rang) -eq 7 -and $script:ledger[(Sid 1)].attempts -eq 6 -and (Get-HordeWakeEntryValue $script:ledger[(Sid 1)] "gaveUp") -eq $true) ("and from there the normal rules hold: six counted attempts and it is given up on - seven knocks in all, one of them free (" + (Rang) + ")")
# A SESSION ALREADY AT ITS CAP WHEN ITS LIMIT ENDS: the free knock is what it is owed.
Start-Case; Seat 1
$null = Pass 0 -Using $capOne
Check ((Get-HordeWakeEntryValue $script:ledger[(Sid 1)] "gaveUp") -eq $true -and (Rang) -eq 1) "CONTROL: a session nudged to its cap - one, here - is given up on"
Seat 1 @{ Limited = "yes"; LimitedUntil = (At 100) }
$r = Pass 50 -Using $capOne
Check ((Rang) -eq 1) "CONTROL: while its limit lasts it is not knocked for"
$r = Pass 100 -Using $capOne
Check ((Decided $r).action -ceq "nudge" -and (Rang) -eq 2 -and $script:ledger[(Sid 1)].attempts -eq 1) "at the moment its limit ends it is knocked for once, cap or no cap: the knocks it had could not have been answered"
$r = Pass 500 -Using $capOne
Check ((Rang) -eq 2 -and "$((Decided $r).reason)".StartsWith("gave up")) "and then its cap holds again: one free knock, not a new budget"
Seat 1 @{ Limited = "yes"; LimitedUntil = (At 900) }
$null = Pass 600 -Using $capOne
$r = Pass 900 -Using $capOne
Check ((Rang) -eq 3) "another limit, ending at another time, has a free knock of its own"
Check ((Get-HordeWakeLimit -State ([pscustomobject]@{ limited = "yes"; limitedUntil = (At 0) }) -Now (At 0)).kind -ceq "over" -and (Get-HordeWakeLimit -State ([pscustomobject]@{ limited = "yes"; limitedUntil = (At 1) }) -Now (At 0)).kind -ceq "until" -and (Get-HordeWakeLimit -State ([pscustomobject]@{ limited = "yes"; limitedUntil = $null }) -Now (At 0)).kind -ceq "open" -and (Get-HordeWakeLimit -State ([pscustomobject]@{ limited = "no"; limitedUntil = (At 99) }) -Now (At 0)).kind -ceq "none" -and (Get-HordeWakeLimit -State ([pscustomobject]@{ id = "x" }) -Now (At 0)).kind -ceq "none") "a limit is until a time ahead, over when its time has come, open with no time, and none when the waker says not limited"
$hf = Join-Path $pinned.home ("free-" + [guid]::NewGuid().ToString("N")); New-Item -ItemType Directory -Path $hf | Out-Null
Save-HordeWakeLedger -Ledger @{ (Sid 1) = (New-HordeWakeLedgerRow -Attempts 0 -LastAttemptAt (At 0) -LastOutcome "woken" -MailAt (At -60) -FreeFor (At -10)) } -HordeHome $hf
$rf = Read-HordeWakeLedger -HordeHome $hf
Check ($rf.state -ceq "known" -and (Get-HordeWakeEntryValue $rf.value.ledger[(Sid 1)] "freeFor") -eq (At -10)) "which limit's free knock a session has had is saved with the ledger: a restart does not hand it another"
# 3. NO KNOWN END, RELEASED BY THE HOUR: one knock an hour, never counted.
Start-Case; Seat 1 @{ Limited = "yes" }
$r = Pass 0
Check ((Test-Held $r "usage limit, end unknown") -and $script:ledger.ContainsKey((Sid 1)) -and $script:ledger[(Sid 1)].attempts -eq 0 -and (Get-HordeWakeEntryValue $script:ledger[(Sid 1)] "probeAt") -eq (At 0) -and "$($r.limited[(Sid 1)])" -ceq "usage limit, end unknown") "a session limited with no known end is not nudged, and the pass that first sees it so notes when"
$rung = 0; foreach ($s in 1..11) { $null = Pass ($s * 300); $rung = (Rang) }
Check ($rung -eq 0 -and $script:ledger.ContainsKey((Sid 1)) -and (Get-HordeWakeEntryValue $script:ledger[(Sid 1)] "probeAt") -eq (At 0)) "for the next 55 minutes it is not nudged - not on the back-off's timer either - and when it was first seen stays as it was"
$r = Pass 3600
Check ((Decided $r).action -ceq "nudge" -and (Rang) -eq 1 -and $script:ledger.ContainsKey((Sid 1)) -and $script:ledger[(Sid 1)].attempts -eq 0 -and (Get-HordeWakeEntryValue $script:ledger[(Sid 1)] "probeAt") -eq (At 3600)) "an hour after it was first seen so it is knocked for once, and the knock is not counted"
$r = Pass 3603
Check ((Test-Held2 $r "usage limit, end unknown") -and (Rang) -eq 1) "and then it waits again"
# ...AND THE KNOCKS ARE CAPPED: six for one mail, then one gave-up line, and silence.
$gaveLines = 0; $gaveTold = 0
foreach ($h in 2..9) { $p = Pass ($h * 3600); $gaveLines += @($p.entries | Where-Object { $_.kind -ceq "gave-up" }).Count; $gaveTold += @($p.gaveUp).Count }
Check ((Rang) -eq 6 -and $script:ledger[(Sid 1)].attempts -eq 0 -and $script:ledger[(Sid 1)].probes -eq 6) ("nine hours are SIX knocks, not nine: a session limited with no known end is not typed into for ever (" + (Rang) + " knocks)")
Check ($gaveLines -eq 1 -and $gaveTold -eq 1 -and (Get-HordeWakeEntryValue $script:ledger[(Sid 1)] "gaveUp") -eq $true) "after the sixth it is given up on, said once, with one session for the warchief to be told of"
$r = Pass 40000
Check ((Test-Held2 $r "gave up after 6 knocks while it was limited") -and (Rang) -eq 6) "and it waits, saying so"
$script:ledger = Set-HordeWakeLedgerProbesDue -Ledger $script:ledger
$r = Pass 40003
Check ((Rang) -eq 6 -and $script:ledger[(Sid 1)].probes -eq 6) "a session of the fleet taking mail does not buy it a seventh: the release is capped with the hour"
Seat 1 @{ Limited = "no" }
$r = Pass 40006
Check ((Decided $r).action -ceq "nudge" -and (Rang) -eq 7 -and $script:ledger[(Sid 1)].attempts -eq 1 -and (Get-HordeWakeEntryValue $script:ledger[(Sid 1)] "gaveUp") -ne $true) "when its waker stops saying it is limited it is nudged under the normal rules, from no attempts - and is not held as given up on for a limit that is over"
Start-Case; Seat 1 @{ Limited = "yes" }
foreach ($h in 0..8) { $null = Pass ($h * 3600) }
Seat 1 @{ Limited = "yes"; OldestUnreadAt = (At 40000) }
$null = Pass 40100
$r = Pass (40100 + 3600)
Check ((Rang) -eq 7 -and $script:ledger[(Sid 1)].probes -eq 1) "another mail becoming its oldest unread starts the count again: the cap is for one mail"
$hp = Join-Path $pinned.home ("probes-" + [guid]::NewGuid().ToString("N")); New-Item -ItemType Directory -Path $hp | Out-Null
Save-HordeWakeLedger -Ledger @{ (Sid 1) = (New-HordeWakeLedgerRow -Attempts 0 -LastAttemptAt (At 0) -LastOutcome "woken" -MailAt (At -60) -ProbeAt (At 7) -Probes 4) } -HordeHome $hp
$rb = Read-HordeWakeLedger -HordeHome $hp
Check ($rb.state -ceq "known" -and (Get-HordeWakeEntryValue $rb.value.ledger[(Sid 1)] "probes") -eq 4) "how many knocks a limited session has had is saved with the ledger: a restart does not hand it six more"
# 4. NO KNOWN END, RELEASED WHEN A SESSION OF THE FLEET TAKES MAIL.
Start-Case; Seat 1 @{ Limited = "yes" }; Seat 2 @{ Limited = "yes" }; Seat 3 @{ UnreadCount = 0; OldestUnreadAt = $null }
$null = Pass 0
Check ((Rang) -eq 0 -and $script:ledger.Count -eq 2) "CONTROL: two sessions limited with no known end wait, each noted"
$script:ledger = Set-HordeWakeLedgerProbesDue -Ledger $script:ledger
$null = Pass 3
Check ((Rang) -eq 1) "once their probes are marked due, the first pass knocks for one of them"
$null = Pass 6
Check ((Rang 1) -eq 1 -and (Rang 2) -eq 1 -and @($script:ledger.Values | Where-Object { $_.attempts -ne 0 }).Count -eq 0) "once their probes are marked due - a session of the fleet took mail - each is knocked for once, one a pass: the rate limit delays a release and does not lose it"
$null = Pass 9; $null = Pass 600
Check ((Rang) -eq 2) "and one knock is all a release is: they wait again"
$plain = @{}; $plain[(Sid 5)] = New-HordeWakeLedgerRow -Attempts 2 -LastAttemptAt (At 0) -LastOutcome "woken" -MailAt (At -60)
Check ($null -eq (Get-HordeWakeEntryValue (Set-HordeWakeLedgerProbesDue -Ledger $plain)[(Sid 5)] "probeAt") -and (Set-HordeWakeLedgerProbesDue -Ledger $plain)[(Sid 5)].attempts -eq 2) "an entry that is no probe's is left as it was"
# A session that had been given up on, and is then found limited with no end, is probed all the same.
Start-Case; Seat 1
$one = Get-HordeWakeSettings -Overrides @{ maxNudgesPerMail = 1 }
$null = Pass 0 -Using $one
Check ((Get-HordeWakeEntryValue $script:ledger[(Sid 1)] "gaveUp") -eq $true) "CONTROL: with a cap of one, the session is given up on"
Seat 1 @{ Limited = "yes" }
$null = Pass 3 -Using $one
$r = Pass 3700 -Using $one
Check ((Rang) -eq 2 -and $script:ledger.ContainsKey((Sid 1)) -and $script:ledger[(Sid 1)].attempts -eq 1) "found limited afterwards, it is still knocked for at its hour: the limit explains the silence the cap was spent on"
# ... and when that knock is answered "nothing", what was said of the session is not forgotten.
Seat 1 @{ Limited = "yes"; Outcome = "nothing"; OutcomeReason = "no unread mail" }
$r = Pass 7400 -Using $one
Check ((Rang) -eq 2 -and (Kinds $r) -cnotlike "*gave-up*" -and $script:ledger.ContainsKey((Sid 1)) -and (Get-HordeWakeEntryValue $script:ledger[(Sid 1)] "gaveUp") -eq $true) ("a probe its waker answers with nothing leaves the session given up on, and gave-up is not said a second time (" + (Kinds $r) + ")")
# 5. LIMITED UNKNOWN: the waker can tell, and for this session could not. UNKNOWN IS NOT NO.
function PassM {
    # One pass at t0 + -Seconds, in a fleet where ANOTHER session (99, with no mail of its own) last
    # acknowledged mail at -MovedAt, or nobody did; -Moves says who acknowledged when, instead.
    param([double]$Seconds, $MovedAt = $null, $Moves = $null)
    if ($null -eq $Moves -and $MovedAt -is [datetime]) { $Moves = @{ (Sid 99) = $MovedAt } }
    if ($null -ne $Moves) { foreach ($who in @($Moves.Keys)) { Set-HordeMemoryWakerAcked -Id $who -At $Moves[$who] } }
    Set-HordeMemoryWakerClock (At $Seconds)
    $r = Invoke-HordeWakePass -Send -Waker $memory -Now (At $Seconds) -Settings $settings -Ledger $script:ledger
    $script:ledger = $r.ledger
    return $r
}
Start-Case; Seat 1 @{ Limited = "unknown" }
$r = PassM 0
Check ((Test-Held $r "usage limit unknown") -and $script:ledger.ContainsKey((Sid 1)) -and $script:ledger[(Sid 1)].attempts -eq 0 -and "$($r.limited[(Sid 1)])".StartsWith("usage limit unknown")) "a session whose limit its waker could not read, with no evidence that sessions are taking turns, waits: unknown is not 'not limited', and nothing is counted"
$rung = 0; foreach ($s in 1..200) { $null = PassM ($s * 3); $rung = (Rang) }
Check ($rung -eq 0 -and $script:ledger[(Sid 1)].attempts -eq 0) "ten minutes on it has not been nudged, and nothing is held against it"
Start-Case; Seat 1 @{ Limited = "unknown" }; Seat 2 @{ Role = "warchief" }
$r = PassM 0 -MovedAt (At -30)
Check ((Decided $r 2).action -ceq "nudge" -and (Decided $r 1).reason -ceq "rate limit" -and $r.limited.Count -eq 0) "with a session seen taking mail half a minute ago, unknown is read as not limited: it is ready like any other, and waits only for its turn"
$r = PassM 3 -MovedAt (At -30)
Check ((Decided $r 1).action -ceq "nudge" -and (Rang 1) -eq 1 -and $script:ledger[(Sid 1)].attempts -eq 1 -and $null -eq (Get-HordeWakeEntryValue $script:ledger[(Sid 1)] "probeAt")) "and is nudged in its turn, under the normal rules: the nudge counts"
# THE EDGE of movingEvidenceSeconds (600): evidence exactly that old still counts; a second older does not.
Start-Case; Seat 1 @{ Limited = "unknown" }
$r = PassM 600 -MovedAt (At 0)
Check ((Decided $r).action -ceq "nudge" -and (Rang) -eq 1) "mail taken exactly 600 s ago is still evidence: the window is the last 600 s, both ends in"
Start-Case; Seat 1 @{ Limited = "unknown" }
$r = PassM 601 -MovedAt (At 0)
Check ((Test-Held $r "usage limit unknown") -and (Rang) -eq 0) "mail taken 601 s ago is not: the session waits"
Start-Case; Seat 1 @{ Limited = "unknown" }
$r = PassM 0 -MovedAt (At 5)
Check ((Test-Held $r "usage limit unknown")) "and a time that has not come yet is no evidence of anything"
Check ($settings.movingEvidenceSeconds -eq 600) "the window is a setting, 600 s"
# THE JUDGED SESSION'S OWN MAILBOX IS NEVER THE EVIDENCE: the fleet's repair moves a mailbox with no turn taken.
Start-Case; Seat 1 @{ Limited = "unknown" }
$r = PassM 0 -Moves @{ (Sid 1) = (At -5) }
Check ((Test-Held $r "usage limit unknown") -and (Rang) -eq 0) "a session whose limit is unknown is NOT released by its own mailbox having changed five seconds ago: that is no evidence anybody took a turn"
$r = PassM 3 -Moves @{ (Sid 1) = (At -5); (Sid 2) = (At -700) }
Check ((Test-Held $r "usage limit unknown")) "nor with another session's taking that is too old beside it"
$r = PassM 6 -Moves @{ (Sid 1) = (At -5); (Sid 2) = (At -100) }
Check ((Decided $r).action -ceq "nudge" -and (Rang) -eq 1) "another session's taking, inside the window, releases it"
Start-Case; Seat 1 @{ Limited = "unknown" }; Seat 2 @{ Limited = "unknown" }
$r = PassM 0 -Moves @{ (Sid 1) = (At -5) }
Check ((Decided $r 2).action -ceq "nudge" -and (Decided $r 1).action -ceq "wait" -and "$((Decided $r 1).reason)".StartsWith("usage limit unknown")) "one session's taking is evidence for the OTHER and not for itself"
# IT IS ONLY ASKED OF A SESSION THAT CAN BE REACHED: the fleet says unknown for every row it cannot reach.
Start-Case; Seat 1 @{ Limited = "unknown"; Reachable = "no" }
$r = PassM 0 -MovedAt (At -1)
Check ((Decided $r).action -ceq "wait" -and (Decided $r).reason -ceq "reachable is no" -and (Rang) -eq 0) "a session that cannot be reached, with its limit unknown, is held as unreachable whatever the evidence says"
$r = PassM 3
Check ((Decided $r).reason -ceq "reachable is no" -and $r.limited.Count -eq 0 -and $script:ledger.Count -eq 0) "and with no evidence either: nothing is said of its limit, and nothing is noted against it"
Start-Case; Seat 1 @{ Limited = "yes"; LimitedUntil = (At 600); Reachable = "unknown" }
Check ((Decided (PassM 0)).reason -ceq "reachable is unknown") "reachable is decided before the limit is asked, for a limit that is known too"
# ...and it is released like a limit with no known end: by the hour, uncounted.
Start-Case; Seat 1 @{ Limited = "unknown" }
$null = PassM 0
$r = PassM 3600
Check ((Decided $r).action -ceq "nudge" -and (Rang) -eq 1 -and $script:ledger[(Sid 1)].attempts -eq 0) "with no evidence for an hour, it is knocked for once, uncounted: a lone session is not stuck for ever behind a transcript nobody can read"
# WHAT IS EVIDENCE: another session ACKNOWLEDGING mail. Not a woken answer, not an inbox that changed.
Start-Case; Seat 1 @{ Limited = "unknown" }; Seat 2 @{ UnreadCount = 0; OldestUnreadAt = $null }
$r = PassM 0
Check ((Test-Held $r "usage limit unknown") -and $r.acks.ContainsKey((Sid 2)) -and $null -eq $r.acks[(Sid 2)]) "a session that has never acknowledged any mail is seen, and is no evidence"
Seat 2 @{ UnreadCount = 3; OldestUnreadAt = (At -5) }
$r = PassM 3
Check ((Decided $r 1).action -ceq "wait" -and "$((Decided $r 1).reason)".StartsWith("usage limit unknown")) "mail ARRIVING in another session's inbox is no evidence"
Seat 2 @{ UnreadCount = 0; OldestUnreadAt = $null }
$r = PassM 6
Check ((Decided $r 1).action -ceq "wait" -and "$((Decided $r 1).reason)".StartsWith("usage limit unknown")) "another session's inbox EMPTYING is no evidence either: the fleet's own repair moves a mailbox with no turn taken"
Seat 2 @{ UnreadCount = 0; OldestUnreadAt = $null; LastAckedAt = (At 5) }
$r = PassM 9
Check ((Decided $r 1).action -ceq "nudge" -and $r.acks[(Sid 2)] -eq (At 5)) "another session ACKNOWLEDGING mail four seconds ago is: the limited-unknown session is nudged"
Start-Case; Seat 1 @{ Limited = "unknown" }; Seat 2 @{ UnreadCount = 0; OldestUnreadAt = $null; LastAckedAt = (At -5); Acked = "unknown" }
$r = PassM 0
Check ((Test-Held $r "usage limit unknown") -and -not $r.acks.ContainsKey((Sid 2))) "an acknowledgement its waker could not read (acked unknown) is no evidence, whatever time stands beside it"
Start-Case; Seat 1 @{ Limited = "unknown" }; Seat 2 @{ UnreadCount = 0; OldestUnreadAt = $null; LastAckedAt = (At -5); Reachable = "no" }
$r = PassM 0
Check ((Decided $r 1).action -ceq "wait" -and -not $r.acks.ContainsKey((Sid 2))) "nor is the acknowledgement of a session that cannot be reached: it is not known to be a live one"
Start-Case; Seat 1 @{ Limited = "unknown" }; Seat 2 @{ UnreadCount = 0; OldestUnreadAt = $null; LastAckedAt = (At 500) }
$r = PassM 0
Check ((Decided $r 1).action -ceq "wait") "nor one dated in the future"
# The silence's own reading of the same thing.
$seenA = @{ (Sid 1) = $null; (Sid 2) = $null }
$e1 = Update-HordeWakeSilence -Seen $null -Entries @((New-HordeWakeEntry -At $t0 -Kind "nudge" -Id (Sid 1) -Outcome "woken")) -Acks $seenA -Now (At 0) -Settings $settings
Check (-not $e1.moved -and $e1.seen.acks.Count -eq 2) "a nudge answered woken is NOT a session answering: every knock of the incident was answered woken"
$e2 = Update-HordeWakeSilence -Seen $e1.seen -Entries @() -Acks @{ (Sid 1) = $null; (Sid 2) = (At 20) } -Now (At 30) -Settings $settings
Check ($e2.moved -and $e2.seen.acks[(Sid 2)] -eq (At 20)) "a session seen before that now shows an acknowledgement is one"
$e3 = Update-HordeWakeSilence -Seen $e2.seen -Entries @((New-HordeWakeEntry -At $t0 -Kind "nudge" -Id (Sid 1) -Outcome "woken")) -Acks @{ (Sid 1) = $null; (Sid 2) = (At 20) } -Now (At 60) -Settings $settings
Check (-not $e3.moved) "the same acknowledgement seen again is not a new one"
$e4 = Update-HordeWakeSilence -Seen $e3.seen -Entries @() -Acks @{ (Sid 1) = $null; (Sid 2) = (At 10) } -Now (At 90) -Settings $settings
$e5 = Update-HordeWakeSilence -Seen $e3.seen -Entries @() -Acks @{ (Sid 1) = $null; (Sid 2) = (At 500) } -Now (At 90) -Settings $settings
$e6 = Update-HordeWakeSilence -Seen $e3.seen -Entries @() -Acks @{ (Sid 1) = $null; (Sid 2) = (At 20); (Sid 7) = (At 80) } -Now (At 90) -Settings $settings
Check (-not $e4.moved -and -not $e5.moved -and -not $e6.moved) "an older acknowledgement, one dated in the future, and what a session seen for the FIRST time already had are none of them a session answering now"
$e7 = Update-HordeWakeSilence -Seen $e3.seen -Entries @() -Acks @{ (Sid 2) = (At 85) } -Now (At 90) -Settings $settings
Check ($e7.moved -and $e7.seen.acks.ContainsKey((Sid 1))) "a newer one is; and a session this pass could not read is remembered as it was"

# THE JOURNAL: once per session per limit.
$said = Update-HordeWakeLimited -Seen @{} -Limited @{ (Sid 1) = "usage limit until 2026-10-12T08:10:00Z" } -Known @((Sid 1)) -Now (At 0)
Check (@($said.entries).Count -eq 1 -and $said.entries[0].kind -ceq "usage-limit" -and $said.entries[0].id -ceq (Sid 1) -and $said.entries[0].outcome -ceq "limited" -and "$($said.entries[0].reason)".StartsWith("usage limit until 2026-10-12T08:10:00Z: it is not nudged before then")) "a session that becomes limited is journaled, with until when"
$again = Update-HordeWakeLimited -Seen $said.seen -Limited @{ (Sid 1) = "usage limit until 2026-10-12T08:10:00Z" } -Known @((Sid 1)) -Now (At 3)
Check (@($again.entries).Count -eq 0) "and not again on the next pass"
$open = Update-HordeWakeLimited -Seen $again.seen -Limited @{ (Sid 1) = "usage limit, end unknown" } -Known @((Sid 1)) -Now (At 6)
Check (@($open.entries).Count -eq 1 -and "$($open.entries[0].reason)".StartsWith("usage limit, end unknown: it is not nudged until a session of the fleet takes mail, or once an hour")) "a limit whose end changes is another limit, journaled once more"
$blind = Update-HordeWakeLimited -Seen $open.seen -Limited @{} -Known @() -Now (At 9)
$back = Update-HordeWakeLimited -Seen $blind.seen -Limited @{ (Sid 1) = "usage limit, end unknown" } -Known @((Sid 1)) -Now (At 12)
Check (@($blind.entries).Count -eq 0 -and @($back.entries).Count -eq 0) "a pass that could not read the session does not make its limit news again"
$over = Update-HordeWakeLimited -Seen $back.seen -Limited @{} -Known @((Sid 1)) -Now (At 15)
$anew = Update-HordeWakeLimited -Seen $over.seen -Limited @{ (Sid 1) = "usage limit, end unknown" } -Known @((Sid 1)) -Now (At 18)
Check ($over.seen.Count -eq 0 -and @($anew.entries).Count -eq 1) "a session read as no longer limited is forgotten, and a later limit is journaled as a new one"
# probeAt is kept in the ledger file.
$hl = Join-Path $pinned.home ("probe-" + [guid]::NewGuid().ToString("N")); New-Item -ItemType Directory -Path $hl | Out-Null
$kept = @{}; $kept[(Sid 1)] = New-HordeWakeLedgerRow -Attempts 0 -LastAttemptAt (At 0) -LastOutcome "limited" -MailAt (At -60) -ProbeAt (At 7)
Save-HordeWakeLedger -Ledger $kept -Shadow -HordeHome $hl
$readBack = Read-HordeWakeLedger -Shadow -HordeHome $hl
Check ($readBack.state -ceq "known" -and $readBack.value.ledger.ContainsKey((Sid 1)) -and (Get-HordeWakeEntryValue $readBack.value.ledger[(Sid 1)] "probeAt") -eq (At 7)) "when a session was last probed is saved with the ledger and read back"

Write-Host ""
Write-Host "--- a silent fleet: woken by everybody, taken by nobody, is a fleet that cannot answer ---" -ForegroundColor Cyan

# THE TIMELINES BELOW ARE WRITTEN FOR A WINDOW OF TEN MINUTES, set here: they are about what counts as
# silence, not about how long the window is. The default, and why it is five, has its own section.
$ten = Get-HordeWakeSettings -Overrides @{ fleetSilentMinutes = 10 }
function Knock { param([int]$N, [string]$Outcome = "woken", [string]$Kind = "nudge") return (New-HordeWakeEntry -At $t0 -Kind $Kind -Id (Sid $N) -Outcome $Outcome) }
function Walk {
    # Passes every 30 s from -From to -To, one knock on each, round the sessions in -Who; returns
    # { seen; entries; last }. -Acks is what every pass reads of who has acknowledged mail.
    param($Seen, [int]$From, [int]$To, [int[]]$Who = @(1, 2, 3), $Acks = $unread)
    $all = New-Object System.Collections.ArrayList
    $last = $null
    $i = 0
    for ($s = $From; $s -le $To; $s += 30) {
        $last = Update-HordeWakeSilence -Seen $Seen -Entries @((Knock $Who[$i % $Who.Count])) -Acks $Acks -Now (At $s) -Settings $ten
        $Seen = $last.seen; $i++
        foreach ($e in @($last.entries)) { [void]$all.Add($e) }
    }
    return [pscustomobject]@{ seen = $Seen; entries = $all.ToArray(); last = $last }
}
# Three sessions, each seen, none of which has ever acknowledged any mail.
$unread = @{ (Sid 1) = $null; (Sid 2) = $null; (Sid 3) = $null }
$w = Walk -Seen $null -From 0 -To 570
Check (@($w.entries).Count -eq 0 -and $w.last.silent -eq $false -and $w.last.declared -eq $false -and $w.seen.quietSince -eq (At 0)) "nine and a half minutes of nudges all answered woken, and no mail taken, is not yet a silent fleet"
$d = Update-HordeWakeSilence -Seen $w.seen -Entries @() -Acks $unread -Now (At 600) -Settings $ten
Check ($d.silent -and $d.declared -and @($d.entries).Count -eq 1 -and $d.entries[0].kind -ceq "fleet-silent" -and $d.entries[0].id -ceq "" -and "$($d.entries[0].reason)".StartsWith("for 10 minutes every nudge - 19, to 3 sessions - was answered woken, and no session took its mail")) "at ten minutes it is: one line, saying how many nudges, to how many sessions"
Check ($null -ne $d.condition -and $d.condition.kind -ceq "fleet-silent" -and $d.condition.instance -ceq "2026-10-12T08:00:00.0000000Z" -and $d.moved -eq $false) "with a condition for the warchief, named by when the quiet began"
$e = Update-HordeWakeSilence -Seen $d.seen -Entries @((Knock 1)) -Acks $unread -Now (At 900) -Settings $ten
Check ($e.silent -and -not $e.declared -and @($e.entries).Count -eq 0 -and $null -eq $e.condition) "while it lasts nothing more is said, and it is found silent once"
$grown = @{ (Sid 1) = $null; (Sid 2) = $null; (Sid 3) = $null; (Sid 4) = (At 890) }
$f = Update-HordeWakeSilence -Seen $e.seen -Entries @() -Acks $grown -Now (At 903) -Settings $ten
Check ($f.silent -and -not $f.moved) "a session seen for the first time, with an acknowledgement it already had, is not a session answering: the fleet is still silent"
$partial = @{ (Sid 1) = $null }
$g = Update-HordeWakeSilence -Seen $f.seen -Entries @() -Acks $partial -Now (At 906) -Settings $ten
Check ($g.silent -and -not $g.moved -and $g.seen.acks.ContainsKey((Sid 2))) "nor is a pass that could not read a session: what it held is remembered"
$took = @{ (Sid 1) = $null; (Sid 2) = (At 905); (Sid 3) = $null; (Sid 4) = (At 890) }
$m = Update-HordeWakeSilence -Seen $g.seen -Entries @() -Acks $took -Now (At 909) -Settings $ten
Check (-not $m.silent -and $m.moved -and @($m.entries).Count -eq 1 -and $m.entries[0].kind -ceq "fleet-moving" -and $null -eq $m.seen.quietSince -and @($m.seen.nudges).Count -eq 0) "a session that acknowledges mail ends it: one fleet-moving line, and the count of quiet starts over"
$next = @{ (Sid 1) = (At 950); (Sid 3) = $null; (Sid 4) = (At 890) }
$m2 = Update-HordeWakeSilence -Seen $m.seen -Entries @() -Acks $next -Now (At 960) -Settings $ten
Check ($m2.moved -and @($m2.entries).Count -eq 0) "another session acknowledging mail later is movement too, and is said only when the fleet had been called silent"
# What is NOT a silent fleet.
$two = Walk -Seen $null -From 0 -To 900 -Who @(1, 2)
Check (@($two.entries).Count -eq 0 -and -not $two.last.silent) "two sessions that do not answer are two sessions: it takes three for a fleet"
$busy = Walk -Seen $null -From 0 -To 300
$b = Update-HordeWakeSilence -Seen $busy.seen -Entries @((Knock 2 "busy")) -Acks $unread -Now (At 330) -Settings $ten
$after = Walk -Seen $b.seen -From 360 -To 900
Check (@($after.entries).Count -eq 0 -and -not $after.last.silent) "one nudge answered busy is a session at work: with it in the last ten minutes the fleet is not silent"
$later = Walk -Seen $after.seen -From 930 -To 960
Check (@($later.entries | Where-Object { $_.kind -ceq "fleet-silent" }).Count -eq 1) "ten minutes after that busy answer, with only woken since, it is"
$k = Update-HordeWakeSilence -Seen $busy.seen -Entries @((Knock 2 "killed" "nudge-killed")) -Acks $unread -Now (At 330) -Settings $ten
Check (-not (Walk -Seen $k.seen -From 360 -To 900).last.silent) "a nudge that had to be killed is not a woken either"
$mid = Walk -Seen $null -From 0 -To 300
$mv = Update-HordeWakeSilence -Seen $mid.seen -Entries @() -Acks @{ (Sid 1) = $null; (Sid 2) = (At 305); (Sid 3) = $null } -Now (At 310) -Settings $ten
$rest = Walk -Seen $mv.seen -From 330 -To 900
Check ($mv.moved -and @($mv.entries).Count -eq 0 -and -not $rest.last.silent) "mail acknowledged half-way starts the ten minutes over: at ten minutes from the first nudge the fleet is not silent"
Check ((Walk -Seen $rest.seen -From 930 -To 930).last.silent) "and at ten minutes from the first nudge after it, it is"
$none = Update-HordeWakeSilence -Seen $null -Entries @() -Acks @{} -Now (At 0) -Settings $ten
Check (-not $none.silent -and -not $none.moved -and (Walk -Seen $none.seen -From 3600 -To 3600).last.silent -eq $false) "a watcher that has nudged nobody has no quiet to count from"
# A SILENCE IS DECLARED ONLY WHERE ITS END CAN BE SEEN.
$blind = Walk -Seen $null -From 0 -To 1800 -Acks @{}
Check (@($blind.entries).Count -eq 0 -and -not $blind.last.silent) "through a waker that reads no acknowledgements the fleet is never called silent, however long everybody answers woken: there would be no way to see it end"
# WHILE THE FLEET IS SILENT every nudge is a probe: the longest step, and never counted.
Start-Case; Seat 1; Seat 2; Seat 3
foreach ($s in @(0, 3, 6, 9, 12, 15, 30, 33, 36)) { $null = Pass $s }
Check ($script:ledger[(Sid 1)].attempts -eq 3 -and $script:ledger[(Sid 2)].attempts -eq 3 -and $script:ledger[(Sid 3)].attempts -eq 3) "CONTROL: three sessions, each nudged three times and counted"
$script:ledger = Reset-HordeWakeLedgerAttempts -Ledger $script:ledger
Check (@($script:ledger.Values | Where-Object { $_.attempts -ne 0 -or $_.probeAt -ne $_.lastAttemptAt }).Count -eq 0) "found silent, every attempt is forgiven: they went to sessions that could not answer; when each was last asked is kept"
function Hush { param([double]$Seconds) Set-HordeMemoryWakerClock (At $Seconds); $r = Invoke-HordeWakePass -Send -Waker $memory -Now (At $Seconds) -Settings $settings -Ledger $script:ledger -Silent; $script:ledger = $r.ledger; return $r }
$before = (Rang)
$r = Hush 100
Check ((Rang) -eq $before -and @($r.decisions | Where-Object { $_.action -ceq "wait" -and "$($_.reason)".StartsWith("the fleet is silent: it is asked only every 300 s") }).Count -eq 3) "in a silent fleet nobody is asked before the longest step has passed since it was last asked"
$gave = 0; for ($s = 330; $s -le 14400; $s += 3) { $gave += @((Hush $s).entries | Where-Object { $_.kind -ceq "gave-up" }).Count }
$asked = (Rang) - $before
Check ($asked -ge 44 -and $asked -le 48 -and $gave -eq 0 -and @($script:ledger.Values | Where-Object { $_.attempts -ne 0 }).Count -eq 0) ("four hours of silence are ONE knock every five minutes for the whole fleet of three - not one for each - and not one is counted or given up on (" + $asked + " knocks)")
$each = @(1, 2, 3 | ForEach-Object { (Rang $_) })
Check ((($each | Measure-Object -Maximum).Maximum - ($each | Measure-Object -Minimum).Minimum) -le 1) ("and the probe goes round: each of the three was asked as often as the others, within one (" + ($each -join ",") + ")")
$times = @(Get-HordeMemoryWakerNudges | Where-Object { $_.at -ge (At 330) } | ForEach-Object { $_.at } | Sort-Object)
$gaps = @(for ($i = 1; $i -lt $times.Count; $i++) { ($times[$i] - $times[$i - 1]).TotalSeconds })
Check ($gaps.Count -gt 40 -and ($gaps | Measure-Object -Minimum).Minimum -ge 300) ("no two knocks anywhere in the fleet are less than five minutes apart (shortest gap " + ($gaps | Measure-Object -Minimum).Minimum + " s)")
$r = Pass 14403
Check (@($r.decisions | Where-Object { $_.action -ceq "nudge" }).Count -eq 1 -and @($script:ledger.Values | Where-Object { $_.attempts -eq 1 }).Count -eq 1) "when the fleet moves again the next nudge is an ordinary one, counted from nothing"
Start-Case; Seat 1
$null = Pass 0 -Using $one
$script:ledger = Reset-HordeWakeLedgerAttempts -Ledger $script:ledger
Check ((Get-HordeWakeEntryValue $script:ledger[(Sid 1)] "gaveUp") -ne $true -and $script:ledger[(Sid 1)].attempts -eq 0) "and a session already given up on is given its attempts back"

Write-Host ""
Write-Host "--- the probes of a silent fleet are stretched and capped: the long run ---" -ForegroundColor Cyan

$shippedNow = Get-HordeWakeSettings
Check ($shippedNow.silentProbeStretch -eq 2 -and $shippedNow.silentProbeMaxSeconds -eq 3600 -and $shippedNow.maxSilentProbes -eq 12) "the three settings are named, at 2, 3600 s and 12"
$waits = @(0..14 | ForEach-Object { Get-HordeWakeSilentProbeSeconds -Probes $_ -Settings $shippedNow })
Check (($waits -join ",") -ceq "300,300,600,1200,2400,3600,3600,3600,3600,3600,3600,3600,3600,3600,3600") ("the wait before each probe: the longest back-off step, then doubled each time, then an hour for good (" + ($waits -join ",") + ")")
Check ((Get-HordeWakeSilentProbeSeconds -Probes 9 -Settings (Get-HordeWakeSettings -Overrides @{ silentProbeMaxSeconds = 10 })) -eq 300 -and (Get-HordeWakeSilentProbeSeconds -Probes 9 -Settings (Get-HordeWakeSettings -Overrides @{ silentProbeStretch = 0 })) -eq 300) "settings that would shorten the wait below the longest back-off step do not: it is never less"
function Long {
    # The watcher's loop over three sessions that answer woken and never acknowledge mail, a pass
    # every 30 s for -Hours; returns when (s) each probe of the silent fleet was typed, the lines
    # journaled of the silence, and what was left.
    param([double]$Hours, $Using, $AckAt = $null)
    Reset-HordeMemoryWaker
    foreach ($n in 1..3) { Set-HordeMemoryWakerSession -Id (Sid $n) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60) }
    $ledger = @{}; $seen = $null; $silent = $false; $probes = New-Object System.Collections.ArrayList; $said = New-Object System.Collections.ArrayList; $normal = 0
    for ($t = 0; $t -le [int]($Hours * 3600); $t += 30) {
        if ($null -ne $AckAt -and $t -eq $AckAt) { Set-HordeMemoryWakerSession -Id (Sid 2) -Role "orc" -UnreadCount 0 -LastAckedAt (At ($t - 1)) }
        Set-HordeMemoryWakerClock (At $t)
        $sent = 0; if ($null -ne $seen) { $sent = [int]$seen.probes }
        $r = Invoke-HordeWakePass -Send -Waker $memory -Now (At $t) -Settings $Using -Ledger $ledger -Silent:$silent -SilentProbes $sent
        $typed = @($r.entries | Where-Object { $_.kind -ceq "nudge" }).Count
        if ($silent) { for ($k = 0; $k -lt $typed; $k++) { [void]$probes.Add($t) } } else { $normal += $typed }
        $sil = Update-HordeWakeSilence -Seen $seen -Entries $r.entries -Acks $r.acks -Now (At $t) -Settings $Using
        $ledger = $r.ledger
        if ($sil.declared) { $ledger = Reset-HordeWakeLedgerAttempts -Ledger $ledger }
        if ($sil.moved) { $ledger = Set-HordeWakeLedgerProbesDue -Ledger $ledger }
        foreach ($e in @($sil.entries)) { [void]$said.Add($e.kind + "@" + $t) }
        $seen = $sil.seen; $silent = $sil.silent
    }
    $typedAll = @(Get-HordeMemoryWakerNudges).Count
    Reset-HordeMemoryWaker
    return [pscustomobject]@{ probes = $probes.ToArray(); said = $said.ToArray(); seen = $seen; normal = $normal; typed = $typedAll }
}
$day = Long -Hours 24 -Using $shippedNow
$gaps = @(for ($i = 1; $i -lt $day.probes.Count; $i++) { $day.probes[$i] - $day.probes[$i - 1] })
Check ($day.probes.Count -eq 12 -and $day.seen.probes -eq 12 -and $day.seen.silent -eq $true) ("TWENTY-FOUR HOURS of a fleet that never acknowledges mail: twelve probes are typed in all, not the 288 of one every five minutes (" + $day.probes.Count + ")")
Check (($gaps -join ",") -ceq "300,600,1200,2400,3600,3600,3600,3600,3600,3600,3600") ("and they are stretched: 5, 10, 20, 40 minutes apart, then an hour (" + ($gaps -join ",") + ")")
Check ($day.probes.Count -gt 0 -and ($day.probes[$day.probes.Count - 1] - $day.probes[0]) -le 30000 -and $day.typed -eq ($day.normal + 12)) ("the last is typed within nine hours of the first, and nothing at all is typed in the fifteen hours after it (" + $day.typed + " lines in the day)")
Check (@($day.said | Where-Object { $_ -clike "silent-probes-ended@*" }).Count -eq 1 -and @($day.said | Where-Object { $_ -clike "fleet-silent@*" }).Count -eq 1) ("the journal says once that the fleet was found silent and once that its probes have ended (" + ($day.said -join ",") + ")")
$woke = Long -Hours 14 -Using $shippedNow -AckAt 43200
Check (@($woke.said | Where-Object { $_ -ceq "fleet-moving@43200" }).Count -eq 1 -and $woke.seen.silent -eq $false -and $woke.seen.probes -eq 0 -and $woke.typed -gt ($woke.normal - 1) -and $woke.normal -gt $day.normal) ("STOPPING LOSES NOTHING: a session that acknowledges mail at twelve hours, long after the last probe, ends the silence at that pass, the count starts over, and the other sessions are nudged again (" + ($woke.said -join ",") + ")")
$few = Long -Hours 6 -Using (Get-HordeWakeSettings -Overrides @{ maxSilentProbes = 3 })
Check ($few.probes.Count -eq 3) ("the cap is the setting: at 3, three probes in six hours (" + $few.probes.Count + ")")
$flat = Long -Hours 2 -Using (Get-HordeWakeSettings -Overrides @{ silentProbeStretch = 1; maxSilentProbes = 1000 })
Check ($flat.probes.Count -ge 20) ("CONTROL: with no stretch and no cap to speak of, two hours type a probe every five minutes - what it did before (" + $flat.probes.Count + ")")
# The count is the silence's: a nudge while NOT silent is not one, and it is kept from pass to pass.
$c1 = Update-HordeWakeSilence -Seen ([pscustomobject]@{ silent = $true; quietSince = (At 0); nudges = @(); acks = @{ (Sid 1) = $null }; probes = 10 }) -Entries @((Knock 1)) -Acks @{ (Sid 1) = $null } -Now (At 5000) -Settings $shippedNow
$c2 = Update-HordeWakeSilence -Seen $c1.seen -Entries @((Knock 2)) -Acks @{ (Sid 1) = $null } -Now (At 9000) -Settings $shippedNow
$c3 = Update-HordeWakeSilence -Seen $c2.seen -Entries @() -Acks @{ (Sid 1) = $null } -Now (At 9030) -Settings $shippedNow
Check ($c1.seen.probes -eq 11 -and @($c1.entries).Count -eq 0 -and $c2.seen.probes -eq 12 -and @($c2.entries).Count -eq 1 -and $c2.entries[0].kind -ceq "silent-probes-ended" -and @($c3.entries).Count -eq 0 -and $c3.seen.probes -eq 12) "the eleventh probe is counted and nothing said; the twelfth is the last, said once; the pass after says nothing more"
$c4 = Update-HordeWakeSilence -Seen $null -Entries @((Knock 1)) -Acks @{ (Sid 1) = $null } -Now (At 0) -Settings $shippedNow
Check ($c4.seen.probes -eq 0) "a nudge in a fleet that is not silent is no probe"
Start-Case; Seat 1; Seat 2; Seat 3
$r = Invoke-HordeWakePass -Send -Waker $memory -Now (At 0) -Settings $shippedNow -Ledger @{} -Silent -SilentProbes 12
Check ((Rang) -eq 0 -and @($r.decisions | Where-Object { "$($_.reason)".StartsWith("the fleet is silent: 12 probes went unanswered and no more are sent") }).Count -eq 3) "a pass told the silence has had its twelve types nothing, and each session's decision says why"
$r = Invoke-HordeWakePass -Send -Waker $memory -Now (At 0) -Settings $shippedNow -Ledger @{} -Silent -SilentProbes 11
Check ((Rang) -eq 1) "CONTROL: told eleven, it sends the twelfth"
Reset-HordeMemoryWaker

Write-Host ""
Write-Host "--- at the defaults, a silent fleet is found BEFORE anybody is given up on ---" -ForegroundColor Cyan

function Drive {
    # The watcher's own loop, as core/WakeRun.ps1 runs it, over sessions that answer woken and never take
    # their mail: a pass every 3 s for -Seconds, session n's mail arriving at -Arrive[n-1]. Returns when
    # the fleet was first found silent and when a session was first given up on (seconds, or $null).
    param([int[]]$Arrive, $Using, [int]$Seconds = 1200)
    Reset-HordeMemoryWaker
    $ledger = @{}; $seen = $null; $silent = $false; $silentAt = $null; $gaveUpAt = $null; $seated = @{}
    for ($t = 0; $t -le $Seconds; $t += 3) {
        for ($n = 1; $n -le $Arrive.Count; $n++) { if (-not $seated.ContainsKey($n) -and $t -ge $Arrive[$n - 1]) { $seated[$n] = $true; Set-HordeMemoryWakerSession -Id (Sid $n) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At ($Arrive[$n - 1] - 60)) } }
        Set-HordeMemoryWakerClock (At $t)
        $r = Invoke-HordeWakePass -Send -Waker $memory -Now (At $t) -Settings $Using -Ledger $ledger -Silent:$silent
        $sil = Update-HordeWakeSilence -Seen $seen -Entries $r.entries -Acks $r.acks -Now (At $t) -Settings $Using
        $ledger = $r.ledger
        if ($sil.declared) { $ledger = Reset-HordeWakeLedgerAttempts -Ledger $ledger }
        if ($sil.moved) { $ledger = Set-HordeWakeLedgerProbesDue -Ledger $ledger }
        $seen = $sil.seen; $silent = $sil.silent
        if ($null -eq $gaveUpAt -and @($r.entries | Where-Object { $_.kind -ceq "gave-up" }).Count -gt 0) { $gaveUpAt = $t }
        if ($null -eq $silentAt -and @($sil.entries | Where-Object { $_.kind -ceq "fleet-silent" }).Count -gt 0) { $silentAt = $t }
    }
    Reset-HordeMemoryWaker
    return [pscustomobject]@{ silentAt = $silentAt; gaveUpAt = $gaveUpAt }
}
# THE DEFAULTS, AS SHIPPED - not this suite's $settings, in case a case above ever changes them - and
# the same with the silence switched off, to see when the cap alone would have given up.
$shipped = Get-HordeWakeSettings
$deaf = Get-HordeWakeSettings -Overrides @{ fleetSilentMinutes = 1000000 }
foreach ($case in @(
        @{ what = "one session asked as fast as the back-off allows, two more with mail a little later"; arrive = @(0, 100, 100) },
        @{ what = "three sessions with mail from the start"; arrive = @(0, 0, 0) })) {
    $with = Drive -Arrive $case.arrive -Using $shipped
    $without = Drive -Arrive $case.arrive -Using $deaf
    $said = "silent at " + $with.silentAt + " s, gave up at " + $with.gaveUpAt + " s; with the silence off, gave up at " + $without.gaveUpAt + " s"
    Check ($null -ne $without.gaveUpAt -and $null -eq $without.silentAt) ("CONTROL, " + $case.what + ": with the silence off the cap does give up on a session (" + $said + ")")
    Check ($null -ne $with.silentAt -and $null -ne $without.gaveUpAt -and $with.silentAt -lt $without.gaveUpAt) ($case.what + ": at the defaults the fleet is found silent strictly before the cap would have given up on anybody (" + $said + ")")
    Check ($null -ne $with.silentAt -and $null -eq $with.gaveUpAt) ($case.what + ": and so nobody is given up on at all, in twenty minutes of a fleet that cannot answer")
}

Write-Host ""
Write-Host "--- a fleet that cannot be read: a hiccup at first, permanent after ten failures in a row, said once ---" -ForegroundColor Cyan

$bad = New-HordeUnknown -Reason "records-unreadable: the registry is not JSON"
$fr = $null
$said = New-Object System.Collections.ArrayList
foreach ($n in 1..9) { $step = Update-HordeWakeFleetRead -Seen $fr -Listing $bad -Now (At ($n * 3)) -Settings $settings; $fr = $step.seen; foreach ($e in @($step.entries)) { [void]$said.Add($e) } }
Check ($said.Count -eq 0 -and $fr.failures -eq 9 -and $fr.told -eq $false -and $fr.since -eq (At 3) -and $step.quiet -eq $false -and $null -eq $step.condition) "nine failed readings in a row are not yet permanent: nothing is said, and the journal's own line for each stands"
$step = Update-HordeWakeFleetRead -Seen $fr -Listing $bad -Now (At 30) -Settings $settings; $fr = $step.seen
Check (@($step.entries).Count -eq 1 -and $step.entries[0].kind -ceq "fleet-read-failing" -and $step.entries[0].outcome -ceq "permanent" -and $step.entries[0].id -ceq "" -and "$($step.entries[0].reason)".StartsWith("10 readings of the fleet in a row have failed, the first at 2026-10-12T08:00:03Z: records-unreadable")) "the tenth makes it permanent: one line saying how many, since when and why"
Check ($step.quiet -eq $true -and $null -ne $step.condition -and $step.condition.kind -ceq "fleet-read-failing" -and $step.condition.subject -ceq "" -and $step.condition.instance -ceq "2026-10-12T08:00:03.0000000Z") "with a condition for the warchief to be told, named by when the failing began, and quiet from then on"
$more = 0; foreach ($n in 11..40) { $step = Update-HordeWakeFleetRead -Seen $fr -Listing $bad -Now (At ($n * 3)) -Settings $settings; $fr = $step.seen; $more += @($step.entries).Count; if ($null -ne $step.condition -or -not $step.quiet) { $more += 100 } }
Check ($more -eq 0) "thirty more failures say nothing more, raise no second condition, and stay quiet"
$step = Update-HordeWakeFleetRead -Seen $fr -Listing (New-HordeKnown -Value @()) -Now (At 200) -Settings $settings
Check (@($step.entries).Count -eq 1 -and $step.entries[0].kind -ceq "recovered" -and "$($step.entries[0].reason)".Contains("after 40 readings") -and $step.seen.failures -eq 0 -and $step.seen.told -eq $false -and $step.quiet -eq $false) "the reading that works says recovered, once, and the count starts over"
$step = Update-HordeWakeFleetRead -Seen (Update-HordeWakeFleetRead -Seen $null -Listing $bad -Now (At 0) -Settings $settings).seen -Listing (New-HordeKnown -Value @()) -Now (At 3) -Settings $settings
Check (@($step.entries).Count -eq 0) "a hiccup that mends says nothing: recovered is only for what had been called permanent"
# THE WAKER'S OWN COUNT, when it gives one: its readings, not the watcher's passes.
$counted = New-HordeUnknown -Reason "registry-absent"; Add-Member -InputObject $counted -MemberType NoteProperty -Name "failures" -Value 3
$fr = $null; $lines = 0
foreach ($n in 1..40) { $step = Update-HordeWakeFleetRead -Seen $fr -Listing $counted -Now (At ($n * 3)) -Settings $settings; $fr = $step.seen; $lines += @($step.entries).Count }
Check ($lines -eq 0 -and $fr.failures -eq 3) "forty passes over a waker that says three of its readings have failed are three failures, not forty: a waker that backs off reads far less often than the watcher passes"
$counted.failures = 10
$step = Update-HordeWakeFleetRead -Seen $fr -Listing $counted -Now (At 200) -Settings $settings
Check (@($step.entries).Count -eq 1 -and $step.entries[0].kind -ceq "fleet-read-failing") "and when the waker's own count reaches ten, that is permanent"
Check ((Update-HordeWakeFleetRead -Seen $null -Listing $null -Now $t0 -Settings $settings).quiet -eq $false) "with no waker there is no reading, and nothing to say of it"
Start-Case; Seat
Set-HordeMemoryWakerFault -Call "targets" -Kind "throw"
$r = Pass 0
Check ($null -ne $r.listing -and $r.listing.state -ceq "unknown" -and $r.warchief -ceq "") "the pass hands on what the listing answered, for the tick to count; and a fleet it cannot read has no warchief it can name"
Reset-HordeMemoryWaker
# WHO THE WARCHIEF IS, for whoever must tell it something: the one session with that role.
Start-Case
Set-HordeMemoryWakerSession -Id (Sid 1) -Role "orc" -UnreadCount 0
Set-HordeMemoryWakerSession -Id (Sid 2) -Role "warchief" -UnreadCount 0
Check ((Pass 0).warchief -ceq (Sid 2)) "the pass names the warchief: the one session with that role"
Set-HordeMemoryWakerSession -Id (Sid 3) -Role "warchief" -UnreadCount 0
Check ((Pass 3).warchief -ceq "") "two sessions with that role are no warchief: one is never chosen over the other"
Reset-HordeMemoryWaker

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
Check ((Read-HordeWakeHeartbeat -Mode "live").state -ceq "absent") "with no heartbeat the watcher has never run here: absent"
Check (@(Read-HordeWakeJournalTail -Mode "live").Count -eq 0) "and the journal has no lines"
Check ((Read-HordeWakeLedger -Mode "live").state -ceq "absent") "and no ledger was saved"
# THE BARE NAMES ARE NOBODY'S. Builds from before the two modes wrote them, in shadow; a home that
# holds only those has had neither mode run in it.
$legacyHome = Join-Path $pinned.home "legacy"
New-Item -ItemType Directory -Path (Join-Path $legacyHome "wake") -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $legacyHome "wake\heartbeat.json"), '{"at":"2026-10-12T07:00:00.0000000Z","pid":7,"pass":900,"shadow":true}')
[System.IO.File]::WriteAllText((Join-Path $legacyHome "wake\journal.jsonl"), '{"at":"2026-10-12T07:00:00.0000000Z","kind":"would-nudge","id":"x","outcome":"would-nudge","reason":"old"}' + "`n")
[System.IO.File]::WriteAllText((Join-Path $legacyHome "wake\ledger.json"), '{"schemaVersion":1,"sessions":[{"id":"x","attempts":3,"lastAttemptAt":"2026-10-12T07:00:00.0000000Z","lastOutcome":"would-nudge"}]}')
Check ((Read-HordeWakeHeartbeat -Mode "live" -HordeHome $legacyHome).state -ceq "absent" -and (Read-HordeWakeHeartbeat -Shadow -HordeHome $legacyHome).state -ceq "absent") "in a home holding only the unsuffixed files of earlier builds, neither the live nor the shadow watcher has ever run"
Check (@(Read-HordeWakeJournalTail -Mode "live" -HordeHome $legacyHome).Count -eq 0 -and @(Read-HordeWakeJournalTail -Shadow -HordeHome $legacyHome).Count -eq 0) "neither journal has a line: the old journal.jsonl is no mode's"
Check ((Read-HordeWakeLedger -Mode "live" -HordeHome $legacyHome).state -ceq "absent" -and (Read-HordeWakeLedger -Shadow -HordeHome $legacyHome).state -ceq "absent") "and neither has a ledger: the old ledger.json is read by nobody"
Write-HordeWakeHeartbeat -Mode "live" -At (At 1) -ProcessId 1 -Pass 1 -HordeHome $legacyHome
$null = Write-HordeWakeJournal -Mode "live" -Entries @(New-HordeWakeEntry -At (At 1) -Kind "nudge" -Id (Sid 1) -Outcome "woken") -HordeHome $legacyHome
Save-HordeWakeLedger -Mode "live" -Ledger @{} -HordeHome $legacyHome
$legacyNames = (@(Get-ChildItem -LiteralPath (Join-Path $legacyHome "wake") | ForEach-Object { $_.Name } | Sort-Object) -join ",")
Check ($legacyNames -ceq "heartbeat.json,heartbeat-live.json,journal.jsonl,journal-live.jsonl,ledger.json,ledger-live.json" -and ([System.IO.File]::ReadAllText((Join-Path $legacyHome "wake\heartbeat.json")) -like "*900*")) ("a live run writes files named for it, and the old ones are left as they were, not written over and not deleted (" + $legacyNames + ")")
Check ((Write-HordeWakeJournal -Mode "live" -Entries @()) -eq 0 -and -not (Test-Path -LiteralPath $wakeDir)) "journaling nothing writes nothing"
$entries = @(1..12 | ForEach-Object { New-HordeWakeEntry -At (At $_) -Kind "would-nudge" -Id (Sid $_) -Outcome "would-nudge" -Reason "unread mail, idle, empty box" })
$entries += New-HordeWakeEntry -At (At 13) -Kind "would-post" -Id (Sid 2) -Outcome "would-post" -Reason "restore x" -MessageId "0d000000-0000-4000-8000-000000000001"
Check ((Write-HordeWakeJournal -Mode "live" -Entries $entries) -eq 13) "thirteen entries are thirteen journal lines"
$tail = @(Read-HordeWakeJournalTail -Mode "live" -Count 10)
$last = $tail[9] | ConvertFrom-Json
$firstOfTail = $tail[0] | ConvertFrom-Json
Check ($tail.Count -eq 10 -and $firstOfTail.id -ceq (Sid 4) -and $last.kind -ceq "would-post" -and $last.messageId -ceq "0d000000-0000-4000-8000-000000000001" -and $last.at -ceq "2026-10-12T08:00:13.0000000Z") "the tail is the last ten, each a line of JSON with its time in UTC, and a mail's line carries its messageId"
Check ($null -eq $firstOfTail.PSObject.Properties["messageId"]) "a nudge's line carries none"
$null = Write-HordeWakeJournal -Mode "live" -Entries @($entries[0])
Check (@(Read-HordeWakeJournalTail -Mode "live" -Count 100).Count -eq 14) "the journal is appended to, never replaced"

Write-HordeWakeHeartbeat -At (At 5) -ProcessId 4242 -Pass 7 -Shadow
Check ((Read-HordeWakeHeartbeat -Mode "live").state -ceq "absent") "a shadow heartbeat is not the live one: after it, the live watcher has still never run"
$beat = Read-HordeWakeHeartbeat -Shadow
Check ($beat.state -ceq "known" -and $beat.value.at -eq (At 5) -and $beat.value.pid -eq 4242 -and $beat.value.pass -eq 7 -and $beat.value.shadow -eq $true) "a heartbeat reads back as it was written: when, which process, which pass, and that it was shadow"
Write-HordeWakeHeartbeat -Mode "live" -At (At 8) -ProcessId 4242 -Pass 8
$beat = Read-HordeWakeHeartbeat -Mode "live"
Check ($beat.value.pass -eq 8 -and $beat.value.shadow -eq $false -and @(Get-ChildItem -LiteralPath $wakeDir -Filter "*.tmp").Count -eq 0 -and (Read-HordeWakeHeartbeat -Shadow).value.pass -eq 7) "a live one is a file of its own, written whole with no temporary file left, and the shadow one is as it was"
$null = Write-HordeWakeJournal -Entries @($entries[1]) -Shadow
Check (@(Read-HordeWakeJournalTail -Mode "live" -Count 100).Count -eq 14 -and @(Read-HordeWakeJournalTail -Count 100 -Shadow).Count -eq 1) "the journal is per mode too: a shadow line goes to the shadow journal and the live one is as it was"
[System.IO.File]::WriteAllText((Join-Path $wakeDir "heartbeat-live.json"), "{ not json")
Check ((Read-HordeWakeHeartbeat -Mode "live").state -ceq "unknown") "a heartbeat that cannot be read is unknown, not absent"
Check ((Get-HordeWakeStaleSeconds) -eq 120 -and (Get-HordeWakeStaleSeconds -TickSeconds 3) -eq 120 -and (Get-HordeWakeStaleSeconds -TickSeconds 40) -eq 120) "a heartbeat is stale after 120 s, for any tick up to 40 s"
Check ((Get-HordeWakeStaleSeconds -TickSeconds 41) -eq 123 -and (Get-HordeWakeStaleSeconds -TickSeconds 300) -eq 900) "and after three ticks for a slower watcher: stale is relative to how often it beats"
Write-HordeWakeHeartbeat -Mode "live" -At (At 9) -ProcessId 4242 -Pass 9 -TickSeconds 60
Check ((Read-HordeWakeHeartbeat -Mode "live").value.tickSeconds -eq 60) "the heartbeat carries the tick, so a reader knows what stale is for this watcher"
[System.IO.File]::WriteAllText((Join-Path $wakeDir "heartbeat-live.json"), '{"at":"2026-10-12T08:00:05.0000000Z","pid":1,"pass":2,"shadow":true}')
Check ((Read-HordeWakeHeartbeat -Mode "live").value.tickSeconds -eq 0) "a heartbeat written before it carried one reads as no tick, which is the 120 s floor"

# THE JOURNAL IS BOUNDED: at the cap it is set aside, once, and the tail still reads across the two.
$small = Join-Path $pinned.home "rotate"
$line = New-HordeWakeEntry -At (At 1) -Kind "would-nudge" -Id (Sid 1) -Outcome "would-nudge" -Reason ("x" * 100)
foreach ($n in 1..6) { $null = Write-HordeWakeJournal -Mode "live" -Entries @($line) -HordeHome $small -MaxBytes 400 }
$files = @(Get-ChildItem -LiteralPath (Join-Path $small "wake") | ForEach-Object { $_.Name } | Sort-Object)
Check (($files -join ",") -ceq "journal-live.1.jsonl,journal-live.jsonl") ("past its cap the journal is set aside as journal-live.1.jsonl, and there are never more than the two (" + ($files -join ",") + ")")
Check ((Get-Item -LiteralPath (Join-Path $small "wake\journal-live.jsonl")).Length -lt 800) "the journal that is written to stays under twice the cap"
$last = New-HordeWakeEntry -At (At 2) -Kind "would-nudge" -Id (Sid 9) -Outcome "would-nudge" -Reason "the newest"
foreach ($n in 1..3) { $null = Write-HordeWakeJournal -Mode "live" -Entries @($line) -HordeHome $small -MaxBytes 400 }
$null = Write-HordeWakeJournal -Mode "live" -Entries @($last) -HordeHome $small -MaxBytes 400
$tail = @(Read-HordeWakeJournalTail -Mode "live" -Count 4 -HordeHome $small)
Check ($tail.Count -eq 4 -and ($tail[3] | ConvertFrom-Json).reason -ceq "the newest") "the tail is still the newest lines, filled from the journal set aside when the new one is short"

$keep = @{}
$keep[(Sid 1)] = [pscustomobject]@{ attempts = 4; lastAttemptAt = (At 200); lastOutcome = "busy" }
$keep[(Sid 2)] = [pscustomobject]@{ attempts = 1; lastAttemptAt = (At 3); lastOutcome = "would-nudge" }
Save-HordeWakeLedger -Mode "live" -Ledger $keep
$back = Read-HordeWakeLedger -Mode "live"
Check ($back.state -ceq "known" -and $back.value.ledger.Count -eq 2 -and $back.value.ledger[(Sid 1)].attempts -eq 4 -and $back.value.ledger[(Sid 1)].lastAttemptAt -eq (At 200) -and $back.value.ledger[(Sid 1)].lastOutcome -ceq "busy") "a saved ledger reads back: each session's attempts, time and outcome"
Start-Case; Seat -Change @{ Outcome = "busy"; OutcomeReason = "busy" }
$script:ledger = $back.value.ledger
$r = Pass 300
Check ((Decided $r).action -ceq "wait" -and "$((Decided $r).reason)".Contains("back-off")) "so a watcher that was restarted keeps the back-off it had"
Save-HordeWakeLedger -Mode "live" -Ledger @{}
$back = Read-HordeWakeLedger -Mode "live"
Check ($back.state -ceq "known" -and $back.value.ledger.Count -eq 0) "an empty ledger saves and reads back empty"
Save-HordeWakeLedger -Ledger $keep -Shadow
Check ((Test-Path -LiteralPath (Join-Path $wakeDir "ledger-shadow.json") -PathType Leaf) -and (Read-HordeWakeLedger -Mode "live").value.ledger.Count -eq 0 -and (Read-HordeWakeLedger -Shadow).value.ledger.Count -eq 2) "a shadow run's ledger is a file of its own: saving it leaves the live ledger as it was, and each reads back its own"
[System.IO.File]::WriteAllText((Join-Path $wakeDir "ledger-live.json"), '{"schemaVersion":1,"sessions":[{"id":"x"}]}')
Check ((Read-HordeWakeLedger -Mode "live").state -ceq "unknown") "a saved ledger with a broken entry is unknown, never half a ledger"

} finally {
    Reset-HordeMemoryWaker
    Exit-HordeTestPinnedHome -State $pinned
    Exit-HordeTestEmptyFleet -Pin $fleetPin
}

Complete-HordeSuite -Success "the watcher nudges only what it could read and should wake, backs off, heals, queues a restore fairly, and in shadow does nothing"
