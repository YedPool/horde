# DOES THE SSH TRANSPORT HOLD AGAINST A REAL WINDOWS SSHD, AND IS THE MACHINE'S SSHD LEFT AS IT WAS?
#
# Remote plan step R16 (rewritten 2026-10-05): the cases R5 could not run without a live server, run
# against the Windows OpenSSH Server installed on this machine - not its service, but sshd.exe started
# as this suite's own child on 127.0.0.1 with a test-only config, host key and authorized_keys under a
# temporary folder (transports/ssh/test/Sshd.ps1 says why). Through the real transport (Open, Send,
# Receive on transports/ssh): frames round-trip, a mebibyte included; the session runs the forced
# command and never the one the client asked for; a wrong host key and an unknown client key are each
# refused and read as unknown. With ssh.exe itself: an authorized_keys line whose expiry-time has
# passed is refused, and restrict refuses a port forward that the same key without it is allowed.
#
# THE MACHINE IS LEFT AS IT WAS, CHECKED, NOT ASSUMED. Measured at the start and compared at the end,
# each a checked line: the sshd service's state and start mode, the OpenSSH-Server-In-TCP firewall
# rule, how many sockets listen on port 22, C:\ProgramData\ssh (names, lengths and write times), and
# the user's ~/.ssh. A difference is a FAIL that says so loudly; nothing is put back silently.
#
# A HARD WALL-CLOCK LIMIT. The suite gives itself $limitSeconds; a watchdog process kills its sshd at
# that limit even if the suite hangs or dies, and every wait below is cut to what is left of it.
#
# WHEN THIS MACHINE CANNOT RUN IT. If sshd.exe is missing, refuses the config, or does not answer on
# its port, the suite prints [SKIP] with the reason and exits 3: never green. LOCAL ONLY (it is on the
# machine-bound list, test/lib/SuiteFiles.ps1): it needs this machine's OpenSSH Server and logon.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\Home.ps1")
. (Join-Path $root "transports\Port.ps1")
. (Join-Path $root "transports\ssh\Transport.ps1")
. (Join-Path $here "Sshd.ps1")

$limitSeconds = 120
$clock = [System.Diagnostics.Stopwatch]::StartNew()
function Left { param([int]$Ms) return [int][Math]::Max(1, [Math]::Min($Ms, ($limitSeconds * 1000) - $clock.ElapsedMilliseconds - 5000)) }
$t = Get-HordeTransport -Name "ssh"
$skipped = ""

# THE MACHINE BEFORE.
function Get-UserSshPrint { return (Get-HordeSshKeyFolderPrint -Path (Join-Path $env:USERPROFILE ".ssh")) }
$programData = Join-Path $env:ProgramData "ssh"
$p22 = Get-HordeListenerPrint -Port 22
$before = [pscustomobject]@{ service = (Get-HordeSshdServiceState); firewall = (Get-HordeSshdFirewallState); port22 = ($p22.lines -join " | "); programData = (Get-HordeSshFolderPrint -Path $programData); userSsh = (Get-UserSshPrint) }
Write-Host ("  at the start: sshd service " + $before.service + ", firewall rule enabled=" + $before.firewall + ", " + $p22.sockets + " socket(s) of " + $p22.processes + " process(es) listening on port 22") -ForegroundColor DarkGray
foreach ($l in $p22.lines) { Write-Host ("    " + $l) -ForegroundColor DarkGray }
$me = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$adminEnabled = ([System.Security.Principal.WindowsPrincipal]$me).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host ("  this token: Administrators " + $(if ($adminEnabled) { "enabled (elevated)" } else { "not enabled" })) -ForegroundColor DarkGray

$sshdRoot = ""
$sshd = $null
$savedHome = $env:HORDE_HOME
try {
    Write-Host ""
    Write-Host "--- the instruments: each print sees a planted change, and stale folders are swept ---" -ForegroundColor Cyan
    # The listener print, on a port this process holds on 127.0.0.1 and ::1: two sockets, one process,
    # each line naming this process.
    $l4 = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $l4.Start()
    $benchPort = $l4.LocalEndpoint.Port
    $l6 = $null
    try { $l6 = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::IPv6Loopback, $benchPort); $l6.Start() } catch { $l6 = $null }
    try {
        $lp = Get-HordeListenerPrint -Port $benchPort
        $wantSockets = 1; if ($null -ne $l6) { $wantSockets = 2 }
        Check ($lp.sockets -eq $wantSockets -and $lp.processes -eq 1) ("the listener print counts sockets and processes apart: " + $lp.sockets + " socket(s), " + $lp.processes + " process(es), on 127.0.0.1" + $(if ($null -ne $l6) { " and ::1" } else { " (::1 could not be bound here)" }))
        Check (@($lp.lines | Where-Object { $_.Contains(": pid " + $PID + " ") -and $_.Contains(", started 20") -and -not $_.Contains("(unreadable)") }).Count -eq $wantSockets) ("each line names the owning process, its start and its command line (" + ($lp.lines -join " | ") + ")")
    } finally { $l4.Stop(); if ($null -ne $l6) { $l6.Stop() } }
    Check ((Get-HordeListenerPrint -Port $benchPort).sockets -eq 0) "CONTROL: once closed, the print of that port is empty"
    # The machine-state comparisons below can only fail if the machine changes, so each print is shown
    # here to change when a folder does (review of PR #103, H4).
    $bench = Join-Path $env:TEMP ("horde-sshd-bench-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    New-Item -ItemType Directory -Path $bench | Out-Null
    try {
        [System.IO.File]::WriteAllText((Join-Path $bench "a"), "one")
        $f0 = Get-HordeSshFolderPrint -Path $bench; $k0 = Get-HordeSshKeyFolderPrint -Path $bench
        Check ($f0 -ceq (Get-HordeSshFolderPrint -Path $bench) -and $k0 -ceq (Get-HordeSshKeyFolderPrint -Path $bench)) "CONTROL: each print of an unchanged folder is the same twice"
        [System.IO.File]::WriteAllText((Join-Path $bench "b"), "new")
        Check ((Get-HordeSshFolderPrint -Path $bench) -cne $f0) "the folder print changes when a file is added"
        Check ((Get-HordeSshKeyFolderPrint -Path $bench) -cne $k0) "the key-folder print changes when a file is added"
        $k1 = Get-HordeSshKeyFolderPrint -Path $bench
        $a = Join-Path $bench "a"
        $was = (Get-Item -LiteralPath $a).LastWriteTimeUtc
        [System.IO.File]::WriteAllText($a, "two")
        [System.IO.File]::SetLastWriteTimeUtc($a, $was)
        Check ((Get-HordeSshKeyFolderPrint -Path $bench) -cne $k1) "the key-folder print changes when a file's bytes change, its length and write time kept"
    } finally { Remove-Item -LiteralPath $bench -Recurse -Force -ErrorAction SilentlyContinue }
    # H3: a dead run's folder is swept; a live one's, and anything not named like one, is not.
    $sweep = Join-Path $env:TEMP ("horde-sshd-sweep-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    $old = Join-Path $sweep "horde-sshd-0123456789ab"; $young = Join-Path $sweep "horde-sshd-ba9876543210"; $notOurs = Join-Path $sweep "horde-sshd-notours-old"
    foreach ($d in @($old, $young, $notOurs)) { New-Item -ItemType Directory -Path $d -Force | Out-Null; [System.IO.File]::WriteAllText((Join-Path $d "key"), "k") }
    foreach ($d in @($old, $notOurs)) { [System.IO.Directory]::SetCreationTimeUtc($d, [datetime]::UtcNow.AddHours(-1)) }
    try {
        $swept = @(Remove-HordeSshdStaleRoots -Dir $sweep -OlderThanSeconds ($limitSeconds * 2))
        Check (-not (Test-Path -LiteralPath $old) -and $swept.Count -eq 1 -and $swept[0] -ceq "horde-sshd-0123456789ab") ("a run's folder older than twice the limit is removed, and named (" + ($swept -join ", ") + ")")
        Check ((Test-Path -LiteralPath $young) -and (Test-Path -LiteralPath $notOurs)) "CONTROL: a younger run's folder, and an old folder not named like one, are kept"
    } finally { Remove-Item -LiteralPath $sweep -Recurse -Force -ErrorAction SilentlyContinue }
    $stale = @(Remove-HordeSshdStaleRoots -Dir $env:TEMP -OlderThanSeconds ($limitSeconds * 2))
    Check $true ("stale run folders under TEMP swept: " + $stale.Count + $(if ($stale.Count -gt 0) { " (" + ($stale -join ", ") + ")" } else { "" }))

    Write-Host ""
    Write-Host "--- a throwaway sshd: this suite's child, 127.0.0.1, everything under TEMP ---" -ForegroundColor Cyan
    if (-not (Test-Path -LiteralPath $script:HordeSshdExe -PathType Leaf)) { $skipped = "no sshd.exe at " + $script:HordeSshdExe }
    if ($skipped -eq "") {
        $sshdRoot = New-HordeSshdRoot
        $user = $me.Name.Split('\')[-1].ToLowerInvariant()
        if ($user -cnotmatch '\A[a-z_][a-z0-9_-]{0,31}\z') { $skipped = "this account's name '" + $user + "' is not one the ssh endpoint grammar takes" }
    }
    if ($skipped -eq "") {
        New-HordeSshdKey -Path (Join-Path $sshdRoot "host_ed25519")
        New-HordeSshdKey -Path (Join-Path $sshdRoot "client_ed25519")
        New-HordeSshdKey -Path (Join-Path $sshdRoot "stranger_ed25519")
        New-HordeSshdKey -Path (Join-Path $sshdRoot "other_host_ed25519")
        # The forced command: say who it is, then echo each line of stdin back as it arrives. It reads
        # stdin through $input: under Windows sshd a .NET Console stream ([Console]::In,
        # Console.OpenStandardInput) never returns the session's data, while $input reads it and
        # streams (measured 2026-10-06 on 9.5p1 here and 9.5p2 on the always-on box, issue #100). Pinned
        # by the mutant echo-reads-console-stdin (mutations/sshd-live.psd1): with the Console stream the
        # frame round trip fails (review of PR #103, H2, probe p8: it hangs).
        # LF only: the link's frames end at LF, and WriteLine would end them with CR LF.
        $echo = Join-Path $sshdRoot "echo.ps1"
        [System.IO.File]::WriteAllText($echo, "[Console]::Out.Write('horde-test-forced' + [char]10); [Console]::Out.Flush(); foreach (`$l in `$input) { [Console]::Out.Write(`$l + [char]10); [Console]::Out.Flush() }")
        $port = Get-HordeFreeLoopbackPort
        $config = Write-HordeSshdConfig -Root $sshdRoot -Port $port -ForceCommand ("powershell.exe -NoProfile -NonInteractive -File " + $echo.Replace('\', '/'))
        $clientPub = [System.IO.File]::ReadAllText((Join-Path $sshdRoot "client_ed25519.pub")).Trim()
        [System.IO.File]::WriteAllText((Join-Path $sshdRoot "authorized_keys"), ($clientPub + "`n"))
        $syntax = Test-HordeSshdConfig -Config $config
        Check ($syntax.ok) ("CONTROL: sshd -t accepts the test config (" + $syntax.text + ")")
        if (-not $syntax.ok) { $skipped = "sshd -t refused the test config: " + $syntax.text }
    }
    if ($skipped -eq "") {
        $sshd = Start-HordeTestSshd -Config $config -LimitSeconds $limitSeconds
        $endpoint = $user + "@127.0.0.1:" + $port + "/test-hub"
        $up = $null
        $deadline = [datetime]::UtcNow.AddMilliseconds((Left 20000))
        while ([datetime]::UtcNow -lt $deadline -and -not $sshd.process.HasExited) {
            $up = Test-HordeTransportReachable -Transport $t -Endpoint $endpoint
            if ($up.state -ceq "known" -and $up.value -eq $true) { break }
            Start-Sleep -Milliseconds 250
        }
        if ($null -eq $up -or $up.state -cne "known" -or $up.value -ne $true) { $skipped = "the test sshd did not answer on 127.0.0.1:" + $port + " (" + "$($up.reason)" + "); its log: " + ((Stop-HordeTestSshd -Sshd $sshd) -replace "`r?`n", " | ") }
        else {
            Check $true ("the test sshd answers with an SSH banner on 127.0.0.1:" + $port + ", started from a token with Administrators " + $(if ($adminEnabled) { "enabled" } else { "not enabled" }))
            Check ([System.IO.Path]::IsPathRooted($sshd.watchdogExe) -and $sshd.watchdogExe -ieq (Join-Path ([System.Environment]::SystemDirectory) "WindowsPowerShell\v1.0\powershell.exe")) ("its watchdog is System32's powershell.exe by full path, never a PATH lookup (" + $sshd.watchdogExe + ")")
            Check ((Get-HordeListenerCount -Port $port) -ge 1 -and @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue | Where-Object { $_.LocalAddress -ne "127.0.0.1" }).Count -eq 0) "and listens on 127.0.0.1 only"
        }
    }

    if ($skipped -eq "") {
        # Horde's own files for the node's half (transports/ssh/Argv.ps1): the link key, the hub's host
        # key pinned under its alias, and an ssh_config with no directive.
        $hh = Join-Path $sshdRoot "home"
        $node = Join-Path $hh "node"
        New-Item -ItemType Directory -Path $node | Out-Null
        Copy-Item -LiteralPath (Join-Path $sshdRoot "client_ed25519") -Destination (Join-Path $node "link_ed25519")
        [System.IO.File]::WriteAllText((Join-Path $node "ssh_config"), "# Horde's argv is the whole configuration`n")
        $hostPub = [System.IO.File]::ReadAllText((Join-Path $sshdRoot "host_ed25519.pub")).Trim().Split(' ')
        $pin = { param([string]$Pub) [System.IO.File]::WriteAllText((Join-Path $node "known_hosts"), ("horde-hub-test-hub " + $Pub + "`n")) }
        & $pin ($hostPub[0] + " " + $hostPub[1])
        $env:HORDE_HOME = $hh

        # THROUGH THE PORT: dial.out and auth.peer are yes since R17c-3 (shown live by
        # test/test-transport-conformance.ps1 against transports/ssh/test/FarEnd.ps1), so this suite
        # asks the port for its links as every caller does.
        function Open-Link {
            $o = Open-HordeTransportLink -Transport $t -Endpoint $endpoint -Role "node" -TimeoutMs (Left 15000)
            if ($o.state -cne "known") { Write-Host ("         no link: " + $o.reason) -ForegroundColor DarkYellow; return $null }
            return $o.value
        }

        Write-Host ""
        Write-Host "--- through the transport: the forced command, frames both ways ---" -ForegroundColor Cyan
        $link = Open-Link
        try {
            $first = $null; if ($null -ne $link) { $first = Receive-HordeLinkFrame -Link $link -TimeoutMs (Left 20000) }
            Check ($null -ne $first -and $first.state -ceq "known" -and "$($first.value)" -ceq "horde-test-forced") ("the session runs the forced command, not the 'attach' the transport asked for (" + "$($first.value)$($first.reason)" + ")")
            $live = Get-HordeTestSshdLive -Sshd $sshd
            Check ($live -ge 3) ("CONTROL: with a session open, the sshd's job holds sshd, its watchdog and the session's processes (" + $live + ")")
            $frame = '{"hello":"hub"}'
            $back = $null
            if ($null -ne $link) { $null = Send-HordeLinkFrame -Link $link -Frame $frame; $back = Receive-HordeLinkFrame -Link $link -TimeoutMs (Left 20000) }
            Check ($null -ne $back -and $back.state -ceq "known" -and "$($back.value)" -ceq $frame) "a frame sent through sshd comes back as itself"
            $big = "x" * 1048576
            $bigBack = $null
            if ($null -ne $link) { $null = Send-HordeLinkFrame -Link $link -Frame $big; $bigBack = Receive-HordeLinkFrame -Link $link -TimeoutMs (Left 30000) }
            Check ($null -ne $bigBack -and $bigBack.state -ceq "known" -and "$($bigBack.value)".Length -eq 1048576) ("a mebibyte frame round-trips whole (" + "$($bigBack.value)".Length + " bytes back)")
        } finally { if ($null -ne $link) { Close-HordeLink -Link $link } }

        Write-Host ""
        Write-Host "--- refusals: a wrong host key, an unknown client key ---" -ForegroundColor Cyan
        $otherPub = [System.IO.File]::ReadAllText((Join-Path $sshdRoot "other_host_ed25519.pub")).Trim().Split(' ')
        & $pin ($otherPub[0] + " " + $otherPub[1])
        $link = Open-Link
        try {
            $r = $null; if ($null -ne $link) { $r = Receive-HordeLinkFrame -Link $link -TimeoutMs (Left 20000) }
            Check ($null -ne $r -and $r.state -ceq "unknown" -and "$($r.reason)" -match "(?i)host key|identification") ("a hub whose host key is not the pinned one is refused, unknown, saying why (" + "$($r.reason)" + ")")
        } finally { if ($null -ne $link) { Close-HordeLink -Link $link } }
        & $pin ($hostPub[0] + " " + $hostPub[1])
        Copy-Item -LiteralPath (Join-Path $sshdRoot "stranger_ed25519") -Destination (Join-Path $node "link_ed25519") -Force
        $link = Open-Link
        try {
            $r = $null; if ($null -ne $link) { $r = Receive-HordeLinkFrame -Link $link -TimeoutMs (Left 20000) }
            Check ($null -ne $r -and $r.state -ceq "unknown" -and "$($r.reason)" -match "(?i)permission denied") ("a node key the hub does not know is refused, unknown, saying why (" + "$($r.reason)" + ")")
        } finally { if ($null -ne $link) { Close-HordeLink -Link $link } }
        Copy-Item -LiteralPath (Join-Path $sshdRoot "client_ed25519") -Destination (Join-Path $node "link_ed25519") -Force
        $link = Open-Link
        try {
            $r = $null; if ($null -ne $link) { $r = Receive-HordeLinkFrame -Link $link -TimeoutMs (Left 20000) }
            Check ($null -ne $r -and $r.state -ceq "known" -and "$($r.value)" -ceq "horde-test-forced") "CONTROL: with the right host key and the right node key again, the link opens"
        } finally { if ($null -ne $link) { Close-HordeLink -Link $link } }

        Write-Host ""
        Write-Host "--- authorized_keys options, with ssh.exe itself ---" -ForegroundColor Cyan
        # Raw ssh.exe here, not the transport: the options under test are the server's, and the
        # transport's own argv clears every forwarding before a server could refuse one.
        function Invoke-Ssh {
            param([string[]]$Extra)
            $argv = @("-F", "none", "-T", "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes", "-o", "IdentityAgent=none", "-o", ('IdentityFile="' + (Join-Path $sshdRoot "client_ed25519") + '"'), "-o", ('UserKnownHostsFile="' + (Join-Path $node "known_hosts") + '"'), "-o", "GlobalKnownHostsFile=none", "-o", "StrictHostKeyChecking=yes", "-o", "HostKeyAlias=horde-hub-test-hub", "-o", "ConnectTimeout=10", "-p", "$port") + @($Extra) + @(($user + "@127.0.0.1"), "requested")
            $psi = New-Object System.Diagnostics.ProcessStartInfo((Resolve-HordeSshExe).path, (Join-HordeSshCommandLine -Argv $argv))
            $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
            $p = [System.Diagnostics.Process]::Start($psi)
            $p.StandardInput.Close()
            $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
            if (-not $p.WaitForExit((Left 20000))) { try { $p.Kill() } catch { }; return [pscustomobject]@{ code = -1; out = ""; err = "timed out" } }
            $p.WaitForExit()
            return [pscustomobject]@{ code = $p.ExitCode; out = ("" + $o.Result).Trim(); err = ("" + $e.Result).Trim() }
        }
        $ak = Join-Path $sshdRoot "authorized_keys"
        $plain = Invoke-Ssh @()
        Check ($plain.code -eq 0 -and $plain.out -ceq "horde-test-forced") ("CONTROL: the plain key opens a session that runs the forced command, not 'requested' (exit " + $plain.code + ", " + $plain.out + $plain.err + ")")
        # One way of writing the option for both dates: a malformed option is refused with the same
        # "Permission denied (publickey)" as an expired one (review of PR #103, H1, probe p4), so only a
        # date to come, accepted, shows the refusal is the date's.
        $expiryOption = { param([string]$Day) return ('expiry-time="' + $Day + '" ') }
        [System.IO.File]::WriteAllText($ak, ((& $expiryOption "20200101") + $clientPub + "`n"))
        $expired = Invoke-Ssh @()
        Check ($expired.code -eq 255 -and $expired.err -match "(?i)permission denied") ("a key whose expiry-time has passed is refused (exit " + $expired.code + ", " + $expired.err + ")")
        [System.IO.File]::WriteAllText($ak, ((& $expiryOption "20991231") + $clientPub + "`n"))
        $future = Invoke-Ssh @()
        Check ($future.code -eq 0 -and $future.out -ceq "horde-test-forced") ("CONTROL: the same option with a date still to come is accepted, so the refusal is the date's and not the option's form (exit " + $future.code + ", " + $future.out + $future.err + ")")
        $fwdPort = Get-HordeFreeLoopbackPort
        # No -N: the forced command ends when its stdin closes, so a session whose forward was allowed
        # ends by itself, and one whose forward was refused ends first, ExitOnForwardFailure exit 255.
        $remoteForward = @("-o", "ExitOnForwardFailure=yes", "-R", ("127.0.0.1:" + $fwdPort + ":127.0.0.1:" + $port))
        [System.IO.File]::WriteAllText($ak, ('restrict ' + $clientPub + "`n"))
        $restricted = Invoke-Ssh $remoteForward
        Check ($restricted.code -eq 255 -and $restricted.err -match "(?i)forward") ("restrict refuses a remote port forward (exit " + $restricted.code + ", " + $restricted.err + ")")
        [System.IO.File]::WriteAllText($ak, ($clientPub + "`n"))
        $open = Invoke-Ssh $remoteForward
        Check ($open.code -eq 0 -and $open.out -ceq "horde-test-forced") ("CONTROL: the same forward from the same key without restrict is allowed, and the session runs (exit " + $open.code + ", " + $open.out + $open.err + ")")
    }
} finally {
    $env:HORDE_HOME = $savedHome
    Write-Host ""
    Write-Host "--- the machine is left as it was ---" -ForegroundColor Cyan
    if ($null -ne $sshd) {
        $sshdLog = Stop-HordeTestSshd -Sshd $sshd
        Check (Test-HordeTestSshdGone -Sshd $sshd) "the test sshd is gone, by its own pid and start time"
        Check ($sshd.watchdog.HasExited) "and so is its watchdog"
        $left = Get-HordeTestSshdLeft -Sshd $sshd
        Check ($left -eq 0) ("no process the sshd, its watchdog or any session started is left alive: its job is empty (" + $left + " left)")
        Close-HordeTestSshd -Sshd $sshd
        Check ((Get-HordeListenerCount -Port $port) -eq 0) ("nothing listens on the test port " + $port + " any more")
    }
    if ($sshdRoot -ne "" -and (Split-Path -Leaf $sshdRoot) -match '^horde-sshd-[0-9a-f]{12}$') { Remove-Item -LiteralPath $sshdRoot -Recurse -Force -ErrorAction SilentlyContinue }
    Check ($sshdRoot -eq "" -or -not (Test-Path -LiteralPath $sshdRoot)) "the test's keys, config and authorized_keys are removed"
    $p22After = Get-HordeListenerPrint -Port 22
    $after = [pscustomobject]@{ service = (Get-HordeSshdServiceState); firewall = (Get-HordeSshdFirewallState); port22 = ($p22After.lines -join " | "); programData = (Get-HordeSshFolderPrint -Path $programData); userSsh = (Get-UserSshPrint) }
    Write-Host ("  at the end: " + $p22After.sockets + " socket(s) of " + $p22After.processes + " process(es) listening on port 22") -ForegroundColor DarkGray
    foreach ($l in $p22After.lines) { Write-Host ("    " + $l) -ForegroundColor DarkGray }
    foreach ($k in @("service", "firewall", "port22")) {
        $same = ("$($after.$k)" -ceq "$($before.$k)")
        if (-not $same) { Write-Host ("  !!! THE MACHINE CHANGED: " + $k + " was '" + $before.$k + "' at the start and is '" + $after.$k + "' now. Nothing was put back; look at it.") -ForegroundColor Red }
        Check $same ("the " + $k + " is as it was at the start: " + $after.$k)
    }
    Check ($after.programData -ceq $before.programData) "C:\ProgramData\ssh is as it was: no file added, removed or rewritten"
    Check ($after.userSsh -ceq $before.userSsh) "the user's ~/.ssh is byte for byte as it was"
    Check ($clock.Elapsed.TotalSeconds -lt $limitSeconds) ("the suite finished inside its " + $limitSeconds + " s limit (" + [int]$clock.Elapsed.TotalSeconds + " s)")
}

$banner = "the ssh transport holds against a real Windows sshd, and the machine's sshd is left as it was"
$passCode = 0
if ($skipped -ne "") {
    Write-Host ("  [SKIP] " + $skipped) -ForegroundColor Yellow
    $banner = "LIVE CASES SKIPPED (" + $skipped + "), EXIT 3: " + $banner
    $passCode = 3
}
Complete-HordeSuite -Success $banner -PassCode $passCode
