# channels/Port.ps1 - the relay channels: what a machine of a horde says through the relay, and how what
# it is told arrives, one plug-in per channel.
#
# WHAT A CHANNEL IS (relay design 2026-10-09, section 3, "Channels (plug-ins)"). Every envelope names a
# channel (relay/Envelope.ps1's header): decisions today, chat later. A channel is a folder,
# channels/<name>/, holding Channel.ps1, which calls Register-HordeRelayChannel with:
#   name      the envelope channel it owns, one lower-case word;
#   kinds     the envelope kinds it takes IN on that channel (decisions: answer, rank). Anything else on it is
#             refused before the journal records it;
#   senders   who may send it those kinds: "founder" - the founder's trusted passkeys only - or
#             "horde" - any trusted sender, passkey or peer machine. relay/Trust.ps1 decides who is
#             trusted; this only narrows it;
#   Accept    param($Context, $Item) -> { outcome; reason }: one opened envelope, handed over once it
#             is verified, journaled and opened. $Item is { from; channel; kind; seq; key; evidence;
#             ts; body (bytes) } - ts the envelope's own time, in milliseconds, as its sender signed it. outcome is "done" (acted on), "refused" (never will be: say why) or
#             "retry" (not now: the same record is handed over again later, from the journal).
#             AN ACCEPT MUST BE IDEMPOTENT BY THE RECORD: after a crash between its act and the done
#             mark the same item comes again (relay/Journal.ps1, FINISHED AND UNFINISHED);
#   Tick      param($Context) -> { lines; failed }: whatever the channel sends OUT, on every turn of
#             the runner, and whether it could not (the relay would not take a put, the journal would not
#             record): failed counts toward the runner's backoff (review of 48bc492, finding 1). Plain
#             lines are taken as { lines; failed = $false }. It records with
#             Save-HordeRelayChannelEnvelope and puts with Send-HordeRelayChannelSaved, and keeps what it
#             recorded and could not put in $Context.state, to put that same envelope again.
#   Glance    OPTIONAL. param($Context) -> $true or $false: would a Tick, run now, have something to
#             send? WHY IT EXISTS: the runner's Tick ran once a turn, and a turn is as long as its watch
#             of the mailbox - 60 s on the hosted relay - so the Thrall's reply under a question, or a
#             line of chat, written a second into the watch waited out the rest of it (measured
#             2026-10-13: 6.9 s of an 8 s watch, three times of three). The runner now asks every
#             channel's Glance about once a second WHILE THE WATCH IS OPEN (cli/RelayRun.ps1, SENDING
#             DURING THE WATCH), and runs the Tick, then and there, of each channel that says yes.
#             A GLANCE IS CHEAP, LOCAL AND CHANGES NOTHING: a file's length, the names in a folder, a
#             few bytes past a cursor. It makes no request of the relay - the hosted one counts them -
#             and it does not read the trust store: one idle round of the three Ticks was 186 ms on
#             this box, 134 ms of it the trust store read once by each (measured 2026-10-13), which
#             once a second is a fifth of a core for nothing; one round of their Glances is about 6 ms.
#             IT MAY BE WRONG IN ONE DIRECTION ONLY. A yes with nothing behind it costs one Tick that
#             sends nothing. A no that should have been a yes costs nothing but time: the turn's own
#             Tick still runs when the watch ends, exactly as it always did. So a channel answers no
#             for whatever its Glance cannot see cheaply (a phone key trusted since, a cleared
#             session), and for anything that has already failed: what the relay would not take is
#             the turn's Tick's to put again, after the runner's backoff, never the Glance's to hurry.
#             A channel with no Glance is ticked once a turn, as before.
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
#   2. a PHONE VOUCH ITEM (relay/Trust.ps1, THE VOUCH TRAVELS BY ITSELF) is no envelope and no channel's:
#      it is judged at once by Receive-HordeRelayPhoneVouch, against the trust store as it is now,
#      and settled - done or refused - never journaled;
#      read each other text as an envelope; SORT THE BATCH BY SENDER AND SEQ, so a relay that reorders cannot
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
#      with it, or refuses it for good. A BATCH THAT HOLDS A DATA ITEM runs this step between 4 and the
#      data items (Complete-HordeRelayInbox), so a photo's manifest is opened before its parts are judged.
# Exactly once is therefore the journal's (each envelope recorded once) plus the channel's (its act is
# idempotent by the record); nothing here holds state that a crash could lose.
#
# THE PATH OUT is Send-HordeRelayChannelEnvelope: seal to the recipients, sign with this machine's key,
# record in the journal BEFORE the relay sees it (so its seq is spent whatever happens next), put it
# under its replay key (so a retried put is the same item).
#
# WHAT GOES TO THE PHONE IS TRIMMED BY ITS SENDER (relays/Port.ps1, A SENDER TRIMS ITS OWN STREAM). The
# phone's mailbox is acked by nobody, so a channel that puts there says, on the put itself, how much of
# its own stream is still wanted: Send-HordeRelayChannelSaved -KeepFrom, a seq of the envelope's own
# stream (this machine, that channel). decisions keeps from the first page of the snapshot whose last
# page is being put; chat and progress keep their last so-many envelopes (Get-HordeRelayChannelKeepFrom).
# It is one more thing said on a put that was being made anyway: no request is added.
# WHAT A PUT TELLS THE RUN, kept in the context for the runner to say and to act on (cli/RelayRun.ps1):
#   full       by mailbox: the relay REFUSED a put there because the mailbox, or the account, holds its
#              most (status 507). Until 2026-10-13 that was one more failed turn among others, backed off
#              from for ever in a log nobody was reading, while nothing reached the founder's phone. It
#              is kept here until a put into that mailbox is taken again - BY THE CHANNEL THAT WAS
#              REFUSED (review of PR 232, 2026-10-14). It was kept by mailbox alone and cleared by any
#              put taken there, and the Ticks run in name order: decisions was refused, progress put
#              one small envelope a moment later in the same round, and the mark was gone before the
#              runner looked - nothing said, nobody told; or chat cleared it and decisions set it
#              again the next turn, and the line and the notice were repeated. A small envelope
#              fitting says nothing about a large one that did not. So the mark names the channels
#              refused there (the channel is in the envelope's own key), a channel's own success
#              takes only its own name off, and the mailbox is full until none is left.
#   untrimmed  by mailbox: a put there asked for a trim and the relay took the put without trimming -
#              a relay with no such thing, or a hosted one deployed before it. Nothing failed, and the
#              mailbox is growing toward full: worth one plain line.
#   refusedWith  by status: every status a put was refused with since the runner last emptied it, which
#              it does at the top of each turn - so the runner judges a failed turn's backoff by what the
#              relay said THIS turn, never by the sticky full mark (cli/RelayRun.ps1, BACKOFF).
#
# DATA KINDS (shape B, 2026-10-14: agreed by the Horde coordinator and the relay owner, for the photos
# of channels/chat/Photo.ps1). An item in the machine's mailbox that is NOT an envelope, and opens with
# {"v":1,"kind":"<a registered data kind>", is not signed by anybody, so it is never an envelope, never
# journaled with them, never opened, and never handed to an Accept. It is handed to its kind's Take
# block ALONE - Register-HordeRelayDataKind - whose only power is to keep inert bytes that a passkey-
# signed envelope already vouched for by digest. THE GATE ENFORCES IT BY KIND, NOT BY CONVENTION:
#   - a data kind's name can never be an envelope kind: Test-HordeRelayInboundGate refuses an envelope
#     of that kind on EVERY channel before the journal sees it, Invoke-HordeRelayChannelRecord refuses a
#     record of it (one journaled by older code), and Register-HordeRelayChannel refuses a channel that
#     says it takes it - so an answer, a line, a follow or anything a runner acts on can never be one;
#   - a data item whose kind is not registered is refused as not an envelope, as before;
#   - every Take outcome - taken, pending or refused - settles the item, and a Take that throws refuses
#     it: a part can be lost (the photo is then incomplete, and its phone is told), never wedge the
#     mailbox behind it;
#   - data items refused for the very same reason are said as ONE line with their count, so a photo
#     its runtime cannot take is one line, not one a part (review of PR 285).
#
# Answers are core/tristate; the channels' outcomes are words. Nothing here prints: the runner does.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Tristate.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "relays\Port.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "relay\Journal.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "relay\Join.ps1")
. (Join-Path $PSScriptRoot "Sessions.ps1")

if ($null -eq (Get-Variable -Name HordeRelayChannels -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeRelayChannels = [ordered]@{} }
$script:HordeRelayChannelSenders = @("founder", "horde")
$script:HordeRelayChannelOutcomes = @("done", "refused", "retry")
$script:HordeRelayChannelWordPattern = '\A[a-z][a-z0-9-]{0,31}\z'
if ($null -eq (Get-Variable -Name HordeRelayDataKinds -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeRelayDataKinds = [ordered]@{} }
$script:HordeRelayDataKindPattern = '\A\{"v":1,"kind":"([a-z][a-z0-9-]{0,31})",'
$script:HordeRelayDataOutcomes = @("taken", "pending", "refused")

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
        [scriptblock]$Tick = $null,
        [scriptblock]$Glance = $null
    )
    if ($Name -cnotmatch $script:HordeRelayChannelWordPattern) { throw ("a channel is one lower-case word of up to 32 characters, not '" + $Name + "'") }
    if ((Split-Path -Leaf $Folder) -cne $Name) { throw ("the channel '" + $Name + "' sits in the folder '" + (Split-Path -Leaf $Folder) + "'; a channel's folder is its name") }
    foreach ($k in $Kinds) { if ($k -cnotmatch $script:HordeRelayChannelWordPattern) { throw ("the channel '" + $Name + "' takes the kind '" + $k + "', which is not one lower-case word") } }
    foreach ($k in $Kinds) { if ($script:HordeRelayDataKinds.Contains($k)) { throw ("the channel '" + $Name + "' says it takes the kind '" + $k + "', which is a data kind: unsigned, and never an envelope (DATA KINDS)") } }
    if ($script:HordeRelayChannelSenders -cnotcontains $Senders) { throw ("a channel takes envelopes from " + ($script:HordeRelayChannelSenders -join " or ") + ", not '" + $Senders + "'") }
    # Once per name: a second registration would silently swap the channel every envelope goes to.
    if ($script:HordeRelayChannels.Contains($Name)) { throw ("the channel '" + $Name + "' is already registered, from " + $script:HordeRelayChannels[$Name].folder + "; the first registration stands") }
    # A Glance asks whether a Tick has something to send: with no Tick there is nothing it could ask about.
    if ($null -ne $Glance -and $null -eq $Tick) { throw ("the channel '" + $Name + "' has a Glance and no Tick: a Glance says whether its Tick has something to send") }
    $c = [pscustomobject]@{ PSTypeName = "Horde.RelayChannel"; name = $Name; folder = $Folder; kinds = @($Kinds); senders = $Senders; accept = $Accept; tick = $Tick; glance = $Glance }
    $script:HordeRelayChannels[$Name] = $c
    return $c
}

function Register-HordeRelayDataKind {
    # A data kind (DATA KINDS, in the header): -Name, owned by the registered channel -Channel from its
    # -Folder, and the one block its items are handed to - param($Context, $Text) -> { outcome; reason },
    # outcome taken, pending or refused. Throws on a declaration that does not hold together.
    param([Parameter(Mandatory = $true)][string]$Folder, [Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][string]$Channel, [Parameter(Mandatory = $true)][scriptblock]$Take)
    if ($Name -cnotmatch $script:HordeRelayChannelWordPattern) { throw ("a data kind is one lower-case word of up to 32 characters, not '" + $Name + "'") }
    $owner = Get-HordeRelayChannel -Name $Channel
    if ($null -eq $owner) { throw ("the data kind '" + $Name + "' names the channel '" + $Channel + "', which is not registered") }
    if ($owner.folder -cne $Folder) { throw ("the data kind '" + $Name + "' is registered from " + $Folder + ", not from its channel's folder " + $owner.folder) }
    if ($script:HordeRelayDataKinds.Contains($Name)) { throw ("the data kind '" + $Name + "' is already registered; the first registration stands") }
    foreach ($c in @($script:HordeRelayChannels.Values)) { if (@($c.kinds) -ccontains $Name) { throw ("the channel '" + $c.name + "' takes '" + $Name + "' as an envelope kind, so it cannot be a data kind") } }
    $d = [pscustomobject]@{ PSTypeName = "Horde.RelayDataKind"; name = $Name; channel = $Channel; take = $Take }
    $script:HordeRelayDataKinds[$Name] = $d
    return $d
}

function Get-HordeRelayDataKindOf {
    # The registered data kind an item's text opens with, or $null.
    param([AllowEmptyString()][string]$Text)
    $m = [regex]::Match($Text, $script:HordeRelayDataKindPattern)
    if (-not $m.Success -or -not $script:HordeRelayDataKinds.Contains($m.Groups[1].Value)) { return $null }
    return $script:HordeRelayDataKinds[$m.Groups[1].Value]
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
    # mailbox; connection; decisionsRoot; cursor; acked; state; full; untrimmed }, where openingKeys is the agreement keys
    # that may open (the current one and any retired one in its grace), state a table each channel
    # keeps its own memory in, by name, and full and untrimmed what the puts have told the run (the
    # header, WHAT A PUT TELLS THE RUN). The caller closes it (Close-HordeRelayRunContext). The identity's
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
        decisionsRoot = $DecisionsRoot; cursor = [long]0; acked = [long]0; state = @{}; full = @{}; untrimmed = @{}; refusedWith = @{}
    }))
}

function Update-HordeRelayRunContext {
    # The context opened again - its keys, after a rotation the new mailbox - KEEPING what the run has
    # learnt: the channels' memory (the last snapshot sent, an envelope recorded and not yet put) always,
    # and the cursor and the ack while the mailbox is the same one (review of 48bc492, finding 3: the
    # hourly reopen reset them and sent an identical snapshot again). Known, the new context, and the old
    # one's keys let go; the new context's answer when it cannot be opened, and the old one left as it is.
    param([Parameter(Mandatory = $true)]$Context, $Now = $null)
    $made = New-HordeRelayRunContext -HordeHome $Context.hordeHome -Connection $Context.connection -DecisionsRoot $Context.decisionsRoot -Now $Now
    if ($made.state -cne "known") { return $made }
    $made.value.state = $Context.state
    # What the puts have told the run is the run's too, and is about the relay, not the keys.
    $made.value.full = $Context.full; $made.value.untrimmed = $Context.untrimmed
    if ($null -ne $Context.PSObject.Properties["refusedWith"]) { $made.value.refusedWith = $Context.refusedWith }
    if ($made.value.mailbox -ceq $Context.mailbox) { $made.value.cursor = $Context.cursor; $made.value.acked = $Context.acked }
    Close-HordeRelayRunContext -Context $Context
    return $made
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
    # trust store's unknown. -Cache, a hashtable a caller keeps for one batch, holds the store's answer
    # after the first read: reading it re-verifies every record (about 63 ms, measured in the review of
    # 48bc492), and a batch of answers read it two or three times an item (finding 5).
    #
    # EACH PASSKEY CARRIES ITS SESSION MEMBER (channels/Sessions.ps1; relay/Session.ps1, WHAT THE MACHINE
    # TAKES): what this PC holds of its unlocked sessions, judged at -Now. Built once per -Cache and
    # dropped from it (Clear-HordeRelaySessionCache) whenever a vouch is recorded or a session used, so
    # the next envelope of the batch is judged by what the one before it changed.
    param($Context, $Channel, [hashtable]$Cache = $null, $Now = $null)
    if ($null -ne $Cache -and $Cache.ContainsKey("built")) { $built = $Cache["built"] }
    else {
        if ($null -ne $Cache -and $Cache.ContainsKey("all")) { $all = $Cache["all"] }
        else {
            $all = Find-HordeRelayTrustedSenders -HordeHome $Context.hordeHome -Now $Now
            if ($null -ne $Cache) { $Cache["all"] = $all }
        }
        if ($all.state -cne "known") { return $all }
        $built = $all
        $passkeys = @(@($all.value.Keys) | Where-Object { $all.value[$_].proof -ceq "webauthn" })
        if ($passkeys.Count -gt 0) {
            $records = Read-HordeRelaySessionRecords -HordeHome $Context.hordeHome
            $trust = Read-HordeRelayTrustStore -HordeHome $Context.hordeHome -Now $Now
            $built = New-HordeKnown -Value (Add-HordeRelaySessionPolicies -Context $Context -Senders $all.value -Records $records -Trust $trust -NowMs (ConvertTo-HordeRelayRecordMs -Time $Now))
        }
        if ($null -ne $Cache) { $Cache["built"] = $built }
    }
    if ($Channel.senders -ceq "horde") { return $built }
    $out = @{}
    foreach ($k in @($built.value.Keys)) { if ($built.value[$k].proof -ceq "webauthn") { $out[$k] = $built.value[$k] } }
    return (New-HordeKnown -Value $out)
}

function Clear-HordeRelaySessionCache {
    # The senders' session members are stale (a vouch recorded, a session used): built again on next ask.
    param([hashtable]$Cache = $null)
    if ($null -ne $Cache -and $Cache.ContainsKey("built")) { $Cache.Remove("built") }
}

function Get-HordeRelaySessionCode {
    # The session refusal code a reason starts with (relay/Session.ps1), or "".
    param([string]$Reason)
    foreach ($c in @(Get-HordeRelaySessionRefusals)) { if ($Reason.StartsWith($c + ":")) { return $c } }
    return ""
}

function Get-HordeRelayChannelBodyBudget {
    # The largest body one envelope to -Recipients recipients can carry over this context's relay: the
    # envelope's own cap (1 MiB), and what the relay's maxTextChars leaves once the text is base64url
    # (4 characters for 3 bytes, plus the 16-byte tag) and the header, the recipients and a signature
    # are written. The overhead is counted high: 1024 characters, and 300 for each recipient (a recipient
    # entry is about 190, measured 2026-10-09). A channel that pages its body sizes pages by this.
    param([Parameter(Mandatory = $true)]$Context, [int]$Recipients = 1)
    $text = [double]$Context.connection.relay.limits.maxTextChars - 1024 - 300 * [double]$Recipients
    $fits = [long][System.Math]::Floor($text * 3 / 4) - 16
    return [long][System.Math]::Max(0, [System.Math]::Min([double](Get-HordeRelayEnvelopeLimits).bodyBytes, [double]$fits))
}

function Save-HordeRelayChannelEnvelope {
    # Seal -Body to -Recipients (65-byte agreement keys), sign it as this machine and record it in the
    # journal - the first half of a send. Known { seq; key; text }: recorded, its seq spent, to be put
    # with Send-HordeRelayChannelSaved, again and again if need be. Unknown, with nothing recorded, when
    # it cannot be made, the journal will not record it, or its text is longer than the relay holds:
    # checked BEFORE the journal, so no seq is ever spent on an envelope no put could deliver (review of
    # 48bc492, finding 1).
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)][string]$Channel, [Parameter(Mandatory = $true)][string]$Kind,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Body, [Parameter(Mandatory = $true)][object[]]$Recipients, $Now = $null)
    $most = [long]$Context.connection.relay.limits.maxTextChars
    # Two tries: a second sender of this stream in another process may take the seq between the ask and
    # the record (Get-HordeRelayJournalNextSeq says so); the loser asks again once.
    for ($try = 1; $try -le 2; $try++) {
        $next = Get-HordeRelayJournalNextSeq -From $Context.signKeyId -Channel $Channel -HordeHome $Context.hordeHome
        if ($next.state -cne "known") { return (New-HordeUnknown -Reason ("nothing was recorded: no sequence number - " + $next.reason)) }
        try { $text = New-HordeRelayEnvelope -Kind $Kind -Channel $Channel -Seq $next.value -Body $Body -Recipients $Recipients -Signer $Context.signKey -Now $Now }
        catch { return (New-HordeUnknown -Reason "nothing was recorded: the envelope could not be made" -ErrorRecord $_) }
        if ($text.Length -gt $most) { return (New-HordeUnknown -Reason ("nothing was recorded: the envelope is " + $text.Length + " characters, more than the relay holds (" + $most + ")")) }
        $rec = Register-HordeRelayJournalSent -Text $text -HordeHome $Context.hordeHome -Now $Now
        if ($rec.state -cne "known") { return (New-HordeUnknown -Reason ("nothing was recorded: the journal did not record it - " + $rec.reason)) }
        if (-not $rec.value.fresh) { continue }
        return (New-HordeKnown -Value ([pscustomobject]@{ seq = [long]$next.value; key = $rec.value.key; text = $text }))
    }
    return (New-HordeUnknown -Reason "nothing was recorded: another sender of this stream took the next sequence number twice")
}

function Get-HordeRelayChannelKeepFrom {
    # The seq to keep from so that the stream of -Key holds its last -Keep envelopes once -Key is put
    # (the header, WHAT GOES TO THE PHONE IS TRIMMED BY ITS SENDER): the key's own seq less Keep, plus
    # one. 0 - ask for nothing - while the stream is not yet longer than that, for a key that names no
    # stream, and for a Keep under 1: a channel that keeps nothing of its own stream has a bug.
    param([Parameter(Mandatory = $true)][string]$Key, [Parameter(Mandatory = $true)][long]$Keep)
    $named = Read-HordeRelayStreamKey -Key $Key
    if ($null -eq $named -or $Keep -lt 1) { return [long]0 }
    return [long][System.Math]::Max([long]0, $named.seq - $Keep + 1)
}

function Get-HordeRelayChannelOfKey {
    # The channel an envelope's key names (<sender>/<channel>/<seq>/<nonce>), or "" for a key that names
    # no stream: what a refusal as full is kept under (the header, WHAT A PUT TELLS THE RUN).
    param([string]$Key)
    $named = Read-HordeRelayStreamKey -Key $Key
    if ($null -eq $named) { return "" }
    return $named.stream.Split([char]'/')[1]
}

function Send-HordeRelayChannelSaved {
    # Put an envelope Save-HordeRelayChannelEnvelope recorded into -Mailbox, under its replay key, so a
    # put made again is the same item. -KeepFrom, over 0, also asks the relay to delete what is before
    # that seq in the envelope's own stream (the header). Known { key; relaySeq; duplicate; trimmed } -
    # trimmed how many the relay deleted, -1 when none was asked or the relay did not say; unknown with
    # the relay's reason, and its status when it gave one. What the put told the run goes into the
    # context (the header, WHAT A PUT TELLS THE RUN).
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)]$Saved, [Parameter(Mandatory = $true)][string]$Mailbox, [long]$KeepFrom = 0)
    $put = Send-HordeRelayItem -Connection $Context.connection -Mailbox $Mailbox -Text $Saved.text -Key $Saved.key -KeepFrom $KeepFrom
    if ($put.state -cne "known") {
        $refused = New-HordeUnknown -Reason ("the envelope " + $Saved.key + " is recorded, and the relay did not take it: " + $put.reason)
        $status = $put.PSObject.Properties["status"]
        if ($null -ne $status) {
            $refused | Add-Member -NotePropertyName status -NotePropertyValue ([int]$status.Value)
            # Every status a put was refused with, for the runner to judge THIS turn's backoff by
            # (cli/RelayRun.ps1, BACKOFF); the runner empties it at the top of each turn.
            if ($null -ne $Context.PSObject.Properties["refusedWith"]) { $Context.refusedWith[[int]$status.Value] = $true }
            # FULL IS NOT ONE MORE FAILURE: it is kept, with the relay's own words, for the runner to say
            # plainly and to tell the warchief of.
            if ([int]$status.Value -eq 507) {
                if (-not $Context.full.ContainsKey($Mailbox)) { $Context.full[$Mailbox] = [pscustomobject]@{ mailbox = $Mailbox; reason = "$($put.reason)"; since = [datetime]::UtcNow; channels = @{} } }
                $Context.full[$Mailbox].channels[(Get-HordeRelayChannelOfKey -Key $Saved.key)] = $true
            }
        }
        return $refused
    }
    # TAKEN: this channel is no longer refused there. Another channel's mark stays (the header, full).
    if ($Context.full.ContainsKey($Mailbox)) {
        $Context.full[$Mailbox].channels.Remove((Get-HordeRelayChannelOfKey -Key $Saved.key))
        if ($Context.full[$Mailbox].channels.Count -eq 0) { $Context.full.Remove($Mailbox) }
    }
    if ($KeepFrom -gt 0) {
        if ($put.value.trimmed -lt 0) { $Context.untrimmed[$Mailbox] = $true }
        elseif ($Context.untrimmed.ContainsKey($Mailbox)) { $Context.untrimmed.Remove($Mailbox) }
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ key = $Saved.key; relaySeq = $put.value.seq; duplicate = $put.value.duplicate; trimmed = $put.value.trimmed }))
}

function Send-HordeRelayChannelEnvelope {
    # Record and put in one call (Save-HordeRelayChannelEnvelope, then Send-HordeRelayChannelSaved), for
    # a channel that keeps nothing to put again. Known { seq; key; relaySeq; duplicate }; unknown with the
    # reason, saying whether the envelope was recorded (its seq spent) before it failed.
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)][string]$Channel, [Parameter(Mandatory = $true)][string]$Kind,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Body, [Parameter(Mandatory = $true)][object[]]$Recipients, [Parameter(Mandatory = $true)][string]$Mailbox, $Now = $null)
    $saved = Save-HordeRelayChannelEnvelope -Context $Context -Channel $Channel -Kind $Kind -Body $Body -Recipients $Recipients -Now $Now
    if ($saved.state -cne "known") { return $saved }
    $put = Send-HordeRelayChannelSaved -Context $Context -Saved $saved.value -Mailbox $Mailbox
    if ($put.state -cne "known") { return $put }
    return (New-HordeKnown -Value ([pscustomobject]@{ seq = $saved.value.seq; key = $saved.value.key; relaySeq = $put.value.relaySeq; duplicate = $put.value.duplicate }))
}

function Test-HordeRelayInboundGate {
    # Step 3 of THE PATH IN: why a read envelope must be refused before the journal sees it, or "".
    # { why; channel; senders } - the channel and its senders when it may go on; unknown senders (the
    # trust store unreadable) is not a refusal of this envelope: why is "" and transient is $true.
    param($Context, $Envelope, [hashtable]$Cache = $null, $Now = $null)
    $h = $Envelope.header
    # BY NAME, FIRST, ON EVERY CHANNEL (DATA KINDS): a data kind is never an envelope's.
    if ($script:HordeRelayDataKinds.Contains("$($h.kind)")) { return [pscustomobject]@{ why = ("the kind " + $h.kind + " is data, which is never taken as an envelope on any channel"); transient = $false; channel = $null; senders = $null } }
    $ch = Get-HordeRelayChannel -Name $h.channel
    if ($null -eq $ch) { return [pscustomobject]@{ why = ("no channel '" + $h.channel + "' is registered here"); transient = $false; channel = $null; senders = $null } }
    if (@($ch.kinds) -cnotcontains $h.kind) { return [pscustomobject]@{ why = ("the channel " + $ch.name + " takes " + $(if (@($ch.kinds).Count) { @($ch.kinds) -join ", " } else { "nothing in" }) + ", not " + $h.kind); transient = $false; channel = $ch; senders = $null } }
    $senders = Get-HordeRelayChannelSenders -Context $Context -Channel $ch -Cache $Cache -Now $Now
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
    return [pscustomobject]@{ why = ""; transient = $false; channel = $ch; senders = $senders.value; verified = $verified.value }
}

function Receive-HordeRelayInbox {
    # Steps 1 to 5 of THE PATH IN: one watch of the machine's mailbox, every envelope in it judged and
    # journaled, the relay acked. Known { taken; refused; held; missing; anomalies; cursor; acked } -
    # taken: the replay keys journaled; refused: lines saying what was refused for good and why; held:
    # lines for what could not be judged now and comes again; missing: lines for envelopes of a sender
    # that the journal saw skipped (dropped, delayed or withheld by the relay: design Q11, "shown as
    # missing, never as silence"); data: a line for each data item taken or waiting; opened: when the batch
    # held a data item, the Invoke-HordeRelayUnfinished report of step 6 run before them, else $null.
    # Unknown when the relay could not be read.
    #
    # -Between, WITH -SliceMs, ON A RELAY THAT WATCHES IN SLICES (relays/Port.ps1, A WATCH IN SLICES): the
    # same one watch, held open and waited on -SliceMs at a time, and after every slice in which nothing
    # came -Between is run, handed the context and -With (the caller's own, passed through untouched) -
    # which is where the runner looks for something to send while the watch is still open
    # (cli/RelayRun.ps1, SENDING DURING THE WATCH). A -Between that answers $true ends the watch there
    # (the runner was asked to stop); whatever arrived by then is the batch. On a relay that does not
    # watch in slices, and with no -Between, the watch blocks for its whole time, exactly as it always
    # did, and -Between is never run.
    param([Parameter(Mandatory = $true)]$Context, [int]$TimeoutMs = 0, $Now = $null, [int]$SliceMs = 0, [scriptblock]$Between = $null, $With = $null)
    if ($null -ne $Between -and $SliceMs -gt 0 -and (Test-HordeRelayWatchInSlices $Context.connection)) { $w = Wait-HordeRelayInboxInSlices -Context $Context -TimeoutMs $TimeoutMs -SliceMs $SliceMs -Between $Between -With $With }
    else { $w = Wait-HordeRelayItems -Connection $Context.connection -Mailbox $Context.mailbox -Since $Context.cursor -TimeoutMs $TimeoutMs }
    if ($w.state -cne "known") { return $w }
    return (Complete-HordeRelayInbox -Context $Context -Watched $w -Now $Now)
}

function Wait-HordeRelayInboxInSlices {
    # Step 1 of THE PATH IN on a relay that watches in slices: the batch Wait-HordeRelayItems would have
    # handed over, or its unknown - from ONE watch opened at the relay, however many slices it is waited
    # on in and whatever -Between does between them. The watch is always let go of, also when -Between
    # throws: that is a fault of the caller's own code, and is the caller's to see.
    param([Parameter(Mandatory = $true)]$Context, [int]$TimeoutMs, [int]$SliceMs, [Parameter(Mandatory = $true)][scriptblock]$Between, $With = $null)
    $opened = Open-HordeRelayWatch -Connection $Context.connection -Mailbox $Context.mailbox -Since $Context.cursor -TimeoutMs $TimeoutMs
    if ($opened.state -cne "known") { return $opened }
    # A slice no longer than this relay lets a watch be: the port refuses a longer one.
    $eachMs = [int][System.Math]::Max(1, [System.Math]::Min([double]$SliceMs, [double]$Context.connection.relay.limits.maxWatchMs))
    try {
        while ($true) {
            $slice = Wait-HordeRelayWatch -Watch $opened.value -WaitMs $eachMs
            if ($slice.state -cne "known" -or $slice.value.ended) { return $slice }
            $stop = @(& $Between $Context $With) | Select-Object -Last 1
            # ASKED ONCE MORE, WITHOUT WAITING, BEFORE IT IS LET GO: what arrived while -Between ran is
            # this batch's, and is journaled and acked now, not left for whoever watches next.
            if ($stop -is [bool] -and $stop) { return (Wait-HordeRelayWatch -Watch $opened.value -Last) }
        }
    } finally { Close-HordeRelayWatch -Watch $opened.value }
}

function Complete-HordeRelayInbox {
    # Steps 2 to 5 of THE PATH IN, for a batch somebody has already watched for: -Watched is the known
    # answer of Wait-HordeRelayItems, or of the Wait-HordeRelayWatch that ended a watch in slices
    # (relays/Port.ps1) - the same batch either way, so whether the runner blocked on its watch or sent
    # between slices of it, what arrived is judged, journaled and acked by this one piece of code.
    # Receive-HordeRelayInbox's answer.
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)]$Watched, $Now = $null)
    $w = $Watched
    $refused = New-Object System.Collections.ArrayList
    $held = New-Object System.Collections.ArrayList
    $taken = New-Object System.Collections.ArrayList
    $missing = New-Object System.Collections.ArrayList
    $parsed = New-Object System.Collections.ArrayList
    $settled = @{}
    # The trusted senders, read once for the whole batch (Get-HordeRelayChannelSenders).
    $senderCache = @{}
    $data = New-Object System.Collections.ArrayList
    # Refused data items BY REASON, said once each after the batch (below): a photo is up to 64 items.
    # Keyed ORDINALLY (review round 3 of PR 285): [ordered]@{} ignores case, so two reasons that differ
    # only in case - a hex digest, a photo id - would be folded into one line.
    $dataRefused = New-Object System.Collections.Specialized.OrderedDictionary -ArgumentList ([System.StringComparer]::Ordinal)
    $dataItems = New-Object System.Collections.ArrayList
    $vouched = New-Object System.Collections.ArrayList
    $joined = New-Object System.Collections.ArrayList
    foreach ($it in @($w.value.items)) {
        # A PHONE VOUCH ITEM is no envelope: it is its own proof, judged against the trust store as it is
        # NOW and never journaled (relay/Trust.ps1, THE VOUCH TRAVELS BY ITSELF). Refused or done, it is
        # settled; only a trust store that cannot be read holds it for the next turn.
        if (Test-HordeRelayPhoneVouchText -Text $it.text) {
            $pv = Receive-HordeRelayPhoneVouch -HordeHome $Context.hordeHome -Text $it.text -Now $Now
            if ($pv.outcome -ceq "held") { [void]$held.Add("item " + $it.seq + ": " + $pv.reason); continue }
            $settled[[long]$it.seq] = $true # a vouch, done or refused: acked
            if ($pv.outcome -ceq "done") { [void]$vouched.Add("item " + $it.seq + ": " + $pv.reason) } else { [void]$refused.Add("item " + $it.seq + ": " + $pv.reason) }
            continue
        }
        # A JOIN REQUEST is no envelope either: a new phone asking to join (relay/Join.ps1), recorded or
        # refused at once - it grants nothing - and answered by the join channel's Tick.
        if (Test-HordeRelayJoinRequestText -Text $it.text) {
            $jr = Receive-HordeRelayJoinRequest -HordeHome $Context.hordeHome -Text $it.text -Key $it.key -Now $Now
            if ($jr.outcome -ceq "held") { [void]$held.Add("item " + $it.seq + ": " + $jr.reason); continue }
            $settled[[long]$it.seq] = $true # a join request, recorded or refused: acked
            if ($jr.outcome -ceq "done") { [void]$joined.Add("item " + $it.seq + ": " + $jr.reason) } else { [void]$refused.Add("item " + $it.seq + ": " + $jr.reason) }
            continue
        }
        $r = Read-HordeRelayEnvelope -Text $it.text
        if (-not $r.ok) {
            # A DATA ITEM (the header, DATA KINDS) is set aside, and judged after the envelopes (below).
            $dk = Get-HordeRelayDataKindOf -Text $it.text
            if ($null -ne $dk) { [void]$dataItems.Add([pscustomobject]@{ item = $it; kind = $dk }); continue }
            [void]$refused.Add("item " + $it.seq + ": not an envelope (" + $r.reason + ")"); $settled[[long]$it.seq] = $true; continue
        }
        [void]$parsed.Add([pscustomobject]@{ item = $it; envelope = $r.value })
    }
    # Sorted by sender and that sender's seq (step 2). The relay's own order is not trusted to be theirs.
    $ordered = @($parsed | Sort-Object @{ Expression = { $_.envelope.header.from } }, @{ Expression = { [long]$_.envelope.header.seq } })
    $nowMs = ConvertTo-HordeRelayRecordMs -Time $Now
    # A VOUCH IS TAKEN BEFORE ANY ENVELOPE UNDER IT (relay/Session.ps1): a phone's seqs are per channel,
    # so its opening envelope (trust) and its first answer (decisions) may sort either way round, and an
    # answer judged first would be refused as session-unknown. So every vouch in the batch that verifies
    # in full - the passkey's assertion, the session signature, the binding, the window - is recorded
    # first. The vouch is the founder's own signature: recording it says nothing about the envelope,
    # which is judged and journaled below as any other.
    foreach ($p in @($parsed)) {
        $s = $p.envelope.sig
        if ($s.alg -cne "session" -or $null -eq $s.vouch) { continue }
        $g = Test-HordeRelayInboundGate -Context $Context -Envelope $p.envelope -Cache $senderCache -Now $Now
        if ($g.why -cne "" -or $null -eq $g.verified -or -not $g.verified.newVouch) { continue }
        try { $null = Add-HordeRelaySessionVouch -HordeHome $Context.hordeHome -By $p.envelope.header.from -Sig $s -NowMs $nowMs } catch { [void]$held.Add("the vouch " + $s.vouchId + " could not be recorded: " + $_.Exception.Message) }
        Clear-HordeRelaySessionCache -Cache $senderCache
    }
    foreach ($p in $ordered) {
        $h = $p.envelope.header
        $rk = Get-HordeRelayReplayKey -Header $h
        $gate = Test-HordeRelayInboundGate -Context $Context -Envelope $p.envelope -Cache $senderCache -Now $Now
        if ($gate.transient) { [void]$held.Add($rk + ": " + $gate.why); continue }
        if ($gate.why -cne "") {
            [void]$refused.Add($rk + ": " + $gate.why); $settled[[long]$p.item.seq] = $true
            # What the phone is told (channels/Sessions.ps1, Get-HordeRelaySessionStatus): the code only,
            # and only for a refusal given AFTER both signatures verified (relay/Session.ps1, checks 4
            # to 7) - review of PR 302: anything earlier may be a relay's forgery, which must neither
            # tell the phone something nor push the real refusals out of the newest kept.
            $code = Get-HordeRelaySessionCode -Reason $gate.why
            if ($p.envelope.sig.alg -ceq "session" -and @("session-stale", "session-ended", "session-expired", "session-idle") -ccontains $code) {
                $null = Add-HordeRelaySessionRefusal -HordeHome $Context.hordeHome -From $h.from -VouchId $p.envelope.sig.vouchId -Code $code -NowMs $nowMs
            }
            continue
        }
        # A NEW VOUCH IS TAKEN ONLY ONCE IT IS RECORDED (review of PR 302, must-fix 2): the vouch was
        # recorded above, so the gate now finds it held. One still new here was not recorded - the
        # write threw, was not confirmed on disk, or the name is another passkey's record - and every
        # envelope under it would be judged new, its idle clock never kept. It waits, and comes again.
        if ($p.envelope.sig.alg -ceq "session" -and $null -ne $gate.verified -and $null -ne $gate.verified.PSObject.Properties["newVouch"] -and $gate.verified.newVouch) {
            # A NAME THAT IS ANOTHER PASSKEY'S never frees itself, so waiting would hold the envelope
            # every turn, unacked, until the relay's caps (review of PR 302): refused by name, for good.
            $owner = Get-HordeRelaySessionRecordOwner -HordeHome $Context.hordeHome -VouchId $p.envelope.sig.vouchId
            if ($owner -cne "" -and $owner -cne $h.from) {
                [void]$refused.Add($rk + ": session-refused: the vouch id " + $p.envelope.sig.vouchId + " belongs to another passkey's session on this PC")
                $settled[[long]$p.item.seq] = $true
                continue
            }
            [void]$held.Add($rk + ": its session's vouch " + $p.envelope.sig.vouchId + " could not be recorded on this PC, so it waits")
            continue
        }
        $verdict = Register-HordeRelayJournalReceived -Envelope $p.envelope -Senders $gate.senders -RecipientKeyIds @($Context.openingKeys.Keys) -Channel $h.channel -Kind $h.kind -HordeHome $Context.hordeHome -Now $Now
        if ($verdict.state -cne "known") { [void]$held.Add($rk + ": the journal could not judge it - " + $verdict.reason); continue }
        $settled[[long]$p.item.seq] = $true
        if ($verdict.value.fresh -and $p.envelope.sig.alg -ceq "session") {
            # THE IDLE CLOCK STARTS AGAIN only for an envelope the journal took: a replay or a refusal
            # keeps no session alive.
            $why = Register-HordeRelaySessionSeen -HordeHome $Context.hordeHome -VouchId $p.envelope.sig.vouchId -NowMs $nowMs
            if ($why -cne "") { [void]$held.Add("the session " + $p.envelope.sig.vouchId + " was used, and that could not be kept: " + $why) }
            Clear-HordeRelaySessionCache -Cache $senderCache
        }
        if ($verdict.value.fresh) {
            [void]$taken.Add($rk)
            if ([long]$verdict.value.gapBefore -gt 0) { [void]$missing.Add($rk + ": " + $verdict.value.gapBefore + " envelope(s) of this sender before it are missing") }
        }
        else { [void]$refused.Add($rk + ": " + $verdict.value.why) }
    }
    # ENVELOPES ARE OPENED BEFORE DATA ITEMS ARE JUDGED (review round 4 of PR 285): step 6 runs here, on
    # what was just journaled, when the batch holds a data item - so a photo's signed manifest is
    # verified and accepted before its parts are judged, and they are taken at once, never left in the
    # pending area for junk to crowd. Until round 4 data came first, and every genuine photo's parts
    # waited there for a manifest in the same batch. A BATCH WITH NO DATA ITEM - every chat line,
    # answer, follow and receipt - takes exactly the path it always did: nothing is opened here, and the
    # runner's own step 6 opens it after this returns (test-relay-channels, test-relay-channel-chat). What
    # is opened here is said by the runner from opened, in the words of its own step 6.
    $opened = $null
    if ($dataItems.Count -gt 0) {
        $un = Invoke-HordeRelayUnfinished -Context $Context -Now $Now
        if ($un.state -ceq "known") { $opened = $un.value }
    }
    foreach ($d in $dataItems) {
        # To its kind's Take alone, settled whatever it says.
        $it = $d.item
        $dk = $d.kind
        $settled[[long]$it.seq] = $true
        $got = $null
        try { $got = @(& $dk.take $Context $it.text) | Select-Object -Last 1 } catch { [void]$refused.Add("item " + $it.seq + ": " + $dk.name + " refused: its taker failed: " + $_.Exception.Message); continue }
        $said = $(if ($null -ne $got -and $null -ne $got.PSObject.Properties["reason"]) { "$($got.reason)" } else { "" })
        if ($null -eq $got -or $null -eq $got.PSObject.Properties["outcome"] -or $script:HordeRelayDataOutcomes -cnotcontains "$($got.outcome)") { [void]$refused.Add("item " + $it.seq + ": " + $dk.name + " refused: its taker answered with something that is not taken, pending or refused"); continue }
        if ("$($got.outcome)" -ceq "refused") {
            if (-not $dataRefused.Contains($said)) { $dataRefused[$said] = New-Object System.Collections.ArrayList }
            [void]$dataRefused[$said].Add([long]$it.seq)
        } else { [void]$data.Add("item " + $it.seq + ": " + $said) }
    }
    # ONE LINE A REASON (review of PR 285): data items refused for the same reason - every part of a photo
    # a runtime cannot take says the same thing - are one line naming how many, not a line each. A reason
    # that names its part (a digest, a number) stays a line of its own. "items A to B" only when they are
    # every seq from A to B; otherwise each is named, or, past 8, how many and the first and last
    # (review round 3 of PR 285): items of other reasons, or envelopes, may lie between them. The seqs
    # are SORTED first (review round 4): the relay's order is not trusted, and 3, 1, 5 read as a range
    # of its first and last was "items 3 to 5 (3)".
    foreach ($why in @($dataRefused.Keys)) {
        $seqs = @(@($dataRefused[$why]) | Sort-Object)
        $span = $(if ($seqs.Count -eq 1) { "item " + $seqs[0] }
            elseif ([long]$seqs[$seqs.Count - 1] - [long]$seqs[0] -eq $seqs.Count - 1) { "items " + $seqs[0] + " to " + $seqs[$seqs.Count - 1] + " (" + $seqs.Count + ")" }
            elseif ($seqs.Count -le 8) { "items " + ($seqs -join ", ") }
            else { $seqs.Count.ToString() + " items, the first " + $seqs[0] + " and the last " + $seqs[$seqs.Count - 1] })
        [void]$refused.Add($span + ": " + $why)
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
    return (New-HordeKnown -Value ([pscustomobject]@{ taken = @($taken.ToArray()); refused = @($refused.ToArray()); held = @($held.ToArray()); missing = @($missing.ToArray()); anomalies = @($w.value.anomalies); cursor = $Context.cursor; acked = $Context.acked; vouched = @($vouched.ToArray()); joined = @($joined.ToArray()); data = @($data.ToArray()); opened = $opened }))
}

function Invoke-HordeRelayUnfinished {
    # Step 6 of THE PATH IN: every journaled record of every registered channel that no channel has
    # finished, opened and handed to its channel. Known { done; refused; retry } - lines, one per record.
    # Unknown never: a channel whose journal cannot be read is a retry line, and the others go on.
    param([Parameter(Mandatory = $true)]$Context, $Now = $null)
    $done = New-Object System.Collections.ArrayList
    $refused = New-Object System.Collections.ArrayList
    $retry = New-Object System.Collections.ArrayList
    # The trusted senders, read once for every record of this call, and only if there is one to open.
    $senderCache = @{}
    foreach ($name in @(Get-HordeRelayChannelNames)) {
        $ch = Get-HordeRelayChannel -Name $name
        $list = Get-HordeRelayJournalUnfinished -Channel $name -HordeHome $Context.hordeHome
        if ($list.state -cne "known") { [void]$retry.Add("channel " + $name + ": " + $list.reason); continue }
        foreach ($u in @($list.value)) {
            $outcome = Invoke-HordeRelayChannelRecord -Context $Context -Channel $ch -Record $u -Cache $senderCache -Now $Now
            $line = $u.key + ": " + $outcome.reason
            if ($outcome.outcome -ceq "retry") { [void]$retry.Add($line); continue }
            $mark = Complete-HordeRelayJournalReceived -From $u.from -Channel $name -Seq $u.seq -HordeHome $Context.hordeHome -Now $Now
            if ($mark.state -cne "known") { [void]$retry.Add($line + "; but it could not be marked done (" + $mark.reason + "), so it comes again"); continue }
            if ($outcome.outcome -ceq "done") { [void]$done.Add($line) } else { [void]$refused.Add($line) }
        }
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ done = @($done.ToArray()); refused = @($refused.ToArray()); retry = @($retry.ToArray()) }))
}

function Open-HordeRelayChannelRecord {
    # One journaled record of a channel, opened: { ok; outcome; reason; item }, where item is what the
    # channel's Accept is handed (Invoke-HordeRelayChannelRecord, below, says what is in it). Not ok: outcome
    # refused (the record can never be opened) or retry (the trust store cannot be read now), with the reason.
    # Reads only. The ONE place a journaled record is opened, so a channel that must read a record it
    # has already finished (channels/chat: the words of a line it still waits to see taken) opens it exactly
    # as the runner did.
    #
    # -Reread: the record was opened once already and its line accepted; it is read again for its words
    # alone (channels/chat/Taken.ps1: the receipt of a line already accepted must not depend on a
    # session that has since ended, gone idle or been pruned). The sender is not judged again; the
    # envelope's parts, the journal's verdict and the body's own authentication still are
    # (Unprotect-HordeRelayEnvelope, -Reread). Never use it to hand a record to an Accept.
    param($Context, $Channel, $Record, [hashtable]$Cache = $null, $Now = $null, [switch]$Reread)
    $no = { param([string]$Outcome, [string]$Why) return [pscustomobject]@{ ok = $false; outcome = $Outcome; reason = $Why; item = $null } }
    if ($script:HordeRelayDataKinds.Contains("$($Record.kind)")) { return (& $no "refused" ("the kind " + $Record.kind + " is data, which is never handed to a channel's Accept")) }
    if (@($Channel.kinds) -cnotcontains $Record.kind) { return (& $no "refused" ("the channel " + $Channel.name + " no longer takes the kind " + $Record.kind)) }
    $r = Read-HordeRelayEnvelope -Text $Record.text
    if (-not $r.ok) { return (& $no "refused" ("the journaled text is not an envelope: " + $r.reason)) }
    if ($Reread) {
        $opened = Unprotect-HordeRelayEnvelope -Envelope $r.value -RecipientKeys $Context.openingKeys -Replay $Record.verdict -Channel $Channel.name -Kind $Record.kind -Reread
    } else {
        $senders = Get-HordeRelayChannelSenders -Context $Context -Channel $Channel -Cache $Cache -Now $Now
        if ($senders.state -cne "known") { return (& $no "retry" ("the trust store cannot be read: " + $senders.reason)) }
        # The senders trusted NOW: a device revoked since the record was made opens nothing.
        $opened = Unprotect-HordeRelayEnvelope -Envelope $r.value -Senders $senders.value -RecipientKeys $Context.openingKeys -Replay $Record.verdict -Channel $Channel.name -Kind $Record.kind
    }
    if (-not $opened.ok) { return (& $no "refused" ("not opened: " + $opened.reason)) }
    $proof = $(if ($r.value.sig.alg -ceq "session") { "session" } elseif ($r.value.sig.alg -ceq "ES256") { "es256" } else { "webauthn" })
    $vouchId = $(if ($proof -ceq "session") { $r.value.sig.vouchId } else { "" })
    $item = [pscustomobject]@{ from = $Record.from; channel = $Channel.name; kind = $Record.kind; seq = $Record.seq; key = $Record.key; evidence = $Record.evidence; ts = [long]$r.value.header.ts; body = [byte[]]$opened.value; proof = $proof; vouchId = $vouchId }
    return [pscustomobject]@{ ok = $true; outcome = ""; reason = ""; item = $item }
}

function Invoke-HordeRelayChannelRecord {
    # One unfinished record: open it and hand it to its channel. { outcome; reason }.
    # The item also says HOW its sender signed it (proof: webauthn, a fresh passkey assertion; session,
    # a session key the passkey vouched for at unlock, with its vouchId; es256, a machine), so a channel
    # can ask for a fresh passkey where it must (channels/decisions, needsPasskey). A session envelope is
    # judged again here against the PC's session records NOW: ended or past its cap since it was
    # journaled, it opens nothing.
    param($Context, $Channel, $Record, [hashtable]$Cache = $null, $Now = $null)
    $o = Open-HordeRelayChannelRecord -Context $Context -Channel $Channel -Record $Record -Cache $Cache -Now $Now
    if (-not $o.ok) { return [pscustomobject]@{ outcome = $o.outcome; reason = $o.reason } }
    $item = $o.item
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
    # The path out: every channel's Tick, in name order. { lines; failed } - lines each starting with its
    # channel's name; failed when any channel said it failed, or threw. A channel that throws is a line,
    # and the others still run.
    #
    # againMs: a Tick may say how soon it wants to be turned again (its answer's againMs, over 0) - the
    # decisions channel's bell does, for the end of a quiet period. The soonest of them is returned, 0
    # when none asked, and the run's next watch waits no longer than that (cli/RelayRun.ps1).
    #
    # -Only names the channels to tick, for the runner's look during a watch (Find-HordeRelayChannelsToSend):
    # the others are left for the turn's own Tick. Not given, every channel is ticked.
    param([Parameter(Mandatory = $true)]$Context, $Now = $null, [string[]]$Only = $null)
    $out = New-Object System.Collections.ArrayList
    $failed = $false
    $again = 0
    foreach ($name in @(Get-HordeRelayChannelNames)) {
        $ch = Get-HordeRelayChannel -Name $name
        if ($null -eq $ch.tick) { continue }
        if ($null -ne $Only -and @($Only) -cnotcontains $name) { continue }
        try {
            $got = @(& $ch.tick $Context)
            $lines = $got
            if ($got.Count -eq 1 -and $null -ne $got[0] -and $got[0] -isnot [string] -and $null -ne $got[0].PSObject.Properties["lines"]) {
                $lines = @($got[0].lines)
                if ($null -ne $got[0].PSObject.Properties["failed"] -and $got[0].failed -eq $true) { $failed = $true }
                $ask = $got[0].PSObject.Properties["againMs"]
                if ($null -ne $ask -and $ask.Value -is [int] -and $ask.Value -gt 0 -and ($again -eq 0 -or $ask.Value -lt $again)) { $again = [int]$ask.Value }
            }
            foreach ($l in $lines) { if ("$l" -ne "") { [void]$out.Add($name + ": " + $l) } }
        }
        catch { [void]$out.Add($name + ": failed: " + $_.Exception.Message); $failed = $true }
    }
    return [pscustomobject]@{ lines = @($out.ToArray()); failed = $failed; againMs = $again }
}

function Find-HordeRelayChannelsToSend {
    # Every channel's Glance (the header), in name order: { due; lines } - due the names of the channels
    # whose Glance said yes, for Invoke-HordeRelayChannelTicks -Only; lines one for each Glance that
    # threw. ONLY A PLAIN $true IS A YES: a Glance that throws, or answers with anything else, is a no -
    # the channel's Tick still runs once a turn, as it would with no Glance at all - so a broken Glance
    # can cost the speed it was meant to give and nothing more.
    param([Parameter(Mandatory = $true)]$Context)
    $due = New-Object System.Collections.ArrayList
    $lines = New-Object System.Collections.ArrayList
    foreach ($name in @(Get-HordeRelayChannelNames)) {
        $ch = Get-HordeRelayChannel -Name $name
        if ($null -eq $ch.tick -or $null -eq $ch.glance) { continue }
        try {
            $said = @(& $ch.glance $Context) | Select-Object -Last 1
            if ($said -is [bool] -and $said) { [void]$due.Add($name) }
        }
        catch { [void]$lines.Add($name + ": could not look for something to send, so it is sent at the end of the watch: " + $_.Exception.Message) }
    }
    return [pscustomobject]@{ due = @($due.ToArray()); lines = @($lines.ToArray()) }
}
