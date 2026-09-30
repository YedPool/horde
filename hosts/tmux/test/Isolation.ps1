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
# NOTHING IS KILLED BY A NUMBER ALONE (the first host's kill-safety history, L-020 and its
# review). The server is killed only by `kill-server` through its own socket, after the server that
# answers on that socket has proved it is the one Start recorded: same socket path, same pid, same
# start time. What outlived it is found by the one mark only our panes carry - TMUX=<our socket path>,
# in the process environment, which tmux sets for every pane's child - and each is re-checked for that
# mark in the same shell that kills it. Said plainly: between that check and the kill there is a gap
# of one command, not a held handle; Linux hands pids out in order and reuses one only after the pid
# space wraps, so a stranger taking that pid inside the gap is unlikely, not impossible. MEASURED: a pane child that ignores SIGHUP survived
# `kill-server` (`sh -c 'trap "" HUP; exec sleep 300'`), and tmux 3.4 left its socket file behind.
# Directories are removed with `rmdir`, which refuses a directory that is not empty, never `rm -r`.

if ($null -eq $script:HordeTmuxStarted) { $script:HordeTmuxStarted = @{} }
# The transport is replaceable so the fast suite can prove what the harness WOULD send without a WSL
# in the loop. $null means the real one. A test that sets it puts it back.
if (-not (Test-Path variable:script:HordeTmuxTransport)) { $script:HordeTmuxTransport = $null }

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
    param($Result)
    return [bool]($Result -and $Result.code -eq 1 -and ($Result.err -match 'no server running on|error connecting to'))
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

function Start-HordeIsolatedTmux {
    # Start a tmux server that is ours alone and register it. Returns the instance. THROWS, loudly and
    # with the reason, when WSL, the distro or tmux is missing: an absent host is a failure, never a skip.
    param([string]$Distro = "", [int]$TimeoutSeconds = 30)
    # PREFLIGHT, no server started: which distro, is tmux there, and which user (the socket lives in
    # tmux-<uid>, so the expected path needs it).
    $who = Invoke-HordeWsl -Distro $Distro -Argv @("sh", "-c", 'printf "%s|%s|" "$WSL_DISTRO_NAME" "$(id -u)"; tmux -V') -TimeoutSeconds $TimeoutSeconds
    $why = Get-HordeWslFailure $who
    if ($why) { throw ("tmux host unavailable: " + $why) }
    if ($who.code -ne 0 -or "$($who.out)".Trim() -notmatch '^([A-Za-z0-9._-]+)\|(\d+)\|tmux (\S+)$') {
        throw ("tmux host unavailable: the preflight in WSL answered exit " + $who.code + ": " + ("$($who.out) $($who.err)".Trim() -replace '\s+', ' '))
    }
    $resolved = $Matches[1]; $uid = $Matches[2]; $version = $Matches[3]
    if ($Distro -and $resolved -ne $Distro) { throw ("tmux host unavailable: asked for distro '" + $Distro + "' and reached '" + $resolved + "'") }

    $g = [guid]::NewGuid().ToString("N")
    $e = [pscustomobject]@{ distro = $resolved; uid = $uid; version = $version; guid = $g; name = ("horde-iso-" + $g); dir = ("/tmp/horde-iso-" + $g)
                            socket = ("/tmp/horde-iso-" + $g + "/tmux-" + $uid + "/horde-iso-" + $g); serverPid = ""; startTime = "" }
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
        $new = Invoke-HordeTmux -Instance $inst -Command @("new-session", "-d", "-s", $script:HordeTmuxSession, "-x", "160", "-y", "48", "-c", "/tmp", "--", "sh")
        if ($new.code -ne 0) { throw ("new-session failed: " + $new.err) }
        $id = Invoke-HordeTmux -Instance $inst -Command @("display-message", "-p", "#{socket_path}|#{pid}|#{start_time}")
        $parts = @("$($id.out)".Trim() -split '\|')
        if ($id.code -ne 0 -or $parts.Count -ne 3 -or $parts[0] -cne $e.socket -or $parts[1] -notmatch '^\d+$' -or $parts[2] -notmatch '^\d+$') {
            throw ("the new server did not identify itself on our socket: '" + "$($id.out)".Trim() + "' " + $id.err)
        }
        $e.serverPid = $parts[1]; $e.startTime = $parts[2]
        return $inst
    } catch {
        $msg = "$($_.Exception.Message)"
        [void](Stop-HordeIsolatedTmux -Instance $inst)
        throw ("could not start an isolated tmux server: " + $msg)
    }
}

function Assert-HordeTmuxIsolated {
    # THE CONTROL (L-009). Nothing destructive runs until this has passed. Isolation is MEASURED: the
    # server answering on our socket must be the one Start recorded, and it must hold exactly one
    # session and one pane. Throws on any doubt; returns the pane count when satisfied.
    param($Instance)
    $e = Get-HordeTmuxEntry $Instance
    if (-not $e) { throw "not isolated: not a tmux server this process started" }
    $id = Invoke-HordeTmux -Instance $Instance -Command @("display-message", "-p", "#{socket_path}|#{pid}|#{start_time}")
    if ($id.code -ne 0) { throw ("not isolated: the server did not answer: " + $id.err) }
    $bad = Test-HordeTmuxIdentity -Entry $e -Line $id.out
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

# Every process in the distro whose environment carries TMUX=<socket>, - the variable tmux gives each
# pane's child, so only what ran inside OUR server has it. $1 is the socket path, $2 "kill" or "list".
# Each is checked and killed in the same step; the script's own pid is skipped. The socket path is an
# argument, never spliced into the script text.
$script:HordeTmuxSweep = @'
sock=$1; me=$$
for f in /proc/[0-9]*/environ; do
  p=${f#/proc/}; p=${p%/environ}
  [ "$p" = "$me" ] && continue
  if grep -qaF -e "TMUX=$sock," "$f" 2>/dev/null; then
    if [ "$2" = kill ]; then kill -9 "$p" 2>/dev/null; fi
    echo "$p"
  fi
done
exit 0
'@

# Is the recorded server process still alive? Its argv is the first client's, which holds our unique
# socket name (measured: "tmux -L horde-iso-<guid> -f /dev/null new-session ..."), so a reused pid
# cannot pass. Prints "alive" or "gone". A shell `case`, not grep: a grep given the name as its
# pattern would carry that name in its own argv.
$script:HordeTmuxServerAlive = @'
c=$(tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null)
case "$c" in *"-L $2 "*) echo alive ;; *) echo gone ;; esac
'@

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
'@

function Stop-HordeIsolatedTmux {
    # TEAR THE SERVER DOWN AND PROVE IT WENT: the server, everything that ran in it, its socket and its
    # directory. Returns { stopped; survived; orphansKilled; orphansSurvived; socketRemoved; dirRemoved;
    # refused; reason } so a caller asserts rather than hopes (L-015).
    #
    # IT KILLS ONLY ITS OWN SERVER. The instance must carry a token this process issued (L-028), and
    # before `kill-server` the server answering on our socket must prove it is the one Start recorded -
    # socket path, pid and start time. A different server there is refused, not killed. And
    # `kill-server` is only ever sent through Get-HordeTmuxArgv, so it names our socket, in our
    # directory, and nothing else.
    param($Instance, [int]$TimeoutSeconds = 30)
    $verdict = { param($stopped, $survived, $killed, $still, $sockOk, $dirOk, $refused, $reason)
        if ($refused) { Write-Host ("  isolated tmux teardown REFUSED (" + $reason + ") - nothing was killed") -ForegroundColor Red }
        [pscustomobject]@{ stopped = $stopped; survived = $survived; orphansKilled = @($killed); orphansSurvived = @($still)
                           socketRemoved = $sockOk; dirRemoved = $dirOk; refused = $refused; reason = $reason } }
    if (-not $Instance) { return (& $verdict $false $false @() @() $false $false $true "no instance was passed - nothing was stopped and nothing was verified") }
    $e = Get-HordeTmuxEntry $Instance
    if (-not $e) { return (& $verdict $false $false @() @() $false $false $true "not a tmux server this process started (no registered token) - refusing to kill anything") }

    try {
        # WHO IS ON OUR SOCKET? Our server, nobody, or - refused - someone else.
        if ($e.serverPid) {
            $id = Invoke-HordeTmux -Instance $Instance -Command @("display-message", "-p", "#{socket_path}|#{pid}|#{start_time}") -TimeoutSeconds $TimeoutSeconds
            if ($id.code -eq 0) {
                $bad = Test-HordeTmuxIdentity -Entry $e -Line $id.out
                if ($bad) { return (& $verdict $false $false @() @() $false $false $true ($bad + " - refusing to kill it")) }
                [void](Invoke-HordeTmux -Instance $Instance -Command @("kill-server") -TimeoutSeconds $TimeoutSeconds)
            } elseif (-not (Test-HordeTmuxNoServer $id)) {
                return (& $verdict $false $false @() @() $false $false $true ("the server on our socket did not answer and did not say it was gone (exit " + $id.code + ": " + "$($id.err)".Trim() + ") - refusing to act on it"))
            }
        } else {
            # Start failed before the server identified itself. Anything on our socket can only be the
            # server our own new-session made, because the directory is new and ours, so it is killed.
            [void](Invoke-HordeTmux -Instance $Instance -Command @("kill-server") -TimeoutSeconds $TimeoutSeconds)
        }
        # GONE MEANS THE SOCKET SAYS SO, measured, not "kill-server exited 0".
        $gone = $false
        $deadline = (Get-Date).AddSeconds(10)
        do {
            $ls = Invoke-HordeTmux -Instance $Instance -Command @("list-sessions") -TimeoutSeconds $TimeoutSeconds
            if (Test-HordeTmuxNoServer $ls) { $gone = $true; break }
            Start-Sleep -Milliseconds 200
        } while ((Get-Date) -lt $deadline)
        $alive = $false
        if ($e.serverPid) {
            $pr = Invoke-HordeWsl -Distro $e.distro -Argv @("sh", "-c", $script:HordeTmuxServerAlive, "sh", $e.serverPid, $e.name) -TimeoutSeconds $TimeoutSeconds
            $why = Get-HordeWslFailure $pr
            if ($why) { throw $why }
            $alive = ("$($pr.out)".Trim() -ne "gone")
        }
        $survived = (-not $gone) -or $alive

        # WHAT RAN INSIDE IT, killed, then looked for again: whatever is still there would not die.
        $killed = @(); $still = @()
        $k = Invoke-HordeWsl -Distro $e.distro -Argv @("sh", "-c", $script:HordeTmuxSweep, "sh", $e.socket, "kill") -TimeoutSeconds $TimeoutSeconds
        $why = Get-HordeWslFailure $k
        if ($why) { throw $why }
        $killed = @(Get-HordeTmuxLines $k.out | ForEach-Object { $_.Trim() })
        if ($killed.Count -gt 0) { Start-Sleep -Milliseconds 300 }
        $l = Invoke-HordeWsl -Distro $e.distro -Argv @("sh", "-c", $script:HordeTmuxSweep, "sh", $e.socket, "list") -TimeoutSeconds $TimeoutSeconds
        $why = Get-HordeWslFailure $l
        if ($why) { throw $why }
        $still = @(Get-HordeTmuxLines $l.out | ForEach-Object { $_.Trim() })

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
        return (& $verdict $false $false @() @() $false $false $false ("WSL failed during teardown: " + $_.Exception.Message))
    }

    # A token is used once (as in the first host's harness): a stale object cannot be torn down twice.
    $script:HordeTmuxStarted.Remove("$($Instance.token)")
    if ($survived -or $still.Count -gt 0) {
        Write-Host ("  ISOLATED TMUX SERVER LEAKED: socket " + $e.socket + " in distro " + $e.distro + ", server survived=" + $survived +
                    ", processes that would not die: " + ($still -join ", ") + ". Kill them by hand.") -ForegroundColor Red
    }
    $reason = ""
    if ($survived) { $reason = "the server still answers, or its process is still alive" }
    elseif ($still.Count -gt 0) { $reason = "processes that ran inside it would not die" }
    return (& $verdict (-not $survived -and $still.Count -eq 0) $survived $killed $still $sockOk $dirOk $false $reason)
}
