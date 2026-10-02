# transports/ssh/Native.ps1 - the Win32 job object that ties ssh.exe's life to the link that holds it.
#
# WHY (review of PR #68, round 3, F7; the founder's rule that orphans are prevented structurally). A
# finally in Open stops ssh.exe when Open fails, but nothing in PowerShell runs when the Horde process
# itself dies, or when a caller drops a link without closing it. A job object created with
# JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE kills every process in it when its last handle closes, and the OS
# closes every handle of a process that dies. So ssh.exe is assigned to such a job right after it
# starts, and the only handle is held by the link's channel: closing the channel, the handle being
# collected, or Horde dying each end ssh.exe. Measured for the lifecycle plan (J-3, 2026-09-30): a
# process already inside the desktop's ambient job can be assigned to a new job (they nest), and a
# process in a kill-on-close job dies when the job's last handle closes.
#
# THE WINDOW. .NET starts a process running, not suspended, so there is one statement between the
# start and the assignment, both inside Start-HordeSshProcess. ssh.exe starts no program of its own with the options Horde pins
# (ProxyCommand, LocalCommand and KnownHostsCommand none), so nothing it could start in that window
# escapes the job; Open's try begins before the start, so a failure there is still stopped by the
# finally. Only Horde dying inside that one statement would leave ssh.exe outside the job.
#
# The C# below is pinned by SHA-256 in transports/ssh/test/ExecGuard.ps1: the guard cannot read C#, so
# a change to it is a finding until the pin is changed with it, in review.
# Compiled once per process with Add-Type; a second load finds the type and skips it.

if (-not ([System.Management.Automation.PSTypeName]"HordeSshNative").Type) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public sealed class HordeSshJob : SafeHandleZeroOrMinusOneIsInvalid {
    public HordeSshJob() : base(true) { }
    protected override bool ReleaseHandle() { return HordeSshNative.CloseHandle(handle); }
}

public static class HordeSshNative {
    [StructLayout(LayoutKind.Sequential)]
    struct BASIC_LIMIT {
        public long PerProcessUserTimeLimit; public long PerJobUserTimeLimit; public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize; public UIntPtr MaximumWorkingSetSize; public uint ActiveProcessLimit;
        public UIntPtr Affinity; public uint PriorityClass; public uint SchedulingClass;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct IO_COUNTERS {
        public ulong ReadOperationCount; public ulong WriteOperationCount; public ulong OtherOperationCount;
        public ulong ReadTransferCount; public ulong WriteTransferCount; public ulong OtherTransferCount;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct EXTENDED_LIMIT {
        public BASIC_LIMIT BasicLimitInformation; public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit; public UIntPtr JobMemoryLimit; public UIntPtr PeakProcessMemoryUsed; public UIntPtr PeakJobMemoryUsed;
    }
    const int JobObjectExtendedLimitInformation = 9;
    const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000;

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern HordeSshJob CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetInformationJobObject(HordeSshJob job, int infoClass, ref EXTENDED_LIMIT info, uint length);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool AssignProcessToJobObject(HordeSshJob job, IntPtr process);
    [DllImport("kernel32.dll", SetLastError = true)] internal static extern bool CloseHandle(IntPtr handle);

    // A new, unnamed job that kills every process in it when its last handle closes.
    public static HordeSshJob NewKillOnCloseJob() {
        HordeSshJob job = CreateJobObject(IntPtr.Zero, null);
        if (job.IsInvalid) { throw new Win32Exception(Marshal.GetLastWin32Error()); }
        EXTENDED_LIMIT info = new EXTENDED_LIMIT();
        info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, ref info, (uint)Marshal.SizeOf(typeof(EXTENDED_LIMIT)))) {
            int err = Marshal.GetLastWin32Error();
            job.Dispose();
            throw new Win32Exception(err);
        }
        return job;
    }

    // Put a running process into the job. Throws if Windows refuses.
    public static void Assign(HordeSshJob job, IntPtr process) {
        if (!AssignProcessToJobObject(job, process)) { throw new Win32Exception(Marshal.GetLastWin32Error()); }
    }
}
'@
}
