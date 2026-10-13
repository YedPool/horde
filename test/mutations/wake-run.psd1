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
        @{ Name = "the-quiet-is-forgotten-between-ticks"
           Find = '$Run.silence = $silence.seen'
           Replace = '$Run.silence = $null' }
        @{ Name = "a-silent-fleet-is-nudged-as-ever"
           Find = '-Ledger $Run.ledger -Shadow:$shadow -Silent:$silentNow'
           Replace = '-Ledger $Run.ledger -Shadow:$shadow' }
        @{ Name = "found-silent-nothing-is-forgiven"
           Find = 'if ($silence.declared) { $ledgerNow = Reset-HordeWakeLedgerAttempts -Ledger $ledgerNow }'
           Replace = '' }
        @{ Name = "movement-releases-nobody"
           Find = 'if ($silence.moved) { $ledgerNow = Set-HordeWakeLedgerProbesDue -Ledger $ledgerNow }'
           Replace = '' }
        @{ Name = "a-limit-is-journaled-every-tick"
           Find = '$Run.limited = $limitedNow.seen'
           Replace = '$Run.limited = @{}' }
        @{ Name = "nobody-told-of-a-silent-fleet"
           Find = 'if ($null -ne $silence.condition) { [void]$conditions.Add('
           Replace = 'if ($false) { [void]$conditions.Add(' }
        @{ Name = "proof-as-a-loop"
           Find = 'if (-not $Once) { return (& $no "wake run -Mode proof makes one pass'
           Replace = 'if ($false) { return (& $no "wake run -Mode proof makes one pass' }
        @{ Name = "proof-sends-nothing"
           Find = 'mode = "proof"; live = $true; waker = $waker;'
           Replace = 'mode = "proof"; live = $false; waker = $waker;' }
        @{ Name = "proof-banner-does-not-say-proof"
           Find = 'banner = ("PROOF - PROOF - PROOF - ONE PASS OF REAL NUDGES'
           Replace = 'banner = ("ONE PASS OF REAL NUDGES' }
        @{ Name = "proof-banner-silent-about-what-it-shows"
           Find = 'if ($unverified.Count -gt 0) { $shows = '
           Replace = 'if ($false) { $shows = ' }
        @{ Name = "a-mode-in-another-casing-accepted"
           Find = 'if (@("shadow", "proof", "live") -cnotcontains $Mode) { return (& $no'
           Replace = 'if (@("shadow", "proof", "live") -notcontains $Mode) { return (& $no' }
        @{ Name = "a-word-that-is-no-mode-is-a-live-plan"
           Find = 'if (@("shadow", "proof", "live") -cnotcontains $Mode) { return (& $no'
           Replace = 'if ($false) { return (& $no' }
        @{ Name = "live-may-pick-an-unverified-waker"
           Find = 'if ($Mode -ceq "live") { return (Resolve-HordeProductionWaker) }'
           Replace = '' }
        @{ Name = "shadow-and-proof-may-not-pick-an-unverified-waker"
           Find = 'return (Resolve-HordeProductionWaker -AllowUnverified)'
           Replace = 'return (Resolve-HordeProductionWaker)' }
        @{ Name = "proof-run-writes-the-live-runs-files"
           Find = 'if ($null -ne $p -and "$($p.Value)" -ceq "proof") { return "proof" }'
           Replace = '' }
        @{ Name = "proof-run-posts-when-the-senders-switch-is-on"
           Find = 'if ((Get-HordeWakeRunMode -Run $Run) -cne "live") { return $true }'
           Replace = 'if ((Get-HordeWakeRunMode -Run $Run) -ceq "shadow") { return $true }' }
        @{ Name = "proof-marks-kept-in-the-live-runs-file"
           Find = 'name = ($Stem + "-of-" + $mode + "-run"); mode = "shadow" } }'
           Replace = 'name = ($Stem + "-of-live-run"); mode = "shadow" } }' }
        @{ Name = "shadow-tick-nudges"
           Find = '-Settings $Settings -Ledger $Run.ledger -Shadow:$shadow'
           Replace = '-Settings $Settings -Ledger $Run.ledger -Shadow:$false' }
        @{ Name = "live-tick-only-journals"
           Find = '-Settings $Settings -Ledger $Run.ledger -Shadow:$shadow'
           Replace = '-Settings $Settings -Ledger $Run.ledger -Shadow:$true' }
        @{ Name = "restore-source-goes-live-with-the-run"
           Find = '$script:HordeWakeSendersPost = $false'
           Replace = '$script:HordeWakeSendersPost = $true' }
        @{ Name = "restore-source-never-shadow"
           Find = 'return ($script:HordeWakeSendersPost -ne $true)'
           Replace = 'return $false' }
        @{ Name = "a-run-is-live-by-default"
           Find = 'live = ($word -cne "shadow"); ledger'
           Replace = 'live = $true; ledger' }
        @{ Name = "a-run-is-never-live"
           Find = 'live = ($word -cne "shadow"); ledger'
           Replace = 'live = $false; ledger' }
        @{ Name = "anything-in-live-is-live"
           Find = 'if ($Run.live -ne $true) { return "shadow" }'
           Replace = 'if (-not $Run.live) { return "shadow" }' }
        @{ Name = "ledger-saved-as-the-other-mode"
           Find = 'Save-HordeWakeLedger -Ledger $Run.ledger -Mode $mode -HordeHome $HordeHome'
           Replace = 'Save-HordeWakeLedger -Ledger $Run.ledger -Mode "live" -HordeHome $HordeHome' }
        @{ Name = "ledger-read-from-the-other-mode"
           Find = '$saved = Read-HordeWakeLedger -Mode (Get-HordeWakeRunMode -Run $run) -HordeHome $HordeHome'
           Replace = '$saved = Read-HordeWakeLedger -Mode "live" -HordeHome $HordeHome' }
        @{ Name = "would-posts-of-a-live-run-saved-as-posted"
           Find = 'if (Test-HordeWakeSendersShadow -Run $Run) { return [pscustomobject]@{ name = ($Stem + "-of-" + $mode + "-run"); mode = "shadow" } }'
           Replace = '' }
        @{ Name = "live-run-shares-the-shadow-runs-restore-file"
           Find = 'return [pscustomobject]@{ name = ($Stem + "-of-" + $mode + "-run"); mode = "shadow" } }'
           Replace = 'return [pscustomobject]@{ name = $Stem; mode = "shadow" } }' }
        @{ Name = "restore-state-not-read-back"
           Find = '$savedRestore = Read-HordeRestoreState -Name (Get-HordeWakeSenderFile -Run $run -Stem "restore").name'
           Replace = '$savedRestore = Read-HordeRestoreState -Name "none"' }
        @{ Name = "heartbeat-of-the-other-mode"
           Find = '-Pass $Run.pass -TickSeconds $TickSeconds -Mode $mode'
           Replace = '-Pass $Run.pass -TickSeconds $TickSeconds -Mode "live"' }
        @{ Name = "heartbeat-without-its-tick"
           Find = '-Pass $Run.pass -TickSeconds $TickSeconds -Mode $mode'
           Replace = '-Pass $Run.pass -Mode $mode' }
        @{ Name = "journal-of-the-other-mode"
           Find = 'Write-HordeWakeJournal -Entries $fresh.entries -Mode $mode -HordeHome $HordeHome'
           Replace = 'Write-HordeWakeJournal -Entries $fresh.entries -Mode "live" -HordeHome $HordeHome' }
        @{ Name = "bad-mail-forgotten-between-ticks"
           Find = '$Run.badMail = $bad.seen'
           Replace = '$Run.badMail = @{}' }
        @{ Name = "unreadable-passes-journaled-after-permanent"
           Find = 'if ($fleetRead.quiet -and $e.kind -ceq "skip-unknown" -and "$($e.id)" -ceq "") { continue }'
           Replace = '' }
        @{ Name = "fleet-read-count-forgotten-between-ticks"
           Find = '$Run.fleetRead = $fleetRead.seen'
           Replace = '$Run.fleetRead = $null' }
        @{ Name = "senders-shadow-in-a-shadow-run-only-by-the-switch"
           Find = 'if ((Get-HordeWakeRunMode -Run $Run) -cne "live") { return $true }'
           Replace = '' }
        @{ Name = "the-warchief-forgotten-when-the-fleet-goes-dark"
           Find = 'if ("$($result.warchief)" -cne "") { $Run.warchief = "$($result.warchief)" }'
           Replace = '$Run.warchief = "$($result.warchief)"' }
        @{ Name = "nobody-told-of-a-session-given-up-on"
           Find = 'foreach ($g in @($result.gaveUp)) {'
           Replace = 'foreach ($g in @()) {' }
        @{ Name = "nobody-told-of-a-killed-nudge"
           Find = 'foreach ($e in @($result.entries | Where-Object { $_.kind -ceq "nudge-killed" })) {'
           Replace = 'foreach ($e in @()) {' }
        @{ Name = "nobody-told-of-bad-mail"
           Find = '-Kind "bad-mail" -Subject $e.id'
           Replace = '-Kind "bad-mail" -Subject ""' }
        @{ Name = "nobody-told-of-a-failing-fleet-read"
           Find = 'if ($null -ne $fleetRead.condition) { [void]$conditions.Add('
           Replace = 'if ($false) { [void]$conditions.Add(' }
        @{ Name = "what-was-told-forgotten-between-ticks"
           Find = '$Run.told = $toldNow.told'
           Replace = '$Run.told = @{}' }
        @{ Name = "what-was-told-not-read-back"
           Find = 'if ($savedTells.state -ceq "known") { $run.told = $savedTells.value.told }'
           Replace = '' }
        @{ Name = "live-through-an-unverified-waker"
           Find = 'if ($unverified.Count -gt 0) { return (& $no ("wake run -Mode live is refused'
           Replace = 'if ($false) { return (& $no ("wake run -Mode live is refused' }
        @{ Name = "shadow-banner-silent-about-unverified"
           Find = 'if ($unverified.Count -gt 0) { $note = '
           Replace = 'if ($false) { $note = ' }
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
           Find = 'if ($null -eq $waker) { return (& $no ("wake run -Mode "'
           Replace = 'if ($false) { return (& $no ("wake run -Mode "' }
        @{ Name = "a-plan-is-live-without-being-asked"
           Find = 'if ($Mode -ceq "shadow") {'
           Replace = 'if ($Mode -ceq "shadow" -and $null -eq $waker) {' }
        @{ Name = "shadow-banner-does-not-say-shadow"
           Find = 'banner = ("SHADOW - nothing is nudged and nothing is posted; what would be is journaled.'
           Replace = 'banner = ("nothing is nudged and nothing is posted; what would be is journaled.' }
        @{ Name = "live-banner-does-not-say-live"
           Find = 'banner = ("LIVE - REAL NUDGES are sent'
           Replace = 'banner = ("nudges are sent' }
    )
}
