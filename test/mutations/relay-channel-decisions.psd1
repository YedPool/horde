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
           Find = '($script:HordeDecisionsChannelIdDomain + "`n" + $From + "`n" + $AnswerId)'
           Replace = '($script:HordeDecisionsChannelIdDomain + "`n" + $AnswerId)' }
        @{ Name = "evidence-not-the-records"
           Find = 'wordingVersion = $r.value.wordingVersion; evidence = $Item.evidence'
           Replace = 'wordingVersion = $r.value.wordingVersion; evidence = ("0" * 64)' }
        @{ Name = "answer-recorded-as-the-window"
           Find = 'speaker = "founder"; route = "phone"; text = $r.value.text'
           Replace = 'speaker = "founder"; route = "window"; text = $r.value.text' }
        @{ Name = "unreachable-list-refuses-for-good"
           Find = 'if ($a.state -ceq "unknown") { return [pscustomobject]@{ outcome = "retry";'
           Replace = 'if ($a.state -ceq "unknown") { return [pscustomobject]@{ outcome = "refused";' }
        @{ Name = "extra-member-taken"
           Find = 'if ((@($names | Sort-Object) -join ",") -cne (@($script:HordeDecisionsChannelAnswerMembers | Sort-Object) -join ",")) {'
           Replace = 'if ($false) {' }
        # --- out: the snapshot ---
        @{ Name = "secret-sent-to-the-phone"
           Find = '        if (@(Find-HordeDecisionSecrets -Value $q).Count -gt 0) {'
           Replace = '        if ($false) {' }
        @{ Name = "list-read-on-every-look"
           Find = '    if ($print -cne "" -and $print -ceq $mine.fingerprint) { return [pscustomobject]@{ lines = @(); failed = $false } }'
           Replace = '' }
        @{ Name = "same-snapshot-sent-again"
           Find = '    if ($pages.hash -ceq $mine.sent) { $mine.fingerprint = $print; return [pscustomobject]@{ lines = @(); failed = $false } }'
           Replace = '' }
        @{ Name = "snapshot-of-every-question"
           Find = '-Operation "list" -Request @{ state = "open"; messages = $true }'
           Replace = '-Operation "list" -Request @{ state = "all"; messages = $true }' }
        # --- review of 48bc492 ---
        @{ Name = "answer-for-any-machine"
           Find = '    if ($r.value.machine -cne $Context.signKeyId) {'
           Replace = '    if ($false) {' }
        @{ Name = "snapshot-not-asked-of-the-journal"
           Find = '    if (-not $made.value.sent -or $made.value.kind -cne "snapshot" -or -not $r.value.snapshot.StartsWith($Context.signKeyId + "/decisions/")) {'
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
           Find = 'return [pscustomobject]@{ lines = @($what + " recorded; not delivered yet: " + $why); failed = $true }'
           Replace = 'return [pscustomobject]@{ lines = @($what + " recorded; not delivered yet: " + $why); failed = $false }' }
    )
}
