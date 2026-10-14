# DOES THE HOSTED RELAY BUNDLE ITS WORKER FROM A TREE, OFFLINE, THE SAME EVERY TIME - AND DIFFERENTLY
# ONLY WHEN THE WORKER'S CODE DIFFERS?
#
# relays/cloudflare/Bundle.ps1, the relay's -Bundle block (relays/Port.ps1, DEPLOYING), which the
# supervisor uses to tell whether a change to a file the Worker shares with the phone app changes the
# Worker (cli/RelayPublish.ps1). Every bundle is the pinned wrangler's dry run on a tree this suite copies
# into its temp folder from this checkout, with requests pointed at a closed port: nothing is deployed,
# nothing is sent, and no login is used.
#
# THE PINNED WRANGLER IS NEEDED, ALREADY INSTALLED (a deploy installs it; this suite does not). Without
# it, or without node, the suite skips and exits 3.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "relays\Port.ps1")
foreach ($f in @(Get-HordeRelayFiles)) { . $f }

if ((Find-HordeCloudflareRelayNode) -eq "" -or -not (Test-Path -LiteralPath (Get-HordeCloudflareRelayWranglerScript -ToolsHome (Get-HordeCloudflareRelayToolsHome)) -PathType Leaf)) {
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Complete-HordeSuite -Success "skipped: no node or no pinned wrangler installed here" -PassCode 3
}

$work = Join-Path $env:TEMP ("horde-cf-bundle-test-" + [guid]::NewGuid().ToString("N").Substring(0, 12))

function New-Tree {
    # A tree with what the Worker is built from: the relay's config and code, and the files outside it
    # that the code imports (the protocol and the page), copied from this checkout.
    param([string]$Name)
    $t = Join-Path $work $Name
    foreach ($d in @("relays\cloudflare\worker", "relay\js", "surfaces\pwa\page")) {
        [void][System.IO.Directory]::CreateDirectory((Join-Path $t $d))
        Copy-Item -Path (Join-Path (Join-Path $root $d) "*") -Destination (Join-Path $t $d) -Recurse -Force
    }
    # The relay folder's own files too: the Worker imports its capabilities.json.
    Get-ChildItem -LiteralPath (Join-Path $root "relays\cloudflare") -File | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $t "relays\cloudflare") }
    return $t
}
function Bundle {
    param([string]$Tree)
    $scratch = Join-Path $work ("b-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    [void][System.IO.Directory]::CreateDirectory($scratch)
    return (Get-HordeRelayBundle -Name "cloudflare" -Tree $Tree -Work $scratch)
}

try {
    Write-Host ""
    Write-Host "--- the same tree bundles the same, wherever it is ---" -ForegroundColor Cyan
    $one = Bundle $root
    $two = Bundle $root
    Check ($one.state -ceq "known" -and $one.value.sha256 -cmatch '\A[0-9a-f]{64}\z') ("the checkout's Worker bundles, offline (" + $(if ($one.state -ceq "known") { $one.value.sha256.Substring(0, 12) } else { $one.reason }) + ")")
    Check ($two.state -ceq "known" -and $two.value.sha256 -ceq $one.value.sha256) "a second bundle of it hashes the same: what the dry run writes beside the code (its README's time) is left out"
    $copy = New-Tree "copy"
    $three = Bundle $copy
    Check ($three.state -ceq "known" -and $three.value.sha256 -ceq $one.value.sha256) "a copy of the tree in another folder hashes the same: no absolute path is in the bundle"

    Write-Host ""
    Write-Host "--- a shared file changes the bundle only when the Worker uses the change ---" -ForegroundColor Cyan
    $unused = New-Tree "unused"
    Add-Content -LiteralPath (Join-Path $unused "relay\js\protocol.js") -Value "`nexport function hordeBundleSuiteUnused(x) { return x + 1; }`n"
    $four = Bundle $unused
    Check ($four.state -ceq "known" -and $four.value.sha256 -ceq $one.value.sha256) "a function added to the protocol that the Worker does not use leaves the bundle as it was"
    $used = New-Tree "used"
    Add-Content -LiteralPath (Join-Path $used "relays\cloudflare\worker\index.js") -Value "`nexport const hordeBundleSuiteMark = 1;`n"
    $five = Bundle $used
    Check ($five.state -ceq "known" -and $five.value.sha256 -cne $one.value.sha256) "a change to the Worker's own code changes the bundle"

    Write-Host ""
    Write-Host "--- what cannot be bundled is unknown ---" -ForegroundColor Cyan
    $broken = New-Tree "broken"
    Add-Content -LiteralPath (Join-Path $broken "relays\cloudflare\worker\index.js") -Value "`nexport const = ;`n"
    Check ((Bundle $broken).state -ceq "unknown") "a Worker that does not parse is unknown"
    $none = Join-Path $work "empty"; [void][System.IO.Directory]::CreateDirectory($none)
    Check ((Bundle $none).state -ceq "unknown") "a tree with no config for this relay is unknown"
    $tested = New-Tree "tested"
    $cfg = Join-Path $tested "relays\cloudflare\wrangler.json"
    [System.IO.File]::WriteAllText($cfg, ([System.IO.File]::ReadAllText($cfg)).Replace('"HORDE_RELAY_ORIGIN"', '"HORDE_RELAY_TEST_AUTH": "x", "HORDE_RELAY_ORIGIN"'))
    Check ((Bundle $tested).state -ceq "unknown") "a tree whose config names a test binding is not bundled"

    Write-Host ""
    Write-Host "--- the supervisor's real tools together: load, shipped, bundle ---" -ForegroundColor Cyan
    # In a child process (the relays register once a process), on a clone of this checkout's commit in
    # the suite's folder: the step with the real revision tool, Load, Shipped and Bundle; only whether
    # the commit is on origin/main, the deploy and the requests are stand-ins, and the deploy only writes
    # a line. The code under test is this checkout's; the clone is what it looks at.
    $clone = Join-Path $work "clone"; $hh = Join-Path $work "tend-home"; $out = Join-Path $work "driver-out.txt"
    [void][System.IO.Directory]::CreateDirectory($hh)
    $null = & git clone -q --shared --no-checkout $root $clone
    $head0 = ("" + (& git -C $root rev-parse HEAD)).Trim()
    $null = & git -C $clone -c advice.detachedHead=false checkout -q $head0
    $null = & git -C $clone config user.email suite@example.invalid; $null = & git -C $clone config user.name suite
    $driver = Join-Path $work "driver.ps1"
    [System.IO.File]::WriteAllText($driver, @'
param([string]$Root, [string]$Clone, [string]$HordeHome, [string]$Out)
$ErrorActionPreference = "Stop"
foreach ($f in @("Tristate", "Home", "ModuleSettings", "Heartbeat", "Services", "ServicesFiles", "ServiceHostPort")) { . (Join-Path $Root ("core\" + $f + ".ps1")) }
foreach ($f in @("ServicesAct", "ServicesTell", "RelayDeploy", "RelayPublish")) { . (Join-Path $Root ("cli\" + $f + ".ps1")) }
$t = New-HordeRelayPublishTools
$t.Upstream = { param($C, $X) return (New-HordeKnown -Value $true) }
$t.Deploy = { param($H, $S, $C, $X) [System.IO.File]::AppendAllText($Out, ("DEPLOY " + $X + "`n")); return (New-HordeUnknown -Reason "suite: nothing deployed") }
$t.Http = { param($U) return (New-HordeUnknown -Reason "suite: no request") }
$t.Sleep = { param($Ms) }
foreach ($l in @(Invoke-HordeRelayPublishStep -HordeHome $HordeHome -Tools $t -Checkout $Clone)) { [System.IO.File]::AppendAllText($Out, ($l + "`n")) }
'@)
    $runStep = {
        if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }
        $null = & ([System.IO.Path]::Combine([System.Environment]::SystemDirectory, "WindowsPowerShell\v1.0\powershell.exe")) -NoProfile -ExecutionPolicy Bypass -File $driver -Root $root -Clone $clone -HordeHome $hh -Out $out
        if (Test-Path -LiteralPath $out) { return [System.IO.File]::ReadAllText($out) }
        return ""
    }
    $seed = {
        param([string]$Commit)
        $rel = Join-Path $hh "relay"; [void][System.IO.Directory]::CreateDirectory($rel)
        Remove-Item -LiteralPath (Join-Path $rel "publish-state.json") -ErrorAction SilentlyContinue
        [System.IO.File]::WriteAllText((Join-Path $rel "deployed.json"), ('{"schemaVersion":1,"id":"' + ("0" * 32) + '","commit":"' + $Commit + '","clean":true,"version":"x","relay":"cloudflare","origin":"https://suite.invalid","at":"2026-10-14T00:00:00Z"}'))
    }
    Add-Content -LiteralPath (Join-Path $clone "surfaces\pwa\page\app.js") -Value "`n// a page change of this suite's"
    Add-Content -LiteralPath (Join-Path $clone "relay\js\protocol.js") -Value "`nexport function hordeSuiteUnusedHere(x) { return x; }"
    $null = & git -C $clone commit -qam "suite: page and protocol"
    $c1 = ("" + (& git -C $clone rev-parse HEAD)).Trim()
    & $seed $head0
    $said = & $runStep
    Check ($said.Contains("DEPLOY " + $c1) -and $said.Contains(": the same")) ("a page change and an unused protocol change, bundled alike by the real tools, is handed to the deploy (" + ($said -replace "`n", " | ") + ")")
    $null = & git -C $clone -c advice.detachedHead=false checkout -q $head0
    Add-Content -LiteralPath (Join-Path $clone "relays\cloudflare\worker\index.js") -Value "`nexport const hordeSuiteMark = 1;"
    Add-Content -LiteralPath (Join-Path $clone "surfaces\pwa\page\app.js") -Value "`n// and a page change"
    $null = & git -C $clone commit -qam "suite: worker"
    & $seed $head0
    $said = & $runStep
    Check (-not ($said -cmatch "(?m)^DEPLOY ") -and $said.Contains("Worker changed") -and -not $said.Contains("bundled at")) ("a change to the Worker's own code is warned, and nothing is bundled (" + ($said -replace "`n", " | ") + ")")
} finally {
    if ($work -like "*horde-cf-bundle-test-*" -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
Check (-not (Test-Path -LiteralPath $work)) "the suite's folder is gone"

Complete-HordeSuite -Success "the Worker bundles offline from any tree, the same every time, and differently only when its code does"
