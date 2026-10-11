# transports/ssh/Listen.ps1 - the hub's listener: a Windows sshd that is `horde listen`'s own child.
#
# WHY A CHILD, NEVER THE SERVICE (remote plan R16 and R17a, coordinator's decisions of 2026-10-05 and
# 2026-10-07). OpenSSH Server is installed with its sshd service Disabled and Stopped, its firewall rule
# disabled and nothing on port 22, and Horde never changes any of that. The listener is
# C:\Windows\System32\OpenSSH\sshd.exe started by `horde listen`, in the foreground (-D -e), with
# Horde's own configuration, host key and authorized_keys, all under <home>\hub\listen - never
# C:\ProgramData\ssh, never ~/.ssh. It binds ONE address, 127.0.0.1 unless `horde listen -Address` names
# another: a private one this machine holds - the office LAN, Tailscale, WireGuard - and never a public
# one or every interface (mesh v1, the founder's rule 4; core/ListenAddress.ps1, which the listener port
# applies and this adapter applies again). On any address but loopback the inbound firewall rule is
# horde listen's to keep, through core/FirewallPort.ps1; this file opens none. It runs as the user who runs
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
. (Join-Path $PSScriptRoot "Files.ps1")

$script:HordeSshListenFolder = $PSScriptRoot
$script:HordeSshListenDevicePattern = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
# One admitted key, as enrolment writes it (R17b): the forced attach, restrict, an optional expiry, the
# ed25519 key, and the device it was enrolled for as the comment.
$script:HordeSshListenKeyPattern = '\Acommand="(?<cmd>[^"]+)",restrict(?:,expiry-time="[0-9]{8}")? (?<key>ssh-ed25519 [A-Za-z0-9+/]{68}) horde-device-(?<dev>' + $script:HordeSshListenDevicePattern + ')\z'
# How long sshd has to answer on its port before Start gives up and reports its log.
$script:HordeSshListenStartMs = 15000
# THE MEMORY ANY ONE PROCESS OF THE LISTENER MAY COMMIT (issue #147, item 1). attach reads stdin through
# $input, which holds a line until its LF arrives, so a peer that never sends one would grow attach
# without end; the cap ends it there. Measured 2026-10-07 on this machine (Windows PowerShell 5.1,
# OpenSSH 9.5p1), private commit through the real listener: attach peaks at 150 MB starting up and at
# 207 MB while relaying twelve 4 MiB frames (the ceiling) back to back; each sshd process stays under
# 4 MB; a line with no LF grows attach by about 2 bytes per byte sent (16 MB per 8 MiB, UTF-16), from
# 81 MB idle to 200 MB after 64 MiB. 320 MiB leaves about 1.5 times the relaying peak, and a never-ending
# line reaches it after roughly 120 MiB.
$script:HordeSshListenProcessBytes = 320MB
# WHAT THE LISTENER'S PROCESSES MAY COMMIT TOGETHER, AND HOW MANY MAY RUN (mesh v1, issue #147 item 2;
# Native.ps1, LimitListenerJob). One key opening many connections must not commit gigabytes: each
# connection starts a PowerShell for attach before attach's one-link-per-device check can end it.
# Measured 2026-10-11 on this machine through the real listener (transports/ssh/test/test-listen-local.ps1):
# one open session is six processes under the listener's sshd, and attach commits 81 MB idle, 150 MB
# starting and 207 MB relaying at the frame ceiling (2026-10-07, above). 1 GiB holds the listener and about
# five links relaying at their peak at once, or a dozen idle; 64 processes hold ten sessions and the sshd.
# A link past either fails to start and its node redials; nothing already up is touched.
$script:HordeSshListenJobBytes = 1GB
$script:HordeSshListenActiveProcesses = 64

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
    # AND THE HUB'S REGISTER HOLDS EACH LINE'S DEVICE, LIVE, WITH THAT KEY (issue #144 item 3, issue #147
    # item 4): -Register is the register as the listener port read it just now (transports/Listener.ps1),
    # device id -> the key enrolled for it, live devices only (cli/HubRegistry.ps1). A line written by
    # hand under any device id - one the register never held, revoked, expired, or with another key - is
    # a finding, so `horde listen` neither starts on it nor keeps serving once it appears.
    param([string[]]$Lines, [Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][hashtable]$Register)
    $out = New-Object System.Collections.ArrayList
    $n = 0
    $admitted = 0
    foreach ($l in @($Lines)) {
        $n++
        if ("$l".Trim() -eq "") { continue }
        $m = [regex]::Match("$l", $script:HordeSshListenKeyPattern)
        if (-not $m.Success) { [void]$out.Add("line " + $n + " of authorized_keys is not one enrolled device: a forced command=, restrict, an ed25519 key and horde-device-<id>"); continue }
        if ($m.Groups["cmd"].Value -cne (Get-HordeSshAttachCommand -HordeRoot $Root -DeviceId $m.Groups["dev"].Value)) { [void]$out.Add("line " + $n + " of authorized_keys forces a command other than this Horde's attach for the device it names"); continue }
        $enrolledKey = $Register[$m.Groups["dev"].Value]
        if ($null -eq $enrolledKey) { [void]$out.Add("line " + $n + " of authorized_keys admits device " + $m.Groups["dev"].Value + ", which the hub's register does not hold as enrolled now (never enrolled, revoked or past its expiry)"); continue }
        if ("$enrolledKey" -cne $m.Groups["key"].Value) { [void]$out.Add("line " + $n + " of authorized_keys admits device " + $m.Groups["dev"].Value + " with another key than the one the hub's register enrolled for it"); continue }
        $admitted++
    }
    if ($out.Count -eq 0 -and $admitted -eq 0) { [void]$out.Add("authorized_keys admits no device: enrol one first") }
    return @($out)
}

function Get-HordeSshListenConfig {
    # The sshd_config text, as lines. Forward slashes: sshd reads its configuration the POSIX way.
    # -Address is the one address to bind, already checked (Start-HordeSshListener), and -Family its
    # family, "v4" or "v6".
    param([Parameter(Mandatory = $true)]$Files, [Parameter(Mandatory = $true)][int]$Port, [Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$User, [string]$Address = "127.0.0.1", [string]$Family = "v4")
    $f = $Files.dir.Replace('\', '/')
    $af = "inet"; if ($Family -ceq "v6") { $af = "inet6" }
    # Each entry in parentheses: in an array literal the comma binds tighter than + (R16, measured).
    return @(
        ("Port " + $Port),
        ("ListenAddress " + $Address),
        ("AddressFamily " + $af),
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
    # Does something accept a TCP connection on -Address:-Port within -Ms?
    param([int]$Port, [int]$Ms, [string]$Address = "127.0.0.1")
    $c = New-Object System.Net.Sockets.TcpClient([System.Net.IPAddress]::Parse($Address).AddressFamily)
    try { return ($c.ConnectAsync([System.Net.IPAddress]::Parse($Address), $Port).Wait($Ms) -and $c.Connected) }
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
    # -Register is the hub's register as the port read it for this check (Test-HordeSshListenKeys).
    param([Parameter(Mandatory = $true)]$Listener, [Parameter(Mandatory = $true)][hashtable]$Register)
    $p = $Listener.process
    if ($null -eq $p -or $p.HasExited) { return (New-HordeKnown -Value $false) }
    if (-not (Test-Path -LiteralPath $Listener.authorized -PathType Leaf)) { return (New-HordeUnknown -Reason ("authorized_keys is gone (" + $Listener.authorized + "); the listener stops")) }
    $found = @(Test-HordeSshListenKeys -Lines ([System.IO.File]::ReadAllLines($Listener.authorized)) -Root $Listener.root -Register $Register)
    if ($found.Count -gt 0) { return (New-HordeUnknown -Reason ("authorized_keys changed after the listener started and no longer holds every key to attach: " + ($found -join "; ") + "; the listener stops")) }
    return (New-HordeKnown -Value $true)
}

function Start-HordeSshListener {
    # The adapter's Start (transports/Listener.ps1). -Request is { hordeHome; hubId; port; root; register;
    # address }.
    param([Parameter(Mandatory = $true)]$Request)
    # THE HUB NEVER LISTENS ON A PUBLIC ADDRESS (header): the port checked the address, and it is checked
    # again here, where it is written into the server's configuration.
    $where = Get-HordeListenAddressKind -Address "$($Request.address)"
    if ($where.state -cne "known") { return (New-HordeSshListenResult -Ok $false -Reason ("the listener will not bind that address: " + $where.reason)) }
    $bind = $where.value
    if ($Request.register -isnot [hashtable]) { return (New-HordeSshListenResult -Ok $false -Reason "the listener was given no register of enrolled devices to hold each key to, so it admits none") }
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
    # NO FILE THAT DECIDES ADMISSION, AND NO FOLDER ABOVE IT UP TO HORDE'S HOME, MAY BE WRITTEN BY ANOTHER
    # PRINCIPAL (issue #123; Files.ps1): the listener does not start on keys someone else could have put there.
    $loose = @(Test-HordeSshOnlyMine -Paths @($files.authorized, $files.revoked, $files.hostKey) -Top "$($Request.hordeHome)")
    if ($loose.Count -gt 0) { return (New-HordeSshListenResult -Ok $false -Reason ("the listener will not start on files another principal may write: " + ($loose -join "; ") + "; make Horde's home this user's (with SYSTEM and Administrators) and enrol again")) }
    $found = @(Test-HordeSshListenKeys -Lines ([System.IO.File]::ReadAllLines($files.authorized)) -Root "$($Request.root)" -Register $Request.register)
    if ($found.Count -gt 0) { return (New-HordeSshListenResult -Ok $false -Reason ("the listener will not admit keys it cannot hold to attach: " + ($found -join "; "))) }
    # A missing RevokedKeys file makes sshd refuse every key; an empty one revokes none. Written as enrolment
    # writes it: this user's alone.
    if (-not (Test-Path -LiteralPath $files.revoked -PathType Leaf)) { Write-HordeSshLines -Path $files.revoked -Lines @() }
    $user = [System.Environment]::UserName.ToLowerInvariant()
    [System.IO.File]::WriteAllLines($files.config, [string[]](Get-HordeSshListenConfig -Files $files -Port $port -HordeHome $Request.hordeHome -User $user -Address $bind.address -Family $bind.family))
    $job = [HordeSshNative]::NewKillOnCloseJob()
    $handed = $false
    $proc = $null
    try {
        # No process of the listener may commit more than its cap, nor all of them together more than
        # theirs, nor more of them run at once than the count (Native.ps1, LimitListenerJob).
        [HordeSshNative]::LimitListenerJob($job, [long]$script:HordeSshListenProcessBytes, [long]$script:HordeSshListenJobBytes, [int]$script:HordeSshListenActiveProcesses)
        $proc = Start-HordeSshServer -Config $files.config -Job $job
        $listener = [pscustomobject]@{ process = $proc; startedAt = $proc.StartTime.ToUniversalTime().Ticks; job = $job; log = $proc.StandardError.ReadToEndAsync(); port = $port; config = $files.config; authorized = $files.authorized; root = "$($Request.root)" }
        $null = $proc.StandardOutput.ReadToEndAsync()
        $deadline = [datetime]::UtcNow.AddMilliseconds($script:HordeSshListenStartMs)
        $up = $false
        $shown = $bind.address + ":" + $port
        if ($bind.family -ceq "v6") { $shown = "[" + $bind.address + "]:" + $port }
        while (-not $up -and -not $proc.HasExited -and [datetime]::UtcNow -lt $deadline) { $up = Test-HordeSshListenPort -Port $port -Ms 500 -Address $bind.address }
        if (-not $up) {
            $said = (Stop-HordeSshListener -Listener $listener).Trim()
            return (New-HordeSshListenResult -Ok $false -Reason ("sshd did not answer on " + $shown + " within " + $script:HordeSshListenStartMs + " ms: " + $said.Replace("`r", "").Replace("`n", " | ")))
        }
        $handed = $true
        return (New-HordeSshListenResult -Ok $true -Listener $listener -Address $shown)
    } finally {
        if (-not $handed) { try { $job.Dispose() } catch { } }
    }
}

$null = Register-HordeListener -Folder $script:HordeSshListenFolder `
    -Start { param($Request) return (Start-HordeSshListener -Request $Request) } `
    -Health { param($Listener, $Register) return (Test-HordeSshListenerServing -Listener $Listener -Register $Register) } `
    -Stop { param($Listener) return (Stop-HordeSshListener -Listener $Listener) }
