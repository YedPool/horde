# relays/cloudflare/Wrangler.ps1 - the hosted relay's tooling: the pinned wrangler, installed OUTSIDE the
# repository, the config it is run with, a local `wrangler dev` for the suites, and every run of it.
#
# THE TOOLS LIVE OUTSIDE THE TREE. package.json and package-lock.json here pin wrangler (a development
# tool: the Worker itself loads no package). They are installed by `npm ci` into
# %LOCALAPPDATA%\horde\tools\wrangler-<first 12 hex of the lock's SHA-256>, never into this folder: a
# node_modules in the tree would be read by test/test-host-names.ps1's scan of every file (it reads the
# disk, not git), carry binaries no rule allows, and be copied into every mutation run's throwaway tree.
# A new lock is a new folder, so two checkouts on two locks never share one. The install is made in a
# folder of its own and renamed into place, so two suites installing at once cannot leave half of one;
# --ignore-scripts, because nothing in the lock needs an install script to run (measured 2026-10-11:
# wrangler 4.149.0 ran dev and its runtime with none) and a script is code run at install time.
#
# WHERE IT IS DEPLOYED is wrangler.json's too, and only there: the Worker's name, and in its vars the
# origin it answers at (https://<name>.<account subdomain>.workers.dev) and the path Google sign-in will
# return to (reserved now; sign-in is the next pull request). Get-HordeCloudflareRelayDeployment reads
# them for the adapter's default origin and the deploy; the Worker reads them as bindings.
#
# THE CONFIG IT RUNS WITH IS WRITTEN, NOT USED IN PLACE. wrangler.json beside this file is the one
# production config; New-HordeCloudflareRelayConfig writes a copy into a work folder outside the tree,
# with main, base_dir and the app's folder made absolute, so wrangler's own scratch (.wrangler) lands
# there too. A test run adds test-bindings.json's bindings with a fresh random token, points the
# Worker's origin at the dev's own port (worker/site.js: what sign-in redirects to and machine
# signatures cover), and may add a suite's own vars (the fake provider, a test client, an allowlist, the
# test limits: worker/limits.js);
# a production copy REFUSES a config that holds any HORDE_RELAY_TEST_ binding anywhere (worker/auth.js,
# THE TEST AUTHENTICATOR; worker/oidc.js, THE TEST PROVIDER).
#
# NOTHING IS SENT TO CLOUDFLARE BY A LOCAL RUN. Every run here sets: CLOUDFLARE_CF_FETCH_ENABLED=false
# (a local dev otherwise fetches a request-metadata file from workers.cloudflare.com: measured
# 2026-10-11, it timed out against it), WRANGLER_SEND_METRICS=false and WRANGLER_SEND_ERROR_REPORTS=false
# (and send_metrics false in the config), DO_NOT_TRACK=1, and the local explorer and observability off
# (X_LOCAL_EXPLORER, X_LOCAL_OBSERVABILITY: the second would keep a local copy of every request). Its
# logs and its registry of dev sessions go into the work folder. Only `deploy` and `secret put`, run by
# the deploy, ever reach Cloudflare, with the founder's own wrangler login.
#
# Runs on Windows PowerShell 5.1 and PowerShell 7 alike. No Set-StrictMode here: dot-sourced.

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\Tristate.ps1")

$script:HordeCloudflareRelayFolder = $PSScriptRoot
$script:HordeCloudflareRelayTestBinding = "HORDE_RELAY_TEST_AUTH"
# Every test-only binding starts so (test-bindings.json); none may be in the production config.
$script:HordeCloudflareRelayTestPrefix = "HORDE_RELAY_TEST_"
# How long a local dev may take to answer its first request. Measured 2026-10-11: 1.6 s on this box.
$script:HordeCloudflareRelayDevReadyMs = 60000

function Get-HordeCloudflareRelayRepoRoot { return (Split-Path -Parent (Split-Path -Parent $script:HordeCloudflareRelayFolder)) }

function Find-HordeCloudflareRelayNode {
    # node's full path, or "" when it is not on PATH.
    $c = @(Get-Command -Name "node" -CommandType Application -ErrorAction SilentlyContinue)
    if ($c.Count -eq 0) { return "" }
    return "" + $c[0].Source
}

function Get-HordeCloudflareRelayLockHash {
    # The first 12 hex of the lock's SHA-256, its line ends made LF first, so a CRLF checkout and an LF
    # one name the same folder.
    $text = [System.IO.File]::ReadAllText((Join-Path $script:HordeCloudflareRelayFolder "package-lock.json"), [System.Text.Encoding]::UTF8).Replace("`r`n", "`n")
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $h = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text)) } finally { $sha.Dispose() }
    return ((($h | Select-Object -First 6) | ForEach-Object { $_.ToString("x2") }) -join "")
}

function Get-HordeCloudflareRelayToolsHome {
    # Where this lock's tools are installed. -Base replaces %LOCALAPPDATA%\horde\tools (a suite's own).
    param([string]$Base = "")
    if ($Base -eq "") { $Base = Join-Path $env:LOCALAPPDATA "horde\tools" }
    return (Join-Path $Base ("wrangler-" + (Get-HordeCloudflareRelayLockHash)))
}

function Get-HordeCloudflareRelayWranglerScript {
    # The pinned wrangler's command line, under -ToolsHome.
    param([Parameter(Mandatory = $true)][string]$ToolsHome)
    return (Join-Path $ToolsHome "node_modules\wrangler\wrangler-dist\cli.js")
}

function Get-HordeCloudflareRelayQuietEnv {
    # The environment every wrangler run here gets (header, NOTHING IS SENT TO CLOUDFLARE).
    param([Parameter(Mandatory = $true)][string]$Work)
    return @{
        CLOUDFLARE_CF_FETCH_ENABLED = "false"; WRANGLER_SEND_METRICS = "false"; WRANGLER_SEND_ERROR_REPORTS = "false"
        DO_NOT_TRACK = "1"; X_LOCAL_EXPLORER = "false"; X_LOCAL_OBSERVABILITY = "false"
        WRANGLER_LOG_PATH = (Join-Path $Work "logs"); WRANGLER_REGISTRY_PATH = (Join-Path $Work "registry")
        WRANGLER_HIDE_BANNER = "true"; NO_COLOR = "1"; CI = "true"
    }
}

function Invoke-HordeCloudflareRelayNode {
    # Run node with -ArgList; -StdIn, when given, is written as ASCII bytes and the input closed, so a
    # secret travels in the pipe and never in the arguments. { code; out; err; timedOut }. Only the
    # process this function started is ever stopped.
    param([Parameter(Mandatory = $true)][string]$Node, [string[]]$ArgList = @(), [hashtable]$Env = @{},
        [Parameter(Mandatory = $true)][string]$WorkDir, [AllowEmptyString()][string]$StdIn = "", [int]$TimeoutSeconds = 600)
    $quoted = @($ArgList | ForEach-Object { if ($_ -eq "" -or $_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } })
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Node
    $psi.Arguments = ($quoted -join " ")
    $psi.WorkingDirectory = $WorkDir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    foreach ($k in @($Env.Keys)) { $psi.EnvironmentVariables[$k] = "" + $Env[$k] }
    $p = [System.Diagnostics.Process]::Start($psi)
    try {
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        # THE BASE STREAM, NOT THE WRITER: Windows PowerShell's writer on a child's input may put a byte
        # order mark first (it takes the console's input encoding), and the secret would carry it.
        $in = $p.StandardInput.BaseStream
        if ($StdIn -ne "") { $b = [System.Text.Encoding]::ASCII.GetBytes($StdIn); $in.Write($b, 0, $b.Length); $in.Flush() }
        $in.Close()
        $timedOut = -not $p.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) { try { $p.Kill() } catch { }; $null = $p.WaitForExit(10000) }
        $p.WaitForExit()
        return [pscustomobject]@{ code = $p.ExitCode; out = $outTask.Result; err = $errTask.Result; timedOut = $timedOut }
    } finally { $p.Dispose() }
}

function Install-HordeCloudflareRelayTools {
    # The pinned tools, installed when they are not: known { home; script } or unknown with the reason.
    param([string]$Base = "")
    $node = Find-HordeCloudflareRelayNode
    if ($node -eq "") { return (New-HordeUnknown -Reason "node is not installed here (wrangler needs node 22 or later)") }
    $toolsHome = Get-HordeCloudflareRelayToolsHome -Base $Base
    $script = Get-HordeCloudflareRelayWranglerScript -ToolsHome $toolsHome
    if (Test-Path -LiteralPath $script -PathType Leaf) { return (New-HordeKnown -Value ([pscustomobject]@{ home = $toolsHome; script = $script })) }
    $npm = Join-Path (Split-Path -Parent $node) "node_modules\npm\bin\npm-cli.js"
    if (-not (Test-Path -LiteralPath $npm -PathType Leaf)) { return (New-HordeUnknown -Reason ("npm is not beside node (" + $npm + ")")) }
    $staging = $toolsHome + ".installing-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
    [void][System.IO.Directory]::CreateDirectory($staging)
    try {
        foreach ($f in @("package.json", "package-lock.json")) { [System.IO.File]::Copy((Join-Path $script:HordeCloudflareRelayFolder $f), (Join-Path $staging $f)) }
        $r = Invoke-HordeCloudflareRelayNode -Node $node -ArgList @($npm, "ci", "--ignore-scripts", "--no-audit", "--no-fund") -WorkDir $staging -TimeoutSeconds 600
        if ($r.code -ne 0 -or $r.timedOut) {
            $tail = (@(("" + $r.err).Trim() -split "`n" | Select-Object -Last 3) -join " ")
            return (New-HordeUnknown -Reason ("npm ci of the pinned wrangler failed (exit " + $r.code + "): " + $tail))
        }
        try { [System.IO.Directory]::Move($staging, $toolsHome) } catch { if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { throw } }
    } finally { if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue } }
    if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { return (New-HordeUnknown -Reason ("the pinned wrangler is not at " + $script + " after its install")) }
    return (New-HordeKnown -Value ([pscustomobject]@{ home = $toolsHome; script = $script }))
}

function Test-HordeCloudflareRelayHasTestBinding {
    # Does this config text name a test binding (HORDE_RELAY_TEST_...) anywhere at all - in vars, in an
    # env section, in a comment? Matched as text, so no shape of config can hide it.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    return ($Text.IndexOf($script:HordeCloudflareRelayTestPrefix, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
}

function New-HordeCloudflareRelayConfig {
    # Write the config wrangler runs with into -Out (a folder outside the tree): wrangler.json with main,
    # base_dir and assets.directory absolute, the app's files at -Site. -TestToken adds the test binding
    # (test runs only). -CommittedTestBinding adds test-bindings.json exactly as committed, placeholder
    # and all: only for the suite that shows the Worker refuses the placeholder. With either, -Origin
    # (http to this machine) replaces HORDE_RELAY_ORIGIN and -ExtraVars adds a suite's own vars over the rest.
    # Known: the config's path. Unknown when wrangler.json holds a test binding, the token is too short
    # to count, or the origin is not this machine's.
    param([Parameter(Mandatory = $true)][string]$Out, [Parameter(Mandatory = $true)][string]$Site, [string]$TestToken = "", [switch]$CommittedTestBinding,
        [string]$Origin = "", [hashtable]$ExtraVars = @{})
    $text = [System.IO.File]::ReadAllText((Join-Path $script:HordeCloudflareRelayFolder "wrangler.json"), [System.Text.Encoding]::UTF8)
    if (Test-HordeCloudflareRelayHasTestBinding -Text $text) { return (New-HordeUnknown -Reason ("wrangler.json names a " + $script:HordeCloudflareRelayTestPrefix + " binding: the production config must never carry the test binding, nor any other test-only one")) }
    $isTest = $TestToken -ne "" -or $CommittedTestBinding
    if (-not $isTest -and ($Origin -ne "" -or $ExtraVars.Count -gt 0)) { return (New-HordeUnknown -Reason "-Origin and -ExtraVars are for a test config only") }
    if ($Origin -ne "" -and $Origin -cnotmatch '\Ahttp://127\.0\.0\.1:[0-9]{1,5}\z') { return (New-HordeUnknown -Reason "a test origin is http://127.0.0.1:<port>") }
    $cfg = $text | ConvertFrom-Json
    $slash = { param([string]$p) ([System.IO.Path]::GetFullPath($p)) -replace '\\', '/' }
    $cfg.main = & $slash (Join-Path $script:HordeCloudflareRelayFolder $cfg.main)
    $cfg.base_dir = & $slash (Get-HordeCloudflareRelayRepoRoot)
    $cfg.assets.directory = & $slash $Site
    if ($isTest) {
        if (-not $CommittedTestBinding -and $TestToken -cnotmatch '\A[0-9a-f]{32,}\z') { return (New-HordeUnknown -Reason "a test token is 32 or more lower-case hex digits") }
        $overlay = [System.IO.File]::ReadAllText((Join-Path $script:HordeCloudflareRelayFolder "test-bindings.json"), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $vars = [ordered]@{}
        if ($null -ne $cfg.PSObject.Properties["vars"]) { foreach ($p in $cfg.vars.PSObject.Properties) { $vars[$p.Name] = $p.Value } }
        foreach ($p in $overlay.vars.PSObject.Properties) { $vars[$p.Name] = $p.Value }
        if (-not $CommittedTestBinding) { $vars[$script:HordeCloudflareRelayTestBinding] = $TestToken }
        if ($Origin -ne "") { $vars["HORDE_RELAY_ORIGIN"] = $Origin }
        foreach ($k in @($ExtraVars.Keys)) { $vars[$k] = $ExtraVars[$k] }
        $cfg | Add-Member -NotePropertyName vars -NotePropertyValue ([pscustomobject]$vars) -Force
    }
    [void][System.IO.Directory]::CreateDirectory($Out)
    $path = Join-Path $Out "wrangler.json"
    [System.IO.File]::WriteAllText($path, ($cfg | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding -ArgumentList $false))
    return (New-HordeKnown -Value $path)
}

function Get-HordeCloudflareRelayDeployment {
    # Where the production relay answers, from wrangler.json, its one source: { name; origin; callback }.
    # The Worker's name is the origin's first label (<name>.<account subdomain>.workers.dev); a config
    # where the two disagree would deploy one Worker and send every machine to another, so it throws.
    $cfg = [System.IO.File]::ReadAllText((Join-Path $script:HordeCloudflareRelayFolder "wrangler.json"), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $origin = "" + $cfg.vars.HORDE_RELAY_ORIGIN
    if ($origin -cnotmatch ('\Ahttps://' + [regex]::Escape("" + $cfg.name) + '\.[a-z0-9-]+\.workers\.dev\z')) { throw ("wrangler.json's HORDE_RELAY_ORIGIN '" + $origin + "' is not https://" + $cfg.name + ".<account subdomain>.workers.dev") }
    return [pscustomobject]@{ name = "" + $cfg.name; origin = $origin; callback = "" + $cfg.vars.HORDE_RELAY_GOOGLE_CALLBACK }
}

function Get-HordeCloudflareRelayFreePort {
    # A port no one listens on now, from the system's own choice. Another process may take it before
    # wrangler does; the start then fails, and says so.
    $l = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $l.Start()
    try { return ([System.Net.IPEndPoint]$l.LocalEndpoint).Port } finally { $l.Stop() }
}

function New-HordeCloudflareRelayToken {
    # 32 random bytes as 64 lower-case hex digits.
    $b = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($b) } finally { $rng.Dispose() }
    return (($b | ForEach-Object { $_.ToString("x2") }) -join "")
}

function Start-HordeCloudflareRelayDev {
    # A local `wrangler dev` of the Worker with the test binding, serving the app's files at -Site, its
    # state and scratch in -Work: known { process; origin; token; work } once it answers, or unknown.
    # Stop it with Stop-HordeCloudflareRelayDev; if the caller dies first, it ends with it (dev-host.cjs).
    # -CommittedTestBinding runs it with test-bindings.json's placeholder instead of a token (Config);
    # -ExtraVars adds a suite's own (Config). Its origin is its own port's, written in as the Worker's.
    param([Parameter(Mandatory = $true)][string]$Work, [Parameter(Mandatory = $true)][string]$Site, [Parameter(Mandatory = $true)][string]$Script, [switch]$CommittedTestBinding,
        [hashtable]$ExtraVars = @{})
    $node = Find-HordeCloudflareRelayNode
    if ($node -eq "") { return (New-HordeUnknown -Reason "node is not installed here") }
    $token = New-HordeCloudflareRelayToken
    $port = Get-HordeCloudflareRelayFreePort
    $origin = "http://127.0.0.1:" + $port
    if ($CommittedTestBinding) { $cfg = New-HordeCloudflareRelayConfig -Out (Join-Path $Work "config") -Site $Site -CommittedTestBinding -Origin $origin -ExtraVars $ExtraVars }
    else { $cfg = New-HordeCloudflareRelayConfig -Out (Join-Path $Work "config") -Site $Site -TestToken $token -Origin $origin -ExtraVars $ExtraVars }
    if ($cfg.state -cne "known") { return $cfg }
    $inspector = Get-HordeCloudflareRelayFreePort
    $argv = @((Join-Path $script:HordeCloudflareRelayFolder "dev-host.cjs"), $Script, "dev", "--config", $cfg.value, "--ip", "127.0.0.1", "--port", "$port",
        "--inspector-port", "$inspector", "--persist-to", (Join-Path $Work "state"), "--show-interactive-dev-session=false")
    $quoted = @($argv | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } })
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $node
    $psi.Arguments = ($quoted -join " ")
    $psi.WorkingDirectory = $Work
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    # Its words are read as they come (a full pipe would stop it) and kept for the reason of a failed
    # start; nothing of them reaches the suite's own output.
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $quiet = Get-HordeCloudflareRelayQuietEnv -Work $Work
    foreach ($k in @($quiet.Keys)) { $psi.EnvironmentVariables[$k] = $quiet[$k] }
    $p = [System.Diagnostics.Process]::Start($psi)
    $dev = [pscustomobject]@{ process = $p; origin = $origin; token = $token; work = $Work; out = $p.StandardOutput.ReadToEndAsync(); err = $p.StandardError.ReadToEndAsync() }
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    Add-Type -AssemblyName System.Net.Http
    $http = New-Object System.Net.Http.HttpClient
    $http.Timeout = [TimeSpan]::FromSeconds(5)
    try {
        while ($clock.ElapsedMilliseconds -lt $script:HordeCloudflareRelayDevReadyMs) {
            if ($p.HasExited) {
                $said = (@(("" + $dev.out.Result + $dev.err.Result).Trim() -split "`n" | Select-Object -Last 6) -join " | ")
                return (New-HordeUnknown -Reason ("wrangler dev ended with exit " + $p.ExitCode + " before it answered: " + $said))
            }
            try {
                $r = $http.GetAsync($origin + "/v1/").GetAwaiter().GetResult()
                $code = [int]$r.StatusCode
                $r.Dispose()
                # 401 is the Worker itself answering: nobody vouched for that request, as it should be.
                if ($code -eq 401) { return (New-HordeKnown -Value $dev) }
            } catch { }
            Start-Sleep -Milliseconds 200
        }
    } finally { $http.Dispose() }
    Stop-HordeCloudflareRelayDev -Dev $dev
    return (New-HordeUnknown -Reason ("wrangler dev did not answer within " + $script:HordeCloudflareRelayDevReadyMs + " ms"))
}

function Stop-HordeCloudflareRelayDev {
    # End a dev this file started: close its input (dev-host.cjs then exits, and the runtime with it),
    # and kill that one process, by the handle held, if it has not gone within 10 s.
    param($Dev)
    if ($null -eq $Dev -or $null -eq $Dev.process) { return }
    $p = $Dev.process
    try {
        if (-not $p.HasExited) {
            try { $p.StandardInput.BaseStream.Close() } catch { }
            if (-not $p.WaitForExit(10000)) { try { $p.Kill() } catch { }; $null = $p.WaitForExit(10000) }
        }
    } finally { $p.Dispose() }
}
