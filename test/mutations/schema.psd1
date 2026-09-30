# Mutations of the schema validator. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\schema.psd1
@{
    Target = "core\Schema.ps1"
    Suite  = "test\test-schema-pane-session.ps1"
    Mutations = @(
        @{ Name = "unknown-keyword-skipped"
           Find = 'if ($script:HordeSchemaKeywords -cnotcontains $p.Name) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "type-not-checked"
           Find = 'if (-not (Test-HordeSchemaType -Value $Value -Type "$($kw[''type''])")) {'
           Replace = 'if ($false) {' }
        @{ Name = "enum-ignores-case"
           Find = 'if ($Value -ceq $e) { $ok = $true }'
           Replace = 'if ($Value -eq $e) { $ok = $true }' }
        @{ Name = "enum-not-checked"
           Find = 'if (-not $ok) { [void]$findings.Add($Path + " is '''
           Replace = 'if ($false) { [void]$findings.Add($Path + " is ''' }
        @{ Name = "pattern-not-checked"
           Find = 'if ($Value -cnotmatch "$($kw[''pattern''])") {'
           Replace = 'if ($false) {' }
        @{ Name = "required-not-checked"
           Find = 'if ($null -ne $r -and -not $have.ContainsKey("$r")) {'
           Replace = 'if ($false) {' }
        @{ Name = "properties-not-recursed"
           Find = 'foreach ($f in @(Test-HordeSchema -Value $have[$name] -Schema $props[$name] -Path ($Path + "." + $name))) { [void]$findings.Add($f) }'
           Replace = '' }
        @{ Name = "additional-properties-ignored"
           Find = '} elseif ($kw.ContainsKey("additionalProperties") -and $kw["additionalProperties"] -eq $false) {'
           Replace = '} elseif ($false) {' }
        @{ Name = "items-not-checked"
           Find = 'if ($Value -is [array] -and $kw.ContainsKey("items")) {'
           Replace = 'if ($false) {' }
        @{ Name = "integer-accepts-string"
           Find = '"integer" { return ($Value -is [int] -or $Value -is [long] -or $Value -is [int16] -or $Value -is [byte]) }'
           Replace = '"integer" { return $true }' }
        @{ Name = "schema-name-unchecked"
           Find = 'if ($Name -cnotmatch ''\A[a-z][a-z0-9-]*\.v[0-9]+\z'') { throw'
           Replace = 'if ($false) { throw' }
    )
}
