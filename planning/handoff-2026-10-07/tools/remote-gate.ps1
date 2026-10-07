# remote-gate.ps1 - run test suites of one exact commit on the always-on box over SSH.
#
# WHY: this box is low on RAM; the always-on box (DESKTOP-TJQJGTM, 13 GB) is not. Founder authorized
# running checks there on 2026-09-30 and 2026-10-01.
#
# HOW, and why each part is shaped the way it is:
#   - CODE TRAVELS AS A GIT BUNDLE of the exact commit, made here and copied over with scp. The remote
#     box's GitHub credentials are never used. The bundle is cut from a throwaway bare repository in
#     the local run folder, so no ref is ever created in the repository being tested.
#   - EVERYTHING REMOTE LIVES UNDER ONE ROOT, C:\Users\yagdil\horde-ci\runs\<label>\<run id>. Old runs are
#     pruned to the newest -Keep WITHIN THE SAME LABEL only: a run never deletes another label's folders
#     (2026-10-01, after a keep-last-10 over the shared root deleted other agents' finished runs). Suites run with
#     TEMP, TMP, USERPROFILE, HOME, APPDATA and LOCALAPPDATA pointed inside the run folder, so they cannot write into the
#     remote user's real profile (~/.claude, ~/.codex, ssh keys, git credentials). -RealProfile opts out.
#   - THE REMOTE JOB IS DETACHED. It is created with WMI (Win32_Process.Create), which starts it outside
#     the job object Windows OpenSSH puts a session's processes in; a process started any other way
#     from an ssh session dies when the session drops. It writes only to files, and a status.json the
#     local side reads with short, separate ssh calls. So a dropped connection or a killed local side
#     loses nothing: run this script again with -Attach <run id> and it waits and collects.
#   - NOTHING IS STREAMED. At the end one log per suite, the remote summary and the status file are
#     copied back, and the verdict is decided HERE from those files, not taken from the remote's word.
#   - A RUN IS GREEN ONLY IF IT SAYS SO TO THE END. Every suite log must end in DONE=<code> and carry a
#     verdict line, and the remote summary must end with "REMOTE-GATE <label> complete". Anything
#     missing is NOT RUN (exit 3), never green.
#   - ONLY PROCESSES THIS TOOL STARTED ARE KILLED: a timed-out suite's tree, found by parent pid and
#     checked against creation time so a reused pid is never hit.
#   - WEZTERM IS CONTAINED PER RUN (v2, 2026-10-01). Measured on the box: a suite's `wezterm cli` calls
#     auto-started a mux server on the box's REAL socket that outlived the run, and wrote logs into the
#     real ~/.local/share/wezterm. WezTerm finds that folder through the Windows profile API, so the
#     USERPROFILE/HOME redirect does nothing for it (measured: APPDATA, LOCALAPPDATA, XDG_RUNTIME_DIR,
#     XDG_DATA_HOME, WEZTERM_RUNTIME_DIR, WEZTERM_LOG_DIR and --skip-config all leave the log where it
#     was). What does work, each measured: WEZTERM_LOG=off (no log file is created at all), `cli
#     --no-auto-start` (no mux), and WEZTERM_CONFIG_FILE (a mux that does start binds the socket the
#     config names; its no_serve_automatically did NOT stop the auto-start, measured). So every suite
#     runs with:
#       * a shim wezterm.exe (also as wezterm-gui.exe and wezterm-mux-server.exe) first on PATH. An exe,
#         not a .cmd: horde and wezfleet start "wezterm" through ProcessStartInfo, and CreateProcess only
#         appends .exe. It adds --no-auto-start to every cli call, refuses a cli call aimed at the real
#         socket, and refuses anything that starts a GUI or a mux unless the suite is in -AllowWezterm
#         (then only `start`/gui, with --skip-config forced). Source: rg-shim\WeztermShim.cs.
#       * WEZTERM_UNIX_SOCKET and WEZTERM_CONFIG_FILE inside the run folder, and WEZTERM_LOG=off.
#       * a per-suite marker variable RG_MARK_<guid>, inherited by everything the suite starts.
#     After each suite a sweep finds every wezterm* process born during it, reads its environment block
#     (the technique of wezfleet PR #59), and kills - by pid and creation time - only those carrying the
#     marker: LEAK, and the suite fails. A process without the marker is FOREIGN and left alone; one
#     whose environment cannot be read is UNATTRIBUTED, left alone, and fails the suite. The real WezTerm
#     folder is diffed around each suite; any change is REALDIR and fails the suite, and a new file named
#     by a pid proven to be the run's (a log or a gui-sock) is removed again.
#
# Remote PowerShell is 5.1 and quoting through ssh is fragile, so every remote command is sent as
# powershell -EncodedCommand (UTF-16LE base64), with $ProgressPreference silenced (it otherwise
# emits CLIXML progress records on stderr) and any leftover "#< CLIXML" block stripped.
#
# Usage (run it inside ONE tracked background job; it waits, it does not stream):
#   powershell -NoProfile -File remote-gate.ps1 -Repo C:\Users\yedid\bin\horde -Commit 77725b2 `
#       -Suites test\test-cli.ps1,test\test-ledger.ps1 -Label cli `
#       -Companion @{ wezfleet = 'C:\Users\yedid\bin\wezfleet@main' } `
#       -Env @{ HORDE_WEZFLEET_REPO = '{companion:wezfleet}' }
#   powershell -NoProfile -File remote-gate.ps1 -Attach <run id>      # re-attach and collect
#
# -Env values may use {repo} (the remote clone of -Repo), {src} (the folder holding every clone) and
# {companion:<name>} (the remote clone of that companion). Companions are cloned BESIDE the main repo,
# named by their key, so a sibling lookup such as horde's ..\wezfleet also finds them.
#
# Exit codes: 0 every suite passed; 1 a suite failed, timed out or gave no verdict; 2 the run could
# not be set up or shipped; 3 NOT RUN (the remote never wrote its complete line, died, or the wait
# timed out). The last line printed is always "REMOTE-GATE-LOCAL <label> exit=<n>".
#
# ASCII only. No 2>&1 on native commands (PowerShell 5.1 turns stderr lines into error records).

[CmdletBinding(DefaultParameterSetName = 'Run')]
param(
    [Parameter(ParameterSetName = 'Run', Mandatory = $true)][string]$Repo,
    [Parameter(ParameterSetName = 'Run', Mandatory = $true)][string]$Commit,
    [Parameter(ParameterSetName = 'Run')][string[]]$Suites = @(),
    [Parameter(ParameterSetName = 'Run')][string[]]$Mutate = @(),
    [Parameter(ParameterSetName = 'Run', Mandatory = $true)][ValidatePattern('^[A-Za-z0-9_.-]{1,40}$')][string]$Label,
    [Parameter(ParameterSetName = 'Run')][hashtable]$Env = @{},
    [Parameter(ParameterSetName = 'Run')][hashtable]$Companion = @{},
    [Parameter(ParameterSetName = 'Run')][int]$SuiteTimeoutMinutes = 20,
    [Parameter(ParameterSetName = 'Run')][string]$MutateTool = 'tools\Mutate.ps1',
    [Parameter(ParameterSetName = 'Run')][switch]$RealProfile,
    [Parameter(ParameterSetName = 'Run')][int]$Keep = 10,
    # Suites (from -Suites) that may start a WezTerm GUI. Every other suite gets no WezTerm beyond a
    # contained `cli` (the -NoWezterm default). Even these get --skip-config and never the real socket.
    [Parameter(ParameterSetName = 'Run')][string[]]$AllowWezterm = @(),
    [Parameter(ParameterSetName = 'Run')][string]$WeztermShim = '',
    # Only for re-measuring the GUI behaviour that disabled -AllowWezterm; never for a real gate.
    [Parameter(ParameterSetName = 'Run')][switch]$AllowWeztermDespiteRealRuntimeDir,
    [Parameter(ParameterSetName = 'Attach', Mandatory = $true)][string]$Attach,
    [string]$RemoteHost = 'always-on',
    [string]$RemoteRoot = 'C:\Users\yagdil\horde-ci',
    [string]$LocalRoot = '',
    [int]$PollSeconds = 20,
    [int]$WaitSlackMinutes = 15
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# Not $script:label: at script scope that IS $Label, and its ValidatePattern refuses the empty value
# attach mode needs (measured).
$script:gateLabel = $Label
# Not a param default: under powershell -File on 5.1, $PSScriptRoot is empty while defaults are
# evaluated (measured: -Attach failed on an empty Join-Path).
if (-not $LocalRoot) { $LocalRoot = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'remote-gate-runs' }

# Straight to stdout, never the pipeline: functions below return values, and Write-Output would
# mix these lines into them.
function Write-Line { param([string]$Text) [Console]::Out.WriteLine($Text) }

function Finish {
    param([int]$Code, [string]$Why = '')
    if ($Why) { Write-Line ("REMOTE-GATE-LOCAL " + $script:gateLabel + " " + $Why) }
    Write-Line ("REMOTE-GATE-LOCAL " + $script:gateLabel + " exit=" + $Code)
    exit $Code
}

function Invoke-Native {
    # Run an executable with stdout and stderr kept apart, and a hard timeout. Returns code/out/err.
    # Not 2>&1 (PowerShell 5.1); and a timeout so a hung ssh can never hang the gate.
    param([string]$File, [string[]]$Arguments, [int]$TimeoutSeconds = 120)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $File
    $psi.Arguments = (($Arguments | ForEach-Object {
        if ($_ -match '[\s"]' -or $_ -eq '') { '"' + ($_ -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' } else { $_ }
    }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
        try { $p.Kill() } catch { }
        [void]$p.WaitForExit(5000)
        return [pscustomobject]@{ code = -1; out = ''; err = ('timed out after ' + $TimeoutSeconds + 's'); timedOut = $true }
    }
    $p.WaitForExit()
    return [pscustomobject]@{ code = $p.ExitCode; out = $outTask.Result; err = $errTask.Result; timedOut = $false }
}

function Remove-Clixml {
    param([string]$Text)
    $i = $Text.IndexOf('#< CLIXML')
    if ($i -ge 0) {
        $end = $Text.LastIndexOf('</Objs>')
        if ($end -gt $i) { $Text = $Text.Substring(0, $i) + $Text.Substring($end + 7) } else { $Text = $Text.Substring(0, $i) }
    }
    return $Text
}

function Get-SshOptions {
    return @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15', '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=3')
}

function Invoke-Remote {
    # Run a PowerShell script on the remote box. The script is sent encoded, never quoted.
    param([string]$Script, [int]$TimeoutSeconds = 120)
    $full = "`$ProgressPreference = 'SilentlyContinue'`r`n" + $Script
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($full))
    $r = Invoke-Native -File 'ssh.exe' -Arguments ((Get-SshOptions) + @($RemoteHost, ('powershell -NoProfile -NonInteractive -EncodedCommand ' + $b64))) -TimeoutSeconds $TimeoutSeconds
    $r.out = Remove-Clixml $r.out
    $r.err = Remove-Clixml $r.err
    return $r
}

function Quote { param([string]$s) return "'" + ($s -replace "'", "''") + "'" }

function ConvertTo-ScpPath { param([string]$WinPath) return ($RemoteHost + ':' + ($WinPath -replace '\\', '/')) }

# ---------------------------------------------------------------------------------------------
# The remote runner. Shipped as a file; started detached; writes only inside its run folder.
# ---------------------------------------------------------------------------------------------
# Reads another process's environment block, for attribution: the technique of wezfleet PR #59
# (test_debug/run-suites.ps1). x64 offsets: PEB+0x20 is ProcessParameters; in RTL_USER_PROCESS_PARAMETERS,
# +0x80 is Environment and +0x3F0 EnvironmentSize. Returns null when the process cannot be opened or read.
$ProcEnvSource = @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class RgProcEnv {
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

$RunnerText = @'
param([Parameter(Mandatory = $true)][string]$RunDir)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$job = Get-Content -LiteralPath (Join-Path $RunDir 'job.json') -Raw | ConvertFrom-Json
$logDir = Join-Path $RunDir 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$runnerLog = Join-Path $logDir 'runner.log'
$me = Get-CimInstance Win32_Process -Filter ("ProcessId=" + $PID)
$myStart = $me.CreationDate.ToUniversalTime().ToString('o')

function Log { param([string]$t) Add-Content -LiteralPath $runnerLog -Encoding Ascii -Value ((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') + ' ' + $t) }

function Set-Status {
    param([string]$State, [string]$Current = '', [int]$Index = 0)
    $o = [ordered]@{ state = $State; pid = $PID; start = $myStart; current = $Current; index = $Index; total = @($job.items).Count
        updated = (Get-Date).ToUniversalTime().ToString('o') }
    $tmp = Join-Path $RunDir 'status.json.tmp'
    [System.IO.File]::WriteAllText($tmp, ($o | ConvertTo-Json -Compress), [System.Text.Encoding]::ASCII)
    Move-Item -LiteralPath $tmp -Destination (Join-Path $RunDir 'status.json') -Force
}

function Invoke-Logged {
    # Run a program with stdout and stderr to files; wait at most $Seconds. Returns exit code, or
    # $null on timeout (after killing only the tree this runner started).
    param([string]$File, [string[]]$ArgList, [string]$WorkDir, [string]$Out, [string]$Err, [int]$Seconds)
    $p = Start-Process -FilePath $File -ArgumentList $ArgList -WorkingDirectory $WorkDir -RedirectStandardOutput $Out -RedirectStandardError $Err -WindowStyle Hidden -PassThru
    $h = $p.Handle  # keep a handle so ExitCode is readable after exit
    $started = $p.StartTime
    if ($p.WaitForExit($Seconds * 1000)) { $p.WaitForExit(); return $p.ExitCode }
    Stop-OwnTree -RootPid $p.Id -RootStart $started
    return $null
}

function Stop-OwnTree {
    # Kill the process and its descendants. A descendant counts only if it was created after its
    # parent, so a pid the OS reused for an unrelated process is never killed.
    param([int]$RootPid, [datetime]$RootStart)
    $all = @(Get-CimInstance Win32_Process)
    $root = $all | Where-Object { $_.ProcessId -eq $RootPid } | Select-Object -First 1
    if (-not $root -or [math]::Abs(($root.CreationDate - $RootStart).TotalSeconds) -gt 2) { Log ("tree root " + $RootPid + " already gone"); return }
    $victims = New-Object System.Collections.ArrayList
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue($root)
    while ($queue.Count -gt 0) {
        $n = $queue.Dequeue(); [void]$victims.Add($n)
        foreach ($c in $all) { if ($c.ParentProcessId -eq $n.ProcessId -and $c.CreationDate -ge $n.CreationDate -and $c.ProcessId -ne $n.ProcessId) { $queue.Enqueue($c) } }
    }
    for ($i = $victims.Count - 1; $i -ge 0; $i--) {
        $v = $victims[$i]
        Log ("kill pid=" + $v.ProcessId + " name=" + $v.Name)
        try { Stop-Process -Id $v.ProcessId -Force -ErrorAction Stop } catch { Log ("kill failed: " + $_) }
    }
}

# --- WezTerm containment (see the header of remote-gate.ps1) ---
# The real profile, read BEFORE USERPROFILE is redirected: WezTerm ignores the redirect, so this is where it writes.
$realProfile = $env:USERPROFILE
$realWezDir = Join-Path $realProfile '.local\share\wezterm'
Add-Type -Path (Join-Path $RunDir 'procenv.cs')

function Get-WzProcs {
    return @(Get-CimInstance Win32_Process | Where-Object { $_.Name -like 'wezterm*.exe' } | ForEach-Object {
        [pscustomobject]@{ pid = [int]$_.ProcessId; name = $_.Name; created = $_.CreationDate; ppid = [int]$_.ParentProcessId; path = $_.ExecutablePath } })
}

function Get-RealWezSnap {
    if (-not (Test-Path -LiteralPath $realWezDir)) { return @() }
    return @(Get-ChildItem -LiteralPath $realWezDir -Force -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $_.FullName.Substring($realWezDir.Length + 1) + '|' + $(if ($_.PSIsContainer) { 'dir' } else { $_.Length }) + '|' + $_.LastWriteTimeUtc.Ticks })
}

function Invoke-WzSweep {
    # Every wezterm* process born during the suite: carries the suite's marker -> LEAK, killed by pid and
    # creation time; no marker -> FOREIGN, left; environment unreadable -> UNATTRIBUTED, left.
    param($Before, [datetime]$Since, [string]$Mark)
    $lines = New-Object System.Collections.ArrayList
    $ours = New-Object System.Collections.ArrayList
    $known = @($Before | ForEach-Object { "" + $_.pid + "|" + $_.created.Ticks })
    foreach ($p in @(Get-WzProcs)) {
        if ($known -contains ("" + $p.pid + "|" + $p.created.Ticks)) { continue }
        if ($p.created -lt $Since.AddSeconds(-2)) { continue }
        $desc = "pid=" + $p.pid + " name=" + $p.name + " created=" + $p.created.ToUniversalTime().ToString('o') + " parent=" + $p.ppid + " path=" + $p.path
        $block = [RgProcEnv]::Read($p.pid)
        if ($null -eq $block) { [void]$lines.Add("UNATTRIBUTED " + $desc + " (environment unreadable; left running)"); continue }
        if (@($block -split [char]0) -notcontains ($Mark + '=1')) { [void]$lines.Add("FOREIGN " + $desc + " (no run marker; left running)"); continue }
        [void]$ours.Add([string]$p.pid)
        $again = Get-CimInstance Win32_Process -Filter ("ProcessId=" + $p.pid)
        if ($again -and $again.CreationDate -eq $p.created) {
            try { Stop-Process -Id $p.pid -Force -ErrorAction Stop; [void]$lines.Add("LEAK " + $desc + " (carries " + $Mark + "; killed)") }
            catch { [void]$lines.Add("LEAK " + $desc + " (carries " + $Mark + "; kill failed: " + $_ + ")") }
        } else { [void]$lines.Add("LEAK " + $desc + " (carries " + $Mark + "; exited before the kill)") }
    }
    return [pscustomobject]@{ lines = @($lines.ToArray()); ours = @($ours.ToArray()) }
}

function Compare-RealWez {
    # Any new, changed or removed entry in the real WezTerm folder is REALDIR (fails the suite). A NEW
    # log or gui-sock file named by a pid proven to be the run's is removed again; nothing else is touched.
    param($Before, $After, $OurPids)
    $lines = New-Object System.Collections.ArrayList
    $beforeNames = @($Before | ForEach-Object { ($_ -split '\|')[0] })
    foreach ($e in @($After | Where-Object { $Before -notcontains $_ })) {
        $name = ($e -split '\|')[0]
        $isNew = $beforeNames -notcontains $name
        $m = [regex]::Match($name, '^(?:wezterm(?:-gui|-mux-server)?\.exe-log-(\d+)\.txt|gui-sock-(\d+))$')
        $filePid = $(if ($m.Success) { $m.Groups[1].Value + $m.Groups[2].Value } else { '' })
        if ($isNew -and $filePid -and (@($OurPids) -contains $filePid)) {
            try { Remove-Item -LiteralPath (Join-Path $realWezDir $name) -Force -ErrorAction Stop; [void]$lines.Add("REALDIR new " + $name + " (pid " + $filePid + " is the run's; removed)") }
            catch { [void]$lines.Add("REALDIR new " + $name + " (pid " + $filePid + " is the run's; remove failed: " + $_ + ")") }
        } else { [void]$lines.Add("REALDIR " + $(if ($isNew) { 'new' } else { 'changed' }) + " " + $name + " (not provably the run's; left)") }
    }
    $afterNames = @($After | ForEach-Object { ($_ -split '\|')[0] })
    foreach ($n in @($beforeNames | Where-Object { $afterNames -notcontains $_ })) { [void]$lines.Add("REALDIR removed " + $n + " (left)") }
    return @($lines.ToArray())
}

$summary = New-Object System.Collections.ArrayList
$worst = 0
try {
    Set-Status -State 'cloning'
    Log ("runner pid=" + $PID + " start=" + $myStart + " label=" + $job.label)
    $src = Join-Path $RunDir 'src'
    New-Item -ItemType Directory -Force -Path $src | Out-Null
    foreach ($c in @($job.clones)) {
        $dest = Join-Path $src $c.name
        $bundle = Join-Path $RunDir $c.bundle
        $code = Invoke-Logged -File 'git.exe' -ArgList @('clone', '-q', '-c', 'core.autocrlf=true', '--no-checkout', ('"' + $bundle + '"'), ('"' + $dest + '"')) -WorkDir $RunDir -Out (Join-Path $logDir ('clone-' + $c.name + '.out')) -Err (Join-Path $logDir ('clone-' + $c.name + '.err')) -Seconds 600
        if ($code -ne 0) { throw ("git clone of " + $c.name + " exited " + $code) }
        $code = Invoke-Logged -File 'git.exe' -ArgList @('-C', ('"' + $dest + '"'), 'checkout', '-q', '--detach', $c.commit) -WorkDir $RunDir -Out (Join-Path $logDir ('checkout-' + $c.name + '.out')) -Err (Join-Path $logDir ('checkout-' + $c.name + '.err')) -Seconds 600
        if ($code -ne 0) { throw ("git checkout of " + $c.name + " " + $c.commit + " exited " + $code) }
        $head = (Get-Content -LiteralPath (Join-Path $dest '.git\HEAD') -Raw).Trim()
        Log ("cloned " + $c.name + " HEAD=" + $head)
        if ($head -ne $c.commit) { throw ("clone " + $c.name + " is at " + $head + ", wanted " + $c.commit) }
    }
    $repoDir = Join-Path $src $job.repoName

    # Isolated environment: scratch TEMP and profile, then the caller's variables.
    $tmpDir = Join-Path $RunDir 'tmp'; $homeDir = Join-Path $RunDir 'home'
    New-Item -ItemType Directory -Force -Path $tmpDir, $homeDir | Out-Null
    $env:TEMP = $tmpDir; $env:TMP = $tmpDir
    if (-not $job.realProfile) {
        # APPDATA and LOCALAPPDATA too (coordinator audit, 2026-10-01): an auto-started mux runs the box's real
        # ~/.wezterm.lua, whose plugins clone into the roaming data folder and write Claude hooks under the home.
        $roaming = Join-Path $homeDir 'AppData\Roaming'; $local = Join-Path $homeDir 'AppData\Local'
        New-Item -ItemType Directory -Force -Path $roaming, $local | Out-Null
        $env:USERPROFILE = $homeDir; $env:HOME = $homeDir; $env:APPDATA = $roaming; $env:LOCALAPPDATA = $local
    }
    foreach ($p in @($job.env)) {
        $v = [string]$p.value
        $v = $v.Replace('{repo}', $repoDir).Replace('{src}', $src)
        foreach ($c in @($job.clones)) { $v = $v.Replace('{companion:' + $c.name + '}', (Join-Path $src $c.name)) }
        Set-Item -LiteralPath ('env:' + $p.name) -Value $v
        Log ("env " + $p.name + "=" + $v)
    }

    # WezTerm containment, set AFTER the caller's variables so nothing can loosen it.
    $realWez = Get-Command wezterm.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    $binDir = Join-Path $RunDir 'bin'; $wezDir = Join-Path $RunDir 'wez'
    New-Item -ItemType Directory -Force -Path $binDir, $wezDir | Out-Null
    foreach ($n in @('wezterm.exe', 'wezterm-gui.exe', 'wezterm-mux-server.exe')) { Copy-Item -LiteralPath (Join-Path $RunDir 'wezterm-shim.exe') -Destination (Join-Path $binDir $n) -Force }
    $runSock = Join-Path $wezDir 'sock'
    $cfg = Join-Path $wezDir 'wezterm.lua'
    [System.IO.File]::WriteAllText($cfg, ("return { unix_domains = { { name = 'unix', socket_path = [[" + $runSock + "]], no_serve_automatically = true } } }`r`n"), [System.Text.Encoding]::ASCII)
    if ($realWez) { $env:RG_WEZTERM_REAL = Split-Path -Parent $realWez.Source } else { $env:RG_WEZTERM_REAL = '' }
    $env:RG_WEZTERM_REAL_SOCK = Join-Path $realWezDir 'sock'
    $env:RG_WEZTERM_LEDGER = Join-Path $logDir 'wezterm-ledger.txt'
    $env:WEZTERM_UNIX_SOCKET = $runSock
    $env:WEZTERM_CONFIG_FILE = $cfg
    $env:WEZTERM_LOG = 'off'
    $env:PATH = $binDir + ';' + $env:PATH
    Log ("wezterm: real=" + $env:RG_WEZTERM_REAL + " realdir=" + $realWezDir + " shim=" + $binDir + " socket=" + $runSock)

    $i = 0
    foreach ($it in @($job.items)) {
        $i++
        Set-Status -State 'running' -Current $it.path -Index $i
        $base = ('{0:D2}-{1}' -f $i, ([IO.Path]::GetFileNameWithoutExtension($it.path) -replace '[^A-Za-z0-9_.-]', '_'))
        if ($it.kind -eq 'mutate') { $base += '-mutate' }
        $out = Join-Path $logDir ($base + '.out'); $err = Join-Path $logDir ($base + '.err')
        if ($it.kind -eq 'mutate') { $argList = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $repoDir $job.mutateTool) + '"'), '-Spec', ('"' + $it.path + '"')) }
        else { $argList = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $repoDir $it.path) + '"')) }
        $mode = $(if ($it.wezterm -eq 'isolated') { 'isolated' } else { 'deny' })
        $env:RG_WEZTERM_MODE = $mode
        $mark = 'RG_MARK_' + [guid]::NewGuid().ToString('N')
        $ledger = $env:RG_WEZTERM_LEDGER
        $ledgerBefore = $(if (Test-Path -LiteralPath $ledger) { @(Get-Content -LiteralPath $ledger).Count } else { 0 })
        $wzBefore = @(Get-WzProcs)
        $realBefore = @(Get-RealWezSnap)
        Log ("start " + $it.kind + " " + $it.path + " wezterm=" + $mode + " mark=" + $mark)
        $t0 = Get-Date
        # The suite, and everything it starts, inherits the marker; it is set only around this one call.
        [Environment]::SetEnvironmentVariable($mark, '1')
        try { $code = Invoke-Logged -File 'powershell.exe' -ArgList $argList -WorkDir $repoDir -Out $out -Err $err -Seconds ([int]$job.timeoutSeconds) }
        finally { [Environment]::SetEnvironmentVariable($mark, $null) }
        $secs = [int]((Get-Date) - $t0).TotalSeconds
        Start-Sleep -Seconds 2   # a launcher hands off to a server asynchronously (wezfleet PR #59)
        $sweep = Invoke-WzSweep -Before $wzBefore -Since $t0 -Mark $mark
        $calls = @(); if (Test-Path -LiteralPath $ledger) { $calls = @(Get-Content -LiteralPath $ledger | Select-Object -Skip $ledgerBefore) }
        $ourPids = @($sweep.ours) + @($calls | ForEach-Object { $mm = [regex]::Match($_, '\|child=(\d+)\|'); if ($mm.Success) { $mm.Groups[1].Value } })
        $realLines = @(Compare-RealWez -Before $realBefore -After @(Get-RealWezSnap) -OurPids $ourPids)
        $log = Join-Path $logDir ($base + '.log')
        $lines = New-Object System.Collections.ArrayList
        if (Test-Path -LiteralPath $out) { foreach ($l in (Get-Content -LiteralPath $out)) { [void]$lines.Add($l) } }
        if ((Test-Path -LiteralPath $err) -and (Get-Item -LiteralPath $err).Length -gt 0) { [void]$lines.Add('--- stderr ---'); foreach ($l in (Get-Content -LiteralPath $err)) { [void]$lines.Add($l) } }
        if ($null -eq $code) { [void]$lines.Add('TIMEOUT after ' + $job.timeoutSeconds + 's'); $code = 124 }
        [void]$lines.Add('--- wezterm containment (mode ' + $mode + ') ---')
        foreach ($c in $calls) { [void]$lines.Add('WEZTERM-CALL ' + $c) }
        foreach ($l in @($sweep.lines) + $realLines) { [void]$lines.Add($l); Log $l }
        $bad = @(@($sweep.lines) + $realLines | Where-Object { $_ -match '^(LEAK|UNATTRIBUTED|REALDIR) ' }).Count
        [void]$lines.Add('CONTAINMENT=' + $(if ($bad -gt 0) { 'BREACHED ' + $bad } else { 'clean' }))
        if ($bad -gt 0) { $worst = 1 }
        [void]$lines.Add('SECONDS=' + $secs)
        [void]$lines.Add('DONE=' + $code)
        [System.IO.File]::WriteAllLines($log, [string[]]$lines.ToArray(), [System.Text.Encoding]::ASCII)
        Remove-Item -LiteralPath $out, $err -Force -ErrorAction SilentlyContinue
        Log ("done " + $it.path + " code=" + $code + " seconds=" + $secs)
        [void]$summary.Add(('{0} {1} DONE={2} seconds={3} wezterm={4} CONTAINMENT={5}' -f $base, $it.path, $code, $secs, $mode, $(if ($bad -gt 0) { 'BREACHED' } else { 'clean' })))
        if ($code -ne 0) { $worst = 1 }
    }
    $sumLines = @($summary.ToArray()) + @(('exit=' + $worst), ('REMOTE-GATE ' + $job.label + ' complete'))
    [System.IO.File]::WriteAllLines((Join-Path $RunDir 'summary.txt'), [string[]]$sumLines, [System.Text.Encoding]::ASCII)
    Set-Status -State 'complete' -Index $i
    Log 'complete'
} catch {
    Log ("ABORTED: " + $_)
    $sumLines = @($summary.ToArray()) + @(('REMOTE-GATE ' + $job.label + ' aborted: ' + $_))
    [System.IO.File]::WriteAllLines((Join-Path $RunDir 'summary.txt'), [string[]]$sumLines, [System.Text.Encoding]::ASCII)
    Set-Status -State 'aborted' -Current ("$_")
}
'@

# ---------------------------------------------------------------------------------------------
# Remote probes
# ---------------------------------------------------------------------------------------------
function Get-RemoteStatus {
    # Status as the remote sees it, plus whether the runner process is still the one we started.
    param([string]$RemoteRun)
    $s = @"
`$d = $(Quote $RemoteRun)
`$f = Join-Path `$d 'status.json'
if (-not (Test-Path -LiteralPath `$f)) { '{"state":"nostatus","alive":false}'; return }
`$st = Get-Content -LiteralPath `$f -Raw | ConvertFrom-Json
`$alive = `$false
`$p = Get-CimInstance Win32_Process -Filter ("ProcessId=" + [int]`$st.pid)
if (`$p -and [math]::Abs((`$p.CreationDate.ToUniversalTime() - [datetime]::Parse(`$st.start).ToUniversalTime()).TotalSeconds) -lt 2) { `$alive = `$true }
`$st | Add-Member -NotePropertyName alive -NotePropertyValue `$alive -Force
`$st | ConvertTo-Json -Compress
"@
    $r = Invoke-Remote -Script $s -TimeoutSeconds 60
    if ($r.code -ne 0) { return $null }
    $line = @($r.out -split "`r?`n" | Where-Object { $_ -match '^\{' }) | Select-Object -Last 1
    if (-not $line) { return $null }
    try { return ($line | ConvertFrom-Json) } catch { return $null }
}

function Wait-AndCollect {
    param([string]$RunLabel, [string]$RunId, [string]$LocalRun, [int]$WaitMinutes)
    $remoteRun = Join-Path $RemoteRoot ('runs\' + $RunLabel + '\' + $RunId)
    $deadline = (Get-Date).AddMinutes($WaitMinutes)
    $state = $null; $misses = 0; $lastSeen = ''; $waitStart = Get-Date
    while ((Get-Date) -lt $deadline) {
        $st = Get-RemoteStatus -RemoteRun $remoteRun
        if ($null -eq $st) {
            $misses++
            # The connection is down or the box is busy: keep waiting. The remote job does not need us.
            if ($misses -eq 1 -or ($misses % 10) -eq 0) { Write-Line ("status read failed (" + $misses + " in a row); still waiting") }
        } else {
            $misses = 0
            $seen = $st.state + ' ' + $st.index + '/' + $st.total + ' ' + $st.current
            if ($seen -ne $lastSeen) { Write-Line ((Get-Date).ToString('HH:mm:ss') + ' remote: ' + $seen); $lastSeen = $seen }
            if ($st.state -eq 'complete' -or $st.state -eq 'aborted') { $state = $st.state; break }
            # A runner that has not written its first status yet is given a minute before it counts as dead.
            $young = ((Get-Date) - $waitStart).TotalSeconds -lt 90
            if (($st.state -eq 'nostatus' -and -not $young) -or ($st.state -ne 'nostatus' -and -not $st.alive)) { $state = 'dead'; Write-Line ("remote runner is not alive and never finished (state " + $st.state + ")"); break }
        }
        Start-Sleep -Seconds $PollSeconds
    }
    if ($null -eq $state) { $state = 'waittimeout'; Write-Line ("gave up waiting after " + $WaitMinutes + " minutes; the remote job may still be running: re-attach with -Attach " + $RunId) }

    # Collect whatever exists, in every case.
    $dest = Join-Path $LocalRun 'remote'
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    foreach ($what in @('logs', 'summary.txt', 'status.json')) {
        $r = Invoke-Native -File 'scp.exe' -Arguments ((Get-SshOptions) + @('-q', '-r', (ConvertTo-ScpPath (Join-Path $remoteRun $what)), $dest)) -TimeoutSeconds 300
        if ($r.code -ne 0) { Write-Line ("collect " + $what + ": scp exited " + $r.code + " " + $r.err.Trim()) }
    }
    return $state
}

function Get-Verdict {
    # Decide from the copied files alone. Returns the exit code and prints one line per item.
    param($Job, [string]$LocalRun)
    $logs = Join-Path $LocalRun 'remote\logs'
    $sumFile = Join-Path $LocalRun 'remote\summary.txt'
    $complete = $false
    if (Test-Path -LiteralPath $sumFile) {
        $last = @(Get-Content -LiteralPath $sumFile | Where-Object { $_.Trim() -ne '' }) | Select-Object -Last 1
        $complete = ($last -ceq ('REMOTE-GATE ' + $Job.label + ' complete'))
        if (-not $complete) { Write-Line ("remote summary does not end complete: " + $last) }
    } else { Write-Line 'no remote summary was collected' }
    $bad = 0; $i = 0
    foreach ($it in @($Job.items)) {
        $i++
        $base = ('{0:D2}-{1}' -f $i, ([IO.Path]::GetFileNameWithoutExtension($it.path) -replace '[^A-Za-z0-9_.-]', '_'))
        if ($it.kind -eq 'mutate') { $base += '-mutate' }
        $log = Join-Path $logs ($base + '.log')
        if (-not (Test-Path -LiteralPath $log)) { Write-Line ("  [NOT RUN] " + $it.path + " (no log)"); $bad++; continue }
        $lines = @(Get-Content -LiteralPath $log)
        $doneLine = @($lines | Where-Object { $_ -match '^DONE=-?\d+$' }) | Select-Object -Last 1
        $code = $null; if ($doneLine) { $code = [int]($doneLine.Substring(5)) }
        $secs = (@($lines | Where-Object { $_ -match '^SECONDS=\d+$' }) | Select-Object -Last 1)
        if ($it.kind -eq 'mutate') { $verdict = @($lines | Where-Object { $_ -match '^mutations: ' }) | Select-Object -Last 1 }
        else { $verdict = @($lines | Where-Object { $_ -match '^==== .+ ====$' }) | Select-Object -Last 1 }
        $pass = @($lines | Where-Object { $_ -match '^\s*\[(PASS|OK)\]' }).Count
        $fail = @($lines | Where-Object { $_ -match '^\s*\[(FAIL|ERROR|BAD)\]' }).Count
        $timedOut = @($lines | Where-Object { $_ -match '^TIMEOUT after ' }).Count -gt 0
        $tag = 'PASS'
        if ($null -eq $code) { $tag = 'NO DONE LINE' }
        elseif ($timedOut) { $tag = 'TIMEOUT' }
        elseif (-not $verdict) { $tag = 'NO VERDICT' }
        elseif ($code -ne 0) { $tag = 'FAIL' }
        # WezTerm containment: a suite that leaked, or whose containment was never checked, is not green.
        $breaches = @($lines | Where-Object { $_ -match '^(LEAK|UNATTRIBUTED|REALDIR) ' })
        $contained = @($lines | Where-Object { $_ -match '^CONTAINMENT=' }) | Select-Object -Last 1
        if ($tag -eq 'PASS' -and $breaches.Count -gt 0) { $tag = 'LEAK' }
        elseif ($tag -eq 'PASS' -and -not $contained) { $tag = 'NO CONTAINMENT LINE' }
        if ($tag -ne 'PASS') { $bad++ }
        Write-Line ('  [' + $tag + '] ' + $it.path + ' DONE=' + $code + ' pass=' + $pass + ' fail=' + $fail + ' ' + $secs + ' ' + $contained + ' verdict: ' + $verdict)
        foreach ($f in @($lines | Where-Object { $_ -match '^\s*\[(FAIL|ERROR|BAD)\]' } | Select-Object -First 10)) { Write-Line ('        ' + $f.Trim()) }
        foreach ($f in @($lines | Where-Object { $_ -match '^(LEAK|UNATTRIBUTED|REALDIR|FOREIGN) ' })) { Write-Line ('        ' + $f) }
    }
    if (-not $complete) { return 3 }
    if ($bad -gt 0) { return 1 }
    return 0
}

# ---------------------------------------------------------------------------------------------
# Attach mode
# ---------------------------------------------------------------------------------------------
if ($PSCmdlet.ParameterSetName -eq 'Attach') {
    $localRun = Join-Path $LocalRoot $Attach
    $jobFile = Join-Path $localRun 'job.json'
    $script:gateLabel = 'attach'
    if (-not (Test-Path -LiteralPath $jobFile)) { Finish 2 ("no local record of run " + $Attach + " at " + $jobFile) }
    $job = Get-Content -LiteralPath $jobFile -Raw | ConvertFrom-Json
    $script:gateLabel = $job.label
    Write-Line ("REMOTE-GATE-LOCAL " + $job.label + " attach run=" + $Attach)
    $t0 = Get-Date
    $state = Wait-AndCollect -RunLabel $job.label -RunId $Attach -LocalRun $localRun -WaitMinutes ([int]$job.waitMinutes)
    Write-Line ("remote state=" + $state + " waited=" + [int]((Get-Date) - $t0).TotalSeconds + "s")
    $code = Get-Verdict -Job $job -LocalRun $localRun
    Write-Line ("logs: " + (Join-Path $localRun 'remote\logs'))
    Finish $code
}

# ---------------------------------------------------------------------------------------------
# Run mode: validate, bundle, ship, launch, wait, collect, judge.
# ---------------------------------------------------------------------------------------------
$t0 = Get-Date
if (@($Suites).Count + @($Mutate).Count -eq 0) { Finish 2 'nothing to run: give -Suites and/or -Mutate' }
foreach ($s in @($Suites) + @($Mutate)) { if ($s -match '^[A-Za-z]:|^[\\/]|\.\.') { Finish 2 ("not a repo-relative path: " + $s) } }
foreach ($a in @($AllowWezterm)) { if (@($Suites) -notcontains $a) { Finish 2 ("-AllowWezterm names a suite that is not in -Suites: " + $a) } }
# DISABLED until WezTerm can be given its own runtime folder. Measured 2026-10-01 (run w3-20261001221613): a
# `--skip-config start` GUI, socket pinned in the run folder, still DELETED 17 stale files of the box's own in the
# real ~/.local/share/wezterm at startup and left a gui-sock there. That folder comes from the Windows profile API
# and no variable moves it, so "isolated" is not achievable on this box as the same user. The shim keeps its
# isolated mode for when it is (a separate local user, or a WezTerm that honours a runtime-dir variable).
if (@($AllowWezterm).Count -gt 0 -and -not $AllowWeztermDespiteRealRuntimeDir) { Finish 2 "-AllowWezterm is disabled: a WezTerm GUI on the remote box writes to and prunes its REAL runtime folder (measured 2026-10-01); see the comment above this line" }
if (-not $WeztermShim) { $WeztermShim = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'rg-shim\bin\Release\wezterm.exe' }
if (-not (Test-Path -LiteralPath $WeztermShim)) { Finish 2 ("the WezTerm shim is missing: " + $WeztermShim + " (build rg-shim\WeztermShim.csproj)") }
foreach ($k in @($Env.Keys)) { if ("$k" -like 'WEZTERM_*' -or "$k" -like 'RG_*') { Finish 2 ("-Env may not set " + $k + ": WezTerm containment owns it") } }
$Repo = (Resolve-Path -LiteralPath $Repo).Path
$runId = $Label + '-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6)
$localRun = Join-Path $LocalRoot $runId
New-Item -ItemType Directory -Force -Path $localRun | Out-Null
Write-Line ("REMOTE-GATE-LOCAL " + $Label + " run=" + $runId + " local=" + $localRun)

function New-Bundle {
    # Bundle exactly one commit. A scratch bare repo receives the commit under one ref, so the
    # repository being tested never gains a ref.
    param([string]$From, [string]$Rev, [string]$Name)
    $r = Invoke-Native -File 'git.exe' -Arguments @('-C', $From, 'rev-parse', '--verify', ($Rev + '^{commit}'))
    if ($r.code -ne 0) { Finish 2 ("cannot resolve " + $Rev + " in " + $From + ": " + $r.err.Trim()) }
    $sha = $r.out.Trim()
    $bare = Join-Path $localRun ($Name + '.git')
    $r = Invoke-Native -File 'git.exe' -Arguments @('init', '-q', '--bare', $bare)
    if ($r.code -ne 0) { Finish 2 ("git init failed: " + $r.err.Trim()) }
    # The scratchpad path is long; without this the push fails with "Filename too long" (measured).
    $null = Invoke-Native -File 'git.exe' -Arguments @('-C', $bare, 'config', 'core.longpaths', 'true')
    $r = Invoke-Native -File 'git.exe' -Arguments @('-C', $From, 'push', '-q', '--no-verify', $bare, ($sha + ':refs/heads/gate')) -TimeoutSeconds 600
    if ($r.code -ne 0) { Finish 2 ("git push to scratch failed: " + $r.err.Trim()) }
    $bundle = Join-Path $localRun ($Name + '.bundle')
    $r = Invoke-Native -File 'git.exe' -Arguments @('-C', $bare, 'bundle', 'create', $bundle, 'refs/heads/gate') -TimeoutSeconds 600
    if ($r.code -ne 0) { Finish 2 ("git bundle failed: " + $r.err.Trim()) }
    Remove-Item -LiteralPath $bare -Recurse -Force
    return [pscustomobject]@{ name = $Name; commit = $sha; bundle = ($Name + '.bundle'); from = $From }
}

$repoName = Split-Path -Leaf $Repo
$clones = New-Object System.Collections.ArrayList
[void]$clones.Add((New-Bundle -From $Repo -Rev $Commit -Name $repoName))
foreach ($k in @($Companion.Keys)) {
    if ($k -notmatch '^[A-Za-z0-9_.-]+$' -or $k -eq $repoName) { Finish 2 ("bad companion name: " + $k) }
    $spec = [string]$Companion[$k]; $rev = 'HEAD'
    $at = $spec.LastIndexOf('@')
    if ($at -gt 2) { $rev = $spec.Substring($at + 1); $spec = $spec.Substring(0, $at) }
    [void]$clones.Add((New-Bundle -From (Resolve-Path -LiteralPath $spec).Path -Rev $rev -Name $k))
}
foreach ($c in $clones) { Write-Line ("bundle " + $c.name + " " + $c.commit + " from " + $c.from) }

$items = @()
foreach ($s in @($Suites)) { $items += [pscustomobject]@{ kind = 'suite'; path = $s; wezterm = $(if (@($AllowWezterm) -contains $s) { 'isolated' } else { 'deny' }) } }
foreach ($m in @($Mutate)) { $items += [pscustomobject]@{ kind = 'mutate'; path = $m; wezterm = 'deny' } }
$envList = @(); foreach ($k in @($Env.Keys)) { $envList += [pscustomobject]@{ name = [string]$k; value = [string]$Env[$k] } }
$waitMinutes = $SuiteTimeoutMinutes * $items.Count + $WaitSlackMinutes
$job = [pscustomobject]@{
    label = $Label; runId = $runId; repoName = $repoName; created = (Get-Date).ToUniversalTime().ToString('o')
    clones = @($clones | ForEach-Object { [pscustomobject]@{ name = $_.name; commit = $_.commit; bundle = $_.bundle } })
    items = $items; env = $envList; timeoutSeconds = ($SuiteTimeoutMinutes * 60); mutateTool = $MutateTool
    realProfile = [bool]$RealProfile; waitMinutes = $waitMinutes
}
[System.IO.File]::WriteAllText((Join-Path $localRun 'job.json'), ($job | ConvertTo-Json -Depth 6), [System.Text.Encoding]::ASCII)
[System.IO.File]::WriteAllText((Join-Path $localRun 'runner.ps1'), $RunnerText, [System.Text.Encoding]::ASCII)
Copy-Item -LiteralPath $WeztermShim -Destination (Join-Path $localRun 'wezterm-shim.exe')
[System.IO.File]::WriteAllText((Join-Path $localRun 'procenv.cs'), $ProcEnvSource, [System.Text.Encoding]::ASCII)

# Make the run folder and prune old runs: keep the newest $Keep, never one whose runner still lives.
$remoteRun = Join-Path $RemoteRoot ('runs\' + $Label + '\' + $runId)
$prep = @"
`$root = $(Quote (Join-Path $RemoteRoot ('runs\' + $Label)))
`$run = $(Quote $remoteRun)
New-Item -ItemType Directory -Force -Path `$run | Out-Null
# Belt and braces: only folders named like this label's run ids, inside this label's own subroot.
`$old = @(Get-ChildItem -LiteralPath `$root -Directory | Where-Object { `$_.FullName -ne `$run -and `$_.Name -like '$Label-*' } | Sort-Object CreationTimeUtc -Descending | Select-Object -Skip ($Keep - 1))
foreach (`$d in `$old) {
    `$live = `$false
    `$sf = Join-Path `$d.FullName 'status.json'
    if (Test-Path -LiteralPath `$sf) {
        try { `$st = Get-Content -LiteralPath `$sf -Raw | ConvertFrom-Json
            `$p = Get-CimInstance Win32_Process -Filter ("ProcessId=" + [int]`$st.pid)
            if (`$p -and [math]::Abs((`$p.CreationDate.ToUniversalTime() - [datetime]::Parse(`$st.start).ToUniversalTime()).TotalSeconds) -lt 2) { `$live = `$true } } catch { }
    }
    if (`$live) { "keep-live " + `$d.Name } else { Remove-Item -LiteralPath `$d.FullName -Recurse -Force -ErrorAction SilentlyContinue; "pruned " + `$d.Name }
}
"ready"
"@
$r = Invoke-Remote -Script $prep -TimeoutSeconds 120
if ($r.code -ne 0 -or $r.out -notmatch 'ready') { Finish 2 ("remote prepare failed: code=" + $r.code + " " + $r.err.Trim()) }
foreach ($l in @($r.out -split "`r?`n" | Where-Object { $_ -match '^(pruned|keep-live) ' })) { Write-Line ("remote " + $l) }

$ship = @((Join-Path $localRun 'job.json'), (Join-Path $localRun 'runner.ps1'), (Join-Path $localRun 'wezterm-shim.exe'), (Join-Path $localRun 'procenv.cs')) + @($clones | ForEach-Object { Join-Path $localRun $_.bundle })
$r = Invoke-Native -File 'scp.exe' -Arguments ((Get-SshOptions) + @('-q') + $ship + @((ConvertTo-ScpPath ($remoteRun + '\')))) -TimeoutSeconds 900
if ($r.code -ne 0) { Finish 2 ("scp to remote failed: " + $r.err.Trim()) }
$tShip = Get-Date

# Launch detached via WMI so it is outside the ssh session's job object and survives a disconnect.
$launch = @"
`$run = $(Quote $remoteRun)
`$cmd = 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + (Join-Path `$run 'runner.ps1') + '" -RunDir "' + `$run + '"'
`$res = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = `$cmd; CurrentDirectory = `$run }
"launch rv=" + `$res.ReturnValue + " pid=" + `$res.ProcessId
"@
$r = Invoke-Remote -Script $launch -TimeoutSeconds 120
$m = [regex]::Match($r.out, 'launch rv=(\d+) pid=(\d+)')
if (-not $m.Success -or $m.Groups[1].Value -ne '0') { Finish 2 ("remote launch failed: " + $r.out.Trim() + " " + $r.err.Trim()) }
Write-Line ("launched remote runner pid=" + $m.Groups[2].Value + " run=" + $remoteRun + " (ship took " + [int]($tShip - $t0).TotalSeconds + "s)")
Write-Line ("re-attach if this side dies: powershell -NoProfile -File " + $PSCommandPath + " -Attach " + $runId)

$state = Wait-AndCollect -RunLabel $Label -RunId $runId -LocalRun $localRun -WaitMinutes $waitMinutes
Write-Line ("remote state=" + $state + " total=" + [int]((Get-Date) - $t0).TotalSeconds + "s")
$code = Get-Verdict -Job $job -LocalRun $localRun
Write-Line ("logs: " + (Join-Path $localRun 'remote\logs'))
Finish $code
