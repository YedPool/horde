# DOES THE HOSTED RELAY'S WORKER ANSWER EVERYONE WITH STRICT HEADERS, NOBODY WITHOUT SIGN-IN, AND NOTHING
# OVER ITS CAP - AND CAN ITS PRODUCTION CONFIG NEVER TURN THE TEST AUTHENTICATOR ON?
#
# Relay PR 8a (the founder's plan of 2026-10-11). The mailbox contract itself is
# test/test-relay-conformance.ps1's; this suite holds the Worker to what that suite does not see:
#   1. THE CONFIGS, read without running anything: wrangler.json never names the test binding; the
#      config written for production carries none, and refuses a wrangler.json that does; the one
#      written for a test carries a fresh token; the binding's committed value is too short to count;
#      the production origin is the Worker's own name; the Worker never logs.
#   2. A LOCAL DEV OF THE WORKER serving the built phone app (built by cli/RelayDeploy.ps1 exactly as
#      the deploy builds it: the http transport at its own origin):
#      - strict headers on every kind of answer: a page, a script, a missing file, a refusal, a mailbox
#        answer, the sign-in callback, and a WebSocket upgrade (read off the wire);
#      - the header's policy is the built page's own policy line, plus frame-ancestors 'none';
#      - deny by default: no token, a wrong token, and the right token sent to a name that is not this
#        machine are all 401, even for a path that does not exist;
#      - the caps and the refusals: 64 KiB of text and not one more, a body past its cap, malformed
#        JSON, a member too many, a bad key, a non-ASCII text, malformed cursors, the wrong method, a
#        watch that is not an upgrade, a device name, an ack past the head;
#      - one answer's texts stop at a million characters, so a watch's one message fits a WebSocket's;
#      - a key is remembered while its item is held, and free again once the item is trimmed;
#      - the machine's adapter: quotes and backslashes round-trip, a refusal carries the relay's status
#        and words, and with no origin given it connects to the production origin;
#      - a dev run with test-bindings.json exactly as committed vouches for no one: the placeholder is
#        too short to be a token, whatever a caller sends;
#      - the phone's own relay client and http transport, run by node, against this Worker;
#      - a Google client id stored with a byte order mark in front (2026-10-14) is not set up: the
#        sign-in start is 503 and sends nothing to Google, while its clean twin redirects with the id;
#        the deploy's check after a deploy fails the one and passes the other.
#
# NODE IS NEEDED, and the pinned wrangler (relays/cloudflare/Wrangler.ps1 installs it outside the
# tree). Without them part 2 is skipped, said so, and the suite exits 3, never 0. Every folder is the
# suite's own under %TEMP%, and the dev it starts is stopped in a finally block.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "relays\Port.ps1")
foreach ($f in @(Get-HordeRelayFiles)) { . $f }
. (Join-Path $root "cli\RelayDeploy.ps1")
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Net.Http

$folder = Join-Path $root "relays\cloudflare"
$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$work = Join-Path $env:TEMP ("horde-cf-worker-" + [guid]::NewGuid().ToString("N").Substring(0, 12))
[void][System.IO.Directory]::CreateDirectory($work)

function Read-Text { param([string]$Path) return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) }
function Get-Prop {
    # A member of a parsed object, or $null when the object or the member is not there (strict mode
    # would raise an error instead, and a check that raises is not a failed check).
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

Write-Host ""
Write-Host "--- 1. the configs: the production one can never turn the test authenticator on ---" -ForegroundColor Cyan
$prodText = Read-Text (Join-Path $folder "wrangler.json")
$prod = $prodText | ConvertFrom-Json
$overlayText = Read-Text (Join-Path $folder "test-bindings.json")
Check (Test-HordeCloudflareRelayHasTestBinding -Text $overlayText) "CONTROL: the binding search finds the binding in test-bindings.json"
Check (-not (Test-HordeCloudflareRelayHasTestBinding -Text $prodText)) "wrangler.json, the production config, does not name the test binding anywhere"
Check ($null -eq $prod.PSObject.Properties["env"]) "wrangler.json has no env sections, so no environment of it can carry a binding of its own"
$placeholder = "" + ($overlayText | ConvertFrom-Json).vars.HORDE_RELAY_TEST_AUTH
Check ($placeholder.Length -gt 0 -and $placeholder.Length -lt 32) ("the binding's committed value is a placeholder too short to count (" + $placeholder.Length + " characters; the Worker wants 32)")
$authJs = Read-Text (Join-Path $folder "worker\auth.js")
$siteJs = Read-Text (Join-Path $folder "worker\site.js")
Check ($authJs.Contains("const TEST_TOKEN_MIN = 32;") -and $authJs.Contains("if (!isLoopback(url)) return null;") -and $siteJs.Contains('export const LOOPBACK = new Set(["127.0.0.1", "localhost", "[::1]"]);')) "CONTROL: the Worker's test authenticator wants 32 characters and this machine's own names"

$siteForConfig = Join-Path $work "config-site"
[void][System.IO.Directory]::CreateDirectory($siteForConfig)
$pc = New-HordeCloudflareRelayConfig -Out (Join-Path $work "prod-config") -Site $siteForConfig
$pcText = $(if ($pc.state -ceq "known") { Read-Text $pc.value } else { "" })
Check ($pc.state -ceq "known" -and $pcText -ne "" -and -not (Test-HordeCloudflareRelayHasTestBinding -Text $pcText)) "the config written for production carries no test binding"
$pcObj = $(if ($pcText -ne "") { $pcText | ConvertFrom-Json } else { $null })
$siteSlash = ([System.IO.Path]::GetFullPath($siteForConfig)) -replace '\\', '/'
Check ($null -ne $pcObj -and (Get-Prop (Get-Prop $pcObj "assets") "directory") -ceq $siteSlash -and [System.IO.Path]::IsPathRooted($pcObj.main) -and (Test-Path -LiteralPath $pcObj.main) -and (Get-Prop (Get-Prop $pcObj "vars") "HORDE_RELAY_ORIGIN") -ceq $prod.vars.HORDE_RELAY_ORIGIN) "and points wrangler at the Worker and the app's folder by absolute paths, keeping wrangler.json's own vars"
$tok = New-HordeCloudflareRelayToken
$tc = New-HordeCloudflareRelayConfig -Out (Join-Path $work "test-config") -Site $siteForConfig -TestToken $tok
$tcObj = $(if ($tc.state -ceq "known") { Read-Text $tc.value | ConvertFrom-Json } else { $null })
Check ($null -ne $tcObj -and (Get-Prop (Get-Prop $tcObj "vars") "HORDE_RELAY_TEST_AUTH") -ceq $tok -and (Get-Prop (Get-Prop $tcObj "vars") "HORDE_RELAY_ORIGIN") -ceq $prod.vars.HORDE_RELAY_ORIGIN) "the config written for a test carries the binding with the run's own token, beside wrangler.json's vars"
$short = New-HordeCloudflareRelayConfig -Out (Join-Path $work "short-config") -Site $siteForConfig -TestToken "abc"
Check ($short.state -ceq "unknown") "a test token too short to count is refused before any config is written"
Check ((New-HordeCloudflareRelayToken) -cne $tok -and $tok -cmatch '\A[0-9a-f]{64}\z') "each run's token is 64 fresh hex digits"

# A doctored copy of the folder, its wrangler.json carrying the binding: the production writer refuses
# it. Run in a child process, so the copy's own Wrangler.ps1 reads the copy's own config.
$copy = Join-Path $work "doctored"
foreach ($d in @("core", "relays\cloudflare")) { Copy-Item -LiteralPath (Join-Path $root $d) -Destination (Join-Path $copy $d) -Recurse }
$doctored = $prodText.Replace('"vars": {', '"vars": { "HORDE_RELAY_TEST_AUTH": "0123456789abcdef0123456789abcdef0123456789abcdef",')
[System.IO.File]::WriteAllText((Join-Path $copy "relays\cloudflare\wrangler.json"), $doctored, $utf8)
$probe = Join-Path $work "probe.ps1"
[System.IO.File]::WriteAllText($probe, ('. "' + (Join-Path $copy "relays\cloudflare\Wrangler.ps1") + '"' + "`n" + '$a = New-HordeCloudflareRelayConfig -Out "' + (Join-Path $work "doctored-out") + '" -Site "' + $siteForConfig + '"' + "`n" + 'Write-Output ($a.state + "|" + $a.reason)' + "`n"), $utf8)
$psExe = (Get-Process -Id $PID).Path
$answer = (& $psExe -NoProfile -ExecutionPolicy Bypass -File $probe | Out-String).Trim()
Check ((Test-HordeCloudflareRelayHasTestBinding -Text $doctored) -and $answer -clike "unknown|*must never carry the test binding*" -and -not (Test-Path -LiteralPath (Join-Path $work "doctored-out"))) ("a wrangler.json that carries the binding is refused, and nothing is written (" + $answer + ")")
# The same copy carrying only the test PROVIDER's binding (worker/oidc.js): refused as well - every
# HORDE_RELAY_TEST_ binding is test-only, not just the authenticator's.
$doctoredOidc = $prodText.Replace('"vars": {', '"vars": { "HORDE_RELAY_TEST_OIDC": "http://127.0.0.1:1",')
[System.IO.File]::WriteAllText((Join-Path $copy "relays\cloudflare\wrangler.json"), $doctoredOidc, $utf8)
$answer = (& $psExe -NoProfile -ExecutionPolicy Bypass -File $probe | Out-String).Trim()
Check ($answer -clike "unknown|*must never carry the test binding*" -and -not (Test-Path -LiteralPath (Join-Path $work "doctored-out"))) ("a wrangler.json that carries the test provider's binding is refused too (" + $answer + ")")
$oidcPlaceholder = "" + ($overlayText | ConvertFrom-Json).vars.HORDE_RELAY_TEST_OIDC
Check ($oidcPlaceholder -cnotmatch '\Ahttp://127\.0\.0\.1:[0-9]{1,5}\z') ("the test provider's committed value is a placeholder no Worker takes for a provider (" + $oidcPlaceholder + ")")
# The same copy with another Worker's name than its origin's first label: the origin is refused.
[System.IO.File]::WriteAllText((Join-Path $copy "relays\cloudflare\wrangler.json"), $prodText.Replace('"name": "relay"', '"name": "other"'), $utf8)
[System.IO.File]::WriteAllText($probe, ('. "' + (Join-Path $copy "relays\cloudflare\Wrangler.ps1") + '"' + "`n" + 'try { $d = Get-HordeCloudflareRelayDeployment; Write-Output ("taken|" + $d.origin) } catch { Write-Output ("refused|" + $_.Exception.Message) }' + "`n"), $utf8)
$answer = (& $psExe -NoProfile -ExecutionPolicy Bypass -File $probe | Out-String).Trim()
Check ($prodText.Contains('"name": "relay"') -and $answer -clike "refused|*is not https://other.*") ("a Worker name the origin does not start with is refused, so a deploy never sends machines to another Worker (" + $answer + ")")

$dep = Get-HordeCloudflareRelayDeployment
Check ($dep.name -ceq "relay" -and $dep.origin -clike ("https://" + $dep.name + ".*.workers.dev") -and $dep.callback -ceq "/auth/google/callback") ("the production origin is the Worker's own name under the account's subdomain, and sign-in's return path is reserved (" + $dep.origin + $dep.callback + ")")
$workerFiles = @(Get-ChildItem -LiteralPath (Join-Path $folder "worker") -Filter "*.js" -File)
Check ($workerFiles.Count -ge 6) ("CONTROL: the Worker's files are read (" + $workerFiles.Count + ")")
$logs = @($workerFiles | Where-Object { (Read-Text $_.FullName) -match '\bconsole\s*\.' } | ForEach-Object { $_.Name })
Check ($logs.Count -eq 0) ("the Worker never logs: no console call in any of its files (" + ($logs -join ", ") + ")")

Write-Host ""
Write-Host "--- 2. a local dev of the Worker, serving the built app ---" -ForegroundColor Cyan
$tools = Install-HordeCloudflareRelayTools
$node = Find-HordeCloudflareRelayNode
if ($tools.state -cne "known" -or $node -eq "") {
    Write-Host ("  [SKIP] the Worker cannot be run here: " + $(if ($tools.state -cne "known") { $tools.reason } else { "no node" })) -ForegroundColor Yellow
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
    Complete-HordeSuite -Success "the configs hold; the Worker itself was NOT RUN here" -PassCode 3
}

$site = Join-Path $work "site"
$built = New-HordeRelayDeploySite -Out $site
Check ($built.state -ceq "known") ("the phone app is built with the http transport at its own origin, as the deploy builds it (" + $built.reason + ")")
$dev = Start-HordeCloudflareRelayDev -Work (Join-Path $work "dev") -Site $site -Script $tools.value.script
Check ($dev.state -ceq "known") ("a local dev of the Worker answers (" + $dev.reason + ")")
# A redirect is an answer to check here (sign-in's), never one to follow.
$handler = New-Object System.Net.Http.HttpClientHandler
$handler.AllowAutoRedirect = $false
$http = New-Object System.Net.Http.HttpClient($handler)
$http.Timeout = [TimeSpan]::FromSeconds(30)

function Send-Raw {
    # One request: { code; headers (name -> value, lower-case names); text }.
    param([string]$Method, [string]$Path, [string]$Body = $null, [string]$Authorization = "", [string]$HostName = "", [hashtable]$Extra = @{})
    $req = New-Object System.Net.Http.HttpRequestMessage((New-Object System.Net.Http.HttpMethod($Method)), ($dev.value.origin + $Path))
    if ($Authorization -ne "") { [void]$req.Headers.TryAddWithoutValidation("Authorization", $Authorization) }
    if ($HostName -ne "") { $req.Headers.Host = $HostName }
    foreach ($k in @($Extra.Keys)) { [void]$req.Headers.TryAddWithoutValidation($k, $Extra[$k]) }
    if ($null -ne $Body -and $Body -ne "") { $req.Content = New-Object System.Net.Http.StringContent($Body, [System.Text.Encoding]::UTF8, "application/json") }
    $res = $http.SendAsync($req).GetAwaiter().GetResult()
    try {
        $h = @{}
        foreach ($pair in @($res.Headers) + @($res.Content.Headers)) { $h[$pair.Key.ToLowerInvariant()] = (@($pair.Value) -join ", ") }
        return [pscustomobject]@{ code = [int]$res.StatusCode; headers = $h; text = $res.Content.ReadAsStringAsync().GetAwaiter().GetResult() }
    } finally { $res.Dispose(); $req.Dispose() }
}

function Send-Chunked {
    # A POST whose body goes in chunks with no Content-Length, written on the wire (HttpClient on .NET
    # Framework still sends the length): the status line of the answer.
    param([string]$Path, [string]$Body, [string]$Authorization)
    $u = New-Object System.Uri($dev.value.origin)
    $tcp = New-Object System.Net.Sockets.TcpClient($u.Host, $u.Port)
    try {
        $s = $tcp.GetStream()
        $s.ReadTimeout = 30000
        $head = "POST " + $Path + " HTTP/1.1`r`nHost: " + $u.Authority + "`r`nContent-Type: application/json`r`nTransfer-Encoding: chunked`r`nConnection: close`r`nAuthorization: " + $Authorization + "`r`n`r`n"
        $b = [System.Text.Encoding]::ASCII.GetBytes($head)
        $s.Write($b, 0, $b.Length)
        try {
            for ($i = 0; $i -lt $Body.Length; $i += 16384) {
                $piece = $Body.Substring($i, [Math]::Min(16384, $Body.Length - $i))
                $c = [System.Text.Encoding]::ASCII.GetBytes($piece.Length.ToString("x") + "`r`n" + $piece + "`r`n")
                $s.Write($c, 0, $c.Length)
            }
            $end = [System.Text.Encoding]::ASCII.GetBytes("0`r`n`r`n")
            $s.Write($end, 0, $end.Length)
        } catch { }
        $buf = New-Object byte[] 4096
        $n = $s.Read($buf, 0, $buf.Length)
        if ($n -le 0) { return "" }
        return ([System.Text.Encoding]::ASCII.GetString($buf, 0, $n).Split("`n")[0]).TrimEnd("`r")
    } finally { $tcp.Close() }
}

function Get-UpgradeHeaders {
    # The status line and headers of a WebSocket upgrade, read off the wire (the .NET Framework socket
    # keeps them to itself): { status; headers }.
    param([string]$Path, [string]$Authorization)
    $u = New-Object System.Uri($dev.value.origin)
    $tcp = New-Object System.Net.Sockets.TcpClient($u.Host, $u.Port)
    try {
        $s = $tcp.GetStream()
        $s.ReadTimeout = 10000
        $req = "GET " + $Path + " HTTP/1.1`r`nHost: " + $u.Authority + "`r`nUpgrade: websocket`r`nConnection: Upgrade`r`nSec-WebSocket-Version: 13`r`nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==`r`nAuthorization: " + $Authorization + "`r`n`r`n"
        $b = [System.Text.Encoding]::ASCII.GetBytes($req)
        $s.Write($b, 0, $b.Length)
        $buf = New-Object byte[] 8192
        $got = New-Object System.Text.StringBuilder
        while ($got.ToString().IndexOf("`r`n`r`n") -lt 0) { $n = $s.Read($buf, 0, $buf.Length); if ($n -le 0) { break }; [void]$got.Append([System.Text.Encoding]::ASCII.GetString($buf, 0, $n)) }
        $lines = @($got.ToString().Split("`n") | ForEach-Object { $_.TrimEnd("`r") })
        $h = @{}
        foreach ($l in ($lines | Select-Object -Skip 1)) { $i = $l.IndexOf(":"); if ($i -gt 0) { $h[$l.Substring(0, $i).Trim().ToLowerInvariant()] = $l.Substring($i + 1).Trim() } }
        return [pscustomobject]@{ status = $lines[0]; headers = $h }
    } finally { $tcp.Close() }
}

try {
    if ($dev.state -ceq "known") {
        $bearer = "Bearer " + $dev.value.token
        $mbPath = "/v1/mailboxes/worker-test/phone"
        $pageText = [System.IO.File]::ReadAllText((Join-Path $site "app\index.html"), [System.Text.Encoding]::ASCII)
        $meta = [regex]::Match($pageText, '<meta http-equiv="Content-Security-Policy" content="([^"]+)">')
        Check ($meta.Success -and $meta.Groups[1].Value.Contains("connect-src 'self';")) "CONTROL: the built page carries its policy line, connect-src 'self' and no other origin"
        $wantCsp = $meta.Groups[1].Value + "; frame-ancestors 'none'"

        $null = Send-Raw "POST" ($mbPath + "/items") '{"key":"seed","text":"seed"}' $bearer
        $answers = [ordered]@{
            "the app's page" = (Send-Raw "GET" "/app/index.html")
            "a script of the app" = (Send-Raw "GET" "/app/relay-client.js")
            "the site's root" = (Send-Raw "GET" "/")
            "a file that is not there" = (Send-Raw "GET" "/app/nothing.js")
            "a write to a file" = (Send-Raw "POST" "/app/index.html" "x")
            "a refusal (no sign-in)" = (Send-Raw "GET" ($mbPath + "/items?since=0&max=1"))
            "a mailbox answer" = (Send-Raw "GET" ($mbPath + "/items?since=0&max=1") $null $bearer)
            "the sign-in callback, with no sign-in begun" = (Send-Raw "GET" "/auth/google/callback?code=x")
        }
        $wantStatus = @{ "the app's page" = 200; "a script of the app" = 200; "the site's root" = 200; "a file that is not there" = 404; "a write to a file" = 405; "a refusal (no sign-in)" = 401; "a mailbox answer" = 200; "the sign-in callback, with no sign-in begun" = 303 }
        foreach ($what in @($answers.Keys)) {
            $a = $answers[$what]
            $h = $a.headers
            $ok = $a.code -eq $wantStatus[$what] -and $h["content-security-policy"] -ceq $wantCsp -and $h["strict-transport-security"] -ceq "max-age=63072000; includeSubDomains" -and $h["x-content-type-options"] -ceq "nosniff" -and $h["referrer-policy"] -ceq "no-referrer" -and $h["x-frame-options"] -ceq "DENY"
            $pp = "" + $h["permissions-policy"]
            $ok = $ok -and $pp.Contains("camera=(self)") -and $pp.Contains("publickey-credentials-get=(self)") -and $pp.Contains("microphone=()") -and $pp.Contains("geolocation=()")
            Check $ok ("strict headers on " + $what + " (" + $a.code + "; policy: " + $h["content-security-policy"] + ")")
        }
        Check ($answers["the site's root"].text.Contains("app/index.html")) "the site's root is its own index.html, which sends a visitor to app/index.html"
        Check ("" + $answers["a mailbox answer"].headers["cache-control"] -ceq "no-store" -and "" + $answers["a refusal (no sign-in)"].headers["cache-control"] -ceq "no-store" -and "" + $answers["the sign-in callback, with no sign-in begun"].headers["cache-control"] -ceq "no-store") "the mailbox API's answers, and sign-in's, are never cached"
        Check ("" + $answers["the app's page"].headers["cache-control"] -cne "no-store") "CONTROL: the app's files are not marked no-store, so the header above is the API's own"
        $up = Get-UpgradeHeaders -Path ($mbPath + "/watch?since=0&max=1&timeoutMs=1000") -Authorization $bearer
        Check ($up.status -clike "HTTP/1.1 101*" -and $up.headers["content-security-policy"] -ceq $wantCsp -and $up.headers["x-content-type-options"] -ceq "nosniff" -and $up.headers["strict-transport-security"] -ceq "max-age=63072000; includeSubDomains") ("strict headers on a WebSocket upgrade too (" + $up.status + ")")

        Write-Host ""
        Write-Host "--- deny by default ---" -ForegroundColor Cyan
        foreach ($c in @(
                @{ what = "a read"; m = "GET"; p = ($mbPath + "/items?since=0&max=1"); b = $null },
                @{ what = "a put"; m = "POST"; p = ($mbPath + "/items"); b = '{"key":"k","text":"t"}' },
                @{ what = "an ack"; m = "POST"; p = ($mbPath + "/ack"); b = '{"through":0}' },
                @{ what = "a path that does not exist"; m = "GET"; p = "/v1/nothing/here"; b = $null })) {
            $none = Send-Raw $c.m $c.p $c.b
            $wrong = Send-Raw $c.m $c.p $c.b ("Bearer " + ("0" * 64))
            $elsewhere = Send-Raw $c.m $c.p $c.b $bearer "relay.example.workers.dev"
            Check ($none.code -eq 401 -and $wrong.code -eq 401 -and $elsewhere.code -eq 401) ("" + $c.what + " is 401 with no token, a wrong token, and the right token sent to a name that is not this machine (" + $none.code + ", " + $wrong.code + ", " + $elsewhere.code + ")")
        }
        $ok404 = Send-Raw "GET" "/v1/nothing/here" $null $bearer
        Check ($ok404.code -eq 404) "CONTROL: signed in, the path that does not exist is 404 - the 401 above hid it"
        $upNone = Get-UpgradeHeaders -Path ($mbPath + "/watch?since=0&max=1&timeoutMs=1000") -Authorization "Bearer nobody"
        Check ($upNone.status -clike "HTTP/1.1 401*") ("a watch nobody vouched for is refused before it is upgraded (" + $upNone.status + ")")
        Check ((Get-HordeCloudflareRelayFreePort) -gt 0) "CONTROL: the port probe works"

        Write-Host ""
        Write-Host "--- the caps and the refusals ---" -ForegroundColor Cyan
        $max = [int](Get-HordeRelay -Name "cloudflare").limits.maxTextChars
        Check ($max -eq 65536) ("the relay declares 64 KiB texts (" + $max + ")")
        $full = Send-Raw "POST" ($mbPath + "/items") ('{"key":"full","text":"' + ("a" * $max) + '"}') $bearer
        $over = Send-Raw "POST" ($mbPath + "/items") ('{"key":"over","text":"' + ("a" * ($max + 1)) + '"}') $bearer
        Check ($full.code -eq 200 -and $over.code -eq 413) ("a text of 65536 characters is taken and one of 65537 is 413 (" + $full.code + ", " + $over.code + ")")
        $quoted = Send-Raw "POST" ($mbPath + "/items") ('{"key":"quoted","text":"' + ('\"' * $max) + '"}') $bearer
        Check ($quoted.code -eq 200) ("a text of 65536 quote marks, each written as two in JSON, is still taken: the body's cap counts the escapes (" + $quoted.code + ")")
        $flood = Send-Raw "POST" ($mbPath + "/items") ('{"key":"flood","text":"' + ("a" * (2 * $max + 2048)) + '"}') $bearer
        Check ($flood.code -eq 413) ("a body past the body cap is 413 before it is read (" + $flood.code + ")")
        # Not JSON: read whole, it would be refused as malformed (400); only the count as it is read says 413.
        $chunked = Send-Chunked -Path ($mbPath + "/items") -Body ("x" * (2 * $max + 2048)) -Authorization $bearer
        $smallChunked = Send-Chunked -Path ($mbPath + "/items") -Body '{"key":"chunked-small","text":"small"}' -Authorization $bearer
        Check ($smallChunked -clike "HTTP/1.1 200*") ("CONTROL: a small body sent in chunks is taken (" + $smallChunked + ")")
        Check ($chunked -clike "HTTP/1.1 413*") ("and so is one sent in chunks, with no length to judge it by, stopped as it is read (" + $chunked + ")")
        $badKey = Send-Raw "POST" ($mbPath + "/items") '{"key":"a key","text":"t"}' $bearer
        Check ($badKey.code -eq 400 -and $badKey.text.Contains("the key is not")) ("a bad key is refused by the Worker itself, in its words, before the mailbox is asked (" + $badKey.text + ")")
        foreach ($c in @(
                @{ what = "a body that is not JSON"; b = 'not json'; code = 400 },
                @{ what = "a body with a member too many"; b = '{"key":"k","text":"t","extra":1}'; code = 400 },
                @{ what = "a body with a member missing"; b = '{"key":"k"}'; code = 400 },
                @{ what = "a key with a space"; b = '{"key":"a key","text":"t"}'; code = 400 },
                @{ what = "a text that is not ASCII"; b = ('{"key":"k","text":"caf' + [char]0x00e9 + '"}'); code = 400 },
                @{ what = "a text with a line break"; b = '{"key":"k","text":"a\nb"}'; code = 400 },
                @{ what = "an empty text"; b = '{"key":"k","text":""}'; code = 400 })) {
            $r = Send-Raw "POST" ($mbPath + "/items") $c.b $bearer
            Check ($r.code -eq $c.code) ("" + $c.what + " is " + $c.code + " (" + $r.code + ": " + $r.text + ")")
        }
        foreach ($c in @(
                @{ what = "a cursor with a leading zero"; p = ($mbPath + "/items?since=01&max=1"); code = 400 },
                @{ what = "a cursor past 2^53-1"; p = ($mbPath + "/items?since=9007199254740992&max=1"); code = 400 },
                @{ what = "a batch of 0"; p = ($mbPath + "/items?since=0&max=0"); code = 400 },
                @{ what = "a batch of 257"; p = ($mbPath + "/items?since=0&max=257"); code = 400 },
                @{ what = "a read with no cursor"; p = ($mbPath + "/items?max=1"); code = 400 },
                @{ what = "a watch that is not an upgrade"; p = ($mbPath + "/watch?since=0&max=1&timeoutMs=100"); code = 426 },
                @{ what = "a read of a device-named mailbox"; p = "/v1/mailboxes/con/phone/items?since=0&max=1"; code = 400 },
                @{ what = "a read of a mailbox in capitals"; p = "/v1/mailboxes/Work/phone/items?since=0&max=1"; code = 400 },
                @{ what = "a GET of an ack"; p = ($mbPath + "/ack"); code = 405 })) {
            $r = Send-Raw "GET" $c.p $null $bearer
            Check ($r.code -eq $c.code) ("" + $c.what + " is " + $c.code + " (" + $r.code + ")")
        }
        $wt = Send-Raw "GET" ($mbPath + "/watch?since=0&max=1&timeoutMs=60001") $null $bearer -Extra @{ Upgrade = "websocket"; Connection = "Upgrade"; "Sec-WebSocket-Version" = "13"; "Sec-WebSocket-Key" = "dGhlIHNhbXBsZSBub25jZQ==" }
        Check ($wt.code -eq 400) ("a watch past 60 s is 400 (" + $wt.code + ")")
        $past = Send-Raw "POST" ($mbPath + "/ack") '{"through":99}' $bearer
        $neg = Send-Raw "POST" ($mbPath + "/ack") '{"through":-1}' $bearer
        $frac = Send-Raw "POST" ($mbPath + "/ack") '{"through":1.5}' $bearer
        Check ($past.code -eq 409 -and $neg.code -eq 400 -and $frac.code -eq 400) ("an ack past the head is 409, and of -1 or 1.5 is 400 (" + $past.code + ", " + $neg.code + ", " + $frac.code + ")")
        $refusalTexts = @($over.text, $past.text, $flood.text) -join " "
        Check (-not $refusalTexts.Contains("aaaa")) "a refusal never quotes what the request carried"

        Write-Host ""
        Write-Host "--- one answer fits one WebSocket message ---" -ForegroundColor Cyan
        $big = "/v1/mailboxes/worker-test/big"
        for ($i = 1; $i -le 20; $i++) { $null = Send-Raw "POST" ($big + "/items") ('{"key":"big-' + $i + '","text":"' + ([string][char](96 + $i) * $max) + '"}') $bearer }
        $read = Send-Raw "GET" ($big + "/items?since=0&max=256") $null $bearer
        $items = @(($read.text | ConvertFrom-Json).items)
        $chars = 0; foreach ($it in $items) { $chars += $it.text.Length }
        Check ($read.code -eq 200 -and $items.Count -eq 15 -and $chars -le 1000000 -and $items[0].seq -eq 1) ("a read of 256 stops at 15 items of 64 KiB, under a million characters (" + $items.Count + " items, " + $chars + " characters)")
        $conn = (Connect-HordeRelay -Name "cloudflare" -Options @{ origin = $dev.value.origin; authorization = $bearer }).value
        $w = Wait-HordeRelayItems -Connection $conn -Mailbox "worker-test/big" -Since 15 -Max 256 -TimeoutMs 5000
        Check ($w.state -ceq "known" -and @($w.value.items).Count -eq 5 -and $w.value.next -eq 20) ("a watch's one message carries what fits, and the port reads on from its cursor (" + $w.state + " " + $w.reason + ")")
        $wAll = Wait-HordeRelayItems -Connection $conn -Mailbox "worker-test/big" -Since 0 -Max 256 -TimeoutMs 5000
        Check ($wAll.state -ceq "known" -and @($wAll.value.items).Count -eq 15) ("a watch with 20 full items waiting gets 15 in its one message, not a message too large to send (" + $wAll.state + " " + $wAll.reason + ")")

        Write-Host ""
        Write-Host "--- keys, and the machine's adapter ---" -ForegroundColor Cyan
        $km = "worker-test/keys"
        $k1 = Send-HordeRelayItem -Connection $conn -Mailbox $km -Text "keyed" -Key "same-key"
        $null = Confirm-HordeRelayItems -Connection $conn -Mailbox $km -Through $(if ($k1.state -ceq "known") { $k1.value.seq } else { [long]0 })
        $k2 = Send-HordeRelayItem -Connection $conn -Mailbox $km -Text "keyed again" -Key "same-key"
        Check ($k1.state -ceq "known" -and $k2.state -ceq "known" -and $k1.value.seq -eq 1 -and $k2.value.duplicate -eq $false -and $k2.value.seq -eq 2) "a key is free again once its item is trimmed: the put after the ack is a new item, numbered on"
        $odd = 'a "quoted" \ back\slashed \" text'
        $po = Send-HordeRelayItem -Connection $conn -Mailbox "worker-test/odd" -Text $odd
        $ro = Receive-HordeRelayItems -Connection $conn -Mailbox "worker-test/odd" -Since 0
        Check ($po.state -ceq "known" -and $ro.state -ceq "known" -and @($ro.value.items).Count -eq 1 -and $ro.value.items[0].text -ceq $odd) "quotes and backslashes go through the adapter and come back as they were put"
        $kp = Confirm-HordeRelayItems -Connection $conn -Mailbox "worker-test/odd" -Through 99
        Check ($kp.state -ceq "unknown" -and "$($kp.reason)".Contains("409") -and "$($kp.reason)".Contains("past it")) ("a refusal reaches the caller with the relay's status and words (" + $kp.reason + ")")

        Write-Host ""
        Write-Host "--- a sender trims its own stream: the adapter's put, and what the Worker asks of one ---" -ForegroundColor Cyan
        # relays/Port.ps1, A SENDER TRIMS ITS OWN STREAM. The whole contract is the conformance suite's; here,
        # the adapter's own part - the query it adds and the count it reads back - and the API's checks
        # of a keepFrom, each provoked on purpose.
        $tm = "worker-test/trim"
        $tmPath = "/v1/mailboxes/" + $tm
        $sk = { param([int]$Seq) return (("d4" * 16) + "/decisions/" + $Seq + "/" + ("0" * 20) + $Seq.ToString("0000")) }
        $trimTexts = { return (@((Receive-HordeRelayItems -Connection $conn -Mailbox $tm -Since 0).value.items | ForEach-Object { $_.text }) -join ",") }
        foreach ($i in 1..3) { $null = Send-HordeRelayItem -Connection $conn -Mailbox $tm -Text ("s" + $i) -Key (& $sk $i) }
        $t4 = Send-HordeRelayItem -Connection $conn -Mailbox $tm -Text "s4" -Key (& $sk 4) -KeepFrom 3
        Check ($t4.state -ceq "known" -and $t4.value.seq -eq 4 -and $t4.value.trimmed -eq 2 -and (& $trimTexts) -ceq "s3,s4") ("the adapter's put that says to keep from seq 3 is taken, and reads back that the Worker trimmed the 2 before it (" + $t4.reason + "; held " + (& $trimTexts) + ")")
        $plainAnswer = Send-Raw "POST" ($tmPath + "/items") ('{"key":"' + (& $sk 5) + '","text":"s5"}') $bearer
        $trimAnswer = Send-Raw "POST" ($tmPath + "/items?keepFrom=5") ('{"key":"' + (& $sk 6) + '","text":"s6"}') $bearer
        Check ($plainAnswer.code -eq 200 -and -not $plainAnswer.text.Contains("trimmed") -and $trimAnswer.code -eq 200 -and $trimAnswer.text.Contains('"trimmed":2')) ("a put that asks for no trim is answered as it always was, with nothing of one; a put that asks is answered with how many (" + $plainAnswer.text + " / " + $trimAnswer.text + ")")
        $refusedTrims = @(
            @{ q = "keepFrom=0"; key = (& $sk 7); why = "a keepFrom of 0" },
            @{ q = "keepFrom=x"; key = (& $sk 7); why = "a keepFrom that is no number" },
            @{ q = "keepFrom=07"; key = (& $sk 7); why = "a keepFrom with a leading zero" },
            @{ q = "keepFrom=8"; key = (& $sk 7); why = "a keepFrom past the key's own seq" },
            @{ q = "keepFrom=1"; key = "names-no-stream"; why = "a key that names no stream" },
            @{ q = "keepFrom=1"; key = (("d4" * 16) + "/decisions/07/" + ("0" * 24)); why = "a key whose seq has a leading zero" }
        ) | ForEach-Object { $r = Send-Raw "POST" ($tmPath + "/items?" + $_.q) ('{"key":"' + $_.key + '","text":"never"}') $bearer; [pscustomobject]@{ code = $r.code; why = $_.why } }
        Check (@($refusedTrims | Where-Object { $_.code -ne 400 }).Count -eq 0 -and (& $trimTexts) -ceq "s5,s6") ("a put that asks for a trim it may not have is refused, 400, and neither put nor trimmed: " + ((@($refusedTrims | ForEach-Object { $_.why + " " + $_.code }) -join "; ")) + " (held " + (& $trimTexts) + ")")
        $dc = Connect-HordeRelay -Name "cloudflare" -Options @{}
        Check ($dc.state -ceq "known" -and $null -ne $dc.value -and $dc.value.state.origin -ceq (Get-HordeCloudflareRelayDeployment).origin) "with no origin given, the adapter connects to the production origin wrangler.json names"

        Write-Host ""
        Write-Host "--- the phone's own client, over this Worker ---" -ForegroundColor Cyan
        $r = Invoke-HordeCloudflareRelayNode -Node $node -ArgList @((Join-Path $here "phone-over-worker.mjs"), $site, $dev.value.origin, $dev.value.token) -WorkDir $work -TimeoutSeconds 120
        $lines = @(("" + $r.out) -split "`r?`n" | Where-Object { $_ -ne "" })
        foreach ($l in $lines) { if ($l -clike "[[]PASS[]] *") { Check $true $l.Substring(7) } elseif ($l -clike "[[]FAIL[]] *") { Check $false $l.Substring(7) } }
        Check ($r.code -eq 0 -and @($lines | Where-Object { $_ -ceq "[DONE] 0" }).Count -eq 1 -and @($lines | Where-Object { $_ -clike "[[]PASS[]] *" }).Count -ge 7) ("the phone's checks ran to their end (" + $r.code + "; " + ("" + $r.err).Trim() + ")")

        Write-Host ""
        Write-Host "--- the committed placeholder vouches for no one ---" -ForegroundColor Cyan
        $plain = Start-HordeCloudflareRelayDev -Work (Join-Path $work "dev-placeholder") -Site $site -Script $tools.value.script -CommittedTestBinding
        try {
            Check ($plain.state -ceq "known") ("a dev with test-bindings.json exactly as committed starts (" + $plain.reason + ")")
            if ($plain.state -ceq "known") {
                $pReq = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, ($plain.value.origin + $mbPath + "/items?since=0&max=1"))
                [void]$pReq.Headers.TryAddWithoutValidation("Authorization", "Bearer " + $placeholder)
                $pRes = $http.SendAsync($pReq).GetAwaiter().GetResult()
                $pCode = [int]$pRes.StatusCode
                $pRes.Dispose(); $pReq.Dispose()
                Check ($pCode -eq 401) ("the placeholder sent as the token is 401: too short to count (" + $pCode + ")")
            }
        } finally { if ($plain.state -ceq "known") { Stop-HordeCloudflareRelayDev -Dev $plain.value } }

        Write-Host ""
        Write-Host "--- a marked Google client is not set up: it never reaches Google ---" -ForegroundColor Cyan
        # 2026-10-14: the secrets were stored with a byte order mark in front, and Google refused the id.
        # A dev with the marked id must refuse to start a sign-in (503); its twin, the same id clean, must
        # redirect with it - and the deploy's own check (Deploy.ps1) must tell the two apart.
        $gId = "123456789012-fakeclientforhordetests0000000000.apps.googleusercontent.com"
        $gSecret = "GOCSPX-fakeSecretForHordeTests0123456"
        foreach ($t in @(@{ what = "marked"; id = ([string][char]0xFEFF + $gId) }, @{ what = "clean"; id = $gId })) {
            $gd = Start-HordeCloudflareRelayDev -Work (Join-Path $work ("dev-google-" + $t.what)) -Site $site -Script $tools.value.script -ExtraVars @{ GOOGLE_CLIENT_ID = $t.id; GOOGLE_CLIENT_SECRET = $gSecret }
            try {
                Check ($gd.state -ceq "known") ("a dev with the " + $t.what + " client id starts (" + $gd.reason + ")")
                if ($gd.state -cne "known") { continue }
                $gRes = $http.GetAsync($gd.value.origin + "/auth/google").GetAwaiter().GetResult()
                $gCode = [int]$gRes.StatusCode
                $gLoc = $(if ($null -ne $gRes.Headers.Location) { $gRes.Headers.Location.OriginalString } else { "" })
                $gText = $gRes.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                $gRes.Dispose()
                $gCheck = Test-HordeCloudflareRelaySignInClient -Origin $gd.value.origin -ClientId $gId -Tries 1
                if ($t.what -ceq "marked") {
                    Check ($gCode -eq 503 -and $gText.Contains("sign-in is not set up") -and $gLoc -eq "") ("with the marked id, the sign-in start is 503 'not set up', and nothing is sent to Google (" + $gCode + ")")
                    Check ($gCheck.state -ceq "unknown" -and "$($gCheck.reason)".Contains("503")) ("and the deploy's check fails it (" + $gCheck.reason + ")")
                } else {
                    Check ($gCode -eq 303 -and (Get-HordeCloudflareRelayLocationClientId -Location $gLoc) -ceq $gId) ("CONTROL: its clean twin redirects to Google with the id exactly (" + $gCode + ")")
                    Check ($gCheck.state -ceq "known") ("and the deploy's check passes it (" + $gCheck.reason + ")")
                }
            } finally { if ($gd.state -ceq "known") { Stop-HordeCloudflareRelayDev -Dev $gd.value } }
        }
    }
} finally {
    $http.Dispose()
    if ($dev.state -ceq "known") { Stop-HordeCloudflareRelayDev -Dev $dev.value }
    if ($work -like "*horde-cf-worker-*" -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
Check (-not (Test-Path -LiteralPath $work)) "the suite's folder is gone"

Complete-HordeSuite -Success "the Worker answers with strict headers, nobody without sign-in, nothing over its cap, and its production config cannot turn the test authenticator on"
