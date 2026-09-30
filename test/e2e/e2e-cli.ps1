# END TO END: the horde command line, driven the way a user drives it, in a terminal that is ours.
#
# Migration-plan step 0.9's gate for the CLI. A real isolated WezTerm is started (see
# hosts/wezterm/test/Isolation.ps1 for why it is an INSTANCE and never a window), two panes are spawned in
# it, one running `horde --help` and one running `horde version` through `powershell -File`, exactly
# as a script or a person would, and what a user would see on each pane's screen is read back and
# checked. No agent session is started, so it costs nothing to run.
#
# THE USER'S TERMINAL IS NEVER TOUCHED. Nothing destructive, and nothing that spawns, runs until
# Assert-HordeIsolated has measured that this process is pinned to the new instance and can see only
# its one pane. Teardown is in a finally block, so it runs whatever happens above it - a teardown that
# only runs on success is the leak.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "hosts\wezterm\test\Isolation.ps1")

# THE HARNESS RUNS UNDER "Continue", NOT THE SUITE'S "Stop". It calls wezterm with `2>$null`, and
# measured 2026-09-29 on PowerShell 5.1: under Stop, a native command whose stderr is redirected to
# $null still raises a terminating error for its first stderr line (`cmd /c "echo x 1>&2" 2>$null`
# threw "x"). The harness reports failure through its return values, which every call below checks.
# Variable lookup follows the call stack, so the harness functions called from the block see this
# function's preference.
function Invoke-HordeHarness {
    param([scriptblock]$Block)
    $ErrorActionPreference = "Continue"
    return (& $Block)
}

function Wait-HordePaneText {
    # Read a pane's screen until it holds the marker the pane prints when horde has exited, or the
    # time runs out. Returns the text either way; the caller checks it.
    param([string]$Pane, [string]$Until, [int]$Seconds = 30)
    $deadline = (Get-Date).AddSeconds($Seconds)
    $text = ""
    do {
        $text = "" + ((Invoke-HordeHarness { Invoke-HordeWeztermCli -Rest @("get-text", "--pane-id", $Pane) }) -join "`n")
        if ($text -like ("*" + $Until + "*")) { break }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    return $text
}

$version = "$(Get-Content -LiteralPath (Join-Path $root 'VERSION') -TotalCount 1)".Trim()
$horde = Join-Path $root "horde.ps1"
Check ($version -match '^\d+\.\d+\.\d+$') ("CONTROL: the VERSION file holds a version (" + $version + ")")
$liveBefore = @(Invoke-HordeHarness { Get-HordeWeztermGuiPids })
$origSocket = $env:WEZTERM_UNIX_SOCKET
$origRoot = $env:HORDE_ROOT

# Each pane runs horde through `powershell -File`, as a script would, inside a PowerShell that stays
# open afterwards (-NoExit), so the screen is still there to read when horde has finished, and prints
# horde's exit code after it. Single quotes only: this line passes through PowerShell's native
# argument passing, wezterm's and powershell.exe's, and a double quote would be re-quoted on the way.
function Get-HordePaneCommand {
    param([string[]]$HordeArgs, [string]$Marker)
    $line = "& powershell -NoProfile -ExecutionPolicy Bypass -File '" + ($horde -replace "'", "''") + "' " + ($HordeArgs -join " ") +
        "; '" + $Marker + "=' + `$LASTEXITCODE"
    return @("spawn", "--", "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-NoExit", "-Command", $line)
}

Write-Host ""
Write-Host "=== horde --help and horde version, in an isolated terminal ===" -ForegroundColor Cyan
$iso = Invoke-HordeHarness { Start-HordeIsolatedWezterm -TimeoutSeconds 45 }
Check ($null -ne $iso) "an isolated instance started and answered"
$result = $null
if ($iso) {
    try {
        $count = $null
        try { $count = Invoke-HordeHarness { Assert-HordeIsolated -Instance $iso } }
        catch { Write-Host ("         " + $_.Exception.Message) -ForegroundColor Red }
        Check ($count -eq 1) "it is isolated, measured: exactly one pane, in its own instance"

        if ($count -eq 1) {
            $tag = [guid]::NewGuid().ToString("N").Substring(0, 8)
            $helpMark = "HORDE-HELP-EXIT-" + $tag
            $verMark = "HORDE-VERSION-EXIT-" + $tag

            $spawned = Invoke-HordeHarness { Invoke-HordeWeztermCli -Rest (Get-HordePaneCommand -HordeArgs @("--help") -Marker $helpMark) }
            $helpPane = "$(@($spawned) -join '')".Trim()
            Check ($helpPane -match '^\d+$') ("a pane running horde --help was spawned in the isolated instance (got '" + $helpPane + "')")
            $spawned = Invoke-HordeHarness { Invoke-HordeWeztermCli -Rest (Get-HordePaneCommand -HordeArgs @("version") -Marker $verMark) }
            $verPane = "$(@($spawned) -join '')".Trim()
            Check ($verPane -match '^\d+$' -and $verPane -ne $helpPane) ("a second pane running horde version was spawned (got '" + $verPane + "')")

            if ($helpPane -match '^\d+$') {
                $text = Wait-HordePaneText -Pane $helpPane -Until ($helpMark + "=")
                $lines = @($text -split "`r?`n")
                Check (@($lines | Where-Object { $_ -match '^usage: horde <command>' }).Count -eq 1) "the help pane shows horde's usage line"
                Check (@($lines | Where-Object { $_ -match '^\s+horde version\b' }).Count -eq 1) "the help pane lists 'horde version' exactly once"
                Check (@($lines | Where-Object { $_.Trim() -eq ($helpMark + "=0") }).Count -eq 1) ("horde --help exited 0 in the pane (screen: " + ($text.Trim() -replace "\s*`n\s*", " | ") + ")")
            }
            if ($verPane -match '^\d+$') {
                $text = Wait-HordePaneText -Pane $verPane -Until ($verMark + "=")
                $lines = @($text -split "`r?`n")
                Check (@($lines | Where-Object { $_.Trim() -eq ("horde " + $version) }).Count -eq 1) ("the version pane shows the version from the VERSION file: horde " + $version)
                Check (@($lines | Where-Object { $_.Trim() -eq ($verMark + "=0") }).Count -eq 1) ("horde version exited 0 in the pane (screen: " + ($text.Trim() -replace "\s*`n\s*", " | ") + ")")
            }
        }
    }
    finally {
        $result = Invoke-HordeHarness { Stop-HordeIsolatedWezterm -Instance $iso }
    }
    Check (-not $result.refused) "teardown accepted the instance Start issued"
    Check (-not $result.survived) "the terminal is gone"
    Check (@($result.orphansSurvived).Count -eq 0) "nothing that ran inside it is still running"
    Check ([bool]$result.stopped) "so the teardown's own verdict is stopped"
    Check ([bool]$result.socketRemoved) "its socket file is removed"
    Check (-not (Test-Path -LiteralPath $iso.store)) "its throwaway store is removed"
}

Write-Host ""
Write-Host "=== and the user's terminal was never touched ===" -ForegroundColor Cyan
Check ("$env:WEZTERM_UNIX_SOCKET" -eq "$origSocket") "the pin is back on the terminal this process started in"
Check ("$env:HORDE_ROOT" -eq "$origRoot") "Horde's store is back to what it was"
$liveAfter = @(Invoke-HordeHarness { Get-HordeWeztermGuiPids })
Check (@($liveBefore | Where-Object { $liveAfter -notcontains $_ }).Count -eq 0) "every WezTerm that was running before is still running"
Check (@($liveAfter | Where-Object { $liveBefore -notcontains $_ }).Count -eq 0) "and no extra WezTerm was left behind"

Complete-HordeSuite -Success "horde's help and version reach a user in a real terminal, and the terminal leaves nothing behind"
