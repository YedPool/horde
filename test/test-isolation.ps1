# DOES THE ISOLATION HARNESS REFUSE TO TOUCH A TERMINAL - OR ANY PROCESS - IT DID NOT START?
#
# The fast half of the harness's tests: nothing here launches a terminal. The end-to-end half, which
# does, is test/e2e/e2e-isolation.ps1.
#
# THIS SUITE NEVER KILLS A PROCESS IT DID NOT START ITSELF. An independent review of its first version
# found that it did: it handed a stray pid to the teardown, which force-killed that pid and everything
# the process walker believed descended from it - and the walker could wander into unrelated processes
# through reused parent pids. Kill safety is now proven only on processes this file launches, and the
# pid-reuse case is proven on an injected process table, where nothing real can be harmed.

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
function Start-OwnPing {
    # A throwaway process this suite owns, identified by pid AND creation time from the moment it exists.
    param([int]$Seconds = 60)
    $p = Start-Process -FilePath "ping.exe" -ArgumentList @("-n", "$Seconds", "127.0.0.1") -PassThru -WindowStyle Hidden
    Start-Sleep -Milliseconds 300
    return (Get-HordeProcessInfo -Id $p.Id) }

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
$noWin = @([pscustomobject]@{ pane_id = 1 }, [pscustomobject]@{ pane_id = 2 })
Check ((Test-HordeIsolationPanes -Panes $noWin) -like "*no window_id*") "a pane with no window_id is refused rather than counted as one window"

Write-Host ""
Write-Host "--- the isolation check refuses on any doubt ---" -ForegroundColor Cyan

Check (Throws { Assert-HordeIsolated -Instance $null } "no instance") "no instance is refused"
$saved = $env:WEZTERM_UNIX_SOCKET
$env:WEZTERM_UNIX_SOCKET = "C:\nowhere\gui-sock-1"
Check (Throws { Assert-HordeIsolated -Instance ([pscustomobject]@{ pid = 2; socket = "C:\nowhere\gui-sock-2" }) } "WEZTERM_UNIX_SOCKET is") "a pin that points somewhere else is refused"
Check (Throws { Assert-HordeIsolated -Instance ([pscustomobject]@{ pid = 2; socket = "C:\nowhere\gui-sock-1" }) } "does not belong to pid") "a hand-built instance whose socket names a different pid is refused"
$env:WEZTERM_UNIX_SOCKET = $saved

Write-Host ""
Write-Host "--- CONTROL against the live terminal: read-only, and it must refuse ---" -ForegroundColor Cyan

# The harness's whole reason to exist is to stop a test acting on the user's terminal. So point the
# isolation CHECK at the user's terminal and require it to refuse. It only lists panes. This object is
# never passed to the teardown - which would now refuse it for lack of a token, and is tested for that
# below on a process this suite owns, never on the user's terminal.
if (-not $env:WEZTERM_UNIX_SOCKET) {
    Write-Host "  (skipped: this process is not inside WezTerm, so there is no live terminal to aim at - not a pass)" -ForegroundColor Yellow
} else {
    $leaf = Split-Path -Leaf $env:WEZTERM_UNIX_SOCKET
    $livePid = 0
    if ($leaf -match "^gui-sock-(\d+)$") { $livePid = [int]$Matches[1] }
    $live = [pscustomobject]@{ pid = $livePid; socket = $env:WEZTERM_UNIX_SOCKET }
    $liveRaw = Invoke-HordeWeztermCli -Rest @("list", "--format", "json")
    $liveWindows = @(@(ConvertFrom-HordeWeztermJson -Raw $liveRaw) | ForEach-Object { "$($_.window_id)" } | Sort-Object -Unique).Count
    Write-Host ("  the live terminal has " + $liveWindows + " window(s)") -ForegroundColor DarkGray
    if ($liveWindows -le 1) {
        Write-Host "  (inconclusive: one window cannot be told from a fresh instance by the window heuristic - not a pass)" -ForegroundColor Yellow
    } else {
        Check (Throws { Assert-HordeIsolated -Instance $live } "looks like the user's terminal") "pointed at the live terminal, the isolation check refuses"
    }
}

Write-Host ""
Write-Host "--- the process walker never wanders into a process that is not a descendant ---" -ForegroundColor Cyan

# AN INJECTED TABLE, so the case the review found can be proven without a single real process. It
# mirrors what was measured live: a process created BEFORE the process that now holds its recorded
# parent pid - meaning its real parent died and the pid was reused.
$t0 = Get-Date "2026-09-29 12:00:00"
$table = @(
    [pscustomobject]@{ pid = 100; ppid = 1;   name = "root.exe";   created = $t0.AddMinutes(10) },
    [pscustomobject]@{ pid = 200; ppid = 100; name = "child.exe";  created = $t0.AddMinutes(11) },
    [pscustomobject]@{ pid = 400; ppid = 200; name = "grand.exe";  created = $t0.AddMinutes(12) },
    [pscustomobject]@{ pid = 300; ppid = 100; name = "orphan.exe"; created = $t0.AddMinutes(1) },
    [pscustomobject]@{ pid = 500; ppid = 300; name = "orphankid.exe"; created = $t0.AddMinutes(2) }
)
$d = @(Get-HordeDescendantPids -RootPid 100 -Processes $table | ForEach-Object { $_.pid })
Check ($d -contains 200 -and $d -contains 400) "a child created after its parent is found, and so is its own child"
Check (-not ($d -contains 300)) "a process created before its recorded parent is not treated as that parent's child - the pid was reused"
Check (-not ($d -contains 500)) "and nothing below that orphan is reached either"
Check (-not ($d -contains 100)) "the root is not listed as its own descendant"

# THE SAME CASE ON REAL DATA, read-only. If this machine happens to have a process whose recorded
# parent pid now belongs to something younger, the walker must not count it. Without such a pair the
# check has nothing to test, and says so rather than passing.
$real = @(Get-HordeProcessTable)
$byId = @{}; foreach ($p in $real) { $byId["$($p.pid)"] = $p }
$pair = $null
foreach ($p in $real) {
    $par = $byId["$($p.ppid)"]
    if ($par -and $p.ppid -gt 4 -and $par.created -gt $p.created) { $pair = [pscustomobject]@{ orphan = $p; reused = $par }; break }
}
if ($null -eq $pair) {
    Write-Host "  (inconclusive: no process on this machine currently records a reused parent pid - not a pass)" -ForegroundColor Yellow
} else {
    $live = @(Get-HordeDescendantPids -RootPid $pair.reused.pid -Processes $real | ForEach-Object { $_.pid })
    Write-Host ("  found: " + $pair.orphan.name + " " + $pair.orphan.pid + " records parent " + $pair.reused.pid + ", now a younger " + $pair.reused.name) -ForegroundColor DarkGray
    Check (-not ($live -contains $pair.orphan.pid)) "on real data, an orphan whose parent pid was reused is not counted as a descendant"
}

Write-Host ""
Write-Host "--- nothing is killed on its pid alone ---" -ForegroundColor Cyan

# Every process in this section was started by this suite.
$own = Start-OwnPing
Check ($null -ne $own) "PRECONDITION: the suite started a process of its own to test against"
if ($own) {
    Check ((Stop-HordeProcessIfSame -Id $own.pid -Created $own.created.AddSeconds(-5)) -eq "not-same") "a process whose creation time does not match is left alone"
    Check ($null -ne (Get-HordeProcessInfo -Id $own.pid)) "and really is still running afterwards"
    Check ((Stop-HordeProcessIfSame -Id $own.pid -Created $own.created) -eq "killed") "the process we started, with its real creation time, is killed"
    Check ((Stop-HordeProcessIfSame -Id $own.pid -Created $own.created) -eq "gone") "asking again reads as gone, not as killed a second time"
}

Write-Host ""
Write-Host "--- teardown refuses any instance it did not create ---" -ForegroundColor Cyan

$v = Stop-HordeIsolatedWezterm -Instance $null
Check ($null -ne $v -and -not $v.stopped -and $v.refused) "passing no instance returns a refusal, not a claim that something stopped"
Check ("$($v.reason)" -like "*nothing was verified*") "and it says nothing was verified"

$victim = Start-OwnPing
if ($victim) {
    $forged = [pscustomobject]@{ pid = $victim.pid; created = $victim.created; socket = (Join-Path $env:TEMP "horde-no-such-socket")
                                 store = $null; originalSocket = $env:WEZTERM_UNIX_SOCKET; originalRoot = $env:HORDE_ROOT }
    $r1 = Stop-HordeIsolatedWezterm -Instance $forged
    Check ($r1.refused -and -not $r1.stopped) "an instance with no token is refused"
    Check ($null -ne (Get-HordeProcessInfo -Id $victim.pid)) "and the process it named is still running - nothing was killed"
    $forged | Add-Member -NotePropertyName token -NotePropertyValue "horde-iso:1:1" -Force
    $r2 = Stop-HordeIsolatedWezterm -Instance $forged
    Check ($r2.refused) "an instance with a forged token is refused"
    [void](Stop-HordeProcessIfSame -Id $victim.pid -Created $victim.created)
}

# A GENUINE INSTANCE WHOSE TERMINAL IS ALREADY GONE, built from a process this suite started and then
# stopped itself. Teardown must read it as stopped, kill nothing else, and put the environment back -
# and the environment is CHANGED first, so the restore is actually tested. The first version of this
# check could not fail: it restored the very values that were already in place.
$gone = Start-OwnPing
if ($gone) {
    $wantSock = "C:\horde-test\original-socket"; $wantRoot = "C:\horde-test\original-root"
    $inst = [pscustomobject]@{ pid = $gone.pid; created = $gone.created; socket = (Join-Path $env:TEMP "horde-no-such-socket")
                               store = $null; originalSocket = $wantSock; originalRoot = $wantRoot
                               token = (New-HordeInstanceToken -GuiPid $gone.pid -Created $gone.created) }
    [void](Stop-HordeProcessIfSame -Id $gone.pid -Created $gone.created)
    $keepSock = $env:WEZTERM_UNIX_SOCKET; $keepRoot = $env:HORDE_ROOT
    $env:WEZTERM_UNIX_SOCKET = "C:\horde-test\something-else"; $env:HORDE_ROOT = "C:\horde-test\something-else"
    $r3 = Stop-HordeIsolatedWezterm -Instance $inst
    Check ($r3.stopped -and -not $r3.survived -and -not $r3.refused) "a valid instance whose terminal is already gone reads as stopped"
    Check (@($r3.orphansKilled).Count -eq 0) "and nothing else is killed on its behalf"
    Check ("$env:WEZTERM_UNIX_SOCKET" -eq $wantSock -and "$env:HORDE_ROOT" -eq $wantRoot) "teardown restores the pin and the store it was given, even when something else changed them in between"
    $env:WEZTERM_UNIX_SOCKET = $keepSock; $env:HORDE_ROOT = $keepRoot
}

Write-Host ""
Write-Host "--- finding what ran inside a process, on a real process tree this suite started ---" -ForegroundColor Cyan

$tree = Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", "ping -n 30 127.0.0.1 >nul") -PassThru -WindowStyle Hidden
Start-Sleep -Milliseconds 1500
$treeInfo = Get-HordeProcessInfo -Id $tree.Id
$found = @(Get-HordeDescendantPids -RootPid $tree.Id)
$pings = @($found | Where-Object { (Get-HordeProcessInfo -Id $_.pid).name -eq "PING.EXE" })
Check ($pings.Count -ge 1) "the walker finds the child that ran inside the process"
# Cleanup kills only what this suite started, each by pid AND creation time.
foreach ($x in $found) { [void](Stop-HordeProcessIfSame -Id $x.pid -Created $x.created) }
if ($treeInfo) { [void](Stop-HordeProcessIfSame -Id $treeInfo.pid -Created $treeInfo.created) }

Write-Host ""
Write-Host "--- the CLI can never start a server by accident ---" -ForegroundColor Cyan

# Every wezterm CLI call in the harness goes through one function that adds --no-auto-start. Without
# that flag, a call aimed at a socket that is not answering may start a mux that loads the user's
# config - the thing --skip-config exists to prevent.
$harnessCode = ((Get-Content -LiteralPath (Join-Path $root "test\harness\Isolation.ps1")) | Where-Object { -not $_.TrimStart().StartsWith("#") }) -join "`n"
Check ($harnessCode -match '\$script:HordeIsoCli = @\("cli", "--no-auto-start"\)') "every CLI call in the harness passes --no-auto-start"
$rawCli = @(([regex]::Matches($harnessCode, '& wezterm @\(')) | ForEach-Object { $_.Value })
Check ($rawCli.Count -eq 1) "and the one place that calls wezterm directly is the function that adds it"
Check (-not ($harnessCode -match '& wezterm cli ')) "no other line calls the wezterm CLI without it"

Write-Host ""
Write-Host "--- every script that starts an instance also tears it down, by the real name ---" -ForegroundColor Cyan

# The old system's leak on 2026-09-29 was a NAME: a probe called a teardown function that did not
# exist, so the teardown never ran and nothing inside it could have helped. This guards the class.
#
# $PSCommandPath, NOT $MyInvocation, to exclude this file: inside a Where-Object block $MyInvocation
# describes that block, and the first version of this check counted this very file as a starter.
$self = $PSCommandPath
function Get-CodeOnly { param([string]$Path)
    return ((Get-Content -LiteralPath $Path) | Where-Object { -not $_.TrimStart().StartsWith("#") }) -join "`n" }
$scripts = @(Get-ChildItem -Path $root -Recurse -Include *.ps1 -File |
    Where-Object { $_.FullName -notlike "*\test\harness\*" -and $_.FullName -ne $self })
Check ($scripts.Count -gt 0) "CONTROL: the scan sees real scripts, so an empty result below would mean something"
Check (@($scripts | Where-Object { $_.FullName -eq $self }).Count -eq 0) "CONTROL: this file is excluded from its own scan"
$starters = @($scripts | Where-Object { (Get-CodeOnly -Path $_.FullName) -match "Start-HordeIsolatedWezterm" })
Check ($starters.Count -gt 0) "CONTROL: the scan finds at least one script that starts an instance"
$missing = @($starters | Where-Object { (Get-CodeOnly -Path $_.FullName) -notmatch "Stop-HordeIsolatedWezterm" })
foreach ($s in $starters) { Write-Host ("  starter: " + $s.Name) -ForegroundColor DarkGray }
Check ($missing.Count -eq 0) "every script that starts an instance calls Stop-HordeIsolatedWezterm by its real name"
Check (-not ("Start-HordeIsolatedWezterm" -match "Stop-HordeIsolatedWezterm")) "CONTROL: the matcher does not confuse the start name for the stop name"

Write-Host ""
if ($fails.Count) {
    Write-Host "==== $($fails.Count) FAILURE(S) ====" -ForegroundColor Red
    $fails | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host "==== the harness refuses a terminal, or a process, it did not start ====" -ForegroundColor Green
exit 0
