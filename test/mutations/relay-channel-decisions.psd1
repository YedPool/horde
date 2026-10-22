# Mutations of channels/decisions/Channel.ps1: the snapshot out and the answers in (relay PR 6). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-channel-decisions.psd1
# Each breaks one promise to the founder; test\test-relay-channels.ps1 must fail for every one.
@{
    Target = "channels\decisions\Channel.ps1"
    Suite  = "test\test-relay-channels.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # --- in: the answer ---
        @{ Name = "id-not-bound-to-the-sender"
           Find = '($Domain + "`n" + $From + "`n" + $AnswerId)'
           Replace = '($Domain + "`n" + $AnswerId)' }
        @{ Name = "evidence-not-the-records"
           Find = 'wordingVersion = $r.value.wordingVersion; evidence = $Item.evidence'
           Replace = 'wordingVersion = $r.value.wordingVersion; evidence = ("0" * 64)' }
        # Who signed, written once from the verified envelope (2026-10-12).
        @{ Name = "signer-not-written-in-the-record"
           Find = '        signedBy = $Item.from'
           Replace = '' }
        @{ Name = "signer-taken-from-the-answers-own-text"
           Find = '        signedBy = $Item.from'
           Replace = '        signedBy = $r.value.machine' }
        @{ Name = "answer-recorded-as-the-window"
           Find = 'speaker = "founder"; route = "phone"; text = $r.value.text'
           Replace = 'speaker = "founder"; route = "window"; text = $r.value.text' }
        @{ Name = "unreachable-list-refuses-for-good"
           Find = 'if ($a.state -ceq "unknown") { return [pscustomobject]@{ outcome = "retry";'
           Replace = 'if ($a.state -ceq "unknown") { return [pscustomobject]@{ outcome = "refused";' }
        @{ Name = "extra-member-taken"
           Find = 'if ((@($names | Sort-Object) -join ",") -cne (@($members | Sort-Object) -join ",")) {'
           Replace = 'if ($false) {' }
        # --- in: one part's answer, version 2 (2026-10-12) ---
        @{ Name = "a-version-1-answer-must-name-a-part"
           Find = '$script:HordeDecisionsChannelAnswerVersions = [ordered]@{ "1" = @(); "2" = @("part") }'
           Replace = '$script:HordeDecisionsChannelAnswerVersions = [ordered]@{ "1" = @("part"); "2" = @("part") }' }
        @{ Name = "a-version-2-answer-is-not-read"
           Find = '$script:HordeDecisionsChannelAnswerVersions = [ordered]@{ "1" = @(); "2" = @("part") }'
           Replace = '$script:HordeDecisionsChannelAnswerVersions = [ordered]@{ "1" = @() }' }
        @{ Name = "a-version-2-answer-need-name-no-part"
           Find = '$script:HordeDecisionsChannelAnswerVersions = [ordered]@{ "1" = @(); "2" = @("part") }'
           Replace = '$script:HordeDecisionsChannelAnswerVersions = [ordered]@{ "1" = @(); "2" = @() }' }
        @{ Name = "the-part-is-not-handed-to-the-list"
           Find = '    if ($r.value.part -cne "") { $request["part"] = $r.value.part }'
           Replace = '' }
        @{ Name = "a-part-of-any-spelling-is-handed-on"
           Find = "        if (`$a.part -isnot [string] -or `$a.part -cnotmatch '\A[a-z]\z') {"
           Replace = "        if (`$false) {" }
        @{ Name = "the-turn-does-not-say-which-part"
           Find = '$(if ($r.value.part -cne "") { " part (" + $r.value.part + ")" } else { "" })'
           Replace = '""' }
        # --- out: what the snapshot says of answers ---
        @{ Name = "the-snapshot-does-not-say-which-answers-are-read"
           Find = "+ ',`"answers`":' + `$script:HordeDecisionsChannelAnswerHighest + ',`"ranks`":1,`"receipts`":'"
           Replace = "+ ',`"ranks`":1,`"receipts`":'" }
        @{ Name = "the-snapshot-claims-a-version-this-machine-does-not-read"
           Find = '$script:HordeDecisionsChannelAnswerHighest = 2'
           Replace = '$script:HordeDecisionsChannelAnswerHighest = 3' }
        # --- out: the snapshot ---
        @{ Name = "secret-sent-to-the-phone"
           Find = '        if (@(Find-HordeDecisionSecrets -Value $q).Count -gt 0) {'
           Replace = '        if ($false) {' }
        @{ Name = "list-read-on-every-look"
           Find = '    if (-not $onePage -and $print -cne "" -and $print -ceq $mine.fingerprint -and $receipts.text -ceq "$($mine.receipts)" -and $published.text -ceq "$($mine.published)") { return [pscustomobject]@{ lines = @($said.ToArray()); failed = $false } }'
           Replace = '' }
        @{ Name = "same-snapshot-sent-again"
           Find = '    if (-not $onePage -and $sentAs -ceq $mine.sent) { $mine.fingerprint = $print; $mine.receipts = $receipts.text; $mine.published = $published.text; return [pscustomobject]@{ lines = @($said.ToArray()); failed = $false } }'
           Replace = '' }
        @{ Name = "snapshot-of-every-question"
           Find = '-Operation "list" -Request @{ state = "open"; messages = $true }'
           Replace = '-Operation "list" -Request @{ state = "all"; messages = $true }' }
        # --- review of 48bc492 ---
        @{ Name = "answer-for-any-machine"
           Find = '    if ($Machine -cne $Context.signKeyId) {'
           Replace = '    if ($false) {' }
        @{ Name = "snapshot-not-asked-of-the-journal"
           Find = '    if (-not $made.value.sent -or $made.value.kind -cne "snapshot" -or -not $Snapshot.StartsWith($Context.signKeyId + "/decisions/")) {'
           Replace = '    if ($false) {' }
        @{ Name = "snapshot-without-messages"
           Find = '-Operation "list" -Request @{ state = "open"; messages = $true }'
           Replace = '-Operation "list" -Request @{ state = "open"; messages = $false }' }
        @{ Name = "warchiefs-unread-marks-sent"
           Find = '        if ($null -ne $q.thread.PSObject.Properties["messages"]) { foreach ($m in @($q.thread.messages)) { if ($null -ne $m.PSObject.Properties["unreadBy"]) { $m.PSObject.Properties.Remove("unreadBy") } } }'
           Replace = '' }
        @{ Name = "too-large-question-sent-anyway"
           Find = '        if ($s.bytes + $frameBytes -gt $Budget) {'
           Replace = '        if ($false) {' }
        @{ Name = "waiting-envelope-not-put-first"
           Find = '    if ($mine.pending.Count -gt 0) {'
           Replace = '    if ($false) {' }
        @{ Name = "undelivered-snapshot-not-a-failure"
           Find = 'return [pscustomobject]@{ lines = @(@($said.ToArray()) + @($what + " recorded; not delivered yet: " + $why)); failed = $true }'
           Replace = 'return [pscustomobject]@{ lines = @(@($said.ToArray()) + @($what + " recorded; not delivered yet: " + $why)); failed = $false }' }
        # --- the Tick turns the bell (the founder's bug of 2026-10-12)
        @{ Name = "tick-does-not-turn-the-bell"
           Find = '$bell = Invoke-HordeDecisionsChannelBell -Context $Context'
           Replace = '$bell = [pscustomobject]@{ lines = @(); againMs = 0 }' }
        @{ Name = "bell-line-not-said"
           Find = 'if ("$($turn.said)" -cne "") { $lines = @("notify: " + $turn.said) }'
           Replace = 'if ($false) { $lines = @("notify: " + $turn.said) }' }
        @{ Name = "bell-does-not-ask-for-its-turn"
           Find = 'failed = [bool]$out.failed; againMs = $bell.againMs }'
           Replace = 'failed = [bool]$out.failed; againMs = 0 }' }
    )
}
