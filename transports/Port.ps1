# transports/Port.ps1 - the transport port: how the protocol reaches another Horde, whatever carries it.
#
# WHAT A TRANSPORT IS (remote-sessions design, section 2.1; plan step R4). A transport turns "reach
# node D" into an open, ordered byte stream, and says what it knows about that stream. It knows
# nothing about verbs, sessions, terminals or engines. Each one is a folder, transports/<name>/,
# holding Transport.ps1 (its code) and capabilities.json (what it can do, as data, checked against
# schema/transport-capabilities.v1). This file names no transport: a second one is a new folder, not
# an edit here (the design's decision 10, extending CONTRIBUTING 14).
#
# WHY HERE AND NOT IN remote/. The port calls the script blocks each transport registers, and
# test/test-link-contracts.ps1 (step R1) holds every file in remote/ to "starts no program and no
# shell", which counts any call with &. That rule is right for the protocol: remote/ must never run
# code a frame names. The port runs only code a transports/<name>/ folder registered at load time,
# so it lives with the transports it dispatches to, and remote/ keeps its tripwire unweakened.
#
# THE SPLIT. A transport moves BYTES. This port turns bytes into FRAMES, once, for every transport:
#   - a frame is one line of printable-and-control ASCII, LF-terminated, at most maxFrameBytes long
#     with the LF excluded (schema/link-frame.v1, design 6.1). The port does not parse the line: that
#     is the codec's (remote/Protocol.ps1, step R2), so this step needs nothing from it.
#   - the sender refuses, by throwing, a frame that could not arrive as itself: one holding an LF
#     (it would arrive as two), one holding a non-ASCII character, or one over the cap.
#   - the receiver answers with core/tristate, and NEVER GUESSES. A frame is known only when its LF
#     arrived. Everything else is unknown with the reason: no frame yet ("no frame within N ms"), a
#     link that closed, a link that closed after part of a frame ("partial frame of N bytes"), a line
#     over the cap, a non-ASCII byte. A closed link is unknown, not absent: at the byte level an
#     orderly close and a crash look the same, and only the protocol's bye can say which it was.
#     After a framing error the link is closed, because the next byte cannot be placed in a frame.
#
# THE OPERATIONS. Open (dial) and Listen / Accept give a link; a link has Send, Receive, Close and
# Health. Probe says whether an endpoint is reachable without opening anything. Every one that can
# fail returns a tristate answer; none throws for a failure of the far end.
#
# CAPABILITIES ARE CLAIMS, AND ONLY "yes" COUNTS. unverified, declined and no all read as "does not
# have it" (hosts-research 5.1's rule). The production path to a node asks for auth.peer
# (Resolve-HordeLinkTransport), so a transport that declines it - the in-process pair that exists for
# tests - cannot be picked there. test/test-transport-conformance.ps1 is generated from every
# transport's capabilities.json: each "yes" must be demonstrated, and each other word must be refused
# where it is required.
#
# ADAPTER CONTRACT. transports/<name>/Transport.ps1 is dot-sourced at script level (so its helper
# functions outlive the call - a file dot-sourced inside a function loses them when it returns) and
# calls Register-HordeTransport with five script blocks:
#   Open    param($Endpoint, [int]$TimeoutMs)   -> { ok; channel; peer; reason }
#   Probe   param($Endpoint)                    -> a tristate answer: known true/false, or unknown
#   Listen  param($Endpoint)                    -> { ok; listener; reason }
#   Accept  param($ListenerState, [int]$TimeoutMs) -> { ok; channel; peer; reason }
#   Stop    param($ListenerState)
# A channel is { state; read; write; close }:
#   read    param($Channel, [int]$WaitMs) -> { kind = data | eof | none | error; bytes; reason }
#   write   param($Channel, [byte[]]$Bytes) -> $null when written, or a Task to wait on; throws on failure
#   close   param($Channel)
# A peer is { verified = $true | $false; identity; how }.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Tristate.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Schema.ps1")

if ($null -eq (Get-Variable -Name HordeTransports -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeTransports = @{} }
$script:HordeTransportCapabilityNames = @("auth.peer", "encrypt", "dial.out", "dial.in", "keepalive", "survives.peer.restart")
# What a link between a hub and a node must have. A transport without it is never picked there.
$script:HordeLinkRequires = @("auth.peer")
# Strict ASCII both ways: a non-ASCII character or byte throws instead of turning into '?'.
$script:HordeLinkAscii = [System.Text.Encoding]::GetEncoding("us-ascii", (New-Object System.Text.EncoderExceptionFallback), (New-Object System.Text.DecoderExceptionFallback))
$script:HordeLinkLf = [byte]10

function Get-HordeTransportRoot {
    return $PSScriptRoot
}

function Get-HordeTransportFiles {
    # Every transport's Transport.ps1, for the caller to dot-source at script level:
    #   foreach ($f in @(Get-HordeTransportFiles)) { . $f }
    param([string]$Root = (Get-HordeTransportRoot))
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $Root -Directory | Sort-Object Name | ForEach-Object { Join-Path $_.FullName "Transport.ps1" } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
}

function Test-HordeTransportCapabilities {
    # Findings for a parsed capabilities.json read from -Folder: the schema's, plus the rule the schema
    # cannot say - the transport it names is its own folder.
    param($Capabilities, [string]$Folder)
    $schema = Get-HordeSchema -Name "transport-capabilities.v1"
    $findings = @(Test-HordeSchema -Value $Capabilities -Schema $schema)
    if ($findings.Count -gt 0) { return $findings }
    $leaf = Split-Path -Leaf $Folder
    if ("$($Capabilities.transport)" -cne $leaf) { return @("capabilities.json names the transport '" + $Capabilities.transport + "' but sits in the folder '" + $leaf + "'") }
    return @()
}

function Register-HordeTransport {
    # Called by a transport's own Transport.ps1. Throws, naming every finding, when its
    # capabilities.json is missing or invalid: a transport that cannot say what it does is not one.
    param(
        [Parameter(Mandatory = $true)][string]$Folder,
        [Parameter(Mandatory = $true)][scriptblock]$Open,
        [Parameter(Mandatory = $true)][scriptblock]$Probe,
        [Parameter(Mandatory = $true)][scriptblock]$Listen,
        [Parameter(Mandatory = $true)][scriptblock]$Accept,
        [Parameter(Mandatory = $true)][scriptblock]$Stop
    )
    $capPath = Join-Path $Folder "capabilities.json"
    if (-not (Test-Path -LiteralPath $capPath -PathType Leaf)) { throw ("transport folder '" + $Folder + "' has no capabilities.json") }
    $caps = [System.IO.File]::ReadAllText($capPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $findings = @(Test-HordeTransportCapabilities -Capabilities $caps -Folder $Folder)
    if ($findings.Count -gt 0) { throw ("transport '" + (Split-Path -Leaf $Folder) + "' refused: " + ($findings -join "; ")) }
    # Once per name. A second registration used to replace the first silently, so a stray copy of a
    # folder could swap the transport every caller resolves by that name (review of PR #42).
    if ($script:HordeTransports.ContainsKey("$($caps.transport)")) {
        throw ("transport '" + $caps.transport + "' is already registered, from " + $script:HordeTransports["$($caps.transport)"].folder + "; the first registration stands")
    }
    $t = [pscustomobject]@{
        PSTypeName = "Horde.Transport"; name = "$($caps.transport)"; folder = $Folder; capabilities = $caps
        maxFrameBytes = [int]$caps.maxFrameBytes; open = $Open; probe = $Probe; listen = $Listen; accept = $Accept; stop = $Stop
    }
    $script:HordeTransports[$t.name] = $t
    return $t
}

function Get-HordeTransportNames {
    return @($script:HordeTransports.Keys | Sort-Object)
}

function Get-HordeTransport {
    # A registered transport by name. Throws for a name nobody registered: a caller asking for a
    # transport that is not loaded is a programming error, not a state of the world.
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not $script:HordeTransports.ContainsKey($Name)) { throw ("no transport named '" + $Name + "' is loaded") }
    return $script:HordeTransports[$Name]
}

function Get-HordeTransportSupport {
    # The support word a transport declares for one capability: yes, no, declined or unverified.
    param([Parameter(Mandatory = $true)]$Transport, [Parameter(Mandatory = $true)][string]$Capability)
    if ($script:HordeTransportCapabilityNames -cnotcontains $Capability) { throw ("'" + $Capability + "' is not a transport capability") }
    return "$($Transport.capabilities.capabilities.$Capability.support)"
}

function Test-HordeTransportCapability {
    # True only for "yes". unverified is treated as no (hosts-research 5.1), and so are no and declined.
    param([Parameter(Mandatory = $true)]$Transport, [Parameter(Mandatory = $true)][string]$Capability)
    return ((Get-HordeTransportSupport -Transport $Transport -Capability $Capability) -ceq "yes")
}

function Resolve-HordeTransport {
    # A transport by name that has every capability in -Require, as a tristate answer. -Require is
    # mandatory so a caller states what it needs; @() means nothing.
    param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Require)
    if (-not $script:HordeTransports.ContainsKey($Name)) { return (New-HordeUnknown -Reason ("no transport named '" + $Name + "' is loaded")) }
    $t = $script:HordeTransports[$Name]
    foreach ($c in $Require) {
        if (-not (Test-HordeTransportCapability -Transport $t -Capability $c)) {
            $cap = $t.capabilities.capabilities.$c
            return (New-HordeUnknown -Reason ("transport '" + $Name + "' does not offer " + $c + " (it says " + $cap.support + ": " + $cap.evidence + ")"))
        }
    }
    return (New-HordeKnown -Value $t)
}

function Resolve-HordeLinkTransport {
    # The one way a hub or node picks the transport for a link. It requires auth.peer, so a transport
    # that cannot identify its peer - the in-process test pair declines it - is never chosen here.
    param([Parameter(Mandatory = $true)][string]$Name)
    return (Resolve-HordeTransport -Name $Name -Require $script:HordeLinkRequires)
}

function Invoke-HordeTransportOp {
    # Run one adapter script block. An adapter that throws is a failure to reach the far end, never a
    # crash of the caller: it comes back as { ok = $false; reason }.
    param([scriptblock]$Op, [object[]]$ArgList, [string]$What)
    try { return (& $Op @ArgList) }
    catch { return [pscustomobject]@{ ok = $false; channel = $null; peer = $null; listener = $null; reason = ($What + " failed: " + $_.Exception.Message) } }
}

function New-HordeLink {
    param($Transport, [string]$Role, [string]$Endpoint, $Channel, $Peer)
    $peerRec = $Peer
    if ($null -eq $peerRec) { $peerRec = [pscustomobject]@{ verified = $false; identity = ""; how = "the transport reported no peer" } }
    return [pscustomobject]@{
        PSTypeName = "Horde.Link"; transport = $Transport.name; role = $Role; endpoint = $Endpoint; channel = $Channel; peer = $peerRec
        maxFrameBytes = $Transport.maxFrameBytes; keepalive = (Test-HordeTransportCapability -Transport $Transport -Capability "keepalive")
        buffer = (New-Object 'System.Collections.Generic.List[byte]'); closed = $false; closedReason = ""; closedAt = $null
        openedAt = [datetime]::UtcNow; lastFrameAt = $null; pendingWrite = $null
    }
}

function Test-HordeTransportReachable {
    # Probe: can the endpoint be reached, without opening a link? A tristate answer.
    param([Parameter(Mandatory = $true)]$Transport, [Parameter(Mandatory = $true)][string]$Endpoint)
    try { $a = & $Transport.probe $Endpoint }
    catch { return (New-HordeUnknown -Reason ("probing " + $Transport.name + " endpoint '" + $Endpoint + "'") -ErrorRecord $_) }
    if (-not (Test-HordeAnswer $a)) { return (New-HordeUnknown -Reason ("transport " + $Transport.name + " answered a probe with something that is not an answer")) }
    return $a
}

function Open-HordeTransportLink {
    # Dial -Endpoint. -Role says who is dialling: "node" needs dial.out, "hub" needs dial.in (design
    # 1.2: nodes dial out; the hub dialling is a capability a transport must claim). Returns a tristate
    # answer: known link, or unknown with the reason.
    param(
        [Parameter(Mandatory = $true)]$Transport,
        [Parameter(Mandatory = $true)][string]$Endpoint,
        [Parameter(Mandatory = $true)][ValidateSet("node", "hub")][string]$Role,
        [int]$TimeoutMs = 15000
    )
    $need = "dial.out"
    if ($Role -eq "hub") { $need = "dial.in" }
    if (-not (Test-HordeTransportCapability -Transport $Transport -Capability $need)) {
        $cap = $Transport.capabilities.capabilities.$need
        return (New-HordeUnknown -Reason ("transport " + $Transport.name + " cannot be dialled by a " + $Role + ": " + $need + " is " + $cap.support + " (" + $cap.evidence + ")"))
    }
    $r = Invoke-HordeTransportOp -Op $Transport.open -ArgList @($Endpoint, $TimeoutMs) -What ("opening " + $Transport.name + " endpoint '" + $Endpoint + "'")
    if (-not $r.ok) { return (New-HordeUnknown -Reason ("no link to " + $Transport.name + " endpoint '" + $Endpoint + "': " + $r.reason)) }
    return (New-HordeKnown -Value (New-HordeLink -Transport $Transport -Role $Role -Endpoint $Endpoint -Channel $r.channel -Peer $r.peer))
}

function Start-HordeTransportListener {
    # Listen on -Endpoint. A tristate answer: known listener, or unknown (the endpoint is taken, ...).
    param([Parameter(Mandatory = $true)]$Transport, [Parameter(Mandatory = $true)][string]$Endpoint)
    $r = Invoke-HordeTransportOp -Op $Transport.listen -ArgList @($Endpoint) -What ("listening on " + $Transport.name + " endpoint '" + $Endpoint + "'")
    if (-not $r.ok) { return (New-HordeUnknown -Reason ("cannot listen on " + $Transport.name + " endpoint '" + $Endpoint + "': " + $r.reason)) }
    return (New-HordeKnown -Value ([pscustomobject]@{ PSTypeName = "Horde.Listener"; transport = $Transport; endpoint = $Endpoint; state = $r.listener; stopped = $false }))
}

function Receive-HordeTransportLink {
    # Accept one link on a listener. A tristate answer: known link, or unknown (no peer came in time).
    param([Parameter(Mandatory = $true)]$Listener, [int]$TimeoutMs = 15000)
    if ($Listener.stopped) { return (New-HordeUnknown -Reason "the listener is stopped") }
    $t = $Listener.transport
    $r = Invoke-HordeTransportOp -Op $t.accept -ArgList @($Listener.state, $TimeoutMs) -What ("accepting on " + $t.name + " endpoint '" + $Listener.endpoint + "'")
    if (-not $r.ok) { return (New-HordeUnknown -Reason ("no link accepted on " + $t.name + " endpoint '" + $Listener.endpoint + "': " + $r.reason)) }
    return (New-HordeKnown -Value (New-HordeLink -Transport $t -Role "accept" -Endpoint $Listener.endpoint -Channel $r.channel -Peer $r.peer))
}

function Stop-HordeTransportListener {
    param([Parameter(Mandatory = $true)]$Listener)
    if ($Listener.stopped) { return }
    $Listener.stopped = $true
    try { & $Listener.transport.stop $Listener.state } catch { }
}

function Set-HordeLinkClosed {
    # Mark a link closed, once, with the first reason; the channel is closed too.
    param($Link, [string]$Reason)
    if ($Link.closed) { return }
    $Link.closed = $true
    $Link.closedReason = $Reason
    $Link.closedAt = [datetime]::UtcNow
    try { & $Link.channel.close $Link.channel } catch { }
}

function Update-HordeLinkInput {
    # Move whatever the channel has into the link's buffer, waiting up to -WaitMs for something.
    # Returns $true if any bytes arrived.
    param($Link, [int]$WaitMs)
    if ($Link.closed) { return $false }
    try { $r = & $Link.channel.read $Link.channel $WaitMs }
    catch { Set-HordeLinkClosed -Link $Link -Reason ("the link failed while reading: " + $_.Exception.Message); return $false }
    switch ("$($r.kind)") {
        "data"  { $Link.buffer.AddRange([byte[]]$r.bytes); return $true }
        "eof"   { Set-HordeLinkClosed -Link $Link -Reason "the far end closed the link"; return $false }
        "error" { Set-HordeLinkClosed -Link $Link -Reason ("the link failed while reading: " + $r.reason); return $false }
    }
    return $false
}

function Receive-HordeLinkFrame {
    # The next frame, as a tristate answer: known <the line, without its LF>, or unknown with the
    # reason. Waits up to -TimeoutMs. Never absent: see the file header.
    param([Parameter(Mandatory = $true)]$Link, [int]$TimeoutMs = 30000)
    $deadline = [datetime]::UtcNow.AddMilliseconds([Math]::Max(0, $TimeoutMs))
    while ($true) {
        $lf = $Link.buffer.IndexOf($script:HordeLinkLf)
        if ($lf -gt $Link.maxFrameBytes -or ($lf -lt 0 -and $Link.buffer.Count -gt $Link.maxFrameBytes)) {
            $n = $lf
            if ($n -lt 0) { $n = $Link.buffer.Count }
            $Link.buffer.Clear()
            $why = "a frame over the " + $Link.maxFrameBytes + "-byte cap arrived (" + $n + " bytes without an LF); the link was closed, since the next byte cannot be placed"
            Set-HordeLinkClosed -Link $Link -Reason $why
            return (New-HordeUnknown -Reason $why)
        }
        if ($lf -ge 0) {
            $bytes = $Link.buffer.GetRange(0, $lf).ToArray()
            $Link.buffer.RemoveRange(0, $lf + 1)
            try { $text = $script:HordeLinkAscii.GetString($bytes) }
            catch {
                $Link.buffer.Clear()
                $why = "a frame held a byte that is not ASCII; the link was closed"
                Set-HordeLinkClosed -Link $Link -Reason $why
                return (New-HordeUnknown -Reason $why)
            }
            $Link.lastFrameAt = [datetime]::UtcNow
            return (New-HordeKnown -Value $text -ObservedAt $Link.lastFrameAt)
        }
        if ($Link.closed) {
            $n = $Link.buffer.Count
            $Link.buffer.Clear()
            if ($n -gt 0) { return (New-HordeUnknown -Reason ("a partial frame of " + $n + " bytes arrived and then the link closed (" + $Link.closedReason + "); it is discarded, not guessed at")) }
            return (New-HordeUnknown -Reason ("the link is closed (" + $Link.closedReason + "); no frame"))
        }
        $left = [int](($deadline - [datetime]::UtcNow).TotalMilliseconds)
        if ($left -le 0) {
            $last = "no frame yet"
            if ($null -ne $Link.lastFrameAt) { $last = "last frame at " + $Link.lastFrameAt.ToString("o") }
            return (New-HordeUnknown -Reason ("no frame within " + $TimeoutMs + " ms (" + $last + "); the link is still open"))
        }
        $null = Update-HordeLinkInput -Link $Link -WaitMs ([Math]::Min($left, 250))
    }
}

function Send-HordeLinkFrame {
    # Send one frame. THROWS, sending nothing, for a frame that could not arrive as itself: not a
    # string, holding an LF, holding a non-ASCII character, or over the cap ("refused at the sender",
    # plan step R2). Otherwise a tristate answer: known "sent" when the channel took every byte, or
    # unknown - the link is closed, it broke while sending (whether the far end got any of the frame
    # cannot be known), or the channel did not take it within -TimeoutMs.
    param([Parameter(Mandatory = $true)]$Link, [Parameter(Mandatory = $true)][AllowEmptyString()]$Frame, [int]$TimeoutMs = 30000)
    if ($Frame -isnot [string]) { throw "refused: a frame is a string" }
    if ($Frame.IndexOf([char]10) -ge 0) { throw "refused: a frame may not hold an LF, which would end it early" }
    try { $bytes = $script:HordeLinkAscii.GetBytes($Frame) } catch { throw "refused: a frame is ASCII; escape every other character as the codec does" }
    if ($bytes.Length -gt $Link.maxFrameBytes) { throw ("refused: a frame of " + $bytes.Length + " bytes is over the " + $Link.maxFrameBytes + "-byte cap") }
    if ($Link.closed) { return (New-HordeUnknown -Reason ("the link is closed (" + $Link.closedReason + "); nothing was sent")) }
    if ($null -ne $Link.pendingWrite) {
        $prev = $Link.pendingWrite
        try { $done = $prev.Wait($TimeoutMs) }
        catch { Set-HordeLinkClosed -Link $Link -Reason ("an earlier frame failed to send: " + $_.Exception.InnerException.Message); return (New-HordeUnknown -Reason ("the link broke; nothing more was sent (" + $Link.closedReason + ")")) }
        if (-not $done) { return (New-HordeUnknown -Reason ("an earlier frame is still not taken after " + $TimeoutMs + " ms; nothing more was sent")) }
        $Link.pendingWrite = $null
    }
    $wire = New-Object byte[] ($bytes.Length + 1)
    [Array]::Copy($bytes, $wire, $bytes.Length)
    $wire[$bytes.Length] = $script:HordeLinkLf
    try {
        $task = & $Link.channel.write $Link.channel $wire
        if ($task -is [System.Threading.Tasks.Task]) {
            if (-not $task.Wait($TimeoutMs)) {
                $Link.pendingWrite = $task
                return (New-HordeUnknown -Reason ("the frame was not taken within " + $TimeoutMs + " ms: the far end is not reading. It may still arrive"))
            }
        }
    } catch {
        $inner = $_.Exception
        while ($null -ne $inner.InnerException) { $inner = $inner.InnerException }
        Set-HordeLinkClosed -Link $Link -Reason ("the link broke while sending: " + $inner.Message)
        return (New-HordeUnknown -Reason ("the link broke while sending; whether the far end received any of the frame is unknown (" + $inner.Message + ")"))
    }
    return (New-HordeKnown -Value "sent" -ObservedAt ([datetime]::UtcNow))
}

function Close-HordeLink {
    # Close this end. Safe to call more than once.
    param([Parameter(Mandatory = $true)]$Link)
    Set-HordeLinkClosed -Link $Link -Reason "closed by this end"
}

function Get-HordeLinkHealth {
    # Is the link up, as far as the transport can tell? Reads what is waiting (without consuming a
    # frame), then answers:
    #   known { state = closed; reason; since }  the link has ended - by this end, the far end, or an error.
    #   known { state = open; ... }              only when the transport has keepalive: a dead far
    #                                            end would already have shown as closed.
    #   unknown                                  open as far as anyone has seen, on a transport that
    #                                            cannot notice a dead far end without traffic.
    param([Parameter(Mandatory = $true)]$Link)
    # Drain what is already waiting, so a close that arrived behind data is seen. Bounded: a far end
    # that never stops sending must not keep health from answering.
    for ($i = 0; $i -lt 64; $i++) { if (-not (Update-HordeLinkInput -Link $Link -WaitMs 0)) { break } }
    if ($Link.closed) { return (New-HordeKnown -Value ([pscustomobject]@{ state = "closed"; reason = $Link.closedReason; since = $Link.closedAt }) -ObservedAt ([datetime]::UtcNow)) }
    if ($Link.keepalive) { return (New-HordeKnown -Value ([pscustomobject]@{ state = "open"; reason = ""; since = $Link.openedAt }) -ObservedAt ([datetime]::UtcNow)) }
    return (New-HordeUnknown -Reason ("no failure seen since " + $Link.openedAt.ToString("o") + ", but transport " + $Link.transport + " cannot notice a dead far end without traffic"))
}
