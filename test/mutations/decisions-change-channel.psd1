# Mutations of channels/decisions/Channel.ps1 for a CHANGE of the founder's answer from his phone (T-0152): a
# change takes what the first answer takes - a fresh passkey on a needsPasskey question, and the newest
# answer from any route winning. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-change-channel.psd1
# test\test-relay-decisions-change.ps1 must fail for each. Each find string occurs once.
@{
    Target = "channels\decisions\Channel.ps1"
    Suite  = "test\test-relay-decisions-change.ps1"
    Mutations = @(
        @{ Name = "a-session-may-change-an-answer-to-a-needs-passkey-question"
           Find = '    if ($proofSaid -cne "webauthn") {'
           Replace = '    if ($false) {' }
        @{ Name = "an-older-change-stands-over-a-newer-answer"
           Find = '    if ("$($older.value)" -cne "") { return [pscustomobject]@{ outcome = "refused"; reason = $older.value } }'
           Replace = '' }
        @{ Name = "his-chat-words-or-words-after-closing-count-as-the-newest-answer"
           Find = '        if (-not (Test-HordeDecisionMessageAuthorizes -Message $m)) { continue }'
           Replace = '' }
        @{ Name = "a-needs-passkey-refusal-is-final-and-not-listed-apart"
           Find = '            return [pscustomobject]@{ outcome = "refused"; reason = ("needs-passkey: question " + $r.value.number + " is answered only with a fresh passkey'
           Replace = '            return [pscustomobject]@{ outcome = "refused"; reason = ("question " + $r.value.number + " is answered only with a fresh passkey' }
    )
}
