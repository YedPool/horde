# relays/cloudflare/SecretFiles.ps1 - which files on this machine hold the hosted relay's secrets: the
# relay's -SecretFiles block (Relay.ps1; relays/Port.ps1, WHICH FILES ON THIS MACHINE HOLD A RELAY'S
# SECRETS). Sharing a file with a phone asks the port, so that neither of these can be sent off the
# machine by a person who did not know what it was.
#
# THERE ARE THREE: two found by reading every file of this folder on 2026-10-13, and the third added with
# the request metrics on 2026-10-14:
#   1. THE GOOGLE CLIENT FILE (Settings.ps1, GoogleClient.ps1): the OAuth client JSON, which holds the
#      client's secret. Where it is, is the setting googleClientFile, or the default under the user's
#      profile when the setting is empty - resolved by Get-HordeCloudflareRelayClientFile, the one
#      resolver, which the deploy uses too, so what is named here is the very file a deploy would read.
#   2. THE DEPLOY TOOL'S LOGIN. Deploy.ps1 runs wrangler under "the founder's own login (`wrangler
#      login`, which nothing here runs)", and that login is a file: the account's access and refresh
#      tokens, with which anyone can deploy a Worker to the account. It is the tool's file, not ours,
#      so where it is was READ FROM THE PINNED TOOL'S OWN SOURCE (wrangler 4.149.0, wrangler-dist/cli.js,
#      getGlobalConfigPath, xdgConfig and getAuthConfigFilePath) and checked against this box, where
#      the file is at the second place below:
#        <profile>\.wrangler                                   when that folder exists (its older place)
#        <XDG_CONFIG_HOME, or else APPDATA\xdg.config>\.wrangler   otherwise
#      and, inside either, config\default.toml - or config\default.enc when the tool keeps it encrypted.
#      ALL FOUR ARE NAMED, WHETHER OR NOT THEY ARE THERE: the tool picks between the two folders by
#      looking at the disk, and this looks at nothing (the port's rule: paths only) - and naming a file
#      that does not exist costs nothing, while missing the one that does is the leak.
#      WHAT THIS DOES NOT COVER, and says so: a login made under another profile name of the tool's, or
#      against another of the host's environments, is <that name>.toml in the same folder and is not
#      named here; nothing in this folder ever makes one. A new pin of the tool is when to read its
#      source again.
#   3. THE METRICS SALT FILE (Settings.ps1, MetricsSalt.ps1): the salt the relay hashes account ids with
#      in its request metrics (worker/metrics.js). Whoever holds it can tell whose rows are whose, so it is
#      a secret like the client's. The setting metricsSaltFile, or the default under the user's profile,
#      resolved by Get-HordeCloudflareRelayMetricsSaltFile - the deploy's own resolver. Named last.
#
# WHAT IS NOT A SECRET FILE HERE, each looked at: the pinned tool itself and its lock (public); the
# work folders of a deploy and of a local dev (temp, deleted, and the deploy's "never held a secret" -
# its values go down a pipe, Deploy.ps1); wrangler.json and test-bindings.json (committed; the test
# binding is a placeholder); the settings file (it holds the client file's PATH, never its contents).
# This machine's relay keys are not a file at all: relay/Identity.ps1 keeps them non-exportable in the
# key store. Session cookies and the sign-in allowlist live in the Worker, not on this disk.
#
# WINDOWS ONLY, AS THE RESOLVER IS: with no user profile in the environment there is no default client
# file to name (Settings.ps1) and no place to look for the login, so the answer is unknown, never "none".
#
# NOTHING HERE READS, OPENS OR TESTS FOR ANY OF THESE FILES. It reads the relay's settings, and the
# environment.
#
# No Set-StrictMode here: dot-sourced. Test-HordeModuleSettingFolder is the one test of an absolute path.

. (Join-Path $PSScriptRoot "Settings.ps1")

# What each file is, in words for a person. Fixed: nothing of a setting or of a file is ever in them.
$script:HordeCloudflareRelayClientFileWhat = "the sign-in client file"
$script:HordeCloudflareRelayLoginFileWhat = "the deploy tool's login"
$script:HordeCloudflareRelayMetricsSaltFileWhat = "the request metrics salt file"
# The tool's folder, and its login file under each of the two names it may have (the header).
$script:HordeCloudflareRelayLoginFolder = ".wrangler"
$script:HordeCloudflareRelayLoginNames = @("config\default.toml", "config\default.enc")

function Get-HordeCloudflareRelayLoginFiles {
    # Every place the deploy tool may keep its login (the header, 2): known, the paths, or unknown when
    # the environment does not say where. The three parameters are the environment's, for a suite.
    param([string]$UserProfile = ("" + $env:USERPROFILE), [string]$AppData = ("" + $env:APPDATA), [string]$XdgConfigHome = ("" + $env:XDG_CONFIG_HOME))
    if (-not (Test-HordeModuleSettingFolder -Path $UserProfile)) { return (New-HordeUnknown -Reason "there is no user profile in the environment, so where the deploy tool keeps its login is not known") }
    # PATHS ARE JOINED AS TEXT ([System.IO.Path]::Combine), NEVER WITH Join-Path: Join-Path looks for the
    # drive and throws when there is none (measured 2026-10-13: "Cannot find drive. A drive with the
    # name 'E' does not exist"), and a login on a drive that is not there today is still a login.
    $config = $XdgConfigHome
    if ($config -eq "") {
        # The tool's own fallback when APPDATA is not set: AppData\Roaming under the profile.
        $roaming = $(if ($AppData -ne "") { $AppData } else { [System.IO.Path]::Combine($UserProfile, "AppData\Roaming") })
        $config = [System.IO.Path]::Combine($roaming, "xdg.config")
    }
    if (-not (Test-HordeModuleSettingFolder -Path $config)) { return (New-HordeUnknown -Reason "the environment names a configuration folder that is not an absolute path, so where the deploy tool keeps its login is not known") }
    $out = New-Object System.Collections.ArrayList
    foreach ($folder in @([System.IO.Path]::Combine($UserProfile, $script:HordeCloudflareRelayLoginFolder), [System.IO.Path]::Combine($config, $script:HordeCloudflareRelayLoginFolder))) {
        foreach ($name in $script:HordeCloudflareRelayLoginNames) { [void]$out.Add([System.IO.Path]::Combine($folder, $name)) }
    }
    return (New-HordeKnown -Value @($out.ToArray()))
}

function Get-HordeCloudflareRelaySecretFiles {
    # The -SecretFiles block: known { files }, each { path; what } - the Google client file, then every
    # place the deploy tool's login may be - or unknown when the settings do not read, or name a client
    # file that is not an absolute path. Never absent: this relay always has a client file to name.
    param([string]$HordeHome = "")
    $set = Get-HordeCloudflareRelaySettings -HordeHome $HordeHome
    if ($set.state -cne "known") { return (New-HordeUnknown -Reason ("the hosted relay's settings do not read: " + $set.reason)) }
    $clientFile = Get-HordeCloudflareRelayClientFile -Values $set.value
    if ($clientFile -eq "") { return (New-HordeUnknown -Reason "there is no user profile in the environment, so the default Google client file cannot be named") }
    # THE SAME REFUSAL THE DEPLOY MAKES (GoogleClient.ps1), made here without the file: a relative path
    # names a different file from every folder, so no one file can be called the secret.
    if (-not (Test-HordeModuleSettingFolder -Path $clientFile)) { return (New-HordeUnknown -Reason "the Google client file is not an absolute path (the setting googleClientFile), so which file holds the client's secret is not known") }
    # 3. THE METRICS SALT (MetricsSalt.ps1): its own file, resolved by the deploy's own resolver, and
    # refused the same way when the setting is not an absolute path.
    $saltFile = Get-HordeCloudflareRelayMetricsSaltFile -Values $set.value
    if ($saltFile -eq "" -or -not (Test-HordeModuleSettingFolder -Path $saltFile)) { return (New-HordeUnknown -Reason "the metrics salt file is not an absolute path (the setting metricsSaltFile), so which file holds the metrics salt is not known") }
    $login = Get-HordeCloudflareRelayLoginFiles
    if ($login.state -cne "known") { return $login }
    $files = New-Object System.Collections.ArrayList
    [void]$files.Add([pscustomobject]@{ path = $clientFile; what = $script:HordeCloudflareRelayClientFileWhat })
    foreach ($p in @($login.value)) { [void]$files.Add([pscustomobject]@{ path = $p; what = $script:HordeCloudflareRelayLoginFileWhat }) }
    [void]$files.Add([pscustomobject]@{ path = $saltFile; what = $script:HordeCloudflareRelayMetricsSaltFileWhat })
    return (New-HordeKnown -Value ([pscustomobject]@{ files = @($files.ToArray()) }))
}
