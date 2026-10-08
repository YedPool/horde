# hosts/wezterm/Window.ps1 - which native window of WezTerm shows a given pane.
#
# THE FINDER HALF OF THE WEZTERM HOST (window attach design, 2026-10-06; core/HostWindow.ps1).
# A companion window is to stand beside the terminal window of one session. That session's record says
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
# pane and no native handle; the gui process had 16 terminal windows and 16 window ids.
#
# NOT BY THE TITLE'S FORMAT (trial of 2026-10-07). The first finder asked a window's title to EQUAL the
# title the listing gave for its pane, behind "[<tab>/<tabs>] ". Against the fleet's own terminal it
# answered unknown for the one window it was built for. MEASURED that day, read-only: the window of
# pane 18 was titled "[1/2] <U+25D0> name" when its process's windows were read, the listing a moment
# later said "<U+25D1> name", and the windows 300 ms after that said "[1/2] <U+2733> name" - a working
# session redraws a status glyph at the head of its title several times a second, one listing took
# about a second on that machine, and so the three never agreed while the session worked (with the
# session idle the same finder found the window six times of six). A title is text a session sets; the
# finder now uses what the terminal itself decides and Windows can see too:
#   - THE COUNT. One window id listed and one terminal window in the process: that window. ITS TITLE IS
#     NOT ASKED TO FIT, on purpose (review of 2026-10-06, finding C3).
#   - THE SIZE. The listing gives every pane's size in cells and in pixels, and where it starts in its
#     tab (size.cols, size.rows, size.pixel_width, size.pixel_height, left_col, top_row); Windows gives
#     every window's client size in real pixels. MEASURED 2026-10-07 on that terminal, 16 windows of
#     six sizes, cells of 14 x 32 pixels: the client was wider than the tab's cells by 28 to 40 pixels
#     and taller by 74 to 96, and in every one  cols = floor((client width - 28) / 14)  and
#     rows = floor((client height - 74) / 32) - one padding for all its windows, and what is left over
#     below one cell. THE PADDING IS NOT ASSUMED: it is whatever one pair of numbers explains every
#     window of the process at once (Get-HordeWeztermSizeCandidates). A window whose size, under every
#     padding that explains them all, is the size of the session's window and of no other listed window
#     IS the session's window - when the process has as many windows as the listing has window ids.
#   - THE TITLE, AS THE WEAKER SIGNAL, ONLY TO TELL APART WINDOWS OF ONE SIZE (or all of them, when
#     sizes say nothing: a listing without sizes, minimised windows, no one padding). A window carries
#     a listed window's title when its title CONTAINS the title of the active pane of one of that
#     window's tabs, whatever the terminal wrote around it. Exactly one window of the right size must
#     carry it, and it must not carry another same-sized window's title too.
#   None, or two, or one that fits two ids: unknown, with the reason. Never the likeliest.
# WHAT SIZE CANNOT TELL APART: two windows of the same size (then the title must); a window that is
# minimised (it has no client size; it is found by title, or by being the only one left); a terminal
# whose windows do not share one padding (a tab bar hidden on one-tab windows, screens of different
# scale) - then no padding explains them all and only titles are used.
# The windows are read before and after the listing; a title seen in either reading counts, a size must
# be the same in both, and the whole reading is tried a few times before the answer is unknown.
#
# AND A WINDOW IS BELIEVED ONLY WHEN IT IS FOUND TWICE. One reading can name the wrong window: titles
# stale in just the wrong way fit the session's window id and no other (review of 2026-10-06, finding
# C2). So when a reading finds a window, the whole reading - windows, listing, windows - is taken again
# a moment later (setting confirmWaitMs, 300 ms), and the answer is known only when both name the same
# native window for the same window id (Compare-HordeWeztermWindowReadings, which also says what this
# does not close). It costs one more call to the terminal and the wait, each time a window is found.
# The one-window case is held to it too: the count of one must hold twice.
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
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\ModuleSettings.ps1")
. (Join-Path $PSScriptRoot "Act.ps1")

# THE FINDER'S SETTINGS, declared once (core/ModuleSettings.ps1). A person overrides any of them in
# <HORDE_HOME>\settings\wezterm-window.json. A FILE THAT FAILS A CHECK IS REFUSED, AND THE FINDER THEN
# ANSWERS UNKNOWN WITHOUT ASKING THE TERMINAL ANYTHING: its reason is the settings' own findings, which
# name the file and each key that is wrong. It never reads a terminal with the defaults in a bad
# file's place - a person who set a number and mistyped it would be told a window, or told none, by
# numbers that are not theirs. Nothing else in this file holds one of these numbers.
$script:HordeWeztermWindowSettings = New-HordeModuleSettings -Module "wezterm-window" -Settings @(
    @{ name = "attempts";     kind = "whole";  default = 3;   min = 1; max = 10;   what = "How many times the windows and the listing are read before a title that fits nothing is believed." },
    @{ name = "retryWaitMs";  kind = "whole";  default = 200; min = 0; max = 5000; what = "Milliseconds waited before the windows and the listing are read again." },
    @{ name = "confirmWaitMs"; kind = "whole"; default = 300; min = 50; max = 5000; what = "Milliseconds between the reading that finds a window and the second reading that must name it again." },
    @{ name = "socketFolder"; kind = "folder"; default = "";                       what = "Folder the terminal keeps its sockets in; left out, the terminal's own place under the user's profile." }
)

function Get-HordeWeztermWindowSettings {
    # The settings as { state; values; findings; path }, from the one file under Horde's home; nothing is
    # written. state is defaults (no file), read, or refused, and a refusal carries no values.
    param([string]$HordeHome = "")
    return (Get-HordeModuleSettings -Declaration $script:HordeWeztermWindowSettings -HordeHome $HordeHome)
}

function Get-HordeWeztermWindowSockDir {
    # WHERE THE TERMINAL'S SOCKETS ARE, for this file: the folder a person set, or the terminal's own.
    # The terminal's own place has ONE owner in this host, Get-HordeWeztermSockDir in the act file, and
    # the default is handed to it: the place is written nowhere here (review of 2026-10-06, finding C7:
    # it was written in two files), and the suite checks that it is not.
    param([AllowEmptyString()][string]$Configured = "")
    if ($Configured -ne "") { return $Configured }
    return (Get-HordeWeztermSockDir)
}

function Wait-HordeWeztermWindowMoment {
    # The finder's one way of waiting: -Wait in a test, which is told how long and need not sleep.
    param([int]$Milliseconds, [scriptblock]$Wait = $null)
    if ($Milliseconds -le 0) { return }
    if ($null -ne $Wait) { [void](& $Wait $Milliseconds) } else { Start-Sleep -Milliseconds $Milliseconds }
}

# A TERMINAL WINDOW IS A VISIBLE, UNOWNED TOP-LEVEL WINDOW OF THE GUI PROCESS. Its other top-level windows
# - a probing window per terminal window, the input method's - are hidden or owned (measured
# 2026-10-06: 16 visible unowned windows, 16 hidden probing windows, 2 owned). NOT BY WINDOW CLASS: the
# class is whatever the terminal was started with (--class), and the first run against an isolated
# instance, started with a class of its own, found no window at all by the default class.

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
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c);
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }
    public class Entry { public long Handle; public string Title; public int Width; public int Height; }
    // Every visible, unowned top-level window of one process: handle, title, client size in real pixels.
    // THE SIZE IS ASKED FOR AS A PROCESS THAT KNOWS EACH SCREEN'S SCALE (per-monitor, version 2), for the
    // length of the reading and on this thread only: a process that does not is told sizes divided by the
    // screen's scale, which fit nothing the terminal lists. Where Windows cannot be asked that way, or
    // the window is minimised, the size is 0 x 0: not known, never a guess.
    public static List<Entry> List(uint processId) {
        var found = new List<Entry>();
        IntPtr was = IntPtr.Zero; bool real = false;
        try { was = SetThreadDpiAwarenessContext((IntPtr)(-4)); real = was != IntPtr.Zero; } catch (EntryPointNotFoundException) { real = false; }
        try {
            EnumWindows((h, l) => {
                uint pid; GetWindowThreadProcessId(h, out pid);
                if (pid != processId || !IsWindowVisible(h) || GetWindow(h, 4) != IntPtr.Zero) return true;   // GW_OWNER
                var title = new StringBuilder(GetWindowTextLengthW(h) + 2); GetWindowTextW(h, title, title.Capacity);
                var e = new Entry { Handle = h.ToInt64(), Title = title.ToString(), Width = 0, Height = 0 };
                RECT c;
                if (real && !IsIconic(h) && GetClientRect(h, out c)) { e.Width = c.R - c.L; e.Height = c.B - c.T; }
                found.Add(e);
                return true;
            }, IntPtr.Zero);
        } finally { if (real) SetThreadDpiAwarenessContext(was); }
        return found;
    }
}
'@

function Get-HordeWeztermNativeWindows {
    # The terminal windows of one gui process, as { handle; title; width; height }, the size being the
    # client area's in real pixels. A minimised window is listed, with no size (0 x 0): it is still the
    # session's window.
    param([Parameter(Mandatory = $true)][long]$ProcessId)
    if ($null -eq ("HordeWeztermWindows" -as [type])) { Add-Type -TypeDefinition $script:HordeWeztermWindowSource }
    return @([HordeWeztermWindows]::List([uint32]$ProcessId) | ForEach-Object { [pscustomobject]@{ handle = [long]$_.Handle; title = "" + $_.Title; width = [long]$_.Width; height = [long]$_.Height } })
}

function Get-HordeWeztermPaneShape {
    # Where one pane of the listing sits in its tab and how large its cells are, as { cols; rows; left;
    # top; cellWidth; cellHeight }, or $null when the listing does not say so in whole numbers. NOTHING
    # IS CONVERTED OR FILLED IN: a pane with no left_col would make a split tab look as narrow as one of
    # its panes, and a narrower tab is another window's size. A listing without sizes is still a
    # listing; it only cannot tell windows apart by size.
    param($Pane)
    if ($null -eq $Pane.PSObject.Properties["size"] -or $null -eq $Pane.size) { return $null }
    $n = @{}
    foreach ($f in @("cols", "rows", "pixel_width", "pixel_height")) {
        $v = $Pane.size.PSObject.Properties[$f]
        if ($null -eq $v -or ($v.Value -isnot [int] -and $v.Value -isnot [long]) -or $v.Value -le 0) { return $null }
        $n[$f] = [long]$v.Value
    }
    foreach ($f in @("left_col", "top_row")) {
        $v = $Pane.PSObject.Properties[$f]
        if ($null -eq $v -or ($v.Value -isnot [int] -and $v.Value -isnot [long]) -or $v.Value -lt 0) { return $null }
        $n[$f] = [long]$v.Value
    }
    if (($n["pixel_width"] % $n["cols"]) -ne 0 -or ($n["pixel_height"] % $n["rows"]) -ne 0) { return $null }
    return [pscustomobject]@{ cols = $n["cols"]; rows = $n["rows"]; left = $n["left_col"]; top = $n["top_row"]; cellWidth = [long]($n["pixel_width"] / $n["cols"]); cellHeight = [long]($n["pixel_height"] / $n["rows"]) }
}

function Read-HordeWeztermWindowList {
    # The panes of `cli list --format json`, with what tells windows apart, as an answer: known list
    # of { pane; window; tab; title; active; zoomed; shape }, or unknown when the output is not that
    # list. shape is Get-HordeWeztermPaneShape's, $null where the listing gives no usable size.
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
        # EACH FIELD IS OF ITS OWN KIND OR THE LISTING IS UNKNOWN; none is converted. [bool] of any text
        # that is not empty is true, and "" + $null is "": read that way, "is_active":"no" was an active
        # pane and a missing title an empty one (review of 2026-10-06, finding C6).
        foreach ($id in @("pane_id", "window_id", "tab_id")) {
            $number = $p.PSObject.Properties[$id].Value
            if (($number -isnot [int] -and $number -isnot [long]) -or $number -lt 0) { return (New-HordeUnknown -Reason ("a pane in the terminal's list has a " + $id + " that is not a whole number, so the list is not one this finder can read")) }
        }
        if ($p.title -isnot [string]) { return (New-HordeUnknown -Reason "a pane in the terminal's list has a title that is not text, so no window's title can be compared with it") }
        if ($p.is_active -isnot [bool]) { return (New-HordeUnknown -Reason "a pane in the terminal's list has an is_active that is not true or false, so its window cannot be told from the others") }
        $zoomed = $false
        if ($null -ne $p.PSObject.Properties["is_zoomed"]) {
            if ($p.is_zoomed -isnot [bool]) { return (New-HordeUnknown -Reason "a pane in the terminal's list has an is_zoomed that is not true or false, so its window's title cannot be worked out") }
            $zoomed = $p.is_zoomed
        }
        [void]$rows.Add([pscustomobject]@{ pane = ("" + $p.pane_id); window = ("" + $p.window_id); tab = ("" + $p.tab_id); title = $p.title; active = $p.is_active; zoomed = $zoomed; shape = (Get-HordeWeztermPaneShape -Pane $p) })
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
    # Does a window titled -Title carry the title of the listed window whose panes are -Rows (all of one
    # window id)? It does when it CONTAINS, character for character, the title of the active pane of one
    # of that window's tabs: whatever the terminal writes around a pane's title - a tab count, a zoom
    # mark, a format of the person's own - is not this finder's to know (header). A pane with no title
    # is carried by nothing: the empty text is inside every title.
    param([AllowEmptyString()][string]$Title, [Parameter(Mandatory = $true)][object[]]$Rows)
    foreach ($row in @($Rows | Where-Object { $_.active })) {
        if ($row.title -cne "" -and $Title.IndexOf($row.title, [System.StringComparison]::Ordinal) -ge 0) { return $true }
    }
    return $false
}

function Get-HordeWeztermWindowShapes {
    # The size of every listed window, from its panes: { shapes; why }. shapes is one { window; cols;
    # rows; width; height; cellWidth; cellHeight } per window id - a tab is as wide as its panes reach
    # (left + cols) and every tab of a window is the window's size (measured 2026-10-07: 37 panes in 16
    # windows, every tab of a window the same size, in front or not) - or $null, with why, when the
    # listing does not give ONE size for every window. A PURE FUNCTION.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Rows)
    $shapes = New-Object System.Collections.ArrayList
    foreach ($id in @($Rows | ForEach-Object { $_.window } | Sort-Object -Unique)) {
        $tabs = @{}
        $cell = $null
        foreach ($row in @($Rows | Where-Object { $_.window -ceq $id })) {
            if ($null -eq $row.shape) { return [pscustomobject]@{ shapes = $null; why = ("the listing gives no size for pane " + $row.pane) } }
            if ($null -eq $cell) { $cell = $row.shape }
            if ($row.shape.cellWidth -ne $cell.cellWidth -or $row.shape.cellHeight -ne $cell.cellHeight) { return [pscustomobject]@{ shapes = $null; why = ("the panes of window " + $id + " do not have cells of one size") } }
            if (-not $tabs.ContainsKey($row.tab)) { $tabs[$row.tab] = [pscustomobject]@{ cols = [long]0; rows = [long]0 } }
            $tabs[$row.tab].cols = [Math]::Max($tabs[$row.tab].cols, $row.shape.left + $row.shape.cols)
            $tabs[$row.tab].rows = [Math]::Max($tabs[$row.tab].rows, $row.shape.top + $row.shape.rows)
        }
        if (@($tabs.Values | ForEach-Object { "" + $_.cols + "x" + $_.rows } | Sort-Object -Unique).Count -ne 1) { return [pscustomobject]@{ shapes = $null; why = ("the tabs of window " + $id + " are not of one size") } }
        $tab = @($tabs.Values)[0]
        [void]$shapes.Add([pscustomobject]@{ window = $id; cols = $tab.cols; rows = $tab.rows; width = ($tab.cols * $cell.cellWidth); height = ($tab.rows * $cell.cellHeight); cellWidth = $cell.cellWidth; cellHeight = $cell.cellHeight })
    }
    return [pscustomobject]@{ shapes = $shapes.ToArray(); why = "" }
}

function Get-HordeWeztermAxisFits {
    # ONE DIRECTION OF THE PADDING (header, THE SIZE). -Lengths are the windows' client widths (or
    # heights) in pixels, -Spans what the listed windows' cells cover in that direction, as texts
    # "<pixels>|<cell>". A padding fits a length and a span when what is left of the length after the
    # padding and the span is less than one cell. Returned: every DIFFERENT way some padding of zero or
    # more gives every length at least one span, each as a table length -> the spans it then fits. The
    # paddings tried are, for each length and span, the largest that still fits the pair: going up from
    # any padding, nothing stops fitting before one of those is reached, so every way a padding can fit
    # is one of theirs, or has less in it and so adds nothing a window could be. A PURE FUNCTION.
    param([Parameter(Mandatory = $true)][long[]]$Lengths, [Parameter(Mandatory = $true)][string[]]$Spans)
    $tried = @{}
    $ways = [ordered]@{}
    foreach ($length in $Lengths) {
        foreach ($span in $Spans) {
            $padding = $length - [long]($span -split "\|")[0]
            if ($padding -lt 0 -or $tried.ContainsKey($padding)) { continue }
            $tried[$padding] = $true
            $way = @{}
            $whole = $true
            foreach ($l in $Lengths) {
                $fits = @($Spans | Where-Object { $left = $l - $padding - [long]($_ -split "\|")[0]; ($left -ge 0 -and $left -lt [long]($_ -split "\|")[1]) })
                if ($fits.Count -eq 0) { $whole = $false; break }
                $way["" + $l] = $fits
            }
            if (-not $whole) { continue }
            $key = (@($Lengths | ForEach-Object { "" + $_ + "=" + ($way["" + $_] -join ",") }) -join ";")
            if (-not $ways.Contains($key)) { $ways[$key] = $way }
        }
    }
    return @($ways.Values)
}

function Get-HordeWeztermSizeCandidates {
    # WHICH LISTED WINDOWS EACH WINDOW ON SCREEN COULD BE, BY SIZE ALONE (header, THE SIZE): a table
    # native handle -> window ids, or $null when no one padding explains every window that has a size.
    # -Shapes is Get-HordeWeztermWindowShapes's, -Sized the windows with a client size. A window could be
    # a listed window when, under SOME padding across and down that gives every sized window a listed
    # window - and no group of windows fewer listed windows than it has members - its client area holds
    # exactly that window's columns and rows. More than one padding may do; then a window could be any
    # of what any of them says, so a doubt widens the answer and never narrows it. A PURE FUNCTION.
    param([Parameter(Mandatory = $true)][object[]]$Shapes, [Parameter(Mandatory = $true)][object[]]$Sized)
    $across = @(Get-HordeWeztermAxisFits -Lengths @($Sized | ForEach-Object { [long]$_.width } | Sort-Object -Unique) -Spans @($Shapes | ForEach-Object { "" + $_.width + "|" + $_.cellWidth } | Sort-Object -Unique))
    $down = @(Get-HordeWeztermAxisFits -Lengths @($Sized | ForEach-Object { [long]$_.height } | Sort-Object -Unique) -Spans @($Shapes | ForEach-Object { "" + $_.height + "|" + $_.cellHeight } | Sort-Object -Unique))
    $could = @{}
    $explained = $false
    foreach ($x in $across) {
        foreach ($y in $down) {
            $each = @{}
            $groups = @{}
            $whole = $true
            foreach ($n in $Sized) {
                $ids = @($Shapes | Where-Object { $x["" + [long]$n.width] -ccontains ("" + $_.width + "|" + $_.cellWidth) -and $y["" + [long]$n.height] -ccontains ("" + $_.height + "|" + $_.cellHeight) } | ForEach-Object { $_.window })
                if ($ids.Count -eq 0) { $whole = $false; break }
                $each["" + [long]$n.handle] = $ids
                $group = $ids -join ","
                if (-not $groups.ContainsKey($group)) { $groups[$group] = 0 }
                $groups[$group]++
                if ($groups[$group] -gt $ids.Count) { $whole = $false; break }
            }
            if (-not $whole) { continue }
            $explained = $true
            foreach ($handle in @($each.Keys)) {
                if (-not $could.ContainsKey($handle)) { $could[$handle] = New-Object System.Collections.ArrayList }
                foreach ($id in $each[$handle]) { if ($could[$handle] -cnotcontains $id) { [void]$could[$handle].Add($id) } }
            }
        }
    }
    if (-not $explained) { return $null }
    return $could
}

function New-HordeWeztermUnsettled {
    # An unknown that another reading may settle: a title caught between two states, or two readings
    # that disagreed. It carries a mark, readAgain, so the finder decides by the mark and never by the
    # words of a reason; every other unknown stands as it is, because reading again cannot change it.
    param([Parameter(Mandatory = $true)][string]$Reason)
    $unsettled = New-HordeUnknown -Reason $Reason
    Add-Member -InputObject $unsettled -NotePropertyName readAgain -NotePropertyValue $true
    return $unsettled
}

function Compare-HordeWeztermWindowReadings {
    # THE SECOND PROOF (review of 2026-10-06, finding C2 and decision 4). One reading can name the
    # wrong window as known: with two panes just retitled and the listing newer than both readings of
    # the windows, a stale title fits the session's window id and no other (the review ran that case,
    # and the suite keeps it). So a window is believed only when a second whole reading, taken a moment
    # later, names the same native window for the same window id. -First and -Second are the answers
    # of the two readings, -ApartMs the wait between them. A PURE FUNCTION.
    # WHAT THIS DOES NOT CLOSE: titles that stay stale in the same way through both readings, where a
    # title is what decided. The wait shortens the time a coincidence must last; only an id shared by
    # the terminal's listing and the operating system would end it, and this terminal gives none.
    param([Parameter(Mandatory = $true)]$First, [Parameter(Mandatory = $true)]$Second, [Parameter(Mandatory = $true)][int]$ApartMs)
    if ($First.state -cne "known") { return $First }
    if ($Second.state -cne "known") { return (New-HordeWeztermUnsettled -Reason ("a window was found for the pane and was not found again on a second reading " + $ApartMs + " ms later (" + $Second.reason + "), and a match that does not hold twice is not believed")) }
    if ([long]$First.value.handle -ne [long]$Second.value.handle) { return (New-HordeWeztermUnsettled -Reason ("two readings " + $ApartMs + " ms apart named different windows for the pane (" + $First.value.handle + ", then " + $Second.value.handle + "), so neither is believed")) }
    if ("" + $First.value.window -cne "" + $Second.value.window) { return (New-HordeWeztermUnsettled -Reason ("two readings " + $ApartMs + " ms apart put the pane in different windows of the terminal's own numbering (" + $First.value.window + ", then " + $Second.value.window + "), so neither is believed")) }
    return (New-HordeKnown -Value ([pscustomobject]@{ handle = [long]$Second.value.handle; window = $Second.value.window; detail = ("" + $Second.value.detail + ", and again on a second reading " + $ApartMs + " ms later") }))
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
    # Each terminal window with every title it was seen to carry, before and after the listing, and its
    # client size - which must be the same in both readings, or it is not known.
    $seen = [ordered]@{}
    foreach ($n in (@($Native) + @($NativeAfter))) {
        $key = "" + [long]$n.handle
        if (-not $seen.Contains($key)) { $seen[$key] = [pscustomobject]@{ handle = [long]$n.handle; titles = (New-Object System.Collections.ArrayList); width = [long]$n.width; height = [long]$n.height } }
        if ($seen[$key].titles -cnotcontains $n.title) { [void]$seen[$key].titles.Add("" + $n.title) }
        if ([long]$n.width -ne $seen[$key].width -or [long]$n.height -ne $seen[$key].height) { $seen[$key].width = [long]0; $seen[$key].height = [long]0 }
    }
    $all = @($seen.Values)
    if ($all.Count -eq 0) { return (New-HordeUnknown -Reason "the terminal's process has no terminal window on screen, so there is none to stand beside") }
    $windowIds = @($Rows | ForEach-Object { $_.window } | Sort-Object -Unique)
    if ($windowIds.Count -eq 1 -and $all.Count -eq 1) {
        return (New-HordeKnown -Value ([pscustomobject]@{ handle = $all[0].handle; window = $windowId; detail = "the terminal has one window" }))
    }
    # BY SIZE (header). $could says which listed windows each sized window could be; $noSizes why sizes
    # say nothing, when they do not.
    $sized = @($all | Where-Object { $_.width -gt 0 -and $_.height -gt 0 })
    $unsized = @($all | Where-Object { $_.width -le 0 -or $_.height -le 0 })
    $listed = Get-HordeWeztermWindowShapes -Rows $Rows
    $could = $null
    $noSizes = $listed.why
    if ($null -ne $listed.shapes) {
        if ($sized.Count -eq 0) { $noSizes = "none of the terminal's windows has a size on screen" }
        else { $could = Get-HordeWeztermSizeCandidates -Shapes $listed.shapes -Sized $sized; if ($null -eq $could) { $noSizes = "no one padding explains the sizes of the terminal's windows" } }
    }
    $pool = $all
    $cells = ""
    if ($null -ne $could) {
        $shape = @($listed.shapes | Where-Object { $_.window -ceq $windowId })[0]
        $cells = "" + $shape.cols + " x " + $shape.rows + " cells"
        $bySize = @($sized | Where-Object { $could["" + $_.handle] -ccontains $windowId })
        $theirs = @($bySize | ForEach-Object { $could["" + $_.handle] } | Sort-Object -Unique)
        # AS MANY WINDOWS AS THE LISTED WINDOWS THEY COULD BE: each is one of those, so the session's
        # window is among them and no window without a size can be it. Fewer, and one may be.
        if ($bySize.Count -gt 0 -and $theirs.Count -le $bySize.Count) {
            $pool = $bySize
            if ($pool.Count -eq 1) { return (New-HordeKnown -Value ([pscustomobject]@{ handle = $pool[0].handle; window = $windowId; detail = ("the one of the terminal's " + $all.Count + " windows with the size of the pane's window (" + $cells + ")") })) }
        } else {
            $pool = @($bySize) + @($unsized)
            # THE ONE LEFT OVER: no sized window could be the session's, one window has no size, and the
            # process has exactly as many windows as the listing has window ids - so every other window
            # is another's, and this one is the session's, minimised.
            if ($bySize.Count -eq 0 -and $pool.Count -eq 1 -and $all.Count -eq $windowIds.Count) { return (New-HordeKnown -Value ([pscustomobject]@{ handle = $pool[0].handle; window = $windowId; detail = ("the one of the terminal's " + $all.Count + " windows that is not another's by size: the pane's window has no one size on screen (minimised, or its size was changing)") })) }
        }
        if ($pool.Count -eq 0) { return (New-HordeWeztermUnsettled -Reason ("none of the terminal's " + $all.Count + " windows has the size of the window of pane " + $Pane + " (" + $cells + "), so it is not on screen as the terminal lists it")) }
    }
    # BY TITLE, among the windows size has left (all of them when sizes say nothing).
    $fits = { param($Window, [string]$Id) $rowsOf = @($Rows | Where-Object { $_.window -ceq $Id }); foreach ($t in @($Window.titles)) { if (Test-HordeWeztermWindowTitle -Title $t -Rows $rowsOf) { return $true } }; return $false }
    $matched = @($pool | Where-Object { & $fits $_ $windowId })
    if ($matched.Count -eq 0) {
        if ($null -ne $could) { return (New-HordeWeztermUnsettled -Reason ("" + $pool.Count + " of the terminal's " + $all.Count + " windows could be the window of pane " + $Pane + " by size (" + $cells + "), and none of them carries its title, so which it is cannot be told")) }
        return (New-HordeWeztermUnsettled -Reason ("none of the terminal's " + $all.Count + " windows carries the title of the window of pane " + $Pane + ", and sizes do not tell them apart (" + $noSizes + "): its title changed while it was read, or this terminal titles its windows its own way"))
    }
    if ($matched.Count -gt 1) {
        return (New-HordeUnknown -Reason ("" + $matched.Count + " of the terminal's windows carry the title of the window of pane " + $Pane + $(if ($null -ne $could) { " and could be it by size (" + $cells + ")" } else { "" }) + ", and one is never chosen over another"))
    }
    $one = $matched[0]
    $others = @($windowIds | Where-Object { $_ -cne $windowId -and ($null -eq $could -or $one.width -le 0 -or $one.height -le 0 -or $could["" + $one.handle] -ccontains $_) -and (& $fits $one $_) })
    if ($others.Count -gt 0) {
        return (New-HordeUnknown -Reason ("the one window that carries the title of the window of pane " + $Pane + " carries the title of another of the terminal's windows too, so which it is cannot be told"))
    }
    if ($null -ne $could) { return (New-HordeKnown -Value ([pscustomobject]@{ handle = $one.handle; window = $windowId; detail = ("the one of " + $pool.Count + " windows that could be the pane's window by size (" + $cells + ") that carries its title") })) }
    return (New-HordeKnown -Value ([pscustomobject]@{ handle = $one.handle; window = $windowId; detail = ("the one of the terminal's " + $all.Count + " windows that carries the title of its pane") }))
}

function Find-HordeWeztermSessionWindow {
    # The native window showing pane -Pane of the terminal -Instance, as an answer (header). -Settings
    # is what Get-HordeWeztermWindowSettings gives, for a caller that read them already; without it
    # they are read from Horde's home. Settings that were refused are the answer: unknown, with their
    # findings, and nothing is read (see THE FINDER'S SETTINGS). -Runner, -Windows, -ProcessStart and -Wait replace the
    # terminal's command, the window reader, the process clock and the sleep in a test; -ReadAs says
    # which code page a runner's answer was read in, and the real call's is always this process's own.
    param([AllowEmptyString()][string]$Pane, [AllowEmptyString()][string]$Instance, $Settings = $null,
        [scriptblock]$Runner = $null, [scriptblock]$Windows = $null, [scriptblock]$ProcessStart = $null, [System.Text.Encoding]$ReadAs = $null, [scriptblock]$Wait = $null)
    if ($null -eq $Settings) { $Settings = Get-HordeWeztermWindowSettings }
    # Anything but the two states that carry values is a refusal: the finder goes on only with values it was given.
    if ("" + $Settings.state -cne "defaults" -and "" + $Settings.state -cne "read") {
        return (New-HordeUnknown -Reason ("the finder's settings are refused, so no terminal was asked: " + (@($Settings.findings) -join "; ")))
    }
    return (Find-HordeWeztermSessionWindowWith -Pane $Pane -Instance $Instance -Values $Settings.values -Runner $Runner -Windows $Windows -ProcessStart $ProcessStart -ReadAs $ReadAs -Wait $Wait)
}

function Find-HordeWeztermSessionWindowWith {
    # Find-HordeWeztermSessionWindow's work, with the settings' values in hand (-Values).
    param([AllowEmptyString()][string]$Pane, [AllowEmptyString()][string]$Instance, [Parameter(Mandatory = $true)]$Values,
        [scriptblock]$Runner = $null, [scriptblock]$Windows = $null, [scriptblock]$ProcessStart = $null, [System.Text.Encoding]$ReadAs = $null, [scriptblock]$Wait = $null)
    if ($Pane -cnotmatch '\A[0-9]{1,9}\z') { return (New-HordeUnknown -Reason "the session's record names a pane this terminal does not number that way, so it is not one of this terminal's") }
    # The leaf name only: a record never chooses the folder the socket is looked for in.
    if ($Instance -cnotmatch $script:HordeWeztermSocketLeaf) { return (New-HordeUnknown -Reason "the session's record does not name one of this terminal's instances (gui-sock-<pid>)") }
    $target = New-HordeWeztermTarget -Socket (Join-Path (Get-HordeWeztermWindowSockDir -Configured $Values.socketFolder) $Instance) -ProcessStart $ProcessStart
    if ($target.state -cne "known") { return (New-HordeUnknown -Reason ("the session's terminal is not running: " + $target.reason)) }
    $last = $null
    for ($try = 1; $try -le $Values.attempts; $try++) {
        if ($try -gt 1) { Wait-HordeWeztermWindowMoment -Milliseconds $Values.retryWaitMs -Wait $Wait }
        $last = Read-HordeWeztermWindowReading -Target $target.value -Pane $Pane -Runner $Runner -Windows $Windows -ReadAs $ReadAs
        if ($last.state -ceq "known") {
            # Found once. Believed only if a second whole reading, a moment later, says the same.
            Wait-HordeWeztermWindowMoment -Milliseconds $Values.confirmWaitMs -Wait $Wait
            $again = Read-HordeWeztermWindowReading -Target $target.value -Pane $Pane -Runner $Runner -Windows $Windows -ReadAs $ReadAs
            $last = Compare-HordeWeztermWindowReadings -First $last -Second $again -ApartMs $Values.confirmWaitMs
            if ($last.state -ceq "known") { return $last }
        }
        # Only an answer another reading may settle is read again; every other answer stands.
        if ($null -eq $last.PSObject.Properties["readAgain"]) { return $last }
    }
    return $last
}

function Read-HordeWeztermWindowReading {
    # ONE WHOLE READING of the named terminal -Target: its process's windows, its listing, its windows
    # again, and the decision on those three - the answer of Select-HordeWeztermSessionWindow, or the
    # unknown of whatever could not be read.
    param([Parameter(Mandatory = $true)]$Target, [Parameter(Mandatory = $true)][string]$Pane,
        [scriptblock]$Runner = $null, [scriptblock]$Windows = $null, [System.Text.Encoding]$ReadAs = $null)
    $before = $null; $after = $null
    if ($null -ne $Windows) { $before = @(& $Windows ([long]$Target.guiPid)) } else { $before = @(Get-HordeWeztermNativeWindows -ProcessId ([long]$Target.guiPid)) }
    $readIn = $ReadAs
    if ($null -eq $Runner) { $readIn = Get-HordeWeztermAnswerEncoding }
    $call = Invoke-HordeWeztermCall -Rest @("list", "--format", "json") -Target $Target -Runner $Runner
    if ($call.code -ne 0) { return (New-HordeUnknown -Reason ("the terminal did not list its panes (exit " + $call.code + "): " + ("" + $call.err).Trim())) }
    $listing = $call.out
    if ($null -ne $readIn) {
        $mended = ConvertTo-HordeWeztermAnswerText -Text (@($call.out) -join "`n") -ReadAs $readIn
        if ($mended.state -cne "known") { return $mended }
        $listing = $mended.value
    }
    $rows = Read-HordeWeztermWindowList -Raw $listing
    if ($rows.state -cne "known") { return $rows }
    if ($null -ne $Windows) { $after = @(& $Windows ([long]$Target.guiPid)) } else { $after = @(Get-HordeWeztermNativeWindows -ProcessId ([long]$Target.guiPid)) }
    return (Select-HordeWeztermSessionWindow -Rows @($rows.value) -Pane $Pane -Native $before -NativeAfter $after)
}

# THE PORT (core/HostWindow.ps1). A caller reaches this file only through it, so nothing outside
# hosts/wezterm/ names the terminal (CONTRIBUTING 14).
Register-HordeHostWindowFinder -Name "wezterm" -Find { param($Seat) Find-HordeWeztermSessionWindow -Pane ("" + $Seat.pane) -Instance ("" + $Seat.instance) }
