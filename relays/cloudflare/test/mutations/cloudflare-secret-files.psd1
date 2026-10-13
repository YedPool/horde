# Mutations of which files hold the hosted relay's secrets (relays/cloudflare/SecretFiles.ps1). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-secret-files.psd1
# Each forgets a file, looks in the wrong place, or answers where it should say it cannot tell, and
# relays\cloudflare\test\test-cloudflare-secret-files.ps1 must fail for every one. Every find string
# occurs once. That the block is handed the home it was asked about is
# cloudflare-secret-files-home.psd1's, whose target is Relay.ps1.
@{
    Target = "relays\cloudflare\SecretFiles.ps1"
    Suite  = "relays\cloudflare\test\test-cloudflare-secret-files.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "client-file-not-named"
           Find = '[void]$files.Add([pscustomobject]@{ path = $clientFile; what = $script:HordeCloudflareRelayClientFileWhat })'
           Replace = '' }
        @{ Name = "login-not-named"
           Find = 'foreach ($p in @($login.value)) {'
           Replace = 'foreach ($p in @()) {' }
        @{ Name = "login-called-the-client-file"
           Find = 'what = $script:HordeCloudflareRelayLoginFileWhat })'
           Replace = 'what = $script:HordeCloudflareRelayClientFileWhat })' }
        @{ Name = "refused-settings-read-as-none"
           Find = 'if ($set.state -cne "known") { return (New-HordeUnknown -Reason ("the hosted relay''s settings do not read: " + $set.reason)) }'
           Replace = 'if ($set.state -cne "known") { $set = New-HordeKnown -Value ([pscustomobject]@{ googleClientFile = "" }) }' }
        @{ Name = "relative-client-file-named"
           Find = 'if (-not (Test-HordeModuleSettingFolder -Path $clientFile)) {'
           Replace = 'if ($false) {' }
        @{ Name = "no-profile-not-said"
           Find = 'if ($clientFile -eq "") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "login-that-cannot-be-placed-ignored"
           Find = 'if ($login.state -cne "known") { return $login }'
           Replace = 'if ($login.state -cne "known") { $login = New-HordeKnown -Value @() }' }
        @{ Name = "login-with-no-profile-placed"
           Find = 'if (-not (Test-HordeModuleSettingFolder -Path $UserProfile)) {'
           Replace = 'if ($false) {' }
        @{ Name = "relative-configuration-folder-believed"
           Find = 'if (-not (Test-HordeModuleSettingFolder -Path $config)) {'
           Replace = 'if ($false) {' }
        @{ Name = "encrypted-login-forgotten"
           Find = '$script:HordeCloudflareRelayLoginNames = @("config\default.toml", "config\default.enc")'
           Replace = '$script:HordeCloudflareRelayLoginNames = @("config\default.toml")' }
        @{ Name = "logins-older-place-forgotten"
           Find = 'foreach ($folder in @([System.IO.Path]::Combine($UserProfile, $script:HordeCloudflareRelayLoginFolder), '
           Replace = 'foreach ($folder in @(' }
        @{ Name = "logins-newer-place-forgotten"
           Find = ', [System.IO.Path]::Combine($config, $script:HordeCloudflareRelayLoginFolder))) {'
           Replace = ')) {' }
        @{ Name = "configuration-folder-of-the-environment-ignored"
           Find = '$config = $XdgConfigHome'
           Replace = '$config = ""' }
        @{ Name = "roaming-folder-of-the-environment-ignored"
           Find = '$roaming = $(if ($AppData -ne "") { $AppData } else {'
           Replace = '$roaming = $(if ($false) { $AppData } else {' }
        @{ Name = "joined-by-looking-for-the-drive"
           Find = '$config = [System.IO.Path]::Combine($roaming, "xdg.config")'
           Replace = '$config = Join-Path $roaming "xdg.config"' }
    )
}
