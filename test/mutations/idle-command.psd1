# Mutations of cli/commands/idle.ps1, `horde idle`. Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\idle-command.psd1
@{
    Target = "cli\commands\idle.ps1"
    Suite  = "test\test-idle.ps1"
    Mutations = @(
        @{ Name = "not-allowed-exits-zero"
           Find = '        if (-not $state.allowed) { throw'
           Replace = '        if ($false) { throw' }
        @{ Name = "wait-seconds-without-wait-accepted"
           Find = 'if (-not $Wait -and $WaitSeconds -ne -1) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "refused-settings-ignored"
           Find = '        if (-not $config.ok) { throw'
           Replace = '        if ($false) { throw' }
        @{ Name = "timeout-not-said"
           Find = 'if ($got.timedOut) { Write-Output'
           Replace = 'if ($false) { Write-Output' }
    )
}