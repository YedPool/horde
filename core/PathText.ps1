# core/PathText - two questions answered from a path's TEXT alone: its letters A to Z in one case,
# and whether it names a place on the network.
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
#     control, asking whether a file on that drive exists, left the entry.
#   WHAT IT DOES NOT DO:
#   - It does not resolve anything. A relative path, or a PowerShell drive made over a share, is a
#     network path only once it is resolved, so a caller asks TWICE: of the path as written, and
#     again of the path it resolved to, still before anything looks at the disk. And it must ask
#     before resolving as well as after: PowerShell's own resolver
#     (GetUnresolvedProviderPathFromPSPath), handed a network drive's letter, looked the host up
#     (measured the same day: 1289 ms, and the entry in the cache).
#   - It does not see an alias the drive's type does not give away: a subst drive over a network
#     drive, a volume mount point. Only the open handle's final path shows those
#     (files/Path.ps1, Resolve-HordeFilesLocalPath), which is after the open.
#   - It says nothing of devices or of streams inside a file (files/Path.ps1,
#     Get-HordeFilesPathRefusal). A path it answers "" for is not thereby safe to open.
#   - Its reason is worded for a share ("only a file on one of this machine's own drives is
#     shared"): the words moved with the function, unchanged.
#   THE SURPRISE: A BACKSLASH AND THEN A FORWARD SLASH. Windows reads \/host\share\x.md as the
#   network path \\host\share\x.md. PowerShell's resolver does not: it resolves that spelling to a
#   LOCAL path on the current drive, C:\host\share\x.md (measured 2026-10-13, 5.1). So code that
#   judges a path only AFTER resolving it sees that spelling as local, and whatever is then handed
#   the path as written reaches the network. This function refuses it from the text as written;
#   that is one more reason the question is asked before the resolve and not only after it.
#
# test/test-path-text.ps1 holds both, and test/mutations/path-text.psd1 their mutants.
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

function Get-HordeNetworkPathRefusal {
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
