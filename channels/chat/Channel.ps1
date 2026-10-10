# channels/chat - the founder's chat with his horde's Thrall, end to end encrypted: the Thrall's turns out
# to his phone, his signed lines in to the Thrall (relay design 2026-10-09, PR plan item 10).
#
# WHO IT IS FOR. Thrall-level orchestrators only: one Thrall per horde, found by the conversation port by
# its horde and role (conversations/Port.ps1), never anything below it. Several hordes are several
# entries on one phone (work, personal); each horde's machine runs this channel for its own Thrall.
# VENDOR-NEUTRAL: this file names no agent harness and no messenger. What reads the Thrall is whichever
# conversation adapter locates it; what delivers to it is whichever messenger offers what is asked for.
#
# OUT (the Tick): the Thrall's turns, as the conversation port hands them over - user, assistant and
# system text only (founder decision 8), REDACTED BY THE PORT (conversations/Port.ps1, REDACTION IS
# HERE) - sealed to every TRUSTED phone identity key of the horde (relay/Trust.ps1,
# Find-HordeRelayPhoneKeys) and put into the horde's phone mailbox, <horde>/phone, as kind "turns".
#   - FROM THE END. The first look ever, and every phone key trusted since, does not get the whole
#     conversation: the last startTurns turns of the Thrall's session now (a setting; PR 9's open
#     question 2), sealed to the keys that have not had them, marked backfill. After that every new turn
#     goes to every trusted key. The phone keeps turns by id, so a turn that reaches it twice (a
#     backfill beside a live batch, a resend after a crash) is shown once.
#   - THE CURSOR IS DURABLE AND JOURNAL-BACKED (<HORDE_HOME>\relay\chat\state.json, replaced whole in
#     one rename by core/FileAtomic.ps1). Each send is: read from the cursor; record every envelope in
#     the journal (its seq spent, its text kept whole there); write the state - the new cursor and the
#     replay keys recorded and not yet put; put them, dropping each key once the relay took it. A crash
#     before the state is written reads the same turns again and sends them again (shown once: by id);
#     a crash after it puts the SAME envelopes, read back from the journal by key
#     (Test-HordeRelayJournalSent), and nothing is ever lost. A state file that cannot be read stops the
#     channel, in words, and is never quietly started over.
#   - A CLEAR (PR 9's open question 1). When the Thrall's session is not the cursor's, the session the
#     cursor is in is located by its id (Find-HordeConversationSource -Session) and read to its end
#     first: the Thrall's last words before the clear are sent before the new session's first. Then the
#     new session is read from its start. An old session that can no longer be found is said, and left.
#   - SIZE AND PAGES. A batch is as many envelopes as it needs, each body within the setting pageBytes
#     and what the relay holds (channels/Port.ps1, Get-HordeRelayChannelBodyBudget). A turn longer than a
#     page is never cut: it is split into parts that carry its id, part and parts, and the phone joins
#     them. The JSON is written here with everything past printable ASCII as \u escapes, so a byte of
#     the body is a character and a page is measured exactly.
#   - RATE. A read is at most readTurns turns from at most readBytes of the conversation, and turns are
#     sent at most once every sendIntervalMs: a busy Thrall's lines gather into one batch.
#   - THE SESSION IS ANNOUNCED: every turns body names the Thrall's session now, and a change of session
#     is sent even with no turn in it, so the phone always knows which session its lines are for.
#
# IN (the Accept), kind line, from the founder's TRUSTED passkeys only (senders founder: a peer machine,
# trusted or not, is refused before the journal sees it). Every line is a command-equivalent: the
# envelope is a WebAuthn assertion, user verified, over the sealed body (relay/Envelope.ps1), and the
# body binds it to the horde, this machine and the Thrall's session it was written to:
#   {"v":1,"messageId":"<32 hex>","horde":"<horde>","machine":"<32 hex>","session":"<session id>","text":"..."}
# read strictly - no member repeated, none missing, none added.
#   - DELIVERY is through the messenger port (messengers/Port.ps1), by capabilities, never by name:
#     body.untyped and idempotent.post always; wake preferred - the one messenger that also wakes the
#     Thrall, and failing that the one that can report what the receiver saw (receipt.receiver), so an
#     in-process test messenger that can do neither is never picked. Two that fit are never chosen
#     between: the line is held.
#   - EXACTLY ONCE. The messenger's message id is derived from the sender and the phone's message id:
#       id = the first 16 bytes of SHA-256("horde-relay/chat/v1 line id" LF <sender key id> LF <messageId>),
#            written as a lower-case uuid
#     so a record resumed after a crash, or the phone sending the same line again in a new envelope, is
#     the same post, which an idempotent messenger keeps once. A replayed envelope never gets this far:
#     the journal refuses it.
#   - THE BODY THE THRALL GETS is one header line naming the phone's message id - "FOUNDER LINE from the
#     phone (line <messageId>)" - then a blank line, then his words exactly. The header is what lets a
#     phone recognise its own line if an adapter ever shows a delivered line as a turn.
#   - WHETHER A DELIVERED LINE COMES BACK AS A TURN (PR 9's open question 5), measured 2026-10-10: a
#     line handed over by the fleet messenger's Stop hook is written to the transcript as a user line
#     with isMeta true whose text starts "Stop hook feedback:" (227 of 227 such lines across 193 local
#     transcripts, counted by shape only; and an isolated throwaway session with a blocking Stop hook in
#     its project settings wrote the same shape). The first adapter skips meta lines, so a delivered
#     line is NOT a turn: the Thrall's reply is. The phone therefore shows its own line from its send
#     and from the receipt below, and still drops a user turn carrying "(line <its messageId>)", for an
#     adapter or messenger that would show one.
#   - THE RECEIPT. Every line that names a message id gets one back, kind receipt, sealed to every
#     trusted phone key: { messageId, status, code, session, text } - status accepted, held or refused,
#     code from the closed list below, and his words, so a phone that reloads (or another phone of his)
#     still shows the line. Codes only: the phone shows its own fixed sentence for each (relay/js/
#     protocol.js, CHAT_WORDS), never a word of the relay's or the messenger's.
#       accepted  queued (the messenger took it), delivered (handed over, or seen by the receiver)
#       held      thrall-unknown, no-messenger, not-now (it comes again), not-delivered, expired (final)
#       refused   wrong-machine, wrong-horde, empty, too-long, no-thrall, session-ended (final)
#     A held line that comes again says so once per run, not on every turn.
#   done     the messenger answered: delivered, or known not delivered (held for good);
#   refused  for good, with the code above;
#   retry    the Thrall, the messenger or this machine could not say now: the record comes again.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\JsonText.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\ModuleSettings.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\FileAtomic.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\Device.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "conversations\Port.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "messengers\Port.ps1")
# Every conversation adapter and every messenger, at script level, as each must be loaded; one already
# registered in this session (the file loaded twice, or by another module) is not loaded again, because
# a second registration is refused.
foreach ($chatAdapterFile in @(Get-HordeConversationAdapterFiles)) {
    if (@(Get-HordeConversationAdapterNames) -cnotcontains (Split-Path -Leaf (Split-Path -Parent $chatAdapterFile))) { . $chatAdapterFile }
}
foreach ($chatMessengerFile in @(Get-HordeMessengerFiles)) {
    if (@(Get-HordeMessengerNames) -cnotcontains (Split-Path -Leaf (Split-Path -Parent $chatMessengerFile))) { . $chatMessengerFile }
}

$script:HordeChatChannelFolder = $PSScriptRoot
$script:HordeChatChannelSettings = New-HordeModuleSettings -Module "relay-chat" -Settings @(
    # 50 turns is about the last hour of a busy Thrall (485 prompts and 739 replies in a working day,
    # conversations/Port.ps1, THE CEILINGS): what a phone just paired needs to pick up the thread.
    @{ name = "startTurns"; kind = "whole"; default = 50; min = 0; max = 1000; what = "How many of the Thrall's last turns a phone key newly trusted is sent first." },
    @{ name = "readTurns"; kind = "whole"; default = 200; min = 1; max = 1000; what = "The most turns read from the Thrall's conversation in one look." },
    @{ name = "readBytes"; kind = "whole"; default = 1048576; min = 4096; max = 33554432; what = "The most bytes of the Thrall's conversation read in one look." },
    @{ name = "pageBytes"; kind = "whole"; default = 262144; min = 2048; max = 1048576; what = "The largest body of one envelope of turns, in bytes; a longer batch is sent as more envelopes." },
    @{ name = "sendIntervalMs"; kind = "whole"; default = 2000; min = 0; max = 600000; what = "The shortest time between two sends of turns, in milliseconds: turns written meanwhile go together." },
    @{ name = "lineChars"; kind = "whole"; default = 16000; min = 1; max = 60000; what = "The longest line the founder may send to the Thrall, in characters." },
    @{ name = "ttlSeconds"; kind = "whole"; default = 86400; min = 60; max = 604800; what = "How long a line may wait in the Thrall's mailbox, in seconds." },
    @{ name = "fromLabel"; kind = "label"; default = "F"; what = "The hub label the founder's lines are from: F, unless the person who sends them wears another." }
)
$script:HordeChatChannelLineMembers = @("v", "messageId", "horde", "machine", "session", "text")
$script:HordeChatChannelIdDomain = "horde-relay/chat/v1 line id"
$script:HordeChatChannelFrom = "horde-relay-chat"
$script:HordeChatChannelSessionPattern = '\A[A-Za-z0-9._:-]{1,128}\z'
$script:HordeChatChannelCodes = @{
    accepted = @("queued", "delivered")
    held = @("thrall-unknown", "no-messenger", "not-now", "not-delivered", "expired")
    refused = @("wrong-machine", "wrong-horde", "empty", "too-long", "no-thrall", "session-ended")
}
# What reads the Thrall: what the channel needs of an adapter. A turn sent is never sent again changed,
# so a source whose turns may still grow (partialTurns) is refused; ids are what the phone shows a turn
# once by, and a cursor is what the durable state keeps.
$script:HordeChatChannelRequire = @("incremental", "stableTurnIds")
$script:HordeChatChannelRefuse = @("partialTurns")
# For suites only (Set-HordeChatChannelSource): the conversation port's options and adapter. Empty means
# what the adapters default to - the machine's own fleet.
$script:HordeChatChannelSourceOptions = @{}
$script:HordeChatChannelSourceVendor = ""

function Set-HordeChatChannelSource {
    # For tests: the options the conversation port is asked with, and the one adapter to ask (a memory
    # source). @{} and "" put back the defaults.
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Options, [AllowEmptyString()][string]$Vendor = "")
    $script:HordeChatChannelSourceOptions = $Options
    $script:HordeChatChannelSourceVendor = $Vendor
}

function Get-HordeChatChannelSettingsDeclaration { return $script:HordeChatChannelSettings }

function Get-HordeChatChannelHome {
    param($Context)
    if ("$($Context.hordeHome)" -ne "") { return $Context.hordeHome }
    return (Get-HordeHome)
}

function ConvertTo-HordeChatChannelJsonString {
    # A JSON string of -Text in printable ASCII: quote, backslash, every control character and everything
    # past 0x7E as a \u escape. One byte per character of output, so a page is measured exactly.
    param([AllowEmptyString()][string]$Text)
    $body = [regex]::Replace($Text, '[^\x20\x21\x23-\x5B\x5D-\x7E]', { param($m) '\u' + ([int][char]$m.Value).ToString("x4") })
    return ('"' + $body + '"')
}

function Get-HordeChatChannelStatePath {
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    return [System.IO.Path]::Combine($HordeHome, "relay", "chat", "state.json")
}

function Read-HordeChatChannelState {
    # The durable state: known { cursor; session; phones; pending }, the empty state when there is no file
    # yet, unknown when the file cannot be read or does not hold together - never a guess.
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    $path = Get-HordeChatChannelStatePath -HordeHome $HordeHome
    $empty = [pscustomobject]@{ cursor = $null; session = ""; phones = @(); pending = @() }
    if (-not [System.IO.File]::Exists($path)) { return (New-HordeKnown -Value $empty) }
    try { $bytes = [System.IO.File]::ReadAllBytes($path); Assert-HordeAsciiBytes -Bytes $bytes -What ("the chat state " + $path); $text = [System.Text.Encoding]::ASCII.GetString($bytes) }
    catch { return (New-HordeUnknown -Reason ("the chat state " + $path + " cannot be read: " + $_.Exception.Message)) }
    $why = "the chat state " + $path + " does not hold together"
    if (@(Find-HordeJsonDuplicateKey -Text $text).Count -gt 0) { return (New-HordeUnknown -Reason ($why + ": a member is repeated")) }
    try { $s = ConvertFrom-Json -InputObject $text } catch { return (New-HordeUnknown -Reason ($why + ": it is not JSON")) }
    if ($s -isnot [System.Management.Automation.PSCustomObject]) { return (New-HordeUnknown -Reason ($why + ": it is not an object")) }
    $names = @($s.PSObject.Properties | ForEach-Object { $_.Name }) | Sort-Object
    if (($names -join ",") -cne "cursor,pending,phones,session,v") { return (New-HordeUnknown -Reason ($why + ": its members are " + ($names -join ", "))) }
    if (-not ($s.v -is [int] -or $s.v -is [long]) -or $s.v -ne 1) { return (New-HordeUnknown -Reason ($why + ": it is not version 1")) }
    if ($s.session -isnot [string]) { return (New-HordeUnknown -Reason ($why + ": its session is not text")) }
    foreach ($p in @($s.phones)) { if ($p -isnot [string] -or $p -cnotmatch '\A[0-9a-f]{32}\z') { return (New-HordeUnknown -Reason ($why + ": a phone key is not a key id")) } }
    foreach ($k in @($s.pending)) { if ($k -isnot [string] -or $k.Length -gt 160) { return (New-HordeUnknown -Reason ($why + ": a pending envelope is not a replay key")) } }
    if ($null -ne $s.cursor -and $s.cursor -isnot [System.Management.Automation.PSCustomObject]) { return (New-HordeUnknown -Reason ($why + ": its cursor is not an object")) }
    return (New-HordeKnown -Value ([pscustomobject]@{ cursor = $s.cursor; session = $s.session; phones = @($s.phones); pending = @($s.pending) }))
}

function Write-HordeChatChannelState {
    # The durable state, replaced whole in one rename. Throws when it cannot be written.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)]$State)
    $path = Get-HordeChatChannelStatePath -HordeHome $HordeHome
    $dir = [System.IO.Path]::GetDirectoryName($path)
    [void][System.IO.Directory]::CreateDirectory($dir)
    $cursor = "null"
    if ($null -ne $State.cursor) {
        $c = $State.cursor
        $cursor = '{"schemaVersion":1,"vendor":' + (ConvertTo-HordeChatChannelJsonString "$($c.vendor)") + ',"session":' + (ConvertTo-HordeChatChannelJsonString "$($c.session)") + ',"position":' + (ConvertTo-HordeChatChannelJsonString "$($c.position)") + '}'
    }
    $phones = (@($State.phones) | ForEach-Object { '"' + $_ + '"' }) -join ","
    $pending = (@($State.pending) | ForEach-Object { ConvertTo-HordeChatChannelJsonString $_ }) -join ","
    $text = '{"v":1,"cursor":' + $cursor + ',"session":' + (ConvertTo-HordeChatChannelJsonString "$($State.session)") + ',"phones":[' + $phones + '],"pending":[' + $pending + ']}'
    $tmp = [System.IO.Path]::Combine($dir, ("state-" + [guid]::NewGuid().ToString("N") + ".tmp"))
    $fs = New-Object System.IO.FileStream -ArgumentList $tmp, ([System.IO.FileMode]::CreateNew), ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::None)
    try { $b = [System.Text.Encoding]::ASCII.GetBytes($text); $fs.Write($b, 0, $b.Length); $fs.Flush($true) } finally { $fs.Dispose() }
    try { Move-HordeFileAtomic -From $tmp -To $path } catch { try { [System.IO.File]::Delete($tmp) } catch { }; throw }
}

function Get-HordeChatChannelStateMark {
    # What the durable state says, as one string, to tell whether it changed.
    param($State)
    $c = $State.cursor
    $cur = $(if ($null -eq $c) { "-" } else { "$($c.vendor)|$($c.session)|$($c.position)" })
    return ($cur + "#" + $State.session + "#" + (@($State.phones) -join ",") + "#" + (@($State.pending) -join ","))
}

function Get-HordeChatChannelMemory {
    # The channel's memory in this run's context, its durable state read on first use: { ok; reason; mine }.
    param($Context)
    if (-not $Context.state.ContainsKey("chat")) {
        $Context.state["chat"] = @{ loaded = $false; durable = $null; lastSentAt = [datetime]::MinValue; said = @{}; heldSaid = @{} }
    }
    $mine = $Context.state["chat"]
    if (-not $mine.loaded) {
        $s = Read-HordeChatChannelState -HordeHome (Get-HordeChatChannelHome $Context)
        if ($s.state -cne "known") { return [pscustomobject]@{ ok = $false; reason = $s.reason; mine = $mine } }
        $mine.durable = $s.value
        $mine.loaded = $true
    }
    return [pscustomobject]@{ ok = $true; reason = ""; mine = $mine }
}

function Get-HordeChatChannelSettings {
    param($Context)
    $s = Get-HordeModuleSettings -Declaration $script:HordeChatChannelSettings -HordeHome (Get-HordeChatChannelHome $Context)
    if ($s.state -ceq "refused") { return (New-HordeUnknown -Reason (@($s.findings) -join " ")) }
    return (New-HordeKnown -Value $s.values)
}

function Find-HordeChatChannelSource {
    # The Thrall's conversation (or, with -Session, one past session of it), through the port.
    param($Context, [string]$Session = "")
    return (Find-HordeConversationSource -Fleet $Context.horde -Vendor $script:HordeChatChannelSourceVendor -Session $Session -Require $script:HordeChatChannelRequire -Refuse $script:HordeChatChannelRefuse -Options $script:HordeChatChannelSourceOptions)
}

function Read-HordeChatChannelTail {
    # The last -Keep turns of -Source from -Cursor to its end, and the cursor at the end: known { turns;
    # next }, or the port's unknown. Every read is bounded; a conversation longer than 10,000 reads is
    # not one (10 million turns at the most a read may give).
    param($Source, $Cursor, [int]$Keep, $Settings)
    $queue = New-Object System.Collections.Generic.Queue[object]
    $at = $Cursor
    for ($i = 0; $i -lt 10000; $i++) {
        $r = Read-HordeConversationTurns -Source $Source -Cursor $at -MaxTurns ([int]$Settings.readTurns) -MaxBytes ([long]$Settings.readBytes)
        if ($r.state -cne "known") { return $r }
        foreach ($t in @($r.value.turns)) { $queue.Enqueue($t); if ($queue.Count -gt $Keep) { [void]$queue.Dequeue() } }
        $at = $r.value.next
        if (-not $r.value.more) { break }
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ turns = @($queue.ToArray()); next = $at }))
}

function ConvertTo-HordeChatChannelEntries {
    # One turn as the JSON texts of its entries: one, or, when it does not fit -Room bytes, its text split
    # into parts that each do. A surrogate pair is never split.
    param($Turn, [long]$Room)
    $head = '{"id":' + (ConvertTo-HordeChatChannelJsonString $Turn.turnId) + ',"role":"' + $Turn.role + '","session":' + (ConvertTo-HordeChatChannelJsonString $Turn.source.session)
    if ($null -ne $Turn.PSObject.Properties["time"]) { $head += ',"time":"' + $Turn.time + '"' }
    if ($null -ne $Turn.PSObject.Properties["groupId"]) { $head += ',"group":' + (ConvertTo-HordeChatChannelJsonString $Turn.groupId) }
    if ($null -ne $Turn.PSObject.Properties["truncated"]) { $head += ',"truncated":true' }
    if ($null -ne $Turn.PSObject.Properties["redactions"]) { $head += ',"redactions":' + [int]$Turn.redactions }
    $whole = $head + ',"text":' + (ConvertTo-HordeChatChannelJsonString $Turn.text) + '}'
    if ($whole.Length -le $Room) { return @($whole) }
    # The part fields at their widest: up to 99,999 parts of a turn of at most 100,000 characters.
    $frame = ($head + ',"part":99999,"parts":99999,"text":""}').Length
    $fit = $Room - $frame
    if ($fit -lt 12) { throw ("a page of " + $Room + " bytes cannot hold a part of turn " + $Turn.turnId) }
    $chunks = New-Object System.Collections.ArrayList
    $text = $Turn.text
    $start = 0; $cost = 0
    for ($i = 0; $i -lt $text.Length; $i++) {
        $c = [int]$text[$i]
        $w = $(if ($c -lt 0x20 -or $c -gt 0x7E) { 6 } elseif ($c -eq 0x22 -or $c -eq 0x5C) { 6 } else { 1 })
        # A high surrogate is weighed with its low one: they go in one chunk.
        if ($c -ge 0xD800 -and $c -le 0xDBFF -and $i + 1 -lt $text.Length) { $w = 12 }
        if ($cost + $w -gt $fit -and $i -gt $start) { [void]$chunks.Add($text.Substring($start, $i - $start)); $start = $i; $cost = 0 }
        $cost += $w
        if ($w -eq 12) { $i++ }
    }
    [void]$chunks.Add($text.Substring($start))
    $out = New-Object System.Collections.ArrayList
    for ($k = 0; $k -lt $chunks.Count; $k++) { [void]$out.Add($head + ',"part":' + ($k + 1) + ',"parts":' + $chunks.Count + ',"text":' + (ConvertTo-HordeChatChannelJsonString $chunks[$k]) + '}') }
    return @($out.ToArray())
}

function New-HordeChatChannelPages {
    # The bodies of one batch of turns: as many as it needs, each within -Budget bytes. One body even
    # with no turn: the session is announced.
    param($Context, [string]$Session, [bool]$Backfill, [object[]]$Turns, [long]$Budget)
    $front = '{"v":1,"kind":"chat-turns","horde":"' + $Context.horde + '","machine":"' + $Context.signKeyId + '","session":' + (ConvertTo-HordeChatChannelJsonString $Session) + ',"backfill":' + $(if ($Backfill) { "true" } else { "false" }) + ',"turns":['
    $back = ']}'
    $room = $Budget - $front.Length - $back.Length
    $pages = New-Object System.Collections.ArrayList
    $current = New-Object System.Collections.ArrayList
    $used = 0
    foreach ($t in @($Turns)) {
        foreach ($e in @(ConvertTo-HordeChatChannelEntries -Turn $t -Room $room)) {
            $add = $e.Length + $(if ($current.Count -gt 0) { 1 } else { 0 })
            if ($current.Count -gt 0 -and $used + $add -gt $room) { [void]$pages.Add($front + ($current -join ",") + $back); $current = New-Object System.Collections.ArrayList; $used = 0; $add = $e.Length }
            [void]$current.Add($e)
            $used += $add
        }
    }
    if ($current.Count -gt 0 -or $pages.Count -eq 0) { [void]$pages.Add($front + ($current -join ",") + $back) }
    return @($pages.ToArray())
}

function Send-HordeChatChannelPending {
    # Put every envelope recorded and not yet taken, in order, from the journal; each one taken leaves
    # the state. "" when all were taken, else why not.
    param($Context, $Mine)
    $homeDir = Get-HordeChatChannelHome $Context
    $mailbox = New-HordeRelayMailbox -Horde $Context.horde -Reader "phone"
    while (@($Mine.durable.pending).Count -gt 0) {
        $key = @($Mine.durable.pending)[0]
        $rec = Test-HordeRelayJournalSent -Key $key -HordeHome $homeDir
        if ($rec.state -cne "known") { return ("the journal cannot give back " + $key + ": " + $rec.reason) }
        if ($rec.value.sent) {
            $put = Send-HordeRelayChannelSaved -Context $Context -Saved ([pscustomobject]@{ key = $key; text = $rec.value.text }) -Mailbox $mailbox
            if ($put.state -cne "known") { return $put.reason }
        }
        # A key the journal does not hold was never recorded (a state written by hand): nothing to put.
        $Mine.durable.pending = @(@($Mine.durable.pending) | Select-Object -Skip 1)
        try { Write-HordeChatChannelState -HordeHome $homeDir -State $Mine.durable } catch { return ("the chat state could not be written: " + $_.Exception.Message) }
    }
    return ""
}

function Save-HordeChatChannelBodies {
    # Record each body as one envelope of -Kind sealed to -Phones; the keys, in order, or a throw-free
    # failure: { ok; reason; keys }.
    param($Context, [string]$Kind, [object[]]$Bodies, [object[]]$Phones)
    $recipients = @($Phones | ForEach-Object { , ([byte[]]$_.public) })
    $keys = New-Object System.Collections.ArrayList
    foreach ($b in @($Bodies)) {
        $saved = Save-HordeRelayChannelEnvelope -Context $Context -Channel "chat" -Kind $Kind -Body ([System.Text.Encoding]::ASCII.GetBytes([string]$b)) -Recipients $recipients
        if ($saved.state -cne "known") { return [pscustomobject]@{ ok = $false; reason = $saved.reason; keys = @($keys.ToArray()) } }
        [void]$keys.Add($saved.value.key)
    }
    return [pscustomobject]@{ ok = $true; reason = ""; keys = @($keys.ToArray()) }
}

function Get-HordeChatChannelPhones {
    # The trusted phone keys, at most an envelope's recipients.
    param($Context)
    $phones = Find-HordeRelayPhoneKeys -HordeHome (Get-HordeChatChannelHome $Context)
    if ($phones.state -cne "known") { return $phones }
    $keys = @($phones.value)
    $limit = (Get-HordeRelayEnvelopeLimits).recipients
    if ($keys.Count -gt $limit) { $keys = @($keys | Select-Object -First $limit) }
    return (New-HordeKnown -Value $keys)
}

function Invoke-HordeChatChannelTick {
    # OUT, in the header: { lines; failed }.
    param($Context)
    $m = Get-HordeChatChannelMemory -Context $Context
    $mine = $m.mine
    $once = {
        param([string]$Key, [string]$Line, [bool]$Failed)
        if ($mine.said.ContainsKey($Key) -and $mine.said[$Key] -ceq $Line) { return [pscustomobject]@{ lines = @(); failed = $Failed } }
        $mine.said[$Key] = $Line
        return [pscustomobject]@{ lines = @($Line); failed = $Failed }
    }
    if (-not $m.ok) { return (& $once "state" ("chat is stopped: " + $m.reason + "; mend or move the file, and the channel starts again") $true) }
    $set = Get-HordeChatChannelSettings -Context $Context
    if ($set.state -cne "known") { return (& $once "settings" ("chat is stopped: " + $set.reason) $true) }
    $set = $set.value
    $homeDir = Get-HordeChatChannelHome $Context
    if (@($mine.durable.pending).Count -gt 0) {
        $why = Send-HordeChatChannelPending -Context $Context -Mine $mine
        if ($why -cne "") { return [pscustomobject]@{ lines = @("turns not delivered yet (" + @($mine.durable.pending).Count + " envelope(s) recorded and waiting): " + $why); failed = $true } }
    }
    $phones = Get-HordeChatChannelPhones -Context $Context
    if ($phones.state -cne "known") { return [pscustomobject]@{ lines = @("no turns sent: " + $phones.reason); failed = $true } }
    $all = @($phones.value)
    if ($all.Count -eq 0) { return (& $once "phones" "no turns sent: no phone identity key of this horde is trusted yet" $false) }
    if ([long]$set.sendIntervalMs -gt 0 -and ([datetime]::UtcNow - $mine.lastSentAt).TotalMilliseconds -lt [long]$set.sendIntervalMs) { return [pscustomobject]@{ lines = @(); failed = $false } }
    $src = Find-HordeChatChannelSource -Context $Context
    if ($src.state -ceq "absent") { return (& $once "source" ("no turns sent: no Thrall of horde " + $Context.horde + " is found on this machine") $false) }
    if ($src.state -cne "known") { return (& $once "source" ("no turns sent: the Thrall cannot be read now: " + $src.reason) $false) }
    $mine.said.Remove("source"); $mine.said.Remove("phones")
    $source = $src.value
    $d = $mine.durable
    $was = Get-HordeChatChannelStateMark -State $d
    $batches = New-Object System.Collections.ArrayList
    $notes = New-Object System.Collections.ArrayList
    $known = @($all | ForEach-Object { $_.agreeKeyId })
    $cursor = $d.cursor
    if ($null -eq $cursor) {
        # THE FIRST LOOK: from the end, for every key there is.
        $tail = Read-HordeChatChannelTail -Source $source -Cursor $null -Settings $set -Keep ([int]$set.startTurns)
        if ($tail.state -cne "known") { return (& $once "read" ("no turns sent: the Thrall's conversation could not be read: " + $tail.reason) $false) }
        [void]$batches.Add([pscustomobject]@{ phones = $all; backfill = $true; turns = @($tail.value.turns) })
        $next = $tail.value.next
    } else {
        $fresh = @($all | Where-Object { @($d.phones) -cnotcontains $_.agreeKeyId })
        if ($fresh.Count -gt 0) {
            # A KEY TRUSTED SINCE: the last startTurns turns of the session now, to it alone.
            $tail = Read-HordeChatChannelTail -Source $source -Cursor $null -Keep ([int]$set.startTurns) -Settings $set
            if ($tail.state -cne "known") { return (& $once "read" ("no turns sent: the Thrall's conversation could not be read: " + $tail.reason) $false) }
            [void]$batches.Add([pscustomobject]@{ phones = $fresh; backfill = $true; turns = @($tail.value.turns) })
        }
        if ("$($cursor.session)" -cne $source.session) {
            # A CLEAR: the old session read to its end first.
            $old = Find-HordeChatChannelSource -Context $Context -Session "$($cursor.session)"
            $next = New-HordeConversationCursor -Vendor $source.vendor -Session $source.session -Position ""
            if ($old.state -ceq "known") {
                $r = Read-HordeConversationTurns -Source $old.value -Cursor $cursor -MaxTurns ([int]$set.readTurns) -MaxBytes ([long]$set.readBytes)
                if ($r.state -ceq "known") {
                    if (@($r.value.turns).Count -gt 0) { [void]$batches.Add([pscustomobject]@{ phones = $all; backfill = $false; turns = @($r.value.turns) }) }
                    if ($r.value.more) { $next = $r.value.next }
                    else { [void]$notes.Add("the Thrall's session before the clear was read to its end") }
                }
                else { [void]$notes.Add("the Thrall's session before the clear could not be read, and is left: " + $r.reason) }
            }
            else { [void]$notes.Add("the Thrall's session before the clear is not found, and is left: " + $old.reason) }
        } else {
            $r = Read-HordeConversationTurns -Source $source -Cursor $cursor -MaxTurns ([int]$set.readTurns) -MaxBytes ([long]$set.readBytes)
            if ($r.state -cne "known") { return (& $once "read" ("no turns sent: the Thrall's conversation could not be read: " + $r.reason) $false) }
            foreach ($a in @($r.value.anomalies)) { [void]$notes.Add($a) }
            if (@($r.value.turns).Count -gt 0) { [void]$batches.Add([pscustomobject]@{ phones = $all; backfill = $false; turns = @($r.value.turns) }) }
            $next = $r.value.next
        }
    }
    $mine.said.Remove("read")
    # THE SESSION ANNOUNCED: a change goes out even with no turn in it.
    if ($d.session -cne $source.session -and @($batches | Where-Object { -not $_.backfill -or @($_.phones).Count -eq $all.Count }).Count -eq 0) {
        [void]$batches.Add([pscustomobject]@{ phones = $all; backfill = $false; turns = @() })
    }
    $keys = New-Object System.Collections.ArrayList
    $count = 0
    foreach ($b in $batches) {
        $budget = [long][System.Math]::Min([double]$set.pageBytes, [double](Get-HordeRelayChannelBodyBudget -Context $Context -Recipients @($b.phones).Count))
        $bodies = New-HordeChatChannelPages -Context $Context -Session $source.session -Backfill $b.backfill -Turns @($b.turns) -Budget $budget
        $saved = Save-HordeChatChannelBodies -Context $Context -Kind "turns" -Bodies $bodies -Phones @($b.phones)
        foreach ($k in $saved.keys) { [void]$keys.Add($k) }
        if (-not $saved.ok) {
            # What was recorded is kept to be put; the cursor stays, so the rest is read again.
            $d.pending = @($d.pending) + @($keys.ToArray())
            try { Write-HordeChatChannelState -HordeHome $homeDir -State $d } catch { }
            return [pscustomobject]@{ lines = @("turns not sent: " + $saved.reason); failed = $true }
        }
        $count += @($b.turns).Count
    }
    $d.cursor = $next
    $d.session = $source.session
    $d.phones = $known
    $d.pending = @(@($d.pending) + @($keys.ToArray()))
    # Written only when it changed: a runner turns every second, and a quiet Thrall is no reason to
    # rewrite a file each time.
    try { if ($keys.Count -gt 0 -or (Get-HordeChatChannelStateMark -State $d) -cne $was) { Write-HordeChatChannelState -HordeHome $homeDir -State $d } }
    catch { return [pscustomobject]@{ lines = @("turns recorded, and the chat state could not be written: " + $_.Exception.Message + "; they are sent again after a restart, and the phone shows each once"); failed = $true } }
    $lines = New-Object System.Collections.ArrayList
    foreach ($n in $notes) { [void]$lines.Add($n) }
    if ($keys.Count -eq 0) { return [pscustomobject]@{ lines = @($lines.ToArray()); failed = $false } }
    $mine.lastSentAt = [datetime]::UtcNow
    $what = "" + $count + " turn(s) of the Thrall in " + $keys.Count + " envelope(s)"
    $why = Send-HordeChatChannelPending -Context $Context -Mine $mine
    if ($why -cne "") { [void]$lines.Add($what + " recorded; not delivered yet: " + $why); return [pscustomobject]@{ lines = @($lines.ToArray()); failed = $true } }
    [void]$lines.Add($what + " sent")
    return [pscustomobject]@{ lines = @($lines.ToArray()); failed = $false }
}

function Read-HordeChatChannelLine {
    # The phone's line body, read strictly: { ok; reason; value } with value { messageId; horde; machine;
    # session; text }. Never throws for the body: the PWA that wrote it is code, and code has bugs.
    param([AllowEmptyCollection()][byte[]]$Body)
    $fail = [pscustomobject]@{ ok = $false; reason = ""; value = $null }
    $strict = New-Object System.Text.UTF8Encoding -ArgumentList $false, $true
    try { $text = $strict.GetString($Body) } catch { $fail.reason = "the line is not UTF-8"; return $fail }
    if (-not $text.TrimStart().StartsWith("{")) { $fail.reason = "the line is not a JSON object"; return $fail }
    $dups = @(Find-HordeJsonDuplicateKey -Text $text)
    if ($dups.Count -gt 0) { $fail.reason = ("the line has a member more than once: " + $dups[0]); return $fail }
    try { $a = ConvertFrom-Json -InputObject $text } catch { $fail.reason = "the line is not JSON"; return $fail }
    if ($a -isnot [System.Management.Automation.PSCustomObject]) { $fail.reason = "the line is not a JSON object"; return $fail }
    $names = @($a.PSObject.Properties | ForEach-Object { $_.Name })
    if ((@($names | Sort-Object) -join ",") -cne (@($script:HordeChatChannelLineMembers | Sort-Object) -join ",")) { $fail.reason = ("the line's members are " + ($names -join ", ") + ", not " + ($script:HordeChatChannelLineMembers -join ", ")); return $fail }
    if (-not ($a.v -is [int] -or $a.v -is [long]) -or $a.v -ne 1) { $fail.reason = "the line is not version 1"; return $fail }
    if ($a.messageId -isnot [string] -or $a.messageId -cnotmatch '\A[0-9a-f]{32}\z') { $fail.reason = "the line's messageId is not 32 lower-case hex"; return $fail }
    if ($a.horde -isnot [string] -or $a.horde -cnotmatch '\A[a-z0-9][a-z0-9-]{0,62}\z') { $fail.reason = "the line's horde is not a horde name"; return $fail }
    if ($a.machine -isnot [string] -or $a.machine -cnotmatch '\A[0-9a-f]{32}\z') { $fail.reason = "the line's machine is not a key id"; return $fail }
    if ($a.session -isnot [string] -or $a.session -cnotmatch $script:HordeChatChannelSessionPattern) { $fail.reason = "the line's session is not a session id"; return $fail }
    if ($a.text -isnot [string]) { $fail.reason = "the line's text is not text"; return $fail }
    return [pscustomobject]@{ ok = $true; reason = ""; value = [pscustomobject]@{ messageId = $a.messageId; horde = $a.horde; machine = $a.machine; session = $a.session; text = [string]$a.text } }
}

function Get-HordeChatChannelMessageId {
    # The messenger's message id of one line (EXACTLY ONCE, in the header): a lower-case uuid.
    param([Parameter(Mandatory = $true)][string]$From, [Parameter(Mandatory = $true)][string]$MessageId)
    $h = ConvertTo-HordeRelayHex -Bytes (Get-HordeRelaySha256 -Bytes (Get-HordeRelayAsciiBytes -Text ($script:HordeChatChannelIdDomain + "`n" + $From + "`n" + $MessageId)))
    return ($h.Substring(0, 8) + "-" + $h.Substring(8, 4) + "-" + $h.Substring(12, 4) + "-" + $h.Substring(16, 4) + "-" + $h.Substring(20, 12))
}

function Get-HordeChatChannelThrallBody {
    # What the Thrall reads (header): the header line with the phone's message id, a blank line, his words.
    param([Parameter(Mandatory = $true)][string]$MessageId, [Parameter(Mandatory = $true)][string]$Text)
    return ("FOUNDER LINE from the phone (line " + $MessageId + ")`n`n" + $Text)
}

function Find-HordeChatChannelMessenger {
    # The messenger a line goes through (DELIVERY, in the header): known, or why not as unknown.
    $wakes = Find-HordeMessenger -Require @("body.untyped", "idempotent.post", "wake")
    if ($wakes.state -ceq "known") { return $wakes }
    if ($wakes.state -ceq "unknown") { return $wakes }
    $sees = Find-HordeMessenger -Require @("body.untyped", "idempotent.post", "receipt.receiver")
    if ($sees.state -ceq "known") { return $sees }
    if ($sees.state -ceq "unknown") { return $sees }
    return (New-HordeUnknown -Reason ("no messenger on this machine can deliver a line to the Thrall: " + $wakes.reason))
}

function Send-HordeChatChannelReceipt {
    # Record and put the receipt of one line (THE RECEIPT, in the header). "" when sent, else why not -
    # a receipt recorded and not put waits in the state, and the Tick puts it.
    param($Context, $Mine, [string]$MessageId, [string]$Status, [string]$Code, [string]$Session, [string]$Text)
    if ($script:HordeChatChannelCodes[$Status] -cnotcontains $Code) { throw ("'" + $Code + "' is not a " + $Status + " code") }
    $phones = Get-HordeChatChannelPhones -Context $Context
    if ($phones.state -cne "known") { return ("no receipt: " + $phones.reason) }
    if (@($phones.value).Count -eq 0) { return "no receipt: no phone identity key is trusted" }
    $body = '{"v":1,"kind":"chat-receipt","horde":"' + $Context.horde + '","machine":"' + $Context.signKeyId + '","session":' + (ConvertTo-HordeChatChannelJsonString $Session) + ',"messageId":"' + $MessageId + '","status":"' + $Status + '","code":"' + $Code + '","text":' + (ConvertTo-HordeChatChannelJsonString $Text) + '}'
    $saved = Save-HordeChatChannelBodies -Context $Context -Kind "receipt" -Bodies @($body) -Phones @($phones.value)
    if (-not $saved.ok) { return ("no receipt: " + $saved.reason) }
    $Mine.durable.pending = @(@($Mine.durable.pending) + @($saved.keys))
    try { Write-HordeChatChannelState -HordeHome (Get-HordeChatChannelHome $Context) -State $Mine.durable } catch { }
    return (Send-HordeChatChannelPending -Context $Context -Mine $Mine)
}

function Invoke-HordeChatChannelAccept {
    # One opened line, to the Thrall (IN, in the header). { outcome; reason }.
    param($Context, $Item)
    $r = Read-HordeChatChannelLine -Body $Item.body
    if (-not $r.ok) { return [pscustomobject]@{ outcome = "refused"; reason = $r.reason } }
    $line = $r.value
    $m = Get-HordeChatChannelMemory -Context $Context
    if (-not $m.ok) { return [pscustomobject]@{ outcome = "retry"; reason = ("the chat state cannot be read: " + $m.reason) } }
    $mine = $m.mine
    $answer = {
        param([string]$Outcome, [string]$Status, [string]$Code, [string]$Why, [string]$Session)
        $note = ""
        $heldKey = $line.messageId + "/" + $Code
        if ($Status -cne "held" -or -not $mine.heldSaid.ContainsKey($heldKey)) {
            if ($Status -ceq "held") { $mine.heldSaid[$heldKey] = $true }
            $sent = Send-HordeChatChannelReceipt -Context $Context -Mine $mine -MessageId $line.messageId -Status $Status -Code $Code -Session $Session -Text $line.text
            if ($sent -cne "") { $note = "; " + $sent }
        }
        return [pscustomobject]@{ outcome = $Outcome; reason = ("line " + $line.messageId + ": " + $Status + " (" + $Code + ") - " + $Why + $note) }
    }
    $set = Get-HordeChatChannelSettings -Context $Context
    if ($set.state -cne "known") { return [pscustomobject]@{ outcome = "retry"; reason = ("the relay-chat settings are refused: " + $set.reason) } }
    $set = $set.value
    if ($line.machine -cne $Context.signKeyId) { return (& $answer "refused" "refused" "wrong-machine" ("it is for the machine " + $line.machine + ", not this one") $line.session) }
    if ($line.horde -cne $Context.horde) { return (& $answer "refused" "refused" "wrong-horde" ("it is for the horde " + $line.horde + ", not " + $Context.horde) $line.session) }
    if ($line.text.Trim() -eq "") { return (& $answer "refused" "refused" "empty" "it holds no words" $line.session) }
    if ($line.text.Length -gt [int]$set.lineChars) { return (& $answer "refused" "refused" "too-long" ("it is " + $line.text.Length + " characters; a line holds " + $set.lineChars) $line.session) }
    $src = Find-HordeChatChannelSource -Context $Context
    if ($src.state -ceq "absent") { return (& $answer "refused" "refused" "no-thrall" "no Thrall of this horde is found on this machine" $line.session) }
    if ($src.state -cne "known") { return (& $answer "retry" "held" "thrall-unknown" ("the Thrall cannot be found now: " + $src.reason) $line.session) }
    if ($src.value.session -cne $line.session) { return (& $answer "refused" "refused" "session-ended" ("it was written to the session " + $line.session + ", and the Thrall's session is now " + $src.value.session) $src.value.session) }
    $messenger = Find-HordeChatChannelMessenger
    if ($messenger.state -cne "known") { return (& $answer "retry" "held" "no-messenger" $messenger.reason $line.session) }
    $deviceId = ""
    try { $deviceId = Get-HordeDeviceId -HomeRoot (Get-HordeChatChannelHome $Context) } catch { return (& $answer "retry" "held" "not-now" ("this machine's device id could not be had: " + $_.Exception.Message) $line.session) }
    $message = [pscustomobject]@{
        messageId = (Get-HordeChatChannelMessageId -From $Item.from -MessageId $line.messageId); sessionId = $src.value.session
        from = [pscustomobject]@{ deviceId = $deviceId; sessionId = $script:HordeChatChannelFrom; label = $set.fromLabel }
        body = (Get-HordeChatChannelThrallBody -MessageId $line.messageId -Text $line.text); ttlSeconds = [int]$set.ttlSeconds
    }
    $posted = Send-HordeMessengerMessage -Messenger $messenger.value -Message $message
    if ($posted.state -cne "known") { return (& $answer "retry" "held" "not-now" ("messenger " + $messenger.value.name + " did not take it now: " + $posted.reason) $line.session) }
    switch ("$($posted.value.stage)") {
        "accepted" { return (& $answer "done" "accepted" "queued" ("messenger " + $messenger.value.name + " took it for the Thrall") $line.session) }
        "held" { return (& $answer "done" "held" "not-delivered" ("messenger " + $messenger.value.name + " holds it, not delivered") $line.session) }
        "expired" { return (& $answer "done" "held" "expired" ("messenger " + $messenger.value.name + " gave it up undelivered") $line.session) }
        default { return (& $answer "done" "accepted" "delivered" ("messenger " + $messenger.value.name + " handed it to the Thrall (" + $posted.value.stage + ")") $line.session) }
    }
}

$null = Register-HordeRelayChannel -Folder $script:HordeChatChannelFolder -Name "chat" -Kinds @("line") -Senders "founder" `
    -Accept { param($Context, $Item) return (Invoke-HordeChatChannelAccept -Context $Context -Item $Item) } `
    -Tick { param($Context) return (Invoke-HordeChatChannelTick -Context $Context) }
