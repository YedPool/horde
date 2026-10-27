# DOES THE tmux ISOLATION HARNESS REFUSE TO TOUCH A SERVER IT DID NOT START?
#
# The fast half of the harness's tests. It STARTS NO tmux SERVER: every decision the harness makes
# about what to kill, what to delete and what to refuse is proven here against a FAKE transport that
# records the exact Linux argv the harness would have sent, and answers as tmux and wsl.exe were
# measured to answer. The end-to-end half, which starts real servers, is
# hosts/tmux/test/e2e/e2e-isolation.ps1.
#
# TWO THINGS HERE DO REACH WSL, both read-only and neither starts a server: the preflight (is WSL
# there, is the distro there, is tmux in it), and the proof that an inherited TMUX cannot cross the
# boundary. If WSL or tmux is missing the preflight FAILS - an absent host is never a green skip.
#
# -Distro, or HORDE_TMUX_DISTRO, names the WSL distro; empty means WSL's default distro.
#
# NIGHTLY NET: its preflight reaches WSL; on a machine with no WSL distro it fails by design (nightly net,
# 2026-10-26).
# nightly-needs: wsl

param([string]$Distro = "$env:HORDE_TMUX_DISTRO")

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
# hosts/tmux/test/ - the repository root is three levels up (D12: host test tooling lives with its host).
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
$harnessPath = Join-Path $here "Isolation.ps1"
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
# If the harness does not load, stop with no [FAIL] line, so a mutation run never reads a harness
# that no longer loads as a catch.
try { . $harnessPath } catch { Write-Host ("  the harness did not load: " + $_.Exception.Message); exit 3 }

function Ord { param([string]$A, [string]$B) return [string]::Equals($A, $B, [System.StringComparison]::Ordinal) }
function Reply { param($Code = 0, [string]$Out = "", [string]$Err = "")
    return [pscustomobject]@{ code = $Code; out = $Out; err = $Err; timedOut = $false; startError = "" } }

# THE FAKE WSL. Records every call as { distro; argv }, and answers from $script:answer, a scriptblock
# that gets the call's kind ("tmux", "nsscan", "cleanup", "mkdir", "preflight") and the argv.
$script:calls = New-Object System.Collections.ArrayList
$script:answer = $null
$fake = { param($D, $Argv, $T)
    [void]$script:calls.Add([pscustomobject]@{ distro = $D; argv = @($Argv) })
    $a = @($Argv)
    $kind = "other"
    if ($a[0] -eq "env") { $kind = "tmux" }
    elseif ($a[0] -eq "mkdir") { $kind = "mkdir" }
    elseif ($a[0] -eq "sh" -and $a[2] -eq $script:HordeTmuxNsScan) { $kind = "nsscan" }
    elseif ($a[0] -eq "sh" -and $a[2] -eq $script:HordeTmuxCleanup) { $kind = "cleanup" }
    elseif ($a[0] -eq "sh") { $kind = "preflight" }
    $ans = & $script:answer $kind $a
    # A real scan always ends with "scanned <n>" (n processes it could read); the fake adds it, unless
    # a test wants the raw answer to prove what happens without it.
    if ($kind -eq "nsscan" -and -not $script:rawScan -and $ans -and "$($ans.out)" -notmatch '(?m)^scanned \d+$') {
        $ans = Reply $ans.code ("$($ans.out)" + "scanned 9`n") $ans.err }
    return $ans }
$script:rawScan = $false
# The tmux words after "-f /dev/null". Returned with a leading comma: a one-word command ("kill-server")
# would otherwise arrive as a bare string, and [0] of a string is its first letter (CONTRIBUTING 12) -
# the first run of this suite measured exactly that, as a kill-server the fake never recognised.
# THE FAKE OWNER. Records its argv like any call (kind "owner") and answers from $script:ownerAnswer:
# { proc = $null; nsInode; ready; failure }. No process is started.
$script:ownerAnswer = $null
$fakeOwner = { param($D, $Argv, $T)
    [void]$script:calls.Add([pscustomobject]@{ distro = $D; argv = @($Argv) })
    return $script:ownerAnswer }
function Get-TmuxCommand { param($Argv) $i = [array]::IndexOf($Argv, "/dev/null"); if ($i -lt 0) { return , @() }; return , @($Argv[($i + 1)..($Argv.Count - 1)]) }
function Get-Calls { param([string]$Verb) return @($script:calls | Where-Object { $_.argv[0] -eq "env" -and (Get-TmuxCommand $_.argv)[0] -eq $Verb }) }

# An answer that behaves like a healthy server of ours which dies on kill-server. Script variables,
# not closures: a GetNewClosure block runs in a module of its own and cannot see this suite's helpers.
$script:dead = $false
$script:hLine = ""
$script:hSock = ""
$script:hName = ""
$script:healthy = { param($kind, $a)
    if ($kind -eq "tmux") {
        $verb = (Get-TmuxCommand $a)[0]
        if ($verb -eq "kill-server") { $script:dead = $true; return (Reply 0) }
        if ($script:dead) { return (Reply 1 "" ("no server running on " + $script:hSock)) }
        if ($verb -eq "display-message") { return (Reply 0 ($script:hLine + "`n")) }
        return (Reply 0 "`$0|horde-iso`n")
    }
    # The namespace: pid 1 and the server while it runs, nothing once it has gone.
    if ($kind -eq "nsscan") { if ($script:dead) { return (Reply 0 "") }; return (Reply 0 ("401 sh -c sess=`$1`n403 tmux -L " + $script:hName + " -f /dev/null -D`n")) }
    return (Reply 0 "") }
function Set-Healthy { param($Entry, [string]$ServerPid = "")
    # Arms $script:healthy for Entry. -ServerPid makes the server on our socket claim another pid.
    $script:dead = $false
    $sp = $ServerPid; if (-not $sp) { $sp = $Entry.serverPid }
    $script:hSock = $Entry.socket
    $script:hName = $Entry.name
    $script:hLine = $Entry.socket + "|" + $sp + "|" + $Entry.startTime
}
function New-Entry {
    # A registry entry shaped exactly as Start makes one, registered under a fresh token.
    $g = [guid]::NewGuid().ToString("N")
    $e = [pscustomobject]@{ distro = "fake-distro"; uid = "0"; version = "3.4"; guid = $g; name = ("horde-iso-" + $g); dir = ("/tmp/horde-iso-" + $g)
                            socket = ("/tmp/horde-iso-" + $g + "/tmux-0/horde-iso-" + $g); serverPid = "4242"; startTime = "1790000000"
                            nsInode = "pid:[4026530001]"; owner = $null }
    $tok = "horde-tmux-iso:" + $g
    $script:HordeTmuxStarted[$tok] = $e
    return [pscustomobject]@{ entry = $e; inst = [pscustomobject]@{ token = $tok } }
}

Write-Host ""
Write-Host "--- preflight: WSL, the distro and tmux are really here (read-only, no server) ---" -ForegroundColor Cyan

# FAIL LOUDLY. The e2e cannot run without these, and a suite that skipped green here would read as
# "the tmux host is proven" on a machine where it was never measured.
$pre = Invoke-HordeWsl -Distro $Distro -Argv @("tmux", "-V")
$preWhy = Get-HordeWslFailure $pre
if ($preWhy) { Write-Host ("         " + $preWhy) -ForegroundColor Red }
Check ($preWhy -eq "" -and $pre.code -eq 0 -and "$($pre.out)" -match '^tmux \d') ("WSL answers, the distro '" + $Distro + "' exists (empty = default) and tmux is installed in it: '" + "$($pre.out)".Trim() + "'")

# THE HARNESS'S OWN PREFLIGHT, run for real (it starts nothing): it must pass here, and it must fail
# by name when unshare cannot be found - measured by hiding every binary behind an empty PATH, with
# the shell itself named by its full path.
$hp = Invoke-HordeWsl -Distro $Distro -Argv @("sh", "-c", $script:HordeTmuxPreflight)
Check ($hp.code -eq 0 -and "$($hp.out)".Trim() -match '^[A-Za-z0-9._-]+\|\d+\|tmux \S+$') ("the harness's preflight passes here, unshare and tmux both found: '" + "$($hp.out)".Trim() + "'")
$np = Invoke-HordeWsl -Distro $Distro -Argv @("env", "PATH=/horde-no-such-dir", "/bin/sh", "-c", $script:HordeTmuxPreflight)
Check ($np.code -eq 3 -and "$($np.err)" -match 'unshare \(util-linux\) is not installed') ("with unshare not on PATH, the preflight fails by name, exit 3: '" + "$($np.err)".Trim() + "'")

Write-Host ""
Write-Host "--- the WSL boundary: arguments, bytes and exit codes ---" -ForegroundColor Cyan

# Each argument must reach Linux exactly, through the command-line string wsl.exe parses. The e2e
# proves the round trip on a real wsl.exe; these pin the quoting rules.
$bs = [string][char]92; $q = [string][char]34
Check ((ConvertTo-HordeWinArg "plain") -ceq "plain") "an argument with nothing special is passed as it is"
Check ((ConvertTo-HordeWinArg "") -ceq ($q + $q)) "an empty argument is passed as two quotes, not dropped"
Check ((ConvertTo-HordeWinArg "a b") -ceq ($q + "a b" + $q)) "an argument with a space is quoted"
Check ((ConvertTo-HordeWinArg ("a" + $q + "b")) -ceq ($q + "a" + $bs + $q + "b" + $q)) "a double quote inside is escaped with one backslash"
Check ((ConvertTo-HordeWinArg ("c d" + $bs)) -ceq ($q + "c d" + $bs + $bs + $q)) "a trailing backslash inside quotes is doubled, so it does not escape the closing quote"
Check ((ConvertTo-HordeWinArg ("e " + $bs + $q)) -ceq ($q + "e " + $bs + $bs + $bs + $q + $q)) "a backslash before a quote is doubled and the quote escaped"
Check ((ConvertTo-HordeWinArg ("x" + $bs + "y")) -ceq ("x" + $bs + "y")) "a backslash not before a quote is literal"

# wsl.exe's own message for a missing distro, as measured 2026-09-30: UTF-16LE, no byte order mark,
# on stdout. Decoded as UTF-8 it keeps a NUL after every letter, which is how it reads as nothing.
$msg = "There is no distribution with the supplied name."
$u16 = [System.Text.Encoding]::Unicode.GetBytes($msg)
Check (([System.Text.Encoding]::UTF8.GetString($u16)).Contains([string][char]0)) "CONTROL: read as UTF-8, wsl.exe's own message is full of NULs"
Check (-not (Ord ([System.Text.Encoding]::UTF8.GetString($u16)) $msg)) "CONTROL: and the ordinal comparison below tells that apart from the real text"
# ORDINAL, NOT -ceq: PowerShell compares strings culture-aware, and that IGNORES NUL characters, so
# "T\0h\0e..." -ceq "The..." is true. The mutation run measured it: a decoder that never detected
# UTF-16 survived a -ceq check.
Check (Ord (ConvertFrom-HordeWslBytes $u16) $msg) "wsl.exe's UTF-16 message without a byte order mark is decoded to readable text"
Check (Ord (ConvertFrom-HordeWslBytes (@([byte]0xFF, [byte]0xFE) + $u16)) $msg) "and with a byte order mark, the mark is dropped"
$cafe = [byte[]]@(99, 97, 102, 195, 169)
Check ((ConvertFrom-HordeWslBytes $cafe) -ceq ("caf" + [char]0xE9)) "the Linux program's UTF-8 output is decoded as UTF-8 (measured: printf of an accented word gave these bytes)"
Check ((ConvertFrom-HordeWslBytes ([System.Text.Encoding]::UTF8.GetBytes("ab`n"))) -ceq "ab`n") "an even number of plain UTF-8 bytes is not mistaken for UTF-16"
Check ((ConvertFrom-HordeWslBytes @()) -ceq "") "no bytes decode to an empty string"

$minus1 = Reply -1 $msg ""
Check ((Get-HordeWslFailure $minus1) -like "*exit -1*no distribution*") "exit -1 is read as wsl.exe's own failure, with its message"
$noProg = Reply 1 "" "<3>WSL (574 - Relay) ERROR: CreateProcessCommon:818: execvpe(tmux) failed: No such file or directory`n"
Check ((Get-HordeWslFailure $noProg) -like "*'tmux' is not installed*") "exit 1 with execvpe(...) failed is a missing program, not a tmux answer"
$noSrv = Reply 1 "" "no server running on /tmp/horde-iso-x/tmux-0/horde-iso-x`n"
Check ((Get-HordeWslFailure $noSrv) -eq "") "exit 1 from tmux itself is tmux's answer, not a WSL failure"
Check ((Get-HordeWslFailure ([pscustomobject]@{ code = $null; out = ""; err = ""; timedOut = $true; startError = "" })) -like "*did not finish*") "a timed-out call is a WSL failure"
Check ((Get-HordeWslFailure ([pscustomobject]@{ code = $null; out = ""; err = ""; timedOut = $false; startError = "not found" })) -like "*could not be started*") "wsl.exe missing from Windows is a WSL failure"
Check (Test-HordeTmuxNoServer $noSrv) "'no server running on' is read as no server"
Check (Test-HordeTmuxNoServer (Reply 1 "" "error connecting to /tmp/tmux-0/x (No such file or directory)")) "'error connecting to' is read as no server"
Check (-not (Test-HordeTmuxNoServer $noProg)) "a missing program is not read as no server"
Check (-not (Test-HordeTmuxNoServer (Reply 0 "" "no server running on x"))) "exit 0 is never read as no server"
Check (Test-HordeTmuxNoServer (Reply 125 "" "env: cannot change directory to '/tmp/horde-iso-x': No such file or directory")) "our private directory gone (env -C, exit 125) is read as no server - pid 1 removes it when its server exits"
Check (-not (Test-HordeTmuxNoServer (Reply 125 "" "something else entirely"))) "but exit 125 alone is not"

Write-Host ""
Write-Host "--- an inherited TMUX cannot cross into WSL (read-only) ---" -ForegroundColor Cyan

# The outer terminal sets WSLENV on this machine (measured: TERM:COLORTERM:TERM_PROGRAM:...), and
# WSLENV is what carries a Windows variable into Linux. Poison all three, then prove the harness's
# call does not carry them, against a control that does.
$keep = @{}
foreach ($v in @("TMUX", "TMUX_PANE", "WSLENV")) { $keep[$v] = [Environment]::GetEnvironmentVariable($v, "Process") }
$poison = "/tmp/horde-poison-" + [guid]::NewGuid().ToString("N").Substring(0, 8) + ",1,0"
try {
    [Environment]::SetEnvironmentVariable("TMUX", $poison, "Process")
    [Environment]::SetEnvironmentVariable("TMUX_PANE", "%99", "Process")
    [Environment]::SetEnvironmentVariable("WSLENV", "TMUX/u:TMUX_PANE/u", "Process")
    # CONTROL: an ordinary child of this process, not through the harness, DOES carry the poison in.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "wsl.exe"
    $psi.Arguments = "--exec printenv TMUX"
    if ($Distro) { $psi.Arguments = "-d " + $Distro + " --exec printenv TMUX" }
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    $cp = [System.Diagnostics.Process]::Start($psi)
    $cout = $cp.StandardOutput.ReadToEnd(); [void]$cp.StandardError.ReadToEnd(); $cp.WaitForExit(); $cp.Dispose()
    Check ("$cout".Trim() -eq $poison) "CONTROL: without the scrub, an inherited TMUX reaches Linux through WSLENV"
    $h = Invoke-HordeWsl -Distro $Distro -Argv @("printenv", "TMUX", "TMUX_PANE", "WSLENV")
    Check ($h.code -eq 1 -and "$($h.out)".Trim() -eq "") ("through the harness, none of TMUX, TMUX_PANE or WSLENV reaches Linux (got '" + "$($h.out)".Trim() + "')")
} finally {
    foreach ($v in @($keep.Keys)) { [Environment]::SetEnvironmentVariable($v, $keep[$v], "Process") }
}
Check ([Environment]::GetEnvironmentVariable("TMUX", "Process") -eq $keep["TMUX"]) "and this process's own environment is back as it was"

Write-Host ""
Write-Host "--- every tmux call names our socket, our directory and no config ---" -ForegroundColor Cyan

$a = New-Entry
$argv = Get-HordeTmuxArgv -Entry $a.entry -Command @("list-sessions")
$want = @("env", "-C", $a.entry.dir, "-u", "TMUX", "-u", "TMUX_PANE", ("TMUX_TMPDIR=" + $a.entry.dir), "tmux", "-L", $a.entry.name, "-f", "/dev/null", "list-sessions")
Check (($argv -join " ") -ceq ($want -join " ")) "the argv is env -C <our dir> -u TMUX -u TMUX_PANE TMUX_TMPDIR=<our dir> tmux -L <our name> -f /dev/null <command>"
$other = [pscustomobject]@{ guid = $a.entry.guid; name = "default"; dir = $a.entry.dir }
Check (Throws { Get-HordeTmuxArgv -Entry $other -Command @("kill-server") } "refusing") "a socket name that is not horde-iso-<our guid> is refused - the user's 'default' can never be named"
$other2 = [pscustomobject]@{ guid = $a.entry.guid; name = $a.entry.name; dir = "/tmp" }
Check (Throws { Get-HordeTmuxArgv -Entry $other2 -Command @("kill-server") } "refusing") "a socket directory that is not /tmp/horde-iso-<our guid> is refused - /tmp is where the user's servers live"
$g2 = [guid]::NewGuid().ToString("N")
$other3 = [pscustomobject]@{ guid = $a.entry.guid; name = ("horde-iso-" + $g2); dir = $a.entry.dir }
Check (Throws { Get-HordeTmuxArgv -Entry $other3 -Command @("kill-server") } "refusing") "a name and a directory from two different guids are refused"
Check (Throws { Get-HordeTmuxArgv -Entry $null -Command @("kill-server") } "no registered") "no entry is refused"
Check (Throws { Invoke-HordeTmux -Instance ([pscustomobject]@{ token = "horde-tmux-iso:" + $g2 }) -Command @("list-sessions") } "no registered token") "a tmux call for an instance this process never started is refused before WSL is called"

Write-Host ""
Write-Host "--- deciding whether a server is ours and isolated ---" -ForegroundColor Cyan

$e = $a.entry
Check ($null -eq (Test-HordeTmuxIdentity -Entry $e -Line ($e.socket + "|4242|1790000000`n"))) "CONTROL: the recorded socket, pid and start time are accepted"
Check ((Test-HordeTmuxIdentity -Entry $e -Line ("/tmp/tmux-0/default|4242|1790000000")) -like "*not on our socket*") "a server answering on another socket is refused"
Check ((Test-HordeTmuxIdentity -Entry $e -Line ($e.socket + "|4243|1790000000")) -like "*not the pid*") "a different pid on our socket is refused - the server was restarted by someone"
Check ((Test-HordeTmuxIdentity -Entry $e -Line ($e.socket + "|4242|1790000001")) -like "*not the pid*") "a different start time on our socket is refused"
Check ((Test-HordeTmuxIdentity -Entry $e -Line "garbage") -like "*not socket|pid|start*") "an identity line of the wrong shape is refused"
Check ($null -eq (Test-HordeTmuxIsolation -Sessions @("`$0|horde-iso") -Panes @("%0"))) "CONTROL: one session, the harness's, and one pane is isolated"
Check ((Test-HordeTmuxIsolation -Sessions @() -Panes @()) -like "*unknown, not empty*") "nothing listed is unknown, never an empty server"
Check ((Test-HordeTmuxIsolation -Sessions @("`$0|horde-iso", "`$1|work") -Panes @("%0", "%1")) -like "*2 sessions*") "two sessions are refused"
Check ((Test-HordeTmuxIsolation -Sessions @("`$0|horde-iso") -Panes @("%0", "%1")) -like "*2 panes*") "two panes are refused"
Check ((Test-HordeTmuxIsolation -Sessions @("`$0|work") -Panes @("%0")) -like "*not the harness*") "one session that is not the harness's is refused"
$ce = [pscustomobject]@{ name = "horde-iso-abc"; nsInode = "pid:[4026530009]" }
Check ($null -eq (Test-HordeTmuxContained -Entry $ce -Lines @("1 sh -c sess=`$1", "3 tmux -L horde-iso-abc -f /dev/null -D ", "9 sh"))) "CONTROL: our server in our namespace is contained"
Check ((Test-HordeTmuxContained -Entry $ce -Lines @()) -like "*unknown, not contained*") "an empty namespace is unknown, never contained"
Check ((Test-HordeTmuxContained -Entry $ce -Lines @("1 sh", "3 tmux -L horde-iso-abc -f /dev/null new-session -d")) -like "*not running inside*") "a server started some other way than pid 1's -D is not ours"
Check ((Test-HordeTmuxContained -Entry $ce -Lines @("1 sh", "3 tmux -L horde-iso-abcd -f /dev/null -D")) -like "*not running inside*") "a server with a longer name that starts with ours is not ours"
Check ((Test-HordeTmuxPaneId "%12") -and -not (Test-HordeTmuxPaneId "12") -and -not (Test-HordeTmuxPaneId "%1;kill-server")) "only %<number> is a pane id"

Write-Host ""
Write-Host "--- teardown refuses what it did not start, and kills only by our socket ---" -ForegroundColor Cyan

$script:HordeTmuxTransport = $fake
try {
    $script:calls.Clear()
    $script:answer = { param($k, $a) Reply 0 }
    $v0 = Stop-HordeIsolatedTmux -Instance $null
    Check ($v0.refused -and -not $v0.stopped -and "$($v0.reason)" -like "*nothing was verified*") "no instance is a refusal that says nothing was verified"
    $v1 = Stop-HordeIsolatedTmux -Instance ([pscustomobject]@{ socket = $e.socket; name = $e.name })
    Check ($v1.refused) "an instance with no token is refused"
    $v2 = Stop-HordeIsolatedTmux -Instance ([pscustomobject]@{ token = "horde-tmux-iso:" + $g2 })
    Check ($v2.refused) "a token in the right shape that this process never issued is refused"
    Check ($script:calls.Count -eq 0) "and none of the three reached WSL at all"

    # A DIFFERENT SERVER ON OUR SOCKET: same socket, another pid. Refused; kill-server never sent.
    $b = New-Entry
    $script:calls.Clear()
    Set-Healthy -Entry $b.entry -ServerPid "999"; $script:answer = $script:healthy
    $vb = Stop-HordeIsolatedTmux -Instance $b.inst
    Check ($vb.refused -and "$($vb.reason)" -like "*not the pid*") "a server on our socket that is not the one Start recorded is refused"
    Check ((Get-Calls "kill-server").Count -eq 0) "and kill-server was never sent to it"

    # OUR SERVER, HEALTHY: killed through our socket, verified gone, its namespace read empty, cleaned, token spent.
    $c = New-Entry
    $script:calls.Clear()
    Set-Healthy -Entry $c.entry; $script:answer = $script:healthy
    $vc = Stop-HordeIsolatedTmux -Instance $c.inst
    Check ($vc.stopped -and -not $vc.survived -and -not $vc.refused -and $vc.socketRemoved -and $vc.dirRemoved) "our own server is stopped, and its socket and directory reported removed"
    $ks = @(Get-Calls "kill-server")
    Check ($ks.Count -eq 1) "kill-server is sent exactly once"
    Check ($ks.Count -eq 1 -and ($ks[0].argv -join " ") -ceq ((Get-HordeTmuxArgv -Entry $c.entry -Command @("kill-server")) -join " ")) "and only through our socket, our directory and no config"
    $idAt = [array]::IndexOf(@($script:calls), @(Get-Calls "display-message")[0])
    $ksAt = [array]::IndexOf(@($script:calls), $ks[0])
    Check ($idAt -ge 0 -and $idAt -lt $ksAt) "the server proved who it was before it was killed"
    $cl = @($script:calls | Where-Object { $_.argv[0] -eq "sh" -and $_.argv[2] -eq $script:HordeTmuxCleanup })
    Check ($cl.Count -eq 1 -and $cl[0].argv[4] -ceq $c.entry.socket -and $cl[0].argv[5] -ceq ($c.entry.dir + "/tmux-0") -and $cl[0].argv[6] -ceq $c.entry.dir) "only our socket, our tmux-<uid> folder and our directory are handed to the cleanup"
    Check (@($script:calls | Where-Object { $_.distro -ne "fake-distro" }).Count -eq 0) "every call went to the distro Start recorded"
    $vc2 = Stop-HordeIsolatedTmux -Instance $c.inst
    Check ($vc2.refused) "a token is spent once used - the same server cannot be torn down twice"

    # EVERY tmux CALL in all of the above named our socket: no argv reached tmux without -L horde-iso-.
    $tm = @($script:calls | Where-Object { @($_.argv) -contains "tmux" })
    Check ($tm.Count -gt 0 -and @($tm | Where-Object { $i = [array]::IndexOf($_.argv, "-L"); $i -lt 0 -or $_.argv[$i + 1] -notmatch $script:HordeTmuxNamePattern }).Count -eq 0) "every tmux call teardown made names a horde-iso-<guid> socket"

    # THE CLEANUP SCRIPT: rmdir, never a recursive delete, and the socket only if it is a socket.
    Check ($script:HordeTmuxCleanup -match 'rmdir -- "\$sub"' -and $script:HordeTmuxCleanup -match 'rmdir -- "\$dir"' -and $script:HordeTmuxCleanup -notmatch 'rm -[a-zA-Z]*r') "directories are removed with rmdir, which refuses a folder holding anything, and never rm -r"
    Check ($script:HordeTmuxCleanup -match '\[ -S "\$sock" \] && rm -f -- "\$sock"') "the socket file is removed only if it is a socket"
    # Only a CRLF checkout can fail this - the gate runs the suites from one (core.autocrlf=true).
    $crlfIn = [System.IO.File]::ReadAllText($harnessPath).Contains("`r`n")
    Write-Host ("  this checkout's harness has " + $(if ($crlfIn) { "CRLF" } else { "LF" }) + " line endings") -ForegroundColor DarkGray
    Check (-not ($script:HordeTmuxOwner + $script:HordeTmuxNsScan + $script:HordeTmuxCleanup + $script:HordeTmuxPreflight).Contains("`r")) "the shell scripts handed to sh carry no carriage return, whatever the checkout's line endings"

    # THE SERVER WILL NOT DIE: its socket keeps answering after kill-server. The process check is made
    # to say "gone", so only the socket's answer can show the survival - teardown must measure it.
    $d = New-Entry
    $script:calls.Clear()
    $script:dLine = $d.entry.socket + "|4242|1790000000"
    $script:answer = { param($k, $a)
        if ($k -eq "tmux") { if ((Get-TmuxCommand $a)[0] -eq "display-message") { return (Reply 0 $script:dLine) }; return (Reply 0 "`$0|horde-iso") }
        if ($k -eq "alive") { return (Reply 0 "gone") }
        return (Reply 0 "") }
    $vd = Stop-HordeIsolatedTmux -Instance $d.inst
    Check ($vd.survived -and -not $vd.stopped) "a server that still answers after kill-server is reported as survived, not stopped"
    Check (@($script:calls | Where-Object { $_.argv[0] -eq "sh" -and $_.argv[2] -eq $script:HordeTmuxCleanup }).Count -eq 0 -and -not $vd.socketRemoved) "and its socket is left in place, not deleted under a live server"

    # THE NAMESPACE IS NOT EMPTY: the socket says no server, but a process is still in our namespace -
    # the review of PR 35's escape, a child with no mark of the server. Not stopped.
    $f = New-Entry
    $script:calls.Clear()
    Set-Healthy -Entry $f.entry
    $script:answer = { param($k, $a) if ($k -eq "nsscan") { return (Reply 0 "977 sleep 304`n") }; return (& $script:healthy $k $a) }
    $vf = Stop-HordeIsolatedTmux -Instance $f.inst
    Check ($vf.survived -and -not $vf.stopped) "a process still in our namespace after the server went is reported, and the teardown is not stopped"
    Check (@($vf.orphansSurvived) -contains "977 sleep 304") "and it is named"
    $al = @($script:calls | Where-Object { $_.argv[0] -eq "sh" -and $_.argv[2] -eq $script:HordeTmuxNsScan })
    Check ($al.Count -eq 1 -and $al[0].argv[4] -ceq "pid:[4026530001]") "the emptiness check reads the namespace Start recorded"

    # ASSERT MEASURES CONTAINMENT: a healthy server of ours passes; the same server answering from
    # outside our namespace does not.
    $as = New-Entry
    Set-Healthy -Entry $as.entry; $script:answer = $script:healthy
    $ac = $null; try { $ac = Assert-HordeTmuxIsolated -Instance $as.inst } catch { Write-Host ("         " + $_.Exception.Message) -ForegroundColor Red }
    Check ($ac -eq 1) "CONTROL: Assert passes a server of ours that is inside our namespace"
    $script:answer = { param($k, $a) if ($k -eq "nsscan") { return (Reply 0 "401 sh -c sess=`$1`n") }; return (& $script:healthy $k $a) }
    Check (Throws { Assert-HordeTmuxIsolated -Instance $as.inst } "not running inside our namespace") "Assert refuses a server that is not inside our namespace"
    $script:HordeTmuxStarted.Remove($as.inst.token)

    # THE SERVER IS ALREADY GONE: no kill-server needed; its namespace is still read, and it is cleaned.
    $j = New-Entry
    $script:calls.Clear()
    $script:answer = { param($k, $a) if ($k -eq "tmux") { return (Reply 1 "" "no server running on /tmp/horde-iso-x") }; return (Reply 0 "") }
    $vj = Stop-HordeIsolatedTmux -Instance $j.inst
    Check ($vj.stopped -and $vj.socketRemoved -and (Get-Calls "kill-server").Count -eq 0) "a server that is already gone reads as stopped, and nothing is sent kill-server"

    # NOTHING WAS MEASURED: the owner timed out before it reported its namespace (so there is no
    # namespace to scan) and its wsl.exe will not exit. The review of PR 35 (round 3) found teardown
    # then said "stopped" on the socket's word alone. Without a namespace, only the owner's exit is
    # evidence that pid 1 is gone - and with it everything it held.
    function New-FakeOwnerProc { param([bool]$Exits)
        $o = [pscustomobject]@{ exits = $Exits; closed = $false }
        $si = [pscustomobject]@{ parent = $o }
        $si | Add-Member -MemberType ScriptMethod -Name Close -Value { $this.parent.closed = $true }
        $o | Add-Member -NotePropertyName StandardInput -NotePropertyValue $si
        $o | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($ms) return $this.exits }
        $o | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        return $o }
    $un = New-Entry
    $un.entry.nsInode = ""; $un.entry.serverPid = ""
    $hung = New-FakeOwnerProc $false
    $un.entry.owner = [pscustomobject]@{ proc = $hung; nsInode = ""; ready = $false; failure = "the owner did not report ready in 30s" }
    $script:calls.Clear()
    $script:answer = { param($k, $a) if ($k -eq "tmux") { return (Reply 1 "" "no server running on /tmp/horde-iso-x") }; return (Reply 0 "") }
    $vu = Stop-HordeIsolatedTmux -Instance $un.inst
    Check (-not $vu.stopped -and $vu.survived -and "$($vu.reason)" -like "*never reported its namespace*") ("an owner that never reported its namespace and will not exit is not reported stopped (" + $vu.reason + ")")
    Check ($hung.closed) "and its stdin was closed first, which is pid 1's crash exit"
    $ug = New-Entry
    $ug.entry.nsInode = ""; $ug.entry.serverPid = ""
    $ug.entry.owner = [pscustomobject]@{ proc = (New-FakeOwnerProc $true); nsInode = ""; ready = $false; failure = "the owner did not report ready in 30s" }
    $vg = Stop-HordeIsolatedTmux -Instance $ug.inst
    Check ($vg.stopped) "CONTROL: the same owner that does exit is stopped - unshare, and so pid 1, are gone with it"

    # A SCAN THAT DID NOT FINISH IS NOT AN EMPTY NAMESPACE. The scan always exited 0, so an answer cut
    # short read as "nothing left" (the review of PR 35, round 3). It now ends with "scanned <n>".
    $sc = New-Entry
    $script:answer = { param($k, $a) return (Reply 0 "") }
    $script:rawScan = $true
    Check (Throws { Get-HordeTmuxNsProcs -Entry $sc.entry } "did not finish") "a namespace scan with no completion line throws, rather than reading as empty"
    $script:answer = { param($k, $a) return (Reply 0 "scanned 0`n") }
    Check (Throws { Get-HordeTmuxNsProcs -Entry $sc.entry } "did not finish") "and so does one that could read no process at all - it always reads itself"
    $script:answer = { param($k, $a) return (Reply 0 "977 sleep 304`nscanned 40`n") }
    $okScan = @(Get-HordeTmuxNsProcs -Entry $sc.entry)
    Check ($okScan.Count -eq 1 -and $okScan[0] -eq "977 sleep 304") "CONTROL: a finished scan returns its processes, without the completion line"
    $script:rawScan = $false
    $script:HordeTmuxStarted.Remove($sc.inst.token)

    # THE SOCKET ANSWERS WITH SOMETHING ELSE: neither "ours" nor "no server". Refused.
    $k2 = New-Entry
    $script:calls.Clear()
    $script:answer = { param($k, $a) if ($k -eq "tmux") { return (Reply 1 "" "server version is too old for client") }; return (Reply 0 "") }
    $vk = Stop-HordeIsolatedTmux -Instance $k2.inst
    Check ($vk.refused -and (Get-Calls "kill-server").Count -eq 0) "a socket that answers neither as our server nor as no server is refused"

    # WSL FAILS MID-TEARDOWN: nothing is claimed, and the token is kept so teardown can run again.
    $m = New-Entry
    $script:calls.Clear()
    $script:answer = { param($k, $a) if ($k -eq "tmux") { return (Reply -1 "There is no distribution with the supplied name." "") }; return (Reply 0 "") }
    $vm = Stop-HordeIsolatedTmux -Instance $m.inst
    Check (-not $vm.stopped -and -not $vm.refused -and "$($vm.reason)" -like "*WSL failed*") "a WSL failure mid-teardown claims nothing"
    Check ($script:HordeTmuxStarted.ContainsKey($m.inst.token)) "and keeps the token, so the teardown can be run again"
    $script:HordeTmuxStarted.Remove($m.inst.token)

    Write-Host ""
    Write-Host "--- start fails loudly, and leaves nothing ---" -ForegroundColor Cyan

    $before = $script:HordeTmuxStarted.Count
    $script:answer = { param($k, $a) if ($k -eq "preflight") { return (Reply -1 "There is no distribution with the supplied name." "") }; return (Reply 0) }
    Check (Throws { Start-HordeIsolatedTmux -Distro "no-such-distro" } "tmux host unavailable: wsl.exe failed (exit -1)") "a missing distro throws, naming wsl.exe's exit -1"
    $script:answer = { param($k, $a) if ($k -eq "preflight") { return (Reply 127 "no-such|0|" "sh: 1: tmux: not found") }; return (Reply 0) }
    Check (Throws { Start-HordeIsolatedTmux -Distro "no-such" } "tmux: not found") "tmux missing from the distro throws, with the shell's words"
    $script:answer = { param($k, $a) if ($k -eq "preflight") { return (Reply 0 "other|0|tmux 3.4") }; return (Reply 0) }
    Check (Throws { Start-HordeIsolatedTmux -Distro "wanted" } "reached 'other'") "a distro other than the one asked for throws"
    $script:answer = { param($k, $a) if ($k -eq "preflight") { return (Reply 0 "fake-distro|0|tmux 3.4") }; if ($k -eq "mkdir") { return (Reply 1 "" "mkdir: cannot create directory: File exists") }; return (Reply 0) }
    Check (Throws { Start-HordeIsolatedTmux -Distro "fake-distro" } "private socket directory") "a socket directory that already exists is never adopted"
    $mk = @($script:calls | Where-Object { $_.argv[0] -eq "mkdir" } | Select-Object -Last 1)
    Check ($mk.Count -eq 1 -and ($mk[0].argv -join " ") -match '^mkdir -m 700 -- /tmp/horde-iso-[0-9a-f]{32}$') "the directory is made by plain mkdir (no -p), mode 700, at /tmp/horde-iso-<guid>"
    Check ($script:HordeTmuxStarted.Count -eq $before) "and none of those failures left anything registered"

    $script:answer = { param($k, $a) if ($k -eq "preflight") { return (Reply 3 "" "unshare (util-linux) is not installed in the distro") }; return (Reply 0) }
    Check (Throws { Start-HordeIsolatedTmux -Distro "fake-distro" } "unshare (util-linux) is not installed") "unshare missing from the distro throws - containment is not optional"

    $script:HordeTmuxOwnerLauncher = $fakeOwner
    $script:calls.Clear()
    $script:ownerAnswer = [pscustomobject]@{ proc = $null; nsInode = "pid:[4026530002]"; ready = $false; failure = "the owner said: new-session-failed" }
    $script:answer = { param($k, $a)
        if ($k -eq "preflight") { return (Reply 0 "fake-distro|0|tmux 3.4") }
        if ($k -eq "mkdir") { return (Reply 0) }
        if ($k -eq "tmux") { return (Reply 1 "" "no server running on x") }
        return (Reply 0 "") }
    Check (Throws { Start-HordeIsolatedTmux -Distro "fake-distro" } "new-session-failed") "a contained server that fails to start throws, with the owner's words"
    $cl2 = @($script:calls | Where-Object { $_.argv[0] -eq "sh" -and $_.argv[2] -eq $script:HordeTmuxCleanup })
    Check ($cl2.Count -eq 1 -and $cl2[0].argv[6] -match '^/tmp/horde-iso-[0-9a-f]{32}$') "and its half-made directory is cleaned up by the teardown"
    Check ($script:HordeTmuxStarted.Count -eq $before) "and its token is gone"
    $ow = @($script:calls | Where-Object { $_.argv[0] -eq "unshare" })
    Check ($ow.Count -eq 1) "the owner was started exactly once"
    Check ($ow.Count -eq 1 -and ($ow[0].argv[0..8] -join " ") -ceq ("unshare --pid --fork --kill-child --mount-proc sh -c " + $script:HordeTmuxOwner + " sh")) "as pid 1 of a new pid namespace, killed with unshare, with its own /proc"
    $od = @($script:calls | Where-Object { $_.argv[0] -eq "mkdir" } | Select-Object -Last 1)[0].argv[4]
    Check ($ow.Count -eq 1 -and $ow[0].argv[10] -ceq ($od + "/tmux-0/" + $od.Substring(5)) -and $ow[0].argv[11] -ceq ($od + "/tmux-0") -and $ow[0].argv[12] -ceq $od) "pid 1 is told our socket, our tmux-<uid> folder and our directory, to remove when it exits"
    Check ($ow.Count -eq 1 -and $ow[0].argv[9] -ceq "horde-iso" -and ($ow[0].argv[13..($ow[0].argv.Count - 1)] -join " ") -match '^env -C /tmp/horde-iso-([0-9a-f]{32}) -u TMUX -u TMUX_PANE TMUX_TMPDIR=/tmp/horde-iso-\1 tmux -L horde-iso-\1 -f /dev/null$') "and it names the server through the same argv as every other call"
    Check ((Get-Calls "new-session").Count -eq 0) "no new-session is ever sent from outside - a client that finds no server would start an unconfined one"

    # THE SERVER ANSWERS BUT IS NOT IN OUR NAMESPACE: refused, and our socket's server is killed.
    $script:calls.Clear()
    $script:ownerAnswer = [pscustomobject]@{ proc = $null; nsInode = "pid:[4026530003]"; ready = $true; failure = "" }
    $script:answer = { param($k, $a)
        if ($k -eq "preflight") { return (Reply 0 "fake-distro|0|tmux 3.4") }
        if ($k -eq "mkdir") { return (Reply 0) }
        if ($k -eq "nsscan") { return (Reply 0 "401 sh -c sess=`$1`n") }
        if ($k -eq "tmux") {
            $d0 = @($script:HordeTmuxStarted.Values | Where-Object { $_.nsInode -eq "pid:[4026530003]" }) | Select-Object -First 1
            if ((Get-TmuxCommand $a)[0] -eq "display-message" -and $d0) { return (Reply 0 ($d0.socket + "|3|1790000000")) }
            return (Reply 1 "" "no server running on x") }
        return (Reply 0 "") }
    Check (Throws { Start-HordeIsolatedTmux -Distro "fake-distro" } "not running inside our namespace") "a server that is not inside our namespace is never handed to a test"
    Check ($script:HordeTmuxStarted.Count -eq $before) "and it is torn down"
    $script:HordeTmuxOwnerLauncher = $null
} finally {
    $script:HordeTmuxTransport = $null
    $script:HordeTmuxOwnerLauncher = $null
}

Write-Host ""
Write-Host "--- loading the harness again forgets nothing ---" -ForegroundColor Cyan

$n = New-Entry
. $harnessPath
Check ($script:HordeTmuxStarted.ContainsKey($n.inst.token)) "a second dot-source keeps the registry - teardown would otherwise refuse, and leak, every live server"
Check ($null -eq $script:HordeTmuxTransport) "and the transport is the real one again"
$script:HordeTmuxStarted.Remove($n.inst.token)

Write-Host ""
Write-Host "--- the code: one way to reach WSL, one way to build a tmux call ---" -ForegroundColor Cyan

function Get-CodeOnly { param([string]$Path) return ((Get-Content -LiteralPath $Path) | Where-Object { -not $_.TrimStart().StartsWith("#") }) -join "`n" }
$code = Get-CodeOnly $harnessPath
Check (([regex]::Matches($code, 'FileName\s*=')).Count -eq 1 -and $code -match '\$psi\.FileName = "wsl\.exe"' -and $code -notmatch 'Start-Process|Process\]::Start\(\s*"') "wsl.exe is started in exactly one place, Invoke-HordeWsl, and no other process is started at all"
Check ($code -notmatch '&\s*wsl') "and never through PowerShell's & (which mis-quotes an argument holding a double quote)"
Check ($code -match '\$all \+= "--exec"' -and $code -notmatch '"--",\s*"tmux"') "every call uses --exec, never wsl's -- form, which hands the arguments to a shell to rewrite"
Check (([regex]::Matches($code, '"tmux", "-L"')).Count -eq 1) "tmux's argv is built in exactly one place, Get-HordeTmuxArgv"
Check ($code -notmatch 'pkill|killall|kill-server -a|rm -rf|rm -r ') "no pkill, killall, kill-server -a or recursive delete anywhere in the harness"
# NO PER-PID KILL. Containment makes one unnecessary, and the review of PR 35 found the one there was
# had a gap between checking a pid and killing it. The only kill left is pid 1's watcher stopping its
# own unreaped child inside its own namespace, which can name nothing else.
# WIDENED in round 3: the first version matched only `kill -<UPPER|digit>`, so a bare `kill "$p"`,
# `kill -s KILL`, a perl kill() or a pidfd_send_signal would have passed. Every form of sending a
# signal is matched now; `kill-server` (tmux's own verb, sent through our socket) is not a signal.
function Get-SignalSends { param([string]$Text)
    return @([regex]::Matches($Text, '(?<![\w-])kill(?!-server)\b[^\n]*|pidfd_send_signal|syscall\s*\(\s*424|\.Kill\(\)|Stop-Process|taskkill') | ForEach-Object { $_.Value.Trim() }) }
foreach ($bait in @('kill "$p"', 'kill -s KILL "$p"', 'kill -9 "$p"', 'perl -e "kill 9, $p"', 'syscall(424, $fd, 9, 0, 0)', 'pidfd_send_signal', '$x.Kill()', 'Stop-Process -Id 4')) {
    Check (@(Get-SignalSends $bait).Count -ge 1) ("CONTROL: the guard sees a signal sent as " + $bait)
}
Check (@(Get-SignalSends 'tmux -L x kill-server').Count -eq 0) "CONTROL: tmux's kill-server verb is not a signal"
$shellText = $script:HordeTmuxOwner + "`n" + $script:HordeTmuxNsScan + "`n" + $script:HordeTmuxCleanup + "`n" + $script:HordeTmuxPreflight
$kills = @(Get-SignalSends $shellText)
Check ($kills.Count -eq 1 -and $kills[0] -match '^kill -TERM "\$srv"') ("every shell script the harness hands to sh signals nothing but pid 1's own server child (" + ($kills -join " | ") + ")")
$psKills = @([regex]::Matches($code, '\.Kill\(\)|Stop-Process|taskkill|pidfd_send_signal|syscall\s*\(') | ForEach-Object { $_.Value })
Check ($psKills.Count -eq 1 -and $psKills[0] -eq '.Kill()') ("and the only kill in its PowerShell is one wsl.exe call it started and holds, on timeout (" + ($psKills -join " | ") + ")")
$e2eText = ((Get-Content -LiteralPath (Join-Path $here "e2e\e2e-isolation.ps1")) | Where-Object { -not $_.TrimStart().StartsWith("#") }) -join "`n"
$e2eSignals = @([regex]::Matches($e2eText, 'pidfd_send_signal|syscall\(424|kill -9|kill "\$') | ForEach-Object { $_.Value })
Check ($e2eSignals.Count -eq 1 -and $e2eSignals[0] -eq 'syscall(424') ("the e2e signals only through its one pidfd helper (" + ($e2eSignals -join " | ") + ")")
Check ($code -notmatch '/proc/\[0-9\]\*/environ') "and it reads no process's environment to decide what to kill"
Check ($script:HordeTmuxOwner -match '(?m)^"\$@" -D </dev/null' -and $script:HordeTmuxOwner -match '(?m)^wait "\$srv"$' -and $script:HordeTmuxOwner -match '(?m)^"\$@" new-session ') "pid 1 runs the server in the foreground as its child, makes the session from inside, and waits on the server"
Check ($script:HordeTmuxOwner -match '(?m)^exec 3<&0$' -and $script:HordeTmuxOwner -match '(?m)^\{ cat >/dev/null; kill -TERM "\$srv" 2>/dev/null; \} <&3 &$' -and $script:HordeTmuxOwner -match '(?m)^"\$@" -D </dev/null >/dev/null 2>&1 3<&- &$') "pid 1 watches the owner's stdin on fd 3 and stops the server at EOF - the crash exit - and the server does not hold that stdin"
Check ($script:HordeTmuxOwner -match '(?m)^if \[ -S "\$sock" \]; then rm -f -- "\$sock"; fi$' -and $script:HordeTmuxOwner -match '(?m)^rmdir -- "\$sub" "\$dir" 2>/dev/null$' -and $script:HordeTmuxOwner -notmatch 'rm -[a-zA-Z]*r') "and when the server has gone, pid 1 removes our socket and directories by rmdir, never recursively"

# The first host's 2026-09-29 lesson (L-018): a script that starts an isolated terminal must tear it
# down by the real name. Guarded for this host's starter too.
$self = $PSCommandPath
$scripts = @(Get-ChildItem -Path $root -Recurse -Include *.ps1 -File | Where-Object { $_.FullName -ne $harnessPath -and $_.FullName -ne $self })
$starters = @($scripts | Where-Object { (Get-CodeOnly $_.FullName) -match "Start-HordeIsolatedTmux" })
Check ($starters.Count -gt 0) "CONTROL: the scan finds at least one script that starts an isolated tmux server"
foreach ($s in $starters) { Write-Host ("  starter: " + $s.Name) -ForegroundColor DarkGray }
Check (@($starters | Where-Object { (Get-CodeOnly $_.FullName) -notmatch "Stop-HordeIsolatedTmux" }).Count -eq 0) "every script that starts one calls Stop-HordeIsolatedTmux by its real name"

foreach ($k in @($script:HordeTmuxStarted.Keys)) { $script:HordeTmuxStarted.Remove($k) }
Complete-HordeSuite -Success "the tmux harness refuses a server it did not start, and fails loudly without WSL or tmux"
