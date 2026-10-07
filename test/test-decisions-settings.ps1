# IS EVERY NUMBER THE DECISIONS MODULE CAN BE TUNED BY A NAMED SETTING, IN ONE TABLE, AND NOWHERE ELSE?
#
# decisions/Settings.ps1 and its table, decisions/settings.json. This suite attacks three things:
#   - THE READER REFUSES A WRONG TABLE WHOLE: a default outside its own range, a range upside down, a
#     number that is not whole, a setting that does not say what it means. A wait of -1 would
#     otherwise surface as a hang, far from the table.
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
function Read-Table {
    # Write -Json as a table file of this suite's own and read it with the shipped reader. Returns
    # the table, or the text "THREW: <message>".
    param([string]$Json)
    $script:n++
    $path = Join-Path $script:work ("table-" + $script:n + ".json")
    [System.IO.File]::WriteAllText($path, $Json, $utf8)
    try { return (Read-HordeDecisionSettingsFile -Path $path) } catch { return ("THREW: " + $_.Exception.Message) }
}
function Get-One { param([string]$Body) return ('{"schemaVersion":1,"settings":{' + $Body + '}}') }

try {

Write-Host ""
Write-Host "--- the shipped table ---" -ForegroundColor Cyan
$table = @(Get-HordeDecisionSettingTable)
Check ($table.Count -ge 7) ("CONTROL: the shipped table is read, and names its settings (" + $table.Count + ")")
Check (@($table | Where-Object { $_.default -lt $_.least -or $_.default -gt $_.most -or "$($_.means)".Trim() -eq "" }).Count -eq 0) "every setting's default is inside its own range, and every one says what it means"
Check ((Get-HordeDecisionSetting -Name "decisions.store.maxGap") -eq 100 -and (Get-HordeDecisionSetting -Name "decisions.store.maxGap") -is [long]) "a setting is handed out as a whole 64-bit number"
Check (Throws { Get-HordeDecisionSetting -Name "decisions.store.maxgap" } "is not a setting") "a name in another case is not a setting: it throws, and never reads as 0"
Check (Throws { Get-HordeDecisionSetting -Name "decisions.store.noSuchThing" } "is not a setting") "a name the table does not have throws"
Check ((@($table | ForEach-Object { $_.name }) -join ",") -ceq (@($table | ForEach-Object { $_.name } | Sort-Object) -join ",")) "the table is handed out in name order, so a page that shows it is the same every time"

Write-Host ""
Write-Host "--- a wrong table is refused whole ---" -ForegroundColor Cyan
$good = Read-Table (Get-One '"decisions.a.b":{"default":5,"least":1,"most":9,"means":"a number"}')
Check ($good -isnot [string] -and $good.ContainsKey("decisions.a.b") -and $good["decisions.a.b"].default -eq 5 -and $good["decisions.a.b"].least -eq 1 -and $good["decisions.a.b"].most -eq 9) "CONTROL: a right table of one setting is read, with its default and its range"
Check ((Read-Table (Get-One '"decisions.a.b":{"default":5,"least":5,"most":5,"means":"a number"}')) -isnot [string]) "CONTROL: a default AT both ends of its range is inside it"
Check ("$(Read-Table (Get-One '"decisions.a.b":{"default":0,"least":1,"most":9,"means":"a number"}'))" -like "THREW:*outside its own range*") "a default below its range is refused"
Check ("$(Read-Table (Get-One '"decisions.a.b":{"default":10,"least":1,"most":9,"means":"a number"}'))" -like "THREW:*outside its own range*") "a default above its range is refused"
Check ("$(Read-Table (Get-One '"decisions.a.b":{"default":5,"least":9,"most":1,"means":"a number"}'))" -like "THREW:*upside down*") "a range that is upside down is refused"
Check ("$(Read-Table (Get-One '"decisions.a.b":{"default":1.5,"least":1,"most":9,"means":"a number"}'))" -like "THREW:*no whole number for 'default'*") "a default that is not a whole number is refused"
Check ("$(Read-Table (Get-One '"decisions.a.b":{"default":"5","least":1,"most":9,"means":"a number"}'))" -like "THREW:*no whole number for 'default'*") "a default written as text is refused, not converted"
Check ("$(Read-Table (Get-One '"decisions.a.b":{"default":5,"least":1,"most":1e30,"means":"a number"}'))" -like "THREW:*no whole number for 'most'*") "a limit too large to be a whole number is refused"
Check ("$(Read-Table (Get-One '"decisions.a.b":{"default":5,"most":9,"means":"a number"}'))" -like "THREW:*no whole number for 'least'*") "a setting with no lower limit is refused"
Check ("$(Read-Table (Get-One '"decisions.a.b":{"default":5,"least":1,"most":9}'))" -like "THREW:*does not say what it means*") "a setting that does not say what it means is refused"
Check ("$(Read-Table (Get-One '"decisions.a.b":{"default":5,"least":1,"most":9,"means":"  "}'))" -like "THREW:*does not say what it means*") "and so is one whose meaning is blank"
Check ("$(Read-Table (Get-One '"decisions.a.b":5'))" -like "THREW:*no whole number*") "a setting written as a bare number, with no range, is refused"
Check ("$(Read-Table (Get-One '"store.maxGap":{"default":5,"least":1,"most":9,"means":"a number"}'))" -like "THREW:*is not named decisions.<part>.<name>*") "a setting not named for the module is refused"
Check ("$(Read-Table (Get-One '"decisions.a.b":{"default":5,"least":1,"most":9,"means":"a number"},"decisions.c.d":{"default":50,"least":1,"most":9,"means":"a number"}'))" -like "THREW:*decisions.c.d*outside its own range*") "one wrong setting refuses the whole table, by its name"
Check ("$(Read-Table '{"schemaVersion":2,"settings":{"decisions.a.b":{"default":5,"least":1,"most":9,"means":"a number"}}}')" -like "THREW:*schemaVersion 1*") "a table of another version is refused"
Check ("$(Read-Table '{"schemaVersion":1,"settings":[]}')" -like "THREW:*schemaVersion 1 and a settings object*") "a table whose settings are not an object is refused"
Check ("$(Read-Table '{"schemaVersion":1,"settings":{}}')" -like "THREW:*names no setting*") "a table that names no setting is refused"

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
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-decisions-settings-test-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) { Remove-Item -LiteralPath $script:work -Recurse -Force }
}
Check (-not (Test-Path -LiteralPath $script:work)) "the suite's temp folder is removed"

Complete-HordeSuite -Success "every tunable number of the decisions module is a named setting in one table, and a wrong table is refused"
