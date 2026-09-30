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
           Find = 'if ($Value -is [string] -and $Value -ceq $e) { $ok = $true }'
           Replace = 'if ($Value -is [string] -and $Value -eq $e) { $ok = $true }' }
        @{ Name = "enum-matches-non-string"
           Find = 'if ($Value -is [string] -and $Value -ceq $e) { $ok = $true }'
           Replace = 'if ("$Value" -ceq $e) { $ok = $true }' }
        @{ Name = "enum-accepts-non-string-values"
           Find = 'if ($e -isnot [string]) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "enum-not-checked"
           Find = 'if (-not $ok) { [void]$findings.Add($Path + " is '''
           Replace = 'if ($false) { [void]$findings.Add($Path + " is ''' }
        @{ Name = "pattern-not-checked"
           Find = 'if (-not [regex]::IsMatch($Value, $re, [System.Text.RegularExpressions.RegexOptions]::ECMAScript)) {'
           Replace = 'if ($false) {' }
        @{ Name = "pattern-dollar-kept"
           Find = 'elseif ($c -ceq ''$'') { [void]$sb.Append(''\z''); continue }'
           Replace = '' }
        @{ Name = "pattern-escape-not-skipped"
           Find = 'if ($i + 1 -lt $Pattern.Length) { $i++; [void]$sb.Append($Pattern[$i]) }'
           Replace = '' }
        @{ Name = "pattern-class-not-tracked"
           Find = 'elseif ($c -ceq ''['') { $inClass = $true }'
           Replace = '' }
        @{ Name = "pattern-dotnet-dialect"
           Find = '[regex]::IsMatch($Value, $re, [System.Text.RegularExpressions.RegexOptions]::ECMAScript)'
           Replace = '[regex]::IsMatch($Value, $re, [System.Text.RegularExpressions.RegexOptions]::None)' }
        @{ Name = "pattern-ignores-case"
           Find = '[regex]::IsMatch($Value, $re, [System.Text.RegularExpressions.RegexOptions]::ECMAScript)'
           Replace = '[regex]::IsMatch($Value, $re, ([System.Text.RegularExpressions.RegexOptions]::ECMAScript -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase))' }
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
        @{ Name = "value-keys-ignore-case"
           Find = '$have = New-Object ''System.Collections.Generic.Dictionary[string,object]'' ([System.StringComparer]::Ordinal)'
           Replace = '$have = New-Object ''System.Collections.Generic.Dictionary[string,object]'' ([System.StringComparer]::OrdinalIgnoreCase)' }
        @{ Name = "property-names-ignore-case"
           Find = '$props = New-Object ''System.Collections.Generic.Dictionary[string,object]'' ([System.StringComparer]::Ordinal)'
           Replace = '$props = New-Object ''System.Collections.Generic.Dictionary[string,object]'' ([System.StringComparer]::OrdinalIgnoreCase)' }
        @{ Name = "non-object-schema-accepted"
           Find = 'if (-not ($Schema -is [System.Management.Automation.PSCustomObject] -or $Schema -is [System.Collections.IDictionary])) {'
           Replace = 'if ($false) {' }
        @{ Name = "additional-properties-any-value"
           Find = 'if ($kw.ContainsKey("additionalProperties") -and $kw["additionalProperties"] -isnot [bool]) {'
           Replace = 'if ($false) {' }
        @{ Name = "schema-name-unchecked"
           Find = 'if ($Name -cnotmatch ''\A[a-z][a-z0-9-]*\.v[0-9]+\z'') { throw'
           Replace = 'if ($false) { throw' }
    )
}
