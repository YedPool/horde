# core/Platform - the machine core runs on: the namespace its process ids live in, and how it reads
# its own process table.
#
# WHY A SEAM. The read model checks a session's process against the process table, and compares a
# pid a host reports with it only inside one namespace (core/HostPort.ps1, "PID AND CWD CARRY A
# NAMESPACE"). Both used to be Windows calls written into core (review of PR #31, finding 6). A node
# on another system (the remote plan's R12) supplies its own platform; this file holds the seam and
# the one platform Horde runs on today, Windows, and no other implementation.
#
# A platform is { name; processSpace; processTable }: processTable is a script block returning the
# process table as core/identity takes it - a core/tristate answer holding a hashtable keyed by pid of
# { pid; name; created (UTC); commandLine } - or unknown with the reason.

# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path $PSScriptRoot "Tristate.ps1")

# The namespaces a pid or path can live in, as core/HostPort.ps1's rows name them.
$script:HordeProcessSpacePattern = '^(windows|posix|synthetic|wsl:[A-Za-z0-9._-]{1,64})$'

function New-HordePlatform {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ProcessSpace,
        [Parameter(Mandatory = $true)][scriptblock]$ProcessTable
    )
    if ($ProcessSpace -cnotmatch $script:HordeProcessSpacePattern) { throw ("'" + $ProcessSpace + "' is not a process namespace core knows: windows, posix, synthetic or wsl:<distro>") }
    return [pscustomobject]@{ PSTypeName = "Horde.Platform"; name = $Name; processSpace = $ProcessSpace; processTable = $ProcessTable }
}

function Assert-HordePlatform {
    param($Platform)
    if ($null -eq $Platform -or @($Platform.PSObject.TypeNames) -notcontains "Horde.Platform") { throw "-Platform must be made by New-HordePlatform or Get-HordeLocalPlatform" }
}

function Read-HordePlatformProcessTable {
    # THE SEAM: a platform's process table, as an answer. Every reader of the process table in core
    # comes through here - core/identity and the projection alike.
    param($Platform)
    Assert-HordePlatform $Platform
    return (Invoke-HordeRead -What ("the " + $Platform.name + " process table") -Read { & $Platform.processTable })
}

function Read-HordeWindowsProcessTable {
    # The Windows platform's reader: core/identity's shape plus each process's command line, the
    # only involuntary witness to one conversation running in two processes (YedPool/wezfleet
    # lib/Common.ps1:656-662, "THE COMMAND LINE IS THE ONLY INVOLUNTARY WITNESS"). Read-only CIM,
    # which opens no process handle.
    #
    # WHAT IS MEASURED AND WHAT IS NOT (review finding 8 of PR #19). CIM gives CreationDate as a local
    # time, converted here with ToUniversalTime. Cross-checked 2026-09-30: for 10 of 10 live control
    # files, CIM's time, .NET's Process.StartTime and procStart agreed to the microsecond, and .NET's
    # ticks equalled procStart's exactly; across all 339 processes readable both ways, CIM and .NET
    # agreed to the microsecond. All of them started and were read in the same daylight-saving period.
    # UNMEASURED: a process started before a daylight-saving change and read after it, and above all
    # one started in the hour the clocks repeat, where a local time names two instants and the
    # conversion can land an hour off - which would read a live process as a reused pid.
    return (Invoke-HordeRead -What "the process table" -Read {
        $t = @{}
        foreach ($p in @(Get-CimInstance -ClassName Win32_Process -Property ProcessId, Name, CreationDate, CommandLine -ErrorAction Stop)) {
            $created = $null
            if ($null -ne $p.CreationDate) { $created = ([datetime]$p.CreationDate).ToUniversalTime() }
            $t[[int]$p.ProcessId] = [pscustomobject]@{ pid = [int]$p.ProcessId; name = "$($p.Name)"; created = $created; commandLine = $p.CommandLine }
        }
        return $t
    })
}

function Get-HordeLocalPlatform {
    # The platform Horde runs on today. The one place core names the Windows process namespace.
    return (New-HordePlatform -Name "windows" -ProcessSpace "windows" -ProcessTable { Read-HordeWindowsProcessTable })
}

# POWER THROTTLING (EcoQoS). Measured 2026-10-02 on the development machine (the SSH agent's probe):
# Windows slows a busy background process about 3 s after it starts - an empty PowerShell function
# call went from 23 us to 165 us, and pure .NET ran at about half speed - and opting the process out of
# execution-speed throttling removed the slowdown entirely. The opt-out is per process and is NOT
# inherited: a grandchild of an opted-out process read back ControlMask=0 (measured the same day), so
# every process that does sustained work opts itself out, or is opted out by the process that started
# it. Nothing here changes a system power setting; the call touches only the given process.
#
# THE TYPE IS COMPILED ONCE PER PROCESS, on first use. Add-Type measured 198 ms here on 2026-10-02
# (the 1 s first reported includes PowerShell's own first-use warm-up); loading a precompiled DLL
# measured 112 ms, too little gain to justify a cached binary on disk. The type name carries a version
# so a later change to it is a new type, never a clash with one already loaded in the session.
#
# NOT WINDOWS: there is no such throttling to opt out of, and the answer is absent with that note.
$script:HordePowerTypeName = "HordePowerThrottlingV1"
$script:HordePowerSource = @"
using System;
using System.Runtime.InteropServices;
public static class HordePowerThrottlingV1 {
    [StructLayout(LayoutKind.Sequential)]
    public struct State { public uint Version; public uint ControlMask; public uint StateMask; }
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetProcessInformation(IntPtr process, int infoClass, ref State info, uint size);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetProcessInformation(IntPtr process, int infoClass, ref State info, uint size);
    [DllImport("kernel32.dll")] public static extern IntPtr GetCurrentProcess();
    // ProcessPowerThrottling is information class 4; PROCESS_POWER_THROTTLING_EXECUTION_SPEED is 1.
    // ControlMask 1 with StateMask 0 means: this process decides execution speed, and decides OFF.
    public static int OptOut(IntPtr process) {
        var s = new State { Version = 1, ControlMask = 1, StateMask = 0 };
        return SetProcessInformation(process, 4, ref s, (uint)Marshal.SizeOf(s)) ? 0 : Marshal.GetLastWin32Error();
    }
    public static uint[] Read(IntPtr process) {
        var s = new State { Version = 1 };
        if (!GetProcessInformation(process, 4, ref s, (uint)Marshal.SizeOf(s))) { return new uint[] { 0xFFFFFFFF, (uint)Marshal.GetLastWin32Error() }; }
        return new uint[] { s.ControlMask, s.StateMask };
    }
}
"@

function Test-HordeIsWindows {
    param($OsPlatform = [System.Environment]::OSVersion.Platform)
    return [bool]("" + $OsPlatform -ceq "Win32NT")
}

function Initialize-HordePowerType {
    if (-not ($script:HordePowerTypeName -as [type])) { Add-Type -TypeDefinition $script:HordePowerSource }
}

function Set-HordeThrottlingOptOut {
    # Opt a process - this one by default, or one given by its System.Diagnostics.Process - out of
    # execution-speed power throttling. Known "set", absent off Windows, or unknown with the error.
    param($Process = $null, $OsPlatform = [System.Environment]::OSVersion.Platform)
    if (-not (Test-HordeIsWindows -OsPlatform $OsPlatform)) { return (New-HordeAbsent -Note ("not Windows (" + $OsPlatform + "): there is no execution-speed throttling to opt out of")) }
    try {
        Initialize-HordePowerType
        $h = $(if ($null -eq $Process) { [HordePowerThrottlingV1]::GetCurrentProcess() } else { $Process.Handle })
        $err = [HordePowerThrottlingV1]::OptOut($h)
        if ($err -ne 0) { return (New-HordeUnknown -Reason ("SetProcessInformation refused the opt-out, error " + $err)) }
        return (New-HordeKnown -Value "set")
    } catch { return (New-HordeUnknown -Reason "the throttling opt-out could not be applied" -ErrorRecord $_) }
}

function Get-HordeThrottlingState {
    # A process's throttling state as an answer: known { controlMask; stateMask; optedOut }, absent off
    # Windows, unknown when it cannot be read. optedOut is true only for ControlMask with bit 1 set and
    # StateMask with bit 1 clear - this process decides execution speed, and decided off.
    param($Process = $null, $OsPlatform = [System.Environment]::OSVersion.Platform)
    if (-not (Test-HordeIsWindows -OsPlatform $OsPlatform)) { return (New-HordeAbsent -Note ("not Windows (" + $OsPlatform + "): there is no execution-speed throttling")) }
    try {
        Initialize-HordePowerType
        $h = $(if ($null -eq $Process) { [HordePowerThrottlingV1]::GetCurrentProcess() } else { $Process.Handle })
        $r = [HordePowerThrottlingV1]::Read($h)
        if ($r[0] -eq [uint32]::MaxValue) { return (New-HordeUnknown -Reason ("GetProcessInformation failed, error " + $r[1])) }
        return (New-HordeKnown -Value ([pscustomobject]@{ controlMask = [int]$r[0]; stateMask = [int]$r[1]; optedOut = [bool](($r[0] -band 1) -eq 1 -and ($r[1] -band 1) -eq 0) }))
    } catch { return (New-HordeUnknown -Reason "the throttling state could not be read" -ErrorRecord $_) }
}
