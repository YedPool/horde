# Mutations of how the relay run says what the list of full-mailbox notices holds (cli/RelayRun.ps1), T-0391 slice 5: the list is asked
# about on the setting's clock, its lines reach the run's log (once, not at every look), a notice just posted is asked about at once,
# and the run's table keeps the settings.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-run-taken-look.psd1
# test\test-relay-run-tell-taken.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "cli\RelayRun.ps1"
    Suite  = "test\test-relay-run-tell-taken.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # The list is never asked about on the look (a late TAKEN, an alarm and a give-up are never said).
        @{ Name = "run-never-asks-the-list"
           Find = '    Invoke-HordeRelayRunTakenLook -Watching $Watching -Now $Now -Force:$false'
           Replace = '' }
        # A notice just posted waits for the next due look.
        @{ Name = "run-posted-notice-not-asked-at-once"
           Find = 'Invoke-HordeRelayRunTakenLook -Watching $Watching -Now $Now -Force:$true'
           Replace = 'Invoke-HordeRelayRunTakenLook -Watching $Watching -Now $Now -Force:$false' }
        # The setting's spacing is ignored: the list is read and every mark asked at every look.
        @{ Name = "run-asks-the-list-at-every-look"
           Find = 'if (-not $Force -and ($Now - $Watching.takenAt).TotalSeconds -lt $Watching.takenCheckSeconds) { return }'
           Replace = '' }
        # What the list says never reaches the run's log.
        @{ Name = "run-list-lines-not-said"
           Find = 'if ($Watching.takenLast -cnotcontains $l) { $null = & $Watching.say $l }'
           Replace = '' }
        # The same words are said at every look (an unreadable list, every ten seconds).
        @{ Name = "run-list-lines-repeated"
           Find = 'if ($Watching.takenLast -cnotcontains $l) {'
           Replace = 'if ($true) {' }
        # The lines the mark-first step has (a full list giving up its oldest) never reach the log.
        @{ Name = "run-send-lines-not-said"
           Find = '        foreach ($l in @($sent.lines)) { $null = & $Watching.say $l }'
           Replace = '' }
        # The run counts the post as the warchief told, as before.
        @{ Name = "run-says-the-warchief-was-told"
           Find = '$null = & $Watching.say ("the notice that " + $box + " is full was posted to the warchief''s session; it is delivered only when that session takes it")'
           Replace = '$null = & $Watching.say ("the warchief was told that " + $box + " is full")' }
        @{ Name = "run-settings-not-handed-to-the-table"
           Find = '-TakenAlarmSeconds ([double]$set.takenAlarmSeconds) -TakenCheckSeconds'
           Replace = '-TakenAlarmSeconds 90 -TakenCheckSeconds'
           Expect = "survives"
           Reason = "A run started by the suite is in a home under the temp folder, which posts no notice (cli/RelayRunTell.ps1, A TEST'S HOME TELLS NOBODY), so the settings the run hands its table cannot be seen through the run itself; the table's use of them is held on Invoke-HordeRelayRunPutNotes directly (run-asks-the-list-at-every-look, run-tell-alarm-limit-ignored with a table made at 30 s)." }
    )
}