# Mutations of the photo notice to the Thrall (channels/chat/Photo.ps1), T-0391 slice 4: the notice is awaited BEFORE it is posted, is
# delivered only on the Thrall's own TAKEN, a refusal (and only a refusal) takes its mark off, one alarm and a re-ask cadence and a
# give-up, the phone is told saved after an hour, the notice id is stable, and what the list says reaches the runner's log.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-chat-photo-taken.psd1
# test\test-relay-chat-photos.ps1 must fail for every one. The list's engine is in decisions-route-taken.psd1 (NoticeTaken.ps1).
@{
    Target = "channels\chat\Photo.ps1"
    Suite  = "test\test-relay-chat-photos.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # A list that cannot be written no longer holds the post back.
        @{ Name = "photo-unlisted-notice-still-posted"
           Find = 'if (-not $awaited.ok) { return (& $result $false ("the photo notice cannot be awaited ('
           Replace = 'if ($false) { return (& $result $false ("the photo notice cannot be awaited (' }
        # The mark does not name the Thrall's session.
        @{ Name = "photo-mark-without-session"
           Find = '-SessionId "$($src.value.session)" -Now $at'
           Replace = '-SessionId "" -Now $at' }
        # A known refusal keeps its mark (a never-sent notice alarms).
        @{ Name = "photo-refusal-keeps-mark"
           Find = '        $removed = Remove-HordeDecisionNoticeTaken -Kind $script:HordeChatPhotoTakenKind -HordeHome $homeDir -NoticeId $noticeId'
           Replace = '        $removed = [pscustomobject]@{ ok = $true; reason = "" }' }
        # An unknown result loses its mark (a notice that landed is no longer watched).
        @{ Name = "photo-unknown-loses-mark"
           Find = '    if ($refused) {'
           Replace = '    if ($true) {' }
        # A known refusal is counted as the messenger having taken it (today's bug for a held post).
        @{ Name = "photo-refused-stage-counts-as-taken"
           Find = '$script:HordeChatPhotoPostStages = @("accepted", "handed-over", "seen")'
           Replace = '$script:HordeChatPhotoPostStages = @("accepted", "handed-over", "seen", "held")' }
        # The phone is told delivered for any posted notice (today's bug).
        @{ Name = "photo-posted-counts-as-delivered"
           Find = 'if ($table.ContainsKey("delivered-" + $noticeId)) { [void]$lines.Add('
           Replace = 'if ($true) { [void]$lines.Add(' }
        # The notice id changes on every pass (a restart posts a second message).
        @{ Name = "photo-notice-id-not-stable"
           Find = '    $noticeId = Get-HordeChatPhotoMessageId -From $Record.from -PhotoId $Record.photoId -Sha256 $Record.sha256'
           Replace = '    $noticeId = [guid]::NewGuid().ToString()' }
        # Posted again on every pass.
        @{ Name = "photo-posted-again-every-pass"
           Find = '        $table["posted-" + $noticeId] = $true'
           Replace = '        $null = 0' }
        # The alarm limit, the re-ask cadence and the give-up are the engine's three clocks.
        @{ Name = "photo-alarm-at-once"
           Find = '-AlarmSeconds ([double]$Settings.takenAlarmSeconds)'
           Replace = '-AlarmSeconds 0' }
        @{ Name = "photo-reask-every-pass"
           Find = '-AfterAlarmSeconds ([double]$Settings.takenAfterAlarmSeconds)'
           Replace = '-AfterAlarmSeconds 0' }
        @{ Name = "photo-never-given-up"
           Find = '-TtlSeconds ([double]$Settings.ttlSeconds)'
           Replace = '-TtlSeconds 1e12' }
        # The phone is never told saved after the hour.
        @{ Name = "photo-no-saved-after-the-hour"
           Find = 'elseif ($nowMs - [long]$w.rec.savedAt -ge $script:HordeChatPhotoTellMinutes * 60000) { [void]$lines.Add('
           Replace = 'elseif ($false) { [void]$lines.Add(' }
        # A notice that left the list without a TAKEN leaves the photo open for the hour.
        @{ Name = "photo-given-up-notice-not-settled"
           Find = 'elseif (-not (Test-HordeChatPhotoNoticeListed -HordeHome $homeDir -NoticeId $noticeId)) {'
           Replace = 'elseif ($false) {' }
        # The lines of the list never reach the runner's log.
        @{ Name = "photo-taken-lines-not-returned"
           Find = 'foreach ($l in @(Invoke-HordeChatPhotoTakenTick -Context $Context -Mine $Mine -Settings $Settings -Now $Now -Force ($waiting.Count -gt 0))) { [void]$lines.Add($l) }'
           Replace = '$null = @(Invoke-HordeChatPhotoTakenTick -Context $Context -Mine $Mine -Settings $Settings -Now $Now -Force ($waiting.Count -gt 0))' }
    )
}
