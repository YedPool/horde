# Mutations of core/PermissionLevels.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\permission-levels.psd1
# Each breaks one rule the vocabulary exists for; test\test-permission-levels.ps1 must fail for every
# one of them. The rules that matter most downstream: the order is the file's order (R9 compares
# ranks), a name is matched exactly (a ceiling is never satisfied by a near spelling), anything
# outside the list is unknown and never the lowest or highest level, and a mapping written for
# another vocabulary fails coverage (engines E2).
@{
    Target = "core\PermissionLevels.ps1"
    Suite  = "test\test-permission-levels.ps1"
    Mutations = @(
        @{ Name = "rank-ignores-order"
           Find = '[void]$out.Add([pscustomobject]@{ name = $table.levels[$i].name; rank = $i;'
           Replace = '[void]$out.Add([pscustomobject]@{ name = $table.levels[$i].name; rank = 0;' }
        @{ Name = "not-an-object-accepted"
           Find = 'if ($Table -isnot [System.Management.Automation.PSCustomObject]) {'
           Replace = 'if ($false) {' }
        @{ Name = "extra-root-key-ignored"
           Find = 'foreach ($k in $keys) { if ($k -cne "levels") {'
           Replace = 'foreach ($k in $keys) { if ($false) {' }
        @{ Name = "missing-levels-key-accepted"
           Find = 'if (-not ($keys -ccontains "levels")) {'
           Replace = 'if ($false) {' }
        @{ Name = "not-a-list-accepted"
           Find = 'if ($list -isnot [System.Array]) {'
           Replace = 'if ($false) {' }
        @{ Name = "empty-list-accepted"
           Find = 'if ($list.Count -eq 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "row-not-an-object-accepted"
           Find = 'if ($row -isnot [System.Management.Automation.PSCustomObject]) {'
           Replace = 'if ($false) {' }
        @{ Name = "extra-row-key-ignored"
           Find = 'foreach ($k in $rowKeys) { if ($k -cne "name" -and $k -cne "meaning") {'
           Replace = 'foreach ($k in $rowKeys) { if ($false) {' }
        @{ Name = "name-pattern-unchecked"
           Find = 'if ($name -isnot [string] -or $name -cnotmatch $script:HordePermissionLevelNamePattern) {'
           Replace = 'if ($name -isnot [string]) {' }
        @{ Name = "name-pattern-ignores-case"
           Find = '$name -cnotmatch $script:HordePermissionLevelNamePattern'
           Replace = '$name -notmatch $script:HordePermissionLevelNamePattern' }
        @{ Name = "name-type-unchecked"
           Find = 'if ($name -isnot [string] -or $name -cnotmatch'
           Replace = 'if ("$name" -cnotmatch "^[a-z0-9-]{0,32}$" -and $name -cnotmatch' }
        @{ Name = "duplicate-accepted"
           Find = '} elseif (-not $seen.Add($name)) {'
           Replace = '} elseif ($false) {' }
        @{ Name = "blank-meaning-accepted"
           Find = 'if ($meaning -isnot [string] -or $meaning.Trim() -eq "") {'
           Replace = 'if ($meaning -isnot [string]) {' }
        @{ Name = "non-ascii-meaning-accepted"
           Find = 'if (-not (Test-HordePermissionLevelPrintable -Text $meaning)) {'
           Replace = 'if ($false) {' }
        @{ Name = "long-meaning-accepted"
           Find = 'if ($meaning.Length -gt $script:HordePermissionLevelMeaningMax) {'
           Replace = 'if ($false) {' }
        @{ Name = "long-meaning-off-by-one"
           Find = '$script:HordePermissionLevelMeaningMax = 200'
           Replace = '$script:HordePermissionLevelMeaningMax = 199' }
        @{ Name = "flag-accepted"
           Find = 'if ($meaning -cmatch $script:HordePermissionLevelFlagPattern) {'
           Replace = 'if ($false) {' }
        @{ Name = "short-flag-missed"
           Find = '$script:HordePermissionLevelFlagPattern = ''(^|[^A-Za-z0-9])(--?|/)[A-Za-z]'''
           Replace = '$script:HordePermissionLevelFlagPattern = ''(^|[^A-Za-z0-9])(--|/)[A-Za-z]''' }
        @{ Name = "flag-inside-word-matched"
           Find = '$script:HordePermissionLevelFlagPattern = ''(^|[^A-Za-z0-9])(--?|/)[A-Za-z]'''
           Replace = '$script:HordePermissionLevelFlagPattern = ''(--?|/)[A-Za-z]''' }
        @{ Name = "flag-only-after-space"
           Find = '$script:HordePermissionLevelFlagPattern = ''(^|[^A-Za-z0-9])(--?|/)[A-Za-z]'''
           Replace = '$script:HordePermissionLevelFlagPattern = ''(^|\s)(--?|/)[A-Za-z]''' }
        @{ Name = "slash-flag-missed"
           Find = '$script:HordePermissionLevelFlagPattern = ''(^|[^A-Za-z0-9])(--?|/)[A-Za-z]'''
           Replace = '$script:HordePermissionLevelFlagPattern = ''(^|[^A-Za-z0-9])--?[A-Za-z]''' }
        @{ Name = "load-skips-table-check"
           Find = 'if ($problems.Count -gt 0) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "load-skips-byte-check"
           Find = 'foreach ($b in $bytes) { if ($b -gt 0x7F) {'
           Replace = 'foreach ($b in $bytes) { if ($false) {' }
        @{ Name = "rank-ignores-case"
           Find = 'if ($Levels[$i].name -ceq $Name) {'
           Replace = 'if ($Levels[$i].name -eq $Name) {' }
        @{ Name = "rank-trims-name"
           Find = 'if ($Levels[$i].name -ceq $Name) {'
           Replace = 'if ($Levels[$i].name -ceq $Name.Trim()) {' }
        @{ Name = "rank-from-a-row-field"
           Find = 'return (New-HordeKnown -Value $i)'
           Replace = '$rankProp = $Levels[$i].PSObject.Properties["rank"]; $rankValue = 0; if ($null -ne $rankProp) { $rankValue = [int]$rankProp.Value }; return (New-HordeKnown -Value $rankValue)' }
        @{ Name = "no-name-is-lowest"
           Find = 'return (New-HordeUnknown -Reason ("no permission level was given; the levels are " + $known))'
           Replace = 'return (New-HordeKnown -Value 0)' }
        @{ Name = "unknown-name-is-highest"
           Find = 'return (New-HordeUnknown -Reason ((Format-HordePermissionLevelQuote -Text $Name) + " is not a Horde permission level; the levels are " + $known))'
           Replace = 'return (New-HordeKnown -Value ($Levels.Count - 1))' }
        @{ Name = "unknown-reason-unnamed"
           Find = 'return (New-HordeUnknown -Reason ((Format-HordePermissionLevelQuote -Text $Name) + " is not a Horde permission level; the levels are " + $known))'
           Replace = 'return (New-HordeUnknown -Reason "not a Horde permission level")' }
        @{ Name = "reason-quotes-anything-long"
           Find = 'if ($Text.Length -le $script:HordePermissionLevelQuoteMax -and (Test-HordePermissionLevelPrintable -Text $Text)) {'
           Replace = 'if (Test-HordePermissionLevelPrintable -Text $Text) {' }
        @{ Name = "reason-quotes-control-characters"
           Find = 'if ($Text.Length -le $script:HordePermissionLevelQuoteMax -and (Test-HordePermissionLevelPrintable -Text $Text)) {'
           Replace = 'if ($Text.Length -le $script:HordePermissionLevelQuoteMax) {' }
        @{ Name = "allowed-refuses-at-the-ceiling"
           Find = 'return (New-HordeKnown -Value ([bool]($req.value -le $cap.value)))'
           Replace = 'return (New-HordeKnown -Value ([bool]($req.value -lt $cap.value)))' }
        @{ Name = "allowed-compares-backwards"
           Find = 'return (New-HordeKnown -Value ([bool]($req.value -le $cap.value)))'
           Replace = 'return (New-HordeKnown -Value ([bool]($req.value -ge $cap.value)))' }
        @{ Name = "allowed-clamps-to-the-ceiling"
           Find = 'return (New-HordeKnown -Value ([bool]($req.value -le $cap.value)))'
           Replace = 'return (New-HordeKnown -Value $true)' }
        @{ Name = "allowed-unknown-request-admitted"
           Find = 'if ($req.state -cne "known") { return (New-HordeUnknown -Reason ("the requested permission level is not known: " + $req.reason)) }'
           Replace = 'if ($req.state -cne "known") { return (New-HordeKnown -Value $true) }' }
        @{ Name = "allowed-unknown-ceiling-admitted"
           Find = 'if ($cap.state -cne "known") { return (New-HordeUnknown -Reason ("the permission ceiling is not known: " + $cap.reason)) }'
           Replace = 'if ($cap.state -cne "known") { return (New-HordeKnown -Value $true) }' }
        @{ Name = "duplicate-key-accepted"
           Find = 'if ($null -ne $dup) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "duplicate-key-escapes-not-decoded"
           Find = 'if ($e -ceq ''u'' -and $i + 5 -lt $n) {'
           Replace = 'if ($false) {' }
        @{ Name = "duplicate-key-escaped-quote-ends-string"
           Find = 'if ($Text[$i] -ceq ''\'' -and $i + 1 -lt $n) {'
           Replace = 'if ($false) {' }
        @{ Name = "duplicate-key-not-scoped-to-its-object"
           Find = '$top = $stack[$stack.Count - 1]'
           Replace = '$top = $stack[0]' }
        @{ Name = "bom-not-named"
           Find = 'if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF'
           Replace = 'if ($false -and $bytes[0] -eq 0xEF' }
        @{ Name = "name-length-unbounded"
           Find = '$script:HordePermissionLevelNamePattern = ''^[a-z][a-z0-9-]{0,31}$'''
           Replace = '$script:HordePermissionLevelNamePattern = ''^[a-z][a-z0-9-]*$''' }
        @{ Name = "name-may-start-with-digit-or-hyphen"
           Find = '$script:HordePermissionLevelNamePattern = ''^[a-z][a-z0-9-]{0,31}$'''
           Replace = '$script:HordePermissionLevelNamePattern = ''^[a-z0-9-]{1,32}$''' }
        @{ Name = "control-characters-printable"
           Find = 'if ([int]$c -lt 0x20 -or [int]$c -gt 0x7E) {'
           Replace = 'if ([int]$c -gt 0x7E) {' }
        @{ Name = "coverage-no-mapping-is-one-empty-level"
           Find = 'if ($null -eq $Mapped) { $Mapped = @() }'
           Replace = '' }
        @{ Name = "coverage-trims-mapping"
           Find = '$s = "$m"'
           Replace = '$s = "$m".Trim()' }
        @{ Name = "coverage-missing-ignored"
           Find = '$missing = @($names | Where-Object { -not $counts.ContainsKey($_) })'
           Replace = '$missing = @()' }
        @{ Name = "coverage-unknown-ignored"
           Find = 'if (-not $nameSet.Contains($s)) { [void]$unknown.Add($s) }'
           Replace = '' }
        @{ Name = "coverage-duplicate-ignored"
           Find = 'if ($counts[$s] -eq 2) { [void]$duplicate.Add($s) }'
           Replace = '' }
        @{ Name = "coverage-ignores-case"
           Find = '$nameSet = New-Object ''System.Collections.Generic.HashSet[string]'' ([System.StringComparer]::Ordinal)'
           Replace = '$nameSet = New-Object ''System.Collections.Generic.HashSet[string]'' ([System.StringComparer]::OrdinalIgnoreCase)' }
        @{ Name = "coverage-ok-ignores-duplicates"
           Find = '$ok = ($missing.Count -eq 0 -and $unknown.Count -eq 0 -and $duplicate.Count -eq 0)'
           Replace = '$ok = ($missing.Count -eq 0 -and $unknown.Count -eq 0)' }
    )
}
