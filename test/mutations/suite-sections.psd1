# Mutations of the section rules in test/lib/Suite.ps1 (Register-HordeSuiteSections and
# Enter-HordeSuiteSection). Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\suite-sections.psd1
# Each lets a sectioned run lie - a part read as the whole, a typo read as a catch, a declared list that
# differs from the one that runs; test\test-suite.ps1 must fail for every one.
@{
    Target = "test\lib\Suite.ps1"
    Suite  = "test\test-suite.ps1"
    Mutations = @(
        @{ Name = "skipped-run-exits-0"
           Find = '$PassCode = 3'
           Replace = '$PassCode = 0' }
        @{ Name = "selection-ignored"
           Find = '$raw = "$env:HORDE_SECTIONS"'
           Replace = '$raw = ""' }
        @{ Name = "unselected-section-runs"
           Find = '-ccontains $Id) { return $true }'
           Replace = '-ccontains $Id -or $true) { return $true }' }
        @{ Name = "unknown-selection-allowed"
           Find = 'Add-HordeSuiteProblem ("HORDE_SECTIONS names " + $u + ", which is not a section of this suite")'
           Replace = '$null = $u' }
        @{ Name = "unknown-selection-is-a-fail"
           Find = 'Add-HordeSuiteProblem ("HORDE_SECTIONS names " + $u + ", which is not a section of this suite")'
           Replace = 'Check $false ("HORDE_SECTIONS names " + $u + ", which is not a section of this suite")' }
        @{ Name = "empty-selection-is-whole"
           Find = 'if ($script:HordeSuiteSectionsWanted.Count -eq 0) { Add-HordeSuiteProblem ("HORDE_SECTIONS names no section'
           Replace = 'if ($false) { Add-HordeSuiteProblem ("HORDE_SECTIONS names no section' }
        @{ Name = "unentered-section-allowed"
           Find = 'Add-HordeSuiteProblem ("section " + $id + " is declared but was never entered")'
           Replace = '$null = $id' }
        @{ Name = "undeclared-section-runs"
           Find = 'if ($script:HordeSuiteSectionIds -cnotcontains $Id) { Add-HordeSuiteProblem'
           Replace = 'if ($false) { Add-HordeSuiteProblem' }
        @{ Name = "section-entered-twice-allowed"
           Find = 'if ($script:HordeSuiteSectionsEntered -ccontains $Id) {'
           Replace = 'if ($false) {' }
        @{ Name = "declared-twice-allowed"
           Find = 'if ($null -ne $script:HordeSuiteSectionIds) { Add-HordeSuiteProblem "the suite declares its sections more than once"; return }'
           Replace = '' }
        @{ Name = "any-section-id"
           Find = 'if ("$id" -cnotmatch ''^[a-z0-9][a-z0-9-]*\z'')'
           Replace = 'if ($false)' }
        @{ Name = "duplicate-section-id"
           Find = 'elseif ($seen.ContainsKey("$id")) {'
           Replace = 'elseif ($false) {' }
    )
}
