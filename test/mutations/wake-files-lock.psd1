# Mutations of the run lock in core/WakeFiles.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-files-lock.psd1
# The lock is tested where the run is (test\test-wake-run.ps1), so its mutants have a spec of their own:
# a spec names one suite, and the rest of core/WakeFiles.ps1 is held by test\test-wake.ps1.
@{
    Target = "core\WakeFiles.ps1"
    Suite  = "test\test-wake-run.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "the-lock-is-per-mode-again"
           Find = '$leaf = "run-" + (Get-HordeWakeSendWord -Mode (Get-HordeWakeModeWord -Mode $Mode -Shadow:$Shadow)) + ".lock"'
           Replace = '$leaf = "run-" + (Get-HordeWakeModeWord -Mode $Mode -Shadow:$Shadow) + ".lock"' }
        @{ Name = "any-io-failure-is-a-held-lock"
           Find = 'if ($win32 -eq 32 -or $win32 -eq 33) { return $true }'
           Replace = 'return $true' }
        @{ Name = "lock-violation-not-a-held-lock"
           Find = 'if ($win32 -eq 32 -or $win32 -eq 33) { return $true }'
           Replace = 'if ($win32 -eq 32) { return $true }' }
        @{ Name = "wrapped-violation-not-seen"
           Find = '$e = $e.InnerException'
           Replace = '$e = $null' }
        @{ Name = "held-lock-thrown-instead-of-answered"
           Find = 'if (Test-HordeWakeSharingViolation $_.Exception) { return $null }'
           Replace = '' }
        @{ Name = "lock-shared-for-writing"
           Find = '[System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::Read) }'
           Replace = '[System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::ReadWrite) }' }
        @{ Name = "every-mode-shares-one-lock"
           Find = '$leaf = "run-" + (Get-HordeWakeSendWord -Mode (Get-HordeWakeModeWord -Mode $Mode -Shadow:$Shadow)) + ".lock"'
           Replace = '$leaf = "run-live.lock"' }
    )
}
