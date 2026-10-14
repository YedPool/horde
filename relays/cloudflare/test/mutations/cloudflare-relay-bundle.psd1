# Mutations of relays/cloudflare/Bundle.ps1, the Worker bundled offline from a tree. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-relay-bundle.psd1
# relays\cloudflare\test\test-cloudflare-bundle.ps1 must fail for every one.
@{
    Target = "relays\cloudflare\Bundle.ps1"
    Suite  = "relays\cloudflare\test\test-cloudflare-bundle.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "readme-time-hashed"
           Find = 'Where-Object { $script:HordeCloudflareRelayBundleSkip -notcontains $_.Name }'
           Replace = 'Where-Object { $true }' }
        @{ Name = "module-path-lines-hashed"
           Find = 'if ($f.Extension -ceq ".js") {'
           Replace = 'if ($false) {' }
        @{ Name = "test-binding-bundled"
           Find = 'if (Test-HordeCloudflareRelayHasTestBinding -Text $text) {'
           Replace = 'if ($false) {' }
        @{ Name = "tree-config-ignored"
           Find = '$cfg.main = & $slash (Join-Path $folder $cfg.main)'
           Replace = '$cfg.main = & $slash (Join-Path (Join-Path (Get-HordeCloudflareRelayRepoRoot) "relays\cloudflare") $cfg.main)' }
    )
}
