# DOES THE SUPERVISOR'S PUBLISH STEP DRIVE THE REAL DEPLOY FUNCTION TO THE END - ITS LINES LOGGED AT THE
# STEP'S OWN TIME, ITS RECORD WRITTEN - AND NOT ONLY A STAND-IN OF IT?
#
# The live failure of 2026-10-14T20:41:29Z: the tend's publish step (cli/RelayPublish.ps1) handed its
# log block to Invoke-HordeRelayDeploy (cli/RelayDeploy.ps1) as -Say. The block named $now and $HordeHome
# without binding them, so PowerShell looked them up where the block RAN: inside Invoke-HordeRelayDeploy,
# whose parameter $Now (variable names ignore case) is its clock, a script block. The first line the
# deploy said threw "Cannot process argument transformation on parameter 'At' ... ScriptBlock ... to
# System.DateTime", and every automatic deploy failed. A deploy by hand passes a -Say that names
# neither, so it worked. test/test-relay-publish.ps1 did not see it: its Deploy tool is a stand-in that
# calls -Say from a scope with no $Now of its own, and the real Deploy tool is only ever shown refusing
# a test's home, before the deploy function runs.
#
# Here the step's Deploy tool makes EXACTLY the real tool's call (asserted against the real tool's own
# text) into the REAL Invoke-HordeRelayDeploy, on a relay of this suite's own, registered from a folder
# it makes in its temp folder, whose deploy only counts its calls and says one line. NOTHING IS
# DEPLOYED FOR REAL: no relay of the repository is loaded. Every home is under the temp folder.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "Home", "ModuleSettings", "Heartbeat", "Services", "ServicesFiles", "ServiceHostPort", "Schedule")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
foreach ($f in @("ServicesAct", "ServicesTend", "ServicesTell")) { . (Join-Path $root ("cli\" + $f + ".ps1")) }
. (Join-Path $root "relays\Port.ps1")
. (Join-Path $root "cli\RelayDeploy.ps1")
. (Join-Path $root "cli\RelayPublish.ps1")

$work = Join-Path $env:TEMP ("horde-relay-publish-real-" + [guid]::NewGuid().ToString("N"))
[void][System.IO.Directory]::CreateDirectory($work)
$t0 = [datetime]::new(2026, 10, 14, 12, 0, 0, [System.DateTimeKind]::Utc)
$cA = "a" * 40; $cB = "b" * 40
$origin = "https://zorbreal.example"
$siteMap = Get-HordeRelayDeploySiteSources
$shippedHere = [pscustomobject]@{ workerPrefixes = [string[]]@("relays/zorbreal/"); workerExcept = [string[]]@("relays/zorbreal/test/")
    workerFiles = [string[]]@("cli/RelayDeploy.ps1", "relays/Port.ps1")
    pageFiles = [string[]]@(@($siteMap.Values) + @(Get-HordeRelayDeployBuildFiles)); buildFiles = [string[]]@(Get-HordeRelayDeployBuildFiles)
    sharedFiles = [string[]]@() }

try {
    Write-Host ""
    Write-Host "--- the stand-in makes the real tool's call ---" -ForegroundColor Cyan
    $call = 'Invoke-HordeRelayDeploy -HordeHome $HordeHome -Say $Say -Revision $rev.value'
    Check (("" + (New-HordeRelayPublishTools).Deploy).Contains($call)) "CONTROL: the real Deploy tool calls the deploy function with the step's -Say, as this suite's tool does"

    # This suite's own relay: deployable, counting, and saying a line through -Say as a real relay does.
    $relay = Join-Path $work "repo\relays\zorbreal"
    [void][System.IO.Directory]::CreateDirectory($relay)
    [System.IO.File]::WriteAllText((Join-Path $relay "capabilities.json"), [System.IO.File]::ReadAllText((Join-Path $root "relays\local\capabilities.json")).Replace('"relay": "local"', '"relay": "zorbreal"'))
    $script:relayDeploys = 0
    $none = { param($State) return (New-HordeUnknown -Reason "not used here") }
    $null = Register-HordeRelay -Folder $relay -Connect $none -Put $none -Get $none -Watch $none -Ack $none -Deploy {
        param($Site, $Say, $HordeHome)
        $script:relayDeploys++
        & $Say "the relay's own line"
        return (New-HordeKnown -Value ([pscustomobject]@{ origin = $origin }))
    }
    Check ((@(Get-HordeRelayDeployable) -join ",") -ceq "zorbreal") "CONTROL: this suite's relay is the only one that can be deployed"

    $hh = Join-Path $work "home"
    [void][System.IO.Directory]::CreateDirectory($hh)
    Write-HordeRelayDeployed -HordeHome $hh -Revision ([pscustomobject]@{ commit = $cA; clean = $true }) -Version "1111111111111111" -Relay "zorbreal" -Origin $origin -At $t0.AddDays(-1)
    $script:clock = $t0
    $tools = @{
        Now      = { return $script:clock }
        Sleep    = { param($Ms) $script:clock = $script:clock.AddMilliseconds($Ms) }
        NewId    = { return [guid]::NewGuid().ToString() }
        Head     = { param($Checkout) return (New-HordeKnown -Value ([pscustomobject]@{ commit = $cB; clean = $true })) }
        # PR 384 (T-0333): the step asks how the record's commit relates to the checkout before it deploys. The
        # seeded record ($cA) is behind the checkout ($cB), as a normal deploy is; without this entry the
        # call throws, the step reads it as unknown and never reaches the deploy function.
        Ancestry = { param($Checkout, $Base, $Head) return (New-HordeKnown -Value "behind") }
        Diff     = { param($Checkout, $Base, $Head) return (New-HordeKnown -Value ([pscustomobject]@{ paths = [string[]]@("surfaces/pwa/page/app.js") })) }
        Load     = $null
        Shipped  = { param($Checkout) return (New-HordeKnown -Value $shippedHere) }
        Upstream = { param($Checkout, $Commit) return (New-HordeKnown -Value $true) }
        Bundle   = { param($Checkout, $Commit) return (New-HordeKnown -Value ([pscustomobject]@{ sha256 = ("0" * 64) })) }
        # The real tool's call, past its test-home guard and its read of the checkout's revision.
        Deploy   = {
            param($HordeHome, $Say, $Checkout, $Commit)
            $rev = New-HordeKnown -Value ([pscustomobject]@{ commit = $Commit; clean = $true })
            return (Invoke-HordeRelayDeploy -HordeHome $HordeHome -Say $Say -Revision $rev.value)
        }
        Http     = { param($Url) return (New-HordeKnown -Value ([pscustomobject]@{ status = 404; body = ""; sha256 = "" })) }
        SiteMap  = { return $siteMap }
    }
    $teller = { param($Notices, $HordeHome, $Policy) return [pscustomobject]@{ told = @(@($Notices) | ForEach-Object { $_.id }); problem = "" } }

    Write-Host ""
    Write-Host "--- a pass that deploys, through the real deploy function ---" -ForegroundColor Cyan
    $lines = @(Invoke-HordeRelayPublishStep -HordeHome $hh -Tools $tools -Policy ([pscustomobject]@{ tellWarchief = $true }) -Teller $teller -Checkout $work)
    $bad = @($lines | Where-Object { "" + $_ -like "*the deploy did not work*" -or "" + $_ -like "*the deploy failed*" })
    foreach ($l in $bad) { Write-Host ("         said: " + $l) -ForegroundColor DarkYellow }
    Check ($bad.Count -eq 0) "the deploy did not fail"
    Check ($script:relayDeploys -eq 1) ("the relay's deploy was called, once (" + $script:relayDeploys + ")")
    $rec = Read-HordeRelayDeployed -HordeHome $hh
    Check ($rec.state -ceq "known" -and $rec.value.commit -ceq $cB -and $rec.value.clean -eq $true -and $rec.value.relay -ceq "zorbreal") "the deploy recorded the commit the step checked"
    $logPath = Get-HordeRelayPublishLogPath -HordeHome $hh
    $log = $(if ([System.IO.File]::Exists($logPath)) { [System.IO.File]::ReadAllText($logPath) } else { "" })
    $stamp = $t0.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
    Check ($log.Contains($stamp + "   built the phone app")) "the deploy's own line is in the step's log, at the step's time"
    Check ($log.Contains($stamp + "   the relay's own line")) "and so is the relay's"
} finally {
    if ($work -like "*horde-relay-publish-real-*" -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

Complete-HordeSuite -Success "the supervisor's publish step runs the real deploy function to the end, logging its lines at the step's time and recording the commit"
