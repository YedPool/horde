# DOES THE ISOLATION HARNESS REFUSE TO TOUCH A TERMINAL - OR ANY PROCESS - IT DID NOT START?
#
# The fast half of the harness's tests: nothing here launches a terminal. The end-to-end half, which
# does, is hosts/wezterm/test/e2e/e2e-isolation.ps1.
#
# THIS SUITE NEVER KILLS A PROCESS IT DID NOT START ITSELF. An independent review of its first version
# found that it did: it handed a stray pid to the teardown, which force-killed that pid and everything
# the process walker believed descended from it - and the walker could wander into unrelated processes
# through reused parent pids. Kill safety is now proven only on processes this file launches, and the
# pid-reuse case is proven on an injected process table, where nothing real can be harmed.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
# This file lives in hosts/wezterm/test/ (D12: host-specific test tooling lives with its host), so
# the repository root is three levels up, and the harness is beside it.
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
$harnessPath = Join-Path $here "Isolation.ps1"
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
# If the harness does not load, stop here with no [FAIL] line: every check below would otherwise fail
# for that one reason, and a mutation run would read a harness that no longer loads as a catch.
try { . $harnessPath } catch { Write-Host ("  the harness did not load: " + $_.Exception.Message); exit 3 }
# EVERY PROCESS THIS SUITE STARTS IS HELD, AND ONLY THOSE MAY BE KILLED.
#
# The third review found that mutation testing ran deliberately broken kill code against real
# processes: a mutant walker handed teardown whatever it found, and teardown killed it. So:
#   - every process the suite starts is created through the process API, which keeps its handle from
#     the moment of creation - its pid can never be reused while the suite runs;
#   - every kill the harness makes during this suite goes through $guard, which kills only a pid in
#     that held set, and records - never kills - anything else.
# A broken walker therefore turns into a failed check, not a killed stranger.
$script:ownProcs = New-Object System.Collections.ArrayList
$script:violations = New-Object System.Collections.ArrayList
$script:guardSaw = New-Object System.Collections.ArrayList
$guard = { param($Id, $Created)
    [void]$script:guardSaw.Add([int]$Id)
    if (@($script:ownProcs | Where-Object { $_.Id -eq $Id }).Count -eq 0) { [void]$script:violations.Add([int]$Id); return "refused-by-test" }
    return (Stop-HordeProcessIfSame -Id $Id -Created $Created) }

function Start-OwnProcess {
    # Start a process and hold it. Returns { pid; created; name; proc }. It shares this suite's console
    # (so it gets no console-host child of its own) and its output is drained and discarded.
    param([string]$File, [string]$Arguments)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $File
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.BeginOutputReadLine()
    $p.BeginErrorReadLine()
    [void]$script:ownProcs.Add($p)
    return [pscustomobject]@{ pid = $p.Id; created = $p.StartTime; name = [System.IO.Path]::GetFileName($File); proc = $p }
}
function Start-OwnPing { param([int]$Seconds = 60) return (Start-OwnProcess -File "ping.exe" -Arguments ("-n " + $Seconds + " 127.0.0.1")) }
function Stop-Own { param($Own) if ($Own -and -not $Own.proc.HasExited) { try { $Own.proc.Kill() } catch { }; [void]$Own.proc.WaitForExit(5000) } }
function Hold-OwnChild {
    # A child of a process this suite holds, found by its parent link AND created after that parent -
    # decided here, independently of the code under test - and then held too.
    param($Parent, [string]$Name, [int]$WaitMs = 3000)
    $deadline = (Get-Date).AddMilliseconds($WaitMs)
    while ((Get-Date) -lt $deadline) {
        foreach ($c in @(Get-HordeProcessTable | Where-Object { $_.ppid -eq $Parent.pid -and $_.name -eq $Name })) {
            if ((Get-HordeMicroseconds $c.created) -lt (Get-HordeMicroseconds $Parent.created)) { continue }
            try { $h = [System.Diagnostics.Process]::GetProcessById($c.pid) } catch { continue }
            $hh = $null; try { $hh = $h.Handle } catch { $hh = $null }
            if ($null -eq $hh -or $hh -eq [IntPtr]::Zero) { $h.Dispose(); continue }
            if ((Get-HordeMicroseconds $h.StartTime) -ne (Get-HordeMicroseconds $c.created)) { $h.Dispose(); continue }
            [void]$script:ownProcs.Add($h)
            return [pscustomobject]@{ pid = $c.pid; created = $c.created; name = $Name; proc = $h }
        }
        Start-Sleep -Milliseconds 100
    }
    return $null
}

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
$d = @(Get-HordeDescendantPids -RootPid 100 -RootCreated $t0.AddMinutes(10) -Processes $table | ForEach-Object { $_.pid })
Check ($d -contains 200 -and $d -contains 400) "a child created after its parent is found, and so is its own child"
Check (-not ($d -contains 300)) "a process created before its recorded parent is not treated as that parent's child - the pid was reused"
Check (-not ($d -contains 500)) "and nothing below that orphan is reached either"
Check (-not ($d -contains 100)) "the root is not listed as its own descendant"

# THE ROOT'S OWN PID REUSED. Our root (pid 100, created at +10) has died, and pid 100 now belongs to
# an unrelated process created at +50, which has a child of its own. An orphan of ours (800) is in the
# table too - and it cannot be told apart from the stranger's children by any rule over times, so the
# walker returns NOTHING rather than guess.
$reused = @(
    [pscustomobject]@{ pid = 100; ppid = 1;   name = "someone-else.exe"; created = $t0.AddMinutes(50) },
    [pscustomobject]@{ pid = 900; ppid = 100; name = "their-child.exe";  created = $t0.AddMinutes(60) },
    [pscustomobject]@{ pid = 800; ppid = 100; name = "our-orphan.exe";   created = $t0.AddMinutes(20) },
    [pscustomobject]@{ pid = 810; ppid = 800; name = "our-grandchild.exe"; created = $t0.AddMinutes(21) }
)
$r = @(Get-HordeDescendantPids -RootPid 100 -RootCreated $t0.AddMinutes(10) -Processes $reused | ForEach-Object { $_.pid })
Check (-not ($r -contains 900)) "when our root's own pid has been reused, the new owner's child is never returned"
Check ($r.Count -eq 0) "and nothing else is returned either - with the pid taken by a stranger, nothing can be attributed"

# THE SECOND RE-REVIEW'S CASE: pid 100 was reused by a launcher W (+16) that started the user's app Y
# (+17) and exited. Y records parent 100 and was created after our root. With no owner at all, and
# with a later one, the old rule returned Y and its child. Without a pin, nothing is returned.
$launcherGone = @(
    [pscustomobject]@{ pid = 700; ppid = 100; name = "users-app.exe";   created = $t0.AddMinutes(17) },
    [pscustomobject]@{ pid = 710; ppid = 700; name = "users-app-child.exe"; created = $t0.AddMinutes(18) }
)
$r2 = @(Get-HordeDescendantPids -RootPid 100 -RootCreated $t0.AddMinutes(10) -Processes $launcherGone | ForEach-Object { $_.pid })
Check ($r2.Count -eq 0) "a dead root that nobody holds a handle to has no orphans attributed to it - the pid may have been reused in between"
$laterOwner = @($launcherGone) + @([pscustomobject]@{ pid = 100; ppid = 1; name = "later.exe"; created = $t0.AddMinutes(30) })
$r3 = @(Get-HordeDescendantPids -RootPid 100 -RootCreated $t0.AddMinutes(10) -Processes $laterOwner | ForEach-Object { $_.pid })
Check ($r3.Count -eq 0) "and neither does one whose pid a later process now holds"

# WITH THE PIN, orphans ARE attributed: a handle held since the root was adopted means nobody else can
# have held its pid, so everything recording it as parent and created after it is ours.
$pinned = @(
    [pscustomobject]@{ pid = 800; ppid = 100; name = "our-orphan.exe";     created = $t0.AddMinutes(20) },
    [pscustomobject]@{ pid = 810; ppid = 800; name = "our-grandchild.exe"; created = $t0.AddMinutes(21) },
    [pscustomobject]@{ pid = 300; ppid = 100; name = "older.exe";          created = $t0.AddMinutes(1) }
)
$r4 = @(Get-HordeDescendantPids -RootPid 100 -RootCreated $t0.AddMinutes(10) -RootPinned -Processes $pinned | ForEach-Object { $_.pid })
Check ($r4 -contains 800 -and $r4 -contains 810) "a pinned dead root's orphans are found, with their children"
Check (-not ($r4 -contains 300)) "but not a process created before the root"

# The root read through .NET and through CIM can differ below a microsecond; the walk must not care.
$d2 = @(Get-HordeDescendantPids -RootPid 100 -RootCreated $t0.AddMinutes(10).AddTicks(3) -Processes $table | ForEach-Object { $_.pid })
Check ($d2 -contains 200) "a root creation time a few ticks off still identifies the live root"

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
    $live = @(Get-HordeDescendantPids -RootPid $pair.reused.pid -RootCreated $pair.reused.created -Processes $real | ForEach-Object { $_.pid })
    Write-Host ("  found: " + $pair.orphan.name + " " + $pair.orphan.pid + " records parent " + $pair.reused.pid + ", now a younger " + $pair.reused.name) -ForegroundColor DarkGray
    Check (-not ($live -contains $pair.orphan.pid)) "on real data, an orphan whose parent pid was reused is not counted as a descendant"
}

Write-Host ""
Write-Host "--- nothing is killed on its pid alone ---" -ForegroundColor Cyan

# ONE PROCESS, TWO READINGS, ONE ANSWER. The kill compares a creation time read through CIM with one
# read through .NET. The first version converted with floating-point division and the two disagreed
# for most processes on this machine, so the harness refused to kill its own. Checked on every
# process that both readings can see, and on a fixed pair a double cannot tell apart from its
# neighbour, so the check does not depend on what happens to be running.
$pairA = [datetime]::new([long]639262197519343380, [DateTimeKind]::Utc)
$pairB = [datetime]::new([long]639262197519343387, [DateTimeKind]::Utc)
Check ((Get-HordeMicroseconds $pairA) -eq (Get-HordeMicroseconds $pairB)) "two times within the same microsecond convert to the same value"
Check ((Get-HordeMicroseconds $pairA) -ne (Get-HordeMicroseconds $pairA.AddTicks(10))) "CONTROL: two times a microsecond apart do not"
$agree = 0; $disagree = 0
foreach ($c in @(Get-HordeProcessTable)) {
    $st = $null
    try { $st = ([System.Diagnostics.Process]::GetProcessById($c.pid)).StartTime } catch { continue }
    if (-not $c.created -or -not $st) { continue }
    if ((Get-HordeMicroseconds $c.created) -eq (Get-HordeMicroseconds $st)) { $agree++ } else { $disagree++ }
}
Write-Host ("  measured: " + $agree + " processes agree, " + $disagree + " disagree") -ForegroundColor DarkGray
Check ($agree -gt 10 -and $disagree -eq 0) "the CIM and .NET creation times of every readable process agree to the microsecond"

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

$v = Stop-HordeIsolatedWezterm -Instance $null -KillWith $guard
Check ($null -ne $v -and -not $v.stopped -and $v.refused) "passing no instance returns a refusal, not a claim that something stopped"
Check ("$($v.reason)" -like "*nothing was verified*") "and it says nothing was verified"

$victim = Start-OwnPing
if ($victim) {
    $forged = [pscustomobject]@{ pid = $victim.pid; created = $victim.created; socket = (Join-Path $env:TEMP ("horde-no-such-socket-" + [guid]::NewGuid().ToString("N")))
                                 store = $null; originalSocket = $env:WEZTERM_UNIX_SOCKET; originalRoot = $env:HORDE_ROOT }
    $r1 = Stop-HordeIsolatedWezterm -Instance $forged -KillWith $guard
    Check ($r1.refused -and -not $r1.stopped) "an instance with no token is refused"
    Check ($null -ne (Get-HordeProcessInfo -Id $victim.pid)) "and the process it named is still running - nothing was killed"
    $forged | Add-Member -NotePropertyName token -NotePropertyValue "horde-iso:1:1" -Force
    $r2 = Stop-HordeIsolatedWezterm -Instance $forged -KillWith $guard
    Check ($r2.refused) "an instance with a forged token is refused"
    # A token in exactly the shape Start issues, computed by hand from the victim's real pid and
    # creation time. The first version accepted this, because it only recomputed the token from the
    # object it was handed. Only a token this process registered counts.
    $shaped = "horde-iso:" + $victim.pid + ":" + (Get-HordeMicroseconds $victim.created) + ":" + [guid]::NewGuid().ToString("N")
    $forged | Add-Member -NotePropertyName token -NotePropertyValue $shaped -Force
    $r2b = Stop-HordeIsolatedWezterm -Instance $forged -KillWith $guard
    Check ($r2b.refused -and -not $r2b.stopped) "a correctly shaped token that this process never registered is refused"
    Check ($null -ne (Get-HordeProcessInfo -Id $victim.pid)) "and the process it named is still running after that too"
    # REGISTERED, BUT NOT A WEZTERM. Teardown must refuse to kill a live process that is not a
    # wezterm-gui, even when this process registered it - the one registration made outside Start.
    $notWez = Register-HordeIsolatedInstance -GuiPid $victim.pid -Created $victim.created -Socket "" -Store ""
    $inst0 = [pscustomobject]@{ token = $notWez; originalSocket = $env:WEZTERM_UNIX_SOCKET; originalRoot = $env:HORDE_ROOT }
    $r2c = Stop-HordeIsolatedWezterm -Instance $inst0 -KillWith $guard
    Check ($r2c.refused -and "$($r2c.reason)" -like "*not a WezTerm*") "a registered process that is not a WezTerm is refused, not killed"
    Check ($null -ne (Get-HordeProcessInfo -Id $victim.pid)) "and that process is still running afterwards"
    Stop-Own $victim
}

# REGISTRATION PINS, AND REFUSES A PROCESS IT CANNOT PROVE. A creation time that does not match means
# the pid is not the process described, and nothing is registered.
$wrongTime = Start-OwnPing
if ($wrongTime) {
    Check (Throws { Register-HordeIsolatedInstance -GuiPid $wrongTime.pid -Created $wrongTime.created.AddSeconds(-5) -Socket "" } "refusing to register") "registering a pid whose creation time does not match is refused"
    Stop-Own $wrongTime
}

# LOADING THE HARNESS AGAIN MUST NOT FORGET WHAT IT STARTED. The first version reset the registry on
# every dot-source, after which teardown refused - and so leaked - every live instance.
$again = Start-OwnPing
if ($again) {
    $tokA = Register-HordeIsolatedInstance -GuiPid $again.pid -Created $again.created -Socket "" -OriginalSocket "$env:WEZTERM_UNIX_SOCKET" -OriginalRoot "$env:HORDE_ROOT"
    Stop-Own $again
    . $harnessPath
    $rA = Stop-HordeIsolatedWezterm -Instance ([pscustomobject]@{ token = $tokA }) -KillWith $guard
    Check (-not $rA.refused -and $rA.stopped) "loading the harness a second time does not forget an instance it already started"
}

# A GENUINE INSTANCE WHOSE TERMINAL IS ALREADY GONE, built from a process this suite started and then
# stopped itself. Teardown must read it as stopped, kill nothing else, and put the environment back -
# the environment REGISTRATION recorded, not what the object handed to teardown claims. Both are made
# to differ from what is current, so the restore is actually tested.
$gone = Start-OwnPing
if ($gone) {
    $wantSock = "C:\horde-test\original-socket"; $wantRoot = "C:\horde-test\original-root"
    $tok = Register-HordeIsolatedInstance -GuiPid $gone.pid -Created $gone.created -Socket (Join-Path $env:TEMP ("horde-no-such-socket-" + [guid]::NewGuid().ToString("N"))) -OriginalSocket $wantSock -OriginalRoot $wantRoot
    $inst = [pscustomobject]@{ token = $tok; originalSocket = "C:\horde-test\from-the-object"; originalRoot = "C:\horde-test\from-the-object" }
    Stop-Own $gone
    $keepSock = $env:WEZTERM_UNIX_SOCKET; $keepRoot = $env:HORDE_ROOT
    $env:WEZTERM_UNIX_SOCKET = "C:\horde-test\something-else"; $env:HORDE_ROOT = "C:\horde-test\something-else"
    $r3 = Stop-HordeIsolatedWezterm -Instance $inst -KillWith $guard
    Check ($r3.stopped -and -not $r3.survived -and -not $r3.refused) "a valid instance whose terminal is already gone reads as stopped"
    Check ("$env:WEZTERM_UNIX_SOCKET" -eq $wantSock -and "$env:HORDE_ROOT" -eq $wantRoot) "teardown restores the environment registration recorded, not what the object handed to it says"
    $env:WEZTERM_UNIX_SOCKET = $keepSock; $env:HORDE_ROOT = $keepRoot
    $r3b = Stop-HordeIsolatedWezterm -Instance $inst -KillWith $guard
    Check ($r3b.refused) "a token is spent once used - the same instance cannot be torn down twice"
}

# TEARDOWN DELETES ONLY WHAT IS PROVABLY OURS. Each bait below was made by this suite, and has the
# right name in the wrong folder or a wrong name in the right folder. The first version deleted
# whatever socket path the instance named.
$sockDir = Join-Path $env:USERPROFILE ".local\share\wezterm"
$gone2 = Start-OwnPing
if ($gone2) {
    $bait = Join-Path $env:TEMP ("horde-bait-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    [void](New-Item -ItemType Directory -Path $bait)
    $fakeSock = Join-Path $bait ("gui-sock-" + $gone2.pid)
    $fakeStore = Join-Path $bait ("horde-iso-store-" + [guid]::NewGuid().ToString("N"))
    Set-Content -LiteralPath $fakeSock -Value "not a socket"
    [void](New-Item -ItemType Directory -Path $fakeStore)
    $tok2 = Register-HordeIsolatedInstance -GuiPid $gone2.pid -Created $gone2.created -Socket $fakeSock -Store $fakeStore -OriginalSocket "$env:WEZTERM_UNIX_SOCKET" -OriginalRoot "$env:HORDE_ROOT"
    Stop-Own $gone2
    $r4 = Stop-HordeIsolatedWezterm -Instance ([pscustomobject]@{ token = $tok2 }) -KillWith $guard
    Check (Test-Path -LiteralPath $fakeSock) "a socket file named like ours but outside WezTerm's socket folder is not deleted"
    Check (Test-Path -LiteralPath $fakeStore) "a store named like ours but outside the temp folder itself is not deleted"
    Check (-not $r4.socketRemoved) "and teardown reports the socket as not removed rather than claiming it"
    Remove-Item -LiteralPath $bait -Recurse -Force -ErrorAction SilentlyContinue
}
$gone3 = Start-OwnPing
if ($gone3) {
    $wrongName = Join-Path $env:TEMP ("horde-bait-store-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    [void](New-Item -ItemType Directory -Path $wrongName)
    # WezTerm ignores files in its socket folder that it does not recognise; this one is removed below.
    $wrongSock = $null
    if (Test-Path -LiteralPath $sockDir) {
        $wrongSock = Join-Path $sockDir ("horde-bait-sock-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
        Set-Content -LiteralPath $wrongSock -Value "not a socket"
    }
    $tok3 = Register-HordeIsolatedInstance -GuiPid $gone3.pid -Created $gone3.created -Socket "$wrongSock" -Store $wrongName -OriginalSocket "$env:WEZTERM_UNIX_SOCKET" -OriginalRoot "$env:HORDE_ROOT"
    Stop-Own $gone3
    [void](Stop-HordeIsolatedWezterm -Instance ([pscustomobject]@{ token = $tok3 }) -KillWith $guard)
    Check (Test-Path -LiteralPath $wrongName) "a store in the temp folder itself but not named like ours is not deleted"
    Remove-Item -LiteralPath $wrongName -Recurse -Force -ErrorAction SilentlyContinue
    if ($wrongSock) {
        Check (Test-Path -LiteralPath $wrongSock) "a file in WezTerm's socket folder not named for our pid is not deleted"
        Remove-Item -LiteralPath $wrongSock -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "  (inconclusive: this machine has no WezTerm socket folder - the socket-name rule is untested here)" -ForegroundColor Yellow
    }
}

# AND THE POSITIVE CONTROL: what IS ours is deleted. Without this every check above would pass for a
# teardown that never deleted anything. The socket name is safe to create: it names the pid of a ping
# this suite started and still holds a handle to, so no WezTerm can have that pid.
$gone4 = Start-OwnPing
if ($gone4 -and (Test-Path -LiteralPath $sockDir) -and -not (Test-Path -LiteralPath (Join-Path $sockDir ("gui-sock-" + $gone4.pid)))) {
    $ownSock = Join-Path $sockDir ("gui-sock-" + $gone4.pid)
    $ownStore = Join-Path $env:TEMP ("horde-iso-store-" + [guid]::NewGuid().ToString("N"))
    Set-Content -LiteralPath $ownSock -Value "stands in for a socket"
    [void](New-Item -ItemType Directory -Path $ownStore)
    $tok4 = Register-HordeIsolatedInstance -GuiPid $gone4.pid -Created $gone4.created -Socket $ownSock -Store $ownStore -OriginalSocket "$env:WEZTERM_UNIX_SOCKET" -OriginalRoot "$env:HORDE_ROOT"
    Stop-Own $gone4
    $r5 = Stop-HordeIsolatedWezterm -Instance ([pscustomobject]@{ token = $tok4 }) -KillWith $guard
    Check (-not (Test-Path -LiteralPath $ownSock) -and $r5.socketRemoved) "our own socket file is deleted, and reported as removed"
    Check (-not (Test-Path -LiteralPath $ownStore)) "our own throwaway store is deleted"
    Remove-Item -LiteralPath $ownSock, $ownStore -Recurse -Force -ErrorAction SilentlyContinue
} elseif ($gone4) {
    Stop-Own $gone4
    Write-Host "  (inconclusive: this machine has no WezTerm socket folder - the positive control did not run)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "--- finding what ran inside a process, on a real process tree this suite started ---" -ForegroundColor Cyan

# The walker's answer is only CHECKED here, never acted on. The processes are stopped through the
# handles this suite holds, so a broken walker cannot make this section kill anything else.
$tree = Start-OwnProcess -File "cmd.exe" -Arguments "/c ping -n 30 127.0.0.1 >nul"
$treePing = Hold-OwnChild -Parent $tree -Name "PING.EXE"
Check ($null -ne $treePing) "PRECONDITION: the suite holds the ping its own cmd started"
$found = @(Get-HordeDescendantPids -RootPid $tree.pid -RootCreated $tree.created | ForEach-Object { $_.pid })
Check ($null -ne $treePing -and $found -contains $treePing.pid) "the walker finds the child that ran inside the process"
Stop-Own $treePing; Stop-Own $tree

Write-Host ""
Write-Host "--- a terminal that died first: its orphans are still found and killed ---" -ForegroundColor Cyan

# A registered root that has ALREADY died, with a child still running. Teardown must find the orphan
# through the pin and kill it. Without the pin, or without the orphan kill, the child leaks - both were
# mutations the third review found no test would notice.
$dead = Start-OwnProcess -File "cmd.exe" -Arguments "/c ping -n 60 127.0.0.1 >nul"
$orphan = Hold-OwnChild -Parent $dead -Name "PING.EXE"
if ($orphan) {
    $tokO = Register-HordeIsolatedInstance -GuiPid $dead.pid -Created $dead.created -Socket "" -OriginalSocket "$env:WEZTERM_UNIX_SOCKET" -OriginalRoot "$env:HORDE_ROOT"
    Stop-Own $dead
    $script:guardSaw.Clear()
    $rO = Stop-HordeIsolatedWezterm -Instance ([pscustomobject]@{ token = $tokO }) -KillWith $guard
    # THE GUARD IS REALLY IN THE PATH. Every other safety claim in this suite rests on every harness
    # kill passing through $guard; the fourth review found nothing tested that it does.
    Check (@($script:guardSaw) -contains $dead.pid -and @($script:guardSaw) -contains $orphan.pid) "every kill teardown makes passes through the test's guard"
    Check (@($rO.orphansKilled) -contains $orphan.pid -and $orphan.proc.HasExited) "the child of a terminal that already died is found through the pin and killed"
    Stop-Own $orphan
} else { Check $false "PRECONDITION: the suite holds the orphan-to-be" }

Write-Host ""
Write-Host "--- tearing down a launch: only the launcher we recorded ---" -ForegroundColor Cyan

$launch = Start-OwnProcess -File "cmd.exe" -Arguments "/c ping -n 60 127.0.0.1 >nul"
$launchChild = Hold-OwnChild -Parent $launch -Name "PING.EXE"
Stop-HordeLaunchTree -Launcher $launch.proc -LauncherUs ((Get-HordeMicroseconds $launch.created) - 1) -KillWith $guard
Check (-not $launch.proc.HasExited) "a launcher whose start time is not the one recorded is left alone"
Stop-HordeLaunchTree -Launcher $launch.proc -LauncherUs (Get-HordeMicroseconds $launch.created) -KillWith $guard
Start-Sleep -Milliseconds 300
Check ($launch.proc.HasExited -and $null -ne $launchChild -and $launchChild.proc.HasExited) "the recorded launcher and everything it started are stopped"
Stop-Own $launchChild; Stop-Own $launch

Write-Host ""
Write-Host "--- adopting only the terminal our launcher started ---" -ForegroundColor Cyan

$lt = Get-Date "2026-09-29T12:00:00"
$lus = Get-HordeMicroseconds $lt
$gui = [pscustomobject]@{ pid = 50; ppid = 40; name = "wezterm-gui.exe"; created = $lt.AddSeconds(1) }
Check (Test-HordeAdoptableGui -Gui $gui -LauncherPid 40 -LauncherUs $lus) "CONTROL: the gui our launcher started is adopted"
Check (-not (Test-HordeAdoptableGui -Gui ([pscustomobject]@{ pid = 51; ppid = 99; name = "wezterm-gui.exe"; created = $lt.AddSeconds(1) }) -LauncherPid 40 -LauncherUs $lus)) "a gui with another parent is not adopted"
Check (-not (Test-HordeAdoptableGui -Gui ([pscustomobject]@{ pid = 52; ppid = 40; name = "wezterm-gui.exe"; created = $lt.AddSeconds(-1) }) -LauncherPid 40 -LauncherUs $lus)) "a gui older than our launcher is not adopted, though it records the launcher's pid"
Check (-not (Test-HordeAdoptableGui -Gui ([pscustomobject]@{ pid = 53; ppid = 40; name = "cmd.exe"; created = $lt.AddSeconds(1) }) -LauncherPid 40 -LauncherUs $lus)) "a process that is not a wezterm-gui is not adopted"

Write-Host ""
Write-Host "--- the CLI can never start a server by accident ---" -ForegroundColor Cyan

# Every wezterm CLI call in the harness goes through one function that adds --no-auto-start. Without
# that flag, a call aimed at a socket that is not answering may start a mux that loads the user's
# config - the thing --skip-config exists to prevent.
$harnessCode = ((Get-Content -LiteralPath $harnessPath) | Where-Object { -not $_.TrimStart().StartsWith("#") }) -join "`n"
Check ($harnessCode -match '\$script:HordeIsoCli = @\("cli", "--no-auto-start"\)') "every CLI call in the harness passes --no-auto-start"
$rawCli = @(([regex]::Matches($harnessCode, '& wezterm @\(')) | ForEach-Object { $_.Value })
Check ($rawCli.Count -eq 1) "and the one place that calls wezterm directly is the function that adds it"
Check (-not ($harnessCode -match '& wezterm cli ')) "no other line calls the wezterm CLI without it"

# AND NOT ONLY IN THE HARNESS. The checks above read Isolation.ps1 alone, so a raw call added to any
# other script - an e2e scenario, a tool, a future host adapter - passed them. wezfleet issue #52,
# measured 2026-09-30: one `wezterm cli list` aimed at a dead socket left a mux server running with
# its parent already gone (0 -> 1; with --no-auto-start 0 -> 0), and a call that captured the output
# blocked for about six and a half minutes because the server inherited the pipe. Four such orphans
# were found on the machine that day. So the whole repository is read here, as a parse tree: a
# `wezterm` command anywhere but inside Invoke-HordeWeztermCli fails, and so does a process started
# by hand with a cli argument list. Starting a gui with `start` is allowed - the harness owns and
# reaps it. Comments and strings are not commands, so they are not flagged.
function Find-HordeRawWeztermCall {
    # -> one row per call that bypasses the helper: { line; text }. $Text is a whole script.
    param([string]$Text)
    $tok = $null; $err = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tok, [ref]$err)
    $rows = @()
    foreach ($c in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))) {
        $name = $c.GetCommandName()
        if (-not $name -or (Split-Path -Leaf $name) -notmatch '^wezterm(\.exe)?$') { continue }
        $p = $c.Parent; $inHelper = $false
        while ($p) {
            if ($p -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $p.Name -eq "Invoke-HordeWeztermCli") { $inHelper = $true; break }
            $p = $p.Parent
        }
        if (-not $inHelper) { $rows += [pscustomobject]@{ line = $c.Extent.StartLineNumber; text = $c.Extent.Text } }
    }
    # A ProcessStartInfo for wezterm whose arguments reach the CLI.
    foreach ($a in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                                              $n.Left.Extent.Text -match '\.Arguments$' }, $true))) {
        if ($a.Right.Extent.Text -match '(^|["''\s])cli(["''\s]|$)') {
            $block = $a.Parent
            while ($block -and -not ($block -is [System.Management.Automation.Language.ScriptBlockAst] -or
                                     $block -is [System.Management.Automation.Language.NamedBlockAst])) { $block = $block.Parent }
            if ($block -and $block.Extent.Text -match '\.FileName\s*=\s*["'']wezterm(\.exe)?["'']') {
                $rows += [pscustomobject]@{ line = $a.Extent.StartLineNumber; text = $a.Extent.Text }
            }
        }
    }
    return $rows
}

# THE PLANTED CALL: the same line, once raw and once through the helper. The detector must fail the
# first and pass the second, or the repository scan below proves nothing.
$plantedRaw = "function Get-Panes {`n    return (& wezterm cli list --format json 2>`$null)`n}`n"
$plantedRouted = "function Get-Panes {`n    return (Invoke-HordeWeztermCli -Rest @(`"list`", `"--format`", `"json`"))`n}`n"
Check (@(Find-HordeRawWeztermCall -Text $plantedRaw).Count -eq 1) "CONTROL: a raw wezterm cli call planted outside the helper is found"
Check (@(Find-HordeRawWeztermCall -Text $plantedRouted).Count -eq 0) "CONTROL: the same call routed through Invoke-HordeWeztermCli is not"
Check (@(Find-HordeRawWeztermCall -Text "`$psi.FileName = `"wezterm`"`n`$psi.Arguments = `"cli list`"`n").Count -eq 1) "CONTROL: a hand-started process running the CLI is found"
Check (@(Find-HordeRawWeztermCall -Text "`$psi.FileName = `"wezterm`"`n`$psi.Arguments = `"--skip-config start --always-new-process`"`n").Count -eq 0) "CONTROL: a hand-started gui (``start``) is not"
Check (@(Find-HordeRawWeztermCall -Text "# & wezterm cli list`nWrite-Host `"& wezterm cli list`"`n").Count -eq 0) "CONTROL: a comment or a string naming the call is not"

$allScripts = @(Get-ChildItem -Path $root -Recurse -Include *.ps1 -File | Where-Object { $_.FullName -notmatch '\\\.git\\' })
$rawAnywhere = @()
foreach ($f in $allScripts) {
    foreach ($r in @(Find-HordeRawWeztermCall -Text ([System.IO.File]::ReadAllText($f.FullName)))) {
        $rawAnywhere += ("{0}:{1}: {2}" -f $f.FullName.Substring($root.Length + 1), $r.line, ($r.text -replace '\s+', ' '))
    }
}
foreach ($x in $rawAnywhere) { Write-Host ("         raw: " + $x) -ForegroundColor Red }
Check ($allScripts.Count -gt 20) ("CONTROL: the repository scan reads real scripts ({0})" -f $allScripts.Count)
Check (@($allScripts | Where-Object { $_.FullName -eq $harnessPath }).Count -eq 1) "CONTROL: and the harness, whose one raw call is inside the helper, is among them"
Check ($rawAnywhere.Count -eq 0) "no script anywhere in the repository calls the wezterm CLI except through Invoke-HordeWeztermCli"

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
$allScripts = @(Get-ChildItem -Path $root -Recurse -Include *.ps1 -File)
$scripts = @($allScripts | Where-Object { $_.FullName -ne $harnessPath -and $_.FullName -ne $self })
Check ($scripts.Count -gt 0) "CONTROL: the scan sees real scripts, so an empty result below would mean something"
# BY FULL PATH, NOT BY NAME: a second host brought its own test-isolation.ps1, which is a different
# file and belongs in the scan. Matching the name alone failed this control the day it arrived.
# AND NOT A TAUTOLOGY. Filtering by $self and then finding no $self proves nothing if $self is empty
# or names a file the scan never held (the review of PR 35). So: $self is a real path, the UNFILTERED
# scan holds it, it also holds another test-isolation.ps1, and only this file left the scan.
Check ("$self" -ne "" -and @($allScripts | Where-Object { $_.FullName -eq $self }).Count -eq 1) "CONTROL: this file's own path is known, and the unfiltered scan holds it"
$otherIso = @($allScripts | Where-Object { $_.Name -eq "test-isolation.ps1" -and $_.FullName -ne $self })
Check ($otherIso.Count -ge 1 -and @($scripts | Where-Object { $_.Name -eq "test-isolation.ps1" }).Count -eq $otherIso.Count) "CONTROL: another host's test-isolation.ps1 is in the scan too, and stays in it"
Check ($scripts.Count -eq $allScripts.Count - 2 -and @($scripts | Where-Object { $_.FullName -eq $self }).Count -eq 0) "CONTROL: this file, and only it and the harness, is excluded from its own scan"
$starters = @($scripts | Where-Object { (Get-CodeOnly -Path $_.FullName) -match "Start-HordeIsolatedWezterm" })
Check ($starters.Count -gt 0) "CONTROL: the scan finds at least one script that starts an instance"
$missing = @($starters | Where-Object { (Get-CodeOnly -Path $_.FullName) -notmatch "Stop-HordeIsolatedWezterm" })
foreach ($s in $starters) { Write-Host ("  starter: " + $s.Name) -ForegroundColor DarkGray }
Check ($missing.Count -eq 0) "every script that starts an instance calls Stop-HordeIsolatedWezterm by its real name"
Check (-not ("Start-HordeIsolatedWezterm" -match "Stop-HordeIsolatedWezterm")) "CONTROL: the matcher does not confuse the start name for the stop name"

Write-Host ""
Write-Host "--- nothing outside this suite was ever asked to be killed ---" -ForegroundColor Cyan

Check ($script:violations.Count -eq 0) ("the harness asked to kill only processes this suite started (" + (@($script:violations) -join ", ") + ")")

# Everything the suite started is stopped through its own handle, then every handle is released -
# including registry pins left by instances a test deliberately left registered.
foreach ($p in @($script:ownProcs)) { try { if (-not $p.HasExited) { $p.Kill(); [void]$p.WaitForExit(5000) } } catch { }; $p.Dispose() }
foreach ($k in @($script:HordeIsoStarted.Keys)) { $e = $script:HordeIsoStarted[$k]; if ($e.pin) { $e.pin.Dispose() }; $script:HordeIsoStarted.Remove($k) }

Complete-HordeSuite -Success "the harness refuses a terminal, or a process, it did not start"
