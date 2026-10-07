# core/Fingerprints.ps1 - a folder's list of pinned files, and whether the files still match it.
#
# WHY. Horde depended on nothing outside Windows until an adapter needed a program library it cannot
# be written without (decisions design, 2026-10-06, section 3.11). A file brought in from elsewhere is
# committed beside a list of fingerprints, one line per file:
#
#   <file name> | <sha256, 64 lowercase hex> | <what it is and where it came from>
#
# and it is changed only by a pull request that changes the file and its line together. Two readers
# hold a folder to its list, and both read it through this file so that they cannot come to differ:
#   - the adapter that loads the files checks them BEFORE loading, and refuses on a mismatch;
#   - tools/HostNames.ps1, which otherwise refuses every byte that is not printable ASCII, lets a
#     listed file through without reading it as text, and fails when one no longer matches its line.
#
# A NAME IS A FILE NAME IN THE LIST'S OWN FOLDER, never a path: a list cannot pin, or excuse, a file
# anywhere else. Blank lines and lines beginning with # are ignored.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

$script:HordeFingerprintListName = "fingerprints.txt"

function Get-HordeFingerprintListName { return $script:HordeFingerprintListName }

function Open-HordePinnedFile {
    # A file opened to be checked and then loaded: others may read it, and nobody may write to it,
    # remove it or rename it for as long as the stream is open.
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
}

function Get-HordeStreamSha256 {
    # The SHA-256 of everything in an open file, as 64 lowercase hex digits. The stream is left open.
    param([Parameter(Mandatory = $true)][System.IO.Stream]$Stream)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $Stream.Position = 0; return (-join ($sha.ComputeHash($Stream) | ForEach-Object { $_.ToString("x2") })) }
    finally { $sha.Dispose() }
}

function Get-HordeFileSha256 {
    # A file's SHA-256 as 64 lowercase hex digits. The file is read whole, shared for reading.
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = Open-HordePinnedFile -Path $Path
    try { return (Get-HordeStreamSha256 -Stream $stream) }
    finally { $stream.Dispose() }
}

function Read-HordeFingerprintList {
    # The lines of a fingerprint list as { entries; problems }: entries are { name; sha256; what; line },
    # problems the malformed lines in words. A line that is malformed pins nothing.
    param([Parameter(Mandatory = $true)][string]$Path)
    $entries = New-Object System.Collections.ArrayList
    $problems = New-Object System.Collections.ArrayList
    $seen = @{}
    $n = 0
    # THE LIST IS PLAIN ASCII, like every text file of Horde's: tab, carriage return, line feed and
    # 0x20 to 0x7E. Read as bytes first and refused whole otherwise, so that a list saved in two-byte
    # characters, or with a byte-order mark, is not quietly read here while the gate's own scan of
    # the same file refuses it (review of 2026-10-06, finding A11).
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $b = $bytes[$i]
        if (-not ($b -eq 9 -or $b -eq 10 -or $b -eq 13 -or ($b -ge 0x20 -and $b -le 0x7E))) {
            return [pscustomobject]@{ entries = @(); problems = @("the list is not plain ASCII text (byte " + $i + " is 0x" + $b.ToString("x2") + "), so it pins nothing; save it as ASCII") }
        }
    }
    foreach ($raw in ([System.Text.Encoding]::ASCII.GetString($bytes) -split "`n")) {
        $n++
        $t = $raw.Trim()
        if ($t -eq "" -or $t.StartsWith("#")) { continue }
        $cells = @($t -split "\|" | ForEach-Object { $_.Trim() })
        if ($cells.Count -ne 3) { [void]$problems.Add("line " + $n + " is not '<file name> | <sha256> | <what it is and where it came from>'"); continue }
        # A NAME, NEVER A PATH: no separator, no drive, no "..", so the list reaches only its own folder.
        # It begins and ends with a letter or a digit: Windows opens "a.dll." as a.dll, so a name with
        # a dot at its end would be a second name for one file, and "listed twice" would not see it.
        if ($cells[0] -cnotmatch '\A[A-Za-z0-9](?:[A-Za-z0-9._-]{0,126}[A-Za-z0-9])?\z' -or $cells[0].Contains("..")) { [void]$problems.Add("line " + $n + " names '" + $cells[0] + "', which is not a plain file name in this folder"); continue }
        if ($cells[1] -cnotmatch '\A[0-9a-f]{64}\z') { [void]$problems.Add("line " + $n + " gives no SHA-256 for " + $cells[0] + ": 64 lowercase hex digits are wanted"); continue }
        if ($cells[2] -eq "") { [void]$problems.Add("line " + $n + " does not say what " + $cells[0] + " is or where it came from"); continue }
        # A plain @{} ignores case, as the file system does: A.DLL and a.dll are one file listed twice.
        $key = $cells[0]
        if ($seen.ContainsKey($key)) { [void]$problems.Add("line " + $n + " lists " + $cells[0] + " a second time"); continue }
        $seen[$key] = $true
        [void]$entries.Add([pscustomobject]@{ name = $cells[0]; sha256 = $cells[1]; what = $cells[2]; line = $n })
    }
    return [pscustomobject]@{ entries = @($entries); problems = @($problems) }
}

function Test-HordeFingerprints {
    # Is every file the list in -Folder names there, with exactly the fingerprint its line gives?
    # Returns { ok; findings; files; unlisted; held }: findings in words, empty when ok; files the full
    # paths of the listed files, in the list's order, for a caller that goes on to load them. A folder
    # with no list is not ok: nothing in it is pinned.
    #
    # unlisted is the name of everything else in the folder but the list itself, files and folders,
    # in ordinal order. It is NOT a finding here: what may stand beside pinned files - a licence, a
    # notice - is each caller's rule, and a caller that loads the files should have one, because a
    # program library loaded from a folder can pull in another that was put beside it.
    #
    # -Hold CLOSES THE GAP BETWEEN CHECKING A FILE AND LOADING IT (review of the first adapter to use
    # this, 2026-10-06, finding A6). Each listed file is opened ONCE, its fingerprint is taken from
    # that open file, and when the whole folder is ok the open files are handed back in held: until
    # the caller disposes of them no program can write to one, remove it, rename it, or rename the
    # folder from under it (measured by this file's suite on every run), so what is then loaded by
    # path is what was checked. When the folder is not ok nothing is held. THE CALLER MUST DISPOSE OF
    # EVERY ONE, in a finally.
    param([Parameter(Mandatory = $true)][string]$Folder, [switch]$Hold)
    $findings = New-Object System.Collections.ArrayList
    $files = New-Object System.Collections.ArrayList
    $held = New-Object System.Collections.ArrayList
    $listPath = Join-Path $Folder $script:HordeFingerprintListName
    if (-not (Test-Path -LiteralPath $listPath -PathType Leaf)) {
        return [pscustomobject]@{ ok = $false; findings = @("there is no " + $script:HordeFingerprintListName + " in " + $Folder + ", so nothing there is pinned"); files = @(); unlisted = @(); held = @() }
    }
    $read = Read-HordeFingerprintList -Path $listPath
    foreach ($p in $read.problems) { [void]$findings.Add($script:HordeFingerprintListName + ": " + $p) }
    if (@($read.entries).Count -eq 0) { [void]$findings.Add($script:HordeFingerprintListName + " lists no file") }
    foreach ($e in $read.entries) {
        $full = Join-Path $Folder $e.name
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { [void]$findings.Add($e.name + " is listed and is not there"); continue }
        $actual = ""
        $stream = $null
        try { $stream = Open-HordePinnedFile -Path $full; $actual = Get-HordeStreamSha256 -Stream $stream }
        catch { if ($null -ne $stream) { $stream.Dispose() }; [void]$findings.Add($e.name + " could not be read to check its fingerprint: " + $_.Exception.Message); continue }
        if ($actual -cne $e.sha256) { $stream.Dispose(); [void]$findings.Add($e.name + " does not match its fingerprint: the list says " + $e.sha256 + " and the file is " + $actual); continue }
        [void]$files.Add($full)
        if ($Hold) { [void]$held.Add($stream) } else { $stream.Dispose() }
    }
    # Compared exactly as the list's names are; the file system's own forgiveness of case is not
    # extended to "listed".
    $listed = @($read.entries | ForEach-Object { $_.name }) + @($script:HordeFingerprintListName)
    $unlisted = [string[]]@([System.IO.Directory]::GetFileSystemEntries($Folder) | ForEach-Object { [System.IO.Path]::GetFileName($_) } | Where-Object { $listed -cnotcontains $_ })
    [Array]::Sort($unlisted, [System.StringComparer]::Ordinal)
    if ($findings.Count -gt 0) { foreach ($h in @($held)) { $h.Dispose() }; $held.Clear() }
    return [pscustomobject]@{ ok = ($findings.Count -eq 0); findings = @($findings); files = @($files); unlisted = @($unlisted); held = @($held) }
}
