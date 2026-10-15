# DOES A SHARE REFUSE THE PLACES AND THE NAMES SECRETS ARE KEPT UNDER, HOWEVER THE FILE IS REACHED?
#
# files/Deny.ps1, and the two questions files/Path.ps1 asks for it, in this process. The suite ATTACKS
# the list rather than reading it back:
#   - every word of the list at the start, in the middle and at the end of a name, in mixed case and
#     with a double extension - and, on the other side, every ordinary word that holds "key";
#   - every place from both sides of its edge: a file in it, a file in a folder whose name only
#     begins like it, a file beside it;
#   - a file in a place reached by a link to the file, a link to its folder, a junction, a
#     drive, an 8.3 short name, the long-path prefix, another case, a dot or a blank after the
#     folder's name, and a relative path with dot-dot: each is refused AS THE PLACE, which only a
#     rule that judges the open handle's own path can do;
#   - a Horde home that is itself reached through a link;
#   - -Force on every rule: it shares what it lifts, and the Horde home and .horde-secrets are
#     refused all the same, with a reason that says so;
#   - a drive letter that stands for a network drive is refused before anything looks the host up.
# The real command, with its exit codes, is test/test-files-cli.ps1.
#
# NOTHING HERE IS A REAL SECRET, AND NO REAL FOLDER IS READ. The user's profile is a folder this suite
# made (USERPROFILE is set for this process), the home every call is given is in it, the agent
# harnesses are two this suite describes in a repository folder of its own (so no real harness is
# named or looked for), and every file holds dummy words. All of it is one fresh folder under %TEMP%
# that this suite removes (CONTRIBUTING 9).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "files\Share.ps1")

# THE RELAYS ARE LOADED BY files/Deny.ps1 ITSELF, once per load (its header, THE RELAYS' OWN SECRET
# FILES), and a second load in the same scope must not throw the port's "already registered". Asked
# here, first, before anything below replaces a function of that file: a second load defines its
# functions again. Only the relays' NAMES are looked at; no real relay is asked for its files.
Write-Host ""
Write-Host "--- files/Deny.ps1 loads every relay, once, and loading it again is safe ---" -ForegroundColor Cyan
$relayFolderNames = (@(Get-HordeRelayFiles | ForEach-Object { Split-Path -Leaf (Split-Path -Parent $_) }) -join ",")
$loadedRelayNames = (@(Get-HordeRelayNames) -join ",")
Check ($relayFolderNames -ne "" -and $loadedRelayNames -ceq $relayFolderNames) ("loading the share loads every relay the port finds, by its folder's name (" + $loadedRelayNames + ")")
$secondLoad = "loaded"
try { . (Join-Path $root "files\Deny.ps1") } catch { $secondLoad = "threw: " + $_.Exception.Message }
Check ($secondLoad -ceq "loaded" -and (@(Get-HordeRelayNames) -join ",") -ceq $loadedRelayNames) ("files/Deny.ps1 loaded a second time in the same scope does not throw, and every relay is there once (" + $secondLoad + ")")
$thirdLoad = "loaded"
try { . (Join-Path $root "files\Share.ps1") } catch { $thirdLoad = "threw: " + $_.Exception.Message }
Check ($thirdLoad -ceq "loaded" -and (@(Get-HordeRelayNames) -join ",") -ceq $loadedRelayNames) ("and so does the whole share, loaded again over relays that are already registered (" + $thirdLoad + ")")

$script:work = Join-Path $env:TEMP ("horde-files-deny-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
[System.IO.Directory]::SetCurrentDirectory($script:work)
Set-Location -LiteralPath $script:work
# The handle's own path of this suite's folder: %TEMP% is written with an 8.3 short name on some machines.
$probe = Join-Path $script:work "probe.md"; [System.IO.File]::WriteAllText($probe, "probe")
$opened = Open-HordeFilesSource -Path $probe; $opened.stream.Dispose()
$script:real = Split-Path -Parent $opened.path
$profileDir = Join-Path $script:real "profile"
New-Item -ItemType Directory -Path $profileDir | Out-Null
$env:USERPROFILE = $profileDir
# THE PROFILE THE OPERATING SYSTEM NAMES cannot be moved by a variable, which is the point of asking
# it (files/Deny.ps1), so the one function that asks is replaced, for this suite, by one that answers
# with a folder of the suite's own: NO TEST HERE LOOKS AT THE REAL PROFILE. It is called exactly as
# the real one is, with nothing handed to it. The real one is kept, and asked once, further down.
$script:realOsProfile = ${function:Get-HordeFilesOsProfile}
$script:osProfile = Join-Path $script:real "os-profile"
New-Item -ItemType Directory -Path $script:osProfile | Out-Null
function Get-HordeFilesOsProfile { return $script:osProfile }
# Whatever a function here is not handed, it must not find the real home.
$env:HORDE_HOME = Join-Path $script:real "home-nobody-uses"
$env:HORDE_TEST_HARNESS_X_HOME = Join-Path $script:real "harness-x-moved"
$env:HORDE_TEST_HARNESS_Y_HOME = ""
# TWO HARNESSES OF THIS SUITE'S OWN, described the way a real one describes itself.
$repo = Join-Path $script:real "repo"
New-Item -ItemType Directory -Path (Join-Path $repo "agents\harness-x") | Out-Null
New-Item -ItemType Directory -Path (Join-Path $repo "agents\harness-y") | Out-Null
[System.IO.File]::WriteAllText((Join-Path $repo "agents\harness-x\stores.json"), '{ "schemaVersion": 1, "roots": [ { "profile": ".harness-x" }, { "profile": ".harness-x.json" }, { "env": "HORDE_TEST_HARNESS_X_HOME" } ] }')
[System.IO.File]::WriteAllText((Join-Path $repo "agents\harness-y\stores.json"), '{ "schemaVersion": 1, "roots": [ { "profile": ".harness-y" }, { "env": "HORDE_TEST_HARNESS_Y_HOME" } ] }')
$script:n = 0
$sess = New-HordeKnown -Value "deny-session"
# THE RELAYS THIS SUITE ASKS ARE ITS OWN (the relays' secret files, further down): the real ones are
# let go and the port is given relays registered the way a real one registers, through
# Register-HordeRelay, each with a folder and a capabilities.json of this suite's own. So the share
# asks the real Get-HordeRelaySecretFiles, and no real relay's settings or files are looked at.
# Until a section says otherwise, one made-up relay is asked and names no file: the ordinary answer.
$script:relayFixtures = Join-Path $script:real "relays"
$script:entriesA = @()
$script:relayKnownA = { param($h) New-HordeKnown -Value ([pscustomobject]@{ files = @($script:entriesA) }) }
function Set-TestRelays {
    # The port's relays become exactly these: each @{ name; block }, a block of $null registering a
    # relay with no -SecretFiles at all.
    param([object[]]$Relays)
    $script:HordeRelays.Clear()
    foreach ($r in $Relays) {
        $folder = Join-Path $script:relayFixtures $r.name
        if (-not (Test-Path -LiteralPath $folder)) {
            [void][System.IO.Directory]::CreateDirectory($folder)
            [System.IO.File]::WriteAllText((Join-Path $folder "capabilities.json"), ('{ "schemaVersion": 1, "relay": "' + $r.name + '", "capabilities": { "durable": { "support": "yes", "evidence": "fixture" }, "realtime": { "support": "yes", "evidence": "fixture" }, "reach.remote": { "support": "yes", "evidence": "fixture" }, "trim.on.ack": { "support": "yes", "evidence": "fixture" } }, "limits": { "maxTextChars": 4096, "maxBatch": 8, "maxWatchMs": 2000, "retentionSeconds": 0 } }'))
        }
        if ($null -eq $r.block) { $null = Register-HordeRelay -Folder $folder -Connect {} -Put {} -Get {} -Watch {} -Ack {} }
        else { $null = Register-HordeRelay -Folder $folder -Connect {} -Put {} -Get {} -Watch {} -Ack {} -SecretFiles $r.block }
    }
}
function Set-OrdinaryRelays { $script:entriesA = @(); Set-TestRelays @(@{ name = "test-relay-a"; block = $script:relayKnownA }, @{ name = "test-relay-quiet"; block = $null }) }
Set-OrdinaryRelays

function New-TestHome { $script:n++; return (Join-Path $script:real ("home-" + $script:n)) }
function Get-Names {
    param([string]$TestHome)
    $store = Join-Path $TestHome "store\files"
    if (-not (Test-Path -LiteralPath $store)) { return "" }
    return (@(Get-ChildItem -LiteralPath $store -Force | Sort-Object Name | ForEach-Object { $_.Name }) -join ",")
}
function New-File {
    # A file of dummy words at -Path, its folder made: the path.
    param([string]$Path, [string]$Text = "dummy words, and no secret")
    [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [System.IO.File]::WriteAllText($Path, $Text)
    return $Path
}
function Invoke-Share {
    param([string]$TestHome, [string]$Path, [switch]$Force, [string]$Repo = $repo)
    return (Add-HordeFilesShare -Path $Path -Title "A title" -HordeHome $TestHome -Asking $sess -RepoRoot $Repo -Force:$Force)
}
function Test-Refused {
    # Was the share refused with a reason like -Like (and not like -NotLike), the store left as it was?
    param([string]$TestHome, [string]$Path, [string]$Like, [string]$NotLike = "", [switch]$Force, [string]$Repo = $repo)
    $before = Get-Names $TestHome
    $r = [pscustomobject]@{ outcome = "threw"; reason = "" }
    try { $r = Invoke-Share -TestHome $TestHome -Path $Path -Force:$Force -Repo $Repo } catch { $r.reason = "$($_.Exception.Message)" }
    $ok = ($r.outcome -ceq "refused" -and $r.reason -like ("*" + $Like + "*") -and ($NotLike -eq "" -or $r.reason -notlike ("*" + $NotLike + "*")) -and (Get-Names $TestHome) -ceq $before)
    # The store's names before and after are printed when they differ: round 3 of the review of PR
    # 238 saw this helper fail once with the right outcome and reason, and not again (2026-10-14).
    $after = Get-Names $TestHome
    if (-not $ok) { Write-Host ("         got: " + $r.outcome + " - " + $r.reason + $(if ($after -cne $before) { " (the store before: '" + $before + "'; after: '" + $after + "')" } else { "" })) -ForegroundColor Red }
    return $ok
}
function Test-Shared {
    param([string]$TestHome, [string]$Path, [switch]$Force, [string]$Repo = $repo)
    $r = [pscustomobject]@{ outcome = "threw"; reason = "" }
    try { $r = Invoke-Share -TestHome $TestHome -Path $Path -Force:$Force -Repo $Repo } catch { $r.reason = "$($_.Exception.Message)" }
    if ($r.outcome -cne "shared") { Write-Host ("         got: " + $r.outcome + " - " + $r.reason) -ForegroundColor Red }
    return ($r.outcome -ceq "shared")
}
function Write-Skip { param([string]$What) Write-Host ("  [SKIP] " + $What) -ForegroundColor Yellow }
function Test-Link { param([string]$Path) return ((Test-Path -LiteralPath $Path) -and (([System.IO.File]::GetAttributes($Path) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) }
function New-FileLink { param([string]$Link, [string]$Target) $null = & cmd.exe /c ("mklink `"" + $Link + "`" `"" + $Target + "`" >nul 2>nul"); return (Test-Link $Link) }
function New-FolderLink { param([string]$Link, [string]$Target) $null = & cmd.exe /c ("mklink /D `"" + $Link + "`" `"" + $Target + "`" >nul 2>nul"); return (Test-Link $Link) }
function New-Junction { param([string]$Link, [string]$Target) $null = & cmd.exe /c ("mklink /J `"" + $Link + "`" `"" + $Target + "`" >nul 2>nul"); return (Test-Link $Link) }
function Get-ShortPath { param([string]$Path, [switch]$Folder) try { $fso = New-Object -ComObject Scripting.FileSystemObject; if ($Folder) { return $fso.GetFolder($Path).ShortPath }; return $fso.GetFile($Path).ShortPath } catch { return "" } }
function Get-FreeLetters {
    # Letters that name nothing, for a POWERSHELL drive of this process's own (which is no drive
    # letter of the system's: no other process sees it). Nothing is defined here, only asked.
    $taken = @([System.IO.DriveInfo]::GetDrives() | ForEach-Object { $_.Name.Substring(0, 1) })
    return @("QWXYZVUHGFEDBA".ToCharArray() | ForEach-Object { "" + $_ } | Where-Object { $taken -cnotcontains $_ -and -not [System.IO.Directory]::Exists($_ + ":\") -and $null -eq (Get-PSDrive -Name $_ -ErrorAction SilentlyContinue) })
}
function New-NoHost { return ("horde-" + [guid]::NewGuid().ToString("N").Substring(0, 10)) }

$never = "Nothing there is ever shared, and -Force does not change that"
$insist = "share it again with -Force"
$inHome = "is under the Horde home"
$inSecrets = "is under a .horde-secrets folder"
$inSsh = "is under the folder the user's SSH keys are kept in"
$inAgent = "is under a folder an agent harness keeps its own files in"

# NOT ONE try AROUND THE CHECKS (test/test-files-store.ps1 has the measurement): the sections are plain
# statements, and so is the removal at the end.

Write-Host ""
Write-Host "--- the list: one place, six words, and what -Force may lift ---" -ForegroundColor Cyan
$list = Get-HordeFilesDenyList
$anywhereWords = (@($list.words | Where-Object { $_.how -ceq "anywhere" } | ForEach-Object { $_.word }) -join ",")
$wholeWords = (@($list.words | Where-Object { $_.how -ceq "word" } | ForEach-Object { $_.word }) -join ",")
Check ($anywhereWords -ceq "credential,secret,key,password,passwd,.env,passphrase,mnemonic,kubeconfig,accesstoken,refreshtoken,authtoken") ("the words looked for anywhere in a name are five of the six first asked for, passwd, three the second round of the review added and the three token words of the next round (" + $anywhereWords + ")")
Check ($wholeWords -ceq "token,auth,oauth,cred,private,wallet,cookie,recovery,env,service-account,id_rsa,id_dsa,id_ecdsa,id_ed25519,pem,pfx,p12,ppk,kdbx,jks,netrc,npmrc,pypirc,tfstate,pwd,totp,seed,jwt,vault,2fa") ("the short words, looked for only as whole words, are these, token now among them (" + $wholeWords + ")")
Check (@($list.words | Where-Object { $_.how -cne "anywhere" -and $_.how -cne "word" }).Count -eq 0 -and @($list.words).Count -eq 42) "every word says which of the two ways it is looked for, and there are 42"
Check ((@($list.signInFolders) -join ",") -ceq ".aws,.azure,.kube,.docker" -and (@($list.signInNames) -join ",") -ceq "config.json") "a cloud tool's sign-in is config.json in one of four folders"
Check ($list.secretsFolder -ceq ".horde-secrets" -and $list.sshFolder -ceq ".ssh" -and $list.homeFolder -ceq ".horde") "the three folders of the profile are .horde, .horde-secrets and .ssh"
$wasHome = $env:HORDE_HOME; $env:HORDE_HOME = ""
$defaultHome = Get-HordeHome
$env:HORDE_HOME = $wasHome
Check ($defaultHome -ceq (Join-Path $profileDir $list.homeFolder)) ("and the first is what core/Home.ps1 calls the home when no variable moves it (" + (Split-Path -Leaf $defaultHome) + ")")
Check (@($list.ordinary.Keys).Count -eq 1 -and @($list.ordinary["key"]).Count -eq 15) ("only 'key' has ordinary words taken out of a name first, and there are 15 of them (" + @($list.ordinary["key"]).Count + ")")
$h = New-TestHome
$found = Get-HordeFilesDenyPlaces -HordeHome $h -RepoRoot $repo
$kinds = (@($found.places | ForEach-Object { $_.kind + ":" + $_.force }) -join ",")
Check ($found.unknown -eq "" -and $found.unknownNever -eq "" -and $kinds -ceq "home:False,home:False,secrets:False,ssh:False,home:False,secrets:False,ssh:False,agent:True,agent:True,agent:True,agent:True,agent:True,agent:True,agent:True") ("the places: the home that was named; then under the profile the variable names and again under the one the system names, .horde, .horde-secrets and .ssh, which -Force never lifts; then each harness's folders, which it does, each named once (" + $kinds + ")")
$placePaths = @($found.places | ForEach-Object { $_.path })
Check ($placePaths[0] -ceq $h -and $placePaths -ccontains (Join-Path $profileDir ".horde") -and $placePaths -ccontains (Join-Path $profileDir ".horde-secrets") -and $placePaths -ccontains (Join-Path $profileDir ".ssh")) "the home is the one the caller named, and the three folders are in the profile the variable names"
Check ($placePaths -ccontains (Join-Path $script:osProfile ".horde") -and $placePaths -ccontains (Join-Path $script:osProfile ".horde-secrets") -and $placePaths -ccontains (Join-Path $script:osProfile ".ssh")) "and in the profile the operating system names, which is another folder here"
Check ($placePaths -ccontains (Join-Path $profileDir ".harness-x") -and $placePaths -ccontains (Join-Path $profileDir ".harness-y") -and $placePaths -ccontains $env:HORDE_TEST_HARNESS_X_HOME) "each harness's folders are the ones its own stores.json declares: in the profile, and where its variable moves its store"
Check ($placePaths -ccontains (Join-Path $script:osProfile ".harness-x") -and $placePaths -ccontains (Join-Path $script:osProfile ".harness-y")) "and each harness's folder in the system's profile is a place too"
$realRepo = Get-HordeFilesDenyPlaces -HordeHome $h
$declared = @(Get-ChildItem -LiteralPath (Join-Path $root "agents") -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "stores.json") })
Check ($realRepo.unknown -eq "" -and $declared.Count -ge 1 -and @($realRepo.places | Where-Object { $_.kind -ceq "agent" }).Count -ge (2 * $declared.Count)) ("with no folder named, the shipped harnesses are read: every one of the " + $declared.Count + " that declares its stores gives a folder under each of the two profiles")
# THE REAL FUNCTION, asked once and only for a path: nothing is opened. It answers what the system's
# own call answers, and NOT what the variable says, which this suite set to a folder of its own.
$systemSays = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
$realAnswer = & $script:realOsProfile
Check ($realAnswer -is [string] -and $realAnswer -ceq $systemSays -and $systemSays -ne "") "the real question of the operating system answers what GetFolderPath answers for the user's profile"
Check ($realAnswer -cne $env:USERPROFILE -and $env:USERPROFILE -ceq $profileDir) "MEASURED HERE: with USERPROFILE set to this suite's folder, the system's answer is not that folder - a variable does not move it"
Check ((Get-HordeFilesDenyProfiles).variable -ceq $profileDir -and (Get-HordeFilesDenyProfiles).system -ceq $script:osProfile) "the two profiles are the variable's and the one that question answers"

Write-Host ""
Write-Host "--- a name: each word at the start, in the middle and at the end, in any case of A to Z ---" -ForegroundColor Cyan
$refusedNames = [ordered]@{
    "credential" = @("credentials.json", "my-credential-notes.md", "aws.credential", "CREDENTIALS.TXT", "GoogleCredentials.json", ".git-credentials", "credentials")
    "secret" = @("secret.md", "top-secret-plan.md", "client_secret", "Secrets.json", "MySecretNotes.md", "secretary.txt")
    "token" = @("token.txt", "my-token-list.md", "access_token", "TOKENS.json", "refresh-token.json", "token-budget-analysis.md", "x.token")
    "key" = @("key.md", "api-key.txt", "id_rsa.key.txt", "keys.json", "KEY.MD", "mykey.txt", "keyed.md", "ApiKey.json", "private-key-notes.md", "x.key", "apikeys.txt", "key2.json", "monkey-api-key.txt", "keyboard.key.md", "turkeykey.md", "release.keystore", "private-key.md")
    "password" = @("password.txt", "my-passwords-old.md", "wifi_password", "PASSWORDS.md", "PassWord.txt", "passwordless.md")
    "passwd" = @("passwd.txt", "htpasswd.txt", ".htpasswd", "PASSWD.md", "etc-passwd-copy.txt")
    ".env" = @(".env", ".env.local", "prod.env", "prod.env.txt", ".ENV.json", ".envrc", "notes.environment.md")
    # THE SHORT WORDS, each only as a whole word of the name: alone, with one s, between other
    # words, in capitals, and where a small letter meets a capital.
    "auth" = @("auth.json", "AUTH.md", "my-auth-notes.txt", "auths.json", "harnessAuth.json", "auth_backup.txt", "x.auth")
    "oauth" = @("oauth_creds.json", "oauth.json", "google-oauth-client.json", "oauthCreds.json", "OAUTH.txt")
    "cred" = @("creds.md", "cred.txt", "my_creds.json", "awsCreds.json", "CREDS.TXT")
    "private" = @("private.pem.txt", "private.md", "PRIVATE-notes.txt", "my.private.json")
    "wallet" = @("wallet.json", "wallets.md", "my-wallet.txt", "WALLET.json")
    "cookie" = @("cookies.json", "cookie.txt", "session-cookies.txt", "browserCookies.json")
    "recovery" = @("recovery-codes.txt", "2fa-recovery.md", "RECOVERY.txt")
    "env" = @("env.json", "test-env.md", "ENV.txt", "envs.json", "prodEnv.json")
    "service-account" = @("service-account.json", "service_account.json", "serviceAccount.json", "gcp-service-accounts.md", "service account.txt", "SERVICE.ACCOUNT.json")
    "id_rsa" = @("id_rsa.txt", "id_rsa", "id_rsa.pub", "id-rsa.md", "ID_RSA.TXT", "idRsa.txt", "my_id_rsa_copy.txt")
    "id_dsa" = @("id_dsa.txt", "id_dsa.pub")
    "id_ecdsa" = @("id_ecdsa.txt", "id_ecdsa.pub")
    "id_ed25519" = @("id_ed25519", "id_ed25519.pub", "id_ed25519.txt", "ID-ED25519.md")
    "pem" = @("cert.pem", "server.pem.txt", "PEM.md", "chain_pem.txt")
    "pfx" = @("cert.pfx", "cert.pfx.txt")
    "p12" = @("store.p12", "apple-p12-notes.md")
    "ppk" = @("putty.ppk", "server.ppk.txt")
    "kdbx" = @("vault.kdbx", "vault.kdbx.md")
    "jks" = @("app.jks", "release.jks.txt")
    "netrc" = @(".netrc", "_netrc", "netrc.txt")
    "npmrc" = @(".npmrc", "npmrc.md")
    "pypirc" = @(".pypirc", "pypirc.txt")
    "tfstate" = @("terraform.tfstate", "terraform.tfstate.backup", "prod.tfstate.json")
    # THE NINE THE SECOND ROUND OF THE REVIEW ADDED: three anywhere, six as whole words.
    "passphrase" = @("passphrase.txt", "gpg-passphrase.md", "PASSPHRASES.md", "myPassphraseNotes.txt")
    "mnemonic" = @("mnemonic.txt", "my-mnemonic-phrase.md", "MNEMONICS.md")
    "kubeconfig" = @("kubeconfig", "kubeconfig.json", "prod.kubeconfig.txt", "KubeConfig.md", "mykubeconfigs.md")
    "pwd" = @("pwd.txt", "my-pwd.md", "PWD.md", "pwds.txt", "dbPwd.json")
    "totp" = @("totp.txt", "totp-setup.md", "TOTP.md", "totps.json")
    "seed" = @("seed.txt", "seeds.md", "bip39-seed.txt", "SEED.md", "seed-data.json")
    "jwt" = @("jwt.json", "jwts.md", "my-jwt.txt", "JWT.md")
    "vault" = @("vault.json", "vaults.md", "my-vault.txt", "VAULT.md")
    "2fa" = @("2fa.txt", "my-2fa.md", "2FA.md", "2fas.txt")
    # THE THREE TOKEN WORDS OF THE NEXT ROUND, letters anywhere: run together, as token alone missed.
    "accesstoken" = @("ACCESSTOKEN.txt", "accesstoken.json", "github-accesstoken.md", "myAccesstokens.txt", "AccessToken.json")
    "refreshtoken" = @("refreshtoken.txt", "REFRESHTOKEN.json", "old_refreshtoken.md", "refreshToken.json")
    "authtoken" = @("authtoken.txt", "AUTHTOKEN.md", "ngrok-authtoken.json", "oauthtoken.json", "AuthToken.md")
}
Check (@($refusedNames.Keys).Count -eq @($list.words).Count -and @($list.words | Where-Object { -not $refusedNames.Contains($_.word) }).Count -eq 0) ("every word of the list has names here that only it refuses (" + @($refusedNames.Keys).Count + " of " + @($list.words).Count + ")")
# THE TWELVE NAMES THE REVIEW OF 2026-10-13 MEASURED BEING SHARED: each is refused now.
$reviewed = @("auth.json", "oauth_creds.json", "creds.md", "service-account.json", "id_rsa.txt", "private.pem.txt", "passwd.txt", "htpasswd.txt", "env.json", "wallet.json", "cookies.json", "recovery-codes.txt")
$stillPassing = @($reviewed | Where-Object { (Get-HordeFilesDenyWord -Name $_) -ceq "" })
Check ($reviewed.Count -eq 12 -and $stillPassing.Count -eq 0) ("the twelve names the review measured passing are each refused" + $(if ($stillPassing.Count) { " (STILL PASSING: " + ($stillPassing -join ", ") + ")" } else { "" }))
foreach ($word in $refusedNames.Keys) {
    $missed = @($refusedNames[$word] | Where-Object { (Get-HordeFilesDenyWord -Name $_) -cne $word })
    Check ($missed.Count -eq 0) ("'" + $word + "' is found in all " + @($refusedNames[$word]).Count + " names that hold it: " + (@($refusedNames[$word]) -join ", ") + $(if ($missed.Count) { " (MISSED: " + ($missed -join ", ") + ")" } else { "" }))
}
$plainNames = @("report.md", "notes.txt", "chart.png", "a", "", "ke y.md", "k-e-y.md", "tok.en.md", "pass-word.md", "secre.t", "environment.md", "x.en.v", "credentia.md", "passwor.d")
$caught = @($plainNames | Where-Object { (Get-HordeFilesDenyWord -Name $_) -cne "" })
Check ($caught.Count -eq 0) ("CONTROL: " + $plainNames.Count + " names that hold no word of the list, a word cut short and a word broken by a character among them, are let by" + $(if ($caught.Count) { " (CAUGHT: " + ($caught -join ", ") + ")" } else { "" }))
# A SOFT HYPHEN OR A ZERO-WIDTH SPACE INSIDE A LONG WORD IS JUDGED AS WRITTEN, by code units (the
# review of PR 238, the survivor of 227's nets, word-looked-for-by-the-runtimes-own-comparison): a
# comparison of the runtime's own would take pass<U+00AD>word for password; the list's does not. Both
# characters are invisible, and the rule is the one written in the header, so this pins it.
$invisible = @(("pass" + [char]0x00AD + "word.txt"), ("pass" + [char]0x200B + "word.txt"), ("secr" + [char]0x00AD + "et-notes.md"), ("creden" + [char]0x200B + "tial.json"))
$takenAsTheWord = @($invisible | Where-Object { (Get-HordeFilesDenyWord -Name $_) -cne "" })
Check ($takenAsTheWord.Count -eq 0) ("a soft hyphen (U+00AD) or a zero-width space (U+200B) inside a long word: the name is judged as written, ordinal, and is not the word (" + $takenAsTheWord.Count + " of " + $invisible.Count + " taken for it)")
Check ((Get-HordeFilesDenyWord -Name "password.txt") -ceq "password" -and (Get-HordeFilesDenyWord -Name "secret-notes.md") -ceq "secret" -and (Get-HordeFilesDenyWord -Name "credential.json") -ceq "credential") "CONTROL: the same names without the invisible character are each the word"
# A SHORT WORD INSIDE A LONGER ONE IS NOT THE WORD: the five names the review said must pass, and
# for every short word a name that only holds its letters.
$holdTheLetters = @("author-notes.md", "template.html", "credits.md", "privateer.txt", "cookiecutter.md",
    "authentication-design.html", "authorization-matrix.md", "unauthorized.md", "oauthenticity.md", "incredible.md", "credo.txt", "privately.md", "walletless.md", "cookiebar.png",
    "recoveryless.md", "envelope.md", "environment-setup.md", "serviceaccounting.md", "pemmican.md", "tempemail.md", "ppkg.md", "jksdf.md", "netrcx.md",
    "tokenizer.md", "tokenizer-comparison.md", "tokenization.md", "detokenize.md", "seedling.md", "linseed.md", "vaulted.md", "pwdump.md", "totpx.md", "jwtk.md", "2fab.md", "12fa.md")
$caught = @($holdTheLetters | Where-Object { (Get-HordeFilesDenyWord -Name $_) -cne "" })
Check ($caught.Count -eq 0) ("CONTROL: " + $holdTheLetters.Count + " names that hold a short word's letters inside a longer word are let by" + $(if ($caught.Count) { " (CAUGHT: " + ($caught -join ", ") + ")" } else { "" }))
# THE WORDS OF AN ENTRY STAND TOGETHER, IN ORDER, AND ONLY THE LAST MAY TAKE AN s.
$notTheRun = @("account-service.md", "service-desk-account.md", "rsa-id.txt", "id-notes-rsa.md", "services-account.md", "ids-rsa.md", "id.md", "rsa.md", "service.md", "account.md", "authss.md", "cookiess.md")
$caught = @($notTheRun | Where-Object { (Get-HordeFilesDenyWord -Name $_) -cne "" })
Check ($caught.Count -eq 0) ("CONTROL: an entry of two words is those two, together and in that order, and one s is one s (" + $notTheRun.Count + " names let by)" + $(if ($caught.Count) { " (CAUGHT: " + ($caught -join ", ") + ")" } else { "" }))
Check (((Get-HordeFilesNameWords -Name "oauthCreds.OLD_v2 final-COPY.json") -join ",") -ceq "oauth,creds,old,v2,final,copy,json") ("a name is cut at what is no letter or digit and where a small letter meets a capital, and its words are in lower case (" + ((Get-HordeFilesNameWords -Name "oauthCreds.OLD_v2 final-COPY.json") -join ",") + ")")
Check (@(Get-HordeFilesNameWords -Name "").Count -eq 0 -and @(Get-HordeFilesNameWords -Name "...--__").Count -eq 0) "a name with no letter or digit has no words"
Check ((Get-HordeFilesDenyWord -Name ("auth" + [char]0xE9 + "x.json")) -ceq "auth" -and (Get-HordeFilesDenyWord -Name ([char]0x05D0 + "cred" + [char]0x05D0 + ".md")) -ceq "cred") "a letter outside ASCII ends a word and never hides one: a short word beside such a letter is still the word"
# KNOWN LIMITS of the whole-word way, pinned so that changing them is a decision.
# mytoken.txt IS LET BY, ON PURPOSE (files/Deny.ps1, THE THREE TOKEN WORDS): catching it needs a third
# way of looking, a word that ends in token, which the review did not ask for.
Check ((Get-HordeFilesDenyWord -Name "mytoken.txt") -ceq "" -and (Get-HordeFilesDenyWord -Name "githubtoken.json") -ceq "") "DECIDED: a name word that only ENDS in token (mytoken.txt, githubtoken.json) is not found"
Check ((Get-HordeFilesDenyWord -Name "authfile.json") -ceq "" -and (Get-HordeFilesDenyWord -Name "AUTHFile.json") -ceq "" -and (Get-HordeFilesDenyWord -Name "auth2.json") -ceq "") "KNOWN LIMIT: a short word run into another with no capital between them, or with a digit after it, is not found"

Write-Host ""
Write-Host "--- sixty ordinary names: how many the words refuse, and which word ---" -ForegroundColor Cyan
# MEASURED, NOT TUNED (the review asked for the count). These are names a session would give a file
# it shares, written down before the rule was run on them: eight are the review's own examples.
# The count is pinned so that a change to the words shows what it costs in ordinary names.
$ordinaryNames = @("author-notes.md", "authentication-design.html", "credits.md", "private-beta-plan.md", "template.html", "problem-report.md", "recovery-plan.md", "cookie-banner.png",
    "README.md", "handoff-20261013-094438.md", "report.html", "summary.md", "architecture-overview.md", "meeting-notes.txt", "release-notes.md", "CHANGELOG.md",
    "test-results.json", "coverage-report.html", "screenshot-2026-10-13.png", "design-review.pdf", "api-reference.md", "keyboard-shortcuts.md", "key-findings.md", "monkey-patch-notes.md",
    "keynote-outline.md", "tokenizer-comparison.md", "token-budget-analysis.md", "password-reset-flow.md", "migration-plan.md", "bug-review.md", "environment-setup.md", "deployment-checklist.md",
    "error-log.txt", "metrics-dashboard.html", "cost-model.md", "config-example.json", "package.json", "schema.json", "diagram.png", "logo.webp",
    "invoice.pdf", "user-guide.pdf", "interview-questions.md", "roadmap-2027.md", "benchmark-results.json", "login-page-mockup.png", "session-transcript-summary.md", "secrets-management-proposal.md",
    "authorization-matrix.md", "oauth-flow-diagram.png", "auth-flow.md", "cookiecutter-template.md", "disaster-recovery-runbook.md", "index.html", "notes.txt", "todo.md",
    "comparison-table.md", "sprint-retro.md", "timeline.gif", "onboarding.md", "faq.md", "data-export.json", "style-guide.md", "credit-card-form-mockup.png")
$byWord = @{}
foreach ($ordinaryName in $ordinaryNames) { $fired = Get-HordeFilesDenyWord -Name $ordinaryName; if ($fired -cne "") { if (-not $byWord.ContainsKey($fired)) { $byWord[$fired] = New-Object System.Collections.ArrayList }; [void]$byWord[$fired].Add($ordinaryName) } }
$tally = (@($byWord.Keys | Sort-Object | ForEach-Object { $_ + "=" + $byWord[$_].Count + " (" + ($byWord[$_] -join ", ") + ")" }) -join "; ")
$refusedOrdinary = 0; foreach ($firedWord in $byWord.Keys) { $refusedOrdinary += $byWord[$firedWord].Count }
Write-Host ("  [MEASURED] of " + $ordinaryNames.Count + " ordinary names, " + $refusedOrdinary + " are refused: " + $tally) -ForegroundColor Yellow
Check ($ordinaryNames.Count -eq 64 -and @($ordinaryNames | Select-Object -Unique).Count -eq 64) "the sample is 64 different names"
Check (@($byWord.Keys | Where-Object { $byWord[$_].Count -gt 2 }).Count -eq 0) ("no word refuses more than two of them (" + $tally + ")")
Check ($refusedOrdinary -eq 10) ("and 10 of the 64 are refused, each of which -Force shares (" + $refusedOrdinary + ")")
Check ((Get-HordeFilesDenyWord -Name "tokenizer-comparison.md") -ceq "" -and (Get-HordeFilesDenyWord -Name "token-budget-analysis.md") -ceq "token") "the one that is no longer refused is tokenizer-comparison.md, since token became a whole word; token-budget-analysis.md still is, as accepted"
Check (@(@("passphrase", "mnemonic", "kubeconfig", "pwd", "totp", "seed", "jwt", "vault", "2fa") | Where-Object { $byWord.ContainsKey($_) }).Count -eq 0) "and none of the nine words the second round added refuses any of the 64"
foreach ($plain in @($list.ordinary["key"])) {
    $alone = @(($plain + ".md"), ($plain.ToUpperInvariant() + "s.png"), ("my-" + $plain + "-notes.txt"))
    $wrong = @($alone | Where-Object { (Get-HordeFilesDenyWord -Name $_) -cne "" })
    Check ($wrong.Count -eq 0 -and (Get-HordeFilesDenyWord -Name ($plain + "-key.md")) -ceq "key" -and (Get-HordeFilesDenyWord -Name ("key" + $plain + ".md")) -ceq "key") ("'" + $plain + "' alone is no secret (" + ($alone -join ", ") + "), and with a key beside it the name is refused" + $(if ($wrong.Count) { " (REFUSED: " + ($wrong -join ", ") + ")" } else { "" }))
}
Check ((Get-HordeFilesDenyWord -Name "monkeyboard.md") -ceq "" -and (Get-HordeFilesDenyWord -Name "kekeyboardy.md") -ceq "") "an ordinary word leaves a gap behind it, so what stood on its two sides never joins into 'key'"
# KNOWN LIMITS, pinned so that changing them is a decision: a look-alike letter is not the letter
# (U+212A is the Kelvin sign, which an ignore-case comparison takes for k), and a name with a
# character no eye sees inside the word (U+00AD, a soft hyphen) does not hold the word.
Check ((Get-HordeFilesDenyWord -Name ("to" + [char]0x212A + "en.md")) -ceq "" -and (Get-HordeFilesDenyWord -Name ("to" + [char]0xAD + "ken.md")) -ceq "") "KNOWN LIMIT: a look-alike letter, or a word with an unseen character inside it, is not the word"
Check (("to" + [char]0xAD + "ken.md") -ceq "token.md") "CONTROL: PowerShell's own comparison DOES take that name for token.md, which is why the list compares code units"
Check ((Get-HordeFilesDenyWord -Name ("TOKEN" + [char]0xC9 + ".md")) -ceq "token") "and only A to Z are folded: capitals beside a letter outside ASCII are still found"

Write-Host ""
Write-Host "--- a name, through a share: refused, shared with -Force, and only the file's own name counts ---" -ForegroundColor Cyan
$h = New-TestHome
$docs = Join-Path $script:real "docs"
foreach ($named in @("api-key.txt", "Passwords.md", "my-token.json", "client_secret.txt", "credentials.md", "prod.env.txt", "auth.json", "id_rsa.txt", "serviceAccount.json", "cookies.txt")) {
    $text = "dummy words, and no secret"; if ($named -like "*.json") { $text = '{"dummy":1}' }
    $file = New-File (Join-Path $docs $named) $text
    $word = Get-HordeFilesDenyWord -Name $named
    Check (Test-Refused $h $file ("its name, '" + $named + "', holds '" + $word + "'")) ($named + " is refused, and the reason names the file and the word")
    Check (Test-Refused $h $file $insist) "and says that -Force shares it"
    Check (Test-Shared $h $file -Force) "with -Force it is shared"
}
Check (Test-Shared $h (New-File (Join-Path $docs "keyboard.md"))) "CONTROL: keyboard.md is shared with no -Force"
Check (Test-Shared $h (New-File (Join-Path $docs "monkey.txt"))) "CONTROL: and so is monkey.txt"
Check (Test-Shared $h (New-File (Join-Path $docs "author-notes.md"))) "CONTROL: and author-notes.md, which only holds the letters of a short word"
# A CLOUD TOOL'S SIGN-IN, by its name and its folder's together, on the final path.
$cloud = Join-Path $script:real "cloud"
foreach ($signInFolder in @(".aws", ".azure", ".kube", ".docker")) {
    $signIn = New-File (Join-Path $cloud ($signInFolder + "\config.json")) '{"dummy":1}'
    Check (Test-Refused $h $signIn ("its name, 'config.json', in a folder named '" + $signInFolder + "', is what a cloud tool calls the file it keeps its sign-in in")) ("config.json in a folder named " + $signInFolder + " is refused, and the reason names both")
    Check (Test-Refused $h $signIn $insist) "and says that -Force shares it"
}
Check (Test-Shared $h (Join-Path $cloud ".aws\config.json") -Force) "with -Force it is shared"
Check (Test-Refused $h (New-File (Join-Path $cloud "upper\.AWS\Config.JSON") '{"dummy":1}') "in a folder named '.AWS'") "in any case of the letters of both names"
Check (Test-Shared $h (New-File (Join-Path $cloud "aws\config.json") '{"dummy":1}')) "CONTROL: config.json in a folder named aws, with no dot, is shared"
Check (Test-Shared $h (New-File (Join-Path $cloud ".aws\deeper\config.json") '{"dummy":1}')) "CONTROL: and one deeper under .aws, in a folder of another name: the folder the file is IN is the one that counts"
Check (Test-Shared $h (New-File (Join-Path $cloud ".aws\notes.md"))) "CONTROL: another file in such a folder is shared"
Check (Test-Shared $h (New-File (Join-Path $cloud ".aws2\config.json") '{"dummy":1}')) "CONTROL: and so is config.json in a folder whose name only begins like one"
Check ((Get-HordeFilesNameRefusal -Parts @("C:", ".aws", "credentials")) -like "*holds 'credential'*" -and (Get-HordeFilesNameRefusal -Parts @("C:", "config.json")) -eq "" -and (Get-HordeFilesNameRefusal -Parts @("C:", ".aws", "config.json")) -ne "") "the other file such a folder keeps, credentials, is refused by the word; and a file at the root of a drive is in no folder"
Check (Test-Shared $h (New-File (Join-Path $script:real "secrets\token-store\passwords\report.md"))) "a file with an innocent name in folders named secrets, token-store and passwords is shared: a folder is a place, and only the listed places are refused (the header of files/Deny.ps1 says why)"

Write-Host ""
Write-Host "--- the places, from both sides of each edge ---" -ForegroundColor Cyan
$h = New-TestHome
$null = Invoke-Share -TestHome $h -Path (New-File (Join-Path $docs "first.md"))
Check ([System.IO.Directory]::Exists((Join-Path $h "store\files"))) "CONTROL: the home is there, with its store"
$inSettings = New-File (Join-Path $h "settings\notes.json") '{"dummy":1}'
Check (Test-Refused $h $inSettings $inHome) "a file in the Horde home's settings folder is refused as the Horde home"
Check (Test-Refused $h $inSettings $never) "and the reason says -Force does not change that"
Check (Test-Refused $h $inSettings $inHome -Force) "with -Force it is refused all the same"
Check (Test-Refused $h $inSettings $never -Force) "with the same reason"
$record = @(Get-ChildItem -LiteralPath (Join-Path $h "store\files") -Filter "*.json")[0].FullName
Check (Test-Refused $h $record $inHome -Force) "a record of the store itself is refused, -Force or not"
Check (Test-Refused $h (New-File (Join-Path $h "top.md")) $inHome) "and a file directly in the home"
Check (Test-Shared $h (New-File ($h + "-beside\notes.md"))) "CONTROL: a file in a folder whose name only BEGINS with the home's is shared"
Check (Test-Shared $h (New-File (Join-Path (Split-Path -Parent $h) "beside-the-home.md"))) "CONTROL: and so is a file beside the home"
$inSecretsFile = New-File (Join-Path $profileDir ".horde-secrets\client.json") '{"dummy":1}'
Check (Test-Refused $h $inSecretsFile $inSecrets) "a file under .horde-secrets in the profile is refused as that"
Check (Test-Refused $h $inSecretsFile $never -Force) "and -Force does not change that"
$elsewhere = New-File (Join-Path $script:real "a-copy\.Horde-Secrets\deep\client.md")
Check (Test-Refused $h $elsewhere "is under a folder named '.Horde-Secrets': a folder named .horde, or one whose name begins with .horde-, is Horde's own" -Force) "a folder named .horde-secrets anywhere on the way to the file, in any case of its letters, is refused, -Force or not: it is one of Horde's own folders by its name"
Check (Test-Refused $h (New-File (Join-Path $script:real "a-copy\plain-folder\.horde-secrets")) "is not one that is shared" -NotLike "is under a folder named" -Force) "a FILE named .horde-secrets in an ordinary folder is not a folder on the way: it is refused for its type, not as that folder"
Check (Test-Refused $h (New-File (Join-Path $script:real "a-copy\.horde-secrets-old\client.md")) "is under a folder named '.horde-secrets-old'" -Force) "and so is a folder whose name only BEGINS like it (.horde-secrets-old): every folder whose name begins with .horde- is Horde's own"
Check (Test-Shared $h (New-File (Join-Path $script:real "a-copy\.horde-secrets.md")) -Force) "CONTROL: and a FILE whose name begins so is a file, not a folder on the way: -Force, which never lifts the folder, shares it"
$inSshFile = New-File (Join-Path $profileDir ".ssh\notes.txt")
Check (Test-Refused $h $inSshFile $inSsh) "a file under .ssh in the profile is refused as that"
Check (Test-Refused $h $inSshFile $never -NotLike "share it again") "and the reason says -Force does not change that"
Check (Test-Refused $h $inSshFile $inSsh -Force) "with -Force it is refused all the same: .ssh is the third place -Force never lifts"
Check (Test-Refused $h (New-File (Join-Path $profileDir ".ssh\deep\er\notes.md")) $inSsh) "and so is a file deeper under it"
Check (Test-Shared $h (New-File (Join-Path $profileDir ".ssh2\notes.txt"))) "CONTROL: a folder whose name only begins with .ssh is shared from"
Check (Test-Shared $h (New-File (Join-Path $profileDir "notes-beside-ssh.txt"))) "CONTROL: and a file beside it, in the profile, is shared"
Check (Test-Shared $h (New-File (Join-Path $script:real "not-the-profile\.ssh\notes.txt"))) "CONTROL: a folder named .ssh that is not the profile's is shared from: that place is the user's own, not a name"
foreach ($agentFolder in @((Join-Path $profileDir ".harness-x"), (Join-Path $profileDir ".harness-y"), $env:HORDE_TEST_HARNESS_X_HOME)) {
    $inAgentFile = New-File (Join-Path $agentFolder "projects\notes.md")
    Check (Test-Refused $h $inAgentFile $inAgent) ("a file under a harness's own folder (" + (Split-Path -Leaf $agentFolder) + ") is refused as that")
    Check (Test-Refused $h $inAgentFile ("('" + $agentFolder + "')")) "and the reason names the folder, which is the harness's own data"
    Check (Test-Refused $h $inAgentFile $insist -NotLike "does not change") "and says that -Force shares it"
    Check (Test-Shared $h $inAgentFile -Force) "with -Force it is shared: the place is lifted"
    # INSIDE A HARNESS'S FOLDER -Force LIFTS THE PLACE AND NEVER THE NAME, and the reason says which.
    foreach ($signInName in @("auth.json", ".credentials.json", "api-key.txt")) {
        $text = "dummy words, and no secret"; if ($signInName -like "*.json") { $text = '{"dummy":1}' }
        $inAgentNamed = New-File (Join-Path $agentFolder $signInName) $text
        $word = Get-HordeFilesDenyWord -Name $signInName
        Check (Test-Refused $h $inAgentNamed $inAgent -NotLike "holds '") ($signInName + " in that folder, with no -Force, is refused for the PLACE")
        Check (Test-Refused $h $inAgentNamed ("its name, '" + $signInName + "', holds '" + $word + "', as a file of secrets is named, and it is under a folder an agent harness keeps its own files in") -Force) "with -Force it is refused for its NAME, in that place"
        Check (Test-Refused $h $inAgentNamed ("('" + $agentFolder + "'). -Force shares other files from such a folder, and never one that is named so") -NotLike "share it again" -Force) "and the reason says -Force shares other files from there and never this one"
    }
}
Check (Test-Shared $h (New-File (Join-Path $docs "elsewhere\auth.json") '{"dummy":1}') -Force) "CONTROL: outside every harness's folder, -Force shares a file of the same name"
Check (Test-Shared $h (New-File (Join-Path $profileDir ".harness-xy\notes.md"))) "CONTROL: a folder whose name only begins with a harness's is shared from"
# A HARNESS'S OWN FILE BESIDE ITS FOLDER, in the profile itself: a root its stores.json declares. IT
# IS NEVER SHARED, -Force or not (the review's second round, 2026-10-13: until then it was a place
# like the folder, and -Force shared it). And neither is a file beside it whose name BEGINS with
# its name: a copy another tool left there, whatever suffix it was given. In the variable's profile
# and in the system's.
$ownFileSaid = "is an agent harness's own file, the one it keeps beside its folder with its account and its settings in it"
$ownCopySaid = "and its name begins with that file's name, as a copy or a backup of it does"
$ownNever = "A harness's own file is never shared, and -Force does not change that"
foreach ($besideIn in @($profileDir, $script:osProfile)) {
    $beside = New-File (Join-Path $besideIn ".harness-x.json") '{"dummy":1}'
    Check (Test-Refused $h $beside ($ownFileSaid + " ('" + $beside + "'). " + $ownNever) -NotLike "share it again") ("a harness's own file beside its folder (" + (Split-Path -Leaf $besideIn) + "\.harness-x.json) is refused as a harness's own file, the reason names it and says -Force does not change that")
    Check (Test-Refused $h $beside ($ownFileSaid + " ('" + $beside + "'). " + $ownNever) -NotLike "share it again" -Force) "with -Force it is refused all the same, in the same words: -Force lifts a harness's FOLDER and never its file"
    foreach ($copyName in @(".harness-x.json.some-tool-backup", ".harness-x.json.bak.json", ".harness-x.json2.md", ".Harness-X.JSON.old.txt")) {
        $copy = New-File (Join-Path $besideIn $copyName) '{"dummy":1}'
        Check (Test-Refused $h $copy ("is beside an agent harness's own file ('" + $beside + "') " + $ownCopySaid + ". " + $ownNever) -NotLike "share it again") ("a file beside it whose name begins with its name (" + $copyName + ") is refused as a copy of it")
        Check (Test-Refused $h $copy ($ownCopySaid + ". " + $ownNever) -Force) "and with -Force all the same"
    }
}
# WHAT THAT RULE DOES NOT REFUSE, each shared with no -Force.
Check (Test-Shared $h (New-File (Join-Path $profileDir "my.harness-x.json") '{"dummy":1}')) "CONTROL: a name that only HOLDS the declared name further on (my.harness-x.json) is an ordinary file"
Check (Test-Shared $h (New-File (Join-Path $profileDir ".harness-x.jso.md"))) "CONTROL: so is a name that is only the beginning of the declared name"
Check (Test-Shared $h (New-File (Join-Path $profileDir ".harness-x-notes.md"))) "CONTROL: and a name that begins with the harness's FOLDER's name: a root that is a folder is a place, and gives no name to begin with"
Check (Test-Shared $h (New-File (Join-Path $profileDir ".harness-y.json") '{"dummy":1}')) "CONTROL: and a file of that shape beside a harness that declares no file of its own"
Check (Test-Shared $h (New-File (Join-Path $docs ".harness-x.json") '{"dummy":1}')) "CONTROL: THE SAME NAME IN AN ORDINARY FOLDER, which is not where the adapter says the file is, is an ordinary file"
Check (Test-Shared $h (New-File (Join-Path $docs ".harness-x.json.bak.json") '{"dummy":1}')) "CONTROL: and so is the same beginning there"
Check (Test-Shared $h (New-File (Join-Path $profileDir "a-folder\.harness-x.json.bak.json") '{"dummy":1}')) "CONTROL: and in a folder under the profile: the same folder as the declared file, not one below it"
# BY THE HANDLE'S OWN PATH, as every rule: a link with an innocent name, elsewhere, to that file.
$ownLink = Join-Path $docs "an-innocent-name.json"
Check (New-FileLink $ownLink (Join-Path $profileDir ".harness-x.json")) "CONTROL: a symbolic link with an innocent name was made, in an ordinary folder, to the harness's own file"
Check (Test-Refused $h $ownLink $ownFileSaid -NotLike "is a link" -Force) "named through that link, the file is refused as the harness's own file, -Force or not"
if (Test-Link $ownLink) { [System.IO.File]::Delete($ownLink) }
Check (-not (Test-Path -LiteralPath $ownLink) -and [System.IO.File]::Exists((Join-Path $profileDir ".harness-x.json"))) "that link is gone again, and the file it led to is still there"
# ANY ROOT OF ANY ADAPTER THAT IS A FILE, a root its variable names too: the disk is asked, not the name.
$fileRoot = New-File (Join-Path $script:real "a-store-that-is-a-file\y-store.json") '{"dummy":1}'
$fileRootCopy = New-File (Join-Path $script:real "a-store-that-is-a-file\y-store.json.bak.md")
$fileRootOther = New-File (Join-Path $script:real "a-store-that-is-a-file\notes.md")
$env:HORDE_TEST_HARNESS_Y_HOME = $fileRoot
$viaVariable = ((Test-Refused $h $fileRoot ($ownFileSaid + " ('" + $fileRoot + "'). " + $ownNever)) -and (Test-Refused $h $fileRoot $ownNever -Force))
$viaVariableCopy = Test-Refused $h $fileRootCopy $ownCopySaid -Force
$viaVariableOther = Test-Shared $h $fileRootOther
$env:HORDE_TEST_HARNESS_Y_HOME = ""
Check $viaVariable "a root a harness's VARIABLE names that is a file is that harness's own file too: refused, -Force or not"
Check $viaVariableCopy "and so is a copy beside it"
Check $viaVariableOther "CONTROL: another file in that folder is shared: a root that is a file is no folder, and nothing is under it"
Check (Test-Shared $h $fileRoot) "CONTROL: once the variable is put back, the same file is an ordinary file"
# KNOWN LIMIT, pinned so that closing it is seen: whether a root is a file is asked of the disk, so
# when the declared file is not there, a copy left beside where it was is an ordinary file.
$repoW = Join-Path $script:real "repo-with-a-file-root"
New-Item -ItemType Directory -Path (Join-Path $repoW "agents\harness-w") | Out-Null
[System.IO.File]::WriteAllText((Join-Path $repoW "agents\harness-w\stores.json"), '{ "schemaVersion": 1, "roots": [ { "profile": ".harness-w.json" } ] }')
$leftCopy = New-File (Join-Path $profileDir ".harness-w.json.bak.md")
Check (Test-Shared $h $leftCopy -Repo $repoW) "KNOWN LIMIT: when the declared file is not on the disk, a copy left beside where it was is shared: nothing says the root is a file"
$null = New-File (Join-Path $profileDir ".harness-w.json") '{"dummy":1}'
Check (Test-Refused $h $leftCopy $ownCopySaid -Force -Repo $repoW) "and once the declared file is there, that same copy is refused, -Force or not"
$shippedFileRoots = @(Get-ChildItem -LiteralPath (Join-Path $root "agents") -Directory | ForEach-Object { Join-Path $_.FullName "stores.json" } | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object { @(([System.IO.File]::ReadAllText($_) | ConvertFrom-Json).roots) } | Where-Object { $null -ne $_.PSObject.Properties["profile"] -and ("" + $_.profile) -like "*.json" })
Check ($shippedFileRoots.Count -ge 1 -and @($shippedFileRoots | Where-Object { @($realRepo.places | ForEach-Object { $_.path }) -cnotcontains (Join-Path $script:osProfile ("" + $_.profile)) }).Count -eq 0) ("the shipped adapters declare " + $shippedFileRoots.Count + " such file, and it is a place under the system's profile")
# WHAT -Force NEVER LIFTS IS JUDGED FIRST: a file in the home whose name holds a word is refused as the home.
Check (Test-Refused $h (New-File (Join-Path $h "settings\api-key.txt")) $inHome -NotLike "holds 'key'") "a file in the home with a word in its name is refused for the home, not for the name"
Check (Test-Refused $h (New-File (Join-Path $profileDir ".ssh\api-key.txt")) $inSsh -NotLike "holds 'key'") "and one in .ssh for .ssh"

Write-Host ""
Write-Host "--- a variable the caller sets moves no place away: the review's sequences ---" -ForegroundColor Cyan
# THE REVIEW OF THIS LIST (2026-10-13) moved a variable and shared, with no -Force, what was in the
# real place. Each sequence is run here as it was run there: the variable is moved, and the file in
# the place the SYSTEM names must still be refused, as that place. "The real profile" below is the
# folder this suite's stand-in for the system's question names; the machine's own is never looked at.
$osSsh = New-File (Join-Path $script:osProfile ".ssh\notes.txt")
$osAgentX = New-File (Join-Path $script:osProfile ".harness-x\sign-in\notes.json") '{"dummy":1}'
$osAgentY = New-File (Join-Path $script:osProfile ".harness-y\notes.md")
$osHome = New-File (Join-Path $script:osProfile ".horde\settings\notes.json") '{"dummy":1}'
$osSecrets = New-File (Join-Path $script:osProfile ".horde-secrets\client.json") '{"dummy":1}'
$varHome = New-File (Join-Path $profileDir ".horde\settings\notes.json") '{"dummy":1}'
$emptyProfile = Join-Path $script:real "an-empty-profile"
New-Item -ItemType Directory -Path $emptyProfile | Out-Null
$inRealPlace = "('" + $script:osProfile + "\"
function Test-RealPlaces {
    # Is every file in a place of the system's profile refused, as that place and by its own path?
    # The answers as one text, "ssh agent-x agent-y home home-forced secrets" when all six are.
    $said = New-Object System.Collections.ArrayList
    if ((Test-Refused $h $osSsh $inSsh) -and (Test-Refused $h $osSsh ($inRealPlace + ".ssh')"))) { [void]$said.Add("ssh") }
    if ((Test-Refused $h $osAgentX $inAgent) -and (Test-Refused $h $osAgentX ($inRealPlace + ".harness-x')"))) { [void]$said.Add("agent-x") }
    if ((Test-Refused $h $osAgentY $inAgent) -and (Test-Refused $h $osAgentY ($inRealPlace + ".harness-y')"))) { [void]$said.Add("agent-y") }
    if ((Test-Refused $h $osHome $inHome) -and (Test-Refused $h $osHome ($inRealPlace + ".horde')"))) { [void]$said.Add("home") }
    if (Test-Refused $h $osHome $inHome -Force) { [void]$said.Add("home-forced") }
    if (Test-Refused $h $osSecrets ($inRealPlace + ".horde-secrets')") -Force) { [void]$said.Add("secrets") }
    return ($said -join " ")
}
$allSix = "ssh agent-x agent-y home home-forced secrets"
Check ((Test-RealPlaces) -ceq $allSix) "CONTROL: with no variable moved, a file in each place of the real profile is refused as that place: its .ssh, each harness's folder, its .horde and its .horde-secrets"
# ONE: USERPROFILE moved to an empty folder.
$env:USERPROFILE = $emptyProfile
$seq1 = Test-RealPlaces
$seq1Beside = Test-Shared $h (New-File (Join-Path $emptyProfile "notes.md"))
$seq1Outside = Test-Shared $h (New-File (Join-Path $script:osProfile "documents\notes.md"))
$env:USERPROFILE = $profileDir
Check ($seq1 -ceq $allSix) ("USERPROFILE MOVED to an empty folder: a file in the real .ssh, in each harness's real folder, in the real .horde and the real .horde-secrets is still refused, each as its place (" + $seq1 + ")")
Check ($seq1Beside -and $seq1Outside) "CONTROL: a file in the empty folder it was moved to, and one in the real profile outside those folders, are shared: it is the places that are refused, not the profile"
# TWO: the home moved (the review set HORDE_HOME; here both the variable and what the caller hands in).
$wasHome = $env:HORDE_HOME
$env:HORDE_HOME = Join-Path $script:real "a-moved-home"
$seq2 = Test-RealPlaces
$seq2Var = Test-Refused $h $varHome ("is under the Horde home, where Horde keeps its own records, keys and settings ('" + $profileDir + "\.horde')") -Force
$ambient = [pscustomobject]@{ outcome = "threw"; reason = "" }
try { $ambient = Add-HordeFilesShare -Path $osHome -Title "A title" -Asking $sess -RepoRoot $repo -Force } catch { $ambient.reason = "$($_.Exception.Message)" }
$seq2Moved = Test-Refused $env:HORDE_HOME (New-File (Join-Path $env:HORDE_HOME "settings\notes.json") '{"dummy":1}') ("('" + $env:HORDE_HOME + "')") -Force
$seq2Control = Test-Shared $h (New-File (Join-Path $docs "home-moved-control.md"))
$env:HORDE_HOME = $wasHome
Check ($seq2 -ceq $allSix) ("HORDE_HOME MOVED: the real profile's .horde is still refused, -Force or not, and so is every other place (" + $seq2 + ")")
Check $seq2Var "and so is .horde in the profile the variable names, which is where the home would be had it not been moved"
Check ($ambient.outcome -ceq "refused" -and $ambient.reason -like ("*" + $inHome + "*")) "and with no home handed in at all, only the variable, the real .horde is refused the same"
Check $seq2Moved "the home it was moved to is refused too: a home that really was moved is where the variable says"
Check $seq2Control "CONTROL: an ordinary file is shared with the home moved"
# THREE and FOUR: a harness's own variable moves its store (each of the two harnesses has one).
foreach ($moved in @("HORDE_TEST_HARNESS_X_HOME", "HORDE_TEST_HARNESS_Y_HOME")) {
    $wasMovedTo = [Environment]::GetEnvironmentVariable($moved)
    $movedTo = Join-Path $script:real ("moved-store-" + $moved.Substring(19, 1))
    [Environment]::SetEnvironmentVariable($moved, $movedTo)
    $seq = Test-RealPlaces
    $atMoved = New-File (Join-Path $movedTo "notes.md")
    $seqMoved = ((Test-Refused $h $atMoved $inAgent) -and (Test-Refused $h $atMoved ("('" + $movedTo + "')")))
    $seqMovedForce = Test-Shared $h $atMoved -Force
    $leaf = ".harness-" + $moved.Substring(19, 1).ToLowerInvariant()
    $seqDefault = Test-Refused $h (New-File (Join-Path $profileDir ($leaf + "\notes.md"))) ("('" + $profileDir + "\" + $leaf + "')")
    [Environment]::SetEnvironmentVariable($moved, $wasMovedTo)
    $seqAfter = Test-Shared $h $atMoved
    Check ($seq -ceq $allSix) ("A HARNESS'S OWN VARIABLE MOVED (" + $moved + "): its folder in the real profile is still refused, and so is every other place (" + $seq + ")")
    Check ($seqMoved -and $seqMovedForce) "the folder its variable moved the store to is refused as that harness's, and -Force shares from it"
    Check $seqDefault "and its folder in the profile the variable names is still refused"
    Check $seqAfter "CONTROL: once the variable is put back, the folder it named is an ordinary folder, and the same file is shared"
}
# FIVE: two of them moved together, and then all of them.
$env:USERPROFILE = $emptyProfile; $env:HORDE_HOME = Join-Path $script:real "a-moved-home"
$seq5 = Test-RealPlaces
$env:HORDE_TEST_HARNESS_X_HOME = Join-Path $script:real "moved-store-X"; $env:HORDE_TEST_HARNESS_Y_HOME = Join-Path $script:real "moved-store-Y"
$seq6 = Test-RealPlaces
$seq6Control = Test-Shared $h (New-File (Join-Path $docs "all-moved-control.md"))
$env:USERPROFILE = $profileDir; $env:HORDE_HOME = $wasHome; $env:HORDE_TEST_HARNESS_X_HOME = Join-Path $script:real "harness-x-moved"; $env:HORDE_TEST_HARNESS_Y_HOME = ""
Check ($seq5 -ceq $allSix) ("USERPROFILE AND HORDE_HOME MOVED TOGETHER: every real place is still refused (" + $seq5 + ")")
Check ($seq6 -ceq $allSix) ("ALL FOUR VARIABLES MOVED TOGETHER: every real place is still refused (" + $seq6 + ")")
Check $seq6Control "CONTROL: an ordinary file is shared with all four moved"
# THE OTHER HALF OF THE UNION: what the variable names is still refused when the system names another.
Check (Test-Refused $h (Join-Path $profileDir ".ssh\notes.txt") ("('" + $profileDir + "\.ssh')")) "the profile the variable names keeps its places: its .ssh is refused as before"
Check (Test-Refused $h $inSecretsFile ("('" + $profileDir + "\.horde-secrets')") -Force) "and its .horde-secrets, -Force or not"
# WHEN THE SYSTEM WILL NOT SAY where the profile is, nothing can be told to be outside the real places.
$plainDocEarly = New-File (Join-Path $docs "plain-early.md")
$script:keptOsProfile = $script:osProfile
$script:osProfile = ""
$silent = Test-Refused $h $plainDocEarly "the operating system would not say where the user's profile is"
$silentForce = Test-Refused $h $plainDocEarly $never -Force
$script:osProfile = $script:keptOsProfile
Check $silent "when the operating system will not say where the profile is, an ordinary file is refused, and the reason says that"
Check $silentForce "and -Force does not change it: where the home and the user's keys are is not known"
Check (Test-Shared $h $plainDocEarly) "CONTROL: asked again with the system answering, the same file is shared"
# HORDE'S OWN FOLDERS, BY ONE RULE AND NO LIST: a folder named exactly .horde, or whose name begins
# with .horde-, anywhere on the way to the file, in any case of A to Z, is never shared from.
# ".horde-anything" is a name nobody has made: the rule covers the folder that comes next.
$inHordes = "is Horde's own, where it keeps its records, keys and credentials"
function Get-HordesSaid { param([string]$Folder) return ("is under a folder named '" + $Folder + "': a folder named .horde, or one whose name begins with .horde-, " + $inHordes) }
Check (Test-Refused $h (New-File (Join-Path $script:real "a-copy\.Horde\deep\notes.md")) (Get-HordesSaid ".Horde") -Force) "a folder named .horde anywhere on the way to the file, in any case of its letters, is refused, -Force or not, and the reason names it as it is written"
Check (Test-Refused $h (New-File (Join-Path $script:real "a-copy\.horde\notes.md")) $never -NotLike "share it again" -Force) "and the reason says -Force does not change that"
foreach ($placed in @(@("as the folder the file is in", "family\plain\.horde-anything\notes.md"), @("in the middle of the path", "family\.horde-anything\plain\deeper\notes.md"), @("with capitals", "family\caps\.HORDE-Anything\notes.md"), @("named for something that is real elsewhere", "family\.horde-mesh\notes.md"), @("with nothing after the dash", "family\.horde-\notes.md"))) {
    $inFamily = New-File (Join-Path $script:real $placed[1])
    $folderWritten = @($placed[1] -split '\\' | Where-Object { $_ -like ".horde*" })[0]
    Check (Test-Refused $h $inFamily (Get-HordesSaid $folderWritten)) ("a folder whose name begins with .horde- is refused, " + $placed[0] + " (" + $folderWritten + ")")
    Check (Test-Refused $h $inFamily $never -NotLike "share it again" -Force) "and -Force does not change that"
}
# AT THE TOP OF A PATH, which no test may make on a real drive: the question is asked of the path.
$topSaid = Get-HordeFilesDenyRefusal -FinalPath "C:\.horde-anything\notes.md" -HordeHome $h -RepoRoot $repo -Force
Check ($topSaid -like ("*" + (Get-HordesSaid ".horde-anything") + "*") -and $topSaid -like ("*" + $never)) "and as the first folder of a path, straight under the drive"
Check ((Get-HordeFilesDenyRefusal -FinalPath "C:\.horde\notes.md" -HordeHome $h -RepoRoot $repo -Force) -like ("*" + (Get-HordesSaid ".horde") + "*")) "as is a folder named .horde there"
# THROUGH A JUNCTION: the junction has an innocent name, and the folder it leads to does not.
$familyTarget = Join-Path $script:real "family\plain\.horde-anything"
$familyJunction = Join-Path $script:real "family\an-innocent-junction"
Check (New-Junction $familyJunction $familyTarget) "CONTROL: a junction with an innocent name was made to a folder whose name begins with .horde-"
Check (Test-Refused $h (Join-Path $familyJunction "notes.md") (Get-HordesSaid ".horde-anything") -NotLike "is a link" -Force) "a file named through that junction is refused for the folder it is really in, -Force or not: the open handle's own path is judged"
$innocentTarget = Join-Path $script:real "family\an-ordinary-folder"
$null = New-File (Join-Path $innocentTarget "notes.md")
$namedJunction = Join-Path $script:real "family\.horde-by-name-only"
Check (New-Junction $namedJunction $innocentTarget) "CONTROL: and a junction NAMED so was made to an ordinary folder"
Check (Test-Refused $h (Join-Path $namedJunction "notes.md") "is a link" -NotLike $inHordes) "a file named through THAT junction is not in such a folder - its own path has no such name - and is refused only as a link is"
# WHAT IS NOT OF THAT FAMILY.
Check (Test-Shared $h (New-File (Join-Path $script:real "family\.hordes\notes.md"))) "CONTROL: a folder named .hordes is not: the name is .horde, or .horde and a dash"
Check (Test-Shared $h (New-File (Join-Path $script:real "family\my.horde-notes\notes.md"))) "CONTROL: nor a folder named my.horde-notes: the name must BEGIN so"
Check (Test-Shared $h (New-File (Join-Path $script:real "family\.horde_notes\notes.md"))) "CONTROL: nor one named .horde_notes: an underscore is not the dash"
Check (Test-Shared $h (New-File (Join-Path $script:real "a-copy\horde\notes.md"))) "CONTROL: nor a folder named horde, with no dot"
Check (Test-Shared $h (New-File (Join-Path $script:real "family\plain2\.horde-notes.md"))) "CONTROL: and a FILE named .horde-notes.md in an ordinary folder is shared: the rule is about folders"
Check (Test-Shared $h (New-File (Join-Path $script:real "a-copy\plain\.horde.md"))) "CONTROL: as is a FILE named .horde.md"
# The two junctions by their own entries, so that nothing later follows one.
foreach ($madeJunction in @($familyJunction, $namedJunction)) { if (Test-Link $madeJunction) { [System.IO.Directory]::Delete($madeJunction) } }
Check (-not (Test-Path -LiteralPath $familyJunction) -and -not (Test-Path -LiteralPath $namedJunction) -and [System.IO.File]::Exists((Join-Path $familyTarget "notes.md"))) "the two junctions are gone again, and what they led to is still there"

Write-Host ""
Write-Host "--- a harness nobody described is not left open ---" -ForegroundColor Cyan
$repoGap = Join-Path $script:real "repo-with-a-gap"
New-Item -ItemType Directory -Path (Join-Path $repoGap "agents\harness-z") | Out-Null
$plainDoc = New-File (Join-Path $docs "plain.md")
Check (Test-Refused $h $plainDoc "which folders the agent harnesses keep their own files in is not known" -Repo $repoGap) "with a harness folder that declares no stores, an ordinary file is refused: where that harness keeps its files is not known"
Check (Test-Refused $h $plainDoc $insist -Repo $repoGap) "the reason says -Force shares it"
Check (Test-Shared $h $plainDoc -Force -Repo $repoGap) "and with -Force it is: the harness folders are what -Force lifts"
Check (Test-Refused $h $inSettings $inHome -Force -Repo $repoGap) "the home is still refused then, -Force or not"
$namedDoc = New-File (Join-Path $docs "gap\auth.json") '{"dummy":1}'
Check (Test-Refused $h $namedDoc "is not known" -Force -Repo $repoGap) "but a file NAMED as a secret is not shared then, even with -Force: it cannot be told that it is not in a harness's folder, where such a name is never lifted"
Check (Test-Refused $h $namedDoc "-Force never shares a file that is named so from a harness's folder" -NotLike "share it again" -Force -Repo $repoGap) "and the reason says so"
Check (Test-Shared $h $namedDoc -Force) "CONTROL: with every harness described, -Force shares that file"
Check (Test-Shared $h $plainDoc) "CONTROL: with every harness described, the same file is shared with no -Force"
# NO agents FOLDER AT ALL is not "no harnesses": core answers it with an empty list.
$repoBare = Join-Path $script:real "repo-with-no-agents"
New-Item -ItemType Directory -Path $repoBare | Out-Null
Check ((Get-HordeAgentStoreRoots -Root $repoBare).state -ceq "known" -and @((Get-HordeAgentStoreRoots -Root $repoBare).value).Count -eq 0) "CONTROL: asked of a folder with no agents folder in it, core answers a known list that is empty"
Check (Test-Refused $h $plainDoc ("there is no folder '" + (Join-Path $repoBare "agents") + "'") -Repo $repoBare) "with no agents folder, an ordinary file is refused: which folders are a harness's is not known"
Check (Test-Refused $h $plainDoc $insist -Repo $repoBare) "the reason says -Force shares it"
Check (Test-Shared $h $plainDoc -Force -Repo $repoBare) "and with -Force it is"
Check (Test-Refused $h $namedDoc "is not known" -Force -Repo $repoBare) "and a file named as a secret is not, -Force or not"
Check ((Get-HordeFilesDenyPlaces -HordeHome $h -RepoRoot $repoBare).unknown -like "there is no folder*" -and @((Get-HordeFilesDenyPlaces -HordeHome $h -RepoRoot $repoBare).places | Where-Object { $_.kind -ceq "agent" }).Count -eq 0) "the places then hold no harness folder, and say why"

Write-Host ""
Write-Host "--- every rule judges the open handle's own path: a place reached another way is still the place ---" -ForegroundColor Cyan
$h = New-TestHome
$null = Invoke-Share -TestHome $h -Path (New-File (Join-Path $docs "second.md"))
$sshFolder = Join-Path $profileDir ".ssh"
$sshFile = Join-Path $sshFolder "notes.txt"
$homeFile = New-File (Join-Path $h "settings\notes.json") '{"dummy":1}'
$links = Join-Path $script:real "links"
New-Item -ItemType Directory -Path $links | Out-Null
# A LINK OUTSIDE THE DENIED FOLDERS POINTING INTO ONE. The link test would refuse it too, as a link;
# refused AS THE PLACE shows the list read where the handle really is, not what was written.
Check (New-FileLink (Join-Path $links "innocent.txt") $sshFile) "CONTROL: a symbolic link outside .ssh was made to the file inside it"
Check (Test-Refused $h (Join-Path $links "innocent.txt") $inSsh -NotLike "is a link") "a link outside .ssh to a file inside it is refused as .ssh"
Check (Test-Refused $h (Join-Path $links "innocent.txt") $inSsh -NotLike "is a link" -Force) "and with -Force it is refused as .ssh all the same"
$agentTarget = New-File (Join-Path $profileDir ".harness-x\projects\linked-notes.md")
Check (New-FileLink (Join-Path $links "innocent.md") $agentTarget) "CONTROL: a symbolic link outside a harness's folder was made to a file inside it"
Check (Test-Refused $h (Join-Path $links "innocent.md") $inAgent -NotLike "is a link") "a link outside a harness's folder to a file inside it is refused as that folder"
Check (Test-Refused $h (Join-Path $links "innocent.md") "is a link" -Force) "and with -Force it is still not shared: the place is lifted, and a link is never followed"
Check (New-FileLink (Join-Path $links "innocent.json") $homeFile) "CONTROL: a symbolic link outside the home was made to a file inside it"
Check (Test-Refused $h (Join-Path $links "innocent.json") $inHome -Force) "a link outside the home to a file inside it is refused as the home, -Force or not"
Check (New-FolderLink (Join-Path $links "folder-link") $sshFolder) "CONTROL: a symbolic link to the .ssh folder was made"
Check (Test-Refused $h (Join-Path $links "folder-link\notes.txt") $inSsh -NotLike "is a link") "through a symbolic link to the folder"
Check (New-Junction (Join-Path $links "junction") $sshFolder) "CONTROL: a junction to the .ssh folder was made"
Check (Test-Refused $h (Join-Path $links "junction\notes.txt") $inSsh -NotLike "is a link") "through a junction to the folder"
Check (New-Junction (Join-Path $links "home-junction") $h) "CONTROL: a junction to the home was made"
Check (Test-Refused $h (Join-Path $links "home-junction\settings\notes.json") $inHome -Force) "through a junction to the home, -Force or not"
Check (Test-Refused $h ("\\?\" + $sshFile) $inSsh) "behind the long-path prefix"
Check (Test-Refused $h ("\\?\" + $homeFile) $inHome -Force) "and the home behind it, -Force or not"
Check (Test-Refused $h $sshFile.ToUpperInvariant() $inSsh) "written in capitals"
Check (Test-Refused $h $homeFile.ToUpperInvariant() $inHome -Force) "and the home in capitals, -Force or not"
Check (Test-Refused $h (Join-Path ($sshFolder + ".") "notes.txt") $inSsh) "with a dot after the folder's name, which Windows drops"
# A blank after a FOLDER's name is not dropped (measured 2026-10-13): that path names no file, so it is no way in.
Check (Test-Refused $h (Join-Path ($sshFolder + " ") "notes.txt") "there is no file") "with a blank after the folder's name the path names no file at all"
Check (Test-Refused $h (Join-Path $docs "..\profile\.ssh\notes.txt") $inSsh) "by a path that climbs out of another folder with dot-dot"
Push-Location -LiteralPath $docs
try { $relative = Test-Refused $h "..\profile\.ssh\notes.txt" $inSsh; $relativeHome = Test-Refused $h ("..\" + (Split-Path -Leaf $h) + "\settings\notes.json") $inHome -Force } finally { Pop-Location }
Check $relative "by a relative path with dot-dot, from where the caller stands"
Check $relativeHome "and the home by a relative path, -Force or not"
# An 8.3 short name, where this volume makes them. Behind the long-path prefix .NET changes nothing,
# so the handle really is opened by the short name (test/test-files-store.ps1 has the measurement).
$shortSsh = Get-ShortPath -Path $sshFolder -Folder
$homeLong = New-File (Join-Path $h "a long folder name of the home\notes.md")
$shortHomeDir = Get-ShortPath -Path (Split-Path -Parent $homeLong) -Folder
if ($shortHomeDir -ne "" -and (Split-Path -Leaf $shortHomeDir) -like "*~*") {
    Check (Test-Refused $h (Join-Path $shortHomeDir "notes.md") $inHome -Force) ("by the 8.3 short name of a folder of the home (" + (Split-Path -Leaf $shortHomeDir) + ")")
    Check (Test-Refused $h ("\\?\" + (Join-Path $shortHomeDir "notes.md")) $inHome -Force) "and by that short name behind the long-path prefix, where the handle is opened by the short name itself"
} else { Write-Skip "AN 8.3 SHORT NAME INTO THE HOME COULD NOT BE TESTED: this volume gave the folder no short name." }
$keyLong = New-File (Join-Path $docs "a long name holding a secret word.md")
$shortKey = Get-ShortPath -Path $keyLong
if ($shortKey -ne "" -and (Split-Path -Leaf $shortKey) -like "*~*" -and (Get-HordeFilesDenyWord -Name (Split-Path -Leaf $shortKey)) -ceq "") {
    Check (Test-Refused $h ("\\?\" + $shortKey) "holds 'secret'") ("a name is judged as the disk holds it: opened by a short name with no word in it (" + (Split-Path -Leaf $shortKey) + "), the file is refused for its real name")
} else { Write-Skip "A NAME OPENED BY ITS 8.3 SHORT NAME COULD NOT BE TESTED: this volume gave the file no short name without the word in it." }
if ($shortSsh -ne "" -and (Split-Path -Leaf $shortSsh) -cne ".ssh") { Check (Test-Refused $h ("\\?\" + (Join-Path $shortSsh "notes.txt")) $inSsh) "and .ssh by its own short name" }
# A PATH THAT NAMES NO DENIED FOLDER AT ALL: a drive over the denied folder. Until 2026-10-13 this was
# a subst drive, a real drive letter, which every other process of the user sees; no suite makes one
# any more (test/lib/SuiteFiles.ps1, Get-HordeDriveLetterMakers). A POWERSHELL DRIVE is this
# process's own, and names the same thing: on it the written path is a letter and a file name, and
# nothing in it says .ssh or the home.
# WHAT THIS DOES NOT SHOW, and the subst drive did: that the OPEN HANDLE of a file reached through a
# real drive letter has the folder's own path. A PowerShell drive is resolved to that path before the
# open. That fact of Windows' is asked once, of a real letter, in test/test-path-text.ps1; and that
# the handle's path is what is judged is what the links, the junctions and the short names above show.
$driveLetter = @(Get-FreeLetters)[0]
$byDrive = $false; $byDriveHome = $false; $driveMade = $false
$null = New-PSDrive -Name $driveLetter -PSProvider FileSystem -Root $sshFolder -Scope Script
try {
    $driveMade = ($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($driveLetter + ":\notes.txt") -ceq $sshFile)
    $byDrive = Test-Refused $h ($driveLetter + ":\notes.txt") $inSsh
} finally { Remove-PSDrive -Name $driveLetter -Scope Script }
$null = New-PSDrive -Name $driveLetter -PSProvider FileSystem -Root (Join-Path $h "settings") -Scope Script
try { $byDriveHome = Test-Refused $h ($driveLetter + ":\notes.json") $inHome -Force } finally { Remove-PSDrive -Name $driveLetter -Scope Script }
Check $driveMade ("CONTROL: a PowerShell drive " + $driveLetter + ": of this process's own was made over .ssh (if this fails, the form was NOT tested)")
Check $byDrive "by a drive over .ssh, where the written path names no folder, the file is refused as .ssh"
Check $byDriveHome "and by a drive over a folder of the home, as the home, -Force or not"
Check ($null -eq (Get-PSDrive -Name $driveLetter -ErrorAction SilentlyContinue)) "that drive is gone again"
$sshCopy = Join-Path $docs "a-copy-of-those-notes.txt"
[System.IO.File]::Copy($sshFile, $sshCopy)
Check (Test-Shared $h $sshCopy) "CONTROL: after all those refusals the .ssh file can still be read, and a copy of it outside .ssh is shared: they were the list's refusals and not a broken file"
# WHAT THE HANDLE DOES NOT SAY, pinned so that it is known: a second name (a hard link) outside .ssh
# for a file inside it. The handle's path is the name that was opened, and nothing marks the file.
$hardLink = Join-Path $links "second-name.txt"
$null = & cmd.exe /c ("mklink /H `"" + $hardLink + "`" `"" + $sshFile + "`" >nul 2>nul")
if ([System.IO.File]::Exists($hardLink)) { Check (Test-Shared $h $hardLink) "KNOWN LIMIT: a hard link outside .ssh to a file inside it is shared - it is a second name made on purpose, as a copy is, and the handle's path is the name that was opened" }
else { Write-Skip "A HARD LINK COULD NOT BE MADE, so the known limit was not pinned." }

Write-Host ""
Write-Host "--- a place that is itself reached through a link is still the place ---" -ForegroundColor Cyan
$realHome = Join-Path $script:real "the-real-home"
$linkedHome = Join-Path $links "home-by-a-junction"
$inRealHome = New-File (Join-Path $realHome "settings\notes.json") '{"dummy":1}'
Check (New-Junction $linkedHome $realHome) "CONTROL: a junction was made to a folder, and the home is NAMED by the junction"
Check (Test-Refused $linkedHome $inRealHome $inHome -Force) "named by its real path, a file in a home that is named through a junction is refused as the home, -Force or not"
Check (Test-Refused $linkedHome (Join-Path $linkedHome "settings\notes.json") $inHome -Force) "and named through the junction too"
$resolved = Resolve-HordeFilesDenyPlace -Path $linkedHome
Check (-not $resolved.unknown -and @($resolved.paths).Count -eq 2 -and $resolved.paths[0] -ceq $linkedHome -and $resolved.paths[1] -ceq $realHome) "the home is known by both paths: as it was written, and where it really is"
Check (Test-Shared $linkedHome (New-File (Join-Path $docs "from-a-linked-home.md"))) "CONTROL: a file outside it is shared into that home"
$movedReal = Join-Path $script:real "harness-x-really-here"
$inMoved = New-File (Join-Path $movedReal "notes.md")
$wasMoved = $env:HORDE_TEST_HARNESS_X_HOME
$movedLink = Join-Path $links "harness-x-by-a-junction"
Check (New-Junction $movedLink $movedReal) "CONTROL: a junction was made to a folder, and a harness's variable names the junction"
$env:HORDE_TEST_HARNESS_X_HOME = $movedLink
$viaMoved = Test-Refused $h $inMoved $inAgent
$viaMovedForce = Test-Shared $h $inMoved -Force
$env:HORDE_TEST_HARNESS_X_HOME = $wasMoved
Check $viaMoved "a file in a harness's folder that its variable names through a junction is refused as that folder"
Check $viaMovedForce "and shared with -Force"
$prefixed = Resolve-HordeFilesDenyPlace -Path ("\\?\" + $realHome)
Check (-not $prefixed.unknown -and @($prefixed.paths) -ccontains $realHome) "a place written behind the long-path prefix is known by its plain path"
$absent = Resolve-HordeFilesDenyPlace -Path (Join-Path $script:real "no-such-folder")
Check (-not $absent.unknown -and @($absent.paths).Count -eq 1) "a place that is not there is known by its written path alone, and is not an unknown"
$onShare = Resolve-HordeFilesDenyPlace -Path ("\\" + (New-NoHost) + "\share\home")
Check (-not $onShare.unknown -and @($onShare.paths).Count -eq 0) "a place on a network share holds no file of this machine's drives, and is never looked at"
$noPath = Resolve-HordeFilesDenyPlace -Path "C:\a<b>|c\?"
Check ($noPath.unknown) "a place whose path is no path at all is unknown"
# A PLACE THAT IS THERE AND CANNOT BE ASKED is a refusal, not a pass. Windows is made to say nothing here.
$script:realFolderFinal = ${function:Get-HordeFilesFolderFinalPath}
function Get-HordeFilesFolderFinalPath { param([string]$Path) return [pscustomobject]@{ state = "unknown"; path = "" } }
$unasked = Test-Refused $h $plainDoc "really is could not be told" -Force
$unaskedWhy = Test-Refused $h $plainDoc "the Horde home"
$unaskedNever = Test-Refused $h $plainDoc $never -NotLike "share it again" -Force
Set-Item -Path function:Get-HordeFilesFolderFinalPath -Value $script:realFolderFinal
Check $unasked "when Windows will not say where the home really is, an ordinary file is refused, -Force or not: it cannot be told that it is not in it"
Check $unaskedWhy "and the reason names which place could not be asked"
Check $unaskedNever "and says -Force does not change that, and nothing of sharing it again: the place is one -Force never lifts"
Check (Test-Shared $h $plainDoc) "CONTROL: asked again with Windows answering, the file is shared"

Write-Host ""
Write-Host "--- is a path under a folder: the edge, the case of A to Z, and nothing looser ---" -ForegroundColor Cyan
Check (Test-HordeFilesPathUnder -Path "C:\x\ab\f.md" -Folder "C:\x\ab") "a file in a folder is under it"
Check (Test-HordeFilesPathUnder -Path "C:\x\ab\deep\er\f.md" -Folder "C:\x\ab") "and one deeper"
Check (Test-HordeFilesPathUnder -Path "C:\x\ab" -Folder "C:\x\ab") "the folder is under itself"
Check (Test-HordeFilesPathUnder -Path "C:\x\ab\f.md" -Folder "C:\x\ab\") "a folder written with its separator is the same folder"
Check (-not (Test-HordeFilesPathUnder -Path "C:\x\abc\f.md" -Folder "C:\x\ab")) "C:\x\abc is not under C:\x\ab"
Check (-not (Test-HordeFilesPathUnder -Path "C:\x\a" -Folder "C:\x\ab")) "nor is a shorter path"
Check (-not (Test-HordeFilesPathUnder -Path "C:\x\f.md" -Folder "C:\x\ab")) "nor a file beside the folder"
Check (Test-HordeFilesPathUnder -Path "c:\X\AB\F.MD" -Folder "C:\x\ab") "the case of A to Z does not matter"
Check (-not (Test-HordeFilesPathUnder -Path ("C:\x\a" + [char]0xE9 + "\f.md") -Folder ("C:\x\a" + [char]0xC9))) "the case of a letter outside A to Z does: both paths are as the disk holds them"
Check (-not (Test-HordeFilesPathUnder -Path ("C:\x\a" + [char]0xAD + "b\f.md") -Folder "C:\x\ab")) "and a folder with an unseen character in its name is another folder"
Check (("C:\x\a" + [char]0xAD + "b\f.md").StartsWith("C:\x\ab\")) "CONTROL: the runtime's own StartsWith DOES take it for the same folder, which is why this compares code units"

Write-Host ""
Write-Host "--- where a folder really is, and what a drive letter stands for ---" -ForegroundColor Cyan
$asked = Get-HordeFilesFolderFinalPath -Path $sshFolder
Check ($asked.state -ceq "ok" -and $asked.path -ceq ("\\?\" + $sshFolder)) "the final path of a folder is its path behind \\?\"
$viaJunction = Get-HordeFilesFolderFinalPath -Path (Join-Path $links "junction")
Check ($viaJunction.state -ceq "ok" -and $viaJunction.path -ceq ("\\?\" + $sshFolder)) "asked of a junction, it is the folder the junction leads to"
$viaLink = Get-HordeFilesFolderFinalPath -Path (Join-Path $links "folder-link")
Check ($viaLink.state -ceq "ok" -and $viaLink.path -ceq ("\\?\" + $sshFolder)) "and of a symbolic link, the folder it leads to"
$notThere = Get-HordeFilesFolderFinalPath -Path (Join-Path $script:real "no-such-folder")
Check ($notThere.state -ceq "absent" -and $notThere.path -eq "") "a folder that is not there is absent"
$parentGone = Get-HordeFilesFolderFinalPath -Path (Join-Path $script:real "no-such-folder\nor-this")
Check ($parentGone.state -ceq "absent") "and so is one whose parent is not there"
$badName = Get-HordeFilesFolderFinalPath -Path "C:\a<b>|c"
Check ($badName.state -ceq "unknown") "a name Windows cannot open for another reason is unknown, never absent"
$systemLetter = $script:real.Substring(0, 1)
Check ((Get-HordeDriveLetterTarget -Letter $systemLetter) -like "\Device\*") ("the drive this suite is on stands for a volume (" + (Get-HordeDriveLetterTarget -Letter $systemLetter) + ")")
$noLetters = @(Get-FreeLetters)
Check ($noLetters.Count -ge 1 -and (Get-HordeDriveLetterTarget -Letter $noLetters[0]) -eq "") "a letter that names nothing stands for nothing"
Check ((Get-HordeDriveAliasRefusal -Path ($systemLetter + ":\x.md")) -eq "" -and (Get-HordeDriveAliasRefusal -Path ($noLetters[0] + ":\x.md")) -eq "") "an ordinary drive, and a letter that names nothing, are not this question's"
Check ((Get-HordeDriveAliasRefusal -Path "x.md") -eq "" -and (Get-HordeDriveAliasRefusal -Path "") -eq "" -and (Get-HordeDriveAliasRefusal -Path "\\server\share\x.md") -eq "") "nor is a path with no drive letter"

Write-Host ""
Write-Host "--- a drive letter that stands for a network drive is refused on the first question, and no letter is made ---" -ForegroundColor Cyan
# A SUITE MUST NOT CHANGE WHAT OTHER PROCESSES OF THE USER SEE, and a drive letter is seen by all of
# them. Until 2026-10-13 this section made real letters - one aimed at a host that does not exist,
# letters over that, a ring - and while they stood a fresh powershell of any other session printed
# an error and took 1.4 s to start (core/PathText.ps1, Get-HordeDriveLetterType, has the
# measurement). NO LETTER IS MADE HERE NOW. The two functions that ask Windows about a drive letter -
# what it stands for, and what type of drive it is - are replaced, for this section, by two that
# answer from a table of this suite's for the letters in it and ask the real function for every
# other, and that count who asked. Each is called exactly as the real one is: one -Letter, a text
# back. What Windows itself says of a letter is test/test-path-text.ps1's, in the one place a real
# letter is made.
#   N  a network drive the system mapped        R  a share, straight (the device prefix and then UNC)
#   O  the letter N, and P the letter O         J and K each other (a ring)
#   L  a folder of this suite's own drive, as subst makes; M the letter L, and T the letter M
$script:realLetterTarget = ${function:Get-HordeDriveLetterTarget}
$script:realDriveType = ${function:Get-HordeDriveLetterType}
$script:stands = @{}
$script:driveTypes = @{}
$script:targetAsked = New-Object System.Collections.ArrayList
$script:driveAsked = New-Object System.Collections.ArrayList
function Get-HordeDriveLetterTarget {
    param([Parameter(Mandatory = $true)][string]$Letter)
    [void]$script:targetAsked.Add($Letter)
    if ($script:stands.ContainsKey($Letter.ToUpperInvariant())) { return ("" + $script:stands[$Letter.ToUpperInvariant()]) }
    return (& $script:realLetterTarget -Letter $Letter)
}
function Get-HordeDriveLetterType {
    param([Parameter(Mandatory = $true)][string]$Letter)
    [void]$script:driveAsked.Add($Letter)
    if ($script:driveTypes.ContainsKey($Letter.ToUpperInvariant())) { return ("" + $script:driveTypes[$Letter.ToUpperInvariant()]) }
    return (& $script:realDriveType -Letter $Letter)
}
$h = New-TestHome
$netHost = New-NoHost
$script:stands = @{ "N" = ("\Device\LanmanRedirector\;N:0000000000012345\" + $netHost + "\share"); "R" = ("\??\UNC\" + $netHost + "\share"); "O" = "\??\N:\"; "P" = "\??\O:\"
    "J" = "\??\K:"; "K" = "\??\J:"; "L" = ("\??\" + $docs); "M" = "\??\L:"; "T" = "\??\M:" }
$script:driveTypes = @{ "N" = "Network"; "R" = "Network"; "O" = "NoRootDirectory"; "P" = "NoRootDirectory"; "J" = "NoRootDirectory"; "K" = "NoRootDirectory"; "L" = "Fixed"; "M" = "Fixed"; "T" = "Fixed" }
$results = @{}
try {
    $results.said = Get-HordeDriveAliasRefusal -Path "O:\x.md"
    $results.saidPrefix = ((Get-HordeDriveAliasRefusal -Path "\\?\O:\x.md") -like "*stands for a network drive*")
    $results.saidRelative = ((Get-HordeDriveAliasRefusal -Path "O:x.md") -like "*stands for a network drive*")
    $results.chain = Get-HordeDriveAliasRefusal -Path "P:\x.md"
    $script:driveAsked.Clear()
    $results.viaShare = Test-Refused $h "O:\x.md" "is on a drive (O:) that stands for a network drive (N:), and only a path on one of this machine's own drives is taken. A file is shared from one of this machine's own drives: name it by its local path, or copy it to a local folder"
    $results.viaShareChain = Test-Refused $h "p:\x.md" "that stands for a network drive"
    $results.askedForTheOver = (@($script:driveAsked | Select-Object -Unique) -join ",")
    $results.straight = Get-HordeDriveAliasRefusal -Path "R:\x.md"
    $results.viaShareStraight = Test-Refused $h "R:\x.md" "is on a drive (R:) that stands for a network share, and only a path on one of this machine's own drives is taken. A file is shared from one of this machine's own drives"
    $results.mapped = Get-HordeDriveAliasRefusal -Path "N:\x.md"
    $results.viaShareMapped = Test-Refused $h "N:\x.md" "is on a network drive (N:)"
    $results.placeOnNet = Resolve-HordeFilesDenyPlace -Path "N:\home"
    $results.placeOnAlias = Resolve-HordeFilesDenyPlace -Path "O:\home"
    $results.placeStraight = Resolve-HordeFilesDenyPlace -Path "R:\home"
    $results.ring = Get-HordeDriveAliasRefusal -Path "J:\x.md"
    $results.viaShareRing = Test-Refused $h "J:\x.md" "stands for another drive letter, and that for another, without end"
    $results.overLocal = Get-HordeDriveAliasRefusal -Path "L:\plain.md"
    $results.deep = Get-HordeDriveAliasRefusal -Path "T:\plain.md"
    $script:driveAsked.Clear()
    $results.ordinary = Test-Shared $h $plainDoc
    $results.askedForOrdinary = (@($script:driveAsked | Select-Object -Unique) -join ",")
    # WHAT ONLY THE RESOLVED PATH SHOWS. A PowerShell drive is this process's own - no other process
    # sees it - and a path on it is a path on its folder's drive only once it is resolved. For this
    # one share the table says that THIS SUITE'S OWN DRIVE stands for the network drive: the path as
    # written (on the PowerShell drive, which the table does not know) is let by, and only the second
    # asking, of the resolved path, can refuse.
    $psLetter = $noLetters[0]
    $null = New-PSDrive -Name $psLetter -PSProvider FileSystem -Root $docs -Scope Script
    try {
        $results.psResolves = ($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($psLetter + ":\plain.md") -ceq $plainDoc)
        $results.psShared = Test-Shared $h ($psLetter + ":\plain.md")
        $script:stands[$systemLetter.ToUpperInvariant()] = "\??\N:\"
        try { $results.resolvedOnly = Test-Refused $h ($psLetter + ":\plain.md") ("is on a drive (" + $systemLetter + ":) that stands for a network drive (N:)") } finally { $script:stands.Remove($systemLetter.ToUpperInvariant()) }
    } finally { Remove-PSDrive -Name $psLetter -Scope Script }
} finally {
    Set-Item -Path function:Get-HordeDriveLetterTarget -Value $script:realLetterTarget
    Set-Item -Path function:Get-HordeDriveLetterType -Value $script:realDriveType
}
Check ($results.said -like "'O:\x.md' is on a drive (O:) that stands for a network drive (N:), and only a path on one of this machine's own drives is taken") "a letter that stands for a network drive is refused, and the reason names both letters"
Check $results.saidPrefix "and behind the long-path prefix"
Check $results.saidRelative "and named from wherever that drive stands"
Check ($results.chain -like "*is on a drive (P:) that stands for a network drive (N:)*") "a letter that stands for a letter that stands for a network drive is refused too: the chain is followed to its end"
Check $results.viaShare "through a share, it is refused with that reason, and the share adds its own sentence: what to do about it"
Check $results.viaShareChain "and so is the chain, with its letter in small"
Check ($results.askedForTheOver -ceq "N") ("and through both shares only the network drive at the end was asked its type, never the letter that stands over it: that asking is what was measured looking the host up, and the refusal comes before it (asked: " + $results.askedForTheOver + ")")
Check ($results.straight -like "*is on a drive (R:) that stands for a network share*") "a letter that stands straight for a share is refused by the same question: the table says what it stands for"
Check $results.viaShareStraight "and a share from that letter is refused with that reason, and the share's own sentence after it"
Check ($results.mapped -eq "" -and $results.viaShareMapped) "CONTROL: a network drive the system mapped is not this question's - its target is not written as a share - and a share from it is refused by the network question, with its own reason"
Check (-not $results.placeOnNet.unknown -and @($results.placeOnNet.paths).Count -eq 0) "a folder of the list that is on a network drive is never opened: it holds no file of this machine's drives"
Check (-not $results.placeOnAlias.unknown -and @($results.placeOnAlias.paths).Count -eq 0) "nor is one on a letter that stands for a network drive"
Check (-not $results.placeStraight.unknown -and @($results.placeStraight.paths).Count -eq 0) "nor one on a letter that stands straight for a share"
Check ($results.ring -like "*stands for another drive letter, and that for another, without end*" -and $results.viaShareRing) "two letters that stand for each other are refused, asked directly and through a share: where the file is cannot be told"
Check ($results.overLocal -eq "") "a letter that stands for a folder of this machine's own drive is let by"
Check ($results.deep -eq "") "CONTROL: and so is a chain of three letters that ends at such a folder"
Check ($results.ordinary -and $results.askedForOrdinary -ceq $systemLetter) ("CONTROL: with the same answerers in place an ordinary file is shared, and the only drive asked its type was this suite's own (" + $results.askedForOrdinary + ")")
Check ($results.psResolves -and $results.psShared) "CONTROL: a file named on a PowerShell drive of this process's own, over an ordinary folder, is shared"
Check $results.resolvedOnly "a path that is on such a letter only once it is resolved is refused the same: the question is asked again of the resolved path"
Check ((Get-HordeDriveLetterTarget -Letter $systemLetter) -like "\Device\*" -and (Get-HordeDriveLetterType -Letter $systemLetter) -ceq "Fixed" -and (Test-Shared $h $plainDoc)) "the two real questions are back, and an ordinary file is shared"

Write-Host ""
Write-Host "--- what a text file holds: a private key never, a token of a known shape unless -Force ---" -ForegroundColor Cyan
# EVERY PLANTED SHAPE IS ASSEMBLED FROM PIECES AT RUN TIME, as test/test-secrets.ps1 does, so that no
# credential-shaped text sits in this file; none of them was ever a credential. The patterns are
# core/Secrets.ps1's and are not tested here: what is tested is which kinds a share asks for, what
# -Force lifts, what the reason says, and that nothing is kept.
$h = New-TestHome
$held = Join-Path $script:real "held"
$keyLine = "-----BEGIN RSA PRIV" + "ATE KEY-----"
$keyBody = "MIIEow" + "IBAAKCAQEAx9Qm2Lp7Rt4Vb8Nc1Hdq3J9s"
$keyBlock = $keyLine + "`n" + $keyBody + "`n-----END RSA PRIV" + "ATE KEY-----"
$neverSays = "what it holds looks like a private key"
$keyFiles = [ordered]@{
    "report.md" = ("# A report`n`nSome words.`n`n" + $keyBlock + "`n`nMore words.")
    "at-the-start.txt" = ($keyBlock + "`nwords after it")
    "at-the-end.txt" = ("words before it`n" + $keyLine)
    "one-line.txt" = ("words " + $keyLine + " words")
    "with-crlf.txt" = ("words`r`n" + $keyLine + "`r`n" + $keyBody + "`r`n")
    "account.json" = ('{"type":"dummy","pk":"' + $keyLine.Replace("RSA ", "") + '\n' + $keyBody + '\n"}')
    "page.html" = ("<html><body><pre>" + $keyBlock + "</pre></body></html>")
    "page.htm" = ("<p>" + $keyLine.Replace("RSA", "EC") + "</p>")
    "encrypted.md" = ("words`n" + $keyLine.Replace("RSA", "ENCRYPTED") + "`n")
    "pgp.txt" = ("words`n" + $keyLine.Replace("RSA PRIV", "PGP PRIV").Replace("KEY-----", "KEY BLOCK-----") + "`n")
    "bare.txt" = ("words`n" + $keyLine.Replace("RSA ", "") + "`n")
}
foreach ($named in $keyFiles.Keys) {
    $file = New-File (Join-Path $held $named) $keyFiles[$named]
    Check (Test-Refused $h $file $neverSays -NotLike $keyBody) ($named + ": a text holding a private key's first line is refused, and the reason names the kind and repeats nothing of it")
    Check (Test-Refused $h $file "A file that holds one is never shared, and -Force does not change that" -NotLike "share it again" -Force) "and with -Force it is refused all the same, and the reason says so"
}
$withMark = Join-Path $held "with-a-mark.md"
[System.IO.File]::WriteAllBytes($withMark, ([byte[]](0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::UTF8.GetBytes($keyBlock)))
Check (Test-Refused $h $withMark $neverSays -Force) "after a byte order mark too"
$big = New-Object System.Text.StringBuilder
while ($big.Length -lt 1050000) { [void]$big.Append("An ordinary line of an ordinary report, with nothing in it at all.`n") }
$bigText = $big.ToString().Substring(0, 1048576 - $keyLine.Length) + $keyLine
$bigFile = New-File (Join-Path $held "the-largest.md") $bigText
Check ((New-Object System.IO.FileInfo($bigFile)).Length -eq 1048576) "CONTROL: a text file of exactly the largest size that is shared was made, the key's first line its last bytes"
Check (Test-Refused $h $bigFile $neverSays -Force) "a private key's first line at the very end of the largest file is found"
Check (Test-Shared $h (New-File (Join-Path $held "the-largest-plain.md") $big.ToString().Substring(0, 1048576))) "CONTROL: the same file without it is shared"
# WHAT IS NO PRIVATE KEY, though it looks near to one.
$nearKeys = [ordered]@{
    "public.md" = "-----BEGIN PUBLIC KEY-----`nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A`n-----END PUBLIC KEY-----"
    "certificate.txt" = "-----BEGIN CERTIFICATE-----`nMIIDdzCCAl-gAwIBAgIEAgAAuTANBgkq`n-----END CERTIFICATE-----"
    "small-letters.md" = ("words " + $keyLine.ToLowerInvariant() + " words")
    "the-words-alone.md" = "How to make a PRIVATE KEY, and where the BEGIN line goes."
    "end-line-only.txt" = ("-----END RSA PRIV" + "ATE KEY-----")
}
foreach ($named in $nearKeys.Keys) { Check (Test-Shared $h (New-File (Join-Path $held $named) $nearKeys[$named])) ("CONTROL: " + $named + " holds no private key's first line, and is shared with no -Force") }

$tokenBody = "Ab1" * 12
$shaped = [ordered]@{
    "an access token" = @(("gh" + "p_" + $tokenBody), ("github" + "_pat_" + ("Ef3" * 10)), ("gl" + "pat-" + ("Gh4" * 8)), ("xo" + "xb-" + ("123456789012" * 2)), ("s" + "k-" + ("Ij5" * 10)), ("AK" + "IA" + "ABCDEFGHIJKLMNOP"), ("AI" + "za" + ("Kl6" * 12)))
    "a signed web token" = @(("ey" + "JhbGciOiJIUzI1NiJ9" + "." + "ey" + "JzdWIiOiIxMjM0In0" + "." + "c2lnbmF0dXJlLXBhcnQ"))
    "a webhook address" = @(("https://hooks.slack" + ".com/services/T00000000/B00000000/" + "XyXyXyXyXyXyXyXyXyXyXyXy"), ("https://discord" + ".com/api/webhooks/123456789012/" + "AbCdEfGhIjKl"))
}
$shapeCount = 0
foreach ($kindName in $shaped.Keys) {
    foreach ($plantedShape in @($shaped[$kindName])) {
        $shapeCount++
        $wrapped = @(("The value is " + $plantedShape + " and more words."), ('{"value":"' + $plantedShape + '"}'), ("<a href=""https://example.org/?t=" + $plantedShape + """>x</a>"))
        $names = @(("shape-" + $shapeCount + ".md"), ("shape-" + $shapeCount + ".json"), ("shape-" + $shapeCount + ".html"))
        for ($at = 0; $at -lt 3; $at++) {
            # A webhook address is itself an address: it is not put inside another one.
            if ($at -eq 2 -and $kindName -ceq "a webhook address") { continue }
            $file = New-File (Join-Path $held $names[$at]) $wrapped[$at]
            $tail = $plantedShape.Substring($plantedShape.Length - 8)
            Check (Test-Refused $h $file ("what it holds looks like " + $kindName + ", by its shape; what was found is not repeated here") -NotLike $tail) ($names[$at] + ": a text holding " + $kindName + " is refused, and the reason names the kind and repeats nothing of it")
            Check (Test-Refused $h $file $insist) "and says that -Force shares it"
            Check (Test-Shared $h $file -Force) "with -Force it is shared"
        }
    }
}
Check ($shapeCount -eq 10) "ten planted shapes of the three kinds -Force lifts were each tried in Markdown, JSON and HTML"
$both = New-File (Join-Path $held "both.md") ("a token " + $shaped["an access token"][0] + " and a key`n" + $keyBlock)
Check (Test-Refused $h $both $neverSays -Force) "a text holding a token AND a private key is refused for the key, which -Force does not lift"
# THE KINDS THAT ARE NOT ASKED FOR AT ALL (the review's decision): core finds each of these in a
# text, and a share lets each by with no -Force, because ordinary reports are full of them.
$notAsked = [ordered]@{
    "after-a-colon.txt" = ("Pass" + "word: " + "hunter2x, and then rotate it")
    "in-a-sentence.md" = ("the pass" + "word is 'correct horse battery staple'")
    "bearer.md" = ("Send Bea" + "rer " + ("a1b2c3d4e5" * 3) + " in the header.")
    "authorization.txt" = ("Authorization: Basic " + "ZGVwbG95OlRyMHViNGRvcjM=")
    "inside-an-address.md" = ("clone https://deploy:Tr0ub4dor3x@" + "git.example.com/repo.git")
    "a-long-run.json" = ('{"id":"' + "Zx9Qm2Lp7Rt4Vb8Nc1Hd" + "6Jf3Kg5Ws0YaUe4Ti7Ro" + '"}')
    "a-run-with-slashes.txt" = ("wJalrXUtnFEMI/K7MDENG/" + "bPxRfiCYEXAMPLEKEY")
}
# ALONE ON ITS LINE, THAT IS A YAML SECRET (core/Secrets.ps1, the next round of the review): the named
# kind finds it, and -Force lifts it. Followed by more words on its line, as above, it is prose.
$yamlLine = New-File (Join-Path $held "yaml-line.txt") ("Pass" + "word: " + "hunter2x")
Check (Test-Refused $h $yamlLine "a secret written under a name such as client_secret or password") "a password alone after a colon, the rest of its line, is refused as a secret under its own name"
Check (Test-Shared $h $yamlLine -Force) "and -Force shares it"
foreach ($named in $notAsked.Keys) {
    $file = New-File (Join-Path $held $named) $notAsked[$named]
    Check ((Find-HordeSecretKind -Text $notAsked[$named]) -cne "" -and (Test-Shared $h $file)) ("CONTROL: " + $named + " holds what core calls '" + (Find-HordeSecretKind -Text $notAsked[$named]) + "', which a share does not ask for: it is shared with no -Force")
}
# WHAT SESSIONS REALLY WRITE, in small: each is shared with no -Force. The measurement on full-size
# files, with the numbers, is in the pull request.
$sha = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
$picture = [System.Convert]::ToBase64String([byte[]](0..255 | ForEach-Object { ($_ * 37 + 11) % 256 }) * 8)
$reallyWritten = [ordered]@{
    "report-with-a-picture.html" = ("<html><body><h1>Report</h1><img src=""data:image/png;base64," + $picture + """></body></html>")
    "minified.txt" = "!function(e,t){""use strict"";var n=function(e){return e&&e.__esModule?e:{default:e}},r=t.a1B2c3D4e5F6g7H8,o=Object.assign||function(e){for(var t=1;t<arguments.length;t++){var n=arguments[t];for(var r in n)Object.prototype.hasOwnProperty.call(n,r)&&(e[r]=n[r])}return e};e.exports=o}(module,exports);"
    "ids-and-hashes.json" = ('{"id":"0273216a-4aa6-420b-8bd6-b5d61a13d73d","commit":"07af8361c2d4e5f60718293a4b5c6d7e8f901234","sha256":"' + $sha + '","etag":"W/\"5d41402abc4b2a76b9719d911017c592\"","rows":[{"fileId":"a3f1c2d4e5b60718293a4b5c6d7e8f90","version":3}]}')
    "commit-and-sha.md" = ("Merged at 07af8361c2d4e5f60718293a4b5c6d7e8f901234.`n`n    sha256: " + $sha + "`n")
    "setting-up-the-api.md" = ("# Setting the API key`n`nPut your key in the environment:`n`n    export EXAMPLE_API_KEY=your-api-key-here`n    EXAMPLE_API_KEY=<paste the key>`n`nA key starts with s" + "k- and is shown once. Never commit it.`n")
}
foreach ($named in $reallyWritten.Keys) { Check (Test-Shared $h (New-File (Join-Path $held $named) $reallyWritten[$named])) ("CONTROL: " + $named + ", as a session writes one, is shared with no -Force") }
# A PICTURE AND A PDF ARE NOT LOOKED INTO, pinned so that it is known: their bytes are not text.
$pngHead = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
$pngFile = Join-Path $held "picture.png"
[System.IO.File]::WriteAllBytes($pngFile, ($pngHead + [System.Text.Encoding]::ASCII.GetBytes($keyBlock)))
Check (Test-Shared $h $pngFile) "KNOWN LIMIT: a picture is not looked into - one whose bytes hold a private key's first line is shared"
$pdfFile = Join-Path $held "paper.pdf"
[System.IO.File]::WriteAllBytes($pdfFile, [System.Text.Encoding]::ASCII.GetBytes("%PDF-1.4`n" + $shaped["an access token"][0] + "`n"))
Check (Test-Shared $h $pdfFile) "KNOWN LIMIT: nor is a PDF - one whose bytes hold a token is shared"
# AND WHAT ELSE IT DOES NOT SEE, pinned the same way.
$cut = $shaped["an access token"][0]
Check (Test-Shared $h (New-File (Join-Path $held "cut-in-two.md") ($cut.Substring(0, 10) + "`n" + $cut.Substring(10)))) "KNOWN LIMIT: a token cut across two lines is not found"
Check (Test-Shared $h (New-File (Join-Path $held "as-base64.txt") ([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($keyBlock))))) "KNOWN LIMIT: nor is a private key written as base64 of itself"
# A SECRET UNDER ITS OWN NAME (the review's second round, 2026-10-13). The file a sign-in provider
# issues for a web client is JSON with a member called client_secret; one of Horde's settings may
# name it anywhere. Until that round, under a name that says nothing it was shared with no -Force
# at all, and this place pinned that as a known limit. It is refused now, by the one kind of
# core's that goes by a name and is asked for all the same. Made up here, never the real one;
# core/Secrets.ps1's own suite attacks the rule, and what is tested here is the share.
$namedKind = "a secret written under a name such as client_secret or password"
$namedSays = "what it holds looks like " + $namedKind + ", by its shape; what was found is not repeated here"
$clientValue = "GOC" + "SPX-" + "Ab3dEf6hIj9kLm2nOp5qRs8tUv1w"
$clientFile = '{"web":{"client_id":"123456789012-abcdefghijklmnopqrstuvwxyz012345.apps.example.com","project_id":"made-up","client_' + 'secret":"' + $clientValue + '","redirect_uris":["https://relay.example.org/auth/callback"]}}'
$clientPretty = $clientFile.Replace('","', ('",' + "`r`n" + '    "')).Replace('":"', '": "')
Check ($clientPretty -cne $clientFile -and @($clientPretty -split "`n").Count -ge 4 -and (Get-HordeFilesJsonProblem -Bytes ([System.Text.Encoding]::UTF8.GetBytes($clientPretty))) -eq "") "CONTROL: the client file was also written out over several lines, a blank after each colon, and is still one JSON text"
Check ((Find-HordeSecretKind -Text $clientFile) -ceq "a long random-looking string, as a key or token is" -and (Find-HordeSecretKind -Text $clientFile -Kinds (@($list.shapes.never) + @($list.shapes.lifted))) -ceq $namedKind) "CONTROL: asked as every other caller asks, core says of the made-up client file what it said before; asked for the kinds a share names, it answers the secret under its name"
foreach ($written in @(@("on one line", "web-client.json", $clientFile), @("over several lines", "web-client-written-out.json", $clientPretty))) {
    $file = New-File (Join-Path $held $written[1]) $written[2]
    Check (Test-Refused $h $file $namedSays -NotLike "Ab3dEf6h") ("the made-up client file " + $written[0] + ", under a name that says nothing, is REFUSED with no -Force, and the reason names the kind and repeats nothing of the value")
    Check (Test-Refused $h $file $insist) "and says that -Force shares it"
    Check (Test-Shared $h $file -Force) "with -Force it is shared"
}
Check (Test-Refused $h (New-File (Join-Path $held "client_secret_123456789012.apps.example.com.json") $clientFile) "holds 'secret'") "under the name it is downloaded with, such a file is refused for its name, which is judged first"
$pairNote = New-File (Join-Path $held "settings-notes.md") ("# Notes`n`nIn the file:`n`n    client_" + "secret=" + $clientValue + "`n")
Check (Test-Refused $h $pairNote $namedSays -NotLike "Ab3dEf6h") "written as name=value, with an equals sign, the same secret is refused the same way"
Check (Test-Shared $h $pairNote -Force) "and shared with -Force"
$passNote = New-File (Join-Path $held "name-value.md") ("Set pass" + "word=" + "hunter2longer in the file.")
Check (Test-Refused $h $passNote $namedSays -NotLike "hunter2") "and so is a password written as name=value, which a share let by until that round"
# WHAT THAT KIND LETS BY, each shared with no -Force: a schema that describes the member, and a
# page whose values are placeholders.
$described = '{"properties":{"client_' + 'secret":{"type":"string","description":"whatever-the-provider-issued"},"pass' + 'word":{"type":"string","minLength":12}}}'
Check (Test-Shared $h (New-File (Join-Path $held "client-schema.json") $described)) "CONTROL: a schema, where the member's value is an object that describes it, is shared with no -Force"
$placeheld = '{"client_' + 'secret":"<paste-the-secret-here>","api_' + 'key":"YOUR_API_KEY_HERE","pass' + 'word":"changeme-before-use"}'
Check (Test-Shared $h (New-File (Join-Path $held "client-sample.json") $placeheld)) "CONTROL: and a sample whose values are placeholders (angle brackets, the word your, changeme) is shared with no -Force"
# THE GAP THAT IS LEFT FOR A FILE NO RELAY NAMES, pinned so that closing it is seen: the same file
# with its secret under a member name that is none of the six. Its content says nothing; what closes
# it is the relay that keeps it naming it (the relays' secret files, below, shares this very file
# with a made-up relay that names it).
$otherMember = '{"web":{"client_id":"made-up.apps.example.com","signing_' + 'material":"' + $clientValue + '"}}'
$movedClient = New-File (Join-Path $held "moved-client.json") $otherMember
Check (Test-Shared $h $movedClient) "KNOWN LIMIT: a moved file whose secret sits under another member name, and that no relay names, is shared, with no -Force"
# THE FUNCTION ITSELF, and the list it reads.
Check ((@($list.shapes.never) -join ",") -ceq "a private key" -and (@($list.shapes.lifted) -join ",") -ceq "an access token,a signed web token,a webhook address,a secret written under a name such as client_secret or password") "the kinds asked for are one that is never lifted and four that -Force lifts"
$asBytes = { param([string]$Words) return ,([System.Text.Encoding]::UTF8.GetBytes($Words)) }
Check ((Get-HordeFilesContentRefusal -Bytes (& $asBytes "plain words")) -eq "" -and (Get-HordeFilesContentRefusal -Bytes ([byte[]]@())) -eq "" -and (Get-HordeFilesContentRefusal -Bytes (& $asBytes "plain words") -Force) -eq "") "plain words and an empty file hold nothing"
Check ((Get-HordeFilesContentRefusal -Bytes (& $asBytes $keyBlock)) -like ($neverSays + "*") -and (Get-HordeFilesContentRefusal -Bytes (& $asBytes $keyBlock) -Force) -like ($neverSays + "*")) "a private key is answered the same with and without -Force"
Check ((Get-HordeFilesContentRefusal -Bytes (& $asBytes $cut)) -like "*an access token*" -and (Get-HordeFilesContentRefusal -Bytes (& $asBytes $cut) -Force) -eq "") "a token is answered without -Force and not with it"
$everyKind = @(Find-HordeSecretKind -Text $keyBlock -Kinds (@($list.shapes.never) + @($list.shapes.lifted)))
Check ($everyKind.Count -eq 1 -and $everyKind[0] -ceq "a private key") "CONTROL: every kind the list names is one core/Secrets.ps1 has - it throws for a name it does not have"

Write-Host ""
Write-Host "--- the relays' own secret files: asked of the port, refused by the handle's path, never lifted ---" -ForegroundColor Cyan
# files/Deny.ps1's header, THE RELAYS' OWN SECRET FILES. Each answer the port can give is attacked:
# known with files, known with none, unknown naming a relay, and nobody asked. A file a relay names is
# reached by its path, in another case, through .., by a link to it and through a junction to its
# folder, each with and without -Force; and the files beside it are shared. Every relay is this
# suite's own, and every file holds dummy words.
$h = New-TestHome
$relayDir = Join-Path $script:real "relay-kept"
$clientFile = New-File (Join-Path $relayDir "innocent-name.json") '{"dummy":"content-of-the-client-file-0042"}'
$besideClient = New-File (Join-Path $relayDir "other.json") '{"dummy":1}'
$longerName = New-File (Join-Path $relayDir "innocent-name.json.md") "dummy words, and no secret"
$neverFile = Join-Path $relayDir "not-there-yet.json"
$saysRelay = "is what the relay 'test-relay-a' calls the sign-in client file"
$script:entriesA = @([pscustomobject]@{ path = $clientFile; what = "the sign-in client file" })
Check (Test-Refused $h $clientFile ($saysRelay + " ('" + $clientFile + "'), a file it keeps a secret in. " + $never) "content-of-the-client") "KNOWN WITH FILES: the file a relay names is refused, the reason naming the relay and what the file is, and nothing it holds"
Check (Test-Refused $h $clientFile $saysRelay -Force) "and -Force does not lift it"
Check (Test-Shared $h $besideClient) "CONTROL: a file beside it, in the same folder, is shared"
Check (Test-Shared $h $longerName -Force) "CONTROL: and so is one whose name only begins with its name, as a path that merely begins like it is not it"
Check (Test-Refused $h (Join-Path $relayDir "INNOCENT-NAME.JSON") $saysRelay) "the file, reached by its path in other case, is refused"
Check (Test-Refused $h (Join-Path $relayDir "sub\..\innocent-name.json") $saysRelay -Force) "and by a path with .. in it, with -Force"
$script:entriesA = @([pscustomobject]@{ path = $clientFile.ToUpperInvariant(); what = "the sign-in client file" })
Check (Test-Refused $h $clientFile $saysRelay) "a relay that names the file in other case still has it refused"
Check (Test-Refused $h $clientFile $saysRelay -Force) "and -Force does not lift that either"
$script:entriesA = @([pscustomobject]@{ path = (Join-Path $relayDir "made-up-sub\..\innocent-name.json"); what = "the sign-in client file" })
Check (Test-Refused $h $clientFile $saysRelay) "a relay that names the file with .. in its path still has it refused"
$links = Join-Path $script:work "links"
[void][System.IO.Directory]::CreateDirectory($links)
$junction = Join-Path $links "relay-kept-junction"
if (New-Junction $junction $relayDir) {
    $script:entriesA = @([pscustomobject]@{ path = $clientFile; what = "the sign-in client file" })
    Check (Test-Refused $h (Join-Path $junction "innocent-name.json") $saysRelay) "the file, reached through a junction to its folder, is refused"
    Check (Test-Refused $h (Join-Path $junction "innocent-name.json") $saysRelay -Force) "and with -Force"
    # A share never follows a link (files/Path.ps1), so the file beside it is refused through the junction
    # too - for the link, and not as the relay's file.
    Check (Test-Refused $h (Join-Path $junction "other.json") "is a link" "the relay") "CONTROL: the file beside it, through the same junction, is refused for the link, not as the relay's file"
    $script:entriesA = @([pscustomobject]@{ path = (Join-Path $junction "innocent-name.json"); what = "the sign-in client file" })
    Check (Test-Refused $h $clientFile $saysRelay -Force) "a relay that names the file THROUGH a junction has it refused by its real path, -Force or not"
} else { Write-Skip "a junction could not be made here, so the junction cases did not run" }
$fileLink = Join-Path $links "innocent-link.md"
if (New-FileLink $fileLink $clientFile) {
    $script:entriesA = @([pscustomobject]@{ path = $clientFile; what = "the sign-in client file" })
    Check (Test-Refused $h $fileLink $saysRelay) "the file, reached by a symbolic link to it with another name, is refused"
    Check (Test-Refused $h $fileLink $saysRelay -Force) "and with -Force"
} else { Write-Skip "a symbolic link could not be made here (it needs the right to make one), so the file-link cases did not run" }
# A HARD LINK, A SECOND NAME OF THE SAME FILE (the review of PR 238): no path says it is the file, so
# it is known by which file it is - the volume serial number and file index of the open handle.
$script:entriesA = @([pscustomobject]@{ path = $clientFile; what = "the sign-in client file" })
$hardToClient = Join-Path $links "a-second-name.json"
$hardToBeside = Join-Path $links "a-second-name-of-other.json"
$null = & cmd.exe /c ("mklink /H `"" + $hardToClient + "`" `"" + $clientFile + "`" >nul 2>nul")
$null = & cmd.exe /c ("mklink /H `"" + $hardToBeside + "`" `"" + $besideClient + "`" >nul 2>nul")
if ([System.IO.File]::Exists($hardToClient) -and [System.IO.File]::Exists($hardToBeside)) {
    $sameFile = "is the very file the relay 'test-relay-a' calls the sign-in client file ('" + $clientFile + "') under another name, as a hard link or a network or device path to it is"
    Check (Test-Refused $h $hardToClient $sameFile) "a hard link to the file a relay names, under another name in another folder, is refused as that file"
    Check (Test-Refused $h $hardToClient $sameFile -Force) "and -Force does not lift it"
    Check (Test-Shared $h $hardToBeside -Force) "CONTROL: a hard link to the file BESIDE it is another file, and is shared"
    Check ((Get-HordeFilesDenyRefusal -FinalPath $hardToClient -HordeHome $h -RepoRoot $repo -Force) -like ("*" + $sameFile + "*")) "and the list alone, handed no handle, opens the file for its attributes and says the same"
    $script:entriesA = @([pscustomobject]@{ path = $hardToClient; what = "the sign-in client file" })
    Check (Test-Refused $h $clientFile "under another name, as a hard link or a network or device path to it is" -Force) "a relay that names the second name has the first refused, -Force or not"
} else { Write-Skip "a hard link could not be made here, so the hard-link cases did not run" }
# AN ENTRY THAT IS NO LOCAL PATH IS ASKED WHICH FILE IT IS (round 2 of the review of PR 238,
# 2026-10-14). Through the REAL port, which now hands such a path over: round 1 had to replace the
# port's answer to reach this door, and refused every share here. Each spelling of the client file
# that is no drive path is the same file and is refused, -Force or not, while an ordinary file is
# shared; an identity that cannot be read refuses every share; nothing there, and a file on another
# volume, refuse nothing. A loopback share needs the machine's own administrative share, so a box
# that has none skips those spellings and says so; the device path and the volume need nothing.
$sameAsLink = "under another name, as a hard link or a network or device path to it is"
$letterOf = $clientFile.Substring(0, 1)
$doors = @(("\\.\" + $clientFile), ("\\localhost\" + $letterOf + "$" + $clientFile.Substring(2)), ("\\127.0.0.1\" + $letterOf + "$" + $clientFile.Substring(2)), ("\\?\UNC\localhost\" + $letterOf + "$" + $clientFile.Substring(2)))
# The volume's own name, as the system lists it for the client file's drive (round 4 of the review
# of PR 238: Volume{guid} is one of the three device names the allow-list opens).
$volumeName = ("" + (& mountvol.exe ($letterOf + ":\") /L)).Trim()
if ($volumeName -cmatch '\A\\\\\?\\Volume\{[0-9a-fA-F-]{36}\}\\\z') { $doors += ($volumeName + $clientFile.Substring(3)) } else { Write-Skip ("the volume name of " + $letterOf + ": could not be read here ('" + $volumeName + "'), so the Volume{guid} spelling did not run") }
$clientIs = Get-HordeFilesPathIdentity -Path $clientFile
Check ($clientIs.state -ceq "ok") ("CONTROL: the client file's own identity can be read (" + $clientIs.state + ")")
foreach ($door in $doors) {
    $doorIs = Get-HordeFilesPathIdentity -Path $door
    $short = $door.Substring(0, [Math]::Min(18, $door.Length)) + "..."
    if ($doorIs.state -cne "ok" -and $door -cnotlike "\\.\*" -and $door -cnotlike "\\?\Volume*") { Write-Skip ("the loopback share " + $short + " could not be opened here (" + $doorIs.state + "), so that spelling did not run"); continue }
    Check ($doorIs.state -ceq "ok" -and $doorIs.id -ceq $clientIs.id) ("CONTROL: " + $short + " is the client file's own identity, as measured (" + $doorIs.state + ")")
    $script:entriesA = @([pscustomobject]@{ path = $door; what = "the sign-in client file" })
    Check ((Get-HordeRelaySecretFiles -HordeHome $h).state -ceq "known") ("the real port hands " + $short + " over as a file, not as a relay that could not tell")
    Check (Test-Refused $h $clientFile $sameAsLink) ("SAME IDENTITY: a relay that names the client file as " + $short + " has it refused by its plain path")
    Check (Test-Refused $h $clientFile $sameAsLink -Force) "and -Force does not lift it"
    Check (Test-Shared $h $besideClient -Force) "CONTROL: an ordinary file beside it is shared, where round 1 refused every share"
    if ($null -ne $hardToClient -and [System.IO.File]::Exists($hardToClient)) { Check (Test-Refused $h $hardToClient $sameAsLink -Force) "and a hard link to the client file is refused through that entry too" }
}
# AN IDENTITY THAT CANNOT BE READ: the null device opens and has none, and a share this machine does
# not have does not open. Each refuses every share, -Force or not, and names the relay.
$noShare = "\\localhost\horde-no-such-share-" + [guid]::NewGuid().ToString("N") + "\client.json"
foreach ($unread in @("\\.\NUL", $noShare)) {
    $short = $unread.Substring(0, [Math]::Min(26, $unread.Length)) + "..."
    $unreadIs = Get-HordeFilesPathIdentity -Path $unread
    Check ($unreadIs.state -ceq "unknown") ("CONTROL: which file " + $short + " is cannot be read (" + $unreadIs.state + ")")
    $script:entriesA = @([pscustomobject]@{ path = $unread; what = "the sign-in client file" })
    Check (Test-Refused $h $besideClient ("which file what the relay 'test-relay-a' calls the sign-in client file") -Force) ("UNREADABLE: an entry named as " + $short + " refuses even an ordinary file, -Force or not")
    Check (Test-Refused $h $besideClient "-Force does not change that" -Force) "and says -Force does not lift it"
}
# NOTHING THERE: a device path to a file that is not there yet refuses nothing, as a local one does.
$script:entriesA = @([pscustomobject]@{ path = ("\\.\" + $neverFile); what = "the sign-in client file" })
Check ((Get-HordeFilesPathIdentity -Path ("\\.\" + $neverFile)).state -ceq "absent") "CONTROL: the device path of a file not there yet is absent"
Check (Test-Shared $h $besideClient) "NOTHING THERE: an entry naming a file not there yet, by its device path, refuses nothing"
# ANOTHER VOLUME: the named-pipe file system is a volume of its own, readable, whose serial number no
# drive's file has - the shape of a file on a real network share, which this suite may not reach.
$otherVolume = "\\.\pipe\"
$otherIs = Get-HordeFilesPathIdentity -Path $otherVolume
Check ($otherIs.state -ceq "ok" -and $otherIs.id.Split(":")[0] -cne $clientIs.id.Split(":")[0]) ("CONTROL: " + $otherVolume + " is readable and on another volume (" + $otherIs.state + " " + $otherIs.id + ")")
# Named by its own device name, pipe is no name of the allow-list (round 4 of the review of PR 238):
# which machine it is cannot be told, so it refuses every share. The same volume reached through a
# share of this machine, below, is opened and blocks nothing.
$script:entriesA = @([pscustomobject]@{ path = $otherVolume; what = "the sign-in client file" })
Check (Test-Refused $h $besideClient "which file what the relay 'test-relay-a' calls the sign-in client file" -Force) "A DEVICE NAME OFF THE ALLOW-LIST: an entry named \\.\pipe\ refuses even an ordinary file, -Force or not"
# ONLY A PATH TO THIS MACHINE IS OPENED, DECIDED BY ADDRESS (round 3 of the review of PR 238,
# 2026-10-14; files/Deny.ps1's header). NO NAME IS RESOLVED AND NOTHING ON THE NETWORK IS OPENED
# HERE: the three questions the rule asks are answered by this suite, each called exactly as the
# real one is - which addresses a host resolves to (a table; a name not in it resolves to none),
# which addresses this machine's interfaces have (made-up ones from the documentation ranges), and
# which file a path is (a path under a share of the table is asked as the real folder it stands
# for; every path asked is counted, and anything else is answered "absent" without being opened).
# The drive letters are the suite's own table, as above: no letter is made.
#   horde-self-name   192.0.2.10, this machine's made-up IPv4     horde-remote   203.0.113.7
#   horde-self-six    2001:db8::10, its made-up IPv6              horde-mixed    203.0.113.8 and 127.0.0.1
#   horde-gone        resolves to nothing                        localhost      ::1 and 127.0.0.1, as measured
$realOwn = @(Get-HordeFilesOwnAddresses)
Check ($realOwn -ccontains "127.0.0.1" -and $realOwn -ccontains "::1") ("CONTROL: the real reader of this machine's addresses finds the loopback ones (" + $realOwn.Count + " addresses)")
$script:realResolve = ${function:Get-HordeFilesHostAddresses}
$script:realOwnAddresses = ${function:Get-HordeFilesOwnAddresses}
$script:realOpen = ${function:Get-HordeFilesPathIdentity}
$script:realLetterTarget3 = ${function:Get-HordeDriveLetterTarget}
$script:realDriveType3 = ${function:Get-HordeDriveLetterType}
$script:resolves = @{ "horde-self-name" = @("192.0.2.10"); "horde-self-six" = @("2001:db8::10"); "horde-remote" = @("203.0.113.7"); "horde-mixed" = @("203.0.113.8", "127.0.0.1"); "localhost" = @("::1", "127.0.0.1") }
$script:resolved = New-Object System.Collections.ArrayList
$script:opened = New-Object System.Collections.ArrayList
$script:openAs = @{}
$script:stands3 = @{ "V" = "\Device\LanmanRedirector\;V:0000000000012345\horde-self-name\share"; "W" = "\Device\LanmanRedirector\;W:0000000000012345\horde-remote\share"
    "U" = "\??\UNC\horde-self-name\share"; "Y" = "\??\V:\"; "Q" = "\Device\SomeRedirector"; "J" = "\??\K:"; "K" = "\??\J:"; "Z" = "\??\W:\" }
$script:types3 = @{ "V" = "Network"; "W" = "Network"; "U" = "Network"; "Y" = "NoRootDirectory"; "Q" = "Network"; "J" = "NoRootDirectory"; "K" = "NoRootDirectory"; "Z" = "NoRootDirectory" }
function Get-HordeFilesHostAddresses {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Name)
    [void]$script:resolved.Add($Name)
    $key = ConvertTo-HordeAsciiLower -Text $Name
    if ($script:resolves.ContainsKey($key)) { return @($script:resolves[$key]) }
    return @()
}
function Get-HordeFilesOwnAddresses { return @("192.0.2.10", "2001:db8::10", "fe80::10%7") }
$script:madeUpOwn = ${function:Get-HordeFilesOwnAddresses}
function Get-HordeFilesPathIdentity {
    param([Parameter(Mandatory = $true)][string]$Path)
    [void]$script:opened.Add($Path)
    foreach ($prefix in $script:openAs.Keys) {
        if (-not $Path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($script:openAs[$prefix] -ceq "unreadable") { return [pscustomobject]@{ state = "unknown"; id = "" } }
        return (& $script:realOpen -Path ($script:openAs[$prefix] + $Path.Substring($prefix.Length)))
    }
    # Anything else on the network, or on a letter of the table, is answered without being opened.
    if ($Path -cmatch '\A(?:[\\/]{2}|\\\?\?\\)' -and $Path -cnotmatch '\A\\\\\?\\[A-Za-z]:\\') { return [pscustomobject]@{ state = "absent"; id = "" } }
    if ($Path -cmatch '\A([A-Za-z]):' -and $script:stands3.ContainsKey($Matches[1].ToUpperInvariant())) { return [pscustomobject]@{ state = "absent"; id = "" } }
    return (& $script:realOpen -Path $Path)
}
function Get-HordeDriveLetterTarget {
    param([Parameter(Mandatory = $true)][string]$Letter)
    if ($script:stands3.ContainsKey($Letter.ToUpperInvariant())) { return ("" + $script:stands3[$Letter.ToUpperInvariant()]) }
    return (& $script:realLetterTarget3 -Letter $Letter)
}
function Get-HordeDriveLetterType {
    param([Parameter(Mandatory = $true)][string]$Letter)
    if ($script:types3.ContainsKey($Letter.ToUpperInvariant())) { return ("" + $script:types3[$Letter.ToUpperInvariant()]) }
    return (& $script:realDriveType3 -Letter $Letter)
}
$selfSeen = @{}
$elseSeen = @{}
$untoldSeen = @{}
$byReach = @{}
try {
    # Each share root of the table, and each letter, stands for the relay's real folder when opened.
    foreach ($root in @("\\horde-self-name\share\", "\\horde-self-six\share\", "\\horde-mixed\share\", "\\192.0.2.10\share\", "\\2001-db8--10.ipv6-literal.net\share\", "\\0.0.0.0\share\", "\\fe80--10s3.ipv6-literal.net\share\",
        "\\horde-self-name@SSL@443\share\", "\\horde-self-name.\share\", "\\?\UNC\horde-self-six\share\", "\\HORDE-SELF-NAME\share\", "V:\", "U:\", "Y:\", "\\horde-remote\share\", "\\horde-gone\share\", "\\203.0.113.7\share\", "W:\", "Z:\", "\\?\UNC\horde-remote\share\", "\\--ffff-c000-20a.ipv6-literal.net\share\")) { $script:openAs[$root] = $relayDir + "\" }
    $script:openAs["\\horde-self-name\down\"] = "unreadable"
    $script:openAs["\\horde-self-name\pipes\"] = $otherVolume
    $selfForms = [ordered]@{ "own name (its NIC IPv4)" = "\\horde-self-name\share\"; "own name in capitals" = "\\HORDE-SELF-NAME\share\"; "own name with a trailing dot" = "\\horde-self-name.\share\"
        "own name as a web share (@SSL@443)" = "\\horde-self-name@SSL@443\share\"; "a name resolving to its NIC IPv6" = "\\horde-self-six\share\"; "the long UNC form of that name" = "\\?\UNC\horde-self-six\share\"
        "a name of which one address of two is loopback" = "\\horde-mixed\share\"; "its NIC IPv4 written as an address" = "\\192.0.2.10\share\"; "its NIC IPv4 carried in IPv6" = "\\--ffff-c000-20a.ipv6-literal.net\share\"
        "its NIC IPv6 in the ipv6-literal.net form" = "\\2001-db8--10.ipv6-literal.net\share\"; "its link-local address in another zone" = "\\fe80--10s3.ipv6-literal.net\share\"
        "the unspecified address" = "\\0.0.0.0\share\"; "a mapped drive letter whose host is this machine" = "V:\"; "a letter defined over a share of this machine" = "U:\"; "a letter that stands for that mapped letter" = "Y:\" }
    foreach ($form in $selfForms.Keys) {
        $script:entriesA = @([pscustomobject]@{ path = ($selfForms[$form] + "innocent-name.json"); what = "the sign-in client file" })
        $script:opened.Clear()
        $refused = Test-Refused $h $clientFile $sameAsLink -Force
        $wasOpened = @($script:opened | Where-Object { $_.StartsWith($selfForms[$form], [System.StringComparison]::OrdinalIgnoreCase) }).Count -ge 1
        $selfSeen[$form] = ($refused -and $wasOpened -and (Test-Shared $h $besideClient -Force))
    }
    foreach ($form in @("\\localhost\", "\\127.0.0.1\", "\\0--1.ipv6-literal.net\", "\\0-0-0-0-0-0-0-1.ipv6-literal.net\", ("\\" + [System.Environment]::MachineName.ToLowerInvariant() + "\"))) {
        $byReach[$form] = Get-HordeFilesHostReach -HostName ($form.Trim('\'))
    }
    Set-Item -Path function:Get-HordeFilesOwnAddresses -Value $script:realOwnAddresses
    try { $byReach.realOwnName = Get-HordeFilesHostReach -HostName "192.0.2.10" } finally { Set-Item -Path function:Get-HordeFilesOwnAddresses -Value $script:madeUpOwn }
    $elseForms = [ordered]@{ "a host that resolves to another machine" = "\\horde-remote\share\"; "another machine written as an address" = "\\203.0.113.7\share\"; "a host that resolves to nothing" = "\\horde-gone\share\"; "a mapped drive letter whose host is another machine" = "W:\"
        "the long UNC form of another machine" = "\\?\UNC\horde-remote\share\"; "a letter that stands for that letter" = "Z:\" }
    foreach ($form in $elseForms.Keys) {
        $script:entriesA = @([pscustomobject]@{ path = ($elseForms[$form] + "innocent-name.json"); what = "the sign-in client file" })
        $script:opened.Clear()
        $elseSeen[$form] = ((Test-Shared $h $clientFile -Force) -and (Test-Shared $h $besideClient) -and @($script:opened | Where-Object { $_.StartsWith($elseForms[$form], [System.StringComparison]::OrdinalIgnoreCase) }).Count -eq 0)
    }
    # ANOTHER VOLUME: a share of this machine that is the named-pipe volume is opened, and is
    # another file than every file of the drives.
    $script:entriesA = @([pscustomobject]@{ path = "\\horde-self-name\pipes\"; what = "the sign-in client file" })
    $script:opened.Clear()
    $otherVolumeShared = ((Test-Shared $h $besideClient) -and (Test-Shared $h $clientFile -Force))
    $otherVolumeOpened = @($script:opened | Where-Object { $_ -like "\\horde-self-name\pipes\*" }).Count
    # Round 4 of the review of PR 238: every device name off the allow-list, Global's UNC to another
    # machine above all, refuses every share and is never opened.
    $untoldForms = [ordered]@{ "this machine with its identity unreadable" = "\\horde-self-name\down\"; "a network drive whose entry shows no host" = "Q:\"; "a ring of letters" = "J:\"; "a device path through GLOBALROOT" = "\\?\GLOBALROOT\Device\Mup\horde-remote\share\"
        "Global's UNC to another machine, \\.\" = "\\.\Global\UNC\horde-remote\share\"; "Global's UNC to another machine, \\?\" = "\\?\Global\UNC\horde-remote\share\"; "Global's UNC to another machine, \??\" = "\??\GLOBAL\UNC\horde-remote\share\"
        "Global over a drive letter" = "\\.\Global\C:\"; "a device name someone defined" = "\\.\horde-device\share\"; "a device name like a volume's, but no GUID" = "\\?\Volume{horde}\" }
    foreach ($form in $untoldForms.Keys) {
        $script:entriesA = @([pscustomobject]@{ path = ($untoldForms[$form] + "innocent-name.json"); what = "the sign-in client file" })
        $script:opened.Clear()
        # The relay port hands no \??\ path over as a file (measured round 4): that one is refused a
        # step earlier, as a relay that could not tell, and never reaches the device names.
        $refusedFor = $(if ($untoldForms[$form].StartsWith("\??\")) { "the relay 'test-relay-a' could not tell" } else { "which file what the relay 'test-relay-a' calls the sign-in client file" })
        $refusedAll = Test-Refused $h $besideClient $refusedFor -Force
        $untoldSeen[$form] = ($refusedAll -and ($form -like "this machine*" -or @($script:opened | Where-Object { $_ -like ($untoldForms[$form] + "*") }).Count -eq 0))
    }
    $resolvedNames = @($script:resolved | Select-Object -Unique)
} finally {
    Set-Item -Path function:Get-HordeFilesHostAddresses -Value $script:realResolve
    Set-Item -Path function:Get-HordeFilesOwnAddresses -Value $script:realOwnAddresses
    Set-Item -Path function:Get-HordeFilesPathIdentity -Value $script:realOpen
    Set-Item -Path function:Get-HordeDriveLetterTarget -Value $script:realLetterTarget3
    Set-Item -Path function:Get-HordeDriveLetterType -Value $script:realDriveType3
}
foreach ($form in $selfSeen.Keys) { Check $selfSeen[$form] ("THIS MACHINE, BY ADDRESS: an entry named by " + $form + " is opened, and the same file is refused with -Force, while an ordinary file is shared") }
foreach ($form in @("\\localhost\", "\\127.0.0.1\", "\\0--1.ipv6-literal.net\", "\\0-0-0-0-0-0-0-1.ipv6-literal.net\")) { Check ($byReach[$form] -ceq "self") ("a loopback host, " + $form + ", is this machine (" + $byReach[$form] + ")") }
Check ($byReach[("\\" + [System.Environment]::MachineName.ToLowerInvariant() + "\")] -ceq "unresolved") "CONTROL: a NAME alone makes nothing this machine - this machine's own name, which the table here does not resolve, is not taken for it by its letters"
Check ($byReach.realOwnName -ceq "other") "CONTROL: the made-up NIC address is this machine only by the made-up interfaces: the real reader does not have it"
foreach ($form in $elseSeen.Keys) { Check $elseSeen[$form] ("ANOTHER MACHINE, OR NONE: an entry named by " + $form + " is NEVER OPENED and blocks nothing, not even the very file with -Force") }
Check ($otherVolumeShared -and $otherVolumeOpened -ge 1) ("ANOTHER VOLUME: an entry that is a share of this machine on another volume is opened (" + $otherVolumeOpened + " calls), and blocks neither an ordinary file nor the file it would have been")
foreach ($form in $untoldSeen.Keys) { Check $untoldSeen[$form] ("CANNOT BE TOLD: an entry named by " + $form + " refuses every share, -Force or not, and is not opened unless it is this machine") }
# F's ruling on round 4: NOTHING IS OPENED BY DEFAULT. A rooted or a relative path is neither a device,
# a host nor a letter; the relay port makes such an entry local before it gets here, so the function is
# asked directly, the one place that would have said "open".
foreach ($form in @("\horde-rooted\share\innocent-name.json", "horde-relative\share\innocent-name.json", "/horde-rooted/share/innocent-name.json")) { $r = Get-HordeFilesRelayEntryReach -Path $form; Check ($r -ceq "untold") ("NOTHING OPENED BY DEFAULT: an entry " + $form + " that is no device, host or letter is untold, so every share is refused (" + $r + ")") }
Check ((Get-HordeFilesRelayEntryReach -Path "\\?\Volume{00000000-0000-0000-0000-000000000000}\x.json") -ceq "open") "CONTROL: a volume by its GUID, on the allow-list, is still opened"
Check (($resolvedNames -ccontains "horde-self-name") -and -not ($resolvedNames -ccontains "203.0.113.7") -and -not ($resolvedNames -ccontains "2001:db8::10") -and -not ($resolvedNames -ccontains "0.0.0.0")) ("a name is resolved, and an address written as one is not (asked: " + ($resolvedNames -join ",") + ")")
Check (($resolvedNames -ccontains "horde-self-name") -and -not ($resolvedNames | Where-Object { $_ -like "*@*" -or $_.EndsWith(".") })) "a host is resolved cut at its @ and without its trailing dot"
Check ((Get-HordeFilesHostAddresses -Name "203.0.113.7") -ccontains "203.0.113.7") "CONTROL: the real resolver is back, and answers an address with itself, which sends no query"
$script:entriesA = @([pscustomobject]@{ path = $movedClient; what = "the sign-in client file" })
Check (Test-Refused $h $movedClient $saysRelay -Force) "THE GAP ABOVE, CLOSED BY THE RELAY: the moved client file whose content says nothing is refused once its relay names it, -Force or not"
$script:entriesA = @([pscustomobject]@{ path = $neverFile; what = "the sign-in client file" })
Check (Test-Shared $h $besideClient) "CONTROL: a relay may name a file that is not there yet, and an ordinary file beside it is shared"
# TWO RELAYS, ONE OF WHICH NAMES NOTHING, and a relay that keeps no secret file: the files of the one
# that does are still refused, by its name.
$script:entriesA = @([pscustomobject]@{ path = $clientFile; what = "the sign-in client file" })
Set-TestRelays @(@{ name = "test-relay-a"; block = $script:relayKnownA }, @{ name = "test-relay-b"; block = { param($h) New-HordeKnown -Value ([pscustomobject]@{ files = @() }) } }, @{ name = "test-relay-quiet"; block = $null })
Check (Test-Refused $h $clientFile $saysRelay) "with two relays asked and a third that keeps none, the file one of them names is refused"
Check (Test-Shared $h $besideClient) "CONTROL: and an ordinary file is shared"
Write-Host ""
Write-Host "--- known with none, unknown, and nobody asked ---" -ForegroundColor Cyan
Set-OrdinaryRelays
Check (Test-Shared $h $clientFile) "KNOWN, NO FILE NAMED, A RELAY ASKED: the ordinary answer, and the same file is shared"
# THE RELAYS ARE ASKED OF THE HOME THE SHARE IS GIVEN, not of the user's own: a relay's settings
# live in a home, and a share made for one home must not be judged by another's.
$script:askedHome = $h
Set-TestRelays @(@{ name = "test-relay-a"; block = { param($given) if ($given -ceq $script:askedHome) { New-HordeKnown -Value ([pscustomobject]@{ files = @() }) } else { New-HordeUnknown -Reason "asked of another home" } } })
Check (Test-Shared $h $besideClient) "a relay is asked of the very home the share was given (one that answers only for that home lets the share through)"
Set-OrdinaryRelays
$unknownSays = "which files hold the relays' secrets is not known: the relay 'test-relay-a' could not tell"
Set-TestRelays @(@{ name = "test-relay-a"; block = { param($h) New-HordeUnknown -Reason "its made-up settings do not read" } }, @{ name = "test-relay-b"; block = { param($h) New-HordeKnown -Value ([pscustomobject]@{ files = @() }) } })
Check (Test-Refused $h $besideClient ($unknownSays + ", so whether*" + $never)) "UNKNOWN: an ordinary file is refused, the reason naming the relay that could not tell, and never shared"
Check (Test-Refused $h $besideClient $unknownSays -Force) "and -Force does not lift it"
Check (Test-Refused $h $besideClient $unknownSays "made-up settings") "and the reason does NOT repeat what the relay said (the review of PR 238): a relay may say anything"
Set-TestRelays @(@{ name = "test-relay-a"; block = { param($h) throw "made up exception text 7731" } })
Check (Test-Refused $h $besideClient $unknownSays "7731" -Force) "a relay that throws is one that could not tell: refused, -Force or not, and its exception's text is not in the reason"
Set-TestRelays @(@{ name = "test-relay-a"; block = { param($h) New-HordeKnown -Value ([pscustomobject]@{ files = @([pscustomobject]@{ path = "relative\file.json"; what = "the sign-in client file" }) }) } })
Check (Test-Refused $h $besideClient $unknownSays) "a relay that names a file by a path that is not absolute is one that could not tell"
$nobody = "no relay was asked, so the relays were not loaded"
Set-TestRelays @()
Check (Test-Refused $h $besideClient ($nobody + "*" + $never)) "NOBODY ASKED, no relay loaded at all: an ordinary file is refused, and never shared"
Check (Test-Refused $h $besideClient $nobody -Force) "and -Force does not lift it"
Set-TestRelays @(@{ name = "test-relay-quiet"; block = $null })
Check (Test-Refused $h $besideClient $nobody -Force) "NOBODY ASKED, with a relay loaded that keeps no secret file: the same refusal, -Force or not"
$placesNow = Get-HordeFilesDenyPlaces -HordeHome $h -RepoRoot $repo
Check ($placesNow.unknownRelays -like ("*" + $nobody + "*") -and @($placesNow.places | Where-Object { $_.kind -ceq "relay" }).Count -eq 0) "and the places say why, with no relay place among them"
Set-OrdinaryRelays
Check (Test-Shared $h $besideClient) "CONTROL: with the ordinary answer back, the same file is shared again"

Set-Location -LiteralPath $env:TEMP
[System.IO.Directory]::SetCurrentDirectory($env:TEMP)
if ((Split-Path -Leaf $script:work) -match '\Ahorde-files-deny-test-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) {
    # Every link first, by its own entry, so that removing the folder never follows one.
    foreach ($entry in @(Get-ChildItem -LiteralPath (Join-Path $script:work "links") -Force -ErrorAction SilentlyContinue)) {
        if (Test-Link $entry.FullName) { if ($entry.PSIsContainer) { [System.IO.Directory]::Delete($entry.FullName) } else { [System.IO.File]::Delete($entry.FullName) } }
    }
    # A key file is its user's alone and may refuse a plain removal: its list is reset first.
    foreach ($keyFile in @(Get-ChildItem -LiteralPath $script:work -Recurse -Force -Filter "files-id.key" -ErrorAction SilentlyContinue)) { $null = & icacls.exe $keyFile.FullName /reset /q }
    Remove-Item -LiteralPath $script:work -Recurse -Force
}
Check (-not (Test-Path -LiteralPath $script:work)) "the suite's temp folder is removed"

Complete-HordeSuite -Success "a share refuses the places and the names secrets are kept under by the open handle's own path, -Force lifts what it may and never the Horde home, .horde-secrets, .ssh or a private key in a text, a variable the caller sets moves no place away, and a drive letter that stands for a network drive is refused before its host is looked up"
