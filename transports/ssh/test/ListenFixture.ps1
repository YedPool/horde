# transports/ssh/test/ListenFixture.ps1 - helpers for test-listen-local.ps1. Not a suite.
#
# What the listener's live suite needs around the code under test: a Horde home it may write, keys,
# the machine's state before and after (so a change to it is a loud failure, never put back), and
# every process it starts held in a kill-on-close job of its own, so that a suite that dies leaves
# nothing running (R16's lesson: four sessions outlived their sshd, 2026-10-05).

$script:ListenSshExe = [System.IO.Path]::Combine([System.Environment]::SystemDirectory, "OpenSSH", "ssh.exe")
$script:ListenSshdExe = [System.IO.Path]::Combine([System.Environment]::SystemDirectory, "OpenSSH", "sshd.exe")
$script:ListenKeygenExe = [System.IO.Path]::Combine([System.Environment]::SystemDirectory, "OpenSSH", "ssh-keygen.exe")

function Get-ListenServiceState {
    # The sshd service as "<State>/<StartMode>", or "not installed".
    $s = Get-CimInstance -ClassName Win32_Service -Filter "Name='sshd'" -ErrorAction SilentlyContinue
    if ($null -eq $s) { return "not installed" }
    return ("" + $s.State + "/" + $s.StartMode)
}

function Get-ListenFirewallState {
    # The OpenSSH-Server-In-TCP rule: whether it is enabled, and its direction and action.
    $r = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
    if ($null -eq $r) { return "absent" }
    return ("enabled=" + $r.Enabled + " " + $r.Direction + " " + $r.Action)
}

function Get-ListenListeners {
    # How many sockets listen on -Port, on any address.
    param([Parameter(Mandatory = $true)][int]$Port)
    return @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue).Count
}

function Get-ListenFolderPrint {
    # Names, lengths and write times under -Path, contents unread (host keys live there).
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return "(no folder)" }
    return ((@(Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue | Sort-Object FullName | ForEach-Object { $_.FullName + " " + $_.Length + " " + $_.LastWriteTimeUtc.Ticks })) -join "`n")
}

function Get-ListenMachine {
    # Everything the listener must never change.
    return [pscustomobject]@{
        service = (Get-ListenServiceState); firewall = (Get-ListenFirewallState); port22 = (Get-ListenListeners -Port 22)
        programData = (Get-ListenFolderPrint -Path (Join-Path $env:ProgramData "ssh"))
        userSsh = (Get-ListenFolderPrint -Path (Join-Path $env:USERPROFILE ".ssh"))
    }
}

function New-ListenWork {
    # A folder only this user, SYSTEM and Administrators can read: Windows sshd refuses an
    # authorized_keys another principal can read (R16, measured 2026-10-05).
    $dir = Join-Path $env:TEMP ("horde-listen-" + [guid]::NewGuid().ToString("N").Substring(0, 12))
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

function New-ListenKey {
    # An ed25519 key pair at -Path and -Path.pub, no passphrase.
    param([Parameter(Mandatory = $true)][string]$Path)
    $psi = New-Object System.Diagnostics.ProcessStartInfo($script:ListenKeygenExe, ('-q -t ed25519 -N "" -C horde-test -f "' + $Path + '"'))
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $null = $p.StandardOutput.ReadToEnd(); $null = $p.StandardError.ReadToEnd()
    if (-not $p.WaitForExit(20000)) { try { $p.Kill() } catch { }; throw "ssh-keygen did not finish within 20 s" }
    if ($p.ExitCode -ne 0) { throw ("ssh-keygen failed (exit " + $p.ExitCode + ")") }
    return ([System.IO.File]::ReadAllText($Path + ".pub").Trim().Split(' ')[0..1] -join " ")
}

function Get-ListenFreePort {
    $l = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $l.Start(); $p = $l.LocalEndpoint.Port; $l.Stop()
    return $p
}

function Start-ListenChild {
    # A program as this suite's child, in -Job (kill-on-close), stdin/stdout/stderr redirected:
    # { process; out; err } with out and err read as they come into string builders.
    param([Parameter(Mandatory = $true)][string]$Exe, [Parameter(Mandatory = $true)][string]$Arguments, [Parameter(Mandatory = $true)]$Job, [string]$Directory = "")
    $psi = New-Object System.Diagnostics.ProcessStartInfo($Exe, $Arguments)
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    if ($Directory -ne "") { $psi.WorkingDirectory = $Directory }
    $p = [System.Diagnostics.Process]::Start($psi)
    try { [HordeSshNative]::Assign($Job, $p.Handle) } catch { try { $p.Kill() } catch { }; throw }
    return [pscustomobject]@{ process = $p }
}

function Read-ListenLine {
    # The next line of -Reader within -Ms, or $null.
    param([Parameter(Mandatory = $true)]$Reader, [int]$Ms = 10000)
    $t = $Reader.ReadLineAsync()
    if ($t.Wait($Ms)) { return $t.Result }
    return $null
}

function Get-ListenProcesses {
    # Live processes whose command line holds -Marker: what a teardown must find none of.
    param([Parameter(Mandatory = $true)][string]$Marker)
    return @(Get-CimInstance -ClassName Win32_Process -ErrorAction SilentlyContinue | Where-Object { "$($_.CommandLine)".IndexOf($Marker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and $_.ProcessId -ne $PID })
}

function Get-ListenText {
    # What -Task (a ReadToEndAsync) read, waiting at most -Ms. A pipe another process still holds never
    # ends: a mutant that left sshd outside its job kept horde listen's stdout open through the handle
    # sshd inherited, and an unbounded .Result hung the suite for 900 s (2026-10-07).
    param([Parameter(Mandatory = $true)]$Task, [int]$Ms = 5000)
    if ($Task.Wait($Ms)) { return ("" + $Task.Result) }
    return ("(the stream was still open after " + $Ms + " ms: another process holds it)")
}
