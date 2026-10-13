# Mutations of core/WakeRun.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-run.psd1
# Each breaks one thing a tick of the wake run exists for - shadow doing nothing, a failure that does
# not end the loop, the restore source running beside the pass and not in every one, a shadow run's
# state kept apart; test\test-wake-run.ps1 must fail for every one.
@{
    Target = "core\WakeRun.ps1"
    Suite  = "test\test-wake-run.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "tick-nudges"
           Find = '-Settings $Settings -Ledger $Run.ledger -Shadow'
           Replace = '-Settings $Settings -Ledger $Run.ledger' }
        @{ Name = "tick-posts"
           Find = '-Settings $RestoreSettings -Shadow -Posted $Run.posted'
           Replace = '-Settings $RestoreSettings -Posted $Run.posted' }
        @{ Name = "shadow-ledger-saved-as-the-live-one"
           Find = 'Save-HordeWakeLedger -Ledger $Run.ledger -Shadow -HordeHome $HordeHome'
           Replace = 'Save-HordeWakeLedger -Ledger $Run.ledger -HordeHome $HordeHome' }
        @{ Name = "shadow-restore-state-saved-as-the-live-one"
           Find = 'Save-HordeRestoreState -Posted $Run.posted -Known $Run.restores -Shadow -HordeHome $HordeHome'
           Replace = 'Save-HordeRestoreState -Posted $Run.posted -Known $Run.restores -HordeHome $HordeHome' }
        @{ Name = "shadow-run-reads-the-live-ledger"
           Find = '$saved = Read-HordeWakeLedger -Shadow -HordeHome $HordeHome'
           Replace = '$saved = Read-HordeWakeLedger -HordeHome $HordeHome' }
        @{ Name = "shadow-run-reads-the-live-restore-state"
           Find = '$savedRestore = Read-HordeRestoreState -Shadow -HordeHome $HordeHome'
           Replace = '$savedRestore = Read-HordeRestoreState -HordeHome $HordeHome' }
        @{ Name = "bad-mail-forgotten-between-ticks"
           Find = '$Run.badMail = $bad.seen'
           Replace = '$Run.badMail = @{}' }
        @{ Name = "restore-source-every-tick"
           Find = 'if (($Now - $Run.restoreAt).TotalSeconds -ge $script:HordeWakeRestoreEverySeconds) {'
           Replace = 'if ($true) {' }
        @{ Name = "restore-failure-forgotten-between-readings"
           Find = 'foreach ($n in @($Run.notes)) { [void]$entries.Add('
           Replace = 'foreach ($n in @()) { [void]$entries.Add(' }
        @{ Name = "pass-failure-not-journaled"
           Find = '[void]$failed.Add([pscustomobject]@{ id = "pass";'
           Replace = '$null = ([pscustomobject]@{ id = "pass";' }
        @{ Name = "heartbeat-failure-not-journaled"
           Find = '[void]$failed.Add([pscustomobject]@{ id = "heartbeat";'
           Replace = '$null = ([pscustomobject]@{ id = "heartbeat";' }
        @{ Name = "heartbeat-without-its-tick"
           Find = '-Pass $Run.pass -TickSeconds $TickSeconds -Shadow'
           Replace = '-Pass $Run.pass -Shadow' }
        @{ Name = "heartbeat-not-marked-shadow"
           Find = '-Pass $Run.pass -TickSeconds $TickSeconds -Shadow'
           Replace = '-Pass $Run.pass -TickSeconds $TickSeconds' }
        @{ Name = "unreadable-saved-ledger-said-nothing"
           Find = '$run.said = @($run.said) + ("starting from an empty ledger - " + $saved.reason)'
           Replace = '$null = 0' }
        @{ Name = "lost-journal-entries-not-handed-back"
           Find = 'catch { return @(@($fresh.entries) + (New-HordeWakeEntry'
           Replace = 'catch { return @(@() + (New-HordeWakeEntry' }
    )
}
