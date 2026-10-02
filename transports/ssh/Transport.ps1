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
# ONE PROGRAM START, AT ONE CALL SITE: Start-HordeSshProcess, called by Open with the System32 path.
# tools/ExecScan.ps1 has no policy for transports/ yet (Horde #53); until it has, test-ssh.ps1 holds
# this property by parsing this folder.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced.

. (Join-Path $PSScriptRoot "Argv.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\Home.ps1")

$script:HordeSshFolder = $PSScriptRoot
$script:HordeSshExeRelative = "System32\OpenSSH\ssh.exe"
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
    $p = Join-Path "$env:SystemRoot" $script:HordeSshExeRelative
    if ("$env:SystemRoot" -eq "" -or -not (Test-Path -LiteralPath $p -PathType Leaf)) {
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
    # THE ONE PLACE this transport starts a program. stdin, stdout and stderr are redirected; no window,
    # no shell. The caller holds the returned process, and only it may stop it (CONTRIBUTING 9).
    param([Parameter(Mandatory = $true)][string]$FilePath, [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Arguments)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    return [System.Diagnostics.Process]::Start($psi)
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
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process)
    $in = New-Object System.IO.FileStream($Process.StandardInput.BaseStream.SafeFileHandle, [System.IO.FileAccess]::Write, 1, $false)
    $state = @{
        process = $Process; out = $Process.StandardOutput.BaseStream; in = $in
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
        }
    }
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
        $proc = Start-HordeSshProcess -FilePath $exe.path -Arguments (Join-HordeSshCommandLine -Argv (Get-HordeSshArgv -Endpoint $ep -Paths $paths))
        $peer = [pscustomobject]@{
            verified = $false
            identity = ($script:HordeSshHostKeyAliasPrefix + $ep.hubId)
            how = "the hub's host key is pinned by StrictHostKeyChecking=yes against Horde's own known_hosts under this alias; no live sshd has demonstrated it yet (remote plan R16, R17)"
        }
        return (New-HordeSshResult -Ok $true -Channel (New-HordeSshChannel -Process $proc) -Peer $peer)
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
