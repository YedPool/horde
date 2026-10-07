# IS EVERY NUMBER THE DECISIONS MODULE CAN BE TUNED BY A NAMED SETTING, IN ONE TABLE, AND NOWHERE ELSE?
#
# decisions/Settings.ps1 and its table, decisions/settings.json. This suite attacks three things:
#   - THE READER REFUSES A WRONG TABLE WHOLE: a default outside its own range, a range upside down, a
#     value that is not of its kind, a setting that does not say what it means. A wait of -1 would
#     otherwise surface as a hang, far from the table.
#   - READING IS PURE GIVEN THE TEXT, AND AN OVERRIDE THAT FAILS ITS CHECKS IS REFUSED: a value of the
#     wrong kind or outside its range, a key the table does not have, text that is no override - each
#     is named (file, key, why), nothing is handed out, and no default is put in its place. With no
#     override file the defaults table is used.
#   - A NAME THE TABLE DOES NOT HAVE THROWS: a misspelt name must never read as 0.
#   - THE TABLE AND THE CODE AGREE, BOTH WAYS: every setting the code asks for is in the table, every
#     setting in the table is asked for by the code, and neither the store nor the operations assigns
#     a number to a variable of its own - which is how a tunable gets buried in code again.
#
# Every table but the shipped one is a file this suite writes under %TEMP% and removes (CONTRIBUTING 9).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "decisions\Settings.ps1")

$script:work = Join-Path $env:TEMP ("horde-decisions-settings-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
$script:n = 0
# The override file is looked for under the home: this suite's own, put back at the end.
$keepHome = $env:HORDE_HOME
$env:HORDE_HOME = (Join-Path $script:work "home")
function Read-Table {
    # The table from its text, by the shipped pure reader. Returns the table, or "THREW: <message>".
    param([string]$Json)
    try { return (ConvertFrom-HordeDecisionSettingsText -Text $Json -From "the test's table") } catch { return ("THREW: " + $_.Exception.Message) }
}
function Get-One { param([string]$Body) return ('{"schemaVersion":1,"settings":{' + $Body + '}}') }
function Get-Whole { param([string]$Numbers = '"default":5,"least":1,"most":9') return (Get-One ('"decisions.a.b":{"kind":"whole-number",' + $Numbers + ',"means":"a number"}')) }
function Resolve-With {
    # Lay an override's text over a table of this suite's own. Returns { values; findings }, or a
    # stand-in whose findings say it threw.
    param($Table, [string]$Override)
    try { return (Resolve-HordeDecisionSettings -Table $Table -OverrideText $Override -From "the test's override") } catch { return [pscustomobject]@{ state = "THREW"; values = @{}; findings = @("THREW: " + $_.Exception.Message) } }
}

try {

Write-Host ""
Write-Host "--- the shipped table ---" -ForegroundColor Cyan
$table = @(Get-HordeDecisionSettingTable)
Check ($table.Count -ge 6) ("CONTROL: the shipped table is read, and names its settings (" + $table.Count + ")")
Check (@($table | Where-Object { (Get-HordeDecisionSettingKinds) -cnotcontains $_.kind -or "$($_.means)".Trim() -eq "" -or (Get-HordeDecisionSettingValueProblem -Entry $_ -Value $_.default) -ne "" }).Count -eq 0) "every setting has a kind, says what it means, and has a default that fits its own kind and range"
Check (((Get-HordeDecisionSettingKinds) -join ",") -ceq "text,whole-number,fraction,true-false,folder") "the kinds a setting can be are text, whole-number, fraction, true-false and folder"
Check ((Get-HordeDecisionSetting -Name "decisions.store.maxGap") -eq 100 -and (Get-HordeDecisionSetting -Name "decisions.store.maxGap") -is [long]) "a whole-number setting is handed out as a whole 64-bit number"
Check (Throws { Get-HordeDecisionSetting -Name "decisions.store.maxgap" } "is not a setting") "a name in another case is not a setting: it throws, and never reads as 0"
Check (Throws { Get-HordeDecisionSetting -Name "decisions.store.noSuchThing" } "is not a setting") "a name the table does not have throws"
Check ((@($table | ForEach-Object { $_.name }) -join ",") -ceq (@($table | ForEach-Object { $_.name } | Sort-Object) -join ",")) "the table is handed out in name order, so a page that shows it is the same every time"

Write-Host ""
Write-Host "--- reading is pure given the text, and a wrong table is refused whole ---" -ForegroundColor Cyan
$good = Read-Table (Get-Whole)
Check ($good -isnot [string] -and $good.ContainsKey("decisions.a.b") -and $good["decisions.a.b"].kind -ceq "whole-number" -and $good["decisions.a.b"].default -eq 5 -and $good["decisions.a.b"].least -eq 1 -and $good["decisions.a.b"].most -eq 9 -and $good["decisions.a.b"].means -ceq "a number") "CONTROL: a right table of one setting is read from its text, with its kind, default, range and meaning"
Check ((Read-Table (Get-Whole '"default":5,"least":5,"most":5')) -isnot [string]) "CONTROL: a default AT both ends of its range is inside it"
Check ("$(Read-Table (Get-Whole '"default":0,"least":1,"most":9'))" -like "THREW:*'decisions.a.b' has a default that is 0, outside the range 1 to 9*") "a default below its range is refused, by the setting's name"
Check ("$(Read-Table (Get-Whole '"default":10,"least":1,"most":9'))" -like "THREW:*has a default that is 10, outside the range 1 to 9*") "a default above its range is refused"
Check ("$(Read-Table (Get-Whole '"default":5,"least":9,"most":1'))" -like "THREW:*upside down*") "a range that is upside down is refused"
Check ("$(Read-Table (Get-Whole '"default":1.5,"least":1,"most":9'))" -like "THREW:*has a default that is not a whole number*") "a whole-number default that is not whole is refused"
Check ("$(Read-Table (Get-Whole '"default":"5","least":1,"most":9'))" -like "THREW:*has a default that is not a whole number*") "a default written as text is refused, not converted"
Check ("$(Read-Table (Get-Whole '"default":5,"least":1,"most":1e30'))" -like "THREW:*no number for 'most'*") "a whole number's limit too large to be whole is refused"
Check ("$(Read-Table (Get-Whole '"default":5,"most":9'))" -like "THREW:*no number for 'least'*") "a ranged setting with no lower limit is refused"
Check ("$(Read-Table (Get-Whole '"least":1,"most":9'))" -like "THREW:*'decisions.a.b' has no default*") "a setting with no default is refused"
Check ("$(Read-Table (Get-One '"decisions.a.b":{"kind":"whole-number","default":5,"least":1,"most":9}'))" -like "THREW:*does not say what it means*") "a setting that does not say what it means is refused"
Check ("$(Read-Table (Get-One '"decisions.a.b":{"kind":"whole-number","default":5,"least":1,"most":9,"means":"  "}'))" -like "THREW:*does not say what it means*") "and so is one whose meaning is blank"
Check ("$(Read-Table (Get-One '"decisions.a.b":{"default":5,"least":1,"most":9,"means":"a number"}'))" -like "THREW:*has no kind this version knows; the kinds are: text, whole-number*") "a setting with no kind is refused, with the kinds there are"
Check ("$(Read-Table (Get-One '"decisions.a.b":{"kind":"colour","default":"red","means":"a colour"}'))" -like "THREW:*has no kind this version knows*") "and so is one of a kind nobody knows"
Check ("$(Read-Table (Get-One '"decisions.a.b":5'))" -like "THREW:*is not an entry with a kind*") "a setting written as a bare value is refused"
Check ("$(Read-Table (Get-One '"store.maxGap":{"kind":"whole-number","default":5,"least":1,"most":9,"means":"a number"}'))" -like "THREW:*is not named decisions.<part>.<name>*") "a setting not named for the module is refused"
Check ("$(Read-Table (Get-One '"decisions.a.b":{"kind":"whole-number","default":5,"least":1,"most":9,"means":"a number"},"decisions.c.d":{"kind":"whole-number","default":50,"least":1,"most":9,"means":"a number"}'))" -like "THREW:*decisions.c.d*outside the range*") "one wrong setting refuses the whole table, by its name"
Check ("$(Read-Table '{"schemaVersion":2,"settings":{"decisions.a.b":{"kind":"whole-number","default":5,"least":1,"most":9,"means":"a number"}}}')" -like "THREW:*schemaVersion 1*") "a table of another version is refused"
Check ("$(Read-Table '{"schemaVersion":1,"settings":[]}')" -like "THREW:*schemaVersion 1 and a settings object*") "a table whose settings are not an object is refused"
Check ("$(Read-Table '{"schemaVersion":1,"settings":{}}')" -like "THREW:*names no setting*") "a table that names no setting is refused"
Check ("$(Read-Table 'not json {')" -like "THREW: the test's table is not JSON" -and "$(Read-Table '')" -like "THREW:*") "text that is not JSON is refused, and named by what the caller called it - not quoted"

Write-Host ""
Write-Host "--- every kind: its default is held to it ---" -ForegroundColor Cyan
$kinds = Read-Table (Get-One ('"decisions.k.text":{"kind":"text","default":"hello","least":1,"most":10,"means":"a text"},' +
    '"decisions.k.whole":{"kind":"whole-number","default":5,"least":1,"most":9,"means":"a whole number"},' +
    '"decisions.k.fraction":{"kind":"fraction","default":0.25,"least":0,"most":1,"means":"a fraction"},' +
    '"decisions.k.flag":{"kind":"true-false","default":true,"means":"a flag"},' +
    '"decisions.k.folder":{"kind":"folder","default":"C:\\somewhere\\here","means":"a folder"}'))
Check ($kinds -isnot [string] -and $kinds.Count -eq 5 -and $kinds["decisions.k.text"].default -ceq "hello" -and $kinds["decisions.k.fraction"].default -eq 0.25 -and $kinds["decisions.k.flag"].default -eq $true -and $kinds["decisions.k.folder"].default -ceq "C:\somewhere\here" -and $null -eq $kinds["decisions.k.flag"].least) ("CONTROL: a table with one setting of every kind is read (" + $(if ($kinds -is [string]) { $kinds } else { $kinds.Count }) + ")")
Check ("$(Read-Table (Get-One '"decisions.k.text":{"kind":"text","default":5,"least":1,"most":10,"means":"a text"}'))" -like "THREW:*has a default that is not text*") "a text default that is a number is refused"
Check ("$(Read-Table (Get-One '"decisions.k.text":{"kind":"text","default":"far too long for it","least":1,"most":10,"means":"a text"}'))" -like "THREW:*has a default that is 19 characters long, outside the range 1 to 10*") "a text default longer than its range is refused, by its length and not by its words"
Check ("$(Read-Table (Get-One '"decisions.k.fraction":{"kind":"fraction","default":1.5,"least":0,"most":1,"means":"a fraction"}'))" -like "THREW:*has a default that is 1.5, outside the range 0 to 1*") "a fraction default outside its range is refused"
Check ("$(Read-Table (Get-One '"decisions.k.fraction":{"kind":"fraction","default":true,"least":0,"most":1,"means":"a fraction"}'))" -like "THREW:*has a default that is not a number*") "a fraction default that is a flag is refused"
Check ("$(Read-Table (Get-One '"decisions.k.flag":{"kind":"true-false","default":"true","means":"a flag"}'))" -like "THREW:*has a default that is not true or false*") "a true-false default written as text is refused"
Check ("$(Read-Table (Get-One '"decisions.k.folder":{"kind":"folder","default":"relative\\folder","means":"a folder"}'))" -like "THREW:*has a default that is not an absolute folder*") "a folder default that is not absolute is refused"

Write-Host ""
Write-Host "--- an override that fails its checks is REFUSED, with every problem named; it never falls back to a default ---" -ForegroundColor Cyan
# THE RULE: an override file that fails its checks refuses with a reason and never silently falls back
# to the defaults. A person who wrote 5 where only 10 to 100 is allowed must be told, not handed 40
# without a word. So resolving answers { state; values; findings }: ok with every value, or refused
# with NO values and one finding for every problem - the file, the key, and why.
function Get-Findings { param($Resolved) return (@($Resolved.findings) -join " || ") }
$none = Resolve-With $kinds ""
Check ($none.state -ceq "ok" -and @($none.findings).Count -eq 0 -and $none.values["decisions.k.whole"] -eq 5 -and $none.values["decisions.k.text"] -ceq "hello" -and $none.values.Count -eq 5) "with no override the defaults table is used: every setting has its default, and nothing is refused"
$right = Resolve-With $kinds '{"schemaVersion":1,"values":{"decisions.k.whole":9,"decisions.k.text":"hi","decisions.k.fraction":1,"decisions.k.flag":false,"decisions.k.folder":"D:\\other"}}'
Check ($right.state -ceq "ok" -and @($right.findings).Count -eq 0 -and $right.values["decisions.k.whole"] -eq 9 -and $right.values["decisions.k.text"] -ceq "hi" -and $right.values["decisions.k.fraction"] -eq 1 -and $right.values["decisions.k.flag"] -eq $false -and $right.values["decisions.k.folder"] -ceq "D:\other") "a value of the right kind and inside its range is used, for every kind; a whole number is a fraction too"
$part = Resolve-With $kinds '{"schemaVersion":1,"values":{"decisions.k.whole":7}}'
Check ($part.state -ceq "ok" -and $part.values["decisions.k.whole"] -eq 7 -and $part.values["decisions.k.text"] -ceq "hello") "an override names only what it changes: every other setting keeps its default"
$wrong = Resolve-With $kinds '{"schemaVersion":1,"values":{"decisions.k.whole":10,"decisions.k.text":"twelve chars","decisions.k.fraction":"half","decisions.k.flag":1,"decisions.k.folder":"relative","decisions.k.nothing":3}}'
Check ($wrong.state -ceq "refused" -and $null -eq $wrong.values) ("an override with wrong entries is REFUSED, and hands back no values at all: not the defaults, not the good part of it (" + $wrong.state + ")")
Check (@($wrong.findings).Count -eq 6) ("and EVERY problem is named, not only the first: six findings for six wrong entries (" + @($wrong.findings).Count + ")")
Check (@($wrong.findings | Where-Object { $_ -ceq "the test's override: 'decisions.k.whole' is 10, outside the range 1 to 9" }).Count -eq 1) "a number out of range is named by the file, the key and why, with the range"
Check (@($wrong.findings | Where-Object { $_ -ceq "the test's override: 'decisions.k.fraction' is not a number" }).Count -eq 1 -and @($wrong.findings | Where-Object { $_ -ceq "the test's override: 'decisions.k.flag' is not true or false" }).Count -eq 1 -and @($wrong.findings | Where-Object { $_ -ceq "the test's override: 'decisions.k.folder' is not an absolute folder" }).Count -eq 1) "a wrong kind is named the same way: 1 is not true, and text is not a number"
Check (@($wrong.findings | Where-Object { $_ -ceq "the test's override: 'decisions.k.text' is 12 characters long, outside the range 1 to 10" }).Count -eq 1 -and @($wrong.findings | Where-Object { $_ -like "*twelve chars*" -or $_ -like "*half*" -or $_ -like "*relative*" }).Count -eq 0) "a text is named by its length, and no finding repeats a text a person typed"
Check (@($wrong.findings | Where-Object { $_ -ceq "the test's override: 'decisions.k.nothing' is not a setting of the decisions module" }).Count -eq 1) "a key the table does not have is a problem too: it is not ignored"
Check (@($wrong.findings | Where-Object { $_ -like "*default*" }).Count -eq 0) "no finding says a default was used, because none was"
$oneWrong = Resolve-With $kinds '{"schemaVersion":1,"values":{"decisions.k.whole":7,"decisions.k.fraction":2}}'
Check ($oneWrong.state -ceq "refused" -and $null -eq $oneWrong.values -and @($oneWrong.findings).Count -eq 1) "ONE wrong value refuses the whole override: the right value beside it is not used either"
$edge = Resolve-With $kinds '{"schemaVersion":1,"values":{"decisions.k.whole":1,"decisions.k.fraction":0}}'
Check ($edge.state -ceq "ok" -and $edge.values["decisions.k.whole"] -eq 1 -and $edge.values["decisions.k.fraction"] -eq 0) "CONTROL: a value AT the end of its range is inside it"
$text = Resolve-With $kinds '{"schemaVersion":1,"values":{"decisions.k.whole":"7"}}'
Check ($text.state -ceq "refused" -and (Get-Findings $text) -ceq "the test's override: 'decisions.k.whole' is not a whole number") "a number written as text is the wrong kind: it is never converted, and it refuses"
foreach ($bad in @('not json {', '[1,2]', '{"schemaVersion":2,"values":{"decisions.k.whole":7}}', '{"schemaVersion":1,"values":[]}', '{"schemaVersion":1}')) {
    $got = Resolve-With $kinds $bad
    Check ($got.state -ceq "refused" -and $null -eq $got.values -and @($got.findings).Count -eq 1 -and "$(@($got.findings)[0])" -like "the test's override: it is not an object with schemaVersion 1 and a values object*") ("text that is not an override (" + $bad.Substring(0, [Math]::Min(18, $bad.Length)) + "...) is refused, by the file's name, and not quoted")
}
$odd = Resolve-With $kinds ('{"schemaVersion":1,"values":{"gh' + 'p_' + ("Ab3d" * 9) + '":1}}')
Check ($odd.state -ceq "refused" -and @($odd.findings).Count -eq 1 -and "$(@($odd.findings)[0])" -like "*a key that is not repeated here*" -and "$(@($odd.findings)[0])" -notlike "*Ab3d*") "a key that is not shaped like a setting's name is refused without being repeated"
$twice = Resolve-With $kinds '{"schemaVersion":1,"values":{"decisions.k.whole":7}}'
Check ($twice.values["decisions.k.whole"] -eq 7 -and $kinds["decisions.k.whole"].default -eq 5 -and (Resolve-With $kinds "").values["decisions.k.whole"] -eq 5) "resolving changes nothing it was given: the table's default is still its default"

Write-Host ""
Write-Host "--- the override file under the home: used when it is right, refused when it is not, absent is the defaults ---" -ForegroundColor Cyan
$overrideHome = Join-Path $script:work "override-home"
$env:HORDE_HOME = $overrideHome
$overridePath = "THREW"
try { $overridePath = Get-HordeDecisionSettingsOverridePath } catch { $overridePath = "THREW: " + $_.Exception.Message }
Check ($overridePath -ceq (Join-Path $overrideHome "settings\decisions.json")) ("the override is <home>\settings\decisions.json (" + $overridePath + ")")
function Get-Setting { param([string]$Name) try { return (Get-HordeDecisionSetting -Name $Name) } catch { return ("THREW: " + $_.Exception.Message) } }
Check ((Get-Setting "decisions.store.maxGap") -eq 100 -and -not (Test-Path -LiteralPath $overrideHome)) "with no override file the default is handed out, and asking made no folder"
New-Item -ItemType Directory -Path (Join-Path $overrideHome "settings") | Out-Null
[System.IO.File]::WriteAllText($overridePath, '{"schemaVersion":1,"values":{"decisions.store.maxGap":7}}', $utf8)
Check ((Get-Setting "decisions.store.maxGap") -eq 7 -and (Get-Setting "decisions.store.maxGap") -is [long] -and (Get-Setting "decisions.store.heldReadTries") -eq 40) "a right override file is used for what it names, and the rest keep their defaults"
[System.IO.File]::WriteAllText($overridePath, '{"schemaVersion":1,"values":{"decisions.store.maxGap":-1,"decisions.store.noSuchThing":3}}', $utf8)
$refusal = Get-Setting "decisions.store.maxGap"
Check ("$refusal" -like "THREW:*settings\decisions.json*'decisions.store.maxGap' is -1, outside the range 0 to 1000000*'decisions.store.noSuchThing' is not a setting*") ("a wrong override file REFUSES the setting, naming the file and every problem in it (" + $refusal + ")")
Check ("$(Get-Setting 'decisions.store.heldReadTries')" -like "THREW:*settings\decisions.json*") "and it refuses EVERY setting, not only the wrong one: nothing is handed out from a file that failed its checks, and no default stands in"
Check ((Get-HordeDecisionSettingsProblem) -like "*settings\decisions.json*'decisions.store.maxGap' is -1*" ) "the same reason is there to be asked for without a throw"
[System.IO.File]::WriteAllText($overridePath, 'not json {', $utf8)
Check ("$(Get-Setting 'decisions.store.maxGap')" -like "THREW:*settings\decisions.json*it is not an object with schemaVersion 1*") "an override file that is not JSON refuses too"
Remove-Item -LiteralPath $overridePath
Check ((Get-Setting "decisions.store.maxGap") -eq 100 -and (Get-HordeDecisionSettingsProblem) -ceq "") "CONTROL: with the file gone the defaults are back, and there is no problem to report"

Write-Host ""
Write-Host "--- the table and the code agree, both ways ---" -ForegroundColor Cyan
# Read from the syntax trees of the module's files: every literal name handed to Get-HordeDecisionSetting.
$asked = New-Object System.Collections.ArrayList
$buried = New-Object System.Collections.ArrayList
$moduleFiles = @(Get-ChildItem -LiteralPath (Join-Path $root "decisions") -Filter "*.ps1" -File)
foreach ($file in $moduleFiles) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    foreach ($call in @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and "$($node.GetCommandName())" -ceq "Get-HordeDecisionSetting" }, $true))) {
        $literal = @($call.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.StringConstantExpressionAst] -and "$($_.Value)" -clike "decisions.*" })
        if ($literal.Count -eq 1) { [void]$asked.Add("$($literal[0].Value)") } else { [void]$asked.Add($file.Name + ": a setting asked for by a name that is not one literal") }
    }
    # A NUMBER ASSIGNED TO A VARIABLE OF THE FILE'S OWN is a tunable written in code. Only the store and
    # the operations are held to this: the rules' numbers are rules - the longest text, the largest
    # question number - and changing one changes what may be written, which is not tuning.
    if (@("Store.ps1", "Operations.ps1") -ccontains $file.Name) {
        foreach ($assign in @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true))) {
            $left = "$($assign.Left)"
            $right = $assign.Right
            if ($right -is [System.Management.Automation.Language.CommandExpressionAst]) { $right = $right.Expression }
            if ($left -clike '$script:*' -and $right -is [System.Management.Automation.Language.ConstantExpressionAst] -and $right.Value -isnot [string] -and $right.Value -isnot [bool]) { [void]$buried.Add($file.Name + ": " + "$assign") }
        }
    }
}
$askedNames = @($asked | Sort-Object -Unique)
$tableNames = @($table | ForEach-Object { $_.name })
Check ($moduleFiles.Count -ge 5 -and $askedNames.Count -ge 5) ("CONTROL: the search reads the module's files and finds the settings they ask for (" + $moduleFiles.Count + " files, " + $askedNames.Count + " names)")
Check (@($askedNames | Where-Object { $tableNames -cnotcontains $_ }).Count -eq 0) ("every setting the code asks for is in the table (" + (@($askedNames | Where-Object { $tableNames -cnotcontains $_ }) -join ", ") + ")")
Check (@($tableNames | Where-Object { $askedNames -cnotcontains $_ }).Count -eq 0) ("every setting in the table is asked for by the code: none is a number nothing reads (" + (@($tableNames | Where-Object { $askedNames -cnotcontains $_ }) -join ", ") + ")")
Check ($buried.Count -eq 0) ("neither the store nor the operations assigns a number to a variable of its own (" + ($buried -join " | ") + ")")
# CONTROL: the same search does find a number assigned in code, in a file of this suite's own.
$planted = Join-Path $script:work "planted.ps1"
[System.IO.File]::WriteAllText($planted, '$script:HordePlantedWaitMs = 50' + "`r`n" + '$script:HordePlantedName = "text"' + "`r`n" + '$script:HordePlantedList = @(1, 2)', $utf8)
$tokens = $null; $errors = $null
$plantedAst = [System.Management.Automation.Language.Parser]::ParseFile($planted, [ref]$tokens, [ref]$errors)
$plantedHits = @($plantedAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true) | Where-Object {
    $r = $_.Right; if ($r -is [System.Management.Automation.Language.CommandExpressionAst]) { $r = $r.Expression }
    "$($_.Left)" -clike '$script:*' -and $r -is [System.Management.Automation.Language.ConstantExpressionAst] -and $r.Value -isnot [string] -and $r.Value -isnot [bool] })
Check ($plantedHits.Count -eq 1 -and "$($plantedHits[0])" -clike '*HordePlantedWaitMs = 50') ("CONTROL: the search finds a number assigned in code, and only the number (" + $plantedHits.Count + ")")

} finally {
    $env:HORDE_HOME = $keepHome
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-decisions-settings-test-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) { Remove-Item -LiteralPath $script:work -Recurse -Force }
}
Check (-not (Test-Path -LiteralPath $script:work)) "the suite's temp folder is removed"

Complete-HordeSuite -Success "every tunable number of the decisions module is a named setting in one table, and a wrong table is refused"
