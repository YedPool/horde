# DOES A TAP ON AN ORDER RE-SORT WHAT HE IS LOOKING AT, AND DOES A SECOND TAP TURN IT OVER - IN A REAL
# BROWSER, ON A PHONE-SIZED SCREEN?
#
# The founder, 2026-10-14: "On the decisions page the three sort orders sometimes don't work." and
# "Decisions page sorts should toggle between ascending and descending." The page is the window's and
# the phone's alike (decisions/page/list.js), so it is run here as shipped, in headless Chrome, by
# decisions/page/test/browser-order.mjs, its buttons pressed by real touch events:
#   1. THE CAUSE, MEASURED: on a list longer than the screen a tap re-sorted the list and then scrolled
#      the page after the question that had been at the top (879 px down, the order line gone), so the
#      screen showed the same question; on a short list it seemed to work. After a tap the head of the
#      new order is under the order line, which stays where it was - at the top, and scrolled a little.
#   2. THE ORDER TURNS OVER: the order in force pressed again runs the other way, a third press turns
#      it back, another order starts in its own first direction; the arrow (down, up) and the words a
#      screen reader is given say which way.
#   3. KEPT: through a list that arrives (the background refresh) and through opening the page again;
#      and a page whose storage throws still orders and turns, for as long as it is open.
# And by decisions/page/test/browser-fold.mjs (the founder, the same day: "I also want a collapse all
# button on the questions even though they should start expanded"):
#   4. THE QUESTIONS START UNFOLDED (folded where the host asks, as the window does); one tap on
#      Collapse all folds them all and the button says Expand all, a second unfolds them all; neither
#      touches the order or his place; what he folds or unfolds question by question is kept through a
#      list that arrives; an order chosen still sorts and turns.
# And by decisions/page/test/browser-cards.mjs (the founder's decision 74, the same day: cards first,
# one per lane with its open count and a mark when one blocks all its work, and All questions):
#   5. THE CARDS on the phone's page as app.js puts it together: what is counted (answered, closed,
#      parts, follow-ups, no askedBy) with a must-fail twin; the mark in words and a sign; a tap shows
#      that lane's questions, All shows everything; a background refresh keeps the card and what is
#      folded; sorting inside a card; the card kept on this device; the lanes document's own cards.
# And by decisions/page/test/browser-details.mjs (the founder, 2026-10-15: "Clicking on a decision to get
# more info now seems to have two stages of info showing" and "the input box ... needs to be more clearly
# delineated"):
#   6. ONE TAP on a folded question shows every detail, whole, in one run that ends with the label and
#      the box, and nothing is left to press for more; THE BOX has an edge of 4.5 to 1 or more in light
#      and dark, a label tied to its field, three lines at least on a phone, grows with the words up to
#      twelve, a ring with the caret in it, and a Send key inside its edge that sends and keeps the caret.
#   7. THE ANSWERED ARE HIDDEN UNTIL ASKED FOR (the same day: "By default you need to not show questions
#      that are answered - should be toggleable on top across from the sort by"): hidden by default; a
#      switch across from Collapse all, its state in words, shows With Thrall and History; it keeps the
#      order, the folds and his place; it is kept through opening again; an answered question leaves
#      with nothing jumping.
# The drivers share decisions/page/test/browser-harness.mjs, and run one after the other.
# The sorting itself, case by case, is test/test-decisions-page-order.ps1; the window, driven by its
# probe, is test/e2e/e2e-decisions-order.ps1.
#
# Chrome runs --headless=new: no window is ever shown. Its profile is a folder this suite makes and
# removes; nothing of the owner's is read or written.
# NEEDS Chrome and Node. Without either the suite says so and exits 3, a partial run, never 0.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest

$node = Get-Command -Name "node" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$chrome = @(
    (Join-Path ${env:ProgramFiles} "Google\Chrome\Application\chrome.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe"),
    (Join-Path ${env:LOCALAPPDATA} "Google\Chrome\Application\chrome.exe")
) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
if ($null -eq $node -or $null -eq $chrome) {
    Write-Host ("  [SKIP] " + $(if ($null -eq $node) { "node" } else { "Chrome" }) + " is not installed here, so the page is not run in a browser") -ForegroundColor Yellow
    Complete-HordeSuite -Success "skipped: no node or no Chrome" -PassCode 3
}

$work = Join-Path $env:TEMP ("horde-decisions-browser-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work -Force | Out-Null

# One driver, run to its end: each of its lines a check, and its closing line checked. Each driver has
# a Chrome profile of its own under the suite's folder; they run one after the other, never together.
function Invoke-DecisionsBrowserDriver {
    param([string]$Driver, [string]$Title, [int]$Least)
    $chromeProfile = Join-Path $work ([System.IO.Path]::GetFileNameWithoutExtension($Driver))
    New-Item -ItemType Directory -Path $chromeProfile -Force | Out-Null
    Write-Host ""
    Write-Host ("--- " + $Title + ", in headless Chrome ---") -ForegroundColor Cyan
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $node.Source
    $psi.Arguments = '"' + (Join-Path $root ("decisions\page\test\" + $Driver)) + '" "' + (Join-Path $root "decisions\page") + '" "' + $chrome + '" "' + $chromeProfile + '"'
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
        # NO CLOSING LINE MEANS NOT RUN: a driver that stopped half way printed some passes and no [DONE].
        Check ($p.ExitCode -eq 0 -and $doneLine.Count -eq 1 -and $passes -ge $Least) ($Driver + ": the browser's checks ran to their end (" + $passes + " passed; exit " + $p.ExitCode + "; " + $errTask.Result.Trim() + ")")
    } finally { $p.Dispose() }
    # Chrome is ended by the driver (taskkill of its tree); whatever is left of it under this profile is
    # ended here, before the next driver starts its own.
    Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($chromeProfile) } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

Invoke-DecisionsBrowserDriver -Driver "browser-order.mjs" -Title "the order line, tapped" -Least 24
Invoke-DecisionsBrowserDriver -Driver "browser-fold.mjs" -Title "Collapse all and Expand all, tapped" -Least 19
Invoke-DecisionsBrowserDriver -Driver "browser-cards.mjs" -Title "the cards, tapped" -Least 21
Invoke-DecisionsBrowserDriver -Driver "browser-details.mjs" -Title "one tap shows a question whole; the answer box, tapped and typed in" -Least 35

# The folder goes, with every profile in it.
for ($i = 0; $i -lt 20 -and (Test-Path -LiteralPath $work); $i++) {
    try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction Stop } catch { Start-Sleep -Milliseconds 250 }
}
Check (-not (Test-Path -LiteralPath $work)) "the suite's folder - Chrome's profile - is gone"

Complete-HordeSuite -Success "a tap re-sorts what he is looking at, a second tap turns the order over, and both are kept; the questions start unfolded and one button folds or unfolds them all, keeping the order and his place; one tap shows a question whole, and its answer box is plain to see"
