# Mutations of cli/RelayDeploy.ps1, the command's side of `horde relay deploy`. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-relay-deploy-cli.psd1
# relays\cloudflare\test\test-cloudflare-deploy.ps1 must fail for every one. Every find string occurs once.
# (The spec lives with the hosted relay because its suite is the one that drives the command.)
@{
    Target = "cli\RelayDeploy.ps1"
    Suite  = "relays\cloudflare\test\test-cloudflare-deploy.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "app-built-for-a-demonstration"
           Find = '-Transport "http" -RelayOrigin ""'
           Replace = '-Transport "memory" -RelayOrigin ""' }
        @{ Name = "relay-that-cannot-deploy-taken"
           Find = 'if ($can -cnotcontains $Relay) {'
           Replace = 'if ($false) {' }
        @{ Name = "built-site-kept"
           Find = 'if ($work -like "*horde-relay-deploy-*" -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }'
           Replace = '' }
    )
}
