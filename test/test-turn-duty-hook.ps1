# DOES THE TURN-DUTY STOP HOOK NUDGE AN ORC THAT HAS NOT PUBLISHED ITS DECISIONS LIST - ONCE, AND NEVER AT ITS OWN EXPENSE?
#
# hooks/horde-turn-duty.mjs is a Stop hook. This suite drives the real .mjs with real JSON payloads on stdin, in
# folders it makes under %TEMP%, with a stand-in `horde` (a .cmd that runs a small node script) that answers
# `decisions published -Orc <X> -Json` the way the shipped verb does, and writes a marker line whenever it is run:
#   - stop_hook_active, a throttled session, a session not in the registry and a Warg pass WITHOUT spawning the
#     stand-in (the marker must stay absent: the cheap path is the point);
#   - an Orc or the Thrall that published within 30 minutes passes; one that never published, or published 45
#     minutes ago, is blocked ONCE with the exact reason, and the next stop passes;
#   - the state file is written before the block (a state folder that cannot be written means no block);
#   - fleet.db missing, a timeout, bad JSON, bad stdin: the hook passes, logs one line and records the check;
#   - the task-list check is OFF unless the suite switches it on, and two failed checks make ONE block.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }

$node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $node) {
    Write-Host "  [SKIP] no node here: the hook cannot run" -ForegroundColor Yellow
    Complete-HordeSuite -Success "NOTHING RUN: no node" -PassCode 3
}
$hook = Join-Path $root "hooks\horde-turn-duty.mjs"
$utf8 = New-Object System.Text.UTF8Encoding($false)

$work = Join-Path $env:TEMP ("horde-turn-duty-" + [guid]::NewGuid().ToString("N"))
$stateDir = Join-Path $work "state"
$registry = Join-Path $work "registry"
$marker = Join-Path $work "marker.txt"
$log = Join-Path $work "hook.log"
$homeMarker = Join-Path $work "home-marker.txt"
$configDir = Join-Path $work "config"
$profileDir = Join-Path $work "profile"
$pointerFile = Join-Path $profileDir ".horde-home.json"
$ptrHome1 = Join-Path $work "pointer-home-one"
$ptrHome2 = Join-Path $work "pointer-home-two"
New-Item -ItemType Directory -Path $profileDir, $ptrHome1, $ptrHome2 -Force | Out-Null
New-Item -ItemType Directory -Path $registry -Force | Out-Null

$home1 = "C:\fleet-home\one"
$home2 = "C:\fleet-home\two"
$home3 = "C:\fleet-home\three"
function First-Line { param([string]$Letter) return ("no published decisions list was found for Orc " + $Letter + " in the last 30 minutes: publish yours with horde decisions publish -File <list.json> (empty list is valid)") }

# THE STAND-IN. TD_MODE answers `decisions published`, TD_TASK answers the (placeholder) task-list verb.
$standinJs = @'
import { appendFileSync } from "node:fs";
const a = process.argv.slice(2);
if (process.env.TD_MARKER) appendFileSync(process.env.TD_MARKER, a.join(" ") + "\n");
if (process.env.TD_HOME_MARKER) appendFileSync(process.env.TD_HOME_MARKER, String(process.env.HORDE_HOME) + "\n");
const mode = (a[0] === "decisions" ? process.env.TD_MODE : process.env.TD_TASK) || "never";
const orc = a[a.indexOf("-Orc") + 1];
// TD_SNAP is the snapshot id (default s1); TD_CONFIRMED is minutes ago for confirmedAt, or "bad" for a malformed one.
const list = (who, minutes) => {
  const e = { orc: who, publishedAt: new Date(Date.now() - minutes * 60000).toISOString(), count: 0, items: [] };
  if (process.env.TD_SNAP !== "none") e.snapshot = process.env.TD_SNAP || "s1"; // "none": a list with no snapshot id
  const c = process.env.TD_CONFIRMED;
  if (c === "bad") e.confirmedAt = "not a time";
  else if (c && c.startsWith("raw:")) e.confirmedAt = c.slice(4);
  else if (c) e.confirmedAt = new Date(Date.now() - Number(c) * 60000).toISOString();
  return JSON.stringify({ lists: [e] });
};
if (mode === "never") { console.log('{"lists":[]}'); }
else if (mode.startsWith("age:")) { console.log(list(orc, Number(mode.slice(4)))); }
else if (mode.startsWith("rawpub:")) { const o = JSON.parse(list(orc, 0)); o.lists[0].publishedAt = mode.slice(7); console.log(JSON.stringify(o)); }
else if (mode === "otherorc") { console.log(list("ZZ", 1)); }
else if (mode === "badjson") { console.log("this is not json"); }
else if (mode === "dbmissing") { console.error("horde decisions published: refused: fleet.db does not exist yet at X; run horde db init"); process.exitCode = 1; }
else if (mode === "hang") { setTimeout(() => { console.log('{"lists":[]}'); }, 6000); }
'@
[System.IO.File]::WriteAllText((Join-Path $work "standin.mjs"), $standinJs, $utf8)
$standin = Join-Path $work "standin.cmd"
[System.IO.File]::WriteAllText($standin, ("@`"" + $node.Source + "`" `"" + (Join-Path $work "standin.mjs") + "`" %*`r`n"), $utf8)

function Text { param([string]$Path) return [System.IO.File]::ReadAllText($Path) }
function Reset-Marks { foreach ($f in @($marker, $log, $homeMarker)) { if ([System.IO.File]::Exists($f)) { [System.IO.File]::Delete($f) } } }
function Ran { return [System.IO.File]::Exists($marker) }
function Home-Seen { if (-not [System.IO.File]::Exists($homeMarker)) { return "" }; return (Text $homeMarker).Trim() }
function Put-Config { param([string]$Json) New-Item -ItemType Directory -Path $configDir -Force | Out-Null; [System.IO.File]::WriteAllText((Join-Path $configDir "config.json"), $Json, $utf8) }
function Clear-Config { if (Test-Path -LiteralPath $configDir) { Remove-Item -LiteralPath $configDir -Recurse -Force } }
function Log-Lines { if (-not [System.IO.File]::Exists($log)) { return 0 }; return @((Text $log).TrimEnd("`n") -split "`n").Count }
function State-Path { param([string]$Sid) return (Join-Path $stateDir ($Sid + ".json")) }
function New-Sid { return [guid]::NewGuid().ToString() }
function Put-Session {
    # A registry record, in the shape the real ones have (read from the live registry, read only).
    param([string]$Sid, [string]$Role, [string]$Label, [string]$Parent = "", [switch]$Retired)
    $rec = [ordered]@{ role = $Role; label = $Label; owner = $(if ($Role -eq "master") { "" } else { $Label }) }
    if ($Parent -ne "") { $rec["parent"] = $Parent }
    if ($Retired) { $rec["retired"] = $true; $rec["retiredAt"] = "2026-10-18T10:00:00.0000000Z" }
    [System.IO.File]::WriteAllText((Join-Path $registry ($Sid + ".json")), (ConvertTo-Json -InputObject $rec), $utf8)
}
function Put-State { param([string]$Sid, [int]$CheckedMinutesAgo) New-Item -ItemType Directory -Path $stateDir -Force | Out-Null; $ms = [long]([datetimeoffset]::UtcNow.AddMinutes(-$CheckedMinutesAgo).ToUnixTimeMilliseconds()); [System.IO.File]::WriteAllText((State-Path $Sid), ('{"lastCheckedAt":' + $ms + ',"lastBlockedAt":0}'), $utf8) }
function Put-BlockedState {
    # A state whose last check was 31 minutes ago (throttle over) and whose last block was $BlockedMinutesAgo, for $Snapshot.
    param([string]$Sid, [int]$BlockedMinutesAgo, [string]$Snapshot)
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    $c = [long]([datetimeoffset]::UtcNow.AddMinutes(-31).ToUnixTimeMilliseconds())
    $b = [long]([datetimeoffset]::UtcNow.AddMinutes(-$BlockedMinutesAgo).ToUnixTimeMilliseconds())
    [System.IO.File]::WriteAllText((State-Path $Sid), ('{"lastCheckedAt":' + $c + ',"lastBlockedAt":' + $b + ',"lastDecisionsBlockedAt":' + $b + ',"lastBlockedSnapshot":"' + $Snapshot + '"}'), $utf8)
}
function Get-StateObj { param([string]$Sid) $p = State-Path $Sid; if (-not [System.IO.File]::Exists($p)) { return $null }; return (Text $p | ConvertFrom-Json) }

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
    $psi.EnvironmentVariables["HORDE_TURN_DUTY_STATE_DIR"] = $stateDir
    $psi.EnvironmentVariables["HORDE_TURN_DUTY_REGISTRY"] = $registry
    $psi.EnvironmentVariables["HORDE_TURN_DUTY_HORDE"] = $standin
    $psi.EnvironmentVariables["HORDE_TURN_DUTY_LOG"] = $log
    $psi.EnvironmentVariables["HORDE_TURN_DUTY_TIMEOUT_MS"] = "4000"
    $psi.EnvironmentVariables["TD_MARKER"] = $marker
    $psi.EnvironmentVariables["TD_HOME_MARKER"] = $homeMarker
    $psi.EnvironmentVariables["HORDE_TURN_DUTY_CONFIG_DIR"] = $configDir
    $psi.EnvironmentVariables["HORDE_TURN_DUTY_HORDE_HOME"] = $home1
    $psi.EnvironmentVariables["USERPROFILE"] = $profileDir
    if ($psi.EnvironmentVariables.ContainsKey("HORDE_HOME")) { [void]$psi.EnvironmentVariables.Remove("HORDE_HOME") }
    $psi.EnvironmentVariables["TD_MODE"] = "never"
    $psi.EnvironmentVariables["TD_TASK"] = "never"
    $psi.EnvironmentVariables["TD_SNAP"] = "s1"
    foreach ($k in @("HORDE_TURN_DUTY_TEST_TASKLIST", "TD_CONFIRMED")) { if ($psi.EnvironmentVariables.ContainsKey($k)) { [void]$psi.EnvironmentVariables.Remove($k) } }
    foreach ($k in $Env.Keys) { if ($null -eq $Env[$k]) { if ($psi.EnvironmentVariables.ContainsKey($k)) { [void]$psi.EnvironmentVariables.Remove($k) } } else { $psi.EnvironmentVariables[$k] = $Env[$k] } }
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
function Payload { param([string]$Sid, [bool]$Active = $false) return (ConvertTo-Json -Compress -InputObject @{ session_id = $Sid; transcript_path = "x.jsonl"; cwd = $work; stop_hook_active = $Active; hook_event_name = "Stop" }) }
function Stop-Hook { param([string]$Sid, [hashtable]$Env = @{}, [bool]$Active = $false) return (Invoke-Hook (Payload $Sid $Active) $Env) }
function Test-Pass { param($R) return ($R.code -eq 0 -and $R.out -eq "" -and $R.err -eq "") }
function Get-Block {
    # The block, parsed, or $null when stdout is not exactly one block object.
    param($R)
    if ($R.code -ne 0 -or $R.out -eq "") { return $null }
    try { $o = $R.out | ConvertFrom-Json } catch { return $null }
    if ($o.decision -cne "block") { return $null }
    return $o
}

try {

Write-Host ""
Write-Host "--- CONTROL: the harness can tell a run from a non-run, and a block from a pass ---" -ForegroundColor Cyan
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"
$r = Stop-Hook $s
$b = Get-Block $r
Check ($null -ne $b -and (Ran)) "an Orc that never published is blocked, AND the stand-in ran (so a missing marker below means it was not spawned)"
Check ((Text $marker).Trim() -ceq "decisions published -Orc K -Json") "the hook asks for THIS Orc's list: decisions published -Orc K -Json"

Write-Host ""
Write-Host "--- the cheap paths spawn nothing ---" -ForegroundColor Cyan
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"
$r = Stop-Hook $s @{} $true
Check ((Test-Pass $r) -and -not (Ran) -and -not [System.IO.File]::Exists((State-Path $s))) "stop_hook_active true: exit 0, silent, nothing spawned, no state touched (it never loops)"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"; Put-State $s 5
$r = Stop-Hook $s
Check ((Test-Pass $r) -and -not (Ran)) "checked 5 minutes ago: exit 0, silent, nothing spawned (the throttle)"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"; Put-State $s -600
$r = Stop-Hook $s
Check ($null -ne (Get-Block $r) -and (Ran)) "a lastCheckedAt in the FUTURE (clock rollback) does not throttle: the check runs and blocks"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
[System.IO.File]::WriteAllText((State-Path $s), '{"lastCheckedAt":9999999999999,"lastBlockedAt":0}', $utf8)
$r = Stop-Hook $s
Check ($null -ne (Get-Block $r) -and (Ran)) "a corrupt lastCheckedAt of 9999999999999 does not silence the hook"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"; Put-State $s 31
$r = Stop-Hook $s
Check ($null -ne (Get-Block $r) -and (Ran)) "checked 31 minutes ago: the throttle is over, the check runs and blocks"
Reset-Marks
$s = New-Sid
$r = Stop-Hook $s
$st = Get-StateObj $s
Check ((Test-Pass $r) -and -not (Ran)) "a session not in the registry: exit 0, silent, nothing spawned"
Check ($null -ne $st -and $st.lastCheckedAt -gt 0 -and $st.lastBlockedAt -eq 0) "   and the check is recorded, so the registry is not read again every turn"
Reset-Marks
$s = New-Sid; Put-Session $s "warg" "K" "parent-1"
$r = Stop-Hook $s
Check ((Test-Pass $r) -and -not (Ran)) "a Warg (role warg, with a parent): exit 0, silent, nothing spawned"
Reset-Marks
$s = New-Sid; Put-Session $s "worker" "K" "parent-1"
$r = Stop-Hook $s
Check ((Test-Pass $r) -and -not (Ran)) "a role the hook does not know: left alone"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "lowercase" "parent-1"
$r = Stop-Hook $s
Check ((Test-Pass $r) -and -not (Ran)) "an Orc whose label is not a lane letter: left alone"

Write-Host ""
Write-Host "--- the Orcs and the Thrall ---" -ForegroundColor Cyan
Reset-Marks
$s = New-Sid; Put-Session $s "master" "M"
$r = Stop-Hook $s
Check ($null -ne (Get-Block $r) -and (Text $marker).Trim() -ceq "decisions published -Orc M -Json") "the Thrall (role master) that never published is blocked, asked for as M"
Reset-Marks
$s = New-Sid; Put-Session $s "master" "M"
$r = Stop-Hook $s @{ TD_MODE = "age:3" }
Check ((Test-Pass $r) -and (Ran)) "the Thrall that published 3 minutes ago passes"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"
$r = Stop-Hook $s @{ TD_MODE = "age:5" }
$st = Get-StateObj $s
Check ((Test-Pass $r) -and (Ran)) "an Orc that published 5 minutes ago passes"
Check ($null -ne $st -and $st.lastCheckedAt -gt 0 -and $st.lastBlockedAt -eq 0) "   and the check is recorded, with no block"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"
$r = Stop-Hook $s @{ TD_MODE = "age:45" }
$b = Get-Block $r
$st = Get-StateObj $s
Check ($null -ne $b) "an Orc whose list is 45 minutes old is blocked"
if ($null -ne $b) {
    $lines = @($b.reason -split "`n")
    Check ($lines[0] -ceq (First-Line "K")) "   the reason's first line is exactly: no published decisions list was found for Orc K in the last 30 minutes: ..."
    Check ($b.reason -cnotmatch '(?i)never') "   and it does not claim the list was never published (the verb cannot tell)"
    Check ($lines.Count -eq 4 -and $lines[1] -ceq ("run it in PowerShell as: `$env:HORDE_HOME='" + $home1 + "'; horde decisions publish -File <list.json>")) "   the second line is the exact runnable command, with the home"
    Check ($lines[2] -like 'list.json shape: *"items"*"text"*') "   the third line gives the file shape"
    Check ($lines[3] -ceq "if publish refuses because fleet.db has no row for your Orc, tell N") "   the fourth line says who to tell when publish refuses for want of a row"
    Check (@($b.PSObject.Properties).Count -eq 2) "   the block holds a decision and a reason and nothing else"
}
Check ($null -ne $st -and $st.lastCheckedAt -gt 0 -and $st.lastBlockedAt -gt 0) "   lastCheckedAt AND lastBlockedAt are recorded"
Reset-Marks
$r = Stop-Hook $s @{ TD_MODE = "age:45" }
Check ((Test-Pass $r) -and -not (Ran)) "the very next stop after a block passes, and spawns nothing (one block per 30 minutes)"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"
$r = Stop-Hook $s @{ TD_MODE = "otherorc" }
Check ($null -ne (Get-Block $r)) "a list published by ANOTHER Orc does not count for this one"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"
# The bytes are put on stdin by cmd's own redirection from a file, so exactly one byte-order mark arrives under
# either PowerShell (a redirected stdin of Windows PowerShell 5.1 adds one by itself, PowerShell 7 does not).
$bomFile = Join-Path $work "bom-payload.json"
[System.IO.File]::WriteAllBytes($bomFile, [byte[]](0xEF, 0xBB, 0xBF) + $utf8.GetBytes((Payload $s)))
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $env:ComSpec
$psi.Arguments = '/d /c ""' + $node.Source + '" "' + $hook + '" < "' + $bomFile + '""'
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
foreach ($kv in @{ HORDE_TURN_DUTY_STATE_DIR = $stateDir; HORDE_TURN_DUTY_REGISTRY = $registry; HORDE_TURN_DUTY_HORDE = $standin; HORDE_TURN_DUTY_LOG = $log; HORDE_TURN_DUTY_TIMEOUT_MS = "4000"; TD_MARKER = $marker; TD_MODE = "never"; HORDE_TURN_DUTY_HORDE_HOME = $home1; HORDE_TURN_DUTY_CONFIG_DIR = $configDir }.GetEnumerator()) { $psi.EnvironmentVariables[$kv.Key] = $kv.Value }
$p = [System.Diagnostics.Process]::Start($psi)
$errTask = $p.StandardError.ReadToEndAsync()
$out = $p.StandardOutput.ReadToEnd()
$p.WaitForExit()
$r = [pscustomobject]@{ code = $p.ExitCode; err = $errTask.Result; out = $out }
$p.Dispose()
Check ($null -ne (Get-Block $r)) "stdin that starts with a byte-order mark is read all the same"

Write-Host ""
Write-Host "--- a retired registry row is skipped like a Warg ---" -ForegroundColor Cyan
Reset-Marks
$sOld = New-Sid; Put-Session $sOld "orchestrator" "K" "parent-1" -Retired
$sNew = New-Sid; Put-Session $sNew "orchestrator" "K" "parent-1"
$r = Stop-Hook $sOld
Check ((Test-Pass $r) -and -not (Ran)) "a retired row (retired true, retiredAt set) of lane K: exit 0, silent, nothing spawned"
$r = Stop-Hook $sNew
Check ($null -ne (Get-Block $r) -and (Ran)) "   while the live row of the same lane K beside it is still blocked"
Reset-Marks
$sOldT = New-Sid; Put-Session $sOldT "master" "M" -Retired
$r = Stop-Hook $sOldT
Check ((Test-Pass $r) -and -not (Ran)) "a retired Thrall row: left alone too"

Write-Host ""
Write-Host "--- the Horde home: where the hook finds it, and what it does without one ---" -ForegroundColor Cyan
Clear-Config
function New-OrcSession { $x = New-Sid; Put-Session $x "orchestrator" "K" "parent-1"; return $x }
Reset-Marks
$s = New-OrcSession
$r = Stop-Hook $s @{ HORDE_TURN_DUTY_HORDE_HOME = $home1 }
Check ($null -ne (Get-Block $r) -and (Home-Seen) -ceq $home1) "HORDE_TURN_DUTY_HORDE_HOME alone: horde is run with HORDE_HOME set to it"
Reset-Marks
$s = New-OrcSession
$r = Stop-Hook $s @{ HORDE_TURN_DUTY_HORDE_HOME = $null; HORDE_HOME = $home2 }
$b = Get-Block $r
Check ($null -ne $b -and (Home-Seen) -ceq $home2) "HORDE_HOME alone: horde is run with it"
Check ($null -ne $b -and $b.reason -like ("*HORDE_HOME='" + $home2 + "'; horde decisions publish*")) "   and the block text carries that home"
Reset-Marks
Put-Config ('{"hordeHome": "' + $home3.Replace("\", "\\") + '"}')
$s = New-OrcSession
$r = Stop-Hook $s @{ HORDE_TURN_DUTY_HORDE_HOME = $null }
$b = Get-Block $r
Check ($null -ne $b -and (Home-Seen) -ceq $home3) "the config file alone (config.json, hordeHome): horde is run with it"
Check ($null -ne $b -and $b.reason -like ("*HORDE_HOME='" + $home3 + "'; horde decisions publish*")) "   and the block text carries that home"
Reset-Marks
$s = New-OrcSession
$r = Stop-Hook $s @{ HORDE_TURN_DUTY_HORDE_HOME = $home1; HORDE_HOME = $home2 }
Check ((Home-Seen) -ceq $home1) "precedence: HORDE_TURN_DUTY_HORDE_HOME beats HORDE_HOME and the config file"
Reset-Marks
$s = New-OrcSession
$r = Stop-Hook $s @{ HORDE_TURN_DUTY_HORDE_HOME = $null; HORDE_HOME = $home2 }
Check ((Home-Seen) -ceq $home2) "precedence: HORDE_HOME beats the config file"
Reset-Marks
$s = New-OrcSession
$r = Stop-Hook $s @{ HORDE_TURN_DUTY_HORDE_HOME = $null; HORDE_HOME = "" }
Check ((Home-Seen) -ceq $home3) "an empty HORDE_HOME is no home: the config file is used"

Write-Host ""
Write-Host "--- the home pointer file (T-0299): one rule for every resolver ---" -ForegroundColor Cyan
function Put-Pointer { param([string]$Json) [System.IO.File]::WriteAllText($pointerFile, $Json, $utf8) }
function Clear-Pointer { if (Test-Path -LiteralPath $pointerFile) { Remove-Item -LiteralPath $pointerFile -Force } }
function Pointer-Json { param([string]$Dir) return ('{"v":1,"hordeHome":"' + $Dir.Replace("\", "\\") + '"}') }
$noStateDir = @{ HORDE_TURN_DUTY_HORDE_HOME = $null; HORDE_TURN_DUTY_STATE_DIR = $null; HORDE_TURN_DUTY_CONFIG_DIR = $null }
Clear-Config
Reset-Marks
Put-Pointer (Pointer-Json $ptrHome1)
$s = New-OrcSession
$r = Stop-Hook $s $noStateDir
Check ($null -ne (Get-Block $r) -and (Home-Seen) -ceq $ptrHome1) "HORDE_HOME unset: the pointer file names the home horde is run with"
Check ([System.IO.File]::Exists((Join-Path $ptrHome1 ("turn-duty\" + $s + ".json")))) "   and the state folder follows it: <home>\turn-duty\<session>.json"
Reset-Marks
$s = New-OrcSession
$r = Stop-Hook $s ($noStateDir + @{ HORDE_HOME = $ptrHome2 })
Check ((Home-Seen) -ceq $ptrHome2 -and [System.IO.File]::Exists((Join-Path $ptrHome2 ("turn-duty\" + $s + ".json")))) "HORDE_HOME beats the pointer, for the home and for the state folder"
Reset-Marks
$s = New-OrcSession
$r = Stop-Hook $s @{ HORDE_TURN_DUTY_HORDE_HOME = $ptrHome2; HORDE_TURN_DUTY_STATE_DIR = $null; HORDE_TURN_DUTY_CONFIG_DIR = $null }
Check ((Home-Seen) -ceq $ptrHome2) "HORDE_TURN_DUTY_HORDE_HOME beats the pointer (K's override stays first)"
Check ([System.IO.File]::Exists((Join-Path $ptrHome2 ("turn-duty\" + $s + ".json")))) "   and the state folder follows it too"
Reset-Marks
Put-Pointer (Pointer-Json $ptrHome2)
$s = New-OrcSession
$r = Stop-Hook $s $noStateDir
Check ((Home-Seen) -ceq $ptrHome2) "the pointer is read on every stop: changed, the next stop follows it"
Reset-Marks
Put-Config ('{"hordeHome": "' + $home3.Replace("\", "\\") + '"}')
$s = New-OrcSession
$r = Stop-Hook $s $noStateDir
Check ((Home-Seen) -ceq $ptrHome2) "the pointer beats config.json hordeHome"
Clear-Config
Clear-Pointer
Reset-Marks
$s = New-OrcSession
$r = Stop-Hook $s $noStateDir
Check ((Test-Pass $r) -and -not (Ran) -and (Log-Lines) -eq 1) "no pointer and no home: pass, one log line (the old behavior)"
Check ([System.IO.File]::Exists((Join-Path $profileDir (".horde\turn-duty\" + $s + ".json")))) "   and the state folder is the old one, under the user profile"
foreach ($bad in @(
        @{ n = "v 2"; j = ('{"v":2,"hordeHome":"' + $ptrHome1.Replace("\", "\\") + '"}') }
        @{ n = "no hordeHome"; j = '{"v":1}' }
        @{ n = "a relative hordeHome"; j = '{"v":1,"hordeHome":"some\\folder"}' }
        @{ n = "a folder that is not there"; j = (Pointer-Json (Join-Path $work "no-such-folder")) }
        @{ n = "not JSON"; j = '{"v":1,' }
        @{ n = "non-ASCII"; j = ('{"v":1,"hordeHome":"' + $ptrHome1.Replace("\", "\\") + [char]0x00E9 + '"}') }
    )) {
    Reset-Marks
    Put-Pointer $bad.j
    Put-Config ('{"hordeHome": "' + $home3.Replace("\", "\\") + '"}')
    $s = New-OrcSession
    $r = Stop-Hook $s @{ HORDE_TURN_DUTY_HORDE_HOME = $null; HORDE_TURN_DUTY_STATE_DIR = $null }
    $logText = $(if ([System.IO.File]::Exists($log)) { Text $log } else { "" })
    Check ((Test-Pass $r) -and -not (Ran) -and (Log-Lines) -eq 1 -and $logText.Contains($pointerFile)) ("a bad pointer (" + $bad.n + ") is refused by name in the log, not skipped for config.json: pass, nothing spawned")
}
Clear-Pointer
Clear-Config
Clear-Config
foreach ($c in @(
        @{ n = "no home anywhere"; cfg = $null }
        @{ n = "a config file that is not JSON"; cfg = "{not json" }
        @{ n = "a config file with no hordeHome"; cfg = '{"other": 1}' }
        @{ n = "a config file whose hordeHome is not an absolute path"; cfg = '{"hordeHome": "relative\\home"}' }
        # THE SAME RULE FOR THE ENVIRONMENT (second review of T-0319): a relative or drive-rooted home would resolve
        # against the hook's folder, and a line break would split the printed command.
        @{ n = "a relative HORDE_HOME"; cfg = $null; env = @{ HORDE_HOME = "relative\home" } }
        @{ n = "a drive-rooted HORDE_HOME with no drive"; cfg = $null; env = @{ HORDE_HOME = "\rooted\home" } }
        @{ n = "a HORDE_TURN_DUTY_HORDE_HOME holding a line break"; cfg = $null; env = @{ HORDE_TURN_DUTY_HORDE_HOME = ("C:\a" + [char]10 + "b") } }
    )) {
    Clear-Config
    if ($null -ne $c.cfg) { Put-Config $c.cfg }
    Reset-Marks
    $s = New-OrcSession
    $envFor = @{ HORDE_TURN_DUTY_HORDE_HOME = $null }
    if ($null -ne $c.env) { foreach ($k in $c.env.Keys) { $envFor[$k] = $c.env[$k] } }
    $r = Stop-Hook $s $envFor
    $st = Get-StateObj $s
    Check ((Test-Pass $r) -and -not (Ran) -and (Log-Lines) -eq 1) ("exit 0, silent, nothing spawned, one log line: " + $c.n)
    Check ($null -ne $st -and $st.lastCheckedAt -gt 0 -and $st.lastBlockedAt -eq 0) ("   and the check is recorded: " + $c.n)
}
Clear-Config
Reset-Marks
$s = New-OrcSession
$odd = "C:\fleet's home"
$r = Stop-Hook $s @{ HORDE_TURN_DUTY_HORDE_HOME = $odd }
$b = Get-Block $r
Check ($null -ne $b -and $b.reason -like ("*HORDE_HOME='C:\fleet''s home'; horde decisions publish*")) "a home with an apostrophe is quoted for PowerShell (the apostrophe doubled)"
Reset-Marks
$s = New-OrcSession
$curly = [string][char]0x2019
$r = Stop-Hook $s @{ HORDE_TURN_DUTY_HORDE_HOME = ("C:\fleet" + $curly + "s home") }
$b = Get-Block $r
Check ($null -ne $b -and $b.reason.Contains("HORDE_HOME='C:\fleet" + $curly + $curly + "s home'")) "a curly apostrophe, which PowerShell also reads as a quote, is doubled too"
Write-Host ""
Write-Host "--- an unchanged list is asked about once; a confirmed list is fresh ---" -ForegroundColor Cyan
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"
$r = Stop-Hook $s @{ TD_MODE = "age:45"; TD_SNAP = "snapA" }
$st = Get-StateObj $s
Check ($null -ne (Get-Block $r) -and $st.lastBlockedSnapshot -ceq "snapA") "a block records the snapshot id it saw (lastBlockedSnapshot)"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"; Put-BlockedState $s 40 "snapA"
$r = Stop-Hook $s @{ TD_MODE = "age:200"; TD_SNAP = "snapA" }
$st = Get-StateObj $s
Check ((Test-Pass $r) -and (Ran)) "the SAME snapshot, blocked 40 minutes ago: pass, no block"
Check ($null -ne $st -and $st.lastCheckedAt -gt ([datetimeoffset]::UtcNow.AddMinutes(-1).ToUnixTimeMilliseconds()) -and $st.lastBlockedSnapshot -ceq "snapA") "   the check is recorded and the snapshot is kept"
Check ($null -ne $st -and $st.lastDecisionsBlockedAt -lt ([datetimeoffset]::UtcNow.AddMinutes(-30).ToUnixTimeMilliseconds())) "   and lastDecisionsBlockedAt is NOT moved by a pass (the 4 hours run from the real block)"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"; Put-BlockedState $s 230 "snapA"
$r = Stop-Hook $s @{ TD_MODE = "age:400"; TD_SNAP = "snapA" }
Check (Test-Pass $r) "the same snapshot blocked 230 minutes ago (inside 4 hours): still a pass"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"; Put-BlockedState $s 250 "snapA"
$r = Stop-Hook $s @{ TD_MODE = "age:400"; TD_SNAP = "snapA" }
Check ($null -ne (Get-Block $r)) "the same snapshot blocked 250 minutes ago (past 4 hours): one block again"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"; Put-BlockedState $s 40 "snapA"
$r = Stop-Hook $s @{ TD_MODE = "age:200"; TD_SNAP = "snapB" }
$st = Get-StateObj $s
Check ($null -ne (Get-Block $r) -and $st.lastBlockedSnapshot -ceq "snapB") "a NEW snapshot with an old publishedAt: blocked, and the new snapshot is remembered"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"; Put-BlockedState $s 40 "snapA"
$r = Stop-Hook $s @{ TD_MODE = "never" }
Check ($null -ne (Get-Block $r)) "no list at all after a block: still blocked (no snapshot to match)"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"; Put-BlockedState $s 40 ""
$r = Stop-Hook $s @{ TD_MODE = "age:200"; TD_SNAP = "none" }
Check ($null -ne (Get-Block $r)) "a list with no snapshot id never matches an empty remembered one"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"
$r = Stop-Hook $s @{ TD_MODE = "age:200"; TD_CONFIRMED = "5" }
Check ((Test-Pass $r) -and (Ran)) "confirmedAt 5 minutes ago beats a publishedAt 200 minutes old: pass"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"
$r = Stop-Hook $s @{ TD_MODE = "age:5"; TD_CONFIRMED = "200" }
Check (Test-Pass $r) "a recent publishedAt is not made stale by an older confirmedAt (the newer wins)"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"
$r = Stop-Hook $s @{ TD_MODE = "age:200"; TD_CONFIRMED = "90" }
Check ($null -ne (Get-Block $r)) "confirmedAt 90 minutes ago and publishedAt 200: blocked"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"
$r = Stop-Hook $s @{ TD_MODE = "age:200"; TD_CONFIRMED = "bad" }
Check ($null -ne (Get-Block $r)) "a malformed confirmedAt is ignored: publishedAt decides"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"
$r = Stop-Hook $s @{ TD_MODE = "age:5"; TD_CONFIRMED = "bad" }
Check (Test-Pass $r) "   and a malformed confirmedAt does not spoil a fresh publishedAt"

Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"
$r = Stop-Hook $s @{ TD_MODE = "age:200"; TD_SNAP = "snapA" }
$st = Get-StateObj $s
Check ($null -ne (Get-Block $r) -and $st.lastDecisionsBlockedAt -gt 0) "a decisions block records lastDecisionsBlockedAt"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
$ms31 = [long]([datetimeoffset]::UtcNow.AddMinutes(-31).ToUnixTimeMilliseconds())
[System.IO.File]::WriteAllText((State-Path $s), ('{"lastCheckedAt":' + $ms31 + ',"lastBlockedAt":' + [long]([datetimeoffset]::UtcNow.AddMinutes(-40).ToUnixTimeMilliseconds()) + ',"lastBlockedSnapshot":"snapA"}'), $utf8)
$r = Stop-Hook $s @{ TD_MODE = "age:200"; TD_SNAP = "snapA" }
Check ($null -ne (Get-Block $r)) "an old state file with no lastDecisionsBlockedAt reads as never blocked: blocks"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"; Put-BlockedState $s -600 "snapA"
$r = Stop-Hook $s @{ TD_MODE = "age:200"; TD_SNAP = "snapA" }
Check ($null -ne (Get-Block $r)) "a block time in the FUTURE never counts as recent: blocks"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"; Put-BlockedState $s 40 "snapA"
$r = Stop-Hook $s @{ TD_MODE = "age:200"; TD_SNAP = "snapA"; TD_TASK = "age:200"; HORDE_TURN_DUTY_TEST_TASKLIST = "1" }
$st = Get-StateObj $s
Check ($null -ne (Get-Block $r) -and $st.lastDecisionsBlockedAt -lt ([datetimeoffset]::UtcNow.AddMinutes(-30).ToUnixTimeMilliseconds()) -and $st.lastBlockedSnapshot -ceq "snapA") "a task-list-only block does not move the decisions quiet window or snapshot"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"; Put-BlockedState $s 40 "snapA"
$r = Stop-Hook $s @{ TD_MODE = "age:5"; TD_SNAP = "snapA" }
$st = Get-StateObj $s
Check ((Test-Pass $r) -and $st.lastBlockedSnapshot -ceq "") "a list that passes as fresh clears the remembered snapshot"
Write-Host ""
Write-Host "--- times that cannot be trusted are ignored ---" -ForegroundColor Cyan
foreach ($c in @(
        @{ n = "a publishedAt 100 days in the future"; env = @{ TD_MODE = "age:-144000" } }
        @{ n = "a publishedAt of year 9999"; env = @{ TD_MODE = "rawpub:9999-01-01T00:00:00Z" } }
        @{ n = "a confirmedAt 100 days in the future beside an old publishedAt"; env = @{ TD_MODE = "age:200"; TD_CONFIRMED = "-144000" } }
        @{ n = "a publishedAt that is only a year (2026)"; env = @{ TD_MODE = "rawpub:2026" } }
        @{ n = "a publishedAt that is a bare number (1)"; env = @{ TD_MODE = "rawpub:1" } }
        @{ n = "a publishedAt in a loose date form (Oct 30 2099)"; env = @{ TD_MODE = "rawpub:Oct 30 2099" } }
        @{ n = "a confirmedAt in a loose date form beside an old publishedAt"; env = @{ TD_MODE = "age:200"; TD_CONFIRMED = ("raw:" + (Get-Date).ToUniversalTime().ToString("r", [cultureinfo]::InvariantCulture)) } }
    )) {
    Reset-Marks
    $s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"
    $r = Stop-Hook $s $c.env
    Check ($null -ne (Get-Block $r)) ("ignored, no usable time is stale (never a kill switch): blocks: " + $c.n)
}
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"
$r = Stop-Hook $s @{ TD_MODE = "age:5"; TD_CONFIRMED = "raw:2026-13-45T99:99:99Z" }
Check (Test-Pass $r) "an ISO-shaped but impossible confirmedAt is ignored, a fresh publishedAt still passes"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"
$r = Stop-Hook $s @{ TD_MODE = "age:-1" }
Check (Test-Pass $r) "a publishedAt 1 minute ahead (clock skew within 2 minutes) still counts"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"
$r = Stop-Hook $s @{ TD_MODE = "age:-5" }
Check ($null -ne (Get-Block $r)) "a publishedAt 5 minutes ahead is ignored: no usable time, stale, blocks"

Write-Host ""
Write-Host "--- the state is written BEFORE the block ---" -ForegroundColor Cyan
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"
$r = Stop-Hook $s @{ HORDE_TURN_DUTY_STATE_DIR = $stateDir }
Check ($null -ne (Get-Block $r) -and [System.IO.File]::Exists((State-Path $s))) "after a block the state file exists"
Reset-Marks
$blockedPath = Join-Path $work "state-is-a-file"
[System.IO.File]::WriteAllText($blockedPath, "x", $utf8)
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"
$r = Stop-Hook $s @{ HORDE_TURN_DUTY_STATE_DIR = $blockedPath }
Check ((Test-Pass $r) -and (Ran) -and (Log-Lines) -ge 1) "a state folder that cannot be written: NO block (it could not be remembered), logged"

Write-Host ""
Write-Host "--- it fails open ---" -ForegroundColor Cyan
foreach ($c in @(
        @{ n = "fleet.db missing (the verb says run horde db init)"; env = @{ TD_MODE = "dbmissing" } }
        @{ n = "the verb past the timeout"; env = @{ TD_MODE = "hang" } }
        @{ n = "output that is not JSON"; env = @{ TD_MODE = "badjson" } }
        @{ n = "horde not found"; env = @{ HORDE_TURN_DUTY_HORDE = (Join-Path $work "no-such-horde.cmd") } }
    )) {
    Reset-Marks
    $s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"
    $r = Stop-Hook $s $c.env
    $st = Get-StateObj $s
    Check ((Test-Pass $r) -and (Log-Lines) -eq 1) ("exit 0, silent, exactly one log line: " + $c.n)
    Check ($null -ne $st -and $st.lastCheckedAt -gt 0 -and $st.lastBlockedAt -eq 0) ("   the check is recorded, so it is not retried every turn: " + $c.n)
    Reset-Marks
    $r = Stop-Hook $s $c.env
    Check ((Test-Pass $r) -and -not (Ran)) ("   and the next stop spawns nothing: " + $c.n)
}
foreach ($bad in @(@{ n = "malformed JSON"; s = "{not json" }, @{ n = "empty stdin"; s = "" }, @{ n = "a JSON array"; s = "[1,2]" }, @{ n = "a session id that is a path"; s = '{"session_id":"..\\..\\x"}' }, @{ n = "no session id"; s = '{"hook_event_name":"Stop"}' })) {
    Reset-Marks
    $r = Invoke-Hook $bad.s
    Check ((Test-Pass $r) -and -not (Ran) -and (Log-Lines) -eq 1) ("exit 0, silent, nothing spawned, one log line: " + $bad.n)
}

Write-Host ""
Write-Host "--- the task-list check: off until its writer exists, and ONE block when both fail ---" -ForegroundColor Cyan
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"
$r = Stop-Hook $s @{ TD_MODE = "age:2"; TD_TASK = "never" }
Check ((Test-Pass $r) -and -not ((Ran) -and (Text $marker) -match 'tasklist')) "decisions fresh and the task list never written, check OFF: pass, the task verb is never asked"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"
$r = Stop-Hook $s @{ TD_MODE = "age:2"; TD_TASK = "never"; HORDE_TURN_DUTY_TEST_TASKLIST = "1" }
$b = Get-Block $r
Check ($null -ne $b -and $b.reason -match 'numbered task list' -and $b.reason -cnotmatch 'no published decisions list was found') "check ON, only the task list due: a block with the task-list reason alone"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"
$r = Stop-Hook $s @{ TD_MODE = "age:50"; TD_TASK = "age:50"; HORDE_TURN_DUTY_TEST_TASKLIST = "1" }
$b = Get-Block $r
Check ($null -ne $b -and $b.reason -match 'no published decisions list was found' -and $b.reason -match 'numbered task list') "both due: one block holding both reasons"
Reset-Marks
$r = Stop-Hook $s @{ TD_MODE = "age:50"; TD_TASK = "age:50"; HORDE_TURN_DUTY_TEST_TASKLIST = "1" }
Check ((Test-Pass $r) -and -not (Ran)) "   and the stop right after passes"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"
$r = Stop-Hook $s @{ TD_MODE = "age:50"; TD_TASK = "dbmissing"; HORDE_TURN_DUTY_TEST_TASKLIST = "1" }
$b = Get-Block $r
Check ($null -ne $b -and $b.reason -match 'no published decisions list was found' -and $b.reason -cnotmatch 'numbered task list' -and (Log-Lines) -eq 1) "one check cannot tell (logged), the other is due: the block holds only the due one"
Reset-Marks
$s = New-Sid; Put-Session $s "orchestrator" "K" "parent-1"
$r = Stop-Hook $s @{ TD_MODE = "age:2"; TD_TASK = "age:2"; HORDE_TURN_DUTY_TEST_TASKLIST = "1" }
Check (Test-Pass $r) "both checks done: pass"

} finally {
    if ((Split-Path -Leaf $work) -match '\Ahorde-turn-duty-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force }
}

Complete-HordeSuite -Success "the turn-duty hook blocks an Orc or the Thrall once per 30 minutes for an unpublished list, passes everyone else, and fails open"
