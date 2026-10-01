# END TO END: start real isolated tmux servers in WSL, work inside them, tear them down, and prove that
# they went and that a server of someone else's did not.
#
# Safe to run beside a working tmux: every server this file starts is on a socket named for a fresh
# guid, in a directory made for this run, with no config - see hosts/tmux/test/Isolation.ps1. The
# "user" servers in scenario 3 are started the same way, by this file, so that no real user server is
# ever needed or touched. No agent session is started, so it costs nothing to run.
#
# If WSL, the distro or tmux is missing, this FAILS. An absent host is never a green skip.
#
# -Distro, or HORDE_TMUX_DISTRO, names the WSL distro; empty means WSL's default distro.

param([string]$Distro = "$env:HORDE_TMUX_DISTRO")

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$testDir = Split-Path -Parent $here
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $testDir))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $testDir "Isolation.ps1")

$runGuids = New-Object System.Collections.ArrayList
$distroUsed = $Distro

function Start-UserServer {
    # A server that stands in for the user's own: NOT started through the harness, on a socket name
    # and in a directory the harness never uses. $Dir, when given, is an existing directory to share.
    # Returns { name; dir; socket; line } where line is "socket|pid|start" as the server reports it.
    param([string]$Dir = "")
    $g = [guid]::NewGuid().ToString("N")
    [void]$script:runGuids.Add($g)
    $name = "horde-user-" + $g
    $made = $false
    if (-not $Dir) {
        $Dir = "/tmp/horde-user-" + $g
        $mk = Invoke-HordeWsl -Distro $script:distroUsed -Argv @("mkdir", "-m", "700", "--", $Dir)
        if ($mk.code -ne 0) { throw ("could not make the user server's directory: " + $mk.err) }
        $made = $true
    }
    $u = [pscustomobject]@{ name = $name; dir = $Dir; madeDir = $made; socket = ""; line = "" }
    $base = @("env", "-C", $Dir, "-u", "TMUX", "-u", "TMUX_PANE", ("TMUX_TMPDIR=" + $Dir), "tmux", "-L", $name, "-f", "/dev/null")
    $u | Add-Member -NotePropertyName argv -NotePropertyValue $base
    $n = Invoke-HordeWsl -Distro $script:distroUsed -Argv ($base + @("new-session", "-d", "-s", "users-work", "-c", "/tmp", "--", "sh"))
    if ($n.code -ne 0) { throw ("the user server did not start: " + $n.err) }
    $u.line = (Get-UserLine $u)
    $u.socket = ($u.line -split '\|')[0]
    return $u
}
function Get-UserLine { param($U)
    $r = Invoke-HordeWsl -Distro $script:distroUsed -Argv ($U.argv + @("display-message", "-p", "#{socket_path}|#{pid}|#{start_time}"))
    if ($r.code -ne 0) { return "" }
    return "$($r.out)".Trim() }
function Get-UserSessions { param($U)
    $r = Invoke-HordeWsl -Distro $script:distroUsed -Argv ($U.argv + @("list-sessions", "-F", "#{session_name}"))
    return "$($r.out)".Trim() }
function Stop-UserServer { param($U)
    # Its own socket, as it was started; then its own directory, by rmdir.
    if (-not $U) { return }
    [void](Invoke-HordeWsl -Distro $script:distroUsed -Argv ($U.argv + @("kill-server")))
    if ($U.socket) { [void](Invoke-HordeWsl -Distro $script:distroUsed -Argv @("sh", "-c", '[ -S "$1" ] && rm -f -- "$1"; exit 0', "sh", $U.socket)) }
    if ($U.madeDir) { [void](Invoke-HordeWsl -Distro $script:distroUsed -Argv @("sh", "-c", 'rmdir -- "$1"/tmux-* "$1" 2>/dev/null; exit 0', "sh", $U.dir)) }
}
function Get-Entry { param($Inst) return $script:HordeTmuxStarted["$($Inst.token)"] }
$script:escapeFind = 'for n in "$@"; do for f in /proc/[0-9]*/cmdline; do c=$(tr "\0" " " < "$f" 2>/dev/null); [ "$c" = "sleep $n " ] && { p=${f#/proc/}; echo "${p%/cmdline} sleep $n"; }; done; done; exit 0'
function Get-EscapeSleeps { param($Secs)
    # The processes whose whole command line is exactly "sleep <n>" for this run's unique durations.
    $r = Invoke-HordeWsl -Distro $script:distroUsed -Argv (@("sh", "-c", $script:escapeFind, "sh") + @($Secs | ForEach-Object { "$_" }))
    return @(Get-HordeTmuxLines $r.out) }
function Stop-EscapeSleeps { param($Secs)
    # Test cleanup, reached with anything to do only when the check above has already failed: this
    # test's own escaped children, re-checked by their unique command line in the step that kills them,
    # so a failed run does not leave them for the next run to trip over.
    foreach ($l in @(Get-EscapeSleeps $Secs)) {
        $parts = @($l -split ' ')
        [void](Invoke-HordeWsl -Distro $script:distroUsed -Argv @("sh", "-c", 'c=$(tr "\0" " " < "/proc/$1/cmdline" 2>/dev/null); [ "$c" = "sleep $2 " ] && kill -9 "$1"; exit 0', "sh", $parts[0], $parts[2]))
    } }

Write-Host ""
Write-Host "=== scenario 1: start, prove isolation, spawn, read, send, tear down ===" -ForegroundColor Cyan
$iso = $null
try { $iso = Start-HordeIsolatedTmux -Distro $Distro } catch { Write-Host ("         " + $_.Exception.Message) -ForegroundColor Red }
Check ($null -ne $iso) "an isolated tmux server started in WSL and identified itself - WSL, the distro and tmux are all here"
if ($iso) {
    $distroUsed = $iso.distro
    $e1 = Get-Entry $iso
    [void]$runGuids.Add($e1.guid)
    Write-Host ("  distro " + $iso.distro + ", tmux " + $e1.version + ", server pid " + $e1.serverPid + ", socket " + $iso.socket) -ForegroundColor DarkGray
    $marker = "HORDE-E2E-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
    $escapeSecs = $null
    $v1 = $null
    try {
        $count = $null
        try { $count = Assert-HordeTmuxIsolated -Instance $iso } catch { Write-Host ("         " + $_.Exception.Message) -ForegroundColor Red }
        Check ($count -eq 1) "it is isolated, measured: our socket, our pid and start time, exactly one session and one pane"
        Check ($iso.socket -ceq ("/tmp/horde-iso-" + $e1.guid + "/tmux-" + $e1.uid + "/horde-iso-" + $e1.guid)) "its socket is <private TMUX_TMPDIR>/tmux-<uid>/horde-iso-<guid>, as the harness built it"
        $nsNow = @(Get-HordeTmuxNsProcs -Entry $e1)
        Check (@($nsNow | Where-Object { $_ -match ('^\d+ tmux -L ' + $e1.name + ' -f /dev/null -D\s*$') }).Count -eq 1) ("the server runs with -L <our name> -f /dev/null, inside our own pid namespace " + $e1.nsInode)
        $root = Invoke-HordeWsl -Distro $distroUsed -Argv @("readlink", "/proc/self/ns/pid")
        Check ("$($root.out)".Trim() -match '^pid:\[\d+\]$' -and "$($root.out)".Trim() -ne $e1.nsInode) ("CONTROL: that namespace is not the distro's own (" + "$($root.out)".Trim() + ")")

        if ($count -eq 1) {
            # A pane that prints a marker, then ignores SIGHUP and stays: tmux's kill-server sends SIGHUP,
            # and this child is measured to outlive it, so teardown must find and kill it.
            $pane = New-HordeTmuxPane -Instance $iso -Command @("sh", "-c", ("echo " + $marker + "; trap '' HUP; exec sleep 300"))
            Check (Test-HordeTmuxPaneId $pane) ("a pane was spawned running a command: " + $pane)
            Start-Sleep -Milliseconds 700
            $text = Get-HordeTmuxPaneText -Instance $iso -Pane $pane
            Check ("$text" -like "*$marker*") "the command ran and its output is on that pane's screen"
            $inside = @(Get-HordeTmuxNsProcs -Entry $e1 | Where-Object { $_ -match '^\d+ sh -c echo HORDE-E2E-|^\d+ sleep 300\s*$' })
            Check ($inside.Count -ge 1) ("the pane's process runs inside our namespace: " + ($inside -join "; "))

            $shell = New-HordeTmuxPane -Instance $iso -Command @("sh")
            # Text that starts with "-" and holds a quote and a dollar: typed literally, not parsed.
            Send-HordeTmuxText -Instance $iso -Pane $shell -Text "echo '-typed' `$((40+2))"
            Start-Sleep -Milliseconds 700
            $typed = Get-HordeTmuxPaneText -Instance $iso -Pane $shell
            Check ("$typed" -match '(?m)^-typed 42\s*$') "text sent to a pane is typed literally and the shell ran it (-typed 42 on screen)"

            # THE REVIEW OF PR 35's ESCAPE: children that carry no mark of the server. One drops its
            # whole environment (env -i), so no TMUX=<socket> is left to find it by; one also leaves
            # the session (setsid). Both ignore SIGHUP. Each sleeps a duration unique to this run, so
            # it can be found by its exact command line, and expires on its own if all else fails.
            $escapeSecs = @((200 + (Get-Random -Maximum 50)), (260 + (Get-Random -Maximum 50)))
            [void](New-HordeTmuxPane -Instance $iso -Command @("env", "-i", "sh", "-c", ("trap '' HUP; exec sleep " + $escapeSecs[0])))
            [void](New-HordeTmuxPane -Instance $iso -Command @("sh", "-c", ("setsid env -i sh -c 'trap """" HUP; exec sleep " + $escapeSecs[1] + "' & sleep 1")))
            Start-Sleep -Milliseconds 1500
            $seen = @(Get-EscapeSleeps $escapeSecs)
            Check ($seen.Count -eq 2) ("PRECONDITION: both markless HUP-ignoring children are running (" + ($seen -join "; ") + ")")
        }
    } finally {
        # Teardown runs whatever happened above. A teardown that only runs on success is the leak (L-019).
        $v1 = Stop-HordeIsolatedTmux -Instance $iso
    }
    Check (-not $v1.refused) "teardown accepted the server Start registered"
    Check (-not $v1.survived) "the server is gone: its socket says no server, and its process has exited"
    Check (@($v1.orphansSurvived).Count -eq 0) "nothing that ran inside it is still running"
    Check ($v1.stopped) "so the teardown's own verdict is stopped"
    if ($escapeSecs) {
        $left = @(Get-EscapeSleeps $escapeSecs)
        Check ($left.Count -eq 0) ("a child that dropped its environment, or left the session, did not outlive teardown (" + ($left -join "; ") + ")")
        Check (-not ($v1.stopped -and $left.Count -gt 0)) "and teardown never reports stopped while such a child is still running"
        Stop-EscapeSleeps $escapeSecs
    }
    Check ($v1.socketRemoved -and $v1.dirRemoved) "its socket file and its private directory are removed"
    $after = Invoke-HordeWsl -Distro $distroUsed -Argv @("test", "-e", $e1.dir)
    $nsAfter = @(Get-HordeTmuxNsProcs -Entry $e1)
    Check ($after.code -eq 1 -and $nsAfter.Count -eq 0) ("measured afterwards in WSL: the directory does not exist and no process is left in the namespace (" + ($nsAfter -join "; ") + ")")
}

Write-Host ""
Write-Host "=== scenario 2: the scenario fails midway - teardown must still run ===" -ForegroundColor Cyan
$iso2 = $null
try { $iso2 = Start-HordeIsolatedTmux -Distro $distroUsed } catch { Write-Host ("         " + $_.Exception.Message) -ForegroundColor Red }
Check ($null -ne $iso2) "a second isolated server started"
if ($iso2) {
    [void]$runGuids.Add((Get-Entry $iso2).guid)
    $r2 = $null; $threw = $false
    try {
        try {
            [void](Assert-HordeTmuxIsolated -Instance $iso2)
            throw "injected failure, standing in for any test that breaks partway"
        } finally {
            $r2 = Stop-HordeIsolatedTmux -Instance $iso2
        }
    } catch { $threw = ("$($_.Exception.Message)" -like "*injected failure*") }
    Check $threw "PRECONDITION: the injected failure really was thrown"
    Check ($null -ne $r2 -and $r2.stopped -and $r2.dirRemoved) "when the scenario fails midway, teardown still runs and leaves nothing"
}

Write-Host ""
Write-Host "=== scenario 3: a user's tmux server on another socket survives teardown untouched ===" -ForegroundColor Cyan
$u1 = $null; $u2 = $null; $iso3 = $null
try {
    try { $iso3 = Start-HordeIsolatedTmux -Distro $distroUsed } catch { Write-Host ("         " + $_.Exception.Message) -ForegroundColor Red }
    Check ($null -ne $iso3) "a third isolated server started"
    if ($iso3) {
        $e3 = Get-Entry $iso3
        [void]$runGuids.Add($e3.guid)
        # U1 is the ordinary case: the user's server in its own directory, like /tmp/tmux-<uid>/default.
        # U2 is the harsh one: another server INSIDE our private directory, as if someone had mistyped
        # a socket name into it. Neither is started through the harness.
        $u1 = Start-UserServer
        $u2 = Start-UserServer -Dir $e3.dir
        Check ($u1.line -match '\|\d+\|\d+$' -and $u2.line -match '\|\d+\|\d+$') ("PRECONDITION: both stand-in user servers answer (" + $u1.line + "; " + $u2.line + ")")
        Check ($u2.socket -like ($e3.dir + "/*")) "PRECONDITION: the second one's socket really is inside our private directory"
        $u1Before = $u1.line; $u2Before = $u2.line
        $u1Sessions = Get-UserSessions $u1; $u2Sessions = Get-UserSessions $u2

        # The harness cannot see them: its server still has exactly its own one session and one pane.
        $c3 = $null
        try { $c3 = Assert-HordeTmuxIsolated -Instance $iso3 } catch { Write-Host ("         " + $_.Exception.Message) -ForegroundColor Red }
        Check ($c3 -eq 1) "with two other servers running, one of them in the same directory, the harness still sees only its own one pane"

        $v3 = Stop-HordeIsolatedTmux -Instance $iso3
        Check ($v3.stopped -and $v3.socketRemoved) "our server is stopped and its socket removed"
        Check (-not $v3.dirRemoved) "our directory is NOT removed while a stranger's socket is in it - rmdir refuses, as it must"
        Check ((Get-UserLine $u1) -ceq $u1Before -and (Get-UserSessions $u1) -ceq $u1Sessions) "the user's server in its own directory still answers, same socket, pid, start time and sessions"
        Check ((Get-UserLine $u2) -ceq $u2Before -and (Get-UserSessions $u2) -ceq $u2Sessions) "the server inside our directory still answers too, untouched"
        $s2 = Invoke-HordeWsl -Distro $distroUsed -Argv @("test", "-S", $u2.socket)
        Check ($s2.code -eq 0) "and its socket file is still there"
    }
} finally {
    Stop-UserServer $u2
    Stop-UserServer $u1
    if ($iso3) {
        # Our directory could not go while U2 was in it; with U2 gone it can, by the same rmdir.
        $e3b = [pscustomobject]@{ dir = ("/tmp/horde-iso-" + $e3.guid); uid = $e3.uid }
        [void](Invoke-HordeWsl -Distro $distroUsed -Argv @("sh", "-c", 'rmdir -- "$1/tmux-$2" "$1" 2>/dev/null; exit 0', "sh", $e3b.dir, $e3b.uid))
    }
}
if ($u1 -and $u2) {
    Check ((Get-UserLine $u1) -eq "" -and (Get-UserLine $u2) -eq "") "CONTROL: the stand-in servers were really running until this file stopped them by their own sockets"
}

Write-Host ""
Write-Host "=== scenario 5: the process that owns the server dies without tearing down ===" -ForegroundColor Cyan

# A CRASHED RUN. A child PowerShell - started here and held by its handle, the only process this
# scenario ever kills - starts an isolated server, puts a markless HUP-ignoring child in it, reports
# the server, and is then killed mid-run, so no teardown runs at all. The server, everything in its
# namespace, its socket and its directory must all go on their own: the owner's wsl.exe loses its
# stdin with the dead process, and pid 1 exits on that EOF.
$crashSecs = 320 + (Get-Random -Maximum 40)
$crashScript = Join-Path $env:TEMP ("horde-tmux-crash-" + [guid]::NewGuid().ToString("N") + ".ps1")
$crashBody = @'
param([string]$Harness, [string]$Distro, [string]$Secs)
. $Harness
$i = Start-HordeIsolatedTmux -Distro $Distro
$e = $script:HordeTmuxStarted[$i.token]
[void](New-HordeTmuxPane -Instance $i -Command @("env", "-i", "sh", "-c", ("trap '' HUP; exec sleep " + $Secs)))
[Console]::Out.WriteLine("READY|" + $e.guid + "|" + $e.nsInode)
[Console]::Out.Flush()
Start-Sleep -Seconds 600
# Never reached: this process is killed while it sleeps. A run that did reach here would stop its own.
[void](Stop-HordeIsolatedTmux -Instance $i)
'@
[System.IO.File]::WriteAllText($crashScript, $crashBody)
$child = $null; $crashG = ""; $crashNs = ""
$crashUid = "$((Invoke-HordeWsl -Distro $distroUsed -Argv @("id", "-u")).out)".Trim()
try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File " + (ConvertTo-HordeWinArg $crashScript) + " -Harness " + (ConvertTo-HordeWinArg (Join-Path $testDir "Isolation.ps1")) + " -Distro " + (ConvertTo-HordeWinArg $distroUsed) + " -Secs " + $crashSecs
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    $child = [System.Diagnostics.Process]::Start($psi)
    [void]$child.StandardError.ReadToEndAsync()
    $childStart = $child.StartTime
    $ready = $null
    $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline) {
        $t = $child.StandardOutput.ReadLineAsync()
        if (-not $t.Wait([int][Math]::Max(1, ($deadline - (Get-Date)).TotalMilliseconds))) { break }
        if ($null -eq $t.Result) { break }
        if ($t.Result -match '^READY\|([0-9a-f]{32})\|(pid:\[\d+\])$') { $ready = $Matches; break }
    }
    Check ($null -ne $ready) "PRECONDITION: a child PowerShell started an isolated server and reported it"
    if ($ready) {
        $crashG = $ready[1]; $crashNs = $ready[2]
        [void]$runGuids.Add($crashG)
        $ce = [pscustomobject]@{ distro = $distroUsed; name = ("horde-iso-" + $crashG); nsInode = $crashNs }
        Check (@(Get-HordeTmuxNsProcs -Entry $ce).Count -ge 3 -and @(Get-EscapeSleeps @($crashSecs)).Count -eq 1) "PRECONDITION: its namespace is running, with the markless child inside"
        # The ONLY kill in this scenario: the PowerShell this file started, through the handle it holds.
        $child.Kill()
        [void]$child.WaitForExit(10000)
        Check ($child.HasExited) "the owning PowerShell was killed mid-run, so no teardown ran"
        $gone = $false
        $deadline = (Get-Date).AddSeconds(30)
        while ((Get-Date) -lt $deadline) {
            if (@(Get-HordeTmuxNsProcs -Entry $ce).Count -eq 0) { $gone = $true; break }
            Start-Sleep -Milliseconds 500
        }
        Check $gone ("with its owner dead, every process in the namespace is gone within 30s (" + (@(Get-HordeTmuxNsProcs -Entry $ce) -join "; ") + ")")
        Check (@(Get-EscapeSleeps @($crashSecs)).Count -eq 0) "and the markless HUP-ignoring child with them"
        $ghost = [pscustomobject]@{ guid = $crashG; name = ("horde-iso-" + $crashG); dir = ("/tmp/horde-iso-" + $crashG) }
        $dirLeft = Invoke-HordeWsl -Distro $distroUsed -Argv @("test", "-e", $ghost.dir)
        Check ($dirLeft.code -eq 1) "its private directory, and the socket in it, are gone - nothing is left behind forever"
        $wslLeft = @(Get-CimInstance Win32_Process -Filter ("ParentProcessId = " + $child.Id) -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq "wsl.exe" -and $_.CreationDate -ge $childStart })
        Check ($wslLeft.Count -eq 0) ("and the dead run's wsl.exe has exited on its own (" + (@($wslLeft | ForEach-Object { $_.ProcessId }) -join ", ") + ")")
    }
} finally {
    if ($child -and -not $child.HasExited) { try { $child.Kill() } catch { } }
    if ($child) { $child.Dispose() }
    Remove-Item -LiteralPath $crashScript -Force -ErrorAction SilentlyContinue
    if ($crashG) {
        # ONLY WHEN THE CHECKS ABOVE FAILED is there anything here to do: the dead run's server, by its
        # own socket, its escaped child by its unique command line, and its directory by rmdir.
        $ghost = [pscustomobject]@{ guid = $crashG; name = ("horde-iso-" + $crashG); dir = ("/tmp/horde-iso-" + $crashG) }
        $still = Invoke-HordeWsl -Distro $distroUsed -Argv (Get-HordeTmuxArgv -Entry $ghost -Command @("list-sessions"))
        if ($still.code -eq 0) { [void](Invoke-HordeWsl -Distro $distroUsed -Argv (Get-HordeTmuxArgv -Entry $ghost -Command @("kill-server"))) }
        Stop-EscapeSleeps @($crashSecs)
        [void](Invoke-HordeWsl -Distro $distroUsed -Argv @("sh", "-c", $script:HordeTmuxCleanup, "sh", ($ghost.dir + "/tmux-" + $crashUid + "/" + $ghost.name), ($ghost.dir + "/tmux-" + $crashUid), $ghost.dir))
    }
}

Write-Host ""
Write-Host "=== scenario 4: the WSL boundary, measured ===" -ForegroundColor Cyan

# 1. `wsl.exe --` hands the arguments to a Linux shell; --exec does not. CONTROL first: the rewrite is
#    real on this machine, or the --exec rule would be guarding nothing.
$fmt = '#{pane_id}|$HOME|a b'
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "wsl.exe"
$psi.Arguments = "-d " + $distroUsed + " -- printf %s " + (ConvertTo-HordeWinArg $fmt)
$psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardInput = $true; $psi.CreateNoWindow = $true
$cp = [System.Diagnostics.Process]::Start($psi); $cp.StandardInput.Close()
$viaShell = $cp.StandardOutput.ReadToEnd(); [void]$cp.StandardError.ReadToEnd(); $cp.WaitForExit(); $cp.Dispose()
Check ("$viaShell" -cne $fmt) ("CONTROL: through wsl.exe --, the argument is rewritten by the shell: '" + "$viaShell".Trim() + "'")
$viaExec = Invoke-HordeWsl -Distro $distroUsed -Argv @("printf", "%s", $fmt)
Check ("$($viaExec.out)" -ceq $fmt) "through the harness's --exec, the same argument arrives exactly"
$bs = [string][char]92; $q = [string][char]34
$hard = @("", "a b", ("a" + $q + "b"), ("c" + $bs), ("d e" + $bs + $q + "f"), ("x" + $bs + $bs + "y"), "-x", ("caf" + [char]0xE9))
$rt = Invoke-HordeWsl -Distro $distroUsed -Argv (@("printf", "[%s]\n") + $hard)
$wantRt = (@($hard | ForEach-Object { "[" + $_ + "]" }) -join "`n") + "`n"
Check ("$($rt.out)" -ceq $wantRt) "empty, spaced, quoted, backslashed, dash-led and accented arguments all arrive exactly"

# 2 and 3. A missing distro: exit -1, and wsl.exe's own message is UTF-16 on stdout.
$nd = "horde-no-such-distro-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
$miss = Invoke-HordeWsl -Distro $nd -Argv @("true")
Check ($miss.code -eq -1) ("a missing distro exits -1 (measured " + $miss.code + ")")
Check ("$($miss.out)" -notmatch [string][char]0 -and "$($miss.out)".Trim().Length -gt 10) ("its UTF-16 message is decoded to readable text: '" + "$($miss.out)".Trim() + "'")
Check ((Get-HordeWslFailure $miss) -like "*exit -1*") "and it is read as wsl.exe's own failure"
$threwMissing = ""
try { $x = Start-HordeIsolatedTmux -Distro $nd; if ($x) { [void](Stop-HordeIsolatedTmux -Instance $x) } } catch { $threwMissing = "$($_.Exception.Message)" }
Check ($threwMissing -like "tmux host unavailable*exit -1*") ("starting on a missing distro fails loudly: '" + $threwMissing + "'")
$np = Invoke-HordeWsl -Distro $distroUsed -Argv @("horde-no-such-program")
Check ($np.code -eq 1 -and (Get-HordeWslFailure $np) -like "*not installed*") "a missing program exits 1 like tmux does, and is still told apart from a tmux answer"

# 4. TMUX_TMPDIR that does not exist: tmux silently falls back to /tmp. CONTROL: measured here with a
#    read-only list-sessions on a name nobody uses. Then the harness's env -C makes it impossible.
$gg = [guid]::NewGuid().ToString("N")
$fb = Invoke-HordeWsl -Distro $distroUsed -Argv @("env", "-u", "TMUX", ("TMUX_TMPDIR=/tmp/horde-absent-" + $gg), "tmux", "-L", ("horde-absent-" + $gg), "-f", "/dev/null", "list-sessions")
Check ($fb.code -eq 1 -and "$($fb.err)" -match '/tmp/tmux-\d+/horde-absent-' -and "$($fb.err)" -notmatch 'horde-absent-[0-9a-f]{32}/tmux') ("CONTROL: with its TMUX_TMPDIR missing, tmux looked in the shared /tmp/tmux-<uid> instead: '" + "$($fb.err)".Trim() + "'")
$ghost = [pscustomobject]@{ guid = $gg; name = ("horde-iso-" + $gg); dir = ("/tmp/horde-iso-" + $gg) }
$gv = Invoke-HordeWsl -Distro $distroUsed -Argv (Get-HordeTmuxArgv -Entry $ghost -Command @("list-sessions"))
Check ($gv.code -eq 125 -and "$($gv.err)" -match 'cannot change directory') ("through the harness's argv, a missing private directory stops the call before tmux runs (exit " + $gv.code + ")")

Write-Host ""
Write-Host "=== and nothing of this run is left in WSL ===" -ForegroundColor Cyan
if ($runGuids.Count -gt 0) {
    $left = Invoke-HordeWsl -Distro $distroUsed -Argv (@("sh", "-c", 'for g in "$@"; do for d in /tmp/horde-iso-$g /tmp/horde-user-$g; do [ -e "$d" ] && echo "dir $d"; done; for f in /proc/[0-9]*/cmdline; do c=$(tr "\0" " " < "$f" 2>/dev/null); case "$c" in *"-L horde-iso-$g "*|*"-L horde-user-$g "*) echo "proc $f: $c" ;; esac; done; done; exit 0', "sh") + @($runGuids))
    Check ("$($left.out)".Trim() -eq "" -and $left.code -eq 0) ("no directory and no tmux process of this run's " + $runGuids.Count + " servers remains ('" + "$($left.out)".Trim() + "')")
} else {
    Check $false "PRECONDITION: this run started servers to account for"
}
Check ($script:HordeTmuxStarted.Count -eq 0) "and the harness holds no registered server"

Complete-HordeSuite -Success "isolated tmux servers start, work, and leave nothing behind - and a user's server survives them"
