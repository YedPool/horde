# Mutations of what the decisions receipts tell each passkey of its sessions (channels/decisions/
# Channel.ps1, Get-HordeDecisionsChannelReceipts; T-0177): every passkey trusted now has a session
# member, answers or none, and no other key has one. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-sessions-receipts.psd1
# test\test-relay-sessions.ps1 must fail for every one. Every find string occurs once in the target.
# The receipts' other promises are relay-channel-decisions-receipts.psd1's.
@{
    Target = "channels\decisions\Channel.ps1"
    Suite  = "test\test-relay-sessions.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "a-trusted-passkey-with-no-answers-gets-no-receipt"
           Find = '$Prefer = @(@($Prefer) + @($trusted.Keys))'
           Replace = '$Prefer = @($Prefer)' }
        @{ Name = "a-key-not-trusted-is-told-of-sessions"
           Find = 'if ($trusted.ContainsKey($from) -and $null -ne $sessionRecords -and $sessionRecords.ok) {'
           Replace = 'if ($null -ne $sessionRecords -and $sessionRecords.ok) {' }
        @{ Name = "the-trust-store-is-never-asked"
           Find = 'if ($senders.state -ceq "known") {'
           Replace = 'if ($false) {' }
    )
}
