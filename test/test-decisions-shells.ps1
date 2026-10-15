# DOES `horde decisions` WORK THE SAME UNDER POWERSHELL 7 AS UNDER WINDOWS POWERSHELL 5.1 - AND CAN EACH
# READ WHAT THE OTHER WROTE?
#
# Issue #274: under pwsh 7, `horde decisions add` on a fresh home was refused before anything was
# written - "it is not a decision-event.v1 record: $.at should be string" - while 5.1 added the same
# question. pwsh 7's ConvertFrom-Json reads a date-shaped string as a [datetime] (measured 2026-10-14 on
# 7.6.6), and the decisions module read its own new record back through it. Every other decisions
# suite runs under 5.1 only, so none of them could go red for this. This one runs the shipped horde.ps1
# as its own process (test/lib/Cli.ps1) under EACH shell, on a clean home it made:
#   - add, list, show, answer and close, each exiting 0 with the answer it promises;
#   - a date-shaped text a person typed (a group note, an outcome) comes back exactly as typed;
#   - every timestamp in the answers is text, as the store holds it;
#   - a store written by one shell is read whole by the other: nothing unreadable, nothing not understood.
# Without pwsh.exe the PowerShell 7 half is NOT RUN, said loudly, and the suite exits 3, never 0.
# It starts no pane and touches no terminal (CONTRIBUTING 2 and 3); HORDE_HOME is always a folder this
# suite made under TEMP, and the real store is checked untouched at the end.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")
# The suite reads the answers with its own parse, not core/JsonText's, so a fault in the code under
# test cannot also blind the reader: -DateKind String where this shell has it (7.5 and later), else
# the plain parse, which on 5.1 never makes a date.
$script:readDateKind = (Get-Command ConvertFrom-Json).Parameters.ContainsKey("DateKind")

$script:work = Join-Path $env:TEMP ("horde-decisions-shells-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
$isoText = '\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z\z'
# Typed by a person, shaped like a date: pwsh 7's parser would make it a [datetime], and "o" text of that
# would not be what was typed (no fraction here).
$typedDate = "2026-10-14T12:00:00Z"

function Get-RealStoreListing {
    # What the real store holds, WITHOUT touching it, read from the profile directly, not through
    # HORDE_HOME, which a gate may have set.
    $real = Join-Path (Join-Path (Join-Path "$env:USERPROFILE" ".horde") "store") "decisions"
    if (-not (Test-Path -LiteralPath $real)) { return "(no store)" }
    return (@(Get-ChildItem -LiteralPath $real -Force | Sort-Object Name | ForEach-Object { $_.Name + "|" + $_.Length + "|" + $_.LastWriteTimeUtc.Ticks }) -join ";")
}
$realBefore = Get-RealStoreListing

function New-TestHome {
    param([string]$Name)
    $h = Join-Path $script:work $Name
    New-Item -ItemType Directory -Path $h | Out-Null
    return $h
}

function Invoke-Decisions {
    # `horde decisions <args>` under -Shell, with HORDE_HOME at -HomeDir. Returns { code; out; json }:
    # json is the one -Json answer line, parsed with every string left a string, or $null.
    param([string]$Shell, [string]$HomeDir, [string[]]$HordeArgs)
    if ($HomeDir -notlike ($script:work + "*")) { throw ("refusing a home outside this suite's folder: " + $HomeDir) }
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs (@("decisions") + $HordeArgs) -Env @{ HORDE_HOME = $HomeDir } -Shell $Shell
    $line = @(@($r.out -split "\r?\n") | Where-Object { $_.StartsWith('{"state":') }) | Select-Object -First 1
    $j = $null
    if ($null -ne $line) { try { if ($script:readDateKind) { $j = $line | ConvertFrom-Json -DateKind String } else { $j = $line | ConvertFrom-Json } } catch { $j = $null } }
    return [pscustomobject]@{ code = $r.code; out = $r.out; json = $j }
}

function Show-Out { param($Run) if ($Run.code -ne 0) { Write-Host ("         " + "$($Run.out)".Trim()) -ForegroundColor Red } }

function Test-AllText {
    # Is every value of -Values a string matching the ISO text Horde writes? Exactly $true or $false.
    param($Values)
    $all = @($Values)
    if ($all.Count -eq 0) { return $false }
    foreach ($v in $all) { if ($v -isnot [string] -or $v -cnotmatch $isoText) { return $false } }
    return $true
}

$question = [ordered]@{ title = "Should the setup step run now"; kind = "yes-no"
    whatItIs = "A plain question used to check the decisions command under two shells"
    group = "Setup"; groupNote = $typedDate; askedBy = "me" }
$questionFile = Join-Path $script:work "question.json"
[System.IO.File]::WriteAllText($questionFile, (ConvertTo-Json -InputObject $question), $utf8)

$shells = New-Object System.Collections.ArrayList
[void]$shells.Add([pscustomobject]@{ name = "Windows PowerShell 5.1"; exe = "powershell.exe" })
$pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
$partial = $false
if ($null -eq $pwsh) {
    Write-Host ""
    Write-Host "  [NOT RUN] POWERSHELL 7 IS NOT ON THIS MACHINE (no pwsh.exe). The half of this suite that issue #274 is about was NOT RUN; only 5.1 was checked." -ForegroundColor Yellow
    $partial = $true
} else {
    [void]$shells.Add([pscustomobject]@{ name = "PowerShell 7"; exe = $pwsh.Source })
}

$homes = @{}
try {

foreach ($sh in $shells) {
    Write-Host ""
    Write-Host ("--- " + $sh.name + ": add, list, show, answer, close on a clean home ---") -ForegroundColor Cyan
    $h = New-TestHome ("home-" + ($sh.exe -replace '[^a-zA-Z0-9]', ''))
    $homes[$sh.name] = $h
    $n = $sh.name

    $add = Invoke-Decisions -Shell $sh.exe -HomeDir $h -HordeArgs @("add", "-File", $questionFile, "-Json")
    Check ($add.code -eq 0 -and (Get-HordeTestMember $add.json "value.outcome") -ceq "done" -and (Get-HordeTestMember $add.json "value.number") -eq 1) ($n + ": add exits 0 and says done, question 1 (exit " + $add.code + ")")
    Show-Out $add
    $record = Join-Path $h "store\decisions\0000000001.json"
    Check (Test-Path -LiteralPath $record) ($n + ": the record is in the store under this suite's home")

    $list = Invoke-Decisions -Shell $sh.exe -HomeDir $h -HordeArgs @("list", "-Json")
    $rows = @(Get-HordeTestMember $list.json "value.questions")
    Check ($list.code -eq 0 -and $rows.Count -eq 1 -and (Get-HordeTestMember $rows[0] "title") -ceq $question.title) ($n + ": list exits 0 and holds the one question")
    Check ((Get-HordeTestMember $rows[0] "groupNote") -ceq $typedDate) ($n + ": a date-shaped group note comes back exactly as typed")
    Show-Out $list

    $show = Invoke-Decisions -Shell $sh.exe -HomeDir $h -HordeArgs @("show", "1", "-Json")
    $q = Get-HordeTestMember $show.json "value.question"
    Check ($show.code -eq 0 -and (Get-HordeTestMember $q "number") -eq 1 -and (Get-HordeTestMember $q "state") -ceq "open") ($n + ": show 1 exits 0 with question 1 open")
    Check (Test-AllText (@(Get-HordeTestMember $q "addedAt") + @(@(Get-HordeTestMember $q "history") | ForEach-Object { Get-HordeTestMember $_ "at" }))) ($n + ": show's timestamps are the store's text, not dates")
    Show-Out $show

    $answer = Invoke-Decisions -Shell $sh.exe -HomeDir $h -HordeArgs @("answer", "1", "-Text", "yes", "-Json")
    Check ($answer.code -eq 0 -and (Get-HordeTestMember $answer.json "value.outcome") -ceq "done") ($n + ": answer 1 exits 0 and says done (exit " + $answer.code + ")")
    Show-Out $answer

    $close = Invoke-Decisions -Shell $sh.exe -HomeDir $h -HordeArgs @("close", "1", "-Outcome", $typedDate, "-Json")
    Check ($close.code -eq 0 -and (Get-HordeTestMember $close.json "value.outcome") -ceq "done") ($n + ": close 1 exits 0 and says done (exit " + $close.code + ")")
    Show-Out $close

    $all = Invoke-Decisions -Shell $sh.exe -HomeDir $h -HordeArgs @("list", "-State", "all", "-Json")
    $rows = @(Get-HordeTestMember $all.json "value.questions")
    Check ($all.code -eq 0 -and $rows.Count -eq 1 -and (Get-HordeTestMember $rows[0] "state") -ceq "closed") ($n + ": list -State all shows question 1 closed")
    Check ((Get-HordeTestMember $rows[0] "outcome") -ceq $typedDate) ($n + ": a date-shaped outcome comes back exactly as typed")
    Check ((Get-HordeTestMember $rows[0] "thread.count") -eq 1) ($n + ": the answer is kept in the question's conversation")
    Check (Test-AllText @((Get-HordeTestMember $rows[0] "closedAt"), (Get-HordeTestMember $rows[0] "updatedAt"))) ($n + ": closedAt and updatedAt are the store's text")
    Check (@(Get-HordeTestMember $all.json "value.unreadable").Count -eq 0 -and @(Get-HordeTestMember $all.json "value.notUnderstood").Count -eq 0 -and @(Get-HordeTestMember $all.json "value.ignored").Count -eq 0) ($n + ": nothing in the store is unreadable, ignored or not understood")
    Show-Out $all
}

if ($shells.Count -eq 2) {
    Write-Host ""
    Write-Host "--- each shell reads the store the other wrote ---" -ForegroundColor Cyan
    foreach ($pair in @(@($shells[0], $shells[1]), @($shells[1], $shells[0]))) {
        $writer = $pair[0]; $reader = $pair[1]
        $read = Invoke-Decisions -Shell $reader.exe -HomeDir $homes[$writer.name] -HordeArgs @("list", "-State", "all", "-Json")
        $rows = @(Get-HordeTestMember $read.json "value.questions")
        $what = $reader.name + " reads what " + $writer.name + " wrote"
        Check ($read.code -eq 0 -and $rows.Count -eq 1 -and (Get-HordeTestMember $rows[0] "state") -ceq "closed" -and (Get-HordeTestMember $rows[0] "outcome") -ceq $typedDate) ($what + ": question 1, closed, its outcome exactly as typed")
        Check (@(Get-HordeTestMember $read.json "value.unreadable").Count -eq 0 -and @(Get-HordeTestMember $read.json "value.notUnderstood").Count -eq 0 -and @(Get-HordeTestMember $read.json "value.ignored").Count -eq 0) ($what + ": nothing unreadable, ignored or not understood")
        Show-Out $read
    }
}

Write-Host ""
Write-Host "--- the real store ---" -ForegroundColor Cyan
Check ((Get-RealStoreListing) -ceq $realBefore) "the real decisions store is exactly as it was: every run used this suite's own home"

} finally {
    Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($partial) { Complete-HordeSuite -Success "decisions works under 5.1; under PowerShell 7 it was NOT RUN (no pwsh.exe)" -PassCode 3 }
Complete-HordeSuite -Success "decisions adds, lists, shows, answers and closes under both shells, and each reads what the other wrote"
