# Mutations of the section map in tools\Mutate.ps1: a mutant runs only the sections its spec maps it to,
# and a map can never hide a survivor. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\mutate-sections.psd1
# Each lets a mapped run lie - a survivor reported without the whole suite, a part read as the whole, a
# wrong map run instead of refused; test\test-mutate.ps1 must fail for every one.
@{
    Target = "tools\Mutate.ps1"
    Suite  = "test\test-mutate.ps1"
    # Stop at the first failed check: a caught mutant needs nothing more.
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "survivor-not-rerun-whole"
           Find = 'if ($row.outcome -eq "survived") {'
           Replace = 'if ($false) {' }
        @{ Name = "rerun-keeps-the-map"
           Find = '$rerun = Invoke-HordeSuite -Path $suite -Seconds $TimeoutSeconds -Selection $wholeSelection'
           Replace = '$rerun = Invoke-HordeSuite -Path $suite -Seconds $TimeoutSeconds -Selection $row.sections' }
        @{ Name = "sectioned-exit-3-not-a-pass"
           Find = '-PassCodes (@($passCodes) + 3)'
           Replace = '-PassCodes $passCodes' }
        @{ Name = "map-miss-not-named"
           Find = '$row.mapMiss = ($row.outcome -eq "caught")'
           Replace = '$row.mapMiss = $false' }
        @{ Name = "map-miss-not-counted"
           Find = '$mapMisses++'
           Replace = '' }
        @{ Name = "map-misses-off-the-result-line"
           Find = ' + ", map misses: " + $mapMisses)'
           Replace = ')' }
        @{ Name = "selection-never-passed"
           Find = 'if ($Selection -ne "") { $psi.EnvironmentVariables["HORDE_SECTIONS"] = $Selection }'
           Replace = '' }
        @{ Name = "inherited-selection-kept"
           Find = 'if ($psi.EnvironmentVariables.ContainsKey("HORDE_SECTIONS")) { $psi.EnvironmentVariables.Remove("HORDE_SECTIONS") }'
           Replace = '' }
        @{ Name = "wrong-map-run"
           Find = 'elseif ($mapWhy) { $row.outcome = ("invalid: " + $mapWhy) }'
           Replace = '' }
        @{ Name = "map-ignored"
           Find = 'if (-not $mapWhy) { $row.sections ='
           Replace = 'if ($false) { $row.sections =' }
        @{ Name = "spec-filter-not-whole"
           Find = 'if ($specEnv.ContainsKey("HORDE_SECTIONS")) { $wholeSelection = "$($specEnv.HORDE_SECTIONS)" }'
           Replace = '' }
        @{ Name = "crash-reads-as-catch"
           Find = 'if (@(Get-HordeFailLines -Out $Run.out).Count -gt 0) { return "caught" }'
           Replace = 'return "caught"' }
        @{ Name = "pass-reads-as-catch"
           Find = 'if ($PassCodes -contains $Run.code) { return "survived" }'
           Replace = '' }
    )
}
