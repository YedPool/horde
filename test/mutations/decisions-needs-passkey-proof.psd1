# Mutations of channels/decisions/Answer.ps1's proof that a passkey signed an answer (audit of
# 2026-10-16, item 17: the passkey rule for production actions). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-needs-passkey-proof.psd1
# Each lets an answer stand that no trusted passkey signed, as it reads; test\test-decisions-needs-passkey.ps1
# must fail for every one.
@{
    Target = "channels\decisions\Answer.ps1"
    Suite  = "test\test-decisions-needs-passkey.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "no-evidence-goes-on-to-the-trust-store"
           Find = "        if (`$Evidence -cnotmatch '\A[0-9a-f]{64}\z' -or `$SignedBy -cnotmatch '\A[0-9a-f]{32}\z') {"
           Replace = "        if (`$false) {" }
        @{ Name = "a-revoked-passkey-still-counts"
           Find = '        if ($sender.state -cne "known") {'
           Replace = '        if ($false) {' }
        @{ Name = "any-journal-record-is-the-evidence"
           Find = '-Bytes (Get-HordeRelayAsciiBytes -Text $r.whole))) -ceq $Evidence) {'
           Replace = '-Bytes (Get-HordeRelayAsciiBytes -Text $r.whole))) -ceq $Evidence -or $true) {' }
        @{ Name = "a-session-signature-counts-as-a-passkey"
           Find = '        if ("$($env.value.sig.alg)" -cne "webauthn.get") {'
           Replace = '        if ($false) {' }
        @{ Name = "a-signature-that-does-not-verify-counts"
           Find = '        if (-not $opened.ok) {'
           Replace = '        if ($false) {' }
        @{ Name = "a-body-that-is-no-answer-counts"
           Find = '        if (-not $body.ok) {'
           Replace = '        if ($false) {' }
        @{ Name = "another-machines-answer-counts"
           Find = '        if ($b.machine -cne $opening.value.signKeyId) {'
           Replace = '        if ($false) {' }
        @{ Name = "an-answer-to-another-question-counts"
           Find = '        if ($b.number -ne $Number) {'
           Replace = '        if ($false) {' }
        @{ Name = "other-words-count"
           Find = '        if ($b.text -cne $Text) {'
           Replace = '        if ($false) {' }
        @{ Name = "an-answer-to-a-part-counts-for-the-whole"
           Find = '        if ($b.part -cne $Part) {'
           Replace = '        if ($false) {' }
        @{ Name = "an-answer-to-an-old-wording-counts"
           Find = '        if ($b.wordingVersion -ne $WordingVersion) {'
           Replace = '        if ($false) {' }
        @{ Name = "an-old-answer-replayed-under-a-new-id-counts"
           Find = '        if ((Get-HordeDecisionsChannelAnswerId -From $SignedBy -AnswerId $b.answerId) -cne $Id) {'
           Replace = '        if ($false) {' }
        # --- a check that cannot be made is a no (review of PR 324) ---
        @{ Name = "a-check-that-throws-is-a-yes"
           Find = '        return (& $no ("it could not be checked: " + $_.Exception.Message))'
           Replace = '        return [pscustomobject]@{ ok = $true; reason = ""; keyId = $SignedBy; signedAt = [long]0 }' }
        @{ Name = "keys-that-do-not-open-are-not-asked"
           Find = '        if ($opening.state -cne "known") {'
           Replace = '        if ($false) {' }
        @{ Name = "a-record-with-no-envelope-goes-on"
           Find = '        if (-not $env.ok) {'
           Replace = '        if ($false) {' }
        @{ Name = "a-damaged-record-on-the-way-is-stepped-over"
           Find = '        if (-not $r.ok) { return (& $none ("the journal''s stream of that passkey is damaged: " + $r.reason)) }'
           Replace = '        if (-not $r.ok) { continue }' }
        # --- a later answer in the journal (reviews of PR 324: M2, and the second review's 2, 3 and SHOULDs) ---
        @{ Name = "a-later-answer-is-found-and-ignored"
           Find = '            if (-not $later.ok) { return (& $no $later.reason) }'
           Replace = '' }
        @{ Name = "the-journal-is-never-asked-for-a-later-answer"
           Find = '        if ($null -ne $LaterParts -or $LaterAnyPart) {'
           Replace = '        if ($false) {' }
        @{ Name = "every-answer-in-the-journal-is-later"
           Find = '            if ($r.meta.ts -le $After -and $r.meta.recordedAt -le $AfterRecorded) { continue }'
           Replace = '' }
        @{ Name = "a-later-no-from-a-phone-whose-clock-is-behind-is-not-later"
           Find = '            if ($r.meta.ts -le $After -and $r.meta.recordedAt -le $AfterRecorded) { continue }'
           Replace = '            if ($r.meta.ts -le $After) { continue }' }
        @{ Name = "a-later-answer-to-another-part-counts"
           Find = '            if (-not $AnyPart -and @($Parts) -cnotcontains $a.value.part) { continue }'
           Replace = '' }
        @{ Name = "the-whole-question-asked-filters-by-the-unsigned-parts"
           Find = '            if (-not $AnyPart -and @($Parts) -cnotcontains $a.value.part) { continue }'
           Replace = '            if (@($Parts) -cnotcontains $a.value.part) { continue }' }
        @{ Name = "a-later-answer-to-another-question-counts"
           Find = '            if ($a.value.machine -cne $Machine -or $a.value.number -ne $Number) { continue }'
           Replace = '            if ($a.value.machine -cne $Machine) { continue }' }
        @{ Name = "a-later-answer-for-another-machine-counts"
           Find = '            if ($a.value.machine -cne $Machine -or $a.value.number -ne $Number) { continue }'
           Replace = '            if ($a.value.number -ne $Number) { continue }' }
        @{ Name = "the-same-answer-sent-again-is-a-later-one"
           Find = '            if ((Get-HordeDecisionsChannelAnswerId -From $from -AnswerId $a.value.answerId) -ceq $Id) { continue }'
           Replace = '' }
        @{ Name = "a-change-of-rank-is-read-as-an-answer"
           Find = '            if ($r.meta.kind -cne "answer") { continue }'
           Replace = '' }
        @{ Name = "a-later-body-that-does-not-read-is-skipped"
           Find = '            if (-not $a.ok) { return (& $no ("a later envelope in the journal ("'
           Replace = '            if (-not $a.ok) { continue; return (& $no ("a later envelope in the journal ("' }
        @{ Name = "a-later-envelope-that-will-not-open-is-skipped"
           Find = '            if ($null -eq $body) { return (& $no ("a later envelope in the journal ("'
           Replace = '            if ($null -eq $body) { continue; return (& $no ("a later envelope in the journal ("' }
        @{ Name = "a-damaged-later-record-is-skipped"
           Find = '            if (-not $r.ok) { return (& $no ("the journal''s decisions stream from " + $from + " is damaged: "'
           Replace = '            if (-not $r.ok) { continue; return (& $no ("the journal''s decisions stream from " + $from + " is damaged: "' }
        @{ Name = "a-stream-that-cannot-be-read-is-skipped"
           Find = '        if (-not $st.ok) { return (& $no ("the journal''s decisions stream from "'
           Replace = '        if (-not $st.ok) { continue; return (& $no ("the journal''s decisions stream from "' }
        @{ Name = "a-folder-the-journal-never-makes-is-skipped"
           Find = '        if ($nm -cnotmatch $script:HordeRelayJournalSenderDirPattern) { return (& $no'
           Replace = '        if ($nm -cnotmatch $script:HordeRelayJournalSenderDirPattern) { continue; return (& $no' }
    )
}
