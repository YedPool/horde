# Mutations of reading the Google client file (relays/cloudflare/GoogleClient.ps1). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-google-client.psd1
# relays\cloudflare\test\test-cloudflare-deploy.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "relays\cloudflare\GoogleClient.ps1"
    Suite  = "relays\cloudflare\test\test-cloudflare-deploy.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "file-inside-the-repository-read"
           Find = 'if (Test-HordeCloudflareRelayUnder -Path $Path -Folder $RepoRoot) {'
           Replace = 'if ($false) {' }
        @{ Name = "desktop-client-taken"
           Find = '$web = $parsed.PSObject.Properties["web"]'
           Replace = '$web = @($parsed.PSObject.Properties)[0]' }
        @{ Name = "client-id-unchecked"
           Find = '-cnotmatch $script:HordeCloudflareRelayClientIdPattern'
           Replace = '-cnotmatch ''.''' }
        @{ Name = "short-secret-taken"
           Find = '[\x21-\x7E]{8,256}'
           Replace = '[\x21-\x7E]{1,256}' }
        @{ Name = "relative-path-taken"
           Find = 'if ($Path -eq "" -or -not (Test-HordeModuleSettingFolder -Path $Path)) {'
           Replace = 'if ($Path -eq "") {' }
    )
}
