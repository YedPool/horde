# Mutations of cli/commands/wake.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-command.psd1
# The command is held by its end-to-end scenario, which drives the real command line. Each mutant breaks
# one thing the command itself decides: that run needs -Shadow, that a second run is refused, that a
# flag of another verb is refused, and what status calls stale. (A tick that is not a shadow tick is not
# among them, because the command can no longer make one: core/WakeRun.ps1 offers only the shadow tick,
# and test\mutations\wake-run.psd1 holds that. The review of PR #207 found that dropping -Shadow at
# the command's two call sites passed every suite.)
@{
    Target = "cli\commands\wake.ps1"
    Suite  = "test\e2e\e2e-wake.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "run-without-shadow-allowed"
           Find = 'if (-not $Shadow) { throw "wake run needs -Shadow'
           Replace = 'if ($false) { throw "wake run needs -Shadow' }
        @{ Name = "second-run-not-refused"
           Find = 'if ($null -eq $lock) { throw "a shadow wake run is already running'
           Replace = 'if ($false) { throw "a shadow wake run is already running' }
        @{ Name = "flag-of-another-verb-ignored"
           Find = 'if ($PSBoundParameters.ContainsKey($flag)) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "stale-ignores-the-tick"
           Find = '$limit = Get-HordeWakeStaleSeconds -TickSeconds ([int]$beat.value.tickSeconds)'
           Replace = '$limit = Get-HordeWakeStaleSeconds' }
        @{ Name = "never-stale"
           Find = 'if ($age -gt $limit) {'
           Replace = 'if ($false) {' }
        @{ Name = "tick-of-an-hour-accepted"
           Find = '[ValidateRange(1, 300)][int]$TickSeconds = 3'
           Replace = '[ValidateRange(1, 3600)][int]$TickSeconds = 3' }
        @{ Name = "once-loops"
           Find = 'if ($Once) { Write-Output ("wake: pass " + $run.pass'
           Replace = 'if ($false) { Write-Output ("wake: pass " + $run.pass' }
    )
}
