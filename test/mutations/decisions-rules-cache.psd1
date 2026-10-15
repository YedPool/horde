# Mutations of the kept checks in decisions/Rules.ps1 (THE CHECKS OF A RECORD ARE KEPT, T-0166). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-rules-cache.psd1
# Each breaks one promise of that cache; test\test-decisions-store-cache.ps1 must fail for every one.
@{
    Target = "decisions\Rules.ps1"
    Suite  = "test\test-decisions-store-cache.ps1"
    Mutations = @(
        @{ Name = "checks-reused-across-definitions"
           Find = 'if ($null -eq $held -or -not [object]::ReferenceEquals($held.definitions, $Definitions)) {'
           Replace = 'if ($null -eq $held) {' }
        @{ Name = "checks-of-gone-records-kept"
           Find = '$script:HordeDecisionCheckCache.Remove($k)'
           Replace = '$null = $k' }
        @{ Name = "checks-of-other-stores-let-go"
           Find = 'if (-not $seen.ContainsKey($k) -and $folders.ContainsKey($k.Substring(0, $k.IndexOf("|") + 1))) {'
           Replace = 'if (-not $seen.ContainsKey($k)) {' }
        @{ Name = "no-check-is-kept"
           Find = 'if ($null -eq $Record.PSObject.Properties["stamp"] -or "$($Record.stamp)" -eq "") { return $null }'
           Replace = 'return $null' }
    )
}
