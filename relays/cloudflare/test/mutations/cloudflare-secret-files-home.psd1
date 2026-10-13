# Mutations of the hosted relay's -SecretFiles block where it is handed over (relays/cloudflare/Relay.ps1).
# Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-secret-files-home.psd1
# relays\cloudflare\test\test-cloudflare-secret-files.ps1 must fail for every one. Every find string
# occurs once. What the block answers is cloudflare-secret-files.psd1's, whose target is SecretFiles.ps1.
@{
    Target = "relays\cloudflare\Relay.ps1"
    Suite  = "relays\cloudflare\test\test-cloudflare-secret-files.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "another-homes-settings-read"
           Find = 'return (Get-HordeCloudflareRelaySecretFiles -HordeHome $HordeHome)'
           Replace = 'return (Get-HordeCloudflareRelaySecretFiles -HordeHome "")' }
    )
}
