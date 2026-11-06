# hosts/wezterm/Fleet.ps1 - the WezTerm half of hibernation (fleet/Port.ps1): where each session's pane
# sits now, and how a woken session is given a window, a tab or a split again.
#
# EVERY CALL GOES THROUGH hosts/wezterm/Act.ps1's ONE CALL SITE (Invoke-HordeWeztermCall, which runs
# Invoke-HordeWeztermAct): `cli --no-auto-start`, against a NAMED terminal, its socket set for the call
# alone. So a placement read reaches exactly the terminal the fleet registry says a pane lived in, and a
# wake spawns only into this user's own terminal (Resolve-HordeWeztermOwnMux, which refuses when two
# run and it cannot tell which is meant). -Runner replaces the call in a test, which then sees the argv
# a real call would run (hosts/wezterm/test/test-fleet-host.ps1).
#
# WHERE A PANE IS. The fleet registry stores, per session, the terminal it was last seen in - its socket
# file name, gui-sock-<gui pid> (measured 2026-10-16: 135 of 135 records carry "instance" and "pane") -
# and its pane id there. A pane id is unique only within one terminal's lifetime (Act.ps1's header), so
# it is looked up only in that terminal, named by that socket, and only while that gui runs with the
# start time read when the target is made. `cli list --format json` gives, per pane, window_id, tab_id,
# pane_id, left_col, top_row and size.cols/rows (measured 2026-10-16 on 20261010-083911-e2a98e1b: 23
# panes, every one with all of them). A tab's index is its place among its window's tabs in the list's
# own order, which is the tab bar's order (the list walks each window's tabs in order).
#
# HOW A SESSION IS STARTED AGAIN: never by typing into a pane. The pane is spawned with its program
# given as argv - pwsh -NoLogo -NoProfile -NoExit -Command <the harness's resume line> - so nothing is ever typed
# into a box that might hold something else, and the shell stays when the harness exits, as a pane the
# person opened would. The program is pwsh's full path (Resolve-HordeWeztermProgram: an .exe on PATH,
# never a script shim), as every Horde spawn is (Act.ps1's Start-HordeWeztermPane) - the installed
# PowerShell 7 first, never the Store's while it is there (Resolve-HordeWeztermFleetShell). WITHOUT THE PERSON'S
# PROFILE (second review of PR 318): a profile can define a function or alias of the harness's own name,
# or print and prompt, and the resume line must mean the same in every woken pane; the pane's PATH
# comes from the terminal that spawns it, NOT from the wake (measured by test/e2e/e2e-fleet.ps1: the wake's own PATH
# does not reach the pane), so the harness's command is found by the terminal's PATH.
#
# WHICH TERMINAL. This user's own (Act.ps1's Resolve-HordeWeztermOwnMux), which is refused when two run -
# as they do whenever a test terminal stands beside the person's own. <HORDE_HOME>\settings\
# wezterm-fleet.json may name one by its socket instead (setting socket); placement is then read from that
# socket's folder, so a record and its wake speak of the same terminal. The isolated end-to-end scenario
# (test/e2e/e2e-fleet.ps1) is what needs it; a person running two terminals may use it too.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\Tristate.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\JsonText.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\HostAct.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\ModuleSettings.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\FileAtomic.ps1")
. (Join-Path $PSScriptRoot "Act.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "fleet\Port.ps1")

# The shell a woken session runs in, and its arguments before the resume line. THE INSTALLED POWERSHELL 7
# FIRST, under Program Files, and PATH only when it is not there: a Microsoft Store update of PowerShell 7
# closes every running copy of the Store build, so every pane that ran it closed at once (2026-10-16, the
# whole fleet); the founder ruled that Horde never relies on the Store. While the installed one exists, a
# path under \WindowsApps\ is never chosen.
$script:HordeWeztermFleetShell = "pwsh"
$script:HordeWeztermFleetInstalledShell = "PowerShell\7\pwsh.exe"
$script:HordeWeztermFleetShellArgs = @("-NoLogo", "-NoProfile", "-NoExit", "-Command")
# The registry's name for a terminal is its socket file's name.
$script:HordeWeztermFleetInstancePattern = '\Agui-sock-[1-9][0-9]{0,9}\z'
# The settings (core/ModuleSettings.ps1), declared once: the terminal to wake into, by its socket.
$script:HordeWeztermFleetSettings = New-HordeModuleSettings -Module "wezterm-fleet" -Settings @(
    @{ name = "socket"; kind = "text"; default = ""; min = 0; max = 400; what = "The terminal hibernation reads placement from and wakes into, named by its socket file in full; left out, this user's one running terminal." }
)

function Resolve-HordeWeztermFleetShell {
    # The shell's full path, as an answer: <Program Files>\PowerShell\7\pwsh.exe when that file exists,
    # else the one PATH gives (Resolve-HordeWeztermProgram: an .exe, never a shim). -Exists and -OnPath stand
    # in for the file check and the PATH lookup in a test.
    param([AllowEmptyString()][string]$ProgramFiles = $env:ProgramFiles, [scriptblock]$Exists = $null, [scriptblock]$OnPath = $null)
    if ("" + $ProgramFiles -ne "") {
        $installed = Join-Path $ProgramFiles $script:HordeWeztermFleetInstalledShell
        $there = $(if ($null -ne $Exists) { [bool](& $Exists $installed) } else { Test-Path -LiteralPath $installed -PathType Leaf })
        if ($there) { return (New-HordeKnown -Value $installed) }
    }
    if ($null -ne $OnPath) { return (& $OnPath) }
    return (Resolve-HordeWeztermProgram -Name $script:HordeWeztermFleetShell)
}

# THE TERMINAL RESTORE'S "DO NOT RESTORE" MARKERS (contract of 2026-10-16, after a restore brought every
# session back twice, long-parked ones too): <profile>\.wezurrect\no-restore\<session id>.json, written by
# park and hibernate as { v: 1, sessionId, by, reason: parked | hibernated, at }. The session-restore
# plugin refuses any session that has one; a wake that starts the session removes its marker.
function Get-HordeWeztermFleetNoRestoreDir {
    # The markers' folder under -ProfileDir (USERPROFILE, so a test points it at a folder of its own).
    param([string]$ProfileDir = $env:USERPROFILE)
    return (Join-Path $ProfileDir ".wezurrect\no-restore")
}

function Remove-HordeWeztermFleetNoRestore {
    # Remove the marker of session -SessionId, and no other, as an answer: known "removed" or "none" (no
    # marker is fine), unknown with the reason when the id is not a session id or the file would not go.
    param([AllowEmptyString()][string]$SessionId, [string]$Dir = (Get-HordeWeztermFleetNoRestoreDir))
    if ($SessionId -cnotmatch '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z') { return (New-HordeUnknown -Reason ("'" + $SessionId + "' is not a session id, so no marker was touched")) }
    $path = Join-Path $Dir ($SessionId + ".json")
    if (-not (Test-Path -LiteralPath $path)) { return (New-HordeKnown -Value "none") }
    try { Remove-Item -LiteralPath $path -Force -ErrorAction Stop }
    catch { return (New-HordeUnknown -Reason ("the marker " + $path + " could not be removed: " + $_.Exception.Message)) }
    if (Test-Path -LiteralPath $path) { return (New-HordeUnknown -Reason ("the marker " + $path + " could not be removed: it is still there")) }
    return (New-HordeKnown -Value "removed")
}

function Remove-HordeWeztermFleetNoRestoreIf {
    # Remove the marker of session -SessionId only if it is the one a hibernation wrote (T-0216): the file of
    # that name says reason -Reason and names the same session. As an answer: known "removed", "none" (no
    # marker) or "kept" (a marker that is not that one: a parked one someone else wrote, one naming another
    # session, or one that cannot be read - nothing is removed on a guess); unknown with the reason when the id
    # is not a session id, the reason is not parked or hibernated, or the file would not go. Only that file.
    param([AllowEmptyString()][string]$SessionId, [string]$Reason, [string]$Dir = (Get-HordeWeztermFleetNoRestoreDir))
    if ($SessionId -cnotmatch '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z') { return (New-HordeUnknown -Reason ("'" + $SessionId + "' is not a session id, so no marker was examined")) }
    if ($Reason -cnotmatch '\A(parked|hibernated)\z') { return (New-HordeUnknown -Reason ("'" + $Reason + "' is not a reason a marker may give (parked or hibernated), so no marker was examined")) }
    $path = Join-Path $Dir ($SessionId + ".json")
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return (New-HordeKnown -Value "none") }
    $parsed = $null
    try { $parsed = ConvertFrom-HordeJson -Text ([System.IO.File]::ReadAllText($path)) } catch { return (New-HordeKnown -Value "kept") }
    if ($null -eq $parsed -or $null -eq $parsed.PSObject.Properties["sessionId"] -or $null -eq $parsed.PSObject.Properties["reason"]) { return (New-HordeKnown -Value "kept") }
    if ("" + $parsed.sessionId -cne $SessionId -or "" + $parsed.reason -cne $Reason) { return (New-HordeKnown -Value "kept") }
    return (Remove-HordeWeztermFleetNoRestore -SessionId $SessionId -Dir $Dir)
}

function Write-HordeWeztermFleetNoRestore {
    # The marker of session -SessionId, as an answer: known (the file's path) or unknown with the reason.
    # { v: 1, sessionId, by: "horde", reason, at } - exactly the members the restore plugin's contract names.
    # WRITTEN WHOLE BY RENAME (T-0216): a temp file beside it, then one rename over the marker's name, so the
    # plugin, which reads the folder while a hibernation runs, sees no marker or a whole one - never half of
    # one, and never a temp file, whose name does not end in .json. A write that fails removes its temp file.
    # -Reason is parked or hibernated, nothing else, the contract's two words.
    param([AllowEmptyString()][string]$SessionId, [string]$Reason, [Parameter(Mandatory = $true)][datetime]$At, [string]$Dir = (Get-HordeWeztermFleetNoRestoreDir))
    if ($SessionId -cnotmatch '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z') { return (New-HordeUnknown -Reason ("'" + $SessionId + "' is not a session id, so no marker was written")) }
    if (@("parked", "hibernated") -cnotcontains $Reason) { return (New-HordeUnknown -Reason ("'" + $Reason + "' is not a reason a marker may give (parked or hibernated), so no marker was written")) }
    $path = Join-Path $Dir ($SessionId + ".json")
    $tmp = Join-Path $Dir ($SessionId + ".json." + [guid]::NewGuid().ToString("N") + ".tmp")
    try {
        [void](New-Item -ItemType Directory -Path $Dir -Force -ErrorAction Stop)
        $text = '{"v":1,"sessionId":"' + $SessionId + '","by":"horde","reason":"' + $Reason + '","at":"' + $At.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture) + '"}'
        [System.IO.File]::WriteAllText($tmp, $text, (New-Object System.Text.UTF8Encoding($false)))
        Move-HordeFileAtomic -From $tmp -To $path
    } catch {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        return (New-HordeUnknown -Reason ("the marker " + $path + " could not be written: " + $_.Exception.Message))
    }
    return (New-HordeKnown -Value $path)
}

function Get-HordeWeztermFleetSettings {
    # The settings as { state; values; findings; path }, from the one file under Horde's home.
    param([string]$HordeHome = "")
    return (Get-HordeModuleSettings -Declaration $script:HordeWeztermFleetSettings -HordeHome $HordeHome)
}

function Resolve-HordeWeztermFleetTerminal {
    # The terminal a wake spawns into, as an answer: the one -Settings names by its socket (its gui must
    # be running), else this user's own. Settings that were refused are the answer: unknown, with their
    # findings, and no terminal is asked anything. -Guis, -ProcessStart and -SockDir stand in for the
    # process table and the socket folder in a test.
    param([Parameter(Mandatory = $true)]$Settings, [scriptblock]$Guis = $null, [scriptblock]$ProcessStart = $null, [string]$SockDir = "")
    if ("" + $Settings.state -cne "defaults" -and "" + $Settings.state -cne "read") { return (New-HordeUnknown -Reason ("the fleet's terminal settings are refused, so no terminal was asked: " + (@($Settings.findings) -join "; "))) }
    $named = "" + $Settings.values.socket
    if ($named -ne "") { return (New-HordeWeztermTarget -Socket $named -ProcessStart $ProcessStart) }
    if ($SockDir -eq "") { $SockDir = Get-HordeWeztermSockDir }
    return (Resolve-HordeWeztermOwnMux -SockDir $SockDir -Guis $Guis -ProcessStart $ProcessStart)
}

function Get-HordeWeztermFleetSockDir {
    # Where placement looks for the terminals the registry names: the named socket's folder when one is
    # set, else the terminal's own place (Act.ps1 owns it).
    param([Parameter(Mandatory = $true)]$Settings)
    $named = ""
    if ("" + $Settings.state -ceq "read") { $named = "" + $Settings.values.socket }
    if ($named -ne "" -and [System.IO.Path]::IsPathRooted($named)) { return (Split-Path -Parent $named) }
    return (Get-HordeWeztermSockDir)
}

function ConvertFrom-HordeWeztermFleetList {
    # `cli list --format json` output as rows { window; tab; pane; left; top; cols; rows }, as an answer:
    # unknown when it is not a list of panes that each carry every one of those.
    param([AllowEmptyString()][string]$Text)
    $t = $Text.Trim()
    if ($t -eq "") { return (New-HordeUnknown -Reason "the terminal's pane list was empty output, which is unknown, not none") }
    $parsed = $null
    try { $parsed = ConvertFrom-HordeJson -Text $t } catch { return (New-HordeUnknown -Reason "the terminal's pane list is not JSON") }
    $rows = New-Object System.Collections.ArrayList
    foreach ($p in @($parsed)) {
        if ($null -eq $p) { continue }
        $vals = @{}
        foreach ($n in @("window_id", "tab_id", "pane_id", "left_col", "top_row")) {
            $prop = $p.PSObject.Properties[$n]
            if ($null -eq $prop -or "" + $prop.Value -cnotmatch '\A[0-9]{1,9}\z') { return (New-HordeUnknown -Reason ("a pane in the terminal's list has no " + $n)) }
            $vals[$n] = [int]("" + $prop.Value)
        }
        $size = $p.PSObject.Properties["size"]
        if ($null -eq $size -or $null -eq $size.Value -or "" + $size.Value.cols -cnotmatch '\A[0-9]{1,6}\z' -or "" + $size.Value.rows -cnotmatch '\A[0-9]{1,6}\z') { return (New-HordeUnknown -Reason "a pane in the terminal's list has no size") }
        [void]$rows.Add([pscustomobject]@{ window = $vals["window_id"]; tab = $vals["tab_id"]; pane = $vals["pane_id"]; left = $vals["left_col"]; top = $vals["top_row"]; cols = [int]("" + $size.Value.cols); rows = [int]("" + $size.Value.rows) })
    }
    return (New-HordeKnown -Value $rows.ToArray())
}

function Get-HordeWeztermFleetPlacement {
    # The port's Placement: for each { sessionId; instance; pane } of -Refs, where that pane sits now in
    # the terminal the registry names, as one answer: known map sessionId -> { windowKey; tabIndex;
    # left; top; cols; rows; tabCols; tabRows }, with notes on the side for the sessions it could not
    # place (no instance, a terminal not running, a pane not in the list). A whole answer is unknown only
    # when nothing could be asked at all. -SockDir, -Runner and -ProcessStart stand in for the real ones.
    param([object[]]$Refs = @(), [string]$SockDir = (Get-HordeWeztermSockDir), [scriptblock]$Runner = $null, [scriptblock]$ProcessStart = $null)
    $placed = @{}
    $notes = New-Object System.Collections.ArrayList
    $byInstance = @{}
    foreach ($r in @($Refs)) {
        if ($null -eq $r) { continue }
        if ("" + $r.instance -cnotmatch $script:HordeWeztermFleetInstancePattern -or "" + $r.pane -cnotmatch '\A[0-9]{1,9}\z') { [void]$notes.Add("" + $r.sessionId + ": the registry names no terminal and pane for it"); continue }
        if (-not $byInstance.ContainsKey("" + $r.instance)) { $byInstance["" + $r.instance] = New-Object System.Collections.ArrayList }
        [void]$byInstance["" + $r.instance].Add($r)
    }
    foreach ($inst in @($byInstance.Keys | Sort-Object)) {
        $target = New-HordeWeztermTarget -Socket (Join-Path $SockDir $inst) -ProcessStart $ProcessStart
        if ($target.state -ne "known") { foreach ($r in $byInstance[$inst]) { [void]$notes.Add("" + $r.sessionId + ": " + $target.reason) }; continue }
        $call = Invoke-HordeWeztermCall -Rest @("list", "--format", "json") -Target $target.value -Runner $Runner
        $list = $null
        if ($call.code -ne 0) { $list = New-HordeUnknown -Reason ("the terminal " + $inst + " did not list its panes (exit " + $call.code + "): " + ("" + $call.err).Trim()) }
        else { $list = ConvertFrom-HordeWeztermFleetList -Text ("" + $call.out) }
        if ($list.state -ne "known") { foreach ($r in $byInstance[$inst]) { [void]$notes.Add("" + $r.sessionId + ": " + $list.reason) }; continue }
        $rows = @($list.value)
        foreach ($r in $byInstance[$inst]) {
            $mine = @($rows | Where-Object { $_.pane -eq [int]("" + $r.pane) })
            if ($mine.Count -ne 1) { [void]$notes.Add("" + $r.sessionId + ": pane " + $r.pane + " is not in the list of terminal " + $inst); continue }
            $me = $mine[0]
            $tabs = New-Object System.Collections.ArrayList
            foreach ($row in $rows) { if ($row.window -eq $me.window -and -not $tabs.Contains($row.tab)) { [void]$tabs.Add($row.tab) } }
            $tabPanes = @($rows | Where-Object { $_.tab -eq $me.tab })
            $tabCols = ($tabPanes | ForEach-Object { $_.left + $_.cols } | Measure-Object -Maximum).Maximum
            $tabRows = ($tabPanes | ForEach-Object { $_.top + $_.rows } | Measure-Object -Maximum).Maximum
            $placed["" + $r.sessionId] = [pscustomobject]@{ windowKey = ($inst + ":" + $me.window); tabIndex = $tabs.IndexOf($me.tab); left = $me.left; top = $me.top; cols = $me.cols; rows = $me.rows; tabCols = [int]$tabCols; tabRows = [int]$tabRows }
        }
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ placed = $placed; notes = @($notes) }))
}

function Get-HordeWeztermFleetSpawnRest {
    # The cli call one spawn request makes, after `cli --no-auto-start`: spawn --new-window, spawn
    # --window-id <W>, or split-pane --pane-id <P> --right|--bottom [--percent <n>]; then --cwd, --, the
    # shell, its arguments and the resume line as ONE argument. Throws on a request it cannot make.
    param([Parameter(Mandatory = $true)]$Request, [Parameter(Mandatory = $true)][string]$Program)
    $cwd = "" + $Request.cwd
    if (-not [System.IO.Path]::IsPathRooted($cwd)) { throw ("the working folder must be absolute, not '" + $cwd + "'") }
    $line = "" + $Request.line
    if ($line -eq "" -or $line -cmatch '[\x00-\x1F\x7F]') { throw "the resume line is empty or holds a control character" }
    $rest = @()
    switch -CaseSensitive ("" + $Request.mode) {
        "window" { $rest = @("spawn", "--new-window") }
        "tab" {
            if ("" + $Request.window -cnotmatch '\A[0-9]{1,9}\z') { throw ("'" + $Request.window + "' is not a window id") }
            $rest = @("spawn", "--window-id", ("" + $Request.window))
        }
        "split" {
            if ("" + $Request.pane -cnotmatch '\A[0-9]{1,9}\z') { throw ("'" + $Request.pane + "' is not a pane id") }
            if (@("right", "bottom") -cnotcontains ("" + $Request.direction)) { throw ("'" + $Request.direction + "' is not a split direction (right or bottom)") }
            $rest = @("split-pane", "--pane-id", ("" + $Request.pane), ("--" + $Request.direction))
            if ("" + $Request.percent -cmatch '\A[1-9][0-9]?\z') { $rest += @("--percent", ("" + $Request.percent)) }
        }
        default { throw ("'" + $Request.mode + "' is not a spawn mode (window, tab or split)") }
    }
    return @($rest + @("--cwd", $cwd, "--", $Program) + $script:HordeWeztermFleetShellArgs + @($line))
}

function Format-HordeWeztermFleetSpawn {
    # The port's Describe: the exact command a spawn request runs, as one line, for a dry run. A window
    # that does not exist yet is shown as <window>, a pane as <pane>.
    param([Parameter(Mandatory = $true)]$Request, [string]$Program = "")
    if ($Program -eq "") {
        $p = Resolve-HordeWeztermFleetShell
        if ($p.state -eq "known") { $Program = "" + $p.value } else { $Program = $script:HordeWeztermFleetShell }
    }
    $shown = [pscustomobject]@{ mode = $Request.mode; cwd = $Request.cwd; line = $Request.line; window = $Request.window; pane = $Request.pane; direction = $Request.direction; percent = $Request.percent }
    if ($shown.mode -ceq "tab" -and "" + $shown.window -cnotmatch '\A[0-9]{1,9}\z') { $shown.window = "0" }
    if ($shown.mode -ceq "split" -and "" + $shown.pane -cnotmatch '\A[0-9]{1,9}\z') { $shown.pane = "0" }
    $text = "wezterm " + (ConvertTo-HordeWindowsCommandLine -Argv (Get-HordeWeztermActArgv -Rest (Get-HordeWeztermFleetSpawnRest -Request $shown -Program $Program)))
    if ($Request.mode -ceq "tab" -and "" + $Request.window -cnotmatch '\A[0-9]{1,9}\z') { $text = $text.Replace("--window-id 0", "--window-id <window of " + $Request.window + ">") }
    if ($Request.mode -ceq "split" -and "" + $Request.pane -cnotmatch '\A[0-9]{1,9}\z') { $text = $text.Replace("--pane-id 0", "--pane-id <pane of " + $Request.pane + ">") }
    return $text
}

function ConvertTo-HordeWeztermFleetLine {
    # The terminal's stderr as one short line: a record's reason is one line of at most 600 characters
    # (schema/fleet-hibernation), and the cli's own output has line breaks and no bound.
    param([AllowEmptyString()][string]$Text, [int]$Max = 300)
    $one = ($Text -replace '[\x00-\x1F]+', ' ').Trim()
    if ($one.Length -gt $Max) { $one = $one.Substring(0, $Max - 3) + "..." }
    return $one
}

function Invoke-HordeWeztermFleetSpawn {
    # Spawn one request into -Target, as an answer: known { pane; window }. A new window's id is read
    # back from the pane list, because spawn answers with the pane id alone.
    param([Parameter(Mandatory = $true)]$Target, [Parameter(Mandatory = $true)]$Request, [Parameter(Mandatory = $true)][string]$Program, [scriptblock]$Runner = $null)
    # THE ANSWER'S MEANING (third review of PR 318, P1): ABSENT only when the request was refused BEFORE any
    # call to the terminal, so nothing was started. Every other answer that is not a known pane - a cli
    # timeout (Act.ps1 kills the process after 20 s: exit -1), a failed exit, an answer that is not a pane
    # id - is UNKNOWN, because the cli may have made the pane before it failed: the wake holds it.
    $rest = $null
    try { $rest = Get-HordeWeztermFleetSpawnRest -Request $Request -Program $Program } catch { return (New-HordeAbsent -Note ("the spawn was not made: " + $_.Exception.Message)) }
    $envMap = @{}
    if ($null -ne $Request.environment) { foreach ($k in @($Request.environment.Keys)) { $envMap[$k] = $Request.environment[$k] } }
    $r = Invoke-HordeWeztermCall -Rest $rest -Target $Target -Environment $envMap -Runner $Runner
    if ($r.code -ne 0) { return (New-HordeUnknown -Reason ("the terminal did not start the pane (exit " + $r.code + "), so whether a pane started is unknown: " + (ConvertTo-HordeWeztermFleetLine -Text ("" + $r.err) -Max 300))) }
    $pane = ("" + $r.out).Trim()
    if ($pane -cnotmatch '\A[0-9]{1,9}\z') { return (New-HordeUnknown -Reason ("the terminal answered the spawn with '" + (ConvertTo-HordeWeztermFleetLine -Text $pane -Max 100) + "', not a pane id; whether a pane started is unknown")) }
    $window = "" + $Request.window
    if ($Request.mode -cne "tab") {
        $lr = Invoke-HordeWeztermCall -Rest @("list", "--format", "json") -Target $Target -Runner $Runner
        $list = $null
        if ($lr.code -ne 0) { $list = New-HordeUnknown -Reason ("exit " + $lr.code) } else { $list = ConvertFrom-HordeWeztermFleetList -Text ("" + $lr.out) }
        $hit = @()
        if ($list.state -eq "known") { $hit = @(@($list.value) | Where-Object { $_.pane -eq [int]$pane }) }
        # THE PANE STARTED (second review of PR 318): it is known, with no window and the reason, so the
        # wake waits for it and stops its group, rather than calling it not started.
        if ($hit.Count -ne 1) { return (New-HordeKnown -Value ([pscustomobject]@{ pane = $pane; window = ""; note = ("pane " + $pane + " was started, but which window it is in could not be read back") })) }
        $window = "" + $hit[0].window
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ pane = $pane; window = $window; note = "" }))
}

# THE OPENED TERMINAL, kept at script scope and read by plain blocks, NOT captured by GetNewClosure:
# a closure's functions are looked up from the script scope, and `horde fleet` dot-sources this file
# inside its run block, a scope below that, so a closure calling Invoke-HordeWeztermFleetSpawn found
# no such command (measured 2026-10-16 on 5.1: a closure made in a child scope could not call a
# function defined there; the same closure made at script scope could).
$script:HordeWeztermFleetOpened = $null

function Open-HordeWeztermFleet {
    # The port's Open: this user's own terminal and the shell's full path, as an answer whose value
    # carries the spawn and paneOf blocks for them. Unknown, with nothing spawned, when either cannot be
    # had.
    param([scriptblock]$Runner = $null, $Settings = $null)
    if ($null -eq $Settings) { $Settings = Get-HordeWeztermFleetSettings }
    $own = Resolve-HordeWeztermFleetTerminal -Settings $Settings
    if ($own.state -ne "known") { return $own }
    $prog = Resolve-HordeWeztermFleetShell
    if ($prog.state -ne "known") { return $prog }
    $script:HordeWeztermFleetOpened = [pscustomobject]@{ target = $own.value; program = "" + $prog.value; runner = $Runner }
    $spawn = { param($request) $o = $script:HordeWeztermFleetOpened; Invoke-HordeWeztermFleetSpawn -Target $o.target -Request $request -Program $o.program -Runner $o.runner }
    $paneOf = { param($processId) Get-HordeWeztermProcessPane -ProcessId ([long]$processId) }
    return (New-HordeKnown -Value ([pscustomobject]@{ spawn = $spawn; paneOf = $paneOf; terminal = ("gui " + $own.value.guiPid) }))
}

function Get-HordeWeztermFleetPanes {
    # The port's Panes (fleet/Port.ps1): the live panes of EVERY terminal of this user, one entry per terminal,
    # for the fleet.db sessions step. known list of { instance; state; panes; reason }:
    #   instance  the socket file's name, which is what the fleet registry stores for a terminal
    #   listed    the terminal answered, and `panes` are its pane numbers
    #   closed    its gui is not running (a socket file stays behind when a gui closes, so the file alone proves
    #             nothing): none of its panes is live
    #   unknown   it runs and did not give a list - a timeout, a refusal, output that is not a list - so what sat in
    #             it is NOT known gone; `reason` says why
    # EACH CALL HAS A LIMIT OF ITS OWN (-CallMs) and kills only the child it started (Act.ps1's Invoke-HordeWeztermAct:
    # a process object of its own, never a kill by name), and the whole pass has one budget (-BudgetMs): a terminal
    # the budget ran out before is unknown, not skipped. Every call names its terminal (Act.ps1), so this never
    # reaches the terminal the environment points at. The whole answer is unknown when the socket folder cannot be
    # listed. -SockDir, -Runner and -ProcessStart stand in for the real ones in a test.
    param([string]$SockDir = (Get-HordeWeztermSockDir), [int]$CallMs = 8000, [int]$BudgetMs = 30000, [scriptblock]$Runner = $null, [scriptblock]$ProcessStart = $null)
    if (-not (Test-Path -LiteralPath $SockDir -PathType Container)) { return (New-HordeUnknown -Reason ("there is no terminal socket folder at " + $SockDir + ", so the live panes cannot be listed")) }
    $socks = @()
    try { $socks = @(Get-ChildItem -LiteralPath $SockDir -ErrorAction Stop | Where-Object { -not $_.PSIsContainer -and $_.Name -cmatch $script:HordeWeztermSocketLeaf } | Sort-Object Name) }
    catch { return (New-HordeUnknown -Reason ("the terminal socket folder " + $SockDir + " could not be listed: " + $_.Exception.Message)) }
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $out = New-Object System.Collections.ArrayList
    foreach ($s in $socks) {
        $inst = "" + $s.Name
        $gui = [long]([regex]::Match($inst, $script:HordeWeztermSocketLeaf).Groups[1].Value)
        $start = $null
        if ($null -ne $ProcessStart) { $start = & $ProcessStart $gui } else { $start = Get-HordeWeztermProcessStart -ProcessId $gui }
        if ($null -eq $start) {
            # No start time is "not running" only when no such process exists: one that runs and will not tell its start is unknown.
            $runs = ($null -eq $ProcessStart -and $null -ne (Get-Process -Id $gui -ErrorAction SilentlyContinue))
            if ($runs) { [void]$out.Add([pscustomobject]@{ instance = $inst; state = "unknown"; panes = @(); reason = ("the gui " + $gui + " runs but its start time cannot be read") }) }
            else { [void]$out.Add([pscustomobject]@{ instance = $inst; state = "closed"; panes = @(); reason = ("the gui " + $gui + " is not running") }) }
            continue
        }
        if ($watch.ElapsedMilliseconds -gt $BudgetMs) { [void]$out.Add([pscustomobject]@{ instance = $inst; state = "unknown"; panes = @(); reason = "not listed: the pass budget for pane lists ran out" }); continue }
        $target = New-HordeWeztermTarget -Socket $s.FullName -ProcessStart $ProcessStart
        if ($target.state -ne "known") { [void]$out.Add([pscustomobject]@{ instance = $inst; state = "unknown"; panes = @(); reason = ("" + $target.reason) }); continue }
        $rest = @("list", "--format", "json")
        $call = $null
        if ($null -ne $Runner) { $call = & $Runner $rest @{} $target.value } else { $call = Invoke-HordeWeztermAct -Rest $rest -Target $target.value -TimeoutMs $CallMs -Utf8 }
        if ($call.code -ne 0) { [void]$out.Add([pscustomobject]@{ instance = $inst; state = "unknown"; panes = @(); reason = ("the terminal did not list its panes (exit " + $call.code + "): " + ("" + $call.err).Trim()) }); continue }
        $list = Read-HordeWeztermPaneList -Raw $call.out
        if ($list.state -ne "known") { [void]$out.Add([pscustomobject]@{ instance = $inst; state = "unknown"; panes = @(); reason = ("" + $list.reason) }); continue }
        $nos = @(@($list.value) | ForEach-Object { [int]("" + $_.pane) })
        [void]$out.Add([pscustomobject]@{ instance = $inst; state = "listed"; panes = $nos; reason = "" })
    }
    return (New-HordeKnown -Value $out.ToArray())
}

Register-HordeFleetHost -Name "wezterm" `
    -Placement { param($refs) $st = Get-HordeWeztermFleetSettings; if ("" + $st.state -cne "defaults" -and "" + $st.state -cne "read") { New-HordeUnknown -Reason ("the fleet's terminal settings are refused: " + (@($st.findings) -join "; ")) } else { Get-HordeWeztermFleetPlacement -Refs $refs -SockDir (Get-HordeWeztermFleetSockDir -Settings $st) } } `
    -Open { Open-HordeWeztermFleet } `
    -Describe { param($request) Format-HordeWeztermFleetSpawn -Request $request } `
    -Release { param($sessionId) Remove-HordeWeztermFleetNoRestore -SessionId $sessionId } `
    -Mark { param($sessionId, $reason, $at) Write-HordeWeztermFleetNoRestore -SessionId $sessionId -Reason $reason -At $at } `
    -Unmark { param($sessionId, $reason) Remove-HordeWeztermFleetNoRestoreIf -SessionId $sessionId -Reason $reason } `
    -Panes { $st = Get-HordeWeztermFleetSettings; if ("" + $st.state -cne "defaults" -and "" + $st.state -cne "read") { New-HordeUnknown -Reason ("the fleet's terminal settings are refused: " + (@($st.findings) -join "; ")) } else { Get-HordeWeztermFleetPanes -SockDir (Get-HordeWeztermFleetSockDir -Settings $st) } }
