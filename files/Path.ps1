# files/Path.ps1 - which file a path really names.
#
# THE ONE JOB of this file: turn "the path a caller wrote" into "the one path of the file that was
# opened", or a refusal. A file id is made from a path (files/Share.ps1 says why), and an id is
# permanent once its first record exists, so what a path IS had to be settled before any record was
# written (review of the files store, 2026-10-13).
#
# ONE FILE HAS MANY NAMES. Measured 2026-10-13 on NTFS, one file opened five ways, and what Windows
# said the open handle's final path was (GetFinalPathNameByHandle):
#   its plain path                    C:\t\a long report name.md      \\?\C:\t\a long report name.md
#   the long-path prefix              \\?\C:\t\a long report name.md  the same
#   its 8.3 short name                C:\t\ALONGR~1.MD                the same
#   a drive made with subst           Z:\a long report name.md        the same
#   a share of this machine           \\localhost\C$\t\...            \\?\UNC\localhost\C$\t\...
# So THE PATH IS ASKED OF THE OPEN HANDLE, never worked out from the text: the first four come to
# one path with no code here, and the fifth is never opened at all (below). It is asked of the SAME handle the bytes are then read from, so the
# name that is typed, checked and made into an id is the name of the bytes that are kept.
#
# A NETWORK PATH IS NEVER OPENED, AND NEVER LOOKED AT. That fifth form is the one the handle does not
# bring home: its final path is still the network one. Until 2026-10-13 a share of this machine's
# own drive was brought home by proof - the local file was opened beside it and the two handles
# compared - and every other network path was refused after it had been looked at and opened. The
# review of that found two things, and both are why this is now a refusal from the text:
#   - THE PROOF PROVED THE WRONG THING. All four compared values (the volume's serial number, the
#     file's index, its size, when it was made) are what the SERVER says, and the bytes were still
#     read from the network handle: a hostile or cloned server could have its bytes recorded under a
#     local file's id.
#   - LOOKING IS ALREADY THE HARM. Asking whether a network path exists, or opening it, sends the
#     user's sign-in to whatever host the path names.
# So whether a path is on this machine's own drives is asked FIRST (Get-HordeFilesPlaceRefusal, below),
# and the asking touches no disk and no network. The two questions behind it are core/PathText.ps1's,
# so that there is one copy for every caller: what a drive letter stands for, and then:
#   - A UNC PATH IN ANY SPELLING is refused from its text: two separators of either kind first
#     (\\server, //server, \/server; Windows reads them all as one), and the prefixed forms
#     \\?\UNC\, \\.\UNC\ and \??\UNC\, in either case and with either separator.
#   - A NETWORK DRIVE is refused by its type, asked of the drive letter. Measured 2026-10-13, on a
#     letter aimed at a host that does not exist: asking the type answered Network in under 15 ms
#     and the host was NOT looked up (no entry for it in the DNS cache); the control, asking whether
#     a file on that drive exists, left the entry. PowerShell's own path resolver, handed that
#     drive letter, DID look the host up (1289 ms, and the entry): so the question is asked of the
#     path as written, before anything resolves it, and again of the resolved path, which is where
#     a relative path or a PowerShell drive over a share shows what it is.
#   WHAT IS LEFT FOR AFTER THE OPEN: an alias the drive's type does not give away (a subst drive
#   over a network drive, a volume mount point). Its handle's final path is a network one, and
#   Resolve-HordeFilesLocalPath refuses it then, as before.
#   A file on this machine is named by its local path. A refusal can be lifted later; an id made
#   from a network name could not have been taken back.
## WHAT ELSE IS REFUSED FROM THE TEXT, BEFORE ANYTHING IS OPENED, because for these the opening is the
# harm or the handle cannot tell:
#   - A DEVICE. \\.\ before anything (measured: \\.\C:\t\x.md opens as an ordinary file, and
#     \\.\pipe\x would connect to a pipe), \\?\ before anything but a drive letter or UNC, the NT
#     form \??\, and the names DOS kept for devices - CON, PRN, AUX, NUL, COM0 to COM9, LPT0 to LPT9,
#     CONIN$, CONOUT$ - as any part of the path, with or without an extension (NUL.txt is NUL).
#   - A STREAM INSIDE A FILE (x.bin:y.txt, x.bin::$DATA): a colon anywhere after the drive letter.
#     A handle on a stream gives the FILE's path as its final path, so only the text can tell.
#     Measured: .NET refuses such a path by itself, but not behind \\?\, where the stream opens.
#     KNOWN COST: a path on a PowerShell drive whose name is not one letter (Temp:\x.md) is refused
#     by the same rule; a session names files by their paths.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced.

# The questions asked of a path before it is opened: the one copy, core's.
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\PathText.ps1")

function Get-HordeFilesPathRefusal {
    # Why the path, AS WRITTEN, is not one a file is opened from, or "" when it may be opened. A
    # network path is not this function's: Get-HordeNetworkPathRefusal (core/PathText.ps1) is asked before it.
    param([AllowEmptyString()][string]$Path)
    $rest = $Path
    # The one prefix form that still names a file on a drive; every other \\?\ and all of \\.\ and
    # \??\ is the device namespace. Both slashes: Windows reads //./ as \\.\.
    if ($rest -match '\A\\\\\?\\[A-Za-z]:\\') { $rest = $rest.Substring(4) }
    elseif ($rest -match '\A(?:[\\/]{2}[.?]|\\\?\?)[\\/]') { return ("'" + $Path + "' is in the device form (\\.\ or \\?\): it names a device, a pipe or a volume, not a file by its path") }
    foreach ($part in @($rest -split '[\\/]')) {
        # The name before its first dot or colon, without the blanks Windows drops: NUL.txt, NUL: and "NUL " are NUL.
        $base = (@($part -split '[.:]')[0]).TrimEnd(' ')
        if ($base -match '\A(?:CON|PRN|AUX|NUL|COM[0-9\u00B9\u00B2\u00B3]|LPT[0-9\u00B9\u00B2\u00B3]|CONIN\$|CONOUT\$)\z') { return ("'" + $part + "' in '" + $Path + "' is a name Windows keeps for a device (" + $base.ToUpperInvariant() + "), not a file") }
    }
    if (($rest -replace '\A[A-Za-z]:', '').Contains(":")) { return ("'" + $Path + "' has a colon after its drive letter: that names a stream inside a file, not the file; one whole file is shared") }
    return ""
}

function Initialize-HordeFilesPathNative {
    # The one thing asked of an open handle, defined once a process (core/FileAtomic.ps1's way).
    # GetFinalPathNameByHandle with flags 0: FILE_NAME_NORMALIZED and VOLUME_NAME_DOS, the long name
    # of every part, on a drive letter.
    if (([System.Management.Automation.PSTypeName]"HordeNative.FilePath").Type) { return }
    Add-Type -Namespace HordeNative -Name FilePath -MemberDefinition '[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern int GetFinalPathNameByHandle(Microsoft.Win32.SafeHandles.SafeFileHandle hFile, System.Text.StringBuilder lpszFilePath, int cchFilePath, int dwFlags);'
}

function Get-HordeFilesFinalPath {
    # The final path of an open file, as Windows gives it (\\?\C:\... or \\?\UNC\...), or "" when
    # Windows would not say: a volume with no drive letter, or a handle that is no file's.
    param([Parameter(Mandatory = $true)]$Stream)
    Initialize-HordeFilesPathNative
    $size = 520
    for ($try = 1; $try -le 2; $try++) {
        $text = New-Object System.Text.StringBuilder $size
        $length = [HordeNative.FilePath]::GetFinalPathNameByHandle($Stream.SafeFileHandle, $text, $size, 0)
        if ($length -le 0) { return "" }
        # A length that does not fit is the size to ask with, the ending NUL included.
        if ($length -lt $size) { return $text.ToString() }
        $size = $length + 1
    }
    return ""
}

function Resolve-HordeFilesLocalPath {
    # The one local path (C:\...) of an open file whose final path is -Final: { ok; path; reason }.
    # A final path that is not on a drive letter is a network one that neither its text nor its
    # drive's type gave away (the header says which), and is refused: nothing brings it home.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Final)
    $refuse = { param([string]$Why) return [pscustomobject]@{ ok = $false; path = ""; reason = $Why } }
    if ($Final -eq "") { return (& $refuse "Windows would not say where the opened file really is: it is on a volume with no drive letter, or is not a file on a disk") }
    if ($Final -cnotmatch '\A\\\\\?\\[A-Za-z]:\\') { return (& $refuse ("it is on a network share ('" + ($Final -replace '\A\\\\\?\\UNC\\', '\\') + "'), and only a file on one of this machine's own drives is shared: name it by its local path, or copy it to a local folder")) }
    return [pscustomobject]@{ ok = $true; path = $Final.Substring(4); reason = "" }
}
function Open-HordeFilesSource {
    # Open the file at -Path ONCE, for reading: { ok; stream; path; reason }. path is the one local
    # path of what was opened; stream is the handle it was asked of, which THE CALLER CLOSES when ok.
    # Others may read the file meanwhile and none may write it, so the bytes read are one state of it.
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = $null
    try { $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read) }
    catch { return [pscustomobject]@{ ok = $false; stream = $null; path = ""; reason = ("it cannot be read: " + $_.Exception.GetBaseException().Message) } }
    $where = $null
    try { $where = Resolve-HordeFilesLocalPath -Final (Get-HordeFilesFinalPath -Stream $stream) }
    finally { if ($null -eq $where -or -not $where.ok) { $stream.Dispose() } }
    if (-not $where.ok) { return [pscustomobject]@{ ok = $false; stream = $null; path = ""; reason = $where.reason } }
    return [pscustomobject]@{ ok = $true; stream = $stream; path = $where.path; reason = "" }
}

function Get-HordeFilesPlaceRefusal {
    # Why -Path is not on one of this machine's own drives, in the words of a share, or "" when
    # nothing says so. The two questions are core's (core/PathText.ps1), and THE ORDER IS PART OF
    # THE RULE: what the drive letter stands for is asked first, because for a letter that stands
    # for a network drive the network question itself looks the host up (core has the
    # measurement). Core's reasons say only that the path is not on this machine's own drives;
    # what that means for a share is said here. Asked of the path as written and again of the path
    # it resolves to, before anything looks at the disk.
    param([AllowEmptyString()][string]$Path)
    $why = Get-HordeDriveAliasRefusal -Path $Path
    if ($why -eq "") { $why = Get-HordeNetworkPathRefusal -Path $Path }
    if ($why -eq "") { return "" }
    return ($why + ". A file is shared from one of this machine's own drives: name it by its local path, or copy it to a local folder")
}

function Initialize-HordeFilesPlaceNative {
    # One more question for Windows, defined once a process under a name of its own (a loaded type
    # cannot be given another member, and HordeNative.FilePath may be loaded already): CreateFileW,
    # to open a FOLDER, which .NET's FileStream cannot. Get-HordeFilesFolderFinalPath asks with it.
    if (([System.Management.Automation.PSTypeName]"HordeNative.FilePlace").Type) { return }
    Add-Type -Namespace HordeNative -Name FilePlace -MemberDefinition '[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern Microsoft.Win32.SafeHandles.SafeFileHandle CreateFileW(string lpFileName, int dwDesiredAccess, int dwShareMode, System.IntPtr lpSecurityAttributes, int dwCreationDisposition, int dwFlagsAndAttributes, System.IntPtr hTemplateFile);'
}

function Initialize-HordeFilesIdentityNative {
    # WHICH FILE an open handle is, as the file system numbers it: GetFileInformationByHandle's volume
    # serial number and file index. Two names of one file (a hard link) give one answer, which no
    # path can (files/Deny.ps1, the relays' own files). Defined once a process, under a name of its own.
    if (([System.Management.Automation.PSTypeName]"HordeNative.FileIdentity").Type) { return }
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace HordeNative {
    public static class FileIdentity {
        [StructLayout(LayoutKind.Sequential)]
        private struct Info {
            public uint Attributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME Created, Accessed, Written;
            public uint VolumeSerial, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
        }
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandle(SafeFileHandle handle, out Info info);
        public static string Of(SafeFileHandle handle) {
            Info info;
            if (handle == null || handle.IsInvalid || !GetFileInformationByHandle(handle, out info)) { return ""; }
            return info.VolumeSerial.ToString("x8") + ":" + info.IndexHigh.ToString("x8") + info.IndexLow.ToString("x8");
        }
    }
}
"@
}

function Get-HordeFilesHandleIdentity {
    # The identity of an open file (Initialize-HordeFilesIdentityNative), or "" when Windows would not
    # give it. KNOWN LIMIT: the file index is 64 bits; a volume whose ids are 128 bits (ReFS) may give
    # two files one index, which errs towards refusing.
    param([Parameter(Mandatory = $true)]$Handle)
    Initialize-HordeFilesIdentityNative
    return [HordeNative.FileIdentity]::Of($Handle)
}

function Get-HordeFilesPathIdentity {
    # The identity of the file at -Path: { state: ok | absent | unknown; id }. It is opened for its
    # attributes only (FILE_READ_ATTRIBUTES, 0x80): not one byte of it is read.
    param([Parameter(Mandatory = $true)][string]$Path)
    Initialize-HordeFilesPlaceNative
    # OPEN_EXISTING (3), and FILE_FLAG_BACKUP_SEMANTICS (0x02000000) as for a folder, so that whatever
    # the relay named opens.
    $openExisting = 3
    $backupSemantics = 0x02000000
    $handle = [HordeNative.FilePlace]::CreateFileW($Path, 0x80, 7, [System.IntPtr]::Zero, $openExisting, $backupSemantics, [System.IntPtr]::Zero)
    $code = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if ($handle.IsInvalid) {
        if (@(2, 3) -contains $code) { return [pscustomobject]@{ state = "absent"; id = "" } }
        return [pscustomobject]@{ state = "unknown"; id = "" }
    }
    try { $id = Get-HordeFilesHandleIdentity -Handle $handle } finally { $handle.Dispose() }
    if ($id -eq "") { return [pscustomobject]@{ state = "unknown"; id = "" } }
    return [pscustomobject]@{ state = "ok"; id = $id }
}

function Get-HordeFilesFolderFinalPath {
    # Where the FOLDER at -Path really is: { state: ok | absent | unknown; path }. path is what
    # Windows says of the open folder (\\?\C:\...), by the same question a shared file's handle is
    # asked, so a folder and a file inside it are compared like with like. Measured 2026-10-13, one
    # folder opened by its plain path, a junction, a symbolic link, a subst drive, in capitals, and
    # with a dot or a blank after its name: one final path for all seven.
    #   absent   nothing has that name (Win32 2 or 3): no file can be inside it.
    #   unknown  it is there and could not be opened or asked: the caller must not take it for absent.
    param([Parameter(Mandatory = $true)][string]$Path)
    Initialize-HordeFilesPlaceNative
    # No access is asked for (0): only the name is wanted. Every sharing mode (7), so nobody is kept
    # out. OPEN_EXISTING (3). FILE_FLAG_BACKUP_SEMANTICS (0x02000000), without which a folder does
    # not open.
    $handle = [HordeNative.FilePlace]::CreateFileW($Path, 0, 7, [System.IntPtr]::Zero, 3, 0x02000000, [System.IntPtr]::Zero)
    $code = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if ($handle.IsInvalid) {
        if ($code -eq 2 -or $code -eq 3) { return [pscustomobject]@{ state = "absent"; path = "" } }
        return [pscustomobject]@{ state = "unknown"; path = "" }
    }
    # Asked as a file's is: the one function, handed the handle the way a stream holds it.
    try { $final = Get-HordeFilesFinalPath -Stream ([pscustomobject]@{ SafeFileHandle = $handle }) } finally { $handle.Dispose() }
    if ($final -eq "") { return [pscustomobject]@{ state = "unknown"; path = "" } }
    return [pscustomobject]@{ state = "ok"; path = $final }
}
