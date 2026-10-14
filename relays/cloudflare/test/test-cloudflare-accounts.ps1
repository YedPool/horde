# DOES THE HOSTED RELAY LET IN ONLY A PHONE SIGNED IN WITH GOOGLE AND A MACHINE THAT PHONE REGISTERED -
# EACH ONLY TO ITS OWN ACCOUNT - AND REFUSE EVERY FORGED, STALE, REPLAYED OR CROSS-SITE ATTEMPT?
#
# Relay PR 8b (the founder's plan of 2026-10-11): the auth seam of 8a, filled.
#   1. THE PURE MODULES, under node (units.mjs): the id token's every check, the machine request's
#      header and signed bytes, the cookies, the allowlist, the site's origin, the provider's key cache.
#   2. A LOCAL DEV OF THE WORKER with a LOCAL FAKE PROVIDER (fake-oidc.mjs), wired by the test-only
#      binding HORDE_RELAY_TEST_OIDC - Google is never contacted:
#      - sign-in: the redirect to the provider (code, PKCE S256, state, nonce, openid email profile),
#        the cookies (__Host-, HttpOnly, Secure, SameSite=Lax, Path=/), the session, sign-out;
#      - every id token the provider may lie with is refused: forged, unknown key, alg none, expired,
#        from the future, wrong audience, wrong issuer, wrong nonce, email unverified - and a callback
#        this browser did not start, with another state, or replaying a spent code;
#      - the provider's keys are fetched once for many sign-ins;
#      - CSRF: a cookie without the __Host- prefix is no session; a change carrying the cookie but
#        another Origin, or none, is refused, a watch too; a read is not a change;
#      - two accounts never see each other's mailboxes, though both name them alike;
#      - a machine: registered by the signed-in phone with its offer's account grant (relay/Pairing.ps1),
#        refused with a grant that does not verify, an expired or too-long offer, another key, another
#        account's key, a spent grant; then the machine's own adapter (Relay.ps1) signs every request and
#        reads the phone's mailbox; a replayed, stale, future, high-S, wrong-body, wrong-path or
#        unregistered signature is refused; the machine reaches only its horde, never the account; a
#        revoked key signs nothing more, and its spent grant cannot bring it back;
#      - the phone's own account and relay clients, signed in, over this Worker (node);
#      - the app itself in headless Chrome (browser-signin.mjs): the sign-in screen, Sign in with Google
#        through the provider and back, the cookie as Chrome keeps it, the Account screen, Sign out, a
#        refused sign-in said on the screen - when Chrome is installed; without it that part is skipped
#        and the suite exits 3;
#   3. A SECOND DEV WITH THE ALLOWLIST SWITCHED ON: the listed account signs in, another does not.
#
# NODE IS NEEDED, and the pinned wrangler (relays/cloudflare/Wrangler.ps1 installs it outside the tree);
# without them part 2 and 3 are skipped, said so, and the suite exits 3, never 0. A key store too
# (relay/Keys.ps1): the machines' identities are made with the software provider in Horde homes of the
# suite's own under %TEMP%, and every key is removed at the end and checked gone. Every dev and the
# fake provider are stopped in a finally block.

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
$work = Join-Path $env:TEMP ("horde-cf-accounts-" + [guid]::NewGuid().ToString("N").Substring(0, 12))
[void][System.IO.Directory]::CreateDirectory($work)

Write-Host ""
Write-Host "--- 1. the pure modules, under node ---" -ForegroundColor Cyan
$node = Find-HordeCloudflareRelayNode
if ($node -eq "") {
    Write-Host "  [SKIP] no node here: nothing of the Worker can be run" -ForegroundColor Yellow
    Remove-Item -LiteralPath $work -Recurse -Force
    Complete-HordeSuite -Success "NOTHING RUN: no node" -PassCode 3
}
$u = Invoke-HordeCloudflareRelayNode -Node $node -ArgList @((Join-Path $here "units.mjs"), $root) -WorkDir $work -TimeoutSeconds 120
$ulines = @(("" + $u.out) -split "`r?`n" | Where-Object { $_ -ne "" })
foreach ($l in $ulines) { if ($l -clike "[[]PASS[]] *") { Check $true $l.Substring(7) } elseif ($l -clike "[[]FAIL[]] *") { Check $false $l.Substring(7) } }
Check ($u.code -eq 0 -and @($ulines | Where-Object { $_ -ceq "[DONE] 0" }).Count -eq 1 -and @($ulines | Where-Object { $_ -clike "[[]PASS[]] *" }).Count -ge 40) ("the unit checks ran to their end (" + $u.code + ")")

Write-Host ""
Write-Host "--- 2. a local dev of the Worker, with a fake provider ---" -ForegroundColor Cyan
$tools = Install-HordeCloudflareRelayTools
$store = Get-HordeRelayKeyStore
if ($tools.state -cne "known" -or $store.state -cne "known") {
    Write-Host ("  [SKIP] the Worker or the machines cannot be run here: " + $(if ($tools.state -cne "known") { $tools.reason } else { $store.reason })) -ForegroundColor Yellow
    Remove-Item -LiteralPath $work -Recurse -Force
    Complete-HordeSuite -Success "the pure modules hold; the Worker itself was NOT RUN here" -PassCode 3
}

$clientId = "1234567890-fakeclient.apps.googleusercontent.com"
$clientSecret = "GOCSPX-" + (New-HordeCloudflareRelayToken).Substring(0, 28)
$script:homes = New-Object System.Collections.ArrayList
$script:procs = New-Object System.Collections.ArrayList
$devs = New-Object System.Collections.ArrayList

. (Join-Path $here "Harness.ps1")

$partial = $false
try {
    $fake = Start-FakeProvider
    Check ($fake.issuer -cmatch '\Ahttp://127\.0\.0\.1:[0-9]+\z') ("CONTROL: the fake provider listens on this machine (" + $fake.issuer + ")")
    $site = Join-Path $work "site"
    $built = New-HordeRelayDeploySite -Out $site
    Check ($built.state -ceq "known") ("the phone app is built as the deploy builds it (" + $built.reason + ")")
    # This suite signs in many times from one address and one account: the limits on that are
    # test-cloudflare-limits.ps1's, so here they are set out of its way (worker/limits.js).
    $roomy = '{"signInStartsPerMinute":1000,"newAccountsPerDay":1000,"phonesPerAccount":100}'
    $vars = @{ HORDE_RELAY_TEST_OIDC = $fake.issuer; GOOGLE_CLIENT_ID = $clientId; GOOGLE_CLIENT_SECRET = $clientSecret; HORDE_RELAY_TEST_LIMITS = $roomy }
    $d = Start-HordeCloudflareRelayDev -Work (Join-Path $work "dev") -Site $site -Script $tools.value.script -ExtraVars $vars
    Check ($d.state -ceq "known") ("a local dev of the Worker answers (" + $d.reason + ")")
    if ($d.state -cne "known") { throw "no dev" }
    [void]$devs.Add($d.value)
    $dev = $d.value
    $O = $dev.origin
    $mb = $O + "/v1/mailboxes/work/phone"

    Write-Host ""
    Write-Host "--- sign-in: the redirect, the cookies, the session ---" -ForegroundColor Cyan
    $a = Invoke-SignIn -Dev $dev -Provider $fake
    $loc = New-Object System.Uri((Get-Header $a.start "location"))
    $q = @{}
    foreach ($pair in $loc.Query.TrimStart("?").Split("&")) { $kv = $pair.Split("=", 2); $q[[System.Net.WebUtility]::UrlDecode($kv[0])] = [System.Net.WebUtility]::UrlDecode($kv[1]) }
    Check ($a.start.code -eq 303 -and $loc.GetLeftPart([System.UriPartial]::Path) -ceq ($fake.issuer + "/authorize")) ("the start redirects to the provider's authorization endpoint (" + $a.start.code + ")")
    Check ($q["response_type"] -ceq "code" -and $q["scope"] -ceq "openid email profile" -and $q["client_id"] -ceq $clientId -and $q["redirect_uri"] -ceq ($O + "/auth/google/callback") -and $q["code_challenge_method"] -ceq "S256" -and $q["code_challenge"] -cmatch '\A[A-Za-z0-9_-]{43}\z' -and $q["state"].Length -eq 43 -and $q["nonce"].Length -eq 43 -and -not $q.ContainsKey("code_verifier")) "asking for a code, openid email profile, PKCE S256, a state and a nonce, back to the callback - and never sending the verifier"
    $sc = @($a.start.cookies | Where-Object { $_.StartsWith("__Host-horde-signin=") })
    Check ($sc.Count -eq 1 -and $sc[0] -cmatch '\A__Host-horde-signin=[A-Za-z0-9_.-]+; Max-Age=600; Path=/; Secure; HttpOnly; SameSite=Lax\z') ("the sign-in's state, nonce and verifier wait in a __Host- cookie for ten minutes: HttpOnly, Secure, SameSite=Lax, Path=/ (" + ($sc -join " | ") + ")")
    Check ($a.callback.code -eq 303 -and (Get-Header $a.callback "location") -ceq ($O + "/app/index.html") -and $a.refused -ceq "") ("the callback signs in and sends the browser to the app (" + $a.callback.code + " " + $a.refused + ")")
    $ss = @($a.callback.cookies | Where-Object { $_.StartsWith("__Host-horde-session=") })
    Check ($ss.Count -eq 1 -and $ss[0] -cmatch '\A__Host-horde-session=[A-Za-z0-9_-]{43}; Max-Age=2592000; Path=/; Secure; HttpOnly; SameSite=Lax\z') ("the session is an opaque 256-bit id in a __Host- cookie for 30 days: HttpOnly, Secure, SameSite=Lax, Path=/ (" + ($ss -join " | ") + ")")
    Check (@($a.callback.cookies | Where-Object { $_ -clike "__Host-horde-signin=x; Max-Age=0;*" }).Count -eq 1) "and the sign-in's cookie is cleared"
    Check ((Get-Header $a.start "cache-control") -ceq "no-store" -and (Get-Header $a.callback "cache-control") -ceq "no-store") "no answer of sign-in is ever cached"
    $A1 = "__Host-horde-session=" + $a.session
    $who = Send-To -Url ($O + "/auth/session") -Cookie $A1
    Check ($who.code -eq 200 -and $who.text -ceq '{"signedIn":true,"email":"founder@example.test"}') ("the app can ask who is signed in (" + $who.text + ")")
    Check ((Send-To -Url ($O + "/auth/session")).text -ceq '{"signedIn":false,"email":""}') "and without the cookie, nobody is"
    $stats = (Send-To -Url ($fake.issuer + "/stats")).text | ConvertFrom-Json
    Check ($stats.tokens -eq 1 -and $stats.refusals -eq 0) "the provider took the code with the client's secret and a verifier matching the challenge (it checks both)"

    Write-Host ""
    Write-Host "--- every lying token, and every broken callback, is refused ---" -ForegroundColor Cyan
    $lies = [ordered]@{
        "a forged token (another key, the provider's key id)" = @{ forge = $true }
        "a token under a key id the provider does not publish" = @{ kid = "fake-9" }
        "a token signed with alg none" = @{ alg = "none" }
        "an expired token" = @{ expOffset = -3700 }
        "a token issued in the future" = @{ iatOffset = 120 }
        "a token for another client (aud)" = @{ aud = "999-other.apps.googleusercontent.com" }
        "a token from another issuer" = @{ iss = "https://accounts.example.test" }
        "a token for another sign-in (nonce)" = @{ nonce = "not-this-sign-in" }
        "a token whose email the provider does not vouch for" = @{ email_verified = $false }
    }
    foreach ($what in @($lies.Keys)) {
        $r = Invoke-SignIn -Dev $dev -Provider $fake -Scenario $lies[$what]
        Check ($r.callback.code -eq 303 -and (Get-Header $r.callback "location") -ceq ($O + "/app/index.html#signin-refused") -and $r.session -ceq "" -and $r.refused -ne "") ($what + " makes no session (" + $r.refused + ")")
    }
    $noStart = Invoke-SignIn -Dev $dev -Provider $fake -Mangle { param($cb, $cookie) return @($cb, "") }
    Check ($noStart.session -ceq "" -and $noStart.refused.Contains("started no sign-in")) ("a callback this browser did not start makes no session (" + $noStart.refused + ")")
    $otherState = Invoke-SignIn -Dev $dev -Provider $fake -Mangle { param($cb, $cookie) return @(($cb -replace 'state=[^&]+', ('state=' + ("A" * 43))), $cookie) }
    Check ($otherState.session -ceq "" -and $otherState.refused.Contains("state")) ("a callback with another state makes no session (" + $otherState.refused + ")")
    $stalled = Invoke-SignIn -Dev $dev -Provider $fake -Mangle { param($cb, $cookie) return @($cb, ($cookie -replace '\.[0-9]{13}\z', ("." + ([System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - 601000)))) }
    Check ($stalled.session -ceq "" -and $stalled.refused.Contains("ten minutes")) ("a sign-in begun more than ten minutes ago makes no session (" + $stalled.refused + ")")
    $plain = Invoke-SignIn -Dev $dev -Provider $fake -Mangle { param($cb, $cookie) return @($cb, $cookie.Replace("__Host-horde-signin=", "horde-signin=")) }
    Check ($plain.session -ceq "" -and $plain.refused.Contains("started no sign-in")) "a sign-in cookie without the __Host- prefix is not this browser's sign-in"
    $once = Invoke-SignIn -Dev $dev -Provider $fake
    $again = Send-To -Url $once.callbackUrl -Cookie $once.signinCookie
    Check ($once.session -ne "" -and (Get-CookieValue $again "__Host-horde-session") -ceq "" -and (Get-Header $again "horde-signin-refused").Contains("refused the code")) ("the same code a second time makes no session: the provider spends it (" + (Get-Header $again "horde-signin-refused") + ")")
    $deniedAtProvider = Send-To -Url ($O + "/auth/google/callback?error=access_denied&state=x") -Cookie $once.signinCookie
    Check ((Get-CookieValue $deniedAtProvider "__Host-horde-session") -ceq "" -and (Get-Header $deniedAtProvider "location").EndsWith("#signin-refused")) "a sign-in the account declined at the provider makes none"
    $stats = (Send-To -Url ($fake.issuer + "/stats")).text | ConvertFrom-Json
    Check ($stats.jwksFetches -eq 1) ("the provider's keys were fetched once for every sign-in above, forged and unknown key ids included (" + $stats.jwksFetches + ")")
    Check ((Send-To -Url ($O + "/auth/nothing")).code -eq 404 -and (Send-To -Url ($O + "/auth/google") -Method "POST" -Origin $O).code -eq 405) "an address under /auth/ that is not sign-in's is 404, and the start is GET only"

    Write-Host ""
    Write-Host "--- the session at the mailboxes, and CSRF ---" -ForegroundColor Cyan
    Check ((Send-To -Url ($mb + "/items?since=0&max=10") -Cookie $A1).code -eq 200) "a signed-in phone reads its mailbox"
    Check ((Send-To -Url ($mb + "/items?since=0&max=10") -Cookie ("horde-session=" + $a.session)).code -eq 401) "the same session id in a cookie without the __Host- prefix is refused"
    Check ((Send-To -Url ($mb + "/items?since=0&max=10") -Cookie ("__Host-horde-session=" + ("A" * 43))).code -eq 401) "a session id the relay never made is refused"
    $put = '{"key":"from-a","text":"hello from account a"}'
    Check ((Send-To -Url ($mb + "/items") -Method "POST" -Body $put -Cookie $A1 -Origin "https://evil.example.test").code -eq 401) "a put carrying the cookie from another site's page is refused (CSRF)"
    Check ((Send-To -Url ($mb + "/items") -Method "POST" -Body $put -Cookie $A1).code -eq 401) "and one with no Origin at all"
    Check ((Send-To -Url ($mb + "/items") -Method "POST" -Body $put -Cookie $A1 -Origin $O).code -eq 200) "CONTROL: the same put from the app's own origin is taken"
    $wsEvil = Get-UpgradeStatus -Origin $O -Path "/v1/mailboxes/work/phone/watch?since=0&max=1&timeoutMs=1000" -Cookie $A1 -PageOrigin "https://evil.example.test"
    $wsOwn = Get-UpgradeStatus -Origin $O -Path "/v1/mailboxes/work/phone/watch?since=0&max=1&timeoutMs=1000" -Cookie $A1 -PageOrigin $O
    Check ($wsEvil -clike "HTTP/1.1 401*" -and $wsOwn -clike "HTTP/1.1 101*") ("a watch opened from another site's page is refused, and from the app's own is upgraded (" + $wsEvil + "; " + $wsOwn + ")")

    $renamed = Invoke-SignIn -Dev $dev -Provider $fake -Scenario @{ email = "renamed@example.test" }
    $rr = (Send-To -Url ($mb + "/items?since=0&max=10") -Cookie ("__Host-horde-session=" + $renamed.session)).text | ConvertFrom-Json
    Check ($renamed.session -ne "" -and @($rr.items).Count -eq 1 -and $rr.items[0].text -ceq "hello from account a") "the account is the Google account id, never the email: the same account under a new address reaches the same mailboxes"

    Write-Host ""
    Write-Host "--- two accounts, apart ---" -ForegroundColor Cyan
    $b = Invoke-SignIn -Dev $dev -Provider $fake -Scenario @{ sub = "200000000000000000002"; email = "other@example.test" }
    $B1 = "__Host-horde-session=" + $b.session
    Check ($b.session -ne "" -and $b.session -cne $a.session) "a second Google account signs in to a session of its own"
    $readB = (Send-To -Url ($mb + "/items?since=0&max=10") -Cookie $B1).text | ConvertFrom-Json
    $readA = (Send-To -Url ($mb + "/items?since=0&max=10") -Cookie $A1).text | ConvertFrom-Json
    Check (@($readB.items).Count -eq 0 -and @($readA.items).Count -eq 1 -and $readA.items[0].text -ceq "hello from account a") "the second account's work/phone is empty: the first account's item is the first account's alone"
    $nb = Send-To -Url ($mb + "/items") -Method "POST" -Body '{"key":"from-b","text":"b"}' -Cookie $B1 -Origin $O
    Check ($nb.code -eq 200 -and ($nb.text | ConvertFrom-Json).seq -eq 1) "and numbers its own items from 1"

    Write-Host ""
    Write-Host "--- a machine: registered with its grant, then signing every request ---" -ForegroundColor Cyan
    $m1 = New-TestHome -Horde "work"
    $offer = New-HordeRelayPairingOffer -HordeHome $m1.home -RpId "relay.example.test" -Origins @("https://relay.example.test")
    Check ($offer.state -ceq "known") ("the machine makes an offer (" + $offer.reason + ")")
    $reg = Get-Registration -OfferText $offer.value.text
    $signer = (Open-HordeCloudflareRelaySigner -HordeHome $m1.home).value
    $kid = $signer.keyId
    $mc = (Connect-HordeRelay -Name "cloudflare" -Options @{ origin = $O; hordeHome = $m1.home }).value
    $before = Receive-HordeRelayItems -Connection $mc -Mailbox "work/phone" -Since 0
    Check ($before.state -ceq "unknown" -and $before.reason.Contains("401")) ("before a phone registers it, the machine's signed requests are refused (" + $before.reason + ")")
    Check ((Send-To -Url ($O + "/v1/account/machines") -Method "POST" -Body $reg -Origin $O).code -eq 401) "a registration with no session is refused"
    Check ((Send-To -Url ($O + "/v1/account/machines") -Method "POST" -Body $reg -Cookie $A1 -Origin "https://evil.example.test").code -eq 401) "and one from another site's page"
    $o2 = (Read-HordeRelayPairingOffer -Text $offer.value.text).value
    $late = Send-To -Url ($O + "/v1/account/machines") -Method "POST" -Body (Get-Registration -OfferText $offer.value.text -Over @{ expiresAt = ($o2.expiresAt + 1000) }) -Cookie $A1 -Origin $O
    Check ($late.code -eq 403) ("a grant presented with another expiry does not verify (" + $late.code + ")")
    $m2 = New-TestHome -Horde "work"
    $other = (Open-HordeCloudflareRelaySigner -HordeHome $m2.home).value
    $wrongKey = Send-To -Url ($O + "/v1/account/machines") -Method "POST" -Body (Get-Registration -OfferText $offer.value.text -Over @{ grant = (Get-Grant -Key $other.key -Horde "work" -Offer $o2.offer -Machine $o2.machine -ExpiresAt $o2.expiresAt) }) -Cookie $A1 -Origin $O
    Check ($wrongKey.code -eq 403) ("a grant signed by another machine's key is refused: a public key alone registers nothing (" + $wrongKey.code + ")")
    $otherPub = ConvertTo-HordeRelayBase64Url -Bytes $m2.identity.sign.public
    Check ((Send-To -Url ($O + "/v1/account/machines") -Method "POST" -Body (Get-Registration -OfferText $offer.value.text -Over @{ signPublic = $otherPub }) -Cookie $A1 -Origin $O).code -eq 400) "a signing key that is not the machine the offer names is refused"
    $nowMs = [System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $old = New-HordeRelayPairingOffer -HordeHome $m1.home -RpId "relay.example.test" -Origins @("https://relay.example.test") -Now ([datetime]::UtcNow.AddMinutes(-10))
    Check ((Send-To -Url ($O + "/v1/account/machines") -Method "POST" -Body (Get-Registration -OfferText $old.value.text) -Cookie $A1 -Origin $O).code -eq 400) "an expired offer's grant is refused"
    $far = $nowMs + 2000000
    $longGrant = Get-Grant -Key $signer.key -Horde "work" -Offer $o2.offer -Machine $kid -ExpiresAt $far
    Check ((Send-To -Url ($O + "/v1/account/machines") -Method "POST" -Body (Get-Registration -OfferText $offer.value.text -Over @{ expiresAt = $far; grant = $longGrant }) -Cookie $A1 -Origin $O).code -eq 400) "a grant the machine itself signed, but for longer than any offer lives, is refused"
    $ok = Send-To -Url ($O + "/v1/account/machines") -Method "POST" -Body $reg -Cookie $A1 -Origin $O
    Check ($ok.code -eq 200 -and ($ok.text | ConvertFrom-Json).keyId -ceq $kid -and ($ok.text | ConvertFrom-Json).duplicate -eq $false) ("the signed-in phone registers the machine with its offer's grant (" + $ok.text + ")")
    $dup = Send-To -Url ($O + "/v1/account/machines") -Method "POST" -Body $reg -Cookie $A1 -Origin $O
    Check ($dup.code -eq 200 -and ($dup.text | ConvertFrom-Json).duplicate -eq $true) "sending it again is a yes, already there"
    $offerB = New-HordeRelayPairingOffer -HordeHome $m1.home -RpId "relay.example.test" -Origins @("https://relay.example.test")
    Check ((Send-To -Url ($O + "/v1/account/machines") -Method "POST" -Body (Get-Registration -OfferText $offerB.value.text) -Cookie $B1 -Origin $O).code -eq 409) "another account cannot take the key, even with a fresh offer of its machine"
    $list = (Send-To -Url ($O + "/v1/account") -Cookie $A1).text | ConvertFrom-Json
    Check (@($list.machines).Count -eq 1 -and $list.machines[0].keyId -ceq $kid -and $list.machines[0].horde -ceq "work" -and $list.account.email -ceq "founder@example.test") "the account lists the machine"
    Check (@(((Send-To -Url ($O + "/v1/account") -Cookie $B1).text | ConvertFrom-Json).machines).Count -eq 0) "and the other account lists none"
    # WHEN THE MACHINE WAS LAST HEARD FROM (worker/presence.js; the phone's offline banner, 2026-10-14):
    # only a verified signed request of the machine sets it; it rides on the account's answer, beside the
    # relay's own now, to that account's phones only.
    $lastSeen = { $v = (Send-To -Url ($O + "/v1/account") -Cookie $A1).text | ConvertFrom-Json; return @($v.machines | Where-Object { $_.keyId -ceq $kid })[0].lastSeenAt }
    $localNow = [System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    Check (($list.now -is [long] -or $list.now -is [int]) -and [System.Math]::Abs([double]$list.now - [double]$localNow) -lt 10000) ("the answer carries the relay's own now, a whole number of ms (" + $list.now + ")")
    Check ($null -eq $list.machines[0].lastSeenAt -and @($list.machines[0].PSObject.Properties.Name) -contains "lastSeenAt") "a machine registered but not yet heard from is listed with lastSeenAt null: never seen"

    $heardFrom = [System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $r1 = Receive-HordeRelayItems -Connection $mc -Mailbox "work/phone" -Since 0
    Check ($r1.state -ceq "known" -and @($r1.value.items).Count -eq 1 -and $r1.value.items[0].text -ceq "hello from account a") ("the machine's own adapter, signing each request, reads the phone's mailbox in its account (" + $r1.reason + ")")
    $seen1 = & $lastSeen
    $seenView = (Send-To -Url ($O + "/v1/account") -Cookie $A1).text | ConvertFrom-Json
    Check ($null -ne $seen1 -and $seen1 % 1000 -eq 0 -and $seen1 -ge ($heardFrom - ($heardFrom % 1000) - 5000) -and $seen1 -le $seenView.now) ("a verified machine request records lastSeenAt, to the second, by the relay's clock (" + $seen1 + ", now " + $seenView.now + ")")
    $bText = (Send-To -Url ($O + "/v1/account") -Cookie $B1).text
    Check (-not $bText.Contains($kid) -and -not $bText.Contains("" + $seen1)) "a phone of another account never sees it: its answer names neither the machine nor its time"
    $p1 = Send-HordeRelayItem -Connection $mc -Mailbox ("work/" + $kid) -Text "from the machine" -Key "m-1"
    $w1 = Wait-HordeRelayItems -Connection $mc -Mailbox ("work/" + $kid) -Since 0 -Max 10 -TimeoutMs 3000
    $k1 = Confirm-HordeRelayItems -Connection $mc -Mailbox ("work/" + $kid) -Through 1
    Check ($p1.state -ceq "known" -and $w1.state -ceq "known" -and @($w1.value.items).Count -eq 1 -and $k1.state -ceq "known") ("and puts, watches over a signed WebSocket, and acks (" + $p1.reason + $w1.reason + $k1.reason + ")")
    $odd = Send-HordeRelayItem -Connection $mc -Mailbox "personal/phone" -Text "x"
    Check ($odd.state -ceq "unknown" -and $odd.reason.Contains("403")) ("but reaches no other horde's mailbox (" + $odd.reason + ")")

    # A SENDER TRIMS ITS OWN STREAM, AND ONLY ITS OWN (worker/api.js). The phone's mailbox of the horde
    # holds another machine's stream (put here by the phone, which may put under any key - a key is
    # only a name to the relay - so the other machine need not be registered for this), and this
    # machine's own. Who may delete what is decided by who signed the request, never by what it names.
    $nonce = { param([int]$N) return (("0" * 20) + $N.ToString("0000")) }
    $streamKey = { param([string]$Sender, [int]$Seq) return ($Sender + "/decisions/" + $Seq + "/" + (& $nonce $Seq)) }
    $heldTexts = { return (@(((Send-To -Url ($mb + "/items?since=0&max=50") -Cookie $A1).text | ConvertFrom-Json).items | ForEach-Object { $_.text }) -join ",") }
    foreach ($i in 1..2) { $null = Send-To -Url ($mb + "/items") -Method "POST" -Body ('{"key":"' + (& $streamKey $other.keyId $i) + '","text":"other-' + $i + '"}') -Cookie $A1 -Origin $O }
    foreach ($i in 1..3) { $null = Send-HordeRelayItem -Connection $mc -Mailbox "work/phone" -Text ("mine-" + $i) -Key (& $streamKey $kid $i) }
    Check ((& $heldTexts) -ceq "hello from account a,other-1,other-2,mine-1,mine-2,mine-3") ("CONTROL: the phone's mailbox holds another machine's stream and this machine's own (" + (& $heldTexts) + ")")
    $theirs = Send-HordeRelayItem -Connection $mc -Mailbox "work/phone" -Text "other-3-forged" -Key (& $streamKey $other.keyId 3) -KeepFrom 3
    Check ($theirs.state -ceq "unknown" -and $theirs.reason.Contains("403") -and (& $heldTexts) -ceq "hello from account a,other-1,other-2,mine-1,mine-2,mine-3") ("a machine that asks to trim ANOTHER machine's stream is refused, 403: nothing of that stream is deleted, and its put is not made (" + $theirs.reason + ")")
    $byPhone = Send-To -Url ($mb + "/items?keepFrom=4") -Method "POST" -Body ('{"key":"' + (& $streamKey $kid 4) + '","text":"mine-4-by-the-phone"}') -Cookie $A1 -Origin $O
    $byPhoneOwn = Send-To -Url ($mb + "/items?keepFrom=1") -Method "POST" -Body '{"key":"a-phone-key","text":"x"}' -Cookie $A1 -Origin $O
    Check ($byPhone.code -eq 403 -and $byPhoneOwn.code -eq 403 -and (& $heldTexts) -ceq "hello from account a,other-1,other-2,mine-1,mine-2,mine-3") ("A PHONE MAY NEVER TRIM: a signed-in phone that names keepFrom is refused, 403, whatever key it names, and nothing is put or deleted (" + $byPhone.code + ", " + $byPhoneOwn.code + ")")
    $mine = Send-HordeRelayItem -Connection $mc -Mailbox "work/phone" -Text "mine-4" -Key (& $streamKey $kid 4) -KeepFrom 3
    Check ($mine.state -ceq "known" -and $mine.value.trimmed -eq 2 -and (& $heldTexts) -ceq "hello from account a,other-1,other-2,mine-3,mine-4") ("the machine trims ITS OWN stream by its signed put: the two before seq 3 go, and the other machine's stream and the phone's item stay (" + (& $heldTexts) + ")")
    # THE TRIM IS UNDER THE MACHINE'S SIGNATURE: it is in the query, and the query is signed (the check
    # below, "a signature for one cursor does not read from another"). No request with a refused
    # signature is made here for it: this key's refusals are counted (worker/limits.js), and the
    # checks below spend nearly all of a minute's.
    $past = Send-To -Url ($mb + "/items?keepFrom=9") -Method "POST" -Body ('{"key":"' + (& $streamKey $kid 5) + '","text":"mine-5"}') -Authorization (New-HordeCloudflareRelayMachineAuthorization -Key $signer.key -KeyId $kid -Origin $O -Method "POST" -Target "/v1/mailboxes/work/phone/items?keepFrom=9" -Body ([System.Text.Encoding]::ASCII.GetBytes('{"key":"' + (& $streamKey $kid 5) + '","text":"mine-5"}')))
    Check ($past.code -eq 400 -and (& $heldTexts) -ceq "hello from account a,other-1,other-2,mine-3,mine-4") ("and the machine's own signed trim from past the key's seq is refused, 400, with nothing put: a put never deletes itself (" + $past.code + ")")
    Check ((Send-To -Url ($O + "/v1/account") -Authorization (New-HordeCloudflareRelayMachineAuthorization -Key $signer.key -KeyId $kid -Origin $O -Method "GET" -Target "/v1/account")).code -eq 403) "and may not read the account"
    $bRead = (Send-To -Url ($mb + "/items?since=0&max=10") -Cookie $B1).text | ConvertFrom-Json
    Check (@($bRead.items | Where-Object { $_.text -ceq "from the machine" }).Count -eq 0) "what the machine put is not in the other account"

    $target = "/v1/mailboxes/work/phone/items?since=0&max=10"
    $h1 = New-HordeCloudflareRelayMachineAuthorization -Key $signer.key -KeyId $kid -Origin $O -Method "GET" -Target $target
    $first = Send-To -Url ($O + $target) -Authorization $h1
    $replay = Send-To -Url ($O + $target) -Authorization $h1
    Check ($first.code -eq 200 -and $replay.code -eq 401) ("a signed request is taken once; the same request again is a replay, refused (" + $first.code + ", " + $replay.code + ")")
    $stale = Send-To -Url ($O + $target) -Authorization (New-HordeCloudflareRelayMachineAuthorization -Key $signer.key -KeyId $kid -Origin $O -Method "GET" -Target $target -Time ([System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - 61000))
    Check ($stale.code -eq 401 -and $stale.text.Contains("clock")) ("a request signed more than a minute ago is stale, and told so (" + $stale.text + ")")
    $future = Send-To -Url ($O + $target) -Authorization (New-HordeCloudflareRelayMachineAuthorization -Key $signer.key -KeyId $kid -Origin $O -Method "GET" -Target $target -Time ([System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + 61000))
    Check ($future.code -eq 401) "and one dated more than a minute ahead"
    $hs = New-HordeCloudflareRelayMachineAuthorization -Key $signer.key -KeyId $kid -Origin $O -Method "GET" -Target $target
    $twin = Send-To -Url ($O + $target) -Authorization (ConvertTo-HighS -Authorization $hs)
    $lowAfter = Send-To -Url ($O + $target) -Authorization $hs
    Check ($twin.code -eq 401 -and $lowAfter.code -eq 200) ("the high-S twin of a signature is refused, and does not spend the nonce of the true one (" + $twin.code + ", " + $lowAfter.code + ")")
    $putTarget = "/v1/mailboxes/work/phone/items"
    $signedFor = New-HordeCloudflareRelayMachineAuthorization -Key $signer.key -KeyId $kid -Origin $O -Method "POST" -Target $putTarget -Body ([System.Text.Encoding]::ASCII.GetBytes('{"key":"m-2","text":"signed"}'))
    Check ((Send-To -Url ($O + $putTarget) -Method "POST" -Body '{"key":"m-2","text":"swapped"}' -Authorization $signedFor).code -eq 401) "a signed put whose body was swapped is refused"
    $queryFor = New-HordeCloudflareRelayMachineAuthorization -Key $signer.key -KeyId $kid -Origin $O -Method "GET" -Target "/v1/mailboxes/work/phone/items?since=0&max=10"
    Check ((Send-To -Url ($O + "/v1/mailboxes/work/phone/items?since=1&max=10") -Authorization $queryFor).code -eq 401) "a signature for one cursor does not read from another: the query is signed too"
    $pathFor = New-HordeCloudflareRelayMachineAuthorization -Key $signer.key -KeyId $kid -Origin $O -Method "GET" -Target "/v1/mailboxes/work/other/items?since=0&max=10"
    Check ((Send-To -Url ($O + $target) -Authorization $pathFor).code -eq 401) "a signature for one mailbox does not open another"
    $originFor = New-HordeCloudflareRelayMachineAuthorization -Key $signer.key -KeyId $kid -Origin "https://relay.example.test" -Method "GET" -Target $target
    Check ((Send-To -Url ($O + $target) -Authorization $originFor).code -eq 401) "a signature made for another deployment's origin is refused"
    # Past a second boundary, so a request that wrongly counted would show as a later second.
    $seenBefore = & $lastSeen
    Start-Sleep -Milliseconds 1100
    $unreg = New-HordeCloudflareRelayMachineAuthorization -Key $other.key -KeyId $other.keyId -Origin $O -Method "GET" -Target $target
    Check ((Send-To -Url ($O + $target) -Authorization $unreg).code -eq 401) "a machine nobody registered is refused"
    $claimed = New-HordeCloudflareRelayMachineAuthorization -Key $other.key -KeyId $kid -Origin $O -Method "GET" -Target $target
    Check ((Send-To -Url ($O + $target) -Authorization $claimed).code -eq 401) "and so is one signing under a registered machine's key id with its own key"
    # No request is refused here for this alone: this key's refused signatures are counted (worker/limits.js),
    # and the checks above and below spend nearly all of a minute's. The two just made are the case.
    Check ((& $lastSeen) -eq $seenBefore) ("an unverified or failed-signature request does not record lastSeenAt: one signed under the machine's key id by another key, one by a key nobody registered - the machine's time stays " + $seenBefore)

    Write-Host ""
    Write-Host "--- revoke: the key signs nothing more ---" -ForegroundColor Cyan
    Check ((Send-To -Url ($O + "/v1/account/machines/" + $kid) -Method "DELETE" -Cookie $B1 -Origin $O).code -eq 404) "another account cannot remove the machine"
    Check ((Send-To -Url ($O + "/v1/account/machines/" + $kid) -Method "DELETE" -Cookie $A1 -Origin "https://evil.example.test").code -eq 401) "nor can another site's page, with the account's cookie"
    $still = Receive-HordeRelayItems -Connection $mc -Mailbox "work/phone" -Since 0
    Check ($still.state -ceq "known") "CONTROL: the machine still reads"
    Check ((& $lastSeen) -gt $seenBefore) "CONTROL: and that verified request is heard, a later second"
    $rm = Send-To -Url ($O + "/v1/account/machines/" + $kid) -Method "DELETE" -Cookie $A1 -Origin $O
    Check ($rm.code -eq 200) ("the account's phone removes the machine (" + $rm.text + ")")
    $gone = Receive-HordeRelayItems -Connection $mc -Mailbox "work/phone" -Since 0
    Check ($gone.state -ceq "unknown" -and $gone.reason.Contains("401")) ("and its next request is refused (" + $gone.reason + ")")
    Check ((Send-To -Url ($O + "/v1/account/machines") -Method "POST" -Body $reg -Cookie $A1 -Origin $O).code -eq 409) "its spent grant cannot bring it back"
    Check (@(((Send-To -Url ($O + "/v1/account") -Cookie $A1).text | ConvertFrom-Json).machines).Count -eq 0) "and the account no longer lists it"
    $offer2 = New-HordeRelayPairingOffer -HordeHome $m2.home -RpId "relay.example.test" -Origins @("https://relay.example.test")
    Check ((Send-To -Url ($O + "/v1/account/machines") -Method "POST" -Body (Get-Registration -OfferText $offer2.value.text) -Cookie $A1 -Origin $O).code -eq 200) "a second machine registers"
    $mc2 = (Connect-HordeRelay -Name "cloudflare" -Options @{ origin = $O; hordeHome = $m2.home }).value
    Check ((Send-To -Url ($O + "/v1/account/machines/" + $kid) -Method "DELETE" -Authorization (New-HordeCloudflareRelayMachineAuthorization -Key $other.key -KeyId $other.keyId -Origin $O -Method "DELETE" -Target ("/v1/account/machines/" + $kid))).code -eq 403) "a machine may not remove another"
    $self = Send-To -Url ($O + "/v1/account/machines/" + $other.keyId) -Method "DELETE" -Authorization (New-HordeCloudflareRelayMachineAuthorization -Key $other.key -KeyId $other.keyId -Origin $O -Method "DELETE" -Target ("/v1/account/machines/" + $other.keyId))
    Check ($self.code -eq 200 -and (Receive-HordeRelayItems -Connection $mc2 -Mailbox "work/phone" -Since 0).state -ceq "unknown") "but may remove its own key, and then signs nothing more"
    $signer.key.Dispose(); $other.key.Dispose()

    Write-Host ""
    Write-Host "--- the phone's own clients, signed in, over this Worker ---" -ForegroundColor Cyan
    $r = Invoke-HordeCloudflareRelayNode -Node $node -ArgList @((Join-Path $here "phone-account-over-worker.mjs"), $site, $O, $a.session) -WorkDir $work -TimeoutSeconds 120
    $lines = @(("" + $r.out) -split "`r?`n" | Where-Object { $_ -ne "" })
    foreach ($l in $lines) { if ($l -clike "[[]PASS[]] *") { Check $true $l.Substring(7) } elseif ($l -clike "[[]FAIL[]] *") { Check $false $l.Substring(7) } }
    Check ($r.code -eq 0 -and @($lines | Where-Object { $_ -ceq "[DONE] 0" }).Count -eq 1 -and @($lines | Where-Object { $_ -clike "[[]PASS[]] *" }).Count -ge 9) ("the phone's checks ran to their end (" + $r.code + "; " + ("" + $r.err).Trim() + ")")

    Write-Host ""
    Write-Host "--- sign-out ---" -ForegroundColor Cyan
    Check ((Send-To -Url ($O + "/auth/signout") -Method "POST" -Cookie $A1 -Origin "https://evil.example.test").code -eq 403) "another site's page cannot sign the phone out"
    Check ((Send-To -Url ($mb + "/items?since=0&max=1") -Cookie $A1).code -eq 200) "CONTROL: so the session still reads"
    $out = Send-To -Url ($O + "/auth/signout") -Method "POST" -Cookie $A1 -Origin $O
    Check ($out.code -eq 200 -and @($out.cookies | Where-Object { $_ -clike "__Host-horde-session=x; Max-Age=0;*" }).Count -eq 1) "signing out clears the cookie"
    Check ((Send-To -Url ($mb + "/items?since=0&max=1") -Cookie $A1).code -eq 401) "and ends the session at the relay: the old cookie, kept, reads nothing"

    Write-Host ""
    Write-Host "--- the app itself, in headless Chrome ---" -ForegroundColor Cyan
    $chrome = @(
        (Join-Path ${env:ProgramFiles} "Google\Chrome\Application\chrome.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe"),
        (Join-Path ${env:LOCALAPPDATA} "Google\Chrome\Application\chrome.exe")
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($null -eq $chrome) {
        Write-Host "  [SKIP] Chrome is not installed here, so the app's sign-in is not run in a browser" -ForegroundColor Yellow
        $partial = $true
    } else {
        $profileDir = Join-Path $work "chrome"
        [void][System.IO.Directory]::CreateDirectory($profileDir)
        # The first machine again, with a NEW offer - its old grant is spent, a new one is not - so the
        # app's Account screen has one machine to list and to remove.
        $again = Invoke-SignIn -Dev $dev -Provider $fake
        $offer3 = New-HordeRelayPairingOffer -HordeHome $m1.home -RpId "relay.example.test" -Origins @("https://relay.example.test") -Label "build-box"
        $back = Send-To -Url ($O + "/v1/account/machines") -Method "POST" -Body (Get-Registration -OfferText $offer3.value.text) -Cookie ("__Host-horde-session=" + $again.session) -Origin $O
        $mc3 = (Connect-HordeRelay -Name "cloudflare" -Options @{ origin = $O; hordeHome = $m1.home }).value
        Check ($back.code -eq 200 -and (Receive-HordeRelayItems -Connection $mc3 -Mailbox "work/phone" -Since 0).state -ceq "known") "a removed machine paired again with a new offer is registered again, and reads"
        $r = Invoke-HordeCloudflareRelayNode -Node $node -ArgList @((Join-Path $here "browser-signin.mjs"), $O, $fake.issuer, $chrome, $profileDir, "build-box") -WorkDir $work -TimeoutSeconds 180
        $lines = @(("" + $r.out) -split "`r?`n" | Where-Object { $_ -ne "" })
        foreach ($l in $lines) { if ($l -clike "[[]PASS[]] *") { Check $true $l.Substring(7) } elseif ($l -clike "[[]FAIL[]] *") { Check $false $l.Substring(7) } }
        Check ($r.code -eq 0 -and @($lines | Where-Object { $_ -ceq "[DONE] 0" }).Count -eq 1 -and @($lines | Where-Object { $_ -clike "[[]PASS[]] *" }).Count -ge 18) ("the browser's checks ran to their end (" + $r.code + "; " + ("" + $r.err).Trim() + ")")
        $afterUi = Receive-HordeRelayItems -Connection $mc3 -Mailbox "work/phone" -Since 0
        Check ($afterUi.state -ceq "unknown" -and $afterUi.reason.Contains("401")) ("the machine removed on the app's screen is refused at its next request (" + $afterUi.reason + ")")
    }

    Write-Host ""
    Write-Host "--- 3. the allowlist switched on ---" -ForegroundColor Cyan
    $list = '{"on":true,"emails":["founder@example.test"],"subs":["300000000000000000003"]}'
    $vars2 = @{ HORDE_RELAY_TEST_OIDC = $fake.issuer; GOOGLE_CLIENT_ID = $clientId; GOOGLE_CLIENT_SECRET = $clientSecret; HORDE_RELAY_SIGNIN_ALLOWLIST = $list; HORDE_RELAY_TEST_LIMITS = $roomy }
    $d2 = Start-HordeCloudflareRelayDev -Work (Join-Path $work "dev-allow") -Site $site -Script $tools.value.script -ExtraVars $vars2
    Check ($d2.state -ceq "known") ("a dev with the allowlist on answers (" + $d2.reason + ")")
    if ($d2.state -ceq "known") {
        [void]$devs.Add($d2.value)
        $in = Invoke-SignIn -Dev $d2.value -Provider $fake
        $bySub = Invoke-SignIn -Dev $d2.value -Provider $fake -Scenario @{ sub = "300000000000000000003"; email = "third@example.test" }
        $outside = Invoke-SignIn -Dev $d2.value -Provider $fake -Scenario @{ sub = "200000000000000000002"; email = "other@example.test" }
        Check ($in.session -ne "" -and $bySub.session -ne "") "a listed email signs in, and so does a listed account id"
        Check ($outside.session -ceq "" -and $outside.refused.Contains("allowlist")) ("an account on neither list does not (" + $outside.refused + ")")
    }
    Check ($b.session -ne "") "CONTROL: that same account signed in to the first dev, whose allowlist is off: signup is public by default"
} finally {
    foreach ($dv in @($devs)) { Stop-HordeCloudflareRelayDev -Dev $dv }
    foreach ($p in @($script:procs)) { try { if (-not $p.HasExited) { $p.StandardInput.BaseStream.Close(); if (-not $p.WaitForExit(10000)) { $p.Kill() } } } catch { }; $p.Dispose() }
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
    if ($work -like "*horde-cf-accounts-*" -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
Check (-not (Test-Path -LiteralPath $work)) "the suite's folder is gone"

if ($partial) { Complete-HordeSuite -Success "the Worker's sign-in and machines hold; the app was NOT RUN in a browser here" -PassCode 3 }
Complete-HordeSuite -Success "only a phone signed in with Google and a machine it registered get in, each to its own account, and every forged, stale, replayed or cross-site attempt is refused"
