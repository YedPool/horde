# transports/ssh/test/FarEnd.ps1 - the ssh transport's live far end for test/test-transport-conformance.ps1
# (remote plan R17c-3). Not a suite. The conformance suite dot-sources a transport's test/FarEnd.ps1 when
# its accept is not yes, so a capability that only a live far end can show is shown against one.
#
# THE FAR END IS THE HUB'S LISTENER, AS R17a RUNS IT: R16's child sshd (Sshd.ps1: 127.0.0.1, a TEMP
# folder only this user, SYSTEM and Administrators can read, a kill-on-close job, a watchdog), with NO
# ForceCommand, reading the hub's own enrolment files - authorized_keys and revoked_keys written by
# Enroll.ps1, the host key Initialize-HordeSshHub made. Each node is a Horde home of its own, its key and
# its pin made by Enroll.ps1 too. So what is shown is the enrolment code's lines doing their job. The
# enrolled forced command runs <root>\cli\attach.ps1; the root here is a TEMP stand-in whose attach.ps1
# echoes each line (stdin through $input, issue #100), since the real one is R17a's.
#
# THE CONTRACT the suite reads: $script:HordeFarEnds["<transport>"] = { start; stop } where start returns
# { skip; cases }. skip is "" or why this machine cannot run the far end. Each case is { capability; kind;
# name; homeDir; endpoint; expect; refusal }: the suite points HORDE_HOME at homeDir, opens a node link to
# endpoint through the port, and expects frames to round-trip ("carries") or the link to be refused with
# a reason matching refusal ("refused"). The kinds a capability needs are the suite's, not this file's.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path $PSScriptRoot "Sshd.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "Enroll.ps1")

$script:HordeSshFarEndLimitSeconds = 300

function Start-HordeSshFarEnd {
    $fe = [pscustomobject]@{ skip = ""; cases = @(); sshd = $null; root = "" }
    if (-not (Test-Path -LiteralPath $script:HordeSshdExe -PathType Leaf)) { $fe.skip = "no sshd.exe at " + $script:HordeSshdExe; return $fe }
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $user = $me.Name.Split('\')[-1].ToLowerInvariant()
    if ($user -cnotmatch '\A[a-z_][a-z0-9_-]{0,31}\z') { $fe.skip = "this account's name '" + $user + "' is not one the ssh endpoint grammar takes"; return $fe }
    $root = New-HordeSshdRoot
    $fe.root = $root
    $hubId = "3f2504e0-4f89-41d3-9a0c-0305e82c3301"
    # The stand-in for Horde's root: only its cli\attach.ps1, an echo. LF only: frames end at LF.
    $fakeRoot = Join-Path $root "horde"
    New-Item -ItemType Directory -Path (Join-Path $fakeRoot "cli") -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $fakeRoot "cli\attach.ps1"), "param([string]`$Device) foreach (`$l in `$input) { [Console]::Out.Write(`$l + [char]10); [Console]::Out.Flush() }")
    # The hub: its listener host key, and the enrolment files sshd reads.
    $hubHome = Join-Path $root "hub-home"
    New-Item -ItemType Directory -Path $hubHome | Out-Null
    $hi = Initialize-HordeSshHub -HordeHome $hubHome -HubId $hubId
    if (-not $hi.ok) { $fe.skip = "the hub's host key could not be made: " + $hi.reason; return $fe }
    $hostLine = $hi.line.Substring($hi.line.IndexOf(' ') + 1)
    $lp = Get-HordeSshListenPaths -HordeHome $hubHome
    # A node: its own home, key and pin. -Pin is the host key line it pins.
    $node = {
        param([string]$Name, [string]$DeviceId, [string]$Pin)
        $h = Join-Path $root $Name
        New-Item -ItemType Directory -Path $h | Out-Null
        $n = Initialize-HordeSshNode -HordeHome $h -DeviceId $DeviceId
        if (-not $n.ok) { throw ("node " + $Name + ": " + $n.reason) }
        $p = Add-HordeSshPin -HordeHome $h -HubId $hubId -HostKey $Pin
        if (-not $p.ok) { throw ("node " + $Name + " pin: " + $p.reason) }
        return [pscustomobject]@{ home = $h; key = $n.line.Substring($n.line.IndexOf(' ') + 1) }
    }
    $enrolled = & $node "node-enrolled" "1b9d6bcd-bbfd-4b2d-9b5d-ab8dfbbd4bed" $hostLine
    $stranger = & $node "node-stranger" "2c8e7a1b-3d4f-4a5b-9c6d-7e8f9a0b1c2d" $hostLine
    New-HordeSshdKey -Path (Join-Path $root "other_host_ed25519")
    $otherHost = ([System.IO.File]::ReadAllText((Join-Path $root "other_host_ed25519.pub")).Trim().Split(' ')[0..1]) -join ' '
    $misled = & $node "node-wrong-pin" "3d9f8b2c-4e5a-4b6c-8d7e-8f9a0b1c2d3e" $otherHost
    $revoked = & $node "node-revoked" "4e0a9c3d-5f6b-4c7d-9e8f-9a0b1c2d3e4f" $hostLine
    foreach ($e in @(@{ dev = "1b9d6bcd-bbfd-4b2d-9b5d-ab8dfbbd4bed"; key = $enrolled.key }, @{ dev = "3d9f8b2c-4e5a-4b6c-8d7e-8f9a0b1c2d3e"; key = $misled.key }, @{ dev = "4e0a9c3d-5f6b-4c7d-9e8f-9a0b1c2d3e4f"; key = $revoked.key })) {
        $r = Add-HordeSshEnrolment -HordeHome $hubHome -DeviceId $e.dev -Key $e.key -HordeRoot $fakeRoot
        if (-not $r.ok) { $fe.skip = "enrolment failed: " + $r.reason; return $fe }
    }
    # Revoked, then its line put back by hand: only RevokedKeys can refuse it now.
    $line = @(Read-HordeSshLines -Path $lp.authorized | Where-Object { $_.EndsWith(" horde-device-4e0a9c3d-5f6b-4c7d-9e8f-9a0b1c2d3e4f") })
    $rv = Remove-HordeSshEnrolment -HordeHome $hubHome -DeviceId "4e0a9c3d-5f6b-4c7d-9e8f-9a0b1c2d3e4f"
    if (-not $rv.ok -or $line.Count -ne 1) { $fe.skip = "revocation could not be set up: " + $rv.reason; return $fe }
    Write-HordeSshLines -Path $lp.authorized -Lines (@(Read-HordeSshLines -Path $lp.authorized) + $line)
    if (-not (Test-Path -LiteralPath $lp.revoked)) { Write-HordeSshLines -Path $lp.revoked -Lines @() }
    $port = Get-HordeFreeLoopbackPort
    $config = Write-HordeSshdConfig -Root $root -Port $port -ForceCommand "" -HostKey $lp.hostKey -AuthorizedKeys $lp.authorized -RevokedKeys $lp.revoked
    $syntax = Test-HordeSshdConfig -Config $config
    if (-not $syntax.ok) { $fe.skip = "sshd -t refused the far end's config: " + $syntax.text; return $fe }
    $fe.sshd = Start-HordeTestSshd -Config $config -LimitSeconds $script:HordeSshFarEndLimitSeconds
    $endpoint = $user + "@127.0.0.1:" + $port + "/" + $hubId
    $deadline = [datetime]::UtcNow.AddSeconds(20)
    $up = $null
    while ([datetime]::UtcNow -lt $deadline -and -not $fe.sshd.process.HasExited) {
        $up = Test-HordeSshBanner -Endpoint $endpoint
        if ($up.state -ceq "known" -and $up.value -eq $true) { break }
        Start-Sleep -Milliseconds 250
    }
    if ($null -eq $up -or $up.state -cne "known" -or $up.value -ne $true) { $fe.skip = "the far end's sshd did not answer on 127.0.0.1:" + $port + ": " + ((Stop-HordeTestSshd -Sshd $fe.sshd) -replace "`r?`n", " | "); return $fe }
    $fe.cases = @(
        [pscustomobject]@{ capability = "dial.out"; kind = "round-trip"; name = "a node dials the hub's listener through the port and frames round-trip"; homeDir = $enrolled.home; endpoint = $endpoint; expect = "carries"; refusal = "" }
        [pscustomobject]@{ capability = "auth.peer"; kind = "admits-enrolled"; name = "an enrolled key, with the hub's host key pinned, connects and the far end is the pinned one"; homeDir = $enrolled.home; endpoint = $endpoint; expect = "carries"; refusal = "" }
        [pscustomobject]@{ capability = "auth.peer"; kind = "refuses-unknown-client"; name = "a client key the hub never enrolled is refused"; homeDir = $stranger.home; endpoint = $endpoint; expect = "refused"; refusal = "(?i)permission denied" }
        [pscustomobject]@{ capability = "auth.peer"; kind = "refuses-changed-host"; name = "a hub whose host key is not the one pinned is refused"; homeDir = $misled.home; endpoint = $endpoint; expect = "refused"; refusal = "(?i)host key|identification" }
        [pscustomobject]@{ capability = "auth.peer"; kind = "refuses-revoked"; name = "a revoked key is refused, even with its authorized_keys line put back by hand"; homeDir = $revoked.home; endpoint = $endpoint; expect = "refused"; refusal = "(?i)permission denied" }
    )
    return $fe
}

function Stop-HordeSshFarEnd {
    # Ends the far end's sshd and everything it started, and removes its folder; returns what is left
    # alive (0 when the job is empty).
    param($FarEnd)
    $left = 0
    if ($null -ne $FarEnd.sshd) {
        $null = Stop-HordeTestSshd -Sshd $FarEnd.sshd
        $left = Get-HordeTestSshdLeft -Sshd $FarEnd.sshd
        Close-HordeTestSshd -Sshd $FarEnd.sshd
    }
    if ($FarEnd.root -ne "" -and (Split-Path -Leaf $FarEnd.root) -match '^horde-sshd-[0-9a-f]{12}$') { Remove-Item -LiteralPath $FarEnd.root -Recurse -Force -ErrorAction SilentlyContinue }
    return $left
}

if ($null -eq (Get-Variable -Name HordeFarEnds -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeFarEnds = @{} }
$script:HordeFarEnds[(Split-Path -Leaf (Split-Path -Parent $PSScriptRoot))] = [pscustomobject]@{ start = { Start-HordeSshFarEnd }; stop = { param($FarEnd) Stop-HordeSshFarEnd -FarEnd $FarEnd } }
