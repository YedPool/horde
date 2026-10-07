# DOES THE WINDOWS FOLLOWER KEEP A REAL WINDOW BESIDE ANOTHER PROGRAM'S REAL WINDOW, AND LET IT GO
# RIGHT WHEN THAT WINDOW IS GONE?
#
# platform/windows/WindowFollow.ps1, asked only through core/WindowFollowPort.ps1, as a caller asks.
# Where a companion stands is the port's pure function and is test/test-window-follow-port.ps1's. This
# suite holds what is the Windows follower's own, and it is this unit's OWN scenario: two plain windows,
# no web page and no terminal.
#
# THE TWO WINDOWS. The companion is a plain form of this process. The OTHER window belongs to ANOTHER
# PROCESS this suite starts for the purpose - a few lines of Windows PowerShell showing one plain form -
# because owning a window across programs is the thing to prove. It is moved, resized, minimised,
# restored and closed from here, by its handle, after checking that the handle is that process's.
# The suite stops only the processes it started, by the handles it holds.
#
# WHAT A PERSON AT THE MACHINE MAY SEE. Every window stands near -32000,-32000, far off every screen,
# and none is ever activated: nothing here asks for the keyboard, and the suite fails if any of its
# windows is the foreground window or its thread's active window at any look. The other program's
# window is an ordinary one, so it has a TASKBAR BUTTON for as long as it lives (a few seconds, three
# times), and the companion has one for the moments it stands free: that button is what is being
# proved. Nothing else is on screen.
#
# HOW "IN THE TASKBAR" IS READ. Windows tells every shell-hook window when a window becomes a taskbar
# window (HSHELL_WINDOWCREATED) and when it stops being one (HSHELL_WINDOWDESTROYED); the taskbar
# itself is such a listener. This suite registers one of its own and reads what Windows said. Its
# control is the other program's window, which must be announced when it appears.
#
# IT NEEDS AN INTERACTIVE LOGON: a desktop to make windows on and a shell to announce them to. Where
# there is none it says so and exits 3, and test/lib/SuiteFiles.ps1 lists it as bound to such a machine.
# It was written and run on Windows 10.0.26200, one screen at one and a half times the ordinary scale.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\WindowFollowPort.ps1")
# A home of this run's own, which is never made: a follow started with no settings handed in reads the
# person's file, and the person's real one is not this suite's to read.
$env:HORDE_HOME = Join-Path $env:TEMP ("horde-follow-home-" + [guid]::NewGuid().ToString("N"))

function Field {
    # A field of an object, or the text "<none>" when it is not there - so that a missing field fails a
    # check instead of raising under strict mode.
    param($From, [string]$Name)
    if ($null -eq $From -or $null -eq $From.PSObject.Properties[$Name]) { return "<none>" }
    return $From.PSObject.Properties[$Name].Value
}

Write-Host ""
Write-Host "--- found by folder, and registered by being loaded ---" -ForegroundColor Cyan
$before = Get-HordeWindowFollower
Check ($before.state -ceq "unknown") "CONTROL: before any follower's file is loaded the port has none"
$files = @(Get-HordeWindowFollowerFiles -Root $root)
Check ($files.Count -eq 1 -and $files[0] -like "*\platform\windows\WindowFollow.ps1") ("the port finds this follower's file by folder, and no other (" + $files.Count + ")")
Check ($null -eq ("HordeWindowsFollowV1" -as [type])) "CONTROL: nothing native is loaded yet"
foreach ($file in $files) { . $file }
Check ($null -eq ("HordeWindowsFollowV1" -as [type])) "loading the file compiles nothing and asks Windows nothing"
$loaded = Get-HordeWindowFollower
Check ($loaded.state -ceq "known" -and (Field $loaded.value "name") -ceq "windows") "loaded, it is the follower the port asks on this system"

Write-Host ""
Write-Host "--- real scale has one owner, and it is not this file ---" -ForegroundColor Cyan
$followText = [System.IO.File]::ReadAllText((Join-Path $root "platform\windows\WindowFollow.ps1"))
$scaleText = [System.IO.File]::ReadAllText((Join-Path $root "platform\windows\Scale.ps1"))
Check ($scaleText.Contains("SetProcessDpiAwarenessContext") -and $followText.Contains("SetWindowPos")) "CONTROL: the search sees the awareness call in its owner's file, and a call this file does make"
Check (-not $followText.Contains("SetProcessDpiAwarenessContext")) "the follower does not ask Windows for the awareness in words of its own"
Check ($null -eq (Get-Command -Name "Enable-HordeWindowRealPixels" -ErrorAction SilentlyContinue) -and $null -ne (Get-Command -Name "Enable-HordeWindowsRealScale" -ErrorAction SilentlyContinue)) "and loading it brings the one owner's function, not a second one"

Write-Host ""
Write-Host "--- what Windows answered a start, turned into what the caller is told ---" -ForegroundColor Cyan
$s = ConvertTo-HordeWindowsFollowStart -Code 0 -ErrorCode 0
Check ((Field $s "state") -ceq "following" -and (Field $s "reason") -ceq "") "owned and reported: following, with nothing to say"
$s = ConvertTo-HordeWindowsFollowStart -Code 0 -ErrorCode 87
Check ((Field $s "state") -ceq "following") "following whatever error number an earlier call left behind"
$s = ConvertTo-HordeWindowsFollowStart -Code 1 -ErrorCode 87
Check ((Field $s "state") -ceq "failed" -and (Field $s "reason") -ceq "Windows would not make the other window the owner of ours (error 87), so it is not followed") "the owner was not set: failed, with Windows' error number"
$s = ConvertTo-HordeWindowsFollowStart -Code 2 -ErrorCode 0
Check ((Field $s "state") -ceq "failed" -and (Field $s "reason") -ceq "Windows would not report the other window's moves, so it cannot be followed") "no reports of its moves: failed, in words"
$s = ConvertTo-HordeWindowsFollowStart -Code 9 -ErrorCode 0
Check ((Field $s "state") -ceq "failed" -and "$(Field $s 'reason')" -like "*9*") "an answer this file does not know is failed, never following"

if (-not (Test-HordeIsWindows)) {
    Write-Host "  [SKIP] everything that asks Windows: this is not Windows" -ForegroundColor Yellow
    Complete-HordeSuite -Success "OFF WINDOWS - ONLY THE LOADING WAS CHECKED, EXIT 3" -PassCode 3
}

Write-Host ""
Write-Host "--- the follower refuses without touching any window ---" -ForegroundColor Cyan
$r = Get-HordeWindowFollow
Check ((Field $r "state") -ceq "none" -and (Field $r "target") -eq 0 -and $null -eq (Field $r "placed")) "CONTROL: nothing is followed until something is started"
Check ((Field (Update-HordeWindowFollow) "state") -ceq "none") "placing again when nothing is followed places nothing"
# 2147480001 and 2147480003: no window has such a handle (the first check proves it of the first).
$gone = Get-HordeWindowFollowRectangle -Handle 2147480001
Check ((Test-HordeAnswer $gone) -and $gone.state -ceq "absent") "a handle that is no window has no rectangle: absent, which is not unknown"
$r = Start-HordeWindowFollow -Target 2147480001 -Companion 2147480003
Check ((Field $r "state") -ceq "failed" -and (Field $r "reason") -ceq "the window to stand beside does not exist") "a handle that is no window cannot be stood beside: failed, in words"
Check ((Field (Get-HordeWindowFollow) "state") -ceq "none") "and after that refusal nothing is being followed"
Check ((Field (Disconnect-HordeWindowFollow) "state") -ceq "none") "letting go when nothing is followed does nothing"
Check ((Field (Stop-HordeWindowFollow) "state") -ceq "none") "and so does stopping"

if (-not [System.Environment]::UserInteractive) {
    Write-Host "  [SKIP] the two real windows: this process has no interactive desktop" -ForegroundColor Yellow
    Complete-HordeSuite -Success "NO INTERACTIVE DESKTOP - NO WINDOW WAS FOLLOWED, EXIT 3" -PassCode 3
}

# ---------------------------------------------------------------------------------------------------
# THE TWO REAL WINDOWS.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Windows.Forms;
// A form that is shown without being activated: a test window never asks for the keyboard.
public class FollowTestForm : Form { protected override bool ShowWithoutActivation { get { return true; } } }
// What Windows tells the shell about taskbar windows, as "code:handle" (1 created, 2 destroyed).
public class FollowTestShellWatch : NativeWindow {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern uint RegisterWindowMessage(string s);
    [DllImport("user32.dll")] static extern bool RegisterShellHookWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool DeregisterShellHookWindow(IntPtr h);
    uint message; public List<string> Seen = new List<string>(); public bool Registered;
    public FollowTestShellWatch() { CreateHandle(new CreateParams()); message = RegisterWindowMessage("SHELLHOOK"); Registered = RegisterShellHookWindow(Handle); }
    protected override void WndProc(ref Message m) { if ((uint)m.Msg == message) { Seen.Add(m.WParam.ToInt64() + ":" + m.LParam.ToInt64()); } base.WndProc(ref m); }
    public void Done() { DeregisterShellHookWindow(Handle); DestroyHandle(); }
}
// This suite's own eyes and hands, apart from the code under test.
public static class FollowTestProbe {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] struct GUITHREADINFO { public int cbSize; public int flags; public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret; public RECT rcCaret; }
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] static extern IntPtr SetWindowLongPtr(IntPtr h, int index, IntPtr value);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr(IntPtr h, int index);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint message, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint thread, ref GUITHREADINFO info);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr h);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    public static long Owner(long h) { return GetWindow(new IntPtr(h), 4).ToInt64(); }                     // GW_OWNER
    public static long SetOwner(long h, long owner) { return SetWindowLongPtr(new IntPtr(h), -8, new IntPtr(owner)).ToInt64(); }
    public static long ExStyle(long h) { return GetWindowLongPtr(new IntPtr(h), -20).ToInt64(); }
    public static bool Exists(long h) { return IsWindow(new IntPtr(h)); }
    public static bool Visible(long h) { return IsWindowVisible(new IntPtr(h)); }
    public static long Foreground() { return GetForegroundWindow().ToInt64(); }
    public static long ThreadActive() { GUITHREADINFO g = new GUITHREADINFO(); g.cbSize = Marshal.SizeOf(typeof(GUITHREADINFO)); if (!GetGUIThreadInfo(GetCurrentThreadId(), ref g)) return -1; return g.hwndActive.ToInt64(); }
    public static uint ProcessOf(long h) { uint pid; GetWindowThreadProcessId(new IntPtr(h), out pid); return pid; }
    public static int Dpi(long h) { return (int)GetDpiForWindow(new IntPtr(h)); }
    public static string Rect(long h) { RECT r; if (!GetWindowRect(new IntPtr(h), out r)) return "none"; return r.Left + "," + r.Top + " " + (r.Right - r.Left) + "x" + (r.Bottom - r.Top); }
    public static int[] Sides(long h) { RECT r; if (!GetWindowRect(new IntPtr(h), out r)) return null; return new int[] { r.Left, r.Top, r.Right, r.Bottom }; }
    // SWP_NOZORDER | SWP_NOACTIVATE: a test moves a window, and never gives it the keyboard.
    public static bool Move(long h, int x, int y, int cx, int cy) { return SetWindowPos(new IntPtr(h), IntPtr.Zero, x, y, cx, cy, 0x0004 | 0x0010); }
    public static bool Show(long h, int cmd) { return ShowWindow(new IntPtr(h), cmd); }
    public static bool Close(long h) { return PostMessage(new IntPtr(h), 0x0010, IntPtr.Zero, IntPtr.Zero); }   // WM_CLOSE
    // How many windows are walked before the search gives up: far more than a desktop holds, and an
    // end to a walk that Windows could otherwise lead in a circle while windows are being reordered.
    public const int WalkLimit = 100000;
    public static bool IsAbove(long top, long below) {
        IntPtr h = new IntPtr(below);
        for (int walked = 0; h != IntPtr.Zero && walked < WalkLimit; walked++) { h = GetWindow(h, 3); if (h.ToInt64() == top) return true; }   // GW_HWNDPREV
        return false;
    }
}
'@

$script:forms = New-Object System.Collections.ArrayList       # every window of this process the suite makes
$script:ours = New-Object System.Collections.ArrayList        # and the handle of each, which outlives a closed form
$script:others = New-Object System.Collections.ArrayList      # every other process it starts
$script:loud = New-Object System.Collections.ArrayList        # every look at which a test window had the keyboard
$script:looks = 0
$script:watch = $null

function Pump {
    # Let this thread's messages through for a while: Windows' reports of the other window's moves
    # arrive here, as they would in a window's own loop.
    param([int]$Milliseconds = 200)
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    while ($clock.ElapsedMilliseconds -lt $Milliseconds) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 15 }
}
function WaitFor {
    # Pump until the block is true, or the time is up: exactly true or false. The machine this runs on
    # may be slowed on purpose, so the wait is long and a pass is quick.
    param([scriptblock]$Until, [int]$Seconds = 20)
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    while ($clock.Elapsed.TotalSeconds -lt $Seconds) {
        if ([bool](& $Until)) { return $true }
        Pump 60
    }
    return [bool](& $Until)
}
function Look {
    # One look at who has the keyboard: no window of this suite, in this process or another, may be
    # the foreground window, and none of this process's may be its thread's active window.
    param([string]$When)
    $script:looks++
    $front = [FollowTestProbe]::Foreground()
    $active = [FollowTestProbe]::ThreadActive()
    $ours = @($script:ours)
    $theirs = @($script:others | ForEach-Object { $_.handle })
    if (($ours + $theirs) -contains $front) { [void]$script:loud.Add($When + ": the foreground window was a test window (" + $front + ")") }
    if ($ours -contains $active) { [void]$script:loud.Add($When + ": this thread's active window was a test window (" + $active + ")") }
}
function Quiet { return [bool]($script:loud.Count -eq 0) }
function Told {
    # Has Windows told the shell this about that window since the last Forget? 1: it is now a taskbar
    # window. 2: it no longer is.
    param([int]$Code, [long]$Handle)
    return [bool](@($script:watch.Seen) -contains ("" + $Code + ":" + $Handle))
}
function Forget { $script:watch.Seen.Clear() }
function New-TestWindow {
    # A plain window of this process, far off screen, never activated. -Hidden: made and never shown.
    param([string]$Title, [int]$Top = -30000, [switch]$Hidden, [switch]$Tool)
    $form = New-Object FollowTestForm
    $form.Text = $Title; $form.ShowInTaskbar = $false; $form.StartPosition = "Manual"
    if ($Tool) { $form.FormBorderStyle = "SizableToolWindow" }
    $form.Location = New-Object System.Drawing.Point(-32000, $Top); $form.Size = New-Object System.Drawing.Size(240, 160)
    [void]$script:forms.Add($form)
    if (-not $Hidden) { $form.Show() }
    [void]$script:ours.Add($form.Handle.ToInt64())
    Pump 200
    return $form
}
function Start-OtherWindow {
    # Another process showing one plain window: { process; handle }. It ends by itself when this
    # process is gone or after three minutes, whatever happens here.
    param([string]$Title)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $script:otherScript + '" -Parent ' + $PID + ' -Title "' + $Title + '" -Scale "' + (Join-Path $root "platform\windows\Scale.ps1") + '"'
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $env:TEMP
    $process = [System.Diagnostics.Process]::Start($psi)
    $other = [pscustomobject]@{ process = $process; handle = [long]0 }
    [void]$script:others.Add($other)
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    while ($clock.Elapsed.TotalSeconds -lt 60 -and $other.handle -eq 0) {
        $line = $process.StandardOutput.ReadLineAsync()
        while (-not $line.Wait(100)) { Pump 20; if ($clock.Elapsed.TotalSeconds -ge 60) { break } }
        if (-not $line.IsCompleted -or $null -eq $line.Result) { break }
        if ($line.Result -match '\Ahandle=(\d+)\z') { $other.handle = [long]$Matches[1] }
    }
    if ($other.handle -eq 0) { throw "the other process did not show a window within a minute" }
    # Only a window of the process just started is ever moved or closed from here.
    if ([FollowTestProbe]::ProcessOf($other.handle) -ne [uint32]$process.Id) { throw "the handle the other process named is not its own window" }
    return $other
}
function Expected {
    # Where the companion should stand beside the other window, worked out HERE from what this
    # suite's own probe reads and the default numbers - its right edge 24 in, its top 48 down, a third
    # as wide but not under 320, its bottom 24 in but not under 200 high - at the other window's scale.
    # As text, "left,top widthxheight".
    param([long]$Other)
    $sides = [FollowTestProbe]::Sides($Other)
    $scale = [FollowTestProbe]::Dpi($Other) / 96.0
    $width = [Math]::Min([Math]::Max([int][Math]::Round(($sides[2] - $sides[0]) / 3.0), [int][Math]::Round(320 * $scale)), ($sides[2] - $sides[0]) - 2 * [int][Math]::Round(24 * $scale))
    $top = $sides[1] + [int][Math]::Round(48 * $scale)
    $tall = $sides[3] - $sides[1]
    $height = [Math]::Max($tall - [int][Math]::Round(48 * $scale) - [int][Math]::Round(24 * $scale), [Math]::Min([int][Math]::Round(200 * $scale), [Math]::Max($tall - [int][Math]::Round(48 * $scale), 1)))
    return ("" + ($sides[2] - [int][Math]::Round(24 * $scale) - $width) + "," + $top + " " + $width + "x" + $height)
}
function Placed { param($Record) $p = Field $Record "placed"; if ($null -eq $p -or $p -is [string]) { return "none" }; return ("" + $p.left + "," + $p.top + " " + $p.width + "x" + $p.height) }

$script:otherScript = Join-Path $env:TEMP ("horde-follow-other-" + $PID + ".ps1")
[System.IO.File]::WriteAllText($script:otherScript, @'
param([int]$Parent, [string]$Title, [string]$Scale)
# The other program of test/test-window-follow.ps1: one plain window, shown without being activated.
. $Scale
[void](Enable-HordeWindowsRealScale)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition 'public class FollowTestOther : System.Windows.Forms.Form { public int One = 1; protected override bool ShowWithoutActivation { get { return true; } } }'
$form = New-Object FollowTestOther
$form.Text = $Title; $form.StartPosition = "Manual"
$form.Location = New-Object System.Drawing.Point(-32000, -32000); $form.Size = New-Object System.Drawing.Size(600, 400)
$form.Show()
[Console]::Out.WriteLine("handle=" + $form.Handle.ToInt64()); [Console]::Out.Flush()
# It lives on after its window is closed: that is one of the things measured. It ends when the suite
# that started it is gone, or after three minutes.
$clock = [System.Diagnostics.Stopwatch]::StartNew(); $turn = 0
while ($clock.Elapsed.TotalSeconds -lt 180) {
    [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 25
    $turn++
    if ($turn % 40 -eq 0) { try { [void][System.Diagnostics.Process]::GetProcessById($Parent) } catch { break } }
}
'@)

try {
    Write-Host ""
    Write-Host "--- real pixels, and this suite's own eyes ---" -ForegroundColor Cyan
    $scale = Enable-HordeWindowFollowRealScale
    Check ((Field $scale "realScale") -ceq "yes") ("through the port this process is made to see real pixels (" + (Field $scale "state") + ", " + (Field $scale "awareness") + ")")
    $script:watch = New-Object FollowTestShellWatch
    Check ([bool]$script:watch.Registered) "CONTROL: Windows will tell this suite what it tells the taskbar"
    $front = [FollowTestProbe]::Foreground()
    Look "before any window"

    $companion = New-TestWindow -Title "horde follow test: companion"
    $mine = $companion.Handle.ToInt64()
    Look "the companion first appears"
    Check ([FollowTestProbe]::Visible($mine) -and (Quiet)) ("the companion is shown, and showing it took no keyboard (" + ($script:loud -join "; ") + ")")
    Check (-not (Told 1 $mine)) "made for standing beside a window, it is not a taskbar window"
    Forget

    $a = Start-OtherWindow -Title "horde follow test: the other window"
    $other = $a.handle
    Check ((WaitFor { Told 1 $other })) "CONTROL: the other program's window is an ordinary one, and this suite hears Windows announce it to the taskbar"
    [void][FollowTestProbe]::Move($other, -32000, -32000, 600, 400)
    Pump 300
    Look "the other window appears"

    Write-Host ""
    Write-Host "--- another window's rectangle and scale, through the port ---" -ForegroundColor Cyan
    $read = Get-HordeWindowFollowRectangle -Handle $other
    $sides = [FollowTestProbe]::Sides($other)
    Check ((Test-HordeAnswer $read) -and $read.state -ceq "known" -and $read.value.left -eq $sides[0] -and $read.value.top -eq $sides[1] -and $read.value.right -eq $sides[2] -and $read.value.bottom -eq $sides[3]) ("the port reads the other window where this suite's own probe finds it (" + [FollowTestProbe]::Rect($other) + ")")
    Check ($sides[0] -eq -32000 -and $sides[1] -eq -32000 -and ($sides[2] - $sides[0]) -eq 600) "CONTROL: in real pixels - it stands where it was put, 600 wide, far off every screen"
    Check ((Test-HordeAnswer $read) -and $read.state -ceq "known" -and $read.value.scale -eq ([FollowTestProbe]::Dpi($other) / 96.0)) ("and its scale is its screen's (" + ([FollowTestProbe]::Dpi($other) / 96.0) + ")")

    Write-Host ""
    Write-Host "--- only this process's own window is ever placed ---" -ForegroundColor Cyan
    $r = Start-HordeWindowFollow -Target $mine -Companion $other
    Check ((Field $r "state") -ceq "failed" -and (Field $r "reason") -ceq "the window to place is not this process's own, and only its own window is ever moved") "asked to place another program's window: failed, in words"
    Check ([FollowTestProbe]::Owner($other) -eq 0 -and [FollowTestProbe]::Rect($other) -ceq "-32000,-32000 600x400") "and that window was neither owned nor moved"
    $r = Start-HordeWindowFollow -Target $other -Companion 2147480003
    Check ((Field $r "state") -ceq "failed" -and (Field $r "reason") -ceq "the window to place does not exist") "a companion that is no window: failed"

    Write-Host ""
    Write-Host "--- a follow that could not own is failed, not assumed ---" -ForegroundColor Cyan
    # Windows refuses to make a window the owner of the window that owns it (error 87, measured
    # 2026-10-07). So a hidden window the companion owns is a window that exists and cannot own it.
    $owned = New-TestWindow -Title "horde follow test: owned by the companion" -Top -29000 -Hidden
    [void][FollowTestProbe]::SetOwner($owned.Handle.ToInt64(), $mine)
    $ownerBefore = [FollowTestProbe]::Owner($mine)
    Check ([FollowTestProbe]::Owner($owned.Handle.ToInt64()) -eq $mine) "CONTROL: a hidden window of this suite's is owned by the companion"
    $r = Start-HordeWindowFollow -Target $owned.Handle.ToInt64() -Companion $mine
    Check ((Field $r "state") -ceq "failed" -and "$(Field $r 'reason')" -like "Windows would not make the other window the owner of ours (error *), so it is not followed") ("Windows refuses that owner, and the follow says so: failed (" + (Field $r "state") + ": " + (Field $r "reason") + ")")
    Check ([FollowTestProbe]::Owner($mine) -eq $ownerBefore -and (Field (Get-HordeWindowFollow) "state") -ceq "none") "the companion's owner is what it was, and nothing is being followed"
    [void](Stop-HordeWindowFollow)
    [void][FollowTestProbe]::SetOwner($owned.Handle.ToInt64(), 0)
    Look "after the refusals"

    Write-Host ""
    Write-Host "--- owned, and placed where the pure function says ---" -ForegroundColor Cyan
    Forget
    Check (-not [FollowTestProbe]::IsAbove($mine, $other) -and [FollowTestProbe]::IsAbove($other, $mine)) "CONTROL: made first, the companion stands UNDER the other window until it is followed"
    $r = Start-HordeWindowFollow -Target $other -Companion $mine
    Look "the follow starts"
    Check ((Field $r "state") -ceq "following" -and (Field $r "reason") -ceq "" -and (Field $r "target") -eq $other -and (Field $r "companion") -eq $mine -and (Field $r "mode") -ceq "floating") "the follow starts: following, with both windows and the mode"
    Check ([FollowTestProbe]::Owner($mine) -eq $other) ("the other program's window IS the companion's owner, read back from Windows (" + [FollowTestProbe]::Owner($mine) + ")")
    $want = Expected $other
    $pure = Get-HordeWindowFollowPlacement -Target $read.value -Scale $read.value.scale
    Check ((Placed $r) -ceq $want -and $pure.state -ceq "known" -and ("" + $pure.value.left + "," + $pure.value.top + " " + $pure.value.width + "x" + $pure.value.height) -ceq $want) ("the record says it was placed where the pure function says, which is where this suite works it out (" + (Placed $r) + " against " + $want + ")")
    Check ([FollowTestProbe]::Rect($mine) -ceq $want) ("and that is where the companion IS, in real pixels (" + [FollowTestProbe]::Rect($mine) + ")")
    Check ([FollowTestProbe]::IsAbove($mine, $other)) "it stands above the other window, though it was made first and so stood under it"
    Check (-not (Told 1 $mine)) "owned, it is not a taskbar window"
    Check ((Field $r "placements") -eq 1) "it was placed once"

    Write-Host ""
    Write-Host "--- it goes where the other window goes ---" -ForegroundColor Cyan
    $eventsBefore = [int](Field (Get-HordeWindowFollow) "events")
    [void][FollowTestProbe]::Move($other, -31860, -31930, 600, 400)
    $want = Expected $other
    Check ((WaitFor { [FollowTestProbe]::Rect($mine) -ceq $want })) ("the other window moved by 140,70: the companion moved with it, with nothing here asking (" + [FollowTestProbe]::Rect($mine) + " against " + $want + ")")
    $r = Get-HordeWindowFollow
    Check ([int](Field $r "events") -gt $eventsBefore -and (Placed $r) -ceq $want) ("because Windows reported the move (" + (Field $r "events") + " reports), and the record has the new place")
    Look "after a move"
    [void][FollowTestProbe]::Move($other, -31860, -31930, 1500, 520)
    $want = Expected $other
    Check ((WaitFor { [FollowTestProbe]::Rect($mine) -ceq $want })) ("the other window made 1500 by 520: the companion is resized to a third of it (" + [FollowTestProbe]::Rect($mine) + " against " + $want + ")")
    Check ([FollowTestProbe]::IsAbove($mine, $other)) "and still stands above it"
    Look "after a resize"
    $placedBefore = Placed (Get-HordeWindowFollow)
    $asked = Get-HordeWindowFollow
    Check ((Field $asked "placements") -eq (Field (Get-HordeWindowFollow) "placements")) "asking for the record places nothing"
    $again = Update-HordeWindowFollow
    Check ((Field $again "placements") -eq ([int](Field $asked "placements") + 1) -and (Placed $again) -ceq $placedBefore -and [FollowTestProbe]::Rect($mine) -ceq $want) "placing again places once more, in the same place"

    Write-Host ""
    Write-Host "--- hidden while the other window is minimised, back when it is restored ---" -ForegroundColor Cyan
    [void][FollowTestProbe]::Show($other, 7)        # SW_SHOWMINNOACTIVE
    Check ((WaitFor { -not [FollowTestProbe]::Visible($mine) })) "the other window minimised: the companion is hidden"
    Pump 300
    $r = Update-HordeWindowFollow
    Check ((Field $r "state") -ceq "following" -and (Placed $r) -ceq $placedBefore) ("it is still following, and a minimised window's rectangle was not taken for a place (" + (Placed $r) + ")")
    Look "while minimised"
    [void][FollowTestProbe]::Show($other, 4)        # SW_SHOWNOACTIVATE
    Check ((WaitFor { [FollowTestProbe]::Visible($mine) -and [FollowTestProbe]::Rect($mine) -ceq $want })) ("restored: the companion is back, where it stood (" + [FollowTestProbe]::Rect($mine) + ")")
    Look "after a restore"
    Check ((Quiet)) ("through all of that no test window had the keyboard (" + $script:looks + " looks; " + ($script:loud -join "; ") + ")")

    Write-Host ""
    Write-Host "--- stopped while following ---" -ForegroundColor Cyan
    $r = Stop-HordeWindowFollow
    Check ((Field $r "state") -ceq "none" -and [FollowTestProbe]::Owner($mine) -eq 0) "stopped while following: nothing is followed, and the companion is no longer owned"
    $stood = [FollowTestProbe]::Rect($mine)
    [void][FollowTestProbe]::Move($other, -31900, -31900, 1500, 520)
    Pump 1000
    Check ([FollowTestProbe]::Rect($mine) -ceq $stood) "the other window moves and the companion is no longer moved"
    $r = Start-HordeWindowFollow -Target $other -Companion $mine
    $want = Expected $other
    Check ((Field $r "state") -ceq "following" -and [FollowTestProbe]::Rect($mine) -ceq $want) "started again, it stands beside the other window where that now is"
    [void][FollowTestProbe]::Move($other, -31860, -31930, 1500, 520)
    $want = Expected $other
    Check ((WaitFor { [FollowTestProbe]::Rect($mine) -ceq $want })) "and goes where it goes"
    Look "after a stop and a start"

    Write-Host ""
    Write-Host "--- let go, it stands free ---" -ForegroundColor Cyan
    Forget
    $countedBefore = [int](Field (Get-HordeWindowFollow) "events")
    Check ($countedBefore -gt 0) "CONTROL: this follow counted reports of moves"
    $r = Disconnect-HordeWindowFollow
    Look "the companion is let go"
    Check ((Field $r "state") -ceq "free" -and (Field $r "reason") -ceq "it was let go, and stands free" -and (Field $r "companion") -eq $mine) "let go: free, in words"
    Check ([FollowTestProbe]::Owner($mine) -eq 0) "it is no longer owned"
    $stood = [FollowTestProbe]::Rect($mine)
    [void][FollowTestProbe]::Move($other, -31700, -31800, 1500, 520)
    Pump 1200
    Check ([FollowTestProbe]::Rect($mine) -ceq $stood -and (Field (Get-HordeWindowFollow) "state") -ceq "free") ("the other window moves on and the free one stays where it stood (" + [FollowTestProbe]::Rect($mine) + ")")
    Check ([FollowTestProbe]::Exists($other)) "CONTROL: the other window is still there; it was let go, not lost"


    Write-Host ""
    Write-Host "--- followed again ---" -ForegroundColor Cyan
    Forget
    $r = Start-HordeWindowFollow -Target $other -Companion $mine
    Look "the follow starts again"
    $want = Expected $other
    Check ((Field $r "state") -ceq "following" -and [FollowTestProbe]::Owner($mine) -eq $other -and [FollowTestProbe]::Rect($mine) -ceq $want) ("the free window is made a companion again: owned, and placed beside the other window where it now is (" + [FollowTestProbe]::Rect($mine) + ")")
    Look "after the second follow"

    Write-Host ""
    Write-Host "--- the other WINDOW is closed while its process lives: lost ---" -ForegroundColor Cyan
    Forget
    [void][FollowTestProbe]::Close($other)
    Check ((WaitFor { -not [FollowTestProbe]::Exists($other) })) "the other window is closed"
    Check ((WaitFor { (Field (Get-HordeWindowFollow) "state") -ceq "lost" })) "asked, the follow answers lost"
    $r = Get-HordeWindowFollow
    Check (-not $a.process.HasExited) "CONTROL: the other PROCESS is still running"
    Check ([FollowTestProbe]::Exists($mine)) "the companion was NOT destroyed with the window that owned it"
    Check ((Field $r "reason") -ceq "the window it stood beside no longer exists" -and (Field $r "companion") -eq $mine -and (Placed $r) -ceq $want) "the record says why, and where the companion last stood"
    Check ([FollowTestProbe]::Owner($mine) -eq 0) "it is owned by nothing"
    Look "after the other window was closed"
    Check ((Quiet)) ("and nothing took the keyboard (" + ($script:loud -join "; ") + ")")
    Check ((Field (Stop-HordeWindowFollow) "state") -ceq "none" -and (Field (Get-HordeWindowFollow) "state") -ceq "none") "stopped: nothing is followed"
    $a.process.Kill(); [void]$a.process.WaitForExit(10000)

    Write-Host ""
    Write-Host "--- the other PROCESS ends: lost ---" -ForegroundColor Cyan
    $b = Start-OtherWindow -Title "horde follow test: the second other window"
    $second = $b.handle
    [void][FollowTestProbe]::Move($second, -32000, -32000, 600, 400)
    Pump 300
    $r = Start-HordeWindowFollow -Target $second -Companion $mine
    $want = Expected $second
    Check ((Field $r "state") -ceq "following" -and [FollowTestProbe]::Owner($mine) -eq $second -and [FollowTestProbe]::Rect($mine) -ceq $want) "the companion follows a second program's window"
    Forget
    $b.process.Kill(); [void]$b.process.WaitForExit(10000)
    Check ((WaitFor { -not [FollowTestProbe]::Exists($second) })) "the other process is ended, and its window is gone with it"
    Check ((WaitFor { (Field (Get-HordeWindowFollow) "state") -ceq "lost" })) "asked, the follow answers lost"
    Check ([FollowTestProbe]::Exists($mine) -and [FollowTestProbe]::Owner($mine) -eq 0) "the companion is still there, owned by nothing"
    Look "after the other process ended"
    [void](Stop-HordeWindowFollow)

    Write-Host ""
    Write-Host "--- never the keyboard ---" -ForegroundColor Cyan
    Check ($script:looks -ge 10 -and (Quiet)) ("at none of " + $script:looks + " looks was a test window the foreground window or its thread's active one (" + ($script:loud -join "; ") + ")")
    Check ([FollowTestProbe]::ThreadActive() -ne -1) "CONTROL: this thread's active window can be read"
}
finally {
    # Whatever happened above. Only what this suite made: its own forms, and the processes it started,
    # by the handles it holds.
    try { [void](Stop-HordeWindowFollow) } catch { }
    foreach ($form in @($script:forms)) { try { $form.Close(); $form.Dispose() } catch { } }
    foreach ($started in @($script:others)) { try { if (-not $started.process.HasExited) { $started.process.Kill() } } catch { } }
    if ($null -ne $script:watch) { try { $script:watch.Done() } catch { } }
    try { [System.IO.File]::Delete($script:otherScript) } catch { }
}

Complete-HordeSuite -Success "a real window is kept beside another program's real window, and stands free when that window is gone"
