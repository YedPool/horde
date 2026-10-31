$HordeCommand = @{
    name    = "idle"
    group   = "work"
    usage   = "idle [-Wait [-WaitSeconds <n>]] [-Json]"
    summary = "is the PC idle or is it night, so a test suite, guard run, mutation run or review may start? Prints the seconds without keyboard or mouse input, the local time and 'idle-or-night: yes' or 'no'. Exit 0 when allowed; exit 1 (after the lines, with the reason) when not, because horde's exit codes are 0, 1 and 2 only and 2 means a wrong command line. -Wait polls until it holds or -WaitSeconds (default 3600) pass, and exits 1 on timeout. Idle means 600 s without input, night means 22:00 to 07:00 local; both are settings in <HORDE_HOME>\settings\idle.json (idleSeconds, nightStartHour, nightEndHour). Input the fleet types into panes does not count as input. A process outside the interactive session cannot read the input clock: that is treated as not idle, unless it is night (core/IdleState.ps1)"
    run     = {
        [CmdletBinding()] param([switch]$Wait, [int]$WaitSeconds = -1, [switch]$Json)
        if (-not $Wait -and $WaitSeconds -ne -1) { throw (New-HordeUsageError "idle: -WaitSeconds goes with -Wait") }
        if ($WaitSeconds -lt -1) { throw (New-HordeUsageError "idle: -WaitSeconds must be 0 or more") }
        if ($Wait -and $WaitSeconds -eq -1) { $WaitSeconds = 3600 }
        $root = Get-HordeRoot
        . (Join-Path $root "core\IdleState.ps1")
        $config = Get-HordeIdleConfig
        if (-not $config.ok) { throw ($config.findings -join [Environment]::NewLine) }
        # HORDE_IDLE_INPUT_SECONDS pins the input reader to "known, this many seconds" so a suite can ask for a
        # not-allowed answer on a PC nobody has touched for a day (T-0331: the real reader read 33 h on 2026-10-31 and
        # test-idle.ps1 could not make "busy" happen). It is no wider than idle.json, which already sets idleSeconds.
        # A value that is not digits is refused, never read as zero.
        $reader = { Read-HordeIdleSeconds }
        $pin = [Environment]::GetEnvironmentVariable("HORDE_IDLE_INPUT_SECONDS")
        if ($pin) {
            if ($pin -cnotmatch "^[0-9]{1,9}$") { throw "idle: HORDE_IDLE_INPUT_SECONDS must be whole seconds in digits only" }
            $pinned = [int]$pin
            $reader = { [pscustomobject]@{ state = "known"; seconds = $pinned; reason = "" } }.GetNewClosure()
        }
        if ($Wait) { $got = Wait-HordeIdleState -GetState { Get-HordeIdleState -Config $config -Reader $reader } -WaitSeconds $WaitSeconds }
        else { $got = [pscustomobject]@{ allowed = $false; timedOut = $false; state = (Get-HordeIdleState -Config $config -Reader $reader) } ; $got.allowed = $got.state.allowed }
        $state = $got.state
        if ($Json) {
            [pscustomobject]@{ idleSeconds = $state.idleSeconds; needSeconds = $state.needSeconds; time = $state.time; allowed = $state.allowed; why = $state.why; timedOut = $got.timedOut } | ConvertTo-Json -Compress
        } else {
            Format-HordeIdleState -State $state | ForEach-Object { Write-Output $_ }
            if ($got.timedOut) { Write-Output ("gave up after " + $WaitSeconds + " s waiting for idle-or-night") }
        }
        if (-not $state.allowed) { throw ("idle-or-night does not hold (" + $state.why + "); nothing may be started now") }
    }
}
