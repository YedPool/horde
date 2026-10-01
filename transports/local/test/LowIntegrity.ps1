# transports/local/test/LowIntegrity.ps1 - start a process of THIS user at LOW integrity, for
# test-local.ps1. A low-integrity process of the same user is the attacker the review of PR #42 used
# (a sandboxed browser tab, a downloaded tool run under a lowered token): same SID, so an owner check
# alone cannot tell it from the user. Built from the reviewer's probe: duplicate this process's token,
# set its integrity label to Low (S-1-16-4096), and CreateProcessAsUser with it - no privilege needed
# to lower one's own token.
#
# Also makes a folder the low process can write its report to: a low-integrity process cannot write
# to the user's ordinary (medium-labelled) folders, so the folder is labelled low with icacls.

if (-not ([System.Management.Automation.PSTypeName]"HordeLowIntegrity").Type) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class HordeLowIntegrity {
    [StructLayout(LayoutKind.Sequential)] struct SID_AND_ATTRIBUTES { public IntPtr Sid; public uint Attributes; }
    [StructLayout(LayoutKind.Sequential)] struct TOKEN_MANDATORY_LABEL { public SID_AND_ATTRIBUTES Label; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO { public int cb; public string reserved, desktop, title; public int x, y, xs, ys, xc, yc, fill, flags; public short show, cbReserved2; public IntPtr reserved2, stdIn, stdOut, stdErr; }
    [StructLayout(LayoutKind.Sequential)] struct PROCESS_INFORMATION { public IntPtr process, thread; public int pid, tid; }
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr p, uint a, out IntPtr t);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool DuplicateTokenEx(IntPtr t, uint a, IntPtr sa, int il, int tt, out IntPtr nt);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool ConvertStringSidToSid(string s, out IntPtr sid);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool SetTokenInformation(IntPtr t, int c, ref TOKEN_MANDATORY_LABEL i, int l);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool CreateProcessAsUser(IntPtr t, string app, string cmd, IntPtr pa, IntPtr ta, bool inh, uint f, IntPtr env, string dir, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr p);

    // The new process's id, or a negative Win32 error.
    public static int Start(string commandLine) {
        IntPtr tok, dup, sid;
        if (!OpenProcessToken(GetCurrentProcess(), 0x0002 | 0x0080 | 0x0008 | 0x0001, out tok)) return -Marshal.GetLastWin32Error();
        try {
            if (!DuplicateTokenEx(tok, 0x02000000, IntPtr.Zero, 2, 1, out dup)) return -Marshal.GetLastWin32Error();
            try {
                if (!ConvertStringSidToSid("S-1-16-4096", out sid)) return -Marshal.GetLastWin32Error();
                try {
                    TOKEN_MANDATORY_LABEL l = new TOKEN_MANDATORY_LABEL();
                    l.Label.Sid = sid;
                    l.Label.Attributes = 0x20;
                    if (!SetTokenInformation(dup, 25, ref l, Marshal.SizeOf(l) + 12)) return -Marshal.GetLastWin32Error();
                    STARTUPINFO si = new STARTUPINFO();
                    si.cb = Marshal.SizeOf(si);
                    si.flags = 1;
                    si.show = 0;
                    PROCESS_INFORMATION pi;
                    if (!CreateProcessAsUser(dup, null, commandLine, IntPtr.Zero, IntPtr.Zero, false, 0x08000000, IntPtr.Zero, null, ref si, out pi)) return -Marshal.GetLastWin32Error();
                    CloseHandle(pi.thread);
                    CloseHandle(pi.process);
                    return pi.pid;
                } finally { LocalFree(sid); }
            } finally { CloseHandle(dup); }
        } finally { CloseHandle(tok); }
    }
}
'@
}

function New-HordeLowFolder {
    # A fresh folder under TEMP that a low-integrity process may write to. Returns its path.
    $dir = Join-Path $env:TEMP ("horde-lowil-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $dir | Out-Null
    $icacls = Join-Path $env:WINDIR "System32\icacls.exe"
    $null = & $icacls $dir /setintegritylevel "(OI)(CI)low"
    if ($LASTEXITCODE -ne 0) { throw ("icacls could not label " + $dir + " low (exit " + $LASTEXITCODE + ")") }
    return $dir
}

function Start-HordeLowChild {
    # Run transports/local/test/low-child.ps1 at low integrity with -Mode and -Pipe, reporting to a
    # file in -Folder. Returns { pid; out }.
    param([string]$Mode, [string]$Pipe, [string]$Folder)
    $out = Join-Path $Folder ($Mode + "-" + [guid]::NewGuid().ToString("N") + ".txt")
    $ps = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    $child = Join-Path $PSScriptRoot "low-child.ps1"
    $cmd = '"' + $ps + '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $child + '" -Mode ' + $Mode + ' -Pipe ' + $Pipe + ' -Out "' + $out + '"'
    $id = [HordeLowIntegrity]::Start($cmd)
    if ($id -lt 0) { throw ("could not start a low-integrity process: Win32 error " + (-$id)) }
    return [pscustomobject]@{ pid = $id; out = $out }
}

function Wait-HordeLowLine {
    # Wait up to -Ms for the child's report to hold a line matching -Pattern. True if it does.
    param([string]$Out, [string]$Pattern, [int]$Ms)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $Ms) {
        if (Test-Path -LiteralPath $Out) {
            $text = ""
            try { $text = [System.IO.File]::ReadAllText($Out) } catch { }
            if ($text -match $Pattern) { return $true }
        }
        Start-Sleep -Milliseconds 100
    }
    return $false
}
