# Mutations of the relay's owners as the deploy writes and guards them (relays/cloudflare/Owners.ps1).
# Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-owners.psd1
# relays\cloudflare\test\test-cloudflare-deploy.ps1 (a fake wrangler and a stub live relay only) must fail
# for every one. Every find string occurs once.
@{
    Target = "relays\cloudflare\Owners.ps1"
    Suite  = "relays\cloudflare\test\test-cloudflare-deploy.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "anything-taken-as-an-owner"
           Find = 'elseif ($lower -cmatch $script:HordeCloudflareRelayAllowlistEmail) { if (-not $emails.Contains($lower))'
           Replace = 'elseif ($true) { if (-not $emails.Contains($lower))' }
        @{ Name = "no-most-owners"
           Find = 'if ($count -gt $script:HordeCloudflareRelayOwnersMax) {'
           Replace = 'if ($false) {' }
        @{ Name = "emails-keep-their-case"
           Find = 'if (-not $emails.Contains($lower)) { [void]$emails.Add($lower) }'
           Replace = 'if (-not $emails.Contains($e)) { [void]$emails.Add($e) }' }
        @{ Name = "live-owners-ignored"
           Find = 'if ($live.state -ceq "known" -and $live.value.owners -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "unknown-read-as-none"
           Find = 'if ($live.state -ceq "unknown") { return (New-HordeUnknown -Reason ($live.reason + ", and the setting'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ($live.reason + ", and the setting' }
        @{ Name = "opt-out-asks-anyway"
           Find = 'if ($Owners.mode -ceq "none") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "status-says-shared-for-owners"
           Find = 'if ($live.state -ceq "absent" -or (-not $live.value.reserve)) {'
           Replace = 'if ($true) {' }
    )
}
