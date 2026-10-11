# Mutations of how a machine signs its requests to the hosted relay (relays/cloudflare/RequestSigner.ps1,
# relay PR 8b). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-request-signer.psd1
# relays\cloudflare\test\test-cloudflare-accounts.ps1 must fail for every one: what this file writes is
# sent to the real Worker there. Every find string occurs once.
#
# NOT HERE, and why: closing the agreement key Open-HordeCloudflareRelaySigner does not need (a handle
# left open changes nothing a request can show).
@{
    Target = "relays\cloudflare\RequestSigner.ps1"
    Suite  = "relays\cloudflare\test\test-cloudflare-accounts.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "another-domain"
           Find = '$script:HordeCloudflareRelayRequestDomain = "horde-relay/request/v1`n"'
           Replace = '$script:HordeCloudflareRelayRequestDomain = "horde-relay/request/v2`n"' }
        @{ Name = "one-nonce-for-every-request"
           Find = 'if ($Nonce -eq "") { $Nonce = ConvertTo-HordeRelayHex -Bytes (Get-HordeRelayRandomBytes -Count 16) }'
           Replace = 'if ($Nonce -eq "") { $Nonce = "0" * 32 }' }
        @{ Name = "clock-two-minutes-slow"
           Find = 'if ($Time -lt 0) { $Time = [System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }'
           Replace = 'if ($Time -lt 0) { $Time = [System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - 120000 }' }
        @{ Name = "body-not-hashed"
           Find = '$hash = ConvertTo-HordeRelayBase64Url -Bytes (Get-HordeRelaySha256 -Bytes ([byte[]]$Body))'
           Replace = '$hash = ConvertTo-HordeRelayBase64Url -Bytes (Get-HordeRelaySha256 -Bytes ([byte[]]@()))' }
        @{ Name = "method-not-signed"
           Find = '$Origin + "`n" + $Method + "`n" + $Target'
           Replace = '$Origin + "`n" + "GET" + "`n" + $Target' }
    )
}
