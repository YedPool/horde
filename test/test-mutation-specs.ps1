# EVERY MUTANT OF EVERY SPEC MUST APPLY: its find string occurs exactly once in its spec's target.
# tools\Mutate.ps1 refuses a mutant whose find string occurs zero times or more than once ("did not
# apply"), but only when that spec is run, and the full specs are run rarely. Meanwhile any edit to a
# target can add a second copy of a find string, or remove the only one. That happened: 56e99a7 (PR
# #57) copied the line that test\mutations\port-names.psd1's port-own-folder-assumed-hosts mutates
# into a second function of tools\HostNames.ps1, and the spec stayed broken on main, unseen, until
# the -Changed selector placed every mutant on 2026-10-02. This suite checks every spec on every gate
# run, by text alone - no suite is run - so it costs seconds.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\SuiteFiles.ps1")

function Get-SpecFiles {
    # Every <suite folder>/mutations/*.psd1, for the suite folders of test\lib\SuiteFiles.ps1.
    param([string]$Root)
    $out = New-Object System.Collections.ArrayList
    foreach ($pattern in $script:HordeSuiteFolders) {
        $dirs = @(Get-Item -LiteralPath $Root)
        foreach ($p in @(($pattern -split "/") + "mutations")) {
            $next = @()
            foreach ($d in $dirs) {
                if ($p -eq "*") { $next += @(Get-ChildItem -LiteralPath $d.FullName -Directory -ErrorAction SilentlyContinue) }
                else { $c = Join-Path $d.FullName $p; if (Test-Path -LiteralPath $c -PathType Container) { $next += @(Get-Item -LiteralPath $c) } }
            }
            $dirs = $next
        }
        foreach ($d in $dirs) { foreach ($f in @(Get-ChildItem -LiteralPath $d.FullName -Filter "*.psd1" -File | Where-Object { $_.Extension -ceq ".psd1" })) { [void]$out.Add($f) } }
    }
    return @($out)
}

function Get-FindCount {
    param([string]$Text, [string]$Find)
    if ($Find.Length -eq 0) { return 0 }
    $n = 0; $i = 0
    while (($i = $Text.IndexOf($Find, $i, [System.StringComparison]::Ordinal)) -ge 0) { $n++; $i += $Find.Length }
    return $n
}

function Get-SpecProblems {
    # One line per mutant that would not apply: "<spec> :: <mutant>: <why>". Empty means every one does.
    param([string]$Root, [object[]]$Specs)
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
    $out = New-Object System.Collections.ArrayList
    foreach ($f in $Specs) {
        $rel = $f.FullName.Substring($rootFull.Length + 1)
        $s = Import-PowerShellDataFile -LiteralPath $f.FullName
        $target = Join-Path $rootFull "$($s.Target)"
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { [void]$out.Add($rel + ": its target " + $s.Target + " does not exist"); continue }
        $text = [System.IO.File]::ReadAllText($target)
        foreach ($m in @($s.Mutations)) {
            $n = Get-FindCount -Text $text -Find "$($m.Find)"
            if ($n -ne 1) { [void]$out.Add($rel + " :: " + $m.Name + ": its find string occurs " + $n + " times in " + $s.Target + ", not once") }
        }
    }
    return @($out)
}

$specs = @(Get-SpecFiles -Root $root)
$mutants = 0; foreach ($f in $specs) { $mutants += @((Import-PowerShellDataFile -LiteralPath $f.FullName).Mutations).Count }
# CONTROLS: the search finds the specs and mutants known to be there, so an empty problem list means
# something.
Check ($specs.Count -ge 40) ("CONTROL: the spec search finds the repository's specs (" + $specs.Count + ")")
Check (@($specs | Where-Object { $_.FullName -like "*\test\mutations\port-names.psd1" }).Count -eq 1) "CONTROL: it finds test\mutations\port-names.psd1"
Check (@($specs | Where-Object { $_.FullName -match '\\hosts\\[^\\]+\\test\\mutations\\' }).Count -ge 1) "CONTROL: it finds a spec in a host's own folder"
Check (@($specs | Where-Object { $_.FullName -like "*\test\fixtures\*" }).Count -eq 0) "CONTROL: fixture specs are not specs"

# CONTROL: on a planted spec, a find string that occurs twice, one that is missing, and a missing
# target are each reported, and one that occurs once is not.
$fx = Join-Path $env:TEMP ("horde-specfind-" + [guid]::NewGuid().ToString("N"))
try {
    New-Item -ItemType Directory -Path (Join-Path $fx "test\mutations") | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $fx "t.ps1"), "function A { return 1 }`r`nfunction B { return 1 }`r`nfunction C { return 3 }`r`n")
    [System.IO.File]::WriteAllText((Join-Path $fx "test\mutations\planted.psd1"), "@{ Target = 't.ps1'; Suite = 's.ps1'; Mutations = @(@{ Name = 'twice'; Find = 'return 1'; Replace = 'return 2' }, @{ Name = 'absent'; Find = 'return 9'; Replace = 'return 8' }, @{ Name = 'once'; Find = 'return 3'; Replace = 'return 4' }) }")
    [System.IO.File]::WriteAllText((Join-Path $fx "test\mutations\no-target.psd1"), "@{ Target = 'gone.ps1'; Suite = 's.ps1'; Mutations = @(@{ Name = 'x'; Find = 'y'; Replace = 'z' }) }")
    $planted = @(Get-SpecProblems -Root $fx -Specs @(Get-SpecFiles -Root $fx))
    Check (@($planted | Where-Object { $_ -match 'planted\.psd1 :: twice: its find string occurs 2 times' }).Count -eq 1) "CONTROL: a find string that occurs twice is reported, with its spec and mutant"
    Check (@($planted | Where-Object { $_ -match 'planted\.psd1 :: absent: its find string occurs 0 times' }).Count -eq 1) "CONTROL: a find string that does not occur is reported"
    Check (@($planted | Where-Object { $_ -match 'no-target\.psd1: its target gone\.ps1 does not exist' }).Count -eq 1) "CONTROL: a spec whose target is missing is reported"
    Check (@($planted | Where-Object { $_ -match ':: once:' }).Count -eq 0) "CONTROL: a find string that occurs once is not"
    # A SPEC IN A SUBFOLDER OF mutations/ IS STILL A SPEC (review of PR #62, probe Q1: one in
    # test\mutations\sub\ was not seen and the suite passed).
    New-Item -ItemType Directory -Path (Join-Path $fx "test\mutations\sub") | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $fx "test\mutations\sub\nested.psd1"), "@{ Target = 't.ps1'; Suite = 's.ps1'; Mutations = @(@{ Name = 'nested-twice'; Find = 'return 1'; Replace = 'return 2' }) }")
    # A FIND STRING THAT SPANS LINES occurs once here, yet tools\Mutate.ps1 refuses it as invalid -
    # line endings differ by checkout (probe Q4: it passed this guard).
    [System.IO.File]::WriteAllText((Join-Path $fx "test\mutations\multiline.psd1"), "@{ Target = 't.ps1'; Suite = 's.ps1'; Mutations = @(@{ Name = 'spans'; Find = ""return 3 }``r``nfunction C""; Replace = 'x' }) }")
    [System.IO.File]::WriteAllText((Join-Path $fx "t.ps1"), "function A { return 1 }`r`nfunction B { return 1 }`r`nfunction C { return 3 }`r`nfunction C2 { return 3 }`r`n")
    $planted2 = @(Get-SpecProblems -Root $fx -Specs @(Get-SpecFiles -Root $fx))
    Check (@($planted2 | Where-Object { $_ -match 'sub\\nested\.psd1 :: nested-twice: its find string occurs 2 times' }).Count -eq 1) "a spec in a subfolder of mutations is checked too"
    Check (@($planted2 | Where-Object { $_ -match 'multiline\.psd1 :: spans: its find string spans lines' }).Count -eq 1) "a find string that spans lines is refused, as tools\Mutate.ps1 refuses it"
} finally {
    if ((Split-Path -Leaf $fx) -match '^horde-specfind-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $fx)) { Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue }
}

$problems = @(Get-SpecProblems -Root $root -Specs $specs)
foreach ($p in $problems) { Write-Host ("        " + $p) -ForegroundColor Red }
Check ($problems.Count -eq 0) ("every mutant of every spec applies: its find string occurs exactly once in its target (" + $mutants + " mutants in " + $specs.Count + " specs, " + $problems.Count + " that do not)")

Complete-HordeSuite -Success "every mutant of every spec has exactly one place to apply"
