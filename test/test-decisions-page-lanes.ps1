# IS EACH QUESTION ON THE RIGHT CARD, AND IS EACH CARD'S COUNT RIGHT - WITHOUT A PAGE?
#
# The founder's decision 74 (2026-10-14): on the decisions page, cards first - one per lane with its
# open-question count and a mark when one of its questions blocks all its work, and one for all of
# them. A question names no lane of its own (schema/decision-question.v1), so decisions/page/list.js
# reads it from who asked; this suite holds that reading and the cards' numbers under Node
# (decisions/page/test/lane-units.mjs): an Orc's lane (C, F1), the keeper's (M (Thrall), Thrall), a
# question that names nobody, the count of what is still to answer, the blocks mark, and a must-fail
# twin. What a real page counts as still to answer, and the cards drawn and tapped, are
# test/test-decisions-page-browser.ps1 (decisions/page/test/browser-cards.mjs).
#
# NEEDS Node. Without it the suite says so and exits 3, a partial run, never 0.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest

$node = Get-Command -Name "node" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $node) {
    Write-Host "  [SKIP] node is not installed here, so the lanes are not run" -ForegroundColor Yellow
    Complete-HordeSuite -Success "skipped: no node" -PassCode 3
}

Write-Host ""
Write-Host "--- the lanes and the cards' numbers, run ---" -ForegroundColor Cyan
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $node.Source
$psi.Arguments = '"' + (Join-Path $root "decisions\page\test\lane-units.mjs") + '" "' + (Join-Path $root "decisions\page\list.js") + '"'
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$p = [System.Diagnostics.Process]::Start($psi)
try {
    $errTask = $p.StandardError.ReadToEndAsync()
    $out = $p.StandardOutput.ReadToEnd()
    if (-not $p.WaitForExit(120000)) { $p.Kill() }
    $lines = @($out -split "`n" | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_ -ne "" })
    foreach ($l in $lines) {
        if ($l.StartsWith("[PASS] ")) { Check $true $l.Substring(7) }
        elseif ($l.StartsWith("[FAIL] ")) { Check $false $l.Substring(7) }
    }
    $passes = @($lines | Where-Object { $_.StartsWith("[PASS] ") }).Count
    $doneLine = @($lines | Where-Object { $_.StartsWith("[DONE] ") })
    # NO CLOSING LINE MEANS NOT RUN: a script that stopped half way printed some passes and no [DONE].
    Check ($p.ExitCode -eq 0 -and $doneLine.Count -eq 1 -and $passes -ge 11) ("the lanes' checks ran to their end (" + $passes + " passed; exit " + $p.ExitCode + "; " + $errTask.Result.Trim() + ")")
} finally { $p.Dispose() }

Complete-HordeSuite -Success "each question is on its lane's card, read from who asked, and each card counts what is still to answer"
