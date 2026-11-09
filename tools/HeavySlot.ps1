# tools/HeavySlot.ps1 - THE LOCAL GATE: one heavy test run at a time on this machine, across every
# session and agent that runs one (CONTRIBUTING 15, rule 5: "locally, one run at a time, through the
# local gate, which holds one lock across every agent on the machine").
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\HeavySlot.ps1 -Script <suite, relative to -Worktree> [-Worktree <path>]
#       [-ScriptArgs <a>,<b> | -ArgsFile <args.json>] [-Out <log>] [-MinFreeGB 3] [-MinCommitHeadroomGB 0] [-WaitSeconds 7200]
#       [-RunSeconds 3600] [-NetRun]
# A RUN STARTS ONLY WHEN THE PC IS IDLE OR IT IS NIGHT (founder rule, 2026-10-22): 10 minutes without keyboard
# or mouse input, or 22:00 to 07:00 local; core/IdleState.ps1 says what counts, and <HORDE_HOME>\settings\idle.json
# sets the thresholds. There is no switch to skip it: a suite that must stand clear of the machine's clock points
# HORDE_HOME at a folder whose idle.json makes every hour night (nightStartHour 0, nightEndHour 24).
# THE RUN'S ARGUMENTS. -ScriptArgs is split on commas, and each piece loses one layer of matching quotes:
#   powershell -File hands the list over as ONE string with its quotes still on (measured 2026-10-15:
#   -ScriptArgs '-Spec','x.psd1' reached the suite as the single argument '-Spec','x.psd1'). A piece that
#   still holds a quote after that is refused with 126, nothing run, rather than passed on mangled.
#   -ArgsFile is a JSON array of strings, taken exactly; it is the way for an argument holding a comma,
#   a single quote or a space, and wins over -ScriptArgs. A missing file, one that does not start with
#   [, or one holding a non-string is refused with 126, each in its own words. Either way, an argument
#   holding a double quote, one of cmd's own characters (& | < > ^ %) or a control character (a line
#   break ends cmd's line) is refused with 126: the run is started through cmd's line, which would
#   read them itself.
#
# Development tooling, not part of the engine. test/test-heavy-slot.ps1 is its suite.
#
# WHY (2026-10-14). Several agents each waited for free memory, then all started together when it freed,
# and this PC sat at 6 to 12 percent free all evening; two heavy runs started in the same minute while
# the founder's own sessions shared the machine. Waiting for memory is not enough: the WAIT must be one
# queue. So the slot is a machine-wide named mutex, and memory is waited for only by its holder.
#
# WHAT IT DOES, in order:
#   1. WAITS FIRST, TAKES LAST (T-0331; core/HeavySlotAcquire.ps1). Until 2026-10-22 it took the slot and then
#      waited for memory, so one waiter under the floor held every lane back for as long as ITS -WaitSeconds
#      (about 2.5 hours on that day). Now it waits, holding nothing, for BOTH idle-or-night and free memory of
#      at least -MinFreeGB, and only then tries the mutex -SlotName, in short slices so Ctrl+C can break the
#      wait. It checks both again after taking the slot; if either failed in between it RELEASES the slot
#      and goes back to waiting. -WaitSeconds bounds all of it together. -MinCommitHeadroomGB (default 0, off)
#      adds a third floor, commit limit less commit charge (2026-10-23: 52.3 of 54.8 GB committed all night).
#      A wait that gives up on memory or commit lists the 8 largest process groups by working set, so the
#      log names who holds the memory;
#   2. A HOLDER THAT WAS KILLED leaves the mutex abandoned, and Windows hands it to the next waiter. Its run
#      dies with it (step 4's job), but a run of an older gate, or one started some other way, may not. So
#      the holder keeps a record (-HolderFile: the run's process id, start time and script), and a later
#      holder that finds a record of a run still alive - the same id AND the same start time, so a reused
#      id is not mistaken for it - waits for that run to end first. A record that cannot be read is
#      ignored: refusing on it would block every run for ever. Since T-0445 the record also carries the worktree
#      and the time the slot was taken (UTC), after the first three lines, which stay as every older reader reads
#      them; a waiter that gives up on the slot, or has waited 10 s on it, names the holder from the record; and
#      a slot log beside the record (.log) keeps one line per take, release and give-up, never the run's arguments;
#   3. (the memory wait is step 1 now, before the slot);
#   4. runs the script - a .ps1 under Windows PowerShell 5.1, a .mjs under node - with standard input
#      closed and PSModulePath cleared, output to -Out, for at most -RunSeconds, INSIDE A KILL-ON-CLOSE
#      JOB OBJECT that allows no breakaway. It is created suspended, put in the job, recorded (step 2),
#      and only then resumed, so every process it ever starts is in the job - a grandchild whose middle
#      parent exited too (npx, cmd, node and Chrome all hand over that way; taskkill /T from the run's id
#      cannot reach those, measured for Chrome in test/lib/Browser.ps1). And when this gate is killed,
#      Windows closes the job's handle with it and every process of the run dies;
#   5. ALWAYS, in finally (an error, Ctrl+C, a timeout, a normal end): the whole job is ended - a run past
#      its time, and anything a finished run left behind - before the record is removed and the mutex
#      released. An error nobody planned for (node missing, the mutex refused) is said, with exit 127,
#      before the closing line, never after it.
# Every exit says why in plain words, and the LAST line is always "heavy-slot: released exit=<n>"
# (CONTRIBUTING 15, rule 7: a run without its closing line proves nothing), written to the console's own
# output so a stopped pipeline cannot swallow it.
#
# THE NET'S FIRST CLAIM (2026-11-06): the nightly net holds the named mutex <SlotName>-NetClaim open from its start until
# its bisects are over and its report is written (T-0447). While that name exists, a gate without -NetRun waits, holding nothing, and gives up with 125 in
# its own words, never taking the slot. Only the net passes -NetRun. A mutex name lasts only while a process holds it, so a
# killed net or a restart leaves no claim behind. Derived from -SlotName, so a suite with a slot of its own is not held up.
#
# EXIT CODES: the script's own; 124 the run passed -RunSeconds; 125 the slot, a killed holder's run or
# the memory (or the commit headroom) was not had within -WaitSeconds (nothing was run); 128 the PC was not idle and it was not night within -WaitSeconds (nothing was run, nothing held); 126 the script is not there; 127 an
# error the gate did not plan for. 126 also means the run's arguments were refused (THE RUN'S
# ARGUMENTS). A suite that itself exits 124 to 127 reads the same: tell them apart by
# the gate's own words above the closing line.
#
# A suite uses its own -SlotName and -HolderFile, so a test never takes or frees the machine's real slot.

param(
    [Parameter(Mandatory = $true)][string]$Script,
    [string]$Worktree = "",
    [string[]]$ScriptArgs = @(),
    [string]$ArgsFile = "",
    [string]$Out = "",
    [double]$MinFreeGB = 3,
    [double]$MinCommitHeadroomGB = 0,
    [int]$WaitSeconds = 7200,
    [int]$RunSeconds = 3600,
    [string]$SlotName = "Global\HordeHeavySlot",
    [string]$HolderFile = "",
    [switch]$NetRun
)
$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\IdleState.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\HeavySlotAcquire.ps1")

if (-not ([System.Management.Automation.PSTypeName]"HordeHeavySlotJobV1").Type) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class HordeHeavySlotJobV1 {
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
    [DllImport("kernel32.dll", SetLastError = true)] static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetExitCodeProcess(IntPtr p, out uint code);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    const uint CREATE_SUSPENDED = 0x4, CREATE_NO_WINDOW = 0x08000000, CREATE_UNICODE_ENVIRONMENT = 0x400;
    // KILL_ON_JOB_CLOSE (0x2000) and nothing else: no BREAKAWAY_OK (0x800), no SILENT_BREAKAWAY_OK (0x1000).
    const uint KILL_ON_JOB_CLOSE = 0x2000;

    // Create cmd SUSPENDED in a new kill-on-close job: { job, process, thread, pid }. Nothing runs until
    // Resume. On any failure nothing is left and every handle is closed.
    public static long[] Create(string exe, string cmd, string dir) {
        IntPtr j = CreateJobObject(IntPtr.Zero, null);
        if (j == IntPtr.Zero) throw new Win32Exception();
        EXTENDED_LIMIT l = new EXTENDED_LIMIT();
        l.basic.flags = KILL_ON_JOB_CLOSE;
        if (!SetInformationJobObject(j, 9, ref l, Marshal.SizeOf(l))) { int e = Marshal.GetLastWin32Error(); CloseHandle(j); throw new Win32Exception(e); }
        STARTUPINFO si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(si);
        PROCESS_INFORMATION pi;
        if (!CreateProcess(exe, new System.Text.StringBuilder(cmd), IntPtr.Zero, IntPtr.Zero, false, CREATE_SUSPENDED | CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT, IntPtr.Zero, dir, ref si, out pi)) {
            int e = Marshal.GetLastWin32Error(); CloseHandle(j); throw new Win32Exception(e);
        }
        if (!AssignProcessToJobObject(j, pi.process)) {
            int e = Marshal.GetLastWin32Error(); TerminateProcess(pi.process, 1); CloseHandle(pi.thread); CloseHandle(pi.process); CloseHandle(j); throw new Win32Exception(e);
        }
        return new long[] { j.ToInt64(), pi.process.ToInt64(), pi.thread.ToInt64(), pi.pid };
    }
    public static void Resume(long thread) { if (ResumeThread(new IntPtr(thread)) == 0xFFFFFFFF) throw new Win32Exception(); CloseHandle(new IntPtr(thread)); }
    // Has the process ended within ms?
    public static bool Wait(long process, uint ms) { return WaitForSingleObject(new IntPtr(process), ms) == 0; }
    public static int ExitCode(long process) { uint c; if (!GetExitCodeProcess(new IntPtr(process), out c)) return -1; return unchecked((int)c); }
    // How many processes of the job are alive now, or -1 when the job cannot be read.
    public static int Active(long j) { ACCOUNTING a; if (!QueryInformationJobObject(new IntPtr(j), 1, out a, Marshal.SizeOf(typeof(ACCOUNTING)), IntPtr.Zero)) return -1; return (int)a.active; }
    public static bool Terminate(long j) { return TerminateJobObject(new IntPtr(j), 1); }
    public static void Close(long h) { CloseHandle(new IntPtr(h)); }
}
'@
}

function Get-HordeHeavySlotFreeGB { return [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 2) }

# FreeVirtualMemory is the commit limit less the commit charge, in KB.
function Get-HordeHeavySlotCommitHeadroomGB { return [math]::Round((Get-CimInstance Win32_OperatingSystem).FreeVirtualMemory / 1MB, 2) }

function Write-HordeHeavySlotHolders {
    # Who holds the memory, after a wait for it gave up: never fatal, a gate must still close with its line.
    try { foreach ($l in @(Get-HordeHeavySlotMemoryHolders -Processes @(Get-Process -ErrorAction SilentlyContinue) -Top 8)) { Write-HordeHeavySlotLine $l } }
    catch { Write-HordeHeavySlotLine ("heavy-slot: the memory holders could not be listed: " + $_.Exception.Message) }
}

function Write-HordeHeavySlotLine { param([string]$Line) [Console]::Out.WriteLine($Line) }

function Get-HordeHeavySlotLiveRun {
    # The run a holder record names, if that very process is still alive: { pid; script; process } or $null.
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $rec = $null
    try { $rec = [System.IO.File]::ReadAllText($Path) -split "`n" } catch { return $null }
    if (@($rec).Count -lt 3) { return $null }
    $runPid = 0; $ticks = [long]0
    if (-not [int]::TryParse($rec[0].Trim(), [ref]$runPid) -or -not [long]::TryParse($rec[1].Trim(), [ref]$ticks)) { return $null }
    $p = Get-Process -Id $runPid -ErrorAction SilentlyContinue
    if ($null -eq $p) { return $null }
    try { if ($p.StartTime.ToUniversalTime().Ticks -ne $ticks) { return $null } } catch { return $null }
    return [pscustomobject]@{ pid = $runPid; script = $rec[2].Trim(); process = $p }
}

function Get-HordeHeavySlotHolderText {
    # WHO HOLDS THE SLOT, in words, from its holder record (T-0445: on 2026-11-07 a bisect gave up after 900 s and
    # nothing could name what held the slot). Lines 1 to 3 are the run's id, its start ticks and its script, as every
    # older reader reads them; a gate since T-0445 adds its worktree and the time it took the slot (UTC). The post-merge
    # monitor writes the first three only. Never fatal: a waiter must still give up and close with its line.
    param([string]$Path)
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "a holder that keeps no record here (or one between its take and its record)" }
        $rec = @(([System.IO.File]::ReadAllText($Path) -split "`n") | ForEach-Object { $_.Trim() })
        if ($rec.Count -lt 3 -or $rec[2] -eq "") { return "a holder whose record cannot be read" }
        $t = $rec[2] + " (process " + $rec[0]
        if ($rec.Count -gt 3 -and $rec[3] -ne "") { $t += ", worktree " + $rec[3] }
        if ($rec.Count -gt 4 -and $rec[4] -ne "") { $t += ", since " + $rec[4] }
        return ($t + ")")
    } catch { return "a holder whose record cannot be read" }
}

function Write-HordeHeavySlotLog {
    # THE SLOT LOG (T-0445): one line per take, release and give-up, beside the holder record, so a wait can be traced to
    # its holder afterwards. Only the time, the gate's id, the script's name, the worktree, the seconds waited and the exit:
    # never the run's arguments, which may carry paths or secrets. Over 1 MB it is moved to .1 (one old copy) by a gate
    # that holds the slot. A write that fails costs one warning and never the run: no retry, so it never adds a wait.
    param([string]$Event, [string]$Exit = "")
    try {
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($script:slotLog))
        if ($Event -ceq "take" -and (Test-Path -LiteralPath $script:slotLog -PathType Leaf) -and (Get-Item -LiteralPath $script:slotLog).Length -gt 1MB) {
            Move-Item -LiteralPath $script:slotLog -Destination ($script:slotLog + ".1") -Force
        }
        $line = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ") + " " + $Event + " pid=" + $PID + " script=" + $Script + " worktree=" + $Worktree + " waited=" + $script:waited
        if ($Exit -ne "") { $line += " exit=" + $Exit }
        [System.IO.File]::AppendAllText($script:slotLog, $line + "`r`n")
    } catch {
        if (-not $script:logWarned) { $script:logWarned = $true; Write-HordeHeavySlotLine ("heavy-slot: WARNING - the slot log " + $script:slotLog + " could not be written (" + $_.Exception.Message + "); the run is not affected") }
    }
}

function Test-HordeHeavySlotNetClaim {
    # Does the net's first claim exist? A name we may not open still exists, so it counts; any other error is no claim:
    # refusing on it would block every run for ever.
    param([string]$Name)
    $claim = $null
    try { if ([System.Threading.Mutex]::TryOpenExisting($Name, [ref]$claim)) { $claim.Dispose(); return $true } return $false }
    catch [System.UnauthorizedAccessException] { return $true }
    catch { return $false }
}

function ConvertTo-HordeHeavySlotArg { param([string]$A) if ($A -match '\s') { return ('"' + $A + '"') } return $A }

if ($Worktree -eq "") { $Worktree = (Get-Location).Path }
# powershell -File hands a list to a [string[]] as ONE string, so a comma separates the run's arguments.
$script:argsRefused = ""
if ($ArgsFile -ne "") {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) "core\JsonText.ps1")
    $list = $null
    # A missing or unreadable file is said so, apart from bad JSON, so a typo in the path is not read as a
    # broken file (review of PR 316).
    $raw = $null
    try { $raw = [System.IO.File]::ReadAllText($ArgsFile) } catch { $script:argsRefused = "the -ArgsFile " + $ArgsFile + " cannot be read: " + $_.Exception.Message }
    # An ARRAY, as the header says: one bare JSON string would otherwise pass as a one-argument list.
    if ($script:argsRefused -eq "" -and -not $raw.TrimStart().StartsWith("[")) { $script:argsRefused = "the -ArgsFile " + $ArgsFile + " is not a JSON array of strings (it does not start with [)" }
    if ($script:argsRefused -eq "") { try { $list = ConvertFrom-HordeJson $raw } catch { $script:argsRefused = "the -ArgsFile " + $ArgsFile + " is not a JSON array of strings" } }
    if ($script:argsRefused -eq "") {
        $items = @($list)
        if (@($items | Where-Object { $_ -isnot [string] }).Count -gt 0) { $script:argsRefused = "the -ArgsFile " + $ArgsFile + " holds something that is not a string" }
        else { $ScriptArgs = [string[]]$items }
    }
} else {
    # Split on commas, then one layer of matching quotes off each piece (the header, THE RUN'S ARGUMENTS).
    $ScriptArgs = @(@($ScriptArgs) | ForEach-Object { ("" + $_) -split "," } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" } | ForEach-Object {
        if ($_.Length -ge 2 -and (($_[0] -eq "'" -and $_[-1] -eq "'") -or ($_[0] -eq '"' -and $_[-1] -eq '"'))) { $_.Substring(1, $_.Length - 2) } else { $_ } })
    foreach ($a in @($ScriptArgs)) { if ($script:argsRefused -eq "" -and ($a.Contains('"') -or $a.StartsWith("'") -or $a.EndsWith("'"))) { $script:argsRefused = "an argument still holds a quote after one layer was taken off: " + $a + " (use -ArgsFile)" } }
}
# Every argument goes into cmd's line (below): a double quote ends cmd's quoting, and & | < > ^ % are
# cmd's own (an & would start a second command), so none of them can reach the run as written.
foreach ($a in @($ScriptArgs)) { if ($script:argsRefused -eq "" -and $a -match '["&|<>^%]') { $script:argsRefused = "an argument holds a character cmd's line cannot carry (a double quote or & | < > ^ %): " + $a } }
# A control character (a line break above all) ends cmd's line where it stands: what follows is
# dropped without a word, so the run would get fewer arguments than asked (review of PR 316).
foreach ($a in @($ScriptArgs)) { if ($script:argsRefused -eq "" -and $a -match '[\x00-\x1F]') { $script:argsRefused = "an argument holds a control character (a line break or a tab), which would cut cmd's line short: " + ($a -replace '[\x00-\x1F]', '?') } }
$name = ($SlotName -replace '[^A-Za-z0-9-]', '-')
# The record lives where every agent of this user finds it, whatever TEMP each was given.
if ($HolderFile -eq "") { $HolderFile = Join-Path (Join-Path $env:LOCALAPPDATA "horde") ("heavy-slot-" + $name + ".txt") }
# The slot log sits beside the record, so a suite's own -HolderFile gives it its own log too.
$script:slotLog = [System.IO.Path]::ChangeExtension($HolderFile, ".log")
$path = Join-Path $Worktree $Script
if ($Out -eq "") { $Out = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-heavy-slot-" + [System.IO.Path]::GetFileNameWithoutExtension($Script) + ".txt") }

# The body is a block, so each early exit is a return from it, and the code and the closing line come
# after it whatever happened. Its state lives in the script scope, where catch and finally read it.
$script:code = 125
$script:mutex = $null
$script:held = $false
$script:job = $null
$script:everHeld = $false
$script:waited = 0
$script:takenAt = ""
$script:logWarned = $false
$script:holderSaid = $false
$clock = [System.Diagnostics.Stopwatch]::StartNew()
$left = { [int][math]::Max(0, $WaitSeconds - $clock.Elapsed.TotalSeconds) }
$slice = 500
$main = {
    if ($argsRefused -ne "") { $script:code = 126; Write-HordeHeavySlotLine ("heavy-slot: " + $argsRefused + "; nothing was run"); return }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $script:code = 126; Write-HordeHeavySlotLine ("heavy-slot: there is no script " + $path + "; nothing was run"); return }
    $script:mutex = New-Object System.Threading.Mutex($false, $SlotName)
    Write-HordeHeavySlotLine ("heavy-slot: waiting for the slot " + $SlotName + " for " + $Script)
    $idleCfg = Get-HordeIdleConfig
    if (-not $idleCfg.ok) { throw ($idleCfg.findings -join " ") }
    # WAIT FIRST, TAKE LAST (core/HeavySlotAcquire.ps1): idle-or-night, then memory, then the slot, each
    # checked again after the take; nothing is held while waiting for any of them, and -WaitSeconds
    # bounds the whole. The slot itself is waited for in slices, so Ctrl+C is seen between them: one long
    # WaitOne cannot be broken.
    $claimName = $SlotName + "-NetClaim"
    $claimCheck = $(if ($NetRun) { $null } else { { Test-HordeHeavySlotNetClaim -Name $claimName } })
    $got = Invoke-HordeHeavySlotAcquire -MinFreeGB $MinFreeGB -MinCommitHeadroomGB $MinCommitHeadroomGB -WaitSeconds $WaitSeconds -SliceMs $slice -GetNetClaim $claimCheck `
        -GetIdle { Get-HordeIdleState -Config $idleCfg } `
        -GetFreeGB { Get-HordeHeavySlotFreeGB } `
        -GetCommitHeadroomGB { Get-HordeHeavySlotCommitHeadroomGB } `
        -TrySlot {
            param($ms)
            try { $script:held = $script:mutex.WaitOne($ms) }
            catch [System.Threading.AbandonedMutexException] { $script:held = $true; Write-HordeHeavySlotLine "heavy-slot: the last holder was killed before it released the slot" }
            # Once, after 10 s on the slot itself: who is ahead, so a long wait names its cause (T-0445).
            if (-not $script:held -and -not $script:holderSaid -and $clock.Elapsed.TotalSeconds -ge 10) {
                $script:holderSaid = $true
                Write-HordeHeavySlotLine ("heavy-slot: the slot is held by " + (Get-HordeHeavySlotHolderText -Path $HolderFile))
            }
            return $script:held
        } `
        -ReleaseSlot { $script:mutex.ReleaseMutex(); $script:held = $false } `
        -Elapsed { $clock.Elapsed.TotalSeconds } `
        -Sleep { param($ms) Start-Sleep -Milliseconds $ms } `
        -Say { param($line) Write-HordeHeavySlotLine $line }
    if ($got.state -cne "held") {
        if ($got.blocker -ceq "idle") { $script:code = 128; Write-HordeHeavySlotLine ("heavy-slot: gave up after " + $WaitSeconds + " s waiting for the PC to be idle or for night; nothing was run"); return }
        if ($got.blocker -ceq "claim") { Write-HordeHeavySlotLine ("heavy-slot: gave up after " + $WaitSeconds + " s: the nightly net has first claim on the slot until its report is written, at the latest about 06:30; nothing was run. Try again after that."); return }
        if ($got.blocker -ceq "memory") { Write-HordeHeavySlotLine ("heavy-slot: gave up after " + $WaitSeconds + " s waiting for " + $MinFreeGB + " GB of free memory (now " + (Get-HordeHeavySlotFreeGB) + "); nothing was run"); Write-HordeHeavySlotHolders; return }
        if ($got.blocker -ceq "commit") { Write-HordeHeavySlotLine ("heavy-slot: gave up after " + $WaitSeconds + " s waiting for " + $MinCommitHeadroomGB + " GB of commit headroom (now " + (Get-HordeHeavySlotCommitHeadroomGB) + "); nothing was run"); Write-HordeHeavySlotHolders; return }
        Write-HordeHeavySlotLine ("heavy-slot: the slot is held by " + (Get-HordeHeavySlotHolderText -Path $HolderFile))
        Write-HordeHeavySlotLine ("heavy-slot: gave up after " + $WaitSeconds + " s waiting for the slot; nothing was run")
        return
    }
    $script:everHeld = $true
    $script:waited = [int]$clock.Elapsed.TotalSeconds
    $script:takenAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    Write-HordeHeavySlotLog -Event "take"
    # Measured 2026-10-14 on this PC: a holder killed with Stop-Process did NOT leave the mutex abandoned
    # for the next waiter, whose WaitOne simply returned true, so the record, not the mutex, says a holder
    # did not finish: a record still there with its run gone is a holder that never reached its finally.
    $orphan = Get-HordeHeavySlotLiveRun -Path $HolderFile
    if ($null -eq $orphan -and (Test-Path -LiteralPath $HolderFile -PathType Leaf)) { Write-HordeHeavySlotLine "heavy-slot: the last holder did not finish cleanly (its record was left), and its run is gone" }
    if ($null -ne $orphan) {
        Write-HordeHeavySlotLine ("heavy-slot: a killed holder's run is still going (" + $orphan.script + ", process " + $orphan.pid + "): waiting for it to end first")
        while (-not $orphan.process.WaitForExit($slice)) {
            if ((& $left) -le 0) { Write-HordeHeavySlotLine ("heavy-slot: gave up after " + $WaitSeconds + " s waiting for that run to end; nothing was run"); return }
        }
    }

    Write-HordeHeavySlotLine ("heavy-slot: running " + $Script + " with " + (Get-HordeHeavySlotFreeGB) + " GB free, output in " + $Out)
    $empty = Join-Path ([System.IO.Path]::GetTempPath()) "horde-heavy-slot-empty-stdin.txt"
    [System.IO.File]::WriteAllText($empty, "")
    $env:PSModulePath = ""
    if ($Script -like "*.mjs") {
        $exe = (Get-Command node -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
        $argv = @($path) + @($ScriptArgs)
    } else {
        $exe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
        $argv = @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $path) + @($ScriptArgs)
    }
    # The redirections are cmd's, so the run's own streams go to the files and the job holds cmd and the
    # run together. /s: the outer quotes are cmd's, everything inside is the line as written.
    $inner = '"' + $exe + '" ' + ((@($argv) | ForEach-Object { ConvertTo-HordeHeavySlotArg $_ }) -join " ") + ' < "' + $empty + '" > "' + $Out + '" 2> "' + $Out + '.err"'
    $cmdExe = Join-Path $env:SystemRoot "System32\cmd.exe"
    $made = [HordeHeavySlotJobV1]::Create($cmdExe, ('"' + $cmdExe + '" /d /s /c "' + $inner + '"'), $Worktree)
    $script:job = [pscustomobject]@{ job = [long]$made[0]; process = [long]$made[1]; pid = [int]$made[3] }
    # Recorded BEFORE it runs: a holder killed at any moment after this leaves a record of a live run.
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($HolderFile))
    $start = (Get-Process -Id $job.pid).StartTime.ToUniversalTime().Ticks
    # Lines 1 to 3 exactly as every older reader reads them (pid, start ticks, script); new fields only after (T-0445).
    [System.IO.File]::WriteAllText($HolderFile, ("" + $job.pid + "`n" + $start + "`n" + $Script + "`n" + $Worktree + "`n" + $script:takenAt + "`n"))
    [HordeHeavySlotJobV1]::Resume([long]$made[2])
    $runClock = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not [HordeHeavySlotJobV1]::Wait($job.process, $slice)) {
        if ($runClock.Elapsed.TotalSeconds -ge $RunSeconds) {
            # Ended in finally below, with every process of the job.
            $script:code = 124
            Write-HordeHeavySlotLine ("heavy-slot: TIMEOUT - " + $Script + " ran past " + $RunSeconds + " s and was ended with every process it started")
            return
        }
    }
    $script:code = [HordeHeavySlotJobV1]::ExitCode($job.process)
}
try { & $main }
catch {
    $script:code = 127
    Write-HordeHeavySlotLine ("heavy-slot: ERROR - " + $_.Exception.Message)
}
finally {
    if ($null -ne $job) {
        # The whole job, always: a run past its time, and whatever a finished run left behind.
        $null = [HordeHeavySlotJobV1]::Terminate($job.job)
        $c = [System.Diagnostics.Stopwatch]::StartNew()
        while ([HordeHeavySlotJobV1]::Active($job.job) -gt 0 -and $c.Elapsed.TotalSeconds -lt 10) { Start-Sleep -Milliseconds 100 }
        [HordeHeavySlotJobV1]::Close($job.process)
        [HordeHeavySlotJobV1]::Close($job.job)
        try { if (Test-Path -LiteralPath $HolderFile) { $first = ([System.IO.File]::ReadAllText($HolderFile) -split "`n")[0].Trim(); if ($first -eq ("" + $job.pid)) { Remove-Item -LiteralPath $HolderFile -Force } } } catch { }
    }
    # Logged while still held, so the next take's line always comes after this release's.
    if ($held) { Write-HordeHeavySlotLog -Event "release" -Exit ("" + $code) }
    elseif (-not $everHeld -and ($code -eq 125 -or $code -eq 128)) { $script:waited = [int]$clock.Elapsed.TotalSeconds; Write-HordeHeavySlotLog -Event "gave-up" -Exit ("" + $code) }
    if ($held) { $mutex.ReleaseMutex() }
    if ($null -ne $mutex) { $mutex.Dispose() }
    Write-HordeHeavySlotLine ("heavy-slot: released exit=" + $code)
}
exit $code
