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
           Find = 'elseif ($act -ceq "alarm") { $status_ = "held"; $code = "not-delivered" }'
           Replace = 'elseif ($act -ceq "alarm") { $status_ = "accepted"; $code = "delivered" }' }
        # A line that cannot be reported to the phone is asked again, not forgotten.
        @{ Name = "unreported-line-forgotten"
           Find = '[void]$keep.Add($mark); [void]$lines.Add("chat: line " + $e.messageId + " is " + $act + ", and the phone could not be told ("'
           Replace = '[void]$lines.Add("chat: line " + $e.messageId + " is " + $act + ", and the phone could not be told ("' }
        # A line given up at ttl is told to the phone; a line is asked about only when due.
        @{ Name = "ttl-never-expires"
           Find = 'if ($AgeSeconds -ge $TtlSeconds) { return "expired" }'
           Replace = 'if ($false) { return "expired" }' }
        @{ Name = "asked-on-every-turn"
           Find = 'if ($now - $last -lt $every) { [void]$keep.Add($mark); continue }'
           Replace = '' }
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
        # The Glance says yes when a line is due.
        @{ Name = "glance-never-due"
           Find = '        if ($now - $last -ge $every) { return $true }'
           Replace = '        if ($false) { return $true }' }
    )
}
