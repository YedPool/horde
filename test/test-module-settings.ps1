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

Complete-HordeSuite -Success "a module's settings are its declared defaults, overridden by one file under the home, and everything wrong is said by name"
