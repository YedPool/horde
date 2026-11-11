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
. (Join-Path $root "transports\Port.ps1")
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

# WHICH TRANSPORTS RAN THE FAR-END CASES (remote plan step R5). The far end of every case below is
# the transport's own listener, in this process. A transport whose accept is not yes - ssh's hub side
# is a server program with a forced command, steps R16 and R17 - has no far end here, so those cases do not run for
# it, and the suite says so by name at the end: a partial run must not read as a full one. Its yes
# claims still have to be shown, so a transport that skips them can claim nothing they would prove.
$script:farEndRan = New-Object System.Collections.ArrayList
$script:farEndSkipped = New-Object System.Collections.ArrayList

# A LIVE FAR END (remote plan R17c-3). A transport whose accept is not yes may bring one:
# transports/<name>/test/FarEnd.ps1, found by folder. Its cases run here, each a named check, and a
# capability is shown by them only when EVERY kind of evidence below passed for it: a yes with a kind
# missing, or failed, is a yes no case demonstrated, and the suite fails (coordinator, 2026-10-07: each
# capability its own evidence, and no flip without a named check behind it).
$script:HordeEvidenceKinds = @{
    "dial.out" = @("round-trip")
    "auth.peer" = @("admits-enrolled", "refuses-unknown-client", "refuses-changed-host", "refuses-revoked")
}
$script:HordeFarEnds = @{}

function Invoke-FarEndCases {
    # Run transport -Name's live far end, if it has one and claims something of it. Returns the
    # capabilities its cases showed. Every case is a Check; the far end's teardown is one too.
    param($Transport, [string]$Name)
    $shownHere = @{}
    $feFile = Join-Path $Transport.folder "test\FarEnd.ps1"
    if (-not (Test-Path -LiteralPath $feFile -PathType Leaf)) { return $shownHere }
    . $feFile
    $entry = $script:HordeFarEnds[$Name]
    Check ($null -ne $entry) "[$Name] its test\FarEnd.ps1 registers a far end under its own name"
    if ($null -eq $entry) { return $shownHere }
    $claimed = @($script:HordeEvidenceKinds.Keys | Where-Object { Test-HordeTransportCapability -Transport $Transport -Capability $_ })
    if ($claimed.Count -eq 0) { Write-Host ("  [SKIP] [" + $Name + "] the live far end did not run: none of " + (@($script:HordeEvidenceKinds.Keys) -join ", ") + " is declared yes") -ForegroundColor Yellow; return $shownHere }
    Write-Host ("--- [" + $Name + "] its live far end ---") -ForegroundColor Cyan
    $fe = & $entry.start
    if ("$($fe.skip)" -ne "") {
        Write-Host ("  [SKIP] [" + $Name + "] the live far end could not run here: " + $fe.skip) -ForegroundColor Yellow
        [void]$script:farEndSkipped.Add($Name + " live far end (" + $fe.skip + ")")
        $null = & $entry.stop $fe
        return $shownHere
    }
    [void]$script:farEndRan.Add($Name + " (live far end)")
    $passed = @{}
    $saved = $env:HORDE_HOME
    try {
        foreach ($c in @($fe.cases)) {
            $env:HORDE_HOME = $c.homeDir
            $o = Open-HordeTransportLink -Transport $Transport -Endpoint $c.endpoint -Role "node" -TimeoutMs 15000
            $ok = $false
            $detail = ""
            if ($c.expect -ceq "carries") {
                if ($o.state -ceq "known") {
                    $link = $o.value
                    try {
                        $sent = @("first", "{""v"":1,""kind"":""ping""}", (-join ([char[]](32..126))))
                        $got = New-Object System.Collections.ArrayList
                        foreach ($s in $sent) {
                            $null = Send-HordeLinkFrame -Link $link -Frame $s -TimeoutMs 15000
                            $a = Receive-HordeLinkFrame -Link $link -TimeoutMs 20000
                            if ($a.state -ceq "known") { [void]$got.Add($a.value) } else { [void]$got.Add("<" + $a.reason + ">") }
                        }
                        $ok = (($got -join "|") -ceq ($sent -join "|"))
                        $detail = ($got -join " | ")
                        if ($c.kind -ceq "admits-enrolled") {
                            $ok = $ok -and $link.peer.verified -eq $true -and "$($link.peer.identity)" -ne ""
                            $detail = $detail + "; peer " + $link.peer.identity + " verified=" + $link.peer.verified
                        }
                    } finally { Close-HordeLink -Link $link }
                } else { $detail = $o.reason }
            } else {
                $why = ""
                if ($o.state -ceq "known") {
                    $link = $o.value
                    try {
                        $null = Send-HordeLinkFrame -Link $link -Frame "anyone there" -TimeoutMs 15000
                        $a = Receive-HordeLinkFrame -Link $link -TimeoutMs 20000
                        if ($a.state -ceq "known") { $why = "" ; $detail = "a frame came back: " + $a.value } else { $why = "$($a.reason)" }
                    } finally { Close-HordeLink -Link $link }
                } else { $why = "$($o.reason)" }
                $ok = ($why -ne "" -and $why -match $c.refusal)
                if ($detail -eq "") { $detail = $why }
            }
            Check $ok ("[$Name] " + $c.capability + ", " + $c.kind + ": " + $c.name + " (" + $detail + ")")
            if ($ok) {
                if (-not $passed.ContainsKey($c.capability)) { $passed[$c.capability] = New-Object System.Collections.ArrayList }
                [void]$passed[$c.capability].Add($c.kind)
            }
        }
    } finally {
        $env:HORDE_HOME = $saved
        $left = & $entry.stop $fe
        Check ($left -eq 0) ("[$Name] the live far end is torn down: nothing it started is left alive (" + $left + " left)")
    }
    foreach ($cap in @($script:HordeEvidenceKinds.Keys)) {
        $need = @($script:HordeEvidenceKinds[$cap])
        $have = @(); if ($passed.ContainsKey($cap)) { $have = @($passed[$cap]) }
        $missing = @($need | Where-Object { $have -cnotcontains $_ })
        if ($missing.Count -eq 0) { $shownHere[$cap] = $true }
        elseif (Test-HordeTransportCapability -Transport $Transport -Capability $cap) { Write-Host ("         " + $cap + " lacks evidence of kind: " + ($missing -join ", ")) -ForegroundColor Red }
    }
    return $shownHere
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

    if (-not (Yes "accept")) {
        $why = "accept is " + (Get-HordeTransportSupport -Transport $t -Capability "accept") + " (" + $t.capabilities.capabilities.accept.evidence + ")"
        $la = Start-HordeTransportListener -Transport $t -Endpoint (New-Endpoint)
        Check ($la.state -ceq "unknown" -and "$($la.reason)" -like "*accept*") "[$n] accept not yes: this end may not listen, and the refusal names accept"
        foreach ($pair in @(@{ role = "node"; cap = "dial.out" }, @{ role = "hub"; cap = "dial.in" })) {
            if (-not (Yes $pair.cap)) {
                $o = Open-HordeTransportLink -Transport $t -Endpoint (New-Endpoint) -Role $pair.role -TimeoutMs 500
                Check ($o.state -ceq "unknown" -and "$($o.reason)" -like "*$($pair.cap)*") "[$n] a $($pair.role) may not dial: $($pair.cap) is not yes"
            }
        }
        foreach ($bad in @("..\x", "a b", "A")) {
            Check ((Test-HordeTransportReachable -Transport $t -Endpoint $bad).state -ceq "unknown") "[$n] probing '$bad' is unknown"
        }
        Write-Host ("  [SKIP] [" + $n + "] the in-process far-end cases did not run: " + $why) -ForegroundColor Yellow
        [void]$script:farEndSkipped.Add($n + " (" + $why + ")")
        $live = Invoke-FarEndCases -Transport $t -Name $n
        Write-Host "--- every yes was shown ---" -ForegroundColor Cyan
        foreach ($c in $caps) {
            if (Yes $c) { Check ($live.ContainsKey($c)) "[$n] $c is declared yes, and its live far end's named checks showed every kind of evidence it needs" }
        }
        continue
    }
    [void]$script:farEndRan.Add($n)

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
    $ka = $null
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
        # AN ACCEPT WITH NOBODY DIALLING WAITS OUT ITS TIME (T-0421). The dial above was waiting before the
        # accept began (the peer sets Ready only after it dialled), so the accept took it at once. The memory
        # transport then left that dial's wake-up signal unspent, and its next accept woke on it, found
        # nothing and gave up at once; the node's loop read the quick failure as a broken listener and
        # replaced it, and a hub dial landing on the old one was never answered (test-hub-serve under 5.1,
        # red 6 of 9 on 2026-11-06: "no frame within 30000 ms; the link is still open").
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $none = Receive-HordeTransportLink -Listener $listener -TimeoutMs 1500
        $sw.Stop()
        Check ($none.state -cne "known" -and $sw.ElapsedMilliseconds -ge 1200) ("[$n] an accept with nobody dialling waits out its time, even after an accept that found a dial already waiting (" + $sw.ElapsedMilliseconds + " ms of 1500)")
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
    # accept yes is shown by "the far end's dial is accepted" above, and every far-end case rests on it.
    if ($null -ne $ka -and $ka.state -eq "known") { $shown["accept"] = $true }
    foreach ($c in $caps) {
        if (Yes $c) { Check ($shown.ContainsKey($c)) "[$n] $c is declared yes, and a case above demonstrated it" }
    }
}
} finally {
    foreach ($p in @($script:peers)) { if (-not $p.stopped) { $null = Stop-Peer $p } }
}

Write-Host ""
Write-Host ("  far-end cases RAN for: " + ((@($script:farEndRan) | ForEach-Object { $_ }) -join ", ")) -ForegroundColor Cyan
if ($script:farEndSkipped.Count -gt 0) { Write-Host ("  far-end cases DID NOT RUN for: " + (@($script:farEndSkipped) -join "; ")) -ForegroundColor Yellow }
Check ($script:farEndRan.Count -ge 1) ("CONTROL: the far-end cases ran for at least one transport (" + $script:farEndRan.Count + ")")

Complete-HordeSuite -Success "every transport does what its capabilities say, and nothing is guessed"
