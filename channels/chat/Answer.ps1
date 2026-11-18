# channels/chat/Answer.ps1 - the founder's ANSWER TO AN ITEM OF A PUBLISHED LIST, from his phone to the Orc that owns the list
# (task T-0352, the founder's, 2026-10-23: "since the published lists came to the phone I cannot type an answer to any of them").
#
# THE CAUSE. The decisions page drew each published item as text (surfaces/pwa/page/published-lists.js) and nothing more. Answers
# existed only for the questions of the decisions store, keyed by question NUMBER (channels/decisions, kind answer), and most
# published items carry no question number: of the Thrall's 13 only one linked a question, and Orcs A, C, D, F, L and Q likewise.
# There was nothing to answer them by. An item needs its own way in, and this is it.
#
# IT RIDES THE CHAT CHANNEL, as a kind of its own, because the chat is the founder's one path that already has everything a
# signed command to a session needs: his passkey (or its unlocked session), the exactly-once post through the messenger port, the
# awaiting list that makes DELIVERED mean the receiving session's own hook took it (Taken.ps1), and receipts back to every trusted
# phone key that carry his words. Nothing of it is written again here: the marks, the clock of the alarm and the decision of what
# a messenger's stage means are Taken.ps1's, used as they are.
#
# IN (the Accept), kind answer, from the founder's TRUSTED passkeys only (the channel's senders gate, channels/Port.ps1): an
# envelope signed over the sealed body, which binds it to the horde and this machine and names the list and the item:
#   {"v":1,"messageId":"<32 hex>","horde":"<horde>","machine":"<32 hex>","lane":"<thrall or an Orc's letter>",
#    "snapshot":"<the list's id, 26 characters>","index":<the item's 1-based place in that list>,"text":"..."}
# read strictly - no member repeated, none missing, none added. A recipient is NOT a member: the phone never names one.
#   - THE ITEM IS FOUND AT THE MACHINE, in fleet.db, read-only (fleet-db/decisions-cli.mjs published-item): the snapshot is looked
#     up among ALL the lists ever published, live or archived, so an answer to an item of a list since replaced still reaches
#     the Orc that published it. A snapshot or an index that never existed is refused (no-such-item), and a lane that is not the
#     snapshot's own is refused (wrong-lane): the lane is the phone's claim and is checked against the list, never trusted.
#   - THE RECIPIENT IS RESOLVED ON THE MACHINE from the list's owner, never from the body: the Thrall's list goes to the session
#     that holds the Thrall's seat (role warchief), an Orc's to the session whose record wears the Orc's letter with the role orc
#     (core/SessionSeat.ps1, the seats the decisions router uses, decisions/Route.ps1). A seat that is not there is HELD with a
#     code (no-session) and the record comes again; an Orc retired in fleet.db is refused (orc-retired). It is never sent to
#     another seat, never to the Thrall in its place, and never dropped.
#   - DELIVERY is through the messenger port by capabilities, exactly as a chat line is (Find-HordeChatChannelMessenger): the
#     body the Orc reads is
#       FOUNDER ANSWER from the phone (answer <messageId>) to your published list item <index> (snapshot <id>):
#       "<the item's text, as published>"
#
#       <his words exactly>
#     from.verified names the founder by the passkey whose key id signed it (messengers/Port.ps1, A VERIFIED SENDER).
#   - EXACTLY ONCE. The messenger's message id is derived from the sender, the phone's message id, his words, the snapshot and the
#     index (Get-HordeChatAnswerMessageId), so a record resumed after a crash, or the phone sending the same answer (under the same message id, which the page keeps until the send is taken) again in a new
#     envelope, is the same post, which an idempotent messenger keeps once; other words, or another item, under one message id are
#     another post. A replayed envelope never gets this far: the journal refuses it.
#   - TOO LONG is counted as the chat line is (lineChars, and the messenger port's 64 KiB for the whole body).
#
# THE RECEIPT. Every answer that names a message id gets one back, kind answer-receipt, sealed to every trusted phone key:
#   {"v":1,"kind":"chat-answer-receipt","horde","machine","messageId","lane","snapshot","index","status","code","sentAt","text"}
# with HIS WORDS in it, so a phone that reloads (or another phone of his) still shows the answer under its item. Codes only: the
# phone shows its own fixed sentence for each (relay/js/protocol.js, ITEM_ANSWER_WORDS), never a word of the relay's or the
# messenger's. The receipts go into the same phone mailbox, as the same kind of envelope, as a photo's (Photo.ps1), and the chat
# keeps the last keepEnvelopes of them with the rest; the phone does not show them in the chat.
#   accepted  queued     the messenger took it: it is in the Orc's mailbox and the Orc has NOT yet taken it      ("Sent")
#             delivered  handed over, or seen by the receiver - the Orc's own hook confirmed it                  ("Delivered")
#   held      no-session (the Orc has no session now; it comes again), not-now (it comes again), not-delivered
#             (final: the messenger holds it for good), expired (final)
#   refused   wrong-machine, wrong-horde, empty, too-long, no-such-item, wrong-lane, orc-retired (all final)
#
# DELIVERED IS TAKEN, FOR ANY SESSION. The messenger port's status is asked by the messenger's own id for the post, whatever session
# it was posted to (messengers/Port.ps1, Get-HordeMessengerStatus), so the awaiting list of Taken.ps1 serves an Orc's session as it
# serves the Thrall's: an answer the messenger accepted is awaited (answers.json, beside the chat's state, in the same marks),
# is delivered when the stage is handed-over or seen, is told held/not-now ONCE when it is not taken in takenAlarmSeconds, and is
# given up held/expired after ttlSeconds - never dropped in silence. The list is this file's own, not the chat state's: that file
# is read strictly by its members and by the channel's other code, and a second list in it would be a change to them.
#
# THE SEAM FOR A SUITE: Set-HordeChatAnswerSeat takes the reader of seats and Set-HordeChatAnswerItemReader the reader of items,
# as the decisions router and channel take theirs; $null, as everywhere but in a suite, means the real ones.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\SessionSeat.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "decisions\Publish.ps1")

$script:HordeChatAnswerMembers = @("v", "messageId", "horde", "machine", "lane", "snapshot", "index", "text")
$script:HordeChatAnswerIdDomain = "horde-relay/chat/v1 answer id"
$script:HordeChatAnswerLanePattern = '\A(thrall|[A-Z][A-Z0-9]{0,3})\z'
$script:HordeChatAnswerSnapshotPattern = '\A[0-9A-HJKMNP-TV-Z]{26}\z'
$script:HordeChatAnswerMostIndex = 100000
$script:HordeChatAnswerCodes = @{
    accepted = @("queued", "delivered")
    held = @("no-session", "not-now", "not-delivered", "expired")
    refused = @("wrong-machine", "wrong-horde", "empty", "too-long", "no-such-item", "wrong-lane", "orc-retired")
}
# The most answers awaited at once: far more than a day of them; the oldest past it are given up on WITH a receipt.
$script:HordeChatAnswerKept = 200
# The most answers the fleet is asked about in one Tick (each ask is a process), the longest-unasked first.
$script:HordeChatAnswerAsksPerTick = 10
# For a suite only: a reader of seats (param($Role, $Label) -> core/Tristate.ps1 answer with known { sessionId }) and a reader of
# items (param($Snapshot, $Position, $HordeHome) -> { code; out; err } as Invoke-HordeDecisionNode answers).
$script:HordeChatAnswerSeat = $null
$script:HordeChatAnswerItemReader = $null

# For a suite only: the real clock, in milliseconds since 1970, that the age limit reads (0 means the real one).
$script:HordeChatAnswerClockMs = [long]0
function Set-HordeChatAnswerClock { param([long]$Ms = 0) $script:HordeChatAnswerClockMs = $Ms }
function Get-HordeChatAnswerNowMs {
    if ($script:HordeChatAnswerClockMs -gt 0) { return $script:HordeChatAnswerClockMs }
    return [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
}
function Set-HordeChatAnswerSeat { param([scriptblock]$Reader = $null) $script:HordeChatAnswerSeat = $Reader }
function Set-HordeChatAnswerItemReader { param([scriptblock]$Reader = $null) $script:HordeChatAnswerItemReader = $Reader }

function Get-HordeChatAnswerLedgerPath {
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    return [System.IO.Path]::Combine($HordeHome, "relay", "chat", "answers.json")
}

function Read-HordeChatAnswerLedger {
    # The awaiting list of answers: known { awaiting }, the empty list when there is no file yet, unknown when the file cannot be
    # read or does not hold together - never a guess, and never quietly started over. (Taken.ps1 reads any such file.)
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    return (Read-HordeTakenLedgerFile -Path (Get-HordeChatAnswerLedgerPath -HordeHome $HordeHome) -What "the answers ledger" -Noun "answer")
}

function Write-HordeChatAnswerLedger {
    # The awaiting list, replaced whole in one rename. Throws when it cannot be written.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)]$Ledger)
    Write-HordeTakenLedgerFile -Path (Get-HordeChatAnswerLedgerPath -HordeHome $HordeHome) -Ledger $Ledger -TempPrefix "answers"
}

function Get-HordeChatAnswerLedgerOf {
    # The awaiting list in this run's memory, read on first use: { ok; reason; ledger }.
    param($Context, $Mine)
    if (-not $Mine.ContainsKey("answerLedger")) {
        $r = Read-HordeChatAnswerLedger -HordeHome (Get-HordeChatChannelHome $Context)
        if ($r.state -cne "known") { return [pscustomobject]@{ ok = $false; reason = $r.reason; ledger = $null } }
        $Mine["answerLedger"] = $r.value
        $Mine["answerChecked"] = @{}
    }
    return [pscustomobject]@{ ok = $true; reason = ""; ledger = $Mine["answerLedger"] }
}

function Read-HordeChatAnswerBody {
    # The phone's answer body, read strictly: { ok; reason; value } with value { messageId; horde; machine; lane; snapshot; index; text }.
    # Never throws for the body: the PWA that wrote it is code, and code has bugs.
    param([AllowEmptyCollection()][byte[]]$Body)
    $fail = [pscustomobject]@{ ok = $false; reason = ""; value = $null }
    $strict = New-Object System.Text.UTF8Encoding -ArgumentList $false, $true
    try { $text = $strict.GetString($Body) } catch { $fail.reason = "the answer is not UTF-8"; return $fail }
    if (-not $text.TrimStart().StartsWith("{")) { $fail.reason = "the answer is not a JSON object"; return $fail }
    $dups = @(Find-HordeJsonDuplicateKey -Text $text)
    if ($dups.Count -gt 0) { $fail.reason = ("the answer has a member more than once: " + $dups[0]); return $fail }
    try { $a = ConvertFrom-HordeJson $text } catch { $fail.reason = "the answer is not JSON"; return $fail }
    if ($a -isnot [System.Management.Automation.PSCustomObject]) { $fail.reason = "the answer is not a JSON object"; return $fail }
    $names = @($a.PSObject.Properties | ForEach-Object { $_.Name })
    if ((@($names | Sort-Object) -join ",") -cne (@($script:HordeChatAnswerMembers | Sort-Object) -join ",")) { $fail.reason = ("the answer's members are " + ($names -join ", ") + ", not " + ($script:HordeChatAnswerMembers -join ", ")); return $fail }
    if (-not ($a.v -is [int] -or $a.v -is [long]) -or $a.v -ne 1) { $fail.reason = "the answer is not version 1"; return $fail }
    if ($a.messageId -isnot [string] -or $a.messageId -cnotmatch '\A[0-9a-f]{32}\z') { $fail.reason = "the answer's messageId is not 32 lower-case hex"; return $fail }
    if ($a.horde -isnot [string] -or $a.horde -cnotmatch '\A[a-z0-9][a-z0-9-]{0,62}\z') { $fail.reason = "the answer's horde is not a horde name"; return $fail }
    if ($a.machine -isnot [string] -or $a.machine -cnotmatch '\A[0-9a-f]{32}\z') { $fail.reason = "the answer's machine is not a key id"; return $fail }
    if ($a.lane -isnot [string] -or $a.lane -cnotmatch $script:HordeChatAnswerLanePattern) { $fail.reason = "the answer's lane is not thrall or an Orc's letter"; return $fail }
    if ($a.snapshot -isnot [string] -or $a.snapshot -cnotmatch $script:HordeChatAnswerSnapshotPattern) { $fail.reason = "the answer's snapshot is not a list id"; return $fail }
    if (-not ($a.index -is [int] -or $a.index -is [long]) -or $a.index -lt 1 -or $a.index -gt $script:HordeChatAnswerMostIndex) { $fail.reason = "the answer's index is not an item's place"; return $fail }
    if ($a.text -isnot [string]) { $fail.reason = "the answer's text is not text"; return $fail }
    return [pscustomobject]@{ ok = $true; reason = ""; value = [pscustomobject]@{ messageId = $a.messageId; horde = $a.horde; machine = $a.machine; lane = $a.lane; snapshot = $a.snapshot; index = [int]$a.index; text = [string]$a.text } }
}

function Get-HordeChatAnswerMessageId {
    # The messenger's message id of one answer (EXACTLY ONCE, in the header): a lower-case uuid.
    param([Parameter(Mandatory = $true)][string]$From, [Parameter(Mandatory = $true)][string]$MessageId, [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text, [Parameter(Mandatory = $true)][string]$Snapshot, [Parameter(Mandatory = $true)][int]$Index)
    $words = ConvertTo-HordeRelayHex -Bytes (Get-HordeRelaySha256 -Bytes ([System.Text.Encoding]::UTF8.GetBytes($Text)))
    $h = ConvertTo-HordeRelayHex -Bytes (Get-HordeRelaySha256 -Bytes (Get-HordeRelayAsciiBytes -Text ($script:HordeChatAnswerIdDomain + "`n" + $From + "`n" + $MessageId + "`n" + $words + "`n" + $Snapshot + "`n" + $Index)))
    return ($h.Substring(0, 8) + "-" + $h.Substring(8, 4) + "-" + $h.Substring(12, 4) + "-" + $h.Substring(16, 4) + "-" + $h.Substring(20, 12))
}

function Get-HordeChatAnswerOrcBody {
    # What the Orc reads (header): the header line naming the answer, the item and its list, the item's text as published on one
    # line, a blank line, then his words exactly.
    # -Live false: the snapshot is not the Orc's newest list (N1 of the review of PR 382), and the body says so, because item N of the
    # newest list may be another item.
    param([Parameter(Mandatory = $true)][string]$MessageId, [Parameter(Mandatory = $true)][int]$Index, [Parameter(Mandatory = $true)][string]$Snapshot, [Parameter(Mandatory = $true)][AllowEmptyString()][string]$ItemText, [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text, [bool]$Live = $true)
    $one = [regex]::Replace($ItemText, '\s*[\r\n]+\s*', ' ').Trim()
    $older = $(if ($Live) { "" } else { "NOTE: this is an older list of yours; your newest published list is not this one, so item " + $Index + " there may be another item.`n" })
    return ("FOUNDER ANSWER from the phone (answer " + $MessageId + ") to your published list item " + $Index + " (snapshot " + $Snapshot + "):`n" + $older + "`"" + $one + "`"`n`n" + $Text)
}

function Find-HordeChatAnswerItem {
    # The published item the phone named, found in fleet.db (header, THE ITEM IS FOUND AT THE MACHINE): known { orc; rank; retired;
    # live; count; text }, absent { reason } when no such list or item ever existed, unknown when it cannot be asked now.
    param($Context, [Parameter(Mandatory = $true)][string]$Snapshot, [Parameter(Mandatory = $true)][int]$Index)
    $homeDir = Get-HordeChatChannelHome $Context
    $r = $null
    try {
        if ($null -ne $script:HordeChatAnswerItemReader) { $r = & $script:HordeChatAnswerItemReader $Snapshot $Index $homeDir }
        else { $r = Invoke-HordeDecisionNode -NodeArgs @("published-item", "--snapshot", $Snapshot, "--position", "$Index") -FleetHome $homeDir }
    } catch { return (New-HordeUnknown -Reason ("fleet.db could not be asked for the item: " + $_.Exception.Message)) }
    if ([int]$r.code -ne 0) { return (New-HordeUnknown -Reason ("fleet.db could not be asked for the item: " + [regex]::Replace("$($r.err)", '\s+', ' ').Trim())) }
    try { $j = ConvertFrom-HordeJson "$($r.out)" } catch { return (New-HordeUnknown -Reason "fleet.db answered the item with something that is not JSON") }
    if ($j -isnot [System.Management.Automation.PSCustomObject] -or $null -eq $j.PSObject.Properties["found"]) { return (New-HordeUnknown -Reason "fleet.db answered the item with something that is not an answer") }
    if ($j.found -ne $true) { return (New-HordeAbsent -Note ("" + $j.reason)) }
    foreach ($m in @("orc", "rank", "retired", "live", "count", "text")) { if ($null -eq $j.PSObject.Properties[$m]) { return (New-HordeUnknown -Reason ("fleet.db answered the item without " + $m)) } }
    return (New-HordeKnown -Value ([pscustomobject]@{ orc = "$($j.orc)"; rank = "$($j.rank)"; retired = ($j.retired -eq $true); live = ($j.live -eq $true); count = [int]$j.count; text = "$($j.text)" }))
}

function Find-HordeChatAnswerSeat {
    # The session that owns a list (header, THE RECIPIENT IS RESOLVED ON THE MACHINE): the Thrall's seat for rank thrall, else the
    # seat wearing the Orc's letter with the role orc. A core/Tristate.ps1 answer with known { sessionId }; absent when no such
    # session runs; unknown when it cannot be proven now (two claimants, a registry that cannot be read).
    param([Parameter(Mandatory = $true)][string]$Rank, [Parameter(Mandatory = $true)][string]$Orc)
    $seat = $script:HordeChatAnswerSeat
    if ($null -eq $seat) { $seat = { param([string]$Role, [string]$Label) if ($Label -ceq "") { return (Get-HordeRoleSeat -Role $Role) }; return (Get-HordeLabelSeat -Label $Label -Role $Role) } }
    try {
        if ($Rank -ceq "thrall") { $found = & $seat "warchief" "" } else { $found = & $seat "orc" $Orc }
    } catch { return (New-HordeUnknown -Reason $_.Exception.Message) }
    if ($null -eq $found) { return (New-HordeUnknown -Reason "nothing answered which session holds the seat") }
    if ("$($found.state)" -ceq "known" -and "$($found.value.sessionId)" -ne "") { return $found }
    if ("$($found.state)" -ceq "absent") { return $found }
    return (New-HordeUnknown -Reason $(if ("$($found.reason)" -ne "") { [regex]::Replace("$($found.reason)", '\s+', ' ').Trim() } else { "the seat could not be proven" }))
}

function Send-HordeChatAnswerReceipt {
    # Record and put the receipt of one answer (THE RECEIPT, in the header). "" when sent, else why not - a receipt recorded and not
    # put waits in the chat state, and the Tick puts it.
    param($Context, $Mine, $Answer, [string]$Status, [string]$Code, [long]$SentAt = 0)
    if ($script:HordeChatAnswerCodes[$Status] -cnotcontains $Code) { throw ("'" + $Code + "' is not an answer " + $Status + " code") }
    $phones = Get-HordeChatChannelPhones -Context $Context
    if ($phones.state -cne "known") { return ("no receipt: " + $phones.reason) }
    if (@($phones.value).Count -eq 0) { return "no receipt: no phone identity key is trusted" }
    $body = '{"v":1,"kind":"chat-answer-receipt","horde":"' + $Context.horde + '","machine":"' + $Context.signKeyId + '","messageId":"' + $Answer.messageId + '","lane":"' + $Answer.lane + '","snapshot":"' + $Answer.snapshot + '","index":' + [int]$Answer.index +
        ',"status":"' + $Status + '","code":"' + $Code + '"' + $(if ($SentAt -gt 0) { ',"sentAt":' + $SentAt } else { '' }) + ',"text":' + (ConvertTo-HordeChatChannelJsonString $Answer.text) + '}'
    $saved = Save-HordeChatChannelBodies -Context $Context -Kind "answer-receipt" -Bodies @($body) -Phones @($phones.value)
    if (-not $saved.ok) { return ("no receipt: " + $saved.reason) }
    Add-HordeChatChannelPending -State $Mine.durable -Keys @($saved.keys) -Before $Mine.durable.cursor
    try { Write-HordeChatChannelState -HordeHome (Get-HordeChatChannelHome $Context) -State $Mine.durable } catch { }
    return (Send-HordeChatChannelPending -Context $Context -Mine $Mine)
}

function Invoke-HordeChatAnswerAccept {
    # One opened answer (IN, in the header). { outcome; reason }.
    param($Context, $Item)
    $r = Read-HordeChatAnswerBody -Body $Item.body
    if (-not $r.ok) { return [pscustomobject]@{ outcome = "refused"; reason = $r.reason } }
    $ans = $r.value
    $m = Get-HordeChatChannelMemory -Context $Context
    if (-not $m.ok) { return [pscustomobject]@{ outcome = "retry"; reason = ("the chat state cannot be read: " + $m.reason) } }
    $mine = $m.mine
    $lg = Get-HordeChatAnswerLedgerOf -Context $Context -Mine $mine
    if (-not $lg.ok) { return [pscustomobject]@{ outcome = "retry"; reason = ("the answers ledger cannot be read: " + $lg.reason) } }
    $sentAt = [long]0
    $signedAt = $Item.PSObject.Properties["ts"]
    if ($null -ne $signedAt -and [long]$signedAt.Value -gt 0) { $sentAt = [long]$signedAt.Value }
    $answer = {
        param([string]$Outcome, [string]$Status, [string]$Code, [string]$Why)
        $note = ""
        $heldKey = "answer/" + $ans.messageId + "/" + $Code
        if ($Status -cne "held" -or -not $mine.heldSaid.ContainsKey($heldKey)) {
            if ($Status -ceq "held") { $mine.heldSaid[$heldKey] = $true }
            $sent = Send-HordeChatAnswerReceipt -Context $Context -Mine $mine -Answer $ans -Status $Status -Code $Code -SentAt $sentAt
            if ($sent -cne "") { $note = "; " + $sent }
        }
        return [pscustomobject]@{ outcome = $Outcome; reason = ("answer " + $ans.messageId + " to item " + $ans.index + " of " + $ans.snapshot + ": " + $Status + " (" + $Code + ") - " + $Why + $note) }
    }
    $set = Get-HordeChatChannelSettings -Context $Context
    if ($set.state -cne "known") { return [pscustomobject]@{ outcome = "retry"; reason = ("the relay-chat settings are refused: " + $set.reason) } }
    $set = $set.value
    if ($ans.machine -cne $Context.signKeyId) { return (& $answer "refused" "refused" "wrong-machine" ("it is for the machine " + $ans.machine + ", not this one")) }
    if ($ans.horde -cne $Context.horde) { return (& $answer "refused" "refused" "wrong-horde" ("it is for the horde " + $ans.horde + ", not " + $Context.horde)) }
    if ($ans.text.Trim() -eq "") { return (& $answer "refused" "refused" "empty" "it holds no words") }
    # AN AGE LIMIT (review of PR 382, S3): an answer held for want of a session or a reading is not carried for ever - an Orc parked on Friday
    # must not be handed Friday's answer on Tuesday as if it were current. Past ttlSeconds from the time his passkey signed it, it is given up
    # with a receipt (held, expired - final), the clock being the real one.
    if ($sentAt -gt 0 -and ((Get-HordeChatAnswerNowMs) - $sentAt) -gt ([long]$set.ttlSeconds * 1000)) { return (& $answer "done" "held" "expired" ("it was signed more than " + $set.ttlSeconds + " s ago and was not delivered; it is not carried further")) }
    if ($ans.text.Length -gt [int]$set.lineChars) { return (& $answer "refused" "refused" "too-long" ("it is " + $ans.text.Length + " characters; an answer holds " + $set.lineChars)) }
    # THE ITEM, from fleet.db: whose list it is and what it said.
    $pub = Find-HordeChatAnswerItem -Context $Context -Snapshot $ans.snapshot -Index $ans.index
    if ($pub.state -ceq "absent") { return (& $answer "refused" "refused" "no-such-item" ("no such list or item was ever published: " + $pub.reason)) }
    if ($pub.state -cne "known") { return (& $answer "retry" "held" "not-now" ("the published lists cannot be asked now: " + $pub.reason)) }
    $owner = $pub.value
    $ownerLane = $(if ($owner.rank -ceq "thrall") { "thrall" } else { $owner.orc })
    if ($ownerLane -cne $ans.lane) { return (& $answer "refused" "refused" "wrong-lane" ("the item is in the list of '" + $ownerLane + "', not of '" + $ans.lane + "'")) }
    if ($owner.retired) { return (& $answer "refused" "refused" "orc-retired" ("'" + $ownerLane + "' is retired in fleet.db, so nothing is waiting for the answer")) }
    $bodyText = Get-HordeChatAnswerOrcBody -MessageId $ans.messageId -Index $ans.index -Snapshot $ans.snapshot -ItemText $owner.text -Text $ans.text -Live $owner.live
    $bodyBytes = [System.Text.Encoding]::UTF8.GetByteCount($bodyText)
    if ($bodyBytes -gt $script:HordeMessengerBodyBytes) { return (& $answer "refused" "refused" "too-long" ("its message is " + $bodyBytes + " UTF-8 bytes; a message holds " + $script:HordeMessengerBodyBytes)) }
    # THE RECIPIENT, resolved here and nowhere else.
    $seat = Find-HordeChatAnswerSeat -Rank $owner.rank -Orc $owner.orc
    if ($seat.state -ceq "absent") { return (& $answer "retry" "held" "no-session" ("no live session holds the seat of '" + $ownerLane + "' now; the answer is kept and comes again")) }
    if ($seat.state -cne "known") { return (& $answer "retry" "held" "not-now" ("the seat of '" + $ownerLane + "' cannot be proven now: " + $seat.reason)) }
    $messenger = Find-HordeChatChannelMessenger
    if ($messenger.state -cne "known") { return (& $answer "retry" "held" "not-now" ("no messenger can take it now: " + $messenger.reason)) }
    $deviceId = ""
    try { $deviceId = Get-HordeDeviceId -HomeRoot (Get-HordeChatChannelHome $Context) } catch { return (& $answer "retry" "held" "not-now" ("this machine's device id could not be had: " + $_.Exception.Message)) }
    $message = [pscustomobject]@{
        messageId = (Get-HordeChatAnswerMessageId -From $Item.from -MessageId $ans.messageId -Text $ans.text -Snapshot $ans.snapshot -Index $ans.index); sessionId = "$($seat.value.sessionId)"
        # VERIFIED: this Accept runs only for an answer the relay verified as signed by a passkey the trust store holds as the
        # founder's (senders founder, channels/Port.ps1's gate), so it says so, by that passkey's key id.
        from = [pscustomobject]@{ deviceId = $deviceId; sessionId = $script:HordeChatChannelFrom; label = $set.fromLabel; verified = [pscustomobject]@{ kind = "founder"; by = "passkey"; keyId = $Item.from } }
        body = $bodyText; ttlSeconds = [int]$set.ttlSeconds
    }
    $posted = Send-HordeMessengerMessage -Messenger $messenger.value -Message $message
    if ($posted.state -cne "known") { return (& $answer "retry" "held" "not-now" ("messenger " + $messenger.value.name + " did not take it now: " + $posted.reason)) }
    $wake = Format-HordeMessengerWake -Answer $posted
    if ($wake -cne "") { $wake = "; " + $wake }
    switch ("$($posted.value.stage)") {
        "accepted" {
            # IN THE ORC'S MAILBOX, NOT YET TAKEN: owned by the awaiting list from here, written BEFORE the record is done.
            $wp = $posted.value.PSObject.Properties["woken"]
            $entry = [pscustomobject]@{ messageId = $ans.messageId; messengerId = $message.messageId; postedMs = (Get-HordeChatTakenNowMs); from = "$($Item.from)"; seq = [long]$Item.seq; alarmed = $false; woken = ($null -ne $wp -and $wp.Value -eq $true); session = "" }
            $already = Get-HordeChatTakenEntry -State $lg.ledger -MessageId $ans.messageId
            if ($null -ne $already -and $already.alarmed) {
                return [pscustomobject]@{ outcome = "done"; reason = ("answer " + $ans.messageId + ": already awaited and alarmed - no receipt sent over the alarm") }
            }
            $gaveUp = @()
            $before = @($lg.ledger.awaiting)
            $overflow = @(Get-HordeChatAnswerOverflow -Ledger $lg.ledger -Kept $script:HordeChatAnswerKept)
            if (Add-HordeChatAnswerAwaiting -Ledger $lg.ledger -Entry $entry) {
                $mine["answerChecked"][$ans.messageId] = (Get-HordeChatTakenNowMs)
                try { Write-HordeChatAnswerLedger -HordeHome (Get-HordeChatChannelHome $Context) -Ledger $lg.ledger }
                catch {
                    # Not on disk, so not in memory either: the record comes again and adds it again.
                    $lg.ledger.awaiting = $before
                    return (& $answer "retry" "held" "not-now" ("the answers ledger could not be written, so the answer is not yet awaited: " + $_.Exception.Message))
                }
                $gaveUp = @(foreach ($old in $overflow) { Send-HordeChatAnswerGiveUp -Context $Context -Mine $mine -Entry $old -Why "the awaiting list is full" })
            }
            $queued = & $answer "done" "accepted" "queued" ("messenger " + $messenger.value.name + " took it for the session of '" + $ownerLane + "'" + $wake + "; awaiting that session's own side")
            if ($gaveUp.Count -gt 0) { $queued.reason = $queued.reason + " | " + ($gaveUp -join " | ") }
            return $queued
        }
        "held" { return (& $answer "done" "held" "not-delivered" ("messenger " + $messenger.value.name + " holds it, not delivered")) }
        "expired" { return (& $answer "done" "held" "expired" ("messenger " + $messenger.value.name + " gave it up undelivered")) }
        default { return (& $answer "done" "accepted" "delivered" ("messenger " + $messenger.value.name + " handed it to the session of '" + $ownerLane + "' (" + $posted.value.stage + ")")) }
    }
}

function Get-HordeChatAnswerOverflow {
    # The entries that adding ONE more to a list would push off it, past -Kept: the oldest. Taken.ps1's own rule for another list size.
    param($Ledger, [int]$Kept)
    $marks = @($Ledger.awaiting)
    $over = $marks.Count + 1 - $Kept
    $out = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $over -and $i -lt $marks.Count; $i++) {
        $e = ConvertFrom-HordeChatTakenMark -Mark $marks[$i]
        if ($null -ne $e) { [void]$out.Add($e) }
    }
    return @($out.ToArray())
}

function Add-HordeChatAnswerAwaiting {
    # An answer posted, to the awaiting list once; one already there (a resend) keeps its own clock. $true when added.
    param($Ledger, [Parameter(Mandatory = $true)]$Entry)
    foreach ($m in @($Ledger.awaiting)) {
        $e = ConvertFrom-HordeChatTakenMark -Mark $m
        if ($null -ne $e -and $e.messageId -ceq $Entry.messageId) { return $false }
    }
    $Ledger.awaiting = @(@($Ledger.awaiting) + @(ConvertTo-HordeChatTakenMark -Entry $Entry) | Select-Object -Last $script:HordeChatAnswerKept)
    return $true
}

function Get-HordeChatAnswerWords {
    # The answer and its sending time of one awaiting entry, read back from its journal record (the ledger keeps no word): { state;
    # answer; sentAt; reason }, state ok, retry (the journal cannot be read now) or gone (the record can never be opened again).
    param($Context, $Entry)
    $homeDir = Get-HordeChatChannelHome $Context
    $rec = Get-HordeRelayJournalReceivedRecord -From $Entry.from -Channel "chat" -Seq $Entry.seq -HordeHome $homeDir
    if ($rec.state -cne "known") { return [pscustomobject]@{ state = "retry"; answer = $null; sentAt = [long]0; reason = $rec.reason } }
    $o = Open-HordeRelayChannelRecord -Context $Context -Channel (Get-HordeRelayChannel -Name "chat") -Record $rec.value -Reread
    if (-not $o.ok) { return [pscustomobject]@{ state = $(if ($o.outcome -ceq "retry") { "retry" } else { "gone" }); answer = $null; sentAt = [long]0; reason = $o.reason } }
    $r = Read-HordeChatAnswerBody -Body $o.item.body
    if (-not $r.ok) { return [pscustomobject]@{ state = "gone"; answer = $null; sentAt = [long]0; reason = $r.reason } }
    if ($r.value.messageId -cne $Entry.messageId) { return [pscustomobject]@{ state = "gone"; answer = $null; sentAt = [long]0; reason = "the record holds another answer than the one awaited" } }
    return [pscustomobject]@{ state = "ok"; answer = $r.value; sentAt = [long]$o.item.ts; reason = "" }
}

function Send-HordeChatAnswerGiveUp {
    # One awaiting entry that leaves the list for a reason that is not its own end: the phone is told held/not-delivered, and an ALARM
    # line names it. Returns the log line. The caller removes the entry.
    param($Context, $Mine, $Entry, [string]$Why)
    $w = Get-HordeChatAnswerWords -Context $Context -Entry $Entry
    if ($w.state -cne "ok") { return ("ALARM: answer " + $Entry.messageId + " left the awaiting list (" + $Why + ") and the phone could NOT be told (its words cannot be read: " + $w.reason + ")") }
    $sent = Send-HordeChatAnswerReceipt -Context $Context -Mine $Mine -Answer $w.answer -Status "held" -Code "not-delivered" -SentAt $w.sentAt
    if ($sent.StartsWith("no receipt:")) { return ("ALARM: answer " + $Entry.messageId + " left the awaiting list (" + $Why + ") and the phone could NOT be told (" + $sent + ")") }
    return ("ALARM: answer " + $Entry.messageId + " left the awaiting list (" + $Why + "); the phone is told it was not delivered" + $(if ($sent -cne "") { "; " + $sent } else { "" }))
}

function Test-HordeChatAnswerDue {
    # Is any awaiting answer due to be asked about? Local only: a mark and a clock. For the Glance.
    param($Mine)
    if (-not $Mine.ContainsKey("answerLedger") -or -not $Mine.ContainsKey("takenCheckMs") -or -not $Mine.ContainsKey("takenAfterAlarmMs")) { return $false }
    $now = Get-HordeChatTakenNowMs
    foreach ($m in @($Mine["answerLedger"].awaiting)) {
        $e = ConvertFrom-HordeChatTakenMark -Mark $m
        if ($null -eq $e) { return $true }
        $every = $(if ($e.alarmed) { [long]$Mine["takenAfterAlarmMs"] } else { [long]$Mine["takenCheckMs"] })
        $last = $(if ($Mine["answerChecked"].ContainsKey($e.messageId)) { [long]$Mine["answerChecked"][$e.messageId] } else { [long]0 })
        if ($now - $last -ge $every) { return $true }
    }
    return $false
}

function Invoke-HordeChatAnswerTick {
    # Ask about every awaiting answer that is due and act on it, as Taken.ps1 does for the Thrall's lines (Get-HordeChatTakenAction is
    # used as it is): { lines; failed }. The ledger is read on first use, and only when it is not empty does anything run.
    param($Context, $Mine, $Settings)
    $lines = New-Object System.Collections.ArrayList
    $lg = Get-HordeChatAnswerLedgerOf -Context $Context -Mine $Mine
    if (-not $lg.ok) { return [pscustomobject]@{ lines = @("answers: the awaiting list cannot be read: " + $lg.reason); failed = $true } }
    $d = $lg.ledger
    if (@($d.awaiting).Count -eq 0) { return [pscustomobject]@{ lines = @(); failed = $false } }
    $Mine["takenCheckMs"] = [long]$Settings.takenCheckSeconds * 1000
    $Mine["takenAfterAlarmMs"] = [long]$Settings.takenAfterAlarmSeconds * 1000
    $homeDir = Get-HordeChatChannelHome $Context
    $now = Get-HordeChatTakenNowMs
    $messenger = Find-HordeChatChannelMessenger
    $keep = New-Object System.Collections.ArrayList
    $changed = $false
    $dueList = New-Object System.Collections.ArrayList
    $pos = 0
    foreach ($mark in @($d.awaiting)) {
        $pos++
        $de = ConvertFrom-HordeChatTakenMark -Mark $mark
        if ($null -eq $de) { continue }
        $dLast = $(if ($Mine["answerChecked"].ContainsKey($de.messageId)) { [long]$Mine["answerChecked"][$de.messageId] } else { [long]0 })
        if ($now - $dLast -ge (Get-HordeChatTakenDueMs -Settings $Settings -Alarmed $de.alarmed)) { [void]$dueList.Add([pscustomobject]@{ id = $de.messageId; last = $dLast; pos = $pos }) }
    }
    $mayAsk = @{}
    foreach ($x in @($dueList.ToArray() | Sort-Object -Property last, pos | Select-Object -First $script:HordeChatAnswerAsksPerTick)) { $mayAsk[$x.id] = $true }
    foreach ($mark in @($d.awaiting)) {
        $e = ConvertFrom-HordeChatTakenMark -Mark $mark
        if ($null -eq $e) { [void]$lines.Add("answers: an awaiting mark that is not one was dropped"); $changed = $true; continue }
        if (-not $mayAsk.ContainsKey($e.messageId)) { [void]$keep.Add($mark); continue }
        $Mine["answerChecked"][$e.messageId] = $now
        $status = $null
        if ($messenger.state -ceq "known") { $status = Get-HordeMessengerStatus -Messenger $messenger.value -MessageId $e.messengerId }
        $age = ($now - $e.postedMs) / 1000.0
        $act = Get-HordeChatTakenAction -Status $status -AgeSeconds $age -Alarmed $e.alarmed -AlarmSeconds ([double]$Settings.takenAlarmSeconds) -TtlSeconds ([double]$Settings.ttlSeconds)
        if ($act -ceq "wait") { [void]$keep.Add($mark); continue }
        $w = Get-HordeChatAnswerWords -Context $Context -Entry $e
        if ($w.state -ceq "retry" -and $age -gt [double]$Settings.ttlSeconds) {
            [void]$lines.Add("ALARM: answer " + $e.messageId + " is left (" + $act + ") after " + [int]$age + " s and the phone could NOT be told: its record cannot be read - " + $w.reason); $changed = $true; continue
        }
        if ($w.state -ceq "retry") { [void]$keep.Add($mark); [void]$lines.Add("answers: " + $e.messageId + " is " + $act + ", but its words cannot be read yet (" + $w.reason + "); asked again"); continue }
        if ($w.state -ceq "gone") {
            [void]$lines.Add("ALARM: answer " + $e.messageId + " is left (" + $act + ") and the phone could NOT be told: its record cannot be opened again - " + $w.reason); $changed = $true; continue
        }
        $status_ = "accepted"; $code = "delivered"
        if ($act -ceq "held") { $status_ = "held"; $code = "not-delivered" }
        elseif ($act -ceq "expired") { $status_ = "held"; $code = "expired" }
        elseif ($act -ceq "alarm") { $status_ = "held"; $code = $script:HordeChatTakenAlarmCode }
        $sent = Send-HordeChatAnswerReceipt -Context $Context -Mine $Mine -Answer $w.answer -Status $status_ -Code $code -SentAt $w.sentAt
        if ($sent.StartsWith("no receipt:")) {
            [void]$keep.Add($mark); [void]$lines.Add("answers: " + $e.messageId + " is " + $act + ", and the phone could not be told (" + $sent + "); asked again"); continue
        }
        $note = $(if ($sent -cne "") { "; " + $sent } else { "" })
        $changed = $true
        switch ($act) {
            "confirmed" { [void]$lines.Add("answers: " + $e.messageId + " TAKEN by the receiving session after " + [int]$age + " s: delivered" + $note) }
            "held" { [void]$lines.Add("answers: " + $e.messageId + " NOT DELIVERED: the messenger holds it for good; the phone is told" + $note) }
            "expired" { [void]$lines.Add("answers: " + $e.messageId + " NOT DELIVERED, given up after " + [int]$age + " s; the phone is told" + $note) }
            "alarm" {
                $e.alarmed = $true
                [void]$keep.Add((ConvertTo-HordeChatTakenMark -Entry $e))
                [void]$lines.Add("ALARM: answer " + $e.messageId + " was NOT TAKEN by its session in " + [int]$age + " s (" + $(if ($e.woken) { "the knock landed and the session did not take it" } else { "the session was not woken" }) + "); the founder's phone is told, and it is asked again until it is taken" + $note)
            }
        }
    }
    if ($changed) {
        $d.awaiting = @($keep.ToArray())
        try { Write-HordeChatAnswerLedger -HordeHome $homeDir -Ledger $d }
        catch { [void]$lines.Add("answers: the awaiting list could not be written: " + $_.Exception.Message + "; it is read again after a restart"); return [pscustomobject]@{ lines = @($lines.ToArray()); failed = $true } }
    }
    return [pscustomobject]@{ lines = @($lines.ToArray()); failed = $false }
}
