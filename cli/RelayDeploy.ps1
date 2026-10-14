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
# ONE DEPLOY AT A TIME, A HOME (2026-10-14). The supervisor's pass now deploys the phone page by itself
# (cli/RelayPublish.ps1), and a person may run this command at the same moment: two deploys would race
# each other's secrets and versions. So every deploy holds <home>\relay\deploy.lock - an open file,
# which the operating system lets go of however the process ends, as the tend's own lock is
# (core/ServicesFiles.ps1) - from before the site is built to after the record is written, and a second
# deploy is refused at once, with the reason Get-HordeRelayDeployBusyReason gives, never queued.
#
# WHAT WAS DEPLOYED IS RECORDED, by whoever deployed it. After a deploy the relay confirmed, this writes
# <home>\relay\deployed.json: { schemaVersion; commit; clean; version; relay; origin; at }. commit is
# the revision of the checkout the site was built from and clean whether that checkout had changes of
# its own (-Revision says; with none, the commit is "", which nothing reads as a base); version is the
# app's VERSION as built; origin is where the relay said it answers. The supervisor compares commit with
# the checkout to decide whether the page is behind (cli/RelayPublish.ps1), so a deploy by hand and one
# by the supervisor keep the one record, and agree. A deploy that failed writes nothing: the record says
# what is live, as far as anyone here knows.
#
# No Set-StrictMode here: dot-sourced. Requires relays/Port.ps1 and the relays loaded.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "surfaces\pwa\Site.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\FileAtomic.ps1")

$script:HordeRelayDeployBusyReason = "another deploy of the relay is running on this Horde home; this one did nothing"
$script:HordeRelayDeployedSchemaVersion = 1
$script:HordeRelayDeployedMaxBytes = 4096

function Get-HordeRelayDeployBusyReason { return $script:HordeRelayDeployBusyReason }

function Get-HordeRelayDeploySiteSources {
    # Site path -> repository path of every file the deployed site serves (Site.ps1's list): what the
    # supervisor's check asks the hosted relay for after a deploy.
    return (Get-HordePwaSiteFiles)
}

function Get-HordeRelayDeployBuildFiles {
    # The code that builds the site, as repository paths: this file, Site.ps1 and the files each
    # dot-sources (the lines at the top of each). A change to any of them can change every built file, so
    # the supervisor counts it as the page (cli/RelayPublish.ps1); test/test-relay-publish.ps1 reads the
    # dot-source lines of these files and fails when one is missing here.
    return @("cli/RelayDeploy.ps1", "surfaces/pwa/Site.ps1", "core/Tristate.ps1", "core/FileAtomic.ps1")
}

function Get-HordeRelayDeploySiteHashes {
    # Site path -> SHA-256 (lower-case hex) of each built file under -Out: what the supervisor's check
    # compares the hosted bytes with, since the built folder is gone once the deploy ends.
    param([Parameter(Mandatory = $true)][string]$Out, [string[]]$Files = @())
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $h = @{}
        foreach ($f in @($Files)) { $h[$f] = (($sha.ComputeHash([System.IO.File]::ReadAllBytes((Join-Path $Out ("" + $f).Replace('/', [System.IO.Path]::DirectorySeparatorChar)))) | ForEach-Object { $_.ToString("x2") }) -join "") }
        return $h
    } finally { $sha.Dispose() }
}

function Get-HordeRelayDeployFolder {
    param([string]$HordeHome = "")
    if ($HordeHome -eq "") { $HordeHome = Get-HordeHome }
    return [System.IO.Path]::Combine($HordeHome, "relay")
}

function Get-HordeRelayDeployedPath { param([string]$HordeHome = "") return [System.IO.Path]::Combine((Get-HordeRelayDeployFolder -HordeHome $HordeHome), "deployed.json") }

function Enter-HordeRelayDeployLock {
    # The open lock (header, ONE DEPLOY AT A TIME), for the caller to dispose, or $null when another
    # deploy holds it. Never waits: a deploy is minutes, and nobody should stand behind one.
    param([string]$HordeHome = "")
    $path = [System.IO.Path]::Combine((Get-HordeRelayDeployFolder -HordeHome $HordeHome), "deploy.lock")
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path))
    try { return (New-Object System.IO.FileStream -ArgumentList $path, ([System.IO.FileMode]::OpenOrCreate), ([System.IO.FileAccess]::ReadWrite), ([System.IO.FileShare]::None)) }
    catch [System.IO.IOException] { return $null }
}

function Read-HordeRelayDeployed {
    # The record of the last deploy (header): known { commit; clean; version; relay; origin; at }, absent
    # when no deploy here has written one, unknown when the file is not one this wrote.
    param([string]$HordeHome = "")
    $path = Get-HordeRelayDeployedPath -HordeHome $HordeHome
    if (-not [System.IO.File]::Exists($path)) { return (New-HordeAbsent -Note "no deploy on this Horde home has recorded what it deployed") }
    $r = $null
    try {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        if ($bytes.Length -gt $script:HordeRelayDeployedMaxBytes) { return (New-HordeUnknown -Reason ("the deploy record " + $path + " is larger than one is")) }
        $r = [System.Text.Encoding]::ASCII.GetString($bytes) | ConvertFrom-Json
    } catch { return (New-HordeUnknown -Reason ("the deploy record " + $path + " could not be read") -ErrorRecord $_) }
    $ok = ($null -ne $r -and $r.schemaVersion -eq $script:HordeRelayDeployedSchemaVersion -and ("" + $r.commit) -cmatch '\A([0-9a-f]{40})?\z' -and $r.clean -is [bool] -and ("" + $r.origin) -cmatch '\Ahttps://[a-z0-9.-]+(:[0-9]{1,5})?\z')
    $at = [datetime]::MinValue
    if ($ok) { $ok = [datetime]::TryParseExact(("" + $r.at), "yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture, ([System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal), [ref]$at) }
    if (-not $ok) { return (New-HordeUnknown -Reason ("the deploy record " + $path + " is not one a deploy wrote")) }
    return (New-HordeKnown -Value ([pscustomobject]@{ commit = "" + $r.commit; clean = [bool]$r.clean; version = "" + $r.version; relay = "" + $r.relay; origin = "" + $r.origin; at = $at }))
}

function Write-HordeRelayDeployed {
    # Replace the record whole (core/FileAtomic.ps1). -Revision is { commit; clean }, or $null: unknown.
    param([string]$HordeHome = "", $Revision = $null, [Parameter(Mandatory = $true)][string]$Version, [Parameter(Mandatory = $true)][string]$Relay, [Parameter(Mandatory = $true)][string]$Origin, [Parameter(Mandatory = $true)][datetime]$At)
    $commit = ""; $clean = $false
    if ($null -ne $Revision -and ("" + $Revision.commit) -cmatch '\A[0-9a-f]{40}\z') { $commit = "" + $Revision.commit; $clean = [bool]($Revision.clean -eq $true) }
    $path = Get-HordeRelayDeployedPath -HordeHome $HordeHome
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path))
    # At is written as given: a [datetime] of unspecified kind is taken as UTC, as every clock here is.
    $text = ConvertTo-Json -InputObject ([ordered]@{ schemaVersion = $script:HordeRelayDeployedSchemaVersion; commit = $commit; clean = $clean; version = $Version; relay = $Relay; origin = $Origin; at = $At.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture) })
    $temp = $path + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    [System.IO.File]::WriteAllText($temp, $text, [System.Text.Encoding]::ASCII)
    try { Move-HordeFileAtomic -From $temp -To $path }
    catch { try { [System.IO.File]::Delete($temp) } catch { }; throw }
}

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
    # Build the app and deploy relay -Relay with it: known { relay; origin; version; hashes } or unknown
    # with the reason; hashes is each built file's (Get-HordeRelayDeploySiteHashes). The built site is
    # the run's own temporary folder, deleted at the end whatever happened.
    # Under the deploy lock, and recorded when it worked (header). -Revision: the checkout's { commit;
    # clean }, read by the caller BEFORE this is called, so the record never names a revision newer than
    # the files the build reads; $null records the commit as unknown. -Now: the clock of the record.
    param([string]$Relay = "", [scriptblock]$Say = { param($Line) }, [string]$HordeHome = "", $Revision = $null, [scriptblock]$Now = { [datetime]::UtcNow })
    $target = Resolve-HordeRelayDeployTarget -Relay $Relay
    if ($target.state -cne "known") { return $target }
    $lock = Enter-HordeRelayDeployLock -HordeHome $HordeHome
    if ($null -eq $lock) { return (New-HordeUnknown -Reason $script:HordeRelayDeployBusyReason) }
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-relay-deploy-" + [guid]::NewGuid().ToString("N").Substring(0, 12))
    try {
        $site = New-HordeRelayDeploySite -Out (Join-Path $work "site")
        if ($site.state -cne "known") { return (New-HordeUnknown -Reason ("the phone app could not be built: " + $site.reason)) }
        & $Say ("built the phone app (version " + $site.value.version + ") for relay " + $target.value)
        $hashes = Get-HordeRelayDeploySiteHashes -Out $site.value.out -Files @($site.value.files)
        $done = Publish-HordeRelay -Name $target.value -Site $site.value.out -Say $Say -HordeHome $HordeHome
        if ($done.state -cne "known") { return $done }
        try { Write-HordeRelayDeployed -HordeHome $HordeHome -Revision $Revision -Version $site.value.version -Relay $done.value.relay -Origin $done.value.origin -At (& $Now) }
        catch { & $Say ("note: the deploy worked, but its record could not be written: " + $_.Exception.Message) }
        return (New-HordeKnown -Value ([pscustomobject]@{ relay = $done.value.relay; origin = $done.value.origin; version = $site.value.version; hashes = $hashes }))
    } finally {
        if ($work -like "*horde-relay-deploy-*" -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
        $lock.Dispose()
    }
}
