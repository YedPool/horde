# Mutations of decisions/Notify.ps1, the doorbell for the founder's answers. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-notify.psd1
# test\test-decisions-notify.ps1 must fail for each.
#
# NOT MUTATED HERE: Start- and Stop-HordeDecisionNotifyBeside's runspace plumbing, which the suite
# drives once and test/e2e/e2e-decisions-notify.ps1 drives beside a real window; and the notice's
# wording, which no text of a message ever reaches (it is built from numbers alone).
@{
    Target = "decisions\Notify.ps1"
    Suite  = "test\test-decisions-notify.ps1"
    Mutations = @(
        # --- what a messenger must offer
        @{ Name = "a-doorbell-that-cannot-wake"
           Find = '$script:HordeDecisionNotifyMessengerNeeds = @("body.untyped", "idempotent.post", "wake")'
           Replace = '$script:HordeDecisionNotifyMessengerNeeds = @("body.untyped", "idempotent.post")' }
        # --- the quiet rule
        @{ Name = "quiet-period-not-waited"
           Find = 'if ($Now -lt $quietEnds) {'
           Replace = 'if ($false) {' }
        @{ Name = "rings-on-a-reading-begun-before-quiet-ended"
           Find = 'if ($ReadStartedAt -lt $quietEnds) {'
           Replace = 'if ($false) {' }
        @{ Name = "back-off-not-kept"
           Find = 'if ($Now -lt $NextAttemptAt) {'
           Replace = 'if ($false) {' }
        @{ Name = "future-stored-time-believed"
           Find = 'if ($null -ne $stored -and $stored -le $Now) { return $stored }'
           Replace = 'if ($null -ne $stored) { return $stored }' }
        @{ Name = "back-off-does-not-double"
           Find = '[Math]::Min($Tracker.retryDelay * 2, $script:HordeDecisionNotifyRetryMostSeconds)'
           Replace = '[Math]::Min($Tracker.retryDelay * 1, $script:HordeDecisionNotifyRetryMostSeconds)' }
        # --- what is rung for
        @{ Name = "told-messages-ring-again"
           Find = '$pending = @($unread.items | Where-Object { -not $record.told.Contains($_.message) })'
           Replace = '$pending = @($unread.items)' }
        @{ Name = "any-speaker-rings"
           Find = '"$($_.message.speaker)" -ceq $script:HordeDecisionNotifySpeaker'
           Replace = '$true' }
        @{ Name = "told-on-any-stage"
           Find = '$posted.state -ceq "known" -and $script:HordeDecisionNotifyStages -ccontains "$($posted.value.stage)"'
           Replace = '$posted.state -ceq "known"' }
        @{ Name = "notice-id-depends-on-order"
           Find = '((@($Ids | Sort-Object { [long]$_ }) | ForEach-Object { "$_" }) -join ",")'
           Replace = '((@($Ids) | ForEach-Object { "$_" }) -join ",")' }
        @{ Name = "notice-id-ignores-the-home"
           Find = '"horde-decisions-notify`n" + [System.IO.Path]::GetFullPath($HordeHome).TrimEnd(''\'').ToLowerInvariant() + "`n" +'
           Replace = '"horde-decisions-notify`n" +' }
        # --- the told record
        @{ Name = "unreadable-record-rings-from-empty-memory"
           Find = 'if ($record.state -ceq "refused") { return (& $result "refused"'
           Replace = 'if ($false) { return (& $result "refused"' }
        @{ Name = "key-given-twice-read-anyway"
           Find = 'if (@(Find-HordeJsonDuplicateKey -Text $text).Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "bad-entry-passed-over"
           Find = 'if (-not $ok) { return (& $no "refused"'
           Replace = 'if ($false) { return (& $no "refused"' }
        # --- the loop
        @{ Name = "second-notify-for-a-home-runs"
           Find = 'try { $held = $mutex.WaitOne(0) }'
           Replace = 'try { [void]$mutex.WaitOne(0); $held = $true }' }
        @{ Name = "stop-drops-an-answer-in-its-quiet-period"
           Find = 'elseif (-not ($last.outcome -ceq "waiting"'
           Replace = 'elseif ($true -or -not ($last.outcome -ceq "waiting"' }
        # --- who the notice is from
        @{ Name = "notice-wears-no-label"
           Find = 'sessionId = $script:HordeDecisionNotifyFrom; label = $Tracker.fromLabel }'
           Replace = 'sessionId = $script:HordeDecisionNotifyFrom }' }
        @{ Name = "tracker-ignores-the-label-given"
           Find = 'if ($FromLabel -eq "") { $FromLabel ='
           Replace = 'if ($true) { $FromLabel =' }
        @{ Name = "loop-ignores-the-settings-label"
           Find = '-QuietSeconds $v.quietSeconds -FromLabel $v.fromLabel'
           Replace = '-QuietSeconds $v.quietSeconds' }
        # --- a part answered (2026-10-12) ---
        @{ Name = "the-notice-does-not-say-which-part"
           Find = '        elseif ($letters.Count -eq 1) { "" + $number + " (part " + $letters[0] + ")" }'
           Replace = '        elseif ($letters.Count -eq 1) { "" + $number }' }
        @{ Name = "the-notice-names-only-the-first-of-several-parts"
           Find = '        else { "" + $number + " (parts " + (($letters[0..($letters.Count - 2)]) -join ", ") + " and " + $letters[$letters.Count - 1] + ")" }'
           Replace = '        else { "" + $number + " (part " + $letters[0] + ")" }' }
        @{ Name = "anything-called-a-part-reaches-the-notice"
           Find = """`$(`$_.part)"" -cmatch '\A[a-z]\z' } | ForEach-Object"
           Replace = "`$true } | ForEach-Object" }
        @{ Name = "a-part-is-named-for-another-question"
           Find = '        $letters = @($Items | Where-Object { [int]$_.question -eq $number -and'
           Replace = '        $letters = @($Items | Where-Object {' }
        @{ Name = "what-is-rung-for-carries-no-part"
           Find = 'signedBy = $held["signedBy"]; part = $held["part"] }'
           Replace = 'signedBy = $held["signedBy"]; part = "" }' }
        # --- woken, or only queued (the founder's bug of 2026-10-12)
        @{ Name = "bell-does-not-say-whether-woken"
           Find = '$posted.value.stage + $wake + ")"'
           Replace = '$posted.value.stage + ")"' }
        # --- the founder, verified - or only his label (2026-10-12)
        @{ Name = "verified-never-put-on-the-notice"
           Find = 'if ($null -ne $who.verified) { $from | Add-Member'
           Replace = 'if ($false) { $from | Add-Member' }
        @{ Name = "one-unsigned-answer-does-not-stop-it"
           Find = 'if ($signer.keyId -ceq "") { return (& $no ('
           Replace = 'if ($signer.keyId -ceq "") { continue }; if ($false) { return (& $no (' }
        @{ Name = "two-passkeys-and-the-first-is-named"
           Find = 'if ($keys.Count -ne 1) {'
           Replace = 'if ($keys.Count -lt 1) {' }
        @{ Name = "trust-store-never-asked"
           Find = 'try { $trusted = & $Trust $keyId } catch'
           Replace = 'try { $trusted = New-HordeKnown -Value ([pscustomobject]@{ proof = "webauthn" }) } catch' }
        @{ Name = "left-to-itself-every-key-is-trusted"
           Find = 'return (Find-HordeRelayTrustedSender -HordeHome $HordeHome -KeyId $KeyId) } }'
           Replace = 'return (New-HordeKnown -Value ([pscustomobject]@{ proof = "webauthn" })) } }' }
        @{ Name = "a-store-that-cannot-say-is-believed"
           Find = 'if ($null -eq $trusted -or @("known", "absent") -cnotcontains "$($trusted.state)") {'
           Replace = 'if ($null -eq $trusted) {' }
        @{ Name = "revoked-key-not-told-apart"
           Find = 'if ($trusted.state -ceq "absent") { return (& $no ('
           Replace = 'if ($false) { return (& $no (' }
        @{ Name = "machine-key-named-as-the-founder"
           Find = 'if ($null -eq $trusted.value -or "$($trusted.value.proof)" -cne "webauthn") {'
           Replace = 'if ($null -eq $trusted.value) {' }
        @{ Name = "known-with-no-sender-named-as-the-founder"
           Find = 'if ($null -eq $trusted.value -or "$($trusted.value.proof)" -cne "webauthn") {'
           Replace = 'if ($null -ne $trusted.value -and "$($trusted.value.proof)" -cne "webauthn") {' }
        @{ Name = "label-only-reason-not-said"
           Find = 'elseif ($who.claimed) { $said = $said + "; by label only: " + $who.why }'
           Replace = '' }
        @{ Name = "window-answers-say-a-reason"
           Find = 'elseif ($who.claimed) { $said = $said + "; by label only: " + $who.why }'
           Replace = 'else { $said = $said + "; by label only: " + $who.why }' }
        @{ Name = "verified-not-said-in-the-line"
           Find = '$said = $said + "; as the founder, verified by his passkey " + $who.verified.keyId'
           Replace = '$said = $said' }
        @{ Name = "messenger-note-dropped"
           Find = 'if ($null -ne $note -and "$($note.Value)" -ne "" -and -not $wake.Contains("$($note.Value)")) { $said = $said + "; " + $note.Value }'
           Replace = '' }
        @{ Name = "signedBy-that-is-not-text-is-read"
           Find = '$(if ($null -ne $p -and $p.Value -is [string]) { $p.Value } else { "" })'
           Replace = '$(if ($null -ne $p) { "$($p.Value)" } else { "" })' }
        @{ Name = "route-not-read-from-the-record"
           Find = 'route = $held["route"]; evidence = $held["evidence"]; signedBy = $held["signedBy"]'
           Replace = 'route = "phone"; evidence = $held["evidence"]; signedBy = $held["signedBy"]' }
        @{ Name = "evidence-not-read-from-the-record"
           Find = 'route = $held["route"]; evidence = $held["evidence"]; signedBy = $held["signedBy"]'
           Replace = 'route = $held["route"]; evidence = ("0" * 64); signedBy = $held["signedBy"]' }
        @{ Name = "messenger-reason-said-twice"
           Find = ' -and -not $wake.Contains("$($note.Value)")) { $said = $said + "; " + $note.Value }'
           Replace = ') { $said = $said + "; " + $note.Value }' }
        # --- one turn of the bell, for the relay runner (the founder's bug of 2026-10-12)
        @{ Name = "turn-rings-beside-a-running-notify"
           Find = 'if (-not $mine) { $mutex.Dispose(); return [pscustomobject]@{ outcome = "elsewhere"; said = ""; againMs = 0 } }'
           Replace = 'if ($false) { $mutex.Dispose(); return [pscustomobject]@{ outcome = "elsewhere"; said = ""; againMs = 0 } }' }
        @{ Name = "turn-reads-the-inbox-every-time"
           Find = 'if (-not $due) {'
           Replace = 'if ($false) {' }
        @{ Name = "turn-never-asks-to-be-turned-again"
           Find = 'if ($null -ne $last.wakeAt) { $again = [int][Math]::Max(200,'
           Replace = 'if ($false) { $again = [int][Math]::Max(200,' }
        @{ Name = "turn-says-its-line-every-time"
           Find = 'if ($Line -cne "" -and $Line -cne "$($Memory[''said''])") { $said = $Line }'
           Replace = 'if ($Line -cne "") { $said = $Line }' }
        @{ Name = "turn-rings-on-refused-settings"
           Find = 'if ($settings.state -ceq "refused") { return (& $answer "refused"'
           Replace = 'if ($false) { return (& $answer "refused"' }
    )
}
