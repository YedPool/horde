# platform/windows/Scale.ps1 - tell Windows that this process draws at each screen's real scale, and
# say what the process is.
#
# WHAT IT OWNS, and nothing else: the one call that makes a process per-monitor DPI aware, and the one
# read of what awareness a process has. Anything that makes a window, or reads another window's
# rectangle, needs the process to see real pixels; each used to ask Windows itself, in its own words.
# They ask here instead. This file makes no window, knows no window, and keeps no state.
#
# WHY IT MATTERS. Until a process says otherwise Windows treats it as unaware: it is told every screen
# is at the ordinary scale of 96 dots per inch, its windows are drawn small and stretched (soft text),
# and every rectangle it reads is a scaled one, so a place worked out from it is wrong by the screen's
# scale. Measured 2026-10-06 by the window follower, with the process made aware first, on a screen at
# one and a half times the ordinary scale: a window at 60,60 of 1100 by 640 real pixels, and its
# companion standing at 644,132, 480 by 532 - exactly the place worked out for it.
#
# HOW TO CALL IT.
#
#   . (Join-Path <repository> "platform\windows\Scale.ps1")
#   $scale = Enable-HordeWindowsRealScale
#
# WHEN: once, BEFORE THE PROCESS MAKES ITS FIRST WINDOW, which is what Windows documents for this
# call. (Measured 2026-10-07 on Windows 10.0.26200: a call made while a never-shown window already
# existed was still taken, and that window then read per-monitor-v2 at 144 dots per inch. What a
# window already shown and drawn does was NOT measured, so the rule is the documented one.) A caller
# that only reads other programs' windows calls it before its first read.
#
# IT NEVER THROWS AND IT IS SAFE TO CALL AGAIN. The answer is plain data:
#
#   state      "applied"      Windows took it, now.
#              "already"      the process already had an awareness - an earlier call, here or in a
#                             library, or the program's manifest. Windows sets it once per process.
#              "unavailable"  it could not be asked for: a Windows older than 10 version 1703, which
#                             has no such call, or a refusal Windows gave no better name to.
#   awareness  what the process IS after the call, read back: "unaware", "system", "per-monitor",
#              "per-monitor-v2", "unaware-gdi-scaled" or "unknown".
#   realScale  "yes" for per-monitor and per-monitor-v2, "no" for the others, "unknown" when it could
#              not be read. Never a true or false: unknown is not no.
#   reason     a sentence, for a person or a log.
#
# NONE OF THE THREE STATES IS AN ERROR: the window still works, drawn by Windows at the wrong scale.
# DECIDE ON realScale, NOT ON state. "already" does not mean aware: measured 2026-10-07, a process set
# to system awareness first answers "already" and stays system, real scale "no". And "applied" with
# real scale "unknown" is a Windows between versions 1703 and 1803, which takes the call and cannot
# be asked what it is.
#
# Get-HordeWindowsScaleAwareness is the read alone - { awareness; realScale; reason } - and changes
# nothing; a test or a caller uses it to see what the process is.
#
# WHAT WAS MEASURED, 2026-10-07, Windows 10.0.26200, each in a fresh Windows PowerShell 5.1 process:
#   - a fresh process reads unaware;
#   - the call is taken, and the process then reads per-monitor-v2;
#   - a second call is refused with error 5 (access denied), the process unchanged;
#   - a value Windows does not know is refused with error 87 (invalid parameter);
#   - after a call that was taken, the last error still held an earlier call's number (203), so the
#     error is read only when the call was refused.
# NOT MEASURED: a Windows without the call (the catch below is written from the documentation), a
# second monitor or a second scale, and a system that is not Windows, where loading user32 fails and
# the answer is "unavailable" by the same catch.
#
# THE TYPE IS COMPILED ON FIRST USE, not when this file is loaded, so loading costs nothing and does
# nothing. Its name carries a version, so a later change is a new type and never a clash with one
# already loaded in the session (core/Platform.ps1 measured and chose the same).
#
# FUNCTIONS, NOT $script: VARIABLES: a command's run block calls these from the runner's script scope,
# where a $script: variable of this file reads as nothing (cli/Commands.ps1 measured it).
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

function Get-HordeWindowsScaleSource { return @"
using System;
using System.Runtime.InteropServices;
public static class HordeWindowsScaleV1 {
    [DllImport("user32.dll", SetLastError = true)] static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] static extern IntPtr GetDpiAwarenessContextForProcess(IntPtr process);
    [DllImport("user32.dll")] static extern bool AreDpiAwarenessContextsEqual(IntPtr a, IntPtr b);
    // { taken, error }: taken is 1 when Windows took it, 0 when it refused, -1 when there is no such
    // call. DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 is -4. The error is read only after a refusal.
    public static int[] Apply() {
        try {
            if (SetProcessDpiAwarenessContext(new IntPtr(-4))) { return new int[] { 1, 0 }; }
            return new int[] { 0, Marshal.GetLastWin32Error() };
        }
        catch (EntryPointNotFoundException) { return new int[] { -1, 0 }; }
        catch (DllNotFoundException) { return new int[] { -1, 0 }; }
    }
    // Which of Windows' named contexts this process has, as its number without the sign: 1 unaware,
    // 2 system, 3 per-monitor, 4 per-monitor-v2, 5 unaware-gdi-scaled. 0 when it is none of them, -1
    // when this Windows cannot be asked. A null process handle is this process.
    public static int Read() {
        try {
            IntPtr context = GetDpiAwarenessContextForProcess(IntPtr.Zero);
            for (int i = 1; i <= 5; i++) { if (AreDpiAwarenessContextsEqual(context, new IntPtr(-i))) { return i; } }
            return 0;
        }
        catch (EntryPointNotFoundException) { return -1; }
        catch (DllNotFoundException) { return -1; }
    }
}
"@ }

function Get-HordeWindowsScaleStates {
    # Every state Enable-HordeWindowsRealScale can answer, for a caller or a schema that lists them.
    return @("applied", "already", "unavailable")
}

function ConvertTo-HordeWindowsScaleState {
    # PURE. What Windows answered the call, as { state; reason }. -Taken is 1, 0 or -1 as the native
    # half gives it; -ErrorCode is Windows' last error and counts only after a refusal.
    param([Parameter(Mandatory = $true)][int]$Taken, [int]$ErrorCode = 0)
    if ($Taken -eq 1) { return [pscustomobject]@{ state = "applied"; reason = "Windows took it: this process draws at each screen's real scale" } }
    if ($Taken -eq -1) { return [pscustomobject]@{ state = "unavailable"; reason = "this system has no call to set it (Windows 10 version 1703 is the first that has)" } }
    # ERROR_ACCESS_DENIED: Windows' documented answer when the awareness was set before.
    if ($ErrorCode -eq 5) { return [pscustomobject]@{ state = "already"; reason = "this process already had its awareness set, by an earlier call or by its manifest; Windows sets it once" } }
    return [pscustomobject]@{ state = "unavailable"; reason = ("Windows refused it, error " + $ErrorCode) }
}

function ConvertTo-HordeWindowsScaleAwareness {
    # PURE. The native half's number, as { awareness; realScale; reason }. Per-monitor and its second
    # version both hand the process real pixels on every screen; the others do not. A number outside
    # the list is unknown, never "no": a later Windows may name a sixth.
    param([Parameter(Mandatory = $true)][int]$Code)
    $names = @{ 1 = "unaware"; 2 = "system"; 3 = "per-monitor"; 4 = "per-monitor-v2"; 5 = "unaware-gdi-scaled" }
    if ($Code -eq -1) { return [pscustomobject]@{ awareness = "unknown"; realScale = "unknown"; reason = "this system cannot be asked what the process is (Windows 10 version 1803 is the first that can)" } }
    if (-not $names.ContainsKey($Code)) { return [pscustomobject]@{ awareness = "unknown"; realScale = "unknown"; reason = "Windows named an awareness this file does not know" } }
    $real = "no"
    if ($Code -eq 3 -or $Code -eq 4) { $real = "yes" }
    return [pscustomobject]@{ awareness = $names[$Code]; realScale = $real; reason = "" }
}

function Initialize-HordeWindowsScaleType {
    if (-not ("HordeWindowsScaleV1" -as [type])) { Add-Type -TypeDefinition (Get-HordeWindowsScaleSource) -ErrorAction Stop }
}

function Get-HordeWindowsScaleAwareness {
    # What this process is, as { awareness; realScale; reason }. Reads only; never throws.
    try {
        Initialize-HordeWindowsScaleType
        return (ConvertTo-HordeWindowsScaleAwareness -Code ([HordeWindowsScaleV1]::Read()))
    } catch { return [pscustomobject]@{ awareness = "unknown"; realScale = "unknown"; reason = ("the awareness could not be read: " + $_.Exception.Message) } }
}

function Enable-HordeWindowsRealScale {
    # Ask Windows, once, to let this process draw at each screen's real scale. Answers
    # { state; awareness; realScale; reason } and never throws; see the header for when to call it and
    # how to read the answer.
    try {
        Initialize-HordeWindowsScaleType
        $asked = [HordeWindowsScaleV1]::Apply()
        $did = ConvertTo-HordeWindowsScaleState -Taken $asked[0] -ErrorCode $asked[1]
    } catch { $did = [pscustomobject]@{ state = "unavailable"; reason = ("the call could not be made: " + $_.Exception.Message) } }
    $now = Get-HordeWindowsScaleAwareness
    return [pscustomobject]@{ state = $did.state; awareness = $now.awareness; realScale = $now.realScale; reason = $did.reason }
}
