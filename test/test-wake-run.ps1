# DOES A TICK OF THE WAKE RUN NUDGE NOBODY, POST NOTHING, AND SURVIVE WHATEVER ONE OF ITS PARTS THROWS?
#
# core/WakeRun.ps1 - the tick `horde wake run -Shadow` makes over and over - and the lock that keeps a
# second run out (core/WakeFiles.ps1). Driven here with the in-process waker, sessions this suite
# hands in and a clock it moves by hand, under a home it made and removes:
#   - A SHADOW TICK IS SHADOW BY CONSTRUCTION. With sessions that qualify for a nudge and a restore
#     that plans mail, twenty ticks ring nobody, and the live state files are never written.
#   - A TICK NEVER THROWS. A reader that throws, a wake pass that cannot save its ledger and a heartbeat
#     that cannot be written are each journaled once for as long as they last, and the next tick runs.
#   - THE RESTORE SOURCE RUNS BESIDE THE WAKE PASS, every 30 s and not every tick.
#   - ONE RUN A HOME AND A MODE: a second lock is refused while the first is held, and a lock nobody
#     holds - its process gone - blocks nobody.

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
. (Join-Path $root "core\WakeRun.ps1")
. (Join-Path $root "wakers\memory\Waker.ps1")
# The in-process test messenger: what the two senders post through in the one section that turns them on.
. (Join-Path $root "messengers\memory\Messenger.ps1")

$memory = Get-HordeWaker -Name "memory"
$t0 = New-Object System.DateTime(2026, 10, 12, 8, 0, 0, [System.DateTimeKind]::Utc)
function At { param([double]$Seconds) return $t0.AddSeconds($Seconds) }
function Sid { param([int]$N) return ("0a000000-0000-4000-8000-" + $N.ToString("000000000000")) }
function New-Home { $h = Join-Path $pinned.home ("run-" + [guid]::NewGuid().ToString("N")); New-Item -ItemType Directory -Path $h | Out-Null; return $h }
function Read-Lines { param([string]$HordeHome) return @(Read-HordeWakeJournalTail -Count 1000 -Shadow -HordeHome $HordeHome | ForEach-Object { $_ | ConvertFrom-Json }) }
# Six orcs restored together an hour ago in their earlier lives, none moved: a restore that plans mail.
$restored = @(1..6 | ForEach-Object { [pscustomobject]@{ id = (Sid $_); role = "orc"; parent = ""; startedAt = (At ($_ * 10 - 400)); lastChangeAt = (At ($_ * 10 - 398)); status = "idle"; firstSeenAt = (At -90000) } })
$script:reads = 0
$readRestored = { $script:reads++; $a = New-HordeKnown -Value $restored; Add-Member -InputObject $a -MemberType NoteProperty -Name "leftOut" -Value @(); $a }

try {

Write-Host ""
Write-Host "--- a shadow tick rings nobody and posts nothing, and keeps its state apart ---" -ForegroundColor Cyan

$h = New-Home
Reset-HordeMemoryWaker
foreach ($n in 1..6) { Set-HordeMemoryWakerSession -Id (Sid $n) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60) }
$run = New-HordeWakeRun -HordeHome $h
Check ($run.pass -eq 0 -and $run.ledger.Count -eq 0 -and @($run.said).Count -eq 0) "CONTROL: a run in a new home starts from nothing, with nothing to say"
$kinds = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt 20; $i++) {
    Set-HordeMemoryWakerClock (At ($i * 3))
    foreach ($e in @(Invoke-HordeWakeTick -Run $run -Now (At ($i * 3)) -Waker $memory -ReadSessions $readRestored -TickSeconds 3 -ProcessId 4242 -HordeHome $h)) { [void]$kinds.Add($e.kind) }
}
Check (@(Get-HordeMemoryWakerAsks).Count -eq 0) "twenty ticks over six sessions that qualify ask the waker for no nudge at all"
Check (@($kinds | Where-Object { $_ -cnotlike "would-*" }).Count -eq 0 -and @($kinds | Where-Object { $_ -ceq "would-nudge" }).Count -ge 6 -and @($kinds | Where-Object { $_ -ceq "would-post" }).Count -eq 6 -and @($kinds | Where-Object { $_ -ceq "would-stall" }).Count -eq 1) ("every entry says would: a would-nudge for each session, one would-post for each restored orc, one would-stall (" + (@($kinds | Group-Object | ForEach-Object { $_.Name + " x" + $_.Count }) -join ", ") + ")")
$names = @(Get-ChildItem -LiteralPath (Join-Path $h "wake") | ForEach-Object { $_.Name } | Sort-Object)
Check (($names -join ",") -ceq "heartbeat-shadow.json,journal-shadow.jsonl,ledger-shadow.json,restore-shadow.json") ("it wrote the shadow run's own journal, heartbeat, ledger and restore state, and no file of a live run (" + ($names -join ",") + ")")
Check (@(Read-Lines $h).Count -eq $kinds.Count) "what a tick returns is what it journaled"
$beat = Read-HordeWakeHeartbeat -Shadow -HordeHome $h
Check ($beat.state -ceq "known" -and $beat.value.pass -eq 20 -and $beat.value.shadow -eq $true -and $beat.value.tickSeconds -eq 3 -and $beat.value.pid -eq 4242 -and $beat.value.at -eq (At 57)) "the heartbeat is the last tick's: its pass, its time, shadow, the tick and the process"
Check ($script:reads -eq 2) ("the restore source ran beside the wake pass every 30 s, not every tick: twice in 57 s (" + $script:reads + ")")
$again = New-HordeWakeRun -HordeHome $h
Check ($again.ledger.Count -eq 6 -and $again.posted.Count -eq 7 -and @($again.restores).Count -eq 1) "a run that starts again reads back the shadow run's ledger, what it would have posted, and the restore it found"

# MAIL NOBODY CAN READ: the tick journals bad-mail once, on the second tick that shows it.
$h = New-Home
Reset-HordeMemoryWaker
Set-HordeMemoryWakerSession -Id (Sid 1) -Role "orc" -UnreadCount 0 -UnreadableCount 3
$run = New-HordeWakeRun -HordeHome $h
$none = { $a = New-HordeKnown -Value @(); Add-Member -InputObject $a -MemberType NoteProperty -Name "leftOut" -Value @(); $a }
$said = @(); foreach ($s in @(0, 3, 6, 9)) { $said += , @(Invoke-HordeWakeTick -Run $run -Now (At $s) -Waker $memory -ReadSessions $none -HordeHome $h | ForEach-Object { $_.kind }) }
Check (@($said[0]).Count -eq 0 -and (@($said[1]) -join ",") -ceq "bad-mail,would-tell" -and @($said[2]).Count -eq 0 -and @($said[3]).Count -eq 0) "a session whose mailbox holds records nobody can read is journaled bad-mail once, on the second tick that shows it, with the tell the warchief would get, and not again"
$line = @(Read-Lines $h | Where-Object { $_.kind -ceq "would-tell" })
Check ($line.Count -eq 1 -and $line[0].id -ceq (Sid 1) -and "$($line[0].reason)".StartsWith("bad-mail: the mailbox of the session " + (Sid 1)) -and (Test-Path -LiteralPath (Join-Path $h "wake\tells-shadow.json"))) "the would-tell line names the session and the condition, and what was told is kept in the shadow run's own file"
$again = New-HordeWakeRun -HordeHome $h
Check ($again.told.Count -eq 1 -and @($again.told.Values)[0].state -ceq "would-tell") "a run that starts again reads back what it would have told, so it is not said twice"

# A FLEET THAT CANNOT BE READ: the tick says it once as unknown, once as permanent, and once as recovered.
$h = New-Home
Reset-HordeMemoryWaker
Set-HordeMemoryWakerFault -Call "targets" -Kind "throw"
$run = New-HordeWakeRun -HordeHome $h
$seenKinds = New-Object System.Collections.ArrayList
foreach ($n in 0..29) { foreach ($e in @(Invoke-HordeWakeTick -Run $run -Now (At ($n * 3)) -Waker $memory -ReadSessions $none -HordeHome $h)) { [void]$seenKinds.Add($e.kind + "@" + $n) } }
Check ((@($seenKinds) -join ",") -ceq "skip-unknown@0,fleet-read-failing@9,would-tell@9") ("thirty ticks over a fleet that cannot be read journal three lines: unknown on the first, permanent and the tell of it on the tenth, and nothing after (" + (@($seenKinds) -join ",") + ")")
Set-HordeMemoryWakerFault -Call "targets" -Kind ""
$back = @(Invoke-HordeWakeTick -Run $run -Now (At 100) -Waker $memory -ReadSessions $none -HordeHome $h | ForEach-Object { $_.kind })
Check (($back -join ",") -ceq "recovered") "the tick on which it can be read again says recovered"

# A SESSION GIVEN UP ON, AND A NUDGE THAT HAD TO BE KILLED: each is a tell, once.
$h = New-Home
Reset-HordeMemoryWaker
Set-HordeMemoryWakerSession -Id (Sid 1) -Role "warchief" -UnreadCount 0
Set-HordeMemoryWakerSession -Id (Sid 2) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60) -Outcome "killed" -OutcomeReason "nudge-killed: stopped part-way"
$run = New-HordeWakeRun -Live -HordeHome $h
Set-HordeMemoryWakerClock (At 0)
$first = @(Invoke-HordeWakeTick -Run $run -Now (At 0) -Waker $memory -ReadSessions $none -HordeHome $h | ForEach-Object { $_.kind + ":" + $_.id })
Check (($first -join ",") -ceq ("nudge-killed:" + (Sid 2) + ",would-tell:" + (Sid 2)) -and $run.warchief -ceq (Sid 1)) ("a nudge that had to be killed is journaled, and the warchief would be told of it - would, because the senders are shadow even in a live run (" + ($first -join ",") + ")")
Check ((@(Get-ChildItem -LiteralPath (Join-Path $h "wake") | ForEach-Object { $_.Name } | Sort-Object) -join ",") -ceq "heartbeat-live.json,journal-live.jsonl,ledger-live.json,tells-of-live-run-shadow.json") "and what the live run would have told is kept in a shadow file of its own - never tells-live.json, which is for what was really told, and never the shadow run's"
$h = New-Home
Reset-HordeMemoryWaker
Set-HordeMemoryWakerSession -Id (Sid 2) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60) -Outcome "busy" -OutcomeReason "mid-turn"
$run = New-HordeWakeRun -Live -HordeHome $h
$gave = New-Object System.Collections.ArrayList
foreach ($n in 0..7) { Set-HordeMemoryWakerClock (At ($n * 400)); foreach ($e in @(Invoke-HordeWakeTick -Run $run -Now (At ($n * 400)) -Waker $memory -ReadSessions $none -Settings (Get-HordeWakeSettings -Overrides @{ maxNudgesPerMail = 2 }) -HordeHome $h)) { [void]$gave.Add($e.kind) } }
Check (@($gave | Where-Object { $_ -ceq "gave-up" }).Count -eq 1 -and @($gave | Where-Object { $_ -ceq "would-tell" }).Count -eq 1) ("a session given up on is one gave-up line and one tell, over eight ticks (" + (@($gave) -join ",") + ")")

# A USAGE LIMIT: said once, no nudge until it ends.
$h = New-Home
Reset-HordeMemoryWaker
Set-HordeMemoryWakerSession -Id (Sid 1) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60) -Limited $true -LimitedUntil (At 300)
$run = New-HordeWakeRun -Live -HordeHome $h
$lim = New-Object System.Collections.ArrayList
foreach ($n in 0..99) { Set-HordeMemoryWakerClock (At ($n * 3)); foreach ($e in @(Invoke-HordeWakeTick -Run $run -Now (At ($n * 3)) -Waker $memory -ReadSessions $none -HordeHome $h)) { [void]$lim.Add($e.kind + "@" + ($n * 3)) } }
Check ((@($lim) -join ",") -ceq "usage-limit@0" -and @(Get-HordeMemoryWakerNudges).Count -eq 0) ("for the five minutes of a session's usage limit the tick journals it once and rings nobody (" + (@($lim) -join ",") + ")")
Set-HordeMemoryWakerClock (At 300)
$freed = @(Invoke-HordeWakeTick -Run $run -Now (At 300) -Waker $memory -ReadSessions $none -HordeHome $h | ForEach-Object { $_.kind })
Check (($freed -join ",") -ceq "nudge" -and $run.limited.Count -eq 0) "at the time it ends the session is nudged"
# A SILENT FLEET, as the tick sees it: three sessions that answer woken and never take their mail.
$h = New-Home
Reset-HordeMemoryWaker
foreach ($n in 1..3) { Set-HordeMemoryWakerSession -Id (Sid $n) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60) }
# (This timeline is written for a window of ten minutes, set here; the default, and that it finds the
# silence before anybody is given up on, is test/test-wake.ps1's.)
$tenMinutes = Get-HordeWakeSettings -Overrides @{ fleetSilentMinutes = 10 }
$run = New-HordeWakeRun -Live -HordeHome $h
$quiet = New-Object System.Collections.ArrayList
foreach ($n in 0..300) { Set-HordeMemoryWakerClock (At ($n * 3)); foreach ($e in @(Invoke-HordeWakeTick -Run $run -Now (At ($n * 3)) -Waker $memory -ReadSessions $none -Settings $tenMinutes -HordeHome $h)) { [void]$quiet.Add([pscustomobject]@{ kind = $e.kind; at = ($n * 3); reason = "$($e.reason)" }) } }
$found = @($quiet | Where-Object { $_.kind -ceq "fleet-silent" })
Check ($found.Count -eq 1 -and $found[0].at -eq 600) ("fifteen minutes of ticks over it find the fleet silent once, at ten minutes (" + (@($found | ForEach-Object { $_.at }) -join ",") + ")")
Check (@($quiet | Where-Object { $_.kind -ceq "would-tell" -and $_.reason.StartsWith("fleet-silent: ") }).Count -eq 1) "and the warchief would be told of it, once"
Check (@($run.ledger.Values | Where-Object { $_.attempts -ne 0 -or (Get-HordeWakeEntryValue $_ "gaveUp") -eq $true }).Count -eq 0 -and $run.silence.silent -eq $true) "from then no attempt is held against any session - the ones already counted, and already given up on, are forgiven"
$rungSilent = @(Get-HordeMemoryWakerNudges).Count
Check (@($quiet | Where-Object { $_.kind -ceq "nudge" -and $_.at -gt 600 }).Count -eq 3) "and in the five minutes after, each session is knocked for once: only at the longest step"
Set-HordeMemoryWakerSession -Id (Sid 2) -Role "orc" -UnreadCount 0
$moved = New-Object System.Collections.ArrayList
foreach ($n in 301..310) { Set-HordeMemoryWakerClock (At ($n * 3)); foreach ($e in @(Invoke-HordeWakeTick -Run $run -Now (At ($n * 3)) -Waker $memory -ReadSessions $none -Settings $tenMinutes -HordeHome $h)) { [void]$moved.Add($e.kind + ":" + $e.id) } }
Check (@($moved | Where-Object { $_ -ceq "fleet-moving:" }).Count -eq 1 -and $moved[0] -ceq "fleet-moving:" -and $run.silence.silent -eq $false) ("when one session takes its mail the tick says fleet-moving, once (" + (@($moved) -join ",") + ")")
Check (@($moved | Where-Object { $_ -ceq ("nudge:" + (Sid 1)) }).Count -ge 1 -and @($moved | Where-Object { $_ -ceq ("nudge:" + (Sid 3)) }).Count -ge 1 -and @($run.ledger.Values | Where-Object { $_.attempts -ge 1 }).Count -eq 2) "and the two that still have mail are knocked for at once, as ordinary attempts counted from nothing: nobody is left unwoken when the fleet comes back"
# A SESSION LIMITED WITH NO KNOWN END is released by that same movement.
$h = New-Home
Reset-HordeMemoryWaker
Set-HordeMemoryWakerSession -Id (Sid 1) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60) -Limited $true
Set-HordeMemoryWakerSession -Id (Sid 2) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60) -MidTurn "yes"
$run = New-HordeWakeRun -Live -HordeHome $h
foreach ($n in 0..20) { Set-HordeMemoryWakerClock (At ($n * 3)); $null = Invoke-HordeWakeTick -Run $run -Now (At ($n * 3)) -Waker $memory -ReadSessions $none -HordeHome $h }
Check (@(Get-HordeMemoryWakerNudges).Count -eq 0) "CONTROL: a session limited with no known end is not nudged while nothing moves"
Set-HordeMemoryWakerSession -Id (Sid 2) -Role "orc" -UnreadCount 0
foreach ($n in 21..24) { Set-HordeMemoryWakerClock (At ($n * 3)); $null = Invoke-HordeWakeTick -Run $run -Now (At ($n * 3)) -Waker $memory -ReadSessions $none -HordeHome $h }
Check (@(Get-HordeMemoryWakerNudges -Id (Sid 1)).Count -eq 1 -and $run.ledger[(Sid 1)].attempts -eq 0) "when another session takes its mail it is knocked for, once, uncounted: a limit the fleet shares has reset"

Write-Host ""
Write-Host "--- the one switch: turned on, a live run posts what both senders have to say, and a shadow run still posts nothing ---" -ForegroundColor Cyan

$watch = & (Join-Path $root "messengers\memory\test\Fixture.ps1") -Root $root
$box = & $watch.New
$inProcess = Get-HordeMessenger -Name "memory"
$wasPosting = $script:HordeWakeSendersPost
Check ($wasPosting -eq $false) "the switch is off as shipped: neither sender posts in any mode"
try {
    $script:HordeWakeSendersPost = $true
    $h = New-Home
    Reset-HordeMemoryWaker
    Set-HordeMemoryWakerSession -Id (Sid 1) -Role "warchief" -UnreadCount 0
    Set-HordeMemoryWakerSession -Id (Sid 2) -Role "orc" -UnreadCount 0 -UnreadableCount 2
    $run = New-HordeWakeRun -Live -HordeHome $h
    $on = New-Object System.Collections.ArrayList
    foreach ($s in @(0, 3, 6)) { foreach ($e in @(Invoke-HordeWakeTick -Run $run -Now (At $s) -Waker $memory -ReadSessions $none -Messenger $inProcess -HordeHome $h)) { [void]$on.Add($e) } }
    $tells = @($on | Where-Object { $_.kind -ceq "tell" })
    Check ($tells.Count -eq 1 -and $tells[0].outcome -ceq "posted" -and @($on | Where-Object { $_.kind -ceq "would-tell" }).Count -eq 0) "with the switch on, a live run tells the warchief for real, once"
    $got = & $watch.Observe $box $tells[0].messageId
    Check ($got.records -eq 1 -and "$(@($got.bodies)[0])".StartsWith("AUTOMATED, from the wake watcher: the mailbox of the session " + (Sid 2))) "the mail is in the messenger's store, one record, and says it is automated"
    Check ((Test-Path -LiteralPath (Join-Path $h "wake\tells-live.json")) -and -not (Test-Path -LiteralPath (Join-Path $h "wake\tells-of-live-run-shadow.json"))) "and what was really told is kept in the live file"
    # THE FLEET CANNOT BE READ NOW: the warchief the last good pass named is who is told.
    Set-HordeMemoryWakerFault -Call "targets" -Kind "throw"
    $dark = New-Object System.Collections.ArrayList
    foreach ($n in 0..11) { foreach ($e in @(Invoke-HordeWakeTick -Run $run -Now (At (100 + $n * 3)) -Waker $memory -ReadSessions $none -Messenger $inProcess -HordeHome $h)) { [void]$dark.Add($e) } }
    $told = @($dark | Where-Object { $_.kind -ceq "tell" })
    Check ($told.Count -eq 1 -and $told[0].outcome -ceq "posted" -and (& $watch.Observe $box $told[0].messageId).records -eq 1) "a fleet that can no longer be read is told to the warchief the last good pass named: the pass that most needs somebody told is the one that cannot say who"
    Set-HordeMemoryWakerFault -Call "targets" -Kind ""
    # THE RESTORE SOURCE TURNS ON WITH IT.
    $h = New-Home
    Reset-HordeMemoryWaker
    $run = New-HordeWakeRun -Live -HordeHome $h
    $script:reads = 0
    $posts = @(Invoke-HordeWakeTick -Run $run -Now (At 0) -Waker $memory -ReadSessions $readRestored -Messenger $inProcess -HordeHome $h | Where-Object { $_.kind -ceq "post" -or $_.kind -ceq "would-post" })
    Check ($posts.Count -gt 0 -and @($posts | Where-Object { $_.kind -cne "post" -or $_.outcome -cne "posted" }).Count -eq 0 -and (Test-Path -LiteralPath (Join-Path $h "wake\restore-live.json"))) "and so does the restore source, at the same switch: its resume mails are posted, and marked in the live file"
    # A SHADOW RUN IS SHADOW WHATEVER THE SWITCH SAYS.
    $h = New-Home
    Reset-HordeMemoryWaker
    Set-HordeMemoryWakerSession -Id (Sid 1) -Role "warchief" -UnreadCount 0
    Set-HordeMemoryWakerSession -Id (Sid 2) -Role "orc" -UnreadCount 0 -UnreadableCount 2
    $run = New-HordeWakeRun -HordeHome $h
    $quiet = New-Object System.Collections.ArrayList
    foreach ($s in @(0, 3)) { foreach ($e in @(Invoke-HordeWakeTick -Run $run -Now (At $s) -Waker $memory -ReadSessions $readRestored -Messenger $inProcess -HordeHome $h)) { [void]$quiet.Add($e.kind) } }
    Check (@($quiet | Where-Object { $_ -ceq "tell" -or $_ -ceq "post" -or $_ -ceq "stall" }).Count -eq 0 -and @($quiet | Where-Object { $_ -ceq "would-tell" }).Count -eq 1 -and @($quiet | Where-Object { $_ -ceq "would-post" }).Count -gt 0) "a shadow run, with the switch on and a messenger in hand, still posts nothing: would-tell and would-post only"
} finally { $script:HordeWakeSendersPost = $wasPosting; & $watch.Remove $box }

Write-Host ""
Write-Host "--- a tick never throws: what fails is journaled once, and the next tick runs ---" -ForegroundColor Cyan

$h = New-Home
Reset-HordeMemoryWaker
$run = New-HordeWakeRun -HordeHome $h
$boom = { throw "the process table could not be read" }
$first = @(Invoke-HordeWakeTick -Run $run -Now (At 0) -Waker $memory -ReadSessions $boom -HordeHome $h)
Check ($first.Count -eq 1 -and $first[0].kind -ceq "skip-unknown" -and $first[0].id -ceq "restore" -and "$($first[0].reason)".Contains("could not be read")) "a reader of the sessions that throws is an entry saying so, not a throw of the tick"
$more = @(); foreach ($s in @(3, 6, 30, 33)) { $more += @(Invoke-HordeWakeTick -Run $run -Now (At $s) -Waker $memory -ReadSessions $boom -HordeHome $h) }
Check ($more.Count -eq 0 -and $run.pass -eq 5) "it is journaled once while it lasts - across the next reading too - and every tick still ran"
$mended = @(Invoke-HordeWakeTick -Run $run -Now (At 60) -Waker $memory -ReadSessions { New-HordeUnknown -Reason "no agent's listing is whole" } -HordeHome $h)
Check ($mended.Count -eq 1 -and "$($mended[0].reason)".Contains("no agent's listing is whole")) "a new reason is journaled when it changes"
$odd = @(Invoke-HordeWakeTick -Run $run -Now (At 90) -Waker $memory -ReadSessions { "not an answer" } -HordeHome $h)
Check ($odd.Count -eq 1 -and "$($odd[0].reason)".Contains("not an answer")) "and a reader that answers rubbish is unknown, with the reason"

# THE WAKE PASS FAILS: its ledger cannot be saved, because a folder stands where the file belongs.
$h = New-Home
Reset-HordeMemoryWaker
Set-HordeMemoryWakerSession -Id (Sid 1) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60)
New-Item -ItemType Directory -Path (Join-Path $h "wake\ledger-shadow.json") -Force | Out-Null
$run = New-HordeWakeRun -HordeHome $h
$none = { $a = New-HordeKnown -Value @(); Add-Member -InputObject $a -MemberType NoteProperty -Name "leftOut" -Value @(); $a }
$failed = @(Invoke-HordeWakeTick -Run $run -Now (At 0) -Waker $memory -ReadSessions $none -HordeHome $h)
Check (@($failed | Where-Object { $_.kind -ceq "skip-unknown" -and $_.id -ceq "pass" -and "$($_.reason)".Contains("the wake pass failed") }).Count -eq 1) "a wake pass that throws is an entry saying so"
Check ((Read-HordeWakeHeartbeat -Shadow -HordeHome $h).value.pass -eq 1) "and the heartbeat is still written: the watcher is alive"
$next = @(Invoke-HordeWakeTick -Run $run -Now (At 3) -Waker $memory -ReadSessions $none -HordeHome $h)
Check (@($next | Where-Object { $_.id -ceq "pass" }).Count -eq 0 -and (Read-HordeWakeHeartbeat -Shadow -HordeHome $h).value.pass -eq 2) "the next tick runs, and does not journal the same failure again"

# THE HEARTBEAT FAILS: a folder stands where it belongs.
$h = New-Home
Reset-HordeMemoryWaker
New-Item -ItemType Directory -Path (Join-Path $h "wake\heartbeat-shadow.json") -Force | Out-Null
$run = New-HordeWakeRun -HordeHome $h
$failed = @(Invoke-HordeWakeTick -Run $run -Now (At 0) -Waker $memory -ReadSessions $none -HordeHome $h)
Check (@($failed | Where-Object { $_.id -ceq "heartbeat" -and "$($_.reason)".Contains("could not be written") }).Count -eq 1) "a heartbeat that cannot be written is an entry saying so, not the end of the watcher"
$next = @(Invoke-HordeWakeTick -Run $run -Now (At 3) -Waker $memory -ReadSessions $none -HordeHome $h)
Check ($next.Count -eq 0 -and $run.pass -eq 2 -and @(Read-Lines $h).Count -eq 1) "and the loop goes on, the failure journaled once"

# THE JOURNAL FAILS: a folder stands where it belongs. The tick hands back what it could not write.
$h = New-Home
New-Item -ItemType Directory -Path (Join-Path $h "wake\journal-shadow.jsonl") -Force | Out-Null
$run = New-HordeWakeRun -HordeHome $h
$failed = @(Invoke-HordeWakeTick -Run $run -Now (At 0) -Waker $null -ReadSessions $boom -HordeHome $h)
Check (@($failed | Where-Object { $_.id -ceq "journal" }).Count -eq 1 -and @($failed | Where-Object { $_.id -ceq "restore" }).Count -eq 1) "a journal that cannot be written is handed back with the entries it lost, for the caller to print"

# A SAVED FILE THAT CANNOT BE READ: the run starts from empty and says so.
$h = New-Home
New-Item -ItemType Directory -Path (Join-Path $h "wake") | Out-Null
[System.IO.File]::WriteAllText((Join-Path $h "wake\ledger-shadow.json"), "{ not json")
[System.IO.File]::WriteAllText((Join-Path $h "wake\restore-shadow.json"), "{ not json")
$run = New-HordeWakeRun -HordeHome $h
Check ($run.ledger.Count -eq 0 -and @($run.said).Count -eq 2 -and "$($run.said[0])".Contains("empty ledger") -and "$($run.said[1])".Contains("no mail marked posted")) "a run whose saved state cannot be read starts from empty, and has two things to say"

Write-Host ""
Write-Host "--- a live tick sends exactly the nudges the pass decided, and nothing else ---" -ForegroundColor Cyan

$h = New-Home
Reset-HordeMemoryWaker
Set-HordeMemoryWakerSession -Id (Sid 1) -Role "warchief" -UnreadCount 1 -OldestUnreadAt (At -60)
Set-HordeMemoryWakerSession -Id (Sid 2) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60)
Set-HordeMemoryWakerSession -Id (Sid 3) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60) -BoxEmpty "no"
Set-HordeMemoryWakerSession -Id (Sid 4) -Role "orc" -UnreadCount 0
$live = New-HordeWakeRun -Live -HordeHome $h
Check ($live.live -eq $true -and (New-HordeWakeRun -HordeHome $h).live -eq $false) "a run is live only when it was made live; made without a word, it is shadow"
$script:reads = 0
$kinds = New-Object System.Collections.ArrayList
foreach ($s in @(0, 3)) {
    Set-HordeMemoryWakerClock (At $s)
    foreach ($e in @(Invoke-HordeWakeTick -Run $live -Now (At $s) -Waker $memory -ReadSessions $readRestored -TickSeconds 3 -ProcessId 4242 -HordeHome $h)) { [void]$kinds.Add($e.kind + ":" + $e.id + ":" + $e.outcome) }
}
Check ((@(Get-HordeMemoryWakerAsks) -join ",") -ceq ((Sid 1) + "," + (Sid 2))) "two live ticks ask the waker for exactly the two nudges decided, one a tick, the warchief first - not the session with text in its box, not the one with no mail"
Check ((@(Get-HordeMemoryWakerNudges | ForEach-Object { $_.id }) -join ",") -ceq ((Sid 1) + "," + (Sid 2))) "and both were rung"
Check (@($kinds | Where-Object { $_ -clike "nudge:*:woken" }).Count -eq 2 -and @($kinds | Where-Object { $_ -clike "would-nudge:*" }).Count -eq 0) "the journal says nudge, woken - not would-nudge"
# THE RESTORE SOURCE IS SHADOW EVEN NOW: a restore is found and mail is planned, and none is posted.
Check (@($kinds | Where-Object { $_ -clike "would-post:*" }).Count -eq 6 -and @($kinds | Where-Object { $_ -clike "would-stall:*" }).Count -eq 1 -and @($kinds | Where-Object { $_ -clike "post:*" -or $_ -clike "stall:*" }).Count -eq 0) ("in a live run the restore source still only journals would-post and would-stall, and posts nothing (" + (@($kinds | ForEach-Object { ($_ -split ":")[0] } | Group-Object | ForEach-Object { $_.Name + " x" + $_.Count }) -join ", ") + ")")
$names = @(Get-ChildItem -LiteralPath (Join-Path $h "wake") | ForEach-Object { $_.Name } | Sort-Object)
Check (($names -join ",") -ceq "heartbeat-live.json,journal-live.jsonl,ledger-live.json,restore-of-live-run-shadow.json") ("it wrote the live run's own journal, heartbeat and ledger, and kept what the source would have posted in a shadow file of its own - never restore-live.json, which is for mail really posted (" + ($names -join ",") + ")")
$beat = Read-HordeWakeHeartbeat -HordeHome $h
Check ($beat.state -ceq "known" -and $beat.value.shadow -eq $false -and $beat.value.pass -eq 2 -and (Read-HordeWakeHeartbeat -Shadow -HordeHome $h).state -ceq "absent") "its heartbeat is the live one, marked not shadow, and no shadow heartbeat was written"
# A SHADOW RUN BESIDE IT, on the same home: each keeps its own heartbeat and journal.
Reset-HordeMemoryWaker
$beside = New-HordeWakeRun -HordeHome $h
$null = Invoke-HordeWakeTick -Run $beside -Now (At 500) -Waker $memory -ReadSessions $none -TickSeconds 3 -ProcessId 4343 -HordeHome $h
Check ((Read-HordeWakeHeartbeat -HordeHome $h).value.at -eq (At 3) -and (Read-HordeWakeHeartbeat -Shadow -HordeHome $h).value.at -eq (At 500)) "a shadow run ticking on the same home leaves the live heartbeat as it was: a live watcher that died is not made to look alive"
Check (@(Read-HordeWakeJournalTail -Count 1000 -HordeHome $h | ForEach-Object { ($_ | ConvertFrom-Json).kind } | Where-Object { $_ -cnotlike "would-*" -and $_ -cne "nudge" }).Count -eq 0 -and @(Read-HordeWakeJournalTail -Count 1000 -HordeHome $h).Count -eq $kinds.Count) "and the live journal holds only the live run's lines"
$tampered = New-HordeWakeRun -HordeHome $h
$tampered.live = "yes"
Reset-HordeMemoryWaker
Set-HordeMemoryWakerSession -Id (Sid 1) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60)
$null = Invoke-HordeWakeTick -Run $tampered -Now (At 600) -Waker $memory -ReadSessions $none -HordeHome $h
Check (@(Get-HordeMemoryWakerAsks).Count -eq 0) "a run whose live is anything but true - a word, here - is ticked as shadow"

Write-Host ""
Write-Host "--- how a run starts: shadow unless another mode is named; live only through a verified waker; proof only as one pass ---" -ForegroundColor Cyan

$none5 = New-HordeAbsent -Note "no loaded waker offers every capability"
$one = New-HordeKnown -Value $memory
$p = Get-HordeWakeRunPlan -Picked $one
Check ($p.ok -and $p.live -eq $false -and [object]::ReferenceEquals($p.waker, $memory) -and "$($p.banner)".StartsWith("SHADOW - ")) "with no word the run is shadow, reads through the installed waker, and its banner begins SHADOW"
$p = Get-HordeWakeRunPlan -Picked $none5
Check ($p.ok -and $p.live -eq $false -and $null -eq $p.waker -and "$($p.banner)".StartsWith("SHADOW - ") -and "$($p.banner)".Contains("No waker is installed")) "a shadow run with no waker still starts, and says in its banner that none is installed"
$p = Get-HordeWakeRunPlan -Mode "live" -Picked $one
Check ($p.ok -and $p.live -eq $true -and [object]::ReferenceEquals($p.waker, $memory) -and "$($p.banner)".StartsWith("LIVE - REAL NUDGES") -and "$($p.banner)".Contains("restore source stays shadow")) "asked for by name, with a waker, the run is live, and its banner begins LIVE and says the restore source stays shadow"
# Caught on purpose: a plan that went on with no waker would throw reading its name, and a throw must
# fail this check rather than end it.
$p = $null
try { $p = Get-HordeWakeRunPlan -Mode "live" -Picked $none5 } catch { $p = $null }
Check ($null -ne $p -and $p.ok -eq $false -and $p.live -eq $false -and $null -eq $p.waker -and "$($p.reason)".Contains("needs an installed waker") -and "$($p.reason)".Contains("no loaded waker offers")) "a live run with no waker installed is refused, saying why"
$p = Get-HordeWakeRunPlan -Mode "live" -Picked (New-HordeUnknown -Reason "2 wakers each offer every capability")
Check ($p.ok -eq $false -and "$($p.reason)".Contains("2 wakers")) "and so is one when two wakers could be picked: one is never chosen"
# A WAKER WHOSE CAPABILITIES ARE UNVERIFIED: read through in shadow, named; never rung through live.
$claimed = Register-HordeWaker -Name "fixture-unverified" -Folder (Join-Path $root "test\fixtures\waker\caps\fixture-unverified") -Targets { New-HordeKnown -Value @() } -State { param($id) New-HordeUnknown -Reason "a fixture" } -Nudge { param($id) New-HordeUnknown -Reason "a fixture" }
$p = Get-HordeWakeRunPlan -Picked (New-HordeKnown -Value $claimed)
Check ($p.ok -and $p.live -eq $false -and [object]::ReferenceEquals($p.waker, $claimed) -and "$($p.banner)".StartsWith("SHADOW - ") -and "$($p.banner)".Contains("UNVERIFIED") -and "$($p.banner)".Contains("state.turn, nudge.guarded")) "a shadow run reads through a waker whose capabilities are unverified, and its banner names each one"
Check (-not "$((Get-HordeWakeRunPlan -Picked $one).banner)".Contains("UNVERIFIED")) "and says nothing of the kind for a waker that has none"
$p = Get-HordeWakeRunPlan -Mode "live" -Picked (New-HordeKnown -Value $claimed)
Check ($p.ok -eq $false -and $p.live -eq $false -and $null -eq $p.waker -and "$($p.reason)".Contains("unverified") -and "$($p.reason)".Contains("state.turn, nudge.guarded")) "a live run through it is refused, naming what is unverified"
# PROOF: one pass of real nudges, the only run that rings through unverified capabilities.
$p = Get-HordeWakeRunPlan -Mode "proof" -Once -Target (Sid 3) -Picked (New-HordeKnown -Value $claimed)
Check ($p.ok -and $p.mode -ceq "proof" -and $p.target -ceq (Sid 3) -and $p.live -eq $true -and [object]::ReferenceEquals($p.waker, $claimed) -and "$($p.banner)".StartsWith("PROOF - PROOF - PROOF - ONE PASS, AND AT MOST ONE REAL NUDGE, TO THE SESSION " + (Sid 3) + " AND NO OTHER") -and "$($p.banner)".Contains("UNVERIFIED") -and "$($p.banner)".Contains("state.turn, nudge.guarded")) "a proof run with -Once rings through a waker whose capabilities are unverified: its banner says PROOF, loudly, and names what it is there to show"
$p = Get-HordeWakeRunPlan -Mode "proof" -Target (Sid 3) -Picked (New-HordeKnown -Value $claimed)
Check ($p.ok -eq $false -and $p.live -eq $false -and $null -eq $p.waker -and "$($p.reason)".Contains("add -Once")) "a proof run without -Once is refused: it is never a loop"
$p = Get-HordeWakeRunPlan -Mode "proof" -Once -Target (Sid 3) -Picked $none5
Check ($p.ok -eq $false -and "$($p.reason)".Contains("needs an installed waker")) "and so is one with no waker to ring through"
$p = Get-HordeWakeRunPlan -Mode "proof" -Once -Target (Sid 3) -Picked $one
Check ($p.ok -and $p.mode -ceq "proof" -and -not "$($p.banner)".Contains("UNVERIFIED")) "a proof run through a waker with nothing unverified runs, and names none"
# A PROOF RUN HAS ONE SESSION, NAMED BY THE PERSON: no target, or one that is no whole session id, is a
# mistake in the command line; and a target is nothing a shadow or a live run has.
$p = Get-HordeWakeRunPlan -Mode "proof" -Once -Picked $one
Check ($p.ok -eq $false -and $p.usage -eq $true -and $p.live -eq $false -and $null -eq $p.waker -and "$($p.reason)".Contains("needs -Target")) "a proof run with no -Target is refused as a usage error: it never picks a session itself"
foreach ($bad in @("A", "M", "0a000000", "0a000000-0000-4000-8000", ((Sid 3).ToUpperInvariant()), ((Sid 3) + " "), ((Sid 3) + "`n"), "*", ((Sid 3) + "," + (Sid 2)))) {
    $p = Get-HordeWakeRunPlan -Mode "proof" -Once -Target $bad -Picked $one
    Check ($p.ok -eq $false -and $p.usage -eq $true -and $p.live -eq $false -and $p.target -ceq "") ("a -Target of '" + $bad.Trim() + "' - a label, a part of an id, another casing, two ids - is refused: a session id written out in full, or nothing")
}
foreach ($word in @("shadow", "live")) {
    $p = Get-HordeWakeRunPlan -Mode $word -Once -Target (Sid 3) -Picked $one
    Check ($p.ok -eq $false -and $p.usage -eq $true -and $p.live -eq $false) ("-Target with -Mode " + $word + " is refused as a usage error: only a proof run has one session")
}
Check ((Get-HordeWakeRunPlan -Mode "live" -Picked $one).usage -eq $false -and (Get-HordeWakeRunPlan -Mode "live" -Picked $none5).usage -eq $false) "a refusal that is no mistake in the command line - no waker - is not called one"
# THE PASS OF A PROOF RUN: three sessions are ready, the warchief among them, and the person named the
# one the fair order serves LAST.
$h = New-Home
Reset-HordeMemoryWaker
Set-HordeMemoryWakerSession -Id (Sid 1) -Role "warchief" -UnreadCount 1 -OldestUnreadAt (At -600)
Set-HordeMemoryWakerSession -Id (Sid 2) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -300)
Set-HordeMemoryWakerSession -Id (Sid 3) -Role "warg" -UnreadCount 1 -OldestUnreadAt (At -60)
Set-HordeMemoryWakerClock (At 0)
$aimed = New-HordeWakeRun -Mode "proof" -Target (Sid 3) -HordeHome $h
$did = @(Invoke-HordeWakeTick -Run $aimed -Now (At 0) -Waker $memory -ReadSessions $none -HordeHome $h | ForEach-Object { $_.kind + ":" + $_.id })
Check ((@(Get-HordeMemoryWakerNudges | ForEach-Object { $_.id }) -join ",") -ceq (Sid 3) -and (@(Get-HordeMemoryWakerAsks) -join ",") -ceq (Sid 3) -and ($did -join ",") -ceq ("nudge:" + (Sid 3))) ("of three ready sessions a proof run nudges exactly one, the one it was aimed at - not the warchief, which the fair order serves first (" + ($did -join ",") + ")")
Check ((@(Get-HordeMemoryWakerReads | Sort-Object -Unique) -join ",") -ceq (Sid 3)) ("and no other session's state was so much as read (" + (@(Get-HordeMemoryWakerReads) -join ",") + ")")
# A TARGET THAT IS NOT IN THE FLEET: nobody is nudged - the pass never falls back to who is ready.
$h = New-Home
Reset-HordeMemoryWaker
Set-HordeMemoryWakerSession -Id (Sid 1) -Role "warchief" -UnreadCount 1 -OldestUnreadAt (At -600)
Set-HordeMemoryWakerSession -Id (Sid 2) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -300)
$astray = New-HordeWakeRun -Mode "proof" -Target (Sid 9) -HordeHome $h
$did = @(Invoke-HordeWakeTick -Run $astray -Now (At 0) -Waker $memory -ReadSessions $none -HordeHome $h)
Check (@(Get-HordeMemoryWakerAsks).Count -eq 0 -and @(Get-HordeMemoryWakerReads).Count -eq 0 -and @($did | Where-Object { $_.kind -ceq "proof-target-absent" -and $_.id -ceq (Sid 9) -and "$($_.reason)".Contains("not in the fleet's listing") }).Count -eq 1) "a proof run aimed at a session the fleet does not list nudges nobody, reads nobody, and says so in one line"
# A PROOF RUN WITH NO TARGET AT ALL - made by a caller that skipped the plan - nudges nobody.
$h = New-Home
$blindProof = New-HordeWakeRun -Mode "proof" -HordeHome $h
$did = @(Invoke-HordeWakeTick -Run $blindProof -Now (At 0) -Waker $memory -ReadSessions $none -HordeHome $h)
Check (@(Get-HordeMemoryWakerAsks).Count -eq 0 -and @(Get-HordeMemoryWakerReads).Count -eq 0 -and @($did | Where-Object { $_.kind -ceq "skip-unknown" -and $_.id -ceq "pass" -and "$($_.reason)".Contains("without the one session") }).Count -eq 1) "a proof run made with no target never runs the pass over the fleet: nobody is read, nobody is nudged"
Check ((New-HordeWakeRun -Mode "live" -Target (Sid 3) -HordeHome $h).target -ceq "" -and (New-HordeWakeRun -Target (Sid 3) -HordeHome $h).target -ceq "") "and a target is kept for a proof run only"
# THE FLEET CANNOT BE READ: the proof's session was not found, and that is said.
Reset-HordeMemoryWaker
Set-HordeMemoryWakerFault -Call "targets" -Kind "throw"
$h = New-Home
$dark = New-HordeWakeRun -Mode "proof" -Target (Sid 3) -HordeHome $h
$did = @(Invoke-HordeWakeTick -Run $dark -Now (At 0) -Waker $memory -ReadSessions $none -HordeHome $h | ForEach-Object { $_.kind })
Check (($did -join ",") -ceq "skip-unknown,proof-target-absent") ("a proof run over a fleet that cannot be read says so, and that its session was not found (" + ($did -join ",") + ")")
Reset-HordeMemoryWaker
foreach ($word in @("LIVE", "Live", "liv", "l", "", "both")) {
    $p = Get-HordeWakeRunPlan -Mode $word -Once -Picked $one
    Check ($p.ok -eq $false -and $p.live -eq $false -and $null -eq $p.waker) ("the mode '" + $word + "' is no mode: refused, never taken for the nearest one")
}
Check ((Get-HordeWakeRunPlan -Mode "live" -Picked $one).mode -ceq "live" -and (Get-HordeWakeRunPlan -Picked $one).mode -ceq "shadow") "a plan says its mode"
# WHICH WAKER A MODE MAY HAVE: loaded here are the in-process one, which declines a capability, and
# the fixture that claims all five with two unverified.
Check ((Get-HordeWakeRunPick -Mode "live").state -ceq "absent") "for a live run the port is asked for a waker that offers every capability: there is none here"
$pick = Get-HordeWakeRunPick -Mode "proof"
Check ($pick.state -ceq "known" -and [object]::ReferenceEquals($pick.value, $claimed) -and (Get-HordeWakeRunPick -Mode "shadow").state -ceq "known" -and (Get-HordeWakeRunPick).state -ceq "known") "for a proof run and a shadow run, one that claims them unverified will do"
# A PROOF RUN'S FILES ARE ITS OWN.
$h = New-Home
Reset-HordeMemoryWaker
Set-HordeMemoryWakerSession -Id (Sid 1) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60)
Set-HordeMemoryWakerClock (At 0)
$proof = New-HordeWakeRun -Mode "proof" -Target (Sid 1) -HordeHome $h
$proved = @(Invoke-HordeWakeTick -Run $proof -Now (At 0) -Waker $memory -ReadSessions $readRestored -TickSeconds 3 -ProcessId 4545 -HordeHome $h | ForEach-Object { $_.kind })
Check ($proof.mode -ceq "proof" -and $proof.live -eq $true -and @(Get-HordeMemoryWakerNudges).Count -eq 1 -and @($proved | Where-Object { $_ -ceq "nudge" }).Count -eq 1) "a proof run's tick sends the real nudge"
Check (@($proved | Where-Object { $_ -ceq "post" -or $_ -ceq "stall" -or $_ -ceq "tell" }).Count -eq 0 -and @($proved | Where-Object { $_ -ceq "would-post" }).Count -gt 0) "and posts nothing: the senders are shadow in a proof run"
$names = @(Get-ChildItem -LiteralPath (Join-Path $h "wake") | ForEach-Object { $_.Name } | Sort-Object)
Check (($names -join ",") -ceq "heartbeat-proof.json,journal-proof.jsonl,ledger-proof.json,restore-of-proof-run-shadow.json") ("it wrote the proof run's own files and no file of a live or a shadow run (" + ($names -join ",") + ")")
$beat = Read-HordeWakeHeartbeat -Mode "proof" -HordeHome $h
Check ($beat.state -ceq "known" -and $beat.value.mode -ceq "proof" -and $beat.value.shadow -eq $false -and (Read-HordeWakeHeartbeat -HordeHome $h).state -ceq "absent" -and (Read-HordeWakeHeartbeat -Shadow -HordeHome $h).state -ceq "absent") "its heartbeat says proof, and neither the live nor the shadow heartbeat was written: a proof pass does not make a live watcher look alive"
$switchWas = $script:HordeWakeSendersPost
try { $script:HordeWakeSendersPost = $true; Check ((Test-HordeWakeSendersShadow -Run $proof) -eq $true -and (Test-HordeWakeSendersShadow -Run (New-HordeWakeRun -Mode "live" -HordeHome $h)) -eq $false) "with the senders' switch on, a live run posts and a proof run still does not" } finally { $script:HordeWakeSendersPost = $switchWas }
$threw = $false; try { $null = New-HordeWakeRun -Mode "LIVE" -HordeHome $h } catch { $threw = $true }
Check $threw "a run cannot be made in a mode that is no mode"
$lockP = Enter-HordeWakeLock -Mode "proof" -ProcessId 1 -HordeHome $h
# Caught on purpose: a lock that threw for a second holder must fail this check, not end the suite.
$secondP = "threw"
try { $secondP = Enter-HordeWakeLock -Mode "proof" -ProcessId 2 -HordeHome $h } catch { $secondP = "threw" }
try { Check ($null -ne $lockP -and (Test-Path -LiteralPath (Join-Path $h "wake\run-proof.lock")) -and $null -eq $secondP) "a proof run holds a lock of its own, and a second proof run is kept out" } finally { if ($null -ne $lockP) { $lockP.Dispose() }; if ($null -ne $secondP -and $secondP -isnot [string]) { $secondP.Dispose() } }
$p = Get-HordeWakeRunPlan -Mode "live" -Picked "not an answer"
Check ($p.ok -eq $false -and $p.live -eq $false) "and an answer about the waker that is not one never makes a live run"

Write-Host ""
Write-Host "--- one run a home and a mode: a lock that is a held file, not a pid ---" -ForegroundColor Cyan

$h = New-Home
$lock = Enter-HordeWakeLock -Shadow -ProcessId 4242 -HordeHome $h
Check ($null -ne $lock) "the first run takes the lock"
# Caught on purpose: a lock that THREW for a held file must fail this check, not end it.
$second = "not asked"
try { $second = Enter-HordeWakeLock -Shadow -ProcessId 4243 -HordeHome $h } catch { $second = "threw: " + $_.Exception.Message }
Check ($null -eq $second) "a second run in the same home and mode is refused while the first holds it"
$live = Enter-HordeWakeLock -ProcessId 4244 -HordeHome $h
Check ($null -ne $live) "a live run's lock is another: shadow and live do not shut each other out"
if ($null -ne $live) { $live.Dispose() }
Check ([System.IO.File]::Open((Join-Path $h "wake\run-shadow.lock"), [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite) -is [System.IO.FileStream]) "CONTROL: the held lock can still be opened for reading"
$lock.Dispose()
# The file is still there, with the pid of a process that no longer holds it: exactly what a crash leaves.
Check (Test-Path -LiteralPath (Join-Path $h "wake\run-shadow.lock") -PathType Leaf) "CONTROL: the lock file outlives the run that held it"
$after = Enter-HordeWakeLock -Shadow -ProcessId 4245 -HordeHome $h
Check ($null -ne $after) "a lock left by a run that is gone blocks nobody: it is the open handle that holds, not the file or the pid in it"
if ($null -ne $after) { $after.Dispose() }
# ONLY "ANOTHER PROCESS HOLDS IT" IS A HELD LOCK. Every other failure to open it is what it is.
Check (Test-HordeWakeSharingViolation (New-Object System.IO.IOException("in use", -2147024864))) "a sharing violation (Win32 error 32) is a held lock"
Check (Test-HordeWakeSharingViolation (New-Object System.IO.IOException("locked", -2147024863))) "and so is a lock violation (33)"
Check (-not (Test-HordeWakeSharingViolation (New-Object System.IO.IOException("the disk is full", -2147024784)))) "a full disk is not a held lock"
Check (-not (Test-HordeWakeSharingViolation (New-Object System.IO.IOException("something else")))) "nor is an I/O failure with no such error number"
Check (-not (Test-HordeWakeSharingViolation (New-Object System.UnauthorizedAccessException("denied")))) "nor a file nobody may open"
Check (Test-HordeWakeSharingViolation (New-Object System.Exception("wrapped", (New-Object System.IO.IOException("in use", -2147024864))))) "a sharing violation wrapped in another exception is still one"
Check (-not (Test-HordeWakeSharingViolation $null)) "and nothing at all is not one"
$h = New-Home
New-Item -ItemType Directory -Path (Join-Path $h "wake\run-shadow.lock") -Force | Out-Null
$took = "nothing"
try { $took = Enter-HordeWakeLock -Shadow -ProcessId 4246 -HordeHome $h; if ($null -eq $took) { $took = "refused as held" } } catch { $took = "threw: " + $_.Exception.Message }
Check ("$took".StartsWith("threw: ")) ("a lock that cannot be opened for another reason - a folder stands where it belongs - is thrown as what it is, never answered as 'already running' (" + $took + ")")

} finally {
    Reset-HordeMemoryWaker
    [System.GC]::Collect()
    Exit-HordeTestPinnedHome -State $pinned
    Exit-HordeTestEmptyFleet -Pin $fleetPin
}

Complete-HordeSuite -Success "a shadow tick rings nobody, posts nothing, survives what its parts throw, and only one run holds a home"
