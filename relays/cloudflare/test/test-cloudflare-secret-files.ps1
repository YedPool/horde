# DOES THE HOSTED RELAY NAME EVERY FILE ON THIS MACHINE THAT HOLDS ITS SECRETS, FROM ITS SETTINGS AND THE
# ENVIRONMENT ALONE, AND SAY "I CANNOT TELL" RATHER THAN NAME THE WRONG ONE?
#
# relays/cloudflare/SecretFiles.ps1, asked through the port (relays/Port.ps1, WHICH FILES ON THIS MACHINE
# HOLD A RELAY'S SECRETS) exactly as the code that shares a file asks. Pinned here:
#   1. with no settings: the default Google client file under the user's profile, the four places
#      the deploy tool may keep its login, and the default metrics salt file (the request metrics,
#      2026-10-14), each with its fixed words;
#   2. with the setting googleClientFile: that file, wherever it is and whatever it is called - one that
#      does not exist, and one another process holds open and will not share, are still named, because
#      nothing here opens a file - and it is the very path the deploy's own resolver gives; and with the
#      setting metricsSaltFile, that file, by the deploy's own resolver too;
#   3. where the login is: under XDG_CONFIG_HOME when that is set, under APPDATA when it is not, and
#      under the profile's own AppData\Roaming when neither is;
#   4. what it cannot tell, each unknown and each for its own reason: a client file that is not an
#      absolute path, a metrics salt file that is not one, a settings file that fails its checks, no user profile, a configuration folder
#      that is not an absolute path;
#   5. asking writes nothing, and the home asked about is the one read.
#
# EVERYTHING IS THE SUITE'S OWN. The Horde home, the user profile, APPDATA and XDG_CONFIG_HOME are folders
# under the temp folder for as long as the suite runs (the environment is this process's, and is put
# back): no path here is the user's own profile, and no real secret file is named, opened or looked for.
# NOTHING HERE RUNS THE DEPLOY TOOL OR CONTACTS ANYTHING. It needs no node.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "relays\Port.ps1")
foreach ($f in @(Get-HordeRelayFiles)) { . $f }
Set-StrictMode -Version Latest

# This relay's name is its folder's: the suite lives two folders under it.
$relay = Split-Path -Leaf (Split-Path -Parent $here)
$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-cf-secret-files-test-" + [guid]::NewGuid().ToString("N").Substring(0, 12))
$hh = Join-Path $work "home"
$prof = Join-Path $work "profile"
$roaming = Join-Path $work "roaming"
$settingsFile = Join-Path $hh "settings\relay-cloudflare.json"
New-Item -ItemType Directory -Path (Join-Path $hh "settings") -Force | Out-Null
$kept = @{ USERPROFILE = $env:USERPROFILE; APPDATA = $env:APPDATA; XDG_CONFIG_HOME = $env:XDG_CONFIG_HOME }
$clientWords = "the sign-in client file"
$loginWords = "the deploy tool's login"
$saltWords = "the request metrics salt file"

function Set-Settings {
    # The relay's settings file in the suite's home: -Raw as is, -Client as googleClientFile, or none.
    param([string]$Client = "", [string]$Raw = "", [switch]$None, [string]$Salt = "")
    if ($None) { if (Test-Path -LiteralPath $settingsFile) { Remove-Item -LiteralPath $settingsFile -Force }; return }
    if ($Raw -eq "") { $Raw = (@{ schemaVersion = 1; settings = @{ googleClientFile = $Client; metricsSaltFile = $Salt } } | ConvertTo-Json -Depth 4) }
    [System.IO.File]::WriteAllText($settingsFile, $Raw, $utf8)
}
function Ask {
    # The port's answer for the suite's home, and this relay's files in it.
    $a = Get-HordeRelaySecretFiles -HordeHome $hh
    $mine = @()
    if ($a.state -ceq "known") { $mine = @($a.value.files | Where-Object { $_.relay -ceq $relay }) }
    return [pscustomobject]@{ answer = $a; files = $mine; paths = @($mine | ForEach-Object { $_.path }) }
}
function Login-Paths {
    # The four places of the login under -Config (the configuration folder the tool is given).
    param([string]$Config)
    return @((Join-Path $prof ".wrangler\config\default.toml"), (Join-Path $prof ".wrangler\config\default.enc"),
        (Join-Path $Config ".wrangler\config\default.toml"), (Join-Path $Config ".wrangler\config\default.enc"))
}

try {
    $env:USERPROFILE = $prof
    $env:APPDATA = $roaming
    $env:XDG_CONFIG_HOME = ""

    Write-Host ""
    Write-Host "--- 1. with no settings: the default client file, and every place the deploy tool's login may be ---" -ForegroundColor Cyan
    Check (-not (Test-Path -LiteralPath $settingsFile) -and -not (Test-Path -LiteralPath $prof)) "CONTROL: the suite's home holds no settings file, and its profile folder does not even exist"
    Check (@(Get-HordeRelayNames) -ccontains $relay -and $null -ne (Get-HordeRelay -Name $relay).secretFiles) ("this relay hands the port its word on its secret files (" + $relay + ")")
    Check ((@(Get-HordeRelayNames | Where-Object { $null -ne (Get-HordeRelay -Name $_).secretFiles }) -join ",") -ceq $relay) "and of the relays loaded it is the only one that does: a relay on this disk keeps no secret file"
    $q = Ask
    Check ($q.answer.state -ceq "known" -and (@($q.answer.value.asked) -join ",") -ceq $relay) ("asked through the port it can tell, and it was the one asked (" + $q.answer.state + ")")
    $want = @((Join-Path $prof ".horde-secrets\google-oauth-client.json")) + @(Login-Paths -Config (Join-Path $roaming "xdg.config")) + @((Join-Path $prof ".horde-secrets\relay-metrics-salt.txt"))
    Check ($q.paths.Count -eq 6 -and ($q.paths -join "|") -ceq ($want -join "|")) ("it names six files: the default client file under the profile, then the login's two names in the tool's older place and in its newer one, then the default metrics salt file under the profile (" + $q.paths.Count + ")")
    Check ($q.files[0].what -ceq $clientWords -and (@($q.files | Select-Object -Skip 1 -First 4 | ForEach-Object { $_.what } | Sort-Object -Unique) -join "|") -ceq $loginWords -and $q.files[5].what -ceq $saltWords) "each with its own fixed words: the client file is the sign-in client file, the next four the deploy tool's login, the last the request metrics salt file"
    Check (@($q.paths | Where-Object { -not $_.StartsWith($work + "\", [System.StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) "CONTROL: every path named is under the suite's own folder - none is the user's own profile"

    Write-Host ""
    Write-Host "--- 2. with the setting: that file, wherever it is and whatever it is called, and never opened ---" -ForegroundColor Cyan
    $elsewhere = Join-Path $work "elsewhere\any name at all.dat"
    Set-Settings -Client $elsewhere
    $q = Ask
    Check ($q.answer.state -ceq "known" -and $q.paths.Count -eq 6 -and $q.paths[0] -ceq $elsewhere -and $q.files[0].what -ceq $clientWords) ("the client file is the one the setting names, by any name (" + $q.answer.state + ")")
    Check ($q.paths -cnotcontains (Join-Path $prof ".horde-secrets\google-oauth-client.json")) "and the default place is no longer named: it is not where the secret is"
    Check (-not (Test-Path -LiteralPath $elsewhere) -and -not (Test-Path -LiteralPath (Split-Path -Parent $elsewhere))) "CONTROL: that file, and its folder, do not exist - a file is named for where a secret would be, not for being there"
    $resolved = Get-HordeCloudflareRelayClientFile -Values (Get-HordeCloudflareRelaySettings -HordeHome $hh).value
    Check ($resolved -ceq $q.paths[0]) "it is the very path the deploy's own resolver gives: the file named is the file a deploy would read"
    $saltElsewhere = Join-Path $work "salts\any salt.bin"
    Set-Settings -Client $elsewhere -Salt $saltElsewhere
    $q = Ask
    $saltResolved = Get-HordeCloudflareRelayMetricsSaltFile -Values (Get-HordeCloudflareRelaySettings -HordeHome $hh).value
    Check ($q.answer.state -ceq "known" -and $q.paths.Count -eq 6 -and $q.paths[5] -ceq $saltElsewhere -and $q.files[5].what -ceq $saltWords -and $saltResolved -ceq $saltElsewhere -and $q.paths -cnotcontains (Join-Path $prof ".horde-secrets\relay-metrics-salt.txt")) "the metrics salt file is the one its setting names, the deploy's own resolver's, and the default is no longer named"
    Set-Settings -Client $elsewhere
    Set-Settings -Client ((Join-Path $work "elsewhere") + "\..\vault\client.json")
    $q = Ask
    Check ($q.answer.state -ceq "known" -and $q.paths[0] -ceq (Join-Path $work "vault\client.json")) "a setting written with a dot-dot in it is named as the file it opens"
    $noDrive = @([char[]]"BQXYZ" | Where-Object { -not [System.IO.Directory]::Exists($_ + ":\") } | Select-Object -First 1)
    if ($noDrive.Count -eq 1) {
        Set-Settings -Client ($noDrive[0] + ":\keys\client.json")
        $q = Ask
        Check ($q.answer.state -ceq "known" -and $q.paths[0] -ceq ($noDrive[0] + ":\keys\client.json")) ("a client file on a drive that is not there today (" + $noDrive[0] + ":) is still named")
    } else { Write-Host "  [SKIP] every drive letter tried exists here, so a client file on a missing drive was not tried" -ForegroundColor Yellow }
    # A FILE NOBODY ELSE MAY OPEN: held open here without sharing, so anything that tried to read it
    # would fail, and the answer would be unknown.
    $held = Join-Path $work "held-client.json"
    [System.IO.File]::WriteAllText($held, "not a client file, and never read", $utf8)
    Set-Settings -Client $held
    $lock = [System.IO.File]::Open($held, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    try {
        $blocked = $false
        try { $null = [System.IO.File]::ReadAllText($held) } catch { $blocked = $true }
        $q = Ask
    } finally { $lock.Dispose() }
    Check ($blocked) "CONTROL: a file held open without sharing cannot be read by anyone else"
    Check ($q.answer.state -ceq "known" -and $q.paths[0] -ceq $held) "and it is named all the same: nothing here opens the client file"

    Write-Host ""
    Write-Host "--- 3. where the deploy tool's login is, from the environment ---" -ForegroundColor Cyan
    Set-Settings -Client $elsewhere
    $xdg = Join-Path $work "xdg"
    $env:XDG_CONFIG_HOME = $xdg
    $q = Ask
    Check ($q.answer.state -ceq "known" -and (@($q.paths | Select-Object -Skip 1 -First 4) -join "|") -ceq (@(Login-Paths -Config $xdg) -join "|")) "with XDG_CONFIG_HOME set, the login's newer place is under it, and APPDATA is not used"
    $env:XDG_CONFIG_HOME = ""
    $env:APPDATA = ""
    $q = Ask
    Check ($q.answer.state -ceq "known" -and (@($q.paths | Select-Object -Skip 1 -First 4) -join "|") -ceq (@(Login-Paths -Config (Join-Path $prof "AppData\Roaming\xdg.config")) -join "|")) "with neither XDG_CONFIG_HOME nor APPDATA, it is under the profile's own AppData\Roaming, as the tool itself falls back"
    $env:APPDATA = $roaming
    # ON A DRIVE THAT IS NOT THERE, when this machine has such a letter: joining paths by asking the
    # system throws for one (SecretFiles.ps1), and a login on a drive not plugged in is still a login.
    $far = $(if ($noDrive.Count -eq 1) { "" + $noDrive[0] } else { "C" })
    # A throw here is caught and made a failed check: tools\Mutate.ps1 counts a mutant caught only by a
    # check that failed, never by a suite that fell over.
    $own = $null
    try { $own = Get-HordeCloudflareRelayLoginFiles -UserProfile ($far + ":\people\someone") -AppData ($far + ":\roaming") -XdgConfigHome "" } catch { $own = $null }
    Check ($null -ne $own -and $own.state -ceq "known" -and(@($own.value) -join "|") -ceq (@("X:\people\someone\.wrangler\config\default.toml", "X:\people\someone\.wrangler\config\default.enc", "X:\roaming\xdg.config\.wrangler\config\default.toml", "X:\roaming\xdg.config\.wrangler\config\default.enc") -join "|").Replace("X:", $far + ":")) "asked directly, with an environment handed to it - on a drive that need not exist - the four places are exactly: profile\.wrangler and <APPDATA>\xdg.config\.wrangler, each with config\default.toml and config\default.enc"

    Write-Host ""
    Write-Host "--- 4. what it cannot tell is unknown, each for its own reason ---" -ForegroundColor Cyan
    $q = Ask
    Check ($q.answer.state -ceq "known") "CONTROL: before each of these, the same question is answered"
    Set-Settings -Client "keys\client.json"
    $q = Ask
    Check ($q.answer.state -ceq "unknown" -and "$($q.answer.reason)".Contains("'" + $relay + "'") -and "$($q.answer.reason)".Contains("googleClientFile") -and (@($q.answer.relays) -join ",") -ceq $relay) ("a client file that is not an absolute path: unknown, naming this relay and the setting (" + $q.answer.reason + ")")
    Set-Settings -Client $elsewhere -Salt "keys\salt.txt"
    $q = Ask
    Check ($q.answer.state -ceq "unknown" -and "$($q.answer.reason)".Contains("'" + $relay + "'") -and "$($q.answer.reason)".Contains("metricsSaltFile") -and (@($q.answer.relays) -join ",") -ceq $relay) ("a metrics salt file that is not an absolute path: unknown, naming this relay and the setting (" + $q.answer.reason + ")")
    Set-Settings -Raw "{ this is not a settings file"
    $q = Ask
    Check ($q.answer.state -ceq "unknown" -and "$($q.answer.reason)".Contains("settings do not read")) ("a settings file that fails its checks: unknown - never the default read as if nothing were set (" + $q.answer.reason + ")")
    Set-Settings -None
    $env:USERPROFILE = ""
    $q = Ask
    Check ($q.answer.state -ceq "unknown" -and "$($q.answer.reason)".Contains("no user profile") -and "$($q.answer.reason)".Contains("default Google client file")) ("no user profile and no setting: unknown, because there is no default client file to name (" + $q.answer.reason + ")")
    Set-Settings -Client $elsewhere
    $q = Ask
    Check ($q.answer.state -ceq "unknown" -and "$($q.answer.reason)".Contains("no user profile") -and "$($q.answer.reason)".Contains("login")) ("no user profile, with the client file set: still unknown, because where the login is cannot be told (" + $q.answer.reason + ")")
    $env:USERPROFILE = $prof
    $env:XDG_CONFIG_HOME = "config\here"
    $q = Ask
    Check ($q.answer.state -ceq "unknown" -and "$($q.answer.reason)".Contains("configuration folder")) ("a configuration folder that is not an absolute path: unknown (" + $q.answer.reason + ")")
    $env:XDG_CONFIG_HOME = ""
    $q = Ask
    Check ($q.answer.state -ceq "known" -and $q.paths.Count -eq 6) "CONTROL: and with the environment put right it is answered again"

    Write-Host ""
    Write-Host "--- 5. asking writes nothing, and the home asked about is the one read ---" -ForegroundColor Cyan
    $other = Join-Path $work "other-home"
    New-Item -ItemType Directory -Path $other -Force | Out-Null
    $a = Get-HordeRelaySecretFiles -HordeHome $other
    Check ($a.state -ceq "known" -and @($a.value.files)[0].path -ceq (Join-Path $prof ".horde-secrets\google-oauth-client.json")) "another home, with no settings, is answered from that home: the default, not the first home's setting"
    $direct = & (Get-HordeRelay -Name $relay).secretFiles $hh
    Check ((Test-HordeAnswer $direct) -and $direct.state -ceq "known" -and @($direct.value.files)[0].path -ceq $elsewhere) "the block itself, handed a home, reads that home's settings"
    $left = @(Get-ChildItem -LiteralPath $work -Recurse -Force | ForEach-Object { $_.FullName.Substring($work.Length) } | Sort-Object)
    Check (($left -join ",") -ceq "\held-client.json,\home,\home\settings,\home\settings\relay-cloudflare.json,\other-home") ("the suite's folder holds what the suite put there and nothing else: no profile, no secrets folder, no file was made (" + ($left -join ",") + ")")
} finally {
    foreach ($k in @($kept.Keys)) { [System.Environment]::SetEnvironmentVariable($k, $kept[$k], "Process") }
    if ($work -like "*horde-cf-secret-files-test-*" -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
Check (-not (Test-Path -LiteralPath $work) -and $env:USERPROFILE -ceq $kept["USERPROFILE"]) "the suite's folder is gone, and the environment is as it was"

Complete-HordeSuite -Success "the hosted relay names its client file and the deploy tool's login from settings alone, opens neither, and says so when it cannot tell"
