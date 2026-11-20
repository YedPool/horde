# Mutations of core/WakeRun.ps1, T-0391 slice 9: the tick's look at the two awaiting lists counts a restore mail done / the warchief told
# only on a TAKEN, and hands the list to the restore pass so nothing is posted twice.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-run-taken.psd1 [-Only <name>,...]
# test\test-wake-taken.ps1 must fail for every one.
@{
    Target = "core\WakeRun.ps1"
    Suite  = "test\test-wake-taken.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # What left the restore source's list is not counted done.
        @{ Name = "run-taken-restore-not-counted"
           Find = 'foreach ($x in @($restored.left)) { $Run.posted["$($x.id)"] = $Now }'
           Replace = '' }
        # A tell that left its list on a give-up is told as told.
        @{ Name = "run-taken-given-up-tell-told"
           Find = 'state = $(if ($x.delivered) { "told" } else { "undelivered" })'
           Replace = 'state = "told"' }
        # The tell's state stays awaiting after its TAKEN.
        @{ Name = "run-taken-tell-stays-awaiting"
           Find = 'state = $(if ($x.delivered) { "told" } else { "undelivered" })'
           Replace = 'state = "awaiting"' }
        # The restore pass is not told what is awaiting.
        @{ Name = "run-taken-awaiting-not-handed-to-the-pass"
           Find = '-DuplicateNames @($dupList | ForEach-Object { "$($_.sessionId)" }) -Awaiting $awaitingIds'
           Replace = '-DuplicateNames @($dupList | ForEach-Object { "$($_.sessionId)" })' }
        # The look at the lists is never made.
        @{ Name = "run-taken-never-looked-at"
           Find = 'if (-not (Test-HordeWakeSendersShadow -Run $Run) -and ($Now - $Run.takenAt).TotalSeconds -ge $script:HordeWakeTakenEverySeconds) {'
           Replace = 'if ($false) {' }
        # A TAKEN is not journaled.
        @{ Name = "run-taken-lines-not-journaled"
           Find = 'foreach ($e in @(Update-HordeWakeTaken -Run $Run -Now $Now -Messenger $Messenger -HordeHome $HordeHome)) { [void]$entries.Add($e) }'
           Replace = '$null = Update-HordeWakeTaken -Run $Run -Now $Now -Messenger $Messenger -HordeHome $HordeHome' }
        # The restore pass is not told which mails to post once more.
        @{ Name = "run-taken-retry-not-handed-to-the-pass"
           Find = '-Awaiting $awaitingIds -Retry $retryIds'
           Replace = '-Awaiting $awaitingIds' }
        # A mail is posted once more on every pass after its alarm.
        @{ Name = "run-taken-retry-every-pass"
           Find = 'foreach ($rid in $retryIds) { if ($postedNow -ccontains "$rid") { $Run.retried["$rid"] = $Now } }'
           Replace = '' }
        # The warchief is not told of an alarmed resume mail.
        @{ Name = "run-taken-no-resume-untaken-tell"
           Find = 'foreach ($al in @(Get-HordeWakeMailAlarmed -Kind $script:HordeRestoreTakenKind -HordeHome $HordeHome)) {'
           Replace = 'foreach ($al in @()) {' }
        # A list that cannot be read is journaled on every look.
        @{ Name = "run-taken-trouble-every-look"
           Find = 'if (-not $Run.takenTrouble.ContainsKey($Stem) -or "$($Run.takenTrouble[$Stem])" -cne $trouble) {'
           Replace = 'if ($true) {' }
        # A list that cannot be read is journaled as an alarm.
        @{ Name = "run-taken-trouble-as-alarm"
           Find = '-Outcome "list-trouble"'
           Replace = '-Outcome "alarm"' }
        # Only the first alarmed mark is told of (the reviewer's surviving mutant).
        @{ Name = "run-taken-resume-untaken-first-mark-only"
           Find = 'foreach ($al in @(Get-HordeWakeMailAlarmed -Kind $script:HordeRestoreTakenKind -HordeHome $HordeHome)) {'
           Replace = 'foreach ($al in @(Get-HordeWakeMailAlarmed -Kind $script:HordeRestoreTakenKind -HordeHome $HordeHome | Select-Object -First 1)) {' }
        # A mail the plan did not contain still spends its one repost.
        @{ Name = "run-taken-repost-spent-without-a-post"
           Find = 'foreach ($rid in $retryIds) { if ($postedNow -ccontains "$rid") { $Run.retried["$rid"] = $Now } }'
           Replace = 'foreach ($rid in $retryIds) { $Run.retried["$rid"] = $Now }' }
        # The tell says the mail is in a mailbox (it is not known to be).
        @{ Name = "run-taken-tell-claims-a-mailbox"
           Find = '; it may not have arrived, and that session'
           Replace = '; it is in its mailbox, and that session' }
    )
}
