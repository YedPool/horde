# DOES THE PUBLIC HOSTED RELAY HOLD EVERY ACCOUNT, DEVICE AND ADDRESS TO ITS LIMITS - REFUSING, NEVER
# DROPPING - KEEP NOTHING PAST ITS RETENTION, DELETE AN ACCOUNT WHOLE AND AT ONCE, AND MOVE A ROTATED
# MACHINE'S REGISTRATION ONCE?
#
# Relay PR 8c (the founder's plan of 2026-10-11): abuse limits, retention, account deletion, the
# machine's label, and identity rotation. Each limit is attacked at its edge, with small values a local
# dev takes through the test-only binding HORDE_RELAY_TEST_LIMITS (worker/limits.js); the defaults
# themselves are checked against the approved numbers in part 1.
#   1. THE PURE PARTS, under node (limits-units.mjs): the approved numbers in their one place, the test
#      override and where it is honoured, a bucket and a day count at their edges, a limit's refusal,
#      the rotation's record.
#   2. A DEV WITH TIGHT RATES AND CAPS: sign-ins started per address; accounts made per address; phones
#      per account (and signing one out from another); machines per account and pairings per hour;
#      puts and reads per device, at the burst and after it, with no seq lost to a refusal; a full
#      mailbox refusing, never evicting; refused signatures per key and address, and per address; the
#      nonce cache at its bound; one live watch per device in a mailbox, for a phone (watch-limits.mjs)
#      and for a machine's own adapter.
#   3. A DEV WITH A SHORT DAY AND A SHORT RETENTION: the account's requests a day, across its devices,
#      with its own screen still open over it; an unacked item kept until its retention and gone after.
#   4. A DEV WITH ROOM: everything but app files and sign-in is 401 to nobody; the machine's label;
#      identity rotation carried by the machine's adapter, and refused when replayed, presented twice,
#      tampered with, or for a removed machine; deleting an account - its sessions, machines and
#      mailboxes at once, puts racing it, and the same Google account signing up again to nothing.
#
# NODE IS NEEDED, and the pinned wrangler (relays/cloudflare/Wrangler.ps1 installs it outside the tree);
# without them parts 2 to 4 are skipped, said so, and the suite exits 3, never 0. A key store too
# (relay/Keys.ps1): the machines' identities are made with the software provider in Horde homes of the
# suite's own under %TEMP%, and every key is removed at the end and checked gone. Every dev and the fake
# provider are stopped in a finally block. Google and Cloudflare are never contacted.

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
Write-Host ("  runtime: PowerShell " + $PSVersionTable.PSVersion + " (" + $PSVersionTable.PSEdition + ")") -ForegroundColor DarkGray

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$work = Join-Path $env:TEMP ("horde-cf-limits-" + [guid]::NewGuid().ToString("N").Substring(0, 12))
[void][System.IO.Directory]::CreateDirectory($work)

Write-Host ""
Write-Host "--- 1. the pure parts, under node ---" -ForegroundColor Cyan
$node = Find-HordeCloudflareRelayNode
if ($node -eq "") {
    Write-Host "  [SKIP] no node here: nothing of the Worker can be run" -ForegroundColor Yellow
    Remove-Item -LiteralPath $work -Recurse -Force
    Complete-HordeSuite -Success "NOTHING RUN: no node" -PassCode 3
}
function Invoke-NodeChecks {
    # A node script's [PASS]/[FAIL] lines as checks, and one check that it ran to its end.
    param([string[]]$ArgList, [int]$AtLeast, [string]$What)
    $r = Invoke-HordeCloudflareRelayNode -Node $node -ArgList $ArgList -WorkDir $work -TimeoutSeconds 180
    $lines = @(("" + $r.out) -split "`r?`n" | Where-Object { $_ -ne "" })
    foreach ($l in $lines) { if ($l -clike "[[]PASS[]] *") { Check $true $l.Substring(7) } elseif ($l -clike "[[]FAIL[]] *") { Check $false $l.Substring(7) } }
    Check ($r.code -eq 0 -and @($lines | Where-Object { $_ -ceq "[DONE] 0" }).Count -eq 1 -and @($lines | Where-Object { $_ -clike "[[]PASS[]] *" }).Count -ge $AtLeast) ($What + " ran to their end (" + $r.code + "; " + ("" + $r.err).Trim() + ")")
}
Invoke-NodeChecks -ArgList @((Join-Path $here "limits-units.mjs"), $root) -AtLeast 40 -What "the unit checks"

Write-Host ""
Write-Host "--- an always-on fleet's day, from the constants ---" -ForegroundColor Cyan
# Three machines whose runners never stop: each quiet turn is one watch, and a watch on the hosted relay
# waits its run watch (relays/cloudflare/Relay.ps1, through the port: cli/RelayRun.ps1's own
# Get-HordeRelayRunWatchMs), so a day is 86,400,000 ms over it. That must leave the account's day
# (worker/limits.js's requestsPerDay, read from the Worker's own module) at least half free, for the
# phone, the puts and the acks. Computed, not run for 24 h.
. (Join-Path $root "cli\RelayRun.ps1")
$cf = Get-HordeRelay -Name "cloudflare"
$runWatch = Get-HordeRelayRunWatchMs -SettingMs 25000 -Relay $cf
$anySetting = @(0, 1000, 25000, 60000 | ForEach-Object { Get-HordeRelayRunWatchMs -SettingMs $_ -Relay $cf }) | Select-Object -Unique
$defaultsRun = Invoke-HordeCloudflareRelayNode -Node $node -ArgList @("--input-type=module", "-e", ('import { DEFAULTS } from "' + ([System.Uri](Join-Path $root "relays\cloudflare\worker\limits.js")).AbsoluteUri + '"; process.stdout.write(JSON.stringify(DEFAULTS));')) -WorkDir $work -TimeoutSeconds 60
$defaults = $null
try { $defaults = ("" + $defaultsRun.out) | ConvertFrom-Json } catch { $defaults = $null }
Check ($runWatch -eq 60000 -and @($anySetting).Count -eq 1) ("a runner on the hosted relay watches 60 s, whatever its own watchMs setting (" + $runWatch + ")")
Check ((Get-HordeRelayRunWatchMs -SettingMs 25000 -Relay (Get-HordeRelay -Name "local")) -eq 25000) "CONTROL: on a relay that declares no run watch, the setting still decides"
$perMachine = [Math]::Ceiling(86400000 / $runWatch)
$fleet = 3 * $perMachine
Check ($null -ne $defaults -and $defaults.requestsPerDay -eq 20000) ("the account's day is 20,000 requests (" + $(if ($null -ne $defaults) { $defaults.requestsPerDay } else { $defaultsRun.err }) + ")")
Check ($null -ne $defaults -and $fleet * 2 -le $defaults.requestsPerDay) ("three always-on machines make " + $fleet + " requests a day (" + $perMachine + " each), leaving more than half the account's day free")

Write-Host ""
Write-Host "--- 2. a dev with tight rates and caps ---" -ForegroundColor Cyan
$tools = Install-HordeCloudflareRelayTools
$store = Get-HordeRelayKeyStore
if ($tools.state -cne "known" -or $store.state -cne "known") {
    Write-Host ("  [SKIP] the Worker or the machines cannot be run here: " + $(if ($tools.state -cne "known") { $tools.reason } else { $store.reason })) -ForegroundColor Yellow
    Remove-Item -LiteralPath $work -Recurse -Force
    Complete-HordeSuite -Success "the pure parts hold; the Worker itself was NOT RUN here" -PassCode 3
}

$clientId = "1234567890-fakeclient.apps.googleusercontent.com"
$clientSecret = "GOCSPX-" + (New-HordeCloudflareRelayToken).Substring(0, 28)
$script:homes = New-Object System.Collections.ArrayList
$script:procs = New-Object System.Collections.ArrayList
$script:signers = New-Object System.Collections.ArrayList
$devs = New-Object System.Collections.ArrayList
. (Join-Path $here "Harness.ps1")

# A fresh client address for each sign-in that is not about addresses (worker/address.js), so the limits
# on addresses never stand in the way of a check about something else.
$script:addressCount = 0
function New-Address { $script:addressCount++; return ("10.9." + [Math]::Floor($script:addressCount / 250) + "." + (($script:addressCount % 250) + 1)) }
function New-Phone {
    # A sign-in of the Google account -Sub: Invoke-SignIn's answer, plus cookie (the Cookie header).
    param($Dev, [string]$Sub, [string]$Address = "")
    if ($Address -eq "") { $Address = New-Address }
    $r = Invoke-SignIn -Dev $Dev -Provider $fake -Scenario @{ sub = $Sub; email = ($Sub + "@example.test") } -Address $Address
    $r | Add-Member -NotePropertyName cookie -NotePropertyValue ("__Host-horde-session=" + $r.session)
    return $r
}
function New-Machine {
    # A machine with an identity of its own, registered by -Cookie's phone with an offer under -Label:
    # { home; kid; signer; reg (the registration's answer) }.
    param($Dev, [string]$Cookie, [string]$Label = "box", [string]$Horde = "work")
    $m = New-TestHome -Horde $Horde
    $o = New-HordeRelayPairingOffer -HordeHome $m.home -RpId "relay.example.test" -Origins @("https://relay.example.test") -Label $Label
    $reg = Send-To -Url ($Dev.origin + "/v1/account/machines") -Method "POST" -Body (Get-Registration -OfferText $o.value.text) -Cookie $Cookie -Origin $Dev.origin
    $s = (Open-HordeCloudflareRelaySigner -HordeHome $m.home).value
    [void]$script:signers.Add($s)
    return [pscustomobject]@{ home = $m.home; kid = $s.keyId; signer = $s; reg = $reg; offer = $o.value }
}
function New-Offer {
    # Another offer of -Machine's: a registration body.
    param($Machine, [string]$Label = "box")
    $o = New-HordeRelayPairingOffer -HordeHome $Machine.home -RpId "relay.example.test" -Origins @("https://relay.example.test") -Label $Label
    return (Get-Registration -OfferText $o.value.text)
}
function Get-SignedAuthorization {
    param($Dev, $Signer, [string]$Method, [string]$Target, [string]$Body = "")
    $bytes = New-Object byte[] 0
    if ($Body -ne "") { $bytes = [System.Text.Encoding]::ASCII.GetBytes($Body) }
    return (New-HordeCloudflareRelayMachineAuthorization -Key $Signer.key -KeyId $Signer.keyId -Origin $Dev.origin -Method $Method -Target $Target -Body $bytes)
}
function Send-Signed {
    # One request signed by -Signer's key, from -Address.
    param($Dev, $Signer, [string]$Method = "GET", [string]$Target, [string]$Body = "", [string]$Address = "")
    return (Send-To -Url ($Dev.origin + $Target) -Method $Method -Body $Body -Authorization (Get-SignedAuthorization -Dev $Dev -Signer $Signer -Method $Method -Target $Target -Body $Body) -Address $Address)
}
function Get-Code { param($Answer) try { $j = $Answer.text | ConvertFrom-Json; if ($null -ne $j.PSObject.Properties["code"]) { return ("" + $j.code) } } catch { }; return "" }
function Get-Json { param($Answer) try { return ($Answer.text | ConvertFrom-Json) } catch { return $null } }
function Start-Dev {
    param([string]$Name, [string]$Limits)
    $vars = @{ HORDE_RELAY_TEST_OIDC = $fake.issuer; GOOGLE_CLIENT_ID = $clientId; GOOGLE_CLIENT_SECRET = $clientSecret; HORDE_RELAY_TEST_LIMITS = $Limits }
    $d = Start-HordeCloudflareRelayDev -Work (Join-Path $work $Name) -Site $site -Script $tools.value.script -ExtraVars $vars
    Check ($d.state -ceq "known") ("a dev with " + $Limits + " answers (" + $d.reason + ")")
    if ($d.state -cne "known") { throw ("no dev " + $Name) }
    [void]$devs.Add($d.value)
    return $d.value
}

try {
    $fake = Start-FakeProvider
    $site = Join-Path $work "site"
    $built = New-HordeRelayDeploySite -Out $site
    Check ($built.state -ceq "known") ("the phone app is built as the deploy builds it (" + $built.reason + ")")
    $R = Start-Dev -Name "rates" -Limits '{"accountMaxMailboxes":3,"accountMaxChars":200,"putBurst":5,"putsPerMinute":12,"readBurst":6,"readsPerMinute":12,"machinesPerAccount":2,"phonesPerAccount":2,"pairingsPerHour":4,"signInStartsPerMinute":3,"newAccountsPerDay":1,"refusedSignaturesPerMinutePerKey":3,"refusedSignaturesPerMinutePerAddress":5,"noncesPerKey":4,"mailboxMaxItems":8,"mailboxMaxChars":100}'
    $O = $R.origin
    $bearer = "Bearer " + $R.token

    Write-Host ""
    Write-Host "--- sign-ins started, and accounts made, per address ---" -ForegroundColor Cyan
    $starts = @(1, 2, 3 | ForEach-Object { Send-To -Url ($O + "/auth/google") -Address "10.1.0.1" })
    Check (@($starts | Where-Object { $_.code -eq 303 -and (Get-Header $_ "location").StartsWith($fake.issuer + "/authorize") }).Count -eq 3) "three sign-ins start from one address, each sent to the provider"
    $fourth = Send-To -Url ($O + "/auth/google") -Address "10.1.0.1"
    Check ($fourth.code -eq 303 -and (Get-Header $fourth "location") -ceq ($O + "/app/index.html#signin-refused:busy") -and [int](Get-Header $fourth "retry-after") -ge 1 -and (Get-CookieValue $fourth "__Host-horde-signin") -ceq "") ("the fourth in the minute is sent back to the app, refused, told when to try again, with no sign-in begun (" + (Get-Header $fourth "location") + ", Retry-After " + (Get-Header $fourth "retry-after") + ")")
    Check ((Get-Header (Send-To -Url ($O + "/auth/google") -Address "10.1.0.9") "location").StartsWith($fake.issuer + "/authorize")) "CONTROL: a start from another address goes to the provider"
    $na1 = New-Phone -Dev $R -Sub "100000000000000000101" -Address "10.1.0.2"
    $na2 = New-Phone -Dev $R -Sub "100000000000000000102" -Address "10.1.0.2"
    Check ($na1.session -ne "" -and $na2.session -ceq "" -and (Get-Header $na2.callback "location") -ceq ($O + "/app/index.html#signin-refused:new-accounts")) ("an address makes its one account of the day, and the next new account from it is refused, said so (" + $na2.refused + ")")
    $na1again = New-Phone -Dev $R -Sub "100000000000000000101" -Address "10.1.0.2"
    Check ($na1again.session -ne "") "an account already made still signs in from that address"
    Check ((New-Phone -Dev $R -Sub "100000000000000000102" -Address "10.1.0.3").session -ne "") "and the refused account is made from another"

    Write-Host ""
    Write-Host "--- phones per account ---" -ForegroundColor Cyan
    $p1 = New-Phone -Dev $R -Sub "100000000000000000201"
    $p2 = New-Phone -Dev $R -Sub "100000000000000000201"
    $p3 = New-Phone -Dev $R -Sub "100000000000000000201"
    Check ($p1.session -ne "" -and $p2.session -ne "" -and $p3.session -ceq "" -and (Get-Header $p3.callback "location").EndsWith("#signin-refused:phones") -and $p3.refused.Contains("2 phones")) ("two phones sign in to an account of two, and a third is refused, said so (" + $p3.refused + ")")
    $view = Get-Json (Send-To -Url ($O + "/v1/account") -Cookie $p1.cookie)
    $mine = @($view.phones | Where-Object { $_.current -eq $true })
    $others = @($view.phones | Where-Object { $_.current -ne $true })
    Check (@($view.phones).Count -eq 2 -and $mine.Count -eq 1 -and $others.Count -eq 1 -and $others[0].id -cmatch '\A[0-9a-f]{64}\z') ("the account lists both phones, this one marked (" + (@($view.phones) | ConvertTo-Json -Compress) + ")")
    Check ((Send-To -Url ($O + "/v1/account/phones/" + ("0" * 64)) -Method "DELETE" -Cookie $p1.cookie -Origin $O).code -eq 404) "signing out a phone the account does not have is 404"
    Check ((Send-To -Url ($O + "/v1/account/phones/" + $others[0].id) -Method "DELETE" -Cookie $p1.cookie -Origin "https://evil.example.test").code -eq 401) "and another site's page cannot sign one out"
    $out = Send-To -Url ($O + "/v1/account/phones/" + $others[0].id) -Method "DELETE" -Cookie $p1.cookie -Origin $O
    Check ($out.code -eq 200 -and (Send-To -Url ($O + "/v1/account") -Cookie $p2.cookie).code -eq 401) ("one phone signs the other out, which reads nothing more at once (" + $out.text + ")")
    $p4 = New-Phone -Dev $R -Sub "100000000000000000201"
    Check ($p4.session -ne "") "and its place is free: a phone signs in again"
    Check ((New-Phone -Dev $R -Sub "100000000000000000201").session -ceq "") "CONTROL: and the account is full again"
    $so = Send-To -Url ($O + "/auth/signout") -Method "POST" -Cookie $p4.cookie -Origin $O
    Check ($so.code -eq 200 -and (New-Phone -Dev $R -Sub "100000000000000000201").session -ne "") "a phone that signs itself out frees its place too"

    Write-Host ""
    Write-Host "--- machines per account, pairings per hour ---" -ForegroundColor Cyan
    $mc = New-Phone -Dev $R -Sub "100000000000000000301"
    $ma = New-Machine -Dev $R -Cookie $mc.cookie -Label "first-box"
    $mb2 = New-Machine -Dev $R -Cookie $mc.cookie -Label "second-box"
    $m3 = New-Machine -Dev $R -Cookie $mc.cookie -Label "third-box"
    Check ($ma.reg.code -eq 200 -and $mb2.reg.code -eq 200) "an account of two machines registers two"
    Check ($m3.reg.code -eq 409 -and (Get-Code $m3.reg) -ceq "machines-cap" -and $m3.reg.text.Contains("remove one")) ("the third is refused with its code, saying what to do (" + $m3.reg.text + ")")
    Check ((Send-Signed -Dev $R -Signer $m3.signer -Target "/v1/mailboxes/work/phone/items?since=0&max=1").code -eq 401) "and the refused machine's key was not left registered: it reaches nothing"
    Check (@((Get-Json (Send-To -Url ($O + "/v1/account") -Cookie $mc.cookie)).machines).Count -eq 2) "the account still lists two"
    $rm = Send-To -Url ($O + "/v1/account/machines/" + $ma.kid) -Method "DELETE" -Cookie $mc.cookie -Origin $O
    $again = Send-To -Url ($O + "/v1/account/machines") -Method "POST" -Body (New-Offer -Machine $m3 -Label "third-box") -Cookie $mc.cookie -Origin $O
    Check ($rm.code -eq 200 -and $again.code -eq 200) ("one removed, the third registers with a new offer (" + $again.text + ")")
    $fifth = Send-To -Url ($O + "/v1/account/machines") -Method "POST" -Body (New-Offer -Machine $ma -Label "first-box") -Cookie $mc.cookie -Origin $O
    Check ($fifth.code -eq 429 -and (Get-Code $fifth) -ceq "rate-limited" -and [int](Get-Header $fifth "retry-after") -ge 1) ("the fifth registration attempt in the hour is refused, rate-limited, with Retry-After - a pairing an account makes four of an hour here (" + $fifth.code + " " + $fifth.text + ")")
    $other = New-Phone -Dev $R -Sub "100000000000000000302"
    Check ((New-Machine -Dev $R -Cookie $other.cookie).reg.code -eq 200) "CONTROL: another account's pairing is its own"

    Write-Host ""
    Write-Host "--- puts and reads per device ---" -ForegroundColor Cyan
    $rt = New-Phone -Dev $R -Sub "100000000000000000401"
    $rt2 = New-Phone -Dev $R -Sub "100000000000000000401"
    $mbx = $O + "/v1/mailboxes/work/rates"
    $reads = @(1..6 | ForEach-Object { (Send-To -Url ($mbx + "/items?since=0&max=10") -Cookie $rt.cookie).code })
    $read7 = Send-To -Url ($mbx + "/items?since=0&max=10") -Cookie $rt.cookie
    Check (($reads -join ",") -ceq "200,200,200,200,200,200" -and $read7.code -eq 429 -and (Get-Code $read7) -ceq "rate-limited") ("six reads at once, the device's read burst, and the seventh is refused (" + ($reads -join ",") + "," + $read7.code + ")")
    $puts = @(1..5 | ForEach-Object { (Send-To -Url ($mbx + "/items") -Method "POST" -Body ('{"key":"k-' + $_ + '","text":"t' + $_ + '"}') -Cookie $rt.cookie -Origin $O).code })
    Check (($puts -join ",") -ceq "200,200,200,200,200") ("puts are a bucket of their own: five at once, the put burst, after the reads ran out (" + ($puts -join ",") + ")")
    $put6 = Send-To -Url ($mbx + "/items") -Method "POST" -Body '{"key":"k-6","text":"t6"}' -Cookie $rt.cookie -Origin $O
    $wait = [int](Get-Header $put6 "retry-after")
    Check ($put6.code -eq 429 -and (Get-Code $put6) -ceq "rate-limited" -and $wait -ge 1 -and $wait -le 5) ("the sixth put is refused, rate-limited, told to wait at most the five seconds a token takes at 12 a minute (" + $put6.code + ", Retry-After " + $wait + ")")
    Check ((Send-To -Url ($mbx + "/items") -Method "POST" -Body '{"key":"k-other","text":"x"}' -Cookie $rt2.cookie -Origin $O).code -eq 200) "the same account's other phone is a device of its own, and puts"
    Start-Sleep -Milliseconds ($wait * 1000 + 300)
    $put6b = Send-To -Url ($mbx + "/items") -Method "POST" -Body '{"key":"k-6","text":"t6"}' -Cookie $rt.cookie -Origin $O
    Check ($put6b.code -eq 200 -and (Get-Json $put6b).seq -eq 7) ("after the wait the refused put is taken, numbered straight after the others: a refusal takes no seq (" + $put6b.text + ")")
    $all = Get-Json (Send-To -Url ($mbx + "/items?since=0&max=10") -Cookie $rt.cookie)
    Check (((@($all.items) | ForEach-Object { $_.key }) -join ",") -ceq "k-1,k-2,k-3,k-4,k-5,k-other,k-6") "and the mailbox holds every put that was taken, once, in order"

    Write-Host ""
    Write-Host "--- an account's mailboxes and characters in all ---" -ForegroundColor Cyan
    # Two phones of one account, so the puts are two devices' bursts (five each here).
    $am1 = New-Phone -Dev $R -Sub "100000000000000000451"
    $am2 = New-Phone -Dev $R -Sub "100000000000000000451"
    $amPut = { param($Phone, [string]$Box, [string]$Key, [string]$Text) Send-To -Url ($O + "/v1/mailboxes/work/" + $Box + "/items") -Method "POST" -Body ('{"key":"' + $Key + '","text":"' + $Text + '"}') -Cookie $Phone.cookie -Origin $O }
    $three = @(@("m1", "m2", "m3") | ForEach-Object { (& $amPut $am1 $_ "k" "x").code })
    $fourth = & $amPut $am1 "m4" "k" "x"
    Check (($three -join ",") -ceq "200,200,200" -and $fourth.code -eq 409 -and (Get-Code $fourth) -ceq "mailboxes-cap") ("an account of three mailboxes puts into three, and a fourth is refused, mailboxes-cap (" + $fourth.text + ")")
    Check ((& $amPut $am2 "m2" "k2" "y").code -eq 200) "a mailbox it already has still takes more"
    $null = Send-To -Url ($O + "/v1/mailboxes/work/m1/ack") -Method "POST" -Body '{"through":1}' -Cookie $am1.cookie -Origin $O
    Check ((& $amPut $am2 "m4" "k" "x").code -eq 200) "once one is read and acked to empty, the fourth is taken"
    $ac1 = New-Phone -Dev $R -Sub "100000000000000000452"
    $ac2 = New-Phone -Dev $R -Sub "100000000000000000452"
    $c60 = & $amPut $ac1 "a" "k1" ("x" * 60)
    $c40 = & $amPut $ac1 "a" "k2" ("x" * 40)
    $c100 = & $amPut $ac1 "b" "k1" ("x" * 100)
    $over = & $amPut $ac1 "c" "k1" "x"
    Check ($c60.code -eq 200 -and $c40.code -eq 200 -and $c100.code -eq 200 -and $over.code -eq 507 -and (Get-Code $over) -ceq "account-full") ("an account of 200 characters takes exactly 200 across two mailboxes, and one more is refused, account-full (" + $over.text + ")")
    $heldA = Get-Json (Send-To -Url ($O + "/v1/mailboxes/work/a/items?since=0&max=10") -Cookie $ac2.cookie)
    Check (@($heldA.items).Count -eq 2) "nothing was evicted to make room"
    $null = Send-To -Url ($O + "/v1/mailboxes/work/a/ack") -Method "POST" -Body '{"through":1}' -Cookie $ac2.cookie -Origin $O
    Check ((& $amPut $ac2 "c" "k1" ("x" * 60)).code -eq 200 -and (& $amPut $ac2 "c" "k2" "x").code -eq 507) "an ack gives its characters back: 60 freed are 60 taken, and not one more"

    Write-Host ""
    Write-Host "--- a full mailbox refuses, and never evicts ---" -ForegroundColor Cyan
    $cap = $O + "/v1/mailboxes/cap/items"
    $taken = @(1..8 | ForEach-Object { (Send-To -Url ($cap + "/items") -Method "POST" -Body ('{"key":"c-' + $_ + '","text":"c' + $_ + '"}') -Authorization $bearer).code })
    $full = Send-To -Url ($cap + "/items") -Method "POST" -Body '{"key":"c-9","text":"c9"}' -Authorization $bearer
    Check (($taken -join ",") -ceq "200,200,200,200,200,200,200,200" -and $full.code -eq 507 -and (Get-Code $full) -ceq "mailbox-full" -and $full.text.Contains("acked")) ("a mailbox of eight takes eight, and refuses the ninth, mailbox-full, saying why (" + $full.text + ")")
    $dup = Send-To -Url ($cap + "/items") -Method "POST" -Body '{"key":"c-1","text":"c1"}' -Authorization $bearer
    Check ($dup.code -eq 200 -and (Get-Json $dup).duplicate -eq $true) "a put of a key it holds is still the idempotent yes, full or not"
    $held = Get-Json (Send-To -Url ($cap + "/items?since=0&max=10") -Authorization $bearer)
    Check (((@($held.items) | ForEach-Object { $_.key }) -join ",") -ceq "c-1,c-2,c-3,c-4,c-5,c-6,c-7,c-8") "nothing was evicted to make room: the eight unacked items are all there"
    $null = Send-To -Url ($cap + "/ack") -Method "POST" -Body '{"through":2}' -Authorization $bearer
    $after = Send-To -Url ($cap + "/items") -Method "POST" -Body '{"key":"c-9","text":"c9"}' -Authorization $bearer
    Check ($after.code -eq 200 -and (Get-Json $after).seq -eq 9) "an ack makes room, and the refused item is taken"
    $chars = $O + "/v1/mailboxes/cap/chars"
    $forty = "x" * 40
    $c1 = Send-To -Url ($chars + "/items") -Method "POST" -Body ('{"key":"a","text":"' + $forty + '"}') -Authorization $bearer
    $c2 = Send-To -Url ($chars + "/items") -Method "POST" -Body ('{"key":"b","text":"' + $forty + '"}') -Authorization $bearer
    $c3 = Send-To -Url ($chars + "/items") -Method "POST" -Body ('{"key":"c","text":"' + $forty + '"}') -Authorization $bearer
    $c4 = Send-To -Url ($chars + "/items") -Method "POST" -Body ('{"key":"d","text":"' + ("y" * 20) + '"}') -Authorization $bearer
    Check ($c1.code -eq 200 -and $c2.code -eq 200 -and $c3.code -eq 507 -and (Get-Code $c3) -ceq "mailbox-full" -and $c4.code -eq 200) ("a mailbox of 100 characters takes 80, refuses 40 more, and takes 20 - exactly its most (" + (@($c1.code, $c2.code, $c3.code, $c4.code) -join ",") + ")")

    Write-Host ""
    Write-Host "--- refused signatures, per key and address, and per address ---" -ForegroundColor Cyan
    $rs = New-Phone -Dev $R -Sub "100000000000000000501"
    $k = New-Machine -Dev $R -Cookie $rs.cookie -Label "victim-box"
    # A machine that rotates now, and presents its rotation once its address is refused (below).
    $rb = New-Machine -Dev $R -Cookie $rs.cookie -Label "blocked-rotating-box"
    $null = Update-HordeRelayMachineIdentity -HordeHome $rb.home -Reason "scheduled" -Provider "software"
    $rbs = (Open-HordeCloudflareRelaySigner -HordeHome $rb.home).value
    [void]$script:signers.Add($rbs)
    $rbBody = '{"record":' + (ConvertTo-HordeCloudflareRelayJsonString (Get-HordeRelayRetirementText -HordeHome $rb.home -Generation 1).value) + '}'
    $forger = New-TestHome
    $fs = (Open-HordeCloudflareRelaySigner -HordeHome $forger.home).value
    [void]$script:signers.Add($fs)
    $tgt = "/v1/mailboxes/work/phone/items?since=0&max=1"
    $forged = @(1..3 | ForEach-Object { (Send-To -Url ($O + $tgt) -Authorization (New-HordeCloudflareRelayMachineAuthorization -Key $fs.key -KeyId $k.kid -Origin $O -Method "GET" -Target $tgt) -Address "10.2.0.1").code })
    $fourthForged = Send-To -Url ($O + $tgt) -Authorization (New-HordeCloudflareRelayMachineAuthorization -Key $fs.key -KeyId $k.kid -Origin $O -Method "GET" -Target $tgt) -Address "10.2.0.1"
    Check (($forged -join ",") -ceq "401,401,401" -and $fourthForged.code -eq 429 -and (Get-Code $fourthForged) -ceq "rate-limited") ("three forged signatures under a machine's key id from one address are refused, and the fourth is refused at once, rate-limited (" + ($forged -join ",") + "," + $fourthForged.code + ")")
    Check ((Send-Signed -Dev $R -Signer $k.signer -Target $tgt -Address "10.2.0.1").code -eq 429) "that address is refused for that key until it refills, true signature or not"
    Check ((Send-Signed -Dev $R -Signer $k.signer -Target $tgt -Address "10.2.0.2").code -eq 200) "but the machine itself, from its own address, is not locked out by a forger who knows its key id"
    $strangers = @(1..5 | ForEach-Object { $sk = ConvertTo-HordeRelayHex -Bytes (Get-HordeRelayRandomBytes -Count 16); (Send-To -Url ($O + $tgt) -Authorization (New-HordeCloudflareRelayMachineAuthorization -Key $fs.key -KeyId $sk -Origin $O -Method "GET" -Target $tgt) -Address "10.2.0.3").code })
    $sixth = Send-To -Url ($O + $tgt) -Authorization (New-HordeCloudflareRelayMachineAuthorization -Key $fs.key -KeyId (ConvertTo-HordeRelayHex -Bytes (Get-HordeRelayRandomBytes -Count 16)) -Origin $O -Method "GET" -Target $tgt) -Address "10.2.0.3"
    Check (($strangers -join ",") -ceq "401,401,401,401,401" -and $sixth.code -eq 429) ("five signatures under five unregistered key ids from one address are refused, and the sixth is refused at once (" + ($strangers -join ",") + "," + $sixth.code + ")")
    Check ((Send-Signed -Dev $R -Signer $k.signer -Target $tgt -Address "10.2.0.3").code -eq 429) "and that address's machine requests are all refused for now, true ones too"
    Check ((Send-To -Url ($O + "/v1/machines/rotation") -Method "POST" -Body '{"record":"x"}' -Authorization (Get-SignedAuthorization -Dev $R -Signer $fs -Method "POST" -Target "/v1/machines/rotation" -Body '{"record":"x"}') -Address "10.2.0.3").code -eq 429) "the rotation route too"
    Check ((Send-To -Url ($O + "/v1/machines/rotation") -Method "POST" -Body $rbBody -Authorization (Get-SignedAuthorization -Dev $R -Signer $rbs -Method "POST" -Target "/v1/machines/rotation" -Body $rbBody) -Address "10.2.0.3").code -eq 429) "even a true rotation, from that address, is refused for now"
    Check ((Send-To -Url ($O + "/v1/machines/rotation") -Method "POST" -Body $rbBody -Authorization (Get-SignedAuthorization -Dev $R -Signer $rbs -Method "POST" -Target "/v1/machines/rotation" -Body $rbBody) -Address "10.2.0.4").code -eq 200) "CONTROL: and moves the registration from another"

    Write-Host ""
    Write-Host "--- the nonce cache at its bound ---" -ForegroundColor Cyan
    $nb = New-Phone -Dev $R -Sub "100000000000000000601"
    $nm = New-Machine -Dev $R -Cookie $nb.cookie -Label "busy-box"
    $firstAuth = Get-SignedAuthorization -Dev $R -Signer $nm.signer -Method "GET" -Target $tgt
    $codes = @((Send-To -Url ($O + $tgt) -Authorization $firstAuth).code) + @(2..4 | ForEach-Object { (Send-Signed -Dev $R -Signer $nm.signer -Target $tgt).code })
    $fifthReq = Send-Signed -Dev $R -Signer $nm.signer -Target $tgt
    Check (($codes -join ",") -ceq "200,200,200,200" -and $fifthReq.code -eq 429 -and (Get-Code $fifthReq) -ceq "rate-limited" -and $fifthReq.text.Contains("most the relay keeps")) ("a key keeps four nonces here: four requests are taken and the fifth is refused, its nonce not kept (" + ($codes -join ",") + "," + $fifthReq.code + ")")
    Check ((Send-To -Url ($O + $tgt) -Authorization $firstAuth).code -eq 401) "and no nonce was forgotten to make room: the first request, replayed, is still refused as a replay"

    Write-Host ""
    Write-Host "--- one live watch per device in a mailbox ---" -ForegroundColor Cyan
    $wa = New-Phone -Dev $R -Sub "100000000000000000701"
    $wb = New-Phone -Dev $R -Sub "100000000000000000701"
    Invoke-NodeChecks -ArgList @((Join-Path $here "watch-limits.mjs"), $site, $O, $wa.session, $wb.session) -AtLeast 6 -What "the phones' watch checks"
    $wm = New-Machine -Dev $R -Cookie $wa.cookie -Label "watch-box"
    $mbox = "work/" + $wm.kid
    $ps = [PowerShell]::Create()
    [void]$ps.AddScript({
            param($Port, $Origin, $HordeHome, $Mailbox)
            . $Port
            foreach ($f in @(Get-HordeRelayFiles)) { . $f }
            $c = (Connect-HordeRelay -Name "cloudflare" -Options @{ origin = $Origin; hordeHome = $HordeHome }).value
            $w = Wait-HordeRelayItems -Connection $c -Mailbox $Mailbox -Since 0 -TimeoutMs 20000
            return @($w.state, $w.reason)
        }).AddArgument((Join-Path $root "relays\Port.ps1")).AddArgument($O).AddArgument($wm.home).AddArgument($mbox)
    try {
        $h = $ps.BeginInvoke()
        Start-Sleep -Milliseconds 2500
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        $mc2 = (Connect-HordeRelay -Name "cloudflare" -Options @{ origin = $O; hordeHome = $wm.home }).value
        $second = Wait-HordeRelayItems -Connection $mc2 -Mailbox $mbox -Since 0 -TimeoutMs 2000
        $first = @($ps.EndInvoke($h) | ForEach-Object { "$_" })
    } finally { $ps.Dispose() }
    Check ($first.Count -eq 2 -and $first[0] -ceq "unknown" -and $first[1].Contains("replaced") -and $second.state -ceq "known" -and $clock.ElapsedMilliseconds -lt 8000) ("the machine's own adapter reads its watch replaced by its newer one as a failed watch, so its runner backs off (" + ($first -join ": ") + ")")

    Write-Host ""
    Write-Host "--- 3. a dev with a short day and a short retention ---" -ForegroundColor Cyan
    $D = Start-Dev -Name "day" -Limits '{"requestsPerDay":6,"retentionMs":2500,"accountMaxChars":50}'
    $O = $D.origin
    $bearer = "Bearer " + $D.token
    $dp = New-Phone -Dev $D -Sub "100000000000000000801"
    $dm = New-Machine -Dev $D -Cookie $dp.cookie -Label "day-box"
    Check ($dm.reg.code -eq 200) "registering a machine is not a mailbox request: it is not counted against the day"
    $dayCodes = @(1..6 | ForEach-Object { (Send-To -Url ($O + "/v1/mailboxes/work/phone/items?since=0&max=1") -Cookie $dp.cookie).code })
    $seventh = Send-To -Url ($O + "/v1/mailboxes/work/phone/items?since=0&max=1") -Cookie $dp.cookie
    $toMidnight = [int](Get-Header $seventh "retry-after")
    Check (($dayCodes -join ",") -ceq "200,200,200,200,200,200" -and $seventh.code -eq 429 -and (Get-Code $seventh) -ceq "daily-limit" -and $toMidnight -ge 1 -and $toMidnight -le 86400) ("an account of six requests a day makes six, and the seventh is refused, daily-limit, until UTC midnight (" + $seventh.code + ", Retry-After " + $toMidnight + " s)")
    Check ((Send-Signed -Dev $D -Signer $dm.signer -Target ("/v1/mailboxes/work/" + $dm.kid + "/items?since=0&max=1")).code -eq 429) "the day is the account's, not the device's: its machine is refused too"
    Check ((Send-To -Url ($O + "/v1/account") -Cookie $dp.cookie).code -eq 200) "but its own Account screen still opens over its day, so it can manage itself"
    $de = New-Phone -Dev $D -Sub "100000000000000000802"
    Check ((Send-To -Url ($O + "/v1/mailboxes/work/phone/items?since=0&max=1") -Cookie $de.cookie).code -eq 200) "CONTROL: another account's day is its own"

    $ret = $O + "/v1/mailboxes/ret/kept"
    $put = Send-To -Url ($ret + "/items") -Method "POST" -Body '{"key":"r-1","text":"kept for a while"}' -Authorization $bearer
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    Start-Sleep -Milliseconds 1000
    $put2 = Send-To -Url ($ret + "/items") -Method "POST" -Body '{"key":"r-2","text":"put a second later"}' -Authorization $bearer
    $put2At = $clock.ElapsedMilliseconds
    Start-Sleep -Milliseconds 200
    $before = Get-Json (Send-To -Url ($ret + "/items?since=0&max=10") -Authorization $bearer)
    $beforeAt = $clock.ElapsedMilliseconds
    Check ($put.code -eq 200 -and $put2.code -eq 200 -and @($before.items).Count -eq 2 -and $beforeAt -lt 2400) ("unacked items are kept before their retention ends (read " + $beforeAt + " ms after the first put, of 2500)")
    $first = $null
    while ($clock.ElapsedMilliseconds -lt 15000) {
        Start-Sleep -Milliseconds 100
        $first = Get-Json (Send-To -Url ($ret + "/items?since=0&max=10") -Authorization $bearer)
        if (-not (@($first.items) | Where-Object { $_.key -ceq "r-1" })) { break }
    }
    $firstAt = $clock.ElapsedMilliseconds
    Check (@($first.items).Count -eq 1 -and $first.items[0].key -ceq "r-2" -and $firstAt -ge 2400 -and $firstAt -lt ($put2At + 2400)) ("the first is deleted once its retention ends, by the mailbox's alarm, never before - and the second, not yet at its end, is kept (" + $firstAt + " ms; the second was put at " + $put2At + ")")
    $gone = $null
    while ($clock.ElapsedMilliseconds -lt 20000) {
        Start-Sleep -Milliseconds 100
        $gone = Get-Json (Send-To -Url ($ret + "/items?since=0&max=10") -Authorization $bearer)
        if (@($gone.items).Count -eq 0) { break }
    }
    $goneAt = $clock.ElapsedMilliseconds
    Check (@($gone.items).Count -eq 0 -and $goneAt -ge ($put2At + 2400) -and $goneAt -lt 20000) ("then the second at its own end: the alarm moved on to it (gone " + $goneAt + " ms after the first put)")
    $next = Send-To -Url ($ret + "/items") -Method "POST" -Body '{"key":"r-3","text":"after"}' -Authorization $bearer
    Check ($next.code -eq 200 -and (Get-Json $next).seq -eq 3) "and their seqs are never given again: the head stays where it was"
    $ex = New-Phone -Dev $D -Sub "100000000000000000803"
    $exFull = Send-To -Url ($O + "/v1/mailboxes/work/exp/items") -Method "POST" -Body ('{"key":"e-1","text":"' + ("x" * 50) + '"}') -Cookie $ex.cookie -Origin $O
    $exOver = Send-To -Url ($O + "/v1/mailboxes/work/exp/items") -Method "POST" -Body '{"key":"e-2","text":"x"}' -Cookie $ex.cookie -Origin $O
    Start-Sleep -Milliseconds 4000
    $exAfter = Send-To -Url ($O + "/v1/mailboxes/work/exp/items") -Method "POST" -Body '{"key":"e-2","text":"x"}' -Cookie $ex.cookie -Origin $O
    Check ($exFull.code -eq 200 -and $exOver.code -eq 507 -and $exAfter.code -eq 200) ("an account full of unacked mail is given its room back when that mail expires (" + (@($exFull.code, $exOver.code, $exAfter.code) -join ", ") + ")")
    $acked = $O + "/v1/mailboxes/ret/acked"
    $null = Send-To -Url ($acked + "/items") -Method "POST" -Body '{"key":"a-1","text":"read"}' -Authorization $bearer
    $null = Send-To -Url ($acked + "/ack") -Method "POST" -Body '{"through":1}' -Authorization $bearer
    Check (@((Get-Json (Send-To -Url ($acked + "/items?since=0&max=10") -Authorization $bearer)).items).Count -eq 0) "an acked item is deleted by its ack, at once"

    Write-Host ""
    Write-Host "--- 4. a dev with room ---" -ForegroundColor Cyan
    $X = Start-Dev -Name "room" -Limits '{"signInStartsPerMinute":1000,"newAccountsPerDay":1000}'
    $O = $X.origin

    Write-Host ""
    Write-Host "--- nobody gets past the door ---" -ForegroundColor Cyan
    $doors = [ordered]@{
        "GET /v1" = @("GET", "/v1"); "GET /v1/" = @("GET", "/v1/"); "GET /v1/account" = @("GET", "/v1/account"); "DELETE /v1/account" = @("DELETE", "/v1/account")
        "POST /v1/account/machines" = @("POST", "/v1/account/machines"); "DELETE a machine" = @("DELETE", ("/v1/account/machines/" + ("a" * 32)))
        "DELETE a phone" = @("DELETE", ("/v1/account/phones/" + ("a" * 64))); "a read" = @("GET", "/v1/mailboxes/work/phone/items?since=0&max=1")
        "a put" = @("POST", "/v1/mailboxes/work/phone/items"); "an ack" = @("POST", "/v1/mailboxes/work/phone/ack"); "a watch, not upgraded" = @("GET", "/v1/mailboxes/work/phone/watch?since=0&max=1&timeoutMs=1")
        "a rotation" = @("POST", "/v1/machines/rotation"); "a rotation read" = @("GET", "/v1/machines/rotation"); "a path that is not one" = @("GET", "/v1/nothing")
    }
    $leaks = @()
    foreach ($n in @($doors.Keys)) { $a = Send-To -Url ($O + $doors[$n][1]) -Method $doors[$n][0] -Body $(if ($doors[$n][0] -ceq "GET") { "" } else { "{}" }) -Origin $O; if ($a.code -ne 401) { $leaks += ($n + " " + $a.code) } }
    $ws = Get-UpgradeStatus -Origin $O -Path "/v1/mailboxes/work/phone/watch?since=0&max=1&timeoutMs=1000" -Cookie "x=1" -PageOrigin $O
    Check ($leaks.Count -eq 0 -and $ws -clike "HTTP/1.1 401*") ("every API path, the new ones too, is 401 to nobody, a watch's upgrade included (" + ($leaks -join "; ") + ")")
    Check ((Send-To -Url ($O + "/app/index.html")).code -eq 200 -and (Send-To -Url ($O + "/auth/session")).code -eq 200 -and (Send-To -Url ($O + "/auth/google")).code -eq 303) "only the app's files and sign-in answer anybody"

    Write-Host ""
    Write-Host "--- the machine's label ---" -ForegroundColor Cyan
    $lp = New-Phone -Dev $X -Sub "100000000000000000901"
    $lm = New-Machine -Dev $X -Cookie $lp.cookie -Label "build-box"
    $listed = @((Get-Json (Send-To -Url ($O + "/v1/account") -Cookie $lp.cookie)).machines)
    Check ($lm.reg.code -eq 200 -and $listed.Count -eq 1 -and $listed[0].label -ceq "build-box" -and $listed[0].keyId -ceq $lm.kid) "the account lists the machine by the name its offer gave"
    $relabel = New-TestHome
    $ro = New-HordeRelayPairingOffer -HordeHome $relabel.home -RpId "relay.example.test" -Origins @("https://relay.example.test") -Label "honest-box"
    $renamed = Send-To -Url ($O + "/v1/account/machines") -Method "POST" -Body (Get-Registration -OfferText $ro.value.text -Over @{ label = "evil-box" }) -Cookie $lp.cookie -Origin $O
    Check ($renamed.code -eq 403) ("a phone that renames the machine on its way to the relay is refused: the grant signs the label (" + $renamed.code + ")")

    Write-Host ""
    Write-Host "--- identity rotation ---" -ForegroundColor Cyan
    $rotP = New-Phone -Dev $X -Sub "100000000000000001001"
    $r1 = New-Machine -Dev $X -Cookie $rotP.cookie -Label "rotating-box"
    $oldKid = $r1.kid
    $rot = Update-HordeRelayMachineIdentity -HordeHome $r1.home -Reason "scheduled" -Provider "software"
    Check ($rot.state -ceq "known" -and @($rot.value.vouched).Count -eq 1) ("the machine rotates its identity, its old key vouching for the new (" + $rot.reason + ")")
    $rc = (Connect-HordeRelay -Name "cloudflare" -Options @{ origin = $O; hordeHome = $r1.home }).value
    $afterRot = Receive-HordeRelayItems -Connection $rc -Mailbox "work/phone" -Since 0
    $newKid = $rot.value.identity.sign.keyId
    $rlist = @((Get-Json (Send-To -Url ($O + "/v1/account") -Cookie $rotP.cookie)).machines)
    Check ($afterRot.state -ceq "known" -and $rlist.Count -eq 1 -and $rlist[0].keyId -ceq $newKid -and $rlist[0].label -ceq "rotating-box" -and $newKid -cne $oldKid) ("its adapter carries the vouch at its first refusal, the relay moves the registration, and it reads - no pairing again (" + $afterRot.reason + ")")
    Check ($rc.state.rotationTried -eq $true) "CONTROL: it was the rotation that let it in"

    $r2 = New-Machine -Dev $X -Cookie $rotP.cookie -Label "second-rotating-box"
    $rot2 = Update-HordeRelayMachineIdentity -HordeHome $r2.home -Reason "scheduled" -Provider "software"
    $record = (Get-HordeRelayRetirementText -HordeHome $r2.home -Generation 1).value
    $s2 = (Open-HordeCloudflareRelaySigner -HordeHome $r2.home).value
    [void]$script:signers.Add($s2)
    $body = '{"record":' + (ConvertTo-HordeCloudflareRelayJsonString $record) + '}'
    $auth = Get-SignedAuthorization -Dev $X -Signer $s2 -Method "POST" -Target "/v1/machines/rotation" -Body $body
    $moved = Send-To -Url ($O + "/v1/machines/rotation") -Method "POST" -Body $body -Authorization $auth
    $mj = Get-Json $moved
    Check ($moved.code -eq 200 -and $mj.keyId -ceq $s2.keyId -and $mj.from -ceq $r2.kid) ("the rotation, signed by the new key with the old key's vouch, moves the registration (" + $moved.text + ")")
    Check ((Send-To -Url ($O + "/v1/machines/rotation") -Method "POST" -Body $body -Authorization $auth).code -eq 401) "the same request again is a replay, refused"
    Check ((Send-To -Url ($O + "/v1/machines/rotation") -Method "POST" -Body $body -Authorization (Get-SignedAuthorization -Dev $X -Signer $s2 -Method "POST" -Target "/v1/machines/rotation" -Body $body)).code -eq 401) "and the record presented again, freshly signed, moves nothing: single use, the old key is nobody's now"
    Check ((Send-Signed -Dev $X -Signer $s2 -Target "/v1/mailboxes/work/phone/items?since=0&max=1").code -eq 200) "CONTROL: the new key reads"

    $r3 = New-Machine -Dev $X -Cookie $rotP.cookie -Label "third-rotating-box"
    $null = Update-HordeRelayMachineIdentity -HordeHome $r3.home -Reason "scheduled" -Provider "software"
    $rec3 = (Get-HordeRelayRetirementText -HordeHome $r3.home -Generation 1).value
    $s3 = (Open-HordeCloudflareRelaySigner -HordeHome $r3.home).value
    [void]$script:signers.Add($s3)
    $tampered = $rec3.Replace('"reason":"scheduled"', '"reason":"scheduleD"')
    $tb = '{"record":' + (ConvertTo-HordeCloudflareRelayJsonString $tampered) + '}'
    Check ((Send-To -Url ($O + "/v1/machines/rotation") -Method "POST" -Body $tb -Authorization (Get-SignedAuthorization -Dev $X -Signer $s3 -Method "POST" -Target "/v1/machines/rotation" -Body $tb)).code -eq 401) "a record changed after the old key vouched for it moves nothing"
    $b3 = '{"record":' + (ConvertTo-HordeCloudflareRelayJsonString $rec3) + '}'
    Check ((Send-To -Url ($O + "/v1/machines/rotation") -Method "POST" -Body $b3 -Authorization (Get-SignedAuthorization -Dev $X -Signer $s2 -Method "POST" -Target "/v1/machines/rotation" -Body $b3)).code -eq 401) "nor does a true record presented by a key that is not its successor"
    $noVouch = [regex]::Replace($rec3, '"vouch":"[A-Za-z0-9_-]*"\}\z', '"vouch":""}')
    $nb3 = '{"record":' + (ConvertTo-HordeCloudflareRelayJsonString $noVouch) + '}'
    Check ((Send-To -Url ($O + "/v1/machines/rotation") -Method "POST" -Body $nb3 -Authorization (Get-SignedAuthorization -Dev $X -Signer $s3 -Method "POST" -Target "/v1/machines/rotation" -Body $nb3)).code -eq 401) "nor a record with no vouch"
    Check ((Send-To -Url ($O + "/v1/machines/rotation") -Method "POST" -Body $b3 -Authorization (New-HordeCloudflareRelayMachineAuthorization -Key $s2.key -KeyId $s3.keyId -Origin $O -Method "POST" -Target "/v1/machines/rotation" -Body ([System.Text.Encoding]::ASCII.GetBytes($b3)))).code -eq 401) "nor one under the successor's key id, signed by another key"
    $elsewhereId = ConvertTo-HordeRelayHex -Bytes (Get-HordeRelayRandomBytes -Count 16)
    Check ((Send-To -Url ($O + "/v1/machines/rotation") -Method "POST" -Body $b3 -Authorization (New-HordeCloudflareRelayMachineAuthorization -Key $s3.key -KeyId $elsewhereId -Origin $O -Method "POST" -Target "/v1/machines/rotation" -Body ([System.Text.Encoding]::ASCII.GetBytes($b3)))).code -eq 401) "nor one the successor signs under another key id: the registration lands under no other"
    $staleR = Send-To -Url ($O + "/v1/machines/rotation") -Method "POST" -Body $b3 -Authorization (New-HordeCloudflareRelayMachineAuthorization -Key $s3.key -KeyId $s3.keyId -Origin $O -Method "POST" -Target "/v1/machines/rotation" -Body ([System.Text.Encoding]::ASCII.GetBytes($b3)) -Time ([System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - 61000))
    Check ($staleR.code -eq 401 -and $staleR.text.Contains("clock")) "nor a stale one, told so"
    Check ((Send-To -Url ($O + "/v1/machines/rotation") -Method "POST" -Body $b3 -Authorization (Get-SignedAuthorization -Dev $X -Signer $s3 -Method "POST" -Target "/v1/machines/rotation" -Body $b3)).code -eq 200) "CONTROL: the true record from its successor does"

    $r5 = New-Machine -Dev $X -Cookie $rotP.cookie -Label "watching-box"
    $null = Update-HordeRelayMachineIdentity -HordeHome $r5.home -Reason "scheduled" -Provider "software"
    $rc5 = (Connect-HordeRelay -Name "cloudflare" -Options @{ origin = $O; hordeHome = $r5.home }).value
    $w5 = Wait-HordeRelayItems -Connection $rc5 -Mailbox "work/phone" -Since 0 -TimeoutMs 1000
    Check ($w5.state -ceq "known" -and $rc5.state.rotationTried -eq $true) ("a rotated machine whose first request is a watch carries its vouch too, and watches (" + $w5.reason + ")")

    $r6 = New-Machine -Dev $X -Cookie $rotP.cookie -Label "contested-box"
    $null = Update-HordeRelayMachineIdentity -HordeHome $r6.home -Reason "scheduled" -Provider "software"
    $rec6 = (Get-HordeRelayRetirementText -HordeHome $r6.home -Generation 1).value
    $s6 = (Open-HordeCloudflareRelaySigner -HordeHome $r6.home).value
    [void]$script:signers.Add($s6)
    $otherAcct = New-Phone -Dev $X -Sub "100000000000000001002"
    $taken6 = Send-To -Url ($O + "/v1/account/machines") -Method "POST" -Body (New-Offer -Machine $r6 -Label "contested-box") -Cookie $otherAcct.cookie -Origin $O
    $b6 = '{"record":' + (ConvertTo-HordeCloudflareRelayJsonString $rec6) + '}'
    $contested = Send-To -Url ($O + "/v1/machines/rotation") -Method "POST" -Body $b6 -Authorization (Get-SignedAuthorization -Dev $X -Signer $s6 -Method "POST" -Target "/v1/machines/rotation" -Body $b6)
    Check ($taken6.code -eq 200 -and $contested.code -eq 401) ("a successor already registered to another account is not taken over by the rotation (" + $taken6.code + ", " + $contested.code + ")")
    $null = Send-To -Url ($O + "/v1/account/machines/" + $s6.keyId) -Method "DELETE" -Cookie $otherAcct.cookie -Origin $O
    $retried = Send-To -Url ($O + "/v1/machines/rotation") -Method "POST" -Body $b6 -Authorization (Get-SignedAuthorization -Dev $X -Signer $s6 -Method "POST" -Target "/v1/machines/rotation" -Body $b6)
    Check ($retried.code -eq 200) ("and the old registration was put back, so once the other account lets the key go, the rotation moves it (" + $retried.text + ")")

    $r4 = New-Machine -Dev $X -Cookie $rotP.cookie -Label "removed-box"
    $null = Send-To -Url ($O + "/v1/account/machines/" + $r4.kid) -Method "DELETE" -Cookie $rotP.cookie -Origin $O
    $null = Update-HordeRelayMachineIdentity -HordeHome $r4.home -Reason "scheduled" -Provider "software"
    $rc4 = (Connect-HordeRelay -Name "cloudflare" -Options @{ origin = $O; hordeHome = $r4.home }).value
    $after4 = Receive-HordeRelayItems -Connection $rc4 -Mailbox "work/phone" -Since 0
    Check ($after4.state -ceq "unknown" -and $after4.reason.Contains("401") -and $rc4.state.rotationTried -eq $true) ("a machine the account removed stays removed after it rotates: its vouch moves nothing (" + $after4.reason + ")")

    Write-Host ""
    Write-Host "--- each machine is a device of its own ---" -ForegroundColor Cyan
    $twoP = New-Phone -Dev $X -Sub "100000000000000001201"
    $busy = New-Machine -Dev $X -Cookie $twoP.cookie -Label "busy-box"
    $calm = New-Machine -Dev $X -Cookie $twoP.cookie -Label "calm-box"
    # Puts: a burst of 20, then one a second (the defaults). The busy machine puts until it is refused;
    # the other's put follows at once, before a token could come back to a bucket the two shared.
    $taken = 0
    $refusedPut = $null
    for ($i = 1; $i -le 40 -and $null -eq $refusedPut; $i++) {
        $pa = Send-Signed -Dev $X -Signer $busy.signer -Method "POST" -Target "/v1/mailboxes/work/busy/items" -Body ('{"key":"b-' + $i + '","text":"busy"}')
        if ($pa.code -eq 200) { $taken++ } else { $refusedPut = $pa }
    }
    $calmPut = Send-Signed -Dev $X -Signer $calm.signer -Method "POST" -Target "/v1/mailboxes/work/calm/items" -Body '{"key":"c-1","text":"calm"}'
    Check ($taken -ge 20 -and $null -ne $refusedPut -and $refusedPut.code -eq 429) ("one machine puts its burst of 20, and is then refused (" + $taken + " taken)")
    Check ($calmPut.code -eq 200) "and another machine of the same account puts at once: its bucket is its own"

    Write-Host ""
    Write-Host "--- deleting an account ---" -ForegroundColor Cyan
    $sub = "100000000000000001101"
    $d1 = New-Phone -Dev $X -Sub $sub
    $d2 = New-Phone -Dev $X -Sub $sub
    $dmach = New-Machine -Dev $X -Cookie $d1.cookie -Label "doomed-box"
    # More mailboxes than one alarm run wipes (accounts.js, WIPE_BATCH 20), so the wipe must go on in a
    # second run: work/zzzz sorts last of them all, and the machine watches it.
    $filled = @(0..19 | ForEach-Object { (Send-To -Url ($O + "/v1/mailboxes/work/" + $_.ToString("0000") + "/items") -Method "POST" -Body ('{"key":"d-' + $_ + '","text":"doomed"}') -Cookie $d1.cookie -Origin $O).code })
    $filled += @(@("a", "b", "c", "zzzz") | ForEach-Object { (Send-To -Url ($O + "/v1/mailboxes/work/" + $_ + "/items") -Method "POST" -Body ('{"key":"d-' + $_ + '","text":"doomed"}') -Cookie $d2.cookie -Origin $O).code })
    Check (@($filled | Where-Object { $_ -ne 200 }).Count -eq 0) ("twenty-four mailboxes filled (" + ($filled -join ",") + ")")
    $mput = Send-Signed -Dev $X -Signer $dmach.signer -Method "POST" -Target ("/v1/mailboxes/work/" + $dmach.kid + "/items") -Body '{"key":"m-1","text":"doomed too"}'
    Check ($dmach.reg.code -eq 200 -and $mput.code -eq 200) "an account with two phones, a machine, and twenty-five mailboxes holding items"
    Check ((Send-To -Url ($O + "/v1/account") -Method "DELETE" -Body '{"confirm":"yes"}' -Cookie $d1.cookie -Origin $O).code -eq 400) "a deletion that does not say so in the words asked for is refused"
    Check ((Send-To -Url ($O + "/v1/account") -Method "DELETE" -Body '{"confirm":"delete this account"}' -Cookie $d1.cookie -Origin "https://evil.example.test").code -eq 401) "and one from another site's page"
    Check ((Send-Signed -Dev $X -Signer $dmach.signer -Method "DELETE" -Target "/v1/account" -Body '{"confirm":"delete this account"}').code -eq 403) "and one from a machine: only a phone deletes its account"
    $ps = [PowerShell]::Create()
    [void]$ps.AddScript({
            param($Port, $Origin, $HordeHome, $Mailbox)
            . $Port
            foreach ($f in @(Get-HordeRelayFiles)) { . $f }
            $c = (Connect-HordeRelay -Name "cloudflare" -Options @{ origin = $Origin; hordeHome = $HordeHome }).value
            $w = Wait-HordeRelayItems -Connection $c -Mailbox $Mailbox -Since 1 -TimeoutMs 20000
            return @($w.state, $w.reason)
        }).AddArgument((Join-Path $root "relays\Port.ps1")).AddArgument($O).AddArgument($dmach.home).AddArgument("work/zzzz")
    $racing = New-Object System.Collections.ArrayList
    try {
        $h = $ps.BeginInvoke()
        Start-Sleep -Milliseconds 2500
        for ($i = 1; $i -le 12; $i++) {
            $req = New-Object System.Net.Http.HttpRequestMessage((New-Object System.Net.Http.HttpMethod("POST")), ($O + "/v1/mailboxes/work/race/items"))
            [void]$req.Headers.TryAddWithoutValidation("Cookie", $d2.cookie)
            [void]$req.Headers.TryAddWithoutValidation("Origin", $O)
            $req.Content = New-Object System.Net.Http.StringContent(('{"key":"race-' + $i + '","text":"racing"}'), [System.Text.Encoding]::ASCII, "application/json")
            [void]$racing.Add($http.SendAsync($req))
        }
        $del = Send-To -Url ($O + "/v1/account") -Method "DELETE" -Body '{"confirm":"delete this account"}' -Cookie $d1.cookie -Origin $O
        $raceCodes = @($racing | ForEach-Object { [int]$_.GetAwaiter().GetResult().StatusCode })
        $watchEnd = @($ps.EndInvoke($h) | ForEach-Object { "$_" })
    } finally { $ps.Dispose(); foreach ($t in $racing) { try { $t.Result.Dispose() } catch { } } }
    Check ($del.code -eq 200 -and (Get-Json $del).deleted -eq $true -and @($del.cookies | Where-Object { $_ -clike "__Host-horde-session=x; Max-Age=0;*" }).Count -eq 1) ("the phone deletes its account, and its own cookie is cleared (" + $del.text + ")")
    Check (@($raceCodes | Where-Object { @(200, 401, 410) -notcontains $_ }).Count -eq 0) ("puts racing the deletion are each taken before it or refused after it - never a failure of the relay (" + ($raceCodes -join ",") + ")")
    Check ((Send-To -Url ($O + "/v1/account") -Cookie $d1.cookie).code -eq 401 -and (Send-To -Url ($O + "/v1/mailboxes/work/a/items?since=0&max=1") -Cookie $d2.cookie).code -eq 401) "at once, both phones' sessions are over"
    Check ((Send-Signed -Dev $X -Signer $dmach.signer -Target ("/v1/mailboxes/work/" + $dmach.kid + "/items?since=0&max=1")).code -eq 401) "and the machine's registration"
    Check ((Send-To -Url ($O + "/auth/session") -Cookie $d2.cookie).text -ceq '{"signedIn":false,"email":""}') "the other phone's session itself is ended, not only refused: it is signed out"
    Check ($watchEnd.Count -eq 2 -and $watchEnd[0] -ceq "unknown" -and $watchEnd[1].Contains("deleted")) ("and the machine's waiting watch, in the mailbox wiped last, is ended, said why: every mailbox was wiped, more than one alarm run's worth (" + ($watchEnd -join ": ") + ")")
    Check ((Send-To -Url ($O + "/v1/account") -Method "DELETE" -Body '{"confirm":"delete this account"}' -Cookie $d1.cookie -Origin $O).code -eq 401) "the deleted account cannot be deleted again by its old cookie"
    Start-Sleep -Milliseconds 1500
    $reborn = New-Phone -Dev $X -Sub $sub
    $rv = Get-Json (Send-To -Url ($O + "/v1/account") -Cookie $reborn.cookie)
    Check ($reborn.session -ne "" -and @($rv.machines).Count -eq 0 -and @($rv.phones).Count -eq 1) "the same Google account signs up again, as a new account: no machine, one phone"
    $empty = @("a", "b", "c", "race", "0000", "0019", "zzzz", $dmach.kid) | ForEach-Object { @((Get-Json (Send-To -Url ($O + "/v1/mailboxes/work/" + $_ + "/items?since=0&max=10") -Cookie $reborn.cookie)).items).Count }
    Check ((@($empty) -join ",") -ceq "0,0,0,0,0,0,0,0") ("and every mailbox of the old one is empty to it, the raced ones too (" + (@($empty) -join ",") + ")")
    $fresh = Send-To -Url ($O + "/v1/mailboxes/work/a/items") -Method "POST" -Body '{"key":"new-1","text":"new"}' -Cookie $reborn.cookie -Origin $O
    Check ($fresh.code -eq 200 -and (Get-Json $fresh).seq -eq 1) "a put there starts a new mailbox, from seq 1"
    Check ((Send-Signed -Dev $X -Signer $dmach.signer -Target ("/v1/mailboxes/work/" + $dmach.kid + "/items?since=0&max=1")).code -eq 401) "and the old machine is not the new account's: it must be paired again"
    $stranger = New-Phone -Dev $X -Sub "100000000000000001102"
    Check ((Send-To -Url ($O + "/v1/account/machines") -Method "POST" -Body (New-Offer -Machine $dmach -Label "doomed-box") -Cookie $stranger.cookie -Origin $O).code -eq 200) "its key was released, not left to the deleted account: any account may pair it now"
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
    if ($work -like "*horde-cf-limits-*" -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
Check (-not (Test-Path -LiteralPath $work)) "the suite's folder is gone"

Complete-HordeSuite -Success "every account, device and address is held to its limits - refused, never dropped - nothing outlives its retention, a deleted account is gone whole, and a rotated machine moves once"
