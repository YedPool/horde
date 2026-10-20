# Mutations of hooks/horde-status-guard-check.ps1, the checker half of the status guard hook. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\status-guard-check.psd1
# Each breaks one rule of rejecting, restoring or copying; test\test-status-guard-hook.ps1 must fail a check for every one.
@{
    Target = "hooks\horde-status-guard-check.ps1"
    Suite  = "test\test-status-guard-hook.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "bad-card-not-restored"
           Find = 'Write-StatusGuardFile $file $goodBytes'
           Replace = '$null = $goodBytes' }
        @{ Name = "bad-last-good-restored"
           Find = 'if ((ConvertFrom-HordeFleetStatusBytes -Bytes $goodBytes).problems.Count -eq 0) {'
           Replace = 'if ($true) {' }
        @{ Name = "clean-card-not-copied"
           Find = 'if (-not $same) {'
           Replace = 'if ($false) {' }
        @{ Name = "restore-not-reported"
           Find = '$outcome = ''restored'''
           Replace = '$outcome = ''left''' }
        @{ Name = "bad-card-taken-as-clean"
           Find = 'if ($read.written) {'
           Replace = 'if ($true) {' }
        @{ Name = "bad-card-copied-as-last-good"
           Find = 'if ($check.problems.Count -eq 0) {'
           Replace = 'if ($true) {' }
    )
}
