# DOES THE TRANSPORT PORT KEEP A TRANSPORT HONEST ABOUT WHAT IT CAN DO, AND NEVER GUESS A FRAME?
#
# Remote plan step R4, the port half (transports/Port.ps1). Two things are pinned here, both without
# any real transport, so every outcome is exact and repeatable:
#   - REGISTRATION AND CAPABILITIES. A transport folder whose capabilities.json breaks
#     schema/transport-capabilities.v1, or names another folder, is refused. Only "yes" counts as
#     having a capability; the production path to a node requires auth.peer.
#   - FRAMING, over a scripted byte channel that hands the port exactly the bytes a test chooses:
#     split lines, many lines at once, a line at the cap and one over it, a non-ASCII byte, a close in
#     the middle of a frame. A frame is known only when its LF arrived; everything else is unknown.
#
# The real transports, and a far end on another thread, are test/test-transport-conformance.ps1.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "transports\Port.ps1")

$fx = Join-Path $here "fixtures\transport\caps"
$script:opened = 0

function New-ScriptedChannel {
    # A byte channel that reads from a script: each item is a byte array, "eof" or "error". Once the
    # script runs out, reads find nothing. Writes are kept, or throw, or never finish.
    param([object[]]$Script = @(), [string]$WriteMode = "keep")
    $q = New-Object System.Collections.Queue
    foreach ($s in $Script) { $q.Enqueue($s) }
    return [pscustomobject]@{
        state = @{ script = $q; written = (New-Object System.Collections.ArrayList); writeMode = $WriteMode; closed = 0 }
        read = {
            param($Channel, [int]$WaitMs)
            $st = $Channel.state
            if ($st.script.Count -eq 0) { Start-Sleep -Milliseconds ([Math]::Min([Math]::Max(0, $WaitMs), 20)); return [pscustomobject]@{ kind = "none"; bytes = $null; reason = "" } }
            $item = $st.script.Dequeue()
            if ($item -is [string] -and $item -eq "eof") { return [pscustomobject]@{ kind = "eof"; bytes = $null; reason = "" } }
            if ($item -is [string] -and $item -eq "error") { return [pscustomobject]@{ kind = "error"; bytes = $null; reason = "scripted failure" } }
            return [pscustomobject]@{ kind = "data"; bytes = [byte[]]$item; reason = "" }
        }
        write = {
            param($Channel, [byte[]]$Bytes)
            $st = $Channel.state
            if ($st.writeMode -eq "throw") { throw (New-Object System.IO.IOException("scripted broken pipe")) }
            if ($st.writeMode -eq "hang") { return (New-Object 'System.Threading.Tasks.TaskCompletionSource[int]').Task }
            [void]$st.written.Add([byte[]]$Bytes)
            return $null
        }
        close = { param($Channel) $Channel.state.closed++ }
    }
}
function B { param([string]$Text) return ,([System.Text.Encoding]::ASCII.GetBytes($Text)) }
function Reg {
    param([string]$Name, [scriptblock]$Open = { param($e, $t) $script:opened++; [pscustomobject]@{ ok = $true; channel = (New-ScriptedChannel); peer = $null; reason = "" } },
          [scriptblock]$Probe = { param($e) New-HordeKnown -Value $true })
    return (Register-HordeTransport -Folder (Join-Path $fx $Name) -Open $Open -Probe $Probe `
        -Listen { param($e) [pscustomobject]@{ ok = $true; listener = @{}; reason = "" } } `
        -Accept { param($s, $t) [pscustomobject]@{ ok = $false; channel = $null; peer = $null; reason = "fixture accepts nothing" } } `
        -Stop { param($s) })
}
function Link { param($Transport, [object[]]$Script = @(), [string]$WriteMode = "keep")
    return (New-HordeLink -Transport $Transport -Role "node" -Endpoint "e" -Channel (New-ScriptedChannel -Script $Script -WriteMode $WriteMode) -Peer $null) }

Write-Host ""
Write-Host "--- a transport folder is registered only with valid capabilities, naming itself ---" -ForegroundColor Cyan

$good = Reg "fixture-good"
Check ($good.name -ceq "fixture-good" -and $good.maxFrameBytes -eq 16) "a folder with valid capabilities registers under its own name"
Check (@(Get-HordeTransportNames) -contains "fixture-good") "and is listed"
foreach ($case in @(
        @{ n = "fixture-misnamed"; like = "sits in the folder"; what = "capabilities that name another transport than their folder" },
        @{ n = "fixture-missing-cap"; like = "keepalive"; what = "capabilities missing one of the closed list" },
        @{ n = "fixture-extra-cap"; like = "teleport"; what = "a capability outside the closed list" },
        @{ n = "fixture-bad-word"; like = "maybe"; what = "a support word outside yes, no, declined, unverified" },
        @{ n = "fixture-blank-evidence"; like = "evidence"; what = "a capability with blank evidence" },
        @{ n = "fixture-no-file"; like = "no capabilities.json"; what = "a folder with no capabilities.json" })) {
    Check (Throws { Reg $case.n } $case.like) ("refused: " + $case.what)
    Check (@(Get-HordeTransportNames) -notcontains $case.n) ("and " + $case.n + " is not registered")
}
Check (Throws { Get-HordeTransport -Name "fixture-none" } "no transport") "asking for a transport nobody registered is an error, not a quiet default"
# A NAME IS REGISTERED ONCE. Registering a folder whose name is already taken replaced the first
# transport without a word (review of PR #42): a second copy of a folder, or a stray dot-source,
# could swap the transport every caller resolves by that name. It is refused, and the first stands.
$firstGood = Get-HordeTransport -Name "fixture-good"
Check (Throws { Reg "fixture-good" -Open { param($e, $t) "replaced" } } "already registered") "registering a name a second time is refused"
Check ([object]::ReferenceEquals((Get-HordeTransport -Name "fixture-good"), $firstGood)) "and the first registration still stands"

Write-Host ""
Write-Host "--- only 'yes' is having a capability; the production path requires auth.peer ---" -ForegroundColor Cyan

Check ((Test-HordeTransportCapability -Transport $good -Capability "auth.peer") -eq $true) "yes is having it"
Check ((Test-HordeTransportCapability -Transport $good -Capability "dial.in") -eq $false) "unverified is not having it"
Check ((Test-HordeTransportCapability -Transport $good -Capability "survives.peer.restart") -eq $false) "declined is not having it"
Check ((Test-HordeTransportCapability -Transport $good -Capability "encrypt") -eq $false) "no is not having it"
Check (Throws { Test-HordeTransportCapability -Transport $good -Capability "teleport" } "not a transport capability") "asking about a capability outside the list is an error"
$r = Resolve-HordeTransport -Name "fixture-good" -Require @("auth.peer", "dial.out")
Check ($r.state -ceq "known" -and $r.value.name -ceq "fixture-good") "a transport with every required capability resolves"
$r = Resolve-HordeTransport -Name "fixture-good" -Require @("dial.in")
Check ($r.state -ceq "unknown" -and "$($r.reason)" -like "*dial.in*unverified*") "one lacking a required capability is unknown, naming the capability and its word"
Check ((Resolve-HordeTransport -Name "fixture-good" -Require @()).state -ceq "known") "requiring nothing resolves"
Check ((Resolve-HordeTransport -Name "fixture-none" -Require @()).state -ceq "unknown") "an unregistered name resolves to unknown"
$nk = Reg "fixture-nokeepalive"
Check ((Resolve-HordeLinkTransport -Name "fixture-good").state -ceq "known") "the link path picks a transport with auth.peer yes"
$lr = Resolve-HordeLinkTransport -Name "fixture-nokeepalive"
Check ($lr.state -ceq "unknown" -and "$($lr.reason)" -like "*auth.peer*") "and refuses one whose auth.peer is not yes"

Write-Host ""
Write-Host "--- open, probe and listen report failures as answers ---" -ForegroundColor Cyan

$script:opened = 0
$o = Open-HordeTransportLink -Transport $good -Endpoint "e" -Role "hub"
Check ($o.state -ceq "unknown" -and "$($o.reason)" -like "*dial.in*") "a hub may not dial a transport whose dial.in is not yes"
Check ($script:opened -eq 0) "and the transport's open was never called"
$o = Open-HordeTransportLink -Transport $good -Endpoint "e" -Role "node"
Check ($o.state -ceq "known" -and $script:opened -eq 1) "a node dials it (dial.out yes)"
Check ($o.value.peer.verified -eq $false) "a transport that reports no peer gives an unverified peer, not a trusted one"
$boom = Reg "fixture-boom" -Open { param($e, $t) throw "adapter exploded" } -Probe { param($e) "yes" }
$o = Open-HordeTransportLink -Transport $boom -Endpoint "e" -Role "node"
Check ($o.state -ceq "unknown" -and "$($o.reason)" -like "*adapter exploded*") "an adapter that throws while opening gives unknown with its message, not a crash"
$p = Test-HordeTransportReachable -Transport $boom -Endpoint "e"
Check ((Test-HordeAnswer $p) -and $p.state -ceq "unknown") "a probe that answers with a bare value is unknown, not believed"

Write-Host ""
Write-Host "--- receiving: a frame is known only when its LF arrived ---" -ForegroundColor Cyan

$l = Link $good @((B "ab"), (B ("c" + [char]10 + "de" + [char]10 + "f")), "eof")
$a = Receive-HordeLinkFrame -Link $l -TimeoutMs 2000
Check ($a.state -ceq "known" -and $a.value -ceq "abc") "a frame split across two reads is joined"
$a = Receive-HordeLinkFrame -Link $l -TimeoutMs 2000
Check ($a.state -ceq "known" -and $a.value -ceq "de") "two frames in one read are two frames"
$a = Receive-HordeLinkFrame -Link $l -TimeoutMs 2000
Check ($a.state -ceq "unknown" -and "$($a.reason)" -like "*partial frame of 1 bytes*") "bytes with no LF before the link closed are a partial frame: unknown, with the count"
$a = Receive-HordeLinkFrame -Link $l -TimeoutMs 200
Check ($a.state -ceq "unknown" -and "$($a.reason)" -like "*closed*") "after that, the closed link gives unknown, never absent"
$l = Link $good @((B ("x" + [char]10)), "eof")
$a = Receive-HordeLinkFrame -Link $l -TimeoutMs 2000
$a2 = Receive-HordeLinkFrame -Link $l -TimeoutMs 2000
Check ($a.state -ceq "known" -and $a2.state -ceq "unknown" -and "$($a2.reason)" -like "*the far end closed*") "a close exactly at a frame boundary is unknown too: an orderly close and a crash look the same here"
$l = Link $good @(, (B ([char]10)))
$a = Receive-HordeLinkFrame -Link $l -TimeoutMs 2000
Check ($a.state -ceq "known" -and $a.value -ceq "") "an empty line is a known empty frame; judging it is the codec's"
$l = Link $good @()
$t0 = Get-Date
$a = Receive-HordeLinkFrame -Link $l -TimeoutMs 150
Check ($a.state -ceq "unknown" -and "$($a.reason)" -like "*no frame within 150 ms*still open*") "nothing in time is unknown and says the link is still open"
Check (-not $l.closed) "and does not close it"
Check (((Get-Date) - $t0).TotalMilliseconds -ge 140) "and waited the time it was given"

$l = Link $good @(, (B (("a" * 16) + [char]10)))
$a = Receive-HordeLinkFrame -Link $l -TimeoutMs 2000
Check ($a.state -ceq "known" -and $a.value.Length -eq 16) "a frame of exactly the cap (16 bytes) is received"
$l = Link $good @(, (B (("a" * 17) + [char]10)))
$a = Receive-HordeLinkFrame -Link $l -TimeoutMs 2000
Check ($a.state -ceq "unknown" -and "$($a.reason)" -like "*over the 16-byte cap*") "a frame one byte over the cap is unknown"
Check ($l.closed) "and closes the link: the next byte cannot be placed"
$l = Link $good @(, (B ("a" * 17)))
$a = Receive-HordeLinkFrame -Link $l -TimeoutMs 2000
Check ($a.state -ceq "unknown" -and "$($a.reason)" -like "*over the 16-byte cap*" -and $l.closed) "17 bytes with no LF yet are already over the cap: unknown, without waiting for more"
$l = Link $good @(, [byte[]]@(0x61, 0xE9, 0x0A))
$a = Receive-HordeLinkFrame -Link $l -TimeoutMs 2000
Check ($a.state -ceq "unknown" -and "$($a.reason)" -like "*not ASCII*" -and $l.closed) "a byte above 0x7F is unknown and closes the link"
$l = Link $good @("error")
$a = Receive-HordeLinkFrame -Link $l -TimeoutMs 2000
Check ($a.state -ceq "unknown" -and "$($a.reason)" -like "*scripted failure*" -and $l.closed) "a read that fails closes the link and says why"
$l = Link $good @((B ("ok" + [char]10)), "eof")
$h = Get-HordeLinkHealth -Link $l
Check ($h.state -ceq "known" -and $h.value.state -ceq "closed") "health notices the far end closed without anything being sent"
$a = Receive-HordeLinkFrame -Link $l -TimeoutMs 2000
Check ($a.state -ceq "known" -and $a.value -ceq "ok") "and a whole frame that came before the close is still delivered"
# HEALTH HOLDS THE CAP TOO. Health drains what is waiting so that a close behind data is seen; it
# used to drain 64 reads whatever they held, so a far end streaming bytes with no LF grew the buffer
# far past the frame cap between two receives (review of PR #42). 64 reads of 16 bytes, cap 16:
$flood = @(1..64 | ForEach-Object { , (B ("a" * 16)) })
$l = Link $good $flood
$h = Get-HordeLinkHealth -Link $l
Check ($l.buffer.Count -le 2 * $good.maxFrameBytes) ("health keeps the buffer within the cap while it drains (" + $l.buffer.Count + " bytes held)")
Check ($h.state -ceq "known" -and $h.value.state -ceq "closed" -and "$($h.value.reason)" -like "*over the 16-byte cap*") "and a line already over the cap closes the link there, as a receive would"
$l = Link $good @((B ("ab" + [char]10)), (B ("cd" + [char]10)), (B ("ef" + [char]10)), (B ("gh" + [char]10)), (B ("ij" + [char]10)), (B ("kl" + [char]10)), (B ("mn" + [char]10)), "eof")
$h = Get-HordeLinkHealth -Link $l
Check ($l.buffer.Count -le 2 * $good.maxFrameBytes -and -not $l.closed) "whole frames waiting are not an overflow: health stops draining at the cap and the link stays open"
$got = @(1..7 | ForEach-Object { $x = Receive-HordeLinkFrame -Link $l -TimeoutMs 1000; if ($x.state -eq "known") { $x.value } })
Check (($got -join ",") -ceq "ab,cd,ef,gh,ij,kl,mn") "and every one of them is still received, in order"

Write-Host ""
Write-Host "--- sending: refused at the sender, or sent, or unknown ---" -ForegroundColor Cyan

$l = Link $good @()
$s = Send-HordeLinkFrame -Link $l -Frame "hello"
Check ($s.state -ceq "known" -and $s.value -ceq "sent") "a valid frame is sent"
$w = [byte[]]$l.channel.state.written[0]
Check ([System.Text.Encoding]::ASCII.GetString($w) -ceq ("hello" + [char]10)) "as its bytes and one LF"
$s = Send-HordeLinkFrame -Link $l -Frame ("a" * 16)
Check ($s.state -ceq "known") "a frame of exactly the cap is sent"
$before = $l.channel.state.written.Count
Check (Throws { Send-HordeLinkFrame -Link $l -Frame ("a" * 17) } "over the 16-byte cap") "a frame over the cap is refused at the sender"
Check (Throws { Send-HordeLinkFrame -Link $l -Frame ("a" + [char]10 + "b") } "LF") "a frame holding an LF is refused: it would arrive as two"
Check (Throws { Send-HordeLinkFrame -Link $l -Frame ("caf" + [char]0xE9) } "ASCII") "a frame holding a non-ASCII character is refused"
Check (Throws { Send-HordeLinkFrame -Link $l -Frame 5 } "string") "a frame that is not a string is refused"
Check ($l.channel.state.written.Count -eq $before) "and none of the refused frames wrote a byte"
$s = Send-HordeLinkFrame -Link $l -Frame ""
Check ($s.state -ceq "known") "an empty frame is sent; judging it is the codec's"
$l = Link $good @() "throw"
$s = Send-HordeLinkFrame -Link $l -Frame "x"
Check ($s.state -ceq "unknown" -and "$($s.reason)" -like "*whether the far end received*") "a write that breaks is unknown: whether the far end got any of it cannot be known"
Check ($l.closed) "and closes the link"
$s = Send-HordeLinkFrame -Link $l -Frame "y"
Check ($s.state -ceq "unknown" -and "$($s.reason)" -like "*closed*nothing was sent*") "sending on a closed link is unknown and sends nothing"
$l = Link $good @() "hang"
$s = Send-HordeLinkFrame -Link $l -Frame "x" -TimeoutMs 100
Check ($s.state -ceq "unknown" -and "$($s.reason)" -like "*not taken within 100 ms*") "a write the far end never takes is unknown after the timeout, not a hang"
$s = Send-HordeLinkFrame -Link $l -Frame "y" -TimeoutMs 100
Check ($s.state -ceq "unknown" -and "$($s.reason)" -like "*earlier frame*") "and the next frame waits behind it rather than overtaking it"

Write-Host ""
Write-Host "--- health and close ---" -ForegroundColor Cyan

$l = Link $good @()
$h = Get-HordeLinkHealth -Link $l
Check ($h.state -ceq "known" -and $h.value.state -ceq "open") "an idle link on a transport with keepalive is known open"
$l2 = Link $nk @()
$h = Get-HordeLinkHealth -Link $l2
Check ($h.state -ceq "unknown" -and "$($h.reason)" -like "*cannot notice*") "on a transport without keepalive an idle link is unknown, not open"
Close-HordeLink -Link $l
Close-HordeLink -Link $l
Check ($l.channel.state.closed -eq 1) "closing twice closes the channel once"
$h = Get-HordeLinkHealth -Link $l
Check ($h.state -ceq "known" -and $h.value.state -ceq "closed" -and "$($h.value.reason)" -like "*this end*") "a link this end closed is known closed, by this end"
$a = Receive-HordeLinkFrame -Link $l -TimeoutMs 100
Check ($a.state -ceq "unknown") "receiving on it is unknown"

Complete-HordeSuite -Success "the port refuses dishonest transports and never guesses a frame"
