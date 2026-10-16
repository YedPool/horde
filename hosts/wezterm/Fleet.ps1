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
# given as argv - pwsh -NoLogo -NoExit -Command <the harness's resume line> - so nothing is ever typed
# into a box that might hold something else, and the shell stays when the harness exits, as a pane the
# person opened would. The program is pwsh's full path (Resolve-HordeWeztermProgram: an .exe on PATH,
# never a script shim), as every Horde spawn is (Act.ps1's Start-HordeWeztermPane).
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\Tristate.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\JsonText.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\HostAct.ps1")
. (Join-Path $PSScriptRoot "Act.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "fleet\Port.ps1")

# The shell a woken session runs in, and its arguments before the resume line.
$script:HordeWeztermFleetShell = "pwsh"
$script:HordeWeztermFleetShellArgs = @("-NoLogo", "-NoExit", "-Command")
# The registry's name for a terminal is its socket file's name.
$script:HordeWeztermFleetInstancePattern = '\Agui-sock-[1-9][0-9]{0,9}\z'

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
        $p = Resolve-HordeWeztermProgram -Name $script:HordeWeztermFleetShell
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

function Invoke-HordeWeztermFleetSpawn {
    # Spawn one request into -Target, as an answer: known { pane; window }. A new window's id is read
    # back from the pane list, because spawn answers with the pane id alone.
    param([Parameter(Mandatory = $true)]$Target, [Parameter(Mandatory = $true)]$Request, [Parameter(Mandatory = $true)][string]$Program, [scriptblock]$Runner = $null)
    $rest = $null
    try { $rest = Get-HordeWeztermFleetSpawnRest -Request $Request -Program $Program } catch { return (New-HordeUnknown -Reason ("the spawn was not made: " + $_.Exception.Message)) }
    $envMap = @{}
    if ($null -ne $Request.environment) { foreach ($k in @($Request.environment.Keys)) { $envMap[$k] = $Request.environment[$k] } }
    $r = Invoke-HordeWeztermCall -Rest $rest -Target $Target -Environment $envMap -Runner $Runner
    if ($r.code -ne 0) { return (New-HordeUnknown -Reason ("the terminal did not start the pane (exit " + $r.code + "): " + ("" + $r.err).Trim())) }
    $pane = ("" + $r.out).Trim()
    if ($pane -cnotmatch '\A[0-9]{1,9}\z') { return (New-HordeUnknown -Reason ("the terminal answered the spawn with '" + $pane + "', not a pane id; whether a pane started is unknown")) }
    $window = "" + $Request.window
    if ($Request.mode -cne "tab") {
        $lr = Invoke-HordeWeztermCall -Rest @("list", "--format", "json") -Target $Target -Runner $Runner
        $list = $null
        if ($lr.code -ne 0) { $list = New-HordeUnknown -Reason ("exit " + $lr.code) } else { $list = ConvertFrom-HordeWeztermFleetList -Text ("" + $lr.out) }
        $hit = @()
        if ($list.state -eq "known") { $hit = @(@($list.value) | Where-Object { $_.pane -eq [int]$pane }) }
        if ($hit.Count -ne 1) { return (New-HordeUnknown -Reason ("pane " + $pane + " was started, but which window it is in could not be read back")) }
        $window = "" + $hit[0].window
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ pane = $pane; window = $window }))
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
    param([scriptblock]$Runner = $null)
    $own = Resolve-HordeWeztermOwnMux
    if ($own.state -ne "known") { return $own }
    $prog = Resolve-HordeWeztermProgram -Name $script:HordeWeztermFleetShell
    if ($prog.state -ne "known") { return $prog }
    $script:HordeWeztermFleetOpened = [pscustomobject]@{ target = $own.value; program = "" + $prog.value; runner = $Runner }
    $spawn = { param($request) $o = $script:HordeWeztermFleetOpened; Invoke-HordeWeztermFleetSpawn -Target $o.target -Request $request -Program $o.program -Runner $o.runner }
    $paneOf = { param($processId) Get-HordeWeztermProcessPane -ProcessId ([long]$processId) }
    return (New-HordeKnown -Value ([pscustomobject]@{ spawn = $spawn; paneOf = $paneOf; terminal = ("gui " + $own.value.guiPid) }))
}

Register-HordeFleetHost -Name "wezterm" `
    -Placement { param($refs) Get-HordeWeztermFleetPlacement -Refs $refs } `
    -Open { Open-HordeWeztermFleet } `
    -Describe { param($request) Format-HordeWeztermFleetSpawn -Request $request }
