# DOES THE HOSTED RELAY TAKE A SIGNED-IN PHONE'S JOIN REQUEST ONLY THROUGH ITS JOIN ROUTE, HOLD IT TO
# ITS LIMITS - ONE PENDING AN ACCOUNT, CAPS AN HOUR PER ACCOUNT AND PER ADDRESS, TEN MINUTES' LIFE -
# REFUSING, NEVER DROPPING, AND LET A MACHINE FREE THE SLOT AT ONCE, A REJECT BLOCKING THE ADDRESS?
#
# Phone-started pairing ("Add this phone"; worker/join.js, the section JOIN REQUESTS). Against a local
# dev of the Worker with a local fake provider, as test-cloudflare-accounts.ps1 and
# test-cloudflare-limits.ps1 run one, with small limits through the test-only binding
# HORDE_RELAY_TEST_LIMITS (worker/limits.js) - a short life, so expiry is seen in seconds - and the
# client address and the country named per request by the test headers (worker/client-address.js,
# worker/join.js). Each limit has its must-refuse and its must-accept twin:
#   - a request lands as the one canonical item in the named machine's mailbox under join/<request>,
#     and the machine reads it with its own signed request;
#   - one pending an account: another id refused 409 join-pending, the same id answered again;
#   - the account's cap and the address's cap an hour, each refused 429 while the other still takes,
#     and a refusal by one spends nothing of the other;
#   - a pending request expires, and the slot is free;
#   - the machine's close: rejected frees the slot at once and blocks that address; expired frees it
#     and blocks nothing; a phone may not close, nor another machine of the account;
#   - nobody puts a join/ item into a mailbox straight; a machine of another account, or none, is
#     refused; every malformed field is refused 400; the phone's own client says the code word.
#
# NODE IS NEEDED, and the pinned wrangler (relays/cloudflare/Wrangler.ps1 installs it outside the tree),
# and a key store (relay/Keys.ps1); without them the suite says so and exits 3, never 0. The machines'
# identities are made with the software provider in Horde homes of the suite's own under %TEMP%, and
# every key is removed at the end and checked gone. Google and Cloudflare are never contacted.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "relays\Port.ps1")
foreach ($f in @(Get-HordeRelayFiles)) { . $f }
. (Join-Path $root "relay\Pairing.ps1")
. (Join-Path $root "cli\RelayDeploy.ps1")
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Net.Http
Add-Type -AssemblyName System.Numerics
Write-Host ("  runtime: PowerShell " + $PSVersionTable.PSVersion + " (" + $PSVersionTable.PSEdition + ")") -ForegroundColor DarkGray

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$work = Join-Path $env:TEMP ("horde-cf-join-" + [guid]::NewGuid().ToString("N").Substring(0, 12))
[void][System.IO.Directory]::CreateDirectory($work)

$node = Find-HordeCloudflareRelayNode
if ($node -eq "") {
    Write-Host "  [SKIP] no node here: nothing of the Worker can be run" -ForegroundColor Yellow
    Remove-Item -LiteralPath $work -Recurse -Force
    Complete-HordeSuite -Success "NOTHING RUN: no node" -PassCode 3
}
$tools = Install-HordeCloudflareRelayTools
$store = Get-HordeRelayKeyStore
if ($tools.state -cne "known" -or $store.state -cne "known") {
    Write-Host ("  [SKIP] the Worker or the machines cannot be run here: " + $(if ($tools.state -cne "known") { $tools.reason } else { $store.reason })) -ForegroundColor Yellow
    Remove-Item -LiteralPath $work -Recurse -Force
    Complete-HordeSuite -Success "NOTHING RUN: the Worker cannot be run here" -PassCode 3
}

$clientId = "1234567890-fakeclient.apps.googleusercontent.com"
$clientSecret = "GOCSPX-" + (New-HordeCloudflareRelayToken).Substring(0, 28)
$script:homes = New-Object System.Collections.ArrayList
$script:procs = New-Object System.Collections.ArrayList
$script:signers = New-Object System.Collections.ArrayList
$devs = New-Object System.Collections.ArrayList
. (Join-Path $here "Harness.ps1")

# THE LIMITS HERE: 3 join requests an account an hour, 2 an address, a pending request's life 10 s - long
# enough for one account's checks to run inside it, short enough to wait out once. Sign-ins and phones
# out of the way (their limits are test-cloudflare-limits.ps1's).
$lifeMs = 10000
$limits = '{"signInStartsPerMinute":1000,"newAccountsPerDay":1000,"phonesPerAccount":100,"joinRequestsPerHour":3,"joinRequestsPerHourPerAddress":2,"joinRequestMs":' + $lifeMs + '}'
$label = "Pixel 9"
$agent = "Mozilla/5.0 (Linux; Android 14; Pixel 9) Chrome/129.0"

$script:addressCount = 0
function New-Address { $script:addressCount++; return ("10.30." + [Math]::Floor($script:addressCount / 250) + "." + (($script:addressCount % 250) + 1)) }
function New-Id { return [guid]::NewGuid().ToString("N") }
function New-Phone {
    param([string]$Sub)
    $r = Invoke-SignIn -Dev $dev -Provider $fake -Scenario @{ sub = $Sub; email = ($Sub + "@example.test") } -Address (New-Address)
    $r | Add-Member -NotePropertyName cookie -NotePropertyValue ("__Host-horde-session=" + $r.session)
    return $r
}
function New-Machine {
    # A machine registered by -Phone's account: { home; kid; signer; reg; conn (its port connection) }.
    param($Phone, [string]$Label = "box")
    $m = New-TestHome -Horde "work"
    $offer = New-HordeRelayPairingOffer -HordeHome $m.home -RpId "relay.example.test" -Origins @("https://relay.example.test") -Label $Label
    $reg = Send-To -Url ($O + "/v1/account/machines") -Method "POST" -Body (Get-Registration -OfferText $offer.value.text) -Cookie $Phone.cookie -Origin $O
    $s = (Open-HordeCloudflareRelaySigner -HordeHome $m.home).value
    [void]$script:signers.Add($s)
    $conn = (Connect-HordeRelay -Name "cloudflare" -Options @{ origin = $O; hordeHome = $m.home }).value
    return [pscustomobject]@{ home = $m.home; kid = $s.keyId; signer = $s; reg = $reg; conn = $conn; public = $m.identity.sign.public }
}
function Send-Signed {
    # One request signed by -Machine's key.
    param($Machine, [string]$Method = "GET", [string]$Target, [string]$Body = "")
    $bytes = New-Object byte[] 0
    if ($Body -ne "") { $bytes = [System.Text.Encoding]::ASCII.GetBytes($Body) }
    $auth = New-HordeCloudflareRelayMachineAuthorization -Key $Machine.signer.key -KeyId $Machine.kid -Origin $O -Method $Method -Target $Target -Body $bytes
    return (Send-To -Url ($O + $Target) -Method $Method -Body $Body -Authorization $auth)
}
function Get-Json { param($Answer) try { return ($Answer.text | ConvertFrom-Json) } catch { return $null } }
function Get-Code { param($Answer) $j = Get-Json $Answer; if ($null -ne $j -and $null -ne $j.PSObject.Properties["code"]) { return ("" + $j.code) }; return "" }
function Get-JoinBody {
    param([string]$Machine, [string]$Request, [hashtable]$Over = @{})
    $b = [ordered]@{ machine = $Machine; request = $Request; label = $label; agent = $agent; requestKey = $requestKey }
    foreach ($k in @($Over.Keys)) { $b[$k] = $Over[$k] }
    return ($b | ConvertTo-Json -Compress)
}
function Send-Join {
    # A phone's join request, as the app's page sends it, from -Address, naming -Country (the test header).
    param($Phone, [string]$Machine, [string]$Request, [string]$Address, [string]$Country = "", [hashtable]$Over = @{}, [string]$Body = "", [string]$Origin = "")
    if ($Body -eq "") { $Body = Get-JoinBody -Machine $Machine -Request $Request -Over $Over }
    if ($Origin -eq "") { $Origin = $O }
    $req = New-Object System.Net.Http.HttpRequestMessage((New-Object System.Net.Http.HttpMethod("POST")), ($O + "/v1/account/join"))
    [void]$req.Headers.TryAddWithoutValidation("Cookie", $Phone.cookie)
    [void]$req.Headers.TryAddWithoutValidation("Origin", $Origin)
    [void]$req.Headers.TryAddWithoutValidation("Horde-Test-Client-Address", $Address)
    if ($Country -ne "") { [void]$req.Headers.TryAddWithoutValidation("Horde-Test-Country", $Country) }
    $req.Content = New-Object System.Net.Http.ByteArrayContent(, ([System.Text.Encoding]::ASCII.GetBytes($Body)))
    $req.Content.Headers.ContentType = New-Object System.Net.Http.Headers.MediaTypeHeaderValue("application/json")
    $res = $http.SendAsync($req).GetAwaiter().GetResult()
    try {
        $h = @{}
        foreach ($pair in @($res.Headers) + @($res.Content.Headers)) { $h[$pair.Key.ToLowerInvariant()] = @($pair.Value) }
        return [pscustomobject]@{ code = [int]$res.StatusCode; headers = $h; text = $res.Content.ReadAsStringAsync().GetAwaiter().GetResult(); cookies = @() }
    } finally { $res.Dispose(); $req.Dispose() }
}
function Close-Join {
    # The machine ends a join request through its own adapter (relays/cloudflare/Relay.ps1, -JoinClose).
    param($Machine, [string]$Request, [string]$Outcome)
    return (Close-HordeRelayJoinAtRelay -Connection $Machine.conn -Request $Request -Outcome $Outcome)
}
function Show { param($Answer) return ("" + $Answer.code + " " + (Get-Code $Answer) + " " + $Answer.text) }

try {
    $fake = Start-FakeProvider
    $site = Join-Path $work "site"
    $built = New-HordeRelayDeploySite -Out $site
    Check ($built.state -ceq "known") ("the phone app is built as the deploy builds it (" + $built.reason + ")")
    $vars = @{ HORDE_RELAY_TEST_OIDC = $fake.issuer; GOOGLE_CLIENT_ID = $clientId; GOOGLE_CLIENT_SECRET = $clientSecret; HORDE_RELAY_TEST_LIMITS = $limits }
    $d = Start-HordeCloudflareRelayDev -Work (Join-Path $work "dev") -Site $site -Script $tools.value.script -ExtraVars $vars
    Check ($d.state -ceq "known") ("a local dev of the Worker answers, with " + $limits + " (" + $d.reason + ")")
    if ($d.state -cne "known") { throw "no dev" }
    [void]$devs.Add($d.value)
    $dev = $d.value
    $O = $dev.origin

    $pA = New-Phone -Sub "400000000000000000001"
    $mA = New-Machine -Phone $pA -Label "home-pc"
    $mA2 = New-Machine -Phone $pA -Label "work-pc"
    Check ($pA.session -ne "" -and $mA.reg.code -eq 200 -and $mA2.reg.code -eq 200) "CONTROL: account A is signed in on a phone and has two machines"
    # A P-256 point the new phone would send: a machine's public signing key is one, uncompressed.
    $requestKey = ConvertTo-HordeRelayBase64Url -Bytes $mA2.public
    Check ($requestKey -cmatch '\A[A-Za-z0-9_-]{87}\z') ("CONTROL: the request key is 65 bytes of a P-256 point in base64url, 87 characters (" + $requestKey.Length + ")")

    Write-Host ""
    Write-Host "--- a request lands as the canonical item, read by the machine it names ---" -ForegroundColor Cyan
    $X1 = New-Address; $X2 = New-Address; $X3 = New-Address
    $req1 = New-Id
    $before = [System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $j1 = Send-Join -Phone $pA -Machine $mA.kid -Request $req1 -Address $X1 -Country "IL"
    $after = [System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $v1 = Get-Json $j1
    Check ($j1.code -eq 200 -and $null -ne $v1 -and $v1.request -ceq $req1 -and @($v1.PSObject.Properties.Name).Count -eq 2) ("a signed-in phone's join request is taken: 200 { request, expiresAt } (" + (Show $j1) + ")")
    $exp1 = [long]$v1.expiresAt
    Check ($exp1 -ge $before + $lifeMs - 2000 -and $exp1 -le $after + $lifeMs + 2000) ("and expires joinRequestMs after it was made, by the relay's clock (" + $exp1 + ")")
    $read = Receive-HordeRelayItems -Connection $mA.conn -Mailbox ("work/" + $mA.kid) -Since 0
    $expected = '{"v":1,"kind":"horde-relay-join-request","request":"' + $req1 + '","horde":"work","machine":"' + $mA.kid + '","label":"' + $label + '","agent":"' + $agent + '","requestKey":"' + $requestKey + '","country":"IL","requestedAt":' + ($exp1 - $lifeMs) + ',"expiresAt":' + $exp1 + '}'
    $items = @($(if ($read.state -ceq "known") { @($read.value.items) } else { @() }))
    Check ($read.state -ceq "known" -and $items.Count -eq 1 -and $items[0].key -ceq ("join/" + $req1)) ("the machine reads it with its own signed request, in its mailbox work/<its key id>, under join/<request> (" + $read.reason + ")")
    Check ($items.Count -eq 1 -and $items[0].text -ceq $expected) ("the item is exactly the canonical text, members in order, the country the caller's (" + $(if ($items.Count -gt 0) { $items[0].text } else { "none" }) + ")")
    $other = Receive-HordeRelayItems -Connection $mA2.conn -Mailbox ("work/" + $mA2.kid) -Since 0
    Check ($other.state -ceq "known" -and @($other.value.items).Count -eq 0) "and the account's other machine's mailbox holds nothing: the request goes to the machine it names"

    Write-Host ""
    Write-Host "--- one pending request an account ---" -ForegroundColor Cyan
    $second = Send-Join -Phone $pA -Machine $mA.kid -Request (New-Id) -Address $X2
    Check ($second.code -eq 409 -and (Get-Code $second) -ceq "join-pending") ("a second request, another id, is refused while the first is pending: 409 join-pending (" + (Show $second) + ")")
    $again = Send-Join -Phone $pA -Machine $mA.kid -Request $req1 -Address $X1 -Country "IL"
    Check ($again.code -eq 200 -and [long](Get-Json $again).expiresAt -eq $exp1) ("the same request again is answered 200 again, its expiry unchanged (" + (Show $again) + ")")
    $still = Receive-HordeRelayItems -Connection $mA.conn -Mailbox ("work/" + $mA.kid) -Since 0
    Check ($still.state -ceq "known" -and @($still.value.items).Count -eq 1) "and puts nothing more into the mailbox"

    Write-Host ""
    Write-Host "--- who may end a request ---" -ForegroundColor Cyan
    $byPhone = Send-To -Url ($O + "/v1/account/join/" + $req1 + "/close") -Method "POST" -Body '{"outcome":"rejected"}' -Cookie $pA.cookie -Origin $O
    Check ($byPhone.code -eq 403) ("a phone may not end a join request: 403 (" + (Show $byPhone) + ")")
    $byOther = Send-Signed -Machine $mA2 -Method "POST" -Target ("/v1/account/join/" + $req1 + "/close") -Body '{"outcome":"rejected"}'
    Check ($byOther.code -eq 403) ("another machine of the account may not end a request naming the first: 403, not freed:false (" + (Show $byOther) + ")")
    $stillPending = Send-Join -Phone $pA -Machine $mA.kid -Request (New-Id) -Address $X2
    Check ($stillPending.code -eq 409) "CONTROL: so the request is still pending"
    $machineAsks = Send-Signed -Machine $mA -Method "POST" -Target "/v1/account/join" -Body (Get-JoinBody -Machine $mA.kid -Request (New-Id))
    Check ($machineAsks.code -eq 403) ("a machine may not make a join request: only a phone asks to join (" + (Show $machineAsks) + ")")
    $badOutcome = Send-Signed -Machine $mA -Method "POST" -Target ("/v1/account/join/" + $req1 + "/close") -Body '{"outcome":"maybe"}'
    Check ($badOutcome.code -eq 400) ("an outcome that is not approved, rejected, expired or ended is refused 400 (" + (Show $badOutcome) + ")")

    Write-Host ""
    Write-Host "--- a reject frees the slot at once and blocks the address; an expiry blocks nothing ---" -ForegroundColor Cyan
    $rej = Close-Join -Machine $mA -Request $req1 -Outcome "rejected"
    Check ($rej.state -ceq "known" -and $rej.value.freed -eq $true -and $rej.value.asked -eq $true) ("the machine ends it, rejected, through its own adapter: freed (" + $rej.reason + ")")
    $req2 = New-Id
    $j2 = Send-Join -Phone $pA -Machine $mA.kid -Request $req2 -Address $X2
    Check ($j2.code -eq 200) ("AT ONCE a request from another address is taken: the slot is free (" + (Show $j2) + ")")
    $blocked = Send-Join -Phone $pA -Machine $mA.kid -Request (New-Id) -Address $X1
    Check ($blocked.code -eq 429 -and (Get-Code $blocked) -ceq "join-blocked" -and [int](Get-Header $blocked "retry-after") -gt 600) ("and the rejected request's address, with a token left, is refused 429 join-blocked for the hour (" + (Show $blocked) + ", Retry-After " + (Get-Header $blocked "retry-after") + ")")
    $exp2 = Close-Join -Machine $mA -Request $req2 -Outcome "expired"
    $exp2again = Close-Join -Machine $mA -Request $req2 -Outcome "expired"
    Check ($exp2.state -ceq "known" -and $exp2.value.freed -eq $true -and $exp2again.state -ceq "known" -and $exp2again.value.freed -eq $false) "ended as expired, it is freed; ended again, freed:false - a request that is not pending is not an error"
    $req3 = New-Id
    $j3 = Send-Join -Phone $pA -Machine $mA.kid -Request $req3 -Address $X2
    Check ($j3.code -eq 200) ("the same address asks again and is taken: an expiry blocks nothing (" + (Show $j3) + ")")
    $notPending = Send-Signed -Machine $mA2 -Method "POST" -Target ("/v1/account/join/" + (New-Id) + "/close") -Body '{"outcome":"rejected"}'
    Check ($notPending.code -eq 200 -and $notPending.text -ceq '{"freed":false}') ("a machine ending a request that is not the pending one: 200 {freed:false} (" + (Show $notPending) + ")")
    $ended = Close-Join -Machine $mA -Request $req3 -Outcome "ended"
    Check ($ended.state -ceq "known" -and $ended.value.freed -eq $true) "ended, it is freed"

    Write-Host ""
    Write-Host "--- the account's cap an hour ---" -ForegroundColor Cyan
    $capped = Send-Join -Phone $pA -Machine $mA.kid -Request (New-Id) -Address $X3
    Check ($capped.code -eq 429 -and (Get-Code $capped) -ceq "rate-limited" -and [int](Get-Header $capped "retry-after") -ge 1) ("the account's fourth request in the hour is refused 429 rate-limited, from an address that has made none (" + (Show $capped) + ")")

    Write-Host ""
    Write-Host "--- the address's cap an hour, and what a refusal spends ---" -ForegroundColor Cyan
    $pB = New-Phone -Sub "400000000000000000002"
    $mB = New-Machine -Phone $pB -Label "b-pc"
    $b1 = New-Id
    $jb1 = Send-Join -Phone $pB -Machine $mB.kid -Request $b1 -Address $X3
    $null = Close-Join -Machine $mB -Request $b1 -Outcome "ended"
    $b2 = New-Id
    $jb2 = Send-Join -Phone $pB -Machine $mB.kid -Request $b2 -Address $X3
    $null = Close-Join -Machine $mB -Request $b2 -Outcome "ended"
    Check ($jb1.code -eq 200 -and $jb2.code -eq 200) ("another account takes two requests from the address account A was refused from: the account's refusal spent none of the address's (" + (Show $jb1) + "; " + (Show $jb2) + ")")
    $addrCapped = Send-Join -Phone $pB -Machine $mB.kid -Request (New-Id) -Address $X3
    Check ($addrCapped.code -eq 429 -and (Get-Code $addrCapped) -ceq "rate-limited") ("the address's third in the hour is refused 429 rate-limited (" + (Show $addrCapped) + ")")
    $X4 = New-Address
    $jb3 = Send-Join -Phone $pB -Machine $mB.kid -Request (New-Id) -Address $X4
    Check ($jb3.code -eq 200) ("while another address may still request - the account's third, so the address's refusal spent none of the account's (" + (Show $jb3) + ")")

    Write-Host ""
    Write-Host "--- a pending request expires ---" -ForegroundColor Cyan
    $pC = New-Phone -Sub "400000000000000000003"
    $mC = New-Machine -Phone $pC -Label "c-pc"
    $X5 = New-Address; $X6 = New-Address
    $jc1 = Send-Join -Phone $pC -Machine $mC.kid -Request (New-Id) -Address $X5
    $jc2 = Send-Join -Phone $pC -Machine $mC.kid -Request (New-Id) -Address $X6
    Check ($jc1.code -eq 200 -and $jc2.code -eq 409) ("CONTROL: a request is pending, and another is refused (" + (Show $jc1) + "; " + (Show $jc2) + ")")
    $wait = [long](Get-Json $jc1).expiresAt - [System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + 500
    if ($wait -gt 0) { Start-Sleep -Milliseconds $wait }
    $jc3 = Send-Join -Phone $pC -Machine $mC.kid -Request (New-Id) -Address $X6
    Check ($jc3.code -eq 200) ("past joinRequestMs, with nobody acting, a new request is taken (" + (Show $jc3) + ")")

    Write-Host ""
    Write-Host "--- nobody puts a join request straight into a mailbox ---" -ForegroundColor Cyan
    $box = $O + "/v1/mailboxes/work/" + $mA.kid + "/items"
    $phonePut = Send-To -Url $box -Method "POST" -Body ('{"key":"join/' + (New-Id) + '","text":"forged"}') -Cookie $pA.cookie -Origin $O
    Check ($phonePut.code -eq 403) ("a phone's put of a join/ key is refused 403 (" + (Show $phonePut) + ")")
    $machinePut = Send-HordeRelayItem -Connection $mA2.conn -Mailbox ("work/" + $mA.kid) -Text "forged" -Key ("join/" + (New-Id))
    Check ($machinePut.state -ceq "unknown" -and $machinePut.reason.Contains("403")) ("and a machine's (" + $machinePut.reason + ")")
    $controlPut = Send-To -Url $box -Method "POST" -Body '{"key":"joined-x","text":"fine"}' -Cookie $pA.cookie -Origin $O
    Check ($controlPut.code -eq 200) "CONTROL: the same put under another key is taken"

    Write-Host ""
    Write-Host "--- what a join request may name, and how it must be made ---" -ForegroundColor Cyan
    $X7 = New-Address
    $foreign = Send-Join -Phone $pC -Machine $mA.kid -Request (New-Id) -Address $X7
    $nobody = Send-Join -Phone $pC -Machine (New-Id) -Request (New-Id) -Address $X7
    Check ($foreign.code -eq 404 -and $nobody.code -eq 404) ("a request naming another account's machine, or no machine at all, is refused 404 (" + (Show $foreign) + "; " + (Show $nobody) + ")")
    $csrf = Send-Join -Phone $pC -Machine $mC.kid -Request (New-Id) -Address $X7 -Origin "https://evil.example.test"
    Check ($csrf.code -eq 401) "a join request from another site's page is refused (CSRF)"
    $offCurve = New-Object byte[] 65
    $offCurve[0] = 4
    for ($i = 1; $i -lt 65; $i++) { $offCurve[$i] = 1 }
    $short = New-Object byte[] 64
    $short[0] = 4
    $malformed = [ordered]@{
        "a machine that is not a key id" = @{ machine = "NOT-A-KEY" }
        "a request id that is not 32 lower-case hex" = @{ request = ((New-Id).ToUpperInvariant()) }
        "a label with a quote" = @{ label = 'say "hi"' }
        "an empty label" = @{ label = "" }
        "an agent with a backslash" = @{ agent = 'a\b' }
        "an agent of 201 characters" = @{ agent = ("a" * 201) }
        "a request key of 64 bytes" = @{ requestKey = (ConvertTo-HordeRelayBase64Url -Bytes $short) }
        "a request key that is no point of the curve" = @{ requestKey = (ConvertTo-HordeRelayBase64Url -Bytes $offCurve) }
        "a request key that is not text" = @{ requestKey = 5 }
    }
    foreach ($what in @($malformed.Keys)) {
        $r = Send-Join -Phone $pC -Machine $mC.kid -Request (New-Id) -Address $X7 -Over $malformed[$what]
        Check ($r.code -eq 400) ($what + " is refused 400 (" + (Show $r) + ")")
    }
    $extra = Send-Join -Phone $pC -Machine $mC.kid -Request (New-Id) -Address $X7 -Body ('{"machine":"' + $mC.kid + '","request":"' + (New-Id) + '","label":"x","agent":"","requestKey":"' + $requestKey + '","more":1}')
    Check ($extra.code -eq 400) ("a body with a member more than the five is refused 400 (" + (Show $extra) + ")")
    $edge = Send-Join -Phone $pC -Machine $mC.kid -Request (New-Id) -Address $X7 -Over @{ agent = ""; label = "x" }
    Check ($edge.code -eq 409) ("CONTROL: an empty agent and a one-character label pass the checks (the one pending request then refuses it, 409: " + (Show $edge) + ")")

    Write-Host ""
    Write-Host "--- the phone's own client says which limit ---" -ForegroundColor Cyan
    $pD = New-Phone -Sub "400000000000000000004"
    $mD = New-Machine -Phone $pD -Label "d-pc"
    $script = Join-Path $work "join-client.mjs"
    $js = @'
import { pathToFileURL } from "node:url";
import { join } from "node:path";
const [, , siteDir, origin, sessionId, machine, requestKey, first, second] = process.argv;
const A = await import(pathToFileURL(join(siteDir, "app/account-client.js")).href);
const headers = { Cookie: "__Host-horde-session=" + sessionId, Origin: origin };
const account = A.accountClient((u, init) => fetch(u, { ...init, headers: { ...(init.headers || {}), ...headers } }), origin);
const one = await account.requestJoin({ machine, request: first, label: "Pixel 9", agent: "node", requestKey });
const two = await account.requestJoin({ machine, request: second, label: "Pixel 9", agent: "node", requestKey });
process.stdout.write(JSON.stringify({ one, two }));
'@
    [System.IO.File]::WriteAllText($script, $js, $utf8)
    $f1 = New-Id; $f2 = New-Id
    $nr = Invoke-HordeCloudflareRelayNode -Node $node -ArgList @($script, $site, $O, $pD.session, $mD.kid, $requestKey, $f1, $f2) -WorkDir $work -TimeoutSeconds 120
    $got = $null
    try { $got = ("" + $nr.out) | ConvertFrom-Json } catch { $got = $null }
    Check ($null -ne $got -and $got.one.state -ceq "known" -and $got.one.value.request -ceq $f1 -and $got.one.code -ceq "") ("the app's requestJoin makes the request: known { request, expiresAt } (" + $nr.out + $nr.err + ")")
    Check ($null -ne $got -and $got.two.state -ceq "unknown" -and $got.two.status -eq 409 -and $got.two.code -ceq "join-pending") "and a second is unknown, 409, with the code join-pending, so the screen can say another request is pending"

    Write-Host ""
    Write-Host "--- a request is taken once ---" -ForegroundColor Cyan
    $doneD = Close-Join -Machine $mD -Request $f1 -Outcome "ended"
    $reused = Send-Join -Phone $pD -Machine $mD.kid -Request $f1 -Address (New-Address)
    Check ($doneD.state -ceq "known" -and $doneD.value.freed -eq $true -and $reused.code -eq 409 -and (Get-Code $reused) -ceq "") ("a request id used before, its request ended, is refused 409: its item is still in the mailbox, and a request is taken once (" + (Show $reused) + ")")
    $freshD = Send-Join -Phone $pD -Machine $mD.kid -Request (New-Id) -Address (New-Address)
    Check ($freshD.code -eq 200) ("and that refusal held nothing: a new request is taken at once (" + (Show $freshD) + ")")
} finally {
    foreach ($dv in @($devs)) { Stop-HordeCloudflareRelayDev -Dev $dv }
    foreach ($p in @($script:procs)) { try { if (-not $p.HasExited) { $p.StandardInput.BaseStream.Close(); if (-not $p.WaitForExit(10000)) { $p.Kill() } } } catch { }; $p.Dispose() }
    foreach ($s in @($script:signers)) { try { $s.key.Dispose() } catch { } }
    $http.Dispose()
    $made = New-Object System.Collections.ArrayList
    foreach ($h in @($script:homes)) {
        foreach ($k in @(Get-TestKeyNames -HordeHome $h)) {
            [void]$made.Add($k)
            try { [void](Remove-HordeRelayKey -Name $k.n -Scope $k.s) } catch { Write-Host ("  cleanup of " + $k.n + " failed: " + $_.Exception.Message) -ForegroundColor Yellow }
        }
        if ((Split-Path -Leaf $h) -match '^horde-cf-accounts-home-[0-9a-f]{32}$') { Remove-Item -LiteralPath $h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    $left = @($made | Where-Object { (Find-HordeRelayCngKey -Name $_.n -Scope $_.s) -cne "" })
    Check ($made.Count -ge 4 -and $left.Count -eq 0) ("every key the suite's machines made is gone (" + $made.Count + " names, " + $left.Count + " left)")
    if ($work -like "*horde-cf-join-*" -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
Check (-not (Test-Path -LiteralPath $work)) "the suite's folder is gone"

Complete-HordeSuite -Success "a join request reaches the machine it names only through the join route, held to one pending an account and its caps an hour - refused, never dropped - and a machine frees the slot at once, a reject blocking the address"
