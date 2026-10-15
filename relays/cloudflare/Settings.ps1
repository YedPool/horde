# relays/cloudflare/Settings.ps1 - the hosted relay's settings: core/ModuleSettings.ps1's, module
# relay-cloudflare (<HORDE_HOME>\settings\relay-cloudflare.json). A file that fails its checks refuses
# the deploy in its own words; nothing runs on a setting the founder did not choose.
#
# WHERE THE RELAY ANSWERS: THE SHIPPED RELAY, UNLESS THIS HOME HOSTS ITS OWN (2026-10-14). The shipped
# origin is wrangler.json's: the one relay every Horde user shares, with open sign-up by any Google
# account (the founder's decision of that day). A home that hosts a relay of its own - an operator -
# sets relayOrigin to https://<Worker name>.<account subdomain>.workers.dev; the Worker is then deployed
# under the origin's first label, and the deploy writes the origin into the config it runs with
# (Wrangler.ps1, New-HordeCloudflareRelayConfig -Deployment), which is what the Worker reads.
# Get-HordeCloudflareRelayDeployment is the one answer to "where", for the deploy and for a connection
# with no origin of its own alike, and says whether it was chosen here or shipped.
#
# THE GOOGLE CLIENT FILE IS A PATH, NEVER ITS CONTENTS. The OAuth client JSON Google issues holds the
# client's secret, so it lives in the founder's own folder, outside every repository, and the deploy
# reads it, hands its two values to wrangler through a pipe, and keeps nothing (Deploy.ps1). The default
# is derived from the user's profile when the deploy runs, never written here as a path.
#
# No Set-StrictMode here: dot-sourced.

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\ModuleSettings.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\JsonText.ps1")

$script:HordeCloudflareRelaySettings = New-HordeModuleSettings -Module "relay-cloudflare" -Settings @(
    @{ name = "relayOrigin"; kind = "text"; default = ""; min = 0; max = 200
       what = "Where a home that hosts its own relay has it answer: https://<Worker>.<subdomain>.workers.dev. Empty means the shipped relay all Horde users share." },
    @{ name = "googleClientFile"; kind = "text"; default = ""; min = 0; max = 1024
       what = "The Google OAuth client JSON the deploy reads; empty means .horde-secrets\google-oauth-client.json in the user's profile." },
    @{ name = "wranglerScript"; kind = "text"; default = ""; min = 0; max = 1024
       what = "A wrangler command line (a .js file node runs) to deploy with; empty means the pinned one, installed outside the repository." },
    # SIGN-IN (relay PR 8b, SignInAllowlist.ps1): public by default; true here is the one switch.
    @{ name = "signInAllowlistOn"; kind = "truefalse"; default = $false
       what = "Whether only the accounts in signInAllowlist may sign in to the relay; false lets any Google account sign up." },
    @{ name = "signInAllowlist"; kind = "text"; default = ""; min = 0; max = 4096
       what = "The Google accounts that may sign in once signInAllowlistOn is true: emails and Google account ids, separated by commas." },
    # THE OWNERS (Owners.ps1, worker/budget.js): who may use the relay-wide reserve once the shared day is spent.
    @{ name = "relayOwnerAccounts"; kind = "text"; default = ""; min = 0; max = 4096
       what = "The relay's owners, who alone may use its reserve of requests: emails or Google account ids, by commas; none for no owner. Empty: refused while the live relay has owners." },
    # THE METRICS SALT (MetricsSalt.ps1, worker/metrics.js): a secret file, named here by its path only.
    @{ name = "metricsSaltFile"; kind = "text"; default = ""; min = 0; max = 1024
       what = "The file holding the relay's metrics salt, the Worker secret METRICS_SALT; empty means .horde-secrets\relay-metrics-salt.txt in the user's profile." }
)
# The default client file, under the user's profile.
$script:HordeCloudflareRelayClientFileDefault = ".horde-secrets\google-oauth-client.json"
# The default metrics salt file, under the user's profile.
$script:HordeCloudflareRelayMetricsSaltFileDefault = ".horde-secrets\relay-metrics-salt.txt"
# This folder, for wrangler.json's sign-in return path (Get-HordeCloudflareRelayDeployment).
$script:HordeCloudflareRelaySettingsFolder = $PSScriptRoot
# A deployed origin: https://<Worker name>.<account subdomain>.workers.dev, each label as a Worker
# name and a subdomain may be (lower-case letters, digits and inner hyphens, 63 at most). Group 1 is
# the Worker's name. Nothing else is taken: a custom domain is not something the deploy can set up.
$script:HordeCloudflareRelayOriginSettingPattern = '\Ahttps://([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.workers\.dev\z'

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

function Get-HordeCloudflareRelaySettingsPath {
    # Where this home's settings file for the hosted relay is: a path only, nothing is looked at.
    param([string]$HordeHome = "")
    return (Get-HordeModuleSettingsPath -Declaration $script:HordeCloudflareRelaySettings -HordeHome $HordeHome)
}

function Get-HordeCloudflareRelayDeployment {
    # Where this home's hosted relay answers (the header, WHERE THE RELAY ANSWERS): known { name; origin;
    # callback; chosen }, or unknown with the reason - the settings refused, or an origin a deploy cannot
    # make. chosen is true when the home's relayOrigin names it, false for the shipped relay. -Values are
    # the settings already read; without them they are read from -HordeHome. The callback is the path
    # Google sends a signed-in browser back to, wrangler.json's.
    param([string]$HordeHome = "", $Values = $null)
    if ($null -eq $Values) {
        $set = Get-HordeCloudflareRelaySettings -HordeHome $HordeHome
        if ($set.state -cne "known") { return $set }
        $Values = $set.value
    }
    $cfg = ConvertFrom-HordeJson -Text ([System.IO.File]::ReadAllText((Join-Path $script:HordeCloudflareRelaySettingsFolder "wrangler.json"), [System.Text.Encoding]::UTF8))
    $origin = "" + $Values.relayOrigin
    $chosen = $origin -ne ""
    $what = $(if ($chosen) { "the hosted relay's setting relayOrigin" } else { "wrangler.json's shipped HORDE_RELAY_ORIGIN" })
    if (-not $chosen) { $origin = "" + $cfg.vars.HORDE_RELAY_ORIGIN }
    $m = [regex]::Match($origin, $script:HordeCloudflareRelayOriginSettingPattern)
    if (-not $m.Success) { return (New-HordeUnknown -Reason ($what + " '" + $origin + "' is not https://<Worker name>.<account subdomain>.workers.dev; horde setup -Operator says what to set")) }
    return (New-HordeKnown -Value ([pscustomobject]@{ name = $m.Groups[1].Value; origin = $origin; callback = "" + $cfg.vars.HORDE_RELAY_GOOGLE_CALLBACK; chosen = $chosen }))
}

function Get-HordeCloudflareRelayClientFile {
    # The Google client file the settings name, or the default under the user's profile.
    param($Values)
    if ("" + $Values.googleClientFile -ne "") { return ("" + $Values.googleClientFile) }
    if ("" + $env:USERPROFILE -eq "") { return "" }
    return (Join-Path $env:USERPROFILE $script:HordeCloudflareRelayClientFileDefault)
}

function Get-HordeCloudflareRelayMetricsSaltFile {
    # The metrics salt file the settings name, or the default under the user's profile.
    param($Values)
    if ("" + $Values.metricsSaltFile -ne "") { return ("" + $Values.metricsSaltFile) }
    if ("" + $env:USERPROFILE -eq "") { return "" }
    return (Join-Path $env:USERPROFILE $script:HordeCloudflareRelayMetricsSaltFileDefault)
}
