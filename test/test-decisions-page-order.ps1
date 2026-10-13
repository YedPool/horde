# IS THE FOUNDER'S LIST IN THE ORDER HE CHOSE - BY ONE SORTING, WHATEVER SHOWS IT?
#
# The founder, 2026-10-12: new questions at the top; an order-by for date (latest first), overall task
# importance, and how much the question blocks its task. The window and the phone draw the same
# document (decisions/page/list.js), so one function sorts for both, and this suite holds it:
#   1. THE SORTING, run without a page (decisions/page/test/order-units.mjs under Node): each order,
#      its ties, a question that states neither word, a word of a later version, a list from before
#      the words existed, and one answer whatever order the list is handed in.
#   2. THE WORDS THE PAGE SORTS BY ARE THE RULES' OWN. A page cannot ask decisions/Rules.ps1, so
#      list.js writes the two lists and their defaults down again; they are compared here, word for
#      word and in order, so that the keeper cannot be told "high" sorts first while the page sorts
#      it last.
# What the page DRAWS - the line where he chooses, the order of the lines, the order kept for the
# next time - is test/e2e/e2e-decisions-order.ps1, in a real window.
#
# Node runs part 1. Where there is none the suite says so and passes as PARTIAL (exit 3): part 2 ran.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "decisions\Rules.ps1")

$listPath = Join-Path $root "decisions\page\list.js"
$list = [System.IO.File]::ReadAllText($listPath)
$partial = $false

Write-Host ""
Write-Host "--- the words the page sorts by are the rules' own ---" -ForegroundColor Cyan
function Get-PageList {
    # The words of one array the page script declares, `var <Name> = ["a", "b"];`, or a marker when
    # the line is not there exactly once.
    param([string]$Name)
    $found = [regex]::Matches($list, '(?m)^\s*var ' + [regex]::Escape($Name) + ' = \[([^\]]*)\];')
    if ($found.Count -ne 1) { return ("(declared " + $found.Count + " times)") }
    return (@([regex]::Matches($found[0].Groups[1].Value, '"([^"]*)"') | ForEach-Object { $_.Groups[1].Value }) -join ",")
}
function Get-PageWord {
    param([string]$Name)
    $found = [regex]::Matches($list, '(?m)^\s*var ' + [regex]::Escape($Name) + ' = "([^"]*)";')
    if ($found.Count -ne 1) { return ("(declared " + $found.Count + " times)") }
    return $found[0].Groups[1].Value
}
Check ((Get-PageList "IMPORTANCES") -ceq ((Get-HordeDecisionImportances) -join ",")) ("the page's importances are the rules', in the rules' order (" + (Get-PageList "IMPORTANCES") + ")")
Check ((Get-PageList "BLOCKINGS") -ceq ((Get-HordeDecisionBlockings) -join ",")) ("the page's blockings are the rules', in the rules' order (" + (Get-PageList "BLOCKINGS") + ")")
Check ((Get-PageWord "DEFAULT_IMPORTANCE") -ceq (Get-HordeDecisionDefaultImportance) -and (Get-PageWord "DEFAULT_BLOCKS") -ceq (Get-HordeDecisionDefaultBlocks)) ("and a question that states neither reads on the page as it does in the rules (" + (Get-PageWord "DEFAULT_IMPORTANCE") + ", " + (Get-PageWord "DEFAULT_BLOCKS") + ")")
Check ((Get-PageList "NO_SUCH_LIST") -ceq "(declared 0 times)" -and (Get-PageWord "DEFAULT_ORDER") -ceq "date") "CONTROL: a list the page does not declare is reported as that; and the order he gets until he chooses is by date"

Write-Host ""
Write-Host "--- the sorting, run ---" -ForegroundColor Cyan
$node = Get-Command -Name "node" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $node) {
    Write-Host "  [SKIP] node is not installed here, so the sorting is not run" -ForegroundColor Yellow
    $partial = $true
} else {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $node.Source
    $psi.Arguments = '"' + (Join-Path $root "decisions\page\test\order-units.mjs") + '" "' + $listPath + '"'
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
        Check ($p.ExitCode -eq 0 -and $doneLine.Count -eq 1 -and $passes -ge 25) ("the sorting's checks ran to their end (" + $passes + " passed; exit " + $p.ExitCode + "; " + $errTask.Result.Trim() + ")")
    } finally { $p.Dispose() }
}

if ($partial) { Complete-HordeSuite -Success "the page sorts by the rules' own words; the sorting itself was not run (no node)" -PassCode 3 }
Complete-HordeSuite -Success "the list is sorted by one function, by the rules' own words, to one answer whatever order it is handed in"
