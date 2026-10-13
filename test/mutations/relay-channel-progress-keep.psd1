# Mutations of how the progress channel keeps the phone's mailbox to its last keepEnvelopes
# (channels/progress/Channel.ps1, THE PHONE'S MAILBOX HOLDS THE LAST keepEnvelopes; 2026-10-13). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-channel-progress-keep.psd1
# test\test-relay-channel-progress.ps1 must fail for every one. Every find string occurs exactly once.
# The channel's other promises are relay-channel-progress.psd1's: a spec of their own, so that a review
# round reruns these and not the eighty-odd that were there before them (CONTRIBUTING 15: a change to
# a spec file reruns every mutant of that spec).
@{
    Target = "channels\progress\Channel.ps1"
    Suite  = "test\test-relay-channel-progress.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "progress-envelopes-pile-up-in-the-phones-mailbox"
           Find = '-Mailbox $mailbox -KeepFrom (Get-HordeRelayChannelKeepFrom -Key $key -Keep $keep)'
           Replace = '-Mailbox $mailbox' }
        @{ Name = "keep-envelopes-setting-not-read"
           Find = '$mine["keepEnvelopes"] = [long]$set.keepEnvelopes'
           Replace = '' }
        @{ Name = "keep-envelopes-setting-not-used"
           Find = 'if ($Mine.ContainsKey("keepEnvelopes")) { $keep = [long]$Mine["keepEnvelopes"] }'
           Replace = '' }
    )
}
