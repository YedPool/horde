# IS HORDE'S PERMISSION-LEVEL VOCABULARY CLOSED, ORDERED, AND FREE OF ANY HARNESS?
#
# Remote plan step R0 (planning/execution-plan-remote.md). core/permission-levels.json is read by two
# later steps that must not wait on each other: engines E2, whose descriptor maps every level to one
# harness's flags exactly once, and remote R9, whose node ceiling refuses a spawn or a drive above it.
# This suite holds the file to the rules both depend on, and holds the coverage check E2 will call to
# the change that matters most: a level added to or removed from the vocabulary must break a
# descriptor written against the old list, so no harness keeps running on a stale mapping.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\PermissionLevels.ps1")
. (Join-Path $root "tools\HostNames.ps1")

$realPath = Join-Path $root "core\permission-levels.json"
function Names { param($Levels) return (@($Levels | ForEach-Object { $_.name }) -join ",") }
# A vocabulary as text, one row per name, each with a plain meaning. Tests build their variants here,
# so a variant differs from a well-formed table only in what the test says it changes.
function LevelsText {
    param([string[]]$Names, [string]$Extra = "")
    $rows = @($Names | ForEach-Object { '{ "name": "' + $_ + '", "meaning": "A level used only by this suite."' + $Extra + ' }' })
    return ('{ "levels": [ ' + ($rows -join ", ") + ' ] }')
}
function Problems { param([string]$Text) return @(Test-HordePermissionLevelTable -Table ($Text | ConvertFrom-Json)) }
function HasProblem { param([string]$Text, [string]$Like) return (@(Problems $Text | Where-Object { $_ -like "*$Like*" }).Count -gt 0) }

Write-Host ""
Write-Host "--- loading the module ---" -ForegroundColor Cyan
$strictKept = & { Set-StrictMode -Version Latest; . (Join-Path $root "core\PermissionLevels.ps1"); try { $null = $hordeNeverAssignedVariable; $false } catch { $true } }
Check ($strictKept -eq $true) "dot-sourcing core/PermissionLevels leaves the caller's strict mode on"

Write-Host ""
Write-Host "--- the vocabulary on disk ---" -ForegroundColor Cyan
# Loaded inside a check, so a loader that throws on the real file fails a check here instead of
# stopping the suite with an error, which a mutation run cannot count as a catch.
$levels = @()
$loadError = ""
try { $levels = @(Get-HordePermissionLevels) } catch { $loadError = "$($_.Exception.Message)" }
Check ($loadError -eq "") ("the vocabulary on disk loads" + $(if ($loadError -ne "") { ": " + $loadError } else { "" }))
Check ($levels.Count -gt 0) "the vocabulary is not empty"
# THE AGREED ORDER, as a golden. Changing it is a policy change - a ceiling of 'edits' would admit or
# refuse different sessions - so it must be a deliberate edit to this line, seen in review.
Check ((Names $levels) -ceq "plan,ask,edits,bypass") "the levels are plan < ask < edits < bypass, lowest first"
$ranksInOrder = $true
for ($i = 0; $i -lt $levels.Count; $i++) { if ($levels[$i].rank -ne $i) { $ranksInOrder = $false } }
Check ($ranksInOrder -eq $true) "each level's rank is its position in the file, so a later row is a higher level"
Check (@($levels | Where-Object { "$($_.meaning)".Trim() -eq "" }).Count -eq 0) "every level has a meaning"
Check (@(Problems ([System.IO.File]::ReadAllText($realPath))).Count -eq 0) "the file on disk passes its own table check"
$bytes = [System.IO.File]::ReadAllBytes($realPath)
Check (@($bytes | Where-Object { $_ -gt 0x7E -or ($_ -lt 0x20 -and $_ -ne 0x0A -and $_ -ne 0x0D) }).Count -eq 0) "the file is printable ASCII (CONTRIBUTING 13)"

Write-Host ""
Write-Host "--- the file names no harness and no terminal (CONTRIBUTING 14) ---" -ForegroundColor Cyan
# The ratchet, test/test-host-names.ps1, scans every file outside a port's folder. These checks say
# that it reaches this file, and that no name any port declares is in it - with a control proving the
# same counter finds a declared name when one is there.
$scanned = @(Get-HordeRepoFiles -RepoRoot $root -Skip @() | Where-Object { $_.rel -ceq "core/permission-levels.json" })
Check ($scanned.Count -eq 1) "the port-names ratchet scans core/permission-levels.json"
$declared = New-Object System.Collections.ArrayList
foreach ($family in @("agents", "hosts")) {
    foreach ($f in @(Get-ChildItem -Path (Join-Path $root ($family + "\*\names.txt")) -File)) {
        foreach ($k in @((Get-HordeHostNameSet -Text ([System.IO.File]::ReadAllText($f.FullName))).Keys)) { [void]$declared.Add("$k") }
    }
}
Check ($declared.Count -ge 2) "the ports declare names to look for (found $($declared.Count))"
Check ((Get-HordeNameMentionCount -Full $realPath -Rel "core/permission-levels.json" -Names @($declared)) -eq 0) "no declared harness or terminal name appears in the vocabulary"
$planted = Join-Path $env:TEMP ("horde-permlevels-" + [guid]::NewGuid().ToString("N") + ".json")
try {
    [System.IO.File]::WriteAllText($planted, (LevelsText -Names @("plan")).Replace("only by this suite", "only by " + $declared[0]))
    Check ((Get-HordeNameMentionCount -Full $planted -Rel "planted.json" -Names @($declared)) -eq 1) "control: the same counter finds a declared name planted in a meaning"
} finally { Remove-Item -LiteralPath $planted -Force -ErrorAction SilentlyContinue }

Write-Host ""
Write-Host "--- the table check refuses every malformed vocabulary ---" -ForegroundColor Cyan
Check (@(Problems (LevelsText -Names @("plan", "ask"))).Count -eq 0) "control: a well-formed two-level table passes"
Check (HasProblem '{ "levels": [] }' "empty") "an empty list is refused"
Check (HasProblem '{ "other": [] }' "no levels key") "a table with no levels key is refused, and says so"
Check (HasProblem '{ "levels": { "name": "plan", "meaning": "x" } }' "list") "levels that are not a list are refused"
Check (HasProblem '"plan"' "object") "a vocabulary that is not an object is refused"
Check (HasProblem ((LevelsText -Names @("plan")).Replace(' ] }', ' ], "extra": 1 }')) "extra") "a key beside levels is refused"
Check (HasProblem (LevelsText -Names @("plan", "ask", "plan")) "twice") "a level listed twice is refused"
Check (HasProblem (LevelsText -Names @("plan", "Plan")) "name") "a level name with a capital is refused, so case can never make two names one"
Check (HasProblem (LevelsText -Names @("plan", "a b")) "name") "a level name with a space is refused"
Check (HasProblem (LevelsText -Names @("plan", "")) "name") "an empty level name is refused"
Check (HasProblem (LevelsText -Names @("plan") -Extra ', "flag": "x"') "extra") "a row with a key beyond name and meaning is refused"
Check (HasProblem '{ "levels": [ { "name": "plan" } ] }' "meaning") "a row without a meaning is refused"
Check (HasProblem '{ "levels": [ { "name": "plan", "meaning": "   " } ] }' "meaning") "a blank meaning is refused"
Check (HasProblem '{ "levels": [ { "name": "plan", "meaning": "Runs with --skip-all set." } ] }' "flag") "a meaning that spells a long flag is refused"
Check (HasProblem '{ "levels": [ { "name": "plan", "meaning": "Runs with -y given." } ] }' "flag") "a meaning that spells a short flag is refused"
Check (@(Problems '{ "levels": [ { "name": "plan", "meaning": "Reads; a well-known, read-only level." } ] }').Count -eq 0) "control: a hyphen inside a word is not a flag"
Check (HasProblem '{ "levels": [ { "name": "plan", "meaning": "caf\u00e9" } ] }' "ASCII") "a meaning with a non-ASCII character is refused"
Check (HasProblem '{ "levels": [ { "name": 3, "meaning": "x" } ] }' "name") "a name that is not a string is refused"
Check (@(Problems ('{ "levels": [ { "name": "plan", "meaning": "' + ("m" * 200) + '" } ] }')).Count -eq 0) "control: a meaning of exactly 200 characters passes"
Check (HasProblem ('{ "levels": [ { "name": "plan", "meaning": "' + ("m" * 201) + '" } ] }') "longer") "a meaning of 201 characters is refused"
Check (HasProblem '{ "levels": [ "plan" ] }' "object") "a row that is not an object is refused"
Check (@(Problems (LevelsText -Names @("a" * 32))).Count -eq 0) "control: a level name of 32 characters passes"
Check (HasProblem (LevelsText -Names @("a" * 33)) "name") "a level name of 33 characters is refused"
Check (HasProblem (LevelsText -Names @("1plan")) "name") "a level name starting with a digit is refused"
Check (HasProblem (LevelsText -Names @("-plan")) "name") "a level name starting with a hyphen, which reads as a flag, is refused"
Check (HasProblem '{ "levels": [ { "name": "plan", "meaning": "Reads\tonly." } ] }' "ASCII") "a meaning holding a tab is refused: printable means no control character"
Check (HasProblem '{ "levels": [ { "name": "plan", "meaning": "Runs with (--skip-all) set." } ] }' "flag") "a flag in brackets is refused"
Check (HasProblem '{ "levels": [ { "name": "plan", "meaning": "Runs with \"--yolo\" given." } ] }' "flag") "a flag in quotes is refused"
Check (HasProblem '{ "levels": [ { "name": "plan", "meaning": "Runs with /y given." } ] }' "flag") "a slash flag is refused"
Check (@(Problems '{ "levels": [ { "name": "plan", "meaning": "Reads and/or proposes." } ] }').Count -eq 0) "control: a slash inside a word is not a flag"

Write-Host ""
Write-Host "--- a key written twice is refused, not read as its last copy ---" -ForegroundColor Cyan
$longKey = ('{ "levels": [ { "name": "plan", "meaning": "x", "' + ('k' * 300) + '": 1, "' + ('k' * 300) + '": 2 } ] }')
$longMsg = ""; try { $null = Read-HordePermissionLevelText -Text $longKey } catch { $longMsg = "$($_.Exception.Message)" }
Check ($longMsg -clike "*twice*" -and $longMsg.IndexOf(('k' * 41)) -lt 0 -and $longMsg.Length -lt 400) "a long repeated key is refused without being copied into the reason"
# ConvertFrom-Json in PowerShell 5.1 keeps the last of two equal keys and says nothing (review of this
# PR), so a reader would see one vocabulary and Horde would use another.
Check (Throws { Read-HordePermissionLevelText -Text '{ "levels": [ { "name": "plan", "meaning": "x" } ], "levels": [ { "name": "plan", "meaning": "x" }, { "name": "bypass", "meaning": "x" } ] }' } "twice") "a second levels key is refused"
Check (Throws { Read-HordePermissionLevelText -Text '{ "levels": [ { "name": "plan", "meaning": "x", "name": "bypass" } ] }' } "twice") "a row naming two levels is refused"
Check (Throws { Read-HordePermissionLevelText -Text '{ "levels": [ { "name": "plan", "meaning": "x", "\u006eame": "bypass" } ] }' } "twice") "a second key spelled with an escape is the same key, and refused"
Check ((Names @(Read-HordePermissionLevelText -Text '{ "levels": [ { "name": "plan", "meaning": "Says \"name\": x." }, { "name": "ask", "meaning": "y" } ] }')) -ceq "plan,ask") "control: the same key in two rows, and a key-like text inside a string, are not duplicates"
Check ((Names @(Read-HordePermissionLevelText -Text ([System.IO.File]::ReadAllText($realPath)))) -ceq "plan,ask,edits,bypass") "control: the file on disk has no duplicate key"

$badFile = Join-Path $env:TEMP ("horde-permlevels-" + [guid]::NewGuid().ToString("N") + ".json")
try {
    [System.IO.File]::WriteAllText($badFile, (LevelsText -Names @("plan", "plan")))
    Check (Throws { Get-HordePermissionLevels -Path $badFile } "twice") "loading a file with a duplicate level throws and says why"
    [System.IO.File]::WriteAllBytes($badFile, [byte[]](@([System.Text.Encoding]::ASCII.GetBytes('{ "levels": [ { "name": "plan", "meaning": "caf')) + @(0xC3, 0xA9) + @([System.Text.Encoding]::ASCII.GetBytes('" } ] }'))))
    Check (Throws { Get-HordePermissionLevels -Path $badFile } "ASCII") "loading a file holding a raw non-ASCII byte throws"
    [System.IO.File]::WriteAllBytes($badFile, [byte[]](@(0xEF, 0xBB, 0xBF) + @([System.Text.Encoding]::ASCII.GetBytes((LevelsText -Names @("plan"))))))
    Check (Throws { Get-HordePermissionLevels -Path $badFile } "byte-order mark") "loading a file that starts with a byte-order mark throws, and names the mark"
    [System.IO.File]::WriteAllText($badFile, (LevelsText -Names @("plan", "ask")))
    Check ((Names @(Get-HordePermissionLevels -Path $badFile)) -ceq "plan,ask") "control: a well-formed file at another path loads"
} finally { Remove-Item -LiteralPath $badFile -Force -ErrorAction SilentlyContinue }

Write-Host ""
Write-Host "--- a level's rank is a tristate answer ---" -ForegroundColor Cyan
$r = Get-HordePermissionLevelRank -Name "edits" -Levels $levels
Check ($r.state -ceq "known" -and $r.value -eq 2) "edits has rank 2"
$r0 = Get-HordePermissionLevelRank -Name "plan" -Levels $levels
Check ($r0.state -ceq "known" -and $r0.value -eq 0) "plan, the lowest level, is known with rank 0, not mistaken for nothing"
$hi = Get-HordePermissionLevelRank -Name "bypass" -Levels $levels
Check ($hi.state -ceq "known" -and $hi.value -gt $r.value) "bypass ranks above edits"
$un = Get-HordePermissionLevelRank -Name "root" -Levels $levels
Check ($un.state -ceq "unknown" -and $un.reason -clike "*'root'*" -and $un.reason -clike "*plan, ask, edits, bypass*") "a name outside the vocabulary is unknown, naming it and the vocabulary"
$case = Get-HordePermissionLevelRank -Name "Bypass" -Levels $levels
Check ($case.state -ceq "unknown") "a level is matched exactly: 'Bypass' is not bypass"
$pad = Get-HordePermissionLevelRank -Name " plan" -Levels $levels
Check ($pad.state -ceq "unknown") "a padded name is not trimmed into a match"
$none = Get-HordePermissionLevelRank -Name "" -Levels $levels
Check ($none.state -ceq "unknown") "an empty name is unknown, never the lowest level"
$nul = Get-HordePermissionLevelRank -Name $null -Levels $levels
Check ($nul.state -ceq "unknown") "no name at all is unknown"
# Under R9 the name comes from a remote request and the reason goes to logs.
$long = Get-HordePermissionLevelRank -Name ("x" * 100) -Levels $levels
Check ($long.state -ceq "unknown" -and $long.reason -cnotlike ("*" + ("x" * 41) + "*") -and $long.reason -clike "*100 characters*") "a long unknown name is described in the reason, not copied into it"
$ctl = Get-HordePermissionLevelRank -Name ("a" + [char]27 + "b") -Levels $levels
Check ($ctl.state -ceq "unknown" -and $ctl.reason.IndexOf([char]27) -lt 0) "an unknown name holding a control character is not copied into the reason"
# The rank is the row's position, never a field a row carries: a hand-built row with no rank once
# read as rank 0 (review of this PR).
$handBuilt = @([pscustomobject]@{ name = "plan" }, [pscustomobject]@{ name = "edits" })
$hb = Get-HordePermissionLevelRank -Name "edits" -Levels $handBuilt
Check ($hb.state -ceq "known" -and $hb.value -eq 1) "a level's rank is its position in the list given, not a rank field"

Write-Host ""
Write-Host "--- a request is allowed only at or below the ceiling (R9 gates spawn and drive with this) ---" -ForegroundColor Cyan
function Allowed { param($Req, $Cap) return (Test-HordePermissionLevelAllowed -Requested $Req -Ceiling $Cap -Levels $levels) }
$a = Allowed "edits" "edits"
Check ($a.state -ceq "known" -and $a.value -eq $true) "a request at the ceiling is allowed"
$a = Allowed "plan" "bypass"
Check ($a.state -ceq "known" -and $a.value -eq $true) "a request below the ceiling is allowed"
$a = Allowed "bypass" "edits"
Check ($a.state -ceq "known" -and $a.value -eq $false) "a request above the ceiling is refused, not lowered to it"
$a = Allowed "ask" "plan"
Check ($a.state -ceq "known" -and $a.value -eq $false) "a request one level above the ceiling is refused"
$a = Allowed "root" "bypass"
Check ($a.state -ceq "unknown" -and $a.reason -clike "*requested*'root'*") "an unknown request under the highest ceiling is unknown, never allowed"
$a = Allowed "plan" "Bypass"
Check ($a.state -ceq "unknown" -and $a.reason -clike "*ceiling*'Bypass'*") "a ceiling that is not a level is unknown, even for the lowest request"
$a = Allowed $null "bypass"
Check ($a.state -ceq "unknown") "no requested level is unknown, never the lowest"
$a = Allowed "plan" $null
Check ($a.state -ceq "unknown") "no ceiling is unknown, never the highest"

Write-Host ""
Write-Host "--- a descriptor's mapping must cover the vocabulary exactly once (engines E2) ---" -ForegroundColor Cyan
$fixture = [System.IO.File]::ReadAllText((Join-Path $root "test\fixtures\permission-levels\descriptor-maps-v1.json")) | ConvertFrom-Json
$mapped = @($fixture.permissionLevels | ForEach-Object { "$($_.level)" })
$cov = Test-HordePermissionLevelCoverage -Mapped $mapped -Levels $levels
Check ($cov.ok -eq $true) "the fixture descriptor written against today's vocabulary covers it"
$added = @(Read-HordePermissionLevelText -Text (LevelsText -Names (@($levels | ForEach-Object { $_.name }) + @("sandboxed"))))
$covAdded = Test-HordePermissionLevelCoverage -Mapped $mapped -Levels $added
Check ($covAdded.ok -eq $false -and @($covAdded.missing) -ccontains "sandboxed") "a level added to the vocabulary fails the old descriptor, naming the level it lacks"
$removed = @(Read-HordePermissionLevelText -Text (LevelsText -Names @("plan", "ask", "bypass")))
$covRemoved = Test-HordePermissionLevelCoverage -Mapped $mapped -Levels $removed
Check ($covRemoved.ok -eq $false -and @($covRemoved.unknown) -ccontains "edits") "a level removed from the vocabulary fails the old descriptor, naming the level it still maps"
$covDup = Test-HordePermissionLevelCoverage -Mapped (@($mapped) + @("ask")) -Levels $levels
Check ($covDup.ok -eq $false -and @($covDup.duplicate) -ccontains "ask") "a level mapped twice fails, naming it"
$covNone = Test-HordePermissionLevelCoverage -Mapped @() -Levels $levels
Check ($covNone.ok -eq $false -and @($covNone.missing).Count -eq $levels.Count) "a descriptor that maps nothing fails with every level missing"
$covPad = Test-HordePermissionLevelCoverage -Mapped @(" plan", "ask", "edits", "bypass") -Levels $levels
Check ($covPad.ok -eq $false -and @($covPad.missing) -ccontains "plan" -and @($covPad.unknown) -ccontains " plan") "a padded mapping covers nothing: ' plan' is not plan"
$covNull = Test-HordePermissionLevelCoverage -Mapped $null -Levels $levels
Check ($covNull.ok -eq $false -and @($covNull.missing).Count -eq $levels.Count -and @($covNull.unknown).Count -eq 0) "no mapping at all is every level missing, and no level '' unknown"
$covCase = Test-HordePermissionLevelCoverage -Mapped @("plan", "ask", "edits", "Bypass") -Levels $levels
Check ($covCase.ok -eq $false -and @($covCase.missing) -ccontains "bypass" -and @($covCase.unknown) -ccontains "Bypass") "a mapping is matched exactly: 'Bypass' covers nothing"

Complete-HordeSuite -Success "the permission-level vocabulary is closed, ordered and harness-free, and a change to it breaks a stale mapping"
