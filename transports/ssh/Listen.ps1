# transports/ssh/Listen.ps1 - the hub's listener: a Windows sshd that is `horde listen`'s own child.
#
# WHY A CHILD, NEVER THE SERVICE (remote plan R16 and R17a, coordinator's decisions of 2026-10-05 and
# 2026-10-07). OpenSSH Server is installed with its sshd service Disabled and Stopped, its firewall rule
# disabled and nothing on port 22, and Horde never changes any of that. The listener is
# C:\Windows\System32\OpenSSH\sshd.exe started by `horde listen`, in the foreground (-D -e), with
# Horde's own configuration, host key and authorized_keys, all under <home>\hub\listen - never
# C:\ProgramData\ssh, never ~/.ssh. It binds 127.0.0.1 only: a node on another machine arrives through
# a tunnel to that address (R17d), so no firewall rule is ever needed. It runs as the user who runs
# `horde listen`, and a Windows sshd that is not SYSTEM can admit only that same user (measured
# 2026-10-05, R16): links run under the founder's own account, held by the key options.
#
# EVERY PROCESS IT STARTS IS IN ONE KILL-ON-CLOSE JOB (Native.ps1), whose only handle the listener
# holds. Killing sshd.exe alone does not end its sessions (R16, 2026-10-05: four survivors found by
# hand), so Stop closes the job, and if `horde listen` itself dies Windows closes the job and ends
# sshd and every session with it. Measured 2026-10-07: a session's processes stay in the job, and none
# is left after it closes.
#
# THE FORCED COMMAND IS EACH KEY'S command=, NOT A ForceCommand. Measured 2026-10-07 with this sshd
# (9.5p1): a ForceCommand in sshd_config replaces the key's command= entirely, so the -Device the
# enrolment wrote into the key (R17b) never reaches attach, and attach is what binds the link to its
# device (remote/LinkBinding.ps1). So the configuration has no ForceCommand, and Start refuses to run
# while any line of authorized_keys lacks the forced attach this Horde expects or restrict: an
# admitted key without them would be a shell. The same measurement showed the command the client
# asks for is never run (the forced one ran instead).
#
# HORDE'S HOME REACHES THE SESSION, AND SetEnv SAYS SO. attach must use the listener's own home, to
# find the same device id and so the same hub pipe. Measured 2026-10-07: SetEnv HORDE_HOME reaches the
# session; and a session of this non-SYSTEM sshd also inherits `horde listen`'s environment, so the
# live suite passed with SetEnv removed. SetEnv stays so the home does not rest on an inheritance
# nothing documents (the sshd service, as SYSTEM, builds the user's environment afresh; unmeasured here).
#
# ONE PROGRAM, STARTED ONE WAY (transports/ssh/test/ExecGuard.ps1): Start-HordeSshServer starts the
# System32 sshd.exe, named by its absolute path, with one fixed argv - -D -e -f and the configuration
# this file wrote under Horde's home.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path $PSScriptRoot "Argv.ps1")
. (Join-Path $PSScriptRoot "Native.ps1")
. (Join-Path $PSScriptRoot "Attach.ps1")

$script:HordeSshListenFolder = $PSScriptRoot
$script:HordeSshListenDevicePattern = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
# One admitted key, as enrolment writes it (R17b): the forced attach, restrict, an optional expiry, the
# ed25519 key, and the device it was enrolled for as the comment.
$script:HordeSshListenKeyPattern = '\Acommand="(?<cmd>[^"]+)",restrict(?:,expiry-time="[0-9]{8}")? ssh-ed25519 [A-Za-z0-9+/]{68} horde-device-(?<dev>' + $script:HordeSshListenDevicePattern + ')\z'
# How long sshd has to answer on its port before Start gives up and reports its log.
$script:HordeSshListenStartMs = 15000

function Get-HordeSshListenFiles {
    # Where the listener's files live, all under Horde's home (the layout enrolment writes, R17b).
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    $dir = Join-Path $HordeHome "hub\listen"
    return [pscustomobject]@{
        dir = $dir; hostKey = (Join-Path $dir "host_ed25519"); authorized = (Join-Path $dir "authorized_keys")
        revoked = (Join-Path $dir "revoked_keys"); config = (Join-Path $dir "sshd_config"); pid = (Join-Path $dir "sshd.pid")
    }
}

function Test-HordeSshListenKeys {
    # Findings for authorized_keys' -Lines: empty means every line admits one device, forced to exactly
    # the attach command this Horde (-Root) builds for that device (Get-HordeSshAttachCommand, Attach.ps1), restricted.
    # A line without command= would be a shell, so it is a finding like any other. Lines are named by
    # number, never quoted: they hold keys.
    param([string[]]$Lines, [Parameter(Mandatory = $true)][string]$Root)
    $out = New-Object System.Collections.ArrayList
    $n = 0
    $admitted = 0
    foreach ($l in @($Lines)) {
        $n++
        if ("$l".Trim() -eq "") { continue }
        $m = [regex]::Match("$l", $script:HordeSshListenKeyPattern)
        if (-not $m.Success) { [void]$out.Add("line " + $n + " of authorized_keys is not one enrolled device: a forced command=, restrict, an ed25519 key and horde-device-<id>"); continue }
        if ($m.Groups["cmd"].Value -cne (Get-HordeSshAttachCommand -HordeRoot $Root -DeviceId $m.Groups["dev"].Value)) { [void]$out.Add("line " + $n + " of authorized_keys forces a command other than this Horde's attach for the device it names"); continue }
        $admitted++
    }
    if ($out.Count -eq 0 -and $admitted -eq 0) { [void]$out.Add("authorized_keys admits no device: enrol one first") }
    return @($out)
}

function Get-HordeSshListenConfig {
    # The sshd_config text, as lines. Forward slashes: sshd reads its configuration the POSIX way.
    param([Parameter(Mandatory = $true)]$Files, [Parameter(Mandatory = $true)][int]$Port, [Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$User)
    $f = $Files.dir.Replace('\', '/')
    # Each entry in parentheses: in an array literal the comma binds tighter than + (R16, measured).
    return @(
        ("Port " + $Port),
        "ListenAddress 127.0.0.1",
        "AddressFamily inet",
        ("HostKey " + $f + "/host_ed25519"),
        ("PidFile " + $f + "/sshd.pid"),
        ("AuthorizedKeysFile " + $f + "/authorized_keys"),
        ("RevokedKeys " + $f + "/revoked_keys"),
        ("AllowUsers " + $User),
        "PubkeyAuthentication yes",
        "PasswordAuthentication no",
        "KbdInteractiveAuthentication no",
        "PermitTTY no",
        "DisableForwarding yes",
        "PermitTunnel no",
        "PermitUserEnvironment no",
        "MaxAuthTries 2",
        "MaxSessions 1",
        "LoginGraceTime 20",
        "ClientAliveInterval 15",
        "ClientAliveCountMax 4",
        "MaxStartups 4:50:8",
        ('SetEnv "HORDE_HOME=' + $HordeHome.Replace('\', '/') + '"'),
        "LogLevel VERBOSE"
    )
}

function Start-HordeSshServer {
    # THE ONE PLACE the listener starts a program: the System32 sshd.exe, its argv fixed here, into -Job
    # on the next statement (Native.ps1). stdout and stderr are redirected; no window, no shell.
    param([Parameter(Mandatory = $true)][string]$Config, [Parameter(Mandatory = $true)][HordeSshJob]$Job)
    $serverArgs = Join-HordeSshCommandLine -Argv @("-D", "-e", "-f", $Config)
    $psi = [System.Diagnostics.ProcessStartInfo]::new([System.IO.Path]::Combine([System.Environment]::SystemDirectory, "OpenSSH", "sshd.exe"), $serverArgs)
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

function Test-HordeSshListenPort {
    # Does something accept a TCP connection on 127.0.0.1:-Port within -Ms?
    param([int]$Port, [int]$Ms)
    $c = New-Object System.Net.Sockets.TcpClient
    try { return ($c.ConnectAsync("127.0.0.1", $Port).Wait($Ms) -and $c.Connected) }
    catch { return $false }
    finally { $c.Dispose() }
}

function New-HordeSshListenResult {
    param([bool]$Ok, $Listener = $null, [string]$Address = "", [string]$Reason = "")
    return [pscustomobject]@{ ok = $Ok; listener = $Listener; address = $Address; reason = $Reason }
}

function Stop-HordeSshListener {
    # End sshd and every session it started (the whole job), and return what it wrote to stderr.
    param([Parameter(Mandatory = $true)]$Listener)
    try { $Listener.job.Dispose() } catch { }
    if ($null -ne $Listener.process -and -not $Listener.process.HasExited) { $null = $Listener.process.WaitForExit(10000) }
    $text = ""
    try { if ($Listener.log.Wait(5000)) { $text = "" + $Listener.log.Result } } catch { }
    return $text
}

function Test-HordeSshListenerServing {
    # The adapter's Health: known $true while sshd runs and every authorized_keys line still holds to
    # attach; known $false once sshd has ended; unknown, with the reason, when the keys no longer hold.
    # WHY THE KEYS AGAIN (issue #147, item 4): sshd reads authorized_keys at every login, so a line
    # written after Start - by a buggy writer, a bare key above all - would be admitted unchecked.
    # horde listen asks this every second and stops the listener on anything but known $true.
    param([Parameter(Mandatory = $true)]$Listener)
    $p = $Listener.process
    if ($null -eq $p -or $p.HasExited) { return (New-HordeKnown -Value $false) }
    if (-not (Test-Path -LiteralPath $Listener.authorized -PathType Leaf)) { return (New-HordeUnknown -Reason ("authorized_keys is gone (" + $Listener.authorized + "); the listener stops")) }
    $found = @(Test-HordeSshListenKeys -Lines ([System.IO.File]::ReadAllLines($Listener.authorized)) -Root $Listener.root)
    if ($found.Count -gt 0) { return (New-HordeUnknown -Reason ("authorized_keys changed after the listener started and no longer holds every key to attach: " + ($found -join "; ") + "; the listener stops")) }
    return (New-HordeKnown -Value $true)
}

function Start-HordeSshListener {
    # The adapter's Start (transports/Listener.ps1). -Request is { hordeHome; hubId; port; root }.
    param([Parameter(Mandatory = $true)]$Request)
    if ("$($Request.hubId)" -cnotmatch ('\A' + $script:HordeSshListenDevicePattern + '\z')) { return (New-HordeSshListenResult -Ok $false -Reason ("'" + $Request.hubId + "' is not a hub id: one lowercase UUID, the hub's device id")) }
    $port = [int]$Request.port
    if ($port -lt 1 -or $port -gt 65535) { return (New-HordeSshListenResult -Ok $false -Reason ("port " + $port + " is not a TCP port to listen on")) }
    # The configuration names files under the home unquoted, and sshd reads a space as the end of a
    # path, # as a comment and % in AuthorizedKeysFile as a token (issue #147, item 3). Such a home
    # would fail closed but say nothing useful, so it is refused here, saying why.
    if ("$($Request.hordeHome)" -match '[\s#%"]') { return (New-HordeSshListenResult -Ok $false -Reason ("Horde's home '" + $Request.hordeHome + "' holds a space, #, % or quote, which sshd's configuration cannot name; set HORDE_HOME to a path without them")) }
    $files = Get-HordeSshListenFiles -HordeHome $Request.hordeHome
    if (-not (Test-Path -LiteralPath $files.hostKey -PathType Leaf)) { return (New-HordeSshListenResult -Ok $false -Reason ("the hub has no listener host key at " + $files.hostKey + ": run horde hub init")) }
    if (-not (Test-Path -LiteralPath $files.authorized -PathType Leaf)) { return (New-HordeSshListenResult -Ok $false -Reason ("no node is enrolled (" + $files.authorized + " does not exist): run horde hub enroll")) }
    $found = @(Test-HordeSshListenKeys -Lines ([System.IO.File]::ReadAllLines($files.authorized)) -Root "$($Request.root)")
    if ($found.Count -gt 0) { return (New-HordeSshListenResult -Ok $false -Reason ("the listener will not admit keys it cannot hold to attach: " + ($found -join "; "))) }
    # A missing RevokedKeys file makes sshd refuse every key; an empty one revokes none.
    if (-not (Test-Path -LiteralPath $files.revoked -PathType Leaf)) { [System.IO.File]::WriteAllText($files.revoked, "") }
    $user = [System.Environment]::UserName.ToLowerInvariant()
    [System.IO.File]::WriteAllLines($files.config, [string[]](Get-HordeSshListenConfig -Files $files -Port $port -HordeHome $Request.hordeHome -User $user))
    $job = [HordeSshNative]::NewKillOnCloseJob()
    $handed = $false
    $proc = $null
    try {
        $proc = Start-HordeSshServer -Config $files.config -Job $job
        $listener = [pscustomobject]@{ process = $proc; startedAt = $proc.StartTime.ToUniversalTime().Ticks; job = $job; log = $proc.StandardError.ReadToEndAsync(); port = $port; config = $files.config; authorized = $files.authorized; root = "$($Request.root)" }
        $null = $proc.StandardOutput.ReadToEndAsync()
        $deadline = [datetime]::UtcNow.AddMilliseconds($script:HordeSshListenStartMs)
        $up = $false
        while (-not $up -and -not $proc.HasExited -and [datetime]::UtcNow -lt $deadline) { $up = Test-HordeSshListenPort -Port $port -Ms 500 }
        if (-not $up) {
            $said = (Stop-HordeSshListener -Listener $listener).Trim()
            return (New-HordeSshListenResult -Ok $false -Reason ("sshd did not answer on 127.0.0.1:" + $port + " within " + $script:HordeSshListenStartMs + " ms: " + $said.Replace("`r", "").Replace("`n", " | ")))
        }
        $handed = $true
        return (New-HordeSshListenResult -Ok $true -Listener $listener -Address ("127.0.0.1:" + $port))
    } finally {
        if (-not $handed) { try { $job.Dispose() } catch { } }
    }
}

$null = Register-HordeListener -Folder $script:HordeSshListenFolder `
    -Start { param($Request) return (Start-HordeSshListener -Request $Request) } `
    -Health { param($Listener) return (Test-HordeSshListenerServing -Listener $Listener) } `
    -Stop { param($Listener) return (Stop-HordeSshListener -Listener $Listener) }
