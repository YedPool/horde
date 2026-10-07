# core/ModuleSettings - where a module's settings live: its own declared defaults, and one file a person
# may write under Horde's home.
#
# HOW A MODULE USES THIS. Declare the table once, at the top of the module, and read it where the
# module starts:
#
#   . (Join-Path $PSScriptRoot "..\core\ModuleSettings.ps1")
#   $script:HordeProbeSettings = New-HordeModuleSettings -Module "probe" -Settings @(
#       @{ name = "widthPx";      kind = "whole";     default = 520;      min = 200; max = 4000; what = "Width of the window, in pixels." },
#       @{ name = "share";        kind = "fraction";  default = 0.25;     min = 0.1; max = 0.9;  what = "Share of the screen the window may take." },
#       @{ name = "follow";       kind = "truefalse"; default = $true;                           what = "Whether the window follows its terminal." },
#       @{ name = "role";         kind = "text";      default = "chief";  min = 1;   max = 40;   what = "The role the window stands beside." },
#       @{ name = "theme";        kind = "text";      default = "system"; values = @("system", "light", "dark"); what = "Which colours the page uses." },
#       @{ name = "statusFolder"; kind = "folder";    default = "";                              what = "Where status files are; empty means the module's own place." }
#   )
#   $s = Get-HordeModuleSettings -Declaration $script:HordeProbeSettings
#   foreach ($f in $s.findings) { Write-Warning $f }      # each one a plain sentence naming its key
#   $width = $s.values.widthPx                            # every declared name is there, always
#
# and a person overrides any of them in <HORDE_HOME>\settings\probe.json (schema/module-settings.v1):
#
#   { "schemaVersion": 1, "settings": { "widthPx": 640, "theme": "dark" } }
#
# THE THREE ENTRY POINTS a module calls:
#   New-HordeModuleSettings -Module <name> -Settings <table>          the declaration; THROWS on a
#                                                                     malformed table, naming every problem
#   Read-HordeModuleSettingsText -Declaration <it> -Text <text|$null> { values; findings }, PURE given
#                                                                     the file's text; $null is "no file"
#   Get-HordeModuleSettings -Declaration <it> [-HordeHome <path>]     { values; findings; path }: reads
#                                                                     the one file and writes nothing
# values is an object with one property per declared name ($s.values.widthPx): the file's value where it
# gave a good one, the default everywhere else. findings is a list of sentences, empty when nothing is
# wrong. A module decides what to do with a finding (print it, show it); this file never prints.
# Two more are for whatever will SHOW a module's settings, which is not built here:
# Get-HordeModuleSettingRule (an entry's allowed range, in words) and Get-HordeModuleSettingsPath
# (where the file is). The rest of the file is its own.
#
# WHAT IS WRONG IN A FILE IS SAID BY NAME, AND THE DEFAULT IS USED. A name the module did not declare, a
# value of the wrong kind and a value outside the allowed range are one finding each, and that setting
# is its default: never a throw, because a typo in a person's file must not stop a window opening, and
# never a silent ignore, because a setting that quietly did nothing is the worst of the three. A file
# that is not there is every default and no finding. A file that cannot be read as a whole - held by
# another program, over 262144 bytes, not UTF-8, not JSON, a key written twice, not the shape of
# schema/module-settings.v1 - is its findings and EVERY default: half of a file nobody can vouch for
# is not used. Only a malformed DECLARATION throws, when it is declared: that is a programming error,
# and the suite of the module that made it must fail.
#
# THE KINDS, and what "allowed range" means for each. min and max are inclusive.
#   whole      A whole number, an Int32. min and max are required: no number here is unbounded. In the
#              file it is written in digits only (520, -5): 520.0, 5.2e2 and "520" are a wrong kind, not
#              a number to round or convert, because a person who wrote 1.5 would get 1 or 2 and never
#              be told. (Measured 2026-10-07 on 5.1: ConvertFrom-Json reads 520 as Int32, 5000000000 as
#              Int64, 520.0 and a whole number past Int64 as Decimal, 5.2e2 and 1e30 as Double; only the
#              first is a whole number here, and the others are told so with the number they gave.)
#   fraction   A share of something: a number from 0 to 1, a Double. min and max are required and lie
#              within 0 to 1. Written as a JSON number (0.25, 1e-1, 0, 1), never "25%" or "1/4". It is
#              converted to a Double FIRST and that Double is both what is compared and what the module
#              gets, so 0.99999999999999999999, which 5.1 reads as a Decimal that is 1 as a Double, is 1
#              and passes a largest value of 1 (measured 2026-10-07).
#   truefalse  true or false, written without quotes. "true", 1 and 0 are a wrong kind.
#   text       A string with no control character in it (Unicode category Cc: a line break in a role
#              name or a font list is never meant). Its range is EITHER a length in characters (min and
#              max, max at most 4096) OR a closed list (values, compared exactly), never both.
#   folder     An absolute path, at most 1024 characters, kept exactly as written. Absolute means it
#              does not depend on the current folder or drive: on Windows a drive letter and a slash
#              (C:\x, c:/x) or two slashes (\\server\share); C:x, \x and x\y are refused, although .NET
#              calls the first two rooted (measured 2026-10-07). On a system whose separator is / any
#              rooted path passes; only Windows is tested. WHETHER THE FOLDER EXISTS, AND WHAT TO DO
#              WHEN IT DOES NOT, IS THE MODULE'S OWN BUSINESS: a pure reader cannot look. A folder's
#              DEFAULT may also be empty, meaning "the module's own place", because shipped code holds
#              no absolute path of anyone's machine (CONTRIBUTING 11); a file may not say empty, it
#              leaves the key out.
# A list of things (font families) is text, as the module's consumer writes it. There is no list kind.
#
# NAMES. A module is lower-case letters, digits and hyphens, starting with a letter, at most 40 - it
# is a file name, so a Windows device name (con, nul, com1) is refused. A setting is lower camel case,
# letters and digits, at most 40 (widthPx, redrawWaitMs: say the unit in the name). Names are compared
# EXACTLY in the file; "WidthPx" is an unknown key, and its finding says which name was meant. Two
# declared names may not differ only in case.
#
# THE HOME SAYS WHERE, NEVER WHAT (core/Home.ps1). HORDE_HOME chooses which folder the file is read
# from, so a test can point Horde at a folder it made. No environment variable sets, overrides or
# switches a setting, because a child process inherits its parent's environment: this file reads none.
#
# WHERE THIS FOLLOWS core/config-keys.json AND core/EngineConfig.ps1, AND WHERE IT DOES NOT. Followed:
# a declared table checked as a whole before anything reads it, throwing with every problem; a field
# nobody reads refused (review of PR #73, F3); names and enum values compared exactly; lower camel case
# names; duplicate keys found in the text (core/JsonText.ps1), since ConvertFrom-Json keeps one and says
# nothing; the document checked against a schema (core/Schema.ps1); the text function apart from the
# file function. NOT followed, each for a reason:
#   - That registry is ENGINE configuration: one list for the whole engine, resolved per session
#     through layers L0 to L5, with kinds name, model and enum and no number. A module's milliseconds
#     and pixels are per module, have one layer (the person's file over the defaults) and need numbers
#     with ranges. So the table is declared by the module, in code, beside the code that uses it, and
#     is not a row in a shared file that every module's pull request would have to edit.
#   - Its findings are { severity; code; source; path; detail } and a bad layer blocks resolution.
#     Here a finding is one sentence and the default is used: nothing downstream branches on a code.
#   - Its files are plain ASCII and a byte-order mark is a finding. This file is a PERSON's, may hold a
#     folder under a profile whose name is not ASCII, and is saved by editors that write a mark: it is
#     UTF-8, a leading mark is skipped, and text values may hold any character but a control character.
#   - It redacts secret-shaped strings from findings. Loading that would load the engine checker and
#     the agent descriptors into every window. Instead A FINDING NEVER QUOTES A TEXT VALUE: it says the
#     value's length, or that it is not on the list. Numbers and true/false are quoted. A key name is
#     quoted, cut at 60 characters, with anything that is not printable ASCII written as \uXXXX.
#
# No Set-StrictMode here: this file is dot-sourced, so a file-scope Set-StrictMode would set the
# caller's mode (see core/Tristate.ps1). The functions run under -Version Latest.
. (Join-Path $PSScriptRoot "Home.ps1")
. (Join-Path $PSScriptRoot "Schema.ps1")
. (Join-Path $PSScriptRoot "JsonText.ps1")
. (Join-Path $PSScriptRoot "ReadShared.ps1")

$script:HordeModuleSettingKinds = @("text", "whole", "fraction", "truefalse", "folder")
$script:HordeModuleSettingFields = @("name", "kind", "default", "what", "min", "max", "values")
$script:HordeModuleNamePattern = '\A[a-z][a-z0-9-]{0,39}\z'
# con.json opens the console, not a file, on Windows; the names are refused everywhere so a module's
# name does not have to change the day it runs there.
$script:HordeModuleDeviceNamePattern = '\A(con|prn|aux|nul|com[0-9]|lpt[0-9])\z'
$script:HordeModuleSettingNamePattern = '\A[a-z][a-zA-Z0-9]{0,39}\z'
# What an entry says it is: one line a person can read in a table, printable ASCII as every source file.
$script:HordeModuleSettingWhatPattern = '\A[\x20-\x7E]{1,200}\z'
# The longest text and the longest folder a setting may hold. A cap, so "no largest length" cannot be
# declared; 1024 is about four times the 260 of an ordinary Windows path, and below the 32767 a long
# one may reach.
$script:HordeModuleSettingTextCap = 4096
$script:HordeModuleSettingFolderCap = 1024
$script:HordeModuleSettingsSchemaName = "module-settings.v1"
# The folder under the home that holds one file per module, <module>.json.
$script:HordeModuleSettingsFolder = "settings"
# THE LONGEST FILE THAT IS READ, in characters of text and, for the file itself, in bytes. Forty
# settings, each with a forty-character name and a short value, come to about 2500 characters
# (reckoned, not measured), so this is a hundred times a large file and still small to hold in memory.
$script:HordeModuleSettingsMaxLength = 262144
# How much of a key's name, and of a whole finding, is shown before it is cut.
$script:HordeModuleSettingsNameShown = 60
$script:HordeModuleSettingsFindingShown = 400
# WHAT JSON IS MADE OF, AND NOTHING ELSE: blanks, the six marks, strings in double quotes with JSON's
# own escapes, true, false, null, and numbers as JSON writes them. The text is matched from its start
# and must be consumed whole, BEFORE the parser sees it, because Windows PowerShell 5.1's
# ConvertFrom-Json reads more than JSON (measured 2026-10-07): {'a':1} and {a:1} parse, so a key
# repeated in single quotes or with none is kept once in silence and core/JsonText.ps1's scan, which
# reads double-quoted keys, never sees it; NaN parses as a Double that is below nothing and above
# nothing; 010 parses as 10 and +5 as 5. This says only what the pieces are; whether they form a
# document is still the parser's to say. Nothing follows the repeat, so a text that stops matching
# stops there: there is nothing to backtrack into, and 200000 digits with a letter after them are
# refused as fast as they are read (test/test-module-settings.ps1 has that text).
$script:HordeModuleSettingsJsonPieces = '\A(?:[ \t\r\n]+|[{}\[\],:]|"(?:[^"\\\x00-\x1F]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4}))*"|true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?(?![0-9A-Za-z.+-]))*'

function Test-HordeModuleSettingFolder {
    # Is this an absolute path, one that means the same from every current folder and drive?
    # IsPathRooted answers yes for C:x and \x (measured 2026-10-07), which do not; it is still asked,
    # because it throws on a character no path may hold (| < > " and control characters), which is a no.
    param([string]$Path)
    try { if (-not [System.IO.Path]::IsPathRooted($Path)) { return $false } } catch { return $false }
    if ([System.IO.Path]::DirectorySeparatorChar -eq [char]'\') { return [bool]($Path -cmatch '\A(?:[A-Za-z]:[\\/]|[\\/]{2}[^\\/])') }
    return $true
}

function Test-HordeModuleSettingValue {
    # Does a value fit an entry's kind and range? { ok; value }: value is what the module gets, in the
    # entry's own .NET type. ONE CHECK FOR BOTH SIDES: a declared default and a value from a file go
    # through this same function, so a default can never be something the file could not say.
    param($Entry, $Value)
    $no = [pscustomobject]@{ ok = $false; value = $null }
    $kind = "" + $Entry.kind
    if ($kind -ceq "whole") {
        # AN Int32 OR NOTHING. An Int64 is what the parser gives a whole number past Int32, which no
        # range here can hold (min and max are Int32), so it needs no branch of its own.
        if ($Value -isnot [int]) { return $no }
        if ($Value -lt $Entry.min -or $Value -gt $Entry.max) { return $no }
        return [pscustomobject]@{ ok = $true; value = $Value }
    }
    if ($kind -ceq "fraction") {
        if (-not ($Value -is [int] -or $Value -is [decimal] -or $Value -is [double])) { return $no }
        $asDouble = [double]$Value
        # Not-a-number is below nothing and above nothing, so the range would pass it. (An infinity is
        # outside every range, and a file cannot say either: neither is JSON.)
        if ([double]::IsNaN($asDouble)) { return $no }
        if ($asDouble -lt $Entry.min -or $asDouble -gt $Entry.max) { return $no }
        return [pscustomobject]@{ ok = $true; value = $asDouble }
    }
    if ($kind -ceq "truefalse") {
        if ($Value -isnot [bool]) { return $no }
        return [pscustomobject]@{ ok = $true; value = $Value }
    }
    if ($Value -isnot [string] -or $Value -cmatch '\p{Cc}') { return $no }
    if ($kind -ceq "folder") {
        if ($Value.Length -gt $script:HordeModuleSettingFolderCap -or -not (Test-HordeModuleSettingFolder -Path $Value)) { return $no }
        return [pscustomobject]@{ ok = $true; value = $Value }
    }
    if ($null -ne $Entry.values) { if (@($Entry.values) -cnotcontains $Value) { return $no } }
    elseif ($Value.Length -lt $Entry.min -or $Value.Length -gt $Entry.max) { return $no }
    return [pscustomobject]@{ ok = $true; value = $Value }
}

function Get-HordeModuleSettingNumber {
    # A number as a finding or a rule writes it: the same text on every machine, whatever its culture.
    param($Number)
    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    if ($Number -is [double]) { return $Number.ToString("R", $invariant) }
    return $Number.ToString($invariant)
}

function Get-HordeModuleSettingRule {
    # What an entry allows, in words: the middle of every finding, and what a table of settings shows.
    param([Parameter(Mandatory = $true)]$Entry)
    $kind = "" + $Entry.kind
    if ($kind -ceq "whole") { return ("a whole number from " + (Get-HordeModuleSettingNumber $Entry.min) + " to " + (Get-HordeModuleSettingNumber $Entry.max) + ", written in digits only") }
    if ($kind -ceq "fraction") { return ("a number from " + (Get-HordeModuleSettingNumber $Entry.min) + " to " + (Get-HordeModuleSettingNumber $Entry.max)) }
    if ($kind -ceq "truefalse") { return "true or false, written without quotes" }
    if ($kind -ceq "folder") { return ("an absolute folder path of at most " + $script:HordeModuleSettingFolderCap + " characters") }
    if ($null -ne $Entry.values) { return ("one of: " + (@($Entry.values) -join ", ")) }
    return ("text of " + $Entry.min + " to " + $Entry.max + " characters")
}

function Get-HordeModuleSettingGiven {
    # What was given instead, in words. A TEXT VALUE IS NEVER QUOTED (the header says why): its length
    # is. A number is, because a person fixing "5000" needs to see it and a number is no credential.
    param($Value)
    if ($null -eq $Value) { return "null" }
    if ($Value -is [bool]) { if ($Value) { return "true" }; return "false" }
    if ($Value -is [string]) {
        if ($Value -cmatch '\p{Cc}') { return "text holding a control character" }
        return ("text of " + $Value.Length + " characters")
    }
    if ($Value -is [int] -or $Value -is [long]) { return ("the whole number " + (Get-HordeModuleSettingNumber $Value)) }
    if ($Value -is [decimal] -or $Value -is [double]) { return ("the number " + (Get-HordeModuleSettingNumber $Value)) }
    if ($Value -is [System.Collections.IList]) { return "a list" }
    return "an object"
}

function New-HordeModuleSettings {
    # A module's declaration: { module; settings }, each setting { name; kind; default; what; min; max;
    # values } with the fields its kind does not have as $null. THROWS, naming every problem at once,
    # on a table that is not well formed: it is written by a programmer and read on every start, so it
    # fails where it is declared and not on the day a file first meets the bad entry.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Module, [Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowNull()][object[]]$Settings)
    if ($Module -cnotmatch $script:HordeModuleNamePattern) { throw ("'" + $Module + "' is not a module name: lower-case letters, digits and hyphens, starting with a letter, at most 40") }
    if ($Module -cmatch $script:HordeModuleDeviceNamePattern) { throw ("'" + $Module + "' is not a module name: it is a device's name on Windows, where no file can have it") }
    if (@($Settings).Count -eq 0) { throw ("the module " + $Module + " declares no settings") }
    $problems = New-Object System.Collections.ArrayList
    $rows = New-Object System.Collections.ArrayList
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $place = 0
    foreach ($raw in @($Settings)) {
        $place++
        if ($raw -isnot [System.Collections.IDictionary]) { [void]$problems.Add("entry " + $place + " is not a table (@{ name = ...; kind = ...; default = ...; what = ... })"); continue }
        # FIELD NAMES ARE COMPARED EXACTLY: a plain @{} ignores case, so its keys go into an ordinal
        # dictionary first (Get-HordeObjectByKey, core/Schema.ps1), and Min is then a field nobody reads.
        $fields = Get-HordeObjectByKey $raw
        $name = $null; [void]$fields.TryGetValue("name", [ref]$name)
        if ($name -isnot [string] -or $name -cnotmatch $script:HordeModuleSettingNamePattern) { [void]$problems.Add("entry " + $place + " has the name '" + $name + "'; a setting's name is lower camel case, letters and digits, at most 40"); continue }
        if (-not $seen.Add($name)) { [void]$problems.Add("the setting " + $name + " is declared twice, ignoring case"); continue }
        $before = $problems.Count
        foreach ($field in @($fields.Keys)) { if ($script:HordeModuleSettingFields -cnotcontains $field) { [void]$problems.Add("the setting " + $name + " has the field '" + $field + "', which a setting does not have") } }
        $kind = $null; [void]$fields.TryGetValue("kind", [ref]$kind)
        if ($kind -isnot [string] -or $script:HordeModuleSettingKinds -cnotcontains $kind) { [void]$problems.Add("the setting " + $name + " has the kind '" + $kind + "'; one of " + ($script:HordeModuleSettingKinds -join ", ")); continue }
        $what = $null; [void]$fields.TryGetValue("what", [ref]$what)
        if ($what -isnot [string] -or $what -cnotmatch $script:HordeModuleSettingWhatPattern -or $what.Trim() -ceq "") { [void]$problems.Add("the setting " + $name + " must say what it is: one line of 1 to 200 printable ASCII characters") }
        $min = $null; $max = $null; $values = $null
        $hasMin = $fields.TryGetValue("min", [ref]$min)
        $hasMax = $fields.TryGetValue("max", [ref]$max)
        $hasValues = $fields.TryGetValue("values", [ref]$values)
        $ranged = ($kind -ceq "whole" -or $kind -ceq "fraction" -or ($kind -ceq "text" -and -not $hasValues))
        if ($kind -ceq "text" -and $hasValues -and ($hasMin -or $hasMax)) { [void]$problems.Add("the setting " + $name + " has a length and a closed list; text has one or the other, not both") }
        elseif ($kind -ceq "text" -and -not ($hasValues -or $hasMin -or $hasMax)) { [void]$problems.Add("the setting " + $name + " is text with no allowed range: give min and max (a length) or values (a closed list)") }
        elseif ($ranged) {
            # THE SMALLEST AND LARGEST: whole numbers for a whole number and for a length (0 to 4096),
            # numbers within 0 to 1 for a fraction. An Int32 only: 200.0 is refused here as it is in a file.
            foreach ($end in @("min", "max")) {
                $word = $(if ($end -ceq "min") { "smallest" } else { "largest" })
                $bound = $(if ($end -ceq "min") { $min } else { $max })
                $given = $(if ($end -ceq "min") { $hasMin } else { $hasMax })
                if ($kind -ceq "fraction") {
                    $isNumber = ($bound -is [int] -or $bound -is [double] -or $bound -is [decimal])
                    if (-not $given -or -not $isNumber -or [double]::IsNaN([double]$bound)) { [void]$problems.Add("the setting " + $name + " needs its " + $word + " value (" + $end + "), a number") }
                    elseif ([double]$bound -lt 0 -or [double]$bound -gt 1) { [void]$problems.Add("the setting " + $name + " has a " + $word + " value outside 0 to 1; a fraction is a share of something") }
                }
                elseif (-not $given -or $bound -isnot [int]) { [void]$problems.Add("the setting " + $name + " needs its " + $word + " " + $(if ($kind -ceq "text") { "length" } else { "value" }) + " (" + $end + "), a whole number written in digits") }
                elseif ($kind -ceq "text" -and ($bound -lt 0 -or $bound -gt $script:HordeModuleSettingTextCap)) { [void]$problems.Add("the setting " + $name + " has a " + $word + " length outside 0 to " + $script:HordeModuleSettingTextCap) }
            }
            if ($problems.Count -eq $before -and $min -gt $max) { [void]$problems.Add("the setting " + $name + " has its smallest (" + $min + ") above its largest (" + $max + ")") }
            if ($kind -ceq "fraction" -and $problems.Count -eq $before) { $min = [double]$min; $max = [double]$max }
        }
        if (-not $ranged -and $kind -cne "text") {
            foreach ($end in @("min", "max")) { if ($fields.ContainsKey($end)) { [void]$problems.Add("the setting " + $name + " has the field '" + $end + "', which a " + $kind + " setting does not have") } }
        }
        if ($hasValues -and $kind -cne "text") { [void]$problems.Add("the setting " + $name + " has the field 'values', which a " + $kind + " setting does not have; only text has a closed list") }
        elseif ($hasValues) {
            # A CLOSED LIST: one or more different texts, each what a text value may be. Kept as an array
            # even when it holds one, so a caller's .Count is a number.
            $listed = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
            $bad = ($values -isnot [System.Collections.IList] -or @($values).Count -eq 0)
            if (-not $bad) { foreach ($v in @($values)) { if ($v -isnot [string] -or $v.Length -lt 1 -or $v.Length -gt $script:HordeModuleSettingTextCap -or $v -cmatch '\p{Cc}') { $bad = $true } } }
            if ($bad) { [void]$problems.Add("the setting " + $name + " needs its closed list (values): one or more texts of 1 to " + $script:HordeModuleSettingTextCap + " characters with no control character") }
            else { foreach ($v in @($values)) { if (-not $listed.Add($v)) { [void]$problems.Add("the setting " + $name + " lists the value " + $v + " twice") } } }
            $values = [string[]]@($values | ForEach-Object { "" + $_ })
        }
        if (-not $fields.ContainsKey("default")) { [void]$problems.Add("the setting " + $name + " has no default"); continue }
        # THE DEFAULT IS CHECKED ONLY AGAINST A RANGE THAT STANDS, by the check a file's value gets.
        if ($problems.Count -ne $before) { continue }
        $entry = [pscustomobject]@{ name = $name; kind = $kind; default = $null; what = $what; min = $(if ($ranged) { $min } else { $null }); max = $(if ($ranged) { $max } else { $null }); values = $(if ($hasValues) { ,$values } else { $null }) }
        $default = $fields["default"]
        if ($kind -ceq "folder" -and $default -is [string] -and $default -ceq "") { $entry.default = "" }
        else {
            $checked = Test-HordeModuleSettingValue -Entry $entry -Value $default
            if (-not $checked.ok) { [void]$problems.Add("the setting " + $name + " has a default that is not " + (Get-HordeModuleSettingRule -Entry $entry) + ": it is " + (Get-HordeModuleSettingGiven -Value $default)); continue }
            $entry.default = $checked.value
        }
        [void]$rows.Add($entry)
    }
    if ($problems.Count -gt 0) { throw ("the settings of " + $Module + " are declared wrongly: " + ($problems -join "; ")) }
    return [pscustomobject]@{ PSTypeName = "Horde.ModuleSettings"; module = $Module; settings = $rows.ToArray() }
}

function ConvertTo-HordeModuleSettingsPlain {
    # A text as a finding may carry it: printable ASCII as it is, anything else as \uXXXX, cut after
    # -Max characters with "..." to say so. A finding is printed to consoles that cannot draw every
    # character, and a key's name comes from a file anybody may have written.
    param([AllowEmptyString()][string]$Text, [int]$Max)
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $Text.ToCharArray()) {
        if ($sb.Length -ge $Max) { [void]$sb.Append("..."); break }
        $code = [int]$c
        if ($code -ge 0x20 -and $code -le 0x7E) { [void]$sb.Append($c) } else { [void]$sb.Append("\u" + $code.ToString("X4")) }
    }
    return $sb.ToString()
}

function Get-HordeModuleSettingsFileSentence {
    # The one sentence for a file that cannot be used as a whole, whoever found out: the text reading
    # or the file reading.
    param([string]$Module, [string]$Problem)
    return ("the settings file of " + $Module + " " + $Problem + "; every setting of " + $Module + " is its default")
}

function Assert-HordeModuleSettingsDeclaration {
    # Only what New-HordeModuleSettings returned is a declaration: a hand-built table was never checked.
    param($Declaration)
    if ($null -eq $Declaration -or $Declaration.PSObject.TypeNames -notcontains "Horde.ModuleSettings") { throw "-Declaration must be what New-HordeModuleSettings returned" }
}

function Read-HordeModuleSettingsDocument {
    # The settings part of a file's text, or why the text cannot be read as a whole: { settings;
    # problems }, one of them empty. Each problem finishes the sentence "the settings file of <module> ...".
    # IN THIS ORDER: the length before anything walks the text; what JSON is made of before the
    # duplicate scan, which reads only double-quoted keys; the duplicate scan before the parser, which
    # keeps one of two equal keys and throws on two that differ in case; the schema last.
    param([AllowEmptyString()][string]$Text)
    if ($Text.Length -gt $script:HordeModuleSettingsMaxLength) { return [pscustomobject]@{ settings = $null; problems = @("is longer than " + $script:HordeModuleSettingsMaxLength + " characters") } }
    $pieces = [regex]::Match($Text, $script:HordeModuleSettingsJsonPieces)
    if ($pieces.Length -ne $Text.Length) {
        $line = $Text.Substring(0, $pieces.Length).Split([char]10).Count
        return [pscustomobject]@{ settings = $null; problems = @("is not JSON: line " + $line + " holds something JSON does not have") }
    }
    $twice = @(Find-HordeJsonDuplicateKey -Text $Text)
    if ($twice.Count -gt 0) { return [pscustomobject]@{ settings = $null; problems = @($twice | ForEach-Object { "says one thing twice: " + $_ }) } }
    # WHAT THE PARSER REFUSES ALTHOUGH ITS PIECES ARE JSON's (measured 2026-10-07 on 5.1): pieces in no
    # order ({ "a": 1, }), a number too large for a Double (1e400), values nested more than about 100
    # deep ("RecursionLimit exceeded"), an empty key, and a key named PSObject, which it keeps for
    # itself. Each is this one sentence. The parser's own message is not passed on: it quotes the text.
    $parsed = $null
    try { $parsed = $Text | ConvertFrom-Json } catch { return [pscustomobject]@{ settings = $null; problems = @("is not JSON the parser can read") } }
    $unfit = @(Test-HordeSchema -Value $parsed -Schema (Get-HordeSchema -Name $script:HordeModuleSettingsSchemaName))
    if ($unfit.Count -gt 0) { return [pscustomobject]@{ settings = $null; problems = @($unfit | ForEach-Object { "does not fit schema/" + $script:HordeModuleSettingsSchemaName + ": " + $_ }) } }
    return [pscustomobject]@{ settings = (Get-HordeObjectByKey $parsed)["settings"]; problems = @() }
}

function Read-HordeModuleSettingsText {
    # A module's settings from its file's TEXT: { values; findings }. PURE: the same declaration and
    # text give the same answer on any machine, and nothing is read but Horde's own schema file. -Text
    # is $null when there is no file, which is every default and no finding; "" is an empty file, which
    # is a finding. The rules are in the header.
    param([Parameter(Mandatory = $true)]$Declaration, [AllowNull()]$Text)
    Assert-HordeModuleSettingsDeclaration -Declaration $Declaration
    if ($null -ne $Text -and $Text -isnot [string]) { throw "-Text is the file's text, or `$null when there is no file" }
    $module = "" + $Declaration.module
    $byName = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
    $byNameAnyCase = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    $values = [ordered]@{}
    foreach ($entry in @($Declaration.settings)) { $byName[$entry.name] = $entry; $byNameAnyCase[$entry.name] = $entry; $values[$entry.name] = $entry.default }
    $sentences = New-Object System.Collections.ArrayList
    if ($null -ne $Text) {
        # ONE LEADING BYTE-ORDER MARK IS SKIPPED, here and not only where the file is decoded, so the
        # answer is the same whoever turned the bytes into text: .NET's GetString keeps the mark and
        # 5.1's parser refuses it as "Invalid JSON primitive" (measured 2026-10-07).
        $body = $Text
        if ($body.Length -gt 0 -and [int]$body[0] -eq 0xFEFF) { $body = $body.Substring(1) }
        $doc = Read-HordeModuleSettingsDocument -Text $body
        foreach ($problem in @($doc.problems)) { [void]$sentences.Add((Get-HordeModuleSettingsFileSentence -Module $module -Problem $problem)) }
        if ($null -ne $doc.settings) {
            # NAMES ARE COMPARED EXACTLY, so the file's keys go through an ordinal dictionary as the
            # declaration's fields did: a property read on the parsed object would ignore case.
            $given = Get-HordeObjectByKey $doc.settings
            foreach ($key in @($given.Keys)) {
                $shown = ConvertTo-HordeModuleSettingsPlain -Text $key -Max $script:HordeModuleSettingsNameShown
                if (-not $byName.ContainsKey($key)) {
                    $meant = ""
                    if ($byNameAnyCase.ContainsKey($key)) { $meant = " (names are case-sensitive: '" + $byNameAnyCase[$key].name + "' is one)" }
                    [void]$sentences.Add($module + " has no setting '" + $shown + "'" + $meant + "; it is not used")
                    continue
                }
                $entry = $byName[$key]
                $checked = Test-HordeModuleSettingValue -Entry $entry -Value $given[$key]
                if ($checked.ok) { $values[$key] = $checked.value; continue }
                [void]$sentences.Add($module + " setting '" + $shown + "' must be " + (Get-HordeModuleSettingRule -Entry $entry) + "; the file gives " + (Get-HordeModuleSettingGiven -Value $given[$key]) + "; the default is used")
            }
        }
    }
    # A NEW OBJECT EACH TIME, with a property per declared name: under strict mode a misspelt name is an
    # error where a table would answer with nothing, and a caller that changes its answer changes only that.
    $answer = New-Object psobject
    foreach ($name in @($values.Keys)) { Add-Member -InputObject $answer -NotePropertyName $name -NotePropertyValue $values[$name] }
    $findings = [string[]]@($sentences | ForEach-Object { ConvertTo-HordeModuleSettingsPlain -Text $_ -Max $script:HordeModuleSettingsFindingShown })
    return [pscustomobject]@{ values = $answer; findings = $findings }
}

function Get-HordeModuleSettingsPath {
    # Where a module's file is: <home>\settings\<module>.json. A path only: nothing is looked at.
    # Without -HordeHome the home is Horde's own (core/Home.ps1), whose refusal of a relative HORDE_HOME
    # is passed on as it is: that is no file's fault, and no default would be the right answer to it.
    param([Parameter(Mandatory = $true)]$Declaration, [string]$HordeHome = "")
    Assert-HordeModuleSettingsDeclaration -Declaration $Declaration
    $base = $HordeHome
    if ($base -eq "") { $base = Get-HordeHome }
    elseif (-not (Test-HordeModuleSettingFolder -Path $base)) { throw ("-HordeHome must be an absolute path, not '" + $base + "'") }
    return [System.IO.Path]::Combine($base, $script:HordeModuleSettingsFolder, ($Declaration.module + ".json"))
}

function Get-HordeModuleSettings {
    # A module's settings from its file under the home: { values; findings; path }. READS THAT ONE
    # FILE AND WRITES NOTHING: no home, no settings folder and no file is ever created here (core/Home.ps1:
    # "a reader must not make folders"), so a module with no file leaves no trace of having asked.
    # A file or folder that is not there is every default and no finding. A file that is there and
    # cannot be used is ONE finding and every default: larger than the limit (its length is asked
    # before a byte is read), held by another program for itself, a folder in its place, or bytes that
    # are not UTF-8 - which is what Windows PowerShell 5.1's own > writes (UTF-16), so the finding
    # says how to save it. The decoder throws on a bad byte; a lenient one would put U+FFFD in a
    # folder's name and say nothing.
    param([Parameter(Mandatory = $true)]$Declaration, [string]$HordeHome = "")
    $path = Get-HordeModuleSettingsPath -Declaration $Declaration -HordeHome $HordeHome
    $text = $null
    $trouble = ""
    $stream = $null
    try {
        # Shared for reading, writing and deleting (core/ReadShared.ps1): an editor saving the file by
        # swapping a new one into place must not fail because a window was reading it.
        $stream = Open-HordeSharedStream -Path $path
        if ($stream.Length -gt $script:HordeModuleSettingsMaxLength) { $trouble = "is larger than " + $script:HordeModuleSettingsMaxLength + " bytes" }
        else {
            $buffer = New-Object System.IO.MemoryStream
            $stream.CopyTo($buffer)
            try { $text = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($buffer.ToArray()) }
            catch { $trouble = "is not UTF-8 text; save it as UTF-8" }
        }
    } catch {
        $cause = $_.Exception.GetBaseException()
        if (-not ($cause -is [System.IO.FileNotFoundException] -or $cause -is [System.IO.DirectoryNotFoundException])) { $trouble = "cannot be read (" + $cause.GetType().Name + ")" }
    } finally { if ($null -ne $stream) { $stream.Dispose() } }
    $read = Read-HordeModuleSettingsText -Declaration $Declaration -Text $text
    $findings = $read.findings
    if ($trouble -ne "") { $findings = [string[]]@(Get-HordeModuleSettingsFileSentence -Module $Declaration.module -Problem $trouble) }
    return [pscustomobject]@{ values = $read.values; findings = $findings; path = $path }
}
