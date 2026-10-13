$HordeCommand = @{
    name    = "wake"
    group   = "wake"
    sustained = $true
    usage   = "wake run [-Shadow | -Live] [-Once] [-TickSeconds <n>] | wake status"
    summary = "run: the wake watcher - every pass it re-reads which sessions have unread mail and are idle with an empty input box, and after every session was started or restored together which orcs have not taken a turn since. SHADOW unless -Live is given: it writes what it would do to its journal and nudges and posts nothing. With -Live it sends real nudges through the installed waker; the restore source still only journals. status: for each mode, how long ago the watcher last ran, whether that is stale, and its last 10 journal lines"
    run     = {
        [CmdletBinding(DefaultParameterSetName = "shadow")] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("run", "status")][string]$Verb,
            [Parameter(ParameterSetName = "shadow")][switch]$Shadow,
            [Parameter(ParameterSetName = "live")][switch]$Live,
            [switch]$Once,
            [ValidateRange(1, 300)][int]$TickSeconds = 3
        )
        # -Shadow AND -Live ARE TWO PARAMETER SETS, so naming both is refused when the arguments are
        # bound - a usage error, exit 2 - and never reaches this body to be decided here.
        # -TickSeconds IS AT MOST 300: a watcher that looks less often than every five minutes is not a
        # doorbell, and stale is three ticks (core/WakeFiles.ps1), so a longer tick is a longer blindness.
        # A flag meant for another verb is refused, never silently ignored (cli/Commands.ps1, run blocks).
        if ($Verb -eq "status") { foreach ($flag in @("Shadow", "Live", "Once", "TickSeconds")) { if ($PSBoundParameters.ContainsKey($flag)) { throw ("-" + $flag + " belongs to wake run, not wake status") } } }
        # Loaded here, in the command's own scope, so each waker's functions stay visible to the blocks
        # it registers (wakers/Port.ps1, Get-HordeWakerFiles).
        $root = Get-HordeRoot
        . (Join-Path $root "core\WakeRun.ps1")
        foreach ($w in @(Get-HordeWakerFiles)) { . $w }

        if ($Verb -eq "status") {
            # BOTH MODES, EACH BY ITS OWN FILES: a shadow run says nothing of whether the live watcher
            # is alive (core/WakeFiles.ps1, Get-HordeWakeModeFile).
            foreach ($mode in @("LIVE", "SHADOW")) {
                $isShadow = ($mode -ceq "SHADOW")
                $beat = Read-HordeWakeHeartbeat -Shadow:$isShadow
                if ($beat.state -ceq "absent") { Write-Output ($mode + ": " + $beat.reason) }
                elseif ($beat.state -cne "known") { Write-Output ($mode + ": heartbeat unknown - " + $beat.reason) }
                else {
                    $age = [int][System.Math]::Max(0, ([datetime]::UtcNow - $beat.value.at).TotalSeconds)
                    $limit = Get-HordeWakeStaleSeconds -TickSeconds ([int]$beat.value.tickSeconds)
                    $word = "fresh"
                    if ($age -gt $limit) { $word = "STALE (over " + $limit + " s): this watcher is not running" }
                    Write-Output ($mode + ": heartbeat " + $age + " s ago, " + $word + " (pass " + $beat.value.pass + ", pid " + $beat.value.pid + ")")
                }
                $tail = @(Read-HordeWakeJournalTail -Count 10 -Shadow:$isShadow)
                if ($tail.Count -eq 0) { Write-Output ($mode + ": journal empty") }
                else { Write-Output ($mode + ": journal, the last " + $tail.Count + " line(s)"); foreach ($line in $tail) { Write-Output ("  " + $line) } }
            }
            return
        }

        # SHADOW IS THE DEFAULT, AND LIVE IS ASKED FOR BY NAME. With no flag, or -Shadow, the run journals
        # what it would do and nudges nobody. Only -Live makes a live run - refused when no waker is
        # installed to ring through (core/WakeRun.ps1, Get-HordeWakeRunPlan) - and the mode is given to
        # the run once, below, and to nothing else: the tick takes it from the run.
        $plan = Get-HordeWakeRunPlan -Live:$Live -Picked (Resolve-HordeProductionWaker)
        if (-not $plan.ok) { throw $plan.reason }
        $waker = $plan.waker
        # ONE WATCHER A HOME AND A MODE (core/WakeFiles.ps1, Enter-HordeWakeLock): held until this command ends.
        $lock = Enter-HordeWakeLock -Shadow:(-not $plan.live) -ProcessId $PID
        if ($null -eq $lock) { throw ("a " + $(if ($plan.live) { "live" } else { "shadow" }) + " wake run is already running in this home; this one has not started") }
        try {
            Write-Output ("wake: " + $plan.banner)
            $run = New-HordeWakeRun -Live:$plan.live
            foreach ($line in @($run.said)) { Write-Output ("wake: " + $line) }
            $modeWord = $(if ($run.live -eq $true) { "LIVE" } else { "shadow" })
            while ($true) {
                $entries = @(Invoke-HordeWakeTick -Run $run -Now ([datetime]::UtcNow) -Waker $waker -TickSeconds $TickSeconds -ProcessId $PID)
                foreach ($e in $entries) { Write-Output ("wake: " + $e.kind + " " + $e.id + " " + $e.outcome + " - " + $e.reason) }
                if ($Once) { Write-Output ("wake: pass " + $run.pass + " done, " + $entries.Count + " journal line(s), " + $modeWord); return }
                Start-Sleep -Seconds $TickSeconds
            }
        } finally { $lock.Dispose() }
    }
}
