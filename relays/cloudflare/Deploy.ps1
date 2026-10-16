# relays/cloudflare/Deploy.ps1 - putting the hosted relay on Cloudflare: the Google client's two values
# and the sign-in allowlist stored as Worker secrets, then the Worker deployed with the phone app it serves. The relay's -Deploy
# block (Relay.ps1); `horde relay deploy` (cli/RelayDeploy.ps1) builds the app and calls it through the
# port (relays/Port.ps1, Publish-HordeRelay).
#
# THE STEPS, each stopping the deploy when it fails, with nothing done after it:
#   1. the settings (Settings.ps1): where the relay will answer (the home's relayOrigin, or the shipped
#      origin when it is unset; one a deploy cannot make is refused), the Google client file they name,
#      read and checked
#      (GoogleClient.ps1), and the sign-in allowlist they hold (SignInAllowlist.ps1: off unless
#      switched on) - before wrangler is even looked for, so a missing file costs nothing; and every
#      secret's value checked as it will be stored (Test-HordeCloudflareRelaySecretValue);
#   2. wrangler: the pinned one (Wrangler.ps1, installed outside the tree when it is not), or the one the
#      setting wranglerScript names;
#   3. the production config, written into a work folder outside the tree (Wrangler.ps1,
#      New-HordeCloudflareRelayConfig), which REFUSES a wrangler.json that carries a test binding;
#   4. `wrangler secret put GOOGLE_CLIENT_ID`, `... GOOGLE_CLIENT_SECRET` and
#      `... HORDE_RELAY_SIGNIN_ALLOWLIST` (written every time, so switching it off is a deploy too), each value written to
#      wrangler's standard input - never an argument (a process list shows those to anyone on the
#      machine), never a file (a file outlives the run, and could be one in the repository);
#   5. `wrangler deploy`;
#   6. THE CHECK: the deployed relay's own sign-in start (GET <origin>/auth/google, its redirect not
#      followed) must send Google the client file's id, byte for byte, or the deploy is reported failed
#      (Test-HordeCloudflareRelaySignInClient). Measured 2026-10-14: a deploy that "worked" had stored
#      every secret with a byte order mark in front (Wrangler.ps1, Start-HordeCloudflareRelayProcessNoMark),
#      and only the founder's failed sign-in showed it.
# Secrets before the deploy, as the founder set it (2026-10-11): a Worker never runs a version that is
# missing them. The work folder is deleted at the end, whatever happened; it never held a secret.
#
# NOTHING SAID HOLDS A SECRET. What wrangler prints is passed on line by line, with every value
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
. (Join-Path $PSScriptRoot "SignInAllowlist.ps1")

# The Worker's secrets, in the order they are stored, each from the value of that name below (Publish).
$script:HordeCloudflareRelaySecretNames = [ordered]@{ GOOGLE_CLIENT_ID = "clientId"; GOOGLE_CLIENT_SECRET = "clientSecret"; HORDE_RELAY_SIGNIN_ALLOWLIST = "allowlist" }
$script:HordeCloudflareRelayDeploySeconds = 600
# The check after a deploy asks this many times, this far apart, before it calls the deploy failed: a
# Worker just deployed can take a few seconds to answer everywhere. A suite shortens the wait.
# Each try is a real GET /auth/google: it counts toward this machine's address's signInStartsPerMinute
# (10, worker/limits.js) and the relay sets a pending sign-in cookie, which the check discards. 3 is well
# inside that limit.
$script:HordeCloudflareRelayCheckTries = 3
$script:HordeCloudflareRelayCheckWaitMs = 2000

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

function Test-HordeCloudflareRelaySecretValue {
    # Why the secret -Name may not be stored with -Value, or "" when it may. Every value the Worker reads
    # is printable ASCII with nothing around it (a client id, a client secret, the allowlist's JSON), so
    # anything else is a mistake on its way in - a byte order mark (U+FEFF) above all, the incident of
    # 2026-10-14 - and is refused, never stripped: a value mended silently hides how it was broken. The
    # reason names the secret, never its value.
    param([Parameter(Mandatory = $true)][string]$Name, [AllowEmptyString()][string]$Value)
    if ($Value.Length -gt 0 -and $Value[0] -eq [char]0xFEFF) { return ("the value of the secret " + $Name + " begins with a byte order mark (U+FEFF)") }
    foreach ($c in $Value.ToCharArray()) {
        if ([int]$c -lt 0x20 -or [int]$c -gt 0x7E) { return ("the value of the secret " + $Name + " holds a character that is not printable ASCII") }
    }
    if ($Value -cne $Value.Trim()) { return ("the value of the secret " + $Name + " begins or ends with a space") }
    return ""
}

function Get-HordeCloudflareRelayLocationClientId {
    # The client_id a sign-in start's Location sends the browser to Google with, decoded, or $null when
    # it names none (or names it twice).
    param([AllowEmptyString()][string]$Location)
    $q = $Location.IndexOf("?")
    if ($q -lt 0) { return $null }
    $found = @()
    foreach ($pair in $Location.Substring($q + 1).Split("&")) {
        if ($pair.StartsWith("client_id=", [System.StringComparison]::Ordinal)) { $found += [System.Uri]::UnescapeDataString($pair.Substring(10).Replace("+", " ")) }
    }
    if ($found.Count -ne 1) { return $null }
    return $found[0]
}

function Test-HordeCloudflareRelaySignInClient {
    # Does the relay at -Origin start a sign-in with exactly -ClientId? GET <origin>/auth/google, its
    # redirect not followed, and the client_id in its Location compared ordinally, byte for byte: known
    # $true, or unknown with a reason that holds no value. A Worker just deployed may still be reaching
    # the edge, so it is asked up to -Tries times, -WaitMs apart.
    param([Parameter(Mandatory = $true)][string]$Origin, [Parameter(Mandatory = $true)][string]$ClientId, [int]$Tries = 3, [int]$WaitMs = 2000)
    Add-Type -AssemblyName System.Net.Http
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $false
    $handler.UseCookies = $false
    $http = New-Object System.Net.Http.HttpClient($handler)
    $http.Timeout = [TimeSpan]::FromSeconds(15)
    $why = ""
    try {
        for ($i = 1; $i -le $Tries; $i++) {
            if ($i -gt 1) { Start-Sleep -Milliseconds $WaitMs }
            try {
                $res = $http.GetAsync($Origin + "/auth/google").GetAwaiter().GetResult()
                try {
                    $code = [int]$res.StatusCode
                    $loc = $(if ($null -ne $res.Headers.Location) { $res.Headers.Location.OriginalString } else { "" })
                } finally { $res.Dispose() }
            } catch { $why = "it did not answer GET /auth/google"; continue }
            if ($code -lt 300 -or $code -gt 399 -or $loc -eq "") { $why = "GET /auth/google answered " + $code + ", not a redirect to Google (503 is a relay whose sign-in is not set up)"; continue }
            $sent = Get-HordeCloudflareRelayLocationClientId -Location $loc
            if ($null -eq $sent) { $why = "GET /auth/google redirected with no single client_id"; continue }
            if ([string]::Equals($sent, $ClientId, [System.StringComparison]::Ordinal)) { return (New-HordeKnown -Value $true) }
            $why = "the client id its sign-in sends Google is not the client file's, byte for byte, so Google would refuse it (invalid_client)"
        }
    } finally { $http.Dispose() }
    return (New-HordeUnknown -Reason $why)
}

function Publish-HordeCloudflareRelay {
    # Deploy the hosted relay serving the app in -Site: known { origin } or unknown with the reason.
    param([Parameter(Mandatory = $true)][string]$Site, [scriptblock]$Say = { param($Line) }, [string]$HordeHome = "")
    $set = Get-HordeCloudflareRelaySettings -HordeHome $HordeHome
    if ($set.state -cne "known") { return $set }
    $dep = Get-HordeCloudflareRelayDeployment -Values $set.value
    if ($dep.state -cne "known") { return $dep }
    $dep = $dep.value
    $clientFile = Get-HordeCloudflareRelayClientFile -Values $set.value
    $client = Read-HordeCloudflareRelayGoogleClient -Path $clientFile -RepoRoot (Get-HordeCloudflareRelayRepoRoot)
    if ($client.state -cne "known") { return $client }
    $allow = ConvertTo-HordeCloudflareRelayAllowlist -Values $set.value
    if ($allow.state -cne "known") { return $allow }
    $values = @{ clientId = $client.value.clientId; clientSecret = $client.value.clientSecret; allowlist = $allow.value }
    $secrets = @($client.value.clientId, $client.value.clientSecret, $allow.value)
    foreach ($name in @($script:HordeCloudflareRelaySecretNames.Keys)) {
        $bad = Test-HordeCloudflareRelaySecretValue -Name $name -Value ("" + $values[$script:HordeCloudflareRelaySecretNames[$name]])
        if ($bad -ne "") { return (New-HordeUnknown -Reason ($bad + "; nothing was deployed")) }
    }
    $checkOrigin = "" + $set.value.deployCheckOrigin
    if ($checkOrigin -ne "" -and $checkOrigin -cnotmatch '\Ahttp://127\.0\.0\.1:[0-9]{1,5}\z') { return (New-HordeUnknown -Reason "the setting deployCheckOrigin is for a test's stand-in only: http://127.0.0.1:<port>, or empty for the relay itself; nothing was deployed") }
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

    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-relay-cf-deploy-" + [guid]::NewGuid().ToString("N").Substring(0, 12))
    [void][System.IO.Directory]::CreateDirectory($work)
    try {
        $cfg = New-HordeCloudflareRelayConfig -Out (Join-Path $work "config") -Site $Site -Deployment $dep
        if ($cfg.state -cne "known") { return $cfg }
        $quiet = Get-HordeCloudflareRelayQuietEnv -Work $work
        foreach ($name in @($script:HordeCloudflareRelaySecretNames.Keys)) {
            $value = "" + $values[$script:HordeCloudflareRelaySecretNames[$name]]
            $r = Invoke-HordeCloudflareRelayNode -Node $node -ArgList @($wrangler, "secret", "put", $name, "--config", $cfg.value) -Env $quiet -WorkDir $work -StdIn $value -TimeoutSeconds $script:HordeCloudflareRelayDeploySeconds
            if ($r.timedOut -or $r.code -ne 0) { return (New-HordeUnknown -Reason ("wrangler secret put " + $name + " failed (exit " + $r.code + $(if ($r.timedOut) { ", timed out" } else { "" }) + "): " + (Get-HordeCloudflareRelayWranglerTail -Run $r -Secrets $secrets) + "; nothing was deployed")) }
            & $Say ("stored " + $name + " as a secret of the Worker " + $dep.name)
        }
        $r = Invoke-HordeCloudflareRelayNode -Node $node -ArgList @($wrangler, "deploy", "--config", $cfg.value) -Env $quiet -WorkDir $work -TimeoutSeconds $script:HordeCloudflareRelayDeploySeconds
        foreach ($l in @(("" + $r.out) -split "`r?`n" | Where-Object { $_.Trim() -ne "" })) { & $Say ("  " + (Hide-HordeCloudflareRelaySecrets -Text $l -Secrets $secrets)) }
        if ($r.timedOut -or $r.code -ne 0) { return (New-HordeUnknown -Reason ("wrangler deploy failed (exit " + $r.code + $(if ($r.timedOut) { ", timed out" } else { "" }) + "): " + (Get-HordeCloudflareRelayWranglerTail -Run $r -Secrets $secrets))) }
        $asked = $(if ($checkOrigin -ne "") { $checkOrigin } else { $dep.origin })
        $check = Test-HordeCloudflareRelaySignInClient -Origin $asked -ClientId $client.value.clientId -Tries $script:HordeCloudflareRelayCheckTries -WaitMs $script:HordeCloudflareRelayCheckWaitMs
        # The Worker is live by now, running the secrets just stored: the answer is unknown marked live
        # (relays/Port.ps1, DEPLOYING), so no caller says "not deployed", and the reason names the way back.
        if ($check.state -cne "known") {
            $failed = New-HordeUnknown -Reason ("its sign-in failed the check after the deploy: " + $check.reason + ". Sign-in will not work until it is fixed: deploy again from a fixed checkout (under PowerShell 7, or with the byte order mark fix), then check that " + $asked + "/auth/google redirects to Google")
            $failed | Add-Member -NotePropertyName live -NotePropertyValue $true
            return $failed
        }
        & $Say ("checked: the relay's sign-in sends Google the client file's id")
        # SIGN-IN'S RETURN ADDRESS (8b) must be registered with Google, or Google refuses the sign-in.
        $callback = $dep.origin + $dep.callback
        if (@($client.value.redirectUris) -cnotcontains $callback) { & $Say ("note: the Google client does not list " + $callback + " among its redirect addresses; add it in the Google Cloud console before sign-in is used") }
        return (New-HordeKnown -Value ([pscustomobject]@{ origin = $dep.origin }))
    } finally {
        if ($work -like "*horde-relay-cf-deploy-*" -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
