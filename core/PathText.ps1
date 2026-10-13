# core/PathText - three questions answered of a path without opening it: its letters A to Z in one
# case, whether its text names a place on the network, and whether its drive letter stands for one.
#
# WHY ITS OWN FILE. Both were written for the files store (files/Share.ps1, files/Path.ps1; the review
# of its pull request #215, 2026-10-13). The decisions code needs the same two answers: it makes
# names from a folded path, and it resolves paths a caller wrote. Core does not load files, and two
# copies of a rule drift, so there is one definition here and files calls it. Neither function was
# changed by the move: the file id pinned in test/test-files-store.ps1 is the number it was.
#
# ConvertTo-HordeAsciiLower - FOR TEXT THAT GOES INTO SOMETHING PERMANENT OR SHARED BETWEEN RUNTIMES:
# an id, a digest, the name of an object two processes must both find.
#   WHAT IT DOES: the 26 letters A to Z become a to z. Every other character is left exactly as it is.
#   WHY NOT ToLowerInvariant: that reads the runtime's own case table, and the tables differ.
#   Measured 2026-10-13 on one machine, three characters: Windows PowerShell 5.1 leaves U+1E9E,
#   U+2126 and U+A7AE as they are, and PowerShell 7.6.6 makes them U+00DF, U+03C9 and U+026A. So one
#   path, folded by the table and hashed, was one file id under the first runtime and another under
#   the second; a path with none of those characters was one id under both (the control).
#   WHAT IT DOES NOT DO: it is not a lower-casing of text for people, and it knows no alphabet but
#   A to Z. E acute stays E acute. KNOWN COST for whoever makes an id with it: a file renamed to
#   another case of a letter outside A to Z is another text, so another id.
#   A TRAP FOR WHOEVER TESTS A CALLER: under 5.1 those three characters are not changed by
#   ToLowerInvariant either, so on 5.1 they cannot show that the runtime's table came back. U+00C9
#   can: 5.1's table changes it.
#
# Get-HordeNetworkPathRefusal - THE FIRST QUESTION TO ASK OF A PATH A CALLER WROTE, before anything
# resolves it, asks whether it exists, or opens it.
#   WHY FIRST: looking is already the harm. Asking whether a network path exists, or opening it,
#   sends the user's sign-in to whatever host the path names.
#   WHAT IT DOES: answers "" or the reason, and touches no disk and no network.
#   - A UNC PATH IN ANY SPELLING is seen in its text: two separators of either kind first
#     (\\server, //server, \/server, /\server; Windows reads them all as one), and the prefixed
#     forms \\?\UNC\, \\.\UNC\ and \??\UNC\, in either case and with either separator.
#   - A NETWORK DRIVE is seen by its type, asked of the drive letter (also behind \\?\, in small
#     letters, and written R:x). Measured 2026-10-13, on a letter aimed at a host that does not
#     exist: asking the type took 0 to 13 ms and left NOTHING in the DNS cache for that host; the
#     control, asking whether a file on that drive exists, left the entry. THAT MEASUREMENT NEEDED
#     A REAL LETTER, and is not run by any suite any more: the type is asked through one function
#     (Get-HordeDriveLetterType) that the suites answer themselves, and it says why.
#   WHAT IT DOES NOT DO:
#   - It does not resolve anything. A relative path, or a PowerShell drive made over a share, is a
#     network path only once it is resolved, so a caller asks TWICE: of the path as written, and
#     again of the path it resolved to, still before anything looks at the disk. And it must ask
#     before resolving as well as after: PowerShell's own resolver
#     (GetUnresolvedProviderPathFromPSPath), handed a network drive's letter, looked the host up
#     (measured the same day: 1289 ms, and the entry in the cache).
#   - It does not see a drive letter that STANDS FOR a network drive, and for such a letter it is
#     itself the harm: Get-HordeDriveAliasRefusal, below, is asked BEFORE it.
#   - It does not see a volume mount point that leads to the network. Only the open handle's final
#     path shows that (files/Path.ps1, Resolve-HordeFilesLocalPath), which is after the open.
#   - It says nothing of devices or of streams inside a file (files/Path.ps1,
#     Get-HordeFilesPathRefusal). A path it answers "" for is not thereby safe to open.
#   ITS REASON SAYS ONLY WHAT IS TRUE FOR EVERY CALLER: that the path is a network path, or on a
#   network drive, and that only a path on one of this machine's own drives is taken. What the
#   caller was doing with the path - sharing a file, opening a report - is the caller's to add
#   (files/Path.ps1's Get-HordeFilesPlaceRefusal adds the sentence about sharing). Until 2026-10-13
#   the reason said "is shared", which was the files store's word and wrong for anyone else.
#   THE SURPRISE: A BACKSLASH AND THEN A FORWARD SLASH. Windows reads \/host\share\x.md as the
#   network path \\host\share\x.md. PowerShell's resolver does not: it resolves that spelling to a
#   LOCAL path on the current drive, C:\host\share\x.md (measured 2026-10-13, 5.1). So code that
#   judges a path only AFTER resolving it sees that spelling as local, and whatever is then handed
#   the path as written reaches the network. This function refuses it from the text as written;
#   that is one more reason the question is asked before the resolve and not only after it.
#
# Get-HordeDriveAliasRefusal - WHERE A DRIVE LETTER REALLY POINTS, ANSWERED WITHOUT OPENING ANYTHING.
# Asked BEFORE Get-HordeNetworkPathRefusal, of the path as written and again of the path it resolves to.
#   WHY IT EXISTS, AND WHY FIRST. A drive letter can stand for another drive letter: subst makes
#   one over a folder, and DefineDosDevice over anything. Measured 2026-10-13 on a letter S: defined
#   over R:\, R: being a network drive aimed at a host that does not exist, one fresh host a step:
#     defining S:, and reading from the system's table what S: stands for   host NOT looked up
#     asking the type of R:                                                 host NOT looked up
#     asking the type of S: (the answer is NoRootDirectory, not Network)    host WAS looked up
#   So for such a letter the network question above does not refuse - and its asking is the harm.
#   WHAT IT DOES: reads the system's own table of drive names (QueryDosDevice), which asks no disk
#   and no network, a letter at a time until one stands for no other letter, and asks the TYPE of
#   that last letter only. It refuses a letter whose chain ends at a network drive, and a chain
#   that does not end within eight letters (a ring), since where that is cannot be told.
#   WHAT IT DOES NOT SEE:
#   - A network drive whose target in the table is not written as a share (a drive the system
#     mapped has a redirector's device there). It answers "" and the network question refuses
#     it by its type; that question is safe for such a letter. A letter DEFINED straight over a
#     share (\??\UNC\host\share) is refused here, since the review of 2026-10-13: the table has
#     already said what it is.
#   - A volume mount point, a junction or a symbolic link that leads to the network from a folder
#     of a local drive. Those are not drive letters; only an open handle's final path shows them.
#   - A PowerShell drive (New-PSDrive), which is not in the system's table. It shows once the path
#     is resolved, which is why the question is asked again then.
#   - A letter redefined between the question and the open. It is a look, not a lock.
#
# test/test-path-text.ps1 holds all three, and test/mutations/path-text.psd1 their mutants.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It loads nothing.

function ConvertTo-HordeAsciiLower {
    # -Text with the 26 letters A to Z made a to z, and EVERY OTHER CHARACTER AS IT IS. Written out
    # here, with no case table of the runtime's: a table differs between runtimes and changes with
    # them. Measured 2026-10-13 on one machine, ToLowerInvariant of U+1E9E, U+2126 and U+A7AE: each
    # is left as it is by Windows PowerShell 5.1 and changed by PowerShell 7.6, so one path had one
    # file id under the first and another under the second (review of the files store).
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    $folded = New-Object System.Text.StringBuilder $Text.Length
    foreach ($character in $Text.ToCharArray()) {
        $code = [int]$character
        if ($code -ge 65 -and $code -le 90) { $code += 32 }
        [void]$folded.Append([char]$code)
    }
    return $folded.ToString()
}

function Get-HordeDriveLetterType {
    # What kind of drive the letter -Letter is, as Windows names it (Fixed, Network, Removable,
    # NoRootDirectory for a letter that names nothing, and the rest), or "" when it cannot be asked.
    # THE ONE PLACE THAT QUESTION IS ASKED, so that a suite can answer it without a drive: a drive
    # letter is seen by EVERY process of the user while it exists. Until 2026-10-13 the suites made
    # real letters aimed at a host that does not exist, and while one stood, a fresh powershell of
    # any other session printed "Attempting to perform the InitializeDefaultDrives operation on
    # the 'FileSystem' provider failed" and took 1.4 s to start instead of 0.2 (measured that day,
    # 7 of 8 starts). A suite replaces this function, called exactly as it is here.
    param([Parameter(Mandatory = $true)][string]$Letter)
    try { return ("" + (New-Object System.IO.DriveInfo($Letter)).DriveType) } catch { return "" }
}

function Get-HordeNetworkPathRefusal {
    # Why -Path is a network path, or "" when nothing says it is. THE FIRST QUESTION ASKED OF A PATH,
    # and it touches no disk and no network: the header has the measurement. Asked of the path as
    # written and again of the path it resolves to.
    param([AllowEmptyString()][string]$Path)
    $local = "only a path on one of this machine's own drives is taken"
    # Two separators of either kind first, unless what follows is the device or long-path prefix...
    $unc = ($Path -cmatch '\A[\\/]{2}' -and $Path -cnotmatch '\A[\\/]{2}[.?][\\/]')
    # ...and that prefix, or the NT one, before UNC. The letters are written out in both cases: an
    # ignore-case match asks a case table, which is what an id's input must never do.
    if (-not $unc) { $unc = ($Path -cmatch '\A(?:[\\/]{2}[.?]|\\\?\?)[\\/][Uu][Nn][Cc](?:[\\/]|\z)') }
    if ($unc) { return ("'" + $Path + "' is a network path, and " + $local) }
    if ($Path -cmatch '\A(?:\\\\\?\\)?([A-Za-z]):') {
        $letter = $Matches[1]
        # A letter whose type cannot be asked is not thereby a network drive: it goes on, and the
        # open handle's own path decides.
        $type = Get-HordeDriveLetterType -Letter $letter
        if ($type -ceq "Network") { return ("'" + $Path + "' is on a network drive (" + $letter + ":), and " + $local) }
    }
    return ""
}

function Initialize-HordePathTextNative {
    # The one question this file asks of Windows, defined once a process (core/FileAtomic.ps1's way):
    # QueryDosDevice, what a drive letter stands for in the system's own table of names.
    if (([System.Management.Automation.PSTypeName]"HordeNative.DriveName").Type) { return }
    Add-Type -Namespace HordeNative -Name DriveName -MemberDefinition '[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern int QueryDosDevice(string lpDeviceName, System.Text.StringBuilder lpTargetPath, int ucchMax);'
}

function Get-HordeDriveLetterTarget {
    # What the drive letter -Letter stands for, as Windows keeps it, or "" when it names nothing.
    # Measured 2026-10-13: C: is \Device\HarddiskVolume3; a subst drive over a folder is
    # \??\C:\that\folder; a letter aimed at a share is \??\UNC\host\share.
    param([Parameter(Mandatory = $true)][string]$Letter)
    Initialize-HordePathTextNative
    $text = New-Object System.Text.StringBuilder 1024
    if ([HordeNative.DriveName]::QueryDosDevice($Letter + ":", $text, 1024) -le 0) { return "" }
    return $text.ToString()
}

function Get-HordeDriveAliasRefusal {
    # Why -Path is on a drive letter that STANDS FOR a network drive, or "" when nothing says it is.
    # ASKED BEFORE THE NETWORK QUESTION, and nothing is opened: the header has the measurement, and
    # what this does not see. A letter that stands for no other letter is the network question's,
    # and this answers "" - unless the table says it stands straight for a share.
    param([AllowEmptyString()][string]$Path)
    if ($Path -cnotmatch '\A(?:\\\\\?\\)?([A-Za-z]):') { return "" }
    $first = $Matches[1]
    $ownDrives = "only a path on one of this machine's own drives is taken"
    $last = $first
    $ended = $false
    # Eight letters deep is more than anyone makes; a ring of letters never ends, and is refused.
    for ($hop = 1; $hop -le 8; $hop++) {
        $target = Get-HordeDriveLetterTarget -Letter $last
        # Anything but another drive letter is a volume, a share or nothing: the chain ends here.
        if ($target -cnotmatch '\A\\\?\?\\([A-Za-z]):') { $ended = $true; break }
        $last = $Matches[1]
    }
    if (-not $ended) { return ("'" + $Path + "' is on a drive (" + $first + ":) that stands for another drive letter, and that for another, without end: where it really is cannot be told, and " + $ownDrives) }
    if ([string]::Equals($last, $first, [System.StringComparison]::Ordinal)) {
        # A LETTER DEFINED STRAIGHT OVER A SHARE says so in the table itself: its target is the
        # device prefix and then UNC. The network question refuses such a letter too, by its type;
        # this refuses it from what was already read, and does not lean on the type being right.
        if ($target -cmatch '\A\\\?\?\\[Uu][Nn][Cc](?:\\|\z)') { return ("'" + $Path + "' is on a drive (" + $first + ":) that stands for a network share, and " + $ownDrives) }
        return ""
    }
    if ((Get-HordeNetworkPathRefusal -Path ($last + ":\")) -ne "") { return ("'" + $Path + "' is on a drive (" + $first + ":) that stands for a network drive (" + $last + ":), and " + $ownDrives) }
    return ""
}
