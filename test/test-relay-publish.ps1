# DOES THE SUPERVISOR KEEP THE HOSTED PHONE PAGE CURRENT - DEPLOYING ONLY WHAT IT MAY, CHECKING IT, AND
# TELLING ONCE?
#
# cli/RelayPublish.ps1 (the pass's step), and the lock and the record of cli/RelayDeploy.ps1, which a
# deploy by hand and the supervisor's own share.
#
# NOTHING IS DEPLOYED, FETCHED OR TOLD FOR REAL (CONTRIBUTING 9):
#   - THE STEP runs on tools this suite makes: a commit that is a name in a table, a diff that is a
#     list, a deploy that writes the record a real one would and changes a table of answers, and an
#     HTTP that reads that table. The real tools are made once, only to show the deploy refuses a
#     test's home - pointed at a folder of this suite's that holds no relay, so it cannot reach one.
#   - THE DEPLOY'S LOCK AND RECORD run through the real Invoke-HordeRelayDeploy, on a relay of this
#     suite's own registered from its temp folder, whose deploy only counts its calls. No relay of the
#     repository is loaded.
#   - EVERY HOME is under the temp folder, and the teller is a block that records what it was handed.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "Home", "ModuleSettings", "Heartbeat", "Services", "ServicesFiles", "ServiceHostPort", "Schedule")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
foreach ($f in @("ServicesAct", "ServicesTend", "ServicesTell")) { . (Join-Path $root ("cli\" + $f + ".ps1")) }
. (Join-Path $root "relays\Port.ps1")
. (Join-Path $root "cli\RelayDeploy.ps1")
. (Join-Path $root "cli\RelayPublish.ps1")

$work = Join-Path $env:TEMP ("horde-relay-publish-" + [guid]::NewGuid().ToString("N"))
[void][System.IO.Directory]::CreateDirectory($work)
$t0 = [datetime]::new(2026, 10, 14, 12, 0, 0, [System.DateTimeKind]::Utc)
$cA = "a" * 40; $cB = "b" * 40; $cC = "c" * 40
$origin = "https://zorbrelay.example"
$v1 = "1111111111111111"; $v2 = "2222222222222222"

function New-Home { param([string]$Name) $h = Join-Path $work $Name; [void][System.IO.Directory]::CreateDirectory($h); return $h }
function Sw { param([string]$Version) return [pscustomobject]@{ status = 200; body = ("// the worker`nconst VERSION = `"" + $Version + "`";`nconst SHELL = [];`n") } }

# THE WORLD the stand-in tools act on. A deploy that works writes the record, as the real one does,
# and makes the page serve what it built; every tool records its call.
function New-World {
    param([string]$HordeHome)
    return @{ home = $HordeHome; now = $t0; head = $cB; clean = $true; headOk = $true; diffs = @{}; diffOk = $true
        deploy = "ok"; built = $v2; serveAfter = $null; deploys = 0; calls = (New-Object System.Collections.ArrayList)
        http = @{ ($origin + "/app/sw.js") = (Sw $v1) }; changedAnswer = 200
        told = (New-Object System.Collections.ArrayList); tellCalls = 0 }
}
function New-Tools {
    return @{
        Now     = { return $W.now }
        NewId   = { return [guid]::NewGuid().ToString() }
        Head    = { param($Checkout) [void]$W.calls.Add("head"); if (-not $W.headOk) { return (New-HordeUnknown -Reason "no revision tool") }; return (New-HordeKnown -Value ([pscustomobject]@{ commit = $W.head; clean = $W.clean })) }
        Diff    = {
            param($Checkout, $Base, $Head)
            [void]$W.calls.Add("diff " + $Base.Substring(0, 1) + ".." + $Head.Substring(0, 1))
            if (-not $W.diffOk -or -not $W.diffs.ContainsKey($Base + ".." + $Head)) { return (New-HordeUnknown -Reason "bad revision") }
            return (New-HordeKnown -Value ([pscustomobject]@{ paths = [string[]]@($W.diffs[$Base + ".." + $Head]) }))
        }
        Deploy  = {
            param($HordeHome, $Say, $Checkout)
            $W.deploys++; [void]$W.calls.Add("deploy")
            & $Say "a line the deploy said"
            if ($W.deploy -ceq "busy") { return (New-HordeUnknown -Reason (Get-HordeRelayDeployBusyReason)) }
            if ($W.deploy -ceq "fail") { return (New-HordeUnknown -Reason "a secret could not be stored: not logged in") }
            Write-HordeRelayDeployed -HordeHome $HordeHome -Revision ([pscustomobject]@{ commit = $W.head; clean = $true }) -Version $W.built -Relay "zorbrelay" -Origin $origin -At $W.now
            $W.http[$origin + "/app/sw.js"] = (Sw $(if ($null -ne $W.serveAfter) { $W.serveAfter } else { $W.built }))
            return (New-HordeKnown -Value ([pscustomobject]@{ relay = "zorbrelay"; origin = $origin; version = $W.built }))
        }
        Http    = {
            param($Url)
            [void]$W.calls.Add("http " + $Url.Substring($origin.Length))
            if ($W.http.ContainsKey($Url)) { return (New-HordeKnown -Value $W.http[$Url]) }
            return (New-HordeKnown -Value ([pscustomobject]@{ status = $W.changedAnswer; body = "" }))
        }
        SiteMap = { return (Get-HordeRelayDeploySiteSources) }
    }
}
$teller = { param($Notices, $HordeHome, $Policy) $W.tellCalls++; foreach ($n in @($Notices)) { [void]$W.told.Add($n) }; return [pscustomobject]@{ told = @(@($Notices) | ForEach-Object { $_.id }); problem = "" } }
$policyOn = [pscustomobject]@{ tellWarchief = $true }

function Pass { param([hashtable]$Tools = $null, $Policy = $policyOn) if ($null -eq $Tools) { $Tools = New-Tools }; return @(Invoke-HordeRelayPublishStep -HordeHome $W.home -Tools $Tools -Policy $Policy -Teller $teller -Checkout $work) }
function Seed { param([string]$Commit = $cA, [bool]$Clean = $true) Write-HordeRelayDeployed -HordeHome $W.home -Revision ([pscustomobject]@{ commit = $Commit; clean = $Clean }) -Version $v1 -Relay "zorbrelay" -Origin $origin -At $t0.AddDays(-1) }
function Whats { return (@($W.told | ForEach-Object { $_.what }) -join ",") }
function Says { param($Lines, [string]$Text) return [bool](@($Lines | Where-Object { "" + $_ -like ("*" + $Text + "*") }).Count -gt 0) }
function Show { param($Lines) foreach ($l in @($Lines)) { Write-Host ("         said: " + $l) -ForegroundColor DarkYellow } }

try {
    Write-Host ""
    Write-Host "--- the classes: the page, the relay, and everything else ---" -ForegroundColor Cyan
    $c = Get-HordeRelayPublishClasses -Paths @("surfaces/pwa/page/app.js", "relay/js/protocol.js", "relays/zorbrelay/worker/site.js", "relays/zorbrelay/deploy-config.json", "relay/Envelope.ps1", "core/Services.ps1", "surfaces/pwa-other/x.js", "Surfaces/pwa/page/app.js")
    Check ((@($c.page) -join ",") -ceq "surfaces/pwa/page/app.js,relay/js/protocol.js") ("only surfaces/pwa/** and relay/js/** are the page (" + (@($c.page) -join ",") + ")")
    Check ((@($c.relay) -join ",") -ceq "relays/zorbrelay/worker/site.js,relays/zorbrelay/deploy-config.json") "a relay's worker and its deploy config are the relay"
    Check ((@($c.other) -join ",") -ceq "relay/Envelope.ps1,core/Services.ps1,surfaces/pwa-other/x.js,Surfaces/pwa/page/app.js") "the machine side of relay/, core, a look-alike folder and another case are none of the page"

    Write-Host ""
    Write-Host "--- a page-only change is deployed, checked and told once ---" -ForegroundColor Cyan
    $W = New-World (New-Home "page-only"); Seed
    $W.diffs[$cA + ".." + $cB] = @("surfaces/pwa/page/app.js", "surfaces/pwa/test/test-pwa-site.ps1")
    $l = Pass
    Check ($W.deploys -eq 1) "the page was deployed"
    Check (Says $l "DEPLOYED bbbbbbb and checked") "the pass says it deployed and checked it"
    if (-not (Says $l "DEPLOYED")) { Show $l }
    Check ($W.calls -ccontains "http /app/sw.js") "the service worker was asked for, at the origin the deploy answered with"
    Check ($W.calls -ccontains "http /app/app.js") "the changed file the site serves was asked for"
    Check (@($W.calls | Where-Object { $_ -like "http *test-pwa-site*" }).Count -eq 0) "a changed file the site does not serve is not asked for"
    $rec = Read-HordeRelayDeployed -HordeHome $W.home
    Check ($rec.state -ceq "known" -and $rec.value.commit -ceq $cB) "the record names the commit deployed"
    Check ((Whats) -ceq "deployed") ("the warchief was told once, that it was deployed (" + (Whats) + ")")
    $l = Pass; $null = Pass
    Check ($W.deploys -eq 1 -and $W.told.Count -eq 1 -and $W.tellCalls -eq 1) "later passes neither deploy again nor tell again"
    Check (Says $l "current") "a later pass says the page is current"
    $logText = [System.IO.File]::ReadAllText((Get-HordeRelayPublishLogPath -HordeHome $W.home))
    Check ($logText.Contains("deploying bbbbbbb") -and $logText.Contains("a line the deploy said") -and $logText.Contains("DEPLOYED bbbbbbb")) "the deploy is logged, with every line the deploy said"
    $body = Format-HordeServiceNoticeBody -Notice $W.told[0]
    Check ($body.StartsWith("HORDE SERVICES - phone page`n") -and $body.Contains("deployed the phone page and checked it") -and $body.Contains("(commit bbbbbbb)")) "the notice says it was deployed, in fixed words, with the commit"
    Check (-not $body.Contains("needs attention")) "news that it was deployed does not say it needs attention"

    Write-Host ""
    Write-Host "--- a worker change is not deployed and is warned once ---" -ForegroundColor Cyan
    $W = New-World (New-Home "worker"); Seed
    $W.diffs[$cA + ".." + $cB] = @("surfaces/pwa/page/app.js", "relays/zorbrelay/worker/site.js")
    $l = Pass; $null = Pass
    Check ($W.deploys -eq 0) "nothing was deployed"
    Check ((Whats) -ceq "relay-changed") ("the warchief was told once that the relay changed (" + (Whats) + ")")
    Check (Says $l "the relay changed") "the pass says why"
    $body = Format-HordeServiceNoticeBody -Notice $W.told[0]
    Check ($body.Contains("needs attention") -and $body.Contains("horde relay deploy") -and -not $body.Contains("zorbrelay")) "the warning says what a person does, and nothing from the change itself"
    $W.head = $cC; $W.diffs[$cA + ".." + $cC] = @("surfaces/pwa/page/app.js", "relays/zorbrelay/worker/site.js", "relays/zorbrelay/worker/more.js")
    $null = Pass
    Check ($W.told.Count -eq 1) "a later merge with the same mix of changes is not told again"
    $W = New-World (New-Home "relay-config-only"); Seed; $W.diffs[$cA + ".." + $cB] = @("relays/zorbrelay/deploy-config.json")
    $null = Pass
    Check ($W.deploys -eq 0 -and (Whats) -ceq "relay-changed") "a change to the relay's deploy config alone is not deployed either"

    Write-Host ""
    Write-Host "--- a change outside both is warned, not deployed ---" -ForegroundColor Cyan
    $W = New-World (New-Home "other"); Seed
    $W.diffs[$cA + ".." + $cB] = @("surfaces/pwa/page/app.js", "core/Services.ps1")
    $l = Pass; $null = Pass
    Check ($W.deploys -eq 0) "nothing was deployed"
    Check ((Whats) -ceq "other-changed") ("the warchief was told once that files beyond the page changed (" + (Whats) + ")")
    $W = New-World (New-Home "other-only"); Seed; $W.diffs[$cA + ".." + $cB] = @("decisions/page/list.js")
    $null = Pass
    Check ($W.deploys -eq 0 -and (Whats) -ceq "other-changed") "a file the site serves from outside the two page folders is not the page: warned, not deployed"

    Write-Host ""
    Write-Host "--- no change does nothing ---" -ForegroundColor Cyan
    $W = New-World (New-Home "same"); Seed -Commit $cB
    $l = Pass
    Check ($W.deploys -eq 0 -and $W.told.Count -eq 0 -and @($W.calls | Where-Object { $_ -like "diff*" -or $_ -like "http*" }).Count -eq 0) "the checkout on the deployed commit: no diff, no request, no deploy, nobody told"
    Check (Says $l "current") "it says the page is current"
    $W = New-World (New-Home "empty-diff"); Seed; $W.diffs[$cA + ".." + $cB] = @()
    $null = Pass
    Check ($W.deploys -eq 0 -and $W.told.Count -eq 0) "commits that change no file: nothing done, nobody told"

    Write-Host ""
    Write-Host "--- a failed deploy warns once and is retried no sooner than an hour ---" -ForegroundColor Cyan
    $W = New-World (New-Home "failed"); Seed; $W.deploy = "fail"
    $W.diffs[$cA + ".." + $cB] = @("surfaces/pwa/page/app.js")
    $l = Pass
    Check ($W.deploys -eq 1 -and (Whats) -ceq "deploy-failed") ("the failed deploy is told (" + (Whats) + ")")
    Check (Says $l "FAILED") "the pass says it failed"
    Check ((Read-HordeRelayDeployed -HordeHome $W.home).value.commit -ceq $cA) "a failed deploy changes no record"
    $W.now = $t0.AddMinutes(30); $l = Pass
    Check ($W.deploys -eq 1) "half an hour later it is not tried again"
    Check (Says $l "waits") "the pass says it waits"
    $W.head = $cC; $W.diffs[$cA + ".." + $cC] = @("surfaces/pwa/page/app.js"); $W.now = $t0.AddMinutes(59); $null = Pass
    Check ($W.deploys -eq 1) "a newer commit within the hour waits as well: at most one try an hour"
    $W.head = $cB; $W.now = $t0.AddMinutes(61); $null = Pass
    Check ($W.deploys -eq 2) "an hour later it is tried again"
    Check ($W.told.Count -eq 1) "and the same failure is not told again"
    $W.deploy = "ok"; $W.now = $t0.AddMinutes(122); $null = Pass
    Check ($W.deploys -eq 3 -and (Whats) -ceq "deploy-failed,deployed") ("once it works, that is told (" + (Whats) + ")")
    $st = Read-HordeRelayPublishState -HordeHome $W.home
    Check ($st.state -ceq "known" -and $null -eq $st.value.failure) "and the failure is settled"

    Write-Host ""
    Write-Host "--- a deploy whose sw VERSION did not change is a failed check ---" -ForegroundColor Cyan
    $W = New-World (New-Home "same-version"); Seed; $W.built = $v1
    $W.diffs[$cA + ".." + $cB] = @("surfaces/pwa/page/app.js")
    $l = Pass
    Check ($W.deploys -eq 1 -and (Whats) -ceq "check-failed") ("a deploy that left VERSION as it was is a failed check (" + (Whats) + ")")
    Check (Says $l "did not change") "the pass says the VERSION did not change"
    if (-not (Says $l "did not change")) { Show $l }
    $W.now = $t0.AddMinutes(61); $null = Pass
    Check ($W.deploys -eq 2) "it is tried again from the base it failed from, though the record already names the commit"
    Check ($W.calls -ccontains "diff a..b") "the retry compares with the base before the failed check"
    $W = New-World (New-Home "stale"); Seed; $W.serveAfter = $v1
    $W.diffs[$cA + ".." + $cB] = @("surfaces/pwa/page/app.js")
    $l = Pass
    Check ((Whats) -ceq "check-failed" -and (Says $l "not the 2222222222222222 the deploy built")) "a page still serving the old VERSION after the deploy is a failed check"
    $hand = New-World (New-Home "hand-settles"); $W = $hand; Seed; $W.built = $v1
    $W.diffs[$cA + ".." + $cB] = @("surfaces/pwa/page/app.js")
    $null = Pass
    Write-HordeRelayDeployed -HordeHome $W.home -Revision ([pscustomobject]@{ commit = $cB; clean = $true }) -Version $v2 -Relay "zorbrelay" -Origin $origin -At $t0.AddMinutes(10)
    $W.now = $t0.AddMinutes(70); $l = Pass
    Check ($W.deploys -eq 1 -and (Says $l "settled")) "a deploy by hand after the failure settles it: no retry"

    Write-Host ""
    Write-Host "--- a new file answering 404 is a failed check ---" -ForegroundColor Cyan
    $W = New-World (New-Home "404"); Seed; $W.changedAnswer = 404
    $W.diffs[$cA + ".." + $cB] = @("surfaces/pwa/page/lane-card.js", "surfaces/pwa/page/app.js")
    $l = Pass
    Check ($W.deploys -eq 1 -and (Whats) -ceq "check-failed") ("a changed file the site serves that answers 404 fails the check (" + (Whats) + ")")
    Check (Says $l "app/app.js did not answer 200 (it answered 404)") "the pass names the file"
    if (-not (Says $l "answered 404")) { Show $l }

    Write-Host ""
    Write-Host "--- the check, alone ---" -ForegroundColor Cyan
    $ok = New-HordeKnown -Value ([pscustomobject]@{ status = 200; body = "" })
    Check ((Test-HordeRelayPublishCheck -Before $v1 -Built $v2 -After (New-HordeKnown -Value (Sw $v2)) -Files @([pscustomobject]@{ path = "app/app.js"; answer = $ok })).ok) "CONTROL: a new VERSION, the built one, and every file 200 pass"
    Check ((Test-HordeRelayPublishCheck -Before "" -Built $v2 -After (New-HordeKnown -Value (Sw $v2))).ok) "with the VERSION before unknown, the built one being served passes"
    Check (-not (Test-HordeRelayPublishCheck -Before $v1 -Built $v1 -After (New-HordeKnown -Value (Sw $v1))).ok) "the VERSION unchanged fails"
    Check (-not (Test-HordeRelayPublishCheck -Before $v1 -Built $v2 -After (New-HordeKnown -Value ([pscustomobject]@{ status = 404; body = "" }))).ok) "a worker that does not answer 200 fails"
    Check (-not (Test-HordeRelayPublishCheck -Before $v1 -Built $v2 -After (New-HordeUnknown -Reason "timed out")).ok) "a worker that does not answer at all fails"
    Check (-not (Test-HordeRelayPublishCheck -Before $v1 -Built $v2 -After (New-HordeKnown -Value (Sw $v2)) -Files @([pscustomobject]@{ path = "app/x.js"; answer = (New-HordeUnknown -Reason "timed out") })).ok) "a changed file that does not answer fails"
    $served = @(Get-HordeRelayPublishServed -Changed @("surfaces/pwa/page/app.js", "relay/js/protocol.js", "surfaces/pwa/Site.ps1") -SiteMap (Get-HordeRelayDeploySiteSources))
    Check (($served -join ",") -ceq "app/app.js,relay/protocol.js") ("the files asked for are the changed ones the site serves, at their site paths (" + ($served -join ",") + ")")

    Write-Host ""
    Write-Host "--- the first run with no record warns and does not deploy ---" -ForegroundColor Cyan
    # CHOSEN: no seeding from the live VERSION. It is a hash of built files, not a commit (header).
    $W = New-World (New-Home "first-run")
    $l = Pass; $null = Pass
    Check ($W.deploys -eq 0 -and @($W.calls | Where-Object { $_ -like "diff*" }).Count -eq 0) "nothing is compared and nothing deployed"
    Check ((Whats) -ceq "no-record") ("the warchief is told once that a deploy by hand records it (" + (Whats) + ")")
    $W = New-World (New-Home "unclean-record"); Seed -Clean $false; $W.diffs[$cA + ".." + $cB] = @("surfaces/pwa/page/app.js")
    $null = Pass
    Check ($W.deploys -eq 0 -and (Whats) -ceq "no-record") "a record made from a checkout with changes of its own is no base: warned, not deployed"
    $W = New-World (New-Home "bad-record"); [void][System.IO.Directory]::CreateDirectory((Get-HordeRelayDeployFolder -HordeHome $W.home))
    [System.IO.File]::WriteAllText((Get-HordeRelayDeployedPath -HordeHome $W.home), "{ not json")
    $null = Pass
    Check ($W.deploys -eq 0 -and (Whats) -ceq "no-record") "a record that cannot be read is no base: warned, not deployed"

    Write-Host ""
    Write-Host "--- everything else that is unknown is not a deploy ---" -ForegroundColor Cyan
    $W = New-World (New-Home "dirty"); Seed; $W.clean = $false; $W.diffs[$cA + ".." + $cB] = @("surfaces/pwa/page/app.js")
    $null = Pass; $null = Pass
    Check ($W.deploys -eq 0 -and (Whats) -ceq "dirty") "a checkout with changes of its own is not deployed, and that is told once"
    $W = New-World (New-Home "no-diff"); Seed; $W.diffOk = $false
    $null = Pass; $null = Pass
    Check ($W.deploys -eq 0 -and (Whats) -ceq "unreadable") "a diff that cannot be read is not deployed, and that is told once"
    $W = New-World (New-Home "no-head"); Seed; $W.headOk = $false
    $null = Pass
    Check ($W.deploys -eq 0 -and (Whats) -ceq "unreadable") "a commit that cannot be read is not deployed"
    $W = New-World (New-Home "interrupted"); Seed
    $W.diffs[$cA + ".." + $cB] = @("surfaces/pwa/page/app.js")
    $s0 = New-HordeRelayPublishState; $s0.attempt = [pscustomobject]@{ head = $cB; base = $cA; at = $t0.AddMinutes(-5) }
    Write-HordeRelayPublishState -State $s0 -HordeHome $W.home
    $l = Pass
    Check ($W.deploys -eq 0 -and (Whats) -ceq "deploy-failed") "a deploy a pass was ended in the middle of is counted as failed, told, and not tried again at once"
    Check (Says $l "never finished") "the pass says so"
    $W = New-World (New-Home "corrupt-state"); Seed
    [System.IO.File]::WriteAllText((Get-HordeRelayPublishStatePath -HordeHome $W.home), "{ nope")
    $l = Pass
    Check ($W.deploys -eq 0 -and (Says $l "LEFT ALONE")) "a state that cannot be read is never begun again as new"

    Write-Host ""
    Write-Host "--- telling ---" -ForegroundColor Cyan
    $W = New-World (New-Home "tell-off")
    $l = Pass -Policy ([pscustomobject]@{ tellWarchief = $false })
    Check ($W.tellCalls -eq 0 -and (Says $l "telling is switched off")) "with telling switched off nobody is told, and the pass says so"
    Check (@((Read-HordeRelayPublishState -HordeHome $W.home).value.pending).Count -eq 1) "the notice waits"
    $null = Pass
    Check ($W.tellCalls -eq 1 -and $W.told.Count -eq 1) "the next pass that may tell tells it, once"

    Write-Host ""
    Write-Host "--- the lock stops a second deploy ---" -ForegroundColor Cyan
    # A relay of this suite's own, in its temp folder, whose deploy counts its calls.
    $fakeRelay = Join-Path $work "zorbrelay"
    [void][System.IO.Directory]::CreateDirectory($fakeRelay)
    $caps = [System.IO.File]::ReadAllText((Join-Path $root "relays\local\capabilities.json")).Replace('"relay": "local"', '"relay": "zorbrelay"')
    [System.IO.File]::WriteAllText((Join-Path $fakeRelay "capabilities.json"), $caps)
    $script:relayDeploys = 0; $script:relayAnswer = "ok"
    $none = { param($State) return (New-HordeUnknown -Reason "not used here") }
    $null = Register-HordeRelay -Folder $fakeRelay -Connect $none -Put $none -Get $none -Watch $none -Ack $none -Deploy {
        param($Site, $Say, $HordeHome)
        $script:relayDeploys++
        if ($script:relayAnswer -ceq "fail") { return (New-HordeUnknown -Reason "not logged in") }
        return (New-HordeKnown -Value ([pscustomobject]@{ origin = "https://zorbrelay.example" }))
    }
    $hh = New-Home "lock"
    $held = Enter-HordeRelayDeployLock -HordeHome $hh
    try {
        Check ($null -ne $held) "CONTROL: the lock can be taken"
        Check ($null -eq (Enter-HordeRelayDeployLock -HordeHome $hh)) "a second taker is refused while it is held"
        $a = Invoke-HordeRelayDeploy -Relay "zorbrelay" -HordeHome $hh -Revision ([pscustomobject]@{ commit = $cC; clean = $true })
        Check ($a.state -ceq "unknown" -and $a.reason -ceq (Get-HordeRelayDeployBusyReason)) "a deploy while another holds the lock is refused as busy"
        Check ($script:relayDeploys -eq 0) "and the relay's deploy was never called"
        Check (-not [System.IO.File]::Exists((Get-HordeRelayDeployedPath -HordeHome $hh))) "and nothing was recorded"
    } finally { if ($null -ne $held) { $held.Dispose() } }
    $a = Invoke-HordeRelayDeploy -Relay "zorbrelay" -HordeHome $hh -Revision ([pscustomobject]@{ commit = $cC; clean = $true })
    Check ($a.state -ceq "known" -and $script:relayDeploys -eq 1) "CONTROL: with the lock let go, the deploy runs"
    Check ($null -ne ($again = Enter-HordeRelayDeployLock -HordeHome $hh)) "a deploy lets go of the lock when it ends"
    if ($null -ne $again) { $again.Dispose() }
    $W = New-World (New-Home "busy-step"); Seed; $W.deploy = "busy"; $W.diffs[$cA + ".." + $cB] = @("surfaces/pwa/page/app.js")
    $l = Pass
    Check ($W.deploys -eq 1 -and $W.told.Count -eq 0 -and (Says $l "another deploy is running")) "a pass that finds a deploy running tells nobody and counts no failure"
    $W.deploy = "ok"; $W.now = $t0.AddMinutes(1); $null = Pass
    Check ($W.deploys -eq 2 -and (Whats) -ceq "deployed") "the next pass deploys"

    Write-Host ""
    Write-Host "--- a hand-run deploy records the deployed commit ---" -ForegroundColor Cyan
    $hh = New-Home "hand"
    $a = Invoke-HordeRelayDeploy -Relay "zorbrelay" -HordeHome $hh -Revision ([pscustomobject]@{ commit = $cC; clean = $true }) -Now { $t0 }
    $rec = Read-HordeRelayDeployed -HordeHome $hh
    Check ($rec.state -ceq "known" -and $rec.value.commit -ceq $cC -and $rec.value.clean -eq $true) "the record names the commit the caller read, and that it was clean"
    Check ($rec.value.origin -ceq "https://zorbrelay.example" -and $rec.value.relay -ceq "zorbrelay" -and $rec.value.at -eq $t0) "and the origin and relay the deploy answered with, at the deploy's time"
    Check ($a.state -ceq "known" -and $rec.value.version -cmatch '\A[0-9a-f]{16}\z' -and $rec.value.version -ceq $a.value.version) "and the VERSION it built, which the deploy also answers"
    $W = New-World $hh; $W.head = $cC
    $l = Pass
    Check ($W.deploys -eq 0 -and $W.told.Count -eq 0 -and (Says $l "current")) "the supervisor reads that record as its own: the page is current"
    $hh = New-Home "hand-unclean"
    $null = Invoke-HordeRelayDeploy -Relay "zorbrelay" -HordeHome $hh -Revision ([pscustomobject]@{ commit = $cC; clean = $false })
    Check ((Read-HordeRelayDeployed -HordeHome $hh).value.clean -eq $false) "a deploy from a checkout with changes of its own is recorded as not clean"
    $hh = New-Home "hand-unknown"
    $null = Invoke-HordeRelayDeploy -Relay "zorbrelay" -HordeHome $hh
    Check ((Read-HordeRelayDeployed -HordeHome $hh).value.commit -ceq "") "a deploy whose commit was not read records none"
    $W = New-World $hh; $null = Pass
    Check ($W.deploys -eq 0 -and (Whats) -ceq "no-record") "and the supervisor does not take that for a base"
    $hh = New-Home "hand-failed"; $script:relayAnswer = "fail"
    $a = Invoke-HordeRelayDeploy -Relay "zorbrelay" -HordeHome $hh -Revision ([pscustomobject]@{ commit = $cC; clean = $true })
    Check ($a.state -ceq "unknown" -and -not [System.IO.File]::Exists((Get-HordeRelayDeployedPath -HordeHome $hh))) "a deploy that failed records nothing"
    $script:relayAnswer = "ok"

    Write-Host ""
    Write-Host "--- the real deploy tool refuses a test's home ---" -ForegroundColor Cyan
    # Pointed at a folder of this suite's that holds no relay: were the guard gone, it could not reach one.
    $real = New-HordeRelayPublishTools
    $a = $null
    try { $a = & $real.Deploy (New-Home "real-tools") { param($Line) } $work } catch { $a = $null }
    Check ($null -ne $a -and $a.state -ceq "unknown" -and $a.reason -like "*a test's*") "a home under the temp folder deploys nothing"

    Write-Host ""
    Write-Host "--- the pass looks at the page on a whole pass only ---" -ForegroundColor Cyan
    $hh = New-Home "tend"
    [void][System.IO.Directory]::CreateDirectory((Join-Path $hh "settings"))
    [System.IO.File]::WriteAllText((Join-Path $hh "settings\service-definitions.json"), '{ "schemaVersion": 1, "settings": { } }')
    $script:published = New-Object System.Collections.ArrayList
    $tendTools = @{ Now = { return $t0 }; Sleep = { param($Ms) }; NewId = { return [guid]::NewGuid().ToString() }; TellAll = { param($Notices, $HordeHome, $Policy) return [pscustomobject]@{ told = @(); problem = "" } }
        PagePublish = { param($HordeHome, $Policy, $Teller) [void]$script:published.Add([pscustomobject]@{ home = $HordeHome; tells = [bool]($null -ne $Teller); policy = [bool]($null -ne $Policy) }); return @("phone page: looked at") } }
    $done = Invoke-HordeServiceSupervisor -HordeHome $hh -Tools $tendTools
    Check ($script:published.Count -eq 1 -and $script:published[0].home -ceq $hh -and $script:published[0].tells -and $script:published[0].policy) "a whole pass looks once, with its home, its policy and its teller"
    Check (@($done.lines) -ccontains "phone page: looked at") "and says what it said"
    $tendTools.PagePublish = { param($HordeHome, $Policy, $Teller) throw "boom" }
    $done = Invoke-HordeServiceSupervisor -HordeHome $hh -Tools $tendTools
    Check ($done.ran -and (Says $done.lines "THE PASS FAILED ON IT")) "a step that throws is the step's failure, not the pass's"
    $tendTools.Remove("PagePublish")
    $done = Invoke-HordeServiceSupervisor -HordeHome $hh -Tools $tendTools
    Check ($done.ran -and -not (Says $done.lines "phone page")) "with no step handed in, nothing is looked at"
    Check ($null -eq (New-HordeServiceTools)["PagePublish"]) "the pass's own tools hand in none: only the command does"
} finally {
    if ($work -like "*horde-relay-publish-*" -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

Complete-HordeSuite -Success "the supervisor deploys the phone page only when only the page changed, checks it took, tells once, retries hourly, and shares one lock and one record with a deploy by hand"
