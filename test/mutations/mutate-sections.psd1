# Mutations of the section map in tools\Mutate.ps1: the whole suite decides every verdict unless the
# caller says -Fast, and a -Fast result can never be read as a gate's.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\mutate-sections.psd1
# Each lets a mapped run lie - a map used in a plain run, a survivor reported without the whole suite,
# a part read as the whole, a wrong map run instead of refused, a fast result shaped like a gate's;
# test\test-mutate.ps1 must fail for every one.
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
        @{ Name = "maps-line-not-printed"
           Find = 'if ($mapped -gt 0) { Write-Host ("maps: sectioned "'
           Replace = 'if ($false) { Write-Host ("maps: sectioned "' }
        @{ Name = "map-hides-not-counted"
           Find = '$mapHides++'
           Replace = '' }
        @{ Name = "sectioned-runs-not-counted"
           Find = 'if ($r.sectioned) { $sectioned++ }'
           Replace = '' }
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
        @{ Name = "map-baseline-skipped"
           Find = '$selBase = Invoke-HordeSuite -Path $suite -Seconds $TimeoutSeconds -Selection $sel'
           Replace = '$selBase = [pscustomobject]@{ code = 3; out = ""; timedOut = $false }' }
        @{ Name = "map-baseline-accepts-a-failure"
           Find = 'if ((@($PassCodes) + 3) -notcontains $Run.code) { return ("exited " + $Run.code) }'
           Replace = '' }
        @{ Name = "after-map-baseline-skipped"
           Find = '$selAfter = Invoke-HordeSuite -Path $suite -Seconds $TimeoutSeconds -Selection $sel'
           Replace = '$selAfter = $selBase' }
        @{ Name = "map-baseline-ignores-errors"
           Find = 'if (@(($Run.out -split "`r?`n") | Where-Object { $_ -match ''^\s*\[(FAIL|ERROR)\]'' }).Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "rerun-accepts-exit-3"
           Find = '$row.outcome = Get-HordeRunOutcome -Run $rerun -PassCodes $passCodes -Seconds $TimeoutSeconds'
           Replace = '$row.outcome = Get-HordeRunOutcome -Run $rerun -PassCodes (@($passCodes) + 3) -Seconds $TimeoutSeconds' }
        @{ Name = "timeout-reads-survived"
           Find = 'if ($Run.timedOut) { return ("timed out after " + $Seconds + "s - not a catch") }'
           Replace = 'if ($Run.timedOut) { return "survived" }' }
        @{ Name = "mapped-catch-not-verified"
           Find = '} elseif ($row.outcome -eq "caught" -and $confirmCatches) {'
           Replace = '} elseif ($false) {' }
        @{ Name = "verify-env-ignored"
           Find = '$confirmCatches = ($VerifyMaps -or $verifyEnv -ceq "1")'
           Replace = '$confirmCatches = [bool]$VerifyMaps' }
        @{ Name = "verify-switch-ignored"
           Find = '$confirmCatches = ($VerifyMaps -or $verifyEnv -ceq "1")'
           Replace = '$confirmCatches = ($verifyEnv -ceq "1")' }
        # The finding that blocked the first form (review of #115, round 3, F1): with a map used in a
        # plain run, a catch only a section makes is reported caught, exit 0.
        @{ Name = "map-used-without-fast"
           Find = '$useMaps = [bool]$Fast'
           Replace = '$useMaps = $true' }
        @{ Name = "sections-run-without-fast"
           Find = 'if ($row.sections -and $useMaps) {'
           Replace = 'if ($row.sections) {' }
        @{ Name = "map-baselines-run-without-fast"
           Find = 'if ($useMaps) { $selections = @('
           Replace = 'if ($true) { $selections = @(' }
        @{ Name = "verify-env-any-value-accepted"
           Find = 'if (@("", "0", "1") -cnotcontains $verifyEnv) {'
           Replace = 'if ($false) {' }
        @{ Name = "verify-env-zero-refused"
           Find = 'if (@("", "0", "1") -cnotcontains $verifyEnv) {'
           Replace = 'if (@("", "1") -cnotcontains $verifyEnv) {' }
        @{ Name = "verify-env-refusal-on-stdout"
           Find = '[Console]::Error.WriteLine("  HORDE_MUTATE_VERIFY_MAPS is'
           Replace = '[Console]::Out.WriteLine("  HORDE_MUTATE_VERIFY_MAPS is' }
        @{ Name = "fast-result-line-classic-shaped"
           Find = 'if ($unverified -gt 0) { $resultHead ='
           Replace = 'if ($false) { $resultHead =' }
        @{ Name = "map-counts-back-on-the-result-line"
           Find = 'Write-Host ($resultHead + $results.Count + ", as expected: " + ($results.Count - $bad) + ", not: " + $bad)'
           Replace = 'Write-Host ($resultHead + $results.Count + ", as expected: " + ($results.Count - $bad) + ", not: " + $bad + ", map misses: " + $mapMisses)' }
        @{ Name = "whole-verdict-ignored"
           Find = 'else { $row.outcome = $wholeOutcome; $row.failures = @(Get-HordeFailLines -Out $confirm.out); $row.mapHides = $true }'
           Replace = 'else { $row.mapHides = $true }' }
        @{ Name = "unverified-not-counted"
           Find = '$where += " unverified: the whole suite was not run"; $unverified++'
           Replace = '$where += " unverified: the whole suite was not run"' }
        @{ Name = "map-hides-not-named"
           Find = 'if ($r.mapHides) {'
           Replace = 'if ($false) {' }
        @{ Name = "crash-reads-as-catch"
           Find = 'if (@(Get-HordeFailLines -Out $Run.out).Count -gt 0) { return "caught" }'
           Replace = 'return "caught"' }
        @{ Name = "pass-reads-as-catch"
           Find = 'if ($PassCodes -contains $Run.code) { return "survived" }'
           Replace = '' }
    )
}
