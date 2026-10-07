# hosts/wezterm/Window.ps1 - which native window of WezTerm shows a given pane.
#
# THE FINDER HALF OF THE WEZTERM HOST (decisions window attach design, 2026-10-06; core/HostWindow.ps1).
# A Horde window is to stand beside the terminal window of one session. That session's record says
# which pane it runs in and which terminal ("instance", the leaf name of the terminal's mux socket,
# gui-sock-<gui pid>). This file turns those two texts into ONE native window handle, or says why it
# cannot. It only reads: one `cli list`, and the titles of the terminal process's own windows. It never
# types, moves, resizes or closes anything, and never starts a terminal (`cli --no-auto-start`).
#
# NEVER BY SEARCHING FOR A NAME. The window is not found by looking for a title that says who is in
# it: titles are text a session sets, and two windows can carry one. The chain is the terminal's own:
#   the instance      -> the terminal's gui process, which must be running (hosts/wezterm/Act.ps1's
#                        target: the socket named after the gui, and the gui's start time)
#   the pane          -> the window id the terminal's own listing gives for that pane
#   that window id    -> one of the gui process's top-level windows
# The last step is the only one Windows and the terminal do not share an id for. MEASURED 2026-10-06
# (20240203): `cli list --format json` gives window_id, tab_id, pane_id, title and is_active for every
# pane and no native handle; the gui process had 16 terminal windows and 16 window ids. So:
#   - one window id listed, one terminal window in the process: that window, nothing to tell apart.
#   - otherwise, BY THAT EXACT WINDOW'S OWN DETAILS FROM THE SAME LISTING: a terminal window is titled
#     after the active pane of its active tab, with "[<tab>/<tabs>] " in front when it has more than
#     one tab and "[Z] " when the pane is zoomed (measured: "[6/6] <pane title>" on a six-tab window,
#     the bare pane title on a one-tab window). The listing gives every tab's active pane and the
#     number of tabs, so the titles the session's window can have are known. Exactly one terminal
#     window must carry one of them, AND that window must not also fit another window id's titles.
#     None, or two, or one that fits two ids: unknown, with the reason. Never the likeliest.
# A title can change between the two reads (a busy session redraws its title several times a second),
# so the windows are read before and after the listing and a match in either counts, and the whole
# reading is tried a few times before the answer is unknown.
#
# A terminal configured to title its windows another way (its format-window-title event) will fit no
# title: the answer is then unknown, and the caller's window stands free. That is the honest result.
#
# THE LISTING IS UTF-8, AND IS MENDED HERE. Titles hold characters outside ASCII. The host's one call
# (hosts/wezterm/Act.ps1) leaves the decoding of the terminal's answer to .NET, which reads it in the
# console's code page, or the machine's when there is no console: a title of one character outside
# ASCII came back as three others and did not equal itself (measured 2026-10-06). That file is the
# act path's and is not changed for this one: the finder notes the code page the answer was read in,
# turns the text back into the bytes the terminal wrote, and reads those as UTF-8
# (ConvertTo-HordeWeztermAnswerText). Where the bytes cannot be had back, or are not UTF-8, the answer
# is unknown. WHEN THE HOST'S CALL ITSELF READS UTF-8, this mending goes: it would then mend text
# that is already right, and its suite's control - the same call, measured each run - fails first.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\HostAct.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\HostWindow.ps1")
. (Join-Path $PSScriptRoot "Act.ps1")

# A TERMINAL WINDOW IS A VISIBLE, UNOWNED TOP-LEVEL WINDOW OF THE GUI PROCESS. Its other top-level windows
# - a probing window per terminal window, the input method's - are hidden or owned (measured
# 2026-10-06: 16 visible unowned windows, 16 hidden probing windows, 2 owned). NOT BY WINDOW CLASS: the
# class is whatever the terminal was started with (--class), and the first run against an isolated
# instance, started with a class of its own, found no window at all by the default class.
# How many times the windows and the listing are read before a title that fits nothing is believed.
$script:HordeWeztermWindowAttempts = 3
$script:HordeWeztermWindowRetryMs = 200

$script:HordeWeztermWindowSource = @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class HordeWeztermWindows {
    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowTextW(IntPtr h, StringBuilder sb, int n);
    [DllImport("user32.dll")] static extern int GetWindowTextLengthW(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
    // Every visible, unowned top-level window of one process: handle, then title.
    public static List<KeyValuePair<long, string>> List(uint processId) {
        var found = new List<KeyValuePair<long, string>>();
        EnumWindows((h, l) => {
            uint pid; GetWindowThreadProcessId(h, out pid);
            if (pid != processId || !IsWindowVisible(h) || GetWindow(h, 4) != IntPtr.Zero) return true;   // GW_OWNER
            var title = new StringBuilder(GetWindowTextLengthW(h) + 2); GetWindowTextW(h, title, title.Capacity);
            found.Add(new KeyValuePair<long, string>(h.ToInt64(), title.ToString()));
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
'@

function Get-HordeWeztermNativeWindows {
    # The terminal windows of one gui process, as { handle; title }. A minimised window is listed: it
    # is still the session's window.
    param([Parameter(Mandatory = $true)][long]$ProcessId)
    if ($null -eq ("HordeWeztermWindows" -as [type])) { Add-Type -TypeDefinition $script:HordeWeztermWindowSource }
    return @([HordeWeztermWindows]::List([uint32]$ProcessId) | ForEach-Object { [pscustomobject]@{ handle = [long]$_.Key; title = "" + $_.Value } })
}

function Read-HordeWeztermWindowList {
    # The panes of `cli list --format json`, with what tells windows apart, as an answer: known list
    # of { pane; window; tab; title; active; zoomed }, or unknown when the output is not that list.
    # hosts/wezterm/Act.ps1's Read-HordeWeztermPaneList reads the same output for the act path and
    # drops is_active, which only this file needs.
    param($Raw)
    $joined = ((@($Raw) -join "`n").Trim())
    if ($joined -eq "") { return (New-HordeUnknown -Reason "the terminal's pane list was empty output, which is unknown, not none") }
    $parsed = $null
    try { $parsed = $joined | ConvertFrom-Json } catch { return (New-HordeUnknown -Reason "the terminal's pane list is not JSON") }
    if ($joined -ceq "[]") { return (New-HordeKnown -Value @()) }
    $rows = New-Object System.Collections.ArrayList
    foreach ($p in @($parsed)) {
        foreach ($need in @("pane_id", "window_id", "tab_id", "title", "is_active")) {
            if ($null -eq $p -or $null -eq $p.PSObject.Properties[$need]) { return (New-HordeUnknown -Reason ("a pane in the terminal's list has no " + $need + ", so its window cannot be told from the others")) }
        }
        $zoomed = $false
        if ($null -ne $p.PSObject.Properties["is_zoomed"]) { $zoomed = [bool]$p.is_zoomed }
        [void]$rows.Add([pscustomobject]@{ pane = ("" + $p.pane_id); window = ("" + $p.window_id); tab = ("" + $p.tab_id); title = ("" + $p.title); active = [bool]$p.is_active; zoomed = $zoomed })
    }
    return (New-HordeKnown -Value $rows.ToArray())
}

function Get-HordeWeztermAnswerEncoding {
    # The code page .NET reads a child process's answer in when the call names none: the console's
    # output code page, or the machine's own when this process has no console. Read just before the call.
    try { return [Console]::OutputEncoding } catch { return [System.Text.Encoding]::Default }
}

function ConvertTo-HordeWeztermAnswerText {
    # The terminal's answer as the terminal wrote it (header, THE LISTING IS UTF-8, AND IS MENDED HERE),
    # as an answer: known text, or unknown with the reason. -Text is the answer as it was read, -ReadAs
    # the code page it was read in. A PURE FUNCTION. Text that is all ASCII is the same in every code
    # page Windows has, and an answer already read as UTF-8 is right: both are handed back untouched.
    param([AllowEmptyString()][string]$Text, [Parameter(Mandatory = $true)][System.Text.Encoding]$ReadAs)
    if ($ReadAs.CodePage -eq 65001 -or $Text -cnotmatch '[^\u0000-\u007F]') { return (New-HordeKnown -Value $Text) }
    # Back to the terminal's bytes: only where the code page gives one character for every byte, and
    # this very text comes back from its bytes unchanged. Otherwise a byte was lost when it was read.
    $bytes = $null
    if ($ReadAs.IsSingleByte) { $bytes = $ReadAs.GetBytes($Text); if ($ReadAs.GetString($bytes) -cne $Text) { $bytes = $null } }
    if ($null -eq $bytes) { return (New-HordeUnknown -Reason ("the terminal's answer was read in code page " + $ReadAs.CodePage + ", from which it cannot be turned back into what the terminal wrote")) }
    try { return (New-HordeKnown -Value (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes)) }
    catch { return (New-HordeUnknown -Reason "the terminal's answer is not UTF-8, so its titles cannot be compared") }
}

function Test-HordeWeztermWindowTitle {
    # Could a terminal window with the panes -Rows (all of one window id) be titled -Title? The title
    # of one of its tabs' active panes, behind "[<tab>/<tabs>] " when it has more than one tab and
    # "[Z] " when that pane is zoomed (header). Compared exactly.
    param([AllowEmptyString()][string]$Title, [Parameter(Mandatory = $true)][object[]]$Rows)
    $tabs = @($Rows | ForEach-Object { $_.tab } | Sort-Object -Unique).Count
    foreach ($row in @($Rows | Where-Object { $_.active })) {
        $want = $row.title
        if ($row.zoomed) { $want = "[Z] " + $want }
        if ($tabs -le 1) { if ($Title -ceq $want) { return $true }; continue }
        for ($i = 1; $i -le $tabs; $i++) { if ($Title -ceq ("[" + $i + "/" + $tabs + "] " + $want)) { return $true } }
    }
    return $false
}

function Select-HordeWeztermSessionWindow {
    # THE DECISION, with no terminal in it: from the listing's rows, the pane, and the terminal
    # process's windows read before (-Native) and after (-NativeAfter) the listing, an answer - known
    # { handle; window; detail }, or unknown with the reason (header). A PURE FUNCTION.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Rows, [Parameter(Mandatory = $true)][string]$Pane,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Native, [AllowEmptyCollection()][object[]]$NativeAfter = @())
    $mine = @($Rows | Where-Object { $_.pane -ceq $Pane })
    if ($mine.Count -eq 0) { return (New-HordeUnknown -Reason ("the terminal lists no pane " + $Pane + ": the session's record names a pane that is no longer there")) }
    if ($mine.Count -gt 1) { return (New-HordeUnknown -Reason ("the terminal lists pane " + $Pane + " " + $mine.Count + " times, so its window cannot be told")) }
    $windowId = $mine[0].window
    # Each terminal window with every title it was seen to carry, before and after the listing.
    $titles = [ordered]@{}
    foreach ($n in (@($Native) + @($NativeAfter))) {
        $key = "" + [long]$n.handle
        if (-not $titles.Contains($key)) { $titles[$key] = New-Object System.Collections.ArrayList }
        if ($titles[$key] -cnotcontains $n.title) { [void]$titles[$key].Add("" + $n.title) }
    }
    if ($titles.Count -eq 0) { return (New-HordeUnknown -Reason "the terminal's process has no terminal window on screen, so there is none to stand beside") }
    $windowIds = @($Rows | ForEach-Object { $_.window } | Sort-Object -Unique)
    if ($windowIds.Count -eq 1 -and $titles.Count -eq 1) {
        return (New-HordeKnown -Value ([pscustomobject]@{ handle = [long](@($titles.Keys)[0]); window = $windowId; detail = "the terminal has one window" }))
    }
    $fits = { param([string]$Key, [string]$Id) $rowsOf = @($Rows | Where-Object { $_.window -ceq $Id }); foreach ($t in @($titles[$Key])) { if (Test-HordeWeztermWindowTitle -Title $t -Rows $rowsOf) { return $true } }; return $false }
    $matched = @(@($titles.Keys) | Where-Object { & $fits $_ $windowId })
    if ($matched.Count -eq 0) {
        return (New-HordeUnknown -Reason ("none of the terminal's " + $titles.Count + " windows is titled as the window of pane " + $Pane + " would be: its title changed while it was read, or this terminal titles its windows its own way"))
    }
    if ($matched.Count -gt 1) {
        return (New-HordeUnknown -Reason ("" + $matched.Count + " of the terminal's windows are titled as the window of pane " + $Pane + " would be, and one is never chosen over another"))
    }
    $others = @($windowIds | Where-Object { $_ -cne $windowId -and (& $fits $matched[0] $_) })
    if ($others.Count -gt 0) {
        return (New-HordeUnknown -Reason ("the one window titled as the window of pane " + $Pane + " would be is titled as another of the terminal's windows would be too, so which it is cannot be told"))
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ handle = [long]$matched[0]; window = $windowId; detail = ("the one of the terminal's " + $titles.Count + " windows titled after its panes") }))
}

function Find-HordeWeztermSessionWindow {
    # The native window showing pane -Pane of the terminal -Instance, as an answer (header). -SockDir,
    # -Runner, -Windows and -ProcessStart replace the socket folder, the terminal's command, the window
    # reader and the process clock in a test; -ReadAs says which code page a runner's answer was read
    # in, and the real call's is always this process's own.
    param([AllowEmptyString()][string]$Pane, [AllowEmptyString()][string]$Instance,
        [string]$SockDir = (Join-Path $env:USERPROFILE ".local\share\wezterm"),
        [scriptblock]$Runner = $null, [scriptblock]$Windows = $null, [scriptblock]$ProcessStart = $null, [System.Text.Encoding]$ReadAs = $null,
        [int]$Attempts = $script:HordeWeztermWindowAttempts, [int]$RetryMs = $script:HordeWeztermWindowRetryMs)
    if ($Pane -cnotmatch '\A[0-9]{1,9}\z') { return (New-HordeUnknown -Reason "the session's record names a pane this terminal does not number that way, so it is not one of this terminal's") }
    # The leaf name only: a record never chooses the folder the socket is looked for in.
    if ($Instance -cnotmatch $script:HordeWeztermSocketLeaf) { return (New-HordeUnknown -Reason "the session's record does not name one of this terminal's instances (gui-sock-<pid>)") }
    $target = New-HordeWeztermTarget -Socket (Join-Path $SockDir $Instance) -ProcessStart $ProcessStart
    if ($target.state -cne "known") { return (New-HordeUnknown -Reason ("the session's terminal is not running: " + $target.reason)) }
    $last = $null
    for ($try = 1; $try -le [Math]::Max($Attempts, 1); $try++) {
        if ($try -gt 1 -and $RetryMs -gt 0) { Start-Sleep -Milliseconds $RetryMs }
        $before = $null; $after = $null
        if ($null -ne $Windows) { $before = @(& $Windows ([long]$target.value.guiPid)) } else { $before = @(Get-HordeWeztermNativeWindows -ProcessId ([long]$target.value.guiPid)) }
        $readIn = $ReadAs
        if ($null -eq $Runner) { $readIn = Get-HordeWeztermAnswerEncoding }
        $call = Invoke-HordeWeztermCall -Rest @("list", "--format", "json") -Target $target.value -Runner $Runner
        if ($call.code -ne 0) { return (New-HordeUnknown -Reason ("the terminal did not list its panes (exit " + $call.code + "): " + ("" + $call.err).Trim())) }
        $listing = $call.out
        if ($null -ne $readIn) {
            $mended = ConvertTo-HordeWeztermAnswerText -Text (@($call.out) -join "`n") -ReadAs $readIn
            if ($mended.state -cne "known") { return $mended }
            $listing = $mended.value
        }
        $rows = Read-HordeWeztermWindowList -Raw $listing
        if ($rows.state -cne "known") { return $rows }
        if ($null -ne $Windows) { $after = @(& $Windows ([long]$target.value.guiPid)) } else { $after = @(Get-HordeWeztermNativeWindows -ProcessId ([long]$target.value.guiPid)) }
        $last = Select-HordeWeztermSessionWindow -Rows @($rows.value) -Pane $Pane -Native $before -NativeAfter $after
        # Only a title that fitted nothing is worth another reading; every other answer stands.
        if ($last.state -ceq "known" -or $last.reason -notlike "none of the terminal's*") { return $last }
    }
    return $last
}

# THE PORT (core/HostWindow.ps1). A caller reaches this file only through it, so nothing outside
# hosts/wezterm/ names the terminal (CONTRIBUTING 14).
Register-HordeHostWindowFinder -Name "wezterm" -Find { param($Seat) Find-HordeWeztermSessionWindow -Pane ("" + $Seat.pane) -Instance ("" + $Seat.instance) }
