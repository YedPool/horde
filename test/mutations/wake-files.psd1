# Mutations of core/WakeFiles.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-files.psd1
# Each breaks one rule of the wake folder's files; test\test-wake.ps1 must fail for every one.
@{
    Target = "core\WakeFiles.ps1"
    Suite  = "test\test-wake.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "unknown-journaled-every-pass"
           Find = '-and "$($Unknown["$($e.id)"])" -ceq "$($e.reason)") { continue }'
           Replace = '-and $false) { continue }' }
    )
}
