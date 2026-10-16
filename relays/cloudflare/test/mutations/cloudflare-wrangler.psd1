# Mutations of the hosted relay's tooling (relays/cloudflare/Wrangler.ps1) that the Worker's suite
# holds: the configs it writes. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-wrangler.psd1
# Every find string occurs once.
#
# NOT HERE, and why: the test origin written over HORDE_RELAY_ORIGIN, and its pattern (relay PR 8b). A
# mutant that dropped it would leave a local dev naming the production origin, and a suite that signed
# in there would follow the redirect to the real deployment - which no suite may contact.
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
        @{ Name = "only-the-authenticator-binding-is-test-only"
           Find = '$script:HordeCloudflareRelayTestPrefix = "HORDE_RELAY_TEST_"'
           Replace = '$script:HordeCloudflareRelayTestPrefix = "HORDE_RELAY_TEST_AUTH"' }
        @{ Name = "app-folder-left-relative"
           Find = '$cfg.assets.directory = & $slash $Site'
           Replace = '$cfg.assets.directory = "site"' }
        @{ Name = "production-config-without-a-deployment"
           Find = '-not $isTest -and ($null -eq $Deployment -or'
           Replace = '$false -and ($null -eq $Deployment -or' }
        @{ Name = "production-config-keeps-wrangler-json-name"
           Find = '$cfg.name = "" + $Deployment.name'
           Replace = '$null = $Deployment.name' }
    )
}
