# DOES A HEARTBEAT SAY WHO WROTE IT AND WHEN, AND IS "STALE" COMPUTED FROM THE WRITER'S OWN TICK?
#
# core/Heartbeat.ps1. Everything is written under a folder this suite makes in temp and removes; the
# clock is a value the suite passes, never the machine's.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\Heartbeat.ps1")

$work = Join-Path $env:TEMP ("horde-heartbeat-" + [guid]::NewGuid().ToString("N"))
[void][System.IO.Directory]::CreateDirectory($work)
$t0 = [datetime]::new(2026, 10, 13, 12, 0, 0, [System.DateTimeKind]::Utc)
$born = [datetime]::new(2026, 10, 13, 11, 0, 0, 123, [System.DateTimeKind]::Utc).AddTicks(4567)

try {
    Write-Host ""
    Write-Host "--- stale is three of the writer's own ticks, never a constant ---" -ForegroundColor Cyan
    Check ((Get-HordeHeartbeatStaleSeconds -TickSeconds 60) -eq 180) "a writer that beats every 60 s is stale after 180 s"
    Check ((Get-HordeHeartbeatStaleSeconds -TickSeconds 1200) -eq 3600) "one that beats every 20 minutes is stale after an hour, not after two minutes"
    Check ((Get-HordeHeartbeatStaleSeconds -TickSeconds 1) -eq 30) "a very short tick is held to the floor of 30 s"
    Check ((Get-HordeHeartbeatStaleSeconds -TickSeconds 0) -eq 30 -and (Get-HordeHeartbeatStaleSeconds -TickSeconds -5) -eq 30) "a writer that names no tick, or a nonsense one, gets the floor alone"
    Check ((Get-HordeHeartbeatStaleSeconds -TickSeconds 10 -FloorSeconds 120) -eq 120) "a caller may ask for a higher floor"

    Write-Host ""
    Write-Host "--- written whole, read back the same ---" -ForegroundColor Cyan
    $path = Join-Path $work "sub\beat.json"
    Write-HordeHeartbeat -Path $path -At $t0 -ProcessId 4242 -ProcessStartedAt $born -TickSeconds 97 -Pass 7
    $read = Read-HordeHeartbeat -Path $path
    Check ($read.state -ceq "known" -and $read.value.pid -eq 4242 -and $read.value.tickSeconds -eq 97 -and $read.value.pass -eq 7) "the pid, the tick and the pass come back"
    Check ($read.value.at -eq $t0 -and $read.value.at.Kind -eq [System.DateTimeKind]::Utc) "the time comes back as the same instant, in UTC"
    Check ($read.value.startedAt.Ticks -eq $born.Ticks) "the process's start comes back to the tick: it is half of the identity"
    Check (@(Get-ChildItem -LiteralPath (Join-Path $work "sub")).Count -eq 1) "nothing is left beside it: the temporary file became the heartbeat"
    Write-HordeHeartbeat -Path $path -At $t0.AddSeconds(5) -ProcessId 4242 -ProcessStartedAt $born -TickSeconds 97 -Pass 8
    Check ((Read-HordeHeartbeat -Path $path).value.pass -eq 8) "a second beat replaces the first"
    Check (Throws { Write-HordeHeartbeat -Path "relative\beat.json" -At $t0 -ProcessId 1 -TickSeconds 1 } "absolute path") "a relative path is refused: where it would land depends on the current folder"

    Write-Host ""
    Write-Host "--- absent, unknown and known are told apart ---" -ForegroundColor Cyan
    Check ((Read-HordeHeartbeat -Path (Join-Path $work "none.json")).state -ceq "absent") "no file is absent: it has never run here"
    $bad = Join-Path $work "bad.json"
    [System.IO.File]::WriteAllText($bad, "{ not json")
    Check ((Read-HordeHeartbeat -Path $bad).state -ceq "unknown") "a file that is not JSON is unknown, with a reason"
    [System.IO.File]::WriteAllText($bad, '{ "pid": 5, "tickSeconds": 3 }')
    Check ((Read-HordeHeartbeat -Path $bad).reason -like "*no time*") "a heartbeat with no time is unknown"
    [System.IO.File]::WriteAllText($bad, '{ "at": "2026-10-13T12:00:00", "pid": 5 }')
    Check ((Read-HordeHeartbeat -Path $bad).state -ceq "unknown") "a time with no zone is not a time: it cannot be placed"
    [System.IO.File]::WriteAllText($bad, '{ "at": "2026-10-13T12:00:00Z" }')
    Check ((Read-HordeHeartbeat -Path $bad).reason -like "*names no process*") "a heartbeat that names no process is unknown"
    [System.IO.File]::WriteAllText($bad, '{ "at": "2026-10-13T12:00:00Z", "pid": 5 }')
    $bare = Read-HordeHeartbeat -Path $bad
    Check ($bare.state -ceq "known" -and $null -eq $bare.value.startedAt -and $bare.value.tickSeconds -eq 0) "one with a time and a pid and nothing else is known, its start and tick left unsaid"
    [System.IO.File]::WriteAllText($bad, ("x" * 5000))
    Check ((Read-HordeHeartbeat -Path $bad).reason -like "*more than a heartbeat*") "a file far larger than a heartbeat is refused unread"
    [System.IO.File]::WriteAllText($bad, '[1, 2]')
    Check ((Read-HordeHeartbeat -Path $bad).state -ceq "unknown") "a list is not a heartbeat"

    Write-Host ""
    Write-Host "--- the verdict, with a clock the suite holds ---" -ForegroundColor Cyan
    $beat = Read-HordeHeartbeat -Path $path
    $at = $beat.value.at
    $v = Get-HordeHeartbeatVerdict -Heartbeat $beat -Now $at.AddSeconds(291)
    Check ($v.state -ceq "known" -and $v.value.fresh -and $v.value.ageSeconds -eq 291 -and $v.value.staleAfterSeconds -eq 291 -and $v.value.tickSeconds -eq 97) "at exactly three ticks it is still fresh"
    Check (-not (Get-HordeHeartbeatVerdict -Heartbeat $beat -Now $at.AddSeconds(292)).value.fresh) "one second later it is stale"
    Check ((Get-HordeHeartbeatVerdict -Heartbeat $bare -Now ([datetime]::new(2026, 10, 13, 12, 5, 0, [System.DateTimeKind]::Utc)) -DefaultTickSeconds 200).value.fresh) "a heartbeat that names no tick is judged by the tick its reader was told to expect"
    Check (-not (Get-HordeHeartbeatVerdict -Heartbeat $bare -Now ([datetime]::new(2026, 10, 13, 12, 5, 0, [System.DateTimeKind]::Utc))).value.fresh) "CONTROL: with no tick from either, the floor decides, and five minutes is stale"
    Check ((Get-HordeHeartbeatVerdict -Heartbeat $beat -Now $at.AddSeconds(-10)).value.ageSeconds -eq 0) "a heartbeat a few seconds ahead of the clock reads as just written"
    $future = Get-HordeHeartbeatVerdict -Heartbeat $beat -Now $at.AddSeconds(-1000)
    Check ($future.state -ceq "unknown" -and $future.reason -like "*in the future*") "one far in the future is unknown: read as fresh it would keep a dead writer alive until the clock caught up"
    Check ((Get-HordeHeartbeatVerdict -Heartbeat (New-HordeAbsent -Note "never") -Now $t0).state -ceq "absent") "an absent heartbeat stays absent"
    Check ((Get-HordeHeartbeatVerdict -Heartbeat (New-HordeUnknown -Reason "held") -Now $t0).reason -ceq "held") "an unknown one stays unknown, with its reason"
    Check (Throws { Get-HordeHeartbeatVerdict -Heartbeat "fresh" -Now $t0 } "not a Horde answer") "something that is not an answer is refused"

    Write-Host ""
    Write-Host "--- a pid alone is not an identity ---" -ForegroundColor Cyan
    Check (Test-HordeHeartbeatSameStart -One $born -Other $born.AddMilliseconds(900)) "two readings of one start within a second are the same process"
    Check (-not (Test-HordeHeartbeatSameStart -One $born -Other $born.AddSeconds(2))) "two seconds apart they are not"
    Check (-not (Test-HordeHeartbeatSameStart -One $born -Other $null) -and -not (Test-HordeHeartbeatSameStart -One $null -Other $null)) "a missing start is never the same: the pid alone would be deciding"
    $self = Get-HordeHeartbeatSelf
    $mine = [System.Diagnostics.Process]::GetCurrentProcess()
    Check ($self.pid -eq $PID -and $self.startedAt -is [datetime] -and $self.startedAt.Ticks -eq $mine.StartTime.ToUniversalTime().Ticks) "this process names itself by its pid and its own start"
    $mine.Dispose()

    Write-Host ""
    Write-Host "--- the quiet write never throws ---" -ForegroundColor Cyan
    $blocked = Join-Path $work "afile"
    [System.IO.File]::WriteAllText($blocked, "x")
    $q = Write-HordeHeartbeatQuietly -Path (Join-Path $blocked "beat.json") -At $t0 -ProcessId 1 -TickSeconds 1
    Check ($q.state -ceq "unknown" -and $q.reason -like "the heartbeat could not be written*") "a heartbeat that cannot be written is an unknown with the reason, not an error"
    $q2 = Write-HordeHeartbeatQuietly -Path (Join-Path $work "quiet.json") -At $t0 -ProcessId 1 -ProcessStartedAt $born -TickSeconds 1
    Check ($q2.state -ceq "known" -and (Read-HordeHeartbeat -Path (Join-Path $work "quiet.json")).state -ceq "known") "and one that can be is written"
    Check (Throws { Write-HordeHeartbeat -Path (Join-Path $blocked "beat.json") -At $t0 -ProcessId 1 -TickSeconds 1 }) "CONTROL: the plain write does throw there"
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "a heartbeat names its writer by pid and start, reads back exactly, and is stale by its own tick"
