# DOES A JUMP TO THE LATEST MESSAGE STOP BELOW THE STICKY BAR - IN A REAL BROWSER, AT DESKTOP WIDTH, PHONE
# WIDTH AND 200 PERCENT ZOOM?
#
# The founder, 2026-10-20, on his desktop browser: "When horde jumps to the latest question, it jumps a little
# too far and I can't see the question - it's blocked by the decisions button." The phone app (surfaces/pwa/page)
# is run as shipped in headless Chrome by decisions/page/test/browser-bar.mjs, through browser-harness.mjs's
# /bar.html - its own bar, list and chat boxes cut out of index.html:
#   1. the newest message taller than the screen: after Jump to latest its top is at or below the bar's bottom
#      and above the composer; one that fits stands whole between the two;
#   2. the bar grown (the PC-offline line wraps): --bar-h follows its real height and the jump still clears it;
#   3. a question brought to the top of the view by the browser stands below the bar;
#   at 1400 by 900, at 390 by 844, and at 200 percent zoom.
# The rule itself is surfaces/pwa/page/chat-scroll.js; the bar's height is bar-height.js; the margin is app.css.
# Mutations: test\mutations\pwa-bar-offset.psd1.
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

$work = Join-Path $env:TEMP ("horde-bar-offset-browser-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work -Force | Out-Null

# One driver, run to its end: each of its lines a check, and its closing line checked. Each driver has
# a Chrome profile of its own under the suite's folder; they run one after the other, never together.
function Invoke-BarOffsetBrowserDriver {
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

Invoke-BarOffsetBrowserDriver -Driver "browser-bar.mjs" -Title "the jump to the latest message, below the sticky bar" -Least 45

# The folder goes, with every profile in it.
for ($i = 0; $i -lt 20 -and (Test-Path -LiteralPath $work); $i++) {
    try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction Stop } catch { Start-Sleep -Milliseconds 250 }
}
Check (-not (Test-Path -LiteralPath $work)) "the suite's folder - Chrome's profile - is gone"

Complete-HordeSuite -Success "a jump to the latest message stops below the sticky bar at desktop width, phone width and 200 percent zoom, and follows a bar that grows"
