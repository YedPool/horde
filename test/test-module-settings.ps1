# DOES A MODULE GET ITS SETTINGS FROM ITS OWN DECLARED DEFAULTS AND ONE FILE UNDER THE HOME, AND IS
# EVERYTHING WRONG IN THAT FILE SAID BY NAME?
#
# core/ModuleSettings.ps1. Three parts, as the file has three entry points: the declaration (a malformed
# table is a programming error and throws), the pure reading of a file's text, and the reading of the
# file itself in a home this suite creates under TEMP and removes. Nothing here reads or writes the
# real home.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\ModuleSettings.ps1")

function Section { param([string]$Title) Write-Host ""; Write-Host ("--- " + $Title + " ---") -ForegroundColor Cyan }

function Table {
    # A valid table with one setting of every kind (two of text: a length and a closed list), with one
    # entry changed: -Set replaces or adds fields of the entry called -Name, -Drop removes them.
    param([string]$Name = "", [hashtable]$Set = @{}, [string[]]$Drop = @())
    $rows = @(
        @{ name = "widthPx"; kind = "whole"; default = 520; min = 200; max = 4000; what = "Width of the window, in pixels." },
        @{ name = "share"; kind = "fraction"; default = 0.25; min = 0.1; max = 0.9; what = "Share of the screen the window may take." },
        @{ name = "follow"; kind = "truefalse"; default = $true; what = "Whether the window follows its terminal." },
        @{ name = "role"; kind = "text"; default = "chief"; min = 1; max = 12; what = "The role the window stands beside." },
        @{ name = "theme"; kind = "text"; default = "system"; values = @("system", "light", "dark"); what = "Which colours the page uses." },
        @{ name = "statusFolder"; kind = "folder"; default = ""; what = "Where status files are; empty means the module's own place." }
    )
    foreach ($r in $rows) {
        if ($r.name -cne $Name) { continue }
        # Dropped first: a plain @{} ignores case, so setting Min on a table that has min would only
        # change min's value.
        foreach ($d in $Drop) { $r.Remove($d) }
        foreach ($k in @($Set.Keys)) { $r[$k] = $Set[$k] }
    }
    return $rows
}

function Refused {
    # Is this table refused when it is declared, with a message holding every -Like part?
    param([object[]]$Rows, [string[]]$Like, [string]$Module = "probe")
    $message = ""
    try { $null = New-HordeModuleSettings -Module $Module -Settings $Rows; return $false } catch { $message = "" + $_.Exception.Message }
    foreach ($part in $Like) { if ($message -notlike ("*" + $part + "*")) { Write-Host ("    got: " + $message) -ForegroundColor DarkYellow; return $false } }
    return $true
}

function Declared {
    # The declared entry called -Name, from a table that must be accepted.
    param([object[]]$Rows, [string]$Name)
    $d = New-HordeModuleSettings -Module "probe" -Settings $Rows
    return @($d.settings | Where-Object { $_.name -ceq $Name })[0]
}

# ---------------------------------------------------------------------------------------------------
Section "the declaration"
$decl = New-HordeModuleSettings -Module "probe" -Settings (Table)
Check ($decl.module -ceq "probe") "a declaration carries its module's name"
Check ((@($decl.settings | ForEach-Object { $_.name }) -join ",") -ceq "widthPx,share,follow,role,theme,statusFolder") "and its settings in the order they were declared"
Check ($decl.settings[0].default -is [int] -and $decl.settings[0].default -eq 520) "a whole number's default is an Int32"
Check ($decl.settings[1].default -is [double] -and $decl.settings[1].default -eq 0.25) "a fraction's default is a Double"
Check ($decl.settings[2].default -is [bool] -and $decl.settings[2].default -eq $true) "a true-false default is a Boolean"
Check ($decl.settings[3].default -is [string] -and $decl.settings[3].default -ceq "chief") "a text default is a String"
Check ($decl.settings[5].default -is [string] -and $decl.settings[5].default -ceq "") "a folder's default may be empty: the module's own place"
Check ($decl.settings[0].what -ceq "Width of the window, in pixels.") "an entry keeps what it says the setting is"
Check ((Get-HordeModuleSettingRule -Entry $decl.settings[0]) -ceq "a whole number from 200 to 4000, written in digits only") "the rule of a whole number, in words"
Check ((Get-HordeModuleSettingRule -Entry $decl.settings[1]) -ceq "a number from 0.1 to 0.9") "the rule of a fraction, in words"
Check ((Get-HordeModuleSettingRule -Entry $decl.settings[2]) -ceq "true or false, written without quotes") "the rule of a true-false setting, in words"
Check ((Get-HordeModuleSettingRule -Entry $decl.settings[3]) -ceq "text of 1 to 12 characters") "the rule of a text setting with a length, in words"
Check ((Get-HordeModuleSettingRule -Entry $decl.settings[4]) -ceq "one of: system, light, dark") "the rule of a text setting with a closed list, in words"
Check ((Get-HordeModuleSettingRule -Entry $decl.settings[5]) -ceq "an absolute folder path of at most 1024 characters") "the rule of a folder, in words"

Section "a module's name"
foreach ($good in @("a", "decisions-window", ("m" + ("x" * 39)), "con-sole", "v2")) {
    Check ((New-HordeModuleSettings -Module $good -Settings (Table)).module -ceq $good) ("the module name '" + $good + "' is accepted")
}
foreach ($bad in @("Probe", "a b", "1a", "-a", "a_b", "a.b", "a/b", "..", ("m" + ("x" * 40)))) {
    Check (Refused -Rows (Table) -Module $bad -Like "is not a module name") ("the module name '" + $bad + "' is refused")
}
foreach ($device in @("con", "prn", "aux", "nul", "com1", "lpt9")) {
    Check (Refused -Rows (Table) -Module $device -Like "device") ("the module name '" + $device + "' is refused: no file can have a device's name")
}

Section "a malformed table throws when it is declared"
Check (Throws { New-HordeModuleSettings -Module "probe" -Settings @() } "declares no settings") "a table with no settings is refused"
Check (Refused -Rows @("widthPx") -Like "entry 1 is not a table") "an entry that is not a table is refused, by its place"
Check (Refused -Rows ((Table) + @(@{ name = "WIDTHPX"; kind = "truefalse"; default = $true; what = "A second one." })) -Like "entry 7 has the name") "an entry is found by its place when its name is not one"
Check (Refused -Rows ((Table) + @(@{ name = "widthpx"; kind = "truefalse"; default = $true; what = "A second one." })) -Like "widthpx", "twice") "two names that differ only in case are refused: a person could not tell them apart"
foreach ($bad in @("WidthPx", "width_px", "width.px", "width-px", "9px", "", ("w" + ("x" * 40)))) {
    Check (Refused -Rows (Table "widthPx" @{ name = $bad }) -Like "entry 1 has the name") ("the setting name '" + $bad + "' is refused: lower camel case, at most 40")
}
Check (Refused -Rows (Table "widthPx" @{ name = 5 }) -Like "entry 1 has the name") "a setting name that is not text is refused"
Check ((Declared (Table "widthPx" @{ name = ("w" + ("x" * 39)) }) ("w" + ("x" * 39))).default -eq 520) "a setting name of 40 characters is accepted"
Check (Refused -Rows (Table "widthPx" @{ minimum = 1 }) -Like "widthPx", "'minimum'", "does not have") "a field nobody reads is refused by name, never ignored"
Check (Refused -Rows (Table "widthPx" @{ Min = 200 } -Drop "min") -Like "widthPx", "'Min'") "a field name is compared exactly: Min is not min"
foreach ($bad in @("number", "Whole", "int", "", 5)) {
    Check (Refused -Rows (Table "widthPx" @{ kind = $bad }) -Like "widthPx", "kind") ("the kind '" + $bad + "' is refused")
}
Check (Refused -Rows (Table "widthPx" -Drop "kind") -Like "widthPx", "kind") "an entry with no kind is refused"
Check (Refused -Rows (Table "widthPx" -Drop "default") -Like "widthPx", "no default") "an entry with no default is refused"
Check (Refused -Rows (Table "widthPx" -Drop "what") -Like "widthPx", "what it is") "an entry that does not say what it is is refused"
foreach ($bad in @("", "   ", ("w" * 201), ("caf" + [char]0xE9), 7)) {
    Check (Refused -Rows (Table "widthPx" @{ what = $bad }) -Like "widthPx", "what it is") ("a description that is empty, blank, over 200 characters, not ASCII or not text is refused (" + ("" + $bad).Length + " characters)")
}
Check ((Declared (Table "widthPx" @{ what = ("w" * 200) }) "widthPx").what.Length -eq 200) "a description of 200 characters is accepted"
Check (Refused -Rows ((Table "widthPx" @{ max = 100 }) | ForEach-Object { if ($_.name -ceq "role") { $_.kind = "word" }; $_ }) -Like "widthPx", "role") "EVERY problem is in the one message: two bad entries, both named"

Section "a whole number's table entry"
Check ((Declared (Table "widthPx" @{ default = 200 }) "widthPx").default -eq 200) "a default equal to the smallest allowed is accepted"
Check ((Declared (Table "widthPx" @{ default = 4000 }) "widthPx").default -eq 4000) "a default equal to the largest allowed is accepted"
Check ((Declared (Table "widthPx" @{ default = 7; min = 7; max = 7 }) "widthPx").default -eq 7) "a range of one value is a range"
Check ((Declared (Table "widthPx" @{ default = -5; min = -10; max = -1 }) "widthPx").default -eq -5) "a range below zero is a range"
foreach ($bad in @(199, 4001, 520.0, "520", $true, $null, 5000000000, [decimal]520)) {
    $shown = $(if ($null -eq $bad) { "null" } else { $bad.GetType().Name + " " + $bad })
    Check (Refused -Rows (Table "widthPx" @{ default = $bad }) -Like "widthPx", "default", "a whole number from 200 to 4000") ("a whole number's default may not be " + $shown)
}
Check (Refused -Rows (Table "widthPx" -Drop "min") -Like "widthPx", "smallest") "a whole number with no smallest value is refused"
Check (Refused -Rows (Table "widthPx" -Drop "max") -Like "widthPx", "largest") "a whole number with no largest value is refused"
Check (Refused -Rows (Table "widthPx" @{ min = 200.0 }) -Like "widthPx", "smallest") "a smallest value written as 200.0 is refused"
Check (Refused -Rows (Table "widthPx" @{ max = "4000" }) -Like "widthPx", "largest") "a largest value written as text is refused"
Check (Refused -Rows (Table "widthPx" @{ max = 5000000000 }) -Like "widthPx", "largest") "a largest value beyond an Int32 is refused"
Check (Refused -Rows (Table "widthPx" @{ min = 4001; default = 4001 }) -Like "widthPx", "above") "a smallest value above the largest is refused"
Check (Refused -Rows (Table "widthPx" @{ values = @(1, 2) }) -Like "widthPx", "'values'") "a closed list on a whole number is refused: only text has one"

Section "a fraction's table entry"
Check ((Declared (Table "share" @{ default = 1; min = 0; max = 1 }) "share").default -is [double]) "a fraction's default written as 1 is the Double 1"
Check ((Declared (Table "share" @{ default = [decimal]0.5 }) "share").default -is [double]) "a fraction's default given as a Decimal is a Double"
Check ((Declared (Table "share" @{ default = 0.1 }) "share").default -eq 0.1) "a default equal to the smallest allowed is accepted"
Check ((Declared (Table "share" @{ default = 0.9 }) "share").default -eq 0.9) "a default equal to the largest allowed is accepted"
Check ((Declared (Table "share" @{ min = 0; max = 1 }) "share").min -eq 0.0) "a fraction may span the whole of 0 to 1"
foreach ($bad in @(0.05, 0.95, "0.25", $true, $null, [double]::NaN, [double]::PositiveInfinity)) {
    $shown = $(if ($null -eq $bad) { "null" } else { $bad.GetType().Name + " " + $bad })
    Check (Refused -Rows (Table "share" @{ default = $bad }) -Like "share", "default", "a number from 0.1 to 0.9") ("a fraction's default may not be " + $shown)
}
Check (Refused -Rows (Table "share" @{ default = [double]::NaN; min = 0; max = 1 }) -Like "share", "default") "not-a-number is no fraction even when every number is allowed"
Check (Refused -Rows (Table "share" -Drop "min") -Like "share", "smallest") "a fraction with no smallest value is refused"
Check (Refused -Rows (Table "share" -Drop "max") -Like "share", "largest") "a fraction with no largest value is refused"
Check (Refused -Rows (Table "share" @{ min = -0.1 }) -Like "share", "0 to 1") "a fraction's smallest value below 0 is refused: a fraction is a share of something"
Check (Refused -Rows (Table "share" @{ max = 1.5 }) -Like "share", "0 to 1") "a fraction's largest value above 1 is refused"
Check (Refused -Rows (Table "share" @{ max = "0.9" }) -Like "share", "largest") "a fraction's largest value written as text is refused"
Check (Refused -Rows (Table "share" @{ min = [double]::NaN }) -Like "share", "smallest") "a fraction's smallest value that is not a number is refused"
Check (Refused -Rows (Table "share" @{ min = 0.5; max = 0.4; default = 0.45 }) -Like "share", "above") "a fraction's smallest value above its largest is refused"
Check (Refused -Rows (Table "share" @{ values = @(0.1) }) -Like "share", "'values'") "a closed list on a fraction is refused"

Section "a true-false table entry"
Check ((Declared (Table "follow" @{ default = $false }) "follow").default -eq $false) "false is a default"
foreach ($bad in @("true", 1, 0, $null)) {
    $shown = $(if ($null -eq $bad) { "null" } else { $bad.GetType().Name + " " + $bad })
    Check (Refused -Rows (Table "follow" @{ default = $bad }) -Like "follow", "default", "true or false") ("a true-false default may not be " + $shown)
}
Check (Refused -Rows (Table "follow" @{ min = 0 }) -Like "follow", "'min'") "a smallest value on a true-false setting is refused"
Check (Refused -Rows (Table "follow" @{ max = 1 }) -Like "follow", "'max'") "a largest value on a true-false setting is refused"
Check (Refused -Rows (Table "follow" @{ values = @($true) }) -Like "follow", "'values'") "a closed list on a true-false setting is refused"

Section "a text table entry"
Check ((Declared (Table "role" @{ default = ""; min = 0 }) "role").default -ceq "") "text may be empty when its smallest length is 0"
Check ((Declared (Table "role" @{ default = ("r" * 12) }) "role").default.Length -eq 12) "text as long as its largest length is accepted"
Check ((Declared (Table "role" @{ default = ("r" * 4096); max = 4096 }) "role").default.Length -eq 4096) "text may be declared up to 4096 characters long"
foreach ($bad in @("", ("r" * 13), 5, $true, $null, "two`nlines", ("tab`there"), ("del" + [char]0x7F), ("c1" + [char]0x85))) {
    $shown = $(if ($null -eq $bad) { "null" } else { $bad.GetType().Name + " of " + ("" + $bad).Length })
    Check (Refused -Rows (Table "role" @{ default = $bad }) -Like "role", "default", "text of 1 to 12 characters") ("a text default may not be " + $shown + " (empty, too long, not text, or holding a control character)")
}
Check (Refused -Rows (Table "role" -Drop "min") -Like "role", "smallest") "text with a largest length and no smallest is refused"
Check (Refused -Rows (Table "role" -Drop "max") -Like "role", "largest") "text with a smallest length and no largest is refused"
Check (Refused -Rows (Table "role" -Drop "min", "max") -Like "role", "closed list") "text with neither a length nor a closed list is refused"
Check (Refused -Rows (Table "role" @{ min = -1 }) -Like "role", "smallest") "a smallest length below 0 is refused"
Check (Refused -Rows (Table "role" @{ max = 4097 }) -Like "role", "largest") "a largest length above 4096 is refused"
Check (Refused -Rows (Table "role" @{ min = 1.0 }) -Like "role", "smallest") "a length written as 1.0 is refused"
Check (Refused -Rows (Table "role" @{ min = 13 }) -Like "role", "above") "a smallest length above the largest is refused"
Check (Refused -Rows (Table "role" @{ values = @("chief") }) -Like "role", "not both") "a length and a closed list together are refused"
Check (Refused -Rows (Table "theme" @{ default = "Dark" }) -Like "theme", "default", "one of: system, light, dark") "a default outside the closed list is refused, and the list is compared exactly"
Check (Refused -Rows (Table "theme" @{ values = @() }) -Like "theme", "closed list") "an empty closed list is refused"
Check (Refused -Rows (Table "theme" @{ values = "system" }) -Like "theme", "closed list") "a closed list that is one text and not a list is refused"
Check (Refused -Rows (Table "theme" @{ values = @("system", "light", "system") }) -Like "theme", "twice") "a closed list holding a value twice is refused"
Check (Refused -Rows (Table "theme" @{ values = @("system", 5) }) -Like "theme", "closed list") "a closed list holding something that is not text is refused"
Check (Refused -Rows (Table "theme" @{ values = @("system", "") }) -Like "theme", "closed list") "a closed list holding empty text is refused"
Check (Refused -Rows (Table "theme" @{ values = @("system", "two`nlines") }) -Like "theme", "closed list") "a closed list holding a control character is refused"
Check (Refused -Rows (Table "theme" @{ values = @("system", ("t" * 4097)) }) -Like "theme", "closed list") "a closed list holding text over 4096 characters is refused"
Check ((Declared (Table "theme" @{ values = @("system", "System") }) "theme").values.Count -eq 2) "two listed values that differ in case are two values"
Check ((Declared (Table "theme" @{ values = @("system") }) "theme").values.Count -eq 1) "a closed list of one value stays a list"

Section "a folder's table entry"
foreach ($good in @("C:\status", "c:/status", "\\server\share\status", "D:\")) {
    Check ((Declared (Table "statusFolder" @{ default = $good }) "statusFolder").default -ceq $good) ("the folder default '" + $good + "' is accepted as written")
}
foreach ($bad in @("status", ".\status", "..\status", "C:status", "\status", "/status", "C:\a|b", "C:\a`nb", ("C:\" + ("f" * 1022)), 5, $true, $null)) {
    $shown = $(if ($null -eq $bad) { "null" } else { $bad.GetType().Name + " of " + ("" + $bad).Length })
    Check (Refused -Rows (Table "statusFolder" @{ default = $bad }) -Like "statusFolder", "default", "an absolute folder path") ("a folder default may not be " + $shown + " (" + $(if ($bad -is [string] -and $bad.Length -lt 20) { $bad -replace "\s", "?" } else { "..." }) + ")")
}
Check ((Declared (Table "statusFolder" @{ default = ("C:\" + ("f" * 1021)) }) "statusFolder").default.Length -eq 1024) "a folder of 1024 characters is accepted"
Check (Refused -Rows (Table "statusFolder" @{ min = 1 }) -Like "statusFolder", "'min'") "a smallest value on a folder is refused"
Check (Refused -Rows (Table "statusFolder" @{ values = @("C:\a") }) -Like "statusFolder", "'values'") "a closed list on a folder is refused"

# ---------------------------------------------------------------------------------------------------
# THE PURE READING. Everything below hands Read-HordeModuleSettingsText a text; no file is involved.

function Doc { param([string]$Settings) return ('{ "schemaVersion": 1, "settings": ' + $Settings + ' }') }
function FromText { param($Text) return (Read-HordeModuleSettingsText -Declaration $decl -Text $Text) }
function Says {
    # Does exactly one finding hold every -Like part? Prints the findings when not.
    param($Result, [string[]]$Like)
    $hits = 0
    foreach ($f in @($Result.findings)) { $all = $true; foreach ($part in $Like) { if ($f -notlike ("*" + $part + "*")) { $all = $false } }; if ($all) { $hits++ } }
    if ($hits -ne 1) { foreach ($f in @($Result.findings)) { Write-Host ("    finding: " + $f) -ForegroundColor DarkYellow } }
    return ($hits -eq 1)
}
function AllDefaults {
    param($Result)
    $v = $Result.values
    return ($v.widthPx -is [int] -and $v.widthPx -eq 520 -and $v.share -is [double] -and $v.share -eq 0.25 -and $v.follow -is [bool] -and $v.follow -eq $true -and
            $v.role -ceq "chief" -and $v.theme -ceq "system" -and $v.statusFolder -ceq "")
}
function Unreadable {
    # A text that cannot be read as a whole: one or more findings, each saying so, each holding every
    # -Like part, and every setting its default.
    param($Text, [string[]]$Like = @())
    $r = FromText $Text
    $n = @($r.findings).Count
    $good = ($n -ge 1 -and (AllDefaults $r))
    foreach ($f in @($r.findings)) { foreach ($part in (@("the settings file of probe ", "every setting of probe is its default") + $Like)) { if ($f -notlike ("*" + $part + "*")) { $good = $false } } }
    if (-not $good) { foreach ($f in @($r.findings)) { Write-Host ("    finding: " + $f) -ForegroundColor DarkYellow } }
    return $good
}
function WrongValue {
    # One setting given a wrong value beside a good one: exactly one finding, naming the key, its rule
    # and what was given; the setting is its default; the good one beside it is still read.
    param([string]$Key, [string]$Json, [string]$Given)
    $r = FromText (Doc ('{ "' + $Key + '": ' + $Json + ', "theme": "dark" }'))
    $entry = @($decl.settings | Where-Object { $_.name -ceq $Key })[0]
    $named = Says $r @(("probe setting '" + $Key + "' must be " + (Get-HordeModuleSettingRule -Entry $entry) + ";"), ("the file gives " + $Given + ";"), "the default is used")
    $kept = ($r.values.$Key -eq $entry.default -and $r.values.$Key.GetType() -eq $entry.default.GetType())
    return ($named -and $kept -and @($r.findings).Count -eq 1 -and $r.values.theme -ceq "dark")
}

Section "no file, and a file that changes nothing"
$none = FromText $null
Check (AllDefaults $none) "with no file every setting is its declared default"
Check (@($none.findings).Count -eq 0 -and $none.findings -is [array]) "and there is no finding: findings is an empty list, not nothing"
Check ((@($none.values.PSObject.Properties | ForEach-Object { $_.Name }) -join ",") -ceq "widthPx,share,follow,role,theme,statusFolder") "values holds every declared name, in the declared order"
Check (Throws { $null = $none.values.widthPixels } "") "a name the module did not declare cannot be read from values: a typo is an error, not an empty value"
$empty = FromText (Doc "{}")
Check ((AllDefaults $empty) -and @($empty.findings).Count -eq 0) "a file that sets nothing is every default and no finding"

Section "a good file"
$all = FromText (Doc '{ "widthPx": 640, "share": 0.5, "follow": false, "role": "scout", "theme": "dark", "statusFolder": "C:\\status files" }')
Check (@($all.findings).Count -eq 0) "a file of six good values has no finding"
Check ($all.values.widthPx -is [int] -and $all.values.widthPx -eq 640) "a whole number is read, as an Int32"
Check ($all.values.share -is [double] -and $all.values.share -eq 0.5) "a fraction is read, as a Double"
Check ($all.values.follow -is [bool] -and $all.values.follow -eq $false) "false is read, as a Boolean"
Check ($all.values.role -ceq "scout") "text with a length is read"
Check ($all.values.theme -ceq "dark") "text from a closed list is read"
Check ($all.values.statusFolder -ceq "C:\status files") "a folder is read, exactly as written"
$one = FromText (Doc '{ "widthPx": 200 }')
Check ($one.values.widthPx -eq 200 -and $one.values.share -eq 0.25 -and $one.values.role -ceq "chief" -and @($one.findings).Count -eq 0) "a file overrides only what it names; the smallest allowed whole number is allowed"
Check ((FromText (Doc '{ "widthPx": 4000 }')).values.widthPx -eq 4000) "the largest allowed whole number is allowed"
Check ((FromText (Doc '{ "share": 1e-1 }')).values.share -eq 0.1) "a fraction written with an exponent is a number: 1e-1 is the smallest allowed here"
Check ((FromText (Doc '{ "share": 0.9 }')).values.share -eq 0.9) "the largest allowed fraction is allowed"
$unit = New-HordeModuleSettings -Module "probe" -Settings @(@{ name = "share"; kind = "fraction"; default = 0.5; min = 0; max = 1; what = "A share." })
function UnitShare { param([string]$Json) return (Read-HordeModuleSettingsText -Declaration $unit -Text (Doc ('{ "share": ' + $Json + ' }'))) }
Check ((UnitShare "0").values.share -is [double] -and (UnitShare "0").values.share -eq 0.0 -and @((UnitShare "0").findings).Count -eq 0) "a fraction written as 0 is the Double 0"
Check ((UnitShare "1").values.share -is [double] -and (UnitShare "1").values.share -eq 1.0) "a fraction written as 1 is the Double 1"
Check ((UnitShare "0.99999999999999999999").values.share -eq 1.0 -and @((UnitShare "0.99999999999999999999").findings).Count -eq 0) "a fraction is compared as the Double the module gets: twenty nines are 1"
Check ((UnitShare "1.0000001").values.share -eq 0.5 -and @((UnitShare "1.0000001").findings).Count -eq 1) "a fraction just above 1 is refused"
Check ((UnitShare "-0.0000001").values.share -eq 0.5 -and @((UnitShare "-0.0000001").findings).Count -eq 1) "a fraction just below 0 is refused"
$accent = "caf" + [char]0xE9 + " " + [char]0x4E2D + [char]0x6587
Check ((FromText (Doc ('{ "role": "' + $accent + '" }'))).values.role -ceq $accent) "a text value that is not ASCII is read as it is"
Check ((FromText (Doc '{ "role": "caf\u00e9" }')).values.role -ceq ("caf" + [char]0xE9)) "and so is one written with an escape"
Check ((FromText (Doc ('{ "statusFolder": "C:\\Users\\' + $accent + '\\status" }'))).values.statusFolder -ceq ("C:\Users\" + $accent + "\status")) "a folder under a name that is not ASCII is read as it is"
Check ((FromText (Doc '{ "statusFolder": "\\\\server\\share\\status" }')).values.statusFolder -ceq "\\server\share\status") "a folder on a share is absolute"
Check ((FromText (Doc '{ "statusFolder": "d:/status" }')).values.statusFolder -ceq "d:/status") "a folder written with forward slashes is absolute, and is not rewritten"
Check ((FromText (Doc '{ "statusFolder": "C:\\a\\..\\b" }')).values.statusFolder -ceq "C:\a\..\b") "a folder is not normalised: what the module gets is what the person wrote"
Check ((FromText ('{ "schemaVersion": 1.0, "settings": { "widthPx": 640 } }')).values.widthPx -eq 640) "schemaVersion 1.0 is version 1, as core/Schema.ps1 reads an integer"
Check ((FromText ('{ "settings": { "widthPx": 640 }, "schemaVersion": 1 }')).values.widthPx -eq 640) "the order of the file's two parts does not matter"

Section "a wrong value is reported by name and its default is used"
Check (WrongValue "widthPx" "520.0" "the number 520.0") "a whole number written 520.0 is a wrong kind"
Check (WrongValue "widthPx" '"640"' "text of 3 characters") "a whole number written as text is a wrong kind"
Check (WrongValue "widthPx" "6.4e2" "the number 640") "a whole number written with an exponent is a wrong kind"
Check (WrongValue "widthPx" "true" "true") "true is not a whole number"
Check (WrongValue "widthPx" "null" "null") "null is not a whole number"
Check (WrongValue "widthPx" "[640]" "a list") "a list is not a whole number"
Check (WrongValue "widthPx" '{ "px": 640 }' "an object") "an object is not a whole number"
Check (WrongValue "widthPx" "199" "the whole number 199") "a whole number one below the smallest is out of range"
Check (WrongValue "widthPx" "4001" "the whole number 4001") "a whole number one above the largest is out of range"
Check (WrongValue "widthPx" "-640" "the whole number -640") "a negative whole number is out of range here"
Check (WrongValue "widthPx" "5000000000" "the whole number 5000000000") "a whole number beyond an Int32 is out of range"
Check (WrongValue "widthPx" "99999999999999999999" "the number 99999999999999999999") "a whole number beyond an Int64 is refused"
Check (WrongValue "widthPx" "1e30" "the number 1E+30") "1e30 is refused as a whole number"
Check (WrongValue "share" '"0.5"' "text of 3 characters") "a fraction written as text is a wrong kind"
Check (WrongValue "share" "true" "true") "true is not a fraction"
Check (WrongValue "share" "null" "null") "null is not a fraction"
Check (WrongValue "share" "[0.5]" "a list") "a list is not a fraction"
Check (WrongValue "share" "0.05" "the number 0.05") "a fraction below the smallest is out of range"
Check (WrongValue "share" "0.95" "the number 0.95") "a fraction above the largest is out of range"
Check (WrongValue "share" "5" "the whole number 5") "5 is no fraction"
Check (WrongValue "share" "1e30" "the number 1E+30") "1e30 is no fraction"
Check (WrongValue "share" "-0.5" "the number -0.5") "a negative number is no fraction"
Check (WrongValue "follow" '"true"' "text of 4 characters") "true in quotes is a wrong kind"
Check (WrongValue "follow" "1" "the whole number 1") "1 is not true"
Check (WrongValue "follow" "0" "the whole number 0") "0 is not false"
Check (WrongValue "follow" "null" "null") "null is not true or false"
Check (WrongValue "role" '""' "text of 0 characters") "text shorter than the smallest length is out of range"
Check (WrongValue "role" '"SECRETSECRET1"' "text of 13 characters") "text longer than the largest length is out of range"
Check (WrongValue "role" "5" "the whole number 5") "a number is not text"
Check (WrongValue "role" "true" "true") "true is not text"
Check (WrongValue "role" "null" "null") "null is not text"
Check (WrongValue "role" '["chief"]' "a list") "a list is not text"
Check (WrongValue "role" '{ "name": "chief" }' "an object") "an object is not text"
Check (WrongValue "role" '"two\nlines"' "text holding a control character") "text holding a line break is refused"
Check (WrongValue "role" '"a\u0000b"' "text holding a control character") "text holding a NUL is refused"
Check (WrongValue "role" '"a\u0085b"' "text holding a control character") "text holding a C1 control character is refused"
$r = FromText (Doc '{ "theme": "Dark" }')
Check ((Says $r @("probe setting 'theme' must be one of: system, light, dark;", "the file gives text of 4 characters;", "the default is used")) -and $r.values.theme -ceq "system") "a value outside the closed list is refused, and the list is compared exactly"
$r = FromText (Doc '{ "theme": 5, "widthPx": 640 }')
Check ((Says $r @("probe setting 'theme' must be one of: system, light, dark;", "the whole number 5")) -and $r.values.theme -ceq "system" -and $r.values.widthPx -eq 640) "a number is not on a closed list of text"
Check (WrongValue "statusFolder" '"status"' "text of 6 characters") "a folder that is a bare name is refused"
Check (WrongValue "statusFolder" '"..\\status"' "text of 9 characters") "a folder relative to the current folder is refused"
Check (WrongValue "statusFolder" '"C:status"' "text of 8 characters") "a folder relative to a drive's current folder is refused"
Check (WrongValue "statusFolder" '"\\status"' "text of 7 characters") "a folder relative to the current drive is refused"
Check (WrongValue "statusFolder" '""' "text of 0 characters") "a file may not say an empty folder: it leaves the key out"
Check (WrongValue "statusFolder" '"C:\\a|b"' "text of 6 characters") "a folder holding a character no path may hold is refused"
Check (WrongValue "statusFolder" ('"C:\\' + ("f" * 1022) + '"') "text of 1025 characters") "a folder over 1024 characters is refused"
Check ((FromText (Doc ('{ "statusFolder": "C:\\' + ("f" * 1021) + '" }'))).values.statusFolder.Length -eq 1024) "a folder of 1024 characters is read"
Check (WrongValue "statusFolder" "5" "the whole number 5") "a number is not a folder"
Check (WrongValue "statusFolder" "null" "null") "null is not a folder"
$r = FromText (Doc '{ "role": "SECRETSECRET1", "statusFolder": "SECRET-relative", "theme": "SECRET-theme" }')
Check (@($r.findings).Count -eq 3 -and @($r.findings | Where-Object { $_ -like "*SECRET*" }).Count -eq 0) "NO FINDING QUOTES A TEXT VALUE: three wrong texts, three findings, none holding the text"

Section "an unknown key is reported by name"
$r = FromText (Doc '{ "colour": "red", "widthPx": 640 }')
Check ((Says $r @("probe has no setting 'colour'", "it is not used")) -and @($r.findings).Count -eq 1 -and $r.values.widthPx -eq 640) "a key the module did not declare is one finding, and the keys beside it are read"
Check (@($r.values.PSObject.Properties | Where-Object { $_.Name -ceq "colour" }).Count -eq 0 -and @($r.values.PSObject.Properties).Count -eq 6) "and it is not among the values"
Check (@($r.findings | Where-Object { $_ -like "*case-sensitive*" }).Count -eq 0) "a key that is no declared name in any case gets no hint"
$r = FromText (Doc '{ "WidthPx": 640 }')
Check ((Says $r @("probe has no setting 'WidthPx'", "names are case-sensitive", "'widthPx'")) -and $r.values.widthPx -eq 520) "A NAME IS COMPARED EXACTLY: WidthPx is an unknown key, its finding says which name was meant, and widthPx is its default"
$r = FromText (Doc '{ "colour": 1, "size": 2, "widthPx": "wide", "share": 7 }')
Check (@($r.findings).Count -eq 4 -and (Says $r "'colour'") -and (Says $r "'size'") -and (Says $r "'widthPx'") -and (Says $r "'share'") -and (AllDefaults $r)) "four things wrong are four findings, one per key"
$longKey = "k" * 100
$r = FromText (Doc ('{ "' + $longKey + '": 1 }'))
Check ((Says $r @(("'" + ("k" * 60) + "...'"))) -and @($r.findings | Where-Object { $_ -like ("*" + ("k" * 61) + "*") }).Count -eq 0) "an unknown key's name is cut at 60 characters"
$r = FromText (Doc ('{ "' + ("k" * 60) + '": 1 }'))
Check (Says $r @(("'" + ("k" * 60) + "'"))) "and one of exactly 60 is not cut"
$r = FromText (Doc ('{ "caf' + [char]0xE9 + '\u0007~ ": 1 }'))
Check ((Says $r @("'caf\u00E9\u0007~ '")) -and @($r.findings | Where-Object { $_ -cmatch '[^\x20-\x7E]' }).Count -eq 0) "an unknown key's name is written in printable ASCII, the rest as \uXXXX"
$r = FromText (Doc '{ "__proto__": 1, "constructor": 2, "Count": 3, "Length": 4, "ToString": 5 }')
Check (@($r.findings).Count -eq 5 -and (Says $r "'__proto__'") -and (Says $r "'ToString'") -and (AllDefaults $r)) "keys named after things a language keeps are unknown keys like any other"

Section "a text that cannot be read as a whole is its findings and every default"
Check (Unreadable "widthPx = 640" "is not JSON: line 1") "text that is not JSON is one finding"
Check (@((FromText "widthPx = 640").findings).Count -eq 1) "exactly one"
Check (Unreadable "" "does not fit schema/module-settings.v1") "an empty file is not a settings file"
Check (Unreadable "   `r`n  " "does not fit") "a file of blanks is not a settings file"
Check (Unreadable "null" "does not fit") "null is not a settings file"
Check (Unreadable "[]" "should be object") "A FILE THAT IS A LIST is not a settings file"
Check (Unreadable ('[' + (Doc '{ "widthPx": 640 }') + ']') "should be object") "a list holding one good settings file is not a settings file"
Check (Unreadable '"settings"' "should be object") "a file that is one text is not a settings file"
Check (Unreadable "640" "should be object") "a file that is one number is not a settings file"
Check (Unreadable '{ "schemaVersion": 1, "settings": { "widthPx": 640 }' "is not JSON") "an object that never closes is not JSON"
Check (Unreadable '{ "schemaVersion": 1, "settings": { "widthPx": 640, } }' "is not JSON") "a trailing comma is not JSON"
Check (Unreadable ((Doc '{ "widthPx": 640 }') + (Doc '{ "widthPx": 300 }')) "is not JSON") "two documents in one file are not JSON"
Check (Unreadable ('{ "schemaVersion": 1, "settings": { "widthPx": 640 } } // wide') "is not JSON: line 1") "a comment is not JSON"
Check (Unreadable ("{`n  `"schemaVersion`": 1,`n  `"settings`": { 'widthPx': 640 }`n}") "is not JSON: line 3") "SINGLE QUOTES ARE NOT JSON, and the finding says the line: 5.1's parser accepts them, and the duplicate-key scan sees only double-quoted keys"
Check (Unreadable "{ 'schemaVersion': 1, 'settings': { 'widthPx': 640, 'widthPx': 300 } }" "is not JSON") "so a key repeated in single quotes cannot slip one value past the other"
Check (Unreadable '{ schemaVersion: 1, settings: { widthPx: 640, widthPx: 300 } }' "is not JSON") "nor can one repeated with no quotes at all"
Check (Unreadable (Doc '{ "share": NaN }') "is not JSON") "NaN is not JSON, though 5.1's parser reads it as a number that is inside every range"
Check (Unreadable (Doc '{ "share": Infinity }') "is not JSON") "Infinity is not JSON"
Check (Unreadable (Doc '{ "widthPx": 0640 }') "is not JSON") "a number with a leading zero is not JSON, though 5.1's parser reads 0640 as 640"
Check (Unreadable (Doc '{ "widthPx": +640 }') "is not JSON") "a number with a plus sign is not JSON"
Check (Unreadable (Doc '{ "widthPx": 0x280 }') "is not JSON") "a number in hexadecimal is not JSON"
Check (Unreadable (Doc '{ "widthPx": 640. }') "is not JSON") "a number ending in a point is not JSON"
Check (Unreadable (Doc '{ "widthPx": 640px }') "is not JSON") "a number with a unit is not JSON"
Check (Unreadable (Doc ('{ "role": "tab' + "`t" + 'here" }')) "is not JSON") "a raw tab inside a string is not JSON"
Check (Unreadable (Doc '{ "role": "a\qb" }') "is not JSON") "an escape JSON does not have is not JSON"
Check (Unreadable (Doc '{ "share": 1e400 }') "is not JSON") "A NUMBER TOO LARGE TO HOLD is not JSON to the parser: one finding, never an error"
Check (Unreadable (Doc ('{ "role": ' + ("[" * 200) + ("]" * 200) + ' }')) "is not JSON") "VALUES NESTED 200 DEEP are past the parser's limit: one finding, never an error"
Check (Unreadable (Doc '{ "": 1 }') "is not JSON the parser can read") "an empty key is refused by the parser: one finding, never an error"
Check (Unreadable (Doc '{ "PSObject": 1, "widthPx": 640 }') "is not JSON the parser can read") "a key named PSObject is refused by 5.1's parser, which keeps that name for itself: one finding, never an error"
Check (Unreadable (("1" * 200000) + "x") "is not JSON") "two hundred thousand digits and a letter are not JSON, and saying so does not take the suite's time"
Check (Unreadable ('{ "a": "' + ("\\" * 100000)) "is not JSON") "nor does a string of a hundred thousand backslashes that never ends"

Section "a key written twice"
$r = FromText (Doc '{ "widthPx": 640, "widthPx": 300, "theme": "dark" }')
Check ((Unreadable (Doc '{ "widthPx": 640, "widthPx": 300, "theme": "dark" }') @("says one thing twice", "'widthPx'")) -and $r.values.widthPx -eq 520 -and $r.values.theme -ceq "system") "A KEY WRITTEN TWICE is a finding naming it, and NEITHER value is used, nor anything else in the file"
Check (Unreadable (Doc '{ "widthPx": 640, "width\u0050x": 300 }') @("says one thing twice", "'widthPx'")) "a key written twice, once with an escape, is the same key"
Check (Unreadable (Doc '{ "widthPx": 640, "WIDTHPX": 300 }') @("says one thing twice", "'WIDTHPX'")) "KEYS THAT DIFFER ONLY IN CASE are a finding: 5.1's parser throws on them, and the scan names the key"
Check (Unreadable '{ "schemaVersion": 1, "settings": { "widthPx": 640 }, "settings": { "widthPx": 300 } }' @("says one thing twice", "'settings'")) "the file's own part written twice is a finding"
Check (Unreadable (Doc '{ "role": { "a": 1, "a": 2 } }') @("says one thing twice", "'a'")) "a key written twice inside a nested value is a finding too"
Check (@((FromText (Doc '{ "widthPx": 640, "widthPx": 300, "share": 0.5, "share": 0.6 }')).findings).Count -eq 2) "two keys written twice are two findings"

Section "a file that is not the shape of schema/module-settings.v1"
Check (Unreadable '{ "settings": { "widthPx": 640 } }' @("does not fit schema/module-settings.v1", "'schemaVersion'")) "a file with no schemaVersion is not read"
Check (Unreadable '{ "schemaVersion": 2, "settings": { "widthPx": 640 } }' @("does not fit", "schemaVersion")) "a file of another version is not read: nobody knows its shape"
Check (Unreadable '{ "schemaVersion": "1", "settings": { "widthPx": 640 } }' @("does not fit", "schemaVersion")) "a version written as text is not read"
Check (Unreadable '{ "schemaVersion": 1 }' @("does not fit", "'settings'")) "a file with no settings part is not read"
Check (Unreadable '{ "schemaVersion": 1, "settings": [ { "widthPx": 640 } ] }' @("does not fit", "settings should be object")) "settings that are a list are not read"
Check (Unreadable '{ "schemaVersion": 1, "settings": null }' @("does not fit", "settings should be object")) "settings that are null are not read"
Check (Unreadable '{ "schemaVersion": 1, "settings": "widthPx" }' @("does not fit", "settings should be object")) "settings that are text are not read"
Check (Unreadable '{ "schemaVersion": 1, "widthPx": 640 }' @("does not fit")) "a setting written beside the settings part, not in it, is not read"
Check (Unreadable '{ "schemaVersion": 1, "settings": { "widthPx": 640 }, "comment": "wide" }' @("does not fit", "'comment'")) "a part the schema does not have is named, and the file is not read"
Check (Unreadable '{ "schemaVersion": 1, "Settings": { "widthPx": 640 } }' @("does not fit")) "the file's own names are compared exactly too: Settings is not settings"
Check (@((FromText '{ "comment": 1 }').findings).Count -eq 3) "every way a file misses the schema is its own finding (no version, no settings, a part it does not have)"

Section "a byte-order mark, and a file's length"
$mark = [string][char]0xFEFF
$r = FromText ($mark + (Doc '{ "widthPx": 640 }'))
Check ($r.values.widthPx -eq 640 -and @($r.findings).Count -eq 0) "A LEADING BYTE-ORDER MARK is skipped: editors write one, and 5.1's parser refuses it"
Check (Unreadable ($mark + $mark + (Doc '{ "widthPx": 640 }')) "is not JSON") "only one, and only at the start"
Check (Unreadable ((Doc '{ "widthPx": 640 }') + $mark) "is not JSON") "a mark anywhere else is not JSON"
$good = Doc '{ "widthPx": 640 }'
$atCap = $good + (" " * (262144 - $good.Length))
$r = FromText $atCap
Check ($atCap.Length -eq 262144 -and $r.values.widthPx -eq 640 -and @($r.findings).Count -eq 0) "a text of 262144 characters is read"
Check (Unreadable ($atCap + " ") "is longer than 262144 characters") "one character more is one finding and every default, whatever it holds"
$r = FromText ($mark + $atCap)
Check ($r.values.widthPx -eq 640 -and @($r.findings).Count -eq 0) "the mark is not counted in the length"

Section "what the pure reading refuses, and what it never touches"
Check (Throws { Read-HordeModuleSettingsText -Declaration $decl -Text 640 } "text") "a -Text that is not text is a programming error"
Check (Throws { Read-HordeModuleSettingsText -Declaration @{ module = "probe"; settings = @() } -Text $null } "New-HordeModuleSettings") "a -Declaration that New-HordeModuleSettings did not make is a programming error"
Check (Throws { Read-HordeModuleSettingsText -Declaration "probe" -Text $null } "New-HordeModuleSettings") "and so is a module's name in its place"
$homeBefore = $env:HORDE_HOME
try {
    # A relative home makes Get-HordeHome throw (core/Home.ps1), so a reading that asked for the home
    # would throw here.
    $env:HORDE_HOME = "relative\home"
    $r = FromText (Doc '{ "widthPx": 640 }')
    Check ($r.values.widthPx -eq 640 -and @($r.findings).Count -eq 0) "THE PURE READING NEVER ASKS WHERE THE HOME IS: it answers with a home nobody could use"
} finally { $env:HORDE_HOME = $homeBefore }
$r = FromText (Doc '{ "widthPx": 640 }')
$r.values.widthPx = 1
Check ((FromText $null).values.widthPx -eq 520 -and $decl.settings[0].default -eq 520) "an answer is the caller's own: changing it changes neither the declaration nor the next answer"
$hostile = FromText (Doc ('{ "caf' + [char]0xE9 + '": "x", "role": "' + [char]0x4E2D + '\u0001", "' + ("k" * 500) + '": [[[1]]] }'))
Check (@($hostile.findings).Count -eq 3 -and @($hostile.findings | Where-Object { $_ -cmatch '[^\x20-\x7E]' -or $_.Length -gt 403 }).Count -eq 0) "every finding is printable ASCII, and at most 400 characters and a mark that it was cut"

Complete-HordeSuite -Success "a module's settings are its declared defaults, overridden by one file under the home, and everything wrong is said by name"
