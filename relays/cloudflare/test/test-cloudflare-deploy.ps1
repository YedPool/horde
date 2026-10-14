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
#   2. refusals before wrangler is ever run: no client file, one inside the repository, one that is not
#      JSON, not a web client, a malformed id, no secret, a relative path, a settings file that fails
#      its checks, a wranglerScript that is not there, an allowlist entry that is neither an email nor a
#      Google account id, an allowlist switched on with nobody on it - each reason free of the values
#      planted in it;
#   3. a wrangler that fails: at a secret, nothing is deployed; at the deploy, it says so; and what it
#      printed reaches the founder with the values hidden;
#   4. which relay: the one that can be deployed, and a refusal for one that cannot;
#   5. the shipped command, end to end: horde relay deploy, its success and failure, and its refusals;
#   6. the check after a deploy (2026-10-14): the relay's sign-in must send Google the client file's id,
#      byte for byte - a matching Location passes, and a marked, spaced, doubled or missing id, or a
#      relay whose sign-in is not set up, reports the deploy failed with no value in the reason. EVERY
#      deploy here is checked against test/fake-signin-start.cjs (the setting deployCheckOrigin), never
#      the real relay;
#   7. every secret's value, refused before wrangler runs when it begins with a byte order mark, holds a
#      character that is not printable ASCII, or has a space at either end - each rule with a twin that
#      must pass;
#   8. the bytes wrangler is given under Windows PowerShell 5.1 with a console whose input encoding is
#      UTF-8 WITH a preamble, as the founder's was on 2026-10-14: the value and nothing before it - with
#      a CONTROL that a plain start in that same console does put EF BB BF first, so the check can fail.
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
$dep = Get-HordeCloudflareRelayDeployment
$callback = $dep.origin + $dep.callback
$env:HORDE_FAKE_WRANGLER_LOG = $log
$env:HORDE_FAKE_WRANGLER_FAIL = ""
$node = Find-HordeCloudflareRelayNode
$bom = [string][char]0xFEFF
# The check after a failed comparison asks again; here it asks as often, but without the wait.
$script:HordeCloudflareRelayCheckWaitMs = 50
$starts = @{}
$script:startProcs = New-Object System.Collections.ArrayList

function Start-FakeStart {
    # A stand-in for the relay's sign-in start (fake-signin-start.cjs) answering in -Mode: its origin.
    param([string]$Mode)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $node
    $psi.Arguments = '"' + (Join-Path $here "fake-signin-start.cjs") + '" ' + $clientId + ' ' + $Mode
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    [void]$script:startProcs.Add($p)
    $null = $p.StandardError.ReadToEndAsync()
    $line = $p.StandardOutput.ReadLineAsync()
    if (-not $line.Wait(30000) -or "" + $line.Result -cnotmatch '\APORT ([0-9]+)\z') { throw ("the fake sign-in start did not start: " + $line.Result) }
    return ("http://127.0.0.1:" + $Matches[1])
}
foreach ($m in @("same", "mark", "space", "none", "two")) { $starts[$m] = Start-FakeStart -Mode $m }

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
    # The check after the deploy asks the suite's stand-in (-Check, the matching one by default), never
    # the real relay.
    param([string]$Client = "", [string]$Wrangler = $fake, [string]$Raw = "", [hashtable]$More = @{}, [string]$Check = $starts["same"])
    if ($Raw -eq "") {
        $set = @{ googleClientFile = $Client; wranglerScript = $Wrangler; deployCheckOrigin = $Check }
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
        Check (@($runs | Where-Object { $null -eq $_.config -or $_.config.namesTestBinding -or -not $_.config.appIndex -or $_.config.name -cne "relay" }).Count -eq 0) "every run is given the production config: the Worker relay, no test binding, the app's files beside it"
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
    Set-Settings -Client (Write-Client -WithCallback) -More @{ signInAllowlistOn = $false; signInAllowlist = "founder@example.com" }
    Clear-Log
    $d = Deploy
    $runs = @(Read-Log)
    Check ($d.answer.state -ceq "known" -and $runs.Count -eq 4 -and $runs[2].stdin -ceq '{"on":false,"emails":["founder@example.com"],"subs":[]}') "switched off, the list is kept for the day it is switched on, and nobody is shut out"

    Write-Host ""
    Write-Host "--- 2. refusals, before wrangler is ever run ---" -ForegroundColor Cyan
    $inside = Join-Path $root "relays\cloudflare\google-oauth-client.json"
    $bad = @(
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
        Set-Settings -Client $c.client -Wrangler $(if ($c.ContainsKey("wrangler")) { $c.wrangler } else { $fake }) -More $(if ($c.ContainsKey("more")) { $c.more } else { @{} })
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
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("relay", "deploy", "-Relay", "local") -Env $cliEnv
    Check ($r.code -ne 0 -and $r.out.Contains("cannot be deployed")) "relay deploy -Relay local is refused"
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("relay", "deploy", "-MaxTurns", "1") -Env $cliEnv
    Check ($r.code -ne 0 -and $r.out.Contains("-MaxTurns does not belong to relay deploy")) "a flag of another verb is refused"

    Write-Host ""
    Write-Host "--- 6. the check after a deploy: the client id sign-in sends Google ---" -ForegroundColor Cyan
    $ok = Test-HordeCloudflareRelaySignInClient -Origin $starts["same"] -ClientId $clientId -Tries 1
    Check ($ok.state -ceq "known") ("a Location whose client_id is the client file's passes (" + $ok.reason + ")")
    $no = Test-HordeCloudflareRelaySignInClient -Origin $starts["mark"] -ClientId $clientId -Tries 1
    Check ($no.state -ceq "unknown" -and "$($no.reason)".Contains("byte for byte") -and -not (Holds-Value ("" + $no.reason))) ("one whose client_id has a byte order mark in front fails, and the reason holds no value (" + $no.reason + ")")
    Check ((Get-HordeCloudflareRelayLocationClientId -Location ("https://x/?a=1&client_id=" + [System.Uri]::EscapeDataString($bom + "id"))) -ceq ($bom + "id")) "CONTROL: the client_id is read back decoded, mark and all, so the comparison sees it"
    Set-Settings -Client (Write-Client -WithCallback)
    Clear-Log
    $d = Deploy
    Check ($d.answer.state -ceq "known" -and ($d.said -join "`n").Contains("checked: the relay's sign-in sends Google the client file's id")) ("a deploy whose relay sends the client file's id is checked and passes (" + $d.answer.reason + ")")
    $bad = @(
        @{ what = "a byte order mark in front of the id"; mode = "mark"; like = "byte for byte" },
        @{ what = "a space after the id"; mode = "space"; like = "byte for byte" },
        @{ what = "the id twice"; mode = "two"; like = "no single client_id" },
        @{ what = "a sign-in that is not set up (503)"; mode = "none"; like = "answered 503" }
    )
    foreach ($c in $bad) {
        Set-Settings -Client (Write-Client -WithCallback) -Check $starts[$c.mode]
        Clear-Log
        $d = Deploy
        $why = "" + $d.answer.reason
        Check ($d.answer.state -ceq "unknown" -and $why.Contains("the relay was deployed, but its sign-in failed the check after the deploy") -and $why.Contains($c.like) -and @(Read-Log).Count -eq 4 -and -not (Holds-Value ($why + ($d.said -join " ")))) ("a relay whose sign-in sends " + $c.what + ": the deploy is reported failed, with no value in the reason (" + $why + ")")
    }
    # Not 127.0.0.1, so refused - yet on this machine, so a mutant that took it would contact nothing.
    Set-Settings -Client (Write-Client -WithCallback) -Check "http://localhost:9"
    Clear-Log
    $d = Deploy
    Check ($d.answer.state -ceq "unknown" -and "$($d.answer.reason)".Contains("deployCheckOrigin") -and @(Read-Log).Count -eq 0) ("the check can be pointed only at a stand-in on this machine: anything else is refused before wrangler runs (" + $d.answer.reason + ")")
    $cliEnv["HORDE_FAKE_WRANGLER_FAIL"] = ""
    Set-Settings -Client (Write-Client -WithCallback) -Check $starts["mark"]
    Clear-Log
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("relay", "deploy") -Env $cliEnv
    Check ($r.code -ne 0 -and $r.out.Contains("the relay was not deployed") -and $r.out.Contains("byte for byte") -and -not (Holds-Value $r.out)) ("horde relay deploy whose check fails exits non-zero and says why, with no value (exit " + $r.code + ")")

    Write-Host ""
    Write-Host "--- 7. every secret's value, before wrangler runs ---" -ForegroundColor Cyan
    $twins = @(
        @{ rule = "a byte order mark in front"; refuse = ($bom + $clientId); pass = $clientId; like = "byte order mark" },
        @{ rule = "a space at either end"; refuse = ($clientSecret + " "); pass = ("GOCSPX-inner space-0123456"); like = "begins or ends with a space" },
        @{ rule = "a space in front"; refuse = (" " + $clientSecret); pass = $clientSecret; like = "begins or ends with a space" },
        @{ rule = "a character that is not ASCII"; refuse = ("GOCSPX-caf" + [char]0x00E9 + "0123456"); pass = "GOCSPX-cafe0123456"; like = "not printable ASCII" },
        @{ rule = "a control character"; refuse = ("GOCSPX-a`tb0123456"); pass = "GOCSPX-a b0123456"; like = "not printable ASCII" }
    )
    foreach ($t in $twins) {
        $r1 = Test-HordeCloudflareRelaySecretValue -Name "GOOGLE_CLIENT_SECRET" -Value $t.refuse
        $r2 = Test-HordeCloudflareRelaySecretValue -Name "GOOGLE_CLIENT_SECRET" -Value $t.pass
        Check ($r1.Contains($t.like) -and $r1.Contains("GOOGLE_CLIENT_SECRET") -and -not $r1.Contains($t.refuse.Trim([char]0xFEFF, ' '))) ("a value with " + $t.rule + " is refused, naming the secret and not the value (" + $r1 + ")")
        Check ($r2 -ceq "") ("its twin without it passes (" + $r2 + ")")
    }
    # THROUGH THE DEPLOY: the reader is swapped for one that hands back the marked value, as no client file
    # can (GoogleClient.ps1's patterns refuse it first), so the deploy's own check is what refuses.
    $realRead = ${function:Read-HordeCloudflareRelayGoogleClient}
    $realAllow = ${function:ConvertTo-HordeCloudflareRelayAllowlist}
    try {
        $through = @(
            @{ what = "a client id with a byte order mark"; id = ($bom + $clientId); secret = $clientSecret; allow = ""; name = "GOOGLE_CLIENT_ID"; like = "byte order mark" },
            @{ what = "a client secret with a space after it"; id = $clientId; secret = ($clientSecret + " "); allow = ""; name = "GOOGLE_CLIENT_SECRET"; like = "begins or ends with a space" },
            @{ what = "a client secret that is not ASCII"; id = $clientId; secret = ($clientSecret + [char]0x00E9); allow = ""; name = "GOOGLE_CLIENT_SECRET"; like = "not printable ASCII" },
            @{ what = "an allowlist with a byte order mark"; id = $clientId; secret = $clientSecret; allow = ($bom + '{"on":false,"emails":[],"subs":[]}'); name = "HORDE_RELAY_SIGNIN_ALLOWLIST"; like = "byte order mark" }
        )
        Set-Settings -Client (Write-Client -WithCallback)
        foreach ($c in $through) {
            $script:planted = $c
            Set-Item -Path function:script:Read-HordeCloudflareRelayGoogleClient -Value { param($Path, $RepoRoot) New-HordeKnown -Value ([pscustomobject]@{ clientId = $script:planted.id; clientSecret = $script:planted.secret; redirectUris = @() }) }
            if ($c.allow -ne "") { Set-Item -Path function:script:ConvertTo-HordeCloudflareRelayAllowlist -Value { param($Values) New-HordeKnown -Value $script:planted.allow } }
            else { Set-Item -Path function:script:ConvertTo-HordeCloudflareRelayAllowlist -Value $realAllow }
            Clear-Log
            $d = Deploy
            $why = "" + $d.answer.reason
            Check ($d.answer.state -ceq "unknown" -and $why.Contains($c.name) -and $why.Contains($c.like) -and $why.Contains("nothing was deployed") -and @(Read-Log).Count -eq 0 -and -not $why.Contains($clientSecret) -and -not $why.Contains($clientId)) ("" + $c.what + ": refused before wrangler runs, naming the secret and not its value (" + $why + ")")
        }
        $script:planted = @{ id = $clientId; secret = "GOCSPX-inner space-0123456" }
        Set-Item -Path function:script:Read-HordeCloudflareRelayGoogleClient -Value { param($Path, $RepoRoot) New-HordeKnown -Value ([pscustomobject]@{ clientId = $script:planted.id; clientSecret = $script:planted.secret; redirectUris = @() }) }
        Set-Item -Path function:script:ConvertTo-HordeCloudflareRelayAllowlist -Value $realAllow
        Clear-Log
        $d = Deploy
        $runs = @(Read-Log)
        Check ($d.answer.state -ceq "known" -and $runs.Count -eq 4 -and $runs[1].stdin -ceq "GOCSPX-inner space-0123456") ("CONTROL: through the same swapped reader, clean values deploy, a space inside one included (" + $d.answer.reason + ")")
    } finally {
        Set-Item -Path function:script:Read-HordeCloudflareRelayGoogleClient -Value $realRead
        Set-Item -Path function:script:ConvertTo-HordeCloudflareRelayAllowlist -Value $realAllow
    }

    Write-Host ""
    Write-Host "--- 8. the bytes wrangler is given, under Windows PowerShell 5.1 with a UTF-8 console ---" -ForegroundColor Cyan
    # A child Windows PowerShell 5.1 sets its console's input encoding to UTF-8 with a preamble, then
    # runs `secret put` through the deploy's own Invoke-HordeCloudflareRelayNode, and - the CONTROL - a
    # plain Process.Start in that same console, each against the fake wrangler with its own log.
    $probe = Join-Path $work "stdin-probe.ps1"
    $probeText = @'
param([string]$Root, [string]$Fake, [string]$Log, [string]$Raw)
$ErrorActionPreference = "Stop"
[Console]::InputEncoding = New-Object System.Text.UTF8Encoding -ArgumentList $true
$enc = [Console]::InputEncoding
. (Join-Path $Root "relays\cloudflare\Wrangler.ps1")
$node = Find-HordeCloudflareRelayNode
$r = Invoke-HordeCloudflareRelayNode -Node $node -ArgList @($Fake, "secret", "put", "GOOGLE_CLIENT_ID") -Env @{ HORDE_FAKE_WRANGLER_LOG = $Log } -WorkDir (Split-Path -Parent $Log) -StdIn "VALUE-1" -TimeoutSeconds 60
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $node
$psi.Arguments = '"' + $Fake + '" secret put GOOGLE_CLIENT_ID'
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.CreateNoWindow = $true
$psi.EnvironmentVariables["HORDE_FAKE_WRANGLER_LOG"] = $Raw
$p = [System.Diagnostics.Process]::Start($psi)
$b = [System.Text.Encoding]::ASCII.GetBytes("VALUE-1")
$p.StandardInput.BaseStream.Write($b, 0, $b.Length)
$p.StandardInput.BaseStream.Close()
$null = $p.StandardOutput.ReadToEnd()
$p.WaitForExit()
"PS=" + $PSVersionTable.PSVersion.Major + ";CP=" + $enc.CodePage + ";PRE=" + $enc.GetPreamble().Length + ";AFTERCP=" + [Console]::InputEncoding.CodePage + ";AFTERPRE=" + [Console]::InputEncoding.GetPreamble().Length + ";CODE=" + $r.code
'@
    [System.IO.File]::WriteAllText($probe, $probeText, $utf8)
    $fixedLog = Join-Path $work "stdin-fixed.log"
    $rawLog = Join-Path $work "stdin-raw.log"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $probe + '" -Root "' + $root + '" -Fake "' + $fake + '" -Log "' + $fixedLog + '" -Raw "' + $rawLog + '"'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $pp = [System.Diagnostics.Process]::Start($psi)
    $perr = $pp.StandardError.ReadToEndAsync()
    $pout = $pp.StandardOutput.ReadToEnd()
    $null = $pp.WaitForExit(120000)
    $said = ("" + $pout).Trim()
    Check ($said.Contains("PS=5;CP=65001;PRE=3;")) ("CONTROL: the child is Windows PowerShell 5.1 with a UTF-8 console input encoding that has a preamble (" + $said + " " + ("" + $perr.Result).Trim() + ")")
    $readLog = { param($p) if (Test-Path -LiteralPath $p) { @([System.IO.File]::ReadAllLines($p) | Where-Object { $_ -ne "" } | ForEach-Object { $_ | ConvertFrom-Json }) } else { @() } }
    $rawRuns = @(& $readLog $rawLog)
    $fixedRuns = @(& $readLog $fixedLog)
    $markLatin1 = [string][char]0xEF + [char]0xBB + [char]0xBF
    Check ($rawRuns.Count -eq 1 -and $rawRuns[0].stdin -ceq ($markLatin1 + "VALUE-1")) ("CONTROL: in that console a plain start puts EF BB BF before the value, so the next check can fail (" + $(if ($rawRuns.Count -eq 1) { (@([System.Text.Encoding]::GetEncoding(28591).GetBytes($rawRuns[0].stdin) | Select-Object -First 4) -join ",") } else { "no run" }) + ")")
    Check ($fixedRuns.Count -eq 1 -and $fixedRuns[0].stdin -ceq "VALUE-1" -and $said.Contains("CODE=0")) ("the deploy's own run gives wrangler the value and nothing before it (" + $(if ($fixedRuns.Count -eq 1) { (@([System.Text.Encoding]::GetEncoding(28591).GetBytes($fixedRuns[0].stdin) | Select-Object -First 4) -join ",") } else { "no run" }) + ")")
    Check ($said.Contains(";AFTERCP=65001;AFTERPRE=3;")) ("and the console's input encoding is put back as it was (" + $said + ")")
} finally {
    foreach ($p in @($script:startProcs)) { try { if (-not $p.HasExited) { $p.StandardInput.BaseStream.Close(); if (-not $p.WaitForExit(10000)) { $p.Kill() } } } catch { }; $p.Dispose() }
    $env:HORDE_FAKE_WRANGLER_LOG = $null
    $env:HORDE_FAKE_WRANGLER_FAIL = $null
    if ($work -like "*horde-cf-deploy-test-*" -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
Check (-not (Test-Path -LiteralPath $work)) "the suite's folder is gone"

Complete-HordeSuite -Success "the deploy pipes the client's values to wrangler and never says them, deploys the production config with the app, and stops at the first failure"
