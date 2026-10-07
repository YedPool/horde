# transports/ssh/Transport.ps1 - the ssh transport: a node dials its hub with the System32 ssh.exe.
#
# Remote plan step R5; remote design 1.2, 2.4 and 8. WHAT IS HERE is the node's half: Open starts
# ssh.exe with argv built from data (Argv.ps1), and the link's bytes are its stdin and stdout. WHAT IS
# NOT is the hub's half - sshd with a forced command, running while `horde listen` runs (R16), with the
# enrolled per-device keys (R17) - so accept is no, and Listen refuses naming those steps. Until a
# live sshd has shown them, auth.peer, encrypt, dial.out and keepalive are unverified in
# capabilities.json: argv asks for each, and nothing here has demonstrated one (hosts-research 5.1).
#
# MEASURED 2026-10-02, OpenSSH_for_Windows 9.5p2 (System32), each one shaping code below:
#   - ssh.exe IGNORES USERPROFILE: ~ resolves to the real profile whatever the environment says, so a
#     test cannot plant a hostile ~/.ssh/config without touching the user's own. Independence from the
#     user's files is therefore shown with ssh.exe -G (transports/ssh/test/test-ssh.ps1).
#   - with no -i file, ssh.exe silently offers the default ~/.ssh/id_* keys, even with -F none and
#     IdentitiesOnly=yes. Open refuses to start unless Horde's key file exists.
#   - a closed port is exit 255 with "banner exchange: Connection to UNKNOWN port -1: Connection
#     refused" on stderr and nothing on stdout. ssh(1): it "exits with the exit status of the remote
#     command or with 255 if an error occurred", so 255 is a transport error, never a protocol verdict.
#
# STREAM HYGIENE (hosts-research C9; CONTRIBUTING 12): stderr is read on its own and never enters the
# frame reader; its first line becomes the reason for exit 255. No 2>&1 anywhere. STDERR IS BOUNDED
# (review of PR #68, F3: 150 MiB of stderr grew this process by 266 MiB, and an escape sequence reached
# the reason): it is drained whenever the link reads or waits, only its first 4096 bytes are kept and
# the rest is counted and dropped, and the reason is at most 200 printable characters.
#
# NO ORPHAN (review of PR #68, F7 and round 3; the founder's rule that orphans are prevented
# structurally). ssh.exe runs in a job object that kills it when its last handle closes (Native.ps1),
# and the only handle is held by the link's channel. So when the channel closes, when a caller drops
# the link, or when the Horde process dies, the OS ends ssh.exe; no PowerShell has to run. Open's try
# begins before the start, so any failure up to the handoff closes the job too, and also stops the
# process by pid and start time through the handle held since the start. test-ssh.ps1 makes each step
# throw, and kills a whole driver process mid-link, and finds no ssh.exe of ours alive.
#
# KNOWN AND LEFT (review of PR #68, F6, LOW): Test-HordeSshFiles reads Horde's ssh_config as decoded
# text, while ssh reads bytes, and reads it before the spawn, so a writer with access to <HordeHome>
# could change it in between. The review's probes found no bypass - a UTF-16 file with a directive
# made ssh fail closed, and a CR-only or BOM-prefixed file was either refused here or read by ssh as a
# comment - and a byte-level ASCII check, or passing the config's bytes to ssh rather than its path,
# would close the gap. Left as it is by the coordinator's decision of 2026-10-02.
#
# ONE PROGRAM START, AT ONE CALL SITE: Start-HordeSshProcess, called once by Open, starting the System32
# ssh.exe named in its own one setup expression.
# tools/ExecScan.ps1 has no policy for transports/ yet (Horde #53); until it has, test-ssh.ps1 holds
# this property by parsing this folder.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced.

. (Join-Path $PSScriptRoot "Argv.ps1")
. (Join-Path $PSScriptRoot "Native.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\Home.ps1")

$script:HordeSshFolder = $PSScriptRoot
$script:HordeSshBufferBytes = 65536
$script:HordeSshExitTransportError = 255
$script:HordeSshProbeTimeoutMs = 5000
$script:HordeSshBannerPrefixes = @("SSH-2.0-", "SSH-1.99-")
$script:HordeSshStderrKeepBytes = 4096
$script:HordeSshReasonChars = 200
$script:HordeSshHubSide = "the ssh transport's accepting end is the hub's sshd with a forced command, run by horde listen (remote plan R16) for keys enrollment writes (R17); neither is built in step R5"

function Resolve-HordeSshExe {
    # The System32 ssh.exe, by its path - never through PATH, where Git's copy (remote design M-03) or
    # anything else can come first. { ok; path; reason }.
    # Named by .NET, with no command resolved and no environment variable read (review of PR #68,
    # round 3): the same expression Start-HordeSshProcess starts.
    $p = [System.IO.Path]::Combine([System.Environment]::SystemDirectory, "OpenSSH", "ssh.exe")
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        return [pscustomobject]@{ ok = $false; path = ""; reason = ("no ssh.exe at " + $p + ": the OpenSSH client in System32 is the only one this transport runs") }
    }
    return [pscustomobject]@{ ok = $true; path = $p; reason = "" }
}

function Test-HordeSshFiles {
    # Are Horde's key, known_hosts and config in place, and is the config free of directives?
    # { ok; reason }. Each refusal says why it matters.
    param([Parameter(Mandatory = $true)]$Paths)
    if (-not (Test-Path -LiteralPath $Paths.identity -PathType Leaf)) {
        return [pscustomobject]@{ ok = $false; reason = ("Horde's key " + $Paths.identity + " does not exist; enrollment (remote plan R17) writes it, and without it ssh.exe would offer the user's own ~/.ssh keys") }
    }
    if (-not (Test-Path -LiteralPath $Paths.knownHosts -PathType Leaf)) {
        return [pscustomobject]@{ ok = $false; reason = ("Horde's known_hosts " + $Paths.knownHosts + " does not exist; the hub's host key must be pinned before a link opens") }
    }
    if (-not (Test-Path -LiteralPath $Paths.config -PathType Leaf)) {
        return [pscustomobject]@{ ok = $false; reason = ("Horde's ssh_config " + $Paths.config + " does not exist; it is the -F file that keeps the user's own config out") }
    }
    $n = 0
    foreach ($line in ([System.IO.File]::ReadAllText($Paths.config) -split "`n")) {
        $n++
        $t = $line.Trim()
        if ($t -ne "" -and -not $t.StartsWith("#")) {
            return [pscustomobject]@{ ok = $false; reason = ("Horde's ssh_config " + $Paths.config + " holds a directive on line " + $n + "; it must hold none, because Horde's argv is the whole configuration") }
        }
    }
    return [pscustomobject]@{ ok = $true; reason = "" }
}

function Start-HordeSshProcess {
    # THE ONE PLACE this transport starts a program, and the program is fixed here: the System32 ssh.exe,
    # named in the one expression that sets the start up, never a path a caller passes or a variable
    # anyone can reassign (review of PR #68, round 2, F4: a $exe or $psi.FileName reassigned before the
    # start ran another program). stdin, stdout and stderr are redirected; no window, no shell. The
    # caller holds the returned process, and only it may stop it (CONTRIBUTING 9).
    # -Job is the kill-on-close job the process goes into on the next statement (Native.ps1), so no
    # caller ever holds an ssh.exe outside one; if Windows refuses the assignment, the process is stopped
    # through its handle before the error goes on (review of PR #68, round 3: a throw after the start
    # returned, before the caller had assigned it, left ssh.exe running).
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Arguments, [Parameter(Mandatory = $true)][HordeSshJob]$Job)
    $psi = [System.Diagnostics.ProcessStartInfo]::new([System.IO.Path]::Combine([System.Environment]::SystemDirectory, "OpenSSH", "ssh.exe"), $Arguments)
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $started = [System.Diagnostics.Process]::Start($psi)
    try { [HordeSshNative]::Assign($Job, $started.Handle) }
    catch {
        try { $started.Kill() } catch { }
        throw
    }
    return $started
}

function Update-HordeSshStderr {
    # Move whatever stderr has ready into the kept bytes, up to the cap, and count the rest as dropped.
    # Never waits: a read is always pending, and each one that has finished is taken and replaced.
    param($State)
    while (-not $State.errEof) {
        if ($null -eq $State.errTask) { $State.errTask = $State.err.ReadAsync($State.errChunk, 0, $State.errChunk.Length) }
        if (-not $State.errTask.IsCompleted) { return }
        $n = 0
        try { $n = $State.errTask.Result } catch { $n = 0 }
        $State.errTask = $null
        if ($n -le 0) { $State.errEof = $true; return }
        $take = [Math]::Min($script:HordeSshStderrKeepBytes - $State.errKept.Count, $n)
        for ($k = 0; $k -lt $take; $k++) { $State.errKept.Add($State.errChunk[$k]) }
        $State.errDropped += ($n - $take)
    }
}

function Wait-HordeSshStderrOrExit {
    # Drain stderr until it ends and the process has exited, or -Ms pass. A process blocked writing a
    # flood of stderr cannot exit until it is drained, so waiting for the exit alone could wait forever.
    param($State, [int]$Ms)
    $deadline = [datetime]::UtcNow.AddMilliseconds($Ms)
    while ([datetime]::UtcNow -lt $deadline) {
        Update-HordeSshStderr -State $State
        if ($State.errEof -and $State.process.HasExited) { return $true }
        if ($null -ne $State.errTask) { $null = $State.errTask.Wait(100) } else { $null = $State.process.WaitForExit(100) }
    }
    Update-HordeSshStderr -State $State
    return $State.process.HasExited
}

function Get-HordeSshFirstLine {
    # The first non-blank line of the stderr kept so far, as at most 200 printable ASCII characters:
    # anything else - an escape sequence, a bell - becomes "?", so stderr never writes to a terminal.
    param($State)
    $text = [System.Text.Encoding]::ASCII.GetString($State.errKept.ToArray())
    foreach ($l in ($text -split "`r?`n")) {
        $clean = ($l -replace '[^\x20-\x7E]', '?').Trim()
        if ($clean -eq "") { continue }
        # A line of nothing but punctuation is a banner's border, not a reason: against a live Windows
        # sshd with a changed host key, ssh.exe's first line is a row of '@' and the reason ("REMOTE
        # HOST IDENTIFICATION HAS CHANGED") is the next (measured 2026-10-05, remote plan R16).
        if ($clean -notmatch '[A-Za-z0-9]') { continue }
        if ($clean.Length -gt $script:HordeSshReasonChars) { $clean = $clean.Substring(0, $script:HordeSshReasonChars) + "..." }
        return $clean
    }
    return "(nothing on stderr)"
}

function New-HordeSshChannel {
    # A byte channel over a running process's stdin and stdout (the port's channel contract, Port.ps1).
    # One read is kept pending. At the end of stdout the process's exit decides what the end was: 255
    # is a transport error with stderr's first line as the reason; anything else is the far side
    # closing. Writes go through an unbuffered stream on the stdin handle: the redirected writer's own
    # stream buffers 4096 bytes, and a small frame could sit in it unsent.
    # -Job is the kill-on-close job ssh.exe runs in (Native.ps1); the channel holds its only handle, so
    # closing the channel - or losing it with this process - ends ssh.exe. A stand-in child has none.
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process, $Job = $null)
    $in = New-Object System.IO.FileStream($Process.StandardInput.BaseStream.SafeFileHandle, [System.IO.FileAccess]::Write, 1, $false)
    $state = @{
        process = $Process; job = $Job; out = $Process.StandardOutput.BaseStream; in = $in
        buf = (New-Object byte[] $script:HordeSshBufferBytes); pending = $null
        err = $Process.StandardError.BaseStream; errChunk = (New-Object byte[] $script:HordeSshBufferBytes); errTask = $null; errEof = $false
        errKept = (New-Object System.Collections.Generic.List[byte]); errDropped = [long]0
    }
    return [pscustomobject]@{
        state = $state
        read = {
            param($Channel, [int]$WaitMs)
            $st = $Channel.state
            try {
                if ($null -eq $st.pending) { $st.pending = $st.out.ReadAsync($st.buf, 0, $st.buf.Length) }
                # Wait on stdout AND stderr: whatever arrives on stderr is drained at once, so a flood of
                # it can neither stall the process writing it nor pile up here.
                $deadline = [datetime]::UtcNow.AddMilliseconds([Math]::Max(0, $WaitMs))
                while (-not $st.pending.IsCompleted) {
                    Update-HordeSshStderr -State $st
                    $left = [int][Math]::Ceiling(($deadline - [datetime]::UtcNow).TotalMilliseconds)
                    if ($left -le 0) { return [pscustomobject]@{ kind = "none"; bytes = $null; reason = "" } }
                    $waitOn = @($st.pending)
                    if ($null -ne $st.errTask) { $waitOn += $st.errTask }
                    $null = [System.Threading.Tasks.Task]::WaitAny([System.Threading.Tasks.Task[]]$waitOn, $left)
                }
                $n = $st.pending.Result
            } catch {
                $st.pending = $null
                $e = $_.Exception
                while ($null -ne $e.InnerException) { $e = $e.InnerException }
                return [pscustomobject]@{ kind = "error"; bytes = $null; reason = $e.Message }
            }
            $st.pending = $null
            if ($n -gt 0) {
                $copy = New-Object byte[] $n
                [Array]::Copy($st.buf, $copy, $n)
                return [pscustomobject]@{ kind = "data"; bytes = $copy; reason = "" }
            }
            if ((Wait-HordeSshStderrOrExit -State $st -Ms 5000) -and $st.process.ExitCode -eq $script:HordeSshExitTransportError) {
                return [pscustomobject]@{ kind = "error"; bytes = $null; reason = ("ssh exit 255, a transport error: " + (Get-HordeSshFirstLine -State $st)) }
            }
            return [pscustomobject]@{ kind = "eof"; bytes = $null; reason = "" }
        }
        write = {
            param($Channel, [byte[]]$Bytes)
            # Asynchronous, so the port can bound the wait on a far end that stops reading.
            return $Channel.state.in.WriteAsync($Bytes, 0, $Bytes.Length)
        }
        close = {
            param($Channel)
            $st = $Channel.state
            # Closing stdin ends the session from this side; a process still running after that is
            # this channel's own child, held by its handle, and is stopped through it.
            try { $st.in.Dispose() } catch { }
            try { if (-not $st.process.WaitForExit(2000)) { $st.process.Kill(); $null = $st.process.WaitForExit(5000) } } catch { }
            if ($null -ne $st.job) { try { $st.job.Dispose() } catch { } }
        }
    }
}

function Stop-HordeSshUnowned {
    # Stop a process this adapter started and is not handing on (header, NO ORPHAN): only when its pid
    # still names a process with the start time recorded at the start, and through the handle held
    # since then, so a pid reused by another program is never the one stopped.
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process, [Parameter(Mandatory = $true)][datetime]$StartedAt)
    try {
        if ($Process.HasExited) { return }
        $now = [System.Diagnostics.Process]::GetProcessById($Process.Id)
        if ($now.StartTime -ne $StartedAt) { return }
        $Process.Kill()
        $null = $Process.WaitForExit(5000)
    } catch { }
}

function New-HordeSshResult {
    param([bool]$Ok, $Channel = $null, $Peer = $null, [string]$Reason = "")
    return [pscustomobject]@{ ok = $Ok; channel = $Channel; peer = $Peer; listener = $null; reason = $Reason }
}

function Test-HordeSshBanner {
    # Probe: TCP connect, then read the server's identification line; no key exchange, no session.
    # Returns a tristate answer. Refused is known unreachable; a line that is not an SSH banner is
    # unknown - something answers, and it is not an ssh server.
    param([string]$Endpoint)
    $e = ConvertFrom-HordeSshEndpoint -Endpoint $Endpoint
    if (-not $e.ok) { return (New-HordeUnknown -Reason $e.reason) }
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        try {
            $c = $client.ConnectAsync($e.host, $e.port)
            if (-not $c.Wait($script:HordeSshProbeTimeoutMs)) { return (New-HordeUnknown -Reason ("no answer from " + $e.host + ":" + $e.port + " within " + $script:HordeSshProbeTimeoutMs + " ms")) }
        } catch {
            $x = $_.Exception
            while ($null -ne $x.InnerException) { $x = $x.InnerException }
            if ($x -is [System.Net.Sockets.SocketException] -and $x.SocketErrorCode -eq [System.Net.Sockets.SocketError]::ConnectionRefused) {
                return (New-HordeKnown -Value $false)
            }
            return (New-HordeUnknown -Reason ("connecting to " + $e.host + ":" + $e.port + ": " + $x.Message))
        }
        $stream = $client.GetStream()
        $buf = New-Object byte[] 255
        $got = 0
        $deadline = [datetime]::UtcNow.AddMilliseconds($script:HordeSshProbeTimeoutMs)
        while ($got -lt $buf.Length -and [datetime]::UtcNow -lt $deadline) {
            $r = $stream.ReadAsync($buf, $got, $buf.Length - $got)
            if (-not $r.Wait([Math]::Max(1, [int]($deadline - [datetime]::UtcNow).TotalMilliseconds))) { break }
            if ($r.Result -eq 0) { break }
            $got += $r.Result
            if ([Array]::IndexOf($buf, [byte]10, 0, $got) -ge 0) { break }
        }
        $line = ([System.Text.Encoding]::ASCII.GetString($buf, 0, $got) -split "`n")[0].TrimEnd()
        foreach ($pfx in $script:HordeSshBannerPrefixes) {
            if ($line.StartsWith($pfx, [System.StringComparison]::Ordinal)) { return (New-HordeKnown -Value $true) }
        }
        $shown = ($line -replace '[^\x20-\x7E]', '?')
        if ($shown.Length -gt 40) { $shown = $shown.Substring(0, 40) }
        return (New-HordeUnknown -Reason ($e.host + ":" + $e.port + " answered, but not with an SSH banner ('" + $shown + "')"))
    } finally {
        $client.Close()
    }
}

$null = Register-HordeTransport -Folder $script:HordeSshFolder `
    -Open {
        param($Endpoint, [int]$TimeoutMs)
        $ep = ConvertFrom-HordeSshEndpoint -Endpoint $Endpoint
        if (-not $ep.ok) { return (New-HordeSshResult -Ok $false -Reason ("not an ssh endpoint: " + $ep.reason)) }
        $exe = Resolve-HordeSshExe
        if (-not $exe.ok) { return (New-HordeSshResult -Ok $false -Reason $exe.reason) }
        $paths = Get-HordeSshPaths -HordeHome (Get-HordeHome)
        foreach ($path in @($paths.config, $paths.identity, $paths.knownHosts)) {
            $why = Test-HordeSshSafePath -Path $path
            if ($why -ne "") { return (New-HordeSshResult -Ok $false -Reason $why) }
        }
        $ready = Test-HordeSshFiles -Paths $paths
        if (-not $ready.ok) { return (New-HordeSshResult -Ok $false -Reason $ready.reason) }
        # NO ORPHAN (header): the try begins before the start, the job exists before ssh.exe does, and the
        # start function puts the process in the job on its next statement. $handed is set only on the last line before the
        # return; until then the finally ends ssh.exe, by closing the job and by pid and start time.
        $proc = $null
        $job = $null
        $startedAt = $null
        $handed = $false
        try {
            $job = [HordeSshNative]::NewKillOnCloseJob()
            $proc = Start-HordeSshProcess -Arguments (Join-HordeSshCommandLine -Argv (Get-HordeSshArgv -Endpoint $ep -Paths $paths)) -Job $job
            $startedAt = $proc.StartTime
            $peer = [pscustomobject]@{
                verified = $false
                identity = ($script:HordeSshHostKeyAliasPrefix + $ep.hubId)
                how = "the hub's host key is pinned by StrictHostKeyChecking=yes against Horde's own known_hosts under this alias; no live sshd has demonstrated it yet (remote plan R16, R17)"
            }
            $result = New-HordeSshResult -Ok $true -Channel (New-HordeSshChannel -Process $proc -Job $job) -Peer $peer
            $handed = $true
            return $result
        } finally {
            if (-not $handed) {
                if ($null -ne $job) { $job.Dispose() }
                if ($null -ne $proc -and $null -ne $startedAt) { Stop-HordeSshUnowned -Process $proc -StartedAt $startedAt }
            }
        }
    } `
    -Probe {
        param($Endpoint)
        return (Test-HordeSshBanner -Endpoint $Endpoint)
    } `
    -Listen {
        param($Endpoint)
        return [pscustomobject]@{ ok = $false; listener = $null; reason = $script:HordeSshHubSide }
    } `
    -Accept {
        param($ListenerState, [int]$TimeoutMs)
        return (New-HordeSshResult -Ok $false -Reason $script:HordeSshHubSide)
    } `
    -Stop {
        param($ListenerState)
    }
