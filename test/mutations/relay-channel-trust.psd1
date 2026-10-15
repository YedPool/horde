# Mutations of channels/trust/Channel.ps1: a phone announcing its identity key (relay PR 6). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-channel-trust.psd1
# test\test-relay-channels.ps1 must fail for every one.
@{
    Target = "channels\trust\Channel.ps1"
    Suite  = "test\test-relay-channels.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "extra-member-taken"
           Find = 'if ((@($names | Sort-Object) -join ",") -cne (@($script:HordeTrustChannelMembers | Sort-Object) -join ",")) {'
           Replace = 'if ($false) {' }
        @{ Name = "refused-key-retried-for-ever"
           Find = 'if ($added.state -cne "known") { return [pscustomobject]@{ outcome = "refused";'
           Replace = 'if ($added.state -cne "known") { return [pscustomobject]@{ outcome = "retry";' }
        @{ Name = "nothing-taken-in"
           Find = '-Kinds @("phone-key", "session") -Senders "founder"'
           Replace = '-Kinds @() -Senders "founder"' }
    )
}
