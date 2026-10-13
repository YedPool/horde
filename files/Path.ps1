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
# So Get-HordeFilesNetworkRefusal is asked FIRST, and it touches no disk and no network:
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
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It loads nothing.

function Get-HordeFilesNetworkRefusal {
    # Why -Path is a network path, or "" when nothing says it is. THE FIRST QUESTION ASKED OF A PATH,
    # and it touches no disk and no network: the header has the measurement. Asked of the path as
    # written and again of the path it resolves to.
    param([AllowEmptyString()][string]$Path)
    $local = "only a file on one of this machine's own drives is shared: name it by its local path, or copy it to a local folder"
    # Two separators of either kind first, unless what follows is the device or long-path prefix...
    $unc = ($Path -cmatch '\A[\\/]{2}' -and $Path -cnotmatch '\A[\\/]{2}[.?][\\/]')
    # ...and that prefix, or the NT one, before UNC. The letters are written out in both cases: an
    # ignore-case match asks a case table, which is what an id's input must never do.
    if (-not $unc) { $unc = ($Path -cmatch '\A(?:[\\/]{2}[.?]|\\\?\?)[\\/][Uu][Nn][Cc](?:[\\/]|\z)') }
    if ($unc) { return ("'" + $Path + "' is a network path, and " + $local) }
    if ($Path -cmatch '\A(?:\\\\\?\\)?([A-Za-z]):') {
        $letter = $Matches[1]
        $type = $null
        # A letter whose type cannot be asked is not thereby a network drive: it goes on, and the
        # open handle's own path decides.
        try { $type = (New-Object System.IO.DriveInfo($letter)).DriveType } catch { $type = $null }
        if ($type -eq [System.IO.DriveType]::Network) { return ("'" + $Path + "' is on a network drive (" + $letter + ":), and " + $local) }
    }
    return ""
}

function Get-HordeFilesPathRefusal {
    # Why the path, AS WRITTEN, is not one a file is opened from, or "" when it may be opened. A
    # network path is not this function's: Get-HordeFilesNetworkRefusal is asked before it.
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

function Initialize-HordeFilesPlaceNative {
    # Two more questions for Windows, defined once a process under a name of their own: a loaded
    # type cannot be given another member, and HordeNative.FilePath may be loaded already.
    #   QueryDosDevice  what a drive letter stands for, read from the system's own table of names.
    #   CreateFileW     to open a FOLDER, which .NET's FileStream cannot: Get-HordeFilesFolderFinalPath.
    if (([System.Management.Automation.PSTypeName]"HordeNative.FilePlace").Type) { return }
    Add-Type -Namespace HordeNative -Name FilePlace -MemberDefinition '[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern int QueryDosDevice(string lpDeviceName, System.Text.StringBuilder lpTargetPath, int ucchMax); [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern Microsoft.Win32.SafeHandles.SafeFileHandle CreateFileW(string lpFileName, int dwDesiredAccess, int dwShareMode, System.IntPtr lpSecurityAttributes, int dwCreationDisposition, int dwFlagsAndAttributes, System.IntPtr hTemplateFile);'
}

function Get-HordeFilesDriveTarget {
    # What the drive letter -Letter stands for, as Windows keeps it, or "" when it names nothing.
    # Measured 2026-10-13: C: is \Device\HarddiskVolume3; a subst drive over a folder is
    # \??\C:\that\folder; a letter aimed at a share is \??\UNC\host\share.
    param([Parameter(Mandatory = $true)][string]$Letter)
    Initialize-HordeFilesPlaceNative
    $text = New-Object System.Text.StringBuilder 1024
    if ([HordeNative.FilePlace]::QueryDosDevice($Letter + ":", $text, 1024) -le 0) { return "" }
    return $text.ToString()
}

function Get-HordeFilesAliasRefusal {
    # Why -Path is on a drive letter that STANDS FOR a network drive, or "" when nothing says it is.
    # THE FIRST QUESTION ASKED OF A DRIVE LETTER, before the network question, because that question
    # is itself the harm here. Measured 2026-10-13, a letter S: defined over R:\, R: being a network
    # drive aimed at a host that does not exist, one fresh host a step:
    #   defining S:, and asking the system's table what S: stands for   the host was NOT looked up
    #   asking the type of R:                                          the host was NOT looked up
    #   asking the type of S: (it answers NoRootDirectory, not Network) the host WAS looked up
    # So the type of a letter is asked only of a letter that stands for no other letter. The
    # system's table of names is read first (it asks no disk and no network), a letter at a time,
    # and the type is asked of the letter the chain ends in. A letter that stands for itself is the
    # network question's, and this answers "". Asked of the path as written and again of the path it
    # resolves to, as the network question is. The open handle's own path is still judged afterwards
    # (Resolve-HordeFilesLocalPath): that is the second net, not this.
    param([AllowEmptyString()][string]$Path)
    if ($Path -cnotmatch '\A(?:\\\\\?\\)?([A-Za-z]):') { return "" }
    $first = $Matches[1]
    $local = "only a file on one of this machine's own drives is shared: name it by its local path, or copy it to a local folder"
    $last = $first
    $ended = $false
    # Eight letters deep is more than anyone makes; a ring of letters never ends, and is refused.
    for ($hop = 1; $hop -le 8; $hop++) {
        $target = Get-HordeFilesDriveTarget -Letter $last
        # Anything but another drive letter is a volume, a share or nothing: the chain ends here.
        if ($target -cnotmatch '\A\\\?\?\\([A-Za-z]):') { $ended = $true; break }
        $last = $Matches[1]
    }
    if (-not $ended) { return ("'" + $Path + "' is on a drive (" + $first + ":) that stands for another drive letter, and that for another, without end: where it really is cannot be told, and " + $local) }
    if ([string]::Equals($last, $first, [System.StringComparison]::Ordinal)) { return "" }
    if ((Get-HordeFilesNetworkRefusal -Path ($last + ":\")) -ne "") { return ("'" + $Path + "' is on a drive (" + $first + ":) that stands for a network drive (" + $last + ":), and " + $local) }
    return ""
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
