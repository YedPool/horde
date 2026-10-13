# Mutations of core/WakeRun.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-run.psd1
# Each breaks one thing a tick of the wake run exists for - shadow doing nothing, live sending only the
# decided nudges, the restore source staying shadow in BOTH modes, each mode keeping to its own files, a
# failure that does not end the loop, a live run refused without a waker; test\test-wake-run.ps1 must
# fail for every one.
@{
    Target = "core\WakeRun.ps1"
    Suite  = "test\test-wake-run.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "shadow-tick-nudges"
           Find = '-Settings $Settings -Ledger $Run.ledger -Shadow:$shadow'
           Replace = '-Settings $Settings -Ledger $Run.ledger -Shadow:$false' }
        @{ Name = "live-tick-only-journals"
           Find = '-Settings $Settings -Ledger $Run.ledger -Shadow:$shadow'
           Replace = '-Settings $Settings -Ledger $Run.ledger -Shadow:$true' }
        @{ Name = "restore-source-goes-live-with-the-run"
           Find = '-Settings $RestoreSettings -Shadow -Posted $Run.posted'
           Replace = '-Settings $RestoreSettings -Shadow:$shadow -Posted $Run.posted' }
        @{ Name = "restore-source-never-shadow"
           Find = '-Settings $RestoreSettings -Shadow -Posted $Run.posted'
           Replace = '-Settings $RestoreSettings -Posted $Run.posted' }
        @{ Name = "a-run-is-live-by-default"
           Find = '$run = [pscustomobject]@{ live = [bool]$Live;'
           Replace = '$run = [pscustomobject]@{ live = $true;' }
        @{ Name = "a-run-is-never-live"
           Find = '$run = [pscustomobject]@{ live = [bool]$Live;'
           Replace = '$run = [pscustomobject]@{ live = $false;' }
        @{ Name = "anything-in-live-is-live"
           Find = '$shadow = ($Run.live -ne $true)'
           Replace = '$shadow = (-not $Run.live)' }
        @{ Name = "ledger-saved-as-the-other-mode"
           Find = 'Save-HordeWakeLedger -Ledger $Run.ledger -Shadow:$shadow -HordeHome $HordeHome'
           Replace = 'Save-HordeWakeLedger -Ledger $Run.ledger -Shadow:(-not $shadow) -HordeHome $HordeHome' }
        @{ Name = "ledger-read-from-the-other-mode"
           Find = '$saved = Read-HordeWakeLedger -Shadow:(-not $run.live) -HordeHome $HordeHome'
           Replace = '$saved = Read-HordeWakeLedger -Shadow:($run.live) -HordeHome $HordeHome' }
        @{ Name = "would-posts-of-a-live-run-saved-as-posted"
           Find = 'Save-HordeRestoreState -Posted $Run.posted -Known $Run.restores -Name (Get-HordeWakeRestoreName -Run $Run) -Shadow -HordeHome $HordeHome'
           Replace = 'Save-HordeRestoreState -Posted $Run.posted -Known $Run.restores -HordeHome $HordeHome' }
        @{ Name = "live-run-shares-the-shadow-runs-restore-file"
           Find = 'if ($Run.live -eq $true) { return $script:HordeWakeLiveRestoreName }'
           Replace = '' }
        @{ Name = "restore-state-not-read-back"
           Find = '$savedRestore = Read-HordeRestoreState -Name (Get-HordeWakeRestoreName -Run $run) -Shadow -HordeHome $HordeHome'
           Replace = '$savedRestore = Read-HordeRestoreState -Name "none" -Shadow -HordeHome $HordeHome' }
        @{ Name = "heartbeat-of-the-other-mode"
           Find = '-Pass $Run.pass -TickSeconds $TickSeconds -Shadow:$shadow'
           Replace = '-Pass $Run.pass -TickSeconds $TickSeconds -Shadow:(-not $shadow)' }
        @{ Name = "heartbeat-without-its-tick"
           Find = '-Pass $Run.pass -TickSeconds $TickSeconds -Shadow:$shadow'
           Replace = '-Pass $Run.pass -Shadow:$shadow' }
        @{ Name = "journal-of-the-other-mode"
           Find = 'Write-HordeWakeJournal -Entries $fresh.entries -Shadow:$shadow -HordeHome $HordeHome'
           Replace = 'Write-HordeWakeJournal -Entries $fresh.entries -Shadow:(-not $shadow) -HordeHome $HordeHome' }
        @{ Name = "bad-mail-forgotten-between-ticks"
           Find = '$Run.badMail = $bad.seen'
           Replace = '$Run.badMail = @{}' }
        @{ Name = "unreadable-passes-journaled-after-permanent"
           Find = 'if ($fleetRead.quiet -and $e.kind -ceq "skip-unknown" -and "$($e.id)" -ceq "") { continue }'
           Replace = '' }
        @{ Name = "fleet-read-count-forgotten-between-ticks"
           Find = '$Run.fleetRead = $fleetRead.seen'
           Replace = '$Run.fleetRead = $null' }
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
        @{ Name = "unreadable-saved-ledger-said-nothing"
           Find = '$run.said = @($run.said) + ("starting from an empty ledger - " + $saved.reason)'
           Replace = '$null = 0' }
        @{ Name = "lost-journal-entries-not-handed-back"
           Find = 'catch { return @(@($fresh.entries) + (New-HordeWakeEntry'
           Replace = 'catch { return @(@() + (New-HordeWakeEntry' }
        @{ Name = "live-run-started-with-no-waker"
           Find = 'if ($null -eq $waker) { return [pscustomobject]@{ ok = $false; live = $false;'
           Replace = 'if ($false) { return [pscustomobject]@{ ok = $false; live = $false;' }
        @{ Name = "a-plan-is-live-without-being-asked"
           Find = 'if (-not $Live) {'
           Replace = 'if (-not $Live -and $null -eq $waker) {' }
        @{ Name = "shadow-banner-does-not-say-shadow"
           Find = 'banner = ("SHADOW - nothing is nudged and nothing is posted; what would be is journaled.'
           Replace = 'banner = ("nothing is nudged and nothing is posted; what would be is journaled.' }
        @{ Name = "live-banner-does-not-say-live"
           Find = 'banner = ("LIVE - REAL NUDGES are sent'
           Replace = 'banner = ("nudges are sent' }
    )
}
