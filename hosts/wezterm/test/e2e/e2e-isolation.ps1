# END TO END: start a real isolated WezTerm, run something inside it, tear it down, prove it all went.
#
# This launches real, minimized terminals. It is safe to run beside a working one because each is a
# separate instance with its own mux, and because it asserts that before doing anything - see
# hosts/wezterm/test/Isolation.ps1. No agent session is started, so it costs nothing to run.
#
# TWO SCENARIOS. The first is the ordinary one. The second FAILS ON PURPOSE partway through, because a
# teardown that only runs when everything went well is the leak - and the first version of this file
# never proved otherwise.

$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path -Parent $here) "Isolation.ps1")

$fails = @()
function Check { param($Cond, [string]$What)
    if ($Cond) { Write-Host "  [PASS] $What" -ForegroundColor DarkGray }
    else { Write-Host "  [FAIL] $What" -ForegroundColor Red; $script:fails += $What } }

$liveBefore = @(Get-HordeWeztermGuiPids)
$origSocket = $env:WEZTERM_UNIX_SOCKET
$origRoot = $env:HORDE_ROOT
$marker = "HORDE-E2E-" + [guid]::NewGuid().ToString("N").Substring(0, 8)

Write-Host ""
Write-Host "=== scenario 1: start, prove isolation, run something, tear down ===" -ForegroundColor Cyan
$iso = Start-HordeIsolatedWezterm -TimeoutSeconds 45
Check ($null -ne $iso) "an isolated instance started and answered"

if ($iso) {
    # MEASURED, not assumed: the gui adopted is the one our own launcher produced. Start only accepts a
    # gui whose parent is the launch process, so if this line prints, that rule held on this machine.
    Write-Host ("  adopted gui " + $iso.pid + ", whose parent is our launcher " + $iso.launcherPid) -ForegroundColor DarkGray
    $result = $null
    try {
        $count = $null
        try { $count = Assert-HordeIsolated -Instance $iso } catch { Write-Host ("         " + $_.Exception.Message) -ForegroundColor Red }
        Check ($count -eq 1) "it is isolated, measured: exactly one pane, in its own window"
        Check ("$env:HORDE_ROOT" -eq "$($iso.store)" -and (Test-Path -LiteralPath $iso.store)) "Horde's own state points at a throwaway store while it runs"

        # EVERY PANE PASSES THE IN-PANE ENVIRONMENT CHECK FIRST (coordinator's rule of 2026-10-05; issue
        # #95): the throwaway store must reach a pane spawned the way this scenario spawns.
        $envOk = $false
        if ($count -eq 1) {
            try { $envOk = Assert-HordePaneEnvironment -Instance $iso -Variables @{ HORDE_ROOT = "$($iso.store)" } -Tool (Get-HordePaneTool) } catch { Write-Host ("         " + $_.Exception.Message) -ForegroundColor Red }
        }
        Check ($envOk -eq $true) "a pane spawned as this scenario spawns sees the throwaway store, proved from inside the pane"
        if ($count -eq 1 -and $envOk) {
            $spawned = Invoke-HordeWeztermCli -Rest @("spawn", "--", "cmd", "/c", "echo $marker && ping -n 120 127.0.0.1 >nul")
            $pane = "$(@($spawned) -join '')".Trim()
            Check ($pane -match '^\d+$') "a pane was spawned in the isolated instance"
            Start-Sleep -Seconds 2
            $text = ""
            if ($pane -match '^\d+$') { $text = "" + (Invoke-HordeWeztermCli -Rest @("get-text", "--pane-id", $pane)) }
            Check ($text -like "*$marker*") "the command ran and its output is on that pane's screen"
            $inside = @(Get-HordeDescendantPids -RootPid $iso.pid -RootCreated $iso.created)
            $pingInside = @($inside | Where-Object { (Get-HordeProcessInfo -Id $_.pid).name -eq "PING.EXE" })
            Check ($pingInside.Count -ge 1) "the long-lived child is running inside the instance's process tree"
        }
    }
    finally {
        # Teardown runs whatever happened above. A teardown that only runs on success is the leak.
        $result = Stop-HordeIsolatedWezterm -Instance $iso
    }

    Check (-not $result.refused) "teardown accepted the instance Start issued"
    Check (-not $result.survived) "the terminal is gone"
    Check (@($result.orphansSurvived).Count -eq 0) "nothing that ran inside it is still running"
    Check ($result.stopped) "so the teardown's own verdict is stopped"
    Check ($result.socketRemoved) "its socket file is removed"
    Check (-not (Test-Path -LiteralPath $iso.store)) "its throwaway store is removed"
    Write-Host ("  measured: killing the terminal left " + @($result.orphansKilled).Count +
                " process(es) running that the harness then had to kill") -ForegroundColor Cyan
}

Write-Host ""
Write-Host "=== scenario 2: the scenario fails midway - teardown must still run ===" -ForegroundColor Cyan
$iso2 = Start-HordeIsolatedWezterm -TimeoutSeconds 45
Check ($null -ne $iso2) "a second isolated instance started and answered"
if ($iso2) {
    $r2 = $null; $threw = $false
    try {
        try {
            [void](Assert-HordeIsolated -Instance $iso2)
            throw "injected failure, standing in for any test that breaks partway"
        }
        finally {
            $r2 = Stop-HordeIsolatedWezterm -Instance $iso2
        }
    } catch { $threw = ("$($_.Exception.Message)" -like "*injected failure*") }
    Check $threw "PRECONDITION: the injected failure really was thrown"
    Check ($null -ne $r2 -and $r2.stopped) "when the scenario fails midway, teardown still runs and leaves nothing"
    Check ("$env:WEZTERM_UNIX_SOCKET" -eq "$origSocket") "and the pin is back on the original terminal even after a failure"
}

Write-Host ""
Write-Host "=== and the user's terminal was never touched ===" -ForegroundColor Cyan
Check ("$env:WEZTERM_UNIX_SOCKET" -eq "$origSocket") "the pin is back on the terminal this process started in"
Check ("$env:HORDE_ROOT" -eq "$origRoot") "Horde's store is back to what it was"
$liveAfter = @(Get-HordeWeztermGuiPids)
Check (@($liveBefore | Where-Object { $liveAfter -notcontains $_ }).Count -eq 0) "every WezTerm that was running before is still running"
Check (@($liveAfter | Where-Object { $liveBefore -notcontains $_ }).Count -eq 0) "and no extra WezTerm was left behind"

Write-Host ""
if ($fails.Count) {
    Write-Host "==== $($fails.Count) FAILURE(S) ====" -ForegroundColor Red
    $fails | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host "==== an isolated terminal starts, works, and leaves nothing behind - even when a test fails ====" -ForegroundColor Green
exit 0
