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
        @{ Name = "the-default-is-live"
           Find = '$plan = Get-HordeWakeRunPlan -Live:$Live -Picked (Resolve-HordeProductionWaker)'
           Replace = '$plan = Get-HordeWakeRunPlan -Live -Picked (Resolve-HordeProductionWaker)' }
        @{ Name = "live-is-never-live"
           Find = '$plan = Get-HordeWakeRunPlan -Live:$Live -Picked (Resolve-HordeProductionWaker)'
           Replace = '$plan = Get-HordeWakeRunPlan -Picked (Resolve-HordeProductionWaker)' }
        @{ Name = "the-run-is-made-live-whatever-the-plan"
           Find = '$run = New-HordeWakeRun -Live:$plan.live'
           Replace = '$run = New-HordeWakeRun -Live' }
        @{ Name = "shadow-and-live-together-accepted"
           Find = '[Parameter(ParameterSetName = "live")][switch]$Live,'
           Replace = '[switch]$Live,' }
        @{ Name = "second-run-not-refused"
           Find = 'if ($null -eq $lock) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "flag-of-another-verb-ignored"
           Find = 'if ($PSBoundParameters.ContainsKey($flag)) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "status-reads-one-heartbeat-for-both-modes"
           Find = '$beat = Read-HordeWakeHeartbeat -Shadow:$isShadow'
           Replace = '$beat = Read-HordeWakeHeartbeat -Shadow' }
        @{ Name = "status-reads-one-journal-for-both-modes"
           Find = '$tail = @(Read-HordeWakeJournalTail -Count 10 -Shadow:$isShadow)'
           Replace = '$tail = @(Read-HordeWakeJournalTail -Count 10 -Shadow)' }
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
