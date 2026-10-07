# Mutations of the section trap check in test/lib/SuiteSections.ps1 (Get-HordeSectionTrapProblems).
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\section-traps.psd1
# Each lets a section without its own trap line through, or blames a block that is no section;
# test\test-suite.ps1 must fail for every one.
@{
    Target = "test\lib\SuiteSections.ps1"
    Suite  = "test\test-suite.ps1"
    Mutations = @(
        @{ Name = "trapless-section-passes"
           Find = 'if ($traps.Count -ne 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "any-if-is-a-section"
           Find = 'if ($cond -notmatch ''^\s*Enter-HordeSuiteSection\s+"([^"]*)"'') { continue }'
           Replace = 'if ($false) { continue }' }
    )
}
