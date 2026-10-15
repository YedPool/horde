# decisions/Settings.ps1 - the decisions module's settings, read from one table.
#
# THE ONE JOB of this file is to hand out a setting by its name. The table is decisions/settings.json:
# everything the module can be tuned by, each entry with its kind, its default, the range a value may
# be in, and what it is. No other file of the module writes such a value down; decisions/Store.ps1 and
# decisions/Operations.ps1 ask here, at the moment they need one.
#
# WHY NOT core/config-keys.json. That registry (core/EngineConfig.ps1) holds what an engine rule may
# SET for a session - a profile, a model, a permission - resolved per target through layers L0 to L5,
# and its value kinds are a name, a model and an enum. It has no kind for a number and no notion of a
# module's own default, so a wait in milliseconds cannot be declared there.
#
# SHAPED FOR A GENERAL SETTINGS UNIT THAT DOES NOT EXIST YET, and depending on none. The shape is the
# one such a unit is expected to read: a defaults table per module, and an override per module laid
# over it. So:
#   - AN ENTRY IS name, kind, default, least and most (the allowed range), and means. The kinds are
#     text, whole-number, fraction, true-false and folder. Every setting of this module is a whole
#     number today; the other kinds are read and checked all the same, so that the table's shape is
#     not this module's alone.
#   - READING IS PURE GIVEN THE TEXT. ConvertFrom-HordeDecisionSettingsText and
#     Resolve-HordeDecisionSettings take text and give values; neither opens a file, reads the
#     environment or a clock. Only Get-HordeDecisionSetting, and what it calls, reads files.
#   - AN OVERRIDE IS LAID OVER THE DEFAULTS, AND ONE THAT FAILS ITS CHECKS IS REFUSED. The rule, which
#     the general unit takes too: an override file that fails its checks refuses with a reason and
#     NEVER SILENTLY FALLS BACK TO THE DEFAULTS. A person who wrote 5 where only 10 to 100 is allowed
#     must be told so - not handed the default without a word, which would look exactly like being
#     obeyed. So a value of the wrong kind or outside its range, a key the table does not have, or
#     text that is no override at all refuses the WHOLE override, naming every problem (the file, the
#     key, why); no setting is handed out from it, the wrong ones or the right ones, and no default
#     stands in. With NO override file the defaults table is used: that is not a fallback, it is
#     what was asked for.
#   - THE OVERRIDE FILE IS <HordeHome>\settings\decisions.json, the place the general unit gives a
#     module's override. Get-HordeDecisionSetting reads it, if it is there, every time it is asked:
#     a small file, and a process that stays up sees a change without being restarted.
# WHEN THAT UNIT LANDS: decisions/settings.json becomes its defaults table for this module (moved or
# pointed at, entry for entry); the pure functions here are replaced by its reader; and
# Get-HordeDecisionSetting and Get-HordeDecisionSettingsProblem become calls to it. Nothing that calls
# those two changes.
#
# THE SHIPPED TABLE BEING WRONG IS A DEFECT, NOT A SETTING: a default outside its own range, a range
# upside down, a kind nobody knows. That is refused whole, at the first setting asked for.
#
# THE TABLE IS DATA, NOT CODE, as decisions/question-kinds.json is: a page in a window can read it.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Home.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\JsonText.ps1")

$script:HordeDecisionSettings = $null
$script:HordeDecisionSettingNamePattern = '\Adecisions(\.[a-z][A-Za-z0-9]{0,39}){2}\z'
# THE KINDS a setting can be. ranged: whether least and most are numbers the value must lie between
# (for text they are the fewest and the most characters; a true-false and a folder have no range).
$script:HordeDecisionSettingKinds = [ordered]@{
    "text"         = @{ ranged = $true }
    "whole-number" = @{ ranged = $true }
    "fraction"     = @{ ranged = $true }
    "true-false"   = @{ ranged = $false }
    "folder"       = @{ ranged = $false }
}

function Get-HordeDecisionSettingKinds { return @($script:HordeDecisionSettingKinds.Keys) }

function Test-HordeDecisionSettingNumber {
    # Is a parsed JSON value a number, and for -Whole a whole one a 64-bit integer holds? Windows
    # PowerShell 5.1's ConvertFrom-Json reads 5 as Int32, 5000000000 as Int64, 1.5 as Decimal and 1e30
    # as Double; text and true are never numbers here, and are never converted into one.
    param($Value, [switch]$Whole)
    if ($Value -is [int] -or $Value -is [long]) { return $true }
    if ($Whole) { return $false }
    return ($Value -is [decimal] -or $Value -is [double] -or $Value -is [single])
}

function Get-HordeDecisionSettingValueProblem {
    # Why a value does not fit an entry of the table - its kind, or its range - as the end of a
    # sentence, or "" when it fits. Used for a default (where a problem is a defect) and for an
    # override (where it is reported and the default used), so the two cannot be judged differently.
    # A value is never converted to make it fit: "5" is not 5.
    param($Entry, $Value)
    $kind = "$($Entry.kind)"
    if ($kind -ceq "whole-number") {
        if (-not (Test-HordeDecisionSettingNumber -Value $Value -Whole)) { return "is not a whole number" }
        if ([long]$Value -lt [long]$Entry.least -or [long]$Value -gt [long]$Entry.most) { return ("is " + $Value + ", outside the range " + $Entry.least + " to " + $Entry.most) }
        return ""
    }
    if ($kind -ceq "fraction") {
        if (-not (Test-HordeDecisionSettingNumber -Value $Value)) { return "is not a number" }
        if ([double]$Value -lt [double]$Entry.least -or [double]$Value -gt [double]$Entry.most) { return ("is " + $Value + ", outside the range " + $Entry.least + " to " + $Entry.most) }
        return ""
    }
    if ($kind -ceq "true-false") {
        if ($Value -isnot [bool]) { return "is not true or false" }
        return ""
    }
    if ($kind -ceq "text") {
        if ($Value -isnot [string]) { return "is not text" }
        if ($Value.Length -lt [long]$Entry.least -or $Value.Length -gt [long]$Entry.most) { return ("is " + $Value.Length + " characters long, outside the range " + $Entry.least + " to " + $Entry.most) }
        return ""
    }
    if ($kind -ceq "folder") {
        # A folder is named, never looked for: reading a setting touches no disk.
        if ($Value -isnot [string] -or $Value.Trim() -eq "") { return "is not the name of a folder" }
        if (-not [System.IO.Path]::IsPathRooted($Value)) { return "is not an absolute folder" }
        return ""
    }
    return ("is of the kind '" + $kind + "', which is not a kind of setting")
}

function ConvertFrom-HordeDecisionSettingsText {
    # The settings table from its text, checked, as name -> { name; kind; default; least; most; means }.
    # PURE: text in, table out. -From names the text in a refusal (a file's name, say). A table that is
    # wrong is refused whole, by the name of the setting that is.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text, [string]$From = "the settings table")
    $table = $null
    try { $table = (ConvertFrom-HordeJson $Text) } catch { throw ($From + " is not JSON") }
    $versionProp = $null; $settingsProp = $null
    if ($table -is [System.Management.Automation.PSCustomObject]) { $versionProp = $table.PSObject.Properties["schemaVersion"]; $settingsProp = $table.PSObject.Properties["settings"] }
    if ($null -eq $versionProp -or $versionProp.Value -ne 1 -or $null -eq $settingsProp -or $settingsProp.Value -isnot [System.Management.Automation.PSCustomObject]) {
        throw ($From + " is not a settings table this version reads: it needs schemaVersion 1 and a settings object")
    }
    # Ordinal: a name is matched exactly, so 'decisions.store.maxgap' is not a setting.
    $out = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
    foreach ($prop in @($settingsProp.Value.PSObject.Properties)) {
        $name = "$($prop.Name)"
        if ($name -cnotmatch $script:HordeDecisionSettingNamePattern) { throw ("the setting '" + $name + "' is not named decisions.<part>.<name>") }
        $entry = $prop.Value
        if ($entry -isnot [System.Management.Automation.PSCustomObject]) { throw ("the setting '" + $name + "' is not an entry with a kind, a default and what it means") }
        $kindProp = $entry.PSObject.Properties["kind"]
        if ($null -eq $kindProp -or $kindProp.Value -isnot [string] -or -not $script:HordeDecisionSettingKinds.Contains("$($kindProp.Value)")) {
            throw ("the setting '" + $name + "' has no kind this version knows; the kinds are: " + (@($script:HordeDecisionSettingKinds.Keys) -join ", "))
        }
        $kind = "$($kindProp.Value)"
        $meansProp = $entry.PSObject.Properties["means"]
        if ($null -eq $meansProp -or $meansProp.Value -isnot [string] -or "$($meansProp.Value)".Trim() -eq "") { throw ("the setting '" + $name + "' does not say what it means") }
        $defaultProp = $entry.PSObject.Properties["default"]
        if ($null -eq $defaultProp) { throw ("the setting '" + $name + "' has no default") }
        $least = $null; $most = $null
        if ([bool]$script:HordeDecisionSettingKinds[$kind].ranged) {
            foreach ($end in @("least", "most")) {
                $p = $entry.PSObject.Properties[$end]
                # A text's range is a count of characters, and a whole number's is whole.
                if ($null -eq $p -or -not (Test-HordeDecisionSettingNumber -Value $p.Value -Whole:($kind -cne "fraction"))) { throw ("the setting '" + $name + "' has no number for '" + $end + "', the " + $end + " a value may be") }
            }
            $least = $entry.least; $most = $entry.most
            if ([double]$least -gt [double]$most) { throw ("the setting '" + $name + "' has a range that is upside down: " + $least + " to " + $most) }
        }
        $made = [pscustomobject]@{ name = $name; kind = $kind; default = $defaultProp.Value; least = $least; most = $most; means = "$($meansProp.Value)" }
        $wrong = Get-HordeDecisionSettingValueProblem -Entry $made -Value $made.default
        if ($wrong -ne "") { throw ("the setting '" + $name + "' has a default that " + $wrong) }
        $out[$name] = $made
    }
    if ($out.Count -eq 0) { throw ($From + " names no setting") }
    return $out
}

function Resolve-HordeDecisionSettings {
    # The value of every setting: its default, or the override's value where the override gives one.
    # PURE: a table (ConvertFrom-HordeDecisionSettingsText) and the override's text in,
    # { state; values; findings } out. -OverrideText is JSON, { "schemaVersion": 1, "values":
    # { name: value } }, or "" for no override; -From names the override in a finding (its file).
    #   state ok       values holds every setting; findings is empty.
    #   state refused  THE OVERRIDE FAILED ITS CHECKS. values is $null - nothing is handed out, and no
    #                  default stands in for a wrong value - and findings names EVERY problem: the
    #                  file, the key, and why. One wrong entry refuses the whole override.
    # A finding never repeats a text value, nor a key that is not shaped like a setting's name: what a
    # person typed into a settings file may be what must not be printed.
    param([Parameter(Mandatory = $true)]$Table, [AllowEmptyString()][string]$OverrideText = "", [string]$From = "the settings override")
    $values = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
    foreach ($name in @($Table.Keys)) { $values[$name] = $Table[$name].default }
    if ($OverrideText.Trim() -eq "") { return [pscustomobject]@{ state = "ok"; values = $values; findings = @() } }
    $findings = New-Object System.Collections.ArrayList
    $given = $null
    try { $given = (ConvertFrom-HordeJson $OverrideText) } catch { $given = $null }
    $valuesProp = $null; $versionProp = $null
    if ($given -is [System.Management.Automation.PSCustomObject]) { $valuesProp = $given.PSObject.Properties["values"]; $versionProp = $given.PSObject.Properties["schemaVersion"] }
    if ($null -eq $versionProp -or $versionProp.Value -ne 1 -or $null -eq $valuesProp -or $valuesProp.Value -isnot [System.Management.Automation.PSCustomObject]) {
        return [pscustomobject]@{ state = "refused"; values = $null; findings = @($From + ": it is not an object with schemaVersion 1 and a values object") }
    }
    foreach ($prop in @($valuesProp.Value.PSObject.Properties)) {
        $name = "$($prop.Name)"
        if (-not $Table.ContainsKey($name)) {
            $shown = "a key that is not repeated here"
            if ($name -cmatch '\A[A-Za-z][A-Za-z0-9.]{0,99}\z') { $shown = "'" + $name + "'" }
            [void]$findings.Add($From + ": " + $shown + " is not a setting of the decisions module")
            continue
        }
        $wrong = Get-HordeDecisionSettingValueProblem -Entry $Table[$name] -Value $prop.Value
        if ($wrong -ne "") { [void]$findings.Add($From + ": '" + $name + "' " + $wrong); continue }
        $values[$name] = $prop.Value
    }
    if ($findings.Count -gt 0) { return [pscustomobject]@{ state = "refused"; values = $null; findings = @($findings) } }
    return [pscustomobject]@{ state = "ok"; values = $values; findings = @() }
}

function Get-HordeDecisionSettingTable {
    # Every setting, as { name; kind; default; least; most; means }, in name order: for a caller that
    # shows them (a help text, a settings page). Read once for the process.
    if ($null -eq $script:HordeDecisionSettings) {
        $path = Join-Path $PSScriptRoot "settings.json"
        $script:HordeDecisionSettings = ConvertFrom-HordeDecisionSettingsText -Text ([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)) -From "decisions/settings.json"
    }
    return @($script:HordeDecisionSettings.Keys | Sort-Object | ForEach-Object { $script:HordeDecisionSettings[$_] })
}

function Get-HordeDecisionSettingsOverridePath {
    # Where this module's override file is: <HordeHome>\settings\decisions.json. Worked out, never
    # created: asking for a setting makes no folder.
    return (Join-Path (Join-Path (Get-HordeHome) "settings") "decisions.json")
}

function Get-HordeDecisionSettingsNow {
    # Every setting as it stands now: the table, with the override file laid over it when there is
    # one. Returns Resolve-HordeDecisionSettings's { state; values; findings }. An override file that
    # is there and cannot be read is refused like one that fails its checks.
    if ($null -eq $script:HordeDecisionSettings) { $null = Get-HordeDecisionSettingTable }
    $path = Get-HordeDecisionSettingsOverridePath
    if (-not [System.IO.File]::Exists($path)) { return (Resolve-HordeDecisionSettings -Table $script:HordeDecisionSettings) }
    $text = $null
    try { $text = [System.IO.File]::ReadAllText($path, (New-Object System.Text.UTF8Encoding($false, $true))) }
    catch { return [pscustomobject]@{ state = "refused"; values = $null; findings = @($path + ": it could not be read as UTF-8 text") } }
    # A file that is there and empty is not "no override": somebody made it, and it says nothing.
    if ($text.Trim() -eq "") { return [pscustomobject]@{ state = "refused"; values = $null; findings = @($path + ": it is empty; remove it to use the defaults") } }
    return (Resolve-HordeDecisionSettings -Table $script:HordeDecisionSettings -OverrideText $text -From $path)
}

function Get-HordeDecisionSettingsProblem {
    # Why the settings cannot be used, as one sentence naming the file and every problem, or "" when
    # they can. For a caller that must answer rather than throw (decisions/Operations.ps1).
    $now = Get-HordeDecisionSettingsNow
    if ($now.state -ceq "ok") { return "" }
    return ("the decisions settings override was refused, so no setting is used and no default is put in its place: " + (@($now.findings) -join "; "))
}

function Get-HordeDecisionSetting {
    # The value of one setting: the override's, when there is an override file and it passed its
    # checks; the default, when there is no override file. WHEN THE OVERRIDE FAILED ITS CHECKS THIS
    # THROWS, with every problem named, for every setting: a default is never handed out in place of
    # a value a person tried to set.
    # A name the table does not have THROWS: a misspelt name must never read as 0 or as nothing.
    param([Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $script:HordeDecisionSettings) { $null = Get-HordeDecisionSettingTable }
    if (-not $script:HordeDecisionSettings.ContainsKey($Name)) { throw ("'" + $Name + "' is not a setting of the decisions module (decisions/settings.json)") }
    $now = Get-HordeDecisionSettingsNow
    if ($now.state -cne "ok") { throw ("the decisions settings override was refused, so no setting is used and no default is put in its place: " + (@($now.findings) -join "; ")) }
    $value = $now.values[$Name]
    # A whole number is handed out as a 64-bit one, whatever the parser read it as.
    if ("$($script:HordeDecisionSettings[$Name].kind)" -ceq "whole-number") { return [long]$value }
    return $value
}
