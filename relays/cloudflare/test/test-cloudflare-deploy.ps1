# DOES `horde relay deploy` STORE THE GOOGLE CLIENT'S TWO VALUES THROUGH A PIPE AND NEVER SAY THEM, DEPLOY
# THE PRODUCTION CONFIG WITH THE APP BUILT FOR ITS OWN ORIGIN, AND STOP AT THE FIRST STEP THAT FAILS?
#
# Relay PR 8a. Every wrangler here is test/fake-wrangler.cjs, named by the relay's own setting
# wranglerScript in a Horde home of the suite's own: NOTHING HERE RUNS THE REAL WRANGLER OR CONTACTS
# CLOUDFLARE, and the Google client file is a fake of the suite's own, never the founder's.
#   1. a deploy, in this process: secrets first - the client's two values and the sign-in allowlist
#      (relay PR 8b: off by default, written as the Worker reads it) - each value on standard input exactly - no byte order
#      mark, no line end - and in no argument; then the deploy; of the production config, which names no
#      test binding, serving the app built with the http transport at its own origin; quiet; and
#      nothing said holds a value; the work folders are gone after; the redirect-address note;
#   2. refusals before wrangler is ever run: a relay origin (relayOrigin) a deploy cannot make, no
#      client file, one inside the repository, one that is not
#      JSON, not a web client, a malformed id, no secret, a relative path, a settings file that fails
#      its checks, a wranglerScript that is not there, an allowlist entry that is neither an email nor a
#      Google account id, an allowlist switched on with nobody on it - each reason free of the values
#      planted in it;
#   3. a wrangler that fails: at a secret, nothing is deployed; at the deploy, it says so; and what it
#      printed reaches the founder with the values hidden;
#   4. which relay: the one that can be deployed, and a refusal for one that cannot;
#   5. the shipped command, end to end: horde relay deploy, its success and failure, and its refusals.
#
# NODE IS NEEDED (the fake is a node script, as wrangler is). Without it the suite skips and exits 3.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "relays\Port.ps1")
foreach ($f in @(Get-HordeRelayFiles)) { . $f }
. (Join-Path $root "cli\RelayDeploy.ps1")
. (Join-Path $root "test\lib\Cli.ps1")
Set-StrictMode -Version Latest

if ((Find-HordeCloudflareRelayNode) -eq "") {
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Complete-HordeSuite -Success "skipped: no node here, so no wrangler, fake or real" -PassCode 3
}

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$work = Join-Path $env:TEMP ("horde-cf-deploy-test-" + [guid]::NewGuid().ToString("N").Substring(0, 12))
$hh = Join-Path $work "home"
New-Item -ItemType Directory -Path (Join-Path $hh "settings") -Force | Out-Null
$log = Join-Path $work "wrangler.log"
$fake = Join-Path $here "fake-wrangler.cjs"
$clientId = "123456789012-fakeclientforhordetests0000000000.apps.googleusercontent.com"
$clientSecret = "GOCSPX-fakeSecretForHordeTests0123456"
# The home's relay origin (Settings.ps1, relayOrigin): the suite's own, under the example subdomain.
$homeOrigin = "https://relay.example.workers.dev"
$dep = [pscustomobject]@{ name = "relay"; origin = $homeOrigin; callback = "/auth/google/callback" }
$callback = $dep.origin + $dep.callback
$env:HORDE_FAKE_WRANGLER_LOG = $log
$env:HORDE_FAKE_WRANGLER_FAIL = ""

function Write-Client {
    # A client file of the suite's own: -Text as is, or a well-formed web client.
    param([string]$Name = "client.json", [string]$Text = "", [switch]$WithCallback)
    if ($Text -eq "") {
        $uris = $(if ($WithCallback) { '"' + $callback + '", ' } else { "" }) + '"http://localhost:8080/"'
        $Text = '{"web":{"client_id":"' + $clientId + '","project_id":"horde-test","auth_uri":"https://accounts.google.com/o/oauth2/auth","token_uri":"https://oauth2.googleapis.com/token","client_secret":"' + $clientSecret + '","redirect_uris":[' + $uris + ']}}'
    }
    $p = Join-Path $work $Name
    [System.IO.File]::WriteAllText($p, $Text, $utf8)
    return $p
}
function Set-Settings {
    # The relay's settings file in the suite's home: -Raw as is, or googleClientFile and wranglerScript.
    param([string]$Client = "", [string]$Wrangler = $fake, [string]$Raw = "", [hashtable]$More = @{}, [string]$Origin = $homeOrigin)
    if ($Raw -eq "") {
        $set = @{ googleClientFile = $Client; wranglerScript = $Wrangler }
        if ($Origin -ne "") { $set["relayOrigin"] = $Origin }
        foreach ($k in @($More.Keys)) { $set[$k] = $More[$k] }
        $Raw = (@{ schemaVersion = 1; settings = $set } | ConvertTo-Json -Depth 4)
    }
    [System.IO.File]::WriteAllText((Join-Path $hh "settings\relay-cloudflare.json"), $Raw, $utf8)
}
function Read-Log {
    # Every run of the fake since the log was last cleared.
    if (-not (Test-Path -LiteralPath $log)) { return @() }
    return @([System.IO.File]::ReadAllLines($log) | Where-Object { $_ -ne "" } | ForEach-Object { $_ | ConvertFrom-Json })
}
function Clear-Log { if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force } }
function Get-DeployLeftovers { return @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "horde-relay-cf-deploy-*" -or $_.Name -like "horde-relay-deploy-*" } | ForEach-Object { $_.FullName }) }
function Deploy {
    # A deploy in this process: { answer; said }.
    $said = New-Object System.Collections.ArrayList
    $a = Invoke-HordeRelayDeploy -Relay "cloudflare" -HordeHome $hh -Say { param($Line) [void]$said.Add("" + $Line) }
    return [pscustomobject]@{ answer = $a; said = @($said) }
}
function Holds-Value { param([string]$Text) return ($Text.Contains($clientSecret) -or $Text.Contains($clientId)) }

try {
    Write-Host ""
    Write-Host "--- 1. a deploy: secrets through a pipe, then the production config with the app ---" -ForegroundColor Cyan
    Set-Settings -Client (Write-Client)
    Clear-Log
    $before = @(Get-DeployLeftovers)
    $d = Deploy
    $runs = @(Read-Log)
    Check ($d.answer.state -ceq "known" -and $d.answer.value.origin -ceq $dep.origin -and $d.answer.value.relay -ceq "cloudflare") ("the deploy answers where the relay now is (" + $d.answer.state + " " + $d.answer.reason + ")")
    Check ($runs.Count -eq 4) ("wrangler ran four times (" + $runs.Count + ")")
    if ($runs.Count -eq 4) {
        $cmds = @($runs | ForEach-Object { (@($_.argv) | Select-Object -First 3) -join " " })
        Check ($cmds[0] -ceq "secret put GOOGLE_CLIENT_ID" -and $cmds[1] -ceq "secret put GOOGLE_CLIENT_SECRET" -and $cmds[2] -ceq "secret put HORDE_RELAY_SIGNIN_ALLOWLIST" -and $cmds[3] -clike "deploy --config*") ("the three secrets first, then the deploy (" + ($cmds -join "; ") + ")")
        Check ($runs[0].stdin -ceq $clientId -and $runs[1].stdin -ceq $clientSecret) "each secret's value is on standard input exactly: no byte order mark, no line end"
        Check ($runs[2].stdin -ceq '{"on":false,"emails":[],"subs":[]}') ("with the settings untouched the allowlist is OFF: signup is public (" + $runs[2].stdin + ")")
        Check ($runs[3].stdin -ceq "") "the deploy is given nothing on its input"
        $argvAll = (@($runs | ForEach-Object { @($_.argv) -join " " }) -join " ")
        Check (-not (Holds-Value $argvAll)) "no value is ever an argument"
        Check (@($runs | Where-Object { $null -eq $_.config -or $_.config.namesTestBinding -or -not $_.config.appIndex -or $_.config.name -cne "relay" -or $_.config.origin -cne $homeOrigin }).Count -eq 0) "every run is given the production config: the home's Worker and origin, no test binding, the app's files beside it"
        $repoFull = [System.IO.Path]::GetFullPath($root).TrimEnd('\') + "\"
        Check (@($runs | Where-Object { ([System.IO.Path]::GetFullPath($_.config.path)).StartsWith($repoFull, [System.StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) "the config wrangler is given lives outside the repository"
        $appConfig = $runs[3].config.appConfig | ConvertFrom-Json
        Check ($appConfig.transport -ceq "http" -and $appConfig.relayOrigin -ceq "") ("the app is built with the http transport at its own origin (" + $runs[3].config.appConfig + ")")
        Check (@($runs | Where-Object { $_.env.WRANGLER_SEND_METRICS -cne "false" -or $_.env.CI -cne "true" -or $null -ne $_.env.PSObject.Properties["HORDE_RELAY_TEST_AUTH"] }).Count -eq 0) "every run is quiet and non-interactive, and none carries the test binding"
    }
    $saidAll = $d.said -join "`n"
    Check (-not (Holds-Value $saidAll) -and $saidAll.Contains("stored GOOGLE_CLIENT_SECRET") -and $saidAll.Contains("https://relay.example.workers.dev")) "what the deploy says names each step and passes wrangler's words on, and holds no value"
    Check ($saidAll.Contains("note: the Google client does not list " + $callback)) "a client that does not list the relay's return address gets a note naming it"
    $after = @(Get-DeployLeftovers | Where-Object { $before -notcontains $_ })
    Check ($after.Count -eq 0) ("the deploy's work folders are gone (" + ($after -join ", ") + ")")
    Set-Settings -Client (Write-Client -WithCallback)
    Clear-Log
    $d = Deploy
    Check ($d.answer.state -ceq "known" -and -not (($d.said -join "`n").Contains("note:"))) "with the return address listed, there is no note"
    Set-Settings -Client (Write-Client -WithCallback) -More @{ signInAllowlistOn = $true; signInAllowlist = "Founder@Example.com, 112233445566778899 ,second@example.org" }
    Clear-Log
    $d = Deploy
    $runs = @(Read-Log)
    Check ($d.answer.state -ceq "known" -and $runs.Count -eq 4 -and $runs[2].stdin -ceq '{"on":true,"emails":["founder@example.com","second@example.org"],"subs":["112233445566778899"]}') ("one setting switches the allowlist on: its emails in lower case, its Google account ids apart (" + $(if ($runs.Count -ge 3) { $runs[2].stdin } else { $d.answer.reason }) + ")")
    Check (-not (($d.said -join " ").Contains("founder@example.com"))) "and what the deploy says names nobody on it"
    # THE WORKER IS THE ORIGIN'S FIRST LABEL: another home's origin deploys another Worker, there.
    Set-Settings -Client (Write-Client -WithCallback) -Origin "https://my-relay.example.workers.dev"
    Clear-Log
    $d = Deploy
    $runs = @(Read-Log)
    Check ($d.answer.state -ceq "known" -and $d.answer.value.origin -ceq "https://my-relay.example.workers.dev" -and $runs.Count -eq 4 -and @($runs | Where-Object { $_.config.name -cne "my-relay" -or $_.config.origin -cne "https://my-relay.example.workers.dev" }).Count -eq 0) ("another home's relayOrigin deploys its own Worker, my-relay, at its own origin (" + $d.answer.state + " " + $d.answer.reason + ")")
    Set-Settings -Client (Write-Client -WithCallback) -More @{ signInAllowlistOn = $false; signInAllowlist = "founder@example.com" }
    Clear-Log
    $d = Deploy
    $runs = @(Read-Log)
    Check ($d.answer.state -ceq "known" -and $runs.Count -eq 4 -and $runs[2].stdin -ceq '{"on":false,"emails":["founder@example.com"],"subs":[]}') "switched off, the list is kept for the day it is switched on, and nobody is shut out"

    Write-Host ""
    Write-Host "--- 2. refusals, before wrangler is ever run ---" -ForegroundColor Cyan
    $inside = Join-Path $root "relays\cloudflare\google-oauth-client.json"
    $bad = @(
        @{ what = "a relay origin that is not a workers.dev origin"; client = (Write-Client); origin = "https://relay.example.com"; like = "is not https://<Worker name>" },
        @{ what = "a relay origin over plain http"; client = (Write-Client); origin = "http://relay.example.workers.dev"; like = "is not https://<Worker name>" },
        @{ what = "a relay origin with no account subdomain"; client = (Write-Client); origin = "https://relay.workers.dev"; like = "is not https://<Worker name>" },
        @{ what = "no client file"; client = (Join-Path $work "absent.json"); like = "there is no Google client file" },
        @{ what = "a client file inside the repository"; client = $inside; like = "inside the repository" },
        @{ what = "a client file that is not JSON"; client = (Write-Client -Name "notjson.json" -Text ("not json " + $clientSecret)); like = "is not a JSON object" },
        @{ what = "a desktop client, not a web one"; client = (Write-Client -Name "installed.json" -Text ('{"installed":{"client_id":"' + $clientId + '","client_secret":"' + $clientSecret + '"}}')); like = "not a web application's client" },
        @{ what = "a malformed client id"; client = (Write-Client -Name "badid.json" -Text ('{"web":{"client_id":"' + $clientSecret + '","client_secret":"' + $clientSecret + '"}}')); like = "no web.client_id" },
        @{ what = "no client secret"; client = (Write-Client -Name "nosecret.json" -Text ('{"web":{"client_id":"' + $clientId + '","client_secret":"short"}}')); like = "no web.client_secret" },
        @{ what = "a relative client path"; client = "secrets\client.json"; like = "absolute path" },
        @{ what = "a wranglerScript that is not there"; client = (Write-Client); wrangler = (Join-Path $work "no-wrangler.js"); like = "wranglerScript names no file" },
        @{ what = "an allowlist entry that is neither an email nor an account id"; client = (Write-Client); more = @{ signInAllowlist = ("founder@example.com, not-an-address " + $clientSecret) }; like = "signInAllowlist" },
        @{ what = "an allowlist switched on with nobody on it"; client = (Write-Client); more = @{ signInAllowlistOn = $true; signInAllowlist = "" }; like = "nobody could sign in" }
    )
    foreach ($c in $bad) {
        Set-Settings -Client $c.client -Wrangler $(if ($c.ContainsKey("wrangler")) { $c.wrangler } else { $fake }) -More $(if ($c.ContainsKey("more")) { $c.more } else { @{} }) -Origin $(if ($c.ContainsKey("origin")) { $c.origin } else { $homeOrigin })
        Clear-Log
        $d = Deploy
        Check ($d.answer.state -ceq "unknown" -and "$($d.answer.reason)".Contains($c.like) -and @(Read-Log).Count -eq 0 -and -not (Holds-Value ("" + $d.answer.reason + ($d.said -join " ")))) ("" + $c.what + ": refused, wrangler never run, no value in the reason (" + $d.answer.reason + ")")
    }
    Check (-not (Test-Path -LiteralPath $inside)) "CONTROL: the inside-the-repository case wrote nothing into the tree"
    Set-Settings -Raw '{"schemaVersion":1,"settings":{"googleClientFile":"x","colour":"blue"}}'
    Clear-Log
    $d = Deploy
    Check ($d.answer.state -ceq "unknown" -and "$($d.answer.reason)".Contains("colour") -and @(Read-Log).Count -eq 0) ("a settings file that fails its checks refuses the deploy in its own words (" + $d.answer.reason + ")")

    Write-Host ""
    Write-Host "--- 3. a wrangler that fails ---" -ForegroundColor Cyan
    Set-Settings -Client (Write-Client)
    Clear-Log
    $env:HORDE_FAKE_WRANGLER_FAIL = "secret"
    $d = Deploy
    $runs = @(Read-Log)
    Check ($d.answer.state -ceq "unknown" -and "$($d.answer.reason)".Contains("secret put GOOGLE_CLIENT_ID failed (exit 7)") -and "$($d.answer.reason)".Contains("nothing was deployed") -and $runs.Count -eq 1) ("a failed secret stops the deploy before anything is deployed (" + $runs.Count + " run)")
    Check ("$($d.answer.reason)".Contains("<redacted>") -and -not (Holds-Value ("" + $d.answer.reason))) ("what the failing wrangler printed reaches the founder with the value hidden (" + $d.answer.reason + ")")
    Clear-Log
    $env:HORDE_FAKE_WRANGLER_FAIL = "deploy"
    $d = Deploy
    Check ($d.answer.state -ceq "unknown" -and "$($d.answer.reason)".Contains("wrangler deploy failed (exit 7)") -and @(Read-Log).Count -eq 4) "a failed deploy says so, after the secrets"
    $env:HORDE_FAKE_WRANGLER_FAIL = ""

    Write-Host ""
    Write-Host "--- 4. which relay ---" -ForegroundColor Cyan
    Check (@(Get-HordeRelayDeployable) -join "," -ceq "cloudflare") ("the hosted relay is the one relay that can be deployed (" + (@(Get-HordeRelayDeployable) -join ",") + ")")
    $t = Resolve-HordeRelayDeployTarget
    Check ($t.state -ceq "known" -and $t.value -ceq "cloudflare") "with none named, the deploy picks it"
    $t = Resolve-HordeRelayDeployTarget -Relay "local"
    Check ($t.state -ceq "unknown" -and "$($t.reason)".Contains("cannot be deployed")) "a relay on this disk is refused: it has nothing to put anywhere"

    Write-Host ""
    Write-Host "--- 5. the shipped command ---" -ForegroundColor Cyan
    Set-Settings -Client (Write-Client -WithCallback)
    Clear-Log
    $cliEnv = @{ HORDE_HOME = $hh; HORDE_FAKE_WRANGLER_LOG = $log; HORDE_FAKE_WRANGLER_FAIL = "" }
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("relay", "deploy") -Env $cliEnv
    Check ($r.code -eq 0 -and $r.out.Contains("deployed relay cloudflare: it answers at " + $dep.origin) -and @(Read-Log).Count -eq 4 -and -not (Holds-Value $r.out)) ("horde relay deploy deploys, says where, and prints no value (exit " + $r.code + ")")
    # WHAT IS DEPLOYED IS RECORDED (cli/RelayDeploy.ps1): the commit of the checkout the command ran from,
    # which the supervisor compares with its own (cli/RelayPublish.ps1).
    $headNow = ("" + (& git -C $root rev-parse HEAD)).Trim()
    $rec = Read-HordeRelayDeployed -HordeHome $hh
    Check ($headNow -cmatch '\A[0-9a-f]{40}\z' -and $rec.state -ceq "known" -and $rec.value.commit -ceq $headNow -and $rec.value.origin -ceq $dep.origin -and $rec.value.relay -ceq "cloudflare") ("horde relay deploy records the commit it was deployed from, the relay and its origin (" + $(if ($rec.state -ceq "known") { $rec.value.commit } else { $rec.reason }) + ")")
    Clear-Log
    $cliEnv["HORDE_FAKE_WRANGLER_FAIL"] = "secret"
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("relay", "deploy", "-Relay", "cloudflare") -Env $cliEnv
    Check ($r.code -ne 0 -and $r.out.Contains("the relay was not deployed") -and -not (Holds-Value $r.out)) ("a failed deploy exits non-zero, says so, and prints no value (exit " + $r.code + ")")
    Check ((Read-HordeRelayDeployed -HordeHome $hh).value.at -eq $rec.value.at) "a failed deploy leaves the record of the last one that worked"
    # THE SHIPPED RELAY (2026-10-14): with no relayOrigin, the deploy is of wrangler.json's own origin -
    # the relay every user shares, which only its operator deploys.
    $shipped = "" + (([System.IO.File]::ReadAllText((Join-Path $root "relays\cloudflare\wrangler.json"))) | ConvertFrom-Json).vars.HORDE_RELAY_ORIGIN
    Set-Settings -Client (Write-Client -WithCallback) -Origin ""
    $cliEnv["HORDE_FAKE_WRANGLER_FAIL"] = ""
    Clear-Log
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("relay", "deploy") -Env $cliEnv
    $runs = @(Read-Log)
    Check ($shipped -clike "https://relay.*.workers.dev" -and $r.code -eq 0 -and $r.out.Contains("it answers at " + $shipped) -and $runs.Count -eq 4 -and @($runs | Where-Object { $_.config.name -cne "relay" -or $_.config.origin -cne $shipped }).Count -eq 0) ("with no relayOrigin, horde relay deploy deploys the shipped relay, at wrangler.json's origin (exit " + $r.code + ")")
    Set-Settings -Client (Write-Client -WithCallback)
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("relay", "deploy", "-Relay", "local") -Env $cliEnv
    Check ($r.code -ne 0 -and $r.out.Contains("cannot be deployed")) "relay deploy -Relay local is refused"
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("relay", "deploy", "-MaxTurns", "1") -Env $cliEnv
    Check ($r.code -ne 0 -and $r.out.Contains("-MaxTurns does not belong to relay deploy")) "a flag of another verb is refused"
} finally {
    $env:HORDE_FAKE_WRANGLER_LOG = $null
    $env:HORDE_FAKE_WRANGLER_FAIL = $null
    if ($work -like "*horde-cf-deploy-test-*" -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
Check (-not (Test-Path -LiteralPath $work)) "the suite's folder is gone"

Complete-HordeSuite -Success "the deploy pipes the client's values to wrangler and never says them, deploys the production config with the app, and stops at the first failure"
