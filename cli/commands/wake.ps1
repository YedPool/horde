$HordeCommand = @{
    name    = "wake"
    group   = "wake"
    sustained = $true
    usage   = "wake run [-Mode shadow|live] [-Once] [-TickSeconds <n>] | wake run -Proof -Target <session id> -Once | wake status"
    summary = "run: the wake watcher - every pass it re-reads which sessions have unread mail and are idle with an empty input box, and after every session was started or restored together which orcs have not taken a turn since. Three forms. wake run (or -Mode shadow) is SHADOW: it journals what it would do, and nudges and posts nothing. wake run -Mode live sends real nudges, one a pass, for as long as it runs - only through a waker whose every capability is verified and whose program is named in its settings. wake run -Proof -Target <session id> -Once is a proof run: ONE pass that may type one line into the ONE session named and no other, to verify a waker; all three are required. In every form the restore source and the tells to the warchief only journal what they would send. status: for shadow, proof and live, how long ago each last ran, whether that is stale, and its last 10 journal lines"
    run     = {
        [CmdletBinding(DefaultParameterSetName = "watch")] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("run", "status")][string]$Verb,
            [Parameter(ParameterSetName = "watch")][ValidateSet("shadow", "live")][ValidateScript({ @("shadow", "live") -ccontains $_ })][string]$Mode = "shadow",
            [Parameter(ParameterSetName = "watch", DontShow = $true)][ValidateScript({ $false })][object]$Mod,
            [Parameter(ParameterSetName = "proof")][Parameter(ParameterSetName = "proof-alone")][Parameter(ParameterSetName = "proof-no-once")][Parameter(ParameterSetName = "proof-no-target")][switch]$Proof,
            [Parameter(ParameterSetName = "proof")][Parameter(ParameterSetName = "proof-no-once")][Parameter(ParameterSetName = "target-no-proof")][ValidateScript({ $_ -cmatch '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z' })][string]$Target = "",
            [Parameter(ParameterSetName = "watch")][Parameter(ParameterSetName = "proof")][Parameter(ParameterSetName = "proof-no-target")][Parameter(ParameterSetName = "target-no-proof")][switch]$Once,
            [Parameter(ParameterSetName = "watch")][ValidateRange(1, 300)][int]$TickSeconds = 3
        )
        # A PROOF RUN IS A COMMAND LINE OF ITS OWN: -Proof -Target <session id> -Once, ALL THREE, AND
        # NOTHING OF A WATCH. It types into a real session, so which one is never left to the run: the
        # first version of proof nudged whichever session the fair order served first, and that is the
        # warchief (review of PR #220). The three are one parameter set, "proof", and -Mode and
        # -TickSeconds belong to the other: so a proof with no target, a target with no proof, a
        # proof that would loop, and a target given to a shadow or a live run are each refused when
        # the arguments are bound - a usage error, exit 2 - before this body runs.
        # NONE OF THE THREE IS DECLARED MANDATORY, AND THAT IS ON PURPOSE. They were, at first: and a
        # missing mandatory parameter is not refused by PowerShell when it can ask - it PROMPTS
        # ("Target:"), and a horde started with its input open waited there for ever (found
        # 2026-10-13: the scenario hung on "wake run -Proof -Once"). So the incomplete forms are each
        # made AMBIGUOUS instead, which PowerShell refuses at once and never asks about: -Proof alone
        # fits proof-alone and three other sets, -Proof -Once fits proof and proof-no-target, -Proof
        # -Target fits proof and proof-no-once, -Target -Once fits proof and target-no-proof - and
        # none of those is the default set, so none is chosen. Only all three together fit exactly
        # one set. The four extra sets exist for nothing else, and the body below still refuses
        # anything but all three. THAT IS WHY
        # PROOF IS A SWITCH AND NOT A THIRD VALUE OF -Mode: a rule between two parameters' VALUES can
        # only be checked in the body, where a refusal is an ordinary failure (cli/Runner.ps1), and
        # "-Mode proof" alone would have bound. -Target is a session id written out in full, a
        # lower-case UUID, in exactly that casing: not a label and not a part of an id.
        # THE MODE IS ONE WORD, WRITTEN OUT, AND NOTHING ELSE SELECTS ONE. The two switches this replaces
        # (-Shadow, -Live) could be reached by any prefix PowerShell would complete - -L was a live run -
        # and a live run must never be one keystroke's accident. So: the value is one of two, in
        # exactly that casing (the second validation: ValidateSet alone ignores case; a watch has two
        # modes, shadow and live - a proof run is not one of them, above); and the NAME
        # must be -Mode in full. PowerShell binds an unambiguous prefix of a parameter's name to it, so
        # -Mod is declared here as a parameter of its own that accepts no value: written out, it is
        # that parameter - an exact name wins over a prefix - and is refused; and -M and -Mo are now a
        # prefix of two names, which PowerShell refuses as ambiguous. Each is a usage error, exit 2,
        # when the arguments are bound, before this body runs. -Live, -L and -Shadow are no parameter
        # at all.
        # -TickSeconds IS AT MOST 300: a watcher that looks less often than every five minutes is not a
        # doorbell, and stale is three ticks (core/WakeFiles.ps1), so a longer tick is a longer blindness.
        # A flag meant for another verb is refused, never silently ignored (cli/Commands.ps1, run blocks).
        if ($Verb -eq "status") { foreach ($flag in @("Mode", "Proof", "Target", "Once", "TickSeconds")) { if ($PSBoundParameters.ContainsKey($flag)) { throw ("-" + $flag + " belongs to wake run, not wake status") } } }
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
        # WHICH RUN THIS IS: a proof when -Proof was given (and then -Target and -Once were too, or the
        # arguments would not have bound), else the watch's mode. Not written back into $Mode: that
        # is the parameter, and its validation would refuse the word.
        if ($PSCmdlet.ParameterSetName -cne "watch" -and -not ($PSCmdlet.ParameterSetName -ceq "proof" -and $Proof -and $Once -and $Target -cne "")) { throw "a proof run is -Proof -Target <session id> -Once, all three; this is not one, and nothing was run" }
        $chosen = $Mode
        $aim = ""
        if ($Proof) { $chosen = "proof"; $aim = $Target }
        $plan = Get-HordeWakeRunPlan -Mode $chosen -Once:$Once -Target $aim -Picked (Get-HordeWakeRunPick -Mode $chosen)
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
            $run = New-HordeWakeRun -Mode $plan.mode -Target $plan.target
            foreach ($line in @($run.said)) { Write-Output ("wake: " + $line) }
            $modeWord = $(if ($plan.mode -ceq "shadow") { "shadow" } else { $plan.mode.ToUpperInvariant() })
            while ($true) {
                $entries = @(Invoke-HordeWakeTick -Run $run -Now ([datetime]::UtcNow) -Waker $waker -TickSeconds $TickSeconds -ProcessId $PID)
                foreach ($e in $entries) { Write-Output ("wake: " + $e.kind + " " + $e.id + " " + $e.outcome + " - " + $e.reason) }
                # ONE PASS, for -Once - and for a proof run whatever else is true: the plan refused a
                # proof without -Once, and this is the loop's own word for the same thing.
                if ($Once -or $plan.mode -ceq "proof") {
                    Write-Output ("wake: pass " + $run.pass + " done, " + $entries.Count + " journal line(s), " + $modeWord)
                    # A PROOF THAT COULD NOT FIND ITS SESSION PROVED NOTHING, and says so by its exit.
                    if (@($entries | Where-Object { $_.kind -ceq "proof-target-absent" -or ($plan.mode -ceq "proof" -and $_.kind -ceq "skip-unknown" -and $_.id -ceq "pass") }).Count -gt 0) { throw ("the proof run nudged nobody: its session " + $plan.target + " was not found in the fleet's listing") }
                    return
                }
                Start-Sleep -Seconds $TickSeconds
            }
        } finally { $lock.Dispose() }
    }
}
