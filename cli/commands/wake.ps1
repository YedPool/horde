$HordeCommand = @{
    name    = "wake"
    group   = "wake"
    sustained = $true
    usage   = "wake run [-Mode shadow|proof|live] [-Once] [-TickSeconds <n>] | wake status"
    summary = "run: the wake watcher - every pass it re-reads which sessions have unread mail and are idle with an empty input box, and after every session was started or restored together which orcs have not taken a turn since. SHADOW unless -Mode says otherwise (live: real nudges, through a waker whose every capability is verified; proof: one pass of real nudges, with -Once, to verify one): it writes what it would do to its journal and nudges and posts nothing. With -Live it sends real nudges through the installed waker; the restore source still only journals. status: for each mode, how long ago the watcher last ran, whether that is stale, and its last 10 journal lines"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("run", "status")][string]$Verb,
            [ValidateSet("shadow", "proof", "live")][ValidateScript({ @("shadow", "proof", "live") -ccontains $_ })][string]$Mode = "shadow",
            [Parameter(DontShow = $true)][ValidateScript({ $false })][object]$Mod,
            [switch]$Once,
            [ValidateRange(1, 300)][int]$TickSeconds = 3
        )
        # THE MODE IS ONE WORD, WRITTEN OUT, AND NOTHING ELSE SELECTS ONE. The two switches this replaces
        # (-Shadow, -Live) could be reached by any prefix PowerShell would complete - -L was a live run -
        # and a live run must never be one keystroke's accident. So: the value is one of three, in
        # exactly that casing (the second validation: ValidateSet alone ignores case); and the NAME
        # must be -Mode in full. PowerShell binds an unambiguous prefix of a parameter's name to it, so
        # -Mod is declared here as a parameter of its own that accepts no value: written out, it is
        # that parameter - an exact name wins over a prefix - and is refused; and -M and -Mo are now a
        # prefix of two names, which PowerShell refuses as ambiguous. Each is a usage error, exit 2,
        # when the arguments are bound, before this body runs. -Live, -L and -Shadow are no parameter
        # at all.
        # -TickSeconds IS AT MOST 300: a watcher that looks less often than every five minutes is not a
        # doorbell, and stale is three ticks (core/WakeFiles.ps1), so a longer tick is a longer blindness.
        # A flag meant for another verb is refused, never silently ignored (cli/Commands.ps1, run blocks).
        if ($Verb -eq "status") { foreach ($flag in @("Mode", "Once", "TickSeconds")) { if ($PSBoundParameters.ContainsKey($flag)) { throw ("-" + $flag + " belongs to wake run, not wake status") } } }
        # Loaded here, in the command's own scope, so each waker's functions stay visible to the blocks
        # it registers (wakers/Port.ps1, Get-HordeWakerFiles).
        $root = Get-HordeRoot
        . (Join-Path $root "core\WakeRun.ps1")
        foreach ($w in @(Get-HordeWakerFiles)) { . $w }

        if ($Verb -eq "status") {
            # EVERY MODE, EACH BY ITS OWN FILES: a shadow run says nothing of whether the live watcher
            # is alive (core/WakeFiles.ps1, Get-HordeWakeModeFile). A proof run makes one pass, so its
            # heartbeat is stale soon after; it is shown for when it last ran.
            # (The loop variable is not $mode: that is the parameter, in any casing, and its validation would refuse these.)
            foreach ($shown in @("LIVE", "PROOF", "SHADOW")) {
                $word = $shown.ToLowerInvariant()
                $beat = Read-HordeWakeHeartbeat -Mode $word
                if ($beat.state -ceq "absent") { Write-Output ($shown + ": " + $beat.reason) }
                elseif ($beat.state -cne "known") { Write-Output ($shown + ": heartbeat unknown - " + $beat.reason) }
                else {
                    $age = [int][System.Math]::Max(0, ([datetime]::UtcNow - $beat.value.at).TotalSeconds)
                    $limit = Get-HordeWakeStaleSeconds -TickSeconds ([int]$beat.value.tickSeconds)
                    $how = "fresh"
                    if ($age -gt $limit) { $how = "STALE (over " + $limit + " s): this watcher is not running" }
                    Write-Output ($shown + ": heartbeat " + $age + " s ago, " + $how + " (pass " + $beat.value.pass + ", pid " + $beat.value.pid + ")")
                }
                $tail = @(Read-HordeWakeJournalTail -Count 10 -Mode $word)
                if ($tail.Count -eq 0) { Write-Output ($shown + ": journal empty") }
                else { Write-Output ($shown + ": journal, the last " + $tail.Count + " line(s)"); foreach ($line in $tail) { Write-Output ("  " + $line) } }
            }
            return
        }

        # SHADOW IS THE DEFAULT, AND THE OTHER TWO ARE ASKED FOR BY NAME. What each needs - a waker, every
        # capability verified, -Once - is decided in core/WakeRun.ps1 (Get-HordeWakeRunPlan), and the
        # mode is given to the run once, below, and to nothing else: the tick takes it from the run.
        $plan = Get-HordeWakeRunPlan -Mode $Mode -Once:$Once -Picked (Get-HordeWakeRunPick -Mode $Mode)
        if (-not $plan.ok) { throw $plan.reason }
        $waker = $plan.waker
        # ONE WATCHER A HOME AND A MODE (core/WakeFiles.ps1, Enter-HordeWakeLock): held until this command ends.
        # Only "another run holds it" is said as that; any other failure to take the lock is said as
        # what it is, so nobody is sent looking for a second watcher when the disk is full.
        $lock = $null
        try { $lock = Enter-HordeWakeLock -Mode $plan.mode -ProcessId $PID }
        catch { throw ("the wake run could not take its lock, so it has not started: " + $_.Exception.Message) }
        if ($null -eq $lock) { throw ("a " + $plan.mode + " wake run is already running in this home; this one has not started") }
        try {
            Write-Output ("wake: " + $plan.banner)
            $run = New-HordeWakeRun -Mode $plan.mode
            foreach ($line in @($run.said)) { Write-Output ("wake: " + $line) }
            $modeWord = $(if ($plan.mode -ceq "shadow") { "shadow" } else { $plan.mode.ToUpperInvariant() })
            while ($true) {
                $entries = @(Invoke-HordeWakeTick -Run $run -Now ([datetime]::UtcNow) -Waker $waker -TickSeconds $TickSeconds -ProcessId $PID)
                foreach ($e in $entries) { Write-Output ("wake: " + $e.kind + " " + $e.id + " " + $e.outcome + " - " + $e.reason) }
                # ONE PASS, for -Once - and for a proof run whatever else is true: the plan refused a
                # proof without -Once, and this is the loop's own word for the same thing.
                if ($Once -or $plan.mode -ceq "proof") { Write-Output ("wake: pass " + $run.pass + " done, " + $entries.Count + " journal line(s), " + $modeWord); return }
                Start-Sleep -Seconds $TickSeconds
            }
        } finally { $lock.Dispose() }
    }
}
