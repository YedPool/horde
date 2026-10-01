# DOES EVERY TRANSPORT DO WHAT ITS capabilities.json SAYS, AND NOTHING IT DOES NOT?
#
# Remote plan step R4: "a conformance suite generated from each transport's capabilities.json (every
# yes a positive test, every no an honest refusal)". This suite names no transport. It loads every
# transports/<name>/Transport.ps1 and runs the same cases against each:
#   - every capability declared yes must be DEMONSTRATED by a case here, or the suite fails. A yes
#     that no case can show (encrypt, survives.peer.restart today) is refused, not trusted.
#   - every capability declared anything else must be refused where it is required.
#   - the frame rules hold end to end: a frame of the full cap round-trips; a partial frame, a close,
#     an oversize line and a non-ASCII byte from the far end are unknown, never a guessed frame.
#
# THE FAR END RUNS ON ANOTHER THREAD. test/fixtures/transport/peer.ps1 runs in a second runspace of
# this process, so both ends of a link are live at once: a mebibyte written into a pipe needs a
# reader, and a single-threaded test would deadlock there. The peer misbehaves on purpose where a case
# says so, by writing raw bytes to its transport's channel.
#
# Every endpoint is a fresh random id, used only by this suite (CONTRIBUTING 9).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "remote\Transport.ps1")
foreach ($f in @(Get-HordeTransportFiles)) { . $f }

$peerScript = Join-Path $here "fixtures\transport\peer.ps1"
$script:peers = New-Object System.Collections.ArrayList

function New-Endpoint { return [guid]::NewGuid().ToString() }

function Start-Peer {
    param([string]$Name, [string]$Endpoint, [string]$Mode, [string]$Behavior)
    $ev = [pscustomobject]@{
        ready = (New-Object System.Threading.ManualResetEventSlim($false))
        go = (New-Object System.Threading.ManualResetEventSlim($false))
        again = (New-Object System.Threading.ManualResetEventSlim($false))
    }
    $ps = [PowerShell]::Create()
    [void]$ps.AddCommand($peerScript).AddParameter("Root", $root).AddParameter("Name", $Name).AddParameter("Endpoint", $Endpoint).AddParameter("Mode", $Mode).AddParameter("Behavior", $Behavior).AddParameter("Events", $ev)
    $h = $ps.BeginInvoke()
    $p = [pscustomobject]@{ ps = $ps; h = $h; ev = $ev; behavior = $Behavior; stopped = $false }
    [void]$script:peers.Add($p)
    $inTime = $ev.ready.Wait(30000)
    if (-not $inTime) { Write-Host ("         the " + $Behavior + " peer was not ready within 30 s") -ForegroundColor Red }
    return $p
}

function Stop-Peer {
    # Let the peer finish and collect what went wrong on its side. Returns the list of its errors.
    param($Peer)
    if ($Peer.stopped) { return @() }
    $Peer.stopped = $true
    $Peer.ev.go.Set()
    $errs = New-Object System.Collections.ArrayList
    if ($Peer.h.AsyncWaitHandle.WaitOne(40000)) {
        try { $null = $Peer.ps.EndInvoke($Peer.h) } catch { [void]$errs.Add($_.Exception.Message) }
    } else {
        [void]$errs.Add("the " + $Peer.behavior + " peer did not finish within 40 s")
        try { $Peer.ps.Stop() } catch { }
    }
    foreach ($e in @($Peer.ps.Streams.Error)) { [void]$errs.Add("$e") }
    $Peer.ps.Dispose()
    return @($errs)
}

function Check-Peer {
    param($Peer, [string]$What)
    $errs = @(Stop-Peer $Peer)
    Check ($errs.Count -eq 0) ("the far end of '" + $What + "' ran without an error")
    foreach ($e in $errs) { Write-Host ("         peer: " + $e) -ForegroundColor Red }
}

function Open-To {
    # Dial the endpoint as a node; the link, or $null with a failed check.
    param($T, [string]$Endpoint, [string]$Role = "node")
    $o = Open-HordeTransportLink -Transport $T -Endpoint $Endpoint -Role $Role -TimeoutMs 10000
    if ($o.state -ne "known") { Write-Host ("         open failed: " + $o.reason) -ForegroundColor Red; return $null }
    return (Get-HordeValue $o)
}

$names = @(Get-HordeTransportNames)
$folders = @(Get-HordeTransportFiles)
Write-Host ""
Write-Host ("--- " + $names.Count + " transport(s) loaded: " + ($names -join ", ") + " ---") -ForegroundColor Cyan
Check ($names.Count -ge 1) "at least one transport is loaded"
Check ($names.Count -eq $folders.Count) "every transports/<name>/Transport.ps1 registered exactly one transport"

try {
foreach ($n in $names) {
    $t = Get-HordeTransport -Name $n
    $caps = @($script:HordeTransportCapabilityNames)
    $shown = @{}
    function Yes { param([string]$Cap) return (Test-HordeTransportCapability -Transport $t -Capability $Cap) }

    Write-Host ""
    Write-Host ("=== transport '" + $n + "' ===") -ForegroundColor Cyan
    Write-Host ("  declares: " + (($caps | ForEach-Object { $_ + "=" + (Get-HordeTransportSupport -Transport $t -Capability $_) }) -join ", ")) -ForegroundColor DarkGray

    Write-Host "--- every word but yes is refused where it is required ---" -ForegroundColor Cyan
    # The protocol's own cap, read from the contract (schema/link-frame.v1, step R1), not copied here.
    $limits = (Get-HordeSchema -Name "link-frame.v1").'x-horde-limits'
    Check ($t.maxFrameBytes -ge [int]$limits.frameBytes) "[$n] it carries a frame of the protocol's cap, $($limits.frameBytes) bytes"
    Check ($t.maxFrameBytes -le [int]$limits.frameBytesCeiling) "[$n] and no more than the protocol's ceiling, $($limits.frameBytesCeiling) bytes"
    foreach ($c in $caps) {
        $word = Get-HordeTransportSupport -Transport $t -Capability $c
        $r = Resolve-HordeTransport -Name $n -Require @($c)
        if ($word -ceq "yes") { Check ($r.state -ceq "known") "[$n] requiring $c (yes) resolves" }
        else { Check ($r.state -ceq "unknown" -and "$($r.reason)" -like "*$c*$word*") "[$n] requiring $c ($word) is refused, naming the word" }
    }
    $lp = Resolve-HordeLinkTransport -Name $n
    if (Yes "auth.peer") { Check ($lp.state -ceq "known") "[$n] the production link path may pick it: auth.peer is yes" }
    else { Check ($lp.state -ceq "unknown") "[$n] the production link path refuses it: auth.peer is not yes" }

    Write-Host "--- dialling, as a node and as a hub ---" -ForegroundColor Cyan
    foreach ($pair in @(@{ role = "node"; cap = "dial.out" }, @{ role = "hub"; cap = "dial.in" })) {
        $ep = New-Endpoint
        if (-not (Yes $pair.cap)) {
            $o = Open-HordeTransportLink -Transport $t -Endpoint $ep -Role $pair.role -TimeoutMs 500
            Check ($o.state -ceq "unknown" -and "$($o.reason)" -like "*$($pair.cap)*") "[$n] a $($pair.role) may not dial: $($pair.cap) is not yes"
            continue
        }
        $peer = Start-Peer -Name $n -Endpoint $ep -Mode "listen" -Behavior "echo"
        $link = Open-To $t $ep $pair.role
        Check ($null -ne $link) "[$n] a $($pair.role) dials a listening endpoint"
        if ($null -ne $link) {
            $sent = @("first", "{""v"":1,""kind"":""ping""}", (-join ([char[]](32..126))))
            $got = New-Object System.Collections.ArrayList
            foreach ($s in $sent) {
                $null = Send-HordeLinkFrame -Link $link -Frame $s -TimeoutMs 10000
                $a = Receive-HordeLinkFrame -Link $link -TimeoutMs 10000
                if ($a.state -eq "known") { [void]$got.Add($a.value) } else { [void]$got.Add("<" + $a.reason + ">") }
            }
            Check (($got -join "|") -ceq ($sent -join "|")) "[$n] frames round-trip in order and unchanged, every printable ASCII character included ($($pair.role))"
            if ($pair.role -eq "node") {
                if (Yes "auth.peer") {
                    Check ($link.peer.verified -eq $true -and "$($link.peer.identity)" -ne "") "[$n] auth.peer yes: the dialled end is verified and named ($($link.peer.how))"
                    if ($link.peer.verified -eq $true) { $shown["auth.peer.dial"] = $true }
                } else {
                    Check ($link.peer.verified -eq $false) "[$n] auth.peer not yes: the dialled end is not claimed verified"
                }
            }
            if (($got -join "|") -ceq ($sent -join "|")) { $shown[$pair.cap] = $true }
            Close-HordeLink -Link $link
        }
        Check-Peer $peer "echo for a $($pair.role)"
    }

    Write-Host "--- the whole cap, and refusals at the sender ---" -ForegroundColor Cyan
    $ep = New-Endpoint
    $peer = Start-Peer -Name $n -Endpoint $ep -Mode "listen" -Behavior "echo"
    $link = Open-To $t $ep
    if ($null -ne $link) {
        $big = "y" * $t.maxFrameBytes
        $s = Send-HordeLinkFrame -Link $link -Frame $big -TimeoutMs 30000
        $a = Receive-HordeLinkFrame -Link $link -TimeoutMs 30000
        Check ($s.state -ceq "known" -and $a.state -ceq "known" -and $a.value -ceq $big) "[$n] a frame of exactly $($t.maxFrameBytes) bytes round-trips intact"
        Check (Throws { Send-HordeLinkFrame -Link $link -Frame ($big + "y") } "over the") "[$n] one byte more is refused at the sender"
        Check (Throws { Send-HordeLinkFrame -Link $link -Frame ("a" + [char]10 + "b") } "LF") "[$n] a frame holding an LF is refused at the sender"
        Check (Throws { Send-HordeLinkFrame -Link $link -Frame ("caf" + [char]0xE9) } "ASCII") "[$n] a frame holding a non-ASCII character is refused at the sender"
        $null = Send-HordeLinkFrame -Link $link -Frame "after" -TimeoutMs 10000
        $a = Receive-HordeLinkFrame -Link $link -TimeoutMs 10000
        Check ($a.state -ceq "known" -and $a.value -ceq "after") "[$n] the refused frames sent nothing: the next frame arrives as the next frame"
        Close-HordeLink -Link $link
    } else { Check $false "[$n] a link for the cap cases" }
    Check-Peer $peer "echo for the cap"

    Write-Host "--- accepting: the far end dials in ---" -ForegroundColor Cyan
    $ep = New-Endpoint
    $la = Start-HordeTransportListener -Transport $t -Endpoint $ep
    Check ($la.state -ceq "known") "[$n] this end listens"
    if ($la.state -eq "known") {
        $listener = Get-HordeValue $la
        $second = Start-HordeTransportListener -Transport $t -Endpoint $ep
        Check ($second.state -ceq "unknown" -and "$($second.reason)" -like "*in use*") "[$n] a second listener on the same endpoint is refused as in use"
        $pr = Test-HordeTransportReachable -Transport $t -Endpoint $ep
        Check ($pr.state -ceq "known" -and $pr.value -eq $true) "[$n] a probe finds the listening endpoint reachable"
        $peer = Start-Peer -Name $n -Endpoint $ep -Mode "dial" -Behavior "echo"
        $ka = Receive-HordeTransportLink -Listener $listener -TimeoutMs 10000
        Check ($ka.state -ceq "known") "[$n] the far end's dial is accepted"
        if ($ka.state -eq "known") {
            $link = Get-HordeValue $ka
            $null = Send-HordeLinkFrame -Link $link -Frame "ping" -TimeoutMs 10000
            $a = Receive-HordeLinkFrame -Link $link -TimeoutMs 10000
            Check ($a.state -ceq "known" -and $a.value -ceq "ping") "[$n] an accepted link carries frames"
            if (Yes "auth.peer") {
                Check ($link.peer.verified -eq $true -and "$($link.peer.identity)" -ne "") "[$n] auth.peer yes: the accepted end is verified and named ($($link.peer.how))"
                if ($link.peer.verified -eq $true) { $shown["auth.peer.accept"] = $true }
            } else { Check ($link.peer.verified -eq $false) "[$n] auth.peer not yes: the accepted end is not claimed verified" }
            Close-HordeLink -Link $link
        }
        Check-Peer $peer "a dial in"
        Stop-HordeTransportListener -Listener $listener
        $pr = Test-HordeTransportReachable -Transport $t -Endpoint $ep
        Check ($pr.state -ceq "known" -and $pr.value -eq $false) "[$n] after the listener stops, a probe finds it unreachable"
    }
    $o = Open-HordeTransportLink -Transport $t -Endpoint (New-Endpoint) -Role "node" -TimeoutMs 500
    Check ($o.state -ceq "unknown" -and "$($o.reason)" -ne "") "[$n] dialling an endpoint nobody listens on is unknown with a reason, not an error"
    foreach ($bad in @("..\x", "a b", "A")) {
        Check ((Start-HordeTransportListener -Transport $t -Endpoint $bad).state -ceq "unknown") "[$n] listening on the malformed endpoint '$bad' is refused"
        Check ((Test-HordeTransportReachable -Transport $t -Endpoint $bad).state -ceq "unknown") "[$n] probing '$bad' is unknown"
    }

    Write-Host "--- the far end misbehaves: nothing is guessed ---" -ForegroundColor Cyan
    $ep = New-Endpoint
    $peer = Start-Peer -Name $n -Endpoint $ep -Mode "listen" -Behavior "partial"
    $link = Open-To $t $ep
    if ($null -ne $link) {
        $a = Receive-HordeLinkFrame -Link $link -TimeoutMs 10000
        Check ($a.state -ceq "unknown" -and "$($a.reason)" -like "*partial frame of 3 bytes*") "[$n] 3 bytes and then a close are a partial frame: unknown, not 'abc'"
        Close-HordeLink -Link $link
    } else { Check $false "[$n] a link for the partial case" }
    Check-Peer $peer "partial"

    $ep = New-Endpoint
    $peer = Start-Peer -Name $n -Endpoint $ep -Mode "listen" -Behavior "one-then-close"
    $link = Open-To $t $ep
    if ($null -ne $link) {
        $a = Receive-HordeLinkFrame -Link $link -TimeoutMs 10000
        $a2 = Receive-HordeLinkFrame -Link $link -TimeoutMs 10000
        Check ($a.state -ceq "known" -and $a.value -ceq "one") "[$n] the whole frame sent before a close arrives"
        Check ($a2.state -ceq "unknown" -and "$($a2.reason)" -like "*closed*") "[$n] and then the close is unknown, never absent"
        $h = Get-HordeLinkHealth -Link $link
        Check ($h.state -ceq "known" -and $h.value.state -ceq "closed") "[$n] health then reads closed"
        Close-HordeLink -Link $link
    } else { Check $false "[$n] a link for the close case" }
    Check-Peer $peer "one-then-close"

    $ep = New-Endpoint
    $peer = Start-Peer -Name $n -Endpoint $ep -Mode "listen" -Behavior "close"
    $link = Open-To $t $ep
    if ($null -ne $link) {
        if (Yes "keepalive") {
            $seen = $false
            $until = (Get-Date).AddSeconds(5)
            while (-not $seen -and (Get-Date) -lt $until) {
                $h = Get-HordeLinkHealth -Link $link
                if ($h.state -eq "known" -and $h.value.state -eq "closed") { $seen = $true } else { Start-Sleep -Milliseconds 50 }
            }
            Check ($seen) "[$n] keepalive yes: a far end that closes is noticed within 5 s, with no frame sent"
            if ($seen) { $shown["keepalive"] = $true }
        } else {
            Write-Host "  [$n] keepalive not yes: no claim to test" -ForegroundColor DarkGray
        }
        Close-HordeLink -Link $link
    } else { Check $false "[$n] a link for the keepalive case" }
    Check-Peer $peer "close"

    $ep = New-Endpoint
    $peer = Start-Peer -Name $n -Endpoint $ep -Mode "listen" -Behavior "oversize"
    $link = Open-To $t $ep
    if ($null -ne $link) {
        $a = Receive-HordeLinkFrame -Link $link -TimeoutMs 20000
        Check ($a.state -ceq "unknown" -and "$($a.reason)" -like "*over the*cap*") "[$n] a line over the cap from the far end is unknown"
        Check ($link.closed) "[$n] and closes the link"
    } else { Check $false "[$n] a link for the oversize case" }
    Check-Peer $peer "oversize"

    $ep = New-Endpoint
    $peer = Start-Peer -Name $n -Endpoint $ep -Mode "listen" -Behavior "nonascii"
    $link = Open-To $t $ep
    if ($null -ne $link) {
        $a = Receive-HordeLinkFrame -Link $link -TimeoutMs 10000
        Check ($a.state -ceq "unknown" -and "$($a.reason)" -like "*not ASCII*" -and $link.closed) "[$n] a non-ASCII byte from the far end is unknown and closes the link"
    } else { Check $false "[$n] a link for the non-ASCII case" }
    Check-Peer $peer "nonascii"

    $ep = New-Endpoint
    $peer = Start-Peer -Name $n -Endpoint $ep -Mode "listen" -Behavior "hold"
    $link = Open-To $t $ep
    if ($null -ne $link) {
        $a = Receive-HordeLinkFrame -Link $link -TimeoutMs 300
        Check ($a.state -ceq "unknown" -and "$($a.reason)" -like "*no frame within 300 ms*") "[$n] a quiet far end is unknown after the timeout, and the link stays open"
        $h = Get-HordeLinkHealth -Link $link
        if (Yes "keepalive") { Check ($h.state -ceq "known" -and $h.value.state -ceq "open") "[$n] keepalive yes: a quiet but live link is known open" }
        else { Check ($h.state -ceq "unknown") "[$n] keepalive not yes: a quiet link is unknown, not open" }
        $peer.ev.go.Set()
        $a = Receive-HordeLinkFrame -Link $link -TimeoutMs 10000
        Check ($a.state -ceq "known" -and $a.value -ceq "late") "[$n] the frame that comes later is still received"
        $null = Send-HordeLinkFrame -Link $link -Frame "ack" -TimeoutMs 10000
        Close-HordeLink -Link $link
    } else { Check $false "[$n] a link for the quiet case" }
    Check-Peer $peer "hold"

    Write-Host "--- a far end that restarts ---" -ForegroundColor Cyan
    $ep = New-Endpoint
    $peer = Start-Peer -Name $n -Endpoint $ep -Mode "listen" -Behavior "restart"
    $link = Open-To $t $ep
    if ($null -ne $link) {
        $again = $peer.ev.again.Wait(20000)
        Check ($again) "[$n] the far end restarted its listener"
        $a = Receive-HordeLinkFrame -Link $link -TimeoutMs 3000
        if (Yes "survives.peer.restart") {
            Check $false "[$n] survives.peer.restart is yes, and no case here can show a link carrying on across a restart"
        } else {
            Check ($a.state -ceq "unknown" -and "$($a.reason)" -like "*closed*") "[$n] survives.peer.restart not yes: the old link reads closed, and no frame of the new one leaks into it"
        }
        Close-HordeLink -Link $link
        $fresh = Open-To $t $ep
        if ($null -ne $fresh) {
            $a = Receive-HordeLinkFrame -Link $fresh -TimeoutMs 10000
            Check ($a.state -ceq "known" -and $a.value -ceq "fresh") "[$n] a new link to the restarted far end works"
            Close-HordeLink -Link $fresh
        } else { Check $false "[$n] a new link to the restarted far end" }
    } else { Check $false "[$n] a link for the restart case" }
    Check-Peer $peer "restart"

    Write-Host "--- every yes was shown ---" -ForegroundColor Cyan
    if ($shown.ContainsKey("auth.peer.dial") -and $shown.ContainsKey("auth.peer.accept")) { $shown["auth.peer"] = $true }
    foreach ($c in $caps) {
        if (Yes $c) { Check ($shown.ContainsKey($c)) "[$n] $c is declared yes, and a case above demonstrated it" }
    }
}
} finally {
    foreach ($p in @($script:peers)) { if (-not $p.stopped) { $null = Stop-Peer $p } }
}

Complete-HordeSuite -Success "every transport does what its capabilities say, and nothing is guessed"
