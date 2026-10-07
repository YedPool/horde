# Mutations of decisions/Settings.ps1, the reader of the decisions module's settings table. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-settings-reader.psd1
# Each lets a wrong table, or a wrong name, through; test\test-decisions-settings.ps1 must fail for
# every one.
@{
    Target = "decisions\Settings.ps1"
    Suite  = "test\test-decisions-settings.ps1"
    Mutations = @(
        @{ Name = "unknown-name-reads-as-nothing"
           Find = 'if (-not $script:HordeDecisionSettings.ContainsKey($Name)) { throw ('
           Replace = 'if (-not $script:HordeDecisionSettings.ContainsKey($Name)) { return [long]0 }; if ($false) { throw (' }
        @{ Name = "name-matched-ignoring-case"
           Find = '$out = New-Object ''System.Collections.Generic.Dictionary[string,object]'' ([System.StringComparer]::Ordinal)'
           Replace = '$out = New-Object ''System.Collections.Generic.Dictionary[string,object]'' ([System.StringComparer]::OrdinalIgnoreCase)' }
        @{ Name = "table-of-another-version-read"
           Find = 'if ($null -eq $versionProp -or $versionProp.Value -ne 1 -or $null -eq $settingsProp'
           Replace = 'if ($null -eq $versionProp -or $null -eq $settingsProp' }
        @{ Name = "settings-that-are-not-an-object-read"
           Find = '-or $settingsProp.Value -isnot [System.Management.Automation.PSCustomObject]) {'
           Replace = ') {' }
        @{ Name = "name-of-another-module-taken"
           Find = 'if ($name -cnotmatch $script:HordeDecisionSettingNamePattern) { throw ('
           Replace = 'if ($false) { throw (' }
        @{ Name = "number-that-is-not-whole-taken"
           Find = 'if ($null -eq $p -or -not ($p.Value -is [int] -or $p.Value -is [long])) { throw ('
           Replace = 'if ($null -eq $p) { throw (' }
        @{ Name = "missing-limit-taken"
           Find = 'if ($null -eq $p -or -not ($p.Value -is [int] -or $p.Value -is [long])) { throw ('
           Replace = 'if ($null -eq $p) { continue }; if (-not ($p.Value -is [int] -or $p.Value -is [long])) { throw (' }
        @{ Name = "meaning-not-required"
           Find = 'if ($null -eq $meansProp -or $meansProp.Value -isnot [string] -or "$($meansProp.Value)".Trim() -eq "") { throw ('
           Replace = 'if ($false) { throw (' }
        @{ Name = "blank-meaning-taken"
           Find = 'if ($null -eq $meansProp -or $meansProp.Value -isnot [string] -or "$($meansProp.Value)".Trim() -eq "") { throw ('
           Replace = 'if ($null -eq $meansProp -or $meansProp.Value -isnot [string]) { throw (' }
        @{ Name = "upside-down-range-taken"
           Find = 'if ($numbers["least"] -gt $numbers["most"]) { throw ('
           Replace = 'if ($false) { throw (' }
        @{ Name = "default-below-its-range-taken"
           Find = 'if ($numbers["default"] -lt $numbers["least"] -or $numbers["default"] -gt $numbers["most"]) {'
           Replace = 'if ($numbers["default"] -gt $numbers["most"]) {' }
        @{ Name = "default-above-its-range-taken"
           Find = 'if ($numbers["default"] -lt $numbers["least"] -or $numbers["default"] -gt $numbers["most"]) {'
           Replace = 'if ($numbers["default"] -lt $numbers["least"]) {' }
        @{ Name = "default-at-the-end-of-its-range-refused"
           Find = 'if ($numbers["default"] -lt $numbers["least"] -or $numbers["default"] -gt $numbers["most"]) {'
           Replace = 'if ($numbers["default"] -le $numbers["least"] -or $numbers["default"] -ge $numbers["most"]) {' }
        @{ Name = "empty-table-read"
           Find = 'if ($out.Count -eq 0) { throw ('
           Replace = 'if ($false) { throw (' }
        @{ Name = "table-handed-out-in-no-order"
           Find = 'return @($script:HordeDecisionSettings.Keys | Sort-Object | ForEach-Object { $script:HordeDecisionSettings[$_] })'
           Replace = 'return @($script:HordeDecisionSettings.Keys | Sort-Object -Descending | ForEach-Object { $script:HordeDecisionSettings[$_] })' }
    )
}
