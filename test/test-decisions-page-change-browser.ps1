# CAN THE FOUNDER CHANGE HIS ANSWER ON A PHONE - THE BUTTON, THE REOPENED BOX AND THE STATUS LINES - IN A REAL
# BROWSER? (T-0152; the founder on Q67, 2026-10-15: "On a phone it is easy to tap the wrong option.")
#
# The page is the window's and the phone's alike (decisions/page/list.js), so it is run here as shipped, in
# headless Chrome on a 412 px screen with touch, by decisions/page/test/browser-change.mjs, its buttons
# pressed by real touch events and its words typed as a keyboard types them:
#   1. THE BUTTON: on an answered question that is not closed, 44 px at least, and on no other.
#   2. THE STATUS LINES, in plain words and never silent: "answer changed - waiting for Orc F to confirm",
#      and what Orc F replied (not acted yet / undoing / cannot undo, with why); under a closed question
#      "This question is closed - Orc F has acted on it. To change course, ask a follow-up."
#   3. A TAP REOPENS THE BOX with his answer selected and the caret in it; what he sends is the ordinary
#      save; a refusal stays under his words; Keep my answer sends nothing.
# It is a suite of its own, beside test/test-decisions-page-browser.ps1 (the order, fold, cards and
# details drivers), so that its mutation spec (test/mutations/decisions-change-page.psd1) runs one driver
# a mutant, not five. The rules under it are test/test-decisions-change.ps1's.
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
    Complete-HordeSuite -Success "the founder can change his answer on a phone: the button on an answered, unclosed question only, the box reopened with his answer selected, the status lines in plain words, and a closed question says why there is none" -PassCode 3
}

$work = Join-Path $env:TEMP ("horde-decisions-change-browser-" + [guid]::NewGuid().ToString("N"))
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

Invoke-DecisionsBrowserDriver -Driver "browser-change.mjs" -Title "Change my answer, tapped and typed in" -Least 25

# The folder goes, with every profile in it.
for ($i = 0; $i -lt 20 -and (Test-Path -LiteralPath $work); $i++) {
    try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction Stop } catch { Start-Sleep -Milliseconds 250 }
}
Check (-not (Test-Path -LiteralPath $work)) "the suite's folder - Chrome's profile - is gone"

Complete-HordeSuite -Success "the founder can change his answer on a phone: the button on an answered, unclosed question only, the box reopened with his answer selected, the status lines in plain words, and a closed question says why there is none"
