# ONE RUN OF A BROWSER SUITE, CUT SHORT ONE WAY, for test/test-browser-cleanup.ps1. Shaped as the real
# suites are (relays/cloudflare/test/test-cloudflare-accounts.ps1, surfaces/pwa/test/test-pwa-browser.ps1):
# the browser started through -Launcher inside a try, a node driver reaching it, and the launcher's
# cleanup in the finally. -Mode says how the run ends:
#   pass           the driver finishes (its input closed) and the run ends normally;
#   throw          an error thrown mid-suite;
#   timeout        the driver does not finish in time: the run kills it, as Invoke-HordeCloudflareRelayNode
#                  does on its timeout, and fails;
#   driver-killed  the run waits on its driver, and the TEST kills the driver;
#   wait           the run waits for ever: the test stops it (Ctrl+C) or kills this process.
# Every step is appended to -Log as one line, for the test to read: PROFILE <path>, DRIVER <pid>, READY,
# STOPPED <what the cleanup said>.
#
# THE DRIVER. With test/lib/Browser.ps1 the driver is a node process apart from the browser
# (hold.mjs). A launcher whose handle carries a .driver - the shape before 2026-10-14, where the node
# driver itself spawned the browser - has that process used as the driver, so the same run measures it.
param([Parameter(Mandatory = $true)][string]$Launcher, [Parameter(Mandatory = $true)][string]$Mode, [Parameter(Mandatory = $true)][string]$Chrome,
    [Parameter(Mandatory = $true)][string]$Parent, [Parameter(Mandatory = $true)][string]$Node, [Parameter(Mandatory = $true)][string]$Log)
$ErrorActionPreference = "Stop"
. $Launcher
function Write-Step { param([string]$Line) [System.IO.File]::AppendAllText($Log, $Line + "`r`n", [System.Text.Encoding]::ASCII) }

$browser = $null
$drv = $null
try {
    $browser = Start-HordeTestBrowser -Chrome $Chrome -Parent $Parent
    Write-Step ("PROFILE " + $browser.profile)
    if ($null -ne $browser.PSObject.Properties["driver"]) { $drv = $browser.driver }
    else {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Node
        $psi.Arguments = '"' + (Join-Path $PSScriptRoot "hold.mjs") + '" ' + $browser.port
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $drv = [System.Diagnostics.Process]::Start($psi)
        $said = $drv.StandardOutput.ReadLineAsync()
        if (-not $said.Wait(20000) -or $said.Result -cne "CONNECTED") { throw "the stand-in driver did not reach the browser" }
    }
    Write-Step ("DRIVER " + $drv.Id)
    Write-Step "READY"
    switch ($Mode) {
        "pass" { $drv.StandardInput.BaseStream.Close(); if (-not $drv.WaitForExit(20000)) { throw "the driver did not finish" } }
        "throw" { throw "a failure in the middle of the suite" }
        "timeout" { if (-not $drv.WaitForExit(2000)) { $drv.Kill(); $null = $drv.WaitForExit(10000); throw "the driver timed out and was killed" } }
        "driver-killed" { if ($drv.WaitForExit(60000)) { throw "the driver ended before its work was done" } }
        "wait" { Start-Sleep -Seconds 600 }
        default { throw ("no such mode: " + $Mode) }
    }
} finally {
    if ($null -ne $drv) { try { if (-not $drv.HasExited) { $drv.StandardInput.BaseStream.Close(); if (-not $drv.WaitForExit(10000)) { $drv.Kill() } } } catch { } }
    $end = Stop-HordeTestBrowser -Browser $browser
    Write-Step ("STOPPED " + $end.said)
}
