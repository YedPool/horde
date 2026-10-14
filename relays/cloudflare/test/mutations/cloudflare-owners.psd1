# Mutations of the relay's owners the deploy passes (relays/cloudflare/Owners.ps1). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-owners.psd1
# relays\cloudflare\test\test-cloudflare-deploy.ps1 (a fake wrangler only) must fail for every one.
# Every find string occurs once.
@{
    Target = "relays\cloudflare\Owners.ps1"
    Suite  = "relays\cloudflare\test\test-cloudflare-deploy.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "an-email-taken-as-an-owner"
           Find = 'if ($e -cnotmatch $script:HordeCloudflareRelayOwnerSub) {'
           Replace = 'if ($false) {' }
        @{ Name = "no-most-owners"
           Find = 'if ($subs.Count -gt $script:HordeCloudflareRelayOwnersMax) {'
           Replace = 'if ($false) {' }
        @{ Name = "an-owner-given-twice-written-twice"
           Find = 'if (-not $subs.Contains($e)) { [void]$subs.Add($e) }'
           Replace = '[void]$subs.Add($e)' }
        @{ Name = "owners-not-passed"
           Find = 'return @("--var", ($script:HordeCloudflareRelayOwnersBinding + ":" + $Owners))'
           Replace = 'return @()' }
        @{ Name = "an-empty-var-passed-with-none"
           Find = 'if ($Owners -eq "") { return @() }'
           Replace = 'if ($false) { return @() }' }
    )
}
