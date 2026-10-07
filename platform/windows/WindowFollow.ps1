# platform/windows/WindowFollow.ps1 - the Windows follower of core/WindowFollowPort.ps1: keep one
# window of this process beside another window this process does not own.
#
# A CALLER NEVER NAMES THIS FILE'S FUNCTIONS. It loads the port and every follower found by folder,
# and asks the port; this file registers itself there at its last line. What the verbs mean, and what a
# follow record is, is written once, in the port's header. This file is HOW Windows does them.
#
# WHAT IT DOES, and nothing else: given the native handle of a window - any window, of any program -
# and the handle of a window of this process, it makes the second a companion of the first: placed
# relative to it, re-placed when it moves or is resized, above it, hidden while it is minimised and
# back when it is restored, and never given the keyboard by any of that. It does not know what either
# window shows or how the first one was found.
#
# HOW, as the proof of 2026-10-06 measured it against a window of another program started for the
# purpose, and as test/test-window-follow.ps1 measures on every run with two plain windows of its own:
#   - THE OTHER WINDOW IS MADE THE OWNER of ours (GWLP_HWNDPARENT), which Windows allows across
#     programs. An owned window always stands above its owner, is hidden when the owner is minimised
#     and returns when it is restored; Windows does all three, and nothing here polls for them.
#     WHETHER WINDOWS DID IT IS READ BACK: a follow whose owner was not set is "failed" with Windows'
#     error, never "following".
#   - WINDOWS REPORTS EVERY MOVE AND RESIZE of the other window's process (SetWinEventHook,
#     EVENT_OBJECT_LOCATIONCHANGE, out of context), and ours is placed again each time. The proof
#     passed all eight of its checks: placed on attach, above, after a move, a resize, a minimise, a
#     restore and a maximise, above again, with the foreground window the same throughout.
#   - EVERY PLACEMENT IS SWP_NOACTIVATE, so placing never takes the keyboard.
#   - ABOVE IT FROM THE START: Windows orders an owned window above its owner when the owner is next
#     activated, so a companion made before the other window is stood directly above it when the
#     follow starts, and not at the top of every program's windows.
#
# WHERE IT IS PLACED is the port's pure function, Get-HordeWindowFollowPlacement, and nothing of this
# file's: the native half only carries its answer to Windows. The numbers it works from are the module's
# settings, which the port hands to Start and this file keeps for as long as the follow lasts.
#
# PIXELS ARE REAL PIXELS only when the process draws at each screen's real scale, and asking Windows
# for that has ONE owner, platform/windows/Scale.ps1, loaded here and handed to the port as this
# follower's RealScale: a caller that works out a place before its window exists asks for it first, or
# the rectangle it reads is a scaled one. (Measured 2026-10-06 with the process made aware first, at
# one and a half times the ordinary scale: a window at 60,60 of 1100 by 640 real pixels, and the
# companion standing at 644,132, 480 by 532 - exactly the place worked out for it. What it looked like
# in the first second, before it was followed, was not observed.) This file reads the other window's
# scale (GetDpiForWindow, over 96) so that margins and smallest sizes are the same physical size on
# every screen. NOT MEASURED: a second monitor or a second scale - the measuring machine has one screen.
#
# WHAT A CALLER MUST KNOW ABOUT THE OTHER WINDOW GOING AWAY. Both are measured on every run by
# test/test-window-follow.ps1, against a plain window of another process (first 2026-10-06 and
# 2026-10-07; not against a terminal's window):
#   - Its PROCESS ENDS (ended by its handle): our window stays, and Windows reads its owner back as
#     none. The next ask answers "lost".
#   - Its WINDOW IS CLOSED while its process lives on: Windows documents that an owned window is
#     destroyed with its owner. THAT IS NOT WHAT HAPPENS ACROSS PROGRAMS: ours is not destroyed. It
#     stays, its owner read back as none, and the next ask answers "lost".
# Nothing tells this file the moment the other window goes: a caller learns "lost" by asking, on its
# own timer. Following a session into a new window is a later slice's.
#
# ONE FOLLOW AT A TIME: the native half keeps one hook and one target, so starting a second follow
# ends the first.
#
# THE TYPE IS COMPILED ON FIRST USE, not when this file is loaded, and its name carries a version, so
# a later change is a new type and never a clash with one already loaded in the session
# (platform/windows/Scale.ps1 does the same). NOT MEASURED: a 32-bit process, where user32 has no
# SetWindowLongPtrW; the port answers "unavailable" with what Windows said.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.
. (Join-Path $PSScriptRoot "Scale.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\Platform.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\WindowFollowPort.ps1")

# The one follow of this process: { target; companion; mode; settings; state; reason; placed; placements }, or
# nothing. Kept across a second load of this file.
if ($null -eq (Get-Variable -Name HordeWindowsFollow -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeWindowsFollow = $null }

function Get-HordeWindowsFollowSource { return @'
using System;
using System.Runtime.InteropServices;
public static class HordeWindowsFollowV1 {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    public delegate void WinEventDelegate(IntPtr hook, uint evt, IntPtr hwnd, int idObject, int idChild, uint thread, uint time);
    [DllImport("user32.dll")] static extern IntPtr SetWinEventHook(uint min, uint max, IntPtr mod, WinEventDelegate cb, uint pid, uint tid, uint flags);
    [DllImport("user32.dll")] static extern bool UnhookWinEvent(IntPtr hook);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)] static extern IntPtr SetWindowLongPtr(IntPtr h, int index, IntPtr value);
    [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr h);

    static IntPtr target = IntPtr.Zero, hook = IntPtr.Zero;
    static WinEventDelegate keep;       // held, or the delegate is collected while Windows still calls it
    static Action moved;
    public static int Events;

    static void OnEvent(IntPtr h, uint evt, IntPtr hwnd, int idObject, int idChild, uint thread, uint time) {
        // The window itself (OBJID_WINDOW), not its caret, its cursor or a child.
        if (hwnd != target || idObject != 0) return;
        Events++;
        if (moved != null) { moved(); }
    }
    public static bool Exists(long h) { return IsWindow(new IntPtr(h)); }
    public static bool Minimised(long h) { return IsIconic(new IntPtr(h)); }
    public static uint ProcessOf(long h) { uint pid; GetWindowThreadProcessId(new IntPtr(h), out pid); return pid; }
    public static int Dpi(long h) { try { uint d = GetDpiForWindow(new IntPtr(h)); return d == 0 ? 96 : (int)d; } catch (EntryPointNotFoundException) { return 96; } }
    public static int[] Rect(long h) { RECT r; if (!GetWindowRect(new IntPtr(h), out r)) return null; return new int[] { r.Left, r.Top, r.Right, r.Bottom }; }
    // SWP_NOZORDER (4) | SWP_NOACTIVATE (0x10): the size and the place, never the order, never the keyboard.
    public static bool Place(long h, int x, int y, int cx, int cy) { return SetWindowPos(new IntPtr(h), IntPtr.Zero, x, y, cx, cy, 0x0004 | 0x0010); }
    // { code, error }: 0 the other window owns ours and its moves are reported; 1 Windows did not make
    // it the owner, error being its last error; 2 Windows would not report its moves.
    public static int[] Attach(long targetWindow, long companion, Action onMoved) {
        Unhook();
        IntPtr ownerBefore = GetWindow(new IntPtr(companion), 4);     // GW_OWNER
        SetWindowLongPtr(new IntPtr(companion), -8, new IntPtr(targetWindow));     // GWLP_HWNDPARENT: the other window owns ours
        int error = Marshal.GetLastWin32Error();
        // THE RESULT IS READ BACK, not assumed: the call's own return is the owner before, which is
        // nothing both for a window that had none and for a refusal. Windows refuses, for one, an
        // owner that is itself owned by our window (error 87, measured 2026-10-07).
        if (GetWindow(new IntPtr(companion), 4) != new IntPtr(targetWindow)) { return new int[] { 1, error }; }
        target = new IntPtr(targetWindow);
        moved = onMoved;
        Events = 0;     // the reports counted are this follow's, not every follow's since the process began
        // Windows keeps an owned window above its owner from the owner's next activation on, NOT from
        // the moment it is owned: a companion made before the other window stood under it (measured
        // 2026-10-07). So it is stood directly above the other window now - under the window that was
        // just above that one (GW_HWNDPREV), never at the top of every program's windows - and with
        // SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE, so nothing but the order changes.
        IntPtr above = GetWindow(target, 3);
        if (above != new IntPtr(companion)) { SetWindowPos(new IntPtr(companion), above, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010); }
        keep = new WinEventDelegate(OnEvent);
        // EVENT_OBJECT_LOCATIONCHANGE of the other window's process, delivered to this thread's message loop.
        hook = SetWinEventHook(0x800B, 0x800B, IntPtr.Zero, keep, ProcessOf(targetWindow), 0, 0);
        if (hook != IntPtr.Zero) { return new int[] { 0, 0 }; }
        // Not followed after all: ours goes back to the owner it had, and nothing is listened for.
        SetWindowLongPtr(new IntPtr(companion), -8, ownerBefore);
        Unhook();
        return new int[] { 2, 0 };
    }
    // The delegate is NOT let go here: this may be called from inside it, when a report of a move
    // finds the other window gone, and Windows is still on its way back through it. The next Attach
    // replaces it.
    public static void Unhook() {
        if (hook != IntPtr.Zero) { UnhookWinEvent(hook); hook = IntPtr.Zero; }
        target = IntPtr.Zero; moved = null;
    }
    public static void Disown(long companion) {
        if (IsWindow(new IntPtr(companion))) { SetWindowLongPtr(new IntPtr(companion), -8, IntPtr.Zero); }
    }
}
'@ }

function Initialize-HordeWindowsFollowType {
    if (-not ("HordeWindowsFollowV1" -as [type])) { Add-Type -TypeDefinition (Get-HordeWindowsFollowSource) -ErrorAction Stop }
}

function ConvertTo-HordeWindowsFollowStart {
    # PURE. What the native half answered a start, as { state; reason }. -Code is 0, 1 or 2 as Attach
    # gives it; -ErrorCode is Windows' last error and counts only when the owner was not set.
    param([Parameter(Mandatory = $true)][int]$Code, [int]$ErrorCode = 0)
    if ($Code -eq 0) { return [pscustomobject]@{ state = "following"; reason = "" } }
    if ($Code -eq 1) { return [pscustomobject]@{ state = "failed"; reason = ("Windows would not make the other window the owner of ours (error " + $ErrorCode + "), so it is not followed") } }
    if ($Code -eq 2) { return [pscustomobject]@{ state = "failed"; reason = "Windows would not report the other window's moves, so it cannot be followed" } }
    return [pscustomobject]@{ state = "failed"; reason = ("the native half answered " + $Code + ", which is not an answer it has") }
}

function Get-HordeWindowsFollowRecord {
    # The follow as the port's record: what is in $script:HordeWindowsFollow, or "none".
    $s = $script:HordeWindowsFollow
    if ($null -eq $s) { return (New-HordeWindowFollowRecord -State "none") }
    return (New-HordeWindowFollowRecord -State $s.state -Reason $s.reason -Target $s.target -Companion $s.companion -Mode $s.mode -Placed $s.placed -Placements $s.placements -Events ([HordeWindowsFollowV1]::Events))
}

function Get-HordeWindowsFollowRectangle {
    # The port's Rectangle: known { left; top; right; bottom; scale }, or absent when Windows has no
    # such window.
    param([Parameter(Mandatory = $true)][long]$Handle)
    Initialize-HordeWindowsFollowType
    $r = [HordeWindowsFollowV1]::Rect($Handle)
    if ($null -eq $r) { return (New-HordeAbsent -Note "there is no such window") }
    return (New-HordeKnown -Value ([pscustomobject]@{ left = $r[0]; top = $r[1]; right = $r[2]; bottom = $r[3]; scale = ([HordeWindowsFollowV1]::Dpi($Handle) / 96.0) }))
}

function Set-HordeWindowsFollowFree {
    # The companion stands free: Windows is told to stop reporting, and ours is no longer owned.
    param([Parameter(Mandatory = $true)][string]$State, [Parameter(Mandatory = $true)][string]$Reason)
    $s = $script:HordeWindowsFollow
    [HordeWindowsFollowV1]::Unhook()
    [HordeWindowsFollowV1]::Disown($s.companion)
    $s.state = $State; $s.reason = $Reason
}

function Update-HordeWindowsFollow {
    # The port's Update: look whether the other window still exists and, when -Place, place the
    # companion again from where it is now. While the other window is minimised nothing is placed:
    # Windows has hidden ours, and a minimised window's rectangle is not a place.
    param([bool]$Place = $true)
    $s = $script:HordeWindowsFollow
    if ($null -eq $s -or $s.state -cne "following") { return (Get-HordeWindowsFollowRecord) }
    if (-not [HordeWindowsFollowV1]::Exists($s.target)) {
        Set-HordeWindowsFollowFree -State "lost" -Reason "the window it stood beside no longer exists"
        return (Get-HordeWindowsFollowRecord)
    }
    if ($Place -and -not [HordeWindowsFollowV1]::Minimised($s.target)) {
        $beside = Get-HordeWindowsFollowRectangle -Handle $s.target
        if ($beside.state -ceq "known") {
            $at = Get-HordeWindowFollowPlacement -Target $beside.value -Scale $beside.value.scale -Mode $s.mode -Settings $s.settings
            if ($at.state -ceq "known") {
                [void][HordeWindowsFollowV1]::Place($s.companion, $at.value.left, $at.value.top, $at.value.width, $at.value.height)
                $s.placed = $at.value
                $s.placements = [int]$s.placements + 1
            }
        }
    }
    return (Get-HordeWindowsFollowRecord)
}

function Start-HordeWindowsFollow {
    # The port's Start. The port has already refused a mode that is not built, a handle that is not
    # above zero and a window beside itself.
    param([Parameter(Mandatory = $true)][long]$Target, [Parameter(Mandatory = $true)][long]$Companion, [Parameter(Mandatory = $true)][string]$Mode, [Parameter(Mandatory = $true)]$Settings)
    Initialize-HordeWindowsFollowType
    if ($null -ne $script:HordeWindowsFollow) { [void](Stop-HordeWindowsFollow) }
    if (-not [HordeWindowsFollowV1]::Exists($Target)) { return (New-HordeWindowFollowRecord -State "failed" -Reason "the window to stand beside does not exist") }
    if (-not [HordeWindowsFollowV1]::Exists($Companion)) { return (New-HordeWindowFollowRecord -State "failed" -Reason "the window to place does not exist") }
    if ([HordeWindowsFollowV1]::ProcessOf($Companion) -ne [uint32]$PID) { return (New-HordeWindowFollowRecord -State "failed" -Reason "the window to place is not this process's own, and only its own window is ever moved") }
    # One line, calling a named function that reads the state below: a script block given to .NET does
    # not keep the variables of the function that wrote it.
    $attached = [HordeWindowsFollowV1]::Attach($Target, $Companion, [Action]{ [void](Update-HordeWindowsFollow) })
    $started = ConvertTo-HordeWindowsFollowStart -Code $attached[0] -ErrorCode $attached[1]
    if ($started.state -cne "following") { return (New-HordeWindowFollowRecord -State "failed" -Reason $started.reason) }
    $script:HordeWindowsFollow = [pscustomobject]@{ target = $Target; companion = $Companion; mode = $Mode; settings = $Settings; state = "following"; reason = ""; placed = $null; placements = 0 }
    return (Update-HordeWindowsFollow -Place $true)
}

function Disconnect-HordeWindowsFollow {
    # The port's Release: a companion that is followed stands free; one that is lost already does.
    $s = $script:HordeWindowsFollow
    if ($null -ne $s -and $s.state -ceq "following") { Set-HordeWindowsFollowFree -State "free" -Reason "it was let go, and stands free" }
    return (Get-HordeWindowsFollowRecord)
}

function Stop-HordeWindowsFollow {
    # The port's Stop: Windows is told to stop reporting, and ours is no longer owned by the other
    # window if it still was.
    $s = $script:HordeWindowsFollow
    if ($null -ne $s) {
        if ($s.state -ceq "following") { [HordeWindowsFollowV1]::Unhook(); [HordeWindowsFollowV1]::Disown($s.companion) }
        $script:HordeWindowsFollow = $null
    }
    return (Get-HordeWindowsFollowRecord)
}

function Register-HordeWindowsFollower {
    # This file's one line at the port: its name, and the seven blocks the port's header lists.
    $blocks = @{
        Name      = "windows"
        Applies   = { Test-HordeIsWindows }
        RealScale = { Enable-HordeWindowsRealScale }
        Rectangle = { param($Handle) Get-HordeWindowsFollowRectangle -Handle $Handle }
        Start     = { param($Target, $Companion, $Mode, $Settings) Start-HordeWindowsFollow -Target $Target -Companion $Companion -Mode $Mode -Settings $Settings }
        Update    = { param($Place) Update-HordeWindowsFollow -Place $Place }
        Release   = { Disconnect-HordeWindowsFollow }
        Stop      = { Stop-HordeWindowsFollow }
    }
    Register-HordeWindowFollower @blocks
}
Register-HordeWindowsFollower