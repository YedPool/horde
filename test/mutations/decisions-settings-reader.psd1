# Mutations of decisions/Settings.ps1, the reader of the decisions module's settings table. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-settings-reader.psd1
# Each lets a wrong table, a wrong name or a wrong override through; test\test-decisions-settings.ps1
# must fail for every one.
@{
    Target = "decisions\Settings.ps1"
    Suite  = "test\test-decisions-settings.ps1"
    Mutations = @(
        # --- a name ---
        @{ Name = "unknown-name-reads-as-nothing"
           Find = 'if (-not $script:HordeDecisionSettings.ContainsKey($Name)) { throw ('
           Replace = 'if (-not $script:HordeDecisionSettings.ContainsKey($Name)) { return [long]0 }; if ($false) { throw (' }
        @{ Name = "name-matched-ignoring-case"
           Find = '    $out = New-Object ''System.Collections.Generic.Dictionary[string,object]'' ([System.StringComparer]::Ordinal)'
           Replace = '    $out = New-Object ''System.Collections.Generic.Dictionary[string,object]'' ([System.StringComparer]::OrdinalIgnoreCase)' }
        @{ Name = "name-of-another-module-taken"
           Find = 'if ($name -cnotmatch $script:HordeDecisionSettingNamePattern) { throw ('
           Replace = 'if ($false) { throw (' }
        @{ Name = "whole-number-handed-out-as-it-was-parsed"
           Find = 'if ("$($script:HordeDecisionSettings[$Name].kind)" -ceq "whole-number") { return [long]$value }'
           Replace = '' }
        @{ Name = "table-handed-out-in-no-order"
           Find = 'return @($script:HordeDecisionSettings.Keys | Sort-Object | ForEach-Object { $script:HordeDecisionSettings[$_] })'
           Replace = 'return @($script:HordeDecisionSettings.Keys | Sort-Object -Descending | ForEach-Object { $script:HordeDecisionSettings[$_] })' }
        # --- the table ---
        @{ Name = "text-that-is-not-json-quoted-by-the-parser"
           Find = 'try { $table = (ConvertFrom-HordeJson $Text) } catch { throw ($From + " is not JSON") }'
           Replace = '$table = (ConvertFrom-HordeJson $Text)' }
        @{ Name = "table-of-another-version-read"
           Find = 'if ($null -eq $versionProp -or $versionProp.Value -ne 1 -or $null -eq $settingsProp -or $settingsProp.Value -isnot [System.Management.Automation.PSCustomObject]) {'
           Replace = 'if ($null -eq $versionProp -or $null -eq $settingsProp -or $settingsProp.Value -isnot [System.Management.Automation.PSCustomObject]) {' }
        @{ Name = "settings-that-are-not-an-object-read"
           Find = 'if ($null -eq $versionProp -or $versionProp.Value -ne 1 -or $null -eq $settingsProp -or $settingsProp.Value -isnot [System.Management.Automation.PSCustomObject]) {'
           Replace = 'if ($null -eq $versionProp -or $versionProp.Value -ne 1 -or $null -eq $settingsProp) {' }
        @{ Name = "bare-value-taken-as-an-entry"
           Find = 'if ($entry -isnot [System.Management.Automation.PSCustomObject]) { throw ('
           Replace = 'if ($false) { throw (' }
        @{ Name = "kind-not-required"
           Find = '-or -not $script:HordeDecisionSettingKinds.Contains("$($kindProp.Value)")) {'
           Replace = ') {' }
        @{ Name = "meaning-not-required"
           Find = 'if ($null -eq $meansProp -or $meansProp.Value -isnot [string] -or "$($meansProp.Value)".Trim() -eq "") { throw ('
           Replace = 'if ($false) { throw (' }
        @{ Name = "blank-meaning-taken"
           Find = 'if ($null -eq $meansProp -or $meansProp.Value -isnot [string] -or "$($meansProp.Value)".Trim() -eq "") { throw ('
           Replace = 'if ($null -eq $meansProp -or $meansProp.Value -isnot [string]) { throw (' }
        @{ Name = "default-not-required"
           Find = 'if ($null -eq $defaultProp) { throw ('
           Replace = 'if ($null -eq $defaultProp) { $defaultProp = [pscustomobject]@{ Value = 5 } }; if ($false) { throw (' }
        @{ Name = "limit-not-required"
           Find = 'if ($null -eq $p -or -not (Test-HordeDecisionSettingNumber -Value $p.Value -Whole:($kind -cne "fraction"))) { throw ('
           Replace = 'if ($false) { throw (' }
        @{ Name = "limit-of-a-whole-number-need-not-be-whole"
           Find = 'if ($null -eq $p -or -not (Test-HordeDecisionSettingNumber -Value $p.Value -Whole:($kind -cne "fraction"))) { throw ('
           Replace = 'if ($null -eq $p -or -not (Test-HordeDecisionSettingNumber -Value $p.Value)) { throw (' }
        @{ Name = "upside-down-range-taken"
           Find = 'if ([double]$least -gt [double]$most) { throw ('
           Replace = 'if ($false) { throw (' }
        @{ Name = "default-not-held-to-its-kind-and-range"
           Find = '        if ($wrong -ne "") { throw ("the setting ''" + $name + "'' has a default that " + $wrong) }'
           Replace = '' }
        @{ Name = "empty-table-read"
           Find = 'if ($out.Count -eq 0) { throw ('
           Replace = 'if ($false) { throw (' }
        # --- a value, held to its kind and its range: for a default and for an override alike ---
        @{ Name = "whole-number-need-not-be-whole"
           Find = 'if (-not (Test-HordeDecisionSettingNumber -Value $Value -Whole)) { return "is not a whole number" }'
           Replace = 'if (-not (Test-HordeDecisionSettingNumber -Value $Value)) { return "is not a whole number" }' }
        @{ Name = "text-converted-to-a-number"
           Find = '    if ($Value -is [int] -or $Value -is [long]) { return $true }'
           Replace = '    if ($Value -is [int] -or $Value -is [long] -or ($Value -is [string] -and $Value -match "\A[0-9]+\z")) { return $true }' }
        @{ Name = "whole-number-below-its-range-taken"
           Find = 'if ([long]$Value -lt [long]$Entry.least -or [long]$Value -gt [long]$Entry.most) {'
           Replace = 'if ([long]$Value -gt [long]$Entry.most) {' }
        @{ Name = "whole-number-above-its-range-taken"
           Find = 'if ([long]$Value -lt [long]$Entry.least -or [long]$Value -gt [long]$Entry.most) {'
           Replace = 'if ([long]$Value -lt [long]$Entry.least) {' }
        @{ Name = "whole-number-at-the-end-of-its-range-refused"
           Find = 'if ([long]$Value -lt [long]$Entry.least -or [long]$Value -gt [long]$Entry.most) {'
           Replace = 'if ([long]$Value -le [long]$Entry.least -or [long]$Value -ge [long]$Entry.most) {' }
        @{ Name = "fraction-outside-its-range-taken"
           Find = 'if ([double]$Value -lt [double]$Entry.least -or [double]$Value -gt [double]$Entry.most) {'
           Replace = 'if ($false) {' }
        @{ Name = "fraction-need-not-be-a-number"
           Find = 'if (-not (Test-HordeDecisionSettingNumber -Value $Value)) { return "is not a number" }'
           Replace = '' }
        @{ Name = "one-is-true"
           Find = 'if ($Value -isnot [bool]) { return "is not true or false" }'
           Replace = 'if ($Value -isnot [bool] -and $Value -isnot [int]) { return "is not true or false" }' }
        @{ Name = "text-need-not-be-text"
           Find = 'if ($Value -isnot [string]) { return "is not text" }'
           Replace = 'if ($false) { return "is not text" }' }
        @{ Name = "text-of-any-length-taken"
           Find = 'if ($Value.Length -lt [long]$Entry.least -or $Value.Length -gt [long]$Entry.most) {'
           Replace = 'if ($false) {' }
        @{ Name = "relative-folder-taken"
           Find = 'if (-not [System.IO.Path]::IsPathRooted($Value)) { return "is not an absolute folder" }'
           Replace = '' }
        # --- an override: one that fails its checks is refused, with every problem named, and no default stands in ---
        @{ Name = "override-not-laid-over-the-defaults"
           Find = '        $values[$name] = $prop.Value'
           Replace = '' }
        @{ Name = "wrong-value-skipped-and-its-default-used"
           Find = '    if ($findings.Count -gt 0) { return [pscustomobject]@{ state = "refused"; values = $null; findings = @($findings) } }'
           Replace = '' }
        @{ Name = "refused-override-still-hands-out-values"
           Find = '    if ($findings.Count -gt 0) { return [pscustomobject]@{ state = "refused"; values = $null; findings = @($findings) } }'
           Replace = '    if ($findings.Count -gt 0) { return [pscustomobject]@{ state = "refused"; values = $values; findings = @($findings) } }' }
        @{ Name = "only-the-first-problem-named"
           Find = '        if ($wrong -ne "") { [void]$findings.Add($From + ": ''" + $name + "'' " + $wrong); continue }'
           Replace = '        if ($wrong -ne "") { [void]$findings.Add($From + ": ''" + $name + "'' " + $wrong); break }' }
        @{ Name = "wrong-value-used-as-it-is"
           Find = '        if ($wrong -ne "") { [void]$findings.Add($From + ": ''" + $name + "'' " + $wrong); continue }'
           Replace = '' }
        @{ Name = "problem-does-not-name-its-file"
           Find = '        if ($wrong -ne "") { [void]$findings.Add($From + ": ''" + $name + "'' " + $wrong); continue }'
           Replace = '        if ($wrong -ne "") { [void]$findings.Add("''" + $name + "'' " + $wrong); continue }' }
        @{ Name = "key-that-is-no-setting-ignored"
           Find = '            [void]$findings.Add($From + ": " + $shown + " is not a setting of the decisions module")'
           Replace = '' }
        @{ Name = "odd-key-in-an-override-repeated"
           Find = 'if ($name -cmatch ''\A[A-Za-z][A-Za-z0-9.]{0,99}\z'') { $shown ='
           Replace = 'if ($true) { $shown =' }
        @{ Name = "override-of-another-version-used"
           Find = 'if ($null -eq $versionProp -or $versionProp.Value -ne 1 -or $null -eq $valuesProp -or $valuesProp.Value -isnot [System.Management.Automation.PSCustomObject]) {'
           Replace = 'if ($null -eq $valuesProp -or $valuesProp.Value -isnot [System.Management.Automation.PSCustomObject]) {' }
        @{ Name = "text-that-is-no-override-falls-back-to-the-defaults"
           Find = '        return [pscustomobject]@{ state = "refused"; values = $null; findings = @($From + ": it is not an object with schemaVersion 1 and a values object") }'
           Replace = '        return [pscustomobject]@{ state = "ok"; values = $values; findings = @() }' }
        @{ Name = "resolving-changes-the-table"
           Find = '        $values[$name] = $prop.Value'
           Replace = '        $values[$name] = $prop.Value; $Table[$name].default = $prop.Value' }
        # --- the override file under the home ---
        @{ Name = "override-file-never-read"
           Find = '    if (-not [System.IO.File]::Exists($path)) { return (Resolve-HordeDecisionSettings -Table $script:HordeDecisionSettings) }'
           Replace = '    if ($true) { return (Resolve-HordeDecisionSettings -Table $script:HordeDecisionSettings) }' }
        @{ Name = "refused-override-hands-out-the-default"
           Find = '    if ($now.state -cne "ok") { throw ('
           Replace = '    if ($now.state -cne "ok") { return [long]$script:HordeDecisionSettings[$Name].default }; if ($false) { throw (' }
        @{ Name = "refusal-does-not-name-the-file"
           Find = '    return (Resolve-HordeDecisionSettings -Table $script:HordeDecisionSettings -OverrideText $text -From $path)'
           Replace = '    return (Resolve-HordeDecisionSettings -Table $script:HordeDecisionSettings -OverrideText $text)' }
        @{ Name = "override-looked-for-somewhere-else"
           Find = '    return (Join-Path (Join-Path (Get-HordeHome) "settings") "decisions.json")'
           Replace = '    return (Join-Path (Join-Path (Get-HordeHome) "store") "decisions.json")' }
        @{ Name = "problem-not-there-to-be-asked-for"
           Find = '    if ($now.state -ceq "ok") { return "" }'
           Replace = '    return ""' }
    )
}
