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
            [ValidateRange(1, 3600)][int]$TickSeconds = 3
        )
        # A flag meant for another verb is refused, never silently ignored (cli/Commands.ps1, run blocks).
        if ($Verb -eq "status") { foreach ($flag in @("Shadow", "Once", "TickSeconds")) { if ($PSBoundParameters.ContainsKey($flag)) { throw ("-" + $flag + " belongs to wake run, not wake status") } } }
        # Loaded here, in the command's own scope, so each waker's functions stay visible to the blocks
        # it registers (wakers/Port.ps1, Get-HordeWakerFiles).
        $root = Get-HordeRoot
        . (Join-Path $root "core\Wake.ps1")
        foreach ($w in @(Get-HordeWakerFiles)) { . $w }

        if ($Verb -eq "status") {
            $beat = Read-HordeWakeHeartbeat
            if ($beat.state -ceq "absent") { Write-Output $beat.reason }
            elseif ($beat.state -cne "known") { Write-Output ("heartbeat: unknown - " + $beat.reason) }
            else {
                $age = [int][System.Math]::Max(0, ([datetime]::UtcNow - $beat.value.at).TotalSeconds)
                $limit = Get-HordeWakeStaleSeconds
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
        # there is no path from here to a nudge: every pass below is made with -Shadow, literally.
        if (-not $Shadow) { throw "wake run needs -Shadow: live nudging arrives with the first real waker. With -Shadow it journals what it would do and nudges nobody" }
        $settings = Get-HordeWakeSettings
        $picked = Resolve-HordeProductionWaker
        $waker = $null
        if ($picked.state -ceq "known") { $waker = $picked.value; Write-Output ("wake: shadow run through the waker '" + $waker.name + "'") }
        else { Write-Output ("wake: no waker is installed, so no session is watched for unread mail; the restore source still runs (" + $picked.reason + ")") }
        $ledger = @{}
        $posted = @{}
        $saved = Read-HordeWakeLedger
        if ($saved.state -ceq "known") { $ledger = $saved.value.ledger; $posted = $saved.value.posted }
        elseif ($saved.state -ceq "unknown") { Write-Output ("wake: starting from an empty ledger - " + $saved.reason) }
        # THE RESTORE SOURCE IS READ EVERY 30 s, NOT EVERY PASS: it reads the process table, and a
        # restore is measured in minutes (the first resume is due at once, the stall notice at 300 s).
        $restoreEvery = 30
        $restoreAt = [datetime]::MinValue
        $unknown = @{}
        $pass = [long]0
        while ($true) {
            $pass++
            $now = [datetime]::UtcNow
            $sessions = $null
            $extra = @()
            if (($now - $restoreAt).TotalSeconds -ge $restoreEvery) {
                $restoreAt = $now
                $read = Get-HordeRestoreSessions
                if ($read.state -ceq "known") { $sessions = @($read.value) }
                else { $extra = @(New-HordeWakeEntry -At $now -Kind "skip-unknown" -Id "restore" -Outcome "unknown" -Reason ("the restore source could not read the sessions: " + $read.reason)) }
            }
            $result = Invoke-HordeWakePass -Waker $waker -Now $now -Settings $settings -Ledger $ledger -Shadow -RestoreSessions $sessions -Posted $posted
            # The restore source's own unknown is carried between its readings, so the passes in between
            # neither repeat it nor forget it.
            if ($null -eq $sessions -and $extra.Count -eq 0 -and $unknown.ContainsKey("restore")) { $extra = @(New-HordeWakeEntry -At $now -Kind "skip-unknown" -Id "restore" -Outcome "unknown" -Reason $unknown["restore"]) }
            $fresh = Select-HordeWakeNewEntries -Entries (@($result.entries) + $extra) -Unknown $unknown
            $unknown = $fresh.unknown
            $changed = (@($fresh.entries).Count -gt 0 -or $result.ledger.Count -ne $ledger.Count)
            $ledger = $result.ledger
            $posted = $result.posted
            $null = Write-HordeWakeJournal -Entries $fresh.entries
            if ($changed) { Save-HordeWakeLedger -Ledger $ledger -Posted $posted }
            Write-HordeWakeHeartbeat -At $now -ProcessId $PID -Pass $pass -Shadow
            foreach ($e in @($fresh.entries)) { Write-Output ("wake: " + $e.kind + " " + $e.id + " " + $e.outcome + " - " + $e.reason) }
            if ($Once) { Write-Output ("wake: pass " + $pass + " done, " + @($fresh.entries).Count + " journal line(s), shadow"); return }
            Start-Sleep -Seconds $TickSeconds
        }
    }
}
