# CAN A SHADOW WAKE RUN REACH A NUDGE AT ALL? (T-0116)
#
# A shadow run used to be handed the REAL waker, and the only thing between it and a keystroke in a live
# session was one runtime branch in core/Wake.ps1 (the would-nudge branch of Invoke-HordeWakePass). Now the
# tick hands the pass a waker with no nudge in it (wakers/Port.ps1, Get-HordeWakerReadOnly), and the
# branch is the second guard. Driven through the real plan and the real tick, with a waker whose nudge
# RECORDS every call, and with the pass itself watched for the waker it is handed:
#   - A SHADOW TICK REACHES NO NUDGE EVEN WITH THE BRANCH GONE: test\mutations\wake-shadow-nudge.psd1
#     takes the branch out and this suite must still see no call (declared as a survivor, with its reason).
#   - A SHADOW TICK IS HANDED A WAKER WITH NO NUDGE, and still reads state through it.
#   - A PROOF AND A LIVE TICK ARE HANDED THE REAL WAKER, nudge and all: a proof nudges only its target.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "test\lib\FleetPin.ps1")
. (Join-Path $root "test\lib\MessengerPins.ps1")
$fleetPin = Enter-HordeTestEmptyFleet
$pinned = Enter-HordeTestPinnedHome -Root $root
. (Join-Path $root "core\WakeRun.ps1")
. (Join-Path $root "wakers\memory\Waker.ps1")

$memory = Get-HordeWaker -Name "memory"
$t0 = New-Object System.DateTime(2026, 10, 12, 8, 0, 0, [System.DateTimeKind]::Utc)
function At { param([double]$Seconds) return $t0.AddSeconds($Seconds) }
function Sid { param([int]$N) return ("0a000000-0000-4000-8000-" + $N.ToString("000000000000")) }
function New-Home { $h = Join-Path $pinned.home ("run-" + [guid]::NewGuid().ToString("N")); New-Item -ItemType Directory -Path $h | Out-Null; return $h }
$none = { $a = New-HordeKnown -Value @(); Add-Member -InputObject $a -MemberType NoteProperty -Name "leftOut" -Value @(); $a }

# THE PASS IS WATCHED: a wrapper with the pass's own parameters records the waker each call is handed,
# then runs the real pass. Made from the real function's metadata, so it cannot drift from it.
$script:handed = New-Object System.Collections.ArrayList
$script:realPass = (Get-Command -Name Invoke-HordeWakePass -CommandType Function).ScriptBlock
$passParams = [System.Management.Automation.ProxyCommand]::GetParamBlock((New-Object System.Management.Automation.CommandMetadata (Get-Command -Name Invoke-HordeWakePass -CommandType Function)))
Set-Item -Path "Function:\Invoke-HordeWakePass" -Value ([scriptblock]::Create("param(" + $passParams + ") [void]`$script:handed.Add(`$Waker); & `$script:realPass @PSBoundParameters"))

function Seat-Fleet {
    Reset-HordeMemoryWaker
    foreach ($n in 1..3) { Set-HordeMemoryWakerSession -Id (Sid $n) -Role "orc" -UnreadCount 1 -OldestUnreadAt (At -60) }
}

try {

Write-Host ""
Write-Host "--- a shadow run, from its plan through its ticks, is handed no nudge and asks for none ---" -ForegroundColor Cyan

$h = New-Home
Seat-Fleet
$plan = Get-HordeWakeRunPlan -Mode "shadow" -Picked (New-HordeKnown -Value $memory)
Check ($plan.ok -eq $true -and $plan.mode -ceq "shadow" -and $plan.live -eq $false) "CONTROL: the plan for a shadow run through the installed waker is ok, shadow, and not live"
$run = New-HordeWakeRun -Mode $plan.mode -Target $plan.target -Self "" -HordeHome $h
$script:handed.Clear()
for ($i = 0; $i -lt 10; $i++) {
    Set-HordeMemoryWakerClock (At ($i * 3))
    $null = Invoke-HordeWakeTick -Run $run -Now (At ($i * 3)) -Waker $plan.waker -ReadSessions $none -TickSeconds 3 -ProcessId 4242 -HordeHome $h
}
Check ($script:handed.Count -eq 10) ("CONTROL: the pass was watched on every one of ten ticks (" + $script:handed.Count + ")")
Check (@($script:handed | Where-Object { $null -ne $_ -and $null -ne $_.PSObject.Properties["nudge"] -and $null -eq $_.nudge }).Count -eq $script:handed.Count) "every shadow tick handed the pass a waker whose nudge is absent"
Check (@($script:handed | Where-Object { $null -ne $_ -and $null -ne $_.PSObject.Properties["exit"] -and $null -eq $_.exit }).Count -eq $script:handed.Count) "and a waker whose exit is absent too: a shadow run ends no session"
Check (@($script:handed | Where-Object { $_.name -ceq "memory" }).Count -eq $script:handed.Count) "and it is still the installed waker, by name, not another"
Check (@(Get-HordeMemoryWakerAsks).Count -eq 0) ("the waker's nudge was asked for nothing in ten ticks over three sessions with mail (" + @(Get-HordeMemoryWakerAsks).Count + ")")
# Not a count of journal lines, which the would-nudge branch shapes: the waker's own record of what it was asked to READ.
$reads = @(Get-HordeMemoryWakerReads)
$short = @(1..3 | Where-Object { $n = $_; @($reads | Where-Object { $_ -ceq (Sid $n) }).Count -lt 10 })
Check ($short.Count -eq 0) ("and the state was still read through the view: every session was read on every one of ten ticks (" + $reads.Count + " reads)")
# The port itself refuses the very waker the pass was handed, so a branch removed from the pass changes nothing.
$a = Send-HordeWakeNudge -Waker $script:handed[0] -Id (Sid 1)
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("without a nudge") -and @(Get-HordeMemoryWakerAsks).Count -eq 0) "and a nudge asked of that very waker through the port is refused, with the reason, and rings nobody"
Check ($null -ne $memory.nudge) "and the installed waker itself still has its nudge: the view is a copy, not an edit"

Write-Host ""
Write-Host "--- a proof run and a live run are handed the real waker, with its nudge ---" -ForegroundColor Cyan

$h = New-Home
Seat-Fleet
$run = New-HordeWakeRun -Mode "proof" -Target (Sid 2) -Self "" -HordeHome $h
$script:handed.Clear()
Set-HordeMemoryWakerClock (At 0)
$null = Invoke-HordeWakeTick -Run $run -Now (At 0) -Waker $memory -ReadSessions $none -TickSeconds 3 -ProcessId 4242 -HordeHome $h
Check ($script:handed.Count -eq 1 -and [object]::ReferenceEquals($script:handed[0], $memory) -and $script:handed[0].nudge -is [scriptblock]) "a proof tick is handed the very waker it was given, nudge and all"
Check ((@(Get-HordeMemoryWakerAsks) -join ",") -ceq (Sid 2)) ("and it nudges only its target (" + (@(Get-HordeMemoryWakerAsks) -join ",") + ")")

$h = New-Home
Seat-Fleet
$run = New-HordeWakeRun -Live -Self "" -HordeHome $h
$script:handed.Clear()
Set-HordeMemoryWakerClock (At 0)
$null = Invoke-HordeWakeTick -Run $run -Now (At 0) -Waker $memory -ReadSessions $none -TickSeconds 3 -ProcessId 4242 -HordeHome $h
Check ($script:handed.Count -eq 1 -and [object]::ReferenceEquals($script:handed[0], $memory) -and $script:handed[0].nudge -is [scriptblock]) "a live tick is handed the very waker it was given, nudge and all"
Check (@(Get-HordeMemoryWakerAsks).Count -ge 1) ("and it nudges: the sessions with mail were asked for (" + @(Get-HordeMemoryWakerAsks).Count + ")")

} finally {
    Reset-HordeMemoryWaker
    [System.GC]::Collect()
    Exit-HordeTestPinnedHome -State $pinned
    Exit-HordeTestEmptyFleet -Pin $fleetPin
}

Complete-HordeSuite -Success "a shadow run is handed a waker with no nudge and asks for none, while proof and live keep the real waker's"
