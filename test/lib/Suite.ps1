# test/lib/Suite.ps1 - the one definition of how a Horde test suite checks things and how it ends.
#
# Every suite dot-sources this file, puts ONE trap line at its own top level, and ends by calling
# Complete-HordeSuite:
#
#   . (Join-Path $root "test\lib\Suite.ps1")
#   trap { Register-HordeSuiteError $_; continue }
#   ...checks...
#   Complete-HordeSuite -Success "what passing proves"
#
# WHY ONE FILE. Each suite used to carry its own copy of these helpers, and each copy had to learn the
# same lessons separately:
#   - A CHECK'S CONDITION MUST BE EXACTLY TRUE OR FALSE. A Throws helper returned its block's output
#     alongside $false; PowerShell reads that array as true, so a "must be refused" check passed when
#     nothing was refused. And `-like` on a list returns the matching items, not a boolean.
#   - A CHECK MUST NOT VANISH. When the expression inside Check(...) raises an error - under strict
#     mode, reading a property that is not there - PowerShell stops that one statement and carries on:
#     the check prints neither PASS nor FAIL, and the suite still exits 0. A review of core/tristate
#     measured a broken module passing that way. The trap line records every such error, and
#     Complete-HordeSuite fails the suite for it. (Measured 2026-09-29: the trap sees errors raised
#     inside functions too, and does not see errors a test catches on purpose.)
#
#   - AN ERROR THAT DOES NOT STOP ANYTHING STILL COUNTS. With the default preference, a cmdlet that
#     cannot find a path writes an error and carries on, and a check built on its empty result
#     passed. This file sets $ErrorActionPreference = "Stop" for the suite that dot-sources it, so
#     such an error reaches the trap. A test that expects an error says so, with -ErrorAction or a
#     try/catch.
#
# WHY THE TRAP IS A LINE IN EACH SUITE AND NOT IN HERE: a trap belongs to the script block that
# declares it, so one declared in this dot-sourced file would not cover the suite's own statements.
# And this file is loaded FIRST, before anything else a suite loads, so an error while loading the
# code under test is recorded like any other.
#
# WHAT THE TRAP'S `continue` DOES TO CONTROL FLOW, measured by the review of this file: after an
# unexpected error, execution resumes at the next statement of the SCRIPT, so the rest of a function
# that raised it is abandoned, and so are the remaining passes of a top-level loop. The suite still
# fails - the error is recorded - but code that must run anyway, such as stopping processes a test
# started, has to sit in its own try/finally.
#
# [ERROR], NOT [FAIL]. An unexpected error is printed as [ERROR]. tools/Mutate.ps1 counts a mutant as
# caught only when a CHECK failed ([FAIL]); a suite that merely crashed did not catch anything.

$ErrorActionPreference = "Stop"
$script:fails = New-Object System.Collections.ArrayList
$script:suiteErrors = New-Object System.Collections.ArrayList
# Sections (Register-HordeSuiteSections below). Named apart from the section variables two suites
# still keep of their own (test-engine-config, test-projection), so loading this file never resets them.
$script:HordeSuiteSectionIds = $null
$script:HordeSuiteSectionsWanted = @()
$script:HordeSuiteSectionsEntered = New-Object System.Collections.ArrayList
$script:HordeSuiteSectionsSkipped = New-Object System.Collections.ArrayList

function Check {
    param($Cond, [string]$What)
    if ($Cond -isnot [bool]) {
        Write-Host "  [FAIL] $What (the check's condition was not true or false)" -ForegroundColor Red
        [void]$script:fails.Add($What); return
    }
    if ($Cond) { Write-Host "  [PASS] $What" -ForegroundColor DarkGray }
    else {
        Write-Host "  [FAIL] $What" -ForegroundColor Red; [void]$script:fails.Add($What)
        # FAIL FAST, for mutation runs only: a mutant is caught at its first failed check, and the rest
        # of a slow suite proves nothing more about it. Set by a spec's Environment (second review of
        # PR #31, finding 9); an ordinary run reports every check.
        if ($env:HORDE_FAIL_FAST -eq "1") { Write-Host "  [FAIL-FAST] stopping at the first failed check (HORDE_FAIL_FAST=1)" -ForegroundColor Red; exit 1 }
    }
}

function Throws {
    # Does the block throw, with a message containing Like? The block's own output is discarded, so it
    # can never be mistaken for the answer.
    param([scriptblock]$Block, [string]$Like = "")
    try { $null = & $Block; return $false } catch { return ("$($_.Exception.Message)" -like "*$Like*") }
}

function Register-HordeSuiteError {
    # Called by the suite's trap line. Records an error no test expected, so the suite cannot pass.
    param($ErrorRecord)
    $where = ""
    if ($ErrorRecord.InvocationInfo) { $where = " (line " + $ErrorRecord.InvocationInfo.ScriptLineNumber + ")" }
    [void]$script:suiteErrors.Add("$ErrorRecord" + $where)
    Write-Host ("  [ERROR] an error no test expected" + $where + ": " + $ErrorRecord) -ForegroundColor Red
}

function Add-HordeSuiteProblem {
    # Record a problem that is not a failed check: printed as [ERROR], and the suite cannot pass.
    param([string]$Text)
    [void]$script:suiteErrors.Add($Text)
    Write-Host ("  [ERROR] " + $Text) -ForegroundColor Red
}

# SECTIONS, FOR MUTATION RUNS (issues #82 and #83). A mutant of one rule is caught by the one part of a
# suite that checks that rule, yet every mutant reran the whole suite: link-contract.psd1 took about
# 2900 s on the always-on box. A suite that names its parts lets a mutation spec map each mutant to the
# sections that kill it, and tools\Mutate.ps1 runs only those (it reruns the whole suite before it
# reports a survivor, so a wrong map costs time, never a verdict). A suite declares its sections once,
# as ONE LITERAL LIST - test\lib\SuiteSections.ps1 reads it from the text to check every map - and
# guards each part:
#
#   Register-HordeSuiteSections -Ids @("controls", "rows")
#   if (Enter-HordeSuiteSection "controls" "the real contract is valid") {
#       trap { Register-HordeSuiteError $_; continue }
#       ...checks...
#   }
#
# EVERY SECTION CARRIES THE TRAP LINE TOO. After an unexpected error the suite's own trap resumes at
# the next statement of the SCRIPT, and a whole section is one statement: every check after the error
# in that section would be skipped, so a mutant that throws first and fails a check later read as a
# suite that broke, not a catch (measured on test-link-protocol's version section, 2026-10-07). A trap
# inside the section resumes at the next statement of the section, as the suite's does at top level
# (measured). test\test-suite.ps1 fails a section without one (test\lib\SuiteSections.ps1).
#
# HORDE_SECTIONS=<id,id> selects. The rules, each because the opposite would let a run lie:
#   - A run that skipped any section exits 3, never 0, so no gate reads a part as the whole.
#   - A selected name the suite does not declare is an [ERROR], never a [FAIL]: tools\Mutate.ps1
#     counts a mutant caught only from a [FAIL], so a typo in a map cannot read as a catch.
#   - A selection that names nothing is an error, not "every section".
#   - The selection is read once and removed from the environment, so nothing the suite starts sees it.
#   - A declared section the suite never enters, or one entered that was never declared, fails the
#     suite: the list a map is checked against is the list that runs.
function Register-HordeSuiteSections {
    param([string[]]$Ids)
    if ($null -ne $script:HordeSuiteSectionIds) { Add-HordeSuiteProblem "the suite declares its sections more than once"; return }
    $seen = @{}
    foreach ($id in @($Ids)) {
        if ("$id" -cnotmatch '^[a-z0-9][a-z0-9-]*\z') { Add-HordeSuiteProblem ("section id '" + $id + "' is not lowercase letters, digits and hyphens") }
        elseif ($seen.ContainsKey("$id")) { Add-HordeSuiteProblem ("section id '" + $id + "' is declared twice") }
        $seen["$id"] = $true
    }
    $script:HordeSuiteSectionIds = @($Ids | ForEach-Object { "$_" })
    $raw = "$env:HORDE_SECTIONS"
    # The selection is this suite's alone: a suite or tool it starts would inherit it and read it as its
    # own - and a child suite given a name it does not have fails, which its parent's check would print
    # as a [FAIL], a catch (review of #115, B2). So it leaves this process once read.
    [System.Environment]::SetEnvironmentVariable("HORDE_SECTIONS", $null, "Process")
    if ($raw -eq "") { return }
    $script:HordeSuiteSectionsWanted = @($raw -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
    if ($script:HordeSuiteSectionsWanted.Count -eq 0) { Add-HordeSuiteProblem ("HORDE_SECTIONS names no section ('" + $raw + "')"); return }
    foreach ($u in @($script:HordeSuiteSectionsWanted | Where-Object { $script:HordeSuiteSectionIds -cnotcontains $_ })) {
        Add-HordeSuiteProblem ("HORDE_SECTIONS names " + $u + ", which is not a section of this suite")
    }
}

function Enter-HordeSuiteSection {
    # Print the section's header; return whether it runs.
    param([string]$Id, [string]$Title)
    if ($script:HordeSuiteSectionIds -cnotcontains $Id) { Add-HordeSuiteProblem ("section " + $Id + " is not declared by Register-HordeSuiteSections"); return $false }
    if ($script:HordeSuiteSectionsEntered -ccontains $Id) { Add-HordeSuiteProblem ("section " + $Id + " is entered twice") }
    [void]$script:HordeSuiteSectionsEntered.Add($Id)
    Write-Host ""
    Write-Host ("--- " + $Title + " ---") -ForegroundColor Cyan
    if ($script:HordeSuiteSectionsWanted.Count -eq 0 -or $script:HordeSuiteSectionsWanted -ccontains $Id) { return $true }
    [void]$script:HordeSuiteSectionsSkipped.Add($Id)
    Write-Host ("  [SKIP] section " + $Id + " was not selected") -ForegroundColor Yellow
    return $false
}

function Complete-HordeSuite {
    # End the suite: exit 1 if any check failed or any unexpected error was recorded, else exit
    # -PassCode (0 unless given). A suite that skipped part of itself on purpose passes with a code of
    # its own, so a gate that expects 0 fails loudly instead of reading a partial run as a whole one;
    # tools\Mutate.ps1 accepts it only from a spec that declares it (PassCodes).
    param([string]$Success = "every check passed", [ValidateRange(0, 255)][int]$PassCode = 0)
    if ($null -ne $script:HordeSuiteSectionIds) {
        foreach ($id in @($script:HordeSuiteSectionIds | Where-Object { $script:HordeSuiteSectionsEntered -cnotcontains $_ })) {
            Add-HordeSuiteProblem ("section " + $id + " is declared but was never entered")
        }
        # A run that skipped a section passed only part of the suite (SECTIONS above).
        if ($script:HordeSuiteSectionsSkipped.Count -gt 0 -and $PassCode -eq 0) {
            $PassCode = 3
            $Success = $Success + " (sections run: " + ($script:HordeSuiteSectionsWanted -join ",") + "; skipped: " + ($script:HordeSuiteSectionsSkipped -join ",") + ")"
        }
    }
    Write-Host ""
    $n = $script:fails.Count + $script:suiteErrors.Count
    if ($n -gt 0) {
        Write-Host ("==== " + $n + " FAILURE(S) ====") -ForegroundColor Red
        foreach ($f in $script:fails) { Write-Host ("  - " + $f) -ForegroundColor Red }
        foreach ($e in $script:suiteErrors) { Write-Host ("  - unexpected error: " + $e) -ForegroundColor Red }
        exit 1
    }
    Write-Host ("==== " + $Success + " ====") -ForegroundColor Green
    exit $PassCode
}
