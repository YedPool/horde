# tools/CiGuards.ps1 - runs every repo-wide guard listed in test\guards.txt, each in Windows PowerShell 5.1
# AND in PowerShell 7, and says which are green. The CI workflow (.github/workflows/guards.yml) is one step
# that calls this; `horde merge` (cli/Merge.ps1) reads the same list through core/GuardList.ps1 (T-0247).
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\CiGuards.ps1 [-Root <repo>] [-LogFolder <dir>]
#       [-Only <guard script, e.g. test\test-core-load.ps1>] [-Seconds 1200]
#       [-MachinePsModulePath <value>]   (a seam for the suite; the default is the machine's own value)
#
# GREEN IS EXIT 0 AND A CLOSING BANNER (CONTRIBUTING 15 rule 7): the last "==== ... ====" line of the
# guard's output must exist and must not be a failures banner; a guard with no banner was NOT RUN and is
# red here. Every guard runs even when an earlier one is red, so one run reports them all. Each run's
# output is kept in <LogFolder>\<guard>.<shell>.log and echoed to the console. When GITHUB_STEP_SUMMARY is
# set, a table of the runs is appended to it. Exit 0 only if every run is green; 1 otherwise.
#
# THE CHILD'S PSModulePath (core/GuardList.ps1, Get-HordeGuardEnvironment): the parent's is dropped; 5.1
# gets the machine value, 7 builds its own. Children are started through the process API, with their input
# closed and no `2>&1` (which turns a 5.1 native command's stderr into errors).
#
# Development tooling, not part of the engine. test/test-ci-guards.ps1 is its suite.
param(
    [string]$Root = "",
    [string]$LogFolder = "",
    [string]$Only = "",
    [AllowNull()]$MachinePsModulePath = $null,
    [int]$Seconds = 1200
)

if ($Root -eq "") { $Root = Split-Path -Parent $PSScriptRoot }
. (Join-Path $Root "core\GuardList.ps1")

function Write-HordeCiLine { param([string]$Line) [Console]::Out.WriteLine($Line) }

function ConvertTo-HordeCiArg {
    # One argument for a Windows command line: quoted when it holds a space or a quote.
    param([string]$Text)
    if ($Text -eq "") { return '""' }
    if ($Text -notmatch '[\s"]') { return $Text }
    return ('"' + ($Text -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"')
}

function Invoke-HordeCiGuard {
    # Run one guard in one shell: { code; out }. Code -1: it could not start, or ran past -Seconds (it is
    # then stopped with its children by process id - never by name).
    param([string]$Program, [string]$Script, [string]$Directory, [hashtable]$Environment, [int]$Seconds)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Program
    $words = @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $Script)
    $psi.Arguments = (@($words | ForEach-Object { ConvertTo-HordeCiArg -Text $_ }) -join " ")
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $Directory
    if ($psi.EnvironmentVariables.ContainsKey("PSModulePath")) { $psi.EnvironmentVariables.Remove("PSModulePath") }
    foreach ($k in @($Environment.Keys)) { $psi.EnvironmentVariables[[string]$k] = "" + $Environment[$k] }
    $p = $null
    try { $p = [System.Diagnostics.Process]::Start($psi) } catch { return [pscustomobject]@{ code = -1; out = ("could not start " + $Program + ": " + $_.Exception.Message) } }
    try {
        $p.StandardInput.Close()
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($Seconds * 1000)) {
            try { $null = & taskkill.exe /T /F /PID $p.Id } catch { }
            $global:LASTEXITCODE = 0
            return [pscustomobject]@{ code = -1; out = ("ran past " + $Seconds + " s and was stopped") }
        }
        $p.WaitForExit()
        return [pscustomobject]@{ code = $p.ExitCode; out = ($outTask.Result + $errTask.Result) }
    } finally { $p.Dispose() }
}

function Get-HordeCiBanner {
    # PURE. The last closing banner line of a guard's output, or "" when there is none.
    param([AllowEmptyString()][string]$Text)
    $found = @(("" + $Text) -split "\r?\n" | Where-Object { $_ -cmatch '\A==== .+ ====\s*\z' } | Select-Object -Last 1)
    if ($found.Count -eq 0) { return "" }
    return $found[0].Trim()
}

function Test-HordeCiGreen {
    # PURE. Green only on exit 0 AND a closing banner that is not a failures banner.
    param([int]$Code, [AllowEmptyString()][string]$Banner)
    return ($Code -eq 0 -and $Banner -ne "" -and $Banner -cnotmatch 'FAILURE')
}

$listFile = Join-Path $Root (Get-HordeGuardListPath)
if (-not [System.IO.File]::Exists($listFile)) { Write-HordeCiLine ("::error::" + (Get-HordeGuardListPath) + " is not there"); Write-HordeCiLine ("not green: no guard list"); exit 1 }
$list = Read-HordeGuardList -Text ([System.IO.File]::ReadAllText($listFile))
if (-not $list.ok) { Write-HordeCiLine ("::error::" + $list.why); Write-HordeCiLine "not green: the guard list is unusable"; exit 1 }
$guards = @($list.guards)
if ($Only -ne "") {
    $want = $Only.Replace("/", "\")
    if (-not ($guards -ccontains $want)) { Write-HordeCiLine ("::error::-Only " + $Only + " is not in " + (Get-HordeGuardListPath)); exit 1 }
    $guards = @($want)
}
if ($LogFolder -eq "") { $LogFolder = Join-Path ([System.IO.Path]::GetTempPath()) "horde-ci-guards" }
[void][System.IO.Directory]::CreateDirectory($LogFolder)

$machinePath = $MachinePsModulePath
if ($null -eq $machinePath) { $machinePath = [Environment]::GetEnvironmentVariable("PSModulePath", "Machine") }
$programs = @{ "5.1" = (Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"); "7" = (Get-HordeGuardPwsh7) }
$rows = New-Object System.Collections.ArrayList
Write-HordeCiLine ("the guards, from " + (Get-HordeGuardListPath) + ": " + ($guards -join ", "))
foreach ($g in $guards) {
    foreach ($sh in @(Get-HordeGuardShells)) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($g)
        $log = Join-Path $LogFolder ($name + "." + $sh.key + ".log")
        Write-HordeCiLine ("::group::" + $name + " in " + $sh.label)
        $program = $programs[$sh.key]
        if (-not [System.IO.File]::Exists($program)) {
            $run = [pscustomobject]@{ code = -1; out = ($sh.label + " is not at " + $program) }
        }
        elseif (-not [System.IO.File]::Exists((Join-Path $Root $g))) {
            $run = [pscustomobject]@{ code = -1; out = ("the guard " + $g + " is not in the checkout") }
        }
        else {
            $run = Invoke-HordeCiGuard -Program $program -Script (Join-Path $Root $g) -Directory $Root -Environment (Get-HordeGuardEnvironment -Shell $sh.key -MachinePsModulePath ("" + $machinePath)) -Seconds $Seconds
        }
        [System.IO.File]::WriteAllText($log, ("" + $run.out), (New-Object System.Text.UTF8Encoding($false)))
        Write-HordeCiLine ("" + $run.out)
        $banner = Get-HordeCiBanner -Text $run.out
        $green = Test-HordeCiGreen -Code $run.code -Banner $banner
        Write-HordeCiLine "::endgroup::"
        Write-HordeCiLine ($(if ($green) { "[GREEN] " } else { "[RED] " }) + $name + " in " + $sh.label + " (exit " + $run.code + ", " + $(if ($banner -eq "") { "no closing banner: NOT RUN" } else { $banner }) + ")")
        [void]$rows.Add([pscustomobject]@{ guard = $name; shell = $sh.label; code = $run.code; banner = $(if ($banner -eq "") { "(none: NOT RUN)" } else { $banner }); green = $green })
    }
}

$lines = @("| guard | shell | exit | closing banner | |", "| --- | --- | --- | --- | --- |")
foreach ($r in $rows) { $lines += ("| " + $r.guard + " | " + $r.shell + " | " + $r.code + " | " + $r.banner.Replace("|", "/") + " | " + $(if ($r.green) { "green" } else { "RED" }) + " |") }
$lines += ""
$lines += "This check notifies and never blocks a merge. horde merge runs the same list (test/guards.txt), in the same two shells, before it merges."
if ("" + $env:GITHUB_STEP_SUMMARY -ne "") { Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value ($lines -join "`n") }
$red = @($rows | Where-Object { -not $_.green })
if ($red.Count -gt 0) {
    Write-HordeCiLine ("::error::not green: " + (@($red | ForEach-Object { $_.guard + " (" + $_.shell + ")" }) -join ", "))
    exit 1
}
Write-HordeCiLine ("every guard is green in both shells (" + $rows.Count + " runs)")
exit 0
