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
#      nothing said holds a value; the work folders are gone after; the redirect-address note; the
#      relay's owners as one plain --var of the deploy, or - with none set - a warning and no --var;
#   2. refusals before wrangler is ever run: no client file, one inside the repository, one that is not
#      JSON, not a web client, a malformed id, no secret, a relative path, a settings file that fails
#      its checks, a wranglerScript that is not there, an allowlist entry that is neither an email nor a
#      Google account id, an allowlist switched on with nobody on it, an owner named by email, one owner
#      past the most - each reason free of the values
#      planted in it;
#   3. a wrangler that fails: at a secret, nothing is deployed; at the deploy, it says so; and what it
#      printed reaches the founder with the values hidden;
#   4. which relay: the one that can be deployed, and a refusal for one that cannot;
#   5. the shipped command, end to end: horde relay deploy, its success and failure, and its refusals;
#   6. horde relay status: what the live relay (a stub of the suite's own) says of its owners.
# THE OWNERS (part 1): a secret by email or account id; a home that names none is refused while the live
# relay has owners, deploys with a warning while it has none, is refused when it cannot say; none is the
# opt-out.
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

# THE LIVE RELAY, A STUB (relays/cloudflare/Owners.ps1): every deploy whose home names no owner asks the
# live relay first. Here that is a listener of the suite's own on 127.0.0.1 - the only stand-in the
# deploy takes (HORDE_RELAY_TEST_STATUS_ORIGIN) - answering GET /status/owners with $live.answer, and
# counting what it was asked. Nothing here reaches the real relay. ONCE A DEPLOY HAS RUN (the fake
# wrangler's last run is the deploy) it answers as the deployed version would: the owners the deploy
# wrote and its word, so the deploy's confirmation (Owners.ps1, the deploy's word) finds its own at once;
# $live.echo = $false turns that off for the status checks.
$live = [hashtable]::Synchronized(@{ answer = "404"; asked = 0; echo = $true; log = $log })
$liveListener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
$liveListener.Start()
$env:HORDE_RELAY_TEST_STATUS_ORIGIN = "http://127.0.0.1:" + ([System.Net.IPEndPoint]$liveListener.LocalEndpoint).Port
$liveRs = [runspacefactory]::CreateRunspace()
$liveRs.Open()
$livePs = [powershell]::Create()
$livePs.Runspace = $liveRs
[void]$livePs.AddScript({
        param($Listener, $Live)
        while ($true) {
            try { $c = $Listener.AcceptTcpClient() } catch { return }
            try {
                $st = $c.GetStream()
                $st.ReadTimeout = 5000
                $buf = New-Object byte[] 8192
                $got = ""
                while (-not $got.Contains("`r`n`r`n")) { $n = $st.Read($buf, 0, $buf.Length); if ($n -le 0) { break }; $got += [System.Text.Encoding]::ASCII.GetString($buf, 0, $n) }
                $Live.asked = $Live.asked + 1
                $a = "" + $Live.answer
                if ($Live.echo -and (Test-Path -LiteralPath $Live.log)) {
                    $runs = @([System.IO.File]::ReadAllLines($Live.log) | Where-Object { $_ -ne "" } | ForEach-Object { $_ | ConvertFrom-Json })
                    if ($runs.Count -gt 0 -and ("" + @($runs[$runs.Count - 1].argv)[0]) -ceq "deploy") {
                        $o = @($runs | Where-Object { (@($_.argv) -join " ") -like "secret put HORDE_RELAY_OWNER_ACCOUNTS*" } | Select-Object -Last 1)
                        if ($o.Count -eq 1) {
                            $j = ("" + $o[0].stdin).Substring(("" + $o[0].stdin).IndexOf("{")) | ConvertFrom-Json
                            $n = @($j.emails).Count + @($j.subs).Count
                            $a = '{"owners":' + $n + ',"reserve":' + $(if ($n -gt 0) { "true" } else { "false" }) + ',"deploy":"' + $j.deploy + '"}'
                        }
                    }
                }
                $body = $(if ($a.StartsWith("{")) { $a } else { "" })
                $code = $(if ($a.StartsWith("{")) { "200 OK" } elseif ($a -ceq "500") { "500 Internal Server Error" } else { "404 Not Found" })
                $text = "HTTP/1.1 " + $code + "`r`nContent-Type: application/json`r`nContent-Length: " + $body.Length + "`r`nConnection: close`r`n`r`n" + $body
                $bytes = [System.Text.Encoding]::ASCII.GetBytes($text)
                $st.Write($bytes, 0, $bytes.Length)
                $st.Flush()
            } catch { } finally { $c.Close() }
        }
    }).AddArgument($liveListener).AddArgument($live)
$liveJob = $livePs.BeginInvoke()

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
    param([string]$Client = "", [string]$Wrangler = $fake, [string]$Raw = "", [hashtable]$More = @{})
    if ($Raw -eq "") {
        $set = @{ googleClientFile = $Client; wranglerScript = $Wrangler }
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
function Remove-Word { param([string]$Text) return ($Text -replace '"deploy":"[0-9a-f]{16}",', "") }
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
    Check ($runs.Count -eq 5) ("wrangler ran five times (" + $runs.Count + ")")
    if ($runs.Count -eq 5) {
        $cmds = @($runs | ForEach-Object { (@($_.argv) | Select-Object -First 3) -join " " })
        Check ($cmds[0] -ceq "secret put GOOGLE_CLIENT_ID" -and $cmds[1] -ceq "secret put GOOGLE_CLIENT_SECRET" -and $cmds[2] -ceq "secret put HORDE_RELAY_SIGNIN_ALLOWLIST" -and $cmds[3] -ceq "secret put HORDE_RELAY_OWNER_ACCOUNTS" -and $cmds[4] -clike "deploy --config*") ("the four secrets first, then the deploy (" + ($cmds -join "; ") + ")")
        Check ($runs[0].stdin -ceq $clientId -and $runs[1].stdin -ceq $clientSecret) "each secret's value is on standard input exactly: no byte order mark, no line end"
        Check ($runs[2].stdin -ceq '{"on":false,"emails":[],"subs":[]}') ("with the settings untouched the allowlist is OFF: signup is public (" + $runs[2].stdin + ")")
        Check ((Remove-Word $runs[3].stdin) -ceq '{"emails":[],"subs":[]}') ("with no owner set, and none on the live relay, the owners are written empty (" + $runs[3].stdin + ")")
        Check ($runs[3].stdin -cmatch '"deploy":"[0-9a-f]{16}",' -and ($d.said -join " ").Contains("the live relay runs this deploy: 0 owner(s), no reserve")) "the owners carry the deploy's word, and the deploy waits until its own version answers it"
        Check ($runs[4].stdin -ceq "") "the deploy is given nothing on its input"
        $argvAll = (@($runs | ForEach-Object { @($_.argv) -join " " }) -join " ")
        Check (-not (Holds-Value $argvAll)) "no value is ever an argument"
        Check (@($runs | Where-Object { $null -eq $_.config -or $_.config.namesTestBinding -or -not $_.config.appIndex -or $_.config.name -cne "relay" }).Count -eq 0) "every run is given the production config: the Worker relay, no test binding, the app's files beside it"
        $repoFull = [System.IO.Path]::GetFullPath($root).TrimEnd('\') + "\"
        Check (@($runs | Where-Object { ([System.IO.Path]::GetFullPath($_.config.path)).StartsWith($repoFull, [System.StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) "the config wrangler is given lives outside the repository"
        $appConfig = $runs[4].config.appConfig | ConvertFrom-Json
        Check ($appConfig.transport -ceq "http" -and $appConfig.relayOrigin -ceq "") ("the app is built with the http transport at its own origin (" + $runs[4].config.appConfig + ")")
        Check (@($runs | Where-Object { $_.env.WRANGLER_SEND_METRICS -cne "false" -or $_.env.CI -cne "true" -or $null -ne $_.env.PSObject.Properties["HORDE_RELAY_TEST_AUTH"] }).Count -eq 0) "every run is quiet and non-interactive, and none carries the test binding"
    }
    $saidAll = $d.said -join "`n"
    Check (-not (Holds-Value $saidAll) -and $saidAll.Contains("stored GOOGLE_CLIENT_SECRET") -and $saidAll.Contains("https://relay.example.workers.dev")) "what the deploy says names each step and passes wrangler's words on, and holds no value"
    Check ($saidAll.Contains("note: the Google client does not list " + $callback)) "a client that does not list the relay's return address gets a note naming it"
    $argvNoOwner = (@($runs | ForEach-Object { @($_.argv) -join " " }) -join " ")
    Check ($saidAll.Contains("warning: the setting relayOwnerAccounts names no owner") -and $saidAll.Contains("shared by every account") -and -not $argvNoOwner.Contains("--var")) "with no owner set, and none on the live relay, the deploy warns that the relay keeps no reserve - its whole day shared"
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
    Check ($d.answer.state -ceq "known" -and $runs.Count -eq 5 -and $runs[2].stdin -ceq '{"on":true,"emails":["founder@example.com","second@example.org"],"subs":["112233445566778899"]}') ("one setting switches the allowlist on: its emails in lower case, its Google account ids apart (" + $(if ($runs.Count -ge 3) { $runs[2].stdin } else { $d.answer.reason }) + ")")
    Check (-not (($d.said -join " ").Contains("founder@example.com"))) "and what the deploy says names nobody on it"
    Set-Settings -Client (Write-Client -WithCallback) -More @{ signInAllowlistOn = $false; signInAllowlist = "founder@example.com" }
    Clear-Log
    $d = Deploy
    $runs = @(Read-Log)
    Check ($d.answer.state -ceq "known" -and $runs.Count -eq 5 -and $runs[2].stdin -ceq '{"on":false,"emails":["founder@example.com"],"subs":[]}') "switched off, the list is kept for the day it is switched on, and nobody is shut out"
    # THE OWNERS (Owners.ps1): a secret like the allowlist, by email or Google account id - and a home that
    # names none may not deploy over a live relay that has some.
    Set-Settings -Client (Write-Client -WithCallback) -More @{ relayOwnerAccounts = " Boss@Example.com ,112233445566778899,boss@example.com,112233445566778899" }
    Clear-Log
    $live.asked = 0
    $d = Deploy
    $runs = @(Read-Log)
    Check ($d.answer.state -ceq "known" -and $runs.Count -eq 5 -and (Remove-Word $runs[3].stdin) -ceq '{"emails":["boss@example.com"],"subs":["112233445566778899"]}' -and $live.asked -eq 1) ("SET: the owners are a secret of their own - emails in lower case, account ids apart, each once - and the live relay is asked only to confirm the deploy (" + $(if ($runs.Count -ge 4) { $runs[3].stdin } else { $d.answer.reason }) + ")")
    $argvOwners = (@($runs | ForEach-Object { @($_.argv) -join " " }) -join " ")
    $saidOwners = $d.said -join " "
    Check (-not $argvOwners.Contains("boss@example.com") -and -not $argvOwners.Contains("--var") -and -not $saidOwners.Contains("warning:") -and $saidOwners.Contains("the relay's owners: 2 account(s)") -and -not $saidOwners.Contains("boss@example.com")) "no owner is ever an argument, and what the deploy says counts them without naming them"
    Check (-not ([System.IO.File]::ReadAllText((Join-Path $root "relays\cloudflare\wrangler.json")).Contains("HORDE_RELAY_OWNER_ACCOUNTS"))) "CONTROL: the committed config names no owner"
    Set-Settings -Client (Write-Client -WithCallback) -More @{ relayOwnerAccounts = ((1..16 | ForEach-Object { "1000" + $_ }) -join ",") }
    Clear-Log
    $d = Deploy
    Check ($d.answer.state -ceq "known" -and @(Read-Log).Count -eq 5) ("CONTROL: sixteen owners, the most - one step below the refusal in part 2 - deploy (" + $d.answer.reason + ")")
    # MISSING, AND THE LIVE RELAY HAS OWNERS: refused, nothing run, the reason naming the setting and its file.
    Set-Settings -Client (Write-Client -WithCallback)
    $settingsFile = Join-Path $hh "settings\relay-cloudflare.json"
    $live.answer = '{"owners":1,"reserve":true}'
    Clear-Log
    $live.asked = 0
    $d = Deploy
    Check ($d.answer.state -ceq "unknown" -and "$($d.answer.reason)".Contains("the live relay has 1 owner(s), and the setting relayOwnerAccounts in " + $settingsFile + " names none") -and "$($d.answer.reason)".Contains("nothing was deployed") -and @(Read-Log).Count -eq 0 -and $live.asked -eq 1) ("MISSING + LIVE OWNERS: refused, nothing run, the setting and its file named (" + $d.answer.reason + ")")
    # MISSING, AND THE LIVE RELAY HAS NONE: deployed, with the warning.
    $live.answer = '{"owners":0,"reserve":false}'
    Clear-Log
    $d = Deploy
    Check ($d.answer.state -ceq "known" -and @(Read-Log).Count -eq 5 -and ($d.said -join " ").Contains("warning: the setting relayOwnerAccounts names no owner, and the live relay has none")) ("MISSING + NO LIVE OWNERS: deployed, with the warning (" + $d.answer.reason + ")")
    # MISSING, AND THE LIVE RELAY CANNOT SAY: refused - not knowing is not none.
    $live.answer = "500"
    Clear-Log
    $d = Deploy
    Check ($d.answer.state -ceq "unknown" -and "$($d.answer.reason)".Contains("answered 500") -and @(Read-Log).Count -eq 0) ("MISSING + A LIVE RELAY THAT CANNOT SAY: refused, nothing run (" + $d.answer.reason + ")")
    # THE OPT-OUT: none clears them on purpose, without asking.
    $live.answer = '{"owners":1,"reserve":true}'
    Set-Settings -Client (Write-Client -WithCallback) -More @{ relayOwnerAccounts = "None" }
    Clear-Log
    $live.asked = 0
    $d = Deploy
    $runs = @(Read-Log)
    Check ($d.answer.state -ceq "known" -and $runs.Count -eq 5 -and (Remove-Word $runs[3].stdin) -ceq '{"emails":[],"subs":[]}' -and $live.asked -eq 1 -and ($d.said -join " ").Contains("clears any the live relay has")) ("OPT-OUT: relayOwnerAccounts none deploys with no owners, clearing the live relay's, said so (" + $d.answer.reason + ")")
    $live.answer = "404"

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
        @{ what = "an allowlist switched on with nobody on it"; client = (Write-Client); more = @{ signInAllowlistOn = $true; signInAllowlist = "" }; like = "nobody could sign in" },
        @{ what = "an owner that is neither an email nor an account id"; client = (Write-Client); more = @{ relayOwnerAccounts = "112233445566778899, not-an-owner" }; like = "relayOwnerAccounts holds an entry (number 2) that is neither an email nor a Google account id" },
        @{ what = "seventeen owners, one past the most"; client = (Write-Client); more = @{ relayOwnerAccounts = ((1..17 | ForEach-Object { "1000" + $_ }) -join ",") }; like = "names more than 16" }
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
    Check ($d.answer.state -ceq "unknown" -and "$($d.answer.reason)".Contains("wrangler deploy failed (exit 7)") -and @(Read-Log).Count -eq 5) "a failed deploy says so, after the secrets"
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
    Check ($r.code -eq 0 -and $r.out.Contains("deployed relay cloudflare: it answers at " + $dep.origin) -and @(Read-Log).Count -eq 5 -and -not (Holds-Value $r.out)) ("horde relay deploy deploys, says where, and prints no value (exit " + $r.code + ")")
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
    Write-Host "--- 6. horde relay status: what the live relay says of its owners ---" -ForegroundColor Cyan
    $live.echo = $false
    $live.answer = '{"owners":0,"reserve":false}'
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("relay", "status") -Env $cliEnv
    Check ($r.code -eq 0 -and $r.out.Contains("no owner set: the whole day is shared, no reserve")) ("with no owner on the live relay, relay status says the whole day is shared, no reserve (exit " + $r.code + ": " + $r.out.Trim() + ")")
    $live.answer = '{"owners":2,"reserve":true}'
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("relay", "status", "-Relay", "cloudflare") -Env $cliEnv
    Check ($r.code -eq 0 -and $r.out.Contains("2 owner(s): the reserve of the day is kept for them") -and -not $r.out.Contains("no reserve")) ("with owners, it says how many and that the reserve is kept for them - never who (exit " + $r.code + ": " + $r.out.Trim() + ")")
    $live.answer = "500"
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("relay", "status") -Env $cliEnv
    Check ($r.code -eq 0 -and $r.out.Contains("cannot say whether it has owners")) ("a live relay that cannot be asked is said so, never read as none (exit " + $r.code + ")")
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("relay", "status", "-Relay", "local") -Env $cliEnv
    Check ($r.code -ne 0 -and $r.out.Contains("cannot say how it is")) "a relay that runs only here has no status to ask"
    $live.answer = "404"
} finally {
    $env:HORDE_FAKE_WRANGLER_LOG = $null
    $env:HORDE_FAKE_WRANGLER_FAIL = $null
    $env:HORDE_RELAY_TEST_STATUS_ORIGIN = $null
    try { $liveListener.Stop() } catch { }
    try { $livePs.Dispose(); $liveRs.Dispose() } catch { }
    if ($work -like "*horde-cf-deploy-test-*" -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
Check (-not (Test-Path -LiteralPath $work)) "the suite's folder is gone"

Complete-HordeSuite -Success "the deploy pipes the client's values to wrangler and never says them, deploys the production config with the app, and stops at the first failure"
