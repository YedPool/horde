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
Check (@($said[0]).Count -eq 0 -and (@($said[1]) -join ",") -ceq "bad-mail" -and @($said[2]).Count -eq 0 -and @($said[3]).Count -eq 0) "a session whose mailbox holds records nobody can read is journaled bad-mail once, on the second tick that shows it, and not again"

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
Check (($names -join ",") -ceq "heartbeat.json,journal.jsonl,ledger.json,restore-of-live-run-shadow.json") ("it wrote the live run's own journal, heartbeat and ledger, and kept what the source would have posted in a shadow file of its own - never restore.json, which is for mail really posted (" + ($names -join ",") + ")")
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
Write-Host "--- how a run starts: shadow unless live is asked for, and live only with a waker ---" -ForegroundColor Cyan

$none5 = New-HordeAbsent -Note "no loaded waker offers every capability"
$one = New-HordeKnown -Value $memory
$p = Get-HordeWakeRunPlan -Picked $one
Check ($p.ok -and $p.live -eq $false -and [object]::ReferenceEquals($p.waker, $memory) -and "$($p.banner)".StartsWith("SHADOW - ")) "with no word the run is shadow, reads through the installed waker, and its banner begins SHADOW"
$p = Get-HordeWakeRunPlan -Picked $none5
Check ($p.ok -and $p.live -eq $false -and $null -eq $p.waker -and "$($p.banner)".StartsWith("SHADOW - ") -and "$($p.banner)".Contains("No waker is installed")) "a shadow run with no waker still starts, and says in its banner that none is installed"
$p = Get-HordeWakeRunPlan -Live -Picked $one
Check ($p.ok -and $p.live -eq $true -and [object]::ReferenceEquals($p.waker, $memory) -and "$($p.banner)".StartsWith("LIVE - REAL NUDGES") -and "$($p.banner)".Contains("restore source stays shadow")) "asked for by name, with a waker, the run is live, and its banner begins LIVE and says the restore source stays shadow"
# Caught on purpose: a plan that went on with no waker would throw reading its name, and a throw must
# fail this check rather than end it.
$p = $null
try { $p = Get-HordeWakeRunPlan -Live -Picked $none5 } catch { $p = $null }
Check ($null -ne $p -and $p.ok -eq $false -and $p.live -eq $false -and $null -eq $p.waker -and "$($p.reason)".Contains("needs an installed waker") -and "$($p.reason)".Contains("no loaded waker offers")) "a live run with no waker installed is refused, saying why"
$p = Get-HordeWakeRunPlan -Live -Picked (New-HordeUnknown -Reason "2 wakers each offer every capability")
Check ($p.ok -eq $false -and "$($p.reason)".Contains("2 wakers")) "and so is one when two wakers could be picked: one is never chosen"
$p = Get-HordeWakeRunPlan -Live -Picked "not an answer"
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
