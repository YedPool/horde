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
function Read-Lines { param([string]$HordeHome) return @(Read-HordeWakeJournalTail -Count 1000 -HordeHome $HordeHome | ForEach-Object { $_ | ConvertFrom-Json }) }
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
$run = New-HordeWakeShadowRun -HordeHome $h
Check ($run.pass -eq 0 -and $run.ledger.Count -eq 0 -and @($run.said).Count -eq 0) "CONTROL: a run in a new home starts from nothing, with nothing to say"
$kinds = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt 20; $i++) {
    Set-HordeMemoryWakerClock (At ($i * 3))
    foreach ($e in @(Invoke-HordeWakeShadowTick -Run $run -Now (At ($i * 3)) -Waker $memory -ReadSessions $readRestored -TickSeconds 3 -ProcessId 4242 -HordeHome $h)) { [void]$kinds.Add($e.kind) }
}
Check (@(Get-HordeMemoryWakerAsks).Count -eq 0) "twenty ticks over six sessions that qualify ask the waker for no nudge at all"
Check (@($kinds | Where-Object { $_ -cnotlike "would-*" }).Count -eq 0 -and @($kinds | Where-Object { $_ -ceq "would-nudge" }).Count -ge 6 -and @($kinds | Where-Object { $_ -ceq "would-post" }).Count -eq 6 -and @($kinds | Where-Object { $_ -ceq "would-stall" }).Count -eq 1) ("every entry says would: a would-nudge for each session, one would-post for each restored orc, one would-stall (" + (@($kinds | Group-Object | ForEach-Object { $_.Name + " x" + $_.Count }) -join ", ") + ")")
$names = @(Get-ChildItem -LiteralPath (Join-Path $h "wake") | ForEach-Object { $_.Name } | Sort-Object)
Check (($names -join ",") -ceq "heartbeat.json,journal.jsonl,ledger-shadow.json,restore-shadow.json") ("it wrote the journal, the heartbeat and the shadow run's own state, and never the live ledger.json or restore.json (" + ($names -join ",") + ")")
Check (@(Read-Lines $h).Count -eq $kinds.Count) "what a tick returns is what it journaled"
$beat = Read-HordeWakeHeartbeat -HordeHome $h
Check ($beat.state -ceq "known" -and $beat.value.pass -eq 20 -and $beat.value.shadow -eq $true -and $beat.value.tickSeconds -eq 3 -and $beat.value.pid -eq 4242 -and $beat.value.at -eq (At 57)) "the heartbeat is the last tick's: its pass, its time, shadow, the tick and the process"
Check ($script:reads -eq 2) ("the restore source ran beside the wake pass every 30 s, not every tick: twice in 57 s (" + $script:reads + ")")
$again = New-HordeWakeShadowRun -HordeHome $h
Check ($again.ledger.Count -eq 6 -and $again.posted.Count -eq 7 -and @($again.restores).Count -eq 1) "a run that starts again reads back the shadow run's ledger, what it would have posted, and the restore it found"

Write-Host ""
Write-Host "--- a tick never throws: what fails is journaled once, and the next tick runs ---" -ForegroundColor Cyan

$h = New-Home
Reset-HordeMemoryWaker
$run = New-HordeWakeShadowRun -HordeHome $h
$boom = { throw "the process table could not be read" }
$first = @(Invoke-HordeWakeShadowTick -Run $run -Now (At 0) -Waker $memory -ReadSessions $boom -HordeHome $h)
Check ($first.Count -eq 1 -and $first[0].kind -ceq "skip-unknown" -and $first[0].id -ceq "restore" -and "$($first[0].reason)".Contains("could not be read")) "a reader of the sessions that throws is an entry saying so, not a throw of the tick"
$more = @(); foreach ($s in @(3, 6, 30, 33)) { $more += @(Invoke-HordeWakeShadowTick -Run $run -Now (At $s) -Waker $memory -ReadSessions $boom -HordeHome $h) }
Check ($more.Count -eq 0 -and $run.pass -eq 5) "it is journaled once while it lasts - across the next reading too - and every tick still ran"
$mended = @(Invoke-HordeWakeShadowTick -Run $run -Now (At 60) -Waker $memory -ReadSessions { New-HordeUnknown -Reason "no agent's listing is whole" } -HordeHome $h)
Check ($mended.Count -eq 1 -and "$($mended[0].reason)".Contains("no agent's listing is whole")) "a new reason is journaled when it changes"
$odd = @(Invoke-HordeWakeShadowTick -Run $run -Now (At 90) -Waker $memory -ReadSessions { "not an answer" } -HordeHome $h)
Check ($odd.Count -eq 1 -and "$($odd[0].reason)".Contains("not an answer")) "and a reader that answers rubbish is unknown, with the reason"

# THE WAKE PASS FAILS: its ledger cannot be saved, because a folder stands where the file belongs.
$h = New-Home
Reset-HordeMemoryWaker
Set-HordeMemoryWakerSession -Id (Sid 1) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60)
New-Item -ItemType Directory -Path (Join-Path $h "wake\ledger-shadow.json") -Force | Out-Null
$run = New-HordeWakeShadowRun -HordeHome $h
$none = { $a = New-HordeKnown -Value @(); Add-Member -InputObject $a -MemberType NoteProperty -Name "leftOut" -Value @(); $a }
$failed = @(Invoke-HordeWakeShadowTick -Run $run -Now (At 0) -Waker $memory -ReadSessions $none -HordeHome $h)
Check (@($failed | Where-Object { $_.kind -ceq "skip-unknown" -and $_.id -ceq "pass" -and "$($_.reason)".Contains("the wake pass failed") }).Count -eq 1) "a wake pass that throws is an entry saying so"
Check ((Read-HordeWakeHeartbeat -HordeHome $h).value.pass -eq 1) "and the heartbeat is still written: the watcher is alive"
$next = @(Invoke-HordeWakeShadowTick -Run $run -Now (At 3) -Waker $memory -ReadSessions $none -HordeHome $h)
Check (@($next | Where-Object { $_.id -ceq "pass" }).Count -eq 0 -and (Read-HordeWakeHeartbeat -HordeHome $h).value.pass -eq 2) "the next tick runs, and does not journal the same failure again"

# THE HEARTBEAT FAILS: a folder stands where it belongs.
$h = New-Home
Reset-HordeMemoryWaker
New-Item -ItemType Directory -Path (Join-Path $h "wake\heartbeat.json") -Force | Out-Null
$run = New-HordeWakeShadowRun -HordeHome $h
$failed = @(Invoke-HordeWakeShadowTick -Run $run -Now (At 0) -Waker $memory -ReadSessions $none -HordeHome $h)
Check (@($failed | Where-Object { $_.id -ceq "heartbeat" -and "$($_.reason)".Contains("could not be written") }).Count -eq 1) "a heartbeat that cannot be written is an entry saying so, not the end of the watcher"
$next = @(Invoke-HordeWakeShadowTick -Run $run -Now (At 3) -Waker $memory -ReadSessions $none -HordeHome $h)
Check ($next.Count -eq 0 -and $run.pass -eq 2 -and @(Read-Lines $h).Count -eq 1) "and the loop goes on, the failure journaled once"

# THE JOURNAL FAILS: a folder stands where it belongs. The tick hands back what it could not write.
$h = New-Home
New-Item -ItemType Directory -Path (Join-Path $h "wake\journal.jsonl") -Force | Out-Null
$run = New-HordeWakeShadowRun -HordeHome $h
$failed = @(Invoke-HordeWakeShadowTick -Run $run -Now (At 0) -Waker $null -ReadSessions $boom -HordeHome $h)
Check (@($failed | Where-Object { $_.id -ceq "journal" }).Count -eq 1 -and @($failed | Where-Object { $_.id -ceq "restore" }).Count -eq 1) "a journal that cannot be written is handed back with the entries it lost, for the caller to print"

# A SAVED FILE THAT CANNOT BE READ: the run starts from empty and says so.
$h = New-Home
New-Item -ItemType Directory -Path (Join-Path $h "wake") | Out-Null
[System.IO.File]::WriteAllText((Join-Path $h "wake\ledger-shadow.json"), "{ not json")
[System.IO.File]::WriteAllText((Join-Path $h "wake\restore-shadow.json"), "{ not json")
$run = New-HordeWakeShadowRun -HordeHome $h
Check ($run.ledger.Count -eq 0 -and @($run.said).Count -eq 2 -and "$($run.said[0])".Contains("empty ledger") -and "$($run.said[1])".Contains("no mail marked posted")) "a run whose saved state cannot be read starts from empty, and has two things to say"

Write-Host ""
Write-Host "--- one run a home and a mode: a lock that is a held file, not a pid ---" -ForegroundColor Cyan

$h = New-Home
$lock = Enter-HordeWakeLock -Shadow -ProcessId 4242 -HordeHome $h
Check ($null -ne $lock) "the first run takes the lock"
$second = Enter-HordeWakeLock -Shadow -ProcessId 4243 -HordeHome $h
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

} finally {
    Reset-HordeMemoryWaker
    [System.GC]::Collect()
    Exit-HordeTestPinnedHome -State $pinned
    Exit-HordeTestEmptyFleet -Pin $fleetPin
}

Complete-HordeSuite -Success "a shadow tick rings nobody, posts nothing, survives what its parts throw, and only one run holds a home"
