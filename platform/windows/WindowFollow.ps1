# platform/windows/WindowFollow.ps1 - keep one window beside another window this process does not own.
#
# WHAT IT DOES, and nothing else (decisions window attach design, 2026-10-06): given the native handle
# of a window - any window, of any program - and the handle of a window of this process, it makes the
# second a companion of the first: placed relative to it, re-placed when it moves or is resized, above
# it, hidden while it is minimised and back when it is restored, and never given the keyboard by any
# of that. It does not know what either window shows, how the first one was found, or what a terminal
# is. The same part can later put any Horde window beside any session's window.
#
# HOW, as the proof of 2026-10-06 measured it against a terminal window started for the purpose:
#   - THE OTHER WINDOW IS MADE THE OWNER of ours (GWLP_HWNDPARENT), which Windows allows across
#     programs. An owned window always stands above its owner, is hidden when the owner is minimised
#     and returns when it is restored; Windows does all three, and nothing here polls for them.
#   - WINDOWS REPORTS EVERY MOVE AND RESIZE of the other window's process (SetWinEventHook,
#     EVENT_OBJECT_LOCATIONCHANGE, out of context), and ours is placed again each time. The proof
#     passed all eight of its checks: placed on attach, above, after a move, a resize, a minimise, a
#     restore and a maximise, above again, with the foreground window the same throughout.
#   - EVERY PLACEMENT IS SWP_NOACTIVATE, so placing never takes the keyboard.
#
# WHERE IT IS PLACED IS A PURE FUNCTION, Get-HordeWindowFollowPlacement: the other window's rectangle
# and the screen's scale in, a rectangle out. It is tested with no window (test/test-window-follow.ps1),
# and the native half only carries its answer to Windows.
#
# ONE MODE IS BUILT: floating, at the top right of the other window, about a third of its width and
# most of its height. THE SEAMS LEFT FOR LATER, and not built: a mode is a name handed to the pure
# function, which refuses any it does not know, so side-by-side is a second branch there and a call
# that sizes the other window here; a place the person dragged it to is an offset handed to the same
# function; the small tab is a size. None of the three exists yet.
#
# PIXELS ARE REAL PIXELS when the process is per-monitor DPI aware, which is the window's maker's to
# arrange before it makes its first window. This file only reads the other window's scale
# (GetDpiForWindow) so that margins and smallest sizes are the same physical size on every screen.
# NOT MEASURED: a second monitor or a second scale - the measuring machine has one screen.
#
# WHAT WINDOWS DOES THAT A CALLER MUST KNOW: when the owner window is destroyed, Windows destroys the
# windows it owns. So when the other window closes, ours closes with it. Following a session into a
# new window, and standing free when there is none, are a later slice's.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

$script:HordeWindowFollowModes = @("floating")
# The floating mode's numbers, in pixels at the ordinary scale of 96 dots per inch; each is multiplied
# by the other window's scale. The margins are the proof's: 24 from the right edge, and 48 from the top
# so that the other window's title and tab bar stay visible above ours.
$script:HordeWindowFollowFloating = @{ marginTop = 48; marginRight = 24; marginBottom = 24; widthShare = 3; minWidth = 320; minHeight = 200 }
$script:HordeWindowFollow = $null

$script:HordeWindowFollowSource = @'
using System;
using System.Runtime.InteropServices;
public static class HordeWindowFollowNative {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    public delegate void WinEventDelegate(IntPtr hook, uint evt, IntPtr hwnd, int idObject, int idChild, uint thread, uint time);
    [DllImport("user32.dll")] static extern IntPtr SetWinEventHook(uint min, uint max, IntPtr mod, WinEventDelegate cb, uint pid, uint tid, uint flags);
    [DllImport("user32.dll")] static extern bool UnhookWinEvent(IntPtr hook);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)] static extern IntPtr SetWindowLongPtr(IntPtr h, int index, IntPtr value);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr(IntPtr h, int index);
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
    public static bool Visible(long h) { return IsWindowVisible(new IntPtr(h)); }
    public static long Foreground() { return GetForegroundWindow().ToInt64(); }
    public static long Owner(long h) { return GetWindowLongPtr(new IntPtr(h), -8).ToInt64(); }
    public static uint ProcessOf(long h) { uint pid; GetWindowThreadProcessId(new IntPtr(h), out pid); return pid; }
    public static int Dpi(long h) { try { uint d = GetDpiForWindow(new IntPtr(h)); return d == 0 ? 96 : (int)d; } catch (EntryPointNotFoundException) { return 96; } }
    public static int[] Rect(long h) { RECT r; if (!GetWindowRect(new IntPtr(h), out r)) return null; return new int[] { r.Left, r.Top, r.Right, r.Bottom }; }
    // SWP_NOZORDER (4) | SWP_NOACTIVATE (0x10): the size and the place, never the order, never the keyboard.
    public static bool Place(long h, int x, int y, int cx, int cy) { return SetWindowPos(new IntPtr(h), IntPtr.Zero, x, y, cx, cy, 0x0004 | 0x0010); }
    public static bool IsAbove(long top, long below) {
        IntPtr h = new IntPtr(below); int guard = 0;
        while (h != IntPtr.Zero && guard++ < 4000) { h = GetWindow(h, 3); if (h.ToInt64() == top) return true; }   // GW_HWNDPREV
        return false;
    }
    public static bool Attach(long targetWindow, long follower, Action onMoved) {
        Detach(0);
        target = new IntPtr(targetWindow);
        moved = onMoved;
        SetWindowLongPtr(new IntPtr(follower), -8, target);     // GWLP_HWNDPARENT: the other window owns ours
        keep = new WinEventDelegate(OnEvent);
        // EVENT_OBJECT_LOCATIONCHANGE of the other window's process, delivered to this thread's message loop.
        hook = SetWinEventHook(0x800B, 0x800B, IntPtr.Zero, keep, ProcessOf(targetWindow), 0, 0);
        return hook != IntPtr.Zero;
    }
    public static void Detach(long follower) {
        if (hook != IntPtr.Zero) { UnhookWinEvent(hook); hook = IntPtr.Zero; }
        if (follower != 0 && IsWindow(new IntPtr(follower))) { SetWindowLongPtr(new IntPtr(follower), -8, IntPtr.Zero); }
        target = IntPtr.Zero; moved = null; keep = null;
    }
}
'@

function Get-HordeWindowFollowModes { return @($script:HordeWindowFollowModes) }

function Get-HordeWindowFollowPlacement {
    # Where the companion stands, as { left; top; width; height } in pixels. -Target is the other
    # window's rectangle { left; top; right; bottom }; -Dpi its screen's dots per inch (96 is the
    # ordinary scale). A PURE FUNCTION: no window is read or moved here.
    #
    # FLOATING: the right edge 24 in from the other window's, the top 48 down from its top, a third of
    # its width and all of its height but the margins - and never smaller than a list can be read in,
    # nor wider than the other window allows.
    param([Parameter(Mandatory = $true)]$Target, [string]$Mode = "floating", [int]$Dpi = 96)
    if ($script:HordeWindowFollowModes -cnotcontains $Mode) { throw ("'" + $Mode + "' is not a way a window is followed; the ways built are: " + ($script:HordeWindowFollowModes -join ", ")) }
    if ($Dpi -lt 48 -or $Dpi -gt 960) { throw ("" + $Dpi + " dots per inch is not a screen's scale") }
    $left = [int]$Target.left; $top = [int]$Target.top; $right = [int]$Target.right; $bottom = [int]$Target.bottom
    if ($right -le $left -or $bottom -le $top) { throw "the other window's rectangle is empty, so there is nowhere beside it" }
    $f = $script:HordeWindowFollowFloating
    # Whole pixels, rounded once per number, so that two placements from one rectangle are the same.
    $scale = { param([int]$n) return [int][Math]::Round($n * $Dpi / 96.0) }
    $marginTop = & $scale $f.marginTop; $marginRight = & $scale $f.marginRight; $marginBottom = & $scale $f.marginBottom
    $targetWidth = $right - $left; $targetHeight = $bottom - $top
    $width = [Math]::Max([int][Math]::Round($targetWidth / [double]$f.widthShare), (& $scale $f.minWidth))
    # Never wider than the other window less a margin each side: on a narrow window it shrinks with it.
    $width = [Math]::Min($width, [Math]::Max($targetWidth - 2 * $marginRight, 1))
    $height = [Math]::Max($targetHeight - $marginTop - $marginBottom, [Math]::Min((& $scale $f.minHeight), [Math]::Max($targetHeight - $marginTop, 1)))
    return [pscustomobject]@{ left = ($right - $marginRight - $width); top = ($top + $marginTop); width = $width; height = $height }
}

function Initialize-HordeWindowFollow {
    if ($null -eq ("HordeWindowFollowNative" -as [type])) { Add-Type -TypeDefinition $script:HordeWindowFollowSource }
}

function Get-HordeWindowRectangle {
    # A window's rectangle { left; top; right; bottom } and its screen's scale, or $null when Windows
    # will not give one (the window is gone).
    param([Parameter(Mandatory = $true)][long]$Handle)
    Initialize-HordeWindowFollow
    $r = [HordeWindowFollowNative]::Rect($Handle)
    if ($null -eq $r) { return $null }
    return [pscustomobject]@{ left = $r[0]; top = $r[1]; right = $r[2]; bottom = $r[3]; dpi = [HordeWindowFollowNative]::Dpi($Handle) }
}

function Update-HordeWindowFollow {
    # Place the companion again from where the other window is now. Returns the follow's state:
    # following, or lost when the other window no longer exists. While the other window is minimised
    # nothing is placed: Windows has hidden ours, and a minimised window's rectangle is not a place.
    $s = $script:HordeWindowFollow
    if ($null -eq $s) { return "none" }
    if (-not [HordeWindowFollowNative]::Exists($s.target)) { $s.state = "lost"; return "lost" }
    if ([HordeWindowFollowNative]::Minimised($s.target)) { return $s.state }
    $rect = Get-HordeWindowRectangle -Handle $s.target
    if ($null -eq $rect) { $s.state = "lost"; return "lost" }
    $at = Get-HordeWindowFollowPlacement -Target $rect -Mode $s.mode -Dpi $rect.dpi
    [void][HordeWindowFollowNative]::Place($s.follower, $at.left, $at.top, $at.width, $at.height)
    $s.placed = $at
    $s.placements = [int]$s.placements + 1
    return $s.state
}

function Start-HordeWindowFollow {
    # Make the window -Follower (of this process) a companion of the window -Target (anyone's), and
    # place it. Returns { state; reason }: following, or failed with why. Call it on the thread that
    # runs the follower's message loop: that is where Windows delivers the other window's moves.
    param([Parameter(Mandatory = $true)][long]$Target, [Parameter(Mandatory = $true)][long]$Follower, [string]$Mode = "floating")
    if ($script:HordeWindowFollowModes -cnotcontains $Mode) { return [pscustomobject]@{ state = "failed"; reason = ("'" + $Mode + "' is not a way a window is followed") } }
    Initialize-HordeWindowFollow
    if ($Target -eq 0 -or -not [HordeWindowFollowNative]::Exists($Target)) { return [pscustomobject]@{ state = "failed"; reason = "the window to stand beside does not exist" } }
    if ($Follower -eq 0 -or -not [HordeWindowFollowNative]::Exists($Follower)) { return [pscustomobject]@{ state = "failed"; reason = "the window to place does not exist" } }
    if ($Target -eq $Follower) { return [pscustomobject]@{ state = "failed"; reason = "a window cannot stand beside itself" } }
    if ([HordeWindowFollowNative]::ProcessOf($Follower) -ne [uint32]$PID) { return [pscustomobject]@{ state = "failed"; reason = "the window to place is not this process's own, and only its own window is ever moved" } }
    $script:HordeWindowFollow = [pscustomobject]@{ target = $Target; follower = $Follower; mode = $Mode; state = "following"; placed = $null; placements = 0 }
    # One line, calling a named function that reads the state above: a script block given to .NET does
    # not keep the variables of the function that wrote it (the first surface's suite measures this).
    $hooked = [HordeWindowFollowNative]::Attach($Target, $Follower, [Action]{ [void](Update-HordeWindowFollow) })
    if (-not $hooked) {
        [HordeWindowFollowNative]::Detach($Follower)
        $script:HordeWindowFollow = $null
        return [pscustomobject]@{ state = "failed"; reason = "Windows would not report the other window's moves, so it cannot be followed" }
    }
    [void](Update-HordeWindowFollow)
    return [pscustomobject]@{ state = "following"; reason = "" }
}

function Get-HordeWindowFollow {
    # What is being followed, for a caller that reports it: { target; follower; mode; state; placed;
    # placements; events }, or $null when nothing is.
    $s = $script:HordeWindowFollow
    if ($null -eq $s) { return $null }
    return [pscustomobject]@{ target = $s.target; follower = $s.follower; mode = $s.mode; state = $s.state; placed = $s.placed; placements = $s.placements; events = [HordeWindowFollowNative]::Events }
}

function Stop-HordeWindowFollow {
    # Stop following: Windows is told to stop reporting, and ours is no longer owned by the other window
    # if it still exists.
    $s = $script:HordeWindowFollow
    if ($null -eq $s) { return }
    [HordeWindowFollowNative]::Detach($s.follower)
    $script:HordeWindowFollow = $null
}
