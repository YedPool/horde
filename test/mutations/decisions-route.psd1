# Mutations of decisions/Route.ps1, which sends a founder's answer to the Orc that asked. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-route.psd1
# test\test-decisions-route.ps1 must fail for each.
#
# NOT MUTATED HERE: the notice's words beyond what a reader acts on (its first line, his words, the
# command that acknowledges it), and the default seat and analyst blocks, which the suite replaces with
# stand-ins so that no real fleet or mail is touched; the analyst's own mail is driven directly.
@{
    Target = "decisions\Route.ps1"
    Suite  = "test\test-decisions-route.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # --- the messenger
        @{ Name = "a-messenger-that-cannot-wake"
           Find = '$script:HordeDecisionRouteMessengerNeeds = @("body.untyped", "idempotent.post", "wake")'
           Replace = '$script:HordeDecisionRouteMessengerNeeds = @("body.untyped", "idempotent.post")' }
        @{ Name = "recorded-on-any-stage"
           Find = '$posted.state -cne "known" -or $script:HordeDecisionRouteStages -cnotcontains "$($posted.value.stage)"'
           Replace = '$posted.state -cne "known"' }
        # --- what is routed
        @{ Name = "old-answers-routed"
           Find = 'if ($null -eq $at -or $at -lt $oldest) { continue }'
           Replace = 'if ($null -eq $at) { continue }' }
        @{ Name = "answers-under-closed-questions-routed"
           Find = 'if ("$($q.state)" -cne "open" -or $null -eq $q.thread.PSObject.Properties["messages"]) { continue }'
           Replace = 'if ($null -eq $q.thread.PSObject.Properties["messages"]) { continue }' }
        @{ Name = "acts-routed"
           Find = '-cne (Get-HordeDecisionFirstTurn) -or "$($m.act)" -ne "") { continue }'
           Replace = '-cne (Get-HordeDecisionFirstTurn)) { continue }' }
        @{ Name = "anybody-s-words-routed"
           Find = 'if ($null -eq $m -or "$($m.speaker)" -cne (Get-HordeDecisionFirstTurn) -or'
           Replace = 'if ($null -eq $m -or' }
        @{ Name = "routed-answers-routed-again"
           Find = 'if (Test-HordeDecisionRouted -Question $q -Answer ([long]$m.sequence) -Purpose "answer") { continue }'
           Replace = '' }
        @{ Name = "reminded-again"
           Find = 'if ($null -eq $u -or [bool]$u.reminded -or'
           Replace = 'if ($null -eq $u -or' }
        @{ Name = "reminded-for-an-answer-never-routed"
           Find = 'if (-not (Test-HordeDecisionRouted -Question $q -Answer ([long]$u.answer) -Purpose "answer")) { continue }'
           Replace = '' }
        # --- where it goes
        @{ Name = "the-orc-is-never-asked"
           Find = 'if ($asker.seat -ceq "orc") {'
           Replace = 'if ($false) {' }
        @{ Name = "an-orc-seat-that-is-not-known-is-used"
           Find = 'if ($null -ne $found -and "$($found.state)" -ceq "known" -and "$($found.value.sessionId)" -ne "") {'
           Replace = 'if ($null -ne $found -and "$($found.state)" -cne "unknown") {' }
        @{ Name = "no-warchief-sent-anyway"
           Find = 'if ($null -eq $boss -or "$($boss.state)" -cne "known" -or "$($boss.value.sessionId)" -eq "") {'
           Replace = 'if ($null -eq $boss) {' }
        @{ Name = "unresolved-said-resolved"
           Find = 'resolved = ($note -eq ""); note = $note; problem = ""; seatState'
           Replace = 'resolved = $true; note = $note; problem = ""; seatState' }
        # --- exactly once
        @{ Name = "notice-id-ignores-the-answer"
           Find = '+ $Number + "`n" + $Answer + "`n" + $SessionId'
           Replace = '+ $Number + "`n" + $SessionId' }
        @{ Name = "notice-id-ignores-the-home"
           Find = '"horde-decisions-route`n" + [System.IO.Path]::GetFullPath($HordeHome).TrimEnd(''\'').ToLowerInvariant() + "`n" + $Purpose'
           Replace = '"horde-decisions-route`n" + $Purpose' }
        @{ Name = "notice-id-new-each-pass"
           Find = '$noticeId = Get-HordeDecisionRouteNoticeId -HordeHome $HordeHome -Purpose $item.purpose -Number $number -Answer $seq -SessionId $target.sessionId'
           Replace = '$noticeId = [guid]::NewGuid().ToString()' }
        @{ Name = "record-id-new-each-pass"
           Find = 'id = (Get-HordeDecisionRouteRecordId -Purpose $item.purpose -Number $number -Answer $seq)'
           Replace = 'id = ([guid]::NewGuid().ToString("N"))' }
        @{ Name = "a-record-not-written-said-routed"
           Find = 'if ($wrote.state -ceq "known" -and @("done", "replayed") -ccontains "$($wrote.value.outcome)") {'
           Replace = 'if ($true) {' }
        # --- the analyst
        @{ Name = "the-analyst-is-not-told"
           Find = 'try { $sent = & $Analyst (Format-HordeDecisionRouteAnalystLine -Item $item -Target $target -Token $token) $token (ConvertFrom-HordeDecisionRouteTime -Text "$($item.answer.at)") } catch {'
           Replace = 'try { $sent = $null } catch {' }
        @{ Name = "the-analyst-is-told-of-reminders"
           Find = '        if ($item.purpose -ceq "answer") {'
           Replace = '        if ($true) {' }
        @{ Name = "the-analyst-line-written-twice"
           Find = 'if ($held.Contains($Token)) {'
           Replace = 'if ($false) {' }
        @{ Name = "delivered-mail-not-looked-in"
           Find = 'foreach ($dir in @($paths.mail, $paths.delivered)) {'
           Replace = 'foreach ($dir in @($paths.mail)) {' }
        # --- the notice
        @{ Name = "the-notice-without-his-words"
           Find = 'foreach ($l in @(([string]$m.text) -split "\r?\n")) { [void]$lines.Add("  " + $l) }'
           Replace = '' }
        @{ Name = "the-orc-is-told-to-close-not-ack"
           Find = '$mine = ($Target.seat -ceq "orc")'
           Replace = '$mine = $false' }
        # --- the turn
        @{ Name = "two-routers-at-once"
           Find = 'try { $mine = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $mine = $true }'
           Replace = '$mine = $true' }
        @{ Name = "every-turn-passes"
           Find = '$due = $Force -or'
           Replace = '$due = $true -or' }
        @{ Name = "its-own-records-read-as-a-change"
           Find = '$Memory["mark"] = Get-HordeDecisionRouteStoreMark -Root $StoreRoot'
           Replace = '$Memory["mark"] = $mark' }
        @{ Name = "a-line-said-every-turn"
           Find = 'if ($text -cne "$($Memory[''said''])") { $new = $said }'
           Replace = '$new = $said' }
        @{ Name = "a-refused-settings-file-routes-anyway"
           Find = 'if ($settings.state -ceq "refused") {'
           Replace = 'if ($false) {' }
        # --- an Orc seat that cannot be proven now is waited for (review of 2026-10-16)
        @{ Name = "an-unprovable-seat-falls-back-at-once"
           Find = 'if ($waited -lt $SeatGraceSeconds) {'
           Replace = 'if ($false) {' }
        @{ Name = "an-unprovable-seat-is-waited-for-ever"
           Find = 'if ($waited -lt $SeatGraceSeconds) {'
           Replace = 'if ($true) {' }
        @{ Name = "an-absent-seat-is-treated-as-unprovable"
           Find = '$seatState = $(if ($null -ne $found -and "$($found.state)" -ceq "absent") { "absent" } else { "unknown" })'
           Replace = '$seatState = "unknown"' }
        @{ Name = "the-pending-line-says-it-went-to-the-warchief"
           Find = '$target.seatWhy + "); waiting up to "'
           Replace = '$target.note + "); waiting up to "' }
        @{ Name = "a-reminder-without-his-words"
           Find = '@(([string]$m.text) -split "\r?\n")) { [void]$lines.Add("  " + $l) }'
           Replace = '@(([string]$(if ($Item.purpose -ceq "answer") { $m.text } else { "" })) -split "\r?\n")) { [void]$lines.Add("  " + $l) }' }
        @{ Name = "the-analyst-blames-the-asker-for-a-missing-seat"
           Find = 'elseif ("$($Target.asker)" -ceq "orc")'
           Replace = 'elseif ($false)' }
    )
}
