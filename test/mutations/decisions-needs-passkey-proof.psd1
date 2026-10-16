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
           Find = '        if ($b.machine -cne $me.value.sign.keyId) {'
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
    )
}
