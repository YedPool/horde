# transports/ssh/test/Sshd.ps1 - a throwaway Windows sshd for test-sshd-local.ps1. Not a suite.
#
# WHY A CHILD PROCESS, NEVER THE SERVICE (remote plan R16, as rewritten 2026-10-05). OpenSSH Server is
# installed on the founder's machine with the sshd service Disabled and Stopped, its firewall rule
# disabled, and nothing on port 22; the design runs sshd only while `horde listen` runs. A test must
# not change any of that. So the test's sshd is C:\Windows\System32\OpenSSH\sshd.exe started as this
# suite's own child, in the foreground (-D -e), with a config, host key, authorized_keys and pid file
# all under one temporary folder, listening on 127.0.0.1 on a free port. Nothing under
# C:\ProgramData\ssh, no service setting, no firewall rule and no account is read for writing or
# changed. Measured 2026-10-05: sshd.exe runs this way from an elevated token and from a
# runas /trustlevel:0x20000 one (Administrators deny-only), and authenticates the same user.
#
# WHY THE FOLDER'S ACL IS SET. Windows sshd refuses an authorized_keys file another principal can
# read ("Bad permissions. Try removing permissions for user: <a local group>", measured
# 2026-10-05 on a file under TEMP), and ssh.exe refuses such a private key. The folder is made with a
# protected ACL: this user, SYSTEM and Administrators only, inherited by everything in it.
#
# EVERY PROCESS THE SSHD STARTS IS IN ONE JOB. Killing sshd.exe does not end its sessions: the
# forced command's cmd.exe and the PowerShell under it outlived it, held the suite's inherited output
# pipe, and kept the run's wrapper alive (four of them found and stopped by hand, 2026-10-05). So sshd
# and its watchdog go into a kill-on-close job object the moment they start; every session child
# joins it, Stop-HordeTestSshd ends the whole job, the suite checks the job holds no process
# afterwards, and if the suite itself dies Windows closes the job and ends everything in it.
#
# A WATCHDOG FOR A SUITE THAT HANGS. Start-HordeTestSshd also starts a small PowerShell process that
# ends the job's sshd, by pid and start time, after the suite's wall-clock limit.

if (-not ([System.Management.Automation.PSTypeName]"HordeTestJob").Type) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HordeTestJob {
    [StructLayout(LayoutKind.Sequential)] struct BASIC_LIMIT { public long a, b; public uint flags; public UIntPtr c, d; public uint e; public UIntPtr f; public uint g, h; }
    [StructLayout(LayoutKind.Sequential)] struct IO_COUNTERS { public ulong a, b, c, d, e, f; }
    [StructLayout(LayoutKind.Sequential)] struct EXTENDED_LIMIT { public BASIC_LIMIT basic; public IO_COUNTERS io; public UIntPtr p, j, pp, jp; }
    [StructLayout(LayoutKind.Sequential)] struct ACCOUNTING { public long a, b, c, d; public uint pageFaults, total, active, terminated; }
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr CreateJobObject(IntPtr a, string n);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetInformationJobObject(IntPtr j, int c, ref EXTENDED_LIMIT i, int l);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool AssignProcessToJobObject(IntPtr j, IntPtr p);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool QueryInformationJobObject(IntPtr j, int c, out ACCOUNTING i, int l, IntPtr r);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool TerminateJobObject(IntPtr j, uint code);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    // A job that kills every process in it when its last handle closes.
    public static IntPtr Create() {
        IntPtr j = CreateJobObject(IntPtr.Zero, null);
        if (j == IntPtr.Zero) throw new System.ComponentModel.Win32Exception();
        EXTENDED_LIMIT l = new EXTENDED_LIMIT();
        l.basic.flags = 0x2000;
        if (!SetInformationJobObject(j, 9, ref l, Marshal.SizeOf(l))) { int e = Marshal.GetLastWin32Error(); CloseHandle(j); throw new System.ComponentModel.Win32Exception(e); }
        return j;
    }
    public static void Assign(IntPtr j, IntPtr process) { if (!AssignProcessToJobObject(j, process)) throw new System.ComponentModel.Win32Exception(); }
    // How many processes in the job are alive now, or -1 when the job cannot be read.
    public static int Active(IntPtr j) { ACCOUNTING a; if (!QueryInformationJobObject(j, 1, out a, Marshal.SizeOf(typeof(ACCOUNTING)), IntPtr.Zero)) return -1; return (int)a.active; }
    public static bool Terminate(IntPtr j) { return TerminateJobObject(j, 1); }
    public static void Close(IntPtr j) { CloseHandle(j); }
}
'@
}

$script:HordeSshdExe = [System.IO.Path]::Combine([System.Environment]::SystemDirectory, "OpenSSH", "sshd.exe")
$script:HordeSshKeygenExe = [System.IO.Path]::Combine([System.Environment]::SystemDirectory, "OpenSSH", "ssh-keygen.exe")
# The watchdog's PowerShell, by its System32 path (review of PR #103, H5).
$script:HordeSshdPowerShellExe = [System.IO.Path]::Combine([System.Environment]::SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe")

function Get-HordeSshdServiceState {
    # The sshd service as "<State>/<StartMode>", e.g. "Stopped/Disabled", or "not installed".
    $s = Get-CimInstance -ClassName Win32_Service -Filter "Name='sshd'" -ErrorAction SilentlyContinue
    if ($null -eq $s) { return "not installed" }
    return ("" + $s.State + "/" + $s.StartMode)
}

function Get-HordeSshdFirewallState {
    # The OpenSSH-Server-In-TCP rule's Enabled value, or "absent".
    $r = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
    if ($null -eq $r) { return "absent" }
    return ("" + $r.Enabled)
}

function Get-HordeListenerCount {
    # How many sockets listen on -Port, on any address.
    param([Parameter(Mandatory = $true)][int]$Port)
    return @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue).Count
}

function Get-HordeSshFolderPrint {
    # Names, lengths and write times of every file under -Path: what a change to that folder would
    # change. Contents are not read - C:\ProgramData\ssh holds host keys this suite has no business reading.
    # What cannot be listed is named in the print, not dropped: from an unelevated token part of
    # C:\ProgramData\ssh is unreadable, and was invisible both before and after (review of PR #103, H4).
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return "(no folder)" }
    $unread = $null
    $lines = @(Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable unread | Sort-Object FullName | ForEach-Object { $_.FullName + " " + $_.Length + " " + $_.LastWriteTimeUtc.Ticks })
    $lines += @($unread | ForEach-Object { "unreadable: " + $_.TargetObject })
    return ($lines -join "`n")
}

function Get-HordeSshKeyFolderPrint {
    # Names, lengths and SHA-256 of every file under -Path: the user's ~/.ssh, byte for byte.
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return "(no folder)" }
    return ((@(Get-ChildItem -LiteralPath $Path -Recurse -File -Force | Sort-Object FullName | ForEach-Object { $_.FullName + " " + $_.Length + " " + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash })) -join "`n")
}

# A crashed run leaves its folder, private keys included (review of PR #103, H3: the kill-on-close job
# ends the processes, but nothing removed the folder). A live run's folder is never older than its
# wall-clock limit - the watchdog ends it - so one older than twice the limit is a dead run's.
$script:HordeSshdRootPattern = '\Ahorde-sshd-[0-9a-f]{12}\z'

function Remove-HordeSshdStaleRoots {
    # Remove each <Dir>\horde-sshd-<12 hex> folder created more than -OlderThanSeconds ago. Returns the
    # names removed. Nothing else in -Dir is touched.
    param([Parameter(Mandatory = $true)][string]$Dir, [Parameter(Mandatory = $true)][int]$OlderThanSeconds)
    $cut = [datetime]::UtcNow.AddSeconds(-$OlderThanSeconds)
    $gone = New-Object System.Collections.ArrayList
    foreach ($d in @(Get-ChildItem -LiteralPath $Dir -Directory -Force -ErrorAction SilentlyContinue)) {
        if ($d.Name -cnotmatch $script:HordeSshdRootPattern) { continue }
        if ($d.CreationTimeUtc -ge $cut) { continue }
        Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $d.FullName)) { [void]$gone.Add($d.Name) }
    }
    return @($gone)
}

function New-HordeSshdRoot {
    # A temporary folder only this user, SYSTEM and Administrators can read (see the header).
    $dir = Join-Path $env:TEMP ("horde-sshd-" + [guid]::NewGuid().ToString("N").Substring(0, 12))
    New-Item -ItemType Directory -Path $dir | Out-Null
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @($me, (New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")), (New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")))) {
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($sid, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
    }
    $acl.SetOwner($me)
    Set-Acl -LiteralPath $dir -AclObject $acl
    return $dir
}

function New-HordeSshdKey {
    # An ed25519 key pair at -Path and -Path.pub, no passphrase.
    param([Parameter(Mandatory = $true)][string]$Path)
    $psi = New-Object System.Diagnostics.ProcessStartInfo($script:HordeSshKeygenExe, ('-q -t ed25519 -N "" -C horde-test -f "' + $Path + '"'))
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $null = $p.StandardOutput.ReadToEnd(); $null = $p.StandardError.ReadToEnd()
    if (-not $p.WaitForExit(20000)) { try { $p.Kill() } catch { }; throw "ssh-keygen did not finish within 20 s" }
    if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $Path)) { throw ("ssh-keygen failed (exit " + $p.ExitCode + ")") }
}

function Get-HordeFreeLoopbackPort {
    $l = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()
    return $port
}

function Write-HordeSshdConfig {
    # The test-only sshd_config: 127.0.0.1 only, keys only, everything under -Root, and -ForceCommand
    # as the one thing a session may run. Forward slashes: sshd reads its config the POSIX way.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][int]$Port, [Parameter(Mandatory = $true)][string]$ForceCommand)
    $f = $Root.Replace('\', '/')
    # Each line in parentheses: in an array literal the comma binds tighter than +, so
    # "Port " + $Port, "next" made one line of every entry after it (measured: sshd -t, "keyword Port
    # extra arguments at end of line").
    $lines = @(
        ("Port " + $Port),
        "ListenAddress 127.0.0.1",
        ("HostKey " + $f + "/host_ed25519"),
        ("PidFile " + $f + "/sshd.pid"),
        ("AuthorizedKeysFile " + $f + "/authorized_keys"),
        "PubkeyAuthentication yes",
        "PasswordAuthentication no",
        "KbdInteractiveAuthentication no",
        "PermitTTY no",
        "AllowAgentForwarding no",
        "X11Forwarding no",
        "Subsystem sftp none",
        "LogLevel VERBOSE",
        ("ForceCommand " + $ForceCommand)
    )
    [System.IO.File]::WriteAllLines((Join-Path $Root "sshd_config"), [string[]]$lines)
    return (Join-Path $Root "sshd_config")
}

function Test-HordeSshdConfig {
    # sshd -t on the config: { ok; text }.
    param([Parameter(Mandatory = $true)][string]$Config)
    $psi = New-Object System.Diagnostics.ProcessStartInfo($script:HordeSshdExe, ('-t -f "' + $Config + '"'))
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(15000)) { try { $p.Kill() } catch { }; return [pscustomobject]@{ ok = $false; text = "sshd -t did not finish within 15 s" } }
    $p.WaitForExit()
    return [pscustomobject]@{ ok = ($p.ExitCode -eq 0); text = ("" + $o.Result + $e.Result).Trim() }
}

function Start-HordeTestSshd {
    # sshd.exe -D -e -f <Config>, as this suite's child, and its watchdog: { process; startedAt; log;
    # watchdog }. -LimitSeconds is when the watchdog kills it if the suite has not.
    param([Parameter(Mandatory = $true)][string]$Config, [Parameter(Mandatory = $true)][int]$LimitSeconds)
    $psi = New-Object System.Diagnostics.ProcessStartInfo($script:HordeSshdExe, ('-D -e -f "' + $Config + '"'))
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $job = [HordeTestJob]::Create()
    $p = [System.Diagnostics.Process]::Start($psi)
    try { [HordeTestJob]::Assign($job, $p.Handle) } catch { try { $p.Kill() } catch { }; [HordeTestJob]::Close($job); throw }
    $started = $p.StartTime.ToUniversalTime().Ticks
    $log = $p.StandardError.ReadToEndAsync()
    $null = $p.StandardOutput.ReadToEndAsync()
    # The watchdog: kills this pid only if it is still the process started at $started.
    $kill = "Start-Sleep -Seconds " + $LimitSeconds + "; try { `$q = Get-Process -Id " + $p.Id + " -ErrorAction Stop; if (`$q.StartTime.ToUniversalTime().Ticks -eq " + $started + ") { `$q.Kill() } } catch { }"
    # By its System32 path, never a PATH lookup (review of PR #103, H5).
    $wsi = New-Object System.Diagnostics.ProcessStartInfo($script:HordeSshdPowerShellExe, ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "' + $kill + '"'))
    $wsi.UseShellExecute = $false; $wsi.CreateNoWindow = $true
    $w = [System.Diagnostics.Process]::Start($wsi)
    [HordeTestJob]::Assign($job, $w.Handle)
    return [pscustomobject]@{ process = $p; startedAt = $started; log = $log; watchdog = $w; watchdogStartedAt = $w.StartTime.ToUniversalTime().Ticks; watchdogExe = $wsi.FileName; job = $job }
}

function Stop-HordeTestSshd {
    # End the sshd, its watchdog and every session either started: the whole job (see the header).
    # Returns sshd's stderr text. The job's handle stays open, so Get-HordeTestSshdLeft can still
    # count what is in it; Close-HordeTestSshd closes it.
    param([Parameter(Mandatory = $true)]$Sshd)
    $null = [HordeTestJob]::Terminate($Sshd.job)
    foreach ($p in @($Sshd.process, $Sshd.watchdog)) {
        if ($null -ne $p -and -not $p.HasExited) { $null = $p.WaitForExit(10000) }
    }
    $text = ""
    try { if ($Sshd.log.Wait(5000)) { $text = "" + $Sshd.log.Result } } catch { }
    return $text
}

function Get-HordeTestSshdLeft {
    # How many processes of the sshd's job are still alive: sshd, its watchdog and every session child.
    param([Parameter(Mandatory = $true)]$Sshd)
    $deadline = [datetime]::UtcNow.AddSeconds(10)
    $n = [HordeTestJob]::Active($Sshd.job)
    while ($n -gt 0 -and [datetime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 200; $n = [HordeTestJob]::Active($Sshd.job) }
    return $n
}

function Get-HordeTestSshdLive {
    # How many processes of the sshd's job are alive right now, without waiting.
    param([Parameter(Mandatory = $true)]$Sshd)
    return [HordeTestJob]::Active($Sshd.job)
}

function Close-HordeTestSshd {
    param([Parameter(Mandatory = $true)]$Sshd)
    [HordeTestJob]::Close($Sshd.job)
}

function Test-HordeTestSshdGone {
    # Is no process left with the sshd's pid and start time? Asked for up to 10 s: a process ended
    # through its job is still listed for a moment after (a Mutate baseline read it alive once, measured
    # 2026-10-06 in a Mutate baseline).
    param([Parameter(Mandatory = $true)]$Sshd)
    $deadline = [datetime]::UtcNow.AddSeconds(10)
    while ($true) {
        $q = Get-Process -Id $Sshd.process.Id -ErrorAction SilentlyContinue
        if ($null -eq $q -or $q.HasExited -or $q.StartTime.ToUniversalTime().Ticks -ne $Sshd.startedAt) { return $true }
        if ([datetime]::UtcNow -ge $deadline) { return $false }
        Start-Sleep -Milliseconds 200
    }
}
