# Mutations of the legacy image list's data. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\process-image-legacy.psd1
# Each makes tools\process-image-legacy.txt say something other than what the tree holds;
# test\test-host-names.ps1 must fail for every one, on its real-repository check.
@{
    Target = "tools\process-image-legacy.txt"
    Suite  = "test\test-host-names.ps1"
    Mutations = @(
        @{ Name = "reader-dropped"
           Find = "core/Faults.ps1 | 1 |"
           Replace = "core/Unrelated.ps1 | 1 |" }
        @{ Name = "count-raised"
           Find = "core/Identity.ps1 | 4 |"
           Replace = "core/Identity.ps1 | 5 |" }
        @{ Name = "count-lowered"
           Find = "core/Identity.ps1 | 4 |"
           Replace = "core/Identity.ps1 | 3 |" }
    )
}
