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
        @{ Name = "duplicate-line-is-said-on-every-pass"
           Find = '$dupNow = Update-HordeWakeSaidOnce -Seen $Run.duplicate'
           Replace = '$dupNow = Update-HordeWakeSaidOnce -Seen @{}' }
        @{ Name = "duplicate-tell-instance-is-not-the-episode"
           Find = '-Instance $Run.duplicateAt["$($e.id)"].ToUniversalTime().ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)'
           Replace = '-Instance "x"' }
        @{ Name = "duplicate-line-is-not-kept-between-passes"
           Find = '$Run.duplicate = $dupNow.seen'
           Replace = '$Run.duplicate = @{}' }
        @{ Name = "the-heartbeat-does-not-say-the-watchers-own-session"
           Find = ' -Self "$(Get-HordeWakeEntryValue $Run "self")" }'
           Replace = ' }' }
        @{ Name = "the-line-names-no-session"
           Find = 'if ($Self -cne "") { return ("this watcher holds session " + $Self + " as its own'
           Replace = 'if ($false) { return ("this watcher holds session " + $Self + " as its own' }
        @{ Name = "the-tick-does-not-tell-the-pass-how-many-probes"
           Find = '-SilentProbes $silentProbes'
           Replace = '-SilentProbes 0' }
        @{ Name = "a-change-in-the-count-of-probes-is-not-saved"
           Find = ' + "|" + "$(Get-HordeWakeEntryValue $Seen "probes")")'
           Replace = ')' }
        @{ Name = "a-run-that-sends-starts-over-a-silence-it-cannot-read"
           Find = 'if ($run.live) { if ("$($run.refused)" -ceq "") { $run.refused = ("what was saved of a silent fleet'
           Replace = 'if ($false) { if ("$($run.refused)" -ceq "") { $run.refused = ("what was saved of a silent fleet' }
        @{ Name = "a-shadow-run-is-refused-over-its-silence-file"
           Find = 'if ($run.live) { if ("$($run.refused)" -ceq "") { $run.refused = ("what was saved of a silent fleet'
           Replace = 'if ($true) { if ("$($run.refused)" -ceq "") { $run.refused = ("what was saved of a silent fleet' }
        @{ Name = "the-silence-refusal-hides-the-ledgers"
           Find = 'if ($run.live) { if ("$($run.refused)" -ceq "") { $run.refused = ("what was saved of a silent fleet'
           Replace = 'if ($run.live) { if ($true) { $run.refused = ("what was saved of a silent fleet' }
        @{ Name = "the-acknowledgements-do-not-reach-the-silence"
           Find = '-Entries $result.entries -Acks $result.acks -Now $Now -Settings $Settings'
           Replace = '-Entries $result.entries -Acks @{} -Now $Now -Settings $Settings' }
        @{ Name = "the-pass-is-not-handed-the-last-reading-of-acknowledgements"
           Find = ' -AcksSeen $Run.silence'
           Replace = '' }
        @{ Name = "a-sessions-own-acknowledgement-releases-its-own-probe"
           Find = ' -Risen (Get-HordeWakeEntryValue $silence "risen")'
           Replace = '' }
        @{ Name = "the-silence-is-not-saved"
           Find = 'if ((Get-HordeWakeSilenceMark -Seen $Run.silence) -cne $silenceWas) {'
           Replace = 'if ($false) {' }
        @{ Name = "the-silence-is-not-read-back"
           Find = 'if ($savedSilence.state -ceq "known") { $run.silence = $savedSilence.value.seen }'
           Replace = 'if ($false) { $run.silence = $savedSilence.value.seen }' }
        @{ Name = "an-unreadable-silence-is-not-said"
           Find = 'else { $run.said = @($run.said) + ("starting as though the fleet were not silent - " + $savedSilence.reason) }'
           Replace = 'else { }' }
        @{ Name = "the-end-of-a-silence-is-not-saved"
           Find = 'return ("" + ((Get-HordeWakeEntryValue $Seen "silent") -eq $true) + "|" + $since + "|"'
           Replace = 'return ("" + $since + "|"' }
        @{ Name = "the-watchers-own-session-does-not-reach-the-pass"
           Find = '-Only $only -Self "$(Get-HordeWakeEntryValue $Run "self")"'
           Replace = '-Only $only' }
        @{ Name = "a-never-nudged-session-is-journaled-every-tick"
           Find = '$Run.never = $neverNow.seen'
           Replace = '$Run.never = @{}' }
        @{ Name = "a-retired-session-is-journaled-as-held"
           Find = '-Kind "never-nudged" -Outcome "skipped"'
           Replace = '-Kind "held" -Outcome "held"' }
        @{ Name = "a-given-own-session-is-ignored"
           Find = 'if ($PSBoundParameters.ContainsKey("Self")) { $own = $Self }'
           Replace = 'if ($false) { $own = $Self }' }
        @{ Name = "a-proof-run-reads-a-ledger-of-its-own"
           Find = '$saved = Read-HordeWakeLedger -Mode (Get-HordeWakeSendWord -Mode (Get-HordeWakeRunMode -Run $run)) -HordeHome $HordeHome'
           Replace = '$saved = Read-HordeWakeLedger -Mode (Get-HordeWakeRunMode -Run $run) -HordeHome $HordeHome' }
        @{ Name = "a-run-that-sends-starts-from-a-ledger-it-cannot-read"
           Find = 'if ($run.live) { $run.refused = ('
           Replace = 'if ($false) { $run.refused = (' }
        @{ Name = "a-refused-run-is-ticked-all-the-same"
           Find = 'if ("$(Get-HordeWakeEntryValue $Run "refused")" -cne "") { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "a-shadow-run-is-refused-for-its-ledger"
           Find = 'if ($run.live) { $run.refused = ('
           Replace = 'if ($true) { $run.refused = (' }
        @{ Name = "the-ledger-is-kept-only-after-the-tells"
           Find = '$Run.ledger = $result.ledger'
           Replace = '$keptLater = $result.ledger' }
        @{ Name = "the-ledger-is-not-saved-after-the-pass"
           Find = 'if ($ledgerChanged) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-tell-whose-state-cannot-be-saved-fails-the-pass"
           Find = '} catch { [void]$failed.Add([pscustomobject]@{ id = "tell"; reason = ("what was told could not be saved: " + $_.Exception.Message) }) }'
           Replace = '} catch { throw }' }
        @{ Name = "a-tell-that-cannot-be-made-fails-the-pass"
           Find = 'catch { [void]$failed.Add([pscustomobject]@{ id = "tell"; reason = ("a tell could not be made: " + $_.Exception.Message) }) }'
           Replace = 'catch { throw }' }
        @{ Name = "a-run-made-with-no-word-is-live"
           Find = 'if ($word -ceq "" -and $Live) { $word = "live" }'
           Replace = 'if ($word -ceq "") { $word = "live" }' }
        @{ Name = "a-run-that-sends-runs-a-program-nobody-named"
           Find = 'if ($loose -cne "") { return (& $no ("wake run -Mode " + $Mode + " is refused: the program'
           Replace = 'if ($false) { return (& $no ("wake run -Mode " + $Mode + " is refused: the program' }
        @{ Name = "a-program-only-found-is-read-as-named"
           Find = 'if ($null -ne $source -and $source.state -ceq "known" -and $source.value.fixed -ne $true) { $loose = "$($source.value.how)" }'
           Replace = '' }
        @{ Name = "a-waker-that-cannot-say-where-its-program-is-may-send"
           Find = 'if ($null -ne $source -and $source.state -ceq "unknown") { $loose ='
           Replace = 'if ($false) { $loose =' }
        @{ Name = "shadow-is-silent-about-a-program-nobody-named"
           Find = 'if ($loose -cne "" -and $source.state -ceq "known") { $note ='
           Replace = 'if ($false) { $note =' }
        @{ Name = "a-retired-session-is-journaled-every-tick"
           Find = '$Run.held = $heldNow.seen'
           Replace = '$Run.held = @{}' }
        @{ Name = "a-retired-session-is-never-said"
           Find = 'foreach ($e in @($heldNow.entries)) { [void]$entries.Add($e) }'
           Replace = '' }
        @{ Name = "a-proof-run-forgets-its-one-session"
           Find = '-Send:(-not $shadow) -Silent:$silentNow -Only $only'
           Replace = '-Send:(-not $shadow) -Silent:$silentNow' }
        @{ Name = "a-proof-run-with-no-session-runs-over-the-fleet"
           Find = 'if ($only -ceq "") { throw "a proof run was made without'
           Replace = 'if ($false) { throw "a proof run was made without' }
        @{ Name = "a-proof-plan-needs-no-target"
           Find = 'if ($Mode -ceq "proof" -and $Target -ceq "") { return (& $no'
           Replace = 'if ($false) { return (& $no' }
        @{ Name = "a-target-of-any-word-is-taken"
           Find = 'if ($Mode -ceq "proof" -and ($Target -cnotmatch $script:HordeWakeProofTargetPattern -or'
           Replace = 'if ($false -and ($Target -cnotmatch $script:HordeWakeProofTargetPattern -or' }
        @{ Name = "a-target-in-another-casing-is-taken"
           Find = 'if ($Mode -ceq "proof" -and ($Target -cnotmatch $script:HordeWakeProofTargetPattern -or'
           Replace = 'if ($Mode -ceq "proof" -and ($Target -notmatch $script:HordeWakeProofTargetPattern -or' }
        @{ Name = "a-shadow-or-live-run-takes-a-target"
           Find = 'if ($Mode -cne "proof" -and $Target -cne "") { return (& $no'
           Replace = 'if ($false) { return (& $no' }
        @{ Name = "a-missing-target-is-no-usage-error"
           Find = 'It never picks one itself" $true) }'
           Replace = 'It never picks one itself" $false) }' }
        @{ Name = "the-quiet-is-forgotten-between-ticks"
           Find = '$Run.silence = $silence.seen'
           Replace = '$Run.silence = $null' }
        @{ Name = "a-silent-fleet-is-nudged-as-ever"
           Find = '-Ledger $Run.ledger -Send:(-not $shadow) -Silent:$silentNow'
           Replace = '-Ledger $Run.ledger -Send:(-not $shadow)' }
        @{ Name = "found-silent-nothing-is-forgiven"
           Find = 'if ($silence.declared) { $Run.ledger = Reset-HordeWakeLedgerAttempts -Ledger $Run.ledger }'
           Replace = '' }
        @{ Name = "movement-releases-nobody"
           Find = 'if ($silence.moved) { $Run.ledger = Set-HordeWakeLedgerProbesDue -Ledger $Run.ledger -Risen (Get-HordeWakeEntryValue $silence "risen") }'
           Replace = '' }
        @{ Name = "a-limit-is-journaled-every-tick"
           Find = '$Run.limited = $limitedNow.seen'
           Replace = '$Run.limited = @{}' }
        @{ Name = "nobody-told-of-a-silent-fleet"
           Find = 'if ($null -ne $silence.condition) { & $make {'
           Replace = 'if ($false) { & $make {' }
        @{ Name = "proof-as-a-loop"
           Find = 'if (-not $Once) { return (& $no "wake run -Mode proof makes one pass'
           Replace = 'if ($false) { return (& $no "wake run -Mode proof makes one pass' }
        @{ Name = "proof-sends-nothing"
           Find = 'mode = "proof"; target = $Target; live = $true; waker = $waker;'
           Replace = 'mode = "proof"; target = $Target; live = $false; waker = $waker;' }
        @{ Name = "proof-banner-does-not-say-proof"
           Find = 'banner = ("PROOF - PROOF - PROOF - ONE PASS, AND AT MOST ONE REAL NUDGE'
           Replace = 'banner = ("ONE PASS, AND AT MOST ONE REAL NUDGE' }
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
           Find = '-Settings $Settings -Ledger $Run.ledger -Send:(-not $shadow)'
           Replace = '-Settings $Settings -Ledger $Run.ledger -Send:$true' }
        @{ Name = "live-tick-only-journals"
           Find = '-Settings $Settings -Ledger $Run.ledger -Send:(-not $shadow)'
           Replace = '-Settings $Settings -Ledger $Run.ledger -Send:$false' }
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
           Find = '$Run.ledger = $result.ledger'
           Replace = '$Run.ledger = $result.ledger; $mode = $(if ($mode -ceq "shadow") { "live" } else { "shadow" })' }
        @{ Name = "ledger-read-from-the-other-mode"
           Find = '$saved = Read-HordeWakeLedger -Mode (Get-HordeWakeSendWord -Mode (Get-HordeWakeRunMode -Run $run)) -HordeHome $HordeHome'
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
           Find = 'if ($null -ne $fleetRead.condition) { & $make {'
           Replace = 'if ($false) { & $make {' }
        @{ Name = "what-was-told-forgotten-between-ticks"
           Find = '$Run.told = $toldNow.told'
           Replace = '$Run.told = @{}' }
        @{ Name = "what-was-told-not-read-back"
           Find = 'if ($savedTells.state -ceq "known") { $run.told = $savedTells.value.told }'
           Replace = 'if ($false) { $run.told = $savedTells.value.told }' }
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
        @{ Name = "duplicate-not-journaled-by-name"
           Find = '$Run.notes = @(@($Run.notes) + @($dupList |'
           Replace = '$Run.notes = @(@($Run.notes) + @(@() |' }
        @{ Name = "duplicates-not-handed-to-the-restore-pass"
           Find = '-UncountedDuplicates $dupCount'
           Replace = '-UncountedDuplicates 0' }
    )
}
