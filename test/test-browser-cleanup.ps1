# DOES A SUITE'S HEADLESS BROWSER - EVERY PROCESS OF IT - END, AND ITS PROFILE GO, HOWEVER THE SUITE ENDS?
#
# test/lib/Browser.ps1 is the one launcher the browser suites use (relays/cloudflare/test/
# test-cloudflare-accounts.ps1, surfaces/pwa/test/test-pwa-browser.ps1). Before it, each node driver
# spawned Chrome itself, and on 2026-10-14 four headless browsers (about 0.4 GB each) were found running
# with no suite, and 130 horde-cf-accounts-* folders in %TEMP% (the launcher's header has why).
#
# Each run below is test/fixtures/browser-cleanup/scenario.ps1 - a suite's shape: the browser started
# through the launcher in a try, a node driver reaching it, the launcher's cleanup in the finally - cut
# short one way. After each, measured from OUTSIDE the launcher: no process is left with that run's
# profile as its --user-data-dir (by command line, not the launcher's own count), and the profile
# folder is gone.
#   pass, a throw mid-suite, the driver timed out and killed, the driver killed from outside: a child
#   PowerShell, as a gate runs a suite;
#   Ctrl+C: the run in a runspace of this process, stopped - the same pipeline stop the console's Ctrl+C
#   makes, which runs finally blocks;
#   the suite itself killed: the child PowerShell killed. No code of it runs, so only the browser is
#   asserted ended (the job closes with the process); its profile is said, and removed by this test.
# CONTROLS: while each run is up, the same command-line instrument finds its browser's processes (more
# than one: the browser's own children), so "none left" is a measurement and not a blind spot.
#
# NEEDS Chrome and node. Without either the suite says so and exits 3. One browser at a time.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
$launcher = Join-Path $root "test\lib\Browser.ps1"
. $launcher
Set-StrictMode -Version Latest

$chrome = Find-HordeTestChrome
$nodeCmd = @(Get-Command -Name "node" -CommandType Application -ErrorAction SilentlyContinue)
if ($chrome -eq "" -or $nodeCmd.Count -eq 0) {
    Write-Host ("  [SKIP] " + $(if ($chrome -eq "") { "Chrome" } else { "node" }) + " is not installed here, so no browser is started") -ForegroundColor Yellow
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Complete-HordeSuite -Success "skipped: no Chrome or no node" -PassCode 3
}
$node = "" + $nodeCmd[0].Source
$scenario = Join-Path $root "test\fixtures\browser-cleanup\scenario.ps1"
$shell = (Get-Process -Id $PID).Path
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-browser-cleanup-" + [guid]::NewGuid().ToString("N"))
[void][System.IO.Directory]::CreateDirectory($work)
$script:profilesSeen = New-Object System.Collections.ArrayList

function Read-Steps {
    param([string]$Log)
    if (-not (Test-Path -LiteralPath $Log)) { return @() }
    try { return @([System.IO.File]::ReadAllLines($Log)) } catch { return @() }
}
function Get-Step {
    # The value after "<Name> " in the run's log, or "".
    param([string]$Log, [string]$Name)
    $l = @(Read-Steps -Log $Log | Where-Object { $_.StartsWith($Name + " ") }) | Select-Object -First 1
    if ($null -eq $l) { return "" }
    return $l.Substring($Name.Length + 1)
}
function Wait-Step {
    param([string]$Log, [string]$Name, [int]$Seconds = 40)
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    while ($clock.Elapsed.TotalSeconds -lt $Seconds) {
        if (@(Read-Steps -Log $Log | Where-Object { $_ -ceq $Name -or $_.StartsWith($Name + " ") }).Count -gt 0) { return $true }
        Start-Sleep -Milliseconds 200
    }
    return $false
}
function Get-Left {
    # The processes with -ProfileDir as their profile, asked for up to 10 s: a process ended through its job
    # is listed for a moment after.
    param([string]$ProfileDir)
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $n = @(Get-HordeTestBrowserProcesses -ProfileDir $ProfileDir).Count
    while ($n -gt 0 -and $clock.Elapsed.TotalSeconds -lt 10) { Start-Sleep -Milliseconds 250; $n = @(Get-HordeTestBrowserProcesses -ProfileDir $ProfileDir).Count }
    return $n
}
function Start-Scenario {
    # The scenario in a child PowerShell of this test's own: { process; log }.
    param([string]$Mode)
    $log = Join-Path $work ($Mode + ".log")
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $shell
    $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $scenario + '" -Launcher "' + $launcher + '" -Mode ' + $Mode + ' -Chrome "' + $chrome + '" -Parent "' + $work + '" -Node "' + $node + '" -Log "' + $log + '"'
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $null = $p.StandardOutput.ReadToEndAsync(); $null = $p.StandardError.ReadToEndAsync()
    return [pscustomobject]@{ process = $p; log = $log }
}
function Test-RunWasUp {
    # CONTROL, while the run is up: its profile is named, and the command-line instrument finds its
    # browser - more than one process of it. Returns the profile.
    param([string]$Log, [string]$What)
    $up = Wait-Step -Log $Log -Name "READY"
    $prof = Get-Step -Log $Log -Name "PROFILE"
    if ($prof -ne "") { [void]$script:profilesSeen.Add($prof) }
    $n = $(if ($prof -ne "") { @(Get-HordeTestBrowserProcesses -ProfileDir $prof).Count } else { 0 })
    Check ($up -and $prof.StartsWith($work) -and $n -ge 2) ("CONTROL (" + $What + "): the browser was up in its own profile under the run's folder, and the instrument saw " + $n + " process(es) of it")
    [System.IO.File]::WriteAllText($Log + ".go", "")
    return $prof
}
function Test-RunCleaned {
    param([string]$ProfileDir, [string]$What, [string]$Log)
    $left = $(if ($ProfileDir -ne "") { Get-Left -ProfileDir $ProfileDir } else { -1 })
    $gone = $ProfileDir -ne "" -and -not (Test-Path -LiteralPath $ProfileDir)
    Check ($left -eq 0) ("" + $What + ": no process is left with the run's profile as its --user-data-dir (" + $left + " left)")
    Check ($gone) ("" + $What + ": the run's profile folder is gone (the run's cleanup said: " + (Get-Step -Log $Log -Name "STOPPED") + ")")
}

try {
    Write-Host ""
    Write-Host "--- the launcher itself ---" -ForegroundColor Cyan
    $end0 = Stop-HordeTestBrowser -Browser $null
    Check ($end0.left -eq 0 -and $end0.profileGone) "stopping no browser is safe: a finally block may run before anything started"
    $b = Start-HordeTestBrowser -Chrome $chrome -Parent $work
    [void]$script:profilesSeen.Add($b.profile)
    Check ($b.port -gt 0 -and (Split-Path -Parent $b.profile) -ceq $work -and (Split-Path -Leaf $b.profile) -cmatch '\Ahorde-browser-[0-9a-f]{32}\z') ("a browser starts in a fresh profile of its own, under -Parent, with its debugging port open (" + $b.port + ")")
    $version = $null
    try { $version = Invoke-RestMethod -Uri ("http://127.0.0.1:" + $b.port + "/json/version") -TimeoutSec 10 } catch { }
    Check ($null -ne $version -and ("" + $version.'User-Agent') -match 'HeadlessChrome') "it answers on that port, and it is headless"
    $seen = @(Get-HordeTestBrowserProcesses -ProfileDir $b.profile)
    Check ($seen.Count -ge 2) ("CONTROL: the command-line instrument finds the browser and its children (" + $seen.Count + ")")
    $end1 = Stop-HordeTestBrowser -Browser $b
    Check ($end1.left -eq 0 -and $end1.profileGone -and (Get-Left -ProfileDir $b.profile) -eq 0) ("stopped, every process of it ends and its profile goes (" + $end1.said + ")")
    $end2 = Stop-HordeTestBrowser -Browser $b
    Check ($end2.left -eq 0 -and $end2.profileGone) "stopping it twice is safe"

    foreach ($mode in @("pass", "throw", "timeout")) {
        Write-Host ""
        Write-Host ("--- a run that ends by " + $mode + " ---") -ForegroundColor Cyan
        $run = Start-Scenario -Mode $mode
        $prof = Test-RunWasUp -Log $run.log -What $mode
        $ended = $run.process.WaitForExit(60000)
        Check ($ended -and $(if ($mode -ceq "pass") { $run.process.ExitCode -eq 0 } else { $run.process.ExitCode -ne 0 })) ("CONTROL: the run ended as " + $mode + " ends it (exit " + $(if ($ended) { $run.process.ExitCode } else { "none in 60 s" }) + ")")
        Test-RunCleaned -ProfileDir $prof -What $mode -Log $run.log
    }

    Write-Host ""
    Write-Host "--- a run whose driver is killed ---" -ForegroundColor Cyan
    $run = Start-Scenario -Mode "driver-killed"
    $prof = Test-RunWasUp -Log $run.log -What "driver killed"
    $dpid = Get-Step -Log $run.log -Name "DRIVER"
    $killed = $false
    if ($dpid -match '\A[0-9]+\z') {
        # The driver is this test's own grandchild: a node process the run started a moment ago.
        $d = Get-Process -Id ([int]$dpid) -ErrorAction SilentlyContinue
        if ($null -ne $d -and $d.ProcessName -ceq "node") { $d.Kill(); $killed = $d.WaitForExit(10000) }
    }
    $ended = $run.process.WaitForExit(60000)
    Check ($killed -and $ended -and $run.process.ExitCode -ne 0) "CONTROL: the driver was killed from outside, and the run failed for it"
    Test-RunCleaned -ProfileDir $prof -What "driver killed" -Log $run.log

    Write-Host ""
    Write-Host "--- a run stopped by Ctrl+C ---" -ForegroundColor Cyan
    $log = Join-Path $work "ctrl-c.log"
    $ps = [powershell]::Create()
    [void]$ps.AddCommand($scenario).AddParameter("Launcher", $launcher).AddParameter("Mode", "wait").AddParameter("Chrome", $chrome).AddParameter("Parent", $work).AddParameter("Node", $node).AddParameter("Log", $log)
    $async = $ps.BeginInvoke()
    try {
        $prof = Test-RunWasUp -Log $log -What "Ctrl+C"
        $ps.Stop()
        Check ($async.IsCompleted -and $ps.InvocationStateInfo.State -eq "Stopped") ("CONTROL: the run was stopped as Ctrl+C stops it (" + $ps.InvocationStateInfo.State + ")")
        Test-RunCleaned -ProfileDir $prof -What "Ctrl+C" -Log $log
    } finally { $ps.Dispose() }

    Write-Host ""
    Write-Host "--- the suite itself killed ---" -ForegroundColor Cyan
    $run = Start-Scenario -Mode "wait"
    $prof = Test-RunWasUp -Log $run.log -What "suite killed"
    $run.process.Kill()
    Check ($run.process.WaitForExit(10000)) "CONTROL: the run's PowerShell is killed, so none of its code runs"
    $left = $(if ($prof -ne "") { Get-Left -ProfileDir $prof } else { -1 })
    Check ($left -eq 0) ("the browser dies with the suite that started it: no process is left with its profile (" + $left + " left)")
    Write-Host ("  [NOTE] its profile folder is " + $(if ($prof -ne "" -and (Test-Path -LiteralPath $prof)) { "left, as expected: nothing ran to remove it; this test removes it" } else { "gone" })) -ForegroundColor DarkGray
} finally {
    # A red run may leave a browser of this test's own: each found only by a profile this test made
    # under its own folder, so nothing else is ever touched. Ended, so the folder can go.
    foreach ($p in @($script:profilesSeen)) {
        foreach ($id in @(Get-HordeTestBrowserProcesses -ProfileDir $p)) { try { Stop-Process -Id $id -Force -ErrorAction Stop } catch { } }
    }
    for ($i = 0; $i -lt 20 -and (Test-Path -LiteralPath $work); $i++) {
        if ((Split-Path -Leaf $work) -match '\Ahorde-browser-cleanup-[0-9a-f]{32}\z') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $work) { Start-Sleep -Milliseconds 250 }
    }
}
Check (-not (Test-Path -LiteralPath $work)) "the test's own folder is gone"

Complete-HordeSuite -Success "a suite's headless browser ends, every process of it, and its profile goes, whether the suite passes, throws, times its driver out, loses its driver or is stopped by Ctrl+C - and the browser dies even with the suite killed"
