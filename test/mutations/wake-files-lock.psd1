# Mutations of the run lock in core/WakeFiles.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-files-lock.psd1
# The lock is tested where the run is (test\test-wake-run.ps1), so its mutants have a spec of their own:
# a spec names one suite, and the rest of core/WakeFiles.ps1 is held by test\test-wake.ps1.
@{
    Target = "core\WakeFiles.ps1"
    Suite  = "test\test-wake-run.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "lock-shared-for-writing"
           Find = '[System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::Read) }'
           Replace = '[System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::ReadWrite) }' }
        @{ Name = "shadow-and-live-share-one-lock"
           Find = 'if ($Shadow) { $leaf = "run-shadow.lock" }'
           Replace = 'if ($Shadow) { $leaf = "run.lock" }' }
        @{ Name = "a-held-lock-throws-instead-of-answering"
           Find = 'catch [System.IO.IOException] { return $null }'
           Replace = 'catch [System.IO.IOException] { throw }' }
    )
}
