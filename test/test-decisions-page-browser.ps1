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
$chromeProfile = Join-Path $work "chrome"
New-Item -ItemType Directory -Path $chromeProfile -Force | Out-Null

Write-Host ""
Write-Host "--- the order line, tapped, in headless Chrome ---" -ForegroundColor Cyan
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $node.Source
$psi.Arguments = '"' + (Join-Path $root "decisions\page\test\browser-order.mjs") + '" "' + (Join-Path $root "decisions\page") + '" "' + $chrome + '" "' + $chromeProfile + '"'
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
    Check ($p.ExitCode -eq 0 -and $doneLine.Count -eq 1 -and $passes -ge 23) ("the browser's checks ran to their end (" + $passes + " passed; exit " + $p.ExitCode + "; " + $errTask.Result.Trim() + ")")
} finally { $p.Dispose() }

# Chrome is ended by the driver (taskkill of its tree); whatever is left of it under this profile is ended
# here, and the folder goes.
Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($chromeProfile) } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
for ($i = 0; $i -lt 20 -and (Test-Path -LiteralPath $work); $i++) {
    try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction Stop } catch { Start-Sleep -Milliseconds 250 }
}
Check (-not (Test-Path -LiteralPath $work)) "the suite's folder - Chrome's profile - is gone"

Complete-HordeSuite -Success "a tap re-sorts what he is looking at, a second tap turns the order over, and both are kept"
