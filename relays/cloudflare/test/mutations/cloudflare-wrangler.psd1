# Mutations of the hosted relay's tooling (relays/cloudflare/Wrangler.ps1) that the Worker's suite
# holds: the configs it writes. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-wrangler.psd1
# Every find string occurs once.
@{
    Target = "relays\cloudflare\Wrangler.ps1"
    Suite  = "relays\cloudflare\test\test-cloudflare-worker.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "production-config-takes-the-test-binding"
           Find = 'if (Test-HordeCloudflareRelayHasTestBinding -Text $text) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "short-test-token-taken"
           Find = '-cnotmatch ''\A[0-9a-f]{32,}\z'''
           Replace = '-cnotmatch ''\A[0-9a-f]{3,}\z''' }
        @{ Name = "wrangler-json-vars-dropped-in-a-test"
           Find = 'if ($null -ne $cfg.PSObject.Properties["vars"]) { foreach ($p in $cfg.vars.PSObject.Properties) { $vars[$p.Name] = $p.Value } }'
           Replace = '' }
        @{ Name = "app-folder-left-relative"
           Find = '$cfg.assets.directory = & $slash $Site'
           Replace = '$cfg.assets.directory = "site"' }
        @{ Name = "origin-of-another-worker-taken"
           Find = '[regex]::Escape("" + $cfg.name) + ''\.[a-z0-9-]+\.workers\.dev\z'''
           Replace = '''[a-z0-9-]+\.[a-z0-9-]+\.workers\.dev\z''' }
    )
}
