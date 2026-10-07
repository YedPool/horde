# hosts/wezterm/Act.ps1 - the acting half of the WezTerm host: start a program in a pane of a named
# terminal, type into one of its panes, end one, and say whether one is still there.
#
# THE ACT PATH'S A2 (planning/execution-plan-remote.md, R19's first version, 2026-10-05). A node starts
# a harness in its OWN terminal, the one its user is logged in to, so the session is a child of that
# terminal's mux and never of the node daemon or of an ssh session (remote design, section 0).
# Process launching lives here and in agents/<name>/, never in remote/ (tools/ExecScan.ps1).
#
# THE TERMINAL IS ALWAYS NAMED, NEVER INHERITED (review of PR #96). Every function takes a -Target: one
# terminal, by its mux socket and the identity of the gui that owns it (pid and start time). The one
# call site, Invoke-HordeWeztermAct, sets WEZTERM_UNIX_SOCKET to the target's socket for each call and
# REFUSES a call with no target or an empty socket - it never lets wezterm's own discovery choose,
# which from inside or outside a pane can reach the user's live terminal. A node's use of its own
# terminal is an explicit choice: Resolve-HordeWeztermOwnMux names it, and refuses when it cannot tell
# which one that is. Every call is also `cli --no-auto-start`, so a target that is not answering is
# refused rather than a server started (wezfleet CONTRIBUTING 1).
#
# A PANE IS TIED TO ITS PROCESS BY THE PROCESS'S OWN ENVIRONMENT (review of #96, follow-up). The
# terminal's pane list names no process (measured 2026-10-06, 20240203: window, tab, pane, size, title,
# cwd, cursor, tty_name null), but the terminal sets WEZTERM_PANE=<pane id> in every pane program's
# environment (measured: WEZTERM_PANE=1 in pane 1). So before a pane is ended, or called live, the
# expected process's environment block is read - read-only, PROCESS_QUERY_INFORMATION and
# PROCESS_VM_READ on a process of this user - and its WEZTERM_PANE must be the handle's pane. A valid
# process with another pane's id ends nothing; an environment that cannot be read ends nothing.
#
# EVERY ACT RE-READS THE TERMINAL'S GUI before it acts: running, with the start time the target names.
# A start time that cannot be read is named as such, and nothing is done.
#
# A HANDLE CARRIES ITS TERMINAL'S IDENTITY. A pane id is unique only within one mux's lifetime: after
# the terminal restarts, "17" can name an unrelated pane (review of PR #96, finding 5). So a handle is
# <gui pid>.<gui start ticks>.<pane id>, and every act on a handle first checks that the target is that
# same terminal, still running with that start time. Ending a pane, and calling it live, also takes the
# process the caller expects in it ({ pid; procStart }), and checks that process is alive with that
# start time and descends from that terminal's gui, before anything is done.
#
# ARGUMENTS ARE QUOTED FOR WINDOWS HERE, NOT BY POWERSHELL. PowerShell 5.1 passes a native argument
# with an embedded quote broken, and a first prompt may hold quotes, line breaks and & | ^ %. The
# command line is built by ConvertTo-HordeWindowsCommandLine with the rules CommandLineToArgvW and the
# C runtime read back (test-act.ps1 round-trips every case through a real process), and the program is
# started through ProcessStartInfo. No cmd.exe is ever between Horde and the harness: a program
# installed only as a .cmd or .bat shim is refused.
#
# A PANE GETS THE ENVIRONMENT OF THE PROCESS THAT RUNS `cli spawn` (measured 2026-10-05, issue #95). So
# Start takes an explicit -Environment for the spawned program: a name with a value is set, a name
# mapped to $null removed (a node removes every variable a harness owns). The map NEVER names a
# WEZTERM_* variable: those decide which terminal the call itself reaches, and only the target does
# that (review of PR #96, finding 1). A value holds no NUL and has a length cap.
#
# TYPED TEXT IS ONE LINE OF PRINTABLE TEXT. send-text --no-paste delivers bytes as keystrokes, so a
# control character in a body - CR, ESC, Ctrl-C, Ctrl-D, or a C1 control such as U+009B, a one-character
# CSI - would act in the harness. Send refuses every C0 and C1 control character and DEL, caps the length, passes the text after `--` so a body like --help is
# text and not a flag, and submits only when told to (-Submit), as a separate keystroke.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

$script:HordeWeztermActExe = "wezterm"
# How long one cli call may take. A spawn answered in under a second on this machine (2026-10-05,
# isolated instance, 12 spawns); 20 s is the bound past which the terminal is called not answering.
$script:HordeWeztermActTimeoutMs = 20000
# The longest environment value a spawn may set. Windows caps a whole environment block at 32767
# characters per variable; a value near that is a mistake, and a map that hits the limit on another
# machine would fail there, not here.
$script:HordeWeztermEnvValueMax = 8192
# The longest text typed in one call: a wake notice is one line; a body is delivered by the harness's
# own message channel, never typed (lifecycle step 13).
$script:HordeWeztermSendMax = 1024
$script:HordeWeztermSocketLeaf = '\Agui-sock-([1-9][0-9]{0,9})\z'
$script:HordeWeztermHandlePattern = '\A([1-9][0-9]{0,9})\.([0-9]{1,20})\.([0-9]{1,9})\z'

function ConvertTo-HordeWindowsArgument {
    # One argument quoted so CommandLineToArgvW and the C runtime read it back exactly: quoted when it
    # is empty or holds a space, tab, line break or quote; a quote preceded by its backslashes doubled;
    # backslashes before the closing quote doubled.
    param([AllowEmptyString()][string]$Arg)
    if ($Arg.Length -gt 0 -and $Arg -cnotmatch '[\s"]') { return $Arg }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $slashes = 0
    foreach ($ch in $Arg.ToCharArray()) {
        if ($ch -eq [char]92) { $slashes++; continue }
        if ($ch -eq '"') { [void]$sb.Append(([string][char]92) * ($slashes * 2 + 1)); [void]$sb.Append('"'); $slashes = 0; continue }
        if ($slashes -gt 0) { [void]$sb.Append(([string][char]92) * $slashes); $slashes = 0 }
        [void]$sb.Append($ch)
    }
    if ($slashes -gt 0) { [void]$sb.Append(([string][char]92) * ($slashes * 2)) }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function ConvertTo-HordeWindowsCommandLine {
    # A whole argument list as one command line.
    param([string[]]$Argv)
    return ((@($Argv) | ForEach-Object { ConvertTo-HordeWindowsArgument -Arg ("" + $_) }) -join " ")
}

function Get-HordeWeztermActArgv {
    # The full argv of one cli call: cli --no-auto-start, then the call. The one place it is built.
    param([Parameter(Mandatory = $true)][string[]]$Rest)
    return @("cli", "--no-auto-start") + @($Rest)
}

function Get-HordeWeztermProcessStart {
    # A live process's start time as FILETIME ticks (UTC) in text, or $null when no process has that pid.
    param([Parameter(Mandatory = $true)][long]$ProcessId)
    $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($null -eq $p) { return $null }
    try { return ("" + $p.StartTime.ToUniversalTime().ToFileTimeUtc()) } catch { return $null }
}

function Test-HordeWeztermSameStart {
    # Do two start times, FILETIME ticks as text, name the same instant to the microsecond? MEASURED
    # 2026-10-06 (#96 round 4): the process table (CIM CreationDate) keeps microseconds, Get-Process
    # keeps 100 ns ticks, and one gui read both ways differed by 2 ticks. So every comparison here is
    # at the precision both sources share; anything unreadable is not the same.
    param($A, $B)
    $x = [decimal]0; $y = [decimal]0
    if (-not [decimal]::TryParse("" + $A, [ref]$x) -or -not [decimal]::TryParse("" + $B, [ref]$y)) { return $false }
    return [bool]([decimal]::Floor($x / 10) -eq [decimal]::Floor($y / 10))
}

# Reads another process's environment block: the PEB's process parameters, then the block they point
# at. 64-bit only; a process this user may open for query and read. Compiled once per process.
$script:HordeWeztermProcEnvSource = @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class HordeWeztermProcEnv {
    [StructLayout(LayoutKind.Sequential)]
    struct PBI { public IntPtr R1; public IntPtr Peb; public IntPtr R2a; public IntPtr R2b; public IntPtr Pid; public IntPtr R3; }
    [DllImport("ntdll.dll")] static extern int NtQueryInformationProcess(IntPtr h, int cls, ref PBI pbi, int len, out int ret);
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenProcess(int access, bool inherit, int pid);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    static IntPtr ReadPtr(IntPtr h, IntPtr a) {
        byte[] b = new byte[8]; IntPtr rd;
        if (!ReadProcessMemory(h, a, b, (IntPtr)8, out rd)) { throw new InvalidOperationException("read"); }
        return (IntPtr)BitConverter.ToInt64(b, 0);
    }
    public static string Read(int pid) {
        if (IntPtr.Size != 8) { return null; }
        IntPtr h = OpenProcess(0x0410, false, pid);
        if (h == IntPtr.Zero) { return null; }
        try {
            PBI pbi = new PBI(); int ret;
            if (NtQueryInformationProcess(h, 0, ref pbi, Marshal.SizeOf(typeof(PBI)), out ret) != 0) { return null; }
            IntPtr pp = ReadPtr(h, IntPtr.Add(pbi.Peb, 0x20));
            IntPtr env = ReadPtr(h, IntPtr.Add(pp, 0x80));
            long size = (long)ReadPtr(h, IntPtr.Add(pp, 0x3F0));
            if (size <= 0 || size > (1 << 22)) { size = 65536; }
            byte[] buf = new byte[size]; IntPtr rd;
            if (!ReadProcessMemory(h, env, buf, (IntPtr)size, out rd)) { return null; }
            return Encoding.Unicode.GetString(buf, 0, (int)rd);
        } catch { return null; }
        finally { CloseHandle(h); }
    }
}
'@

function Get-HordeWeztermProcessPane {
    # The pane id a process says it runs in - WEZTERM_PANE in its own environment block - as an answer:
    # known id text, or unknown naming why it could not be read.
    param([Parameter(Mandatory = $true)][long]$ProcessId)
    if (-not ([System.Management.Automation.PSTypeName]"HordeWeztermProcEnv").Type) { Add-Type -TypeDefinition $script:HordeWeztermProcEnvSource }
    $block = [HordeWeztermProcEnv]::Read([int]$ProcessId)
    if ($null -eq $block) { return (New-HordeUnknown -Reason ("the environment of process " + $ProcessId + " could not be read, so which pane it runs in cannot be told")) }
    foreach ($kv in $block.Split([char]0)) {
        if ($kv.StartsWith("WEZTERM_PANE=", [System.StringComparison]::OrdinalIgnoreCase)) {
            $v = $kv.Substring(13)
            if ($v -cmatch '\A[0-9]{1,9}\z') { return (New-HordeKnown -Value $v) }
            return (New-HordeUnknown -Reason ("process " + $ProcessId + " names its pane '" + $v + "', which is not a pane id"))
        }
    }
    return (New-HordeUnknown -Reason ("process " + $ProcessId + " has no WEZTERM_PANE in its environment, so it is in no pane this terminal can name"))
}

# The reason a Stop or a Live gives when the expected process is proven - alive with its start time,
# descended from the terminal's gui - but its own WEZTERM_PANE names another pane. A session can set
# that variable itself (measured by the review of #99: pane 5 set to 999 read back 999), so a caller
# matches this name to escalate to ending the proven process itself (follow-up issue), rather than
# trusting the refusal or calling the session gone.
$script:HordeWeztermPaneClaimMismatch = "pane-claim-mismatch"

function Test-HordeWeztermPaneTie {
    # Is the expected process in pane -Pane? Known true or false from its own WEZTERM_PANE; unknown
    # when that cannot be read. -PaneOf replaces the reader in a test.
    param([Parameter(Mandatory = $true)]$Expect, [Parameter(Mandatory = $true)][string]$Pane, [scriptblock]$PaneOf = $null)
    $p = $null
    if ($null -ne $PaneOf) { $p = & $PaneOf ([long]$Expect.pid) } else { $p = Get-HordeWeztermProcessPane -ProcessId ([long]$Expect.pid) }
    if ($null -eq $p -or $p.state -ne "known") { return (New-HordeUnknown -Reason $(if ($null -ne $p) { $p.reason } else { "the pane of the expected process could not be read" })) }
    return (New-HordeKnown -Value ([bool]("" + $p.value -ceq $Pane)))
}

function Test-HordeWeztermGuiAlive {
    # $null when -Target's gui is running with the start time the target names; otherwise the reason,
    # naming whether the start time could not be read or differs.
    param([Parameter(Mandatory = $true)]$Target, [scriptblock]$ProcessStart = $null)
    $now = $null
    if ($null -ne $ProcessStart) { $now = & $ProcessStart ([long]$Target.guiPid) } else { $now = Get-HordeWeztermProcessStart -ProcessId ([long]$Target.guiPid) }
    if ($null -eq $now) { return ("the start time of the terminal's gui " + $Target.guiPid + " could not be read: it is not running, or cannot be asked; nothing is done") }
    if (-not (Test-HordeWeztermSameStart $now $Target.guiStart)) { return ("the terminal's gui " + $Target.guiPid + " now has another start time: it is another terminal than the one named; nothing is done") }
    return $null
}

function Test-HordeWeztermTargetShape {
    # Is -Target a named terminal: { socket; guiPid; guiStart }, the socket absolute and named after its
    # gui? $null when it is, or the reason.
    param($Target)
    if ($null -eq $Target) { return "no terminal was named: a call is never sent to whatever terminal the environment points at" }
    $sock = "" + $Target.socket
    if ($sock.Trim() -eq "") { return "the named terminal has no socket: an empty pin would let the call reach the user's live terminal" }
    if (-not [System.IO.Path]::IsPathRooted($sock)) { return ("the terminal's socket '" + $sock + "' is not an absolute path") }
    $m = [regex]::Match((Split-Path -Leaf $sock), $script:HordeWeztermSocketLeaf)
    if (-not $m.Success) { return ("the terminal's socket '" + $sock + "' is not named after a gui (gui-sock-<pid>)") }
    if ("" + $Target.guiPid -cne $m.Groups[1].Value) { return ("the socket names gui " + $m.Groups[1].Value + ", the target gui " + $Target.guiPid) }
    if ("" + $Target.guiStart -cnotmatch '\A[0-9]{1,20}\z') { return "the named terminal gives no start time for its gui" }
    return $null
}

function New-HordeWeztermTarget {
    # A named terminal from its socket path, as an answer: its gui must be running now, and its start
    # time is read and kept, so a later restart of the terminal is seen as another terminal.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Socket, [scriptblock]$ProcessStart = $null)
    if ($Socket.Trim() -eq "" -or -not [System.IO.Path]::IsPathRooted($Socket)) { return (New-HordeUnknown -Reason ("'" + $Socket + "' is not a terminal's socket path")) }
    $m = [regex]::Match((Split-Path -Leaf $Socket), $script:HordeWeztermSocketLeaf)
    if (-not $m.Success) { return (New-HordeUnknown -Reason ("'" + $Socket + "' is not named after a gui (gui-sock-<pid>)")) }
    $gp = [long]$m.Groups[1].Value
    $start = $null
    if ($null -ne $ProcessStart) { $start = & $ProcessStart $gp } else { $start = Get-HordeWeztermProcessStart -ProcessId $gp }
    if ($null -eq $start) { return (New-HordeUnknown -Reason ("the gui " + $gp + " of " + $Socket + " is not running")) }
    return (New-HordeKnown -Value ([pscustomobject]@{ socket = $Socket; guiPid = $gp; guiStart = "" + $start }))
}

function Get-HordeWeztermSockDir {
    # Where a profile's terminals keep their sockets: the user's own profile unless another is given.
    param([string]$ProfileDir = $env:USERPROFILE)
    return (Join-Path $ProfileDir ".local\share\wezterm")
}

function Resolve-HordeWeztermOwnMux {
    # THIS NODE'S OWN TERMINAL, named explicitly for a node that acts in it: the one gui of this user
    # with a socket in the terminal's socket folder. None, or more than one (an isolated test instance
    # beside the user's own counts), is refused: which one is meant cannot be told.
    param([string]$SockDir = (Get-HordeWeztermSockDir), [scriptblock]$Guis = $null, [scriptblock]$ProcessStart = $null)
    $pids = @()
    if ($null -ne $Guis) { $pids = @(& $Guis) } else { $pids = @(Get-Process -Name "wezterm-gui" -ErrorAction SilentlyContinue | ForEach-Object { [long]$_.Id }) }
    $socks = @($pids | ForEach-Object { Join-Path $SockDir ("gui-sock-" + $_) } | Where-Object { Test-Path -LiteralPath $_ })
    if ($socks.Count -eq 0) { return (New-HordeUnknown -Reason "no terminal of this user is running with a socket, so this node has no terminal to act in") }
    if ($socks.Count -gt 1) { return (New-HordeUnknown -Reason ("" + $socks.Count + " terminals are running (" + ($socks -join ", ") + "); which one is this node's own cannot be told, so none is chosen")) }
    return (New-HordeWeztermTarget -Socket $socks[0] -ProcessStart $ProcessStart)
}

function ConvertTo-HordeWeztermHandle {
    # The handle of pane -Pane in -Target: <gui pid>.<gui start ticks>.<pane id>.
    param([Parameter(Mandatory = $true)]$Target, [Parameter(Mandatory = $true)][string]$Pane)
    return ("" + $Target.guiPid + "." + $Target.guiStart + "." + $Pane)
}

function Resolve-HordeWeztermHandle {
    # A handle checked against -Target: known pane id when the handle was made in this same terminal,
    # still running with the same start time; unknown otherwise, with the reason.
    param([Parameter(Mandatory = $true)]$Target, [AllowEmptyString()][string]$Handle, [scriptblock]$ProcessStart = $null)
    $bad = Test-HordeWeztermTargetShape -Target $Target
    if ($null -ne $bad) { return (New-HordeUnknown -Reason $bad) }
    $m = [regex]::Match($Handle, $script:HordeWeztermHandlePattern)
    if (-not $m.Success) { return (New-HordeUnknown -Reason ("'" + $Handle + "' is not a pane handle (<gui pid>.<gui start>.<pane>)")) }
    if ($m.Groups[1].Value -cne "" + $Target.guiPid -or $m.Groups[2].Value -cne "" + $Target.guiStart) { return (New-HordeUnknown -Reason ("the handle " + $Handle + " belongs to another terminal than the one named (gui " + $Target.guiPid + " started " + $Target.guiStart + ")")) }
    $gone = Test-HordeWeztermGuiAlive -Target $Target -ProcessStart $ProcessStart
    if ($null -ne $gone) { return (New-HordeUnknown -Reason ("handle " + $Handle + ": " + $gone + "; a pane id of another terminal is never acted on")) }
    return (New-HordeKnown -Value $m.Groups[3].Value)
}

function Set-HordeWeztermActEnvironment {
    # Apply -Environment to one ProcessStartInfo: a name with a value is set, a name with $null removed.
    # Refused before the call is made: a name that is not a variable name, any WEZTERM_* name (only the
    # target decides which terminal is reached), a value holding NUL, a value past the cap.
    param([Parameter(Mandatory = $true)][System.Diagnostics.ProcessStartInfo]$Psi, [hashtable]$Environment = @{})
    foreach ($k in @($Environment.Keys)) {
        if ("" + $k -cnotmatch '\A[A-Za-z_][A-Za-z0-9_]{0,127}\z') { throw ("'" + $k + "' is not an environment variable name") }
        if (("" + $k).StartsWith("WEZTERM_", [System.StringComparison]::OrdinalIgnoreCase)) { throw ("'" + $k + "' decides which terminal is called; only the named target sets it, never an environment map") }
        $v = $Environment[$k]
        if ($null -ne $v) {
            if (("" + $v).Contains([string][char]0)) { throw ("the value of " + $k + " holds a NUL, which Windows would silently cut") }
            if (("" + $v).Length -gt $script:HordeWeztermEnvValueMax) { throw ("the value of " + $k + " is " + ("" + $v).Length + " characters, over the cap of " + $script:HordeWeztermEnvValueMax) }
        }
    }
    foreach ($k in @($Environment.Keys)) {
        if ($null -eq $Environment[$k]) { if ($Psi.EnvironmentVariables.ContainsKey($k)) { $Psi.EnvironmentVariables.Remove($k) } }
        else { $Psi.EnvironmentVariables[$k] = "" + $Environment[$k] }
    }
}

function Invoke-HordeWeztermAct {
    # Run one cli call against -Target. Returns { code; out; err; timedOut }. REFUSED, with no process
    # started, when no terminal is named (see the header). -Environment changes the call's environment,
    # which a spawned pane inherits; then the target's socket is set last, so nothing overrides it.
    param([Parameter(Mandatory = $true)][string[]]$Rest, $Target, [int]$TimeoutMs = $script:HordeWeztermActTimeoutMs, [hashtable]$Environment = @{})
    $bad = Test-HordeWeztermTargetShape -Target $Target
    if ($null -ne $bad) { return [pscustomobject]@{ code = -1; out = ""; err = ("refused: " + $bad); timedOut = $false } }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:HordeWeztermActExe
    $psi.Arguments = ConvertTo-HordeWindowsCommandLine -Argv (Get-HordeWeztermActArgv -Rest $Rest)
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    try { Set-HordeWeztermActEnvironment -Psi $psi -Environment $Environment } catch { return [pscustomobject]@{ code = -1; out = ""; err = ("refused: " + $_.Exception.Message); timedOut = $false } }
    $psi.EnvironmentVariables["WEZTERM_UNIX_SOCKET"] = "" + $Target.socket
    $p = $null
    try { $p = [System.Diagnostics.Process]::Start($psi) } catch { return [pscustomobject]@{ code = -1; out = ""; err = ("the terminal's command could not be started: " + $_.Exception.Message); timedOut = $false } }
    try {
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutMs)) {
            try { $p.Kill() } catch { }
            return [pscustomobject]@{ code = -1; out = ""; err = ("the terminal did not answer within " + $TimeoutMs + " ms"); timedOut = $true }
        }
        $p.WaitForExit()
        return [pscustomobject]@{ code = $p.ExitCode; out = $outTask.Result; err = $errTask.Result; timedOut = $false }
    } finally { $p.Dispose() }
}

function Resolve-HordeWeztermProgram {
    # A program's full path from its command name, as an answer: the first .exe on PATH with that
    # name. A name found only as a script shim is refused (see the header: no cmd.exe in between).
    param([Parameter(Mandatory = $true)][string]$Name, $Lookup = $null)
    if ($Name -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z') { return (New-HordeUnknown -Reason ("'" + $Name + "' is not a command name")) }
    $found = $null
    if ($null -ne $Lookup) { $found = @(& $Lookup $Name) }
    else { $found = @(Get-Command -Name $Name -CommandType Application -All -ErrorAction SilentlyContinue | ForEach-Object { "" + $_.Source }) }
    $exe = @($found | Where-Object { [System.IO.Path]::GetExtension("" + $_) -ieq ".exe" })
    if ($exe.Count -ge 1) { return (New-HordeKnown -Value ("" + $exe[0])) }
    if ($found.Count -ge 1) { return (New-HordeUnknown -Reason ("'" + $Name + "' is installed here only as " + (Split-Path -Leaf ("" + $found[0])) + ", a script shim; Horde starts no harness through cmd.exe, which would read a prompt's & | ^ % as its own syntax. Install the harness's native executable")) }
    return (New-HordeUnknown -Reason ("'" + $Name + "' is not on this node's PATH"))
}

function Get-HordeWeztermSpawnArgv {
    # The cli call that starts -Program with -Argv in a new pane: spawn, where, then -- and the program.
    # -WindowId puts it in a tab of that window; without one it gets a window of its own (a node runs
    # outside any pane, so there is no current pane to place it beside).
    param([Parameter(Mandatory = $true)][string]$Program, [string[]]$Argv = @(), [Parameter(Mandatory = $true)][string]$Cwd, [string]$WindowId = "")
    $rest = @("spawn")
    if ($WindowId -ne "") { $rest += @("--window-id", $WindowId) } else { $rest += @("--new-window") }
    $rest += @("--cwd", $Cwd, "--", $Program) + @($Argv)
    return $rest
}

function Invoke-HordeWeztermCall {
    # One call through the runner a test injects, or the real one.
    param([Parameter(Mandatory = $true)][string[]]$Rest, $Target, [hashtable]$Environment = @{}, [scriptblock]$Runner = $null)
    if ($null -ne $Runner) { return (& $Runner $Rest $Environment $Target) }
    return (Invoke-HordeWeztermAct -Rest $Rest -Target $Target -Environment $Environment)
}

function Start-HordeWeztermPane {
    # Start -Program (a full path to an .exe, from Resolve-HordeWeztermProgram) with -Argv in a new pane
    # of -Target, in the folder -Cwd, with -Environment applied to the spawn. Returns an answer: known
    # { handle; program; cwd }, the handle carrying the terminal's identity; unknown with the reason.
    param($Target, [Parameter(Mandatory = $true)][string]$Program, [string[]]$Argv = @(), [Parameter(Mandatory = $true)][string]$Cwd,
        [string]$WindowId = "", [hashtable]$Environment = @{}, [scriptblock]$Runner = $null, [scriptblock]$ProcessStart = $null)
    $bad = Test-HordeWeztermTargetShape -Target $Target
    if ($null -ne $bad) { return (New-HordeUnknown -Reason $bad) }
    $gone = Test-HordeWeztermGuiAlive -Target $Target -ProcessStart $ProcessStart
    if ($null -ne $gone) { return (New-HordeUnknown -Reason $gone) }
    if (-not [System.IO.Path]::IsPathRooted($Program) -or [System.IO.Path]::GetExtension($Program) -ine ".exe") { return (New-HordeUnknown -Reason ("the program must be a full path to an .exe, not '" + $Program + "'")) }
    if (-not [System.IO.Path]::IsPathRooted($Cwd)) { return (New-HordeUnknown -Reason ("the working folder must be absolute, not '" + $Cwd + "'")) }
    if ($WindowId -ne "" -and $WindowId -cnotmatch '\A[0-9]{1,9}\z') { return (New-HordeUnknown -Reason ("'" + $WindowId + "' is not a window id")) }
    $rest = Get-HordeWeztermSpawnArgv -Program $Program -Argv $Argv -Cwd $Cwd -WindowId $WindowId
    $r = Invoke-HordeWeztermCall -Rest $rest -Target $Target -Environment $Environment -Runner $Runner
    if ($r.code -ne 0) { return (New-HordeUnknown -Reason ("the terminal did not start the pane (exit " + $r.code + "): " + ("" + $r.err).Trim())) }
    $id = ("" + $r.out).Trim()
    if ($id -cnotmatch '\A[0-9]{1,9}\z') { return (New-HordeUnknown -Reason ("the terminal answered the spawn with '" + $id + "', not a pane id; whether a pane started is unknown")) }
    return (New-HordeKnown -Value ([pscustomobject]@{ handle = (ConvertTo-HordeWeztermHandle -Target $Target -Pane $id); program = $Program; cwd = $Cwd }))
}

function Test-HordeWeztermSendText {
    # $null when -Text may be typed: printable, at most the cap; otherwise the reason.
    param([AllowEmptyString()][string]$Text)
    if ($Text -cmatch '[\x00-\x1F\x7F-\x9F]') { return "the text holds a control character (a line break, Escape, Ctrl-C or the like), which would act as a key in the harness; only printable text is typed, and Enter only by -Submit" }
    if ($Text.Length -gt $script:HordeWeztermSendMax) { return ("the text is " + $Text.Length + " characters, over the cap of " + $script:HordeWeztermSendMax + "; a body goes by the harness's own message channel, never typed") }
    return $null
}

function Send-HordeWeztermText {
    # Type -Text into the pane -Handle of -Target, as keystrokes (--no-paste), after `--` so it is never
    # read as a flag; then, with -Submit, press Enter as a keystroke of its own. Known $true when the
    # terminal took all of it; unknown otherwise.
    param($Target, [Parameter(Mandatory = $true)][string]$Handle, [AllowEmptyString()][string]$Text = "", [switch]$Submit, [scriptblock]$Runner = $null, [scriptblock]$ProcessStart = $null)
    $why = Test-HordeWeztermSendText -Text $Text
    if ($null -ne $why) { return (New-HordeUnknown -Reason $why) }
    if ($Text -eq "" -and -not $Submit) { return (New-HordeUnknown -Reason "nothing to type: no text and no -Submit") }
    $pane = Resolve-HordeWeztermHandle -Target $Target -Handle $Handle -ProcessStart $ProcessStart
    if ($pane.state -ne "known") { return $pane }
    if ($Text -ne "") {
        $r = Invoke-HordeWeztermCall -Rest @("send-text", "--pane-id", $pane.value, "--no-paste", "--", $Text) -Target $Target -Runner $Runner
        if ($r.code -ne 0) { return (New-HordeUnknown -Reason ("the terminal did not take the text (exit " + $r.code + "): " + ("" + $r.err).Trim())) }
    }
    if ($Submit) {
        $r = Invoke-HordeWeztermCall -Rest @("send-text", "--pane-id", $pane.value, "--no-paste", "--", "`r") -Target $Target -Runner $Runner
        if ($r.code -ne 0) { return (New-HordeUnknown -Reason ("the terminal did not take Enter (exit " + $r.code + "): " + ("" + $r.err).Trim())) }
    }
    return (New-HordeKnown -Value $true)
}

function Read-HordeWeztermPaneList {
    # The live panes from `cli list --format json` output, as an answer: known list of { pane; window;
    # tab; cwd; title }, or unknown when the output is not a list. Zero panes is a known empty list only
    # when the terminal answered with [] itself.
    param($Raw)
    $joined = ((@($Raw) -join "`n").Trim())
    if ($joined -eq "") { return (New-HordeUnknown -Reason "the terminal's pane list was empty output, which is unknown, not none") }
    $parsed = $null
    try { $parsed = $joined | ConvertFrom-Json } catch { return (New-HordeUnknown -Reason "the terminal's pane list is not JSON") }
    if ($joined -ceq "[]") { return (New-HordeKnown -Value @()) }
    $rows = New-Object System.Collections.ArrayList
    foreach ($p in @($parsed)) {
        if ($null -eq $p -or $null -eq $p.PSObject.Properties["pane_id"]) { return (New-HordeUnknown -Reason "a pane in the terminal's list has no pane_id") }
        [void]$rows.Add([pscustomobject]@{ pane = ("" + $p.pane_id); window = ("" + $p.window_id); tab = ("" + $p.tab_id); cwd = ("" + $p.cwd); title = ("" + $p.title) })
    }
    return (New-HordeKnown -Value $rows.ToArray())
}

function Get-HordeWeztermProcessTable {
    # Every process: { pid; ppid; start } with start as FILETIME ticks text.
    return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | ForEach-Object {
        $st = ""
        if ($null -ne $_.CreationDate) { $st = "" + $_.CreationDate.ToUniversalTime().ToFileTimeUtc() }
        [pscustomobject]@{ pid = [long]$_.ProcessId; ppid = [long]$_.ParentProcessId; start = $st } })
}

function Test-HordeWeztermProcessInTerminal {
    # Is the process { pid; procStart } alive with that start time, and a descendant of -Target's gui?
    # Known true or false, or unknown when it cannot be told. A parent is believed only when it started
    # before its child: Windows keeps a dead parent's pid in its children, and the pid may be reused.
    param([Parameter(Mandatory = $true)]$Target, $Expect, [object[]]$Table = $null)
    if ($null -eq $Expect -or "" + $Expect.pid -cnotmatch '\A[1-9][0-9]{0,9}\z' -or "" + $Expect.procStart -cnotmatch '\A[0-9]{1,20}\z') { return (New-HordeUnknown -Reason "no expected process { pid; procStart } was given, so the pane's program cannot be proven") }
    if ($null -eq $Table) { $Table = Get-HordeWeztermProcessTable }
    $byPid = @{}
    foreach ($r in @($Table)) { $byPid[[long]$r.pid] = $r }
    $cur = $byPid[[long]$Expect.pid]
    if ($null -eq $cur -or -not (Test-HordeWeztermSameStart $cur.start $Expect.procStart)) { return (New-HordeKnown -Value $false) }
    for ($hop = 0; $hop -lt 8; $hop++) {
        $par = $byPid[[long]$cur.ppid]
        if ($null -eq $par -or [decimal]("0" + $par.start) -gt [decimal]("0" + $cur.start)) { return (New-HordeUnknown -Reason ("the process " + $Expect.pid + " is not traced to the terminal's gui: its parent chain ends at pid " + $cur.ppid)) }
        if ([long]$par.pid -eq [long]$Target.guiPid -and (Test-HordeWeztermSameStart $par.start $Target.guiStart)) { return (New-HordeKnown -Value $true) }
        $cur = $par
    }
    return (New-HordeUnknown -Reason ("the process " + $Expect.pid + " is not traced to the terminal's gui within 8 parents"))
}

function Test-HordeWeztermPaneLive {
    # Is the pane -Handle of -Target still there, running the expected process? Known true only when
    # the terminal is the same one, lists the pane, and the process is alive with that start time;
    # known false when the process is gone or the pane is not listed; unknown when the terminal cannot
    # say. A pane the terminal could not list is never called gone, and neither is a proven process
    # that names another pane (unknown, pane-claim-mismatch).
    param($Target, [Parameter(Mandatory = $true)][string]$Handle, $Expect, [scriptblock]$Runner = $null, [scriptblock]$ProcessStart = $null, [object[]]$Table = $null, [scriptblock]$PaneOf = $null)
    $pane = Resolve-HordeWeztermHandle -Target $Target -Handle $Handle -ProcessStart $ProcessStart
    if ($pane.state -ne "known") { return $pane }
    $r = Invoke-HordeWeztermCall -Rest @("list", "--format", "json") -Target $Target -Runner $Runner
    if ($r.code -ne 0) { return (New-HordeUnknown -Reason ("the terminal did not list its panes (exit " + $r.code + ")")) }
    $l = Read-HordeWeztermPaneList -Raw $r.out
    if ($l.state -ne "known") { return $l }
    if (@($l.value | Where-Object { $_.pane -ceq $pane.value }).Count -eq 0) { return (New-HordeKnown -Value $false) }
    $in = Test-HordeWeztermProcessInTerminal -Target $Target -Expect $Expect -Table $Table
    if ($in.state -ne "known") { return $in }
    if (-not $in.value) { return (New-HordeKnown -Value $false) }
    $tie = Test-HordeWeztermPaneTie -Expect $Expect -Pane $pane.value -PaneOf $PaneOf
    if ($tie.state -ne "known") { return $tie }
    # A proven, running process that names another pane is never called gone: which pane holds it
    # cannot be told (review of #99, finding 1).
    if (-not $tie.value) { return (New-HordeUnknown -Reason ($script:HordeWeztermPaneClaimMismatch + ": the expected process runs in this terminal but names another pane than " + $pane.value + ", so whether this pane still holds it cannot be told")) }
    return (New-HordeKnown -Value $true)
}

function Stop-HordeWeztermPane {
    # End the pane -Handle of -Target and whatever runs in it: the forced end, for a session that must
    # not run or that ignored a graceful close. Done only when all of these hold, and otherwise refused
    # with nothing ended: the terminal is the same one, still running with its start time; the expected
    # process is alive with its start time and descends from that terminal's gui; that process's own
    # WEZTERM_PANE is the handle's pane; and the terminal lists that pane.
    param($Target, [Parameter(Mandatory = $true)][string]$Handle, $Expect, [scriptblock]$Runner = $null, [scriptblock]$ProcessStart = $null, [object[]]$Table = $null, [scriptblock]$PaneOf = $null)
    $pane = Resolve-HordeWeztermHandle -Target $Target -Handle $Handle -ProcessStart $ProcessStart
    if ($pane.state -ne "known") { return $pane }
    $in = Test-HordeWeztermProcessInTerminal -Target $Target -Expect $Expect -Table $Table
    if ($in.state -ne "known") { return (New-HordeUnknown -Reason ("nothing was ended: " + $in.reason)) }
    if (-not $in.value) { return (New-HordeUnknown -Reason "nothing was ended: the expected process is not running with its start time") }
    $tie = Test-HordeWeztermPaneTie -Expect $Expect -Pane $pane.value -PaneOf $PaneOf
    if ($tie.state -ne "known") { return (New-HordeUnknown -Reason ("nothing was ended: " + $tie.reason)) }
    if (-not $tie.value) { return (New-HordeUnknown -Reason ($script:HordeWeztermPaneClaimMismatch + ": nothing was ended: the expected process runs in another pane than " + $pane.value)) }
    $lr = Invoke-HordeWeztermCall -Rest @("list", "--format", "json") -Target $Target -Runner $Runner
    $listed = $null
    if ($lr.code -eq 0) { $listed = Read-HordeWeztermPaneList -Raw $lr.out }
    if ($null -eq $listed -or $listed.state -ne "known") { return (New-HordeUnknown -Reason "nothing was ended: the terminal did not list its panes") }
    if (@($listed.value | Where-Object { $_.pane -ceq $pane.value }).Count -eq 0) { return (New-HordeUnknown -Reason ("nothing was ended: the terminal lists no pane " + $pane.value)) }
    $r = Invoke-HordeWeztermCall -Rest @("kill-pane", "--pane-id", $pane.value) -Target $Target -Runner $Runner
    if ($r.code -ne 0) { return (New-HordeUnknown -Reason ("the terminal did not end the pane (exit " + $r.code + "): " + ("" + $r.err).Trim())) }
    return (New-HordeKnown -Value $true)
}

function Test-HordeWeztermProfileDir {
    # "" when -Path may stand for a profile folder, else why not: a full path on a fixed or removable
    # local drive (never a share, nor a drive letter mapped to one, which Test-Path would reach over the
    # network), already in full form (no '..'), and with no junction or link on any folder that exists
    # from the drive down to the socket folder inside it (review of #108; issue #119: a junction at the
    # profile's .local was adopted, and a mapped network drive passed). -DriveType stands in for the
    # drive's type in a test: root -> type name. -ItemOf stands in for Get-Item in a test: path -> item.
    # A folder that exists but cannot be read is refused: whether it is a junction cannot be told.
    param([AllowEmptyString()][string]$Path, [scriptblock]$DriveType = $null, [scriptblock]$ItemOf = $null)
    if ($Path -cnotmatch '\A[A-Za-z]:\\') { return ("the profile folder '" + $Path + "' is not a full path on a local drive") }
    $driveRoot = $Path.Substring(0, 3)
    $kind = ""
    try { if ($null -ne $DriveType) { $kind = "" + (& $DriveType $driveRoot) } else { $kind = "" + (New-Object System.IO.DriveInfo($driveRoot)).DriveType } } catch { $kind = "" }
    if (@("Fixed", "Removable") -cnotcontains $kind) { return ("the profile folder '" + $Path + "' is on drive " + $driveRoot + " of type '" + $kind + "'; only a fixed or removable local drive may stand for a profile") }
    $full = $null
    try { $full = [System.IO.Path]::GetFullPath($Path) } catch { return ("the profile folder '" + $Path + "' is not a path") }
    if ($full.TrimEnd('\') -cne $Path.TrimEnd('\')) { return ("the profile folder '" + $Path + "' is not in full form (it reads as " + $full + ")") }
    $p = (Get-HordeWeztermSockDir -ProfileDir $full.TrimEnd('\')).TrimEnd('\')
    while ($p.Length -gt 3) {
        if (Test-Path -LiteralPath $p) {
            $it = $null
            try { if ($null -ne $ItemOf) { $it = & $ItemOf $p } else { $it = Get-Item -LiteralPath $p -Force -ErrorAction Stop } } catch { $it = $null }
            if ($null -eq $it) { return ("the profile folder '" + $Path + "' passes through " + $p + ", which cannot be read, so whether it is a junction or link cannot be told") }
            if (($it.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return ("the profile folder '" + $Path + "' passes through " + $p + ", a junction or link") }
        }
        $p = Split-Path -Parent $p
    }
    return ""
}

function Test-HordeWeztermRunningList {
    # "" when -Running is a list of { pid; start } with a numeric pid and a start time of digits, else
    # why not (review of #108: a pid of 'abc' made Own throw where the port says it answers).
    param($Running)
    if ($Running -is [System.Collections.IDictionary]) { return "the running terminals are a table, not a list of { pid; start }" }
    foreach ($e in @($Running)) {
        if ($null -eq $e -or $e -is [System.Collections.IDictionary] -or $null -eq $e.PSObject.Properties["pid"] -or $null -eq $e.PSObject.Properties["start"]) { return "a running terminal is not a { pid; start }" }
        if (("" + $e.pid) -cnotmatch '\A[0-9]{1,10}\z') { return ("a running terminal's pid '" + $e.pid + "' is not a number") }
        if (("" + $e.start) -cnotmatch '\A[0-9]{1,20}\z') { return ("a running terminal's start '" + $e.start + "' is not a time in digits") }
    }
    return ""
}

function Get-HordeWeztermOwnMarker {
    # The port's OwnMarker: the socket file whose presence makes terminal -GuiPid -ProfileDir's own, or
    # $null when the pid is not a number or the folder may not stand for a profile (review of #108).
    param([AllowEmptyString()][string]$ProfileDir, $GuiPid)
    if (("" + $GuiPid) -cnotmatch '\A[0-9]{1,10}\z') { return $null }
    if ((Test-HordeWeztermProfileDir -Path $ProfileDir) -ne "") { return $null }
    return (Join-Path (Get-HordeWeztermSockDir -ProfileDir $ProfileDir) ("gui-sock-" + $GuiPid))
}

function Invoke-HordeWeztermOwn {
    # The port's Own (core/HostAct.ps1). With no arguments, as a node calls it: this user's terminals now,
    # in %USERPROFILE%\.local\share\wezterm. Given a profile folder, the sockets under it; given running
    # terminals ({ pid; start } each), those in place of the processes listed now - the isolation probe's
    # control, which plants one and must find it (test-hub-act-local, 2026-10-06). Either given argument
    # that cannot mean what it says is answered unknown, never a throw. -Guis and -ProcessStart stand in
    # for the process table in a test of the no-argument path; the port never passes them.
    param([string]$ProfileDir = "", $Running = $null, [scriptblock]$Guis = $null, [scriptblock]$ProcessStart = $null)
    $pd = $ProfileDir
    if ($pd -ne "") { $why = Test-HordeWeztermProfileDir -Path $pd; if ($why -ne "") { return (New-HordeUnknown -Reason $why) } }
    if ($pd -eq "") {
        # The node's own path gets the same checks (review of #131): its own profile, on a local drive,
        # with no junction or link from the drive down to its socket folder.
        $pd = "" + $env:USERPROFILE
        $why = Test-HordeWeztermProfileDir -Path $pd
        if ($why -ne "") { return (New-HordeUnknown -Reason ("this user's profile cannot be trusted for its terminals: " + $why)) }
    }
    $sd = Get-HordeWeztermSockDir -ProfileDir $pd
    if ($null -eq $Running) { return (Resolve-HordeWeztermOwnMux -SockDir $sd -Guis $Guis -ProcessStart $ProcessStart) }
    $why = Test-HordeWeztermRunningList -Running $Running
    if ($why -ne "") { return (New-HordeUnknown -Reason $why) }
    $list = @($Running)
    $guis = { @($list | ForEach-Object { [long]$_.pid }) }.GetNewClosure()
    $starts = { param($p) $hit = @($list | Where-Object { [long]$_.pid -eq [long]$p }); if ($hit.Count -eq 1) { "" + $hit[0].start } else { $null } }.GetNewClosure()
    return (Resolve-HordeWeztermOwnMux -SockDir $sd -Guis $guis -ProcessStart $starts)
}

# THE PORT (core/HostAct.ps1). A node reaches these functions only through it, so nothing outside
# hosts/wezterm/ names the terminal (CONTRIBUTING 14). Own names this node's own terminal explicitly.
Register-HordeHostActor -Name "wezterm" `
    -Own { param($profileDir, $running) Invoke-HordeWeztermOwn -ProfileDir $profileDir -Running $running } `
    -OwnMarker { param($profileDir, $guiPid) Get-HordeWeztermOwnMarker -ProfileDir $profileDir -GuiPid $guiPid } `
    -Resolve { param($n) Resolve-HordeWeztermProgram -Name $n } `
    -Start { param($target, $prog, $argv, $cwd, $envMap) if ($null -eq $envMap) { $envMap = @{} }; Start-HordeWeztermPane -Target $target -Program $prog -Argv $argv -Cwd $cwd -Environment $envMap } `
    -Send { param($target, $h, $t, $submit) Send-HordeWeztermText -Target $target -Handle $h -Text $t -Submit:([bool]$submit) } `
    -Live { param($target, $h, $expect) Test-HordeWeztermPaneLive -Target $target -Handle $h -Expect $expect } `
    -Stop { param($target, $h, $expect) Stop-HordeWeztermPane -Target $target -Handle $h -Expect $expect }
