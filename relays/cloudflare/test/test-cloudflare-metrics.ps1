# DOES THE HOSTED RELAY COUNT EVERY REQUEST EXACTLY, BY FIXED WORDS ONLY - NOTHING OF WHAT A REQUEST
# CARRIED - AT NO COST TO ANY USER'S REQUEST OR BUDGET, SHOW THE RELAY-WIDE VIEW ONLY TO AN OWNER'S
# MACHINE, AND DOES THE PC FETCH IT ONCE A DAY?
#
# The relay's request metrics (the design note of 2026-10-14, Orc F, approved by C; worker/metrics.js and
# the files beside it; cli/RelayMetrics.ps1). Each of the design's tests is a part here:
#   1. THE PURE PARTS, under node (metrics-units.mjs): the fixed lists, an isolate's counts and when they
#      are flushed, the metrics object's rows over a storage in memory - its own line, its summary, ITS
#      30-DAY RETENTION BY THE DAILY ALARM (6) - and A METRICS OBJECT THAT THROWS, REFUSES OR NEVER
#      ANSWERS, under the request wrapper itself (3).
#   2. A DEV THAT FLUSHES EVERY REQUEST (the test override HORDE_RELAY_TEST_METRICS, flushCount 1):
#      NO TEXT FROM A MESSAGE REACHES A SUMMARY (1) - puts, reads, watches and acks whose bodies, keys and
#      mailbox names hold a marker, then not a byte of it in the summary, and every string in it from the
#      fixed lists, an hour, a day or a 16-hex hash; THE COUNTS ARE EXACT FOR A SCRIPTED MIX (2), with a
#      must-fail twin; ONLY AN OWNER'S MACHINE READS THE RELAY-WIDE VIEW (5); THE METRICS OBJECT'S OWN
#      CALLS ARE A LINE OF THEIR OWN (8); and THE PC'S PULL MAKES ONE REQUEST A DAY AND WRITES ITS FILE (7).
#   3. A DEV WHOSE METRICS OBJECT REFUSES EVERY FLUSH (failFlush): every user request answered as ever,
#      and as fast (3).
#   4. A DEV WITH A TINY DAY: METRICS' OWN CALLS NEVER MOVE A BUDGET COUNTER (4) - the relay's day runs out
#      after exactly the requests made, however many flushes went on beside them - while A SUMMARY CALL IS
#      COUNTED like any request of its account (review of PR 300), and ITS BRAKE holds: of calls in
#      parallel one passes, and a refused call brakes the next.
#
# NODE IS NEEDED, and the pinned wrangler (relays/cloudflare/Wrangler.ps1 installs it outside the tree);
# without them parts 2 to 4 are skipped, said so, and the suite exits 3, never 0. A key store too: the
# machines' identities are made with the software provider in Horde homes of the suite's own under %TEMP%,
# and every key is removed at the end and checked gone. Each dev is stopped as soon as its part is done,
# so at most one runs at a time. Google and Cloudflare are never contacted.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "relays\Port.ps1")
foreach ($f in @(Get-HordeRelayFiles)) { . $f }
. (Join-Path $root "relay\Pairing.ps1")
. (Join-Path $root "cli\RelayDeploy.ps1")
. (Join-Path $root "cli\RelayMetrics.ps1")
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Net.Http
Write-Host ("  runtime: PowerShell " + $PSVersionTable.PSVersion + " (" + $PSVersionTable.PSEdition + ")") -ForegroundColor DarkGray

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$work = Join-Path $env:TEMP ("horde-cf-metrics-" + [guid]::NewGuid().ToString("N").Substring(0, 12))
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
Invoke-NodeChecks -ArgList @((Join-Path $here "metrics-units.mjs"), $root) -AtLeast 45 -What "the unit checks"

# THE FIXED LISTS, from the Worker's own module (worker/metrics.js): what every string of a summary may be.
$listsRun = Invoke-HordeCloudflareRelayNode -Node $node -ArgList @("--input-type=module", "-e", ('import * as M from "' + ([System.Uri](Join-Path $root "relays\cloudflare\worker\metrics.js")).AbsoluteUri + '"; process.stdout.write(JSON.stringify({ routes: M.ROUTES, kinds: M.KINDS, outcomes: M.OUTCOMES }));')) -WorkDir $work -TimeoutSeconds 60
$lists = $null
try { $lists = ("" + $listsRun.out) | ConvertFrom-Json } catch { $lists = $null }
Check ($null -ne $lists -and @($lists.routes).Count -eq 13 -and @($lists.kinds).Count -eq 3 -and @($lists.outcomes) -ccontains "relay-daily-limit") ("the fixed lists are read from the Worker's own module (" + ("" + $listsRun.err).Trim() + ")")
$allowed = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($w in @($lists.routes) + @($lists.kinds) + @($lists.outcomes) + @("relay", "account")) { [void]$allowed.Add([string]$w) }

$tools = Install-HordeCloudflareRelayTools
$store = Get-HordeRelayKeyStore
if ($tools.state -cne "known" -or $store.state -cne "known") {
    Write-Host ("  [SKIP] the Worker or the machines cannot be run here: " + $(if ($tools.state -cne "known") { $tools.reason } else { $store.reason })) -ForegroundColor Yellow
    Remove-Item -LiteralPath $work -Recurse -Force
    Complete-HordeSuite -Success "the pure parts hold; the Worker itself was NOT RUN here" -PassCode 3
}

$clientId = "1234567890-fakeclient.apps.googleusercontent.com"
$clientSecret = "GOCSPX-" + (New-HordeCloudflareRelayToken).Substring(0, 28)
$salt = New-HordeCloudflareRelayToken
$script:homes = New-Object System.Collections.ArrayList
$script:procs = New-Object System.Collections.ArrayList
$script:signers = New-Object System.Collections.ArrayList
$devs = New-Object System.Collections.ArrayList
. (Join-Path $here "Harness.ps1")

$script:addressCount = 0
function New-Address { $script:addressCount++; return ("10.7." + [Math]::Floor($script:addressCount / 250) + "." + (($script:addressCount % 250) + 1)) }
function New-Phone {
    param($Dev, [string]$Sub, [string]$Email = "")
    if ($Email -eq "") { $Email = $Sub + "@example.test" }
    $r = Invoke-SignIn -Dev $Dev -Provider $fake -Scenario @{ sub = $Sub; email = $Email } -Address (New-Address)
    $r | Add-Member -NotePropertyName cookie -NotePropertyValue ("__Host-horde-session=" + $r.session)
    return $r
}
function New-Machine {
    param($Dev, [string]$Cookie, [string]$Label = "box")
    $m = New-TestHome -Horde "work"
    $o = New-HordeRelayPairingOffer -HordeHome $m.home -RpId "relay.example.test" -Origins @("https://relay.example.test") -Label $Label
    $reg = Send-To -Url ($Dev.origin + "/v1/account/machines") -Method "POST" -Body (Get-Registration -OfferText $o.value.text) -Cookie $Cookie -Origin $Dev.origin
    $s = (Open-HordeCloudflareRelaySigner -HordeHome $m.home).value
    [void]$script:signers.Add($s)
    return [pscustomobject]@{ home = $m.home; kid = $s.keyId; signer = $s; reg = $reg }
}
function Send-Signed {
    # One request signed by -Signer's key; -Attempt adds x-horde-attempt, as the machine's client does.
    param($Dev, $Signer, [string]$Method = "GET", [string]$Target, [string]$Body = "", [int]$Attempt = 0)
    $bytes = New-Object byte[] 0
    if ($Body -ne "") { $bytes = [System.Text.Encoding]::ASCII.GetBytes($Body) }
    $auth = New-HordeCloudflareRelayMachineAuthorization -Key $Signer.key -KeyId $Signer.keyId -Origin $Dev.origin -Method $Method -Target $Target -Body $bytes
    if ($Attempt -le 0) { return (Send-To -Url ($Dev.origin + $Target) -Method $Method -Body $Body -Authorization $auth) }
    $req = New-Object System.Net.Http.HttpRequestMessage((New-Object System.Net.Http.HttpMethod($Method)), ($Dev.origin + $Target))
    [void]$req.Headers.TryAddWithoutValidation("Authorization", $auth)
    [void]$req.Headers.TryAddWithoutValidation("x-horde-attempt", ("" + $Attempt))
    if ($Body -ne "") { $req.Content = New-Object System.Net.Http.ByteArrayContent(, $bytes); $req.Content.Headers.ContentType = New-Object System.Net.Http.Headers.MediaTypeHeaderValue("application/json") }
    try { $res = $http.SendAsync($req).GetAwaiter().GetResult(); try { return [pscustomobject]@{ code = [int]$res.StatusCode; text = $res.Content.ReadAsStringAsync().GetAwaiter().GetResult() } } finally { $res.Dispose() } } finally { $req.Dispose() }
}
function Get-Json { param($Answer) try { return ($Answer.text | ConvertFrom-Json) } catch { return $null } }
function Start-Dev {
    param([string]$Name, [string]$Limits = "{}", [string]$Metrics, [hashtable]$More = @{})
    $vars = @{ HORDE_RELAY_TEST_OIDC = $fake.issuer; GOOGLE_CLIENT_ID = $clientId; GOOGLE_CLIENT_SECRET = $clientSecret; HORDE_RELAY_TEST_LIMITS = $Limits; HORDE_RELAY_TEST_METRICS = $Metrics; METRICS_SALT = $salt }
    foreach ($k in @($More.Keys)) { $vars[$k] = $More[$k] }
    $d = Start-HordeCloudflareRelayDev -Work (Join-Path $work $Name) -Site $site -Script $tools.value.script -ExtraVars $vars
    Check ($d.state -ceq "known") ("a dev with metrics " + $Metrics + " answers (" + $d.reason + ")")
    if ($d.state -cne "known") { throw ("no dev " + $Name) }
    [void]$devs.Add($d.value)
    return $d.value
}
function Stop-Dev { param($Dev) Stop-HordeCloudflareRelayDev -Dev $Dev; [void]$devs.Remove($Dev) }
function Get-Summary {
    # The summary of -Day as -Machine reads it (scope "" asks as the PC does): { code; json; text }.
    param($Dev, $Machine, [string]$Day, [string]$Scope = "")
    $t = "/v1/metrics/summary?day=" + $Day + $(if ($Scope -ne "") { "&scope=" + $Scope } else { "" })
    $a = Send-Signed -Dev $Dev -Signer $Machine.signer -Target $t
    return [pscustomobject]@{ code = $a.code; json = (Get-Json $a); text = $a.text }
}
function Get-RowCounts {
    # A relay-wide summary's request rows as route|kind|outcome -> count, every hour of it summed;
    # rows of count 0 (a watch's end alone) left out. And the rows themselves, by the same key.
    param($Summary)
    $counts = @{}
    $rows = @{}
    foreach ($r in @(Get-HordeTestMember $Summary "requests")) {
        $k = "" + (Get-HordeTestMember $r "route") + "|" + (Get-HordeTestMember $r "kind") + "|" + (Get-HordeTestMember $r "outcome")
        if (-not $rows.ContainsKey($k)) { $rows[$k] = New-Object System.Collections.ArrayList }
        [void]$rows[$k].Add($r)
        $n = [long](Get-HordeTestMember $r "count")
        if ($n -gt 0) { $counts[$k] = [long]$(if ($counts.ContainsKey($k)) { $counts[$k] } else { 0 }) + $n }
    }
    return [pscustomobject]@{ counts = $counts; rows = $rows }
}
function Get-RowSum { param($Rows, [string]$Key, [string]$Name) $s = [long]0; if ($Rows.ContainsKey($Key)) { foreach ($r in @($Rows[$Key])) { $s += [long](Get-HordeTestMember $r $Name) } }; return $s }
function Compare-Counts {
    # "" when -Actual is exactly -Expected (key -> count), else what differs.
    param([hashtable]$Actual, [hashtable]$Expected)
    $diff = New-Object System.Collections.ArrayList
    foreach ($k in @($Expected.Keys + $Actual.Keys | Sort-Object -Unique)) {
        $a = $(if ($Actual.ContainsKey($k)) { $Actual[$k] } else { 0 })
        $e = $(if ($Expected.ContainsKey($k)) { $Expected[$k] } else { 0 })
        if ($a -ne $e) { [void]$diff.Add($k + " " + $a + "/" + $e) }
    }
    return ($diff -join ", ")
}
function Get-StringValues {
    # Every string value anywhere under -Value (property names are not values).
    param($Value)
    $out = New-Object System.Collections.ArrayList
    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) { [void]$out.Add($Value); return @($out) }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [System.Management.Automation.PSCustomObject]) { foreach ($v in $Value) { foreach ($s in @(Get-StringValues $v)) { [void]$out.Add($s) } }; return @($out) }
    if ($Value -is [System.Management.Automation.PSCustomObject]) { foreach ($p in $Value.PSObject.Properties) { foreach ($s in @(Get-StringValues $p.Value)) { [void]$out.Add($s) } } }
    return @($out)
}
function Test-AllowedString {
    param([string]$S)
    return ($allowed.Contains($S) -or $S -cmatch '\A[0-9]{4}-[0-9]{2}-[0-9]{2}(T[0-9]{2})?\z' -or $S -cmatch '\A[0-9a-f]{16}\z')
}
function Add-Expected { param([hashtable]$E, [string]$Key, [int]$By = 1) $E[$Key] = [int]$(if ($E.ContainsKey($Key)) { $E[$Key] } else { 0 }) + $By }

try {
    $fake = Start-FakeProvider
    $site = Join-Path $work "site"
    $built = New-HordeRelayDeploySite -Out $site
    Check ($built.state -ceq "known") ("the phone app is built as the deploy builds it (" + $built.reason + ")")
    $ownerSub = "100000000000000002101"
    $otherSub = "100000000000000002102"
    # THE OWNERS as PR 281 names them (worker/budget.js): one by account id, one by email.
    $ownerEmail = "boss-" + [guid]::NewGuid().ToString("N").Substring(0, 8) + "@example.test"
    $owners = @{ HORDE_RELAY_OWNER_ACCOUNTS = ('{"emails":["' + $ownerEmail + '"],"subs":["' + $ownerSub + '"]}') }

    Write-Host ""
    Write-Host "--- 2. a dev that flushes every request: no text reaches a summary, and the counts are exact ---" -ForegroundColor Cyan
    $M = Start-Dev -Name "metrics" -Metrics '{"flushCount":1,"summaryEveryMs":1}' -More $owners
    $O = $M.origin
    $day = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
    $expected = @{}
    # The launcher's own readiness probe (Wrangler.ps1, Start-HordeCloudflareRelayDev): GET /v1/ until the
    # dev answers, which only its first answered try reaches the Worker as - a 401 to nobody.
    Add-Expected $expected "other|anonymous|unauthenticated"
    # THE MARKER: in mailbox names, keys and texts. Lower-case hex after a fixed start, so it is a legal
    # mailbox part, key and text, and nothing in a summary can be it by chance.
    $marker = "zqmk" + [guid]::NewGuid().ToString("N").Substring(0, 12)
    $po = New-Phone -Dev $M -Sub $ownerSub
    Add-Expected $expected "auth.start|anonymous|ok"; Add-Expected $expected "auth.callback|anonymous|ok"
    $px = New-Phone -Dev $M -Sub $otherSub
    Add-Expected $expected "auth.start|anonymous|ok"; Add-Expected $expected "auth.callback|anonymous|ok"
    $mo = New-Machine -Dev $M -Cookie $po.cookie -Label "owner-box"
    $mx = New-Machine -Dev $M -Cookie $px.cookie -Label "other-box"
    Add-Expected $expected "pair.register|phone|ok" 2
    Check ($po.session -ne "" -and $px.session -ne "" -and $mo.reg.code -eq 200 -and $mx.reg.code -eq 200) "two accounts, each with a phone and a machine: one of them the relay's owner"
    $box = "work/" + $marker
    $putBytes = [long]0
    $puts = @(1, 2, 3 | ForEach-Object {
            $b = '{"key":"k-' + $marker + '-' + $_ + '","text":"the text ' + $marker + ' number ' + $_ + '"}'
            $putBytes += $b.Length
            (Send-To -Url ($O + "/v1/mailboxes/" + $box + "/items") -Method "POST" -Body $b -Cookie $po.cookie -Origin $O).code
        })
    Add-Expected $expected "items.put|phone|ok" 3
    $gets = @(1, 2 | ForEach-Object { (Send-To -Url ($O + "/v1/mailboxes/" + $box + "/items?since=0&max=10") -Cookie $po.cookie).code })
    Add-Expected $expected "items.get|phone|ok" 2
    # A phone's watch, opened and let go of at once with nothing come: an empty watch, ended by its client.
    $up = Get-UpgradeStatus -Origin $O -Path ("/v1/mailboxes/work/" + $marker + "w/watch?since=0&max=5&timeoutMs=20000") -Cookie $po.cookie -PageOrigin $O
    Add-Expected $expected "watch|phone|ok"
    $mput = Send-Signed -Dev $M -Signer $mo.signer -Method "POST" -Target ("/v1/mailboxes/" + $box + "/items") -Body ('{"key":"m-' + $marker + '","text":"machine ' + $marker + '"}')
    Add-Expected $expected "items.put|machine|ok"
    $retry = Send-Signed -Dev $M -Signer $mo.signer -Target ("/v1/mailboxes/" + $box + "/items?since=0&max=10") -Attempt 3
    Add-Expected $expected "items.get|machine|ok"
    # The machine's own client watches, waits its 1.5 s, and closes: an empty watch held about a second.
    $mc = (Connect-HordeRelay -Name "cloudflare" -Options @{ origin = $O; hordeHome = $mo.home }).value
    $mw = Wait-HordeRelayItems -Connection $mc -Mailbox ("work/" + $marker + "m") -Since 0 -TimeoutMs 1500
    Add-Expected $expected "watch|machine|ok"
    $mack = Send-Signed -Dev $M -Signer $mo.signer -Method "POST" -Target ("/v1/mailboxes/" + $box + "/ack") -Body '{"through":4}'
    Add-Expected $expected "ack|machine|ok"
    $bad = Send-To -Url ($O + "/v1/mailboxes/" + $box + "/items?since=x&max=1") -Cookie $po.cookie
    Add-Expected $expected "items.get|phone|bad-request"
    $anon = Send-To -Url ($O + "/v1/mailboxes/" + $box + "/items?since=0&max=1")
    Add-Expected $expected "items.get|anonymous|unauthenticated"
    $none = Send-To -Url ($O + "/v1/" + $marker) -Cookie $po.cookie
    Add-Expected $expected "other|phone|not-found"
    $view = Send-To -Url ($O + "/v1/account") -Cookie $po.cookie
    Add-Expected $expected "account.view|phone|ok"
    Check ((@($puts) -join ",") -ceq "200,200,200" -and (@($gets) -join ",") -ceq "200,200" -and $up.Contains("101") -and $mput.code -eq 200 -and $retry.code -eq 200 -and $mw.state -ceq "known" -and $mack.code -eq 200 -and $bad.code -eq 400 -and $anon.code -eq 401 -and $none.code -eq 404 -and $view.code -eq 200) ("the scripted mix is answered as it always was: puts, reads, two watches, an ack, three refusals and the account (" + (@($puts) -join ",") + "; " + $up + "; " + $mw.state + "; " + $bad.code + "," + $anon.code + "," + $none.code + ")")

    # The counts arrive after the answers (ctx.waitUntil), and a watch's end when its client lets it go:
    # read until they are what was sent, for up to 20 s. The summary reads themselves are not counted.
    $reads = 0
    $sum = $null
    $got = $null
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    do {
        Start-Sleep -Milliseconds 500
        $sum = Get-Summary -Dev $M -Machine $mo -Day $day -Scope "relay"
        $reads++
        $got = Get-RowCounts $sum.json
        $ends = (Get-RowSum $got.rows "watch|phone|ok" "emptyWatch") + (Get-RowSum $got.rows "watch|machine|ok" "emptyWatch")
    } while ($sw.ElapsedMilliseconds -lt 20000 -and ((Compare-Counts -Actual $got.counts -Expected $expected) -ne "" -or $ends -lt 2))
    $day2 = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
    Check ($day2 -ceq $day) ("CONTROL: the suite ran within one UTC day, so one day's summary holds it all (" + $day + ", " + $day2 + ")")
    Check ($sum.code -eq 200 -and ("" + (Get-HordeTestMember $sum.json "scope")) -ceq "relay") ("the owner's machine reads the relay-wide summary (" + $sum.code + ")")
    $diff = Compare-Counts -Actual $got.counts -Expected $expected
    Check ($diff -ceq "") ("THE COUNTS ARE EXACT: every request of the scripted mix, by route, kind and outcome, and nothing else - not one of the " + $reads + " summary reads (" + $(if ($diff -ne "") { $diff } else { @($expected.Keys).Count.ToString() + " rows" }) + ")")
    $twin = @{}
    foreach ($k in @($expected.Keys)) { $twin[$k] = $expected[$k] }
    $twin["items.put|phone|ok"] = $twin["items.put|phone|ok"] - 1
    Check ((Compare-Counts -Actual $got.counts -Expected $twin) -ne "") "MUST-FAIL TWIN: the same mix with one put taken away does not match"
    Check ((Get-RowSum $got.rows "items.put|phone|ok" "bytesIn") -eq $putBytes -and (Get-RowSum $got.rows "items.put|phone|ok" "bytesOut") -gt 0) ("the phone's puts' bytes in are their bodies' exactly, and their answers' bytes out are counted (" + (Get-RowSum $got.rows "items.put|phone|ok" "bytesIn") + " of " + $putBytes + ")")
    Check ((Get-RowSum $got.rows "items.get|machine|ok" "retries") -eq 1 -and (Get-RowSum $got.rows "items.put|machine|ok" "retries") -eq 0) "the machine's read that said x-horde-attempt 3 is counted a retry, and its first try is not"
    Check ((Get-RowSum $got.rows "watch|phone|ok" "emptyWatch") -eq 1 -and (Get-RowSum $got.rows "watch|machine|ok" "emptyWatch") -eq 1 -and (Get-RowSum $got.rows "watch|machine|ok" "watchSeconds") -ge 1) ("each watch that ended with nothing is an empty watch, and the machine's was held a second or more (" + (Get-RowSum $got.rows "watch|machine|ok" "watchSeconds") + " s)")
    $hist = @(@(Get-HordeTestMember $sum.json "requests") | Where-Object { [long](Get-HordeTestMember $_ "count") -gt 0 } | Where-Object { $l = Get-HordeTestMember $_ "latency"; ([long](Get-HordeTestMember $l "lt50ms") + [long](Get-HordeTestMember $l "lt200ms") + [long](Get-HordeTestMember $l "lt1s") + [long](Get-HordeTestMember $l "lt5s") + [long](Get-HordeTestMember $l "more")) -ne [long](Get-HordeTestMember $_ "count") })
    Check ($hist.Count -eq 0) "every row's latency histogram holds each of its requests once"

    # (1) NOTHING OF A MESSAGE.
    Check ($sum.text.Length -gt 100 -and -not $sum.text.Contains($marker) -and -not $sum.text.Contains("zqmk")) ("NO TEXT FROM A MESSAGE REACHES A SUMMARY: the marker that was in every mailbox name, key and text is nowhere in it (" + $sum.text.Length + " characters)")
    $strings = @(Get-StringValues $sum.json)
    $odd = @($strings | Where-Object { -not (Test-AllowedString $_) })
    Check ($strings.Count -gt 20 -and $odd.Count -eq 0) ("and every string in it is a word of the fixed lists, an hour, a day or a 16-hex account hash (" + $strings.Count + " strings; " + ($odd -join ",") + ")")
    Check (-not (Test-AllowedString $marker) -and -not (Test-AllowedString "work/phone") -and (Test-AllowedString "items.put") -and (Test-AllowedString "0123456789abcdef")) "CONTROL: that check refuses the marker and a mailbox name, and takes a route and a hash"
    $hashes = @(@(Get-HordeTestMember $sum.json "accounts") | ForEach-Object { "" + (Get-HordeTestMember $_ "account") } | Sort-Object -Unique)
    Check ($hashes.Count -eq 2 -and @($hashes | Where-Object { $_ -cnotmatch '\A[0-9a-f]{16}\z' }).Count -eq 0 -and -not $sum.text.Contains($ownerSub) -and -not $sum.text.Contains($otherSub) -and -not $sum.text.Contains("example.test") -and -not $sum.text.Contains("boss-")) ("two accounts, each under a 16-hex hash: no account id and no email in it (" + ($hashes -join ",") + ")")

    Write-Host ""
    Write-Host "--- a phone's watch refused by a limit is counted under its code, not ok ---" -ForegroundColor Cyan
    # A third account's phone spends its read burst (worker/limits.js, readBurst), then opens a watch: the
    # relay answers it as an opened socket whose one message is the refusal (api.js, refuseWatch).
    $p3 = New-Phone -Dev $M -Sub "100000000000000002104"
    Add-Expected $expected "auth.start|anonymous|ok"; Add-Expected $expected "auth.callback|anonymous|ok"
    $burst = 0
    $limited = $null
    for ($i = 0; $i -lt 80; $i++) {
        $a = Send-To -Url ($O + "/v1/mailboxes/work/p3/items?since=0&max=1") -Cookie $p3.cookie
        if ($a.code -eq 200) { $burst++ } else { $limited = $a; break }
    }
    Add-Expected $expected "items.get|phone|ok" $burst
    Add-Expected $expected "items.get|phone|rate-limited"
    $refusedUp = Get-UpgradeStatus -Origin $O -Path "/v1/mailboxes/work/p3/watch?since=0&max=5&timeoutMs=20000" -Cookie $p3.cookie -PageOrigin $O
    Add-Expected $expected "watch|phone|rate-limited"
    Check ($burst -ge 40 -and $null -ne $limited -and $limited.code -eq 429 -and $refusedUp.Contains("101")) ("the phone's reads run out after its burst (" + $burst + " taken), and its watch is answered as an opened socket (" + $refusedUp + ")")
    $rw = $null
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    do {
        Start-Sleep -Milliseconds 500
        $rw = Get-Summary -Dev $M -Machine $mo -Day $day -Scope "relay"
        $reads++
        $rwc = (Get-RowCounts $rw.json).counts
    } while ($sw.ElapsedMilliseconds -lt 20000 -and (Compare-Counts -Actual $rwc -Expected $expected) -ne "")
    $rwDiff = Compare-Counts -Actual $rwc -Expected $expected
    Check ($rwDiff -ceq "" -and $rwc["watch|phone|rate-limited"] -eq 1) ("A REFUSED WATCH IS COUNTED UNDER ITS CODE: watch|phone|rate-limited 1, and every other row exactly as before (" + $(if ($rwDiff -ne "") { $rwDiff } else { "ok" }) + ")")
    Check ($rwc["watch|phone|ok"] -eq 1) ("TWIN: the phone's watch that opened is still the one ok watch (" + $rwc["watch|phone|ok"] + ")")

    Write-Host ""
    Write-Host "--- who reads what: the relay-wide view only for an owner's machine ---" -ForegroundColor Cyan
    $xr = Get-Summary -Dev $M -Machine $mx -Day $day -Scope "relay"
    Check ($xr.code -eq 403 -and -not $xr.text.Contains("requests")) ("ANOTHER ACCOUNT'S MACHINE IS REFUSED the relay-wide view, 403 (" + $xr.code + ")")
    $xa = Get-Summary -Dev $M -Machine $mx -Day $day -Scope "account"
    $xAcc = @(Get-HordeTestMember $xa.json "accounts")
    $xHash = "" + (Get-HordeTestMember $xa.json "account")
    Check ($xa.code -eq 200 -and $xHash -cmatch '\A[0-9a-f]{16}\z' -and $xAcc.Count -ge 1 -and @($xAcc | Where-Object { ("" + (Get-HordeTestMember $_ "account")) -cne $xHash }).Count -eq 0 -and $null -eq (Get-HordeTestMember $xa.json "requests") -and $null -eq (Get-HordeTestMember $xa.json "own")) ("and reads its own account's hours, and only those (" + $xa.code + ")")
    Check ((@($xAcc | ForEach-Object { [long](Get-HordeTestMember $_ "count") }) | Measure-Object -Sum).Sum -eq 1) "its account made one request the relay counted against it: the registration of its machine"
    $xd = Get-Summary -Dev $M -Machine $mx -Day $day
    Check ($xd.code -eq 200 -and ("" + (Get-HordeTestMember $xd.json "scope")) -ceq "account") "asked as the PC asks - no scope - it is given its own account's view"
    $oa = Get-Summary -Dev $M -Machine $mo -Day $day -Scope "account"
    $oCount = (@(@(Get-HordeTestMember $oa.json "accounts") | ForEach-Object { [long](Get-HordeTestMember $_ "count") }) | Measure-Object -Sum).Sum
    Check ($oa.code -eq 200 -and ("" + (Get-HordeTestMember $oa.json "account")) -cne $xHash -and $oCount -eq 14) ("the owner's machine reads its own account too: fourteen requests of its phone and machine, under another hash (" + $oCount + ")")
    $od = Get-Summary -Dev $M -Machine $mo -Day $day
    Check ($od.code -eq 200 -and ("" + (Get-HordeTestMember $od.json "scope")) -ceq "relay") "and asked with no scope, the owner's machine is given the relay-wide view"
    Check ((Send-To -Url ($O + "/v1/metrics/summary?day=" + $day + "&scope=account") -Cookie $po.cookie).code -eq 403 -and (Send-To -Url ($O + "/v1/metrics/summary?day=" + $day)).code -eq 401) "a phone is refused, even the owner's, and nobody at all is 401"
    Check ((Get-Summary -Dev $M -Machine $mo -Day "2026-02-30").code -eq 400 -and (Get-Summary -Dev $M -Machine $mo -Day $day -Scope "everything").code -eq 400) "a day that is not a date, and a scope that is not one, are refused"
    $reads += 4

    Write-Host ""
    Write-Host "--- the metrics object's own calls are a line of their own ---" -ForegroundColor Cyan
    $own = Get-Summary -Dev $M -Machine $mo -Day $day -Scope "relay"
    $reads++
    $ownRows = @(Get-HordeTestMember $own.json "own")
    $flushes = (@($ownRows | ForEach-Object { [long](Get-HordeTestMember $_ "flushes") }) | Measure-Object -Sum).Sum
    $incs = (@($ownRows | ForEach-Object { [long](Get-HordeTestMember $_ "increments") }) | Measure-Object -Sum).Sum
    $sreads = (@($ownRows | ForEach-Object { [long](Get-HordeTestMember $_ "summaryReads") }) | Measure-Object -Sum).Sum
    $counted = (@($expected.Values) | Measure-Object -Sum).Sum
    Check ($ownRows.Count -ge 1 -and $sreads -eq $reads) ("THE OWN LINE counts every summary read that reached the object: " + $sreads + " of the suite's " + $reads)
    Check ($flushes -eq $incs -and $incs -eq $counted + 2) ("and every flush: with a flush an increment, one for each request counted and one for each watch's end (" + $flushes + " flushes, " + $incs + " increments; " + $counted + " requests + 2 ends)")
    Check (-not (Get-RowCounts $own.json).counts.ContainsKey("other|machine|ok")) "and not one of those calls is among the request rows: the summary reads are the object's own"

    Write-Host ""
    Write-Host "--- the PC's pull: one request a day, and its file ---" -ForegroundColor Cyan
    $pcHome = $mo.home
    $tomorrow = (Get-Date).ToUniversalTime().Date.AddDays(1).AddHours(2)
    $pm = New-HordeRelayRunMetrics -HordeHome $pcHome -Connection $mc
    Check ($pm.on) "the run keeps metrics on a relay that keeps a summary"
    Add-HordeRelayRunMetric -Metrics $pm -Name "polls" -By 5 -At ((Get-Date).ToUniversalTime())
    Add-HordeRelayRunMetric -Metrics $pm -Name "emptyPolls" -By 4 -At ((Get-Date).ToUniversalTime())
    Add-HordeRelayRunMetric -Metrics $pm -Name "backoffMs" -By 1500 -At ((Get-Date).ToUniversalTime())
    $before = $sreads
    $first = Invoke-HordeRelayRunMetricsDay -Metrics $pm -Connection $mc -Now $tomorrow
    $second = Invoke-HordeRelayRunMetricsDay -Metrics $pm -Connection $mc -Now $tomorrow.AddHours(5)
    $restart = Invoke-HordeRelayRunMetricsDay -Metrics (New-HordeRelayRunMetrics -HordeHome $pcHome -Connection $mc) -Connection $mc -Now $tomorrow.AddHours(6)
    $after = Get-Summary -Dev $M -Machine $mo -Day $day -Scope "relay"
    $reads++
    $sreadsAfter = (@(@(Get-HordeTestMember $after.json "own") | ForEach-Object { [long](Get-HordeTestMember $_ "summaryReads") }) | Measure-Object -Sum).Sum
    Check ($null -ne $first -and $first.state -ceq "known" -and $null -eq $second -and $null -eq $restart -and $sreadsAfter - $before -eq 2) ("THE PC'S PULL MAKES ONE REQUEST A DAY: three calls on one day - one of them a restarted run - asked the relay once (" + ($sreadsAfter - $before - 1) + " pull request(s), and this check's own read)")
    $file = Join-Path $pcHome ("metrics\relay-" + $day + ".json")
    $bytes = $(if (Test-Path -LiteralPath $file) { [System.IO.File]::ReadAllBytes($file) } else { New-Object byte[] 0 })
    $j = $null
    try { $j = [System.Text.Encoding]::ASCII.GetString($bytes) | ConvertFrom-Json } catch { $j = $null }
    $pcHours = @(Get-HordeTestMember $j "pc.hours")
    Check ($bytes.Length -gt 0 -and @($bytes | Where-Object { $_ -gt 0x7E -or ($_ -lt 0x20 -and $_ -ne 0x0A -and $_ -ne 0x0D) }).Count -eq 0 -and $null -ne $first -and $first.path -ceq $file) ("it wrote <HORDE_HOME>\metrics\relay-" + $day + ".json, in printable ASCII (" + $bytes.Length + " bytes)")
    Check (("" + (Get-HordeTestMember $j "day")) -ceq $day -and ("" + (Get-HordeTestMember $j "relay.state")) -ceq "known" -and ("" + (Get-HordeTestMember $j "relay.summary.scope")) -ceq "relay" -and @(Get-HordeTestMember $j "relay.summary.requests").Count -gt 5) "holding the relay's summary of that day as the relay gave it"
    Check ($pcHours.Count -eq 1 -and [long](Get-HordeTestMember $pcHours[0] "polls") -eq 5 -and [long](Get-HordeTestMember $pcHours[0] "emptyPolls") -eq 4 -and [long](Get-HordeTestMember $pcHours[0] "backoffMs") -eq 1500 -and -not (Test-Path -LiteralPath (Join-Path $pcHome ("metrics\pc-" + $day + ".json")))) ("and this PC's own counts of the day beside it, their own file folded in (" + ($pcHours | ConvertTo-Json -Compress) + ")")
    $next = Invoke-HordeRelayRunMetricsDay -Metrics $pm -Connection $mc -Now $tomorrow.AddDays(1)
    $again = Get-Summary -Dev $M -Machine $mo -Day $day -Scope "relay"
    $sreadsNext = (@(@(Get-HordeTestMember $again.json "own") | ForEach-Object { [long](Get-HordeTestMember $_ "summaryReads") }) | Measure-Object -Sum).Sum
    Check ($null -ne $next -and $next.day -ceq $tomorrow.ToString("yyyy-MM-dd") -and $sreadsNext - $sreadsAfter -eq 2) ("CONTROL: the next day asks again, once, for its own yesterday (" + $(if ($null -ne $next) { $next.day } else { "nothing" }) + ")")
    try { $mc.state.http.Dispose() } catch { }
    Stop-Dev -Dev $M

    Write-Host ""
    Write-Host "--- 3. a metrics object that refuses every flush costs no user anything ---" -ForegroundColor Cyan
    $F = Start-Dev -Name "failing" -Metrics '{"flushCount":1,"failFlush":1,"summaryEveryMs":1}' -More $owners
    $O = $F.origin
    $fp = New-Phone -Dev $F -Sub $ownerSub
    $fm = New-Machine -Dev $F -Cookie $fp.cookie -Label "fail-box"
    $codes = New-Object System.Collections.ArrayList
    $slowest = 0
    for ($i = 1; $i -le 10; $i++) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        [void]$codes.Add((Send-To -Url ($O + "/v1/mailboxes/work/f/items") -Method "POST" -Body ('{"key":"f-' + $i + '","text":"t"}') -Cookie $fp.cookie -Origin $O).code)
        [void]$codes.Add((Send-To -Url ($O + "/v1/mailboxes/work/f/items?since=0&max=20") -Cookie $fp.cookie).code)
        $slowest = [Math]::Max($slowest, $sw.ElapsedMilliseconds)
    }
    $fread = Get-Json (Send-To -Url ($O + "/v1/mailboxes/work/f/items?since=0&max=20") -Cookie $fp.cookie)
    Check ($fp.session -ne "" -and $fm.reg.code -eq 200 -and (@($codes | Sort-Object -Unique) -join ",") -ceq "200" -and @(Get-HordeTestMember $fread "items").Count -eq 10) ("A FAILING METRICS OBJECT NEVER FAILS A USER'S REQUEST: sign-in, pairing, ten puts and ten reads, every one answered and every item kept (" + (@($codes | Group-Object | ForEach-Object { $_.Name + " x" + $_.Count }) -join ", ") + ")")
    Check ($slowest -lt 3000) ("nor slows one: the slowest put and read together took " + $slowest + " ms on a local dev")
    # AN OWNER BY EMAIL (PR 281's pins): the first account whose verified email is an owner's is pinned to
    # it by its first counted request - a summary call is one - and reads the relay-wide view; a second
    # account with the same email is not that owner.
    $ep = New-Phone -Dev $F -Sub "100000000000000002103" -Email $ownerEmail
    $em = New-Machine -Dev $F -Cookie $ep.cookie -Label "email-box"
    $first = Get-Summary -Dev $F -Machine $em -Day $day -Scope "relay"
    $asPc = Get-Summary -Dev $F -Machine $em -Day $day
    $ep2 = New-Phone -Dev $F -Sub "100000000000000002105" -Email $ownerEmail
    $em2 = New-Machine -Dev $F -Cookie $ep2.cookie -Label "email-box-2"
    $second = Get-Summary -Dev $F -Machine $em2 -Day $day -Scope "relay"
    $secondPc = Get-Summary -Dev $F -Machine $em2 -Day $day
    Check ($ep.session -ne "" -and $em.reg.code -eq 200 -and $first.code -eq 200 -and ("" + (Get-HordeTestMember $first.json "scope")) -ceq "relay" -and ("" + (Get-HordeTestMember $asPc.json "scope")) -ceq "relay") ("AN OWNER BY EMAIL: the first account with the owner's email is pinned to it by its first request, and its machine reads the relay-wide view, by name or as the PC asks (" + $first.code + ")")
    Check ($ep2.session -ne "" -and $em2.reg.code -eq 200 -and $second.code -eq 403 -and ("" + (Get-HordeTestMember $secondPc.json "scope")) -ceq "account") ("and a second account with the same email is not that owner: refused the relay-wide view, given its own (" + $second.code + ")")
    $fs = Get-Summary -Dev $F -Machine $fm -Day $day -Scope "relay"
    Check ($fs.code -eq 200 -and @(Get-HordeTestMember $fs.json "requests").Count -eq 0 -and ((@(@(Get-HordeTestMember $fs.json "own") | ForEach-Object { [long](Get-HordeTestMember $_ "flushes") }) | Measure-Object -Sum).Sum) -eq 0) "CONTROL: the object really refused them all: it holds no row and counted no flush"
    Stop-Dev -Dev $F

    Write-Host ""
    Write-Host "--- 4. metrics' own calls move no budget; a summary call is counted, and braked ---" -ForegroundColor Cyan
    # A relay's day of 6 (one held back for the owner, leased one at a time) and an account's day of 6; the
    # brake a minute. The owner's phone makes 2 mailbox requests; its machine asks for 3 summaries AT
    # ONCE - one passes the brake and is counted, two are refused unasked; another account's machine is
    # refused the relay-wide view (counted: it passed the gate) and then braked. A flush on every request
    # besides. That is 4 of the day: the owner then takes exactly 2 more. Were summary calls free it would
    # be 4; were the flushes counted, fewer.
    $B = Start-Dev -Name "budget" -Limits '{"requestsPerDay":6,"relayRequestsPerDay":6,"relayOwnerReserve":1,"relayRequestLease":1}' -Metrics '{"flushCount":1,"summaryEveryMs":60000}' -More $owners
    $O = $B.origin
    $bp = New-Phone -Dev $B -Sub $ownerSub
    $bm = New-Machine -Dev $B -Cookie $bp.cookie -Label "budget-box"
    $bx = New-Phone -Dev $B -Sub "100000000000000002106"
    $bxm = New-Machine -Dev $B -Cookie $bx.cookie -Label "public-box"
    $read = { Send-To -Url ($O + "/v1/mailboxes/work/b/items?since=0&max=1") -Cookie $bp.cookie }
    $two = @(1, 2 | ForEach-Object { (& $read).code })
    # THREE CALLS IN PARALLEL, each signed on its own.
    $target = "/v1/metrics/summary?day=" + $day + "&scope=relay"
    $pending = New-Object System.Collections.ArrayList
    $reqs = New-Object System.Collections.ArrayList
    foreach ($k in 1, 2, 3) {
        $auth = New-HordeCloudflareRelayMachineAuthorization -Key $bm.signer.key -KeyId $bm.signer.keyId -Origin $O -Method "GET" -Target $target -Body (New-Object byte[] 0)
        $rq = New-Object System.Net.Http.HttpRequestMessage((New-Object System.Net.Http.HttpMethod("GET")), ($O + $target))
        [void]$rq.Headers.TryAddWithoutValidation("Authorization", $auth)
        [void]$reqs.Add($rq)
    }
    foreach ($rq in $reqs) { [void]$pending.Add($http.SendAsync($rq)) }
    $par = @($pending | ForEach-Object { $r = $_.GetAwaiter().GetResult(); try { [pscustomobject]@{ code = [int]$r.StatusCode; text = $r.Content.ReadAsStringAsync().GetAwaiter().GetResult() } } finally { $r.Dispose() } })
    foreach ($rq in $reqs) { $rq.Dispose() }
    $parCodes = @($par | ForEach-Object { $_.code } | Sort-Object)
    Check ((@($two) -join ",") -ceq "200,200" -and ($parCodes -join ",") -ceq "200,429,429" -and @($par | Where-Object { $_.code -eq 429 -and $_.text.Contains("rate-limited") }).Count -eq 2) ("THE BRAKE: of three summary calls at once, exactly one passes; the other two are refused, rate-limited (" + ($parCodes -join ",") + ")")
    $xRefused = Get-Summary -Dev $B -Machine $bxm -Day $day -Scope "relay"
    $xNext = Get-Summary -Dev $B -Machine $bxm -Day $day -Scope "account"
    Check ($xRefused.code -eq 403 -and $xNext.code -eq 429) ("a REFUSED call brakes the next as an answered one does: 403, then 429 (" + $xRefused.code + "," + $xNext.code + ")")
    Start-Sleep -Milliseconds 1500
    $rest = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt 8; $i++) { $c = & $read; [void]$rest.Add($c); if ($c.code -ne 200) { break } }
    $taken = @($rest | Where-Object { $_.code -eq 200 }).Count
    $last = @($rest)[-1]
    Check ($taken -eq 2 -and $last.code -eq 429 -and $last.text.Contains("relay-daily-limit")) ("THE BUDGET MOVES FOR A SUMMARY CALL AND FOR NOTHING ELSE OF METRICS: of the relay's day of six, 2 reads, 1 summary and 1 refused summary leave exactly 2, then relay-daily-limit - free summaries would have left 4, counted flushes fewer (" + (@($rest | ForEach-Object { $_.code }) -join ",") + ")")
    Stop-Dev -Dev $B
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
    if ($work -like "*horde-cf-metrics-*" -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
Check (-not (Test-Path -LiteralPath $work)) "the suite's folder is gone"

Complete-HordeSuite -Success "every request is counted exactly, by fixed words only and nothing a request carried, at no cost to any user or budget; the relay-wide view is an owner's machine's alone; and the PC fetches it once a day"
