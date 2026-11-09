# DOES THE WATCHER COUNT THE LOOKS THE TERMINAL DID NOT ANSWER, SAY THEM ONCE, AND STOP LOOKING EVERY PASS? (T-0116)
#
# A look at a session's box and turn (the waker's Confirm) starts the terminal's command a handful of times.
# When the terminal does not answer, the fleet's command still exits 0, with the box and the turn unknown and
# a reason word (pane-unverified, terminal-timeout, box-unreadable). Before this suite's change the watcher
# read that as a known state it could not use: nothing journaled, nothing counted, and the same session looked
# at again on the very next pass - thousands of terminal starts an hour for a session that stays blind, each
# start writing Code Integrity events in a log that holds under two hours. Held here, with the REAL wezfleet
# waker against the waker's FAKE of the fleet's command (no real fleet or terminal is ever reached), a tick of
# the wake run (shadow) and a clock this suite moves by hand:
#   - A LOOK THE FAKE ANSWERS BLIND is looked at again only when its back-off has passed (5, 15, 45, 135, 300 s),
#     not every pass; the fake's own record says how many looks were really made.
#   - IT IS JOURNALED ONCE A SPELL: pane-blind (outcome unseen, the session id and the reason word) when the
#     spell starts or its reason changes, and pane-seen, with how many looks it lasted, when a look reads.
#   - IT IS COUNTED: the heartbeat carries passes, looks, blindLooks, blindPasses and when they began; the same
#     numbers are in a counts file beside it, and a run that starts again goes on from them.
#   - `horde wake status` says "looks N, blind N (P passes)".
#   - A BLIND LOOK IS NOT A VERDICT: no session is dead, gone, retired, asleep or held for it, no episode of a
#     duplicated session ends, no attempt is counted, and the restore source says what it says without it.
# Every check that reads a member the old code does not have reads it through Get-HordeTestMember, so on the
# old code the suite FAILS the checks that name the rule and does not break.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "test\lib\FleetPin.ps1")
. (Join-Path $root "test\lib\MessengerPins.ps1")
. (Join-Path $root "test\lib\Cli.ps1")
# PINNED FIRST: an empty fleet and a home of this suite's, so nothing below can read or write the real ones.
$fleetPin = Enter-HordeTestEmptyFleet
$pinned = Enter-HordeTestPinnedHome -Root $root
. (Join-Path $root "core\WakeRun.ps1")
foreach ($f in @(Get-HordeWakerFiles)) { . $f }

$w = Get-HordeWaker -Name "wezfleet"
$fx = & (Join-Path $w.folder "test\Fixture.ps1") -Root $root
$t0 = New-Object System.DateTime(2026, 10, 12, 8, 0, 0, [System.DateTimeKind]::Utc)
function At { param([double]$Seconds) return $t0.AddSeconds($Seconds) }
function Sid { param([int]$N) return ("0a000000-0000-4000-8000-" + $N.ToString("000000000000")) }
function New-Row {
    # A row as the fleet prints one: an idle orc with one unread mail an hour old, an empty box and no turn
    # under way, with -Change laid over it.
    param([int]$N = 1, [hashtable]$Change = @{})
    $r = [ordered]@{ id = (Sid $N); label = ("S" + $N); role = "orchestrator"; parent = ""; retired = $false; reachable = "yes"; mail = "known"; unreadCount = 1; unreadableCount = 0
        oldestUnreadAt = "2026-10-12T07:00:00.0000000Z"; idle = "yes"; boxEmpty = "yes"; midTurn = "no"; reason = ""; reasons = @(); limited = "no"; limitedUntil = $null
        handedOverCount = 0; oldestHandedOverAt = $null; acked = "known"; lastAckedAt = $null; betweenTurns = "no" }
    foreach ($k in $Change.Keys) { $r[$k] = $Change[$k] }
    return $r
}
function New-Blind {
    # The same row as the fleet prints it when the terminal did not answer: the box and the turn unknown, and why.
    param([int]$N = 1, [string]$Reason = "terminal-timeout", [hashtable]$Change = @{})
    $c = @{ boxEmpty = "unknown"; midTurn = "unknown"; reason = $Reason; reasons = @($Reason) }
    foreach ($k in $Change.Keys) { $c[$k] = $Change[$k] }
    return (New-Row $N $c)
}
function Get-Panes { param($State) return @(& $fx.Runs $State | ForEach-Object { @($_.argv) -join " " } | Where-Object { $_ -clike "mail state -To *" }).Count }
function Get-PanesOf { param($State, [int]$N) return @(& $fx.Runs $State | ForEach-Object { @($_.argv) -join " " } | Where-Object { $_ -clike ("mail state -To " + (Sid $N) + " *") }).Count }
$readNone = { $a = New-HordeKnown -Value @(); Add-Member -InputObject $a -MemberType NoteProperty -Name "leftOut" -Value @(); $a }
$readAsleep = { New-HordeKnown -Value @{} }
function Step {
    # One tick of the wake run at -Seconds on the hand-moved clock; returns the entries it journaled.
    param($State, $Run, [double]$Seconds, $ReadSessions = $script:readNone)
    return @(Invoke-HordeWakeTick -Run $Run -Now (At $Seconds) -Waker $w -ReadSessions $ReadSessions -ReadAsleep $script:readAsleep -TickSeconds 3 -ProcessId 4242 -HordeHome $State.home)
}
function Read-Lines { param([string]$HordeHome) return @(Read-HordeWakeJournalTail -Count 2000 -Shadow -HordeHome $HordeHome | ForEach-Object { $_ | ConvertFrom-Json }) }
function Get-Counts { param([string]$HordeHome) $b = Read-HordeWakeHeartbeat -Shadow -HordeHome $HordeHome; if ($b.state -cne "known") { return $null }; return (Get-HordeTestMember $b.value "counts") }
function Num { param($Counts, [string]$Name) if ($null -eq $Counts) { return -1 }; $v = Get-HordeTestMember $Counts $Name; if ($null -eq $v) { return -1 }; return [long]$v }

$have = ($null -ne (Get-Command Update-HordeWakeBlind -ErrorAction SilentlyContinue))
$state = $null
try {

Write-Host ""
Write-Host "--- a session that stays blind is looked at on a back-off, journaled once a spell, and counted ---" -ForegroundColor Cyan

$state = & $fx.New
& $fx.SetRow $state (New-Blind 1 "terminal-timeout")
$run = New-HordeWakeRun -HordeHome $state.home
$lines = New-Object System.Collections.ArrayList
$seenAfter = @{}
# Ticks at 0, 3, 6, 9, 20, 21, 30, 65, 66, 70: the looks the back-off allows are at 0 (then 5 s), 6 (then 15 s),
# 21 (then 45 s) and 66 (then 135 s) - four, in ten passes. Without a back-off every pass looks.
foreach ($sec in @(0, 3, 6, 9, 20, 21, 30, 65, 66, 70)) {
    if ($sec -eq 21) { & $fx.SetRow $state (New-Blind 1 "box-unreadable") }
    foreach ($e in @(Step $state $run $sec)) { [void]$lines.Add($e) }
    $seenAfter["" + $sec] = Get-Panes $state
}
Check ($seenAfter["0"] -eq 1 -and $seenAfter["3"] -eq 1 -and $seenAfter["6"] -eq 2 -and $seenAfter["20"] -eq 2) ("the first look is made at once; the next waits 5 s (none at 3 s, one at 6 s), the one after 15 s (none by 20 s); looks made so far at each pass: " + (($seenAfter.Keys | Sort-Object { [int]$_ } | ForEach-Object { $_ + "s=" + $seenAfter[$_] }) -join " "))
Check ($seenAfter["21"] -eq 3 -and $seenAfter["65"] -eq 3 -and $seenAfter["66"] -eq 4 -and $seenAfter["70"] -eq 4) "then 45 s (none at 65 s), then 135 s: four looks in ten passes, where the old code made ten"
$journal = @(Read-Lines $state.home)
$blinds = @($journal | Where-Object { $_.kind -ceq "pane-blind" })
Check ($blinds.Count -eq 2 -and $blinds[0].id -ceq (Sid 1) -and $blinds[0].outcome -ceq "unseen" -and $blinds[0].reason -ceq "terminal-timeout") "the journal says the spell once when it starts: pane-blind, unseen, the session and the reason word"
Check ($blinds.Count -eq 2 -and $blinds[1].reason -ceq "box-unreadable" -and (ConvertFrom-HordeWakeTimeText $blinds[1].at) -eq (At 21)) "and again when its reason changes (at 21 s), not for the looks in between"
Check (@($journal | Where-Object { $_.kind -ceq "pane-seen" }).Count -eq 0) "CONTROL: no pane-seen while the spell lasts"
Check (@($journal | Where-Object { @("pane-blind", "pane-seen", "would-nudge") -cnotcontains $_.kind }).Count -eq 0) ("and the blind spell is the only thing journaled: no skip-unknown, held, never-nudged or gave-up (" + (@($journal | ForEach-Object { $_.kind } | Sort-Object -Unique) -join ",") + ")")
Check ($run.ledger.Count -eq 0) "no attempt is counted for a session nobody could see: the ledger is empty"
$c = Get-Counts $state.home
Check ((Num $c "passes") -eq 10 -and (Num $c "looks") -eq 4 -and (Num $c "blindLooks") -eq 4 -and (Num $c "blindPasses") -eq 4) ("the heartbeat counts 10 passes, 4 looks, 4 blind looks in 4 passes (" + $(if ($null -eq $c) { "no counts" } else { ($c | ConvertTo-Json -Compress) }) + ")")
Check ($null -ne $c -and $null -ne (ConvertFrom-HordeWakeTimeText (Get-HordeTestMember $c "since")) -and $null -ne (ConvertFrom-HordeWakeTimeText (Get-HordeTestMember $c "startedAt"))) "and the time the counting began and the time this run started"
$countsFile = Join-Path (Join-Path $state.home "wake") "counts-shadow.json"
Check (Test-Path -LiteralPath $countsFile -PathType Leaf) "the counts are also in counts-shadow.json beside the heartbeat, the shadow run's own"
Check (-not (Test-Path -LiteralPath (Join-Path (Join-Path $state.home "wake") "counts-live.json"))) "and no live counts file was made for a shadow run"

Write-Host ""
Write-Host "--- `wake status` says it ---" -ForegroundColor Cyan
$st = Invoke-HordeCliProcess -Root $root -HordeArgs @("wake", "status") -Env @{ HORDE_HOME = $state.home; WEZFLEET_ROOT = $fleetPin.path }
Check ($st.code -eq 0 -and $st.out.Contains("SHADOW: looks 4, blind 4 (4 passes)")) ("wake status shows 'looks 4, blind 4 (4 passes)' for the shadow run (exit " + $st.code + ")")
Check ($st.out.Contains("LIVE: it has never run")) "CONTROL: the live run, which never ran, has no counts to show"

Write-Host ""
Write-Host "--- a run that starts again goes on from the counts, and a look that reads ends the spell ---" -ForegroundColor Cyan
$run2 = New-HordeWakeRun -HordeHome $state.home
$was = Get-Counts $state.home
Check ((Num (Get-HordeTestMember $run2 "counts") "passes") -eq 10 -and (Num (Get-HordeTestMember $run2 "counts") "blindLooks") -eq 4) "a new run reads the counts back from the file at its start"
Check ((Get-HordeTestMember (Get-HordeTestMember $run2 "counts") "since") -eq (ConvertFrom-HordeWakeTimeText (Get-HordeTestMember $was "since"))) "and keeps the time the counting began"
$late = New-Object System.Collections.ArrayList
foreach ($e in @(Step $state $run2 100)) { [void]$late.Add($e) }
& $fx.SetRow $state (New-Row 1)
foreach ($e in @(Step $state $run2 201)) { [void]$late.Add($e) }
$c = Get-Counts $state.home
Check ((Num $c "passes") -eq 12 -and (Num $c "looks") -eq 6 -and (Num $c "blindLooks") -eq 5 -and (Num $c "blindPasses") -eq 5) ("after the restart two more passes, one blind look and one that read: 12 passes, 6 looks, 5 blind, 5 blind passes (" + $(if ($null -eq $c) { "no counts" } else { ($c | ConvertTo-Json -Compress) }) + ")")
Check ((Get-Panes $state) -eq 6) "the restarted run, which forgot the old run's back-off, looked at once (100 s) and again when its own back-off had passed (201 s)"
$seen = @(Read-Lines $state.home | Where-Object { $_.kind -ceq "pane-seen" })
Check ($seen.Count -eq 1 -and $seen[0].id -ceq (Sid 1) -and $seen[0].outcome -ceq "seen") "a look that reads ends the spell with one pane-seen line"
Check ($seen.Count -eq 1 -and "$($seen[0].reason)".Contains("after 1 blind look")) "saying how many looks it lasted (the restarted run's own spell: 1)"
Check (@(Read-Lines $state.home | Where-Object { $_.kind -ceq "would-nudge" }).Count -eq 1) "and the session, now seen, is decided on as any other (shadow: one would-nudge)"
& $fx.Remove $state
$state = $null

Write-Host ""
Write-Host "--- a blind look is not a verdict: nobody is dead, gone, retired or held, and no episode ends ---" -ForegroundColor Cyan
$state = & $fx.New
& $fx.SetRow $state (New-Blind 1 "pane-unverified")
$pass = Invoke-HordeWakePass -Waker $w -Now (At 0) -Ledger @{}
$decision = @($pass.decisions | Where-Object { $_.id -ceq (Sid 1) })
Check ($decision.Count -eq 1 -and $decision[0].action -ceq "wait") "the pass waits on a session it could not see, as it always did"
$bl = Get-HordeTestMember $pass "blindLooks"
Check ($null -ne $bl -and $bl.Count -eq 1 -and $bl[(Sid 1)] -ceq "pane-unverified") "and says it was a blind look, with the fleet's reason word"
Check ((Num $pass "looks") -eq 1) "and counts the look"
Check ($pass.never.Count -eq 0 -and $pass.held.Count -eq 0) "it is not read as retired, gone or hibernated: nobody is never-nudged or held for it"
Check ($pass.duplicate.Count -eq 0 -and $pass.duplicateOn.Count -eq 0 -and $pass.gaveUp.Count -eq 0 -and $pass.ledger.Count -eq 0) "and no duplicate, no give-up and no attempt come of it"
Check ($pass.mail.ContainsKey((Sid 1)) -and $pass.listing.state -ceq "known" -and @($pass.listing.value).Count -eq 1) "the session is still listed and its mail is still read"
Check (@($pass.entries | Where-Object { $_.kind -ceq "skip-unknown" }).Count -eq 0) "and it is not a skip-unknown: the look was not a failure of the read"
& $fx.Remove $state
$state = $null

# A duplicated session (two running copies) has an episode; a blind look at ANOTHER session must not touch it.
$state = & $fx.New
& $fx.SetRow $state (New-Row 2 @{ reasons = @("duplicate-process"); reason = "duplicate-process"; idle = "unknown"; boxEmpty = "unknown"; midTurn = "unknown" })
& $fx.SetRow $state (New-Blind 1 "terminal-timeout")
$run = New-HordeWakeRun -HordeHome $state.home
$all = New-Object System.Collections.ArrayList
foreach ($sec in @(0, 3, 6, 9, 21)) { foreach ($e in @(Step $state $run $sec)) { [void]$all.Add($e) } }
$held = @($all | Where-Object { $_.kind -ceq "held" -and $_.id -ceq (Sid 2) })
Check ($held.Count -eq 1 -and "$($held[0].reason)".Contains("more than one copy")) "CONTROL: the duplicated session's episode is said once"
Check ($run.duplicate.ContainsKey((Sid 2)) -and $run.duplicate.Count -eq 1) "and it lasts through the other session's blind passes: the episode is still open, one"
Check (@($all | Where-Object { $_.kind -ceq "pane-blind" -and $_.id -ceq (Sid 1) }).Count -eq 1 -and @($all | Where-Object { $_.id -ceq (Sid 1) -and $_.kind -cne "pane-blind" }).Count -eq 0) "the blind session has its one pane-blind line and nothing else said of it"
Check ((Get-PanesOf $state 2) -eq 0) "and the duplicated session is not looked at at all"
& $fx.Remove $state
$state = $null

# The restore source says the same with a blind session as with one whose box simply holds text.
function Get-Restored {
    param($State, $Row)
    & $fx.SetRow $State $Row
    $restored = @(1..6 | ForEach-Object { [pscustomobject]@{ id = (Sid $_); role = "orc"; parent = ""; startedAt = (At ($_ * 10 - 400)); lastChangeAt = (At ($_ * 10 - 398)); status = "idle"; firstSeenAt = (At -90000) } })
    $read = { $a = New-HordeKnown -Value $restored; Add-Member -InputObject $a -MemberType NoteProperty -Name "leftOut" -Value @(); $a }.GetNewClosure()
    $r = New-HordeWakeRun -HordeHome $State.home
    $kinds = New-Object System.Collections.ArrayList
    foreach ($sec in @(0, 3, 6, 9, 21, 35)) { foreach ($e in @(Step $State $r $sec $read)) { if (@("pane-blind", "pane-seen") -cnotcontains $e.kind) { [void]$kinds.Add($e.kind + ":" + $e.id + ":" + $e.outcome) } } }
    return @($kinds | Sort-Object)
}
$state = & $fx.New
$withBlind = @(Get-Restored $state (New-Blind 1 "terminal-timeout"))
& $fx.Remove $state
$state = & $fx.New
$withText = @(Get-Restored $state (New-Row 1 @{ boxEmpty = "no" }))
& $fx.Remove $state
$state = $null
Check ($withText.Count -gt 0 -and @($withText | Where-Object { $_ -clike "would-post:*" }).Count -gt 0) "CONTROL: the restore source plans mail for the restored orcs in the control run"
Check (($withBlind -join "|") -ceq ($withText -join "|")) "a blind session queues no restore and cancels none: the journal, but for the blind lines, is the control run's"

Write-Host ""
Write-Host "--- the spells, on their own: the back-off schedule, once a spell, and the reset ---" -ForegroundColor Cyan
Check $have "the spell bookkeeping exists (Update-HordeWakeBlind)"
if ($have) {
    $settings = Get-HordeWakeSettings
    $seen = @{}
    $waits = New-Object System.Collections.ArrayList
    $at = 0
    foreach ($i in 1..7) {
        $r = Update-HordeWakeBlind -Seen $seen -BlindLooks @{ (Sid 1) = "terminal-timeout" } -Now (At $at) -Settings $settings
        $seen = $r.seen
        [void]$waits.Add([int]($seen[(Sid 1)].nextAt - (At $at)).TotalSeconds)
        $at = $at + $waits[$waits.Count - 1]
    }
    Check (($waits -join ",") -ceq "5,15,45,135,300,300,300") ("the wait after each blind look in a row is 5, 15, 45, 135, 300 s, and 300 s for ever (" + ($waits -join ",") + ")")
    Check ($seen[(Sid 1)].looks -eq 7) "and the spell counts its looks"
    $wait = Get-HordeWakeBlindWait -Seen $seen -Now (At ($at - 100))
    Check ($wait.ContainsKey((Sid 1)) -and $wait[(Sid 1)].seconds -eq 100 -and $wait[(Sid 1)].reason -ceq "terminal-timeout") "Get-HordeWakeBlindWait says how long is left, rounded up, and why"
    Check ((Get-HordeWakeBlindWait -Seen $seen -Now (At $at)).Count -eq 0 -and (Get-HordeWakeBlindWait -Seen $null -Now (At $at)).Count -eq 0) "and nothing once the back-off has passed, or for no table"
    $r = Update-HordeWakeBlind -Seen $seen -BlindLooks @{} -SeenLooks @((Sid 1)) -Now (At ($at + 1)) -Settings $settings
    Check ($r.seen.Count -eq 0 -and @($r.entries).Count -eq 1 -and $r.entries[0].kind -ceq "pane-seen" -and $r.entries[0].reason.Contains("after 7 blind look")) "a look that reads clears the spell, with one pane-seen saying 7 looks"
    $r2 = Update-HordeWakeBlind -Seen $r.seen -BlindLooks @{} -SeenLooks @((Sid 1)) -Now (At ($at + 2)) -Settings $settings
    Check (@($r2.entries).Count -eq 0) "and a second look that reads says nothing more"
    $r3 = Update-HordeWakeBlind -Seen $r.seen -BlindLooks @{ (Sid 1) = "terminal-timeout" } -Now (At ($at + 3)) -Settings $settings
    Check ($r3.seen[(Sid 1)].looks -eq 1 -and ($r3.seen[(Sid 1)].nextAt - (At ($at + 3))).TotalSeconds -eq 5 -and @($r3.entries).Count -eq 1) "and the next blind look after it starts a new spell: back to 5 s, and a new pane-blind line"
    $r4 = Update-HordeWakeBlind -Seen $seen -BlindLooks @{ (Sid 1) = "terminal-timeout" } -Now (At ($at + 5)) -Settings $settings
    Check (@($r4.entries).Count -eq 0) "the same reason again in a long spell says nothing"
    $r5 = Update-HordeWakeBlind -Seen $seen -BlindLooks @{} -SeenLooks @() -Listed @((Sid 2)) -Now (At ($at + 5)) -Settings $settings
    Check ($r5.seen.Count -eq 0 -and @($r5.entries).Count -eq 0) "a session no longer in the listing is forgotten, with no line: nobody looked"
    $r6 = Update-HordeWakeBlind -Seen $seen -BlindLooks @{} -SeenLooks @() -Listed $null -Now (At ($at + 5)) -Settings $settings
    Check ($r6.seen.Count -eq 1) "and a listing that could not be read forgets nobody"
    $r7 = Update-HordeWakeBlind -Seen @{} -BlindLooks @{} -SeenLooks @((Sid 3)) -Now (At 1) -Settings $settings
    Check (@($r7.entries).Count -eq 0) "a look that reads a session that was never blind says nothing"
}

} finally {
    if ($null -ne $state) { & $fx.Remove $state }
    Exit-HordeTestPinnedHome -State $pinned
    Exit-HordeTestEmptyFleet -Pin $fleetPin
}

Complete-HordeSuite -Success "a look the terminal did not answer is journaled once a spell, counted for the run, looked at again only after its back-off, and never read as a verdict on the session"
