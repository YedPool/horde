# DOES `horde listen` ADMIT ONLY ENROLLED KEYS, FORCED TO ATTACH, AND DOES ATTACH RELAY THEM TO THE HUB?
#
# Remote plan R17a, end to end. `horde listen` is started as a user would start it, as this suite's own
# child: it runs Windows sshd (transports/ssh/Listen.ps1) on 127.0.0.1 with Horde's own configuration,
# host key and authorized_keys, all under a Horde home this suite makes. The suite plays both other
# parts on this one machine: the hub, listening on its own pipe through the local transport, and the
# node, dialling through the ssh transport's own Open with its key and its pin. It checks:
#   - the keys the listener admits: one enrolled device each, forced to exactly the command
#     Get-HordeSshAttachCommand builds for it (pinned here), restricted; a key line without command= makes
#     `horde listen` refuse to start, and nothing listens;
#   - a session reaches the hub's pipe with the preamble naming the device from the key's command=,
#     never from stdin; the hub may speak first; frames cross one at a time, each answered before the
#     next is sent (streamed, not buffered); a mebibyte frame crosses whole; a hello claiming another
#     device is refused by the binding (remote/LinkBinding.ps1);
#   - the command a client asks for is never run, and a port forward is refused;
#   - when the hub closes, attach ends; when the node closes, attach ends;
#   - CONTROL for issue #100: under the same sshd a forced command that reads stdin through a .NET
#     Console stream gets nothing, while $input in the same session gets the line - which is why attach
#     reads $input and never a Console stream.
#
# THE MACHINE IS LEFT AS IT WAS, CHECKED, NOT ASSUMED: the sshd service's state and start mode, the
# OpenSSH-Server-In-TCP firewall rule, listeners on port 22, C:\ProgramData\ssh and ~/.ssh are read at the
# start and compared at the end, and no sshd, attach or listen process of this suite may survive it. A
# difference is a loud FAIL; nothing is put back.
#
# LOCAL ONLY (machine-bound, test/lib/SuiteFiles.ps1): it needs this machine's OpenSSH Server and an
# interactive logon for the local pipe. When sshd.exe is missing the suite exits 3, never green.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "Schema", "Home", "Device")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "transports\Port.ps1")
. (Join-Path $root "transports\local\Transport.ps1")
. (Join-Path $root "transports\ssh\Transport.ps1")
. (Join-Path $root "transports\Listener.ps1")
. (Join-Path $root "transports\ssh\Listen.ps1")
. (Join-Path $root "remote\LinkBinding.ps1")
. (Join-Path $here "ListenFixture.ps1")

$limitSeconds = 240
$clock = [System.Diagnostics.Stopwatch]::StartNew()
function Left { param([int]$Ms) return [int][Math]::Max(1, [Math]::Min($Ms, ($limitSeconds * 1000) - $clock.ElapsedMilliseconds - 10000)) }
$tl = Get-HordeTransport -Name "local"
$ts = Get-HordeTransport -Name "ssh"
$skipped = ""
$before = Get-ListenMachine
Write-Host ("  at the start: sshd service " + $before.service + ", firewall rule " + $before.firewall + ", " + $before.port22 + " listener(s) on port 22") -ForegroundColor DarkGray
$savedHome = $env:HORDE_HOME
$work = ""
$job = $null
$listen = $null
$hubListener = $null
$ports = New-Object System.Collections.ArrayList
$nodeDev = [guid]::NewGuid().ToString()
$otherDev = [guid]::NewGuid().ToString()

function Start-Listen {
    # The real `horde listen`, as this suite's child in its job.
    param([int]$Port, [int]$Seconds)
    $a = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"" + (Join-Path $root "horde.ps1") + "`" listen -Port " + $Port + " -Seconds " + $Seconds
    return (Start-ListenChild -Exe "powershell.exe" -Arguments $a -Job $job -Directory $work)
}

try {
    if (-not (Test-Path -LiteralPath $script:ListenSshdExe -PathType Leaf)) { $skipped = "no sshd.exe at " + $script:ListenSshdExe }
    $user = [System.Environment]::UserName.ToLowerInvariant()
    if ($skipped -eq "" -and $user -cnotmatch '\A[a-z_][a-z0-9_-]{0,31}\z') { $skipped = "this account's name '" + $user + "' is not one the ssh endpoint grammar takes" }
    if ($skipped -eq "") {
        $work = New-ListenWork
        $hh = Join-Path $work "home"
        $env:HORDE_HOME = $hh
        $hubId = (Get-HordeNode).deviceId
        $job = [HordeSshNative]::NewKillOnCloseJob()
        $files = Get-HordeSshListenFiles -HordeHome $hh
        New-Item -ItemType Directory -Path $files.dir | Out-Null
        $hostPub = New-ListenKey -Path $files.hostKey
        $clientPub = New-ListenKey -Path (Join-Path $work "client_ed25519")

        Write-Host ""
        Write-Host "--- the keys the listener admits: one device each, forced to its attach, restricted ---" -ForegroundColor Cyan
        $attach = Get-HordeSshAttachCommand -HordeRoot $root -DeviceId $nodeDev
        Check ($attach -ceq ([System.IO.Path]::Combine([System.Environment]::SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe") + " -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " + (Join-Path $root "cli\attach.ps1") + " -Device " + $nodeDev)) ("PIN: the forced command is cli\attach.ps1 -Device <id>, as Get-HordeSshAttachCommand builds it (" + $attach + ")")
        $good = 'command="' + $attach + '",restrict ' + $clientPub + " horde-device-" + $nodeDev
        Check (@(Test-HordeSshListenKeys -Lines @($good) -Root $root).Count -eq 0) "CONTROL: a line forced to the attach Get-HordeSshAttachCommand returns for its device, restricted, is admitted"
        Check (@(Test-HordeSshListenKeys -Lines @(('command="' + $attach + '",restrict,expiry-time="20991231" ' + $clientPub + " horde-device-" + $nodeDev), "") -Root $root).Count -eq 0) "and with an expiry, beside a blank line"

        Write-Host ""
        Write-Host "--- horde listen refuses to start while a key is not held to attach ---" -ForegroundColor Cyan
        [System.IO.File]::WriteAllText($files.authorized, ($good + "`n" + $clientPub + " horde-device-" + $otherDev + "`n"))
        $p0 = Get-ListenFreePort; [void]$ports.Add($p0)
        $r = Start-Listen -Port $p0 -Seconds 20
        $err = $r.process.StandardError.ReadToEndAsync(); $null = $r.process.StandardOutput.ReadToEndAsync()
        $ended = $r.process.WaitForExit((Left 60000))
        Check ($ended -and $r.process.ExitCode -eq 1 -and (Get-ListenText $err) -like "*line 2 of authorized_keys*") ("a key line without command= makes horde listen exit 1, naming the line (exit " + $(if ($ended) { $r.process.ExitCode } else { "none" }) + ": " + (Get-ListenText $err).Trim() + ")")
        Check ((Get-ListenListeners -Port $p0) -eq 0 -and @(Get-ListenProcesses -Marker $work | Where-Object { $_.Name -ieq "sshd.exe" }).Count -eq 0) "and no sshd was started: nothing listens on its port"

        Write-Host ""
        Write-Host "--- horde listen, for a while, then stops by itself ---" -ForegroundColor Cyan
        [System.IO.File]::WriteAllText($files.authorized, ($good + "`n"))
        $p1 = Get-ListenFreePort; [void]$ports.Add($p1)
        $r = Start-Listen -Port $p1 -Seconds 8
        $first = Read-ListenLine -Reader $r.process.StandardOutput -Ms (Left 60000)
        Check ("$first" -like ("listening on 127.0.0.1:" + $p1 + " for hub " + $hubId + "*")) ("it says where it listens and for which hub (" + $first + ")")
        $bound = @(Get-NetTCPConnection -State Listen -LocalPort $p1 -ErrorAction SilentlyContinue)
        Check ($bound.Count -ge 1 -and @($bound | Where-Object { $_.LocalAddress -ne "127.0.0.1" }).Count -eq 0) ("it binds 127.0.0.1 only (" + (@($bound | ForEach-Object { $_.LocalAddress }) -join ", ") + ")")
        $cfg = [System.IO.File]::ReadAllText($files.config)
        Check ($cfg -notmatch '(?im)^\s*ForceCommand' -and $cfg -match '(?m)^ListenAddress 127\.0\.0\.1\r?$' -and $cfg -match '(?m)^DisableForwarding yes\r?$' -and $cfg -match '(?m)^PermitTTY no\r?$') "its configuration: no ForceCommand (it would replace the key's -Device), loopback only, no forwarding, no terminal"
        Check ($cfg.Contains($hh.Replace('\', '/') + "/hub/listen/authorized_keys") -and -not $cfg.ToLowerInvariant().Contains("programdata") -and -not $cfg.Contains(".ssh")) "and every file it names is under Horde's home: never ProgramData\ssh, never ~/.ssh"
        $out = $r.process.StandardOutput.ReadToEndAsync(); $err = $r.process.StandardError.ReadToEndAsync()
        $ended = $r.process.WaitForExit((Left 60000))
        Check ($ended -and $r.process.ExitCode -eq 0 -and (Get-ListenText $out) -like ("*listener on 127.0.0.1:" + $p1 + " stopped*")) ("after -Seconds it stops and exits 0 (exit " + $(if ($ended) { $r.process.ExitCode } else { "none" }) + ": " + (Get-ListenText $out).Trim() + " " + (Get-ListenText $err).Trim() + ")")
        Start-Sleep -Milliseconds 500
        Check ((Get-ListenListeners -Port $p1) -eq 0 -and @(Get-ListenProcesses -Marker $work | Where-Object { $_.Name -ieq "sshd.exe" }).Count -eq 0) "and its sshd is gone: nothing listens on its port"
        # Stop itself, not the caller's exit: when horde listen exits, its job's last handle closes and
        # ends sshd whatever Stop did (a mutant that skipped Stop's work survived that case, 2026-10-07),
        # so here the listener is started and stopped in this process, which lives on.
        $ad = Get-HordeListenerAdapter -Name "ssh"
        $p1b = Get-ListenFreePort; [void]$ports.Add($p1b)
        $run = Start-HordeListener -Adapter $ad.value -HordeHome $hh -HubId $hubId -Root $root -Port $p1b
        Check ($run.state -ceq "known" -and (Get-ListenListeners -Port $p1b) -ge 1) ("CONTROL: started in this process, it listens on " + $p1b + " " + $run.reason)
        if ($run.state -ceq "known") {
            $null = Stop-HordeListener -Running $run.value
            $d = [datetime]::UtcNow.AddSeconds(10)
            while (((Get-ListenListeners -Port $p1b) -gt 0 -or -not $run.value.listener.process.HasExited) -and [datetime]::UtcNow -lt $d) { Start-Sleep -Milliseconds 200 }
            Check ($run.value.listener.process.HasExited -and (Get-ListenListeners -Port $p1b) -eq 0) "Stop ends sshd while its caller lives on: nothing listens on its port"
        }

        Write-Host ""
        Write-Host "--- a node dials in: the session reaches the hub's pipe, bound to the key's device ---" -ForegroundColor Cyan
        $hl = Start-HordeTransportListener -Transport $tl -Endpoint ("hub:" + $hubId)
        Check ($hl.state -ceq "known") "the stand-in hub listens on its own pipe"
        $hubListener = Get-HordeValue $hl
        $p2 = Get-ListenFreePort; [void]$ports.Add($p2)
        $listen = Start-Listen -Port $p2 -Seconds ($limitSeconds)
        $first = Read-ListenLine -Reader $listen.process.StandardOutput -Ms (Left 60000)
        Check ("$first" -like ("listening on 127.0.0.1:" + $p2 + "*")) ("horde listen is up (" + $first + ")")
        # The node's half, as enrolment leaves it: its key, the hub's host key pinned under its alias,
        # and an ssh_config with no directive (transports/ssh/Argv.ps1).
        $nodeDir = Join-Path $hh "node"
        Copy-Item -LiteralPath (Join-Path $work "client_ed25519") -Destination (Join-Path $nodeDir "link_ed25519")
        [System.IO.File]::WriteAllText((Join-Path $nodeDir "ssh_config"), "# Horde's argv is the whole configuration`n")
        [System.IO.File]::WriteAllText((Join-Path $nodeDir "known_hosts"), ("horde-hub-" + $hubId + " " + $hostPub + "`n"))
        $endpoint = $user + "@127.0.0.1:" + $p2 + "/" + $hubId
        function Open-Pair {
            # One node link through the adapter's own Open (its dial.out is still unverified, so the
            # port would refuse; R17's later slice flips it) and the hub's accepted end: { node; hub }.
            $o = & $ts.open $endpoint (Left 15000)
            if (-not $o.ok) { Write-Host ("         no node link: " + $o.reason) -ForegroundColor DarkYellow; return $null }
            $n = New-HordeLink -Transport $ts -Role "node" -Endpoint $endpoint -Channel $o.channel -Peer $o.peer
            $a = Receive-HordeTransportLink -Listener $hubListener -TimeoutMs (Left 30000)
            if ($a.state -cne "known") { Write-Host ("         the hub accepted nothing: " + $a.reason) -ForegroundColor DarkYellow; Close-HordeLink -Link $n; return $null }
            return [pscustomobject]@{ node = $n; hub = (Get-HordeValue $a) }
        }
        function Get-AttachCount { return @(Get-ListenProcesses -Marker ("attach.ps1 -Device " + $nodeDev) | Where-Object { $_.Name -ieq "powershell.exe" }).Count }
        function Wait-AttachGone { param([int]$Ms) $d = [datetime]::UtcNow.AddMilliseconds($Ms); while ((Get-AttachCount) -gt 0 -and [datetime]::UtcNow -lt $d) { Start-Sleep -Milliseconds 250 }; return ((Get-AttachCount) -eq 0) }

        $pair = Open-Pair
        Check ($null -ne $pair) "a node link opens and the hub's pipe accepts the session"
        if ($null -ne $pair) {
            try {
                $pre = Receive-HordeLinkFrame -Link $pair.hub -TimeoutMs (Left 20000)
                $b = $null; if ($pre.state -ceq "known") { $b = Read-HordeAttachPreamble -Line "$($pre.value)" }
                Check ($null -ne $b -and $b.state -ceq "known" -and "$($b.value)" -ceq $nodeDev) ("the first line the hub reads is the preamble, naming the device from the key's command= (" + "$($pre.value)$($pre.reason)" + ")")
                Check ((Get-AttachCount) -eq 1) "and exactly one attach runs, for that device"
                $null = Send-HordeLinkFrame -Link $pair.hub -Frame "hub-speaks-first"
                $g = Receive-HordeLinkFrame -Link $pair.node -TimeoutMs (Left 15000)
                Check ($g.state -ceq "known" -and "$($g.value)" -ceq "hub-speaks-first") "the hub may speak first: its frame reaches the node with nothing sent by the node"
                $answers = @()
                foreach ($i in 1..3) {
                    $null = Send-HordeLinkFrame -Link $pair.node -Frame ("frame-" + $i)
                    $h = Receive-HordeLinkFrame -Link $pair.hub -TimeoutMs (Left 15000)
                    if ($h.state -ceq "known") { $null = Send-HordeLinkFrame -Link $pair.hub -Frame ("ack-" + $h.value) }
                    $back = Receive-HordeLinkFrame -Link $pair.node -TimeoutMs (Left 15000)
                    $answers += ("" + $h.value + ">" + $back.value)
                }
                Check (($answers -join "|") -ceq "frame-1>ack-frame-1|frame-2>ack-frame-2|frame-3>ack-frame-3") ("frame by frame: each reaches the hub and is answered before the next is sent, so stdin streams and is not read to its end (" + ($answers -join "|") + ")")
                $null = Send-HordeLinkFrame -Link $pair.node -Frame ("horde-attach 1 " + $otherDev)
                $h = Receive-HordeLinkFrame -Link $pair.hub -TimeoutMs (Left 15000)
                Check ($h.state -ceq "known" -and "$($h.value)" -ceq ("horde-attach 1 " + $otherDev) -and "$($b.value)" -ceq $nodeDev) "a preamble the node writes into stdin arrives as an ordinary later line; the link stays bound to the key's device"
                $forged = '{"v":1,"kind":"hello","hello":{"id":"' + $otherDev + '","name":"box","protocols":[1]}}'
                $null = Send-HordeLinkFrame -Link $pair.node -Frame $forged
                $h = Receive-HordeLinkFrame -Link $pair.hub -TimeoutMs (Left 15000)
                $hf = @(); if ($h.state -ceq "known") { $hf = @(Test-HordeHelloBinding -Frame ("$($h.value)" | ConvertFrom-Json) -BoundDeviceId "$($b.value)") }
                Check ($hf.Count -eq 1 -and $hf[0] -like ("*claims device '" + $otherDev + "'*")) ("a hello claiming another device, sent through the link, is refused by the binding (" + ($hf -join "; ") + ")")
                $true1 = '{"v":1,"kind":"hello","hello":{"id":"' + $nodeDev + '","name":"box","protocols":[1]}}'
                $null = Send-HordeLinkFrame -Link $pair.node -Frame $true1
                $h = Receive-HordeLinkFrame -Link $pair.hub -TimeoutMs (Left 15000)
                Check ($h.state -ceq "known" -and @(Test-HordeHelloBinding -Frame ("$($h.value)" | ConvertFrom-Json) -BoundDeviceId "$($b.value)").Count -eq 0) "CONTROL: the node's own hello, through the same link, stands"
                $big = "x" * 1048576
                $null = Send-HordeLinkFrame -Link $pair.node -Frame $big -TimeoutMs (Left 30000)
                $h = Receive-HordeLinkFrame -Link $pair.hub -TimeoutMs (Left 30000)
                Check ($h.state -ceq "known" -and "$($h.value)".Length -eq 1048576) ("a mebibyte frame crosses whole (" + "$($h.value)".Length + " bytes)")
                Write-Host ""
                Write-Host "--- when the hub closes, attach ends and the node sees the link close ---" -ForegroundColor Cyan
                Close-HordeLink -Link $pair.hub
                $c = Receive-HordeLinkFrame -Link $pair.node -TimeoutMs (Left 15000)
                Check ($c.state -ceq "unknown") ("the node's link reads closed (" + $c.reason + ")")
                Check (Wait-AttachGone -Ms (Left 15000)) "and attach is gone: it ended itself when the hub's pipe closed"
            } finally { Close-HordeLink -Link $pair.node; Close-HordeLink -Link $pair.hub }
        }

        Write-Host ""
        Write-Host "--- when the node closes, attach ends and the hub sees the link close ---" -ForegroundColor Cyan
        $pair = Open-Pair
        Check ($null -ne $pair) "a second link opens"
        if ($null -ne $pair) {
            try {
                $pre = Receive-HordeLinkFrame -Link $pair.hub -TimeoutMs (Left 20000)
                Check ($pre.state -ceq "known") "its preamble arrives"
                Close-HordeLink -Link $pair.node
                $c = Receive-HordeLinkFrame -Link $pair.hub -TimeoutMs (Left 15000)
                Check ($c.state -ceq "unknown") ("the hub's link reads closed (" + $c.reason + ")")
                Check (Wait-AttachGone -Ms (Left 15000)) "and attach is gone"
            } finally { Close-HordeLink -Link $pair.node; Close-HordeLink -Link $pair.hub }
        }

        Write-Host ""
        Write-Host "--- what a client asks for: never a command of its choosing, never a forward ---" -ForegroundColor Cyan
        function Start-RawSsh {
            # ssh.exe itself, with the node's key and pin and -Extra before the destination.
            param([string[]]$Extra, [string[]]$After)
            $argv = @("-F", "none", "-T", "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes", "-o", "IdentityAgent=none", "-o", ('IdentityFile="' + (Join-Path $nodeDir "link_ed25519") + '"'),
                "-o", ('UserKnownHostsFile="' + (Join-Path $nodeDir "known_hosts") + '"'), "-o", "GlobalKnownHostsFile=none", "-o", "StrictHostKeyChecking=yes", "-o", ("HostKeyAlias=horde-hub-" + $hubId),
                "-o", "ConnectTimeout=10", "-p", "$p2") + @($Extra) + @(($user + "@127.0.0.1")) + @($After)
            return (Start-ListenChild -Exe $script:ListenSshExe -Arguments (Join-HordeSshCommandLine -Argv $argv) -Job $job)
        }
        $marker = Join-Path $work "pwned.txt"
        $rs = Start-RawSsh -Extra @() -After @("cmd.exe", "/c", ("echo pwned>" + $marker))
        $a = Receive-HordeTransportLink -Listener $hubListener -TimeoutMs (Left 30000)
        $pre = $null; if ($a.state -ceq "known") { $pre = Receive-HordeLinkFrame -Link (Get-HordeValue $a) -TimeoutMs (Left 15000) }
        Check ($null -ne $pre -and $pre.state -ceq "known" -and "$($pre.value)" -ceq ("horde-attach 1 " + $nodeDev)) "a session that asks for its own command reaches the hub through attach instead"
        $rs.process.StandardInput.Close()
        if ($a.state -ceq "known") { Close-HordeLink -Link (Get-HordeValue $a) }
        $null = $rs.process.WaitForExit((Left 15000))
        Check (-not (Test-Path -LiteralPath $marker)) "and the command it asked for never ran: its marker file does not exist"
        $fwd = Start-RawSsh -Extra @("-W", ("127.0.0.1:" + $p2)) -After @()
        $ferr = $fwd.process.StandardError.ReadToEndAsync(); $null = $fwd.process.StandardOutput.ReadToEndAsync()
        $fended = $fwd.process.WaitForExit((Left 20000))
        Check ($fended -and $fwd.process.ExitCode -ne 0 -and (Get-ListenText $ferr) -match "(?i)prohibited|forward|refused") ("a stdio forward (-W) is refused (exit " + $(if ($fended) { $fwd.process.ExitCode } else { "none" }) + ": " + (Get-ListenText $ferr).Trim() + ")")
        $nobody = Receive-HordeTransportLink -Listener $hubListener -TimeoutMs 500
        Check ($nobody.state -ceq "unknown") "and it reached nothing: the hub's pipe saw no session from it"

        Write-Host ""
        Write-Host "--- CONTROL (issue #100): a .NET Console stream reads nothing in a session; `$input reads the line ---" -ForegroundColor Cyan
        # A second sshd, this suite's own, from the listener's very configuration on another port, whose
        # one key is forced to a probe script instead of attach: the probe tries the Console stream for
        # 5 s, then reads $input. Only a test may admit such a key; the listener refuses it.
        $probe = Join-Path $work "console-probe.ps1"
        [System.IO.File]::WriteAllText($probe, ('$s = [Console]::OpenStandardInput(); $b = New-Object byte[] 64; $t = $s.ReadAsync($b, 0, 64); $n = "none"; if ($t.Wait(5000)) { $n = "" + $t.Result }; [Console]::Out.Write("console=" + $n + [char]10); [Console]::Out.Flush(); foreach ($l in $input) { [Console]::Out.Write("input=" + $l + [char]10); [Console]::Out.Flush(); break }'))
        $ak2 = Join-Path $files.dir "control_keys"
        [System.IO.File]::WriteAllText($ak2, ('command="powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' + $probe + '",restrict ' + $clientPub + "`n"))
        $p3 = Get-ListenFreePort; [void]$ports.Add($p3)
        $cfg2 = Join-Path $files.dir "control_config"
        [System.IO.File]::WriteAllText($cfg2, ($cfg -replace '(?m)^Port [0-9]+', ('Port ' + $p3)).Replace("/hub/listen/authorized_keys", "/hub/listen/control_keys").Replace("/hub/listen/sshd.pid", "/hub/listen/control.pid"))
        $ctl = Start-ListenChild -Exe $script:ListenSshdExe -Arguments ('-D -e -f "' + $cfg2 + '"') -Job $job
        $null = $ctl.process.StandardError.ReadToEndAsync()
        $d = [datetime]::UtcNow.AddMilliseconds((Left 15000)); while ((Get-ListenListeners -Port $p3) -eq 0 -and [datetime]::UtcNow -lt $d -and -not $ctl.process.HasExited) { Start-Sleep -Milliseconds 200 }
        $p2Saved = $p2; $p2 = $p3
        $cs = Start-RawSsh -Extra @() -After @()
        $p2 = $p2Saved
        $cs.process.StandardInput.Write("probe-line`n"); $cs.process.StandardInput.Flush()
        $l1 = Read-ListenLine -Reader $cs.process.StandardOutput -Ms (Left 30000)
        $l2 = Read-ListenLine -Reader $cs.process.StandardOutput -Ms (Left 15000)
        Check ("$l1" -ceq "console=none" -or "$l1" -ceq "console=0") ("the Console stream returned no data within 5 s, though the line was sent (" + $l1 + ")")
        Check ("$l2" -ceq "input=probe-line") ("CONTROL: `$input in the same session read the line (" + $l2 + ")")
        try { $cs.process.StandardInput.Close() } catch { }
        $null = $cs.process.WaitForExit((Left 10000))
        try { $ctl.process.Kill() } catch { }
        $null = $ctl.process.WaitForExit(10000)
        $src = [System.IO.File]::ReadAllText((Join-Path $root "cli\attach.ps1")) + [System.IO.File]::ReadAllText((Join-Path $root "transports\local\Relay.ps1"))
        $code = @($src -split "`n" | Where-Object { $_.TrimStart() -notlike "#*" }) -join "`n"
        Check (-not $code.Contains("OpenStandardInput") -and -not $code.Contains("[Console]::In") -and $code.Contains('$input')) "attach and its relay read stdin through `$input only, never a Console stream"
    }
} finally {
    Write-Host ""
    Write-Host "--- teardown: nothing of this suite survives, and the machine is as it was ---" -ForegroundColor Cyan
    if ($null -ne $listen) {
        # Killed, not asked: the listener's own job must end its sshd and every session when it dies.
        try { $listen.process.Kill() } catch { }
        $null = $listen.process.WaitForExit(15000)
        $d = [datetime]::UtcNow.AddSeconds(15)
        while (@(Get-ListenProcesses -Marker $work | Where-Object { $_.Name -ieq "sshd.exe" }).Count -gt 0 -and [datetime]::UtcNow -lt $d) { Start-Sleep -Milliseconds 250 }
        Check (@(Get-ListenProcesses -Marker $work | Where-Object { $_.Name -ieq "sshd.exe" }).Count -eq 0) "killing horde listen ends its sshd: the job it held closed"
    }
    if ($null -ne $hubListener) { Stop-HordeTransportListener -Listener $hubListener }
    if ($null -ne $job) { $job.Dispose() }
    $env:HORDE_HOME = $savedHome
    if ($skipped -eq "") {
        Start-Sleep -Milliseconds 500
        Check (@(Get-ListenProcesses -Marker ("attach.ps1 -Device " + $nodeDev)).Count -eq 0) "no attach process survives"
        Check (@(Get-ListenProcesses -Marker $work).Count -eq 0) "no sshd, listen or probe process of this suite survives"
        foreach ($p in $ports) { Check ((Get-ListenListeners -Port $p) -eq 0) ("nothing listens on port " + $p + " any more") }
    }
    if ($work -ne "" -and (Split-Path -Leaf $work) -match '^horde-listen-[0-9a-f]{12}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    $after = Get-ListenMachine
    foreach ($k in @("service", "firewall", "port22", "programData", "userSsh")) {
        $same = ("$($after.$k)" -ceq "$($before.$k)")
        if (-not $same) { Write-Host ("  !!! THE MACHINE CHANGED: " + $k + " was '" + $before.$k + "' and is '" + $after.$k + "' now. Nothing was put back; look at it.") -ForegroundColor Red }
        Check $same ("the " + $k + " is as it was at the start")
    }
    Check ($after.service -ceq $before.service -and ($before.service -ceq "not installed" -or $after.service -clike "Stopped/*")) ("the sshd service is " + $after.service + ": this suite never starts it")
}
if ($skipped -ne "") {
    Write-Host ("  [SKIP] " + $skipped) -ForegroundColor Yellow
    Complete-HordeSuite -Success ("SKIPPED: " + $skipped) -PassCode 3
}
Complete-HordeSuite -Success "horde listen admits only enrolled keys, forced to attach, and attach relays each session to the hub's pipe, bound to its device"
