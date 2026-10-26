# Mutations of core/NightlyNet.ps1's night floors and suite-phase run limits (T-0331, 2026-10-26). Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\nightly-floors.psd1
@{
    Target = "core\NightlyNet.ps1"
    Suite  = "test\test-nightly-apps.ps1"
    Mutations = @(
        @{ Name = "night-floor-never-used"
           Find = 'if (-not $night -or -not $f.freeGB.ContainsKey($Kind)) {'
           Replace = 'if ($true) {' }
        @{ Name = "night-runs-into-seven"
           Find = '$night = ($h -ge $f.startHour -or $h -lt $f.endHour)'
           Replace = '$night = ($h -ge $f.startHour -or $h -le $f.endHour)' }
        @{ Name = "suite-cutoff-ignored"
           Find = 'if ($Now.AddSeconds($WaitSeconds) -gt $SuiteCutoff) { return 0 }'
           Replace = '' }
        @{ Name = "run-limit-never-fitted"
           Find = 'if ($left -ge [math]::Min($MinSeconds, $RunSeconds)) { return $left }'
           Replace = '' }
        @{ Name = "run-limit-fitted-below-the-minimum"
           Find = 'if ($left -ge [math]::Min($MinSeconds, $RunSeconds)) { return $left }'
           Replace = 'if ($left -gt 0) { return $left }' }
    )
}
