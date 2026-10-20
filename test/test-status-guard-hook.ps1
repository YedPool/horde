# DOES THE STATUS GUARD HOOK STOP A CARD THE PANEL WOULD REFUSE - WITHOUT EVER BEING THE REASON A TURN FAILS?
#
# hooks/horde-status-guard.mjs is a PostToolUse hook. This suite drives the real .mjs with real JSON
# payloads on stdin, in folders it makes under %TEMP%, and reads what it does to those folders:
#   - a payload that does not concern a status card exits 0 and SPAWNS NOTHING: the checker writes a
#     marker line whenever it runs (HORDE_STATUS_GUARD_MARKER), and the marker must stay absent;
#   - a clean card is copied to .status.last-good.txt, silently;
#   - a bad card written with Write/Edit/MultiEdit is put back from the last good copy (exit 2, stderr
#     naming the file and every problem and the fix); with no good copy the bad file is left (exit 2);
#   - a shell command that mentions status.txt checks the cards written in the last 120 s, and no others;
#   - status.retired.txt is never looked at;
#   - anything that goes wrong inside the hook (bad JSON, no pwsh, a checker that fails) logs one line
#     and exits 0: a guard must fail open.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }

$node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $node) {
    Write-Host "  [SKIP] no node here: the hook cannot run" -ForegroundColor Yellow
    Complete-HordeSuite -Success "NOTHING RUN: no node" -PassCode 3
}
$hook = Join-Path $root "hooks\horde-status-guard.mjs"
$pwsh7 = Join-Path $env:ProgramFiles "PowerShell\7\pwsh.exe"
$utf8 = New-Object System.Text.UTF8Encoding($false)

$work = Join-Path $env:TEMP ("horde-status-guard-" + [guid]::NewGuid().ToString("N"))
$orcs = Join-Path $work "orcs"
New-Item -ItemType Directory -Path $orcs -Force | Out-Null
$elsewhere = Join-Path $work "elsewhere"
New-Item -ItemType Directory -Path $elsewhere -Force | Out-Null
$marker = Join-Path $work "marker.txt"
$log = Join-Path $work "hook.log"

$goodCard = "horde-orc-status 1`norc: K`nlane: guard test`ndoing: writing the guard test`nfinished: read the hook`nblocked: no`n"
$goodCard2 = "horde-orc-status 1`norc: K`nlane: guard test`ndoing: a second good doing`nfinished: read the hook`nblocked: no`n"
$badCard = "horde-orc-status 1`norc: K`nlane: guard test`ndoing: fixing PR 68 and caf" + [char]0x00E9 + "`nfinished: read the hook`nblocked: no`n"

function New-Orcs {
    # A fresh orcs folder, so a shell command (which checks every card written in the last 120 s) sees only its own section cards.
    param([string]$Tag)
    $script:orcs = Join-Path $work (Join-Path $Tag "orcs")
    New-Item -ItemType Directory -Path $script:orcs -Force | Out-Null
}
function Lane { param([string]$Name) $d = Join-Path $orcs $Name; New-Item -ItemType Directory -Path $d -Force | Out-Null; return $d }
function Put { param([string]$Path, [string]$Text, [int]$AgeSeconds = 0) [System.IO.File]::WriteAllBytes($Path, $utf8.GetBytes($Text)); [System.IO.File]::SetLastWriteTimeUtc($Path, [datetime]::UtcNow.AddSeconds(-$AgeSeconds)) }
function Text { param([string]$Path) return [System.IO.File]::ReadAllText($Path) }
function Reset-Marks { foreach ($f in @($marker, $log)) { if ([System.IO.File]::Exists($f)) { [System.IO.File]::Delete($f) } } }
function Ran { return [System.IO.File]::Exists($marker) }
function Names { param([string]$Dir) return (@(Get-ChildItem -LiteralPath $Dir -Force | Sort-Object Name | ForEach-Object { $_.Name }) -join ",") }

function Invoke-Hook {
    # Runs the hook with this payload text on stdin. Returns { code; err; out }.
    param([string]$Stdin, [hashtable]$Env = @{})
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $node.Source
    $psi.Arguments = '"' + $hook + '"'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables["HORDE_STATUS_GUARD_LOG"] = $log
    $psi.EnvironmentVariables["HORDE_STATUS_GUARD_MARKER"] = $marker
    $psi.EnvironmentVariables["HORDE_STATUS_GUARD_PWSH"] = $pwsh7
    if ($psi.EnvironmentVariables.ContainsKey("HORDE_STATUS_ORCS_ROOT")) { [void]$psi.EnvironmentVariables.Remove("HORDE_STATUS_ORCS_ROOT") }
    foreach ($k in $Env.Keys) { $psi.EnvironmentVariables[$k] = $Env[$k] }
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
function Payload { param([string]$Tool, [hashtable]$ToolInput, [string]$Cwd = "") return (ConvertTo-Json -Compress -Depth 5 -InputObject @{ tool_name = $Tool; tool_input = $ToolInput; cwd = $Cwd; session_id = "t" }) }
function Hook-File { param([string]$Tool, [string]$Path, [hashtable]$Env = @{}) return (Invoke-Hook (Payload $Tool @{ file_path = $Path }) $Env) }
function Hook-Shell { param([string]$Cmd, [string]$Cwd, [string]$Tool = "Bash", [hashtable]$Env = @{}) return (Invoke-Hook (Payload $Tool @{ command = $Cmd } $Cwd) $Env) }

try {

Write-Host ""
Write-Host "--- CONTROL: the harness can tell a run from a non-run ---" -ForegroundColor Cyan
Reset-Marks
$k = Lane "K"
Put (Join-Path $k "status.txt") $goodCard
$r = Hook-File "Write" (Join-Path $k "status.txt")
Check ($r.code -eq 0 -and (Ran)) "a Write of a status card exits 0 AND the marker appears (so a missing marker below means the checker did not run)"

Write-Host ""
Write-Host "--- what does not concern a status card spawns nothing ---" -ForegroundColor Cyan
$ignored = @(
    @{ name = "a Write to an unrelated file"; run = { Hook-File "Write" (Join-Path $work "notes.txt") } }
    @{ name = "a Write to another file in an Orc's folder"; run = { Hook-File "Write" (Join-Path $k "other.txt") } }
    @{ name = "a Write to status.txt directly under orcs (no lane folder)"; run = { Hook-File "Write" (Join-Path $orcs "status.txt") } }
    @{ name = "a Write to status.txt outside any orcs folder"; run = { Hook-File "Write" (Join-Path $work "status.txt") } }
    @{ name = "a Write to a card two folders deep"; run = { Hook-File "Write" (Join-Path $k "sub\status.txt") } }
    @{ name = "a Write to status.retired.txt"; run = { Hook-File "Write" (Join-Path $k "status.retired.txt") } }
    @{ name = "a Read of a status card (not a write tool)"; run = { Hook-File "Read" (Join-Path $k "status.txt") } }
    @{ name = "a Bash command that never says status.txt"; run = { Hook-Shell "ls -la" $k } }
    @{ name = "a Bash command naming only status.retired.txt"; run = { Hook-Shell "cat status.retired.txt" $k } }
    @{ name = "a Bash command that says status.txt with no orcs folder to be found"; run = { Hook-Shell "cat status.txt" $elsewhere } }
    @{ name = "a tool the hook has no business with"; run = { Invoke-Hook (Payload "Glob" @{ pattern = "status.txt" } $k) } }
    @{ name = "a payload with no tool_name"; run = { Invoke-Hook '{"tool_input":{"file_path":"x"}}' } }
)
foreach ($c in $ignored) {
    Reset-Marks
    $r = & $c.run
    Check ($r.code -eq 0 -and $r.err -eq "" -and -not (Ran)) ("exit 0, silent, nothing spawned: " + $c.name)
}

Write-Host ""
Write-Host "--- a clean card is copied to the last-good file ---" -ForegroundColor Cyan
Reset-Marks
$c1 = Lane "C1"
Put (Join-Path $c1 "status.txt") $goodCard
$r = Hook-File "Write" (Join-Path $c1 "status.txt")
Check ($r.code -eq 0 -and $r.err -eq "" -and $r.out -eq "") "exit 0 and not a word printed"
Check ([System.IO.File]::Exists((Join-Path $c1 ".status.last-good.txt")) -and (Text (Join-Path $c1 ".status.last-good.txt")) -ceq $goodCard) "the last-good copy is the card's bytes"
Put (Join-Path $c1 "status.txt") $goodCard2
$r = Hook-File "Edit" (Join-Path $c1 "status.txt")
Check ($r.code -eq 0 -and (Text (Join-Path $c1 ".status.last-good.txt")) -ceq $goodCard2) "after a second clean edit the copy moves on"
Check ((Names $c1) -ceq ".status.last-good.txt,status.txt") "no temp file is left"
$upPath = $work + "\ORCS\C1\STATUS.TXT"
$up = Hook-File "Write" $upPath
Check ($up.code -eq 0) "the path match ignores letter case"

Write-Host ""
Write-Host "--- a bad card is put back from the last good copy ---" -ForegroundColor Cyan
foreach ($tool in @("Write", "Edit", "MultiEdit")) {
    Reset-Marks
    $b = Lane ("B" + $tool)
    Put (Join-Path $b "status.txt") $goodCard
    $null = Hook-File $tool (Join-Path $b "status.txt")
    Put (Join-Path $b "status.txt") $badCard
    $r = Hook-File $tool (Join-Path $b "status.txt")
    Check ($r.code -eq 2) ($tool + ": a bad card makes the hook exit 2")
    Check ($r.err.Contains((Join-Path $b "status.txt")) -and $r.err.Contains("holds bytes that are not ASCII") -and $r.err.Contains("doing holds a bare reference or a path")) ($tool + ": stderr names the file and BOTH problems")
    Check ($r.err.Contains("last good copy") -and $r.err.Contains("was put back") -and $r.err.Contains("horde status set -Doing")) ($tool + ": stderr says it was restored and gives the fix")
    Check ((Text (Join-Path $b "status.txt")) -ceq $goodCard) ($tool + ": status.txt is the last good card again")
    Check ((Text (Join-Path $b ".status.last-good.txt")) -ceq $goodCard -and (Names $b) -ceq ".status.last-good.txt,status.txt") ($tool + ": the last-good copy is unchanged and no temp file is left")
}
$fw = Hook-File "Write" (Join-Path $orcs "BWrite/status.txt")
Check ($fw.code -eq 0) "forward slashes in the path are accepted (the restored card is clean now, so exit 0)"

Write-Host ""
Write-Host "--- with no good copy, the bad file is left ---" -ForegroundColor Cyan
$n1 = Lane "N1"
Put (Join-Path $n1 "status.txt") $badCard
$r = Hook-File "Write" (Join-Path $n1 "status.txt")
Check ($r.code -eq 2 -and $r.err.Contains("No good copy existed") -and $r.err.Contains("horde status set")) "exit 2, and it says no good copy existed"
Check ((Text (Join-Path $n1 "status.txt")) -ceq $badCard -and (Names $n1) -ceq "status.txt") "the bad file is untouched and no last-good was invented"
$n2 = Lane "N2"
Put (Join-Path $n2 "status.txt") $badCard
Put (Join-Path $n2 ".status.last-good.txt") ($goodCard.Replace("blocked: no", "blocked:"))
$r = Hook-File "Write" (Join-Path $n2 "status.txt")
Check ($r.code -eq 2 -and $r.err.Contains("No good copy existed") -and (Text (Join-Path $n2 "status.txt")) -ceq $badCard) "a last-good copy that itself does not read clean is NOT put back"

Write-Host ""
Write-Host "--- a shell command checks the cards written in the last 120 s, and no others ---" -ForegroundColor Cyan
Reset-Marks
New-Orcs "shell"
$shellOrcs = $script:orcs
$s1 = Lane "S1"; $s2 = Lane "S2"; $s3 = Lane "S3"
Put (Join-Path $s1 "status.txt") $goodCard
Put (Join-Path $s1 ".status.last-good.txt") $goodCard
Put (Join-Path $s1 "status.txt") $badCard 5
Put (Join-Path $s2 "status.txt") $badCard 600
Put (Join-Path $s2 ".status.last-good.txt") $goodCard 600
$s2before = (Get-Item -LiteralPath (Join-Path $s2 "status.txt")).LastWriteTimeUtc.Ticks
Put (Join-Path $s3 "status.txt") $goodCard2 10
$r = Hook-Shell "echo hello > status.txt" $s1
Check ($r.code -eq 2 -and $r.err.Contains((Join-Path $s1 "status.txt"))) "Bash: the recent bad card is rejected, found from the working folder inside orcs"
Check ((Text (Join-Path $s1 "status.txt")) -ceq $goodCard) "   and restored"
Check ((Text (Join-Path $s2 "status.txt")) -ceq $badCard -and (Get-Item -LiteralPath (Join-Path $s2 "status.txt")).LastWriteTimeUtc.Ticks -eq $s2before -and -not $r.err.Contains((Join-Path $s2 "status.txt"))) "   the STALE bad card (10 minutes old) is not touched and not named"
Check ((Text (Join-Path $s3 ".status.last-good.txt")) -ceq $goodCard2) "   a recent clean card of another Orc gets its last-good copy"
Reset-Marks
New-Orcs "stale"
$st = Lane "ST"
Put (Join-Path $st "status.txt") $badCard 600
$s1again = Hook-Shell "cat status.txt" $st
Check ($s1again.code -eq 0 -and -not (Ran)) "Bash with only stale cards in reach: exit 0 and nothing spawned"
Reset-Marks
Put (Join-Path $s1 "status.txt") $badCard 3
$r = Hook-Shell "Set-Content status.txt 'x'" $s1 "PowerShell"
Check ($r.code -eq 2 -and (Text (Join-Path $s1 "status.txt")) -ceq $goodCard) "the PowerShell tool is treated the same way"
Put (Join-Path $s1 "status.txt") $badCard 3
$r = Hook-Shell "cat status.txt" $elsewhere -Env @{ HORDE_STATUS_ORCS_ROOT = $shellOrcs }
Check ($r.code -eq 2 -and (Text (Join-Path $s1 "status.txt")) -ceq $goodCard) "from a folder outside orcs, HORDE_STATUS_ORCS_ROOT finds the cards"
Put (Join-Path $s1 "status.txt") $badCard 3
$r = Hook-Shell ("echo x > " + (Join-Path $s1 "status.txt")) $env:TEMP
Check ($r.code -eq 2) "an orcs path written in the command finds the cards when the working folder is elsewhere"

Write-Host ""
Write-Host "--- status.retired.txt is never looked at ---" -ForegroundColor Cyan
Reset-Marks
New-Orcs "retired"
$rt = Lane "RT"
Put (Join-Path $rt "status.retired.txt") $badCard 2
$r = Hook-Shell "mv status.txt status.retired.txt" $rt
Check ($r.code -eq 0 -and $r.err -eq "" -and -not (Ran)) "a retired lane (only status.retired.txt, bad) is not checked and nothing is spawned"
Put (Join-Path $rt "status.txt") $goodCard 2
$r = Hook-Shell "cat status.txt" $rt
Check ($r.code -eq 0 -and (Text (Join-Path $rt "status.retired.txt")) -ceq $badCard) "a lane that came back: its status.txt is checked, status.retired.txt still never read or changed"

Write-Host ""
Write-Host "--- it fails open ---" -ForegroundColor Cyan
foreach ($bad in @(@{ n = "malformed JSON"; s = "{not json" }, @{ n = "empty stdin"; s = "" }, @{ n = "a JSON array"; s = "[1,2]" })) {
    Reset-Marks
    $r = Invoke-Hook $bad.s
    $logged = [System.IO.File]::Exists($log) -and @((Text $log).TrimEnd("`n") -split "`n").Count -eq 1
    Check ($r.code -eq 0 -and $r.err -eq "" -and -not (Ran)) ("exit 0, silent: " + $bad.n)
    if ($bad.n -ne "a JSON array") { Check ($logged) ("   and exactly one line in the log: " + $bad.n) }
}
Reset-Marks
$f1 = Lane "F1"
Put (Join-Path $f1 "status.txt") $badCard
$r = Hook-File "Write" (Join-Path $f1 "status.txt") @{ HORDE_STATUS_GUARD_PWSH = (Join-Path $work "no-such-pwsh.exe") }
Check ($r.code -eq 0 -and $r.err -eq "") "pwsh missing: exit 0, silent"
Check ([System.IO.File]::Exists($log) -and @((Text $log).TrimEnd("`n") -split "`n").Count -eq 1) "   and one line in the log"
Check ((Text (Join-Path $f1 "status.txt")) -ceq $badCard) "   the card is left alone, since nothing could judge it"
Reset-Marks
$r = Hook-File "Write" (Join-Path $f1 "status.txt") @{ HORDE_STATUS_GUARD_PWSH = $node.Source }
Check ($r.code -eq 0 -and $r.err -eq "" -and [System.IO.File]::Exists($log)) "a checker that exits with an error (node standing in): exit 0, silent, logged"

} finally {
    if ((Split-Path -Leaf $work) -match '\Ahorde-status-guard-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force }
}

Complete-HordeSuite -Success "the status guard hook rejects and restores a bad card, copies a good one, ignores what is not a card, and fails open"
