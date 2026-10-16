# DOES `horde setup` TAKE A BRAND-NEW MACHINE TO A WORKING ONE - FIXING WHAT IT SAFELY CAN, STOPPING AT
# THE FIRST STEP IT CANNOT FINISH WITH THE ONE NEXT THING TO DO, AND CHANGING NOTHING ON A SECOND RUN?
#
# 2026-10-14: Horde's first person to install it on a fresh machine was stuck. Every user shares the
# shipped relay (the founder's decision that day); hosting one's own is the operator's path. This suite
# starts from Horde homes that do not exist and walks both (cli/Setup.ps1; relays/cloudflare/Setup.ps1):
#   1. THE USER'S PATH, through the shipped command: the home made, settings\relay.json written for
#      the shipped relay (ASCII, exactly), and a stop at the machine's identity; a second run changes
#      nothing; a bad horde name, a relay.json that is there already and -CheckOnly each fix nothing.
#   2. THE REST OF IT, in this process, with stand-ins only for what this machine must not touch (its
#      key store, a phone) and the real files for the rest: the identity made; the relay runner's
#      service written, which the real definitions reader takes; the runner serving or not by its real
#      heartbeat; a phone paired; all set - and a second run that fixes nothing and says all set.
#      Then the supervisor: from a prompt that is not elevated, nothing tried and the one elevated line
#      printed (decoded, it is exactly `services schedule` for this home); elevated, scheduled once.
#      Then the test question, added through the shipped decisions list, once. The requirements
#      (Windows, Windows PowerShell 5.1) first, and setup run again under 5.1 when started from pwsh.
#   3. THE OPERATOR'S PATH (-Operator), through the shipped command, with the must-fail twins: no
#      origin of its own; no client file (and the deploy refuses); a client file whose redirect URIs
#      lack the callback (warned); then the deploy with the fake wrangler, and on to the user's steps.
#   4. THE MANIFEST (setup\steps.json): every step in it has its check in the code and every check its
#      step, both ways; a step with no code, code with no step, a newer manifest version and a manifest
#      that is not ASCII each refuse it whole; -Steps -Json prints it as the code reads it.
#
# NOTHING HERE DEPLOYS OR CONTACTS ANYTHING REAL: the wrangler is test/fake-wrangler.cjs, named by the
# home's own setting; every command runs with USERPROFILE pointed at a profile folder of the suite's
# own, so the default Google client file is never the real one; no network, no scheduler, no key made
# (the identity's fix is -NoFix'd through the command, and a stand-in in this process).
#
# NODE IS NEEDED (the fake wrangler is a node script, and node is an operator's step). Without it the
# suite skips and exits 3. Run under Windows PowerShell 5.1, as every suite is.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "Home", "ModuleSettings", "Heartbeat", "Services")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "relays\Port.ps1")
foreach ($f in @(Get-HordeRelayFiles)) { . $f }
. (Join-Path $root "relay\Trust.ps1")
. (Join-Path $root "relay\Pairing.ps1")
foreach ($f in @("RelayDeploy", "RelayRun", "QrCode", "RelayPair", "SetupStore", "Setup")) { . (Join-Path $root ("cli\" + $f + ".ps1")) }
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "test\lib\RelayPhone.ps1")
Set-StrictMode -Version Latest

if ((Find-HordeCloudflareRelayNode) -eq "") {
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Complete-HordeSuite -Success "skipped: no node here, so no wrangler, fake or real" -PassCode 3
}

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$work = Join-Path $env:TEMP ("horde-cf-setup-test-" + [guid]::NewGuid().ToString("N").Substring(0, 12))
$prof = Join-Path $work "profile"
[void][System.IO.Directory]::CreateDirectory($prof)
$log = Join-Path $work "wrangler.log"
$fake = Join-Path $here "fake-wrangler.cjs"
$clientId = "123456789012-fakeclientforhordesetup000000000.apps.googleusercontent.com"
$clientSecret = "GOCSPX-fakeSecretForHordeSetup01234567"
$clientFile = Join-Path $prof ".horde-secrets\google-oauth-client.json"
$script:said = New-Object System.Collections.ArrayList
# The Store and PowerShell 7 steps (cli/SetupStore.ps1) read the real registry and search path unless told
# otherwise; this suite is about the rest, so they read a pretend machine that is already as it should be.
$fakeMachine = Join-Path $work "pretend-machine.json"

[System.IO.File]::WriteAllText($fakeMachine, '{ "elevated": false, "storePolicy": 2, "pwshResolved": "C:\\Program Files\\PowerShell\\7\\pwsh.exe", "msiVersion": "7.5.3", "actions": [] }')
$script:sayLines = New-Object System.Collections.ArrayList
$script:pairHomes = New-Object System.Collections.ArrayList
$script:partial = $false
# The shipped relay, as the code under test reads it: wrangler.json's origin, for a home that names none.
$shipped = "" + (([System.IO.File]::ReadAllText((Join-Path $root "relays\cloudflare\wrangler.json"))) | ConvertFrom-Json).vars.HORDE_RELAY_ORIGIN
$shippedHost = ([uri]$shipped).Host

function Setup {
    # The shipped command, as a person runs it, on home -HordeHome: { code; out; lines; next }.
    param([string]$HordeHome, [string[]]$More = @())
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs (@("setup") + $More) -Env @{ HORDE_HOME = $HordeHome; USERPROFILE = $prof; HORDE_FAKE_WRANGLER_LOG = $log; HORDE_FAKE_WRANGLER_FAIL = ""; HORDE_SETUP_FAKE_MACHINE = $fakeMachine }
    [void]$script:said.Add($r.out)
    $lines = @($r.out -split "`r?`n" | Where-Object { $_.Trim() -ne "" })
    return [pscustomobject]@{ code = $r.code; out = $r.out; lines = $lines; next = $(if ($lines.Count -gt 0) { $lines[-1] } else { "" }) }
}
function Horde {
    # A horde command on home -HordeHome. A deploy is one at a time PER MACHINE (cli/RelayDeploy.ps1,
    # the machine's lock), so one refused because another suite or the supervisor holds that lock is
    # asked again, for up to a minute: measured 2026-10-14, a run here once met another's deploy.
    param([string]$HordeHome, [string[]]$HordeArgs)
    for ($i = 0; $i -lt 12; $i++) {
        $r = Invoke-HordeCliProcess -Root $root -HordeArgs $HordeArgs -Env @{ HORDE_HOME = $HordeHome; USERPROFILE = $prof; HORDE_FAKE_WRANGLER_LOG = $log; HORDE_FAKE_WRANGLER_FAIL = ""; HORDE_SETUP_FAKE_MACHINE = $fakeMachine }
        if (-not $r.out.Contains((Get-HordeRelayDeployBusyReason))) { return $r }
        Start-Sleep -Seconds 5
    }
    return $r
}
function Has { param($R, [string]$Line) return (@($R.lines | Where-Object { $_ -ceq $Line }).Count -eq 1) }
function HasLike { param($R, [string]$Like) return (@($R.lines | Where-Object { $_ -clike $Like }).Count -ge 1) }
function Write-Text { param([string]$Path, [string]$Text) [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $Path)); [System.IO.File]::WriteAllText($Path, $Text, $utf8) }
function Write-Client {
    param([switch]$WithCallback, [string]$Origin)
    $uris = $(if ($WithCallback) { '"' + $Origin + '/auth/google/callback", ' } else { "" }) + '"http://localhost:8080/"'
    Write-Text $clientFile ('{"web":{"client_id":"' + $clientId + '","project_id":"horde-setup-test","client_secret":"' + $clientSecret + '","redirect_uris":[' + $uris + ']}}')
}
function Get-Tree {
    # Every file under -Folder, with its SHA-256: what a run must leave as it found it.
    param([string]$Folder)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return (@(Get-ChildItem -LiteralPath $Folder -Recurse -File -Force | Sort-Object FullName | ForEach-Object { $_.FullName.Substring($Folder.Length) + "=" + (($sha.ComputeHash([System.IO.File]::ReadAllBytes($_.FullName)) | ForEach-Object { $_.ToString("x2") }) -join "") }) -join "|") } finally { $sha.Dispose() }
}
function Test-Ascii { param([string]$Path) return (@([System.IO.File]::ReadAllBytes($Path) | Where-Object { $_ -gt 126 -or ($_ -lt 32 -and $_ -ne 10 -and $_ -ne 13) }).Count -eq 0) }
function Report {
    # In this process: { report; lines; next; states }.
    param([string]$HordeHome, [hashtable]$Probes, [string[]]$NoFix = @())
    foreach ($pair in @(@("storePolicy", { 2 }), @("pwshResolved", { "C:\Program Files\PowerShell\7\pwsh.exe" }), @("msiVersion", { "7.5.3" }))) { if (-not $Probes.ContainsKey($pair[0])) { $Probes[$pair[0]] = $pair[1] } }
    $r = Get-HordeSetupReport -HordeHome $HordeHome -Root $root -Probes $Probes -Label "Test phone" -NoFix $NoFix -Say { param($Line) [void]$script:sayLines.Add("" + $Line) }
    $lines = @(Format-HordeSetupReport -Report $r)
    [void]$script:said.Add(($lines -join "`n"))
    return [pscustomobject]@{ report = $r; lines = $lines; next = $lines[-1]; states = (@($r.steps | ForEach-Object { $_.id + "=" + $_.state }) -join " ") }
}
function Last-Step { param($R) return @($R.report.steps | Where-Object { @("store-updates-off", "powershell-msi") -cnotcontains $_.id })[-1] }

try {
    Write-Host ""
    Write-Host "--- 1. the user's path, through the shipped command ---" -ForegroundColor Cyan
    $hh = Join-Path $work "home"
    Check (-not (Test-Path -LiteralPath $hh) -and $shipped -clike "https://*.workers.dev") ("CONTROL: the home does not exist yet, and the shipped relay is read (" + $shipped + ")")
    $relayJson = Join-Path $hh "settings\relay.json"
    $s = Setup $hh @("-NoFix", "machine-identity")
    Check ($s.code -eq 0 -and (HasLike $s "  done  what Horde needs: Windows *, Windows PowerShell 5.1*")) ("the requirements are checked first, and met (exit " + $s.code + ")")
    Check ((Has $s ("  fixed Horde home: " + $hh + " (made just now)")) -and (Test-Path -LiteralPath $hh -PathType Container)) "setup makes the home and says so"
    Check ((Has $s ("  fixed relay settings: wrote " + $relayJson + ": the horde home, the phone app at " + $shipped)) -and (Test-Path -LiteralPath $relayJson)) "and writes the relay settings for the shipped relay, saying so"
    $want = '{ "schemaVersion": 1, "settings": { "horde": "home", "pairRpId": "' + $shippedHost + '", "pairOrigin": "' + $shipped + '" } }'
    Check ((Test-Ascii $relayJson) -and [System.IO.File]::ReadAllText($relayJson) -ceq $want) ("the file is ASCII and exactly what the hand-written step wrote (" + [System.IO.File]::ReadAllText($relayJson) + ")")
    $rv = Get-HordeRelaySettingValues -HordeHome $hh
    Check ($rv.state -ceq "known" -and $rv.value.values.horde -ceq "home" -and $rv.value.values.pairRpId -ceq $shippedHost -and $rv.value.values.pairOrigin -ceq $shipped) "and the relay's own settings reader takes it"
    Check ((Has $s "  TO DO machine identity: this machine has no relay identity yet") -and $s.next -ceq "next: horde relay identity -New") ("a step it was told not to fix stops it, with its exact command (" + $s.next + ")")
    Check (-not $s.out.Contains("Google") -and -not $s.out.Contains("deploy") -and -not $s.out.Contains("relay-runner")) "the user is never asked for a Google client or a deploy, and no later step is looked at"
    $before = Get-Tree $hh
    $s = Setup $hh @("-NoFix", "machine-identity")
    Check ((Has $s ("  done  Horde home: " + $hh)) -and (Has $s ("  done  relay settings: this machine is of the horde home; the phone app is at " + $shipped)) -and $s.next -ceq "next: horde relay identity -New" -and (Get-Tree $hh) -ceq $before) "a second run fixes nothing, changes no byte, and says the same next step"
    Check (@(Get-ChildItem -LiteralPath $hh -Recurse -File -Force).Count -eq 1) "the home holds the one file setup wrote, and nothing else"

    $h2 = Join-Path $work "home-badname"
    $s = Setup $h2 @("-NoFix", "machine-identity", "-Horde", "Not A Name")
    Check ((HasLike $s "  TO DO relay settings: *setup tried: the horde name given is refused: *") -and $s.next -clike "next: horde setup -Horde <a name for this horde*" -and -not (Test-Path -LiteralPath (Join-Path $h2 "settings\relay.json"))) "MUST FAIL: a horde name that is not one is refused, honestly, and nothing is written"
    $h3 = Join-Path $work "home-ownfile"
    Write-Text (Join-Path $h3 "settings\relay.json") '{"schemaVersion":1,"settings":{"horde":"mine"}}'
    $before = Get-Tree $h3
    $s = Setup $h3 @("-NoFix", "machine-identity")
    Check ((HasLike $s "  TO DO relay settings: *") -and $s.next -ceq ('next: add "pairRpId": "' + $shippedHost + '", "pairOrigin": "' + $shipped + '" to the settings in ' + (Join-Path $h3 "settings\relay.json")) -and (Get-Tree $h3) -ceq $before) ("MUST FAIL: a relay.json that is there is the person's: setup says exactly what to add, and writes nothing (" + $s.next + ")")
    $h4 = Join-Path $work "home-check"
    $s = Setup $h4 @("-Check")
    Check ((Has $s ("  TO DO Horde home: there is no folder " + $h4)) -and $s.next -ceq ("next: make the folder " + $h4) -and -not (Test-Path -LiteralPath $h4)) "MUST FAIL: -Check fixes nothing, not even the home, and says the manifest's sentence for it"
    $s = Setup $h4 @("-CheckOnly")
    Check ((Has $s ("  TO DO Horde home: there is no folder " + $h4)) -and -not (Test-Path -LiteralPath $h4)) "and -CheckOnly is the same walk"
    # A DOUBLE QUOTE IN -Label breaks the pairing command setup prints, and the arguments it runs itself
    # again with under 5.1: refused, in plain words, before anything is made. (My\"PC is how a command
    # line hands over My"PC.)
    $s = Setup $h4 @("-Label", 'My\"PC')
    Check ($s.code -ne 0 -and $s.out.Contains("-Label cannot hold a double quote: name the phone without one") -and -not (Test-Path -LiteralPath $h4)) ("MUST FAIL: a -Label with a double quote is refused, and nothing is made (exit " + $s.code + ")")
    $threwQ = ""
    try { $null = Get-HordeSetupReport -HordeHome $h4 -Root $root -Label 'My "PC"' -Check } catch { $threwQ = $_.Exception.Message }
    Check ($threwQ.Contains("-Label cannot hold a double quote") -and -not (Test-Path -LiteralPath $h4)) "and the same in this process"
    # STARTED FROM POWERSHELL 7, setup runs itself again under Windows PowerShell 5.1 (issue 274).
    $pwsh = @(Get-Command -Name "pwsh" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($pwsh.Count -eq 1) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $pwsh[0].Source
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"" + (Join-Path $root "horde.ps1") + "`" setup -Check"
        $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
        $psi.EnvironmentVariables["HORDE_HOME"] = $h4; $psi.EnvironmentVariables["USERPROFILE"] = $prof
        $pp = [System.Diagnostics.Process]::Start($psi)
        $ppErr = $pp.StandardError.ReadToEndAsync(); $ppOut = $pp.StandardOutput.ReadToEnd(); $pp.WaitForExit()
        $both = $ppOut + "`n" + $ppErr.Result
        [void]$script:said.Add($both)
        Check ($pp.ExitCode -eq 0 -and $both.Contains("running again under Windows PowerShell 5.1") -and $both -match "done  what Horde needs: Windows [0-9]+ \(build [0-9]+\), Windows PowerShell 5\.1" -and $both.Contains("TO DO Horde home: there is no folder " + $h4)) ("started from PowerShell 7, setup runs itself again under 5.1, with the same arguments (exit " + $pp.ExitCode + ")")
        $pp.Dispose()
    } else { Write-Host "  (no PowerShell 7 here: the run-again under 5.1 is not exercised)" -ForegroundColor Yellow }

    Write-Host ""
    Write-Host "--- 2. the rest, in this process: stand-ins for the key store and the phone only ---" -ForegroundColor Cyan
    $script:hasIdentity = $false
    $idProbe = { param($HordeHome) [pscustomobject]@{ ok = $true; reason = ""; machines = @($(if ($script:hasIdentity) { [pscustomobject]@{ generation = 1 } })) } }
    $makeOk = { param($HordeHome) $script:hasIdentity = $true; New-HordeKnown -Value ([pscustomobject]@{ generation = 1; horde = "home" }) }
    $makeFails = { param($HordeHome) New-HordeUnknown -Reason "no key store answered (a stand-in)" }
    $noPhone = { param($HordeHome) New-HordeKnown -Value ([pscustomobject]@{ devices = @(); machines = @(); revoked = @(); phones = @() }) }
    $x = Report $hh @{ identity = $idProbe; makeIdentity = $makeFails; trust = $noPhone }
    Check ((Last-Step $x).id -ceq "machine-identity" -and (Last-Step $x).state -ceq "todo" -and (Last-Step $x).said -clike "*setup tried: it could not be made: no key store answered (a stand-in)" -and $x.next -ceq "next: horde relay identity -New") "MUST FAIL: an identity that cannot be made is said to have been tried, with why, and the command to make it"
    $defsPath = Join-Path $hh "settings\service-definitions.json"
    Check (-not (Test-Path -LiteralPath $defsPath)) "CONTROL: and nothing past it was touched"
    # The scheduler and elevation are stand-ins too: the real scheduler holds this machine's own jobs.
    $script:scheduled = $false
    $script:installs = 0
    $schedProbe = {
        param($HordeHome)
        $at = $(if ($script:scheduled) { $HordeHome } else { "" })
        New-HordeKnown -Value ([pscustomobject]@{ jobs = @([pscustomobject]@{ name = "Horde services tend at start-up"; found = $script:scheduled; enabled = $script:scheduled; marked = $script:scheduled; home = $at }, [pscustomobject]@{ name = "Horde services tend"; found = $script:scheduled; enabled = $script:scheduled; marked = $script:scheduled; home = $at }) })
    }
    $probes = @{ identity = $idProbe; makeIdentity = $makeOk; trust = $noPhone; schedule = $schedProbe; elevated = { $false }; installSchedule = { param($HordeHome, $Root) $script:installs++; $script:scheduled = $true } }
    $x = Report $hh $probes
    Check ($x.states -clike "requirements=done home=done relay-settings=done machine-identity=fixed runner-defined=fixed runner-scheduled=todo store-updates-off=done powershell-msi=done") ("the identity is made, the relay runner's service written, and scheduling it is next (" + $x.states + ")")
    $read = Get-HordeServiceDefinitions -HordeHome $hh
    $svc = $(if ($read.state -ceq "read" -and @($read.services).Count -eq 1) { $read.services[0] } else { $null })
    Check ((Test-Ascii $defsPath) -and $null -ne $svc -and $svc.name -ceq "relay-runner" -and (@($svc.start.words) -join " ") -ceq "relay run" -and $svc.start.named["Relay"] -ceq "cloudflare" -and $svc.hordeHome -ceq $hh -and $svc.checkout -ceq $root -and (@($svc.stop.words) -join " ") -ceq "relay stop" -and $svc.alive.path -ceq (Get-HordeRelayRunHeartbeatPath -HordeHome $hh)) ("the file is ASCII, and the real definitions reader takes it: the relay run of this checkout, for this home, alive by the runner's own heartbeat (" + $read.state + " " + (@($read.findings) -join "; ") + ")")
    $elev = Get-HordeSetupElevatedCommand -Root $root -HordeHome $hh
    $b64 = $(if ($elev.line -match "-EncodedCommand ([A-Za-z0-9+/=]+)'\z") { $Matches[1] } else { "" })
    $decoded = $(if ($b64 -ne "") { [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($b64)) } else { "" })
    Check ((Last-Step $x).id -ceq "runner-scheduled" -and (Last-Step $x).said -clike "*is not installed*" -and $script:installs -eq 0 -and $x.next -ceq ("next: in any PowerShell window, run this one line, and allow it to run as administrator: " + $elev.line)) ("MUST FAIL: from a prompt that is not elevated, setup tries nothing and prints the one elevated line (" + $x.next + ")")
    Check ($elev.line -clike "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -NoExit -EncodedCommand *'" -and $decoded -ceq ("$" + "env:HORDE_HOME = '" + $hh + "'; & '" + (Join-Path $root "horde.ps1") + "' services schedule") -and @((Last-Step $x).notes | Where-Object { $_ -ceq ("it runs, as administrator: " + $decoded) }).Count -eq 1) ("and that line runs exactly horde services schedule for this home, which it says in plain words (" + $decoded + ")")
    $probes["elevated"] = { $true }
    $x = Report $hh $probes
    Check ($script:installs -eq 1 -and @($x.report.steps | Where-Object { $_.id -ceq "runner-scheduled" -and $_.state -ceq "fixed" }).Count -eq 1 -and (Last-Step $x).id -ceq "runner-serving" -and (Last-Step $x).said -ceq "the relay runner has never run for this home" -and $x.next -ceq "next: horde relay run -Relay cloudflare, and leave that window open") ("from an elevated prompt the supervisor is scheduled, once, before the runner is asked to serve (" + $x.next + ")")
    $beatPath = Get-HordeRelayRunHeartbeatPath -HordeHome $hh
    $self = Get-HordeHeartbeatSelf
    Write-HordeHeartbeat -Path $beatPath -At ([datetime]::UtcNow) -ProcessId $self.pid -ProcessStartedAt $self.startedAt -TickSeconds 60 -Condition "keys" -Why "cannot open this machine's keys"
    $x = Report $hh $probes
    Check ((Last-Step $x).id -ceq "runner-serving" -and (Last-Step $x).said -clike "*cannot do its work: keys, cannot open this machine's keys*") "MUST FAIL: a runner that beats but cannot do its work is not serving"
    Write-HordeHeartbeat -Path $beatPath -At ([datetime]::UtcNow) -ProcessId $self.pid -ProcessStartedAt $self.startedAt -TickSeconds 60
    $probes["now"] = { [datetime]::UtcNow.AddHours(1) }
    $x = Report $hh $probes
    Check ((Last-Step $x).id -ceq "runner-serving" -and (Last-Step $x).said -clike "*heartbeat is * s old: it is not running") "MUST FAIL: a stale heartbeat is not serving"
    $probes.Remove("now")
    $probes.Remove("trust")
    # The pairing itself is a stand-in here (section 2b runs the real one): it answers that no phone came.
    $script:pairs = 0
    $probes["pairConnect"] = { param($Ctx) New-HordeKnown -Value ([pscustomobject]@{ stand = "in" }) }
    $probes["pair"] = { param($Ctx, $Connection) $script:pairs++; [pscustomobject]@{ ok = $false; reason = "no phone answered (a stand-in)"; device = $null; offer = $null } }
    $script:sayLines = New-Object System.Collections.ArrayList
    $x = Report $hh $probes
    $wantNext = "next: on the phone, open " + $shipped + "/app/index.html, sign in with Google, add it to the home screen and open it from there; then here: horde relay pair -Relay cloudflare -Label ""Test phone"", and in the app: Pair with a machine, Scan the QR code; then type the 12-digit number the phone shows"
    Check ((Last-Step $x).id -ceq "phone-paired" -and (Last-Step $x).said -ceq "no phone is paired with this machine yet; setup tried: the pairing did not finish: no phone answered (a stand-in)" -and $script:pairs -eq 1 -and $x.next -ceq $wantNext) ("MUST FAIL: with the real, empty trust store setup runs the pairing; one that does not finish is said, with the command to pair by hand (" + $x.next + ")")
    $minutes = Get-HordeSetupPairMinutes
    $warning = "The pairing code is valid for " + $minutes + " minutes and works for whoever uses it first: keep it off screen shares and out of photos. If someone else may have seen it, stop (Ctrl+C) and run horde setup again."
    Check ($minutes -ge 1 -and @($script:sayLines | Where-Object { $_ -ceq $warning }).Count -eq 1 -and @((Last-Step $x).notes | Where-Object { $_ -ceq $warning }).Count -eq 1) ("before pairing it says how long the code is good for - horde relay pair's own lifetime, " + $minutes + " minutes - and who it works for")
    Check (@($script:sayLines | Where-Object { $_ -ceq ("Pairing a phone with this machine. On the phone: open " + $shipped + "/app/index.html, sign in with Google, add it to the home screen and open it from there; then, in the app, tap Pair with a machine, then Scan the QR code.") }).Count -eq 1) "and exactly where to tap on the phone"
    $probes["trust"] = { param($HordeHome) New-HordeKnown -Value ([pscustomobject]@{ devices = @([pscustomobject]@{ id = "d1"; state = "pending" }); machines = @(); revoked = @(); phones = @() }) }
    $x = Report $hh $probes
    Check ((Last-Step $x).id -ceq "phone-paired" -and (Last-Step $x).state -ceq "todo") "MUST FAIL: a phone still pending is not paired"
    $x = Report $hh $probes -NoFix @("phone-paired")
    Check ((Last-Step $x).id -ceq "phone-paired" -and (Last-Step $x).said -ceq "no phone is paired with this machine yet" -and $script:pairs -eq 2) "-NoFix phone-paired checks without pairing"
    $probes["trust"] = { param($HordeHome) New-HordeKnown -Value ([pscustomobject]@{ devices = @([pscustomobject]@{ id = "d1"; state = "trusted" }); machines = @(); revoked = @(); phones = @() }) }
    $realDecisions = (Get-HordeSetupDefaultProbes).decisions
    $probes["decisions"] = { param($HordeHome, $Root, [string[]]$HordeArgs) [pscustomobject]@{ code = 1; out = ""; err = "the list is held (a stand-in)" } }
    $x = Report $hh $probes
    Check ((Last-Step $x).id -ceq "test-question" -and (Last-Step $x).said -clike "the decisions list cannot be read: the list is held (a stand-in)*") ("with a trusted phone the test question is next; a decisions list that cannot be read stops it, honestly (" + $x.states + ")")
    $probes["decisions"] = $realDecisions
    $x = Report $hh $probes
    $listed = Horde $hh @("decisions", "list", "-State", "all", "-Json")
    $qs = @(@((($listed.out.Trim()) | ConvertFrom-Json).value.questions) | Where-Object { $_.group -ceq "Setup" })
    Check (@($x.report.steps | Where-Object { $_.id -ceq "test-question" -and $_.state -ceq "fixed" -and $_.said -clike "added question 1: Horde is set up on * - does it reach your phone?" }).Count -eq 1 -and $qs.Count -eq 1 -and $qs[0].title -ceq ("Horde is set up on " + $env:COMPUTERNAME + " - does it reach your phone?") -and $qs[0].askedBy -ceq "horde setup") ("setup adds the test question through the shipped decisions list, once (" + $x.states + ")")
    Check ($script:installs -eq 1 -and $x.report.next -ceq "" -and $x.states -ceq "requirements=done home=done relay-settings=done machine-identity=done runner-defined=done runner-scheduled=done runner-serving=done phone-paired=done test-question=fixed store-updates-off=done powershell-msi=done" -and $x.next -ceq ("all set: this machine runs Horde for its home, and its paired phone is served through relay cloudflare at " + $shipped)) ("the test question added, every step is done: all set (" + $x.states + ")")
    $before = Get-Tree $hh
    $x = Report $hh $probes
    $listed = Horde $hh @("decisions", "list", "-State", "all", "-Json")
    $qs = @(@((($listed.out.Trim()) | ConvertFrom-Json).value.questions))
    Check ($x.states -cnotmatch "fixed|todo" -and $x.next -clike "all set:*" -and (Get-Tree $hh) -ceq $before -and $qs.Count -eq 1 -and $script:installs -eq 1 -and $script:pairs -eq 2) "run again: nothing fixed, no byte changed, no second question, nothing scheduled or paired again - all set"
    $probes["platform"] = { [pscustomobject]@{ windowsMajor = 10; windowsBuild = 19045; desktopShell = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"; edition = "Core"; version = "7.4.1" } }
    $x = Report $hh $probes
    Check ($x.states -ceq "requirements=todo" -and (Last-Step $x).said -ceq "setup is running under PowerShell 7.4.1, not Windows PowerShell 5.1" -and $x.next -ceq ("next: run horde from Windows PowerShell 5.1: powershell -NoProfile -ExecutionPolicy Bypass -File " + $root + "\horde.ps1 setup")) "MUST FAIL: run under PowerShell 7 where it could not run itself again, the requirement stops it first"
    $probes["platform"] = { [pscustomobject]@{ windowsMajor = 6; windowsBuild = 9600; desktopShell = ""; edition = "Desktop"; version = "4.0" } }
    $x = Report $hh $probes
    Check ($x.states -ceq "requirements=todo" -and (Last-Step $x).said -ceq "Windows is version 6; Horde needs 10 or 11; Windows PowerShell 5.1 (powershell.exe) is not installed") "MUST FAIL: an older Windows without Windows PowerShell 5.1 is named, both things"
    $probes.Remove("platform")
    $h5 = Join-Path $work "home-owndefs"
    Write-Text (Join-Path $h5 "settings\service-definitions.json") '{"schemaVersion":1,"settings":{}}'
    $s5 = $script:hasIdentity
    $before = Get-Tree $h5
    $x = Report $h5 @{ identity = $idProbe; makeIdentity = $makeOk; trust = $noPhone }
    $after = @(Get-ChildItem -LiteralPath $h5 -Recurse -File -Force | Where-Object { $_.Name -ceq "service-definitions.json" })
    Check ((Last-Step $x).id -ceq "runner-defined" -and (Last-Step $x).state -ceq "todo" -and $x.next -clike ('next: add "relay-runner": { "checkout": *') -and $after.Count -eq 1 -and [System.IO.File]::ReadAllText($after[0].FullName) -ceq '{"schemaVersion":1,"settings":{}}') "MUST FAIL: a service-definitions file that is there is the person's: setup says what to add, and does not write it"
    $entry = $x.report.next.Substring(4, $x.report.next.IndexOf(" to the settings in ") - 4)
    Check ((Read-HordeServiceDefinitionsText -Text ('{"schemaVersion":1,"settings":{' + $entry + '}}')).state -ceq "read") "and what it says to add is an entry the real reader takes"

    Write-Host ""
    Write-Host "--- 2b. the pairing, run by setup: the real horde relay pair, a test phone, typed through -InputFile ---" -ForegroundColor Cyan
    # A home with a REAL relay identity (software keys, removed in the finally block, as the pairing
    # suite does) and a relay on this disk: the offer, the phone's response and the fingerprint are the
    # real ones. The phone is test/lib/RelayPhone.ps1's; it answers when setup says the offer, by
    # pasting its response into the input file, and the "person" types the number the phone computed.
    if ((Get-HordeRelayKeyStore).state -cne "known") {
        Write-Host "  [SKIP] no key store here, so no machine identity to pair" -ForegroundColor Yellow
        $script:partial = $true
    } else {
        $hp = Join-Path $work "home-pair"
        [void]$script:pairHomes.Add($hp)
        Write-Text (Join-Path $hp "settings\relay.json") '{"schemaVersion":1,"settings":{"horde":"work","pairRpId":"relay.example.test","pairOrigin":"https://relay.example.test"}}'
        $idReal = New-HordeRelayMachineIdentity -HordeHome $hp -Provider "software"
        Check ($idReal.state -ceq "known") "CONTROL: the pairing home has a real relay identity"
        $mailboxes = Join-Path $work "pair-relay"
        [void][System.IO.Directory]::CreateDirectory($mailboxes)
        $typed = Join-Path $work "pair-typed.txt"
        [System.IO.File]::WriteAllText($typed, "", [System.Text.Encoding]::ASCII)
        Write-HordeHeartbeat -Path (Get-HordeRelayRunHeartbeatPath -HordeHome $hp) -At ([datetime]::UtcNow) -ProcessId $self.pid -ProcessStartedAt $self.startedAt -TickSeconds 3600
        $script:phone = New-HordeTestPhone
        $script:pairSaid = New-Object System.Collections.ArrayList
        $script:wrongTyped = $false
        $phoneSay = {
            param($Line)
            $l = "" + $Line
            [void]$script:pairSaid.Add($l)
            if ($l -clike '{"v":1,"kind":"horde-relay-pairing-offer"*') {
                $o = Read-HordeRelayPairingOffer -Text $l
                $pend = Read-HordeRelayRecordText -Text ([System.IO.File]::ReadAllText((Join-Path $hp ("relay\pairing\offers\" + $o.value.offer + ".json")))) -Spec (Get-HordeRelayPendingSpec) -Kind "horde-relay-pairing-pending"
                $resp = New-HordeTestPhonePairingResponse -Offer ([pscustomobject]@{ offer = $o.value.offer; code = $o.value.code; challenge = $pend.value.challenge }) -Phone $script:phone
                [System.IO.File]::AppendAllText($typed, $resp + "`n", [System.Text.Encoding]::ASCII)
            }
            if ($l -clike "*Type that number here*") {
                $dev = @((Get-HordeRelayTrust -HordeHome $hp).value.devices | Where-Object { $_.keyId -ceq $script:phone.keyId }) | Select-Object -First 1
                $fp = "" + $dev.fingerprint
                $wrong = $(if ($fp -ceq "0000-0000-0000") { "1111-1111-1111" } else { "0000-0000-0000" })
                [System.IO.File]::AppendAllText($typed, $wrong + "`n" + $fp + "`n", [System.Text.Encoding]::ASCII)
            }
        }
        $pairProbes = @{
            identity = { param($HordeHome) Read-HordeRelayIdentityRecords -HordeHome $HordeHome }
            schedule = $schedProbe; elevated = { $false }; installSchedule = { param($HordeHome, $Root) $script:installs++ }
            pairConnect = { param($Ctx) Connect-HordeRelay -Name "local" -Options @{ root = $mailboxes } }
        }
        $opened = New-Object System.Collections.ArrayList
        $r = Get-HordeSetupReport -HordeHome $hp -Root $root -Probes $pairProbes -Label "Setup phone" -InputFile $typed -Say $phoneSay -OpenPicture { param($Path) [void]$opened.Add($Path) }
        $states = @($r.steps | ForEach-Object { $_.id + "=" + $_.state }) -join " "
        $pairStep = @($r.steps | Where-Object { $_.id -ceq "phone-paired" }) | Select-Object -First 1
        $saidAll = $script:pairSaid -join "`n"
        Check ($null -ne $pairStep -and $pairStep.state -ceq "fixed" -and $pairStep.said -clike "paired: 'Setup phone' (device *) is trusted") ("setup runs the pairing and the phone is trusted (" + $states + ")")
        Check ($saidAll.Contains("Scan this QR code with the phone app (Pair with a machine, Scan the QR code)") -and $opened.Count -eq 1 -and $saidAll.Contains('{"v":1,"kind":"horde-relay-pairing-offer"') -and $saidAll.Contains("Look at your PHONE: it shows a 12-digit number. Type that number here")) "it shows the QR code (opened as a picture) and the offer, and asks for the number the PHONE shows"
        Check ($saidAll.Contains("That number does not match the device that registered") -and $saidAll.Contains("Confirmed: 'Setup phone'")) "a wrong number is refused and the phone's own number confirms it"
        $devReal = @((Get-HordeRelayTrust -HordeHome $hp).value.devices | Where-Object { $_.keyId -ceq $script:phone.keyId }) | Select-Object -First 1
        Check ($null -ne $devReal -and $devReal.state -ceq "trusted" -and -not $saidAll.Contains($devReal.fingerprint)) "the trust store holds the phone, trusted, and the machine never printed its fingerprint"
        Check ($opened.Count -eq 1 -and -not (Test-Path -LiteralPath $opened[0])) "the picture of the offer is gone"
        Check ((@($r.steps | ForEach-Object { $_.id }) -join ",") -clike "*,phone-paired,test-question*" -and @($r.steps | Where-Object { $_.id -ceq "test-question" -and $_.state -ceq "fixed" }).Count -eq 1) ("on success it moves on to the test question, and adds it (" + $states + ")")
    }

    Write-Host ""
    Write-Host "--- 3. the operator's path, through the shipped command ---" -ForegroundColor Cyan
    $ho = Join-Path $work "home-operator"
    $own = "https://relay.example.workers.dev"
    $callback = $own + "/auth/google/callback"
    $register = "in the Google client, the authorized redirect URI is " + $callback + " and the authorized JavaScript origin is " + $own
    $cfSettings = Join-Path $ho "settings\relay-cloudflare.json"
    $s = Setup $ho @("-Operator", "-NoFix", "machine-identity")
    Check ((Has $s ("  TO DO relay origin: this home uses the shipped relay at " + $shipped + ", which every Horde user shares; a home that hosts its own names it in the setting relayOrigin")) -and $s.next -clike ("next: choose where your relay will answer: find your subdomain in the Cloudflare dashboard*then write " + $cfSettings + " as {""schemaVersion"": 1, ""settings"": {""relayOrigin"": ""https://relay.<subdomain>.workers.dev""}}")) ("MUST FAIL: an operator with no origin of his own is asked for one first (" + $s.next + ")")
    Check (-not (Test-Path -LiteralPath (Join-Path $ho "settings\relay.json"))) "and no user step ran before the operator's"
    Write-Text $cfSettings ('{"schemaVersion":1,"settings":{"relayOrigin":"' + $own + '","wranglerScript":' + (ConvertTo-HordeSetupJsonString $fake) + '}}')
    $s = Setup $ho @("-Operator", "-NoFix", "machine-identity")
    Check ((Has $s ("  done  relay origin: the relay will answer at " + $own + ", as the Worker relay")) -and (Has $s ("  TO DO Google sign-in client: there is no Google client file at " + $clientFile + ": download the web client's JSON from the Google Cloud console there, or name it in the setting googleClientFile")) -and (Has $s ("        " + $register))) "MUST FAIL: no client file - setup names that step, the default place under the profile, and the exact redirect URI and JavaScript origin to register"
    Check ($s.next -clike ("next: make the phone's sign-in client in the Google Cloud console*Web application; give it the redirect URI and JavaScript origin below; download its JSON to " + $clientFile + ", outside every repository*")) ("and how to make it and where to put it (" + $s.next + ")")
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    $r = Horde $ho @("relay", "deploy")
    Check ($r.code -ne 0 -and $r.out.Contains("there is no Google client file") -and -not (Test-Path -LiteralPath $log)) ("MUST FAIL: and the deploy refuses without it, running no wrangler (exit " + $r.code + "; log " + (Test-Path -LiteralPath $log) + "; " + $r.out.Trim() + ")")
    Write-Client -Origin $own
    $s = Setup $ho @("-Operator", "-NoFix", "machine-identity")
    Check ((Has $s ("  done  Google sign-in client: the Google client file " + $clientFile + " is a web client")) -and (HasLike $s ("        WARNING: the Google client file does not list " + $callback + " among its redirect URIs*"))) "MUST FAIL: a client file without the callback is read, and warned about by name"
    Check ((HasLike $s "  done  node: node is installed (*") -and (Has $s "  TO DO relay deployed: nothing has been deployed from this home yet") -and $s.next -ceq "next: first log in to Cloudflare once on this machine, if it has not been: npx wrangler@4.149.0 login (it opens a browser); then horde relay deploy -Relay cloudflare") ("then the deploy, with the login it needs first (" + $s.next + ")")
    Write-Client -Origin $own -WithCallback
    $r = Horde $ho @("relay", "deploy")
    $runs = @($(if (Test-Path -LiteralPath $log) { [System.IO.File]::ReadAllLines($log) | Where-Object { $_ -ne "" } | ForEach-Object { $_ | ConvertFrom-Json } }))
    Check ($r.code -eq 0 -and $runs.Count -eq 4 -and @($runs | Where-Object { (Get-HordeTestMember $_ "config.origin") -cne $own -or (Get-HordeTestMember $_ "config.name") -cne "relay" }).Count -eq 0) ("the operator's deploy goes to his own origin, with the fake wrangler (exit " + $r.code + ")")
    $s = Setup $ho @("-Operator", "-NoFix", "machine-identity")
    Check (-not $s.out.Contains("WARNING") -and (HasLike $s ("  done  relay deployed: deployed from this home to " + $own + " on *")) -and (Has $s ("  fixed relay settings: wrote " + (Join-Path $ho "settings\relay.json") + ": the horde home, the phone app at " + $own)) -and $s.next -ceq "next: horde relay identity -New") ("deployed, the operator goes on to the user's steps, for his own relay (" + $s.next + ")")

    Write-Host ""
    Write-Host "--- the steps, as data, and what was said ---" -ForegroundColor Cyan
    $manPath = Join-Path $root "setup\steps.json"
    $manText = [System.IO.File]::ReadAllText($manPath)
    $man = $manText | ConvertFrom-Json
    $fileIds = @($man.steps | ForEach-Object { $_.id })
    $codeIds = @((Get-HordeSetupStepCode).Keys)
    Check ((Test-Ascii $manPath) -and $man.schemaVersion -eq 1 -and $man.manifestVersion -ge 1 -and $fileIds.Count -ge 10) ("CONTROL: setup\steps.json is ASCII and read (" + $fileIds.Count + " steps)")
    Check (@($fileIds | Where-Object { $codeIds -cnotcontains $_ }).Count -eq 0) ("every step in setup\steps.json has its check in cli/Setup.ps1 (missing: " + (@($fileIds | Where-Object { $codeIds -cnotcontains $_ }) -join ", ") + ")")
    Check (@($codeIds | Where-Object { $fileIds -cnotcontains $_ }).Count -eq 0) ("every check in cli/Setup.ps1 has its step in setup\steps.json (missing: " + (@($codeIds | Where-Object { $fileIds -cnotcontains $_ }) -join ", ") + ")")
    # The manifest's "fixes" starts with "none" exactly where the code has no fix - but for the
    # requirements, whose one fix (running again under 5.1) is the command's own, before any step.
    $code = Get-HordeSetupStepCode
    $mismatch = @($man.steps | Where-Object { $_.id -cne "requirements" -and ($_.fixes -clike "none*") -ne ($null -eq $code[$_.id].fix) } | ForEach-Object { $_.id })
    Check ($mismatch.Count -eq 0) ("a step the manifest says setup does not fix has no fix in the code, and the other way round (" + ($mismatch -join ", ") + ")")
    $mdir = Join-Path $work "manifests"
    [void][System.IO.Directory]::CreateDirectory($mdir)
    foreach ($case in @(
            @{ what = "a step with no check in the code"; text = $manText.Replace('"id": "test-question"', '"id": "made-up-step"'); like = "step 'made-up-step' has no check in this code" },
            @{ what = "a check with no step in the manifest"; text = $manText.Replace('"id": "test-question"', '"id": "home"'); like = "this code checks a step 'test-question' that the manifest does not list" },
            @{ what = "a manifest newer than this code"; text = $manText.Replace('"manifestVersion": 1', '"manifestVersion": 2'); like = "manifestVersion 2 is newer than this code knows (1)" },
            @{ what = "a manifest that is not ASCII"; text = $manText.Replace('"title": "Horde home"', ('"title": "Horde h' + [char]0xF6 + 'me"')); like = "it is not ASCII" })) {
        $mp = Join-Path $mdir ([guid]::NewGuid().ToString("N") + ".json")
        [System.IO.File]::WriteAllText($mp, $case.text, $utf8)
        $m2 = Read-HordeSetupManifest -Path $mp
        $threw = ""
        try { $null = Get-HordeSetupReport -HordeHome (Join-Path $work "never-made") -Root $root -Manifest $mp -Check } catch { $threw = $_.Exception.Message }
        Check ($case.text -cne $manText -and $m2.state -ceq "unknown" -and "$($m2.reason)".Contains($case.like) -and $threw.Contains($case.like) -and -not (Test-Path -LiteralPath (Join-Path $work "never-made"))) ("MUST FAIL: " + $case.what + " refuses the whole manifest, and nothing is checked (" + $m2.reason + ")")
    }
    $r = Horde $hh @("setup", "-Steps", "-Json")
    $listed = $null
    try { $listed = ($r.out.Trim()) | ConvertFrom-Json } catch { $listed = $null }
    $ids = $(if ($null -ne $listed) { @($listed.steps | ForEach-Object { $_.id }) -join "," } else { "" })
    Check ($r.code -eq 0 -and $ids -ceq ($fileIds -join ",") -and $listed.manifestVersion -eq $man.manifestVersion -and @($listed.steps | Where-Object { $_.path -ceq "operator" }).Count -eq 2 -and @($listed.steps | Where-Object { $_.fixedBySetup }).Count -eq 9) ("setup -Steps -Json prints the manifest as this code reads it, in order (" + $ids + ")")
    $all = $script:said -join "`n"
    Check ($script:said.Count -ge 12 -and $all.Contains($callback)) ("CONTROL: " + $script:said.Count + " runs were read, and the search finds what they did say")
    Check (-not $all.Contains($clientSecret) -and -not $all.Contains($clientId)) "nothing setup said ever holds the client's id or secret"
    Check (@($all.ToCharArray() | Where-Object { [int]$_ -gt 126 }).Count -eq 0) "and all of it is ASCII"
} finally {
    # Every key a pairing home made, removed, then checked gone (as test/test-relay-pair-cli.ps1 does).
    $made = New-Object System.Collections.ArrayList
    foreach ($h in @($script:pairHomes)) {
        $dir = Join-Path $h "relay\identity"
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter "machine-*.json")) {
            $m = [regex]::Match([System.IO.File]::ReadAllText($f.FullName), '"scope":"([a-z]+)","signName":"([a-z0-9-]+)".*"agreeName":"([a-z0-9-]+)"')
            if ($m.Success) { foreach ($k in @($m.Groups[2].Value, $m.Groups[3].Value)) { [void]$made.Add(@{ n = $k; s = $m.Groups[1].Value }); try { [void](Remove-HordeRelayKey -Name $k -Scope $m.Groups[1].Value) } catch { } } }
        }
    }
    $left = @($made | Where-Object { (Find-HordeRelayCngKey -Name $_.n -Scope $_.s) -cne "" })
    Check ($left.Count -eq 0 -and ($script:partial -or $made.Count -ge 2)) ("every key the suite's pairing home made is gone (" + $made.Count + " names, " + $left.Count + " left)")
    if ($work -like "*horde-cf-setup-test-*" -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
Check (-not (Test-Path -LiteralPath $work)) "the suite's folder is gone"

if ($script:partial) { Complete-HordeSuite -Success "a partial run: no key store here, so the real pairing was skipped" -PassCode 3 }
Complete-HordeSuite -Success "horde setup fixes what it safely can, runs the pairing, stops with one next step, changes nothing on a second run, and keeps the operator's deploy to the operator"
