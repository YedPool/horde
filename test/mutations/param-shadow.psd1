# Mutations of the typed-parameter shadow guard (tools/ParamShadow.ps1; PR #111's node serve break).
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\param-shadow.psd1
# test\test-param-shadow.ps1 must fail for each.
@{
    Target = "tools\ParamShadow.ps1"
    Suite  = "test\test-param-shadow.ps1"
    Mutations = @(
        @{ Name = "same-casing-counted"
           Find = 'if ($v -ieq $k -and $v -cne $k) {'
           Replace = 'if ($v -ieq $k) {' }
        @{ Name = "case-sensitive-compare"
           Find = 'if ($v -ieq $k -and $v -cne $k) {'
           Replace = 'if ($v -ceq $k -and $v -cne $k) {' }
        @{ Name = "untyped-counted"
           Find = 'if ($tc.Count -eq 0) { continue }'
           Replace = 'if ($tc.Count -eq 0) { $typed[$p.Name.VariablePath.UserPath] = "object"; continue }' }
        @{ Name = "loose-types-counted"
           Find = 'if ($script:HordeParamShadowLooseTypes -contains $tn.ToLowerInvariant()) { continue }'
           Replace = '' }
        @{ Name = "nested-blocks-mixed"
           Find = 'if ($owner -ne $sb) { continue }'
           Replace = '' }
    )
}
