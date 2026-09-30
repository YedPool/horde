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
           Find = 'if ($Value -is [System.Collections.IList] -and $kw.ContainsKey("items")) {'
           Replace = 'if ($false) {' }
        @{ Name = "integer-accepts-string"
           Find = 'if ($Value -is [int] -or $Value -is [long] -or $Value -is [int16] -or $Value -is [byte]) { return $true }'
           Replace = 'return $true' }
        @{ Name = "integer-refuses-decimal"
           Find = 'if ($Value -is [decimal]) { return ($Value -eq [decimal]::Truncate($Value)) }'
           Replace = '' }
        @{ Name = "integer-accepts-decimal-fraction"
           Find = 'return ($Value -eq [decimal]::Truncate($Value))'
           Replace = 'return $true' }
        @{ Name = "integer-refuses-double"
           Find = 'if ($Value -is [double] -or $Value -is [single]) {'
           Replace = 'if ($false) {' }
        @{ Name = "integer-accepts-double-fraction"
           Find = '-and $d -eq [Math]::Truncate($d))'
           Replace = ')' }
        @{ Name = "array-type-only-dotnet-array"
           Find = '"array"   { return ($Value -is [System.Collections.IList]) }'
           Replace = '"array"   { return ($Value -is [array]) }' }
        @{ Name = "items-only-dotnet-array"
           Find = 'if ($Value -is [System.Collections.IList] -and $kw.ContainsKey("items")) {'
           Replace = 'if ($Value -is [array] -and $kw.ContainsKey("items")) {' }
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
        @{ Name = "x-keys-not-ignored"
           Find = 'if ($p.Name -like "x-*") { continue }'
           Replace = 'if ($false) { continue }' }
        @{ Name = "absent-additional-properties-read-as-false"
           Find = '} elseif ($kw.ContainsKey("additionalProperties") -and $kw["additionalProperties"] -eq $false) {'
           Replace = '} elseif (-not $kw.ContainsKey("additionalProperties") -or $kw["additionalProperties"] -eq $false) {' }
        @{ Name = "type-string-accepts-anything"
           Find = '"string"  { return ($Value -is [string]) }'
           Replace = '"string"  { return $true }' }
        @{ Name = "type-boolean-accepts-anything"
           Find = '"boolean" { return ($Value -is [bool]) }'
           Replace = '"boolean" { return $true }' }
        @{ Name = "type-null-accepts-anything"
           Find = '"null"    { return ($null -eq $Value) }'
           Replace = '"null"    { return $true }' }
        @{ Name = "type-number-accepts-anything"
           Find = '"number"  { return ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal] -or $Value -is [single]) }'
           Replace = '"number"  { return $true }' }
        @{ Name = "type-array-accepts-anything"
           Find = '"array"   { return ($Value -is [System.Collections.IList]) }'
           Replace = '"array"   { return $true }' }
        @{ Name = "type-object-accepts-anything"
           Find = '"object"  { return ($Value -is [System.Management.Automation.PSCustomObject] -or $Value -is [System.Collections.IDictionary]) }'
           Replace = '"object"  { return $true }' }
        @{ Name = "hashtable-schema-read-as-object"
           Find = 'if ($Node -is [System.Collections.IDictionary]) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "hashtable-value-read-as-object"
           Find = 'if ($Value -is [System.Collections.IDictionary]) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "schema-read-as-ansi"
           Find = '[System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)'
           Replace = '(Get-Content -LiteralPath $Path -Raw)' }
        @{ Name = "schema-name-unchecked"
           Find = 'if ($Name -cnotmatch ''\A[a-z][a-z0-9-]*\.v[0-9]+\z'') { throw'
           Replace = 'if ($false) { throw' }
    )
}
