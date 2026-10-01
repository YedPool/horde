# Isolation.ps1 - a tmux server that is ours alone, for tests that are allowed to break a terminal.
#
# The tmux counterpart of the first host's isolation harness, and held to the same rule (CONTRIBUTING
# 3): the worst a test here can do is destroy the server it created. That harness's lessons are in its
# isolation ledger under planning/ledger/; the ones that carry over are cited below as L-nnn.
#
# WHERE tmux RUNS. There is no native Windows tmux. This harness drives tmux inside WSL, through
# `wsl.exe -d <distro> --exec`. The distro is a parameter; left empty, WSL's default distro is
# resolved once, by name, and every later call is pinned to that name.
#
# WHAT MAKES A SERVER OURS, all four on every call, built in ONE function (Get-HordeTmuxArgv) from the
# registry, never from an object handed in (L-001, L-028):
#   -L horde-iso-<guid>          a socket name nobody else uses. tmux's man page: -L "allows a
#                                different socket name to be specified, allowing several independent
#                                tmux servers to be run".
#   TMUX_TMPDIR=/tmp/horde-iso-<guid>
#                                a socket DIRECTORY nobody else uses, made by `mkdir` (which fails if
#                                it exists), so even a wrong socket name cannot land among the user's.
#   env -C /tmp/horde-iso-<guid> MEASURED 2026-09-30, tmux 3.4: when TMUX_TMPDIR names a directory that
#                                does not exist, tmux SILENTLY FALLS BACK to /tmp - `list-sessions`
#                                answered "error connecting to /tmp/tmux-0/<name>". So a call made after
#                                our directory is gone would look in the user's socket directory. `env
#                                -C` changes into the directory first and exits 125 without running
#                                tmux if it is missing (measured), which makes that fallback impossible.
#   -f /dev/null                 no config: the user's ~/.tmux.conf is never loaded (L-006's lesson).
# And the environment is scrubbed on both sides of the WSL boundary: TMUX, TMUX_PANE and WSLENV are
# removed from the wsl.exe child's environment on Windows (WSLENV is what carries a Windows variable
# into Linux; on this machine it was already set by the outer terminal), and TMUX and TMUX_PANE are
# unset again on the Linux side with `env -u`. Inside a tmux pane a bare tmux command follows $TMUX to
# the server that pane lives in - the same trap as the first host's socket variable (L-003).
#
# THE WSL BOUNDARY, three traps, all measured 2026-09-30 (WSL 2.7.8.0, tmux 3.4):
#   1. `wsl.exe -- cmd args` hands the arguments to the Linux shell, which rewrites them: `$HOME` in an
#      argument came back as /root, and an unquoted `|` became a pipe. `wsl.exe --exec` runs the
#      program with its arguments untouched. Every tmux -F format holds `#{}` and a separator, so only
#      --exec is ever used here.
#   2. wsl.exe's OWN messages are UTF-16LE with no byte order mark, and for a missing distro they come
#      on STDOUT, not stderr ("T\0h\0e\0r\0e\0 \0i\0s\0 \0n\0o\0..."). The Linux program's output is
#      UTF-8 bytes. Both streams are read as bytes and decoded by ConvertFrom-HordeWslBytes.
#   3. Exit codes: a missing distro exits -1 (wsl.exe's own failure); a missing program exits 1 with
#      "execvpe(<name>) failed" on stderr - the same exit code tmux uses for "no server running". So
#      exit 1 alone never means "tmux said no"; Get-HordeWslFailure tells the three apart.
# And the command line: wsl.exe receives one Windows command-line string, so each argument is quoted
# by ConvertTo-HordeWinArg (the rules CommandLineToArgvW reads). PowerShell 5.1's `&` mis-quotes an
# argument holding a double quote, so no native call here goes through `&`.
#
# WHAT IS NOT ISOLATED, said plainly (L-027): processes started inside the server run as the distro's
# user, with that user's files. None of the scenarios here starts an agent.
#
# CONTAINED, NOT REAPED. The server runs as a child of pid 1 of a pid namespace of its own
# (`unshare --pid --fork --kill-child --mount-proc`), and so does everything started in it. A process
# cannot leave a pid namespace - not by dropping its environment, not by setsid, not by double-forking -
# and when pid 1 of a namespace exits, the kernel kills every process left in it. The review of PR 35
# measured the escape this closes: a pane child started as `env -i sh -c 'trap "" HUP; exec sleep 304'`
# carries no TMUX variable, ignores the SIGHUP kill-server sends, and survived a teardown that reported
# "stopped". MEASURED 2026-09-30 (util-linux 2.39.3): with the server contained, that child and a
# setsid'd one were both gone when pid 1 exited, whether kill-server or a closed stdin ended it.
#
# The server is killed only by `kill-server` through its own socket, after the server that answers on
# that socket has proved it is the one Start recorded: same socket path, same pid, same start time.
# Teardown then requires the namespace to be EMPTY - no process whose /proc/<pid>/ns/pid is ours -
# before it says "stopped". tmux 3.4 leaves its socket file behind (measured); it is removed only if it
# is a socket at our exact path. Directories are removed with `rmdir`, which refuses a directory that
# is not empty, never `rm -r`.

if ($null -eq $script:HordeTmuxStarted) { $script:HordeTmuxStarted = @{} }
# The transport is replaceable so the fast suite can prove what the harness WOULD send without a WSL
# in the loop. $null means the real one. A test that sets it puts it back.
if (-not (Test-Path variable:script:HordeTmuxTransport)) { $script:HordeTmuxTransport = $null }
# And the owner - the one long-lived wsl.exe that holds the namespace - is replaceable for the same
# reason. $null means the real one.
if (-not (Test-Path variable:script:HordeTmuxOwnerLauncher)) { $script:HordeTmuxOwnerLauncher = $null }

$script:HordeTmuxSession = "horde-iso"
$script:HordeTmuxNamePattern = '^horde-iso-[0-9a-f]{32}$'

function ConvertTo-HordeWinArg {
    # One argument, quoted so that CommandLineToArgvW - which wsl.exe uses - reads it back unchanged.
    # Backslashes are literal except in a run that ends at a double quote, where each is doubled.
    param([string]$Arg)
    if ($Arg -ne "" -and $Arg -notmatch '[\s"]') { return $Arg }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $slashes = 0
    $bs = [char]92
    foreach ($ch in $Arg.ToCharArray()) {
        if ($ch -eq $bs) { $slashes++; continue }
        if ($ch -eq [char]34) { [void]$sb.Append($bs, 2 * $slashes + 1); [void]$sb.Append([char]34); $slashes = 0; continue }
        if ($slashes) { [void]$sb.Append($bs, $slashes); $slashes = 0 }
        [void]$sb.Append($ch)
    }
    if ($slashes) { [void]$sb.Append($bs, 2 * $slashes) }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function ConvertFrom-HordeWslBytes {
    # Bytes from wsl.exe, as text. UTF-16LE when it has the byte order mark, or when it is an even
    # number of bytes and at least a third of the odd-position bytes are NUL (wsl.exe's own messages
    # carry no mark, measured); UTF-8 otherwise, which is what the Linux program writes.
    param([byte[]]$Bytes)
    if ($null -eq $Bytes -or $Bytes.Length -eq 0) { return "" }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2)
    }
    if ($Bytes.Length % 2 -eq 0) {
        $nul = 0
        for ($i = 1; $i -lt $Bytes.Length; $i += 2) { if ($Bytes[$i] -eq 0) { $nul++ } }
        if ($nul * 3 -ge $Bytes.Length / 2) { return [System.Text.Encoding]::Unicode.GetString($Bytes) }
    }
    return [System.Text.Encoding]::UTF8.GetString($Bytes)
}

function Get-HordeWslFailure {
    # Did the call fail on the WSL side of the boundary, before or instead of the Linux program? Returns
    # the reason, or "" when the Linux program ran and its own exit code is the answer.
    param($Result)
    if ($null -eq $Result) { return "no result" }
    if ($Result.startError) { return "wsl.exe could not be started: " + $Result.startError }
    if ($Result.timedOut) { return "wsl.exe did not finish in time and was stopped" }
    # -1 is wsl.exe's own failure: a missing distro, a stopped service. Its message is on stdout.
    if ($Result.code -eq -1) { return "wsl.exe failed (exit -1): " + (($Result.out + " " + $Result.err).Trim() -replace '\s+', ' ') }
    if ($Result.err -match 'execvpe\((.*?)\) failed') { return "'" + $Matches[1] + "' is not installed in the WSL distro: " + ($Result.err.Trim() -replace '\s+', ' ') }
    return ""
}

function New-HordeWslStartInfo {
    # How wsl.exe is started, for a short call and for the owner alike: --exec, each argument quoted,
    # all three streams redirected, and TMUX, TMUX_PANE and WSLENV removed from the CHILD's environment
    # so nothing inherited from an outer terminal crosses into Linux.
    param([string]$Distro, [string[]]$Argv)
    $all = @()
    if ($Distro) { $all += @("-d", $Distro) }
    $all += "--exec"
    $all += $Argv
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "wsl.exe"
    $psi.Arguments = (@($all | ForEach-Object { ConvertTo-HordeWinArg $_ }) -join " ")
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($v in @("TMUX", "TMUX_PANE", "WSLENV")) { if ($psi.EnvironmentVariables.ContainsKey($v)) { $psi.EnvironmentVariables.Remove($v) } }
    return $psi
}

function Invoke-HordeWsl {
    # THE ONE PLACE wsl.exe IS RUN. Returns { code; out; err; timedOut; startError }.
    #
    # Through the process API, not `&`: both streams are read as bytes (trap 2 above), no `2>&1` is
    # needed (CONTRIBUTING 12), stdin is closed so nothing can wait on the console, and a call that
    # hangs is stopped through the handle this function has held since it started the process.
    #
    # The child's environment, not this process's, is scrubbed: TMUX, TMUX_PANE and WSLENV are removed
    # so nothing inherited from an outer terminal crosses into Linux.
    #
    # -Distro "" runs in WSL's default distro; only Start uses that, to learn the default's name.
    param([string]$Distro, [string[]]$Argv, [int]$TimeoutSeconds = 30)
    if ($script:HordeTmuxTransport) { return (& $script:HordeTmuxTransport $Distro $Argv $TimeoutSeconds) }
    $psi = New-HordeWslStartInfo -Distro $Distro -Argv $Argv
    $p = $null
    try { $p = [System.Diagnostics.Process]::Start($psi) } catch {
        return [pscustomobject]@{ code = $null; out = ""; err = ""; timedOut = $false; startError = "$($_.Exception.Message)" }
    }
    try {
        $p.StandardInput.Close()
        $outMs = New-Object System.IO.MemoryStream
        $errMs = New-Object System.IO.MemoryStream
        $t1 = $p.StandardOutput.BaseStream.CopyToAsync($outMs)
        $t2 = $p.StandardError.BaseStream.CopyToAsync($errMs)
        if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
            try { $p.Kill() } catch { }
            [void]$p.WaitForExit(5000)
            return [pscustomobject]@{ code = $null; out = ""; err = ""; timedOut = $true; startError = "" }
        }
        $p.WaitForExit()
        [void][System.Threading.Tasks.Task]::WaitAll(@($t1, $t2), 10000)
        return [pscustomobject]@{ code = $p.ExitCode; out = (ConvertFrom-HordeWslBytes $outMs.ToArray())
                                  err = (ConvertFrom-HordeWslBytes $errMs.ToArray()); timedOut = $false; startError = "" }
    } finally { $p.Dispose() }
}

function Get-HordeTmuxArgv {
    # The Linux argv of one tmux command against a registered server. The ONLY place tmux's argv is
    # built, so no call can leave out the socket name, the private directory, the config or the scrub.
    # Refuses an entry whose name and directory are not the pair Start makes from one guid.
    param($Entry, [string[]]$Command)
    if (-not $Entry) { throw "no registered server" }
    $g = "$($Entry.guid)"
    if ($g -notmatch '^[0-9a-f]{32}$' -or "$($Entry.name)" -ne ("horde-iso-" + $g) -or "$($Entry.dir)" -ne ("/tmp/horde-iso-" + $g)) {
        throw ("refusing to build a tmux call for '" + $Entry.name + "' in '" + $Entry.dir + "': not a server this harness names")
    }
    return @("env", "-C", $Entry.dir, "-u", "TMUX", "-u", "TMUX_PANE", ("TMUX_TMPDIR=" + $Entry.dir),
             "tmux", "-L", $Entry.name, "-f", "/dev/null") + @($Command)
}

function Get-HordeTmuxEntry {
    # The registry entry behind an instance, or $null. Only a token this process issued counts; the
    # object handed in steers nothing else.
    param($Instance)
    if ($Instance -and $Instance.token -and $script:HordeTmuxStarted.ContainsKey("$($Instance.token)")) { return $script:HordeTmuxStarted["$($Instance.token)"] }
    return $null
}

function Invoke-HordeTmux {
    # One tmux command against an instance this process started. Throws on a WSL-side failure, so a
    # caller never reads "WSL is broken" as "tmux said no".
    param($Instance, [string[]]$Command, [int]$TimeoutSeconds = 30)
    $e = Get-HordeTmuxEntry $Instance
    if (-not $e) { throw "not a tmux server this process started (no registered token)" }
    $r = Invoke-HordeWsl -Distro $e.distro -Argv (Get-HordeTmuxArgv -Entry $e -Command $Command) -TimeoutSeconds $TimeoutSeconds
    $why = Get-HordeWslFailure $r
    if ($why) { throw $why }
    return $r
}

function Test-HordeTmuxNoServer {
    # Did tmux answer that no server is listening on the socket? Both wordings were measured on tmux
    # 3.4: "no server running on <path>" and "error connecting to <path> (No such file or directory)".
    # And a call that `env -C` stopped because our private directory is gone (exit 125, "cannot change
    # directory", measured) means the same: no server can be listening on a socket in a directory that
    # does not exist. Pid 1 removes that directory when its server exits, so after a clean stop this is
    # the answer teardown gets.
    param($Result)
    if (-not $Result) { return $false }
    if ($Result.code -eq 1 -and ($Result.err -match 'no server running on|error connecting to')) { return $true }
    return [bool]($Result.code -eq 125 -and ($Result.err -match '^env: cannot change directory'))
}

function Test-HordeTmuxIdentity {
    # Is the server that answered the one recorded? Line is display-message's "socket|pid|start".
    # Returns $null, or the reason it is not.
    param($Entry, [string]$Line)
    $parts = @("$Line".Trim() -split '\|')
    if ($parts.Count -ne 3) { return "the server's identity line '" + $Line + "' is not socket|pid|start" }
    if ($parts[0] -cne "$($Entry.socket)") { return "the server answers on '" + $parts[0] + "', not on our socket '" + $Entry.socket + "'" }
    if ($parts[1] -ne "$($Entry.serverPid)" -or $parts[2] -ne "$($Entry.startTime)") {
        return "the server on our socket is pid " + $parts[1] + " started " + $parts[2] + ", not the pid " + $Entry.serverPid + " started " + $Entry.startTime + " that Start recorded"
    }
    return $null
}

function Test-HordeTmuxIsolation {
    # The decision half of the isolation check, with no tmux in it. Returns $null when the server holds
    # exactly one session and one pane - a fresh server of ours - or the reason it does not.
    # ZERO IS UNKNOWN, NOT EMPTY (L-012): a list that came back empty is a failed read.
    param([string[]]$Sessions, [string[]]$Panes)
    $s = @($Sessions | Where-Object { "$_".Trim() })
    $p = @($Panes | Where-Object { "$_".Trim() })
    if ($s.Count -eq 0 -or $p.Count -eq 0) { return "no sessions or no panes listed - that is unknown, not empty" }
    if ($s.Count -ne 1) { return "" + $s.Count + " sessions on the server - a fresh isolated server has exactly one" }
    if ($p.Count -ne 1) { return "" + $p.Count + " panes on the server - a fresh isolated server has exactly one" }
    if ($s[0] -notmatch ('\|' + [regex]::Escape($script:HordeTmuxSession) + '$')) { return "the one session is '" + $s[0] + "', not the harness's '" + $script:HordeTmuxSession + "'" }
    return $null
}

function Get-HordeTmuxLines { param([string]$Text) return @(("$Text" -split "`r?`n") | Where-Object { $_.Trim() }) }

# PID 1 OF THE NAMESPACE. Arguments: the session name, our socket path, our tmux-<uid> folder, our
# directory, then the tmux argv prefix Get-HordeTmuxArgv builds (so the server is named in exactly the
# same one place as every other call). It prints its namespace ("pid:[<inode>]"), starts the server in
# the foreground (-D) as its child, waits until the server answers, makes the one session FROM INSIDE -
# no command from outside ever creates a server, because a client that finds no server starts an
# unconfined one - prints "ready", and then waits on the server. When the server exits, pid 1 removes
# our socket and directories (the cleanup script's rules) and exits, and the kernel kills everything
# left in the namespace.
#
# THE CRASH EXIT. Its stdin is the owner wsl.exe's stdin, which only the process that started the
# owner holds. The review of PR 35 found that a run that died without tearing down left its server and
# its directory behind forever. Now a watcher reads that stdin, and at EOF - the teardown closing it, or
# the Windows process that held it dying (measured: killing that PowerShell delivered EOF in Linux) -
# stops the server, and pid 1's exit does the rest. The watcher's `kill` is of pid 1's own unreaped
# child, inside our own namespace: it can name nothing else.
#
# fd 3 keeps that stdin for the watcher: an asynchronous list in a non-interactive shell gets
# /dev/null as its stdin (POSIX), so the watcher reads fd 3, not fd 0. The server gets neither.
$script:HordeTmuxOwner = @'
sess=$1; sock=$2; sub=$3; dir=$4; shift 4
exec 3<&0
readlink /proc/self/ns/pid
"$@" -D </dev/null >/dev/null 2>&1 3<&- &
srv=$!
{ cat >/dev/null; kill -TERM "$srv" 2>/dev/null; } <&3 &
exec 3<&-
i=0
until "$@" list-sessions >/dev/null 2>&1; do
  i=$((i+1)); [ "$i" -gt 100 ] && { echo "server-did-not-start"; exit 1; }
  sleep 0.1
done
"$@" new-session -d -s "$sess" -x 160 -y 48 -c /tmp -- sh </dev/null >/dev/null 2>&1 || { echo "new-session-failed"; exit 1; }
echo ready
wait "$srv"
if [ -S "$sock" ]; then rm -f -- "$sock"; fi
rmdir -- "$sub" "$dir" 2>/dev/null
exit 0
'@ -replace "`r", ""

# Every process whose pid namespace is $1 ("pid:[<inode>]"), one per line: "<pid> <command line>".
# Read from OUTSIDE the namespace, so the pids are the distro's. Newlines in a command line are
# flattened so one process is one line. It ENDS with "scanned <n>", n being how many processes'
# namespaces it could read: without that line, or with n = 0 (it always reads at least itself), the
# scan did not finish, and Get-HordeTmuxNsProcs refuses to read it as empty (the review of PR 35,
# round 3: the scan always exited 0, so a cut-short answer read as "nothing left").
$script:HordeTmuxNsScan = @'
n=0
for f in /proc/[0-9]*/ns/pid; do
  l=$(readlink "$f" 2>/dev/null) || continue
  n=$((n+1))
  [ "$l" = "$1" ] || continue
  p=${f#/proc/}; p=${p%/ns/pid}
  printf '%s %s\n' "$p" "$(tr '\0\n' '  ' < "/proc/$p/cmdline" 2>/dev/null)"
done
echo "scanned $n"
'@ -replace "`r", ""

function Get-HordeTmuxOwnerArgv {
    # The owner's Linux argv: pid 1 of a fresh pid namespace, running $script:HordeTmuxOwner.
    #   --pid --fork   the command runs as pid 1 of a new pid namespace (--fork is required for that);
    #   --kill-child   if unshare itself dies, pid 1 is killed, and with it the namespace;
    #   --mount-proc   a /proc of the namespace's own, so what runs inside sees only the namespace.
    param($Entry)
    return @("unshare", "--pid", "--fork", "--kill-child", "--mount-proc", "sh", "-c", $script:HordeTmuxOwner, "sh", $script:HordeTmuxSession,
             $Entry.socket, ($Entry.dir + "/tmux-" + $Entry.uid), $Entry.dir) + (Get-HordeTmuxArgv -Entry $Entry -Command @())
}

function Start-HordeWslOwner {
    # Start the owner and hold it: one wsl.exe for the life of the instance, through the process API,
    # so this process keeps its handle and its stdin. Its stdin is NEVER closed here: while this process
    # holds it open the server lives, and when this process dies without a teardown the pipe closes and
    # pid 1 takes the server down (see $script:HordeTmuxOwner). Reads its lines until "ready", a failure
    # word, or the timeout. Returns { proc; nsInode; ready; failure }.
    param([string]$Distro, [string[]]$Argv, [int]$TimeoutSeconds = 30)
    if ($script:HordeTmuxOwnerLauncher) { return (& $script:HordeTmuxOwnerLauncher $Distro $Argv $TimeoutSeconds) }
    $out = [pscustomobject]@{ proc = $null; nsInode = ""; ready = $false; failure = "" }
    try { $out.proc = [System.Diagnostics.Process]::Start((New-HordeWslStartInfo -Distro $Distro -Argv $Argv)) } catch { $out.failure = "wsl.exe could not be started: " + $_.Exception.Message; return $out }
    # stderr is drained so a chatty child can never block on a full pipe.
    [void]$out.proc.StandardError.ReadToEndAsync()
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while (-not $out.ready -and -not $out.failure) {
        $left = [int]($deadline - (Get-Date)).TotalMilliseconds
        if ($left -le 0) { $out.failure = "the owner did not report ready in " + $TimeoutSeconds + "s"; break }
        $t = $out.proc.StandardOutput.ReadLineAsync()
        if (-not $t.Wait($left)) { $out.failure = "the owner did not report ready in " + $TimeoutSeconds + "s"; break }
        $line = $t.Result
        if ($null -eq $line) { $out.failure = "the owner exited before it was ready"; break }
        $line = $line.Trim()
        if ($line -match '^pid:\[\d+\]$') { $out.nsInode = $line }
        elseif ($line -eq "ready") { $out.ready = $true }
        else { $out.failure = "the owner said: " + $line }
    }
    return $out
}

function Test-HordeTmuxContained {
    # Is our server inside our namespace? Lines are Get-HordeTmuxNsProcs's "<pid> <command line>".
    # Returns $null, or the reason it is not. The server is the one process running
    # "tmux -L <our name> -f /dev/null -D".
    param($Entry, [string[]]$Lines)
    $l = @($Lines | Where-Object { "$_".Trim() })
    if ($l.Count -eq 0) { return "no process is in our namespace '" + $Entry.nsInode + "' - that is unknown, not contained" }
    $want = "tmux -L " + $Entry.name + " -f /dev/null -D"
    if (@($l | Where-Object { $_ -match ('^\d+ ' + [regex]::Escape($want) + '\s*$') }).Count -ne 1) {
        return "our server ('" + $want + "') is not running inside our namespace '" + $Entry.nsInode + "'"
    }
    return $null
}

function Get-HordeTmuxNsProcs {
    # The processes in an entry's namespace, as "<pid> <command line>" lines. Throws on a WSL failure.
    param($Entry, [int]$TimeoutSeconds = 30)
    if ("$($Entry.nsInode)" -notmatch '^pid:\[\d+\]$') { throw ("no namespace recorded for " + $Entry.name) }
    $r = Invoke-HordeWsl -Distro $Entry.distro -Argv @("sh", "-c", $script:HordeTmuxNsScan, "sh", $Entry.nsInode) -TimeoutSeconds $TimeoutSeconds
    $why = Get-HordeWslFailure $r
    if ($why) { throw $why }
    $lines = @(Get-HordeTmuxLines $r.out)
    $last = ""
    if ($lines.Count -gt 0) { $last = "$($lines[$lines.Count - 1])".Trim() }
    if ($r.code -ne 0 -or $last -notmatch '^scanned ([1-9]\d*)$') {
        throw ("the namespace scan did not finish (exit " + $r.code + ", last line '" + $last + "') - an unfinished scan is not an empty namespace")
    }
    return @($lines | Select-Object -First ($lines.Count - 1))
}

# THE PREFLIGHT, which starts nothing. unshare is checked first and by name: without it there is no
# containment, and a harness that ran uncontained would be the escape the review of PR 35 measured.
# Prints "<distro>|<uid>|tmux <version>".
$script:HordeTmuxPreflight = 'command -v unshare >/dev/null 2>&1 || { echo "unshare (util-linux) is not installed in the distro" >&2; exit 3; }; command -v tmux >/dev/null 2>&1 || { echo "tmux is not installed in the distro" >&2; exit 4; }; printf "%s|%s|" "$WSL_DISTRO_NAME" "$(id -u)"; tmux -V'

function Start-HordeIsolatedTmux {
    # Start a tmux server that is ours alone and register it. Returns the instance. THROWS, loudly and
    # with the reason, when WSL, the distro, tmux or unshare is missing: an absent host is a failure,
    # never a skip.
    param([string]$Distro = "", [int]$TimeoutSeconds = 30)
    # PREFLIGHT, no server started: which distro, is unshare there (containment needs it), is tmux there,
    # and which user (the socket lives in tmux-<uid>, so the expected path needs it).
    $who = Invoke-HordeWsl -Distro $Distro -Argv @("sh", "-c", $script:HordeTmuxPreflight) -TimeoutSeconds $TimeoutSeconds
    $why = Get-HordeWslFailure $who
    if ($why) { throw ("tmux host unavailable: " + $why) }
    if ($who.code -ne 0 -or "$($who.out)".Trim() -notmatch '^([A-Za-z0-9._-]+)\|(\d+)\|tmux (\S+)$') {
        throw ("tmux host unavailable: the preflight in WSL answered exit " + $who.code + ": " + ("$($who.out) $($who.err)".Trim() -replace '\s+', ' '))
    }
    $resolved = $Matches[1]; $uid = $Matches[2]; $version = $Matches[3]
    if ($Distro -and $resolved -ne $Distro) { throw ("tmux host unavailable: asked for distro '" + $Distro + "' and reached '" + $resolved + "'") }

    $g = [guid]::NewGuid().ToString("N")
    $e = [pscustomobject]@{ distro = $resolved; uid = $uid; version = $version; guid = $g; name = ("horde-iso-" + $g); dir = ("/tmp/horde-iso-" + $g)
                            socket = ("/tmp/horde-iso-" + $g + "/tmux-" + $uid + "/horde-iso-" + $g); serverPid = ""; startTime = ""; nsInode = ""; owner = $null }
    # CREATED ONLY IF NEW: plain mkdir fails on an existing path, so a folder we did not make is never
    # adopted (the first host's store lesson). Mode 700, as tmux wants its socket directory.
    $mk = Invoke-HordeWsl -Distro $resolved -Argv @("mkdir", "-m", "700", "--", $e.dir) -TimeoutSeconds $TimeoutSeconds
    $why = Get-HordeWslFailure $mk
    if ($why -or $mk.code -ne 0) { throw ("could not create the private socket directory " + $e.dir + ": " + $why + " " + $mk.err) }

    $token = "horde-tmux-iso:" + $g
    $script:HordeTmuxStarted[$token] = $e
    $inst = [pscustomobject]@{ token = $token; distro = $resolved; socket = $e.socket; name = $e.name; dir = $e.dir }
    # FROM HERE ON, ANY FAILURE UNDOES EVERYTHING (the first host's Start lesson): teardown is
    # safe on a half-started instance, because it kills only by our socket and removes only our paths.
    try {
        $own = Start-HordeWslOwner -Distro $resolved -Argv (Get-HordeTmuxOwnerArgv -Entry $e) -TimeoutSeconds $TimeoutSeconds
        $e.owner = $own
        if ($own.nsInode) { $e.nsInode = $own.nsInode }
        if (-not $own.ready -or -not $e.nsInode) { throw ("the contained server did not start: " + $own.failure) }
        $id = Invoke-HordeTmux -Instance $inst -Command @("display-message", "-p", "#{socket_path}|#{pid}|#{start_time}")
        $parts = @("$($id.out)".Trim() -split '\|')
        if ($id.code -ne 0 -or $parts.Count -ne 3 -or $parts[0] -cne $e.socket -or $parts[1] -notmatch '^\d+$' -or $parts[2] -notmatch '^\d+$') {
            throw ("the new server did not identify itself on our socket: '" + "$($id.out)".Trim() + "' " + $id.err)
        }
        # #{pid} is the server's pid INSIDE the namespace, which is what it reports each time it is asked.
        $e.serverPid = $parts[1]; $e.startTime = $parts[2]
        $bad = Test-HordeTmuxContained -Entry $e -Lines (Get-HordeTmuxNsProcs -Entry $e -TimeoutSeconds $TimeoutSeconds)
        if ($bad) { throw $bad }
        return $inst
    } catch {
        $msg = "$($_.Exception.Message)"
        [void](Stop-HordeIsolatedTmux -Instance $inst)
        throw ("could not start an isolated tmux server: " + $msg)
    }
}

function Assert-HordeTmuxIsolated {
    # THE CONTROL (L-009). Nothing destructive runs until this has passed. Isolation is MEASURED: the
    # server answering on our socket must be the one Start recorded, it must be running inside our own
    # pid namespace, and it must hold exactly one session and one pane. Throws on any doubt; returns the
    # pane count when satisfied.
    param($Instance)
    $e = Get-HordeTmuxEntry $Instance
    if (-not $e) { throw "not isolated: not a tmux server this process started" }
    $id = Invoke-HordeTmux -Instance $Instance -Command @("display-message", "-p", "#{socket_path}|#{pid}|#{start_time}")
    if ($id.code -ne 0) { throw ("not isolated: the server did not answer: " + $id.err) }
    $bad = Test-HordeTmuxIdentity -Entry $e -Line $id.out
    if ($bad) { throw ("not isolated: " + $bad) }
    $bad = Test-HordeTmuxContained -Entry $e -Lines (Get-HordeTmuxNsProcs -Entry $e)
    if ($bad) { throw ("not isolated: " + $bad) }
    $s = Invoke-HordeTmux -Instance $Instance -Command @("list-sessions", "-F", "#{session_id}|#{session_name}")
    $p = Invoke-HordeTmux -Instance $Instance -Command @("list-panes", "-a", "-F", "#{pane_id}")
    if ($s.code -ne 0 -or $p.code -ne 0) { throw ("not isolated: the server did not list itself: " + $s.err + " " + $p.err) }
    $bad = Test-HordeTmuxIsolation -Sessions (Get-HordeTmuxLines $s.out) -Panes (Get-HordeTmuxLines $p.out)
    if ($bad) { throw ("not isolated: " + $bad) }
    return @(Get-HordeTmuxLines $p.out).Count
}

function Test-HordeTmuxPaneId { param([string]$Pane) return ($Pane -match '^%\d+$') }

function New-HordeTmuxPane {
    # Spawn a pane that runs Command (an argv, run without a shell) in the isolated server. Returns
    # its pane id, %N. A new WINDOW, not a split: splits run out of room after a few panes.
    param($Instance, [string[]]$Command, [string]$Cwd = "/tmp")
    $r = Invoke-HordeTmux -Instance $Instance -Command (@("new-window", "-d", "-P", "-F", "#{pane_id}", "-t", ($script:HordeTmuxSession + ":"), "-c", $Cwd, "--") + $Command)
    $pane = "$($r.out)".Trim()
    if ($r.code -ne 0 -or -not (Test-HordeTmuxPaneId $pane)) { throw ("spawning a pane failed: exit " + $r.code + " '" + $pane + "' " + $r.err) }
    return $pane
}

function Get-HordeTmuxPaneText {
    # The text on a pane's screen, wrapped lines joined (-J).
    param($Instance, [string]$Pane)
    if (-not (Test-HordeTmuxPaneId $Pane)) { throw ("not a pane id: '" + $Pane + "'") }
    $r = Invoke-HordeTmux -Instance $Instance -Command @("capture-pane", "-p", "-J", "-t", $Pane)
    if ($r.code -ne 0) { throw ("reading pane " + $Pane + " failed: " + $r.err) }
    return $r.out
}

function Send-HordeTmuxText {
    # Type Text into a pane literally (-l, and -- so text starting with "-" is not read as a flag),
    # then press Enter unless -NoEnter.
    param($Instance, [string]$Pane, [string]$Text, [switch]$NoEnter)
    if (-not (Test-HordeTmuxPaneId $Pane)) { throw ("not a pane id: '" + $Pane + "'") }
    $r = Invoke-HordeTmux -Instance $Instance -Command @("send-keys", "-t", $Pane, "-l", "--", $Text)
    if ($r.code -ne 0) { throw ("sending text to " + $Pane + " failed: " + $r.err) }
    if (-not $NoEnter) {
        $r = Invoke-HordeTmux -Instance $Instance -Command @("send-keys", "-t", $Pane, "Enter")
        if ($r.code -ne 0) { throw ("sending Enter to " + $Pane + " failed: " + $r.err) }
    }
}

# EVERY SCRIPT BELOW HAS ITS CARRIAGE RETURNS STRIPPED. A checkout with core.autocrlf on gives this
# file CRLF line endings, a here-string keeps them, and sh reads "sock=$1<CR>" as a different value
# (CONTRIBUTING 12's autocrlf trap, crossing into Linux).

# Remove our socket file and our two directories, and nothing else. The socket goes only if it is a
# socket (-S) at exactly our path; the directories go by rmdir, which refuses a directory that holds
# anything - a stranger's socket included. Prints what is left.
$script:HordeTmuxCleanup = @'
sock=$1; sub=$2; dir=$3
[ -S "$sock" ] && rm -f -- "$sock"
[ -d "$sub" ] && rmdir -- "$sub" 2>/dev/null
[ -d "$dir" ] && rmdir -- "$dir" 2>/dev/null
[ -e "$sock" ] && echo "socket-left"
[ -e "$dir" ] && echo "dir-left"
exit 0
'@ -replace "`r", ""

function Stop-HordeTmuxOwner {
    # Let the owner go - close its stdin, which is pid 1's crash exit - and wait for its wsl.exe to exit,
    # up to Seconds. Returns $true when it has exited or there is none. Its handle is released either
    # way; the process itself is never killed from here, because the verdict is measured in the
    # namespace, not inferred from wsl.exe.
    param($Entry, [int]$Seconds = 10)
    $o = $Entry.owner
    if (-not $o -or -not $o.proc) { return $true }
    try { $o.proc.StandardInput.Close() } catch { }
    $done = $o.proc.WaitForExit($Seconds * 1000)
    $o.proc.Dispose()
    $Entry.owner = $null
    return $done
}

function Stop-HordeIsolatedTmux {
    # TEAR THE SERVER DOWN AND PROVE IT WENT: the server, everything that ran in it, its socket and its
    # directory. Returns { stopped; survived; orphansSurvived; socketRemoved; dirRemoved;
    # refused; reason } so a caller asserts rather than hopes (L-015).
    #
    # IT KILLS ONLY ITS OWN SERVER. The instance must carry a token this process issued (L-028), and
    # before `kill-server` the server answering on our socket must prove it is the one Start recorded -
    # socket path, pid and start time. A different server there is refused, not killed. And
    # `kill-server` is only ever sent through Get-HordeTmuxArgv, so it names our socket, in our
    # directory, and nothing else.
    param($Instance, [int]$TimeoutSeconds = 30)
    $verdict = { param($stopped, $survived, $still, $sockOk, $dirOk, $refused, $reason)
        if ($refused) { Write-Host ("  isolated tmux teardown REFUSED (" + $reason + ") - nothing was killed") -ForegroundColor Red }
        [pscustomobject]@{ stopped = $stopped; survived = $survived; orphansSurvived = @($still)
                           socketRemoved = $sockOk; dirRemoved = $dirOk; refused = $refused; reason = $reason } }
    if (-not $Instance) { return (& $verdict $false $false @() $false $false $true "no instance was passed - nothing was stopped and nothing was verified") }
    $e = Get-HordeTmuxEntry $Instance
    if (-not $e) { return (& $verdict $false $false @() $false $false $true "not a tmux server this process started (no registered token) - refusing to kill anything") }

    try {
        # WHO IS ON OUR SOCKET? Our server, nobody, or - refused - someone else.
        if ($e.serverPid) {
            $id = Invoke-HordeTmux -Instance $Instance -Command @("display-message", "-p", "#{socket_path}|#{pid}|#{start_time}") -TimeoutSeconds $TimeoutSeconds
            if ($id.code -eq 0) {
                $bad = Test-HordeTmuxIdentity -Entry $e -Line $id.out
                if ($bad) { return (& $verdict $false $false @() $false $false $true ($bad + " - refusing to kill it")) }
                [void](Invoke-HordeTmux -Instance $Instance -Command @("kill-server") -TimeoutSeconds $TimeoutSeconds)
            } elseif (-not (Test-HordeTmuxNoServer $id)) {
                return (& $verdict $false $false @() $false $false $true ("the server on our socket did not answer and did not say it was gone (exit " + $id.code + ": " + "$($id.err)".Trim() + ") - refusing to act on it"))
            }
        } elseif ($e.nsInode) {
            # Start failed after the owner came up but before the server identified itself. Anything on
            # our socket can only be the server our own owner made, because the directory is new and
            # ours, so it is killed.
            [void](Invoke-HordeTmux -Instance $Instance -Command @("kill-server") -TimeoutSeconds $TimeoutSeconds)
        }
        # THE OWNER: when the server exits, pid 1 exits and the owner's wsl.exe with it.
        $ownerGone = Stop-HordeTmuxOwner -Entry $e -Seconds 10
        # GONE MEANS THE SOCKET SAYS SO, measured, not "kill-server exited 0".
        $gone = $false
        $deadline = (Get-Date).AddSeconds(10)
        do {
            $ls = Invoke-HordeTmux -Instance $Instance -Command @("list-sessions") -TimeoutSeconds $TimeoutSeconds
            if (Test-HordeTmuxNoServer $ls) { $gone = $true; break }
            Start-Sleep -Milliseconds 200
        } while ((Get-Date) -lt $deadline)
        # EMPTY MEANS NO PROCESS IS LEFT IN OUR NAMESPACE, measured from outside it. Read at once: once
        # empty, the kernel may give the same inode to a later namespace (measured: two runs in a row
        # were both pid:[4026532227]), which would read as not empty - the safe error.
        $inNs = @()
        if ($e.nsInode) { $inNs = @(Get-HordeTmuxNsProcs -Entry $e -TimeoutSeconds $TimeoutSeconds) }
        # NO NAMESPACE TO SCAN - the owner timed out before it reported one - leaves only the owner's
        # exit as evidence: wsl.exe exits when unshare does, and unshare when pid 1 does, which takes
        # everything in the namespace with it. An owner that has not exited proves nothing, so nothing
        # is claimed (the review of PR 35, round 3: this path used to read as stopped).
        $unmeasured = (-not $e.nsInode) -and (-not $ownerGone)
        $survived = (-not $gone) -or ($inNs.Count -gt 0) -or $unmeasured

        # WHAT RAN INSIDE IT is not hunted down and killed one pid at a time: the namespace already took
        # it, and the scan above is the proof. Whatever is still listed there is reported, not killed.
        $still = @($inNs)

        # OUR SOCKET AND DIRECTORY, only once the server is gone - a survivor keeps its socket, so it
        # can still be reached and cleaned up by hand (the first host's L-023 rule).
        $sockOk = $false; $dirOk = $false
        if (-not $survived) {
            $c = Invoke-HordeWsl -Distro $e.distro -Argv @("sh", "-c", $script:HordeTmuxCleanup, "sh", $e.socket, ($e.dir + "/tmux-" + $e.uid), $e.dir) -TimeoutSeconds $TimeoutSeconds
            $why = Get-HordeWslFailure $c
            if ($why) { throw $why }
            $sockOk = ($c.code -eq 0 -and "$($c.out)" -notmatch 'socket-left')
            $dirOk = ($c.code -eq 0 -and "$($c.out)" -notmatch 'dir-left')
        }
    } catch {
        # WSL ITSELF FAILED MID-TEARDOWN. Nothing is known, so nothing is claimed, and the token is kept
        # so the teardown can be run again once WSL answers.
        Write-Host ("  ISOLATED TMUX SERVER NOT VERIFIED: " + $_.Exception.Message + ". Socket " + $e.socket + " in distro " + $e.distro + ".") -ForegroundColor Red
        return (& $verdict $false $false @() $false $false $false ("WSL failed during teardown: " + $_.Exception.Message))
    }

    # A token is used once (as in the first host's harness): a stale object cannot be torn down twice.
    $script:HordeTmuxStarted.Remove("$($Instance.token)")
    if ($survived -or $still.Count -gt 0) {
        Write-Host ("  ISOLATED TMUX SERVER LEAKED: socket " + $e.socket + " in distro " + $e.distro + ", server survived=" + $survived +
                    ", processes still in its namespace: " + ($still -join ", ") + ". Kill them by hand.") -ForegroundColor Red
    }
    $reason = ""
    if ($unmeasured) { $reason = "the owner never reported its namespace and its wsl.exe did not exit, so nothing could be measured" }
    elseif ($survived) { $reason = "the server still answers, or its namespace still holds processes" }
    elseif ($still.Count -gt 0) { $reason = "processes are still in its namespace" }
    return (& $verdict (-not $survived -and $still.Count -eq 0) $survived $still $sockOk $dirOk $false $reason)
}
