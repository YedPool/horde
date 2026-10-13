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
# Whatever a function here is not handed, it must not find the real home.
$env:HORDE_HOME = Join-Path $script:real "home-nobody-uses"
$env:HORDE_TEST_HARNESS_X_HOME = Join-Path $script:real "harness-x-moved"
# TWO HARNESSES OF THIS SUITE'S OWN, described the way a real one describes itself.
$repo = Join-Path $script:real "repo"
New-Item -ItemType Directory -Path (Join-Path $repo "agents\harness-x") | Out-Null
New-Item -ItemType Directory -Path (Join-Path $repo "agents\harness-y") | Out-Null
[System.IO.File]::WriteAllText((Join-Path $repo "agents\harness-x\stores.json"), '{ "schemaVersion": 1, "roots": [ { "profile": ".harness-x" }, { "env": "HORDE_TEST_HARNESS_X_HOME" } ] }')
[System.IO.File]::WriteAllText((Join-Path $repo "agents\harness-y\stores.json"), '{ "schemaVersion": 1, "roots": [ { "profile": ".harness-y" } ] }')
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
Check ((@($list.words) -join ",") -ceq "credential,secret,token,key,password,.env") ("the words are the six that were asked for (" + (@($list.words) -join ",") + ")")
Check ($list.secretsFolder -ceq ".horde-secrets" -and $list.sshFolder -ceq ".ssh") "the two folders of the profile are .horde-secrets and .ssh"
Check (@($list.ordinary.Keys).Count -eq 1 -and @($list.ordinary["key"]).Count -eq 15) ("only 'key' has ordinary words taken out of a name first, and there are 15 of them (" + @($list.ordinary["key"]).Count + ")")
$h = New-TestHome
$found = Get-HordeFilesDenyPlaces -HordeHome $h -RepoRoot $repo
$kinds = (@($found.places | ForEach-Object { $_.kind + ":" + $_.force }) -join ",")
Check ($found.unknown -eq "" -and $kinds -ceq "home:False,secrets:False,ssh:True,agent:True,agent:True,agent:True") ("the places: the home and .horde-secrets, which -Force never lifts, then .ssh and each harness's folders, which it does (" + $kinds + ")")
$placePaths = @($found.places | ForEach-Object { $_.path })
Check ($placePaths -ccontains $h -and $placePaths -ccontains (Join-Path $profileDir ".horde-secrets") -and $placePaths -ccontains (Join-Path $profileDir ".ssh")) "the home is the one the caller named, and the two folders are in the user's profile"
Check ($placePaths -ccontains (Join-Path $profileDir ".harness-x") -and $placePaths -ccontains (Join-Path $profileDir ".harness-y") -and $placePaths -ccontains $env:HORDE_TEST_HARNESS_X_HOME) "each harness's folders are the ones its own stores.json declares: in the profile, and where its variable moves its store"
$realRepo = Get-HordeFilesDenyPlaces -HordeHome $h
$declared = @(Get-ChildItem -LiteralPath (Join-Path $root "agents") -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "stores.json") })
Check ($realRepo.unknown -eq "" -and $declared.Count -ge 1 -and @($realRepo.places | Where-Object { $_.kind -ceq "agent" }).Count -ge $declared.Count) ("with no folder named, the shipped harnesses are read: every one of the " + $declared.Count + " that declares its stores gives at least one folder")

Write-Host ""
Write-Host "--- a name: each word at the start, in the middle and at the end, in any case of A to Z ---" -ForegroundColor Cyan
$refusedNames = [ordered]@{
    "credential" = @("credentials.json", "my-credential-notes.md", "aws.credential", "CREDENTIALS.TXT", "GoogleCredentials.json")
    "secret" = @("secret.md", "top-secret-plan.md", "client_secret", "Secrets.json", "MySecretNotes.md", "secretary.txt")
    "token" = @("token.txt", "my-token-list.md", "access_token", "TOKENS.json", "refreshToken.json", "tokenizer.md")
    "key" = @("key.md", "api-key.txt", "id_rsa.key.txt", "keys.json", "KEY.MD", "mykey.txt", "keyed.md", "ApiKey.json", "private-key-notes.md", "x.key", "apikeys.txt", "key2.json", "monkey-api-key.txt", "keyboard.key.md", "turkeykey.md")
    "password" = @("password.txt", "my-passwords-old.md", "wifi_password", "PASSWORDS.md", "PassWord.txt", "passwordless.md")
    ".env" = @(".env", ".env.local", "prod.env", "prod.env.txt", ".ENV.json", ".envrc", "notes.environment.md")
}
foreach ($word in $refusedNames.Keys) {
    $missed = @($refusedNames[$word] | Where-Object { (Get-HordeFilesDenyWord -Name $_) -cne $word })
    Check ($missed.Count -eq 0) ("'" + $word + "' is found in all " + @($refusedNames[$word]).Count + " names that hold it: " + (@($refusedNames[$word]) -join ", ") + $(if ($missed.Count) { " (MISSED: " + ($missed -join ", ") + ")" } else { "" }))
}
$plainNames = @("report.md", "notes.txt", "chart.png", "a", "", "ke y.md", "k-e-y.md", "tok.en.md", "pass-word.md", "secre.t", "env.md", "x.en.v", "credentia.md", "passwor.d")
$caught = @($plainNames | Where-Object { (Get-HordeFilesDenyWord -Name $_) -cne "" })
Check ($caught.Count -eq 0) ("CONTROL: " + $plainNames.Count + " names that hold no word of the list, a word cut short and a word broken by a character among them, are let by" + $(if ($caught.Count) { " (CAUGHT: " + ($caught -join ", ") + ")" } else { "" }))
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
foreach ($named in @("api-key.txt", "Passwords.md", "my-token.json", "client_secret.txt", "credentials.md", "prod.env.txt")) {
    $text = "dummy words, and no secret"; if ($named -like "*.json") { $text = '{"dummy":1}' }
    $file = New-File (Join-Path $docs $named) $text
    $word = Get-HordeFilesDenyWord -Name $named
    Check (Test-Refused $h $file ("its name, '" + $named + "', holds '" + $word + "'")) ($named + " is refused, and the reason names the file and the word")
    Check (Test-Refused $h $file $insist) "and says that -Force shares it"
    Check (Test-Shared $h $file -Force) "with -Force it is shared"
}
Check (Test-Shared $h (New-File (Join-Path $docs "keyboard.md"))) "CONTROL: keyboard.md is shared with no -Force"
Check (Test-Shared $h (New-File (Join-Path $docs "monkey.txt"))) "CONTROL: and so is monkey.txt"
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
Check (Test-Refused $h $inSshFile $insist -NotLike "does not change") "and the reason says -Force shares it"
Check (Test-Shared $h $inSshFile -Force) "with -Force it is shared"
Check (Test-Refused $h (New-File (Join-Path $profileDir ".ssh\deep\er\notes.md")) $inSsh) "and so is a file deeper under it"
Check (Test-Shared $h (New-File (Join-Path $profileDir ".ssh-backup\notes.txt"))) "CONTROL: a folder whose name only begins with .ssh is shared from"
Check (Test-Shared $h (New-File (Join-Path $profileDir "notes-beside-ssh.txt"))) "CONTROL: and a file beside it, in the profile, is shared"
Check (Test-Shared $h (New-File (Join-Path $script:real "not-the-profile\.ssh\notes.txt"))) "CONTROL: a folder named .ssh that is not the profile's is shared from: that place is the user's own, not a name"
foreach ($agentFolder in @((Join-Path $profileDir ".harness-x"), (Join-Path $profileDir ".harness-y"), $env:HORDE_TEST_HARNESS_X_HOME)) {
    $inAgentFile = New-File (Join-Path $agentFolder "projects\notes.md")
    Check (Test-Refused $h $inAgentFile $inAgent) ("a file under a harness's own folder (" + (Split-Path -Leaf $agentFolder) + ") is refused as that")
    Check (Test-Refused $h $inAgentFile ("('" + $agentFolder + "')")) "and the reason names the folder, which is the harness's own data"
    Check (Test-Shared $h $inAgentFile -Force) "with -Force it is shared"
}
Check (Test-Shared $h (New-File (Join-Path $profileDir ".harness-xy\notes.md"))) "CONTROL: a folder whose name only begins with a harness's is shared from"
# WHAT -Force NEVER LIFTS IS JUDGED FIRST: a file in the home whose name holds a word is refused as the home.
Check (Test-Refused $h (New-File (Join-Path $h "settings\api-key.txt")) $inHome -NotLike "holds 'key'") "a file in the home with a word in its name is refused for the home, not for the name"
Check (Test-Refused $h (New-File (Join-Path $profileDir ".ssh\api-key.txt")) $inSsh -NotLike "holds 'key'") "and one in .ssh for .ssh"

Write-Host ""
Write-Host "--- a harness nobody described is not left open ---" -ForegroundColor Cyan
$repoGap = Join-Path $script:real "repo-with-a-gap"
New-Item -ItemType Directory -Path (Join-Path $repoGap "agents\harness-z") | Out-Null
$plainDoc = New-File (Join-Path $docs "plain.md")
Check (Test-Refused $h $plainDoc "which folders the agent harnesses keep their own files in is not known" -Repo $repoGap) "with a harness folder that declares no stores, an ordinary file is refused: where that harness keeps its files is not known"
Check (Test-Refused $h $plainDoc $insist -Repo $repoGap) "the reason says -Force shares it"
Check (Test-Shared $h $plainDoc -Force -Repo $repoGap) "and with -Force it is: the harness folders are what -Force lifts"
Check (Test-Refused $h $inSettings $inHome -Force -Repo $repoGap) "the home is still refused then, -Force or not"
Check (Test-Shared $h $plainDoc) "CONTROL: with every harness described, the same file is shared with no -Force"

Write-Host ""
Write-Host "--- every rule judges the open handle's own path: a place reached another way is still the place ---" -ForegroundColor Cyan
$h = New-TestHome
$null = Invoke-Share -TestHome $h -Path (New-File (Join-Path $docs "second.md"))
$sshDir = Join-Path $profileDir ".ssh"
$sshFile = Join-Path $sshDir "notes.txt"
$homeFile = New-File (Join-Path $h "settings\notes.json") '{"dummy":1}'
$links = Join-Path $script:real "links"
New-Item -ItemType Directory -Path $links | Out-Null
# A LINK OUTSIDE THE DENIED FOLDERS POINTING INTO ONE. The link test would refuse it too, as a link;
# refused AS THE PLACE shows the list read where the handle really is, not what was written.
Check (New-FileLink (Join-Path $links "innocent.txt") $sshFile) "CONTROL: a symbolic link outside .ssh was made to the file inside it"
Check (Test-Refused $h (Join-Path $links "innocent.txt") $inSsh -NotLike "is a link") "a link outside .ssh to a file inside it is refused as .ssh"
Check (Test-Refused $h (Join-Path $links "innocent.txt") "is a link" -Force) "and with -Force it is still not shared: the list is lifted, and a link is never followed"
Check (New-FileLink (Join-Path $links "innocent.json") $homeFile) "CONTROL: a symbolic link outside the home was made to a file inside it"
Check (Test-Refused $h (Join-Path $links "innocent.json") $inHome -Force) "a link outside the home to a file inside it is refused as the home, -Force or not"
Check (New-FolderLink (Join-Path $links "folder-link") $sshDir) "CONTROL: a symbolic link to the .ssh folder was made"
Check (Test-Refused $h (Join-Path $links "folder-link\notes.txt") $inSsh -NotLike "is a link") "through a symbolic link to the folder"
Check (New-Junction (Join-Path $links "junction") $sshDir) "CONTROL: a junction to the .ssh folder was made"
Check (Test-Refused $h (Join-Path $links "junction\notes.txt") $inSsh -NotLike "is a link") "through a junction to the folder"
Check (New-Junction (Join-Path $links "home-junction") $h) "CONTROL: a junction to the home was made"
Check (Test-Refused $h (Join-Path $links "home-junction\settings\notes.json") $inHome -Force) "through a junction to the home, -Force or not"
Check (Test-Refused $h ("\\?\" + $sshFile) $inSsh) "behind the long-path prefix"
Check (Test-Refused $h ("\\?\" + $homeFile) $inHome -Force) "and the home behind it, -Force or not"
Check (Test-Refused $h $sshFile.ToUpperInvariant() $inSsh) "written in capitals"
Check (Test-Refused $h $homeFile.ToUpperInvariant() $inHome -Force) "and the home in capitals, -Force or not"
Check (Test-Refused $h (Join-Path ($sshDir + ".") "notes.txt") $inSsh) "with a dot after the folder's name, which Windows drops"
# A blank after a FOLDER's name is not dropped (measured 2026-10-13): that path names no file, so it is no way in.
Check (Test-Refused $h (Join-Path ($sshDir + " ") "notes.txt") "there is no file") "with a blank after the folder's name the path names no file at all"
Check (Test-Refused $h (Join-Path $docs "..\profile\.ssh\notes.txt") $inSsh) "by a path that climbs out of another folder with dot-dot"
Push-Location -LiteralPath $docs
try { $relative = Test-Refused $h "..\profile\.ssh\notes.txt" $inSsh; $relativeHome = Test-Refused $h ("..\" + (Split-Path -Leaf $h) + "\settings\notes.json") $inHome -Force } finally { Pop-Location }
Check $relative "by a relative path with dot-dot, from where the caller stands"
Check $relativeHome "and the home by a relative path, -Force or not"
# An 8.3 short name, where this volume makes them. Behind the long-path prefix .NET changes nothing,
# so the handle really is opened by the short name (test/test-files-store.ps1 has the measurement).
$shortSsh = Get-ShortPath -Path $sshDir -Folder
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
$null = & subst.exe ($substLetter + ":") $sshDir
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
Check (Test-Shared $h $sshFile -Force) "CONTROL: after all those refusals the .ssh file is still one -Force shares, so they were the list's and not a broken file"
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
$asked = Get-HordeFilesFolderFinalPath -Path $sshDir
Check ($asked.state -ceq "ok" -and $asked.path -ceq ("\\?\" + $sshDir)) "the final path of a folder is its path behind \\?\"
$viaJunction = Get-HordeFilesFolderFinalPath -Path (Join-Path $links "junction")
Check ($viaJunction.state -ceq "ok" -and $viaJunction.path -ceq ("\\?\" + $sshDir)) "asked of a junction, it is the folder the junction leads to"
$viaLink = Get-HordeFilesFolderFinalPath -Path (Join-Path $links "folder-link")
Check ($viaLink.state -ceq "ok" -and $viaLink.path -ceq ("\\?\" + $sshDir)) "and of a symbolic link, the folder it leads to"
$notThere = Get-HordeFilesFolderFinalPath -Path (Join-Path $script:real "no-such-folder")
Check ($notThere.state -ceq "absent" -and $notThere.path -eq "") "a folder that is not there is absent"
$parentGone = Get-HordeFilesFolderFinalPath -Path (Join-Path $script:real "no-such-folder\nor-this")
Check ($parentGone.state -ceq "absent") "and so is one whose parent is not there"
$badName = Get-HordeFilesFolderFinalPath -Path "C:\a<b>|c"
Check ($badName.state -ceq "unknown") "a name Windows cannot open for another reason is unknown, never absent"
$systemLetter = $script:real.Substring(0, 1)
Check ((Get-HordeFilesDriveTarget -Letter $systemLetter) -like "\Device\*") ("the drive this suite is on stands for a volume (" + (Get-HordeFilesDriveTarget -Letter $systemLetter) + ")")
$letters = @(Get-FreeLetters)
Check ($letters.Count -ge 3) ("CONTROL: three drive letters that name nothing were found (" + $letters.Count + ")")
Check ((Get-HordeFilesDriveTarget -Letter $letters[0]) -eq "") "a letter that names nothing stands for nothing"
Check ((Get-HordeFilesAliasRefusal -Path ($systemLetter + ":\x.md")) -eq "" -and (Get-HordeFilesAliasRefusal -Path ($letters[0] + ":\x.md")) -eq "") "an ordinary drive, and a letter that names nothing, are not this question's"
Check ((Get-HordeFilesAliasRefusal -Path "x.md") -eq "" -and (Get-HordeFilesAliasRefusal -Path "") -eq "" -and (Get-HordeFilesAliasRefusal -Path "\\server\share\x.md") -eq "") "nor is a path with no drive letter"
$overLocal = ""; $overLocalTarget = ""
$null = & subst.exe ($letters[0] + ":") $docs
try { $overLocalTarget = Get-HordeFilesDriveTarget -Letter $letters[0]; $overLocal = Get-HordeFilesAliasRefusal -Path ($letters[0] + ":\plain.md") } finally { $null = & subst.exe ($letters[0] + ":") /D }
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
    $said = Get-HordeFilesAliasRefusal -Path ($overLetter + ":\x.md")
    $saidPrefix = ((Get-HordeFilesAliasRefusal -Path ("\\?\" + $overLetter + ":\x.md")) -like "*stands for a network drive*")
    $saidRelative = ((Get-HordeFilesAliasRefusal -Path ($overLetter + ":x.md")) -like "*stands for a network drive*")
    $chain = Get-HordeFilesAliasRefusal -Path ($overOver + ":\x.md")
    $viaShare = Test-Refused $h ($overLetter + ":\x.md") ("is on a drive (" + $overLetter + ":) that stands for a network drive (" + $netLetter + ":)")
    $viaShareChain = Test-Refused $h ($overOver.ToLowerInvariant() + ":\x.md") "that stands for a network drive"
    $ownNet = Get-HordeFilesAliasRefusal -Path ($netLetter + ":\x.md")
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
Check ($said -like ("'" + $overLetter + ":\x.md' is on a drive (" + $overLetter + ":) that stands for a network drive (" + $netLetter + ":), and only a file on one of this machine's own drives is shared*")) "a letter that stands for a network drive is refused, and the reason names both letters"
Check $saidPrefix "and behind the long-path prefix"
Check $saidRelative "and named from wherever that drive stands"
Check ($chain -like ("*is on a drive (" + $overOver + ":) that stands for a network drive (" + $netLetter + ":)*")) "a letter that stands for a letter that stands for a network drive is refused too: the chain is followed to its end"
Check ($ownNet -eq "") "a network drive itself is not this question's: the network question refuses it"
Check $viaShare "through a share, it is refused with that reason"
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
try { $ring = Get-HordeFilesAliasRefusal -Path ($letters[0] + ":\x.md") } finally { Remove-Letter $letters[0]; Remove-Letter $letters[1] }
Check ($ring -like "*stands for another drive letter, and that for another, without end*") "two letters that stand for each other are refused: where the file is cannot be told"
Check ((Get-Target $letters[0]) -eq "" -and (Get-Target $letters[1]) -eq "") "and both are gone again"
# Eight letters deep is followed; this chain of three ended at a folder of this machine's own drive.
$deep = "?"; $deepShared = $false
$null = & subst.exe ($letters[0] + ":") $docs
$null = [HordeTest.DenyDos]::DefineDosDevice(1, $letters[1] + ":", "\??\" + $letters[0] + ":")
$null = [HordeTest.DenyDos]::DefineDosDevice(1, $letters[2] + ":", "\??\" + $letters[1] + ":")
try { $deep = Get-HordeFilesAliasRefusal -Path ($letters[2] + ":\plain.md"); $deepShared = Test-Shared $h ($letters[2] + ":\plain.md") } finally { Remove-Letter $letters[2]; Remove-Letter $letters[1]; $null = & subst.exe ($letters[0] + ":") /D }
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
