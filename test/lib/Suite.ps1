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

# READING A MEMBER THAT A MUTANT CAN DROP. Under Set-StrictMode, `$body.thrall.orcs` raises an error when
# any step of it is missing. Inside Check(...) that error makes the check vanish (above), and in a suite
# built as one top-level try the trap's `continue` resumes after the try, skipping every later check
# (issue 216). So a mutant that drops a member ended its suite with no failed check, and
# tools\Mutate.ps1 rightly reported "the suite broke" instead of a catch: three after-merge mutation
# nets in a row (PR 239's node-act, PR 259's notices, the cards channel) found suites doing exactly that.
#
# Read such a member through Get-HordeTestMember instead. It answers what a read WITHOUT strict mode
# would: the value, or $null when any step of the path is missing - so a check written against the
# plain read asserts exactly the same thing, and fails by its own name when the member is gone. It never
# raises an error. A list comes back the way any PowerShell function returns one (an empty list as
# nothing, one item as that item), so count a list with @(...) as usual. Test-HordeTestMember says
# whether the whole path is there, for a check whose rule is that the member exists, or to tell a
# member that is $null from one that is missing.
#
#   Check ((Get-HordeTestMember $b "thrall.orcs") -eq 3) "the Thrall's card counts three Orcs"
#   Check (Test-HordeTestMember $b "thrall.census") "the Thrall's card carries the census"
#
# A path is member names separated by dots. A step reads a property of an object, or a key of a
# dictionary (a hashtable); case is ignored, as PowerShell's own member access ignores it.

function Resolve-HordeTestMember {
    # { found; value } for -Path under -Object. Wrapped in an object so a list is not unrolled on the way.
    param($Object, [Parameter(Mandatory = $true)][string]$Path)
    $cur = $Object
    foreach ($step in ($Path -split '\.')) {
        if ($null -eq $cur -or $step -eq "") { return [pscustomobject]@{ found = $false; value = $null } }
        if ($cur -is [System.Collections.IDictionary]) {
            if (-not $cur.Contains($step)) { return [pscustomobject]@{ found = $false; value = $null } }
            $cur = $cur[$step]
            continue
        }
        $p = $cur.PSObject.Properties[$step]
        if ($null -eq $p) { return [pscustomobject]@{ found = $false; value = $null } }
        $cur = $p.Value
    }
    return [pscustomobject]@{ found = $true; value = $cur }
}

function Get-HordeTestMember {
    # The value at -Path under -Object, or $null when any step is missing. Never raises an error.
    param($Object, [Parameter(Mandatory = $true)][string]$Path)
    return (Resolve-HordeTestMember -Object $Object -Path $Path).value
}

function Test-HordeTestMember {
    # Is every step of -Path there under -Object? Exactly $true or $false; never raises an error.
    param($Object, [Parameter(Mandatory = $true)][string]$Path)
    return [bool](Resolve-HordeTestMember -Object $Object -Path $Path).found
}

# A FAKE PROFILE FOR A CHILD (T-0470). A suite that hands a child a USERPROFILE of its own makes that
# folder with New-HordeTestProfile, which also makes AppData\Local and AppData\Roaming inside it. Without
# them, Windows PowerShell 5.1 finds no local application data folder under USERPROFILE and gets "" for
# it, so a 5.1 child that lives about 20 s saves its module analysis cache as a RELATIVE path - into its
# working folder, which is often the repo root: Microsoft\Windows\PowerShell\ModuleAnalysisCache
# (T-0411, measured 2026-11-11; PowerShell 7 makes the folder itself and is not affected). A profile a
# test keeps empty or absent on purpose is not made here.

function New-HordeTestProfile {
    # Make -Path (and any missing parents) with AppData\Local and AppData\Roaming inside; return -Path.
    param([Parameter(Mandatory = $true)][string]$Path)
    foreach ($d in @($Path, (Join-Path $Path "AppData\Local"), (Join-Path $Path "AppData\Roaming"))) {
        [void][System.IO.Directory]::CreateDirectory($d)
    }
    return $Path
}

function Register-HordeSuiteError {
    # Called by the suite's trap line. Records an error no test expected, so the suite cannot pass.
    param($ErrorRecord)
    $where = ""
    if ($ErrorRecord.InvocationInfo) { $where = " (line " + $ErrorRecord.InvocationInfo.ScriptLineNumber + ")" }
    [void]$script:suiteErrors.Add("$ErrorRecord" + $where)
    Write-Host ("  [ERROR] an error no test expected" + $where + ": " + $ErrorRecord) -ForegroundColor Red
}

function Complete-HordeSuite {
    # End the suite: exit 1 if any check failed or any unexpected error was recorded, else exit
    # -PassCode (0 unless given). A suite that skipped part of itself on purpose passes with a code of
    # its own, so a gate that expects 0 fails loudly instead of reading a partial run as a whole one;
    # tools\Mutate.ps1 accepts it only from a spec that declares it (PassCodes).
    param([string]$Success = "every check passed", [ValidateRange(0, 255)][int]$PassCode = 0)
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
