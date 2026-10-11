# relays/cloudflare/test/Harness.ps1 - what the hosted relay's account suites share: a local fake
# provider, machines with identities of their own, one request as a browser or a machine sends it, a
# whole sign-in, a WebSocket upgrade read off the wire, a registration and its grant. Dot-sourced by
# test-cloudflare-accounts.ps1 and test-cloudflare-limits.ps1, never run alone (it is no suite: the gate
# runs test-*.ps1 only).
#
# The suite sets, before it dot-sources this: $here (this folder), $node, $clientId and $clientSecret
# (the fake provider's client), $utf8, and the lists $script:homes and $script:procs, which it cleans up
# in its finally block. This file makes $http, which the suite disposes of.
#
# -Address (Send-To, Invoke-SignIn) sends Horde-Test-Client-Address: the client address a dev with the
# test limits binding takes it as (worker/client-address.js), so one machine can be many addresses.

function Start-FakeProvider {
    # The fake provider (fake-oidc.mjs): { process; issuer }, once it says its port.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $node
    $psi.Arguments = '"' + (Join-Path $here "fake-oidc.mjs") + '" ' + $clientId + ' ' + $clientSecret
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    [void]$script:procs.Add($p)
    $null = $p.StandardError.ReadToEndAsync()
    $line = $p.StandardOutput.ReadLineAsync()
    if (-not $line.Wait(30000) -or "" + $line.Result -cnotmatch '\APORT ([0-9]+)\z') { throw ("the fake provider did not start: " + $line.Result) }
    return [pscustomobject]@{ process = $p; issuer = ("http://127.0.0.1:" + $Matches[1]) }
}

function New-TestHome {
    param([string]$Horde = "work")
    $h = Join-Path $env:TEMP ("horde-cf-accounts-home-" + [guid]::NewGuid().ToString("N"))
    [void][System.IO.Directory]::CreateDirectory((Join-Path $h "settings"))
    [void]$script:homes.Add($h)
    [System.IO.File]::WriteAllText((Join-Path $h "settings\relay.json"), ('{"schemaVersion": 1, "settings": {"horde": "' + $Horde + '"}}'), $utf8)
    $id = New-HordeRelayMachineIdentity -HordeHome $h -Provider "software"
    if ($id.state -cne "known") { throw ("no identity: " + $id.reason) }
    return [pscustomobject]@{ home = $h; identity = $id.value }
}

function Get-TestKeyNames {
    param([string]$HordeHome)
    $out = New-Object System.Collections.ArrayList
    $dir = Join-Path $HordeHome "relay\identity"
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter "machine-*.json")) {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        $m = [regex]::Match($t, '"scope":"([a-z]+)","signName":"([a-z0-9-]+)".*"agreeName":"([a-z0-9-]+)"')
        if ($m.Success) { [void]$out.Add(@{ n = $m.Groups[2].Value; s = $m.Groups[1].Value }); [void]$out.Add(@{ n = $m.Groups[3].Value; s = $m.Groups[1].Value }) }
    }
    return @($out)
}

$handler = New-Object System.Net.Http.HttpClientHandler
$handler.AllowAutoRedirect = $false
$handler.UseCookies = $false
$http = New-Object System.Net.Http.HttpClient($handler)
$http.Timeout = [TimeSpan]::FromSeconds(30)

function Send-To {
    # One request, as a browser or a machine would send it: { code; headers (lower-case name -> values);
    # text; cookies (Set-Cookie values) }. -Cookie is the Cookie header, -Origin the Origin header.
    param([string]$Url, [string]$Method = "GET", [string]$Body = $null, [string]$Cookie = "", [string]$Origin = "", [string]$Authorization = "", [string]$Address = "")
    $req = New-Object System.Net.Http.HttpRequestMessage((New-Object System.Net.Http.HttpMethod($Method)), $Url)
    if ($Cookie -ne "") { [void]$req.Headers.TryAddWithoutValidation("Cookie", $Cookie) }
    if ($Origin -ne "") { [void]$req.Headers.TryAddWithoutValidation("Origin", $Origin) }
    if ($Authorization -ne "") { [void]$req.Headers.TryAddWithoutValidation("Authorization", $Authorization) }
    if ($Address -ne "") { [void]$req.Headers.TryAddWithoutValidation("Horde-Test-Client-Address", $Address) }
    if ($null -ne $Body -and $Body -ne "") {
        $req.Content = New-Object System.Net.Http.ByteArrayContent(, ([System.Text.Encoding]::ASCII.GetBytes($Body)))
        $req.Content.Headers.ContentType = New-Object System.Net.Http.Headers.MediaTypeHeaderValue("application/json")
    }
    $res = $http.SendAsync($req).GetAwaiter().GetResult()
    try {
        $h = @{}
        foreach ($pair in @($res.Headers) + @($res.Content.Headers)) { $h[$pair.Key.ToLowerInvariant()] = @($pair.Value) }
        $cookies = $(if ($h.ContainsKey("set-cookie")) { @($h["set-cookie"]) } else { @() })
        return [pscustomobject]@{ code = [int]$res.StatusCode; headers = $h; text = $res.Content.ReadAsStringAsync().GetAwaiter().GetResult(); cookies = $cookies }
    } finally { $res.Dispose(); $req.Dispose() }
}

function Get-Header { param($Answer, [string]$Name) if ($Answer.headers.ContainsKey($Name)) { return ("" + @($Answer.headers[$Name])[0]) }; return "" }

function Get-CookieValue {
    # The value a Set-Cookie list gives the cookie Name, or "" ("x" for a cleared one).
    param($Answer, [string]$Name)
    foreach ($c in @($Answer.cookies)) { if (("" + $c).StartsWith($Name + "=")) { return ("" + $c).Substring($Name.Length + 1).Split(";")[0] } }
    return ""
}

function Set-Scenario { param([string]$Issuer, [hashtable]$Scenario = @{}) $null = Send-To -Url ($Issuer + "/scenario") -Method "POST" -Body ($Scenario | ConvertTo-Json -Compress) }

function Invoke-SignIn {
    # A whole sign-in through the dev and the fake provider, as a browser: { start; callback; session;
    # refused } - session the __Host-horde-session value set, or "". -Mangle changes the callback first.
    param($Dev, $Provider, [hashtable]$Scenario = @{}, [scriptblock]$Mangle = $null, [string]$Address = "")
    Set-Scenario -Issuer $Provider.issuer -Scenario $Scenario
    $start = Send-To -Url ($Dev.origin + "/auth/google") -Address $Address
    $signin = Get-CookieValue $start "__Host-horde-signin"
    # A start the relay refused (a limit: worker/signin.js) sends the browser back to the app at once.
    if (-not (Get-Header $start "location").StartsWith($Provider.issuer + "/")) { return [pscustomobject]@{ start = $start; authorize = $null; callbackUrl = ""; signinCookie = ""; callback = $start; session = ""; refused = (Get-Header $start "horde-signin-refused") } }
    $auth = Send-To -Url (Get-Header $start "location")
    $cb = Get-Header $auth "location"
    $cookie = "__Host-horde-signin=" + $signin
    if ($null -ne $Mangle) { $m = & $Mangle $cb $cookie; $cb = $m[0]; $cookie = $m[1] }
    $back = Send-To -Url $cb -Cookie $cookie -Address $Address
    return [pscustomobject]@{ start = $start; authorize = $auth; callbackUrl = $cb; signinCookie = $cookie; callback = $back; session = (Get-CookieValue $back "__Host-horde-session"); refused = (Get-Header $back "horde-signin-refused") }
}

function Get-UpgradeStatus {
    # The status line of a WebSocket upgrade, read off the wire, with the given Cookie and Origin.
    param([string]$Origin, [string]$Path, [string]$Cookie, [string]$PageOrigin)
    $u = New-Object System.Uri($Origin)
    $tcp = New-Object System.Net.Sockets.TcpClient($u.Host, $u.Port)
    try {
        $s = $tcp.GetStream()
        $s.ReadTimeout = 10000
        $req = "GET " + $Path + " HTTP/1.1`r`nHost: " + $u.Authority + "`r`nUpgrade: websocket`r`nConnection: Upgrade`r`nSec-WebSocket-Version: 13`r`nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==`r`nCookie: " + $Cookie + $(if ($PageOrigin -ne "") { "`r`nOrigin: " + $PageOrigin } else { "" }) + "`r`n`r`n"
        $b = [System.Text.Encoding]::ASCII.GetBytes($req)
        $s.Write($b, 0, $b.Length)
        $buf = New-Object byte[] 4096
        $n = $s.Read($buf, 0, $buf.Length)
        return ([System.Text.Encoding]::ASCII.GetString($buf, 0, [Math]::Max(0, $n)).Split("`n")[0]).TrimEnd("`r")
    } finally { $tcp.Close() }
}

function Get-Registration {
    # The body a phone sends to register the machine of an offer (account-client.js), from its text.
    param([string]$OfferText, [hashtable]$Over = @{})
    $o = (Read-HordeRelayPairingOffer -Text $OfferText).value
    $b = [ordered]@{ horde = $o.horde; offer = $o.offer; machine = $o.machine; label = $o.label; signPublic = $o.signPublic; expiresAt = $o.expiresAt; grant = $o.grant }
    foreach ($k in @($Over.Keys)) { $b[$k] = $Over[$k] }
    return ($b | ConvertTo-Json -Compress)
}

function Get-Grant {
    # A grant signed here by -Key for these values: for the refusals the machine's own offers never make.
    param($Key, [string]$Horde, [string]$Offer, [string]$Machine, [long]$ExpiresAt, [string]$Label = "test-machine")
    return (ConvertTo-HordeRelayBase64Url -Bytes (New-HordeRelayEs256Signature -Key $Key -Bytes (Get-HordeRelayAccountGrantBytes -Horde $Horde -Offer $Offer -Machine $Machine -ExpiresAt $ExpiresAt -Label $Label)))
}

function ConvertTo-HighS {
    # The high-S twin of a low-S Authorization's signature: s replaced by n - s.
    param([string]$Authorization)
    $m = [regex]::Match($Authorization, 'sig=([A-Za-z0-9_-]{86})\z')
    $sig = ConvertFrom-HordeRelayBase64Url -Text $m.Groups[1].Value
    $n = [System.Numerics.BigInteger]::Parse("0FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551", [System.Globalization.NumberStyles]::HexNumber)
    $sBytes = New-Object byte[] 33
    for ($i = 0; $i -lt 32; $i++) { $sBytes[$i] = $sig[63 - $i] }
    $high = ($n - (New-Object System.Numerics.BigInteger -ArgumentList (, $sBytes))).ToByteArray()
    $out = New-Object byte[] 64
    [System.Array]::Copy($sig, 0, $out, 0, 32)
    for ($i = 0; $i -lt 32; $i++) { $out[63 - $i] = $(if ($i -lt $high.Length) { $high[$i] } else { 0 }) }
    return ($Authorization.Substring(0, $m.Groups[1].Index) + (ConvertTo-HordeRelayBase64Url -Bytes $out))
}
