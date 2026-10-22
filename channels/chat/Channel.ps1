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
#   - NEVER PUT TO A KEY REVOKED SINCE IT WAS RECORDED (review of 3d837f0, finding 3). The state also
#     keeps rewind: the cursor from before the oldest envelope still waiting. Before each put, the
#     envelope's recipients are compared with the phone keys trusted now; one sealed to a key no longer
#     trusted is dropped - every waiting envelope of turns with it - and the cursor goes back to rewind,
#     so those turns are read again and sealed to the keys trusted now. A waiting receipt sealed to a
#     revoked key is dropped, and that receipt is lost to the other phones (the line still shows from
#     the phone that sent it, and from its founder turn).
#   - A CLEAR (PR 9's open question 1). When the Thrall's session is not the cursor's, the session the
#     cursor is in is located by its id (Find-HordeConversationSource -Session) and read to its end
#     first: the Thrall's last words before the clear are sent before the new session's first. Then the
#     new session is read from its start. Only an old session the port answers ABSENT for (it is gone) is
#     left, and said; one that cannot be found or read just now (unknown) keeps the cursor and is asked
#     again next turn (review of 3d837f0, finding 2), up to clearTries turns in a row, after which it is
#     left, and said, so a transcript that is gone for good cannot stop the chat for ever.
#   - SIZE AND PAGES. A batch is as many envelopes as it needs, each body within the setting pageBytes
#     and what the relay holds (channels/Port.ps1, Get-HordeRelayChannelBodyBudget). A turn longer than a
#     page is never cut: it is split into parts that carry its id, part and parts, and the phone joins
#     them. The JSON is written here with everything past printable ASCII as \u escapes, so a byte of
#     the body is a character and a page is measured exactly.
#   - RATE. A read is at most readTurns turns from at most readBytes of the conversation, and turns are
#     sent at most once every sendIntervalMs: a busy Thrall's lines gather into one batch.
#   - THE PHONE'S MAILBOX HOLDS THE LAST keepEnvelopes OF THIS CHAT, NO MORE (2026-10-13). Nobody acks
#     that mailbox (several phones read it), so every envelope of turns and every receipt this machine
#     ever sent stayed in it for the relay's 30 days, a busy Thrall's day is over a thousand turns
#     (conversations/Port.ps1, THE CEILINGS), and the hosted relay refuses every put to a mailbox that
#     holds 2,000 envelopes. So every put of this channel says to keep, of this machine's chat
#     envelopes, the last keepEnvelopes (channels/Port.ps1, WHAT GOES TO THE PHONE IS TRIMMED BY ITS
#     SENDER): it rides on the put, and costs the relay no request. WHAT THE PHONE SHOWS IS WHAT THE
#     MAILBOX HOLDS - it keeps no chat between sessions - so this is also how far back the chat goes
#     on the phone: 150 envelopes is at least 150 turns and usually several times that (turns written
#     within sendIntervalMs go together), three times what a phone just paired is sent to pick up the
#     thread (startTurns), and at the relay's largest envelope (64 KiB) under half of its 20 MiB a
#     mailbox. A phone paired later is sent its own backfill, sealed to it, as before.
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
#   - EXACTLY ONCE. The messenger's message id is derived from the sender, the phone's message id and
#     the words:
#       id = the first 16 bytes of SHA-256("horde-relay/chat/v1 line id" LF <sender key id> LF <messageId>
#            LF <SHA-256 of the words, hex>), written as a lower-case uuid
#     so a record resumed after a crash, or the phone sending the same line again in a new envelope, is
#     the same post, which an idempotent messenger keeps once - and OTHER words under one message id are
#     another post (review of 3d837f0, finding 1: they were the first post's id, so the Thrall kept the
#     first words while the receipt said the second were delivered). Every receipt carries the words of
#     its own post. A replayed envelope never gets this far: the journal refuses it.
#   - TOO LONG is counted in characters (lineChars, at most 21,000: three UTF-8 bytes a character at
#     the most) and, whatever the setting, in the UTF-8 bytes of the whole body against the messenger
#     port's cap (64 KiB): a line no messenger may take is refused, never retried.
#   - THE SENDER IS NAMED AS VERIFIED (the founder's first live use, 2026-10-11): from.verified says the
#     founder, by the passkey whose key id signed the line, so a messenger that can show it does not
#     present a real founder line as an unknown sender's claim (messengers/Port.ps1, A VERIFIED SENDER).
#   - THE BODY THE THRALL GETS is one header line naming the phone's message id - "FOUNDER LINE from the
#     phone (line <messageId>)" - then a blank line, then his words exactly.
#   - A DELIVERED LINE COMES BACK AS THE FOUNDER'S TURN, and only a real one does (PR 9's open question
#     5, measured 2026-10-10: a line handed over by the fleet messenger's Stop hook is written to the
#     transcript as a meta user line starting "Stop hook feedback:" - 227 of 227 across 193 local
#     transcripts, counted by shape only, and the same in an isolated throwaway session - which the
#     conversation port now hands over as a DELIVERED turn). A delivered turn is shown to the phone as
#     the founder's line, { role founder, line <messageId> }, ONLY when it holds a line header naming a
#     line this machine posted AND the words after the header are, by length and SHA-256, exactly the
#     words of the signed line it posted (kept in the state as id, length and hash - never the words).
#     The Thrall, or anyone, quoting a header shows nothing as the founder's: its own text is not a
#     delivered turn, and a delivered message that copies a header without the very words he signed
#     fails the hash. Every other delivered turn (another session's mail) is not sent to the phone at
#     all. A line whose words the port redacted no longer matches its hash, and is shown from its
#     receipt instead. So the founder's lines stay in the chat after the relay's retention drops the
#     receipts.
#   - THE INBOUND CAP: at most linesPerMinute lines (a setting) are posted to the Thrall in any 60
#     seconds; one past it is held (code too-many) and comes again.
#   - THE RECEIPT. Every line that names a message id gets one back, kind receipt, sealed to every
#     trusted phone key: { messageId, status, code, sentAt, session, text } - status accepted, held or
#     refused, code from the closed list below, and his words, so a phone that reloads (or another phone
#     of his) still shows the line. sentAt is WHEN HE SENT IT (the founder asked for the time of every
#     message, 2026-10-12): the line envelope's own time in milliseconds, which his passkey signed with
#     the rest - the machine's clock is never put in its place, and a record with no such time gives a
#     receipt with no sentAt, which the phone shows with no time. Codes only: the phone shows its own fixed sentence for each (relay/js/
#     protocol.js, CHAT_WORDS), never a word of the relay's or the messenger's.
#       accepted  queued (the messenger took it; the Thrall has NOT yet), delivered (handed over, or seen by
#                 the receiver - the Thrall's own hook confirmed it, Taken.ps1)
#       held      thrall-unknown, no-messenger, not-now, too-many (it comes again), not-delivered,
#                 expired (final)
#       refused   wrong-machine, wrong-horde, empty, too-long, no-thrall, session-ended (final)
#     A held line that comes again says so once per run, not on every turn.
#   done     the messenger answered: handed over or seen by the Thrall's own side (delivered), known not
#            delivered (held for good), or IN THE THRALL'S MAILBOX, NOT YET TAKEN: then the record is
#            done only because the line is now owned by the awaiting list (Taken.ps1, T-0281), which
#            makes it delivered when the Thrall's own hook confirms it and raises an alarm on the
#            phone when it has not within takenAlarmSeconds - "queued" is never the end of the road;
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
. (Join-Path $PSScriptRoot "Photo.ps1")
. (Join-Path $PSScriptRoot "Taken.ps1")
. (Join-Path $PSScriptRoot "Pointer.ps1")
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
    # 150: the header, THE PHONE'S MAILBOX HOLDS THE LAST keepEnvelopes. 1,000 is the ceiling because the
    # hosted relay's mailbox holds 2,000 envelopes for every channel of every machine of the horde.
    @{ name = "keepEnvelopes"; kind = "whole"; default = 150; min = 1; max = 1000; what = "How many of this machine's newest chat envelopes stay in the phone's mailbox; older ones are deleted from the relay, so this is how far back the chat goes on the phone." },
    # 21,000: three bytes a character at the most, and the header, stay inside the messenger port's 64 KiB.
    @{ name = "lineChars"; kind = "whole"; default = 16000; min = 1; max = 21000; what = "The longest line the founder may send to the Thrall, in characters." },
    @{ name = "ttlSeconds"; kind = "whole"; default = 86400; min = 60; max = 604800; what = "How long a line may wait in the Thrall's mailbox, in seconds." },
    # TAKEN (channels/chat/Taken.ps1): a line is delivered only when the Thrall's own side has taken it.
    @{ name = "takenAlarmSeconds"; kind = "whole"; default = 90; min = 10; max = 3600; what = "How long a line the messenger accepted may wait to be taken by the Thrall's own side before the founder's phone is told it was not delivered, in seconds." },
    @{ name = "takenCheckSeconds"; kind = "whole"; default = 10; min = 1; max = 300; what = "How often a line waiting to be taken is asked about before the alarm, in seconds." },
    @{ name = "takenAfterAlarmSeconds"; kind = "whole"; default = 60; min = 5; max = 3600; what = "How often a line already alarmed is asked about, until it is taken or ttlSeconds passes, in seconds." },
    @{ name = "clearTries"; kind = "whole"; default = 60; min = 1; max = 100000; what = "How many turns in a row a session cleared from under the cursor is asked for again, while it cannot be read, before its unread tail is left." },
    @{ name = "linesPerMinute"; kind = "whole"; default = 20; min = 1; max = 600; what = "The most of the founder's lines posted to the Thrall in any 60 seconds; one past it waits." },
    @{ name = "fromLabel"; kind = "label"; default = "F"; what = "The hub label the founder's lines are from: F, unless the person who sends them wears another." },
    # PHOTOS (channels/chat/Photo.ps1). 2 MiB is the coordinator's cap (2026-10-14); the phone makes about 1 MB.
    @{ name = "photoMaxBytes"; kind = "whole"; default = 2097152; min = 65536; max = 2097152; what = "The largest photo the founder may send from the phone, in bytes, after the phone shrinks it." },
    @{ name = "photoWindowSeconds"; kind = "whole"; default = 3600; min = 60; max = 3600; what = "How long after the phone signs a photo its parts may come, in seconds; a photo not whole by then is dropped." },
    @{ name = "photosPerMinute"; kind = "whole"; default = 3; min = 1; max = 30; what = "The most photos taken from the phone in any 60 seconds; one past it waits." },
    # 100 a day: the founder asked for generous budgets (2026-10-14). At 2 MiB a photo is 44 parts and its
    # manifest, so 100 are at most about 8,800 relay requests a day, inside the account's 20,000.
    @{ name = "photosPerDay"; kind = "whole"; default = 100; min = 1; max = 1000; what = "The most photos taken from the phone in any 24 hours; one past it is refused." },
    @{ name = "photoKeepDays"; kind = "whole"; default = 30; min = 1; max = 3650; what = "How many days a photo stays in the photo inbox before it is deleted." },
    @{ name = "photoInbox"; kind = "folder"; default = ""; what = "The folder photos from the phone are saved in, as an absolute path; empty means inbox\photos under Horde's home." }
)
$script:HordeChatChannelLineMembers = @("v", "messageId", "horde", "machine", "session", "text")
$script:HordeChatChannelIdDomain = "horde-relay/chat/v1 line id"
$script:HordeChatChannelFrom = "horde-relay-chat"
$script:HordeChatChannelSessionPattern = '\A[A-Za-z0-9._:-]{1,128}\z'
# A posted line as the state keeps it: its id, the length of his words, and the first 32 hex digits of
# their SHA-256 - enough to know his words again in a delivered turn, never the words themselves.
$script:HordeChatChannelLineMarkPattern = '\A[0-9a-f]{32}:(0|[1-9][0-9]{0,6}):[0-9a-f]{32}\z'
$script:HordeChatChannelLineHeader = '\AFOUNDER LINE from the phone \(line ([0-9a-f]{32})\)\n\n'
# The most bytes of the conversation one Glance looks at (Test-HordeChatChannelGlance): enough to find
# that there is something, which is all it asks; the Tick then reads what there is.
$script:HordeChatChannelGlanceBytes = [long]4096
# The most posted lines the state remembers: a busy day's lines many times over.
$script:HordeChatChannelLinesKept = 2000
$script:HordeChatChannelCodes = @{
    accepted = @("queued", "delivered")
    held = @("thrall-unknown", "no-messenger", "not-now", "too-many", "not-delivered", "expired")
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
    # The durable state: known { cursor; session; phones; pending; lines }, the empty state when there is no file
    # yet, unknown when the file cannot be read or does not hold together - never a guess.
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    $path = Get-HordeChatChannelStatePath -HordeHome $HordeHome
    $empty = [pscustomobject]@{ cursor = $null; session = ""; phones = @(); pending = @(); lines = @(); rewind = $null; awaiting = @() }
    if (-not [System.IO.File]::Exists($path)) { return (New-HordeKnown -Value $empty) }
    try { $bytes = [System.IO.File]::ReadAllBytes($path); Assert-HordeAsciiBytes -Bytes $bytes -What ("the chat state " + $path); $text = [System.Text.Encoding]::ASCII.GetString($bytes) }
    catch { return (New-HordeUnknown -Reason ("the chat state " + $path + " cannot be read: " + $_.Exception.Message)) }
    $why = "the chat state " + $path + " does not hold together"
    if (@(Find-HordeJsonDuplicateKey -Text $text).Count -gt 0) { return (New-HordeUnknown -Reason ($why + ": a member is repeated")) }
    try { $s = ConvertFrom-Json -InputObject $text } catch { return (New-HordeUnknown -Reason ($why + ": it is not JSON")) }
    if ($s -isnot [System.Management.Automation.PSCustomObject]) { return (New-HordeUnknown -Reason ($why + ": it is not an object")) }
    $names = @($s.PSObject.Properties | ForEach-Object { $_.Name }) | Sort-Object
    # awaiting (Taken.ps1) came after the first states: a state without it is read as an empty list.
    if (($names -join ",") -cne "cursor,lines,pending,phones,rewind,session,v" -and ($names -join ",") -cne "awaiting,cursor,lines,pending,phones,rewind,session,v") { return (New-HordeUnknown -Reason ($why + ": its members are " + ($names -join ", "))) }
    if (-not ($s.v -is [int] -or $s.v -is [long]) -or $s.v -ne 1) { return (New-HordeUnknown -Reason ($why + ": it is not version 1")) }
    if ($s.session -isnot [string]) { return (New-HordeUnknown -Reason ($why + ": its session is not text")) }
    foreach ($p in @($s.phones)) { if ($p -isnot [string] -or $p -cnotmatch '\A[0-9a-f]{32}\z') { return (New-HordeUnknown -Reason ($why + ": a phone key is not a key id")) } }
    foreach ($k in @($s.pending)) { if ($k -isnot [string] -or $k.Length -gt 160) { return (New-HordeUnknown -Reason ($why + ": a pending envelope is not a replay key")) } }
    foreach ($l in @($s.lines)) { if ($l -isnot [string] -or $l -cnotmatch $script:HordeChatChannelLineMarkPattern) { return (New-HordeUnknown -Reason ($why + ": a posted line is not an id, a length and a hash")) } }
    $awaiting = @()
    if ($names -ccontains "awaiting") {
        foreach ($a in @($s.awaiting)) { if ($a -isnot [string] -or $a -cnotmatch $script:HordeChatTakenMarkPattern) { return (New-HordeUnknown -Reason ($why + ": a line awaiting the Thrall is not a mark")) } }
        $awaiting = @($s.awaiting)
    }
    if ($null -ne $s.cursor -and $s.cursor -isnot [System.Management.Automation.PSCustomObject]) { return (New-HordeUnknown -Reason ($why + ": its cursor is not an object")) }
    if ($null -ne $s.rewind -and $s.rewind -isnot [System.Management.Automation.PSCustomObject]) { return (New-HordeUnknown -Reason ($why + ": its rewind is not a cursor")) }
    return (New-HordeKnown -Value ([pscustomobject]@{ cursor = $s.cursor; session = $s.session; phones = @($s.phones); pending = @($s.pending); lines = @($s.lines); rewind = $s.rewind; awaiting = $awaiting }))
}

function ConvertTo-HordeChatChannelCursorText {
    # A cursor as the state writes it, or null.
    param($Cursor)
    if ($null -eq $Cursor) { return "null" }
    return ('{"schemaVersion":1,"vendor":' + (ConvertTo-HordeChatChannelJsonString "$($Cursor.vendor)") + ',"session":' + (ConvertTo-HordeChatChannelJsonString "$($Cursor.session)") + ',"position":' + (ConvertTo-HordeChatChannelJsonString "$($Cursor.position)") + '}')
}

function Add-HordeChatChannelPending {
    # Keys recorded and to be put, after those waiting. The first to wait marks rewind: the cursor
    # before them (NEVER PUT TO A KEY REVOKED SINCE IT WAS RECORDED, in the header).
    param($State, [string[]]$Keys, $Before)
    if (@($Keys).Count -eq 0) { return }
    if (@($State.pending).Count -eq 0) { $State.rewind = $Before }
    $State.pending = @(@($State.pending) + @($Keys))
}

function Write-HordeChatChannelState {
    # The durable state, replaced whole in one rename. Throws when it cannot be written.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)]$State)
    $path = Get-HordeChatChannelStatePath -HordeHome $HordeHome
    $dir = [System.IO.Path]::GetDirectoryName($path)
    [void][System.IO.Directory]::CreateDirectory($dir)
    $cursor = ConvertTo-HordeChatChannelCursorText -Cursor $State.cursor
    $rewind = ConvertTo-HordeChatChannelCursorText -Cursor $State.rewind
    $phones = (@($State.phones) | ForEach-Object { '"' + $_ + '"' }) -join ","
    $pending = (@($State.pending) | ForEach-Object { ConvertTo-HordeChatChannelJsonString $_ }) -join ","
    $lines = (@($State.lines) | ForEach-Object { '"' + $_ + '"' }) -join ","
    $awaiting = (@($State.awaiting) | ForEach-Object { '"' + $_ + '"' }) -join ","
    $text = '{"v":1,"cursor":' + $cursor + ',"session":' + (ConvertTo-HordeChatChannelJsonString "$($State.session)") + ',"phones":[' + $phones + '],"pending":[' + $pending + '],"lines":[' + $lines + '],"awaiting":[' + $awaiting + '],"rewind":' + $rewind + '}'
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
    $rw = $(if ($null -eq $State.rewind) { "-" } else { "$($State.rewind.session)|$($State.rewind.position)" })
    return ($cur + "#" + $State.session + "#" + (@($State.phones) -join ",") + "#" + (@($State.pending) -join ",") + "#" + (@($State.lines) -join ",") + "#" + (@($State.awaiting) -join ",") + "#" + $rw)
}

function Get-HordeChatChannelMemory {
    # The channel's memory in this run's context, its durable state read on first use: { ok; reason; mine }.
    param($Context)
    if (-not $Context.state.ContainsKey("chat")) {
        $Context.state["chat"] = @{ loaded = $false; durable = $null; lastSentAt = [datetime]::MinValue; said = @{}; heldSaid = @{}; posted = (New-Object System.Collections.ArrayList); takenChecked = @{} }
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

function Get-HordeChatChannelLineMark {
    # A posted line as the state keeps it (the pattern above).
    param([Parameter(Mandatory = $true)][string]$MessageId, [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    $h = ConvertTo-HordeRelayHex -Bytes (Get-HordeRelaySha256 -Bytes ([System.Text.Encoding]::UTF8.GetBytes($Text)))
    return ($MessageId + ":" + $Text.Length + ":" + $h.Substring(0, 32))
}

function Select-HordeChatChannelShown {
    # The turns the phone is shown, of those read (A DELIVERED LINE COMES BACK AS THE FOUNDER'S TURN):
    # user, assistant and system as they are (a wezfleet pointer or relay line as a marker, no words); a delivered turn as the founder's line when it is one this
    # machine posted, word for word; any other delivered turn not at all.
    param([object[]]$Turns, [string[]]$Lines)
    $byId = @{}
    foreach ($l in @($Lines)) { $p = $l.Split([char]':'); $byId[$p[0]] = [pscustomobject]@{ length = [int]$p[1]; mark = $l } }
    $out = New-Object System.Collections.ArrayList
    foreach ($t in @($Turns)) {
        # A WEZFLEET POINTER OR RELAY LINE IS A MARKER: its time, none of its words (channels/chat/Pointer.ps1).
        if (($t.role -ceq "user" -or $t.role -ceq "delivered") -and (Test-HordeChatPointerLine -Text ([string]$t.text))) {
            $mk = [ordered]@{ role = "marker"; text = ""; turnId = $t.turnId; source = $t.source }
            if ($null -ne $t.PSObject.Properties["time"]) { $mk["time"] = $t.time }
            [void]$out.Add([pscustomobject]$mk)
            continue
        }
        if ($t.role -cne "delivered") { [void]$out.Add($t); continue }
        $text = [string]$t.text
        $at = $text.IndexOf("FOUNDER LINE from the phone (line ", [System.StringComparison]::Ordinal)
        if ($at -lt 0) { continue }
        $m = [regex]::Match($text.Substring($at), $script:HordeChatChannelLineHeader)
        if (-not $m.Success -or -not $byId.ContainsKey($m.Groups[1].Value)) { continue }
        $known = $byId[$m.Groups[1].Value]
        $start = $at + $m.Length
        if ($text.Length - $start -lt $known.length) { continue }
        $words = $text.Substring($start, $known.length)
        $rest = $text.Substring($start + $known.length)
        # What may follow his words is the messenger's own: nothing, or its next line.
        if ($rest -ne "" -and -not $rest.StartsWith("`n")) { continue }
        if ((Get-HordeChatChannelLineMark -MessageId $m.Groups[1].Value -Text $words) -cne $known.mark) { continue }
        $f = [ordered]@{ role = "founder"; text = $words; turnId = $t.turnId; line = $m.Groups[1].Value; source = $t.source }
        if ($null -ne $t.PSObject.Properties["time"]) { $f["time"] = $t.time }
        [void]$out.Add([pscustomobject]$f)
    }
    return @($out.ToArray())
}

function Read-HordeChatChannelTail {
    # The last -Keep turns of -Source from -Cursor to its end, and the cursor at the end: known { turns;
    # next }, or the port's unknown. Every read is bounded; a conversation longer than 10,000 reads is
    # not one (10 million turns at the most a read may give).
    param($Source, $Cursor, [int]$Keep, $Settings, [string[]]$Lines = @())
    $queue = New-Object System.Collections.Generic.Queue[object]
    $at = $Cursor
    for ($i = 0; $i -lt 10000; $i++) {
        $r = Read-HordeConversationTurns -Source $Source -Cursor $at -MaxTurns ([int]$Settings.readTurns) -MaxBytes ([long]$Settings.readBytes)
        if ($r.state -cne "known") { return $r }
        foreach ($t in @(Select-HordeChatChannelShown -Turns @($r.value.turns) -Lines $Lines)) { $queue.Enqueue($t); if ($queue.Count -gt $Keep) { [void]$queue.Dequeue() } }
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
    if ($null -ne $Turn.PSObject.Properties["line"]) { $head += ',"line":"' + $Turn.line + '"' }
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
    param($Context, [string]$Session, [bool]$Backfill, [object[]]$Turns, [long]$Budget, [long]$PhotoBytes = 0, [long]$PhotoWindowMs = 0)
    # photoBytes: this machine takes photos up to that many bytes (Photo.ps1). A phone offers its picture
    # button only to a machine that says so; a phone older than the member reads past it.
    # photoWindowMs: the longest window a photo may name (photoWindowSeconds): the phone asks for no more.
    $front = '{"v":1,"kind":"chat-turns","horde":"' + $Context.horde + '","machine":"' + $Context.signKeyId + '","session":' + (ConvertTo-HordeChatChannelJsonString $Session) + ',"backfill":' + $(if ($Backfill) { "true" } else { "false" }) + $(if ($PhotoBytes -gt 0) { ',"photoBytes":' + $PhotoBytes + $(if ($PhotoWindowMs -gt 0) { ',"photoWindowMs":' + $PhotoWindowMs } else { '' }) } else { '' }) + ',"turns":['
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
    $trusted = $null
    # How many envelopes stay (the header, THE PHONE'S MAILBOX HOLDS THE LAST keepEnvelopes): the
    # setting as the Tick last read it, and its declared default for a put made before any Tick.
    $keep = [long]@($script:HordeChatChannelSettings.settings | Where-Object { $_.name -ceq "keepEnvelopes" })[0].default
    if ($Mine.ContainsKey("keepEnvelopes")) { $keep = [long]$Mine["keepEnvelopes"] }
    while (@($Mine.durable.pending).Count -gt 0) {
        $key = @($Mine.durable.pending)[0]
        $rec = Test-HordeRelayJournalSent -Key $key -HordeHome $homeDir
        if ($rec.state -cne "known") { return ("the journal cannot give back " + $key + ": " + $rec.reason) }
        if ($rec.value.sent) {
            if ($null -eq $trusted) {
                $now = Get-HordeChatChannelPhones -Context $Context
                if ($now.state -cne "known") { return ("the phone keys trusted now cannot be read, so nothing is put: " + $now.reason) }
                $trusted = @($now.value | ForEach-Object { $_.agreeKeyId })
            }
            $to = @((Read-HordeRelayEnvelope -Text $rec.value.text).value.header.to)
            if (@($to | Where-Object { $trusted -cnotcontains $_ }).Count -gt 0) {
                if ($rec.value.kind -ceq "turns") {
                    # Every waiting envelope of turns goes, and the turns are read again from rewind.
                    $keep = New-Object System.Collections.ArrayList
                    foreach ($k in @($Mine.durable.pending)) {
                        $kr = Test-HordeRelayJournalSent -Key $k -HordeHome $homeDir
                        if ($kr.state -ceq "known" -and $kr.value.sent -and $kr.value.kind -ceq "turns") { continue }
                        [void]$keep.Add($k)
                    }
                    $Mine.durable.pending = @($keep.ToArray())
                    $Mine.durable.cursor = $Mine.durable.rewind
                }
                else { $Mine.durable.pending = @(@($Mine.durable.pending) | Select-Object -Skip 1) }
                if (@($Mine.durable.pending).Count -eq 0) { $Mine.durable.rewind = $null }
                try { Write-HordeChatChannelState -HordeHome $homeDir -State $Mine.durable } catch { return ("the chat state could not be written: " + $_.Exception.Message) }
                continue
            }
            $put = Send-HordeRelayChannelSaved -Context $Context -Saved ([pscustomobject]@{ key = $key; text = $rec.value.text }) -Mailbox $mailbox -KeepFrom (Get-HordeRelayChannelKeepFrom -Key $key -Keep $keep)
            if ($put.state -cne "known") { return $put.reason }
        }
        # A key the journal does not hold was never recorded (a state written by hand): nothing to put.
        $Mine.durable.pending = @(@($Mine.durable.pending) | Select-Object -Skip 1)
        if (@($Mine.durable.pending).Count -eq 0) { $Mine.durable.rewind = $null }
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
    # OUT: the Thrall's turns (Invoke-HordeChatChannelTurnsTick), then the photos from the phone that are
    # whole, waiting or out of time (Photo.ps1, Invoke-HordeChatPhotoTick). { lines; failed }.
    param($Context)
    $t = Invoke-HordeChatChannelTurnsTick -Context $Context
    $m = Get-HordeChatChannelMemory -Context $Context
    if (-not $m.ok) { return $t }
    $set = Get-HordeChatChannelSettings -Context $Context
    if ($set.state -cne "known") { return $t }
    # THE LINES WAITING TO BE TAKEN (Taken.ps1): asked about, delivered or alarmed.
    $taken = [pscustomobject]@{ lines = @(); failed = $false }
    try { $taken = Invoke-HordeChatTakenTick -Context $Context -Mine $m.mine -Settings $set.value }
    catch { $taken = [pscustomobject]@{ lines = @("lines awaiting the Thrall failed: " + $_.Exception.Message); failed = $true } }
    $photo = @()
    try { $photo = @(Invoke-HordeChatPhotoTick -Context $Context -Mine $m.mine -Settings $set.value) }
    catch { $photo = @("photos failed: " + $_.Exception.Message) }
    if ($photo.Count -eq 0 -and @($taken.lines).Count -eq 0) { return $t }
    return [pscustomobject]@{ lines = @(@($t.lines) + @($taken.lines) + $photo); failed = ([bool]$t.failed -or [bool]$taken.failed) }
}

function Invoke-HordeChatChannelTurnsTick {
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
    # For the Glance, which reads no settings itself: how long this Tick leaves between two sends.
    $mine["sendIntervalMs"] = [long]$set.sendIntervalMs
    # For every put of this run, a receipt's too: how many envelopes stay in the phone's mailbox.
    $mine["keepEnvelopes"] = [long]$set.keepEnvelopes
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
    # For the Glance, which locates nothing itself: the Thrall as this Tick found it.
    $mine["source"] = $source
    $d = $mine.durable
    $was = Get-HordeChatChannelStateMark -State $d
    $batches = New-Object System.Collections.ArrayList
    $notes = New-Object System.Collections.ArrayList
    $known = @($all | ForEach-Object { $_.agreeKeyId })
    $cursor = $d.cursor
    if ($null -eq $cursor) {
        # THE FIRST LOOK: from the end, for every key there is.
        $tail = Read-HordeChatChannelTail -Source $source -Cursor $null -Settings $set -Keep ([int]$set.startTurns) -Lines @($d.lines)
        if ($tail.state -cne "known") { return (& $once "read" ("no turns sent: the Thrall's conversation could not be read: " + $tail.reason) $false) }
        [void]$batches.Add([pscustomobject]@{ phones = $all; backfill = $true; turns = @($tail.value.turns) })
        $next = $tail.value.next
    } else {
        $fresh = @($all | Where-Object { @($d.phones) -cnotcontains $_.agreeKeyId })
        if ($fresh.Count -gt 0) {
            # A KEY TRUSTED SINCE: the last startTurns turns of the session now, to it alone.
            $tail = Read-HordeChatChannelTail -Source $source -Cursor $null -Keep ([int]$set.startTurns) -Settings $set -Lines @($d.lines)
            if ($tail.state -cne "known") { return (& $once "read" ("no turns sent: the Thrall's conversation could not be read: " + $tail.reason) $false) }
            [void]$batches.Add([pscustomobject]@{ phones = $fresh; backfill = $true; turns = @($tail.value.turns) })
        }
        if ("$($cursor.session)" -cne $source.session) {
            # A CLEAR: the old session read to its end first.
            $old = Find-HordeChatChannelSource -Context $Context -Session "$($cursor.session)"
            $next = New-HordeConversationCursor -Vendor $source.vendor -Session $source.session -Position ""
            $r = $null
            if ($old.state -ceq "known") { $r = Read-HordeConversationTurns -Source $old.value -Cursor $cursor -MaxTurns ([int]$set.readTurns) -MaxBytes ([long]$set.readBytes) }
            $why = $(if ($old.state -ceq "unknown") { $old.reason } elseif ($null -ne $r -and $r.state -cne "known") { $r.reason } else { "" })
            if ($why -ne "") {
                if (-not $mine.ContainsKey("clearTries")) { $mine["clearTries"] = 0 }
                $mine["clearTries"]++
                if ($mine["clearTries"] -lt [int]$set.clearTries) { return (& $once "read" ("no turns sent: the Thrall's session before the clear cannot be read now, and is asked again: " + $why) $false) }
                [void]$notes.Add("the Thrall's session before the clear could not be read in " + $set.clearTries + " tries, and its unread tail is left: " + $why)
                $r = $null
            }
            $mine["clearTries"] = 0
            if ($old.state -ceq "known" -and $null -ne $r) {
                if ($r.state -ceq "known") {
                    $shown = @(Select-HordeChatChannelShown -Turns @($r.value.turns) -Lines @($d.lines))
                    if ($shown.Count -gt 0) { [void]$batches.Add([pscustomobject]@{ phones = $all; backfill = $false; turns = $shown }) }
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
            $shown = @(Select-HordeChatChannelShown -Turns @($r.value.turns) -Lines @($d.lines))
            if ($shown.Count -gt 0) { [void]$batches.Add([pscustomobject]@{ phones = $all; backfill = $false; turns = $shown }) }
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
        $bodies = New-HordeChatChannelPages -Context $Context -Session $source.session -Backfill $b.backfill -Turns @($b.turns) -Budget $budget -PhotoBytes $(if ((Get-HordeChatPhotoRuntimeRefusal) -ceq "") { [long]$set.photoMaxBytes } else { [long]0 }) -PhotoWindowMs ([long]$set.photoWindowSeconds * 1000)
        $saved = Save-HordeChatChannelBodies -Context $Context -Kind "turns" -Bodies $bodies -Phones @($b.phones)
        foreach ($k in $saved.keys) { [void]$keys.Add($k) }
        if (-not $saved.ok) {
            # What was recorded is kept to be put; the cursor stays, so the rest is read again.
            Add-HordeChatChannelPending -State $d -Keys @($keys.ToArray()) -Before $d.cursor
            try { Write-HordeChatChannelState -HordeHome $homeDir -State $d } catch { }
            return [pscustomobject]@{ lines = @("turns not sent: " + $saved.reason); failed = $true }
        }
        $count += @($b.turns).Count
    }
    Add-HordeChatChannelPending -State $d -Keys @($keys.ToArray()) -Before $d.cursor
    $d.cursor = $next
    $d.session = $source.session
    $d.phones = $known
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

function Test-HordeChatChannelGlance {
    # THE GLANCE (channels/Port.ps1, Glance): has the Thrall's conversation moved past the cursor? $true
    # then, and the runner runs the Tick now instead of when its watch of the mailbox ends - so the
    # Thrall's reply to the founder's line is on his phone in about a second and not in up to a minute.
    #   - A FEW BYTES PAST THE CURSOR ARE READ, FROM THE THRALL THE LAST TICK FOUND: one turn at the most
    #     from at most 4,096 bytes, through the conversation port like every read, and nothing is kept
    #     or moved - the cursor is the Tick's. ANYTHING there is a yes: a turn, more than the bytes
    #     looked at, a position that moved (lines that are not turns: the Tick then moves the cursor past
    #     them and sends nothing, so they are not looked at again). The three channels' Glances together
    #     are about 6 ms a round on this box (measured 2026-10-13; test/test-relay-run-send.ps1 prints it).
    #   - THE THRALL IS NOT LOCATED AGAIN. Locating reads every session record of the fleet, and the
    #     trust store is not read either: both are the Tick's, once a turn. So a session cleared since,
    #     and a phone key trusted since, are NOT seen here and wait for the turn's own Tick, as they
    #     always did. (A cleared session's old conversation stops growing, so the answer is a quiet no.)
    #   - NO, UNTIL A TICK HAS FOUND THE THRALL AND SENT ITS FIRST LOOK; NO WHILE AN ENVELOPE IS RECORDED
    #     AND WAITING (the relay would not take it: putting it again is the turn's Tick's, after the
    #     runner's backoff); NO INSIDE sendIntervalMs OF THE LAST SEND (the Tick would send nothing: RATE,
    #     in the header); NO WHEN THE CONVERSATION CANNOT BE READ (the turn's Tick says why).
    param($Context)
    if (-not $Context.state.ContainsKey("chat")) { return $false }
    $mine = $Context.state["chat"]
    # A LINE WAITING TO BE TAKEN THAT IS DUE TO BE ASKED ABOUT is a yes (Taken.ps1): the Tick asks, there
    # and then, and the alarm is not held back until the watch ends. Local only: a mark and a clock.
    if ($mine.loaded -and (Test-HordeChatTakenDue -Mine $mine)) { return $true }
    if (-not $mine.loaded -or -not $mine.ContainsKey("source") -or $null -eq $mine["source"]) { return $false }
    $d = $mine.durable
    if ($null -eq $d.cursor -or @($d.pending).Count -gt 0) { return $false }
    if ("$($d.cursor.session)" -cne $mine["source"].session) { return $false }
    if (([datetime]::UtcNow - $mine.lastSentAt).TotalMilliseconds -lt [long]$mine["sendIntervalMs"]) { return $false }
    $r = Read-HordeConversationTurns -Source $mine["source"] -Cursor $d.cursor -MaxTurns 1 -MaxBytes $script:HordeChatChannelGlanceBytes
    if ($r.state -cne "known") { return $false }
    return (@($r.value.turns).Count -gt 0 -or $r.value.more -or $r.value.reset -cne "none" -or "$($r.value.next.position)" -cne "$($d.cursor.position)")
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
    param([Parameter(Mandatory = $true)][string]$From, [Parameter(Mandatory = $true)][string]$MessageId, [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    $words = ConvertTo-HordeRelayHex -Bytes (Get-HordeRelaySha256 -Bytes ([System.Text.Encoding]::UTF8.GetBytes($Text)))
    $h = ConvertTo-HordeRelayHex -Bytes (Get-HordeRelaySha256 -Bytes (Get-HordeRelayAsciiBytes -Text ($script:HordeChatChannelIdDomain + "`n" + $From + "`n" + $MessageId + "`n" + $words)))
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
    param($Context, $Mine, [string]$MessageId, [string]$Status, [string]$Code, [string]$Session, [string]$Text, [long]$SentAt = 0)
    if ($script:HordeChatChannelCodes[$Status] -cnotcontains $Code) { throw ("'" + $Code + "' is not a " + $Status + " code") }
    $phones = Get-HordeChatChannelPhones -Context $Context
    if ($phones.state -cne "known") { return ("no receipt: " + $phones.reason) }
    if (@($phones.value).Count -eq 0) { return "no receipt: no phone identity key is trusted" }
    $body = '{"v":1,"kind":"chat-receipt","horde":"' + $Context.horde + '","machine":"' + $Context.signKeyId + '","session":' + (ConvertTo-HordeChatChannelJsonString $Session) + ',"messageId":"' + $MessageId + '","status":"' + $Status + '","code":"' + $Code + '"' + $(if ($SentAt -gt 0) { ',"sentAt":' + $SentAt } else { '' }) + ',"text":' + (ConvertTo-HordeChatChannelJsonString $Text) + '}'
    $saved = Save-HordeChatChannelBodies -Context $Context -Kind "receipt" -Bodies @($body) -Phones @($phones.value)
    if (-not $saved.ok) { return ("no receipt: " + $saved.reason) }
    Add-HordeChatChannelPending -State $Mine.durable -Keys @($saved.keys) -Before $Mine.durable.cursor
    try { Write-HordeChatChannelState -HordeHome (Get-HordeChatChannelHome $Context) -State $Mine.durable } catch { }
    return (Send-HordeChatChannelPending -Context $Context -Mine $Mine)
}

function Invoke-HordeChatChannelAccept {
    # One opened line, to the Thrall (IN, in the header), or one photo's manifest (Photo.ps1). { outcome;
    # reason }.
    param($Context, $Item)
    if ("$($Item.kind)" -ceq "photo") { return (Invoke-HordeChatPhotoAccept -Context $Context -Item $Item) }
    $r = Read-HordeChatChannelLine -Body $Item.body
    if (-not $r.ok) { return [pscustomobject]@{ outcome = "refused"; reason = $r.reason } }
    $line = $r.value
    $m = Get-HordeChatChannelMemory -Context $Context
    if (-not $m.ok) { return [pscustomobject]@{ outcome = "retry"; reason = ("the chat state cannot be read: " + $m.reason) } }
    $mine = $m.mine
    # WHEN HE SENT IT: the line envelope's own time, which his passkey signed. An item that carries none
    # (a record handed over by older code) gives a receipt with no time, never a guessed one.
    $sentAt = [long]0
    $signedAt = $Item.PSObject.Properties["ts"]
    if ($null -ne $signedAt -and [long]$signedAt.Value -gt 0) { $sentAt = [long]$signedAt.Value }
    $answer = {
        param([string]$Outcome, [string]$Status, [string]$Code, [string]$Why, [string]$Session)
        $note = ""
        $heldKey = $line.messageId + "/" + $Code
        if ($Status -cne "held" -or -not $mine.heldSaid.ContainsKey($heldKey)) {
            if ($Status -ceq "held") { $mine.heldSaid[$heldKey] = $true }
            $sent = Send-HordeChatChannelReceipt -Context $Context -Mine $mine -MessageId $line.messageId -Status $Status -Code $Code -Session $Session -Text $line.text -SentAt $sentAt
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
    $bodyBytes = [System.Text.Encoding]::UTF8.GetByteCount((Get-HordeChatChannelThrallBody -MessageId $line.messageId -Text $line.text))
    if ($bodyBytes -gt $script:HordeMessengerBodyBytes) { return (& $answer "refused" "refused" "too-long" ("its message is " + $bodyBytes + " UTF-8 bytes; a message holds " + $script:HordeMessengerBodyBytes) $line.session) }
    $src = Find-HordeChatChannelSource -Context $Context
    if ($src.state -ceq "absent") { return (& $answer "refused" "refused" "no-thrall" "no Thrall of this horde is found on this machine" $line.session) }
    if ($src.state -cne "known") { return (& $answer "retry" "held" "thrall-unknown" ("the Thrall cannot be found now: " + $src.reason) $line.session) }
    if ($src.value.session -cne $line.session) { return (& $answer "refused" "refused" "session-ended" ("it was written to the session " + $line.session + ", and the Thrall's session is now " + $src.value.session) $src.value.session) }
    $now = [datetime]::UtcNow
    while ($mine.posted.Count -gt 0 -and ($now - [datetime]$mine.posted[0]).TotalSeconds -ge 60) { $mine.posted.RemoveAt(0) }
    if ($mine.posted.Count -ge [int]$set.linesPerMinute) { return (& $answer "retry" "held" "too-many" ("" + $mine.posted.Count + " lines were posted in the last minute; a minute holds " + $set.linesPerMinute) $line.session) }
    $messenger = Find-HordeChatChannelMessenger
    if ($messenger.state -cne "known") { return (& $answer "retry" "held" "no-messenger" $messenger.reason $line.session) }
    $deviceId = ""
    try { $deviceId = Get-HordeDeviceId -HomeRoot (Get-HordeChatChannelHome $Context) } catch { return (& $answer "retry" "held" "not-now" ("this machine's device id could not be had: " + $_.Exception.Message) $line.session) }
    $message = [pscustomobject]@{
        messageId = (Get-HordeChatChannelMessageId -From $Item.from -MessageId $line.messageId -Text $line.text); sessionId = $src.value.session
        # VERIFIED: this Accept runs only for a line the relay verified as signed by a passkey the trust
        # store holds as the founder's (senders founder, channels/Port.ps1's gate), so it says so, by that
        # passkey's key id (messengers/Port.ps1, A VERIFIED SENDER).
        from = [pscustomobject]@{ deviceId = $deviceId; sessionId = $script:HordeChatChannelFrom; label = $set.fromLabel; verified = [pscustomobject]@{ kind = "founder"; by = "passkey"; keyId = $Item.from } }
        body = (Get-HordeChatChannelThrallBody -MessageId $line.messageId -Text $line.text); ttlSeconds = [int]$set.ttlSeconds
    }
    $posted = Send-HordeMessengerMessage -Messenger $messenger.value -Message $message
    if ($posted.state -cne "known") { return (& $answer "retry" "held" "not-now" ("messenger " + $messenger.value.name + " did not take it now: " + $posted.reason) $line.session) }
    [void]$mine.posted.Add($now)
    # His words, as id, length and hash, so the line is known again when it comes back as a turn.
    $mark = Get-HordeChatChannelLineMark -MessageId $line.messageId -Text $line.text
    if (@($mine.durable.lines) -cnotcontains $mark) {
        $mine.durable.lines = @(@($mine.durable.lines) + @($mark) | Select-Object -Last $script:HordeChatChannelLinesKept)
        try { Write-HordeChatChannelState -HordeHome (Get-HordeChatChannelHome $Context) -State $mine.durable } catch { }
    }
    # WOKEN, OR ONLY QUEUED: the messenger's own word on its knock, said in the line (messengers/Port.ps1,
    # THE WAKE WORD). A line in the mailbox of a Thrall nobody woke is read only at its next turn.
    $wake = Format-HordeMessengerWake -Answer $posted
    if ($wake -cne "") { $wake = "; " + $wake }
    switch ("$($posted.value.stage)") {
        "accepted" {
            # IN THE MAILBOX, NOT YET TAKEN (channels/chat/Taken.ps1): the line is owned by the awaiting list
            # from here, written BEFORE the record is marked done, and is delivered only when the Thrall's
            # own side says so. A list that cannot be written holds the record: it comes again, and the
            # same post (the same id) is kept once by the messenger.
            $wp = $posted.value.PSObject.Properties["woken"]
            $entry = [pscustomobject]@{ messageId = $line.messageId; messengerId = $message.messageId; postedMs = (Get-HordeChatTakenNowMs); from = "$($Item.from)"; seq = [long]$Item.seq; alarmed = $false; woken = ($null -ne $wp -and $wp.Value -eq $true); session = "$($line.session)" }
            $awaitedBefore = @($mine.durable.awaiting)
            $already = Get-HordeChatTakenEntry -State $mine.durable -MessageId $line.messageId
            $overflow = @(Get-HordeChatTakenOverflow -State $mine.durable)
            if ($null -ne $already -and $already.alarmed) {
                # ALREADY AWAITED AND ALARMED (a restart, a re-signed duplicate): its alarm stands, and a
                # queued receipt now would cover it on the phone (the newest receipt wins) and no alarm
                # would come again. Nothing is sent; the line stays awaited with its own clock.
                return [pscustomobject]@{ outcome = "done"; reason = ("line " + $line.messageId + ": already awaited and alarmed - no receipt sent over the alarm") }
            }
            $gaveUp = @()
            if ($null -eq $already) {
                # PAST THE LIST'S SIZE the oldest leave it: never in silence, and the phone is told BEFORE the
                # state write that drops them (a crash in between leaves them listed and told, never gone and
                # unannounced; the record comes again and tells them again, which the phone shows once).
                $told = @(foreach ($old in $overflow) { Send-HordeChatTakenGiveUp -Context $Context -Mine $mine -Entry $old -Why "the awaiting list is full" })
                $gaveUp = @($told | ForEach-Object { $_.line })
                # An entry whose phone could not be told stays listed: nothing is evicted, and this record comes
                # again (the same post is kept once by the messenger) when the phone can be told.
                if (@($told | Where-Object { -not $_.sent }).Count -gt 0) {
                    return (& $answer "retry" "held" "not-now" ("the oldest awaiting line cannot be given up now, so this one is not yet awaited: " + ($gaveUp -join " | ")) $line.session)
                }
            }
            if (Add-HordeChatTaken -State $mine.durable -Entry $entry) {
                $mine.takenChecked[$line.messageId] = (Get-HordeChatTakenNowMs)
                try { Write-HordeChatChannelState -HordeHome (Get-HordeChatChannelHome $Context) -State $mine.durable }
                catch {
                    # Not on disk, so not in memory either: the record comes again and adds it again.
                    $mine.durable.awaiting = $awaitedBefore
                    return (& $answer "retry" "held" "not-now" ("the chat state could not be written, so the line is not yet awaited: " + $_.Exception.Message) $line.session)
                }
            }
            $queued = & $answer "done" "accepted" "queued" ("messenger " + $messenger.value.name + " took it for the Thrall" + $wake + "; awaiting the Thrall's own side (TAKEN)") $line.session
            if ($gaveUp.Count -gt 0) { $queued.reason = $queued.reason + " | " + ($gaveUp -join " | ") }
            return $queued
        }
        "held" { return (& $answer "done" "held" "not-delivered" ("messenger " + $messenger.value.name + " holds it, not delivered") $line.session) }
        "expired" { return (& $answer "done" "held" "expired" ("messenger " + $messenger.value.name + " gave it up undelivered") $line.session) }
        default { return (& $answer "done" "accepted" "delivered" ("messenger " + $messenger.value.name + " handed it to the Thrall (" + $posted.value.stage + ")") $line.session) }
    }
}

$null = Register-HordeRelayChannel -Folder $script:HordeChatChannelFolder -Name "chat" -Kinds @("line", "photo") -Senders "founder" `
    -Accept { param($Context, $Item) return (Invoke-HordeChatChannelAccept -Context $Context -Item $Item) } `
    -Tick { param($Context) return (Invoke-HordeChatChannelTick -Context $Context) } `
    -Glance { param($Context) return (Test-HordeChatChannelGlance -Context $Context) }
# A PHOTO'S PARTS are a data kind (channels/Port.ps1, DATA KINDS): unsigned, never an envelope, handed to
# Photo.ps1's sink alone, which can make them nothing but bytes vouched for by a signed manifest.
$null = Register-HordeRelayDataKind -Folder $script:HordeChatChannelFolder -Name "photo-part" -Channel "chat" `
    -Take { param($Context, $Text) return (Receive-HordeChatPhotoPart -Context $Context -Text $Text) }
