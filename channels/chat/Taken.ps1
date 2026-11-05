# channels/chat/Taken.ps1 - a line of the founder's is not DELIVERED until the Thrall's own side says so.
#
# THE BUG (task T-0281, the founder's, 2026-10-19: "I sent something via the app but you didn't get it
# because nothing prompted you - that is a bug"). His signed line (chat seq 11, 16:32:56) was posted to
# the Thrall's mail at 16:33:00 and the runner marked the record done at 16:33:04. The messenger's knock
# had been refused ("send-refused: not woken (occupied)"), the Thrall was mid-turn, and nothing knocked
# again: the line sat unread for 11 minutes, until the Thrall's next turn boundary (its hook handed it
# over at 16:44:16). The phone's receipt said "Sent: the Thrall's mailbox has it", which was true and
# was all the founder was ever told. Two of the last fourteen lines in the runner's log were posted
# "queued, NOT woken"; the other twelve were woken.
#
# THE CAUSE. Accept ended at the post. "accepted" (the line is in the Thrall's mailbox) was taken for
# the end of the road, and the one fact that says whether the Thrall has it - the receiving session's
# own hook confirming the line in its transcript, which the messenger port reports as the stage
# handed-over and then seen (TAKEN) - was never asked for. A mailbox is not a doorbell, and a post is not
# a delivery.
#
# THE RULE. A line is DELIVERED only when the Thrall's own side has said so, and a line that is not
# confirmed in takenAlarmSeconds is an ALARM on the founder's phone, not a silence:
#   - AWAITING. A line the messenger accepted (stage accepted: in the mailbox, nobody has read it) is
#     recorded in the chat state's awaiting list - its message id, the messenger's id for it, when it was
#     posted, where its journal record is, whether the knock woke the Thrall, whether the alarm was
#     raised - BEFORE its record is marked done. So the journal's done mark means "the line is in the
#     fleet's durable mail and this channel's durable list owns it from here", never "delivered"; a
#     runner killed at any point loses nothing, and the list survives a restart (never the words: the
#     state keeps no word of the conversation, the words are read back from the journal when a receipt
#     needs them).
#   - ASKED. Every takenCheckSeconds the Tick asks the messenger where each awaiting line is
#     (Get-HordeMessengerStatus - a local read of the fleet's mail, nothing to the relay). handed-over or
#     seen is the Thrall's own hook having taken it: the line's receipt becomes accepted/delivered and it
#     leaves the list. A receipt that comes LATE, after the alarm, replaces the alarm on the phone: the
#     phone shows each line's newest receipt.
#   - ALARMED. Not confirmed after takenAlarmSeconds: ONE receipt, held/not-now, to every trusted
#     phone ("Held: delivery failed for now; it will try again." - the phone's fixed sentence for the code,
#     which reads as still-trying and is NOT the sentence of the final held/not-delivered below; a code of
#     its own with a sentence of its own ("Not delivered yet: the Thrall has not taken it; still trying.")
#     needs the phone page deployed, and an old phone drops a code it does not know), and a
#     line in capitals in the runner's log. Not dropped: the line stays in the Thrall's mailbox and in
#     the list, asked for every takenAfterAlarmSeconds, and a late TAKEN still turns the alarm into
#     delivered. A status that cannot be had (unknown, absent) is NOT a confirmation: the alarm is
#     raised on the clock alone.
#   - GIVEN UP. Held or expired by the messenger (final), or ttlSeconds old: the receipt is held/not-delivered
#     or held/expired, the line leaves the list.
#   - A RECEIPT NEVER DEPENDS ON THE SESSION LATER. The words a receipt echoes are read back from the
#     journal record with Open-HordeRelayChannelRecord -Reread: the sender is not judged again. A line
#     signed with the unlocked SESSION key (every real phone line) was judged once, when it was accepted;
#     the session ending, going idle or being pruned afterwards takes nothing from its receipts. Where its
#     words cannot be had at all (the record can never be opened, holds another line, or has been
#     unreadable for a whole ttlSeconds) the receipt goes WITHOUT words (Get-HordeChatTakenReceiptWords):
#     a receipt is matched to its line by the message id alone, so the phone is still alarmed, the mark is
#     kept, and a later TAKEN still turns the alarm into delivered. It is bounded by ttlSeconds like any
#     other: at ttl the line is given up, wordless, and leaves the list. An ALARM line names the line too.
#   - BOUNDED. At most HordeChatTakenAsksPerTick lines are asked about in one Tick (a status is a process
#     started), the longest-unasked first, so the founder's new lines never wait behind them.
#   - NEVER OFF THE LIST IN SILENCE. Past HordeChatTakenKept lines the oldest is given up WITH a
#     held/not-delivered receipt and an ALARM line, never dropped without a word.
# WHY takenAlarmSeconds IS 90. An idle Thrall that is knocked takes its line within seconds. The knock
# can fail (occupied box, no pane found: the cases above), and the fleet's own re-knock, the wake
# watcher (core/Wake.ps1), backs off 5, 15, 45 seconds, 65 in all, before it is asked a fourth time. So
# 90 seconds is after the knock and three of its re-tries have had their chance, and short enough that
# the founder is told while he still has the phone in his hand. It is a setting.
#
# WHAT THIS DOES NOT DO: knock again. A re-knock is the wake watcher's (core/Wake.ps1); this makes the
# unreached line impossible to miss and impossible to lose. The posters that share the cause (the
# decisions router and doorbell, the photo manifest, the services and relay notices) are listed in the
# task's follow-ups.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

# An awaiting line as the state keeps it:
#   <phone messageId 32 hex>:<messenger uuid>:<posted at, ms>:<sender key id 32 hex>:<journal seq>:<alarmed 0|1>:<woken 0|1>[:<session id>]
# The session id is the Thrall's session the line was written to (an id, never a word of his): a receipt that
# goes WITHOUT his words still names it, for the phone refuses a chat body that names no session (T-0340
# round 2). A mark from before it has none; its wordless receipts name HordeChatTakenNoSession.
$script:HordeChatTakenMarkPattern = '\A([0-9a-f]{32}):([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}):([0-9]{1,16}):([0-9a-f]{32}):([0-9]{1,16}):([01]):([01])(?::([A-Za-z0-9._:-]{1,128}))?\z'
# The session a wordless receipt names when the mark holds none (a mark written before it carried one). The
# phone (relay/js/protocol.js CHAT_NO_SESSION) takes it for "no session" and keeps the session it holds.
$script:HordeChatTakenNoSession = "unknown"

# The most lines awaited at once: a day of lines many times over. The oldest past it are given up on,
# with a receipt and an ALARM line (Get-HordeChatTakenOverflow, Send-HordeChatTakenGiveUp).
$script:HordeChatTakenKept = 200
# The most lines the fleet is asked about in one Tick: each ask is a process, and the Tick shares its
# time with the founder's new lines.
$script:HordeChatTakenAsksPerTick = 10
# The code of the alarm receipt: held/not-now, "Held: delivery failed for now; it will try again." - a
# sentence every phone knows that reads as still-trying, unlike the final held/not-delivered.
$script:HordeChatTakenAlarmCode = "not-now"
# For suites only (Set-HordeChatTakenClock): the clock, in milliseconds since 1970. 0 means the real one.
$script:HordeChatTakenClockMs = [long]0

function Set-HordeChatTakenClock {
    # For tests: the time this file reads. 0 puts the real clock back.
    param([long]$Ms = 0)
    $script:HordeChatTakenClockMs = $Ms
}

function Get-HordeChatTakenNowMs {
    if ($script:HordeChatTakenClockMs -gt 0) { return $script:HordeChatTakenClockMs }
    return [long]([datetime]::UtcNow - [datetime]"1970-01-01T00:00:00Z").TotalMilliseconds
}

function ConvertTo-HordeChatTakenMark {
    param([Parameter(Mandatory = $true)]$Entry)
    return ($Entry.messageId + ":" + $Entry.messengerId + ":" + [long]$Entry.postedMs + ":" + $Entry.from + ":" + [long]$Entry.seq + ":" + $(if ($Entry.alarmed) { "1" } else { "0" }) + ":" + $(if ($Entry.woken) { "1" } else { "0" }) + $(if ("$($Entry.session)" -cne "") { ":" + $Entry.session } else { "" }))
}

function ConvertFrom-HordeChatTakenMark {
    # The entry a mark stands for, or $null when it is not one.
    param([string]$Mark)
    if ($Mark -cnotmatch $script:HordeChatTakenMarkPattern) { return $null }
    $g = $Matches
    return [pscustomobject]@{ messageId = $g[1]; messengerId = $g[2]; postedMs = [long]$g[3]; from = $g[4]; seq = [long]$g[5]; alarmed = ($g[6] -ceq "1"); woken = ($g[7] -ceq "1"); session = $(if ($g.ContainsKey(8)) { "$($g[8])" } else { "" }) }
}

function Get-HordeChatTakenEntry {
    # The awaiting entry of one phone message id, or $null.
    param($State, [Parameter(Mandatory = $true)][string]$MessageId)
    foreach ($m in @($State.awaiting)) {
        $e = ConvertFrom-HordeChatTakenMark -Mark $m
        if ($null -ne $e -and $e.messageId -ceq $MessageId) { return $e }
    }
    return $null
}

function Get-HordeChatTakenOverflow {
    # The entries that adding ONE more line to the list would push off it: the oldest, past
    # HordeChatTakenKept. They are not dropped by this; Add-HordeChatTaken does that, and the caller gives
    # each one up with a receipt (Send-HordeChatTakenGiveUp).
    param($State)
    $marks = @($State.awaiting)
    $over = $marks.Count + 1 - $script:HordeChatTakenKept
    $out = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $over -and $i -lt $marks.Count; $i++) {
        $e = ConvertFrom-HordeChatTakenMark -Mark $marks[$i]
        if ($null -ne $e) { [void]$out.Add($e) }
    }
    return @($out.ToArray())
}

function Add-HordeChatTaken {
    # A posted line to the awaiting list, once: a line already there (a resend, a record that comes
    # again) is not added a second time and keeps its own clock.
    param($State, [Parameter(Mandatory = $true)]$Entry)
    foreach ($m in @($State.awaiting)) {
        $e = ConvertFrom-HordeChatTakenMark -Mark $m
        if ($null -ne $e -and $e.messageId -ceq $Entry.messageId) { return $false }
    }
    $State.awaiting = @(@($State.awaiting) + @(ConvertTo-HordeChatTakenMark -Entry $Entry) | Select-Object -Last $script:HordeChatTakenKept)
    return $true
}

function Read-HordeTakenLedgerFile {
    # A list of awaiting marks kept in its own file, for any caller whose list is not the chat state's (the
    # answers to published items, channels/chat/Answer.ps1; the routed decisions, decisions/RouteTaken.ps1):
    # known { awaiting }, the empty list when there is no file yet, unknown when the file cannot be read or does
    # not hold together - never a guess, and never quietly started over. -What names the file in the words
    # of a refusal ("the answers ledger"), -Noun one entry in them ("answer").
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$What, [Parameter(Mandatory = $true)][string]$Noun)
    if (-not [System.IO.File]::Exists($Path)) { return (New-HordeKnown -Value ([pscustomobject]@{ awaiting = @() })) }
    $why = $What + " " + $Path + " does not hold together"
    try { $bytes = [System.IO.File]::ReadAllBytes($Path); Assert-HordeAsciiBytes -Bytes $bytes -What ($What + " " + $Path); $text = [System.Text.Encoding]::ASCII.GetString($bytes) }
    catch { return (New-HordeUnknown -Reason ($What + " " + $Path + " cannot be read: " + $_.Exception.Message)) }
    if (@(Find-HordeJsonDuplicateKey -Text $text).Count -gt 0) { return (New-HordeUnknown -Reason ($why + ": a member is repeated")) }
    try { $s = ConvertFrom-HordeJson $text } catch { return (New-HordeUnknown -Reason ($why + ": it is not JSON")) }
    if ($s -isnot [System.Management.Automation.PSCustomObject]) { return (New-HordeUnknown -Reason ($why + ": it is not an object")) }
    $names = (@($s.PSObject.Properties | ForEach-Object { $_.Name }) | Sort-Object) -join ","
    if ($names -cne "awaiting,v") { return (New-HordeUnknown -Reason ($why + ": its members are " + $names)) }
    if (-not ($s.v -is [int] -or $s.v -is [long]) -or $s.v -ne 1) { return (New-HordeUnknown -Reason ($why + ": it is not version 1")) }
    foreach ($a in @($s.awaiting)) { if ($a -isnot [string] -or $a -cnotmatch $script:HordeChatTakenMarkPattern) { return (New-HordeUnknown -Reason ($why + ": an awaiting " + $Noun + " is not a mark")) } }
    return (New-HordeKnown -Value ([pscustomobject]@{ awaiting = @($s.awaiting) }))
}

function Write-HordeTakenLedgerFile {
    # The list of awaiting marks, replaced whole in one rename (core/FileAtomic.ps1). Throws when it cannot be
    # written. -TempPrefix names the file it is written beside itself as.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Ledger, [Parameter(Mandatory = $true)][string]$TempPrefix)
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    [void][System.IO.Directory]::CreateDirectory($dir)
    $marks = (@($Ledger.awaiting) | ForEach-Object { '"' + $_ + '"' }) -join ","
    $text = '{"v":1,"awaiting":[' + $marks + ']}'
    $tmp = [System.IO.Path]::Combine($dir, ($TempPrefix + "-" + [guid]::NewGuid().ToString("N") + ".tmp"))
    $fs = New-Object System.IO.FileStream -ArgumentList $tmp, ([System.IO.FileMode]::CreateNew), ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::None)
    try { $b = [System.Text.Encoding]::ASCII.GetBytes($text); $fs.Write($b, 0, $b.Length); $fs.Flush($true) } finally { $fs.Dispose() }
    try { Move-HordeFileAtomic -From $tmp -To $Path } catch { try { [System.IO.File]::Delete($tmp) } catch { }; throw }
}

function Get-HordeChatTakenAction {
    # What to do with one awaiting line, from what the messenger says of it and how old it is. PURE: no
    # clock, no file. -Status is the messenger port's answer to a status (known with a stage, absent or
    # unknown). Answers:
    #   confirmed  the Thrall's own side has it (handed-over, seen): delivered
    #   held       the messenger knows it was not delivered, for good
    #   expired    the messenger gave it up, or the line is ttlSeconds old
    #   alarm      not confirmed in time, and not yet said: tell the founder, once
    #   wait       not yet
    # A status that is not known is never a confirmation: it falls to the clock.
    param($Status, [double]$AgeSeconds, [bool]$Alarmed, [double]$AlarmSeconds, [double]$TtlSeconds)
    if ($null -ne $Status -and "$($Status.state)" -ceq "known") {
        $stage = "$($Status.value.stage)"
        if ($stage -ceq "handed-over" -or $stage -ceq "seen") { return "confirmed" }
        if ($stage -ceq "held") { return "held" }
        if ($stage -ceq "expired") { return "expired" }
    }
    if ($AgeSeconds -ge $TtlSeconds) { return "expired" }
    if ($AgeSeconds -ge $AlarmSeconds -and -not $Alarmed) { return "alarm" }
    return "wait"
}

function Get-HordeChatTakenWords {
    # The words and session of one awaiting line, read back from its journal record (the state keeps
    # none). { state; line; sentAt; reason }: state ok, retry (the journal or the trust store cannot be
    # read now) or gone (the record can never be opened again: its passkey was revoked since).
    param($Context, $Entry)
    $homeDir = Get-HordeChatChannelHome $Context
    $rec = Get-HordeRelayJournalReceivedRecord -From $Entry.from -Channel "chat" -Seq $Entry.seq -HordeHome $homeDir
    if ($rec.state -cne "known") { return [pscustomobject]@{ state = "retry"; line = $null; sentAt = [long]0; reason = $rec.reason } }
    # -Reread: the line was accepted already, so its session is not judged again (a session since ended,
    # gone idle or pruned must not take its receipts away).
    $o = Open-HordeRelayChannelRecord -Context $Context -Channel (Get-HordeRelayChannel -Name "chat") -Record $rec.value -Reread
    if (-not $o.ok) { return [pscustomobject]@{ state = $(if ($o.outcome -ceq "retry") { "retry" } else { "gone" }); line = $null; sentAt = [long]0; reason = $o.reason } }
    $r = Read-HordeChatChannelLine -Body $o.item.body
    if (-not $r.ok) { return [pscustomobject]@{ state = "gone"; line = $null; sentAt = [long]0; reason = $r.reason } }
    if ($r.value.messageId -cne $Entry.messageId) { return [pscustomobject]@{ state = "gone"; line = $null; sentAt = [long]0; reason = "the record holds another line than the one awaited" } }
    return [pscustomobject]@{ state = "ok"; line = $r.value; sentAt = [long]$o.item.ts; reason = "" }
}

function Get-HordeChatTakenReceiptWords {
    # What a receipt echoes of one awaiting line: { session; text; sentAt; note }. The words when they
    # were read (Get-HordeChatTakenWords state ok); else NONE - empty text, no time, but the session the mark
    # holds (the phone refuses a body with no session) - and a note that says so. A receipt is matched to its line by the message id, and the phone keeps the words it
    # already holds when a receipt carries none (relay/js/protocol.js, chatTimeline), so a line whose record
    # can no longer be opened can still be told held, delivered or given up.
    param($Words, $Entry)
    if ($Words.state -ceq "ok") { return [pscustomobject]@{ session = "$($Words.line.session)"; text = "$($Words.line.text)"; sentAt = [long]$Words.sentAt; note = "" } }
    $session = $(if ("$($Entry.session)" -cne "") { "$($Entry.session)" } else { $script:HordeChatTakenNoSession })
    return [pscustomobject]@{ session = $session; text = ""; sentAt = [long]0; note = ("sent without his words, which cannot be read: " + $Words.reason) }
}

function Send-HordeChatTakenGiveUp {
    # One awaiting entry that leaves the list for a reason that is not its own end: the phone is told
    # held/not-delivered (its sentence: "the Thrall's mailbox holds it back"), and an ALARM line names it.
    # HONEST ABOUT WHAT IT KNOWS: the line is no longer watched, but it may still be in the Thrall's mailbox
    # and may yet be taken; the log line says so. Returns the log line. The caller removes the entry AFTER
    # this (a crash in between leaves the entry listed and the receipt sent, never the entry gone and the
    # phone told nothing). { sent; line }: sent is $false when the receipt could not even be recorded, and
    # then the caller must NOT remove the entry (it is given up again at the next try). Told ONCE per
    # process: a retry of the same accept after a failed state write does not send it again (heldSaid).
    param($Context, $Mine, $Entry, [string]$Why)
    $said = $Entry.messageId + "/gave-up"
    if ($Mine.heldSaid.ContainsKey($said)) { return [pscustomobject]@{ sent = $true; line = ("chat line " + $Entry.messageId + " was told not delivered already (" + $Why + ")") } }
    $rw = Get-HordeChatTakenReceiptWords -Words (Get-HordeChatTakenWords -Context $Context -Entry $Entry) -Entry $Entry
    $sent = Send-HordeChatChannelReceipt -Context $Context -Mine $Mine -MessageId $Entry.messageId -Status "held" -Code "not-delivered" -Session $rw.session -Text $rw.text -SentAt $rw.sentAt
    if ($sent.StartsWith("no receipt:")) { return [pscustomobject]@{ sent = $false; line = ("ALARM: chat line " + $Entry.messageId + " cannot leave the awaiting list (" + $Why + "): the phone could NOT be told (" + $sent + "); it is kept and tried again") } }
    $Mine.heldSaid[$said] = $true
    $extra = @(@($rw.note, $sent) | Where-Object { $_ -cne "" })
    return [pscustomobject]@{ sent = $true; line = ("ALARM: chat line " + $Entry.messageId + " left the awaiting list (" + $Why + "); it is no longer watched, but it may still be in the Thrall's mailbox and be taken; the phone is told it was not delivered" + $(if ($extra.Count -gt 0) { "; " + ($extra -join "; ") } else { "" })) }
}
function Get-HordeChatTakenDueMs {
    # How long after its last look an awaiting line is asked about again: the quick cadence until it is
    # alarmed, the slow one after.
    param($Settings, [bool]$Alarmed)
    if ($Alarmed) { return ([long]$Settings.takenAfterAlarmSeconds * 1000) }
    return ([long]$Settings.takenCheckSeconds * 1000)
}

function Test-HordeChatTakenDue {
    # Is any awaiting line due to be asked about? Local only: a mark and a clock. For the Glance.
    param($Mine)
    if (-not $Mine.ContainsKey("takenCheckMs") -or -not $Mine.ContainsKey("takenAfterAlarmMs")) { return $false }
    $now = Get-HordeChatTakenNowMs
    foreach ($m in @($Mine.durable.awaiting)) {
        $e = ConvertFrom-HordeChatTakenMark -Mark $m
        if ($null -eq $e) { return $true }
        $every = $(if ($e.alarmed) { [long]$Mine["takenAfterAlarmMs"] } else { [long]$Mine["takenCheckMs"] })
        $last = $(if ($Mine.takenChecked.ContainsKey($e.messageId)) { [long]$Mine.takenChecked[$e.messageId] } else { [long]0 })
        if ($now - $last -ge $every) { return $true }
    }
    return $false
}

function Invoke-HordeChatTakenTick {
    # Ask about every awaiting line that is due, and act (Get-HordeChatTakenAction): { lines; failed }.
    param($Context, $Mine, $Settings)
    $lines = New-Object System.Collections.ArrayList
    $d = $Mine.durable
    if (@($d.awaiting).Count -eq 0) { return [pscustomobject]@{ lines = @(); failed = $false } }
    $Mine["takenCheckMs"] = [long]$Settings.takenCheckSeconds * 1000
    $Mine["takenAfterAlarmMs"] = [long]$Settings.takenAfterAlarmSeconds * 1000
    $homeDir = Get-HordeChatChannelHome $Context
    $now = Get-HordeChatTakenNowMs
    $messenger = Find-HordeChatChannelMessenger
    $keep = New-Object System.Collections.ArrayList
    $changed = $false
    # BOUNDED: of the lines that are due, the longest-unasked go first, at most HordeChatTakenAsksPerTick
    # of them; the rest are untouched and come first on the next Tick.
    $dueLines = New-Object System.Collections.ArrayList
    $pos = 0
    foreach ($mark in @($d.awaiting)) {
        $pos++
        $de = ConvertFrom-HordeChatTakenMark -Mark $mark
        if ($null -eq $de) { continue }
        $dLast = $(if ($Mine.takenChecked.ContainsKey($de.messageId)) { [long]$Mine.takenChecked[$de.messageId] } else { [long]0 })
        if ($now - $dLast -ge (Get-HordeChatTakenDueMs -Settings $Settings -Alarmed $de.alarmed)) { [void]$dueLines.Add([pscustomobject]@{ id = $de.messageId; last = $dLast; pos = $pos }) }
    }
    $mayAsk = @{}
    foreach ($x in @($dueLines.ToArray() | Sort-Object -Property last, pos | Select-Object -First $script:HordeChatTakenAsksPerTick)) { $mayAsk[$x.id] = $true }
    if ($dueLines.Count -gt $mayAsk.Count) { [void]$lines.Add("chat: " + ($dueLines.Count - $mayAsk.Count) + " of " + $dueLines.Count + " awaiting lines wait for the next tick (at most " + $script:HordeChatTakenAsksPerTick + " are asked about in one)") }
    foreach ($mark in @($d.awaiting)) {
        $e = ConvertFrom-HordeChatTakenMark -Mark $mark
        if ($null -eq $e) { [void]$lines.Add("chat: an awaiting mark that is not one was dropped"); $changed = $true; continue }
        if (-not $mayAsk.ContainsKey($e.messageId)) { [void]$keep.Add($mark); continue }
        $Mine.takenChecked[$e.messageId] = $now
        $status = $null
        if ($messenger.state -ceq "known") { $status = Get-HordeMessengerStatus -Messenger $messenger.value -MessageId $e.messengerId }
        $age = ($now - $e.postedMs) / 1000.0
        $act = Get-HordeChatTakenAction -Status $status -AgeSeconds $age -Alarmed $e.alarmed -AlarmSeconds ([double]$Settings.takenAlarmSeconds) -TtlSeconds ([double]$Settings.ttlSeconds)
        if ($act -ceq "wait") { [void]$keep.Add($mark); continue }
        $w = Get-HordeChatTakenWords -Context $Context -Entry $e
        if ($w.state -ceq "retry" -and $act -cne "alarm" -and $age -le [double]$Settings.ttlSeconds) { [void]$keep.Add($mark); [void]$lines.Add("chat: line " + $e.messageId + " is " + $act + ", but its words cannot be read yet (" + $w.reason + "); asked again"); continue }
        # WORDS THAT CANNOT BE HAD (the record can never be opened again, holds another line, is not in the
        # journal, or has been unreadable for a whole ttl; the ALARM goes without them at once, for the
        # founder is not left to wait on a record that may never come back): the receipt goes without them and the rest is as for any line - the
        # alarm is raised and the mark kept (a later TAKEN still turns it into delivered), the end is
        # bounded by ttl. Never a dropped mark with the phone told nothing.
        $rw = Get-HordeChatTakenReceiptWords -Words $w -Entry $e
        $status_ = "accepted"; $code = "delivered"
        if ($act -ceq "held") { $status_ = "held"; $code = "not-delivered" }
        elseif ($act -ceq "expired") { $status_ = "held"; $code = "expired" }
        elseif ($act -ceq "alarm") { $status_ = "held"; $code = $script:HordeChatTakenAlarmCode }
        $sent = Send-HordeChatChannelReceipt -Context $Context -Mine $Mine -MessageId $e.messageId -Status $status_ -Code $code -Session $rw.session -Text $rw.text -SentAt $rw.sentAt
        if ($sent.StartsWith("no receipt:")) {
            # Not even recorded: nothing told the phone, so the line stays as it was and is asked again.
            [void]$keep.Add($mark); [void]$lines.Add("chat: line " + $e.messageId + " is " + $act + ", and the phone could not be told (" + $sent + "); asked again"); continue
        }
        $note = $(if ($sent -cne "") { "; " + $sent } else { "" })
        if ($rw.note -cne "") {
            $note = "; " + $rw.note + $note
            if ($act -cne "alarm") { [void]$lines.Add("ALARM: chat line " + $e.messageId + " left the list as " + $act + " " + $rw.note) }
        }
        $changed = $true
        switch ($act) {
            "confirmed" { [void]$lines.Add("chat: line " + $e.messageId + " TAKEN by the Thrall's own side after " + [int]$age + " s: delivered" + $note) }
            "held" { [void]$lines.Add("chat: line " + $e.messageId + " NOT DELIVERED: the messenger holds it for good; the phone is told" + $note) }
            "expired" { [void]$lines.Add("chat: line " + $e.messageId + " NOT DELIVERED, given up after " + [int]$age + " s; the phone is told" + $note) }
            "alarm" {
                $e.alarmed = $true
                [void]$keep.Add((ConvertTo-HordeChatTakenMark -Entry $e))
                [void]$lines.Add("ALARM: chat line " + $e.messageId + " was NOT TAKEN by the Thrall in " + [int]$age + " s (" + $(if ($e.woken) { "the knock landed and the Thrall did not take it" } else { "the Thrall was not woken" }) + "); the founder's phone is told, and it is asked again until it is taken" + $note)
            }
        }
    }
    if ($changed) {
        $d.awaiting = @($keep.ToArray())
        try { Write-HordeChatChannelState -HordeHome $homeDir -State $d }
        catch { [void]$lines.Add("chat: the awaiting list could not be written: " + $_.Exception.Message + "; it is read again after a restart"); return [pscustomobject]@{ lines = @($lines.ToArray()); failed = $true } }
    }
    return [pscustomobject]@{ lines = @($lines.ToArray()); failed = $false }
}
