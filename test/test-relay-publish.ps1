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
$cA = "a" * 40; $cB = "b" * 40; $cC = "c" * 40; $cD = "d" * 40; $cE = "e" * 40
$origin = "https://zorbrelay.example"
$v1 = "1111111111111111"; $v2 = "2222222222222222"
$siteMap = Get-HordeRelayDeploySiteSources
$builtPaths = @(@($siteMap.Keys) + @("app/config.json", "app/icon-192.png", "app/icon-512.png", "index.html"))
# What the deploy ships, as this suite's relay would have it: its folder but its tests, the two files
# outside it that its code imports, and the site's sources and builder.
$shippedHere = [pscustomobject]@{ workerPrefixes = [string[]]@("relays/zorbrelay/"); workerExcept = [string[]]@("relays/zorbrelay/test/")
    workerFiles = [string[]]@("relay/js/protocol.js", "surfaces/pwa/page/account-client.js", "surfaces/pwa/page/index.html", "cli/RelayDeploy.ps1", "relays/Port.ps1")
    pageFiles = [string[]]@(@($siteMap.Values) + @(Get-HordeRelayDeployBuildFiles)); buildFiles = [string[]]@(Get-HordeRelayDeployBuildFiles)
    sharedFiles = [string[]]@("relay/js/protocol.js", "surfaces/pwa/page/account-client.js", "surfaces/pwa/page/index.html") }

function New-Home { param([string]$Name) $h = Join-Path $work $Name; [void][System.IO.Directory]::CreateDirectory($h); return $h }
function Sw { param([string]$Version) return ("// the worker`nconst VERSION = `"" + $Version + "`";`nconst SHELL = [];`n") }
function Hash { param([string]$Path, [string]$Version) return ("h" + $Version + ":" + $Path) }

# THE WORLD the stand-in tools act on. A deploy that works writes the record, as the real one does, and
# hosts every file it built (with the hash it answers) unless the suite says a file is hosted otherwise.
function New-World {
    param([string]$HordeHome)
    return @{ home = $HordeHome; now = $t0; head = $cB; clean = $true; headOk = $true; headReason = "no revision tool"; diffs = @{}; diffOk = $true; diffReason = "bad revision"; upstreamReason = "origin could not be reached"; shippedOk = $true; bundles = @{}; bundleOk = $true; onMain = $true; movedTo = ""; propagateAfter = 0; sleeps = 0; staged = $null
        deploy = "ok"; built = $v2; serveAfter = $null; deploys = 0; calls = (New-Object System.Collections.ArrayList)
        hosted = @{ "app/sw.js" = [pscustomobject]@{ status = 200; body = (Sw $v1); sha256 = (Hash "app/sw.js" $v1) } }
        otherwise = @{}; changed = @("surfaces/pwa/page/app.js")
        told = (New-Object System.Collections.ArrayList); tellCalls = 0 }
}
function New-Tools {
    return @{
        Now     = { return $W.now }
        # A sleep moves the clock; a deploy staged to propagate shows after the sleeps the suite says.
        Sleep   = {
            param($Ms)
            $W.sleeps++; $W.now = $W.now.AddMilliseconds($Ms)
            if ($null -ne $W.staged -and $W.sleeps -ge $W.propagateAfter) { foreach ($k in @($W.staged.Keys)) { $W.hosted[$k] = $W.staged[$k] }; $W.staged = $null }
        }
        Upstream = { param($Checkout, $Commit) [void]$W.calls.Add("upstream " + $Commit.Substring(0, 1)); if ($null -eq $W.onMain) { return (New-HordeUnknown -Reason $W.upstreamReason) }; return (New-HordeKnown -Value ([bool]$W.onMain)) }
        NewId   = { return [guid]::NewGuid().ToString() }
        Head    = { param($Checkout) [void]$W.calls.Add("head"); if (-not $W.headOk) { return (New-HordeUnknown -Reason $W.headReason) }; return (New-HordeKnown -Value ([pscustomobject]@{ commit = $W.head; clean = $W.clean })) }
        Diff    = {
            param($Checkout, $Base, $Head)
            [void]$W.calls.Add("diff " + $Base.Substring(0, 1) + ".." + $Head.Substring(0, 1))
            if (-not $W.diffOk -or -not $W.diffs.ContainsKey($Base + ".." + $Head)) { return (New-HordeUnknown -Reason $W.diffReason) }
            return (New-HordeKnown -Value ([pscustomobject]@{ paths = [string[]]@($W.diffs[$Base + ".." + $Head]) }))
        }
        Load    = $null
        Shipped = { param($Checkout) [void]$W.calls.Add("shipped"); if (-not $W.shippedOk) { return (New-HordeUnknown -Reason "no relay loaded") }; return (New-HordeKnown -Value $shippedHere) }
        # A Worker bundle: the same at every commit unless the suite says otherwise.
        Bundle  = {
            param($Checkout, $Commit)
            [void]$W.calls.Add("bundle " + $Commit.Substring(0, 1))
            if (-not $W.bundleOk) { return (New-HordeUnknown -Reason "the dry run did not bundle the Worker") }
            return (New-HordeKnown -Value ([pscustomobject]@{ sha256 = $(if ($W.bundles.ContainsKey($Commit)) { $W.bundles[$Commit] } else { "0" * 64 }) }))
        }
        Deploy  = {
            param($HordeHome, $Say, $Checkout, $Commit)
            $W.deploys++; [void]$W.calls.Add("deploy " + $Commit.Substring(0, 1))
            if ($W.movedTo -ne "") { return (New-HordeUnknown -Reason "the checkout moved off the commit that was checked; nothing was deployed") }
            & $Say "a line the deploy said"
            if ($W.deploy -ceq "busy") { return (New-HordeUnknown -Reason (Get-HordeRelayDeployBusyReason)) }
            if ($W.deploy -ceq "fail") { return (New-HordeUnknown -Reason "a secret could not be stored: not logged in") }
            # As Publish-HordeRelay passes on a deploy that went out and then failed its check: marked live.
            if ($W.deploy -ceq "live") { $u = New-HordeUnknown -Reason "relay 'zorbrelay' IS deployed, but its sign-in failed the check after the deploy: Google would refuse it. Sign-in will not work until it is fixed: deploy again from a fixed checkout"; $u | Add-Member -NotePropertyName live -NotePropertyValue $true; return $u }
            # As a real deploy does, the record is written when it ENDS: minutes after the pass began.
            Write-HordeRelayDeployed -HordeHome $HordeHome -Revision ([pscustomobject]@{ commit = $Commit; clean = $true }) -Version $W.built -Relay "zorbrelay" -Origin $origin -At $W.now.AddMinutes(3)
            # Each build differs from the last by the files that changed; sw.js always does.
            $hashes = @{}
            foreach ($p in $builtPaths) { $hashes[$p] = $(if ($p -ceq "app/sw.js" -or @($W.changed) -ccontains ("" + $siteMap[$p])) { Hash $p ($W.built + $W.head) } else { Hash $p "same" }) }
            $new = @{}
            foreach ($p in $builtPaths) { $new[$p] = [pscustomobject]@{ status = 200; body = $(if ($p -ceq "app/sw.js") { Sw $(if ($null -ne $W.serveAfter) { $W.serveAfter } else { $W.built }) } else { "" }); sha256 = $hashes[$p] } }
            foreach ($p in @($W.otherwise.Keys)) { $new[$p] = $W.otherwise[$p] }
            if ($W.propagateAfter -gt 0) { $W.sleeps = 0; $W.staged = $new } else { foreach ($k in @($new.Keys)) { $W.hosted[$k] = $new[$k] } }
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
    $c = Get-HordeRelayPublishClasses -Shipped $shippedHere -Paths @("surfaces/pwa/page/app.js", "surfaces/pwa/Site.ps1", "cli/RelayDeploy.ps1", "cli/RelayPublish.ps1", "decisions/page/list.js",
        "relays/zorbrelay/worker/site.js", "relays/zorbrelay/deploy-config.json", "relay/js/protocol.js", "surfaces/pwa/page/account-client.js",
        "relays/zorbrelay/test/test-x.ps1", "surfaces/pwa/test/test-pwa-site.ps1", "test/test-x.ps1", "core/Services.ps1", "relays/Port.ps1", "relays/other/Relay.ps1", "planning/x.md", "Surfaces/pwa/page/app.js")
    Check ((@($c.page) -join ",") -ceq "surfaces/pwa/page/app.js,surfaces/pwa/Site.ps1,decisions/page/list.js") ("the site's served sources and the code that builds it are the page (" + (@($c.page) -join ",") + ")")
    Check ((@($c.worker) -join ",") -ceq "cli/RelayDeploy.ps1,relays/zorbrelay/worker/site.js,relays/zorbrelay/deploy-config.json,relay/js/protocol.js,surfaces/pwa/page/account-client.js,relays/Port.ps1") ("the relay's folder, what its code imports and the deploy's own code are the Worker (" + (@($c.worker) -join ",") + ")")
    Check (@($c.ignored).Count -eq 8 -and (@($c.ignored) -ccontains "cli/RelayPublish.ps1")) ("tests, core, another relay, planning, another case, and this step's own code are ignored (" + (@($c.ignored) -join ",") + ")")

    Write-Host ""
    Write-Host "--- what the deploy ships is derived, not listed ---" -ForegroundColor Cyan
    # The build's own list: every file the builder dot-sources is in it.
    foreach ($bf in @(@(Get-HordeRelayDeployBuildFiles) + "cli/RelayDeploy.ps1")) {
        $text = [System.IO.File]::ReadAllText((Join-Path $root ($bf -replace '/', '\')))
        foreach ($m in [regex]::Matches($text, '(?m)^\. \(Join-Path .*"([A-Za-z]+\\[^"]+\.ps1)"\)')) {
            $dep = $m.Groups[1].Value -replace '\\', '/'
            Check (@(@(Get-HordeRelayDeployBuildFiles) + @(Get-HordeRelayDeployMachineryFiles)) -ccontains $dep) ("the builder's " + $dep + ", dot-sourced by " + $bf + ", is counted as the page or the deploy's own code")
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
        # Went out, then a check after it failed (relays/Port.ps1, DEPLOYING): unknown marked live.
        if ($script:relayAnswer -ceq "live") { $u = New-HordeUnknown -Reason "its sign-in failed the check after the deploy: Google would refuse it. Sign-in will not work until it is fixed: deploy again from a fixed checkout"; $u | Add-Member -NotePropertyName live -NotePropertyValue $true; return $u }
        return (New-HordeKnown -Value ([pscustomobject]@{ origin = "https://zorbrelay.example" }))
    }
    $sh = Get-HordeRelayPublishShipped -Checkout $repo
    Check ($sh.state -ceq "known" -and (@($sh.value.workerPrefixes) -join ",") -ceq "relays/zorbrelay/" -and (@($sh.value.workerExcept) -join ",") -ceq "relays/zorbrelay/test/") "the deployed relay's folder, from the port, is the Worker's, but its tests"
    Check ((@($sh.value.workerFiles) -join ",") -ceq "cli/RelayDeploy.ps1,relay/js/more.js,relay/js/protocol.js,relays/Port.ps1") ("what its code imports outside it, through every import, is the Worker's too, and not what only its tests import (" + (@($sh.value.workerFiles) -join ",") + ")")
    Check ((@($sh.value.pageFiles) -ccontains "surfaces/pwa/page/app.js") -and (@($sh.value.pageFiles) -ccontains "surfaces/pwa/Site.ps1") -and -not (@($sh.value.pageFiles) -ccontains "cli/RelayDeploy.ps1")) "the site's sources and its builder are the page, and the deploy's own code is not"
    Check ((@($sh.value.sharedFiles) -join ",") -ceq "relay/js/protocol.js") ("shared: the Worker's files the site serves too, and not one it imports that the site does not serve (" + (@($sh.value.sharedFiles) -join ",") + ")")

    Write-Host ""
    Write-Host "--- the port's bundle ---" -ForegroundColor Cyan
    $b1 = Get-HordeRelayBundle -Name "zorbrelay" -Tree $repo -Work $work
    Check ($b1.state -ceq "unknown" -and $b1.reason -like "*cannot bundle*") "a relay that hands in no bundle cannot be measured"
    $bundleRelay = Join-Path $work "zorbbundle"
    [void][System.IO.Directory]::CreateDirectory($bundleRelay)
    [System.IO.File]::WriteAllText((Join-Path $bundleRelay "capabilities.json"), $caps.Replace('"relay": "zorbrelay"', '"relay": "zorbbundle"'))
    $script:bundleAnswer = $null
    $null = Register-HordeRelay -Folder $bundleRelay -Connect $none -Put $none -Get $none -Watch $none -Ack $none -Bundle { param($Tree, $Work) return $script:bundleAnswer }
    $script:bundleAnswer = New-HordeKnown -Value ([pscustomobject]@{ sha256 = ("c" * 64) })
    $b1 = Get-HordeRelayBundle -Name "zorbbundle" -Tree $repo -Work $work
    Check ($b1.state -ceq "known" -and $b1.value.sha256 -ceq ("c" * 64)) "CONTROL: a relay's bundle hash is passed on"
    $script:bundleAnswer = New-HordeKnown -Value ([pscustomobject]@{ sha256 = "short" })
    Check ((Get-HordeRelayBundle -Name "zorbbundle" -Tree $repo -Work $work).state -ceq "unknown") "a bundle answered without a 64-hex hash is unknown"
    $script:bundleAnswer = [pscustomobject]@{ state = "known"; value = [pscustomobject]@{ sha256 = ("c" * 64) } }
    Check ((Get-HordeRelayBundle -Name "zorbbundle" -Tree $repo -Work $work).state -ceq "unknown") "a bundle that is not an answer is unknown"

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
    Check (($W.calls -ccontains "bundle a") -and ($W.calls -ccontains "bundle b") -and ($W.calls -ccontains "upstream b")) "before any deploy: on origin/main, and the Worker bundled alike at both commits"
    Check ($W.calls -ccontains "deploy b") "the deploy is handed the commit that was checked"
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
    Range @("test/test-relay-publish.ps1", "core/Services.ps1", "surfaces/pwa/test/test-pwa-site.ps1", "relays/zorbrelay/test/test-x.ps1", "relays/other/Relay.ps1", "cli/RelayPublish.ps1", "planning/notes.md")
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
    $W = New-World (New-Home "worker-only"); Seed
    Range @("relay/js/protocol.js", "relays/zorbrelay/worker/site.js")
    $null = Pass
    Check ($W.deploys -eq 0 -and (Whats) -ceq "worker-changed") "a worker-only file warns, shared files beside it or not"
    Check (@($W.calls | Where-Object { $_ -like "bundle*" }).Count -eq 0) "and nothing is bundled for it"
    $W = New-World (New-Home "worker-ignored"); Seed
    Range @("relays/zorbrelay/deploy-config.json", "core/Services.ps1")
    $null = Pass
    Check ($W.deploys -eq 0 -and (Whats) -ceq "worker-changed") "a Worker change among ignored files is warned"

    Write-Host ""
    Write-Host "--- a shared file is measured: does the Worker bundle change? ---" -ForegroundColor Cyan
    $W = New-World (New-Home "protocol-same"); Seed
    Range @("relay/js/protocol.js", "surfaces/pwa/page/app.js", "test/test-x.ps1")
    $l = Pass
    Check ($W.deploys -eq 1 -and (Whats) -ceq "deployed") ("a protocol.js change that leaves the worker bundle identical deploys (" + (Whats) + ")")
    Check (($W.calls -ccontains "bundle a") -and ($W.calls -ccontains "bundle b")) "the Worker was bundled at the deployed commit and at the checkout's"
    Check (Says $l ": the same") "the pass says what it measured"
    Check ($W.calls -ccontains "http relay/protocol.js") "the shared file, now the page, is compared after the deploy"
    $W = New-World (New-Home "protocol-differs"); Seed
    Range @("relay/js/protocol.js", "surfaces/pwa/page/account-client.js")
    $W.bundles[$cB] = "1" * 64
    $l = Pass; $null = Pass
    Check ($W.deploys -eq 0 -and (Whats) -ceq "worker-changed") ("one that changes the bundle warns (" + (Whats) + ")")
    Check (@($W.calls | Where-Object { $_ -like "bundle*" }).Count -eq 2) "each commit is bundled once, and the next pass reads the hashes it kept"
    $kept = @((Read-HordeRelayPublishState -HordeHome $W.home).value.bundles)
    Check ($kept.Count -eq 2 -and @($kept | Where-Object { $_.commit -ceq $cB -and $_.sha256 -ceq ("1" * 64) }).Count -eq 1) "the hashes are kept in the state, by commit"
    $W = New-World (New-Home "protocol-unbuilt"); Seed
    Range @("relay/js/protocol.js")
    $W.bundleOk = $false
    $l = Pass; $null = Pass
    Check ($W.deploys -eq 0 -and (Whats) -ceq "worker-unmeasured") ("a bundle that cannot be built warns (" + (Whats) + ")")
    Check (@($W.calls | Where-Object { $_ -like "bundle*" }).Count -eq 2) "and is not tried again within the hour"
    Check (@((Read-HordeRelayPublishState -HordeHome $W.home).value.bundles).Count -eq 0) "a bundle that was not made is not kept"
    $W.bundleOk = $true; $W.now = $t0.AddMinutes(61); $null = Pass
    Check (@($W.calls | Where-Object { $_ -like "bundle*" }).Count -eq 4 -and $W.deploys -eq 1) "an hour later it is bundled again, and deployed once both are made alike"
    $body = Format-HordeServiceNoticeBody -Notice $W.told[0]
    Check ($body.Contains("could not be measured") -and $body.Contains("horde relay deploy")) "and says the Worker could not be measured"
    $W = New-World (New-Home "protocol-half"); Seed
    Range @("relay/js/protocol.js")
    $W.bundles[$cA] = "not a hash"
    $null = Pass
    Check ($W.deploys -eq 0 -and (Whats) -ceq "worker-unmeasured") "a bundle answered without a hash is no measurement"

    Write-Host ""
    Write-Host "--- the measure, alone ---" -ForegroundColor Cyan
    $k = { param($Sha) return (New-HordeKnown -Value ([pscustomobject]@{ sha256 = $Sha })) }
    $cl = Get-HordeRelayPublishClasses -Shipped $shippedHere -Paths @("relay/js/protocol.js", "surfaces/pwa/page/app.js")
    $dd = { param([string[]]$Paths) return (Get-HordeRelayPublishDecision -Classes (Get-HordeRelayPublishClasses -Shipped $shippedHere -Paths $Paths) -Shipped $shippedHere -State (New-HordeRelayPublishState) -Now $t0 -Base $cA).action }
    Check ((& $dd @("relay/js/protocol.js", "surfaces/pwa/page/app.js")) -ceq "measure") "shared files and page files are measured"
    Check ((& $dd @("surfaces/pwa/page/app.js")) -ceq "measure") "page files alone are measured too: every deploy is"
    Check ((& $dd @("relay/js/protocol.js", "relays/zorbrelay/deploy-config.json")) -ceq "warn") "with a worker-only file beside them, they are warned outright"
    Check ((& $dd @("cli/RelayDeploy.ps1", "surfaces/pwa/page/app.js")) -ceq "warn") "a change to the deploy's own code is warned outright"
    Check ((& $dd @("core/Services.ps1")) -ceq "ignore") "nothing shipped: ignored"
    $m = Get-HordeRelayPublishMeasured -Classes $cl -Base (& $k ("a" * 64)) -Head (& $k ("a" * 64))
    Check ($m.measured -ceq "same" -and @($m.worker).Count -eq 0 -and (@($m.page) -join ",") -ceq "surfaces/pwa/page/app.js,relay/js/protocol.js") "alike: the shared files join the page"
    $m = Get-HordeRelayPublishMeasured -Classes $cl -Base (& $k ("a" * 64)) -Head (& $k ("b" * 64))
    Check ($m.measured -ceq "differs" -and (@($m.worker) -join ",") -ceq "relay/js/protocol.js") "different: they stay the Worker's"
    $m = Get-HordeRelayPublishMeasured -Classes $cl -Base (& $k ("a" * 64)) -Head (New-HordeUnknown -Reason "no")
    Check ($m.measured -ceq "unknown" -and @($m.worker).Count -eq 1) "either not made: unknown, and they stay the Worker's"

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
    Check ((Says $l "the deploy did not work") -and -not (Says $l "IS deployed") -and (Format-HordeServiceNoticeBody -Notice $W.told[0]).Contains("deploy of the phone page failed")) "MUST-KEEP TWIN: a deploy that never went out still reads 'deploy-failed: the deploy did not work'"
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
    Write-Host "--- a deploy that went out and failed its check needs action, and is never 'deploy-failed' ---" -ForegroundColor Cyan
    # Review of PR 275: the relay IS live and broken, so the founder must act; "the deploy did not work"
    # would tell him the opposite.
    $W = New-World (New-Home "needs-action"); Seed; $W.deploy = "live"
    Range @("surfaces/pwa/page/app.js")
    $l = Pass
    $all = ($l -join "`n")
    Check ($W.deploys -eq 1 -and (Whats) -ceq "deploy-needs-action" -and $W.told.Count -eq 1) ("it is told, as its own outcome (" + (Whats) + ")")
    Check ((Says $l "NEEDS ACTION - deploy-needs-action: relay 'zorbrelay' IS deployed, but its sign-in failed the check after the deploy") -and (Says $l "deploy again from a fixed checkout")) "the pass says it needs action, that the relay IS deployed, and the way back"
    Check (-not $all.Contains("deploy-failed") -and -not $all.Contains("the deploy did not work") -and $all -notmatch 'not deployed') "and never 'deploy-failed', 'the deploy did not work' or 'not deployed'"
    $body = Format-HordeServiceNoticeBody -Notice $W.told[0]
    Check ($body.Contains("needs attention") -and $body.Contains("IS live, but its sign-in failed the check after the deploy") -and $body.Contains("deploy again from a fixed checkout") -and -not $body.Contains("failed;")) ("the notice to the warchief still escalates, in its own fixed words with the way back (" + ($body -replace "`n", " | ") + ")")
    Check ((Read-HordeRelayDeployed -HordeHome $W.home).value.commit -ceq $cA) "the record is not moved: the page is not taken as current"
    $st = Read-HordeRelayPublishState -HordeHome $W.home
    Check ($st.state -ceq "known" -and $null -ne $st.value.failure -and $st.value.failure.what -ceq "deploy-needs-action") "its state is kept as deploy-needs-action, read back as written"
    $W.now = $t0.AddMinutes(30); $l = Pass
    Check ($W.deploys -eq 1 -and $W.told.Count -eq 1 -and (Says $l "waits")) "it waits an hour like a failure, and is not told again"

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
    # MUST 1 (review of PR 263): the real deploy writes its record when it ENDS, after the failure's
    # time; the record is still the failing deploy's own, so the failure stands and is retried.
    $failRec = (Read-HordeRelayDeployed -HordeHome $W.home).value
    Check ($failRec.commit -ceq $cB) "CONTROL: the record the retried deploy wrote names its commit"
    $W = New-World (New-Home "must1"); Seed; $W.serveAfter = $v1
    Range @("surfaces/pwa/page/app.js")
    $null = Pass
    $st = (Read-HordeRelayPublishState -HordeHome $W.home).value
    Check ((Read-HordeRelayDeployed -HordeHome $W.home).value.at -gt $st.failure.at) "CONTROL: the failing deploy's record is later than the failure"
    $W.now = $t0.AddMinutes(30); $null = Pass
    Check ($W.deploys -eq 1) "within the hour it is not tried again"
    $W.now = $t0.AddMinutes(61); $null = Pass
    Check ($W.deploys -eq 2) "a failed check is tried again an hour later, though its own deploy's record is later than the failure"
    # MUST 2: a deploy by hand of ANOTHER commit after a failure is the base from then on.
    $W = New-World (New-Home "must2"); Seed; $W.deploy = "fail"
    Range @("surfaces/pwa/page/app.js")
    $null = Pass
    Write-HordeRelayDeployed -HordeHome $W.home -Revision ([pscustomobject]@{ commit = $cC; clean = $true }) -Version $v2 -Relay "zorbrelay" -Origin $origin -At $t0.AddMinutes(20)
    $W.diffs[$cC + ".." + $cB] = [string[]]@("surfaces/pwa/page/app.js"); $W.deploy = "ok"
    $W.now = $t0.AddMinutes(25); $l = Pass
    Check ($W.calls -ccontains "diff c..b") "a deploy by hand of another commit after the failure is the base"
    Check ($W.deploys -eq 2 -and (Says $l "settles it") -and (Read-HordeRelayDeployed -HordeHome $W.home).value.commit -ceq $cB) "it settles the failure at once: what changed since it is deployed, with no hour to wait"
    $hand = New-World (New-Home "hand-settles"); $W = $hand; Seed; $W.serveAfter = $v1
    Range @("surfaces/pwa/page/app.js")
    $null = Pass
    Write-HordeRelayDeployed -HordeHome $W.home -Revision ([pscustomobject]@{ commit = $cB; clean = $true }) -Version $v2 -Relay "zorbrelay" -Origin $origin -At $t0.AddMinutes(10)
    $W.now = $t0.AddMinutes(70); $l = Pass
    Check ($W.deploys -eq 1 -and (Says $l "settles it")) "a deploy by hand after the failure settles it: no retry"

    Write-Host ""
    Write-Host "--- the check waits for the hosted page to change, up to 60 s ---" -ForegroundColor Cyan
    $W = New-World (New-Home "propagate"); Seed; $W.propagateAfter = 3
    Range @("surfaces/pwa/page/app.js")
    $l = Pass
    Check ($W.deploys -eq 1 -and (Whats) -ceq "deployed" -and $W.sleeps -ge 3) ("a page that changes three looks after the deploy passes (" + (Whats) + ", " + $W.sleeps + " sleeps)")
    $W = New-World (New-Home "never-propagates"); Seed; $W.propagateAfter = 1000
    Range @("surfaces/pwa/page/app.js")
    $l = Pass
    Check ((Whats) -ceq "check-failed" -and ($W.now - $t0).TotalSeconds -ge 60 -and ($W.now - $t0).TotalSeconds -le 70) ("a page that never changes fails after about 60 s (" + ($W.now - $t0).TotalSeconds + " s)")

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
    # T-0380: the 2026-10-28 05:41Z incident - the checkout's rev-parse did not finish in 20 s, the card said
    # "needs attention", and the next pass (05:47Z) was fine. The reason is the exact text the real tool gives.
    $slowWords = "the checkout's commit could not be read: its checkout X is not a checkout (git rev-parse: it did not finish within 20 s and was ended)"
    $W = New-World (New-Home "slow-once"); Seed; Range @("surfaces/pwa/page/app.js")
    $W.headOk = $false; $W.headReason = $slowWords
    $l = Pass
    Check ($W.deploys -eq 0 -and $W.told.Count -eq 0) "a git call that runs out of time, once: nothing deployed and nothing told"
    $st = (Read-HordeRelayPublishState -HordeHome $W.home).value
    Check ($st.troubled -ne $true -and @($st.told).Count -eq 0 -and $st.slow -eq 1) "and the episode is not troubled, no key is told, the slow pass is counted"
    Check (Says $l "next pass looks again") "and the pass says it will look again"
    $W.headOk = $true; $W.now = $t0.AddMinutes(6)
    $l = Pass
    Check ($W.deploys -eq 1 -and $W.told.Count -eq 1 -and (Whats) -ceq "deployed") "the next pass deploys, and only the deploy is told"
    Check ((Read-HordeRelayPublishState -HordeHome $W.home).value.slow -eq 0) "and the count starts over"
    $W = New-World (New-Home "slow-twice"); Seed; Range @("surfaces/pwa/page/app.js")
    $W.headOk = $false; $W.headReason = $slowWords
    $null = Pass; $W.now = $t0.AddMinutes(6); $null = Pass
    Check ($W.deploys -eq 0 -and (Whats) -ceq "unreadable") "two passes in a row that run out of time: the second is told"
    $null = Pass
    Check ((Whats) -ceq "unreadable") "and a third is not told again in the same episode"
    $W = New-World (New-Home "slow-reset"); Seed; Range @("surfaces/pwa/page/app.js")
    $W.headOk = $false; $W.headReason = $slowWords
    $null = Pass
    $W.headOk = $true; $W.deploy = "fail"; $W.now = $t0.AddMinutes(6); $null = Pass
    $W.headOk = $false; $W.headReason = $slowWords; $W.now = $t0.AddHours(2); $null = Pass
    Check (-not (@($W.told | ForEach-Object { $_.what }) -ccontains "unreadable")) "a pass between two slow ones starts the count over: the second slow one is quiet again"
    $W = New-World (New-Home "not-slow"); Seed; Range @("surfaces/pwa/page/app.js")
    $W.headOk = $false; $W.headReason = "the checkout's commit could not be read: its checkout X is not a checkout (git rev-parse: fatal: not a git repository)"
    $null = Pass
    Check ($W.deploys -eq 0 -and (Whats) -ceq "unreadable") "a failure that is not a time-out is told at once, as before"
    # The same three cases at the diff and at the origin/main fetch (round 2, S1).
    $W = New-World (New-Home "slow-diff-once"); Seed; Range @("surfaces/pwa/page/app.js")
    $W.diffOk = $false; $W.diffReason = $slowWords
    $null = Pass
    Check ($W.deploys -eq 0 -and $W.told.Count -eq 0 -and (Read-HordeRelayPublishState -HordeHome $W.home).value.slow -eq 1) "a diff that runs out of time, once: nothing deployed, nothing told"
    $W.diffOk = $true; $W.now = $t0.AddMinutes(6); $null = Pass
    Check ($W.deploys -eq 1 -and (Whats) -ceq "deployed" -and (Read-HordeRelayPublishState -HordeHome $W.home).value.slow -eq 0) "and the next pass deploys clean"
    $W = New-World (New-Home "slow-diff-twice"); Seed; Range @("surfaces/pwa/page/app.js")
    $W.diffOk = $false; $W.diffReason = $slowWords
    $null = Pass; $W.now = $t0.AddMinutes(6); $null = Pass
    Check ($W.deploys -eq 0 -and (Whats) -ceq "unreadable") "a diff that runs out of time twice in a row is told on the second"
    $W = New-World (New-Home "slow-main-once"); Seed; Range @("surfaces/pwa/page/app.js")
    $W.onMain = $null; $W.upstreamReason = $slowWords
    $null = Pass
    Check ($W.deploys -eq 0 -and $W.told.Count -eq 0 -and (Read-HordeRelayPublishState -HordeHome $W.home).value.slow -eq 1 -and $null -eq (Read-HordeRelayPublishState -HordeHome $W.home).value.failure) "an origin/main fetch that runs out of time, once: nothing deployed, nothing told, no failure kept"
    $W.onMain = $true; $W.now = $t0.AddMinutes(6); $null = Pass
    Check ($W.deploys -eq 1 -and (Whats) -ceq "deployed" -and (Read-HordeRelayPublishState -HordeHome $W.home).value.slow -eq 0) "and the next pass deploys clean"
    $W = New-World (New-Home "slow-main-twice"); Seed; Range @("surfaces/pwa/page/app.js")
    $W.onMain = $null; $W.upstreamReason = $slowWords
    $null = Pass; $W.now = $t0.AddMinutes(6); $null = Pass
    Check ($W.deploys -eq 0 -and (Whats) -ceq "unreadable") "an origin/main fetch that runs out of time twice in a row is told on the second"
    $W = New-World (New-Home "other-diff"); Seed; $W.diffOk = $false
    $null = Pass
    Check ($W.told.Count -eq 1) "a diff that fails for another reason is still told at once"
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
    Write-Host "--- only what is on origin/main, and only the commit checked ---" -ForegroundColor Cyan
    $W = New-World (New-Home "off-main"); Seed; $W.onMain = $false; Range @("surfaces/pwa/page/app.js")
    $l = Pass; $null = Pass
    Check ($W.deploys -eq 0 -and (Whats) -ceq "not-on-main") ("a commit that is not on origin/main is never deployed, and that is told once (" + (Whats) + ")")
    Check (@($W.calls | Where-Object { $_ -like "bundle*" }).Count -eq 0) "and nothing is bundled for it"
    $W = New-World (New-Home "main-unknown"); Seed; $W.onMain = $null; Range @("surfaces/pwa/page/app.js")
    $null = Pass; $W.now = $t0.AddMinutes(30); $null = Pass
    Check ($W.deploys -eq 0 -and (Whats) -ceq "unreadable" -and @($W.calls | Where-Object { $_ -like "upstream*" }).Count -eq 1) "origin/main that cannot be asked: not deployed, told once, asked again an hour later"
    $W = New-World (New-Home "moved"); Seed; $W.movedTo = $cC; Range @("surfaces/pwa/page/app.js")
    $l = Pass
    Check ($W.deploys -eq 1 -and $W.told.Count -eq 0 -and (Says $l "moved off the commit")) "a checkout that moved off the commit checked: nothing deployed, no failure, the next pass looks again"
    Check ($null -eq (Read-HordeRelayPublishState -HordeHome $W.home).value.failure) "and no failure is kept"

    Write-Host ""
    Write-Host "--- a trouble that comes back is told again ---" -ForegroundColor Cyan
    $W = New-World (New-Home "episodes"); Seed; Range @("relays/zorbrelay/worker/site.js")
    $null = Pass; $null = Pass
    Check ((Whats) -ceq "worker-changed") "a Worker change is told once"
    Write-HordeRelayDeployed -HordeHome $W.home -Revision ([pscustomobject]@{ commit = $cB; clean = $true }) -Version $v2 -Relay "zorbrelay" -Origin $origin -At $t0.AddMinutes(5)
    $null = Pass
    Write-HordeRelayDeployed -HordeHome $W.home -Revision ([pscustomobject]@{ commit = $cA; clean = $true }) -Version $v1 -Relay "zorbrelay" -Origin $origin -At $t0.AddMinutes(6)
    $null = Pass
    Check ((Whats) -ceq "worker-changed,worker-changed") "after the page was current again, the same trouble is told again"
    $W = New-World (New-Home "pending-cap"); Seed
    $s0 = New-HordeRelayPublishState
    foreach ($n in 1..25) { $null = Add-HordeRelayPublishNotice -State $s0 -What "dirty" -Key ("k" + $n) -Id ("id" + $n) -At $t0 }
    Check (@($s0.pending).Count -eq 20 -and $s0.pending[19].id -ceq "id25") "at most the last 20 notices wait"

    Write-Host ""
    Write-Host "--- a Worker that differs is told again only when it changes ---" -ForegroundColor Cyan
    # An index.html change: the Worker imports it as text, so the bundle differs from the deployed one,
    # and stays so through every later merge that changes only the page.
    $W = New-World (New-Home "index-html"); Seed
    $W.bundles[$cB] = "9" * 64; $W.bundles[$cC] = "9" * 64; $W.bundles[$cD] = "9" * 64; $W.bundles[$cE] = "8" * 64
    Range @("surfaces/pwa/page/index.html")
    $null = Pass
    foreach ($c in @($cC, $cD)) { $W.head = $c; $W.diffs[$cA + ".." + $c] = [string[]]@("surfaces/pwa/page/index.html", "surfaces/pwa/page/app.js"); $W.now = $W.now.AddMinutes(10); $null = Pass }
    Check ($W.deploys -eq 0 -and (Whats) -ceq "worker-changed") ("three page merges after an index.html change send one notice (" + (Whats) + ")")
    $W.head = $cE; $W.diffs[$cA + ".." + $cE] = [string[]]@("surfaces/pwa/page/index.html", "relay/js/protocol.js"); $null = Pass
    Check ((Whats) -ceq "worker-changed,worker-changed") "a later change that changes the Worker that would ship is told again"

    Write-Host ""
    Write-Host "--- the supervisor's pointer names only a supervisor's home ---" -ForegroundColor Cyan
    # This suite's folders are under the temp folder, so a temp root of its own stands for it.
    $notTemp = Join-Path $work "not-the-temp"
    $tend = New-Home "pointed-home"
    [void][System.IO.Directory]::CreateDirectory((Join-Path $tend "settings"))
    [System.IO.File]::WriteAllText((Join-Path $tend "settings\service-definitions.json"), '{ "schemaVersion": 1, "settings": { } }')
    $bare = New-Home "pointed-bare"
    $pf = Join-Path $work "pointer-cases.txt"
    $read = { param([string]$Text, [string]$TempRoot = $notTemp) [System.IO.File]::WriteAllText($pf, $Text); return (Read-HordeRelayTendHomePointer -Path $pf -TempRoot $TempRoot) }
    $ok = & $read $tend
    Check ($ok.state -ceq "known" -and $ok.value -ceq $tend.TrimEnd('\')) "CONTROL: a full local path to a home the supervisor runs in is taken"
    $r = & $read $tend ""
    Check ($r.state -ceq "unknown" -and $r.reason -like "*under the temp folder*") "a home under the temp folder is refused"
    $r = & $read $bare
    Check ($r.state -ceq "unknown" -and $r.reason -like "*not a Horde home*") "a folder that is not a supervisor's home is refused"
    foreach ($bad in @("relative\home", "C:home", "\\server\share\home", "\\?\C:\home", ($tend + "\..\pointed-home"), "C:\home:stream", "\home")) {
        $r = & $read $bad
        Check ($r.state -ceq "unknown" -and $r.reason -like "*not a full local path*") ("'" + $bad + "' is not a full local path, and is refused")
    }

    Write-Host ""
    Write-Host "--- the hand deploy's second home ---" -ForegroundColor Cyan
    $mine = New-Home "hand-mine"
    [System.IO.File]::WriteAllText($pf, $tend)
    $ch = Get-HordeRelayDeployAlsoRecordIn -Mine $mine -PointerPath $pf -TempRoot $notTemp
    Check ($ch.also -ceq $tend.TrimEnd('\') -and $ch.note -like "*recorded there as well as here*") "from a home that is not a test's, the supervisor's home is recorded in too, and said"
    $ch = Get-HordeRelayDeployAlsoRecordIn -Mine $tend -PointerPath $pf -TempRoot $notTemp
    Check ($ch.also -ceq "" -and $ch.note -ceq "") "from the supervisor's own home, once is enough"
    $ch = Get-HordeRelayDeployAlsoRecordIn -Mine $mine -PointerPath $pf
    Check ($ch.also -ceq "" -and $ch.note -ceq "") "from a test's home, nothing else is written to"
    [System.IO.File]::WriteAllText($pf, $bare)
    $ch = Get-HordeRelayDeployAlsoRecordIn -Mine $mine -PointerPath $pf -TempRoot $notTemp
    Check ($ch.also -ceq "" -and $ch.note -like "*recorded only in*not a Horde home*") "a refused pointer: recorded only in its own home, and it says so"
    $ch = Get-HordeRelayDeployAlsoRecordIn -Mine $mine -PointerPath (Join-Path $work "no-such-pointer.txt") -TempRoot $notTemp
    Check ($ch.also -ceq "" -and $ch.note -ceq "") "no pointer: its own home only, nothing to say"

    Write-Host ""
    Write-Host "--- telling ---" -ForegroundColor Cyan
    $W = New-World (New-Home "tell-off")
    $l = Pass -Policy ([pscustomobject]@{ tellWarchief = $false })
    Check ($W.tellCalls -eq 0 -and (Says $l "telling is switched off")) "with telling switched off nobody is told, and the pass says so"
    Check (@((Read-HordeRelayPublishState -HordeHome $W.home).value.pending).Count -eq 1) "the notice waits"
    $null = Pass
    Check ($W.tellCalls -eq 1 -and $W.told.Count -eq 1) "the next pass that may tell tells it, once"

    Write-Host ""
    Write-Host "--- the lock stops a second deploy, whatever its home ---" -ForegroundColor Cyan
    # The machine's lock, held by another process: a child of this suite, under a name of this suite's
    # own, so the real one is never touched. It writes a file once it holds the lock.
    $lockName = "Global\HordeRelayDeploySuite-" + [guid]::NewGuid().ToString("N")
    Check ((Get-HordeRelayDeployLockName -Relay "zorbrelay") -ceq "Global\HordeRelayDeploy-zorbrelay") "the real lock is the machine's, named by the relay, not by a home"
    $marker = Join-Path $work "lock-held.txt"
    $holder = Join-Path $work "hold-lock.ps1"
    [System.IO.File]::WriteAllText($holder, ('$m = New-Object System.Threading.Mutex -ArgumentList $false, "' + $lockName + '"; [void]$m.WaitOne(); [System.IO.File]::WriteAllText("' + $marker + '", "held"); Start-Sleep -Seconds 60'))
    $child = Start-Process -FilePath ([System.IO.Path]::Combine([System.Environment]::SystemDirectory, "WindowsPowerShell\v1.0\powershell.exe")) -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $holder) -WindowStyle Hidden -PassThru
    try {
        $deadline = [datetime]::UtcNow.AddSeconds(30)
        while (-not [System.IO.File]::Exists($marker) -and [datetime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
        Check ([System.IO.File]::Exists($marker)) "CONTROL: another process holds the lock"
        $hh = New-Home "lock"; $hh2 = New-Home "lock-other-home"
        $a = Invoke-HordeRelayDeploy -Relay "zorbrelay" -HordeHome $hh -LockName $lockName -Revision ([pscustomobject]@{ commit = $cC; clean = $true })
        $a2 = Invoke-HordeRelayDeploy -Relay "zorbrelay" -HordeHome $hh2 -LockName $lockName -Revision ([pscustomobject]@{ commit = $cC; clean = $true })
        Check ($a.state -ceq "unknown" -and $a.reason -ceq (Get-HordeRelayDeployBusyReason) -and $a2.state -ceq "unknown") "a deploy while another process holds the lock is refused as busy, from any home"
        Check ($script:relayDeploys -eq 0) "and the relay's deploy was never called"
        Check (-not [System.IO.File]::Exists((Get-HordeRelayDeployedPath -HordeHome $hh))) "and nothing was recorded"
        # A handle of this suite's own keeps the lock alive when its holder dies, so it is ABANDONED,
        # not gone - as when the tend is killed while another process waits on the same lock.
        $keep = New-Object System.Threading.Mutex -ArgumentList $false, $lockName
    } finally { if (-not $child.HasExited) { $child.Kill() }; $child.WaitForExit(10000) | Out-Null; $child.Dispose() }
    # The holder ended without letting go: the lock is abandoned, and the next deploy takes it.
    $a = Invoke-HordeRelayDeploy -Relay "zorbrelay" -HordeHome $hh -LockName $lockName -Revision ([pscustomobject]@{ commit = $cC; clean = $true })
    Check ($a.state -ceq "known" -and $script:relayDeploys -eq 1) "a lock left by a process that ended is taken, and the deploy runs"
    $again = Enter-HordeRelayDeployLock -Name $lockName
    Check ($null -ne $again) "a deploy lets go of the lock when it ends"
    Exit-HordeRelayDeployLock -Lock $again
    $keep.Dispose()
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
    $hh = New-Home "hand-same-second"
    Write-HordeRelayDeployed -HordeHome $hh -Revision ([pscustomobject]@{ commit = $cC; clean = $true }) -Version $v1 -Relay "zorbrelay" -Origin $origin -At $t0
    $id1 = (Read-HordeRelayDeployed -HordeHome $hh).value.id
    Write-HordeRelayDeployed -HordeHome $hh -Revision ([pscustomobject]@{ commit = $cC; clean = $true }) -Version $v1 -Relay "zorbrelay" -Origin $origin -At $t0
    $id2 = (Read-HordeRelayDeployed -HordeHome $hh).value.id
    Check ($id1 -cmatch '\A[0-9a-f]{32}\z' -and $id2 -cmatch '\A[0-9a-f]{32}\z' -and $id1 -cne $id2) "two deploys recorded in the same second are told apart, by their ids"
    $hh = New-Home "hand-two-homes"; $tendHome = New-Home "hand-tend-home"
    $null = Invoke-HordeRelayDeploy -Relay "zorbrelay" -HordeHome $hh -AlsoRecordIn $tendHome -Revision ([pscustomobject]@{ commit = $cC; clean = $true })
    $r1 = Read-HordeRelayDeployed -HordeHome $hh; $r2 = Read-HordeRelayDeployed -HordeHome $tendHome
    Check ($r1.state -ceq "known" -and $r2.state -ceq "known" -and $r1.value.id -ceq $r2.value.id -and $r2.value.commit -ceq $cC) "a deploy from another home records it in the supervisor's home too, as one deploy"
    $ptr = Join-Path $work "pointer\relay-tend-home.txt"
    Write-HordeRelayTendHomePointer -Path $ptr -HordeHome $tendHome
    Check (([System.IO.File]::ReadAllText($ptr)).Trim() -ceq [System.IO.Path]::GetFullPath($tendHome).TrimEnd('\')) "the supervisor's pointer names its home"
    Check ((Read-HordeRelayTendHomePointer -Path (Join-Path $work "no-pointer.txt")).state -ceq "absent") "no pointer names no home"
    $hh = New-Home "hand-failed"; $script:relayAnswer = "fail"
    $a = Invoke-HordeRelayDeploy -Relay "zorbrelay" -HordeHome $hh -Revision ([pscustomobject]@{ commit = $cC; clean = $true })
    Check ($a.state -ceq "unknown" -and -not [System.IO.File]::Exists((Get-HordeRelayDeployedPath -HordeHome $hh))) "a deploy that failed records nothing"
    Check ($a.reason.Contains("relay 'zorbrelay' was not deployed: not logged in") -and $null -eq $a.PSObject.Properties["live"]) ("CONTROL: a deploy that never went out says 'was not deployed', unmarked (" + $a.reason + ")")
    $hh = New-Home "hand-live"; $script:relayAnswer = "live"
    $a = Invoke-HordeRelayDeploy -Relay "zorbrelay" -HordeHome $hh -Revision ([pscustomobject]@{ commit = $cC; clean = $true })
    $liveMember = $(if (Test-HordeAnswer $a) { $a.PSObject.Properties["live"] } else { $null })
    Check ($a.state -ceq "unknown" -and $null -ne $liveMember -and $liveMember.Value -eq $true -and $a.reason.StartsWith("relay 'zorbrelay' IS deployed, but its sign-in failed") -and $a.reason -notmatch 'not deployed') ("a deploy that went out and failed its check comes back through the port marked live, worded 'IS deployed, but' (" + $a.reason + ")")
    Check (-not [System.IO.File]::Exists((Get-HordeRelayDeployedPath -HordeHome $hh))) "and it records nothing, so the page is not taken as current"
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
    Write-Host "--- the tend's own call, past the test-home guard ---" -ForegroundColor Cyan
    $W = New-World (New-Home "from-tend"); Seed; Range @("surfaces/pwa/page/app.js")
    $ptr = Join-Path $work "from-tend-pointer\relay-tend-home.txt"
    $l = @(Invoke-HordeRelayPublishFromTend -HordeHome $W.home -Teller $teller -Root $work -Tools (New-Tools) -TempRoot (Join-Path $work "not-the-temp") -PointerPath $ptr)
    Check ($W.deploys -eq 1 -and (Says $l "DEPLOYED")) "a home that is not a test's takes the step, with the tools handed in"
    Check ([System.IO.File]::Exists($ptr) -and ([System.IO.File]::ReadAllText($ptr)).Trim() -ceq [System.IO.Path]::GetFullPath($W.home).TrimEnd('\')) "and points the machine at its home"
    $l = @(Invoke-HordeRelayPublishFromTend -HordeHome $W.home -Teller $teller -Root $work -Tools (New-Tools) -PointerPath (Join-Path $work "p2.txt"))
    Check ((Says $l "it is a test's") -and -not [System.IO.File]::Exists((Join-Path $work "p2.txt"))) "a home under the temp folder looks at nothing and points nowhere"

    Write-Host ""
    Write-Host "--- the revision tool's answers, on a repository of this suite's own ---" -ForegroundColor Cyan
    $git = Join-Path $work "gitrepo"
    [void][System.IO.Directory]::CreateDirectory((Join-Path $git "relays\zorb"))
    $gitRun = { param([string[]]$GitArgs) $null = & git -C $git @GitArgs }
    & $gitRun @("init", "-q"); & $gitRun @("config", "user.email", "suite@example.invalid"); & $gitRun @("config", "user.name", "suite")
    [System.IO.File]::WriteAllText((Join-Path $git "relays\zorb\a.js"), "export const a = 1;`n")
    & $gitRun @("add", "-A"); & $gitRun @("commit", "-q", "-m", "one")
    $c1 = ("" + (& git -C $git rev-parse HEAD)).Trim()
    $rv = Get-HordeRelayPublishRevision -Checkout $git
    Check ($rv.state -ceq "known" -and $rv.value.commit -ceq $c1 -and $rv.value.clean -eq $true) "CONTROL: a clean checkout reads as clean"
    [System.IO.File]::AppendAllText((Join-Path $git "relays\zorb\a.js"), "// a change of its own`n")
    Check ((Get-HordeRelayPublishRevision -Checkout $git).value.clean -eq $false) "a checkout with a changed tracked file is not clean"
    & $gitRun @("checkout", "-q", "--", ".")
    [void][System.IO.Directory]::CreateDirectory((Join-Path $git "other"))
    & $gitRun @("mv", "relays/zorb/a.js", "other/a.js"); & $gitRun @("commit", "-q", "-m", "move")
    $c2 = ("" + (& git -C $git rev-parse HEAD)).Trim()
    $ch = Get-HordeRelayPublishChanged -Checkout $git -Base $c1 -Head $c2
    Check ($ch.state -ceq "known" -and (@($ch.value.paths) -ccontains "relays/zorb/a.js") -and (@($ch.value.paths) -ccontains "other/a.js")) "a file moved out of a folder is both its old path and its new one"
    Check ((Get-HordeRelayPublishChanged -Checkout $git -Base "--output=x" -Head $c2).state -ceq "unknown") "a base that is not a commit id never reaches the revision tool"
    # Refused by their words, before any request: the addresses are this machine's closed port.
    Check ((Get-HordeRelayPublishUrl -Url "http://127.0.0.1:9/app/sw.js").reason -like "only an https address*") "an address that is not https is never asked"
    Check ((Get-HordeRelayPublishUrl -Url "https://127.0.0.1:9@evil.invalid/").reason -like "only an https address*") "an https address with a user in it is never asked"

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
