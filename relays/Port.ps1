# relays/Port.ps1 - the relay port: an untrusted mailbox store that the relay module speaks through.
#
# WHAT A RELAY IS (relay design 2026-10-09, section 3 and PR plan item 3). A relay holds opaque texts -
# sealed, signed envelopes (relay/Envelope.ps1) - in named mailboxes, numbers each one, and hands them
# back by cursor. Machines connect to it outbound only, so it is the one place a phone and the
# machines of one horde meet. Each relay is a folder, relays/<name>/, holding Relay.ps1 (its code),
# capabilities.json (what it can do and its limits, as data, checked against
# schema/relay-capabilities.v1) and test/Fixture.ps1 (how test/test-relay-conformance.ps1 drives it).
# This file names no relay: the next one (the hosted one) is a new folder, not an edit here.
#
# THE RELAY IS UNTRUSTED, AND THIS PORT IS WHERE THAT IS ENFORCED FOR EVERY ADAPTER AT ONCE. The design's
# threat model gives the relay the power to see metadata and to drop, delay, reorder or repeat what it
# holds, and denies it the power to read or forge. So:
#   - THE PORT NEVER OPENS A TEXT. It does not parse, decrypt or verify an envelope and never loads the
#     envelope code; authenticity is the envelope's signature, replay and gaps per sender are the
#     journal's (a sibling pull request). A text here is only a string of printable ASCII within a size.
#   - THE PORT NEVER BELIEVES AN ITEM. Every item a relay hands back is checked for shape, and the batch
#     is rebuilt by the port: malformed items, items at or before the cursor, a second item under one
#     seq, and items past the batch asked for are dropped, each as an anomaly that says why; the rest
#     are put in seq order; a hole between two delivered seqs is reported as a gap. The cursor the
#     caller gets is the port's own - the last seq it delivered - never a number the relay chose, so it
#     never moves backwards and never past an item that was not handed over. A relay that drops items
#     can still make them vanish; that is the journal's to notice (per-sender seq), and the gap anomaly
#     is the early sign.
#   - THE PORT NEVER THROWS FOR THE FAR END. A relay that throws, or answers with something that is not
#     a core/tristate answer, or with a receipt or ack that does not hold together, comes back unknown
#     with the reason. Only a relay registered through Register-HordeRelay is called, and only through a
#     connection Connect-HordeRelay made: a look-alike object is refused (the messenger port's lesson,
#     review of #102, finding 6).
#
# ADDRESSING. A mailbox is "<horde>/<reader>": the horde (one Thrall's fleet, which may span machines,
# relay design Q10) and the one party that reads it - "phone", or a machine's key id. One reader per
# mailbox, so one acker, and one writer per direction (design Q15) is the channels' to keep. Each part
# is 1 to 63 of [a-z0-9-], starting with a letter or digit, and never a Windows device name: a relay that
# keeps mailboxes as folders (relays/local) must not be handed "con" or "..". The port does not know what
# a horde or a reader is; the channels name them.
#
# THE OPERATIONS, each a tristate answer:
#   Connect-HordeRelay        -Name -Options                    -> known connection
#   Send-HordeRelayItem       -Connection -Mailbox -Text [-Key] [-KeepFrom] -> known { mailbox; key; seq; duplicate; trimmed }
#   Receive-HordeRelayItems   -Connection -Mailbox -Since [-Max] -> known { mailbox; since; next; items; anomalies }
#   Wait-HordeRelayItems      as Receive, plus -TimeoutMs: returns as soon as there is anything after
#                             -Since, or empty when the time is up (long-poll, design Q8); plus waitedMs
#   Confirm-HordeRelayItems   -Connection -Mailbox -Through     -> known { mailbox; through }
#   Open-HordeRelayWatch, Wait-HordeRelayWatch, Close-HordeRelayWatch: the same watch, held open and
#                             waited on a slice at a time, on a relay that can (A WATCH IN SLICES, below)
# An item is { seq; key; text }. seq is the relay's number for it in its mailbox: 1 for the first put,
# then contiguous, never reused, at most 2^53-1 (so a browser reads it exactly). The cursor is a seq: 0
# is "before everything", and a read returns the items after it.
#
# PUT IS IDEMPOTENT BY KEY. The key is the caller's: an envelope's replay key (from/channel/seq/nonce,
# Get-HordeRelayReplayKey), or, when none is given, "sha256-" and the text's hash. A put of a key the
# mailbox still holds stores nothing and answers the held item's seq with duplicate = true - the first
# put stands even if the text differs, because a passkey may sign one content twice (relay/Envelope.ps1,
# "the signature is not part of an envelope's identity"). A relay that ignores this only costs a
# duplicate the journal refuses.
#
# ACK IS A PROMISE, NOT A REQUEST TO FORGET. Confirm-HordeRelayItems says the reader has kept (journaled)
# everything through a seq; a relay that declares trim.on.ack then deletes those items (design Q16), and
# one that does not keeps them until its retention ends. Either way a later read after the acked cursor
# is unaffected, and a reader acks only what it has kept. An ack past the mailbox's head is the relay's
# to refuse.
#
# CAPABILITIES ARE CLAIMS, AND ONLY "yes" COUNTS (the vocabulary of the host, transport and messenger
# ports). The closed list is durable, realtime, reach.remote and trim.on.ack; the limits are maxTextChars,
# maxBatch, maxWatchMs and retentionSeconds, each held under this port's ceiling at registration. A
# caller picks with Find-HordeRelay -Require (every relay that has all of them) or Resolve-HordeRelay
# -Name -Require; a channel between machines requires reach.remote, which a relay on one disk lacks.
#
# ADAPTER CONTRACT. relays/<name>/Relay.ps1 is dot-sourced at script level and calls Register-HordeRelay
# with five script blocks. Each answers with a core/tristate answer; the port has already checked every
# argument, and checks every answer:
#   Connect param($Options)                                    -> known state (anything the others take)
#   Put     param($State, [string]$Mailbox, [string]$Key, [string]$Text) -> known { seq; duplicate }
#   Get     param($State, [string]$Mailbox, [long]$Since, [int]$Max)     -> known { items }
#   Watch   param($State, [string]$Mailbox, [long]$Since, [int]$Max, [int]$TimeoutMs) -> known { items }
#   Ack     param($State, [string]$Mailbox, [long]$Through)    -> known { through }
# An adapter refuses a text over its own maxTextChars by itself too: the port's check protects the
# adapter from this caller, not the relay from every caller.
# A REFUSAL MAY SAY MORE THAN ITS REASON. An unknown answer may carry status (the relay's whole-number
# status, 100 to 599: 401 refused, 429 rate-limited) and retryAfterMs (how long the relay asked to be
# left, 0 to a day); the port passes each on, as a member of its own unknown, only when it holds. So a
# caller can tell "the relay refuses this machine" from "the relay is down", and wait as long as asked,
# without reading the relay's words (cli/RelayPair.ps1, the founder's first live use, 2026-10-11).
#
# DEPLOYING, FOR A RELAY THAT IS HOSTED. A relay that runs somewhere it must first be put (the hosted
# one) also hands Register-HordeRelay a sixth block, -Deploy; a relay on this disk has none. The caller
# (`horde relay deploy`, cli/RelayDeploy.ps1) builds what the relay is to serve - the phone app, as a
# folder of static files - so the relay never names the app and the app never names the relay:
#   Deploy  param([string]$Site, [scriptblock]$Say, [string]$HordeHome) -> known { origin }
# Publish-HordeRelay runs it and checks its answer as it checks every other; Get-HordeRelayDeployable
# names the relays that have one.
#
# A RELAY THAT COUNTS REQUESTS (the hosted one: a request a day per account is its limit) may also hand
# Register-HordeRelay -RunWatchMs: how long a long-running runner's watch waits on it (cli/RelayRun.ps1).
# A runner's quiet turn is one watch, so this is what one always-on machine costs it a day. 0, the
# default, declares none, and the runner's own setting applies. It is held to 1..maxWatchMs.
#
# A WATCH IN SLICES, FOR A RELAY THAT CAN HOLD ONE OPEN WHILE ITS CALLER DOES SOMETHING ELSE. Watch, above,
# blocks its caller for the whole wait: a runner with something to SEND one second into a 60 s watch
# could send it only when the watch ended, so the founder saw his own message go and then nothing for up
# to a minute (measured 2026-10-13 with a real run over the local relay and an 8 s watch: a note written
# about a second into the watch reached the phone's mailbox 6.9 s later, three times of three). A
# shorter watch is not the answer where requests are counted: a 2 s watch is 43,200 requests a day
# against a day of 20,000. So a relay may also hand Register-HordeRelay three more blocks, all or none:
#   WatchOpen  param($State, [string]$Mailbox, [long]$Since, [int]$Max, [int]$TimeoutMs) -> known handle
#              the watch is open at the relay from now, for TimeoutMs: for a relay that counts requests
#              this is the ONE request the whole watch costs. The handle is the relay's own - anything
#              the other two take.
#   WatchWait  param($State, $Handle, [int]$WaitMs) -> known { ended; items }
#              wait up to WaitMs more on the watch already open, COSTING THE RELAY NOTHING: ended is
#              $true, with the items, once something came or the watch's own time is up; $false, with
#              no items, when only this slice is over and the watch is still open.
#   WatchClose param($State, $Handle)   let go of it; what it answers is not read.
# Between two slices the caller may put, read or ack on the same connection: the watch stays open. The
# port keeps the watch's time by its own clock (a WatchWait that never says ended is ended by the port
# when the time is up), checks that ended is a true or a false, and rebuilds the items exactly as it
# rebuilds a blocking watch's. A relay that hands over none of the three is watched as it always was,
# by Watch; a caller asks Test-HordeRelayWatchInSlices before it opens one. NOT A CAPABILITY OF THE
# CLOSED LIST: nothing picks a relay by it (Find-HordeRelay -Require) - a caller adapts to what the relay
# it was given can do, as it does to -Deploy and -RunWatchMs - and test/test-relay-conformance.ps1
# holds every relay that hands the three over to what is written here.
#
# A SENDER TRIMS ITS OWN STREAM, FOR A MAILBOX NOBODY ACKS (2026-10-13). The phone's mailbox,
# <horde>/phone, is read by every trusted phone of the horde and acked by none of them - one phone's ack
# would delete what another has not read, and a phone paired tomorrow must still find the state - so
# nothing ever left it but by retention, 30 days on the hosted relay, whose mailbox holds 2,000
# envelopes. A machine puts a whole new decisions snapshot there at every change of the list and an
# envelope for every batch of chat and of progress, since today within a second of each: reckoned from
# the channels' own numbers that is some hundreds to over a thousand envelopes a working day, so the
# mailbox was days from full, and full means every put refused and the founder's phone silent.
# WHO KNOWS WHAT IS DEAD WEIGHT IS THE SENDER: an older snapshot the moment a newer one is whole in the
# mailbox, chat past the history a phone is shown. And the relay can act on that WITHOUT READING
# ANYTHING, because an envelope's key already names its stream: <sender key id>/<channel>/<seq>/<nonce>
# (relay/Envelope.ps1, Get-HordeRelayReplayKey). So a put may carry -KeepFrom, a seq OF THAT STREAM:
#   "of the items in this mailbox whose key is <the same sender>/<the same channel>/<n>/..., keep those
#    with n at or after KeepFrom, and delete the rest".
# The stream is never named apart from the put: it is the stream of the key being put, so a put can
# only ever trim the stream it adds to. KeepFrom is 1 to that key's own seq, so a put never deletes
# itself, and nothing newer. The trim costs no request of its own: it rides on a put that was being
# made anyway (the hosted relay counts requests).
#   - ONLY WHEN THE PUT IS TAKEN, or was a duplicate of an item still held. A put the relay refuses
#     trims nothing: a snapshot's last page carries the trim of the snapshot before it, and a last page
#     that is refused must leave that older snapshot whole - the phone is never left with none.
#   - WHOSE STREAM IT IS, is the relay's to hold (the hosted one answers a machine only by its signed
#     requests, and lets it trim only keys that begin with that very key id; a phone may not trim at
#     all - its own folder says how). The port cannot check it and does not pretend to: a relay
#     that trims what it should not has only dropped items, which it could always do.
#   - AN OPTIONAL BLOCK, NOT A CAPABILITY OF THE CLOSED LIST, for the reason the watch in slices is not:
#     nothing picks a relay by it, a caller adapts. A relay that can hands Register-HordeRelay
#       PutKeeping param($State, [string]$Mailbox, [string]$Key, [string]$Text, [long]$KeepFrom)
#                  -> known { seq; duplicate; trimmed }
#     trimmed is how many items it deleted, a whole number; a relay whose far end took the put and
#     said nothing of a trim (an older deployment of the hosted relay) leaves it out. On a relay with
#     no such block the put is made as it always was. Either way Send-HordeRelayItem answers trimmed
#     -1 for "not trimmed, or not said", and the caller says so once, in words (cli/RelayRun.ps1): a
#     mailbox that is not being trimmed is one that fills.
# test/test-relay-conformance.ps1 holds every relay that hands the block over to what is written here.
#
# WHICH FILES ON THIS MACHINE HOLD A RELAY'S SECRETS, ASKED WITHOUT NAMING A RELAY (2026-10-13). Sharing a
# file with a phone (files/) refuses the files in secret places, and one secret file it cannot know of:
# the file a hosted relay's deploy reads its sign-in client from. WHERE THAT FILE IS, IS A SETTING OF
# THAT ONE RELAY - it may point anywhere and the file may have any name - and nothing outside a relay's
# own folder may name the relay to read its setting (CONTRIBUTING rule 14). A survey of the 17 settings
# declarations in the repository on that day found it the only setting that names a secret file. So the
# question is the port's to answer for every caller: a relay that keeps a secret in a file on this
# machine also hands Register-HordeRelay
#   SecretFiles param([string]$HordeHome) -> known { files }, each { path; what }
#               path is absolute; what is a few fixed words for a person - "the sign-in client file" -
#               and NEVER a secret, a setting's value or anything read from the file. Absent when it
#               keeps none here; unknown, with the reason, when it cannot tell - its settings do not
#               read, a setting is not an absolute path.
# and Get-HordeRelaySecretFiles [-HordeHome] asks every loaded relay that handed one over and gives ONE
# answer: known { files; asked } - every entry as { relay; path; what }, asked the relays that were
# asked - only when EVERY one of them answered known or absent; unknown, naming each relay that could
# not tell and why (and carrying their names as its member relays), when any did not. ONE RELAY THAT
# CANNOT TELL MAKES THE WHOLE ANSWER UNKNOWN, ON PURPOSE: the caller is deciding whether a file may
# leave the machine, and a list with a hole in it read as the whole list is the one mistake this exists
# to stop, so the caller can fail closed. A relay with no such block keeps no secret file and is not
# asked; with no relay loaded at all the answer is known and empty.
#   - IT ASKS FOR PATHS AND NOTHING ELSE. Nothing here connects to a relay, starts a process, or opens,
#     lists or tests for a secret file: a file that is not there yet is still named, because the
#     question is where a secret WOULD be. The block reads its relay's settings, and that is all.
#   - THE PORT NEVER THROWS FOR THE RELAY, here as everywhere: a block that throws, answers with
#     something that is not an answer, or names a file by a path that is not absolute or by words that
#     are not 1 to 80 printable ASCII characters, is a relay that could not tell.
#   - EVERY PATH IS HANDED BACK WHOLE: absolute, and with its "." and ".." parts folded away
#     ([System.IO.Path]::GetFullPath, which reads no disk), so a setting written C:\a\..\b\key.json is
#     named as the file it opens. A link, a junction and a short 8.3 name are NOT resolved - that would
#     mean reading the disk - so a caller that compares paths must bring its own to the same form.
#   - AN OPTIONAL BLOCK, NOT A CAPABILITY OF THE CLOSED LIST, for the reason the watch in slices and the
#     trim are not: nothing picks a relay by it (Find-HordeRelay -Require), and a "yes" there is a claim
#     about what the far end can do, shown by a case - this is a fact about this machine's disk.
# A CALLER MUST HAVE LOADED THE RELAYS, at its own script level, exactly as every other caller of the
# port does (Get-HordeRelayFiles): a relay that was never loaded is never asked, and the answer's asked
# is how a caller sees who was. test/test-relay-conformance.ps1 holds every relay that hands the block
# over to what is written here.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Tristate.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Schema.ps1")

if ($null -eq (Get-Variable -Name HordeRelays -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeRelays = @{} }
if ($null -eq (Get-Variable -Name HordeRelayConnections -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeRelayConnections = @{} }
# The watches open in slices now (Open-HordeRelayWatch), by id: only one of these is ever waited on.
if ($null -eq (Get-Variable -Name HordeRelayWatches -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeRelayWatches = @{} }
$script:HordeRelayCapabilityNames = @("durable", "realtime", "reach.remote", "trim.on.ack")
# THE CEILINGS. textChars is relay/Envelope.ps1's text cap (Get-HordeRelayEnvelopeLimits: base64url of a
# 1 MiB body plus 16 KiB), copied and not loaded because the port never loads envelope code;
# test/test-relay-port.ps1 fails if the two ever differ. batch: a read of 256 items at that cap is about
# 360 MB, already more than any caller should hold, and a phone's read is far smaller. watchMs: the
# design's long-poll is about 25 s (Q8, spike S3); 60 s leaves room for a host that holds longer, and
# no more, so a stuck watch is noticed within a minute. seqMax is 2^53-1, the largest whole number a
# browser's JSON reads exactly (the envelope's maxInteger).
$script:HordeRelayTextChars = 1414507
$script:HordeRelayBatchMax = 256
$script:HordeRelayWatchMsMax = 60000
$script:HordeRelaySeqMax = [long]9007199254740991
# The longest Retry-After a refusal may carry to the caller: a day. The relay is untrusted, and a caller
# that waits as long as it asks must not be told to wait for ever; a longer one is left out.
$script:HordeRelayRetryAfterMaxMs = [long]86400000
$script:HordeRelaySegmentPattern = '\A[a-z0-9][a-z0-9-]{0,62}\z'
# Windows device names, which a folder or file of that name (with any extension) would open instead.
$script:HordeRelayDeviceNamePattern = '\A(con|prn|aux|nul|com[0-9]|lpt[0-9])\z'
# An envelope's replay key is <32 hex>/<channel>/<seq>/<24 hex>, at most 107 characters; a content hash
# key is 71. 160 is room for either with a longer channel name, and no more.
$script:HordeRelayKeyPattern = '\A[A-Za-z0-9._:/-]{1,160}\z'
# A key that names its stream (the header, A SENDER TRIMS ITS OWN STREAM): an envelope's replay key,
# <32 hex sender key id>/<channel>/<seq>/<24 hex nonce>. Group 1 is the stream - sender, channel and
# the slash after them, so "chat" is never a prefix of "chat2" - and group 2 the seq in it, written as
# the envelope writes it: digits, no leading zero.
$script:HordeRelayStreamKeyPattern = '\A([0-9a-f]{32}/[a-z][a-z0-9-]{0,31}/)([1-9][0-9]{0,15})/[0-9a-f]{24}\z'
# Printable ASCII, space to tilde: an envelope's canonical text is a subset (no whitespace at all), and
# a text with no line break can be stored one per line by any relay.
$script:HordeRelayTextPattern = '\A[\x20-\x7E]+\z'
# What a relay may call one of its secret files (the header, WHICH FILES ON THIS MACHINE HOLD A RELAY'S
# SECRETS): a few printable words on one line. 80 is room for a phrase and not for a file's contents.
$script:HordeRelaySecretWhatPattern = '\A[\x20-\x7E]{1,80}\z'

function Get-HordeRelayRoot {
    return $PSScriptRoot
}

function Get-HordeRelayFiles {
    # Every relay's Relay.ps1, for the caller to dot-source at script level:
    #   foreach ($f in @(Get-HordeRelayFiles)) { . $f }
    param([string]$Root = (Get-HordeRelayRoot))
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $Root -Directory | Sort-Object Name | ForEach-Object { Join-Path $_.FullName "Relay.ps1" } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
}

function Get-HordeRelayCapabilityNames {
    return @($script:HordeRelayCapabilityNames)
}

function Get-HordeRelayCeilings {
    return [pscustomobject]@{ textChars = $script:HordeRelayTextChars; batch = $script:HordeRelayBatchMax; watchMs = $script:HordeRelayWatchMsMax; seqMax = $script:HordeRelaySeqMax }
}

function Test-HordeRelayCapabilities {
    # Findings for a parsed capabilities.json read from -Folder: the schema's, plus what the schema cannot
    # say - the relay it names is its own folder, and each limit is under the port's ceiling.
    param($Capabilities, [string]$Folder)
    $schema = Get-HordeSchema -Name "relay-capabilities.v1"
    $findings = @(Test-HordeSchema -Value $Capabilities -Schema $schema)
    if ($findings.Count -gt 0) { return $findings }
    $leaf = Split-Path -Leaf $Folder
    $out = New-Object System.Collections.ArrayList
    if ("$($Capabilities.relay)" -cne $leaf) { [void]$out.Add("capabilities.json names the relay '" + $Capabilities.relay + "' but sits in the folder '" + $leaf + "'") }
    $l = $Capabilities.limits
    if ($l.maxTextChars -gt $script:HordeRelayTextChars) { [void]$out.Add("limits.maxTextChars is " + $l.maxTextChars + ", over the " + $script:HordeRelayTextChars + " of the envelope's own text cap") }
    if ($l.maxBatch -gt $script:HordeRelayBatchMax) { [void]$out.Add("limits.maxBatch is " + $l.maxBatch + ", over the port's " + $script:HordeRelayBatchMax) }
    if ($l.maxWatchMs -gt $script:HordeRelayWatchMsMax) { [void]$out.Add("limits.maxWatchMs is " + $l.maxWatchMs + ", over the port's " + $script:HordeRelayWatchMsMax) }
    return @($out)
}

function Register-HordeRelay {
    # Called by a relay's own Relay.ps1. Throws, naming every finding, when its capabilities.json is
    # missing or invalid: a relay that cannot say what it does and how much it holds is not one.
    param(
        [Parameter(Mandatory = $true)][string]$Folder,
        [Parameter(Mandatory = $true)][scriptblock]$Connect,
        [Parameter(Mandatory = $true)][scriptblock]$Put,
        [Parameter(Mandatory = $true)][scriptblock]$Get,
        [Parameter(Mandatory = $true)][scriptblock]$Watch,
        [Parameter(Mandatory = $true)][scriptblock]$Ack,
        [scriptblock]$Deploy = $null,
        [int]$RunWatchMs = 0,
        [scriptblock]$WatchOpen = $null,
        [scriptblock]$WatchWait = $null,
        [scriptblock]$WatchClose = $null,
        [scriptblock]$PutKeeping = $null,
        [scriptblock]$SecretFiles = $null
    )
    $capPath = Join-Path $Folder "capabilities.json"
    if (-not (Test-Path -LiteralPath $capPath -PathType Leaf)) { throw ("relay folder '" + $Folder + "' has no capabilities.json") }
    $caps = [System.IO.File]::ReadAllText($capPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $findings = @(Test-HordeRelayCapabilities -Capabilities $caps -Folder $Folder)
    if ($findings.Count -gt 0) { throw ("relay '" + (Split-Path -Leaf $Folder) + "' refused: " + ($findings -join "; ")) }
    if ($RunWatchMs -lt 0 -or $RunWatchMs -gt [int]$caps.limits.maxWatchMs) { throw ("relay '" + (Split-Path -Leaf $Folder) + "' refused: -RunWatchMs is " + $RunWatchMs + ", not 0 to its maxWatchMs " + $caps.limits.maxWatchMs) }
    # A WATCH IN SLICES is three blocks or none (the header): a relay that could open a watch and not
    # wait on it, or not let go of it, would leave its caller holding a watch for ever.
    $sliceBlocks = @(@($WatchOpen, $WatchWait, $WatchClose) | Where-Object { $null -ne $_ }).Count
    if ($sliceBlocks -ne 0 -and $sliceBlocks -ne 3) { throw ("relay '" + (Split-Path -Leaf $Folder) + "' refused: a watch in slices is -WatchOpen, -WatchWait and -WatchClose together, and it gave " + $sliceBlocks + " of the three") }
    # Once per name: a second registration would silently swap the relay every caller resolves by that
    # name (the transport port's review of PR #42 found exactly that).
    if ($script:HordeRelays.ContainsKey("$($caps.relay)")) {
        throw ("relay '" + $caps.relay + "' is already registered, from " + $script:HordeRelays["$($caps.relay)"].folder + "; the first registration stands")
    }
    $r = [pscustomobject]@{ PSTypeName = "Horde.Relay"; name = "$($caps.relay)"; folder = $Folder; capabilities = $caps
        limits = [pscustomobject]@{ maxTextChars = [int]$caps.limits.maxTextChars; maxBatch = [int]$caps.limits.maxBatch; maxWatchMs = [int]$caps.limits.maxWatchMs; retentionSeconds = [long]$caps.limits.retentionSeconds }
        watchOpen = $WatchOpen; watchWait = $WatchWait; watchClose = $WatchClose; putKeeping = $PutKeeping; secretFiles = $SecretFiles
        connect = $Connect; put = $Put; get = $Get; watch = $Watch; ack = $Ack; deploy = $Deploy; runWatchMs = $RunWatchMs }
    $script:HordeRelays[$r.name] = $r
    return $r
}

function Get-HordeRelayNames {
    return @($script:HordeRelays.Keys | Sort-Object)
}

function Get-HordeRelayDeployable {
    # The names of the loaded relays that can be deployed (header, DEPLOYING), in order.
    return @(Get-HordeRelayNames | Where-Object { $null -ne $script:HordeRelays[$_].deploy })
}

function Publish-HordeRelay {
    # Deploy relay -Name, serving the static files in -Site: known { origin } - where it now answers -
    # or unknown with the reason. Never throws for the relay: a deploy that throws is unknown.
    param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][string]$Site, [scriptblock]$Say = { param($Line) }, [string]$HordeHome = "")
    if (-not $script:HordeRelays.ContainsKey($Name)) { return (New-HordeUnknown -Reason ("no relay named '" + $Name + "' is loaded")) }
    $r = $script:HordeRelays[$Name]
    if ($null -eq $r.deploy) { return (New-HordeUnknown -Reason ("relay '" + $Name + "' is not one that is deployed: it has nothing to put anywhere")) }
    if (-not (Test-Path -LiteralPath (Join-Path $Site "app\index.html") -PathType Leaf)) { return (New-HordeUnknown -Reason ("the folder to serve, " + $Site + ", holds no app\index.html")) }
    try { $a = & $r.deploy $Site $Say $HordeHome }
    catch { return (New-HordeUnknown -Reason ("relay '" + $Name + "' failed to deploy") -ErrorRecord $_) }
    if (-not (Test-HordeAnswer $a)) { return (New-HordeUnknown -Reason ("relay '" + $Name + "' answered the deploy with something that is not an answer")) }
    if ($a.state -cne "known") { return (New-HordeUnknown -Reason ("relay '" + $Name + "' was not deployed: " + $(if ("$($a.reason)" -ne "") { $a.reason } else { $a.state }))) }
    $o = Get-HordeRelayMember $a.value "origin"
    if (-not $o.has -or $o.value -isnot [string] -or $o.value -cnotmatch '\Ahttps://[a-z0-9.-]+(:[0-9]{1,5})?\z') { return (New-HordeUnknown -Reason ("relay '" + $Name + "' answered the deploy without the https origin it answers at")) }
    return (New-HordeKnown -Value ([pscustomobject]@{ relay = $Name; origin = $o.value }) -ObservedAt $a.observedAt)
}

function Get-HordeRelay {
    # A registered relay by name. Throws for a name nobody registered: asking for one that is not loaded
    # is a programming error, not a state of the world.
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not $script:HordeRelays.ContainsKey($Name)) { throw ("no relay named '" + $Name + "' is loaded") }
    return $script:HordeRelays[$Name]
}

function Get-HordeRelaySupport {
    # The support word a relay declares for one capability: yes, no, declined or unverified.
    param([Parameter(Mandatory = $true)]$Relay, [Parameter(Mandatory = $true)][string]$Capability)
    if ($script:HordeRelayCapabilityNames -cnotcontains $Capability) { throw ("'" + $Capability + "' is not a relay capability") }
    return "$($Relay.capabilities.capabilities.$Capability.support)"
}

function Test-HordeRelayCapability {
    # True only for "yes". unverified is treated as no, and so are no and declined.
    param([Parameter(Mandatory = $true)]$Relay, [Parameter(Mandatory = $true)][string]$Capability)
    return ((Get-HordeRelaySupport -Relay $Relay -Capability $Capability) -ceq "yes")
}

function Get-HordeRelayShortfall {
    # Why a relay does not meet the requirements, or "" when it does.
    param($Relay, [string[]]$Require, [long]$MinTextChars)
    foreach ($c in $Require) {
        if (-not (Test-HordeRelayCapability -Relay $Relay -Capability $c)) {
            $cap = $Relay.capabilities.capabilities.$c
            return ("relay '" + $Relay.name + "' does not offer " + $c + " (it says " + $cap.support + ": " + $cap.evidence + ")")
        }
    }
    if ($Relay.limits.maxTextChars -lt $MinTextChars) { return ("relay '" + $Relay.name + "' holds texts of at most " + $Relay.limits.maxTextChars + " characters (maxTextChars), under the " + $MinTextChars + " needed") }
    return ""
}

function Resolve-HordeRelay {
    # A relay by name that has every capability in -Require, as a tristate answer. -Require is mandatory
    # so a caller states what it needs; @() means nothing.
    param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Require, [long]$MinTextChars = 1)
    if (-not $script:HordeRelays.ContainsKey($Name)) { return (New-HordeUnknown -Reason ("no relay named '" + $Name + "' is loaded")) }
    $r = $script:HordeRelays[$Name]
    $why = Get-HordeRelayShortfall -Relay $r -Require $Require -MinTextChars $MinTextChars
    if ($why -ne "") { return (New-HordeUnknown -Reason $why) }
    return (New-HordeKnown -Value $r)
}

function Find-HordeRelay {
    # Every loaded relay that has every capability in -Require and holds texts of -MinTextChars: known,
    # the names in order, or unknown naming each relay and why it was passed over.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Require, [long]$MinTextChars = 1)
    $fit = New-Object System.Collections.ArrayList
    $why = New-Object System.Collections.ArrayList
    foreach ($n in @(Get-HordeRelayNames)) {
        $s = Get-HordeRelayShortfall -Relay $script:HordeRelays[$n] -Require $Require -MinTextChars $MinTextChars
        if ($s -eq "") { [void]$fit.Add($n) } else { [void]$why.Add($s) }
    }
    if ($fit.Count -eq 0) { return (New-HordeUnknown -Reason ("no loaded relay fits: " + $(if ($why.Count) { $why -join "; " } else { "none is loaded" }))) }
    return (New-HordeKnown -Value @($fit.ToArray()))
}

function Test-HordeRelayMailbox {
    # Findings for one mailbox id. None means it may be handed to a relay.
    param($Mailbox)
    if ($Mailbox -isnot [string] -or $Mailbox -eq "") { return @("the mailbox is not a non-empty string") }
    $parts = $Mailbox.Split([char]'/')
    if ($parts.Count -ne 2) { return @("the mailbox '" + $Mailbox + "' is not <horde>/<reader>: it has " + $parts.Count + " part(s)") }
    $out = New-Object System.Collections.ArrayList
    foreach ($p in $parts) {
        if ($p -cnotmatch $script:HordeRelaySegmentPattern) { [void]$out.Add("the mailbox part '" + $p + "' is not 1 to 63 of a-z, 0-9 and -, starting with a letter or digit") }
        elseif ($p -cmatch $script:HordeRelayDeviceNamePattern) { [void]$out.Add("the mailbox part '" + $p + "' is a device name") }
    }
    return @($out)
}

function New-HordeRelayMailbox {
    # The mailbox id of one reader in one horde. Throws for a bad part: a caller building an id has a bug.
    param([Parameter(Mandatory = $true)][string]$Horde, [Parameter(Mandatory = $true)][string]$Reader)
    $id = $Horde + "/" + $Reader
    $findings = @(Test-HordeRelayMailbox -Mailbox $id)
    if ($findings.Count -gt 0) { throw ("'" + $id + "' is not a mailbox: " + ($findings -join "; ")) }
    return $id
}

function Get-HordeRelayContentKey {
    # The key of a text put with none: "sha256-" and its SHA-256 in lower-case hex. The text is ASCII, so
    # its bytes are its characters and the hash has one spelling.
    param([Parameter(Mandatory = $true)][string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $h = $sha.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($Text)) } finally { $sha.Dispose() }
    return ("sha256-" + (($h | ForEach-Object { $_.ToString("x2") }) -join ""))
}

function Get-HordeRelayMember {
    # A member of a parsed object or a dictionary, and whether it is there, without dereferencing it.
    param($Object, [string]$Name)
    if ($Object -is [System.Collections.IDictionary]) { return [pscustomobject]@{ has = $Object.Contains($Name); value = $(if ($Object.Contains($Name)) { $Object[$Name] } else { $null }) } }
    if ($Object -isnot [System.Management.Automation.PSCustomObject]) { return [pscustomobject]@{ has = $false; value = $null } }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return [pscustomobject]@{ has = $false; value = $null } }
    return [pscustomobject]@{ has = $true; value = $p.Value }
}

function Test-HordeRelaySeq {
    # Is this a seq: a whole number (int or long, never text or a double), 1 to 2^53-1?
    param($Value)
    return (($Value -is [int] -or $Value -is [long]) -and $Value -ge 1 -and $Value -le $script:HordeRelaySeqMax)
}

function Test-HordeRelayCursor {
    # Is this a cursor: a whole number 0 to 2^53-1?
    param($Value)
    return (($Value -is [int] -or $Value -is [long]) -and $Value -ge 0 -and $Value -le $script:HordeRelaySeqMax)
}

function Get-HordeRelayTextFinding {
    # Why a text cannot be an item's, or "" when it can.
    param($Text, [int]$MaxChars)
    if ($Text -isnot [string]) { return "the text is not a string" }
    if ($Text.Length -eq 0) { return "the text is empty" }
    if ($Text.Length -gt $MaxChars) { return ("the text is " + $Text.Length + " characters, over the " + $MaxChars + " this relay holds") }
    if ($Text -cnotmatch $script:HordeRelayTextPattern) { return "the text is not printable ASCII on one line" }
    return ""
}

function Test-HordeRelayConnection {
    # Is this the very connection object Connect-HordeRelay made, to a relay still registered as the one
    # it was made with? A look-alike carrying the same id is not.
    param($Connection)
    if ($null -eq $Connection -or $Connection -isnot [System.Management.Automation.PSCustomObject]) { return $false }
    if (@($Connection.PSObject.TypeNames) -notcontains "Horde.RelayConnection") { return $false }
    $id = $Connection.PSObject.Properties["id"]
    if ($null -eq $id -or $id.Value -isnot [string] -or -not $script:HordeRelayConnections.ContainsKey($id.Value)) { return $false }
    if (-not [object]::ReferenceEquals($script:HordeRelayConnections[$id.Value], $Connection)) { return $false }
    $r = $Connection.relay
    return ($script:HordeRelays.ContainsKey($r.name) -and [object]::ReferenceEquals($script:HordeRelays[$r.name], $r))
}

function Connect-HordeRelay {
    # A connection to a registered relay, made with -Options (the relay's own: a folder, an address).
    param([Parameter(Mandatory = $true)][string]$Name, $Options = @{})
    if (-not $script:HordeRelays.ContainsKey($Name)) { return (New-HordeUnknown -Reason ("no relay named '" + $Name + "' is loaded")) }
    $r = $script:HordeRelays[$Name]
    try { $a = & $r.connect $Options }
    catch { return (New-HordeUnknown -Reason ("relay '" + $Name + "' failed to connect") -ErrorRecord $_) }
    if (-not (Test-HordeAnswer $a)) { return (New-HordeUnknown -Reason ("relay '" + $Name + "' answered connect with something that is not an answer")) }
    if ($a.state -cne "known") { return (New-HordeUnknown -Reason ("relay '" + $Name + "' did not connect: " + $(if ("$($a.reason)" -ne "") { $a.reason } else { $a.state }))) }
    $c = [pscustomobject]@{ PSTypeName = "Horde.RelayConnection"; id = [guid]::NewGuid().ToString("N"); relay = $r; state = $a.value }
    $script:HordeRelayConnections[$c.id] = $c
    return (New-HordeKnown -Value $c)
}

function Get-HordeRelayConnectionRefusal {
    # Why an operation on -Connection and -Mailbox was not made, or "" when it may be.
    param($Connection, $Mailbox, [string]$What)
    if (-not (Test-HordeRelayConnection $Connection)) { return ("the " + $What + " was not made: the connection is not one Connect-HordeRelay made") }
    $mf = @(Test-HordeRelayMailbox -Mailbox $Mailbox)
    if ($mf.Count -gt 0) { return ("the " + $What + " was not made: " + ($mf -join "; ")) }
    return ""
}

function Invoke-HordeRelayAdapter {
    # Run one of the relay's script blocks; its answer, or unknown when it threw or answered with
    # something that is not a known answer.
    param($Connection, [string]$Op, [object[]]$Arguments, [string]$What)
    $r = $Connection.relay
    try { $a = & $r.$Op @Arguments }
    catch { return (New-HordeUnknown -Reason ("relay '" + $r.name + "' failed the " + $What) -ErrorRecord $_) }
    if (-not (Test-HordeAnswer $a)) { return (New-HordeUnknown -Reason ("relay '" + $r.name + "' answered the " + $What + " with something that is not an answer")) }
    if ($a.state -ceq "absent") { return (New-HordeUnknown -Reason ("relay '" + $r.name + "' answered the " + $What + " absent, which says nothing")) }
    if ($a.state -ceq "unknown") {
        $u = New-HordeUnknown -Reason ("relay '" + $r.name + "' could not do the " + $What + ": " + $a.reason)
        # A REFUSAL'S STATUS AND RETRY-AFTER (the ADAPTER CONTRACT), carried only when they hold.
        $st = $a.PSObject.Properties["status"]
        if ($null -ne $st -and ($st.Value -is [int] -or $st.Value -is [long]) -and $st.Value -ge 100 -and $st.Value -le 599) { $u | Add-Member -NotePropertyName status -NotePropertyValue ([int]$st.Value) }
        $ra = $a.PSObject.Properties["retryAfterMs"]
        if ($null -ne $ra -and ($ra.Value -is [int] -or $ra.Value -is [long]) -and $ra.Value -ge 0 -and $ra.Value -le $script:HordeRelayRetryAfterMaxMs) { $u | Add-Member -NotePropertyName retryAfterMs -NotePropertyValue ([long]$ra.Value) }
        return $u
    }
    return $a
}

function Read-HordeRelayStreamKey {
    # The stream a key names and its seq in it (the header, A SENDER TRIMS ITS OWN STREAM):
    # { stream; seq }, or $null for a key that names none - a content hash, a pairing key.
    param($Key)
    if ($Key -isnot [string]) { return $null }
    $m = [regex]::Match($Key, $script:HordeRelayStreamKeyPattern)
    if (-not $m.Success) { return $null }
    $n = [long]$m.Groups[2].Value
    if ($n -gt $script:HordeRelaySeqMax) { return $null }
    return [pscustomobject]@{ stream = $m.Groups[1].Value; seq = $n }
}

function Test-HordeRelaySenderTrim {
    # Does this connection's relay trim a sender's stream on a put (the header)? False for anything
    # that is not a connection the port made.
    param($Connection)
    return ((Test-HordeRelayConnection $Connection) -and $null -ne $Connection.relay.putKeeping)
}

function Send-HordeRelayItem {
    # Put one text into a mailbox. -Key is the caller's idempotency key (an envelope's replay key); with
    # none, the text's own hash. -KeepFrom, over 0, asks the relay to delete the older items of the
    # key's own stream (the header, A SENDER TRIMS ITS OWN STREAM); the answer's trimmed is how many it
    # deleted, or -1 when nothing was asked, this relay does not trim, or it did not say.
    param($Connection, $Mailbox, $Text, [string]$Key = "", $KeepFrom = [long]0)
    $refusal = Get-HordeRelayConnectionRefusal -Connection $Connection -Mailbox $Mailbox -What "put"
    if ($refusal -ne "") { return (New-HordeUnknown -Reason $refusal) }
    $lim = $Connection.relay.limits
    $tf = Get-HordeRelayTextFinding -Text $Text -MaxChars $lim.maxTextChars
    if ($tf -ne "") { return (New-HordeUnknown -Reason ("the put was not made: " + $tf)) }
    if ($Key -eq "") { $Key = Get-HordeRelayContentKey -Text $Text }
    elseif ($Key -cnotmatch $script:HordeRelayKeyPattern) { return (New-HordeUnknown -Reason "the put was not made: the key is not 1 to 160 of A-Z, a-z, 0-9 and . _ : / -") }
    if (-not ($KeepFrom -is [int] -or $KeepFrom -is [long]) -or $KeepFrom -lt 0) { return (New-HordeUnknown -Reason ("the put was not made: the seq to keep from, " + $KeepFrom + ", is not a whole number from 0")) }
    $keeping = $false
    if ($KeepFrom -gt 0) {
        # CHECKED BEFORE THE RELAY SEES ANYTHING: the key names a stream, and the trim stops at the key's
        # own seq - a put that could delete itself, or what was put after it, is a bug in its caller.
        $named = Read-HordeRelayStreamKey -Key $Key
        if ($null -eq $named) { return (New-HordeUnknown -Reason "the put was not made: it asks to trim a stream, and its key names none (<sender>/<channel>/<seq>/<nonce>)") }
        if ($KeepFrom -gt $named.seq) { return (New-HordeUnknown -Reason ("the put was not made: it asks to keep from seq " + $KeepFrom + " of its stream, past its own seq " + $named.seq)) }
        $keeping = ($null -ne $Connection.relay.putKeeping)
    }
    if ($keeping) { $a = Invoke-HordeRelayAdapter -Connection $Connection -Op "putKeeping" -Arguments @($Connection.state, $Mailbox, $Key, $Text, [long]$KeepFrom) -What "put" }
    else { $a = Invoke-HordeRelayAdapter -Connection $Connection -Op "put" -Arguments @($Connection.state, $Mailbox, $Key, $Text) -What "put" }
    if ($a.state -cne "known") { return $a }
    $seq = Get-HordeRelayMember $a.value "seq"
    if (-not $seq.has -or -not (Test-HordeRelaySeq $seq.value)) { return (New-HordeUnknown -Reason ("relay '" + $Connection.relay.name + "' answered the put without a seq from 1 to " + $script:HordeRelaySeqMax)) }
    $dup = Get-HordeRelayMember $a.value "duplicate"
    if (-not $dup.has -or $dup.value -isnot [bool]) { return (New-HordeUnknown -Reason ("relay '" + $Connection.relay.name + "' answered the put without saying, true or false, whether it was a duplicate")) }
    # HOW MANY IT TRIMMED IS THE RELAY'S WORD, taken only when it is a count: anything else is "not said".
    $trimmed = [long]-1
    if ($keeping) {
        $t = Get-HordeRelayMember $a.value "trimmed"
        if ($t.has -and (Test-HordeRelayCursor $t.value)) { $trimmed = [long]$t.value }
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ mailbox = $Mailbox; key = $Key; seq = [long]$seq.value; duplicate = [bool]$dup.value; trimmed = $trimmed }) -ObservedAt $a.observedAt)
}

function ConvertFrom-HordeRelayBatch {
    # The relay's answer to a read, rebuilt by the port: every item checked, in seq order, each seq once,
    # nothing at or before -Since, at most -Max; each item dropped is an anomaly saying why, and so is
    # each hole between two delivered seqs. The cursor is the last seq delivered, or -Since.
    param($Connection, $Answer, [string]$Mailbox, [long]$Since, [int]$Max, [string]$What)
    $name = $Connection.relay.name
    $member = Get-HordeRelayMember $Answer.value "items"
    if (-not $member.has) { return (New-HordeUnknown -Reason ("relay '" + $name + "' answered the " + $What + " without items")) }
    # A one-element list arrives unrolled, and an empty one as $null: both are lists here.
    $raw = @()
    if ($null -ne $member.value) { $raw = @($member.value) }
    $anomalies = New-Object System.Collections.ArrayList
    $bySeq = @{}
    $n = 0
    foreach ($it in $raw) {
        $n++
        $at = "item " + $n + " of the " + $What
        if ($null -eq $it -or -not ($it -is [System.Management.Automation.PSCustomObject] -or $it -is [System.Collections.IDictionary])) { [void]$anomalies.Add($at + " is not an object; dropped"); continue }
        $seq = Get-HordeRelayMember $it "seq"
        if (-not $seq.has -or -not (Test-HordeRelaySeq $seq.value)) { [void]$anomalies.Add($at + " has no seq from 1 to " + $script:HordeRelaySeqMax + "; dropped"); continue }
        $key = Get-HordeRelayMember $it "key"
        if (-not $key.has -or $key.value -isnot [string] -or $key.value -cnotmatch $script:HordeRelayKeyPattern) { [void]$anomalies.Add($at + " (seq " + $seq.value + ") has no valid key; dropped"); continue }
        $text = Get-HordeRelayMember $it "text"
        $tf = Get-HordeRelayTextFinding -Text $text.value -MaxChars $Connection.relay.limits.maxTextChars
        if ($tf -ne "") { [void]$anomalies.Add($at + " (seq " + $seq.value + "): " + $tf + "; dropped"); continue }
        $s = [long]$seq.value
        if ($s -le $Since) { [void]$anomalies.Add($at + " has seq " + $s + ", at or before the cursor " + $Since + "; dropped"); continue }
        if ($bySeq.ContainsKey($s)) {
            # THE FIRST STANDS, IN THE RELAY'S ORDER: the port cannot tell which of two texts is real, and
            # the envelope's signature and the journal can. A forged copy delivered in place of the real one
            # is no worse than the real one dropped, which the relay can do anyway.
            if ($bySeq[$s].text -ceq [string]$text.value -and $bySeq[$s].key -ceq [string]$key.value) { [void]$anomalies.Add($at + ": seq " + $s + " came twice; the repeat dropped") }
            else { [void]$anomalies.Add($at + ": seq " + $s + " came again with other text; the first kept") }
            continue
        }
        $bySeq[$s] = [pscustomobject]@{ seq = $s; key = [string]$key.value; text = [string]$text.value }
    }
    $ordered = @($bySeq.Keys | Sort-Object | ForEach-Object { $bySeq[$_] })
    if ($ordered.Count -gt $Max) {
        [void]$anomalies.Add("relay '" + $name + "' answered the " + $What + " with " + ($ordered.Count - $Max) + " item(s) more than the " + $Max + " asked; left for the next read")
        $ordered = @($ordered[0..($Max - 1)])
    }
    # A HOLE BEFORE THE FIRST ITEM COUNTS ONLY AFTER A CURSOR: seqs are contiguous, so a reader resuming
    # from its own cursor expects the very next one. From 0 it does not - a mailbox trimmed by an ack
    # starts later, and a new reader starting there has missed nothing it was owed.
    $prev = $Since
    foreach ($it in $ordered) {
        if ($prev -gt 0 -and $it.seq -ne $prev + 1) { [void]$anomalies.Add("gap: seq " + ($prev + 1) + " to " + ($it.seq - 1) + " did not come") }
        $prev = $it.seq
    }
    $next = $Since
    if ($ordered.Count -gt 0) { $next = $ordered[$ordered.Count - 1].seq }
    return (New-HordeKnown -Value ([pscustomobject]@{ mailbox = $Mailbox; since = $Since; next = [long]$next; items = @($ordered); anomalies = @($anomalies.ToArray()) }) -ObservedAt $Answer.observedAt)
}

function Get-HordeRelayReadRefusal {
    # Why a read of -Since and -Max was not made, or "".
    param($Connection, $Mailbox, $Since, $Max, [string]$What)
    $refusal = Get-HordeRelayConnectionRefusal -Connection $Connection -Mailbox $Mailbox -What $What
    if ($refusal -ne "") { return $refusal }
    if (-not (Test-HordeRelayCursor $Since)) { return ("the " + $What + " was not made: the cursor " + $Since + " is not a whole number from 0 to " + $script:HordeRelaySeqMax) }
    if (-not ($Max -is [int] -or $Max -is [long]) -or $Max -lt 1 -or $Max -gt $Connection.relay.limits.maxBatch) { return ("the " + $What + " was not made: the batch " + $Max + " is not from 1 to the relay's " + $Connection.relay.limits.maxBatch) }
    return ""
}

function Receive-HordeRelayItems {
    # The items of a mailbox after -Since, at most -Max (the relay's maxBatch when not given).
    param($Connection, $Mailbox, $Since = [long]0, $Max = $null)
    if ($null -eq $Max -and (Test-HordeRelayConnection $Connection)) { $Max = $Connection.relay.limits.maxBatch }
    $refusal = Get-HordeRelayReadRefusal -Connection $Connection -Mailbox $Mailbox -Since $Since -Max $Max -What "read"
    if ($refusal -ne "") { return (New-HordeUnknown -Reason $refusal) }
    $a = Invoke-HordeRelayAdapter -Connection $Connection -Op "get" -Arguments @($Connection.state, $Mailbox, [long]$Since, [int]$Max) -What "read"
    if ($a.state -cne "known") { return $a }
    return (ConvertFrom-HordeRelayBatch -Connection $Connection -Answer $a -Mailbox $Mailbox -Since ([long]$Since) -Max ([int]$Max) -What "read")
}

function Wait-HordeRelayItems {
    # As Receive-HordeRelayItems, but when nothing is there yet the relay waits up to -TimeoutMs for it.
    param($Connection, $Mailbox, $Since = [long]0, $Max = $null, $TimeoutMs = 0)
    if ($null -eq $Max -and (Test-HordeRelayConnection $Connection)) { $Max = $Connection.relay.limits.maxBatch }
    $refusal = Get-HordeRelayReadRefusal -Connection $Connection -Mailbox $Mailbox -Since $Since -Max $Max -What "watch"
    if ($refusal -ne "") { return (New-HordeUnknown -Reason $refusal) }
    $most = $Connection.relay.limits.maxWatchMs
    if (-not ($TimeoutMs -is [int] -or $TimeoutMs -is [long]) -or $TimeoutMs -lt 0 -or $TimeoutMs -gt $most) { return (New-HordeUnknown -Reason ("the watch was not made: the timeout " + $TimeoutMs + " ms is not from 0 to the relay's " + $most)) }
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $a = Invoke-HordeRelayAdapter -Connection $Connection -Op "watch" -Arguments @($Connection.state, $Mailbox, [long]$Since, [int]$Max, [int]$TimeoutMs) -What "watch"
    $clock.Stop()
    if ($a.state -cne "known") { return $a }
    $b = ConvertFrom-HordeRelayBatch -Connection $Connection -Answer $a -Mailbox $Mailbox -Since ([long]$Since) -Max ([int]$Max) -What "watch"
    if ($b.state -ceq "known") { $b.value | Add-Member -NotePropertyName waitedMs -NotePropertyValue ([long]$clock.ElapsedMilliseconds) }
    return $b
}

function Test-HordeRelayWatchInSlices {
    # Can this connection's relay hold a watch open while its caller does something else (the header, A
    # WATCH IN SLICES)? False for anything that is not a connection the port made.
    param($Connection)
    if (-not (Test-HordeRelayConnection $Connection)) { return $false }
    return ($null -ne $Connection.relay.watchOpen -and $null -ne $Connection.relay.watchWait -and $null -ne $Connection.relay.watchClose)
}

function Test-HordeRelayWatch {
    # Is this the very watch object Open-HordeRelayWatch made, not yet closed, on a connection that
    # still holds? A look-alike carrying the same id is not, and neither is one already closed.
    param($Watch)
    if ($null -eq $Watch -or $Watch -isnot [System.Management.Automation.PSCustomObject]) { return $false }
    if (@($Watch.PSObject.TypeNames) -notcontains "Horde.RelayWatch") { return $false }
    $id = $Watch.PSObject.Properties["id"]
    if ($null -eq $id -or $id.Value -isnot [string] -or -not $script:HordeRelayWatches.ContainsKey($id.Value)) { return $false }
    if (-not [object]::ReferenceEquals($script:HordeRelayWatches[$id.Value], $Watch)) { return $false }
    return (Test-HordeRelayWatchInSlices $Watch.connection)
}

function Open-HordeRelayWatch {
    # Open a watch of -Mailbox after -Since that is waited on in slices (the header, A WATCH IN SLICES):
    # known, the watch, to hand to Wait-HordeRelayWatch and, always, to Close-HordeRelayWatch. Checked
    # as Wait-HordeRelayItems checks its own, before the relay sees anything; unknown too when this
    # relay does not watch in slices - a caller asks Test-HordeRelayWatchInSlices first.
    param($Connection, $Mailbox, $Since = [long]0, $Max = $null, $TimeoutMs = 0)
    if ($null -eq $Max -and (Test-HordeRelayConnection $Connection)) { $Max = $Connection.relay.limits.maxBatch }
    $refusal = Get-HordeRelayReadRefusal -Connection $Connection -Mailbox $Mailbox -Since $Since -Max $Max -What "watch"
    if ($refusal -ne "") { return (New-HordeUnknown -Reason $refusal) }
    $longest = $Connection.relay.limits.maxWatchMs
    if (-not ($TimeoutMs -is [int] -or $TimeoutMs -is [long]) -or $TimeoutMs -lt 0 -or $TimeoutMs -gt $longest) { return (New-HordeUnknown -Reason ("the watch was not opened: the timeout " + $TimeoutMs + " ms is not from 0 to the relay's " + $longest)) }
    if (-not (Test-HordeRelayWatchInSlices $Connection)) { return (New-HordeUnknown -Reason ("the watch was not opened: relay '" + $Connection.relay.name + "' does not watch in slices")) }
    # THE PORT'S OWN CLOCK, started before the relay is asked: the time the relay takes to open the
    # watch is the watch's, so a watch in slices is never longer than the blocking one it stands in for.
    $sinceOpen = [System.Diagnostics.Stopwatch]::StartNew()
    $a = Invoke-HordeRelayAdapter -Connection $Connection -Op "watchOpen" -Arguments @($Connection.state, $Mailbox, [long]$Since, [int]$Max, [int]$TimeoutMs) -What "watch"
    if ($a.state -cne "known") { return $a }
    $w = [pscustomobject]@{ PSTypeName = "Horde.RelayWatch"; id = [guid]::NewGuid().ToString("N"); connection = $Connection; mailbox = $Mailbox
        since = [long]$Since; max = [int]$Max; timeoutMs = [int]$TimeoutMs; handle = $a.value; clock = $sinceOpen; ended = $false }
    $script:HordeRelayWatches[$w.id] = $w
    return (New-HordeKnown -Value $w -ObservedAt $a.observedAt)
}

function Wait-HordeRelayWatch {
    # Wait up to -WaitMs more on a watch Open-HordeRelayWatch made, costing the relay nothing. Known
    # { ended = $false; waitedMs } when the slice is over and the watch is still open; known { ended =
    # $true; mailbox; since; next; items; anomalies; waitedMs } - a batch exactly as Wait-HordeRelayItems
    # hands it, waitedMs counted from the open - once something came or the watch's time is up; unknown
    # when the relay failed it, and the watch is then over too. -Last makes this the watch's end whatever
    # the relay says: it is asked once more, without waiting, and what it has is the batch (a caller that
    # must stop uses it, so nothing that arrived during its last slice is left unread).
    param($Watch, $WaitMs = 0, [switch]$Last)
    if (-not (Test-HordeRelayWatch $Watch)) { return (New-HordeUnknown -Reason "the wait was not made: the watch is not one Open-HordeRelayWatch made, or it is closed") }
    if ($Watch.ended) { return (New-HordeUnknown -Reason "the wait was not made: the watch has ended") }
    $c = $Watch.connection
    if (-not ($WaitMs -is [int] -or $WaitMs -is [long]) -or $WaitMs -lt 0 -or $WaitMs -gt $c.relay.limits.maxWatchMs) { return (New-HordeUnknown -Reason ("the wait was not made: the slice " + $WaitMs + " ms is not from 0 to the relay's " + $c.relay.limits.maxWatchMs)) }
    # THE WATCH'S TIME IS THE PORT'S TO KEEP: a slice never runs past it, and once it is up the relay is
    # asked one last time without waiting and the watch is over, whatever the relay says of it.
    $leftMs = [long]$Watch.timeoutMs - $Watch.clock.ElapsedMilliseconds
    $over = ($Last -or $leftMs -le 0)
    $sliceMs = 0
    if (-not $over) { $sliceMs = [int][System.Math]::Min([double]$WaitMs, [double]$leftMs) }
    $a = Invoke-HordeRelayAdapter -Connection $c -Op "watchWait" -Arguments @($c.state, $Watch.handle, [int]$sliceMs) -What "watch"
    if ($a.state -cne "known") { $Watch.ended = $true; return $a }
    $said = Get-HordeRelayMember $a.value "ended"
    if (-not $said.has -or $said.value -isnot [bool]) { $Watch.ended = $true; return (New-HordeUnknown -Reason ("relay '" + $c.relay.name + "' answered the watch without saying, true or false, whether it has ended")) }
    # Items handed over with "not ended" end it all the same: a relay does not hand an item over twice.
    $held = Get-HordeRelayMember $a.value "items"
    $some = ($held.has -and $null -ne $held.value -and @($held.value).Count -gt 0)
    if (-not ($said.value -or $some -or $over)) {
        return (New-HordeKnown -Value ([pscustomobject]@{ ended = $false; waitedMs = [long]$Watch.clock.ElapsedMilliseconds }) -ObservedAt $a.observedAt)
    }
    $Watch.ended = $true
    $b = ConvertFrom-HordeRelayBatch -Connection $c -Answer $a -Mailbox $Watch.mailbox -Since $Watch.since -Max $Watch.max -What "watch"
    if ($b.state -ceq "known") {
        $b.value | Add-Member -NotePropertyName ended -NotePropertyValue $true
        $b.value | Add-Member -NotePropertyName waitedMs -NotePropertyValue ([long]$Watch.clock.ElapsedMilliseconds)
    }
    return $b
}

function Close-HordeRelayWatch {
    # Let go of a watch Open-HordeRelayWatch made: always called, ended or not. Safe to call twice, and
    # never throws for the relay - there is nothing a caller could do about a close that failed.
    param($Watch)
    if (-not (Test-HordeRelayWatch $Watch)) { return }
    $script:HordeRelayWatches.Remove($Watch.id)
    $Watch.ended = $true
    try { $null = & $Watch.connection.relay.watchClose $Watch.connection.state $Watch.handle } catch { }
}

function Confirm-HordeRelayItems {
    # The reader has kept everything in the mailbox through -Through: a relay with trim.on.ack may now
    # delete those items.
    param($Connection, $Mailbox, $Through)
    $refusal = Get-HordeRelayConnectionRefusal -Connection $Connection -Mailbox $Mailbox -What "ack"
    if ($refusal -ne "") { return (New-HordeUnknown -Reason $refusal) }
    if (-not (Test-HordeRelayCursor $Through)) { return (New-HordeUnknown -Reason ("the ack was not made: the cursor " + $Through + " is not a whole number from 0 to " + $script:HordeRelaySeqMax)) }
    $a = Invoke-HordeRelayAdapter -Connection $Connection -Op "ack" -Arguments @($Connection.state, $Mailbox, [long]$Through) -What "ack"
    if ($a.state -cne "known") { return $a }
    $t = Get-HordeRelayMember $a.value "through"
    if (-not $t.has -or -not (Test-HordeRelayCursor $t.value) -or [long]$t.value -ne [long]$Through) { return (New-HordeUnknown -Reason ("relay '" + $Connection.relay.name + "' was asked to ack through " + $Through + " and answered through " + $t.value)) }
    return (New-HordeKnown -Value ([pscustomobject]@{ mailbox = $Mailbox; through = [long]$Through }) -ObservedAt $a.observedAt)
}

function Test-HordeRelayAbsolutePath {
    # Is this an absolute path, one that means the same from every current folder and drive? It is
    # core/ModuleSettings.ps1's Test-HordeModuleSettingFolder, COPIED AND NOT LOADED: that file brings the
    # settings reader and its four files with it, which every caller of the port would then pay for, and
    # the port reads no setting. test/test-relay-port.ps1 fails if the two ever answer differently.
    # IsPathRooted says yes to C:x and \x, which are not (measured there, 2026-10-07), so on Windows the
    # answer is the pattern; it is still asked first, because it throws on a character no path may hold.
    param($Path)
    if ($Path -isnot [string] -or $Path -eq "") { return $false }
    $rooted = $false
    try { $rooted = [System.IO.Path]::IsPathRooted($Path) } catch { return $false }
    if ([System.IO.Path]::DirectorySeparatorChar -eq [char]'\') { return [bool]($Path -cmatch '\A(?:[A-Za-z]:[\\/]|[\\/]{2}[^\\/])') }
    return $rooted
}

function Read-HordeRelaySecretFiles {
    # One relay's own word on which files here hold its secrets, checked (the header, WHICH FILES ON THIS
    # MACHINE HOLD A RELAY'S SECRETS): known, a list of { relay; path; what } that may be empty, or
    # unknown with why this relay could not tell. Never throws for the relay.
    param($Relay, [string]$HordeHome)
    $name = $Relay.name
    try { $a = & $Relay.secretFiles $HordeHome }
    catch { return (New-HordeUnknown -Reason ("relay '" + $name + "' failed to say which files hold its secrets") -ErrorRecord $_) }
    if (-not (Test-HordeAnswer $a)) { return (New-HordeUnknown -Reason ("relay '" + $name + "' answered which files hold its secrets with something that is not an answer")) }
    if ($a.state -ceq "unknown") { return (New-HordeUnknown -Reason ("relay '" + $name + "' cannot tell which files hold its secrets: " + $a.reason)) }
    $out = New-Object System.Collections.ArrayList
    # Absent is "none here", and so is a known list with nothing in it. (The word comes first in the
    # comparison only so that this line is not a second match for the find string of
    # test\mutations\relay-port.psd1's absent-answer-passed-on, which must occur once.)
    if ("absent" -ceq $a.state) { return (New-HordeKnown -Value @($out.ToArray())) }
    $member = Get-HordeRelayMember $a.value "files"
    if (-not $member.has) { return (New-HordeUnknown -Reason ("relay '" + $name + "' answered which files hold its secrets without files")) }
    # A one-element list arrives unrolled, and an empty one as $null: both are lists here.
    $raw = @()
    if ($null -ne $member.value) { $raw = @($member.value) }
    $n = 0
    foreach ($it in $raw) {
        $n++
        # NOTHING THE RELAY SAID IS REPEATED IN A REFUSAL: a path that is not one, or words too long to
        # be a description, may be anything at all.
        $at = "relay '" + $name + "' named secret file " + $n + " of " + $raw.Count
        $path = Get-HordeRelayMember $it "path"
        if (-not $path.has -or -not (Test-HordeRelayAbsolutePath $path.value)) { return (New-HordeUnknown -Reason ($at + " by something that is not an absolute path")) }
        # A PATH ON THIS MACHINE'S OWN DRIVES, NOT A NETWORK OR DEVICE ONE (the review of PR 238,
        # 2026-10-13): measured that day, files/ could place neither \\.\C:\... nor
        # \\localhost\C$\... and compared nothing, so a file named so was shared. Two separators at
        # the start is every such form, the long-path prefix \\?\ among them.
        if ($path.value -cmatch '\A[\\/]{2}') { return (New-HordeUnknown -Reason ($at + " by a network or device path, not one on this machine's own drives")) }
        $whole = ""
        try { $whole = [System.IO.Path]::GetFullPath($path.value) } catch { $whole = "" }
        if ($whole -eq "") { return (New-HordeUnknown -Reason ($at + " by a path that cannot be read as one")) }
        $what = Get-HordeRelayMember $it "what"
        if (-not $what.has -or $what.value -isnot [string] -or $what.value -cnotmatch $script:HordeRelaySecretWhatPattern) { return (New-HordeUnknown -Reason ($at + " without saying what it is in 1 to 80 printable characters")) }
        [void]$out.Add([pscustomobject]@{ relay = $name; path = $whole; what = [string]$what.value })
    }
    return (New-HordeKnown -Value @($out.ToArray()))
}

function Get-HordeRelaySecretFiles {
    # Which files on this machine hold relays' secrets (the header, the section of that name): known
    # { files; asked } - files every { relay; path; what } of every loaded relay that keeps one, asked
    # the names of the relays that were asked - or unknown, naming each relay that could not tell and
    # why, with their names as its member relays. -HordeHome is the Horde home whose settings are read
    # (empty: this user's own). Reads settings only: no relay is contacted and no secret file is touched.
    param([string]$HordeHome = "")
    if ($HordeHome -ne "" -and -not (Test-HordeRelayAbsolutePath $HordeHome)) { return (New-HordeUnknown -Reason ("which files hold relays' secrets was not asked: the Horde home '" + $HordeHome + "' is not an absolute folder")) }
    $files = New-Object System.Collections.ArrayList
    $asked = New-Object System.Collections.ArrayList
    $cannot = New-Object System.Collections.ArrayList
    $why = New-Object System.Collections.ArrayList
    foreach ($n in @(Get-HordeRelayNames)) {
        $r = $script:HordeRelays[$n]
        if ($null -eq $r.secretFiles) { continue }
        [void]$asked.Add($n)
        $a = Read-HordeRelaySecretFiles -Relay $r -HordeHome $HordeHome
        if ($a.state -cne "known") { [void]$cannot.Add($n); [void]$why.Add($a.reason); continue }
        foreach ($f in @($a.value)) { [void]$files.Add($f) }
    }
    # ONE RELAY THAT CANNOT TELL MAKES THE WHOLE ANSWER UNKNOWN (the header): what the others named is
    # not handed over beside it, so a list with a hole in it cannot be read as the whole list.
    if ($cannot.Count -gt 0) {
        $u = New-HordeUnknown -Reason ("which files hold relays' secrets is not known: " + ($why -join "; "))
        $u | Add-Member -NotePropertyName relays -NotePropertyValue @($cannot.ToArray())
        return $u
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ files = @($files.ToArray()); asked = @($asked.ToArray()) }))
}
