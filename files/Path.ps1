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
# one path with no code here. It is asked of the SAME handle the bytes are then read from, so the
# name that is typed, checked and made into an id is the name of the bytes that are kept.
#
# A SHARE OF THIS MACHINE is the one form the handle does not bring home: its final path is still the
# network one. It is brought home by PROOF, not by its words. For \\<any server>\<letter>$\<rest> the
# file <letter>:\<rest> is opened beside it and the two open handles are asked who they are: the
# volume's serial number, the file's index on it, its size and when it was made. The same answers
# mean one file, and the local handle's own final path is used. The server's name is never looked
# at: a list of this machine's names always misses one (an address, an alias in a hosts file), and a
# missed name would give one file two ids.
#   WHAT IS REFUSED, because nothing here can prove where it is: a file on any other share, of this
#   machine or another (a mapped network drive is one of those). A network path made into an id
#   would fork the day the same file is named by an address instead of a name, and an id cannot be
#   taken back; a refusal can be lifted later.
#   KNOWN LIMIT: two machines made from one disk image have the same volume serial, and a file
#   untouched since has the same index, size and time on both. \\<the other>\C$\<that file> would be
#   taken for the local one. Those two files are then byte for byte the same file.
#
# WHAT IS REFUSED FROM THE TEXT, BEFORE ANYTHING IS OPENED, because for these the opening is the harm
# or the handle cannot tell:
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
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It loads nothing.

function Get-HordeFilesPathRefusal {
    # Why the path, AS WRITTEN, is not one a file is opened from, or "" when it may be opened.
    param([AllowEmptyString()][string]$Path)
    $rest = $Path
    # The two prefix forms that still name a file on a drive or a share; every other \\?\ and all of
    # \\.\ and \??\ is the device namespace. Both slashes: Windows reads //./ as \\.\.
    if ($rest -match '\A\\\\\?\\UNC\\') { $rest = $rest.Substring(8) }
    elseif ($rest -match '\A\\\\\?\\[A-Za-z]:\\') { $rest = $rest.Substring(4) }
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
    # The two things asked of an open handle, defined once a process (core/FileAtomic.ps1's way).
    # GetFinalPathNameByHandle with flags 0: FILE_NAME_NORMALIZED and VOLUME_NAME_DOS, the long name
    # of every part, on a drive letter. BY_HANDLE_FILE_INFORMATION is written as thirteen 32-bit
    # fields: with its three times as 64-bit fields the compiler pads after the first field and every
    # later one is read four bytes off (measured 2026-10-13: the serial number read as 0).
    if (([System.Management.Automation.PSTypeName]"HordeNative.FilePath").Type) { return }
    Add-Type -Namespace HordeNative -Name FilePath -MemberDefinition '[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern int GetFinalPathNameByHandle(Microsoft.Win32.SafeHandles.SafeFileHandle hFile, System.Text.StringBuilder lpszFilePath, int cchFilePath, int dwFlags); [StructLayout(LayoutKind.Sequential)] public struct Info { public uint Attributes; public uint CreationLow; public uint CreationHigh; public uint AccessLow; public uint AccessHigh; public uint WriteLow; public uint WriteHigh; public uint VolumeSerial; public uint SizeHigh; public uint SizeLow; public uint Links; public uint IndexHigh; public uint IndexLow; } [DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetFileInformationByHandle(Microsoft.Win32.SafeHandles.SafeFileHandle hFile, out Info lpFileInformation);'
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

function Get-HordeFilesIdentity {
    # Who an open file is, as text two handles on one file agree on: the volume's serial number, the
    # file's index on that volume, its size and when it was made. "" when Windows would not say, or
    # gives no index: a file system that numbers nothing cannot prove anything.
    param([Parameter(Mandatory = $true)]$Stream)
    Initialize-HordeFilesPathNative
    $info = New-Object HordeNative.FilePath+Info
    if (-not [HordeNative.FilePath]::GetFileInformationByHandle($Stream.SafeFileHandle, [ref]$info)) { return "" }
    if ($info.IndexHigh -eq 0 -and $info.IndexLow -eq 0) { return "" }
    return (@($info.VolumeSerial, $info.IndexHigh, $info.IndexLow, $info.SizeHigh, $info.SizeLow, $info.CreationHigh, $info.CreationLow) -join ":")
}

function Test-HordeFilesSameFile {
    # Are two identities (Get-HordeFilesIdentity) one file's? An identity that could not be read is
    # nobody's: two files that both gave none are NOT thereby the same file.
    param([AllowEmptyString()][string]$One, [AllowEmptyString()][string]$Other)
    return ($One -ne "" -and $One -ceq $Other)
}

function Resolve-HordeFilesLocalPath {
    # The one local path (C:\...) of the open file -Stream, whose final path is -Final:
    # { ok; path; reason }. The header says how a share of this machine is brought home, and why
    # every other network path is refused.
    param([Parameter(Mandatory = $true)]$Stream, [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Final)
    $refuse = { param([string]$Why) return [pscustomobject]@{ ok = $false; path = ""; reason = $Why } }
    if ($Final -eq "") { return (& $refuse "Windows would not say where the opened file really is: it is on a volume with no drive letter, or is not a file on a disk") }
    if ($Final -cmatch '\A\\\\\?\\[A-Za-z]:\\') { return [pscustomobject]@{ ok = $true; path = $Final.Substring(4); reason = "" } }
    $shown = $Final -replace '\A\\\\\?\\UNC\\', '\\'
    $network = "it is on a network share ('" + $shown + "'), and only a file on one of this machine's own drives is shared: name it by its local path, or copy it to a local folder"
    if ($Final -notmatch '\A\\\\\?\\UNC\\[^\\]+\\([A-Za-z])\$\\(.+)\z') { return (& $refuse $network) }
    # Behind the long-path prefix, so that a path past 260 characters opens too.
    $candidate = "\\?\" + $Matches[1] + ":\" + $Matches[2]
    $mine = Get-HordeFilesIdentity -Stream $Stream
    $beside = $null
    # Opened for nothing but to be asked who it is: it shares everything, and no byte of it is read.
    try { $beside = New-Object System.IO.FileStream($candidate, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)) } catch { return (& $refuse $network) }
    try {
        $local = Get-HordeFilesFinalPath -Stream $beside
        if (-not (Test-HordeFilesSameFile -One $mine -Other (Get-HordeFilesIdentity -Stream $beside)) -or $local -cnotmatch '\A\\\\\?\\[A-Za-z]:\\') { return (& $refuse $network) }
        return [pscustomobject]@{ ok = $true; path = $local.Substring(4); reason = "" }
    } finally { $beside.Dispose() }
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
    try { $where = Resolve-HordeFilesLocalPath -Stream $stream -Final (Get-HordeFilesFinalPath -Stream $stream) }
    finally { if ($null -eq $where -or -not $where.ok) { $stream.Dispose() } }
    if (-not $where.ok) { return [pscustomobject]@{ ok = $false; stream = $null; path = ""; reason = $where.reason } }
    return [pscustomobject]@{ ok = $true; stream = $stream; path = $where.path; reason = "" }
}
