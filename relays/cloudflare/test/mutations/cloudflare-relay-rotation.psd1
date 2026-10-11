# Mutations of what relay PR 8c adds to the machine's adapter (relays/cloudflare/Relay.ps1): a rotated
# identity carried to the relay at the first refusal - of a request or of a watch - once a connection,
# and a watch the relay ended read as a failed watch. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-relay-rotation.psd1
# relays\cloudflare\test\test-cloudflare-limits.ps1 must fail for every one. Every find string occurs once.
#
# NOT HERE, and why: the check that the previous generation's record names this very key as its
# successor and carries a vouch (a record that does not is refused by the relay all the same: the
# mutant only spends one refused request); and the close code read after the watch's ending message
# (the message comes first, so the close is never what the adapter reads: watch-ending-message-ignored
# is the one that shows); and the skip for a first generation (it has no record to carry: the relay
# would find none either way).
@{
    Target = "relays\cloudflare\Relay.ps1"
    Suite  = "relays\cloudflare\test\test-cloudflare-limits.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "request-never-carries-the-rotation"
           Find = 'if ($code -eq 401 -and -not $Once -and (Send-HordeCloudflareRelayRotation -State $State))'
           Replace = 'if ($false -and -not $Once -and (Send-HordeCloudflareRelayRotation -State $State))' }
        @{ Name = "watch-never-carries-the-rotation"
           Find = 'if ($why.Contains("401") -and -not $Once -and (Send-HordeCloudflareRelayRotation -State $State))'
           Replace = 'if ($false -and -not $Once -and (Send-HordeCloudflareRelayRotation -State $State))' }
        @{ Name = "rotation-tried-again-and-again"
           Find = '    $State.rotationTried = $true'
           Replace = '' }
        @{ Name = "run-watch-shortened"
           Find = '$script:HordeCloudflareRelayRunWatchMs = 60000'
           Replace = '$script:HordeCloudflareRelayRunWatchMs = 25000' }
        @{ Name = "run-watch-not-declared"
           Find = '-RunWatchMs $script:HordeCloudflareRelayRunWatchMs'
           Replace = '-RunWatchMs 0' }
        @{ Name = "watch-ending-message-ignored"
           Find = 'if ($null -ne $parsed.PSObject.Properties["error"]) { return (New-HordeUnknown -Reason ("the relay ended the watch: "'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ("the relay ended the watch: "' }
    )
}
