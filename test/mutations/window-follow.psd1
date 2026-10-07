# Mutations of platform/windows/WindowFollow.ps1, the Windows follower of core/WindowFollowPort.ps1.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\window-follow.psd1
# test\test-window-follow.ps1 must fail for each. Where a companion stands is the port's, and so are
# its mutants (test\mutations\window-follow-port.psd1).
@{
    Target = "platform\windows\WindowFollow.ps1"
    Suite  = "test\test-window-follow.ps1"
    Mutations = @(
        @{ Name = "not-registered-by-being-loaded"
           Find = 'Register-HordeWindowFollower @blocks'
           Replace = '' }
        @{ Name = "registered-for-no-system"
           Find = 'Applies   = { Test-HordeIsWindows }'
           Replace = 'Applies   = { $false }' }
        @{ Name = "compiled-when-loaded"
           Find = 'function Initialize-HordeWindowsFollowType {'
           Replace = 'Add-Type -TypeDefinition (Get-HordeWindowsFollowSource); function Initialize-HordeWindowsFollowType {' }
        @{ Name = "a-window-that-is-not-there-is-followed"
           Find = 'if (-not [HordeWindowsFollowV1]::Exists($Target)) { return'
           Replace = 'if ($false) { return' }
    )
}
