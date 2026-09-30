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
           Find = 'if ($e -is [string]) { if ($Value -is [string] -and $Value -ceq $e) { $ok = $true } }'
           Replace = 'if ($e -is [string]) { if ("$Value" -ceq $e) { $ok = $true } }' }
        @{ Name = "enum-whole-number-matches-its-string"
           Find = 'elseif ((Test-HordeSchemaType -Value $Value -Type "integer") -and [Math]::Abs([double]$Value) -lt 1e19 -and [decimal]$Value -eq [decimal]$e) { $ok = $true }'
           Replace = 'elseif ("$Value" -eq "$e") { $ok = $true }' }
        @{ Name = "enum-boolean-matches-anything"
           Find = 'elseif ($e -is [bool]) { if ($Value -is [bool] -and $Value -eq $e) { $ok = $true } }'
           Replace = 'elseif ($e -is [bool]) { if ($Value -eq $e) { $ok = $true } }' }
        @{ Name = "enum-boolean-refused-in-schema"
           Find = 'if ($e -isnot [string] -and $e -isnot [bool] -and -not $isWhole) { throw'
           Replace = 'if ($e -isnot [string] -and -not $isWhole) { throw' }
        @{ Name = "enum-whole-number-never-matches"
           Find = 'elseif ((Test-HordeSchemaType -Value $Value -Type "integer") -and [Math]::Abs([double]$Value) -lt 1e19 -and [decimal]$Value -eq [decimal]$e) { $ok = $true }'
           Replace = 'elseif ($false) { $ok = $true }' }
        @{ Name = "enum-whole-number-guard-only-not-string"
           Find = '(Test-HordeSchemaType -Value $Value -Type "integer") -and [Math]::Abs('
           Replace = '($Value -isnot [string]) -and [Math]::Abs(' }
        @{ Name = "enum-whole-number-guard-as-number"
           Find = '(Test-HordeSchemaType -Value $Value -Type "integer") -and [Math]::Abs('
           Replace = '(Test-HordeSchemaType -Value $Value -Type "number") -and [Math]::Abs(' }
        @{ Name = "enum-member-int32-only"
           Find = '$isWhole = ($e -is [int] -or $e -is [long])'
           Replace = '$isWhole = ($e -is [int])' }
        @{ Name = "enum-range-guard-removed"
           Find = ' -and [Math]::Abs([double]$Value) -lt 1e19'
           Replace = '' }
        @{ Name = "enum-range-guard-at-decimal-limit"
           Find = '[Math]::Abs([double]$Value) -lt 1e19'
           Replace = '[Math]::Abs([double]$Value) -le [double][decimal]::MaxValue' }
        @{ Name = "enum-accepts-non-string-values"
           Find = 'if ($e -isnot [string] -and $e -isnot [bool] -and -not $isWhole) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "enum-not-checked"
           Find = 'if (-not $ok) { [void]$findings.Add($Path + " is '''
           Replace = 'if ($false) { [void]$findings.Add($Path + " is ''' }
        @{ Name = "pattern-not-checked"
           Find = 'if (-not [regex]::IsMatch($Value, $re, [System.Text.RegularExpressions.RegexOptions]::ECMAScript)) {'
           Replace = 'if ($false) {' }
        @{ Name = "pattern-not-compiled-with-its-node"
           Find = 'if ($kw.ContainsKey("pattern")) {'
           Replace = 'if ($false) {' }
        @{ Name = "pattern-compile-error-swallowed"
           Find = 'catch { throw ("pattern at " + $Path'
           Replace = 'catch { [void]("pattern at " + $Path' }
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
           Find = 'foreach ($f in @(Test-HordeSchema -Value $have[$name] -Schema $props[$name] -Path ($Path + "." + $name) -Root $Root)) { [void]$findings.Add($f) }'
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
           Find = '"number"  { return (Test-HordeSchemaIsNumber $Value) }'
           Replace = '"number"  { return $true }' }
        @{ Name = "number-omits-int16-and-byte"
           Find = '"number"  { return (Test-HordeSchemaIsNumber $Value) }'
           Replace = '"number"  { return ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal] -or $Value -is [single]) }' }
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
        @{ Name = "ref-not-anchored"
           Find = '[regex]::Match($Ref, ''\A#/definitions/([A-Za-z0-9_-]+)\z'')'
           Replace = '[regex]::Match($Ref, ''#/definitions/([A-Za-z0-9_-]+)'')' }
        @{ Name = "missing-definition-yields-nothing"
           Find = 'throw ("the schema''s `$ref ''" + $Ref + "'' names no definition")'
           Replace = 'return $null' }
        @{ Name = "definition-name-ignores-case"
           Find = 'if ($d.Name -ceq $name) { return $d.Value }'
           Replace = 'if ($d.Name -eq $name) { return $d.Value }' }
        @{ Name = "keyword-beside-ref-allowed"
           Find = 'if ($beside.Count -gt 0) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "nested-definitions-allowed"
           Find = 'if ($kw.ContainsKey("definitions") -and -not $atTop) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "circular-ref-followed"
           Find = 'if ($RefsHere -ccontains $ref) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "ref-chain-forgotten"
           Find = '-RefsHere (@($RefsHere) + $ref))'
           Replace = '-RefsHere @())' }
        @{ Name = "ref-non-string-stringified"
           Find = 'if ($kw[''$ref''] -isnot [string]) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "definitions-not-checked"
           Find = 'Assert-HordeSchemaDefinitions -Root $Root'
           Replace = '' }
        @{ Name = "definitions-any-value"
           Find = 'if ($kw.ContainsKey("definitions") -and -not (Test-HordeSchemaType -Value $kw["definitions"] -Type "object")) {'
           Replace = 'if ($false) {' }
        @{ Name = "properties-any-value"
           Find = 'if ($kw.ContainsKey("properties") -and -not (Test-HordeSchemaType -Value $kw["properties"] -Type "object")) {'
           Replace = 'if ($false) {' }
        @{ Name = "type-name-unchecked-without-a-value"
           Find = 'if ($kw.ContainsKey("type") -and $script:HordeSchemaTypes -cnotcontains'
           Replace = 'if ($false -and $script:HordeSchemaTypes -cnotcontains' }
        @{ Name = "definition-walk-skips-properties"
           Find = 'foreach ($p in (Get-HordeSchemaProps $kw["properties"])) { Assert-HordeSchemaNode'
           Replace = 'foreach ($p in @()) { Assert-HordeSchemaNode' }
        @{ Name = "definition-walk-skips-items"
           Find = 'if ($kw.ContainsKey("items")) { Assert-HordeSchemaNode'
           Replace = 'if ($false) { Assert-HordeSchemaNode' }
        @{ Name = "definition-ref-not-resolved"
           Find = '$chain = @()'
           Replace = 'return' }
        @{ Name = "definition-ref-chain-not-walked"
           Find = 'if (-not $targetKw.ContainsKey(''$ref'')) { break }'
           Replace = 'break' }
        @{ Name = "minimum-not-applied"
           Find = 'elseif ((Compare-HordeSchemaNumber $Value $kw["minimum"]) -lt 0) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "minimum-exclusive"
           Find = '(Compare-HordeSchemaNumber $Value $kw["minimum"]) -lt 0)'
           Replace = '(Compare-HordeSchemaNumber $Value $kw["minimum"]) -le 0)' }
        @{ Name = "minimum-compared-as-double"
           Find = '$fa = ConvertTo-HordeSchemaFraction $A'
           Replace = 'return ([double]$A).CompareTo([double]$B); $fa = ConvertTo-HordeSchemaFraction $A' }
        @{ Name = "minimum-compared-as-decimal"
           Find = '$fa = ConvertTo-HordeSchemaFraction $A'
           Replace = 'return ([decimal]$A).CompareTo([decimal]$B); $fa = ConvertTo-HordeSchemaFraction $A' }
        @{ Name = "minimum-schema-value-unchecked"
           Find = 'if (-not $finite) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "minimum-nan-allowed-in-schema"
           Find = ' -and -not (($m -is [double] -or $m -is [single]) -and ([double]::IsNaN([double]$m) -or [double]::IsInfinity([double]$m)))'
           Replace = '' }
        @{ Name = "minimum-fraction-allowed"
           Find = '$sameHoweverWritten = ((Test-HordeSchemaType -Value $m -Type "integer") -and'
           Replace = '$sameHoweverWritten = ($true -and' }
        @{ Name = "minimum-upper-bound-removed"
           Find = ' -and (Compare-HordeSchemaNumber $m $bound) -le 0'
           Replace = '' }
        @{ Name = "minimum-lower-bound-removed"
           Find = ' -and (Compare-HordeSchemaNumber $m (-$bound)) -ge 0'
           Replace = '' }
        @{ Name = "minimum-bound-2-to-the-53"
           Find = '$bound = [long]9007199254740991'
           Replace = '$bound = [long]9007199254740992' }
        @{ Name = "minimum-bound-exclusive"
           Find = '(Compare-HordeSchemaNumber $m $bound) -le 0 -and (Compare-HordeSchemaNumber $m (-$bound)) -ge 0'
           Replace = '(Compare-HordeSchemaNumber $m $bound) -lt 0 -and (Compare-HordeSchemaNumber $m (-$bound)) -gt 0' }
        @{ Name = "minimum-whole-number-rule-not-enforced"
           Find = 'if (-not $sameHoweverWritten) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "minimum-nan-value-accepted"
           Find = '[void]$findings.Add($Path + " is NaN'
           Replace = '[void]($Path + " is NaN' }
        @{ Name = "minimum-applied-to-non-numbers"
           Find = 'if ($kw.ContainsKey("minimum") -and (Test-HordeSchemaIsNumber $Value)) {'
           Replace = 'if ($kw.ContainsKey("minimum") -and $null -ne $Value) {' }
        @{ Name = "minimum-ignores-int16"
           Find = 'return ($Value -is [int] -or $Value -is [long] -or $Value -is [int16] -or $Value -is [byte] -or'
           Replace = 'return ($Value -is [int] -or $Value -is [long] -or' }
        @{ Name = "fraction-double-sign-lost"
           Find = 'if ($bits -lt 0) { $mantissa = [System.Numerics.BigInteger]::Negate($mantissa) }'
           Replace = '' }
        @{ Name = "fraction-decimal-scale-lost"
           Find = '$scale = $text.Length - $point - 1; '
           Replace = '' }
        @{ Name = "fraction-double-implied-bit-lost"
           Find = '$mantissa = [System.Numerics.BigInteger]::Add($mantissa, [System.Numerics.BigInteger]::Pow(2, 52)); '
           Replace = '' }
        @{ Name = "ref-not-followed"
           Find = 'return @(Test-HordeSchema -Value $Value -Schema $target -Path $Path -Root $Root -RefsHere (@($RefsHere) + $ref))'
           Replace = 'return @()' }
        @{ Name = "root-lost-in-properties"
           Find = '-Path ($Path + "." + $name) -Root $Root)'
           Replace = '-Path ($Path + "." + $name))' }
        @{ Name = "root-lost-in-items"
           Find = '-Path ($Path + "[" + $i + "]") -Root $Root)'
           Replace = '-Path ($Path + "[" + $i + "]"))' }
    )
}
