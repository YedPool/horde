# Mutations of cli/commands/wake.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-command.psd1
# The command is held by its end-to-end scenario, which drives the real command line against a fake of
# the fleet's command. Each mutant breaks one thing the command itself decides: that a run is SHADOW
# unless -Live is given, that -Live and -Shadow together are refused, that a second run is refused,
# that a flag of another verb is refused, that status shows each mode by its own files, and what it
# calls stale.
@{
    Target = "cli\commands\wake.ps1"
    Suite  = "test\e2e\e2e-wake.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "mode-value-in-any-casing"
           Find = '[ValidateSet("shadow", "proof", "live")][ValidateScript({ @("shadow", "proof", "live") -ccontains $_ })][string]$Mode'
           Replace = '[ValidateSet("shadow", "proof", "live")][string]$Mode' }
        @{ Name = "proof-run-not-told-it-is-once"
           Find = '$plan = Get-HordeWakeRunPlan -Mode $Mode -Once:$Once -Picked (Get-HordeWakeRunPick -Mode $Mode)'
           Replace = '$plan = Get-HordeWakeRunPlan -Mode $Mode -Once -Picked (Get-HordeWakeRunPick -Mode $Mode)' }
        @{ Name = "proof-run-takes-the-live-lock"
           Find = '$lock = Enter-HordeWakeLock -Mode $plan.mode -ProcessId $PID'
           Replace = '$lock = Enter-HordeWakeLock -Mode "shadow" -ProcessId $PID' }
        @{ Name = "the-default-is-live"
           Find = '[string]$Mode = "shadow",'
           Replace = '[string]$Mode = "live",' }
        @{ Name = "live-is-never-live"
           Find = '$plan = Get-HordeWakeRunPlan -Mode $Mode -Once:$Once -Picked (Get-HordeWakeRunPick -Mode $Mode)'
           Replace = '$plan = Get-HordeWakeRunPlan -Mode "shadow" -Once:$Once -Picked (Get-HordeWakeRunPick -Mode $Mode)' }
        @{ Name = "the-run-is-made-live-whatever-the-plan"
           Find = '$run = New-HordeWakeRun -Mode $plan.mode'
           Replace = '$run = New-HordeWakeRun -Mode "live"' }
        @{ Name = "a-prefix-of-the-mode-parameters-name-selects-a-mode"
           Find = '[Parameter(DontShow = $true)][ValidateScript({ $false })][object]$Mod,'
           Replace = '' }
        @{ Name = "second-run-not-refused"
           Find = 'if ($null -eq $lock) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "flag-of-another-verb-ignored"
           Find = 'if ($PSBoundParameters.ContainsKey($flag)) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "status-reads-one-heartbeat-for-every-mode"
           Find = '$beat = Read-HordeWakeHeartbeat -Mode $word'
           Replace = '$beat = Read-HordeWakeHeartbeat -Mode "shadow"' }
        @{ Name = "status-reads-one-journal-for-every-mode"
           Find = '$tail = @(Read-HordeWakeJournalTail -Count 10 -Mode $word)'
           Replace = '$tail = @(Read-HordeWakeJournalTail -Count 10 -Mode "shadow")' }
        @{ Name = "stale-ignores-the-tick"
           Find = '$limit = Get-HordeWakeStaleSeconds -TickSeconds ([int]$beat.value.tickSeconds)'
           Replace = '$limit = Get-HordeWakeStaleSeconds' }
        @{ Name = "never-stale"
           Find = 'if ($age -gt $limit) {'
           Replace = 'if ($false) {' }
        @{ Name = "tick-of-an-hour-accepted"
           Find = '[ValidateRange(1, 300)][int]$TickSeconds = 3'
           Replace = '[ValidateRange(1, 3600)][int]$TickSeconds = 3' }
    )
}
