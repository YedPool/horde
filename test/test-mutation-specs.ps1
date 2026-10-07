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
. (Join-Path $root "test\lib\SuiteSections.ps1")

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
        $suitePath = Join-Path $rootFull "$($s.Suite)"
        if ("$($s.Suite)" -match "[\x00-\x1F]" -or -not (Test-Path -LiteralPath $suitePath -PathType Leaf)) { [void]$out.Add($rel + ": its suite " + ("$($s.Suite)" -replace "[\x00-\x1F]", "?") + " does not exist") }
        $text = [System.IO.File]::ReadAllText($target)
        # A SECTION MAP NAMES ONLY SECTIONS THE SUITE DECLARES. tools\Mutate.ps1 refuses a wrong map too,
        # but only when that spec is run; a suite whose section is renamed would leave every spec mapped
        # to it broken until then. The rule is test\lib\SuiteSections.ps1's, shared with the tool.
        $declared = $null
        if (@($s.Mutations | Where-Object { $_ -is [hashtable] -and $_.ContainsKey("Sections") }).Count -gt 0 -and (Test-Path -LiteralPath $suitePath -PathType Leaf)) {
            $declared = Get-HordeSuiteSectionIds -Path $suitePath
        }
        foreach ($m in @($s.Mutations)) {
            if ($null -ne $declared -and $m.ContainsKey("Sections")) {
                $why = Get-HordeMutantSectionProblem -Mutant $m -Suite "$($s.Suite)" -Declared $declared -SpecEnvironment $s.Environment
                if ($why) { [void]$out.Add($rel + " :: " + $m.Name + ": " + $why) }
            }
            # tools\Mutate.ps1 refuses a find that spans lines, since line endings differ by checkout;
            # it would occur once here and still not apply (review of PR #62, probe Q4).
            if ("$($m.Find)" -match "[\r\n]") { [void]$out.Add($rel + " :: " + $m.Name + ": its find string spans lines, which tools\Mutate.ps1 refuses"); continue }
            $n = Get-FindCount -Text $text -Find "$($m.Find)"
            if ($n -ne 1) { [void]$out.Add($rel + " :: " + $m.Name + ": its find string occurs " + $n + " times in " + $s.Target + ", not once") }
        }
    }
    return @($out)
}

$specs = @(Get-HordeMutationSpecFiles -Root $root)
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
    $planted = @(Get-SpecProblems -Root $fx -Specs @(Get-HordeMutationSpecFiles -Root $fx))
    Check (@($planted | Where-Object { $_ -match 'planted\.psd1 :: twice: its find string occurs 2 times' }).Count -eq 1) "CONTROL: a find string that occurs twice is reported, with its spec and mutant"
    Check (@($planted | Where-Object { $_ -match 'planted\.psd1 :: absent: its find string occurs 0 times' }).Count -eq 1) "CONTROL: a find string that does not occur is reported"
    Check (@($planted | Where-Object { $_ -match 'no-target\.psd1: its target gone\.ps1 does not exist' }).Count -eq 1) "CONTROL: a spec whose target is missing is reported"
    Check (@($planted | Where-Object { $_ -match ':: once:' }).Count -eq 0) "CONTROL: a find string that occurs once is not"
    # A SUITE PATH THAT DOES NOT EXIST passed this guard and failed only on the remote box, as a run
    # with no verdict: a spec written with a tab where a backslash belonged (2026-10-02).
    [System.IO.File]::WriteAllText((Join-Path $fx "s.ps1"), "# a suite")
    [System.IO.File]::WriteAllText((Join-Path $fx "test\mutations\no-suite.psd1"), ("@{ Target = 't.ps1'; Suite = 'test" + [char]9 + "est.ps1'; Mutations = @(@{ Name = 'ok'; Find = 'function C'; Replace = 'function Z' }) }"))
    $planted3 = @(Get-SpecProblems -Root $fx -Specs @(Get-HordeMutationSpecFiles -Root $fx))
    Check (@($planted3 | Where-Object { $_ -match 'no-suite\.psd1: its suite .* does not exist' }).Count -eq 1) "a spec whose suite does not exist is reported"
    Check (@($planted3 | Where-Object { $_ -match 'planted\.psd1: its suite' }).Count -eq 0) "CONTROL: one whose suite exists is not"
    Remove-Item -LiteralPath (Join-Path $fx "test\mutations\no-suite.psd1") -Force
    # A SPEC IN A SUBFOLDER OF mutations/ IS STILL A SPEC (review of PR #62, probe Q1: one in
    # test\mutations\sub\ was not seen and the suite passed).
    New-Item -ItemType Directory -Path (Join-Path $fx "test\mutations\sub") | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $fx "test\mutations\sub\nested.psd1"), "@{ Target = 't.ps1'; Suite = 's.ps1'; Mutations = @(@{ Name = 'nested-twice'; Find = 'return 1'; Replace = 'return 2' }) }")
    # A FIND STRING THAT SPANS LINES occurs once here, yet tools\Mutate.ps1 refuses it as invalid -
    # line endings differ by checkout (probe Q4: it passed this guard).
    [System.IO.File]::WriteAllText((Join-Path $fx "test\mutations\multiline.psd1"), "@{ Target = 't.ps1'; Suite = 's.ps1'; Mutations = @(@{ Name = 'spans'; Find = ""return 3 }``r``nfunction C""; Replace = 'x' }) }")
    [System.IO.File]::WriteAllText((Join-Path $fx "t.ps1"), "function A { return 1 }`r`nfunction B { return 1 }`r`nfunction C { return 3 }`r`nfunction C2 { return 3 }`r`n")
    # ANY mutations FOLDER, AT ANY DEPTH: a port's own spec folder, a spec two folders below
    # mutations/, and a mutations/ folder outside the suite folders are all specs. One rule, shared
    # with tools\Mutate.ps1 -Changed, which otherwise never selected what this suite checked (review
    # of PR #62/#63, 2026-10-02).
    New-Item -ItemType Directory -Path (Join-Path $fx "agents\demo\test\mutations\deep\deeper") | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $fx "agents\demo\test\mutations\deep\deeper\port.psd1"), "@{ Target = 't.ps1'; Suite = 's.ps1'; Mutations = @(@{ Name = 'port-deep'; Find = 'return 9'; Replace = 'return 8' }) }")
    New-Item -ItemType Directory -Path (Join-Path $fx "tools\mutations") | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $fx "tools\mutations\elsewhere.psd1"), "@{ Target = 't.ps1'; Suite = 's.ps1'; Mutations = @(@{ Name = 'elsewhere'; Find = 'return 9'; Replace = 'return 8' }) }")
    New-Item -ItemType Directory -Path (Join-Path $fx "test\fixtures\mutations") | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $fx "test\fixtures\mutations\data.psd1"), "@{ Target = 't.ps1'; Suite = 's.ps1'; Mutations = @(@{ Name = 'fixture-data'; Find = 'return 9'; Replace = 'return 8' }) }")
    $planted2 = @(Get-SpecProblems -Root $fx -Specs @(Get-HordeMutationSpecFiles -Root $fx))
    Check (@($planted2 | Where-Object { $_.StartsWith('agents\demo\test\mutations\deep\deeper\port.psd1 :: port-deep:') }).Count -eq 1) "a spec two folders deep in a port's own mutations folder is checked"
    Check (@($planted2 | Where-Object { $_.StartsWith('tools\mutations\elsewhere.psd1 :: elsewhere:') }).Count -eq 1) "a spec in a mutations folder outside the suite folders is checked"
    Check (@($planted2 | Where-Object { $_ -match 'fixture-data' }).Count -eq 0) "CONTROL: a mutations folder under test\fixtures is data, not a spec"
    Check (@($planted2 | Where-Object { $_ -match 'sub\\nested\.psd1 :: nested-twice: its find string occurs 2 times' }).Count -eq 1) "a spec in a subfolder of mutations is checked too"
    Check (@($planted2 | Where-Object { $_ -match 'multiline\.psd1 :: spans: its find string spans lines' }).Count -eq 1) "a find string that spans lines is refused, as tools\Mutate.ps1 refuses it"
    # SECTION MAPS (perf/mutate-sections): a name the suite does not declare, a map on a suite that
    # declares none, and an empty map are each reported; a good map is not.
    [System.IO.File]::WriteAllText((Join-Path $fx "sec.ps1"), "Register-HordeSuiteSections -Ids @(`"alpha`", `"beta`")`r`n")
    [System.IO.File]::WriteAllText((Join-Path $fx "test\mutations\mapped.psd1"), "@{ Target = 't.ps1'; Suite = 'sec.ps1'; Mutations = @(@{ Name = 'map-good'; Find = 'function C2'; Replace = 'function Z'; Sections = @('beta') }, @{ Name = 'map-typo'; Find = 'function B'; Replace = 'function Y'; Sections = @('alpha', 'btea') }, @{ Name = 'map-empty'; Find = 'function A'; Replace = 'function X'; Sections = @() }) }")
    [System.IO.File]::WriteAllText((Join-Path $fx "test\mutations\mapped-nowhere.psd1"), "@{ Target = 't.ps1'; Suite = 's.ps1'; Mutations = @(@{ Name = 'map-nowhere'; Find = 'function C2'; Replace = 'function Z'; Sections = @('alpha') }) }")
    $planted4 = @(Get-SpecProblems -Root $fx -Specs @(Get-HordeMutationSpecFiles -Root $fx))
    Check (@($planted4 | Where-Object { $_ -match "mapped\.psd1 :: map-typo: section 'btea' is not one sec\.ps1 declares" }).Count -eq 1) "a mapped section the suite does not declare is reported"
    Check (@($planted4 | Where-Object { $_ -match 'mapped\.psd1 :: map-empty: its Sections names no section' }).Count -eq 1) "an empty section map is reported"
    Check (@($planted4 | Where-Object { $_ -match 'mapped-nowhere\.psd1 :: map-nowhere: its suite s\.ps1 declares no sections' }).Count -eq 1) "a map on a suite that declares no sections is reported"
    Check (@($planted4 | Where-Object { $_ -match ':: map-good:' }).Count -eq 0) "CONTROL: a map that names a declared section is not"
    # A SECTION LIST THE TEXT CANNOT ANSWER is refused, not guessed at: one built at run time, one
    # declared twice, one given without -Ids. And a map outside the spec's own HORDE_SECTIONS names a
    # section no whole run of that spec ever tries.
    [System.IO.File]::WriteAllText((Join-Path $fx "dyn.ps1"), "Register-HordeSuiteSections -Ids @(`"alpha`", `$more)`r`n")
    [System.IO.File]::WriteAllText((Join-Path $fx "twice.ps1"), "Register-HordeSuiteSections -Ids @(`"alpha`")`r`nRegister-HordeSuiteSections -Ids @(`"alpha`")`r`n")
    [System.IO.File]::WriteAllText((Join-Path $fx "positional.ps1"), "Register-HordeSuiteSections @(`"alpha`")`r`n")
    foreach ($pair in @(@("dyn", "dyn.ps1"), @("twice", "twice.ps1"), @("positional", "positional.ps1"))) {
        [System.IO.File]::WriteAllText((Join-Path $fx ("test\mutations\read-" + $pair[0] + ".psd1")), ("@{ Target = 't.ps1'; Suite = '" + $pair[1] + "'; Mutations = @(@{ Name = 'read-" + $pair[0] + "'; Find = 'function C2'; Replace = 'function Z'; Sections = @('alpha') }) }"))
    }
    [System.IO.File]::WriteAllText((Join-Path $fx "test\mutations\filtered.psd1"), "@{ Target = 't.ps1'; Suite = 'sec.ps1'; Environment = @{ HORDE_SECTIONS = 'alpha' }; Mutations = @(@{ Name = 'map-outside'; Find = 'function C2'; Replace = 'function Z'; Sections = @('beta') }, @{ Name = 'map-inside'; Find = 'function B'; Replace = 'function Y'; Sections = @('alpha') }) }")
    $planted5 = @(Get-SpecProblems -Root $fx -Specs @(Get-HordeMutationSpecFiles -Root $fx))
    Check (@($planted5 | Where-Object { $_ -match 'read-dyn: its suite dyn\.ps1 builds its section list at run time' }).Count -eq 1) "a section list built at run time is refused, not guessed at"
    Check (@($planted5 | Where-Object { $_ -match 'read-twice: its suite twice\.ps1 declares its sections 2 times' }).Count -eq 1) "a suite that declares its sections twice is refused"
    Check (@($planted5 | Where-Object { $_ -match 'read-positional: its suite positional\.ps1 declares its sections without -Ids' }).Count -eq 1) "a section list given without -Ids is refused"
    Check (@($planted5 | Where-Object { $_ -match "filtered\.psd1 :: map-outside: section 'beta' is outside the spec's own HORDE_SECTIONS \(alpha\)" }).Count -eq 1) "a map outside the spec's own section filter is reported"
    Check (@($planted5 | Where-Object { $_ -match ':: map-inside:' }).Count -eq 0) "CONTROL: a map inside it is not"
} finally {
    if ((Split-Path -Leaf $fx) -match '^horde-specfind-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $fx)) { Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue }
}

$mapped = 0; foreach ($f in $specs) { $mapped += @((Import-PowerShellDataFile -LiteralPath $f.FullName).Mutations | Where-Object { $_.ContainsKey("Sections") }).Count }
Check ($mapped -ge 40) ("CONTROL: the repository's specs map mutants to sections, so the map check has maps to check (" + $mapped + ")")
$problems = @(Get-SpecProblems -Root $root -Specs $specs)
foreach ($p in $problems) { Write-Host ("        " + $p) -ForegroundColor Red }
Check ($problems.Count -eq 0) ("every mutant of every spec applies: its find string occurs exactly once in its target (" + $mutants + " mutants in " + $specs.Count + " specs, " + $problems.Count + " that do not)")

Complete-HordeSuite -Success "every mutant of every spec has exactly one place to apply"
