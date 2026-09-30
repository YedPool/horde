# END TO END: start a real isolated WezTerm, run something inside it, tear it down, prove it all went.
#
# This launches a real, minimized terminal. It is safe to run beside a working one because it is a
# separate instance with its own mux, and because it asserts that before doing anything - see
# test/harness/Isolation.ps1. No agent session is started, so it costs nothing to run.
#
# WHAT IT MEASURES THAT NOTHING ELSE CAN: whether killing the terminal also kills what ran in it. The
# child here is deliberately long-lived, so if it survives the terminal the harness has to find and
# kill it - and the result records whether that happened.

$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
. (Join-Path $root "test\harness\Isolation.ps1")

$fails = @()
function Check { param($Cond, [string]$What)
    if ($Cond) { Write-Host "  [PASS] $What" -ForegroundColor DarkGray }
    else { Write-Host "  [FAIL] $What" -ForegroundColor Red; $script:fails += $What } }

$liveBefore = @(Get-HordeWeztermGuiPids)
$origSocket = $env:WEZTERM_UNIX_SOCKET
$origRoot = $env:HORDE_ROOT
$marker = "HORDE-E2E-" + [guid]::NewGuid().ToString("N").Substring(0, 8)

Write-Host ""
Write-Host "--- start and prove isolation ---" -ForegroundColor Cyan
$iso = Start-HordeIsolatedWezterm -TimeoutSeconds 45
Check ($null -ne $iso) "an isolated instance started and answered"

$result = $null
if ($iso) {
    try {
        $count = $null
        try { $count = Assert-HordeIsolated -Instance $iso } catch { Write-Host ("         " + $_.Exception.Message) -ForegroundColor Red }
        Check ($count -eq 1) "it is isolated, measured: exactly one pane, in its own window"
        Check ("$env:HORDE_ROOT" -eq "$($iso.store)" -and (Test-Path -LiteralPath $iso.store)) "Horde's own state points at a throwaway store while it runs"

        if ($count -eq 1) {
            Write-Host ""
            Write-Host "--- run something real inside it ---" -ForegroundColor Cyan
            $spawned = & wezterm cli spawn -- cmd /c "echo $marker && ping -n 120 127.0.0.1 >nul" 2>$null
            $pane = "$(@($spawned) -join '')".Trim()
            Check ($pane -match '^\d+$') "a pane was spawned in the isolated instance"
            Start-Sleep -Seconds 2
            $text = ""
            if ($pane -match '^\d+$') { $text = "" + (& wezterm cli get-text --pane-id $pane 2>$null) }
            Check ($text -like "*$marker*") "the command ran and its output is on that pane's screen"
            $inside = @(Get-HordeDescendantPids -RootPid $iso.pid)
            $pingInside = @(Get-CimInstance Win32_Process -Filter "Name = 'PING.EXE'" -ErrorAction SilentlyContinue |
                Where-Object { $inside -contains [int]$_.ProcessId })
            Check ($pingInside.Count -ge 1) "the long-lived child is running inside the instance's process tree"
        }
    }
    finally {
        # Teardown runs whatever happened above. A teardown that only runs on success is the leak.
        Write-Host ""
        Write-Host "--- tear down and prove it went ---" -ForegroundColor Cyan
        $result = Stop-HordeIsolatedWezterm -Instance $iso
    }

    Check (-not $result.survived) "the terminal is gone"
    Check (@($result.orphansSurvived).Count -eq 0) "nothing that ran inside it is still running"
    Check ($result.stopped) "so the teardown's own verdict is stopped"
    Check ($result.socketRemoved) "its socket file is removed"
    Check (-not (Test-Path -LiteralPath $iso.store)) "its throwaway store is removed"
    Write-Host ("  measured: killing the terminal left " + @($result.orphansKilled).Count +
                " process(es) running that the harness then had to kill: " + (@($result.orphansKilled) -join ", ")) -ForegroundColor Cyan
}

Write-Host ""
Write-Host "--- and the user's terminal was never touched ---" -ForegroundColor Cyan
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
Write-Host "==== an isolated terminal starts, works, and leaves nothing behind ====" -ForegroundColor Green
exit 0
