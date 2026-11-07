# DOES A MODULE GET ITS SETTINGS FROM ITS OWN DECLARED DEFAULTS AND ONE FILE UNDER THE HOME, AND IS A
# FILE THAT FAILS A CHECK REFUSED WITH EVERYTHING WRONG IN IT SAID BY NAME, NEVER READ IN PART?
#
# core/ModuleSettings.ps1. Three parts, as the file has three entry points: the declaration (a malformed
# table is a programming error and throws), the pure reading of a file's text, and the reading of the
# file itself in a home this suite creates under TEMP and removes. Nothing here reads or writes the
# real home. THE RULE UNDER TEST: an answer is "defaults" (no file), "read" (the file passed every
# check) or "refused" (it failed one: no values at all, and a finding for every problem, each naming
# the file). No check below may find a default standing in for a bad value.

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
    foreach ($part in $Like) { if ($message -cnotlike ("*" + $part + "*")) { Write-Host ("    got: " + $message) -ForegroundColor DarkYellow; return $false } }
    return $true
}

function Declared {
    # The declared entry called -Name, from a table that must be accepted. A TABLE REFUSED HERE IS A
    # FAILED CHECK, not an error of the suite: the answer is then an entry no check expects, so the
    # check that asked fails, and tools\Mutate.ps1 counts the mutant that caused it as caught.
    param([object[]]$Rows, [string]$Name)
    $d = $null
    try { $d = New-HordeModuleSettings -Module "probe" -Settings $Rows }
    catch { Write-Host ("    got: it was refused: " + $_.Exception.Message) -ForegroundColor DarkYellow; return [pscustomobject]@{ name = "<refused>"; kind = "<refused>"; default = "<refused>"; what = "<refused>"; min = $null; max = $null; values = @() } }
    return @($d.settings | Where-Object { $_.name -ceq $Name })[0]
}

# ---------------------------------------------------------------------------------------------------
Section "the declaration"
Check ((Throws { New-HordeModuleSettings -Module "probe" -Settings (Table) }) -eq $false) "a table with a setting of every kind is accepted"
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
    Check ((Throws { New-HordeModuleSettings -Module $good -Settings (Table) }) -eq $false) ("the module name '" + $good + "' is accepted")
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
foreach ($bad in @(199, 4001, 520.0, "520", $true, $null, 5000000000, [long]5000000000, [long]4001, [long]-2147483649, [decimal]520)) {
    $shown = $(if ($null -eq $bad) { "null" } else { $bad.GetType().Name + " " + $bad })
    Check (Refused -Rows (Table "widthPx" @{ default = $bad }) -Like "widthPx", "default", "a whole number from 200 to 4000") ("a whole number's default may not be " + $shown)
}
# AN Int64 IS A WHOLE NUMBER TOO. PowerShell 7's ConvertFrom-Json reads every whole number as an Int64
# (5.1 reads one that fits as an Int32), so a file's 640 arrives as [long] there; the value and the
# default go through one check, so this is the file's case without a parser that makes it.
$wide = Declared (Table "widthPx" @{ default = [long]520 }) "widthPx"
Check ($wide.default -is [int] -and $wide.default -eq 520) "a whole number's default given as an Int64 within the range is accepted, as an Int32"
Check ((Declared (Table "widthPx" @{ default = [long]-5; min = -10; max = -1 }) "widthPx").default -is [int]) "and so is a negative one"
Check (Refused -Rows (Table "widthPx" @{ min = [long]200 }) -Like "widthPx", "smallest") "a smallest value is still an Int32 written in the table: [long] there is a programming choice, not a parser's"
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
$span = Declared (Table "share" @{ min = 0; max = 1 }) "share"
Check ($span.min -is [double] -and $span.min -eq 0.0 -and $span.max -is [double] -and $span.max -eq 1.0) "a fraction may span the whole of 0 to 1, and its smallest and largest are Doubles however they were written"
$wideShare = Declared (Table "share" @{ default = [long]1; min = 0; max = 1 }) "share"
Check ($wideShare.default -is [double] -and $wideShare.default -eq 1.0) "a fraction's default given as an Int64 is the Double 1: PowerShell 7 reads a file's 1 as an Int64"
foreach ($bad in @(0.05, 0.95, "0.25", $true, $null, [long]0, [double]::NaN, [double]::PositiveInfinity)) {
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
foreach ($bad in @("status", ".\status", "..\status", "C:status", "\status", "/status", "C:\a|b", "C:\a<b", "C:\a>b", 'C:\a"b', "C:\a`nb", ("C:\" + ("f" * 1022)), 5, $true, $null)) {
    $shown = $(if ($null -eq $bad) { "null" } else { $bad.GetType().Name + " of " + ("" + $bad).Length })
    Check (Refused -Rows (Table "statusFolder" @{ default = $bad }) -Like "statusFolder", "default", "an absolute folder path") ("a folder default may not be " + $shown + " (" + $(if ($bad -is [string] -and $bad.Length -lt 20) { $bad -replace "\s", "?" } else { "..." }) + ")")
}
Check ((Declared (Table "statusFolder" @{ default = ("C:\" + ("f" * 1021)) }) "statusFolder").default.Length -eq 1024) "a folder of 1024 characters is accepted"
Check (Refused -Rows (Table "statusFolder" @{ min = 1 }) -Like "statusFolder", "'min'") "a smallest value on a folder is refused"
Check (Refused -Rows (Table "statusFolder" @{ values = @("C:\a") }) -Like "statusFolder", "'values'") "a closed list on a folder is refused"

Section "a hub label's table entry"
# A label is checked by schema/link-verbs.v1's label pattern, the one definition: the same strings
# that pattern takes and refuses are taken and refused here.
function LabelRow { param($Default) return @(@{ name = "fromLabel"; kind = "label"; default = $Default; what = "Who a notice is from." }) }
$labelPattern = "$((Get-HordeSchema -Name 'link-verbs.v1').definitions.label.pattern)"
foreach ($good in @("F", "AB", "A1", "ZZ9999", "B12")) {
    Check (($good -cmatch $labelPattern) -and (Declared (LabelRow $good) "fromLabel").default -ceq $good) ("the label default '" + $good + "' is accepted, as the link's label pattern takes it")
}
foreach ($bad in @("f", "A0", "A01", "ABC", "A10000", "", "F`n", " F", "1", 5, $true, $null)) {
    $shown = $(if ($null -eq $bad) { "null" } else { $bad.GetType().Name + " " + ("" + $bad -replace "\s", "?") })
    Check (Refused -Rows (LabelRow $bad) -Like "fromLabel", "default", "a hub label") ("a label default may not be " + $shown)
}
Check (Refused -Rows @(@{ name = "fromLabel"; kind = "label"; default = "F"; min = 1; what = "Who." }) -Like "fromLabel", "'min'") "a smallest value on a label is refused"
Check (Refused -Rows @(@{ name = "fromLabel"; kind = "label"; default = "F"; values = @("F") }) -Like "fromLabel", "'values'") "a closed list on a label is refused"

# ---------------------------------------------------------------------------------------------------
# THE PURE READING. Everything below hands Read-HordeModuleSettingsText a text; no file is involved.

function Doc { param([string]$Settings) return ('{ "schemaVersion": 1, "settings": ' + $Settings + ' }') }
function FromText {
    # -File is handed on only when one is given, so most checks also cover the name used without it.
    param($Text, [string]$File = "")
    if ($File -cne "") { return (Read-HordeModuleSettingsText -Declaration $decl -Text $Text -File $File) }
    return (Read-HordeModuleSettingsText -Declaration $decl -Text $Text)
}
# How every finding of the pure reading starts when no -File is given: the file, the module, what was done.
$refusal = "the settings file 'settings\probe.json' of probe is refused: "
function IsRefusal {
    # Is this answer a refusal: the state says so, there are NO values (not defaults: nothing), and
    # there is at least one finding, each starting by naming the file (-Start) and saying it is refused?
    param($Result, [string]$Start = $refusal)
    if ($null -eq $Result) { return $false }
    $good = ($Result.state -ceq "refused" -and $null -eq $Result.values -and $Result.findings -is [array] -and @($Result.findings).Count -ge 1)
    foreach ($f in @($Result.findings)) { if (-not $f.StartsWith($Start, [System.StringComparison]::Ordinal)) { $good = $false } }
    if (-not $good) { Write-Host ("    got: state " + $Result.state + ", values " + $(if ($null -eq $Result.values) { "none" } else { "present" })) -ForegroundColor DarkYellow; foreach ($f in @($Result.findings)) { Write-Host ("    finding: " + $f) -ForegroundColor DarkYellow } }
    return $good
}
function Says {
    # Does exactly one finding hold every -Like part? Prints the findings when not.
    param($Result, [string[]]$Like)
    $hits = 0
    foreach ($f in @($Result.findings)) { $all = $true; foreach ($part in $Like) { if ($f -cnotlike ("*" + $part + "*")) { $all = $false } }; if ($all) { $hits++ } }
    if ($hits -ne 1) { foreach ($f in @($Result.findings)) { Write-Host ("    finding: " + $f) -ForegroundColor DarkYellow } }
    return ($hits -eq 1)
}
function V {
    # The values of an answer, for a check that reads one. A REFUSAL HAS NONE, and under strict mode
    # reading a name from nothing is an error, which tools\Mutate.ps1 counts as a crash and not as a
    # mutant caught. So for a refusal this prints the findings and hands the check an object whose
    # every name is the text "<refused>": no check expects that, so the check that asked FAILS.
    param($Result)
    if ($null -ne $Result -and $null -ne $Result.values) { return $Result.values }
    if ($null -ne $Result) { foreach ($f in @($Result.findings)) { Write-Host ("    finding: " + $f) -ForegroundColor DarkYellow } }
    $none = New-Object psobject
    foreach ($n in @("widthPx", "share", "follow", "role", "theme", "statusFolder", "face")) { Add-Member -InputObject $none -NotePropertyName $n -NotePropertyValue "<refused>" }
    return $none
}
function AllDefaults {
    param($Result)
    if ($null -eq $Result -or $null -eq $Result.values) { return $false }
    $v = $Result.values
    return ($v.widthPx -is [int] -and $v.widthPx -eq 520 -and $v.share -is [double] -and $v.share -eq 0.25 -and $v.follow -is [bool] -and $v.follow -eq $true -and
            $v.role -ceq "chief" -and $v.theme -ceq "system" -and $v.statusFolder -ceq "")
}
function Unreadable {
    # A text that cannot be used as a whole: a refusal (no values), one or more findings, each saying
    # what "it" - the file - is, and each holding every -Like part.
    param($Text, [string[]]$Like = @())
    # A THROW IS A FAILED CHECK HERE, not an error of the suite: "never a throw" is what is being
    # checked, and tools\Mutate.ps1 counts only a failed check as a mutant caught.
    $r = $null
    try { $r = FromText $Text } catch { Write-Host ("    got: it threw: " + $_.Exception.Message) -ForegroundColor DarkYellow; return $false }
    $good = IsRefusal $r ($refusal + "it ")
    foreach ($f in @($r.findings)) { foreach ($part in $Like) { if ($f -cnotlike ("*" + $part + "*")) { $good = $false } } }
    if (-not $good) { foreach ($f in @($r.findings)) { Write-Host ("    finding: " + $f) -ForegroundColor DarkYellow } }
    return $good
}
function WrongValue {
    # One setting given a wrong value BESIDE A GOOD ONE: the whole file is refused, with exactly one
    # finding, which is the file, the key, its rule and what was given, word for word. The good value
    # beside it is not handed back, and neither is any default: there are no values.
    param([string]$Key, [string]$Json, [string]$Given)
    $r = $null
    try { $r = FromText (Doc ('{ "' + $Key + '": ' + $Json + ', "theme": "dark" }')) } catch { Write-Host ("    got: it threw: " + $_.Exception.Message) -ForegroundColor DarkYellow; return $false }
    $entry = @($decl.settings | Where-Object { $_.name -ceq $Key })[0]
    $want = $refusal + "its key '" + $Key + "' must be " + (Get-HordeModuleSettingRule -Entry $entry) + "; it gives " + $Given
    $good = ((IsRefusal $r) -and @($r.findings).Count -eq 1 -and $r.findings[0] -ceq $want)
    if (-not $good) { Write-Host ("    want:    " + $want) -ForegroundColor DarkYellow; foreach ($f in @($r.findings)) { Write-Host ("    finding: " + $f) -ForegroundColor DarkYellow } }
    return $good
}
function UnknownKey {
    # Does exactly one finding say, word for word, that the file has this key and the module no such
    # setting? -Shown is the key as a finding writes it; -Hint is what follows for a name meant.
    param($Result, [string]$Shown, [string]$Hint = "")
    return (@(@($Result.findings) | Where-Object { $_ -ceq ($refusal + "it has the key '" + $Shown + "', which is no setting of probe" + $Hint) }).Count -eq 1)
}

Section "no file, and a file that changes nothing"
Check ((Throws { FromText $null }) -eq $false) "no file is never an error"
$none = FromText $null
Check ((AllDefaults $none) -and $none.state -ceq "defaults") "with no file the state is defaults and every setting is its declared default"
Check (@($none.findings).Count -eq 0 -and $none.findings -is [array]) "and there is no finding: findings is an empty list, not nothing"
Check ((@($none.PSObject.Properties | ForEach-Object { $_.Name }) -join ",") -ceq "state,values,findings,path") "the answer is state, values, findings and path"
Check ($none.path -ceq "settings\probe.json") "without -File the path is the file's place under any home: settings\<module>.json"
Check ((FromText $null "C:\a home\settings\probe.json").path -ceq "C:\a home\settings\probe.json") "with -File the path is that, as given"
Check ((@((V $none).PSObject.Properties | ForEach-Object { $_.Name }) -join ",") -ceq "widthPx,share,follow,role,theme,statusFolder") "values holds every declared name, in the declared order"
Check (Throws { $null = (V $none).widthPixels } "") "a name the module did not declare cannot be read from values: a typo is an error, not an empty value"
$empty = FromText (Doc "{}")
Check ((AllDefaults $empty) -and @($empty.findings).Count -eq 0 -and $empty.state -ceq "read") "a file that sets nothing is read: every default, no finding, and the state says a file was there"

Section "a good file"
$all = FromText (Doc '{ "widthPx": 640, "share": 0.5, "follow": false, "role": "scout", "theme": "dark", "statusFolder": "C:\\status files" }')
Check (@($all.findings).Count -eq 0 -and $all.findings -is [array] -and $all.state -ceq "read") "a file of six good values is read, with no finding"
Check ((V $all).widthPx -is [int] -and (V $all).widthPx -eq 640) "a whole number is read, as an Int32"
Check ((V $all).share -is [double] -and (V $all).share -eq 0.5) "a fraction is read, as a Double"
Check ((V $all).follow -is [bool] -and (V $all).follow -eq $false) "false is read, as a Boolean"
Check ((V $all).role -ceq "scout") "text with a length is read"
Check ((V $all).theme -ceq "dark") "text from a closed list is read"
Check ((V $all).statusFolder -ceq "C:\status files") "a folder is read, exactly as written"
$one = FromText (Doc '{ "widthPx": 200 }')
Check ((V $one).widthPx -eq 200 -and (V $one).share -eq 0.25 -and (V $one).role -ceq "chief" -and @($one.findings).Count -eq 0) "a file overrides only what it names; the smallest allowed whole number is allowed"
Check ((V (FromText (Doc '{ "widthPx": 4000 }'))).widthPx -eq 4000) "the largest allowed whole number is allowed"
Check ((V (FromText (Doc '{ "share": 1e-1 }'))).share -eq 0.1) "a fraction written with an exponent is a number: 1e-1 is the smallest allowed here"
Check ((V (FromText (Doc '{ "share": 0.9 }'))).share -eq 0.9) "the largest allowed fraction is allowed"
$unit = New-HordeModuleSettings -Module "probe" -Settings @(@{ name = "share"; kind = "fraction"; default = 0.5; min = 0; max = 1; what = "A share." })
function UnitShare { param([string]$Json) return (Read-HordeModuleSettingsText -Declaration $unit -Text (Doc ('{ "share": ' + $Json + ' }'))) }
Check ((V (UnitShare "0")).share -is [double] -and (V (UnitShare "0")).share -eq 0.0 -and @((UnitShare "0").findings).Count -eq 0) "a fraction written as 0 is the Double 0"
Check ((V (UnitShare "1")).share -is [double] -and (V (UnitShare "1")).share -eq 1.0) "a fraction written as 1 is the Double 1"
Check ((V (UnitShare "0.99999999999999999999")).share -eq 1.0 -and @((UnitShare "0.99999999999999999999").findings).Count -eq 0) "a fraction is compared as the Double the module gets: twenty nines are 1"
Check ((IsRefusal (UnitShare "1.0000001")) -and @((UnitShare "1.0000001").findings).Count -eq 1) "a fraction just above 1 refuses the file"
Check ((IsRefusal (UnitShare "-0.0000001")) -and @((UnitShare "-0.0000001").findings).Count -eq 1) "a fraction just below 0 refuses the file"
$accent = "caf" + [char]0xE9 + " " + [char]0x4E2D + [char]0x6587
Check ((V (FromText (Doc ('{ "role": "' + $accent + '" }')))).role -ceq $accent) "a text value that is not ASCII is read as it is"
Check ((V (FromText (Doc '{ "role": "caf\u00e9" }'))).role -ceq ("caf" + [char]0xE9)) "and so is one written with an escape"
Check ((V (FromText (Doc ('{ "statusFolder": "C:\\Users\\' + $accent + '\\status" }')))).statusFolder -ceq ("C:\Users\" + $accent + "\status")) "a folder under a name that is not ASCII is read as it is"
Check ((V (FromText (Doc '{ "statusFolder": "\\\\server\\share\\status" }'))).statusFolder -ceq "\\server\share\status") "a folder on a share is absolute"
Check ((V (FromText (Doc '{ "statusFolder": "d:/status" }'))).statusFolder -ceq "d:/status") "a folder written with forward slashes is absolute, and is not rewritten"
Check ((V (FromText (Doc '{ "statusFolder": "C:\\a\\..\\b" }'))).statusFolder -ceq "C:\a\..\b") "a folder is not normalised: what the module gets is what the person wrote"
Check ((V (FromText ('{ "schemaVersion": 1.0, "settings": { "widthPx": 640 } }'))).widthPx -eq 640) "schemaVersion 1.0 is version 1, as core/Schema.ps1 reads an integer"
Check ((V (FromText ('{ "settings": { "widthPx": 640 }, "schemaVersion": 1 }'))).widthPx -eq 640) "the order of the file's two parts does not matter"

Section "a wrong value refuses the file, named with its key, and no default stands in for it"
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
Check ((IsRefusal $r) -and @($r.findings).Count -eq 1 -and $r.findings[0] -ceq ($refusal + "its key 'theme' must be one of: system, light, dark; it gives text of 4 characters")) "a value outside the closed list refuses the file, and the list is compared exactly"
$r = FromText (Doc '{ "theme": 5, "widthPx": 640 }')
Check ((IsRefusal $r) -and @($r.findings).Count -eq 1 -and $r.findings[0] -ceq ($refusal + "its key 'theme' must be one of: system, light, dark; it gives the whole number 5")) "a number is not on a closed list of text"
Check ($r.state -ceq "refused" -and $null -eq $r.values) "A GOOD VALUE BESIDE ONE BAD KEY IS NOT HANDED BACK: the file is refused whole, and values is null, so a caller that forgets the state cannot use a default by accident"
$r = FromText (Doc '{ "widthPx": 9999, "share": 7, "follow": "yes", "role": "scout" }')
Check ((IsRefusal $r) -and @($r.findings).Count -eq 3 -and (Says $r "its key 'widthPx' must be") -and (Says $r "its key 'share' must be") -and (Says $r "its key 'follow' must be")) "THREE BAD KEYS ARE THREE FINDINGS AND ONE REFUSAL: every problem is found in one pass, each named with its key"
Check (@($r.findings | Where-Object { $_ -like "*role*" }).Count -eq 0) "and the good key beside them is in no finding"
Check (WrongValue "statusFolder" '"status"' "text of 6 characters") "a folder that is a bare name is refused"
Check (WrongValue "statusFolder" '"..\\status"' "text of 9 characters") "a folder relative to the current folder is refused"
Check (WrongValue "statusFolder" '"C:status"' "text of 8 characters") "a folder relative to a drive's current folder is refused"
Check (WrongValue "statusFolder" '"\\status"' "text of 7 characters") "a folder relative to the current drive is refused"
Check (WrongValue "statusFolder" '""' "text of 0 characters") "a file may not say an empty folder: it leaves the key out"
Check (WrongValue "statusFolder" '"C:\\a|b"' "text of 6 characters") "a folder holding a character no path may hold is refused"
Check (WrongValue "statusFolder" ('"C:\\' + ("f" * 1022) + '"') "text of 1025 characters") "a folder over 1024 characters is refused"
Check ((V (FromText (Doc ('{ "statusFolder": "C:\\' + ("f" * 1021) + '" }')))).statusFolder.Length -eq 1024) "a folder of 1024 characters is read"
Check (WrongValue "statusFolder" "5" "the whole number 5") "a number is not a folder"
Check (WrongValue "statusFolder" "null" "null") "null is not a folder"
$r = FromText (Doc '{ "role": "SECRETSECRET1", "statusFolder": "SECRET-relative", "theme": "SECRET-theme" }')
Check ((IsRefusal $r) -and @($r.findings).Count -eq 3 -and @($r.findings | Where-Object { $_ -like "*SECRET*" }).Count -eq 0) "NO FINDING QUOTES A TEXT VALUE: three wrong texts, three findings, none holding the text"

Section "an unknown key refuses the file, by name"
$r = FromText (Doc '{ "colour": "red", "widthPx": 640 }')
Check ((IsRefusal $r) -and @($r.findings).Count -eq 1 -and (UnknownKey $r "colour")) "AN UNKNOWN KEY REFUSES: a key the module did not declare is one finding naming the file and the key, and the good key beside it is not handed back"
Check (@($r.findings | Where-Object { $_ -like "*case-sensitive*" }).Count -eq 0) "a key that is no declared name in any case gets no hint"
$r = FromText (Doc '{ "WidthPx": 640 }')
Check ((IsRefusal $r) -and @($r.findings).Count -eq 1 -and (UnknownKey $r "WidthPx" " (names are case-sensitive: 'widthPx' is one)")) "A NAME IS COMPARED EXACTLY: WidthPx is an unknown key, its finding says which name was meant, and the file is refused"
$r = FromText (Doc '{ "colour": 1, "size": 2, "widthPx": "wide", "share": 7 }')
Check ((IsRefusal $r) -and @($r.findings).Count -eq 4 -and (UnknownKey $r "colour") -and (UnknownKey $r "size") -and (Says $r "its key 'widthPx' must be") -and (Says $r "its key 'share' must be")) "four things wrong - two unknown keys, two wrong values - are four findings, one per key, and one refusal"
$longKey = "k" * 100
$r = FromText (Doc ('{ "' + $longKey + '": 1 }'))
Check ((UnknownKey $r (("k" * 60) + "...")) -and @($r.findings | Where-Object { $_ -like ("*" + ("k" * 61) + "*") }).Count -eq 0) "an unknown key's name is cut at 60 characters"
$r = FromText (Doc ('{ "' + ("k" * 60) + '": 1 }'))
Check (UnknownKey $r ("k" * 60)) "and one of exactly 60 is not cut"
$r = FromText (Doc ('{ "caf' + [char]0xE9 + '\u0007\u001f~ ' + [char]0x7F + '": 1 }'))
Check ((UnknownKey $r 'caf\u00E9\u0007\u001F~ \u007F') -and @($r.findings | Where-Object { $_ -cmatch '[^\x20-\x7E]' }).Count -eq 0) "an unknown key's name is written in printable ASCII (space to tilde, both kept), the rest as \uXXXX"
$r = FromText (Doc '{ "__proto__": 1, "constructor": 2, "Count": 3, "Length": 4, "ToString": 5 }')
Check ((IsRefusal $r) -and @($r.findings).Count -eq 5 -and (UnknownKey $r "__proto__") -and (UnknownKey $r "ToString")) "keys named after things a language keeps are unknown keys like any other"

Section "a text that cannot be used as a whole is refused"
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
Check (Unreadable (Doc '{ "role": "a\qb" }') "is not JSON: line 1") "an escape JSON does not have is not JSON"
Check (Unreadable ('{ "schemaVersion": 1,' + [char]0xA0 + '"settings": { "widthPx": 640 } }') "is not JSON: line 1") "A NO-BREAK SPACE between two parts is not JSON: only space, tab and the two line ends are blanks"
Check (Unreadable (Doc '{ "share": 1e400 }') "is not JSON") "A NUMBER TOO LARGE TO HOLD is not JSON to the parser: one finding, never an error"
Check (Unreadable (Doc ('{ "role": ' + ("[" * 200) + ("]" * 200) + ' }')) "is not JSON") "VALUES NESTED 200 DEEP are past the parser's limit: one finding, never an error"
Check (Unreadable (Doc '{ "": 1 }') "is not JSON the parser can read") "an empty key is refused by the parser: one finding, never an error"
Check (Unreadable (Doc '{ "PSObject": 1, "widthPx": 640 }') "is not JSON the parser can read") "a key named PSObject is refused by 5.1's parser, which keeps that name for itself: one finding, never an error"
Check (Unreadable (("1" * 200000) + "x") "is not JSON") "two hundred thousand digits and a letter are not JSON, and saying so does not take the suite's time"
Check (Unreadable ('{ "a": "' + ("\\" * 100000)) "is not JSON") "nor does a string of a hundred thousand backslashes that never ends"

Section "a key written twice"
$r = FromText (Doc '{ "widthPx": 640, "widthPx": 300, "theme": "dark" }')
Check ((Unreadable (Doc '{ "widthPx": 640, "widthPx": 300, "theme": "dark" }') @("it says one thing twice", "'widthPx'")) -and @($r.findings).Count -eq 1 -and $null -eq $r.values) "A KEY WRITTEN TWICE refuses the file with a finding naming it: NEITHER value is used, nor anything else in the file"
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
Check ($r.state -ceq "read" -and (V $r).widthPx -eq 640 -and @($r.findings).Count -eq 0) "A LEADING BYTE-ORDER MARK is skipped: editors write one, and 5.1's parser refuses it"
Check (Unreadable ($mark + $mark + (Doc '{ "widthPx": 640 }')) "is not JSON") "only one, and only at the start"
Check (Unreadable ((Doc '{ "widthPx": 640 }') + $mark) "is not JSON") "a mark anywhere else is not JSON"
$good = Doc '{ "widthPx": 640 }'
$atCap = $good + (" " * (262144 - $good.Length))
$r = FromText $atCap
Check ($atCap.Length -eq 262144 -and (V $r).widthPx -eq 640 -and @($r.findings).Count -eq 0) "a text of 262144 characters is read"
Check ((Unreadable ($atCap + " ") "it is longer than 262144 characters") -and @((FromText ($atCap + " ")).findings).Count -eq 1) "one character more is refused with one finding, whatever it holds"
$r = FromText ($mark + $atCap)
Check ((V $r).widthPx -eq 640 -and @($r.findings).Count -eq 0) "the mark is not counted in the length"

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
    Check ((V $r).widthPx -eq 640 -and @($r.findings).Count -eq 0) "THE PURE READING NEVER ASKS WHERE THE HOME IS: it answers with a home nobody could use"
} finally { $env:HORDE_HOME = $homeBefore }
$r = FromText (Doc '{ "widthPx": 640 }')
$r.values.widthPx = 1
Check ((V (FromText $null)).widthPx -eq 520 -and $decl.settings[0].default -eq 520) "an answer is the caller's own: changing it changes neither the declaration nor the next answer"
$hostile = FromText (Doc ('{ "caf' + [char]0xE9 + '": "x", "role": "' + [char]0x4E2D + '\u0001", "' + ("k" * 500) + '": [[[1]]] }'))
Check ((IsRefusal $hostile) -and @($hostile.findings).Count -eq 3 -and @($hostile.findings | Where-Object { $_ -cmatch '[^\x20-\x7E]' -or $_.Length -gt 200 }).Count -eq 0) "three hostile keys are three findings, each printable ASCII and short"
$longPart = '{ "schemaVersion": 1, "settings": {}, "' + ("k" * 500) + '": 1 }'
$r = FromText $longPart
Check ((Unreadable $longPart ("'" + ("k" * 200))) -and @($r.findings).Count -eq 1 -and $r.findings[0] -clike "*kkk..." -and $r.findings[0].Length -eq ($refusal.Length + 3 + 300 + 3)) "what the schema says of a file is cut at 300 characters; that the file is refused is said before it, where no cut reaches"
$accentFile = "C:\caf" + [char]0xE9 + " home\settings\probe.json"
$r = FromText (Doc '{ "colour": 1 }') $accentFile
Check ((IsRefusal $r "the settings file 'C:\caf\u00E9 home\settings\probe.json' of probe is refused: it has the key 'colour'") -and $r.path -ceq $accentFile) "A FINDING NAMES THE FILE IT WAS GIVEN, in printable ASCII; the answer's path is that file as given"
$r = FromText "not json" $accentFile
Check (IsRefusal $r "the settings file 'C:\caf\u00E9 home\settings\probe.json' of probe is refused: it is not JSON") "a file that cannot be used as a whole is named the same way"
$longFile = "C:\" + ("d" * 400) + "\probe.json"
$r = FromText (Doc '{ "colour": 1 }') $longFile
Check ((IsRefusal $r ("the settings file 'C:\" + ("d" * 297) + "...' of probe is refused: it has the key 'colour'")) -and $r.path -ceq $longFile) "a file's name longer than 300 characters is cut in the finding, never in the answer's path"
$twiceAccent = Doc ('{ "caf' + [char]0xE9 + '": 1, "caf' + [char]0xE9 + '": 2 }')
Check ((Unreadable $twiceAccent "'caf\u00E9'") -and @((FromText $twiceAccent).findings | Where-Object { $_ -cmatch '[^\x20-\x7E]' }).Count -eq 0) "what the duplicate scan says of a file is written in printable ASCII"
$listDecl = New-HordeModuleSettings -Module "probe" -Settings @(@{ name = "face"; kind = "text"; default = "plain"; values = @("plain", ("caf" + [char]0xE9)); what = "A face." })
$r = Read-HordeModuleSettingsText -Declaration $listDecl -Text (Doc '{ "face": "bold" }')
Check (@($r.findings).Count -eq 1 -and $r.findings[0] -ceq ($refusal + "its key 'face' must be one of: plain, caf\u00E9; it gives text of 4 characters")) "a rule that holds a character that is not ASCII is written in printable ASCII too"
$manyDecl = New-HordeModuleSettings -Module "probe" -Settings @(@{ name = "face"; kind = "text"; default = ("a" * 100); values = @("a", "b", "c", "d", "e") | ForEach-Object { $_ * 100 }; what = "A face." })
$r = Read-HordeModuleSettingsText -Declaration $manyDecl -Text (Doc '{ "face": "bold" }')
Check (@($r.findings).Count -eq 1 -and $r.findings[0] -clike ($refusal + "its key 'face' must be one of: " + ("a" * 100) + ", *...; it gives text of 4 characters") -and $r.findings[0].Length -lt 460) "a rule longer than 300 characters is cut, and the finding still says what was given"
$labelDecl = New-HordeModuleSettings -Module "probe" -Settings (LabelRow "F")
function LabelFrom { param([string]$Json) return (Read-HordeModuleSettingsText -Declaration $labelDecl -Text (Doc ('{ "fromLabel": ' + $Json + ' }'))) }
Check ((Read-HordeModuleSettingsText -Declaration $labelDecl -Text $null).values.fromLabel -ceq "F") "with no file a label is its default"
$r = LabelFrom '"B12"'
Check ($r.state -ceq "read" -and $null -ne $r.values -and $r.values.fromLabel -ceq "B12") "a label a file gives is read"
$labelRule = Get-HordeModuleSettingRule -Entry $labelDecl.settings[0]
foreach ($case in @(@('"b"', "text of 1 characters"), @('"A0"', "text of 2 characters"), @('"F\n"', "text holding a control character"), @('"ABC"', "text of 3 characters"), @('7', "the whole number 7"))) {
    $r = LabelFrom $case[0]
    $want = $refusal + "its key 'fromLabel' must be " + $labelRule + "; it gives " + $case[1]
    $good = ((IsRefusal $r) -and @($r.findings).Count -eq 1 -and $r.findings[0] -ceq $want)
    if (-not $good) { Write-Host ("    want:    " + $want) -ForegroundColor DarkYellow }
    Check $good ("a label of " + $case[0] + " refuses the file, named with its key, the value never quoted")
}
Check ($labelRule -clike "a hub label*") "a label's rule says it is a hub label"
function InCulture {
    # Run a block with the thread's culture set, and put the culture back.
    param([string]$Name, [scriptblock]$Block)
    $was = [System.Threading.Thread]::CurrentThread.CurrentCulture
    try { [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Name); return (& $Block) }
    finally { [System.Threading.Thread]::CurrentThread.CurrentCulture = $was }
}
Check ((InCulture "de-DE" { (0.5).ToString() }) -ceq "0,5") "CONTROL: under a German culture .NET writes one half with a comma"
Check ((InCulture "de-DE" { Get-HordeModuleSettingRule -Entry $decl.settings[1] }) -ceq "a number from 0.1 to 0.9") "A RULE IS WRITTEN THE SAME ON EVERY MACHINE: a fraction's range has a point under a culture that writes a comma"
Check ((InCulture "de-DE" { (FromText (Doc '{ "share": 5e-2, "widthPx": 520.5 }')).findings -join "|" }) -clike "*; it gives the number 0.05|*; it gives the number 520.5") "and so has the number a finding quotes, whether the parser read it as a Double's or a Decimal's"

# ---------------------------------------------------------------------------------------------------
# THE FILE. A home this suite makes under TEMP and removes; HORDE_HOME is put back as it was.

function Tree {
    # Everything under a folder - each path, its size and when it was last written - as one text, so
    # "a read changed nothing" is one comparison. EACH ENTRY IS REFRESHED, so its size and time are
    # asked of the file itself and not taken from the folder's listing, which NTFS may bring up to
    # date late. Without Refresh the comparison failed 2 of its first 3 runs on 2026-10-07, on a file
    # only ever opened for reading; with it, 5 of 5 passed. Which field differed was not captured, so
    # a mismatch now prints both listings.
    param([string]$Dir)
    if (-not (Test-Path -LiteralPath $Dir)) { return "<absent>" }
    return (@(Get-ChildItem -LiteralPath $Dir -Recurse -Force | Sort-Object FullName | ForEach-Object { $_.Refresh(); $_.FullName + "|" + $(if ($_.PSIsContainer) { "folder" } else { "" + $_.Length }) + "|" + $_.LastWriteTimeUtc.Ticks }) -join "`n")
}
$tempHome = Join-Path $env:TEMP ("horde-module-settings-" + [guid]::NewGuid().ToString("N"))
$otherHome = Join-Path $env:TEMP ("horde-module-settings-other-" + [guid]::NewGuid().ToString("N"))
$probeFile = Join-Path $tempHome "settings\probe.json"
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Put { param([byte[]]$Bytes, [string]$Path = $probeFile) [System.IO.File]::WriteAllBytes($Path, $Bytes) }
function FromFile { return (Get-HordeModuleSettings -Declaration $decl -HordeHome $tempHome) }
$fileRefusal = "the settings file '" + $probeFile + "' of probe is refused: "
function FileUnreadable {
    # The file as it stands is refused (no values) with exactly one finding: the file by its whole
    # path, that it is refused, and "it " + -Is, word for word unless -OrMore (then it starts so).
    param([string]$Is, [switch]$OrMore)
    $r = $null
    try { $r = FromFile } catch { Write-Host ("    got: it threw: " + $_.Exception.Message) -ForegroundColor DarkYellow; return $false }
    $good = ((IsRefusal $r $fileRefusal) -and @($r.findings).Count -eq 1 -and $r.path -ceq $probeFile)
    if ($good) { $good = $(if ($OrMore) { $r.findings[0].StartsWith(($fileRefusal + "it " + $Is), [System.StringComparison]::Ordinal) } else { $r.findings[0] -ceq ($fileRefusal + "it " + $Is) }) }
    if (-not $good) { foreach ($f in @($r.findings)) { Write-Host ("    finding: " + $f) -ForegroundColor DarkYellow } }
    return $good
}
$homeBefore = $env:HORDE_HOME
$widthBefore = $env:HORDE_WIDTHPX
$held = $null
try {
    Section "the file: a home, a folder or a file that is not there"
    $r = FromFile
    Check ((AllDefaults $r) -and $r.state -ceq "defaults" -and @($r.findings).Count -eq 0 -and $r.findings -is [array]) "with no home at all the state is defaults: every setting is its default, and there is no finding"
    Check ($r.path -ceq $probeFile) "the answer says which file was looked for: <home>\settings\<module>.json"
    Check (-not (Test-Path -LiteralPath $tempHome)) "A READ DOES NOT CREATE THE HOME"
    $null = New-Item -ItemType Directory -Path $tempHome
    $r = FromFile
    Check ((AllDefaults $r) -and $r.state -ceq "defaults" -and @($r.findings).Count -eq 0) "with a home and no settings folder the state is defaults"
    Check ((Tree $tempHome) -ceq "") "A READ DOES NOT CREATE THE SETTINGS FOLDER"
    $null = New-Item -ItemType Directory -Path (Join-Path $tempHome "settings")
    $r = FromFile
    Check ((AllDefaults $r) -and $r.state -ceq "defaults" -and @($r.findings).Count -eq 0 -and $r.path -ceq $probeFile) "with a settings folder and no file the state is defaults, and the path still says where a file would be"
    Check (@(Get-ChildItem -LiteralPath (Join-Path $tempHome "settings") -Force).Count -eq 0) "A READ DOES NOT CREATE THE FILE"

    Section "the file: read"
    $goodText = Doc '{ "widthPx": 640, "role": "scout" }'
    Put ($utf8.GetBytes($goodText))
    $before = Tree $tempHome
    $r = FromFile
    Check ($r.state -ceq "read" -and (V $r).widthPx -eq 640 -and (V $r).role -ceq "scout" -and (V $r).share -eq 0.25 -and @($r.findings).Count -eq 0 -and $r.findings -is [array]) "a file under the home is read, and overrides what it names"
    Check (@($r.PSObject.Properties | ForEach-Object { $_.Name }) -join "," -ceq "state,values,findings,path") "the answer is state, values, findings and the path read"
    $alone = $false
    try { $held = [System.IO.File]::Open($probeFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None); $alone = $true } catch { $alone = $false }
    if ($null -ne $held) { $held.Dispose(); $held = $null }
    Check $alone "the file is let go when the read returns: another program can then open it for itself"
    $otherDecl = New-HordeModuleSettings -Module "other-module" -Settings (Table)
    Check ((AllDefaults (Get-HordeModuleSettings -Declaration $otherDecl -HordeHome $tempHome))) "ONE FILE PER MODULE: another module is not touched by this one's file"
    Put ($utf8.GetBytes((Doc '{ "widthPx": 300 }'))) (Join-Path $tempHome "settings\other-module.json")
    Check ((V (Get-HordeModuleSettings -Declaration $otherDecl -HordeHome $tempHome)).widthPx -eq 300 -and (V (FromFile)).widthPx -eq 640) "each module reads its own file"
    Remove-Item -LiteralPath (Join-Path $tempHome "settings\other-module.json")

    Section "the file: where the home comes from"
    $env:HORDE_HOME = $tempHome
    $r = Get-HordeModuleSettings -Declaration $decl
    Check ((V $r).widthPx -eq 640 -and $r.path -ceq $probeFile) "without -HordeHome the home is Horde's own (core/Home.ps1): HORDE_HOME says WHERE"
    $env:HORDE_HOME = $otherHome
    Check ((V (FromFile)).widthPx -eq 640) "-HordeHome is used when given, whatever HORDE_HOME says"
    Check ((AllDefaults (Get-HordeModuleSettings -Declaration $decl)) -and -not (Test-Path -LiteralPath $otherHome)) "and a HORDE_HOME that is not there is every default, and is not created"
    $env:HORDE_HOME = "relative\home"
    Check (Throws { Get-HordeModuleSettings -Declaration $decl } "absolute") "a relative HORDE_HOME is refused by core/Home.ps1, as everywhere: that is no file's fault"
    Check (Throws { Get-HordeModuleSettings -Declaration $decl -HordeHome "relative\home" } "-HordeHome must be an absolute path") "a relative -HordeHome is a programming error"
    Check (Throws { Get-HordeModuleSettings -Declaration $decl -HordeHome "C:relative" } "-HordeHome must be an absolute path") "and so is one relative to a drive's current folder"
    Check (Throws { Get-HordeModuleSettings -Declaration "probe" -HordeHome $tempHome } "New-HordeModuleSettings") "a -Declaration that New-HordeModuleSettings did not make is a programming error here too"
    $env:HORDE_HOME = $tempHome
    $env:HORDE_WIDTHPX = "999"
    Check ((V (Get-HordeModuleSettings -Declaration $decl)).widthPx -eq 640) "THE ENVIRONMENT NEVER SETS A SETTING: a variable named after one changes nothing"
    $source = [System.IO.File]::ReadAllText((Join-Path $root "core\ModuleSettings.ps1"))
    Check ($source.IndexOf('$env:', [System.StringComparison]::OrdinalIgnoreCase) -lt 0 -and $source.IndexOf('GetEnvironmentVariable', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) "and core/ModuleSettings.ps1 reads no environment variable at all: the home comes from core/Home.ps1"
    $homeSource = [System.IO.File]::ReadAllText((Join-Path $root "core\Home.ps1"))
    Check ($homeSource.IndexOf('$env:', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) "CONTROL: that search finds the variable core/Home.ps1 reads"

    Section "the file: its bytes"
    Put ([byte[]](0xEF, 0xBB, 0xBF) + $utf8.GetBytes($goodText))
    $r = FromFile
    Check ((V $r).widthPx -eq 640 -and @($r.findings).Count -eq 0) "A FILE SAVED WITH A UTF-8 BYTE-ORDER MARK is read"
    Put ($utf8.GetBytes((Doc ('{ "role": "' + $accent + '" }'))))
    Check ((V (FromFile)).role -ceq $accent) "TEXT THAT IS NOT ASCII is read as UTF-8, character for character"
    Put ([System.Text.Encoding]::Unicode.GetPreamble() + [System.Text.Encoding]::Unicode.GetBytes($goodText))
    Check (FileUnreadable "is not UTF-8 text; save it as UTF-8") "a file saved as UTF-16, as 5.1's redirection writes it, is refused with one finding saying so and how to save it"
    Put ([System.Text.Encoding]::GetEncoding(1252).GetBytes((Doc ('{ "role": "caf' + [char]0xE9 + '" }'))))
    Check (FileUnreadable "is not UTF-8 text; save it as UTF-8") "a file saved in a code page is refused: its letters are never guessed"
    Put ([byte[]](0x7B, 0xFF, 0x7D))
    Check (FileUnreadable "is not UTF-8 text; save it as UTF-8") "bytes that are no text at all are refused"
    Put ([byte[]]@())
    Check (FileUnreadable "does not fit schema/module-settings.v1: " -OrMore) "an empty file is refused with one finding"
    $padded = $utf8.GetBytes($goodText + (" " * (262144 - $goodText.Length)))
    Put $padded
    $r = FromFile
    Check ($padded.Length -eq 262144 -and (V $r).widthPx -eq 640 -and @($r.findings).Count -eq 0) "a file of 262144 bytes is read"
    Put ($padded + [byte[]](0x20))
    Check (FileUnreadable "is larger than 262144 bytes") "a file one byte larger is refused with one finding"
    Put ($utf8.GetBytes((Doc '{ "widthPx": 640, "widthPx": 300, "colour": 1 }')))
    $r = FromFile
    $same = FromText (Doc '{ "widthPx": 640, "widthPx": 300, "colour": 1 }') $probeFile
    Check ((IsRefusal $r $fileRefusal) -and @($r.findings).Count -eq 1 -and ($r.findings -join "|") -ceq ($same.findings -join "|")) "what is wrong inside a file is said in the words the pure reading uses when it is given the file's path"
    Put ($utf8.GetBytes((Doc '{ "widthPx": 9999, "colour": 1, "role": "scout" }')))
    $r = FromFile
    Check ((IsRefusal $r $fileRefusal) -and @($r.findings).Count -eq 2 -and $r.path -ceq $probeFile) "a wrong value and an unknown key in a file are two findings and one refusal: the good value beside them is not handed back, and no default is"
    Check ($r.findings[0] -ceq ($fileRefusal + "its key 'widthPx' must be a whole number from 200 to 4000, written in digits only; it gives the whole number 9999") -and $r.findings[1] -ceq ($fileRefusal + "it has the key 'colour', which is no setting of probe")) "EACH FINDING NAMES THE FILE BY ITS WHOLE PATH, THE KEY AND WHY, in the order the file wrote them"

    Section "the file: when it cannot be opened"
    Put ($utf8.GetBytes($goodText))
    $held = [System.IO.File]::Open($probeFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    Check (FileUnreadable "cannot be read (IOException)") "a file another program holds for itself is refused with one finding, never an error and never the defaults"
    $held.Dispose(); $held = $null
    $held = [System.IO.File]::Open($probeFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::ReadWrite)
    Check ((V (FromFile)).widthPx -eq 640) "a file an editor has open for writing, and shares, is read"
    $held.Dispose(); $held = $null
    Remove-Item -LiteralPath $probeFile
    $null = New-Item -ItemType Directory -Path $probeFile
    Check (FileUnreadable "cannot be read (UnauthorizedAccessException)") "a FOLDER where the file should be is refused with one finding, never an error and never the defaults"
    Remove-Item -LiteralPath $probeFile

    Section "the file: a read writes nothing"
    Put ($utf8.GetBytes((Doc '{ "widthPx": 9999, "colour": 1, "role": "scout" }')))
    $r = FromFile
    Check ($r.state -ceq "refused" -and $null -eq $r.values -and @($r.findings).Count -eq 2) "a refused file is refused every time it is asked: nothing is remembered and nothing falls back"
    $before = Tree $tempHome
    $null = FromFile; $null = FromFile; $null = Get-HordeModuleSettings -Declaration $otherDecl -HordeHome $tempHome
    if ((Tree $tempHome) -cne $before) { Write-Host ("    got: before " + ($before -replace "`n", " ; ")) -ForegroundColor DarkYellow; Write-Host ("    got: after  " + ((Tree $tempHome) -replace "`n", " ; ")) -ForegroundColor DarkYellow }
    Check ($before -clike "*probe.json|*" -and (Tree $tempHome) -ceq $before) "after three reads the home holds the same files, of the same size, last written at the same time"
    Check (@(Get-ChildItem -LiteralPath (Join-Path $tempHome "settings") -Force).Count -eq 1) "and nothing stands beside the file: no copy, no lock, no file for the module that has none"
} finally {
    if ($null -ne $held) { $held.Dispose() }
    $env:HORDE_HOME = $homeBefore
    $env:HORDE_WIDTHPX = $widthBefore
    if (Test-Path -LiteralPath $tempHome) { Remove-Item -LiteralPath $tempHome -Recurse -Force }
}
Check (-not (Test-Path -LiteralPath $tempHome) -and -not (Test-Path -LiteralPath $otherHome)) "the suite leaves no home behind"

Complete-HordeSuite -Success "a module's settings are its declared defaults or one file under the home that passed every check; a file that fails one is refused whole, with every problem named and no default in its place"
