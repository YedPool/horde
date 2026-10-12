# Mutations of how the hosted relay's adapter carries a refusal's status and Retry-After
# (relays/cloudflare/Relay.ps1; relays/Port.ps1, A REFUSAL MAY SAY MORE THAN ITS REASON). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-relay-refusals.psd1
# relays\cloudflare\test\test-cloudflare-refusals.ps1 (a stub relay on 127.0.0.1, no node) must fail for
# every one but the one marked. Every find string occurs once.
@{
    Target = "relays\cloudflare\Relay.ps1"
    Suite  = "relays\cloudflare\test\test-cloudflare-refusals.ps1"
    Mutations = @(
        @{ Name = "request-status-not-carried"
           Find = '(Get-HordeCloudflareRelayWords $words))) -Status $code -RetryAfter $retryAfter)'
           Replace = '(Get-HordeCloudflareRelayWords $words))) -Status 0 -RetryAfter $retryAfter)' }
        @{ Name = "request-retry-after-not-read"
           Find = '$retryAfter = $(if ($null -ne $res.Headers.RetryAfter) { "" + $res.Headers.RetryAfter } else { "" })'
           Replace = '$retryAfter = ""' }
        @{ Name = "watch-refusal-not-carried"
           Find = '(Get-HordeCloudflareRelayWords $why.Trim()))) -Status $code -RetryAfter $retryAfter)'
           Replace = '(Get-HordeCloudflareRelayWords $why.Trim()))) -Status 0 -RetryAfter "")' }
        @{ Name = "watch-response-not-read-on-windows-powershell"
           Find = 'try { $code = [int]$resp.Value.StatusCode; $retryAfter = "" + $resp.Value.Headers["Retry-After"] } catch { }'
           Replace = '$null = $resp' }
        @{ Name = "watch-details-not-collected-on-powershell-7"
           Find = 'if ($null -ne $collect) { $socket.Options.CollectHttpResponseDetails = $true }'
           Replace = '$null = $collect'
           Expect = "survives"
           Reason = "Only PowerShell 7 has the option, and tools\Mutate.ps1 runs the suite under Windows PowerShell 5.1, where the inner WebException's response carries the status instead. Measured by hand under pwsh 7.6.6 on 2026-10-11: the suite passes with the line and its watch checks fail without it." }
        @{ Name = "retry-after-seconds-not-ms"
           Find = 'if ($t -cmatch ''\A[0-9]{1,9}\z'') { return ([long]$t * 1000) }'
           Replace = 'if ($t -cmatch ''\A[0-9]{1,9}\z'') { return ([long]$t) }' }
        @{ Name = "retry-after-date-not-read"
           Find = 'if ([datetime]::TryParseExact($t, "r",'
           Replace = 'if ($false -and [datetime]::TryParseExact($t, "r",' }
        @{ Name = "retry-after-nonsense-taken-as-zero"
           Find = '    return [long]-1'
           Replace = '    return [long]0' }
    )
}
