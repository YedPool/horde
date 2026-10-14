# Mutations of where a home's hosted relay answers (relays/cloudflare/Settings.ps1,
# Get-HordeCloudflareRelayDeployment). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-settings-origin.psd1
# relays\cloudflare\test\test-cloudflare-deploy.ps1 (a fake wrangler only) must fail for every one.
# Every find string occurs once.
@{
    Target = "relays\cloudflare\Settings.ps1"
    Suite  = "relays\cloudflare\test\test-cloudflare-deploy.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "home-origin-ignored"
           Find = 'if (-not $chosen) { $origin = "" + $cfg.vars.HORDE_RELAY_ORIGIN }'
           Replace = '$origin = "" + $cfg.vars.HORDE_RELAY_ORIGIN' }
        @{ Name = "origin-not-checked"
           Find = 'if (-not $m.Success) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "worker-name-not-the-first-label"
           Find = 'name = $m.Groups[1].Value'
           Replace = 'name = "relay"' }
    )
}
