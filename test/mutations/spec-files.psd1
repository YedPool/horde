# Mutations of the one rule for what a mutation spec is: Get-HordeMutationSpecFiles in
# test\lib\SuiteFiles.ps1, read by test\test-mutation-specs.ps1 and by tools\Mutate.ps1 -Changed.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\spec-files.psd1
# Each narrows or widens the rule; test\test-mutation-specs.ps1 must fail for every one. A spec the
# rule misses is never checked and never selected.
@{
    Target = "test\lib\SuiteFiles.ps1"
    Suite  = "test\test-mutation-specs.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "specs-not-searched-below-root"
           Find = '"*.psd1" -File -Recurse -Force'
           Replace = '"*.psd1" -File -Force' }
        @{ Name = "fixtures-counted-as-specs"
           Find = '$specRel.StartsWith($script:HordeSuiteDataFolder + "/")'
           Replace = '$false' }
        @{ Name = "any-psd1-is-a-spec"
           Find = 'if ($folders -cnotcontains "mutations") { continue }'
           Replace = '' }
        @{ Name = "only-the-nearest-folder-counts"
           Find = '$folders = @($specRel.Split(''/'') | Select-Object -SkipLast 1)'
           Replace = '$folders = @($specRel.Split(''/'') | Select-Object -SkipLast 1 | Select-Object -Last 1)' }
    )
}
