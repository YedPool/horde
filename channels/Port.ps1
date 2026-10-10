# channels/Port.ps1 - the relay channels: what a machine of a horde says through the relay, and how what
# it is told arrives, one plug-in per channel.
#
# WHAT A CHANNEL IS (relay design 2026-10-09, section 3, "Channels (plug-ins)"). Every envelope names a
# channel (relay/Envelope.ps1's header): decisions today, chat later. A channel is a folder,
# channels/<name>/, holding Channel.ps1, which calls Register-HordeRelayChannel with:
#   name      the envelope channel it owns, one lower-case word;
#   kinds     the envelope kinds it takes IN on that channel (decisions: answer). Anything else on it is
#             refused before the journal records it;
#   senders   who may send it those kinds: "founder" - the founder's trusted passkeys only - or
#             "horde" - any trusted sender, passkey or peer machine. relay/Trust.ps1 decides who is
#             trusted; this only narrows it;
#   Accept    param($Context, $Item) -> { outcome; reason }: one opened envelope, handed over once it
#             is verified, journaled and opened. $Item is { from; channel; kind; seq; key; evidence;
#             body (bytes) }. outcome is "done" (acted on), "refused" (never will be: say why) or
#             "retry" (not now: the same record is handed over again later, from the journal).
#             AN ACCEPT MUST BE IDEMPOTENT BY THE RECORD: after a crash between its act and the done
#             mark the same item comes again (relay/Journal.ps1, FINISHED AND UNFINISHED);
#   Tick      param($Context) -> lines: whatever the channel sends OUT, on every turn of the runner.
#             It sends through Send-HordeRelayChannelEnvelope, and says what it did in lines a person
#             can read.
# This file names no channel, so chat is a new folder and not an edit here (the design's PR plan,
# item 10).
#
# WHY HERE AND NOT IN relay/. relay/ reads the relay's untrusted text and is held by tools/ExecScan.ps1
# to running no script block it is given; the relay port (relays/Port.ps1) and these plug-ins are
# script blocks by design. So relay/ verifies, journals and opens, and stays the only code that does;
# this file calls it, and calls the relay port, and runs the channels' blocks.
#
# THE PATH IN, for every channel at once (Receive-HordeRelayInbox, then Invoke-HordeRelayUnfinished):
#   1. watch the machine's mailbox from the cursor (relays/Port.ps1 already drops malformed items,
#      repeats and stale ones, and reports gaps);
#   2. read each text as an envelope; SORT THE BATCH BY SENDER AND SEQ, so a relay that reorders cannot
#      make the journal refuse an earlier envelope as out of order;
#   3. refuse, before the journal sees it, an envelope of a channel nobody registered, of a kind its
#      channel does not take, from a sender that channel does not take, not signed by a trusted sender,
#      or not addressed to this machine - so the journal records only what may be opened;
#   4. record it in the journal (relay/Journal.ps1); a replay, a reuse or a late envelope is refused
#      there for good;
#   5. ACK the relay through the last item of the batch that is journaled or refused for good: the
#      journal holds every journaled envelope whole, so the relay may forget it. An item that could not
#      be judged (the journal busy or damaged) stops the ack and the cursor before it, and comes again;
#   6. open every journaled record no channel has finished (Get-HordeRelayJournalUnfinished) - the ones
#      just recorded, and any a killed run left - with Unprotect-HordeRelayEnvelope against the senders
#      trusted NOW, hand the body to its channel's Accept, and mark it done when the channel is done
#      with it, or refuses it for good.
# Exactly once is therefore the journal's (each envelope recorded once) plus the channel's (its act is
# idempotent by the record); nothing here holds state that a crash could lose.
#
# THE PATH OUT is Send-HordeRelayChannelEnvelope: seal to the recipients, sign with this machine's key,
# record in the journal BEFORE the relay sees it (so its seq is spent whatever happens next), put it
# under its replay key (so a retried put is the same item).
#
# Answers are core/tristate; the channels' outcomes are words. Nothing here prints: the runner does.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Tristate.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "relays\Port.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "relay\Journal.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "relay\Pairing.ps1")

if ($null -eq (Get-Variable -Name HordeRelayChannels -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeRelayChannels = [ordered]@{} }
$script:HordeRelayChannelSenders = @("founder", "horde")
$script:HordeRelayChannelOutcomes = @("done", "refused", "retry")
$script:HordeRelayChannelWordPattern = '\A[a-z][a-z0-9-]{0,31}\z'

function Get-HordeRelayChannelRoot {
    return $PSScriptRoot
}

function Get-HordeRelayChannelFiles {
    # Every channel's Channel.ps1, for the caller to dot-source at script level:
    #   foreach ($f in @(Get-HordeRelayChannelFiles)) { . $f }
    param([string]$Root = (Get-HordeRelayChannelRoot))
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $Root -Directory | Sort-Object Name | ForEach-Object { Join-Path $_.FullName "Channel.ps1" } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
}

function Register-HordeRelayChannel {
    # Called by a channel's own Channel.ps1. Throws on a declaration that does not hold together: a
    # channel that cannot say what it takes is not one.
    param(
        [Parameter(Mandatory = $true)][string]$Folder,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Kinds,
        [Parameter(Mandatory = $true)][string]$Senders,
        [Parameter(Mandatory = $true)][scriptblock]$Accept,
        [scriptblock]$Tick = $null
    )
    if ($Name -cnotmatch $script:HordeRelayChannelWordPattern) { throw ("a channel is one lower-case word of up to 32 characters, not '" + $Name + "'") }
    if ((Split-Path -Leaf $Folder) -cne $Name) { throw ("the channel '" + $Name + "' sits in the folder '" + (Split-Path -Leaf $Folder) + "'; a channel's folder is its name") }
    foreach ($k in $Kinds) { if ($k -cnotmatch $script:HordeRelayChannelWordPattern) { throw ("the channel '" + $Name + "' takes the kind '" + $k + "', which is not one lower-case word") } }
    if ($script:HordeRelayChannelSenders -cnotcontains $Senders) { throw ("a channel takes envelopes from " + ($script:HordeRelayChannelSenders -join " or ") + ", not '" + $Senders + "'") }
    # Once per name: a second registration would silently swap the channel every envelope goes to.
    if ($script:HordeRelayChannels.Contains($Name)) { throw ("the channel '" + $Name + "' is already registered, from " + $script:HordeRelayChannels[$Name].folder + "; the first registration stands") }
    $c = [pscustomobject]@{ PSTypeName = "Horde.RelayChannel"; name = $Name; folder = $Folder; kinds = @($Kinds); senders = $Senders; accept = $Accept; tick = $Tick }
    $script:HordeRelayChannels[$Name] = $c
    return $c
}

function Get-HordeRelayChannelNames {
    return @($script:HordeRelayChannels.Keys)
}

function Get-HordeRelayChannel {
    # A registered channel by name, or $null.
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not $script:HordeRelayChannels.Contains($Name)) { return $null }
    return $script:HordeRelayChannels[$Name]
}

function New-HordeRelayRunContext {
    # What the channels work with for one run: this machine's identity and keys, the journal made ready,
    # and the relay connection. Known { hordeHome; horde; signKeyId; signKey; agreeKeyId; openingKeys;
    # mailbox; connection; decisionsRoot; cursor; acked; state }, where openingKeys is the agreement keys
    # that may open (the current one and any retired one in its grace) and state a table each channel
    # keeps its own memory in, by name. The caller closes it (Close-HordeRelayRunContext). The identity's
    # answer when there is none; unknown when the journal cannot be made ready.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)]$Connection, [string]$DecisionsRoot = "", $Now = $null)
    $j = Initialize-HordeRelayJournal -HordeHome $HordeHome -Now $Now
    if ($j.state -cne "known") { return (New-HordeUnknown -Reason ("the relay journal is not ready: " + $j.reason)) }
    $id = Get-HordeRelayMachineIdentity -HordeHome $HordeHome -Open -Now $Now
    if ($id.state -cne "known") { return $id }
    $open = Get-HordeRelayOpeningKeys -HordeHome $HordeHome -Now $Now
    if ($open.state -cne "known") { $id.value.sign.key.Dispose(); $id.value.agree.key.Dispose(); return $open }
    $id.value.agree.key.Dispose()
    # The decisions store of the same home as everything else here, when the caller names a home: one
    # run never reads one home's trust and journal and another's decisions.
    if ($DecisionsRoot -ceq "" -and $HordeHome -cne "") { $DecisionsRoot = [System.IO.Path]::Combine($HordeHome, "store", "decisions") }
    return (New-HordeKnown -Value ([pscustomobject]@{
        hordeHome = $HordeHome; horde = $id.value.horde; signKeyId = $id.value.sign.keyId; signKey = $id.value.sign.key
        agreeKeyId = $id.value.agree.keyId; openingKeys = $open.value.keys; mailbox = $id.value.mailbox; connection = $Connection
        decisionsRoot = $DecisionsRoot; cursor = [long]0; acked = [long]0; state = @{}
    }))
}

function Close-HordeRelayRunContext {
    # Let go of the context's keys. Safe to call twice.
    param($Context)
    if ($null -eq $Context) { return }
    try { if ($null -ne $Context.signKey) { $Context.signKey.Dispose() } } catch { }
    foreach ($k in @($Context.openingKeys.Values)) { try { $k.Dispose() } catch { } }
}

function Get-HordeRelayChannelSenders {
    # The senders a channel takes, from those trusted now: known hashtable (key id -> sender), or the
    # trust store's unknown.
    param($Context, $Channel)
    $all = Find-HordeRelayTrustedSenders -HordeHome $Context.hordeHome
    if ($all.state -cne "known") { return $all }
    if ($Channel.senders -ceq "horde") { return $all }
    $out = @{}
    foreach ($k in @($all.value.Keys)) { if ($all.value[$k].proof -ceq "webauthn") { $out[$k] = $all.value[$k] } }
    return (New-HordeKnown -Value $out)
}

function Send-HordeRelayChannelEnvelope {
    # Seal -Body to -Recipients (65-byte agreement keys), sign it as this machine, record it in the
    # journal, and put it into -Mailbox. Known { seq; key; relaySeq; duplicate }; unknown with the reason,
    # saying whether the envelope was recorded (its seq spent) before it failed.
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)][string]$Channel, [Parameter(Mandatory = $true)][string]$Kind,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Body, [Parameter(Mandatory = $true)][object[]]$Recipients, [Parameter(Mandatory = $true)][string]$Mailbox, $Now = $null)
    # Two tries: a second sender of this stream in another process may take the seq between the ask and
    # the record (Get-HordeRelayJournalNextSeq says so); the loser asks again once.
    for ($try = 1; $try -le 2; $try++) {
        $next = Get-HordeRelayJournalNextSeq -From $Context.signKeyId -Channel $Channel -HordeHome $Context.hordeHome
        if ($next.state -cne "known") { return (New-HordeUnknown -Reason ("nothing was sent: no sequence number - " + $next.reason)) }
        try { $text = New-HordeRelayEnvelope -Kind $Kind -Channel $Channel -Seq $next.value -Body $Body -Recipients $Recipients -Signer $Context.signKey -Now $Now }
        catch { return (New-HordeUnknown -Reason "nothing was sent: the envelope could not be made" -ErrorRecord $_) }
        $rec = Register-HordeRelayJournalSent -Text $text -HordeHome $Context.hordeHome -Now $Now
        if ($rec.state -cne "known") { return (New-HordeUnknown -Reason ("nothing was sent: the journal did not record it - " + $rec.reason)) }
        if (-not $rec.value.fresh) { continue }
        $key = $rec.value.key
        $put = Send-HordeRelayItem -Connection $Context.connection -Mailbox $Mailbox -Text $text -Key $key
        if ($put.state -cne "known") { return (New-HordeUnknown -Reason ("the envelope " + $key + " is recorded (its seq is spent) but the relay did not take it: " + $put.reason)) }
        return (New-HordeKnown -Value ([pscustomobject]@{ seq = [long]$next.value; key = $key; relaySeq = $put.value.seq; duplicate = $put.value.duplicate }))
    }
    return (New-HordeUnknown -Reason "nothing was sent: another sender of this stream took the next sequence number twice")
}

function Test-HordeRelayInboundGate {
    # Step 3 of THE PATH IN: why a read envelope must be refused before the journal sees it, or "".
    # { why; channel; senders } - the channel and its senders when it may go on; unknown senders (the
    # trust store unreadable) is not a refusal of this envelope: why is "" and transient is $true.
    param($Context, $Envelope)
    $h = $Envelope.header
    $ch = Get-HordeRelayChannel -Name $h.channel
    if ($null -eq $ch) { return [pscustomobject]@{ why = ("no channel '" + $h.channel + "' is registered here"); transient = $false; channel = $null; senders = $null } }
    if (@($ch.kinds) -cnotcontains $h.kind) { return [pscustomobject]@{ why = ("the channel " + $ch.name + " takes " + $(if (@($ch.kinds).Count) { @($ch.kinds) -join ", " } else { "nothing in" }) + ", not " + $h.kind); transient = $false; channel = $ch; senders = $null } }
    $senders = Get-HordeRelayChannelSenders -Context $Context -Channel $ch
    if ($senders.state -cne "known") { return [pscustomobject]@{ why = ("the trust store cannot be read: " + $senders.reason); transient = $true; channel = $ch; senders = $null } }
    if (-not $senders.value.ContainsKey($h.from)) {
        $who = Find-HordeRelayTrustedSender -HordeHome $Context.hordeHome -KeyId $h.from
        $what = $(if ($who.state -ceq "known") { "a trusted sender, but not one the channel " + $ch.name + " takes (" + $ch.senders + ")" } elseif ($who.state -ceq "absent") { $who.reason } else { "unknown: " + $who.reason })
        return [pscustomobject]@{ why = ("the sender " + $h.from + " is " + $what); transient = $false; channel = $ch; senders = $null }
    }
    $verified = Test-HordeRelayEnvelope -Envelope $Envelope -Senders $senders.value
    if (-not $verified.ok) { return [pscustomobject]@{ why = $verified.reason; transient = $false; channel = $ch; senders = $null } }
    $forMe = @(@($h.to) | Where-Object { $Context.openingKeys.ContainsKey($_) })
    if ($forMe.Count -eq 0) { return [pscustomobject]@{ why = "it is not addressed to any agreement key of this machine"; transient = $false; channel = $ch; senders = $null } }
    return [pscustomobject]@{ why = ""; transient = $false; channel = $ch; senders = $senders.value }
}

function Receive-HordeRelayInbox {
    # Steps 1 to 5 of THE PATH IN: one watch of the machine's mailbox, every envelope in it judged and
    # journaled, the relay acked. Known { taken; refused; held; missing; anomalies; cursor; acked } -
    # taken: the replay keys journaled; refused: lines saying what was refused for good and why; held:
    # lines for what could not be judged now and comes again; missing: lines for envelopes of a sender
    # that the journal saw skipped (dropped, delayed or withheld by the relay: design Q11, "shown as
    # missing, never as silence"). Unknown when the relay could not be read.
    param([Parameter(Mandatory = $true)]$Context, [int]$TimeoutMs = 0, $Now = $null)
    $w = Wait-HordeRelayItems -Connection $Context.connection -Mailbox $Context.mailbox -Since $Context.cursor -TimeoutMs $TimeoutMs
    if ($w.state -cne "known") { return $w }
    $refused = New-Object System.Collections.ArrayList
    $held = New-Object System.Collections.ArrayList
    $taken = New-Object System.Collections.ArrayList
    $missing = New-Object System.Collections.ArrayList
    $parsed = New-Object System.Collections.ArrayList
    $settled = @{}
    foreach ($it in @($w.value.items)) {
        $r = Read-HordeRelayEnvelope -Text $it.text
        if (-not $r.ok) { [void]$refused.Add("item " + $it.seq + ": not an envelope (" + $r.reason + ")"); $settled[[long]$it.seq] = $true; continue }
        [void]$parsed.Add([pscustomobject]@{ item = $it; envelope = $r.value })
    }
    # Sorted by sender and that sender's seq (step 2). The relay's own order is not trusted to be theirs.
    $ordered = @($parsed | Sort-Object @{ Expression = { $_.envelope.header.from } }, @{ Expression = { [long]$_.envelope.header.seq } })
    foreach ($p in $ordered) {
        $h = $p.envelope.header
        $rk = Get-HordeRelayReplayKey -Header $h
        $gate = Test-HordeRelayInboundGate -Context $Context -Envelope $p.envelope
        if ($gate.transient) { [void]$held.Add($rk + ": " + $gate.why); continue }
        if ($gate.why -cne "") { [void]$refused.Add($rk + ": " + $gate.why); $settled[[long]$p.item.seq] = $true; continue }
        $verdict = Register-HordeRelayJournalReceived -Envelope $p.envelope -Senders $gate.senders -RecipientKeyIds @($Context.openingKeys.Keys) -Channel $h.channel -Kind $h.kind -HordeHome $Context.hordeHome -Now $Now
        if ($verdict.state -cne "known") { [void]$held.Add($rk + ": the journal could not judge it - " + $verdict.reason); continue }
        $settled[[long]$p.item.seq] = $true
        if ($verdict.value.fresh) {
            [void]$taken.Add($rk)
            if ([long]$verdict.value.gapBefore -gt 0) { [void]$missing.Add($rk + ": " + $verdict.value.gapBefore + " envelope(s) of this sender before it are missing") }
        }
        else { [void]$refused.Add($rk + ": " + $verdict.value.why) }
    }
    # Step 5: the cursor and the ack move to the last item before the first one held. Items the port
    # dropped are its anomalies and are behind its own cursor already.
    $through = $Context.cursor
    $stop = $false
    foreach ($it in @($w.value.items)) {
        if ($stop) { break }
        if ($settled.ContainsKey([long]$it.seq)) { $through = [long]$it.seq } else { $stop = $true }
    }
    if (-not $stop) { $through = [long]$w.value.next }
    $Context.cursor = $through
    if ($through -gt $Context.acked) {
        $ack = Confirm-HordeRelayItems -Connection $Context.connection -Mailbox $Context.mailbox -Through $through
        if ($ack.state -ceq "known") { $Context.acked = $through }
        else { [void]$held.Add("the relay was not acked through " + $through + ": " + $ack.reason) }
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ taken = @($taken.ToArray()); refused = @($refused.ToArray()); held = @($held.ToArray()); missing = @($missing.ToArray()); anomalies = @($w.value.anomalies); cursor = $Context.cursor; acked = $Context.acked }))
}

function Invoke-HordeRelayUnfinished {
    # Step 6 of THE PATH IN: every journaled record of every registered channel that no channel has
    # finished, opened and handed to its channel. Known { done; refused; retry } - lines, one per record.
    # Unknown never: a channel whose journal cannot be read is a retry line, and the others go on.
    param([Parameter(Mandatory = $true)]$Context, $Now = $null)
    $done = New-Object System.Collections.ArrayList
    $refused = New-Object System.Collections.ArrayList
    $retry = New-Object System.Collections.ArrayList
    foreach ($name in @(Get-HordeRelayChannelNames)) {
        $ch = Get-HordeRelayChannel -Name $name
        $list = Get-HordeRelayJournalUnfinished -Channel $name -HordeHome $Context.hordeHome
        if ($list.state -cne "known") { [void]$retry.Add("channel " + $name + ": " + $list.reason); continue }
        foreach ($u in @($list.value)) {
            $outcome = Invoke-HordeRelayChannelRecord -Context $Context -Channel $ch -Record $u
            $line = $u.key + ": " + $outcome.reason
            if ($outcome.outcome -ceq "retry") { [void]$retry.Add($line); continue }
            $mark = Complete-HordeRelayJournalReceived -From $u.from -Channel $name -Seq $u.seq -HordeHome $Context.hordeHome -Now $Now
            if ($mark.state -cne "known") { [void]$retry.Add($line + "; but it could not be marked done (" + $mark.reason + "), so it comes again"); continue }
            if ($outcome.outcome -ceq "done") { [void]$done.Add($line) } else { [void]$refused.Add($line) }
        }
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ done = @($done.ToArray()); refused = @($refused.ToArray()); retry = @($retry.ToArray()) }))
}

function Invoke-HordeRelayChannelRecord {
    # One unfinished record: open it and hand it to its channel. { outcome; reason }.
    param($Context, $Channel, $Record)
    if (@($Channel.kinds) -cnotcontains $Record.kind) { return [pscustomobject]@{ outcome = "refused"; reason = ("the channel " + $Channel.name + " no longer takes the kind " + $Record.kind) } }
    $r = Read-HordeRelayEnvelope -Text $Record.text
    if (-not $r.ok) { return [pscustomobject]@{ outcome = "refused"; reason = ("the journaled text is not an envelope: " + $r.reason) } }
    $senders = Get-HordeRelayChannelSenders -Context $Context -Channel $Channel
    if ($senders.state -cne "known") { return [pscustomobject]@{ outcome = "retry"; reason = ("the trust store cannot be read: " + $senders.reason) } }
    # The senders trusted NOW: a device revoked since the record was made opens nothing.
    $opened = Unprotect-HordeRelayEnvelope -Envelope $r.value -Senders $senders.value -RecipientKeys $Context.openingKeys -Replay $Record.verdict -Channel $Channel.name -Kind $Record.kind
    if (-not $opened.ok) { return [pscustomobject]@{ outcome = "refused"; reason = ("not opened: " + $opened.reason) } }
    $item = [pscustomobject]@{ from = $Record.from; channel = $Channel.name; kind = $Record.kind; seq = $Record.seq; key = $Record.key; evidence = $Record.evidence; body = [byte[]]$opened.value }
    $got = $null
    try { $got = & $Channel.accept $Context $item }
    catch { return [pscustomobject]@{ outcome = "retry"; reason = ("the channel " + $Channel.name + " failed: " + $_.Exception.Message) } }
    $got = @($got) | Select-Object -Last 1
    if ($null -eq $got -or $null -eq $got.PSObject.Properties["outcome"] -or $script:HordeRelayChannelOutcomes -cnotcontains "$($got.outcome)") {
        return [pscustomobject]@{ outcome = "retry"; reason = ("the channel " + $Channel.name + " answered with something that is not done, refused or retry") }
    }
    $why = $(if ($null -ne $got.PSObject.Properties["reason"]) { "$($got.reason)" } else { "" })
    return [pscustomobject]@{ outcome = "$($got.outcome)"; reason = $why }
}

function Invoke-HordeRelayChannelTicks {
    # The path out: every channel's Tick, in name order. Lines, each starting with its channel's name. A
    # channel that throws is a line, and the others still run.
    param([Parameter(Mandatory = $true)]$Context, $Now = $null)
    $out = New-Object System.Collections.ArrayList
    foreach ($name in @(Get-HordeRelayChannelNames)) {
        $ch = Get-HordeRelayChannel -Name $name
        if ($null -eq $ch.tick) { continue }
        try { foreach ($l in @(& $ch.tick $Context)) { if ("$l" -ne "") { [void]$out.Add($name + ": " + $l) } } }
        catch { [void]$out.Add($name + ": failed: " + $_.Exception.Message) }
    }
    return @($out.ToArray())
}
