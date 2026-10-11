# Mutations of the machine adapter's signing (relays/cloudflare/Relay.ps1, relay PR 8b): with no test
# token, every request is signed by the machine's own key. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-relay-signing.psd1
# relays\cloudflare\test\test-cloudflare-accounts.ps1 must fail for every one: it registers a machine
# and drives this adapter against a local dev of the Worker. Every find string occurs once.
#
# NOT HERE, and why: the check of Options.hordeHome (a suite always names one, and a relative one would
# only fail to open the identity, as an absent one does); and which home the signer opens (a mutant
# that opened the default one would read this user's own Horde home, which no suite may touch).
@{
    Target = "relays\cloudflare\Relay.ps1"
    Suite  = "relays\cloudflare\test\test-cloudflare-accounts.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "empty-authorization-sent-unsigned"
           Find = 'if ($State.authorization -ne "") { return (New-HordeKnown -Value $State.authorization) }'
           Replace = 'if ($true) { return (New-HordeKnown -Value $State.authorization) }' }
        @{ Name = "body-sent-is-not-the-body-signed"
           Find = '$auth = Get-HordeCloudflareRelayAuthorization -State $State -Method $Method -Target $Path -Body $bytes'
           Replace = '$auth = Get-HordeCloudflareRelayAuthorization -State $State -Method $Method -Target $Path' }
        @{ Name = "watch-query-not-signed"
           Find = '$auth = Get-HordeCloudflareRelayAuthorization -State $State -Method "GET" -Target $target'
           Replace = '$auth = Get-HordeCloudflareRelayAuthorization -State $State -Method "GET" -Target ($target -replace ''\?.*'', '''')' }
    )
}
