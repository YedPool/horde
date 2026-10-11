# relays/cloudflare/Deploy.ps1 - putting the hosted relay on Cloudflare: the Google client's two values
# stored as Worker secrets, then the Worker deployed with the phone app it serves. The relay's -Deploy
# block (Relay.ps1); `horde relay deploy` (cli/RelayDeploy.ps1) builds the app and calls it through the
# port (relays/Port.ps1, Publish-HordeRelay).
#
# THE STEPS, each stopping the deploy when it fails, with nothing done after it:
#   1. the settings (Settings.ps1) and the Google client file they name, read and checked
#      (GoogleClient.ps1) - before wrangler is even looked for, so a missing file costs nothing;
#   2. wrangler: the pinned one (Wrangler.ps1, installed outside the tree when it is not), or the one the
#      setting wranglerScript names;
#   3. the production config, written into a work folder outside the tree (Wrangler.ps1,
#      New-HordeCloudflareRelayConfig), which REFUSES a wrangler.json that carries the test binding;
#   4. `wrangler secret put GOOGLE_CLIENT_ID` and `... GOOGLE_CLIENT_SECRET`, each value written to
#      wrangler's standard input - never an argument (a process list shows those to anyone on the
#      machine), never a file (a file outlives the run, and could be one in the repository);
#   5. `wrangler deploy`.
# Secrets before the deploy, as the founder set it (2026-10-11): a Worker never runs a version that is
# missing them. The work folder is deleted at the end, whatever happened; it never held a secret.
#
# NOTHING SAID HOLDS A SECRET. What wrangler prints is passed on line by line, with both values
# replaced by <redacted> wherever they appear, and a refusal says which step failed and how wrangler
# ended, never what it was given.
#
# The login is the founder's own (`wrangler login`, which nothing here runs): a deploy with no login
# fails at step 4 in wrangler's words.
#
# No Set-StrictMode here: dot-sourced.

. (Join-Path $PSScriptRoot "Wrangler.ps1")
. (Join-Path $PSScriptRoot "Settings.ps1")
. (Join-Path $PSScriptRoot "GoogleClient.ps1")

$script:HordeCloudflareRelaySecretNames = [ordered]@{ GOOGLE_CLIENT_ID = "clientId"; GOOGLE_CLIENT_SECRET = "clientSecret" }
$script:HordeCloudflareRelayDeploySeconds = 600

function Hide-HordeCloudflareRelaySecrets {
    # -Text with every one of -Secrets replaced by <redacted>.
    param([AllowEmptyString()][string]$Text, [string[]]$Secrets)
    $out = $Text
    foreach ($s in $Secrets) { if ("" + $s -ne "") { $out = $out.Replace($s, "<redacted>") } }
    return $out
}

function Get-HordeCloudflareRelayWranglerTail {
    # The last lines wrangler printed, secrets hidden: the words of a failed step.
    param($Run, [string[]]$Secrets)
    $all = (("" + $Run.out) + "`n" + ("" + $Run.err)).Trim()
    $tail = @($all -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -Last 4) -join " | "
    return (Hide-HordeCloudflareRelaySecrets -Text $tail -Secrets $Secrets)
}

function Publish-HordeCloudflareRelay {
    # Deploy the hosted relay serving the app in -Site: known { origin } or unknown with the reason.
    param([Parameter(Mandatory = $true)][string]$Site, [scriptblock]$Say = { param($Line) }, [string]$HordeHome = "")
    $set = Get-HordeCloudflareRelaySettings -HordeHome $HordeHome
    if ($set.state -cne "known") { return $set }
    $clientFile = Get-HordeCloudflareRelayClientFile -Values $set.value
    $client = Read-HordeCloudflareRelayGoogleClient -Path $clientFile -RepoRoot (Get-HordeCloudflareRelayRepoRoot)
    if ($client.state -cne "known") { return $client }
    $secrets = @($client.value.clientId, $client.value.clientSecret)
    & $Say ("read the Google client from " + $clientFile)

    $node = Find-HordeCloudflareRelayNode
    if ($node -eq "") { return (New-HordeUnknown -Reason "node is not installed here (wrangler needs node 22 or later)") }
    $wrangler = "" + $set.value.wranglerScript
    if ($wrangler -eq "") {
        $tools = Install-HordeCloudflareRelayTools
        if ($tools.state -cne "known") { return $tools }
        $wrangler = $tools.value.script
    } elseif (-not (Test-HordeModuleSettingFolder -Path $wrangler) -or -not (Test-Path -LiteralPath $wrangler -PathType Leaf)) {
        return (New-HordeUnknown -Reason ("the setting wranglerScript names no file: '" + $wrangler + "'"))
    }
    $dep = Get-HordeCloudflareRelayDeployment

    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-relay-cf-deploy-" + [guid]::NewGuid().ToString("N").Substring(0, 12))
    [void][System.IO.Directory]::CreateDirectory($work)
    try {
        $cfg = New-HordeCloudflareRelayConfig -Out (Join-Path $work "config") -Site $Site
        if ($cfg.state -cne "known") { return $cfg }
        $quiet = Get-HordeCloudflareRelayQuietEnv -Work $work
        foreach ($name in @($script:HordeCloudflareRelaySecretNames.Keys)) {
            $value = "" + $client.value.($script:HordeCloudflareRelaySecretNames[$name])
            $r = Invoke-HordeCloudflareRelayNode -Node $node -ArgList @($wrangler, "secret", "put", $name, "--config", $cfg.value) -Env $quiet -WorkDir $work -StdIn $value -TimeoutSeconds $script:HordeCloudflareRelayDeploySeconds
            if ($r.timedOut -or $r.code -ne 0) { return (New-HordeUnknown -Reason ("wrangler secret put " + $name + " failed (exit " + $r.code + $(if ($r.timedOut) { ", timed out" } else { "" }) + "): " + (Get-HordeCloudflareRelayWranglerTail -Run $r -Secrets $secrets) + "; nothing was deployed")) }
            & $Say ("stored " + $name + " as a secret of the Worker " + $dep.name)
        }
        $r = Invoke-HordeCloudflareRelayNode -Node $node -ArgList @($wrangler, "deploy", "--config", $cfg.value) -Env $quiet -WorkDir $work -TimeoutSeconds $script:HordeCloudflareRelayDeploySeconds
        foreach ($l in @(("" + $r.out) -split "`r?`n" | Where-Object { $_.Trim() -ne "" })) { & $Say ("  " + (Hide-HordeCloudflareRelaySecrets -Text $l -Secrets $secrets)) }
        if ($r.timedOut -or $r.code -ne 0) { return (New-HordeUnknown -Reason ("wrangler deploy failed (exit " + $r.code + $(if ($r.timedOut) { ", timed out" } else { "" }) + "): " + (Get-HordeCloudflareRelayWranglerTail -Run $r -Secrets $secrets))) }
        # SIGN-IN'S RETURN ADDRESS (8b) must be registered with Google, or Google refuses the sign-in.
        $callback = $dep.origin + $dep.callback
        if (@($client.value.redirectUris) -cnotcontains $callback) { & $Say ("note: the Google client does not list " + $callback + " among its redirect addresses; add it in the Google Cloud console before sign-in is used") }
        return (New-HordeKnown -Value ([pscustomobject]@{ origin = $dep.origin }))
    } finally {
        if ($work -like "*horde-relay-cf-deploy-*" -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
