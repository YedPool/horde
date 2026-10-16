# test/lib/Browser.ps1 - the one way a Horde suite starts a headless browser, and the one way it ends it.
#
#   . (Join-Path $root "test\lib\Browser.ps1")
#   $chrome = Find-HordeTestChrome                    # "" when Chrome is not installed
#   $browser = $null
#   try {
#       $browser = Start-HordeTestBrowser -Chrome $chrome -Parent $work
#       ... a driver connects to http://127.0.0.1:<$browser.port> over the debugging protocol ...
#   } finally {
#       $end = Stop-HordeTestBrowser -Browser $browser    # safe on $null, safe twice
#   }
#
# WHY THIS FILE. Until 2026-10-14 each node driver (the hosted relay's sign-in driver,
# surfaces/pwa/test/browser-drive.mjs) spawned Chrome itself and ended it in its own finally with
# `taskkill /PID <the pid it spawned> /T`. That left headless browsers running for ever, about 0.4 GB
# each (four at once found orphaned on 2026-10-14), and their profiles under %TEMP% (130
# horde-cf-accounts-* folders since 2026-10-11), for two reasons, both measured on this box:
#   - THE PID THE DRIVER HOLDS IS NOT THE BROWSER. Chrome 155 (155.0.8059.79), started as the drivers
#     started it, hands over at once to a second chrome.exe and exits: on 2026-10-14 a running
#     test-pwa-browser.ps1 had its browser (pid 3216) parented by a pid that no longer existed, and the
#     driver node had no chrome.exe child at all. So the driver's `chrome.exitCode === null` was false
#     and the taskkill never ran, and `taskkill /T` from that pid could not have reached the tree anyway.
#     The browser ended only when the driver lived to send Browser.close over the debugging protocol.
#   - A DRIVER THAT DIES SENDS NOTHING. The suite kills the driver on its timeout (Process.Kill, node
#     only); a crash, a Ctrl+C or a killed suite do the same. Node's own job object (libuv puts every
#     child in a kill-on-close job) does not save it: that job allows SILENT breakaway, so the browser
#     the first chrome.exe started is in no job at all. The browser lives on, holds its profile, and the
#     suite's Remove-Item -ErrorAction SilentlyContinue leaves the folder behind without a word.
#
# THE CHOICE: A WINDOWS JOB OBJECT, HELD BY THE SUITE'S OWN POWERSHELL. Chrome is created SUSPENDED,
# put in a job of this process's own that kills every process in it when its last handle closes
# (JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE) and allows NO breakaway, and only then resumed - so every process
# the browser ever starts, the hand-over above included, is born in the job. Then:
#   - pass, fail, a thrown error, Ctrl+C (PowerShell runs finally blocks when a pipeline is stopped), a
#     driver's timeout or death: the suite's finally calls Stop-HordeTestBrowser, which ends the whole
#     job, waits until the job says no process of it is alive, and only then removes the profile, and
#     says whether it is gone;
#   - THE SUITE ITSELF KILLED (taskkill /F, a closed window): no code of the suite runs, but Windows
#     closes the job's handle with the process, and the browser dies with it. Only the profile folder
#     can be left then: nothing runs to remove it. That is the one exit this file cannot clean fully.
# Rejected: killing by image name (it would end the person's own Chrome); killing the tree by pid from
# the driver (above: the pid is gone before the tree is); a job made AFTER Process.Start (the browser
# could hand over before it is assigned); a job in node (node cannot make one without a native addon);
# a sweeper of old folders (it would hide the leak, not stop it).
#
# Never a visible window: --headless=new, and the process is created with CREATE_NO_WINDOW. Nothing of
# the person's own browsers is touched: only the processes in this job, which this file started.

if (-not ([System.Management.Automation.PSTypeName]"HordeTestBrowserJobV1").Type) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class HordeTestBrowserJobV1 {
    [StructLayout(LayoutKind.Sequential)] struct BASIC_LIMIT { public long a, b; public uint flags; public UIntPtr c, d; public uint e; public UIntPtr f; public uint g, h; }
    [StructLayout(LayoutKind.Sequential)] struct IO_COUNTERS { public ulong a, b, c, d, e, f; }
    [StructLayout(LayoutKind.Sequential)] struct EXTENDED_LIMIT { public BASIC_LIMIT basic; public IO_COUNTERS io; public UIntPtr p, j, pp, jp; }
    [StructLayout(LayoutKind.Sequential)] struct ACCOUNTING { public long a, b, c, d; public uint pageFaults, total, active, terminated; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct STARTUPINFO {
        public int cb; public string reserved, desktop, title; public int x, y, xSize, ySize, xChars, yChars, fill, flags;
        public short showWindow, reserved2; public IntPtr reserved3, stdIn, stdOut, stdErr; }
    [StructLayout(LayoutKind.Sequential)] struct PROCESS_INFORMATION { public IntPtr process, thread; public int pid, tid; }
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr a, string n);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetInformationJobObject(IntPtr j, int c, ref EXTENDED_LIMIT i, int l);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool AssignProcessToJobObject(IntPtr j, IntPtr p);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool QueryInformationJobObject(IntPtr j, int c, out ACCOUNTING i, int l, IntPtr r);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool TerminateJobObject(IntPtr j, uint code);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool CreateProcess(string app, System.Text.StringBuilder cmd, IntPtr pa, IntPtr ta,
        bool inherit, uint flags, IntPtr env, string dir, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32.dll", SetLastError = true)] static extern uint ResumeThread(IntPtr t);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool TerminateProcess(IntPtr p, uint code);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    const uint CREATE_SUSPENDED = 0x4, CREATE_NO_WINDOW = 0x08000000, CREATE_UNICODE_ENVIRONMENT = 0x400;
    // KILL_ON_JOB_CLOSE (0x2000) and nothing else: no BREAKAWAY_OK (0x800), no SILENT_BREAKAWAY_OK (0x1000),
    // so no process started inside can leave the job.
    const uint KILL_ON_JOB_CLOSE = 0x2000;

    // Start exe with the command line cmd, suspended, in a new kill-on-close job, then resume it.
    // Returns { job handle, pid }. On any failure nothing is left running and the job is closed.
    public static long[] Start(string exe, string cmd, string dir) {
        IntPtr j = CreateJobObject(IntPtr.Zero, null);
        if (j == IntPtr.Zero) throw new Win32Exception();
        EXTENDED_LIMIT l = new EXTENDED_LIMIT();
        l.basic.flags = KILL_ON_JOB_CLOSE;
        if (!SetInformationJobObject(j, 9, ref l, Marshal.SizeOf(l))) { int e = Marshal.GetLastWin32Error(); CloseHandle(j); throw new Win32Exception(e); }
        STARTUPINFO si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(si);
        PROCESS_INFORMATION pi;
        // No handles inherited: the browser gets no pipe of the suite's, so it can never hold one open.
        if (!CreateProcess(exe, new System.Text.StringBuilder(cmd), IntPtr.Zero, IntPtr.Zero, false, CREATE_SUSPENDED | CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT, IntPtr.Zero, dir, ref si, out pi)) {
            int e = Marshal.GetLastWin32Error(); CloseHandle(j); throw new Win32Exception(e);
        }
        try {
            if (!AssignProcessToJobObject(j, pi.process)) throw new Win32Exception();
            if (ResumeThread(pi.thread) == 0xFFFFFFFF) throw new Win32Exception();
        } catch {
            TerminateProcess(pi.process, 1); CloseHandle(pi.thread); CloseHandle(pi.process); CloseHandle(j); throw;
        }
        CloseHandle(pi.thread); CloseHandle(pi.process);
        return new long[] { j.ToInt64(), pi.pid };
    }
    // How many processes of the job are alive now, or -1 when the job cannot be read.
    public static int Active(long j) { ACCOUNTING a; if (!QueryInformationJobObject(new IntPtr(j), 1, out a, Marshal.SizeOf(typeof(ACCOUNTING)), IntPtr.Zero)) return -1; return (int)a.active; }
    public static bool Terminate(long j) { return TerminateJobObject(new IntPtr(j), 1); }
    public static void Close(long j) { CloseHandle(new IntPtr(j)); }
}
'@
}

# The browser's own flags. The same as the two drivers passed before 2026-10-14: headless, a debugging
# port the system chooses (written to DevToolsActivePort in the profile), and nothing that reaches out.
$script:HordeTestBrowserFlags = @("--headless=new", "--remote-debugging-port=0", "--no-first-run", "--no-default-browser-check", "--disable-extensions",
    "--disable-background-networking", "--disable-sync", "--disable-component-update")
# THE PROFILE'S PATH IS KEPT SHORT (measured 2026-10-15, the bisect of test-pwa-browser after PR 288).
# Chrome writes its service-worker storage up to 139 characters deep inside a profile
# (Default\Service Worker\CacheStorage\<40 hex>\<uuid>\index-dir\the-real-index), and a Windows path
# stops at 259. With the profile at <suite work folder>\horde-browser-<32 hex> (133 characters under
# test-pwa-browser's %TEMP%\horde-pwa-browser-<32 hex>) the deepest file came to 272: the worker
# installed and filled its cache, then its registration was lost, and the page was never controlled -
# 8 checks red, with nothing in the console. The old <work>\chrome (232) and a short parent both pass.
# So the leaf is hb- and 8 hex, and a profile whose path leaves less than that depth of room is
# REFUSED in words before Chrome starts, rather than losing the worker silently.
$script:HordeTestBrowserProfilePrefix = "hb-"
$script:HordeTestBrowserProfileDepth = 140
$script:HordeTestBrowserPathMax = 259

function Find-HordeTestChrome {
    # Chrome's full path, or "" when it is not installed in any of its usual places.
    $c = @(
        (Join-Path ${env:ProgramFiles} "Google\Chrome\Application\chrome.exe"),
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe" }),
        $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe" })
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
    if ($null -eq $c) { return "" }
    return "" + $c
}

function Start-HordeTestBrowser {
    # A headless browser in a fresh profile of its own (<-Parent>\hb-<8 hex>, -Parent
    # defaulting to %TEMP%), in a kill-on-close job of this process (header). Returns the handle
    # { pid; port; profile; job } once the browser's debugging port is open; throws, having ended what
    # it started and removed the profile, when it is not open within -ReadySeconds. -ExtraArgs come
    # after the standard flags (each one argument; quoted here when it holds a space).
    param([Parameter(Mandatory = $true)][string]$Chrome, [string]$Parent = "", [string[]]$ExtraArgs = @(), [int]$ReadySeconds = 20)
    if ($Parent -eq "") { $Parent = [System.IO.Path]::GetTempPath() }
    $profileDir = Join-Path $Parent ($script:HordeTestBrowserProfilePrefix + [guid]::NewGuid().ToString("N").Substring(0, 8))
    $room = $script:HordeTestBrowserPathMax - $script:HordeTestBrowserProfileDepth
    if ($profileDir.Length -gt $room) { throw ("the browser profile path would be " + $profileDir.Length + " characters, more than " + $room + ": Chrome writes up to " + $script:HordeTestBrowserProfileDepth + " more inside it and a Windows path stops at " + $script:HordeTestBrowserPathMax + ", so its service worker would be lost; start it under a shorter -Parent") }
    [void][System.IO.Directory]::CreateDirectory($profileDir)
    $argv = @($script:HordeTestBrowserFlags) + @("--user-data-dir=" + $profileDir) + @($ExtraArgs) + @("about:blank")
    $quoted = @($argv | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } })
    $cmd = '"' + $Chrome + '" ' + ($quoted -join " ")
    $started = $null
    try { $started = [HordeTestBrowserJobV1]::Start($Chrome, $cmd, $profileDir) }
    catch { Remove-Item -LiteralPath $profileDir -Recurse -Force -ErrorAction SilentlyContinue; throw }
    $browser = [pscustomobject]@{ pid = [int]$started[1]; port = 0; profile = $profileDir; job = [long]$started[0]; stopped = $false }
    $portFile = Join-Path $profileDir "DevToolsActivePort"
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    while ($clock.Elapsed.TotalSeconds -lt $ReadySeconds) {
        if (Test-Path -LiteralPath $portFile -PathType Leaf) {
            $first = ""
            try { $first = ("" + [System.IO.File]::ReadAllText($portFile)).Split("`n")[0].Trim() } catch { }
            if ($first -match '\A[0-9]{1,5}\z') { $browser.port = [int]$first; return $browser }
        }
        if ([HordeTestBrowserJobV1]::Active($browser.job) -eq 0) { break }
        Start-Sleep -Milliseconds 100
    }
    $end = Stop-HordeTestBrowser -Browser $browser
    throw ("the browser did not open its debugging port within " + $ReadySeconds + " s (" + $end.said + ")")
}

function Stop-HordeTestBrowser {
    # End every process of the browser's job, wait until the job says none is alive, then remove its
    # profile. { left; profileGone; said } - left is the processes still alive (0 when ended),
    # profileGone whether the folder is gone. Safe on $null and safe twice. Never throws: it runs in
    # finally blocks, where a throw would hide the suite's own error.
    param($Browser)
    if ($null -eq $Browser) { return [pscustomobject]@{ left = 0; profileGone = $true; said = "no browser was started" } }
    $left = 0
    if (-not $Browser.stopped) {
        $Browser.stopped = $true
        try {
            $null = [HordeTestBrowserJobV1]::Terminate($Browser.job)
            # A process ended through its job is counted alive for a moment after (measured on the remote
            # transport tests' throwaway server job): asked for up to 10 s.
            $clock = [System.Diagnostics.Stopwatch]::StartNew()
            $left = [HordeTestBrowserJobV1]::Active($Browser.job)
            while ($left -ne 0 -and $clock.Elapsed.TotalSeconds -lt 10) { Start-Sleep -Milliseconds 100; $left = [HordeTestBrowserJobV1]::Active($Browser.job) }
        } finally { [HordeTestBrowserJobV1]::Close($Browser.job) }
    }
    # The files are free once their processes are gone, but Windows may finish closing a handle a moment
    # later: a few tries, then the folder's state is said, never hidden.
    $gone = $false
    for ($i = 0; $i -lt 20 -and -not $gone; $i++) {
        if (Test-Path -LiteralPath $Browser.profile) { Remove-Item -LiteralPath $Browser.profile -Recurse -Force -ErrorAction SilentlyContinue }
        $gone = -not (Test-Path -LiteralPath $Browser.profile)
        if (-not $gone) { Start-Sleep -Milliseconds 250 }
    }
    $said = $(if ($left -eq 0 -and $gone) { "ended, profile removed" } else { "" + $left + " process(es) left, profile " + $(if ($gone) { "removed" } else { "NOT removed" }) })
    return [pscustomobject]@{ left = $left; profileGone = $gone; said = $said }
}

function Get-HordeTestBrowserProcesses {
    # The processes now running with -ProfileDir as their --user-data-dir, by their command lines: the
    # outside check that a browser is gone, which does not rely on the job's own count. Process ids.
    param([Parameter(Mandatory = $true)][string]$ProfileDir)
    $needle = "--user-data-dir=" + $ProfileDir
    $quotedNeedle = '--user-data-dir="' + $ProfileDir
    return @(Get-CimInstance -ClassName Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $c = "" + $_.CommandLine
        $c.IndexOf($needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or $c.IndexOf($quotedNeedle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    } | ForEach-Object { [int]$_.ProcessId })
}
