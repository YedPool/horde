# DOES THE SSH TRANSPORT DIAL OUT EXACTLY AS DATA SAYS, AND NEVER AS THE USER'S CONFIG SAYS?
#
# Remote plan step R5, the node's half: the node dials the hub with the System32 ssh.exe, whose argv
# is built from data and never from a user's config (remote design 2.4). The hub's half - sshd with a
# forced command, run while `horde listen` runs, and the enrolled per-device keys - is steps R16 and
# R17, and is not built here. So is every case that needs a live sshd: this machine has no WSL user an
# unprivileged throwaway sshd could run as (measured 2026-10-02; the coordinator chose to defer those
# cases). What this suite proves without one:
#   - the endpoint grammar, and argv built from it, option by option, with nothing a caller can inject;
#   - ssh.exe itself, asked with -G, reports the configuration Horde meant: only Horde's identity, only
#     Horde's known_hosts, no global known_hosts, no agent, no multiplexing, no forwarding, no pty; and
#     the control - the same question without Horde's options - shows the user's ~/.ssh, so the check
#     can see the hazard it guards against;
#   - Open refuses to start when Horde's key, known_hosts or config is missing or the config holds a
#     directive: with no key file ssh.exe silently offers the user's own ~/.ssh keys (measured);
#   - ssh.exe is found by its System32 path, never through PATH, where another copy can win;
#   - the byte channel over a child's stdio, with stand-in children: frames round-trip, a mebibyte
#     included; exit 255 is unknown with stderr's first line as the reason; stderr never reaches the
#     frame reader; a real ssh.exe dialling a closed port is exit 255, mapped;
#   - Probe reads an SSH banner over TCP and opens no session;
#   - this file's own process starts are the only ones: the adapter starts exactly one program, at one
#     call site (until tools/ExecScan.ps1 gains a transports/ policy, Horde #53);
#   - the user's ~/.ssh is byte-for-byte the same after the suite as before it.
# Every temp file lives under one folder this suite makes and removes; every child it starts it
# holds and kills itself (CONTRIBUTING 9).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "transports\Port.ps1")
. (Join-Path $root "transports\ssh\Transport.ps1")
. (Join-Path $here "ExecGuard.ps1")

function Ord { param([string]$A, [string]$B) return [string]::Equals($A, $B, [System.StringComparison]::Ordinal) }
function Start-TestProcess {
    # The suite's own starter, for stand-in children and ssh-keygen: the adapter's Start-HordeSshProcess
    # starts the System32 ssh.exe and nothing else (review of PR #68, round 2, F4).
    param([string]$FilePath, [string]$Arguments)
    $tsi = New-Object System.Diagnostics.ProcessStartInfo -ArgumentList @($FilePath, $Arguments)
    $tsi.UseShellExecute = $false; $tsi.CreateNoWindow = $true
    $tsi.RedirectStandardInput = $true; $tsi.RedirectStandardOutput = $true; $tsi.RedirectStandardError = $true
    return [System.Diagnostics.Process]::Start($tsi)
}

# THE USER'S ~/.ssh, measured before anything runs and compared at the end.
function Get-SshDirPrint {
    $d = Join-Path $env:USERPROFILE ".ssh"
    if (-not (Test-Path -LiteralPath $d -PathType Container)) { return "(no ~/.ssh)" }
    $lines = foreach ($f in @(Get-ChildItem -LiteralPath $d -Recurse -File -Force | Sort-Object FullName)) {
        $h = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
        $f.FullName.Substring($d.Length) + " " + $f.Length + " " + $h
    }
    return ($lines -join "`n")
}
$sshDirBefore = Get-SshDirPrint

$tmp = Join-Path $env:TEMP ("horde-ssh-test-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
$children = New-Object System.Collections.ArrayList
$savedHome = $env:HORDE_HOME
try {
    New-Item -ItemType Directory -Path $tmp | Out-Null

    Write-Host ""
    Write-Host "--- the endpoint: user@host:port/hubId, and nothing that could become an option ---" -ForegroundColor Cyan
    $ok = ConvertFrom-HordeSshEndpoint -Endpoint "horde-link@hub.example.net:2222/hub-01"
    Check ($ok.ok -and (Ord $ok.user "horde-link") -and (Ord $ok.host "hub.example.net") -and $ok.port -eq 2222 -and (Ord $ok.hubId "hub-01")) "a well-formed endpoint is read into user, host, port and hub id"
    Check ((ConvertFrom-HordeSshEndpoint -Endpoint "horde-link@127.0.0.1:22/a").ok) "an IPv4 address is a host"
    foreach ($bad in @("..\x", "a b", "A", "", "horde-link@hub:22", "horde-link@hub/abc", "hub:22/abc", "-oProxyCommand=calc@hub:22/a",
                       "horde-link@-oProxyCommand=calc:22/a", "horde-link@hub:0/a", "horde-link@hub:65536/a", "horde-link@hub:22/A",
                       "horde-link@hub:22/a b", "horde-link@hub;calc:22/a", "Horde@hub:22/a", "-x@hub:22/a", "horde-link@-oproxy:22/a", ("horde-link@hub:22/" + ("a" * 64)))) {
        Check (-not (ConvertFrom-HordeSshEndpoint -Endpoint $bad).ok) ("the endpoint '" + $bad + "' is refused")
    }

    Write-Host ""
    Write-Host "--- argv, built from data: design 2.4, option by option ---" -ForegroundColor Cyan
    $paths = Get-HordeSshPaths -HordeHome "C:\h h"
    Check ((Ord $paths.identity "C:\h h\node\link_ed25519") -and (Ord $paths.knownHosts "C:\h h\node\known_hosts") -and (Ord $paths.config "C:\h h\node\ssh_config")) "Horde's key, known_hosts and config live under <HordeHome>\node"
    $argv = @(Get-HordeSshArgv -Endpoint $ok -Paths $paths)
    # -o IdentityFile, never -i (review of PR #68, F1): measured 2026-10-02, a -i file that is gone when
    # ssh starts adds nothing, and ssh then offers the user's default ~/.ssh keys; -o IdentityFile adds
    # the path without looking at it, so a vanished key is a failed login and never the user's key.
    $want = @("-F", "C:\h h\node\ssh_config", "-T",
        "-o", 'IdentityFile="C:\h h\node\link_ed25519"', "-o", "IdentitiesOnly=yes", "-o", "IdentityAgent=none",
        "-o", 'UserKnownHostsFile="C:\h h\node\known_hosts"', "-o", "GlobalKnownHostsFile=none", "-o", "KnownHostsCommand=none",
        "-o", "StrictHostKeyChecking=yes", "-o", "HostKeyAlias=horde-hub-hub-01", "-o", "UpdateHostKeys=no", "-o", "CheckHostIP=no",
        "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=4",
        "-o", "ControlMaster=no", "-o", "ControlPath=none", "-o", "ProxyCommand=none", "-o", "ProxyJump=none",
        "-o", "ForwardAgent=no", "-o", "ForwardX11=no", "-o", "ForwardX11Trusted=no", "-o", "ClearAllForwardings=yes", "-o", "GatewayPorts=no", "-o", "Tunnel=no",
        "-o", "PermitLocalCommand=no", "-o", "LocalCommand=none", "-o", "RemoteCommand=none", "-o", "RequestTTY=no",
        "-o", "PKCS11Provider=none", "-o", "SecurityKeyProvider=internal", "-o", "LogLevel=INFO",
        "-p", "2222", "horde-link@hub.example.net", "attach")
    Check ((@($argv) -join "|") -ceq ($want -join "|")) "argv is exactly the design's list, in order, from the endpoint and Horde's own paths"
    if ((@($argv) -join "|") -cne ($want -join "|")) { Write-Host ("         got: " + (@($argv) -join " ")) -ForegroundColor Red }
    # MESH V1: A NODE DIALS THE HUB'S LAN ADDRESS AND PORT, AND THE PIN STILL HOLDS (node serve -Dial;
    # the hub's listener on the office LAN, horde listen -Address). The address and port are only where to
    # dial; the host key is checked against the pin of the hub's identity, never against the address.
    $lanHub = "7c9e6679-7425-40de-944b-e07fc1f90ae7"
    $lanEp = ConvertFrom-HordeSshEndpoint -Endpoint ("someone@192.168.1.182:2222/" + $lanHub)
    Check ($lanEp.ok -and (Ord $lanEp.host "192.168.1.182") -and $lanEp.port -eq 2222 -and (Ord $lanEp.hubId $lanHub)) "a node takes the hub's LAN address and port, and the hub's device id as its identity"
    $lanArgv = @(Get-HordeSshArgv -Endpoint $lanEp -Paths $paths)
    $lanJoined = (@($lanArgv) -join "|")
    Check ($lanJoined.Contains("|-p|2222|someone@192.168.1.182|attach") -and $lanArgv.Count -eq $want.Count) "argv dials that address and port, and nothing else changes"
    Check ($lanJoined.Contains("|StrictHostKeyChecking=yes|") -and $lanJoined.Contains("|HostKeyAlias=horde-hub-" + $lanHub + "|") -and $lanJoined.Contains('|UserKnownHostsFile="C:\h h\node\known_hosts"|') -and $lanJoined.Contains("|GlobalKnownHostsFile=none|") -and $lanJoined.Contains("|UpdateHostKeys=no|") -and $lanJoined.Contains("|CheckHostIP=no|")) "and the host key is still pinned to the hub's identity, in Horde's known_hosts only, never learned from the address"
    foreach ($bad in @(("someone@192.168.1.182/" + $lanHub), ("someone@192.168.1.182:2222"), ("someone@[fd00::1]:2222/" + $lanHub), ("someone@192.168.1.182:22222222/" + $lanHub))) {
        Check (-not (ConvertFrom-HordeSshEndpoint -Endpoint $bad).ok) ("the LAN endpoint '" + $bad + "' is refused: an address, a port and the hub's identity, each required")
    }
    Check (@($argv | Where-Object { $_ -like "*%*" -or $_ -like "*$*" }).Count -eq 0) "no argument holds a % or $ for anything to expand"
    # PATHS SSH WOULD READ AS SOMETHING ELSE (review of PR #68, F2): inside a -o value ssh expands %d,
    # %h and ${VAR}, cuts at #, and fails on a quote (measured with ssh -G, two review rounds). After the
    # third surprise the rule is an ALLOWLIST: a path holds only letters, digits, space and \ / : . _ -
    # and every other character is refused, the ones not yet known to matter included.
    foreach ($bad in @("C:\x%d\h", "C:\x%h", "C:\a #b", "C:\o'brien", 'C:\q"q', ("C:\t" + [char]9 + "t"), ("C:\caf" + [char]0xE9), ("C:\n" + [char]10 + "l"),
                       'C:\d${HOME}', 'C:\d$HOME', 'C:\x~y', 'C:\p(x86)', 'C:\a;b', 'C:\a=b', 'C:\a,b', 'C:\a!b', 'C:\a@b', 'C:\a&b', 'C:\a[b]', 'C:\a+b', 'C:\a`b',
                       '\\server\share\h', '//server/share/h', 'C:\a\\b', 'C:/a//b', 'relative\h', 'C:h', '\h')) {
        Check ((Test-HordeSshSafePath -Path $bad) -ne "") ("the path '" + ($bad -replace '[^\x20-\x7E]', '?') + "' is refused for ssh's argv")
        Check (Throws { $null = Get-HordeSshArgv -Endpoint $ok -Paths (Get-HordeSshPaths -HordeHome $bad) } "ssh would") ("and argv is not built under a Horde home of '" + ($bad -replace '[^\x20-\x7E]', '?') + "'")
    }
    Check ((Test-HordeSshSafePath -Path "C:\ends\") -ne "") "a path ending in a backslash is refused: it would escape the quote argv puts around it"
    # LOCAL AND ABSOLUTE ONLY (review of PR #68, round 3): ssh collapses a doubled backslash inside the
    # quotes, so \\host\share\x is read as \host\share\x on the current drive, a folder any local user may
    # create. Horde's own paths are local, so a path starts with a drive letter and never doubles a
    # separator.
    Check ((Test-HordeSshSafePath -Path "C:/Users/Jo Smith/.horde") -eq "") "a drive-absolute path with forward slashes is accepted"
    # ARGV CHECKS THE ENDPOINT IT IS GIVEN (review of PR #68, round 3, LOW): data in, argv out - but a
    # forged endpoint object that says ok is re-read field by field, never trusted.
    $forged = [pscustomobject]@{ ok = $true; user = "-oIdentityFile=~/.ssh/id_ed25519"; host = "127.0.0.1"; port = 22; hubId = "h"; reason = "" }
    Check (Throws { $null = Get-HordeSshArgv -Endpoint $forged -Paths $paths } "not a lowercase account") "argv refuses a forged endpoint object whose user would be an ssh option"
    $forged.user = "horde-link"; $forged.host = "-oProxyCommand=calc"
    Check (Throws { $null = Get-HordeSshArgv -Endpoint $forged -Paths $paths } "not a DNS name") "and one whose host would be an ssh option"
    Check ((Test-HordeSshSafePath -Path "C:\Users\Jo Smith\x-y_z\.horde") -eq "") "a path of letters, digits, spaces, dots, hyphens and underscores is accepted: ssh reads those as written (measured)"

    Write-Host ""
    Write-Host "--- the command line ssh.exe receives is the argv, one argument each ---" -ForegroundColor Cyan
    $cases = @("plain", "two words", "C:\h h\node\known_hosts", 'trailing\', 'with space\', 'two\\ ends\\', 'a"b', "", 'x\\"y')
    Check ((Join-HordeSshCommandLine -Argv @("a", "b c")) -ceq 'a "b c"') "a plain argument is passed as it is, and one with a space is quoted"
    $echo = Join-Path $tmp "args.ps1"
    [System.IO.File]::WriteAllText($echo, '$args | ForEach-Object { [Console]::Out.WriteLine("<" + $_ + ">") }' + "`r`n")
    $psExe = [System.IO.Path]::Combine([System.Environment]::SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe")
    $p = Start-TestProcess -FilePath $psExe -Arguments ("-NoProfile -NonInteractive -File " + (Join-HordeSshCommandLine -Argv (@($echo) + $cases)))
    [void]$children.Add($p)
    $outText = $p.StandardOutput.ReadToEnd()
    $null = $p.WaitForExit(30000)
    $gotArgs = @(($outText -split "`r?`n") | Where-Object { $_ -ne "" })
    Check (($gotArgs -join "|") -ceq ((@($cases) | ForEach-Object { "<" + $_ + ">" }) -join "|")) "spaces, quotes, trailing backslashes and an empty argument each arrive as one argument, unchanged"
    if (($gotArgs -join "|") -cne ((@($cases) | ForEach-Object { "<" + $_ + ">" }) -join "|")) { Write-Host ("         got: " + ($gotArgs -join " | ")) -ForegroundColor Red }

    Write-Host ""
    Write-Host "--- ssh.exe is the System32 copy, never one found through PATH ---" -ForegroundColor Cyan
    # The System32 ssh.exe, named as the adapter names it: from the system directory .NET reports, with
    # no command and no environment variable involved (review of PR #68, round 3).
    $sys = [System.IO.Path]::Combine([System.Environment]::SystemDirectory, "OpenSSH", "ssh.exe")
    $fakeBin = Join-Path $tmp "bin"
    New-Item -ItemType Directory -Path $fakeBin | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $fakeBin "ssh.exe"), "not a program")
    $savedPath = $env:PATH
    try {
        $env:PATH = $fakeBin + ";" + $env:PATH
        $r = Resolve-HordeSshExe
    } finally { $env:PATH = $savedPath }
    if (Test-Path -LiteralPath $sys -PathType Leaf) {
        Check ($r.ok -and (Ord $r.path $sys)) "with another ssh.exe first on PATH, the System32 copy is the one used"
    } else {
        Check (-not $r.ok -and "$($r.reason)" -like "*System32*") "with no System32 copy, there is no ssh.exe, whatever PATH holds"
    }
    $haveSsh = $r.ok

    Write-Host ""
    Write-Host "--- Open refuses to start without Horde's own key, known_hosts and empty config ---" -ForegroundColor Cyan
    $hh = Join-Path $tmp "home"
    $node = Join-Path $hh "node"
    New-Item -ItemType Directory -Path $node | Out-Null
    $env:HORDE_HOME = $hh
    $t = Get-HordeTransport -Name "ssh"
    $ep = "horde-link@127.0.0.1:1/test-hub"
    # An Open that throws is a refusal too, but not the one these cases want: the reason must be the
    # adapter's own sentence, so a mutant that lets a missing file through and then fails reading it
    # is caught, not excused by an exception message that happens to name the same file.
    function Open-Raw { param([string]$E) try { return (& $t.open $E 2000) } catch { return [pscustomobject]@{ ok = $false; reason = ("threw: " + $_.Exception.Message) } } }
    $o = Open-Raw $ep
    Check (-not $o.ok -and "$($o.reason)" -like "*link_ed25519 does not exist*") "with no key file, Open refuses - ssh.exe would otherwise offer the user's own ~/.ssh keys"
    if ($haveSsh) {
        $kg = Start-TestProcess -FilePath (Join-Path $env:SystemRoot "System32\OpenSSH\ssh-keygen.exe") -Arguments (Join-HordeSshCommandLine -Argv @("-q", "-t", "ed25519", "-N", "", "-C", "horde-test", "-f", (Join-Path $node "link_ed25519")))
        [void]$children.Add($kg)
        $null = $kg.WaitForExit(30000)
    } else {
        [System.IO.File]::WriteAllText((Join-Path $node "link_ed25519"), "not a key")
    }
    $o = Open-Raw $ep
    Check (-not $o.ok -and "$($o.reason)" -like "*known_hosts*does not exist*pinned*") "with no known_hosts, Open refuses - a host key must already be pinned"
    [System.IO.File]::WriteAllText((Join-Path $node "known_hosts"), "")
    $o = Open-Raw $ep
    Check (-not $o.ok -and "$($o.reason)" -like "*ssh_config*does not exist*-F file*") ("with no config file, Open refuses (" + $o.reason + ")")
    [System.IO.File]::WriteAllText((Join-Path $node "ssh_config"), "# Horde's own, empty`r`n`r`nProxyCommand calc.exe`r`n")
    $o = Open-Raw $ep
    Check (-not $o.ok -and "$($o.reason)" -like "*holds a directive on line 3*") "a config file holding any directive is refused - Horde's argv is the whole configuration"
    [System.IO.File]::WriteAllText((Join-Path $node "ssh_config"), "# Horde's own ssh_config: empty on purpose`r`n`r`n")
    $env:HORDE_HOME = Join-Path $tmp "pct%d"
    $o = Open-Raw $ep
    Check (-not $o.ok -and "$($o.reason)" -like "*ssh would*%*") ("a Horde home ssh would read differently is refused before anything starts (" + $o.reason + ")")
    $env:HORDE_HOME = Join-Path $tmp 'd${HOME}'
    $o = Open-Raw $ep
    Check (-not $o.ok -and "$($o.reason)" -like "*ssh would*") ("a Horde home holding `${HOME}, which ssh would expand, is refused (" + $o.reason + ")")
    $env:HORDE_HOME = $hh
    $o = Open-Raw "not an endpoint"
    Check (-not $o.ok -and "$($o.reason)" -like "*endpoint*") "a malformed endpoint is refused before anything starts"

    if ($haveSsh) {
        Write-Host ""
        Write-Host "--- ssh.exe -G: what ssh itself says the configuration is ---" -ForegroundColor Cyan
        $paths = Get-HordeSshPaths -HordeHome $hh
        $parsed = ConvertFrom-HordeSshEndpoint -Endpoint $ep
        $gArgv = @("-G") + @(Get-HordeSshArgv -Endpoint $parsed -Paths $paths)
        # The adapter's starter puts every ssh.exe in a kill-on-close job; these -G runs get one each.
        $gJobs = New-Object System.Collections.ArrayList
        function New-GJob { $j = [HordeSshNative]::NewKillOnCloseJob(); [void]$gJobs.Add($j); return $j }
        # This process holds the fd-state variable Windows sshd gives a session's command, as a node started
        # over ssh does (Transport.ps1, $script:HordeSshInheritedFdState), and a decoy whose prefix is not
        # 32 hex digits; ssh.exe is started without the first and with the second.
        $fdState = "c28fc6f98a2c44abbbd89d6a3037d0d9_POSIX_FD_STATE"
        $fdDecoy = "horde-test-not-hex_POSIX_FD_STATE"
        [System.Environment]::SetEnvironmentVariable($fdState, "AAAAAAICAjU=")
        [System.Environment]::SetEnvironmentVariable($fdDecoy, "kept")
        try { $g = Start-HordeSshProcess -Arguments (Join-HordeSshCommandLine -Argv $gArgv) -Job (New-GJob) }
        finally { [System.Environment]::SetEnvironmentVariable($fdState, $null); [System.Environment]::SetEnvironmentVariable($fdDecoy, $null) }
        [void]$children.Add($g)
        Check (-not $g.StartInfo.EnvironmentVariables.ContainsKey($fdState)) "ssh.exe is started without the POSIX_FD_STATE variable an ssh session handed this process: it describes this process's handles, not ssh.exe's (the first live mesh link)"
        Check ($g.StartInfo.EnvironmentVariables[$fdDecoy] -ceq "kept") "CONTROL: a variable that only ends the same way, without the 32-hex-digit prefix, is passed on"
        $gOut = $g.StandardOutput.ReadToEnd()
        $null = $g.WaitForExit(30000)
        $cfg = @{}
        foreach ($line in ($gOut -split "`r?`n")) {
            if ($line -match '^(\S+) (.*)$') {
                $k = $Matches[1].ToLowerInvariant()
                if (-not $cfg.ContainsKey($k)) { $cfg[$k] = New-Object System.Collections.ArrayList }
                [void]$cfg[$k].Add($Matches[2])
            }
        }
        function One { param([string]$Key) if (-not $cfg.ContainsKey($Key)) { return "<absent>" }; return (@($cfg[$Key]) -join " ; ") }
        Check ($g.ExitCode -eq 0 -and $cfg.Count -gt 10) ("ssh.exe -G answered with the configuration (" + $cfg.Count + " keys)")
        Check ((One "identityfile") -ceq $paths.identity) ("the only identity offered is Horde's key, byte for byte (" + (One "identityfile") + ")")
        Check ((One "userknownhostsfile") -ceq $paths.knownHosts) ("the only known_hosts read is Horde's, byte for byte the path Open checked (" + (One "userknownhostsfile") + ")")
        Check ((One "globalknownhostsfile") -ceq "none") "no global known_hosts is read"
        Check ((One "identityagent") -ceq "none") "no agent is asked for keys"
        Check ((One "identitiesonly") -ceq "yes") "only the given identity is tried"
        Check ((One "stricthostkeychecking") -ceq "true") "an unknown or changed host key refuses the connection"
        Check ((One "hostkeyalias") -ceq "horde-hub-test-hub") "the host key is pinned by the hub's identity, not its address"
        Check ((One "batchmode") -ceq "yes") "ssh never prompts"
        # ControlPath=none prints no controlpath line at all (measured 2026-10-02): absent is none.
        Check ((One "controlmaster") -ceq "false" -and @("none", "<absent>") -ccontains (One "controlpath")) ("no connection is shared with another ssh (controlmaster " + (One "controlmaster") + ", controlpath " + (One "controlpath") + ")")
        Check ((One "forwardagent") -ceq "no" -and (One "clearallforwardings") -ceq "yes" -and (One "forwardx11") -ceq "no") "nothing is forwarded"
        Check ((One "requesttty") -ceq "false") "no pseudo-terminal is asked for"
        Check ((One "permitlocalcommand") -ceq "no") "no local command runs"
        Check (@("<absent>", "none") -ccontains (One "proxycommand") -and @("<absent>", "none") -ccontains (One "proxyjump")) "no proxy command or jump host comes from anywhere"
        Check ((One "knownhostscommand") -ceq "<absent>" -and (One "remotecommand") -ceq "<absent>" -and (One "localcommand") -ceq "<absent>" -and (One "pkcs11provider") -ceq "<absent>") "no known-hosts command, remote command, local command or PKCS#11 provider is set"
        Check ((One "securitykeyprovider") -ceq "internal" -and (One "tunnel") -ceq "false" -and (One "forwardx11trusted") -ceq "no" -and (One "gatewayports") -ceq "no") "the security-key provider is the built-in one, and no tunnel, trusted X11 or gateway port is open"
        function Get-SshG { param([string[]]$Argv)
            $gp = Start-HordeSshProcess -Arguments (Join-HordeSshCommandLine -Argv (@("-G") + $Argv)) -Job (New-GJob)
            [void]$children.Add($gp)
            $txt = $gp.StandardOutput.ReadToEnd()
            $null = $gp.WaitForExit(30000)
            $h = @{}
            foreach ($line in ($txt -split "`r?`n")) { if ($line -match '^(\S+) (.*)$') { $k = $Matches[1].ToLowerInvariant(); if (-not $h.ContainsKey($k)) { $h[$k] = New-Object System.Collections.ArrayList }; [void]$h[$k].Add($Matches[2]) } }
            return $h }
        # F1, PROVED BY SSH: with Horde's key absent, ssh still offers only that path - no default key.
        # ssh -G needs the -F file to exist (it exits 255 otherwise), so each home gets Horde's empty
        # config and known_hosts; the absent-key home has no key.
        function New-GHome { param([string]$Name)
            $hp = Get-HordeSshPaths -HordeHome (Join-Path $tmp $Name)
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $hp.config) | Out-Null
            [System.IO.File]::WriteAllText($hp.config, "# Horde's own, empty`r`n")
            [System.IO.File]::WriteAllText($hp.knownHosts, "")
            return $hp }
        $gone = New-GHome "no key here"
        Check (-not (Test-Path -LiteralPath $gone.identity)) "CONTROL: the absent-key home really has no key file"
        $gk = Get-SshG -Argv (Get-HordeSshArgv -Endpoint $parsed -Paths $gone)
        Check ((@($gk["identityfile"]) -join " ; ") -ceq $gone.identity) ("with Horde's key file absent, ssh offers only that path and none of the user's default keys (" + (@($gk["identityfile"]) -join " ; ") + ")")
        # F2, PROVED BY SSH: under a home with a space and a tilde, the paths ssh resolves are the paths given.
        $odd = New-GHome "Jo Smith-x_y.z\.horde"
        $go = Get-SshG -Argv (Get-HordeSshArgv -Endpoint $parsed -Paths $odd)
        Check ((@($go["userknownhostsfile"]) -join " ; ") -ceq $odd.knownHosts -and (@($go["identityfile"]) -join " ; ") -ceq $odd.identity) "under a home holding every allowed character but the colon (a space, a hyphen, an underscore, dots), ssh resolves known_hosts and the key to exactly the paths given"
        Check ((One "port") -ceq "1" -and (One "user") -ceq "horde-link" -and (One "hostname") -ceq "127.0.0.1") "port, user and host are the endpoint's"
        # CONTROL: the same question without Horde's config and known_hosts options. ssh.exe ignores
        # USERPROFILE and resolves ~ to the real profile (measured 2026-10-02), so this shows the
        # user's own files without touching them: the check above can see the hazard it refuses.
        $ctl = Start-HordeSshProcess -Arguments (Join-HordeSshCommandLine -Argv @("-G", "-p", "1", "horde-link@127.0.0.1")) -Job (New-GJob)
        [void]$children.Add($ctl)
        $ctlOut = $ctl.StandardOutput.ReadToEnd()
        $null = $ctl.WaitForExit(30000)
        $userKh = ($ctlOut -split "`r?`n" | Where-Object { $_ -like "userknownhostsfile *" }) -join ""
        Check ($userKh -like "*.ssh*known_hosts*") ("CONTROL: without Horde's options ssh.exe reads the user's own known_hosts (" + $userKh + ") - the hazard the check above refuses")

        Write-Host ""
        Write-Host "--- a real ssh.exe dialling a closed port: exit 255 is unknown, stderr is the reason ---" -ForegroundColor Cyan
        $o = & $t.open $ep 5000
        Check ($o.ok) ("with Horde's files in place, Open starts ssh.exe (" + $o.reason + ")")
        if ($o.ok) {
            [void]$children.Add($o.channel.state.process)
            Check ($o.peer.verified -eq $true -and "$($o.peer.identity)" -ceq "horde-hub-test-hub" -and "$($o.peer.how)" -clike "*StrictHostKeyChecking=yes*carries no frame*") "the peer is named by the hub alias, verified by the pin: ssh.exe opens no session to any other host key (shown live, R17c-3)"
            $read = $null
            $until = (Get-Date).AddSeconds(20)
            while ((Get-Date) -lt $until) {
                $read = & $o.channel.read $o.channel 500
                if ($read.kind -ne "none") { break }
            }
            Check ($null -ne $read -and $read.kind -ceq "error" -and "$($read.reason)" -like "*exit 255*" -and "$($read.reason)" -like "*Connection refused*") ("ssh's exit 255 reads as an error naming the exit and stderr's first line (" + $read.reason + ")")
            & $o.channel.close $o.channel
        }

        Write-Host ""
        Write-Host "--- a process Open starts is handed to the link or killed, never left behind (review F7) ---" -ForegroundColor Cyan
        # THE FOUNDER'S RULE: orphans are prevented structurally. Every way out of Open after ssh.exe has
        # started either hands the process to the link or kills it, by pid and start time, in a finally.
        # To see it, ssh.exe must still be running when Open fails: it dials a listener of this suite's
        # that takes the TCP connection and never says a word, so ssh waits for a banner. Each step
        # after the start is made to throw in turn, and every ssh.exe Open started is then checked by
        # its pid and its start time, so a pid reused by another program is never mistaken for ours.
        $silent = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
        $silent.Start()
        $quietEp = "horde-link@127.0.0.1:" + $silent.LocalEndpoint.Port + "/test-hub"
        $script:openStarted = New-Object System.Collections.ArrayList
        $realStart = ${function:Start-HordeSshProcess}
        function Start-HordeSshProcess {
            param([string]$Arguments, $Job)
            $sp = & $realStart -Arguments $Arguments -Job $Job
            [void]$script:openStarted.Add([pscustomobject]@{ process = $sp; id = $sp.Id; at = $sp.StartTime })
            [void]$children.Add($sp)
            return $sp
        }
        function Test-OursAlive { param($Rec)
            try { $q = [System.Diagnostics.Process]::GetProcessById($Rec.id); return ($q.StartTime -eq $Rec.at -and -not $q.HasExited) } catch { return $false } }
        try {
            $o = Open-Raw $quietEp
            Check ($o.ok -and $script:openStarted.Count -eq 1) "CONTROL: an Open that succeeds starts one ssh.exe"
            if ($script:openStarted.Count -ge 1) { Check (Test-OursAlive $script:openStarted[-1]) "CONTROL: and it is alive, waiting on the silent listener, so a dead one below means it was killed" }
            if ($o.ok) { & $o.channel.close $o.channel }
            foreach ($step in @("Start-HordeSshProcess", "New-HordeSshChannel", "New-HordeSshResult")) {
                $before = $script:openStarted.Count
                $saved = (Get-Item -LiteralPath ("function:" + $step)).ScriptBlock
                # For the start itself, the throw comes right AFTER the process has started: the window
                # between the start and anything that could hold it (review of PR #68, round 3).
                if ($step -eq "Start-HordeSshProcess") { $failing = { param([string]$Arguments, $Job) $null = & $saved -Arguments $Arguments -Job $Job; throw "injected failure after the start" } }
                else { $failing = { throw "injected failure after the start" } }
                Set-Item -LiteralPath ("function:script:" + $step) -Value $failing
                try { $o = Open-Raw $quietEp } finally { Set-Item -LiteralPath ("function:script:" + $step) -Value $saved }
                Check (-not $o.ok -and "$($o.reason)" -like "*injected failure*") ("a throw in " + $step + ", after ssh.exe started, fails Open (" + $o.reason + ")")
                Check ($script:openStarted.Count -eq $before + 1) ("CONTROL: Open had started ssh.exe before " + $step + " threw")
                if ($script:openStarted.Count -eq $before + 1) {
                    Check (-not (Test-OursAlive $script:openStarted[-1])) ("no ssh.exe of ours survives a throw in " + $step + ": checked by pid " + $script:openStarted[-1].id + " and its start time")
                }
            }
            # THE STRUCTURAL GUARANTEE (review of PR #68, round 3; the founder's rule): ssh.exe runs in a Job
            # Object that kills it when its last handle closes, and only the link holds that handle. So
            # when the whole Horde process dies mid-link - no finally runs, nothing is closed - the OS
            # stops ssh.exe. A driver process opens a link and reports its ssh.exe; it is then killed.
            $drvScript = Join-Path $tmp "driver.ps1"
            [System.IO.File]::WriteAllText($drvScript, ('. "' + (Join-Path $root "transports\Port.ps1") + '"' + "`r`n" +
                '. "' + (Join-Path $root "transports\ssh\Transport.ps1") + '"' + "`r`n" +
                '$o = & (Get-HordeTransport -Name "ssh").open "' + $quietEp + '" 5000' + "`r`n" +
                'if (-not $o.ok) { [Console]::Out.WriteLine("OPEN-FAILED " + $o.reason); exit 3 }' + "`r`n" +
                '$sp = $o.channel.state.process' + "`r`n" +
                '[Console]::Out.WriteLine("SSH " + $sp.Id + " " + $sp.StartTime.Ticks)' + "`r`n" +
                'Start-Sleep -Seconds 120' + "`r`n"))
            $drv = Start-TestProcess -FilePath $psExe -Arguments ("-NoProfile -NonInteractive -ExecutionPolicy Bypass -File " + (Join-HordeSshCommandLine -Argv @($drvScript)))
            [void]$children.Add($drv)
            $lineTask = $drv.StandardOutput.ReadLineAsync()
            $gotLine = $lineTask.Wait(60000)
            $line = $(if ($gotLine) { "$($lineTask.Result)" } else { "" })
            $m = [regex]::Match($line, '^SSH (\d+) (\d+)$')
            Check ($m.Success) ("CONTROL: the driver opened a link and named its ssh.exe (" + $line + ")")
            if ($m.Success) {
                $rec = [pscustomobject]@{ id = [int]$m.Groups[1].Value; at = [datetime]::new([long]$m.Groups[2].Value) }
                Check (Test-OursAlive $rec) ("CONTROL: that ssh.exe, pid " + $rec.id + ", is alive while the driver holds the link")
                $drv.Kill()
                $null = $drv.WaitForExit(10000)
                $until = (Get-Date).AddSeconds(10)
                while ((Test-OursAlive $rec) -and (Get-Date) -lt $until) { Start-Sleep -Milliseconds 200 }
                Check (-not (Test-OursAlive $rec)) ("when the Horde process holding the link is killed outright, its ssh.exe dies with it: pid " + $rec.id + " and its start time are gone")
            }
        } finally {
            Set-Item -LiteralPath "function:script:Start-HordeSshProcess" -Value $realStart
            $silent.Stop()
        }
    } else {
        Write-Host "  [SKIP] ssh.exe is not in System32 on this machine: the -G, closed-port and F7 cases did not run" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "--- the kill is by pid AND start time: a wrong start time kills nothing ---" -ForegroundColor Cyan
    $victim = Start-TestProcess -FilePath $psExe -Arguments "-NoProfile -NonInteractive -Command Start-Sleep -Seconds 60"
    [void]$children.Add($victim)
    Stop-HordeSshUnowned -Process $victim -StartedAt $victim.StartTime.AddSeconds(-1)
    Check (-not $victim.HasExited) "a process whose start time is not the one recorded is left alone: the pid may now name another program"
    Stop-HordeSshUnowned -Process $victim -StartedAt $victim.StartTime
    Check ($victim.HasExited) "the same process, with the start time recorded, is stopped"

    Write-Host ""
    Write-Host "--- the byte channel over a child's stdio, with stand-in children ---" -ForegroundColor Cyan
    # A stand-in plays ssh's part: it reads stdin and writes stdout and stderr, then exits with a
    # chosen code. The channel is the same code Open hands the port.
    $stand = Join-Path $tmp "stand.ps1"
    [System.IO.File]::WriteAllText($stand, @'
param([string]$Mode)
$in = [Console]::OpenStandardInput()
$out = [Console]::OpenStandardOutput()
$err = [Console]::Error
if ($Mode -eq "echo") {
    $err.WriteLine("Warning: noise on stderr that must never reach a frame")
    # Whole lines back, as the conformance peer echoes whole frames: a byte-streaming echo deadlocks
    # once its stdout pipe is full while the far side is still writing (measured on this step's
    # first run, with a mebibyte frame).
    $line = New-Object System.Collections.Generic.List[byte]
    $buf = New-Object byte[] 65536
    while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
        for ($i = 0; $i -lt $n; $i++) {
            $line.Add($buf[$i])
            if ($buf[$i] -eq 10) { $arr = $line.ToArray(); $out.Write($arr, 0, $arr.Length); $out.Flush(); $line.Clear() }
        }
    }
    exit 0
}
if ($Mode -eq "fail") { $err.WriteLine("banner exchange: Connection to UNKNOWN port -1: Connection refused"); $err.WriteLine("second line"); exit 255 }
if ($Mode -eq "fail-banner") { $err.WriteLine("@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"); $err.WriteLine("@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @"); exit 255 }
if ($Mode -eq "frame-then-exit") { $b = [Text.Encoding]::ASCII.GetBytes("last`n"); $out.Write($b, 0, $b.Length); $out.Flush(); exit 0 }
if ($Mode -eq "exit1") { $err.WriteLine("remote command failed"); exit 1 }
if ($Mode -eq "hostile") {
    $e = [Console]::OpenStandardError()
    $b = [Text.Encoding]::ASCII.GetBytes([string][char]27 + "]0;PWNED" + [char]7 + [char]27 + "[2J" + ("A" * 200000) + "`n")
    $e.Write($b, 0, $b.Length); $e.Flush(); exit 255
}
if ($Mode -eq "flood") {
    # 20 MiB on stderr before a frame on stdout: the frame comes only if stderr is being drained.
    $e = [Console]::OpenStandardError()
    $chunk = New-Object byte[] 65536
    for ($i = 0; $i -lt $chunk.Length; $i++) { $chunk[$i] = 66 }
    for ($i = 0; $i -lt 320; $i++) { $e.Write($chunk, 0, $chunk.Length) }
    $e.Flush()
    $b = [Text.Encoding]::ASCII.GetBytes("done`n"); $out.Write($b, 0, $b.Length); $out.Flush(); exit 0
}
'@)
    function Start-Stand { param([string]$Mode)
        $sp = Start-TestProcess -FilePath $psExe -Arguments ("-NoProfile -NonInteractive -File " + (Join-HordeSshCommandLine -Argv @($stand, $Mode)))
        [void]$children.Add($sp)
        return $sp }
    function Stand-Link { param([string]$Mode)
        return (New-HordeLink -Transport (Get-HordeTransport -Name "ssh") -Role "node" -Endpoint "stand" -Channel (New-HordeSshChannel -Process (Start-Stand $Mode)) -Peer $null) }

    $l = Stand-Link "echo"
    $sent = @("first", "{""v"":1}", (-join ([char[]](32..126))))
    $got = foreach ($s in $sent) { $null = Send-HordeLinkFrame -Link $l -Frame $s -TimeoutMs 10000; $a = Receive-HordeLinkFrame -Link $l -TimeoutMs 10000; if ($a.state -eq "known") { $a.value } else { "<" + $a.reason + ">" } }
    Check ((@($got) -join "|") -ceq ($sent -join "|")) "frames round-trip through a child's stdio in order and unchanged, and stderr noise never reaches one"
    Close-HordeLink -Link $l

    $l2 = Stand-Link "echo"
    $big = "y" * $l2.maxFrameBytes
    $s = Send-HordeLinkFrame -Link $l2 -Frame $big -TimeoutMs 60000
    $a = Receive-HordeLinkFrame -Link $l2 -TimeoutMs 60000
    Check ($s.state -ceq "known" -and $a.state -ceq "known" -and $a.value -ceq $big) ("a frame of the transport's full cap, " + $l2.maxFrameBytes + " bytes, round-trips intact")
    Close-HordeLink -Link $l2

    $l3 = Stand-Link "fail"
    $a = Receive-HordeLinkFrame -Link $l3 -TimeoutMs 20000
    Check ($a.state -ceq "unknown" -and "$($a.reason)" -like "*exit 255*" -and "$($a.reason)" -like "*Connection refused*" -and "$($a.reason)" -notlike "*second line*") ("exit 255 is unknown: a transport error, with stderr's first line and only that (" + $a.reason + ")")
    Close-HordeLink -Link $l3
    # ssh.exe's changed-host-key warning opens with a border of '@': the reason is the first line that
    # says something (remote plan R16, measured against a live Windows sshd).
    $l3b = Stand-Link "fail-banner"
    $a = Receive-HordeLinkFrame -Link $l3b -TimeoutMs 20000
    Check ($a.state -ceq "unknown" -and "$($a.reason)" -like "*REMOTE HOST IDENTIFICATION HAS CHANGED*") ("a stderr that opens with a border line gives the line after it as the reason (" + $a.reason + ")")
    Close-HordeLink -Link $l3b

    $l4 = Stand-Link "frame-then-exit"
    $a = Receive-HordeLinkFrame -Link $l4 -TimeoutMs 20000
    $a2 = Receive-HordeLinkFrame -Link $l4 -TimeoutMs 20000
    Check ($a.state -ceq "known" -and $a.value -ceq "last") "a frame written before a clean exit still arrives"
    Check ($a2.state -ceq "unknown" -and "$($a2.reason)" -like "*closed*" -and "$($a2.reason)" -notlike "*255*") "and the clean exit after it is a close, unknown, never a transport error"
    Close-HordeLink -Link $l4

    # STDERR IS BOUNDED (review of PR #68, F3): the reason is at most 200 printable characters, and only
    # the first 4096 bytes of stderr are kept however much arrives; it is drained while the link reads,
    # so a far side writing it endlessly neither stalls the link nor grows this process.
    $lh = Stand-Link "hostile"
    $a = Receive-HordeLinkFrame -Link $lh -TimeoutMs 30000
    $r = "$($a.reason)"
    # The part stderr gave: after "transport error: ", without the link's own closing parentheses.
    $tail = [regex]::Match($r, 'transport error: (.*?)\)(;|\z)').Groups[1].Value
    Check ($a.state -ceq "unknown" -and $r -like "*exit 255*") ("a hostile stderr still gives exit 255 as unknown (" + $r.Length + " characters of reason)")
    Check ($tail.Length -ge 1 -and $tail.Length -le 203) ("the reason from stderr is at most 200 characters and an ellipsis (" + $tail.Length + ")")
    Check (-not [regex]::IsMatch($r, '[^\x20-\x7E]')) "the reason holds only printable ASCII: the escape and bell characters are gone"
    Close-HordeLink -Link $lh
    $lf = Stand-Link "flood"
    $a = Receive-HordeLinkFrame -Link $lf -TimeoutMs 120000
    Check ($a.state -ceq "known" -and $a.value -ceq "done") ("a frame sent after 20 MiB of stderr arrives: stderr is drained while the link reads (" + $a.reason + ")")
    $st = $lf.channel.state
    Check ($st.errKept.Count -le 4096 -and $st.errDropped -ge (20 * 1048576 - 4096)) ("only the first 4096 bytes of stderr are kept (" + $st.errKept.Count + " kept, " + $st.errDropped + " dropped)")
    Close-HordeLink -Link $lf
    # ONE LONG READ DRAINS TOO: the port reads in slices, but a caller that hands the channel one long
    # wait must not stall a far side that is writing stderr - the read waits on stderr as well as stdout.
    $ch = New-HordeSshChannel -Process (Start-Stand "flood")
    $t0 = Get-Date
    $rd = & $ch.read $ch 90000
    $el = ((Get-Date) - $t0).TotalSeconds
    Check ($rd.kind -ceq "data" -and [System.Text.Encoding]::ASCII.GetString($rd.bytes) -ceq "done`n" -and $el -lt 60) ("a single read given 90 s drains stderr while it waits, and returns the frame well inside it (" + [int]$el + " s, " + $rd.kind + ")")
    & $ch.close $ch

    $l5 = Stand-Link "exit1"
    $a = Receive-HordeLinkFrame -Link $l5 -TimeoutMs 20000
    Check ($a.state -ceq "unknown" -and "$($a.reason)" -like "*closed*" -and "$($a.reason)" -notlike "*transport error*") "an exit other than 255 is the far side ending, not a transport error"
    Close-HordeLink -Link $l5

    Write-Host ""
    Write-Host "--- Probe: an SSH banner over TCP, and no session ---" -ForegroundColor Cyan
    function Start-Banner { param([string]$Text)
        $lst = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
        $lst.Start()
        return [pscustomobject]@{ listener = $lst; port = $lst.LocalEndpoint.Port; text = $Text } }
    function Serve-Banner { param($B)
        # Accept the probe's connection and write the banner, on this thread, after the probe dialled.
        $task = $B.listener.AcceptTcpClientAsync()
        if (-not $task.Wait(15000)) { return $null }
        $c = $task.Result
        $bytes = [Text.Encoding]::ASCII.GetBytes($B.text)
        $c.GetStream().Write($bytes, 0, $bytes.Length)
        return $c }
    foreach ($case in @(@{ text = "SSH-2.0-OpenSSH_9.6`r`n"; want = "true"; what = "an SSH banner is reachable" },
                         @{ text = "HTTP/1.1 400 Bad Request`r`n"; want = "unknown"; what = "a server that answers but not as SSH is unknown, never reachable" })) {
        $b = Start-Banner $case.text
        try {
            # The probe runs in a second runspace so this thread can accept and answer.
            $ps = [PowerShell]::Create()
            [void]$ps.AddScript({ param($Root, $Ep) . (Join-Path $Root "transports\Port.ps1"); . (Join-Path $Root "transports\ssh\Transport.ps1"); Test-HordeTransportReachable -Transport (Get-HordeTransport -Name "ssh") -Endpoint $Ep }).AddArgument($root).AddArgument("horde-link@127.0.0.1:" + $b.port + "/test-hub")
            $h = $ps.BeginInvoke()
            $c = Serve-Banner $b
            Check ($null -ne $c) "CONTROL: the probe dialled the banner server"
            if (-not $h.AsyncWaitHandle.WaitOne(20000)) { $ps.Stop() }
            $res = @($ps.EndInvoke($h))
            $ps.Dispose()
            if ($null -ne $c) { $c.Close() }
            $pr = $res[-1]
            if ($case.want -eq "true") { Check ($pr.state -ceq "known" -and $pr.value -eq $true) ("probe: " + $case.what) }
            else { Check ($pr.state -ceq "unknown" -and "$($pr.reason)" -like "*SSH*") ("probe: " + $case.what + " (" + $pr.reason + ")") }
        } finally { $b.listener.Stop() }
    }
    $closed = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $closed.Start(); $cport = $closed.LocalEndpoint.Port; $closed.Stop()
    $pr = Test-HordeTransportReachable -Transport (Get-HordeTransport -Name "ssh") -Endpoint ("horde-link@127.0.0.1:" + $cport + "/test-hub")
    Check ($pr.state -ceq "known" -and $pr.value -eq $false) ("probe: a port nobody listens on is known unreachable (" + $pr.reason + ")")
    $pr = Test-HordeTransportReachable -Transport (Get-HordeTransport -Name "ssh") -Endpoint "not an endpoint"
    Check ($pr.state -ceq "unknown") "probe: a malformed endpoint is unknown"

    Write-Host ""
    Write-Host "--- the hub side is not built here: listening is refused, naming R16 ---" -ForegroundColor Cyan
    $la = & $t.listen "horde-link@127.0.0.1:22/test-hub"
    Check (-not $la.ok -and "$($la.reason)" -like "*R16*") "the adapter's own Listen refuses and says which step builds it"
    $la = Start-HordeTransportListener -Transport $t -Endpoint "horde-link@127.0.0.1:22/test-hub"
    Check ($la.state -ceq "unknown" -and "$($la.reason)" -like "*accept*") "and the port never asks it: accept is not yes"

    Write-Host ""
    Write-Host "--- the adapter runs only what an allowlist says, and starts one program, the sanctioned way ---" -ForegroundColor Cyan
    # transports/ssh/test/ExecGuard.ps1 says why an allowlist and not a list of forbidden forms: the
    # review of PR #68 passed 12 of 12 such forms through the first guard.
    $found = @(Get-HordeSshExecFindings -Dir (Join-Path $root "transports\ssh"))
    Check ($found.Count -eq 0) ("the adapter's code calls only allowlisted commands, methods and types, and starts exactly one program, in Start-HordeSshProcess, called once by Open with the System32 path (" + $found.Count + " finding(s))")
    foreach ($x in $found) { Write-Host ("         finding: " + $x) -ForegroundColor DarkYellow }
    # EVERY ONE OF THE REVIEW'S FORMS IS REFUSED: each is appended to a copy of Transport.ps1 and the
    # guard must find it. None is run: they sit in function bodies nothing calls, or define an alias.
    $forms = [ordered]@{
        "a second [Process]::Start" = 'function Zz { [System.Diagnostics.Process]::Start("ssh.exe") }'
        "a bare ssh.exe command" = 'function Zz { ssh.exe -o ProxyCommand=calc.exe h }'
        "the alias start" = 'function Zz { start ssh.exe }'
        "the alias saps" = 'function Zz { saps ssh.exe }'
        "a quoted member name" = 'function Zz { $p = New-Object System.Diagnostics.Process; $p."Start"() }'
        "a variable member name" = 'function Zz { $m = "Start"; $p = New-Object System.Diagnostics.Process; $p.$m() }'
        "a COM Run" = 'function Zz { (New-Object -ComObject WScript.Shell).Run("calc") }'
        "a dot-invoked script block" = 'function Zz { . ([scriptblock]::Create("calc")) }'
        "ScriptBlock.Invoke" = 'function Zz { [scriptblock]::Create("calc").Invoke() }'
        "Invoke-Command" = 'function Zz { Invoke-Command -ScriptBlock { calc } }'
        "an alias to the start function" = 'Set-Alias Zz Start-HordeSshProcess; function Yy { Zz -FilePath "C:\x\ssh.exe" -Arguments "" }'
        "cmd.exe /c" = 'function Zz { cmd.exe /c calc }'
        "ExecutionContext.InvokeCommand" = 'function Zz { $ExecutionContext.InvokeCommand.InvokeScript("calc") }'
    }
    $realTransport = [System.IO.File]::ReadAllText((Join-Path $root "transports\ssh\Transport.ps1"))
    function Test-GuardOn { param([string]$Text)
        $md = Join-Path $tmp ("guard-" + [guid]::NewGuid().ToString("N").Substring(0, 6))
        New-Item -ItemType Directory -Path $md | Out-Null
        Copy-Item -LiteralPath (Join-Path $root "transports\ssh\Argv.ps1") -Destination $md
        [System.IO.File]::WriteAllText((Join-Path $md "Transport.ps1"), $Text)
        return @(Get-HordeSshExecFindings -Dir $md) }
    foreach ($k in $forms.Keys) {
        Check ((Test-GuardOn ($realTransport + "`r`n" + $forms[$k] + "`r`n")).Count -ge 1) ("the guard refuses " + $k)
    }
    # ROUND 2 OF THE REVIEW: forms that are edits, not appends. Each must change the file (a control),
    # and the guard must refuse it.
    $edits = [ordered]@{
        "a second caller written in lower case" = @('$script:HordeSshFolder = $PSScriptRoot', '$script:HordeSshFolder = $PSScriptRoot; function Zz { start-hordesshprocess -Arguments "/c echo" }')
        "using module, which runs a module at load" = @('. (Join-Path $PSScriptRoot "Argv.ps1")', ('using module C:\nowhere\evil.psm1' + "`r`n" + '. (Join-Path $PSScriptRoot "Argv.ps1")'))
        "#requires, which loads what it names" = @('. (Join-Path $PSScriptRoot "Argv.ps1")', ('#requires -Modules EvilModule' + "`r`n" + '. (Join-Path $PSScriptRoot "Argv.ps1")'))
        "PSScriptRoot reassigned before the loader" = @('. (Join-Path $PSScriptRoot "Argv.ps1")', ('$PSScriptRoot = "C:\evil"' + "`r`n" + '. (Join-Path $PSScriptRoot "Argv.ps1")'))
        "StartInfo's FileName set after the sanctioned setup" = @('$psi.UseShellExecute = $false', '$psi.FileName = "C:\Windows\System32\cmd.exe"; $psi.UseShellExecute = $false')
        "StartInfo's Arguments set after the sanctioned setup" = @('$psi.UseShellExecute = $false', '$psi.Arguments = "/c calc"; $psi.UseShellExecute = $false')
        "the system root reassigned" = @('$script:HordeSshFolder = $PSScriptRoot', '$script:HordeSshFolder = $PSScriptRoot; $env:SystemRoot = "C:\evil"')
        # ROUND 3: the broad classes, not one-off forms.
        "a cmdlet shadowed inside the start function" = @('function Start-HordeSshProcess {', ('function Start-HordeSshProcess {' + "`r`n" + '    function Join-Path { "C:\Windows\System32\cmd.exe" }'))
        "a cmdlet shadowed at the top" = @('$script:HordeSshFolder = $PSScriptRoot', '$script:HordeSshFolder = $PSScriptRoot; function Join-Path { "C:\Windows\System32\cmd.exe" }')
        "a function defined twice" = @('$script:HordeSshFolder = $PSScriptRoot', '$script:HordeSshFolder = $PSScriptRoot; function Get-HordeSshArgv { @("-oProxyCommand=calc") }')
        "a function replaced through the function: drive" = @('$script:HordeSshFolder = $PSScriptRoot', '$script:HordeSshFolder = $PSScriptRoot; ${function:Get-HordeSshArgv} = { @("-oProxyCommand=calc") }')
        "an alias set through the alias: drive" = @('$script:HordeSshFolder = $PSScriptRoot', '$script:HordeSshFolder = $PSScriptRoot; ${alias:Join-Path} = "Get-Date"')
        "a variable set through the variable: drive" = @('$script:HordeSshFolder = $PSScriptRoot', '$script:HordeSshFolder = $PSScriptRoot; ${variable:x} = 1')
        "Add-Type outside Native.ps1" = @('$script:HordeSshFolder = $PSScriptRoot', '$script:HordeSshFolder = $PSScriptRoot; Add-Type -TypeDefinition "public class Zz {}"')
    }
    foreach ($k in $edits.Keys) {
        $from = $edits[$k][0]; $to = $edits[$k][1]
        Check ($realTransport.Contains($from)) ("CONTROL: the text '" + $from + "' is in Transport.ps1, so the edit for " + $k + " applies")
        Check ((Test-GuardOn ($realTransport.Replace($from, $to))).Count -ge 1) ("the guard refuses " + $k)
    }
    # NATIVE.ps1's C# IS PINNED: the guard cannot read C#, so Add-Type's source is held to a SHA-256 a
    # reviewer agreed to; a changed byte is a finding until the pin is changed with it.
    $mdN = Join-Path $tmp ("guard-native-" + [guid]::NewGuid().ToString("N").Substring(0, 6))
    New-Item -ItemType Directory -Path $mdN | Out-Null
    foreach ($nf in @("Argv.ps1", "Transport.ps1")) { Copy-Item -LiteralPath (Join-Path $root ("transports\ssh\" + $nf)) -Destination $mdN }
    $nativeText = [System.IO.File]::ReadAllText((Join-Path $root "transports\ssh\Native.ps1"))
    [System.IO.File]::WriteAllText((Join-Path $mdN "Native.ps1"), $nativeText.Replace("public static class HordeSshNative", "public static class HordeSshNative /* changed */"))
    Check (@(Get-HordeSshExecFindings -Dir $mdN | Where-Object { "$_" -like "*pinned*" }).Count -ge 1) "the guard refuses Native.ps1 whose C# source differs from the pinned SHA-256"
} finally {
    $env:HORDE_HOME = $savedHome
    foreach ($c in @($children)) {
        # Only the children this suite started and still holds; the handle pins the pid (CONTRIBUTING 9).
        try { if (-not $c.HasExited) { $c.Kill(); $null = $c.WaitForExit(10000) } } catch { }
    }
    Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "--- the user's ~/.ssh is untouched ---" -ForegroundColor Cyan
Check (-not (Test-Path -LiteralPath $tmp)) "the suite's temp folder, keys included, is gone"
Check ((Get-SshDirPrint) -ceq $sshDirBefore) "every file in the user's ~/.ssh has the same length and SHA-256 as before the suite"

Complete-HordeSuite -Success "the ssh transport dials out as its argv says, and never as the user's config says"
