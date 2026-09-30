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
# A CONDITION MUST BE EXACTLY TRUE OR FALSE. Anything else fails, loudly. The first Throws below
# returned whatever its block printed AND $false, and PowerShell reads that array as true - so a
# "must be refused" check passed when nothing was refused. A mutation of the refusal survived, which
# is how it was found.
function Check { param($Cond, [string]$What)
    if ($Cond -isnot [bool]) { Write-Host "  [FAIL] $What (the check's condition was not true or false)" -ForegroundColor Red; $script:fails += $What; return }
    if ($Cond) { Write-Host "  [PASS] $What" -ForegroundColor DarkGray }
    else { Write-Host "  [FAIL] $What" -ForegroundColor Red; $script:fails += $What } }
function Throws { param([scriptblock]$Block, [string]$Like)
    try { $null = & $Block; return $false } catch { return ("$($_.Exception.Message)" -like "*$Like*") } }
function Start-OwnPing {
    # A throwaway process this suite owns, identified by pid AND creation time from the moment it exists.
    #
    # IN THIS PROCESS'S OWN CONSOLE, output to a file. Started with a window of its own, ping gets a
    # console host as a CHILD, which outlives ping by a moment - and a teardown test that kills ping
    # and then asserts "nothing else was killed" would kill that console host and fail at random. The
    # re-review found it.
    param([int]$Seconds = 60)
    $out = Join-Path $env:TEMP ("horde-test-ping-" + [guid]::NewGuid().ToString("N") + ".txt")
    $p = Start-Process -FilePath "ping.exe" -ArgumentList @("-n", "$Seconds", "127.0.0.1") -PassThru -NoNewWindow -RedirectStandardOutput $out
    $script:pingOutputs += $out
    Start-Sleep -Milliseconds 300
    return (Get-HordeProcessInfo -Id $p.Id) }
$script:pingOutputs = @()

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
    # A token in exactly the shape Start issues, computed by hand from the victim's real pid and
    # creation time. The first version accepted this, because it only recomputed the token from the
    # object it was handed. Only a token this process registered counts.
    $shaped = "horde-iso:" + $victim.pid + ":" + (Get-HordeMicroseconds $victim.created) + ":" + [guid]::NewGuid().ToString("N")
    $forged | Add-Member -NotePropertyName token -NotePropertyValue $shaped -Force
    $r2b = Stop-HordeIsolatedWezterm -Instance $forged
    Check ($r2b.refused -and -not $r2b.stopped) "a correctly shaped token that this process never registered is refused"
    Check ($null -ne (Get-HordeProcessInfo -Id $victim.pid)) "and the process it named is still running after that too"
    # REGISTERED, BUT NOT A WEZTERM. Teardown must refuse to kill a live process that is not a
    # wezterm-gui, even when this process registered it - the one registration made outside Start.
    $notWez = Register-HordeIsolatedInstance -GuiPid $victim.pid -Created $victim.created -Socket "" -Store ""
    $inst0 = [pscustomobject]@{ token = $notWez; originalSocket = $env:WEZTERM_UNIX_SOCKET; originalRoot = $env:HORDE_ROOT }
    $r2c = Stop-HordeIsolatedWezterm -Instance $inst0
    Check ($r2c.refused -and "$($r2c.reason)" -like "*not a WezTerm*") "a registered process that is not a WezTerm is refused, not killed"
    Check ($null -ne (Get-HordeProcessInfo -Id $victim.pid)) "and that process is still running afterwards"
    [void](Stop-HordeProcessIfSame -Id $victim.pid -Created $victim.created)
}

# REGISTRATION PINS, AND REFUSES A PROCESS IT CANNOT PROVE. A creation time that does not match means
# the pid is not the process described, and nothing is registered.
$wrongTime = Start-OwnPing
if ($wrongTime) {
    Check (Throws { Register-HordeIsolatedInstance -GuiPid $wrongTime.pid -Created $wrongTime.created.AddSeconds(-5) -Socket "" } "refusing to register") "registering a pid whose creation time does not match is refused"
    [void](Stop-HordeProcessIfSame -Id $wrongTime.pid -Created $wrongTime.created)
}

# LOADING THE HARNESS AGAIN MUST NOT FORGET WHAT IT STARTED. The first version reset the registry on
# every dot-source, after which teardown refused - and so leaked - every live instance.
$again = Start-OwnPing
if ($again) {
    $tokA = Register-HordeIsolatedInstance -GuiPid $again.pid -Created $again.created -Socket "" -OriginalSocket "$env:WEZTERM_UNIX_SOCKET" -OriginalRoot "$env:HORDE_ROOT"
    [void](Stop-HordeProcessIfSame -Id $again.pid -Created $again.created)
    . (Join-Path $root "test\harness\Isolation.ps1")
    $rA = Stop-HordeIsolatedWezterm -Instance ([pscustomobject]@{ token = $tokA })
    Check (-not $rA.refused -and $rA.stopped) "loading the harness a second time does not forget an instance it already started"
}

# A GENUINE INSTANCE WHOSE TERMINAL IS ALREADY GONE, built from a process this suite started and then
# stopped itself. Teardown must read it as stopped, kill nothing else, and put the environment back -
# the environment REGISTRATION recorded, not what the object handed to teardown claims. Both are made
# to differ from what is current, so the restore is actually tested.
$gone = Start-OwnPing
if ($gone) {
    $wantSock = "C:\horde-test\original-socket"; $wantRoot = "C:\horde-test\original-root"
    $tok = Register-HordeIsolatedInstance -GuiPid $gone.pid -Created $gone.created -Socket (Join-Path $env:TEMP "horde-no-such-socket") -OriginalSocket $wantSock -OriginalRoot $wantRoot
    $inst = [pscustomobject]@{ token = $tok; originalSocket = "C:\horde-test\from-the-object"; originalRoot = "C:\horde-test\from-the-object" }
    [void](Stop-HordeProcessIfSame -Id $gone.pid -Created $gone.created)
    $keepSock = $env:WEZTERM_UNIX_SOCKET; $keepRoot = $env:HORDE_ROOT
    $env:WEZTERM_UNIX_SOCKET = "C:\horde-test\something-else"; $env:HORDE_ROOT = "C:\horde-test\something-else"
    $r3 = Stop-HordeIsolatedWezterm -Instance $inst
    Check ($r3.stopped -and -not $r3.survived -and -not $r3.refused) "a valid instance whose terminal is already gone reads as stopped"
    Check (@($r3.orphansKilled).Count -eq 0) "and nothing else is killed on its behalf"
    Check ("$env:WEZTERM_UNIX_SOCKET" -eq $wantSock -and "$env:HORDE_ROOT" -eq $wantRoot) "teardown restores the environment registration recorded, not what the object handed to it says"
    $env:WEZTERM_UNIX_SOCKET = $keepSock; $env:HORDE_ROOT = $keepRoot
    $r3b = Stop-HordeIsolatedWezterm -Instance $inst
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
    [void](Stop-HordeProcessIfSame -Id $gone2.pid -Created $gone2.created)
    $r4 = Stop-HordeIsolatedWezterm -Instance ([pscustomobject]@{ token = $tok2 })
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
    [void](Stop-HordeProcessIfSame -Id $gone3.pid -Created $gone3.created)
    [void](Stop-HordeIsolatedWezterm -Instance ([pscustomobject]@{ token = $tok3 }))
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
if ($gone4 -and (Test-Path -LiteralPath $sockDir)) {
    $ownSock = Join-Path $sockDir ("gui-sock-" + $gone4.pid)
    $ownStore = Join-Path $env:TEMP ("horde-iso-store-" + [guid]::NewGuid().ToString("N"))
    Set-Content -LiteralPath $ownSock -Value "stands in for a socket"
    [void](New-Item -ItemType Directory -Path $ownStore)
    $tok4 = Register-HordeIsolatedInstance -GuiPid $gone4.pid -Created $gone4.created -Socket $ownSock -Store $ownStore -OriginalSocket "$env:WEZTERM_UNIX_SOCKET" -OriginalRoot "$env:HORDE_ROOT"
    [void](Stop-HordeProcessIfSame -Id $gone4.pid -Created $gone4.created)
    $r5 = Stop-HordeIsolatedWezterm -Instance ([pscustomobject]@{ token = $tok4 })
    Check (-not (Test-Path -LiteralPath $ownSock) -and $r5.socketRemoved) "our own socket file is deleted, and reported as removed"
    Check (-not (Test-Path -LiteralPath $ownStore)) "our own throwaway store is deleted"
    Remove-Item -LiteralPath $ownSock, $ownStore -Recurse -Force -ErrorAction SilentlyContinue
} elseif ($gone4) {
    [void](Stop-HordeProcessIfSame -Id $gone4.pid -Created $gone4.created)
    Write-Host "  (inconclusive: this machine has no WezTerm socket folder - the positive control did not run)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "--- finding what ran inside a process, on a real process tree this suite started ---" -ForegroundColor Cyan

$tree = Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", "ping -n 30 127.0.0.1 >nul") -PassThru -WindowStyle Hidden
Start-Sleep -Milliseconds 1500
$treeInfo = Get-HordeProcessInfo -Id $tree.Id
$found = @()
if ($treeInfo) { $found = @(Get-HordeDescendantPids -RootPid $tree.Id -RootCreated $treeInfo.created) }
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

# The ping output files this suite wrote.
$script:pingOutputs | ForEach-Object { Remove-Item -LiteralPath $_ -Force -ErrorAction SilentlyContinue }

Write-Host ""
if ($fails.Count) {
    Write-Host "==== $($fails.Count) FAILURE(S) ====" -ForegroundColor Red
    $fails | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host "==== the harness refuses a terminal, or a process, it did not start ====" -ForegroundColor Green
exit 0
