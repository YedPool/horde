# Mutations of decisions/RouteTaken.ps1, T-0391 slice 1: a routed answer is DELIVERED only when the Orc's own session
# took it, one ALARM is raised when it does not in time, and a notice is never dropped from the awaiting list.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-route-taken.psd1
# test\test-decisions-route-taken.ps1 must fail for every one. The send side (Route.ps1) is in decisions-route-taken-send.psd1;
# the chat's own decision (Taken.ps1) is in relay-chat-taken.psd1.
@{
    Target = "decisions\RouteTaken.ps1"
    Suite  = "test\test-decisions-route-taken.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # The alarm is not remembered: it would be said again at every pass.
        @{ Name = "alarm-not-remembered"
           Find = '$e.alarmed = $true'
           Replace = '$e.alarmed = $false' }
        # An alarmed notice leaves the list: it is silently dropped after one line.
        @{ Name = "alarmed-notice-dropped"
           Find = '[void]$keep.Add((ConvertTo-HordeChatTakenMark -Entry $e))'
           Replace = '' }
        # The Orc's own TAKEN is never recognised: a taken notice stays awaiting and alarms.
        @{ Name = "taken-never-recognised"
           Find = '"confirmed" {'
           Replace = '"confirmed-never" {' }
        # The messenger is never asked: the clock alone speaks, so a taken notice is not delivered.
        @{ Name = "status-never-asked"
           Find = 'if ($null -ne $Messenger) { $status = Get-HordeMessengerStatus -Messenger $Messenger -MessageId $e.messengerId }'
           Replace = '' }
        # The alarm limit is zero: every notice alarms at once.
        @{ Name = "alarm-limit-ignored"
           Find = '-Alarmed $e.alarmed -AlarmSeconds $AlarmSeconds -TtlSeconds $TtlSeconds'
           Replace = '-Alarmed $e.alarmed -AlarmSeconds 0 -TtlSeconds $TtlSeconds' }
        # A notice the messenger holds for good leaves the list without a word.
        @{ Name = "held-notice-dropped-in-silence"
           Find = '"held" { $changed = $true; [void]$lines.Add("ALARM: " + $name + " NOT DELIVERED: the messenger holds it for good; it is no longer watched") }'
           Replace = '"held" { $changed = $true }' }
        # A notice sent again is listed again on a new clock (a restart would re-arm its alarm).
        @{ Name = "resend-listed-again"
           Find = 'if ($null -ne (Get-HordeChatTakenEntry -State $ledger -MessageId $entry.messageId)) {'
           Replace = 'if ($false) {' }
        # A full list pushes its oldest notice off without a word.
        @{ Name = "overflow-notice-dropped-in-silence"
           Find = '$lines = @(foreach ($old in $overflow) { "ALARM: routed notice "'
           Replace = '$lines = @(foreach ($old in @()) { "ALARM: routed notice "' }
        # A list that cannot be written is taken for written: the record would be written for a notice nobody awaits.
        @{ Name = "unwritable-list-taken-for-written"
           Find = 'catch { return [pscustomobject]@{ ok = $false; reason = ("the routed-answers ledger could not be written: " + $_.Exception.Message); lines = $lines } }'
           Replace = 'catch { }' }
    )
}
