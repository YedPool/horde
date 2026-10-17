# END TO END: `horde fleet record` and `horde fleet wake`, driven at the real command line, against a
# terminal this scenario starts - never the one in use.
#
# CONTRIBUTING 2 asks one scenario per user-facing command; this is the one for hibernation. The terminal
# is an instance of its own (Isolation.ps1: its own gui and mux, --skip-config, the socket pin,
# --no-auto-start), and nothing is spawned before Assert-HordeIsolated has measured that this process can
# see only that instance's panes; the run is abandoned if it can see more. Every running gui is listed
# before and after, and the list must be the same.
#
# NO REAL AGENT SESSION IS STARTED. Each "session" is a stand-in script that does what a wake depends on
# and nothing else - it writes a control file (pid, sessionId, cwd, procStart: what the harness's liveness
# adapter reads), stays running, and ends on /exit (removing its file) or with its pane. It runs no hook,
# so it writes nothing of the harness's own state; it refuses to write anything unless the profile it sees
# is this scenario's (a marker file). Every pane runs it BY ITS FULL PATH: the scenario's own spawns name
# it, and the wake is told it through the harness adapter's setting (claude-code-fleet: command). A PATH
# cannot do this: a pane takes its PATH from the terminal, not from the process that spawns it - measured by
# this scenario's own first runs on 2026-10-16, when a stand-in first on the spawning PATH lost to the real
# command in all four panes (which stopped at its first-run screen, under the scenario's empty profile and
# config, and went with the terminal). Before the real wake, its dry run must show the stand-in's path in
# every spawn and no bare command, or the wake is not run.
#
# NOTHING REAL IS READ OR WRITTEN BY THE COMMANDS. Each is started with HORDE_HOME, WEZFLEET_ROOT (the
# fleet registry and the fleet's mail) and USERPROFILE (the harness's control files, and the terminal's
# socket folder as the fleet's mail reads it) pointed at folders of this scenario's, and the harness's
# config folder at an empty one. The terminal to wake into is named by the host's setting
# (wezterm-fleet: socket), because this user's own terminal is refused whenever two run. The wake's mail
# goes through the REAL fleet mail command found on PATH (the same path a person's horde uses), so it is
# written into this scenario's mail folder; that command's knock finds no terminal under this scenario's
# profile and types nothing.
#
# THE KNOWN TRAP (the old system's lesson, Isolation.ps1's header): a real session in an isolated
# terminal still runs the person's hooks and writes the person's pane-sessions files, whose names are pane
# ids that a fresh mux reuses (0, 1, 2...). The stand-in runs no hook. And the person's pane-sessions
# folder is read before and after: no file may appear or go, none may change hands to another session,
# and none may name a session or folder of this scenario's. (Its live sessions rewrite their own files
# on every turn, so contents of an unchanged occupant may change; they are counted, not failed.)
#
# WHAT IT PROVES, in order:
#   1. record: one Orc and two Wargs, the Wargs parented to the Orc and sharing its folder, the second
#      Warg split beside the first in a second tab; a master stand-in runs too and is not recorded. The
#      record holds the three, their roles, parents, placement and each one's process.
#   2. the stand-ins exit; wake: ONE new window, the Orc in its first tab, the Wargs in a second tab
#      split as saved; each pane runs the resume command for the right id in the right folder, with the
#      waking session's own variables scrubbed; every state goes to woken; the wake mail of each is in
#      the fleet's mail folder.
#   3. a second wake of the same id refuses all three (they run) and spawns nothing.
#   4. with one stand-in left running, a wake refuses that one only and wakes the other two.
#   5. it measures how long a stand-in takes to show up running after its spawn, and prints it beside
#      the wake's own wait bound.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "hosts\wezterm\test\Isolation.ps1")
. (Join-Path $root "core\Tristate.ps1")
. (Join-Path $root "core\HostAct.ps1")
. (Join-Path $root "hosts\wezterm\Fleet.ps1")
# The harness runs under Continue: it calls the terminal with 2>$null, which Stop turns into a throw on
# PowerShell 5.1 (test/e2e/e2e-cli.ps1 has the measurement). Checks report failures, not exceptions.
$ErrorActionPreference = "Continue"

function Section { param([string]$Title) Write-Host ""; Write-Host ("=== " + $Title + " ===") -ForegroundColor Cyan }
function Wait-Until { param([scriptblock]$Cond, [int]$Seconds) $d = (Get-Date).AddSeconds($Seconds); while ((Get-Date) -lt $d) { if (& $Cond) { return $true }; Start-Sleep -Milliseconds 200 }; return [bool](& $Cond) }

# ---- the scenario's own folders -------------------------------------------------------------------
$realProfile = "" + $env:USERPROFILE
$work = Join-Path $env:TEMP ("horde-e2e-fleet-" + [guid]::NewGuid().ToString("N"))
$hordeHome = Join-Path $work "home"
$fleetRoot = Join-Path $work "fleet"
$profileDir = Join-Path $work "profile"
$binDir = Join-Path $work "bin"
$cfgDir = Join-Path $work "config"
$lane = Join-Path $work "lanes\orc"
$masterLane = Join-Path $work "lanes\master"
$sessDir = Join-Path $profileDir ".claude\sessions"
$logDir = Join-Path $profileDir "standin-log"
foreach ($d in @($hordeHome, (Join-Path $hordeHome "settings"), (Join-Path $fleetRoot "registry\sessions"), $sessDir, $logDir, $binDir, $cfgDir, $lane, $masterLane)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
$marker = Join-Path $profileDir "horde-e2e-fleet-profile.marker"
[System.IO.File]::WriteAllText($marker, "this profile belongs to test/e2e/e2e-fleet.ps1")
# AN EMPTY TERMINAL CONFIG OF THE SCENARIO'S OWN (T-0216). A wezterm `cli` call, like any wezterm start, loads
# the person's config, and under this scenario's profile its plugin manager clones a plugin into the profile;
# a clone client then held the scenario's folder for over 60 s (seen 2026-10-16), so its removal failed.
# WEZTERM_CONFIG_FILE replaces the search for a config (`wezterm --help`: --config-file, "overrides the normal
# configuration file resolution"), so every command and pane of the scenario loads this empty file and
# nothing else; the harness's own cli calls also pass --skip-config (hosts/wezterm/test/Isolation.ps1).
$emptyWeztermConfig = Join-Path $work "wezterm-empty.lua"
[System.IO.File]::WriteAllText($emptyWeztermConfig, "return {}`n")
$ids = @{}
foreach ($l in @("M", "Q", "Q1", "Q2")) { $ids[$l] = [guid]::NewGuid().ToString() }

# THE STAND-IN, written as the harness's command, first on PATH.
$standIn = @'
# A stand-in for the agent harness, written by test/e2e/e2e-fleet.ps1. Test-only.
$marker = Join-Path $env:USERPROFILE "horde-e2e-fleet-profile.marker"
if (-not (Test-Path -LiteralPath $marker)) { Write-Host "STANDIN REFUSED: this is not the scenario's profile, so nothing is written"; exit 3 }
$id = ""; $mode = ""
for ($i = 0; $i -lt $args.Count - 1; $i++) { if ("" + $args[$i] -ceq "--resume" -or "" + $args[$i] -ceq "--session-id") { $mode = "" + $args[$i]; $id = "" + $args[$i + 1] } }
if ($id -cnotmatch '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z') { Write-Host "STANDIN REFUSED: no session id"; exit 4 }
$start = "" + (Get-Process -Id $PID).StartTime.ToFileTimeUtc()
$dir = Join-Path $env:USERPROFILE ".claude\sessions"
$ctl = Join-Path $dir ("" + $PID + ".json")
$cwd = (Get-Location).Path
$json = '{"pid":' + $PID + ',"sessionId":"' + $id + '","cwd":' + (ConvertTo-Json -InputObject $cwd) + ',"procStart":"' + $start + '","kind":"interactive"}'
$tmp = $ctl + ".tmp"
[System.IO.File]::WriteAllText($tmp, $json)
Move-Item -LiteralPath $tmp -Destination $ctl -Force
$written = "" + [DateTime]::UtcNow.ToFileTimeUtc()
# As the fleet's own hook does when a session starts: its registry row names the pane it now runs in.
$row = Join-Path ("" + $env:WEZFLEET_ROOT) ("registry\sessions\" + $id + ".json")
if ("" + $env:WEZFLEET_ROOT -ne "" -and (Test-Path -LiteralPath $row)) {
    $r = [System.IO.File]::ReadAllText($row) | ConvertFrom-Json
    $r.pane = "" + $env:WEZTERM_PANE
    [System.IO.File]::WriteAllText($row, (ConvertTo-Json -InputObject $r))
}
$log = [ordered]@{ pid = $PID; id = $id; mode = $mode; argv = @($args | ForEach-Object { "" + $_ }); cwd = $cwd; pane = "" + $env:WEZTERM_PANE; procStart = $start; writtenAt = $written; hasOwnVariables = [bool]("" + $env:CLAUDECODE -ne ""); profile = "" + $env:USERPROFILE }
[System.IO.File]::WriteAllText((Join-Path (Join-Path $env:USERPROFILE "standin-log") ("" + $PID + "-" + $id + ".json")), (ConvertTo-Json -InputObject $log -Compress))
Write-Host ("STANDIN-READY " + $id)
while ($true) {
    $l = [Console]::ReadLine()
    if ($null -eq $l) { Start-Sleep -Seconds 1; continue }
    if ($l.Trim() -ceq "/exit") { break }
}
Remove-Item -LiteralPath $ctl -Force -ErrorAction SilentlyContinue
[System.IO.File]::WriteAllText((Join-Path (Join-Path $env:USERPROFILE "standin-log") ("" + $PID + "-" + $id + ".exited")), $written)
Write-Host "STANDIN-EXIT"
'@
$command = "claude"
$standInPath = Join-Path $binDir "standin-agent.ps1"
[System.IO.File]::WriteAllText($standInPath, $standIn)

# What every pane and every command of this scenario is given. A name mapped to $null is removed.
# A SECOND GUARD, for the commands this scenario runs itself (not the panes, whose PATH is the terminal's):
# every folder that holds the harness's command is left out of their PATH, so they cannot find it at all.
$realDirs = @(Get-Command $command -All -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | ForEach-Object { (Split-Path -Parent $_.Source).TrimEnd([char]92).ToLowerInvariant() } | Sort-Object -Unique)
$keptPath = @($env:PATH -split ';' | Where-Object { $_.Trim() -ne "" -and $realDirs -notcontains $_.Trim().TrimEnd([char]92).ToLowerInvariant() })
$childEnv = [ordered]@{ HORDE_HOME = $hordeHome; WEZFLEET_ROOT = $fleetRoot; USERPROFILE = $profileDir; CLAUDE_CONFIG_DIR = $cfgDir; WEZTERM_CONFIG_FILE = $emptyWeztermConfig; PATH = ((@($binDir) + $keptPath) -join ";") }

function Invoke-WithChildEnv {
    # Run -Do with this process's environment set as a child's, and put it back after, whatever happens:
    # a pane gets the environment of the process that runs `cli spawn` (Isolation.ps1's header).
    param([scriptblock]$Do)
    $saved = @{}
    foreach ($k in @($childEnv.Keys)) { $saved[$k] = [System.Environment]::GetEnvironmentVariable($k, "Process") }
    try {
        foreach ($k in @($childEnv.Keys)) { [System.Environment]::SetEnvironmentVariable($k, $childEnv[$k], "Process") }
        return (& $Do)
    } finally {
        foreach ($k in @($saved.Keys)) { [System.Environment]::SetEnvironmentVariable($k, $saved[$k], "Process") }
    }
}

function Invoke-Horde {
    # The shipped horde.ps1, as its own process, with the scenario's environment. { code; out; secs }.
    param([string[]]$HordeArgs)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = [System.IO.Path]::Combine([System.Environment]::SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe")
    $quoted = @($HordeArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } })
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"" + (Join-Path $root "horde.ps1") + "`" " + ($quoted -join " ")
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardInput = $true
    foreach ($k in @($childEnv.Keys)) { $psi.EnvironmentVariables[$k] = "" + $childEnv[$k] }
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(600000)) { try { $p.Kill() } catch { }; return [pscustomobject]@{ code = -1; out = "(did not end in 600 s)"; secs = 600 } }
    $p.WaitForExit()
    $r = [pscustomobject]@{ code = $p.ExitCode; out = ("" + $out.Result + "`n" + $err.Result); secs = [Math]::Round($clock.Elapsed.TotalSeconds, 1) }
    $p.Dispose()
    return $r
}

function ConvertTo-HordeFleetE2eFolder { param([string]$Path) $n = $Path.Replace([string][char]92, "/"); if ($n -cmatch '\A/[A-Za-z]:') { $n = $n.Substring(1) }; return $n.TrimEnd("/").ToLowerInvariant() }
function Get-Panes { return @(ConvertFrom-HordeWeztermJson -Raw (Invoke-HordeWeztermCli -Rest @("list", "--format", "json"))) }
function Get-Control { param([string]$Id) foreach ($f in @(Get-ChildItem -LiteralPath $sessDir -Filter "*.json" -File -ErrorAction SilentlyContinue)) { try { $j = [System.IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json; if ("" + $j.sessionId -ceq $Id) { return $j } } catch { } }; return $null }
function Get-StandInLogs { param([string]$Id) return @(Get-ChildItem -LiteralPath $logDir -Filter ("*-" + $Id + ".json") -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) | ConvertFrom-Json }) }
function Get-StandInMs { param($Log) return [Math]::Round(([long]$Log.writtenAt - [long]$Log.procStart) / 10000.0) }
function Read-Record { param([string]$Hid) $p = Join-Path $hordeHome ("fleet\hibernations\" + $Hid + "\record.json"); if (-not (Test-Path -LiteralPath $p)) { return $null }; return ([System.IO.File]::ReadAllText($p) | ConvertFrom-Json) }
function Get-Sess { param($Rec, [string]$L) return @($Rec.sessions | Where-Object { "" + $_.label -ceq $L })[0] }
function Stop-StandIn {
    # /exit typed into the stand-in's pane, as a person ends a session; then its control file must go.
    param([string]$Pane, [string]$Id)
    [void](Invoke-HordeWeztermCli -Rest @("send-text", "--pane-id", $Pane, "--no-paste", "/exit`r"))
    return (Wait-Until { $null -eq (Get-Control $Id) } 20)
}
function Read-PaneSessions {
    # The person's pane-sessions folder, read only: file name -> { hash; occupant }.
    $dir = Join-Path $realProfile ".claude\pane-sessions"
    $map = @{}
    if (-not (Test-Path -LiteralPath $dir)) { return $map }
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)) {
        $text = ""
        try { $text = [System.IO.File]::ReadAllText($f.FullName) } catch { $text = "(unreadable)" }
        $sid = ""
        $m = [regex]::Match($text, '"session_id"\s*:\s*"([^"]*)"')
        if ($m.Success) { $sid = $m.Groups[1].Value }
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hash = [Convert]::ToBase64String($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text)))
        $sha.Dispose()
        $mine = $false
        foreach ($v in @($ids.Values) + @($work)) { if ($text.IndexOf($v, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $mine = $true } }
        $map[$f.Name] = [pscustomobject]@{ hash = $hash; occupant = $sid; mine = $mine }
    }
    return $map
}

$paneSessionsBefore = Read-PaneSessions
$guisBefore = (@(Get-HordeWeztermGuiPids | Sort-Object) -join ",")
$origSocket = $env:WEZTERM_UNIX_SOCKET
$measure = [ordered]@{ firstStartMs = @(); wokenStartMs = @(); wakeWaitBound = $null }

Section "before any terminal: the stand-in is what the harness's command finds"
# The same shell the wake will choose (hosts/wezterm/Fleet.ps1): the installed PowerShell 7 first.
$pwsh = Resolve-HordeWeztermFleetShell
Check ($pwsh.state -ceq "known") ("the shell a woken pane runs is found (" + $(if ($pwsh.state -ceq "known") { $pwsh.value } else { $pwsh.reason }) + ")")
$found = ""
if ($pwsh.state -ceq "known") {
    $found = (@(Invoke-WithChildEnv { & $pwsh.value -NoLogo -NoProfile -NonInteractive -Command ("@(Get-Command " + $command + " -All -ErrorAction SilentlyContinue | ForEach-Object { `$_.Source }) -join '|'") }) -join "").Trim()
    $found51 = (@(Invoke-WithChildEnv { @(Get-Command $command -All -ErrorAction SilentlyContinue | ForEach-Object { $_.Source }) -join "|" }) -join "").Trim()
}
$safe = ($found -ceq "" -and $found51 -ceq "")
Check $safe ("CONTROL: with the scenario's PATH, neither shell finds the harness's command at all (pwsh: '" + $found + "'; 5.1: '" + $found51 + "'; folders taken off the PATH: " + ($realDirs -join ", ") + ")")
$wezfleet = @(Get-Command wezfleet -ErrorAction SilentlyContinue | Select-Object -First 1)
Check ($wezfleet.Count -eq 1) ("the fleet's real mail command is on PATH, for the wake mail (" + $(if ($wezfleet.Count -eq 1) { $wezfleet[0].Source } else { "none" }) + ")")

$iso = $null
$result = $null
if ($safe -and $pwsh.state -ceq "known") { $iso = Start-HordeIsolatedWezterm -TimeoutSeconds 45 }
Check ($null -ne $iso) "an isolated instance started and answered"
if ($null -ne $iso) {
    try {
        $count = $null
        try { $count = Assert-HordeIsolated -Instance $iso } catch { Write-Host ("         " + $_.Exception.Message) -ForegroundColor Red }
        Check ($count -eq 1) "THE CONTROL: this process sees only the isolated instance, exactly one pane, in its own instance"
        Check (@($guisBefore -split "," | Where-Object { $_ -ne "" }) -notcontains ("" + $iso.pid)) "the instance's gui is a process that was not running before"
        if ($count -ne 1) { throw "not isolated: the scenario is abandoned before it spawns anything" }
        $envOk = $false
        $spawnLikeScenario = { param($prog, $argv, $cwd) Invoke-WithChildEnv { Invoke-HordeWeztermCli -Rest (@("spawn", "--cwd", $cwd, "--", $prog) + @($argv)) } }
        try { $envOk = Assert-HordePaneEnvironment -Instance $iso -Variables @{ USERPROFILE = $profileDir; HORDE_HOME = $hordeHome; WEZFLEET_ROOT = $fleetRoot; CLAUDE_CONFIG_DIR = $cfgDir } -Tool (Get-HordePaneTool) -Spawn $spawnLikeScenario } catch { Write-Host ("         " + $_.Exception.Message) -ForegroundColor Red }
        Check ($envOk -eq $true) "a pane spawned as the stand-ins are sees the scenario's profile, home, fleet and config folder (Assert-HordePaneEnvironment)"
        if ($envOk -ne $true) { throw "the pane environment is not proven: nothing is started" }
        $instance = Split-Path -Leaf $iso.socket
        $paneZero = "" + @(Get-Panes)[0].pane_id

        Section "1. a fleet of stand-ins, and horde fleet record"
        $start = { param([string]$L, [string[]]$Where, [string]$Cwd)
            $clock = [System.Diagnostics.Stopwatch]::StartNew()
            $out = Invoke-WithChildEnv { Invoke-HordeWeztermCli -Rest (@($Where) + @("--cwd", $Cwd, "--", $pwsh.value, "-NoLogo", "-NoProfile", "-NoExit", "-Command", ("& '" + $standInPath + "' --session-id " + $ids[$L]))) }
            $pane = ("" + (@($out) -join "")).Trim()
            $up = Wait-Until { $null -ne (Get-Control $ids[$L]) } 30
            if (-not $up) { Write-Host ("  " + $L + " did not come up; its pane " + $pane + " shows: " + ((@(Invoke-HordeWeztermCli -Rest @("get-text", "--pane-id", $pane)) | Where-Object { "" + $_ -ne "" } | Select-Object -First 15) -join " / ")) -ForegroundColor Yellow }
            [pscustomobject]@{ pane = $pane; up = $up; ms = $clock.ElapsedMilliseconds } }
        $sm = & $start "M" @("spawn", "--pane-id", $paneZero) $masterLane
        $sq = & $start "Q" @("spawn", "--new-window") $lane
        $qWindow = "" + @(Get-Panes | Where-Object { "" + $_.pane_id -ceq $sq.pane })[0].window_id
        $s1 = & $start "Q1" @("spawn", "--window-id", $qWindow) $lane
        $s2 = & $start "Q2" @("split-pane", "--pane-id", $s1.pane, "--right", "--percent", "40") $lane
        Check ($sm.up -and $sq.up -and $s1.up -and $s2.up) ("four stand-ins run and wrote their control files (panes M " + $sm.pane + ", Q " + $sq.pane + ", Q1 " + $s1.pane + ", Q2 " + $s2.pane + ")")
        foreach ($l in @("M", "Q", "Q1", "Q2")) { $lg = @(Get-StandInLogs $ids[$l]); if ($lg.Count -gt 0) { $measure.firstStartMs += (Get-StandInMs $lg[-1]) } }
        Write-Host ("  spawn call to control file seen, ms: " + (@($sm.ms, $sq.ms, $s1.ms, $s2.ms) -join ", ")) -ForegroundColor DarkGray
        $regRows = @(
            [ordered]@{ L = "M"; role = "master"; parent = ""; pane = $sm.pane; cwd = $masterLane },
            [ordered]@{ L = "Q"; role = "orchestrator"; parent = ""; pane = $sq.pane; cwd = $lane },
            [ordered]@{ L = "Q1"; role = "session"; parent = $ids["Q"]; pane = $s1.pane; cwd = $lane },
            [ordered]@{ L = "Q2"; role = "session"; parent = $ids["Q"]; pane = $s2.pane; cwd = $lane })
        foreach ($r in $regRows) {
            # One registry record, as the fleet's own hook writes it (the field names of a real one).
            $rec = [ordered]@{ claudeSessionId = $ids[$r.L]; origin = "user"; fleetSessionId = ""; pane = $r.pane; instance = $instance; cwd = $r.cwd; transcriptPath = (Join-Path $work ($r.L + ".jsonl")); owner = ""; label = $r.L; role = $r.role; lastSeen = [datetime]::UtcNow.ToString("o") }
            if ($r.parent -ne "") { $rec["parent"] = $r.parent }
            [System.IO.File]::WriteAllText((Join-Path $fleetRoot ("registry\sessions\" + $ids[$r.L] + ".json")), (ConvertTo-Json -InputObject $rec))
        }
        [System.IO.File]::WriteAllText((Join-Path $hordeHome "settings\wezterm-fleet.json"), ('{"schemaVersion":1,"settings":{"socket":' + (ConvertTo-Json -InputObject ("" + $iso.socket)) + '}}'))
        [System.IO.File]::WriteAllText((Join-Path $hordeHome "settings\claude-code-fleet.json"), ('{"schemaVersion":1,"settings":{"command":' + (ConvertTo-Json -InputObject ("" + $standInPath)) + '}}'))

        $rec1 = Invoke-Horde @("fleet", "record", "-Labels", "Q,Q1,Q2")
        $hid = ""
        $m = [regex]::Match($rec1.out, 'recorded hibernation ([0-9]{8}-[0-9]{6}): 3 session')
        if ($m.Success) { $hid = $m.Groups[1].Value }
        Check ($rec1.code -eq 0 -and $hid -ne "") ("horde fleet record -Labels Q,Q1,Q2 exits 0 and names the hibernation (" + ($rec1.out.Trim() -replace "\s*`n\s*", " | ") + ")")
        $rec = Read-Record $hid
        $q = $null; $q1 = $null; $q2 = $null
        if ($null -ne $rec) { $q = Get-Sess $rec "Q"; $q1 = Get-Sess $rec "Q1"; $q2 = Get-Sess $rec "Q2" }
        Check ($null -ne $rec -and @($rec.sessions).Count -eq 3 -and $null -eq (Get-Sess $rec "M")) "the record holds the Orc and its two Wargs, and not the master"
        Check ($null -ne $q -and $q.role -ceq "orc" -and $q1.role -ceq "warg" -and $q2.role -ceq "warg" -and $q1.parent -ceq $ids["Q"] -and $q2.parent -ceq $ids["Q"]) "roles and parents are read from the registry"
        Check ($null -ne $q -and $q.placement.windowKey -ceq $q1.placement.windowKey -and $q.placement.tabIndex -eq 0 -and $q1.placement.tabIndex -eq 1 -and $q2.placement.tabIndex -eq 1 -and $q2.placement.left -gt $q1.placement.left) ("placement: one window, the Orc in tab 0, the Wargs side by side in tab 1 (" + $(if ($null -ne $q) { "" + $q.placement.windowKey + " " + $q1.placement.left + "/" + $q2.placement.left } else { "" }) + ")")
        $qLog = @(Get-StandInLogs $ids["Q"])
        Check ($null -ne $q -and $qLog.Count -eq 1 -and "" + $q.process.pid -ceq "" + $qLog[0].pid -and "" + $q.process.start -ceq "" + $qLog[0].procStart) "each session keeps the pid and start time of the process that ran it"

        Section "2. the stand-ins exit, and horde fleet wake"
        $gone = (Stop-StandIn $sq.pane $ids["Q"]) -and (Stop-StandIn $s1.pane $ids["Q1"]) -and (Stop-StandIn $s2.pane $ids["Q2"])
        Check $gone "the Orc and both Wargs ended on /exit, and their control files are gone"
        Check ($null -ne (Get-Control $ids["M"])) "CONTROL: the master stand-in still runs"
        # THE CONTROL BEFORE THE WAKE: its dry run must name the stand-in in every spawn, and no bare command.
        $plan = Invoke-Horde @("fleet", "wake", $hid, "-DryRun")
        $planned = @($plan.out -split "`r?`n" | Where-Object { $_ -like "*--resume*" })
        $planOk = ($plan.code -eq 0 -and $planned.Count -eq 3 -and @($planned | Where-Object { $_.Contains($standInPath) }).Count -eq 3 -and @($planned | Where-Object { $_ -match ('[^\\]\b' + $command + ' --resume') }).Count -eq 0)
        Check $planOk ("CONTROL: the wake's dry run calls the stand-in by its full path in all three spawns, never the harness's bare command (" + ($planned -join " | ") + ")")
        if (-not $planOk) { throw "the wake would not call the stand-in: it is not run" }
        # The terminal restore's no-restore markers, as hibernate writes them, for Q and for the master,
        # which this wake does not start: only Q's may go.
        $markers = Join-Path $profileDir ".wezurrect\no-restore"
        New-Item -ItemType Directory -Path $markers -Force | Out-Null
        foreach ($l in @("Q", "M")) { [System.IO.File]::WriteAllText((Join-Path $markers ($ids[$l] + ".json")), ('{"v":1,"sessionId":"' + $ids[$l] + '","by":"e2e","reason":"hibernated","at":"2026-10-16T10:00:00Z"}')) }
        $panesBefore = @(Get-Panes)
        $windowsBefore = @($panesBefore | ForEach-Object { "" + $_.window_id } | Sort-Object -Unique)
        $wake = Invoke-Horde @("fleet", "wake", $hid)
        Write-Host ("  the wake took " + $wake.secs + " s and said: " + ($wake.out.Trim() -replace "\s*`n\s*", " | ")) -ForegroundColor DarkGray
        Check ($wake.code -eq 0 -and $wake.out -like "*3 to wake, 0 refused*") ("horde fleet wake exits 0 with three to wake (exit " + $wake.code + ")")
        Check ($wake.out -notlike "*registry-stale*") "each woken session's registry row names the pane it was woken in, so nothing is noted registry-stale"
        $panesAfter = @(Get-Panes)
        $new = @($panesAfter | Where-Object { @($panesBefore | ForEach-Object { "" + $_.pane_id }) -notcontains ("" + $_.pane_id) })
        $newWindows = @($new | ForEach-Object { "" + $_.window_id } | Sort-Object -Unique)
        Check ($new.Count -eq 3 -and $newWindows.Count -eq 1 -and $windowsBefore -notcontains $newWindows[0]) ("three new panes, all in ONE new window (" + $new.Count + " panes in " + $newWindows.Count + " window(s))")
        $woken = @{}
        foreach ($l in @("Q", "Q1", "Q2")) { $lg = @(Get-StandInLogs $ids[$l]); if ($lg.Count -ge 2) { $woken[$l] = $lg[-1] } }
        Check ($woken.Count -eq 3) "each of the three came up again as a stand-in run by the wake"
        if ($woken.Count -eq 3) {
            foreach ($l in @("Q", "Q1", "Q2")) {
                $w = $woken[$l]
                Check ($w.mode -ceq "--resume" -and $w.id -ceq $ids[$l] -and (@($w.argv) -join " ") -ceq ("--resume " + $ids[$l])) ($l + "'s pane runs the resume command for its own id")
                Check ((ConvertTo-HordeFleetE2eFolder $w.cwd) -ceq (ConvertTo-HordeFleetE2eFolder $lane)) ($l + " runs in its own folder (" + $w.cwd + ")")
                Check (@($new | ForEach-Object { "" + $_.pane_id }) -ccontains ("" + $w.pane)) ($l + " runs in one of the new panes (" + $w.pane + ")")
                Check (-not $w.hasOwnVariables) ($l + " does not inherit the waking session's own variables")
                $measure.wokenStartMs += (Get-StandInMs $w)
            }
            $pq = @($new | Where-Object { "" + $_.pane_id -ceq $woken["Q"].pane })[0]
            $p1 = @($new | Where-Object { "" + $_.pane_id -ceq $woken["Q1"].pane })[0]
            $p2 = @($new | Where-Object { "" + $_.pane_id -ceq $woken["Q2"].pane })[0]
            $tabsOfNew = @($panesAfter | Where-Object { "" + $_.window_id -ceq $newWindows[0] } | ForEach-Object { "" + $_.tab_id } | Select-Object -Unique)
            Check ($tabsOfNew.Count -eq 2 -and "" + $pq.tab_id -ceq $tabsOfNew[0] -and @($new | Where-Object { "" + $_.tab_id -ceq "" + $pq.tab_id }).Count -eq 1) "the Orc is alone in the window's first tab"
            Check ("" + $p1.tab_id -ceq "" + $p2.tab_id -and "" + $p1.tab_id -ceq $tabsOfNew[1] -and [int]$p2.left_col -gt [int]$p1.left_col -and [int]$p2.top_row -eq [int]$p1.top_row) ("the Wargs share the second tab, the second split to the right of the first, as saved (" + $p1.left_col + "/" + $p2.left_col + ")")
            $share = [Math]::Round(100.0 * [int]$p2.size.cols / ([int]$p1.size.cols + [int]$p2.size.cols))
            Write-Host ("  the split's share as woken: " + $share + " percent (saved: about 40)") -ForegroundColor DarkGray
        }
        $rec = Read-Record $hid
        Check (@("Q", "Q1", "Q2" | Where-Object { "" + (Get-Sess $rec $_).state -cne "woken" }).Count -eq 0) "every session's state is woken"
        Check (-not (Test-Path -LiteralPath (Join-Path $markers ($ids["Q"] + ".json"))) -and (Test-Path -LiteralPath (Join-Path $markers ($ids["M"] + ".json")))) "the woken Orc's no-restore marker was removed by the wake, and the master's, not woken, was left"
        Check ((@((Get-Sess $rec "Q").history | ForEach-Object { $_.state }) -join ",") -ceq "recorded,waking,woken") "and the history keeps each step"
        foreach ($l in @("Q", "Q1", "Q2")) {
            $box = Join-Path $fleetRoot ("mail\" + $ids[$l] + "\inbox")
            $mail = @(Get-ChildItem -LiteralPath $box -File -Recurse -ErrorAction SilentlyContinue | Where-Object { [System.IO.File]::ReadAllText($_.FullName).Contains("You were woken from hibernation " + $hid + ". Read your PARKED-" + $l + ".md") })
            Check ($mail.Count -eq 1) ("the wake mail for " + $l + " was posted through the fleet's real mail command, once, into the scenario's mailbox (" + $box + ")")
        }
        $fresh = @(Get-ChildItem -LiteralPath (Join-Path $realProfile ".claude\sessions") -Filter "*.json" -File -ErrorAction SilentlyContinue | Where-Object { $t = ""; try { $t = [System.IO.File]::ReadAllText($_.FullName) } catch { }; @($ids.Values | Where-Object { $t.Contains($_) }).Count -gt 0 })
        Check ($fresh.Count -eq 0) "no control file in the person's own profile names a session of this scenario"

        Section "3. a second wake of the same id is refused"
        $before3 = @(Get-Panes).Count
        $again = Invoke-Horde @("fleet", "wake", $hid)
        Check ($again.code -eq 0 -and $again.out -like "*0 to wake, 3 refused*" -and @(Get-Panes).Count -eq $before3) ("a second wake refuses all three, which run, and spawns nothing (" + ($again.out.Trim() -replace "\s*`n\s*", " | ") + ")")

        Section "4. one stand-in left running: only that one is refused"
        $q1Pane = "" + $woken["Q1"].pane
        $gone = (Stop-StandIn ("" + $woken["Q"].pane) $ids["Q"]) -and (Stop-StandIn ("" + $woken["Q2"].pane) $ids["Q2"])
        Check ($gone -and $null -ne (Get-Control $ids["Q1"])) "the Orc and the second Warg ended; the first Warg still runs"
        $panesBefore = @(Get-Panes)
        $part = Invoke-Horde @("fleet", "wake", $hid)
        $rec = Read-Record $hid
        Check ($part.code -eq 0 -and $part.out -like "*2 to wake, 1 refused*" -and $part.out -like "*refused Q1*still running*") ("the wake refuses Q1 alone, saying it runs (" + ($part.out.Trim() -replace "\s*`n\s*", " | ") + ")")
        Check ("" + (Get-Sess $rec "Q").state -ceq "woken" -and "" + (Get-Sess $rec "Q2").state -ceq "woken" -and "" + (Get-Sess $rec "Q1").state -ceq "still-awake") "Q and Q2 are woken, Q1 is left still-awake"
        Check (@(Get-Panes).Count -eq $panesBefore.Count + 2 -and @(Get-StandInLogs $ids["Q1"]).Count -eq 2) "two panes were started, and none for Q1"
    }
    catch { Check $false ("the scenario stopped: " + $_.Exception.Message) }
    finally {
        # Teardown runs whatever happened above. A teardown that only runs on success is the leak.
        $result = Stop-HordeIsolatedWezterm -Instance $iso
    }
    Check (-not $result.refused) "teardown accepted the instance Start issued"
    Check ($result.stopped -and -not $result.survived -and @($result.orphansSurvived).Count -eq 0) "the terminal and everything that ran in it are gone"
}

Section "5. measured: how long a stand-in takes to show up running after its spawn"
. (Join-Path $root "fleet\Wake.ps1")
$all = @($measure.firstStartMs) + @($measure.wokenStartMs)
if ($all.Count -gt 0) {
    $max = ($all | Measure-Object -Maximum).Maximum
    Write-Host ("  MEASURED: process start to control file written, ms - first spawns: " + (@($measure.firstStartMs) -join ", ") + "; woken by the wake: " + (@($measure.wokenStartMs) -join ", ") + "; the slowest " + $max + " ms, against the wake's bound of " + $script:HordeFleetWakeWaitSeconds + " s") -ForegroundColor Yellow
    Check ($max -lt ($script:HordeFleetWakeWaitSeconds * 1000)) "every stand-in showed up running well inside the wake's wait bound"
}

Section "and the person's terminal and files were never touched"
Start-Sleep -Milliseconds 800
Check ("$env:WEZTERM_UNIX_SOCKET" -eq "$origSocket") "the pin is back on the terminal this process started in"
$guisAfter = (@(Get-HordeWeztermGuiPids | Sort-Object) -join ",")
Check ($guisAfter -ceq $guisBefore) ("the gui processes running are exactly those running before: " + $guisAfter)
$paneSessionsAfter = Read-PaneSessions
$added = @($paneSessionsAfter.Keys | Where-Object { -not $paneSessionsBefore.ContainsKey($_) })
$removed = @($paneSessionsBefore.Keys | Where-Object { -not $paneSessionsAfter.ContainsKey($_) })
$moved = @($paneSessionsBefore.Keys | Where-Object { $paneSessionsAfter.ContainsKey($_) -and $paneSessionsAfter[$_].occupant -cne $paneSessionsBefore[$_].occupant })
$ours = @($paneSessionsAfter.Keys | Where-Object { $paneSessionsAfter[$_].mine })
$rewritten = @($paneSessionsBefore.Keys | Where-Object { $paneSessionsAfter.ContainsKey($_) -and $paneSessionsAfter[$_].hash -cne $paneSessionsBefore[$_].hash -and $paneSessionsAfter[$_].occupant -ceq $paneSessionsBefore[$_].occupant })
Check ($paneSessionsBefore.Count -gt 0) ("CONTROL: the person's pane-sessions folder was read (" + $paneSessionsBefore.Count + " files)")
Check ($added.Count -eq 0 -and $removed.Count -eq 0) ("no pane-sessions file appeared or went (added: " + ($added -join ",") + "; removed: " + ($removed -join ",") + ")")
Check ($moved.Count -eq 0) ("no pane-sessions file changed hands to another session (" + ($moved -join ",") + ")")
Check ($ours.Count -eq 0) ("no pane-sessions file names a session or folder of this scenario (" + ($ours -join ",") + ")")
Write-Host ("  pane-sessions files rewritten by their own live session during the run (not this scenario): " + $rewritten.Count) -ForegroundColor DarkGray
# A `cli` call loads the person's terminal config, and under this scenario's profile its plugin manager
# clones its plugins into that profile, with read-only git objects (seen 2026-10-16): those are made
# writable first, only inside the scenario's own folder.
if ((Split-Path -Leaf $work) -match '\Ahorde-e2e-fleet-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $work)) { Get-ChildItem -LiteralPath $work -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.IsReadOnly } | ForEach-Object { $_.IsReadOnly = $false } }
# A client still finishing that clone can hold a folder for a few seconds after the terminal is gone (two
# runs of 2026-10-16 left only empty folders, removable a minute later), so this waits up to a minute.
for ($i = 0; $i -lt 60 -and (Test-Path -LiteralPath $work); $i++) {
    try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction Stop }
    catch { Get-ChildItem -LiteralPath $work -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.IsReadOnly } | ForEach-Object { $_.IsReadOnly = $false }; Start-Sleep -Seconds 1 }
}
Check (-not (Test-Path -LiteralPath $work)) "the scenario's folder - its home, fleet, profile and stand-in - is removed"
Remove-HordePaneTool

Complete-HordeSuite -Success "horde fleet record and wake, at the real command line in a terminal of the scenario's own: recorded as laid out, woken into one window as saved, each by its own id in its own folder, mailed through the real fleet mail; a second wake and a running session are refused"
