# DOES THE MERGE GUARD HOOK REFUSE A HAND-TYPED `gh pr merge` OF YedPool/horde - AND NOTHING ELSE?
#
# hooks/horde-merge-guard.mjs is a PreToolUse hook (T-0247). This suite drives the real .mjs with real JSON
# payloads on stdin, in folders it makes under %TEMP%, and reads only its exit code and stderr:
#   - REFUSED (exit 2, stderr naming `horde merge OWNER/REPO#N -Task ... -State ... -By ...`): gh pr merge
#     with -R / --repo YedPool/horde in any letter case, with a pull-request URL of the repository, or with no
#     repository while the working folder's git remote is YedPool/horde; the merge endpoint of gh api; each
#     one found behind cd, a list, a pipe, $( ), backticks, bash -c, cmd /c, powershell -Command, eval,
#     Invoke-Expression, a call operator, a full path to gh.exe, an env prefix, Start-Process;
#   - ALLOWED (exit 0, silent): another repository (-R, or a folder whose remotes are another repository),
#     other gh pr and gh api verbs, `horde merge ...` itself, and TEXT that only mentions the command - an
#     echo, a commit message, a grep pattern, a comment, a here-document or here-string body, a quoted
#     argument; a tool that is not a shell; a payload with no tool_name;
#   - FAIL OPEN: bad JSON, empty input, and a bare gh pr merge in a folder git cannot read each exit 0 and
#     leave one line in the log.
# HORDE MERGE'S OWN gh CALL: the hook runs for a model's tool call and never for the children a command
# starts. The tool call that runs horde merge has horde as its program, and is allowed (below); gh
# itself is a child of that call, so nothing here could refuse it.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }

$node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $node) {
    Write-Host "  [SKIP] no node here: the hook cannot run" -ForegroundColor Yellow
    Complete-HordeSuite -Success "NOTHING RUN: no node" -PassCode 3
}
$hook = Join-Path $root "hooks\horde-merge-guard.mjs"
$utf8 = New-Object System.Text.UTF8Encoding($false)

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-merge-guard-" + [guid]::NewGuid().ToString("N").Substring(0, 10))
[void][System.IO.Directory]::CreateDirectory($work)
$log = Join-Path $work "hook.log"

function New-Repo {
    # A git folder whose origin is $Url (no network is touched), or a plain folder when $Url is empty.
    param([string]$Name, [string]$Url)
    $d = Join-Path $work $Name
    [void][System.IO.Directory]::CreateDirectory($d)
    if ($Url -ne "") {
        $null = & git -C $d init -q
        $null = & git -C $d remote add origin $Url
    }
    return $d
}
$hordeDir = New-Repo "horde" "https://github.com/YedPool/horde.git"
$hordeSsh = New-Repo "horde-ssh" "git@github.com:YedPool/horde.git"
$otherDir = New-Repo "gateway" "https://github.com/OrahVision/api-gateway.git"
$plainDir = New-Repo "plain" ""

function Invoke-Hook {
    # The hook with this payload text on stdin: { code; err; out }.
    param([string]$Stdin)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $node.Source
    $psi.Arguments = '"' + $hook + '"'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables["HORDE_MERGE_GUARD_LOG"] = $log
    $p = [System.Diagnostics.Process]::Start($psi)
    try {
        $bytes = $utf8.GetBytes($Stdin)
        $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $p.StandardInput.Close()
        $errTask = $p.StandardError.ReadToEndAsync()
        $out = $p.StandardOutput.ReadToEnd()
        $p.WaitForExit()
        return [pscustomobject]@{ code = $p.ExitCode; err = $errTask.Result; out = $out }
    } finally { $p.Dispose() }
}
function Payload { param([string]$Tool, [string]$Cmd, [string]$Cwd) return (ConvertTo-Json -Compress -Depth 5 -InputObject @{ tool_name = $Tool; tool_input = @{ command = $Cmd }; cwd = $Cwd; session_id = "t" }) }
function Run { param([string]$Cmd, [string]$Tool = "Bash", [string]$Cwd = $plainDir) return (Invoke-Hook (Payload $Tool $Cmd $Cwd)) }

$Q = [char]39
$D = [char]34

Write-Host ""
Write-Host "--- refused: a hand-typed merge of YedPool/horde ---" -ForegroundColor Cyan
$refused = @(
    @{ n = "gh pr merge -R YedPool/horde"; c = "gh pr merge 320 -R YedPool/horde --merge" }
    @{ n = "--repo, in lower case"; c = "gh pr merge 320 --repo yedpool/horde --merge" }
    @{ n = "--repo=YedPool/horde"; c = "gh pr merge 320 --repo=YedPool/horde" }
    @{ n = "-RYedPool/horde"; c = "gh pr merge 320 -RYedPool/horde" }
    @{ n = "the flag before the number"; c = "gh pr merge --merge -R YedPool/horde 320" }
    @{ n = "a pull request URL"; c = "gh pr merge https://github.com/YedPool/horde/pull/320 --merge" }
    @{ n = "the repository as a github.com URL after -R"; c = "gh pr merge 320 -R https://github.com/YedPool/horde.git" }
    @{ n = "--auto"; c = "gh pr merge 320 -R YedPool/horde --auto --merge" }
    @{ n = "--squash"; c = "gh pr merge 320 -R YedPool/horde --squash" }
    @{ n = "after a list"; c = "git status; gh pr merge 320 -R YedPool/horde" }
    @{ n = "after &&"; c = "git fetch && gh pr merge 320 -R YedPool/horde" }
    @{ n = "after ||"; c = "false || gh pr merge 320 -R YedPool/horde" }
    @{ n = "behind a pipe"; c = "echo y | gh pr merge 320 -R YedPool/horde" }
    @{ n = "on a line of its own"; c = "echo start`ngh pr merge 320 -R YedPool/horde`necho end" }
    @{ n = "in a command substitution"; c = "echo `$(gh pr merge 320 -R YedPool/horde)" }
    @{ n = "in a command substitution inside double quotes"; c = "echo ${D}merged: `$(gh pr merge 320 -R YedPool/horde)${D}" }
    @{ n = "in backticks"; c = "echo ``gh pr merge 320 -R YedPool/horde``" }
    @{ n = "in a subshell"; c = "(gh pr merge 320 -R YedPool/horde)" }
    @{ n = "in braces"; c = "{ gh pr merge 320 -R YedPool/horde; }" }
    @{ n = "bash -c"; c = "bash -c ${Q}gh pr merge 320 -R YedPool/horde${Q}" }
    @{ n = "sh -lc"; c = "sh -lc ${D}gh pr merge 320 -R YedPool/horde${D}" }
    @{ n = "cmd /c"; c = "cmd /c gh pr merge 320 -R YedPool/horde" }
    @{ n = "powershell -Command"; c = "powershell -NoProfile -Command ${D}gh pr merge 320 -R YedPool/horde${D}" }
    @{ n = "pwsh -c"; c = "pwsh -c ${Q}gh pr merge 320 -R YedPool/horde${Q}" }
    @{ n = "bash -c inside bash -c"; c = "bash -c ${D}bash -c ${Q}gh pr merge 320 -R YedPool/horde${Q}${D}" }
    @{ n = "eval"; c = "eval ${D}gh pr merge 320 -R YedPool/horde${D}" }
    @{ n = "Invoke-Expression"; c = "Invoke-Expression ${Q}gh pr merge 320 -R YedPool/horde${Q}" }
    @{ n = "iex"; c = "iex ${D}gh pr merge 320 -R YedPool/horde${D}" }
    @{ n = "the call operator"; c = "& gh pr merge 320 -R YedPool/horde"; tool = "PowerShell" }
    @{ n = "a full path to gh.exe"; c = "& ${Q}C:\Program Files\GitHub CLI\gh.exe${Q} pr merge 320 -R YedPool/horde"; tool = "PowerShell" }
    @{ n = "gh.exe"; c = "gh.exe pr merge 320 -R YedPool/horde"; tool = "PowerShell" }
    @{ n = "an env prefix"; c = "GH_PROMPT_DISABLED=1 gh pr merge 320 -R YedPool/horde" }
    @{ n = "env"; c = "env GH_TOKEN=x gh pr merge 320 -R YedPool/horde" }
    @{ n = "Start-Process"; c = "Start-Process gh -ArgumentList ${Q}pr${Q},${Q}merge${Q},${Q}320${Q},${Q}-R${Q},${Q}YedPool/horde${Q}"; tool = "PowerShell" }
    @{ n = "after cd into another folder"; c = "cd ${D}$otherDir${D} && gh pr merge 320 -R YedPool/horde" }
    @{ n = "the merge endpoint of gh api"; c = "gh api -X PUT repos/YedPool/horde/pulls/320/merge" }
    @{ n = "the merge endpoint, with fields"; c = "gh api repos/YedPool/horde/pulls/320/merge -X PUT -f merge_method=merge" }
    @{ n = "the merge endpoint, in lower case"; c = "gh api /repos/yedpool/horde/pulls/320/merge --method PUT" }
    @{ n = "PowerShell tool, bare, in a Horde folder"; c = "gh pr merge 320 --merge"; tool = "PowerShell"; cwd = $hordeDir }
)
foreach ($t in $refused) {
    $tool = if ($t.ContainsKey("tool")) { $t.tool } else { "Bash" }
    $cwd = if ($t.ContainsKey("cwd")) { $t.cwd } else { $plainDir }
    $r = Run $t.c $tool $cwd
    Check ($r.code -eq 2 -and $r.err -clike "*horde merge OWNER/REPO#N -Task T-NNNN -State done|waiting|progress -By <lane>*" -and $r.out -eq "") ("refused: " + $t.n)
}
$bare = Run "gh pr merge 320 --merge" "Bash" $hordeDir
Check ($bare.code -eq 2 -and $bare.err -clike "*BLOCKED by the horde merge guard*horde merge YedPool/horde#320 -Task T-0247*") "refused: a bare gh pr merge in a folder whose origin is YedPool/horde, with the exact command to use"
$bareSsh = Run "gh pr merge 320 --merge" "Bash" $hordeSsh
Check ($bareSsh.code -eq 2) "refused: a bare gh pr merge in a folder whose origin is the ssh form of YedPool/horde"
$bareNoNumber = Run "gh pr merge --merge" "Bash" $hordeDir
Check ($bareNoNumber.code -eq 2) "refused: gh pr merge with no number in a Horde folder (it merges the current branch's PR)"
$viaCd = Run "cd ${D}$hordeDir${D} && gh pr merge 320 --merge" "Bash" $plainDir
Check ($viaCd.code -eq 2) "refused: a bare gh pr merge after cd into a Horde folder"
$viaSetLocation = Run "Set-Location ${D}$hordeDir${D}; gh pr merge 320 --merge" "PowerShell" $plainDir
Check ($viaSetLocation.code -eq 2) "refused: a bare gh pr merge after Set-Location into a Horde folder"
Check ($bare.err -cnotlike "*Co-Authored*") "  and the message is the hook's own words"

Write-Host ""
Write-Host "--- allowed: other repositories ---" -ForegroundColor Cyan
$allowed = @(
    @{ n = "-R another repository"; c = "gh pr merge 12 -R OrahVision/api-gateway --merge" }
    @{ n = "--repo another repository"; c = "gh pr merge 12 --repo OrahVision/Orahvision-Universal --merge" }
    @{ n = "a repository that merely starts like it"; c = "gh pr merge 12 -R YedPool/horde-tools --merge" }
    @{ n = "a repository that ends like it"; c = "gh pr merge 12 -R NotYedPool/horde --merge" }
    @{ n = "a pull request URL of another repository"; c = "gh pr merge https://github.com/OrahVision/api-gateway/pull/12 --merge" }
    @{ n = "-R another repository, from a Horde folder"; c = "gh pr merge 12 -R OrahVision/api-gateway --merge"; cwd = $hordeDir }
    @{ n = "bare, in another repository's folder"; c = "gh pr merge 12 --merge"; cwd = $otherDir }
    @{ n = "bare, in a folder that is not a git folder (it cannot be told, so the hook stays out of the way)"; c = "gh pr merge 12 --merge"; cwd = $plainDir }
    @{ n = "cd out of a Horde folder first"; c = "cd ${D}$otherDir${D} && gh pr merge 12 --merge"; cwd = $hordeDir }
    @{ n = "the merge endpoint of another repository"; c = "gh api -X PUT repos/OrahVision/api-gateway/pulls/12/merge" }
)
foreach ($t in $allowed) {
    $tool = if ($t.ContainsKey("tool")) { $t.tool } else { "Bash" }
    $cwd = if ($t.ContainsKey("cwd")) { $t.cwd } else { $plainDir }
    $r = Run $t.c $tool $cwd
    Check ($r.code -eq 0 -and $r.err -eq "" -and $r.out -eq "") ("allowed, silent: " + $t.n)
}

Write-Host ""
Write-Host "--- allowed: other gh verbs, and horde merge itself ---" -ForegroundColor Cyan
$verbs = @(
    @{ n = "gh pr view"; c = "gh pr view 320 -R YedPool/horde" }
    @{ n = "gh pr view in a Horde folder"; c = "gh pr view 320 --json state"; cwd = $hordeDir }
    @{ n = "gh pr list"; c = "gh pr list -R YedPool/horde --state merged -L 30 --json number,body" }
    @{ n = "gh pr checks"; c = "gh pr checks 320 -R YedPool/horde" }
    @{ n = "gh pr diff"; c = "gh pr diff 320 -R YedPool/horde" }
    @{ n = "gh pr status"; c = "gh pr status"; cwd = $hordeDir }
    @{ n = "gh pr create"; c = "gh pr create -R YedPool/horde --title x --body y" }
    @{ n = "gh pr ready"; c = "gh pr ready 320 -R YedPool/horde" }
    @{ n = "gh pr close"; c = "gh pr close 322 -R YedPool/horde" }
    @{ n = "gh pr comment"; c = "gh pr comment 320 -R YedPool/horde -b ${D}do not gh pr merge this${D}" }
    @{ n = "gh pr edit"; c = "gh pr edit 320 -R YedPool/horde --body-file b.md" }
    @{ n = "gh api reading a pull request"; c = "gh api repos/YedPool/horde/pulls/320" }
    @{ n = "gh api listing its merge commit files"; c = "gh api repos/YedPool/horde/pulls/320/files" }
    @{ n = "gh api reading commits"; c = "gh api repos/YedPool/horde/commits/abc123 --jq .parents[].sha" }
    @{ n = "gh repo view"; c = "gh repo view YedPool/horde" }
    @{ n = "horde merge (the command to use)"; c = "horde merge YedPool/horde#320 -Task T-0247 -State done -By F" }
    @{ n = "horde merge from a Horde folder"; c = "horde merge YedPool/horde#321 -Task T-0247 -State waiting -By F -On founder"; cwd = $hordeDir }
    @{ n = "horde merge, PowerShell tool"; c = "horde merge YedPool/horde#320 -Task T-0247 -State done -By F"; tool = "PowerShell"; cwd = $hordeDir }
    @{ n = "bin\horde merge by path"; c = "& ${Q}C:\Users\x\bin\horde\bin\horde.ps1${Q} merge YedPool/horde#320 -Task T-0247 -State done -By F"; tool = "PowerShell" }
    @{ n = "git push"; c = "git push origin feature/horde-merge"; cwd = $hordeDir }
)
foreach ($t in $verbs) {
    $tool = if ($t.ContainsKey("tool")) { $t.tool } else { "Bash" }
    $cwd = if ($t.ContainsKey("cwd")) { $t.cwd } else { $plainDir }
    $r = Run $t.c $tool $cwd
    Check ($r.code -eq 0 -and $r.err -eq "" -and $r.out -eq "") ("allowed, silent: " + $t.n)
}

Write-Host ""
Write-Host "--- allowed: text that merely mentions the command ---" -ForegroundColor Cyan
$text = @(
    @{ n = "echo in double quotes"; c = "echo ${D}gh pr merge 320 -R YedPool/horde${D}" }
    @{ n = "echo in single quotes"; c = "echo ${Q}gh pr merge 320 -R YedPool/horde${Q}" }
    @{ n = "echo without quotes"; c = "echo gh pr merge 320 -R YedPool/horde" }
    @{ n = "Write-Output"; c = "Write-Output ${D}run gh pr merge -R YedPool/horde${D}"; tool = "PowerShell" }
    @{ n = "a commit message"; c = "git commit -m ${D}stop hand merges: gh pr merge -R YedPool/horde is refused${D}" }
    @{ n = "a commit message with a ; and && inside it"; c = "git commit -m ${D}a; gh pr merge 1 -R YedPool/horde && b${D}" }
    @{ n = "a grep pattern"; c = "grep -rn ${Q}gh pr merge${Q} NOTES.md CONTRIBUTING.md" }
    @{ n = "a grep pattern with the repository"; c = "grep -rn ${D}gh pr merge .* YedPool/horde${D} docs" }
    @{ n = "a comment line"; c = "# gh pr merge 320 -R YedPool/horde`nls" }
    @{ n = "a comment holding a ; and the command"; c = "ls # note; gh pr merge 320 -R YedPool/horde" }
    @{ n = "a trailing comment"; c = "ls # gh pr merge 320 -R YedPool/horde" }
    @{ n = "a here-document body"; c = "cat > notes.md <<${Q}EOF${Q}`ngh pr merge 320 -R YedPool/horde`nEOF`nls" }
    @{ n = "a here-document body, unquoted delimiter"; c = "cat <<END`n  gh pr merge 320 -R YedPool/horde`nEND" }
    @{ n = "a here-document with a dash"; c = "cat <<-EOT`ngh pr merge 320 -R YedPool/horde`nEOT" }
    @{ n = "a PowerShell here-string body"; c = "`$x = @${Q}`ngh pr merge 320 -R YedPool/horde`n${Q}@`nWrite-Output `$x"; tool = "PowerShell" }
    @{ n = "a PowerShell here-string body with an apostrophe"; c = "`$x = @${Q}`ndon${Q}t run`ngh pr merge 320 -R YedPool/horde`n${Q}@`nWrite-Output `$x"; tool = "PowerShell" }
    @{ n = "a PowerShell double here-string body"; c = "`$x = @${D}`ngh pr merge 320 -R YedPool/horde`n${D}@`nWrite-Output `$x"; tool = "PowerShell" }
    @{ n = "a file written with Set-Content"; c = "Set-Content -Path n.txt -Value ${Q}gh pr merge 320 -R YedPool/horde${Q}"; tool = "PowerShell" }
    @{ n = "gh pr merge as an argument of another program"; c = "python -c ${D}print('gh pr merge -R YedPool/horde')${D}" }
    @{ n = "bash -c that only echoes it"; c = "bash -c ${Q}echo gh pr merge 320 -R YedPool/horde${Q}" }
    @{ n = "a path that contains gh"; c = "ls C:\tools\gh\pr\merge" }
    @{ n = "a program named like gh"; c = "ghost pr merge -R YedPool/horde" }
    @{ n = "gh help text"; c = "gh help pr merge" }
    @{ n = "gh pr merge --help"; c = "gh pr merge --help" }
)
foreach ($t in $text) {
    $tool = if ($t.ContainsKey("tool")) { $t.tool } else { "Bash" }
    $cwd = if ($t.ContainsKey("cwd")) { $t.cwd } else { $hordeDir }
    $r = Run $t.c $tool $cwd
    Check ($r.code -eq 0 -and $r.err -eq "" -and $r.out -eq "") ("allowed, silent: " + $t.n)
}

Write-Host ""
Write-Host "--- allowed: not a shell, or nothing to read ---" -ForegroundColor Cyan
foreach ($tool in @("Read", "Edit", "Write", "Glob", "Grep", "Agent")) {
    $r = Invoke-Hook (Payload $tool "gh pr merge 320 -R YedPool/horde" $hordeDir)
    Check ($r.code -eq 0 -and $r.err -eq "") ("allowed: the " + $tool + " tool is not a shell")
}
$r = Invoke-Hook '{"tool_input":{"command":"gh pr merge 320 -R YedPool/horde"}}'
Check ($r.code -eq 0 -and $r.err -eq "") "allowed: a payload with no tool_name"
$r = Invoke-Hook '{"tool_name":"Bash","tool_input":{}}'
Check ($r.code -eq 0 -and $r.err -eq "") "allowed: a Bash payload with no command"
$r = Invoke-Hook '{"tool_name":"Bash","tool_input":{"command":42}}'
Check ($r.code -eq 0 -and $r.err -eq "") "allowed: a command that is not text"

Write-Host ""
Write-Host "--- fail open: the hook is never why a turn fails ---" -ForegroundColor Cyan
if ([System.IO.File]::Exists($log)) { [System.IO.File]::Delete($log) }
$r = Invoke-Hook "this is not json"
Check ($r.code -eq 0 -and $r.err -eq "") "bad JSON: exit 0, silent"
Check ([System.IO.File]::Exists($log) -and [System.IO.File]::ReadAllText($log) -clike "*stdin parse failed*") "  and one line says why in the log"
$r = Invoke-Hook ""
Check ($r.code -eq 0 -and $r.err -eq "") "empty input: exit 0, silent"
if ([System.IO.File]::Exists($log)) { [System.IO.File]::Delete($log) }
$gone = Join-Path $work "no-such-folder"
$r = Run "gh pr merge 12 --merge" "Bash" $gone
Check ($r.code -eq 0 -and $r.err -eq "" -and [System.IO.File]::Exists($log) -and [System.IO.File]::ReadAllText($log) -clike "*could not read the git remotes*") "a bare gh pr merge in a folder git cannot read: allowed, and the log says it could not be told"
$r = Run "gh pr merge 320 -R YedPool/horde" "Bash" $gone
Check ($r.code -eq 2) "  but with -R YedPool/horde the folder does not matter: still refused"

try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction Stop } catch { Write-Host ("  (the suite's temp folder stays: " + $work + ")") }
Complete-HordeSuite -Success "the merge guard hook refuses a hand-typed gh pr merge of YedPool/horde, and nothing else, and fails open"
