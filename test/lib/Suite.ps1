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
# WHY THE TRAP IS A LINE IN EACH SUITE AND NOT IN HERE: a trap belongs to the script block that
# declares it, so one declared in this dot-sourced file would not cover the suite's own statements.

$script:fails = New-Object System.Collections.ArrayList
$script:suiteErrors = New-Object System.Collections.ArrayList

function Check {
    param($Cond, [string]$What)
    if ($Cond -isnot [bool]) {
        Write-Host "  [FAIL] $What (the check's condition was not true or false)" -ForegroundColor Red
        [void]$script:fails.Add($What); return
    }
    if ($Cond) { Write-Host "  [PASS] $What" -ForegroundColor DarkGray }
    else { Write-Host "  [FAIL] $What" -ForegroundColor Red; [void]$script:fails.Add($What) }
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
    Write-Host ("  [FAIL] an error no test expected" + $where + ": " + $ErrorRecord) -ForegroundColor Red
}

function Complete-HordeSuite {
    # End the suite: exit 1 if any check failed or any unexpected error was recorded, else exit 0.
    param([string]$Success = "every check passed")
    Write-Host ""
    $n = $script:fails.Count + $script:suiteErrors.Count
    if ($n -gt 0) {
        Write-Host ("==== " + $n + " FAILURE(S) ====") -ForegroundColor Red
        foreach ($f in $script:fails) { Write-Host ("  - " + $f) -ForegroundColor Red }
        foreach ($e in $script:suiteErrors) { Write-Host ("  - unexpected error: " + $e) -ForegroundColor Red }
        exit 1
    }
    Write-Host ("==== " + $Success + " ====") -ForegroundColor Green
    exit 0
}
