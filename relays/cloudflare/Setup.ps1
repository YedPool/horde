# relays/cloudflare/Setup.ps1 - where this home's relay answers, and what a home that HOSTS its own
# relay still needs before its first deploy: the relay's -Setup block (relays/Port.ps1, A RELAY THAT IS
# DEPLOYED MAY SAY WHAT A NEW MACHINE STILL NEEDS), which `horde setup` (cli/Setup.ps1) reads.
#
# WHY (2026-10-14). Horde's first person to install it on a fresh machine was stuck: no command said
# what to set up, and the address Google must be told to send a signed-in phone back to was printed
# only after a deploy that worked. Every user shares the shipped relay (the founder's decision of that
# day), so the origin answered is the home's relayOrigin or the shipped one, and the STEPS are the
# operator's (`horde setup -Operator`), in the order a person can take them, each saying what is the
# case and the one thing to do:
#   1. where the relay will answer: the setting relayOrigin (Settings.ps1), set to the operator's own -
#      the shipped relay is not one an operator deploys;
#   2. the Google sign-in client file, read and checked as the deploy reads it (GoogleClient.ps1), with
#      the exact redirect address and JavaScript origin to register beside it, and a warning when the
#      file does not list the redirect address;
#   3. node, which the deploy runs wrangler with (Wrangler.ps1).
# THE STEPS STOP AT THE FIRST ONE NOT DONE: a later one is not even looked at, so a machine with no
# origin chosen never has its client file read, and nothing is said about a step before its turn.
# What cannot be checked from here - the Cloudflare login wrangler keeps for itself - is beforeDeploy.
#
# NOTHING HERE IS A SECRET, AND NOTHING IS DONE: every word is printed. The client file's id and secret
# are read by GoogleClient.ps1, whose answers never hold them, and only its redirect addresses are
# compared here; no file is written, no process started, nothing is asked of the network.
#
# No Set-StrictMode here: dot-sourced by Relay.ps1, after Deploy.ps1 (Settings.ps1, GoogleClient.ps1,
# Wrangler.ps1).

# Where a person finds the account's workers.dev subdomain, and makes the sign-in client: the consoles'
# own menu names, as they were on 2026-10-14.
$script:HordeCloudflareRelaySetupSubdomainWhere = "the Cloudflare dashboard, Workers and Pages, where the account's subdomain is shown as <subdomain>.workers.dev"
$script:HordeCloudflareRelaySetupClientWhere = "the Google Cloud console, APIs and Services, Credentials, Create credentials, OAuth client ID, of type Web application"

function Get-HordeCloudflareRelayWranglerVersion {
    # The wrangler version package.json pins: what `npx wrangler@<version> login` runs.
    $pkg = [System.IO.File]::ReadAllText((Join-Path $script:HordeCloudflareRelayFolder "package.json"), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    return ("" + $pkg.devDependencies.wrangler)
}

function New-HordeCloudflareRelaySetupStep {
    # One step as the port reads it.
    param([string]$Name, [bool]$Done, [string]$Said, [string]$Next = "", [string[]]$Notes = @())
    return [pscustomobject]@{ name = $Name; done = $Done; said = $Said; next = $(if ($Done) { "" } else { $Next }); notes = [string[]]@($Notes) }
}

function Get-HordeCloudflareRelaySetup {
    # The -Setup block: known { origin; steps; beforeDeploy } (the header), or unknown when the home is
    # not one. Reads this home's settings and the client file they name; changes nothing.
    param([string]$HordeHome = "")
    $settingsPath = Get-HordeCloudflareRelaySettingsPath -HordeHome $HordeHome
    $steps = New-Object System.Collections.ArrayList
    $login = "log in to Cloudflare once on this machine, if it has not been: npx wrangler@" + (Get-HordeCloudflareRelayWranglerVersion) + " login (it opens a browser)"
    $answer = { param([string]$Origin) New-HordeKnown -Value ([pscustomobject]@{ origin = $Origin; steps = @($steps.ToArray()); beforeDeploy = $login }) }

    # 1. Where the relay will answer.
    $set = Get-HordeCloudflareRelaySettings -HordeHome $HordeHome
    if ($set.state -cne "known") {
        [void]$steps.Add((New-HordeCloudflareRelaySetupStep -Name "hosted relay settings" -Done $false -Said $set.reason -Next ("correct " + $settingsPath + " as the line above says; every setting it may hold is in relays\cloudflare\Settings.ps1")))
        return (& $answer "")
    }
    $dep = Get-HordeCloudflareRelayDeployment -Values $set.value
    $example = '"relayOrigin": "https://relay.<subdomain>.workers.dev"'
    $write = $(if ([System.IO.File]::Exists($settingsPath)) { "add " + $example + " to the settings in " + $settingsPath } else { "write " + $settingsPath + " as {""schemaVersion"": 1, ""settings"": {" + $example + "}}" })
    $choose = "choose where your relay will answer: find your subdomain in " + $script:HordeCloudflareRelaySetupSubdomainWhere + ", then " + $write
    if ($dep.state -cne "known") {
        # The deploy's own refusal, less its pointer here: this IS horde setup.
        [void]$steps.Add((New-HordeCloudflareRelaySetupStep -Name "relay origin" -Done $false -Said ($dep.reason -replace '; horde setup -Operator says what to set\z', '') -Next $choose))
        return (& $answer "")
    }
    $origin = $dep.value.origin
    if (-not $dep.value.chosen) {
        [void]$steps.Add((New-HordeCloudflareRelaySetupStep -Name "relay origin" -Done $false -Said ("this home uses the shipped relay at " + $origin + ", which every Horde user shares; a home that hosts its own names it in the setting relayOrigin") -Next $choose))
        return (& $answer $origin)
    }
    $callback = $origin + $dep.value.callback
    [void]$steps.Add((New-HordeCloudflareRelaySetupStep -Name "relay origin" -Done $true -Said ("the relay will answer at " + $origin + ", as the Worker " + $dep.value.name)))

    # 2. The Google sign-in client, and what Google must be told.
    $register = "in the Google client, the authorized redirect URI is " + $callback + " and the authorized JavaScript origin is " + $origin
    $clientFile = Get-HordeCloudflareRelayClientFile -Values $set.value
    $client = Read-HordeCloudflareRelayGoogleClient -Path $clientFile -RepoRoot (Get-HordeCloudflareRelayRepoRoot)
    if ($client.state -cne "known") {
        $put = $(if ($clientFile -ne "") { "download its JSON to " + $clientFile + ", outside every repository, or name another file in the setting googleClientFile" } else { "download its JSON outside every repository and name it in the setting googleClientFile" })
        [void]$steps.Add((New-HordeCloudflareRelaySetupStep -Name "Google sign-in client" -Done $false -Said $client.reason -Next ("make the phone's sign-in client in " + $script:HordeCloudflareRelaySetupClientWhere + "; give it the redirect URI and JavaScript origin below; " + $put) -Notes @($register)))
        return (& $answer $origin)
    }
    $notes = @($register)
    if (@($client.value.redirectUris) -cnotcontains $callback) { $notes += ("WARNING: the Google client file does not list " + $callback + " among its redirect URIs, so Google will refuse the phone's sign-in; add it to the client in the Google Cloud console and download the file again") }
    [void]$steps.Add((New-HordeCloudflareRelaySetupStep -Name "Google sign-in client" -Done $true -Said ("the Google client file " + $clientFile + " is a web client") -Notes $notes))

    # 3. The tool the deploy runs.
    $node = Find-HordeCloudflareRelayNode
    if ($node -eq "") {
        [void]$steps.Add((New-HordeCloudflareRelaySetupStep -Name "node" -Done $false -Said "node is not on PATH, and the deploy runs its tools with it" -Next "install Node.js 22 or later from https://nodejs.org, then open a new prompt, so it is on PATH"))
        return (& $answer $origin)
    }
    [void]$steps.Add((New-HordeCloudflareRelaySetupStep -Name "node" -Done $true -Said ("node is installed (" + $node + ")")))
    return (& $answer $origin)
}
