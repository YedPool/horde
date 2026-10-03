# Mutations of core/EngineConfig.ps1's secret scanner and redaction (engines E3, review of PR #73).
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\engine-config-secrets.psd1
# test\test-engine-config.ps1 must fail for every one; only its golden and secret sections run here.
@{
    Target = "core\EngineConfig.ps1"
    Suite  = "test\test-engine-config.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1"; HORDE_SECTIONS = "golden,secrets,secret-matrix" }
    PassCodes = @(3)
    Mutations = @(
        @{ Name = "secret-scan-skipped"
           Find = 'foreach ($p in @(Find-HordeSecretPaths -Value $parsed)) {'
           Replace = 'foreach ($p in @()) {' }
        @{ Name = "secret-mixed-token-dropped"
           Find = "if (`$Token -cmatch '[A-Z]' -and `$Token -cmatch '[a-z]' -and `$Token -cmatch '[0-9]') { return `$true }"
           Replace = "if (`$false) { return `$true }" }
        @{ Name = "secret-lower-token-dropped"
           Find = "if (`$Token.Length -ge 40 -and `$Token -cmatch '^[a-z0-9]+`$' -and `$Token -cmatch '[a-z]' -and `$Token -cmatch '[0-9]') { return `$true }"
           Replace = "if (`$false) { return `$true }" }
        @{ Name = "secret-patterns-dropped"
           Find = 'foreach ($pt in $script:HordeSecretPatterns) { $t = [regex]::Replace($t, $pt, $script:HordeRedacted) }'
           Replace = '' }
        @{ Name = "secret-zai-shape-dropped"
           Find = "'[0-9a-fA-F]{32}\.[A-Za-z0-9]{16,}',"
           Replace = "" }
        @{ Name = "secret-hex-shape-dropped"
           Find = "'(?<![0-9A-Za-z])[0-9a-fA-F]{40,}(?![0-9A-Za-z])'"
           Replace = "'(?!)'" }
        @{ Name = "secret-gitlab-shape-dropped"
           Find = "'glpat-[A-Za-z0-9_-]{20,}',"
           Replace = "" }
        @{ Name = "secret-google-oauth-shape-dropped"
           Find = "'ya29\.[A-Za-z0-9_-]{20,}',"
           Replace = "" }
        @{ Name = "secret-key-names-not-scanned"
           Find = 'if (Test-HordeSecretShape -Text $p.Name) { [void]$out.Add($Path + "." + $p.Name) }'
           Replace = '' }
        @{ Name = "findings-not-redacted"
           Find = 'source = (Protect-HordeText $Source); path = (Protect-HordeText $Path); detail = (Protect-HordeText $Detail)'
           Replace = 'source = $Source; path = $Path; detail = $Detail' }
        @{ Name = "finding-detail-not-redacted"
           Find = 'detail = (Protect-HordeText $Detail)'
           Replace = 'detail = $Detail' }
        @{ Name = "layer-label-not-redacted"
           Find = 'throw (Protect-HordeText ("'
           Replace = 'throw (("' }
    )
}
