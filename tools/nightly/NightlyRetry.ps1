# tools/nightly/NightlyRetry.ps1 - runs the nightly net ONCE more after a restart killed it. T-0397.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\nightly\NightlyRetry.ps1 [-Plan] [-WorkRoot <dir>]
#       [-AtTime <datetime>] [-NetScript <file>] [-MinMinutes 180]
#
# WHY IT EXISTS. On 2026-11-04 a restart at 23:02 killed the net 57 minutes into the night, and nothing ran it again.
# This is its own scheduled task (\Horde\HordeNightlyRetry, at user logon, registered by Register-NightlyRetryTask.ps1)
# and not a trigger of the net's task, so the net's refused-start report, which tells M, cannot fire on every daytime logon.
#
# It decides from evidence on disk (core Get-HordeNightlyRetryDecision) and runs the net at most once per night:
#   run only when the time is inside the night window with at least -MinMinutes (180) left before the net's cutoff, there is
#   no reports\<night>.txt, no FAILED, BUSY or REFUSED file for the night, no marker for the night, and the net's own lock is
#   not held (checked by opening the lock by name; the net's lock stays the real guard).
# THE MARKER (<work folder>\retry\<night>.marker) IS WRITTEN BEFORE THE NET STARTS, so repeated reboots cannot loop: one
# retry per night. A marker that exists counts whatever it holds (corrupt or empty too). If the marker cannot be written,
# nothing runs. Outside those conditions it exits 0, tells nobody, and writes one line to nightly-retry.log in the work
# folder naming the condition that decided. When it runs it also writes "nightly retry <night>:" to nightly.log, which
# the watcher reads to say a retry happened. The net then logs its own window line for the same night; the watcher judges
# the LAST run of a night, so a retried night that reports is RAN.
# -Plan prints the decision and writes and runs nothing. -NetScript is for the suite. Windows PowerShell 5.1 and 7. ASCII only.
param(
    [string]$WorkRoot = "",
    [string]$AtTime = "",
    [string]$NetScript = "",
    [string]$MutexName = "Global\HordeNightlyNet",
    [ValidateRange(1, 600)][int]$MinMinutes = 180,
    [switch]$Plan
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root "core\NightlyNet.ps1")
if ($WorkRoot -eq "") { $WorkRoot = Join-Path (Join-Path $env:LOCALAPPDATA "horde") "nightly" }
if ($NetScript -eq "") { $NetScript = Join-Path $root "tools\NightlyNet.ps1" }
$now = $(if ($AtTime -ne "") { [datetime]::Parse($AtTime, [System.Globalization.CultureInfo]::InvariantCulture) } else { Get-Date })
$retryLog = Join-Path $WorkRoot "nightly-retry.log"

function Write-NightlyRetryLine {
    param([string]$Line)
    $l = $now.ToString("s") + " " + ($Line -replace "[^\x20-\x7E]", "?")
    if ($Plan) { Write-Host ("PLAN " + $l); return }
    try { [void][System.IO.Directory]::CreateDirectory($WorkRoot); Add-Content -LiteralPath $retryLog -Value $l -Encoding Ascii -ErrorAction Stop } catch { }
    Write-Host $l
}

try {
    $night = Get-HordeNightlyNightLabel -Time $now
    $reportDir = Join-Path $WorkRoot "reports"
    $names = @(); if (Test-Path -LiteralPath $reportDir -PathType Container) { $names = @(Get-ChildItem -LiteralPath $reportDir -File | ForEach-Object { $_.Name }) }
    $markerPath = Join-Path (Join-Path $WorkRoot "retry") ($night + ".marker")
    $markerExists = (Test-Path -LiteralPath $markerPath)
    # Is a net run alive? A named lock exists only while a process holds a handle to it.
    $alive = $false
    $held = $null
    try { if ([System.Threading.Mutex]::TryOpenExisting($MutexName, [ref]$held)) { $alive = $true; $held.Dispose() } } catch { }
    $d = Get-HordeNightlyRetryDecision -Now $now -ReportNames $names -MarkerExists $markerExists -NetAlive $alive -MinMinutes $MinMinutes
    Write-NightlyRetryLine ("night " + $d.night + ": " + $(if ($d.run) { "RUN" } else { "no retry" }) + ", decided by: " + $d.condition + " (" + $d.minutesLeft + " min before the cutoff)")
    if (-not $d.run -or $Plan) { exit 0 }
    # THE MARKER FIRST. If it cannot be written, nothing runs: a retry that cannot be remembered could loop.
    try {
        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $markerPath))
        $fs = [System.IO.File]::Open($markerPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
        $bytes = [System.Text.Encoding]::ASCII.GetBytes("retry started " + $now.ToString("s") + "`n")
        $fs.Write($bytes, 0, $bytes.Length); $fs.Dispose()
    } catch {
        Write-NightlyRetryLine ("the marker could not be written, so nothing runs: " + $_.Exception.Message)
        exit 0
    }
    try { Add-Content -LiteralPath (Join-Path $WorkRoot "nightly.log") -Value ($now.ToString("s") + " nightly retry " + $d.night + ": the net is run once more after a restart") -Encoding Ascii -ErrorAction Stop } catch { }
    $ps51 = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    & $ps51 -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $NetScript
    $code = $LASTEXITCODE
    Write-NightlyRetryLine ("the net ended with exit " + $code)
    exit $code
} catch {
    Write-NightlyRetryLine ("the retry itself failed: " + $_.Exception.Message)
    exit 1
}
