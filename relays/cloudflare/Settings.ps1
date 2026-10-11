# relays/cloudflare/Settings.ps1 - the hosted relay's settings: core/ModuleSettings.ps1's, module
# relay-cloudflare (<HORDE_HOME>\settings\relay-cloudflare.json). A file that fails its checks refuses
# the deploy in its own words; nothing runs on a setting the founder did not choose.
#
# WHERE THE RELAY IS DEPLOYED IS NOT A SETTING: the Worker's name and its origin are wrangler.json's
# (Wrangler.ps1, Get-HordeCloudflareRelayDeployment), the one place the deploy and the Worker both read.
#
# THE GOOGLE CLIENT FILE IS A PATH, NEVER ITS CONTENTS. The OAuth client JSON Google issues holds the
# client's secret, so it lives in the founder's own folder, outside every repository, and the deploy
# reads it, hands its two values to wrangler through a pipe, and keeps nothing (Deploy.ps1). The default
# is derived from the user's profile when the deploy runs, never written here as a path.
#
# No Set-StrictMode here: dot-sourced.

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\ModuleSettings.ps1")

$script:HordeCloudflareRelaySettings = New-HordeModuleSettings -Module "relay-cloudflare" -Settings @(
    @{ name = "googleClientFile"; kind = "text"; default = ""; min = 0; max = 1024
       what = "The Google OAuth client JSON the deploy reads; empty means .horde-secrets\google-oauth-client.json in the user's profile." },
    @{ name = "wranglerScript"; kind = "text"; default = ""; min = 0; max = 1024
       what = "A wrangler command line (a .js file node runs) to deploy with; empty means the pinned one, installed outside the repository." }
)
# The default client file, under the user's profile.
$script:HordeCloudflareRelayClientFileDefault = ".horde-secrets\google-oauth-client.json"

function Get-HordeCloudflareRelaySettings {
    # The settings: known values, or unknown with the findings of a refused file.
    param([string]$HordeHome = "")
    try {
        $homeDir = $(if ($HordeHome -ne "") { $HordeHome } else { Get-HordeHome })
        $s = Get-HordeModuleSettings -Declaration $script:HordeCloudflareRelaySettings -HordeHome $homeDir
    } catch { return (New-HordeUnknown -Reason "the hosted relay's settings could not be read" -ErrorRecord $_) }
    if ($s.state -ceq "refused") { return (New-HordeUnknown -Reason ($s.findings -join " ")) }
    return (New-HordeKnown -Value $s.values)
}

function Get-HordeCloudflareRelayClientFile {
    # The Google client file the settings name, or the default under the user's profile.
    param($Values)
    if ("" + $Values.googleClientFile -ne "") { return ("" + $Values.googleClientFile) }
    if ("" + $env:USERPROFILE -eq "") { return "" }
    return (Join-Path $env:USERPROFILE $script:HordeCloudflareRelayClientFileDefault)
}
