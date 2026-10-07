# decisions/Settings.ps1 - the decisions module's tunable numbers, read from one table.
#
# THE ONE JOB of this file is to hand out a setting by its name. The table is decisions/settings.json:
# every number the module can be tuned by, with its default, its range and what it means. No other
# file of the module writes such a number down; decisions/Store.ps1 and decisions/Operations.ps1 ask
# here, at the moment they need one.
#
# WHY NOT core/config-keys.json. That registry (core/EngineConfig.ps1) holds what an engine rule may
# SET for a session - a profile, a model, a permission - resolved per target through layers L0 to L5,
# and its value kinds are a name, a model and an enum. It has no kind for a number and no notion of a
# module's own default, so a wait in milliseconds cannot be declared there today. Until a settings
# unit can hold one, the defaults live in this one table, named as that registry names its keys
# (dotted, module first), so that lifting them is moving the entries and changing the one function
# below - no caller changes.
#
# THE TABLE IS DATA, NOT CODE, as decisions/question-kinds.json is: a page in a window, or a settings
# unit, can read the very file this reads.
#
# A TABLE THAT IS WRONG IS REFUSED WHOLE, at the first setting asked for: a default outside its own
# range, a range that is upside down, a number that is not whole. A wait of -1 or a width of 0.5
# would otherwise surface far from here, as a hang or a file name.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

$script:HordeDecisionSettings = $null
$script:HordeDecisionSettingNamePattern = '\Adecisions(\.[a-z][A-Za-z0-9]{0,39}){2}\z'

function Read-HordeDecisionSettingsFile {
    # The settings table from -Path, checked, as a hashtable of name -> { default; least; most; means }.
    param([Parameter(Mandatory = $true)][string]$Path)
    $table = ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
    $versionProp = $table.PSObject.Properties["schemaVersion"]
    $settingsProp = $table.PSObject.Properties["settings"]
    if ($null -eq $versionProp -or $versionProp.Value -ne 1 -or $null -eq $settingsProp -or $settingsProp.Value -isnot [System.Management.Automation.PSCustomObject]) {
        throw ("'" + (Split-Path -Leaf $Path) + "' is not a settings table this version reads: it needs schemaVersion 1 and a settings object")
    }
    # Ordinal: a name is matched exactly, so 'decisions.store.maxgap' is not a setting.
    $out = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
    foreach ($prop in @($settingsProp.Value.PSObject.Properties)) {
        $name = "$($prop.Name)"
        if ($name -cnotmatch $script:HordeDecisionSettingNamePattern) { throw ("the setting '" + $name + "' is not named decisions.<part>.<name>") }
        $entry = $prop.Value
        $numbers = @{}
        foreach ($member in @("default", "least", "most")) {
            $p = $null
            if ($entry -is [System.Management.Automation.PSCustomObject]) { $p = $entry.PSObject.Properties[$member] }
            # A whole number, and one a 64-bit integer holds: ConvertFrom-Json reads 1.5 as a Decimal
            # and 1e30 as a Double, and neither is a count.
            if ($null -eq $p -or -not ($p.Value -is [int] -or $p.Value -is [long])) { throw ("the setting '" + $name + "' has no whole number for '" + $member + "'") }
            $numbers[$member] = [long]$p.Value
        }
        $meansProp = $entry.PSObject.Properties["means"]
        if ($null -eq $meansProp -or $meansProp.Value -isnot [string] -or "$($meansProp.Value)".Trim() -eq "") { throw ("the setting '" + $name + "' does not say what it means") }
        if ($numbers["least"] -gt $numbers["most"]) { throw ("the setting '" + $name + "' has a range that is upside down: " + $numbers["least"] + " to " + $numbers["most"]) }
        if ($numbers["default"] -lt $numbers["least"] -or $numbers["default"] -gt $numbers["most"]) {
            throw ("the setting '" + $name + "' has the default " + $numbers["default"] + ", outside its own range of " + $numbers["least"] + " to " + $numbers["most"])
        }
        $out[$name] = [pscustomobject]@{ name = $name; default = $numbers["default"]; least = $numbers["least"]; most = $numbers["most"]; means = "$($meansProp.Value)" }
    }
    if ($out.Count -eq 0) { throw ("'" + (Split-Path -Leaf $Path) + "' names no setting") }
    return $out
}

function Get-HordeDecisionSettingTable {
    # Every setting, as { name; default; least; most; means }, in name order: for a caller that shows
    # them (a help text, a settings page). Read once for the process.
    if ($null -eq $script:HordeDecisionSettings) { $script:HordeDecisionSettings = Read-HordeDecisionSettingsFile -Path (Join-Path $PSScriptRoot "settings.json") }
    return @($script:HordeDecisionSettings.Keys | Sort-Object | ForEach-Object { $script:HordeDecisionSettings[$_] })
}

function Get-HordeDecisionSetting {
    # The value of one setting, as a 64-bit whole number. Today that is its default; a settings unit
    # that lets a person change one changes this function and nothing that calls it.
    # A name the table does not have THROWS: a misspelt name must never read as 0 or as nothing.
    param([Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $script:HordeDecisionSettings) { $null = Get-HordeDecisionSettingTable }
    if (-not $script:HordeDecisionSettings.ContainsKey($Name)) { throw ("'" + $Name + "' is not a setting of the decisions module (decisions/settings.json)") }
    return [long]$script:HordeDecisionSettings[$Name].default
}
