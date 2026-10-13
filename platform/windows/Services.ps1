# platform/windows/Services.ps1 - the Windows adapter for core/ServiceHostPort.ps1: is the person at
# the machine, start a process that outlives the pass that started it, and ask a window to close.
#
# IDLE IS THE TIME SINCE THE LAST KEY OR MOUSE INPUT (user32 GetLastInputInfo against GetTickCount).
#   - IT IS A FACT OF ONE LOGON SESSION. Windows keeps the last input per session, so a process that
#     is not in the person's own interactive session - a scheduled job running "whether the user is
#     logged on or not", a service, an SSH logon - is told about a session nobody types in, and would
#     read as idle for ever. Such a process answers UNKNOWN, with that reason: session 0, or a process
#     that is not interactive, cannot see the person. The supervisor waits on an unknown.
#   - THE TICK COUNT WRAPS every 49.7 days (it is 32 bits of milliseconds). The two readings are
#     subtracted as unsigned 32-bit numbers, which is right across one wrap; an idle time of more than
#     49.7 days reads short, which errs towards "not idle", the safe side.
#   - WHAT IT DOES NOT SEE: a person reading the screen without touching anything, or watching a
#     film. "Idle" here means only "no input".
#
# A STARTED PROCESS IS CREATED BY WMI (Win32_Process.Create), NOT AS A CHILD OF THIS ONE. The
# supervisor's pass is a scheduled job with a time limit, and many tools keep their children in a job
# object that ends with them; a service must outlive both. WHETHER the scheduler would end an ordinary
# child with the pass was NOT measured here: a process WMI creates is the WMI host's child and nobody's
# job, so the question does not arise. It runs in the caller's logon session, so a window it opens is
# on the person's desktop. The script this replaces started its two services the same way. It is
# reached through the [wmiclass] accelerator, which Windows PowerShell 5.1 carries itself, not through
# the CIM cmdlets: those are found through PSModulePath, and a PSModulePath another shell left behind
# breaks module discovery in 5.1 (platform/windows/Firewall.ps1 met the same thing).
#
# NO VALUE IS EVER PARSED AS CODE (core/schedule/WindowsTaskScheduler.ps1, from the review of PR #70).
# A horde launch becomes powershell.exe -EncodedCommand: one fixed command in which every value - the
# script, each word, each named value, the home, the folder, the log - is base64 of its UTF-8 text,
# decoded at run time, so no quote, &, %, $ or backtick in a path can end a string or start a command.
# The only texts written into the command as they are, are parameter and environment names, and those
# are letters, digits and underscores by the port's own check, made again here. A program launch is
# the program and its arguments joined by the port's one quoting function (ConvertTo-HordeServiceArgument).
#
# WHAT A HORDE SERVICE PRINTS IS KEPT, in the launch's log file: each line it writes to the host or
# to its output, with the time in front, and what horde itself writes to the process's error stream
# when a command fails - which is the line that says why a service died.
#   - NOT `*>&1`. The script this replaces merged every stream that way; under Windows PowerShell 5.1
#     a redirected error stream turns a native program's stderr into terminating errors (CONTRIBUTING
#     12), and that would hold for everything the service ever runs. Only the information stream is
#     merged (6>&1), which is where a long-running command's lines go.
#   - horde reports a failed command with [Console]::Error, which no PowerShell redirection sees, so
#     the process's error writer is pointed at the same log before the command runs.
#   - A LOG THAT CANNOT BE OPENED DOES NOT STOP THE SERVICE: it then runs unlogged.
#
# THE CONSOLE WINDOW of a started powershell.exe is hidden by its own -WindowStyle Hidden, which shows
# for a moment as it starts. A start is rare, so that is accepted; passing a hidden show-state in the
# start-up information instead would also hide the first window the service itself opens.
#
# A WINDOW IS ASKED TO CLOSE, NOT CLOSED: WM_CLOSE is posted to it, which is what clicking its close
# button sends, so the program that owns it closes it the way it always does - saving what it saves,
# letting go of what it holds - and then ends by itself. The script this replaces did the same to the
# decisions window. TWO THINGS ARE CHECKED FIRST, in this order, and nothing is sent unless both hold:
# the handle IS a window now (IsWindow), and that window belongs to the process named
# (GetWindowThreadProcessId). A handle read from a file is a number Windows gives out again: the
# window it named when the file was written may be gone, and the number may be another program's
# window today. Posting does not wait: whether the window then closes is the supervisor's to see, by
# the process ending, and it ends the process itself when the wait it was given runs out.
#
# NEVER RUN BY A SUITE AGAINST A REAL SERVICE. The suites drive the port through a stand-in adapter;
# of this file they run the pure builders (the command text, the quoting) and, once, a start of a
# child that only writes a file into the suite's own temp folder.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

function Get-HordeWindowsIdleSource { return @"
using System;
using System.Runtime.InteropServices;
public static class HordeWindowsIdleV1 {
    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO info);
    [DllImport("kernel32.dll")] static extern uint GetTickCount();
    // Milliseconds since the last input in this session, or -1 when the system would not say.
    public static long IdleMilliseconds() {
        var info = new LASTINPUTINFO();
        info.cbSize = (uint)Marshal.SizeOf(info);
        if (!GetLastInputInfo(ref info)) { return -1; }
        return (long)unchecked(GetTickCount() - info.dwTime);
    }
}
"@ }

function Initialize-HordeWindowsIdleType {
    # Compiled once a process, on first use (about 0.2 s; core/Platform.ps1 measured Add-Type). The
    # name carries a version so a later change is a new type, never a clash with one already loaded.
    if (-not ("HordeWindowsIdleV1" -as [type])) { Add-Type -TypeDefinition (Get-HordeWindowsIdleSource) }
}

function Get-HordeWindowsSessionSeesPerson {
    # Can this process see the person's input? "" when it can; otherwise why not (header).
    param($Interactive = [System.Environment]::UserInteractive, $SessionId = $null)
    if ($null -eq $SessionId) {
        $self = [System.Diagnostics.Process]::GetCurrentProcess()
        try { $SessionId = $self.SessionId } finally { $self.Dispose() }
    }
    if ($Interactive -ne $true) { return "this process is not interactive, so it is not in the session the person types in" }
    if ([int]$SessionId -eq 0) { return "this process is in session 0, where no person types" }
    return ""
}

function Get-HordeWindowsIdleSeconds {
    # The port's IdleSeconds: known whole seconds, or unknown with the reason.
    $blind = Get-HordeWindowsSessionSeesPerson
    if ($blind -ne "") { return (New-HordeUnknown -Reason $blind) }
    try {
        Initialize-HordeWindowsIdleType
        $ms = [HordeWindowsIdleV1]::IdleMilliseconds()
        if ($ms -lt 0) { return (New-HordeUnknown -Reason "Windows would not say when the last input was") }
        return (New-HordeKnown -Value ([long][System.Math]::Floor($ms / 1000.0)))
    } catch { return (New-HordeUnknown -Reason "the time of the last input could not be read" -ErrorRecord $_) }
}

function Get-HordeWindowsServiceShell {
    # The one shell a horde launch runs in: Windows PowerShell from the system folder, by its path,
    # never whatever a search path finds first.
    return [System.IO.Path]::Combine([System.Environment]::SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe")
}

function ConvertTo-HordeWindowsServiceScript {
    # The fixed command a horde launch runs (header): every value decoded from base64 at run time.
    param([Parameter(Mandatory = $true)]$Launch)
    $b = { param([string]$Text) return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Text)) }
    $name = '\A[A-Za-z_][A-Za-z0-9_]{0,39}\z'
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('$ErrorActionPreference = ''Stop''; $d = { param($b) [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b)) }; ')
    foreach ($k in @($Launch.environment.Keys | Sort-Object)) {
        if ("" + $k -cnotmatch $name) { throw ("not an environment variable name: '" + $k + "'") }
        [void]$sb.Append('[System.Environment]::SetEnvironmentVariable(''' + $k + ''', (& $d ''' + (& $b ("" + $Launch.environment[$k])) + '''), ''Process''); ')
    }
    if ($Launch.workingDirectory -ne "") { [void]$sb.Append('Set-Location -LiteralPath (& $d ''' + (& $b $Launch.workingDirectory) + '''); ') }
    $call = New-Object System.Text.StringBuilder
    [void]$call.Append('& (& $d ''' + (& $b $Launch.script) + ''')')
    foreach ($w in @($Launch.words)) { [void]$call.Append(' (& $d ''' + (& $b $w) + ''')') }
    foreach ($k in @($Launch.named.Keys)) {
        if ("" + $k -cnotmatch $name) { throw ("not a parameter name: '" + $k + "'") }
        [void]$call.Append(' -' + $k + ' (& $d ''' + (& $b ("" + $Launch.named[$k])) + ''')')
    }
    foreach ($k in @($Launch.switches)) {
        if ("" + $k -cnotmatch $name) { throw ("not a parameter name: '" + $k + "'") }
        [void]$call.Append(' -' + $k)
    }
    if ($Launch.logFile -eq "") { [void]$sb.Append($call.ToString() + '; exit $LASTEXITCODE'); return $sb.ToString() }
    # The log (header): opened for appending and shared, so a reader never blocks the service.
    [void]$sb.Append('$w = $null; try { $w = New-Object System.IO.StreamWriter((New-Object System.IO.FileStream((& $d ''' + (& $b $Launch.logFile) + '''), [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)), (New-Object System.Text.UTF8Encoding($false))); $w.AutoFlush = $true; [System.Console]::SetError($w) } catch { $w = $null }; ')
    [void]$sb.Append('if ($null -eq $w) { ' + $call.ToString() + ' } else { ' + $call.ToString() + ' 6>&1 | ForEach-Object { $w.WriteLine((Get-Date -Format s) + '' '' + $_) } }; exit $LASTEXITCODE')
    return $sb.ToString()
}

function ConvertTo-HordeWindowsServiceCommandLine {
    # The whole command line of a launch, of either kind.
    param([Parameter(Mandatory = $true)]$Launch)
    if ($Launch.kind -ceq "program") {
        return ((@($Launch.program) + @($Launch.arguments) | ForEach-Object { ConvertTo-HordeServiceArgument -Text ("" + $_) }) -join " ")
    }
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes((ConvertTo-HordeWindowsServiceScript -Launch $Launch)))
    return ((ConvertTo-HordeServiceArgument -Text (Get-HordeWindowsServiceShell)) + " -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand " + $encoded)
}

function Start-HordeWindowsService {
    # The port's Start: create the process (header), then read back when it started. A process that
    # has already ended by then is a failed start, said so: it has no identity to keep.
    param([Parameter(Mandatory = $true)]$Launch)
    $line = ConvertTo-HordeWindowsServiceCommandLine -Launch $Launch
    # CreateProcess takes at most 32,767 characters; a longer line fails there with a code, not a reason.
    if ($line.Length -gt 32000) { return (New-HordeUnknown -Reason ("the command line would be " + $line.Length + " characters, more than Windows takes")) }
    $folder = $null
    if ($Launch.workingDirectory -ne "") { $folder = $Launch.workingDirectory }
    $made = ([wmiclass]"Win32_Process").Create($line, $folder, $null)
    if ($null -eq $made -or [int]$made.ReturnValue -ne 0) { return (New-HordeUnknown -Reason ("Windows did not create the process (Win32_Process.Create answered " + $(if ($null -eq $made) { "nothing" } else { "" + $made.ReturnValue }) + ")")) }
    $processId = [int]$made.ProcessId
    try {
        $p = [System.Diagnostics.Process]::GetProcessById($processId)
        try { return (New-HordeKnown -Value ([pscustomobject]@{ pid = $processId; startedAt = $p.StartTime.ToUniversalTime() })) } finally { $p.Dispose() }
    } catch { return (New-HordeUnknown -Reason ("process " + $processId + " was created and had ended before it could be looked at")) }
}

function Get-HordeWindowsCloseSource { return @"
using System;
using System.Runtime.InteropServices;
public static class HordeWindowsCloseV1 {
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll", SetLastError = true)] static extern bool PostMessage(IntPtr window, uint message, IntPtr w, IntPtr l);
    // 0: asked (WM_CLOSE, 0x0010, was posted). 1: the handle is not a window. 2: it is a window of
    // another process. Negative: the post failed, and the number is the Win32 error, negated.
    public static int AskToClose(long handle, uint processId) {
        var window = new IntPtr(handle);
        if (!IsWindow(window)) { return 1; }
        uint owner;
        GetWindowThreadProcessId(window, out owner);
        if (owner != processId) { return 2; }
        if (!PostMessage(window, 0x0010, IntPtr.Zero, IntPtr.Zero)) { int e = Marshal.GetLastWin32Error(); return e == 0 ? -1 : -e; }
        return 0;
    }
}
"@ }

function Close-HordeWindowsServiceWindow {
    # The port's CloseWindow (header): known "asked"; absent when the handle is no window, or is
    # another process's - nothing was sent; unknown when the post itself failed.
    param([Parameter(Mandatory = $true)][int]$ProcessId, [Parameter(Mandatory = $true)][long]$Handle)
    try {
        if (-not ("HordeWindowsCloseV1" -as [type])) { Add-Type -TypeDefinition (Get-HordeWindowsCloseSource) }
        $result = [HordeWindowsCloseV1]::AskToClose($Handle, [uint32]$ProcessId)
        if ($result -eq 0) { return (New-HordeKnown -Value "asked") }
        if ($result -eq 1) { return (New-HordeAbsent -Note ("there is no window " + $Handle + " any more; nothing was sent")) }
        if ($result -eq 2) { return (New-HordeAbsent -Note ("window " + $Handle + " is not a window of process " + $ProcessId + "; nothing was sent")) }
        return (New-HordeUnknown -Reason ("Windows would not take the close message for window " + $Handle + " (error " + (0 - $result) + ")"))
    } catch { return (New-HordeUnknown -Reason "the window could not be asked to close" -ErrorRecord $_) }
}

function Register-HordeWindowsServiceHost {
    $blocks = @{
        Name        = "windows"
        Applies     = { [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT }
        IdleSeconds = { Get-HordeWindowsIdleSeconds }
        Start       = { param($Launch) Start-HordeWindowsService -Launch $Launch }
        CloseWindow = { param($ProcessId, $Handle) Close-HordeWindowsServiceWindow -ProcessId $ProcessId -Handle $Handle }
    }
    Register-HordeServiceHost @blocks
}
Register-HordeWindowsServiceHost
