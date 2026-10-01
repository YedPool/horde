# transports/local/Native.ps1 - the Win32 calls the local pipe needs that .NET Framework does not offer.
#
# WHY NATIVE (review of PR #42, 2026-09-30). The reviewer measured a LOW-integrity process of the same
# user creating \\.\pipe\horde-node-<id> before the node did; the hub connected, read the pipe's owner
# - the same user, since integrity is not part of the owner - accepted it as verified, and sent it
# session.spawn. And a low-integrity process could open the node's pipe read-only and read what the
# node sent, because a pipe with no mandatory label gets the default, No-Write-Up only. Closing both
# needs four things System.IO.Pipes cannot do on .NET Framework 4:
#   - GetNamedPipeServerProcessId / GetNamedPipeClientProcessId: who is at the other end;
#   - the integrity level and image path of that process;
#   - CreateNamedPipe with a mandatory label (S:(ML;;NWNR;;;ME)), FILE_FLAG_FIRST_PIPE_INSTANCE (fail if
#     anyone already holds the name) and PIPE_REJECT_REMOTE_CLIENTS (refuse connections that arrive
#     over the network);
#   - reading the label back, which PipeSecurity does not include.
#
# Compiled once per process with Add-Type; a second load finds the type and skips it.

if (-not ([System.Management.Automation.PSTypeName]"HordeLocalNative").Type) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

public static class HordeLocalNative {
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetNamedPipeServerProcessId(SafePipeHandle h, out uint pid);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetNamedPipeClientProcessId(SafePipeHandle h, out uint pid);
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool CloseHandle(IntPtr h);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr p, uint access, out IntPtr tok);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool GetTokenInformation(IntPtr tok, int cls, IntPtr info, int len, out int ret);
    [DllImport("advapi32.dll")] static extern IntPtr GetSidSubAuthority(IntPtr sid, uint n);
    [DllImport("advapi32.dll")] static extern IntPtr GetSidSubAuthorityCount(IntPtr sid);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool QueryFullProcessImageName(IntPtr p, int flags, StringBuilder name, ref int size);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern SafePipeHandle CreateNamedPipe(string name, uint openMode, uint pipeMode, uint maxInst, uint outBuf, uint inBuf, uint timeout, ref SECURITY_ATTRIBUTES sa);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool ConvertStringSecurityDescriptorToSecurityDescriptor(string sddl, uint rev, out IntPtr sd, out uint size);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool ConvertSecurityDescriptorToStringSecurityDescriptor(IntPtr sd, uint rev, uint info, out IntPtr text, out uint len);
    [DllImport("advapi32.dll", SetLastError = true)] static extern uint GetSecurityInfo(SafeHandle h, int objType, uint info, IntPtr owner, IntPtr group, IntPtr dacl, IntPtr sacl, out IntPtr sd);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr p);

    [StructLayout(LayoutKind.Sequential)]
    struct SECURITY_ATTRIBUTES { public int nLength; public IntPtr lpSecurityDescriptor; public int bInheritHandle; }

    const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
    const uint TOKEN_QUERY = 0x0008;
    const int TokenIntegrityLevel = 25;
    const uint PIPE_ACCESS_DUPLEX = 0x3;
    const uint FILE_FLAG_OVERLAPPED = 0x40000000;
    const uint FILE_FLAG_FIRST_PIPE_INSTANCE = 0x00080000;
    const uint PIPE_REJECT_REMOTE_CLIENTS = 0x8;
    const uint PIPE_UNLIMITED_INSTANCES = 255;
    const uint LABEL_SECURITY_INFORMATION = 0x10;
    const int SE_KERNEL_OBJECT = 6;

    // The process at the far end of a pipe, or a negative Win32 error.
    public static long ServerPid(SafePipeHandle h) { uint p; if (GetNamedPipeServerProcessId(h, out p)) return p; return -Marshal.GetLastWin32Error(); }
    public static long ClientPid(SafePipeHandle h) { uint p; if (GetNamedPipeClientProcessId(h, out p)) return p; return -Marshal.GetLastWin32Error(); }

    // A process's integrity level as its RID (4096 low, 8192 medium, 12288 high, 16384 system), or -1
    // when it cannot be read - which callers treat as below every level.
    public static int Integrity(uint pid) {
        IntPtr proc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (proc == IntPtr.Zero) return -1;
        IntPtr tok = IntPtr.Zero;
        IntPtr buf = IntPtr.Zero;
        try {
            if (!OpenProcessToken(proc, TOKEN_QUERY, out tok)) return -1;
            int len;
            GetTokenInformation(tok, TokenIntegrityLevel, IntPtr.Zero, 0, out len);
            if (len <= 0) return -1;
            buf = Marshal.AllocHGlobal(len);
            if (!GetTokenInformation(tok, TokenIntegrityLevel, buf, len, out len)) return -1;
            IntPtr sid = Marshal.ReadIntPtr(buf);
            int count = Marshal.ReadByte(GetSidSubAuthorityCount(sid));
            if (count < 1) return -1;
            return Marshal.ReadInt32(GetSidSubAuthority(sid, (uint)(count - 1)));
        } finally {
            if (buf != IntPtr.Zero) Marshal.FreeHGlobal(buf);
            if (tok != IntPtr.Zero) CloseHandle(tok);
            CloseHandle(proc);
        }
    }

    // A process's executable path, or "" when it cannot be read.
    public static string Image(uint pid) {
        IntPtr proc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (proc == IntPtr.Zero) return "";
        try {
            StringBuilder sb = new StringBuilder(1024);
            int size = sb.Capacity;
            if (!QueryFullProcessImageName(proc, 0, sb, ref size)) return "";
            return sb.ToString();
        } finally { CloseHandle(proc); }
    }

    // A server instance of the pipe at fullName, overlapped, rejecting remote clients, with the
    // security descriptor sddl. first: fail if the name already exists (anyone's). On failure the
    // handle is invalid and error holds the Win32 code.
    public static SafePipeHandle CreateServer(string fullName, string sddl, bool first, uint bufBytes, out int error) {
        IntPtr sd; uint sdLen;
        error = 0;
        if (!ConvertStringSecurityDescriptorToSecurityDescriptor(sddl, 1, out sd, out sdLen)) { error = Marshal.GetLastWin32Error(); return new SafePipeHandle(IntPtr.Zero, true); }
        try {
            SECURITY_ATTRIBUTES sa = new SECURITY_ATTRIBUTES();
            sa.nLength = Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES));
            sa.lpSecurityDescriptor = sd;
            sa.bInheritHandle = 0;
            uint mode = PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED;
            if (first) mode |= FILE_FLAG_FIRST_PIPE_INSTANCE;
            SafePipeHandle h = CreateNamedPipe(fullName, mode, PIPE_REJECT_REMOTE_CLIENTS, PIPE_UNLIMITED_INSTANCES, bufBytes, bufBytes, 0, ref sa);
            if (h.IsInvalid) error = Marshal.GetLastWin32Error();
            return h;
        } finally { LocalFree(sd); }
    }

    // The mandatory label of a kernel object, as SDDL ("S:(ML;;NWNR;;;ME)"), or "" when there is none
    // or it cannot be read.
    public static string LabelSddl(SafeHandle h) {
        IntPtr sd;
        if (GetSecurityInfo(h, SE_KERNEL_OBJECT, LABEL_SECURITY_INFORMATION, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, out sd) != 0) return "";
        try {
            IntPtr text; uint len;
            if (!ConvertSecurityDescriptorToStringSecurityDescriptor(sd, 1, LABEL_SECURITY_INFORMATION, out text, out len)) return "";
            try { return Marshal.PtrToStringUni(text); } finally { LocalFree(text); }
        } finally { LocalFree(sd); }
    }
}
'@
}
