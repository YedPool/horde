# IS EVERY FUNCTION NAME IN THE CODE THAT SHIPS DEFINED EXACTLY ONCE?
#
# A structural guard (tools/FunctionNames.ps1). PowerShell gives a name to whichever definition was
# loaded last and says nothing, so two files defining one name make every caller that loads both run
# one of them by accident of load order. That happened on 2026-10-02: remote R0 (PR #55) added a
# second Find-HordeJsonDuplicateKey beside core/Ownership.ps1's, with other answers. This suite fails
# on any such pair anywhere in shipped code, so the class cannot come back.
#
# Two instruments, each with a control:
#   - THE PARSE, over every shipped file: two top-level definitions of one name, ignoring case.
#   - THE LOAD, of every core/, remote/ and relay/ file into one fresh session, as a caller that needs all of
#     them would: every function the parse found must resolve to the one file the parse says defines
#     it. This measures the symptom for every name the parse saw; a name the parse cannot see (one
#     built at run time) is the guard's stated limit, in tools/FunctionNames.ps1.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "tools\FunctionNames.ps1")

$fx = Join-Path $root "test\fixtures\function-names"

Write-Host ""
Write-Host "--- the parse: no name defined twice in shipped code ---" -ForegroundColor Cyan
$files = @(Get-HordeShippedScriptFiles -Root $root)
Check ($files.Count -ge 30) ("CONTROL: the shipped files were found (" + $files.Count + ")")
Check (($files -ccontains "core/Ownership.ps1") -and ($files -ccontains "core/PermissionLevels.ps1") -and ($files -ccontains "tools/FunctionNames.ps1")) "CONTROL: the two files of the 2026-10-02 collision, and this tool, are scanned"
Check (($files -ccontains "transports/local/Transport.ps1") -and ($files -ccontains "cli/commands/help.ps1") -and ($files -ccontains "horde.ps1")) "CONTROL: files in subfolders, and horde.ps1, are scanned"
Check (($files -ccontains "messengers/Port.ps1") -and ($files -ccontains "messengers/memory/Messenger.ps1") -and -not ($files -ccontains "messengers/memory/test/Fixture.ps1")) "CONTROL: the messengers ship and are scanned, their test fixtures not"
Check (($files -ccontains "decisions/Store.ps1") -and ($files -ccontains "decisions/Rules.ps1") -and ($files -ccontains "decisions/Operations.ps1")) "CONTROL: the decisions module ships and is scanned"
Check ($files -ccontains "platform/windows/Scale.ps1") "CONTROL: the platform code ships and is scanned"
Check (($files -ccontains "surfaces/Port.ps1") -and (@($files | Where-Object { $_ -clike "surfaces/*/Surface.ps1" }).Count -ge 1) -and -not ($files -clike "surfaces/*/test/*")) "CONTROL: the surfaces ship and are scanned, their suites not"
Check ($files -ccontains "fleet/StatusPanel.ps1") "CONTROL: the fleet code ships and is scanned"
Check (($files -ccontains "relay/Envelope.ps1") -and ($files -ccontains "relay/BackendCng.ps1") -and -not ($files -clike "relay/*/test/*")) "CONTROL: the relay module ships and is scanned"
Check (($files -ccontains "relays/Port.ps1") -and (@($files | Where-Object { $_ -clike "relays/*/Relay.ps1" }).Count -ge 1) -and -not ($files -clike "relays/*/test/*")) "CONTROL: the relays ship and are scanned, their test fixtures not"
Check (@($files | Where-Object { @($_ -split '/') -contains "test" }).Count -eq 0) "no file in a test folder is scanned: a suite may override a function in its own process"
$defs = @(Get-HordeTopFunctionDefinitions -Root $root -Files $files)
Check (@($defs | Where-Object { $_.name -ceq "<parse error>" }).Count -eq 0) ("every shipped file parses (" + (@($defs | Where-Object { $_.name -ceq "<parse error>" } | ForEach-Object { $_.file }) -join ", ") + ")")
Check ($defs.Count -ge 200) ("CONTROL: the parse found the shipped functions (" + $defs.Count + ")")
Check (@($defs | Where-Object { $_.name -ceq "Get-HordeHome" -and $_.file -ceq "core/Home.ps1" }).Count -eq 1) "CONTROL: a function known to be there is found in its file"
$dups = @(Find-HordeDuplicateFunctions -Definitions $defs)
foreach ($d in $dups) { Write-Host ("    " + $d.name + ": " + ($d.places -join ", ")) -ForegroundColor Red }
Check ($dups.Count -eq 0) ("no function name is defined twice in shipped code (" + $dups.Count + " found)")

Write-Host ""
Write-Host "--- the parse can see a duplicate ---" -ForegroundColor Cyan
$fxDefs = @(Get-HordeTopFunctionDefinitions -Root $fx -Files @("one.ps1", "two.ps1", "nested.ps1"))
$fxDups = @(Find-HordeDuplicateFunctions -Definitions $fxDefs)
Check ($fxDups.Count -eq 1 -and @($fxDups[0].places).Count -eq 2 -and (@($fxDups[0].places) -join ",") -ceq "one.ps1:2,two.ps1:3") "CONTROL: two files defining one name in different case are one duplicate"
Check (@($fxDefs | Where-Object { $_.file -ceq "nested.ps1" } | ForEach-Object { $_.name }) -join "," -ceq "Get-FixtureOuter") "a function defined inside another is local to it and not counted"
$fxOne = @(Find-HordeDuplicateFunctions -Definitions @(Get-HordeTopFunctionDefinitions -Root $fx -Files @("one.ps1", "nested.ps1")))
Check ($fxOne.Count -eq 0) "CONTROL: without the second file there is no duplicate"
$fxPrefix = @(Get-HordeTopFunctionDefinitions -Root $fx -Files @("one.ps1", "prefixed.ps1"))
Check (@(Find-HordeDuplicateFunctions -Definitions $fxPrefix).Count -eq 1) "a name with a scope prefix is the same name: function script:X and function X are one"
Check (@($fxPrefix | Where-Object { $_.file -ceq "prefixed.ps1" } | ForEach-Object { $_.name }) -join "," -ceq "script:Get-FixtureThing,Get-FixtureHolder,global:Get-FixtureNested,Get-FixtureItem,Get-FixtureAlias") "a global: function inside another, Set-Item function:X and Set-Alias X are definitions too"
# A CLASS METHOD IS NOT A COMMAND (batch 5, 2026-10-03: core/Metrics.ps1's HordeRecordOrderComparer.Compare,
# the first class method in core, was counted as a top-level function, and the load check could not
# find a command of that name).
$fxMethod = @(Get-HordeTopFunctionDefinitions -Root $fx -Files @("method.ps1"))
Check (@($fxMethod | ForEach-Object { $_.name }) -join "," -ceq "Compare" -and @(Find-HordeDuplicateFunctions -Definitions $fxMethod).Count -eq 0) "a class method is not counted: the file's one Compare is its top-level function"
$fxMethod2 = @(Get-HordeTopFunctionDefinitions -Root $fx -Files @("method.ps1", "compare-again.ps1"))
Check (@(Find-HordeDuplicateFunctions -Definitions $fxMethod2).Count -eq 1) "CONTROL: a top-level function of that same name in another file is still counted, and still a duplicate"
$badFile = Join-Path $env:TEMP ("horde-fnames-" + [guid]::NewGuid().ToString("N") + ".ps1")
try {
    [System.IO.File]::WriteAllText($badFile, "function Broken-Thing {")
    $bad = @(Get-HordeTopFunctionDefinitions -Root (Split-Path -Parent $badFile) -Files @(Split-Path -Leaf $badFile))
    Check (@($bad | Where-Object { $_.name -ceq "<parse error>" }).Count -eq 1) "a file that does not parse is reported, never skipped"
} finally { Remove-Item -LiteralPath $badFile -Force -ErrorAction SilentlyContinue }

Write-Host ""
Write-Host "--- the load: every core, remote and relay function resolves to its own file ---" -ForegroundColor Cyan
# A child process loads the files in one session, as a caller needing all of them would, then reports
# the file each function name resolves to. Names come from the parse; files the parse places them in.
function Invoke-HordeLoadCheck {
    param([string]$Base, [string[]]$Rels)
    $want = @(Get-HordeTopFunctionDefinitions -Root $Base -Files $Rels)
    $work = Join-Path $env:TEMP ("horde-fload-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        $lines = New-Object System.Collections.ArrayList
        [void]$lines.Add('$ErrorActionPreference = "Stop"')
        # Single-quoted, with any quote doubled, so a path holding $ or a backtick is not expanded.
        foreach ($r in $Rels) { [void]$lines.Add(". '" + (Join-Path $Base $r).Replace("'", "''") + "'") }
        foreach ($d in $want) {
            [void]$lines.Add('$c = Get-Command -Name "' + $d.name + '" -CommandType Function -ErrorAction SilentlyContinue; if ($null -eq $c) { "MISSING|' + $d.name + '" } else { "AT|' + $d.name + '|" + $c.ScriptBlock.File }')
        }
        [void]$lines.Add('"END"')
        $script = Join-Path $work "load.ps1"
        [System.IO.File]::WriteAllText($script, ($lines -join "`r`n"))
        $out = @(& powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script | ForEach-Object { "$_" })
        $wrong = New-Object System.Collections.ArrayList
        foreach ($d in $want) {
            $expected = [System.IO.Path]::GetFullPath((Join-Path $Base $d.file))
            $got = @($out | Where-Object { $_ -like ("AT|" + $d.name + "|*") }) | Select-Object -First 1
            if ($null -eq $got) { [void]$wrong.Add($d.name + " did not load"); continue }
            $gotFile = ($got -split '\|', 3)[2]
            if (-not [string]::Equals([System.IO.Path]::GetFullPath($gotFile), $expected, [System.StringComparison]::OrdinalIgnoreCase)) { [void]$wrong.Add($d.name + " resolves to " + $gotFile + ", not " + $d.file) }
        }
        return [pscustomobject]@{ ended = (@($out) -ccontains "END"); count = $want.Count; wrong = @($wrong) }
    } finally {
        if ((Split-Path -Leaf $work) -match '^horde-fload-[0-9a-f]{32}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
$loadFiles = @($files | Where-Object { $_ -like "core/*" -or $_ -like "remote/*" -or $_ -like "relay/*" } | Sort-Object)
$load = Invoke-HordeLoadCheck -Base $root -Rels $loadFiles
foreach ($w in $load.wrong) { Write-Host ("    " + $w) -ForegroundColor Red }
Check ($load.ended -eq $true -and $load.count -ge 150) ("CONTROL: the load ran to its end over " + $loadFiles.Count + " files and " + $load.count + " functions")
Check ($load.wrong.Count -eq 0) ("every core, remote and relay function resolves to the one file that defines it (" + $load.wrong.Count + " do not)")
$fxLoad = Invoke-HordeLoadCheck -Base $fx -Rels @("one.ps1", "two.ps1")
Check ($fxLoad.ended -eq $true -and @($fxLoad.wrong | Where-Object { $_ -like "Get-FixtureThing resolves to *two.ps1, not one.ps1" }).Count -eq 1) "CONTROL: the load sees the first of two definitions lose to the second"

Complete-HordeSuite -Success "every function name in shipped code is defined once, by the parse and by the load"
