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
#     the session ending, going idle or being pruned afterwards takes nothing from its receipts. Where a
#     receipt truly cannot be sent (its record cannot be opened at all), an ALARM line names the line.
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
#   <phone messageId 32 hex>:<messenger uuid>:<posted at, ms>:<sender key id 32 hex>:<journal seq>:<alarmed 0|1>:<woken 0|1>
$script:HordeChatTakenMarkPattern = '\A([0-9a-f]{32}):([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}):([0-9]{1,16}):([0-9a-f]{32}):([0-9]{1,16}):([01]):([01])\z'
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
    return ($Entry.messageId + ":" + $Entry.messengerId + ":" + [long]$Entry.postedMs + ":" + $Entry.from + ":" + [long]$Entry.seq + ":" + $(if ($Entry.alarmed) { "1" } else { "0" }) + ":" + $(if ($Entry.woken) { "1" } else { "0" }))
}

function ConvertFrom-HordeChatTakenMark {
    # The entry a mark stands for, or $null when it is not one.
    param([string]$Mark)
    if ($Mark -cnotmatch $script:HordeChatTakenMarkPattern) { return $null }
    $g = $Matches
    return [pscustomobject]@{ messageId = $g[1]; messengerId = $g[2]; postedMs = [long]$g[3]; from = $g[4]; seq = [long]$g[5]; alarmed = ($g[6] -ceq "1"); woken = ($g[7] -ceq "1") }
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

function Send-HordeChatTakenGiveUp {
    # One awaiting entry that leaves the list for a reason that is not its own end: the phone is told
    # held/not-delivered, and an ALARM line names it. Returns the log line. The caller removes the entry.
    param($Context, $Mine, $Entry, [string]$Why)
    $w = Get-HordeChatTakenWords -Context $Context -Entry $Entry
    if ($w.state -cne "ok") { return ("ALARM: chat line " + $Entry.messageId + " left the awaiting list (" + $Why + ") and the phone could NOT be told (its words cannot be read: " + $w.reason + ")") }
    $sent = Send-HordeChatChannelReceipt -Context $Context -Mine $Mine -MessageId $Entry.messageId -Status "held" -Code "not-delivered" -Session $w.line.session -Text $w.line.text -SentAt $w.sentAt
    if ($sent.StartsWith("no receipt:")) { return ("ALARM: chat line " + $Entry.messageId + " left the awaiting list (" + $Why + ") and the phone could NOT be told (" + $sent + ")") }
    return ("ALARM: chat line " + $Entry.messageId + " left the awaiting list (" + $Why + "); the phone is told it was not delivered" + $(if ($sent -cne "") { "; " + $sent } else { "" }))
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
        if ($w.state -ceq "retry" -and $age -gt [double]$Settings.ttlSeconds) {
            # A record that could not be read for a whole ttl is not coming back: never kept for ever in silence.
            [void]$lines.Add("ALARM: chat line " + $e.messageId + " is left (" + $act + ") after " + [int]$age + " s and the phone could NOT be told: its record cannot be read - " + $w.reason); $changed = $true; continue
        }
        if ($w.state -ceq "retry") { [void]$keep.Add($mark); [void]$lines.Add("chat: line " + $e.messageId + " is " + $act + ", but its words cannot be read yet (" + $w.reason + "); asked again"); continue }
        if ($w.state -ceq "gone") {
            # Nothing to tell the phone with: the record can never be opened again (damaged, gone), session or
            # no session. Never in silence: an ALARM line names the line.
            [void]$lines.Add("ALARM: chat line " + $e.messageId + " is left (" + $act + ") and the phone could NOT be told: its record cannot be opened again - " + $w.reason); $changed = $true; continue
        }
        $status_ = "accepted"; $code = "delivered"
        if ($act -ceq "held") { $status_ = "held"; $code = "not-delivered" }
        elseif ($act -ceq "expired") { $status_ = "held"; $code = "expired" }
        elseif ($act -ceq "alarm") { $status_ = "held"; $code = $script:HordeChatTakenAlarmCode }
        $sent = Send-HordeChatChannelReceipt -Context $Context -Mine $Mine -MessageId $e.messageId -Status $status_ -Code $code -Session $w.line.session -Text $w.line.text -SentAt $w.sentAt
        if ($sent.StartsWith("no receipt:")) {
            # Not even recorded: nothing told the phone, so the line stays as it was and is asked again.
            [void]$keep.Add($mark); [void]$lines.Add("chat: line " + $e.messageId + " is " + $act + ", and the phone could not be told (" + $sent + "); asked again"); continue
        }
        $note = $(if ($sent -cne "") { "; " + $sent } else { "" })
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
