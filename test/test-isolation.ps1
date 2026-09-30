# DOES THE ISOLATION HARNESS REFUSE TO TOUCH A TERMINAL IT DID NOT START?
#
# The fast half of the harness's tests: nothing here launches a terminal. The end-to-end half, which
# does, is test/e2e/e2e-isolation.ps1.
#
# The property under test has been violated twice on the system Horde replaces - once by trusting a
# recycled pane id, once by isolating a window instead of an instance. So most of this suite checks
# REFUSALS, and it includes one control against the live terminal that is strictly read-only: it
# points the isolation check at the user's own socket and requires it to refuse.

$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\harness\Isolation.ps1")

$fails = @()
function Check { param($Cond, [string]$What)
    if ($Cond) { Write-Host "  [PASS] $What" -ForegroundColor DarkGray }
    else { Write-Host "  [FAIL] $What" -ForegroundColor Red; $script:fails += $What } }
function Throws { param([scriptblock]$Block, [string]$Like)
    try { & $Block; return $false } catch { return ("$($_.Exception.Message)" -like "*$Like*") } }

Write-Host ""
Write-Host "--- parsing the pane list: the collapse that disarmed the old guard ---" -ForegroundColor Cyan

# The CLI's JSON arrives as LINES. Three panes across two windows, split the way the CLI splits them.
$lines = @('[', '  {"window_id":1,"tab_id":1,"pane_id":1},', '  {"window_id":1,"tab_id":2,"pane_id":2},',
           '  {"window_id":2,"tab_id":3,"pane_id":3}', ']')
$joined = ($lines -join "`n")
# CONTROL: the trap is real in THIS PowerShell. If wrapping the pipeline did not collapse the list
# here, the assertion after it would be testing nothing.
$collapsed = @($joined | ConvertFrom-Json)
Check ($collapsed.Count -eq 1) "CONTROL: wrapping the pipeline in @() really does collapse three panes into one here"
$panes = ConvertFrom-HordeWeztermJson -Raw $lines
Check (@($panes).Count -eq 3) "assign first, then wrap: three panes stay three"
Check ($null -eq (ConvertFrom-HordeWeztermJson -Raw $null)) "no output parses to nothing rather than to an empty list"

Write-Host ""
Write-Host "--- deciding whether panes look isolated ---" -ForegroundColor Cyan

Check ((Test-HordeIsolationPanes -Panes @()) -like "*unknown, not empty*") "zero panes is refused as unknown, never treated as an empty terminal"
Check ($null -eq (Test-HordeIsolationPanes -Panes @($panes[0], $panes[1]))) "panes in one window look like a fresh instance"
Check ((Test-HordeIsolationPanes -Panes $panes) -like "*looks like the user's terminal*") "panes across two windows are refused as the user's terminal"

Write-Host ""
Write-Host "--- the isolation check refuses on any doubt ---" -ForegroundColor Cyan

Check (Throws { Assert-HordeIsolated -Instance $null } "no instance") "no instance is refused"
$saved = $env:WEZTERM_UNIX_SOCKET
$env:WEZTERM_UNIX_SOCKET = "C:\nowhere\gui-sock-1"
Check (Throws { Assert-HordeIsolated -Instance ([pscustomobject]@{ pid = 2; socket = "C:\nowhere\gui-sock-2" }) } "WEZTERM_UNIX_SOCKET is") "a pin that points somewhere else is refused"
Check (Throws { Assert-HordeIsolated -Instance ([pscustomobject]@{ pid = 2; socket = "C:\nowhere\gui-sock-1" }) } "does not belong to pid") "a socket whose name names a different pid is refused"
$env:WEZTERM_UNIX_SOCKET = $saved

Write-Host ""
Write-Host "--- CONTROL against the live terminal: read-only, and it must refuse ---" -ForegroundColor Cyan

# The harness's whole reason to exist is to stop a test acting on the user's terminal. So point it AT
# the user's terminal and require it to refuse. The only call it makes is `wezterm cli list`, which
# reads and changes nothing.
if (-not $env:WEZTERM_UNIX_SOCKET) {
    Write-Host "  (skipped: this process is not inside WezTerm, so there is no live terminal to aim at - not a pass)" -ForegroundColor Yellow
} else {
    $leaf = Split-Path -Leaf $env:WEZTERM_UNIX_SOCKET
    $livePid = 0
    if ($leaf -match "^gui-sock-(\d+)$") { $livePid = [int]$Matches[1] }
    $live = [pscustomobject]@{ pid = $livePid; socket = $env:WEZTERM_UNIX_SOCKET }
    $liveRaw = & wezterm cli list --format json 2>$null
    $liveWindows = @(@(ConvertFrom-HordeWeztermJson -Raw $liveRaw) | ForEach-Object { "$($_.window_id)" } | Sort-Object -Unique).Count
    if ($liveWindows -le 1) {
        Write-Host "  (inconclusive: the live terminal has $liveWindows window, which the window heuristic cannot tell from a fresh instance - not a pass)" -ForegroundColor Yellow
    } else {
        Check (Throws { Assert-HordeIsolated -Instance $live } "looks like the user's terminal") ("pointed at the live terminal ($liveWindows windows), the check refuses")
    }
}

Write-Host ""
Write-Host "--- teardown with nothing to tear down still gives a verdict ---" -ForegroundColor Cyan

$v = Stop-HordeIsolatedWezterm -Instance $null
Check ($null -ne $v) "passing no instance returns a verdict rather than nothing"
Check (-not $v.stopped) "and that verdict is NOT stopped, because nothing was verified"
Check ("$($v.reason)" -like "*nothing was verified*") "and it says so"

# A pid that is certainly not running: spawn a process, let it exit, reuse its id as "the instance".
$gone = Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", "exit") -PassThru -WindowStyle Hidden
$gone.WaitForExit(10000) | Out-Null
$savedSock = $env:WEZTERM_UNIX_SOCKET; $savedRoot = $env:HORDE_ROOT
$dead = Stop-HordeIsolatedWezterm -Instance ([pscustomobject]@{
    pid = $gone.Id; socket = (Join-Path $env:TEMP "horde-no-such-socket"); store = $null
    originalSocket = $savedSock; originalRoot = $savedRoot })
Check ($dead.stopped -and -not $dead.survived) "a terminal that is already gone reads as stopped, not survived"
Check ($dead.socketRemoved) "and a socket that was never there counts as removed"
Check ("$env:WEZTERM_UNIX_SOCKET" -eq "$savedSock" -and "$env:HORDE_ROOT" -eq "$savedRoot") "teardown restores the pin and the store it was given, not some other process's"

Write-Host ""
Write-Host "--- finding what ran inside a process, before killing it ---" -ForegroundColor Cyan

# A real process tree: cmd starts ping, which outlives nothing unless we kill it. The walker must find
# the grandchild, because that is exactly what survives when only the top of the tree is killed.
$tree = Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", "ping -n 30 127.0.0.1 >nul") -PassThru -WindowStyle Hidden
Start-Sleep -Milliseconds 1500
$found = @(Get-HordeDescendantPids -RootPid $tree.Id)
$pings = @(Get-CimInstance Win32_Process -Filter "Name = 'PING.EXE'" -ErrorAction SilentlyContinue | Where-Object { $_.ParentProcessId -eq $tree.Id })
Check ($pings.Count -ge 1) "PRECONDITION: the test really started a child process"
Check (@($pings | Where-Object { $found -contains [int]$_.ProcessId }).Count -eq $pings.Count) "the walker finds the child that ran inside the process"
Check (-not ($found -contains $tree.Id)) "and does not list the process itself as its own descendant"
foreach ($x in @($found + $tree.Id)) { try { Stop-Process -Id $x -Force -ErrorAction SilentlyContinue } catch { } }

Write-Host ""
Write-Host "--- every script that starts an instance also tears it down, by the real name ---" -ForegroundColor Cyan

# The old system's leak on 2026-09-29 was a NAME: a probe called a teardown function that did not
# exist, so the teardown never ran and nothing inside it could have helped. This guards the class.
# $PSCommandPath, NOT $MyInvocation, to exclude this file. Inside a Where-Object block $MyInvocation
# describes that block, not the script - so the first version of this check listed THIS file as a
# script that starts an instance, because it contains the function's name as a string, and then
# passed it. A check that passes for the wrong reason is output shaped like evidence.
$self = $PSCommandPath
function Get-CodeOnly { param([string]$Path)
    # Comment lines removed, so a script that only MENTIONS a function is not counted as calling it.
    return ((Get-Content -LiteralPath $Path) | Where-Object { -not $_.TrimStart().StartsWith("#") }) -join "`n" }
$scripts = @(Get-ChildItem -Path $root -Recurse -Include *.ps1 -File |
    Where-Object { $_.FullName -notlike "*\test\harness\*" -and $_.FullName -ne $self })
Check ($scripts.Count -gt 0) "CONTROL: the scan sees real scripts, so an empty result below would mean something"
Check (@($scripts | Where-Object { $_.FullName -eq $self }).Count -eq 0) "CONTROL: this file is excluded from its own scan"
$starters = @($scripts | Where-Object { (Get-CodeOnly -Path $_.FullName) -match "Start-HordeIsolatedWezterm" })
Check ($starters.Count -gt 0) "CONTROL: the scan finds at least one script that starts an instance"
foreach ($s in $starters) {
    Check ((Get-CodeOnly -Path $s.FullName) -match "Stop-HordeIsolatedWezterm") ("$($s.Name) calls Stop-HordeIsolatedWezterm by its real name")
}
Check (-not ("Start-HordeIsolatedWezterm" -match "Stop-HordeIsolatedWezterm")) "CONTROL: the matcher does not confuse the start name for the stop name"

Write-Host ""
if ($fails.Count) {
    Write-Host "==== $($fails.Count) FAILURE(S) ====" -ForegroundColor Red
    $fails | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host "==== the harness refuses a terminal it did not start ====" -ForegroundColor Green
exit 0
