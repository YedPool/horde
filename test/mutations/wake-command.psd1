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
        @{ Name = "a-refused-run-is-started-by-the-command"
           Find = 'if ("$($run.refused)" -cne "") { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "a-proof-with-no-target-binds"
           Find = '[Parameter(ParameterSetName = "proof")][Parameter(ParameterSetName = "proof-no-once")][Parameter(ParameterSetName = "proof-no-target")][switch]$Proof,'
           Replace = '[Parameter(ParameterSetName = "proof")][Parameter(ParameterSetName = "proof-no-once")][switch]$Proof,' }
        @{ Name = "a-proof-that-would-loop-binds"
           Find = '[Parameter(ParameterSetName = "proof")][Parameter(ParameterSetName = "proof-no-once")][Parameter(ParameterSetName = "target-no-proof")][ValidateScript({ $_ -cmatch ''\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z'' })][string]$Target = "",'
           Replace = '[Parameter(ParameterSetName = "proof")][Parameter(ParameterSetName = "target-no-proof")][ValidateScript({ $_ -cmatch ''\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z'' })][string]$Target = "",' }
        @{ Name = "a-target-with-no-proof-binds"
           Find = '[Parameter(ParameterSetName = "proof")][Parameter(ParameterSetName = "proof-no-once")][Parameter(ParameterSetName = "target-no-proof")][ValidateScript({ $_ -cmatch ''\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z'' })][string]$Target = "",'
           Replace = '[Parameter(ParameterSetName = "proof")][Parameter(ParameterSetName = "proof-no-once")][ValidateScript({ $_ -cmatch ''\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z'' })][string]$Target = "",' }
        @{ Name = "a-target-in-another-casing-or-a-part-of-one-is-taken"
           Find = '[Parameter(ParameterSetName = "proof")][Parameter(ParameterSetName = "proof-no-once")][Parameter(ParameterSetName = "target-no-proof")][ValidateScript({ $_ -cmatch ''\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z'' })][string]$Target = "",'
           Replace = '[Parameter(ParameterSetName = "proof")][Parameter(ParameterSetName = "proof-no-once")][Parameter(ParameterSetName = "target-no-proof")][string]$Target = "",' }
        @{ Name = "a-target-may-be-given-to-a-watch"
           Find = '[Parameter(ParameterSetName = "proof")][Parameter(ParameterSetName = "proof-no-once")][Parameter(ParameterSetName = "target-no-proof")][ValidateScript({ $_ -cmatch ''\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z'' })][string]$Target = "",'
           Replace = '[Parameter(ParameterSetName = "watch")][Parameter(ParameterSetName = "proof")][Parameter(ParameterSetName = "proof-no-once")][Parameter(ParameterSetName = "target-no-proof")][ValidateScript({ $_ -cmatch ''\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z'' })][string]$Target = "",' }
        @{ Name = "a-missing-part-of-a-proof-is-asked-for"
           Find = '[Parameter(ParameterSetName = "proof")][Parameter(ParameterSetName = "proof-no-once")][Parameter(ParameterSetName = "proof-no-target")][switch]$Proof,'
           Replace = '[Parameter(ParameterSetName = "proof", Mandatory = $true)][switch]$Proof,' }
        @{ Name = "proof-is-a-mode-word-again"
           Find = '[Parameter(ParameterSetName = "watch")][ValidateSet("shadow", "live")][ValidateScript({ @("shadow", "live") -ccontains $_ })][string]$Mode'
           Replace = '[Parameter(ParameterSetName = "watch")][ValidateSet("shadow", "live", "proof")][ValidateScript({ @("shadow", "live", "proof") -ccontains $_ })][string]$Mode' }
        @{ Name = "a-proof-is-aimed-at-another-session-than-the-one-named"
           Find = 'if ($Proof) { $chosen = "proof"; $aim = $Target }'
           Replace = 'if ($Proof) { $chosen = "proof"; $aim = "0a000000-0000-4000-8000-000000000001" }' }
        @{ Name = "the-proofs-target-does-not-reach-the-run"
           Find = '$run = New-HordeWakeRun -Mode $plan.mode -Target $plan.target'
           Replace = '$run = New-HordeWakeRun -Mode $plan.mode' }
        @{ Name = "a-proof-that-found-nobody-exits-0"
           Find = '.Count -gt 0) { throw ("the proof run nudged nobody'
           Replace = '.Count -lt 0) { throw ("the proof run nudged nobody' }
        @{ Name = "mode-value-in-any-casing"
           Find = '[ValidateSet("shadow", "live")][ValidateScript({ @("shadow", "live") -ccontains $_ })][string]$Mode'
           Replace = '[ValidateSet("shadow", "live")][string]$Mode' }
        @{ Name = "proof-run-takes-the-live-lock"
           Find = '$lock = Enter-HordeWakeLock -Mode $plan.mode -ProcessId $PID'
           Replace = '$lock = Enter-HordeWakeLock -Mode "shadow" -ProcessId $PID' }
        @{ Name = "the-default-is-live"
           Find = '[string]$Mode = "shadow",'
           Replace = '[string]$Mode = "live",' }
        @{ Name = "live-is-never-live"
           Find = '$plan = Get-HordeWakeRunPlan -Mode $chosen -Once:$Once -Target $aim -Picked (Get-HordeWakeRunPick -Mode $chosen)'
           Replace = '$plan = Get-HordeWakeRunPlan -Mode "shadow" -Once:$Once -Target "" -Picked (Get-HordeWakeRunPick -Mode $chosen)' }
        @{ Name = "the-run-is-made-live-whatever-the-plan"
           Find = '$run = New-HordeWakeRun -Mode $plan.mode -Target $plan.target'
           Replace = '$run = New-HordeWakeRun -Mode "live" -Target $plan.target' }
        @{ Name = "a-prefix-of-the-mode-parameters-name-selects-a-mode"
           Find = '[Parameter(ParameterSetName = "watch", DontShow = $true)][ValidateScript({ $false })][object]$Mod,'
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
