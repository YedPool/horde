# DOES A PROCESS THAT ASKS FOR THE SCREEN'S REAL SCALE GET IT, ONCE, AND IS IT TOLD THE TRUTH ABOUT WHAT IT IS?
#
# platform/windows/Scale.ps1: Enable-HordeWindowsRealScale and Get-HordeWindowsScaleAwareness, the one
# owner of "tell Windows this process draws at the screen's real scale".
#
# THE REAL CALL IS PROVED IN CHILD PROCESSES. Windows keeps one awareness per process and lets it be
# set once, so nothing can be measured twice in one process, and this suite never asks for its own.
# Each child is a fresh Windows PowerShell started for the purpose; it loads the shipped file, does
# one thing and prints what it read. Measured 2026-10-07 on Windows 10.0.26200 before this suite was
# written: a fresh child read unaware, the call was taken and it read per-monitor-v2, a second call
# was refused with error 5, and a child set to system awareness first was refused the same way and
# stayed system.
#
# THE RULES THAT TURN WINDOWS' ANSWER INTO OURS are pure and are tested here with no call at all,
# which is also the only way this machine can reach "a Windows too old to have the call".
#
# No window is ever shown: the one window a child makes is a form whose handle exists and which is
# never shown, as the control that the window count can see a window. Every child is started and
# awaited by test/lib/Program.ps1, which stops only the process it started. One child replaces the
# shipped file's source function with text that cannot be compiled, in its own process, to reach the
# two paths that answer when the native half fails.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "test\lib\Program.ps1")
$scale = Join-Path $root "platform\windows\Scale.ps1"
. $scale

function Get-Field {
    # A field of an answer, or the text "<none>" when the answer does not carry it - so that a missing
    # field fails a check instead of raising under strict mode.
    param($Answer, [string]$Name)
    if ($null -eq $Answer -or $null -eq $Answer.PSObject.Properties[$Name]) { return "<none>" }
    return $Answer.PSObject.Properties[$Name].Value
}

Write-Host ""
Write-Host "--- loading the file does nothing ---" -ForegroundColor Cyan
Check ($null -eq ("HordeWindowsScaleV1" -as [type])) "dot-sourcing compiles nothing and asks Windows nothing: the native type is not loaded"

Write-Host ""
Write-Host "--- what Windows answered, turned into what the call did ---" -ForegroundColor Cyan
$s = ConvertTo-HordeWindowsScaleState -Taken 1 -ErrorCode 0
Check ((Get-Field $s "state") -ceq "applied" -and "$(Get-Field $s 'reason')" -ne "") "taken is applied, with a reason"
# A success leaves the last error of some earlier call behind: measured 2026-10-07, 203 after a call
# that was taken. It must not be read.
$s = ConvertTo-HordeWindowsScaleState -Taken 1 -ErrorCode 5
Check ((Get-Field $s "state") -ceq "applied") "taken is applied whatever error number an earlier call left behind"
$s = ConvertTo-HordeWindowsScaleState -Taken 0 -ErrorCode 5
Check ((Get-Field $s "state") -ceq "already" -and "$(Get-Field $s 'reason')" -like "*already*") "refused with error 5 is already: the awareness was set before"
$s = ConvertTo-HordeWindowsScaleState -Taken 0 -ErrorCode 87
Check ((Get-Field $s "state") -ceq "unavailable" -and "$(Get-Field $s 'reason')" -like "*error 87*") "refused with any other error is unavailable, and the reason carries the number"
$s = ConvertTo-HordeWindowsScaleState -Taken 0 -ErrorCode 0
Check ((Get-Field $s "state") -ceq "unavailable" -and "$(Get-Field $s 'reason')" -like "*error 0*") "refused with no error number is unavailable, never already"
$s = ConvertTo-HordeWindowsScaleState -Taken -1 -ErrorCode 0
Check ((Get-Field $s "state") -ceq "unavailable" -and "$(Get-Field $s 'reason')" -like "*1703*") "a Windows with no such call is unavailable, and the reason names the version that has it"
$s = ConvertTo-HordeWindowsScaleState -Taken -1 -ErrorCode 5
Check ((Get-Field $s "state") -ceq "unavailable") "CONTROL: no such call is unavailable even beside error 5"
Check (@("applied", "already", "unavailable") -join "," -ceq (@(Get-HordeWindowsScaleStates) -join ",")) "the states a caller can be answered are these three, in one list"

Write-Host ""
Write-Host "--- what Windows named, turned into what the process is ---" -ForegroundColor Cyan
$want = @(
    @{ code = 1; awareness = "unaware"; realScale = "no" }
    @{ code = 2; awareness = "system"; realScale = "no" }
    @{ code = 3; awareness = "per-monitor"; realScale = "yes" }
    @{ code = 4; awareness = "per-monitor-v2"; realScale = "yes" }
    @{ code = 5; awareness = "unaware-gdi-scaled"; realScale = "no" }
)
foreach ($w in $want) {
    $a = ConvertTo-HordeWindowsScaleAwareness -Code $w.code
    Check ((Get-Field $a "awareness") -ceq $w.awareness -and (Get-Field $a "realScale") -ceq $w.realScale -and (Get-Field $a "reason") -ceq "") ("context " + $w.code + " is " + $w.awareness + ", real scale " + $w.realScale)
}
$a = ConvertTo-HordeWindowsScaleAwareness -Code 0
Check ((Get-Field $a "awareness") -ceq "unknown" -and (Get-Field $a "realScale") -ceq "unknown" -and "$(Get-Field $a 'reason')" -like "*does not know*") "a context this file does not know is unknown, never no"
$a = ConvertTo-HordeWindowsScaleAwareness -Code 6
Check ((Get-Field $a "awareness") -ceq "unknown" -and (Get-Field $a "realScale") -ceq "unknown") "and so is a number past the list"
$a = ConvertTo-HordeWindowsScaleAwareness -Code -1
Check ((Get-Field $a "awareness") -ceq "unknown" -and (Get-Field $a "realScale") -ceq "unknown" -and "$(Get-Field $a 'reason')" -like "*1803*") "a Windows that cannot be asked is unknown, and the reason names the version that can"

if (-not (Test-HordeIsWindows)) {
    Write-Host "  [SKIP] the real call: this is not Windows" -ForegroundColor Yellow
    Complete-HordeSuite -Success "OFF WINDOWS - ONLY THE PURE RULES RAN, EXIT 3" -PassCode 3
}

Write-Host ""
Write-Host "--- the real call, each in a fresh process ---" -ForegroundColor Cyan
# The probe every child runs. __SCALE__ is the shipped file. Its own native half counts the windows of
# its own process - top-level ones and message-only ones - and can set the awareness the wrong way, as
# a process that was started with a manifest or by another library would have it.
$probeText = @'
param([string]$Mode)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class ScaleProbe {
    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] static extern IntPtr FindWindowExW(IntPtr parent, IntPtr after, IntPtr cls, IntPtr title);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("kernel32.dll")] static extern uint GetCurrentProcessId();
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr v);
    static bool Mine(IntPtr h) { uint p; GetWindowThreadProcessId(h, out p); return p == GetCurrentProcessId(); }
    public static int Windows() {
        int n = 0;
        EnumWindows(delegate(IntPtr h, IntPtr l) { if (Mine(h)) n++; return true; }, IntPtr.Zero);
        IntPtr m = IntPtr.Zero; int guard = 0;
        while (guard++ < 100000) { m = FindWindowExW(new IntPtr(-3), m, IntPtr.Zero, IntPtr.Zero); if (m == IntPtr.Zero) break; if (Mine(m)) n++; }
        return n;
    }
    public static bool PresetSystem() { return SetProcessDpiAwarenessContext(new IntPtr(-2)); }
}
"@
. '__SCALE__'
# A native half that cannot be compiled, and a caller that does not stop on errors: the answers must
# still come, and nothing may reach the error stream.
if ($Mode -eq "broken") { $ErrorActionPreference = "Continue"; function Get-HordeWindowsScaleSource { return "this is not a program" } }
function Say { param([string]$Tag, $Answer) Write-Output ($Tag + " " + @($Answer).Count + " " + (@($Answer | ForEach-Object { @($_.PSObject.Properties | ForEach-Object { $_.Name + "=" + (("" + $_.Value) -replace "\s+", " ") }) -join ";" }) -join " // ")) }
$form = $null
if ($Mode -eq "window") { Add-Type -AssemblyName System.Windows.Forms; $w0 = [ScaleProbe]::Windows(); $form = New-Object System.Windows.Forms.Form; $null = $form.Handle; Write-Output ("MADE " + $w0 + " " + [ScaleProbe]::Windows() + " " + $form.Visible) }
$before = [ScaleProbe]::Windows()
Say "BEFORE" (Get-HordeWindowsScaleAwareness)
if ($Mode -eq "system") { Write-Output ("PRESET " + [ScaleProbe]::PresetSystem()) }
if ($Mode -ne "none") {
    Say "FIRST" (Enable-HordeWindowsRealScale)
    Say "SECOND" (Enable-HordeWindowsRealScale)
}
Say "AFTER" (Get-HordeWindowsScaleAwareness)
Write-Output ("WINDOWS " + $before + " " + [ScaleProbe]::Windows())
if ($null -ne $form) { $form.Dispose() }
Write-Output "END"
'@

$work = Join-Path $env:TEMP ("horde-winscale-" + [guid]::NewGuid().ToString("N"))
$runs = @{}
try {
    New-Item -ItemType Directory -Path $work | Out-Null
    $probe = Join-Path $work "probe.ps1"
    [System.IO.File]::WriteAllText($probe, $probeText.Replace("__SCALE__", $scale.Replace("'", "''")))
    $shell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    foreach ($mode in @("none", "call", "system", "window", "broken")) {
        # A home and a working folder of the child's own, both empty, so that anything it wrote is seen.
        $childHome = Join-Path $work ("home-" + $mode); $cwd = Join-Path $work ("cwd-" + $mode)
        New-Item -ItemType Directory -Path $childHome | Out-Null; New-Item -ItemType Directory -Path $cwd | Out-Null
        $r = Invoke-HordeTestProgram -Path $shell -ArgList @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $probe, "-Mode", $mode) -Env @{ HORDE_HOME = $childHome } -WorkDir $cwd -TimeoutSeconds 240
        $lines = @("$($r.out)" -split "\r?\n" | Where-Object { $_ -ne "" })
        $tags = @{}
        foreach ($l in $lines) { $tag = @($l -split " ", 2)[0]; $tags[$tag] = $l }
        $runs[$mode] = [pscustomobject]@{ run = $r; lines = $lines; tags = $tags
            left = @(Get-ChildItem -LiteralPath $childHome -Force -Recurse).Count + @(Get-ChildItem -LiteralPath $cwd -Force -Recurse).Count }
    }
} finally {
    if ((Split-Path -Leaf $work) -match '^horde-winscale-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

function Line { param([string]$Mode, [string]$Tag) if ($runs.ContainsKey($Mode) -and $runs[$Mode].tags.ContainsKey($Tag)) { return "" + $runs[$Mode].tags[$Tag] }; return "<no " + $Tag + " line>" }
function Ended { param([string]$Mode) return [bool]($runs.ContainsKey($Mode) -and $runs[$Mode].run.timedOut -eq $false -and $runs[$Mode].run.code -eq 0 -and @($runs[$Mode].lines).Count -gt 0 -and @($runs[$Mode].lines)[-1] -ceq "END") }
function ErrText { param([string]$Mode) if ($runs.ContainsKey($Mode)) { $t = "$($runs[$Mode].run.err)".Trim(); return $t.Substring(0, [Math]::Min(300, $t.Length)) }; return "<not run>" }

$unaware = "1 awareness=unaware;realScale=no;reason="
$v2 = "1 awareness=per-monitor-v2;realScale=yes;reason="

# CONTROL: a process that never asks stays what it was, so "per-monitor-v2" below is the call's doing
# and not what every process reads.
Check (Ended "none") ("CONTROL: the child that never asks ran to its end (" + (ErrText "none") + ")")
Check ((Line "none" "BEFORE") -ceq ("BEFORE " + $unaware)) ("a fresh process is not aware: " + (Line "none" "BEFORE"))
Check ((Line "none" "AFTER") -ceq ("AFTER " + $unaware)) ("CONTROL: and reading it twice does not change it: " + (Line "none" "AFTER"))

Check (Ended "call") ("the child that asks ran to its end (" + (ErrText "call") + ")")
Check ((Line "call" "BEFORE") -ceq ("BEFORE " + $unaware)) ("before the call it is not aware: " + (Line "call" "BEFORE"))
Check ((Line "call" "FIRST") -clike "FIRST 1 state=applied;awareness=per-monitor-v2;realScale=yes;reason=?*") ("the call is applied and answers one object saying what the process now is: " + (Line "call" "FIRST"))
Check ((Line "call" "SECOND") -clike "SECOND 1 state=already;awareness=per-monitor-v2;realScale=yes;reason=?*") ("a second call answers already, and still says what the process is: " + (Line "call" "SECOND"))
Check ((Line "call" "AFTER") -ceq ("AFTER " + $v2)) ("after the call the process reads per-monitor-v2: " + (Line "call" "AFTER"))
$m = [regex]::Match((Line "call" "WINDOWS"), '^WINDOWS (\d+) (\d+)\z')
Check ($m.Success -and $m.Groups[1].Value -ceq $m.Groups[2].Value) ("the call made no window, top-level or message-only: " + (Line "call" "WINDOWS"))
Check ($runs.ContainsKey("call") -and $runs["call"].left -eq 0) "it left nothing in the home or the working folder"
Check ($runs.ContainsKey("call") -and "$($runs['call'].run.err)".Trim() -ceq "" -and @($runs["call"].lines).Count -eq 6) ("it printed nothing of its own: the probe's six lines and no error text (" + $(if ($runs.ContainsKey("call")) { @($runs["call"].lines).Count } else { "not run" }) + ")")

# A process whose awareness was set another way - a manifest, a library - is "already", and the answer
# says it does NOT see real scale, so a caller that reads rectangles can tell.
Check (Ended "system") ("the child set to system awareness first ran to its end (" + (ErrText "system") + ")")
Check ((Line "system" "PRESET") -ceq "PRESET True") ("CONTROL: the probe set system awareness itself: " + (Line "system" "PRESET"))
Check ((Line "system" "FIRST") -clike "FIRST 1 state=already;awareness=system;realScale=no;reason=?*") ("the call then answers already, with the truth that this is not real scale: " + (Line "system" "FIRST"))
Check ((Line "system" "AFTER") -ceq "AFTER 1 awareness=system;realScale=no;reason=") ("and the process stays system aware: " + (Line "system" "AFTER"))

# CONTROL for the window count: a form whose handle exists, never shown, is counted.
Check (Ended "window") ("the child that makes a never-shown window ran to its end (" + (ErrText "window") + ")")
$m = [regex]::Match((Line "window" "MADE"), '^MADE (\d+) (\d+) False\z')
Check ($m.Success -and [int]$m.Groups[2].Value -gt [int]$m.Groups[1].Value) ("CONTROL: the window count sees a window that was made and never shown: " + (Line "window" "MADE"))
$m = [regex]::Match((Line "window" "WINDOWS"), '^WINDOWS (\d+) (\d+)\z')
Check ($m.Success -and [int]$m.Groups[1].Value -ge 1 -and $m.Groups[1].Value -ceq $m.Groups[2].Value) ("and beside that window the call still makes none: " + (Line "window" "WINDOWS"))
# IT NEVER THROWS: with a native half that cannot be compiled, both functions still answer, and say why.
Check (Ended "broken") ("the child whose native half cannot be compiled ran to its end (" + (ErrText "broken") + ")")
Check ((Line "broken" "FIRST") -clike "FIRST 1 state=unavailable;awareness=unknown;realScale=unknown;reason=the call could not be made: ?*") ("the call then answers unavailable and unknown, with the cause: " + (Line "broken" "FIRST"))
Check ((Line "broken" "AFTER") -clike "AFTER 1 awareness=unknown;realScale=unknown;reason=the awareness could not be read: ?*") ("and the read answers unknown, with the cause: " + (Line "broken" "AFTER"))
Check ($runs.ContainsKey("broken") -and "$($runs['broken'].run.err)".Trim() -ceq "" -and @($runs["broken"].lines).Count -eq 6) ("and nothing reaches the error stream of a caller that does not stop on errors (" + (ErrText "broken") + ")")

# MEASURED, NOT PROMISED: what Windows answers once a window exists. Printed so a change is seen.
Write-Host ("  MEASURE with a never-shown window already made: " + (Line "window" "FIRST")) -ForegroundColor DarkGray

Complete-HordeSuite -Success "a process is told the screen's real scale once, and is always told what it is"
