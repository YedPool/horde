# Mutations of the -Changed half of tools\Mutate.ps1: its refusals, its plan, its exit codes and the
# one result line a gate reads.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\mutate-changed-driver.psd1
# The copy that runs the mutants is the unmutated tool; the mutant is the copy the suite puts in its
# fixture repository. test\test-mutate-changed.ps1 must fail for every one.
@{
    Target = "tools\Mutate.ps1"
    Suite  = "test\test-mutate-changed.ps1"
    # Stop at the first failed check: a caught mutant needs nothing more.
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "zero-selection-exits-0"
           Find = 'if (-not $verdict.ok) { Write-Host ("  -Changed: " + $verdict.message) -ForegroundColor Red; exit 2 }'
           Replace = '' }
        @{ Name = "plan-prints-a-result"
           Find = 'if ($Plan) { Write-Host "changed: plan only - nothing was run"; exit 0 }'
           Replace = 'if ($Plan) { Write-Host "mutations: 0"; exit 0 }' }
        @{ Name = "only-with-changed-allowed"
           Find = 'if ($Only.Count -gt 0) { Write-Host "  -Only and -Changed both choose the mutants; give one" -ForegroundColor Red; exit 2 }'
           Replace = '' }
        @{ Name = "failed-mutants-exit-0"
           Find = 'if ($worst -ne 0 -or $notSum -gt 0) { exit 1 }'
           Replace = '' }
        @{ Name = "spec-result-relayed-unindented"
           Find = 'if ($l -match ''^(mutations[ :]|maps: )'') { Write-Host ("  " + $so.spec + ": " + $l) } else { Write-Host $l }'
           Replace = 'Write-Host $l' }
        @{ Name = "changed-spec-not-reselected"
           Find = 'specChanged = $diff.changed.ContainsKey($relKey) }'
           Replace = 'specChanged = $false }' }
        @{ Name = "spec-argument-ignored"
           Find = '        $specRels = @($Spec)'
           Replace = '        $specRels = @(Get-HordeMutationSpecFiles -Root $repo | ForEach-Object { $_.FullName.Substring($repoLen) })' }
        @{ Name = "zero-line-carries-a-number"
           Find = 'Write-Host ("mutations: none selected - "'
           Replace = 'Write-Host ("mutations: 0 - "' }
        # -Changed verifies unless its caller said -Fast, and then says so on its total.
        @{ Name = "changed-always-fast"
           Find = 'if ($Fast) { $childArgs.Fast = $true }'
           Replace = '$childArgs.Fast = $true' }
        @{ Name = "changed-fast-not-passed-down"
           Find = 'if ($Fast) { $childArgs.Fast = $true }'
           Replace = '' }
        @{ Name = "fast-spec-result-not-read"
           Find = 'elseif ($mFast.Success) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "unverified-catches-not-summed"
           Find = 'elseif ($mFast.Success) { $unverifiedSum += [int]$mFast.Groups[1].Value;'
           Replace = 'elseif ($mFast.Success) {' }
        @{ Name = "fast-total-classic-shaped"
           Find = 'if ($unverifiedSum -gt 0) { $totalHead ='
           Replace = 'if ($false) { $totalHead =' }
        @{ Name = "map-totals-not-printed"
           Find = 'if ($mapLines -gt 0) { Write-Host ("maps: sectioned "'
           Replace = 'if ($false) { Write-Host ("maps: sectioned "' }
        @{ Name = "map-hides-not-summed"
           Find = '$hideSum += [int]$mMaps.Groups[3].Value'
           Replace = '$hideSum += 0' }
    )
}
