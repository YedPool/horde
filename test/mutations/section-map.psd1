# Mutations of test/lib/SuiteSections.ps1: what sections a suite declares, and whether a mutant's map
# names only those. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\section-map.psd1
# Each lets a wrong map through - one that would run nothing, run the wrong part, or read as a catch;
# test\test-mutation-specs.ps1 must fail for every one.
@{
    Target = "test\lib\SuiteSections.ps1"
    Suite  = "test\test-mutation-specs.ps1"
    Mutations = @(
        @{ Name = "no-declaration-allowed"
           Find = 'if (-not $Declared.ok) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "undeclared-name-allowed"
           Find = 'if ($Declared.ids -cnotcontains $n) {'
           Replace = 'if ($false) {' }
        @{ Name = "empty-map-allowed"
           Find = 'if ($names.Count -eq 0) { return "its Sections names no section" }'
           Replace = '' }
        @{ Name = "outside-spec-filter-allowed"
           Find = 'if ($filter -cnotcontains $n) {'
           Replace = 'if ($false) {' }
        @{ Name = "computed-list-read"
           Find = 'if ($computed.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "second-declaration-ignored"
           Find = 'if ($calls.Count -gt 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "positional-list-read"
           Find = 'if ($null -eq $arg) { return [pscustomobject]@{ ok = $false; ids = @(); error = "declares its sections without -Ids" } }'
           Replace = 'if ($null -eq $arg) { $arg = $els[1] }' }
        @{ Name = "no-declaration-is-empty"
           Find = 'if ($calls.Count -eq 0) { return [pscustomobject]@{ ok = $false; ids = @(); error = "declares no sections" } }'
           Replace = 'if ($calls.Count -eq 0) { return [pscustomobject]@{ ok = $true; ids = @(); error = "" } }' }
    )
}
