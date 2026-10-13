# DOES A SHARE REFUSE THE PLACES AND THE NAMES SECRETS ARE KEPT UNDER, HOWEVER THE FILE IS REACHED?
#
# files/Deny.ps1, and the two questions files/Path.ps1 asks for it, in this process. The suite ATTACKS
# the list rather than reading it back:
#   - every word of the list at the start, in the middle and at the end of a name, in mixed case and
#     with a double extension - and, on the other side, every ordinary word that holds "key";
#   - every place from both sides of its edge: a file in it, a file in a folder whose name only
#     begins like it, a file beside it;
#   - a file in a place reached by a link to the file, a link to its folder, a junction, a subst
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
[System.IO.File]::WriteAllText((Join-Path $repo "agents\harness-x\stores.json"), '{ "schemaVersion": 1, "roots": [ { "profile": ".harness-x" }, { "env": "HORDE_TEST_HARNESS_X_HOME" } ] }')
[System.IO.File]::WriteAllText((Join-Path $repo "agents\harness-y\stores.json"), '{ "schemaVersion": 1, "roots": [ { "profile": ".harness-y" }, { "env": "HORDE_TEST_HARNESS_Y_HOME" } ] }')
$script:n = 0
$sess = New-HordeKnown -Value "deny-session"

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
    if (-not $ok) { Write-Host ("         got: " + $r.outcome + " - " + $r.reason) -ForegroundColor Red }
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
if (-not ([System.Management.Automation.PSTypeName]"HordeTest.DenyDos").Type) {
    Add-Type -Namespace HordeTest -Name DenyDos -MemberDefinition '[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern bool DefineDosDevice(int dwFlags, string lpDeviceName, string lpTargetPath); [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern int QueryDosDevice(string lpDeviceName, System.Text.StringBuilder lpTargetPath, int ucchMax);'
}
function Get-Target { param([string]$Letter) $text = New-Object System.Text.StringBuilder 1024; if ([HordeTest.DenyDos]::QueryDosDevice($Letter + ":", $text, 1024) -le 0) { return "" }; return $text.ToString() }
function Remove-Letter { param([string]$Letter) $was = Get-Target $Letter; if ($was -ne "") { $null = [HordeTest.DenyDos]::DefineDosDevice(7, $Letter + ":", $was) } }
function Get-FreeLetters {
    # Drive letters that name nothing: no drive, no device, and no PowerShell drive.
    return @("RSTUVWQPONMLKJ".ToCharArray() | ForEach-Object { "" + $_ } | Where-Object { (Get-Target $_) -eq "" -and -not [System.IO.Directory]::Exists($_ + ":\") -and $null -eq (Get-PSDrive -Name $_ -ErrorAction SilentlyContinue) })
}
function New-NoHost { return ("horde-" + [guid]::NewGuid().ToString("N").Substring(0, 10)) }
function Get-LookedUp { return ((& ipconfig.exe /displaydns) -join "`n") }

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
Check ($anywhereWords -ceq "credential,secret,token,key,password,passwd,.env") ("the words looked for anywhere in a name are the six first asked for, and passwd (" + $anywhereWords + ")")
Check ($wholeWords -ceq "auth,oauth,cred,private,wallet,cookie,recovery,env,service-account,id_rsa,id_dsa,id_ecdsa,id_ed25519,pem,pfx,p12,ppk,kdbx,jks,netrc,npmrc,pypirc,tfstate") ("the short words, looked for only as whole words, are these (" + $wholeWords + ")")
Check (@($list.words | Where-Object { $_.how -cne "anywhere" -and $_.how -cne "word" }).Count -eq 0 -and @($list.words).Count -eq 30) "every word says which of the two ways it is looked for, and there are 30"
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
Check ($found.unknown -eq "" -and $found.unknownNever -eq "" -and $kinds -ceq "home:False,home:False,secrets:False,ssh:False,home:False,secrets:False,ssh:False,agent:True,agent:True,agent:True,agent:True,agent:True") ("the places: the home that was named; then under the profile the variable names and again under the one the system names, .horde, .horde-secrets and .ssh, which -Force never lifts; then each harness's folders, which it does, each named once (" + $kinds + ")")
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
    "token" = @("token.txt", "my-token-list.md", "access_token", "TOKENS.json", "refreshToken.json", "tokenizer.md")
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
# A SHORT WORD INSIDE A LONGER ONE IS NOT THE WORD: the five names the review said must pass, and
# for every short word a name that only holds its letters.
$holdTheLetters = @("author-notes.md", "template.html", "credits.md", "privateer.txt", "cookiecutter.md",
    "authentication-design.html", "authorization-matrix.md", "unauthorized.md", "oauthenticity.md", "incredible.md", "credo.txt", "privately.md", "walletless.md", "cookiebar.png",
    "recoveryless.md", "envelope.md", "environment-setup.md", "serviceaccounting.md", "pemmican.md", "tempemail.md", "ppkg.md", "jksdf.md", "netrcx.md")
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
Check ($refusedOrdinary -eq 11) ("and 11 of the 64 are refused, each of which -Force shares (" + $refusedOrdinary + ")")
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
Check (Test-Refused $h $elsewhere $inSecrets -Force) "a folder named .horde-secrets anywhere on the way to the file, in any case of its letters, is refused the same, -Force or not"
Check (Test-Refused $h (New-File (Join-Path $script:real "a-copy\plain-folder\.horde-secrets")) "is not one that is shared" -NotLike "is under a .horde-secrets folder" -Force) "a FILE named .horde-secrets in an ordinary folder is not a folder on the way: it is refused for its type, not as that folder"
Check (Test-Shared $h (New-File (Join-Path $script:real "a-copy\.horde-secrets-old\client.md"))) "CONTROL: a folder whose name only begins with .horde-secrets is not that folder"
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
# A FOLDER NAMED .horde ANYWHERE on the way to the file, as .horde-secrets is.
$inNamedHome = "is under a .horde folder"
Check (Test-Refused $h (New-File (Join-Path $script:real "a-copy\.Horde\deep\notes.md")) $inNamedHome -Force) "a folder named .horde anywhere on the way to the file, in any case of its letters, is refused, -Force or not"
Check (Test-Refused $h (New-File (Join-Path $script:real "a-copy\.horde\notes.md")) $never -Force) "and the reason says -Force does not change that"
Check (Test-Shared $h (New-File (Join-Path $script:real "a-copy\.horde-old\notes.md"))) "CONTROL: a folder whose name only begins with .horde is not that folder"
Check (Test-Shared $h (New-File (Join-Path $script:real "a-copy\horde\notes.md"))) "CONTROL: nor is a folder named horde, with no dot"
Check (Test-Shared $h (New-File (Join-Path $script:real "a-copy\plain\.horde.md"))) "CONTROL: and a FILE whose name begins so is a file, not a folder on the way"

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
# A subst drive over the denied folder: the path that is written names no folder at all.
$letters = @(Get-FreeLetters)
$substLetter = $letters[0]
$bySubst = $false; $bySubstHome = $false; $substMade = $false
$null = & subst.exe ($substLetter + ":") $sshFolder
try {
    $substMade = ($LASTEXITCODE -eq 0 -and [System.IO.File]::Exists($substLetter + ":\notes.txt"))
    $bySubst = Test-Refused $h ($substLetter + ":\notes.txt") $inSsh
} finally { $null = & subst.exe ($substLetter + ":") /D }
$null = & subst.exe ($substLetter + ":") (Join-Path $h "settings")
try { $bySubstHome = Test-Refused $h ($substLetter + ":\notes.json") $inHome -Force } finally { $null = & subst.exe ($substLetter + ":") /D }
Check $substMade ("CONTROL: subst made " + $substLetter + ": over .ssh (if this fails, the subst form was NOT tested)")
Check $bySubst "by a subst drive over .ssh, where the written path names no folder, the file is refused as .ssh"
Check $bySubstHome "and by a subst drive over a folder of the home, as the home, -Force or not"
Check ((Get-Target $substLetter) -eq "") "the subst drive is gone again"
$sshCopy = Join-Path $docs "a-copy-of-the-ssh-notes.txt"
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
Set-Item -Path function:Get-HordeFilesFolderFinalPath -Value $script:realFolderFinal
Check $unasked "when Windows will not say where the home really is, an ordinary file is refused, -Force or not: it cannot be told that it is not in it"
Check $unaskedWhy "and the reason names which place could not be asked"
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
$letters = @(Get-FreeLetters)
Check ($letters.Count -ge 3) ("CONTROL: three drive letters that name nothing were found (" + $letters.Count + ")")
Check ((Get-HordeDriveLetterTarget -Letter $letters[0]) -eq "") "a letter that names nothing stands for nothing"
Check ((Get-HordeDriveAliasRefusal -Path ($systemLetter + ":\x.md")) -eq "" -and (Get-HordeDriveAliasRefusal -Path ($letters[0] + ":\x.md")) -eq "") "an ordinary drive, and a letter that names nothing, are not this question's"
Check ((Get-HordeDriveAliasRefusal -Path "x.md") -eq "" -and (Get-HordeDriveAliasRefusal -Path "") -eq "" -and (Get-HordeDriveAliasRefusal -Path "\\server\share\x.md") -eq "") "nor is a path with no drive letter"
$overLocal = ""; $overLocalTarget = ""
$null = & subst.exe ($letters[0] + ":") $docs
try { $overLocalTarget = Get-HordeDriveLetterTarget -Letter $letters[0]; $overLocal = Get-HordeDriveAliasRefusal -Path ($letters[0] + ":\plain.md") } finally { $null = & subst.exe ($letters[0] + ":") /D }
Check ($overLocalTarget -ceq ("\??\" + $docs)) ("a subst drive stands for the folder it was made over (" + $overLocalTarget + ")")
Check ($overLocal -eq "") "a letter that stands for a folder of this machine's own drive is let by"

Write-Host ""
Write-Host "--- a drive letter that stands for a network drive is refused before anything looks the host up ---" -ForegroundColor Cyan
# THE INSTRUMENT is this machine's DNS cache (test/test-files-store.ps1 has its measurement): a host
# name nobody ever used is in it after anything asks the network about a path under it.
$seenHost = New-NoHost
$null = [System.IO.File]::Exists("\\" + $seenHost + "\share\x.md")
$cacheNow = Get-LookedUp
$canSee = ($cacheNow.Contains($seenHost) -and -not $cacheNow.Contains((New-NoHost)))
if ($canSee) { Check $true "CONTROL: the instrument can see a lookup: a host asked about is in the DNS cache, and a name nobody asked about is not" }
else { Write-Skip "WHETHER A HOST WAS LOOKED UP COULD NOT BE SEEN: this machine's DNS cache does not show a host that was just asked about. The refusals below are still checked by their reasons." }
$h = New-TestHome
$netLetter = $letters[0]; $overLetter = $letters[1]; $overOver = $letters[2]
$netHost = New-NoHost
$netTarget = "\??\UNC\" + $netHost + "\share"
$placeOnNet = $null; $placeOnAlias = $null; $psMade = $false; $resolvedOnly = $false; $made = $false; $overMade = ""; $said = ""; $viaShareChain = $false; $ownNet = "?"; $viaShareNet = $false; $saidPrefix = $false; $saidRelative = $false; $viaShare = $false; $seenAfter = $true; $chain = ""; $typeOver = ""; $controlSeen = $false
$null = [HordeTest.DenyDos]::DefineDosDevice(1, $netLetter + ":", $netTarget)
try {
    $made = ((New-Object System.IO.DriveInfo($netLetter)).DriveType -eq [System.IO.DriveType]::Network)
    $null = [HordeTest.DenyDos]::DefineDosDevice(0, $overLetter + ":", $netLetter + ":\")
    $overMade = Get-Target $overLetter
    $null = [HordeTest.DenyDos]::DefineDosDevice(0, $overOver + ":", $overLetter + ":\")
    $said = Get-HordeDriveAliasRefusal -Path ($overLetter + ":\x.md")
    $saidPrefix = ((Get-HordeDriveAliasRefusal -Path ("\\?\" + $overLetter + ":\x.md")) -like "*stands for a network drive*")
    $saidRelative = ((Get-HordeDriveAliasRefusal -Path ($overLetter + ":x.md")) -like "*stands for a network drive*")
    $chain = Get-HordeDriveAliasRefusal -Path ($overOver + ":\x.md")
    $viaShare = Test-Refused $h ($overLetter + ":\x.md") ("is on a drive (" + $overLetter + ":) that stands for a network drive (" + $netLetter + ":), and only a path on one of this machine's own drives is taken. A file is shared from one of this machine's own drives: name it by its local path, or copy it to a local folder")
    $viaShareChain = Test-Refused $h ($overOver.ToLowerInvariant() + ":\x.md") "that stands for a network drive"
    $ownNet = Get-HordeDriveAliasRefusal -Path ($netLetter + ":\x.md")
    $viaShareNet = Test-Refused $h ($netLetter + ":\x.md") ("is on a network drive (" + $netLetter + ":)")
    $placeOnNet = Resolve-HordeFilesDenyPlace -Path ($netLetter + ":\home")
    $placeOnAlias = Resolve-HordeFilesDenyPlace -Path ($overLetter + ":\home")
    $seenAfter = (Get-LookedUp).Contains($netHost)
    # THE CONTROL, and why the order is what it is: asked for its TYPE, the letter over the network
    # letter is not Network, and asking is what looks the host up.
    $typeOver = "" + (New-Object System.IO.DriveInfo($overLetter)).DriveType
    $controlSeen = (Get-LookedUp).Contains($netHost)
    # WHAT ONLY THE RESOLVED PATH SHOWS: a PowerShell drive over the letter that stands for the network
    # drive. Making the drive may itself ask the network, so this comes after the look at the cache.
    $psLetter = @(Get-FreeLetters)[0]
    $null = New-PSDrive -Name $psLetter -PSProvider FileSystem -Root ($overLetter + ":\") -Scope Script -ErrorAction SilentlyContinue
    if ($null -ne (Get-PSDrive -Name $psLetter -ErrorAction SilentlyContinue)) {
        $psMade = ($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($psLetter + ":\x.md") -ceq ($overLetter + ":\x.md"))
        $resolvedOnly = Test-Refused $h ($psLetter + ":\x.md") ("is on a drive (" + $overLetter + ":) that stands for a network drive")
        Remove-PSDrive -Name $psLetter -Scope Script
    }
} finally { Remove-Letter $overOver; Remove-Letter $overLetter; $null = [HordeTest.DenyDos]::DefineDosDevice(7, $netLetter + ":", $netTarget) }
Check ($made -and $overMade -ceq ("\??\" + $netLetter + ":\")) ("CONTROL: " + $netLetter + ": was aimed at a share and is a network drive, and " + $overLetter + ": stands for it (" + $overMade + "); if this fails, the case was NOT tested")
Check ($said -like ("'" + $overLetter + ":\x.md' is on a drive (" + $overLetter + ":) that stands for a network drive (" + $netLetter + ":), and only a path on one of this machine's own drives is taken")) "a letter that stands for a network drive is refused, and the reason names both letters"
Check $saidPrefix "and behind the long-path prefix"
Check $saidRelative "and named from wherever that drive stands"
Check ($chain -like ("*is on a drive (" + $overOver + ":) that stands for a network drive (" + $netLetter + ":)*")) "a letter that stands for a letter that stands for a network drive is refused too: the chain is followed to its end"
Check ($ownNet -eq "") "a network drive itself is not this question's: the network question refuses it"
Check $viaShare "through a share, it is refused with that reason, and the share adds its own sentence: what to do about it"
Check $viaShareChain "and so is the chain, with its letter in small"
Check $viaShareNet "CONTROL: a share from the network drive itself is still refused by the network question, with its own reason"
Check ($null -ne $placeOnNet -and -not $placeOnNet.unknown -and @($placeOnNet.paths).Count -eq 0) "a folder of the list that is on a network drive is never opened: it holds no file of this machine's drives"
Check ($null -ne $placeOnAlias -and -not $placeOnAlias.unknown -and @($placeOnAlias.paths).Count -eq 0) "nor is one on a letter that stands for a network drive"
if ($canSee) { Check (-not $seenAfter) "and through all of those the host was NOT looked up: the system's table of names was read, and nobody was asked" }
if ($canSee) { Check ($typeOver -cne "Network" -and $controlSeen) ("CONTROL: asked for its type, that letter answers " + $typeOver + ", not Network, and the host IS looked up - which is what the refusal came before") }
if ($psMade) { Check $resolvedOnly "a path that is on such a letter only once it is resolved (a PowerShell drive over it) is refused the same: the question is asked again of the resolved path" }
else { Write-Skip "A POWERSHELL DRIVE OVER THE LETTER COULD NOT BE MADE, so the question asked of the RESOLVED path was not tested here." }
Check ((Get-Target $netLetter) -eq "" -and (Get-Target $overLetter) -eq "" -and (Get-Target $overOver) -eq "") "all three drive letters are gone again"
# A RING: a letter that stands for itself by way of another never ends, and is refused.
$ring = ""
$null = [HordeTest.DenyDos]::DefineDosDevice(1, $letters[0] + ":", "\??\" + $letters[1] + ":")
$null = [HordeTest.DenyDos]::DefineDosDevice(1, $letters[1] + ":", "\??\" + $letters[0] + ":")
try { $ring = Get-HordeDriveAliasRefusal -Path ($letters[0] + ":\x.md") } finally { Remove-Letter $letters[0]; Remove-Letter $letters[1] }
Check ($ring -like "*stands for another drive letter, and that for another, without end*") "two letters that stand for each other are refused: where the file is cannot be told"
Check ((Get-Target $letters[0]) -eq "" -and (Get-Target $letters[1]) -eq "") "and both are gone again"
# Eight letters deep is followed; this chain of three ended at a folder of this machine's own drive.
$deep = "?"; $deepShared = $false
$null = & subst.exe ($letters[0] + ":") $docs
$null = [HordeTest.DenyDos]::DefineDosDevice(1, $letters[1] + ":", "\??\" + $letters[0] + ":")
$null = [HordeTest.DenyDos]::DefineDosDevice(1, $letters[2] + ":", "\??\" + $letters[1] + ":")
try { $deep = Get-HordeDriveAliasRefusal -Path ($letters[2] + ":\plain.md"); $deepShared = Test-Shared $h ($letters[2] + ":\plain.md") } finally { Remove-Letter $letters[2]; Remove-Letter $letters[1]; $null = & subst.exe ($letters[0] + ":") /D }
Check ($deep -eq "") "CONTROL: a chain of letters that ends at a folder of this machine's own drive is let by"
Check $deepShared "and a file named through it is shared"
Check ((Get-Target $letters[0]) -eq "" -and (Get-Target $letters[1]) -eq "" -and (Get-Target $letters[2]) -eq "") "and those letters are gone again"

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

Complete-HordeSuite -Success "a share refuses the places and the names secrets are kept under by the open handle's own path, -Force lifts what it may and never the Horde home or .horde-secrets, and a drive letter that stands for a network drive is refused before its host is looked up"
