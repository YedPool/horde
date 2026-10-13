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
Check ((@(Get-ChildItem -LiteralPath (Join-Path $h "wake") | ForEach-Object { $_.Name } | Sort-Object) -join ",") -ceq "heartbeat-live.json,journal-live.jsonl,ledger-live.json,silence-live.json,tells-of-live-run-shadow.json") "and what the live run would have told is kept in a shadow file of its own - never tells-live.json, which is for what was really told, and never the shadow run's"
$h = New-Home
Reset-HordeMemoryWaker
Set-HordeMemoryWakerSession -Id (Sid 2) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60) -Outcome "busy" -OutcomeReason "mid-turn"
$run = New-HordeWakeRun -Live -HordeHome $h
$gave = New-Object System.Collections.ArrayList
foreach ($n in 0..7) { Set-HordeMemoryWakerClock (At ($n * 400)); foreach ($e in @(Invoke-HordeWakeTick -Run $run -Now (At ($n * 400)) -Waker $memory -ReadSessions $none -Settings (Get-HordeWakeSettings -Overrides @{ maxNudgesPerMail = 2 }) -HordeHome $h)) { [void]$gave.Add($e.kind) } }
Check (@($gave | Where-Object { $_ -ceq "gave-up" }).Count -eq 1 -and @($gave | Where-Object { $_ -ceq "would-tell" }).Count -eq 1) ("a session given up on is one gave-up line and one tell, over eight ticks (" + (@($gave) -join ",") + ")")

# A RETIRED SESSION WITH MAIL: said once, and nothing else - no nudge, no attempt, no gave-up, no tell.
$h = New-Home
Reset-HordeMemoryWaker
Set-HordeMemoryWakerSession -Id (Sid 1) -Role "warchief" -UnreadCount 0
Set-HordeMemoryWakerSession -Id (Sid 2) -Role "orc" -UnreadCount 2 -OldestUnreadAt (At -60) -Retired "yes"
$run = New-HordeWakeRun -Live -HordeHome $h
$ret = New-Object System.Collections.ArrayList
foreach ($n in 0..399) { Set-HordeMemoryWakerClock (At ($n * 3)); foreach ($e in @(Invoke-HordeWakeTick -Run $run -Now (At ($n * 3)) -Waker $memory -ReadSessions $none -HordeHome $h)) { [void]$ret.Add($e.kind + ":" + $e.id + "@" + ($n * 3)) } }
Check ((@($ret) -join ",") -ceq ("never-nudged:" + (Sid 2) + "@0") -and @(Get-HordeMemoryWakerAsks).Count -eq 0 -and $run.ledger.Count -eq 0) ("twenty minutes of live ticks over a retired session with unread mail journal one line - never-nudged - and nudge, count, give up on and tell of nobody (" + (@($ret) -join ",") + ")")

# A SESSION THAT MAY BE RETIRED is journaled as held - it waits - and one that IS, as never-nudged.
$h = New-Home
Reset-HordeMemoryWaker
Set-HordeMemoryWakerSession -Id (Sid 2) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60) -Retired "unknown"
$run = New-HordeWakeRun -Live -Self "" -HordeHome $h
$kinds = @(foreach ($n in 0..5) { Invoke-HordeWakeTick -Run $run -Now (At ($n * 3)) -Waker $memory -ReadSessions $none -HordeHome $h | ForEach-Object { $_.kind + ":" + $_.outcome } })
Check (($kinds -join ",") -ceq "held:held") ("a session that may be retired is journaled once as held: the journal's kind says which rule it was (" + ($kinds -join ",") + ")")
# THE WATCHER'S OWN SESSION AND A SENDER'S LABEL, through the tick, live: said once, never nudged.
$h = New-Home
Reset-HordeMemoryWaker
Set-HordeMemoryWakerSession -Id (Sid 1) -Role "warchief" -UnreadCount 1 -OldestUnreadAt (At -60)
Set-HordeMemoryWakerSession -Id (Sid 2) -Role "orc" -Label "WW" -UnreadCount 1 -OldestUnreadAt (At -60)
Set-HordeMemoryWakerSession -Id (Sid 3) -Role "orc" -Label "B" -UnreadCount 1 -OldestUnreadAt (At -60)
$run = New-HordeWakeRun -Live -Self (Sid 1) -HordeHome $h
$mine = New-Object System.Collections.ArrayList
foreach ($n in 0..100) { Set-HordeMemoryWakerClock (At ($n * 3)); foreach ($e in @(Invoke-HordeWakeTick -Run $run -Now (At ($n * 3)) -Waker $memory -ReadSessions $none -HordeHome $h)) { [void]$mine.Add($e.kind + ":" + $e.id) } }
Check ($run.self -ceq (Sid 1) -and @(Get-HordeMemoryWakerAsks | Where-Object { $_ -ceq (Sid 1) -or $_ -ceq (Sid 2) }).Count -eq 0 -and @(Get-HordeMemoryWakerAsks | Where-Object { $_ -ceq (Sid 3) }).Count -ge 1) "five minutes of live ticks never nudge the session the watcher was started from, nor the one wearing a sender's label - only the third"
Check (@($mine | Where-Object { $_ -ceq ("never-nudged:" + (Sid 1)) }).Count -eq 1 -and @($mine | Where-Object { $_ -ceq ("never-nudged:" + (Sid 2)) }).Count -eq 1 -and -not $run.ledger.ContainsKey((Sid 1)) -and -not $run.ledger.ContainsKey((Sid 2))) "each is journaled once, as never-nudged, and nothing is counted against either"
Check ((New-HordeWakeRun -Self "" -HordeHome $h).self -ceq "") "a watcher told it was started from no session holds nobody back for that"

# A USAGE LIMIT: said once, no nudge until it ends.
$h = New-Home
Reset-HordeMemoryWaker
Set-HordeMemoryWakerSession -Id (Sid 1) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60) -Limited "yes" -LimitedUntil (At 300)
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
Check (@($quiet | Where-Object { $_.kind -ceq "nudge" -and $_.at -gt 600 }).Count -eq 1) "and in the five minutes after, ONE session of the three is knocked for, once: a silent fleet is asked by one probe at a time"
Set-HordeMemoryWakerSession -Id (Sid 2) -Role "orc" -UnreadCount 0
$moved = New-Object System.Collections.ArrayList
foreach ($n in 301..310) { Set-HordeMemoryWakerClock (At ($n * 3)); foreach ($e in @(Invoke-HordeWakeTick -Run $run -Now (At ($n * 3)) -Waker $memory -ReadSessions $none -Settings $tenMinutes -HordeHome $h)) { [void]$moved.Add($e.kind + ":" + $e.id) } }
Check (@($moved | Where-Object { $_ -ceq "fleet-moving:" }).Count -eq 1 -and $moved[0] -ceq "fleet-moving:" -and $run.silence.silent -eq $false) ("when one session takes its mail the tick says fleet-moving, once (" + (@($moved) -join ",") + ")")
Check (@($moved | Where-Object { $_ -ceq ("nudge:" + (Sid 1)) }).Count -ge 1 -and @($moved | Where-Object { $_ -ceq ("nudge:" + (Sid 3)) }).Count -ge 1 -and @($run.ledger.Values | Where-Object { $_.attempts -ge 1 }).Count -eq 2) "and the two that still have mail are knocked for at once, as ordinary attempts counted from nothing: nobody is left unwoken when the fleet comes back"
# A WATCHER RESTARTED IN A SILENT FLEET goes on from the silence: it is not found a second time, and no budget is spent again.
$h = New-Home
Reset-HordeMemoryWaker
foreach ($n in 1..3) { Set-HordeMemoryWakerSession -Id (Sid $n) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60) }
$run = New-HordeWakeRun -Live -Self "" -HordeHome $h
foreach ($n in 0..201) { Set-HordeMemoryWakerClock (At ($n * 3)); $null = Invoke-HordeWakeTick -Run $run -Now (At ($n * 3)) -Waker $memory -ReadSessions $none -Settings $tenMinutes -HordeHome $h }
Check ($run.silence.silent -eq $true -and (Test-Path -LiteralPath (Join-Path $h "wake\silence-live.json"))) "CONTROL: the fleet is found silent, and that is saved"
$asksBefore = @(Get-HordeMemoryWakerAsks).Count
$again = New-HordeWakeRun -Live -Self "" -HordeHome $h
Check ($null -ne $again.silence -and $again.silence.silent -eq $true -and $again.silence.quietSince -eq (At 0) -and @($again.ledger.Values | Where-Object { $_.attempts -ne 0 }).Count -eq 0) "a watcher started again reads back that the fleet is silent, since when, and the ledger whose attempts were forgiven"
$after = New-Object System.Collections.ArrayList
foreach ($n in 202..420) { Set-HordeMemoryWakerClock (At ($n * 3)); foreach ($e in @(Invoke-HordeWakeTick -Run $again -Now (At ($n * 3)) -Waker $memory -ReadSessions $none -Settings $tenMinutes -HordeHome $h)) { [void]$after.Add($e.kind) } }
$asksAfter = @(Get-HordeMemoryWakerAsks).Count - $asksBefore
Check (@($after | Where-Object { $_ -ceq "fleet-silent" -or $_ -ceq "gave-up" }).Count -eq 0 -and $asksAfter -ge 1 -and $asksAfter -le 3 -and @($again.ledger.Values | Where-Object { $_.attempts -ne 0 }).Count -eq 0) ("eleven minutes on, the restarted watcher has not found the silence a second time, has given up on nobody, counted nothing, and sent only the fleet's one probe each five minutes (" + $asksAfter + " knocks; " + (@($after) -join ",") + ")")
Set-HordeMemoryWakerSession -Id (Sid 2) -Role "orc" -UnreadCount 0
$end = @(foreach ($n in 421..423) { Set-HordeMemoryWakerClock (At ($n * 3)); Invoke-HordeWakeTick -Run $again -Now (At ($n * 3)) -Waker $memory -ReadSessions $none -Settings $tenMinutes -HordeHome $h | ForEach-Object { $_.kind } })
Check (@($end | Where-Object { $_ -ceq "fleet-moving" }).Count -eq 1 -and (New-HordeWakeRun -Live -Self "" -HordeHome $h).silence.silent -eq $false) "and when a session takes its mail it says fleet-moving, and that is saved too"
[System.IO.File]::WriteAllText((Join-Path $h "wake\silence-live.json"), "{ not json")
$unsure = New-HordeWakeRun -Live -Self "" -HordeHome $h
Check ($null -eq $unsure.silence -and @($unsure.said | Where-Object { "$_".Contains("as though the fleet were not silent") }).Count -eq 1 -and "$($unsure.refused)" -ceq "") "a saved silence that cannot be read is said, and the run starts as though the fleet were not silent"
$hp = New-Home
Save-HordeWakeSilence -Seen ([pscustomobject]@{ silent = $true; quietSince = (At 5); nudges = @(1, 2); mail = @{ x = 1 }; moves = @{ (Sid 2) = (At 9) } }) -Mode "live" -HordeHome $hp
$sb = Read-HordeWakeSilence -Mode "live" -HordeHome $hp
Check ($sb.state -ceq "known" -and $sb.value.seen.silent -eq $true -and $sb.value.seen.quietSince -eq (At 5) -and $sb.value.seen.moves[(Sid 2)] -eq (At 9) -and @($sb.value.seen.nudges).Count -eq 0 -and $sb.value.seen.mail.Count -eq 0 -and (Read-HordeWakeSilence -HordeHome $hp).state -ceq "absent") "what is saved is whether, since when and who took mail - read back as it was, under the sending runs' name and not the shadow run's"

# A SESSION LIMITED WITH NO KNOWN END is released by that same movement.
$h = New-Home
Reset-HordeMemoryWaker
Set-HordeMemoryWakerSession -Id (Sid 1) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60) -Limited "yes"
Set-HordeMemoryWakerSession -Id (Sid 2) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60) -MidTurn "yes"
$run = New-HordeWakeRun -Live -HordeHome $h
foreach ($n in 0..20) { Set-HordeMemoryWakerClock (At ($n * 3)); $null = Invoke-HordeWakeTick -Run $run -Now (At ($n * 3)) -Waker $memory -ReadSessions $none -HordeHome $h }
Check (@(Get-HordeMemoryWakerNudges).Count -eq 0) "CONTROL: a session limited with no known end is not nudged while nothing moves"
Set-HordeMemoryWakerSession -Id (Sid 2) -Role "orc" -UnreadCount 0
foreach ($n in 21..24) { Set-HordeMemoryWakerClock (At ($n * 3)); $null = Invoke-HordeWakeTick -Run $run -Now (At ($n * 3)) -Waker $memory -ReadSessions $none -HordeHome $h }
Check (@(Get-HordeMemoryWakerNudges -Id (Sid 1)).Count -eq 1 -and $run.ledger[(Sid 1)].attempts -eq 0) "when another session takes its mail it is knocked for, once, uncounted: a limit the fleet shares has reset"

# A SESSION WHOSE LIMIT NOBODY COULD READ waits, and is nudged - counted, as normal - once another is seen taking mail.
$h = New-Home
Reset-HordeMemoryWaker
Set-HordeMemoryWakerSession -Id (Sid 1) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60) -Limited "unknown"
Set-HordeMemoryWakerSession -Id (Sid 2) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60) -MidTurn "yes"
$run = New-HordeWakeRun -Live -HordeHome $h
$unk = New-Object System.Collections.ArrayList
foreach ($n in 0..20) { Set-HordeMemoryWakerClock (At ($n * 3)); foreach ($e in @(Invoke-HordeWakeTick -Run $run -Now (At ($n * 3)) -Waker $memory -ReadSessions $none -HordeHome $h)) { [void]$unk.Add($e.kind) } }
Check (@(Get-HordeMemoryWakerNudges).Count -eq 0 -and (@($unk) -join ",") -ceq "usage-limit") ("a session whose limit could not be read is not nudged while nothing shows sessions taking turns, and that is journaled once (" + (@($unk) -join ",") + ")")
Set-HordeMemoryWakerSession -Id (Sid 2) -Role "orc" -UnreadCount 0
foreach ($n in 21..22) { Set-HordeMemoryWakerClock (At ($n * 3)); $null = Invoke-HordeWakeTick -Run $run -Now (At ($n * 3)) -Waker $memory -ReadSessions $none -HordeHome $h }
Check (@(Get-HordeMemoryWakerNudges -Id (Sid 1)).Count -eq 1 -and $run.ledger.ContainsKey((Sid 1)) -and $run.ledger[(Sid 1)].attempts -eq 1 -and $run.silence.moves[(Sid 2)] -eq (At 63)) "once another session takes its mail it is nudged, as an ordinary counted attempt: there is fresh evidence that sessions can take turns"

# A FAULT AFTER THE NUDGE MUST NOT FORGET THE NUDGE. What was told cannot be saved - a folder stands where
# the file belongs - on the very tick a nudge had to be killed, which is a thing the warchief is told of.
$h = New-Home
Reset-HordeMemoryWaker
Set-HordeMemoryWakerSession -Id (Sid 1) -Role "warchief" -UnreadCount 0
Set-HordeMemoryWakerSession -Id (Sid 2) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60) -Outcome "killed" -OutcomeReason "nudge-killed: stopped part-way"
New-Item -ItemType Directory -Path (Join-Path $h "wake\tells-of-live-run-shadow.json") -Force | Out-Null
$run = New-HordeWakeRun -Live -HordeHome $h
$faulty = New-Object System.Collections.ArrayList
foreach ($n in 0..40) { Set-HordeMemoryWakerClock (At ($n * 3)); foreach ($e in @(Invoke-HordeWakeTick -Run $run -Now (At ($n * 3)) -Waker $memory -ReadSessions $none -HordeHome $h)) { [void]$faulty.Add($e.kind + ":" + $e.id + "@" + ($n * 3)) } }
Check (@(Get-HordeMemoryWakerAsks).Count -eq 1) ("with the tells' file unwritable for two minutes, the session whose nudge was killed is asked ONCE - the nudge is remembered, and its back-off holds - not again on every tick (" + @(Get-HordeMemoryWakerAsks).Count + " asks)")
Check ($run.ledger.ContainsKey((Sid 2)) -and $run.ledger[(Sid 2)].attempts -ge 1 -and (Read-HordeWakeLedger -Mode "live" -HordeHome $h).state -ceq "known" -and (Read-HordeWakeLedger -Mode "live" -HordeHome $h).value.ledger.ContainsKey((Sid 2))) "the ledger was kept and saved before the tell was tried: a watcher restarted in the middle of the fault does not knock again either"
Check (@($faulty | Where-Object { $_ -clike "skip-unknown:tell@*" }).Count -eq 1 -and @($faulty | Where-Object { $_ -clike "skip-unknown:pass@*" }).Count -eq 0 -and @($faulty | Where-Object { $_ -clike "nudge-killed:*" }).Count -eq 1 -and @($faulty | Where-Object { $_ -clike "would-tell:*" }).Count -eq 1) ("the fault is said once, as the tell's own and not the pass's, and the nudge and the tell are journaled (" + (@($faulty) -join ",") + ")")
# ...and a tell that cannot even be MADE costs the pass nothing either.
$h = New-Home
Reset-HordeMemoryWaker
Set-HordeMemoryWakerSession -Id (Sid 2) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60) -Outcome "killed" -OutcomeReason "nudge-killed: stopped part-way"
$run = New-HordeWakeRun -Live -HordeHome $h
$realKinds = $script:HordeWakeTellKinds
try {
    $script:HordeWakeTellKinds = @("gave-up")
    $unmade = New-Object System.Collections.ArrayList
    foreach ($n in 0..10) { Set-HordeMemoryWakerClock (At ($n * 3)); foreach ($e in @(Invoke-HordeWakeTick -Run $run -Now (At ($n * 3)) -Waker $memory -ReadSessions $none -HordeHome $h)) { [void]$unmade.Add($e.kind + ":" + $e.id) } }
} finally { $script:HordeWakeTellKinds = $realKinds }
Check (@(Get-HordeMemoryWakerAsks).Count -eq 1 -and $run.ledger.ContainsKey((Sid 2)) -and @($unmade | Where-Object { $_ -ceq "skip-unknown:tell" }).Count -eq 1) ("a tell that cannot be made is said once, and the nudge is remembered: one ask in thirty seconds (" + (@($unmade) -join ",") + ")")

# A LEDGER THAT IS THERE AND CANNOT BE READ: a run that sends is refused; a shadow run starts from empty and says so.
foreach ($sending in @("live", "proof")) {
    $h = New-Home
    New-Item -ItemType Directory -Path (Join-Path $h "wake") -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $h "wake\ledger-live.json"), "{ not json")
    Reset-HordeMemoryWaker
    Set-HordeMemoryWakerSession -Id (Sid 1) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60)
    Set-HordeMemoryWakerClock (At 0)
    $bad = New-HordeWakeRun -Mode $sending -Target (Sid 1) -HordeHome $h
    Check ("$($bad.refused)".Contains("cannot be read") -and "$($bad.refused)".Contains("ledger-live.json")) ("a " + $sending + " run made over a ledger file that cannot be read is refused, naming the file")
    $did = @(Invoke-HordeWakeTick -Run $bad -Now (At 0) -Waker $memory -ReadSessions $none -HordeHome $h)
    Check (@(Get-HordeMemoryWakerAsks).Count -eq 0 -and @(Get-HordeMemoryWakerReads).Count -eq 0 -and @($did | Where-Object { $_.kind -ceq "skip-unknown" -and $_.id -ceq "pass" -and "$($_.reason)".Contains("was refused") }).Count -eq 1) ("and a tick handed that run nudges nobody: an unreadable ledger is never read as an empty one by a run that sends")
    Check ([System.IO.File]::ReadAllText((Join-Path $h "wake\ledger-live.json")) -ceq "{ not json") "the file is left as it was, for a person to mend"
}
$h = New-Home
New-Item -ItemType Directory -Path (Join-Path $h "wake") -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $h "wake\ledger-shadow.json"), "{ not json")
$soft = New-HordeWakeRun -HordeHome $h
Check ("$($soft.refused)" -ceq "" -and @($soft.said | Where-Object { "$_".Contains("starting from an empty ledger") }).Count -eq 1) "a shadow run over an unreadable ledger starts from empty and says so: it sends nothing"
Check ("$((New-HordeWakeRun -Mode "live" -HordeHome (New-Home)).refused)" -ceq "") "CONTROL: a run that sends, with no ledger file at all, is not refused: absent is not unreadable"

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
Check (@($failed | Where-Object { $_.kind -ceq "skip-unknown" -and $_.id -ceq "ledger" -and "$($_.reason)".Contains("the ledger could not be saved") }).Count -eq 1) "a ledger that cannot be saved is an entry saying so"
Check ($run.ledger.Count -eq 1) "and what the pass counted is kept in the running watcher all the same"
Check ((Read-HordeWakeHeartbeat -Shadow -HordeHome $h).value.pass -eq 1) "and the heartbeat is still written: the watcher is alive"
$next = @(Invoke-HordeWakeTick -Run $run -Now (At 3) -Waker $memory -ReadSessions $none -HordeHome $h)
Check (@($next | Where-Object { $_.id -ceq "ledger" -or $_.id -ceq "pass" }).Count -eq 0 -and (Read-HordeWakeHeartbeat -Shadow -HordeHome $h).value.pass -eq 2) "the next tick runs, and does not journal the same failure again"

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
Check (($names -join ",") -ceq "heartbeat-live.json,journal-live.jsonl,ledger-live.json,restore-of-live-run-shadow.json,silence-live.json") ("it wrote the live run's own journal, heartbeat and ledger, and kept what the source would have posted in a shadow file of its own - never restore-live.json, which is for mail really posted (" + ($names -join ",") + ")")
$beat = Read-HordeWakeHeartbeat -Mode "live" -HordeHome $h
Check ($beat.state -ceq "known" -and $beat.value.shadow -eq $false -and $beat.value.pass -eq 2 -and (Read-HordeWakeHeartbeat -Shadow -HordeHome $h).state -ceq "absent") "its heartbeat is the live one, marked not shadow, and no shadow heartbeat was written"
# A SHADOW RUN BESIDE IT, on the same home: each keeps its own heartbeat and journal.
Reset-HordeMemoryWaker
$beside = New-HordeWakeRun -HordeHome $h
$null = Invoke-HordeWakeTick -Run $beside -Now (At 500) -Waker $memory -ReadSessions $none -TickSeconds 3 -ProcessId 4343 -HordeHome $h
Check ((Read-HordeWakeHeartbeat -Mode "live" -HordeHome $h).value.at -eq (At 3) -and (Read-HordeWakeHeartbeat -Shadow -HordeHome $h).value.at -eq (At 500)) "a shadow run ticking on the same home leaves the live heartbeat as it was: a live watcher that died is not made to look alive"
Check (@(Read-HordeWakeJournalTail -Mode "live" -Count 1000 -HordeHome $h | ForEach-Object { ($_ | ConvertFrom-Json).kind } | Where-Object { $_ -cnotlike "would-*" -and $_ -cne "nudge" }).Count -eq 0 -and @(Read-HordeWakeJournalTail -Mode "live" -Count 1000 -HordeHome $h).Count -eq $kinds.Count) "and the live journal holds only the live run's lines"
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
Check (($names -join ",") -ceq "heartbeat-proof.json,journal-proof.jsonl,ledger-live.json,restore-of-proof-run-shadow.json,silence-live.json") ("it wrote the proof run's own journal and heartbeat, and counted its nudge in the ONE ledger the sending runs share - no ledger of its own (" + ($names -join ",") + ")")
$beat = Read-HordeWakeHeartbeat -Mode "proof" -HordeHome $h
Check ($beat.state -ceq "known" -and $beat.value.mode -ceq "proof" -and $beat.value.shadow -eq $false -and (Read-HordeWakeHeartbeat -Mode "live" -HordeHome $h).state -ceq "absent" -and (Read-HordeWakeHeartbeat -Shadow -HordeHome $h).state -ceq "absent") "its heartbeat says proof, and neither the live nor the shadow heartbeat was written: a proof pass does not make a live watcher look alive"
$switchWas = $script:HordeWakeSendersPost
try { $script:HordeWakeSendersPost = $true; Check ((Test-HordeWakeSendersShadow -Run $proof) -eq $true -and (Test-HordeWakeSendersShadow -Run (New-HordeWakeRun -Mode "live" -HordeHome $h)) -eq $false) "with the senders' switch on, a live run posts and a proof run still does not" } finally { $script:HordeWakeSendersPost = $switchWas }
$threw = $false; try { $null = New-HordeWakeRun -Mode "LIVE" -HordeHome $h } catch { $threw = $true }
Check $threw "a run cannot be made in a mode that is no mode"
$lockP = Enter-HordeWakeLock -Mode "proof" -ProcessId 1 -HordeHome $h
# Caught on purpose: a lock that threw for a second holder must fail this check, not end the suite.
$secondP = "threw"
try { $secondP = Enter-HordeWakeLock -Mode "proof" -ProcessId 2 -HordeHome $h } catch { $secondP = "threw" }
try { Check ($null -ne $lockP -and (Test-Path -LiteralPath (Join-Path $h "wake\run-live.lock")) -and -not (Test-Path -LiteralPath (Join-Path $h "wake\run-proof.lock")) -and $null -eq $secondP) "a proof run holds the sending runs' one lock, and a second proof run is kept out" } finally { if ($null -ne $lockP) { $lockP.Dispose() }; if ($null -ne $secondP -and $secondP -isnot [string]) { $secondP.Dispose() } }
# A RUN THAT SENDS RUNS ONLY A PROGRAM A PERSON NAMED: one the waker merely found is refused.
$script:whence = { New-HordeKnown -Value ([pscustomobject]@{ fixed = $false; how = "the command is in the folder found from the command on PATH, X:\somewhere\tool.cmd" }) }
$found = Register-HordeWaker -Name "fixture-source" -Folder (Join-Path $root "test\fixtures\waker\caps\fixture-source") -Targets { New-HordeKnown -Value @() } -State { param($id) New-HordeUnknown -Reason "a fixture" } -Nudge { param($id) New-HordeUnknown -Reason "a fixture" } -Source { & $script:whence }
$foundPick = New-HordeKnown -Value $found
$p = Get-HordeWakeRunPlan -Mode "live" -Picked $foundPick
Check ($p.ok -eq $false -and $p.usage -eq $false -and $p.live -eq $false -and $null -eq $p.waker -and "$($p.reason)".Contains("was not named in a setting") -and "$($p.reason)".Contains("found from the command on PATH")) "a live run through a waker whose program was only found on PATH is refused, saying where it was found"
$p = Get-HordeWakeRunPlan -Mode "proof" -Once -Target (Sid 3) -Picked $foundPick
Check ($p.ok -eq $false -and $p.live -eq $false -and $null -eq $p.waker -and "$($p.reason)".Contains("was not named in a setting")) "and so is a proof run: it types too"
$p = Get-HordeWakeRunPlan -Picked $foundPick
Check ($p.ok -and $p.live -eq $false -and [object]::ReferenceEquals($p.waker, $found) -and "$($p.banner)".StartsWith("SHADOW - ") -and "$($p.banner)".Contains("NOT NAMED IN A SETTING") -and "$($p.banner)".Contains("found from the command on PATH")) "a shadow run may read through it, and its banner says the program was not named and where it was found"
$script:whence = { New-HordeKnown -Value ([pscustomobject]@{ fixed = $true; how = "the command is in the folder set as root in a settings file" }) }
$p = Get-HordeWakeRunPlan -Mode "live" -Picked $foundPick
Check ($p.ok -and $p.live -eq $true -and -not "$((Get-HordeWakeRunPlan -Picked $foundPick).banner)".Contains("NOT NAMED")) "named in a setting, the same waker may send, and the shadow banner has nothing to say of it"
$script:whence = { New-HordeUnknown -Reason "its settings are refused" }
$p = Get-HordeWakeRunPlan -Mode "live" -Picked $foundPick
Check ($p.ok -eq $false -and "$($p.reason)".Contains("could not say where its program comes from") -and (Get-HordeWakeRunPlan -Mode "proof" -Once -Target (Sid 3) -Picked $foundPick).ok -eq $false -and (Get-HordeWakeRunPlan -Picked $foundPick).ok) "a waker that cannot say where its program is may be read through in shadow and is refused for a run that sends"
$script:HordeWakers.Remove("fixture-source")
# A RUN IS SHADOW UNLESS IT IS MADE OTHERWISE, at every level it is made at.
$hs = New-Home
Check ((New-HordeWakeRun -HordeHome $hs).mode -ceq "shadow" -and (New-HordeWakeRun -Mode "" -HordeHome $hs).mode -ceq "shadow" -and (New-HordeWakeRun -Live:$false -HordeHome $hs).live -eq $false -and (New-HordeWakeRun -Live -HordeHome $hs).mode -ceq "live" -and (Get-HordeWakeRunPlan -Picked $one).mode -ceq "shadow") "a run made with no word, an empty mode or -Live:false is shadow, and so is a plan made with none"
# ONE LOCK AND ONE LEDGER FOR THE RUNS THAT SEND.
$h = New-Home
$heldLive = Enter-HordeWakeLock -Mode "live" -ProcessId 1 -HordeHome $h
$tryProof = "threw"; try { $tryProof = Enter-HordeWakeLock -Mode "proof" -ProcessId 2 -HordeHome $h } catch { $tryProof = "threw" }
$tryShadow = "threw"; try { $tryShadow = Enter-HordeWakeLock -ProcessId 3 -HordeHome $h } catch { $tryShadow = "threw" }
try { Check ($null -ne $heldLive -and $null -eq $tryProof -and $null -ne $tryShadow -and $tryShadow -isnot [string]) "while a live run holds its lock a proof run is kept out, and a shadow run is not" } finally { foreach ($l in @($heldLive, $tryProof, $tryShadow)) { if ($null -ne $l -and $l -isnot [string]) { $l.Dispose() } } }
$heldProof = Enter-HordeWakeLock -Mode "proof" -ProcessId 1 -HordeHome $h
$tryLive = "threw"; try { $tryLive = Enter-HordeWakeLock -Mode "live" -ProcessId 2 -HordeHome $h } catch { $tryLive = "threw" }
try { Check ($null -ne $heldProof -and $null -eq $tryLive) "and while a proof run holds it a live run is kept out: two runs never send at once" } finally { foreach ($l in @($heldProof, $tryLive)) { if ($null -ne $l -and $l -isnot [string]) { $l.Dispose() } } }
Check ((Get-HordeWakeSendWord -Mode "proof") -ceq "live" -and (Get-HordeWakeSendWord -Mode "live") -ceq "live" -and (Get-HordeWakeSendWord -Mode "shadow") -ceq "shadow" -and (Get-HordeWakeSendWord) -ceq "shadow") "the sending runs share the word live for their lock and their ledger; shadow, and a caller that names no mode, have shadow's"
# THE BUDGET IS ONE: what a live run counted against a session, a proof run starts from, and adds to.
$h = New-Home
Reset-HordeMemoryWaker
Set-HordeMemoryWakerSession -Id (Sid 1) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60)
Set-HordeMemoryWakerSession -Id (Sid 2) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60)
$liveRun = New-HordeWakeRun -Mode "live" -HordeHome $h
foreach ($n in 0..1) { Set-HordeMemoryWakerClock (At ($n * 3)); $null = Invoke-HordeWakeTick -Run $liveRun -Now (At ($n * 3)) -Waker $memory -ReadSessions $none -HordeHome $h }
Check (@(Get-HordeMemoryWakerAsks).Count -eq 2) "CONTROL: a live run nudged both sessions once"
$after = New-HordeWakeRun -Mode "proof" -Target (Sid 1) -HordeHome $h
Check ($after.ledger.Count -eq 2 -and $after.ledger[(Sid 1)].attempts -eq 1) "a proof run made afterwards starts from the ledger the live run wrote: the session's one attempt is already counted"
Set-HordeMemoryWakerClock (At 7)
$did = @(Invoke-HordeWakeTick -Run $after -Now (At 7) -Waker $memory -ReadSessions $none -HordeHome $h | ForEach-Object { $_.kind })
Check (@(Get-HordeMemoryWakerAsks).Count -eq 3 -and $after.ledger[(Sid 1)].attempts -eq 2) "its nudge is the session's second, not a first out of a budget of its own"
$backLive = New-HordeWakeRun -Mode "live" -HordeHome $h
Check ($backLive.ledger[(Sid 1)].attempts -eq 2 -and $backLive.ledger[(Sid 2)].attempts -eq 1 -and -not (Test-Path -LiteralPath (Join-Path $h "wake\ledger-proof.json"))) "and a live run started after it reads both: the proof wrote the same ledger, kept the other session's entry, and made no ledger of its own"
$backProof = New-HordeWakeRun -Mode "proof" -Target (Sid 1) -HordeHome $h
Set-HordeMemoryWakerClock (At 9)
$null = Invoke-HordeWakeTick -Run $backProof -Now (At 9) -Waker $memory -ReadSessions $none -HordeHome $h
Check (@(Get-HordeMemoryWakerAsks).Count -eq 3) "a proof repeated two seconds later is held by the back-off the first one left: proofs cannot be used to hammer a session"
# A PROOF SENDS NO PROBE, however old the ledger it reads: a limited session is not typed into because an hour has passed.
$h = New-Home
Reset-HordeMemoryWaker
Set-HordeMemoryWakerSession -Id (Sid 1) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60) -Limited "yes"
$first = New-HordeWakeRun -Mode "proof" -Target (Sid 1) -HordeHome $h
Set-HordeMemoryWakerClock (At 0)
$null = Invoke-HordeWakeTick -Run $first -Now (At 0) -Waker $memory -ReadSessions $none -HordeHome $h
$second = New-HordeWakeRun -Mode "proof" -Target (Sid 1) -HordeHome $h
Set-HordeMemoryWakerClock (At 7200)
$late = @(Invoke-HordeWakeTick -Run $second -Now (At 7200) -Waker $memory -ReadSessions $none -HordeHome $h)
Check (@(Get-HordeMemoryWakerAsks).Count -eq 0 -and $second.ledger.ContainsKey((Sid 1))) ("a second proof two hours after the first, aimed at a session limited with no known end, types nothing: the hourly probe is the watcher's, never a proof's (" + (@($late | ForEach-Object { $_.kind }) -join ",") + ")")
$liveLate = New-HordeWakeRun -Mode "live" -HordeHome $h
Set-HordeMemoryWakerClock (At 7203)
$null = Invoke-HordeWakeTick -Run $liveLate -Now (At 7203) -Waker $memory -ReadSessions $none -HordeHome $h
Check (@(Get-HordeMemoryWakerAsks).Count -eq 1) "CONTROL: a live run at that moment does send the probe that is due"
Reset-HordeMemoryWaker
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
$live = Enter-HordeWakeLock -Mode "live" -ProcessId 4244 -HordeHome $h
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
