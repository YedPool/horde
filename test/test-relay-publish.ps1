# DOES THE SUPERVISOR KEEP THE HOSTED PHONE PAGE CURRENT - DEPLOYING ONLY WHAT IT MAY, CHECKING IT, AND
# TELLING ONCE?
#
# cli/RelayPublish.ps1 (the pass's step), and the lock, the record and the build's lists of
# cli/RelayDeploy.ps1, which a deploy by hand and the supervisor's own share.
#
# NOTHING IS DEPLOYED, FETCHED OR TOLD FOR REAL (CONTRIBUTING 9):
#   - THE STEP runs on tools this suite makes: a commit that is a name in a table, a diff that is a
#     list, a list of what is shipped given as data, a deploy that writes the record a real one would
#     and fills a table of hosted files, and an HTTP that reads that table. The real tools are made
#     once, only to show the deploy refuses a test's home.
#   - THE DEPLOY'S LOCK AND RECORD, and what is shipped, run through the real functions, on a relay of
#     this suite's own registered from a repository it makes in its temp folder, whose deploy only
#     counts its calls. No relay of the repository is loaded; the repository's own worker code is only
#     read, to show the imports are followed through it.
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
$siteMap = Get-HordeRelayDeploySiteSources
$builtPaths = @(@($siteMap.Keys) + @("app/config.json", "app/icon-192.png", "app/icon-512.png", "index.html"))
# What the deploy ships, as this suite's relay would have it: its folder but its tests, the two files
# outside it that its code imports, and the site's sources and builder.
$shippedHere = [pscustomobject]@{ workerPrefixes = [string[]]@("relays/zorbrelay/"); workerExcept = [string[]]@("relays/zorbrelay/test/")
    workerFiles = [string[]]@("relay/js/protocol.js", "surfaces/pwa/page/account-client.js")
    pageFiles = [string[]]@(@($siteMap.Values) + @(Get-HordeRelayDeployBuildFiles)); buildFiles = [string[]]@(Get-HordeRelayDeployBuildFiles) }

function New-Home { param([string]$Name) $h = Join-Path $work $Name; [void][System.IO.Directory]::CreateDirectory($h); return $h }
function Sw { param([string]$Version) return ("// the worker`nconst VERSION = `"" + $Version + "`";`nconst SHELL = [];`n") }
function Hash { param([string]$Path, [string]$Version) return ("h" + $Version + ":" + $Path) }

# THE WORLD the stand-in tools act on. A deploy that works writes the record, as the real one does, and
# hosts every file it built (with the hash it answers) unless the suite says a file is hosted otherwise.
function New-World {
    param([string]$HordeHome)
    return @{ home = $HordeHome; now = $t0; head = $cB; clean = $true; headOk = $true; diffs = @{}; diffOk = $true; shippedOk = $true
        deploy = "ok"; built = $v2; serveAfter = $null; deploys = 0; calls = (New-Object System.Collections.ArrayList)
        hosted = @{ "app/sw.js" = [pscustomobject]@{ status = 200; body = (Sw $v1); sha256 = (Hash "app/sw.js" $v1) } }
        otherwise = @{}; changed = @("surfaces/pwa/page/app.js")
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
        Load    = $null
        Shipped = { param($Checkout) [void]$W.calls.Add("shipped"); if (-not $W.shippedOk) { return (New-HordeUnknown -Reason "no relay loaded") }; return (New-HordeKnown -Value $shippedHere) }
        Deploy  = {
            param($HordeHome, $Say, $Checkout)
            $W.deploys++; [void]$W.calls.Add("deploy")
            & $Say "a line the deploy said"
            if ($W.deploy -ceq "busy") { return (New-HordeUnknown -Reason (Get-HordeRelayDeployBusyReason)) }
            if ($W.deploy -ceq "fail") { return (New-HordeUnknown -Reason "a secret could not be stored: not logged in") }
            Write-HordeRelayDeployed -HordeHome $HordeHome -Revision ([pscustomobject]@{ commit = $W.head; clean = $true }) -Version $W.built -Relay "zorbrelay" -Origin $origin -At $W.now
            # Each build differs from the last by the files that changed; sw.js always does.
            $hashes = @{}
            foreach ($p in $builtPaths) { $hashes[$p] = $(if ($p -ceq "app/sw.js" -or @($W.changed) -ccontains ("" + $siteMap[$p])) { Hash $p ($W.built + $W.head) } else { Hash $p "same" }) }
            foreach ($p in $builtPaths) { $W.hosted[$p] = [pscustomobject]@{ status = 200; body = $(if ($p -ceq "app/sw.js") { Sw $(if ($null -ne $W.serveAfter) { $W.serveAfter } else { $W.built }) } else { "" }); sha256 = $hashes[$p] } }
            foreach ($p in @($W.otherwise.Keys)) { $W.hosted[$p] = $W.otherwise[$p] }
            return (New-HordeKnown -Value ([pscustomobject]@{ relay = "zorbrelay"; origin = $origin; version = $W.built; hashes = $hashes }))
        }
        Http    = {
            param($Url)
            $p = $Url.Substring($origin.Length + 1)
            [void]$W.calls.Add("http " + $p)
            if ($W.hosted.ContainsKey($p)) { return (New-HordeKnown -Value $W.hosted[$p]) }
            return (New-HordeKnown -Value ([pscustomobject]@{ status = 404; body = ""; sha256 = "" }))
        }
        SiteMap = { return $siteMap }
    }
}
$teller = { param($Notices, $HordeHome, $Policy) $W.tellCalls++; foreach ($n in @($Notices)) { [void]$W.told.Add($n) }; return [pscustomobject]@{ told = @(@($Notices) | ForEach-Object { $_.id }); problem = "" } }
$policyOn = [pscustomobject]@{ tellWarchief = $true }

function Pass { param([hashtable]$Tools = $null, $Policy = $policyOn) if ($null -eq $Tools) { $Tools = New-Tools }; return @(Invoke-HordeRelayPublishStep -HordeHome $W.home -Tools $Tools -Policy $Policy -Teller $teller -Checkout $work) }
function Seed { param([string]$Commit = $cA, [bool]$Clean = $true) Write-HordeRelayDeployed -HordeHome $W.home -Revision ([pscustomobject]@{ commit = $Commit; clean = $Clean }) -Version $v1 -Relay "zorbrelay" -Origin $origin -At $t0.AddDays(-1) }
function Range { param([string[]]$Paths, [string]$From = $cA, [string]$To = $cB) $W.diffs[$From + ".." + $To] = [string[]]@($Paths); $W.changed = [string[]]@($Paths) }
function Whats { return (@($W.told | ForEach-Object { $_.what }) -join ",") }
function Says { param($Lines, [string]$Text) return [bool](@($Lines | Where-Object { "" + $_ -like ("*" + $Text + "*") }).Count -gt 0) }
function Show { param($Lines) foreach ($l in @($Lines)) { Write-Host ("         said: " + $l) -ForegroundColor DarkYellow } }

try {
    Write-Host ""
    Write-Host "--- the classes: by what the deploy ships ---" -ForegroundColor Cyan
    $c = Get-HordeRelayPublishClasses -Shipped $shippedHere -Paths @("surfaces/pwa/page/app.js", "surfaces/pwa/Site.ps1", "cli/RelayDeploy.ps1", "decisions/page/list.js",
        "relays/zorbrelay/worker/site.js", "relays/zorbrelay/deploy-config.json", "relay/js/protocol.js", "surfaces/pwa/page/account-client.js",
        "relays/zorbrelay/test/test-x.ps1", "surfaces/pwa/test/test-pwa-site.ps1", "test/test-x.ps1", "core/Services.ps1", "relays/Port.ps1", "relays/other/Relay.ps1", "planning/x.md", "Surfaces/pwa/page/app.js")
    Check ((@($c.page) -join ",") -ceq "surfaces/pwa/page/app.js,surfaces/pwa/Site.ps1,cli/RelayDeploy.ps1,decisions/page/list.js") ("the site's served sources and the code that builds it are the page (" + (@($c.page) -join ",") + ")")
    Check ((@($c.worker) -join ",") -ceq "relays/zorbrelay/worker/site.js,relays/zorbrelay/deploy-config.json,relay/js/protocol.js,surfaces/pwa/page/account-client.js") ("the relay's folder and what its code imports are the Worker, the shared protocol included (" + (@($c.worker) -join ",") + ")")
    Check (@($c.ignored).Count -eq 8) ("tests, core, the port, another relay, planning and another case are ignored (" + (@($c.ignored) -join ",") + ")")

    Write-Host ""
    Write-Host "--- what the deploy ships is derived, not listed ---" -ForegroundColor Cyan
    # The build's own list: every file the builder dot-sources is in it.
    foreach ($bf in @(Get-HordeRelayDeployBuildFiles)) {
        $text = [System.IO.File]::ReadAllText((Join-Path $root ($bf -replace '/', '\')))
        foreach ($m in [regex]::Matches($text, '(?m)^\. \(Join-Path .*"([A-Za-z]+\\[^"]+\.ps1)"\)')) {
            $dep = $m.Groups[1].Value -replace '\\', '/'
            Check (@(Get-HordeRelayDeployBuildFiles) -ccontains $dep) ("the builder's " + $dep + ", dot-sourced by " + $bf + ", is counted as the page")
        }
    }
    # The Worker's imports, followed through this repository's own relays' code (no relay named): the
    # protocol and the account client are imported by the Worker, so they are the Worker's.
    $relayCode = @(Get-ChildItem -LiteralPath (Join-Path $root "relays") -Recurse -File -Filter "*.js" | Where-Object { $_.FullName -notmatch '\\test\\' } | ForEach-Object { $_.FullName.Substring($root.Length + 1) -replace '\\', '/' })
    Check ($relayCode.Count -ge 5) ("CONTROL: the relays' code was found (" + $relayCode.Count + " files)")
    $reach = @(Get-HordeRelayPublishImports -Root $root -Start $relayCode)
    Check (($reach -ccontains "relay/js/protocol.js") -and ($reach -ccontains "surfaces/pwa/page/account-client.js")) "the imports reach the protocol and the account client from the Worker"
    Check (-not ($reach -ccontains "surfaces/pwa/page/app.js")) "CONTROL: and not a page file the Worker does not import"
    # On a repository of this suite's own: its relay, registered from there, ships its folder and what
    # its code imports, through a second file, and not what only its tests import.
    $repo = Join-Path $work "repo"
    $fakeRelay = Join-Path $repo "relays\zorbrelay"
    foreach ($d in @("worker", "test")) { [void][System.IO.Directory]::CreateDirectory((Join-Path $fakeRelay $d)) }
    [void][System.IO.Directory]::CreateDirectory((Join-Path $repo "relay\js")); [void][System.IO.Directory]::CreateDirectory((Join-Path $repo "core"))
    [System.IO.File]::WriteAllText((Join-Path $fakeRelay "worker\index.js"), "import { a } from `"./a.js`";`nimport {`n  b,`n} from `"../../../relay/js/protocol.js`";`nimport { DurableObject } from `"host:workers`";`n")
    [System.IO.File]::WriteAllText((Join-Path $fakeRelay "worker\a.js"), "export const a = 1;`n")
    [System.IO.File]::WriteAllText((Join-Path $repo "relay\js\protocol.js"), "export { c } from `"./more.js`";`n")
    [System.IO.File]::WriteAllText((Join-Path $repo "relay\js\more.js"), "export const c = 1;`n")
    [System.IO.File]::WriteAllText((Join-Path $fakeRelay "test\t.js"), "import `"../../../core/only-tests.js`";`n")
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
    $sh = Get-HordeRelayPublishShipped -Checkout $repo
    Check ($sh.state -ceq "known" -and (@($sh.value.workerPrefixes) -join ",") -ceq "relays/zorbrelay/" -and (@($sh.value.workerExcept) -join ",") -ceq "relays/zorbrelay/test/") "the deployed relay's folder, from the port, is the Worker's, but its tests"
    Check ((@($sh.value.workerFiles) -join ",") -ceq "relay/js/more.js,relay/js/protocol.js") ("what its code imports outside it, through every import, is the Worker's too, and not what only its tests import (" + (@($sh.value.workerFiles) -join ",") + ")")
    Check ((@($sh.value.pageFiles) -ccontains "surfaces/pwa/page/app.js") -and (@($sh.value.pageFiles) -ccontains "surfaces/pwa/Site.ps1") -and (@($sh.value.buildFiles) -ccontains "cli/RelayDeploy.ps1")) "the site's sources and its builder are the page"

    Write-Host ""
    Write-Host "--- a page change is deployed, checked and told once ---" -ForegroundColor Cyan
    $W = New-World (New-Home "page-only"); Seed
    Range @("surfaces/pwa/page/app.js")
    $l = Pass
    Check ($W.deploys -eq 1) "the page was deployed"
    Check (Says $l "DEPLOYED bbbbbbb and checked") "the pass says it deployed and checked it"
    if (-not (Says $l "DEPLOYED")) { Show $l }
    Check (($W.calls -ccontains "http app/sw.js") -and ($W.calls -ccontains "http app/app.js")) "the worker and the changed file were asked for, at the origin the deploy answered with"
    Check (-not ($W.calls -ccontains "http app/store.js")) "a file that did not change is not asked for"
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
    Write-Host "--- page plus tests deploys ---" -ForegroundColor Cyan
    $W = New-World (New-Home "page-tests"); Seed
    Range @("surfaces/pwa/page/app.js", "surfaces/pwa/test/test-pwa-site.ps1", "test/test-relay-publish.ps1", "core/Services.ps1")
    $null = Pass
    Check ($W.deploys -eq 1 -and (Whats) -ceq "deployed") ("a page change among tests and core is deployed (" + (Whats) + ")")
    $W = New-World (New-Home "builder"); Seed
    Range @("surfaces/pwa/Site.ps1")
    $null = Pass
    Check ($W.deploys -eq 1 -and (Whats) -ceq "deployed") "a change to the code that builds the site is deployed"
    Check (($W.calls -ccontains "http app/store.js") -and ($W.calls -ccontains "http app/config.json")) "and then every built file under app/ is compared"

    Write-Host ""
    Write-Host "--- a range of only tests and core does nothing ---" -ForegroundColor Cyan
    $W = New-World (New-Home "ignored"); Seed
    Range @("test/test-relay-publish.ps1", "core/Services.ps1", "surfaces/pwa/test/test-pwa-site.ps1", "relays/zorbrelay/test/test-x.ps1", "relays/Port.ps1", "planning/notes.md")
    $l = Pass
    Check ($W.deploys -eq 0 -and $W.told.Count -eq 0) "nothing deployed, nobody told"
    Check (Says $l "nothing the deploy ships changed") "the pass says why"
    Check ((Read-HordeRelayDeployed -HordeHome $W.home).value.commit -ceq $cA) "the record still names what was deployed"
    $st = (Read-HordeRelayPublishState -HordeHome $W.home).value
    Check ($null -ne $st.checked -and $st.checked.base -ceq $cA -and $st.checked.through -ceq $cB) "the range is remembered as checked"
    $W.calls.Clear(); $null = Pass
    Check (@($W.calls | Where-Object { $_ -like "diff*" -or $_ -ceq "shipped" }).Count -eq 0) "the same range is not read again"
    $W.head = $cC; $W.diffs[$cB + ".." + $cC] = [string[]]@("surfaces/pwa/page/app.js"); $W.changed = @("surfaces/pwa/page/app.js")
    $null = Pass
    Check ($W.calls -ccontains "diff b..c") "a later commit is read from where the checked range ended"
    Check ($W.deploys -eq 1 -and (Read-HordeRelayDeployed -HordeHome $W.home).value.commit -ceq $cC) "and its page change is deployed, moving the record"
    Check ($null -eq (Read-HordeRelayPublishState -HordeHome $W.home).value.checked) "the checked range is spent once the base moves"

    Write-Host ""
    Write-Host "--- worker plus tests warns ---" -ForegroundColor Cyan
    $W = New-World (New-Home "worker"); Seed
    Range @("surfaces/pwa/page/app.js", "relays/zorbrelay/worker/site.js", "test/test-x.ps1")
    $l = Pass; $null = Pass
    Check ($W.deploys -eq 0) "nothing was deployed"
    Check ((Whats) -ceq "worker-changed") ("the warchief was told once that the Worker changed (" + (Whats) + ")")
    Check (Says $l "the relay's Worker changed") "the pass says why"
    $body = Format-HordeServiceNoticeBody -Notice $W.told[0]
    Check ($body.Contains("needs attention") -and $body.Contains("horde relay deploy") -and -not $body.Contains("zorbrelay")) "the warning says what a person does, and nothing from the change itself"
    $W.head = $cC; $W.diffs[$cA + ".." + $cC] = [string[]]@("surfaces/pwa/page/app.js", "relays/zorbrelay/worker/site.js", "relays/zorbrelay/worker/more.js")
    $null = Pass
    Check ($W.told.Count -eq 1) "a later merge with the same mix is not told again"
    $W = New-World (New-Home "protocol"); Seed
    Range @("relay/js/protocol.js", "test/test-x.ps1")
    $null = Pass
    Check ($W.deploys -eq 0 -and (Whats) -ceq "worker-changed") "a change to the protocol the Worker imports is a Worker change: warned, not deployed"
    $W = New-World (New-Home "worker-ignored"); Seed
    Range @("relays/zorbrelay/deploy-config.json", "core/Services.ps1")
    $null = Pass
    Check ($W.deploys -eq 0 -and (Whats) -ceq "worker-changed") "a Worker change among ignored files is warned"

    Write-Host ""
    Write-Host "--- no change does nothing ---" -ForegroundColor Cyan
    $W = New-World (New-Home "same"); Seed -Commit $cB
    $l = Pass
    Check ($W.deploys -eq 0 -and $W.told.Count -eq 0 -and @($W.calls | Where-Object { $_ -like "diff*" -or $_ -like "http*" -or $_ -ceq "shipped" }).Count -eq 0) "the checkout on the deployed commit: no diff, no request, no deploy, nobody told"
    Check (Says $l "current") "it says the page is current"
    $W = New-World (New-Home "empty-diff"); Seed; Range @()
    $null = Pass
    Check ($W.deploys -eq 0 -and $W.told.Count -eq 0) "commits that change no file: nothing done, nobody told"

    Write-Host ""
    Write-Host "--- a failed deploy warns once and is retried no sooner than an hour ---" -ForegroundColor Cyan
    $W = New-World (New-Home "failed"); Seed; $W.deploy = "fail"
    Range @("surfaces/pwa/page/app.js")
    $l = Pass
    Check ($W.deploys -eq 1 -and (Whats) -ceq "deploy-failed") ("the failed deploy is told (" + (Whats) + ")")
    Check (Says $l "FAILED") "the pass says it failed"
    Check ((Read-HordeRelayDeployed -HordeHome $W.home).value.commit -ceq $cA) "a failed deploy changes no record"
    $W.now = $t0.AddMinutes(30); $l = Pass
    Check ($W.deploys -eq 1) "half an hour later it is not tried again"
    Check (Says $l "waits") "the pass says it waits"
    $W.head = $cC; $W.diffs[$cA + ".." + $cC] = [string[]]@("surfaces/pwa/page/app.js"); $W.now = $t0.AddMinutes(59); $null = Pass
    Check ($W.deploys -eq 1) "a newer commit within the hour waits as well: at most one try an hour"
    $W.head = $cB; $W.now = $t0.AddMinutes(61); $null = Pass
    Check ($W.deploys -eq 2) "an hour later it is tried again"
    Check ($W.told.Count -eq 1) "and the same failure is not told again"
    $W.deploy = "ok"; $W.now = $t0.AddMinutes(122); $null = Pass
    Check ($W.deploys -eq 3 -and (Whats) -ceq "deploy-failed,deployed") ("once it works, that is told (" + (Whats) + ")")
    $st = Read-HordeRelayPublishState -HordeHome $W.home
    Check ($st.state -ceq "known" -and $null -eq $st.value.failure) "and the failure is settled"

    Write-Host ""
    Write-Host "--- the VERSION: required to change only when the files it hashes did ---" -ForegroundColor Cyan
    $W = New-World (New-Home "stale"); Seed; $W.serveAfter = $v1
    Range @("surfaces/pwa/page/app.js")
    $l = Pass
    Check ($W.deploys -eq 1 -and (Whats) -ceq "check-failed") ("a deploy whose built VERSION is new but the served one did not change is a failed check (" + (Whats) + ")")
    Check (Says $l "did not change") "the pass says the VERSION did not change"
    if (-not (Says $l "did not change")) { Show $l }
    $W.now = $t0.AddMinutes(61); $W.serveAfter = $null; $null = Pass
    Check ($W.deploys -eq 2) "it is tried again from the base it failed from, though the record already names the commit"
    Check ($W.calls -ccontains "diff a..b") "the retry compares with the base before the failed check"
    Check ((Whats) -ceq "check-failed,deployed") "and once the page serves what was built, that is told"
    $hand = New-World (New-Home "hand-settles"); $W = $hand; Seed; $W.serveAfter = $v1
    Range @("surfaces/pwa/page/app.js")
    $null = Pass
    Write-HordeRelayDeployed -HordeHome $W.home -Revision ([pscustomobject]@{ commit = $cB; clean = $true }) -Version $v2 -Relay "zorbrelay" -Origin $origin -At $t0.AddMinutes(10)
    $W.now = $t0.AddMinutes(70); $l = Pass
    Check ($W.deploys -eq 1 -and (Says $l "settled")) "a deploy by hand after the failure settles it: no retry"

    Write-Host ""
    Write-Host "--- an sw.js-only change passes by content ---" -ForegroundColor Cyan
    # app/sw.js is not among the files its own VERSION hashes, so the build's VERSION stays as served.
    $W = New-World (New-Home "sw-only"); Seed; $W.built = $v1
    Range @("surfaces/pwa/page/sw.js")
    $l = Pass
    Check ($W.deploys -eq 1 -and (Whats) -ceq "deployed") ("a change to sw.js alone, served with the bytes built, passes though its VERSION did not change (" + (Whats) + ")")
    if ((Whats) -cne "deployed") { Show $l }
    $W = New-World (New-Home "sw-stale"); Seed; $W.built = $v1
    Range @("surfaces/pwa/page/sw.js")
    $W.otherwise["app/sw.js"] = [pscustomobject]@{ status = 200; body = (Sw $v1); sha256 = (Hash "app/sw.js" $v1) }
    $l = Pass
    Check ((Whats) -ceq "check-failed" -and (Says $l "app/sw.js is hosted with bytes other than the ones built")) "the same change still hosted as before fails"

    Write-Host ""
    Write-Host "--- a changed served file whose hosted bytes differ fails ---" -ForegroundColor Cyan
    $W = New-World (New-Home "bytes"); Seed
    Range @("surfaces/pwa/page/app.js")
    $W.otherwise["app/app.js"] = [pscustomobject]@{ status = 200; body = ""; sha256 = "an old build" }
    $l = Pass
    Check ($W.deploys -eq 1 -and (Whats) -ceq "check-failed") ("a changed file hosted with other bytes fails the check (" + (Whats) + ")")
    Check (Says $l "app/app.js is hosted with bytes other than the ones built") "the pass names the file"
    $W = New-World (New-Home "404"); Seed
    Range @("surfaces/pwa/page/lane-card.js", "surfaces/pwa/page/app.js")
    $W.otherwise["app/app.js"] = [pscustomobject]@{ status = 404; body = ""; sha256 = "" }
    $l = Pass
    Check ($W.deploys -eq 1 -and (Whats) -ceq "check-failed" -and (Says $l "app/app.js did not answer 200 (it answered 404)")) "a changed file answering 404 fails the check, and is named"

    Write-Host ""
    Write-Host "--- the check, alone ---" -ForegroundColor Cyan
    $okSw = New-HordeKnown -Value ([pscustomobject]@{ status = 200; body = (Sw $v2); sha256 = "s" })
    $f = { param($Sha, $Expected, $Status = 200) return [pscustomobject]@{ path = "app/app.js"; answer = (New-HordeKnown -Value ([pscustomobject]@{ status = $Status; body = ""; sha256 = $Sha })); expected = $Expected } }
    Check ((Test-HordeRelayPublishCheck -Before $v1 -Built $v2 -After $okSw -Files @((& $f "x" "x"))).ok) "CONTROL: a new VERSION, the built one, and every file as built pass"
    Check ((Test-HordeRelayPublishCheck -Before "" -Built $v2 -After $okSw).ok) "with the VERSION before unknown, the built one being served passes"
    Check ((Test-HordeRelayPublishCheck -Before $v2 -Built $v2 -After $okSw).ok) "a VERSION that was not to change, unchanged, passes"
    Check (-not (Test-HordeRelayPublishCheck -Before $v1 -Built $v2 -After (New-HordeKnown -Value ([pscustomobject]@{ status = 200; body = (Sw $v1); sha256 = "s" }))).ok) "a VERSION that was to change, unchanged, fails"
    Check (-not (Test-HordeRelayPublishCheck -Before $v1 -Built $v2 -After (New-HordeKnown -Value ([pscustomobject]@{ status = 200; body = (Sw "3333333333333333"); sha256 = "s" }))).ok) "a VERSION other than the built one fails"
    Check (-not (Test-HordeRelayPublishCheck -Before $v1 -Built $v2 -After (New-HordeKnown -Value ([pscustomobject]@{ status = 404; body = ""; sha256 = "" }))).ok) "a worker that does not answer 200 fails"
    Check (-not (Test-HordeRelayPublishCheck -Before $v1 -Built $v2 -After (New-HordeUnknown -Reason "timed out")).ok) "a worker that does not answer at all fails"
    Check (-not (Test-HordeRelayPublishCheck -Before $v1 -Built $v2 -After $okSw -Files @((& $f "x" ""))).ok) "a file the deploy did not build fails"
    Check (-not (Test-HordeRelayPublishCheck -Before $v1 -Built $v2 -After $okSw -Files @([pscustomobject]@{ path = "app/x.js"; answer = (New-HordeUnknown -Reason "timed out"); expected = "x" })).ok) "a file that does not answer fails"
    $served = @(Get-HordeRelayPublishServed -Changed @("surfaces/pwa/page/app.js", "relay/js/protocol.js", "test/x.ps1") -SiteMap $siteMap -BuildFiles @(Get-HordeRelayDeployBuildFiles) -Built $builtPaths)
    Check (($served -join ",") -ceq "app/app.js,app/sw.js,relay/protocol.js") ("compared: the worker and the changed files the site serves, at their site paths (" + ($served -join ",") + ")")
    $served = @(Get-HordeRelayPublishServed -Changed @("core/Tristate.ps1") -SiteMap $siteMap -BuildFiles @(Get-HordeRelayDeployBuildFiles) -Built $builtPaths)
    Check ($served.Count -eq @($builtPaths | Where-Object { $_ -like "app/*" }).Count -and -not ($served -ccontains "index.html")) "a change to the builder compares every built file under app/"

    Write-Host ""
    Write-Host "--- the first run with no record warns and does not deploy ---" -ForegroundColor Cyan
    # CHOSEN: no seeding from the live VERSION. It is a hash of built files, not a commit (header).
    $W = New-World (New-Home "first-run")
    $null = Pass; $null = Pass
    Check ($W.deploys -eq 0 -and @($W.calls | Where-Object { $_ -like "diff*" }).Count -eq 0) "nothing is compared and nothing deployed"
    Check ((Whats) -ceq "no-record") ("the warchief is told once that a deploy by hand records it (" + (Whats) + ")")
    $W = New-World (New-Home "unclean-record"); Seed -Clean $false; Range @("surfaces/pwa/page/app.js")
    $null = Pass
    Check ($W.deploys -eq 0 -and (Whats) -ceq "no-record") "a record made from a checkout with changes of its own is no base: warned, not deployed"
    $W = New-World (New-Home "bad-record"); [void][System.IO.Directory]::CreateDirectory((Get-HordeRelayDeployFolder -HordeHome $W.home))
    [System.IO.File]::WriteAllText((Get-HordeRelayDeployedPath -HordeHome $W.home), "{ not json")
    $null = Pass
    Check ($W.deploys -eq 0 -and (Whats) -ceq "no-record") "a record that cannot be read is no base: warned, not deployed"

    Write-Host ""
    Write-Host "--- everything else that is unknown is not a deploy ---" -ForegroundColor Cyan
    $W = New-World (New-Home "dirty"); Seed; $W.clean = $false; Range @("surfaces/pwa/page/app.js")
    $null = Pass; $null = Pass
    Check ($W.deploys -eq 0 -and (Whats) -ceq "dirty") "a checkout with changes of its own is not deployed, and that is told once"
    $W = New-World (New-Home "no-diff"); Seed; $W.diffOk = $false
    $null = Pass; $null = Pass
    Check ($W.deploys -eq 0 -and (Whats) -ceq "unreadable") "a diff that cannot be read is not deployed, and that is told once"
    $W = New-World (New-Home "no-shipped"); Seed; $W.shippedOk = $false; Range @("surfaces/pwa/page/app.js")
    # Caught, so that a step that crashed on it is a failed check here, not only an error.
    try { $null = Pass; $null = Pass } catch { }
    Check ($W.deploys -eq 0 -and (Whats) -ceq "unreadable") "what is shipped that cannot be told is not deployed, and that is told once"
    $W = New-World (New-Home "no-head"); Seed; $W.headOk = $false
    $null = Pass
    Check ($W.deploys -eq 0 -and (Whats) -ceq "unreadable") "a commit that cannot be read is not deployed"
    $W = New-World (New-Home "interrupted"); Seed
    Range @("surfaces/pwa/page/app.js")
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
    $W = New-World (New-Home "busy-step"); Seed; $W.deploy = "busy"; Range @("surfaces/pwa/page/app.js")
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
    Check ($a.value.hashes["app/sw.js"] -cmatch '\A[0-9a-f]{64}\z' -and $a.value.hashes.Count -eq $builtPaths.Count) "the deploy answers the hash of every file it built"
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
    # Were the guard gone, the only relay it could reach is this suite's own, whose deploy only counts.
    $real = New-HordeRelayPublishTools
    $before = $script:relayDeploys
    $a = $null
    try { $a = & $real.Deploy (New-Home "real-tools") { param($Line) } $work } catch { $a = $null }
    Check ($null -ne $a -and $a.state -ceq "unknown" -and $a.reason -like "*a test's*" -and $script:relayDeploys -eq $before) "a home under the temp folder deploys nothing"

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

Complete-HordeSuite -Success "the supervisor deploys the phone page when it changed and the Worker did not, ignores what is not shipped, checks the hosted bytes, tells once, retries hourly, and shares one lock and one record with a deploy by hand"
