$HordeCommand = @{
    name    = "wake"
    group   = "wake"
    sustained = $true
    usage   = "wake run -Shadow [-Once] [-TickSeconds <n>] | wake status"
    summary = "run: the wake watcher - every pass it re-reads which sessions have unread mail and are idle with an empty input box, and after a restore of every session which still have not taken a turn; with -Shadow, the only way it runs today, it writes what it would do to its journal and nudges and posts nothing. status: how long ago the watcher last ran, whether that is stale, and its last 10 journal lines"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("run", "status")][string]$Verb,
            [switch]$Shadow,
            [switch]$Once,
            [ValidateRange(1, 300)][int]$TickSeconds = 3
        )
        # -TickSeconds IS AT MOST 300: a watcher that looks less often than every five minutes is not a
        # doorbell, and stale is three ticks (core/WakeFiles.ps1), so a longer tick is a longer blindness.
        # A flag meant for another verb is refused, never silently ignored (cli/Commands.ps1, run blocks).
        if ($Verb -eq "status") { foreach ($flag in @("Shadow", "Once", "TickSeconds")) { if ($PSBoundParameters.ContainsKey($flag)) { throw ("-" + $flag + " belongs to wake run, not wake status") } } }
        # Loaded here, in the command's own scope, so each waker's functions stay visible to the blocks
        # it registers (wakers/Port.ps1, Get-HordeWakerFiles).
        $root = Get-HordeRoot
        . (Join-Path $root "core\WakeRun.ps1")
        foreach ($w in @(Get-HordeWakerFiles)) { . $w }

        if ($Verb -eq "status") {
            $beat = Read-HordeWakeHeartbeat
            if ($beat.state -ceq "absent") { Write-Output $beat.reason }
            elseif ($beat.state -cne "known") { Write-Output ("heartbeat: unknown - " + $beat.reason) }
            else {
                $age = [int][System.Math]::Max(0, ([datetime]::UtcNow - $beat.value.at).TotalSeconds)
                $limit = Get-HordeWakeStaleSeconds -TickSeconds ([int]$beat.value.tickSeconds)
                $word = "fresh"
                if ($age -gt $limit) { $word = "STALE (over " + $limit + " s): the watcher is not running" }
                Write-Output ("heartbeat: " + $age + " s ago, " + $word + " (pass " + $beat.value.pass + ", pid " + $beat.value.pid + ", shadow " + ("$($beat.value.shadow)").ToLowerInvariant() + ")")
            }
            $tail = @(Read-HordeWakeJournalTail -Count 10)
            if ($tail.Count -eq 0) { Write-Output "journal: empty" }
            else { Write-Output ("journal: the last " + $tail.Count + " line(s)"); foreach ($line in $tail) { Write-Output ("  " + $line) } }
            return
        }

        # SHADOW IS THE ONLY WAY IT RUNS TODAY. No waker that can reach a real session ships yet, and
        # there is no path from here to a nudge: the only tick this command can make is the shadow tick
        # (core/WakeRun.ps1), which takes no parameter that could make it anything else.
        if (-not $Shadow) { throw "wake run needs -Shadow: live nudging arrives with the first real waker. With -Shadow it journals what it would do and nudges nobody" }
        # ONE WATCHER A HOME AND A MODE (core/WakeFiles.ps1, Enter-HordeWakeLock): held until this command ends.
        $lock = Enter-HordeWakeLock -Shadow -ProcessId $PID
        if ($null -eq $lock) { throw "a shadow wake run is already running in this home; this one has not started" }
        try {
            $picked = Resolve-HordeProductionWaker
            $waker = $null
            if ($picked.state -ceq "known") { $waker = $picked.value; Write-Output ("wake: shadow run through the waker '" + $waker.name + "'") }
            else { Write-Output ("wake: no waker is installed, so no session is watched for unread mail; the restore source still runs (" + $picked.reason + ")") }
            $run = New-HordeWakeShadowRun
            foreach ($line in @($run.said)) { Write-Output ("wake: " + $line) }
            while ($true) {
                $entries = @(Invoke-HordeWakeShadowTick -Run $run -Now ([datetime]::UtcNow) -Waker $waker -TickSeconds $TickSeconds -ProcessId $PID)
                foreach ($e in $entries) { Write-Output ("wake: " + $e.kind + " " + $e.id + " " + $e.outcome + " - " + $e.reason) }
                if ($Once) { Write-Output ("wake: pass " + $run.pass + " done, " + $entries.Count + " journal line(s), shadow"); return }
                Start-Sleep -Seconds $TickSeconds
            }
        } finally { $lock.Dispose() }
    }
}
