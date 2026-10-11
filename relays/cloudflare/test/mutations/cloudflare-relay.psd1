# Mutations of the machine's adapter for the hosted relay (relays/cloudflare/Relay.ps1). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-relay.psd1
# relays\cloudflare\test\test-cloudflare-worker.ps1 must fail for every one (it drives the adapter
# against a local dev of the Worker, beside what the conformance suite does). Every find string occurs once.
@{
    Target = "relays\cloudflare\Relay.ps1"
    Suite  = "relays\cloudflare\test\test-cloudflare-worker.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "quotes-not-escaped"
           Find = 'return (''"'' + $Text.Replace(''\'', ''\\'').Replace(''"'', ''\"'') + ''"'')'
           Replace = 'return (''"'' + $Text + ''"'')' }
        @{ Name = "refusal-status-lost"
           Find = 'return (New-HordeUnknown -Reason ("the relay answered the " + $What + " with " + $code + ": " + (Get-HordeCloudflareRelayWords $words)))'
           Replace = 'return (New-HordeUnknown -Reason ("the relay refused the " + $What))' }
        @{ Name = "no-default-origin"
           Find = 'if ($null -eq $origin -or "$origin" -eq "") { $origin = (Get-HordeCloudflareRelayDeployment).origin }'
           Replace = '' }
        @{ Name = "request-not-signed"
           Find = 'if ($State.authorization -ne "") { [void]$req.Headers.TryAddWithoutValidation("Authorization", $State.authorization) }'
           Replace = '' }
        @{ Name = "watch-not-signed"
           Find = 'if ($State.authorization -ne "") { $socket.Options.SetRequestHeader("Authorization", $State.authorization) }'
           Replace = '' }
    )
}
