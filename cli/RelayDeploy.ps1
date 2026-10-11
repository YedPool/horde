# cli/RelayDeploy.ps1 - `horde relay deploy`: build the phone app as the static site a hosted relay serves,
# and hand it to that relay's own deploy (relays/Port.ps1, DEPLOYING).
#
# WHY THE SITE IS BUILT HERE. The relay serves the app and must not name it, and the app talks to the
# relay and must not name it (CONTRIBUTING 14: nothing outside relays/<name>/ names a relay, nothing
# outside surfaces/<name>/ names a surface). This file names neither port's internals beyond the two
# entry points it joins: New-HordePwaSite builds the app, Publish-HordeRelay deploys whichever relay.
#
# THE APP IS BUILT FOR ITS OWN ORIGIN: the http transport with no relay origin, because the hosted relay
# serves the app and its mailbox API from one origin (relays/<name>/ says where). Its policy line then
# allows connections to its own origin only.
#
# WHICH RELAY: -Relay names it; with none, the one loaded relay that can be deployed, and a refusal when
# there is none or more than one, so a deploy never goes somewhere the founder did not mean.
#
# No Set-StrictMode here: dot-sourced. Requires relays/Port.ps1 and the relays loaded.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "surfaces\pwa\Site.ps1")

function New-HordeRelayDeploySite {
    # The phone app as a hosted relay serves it, built into -Out: Site.ps1's answer.
    param([Parameter(Mandatory = $true)][string]$Out)
    return (New-HordePwaSite -Out $Out -Transport "http" -RelayOrigin "")
}

function Resolve-HordeRelayDeployTarget {
    # The relay to deploy: known name, or unknown with why.
    param([string]$Relay = "")
    $can = @(Get-HordeRelayDeployable)
    if ($Relay -ne "") {
        if ($can -cnotcontains $Relay) { return (New-HordeUnknown -Reason ("relay '" + $Relay + "' cannot be deployed; the relays that can: " + $(if ($can.Count) { $can -join ", " } else { "none" }))) }
        return (New-HordeKnown -Value $Relay)
    }
    if ($can.Count -eq 1) { return (New-HordeKnown -Value $can[0]) }
    if ($can.Count -eq 0) { return (New-HordeUnknown -Reason "no loaded relay can be deployed") }
    return (New-HordeUnknown -Reason ("more than one relay can be deployed (" + ($can -join ", ") + "): name one with -Relay"))
}

function Invoke-HordeRelayDeploy {
    # Build the app and deploy relay -Relay with it: known { relay; origin } or unknown with the reason.
    # The built site is the run's own temporary folder, deleted at the end whatever happened.
    param([string]$Relay = "", [scriptblock]$Say = { param($Line) }, [string]$HordeHome = "")
    $target = Resolve-HordeRelayDeployTarget -Relay $Relay
    if ($target.state -cne "known") { return $target }
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-relay-deploy-" + [guid]::NewGuid().ToString("N").Substring(0, 12))
    try {
        $site = New-HordeRelayDeploySite -Out (Join-Path $work "site")
        if ($site.state -cne "known") { return (New-HordeUnknown -Reason ("the phone app could not be built: " + $site.reason)) }
        & $Say ("built the phone app (version " + $site.value.version + ") for relay " + $target.value)
        return (Publish-HordeRelay -Name $target.value -Site $site.value.out -Say $Say -HordeHome $HordeHome)
    } finally {
        if ($work -like "*horde-relay-deploy-*" -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
