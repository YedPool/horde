# Mutations of channels/chat/Taken.ps1 (T-0281: a chat line is delivered only when the Thrall's own side takes it).
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-chat-taken.psd1
# Each breaks one rule of the fix; test\test-relay-chat-taken.ps1 must fail for every one.
# The mutations in channels/chat/Channel.ps1 (the accept side) are in relay-chat-taken-accept.psd1.
@{
    Target = "channels\chat\Taken.ps1"
    Suite  = "test\test-relay-chat-taken.ps1"
    Mutations = @(
        # A status that cannot be read is never a confirmation.
        @{ Name = "unreadable-status-counted-as-taken"
           Find = '    if ($AgeSeconds -ge $TtlSeconds) { return "expired" }'
           Replace = '    if ($null -eq $Status -or "$($Status.state)" -cne "known") { return "confirmed" }
    if ($AgeSeconds -ge $TtlSeconds) { return "expired" }' }
        # Only the Thrall's own hook confirms: handed-over and seen, nothing weaker.
        @{ Name = "queued-counted-as-taken"
           Find = 'if ($stage -ceq "handed-over" -or $stage -ceq "seen") { return "confirmed" }'
           Replace = 'if ($stage -ceq "handed-over" -or $stage -ceq "seen" -or $stage -ceq "accepted") { return "confirmed" }' }
        @{ Name = "seen-not-a-confirmation"
           Find = 'if ($stage -ceq "handed-over" -or $stage -ceq "seen") { return "confirmed" }'
           Replace = 'if ($stage -ceq "handed-over") { return "confirmed" }' }
        # An unconfirmed line alarms to the phone after takenAlarmSeconds, once.
        @{ Name = "alarm-never-sent"
           Find = 'if ($AgeSeconds -ge $AlarmSeconds -and -not $Alarmed) { return "alarm" }'
           Replace = 'if ($false) { return "alarm" }' }
        @{ Name = "alarm-sent-early"
           Find = 'if ($AgeSeconds -ge $AlarmSeconds -and -not $Alarmed) { return "alarm" }'
           Replace = 'if ($AgeSeconds -ge 0 -and -not $Alarmed) { return "alarm" }' }
        @{ Name = "alarm-sent-twice"
           Find = 'if ($AgeSeconds -ge $AlarmSeconds -and -not $Alarmed) { return "alarm" }'
           Replace = 'if ($AgeSeconds -ge $AlarmSeconds) { return "alarm" }' }
        # A late TAKEN turns the alarm into delivered: the status of an alarmed line is still asked.
        @{ Name = "late-taken-not-turning-to-delivered"
           Find = 'if ($messenger.state -ceq "known") { $status = Get-HordeMessengerStatus'
           Replace = 'if ($messenger.state -ceq "known" -and -not $e.alarmed) { $status = Get-HordeMessengerStatus' }
        # The alarm leaves the line awaiting; it is never dropped after the alarm.
        @{ Name = "line-dropped-after-alarm"
           Find = '                [void]$keep.Add((ConvertTo-HordeChatTakenMark -Entry $e))'
           Replace = '' }
        @{ Name = "alarm-forgotten-in-the-mark"
           Find = '                $e.alarmed = $true'
           Replace = '                $e.alarmed = $false' }
        # The alarm is one receipt held/not-delivered; a confirmation is accepted/delivered.
        @{ Name = "alarm-sent-as-delivered"
           Find = 'elseif ($act -ceq "alarm") { $status_ = "held"; $code = $script:HordeChatTakenAlarmCode }'
           Replace = 'elseif ($act -ceq "alarm") { $status_ = "accepted"; $code = "delivered" }' }
        # A line that cannot be reported to the phone is asked again, not forgotten.
        @{ Name = "unreported-line-forgotten"
           Find = '[void]$keep.Add($mark); [void]$lines.Add("chat: line " + $e.messageId + " is " + $act + ", and the phone could not be told ("'
           Replace = '$changed = $true; [void]$lines.Add("chat: line " + $e.messageId + " is " + $act + ", and the phone could not be told ("' }
        # A line given up at ttl is told to the phone; a line is asked about only when due.
        @{ Name = "ttl-never-expires"
           Find = 'if ($AgeSeconds -ge $TtlSeconds) { return "expired" }'
           Replace = 'if ($false) { return "expired" }' }
        @{ Name = "asked-on-every-turn"
           Find = 'if ($now - $dLast -ge (Get-HordeChatTakenDueMs -Settings $Settings -Alarmed $de.alarmed)) {'
           Replace = 'if ($true) {' }
        # A duplicate or a restart does not double-send or lose a line.
        @{ Name = "duplicate-added-twice"
           Find = 'if ($null -ne $e -and $e.messageId -ceq $Entry.messageId) { return $false }'
           Replace = '' }
        @{ Name = "awaiting-list-not-kept-across-ticks"
           Find = '        $d.awaiting = @($keep.ToArray())'
           Replace = '        $d.awaiting = @()' }
        # The mark keeps no word of the conversation.
        @{ Name = "words-stored-in-awaiting-mark"
           Find = '":" + $(if ($Entry.woken) { "1" } else { "0" }))'
           Replace = '":" + $(if ($Entry.woken) { "1" } else { "0" }) + ":" + $Entry.text)' }
        # M1: a receipt never depends on the session later. The words are read back WITHOUT judging the
        # session again; a record that cannot be opened at all is an ALARM line, never a silence.
        @{ Name = "receipt-judges-the-session-again"
           Find = '-Record $rec.value -Reread'
           Replace = '-Record $rec.value' }
        @{ Name = "unopenable-line-dropped-silently"
           Find = '[void]$lines.Add("ALARM: chat line " + $e.messageId + " is left (" + $act + ") and the phone could NOT be told: its record cannot be opened again - " + $w.reason)'
           Replace = '[void]$lines.Add("chat: line " + $e.messageId + " is left (" + $act + "): its record cannot be opened again - " + $w.reason)' }
        @{ Name = "unreadable-record-kept-for-ever"
           Find = 'if ($w.state -ceq "retry" -and $age -gt [double]$Settings.ttlSeconds) {'
           Replace = 'if ($false) {' }
        @{ Name = "another-line-s-words-echoed"
           Find = 'if ($r.value.messageId -cne $Entry.messageId) {'
           Replace = 'if ($false) {' }
        # S4: the alarm is still-trying (held/not-now), not the final held/not-delivered.
        @{ Name = "alarm-reads-as-final"
           Find = 'elseif ($act -ceq "alarm") { $status_ = "held"; $code = $script:HordeChatTakenAlarmCode }'
           Replace = 'elseif ($act -ceq "alarm") { $status_ = "held"; $code = "not-delivered" }' }
        # S3: the asks of one tick are bounded, the longest-unasked first.
        @{ Name = "asks-per-tick-unbounded"
           Find = 'Select-Object -First $script:HordeChatTakenAsksPerTick'
           Replace = 'Select-Object -First 100000' }
        @{ Name = "asks-newest-first"
           Find = 'Sort-Object -Property last, pos |'
           Replace = 'Sort-Object -Property last, pos -Descending |' }
        # S2: a line pushed off the full list is told to the phone, with an ALARM line.
        @{ Name = "overflow-receipt-wrong"
           Find = '-MessageId $Entry.messageId -Status "held" -Code "not-delivered"'
           Replace = '-MessageId $Entry.messageId -Status "accepted" -Code "delivered"' }
        @{ Name = "overflow-alarm-line-lost"
           Find = 'return ("ALARM: chat line " + $Entry.messageId + " left the awaiting list (" + $Why + "); the phone is told it was not delivered"'
           Replace = 'return ("chat: line " + $Entry.messageId + " left the awaiting list (" + $Why + "); the phone is told it was not delivered"' }
        # The Glance says yes when a line is due.
        @{ Name = "glance-never-due"
           Find = '        if ($now - $last -ge $every) { return $true }'
           Replace = '        if ($false) { return $true }' }
    )
}
