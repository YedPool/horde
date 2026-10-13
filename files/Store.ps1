# files/Store.ps1 - the files store: write-once records of what was shared, and the bytes beside them.
#
# THE ONE JOB of this file is to keep entries and hand the records back. It knows nothing of types,
# caps, titles or sessions: a record is "a JSON object in a file named for a file id and a version",
# and bytes are "a file named for its own sha256". What may be shared, and what a record must hold, is
# files/Share.ps1's. It is modelled on decisions/Store.ps1, whose header has the measurements behind
# each rule; what is the same is said shortly here, and what differs is said in full.
#
# THE FILES, in -Root (by default <HordeHome>\store\files):
#   <32 hex file id>.<version in six digits>.json   one record: one version of one shared file
#   <64 hex sha256>.bytes                           the bytes of a shared file, named by their digest
#   writing-<32 hex>.part                           a writer's temporary file, until it has its name
# Nothing else is kept: no index and no counter. The folder is the single source of truth.
#
# THE RULES, and what makes each one hold:
#   - EVERY ENTRY IS PUT IN PLACE BY A MOVE THAT DOES NOT REPLACE. It is written whole into a temporary
#     file this writer holds open, flushed to disk, and then moved to its name by core/FileAtomic.ps1's
#     Move-HordeFileNewDurable. The operating system lets exactly one move to a name succeed, so two
#     shares of one file at one moment cannot both take version 3: the loser is told "exists" and its
#     caller takes the next version. test/test-files-race.ps1 races separate processes, and a control
#     store that overwrites, to show the race can see a lost record.
#   - AN ENTRY IS NEVER REWRITTEN AND NEVER DELETED. Nothing here opens an entry for writing, and the
#     only files deleted are this file's own temporary ones, by their name pattern, never through a link.
#   - AN ENTRY IS NEVER SEEN HALF-WRITTEN. It has no name until it is whole.
#   - THE SAME BYTES ARE KEPT ONCE. Their name is their digest, so the second writer of the same bytes
#     is told "exists", and that is success: what has the name is what it meant to write.
#
# WHAT A WRITER KILLED PART-WAY LEAVES: a temporary file, or bytes with no record. Neither is in the
# list. Bytes with no record are never removed (an entry is never deleted) and are used by the next
# share of the same bytes. A record is written only after its bytes have their name, so no record
# ever names bytes that are not there.
#
# TEMPORARY FILES LEFT BY A KILLED WRITER are swept at the start of the next write, under
# decisions/Store.ps1's invariant, all four of: neither it nor the store folder is a link; its name is
# exactly the temporary pattern; it is older than the age the caller gives (the setting
# leftoverMinAgeSeconds); and NO PROCESS HOLDS IT OPEN - it is claimed with no sharing at all, which
# the operating system refuses while any other handle exists. A live writer holds its file from the
# moment it exists until it has its name, so "nobody holds it" is "its writer is dead".
#
# WHERE THIS DIFFERS FROM decisions/Store.ps1:
#   - No total order, so no gaps and no "missing": a file's versions are found by its id.
#   - A record that is a link is not read: its words would be another file's. It is reported.
#   - The numbers are parameters here. files/Settings.ps1 names them and files/Share.ps1 hands them in,
#     so this file reads no settings and a test can give its own.
#   - The write and the sweep are written out again, not shared: decisions/Store.ps1's are bound to its
#     own names and settings. Folding the two into one core helper is a change to that store.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Home.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\FileAtomic.ps1")

function Get-HordeFilesStoreFormat {
    # What the store IS, which no setting could change without making it another store: its three name
    # patterns, the width of a version, and the Win32 codes of a read that found the file held (32
    # ERROR_SHARING_VIOLATION, 33 ERROR_LOCK_VIOLATION). \A and \z, not ^ and $: in .NET, $ also
    # matches before a final newline (remote/Journal.ps1).
    return [pscustomobject]@{
        record = '\A([0-9a-f]{32})\.([0-9]{6})\.json\z'
        bytes = '\A[0-9a-f]{64}\.bytes\z'
        temporary = '\Awriting-[0-9a-f]{32}\.part\z'
        versionDigits = 6
        maxVersion = 999999
        busyCodes = @(32, 33)
    }
}

function Get-HordeFilesStoreRoot {
    # Where the store is: <home>\store\files. A path only; nothing is looked at and nothing is made.
    param([string]$HordeHome = "")
    $base = $HordeHome
    if ($base -eq "") { $base = Get-HordeHome }
    return (Join-Path (Join-Path $base "store") "files")
}

function Get-HordeFilesRecordName {
    # The file name of version -Version of file -FileId.
    param([Parameter(Mandatory = $true)][string]$FileId, [Parameter(Mandatory = $true)][int]$Version)
    $format = Get-HordeFilesStoreFormat
    if ($FileId -cnotmatch '\A[0-9a-f]{32}\z') { throw ("a file id is 32 lower-case hex digits, not '" + $FileId + "'") }
    if ($Version -lt 1 -or $Version -gt $format.maxVersion) { throw ("a version is 1 to " + $format.maxVersion + ", not " + $Version) }
    return ($FileId + "." + $Version.ToString(("D" + $format.versionDigits), [System.Globalization.CultureInfo]::InvariantCulture) + ".json")
}

function Get-HordeFilesBytesName {
    # The file name of the bytes whose digest is -Sha256.
    param([Parameter(Mandatory = $true)][string]$Sha256)
    if ($Sha256 -cnotmatch '\A[0-9a-f]{64}\z') { throw ("a sha256 is 64 lower-case hex digits, not '" + $Sha256 + "'") }
    return ($Sha256 + ".bytes")
}

function Test-HordeFilesStoreLink {
    # Is the entry at -Path itself a link of any kind (a symbolic link, a junction, any reparse point)?
    # Its OWN attributes are read, so a link to a record answers true. An entry that cannot be read
    # answers true: when it cannot be told, it is treated as what must not be followed.
    param([Parameter(Mandatory = $true)][string]$Path)
    try { return (([System.IO.File]::GetAttributes($Path) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) } catch { return $true }
}

function Get-HordeFilesStoreWin32Code {
    param($ErrorRecord)
    $ex = $ErrorRecord.Exception
    while ($null -ne $ex -and $ex -isnot [System.IO.IOException] -and $null -ne $ex.InnerException) { $ex = $ex.InnerException }
    if ($ex -isnot [System.IO.IOException]) { return -1 }
    return ($ex.HResult -band 0xFFFF)
}

function Remove-HordeFilesStoreLeftovers {
    # Remove the temporary files dead writers left in -Root. Returns how many were removed. The header
    # states the invariant. A file that cannot be removed is left for the next write; this never fails
    # a write.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][int]$MinAgeSeconds, [datetime]$Now = [datetime]::UtcNow)
    $removed = 0
    $format = Get-HordeFilesStoreFormat
    if ([System.IO.Directory]::Exists($Root) -and (Test-HordeFilesStoreLink -Path $Root)) { return 0 }
    $found = @()
    try { $found = @([System.IO.Directory]::GetFiles($Root, "writing-*.part")) } catch { return 0 }
    foreach ($leftover in $found) {
        if ([System.IO.Path]::GetFileName($leftover) -cnotmatch $format.temporary) { continue }
        try {
            # NEVER THROUGH A LINK: the claim below deletes what it opens, and an open by name follows a
            # link to its target (decisions/Store.ps1 has the review that saw a record deleted this way).
            if (Test-HordeFilesStoreLink -Path $leftover) { continue }
            if (($Now - [System.IO.File]::GetLastWriteTimeUtc($leftover)).TotalSeconds -lt $MinAgeSeconds) { continue }
            # CLAIMED, NOT JUST DELETED: this open is refused while any other handle exists, so a file a
            # live writer holds is never taken; closing the claim deletes the file.
            $claim = New-Object System.IO.FileStream($leftover, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None, 1, [System.IO.FileOptions]::DeleteOnClose)
            $claim.Dispose()
            $removed++
        } catch { }
    }
    return $removed
}

function Add-HordeFilesStoreEntry {
    # Put an entry named -Name, holding -Bytes, in the store: written whole into a temporary file this
    # writer holds open, flushed to disk, and given its name by a durable move that does not replace.
    #   "created"      the entry is in the store, and everything that makes it durable returned success;
    #   "exists"       a file already has that name. For a record: another share took that version. For
    #                  bytes: the same bytes are already kept;
    #   "unconfirmed"  the entry HAS its name, but the flush after the move failed. It must not be
    #                  reported as saved, and not as "nothing was written" either.
    # Throws when the folder or the file cannot be made, or the move fails any other way.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes, [Parameter(Mandatory = $true)][int]$LeftoverMinAgeSeconds)
    if (-not [System.IO.Path]::IsPathRooted("$Root")) { throw ("the files store needs an absolute folder, not '" + $Root + "'") }
    $format = Get-HordeFilesStoreFormat
    # Only the two names the store keeps: a name with a separator or dots in it never reaches a path.
    if ($Name -cnotmatch $format.record -and $Name -cnotmatch $format.bytes) { throw ("'" + $Name + "' is not a name the files store keeps") }
    [void][System.IO.Directory]::CreateDirectory($Root)
    $entryPath = Join-Path $Root $Name
    $null = Remove-HordeFilesStoreLeftovers -Root $Root -MinAgeSeconds $LeftoverMinAgeSeconds
    $tmpPath = Join-Path $Root ("writing-" + [guid]::NewGuid().ToString("N") + ".part")
    # Sharing delete and nothing else: the file can be renamed while this handle is open, and nothing
    # can read or write it until it is whole and let go.
    $fs = New-Object System.IO.FileStream($tmpPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Delete, 4096, [System.IO.FileOptions]::WriteThrough)
    $moved = ""
    try {
        $fs.Write($Bytes, 0, $Bytes.Length)
        $fs.Flush($true)
        $moved = Move-HordeFileNewDurable -From $tmpPath -To $entryPath -Open $fs
    } finally {
        $fs.Dispose()
        # Whatever went wrong, this writer's own temporary file does not stay.
        if ($moved -cne "moved" -and $moved -cne "unconfirmed") { try { [System.IO.File]::Delete($tmpPath) } catch { } }
    }
    if ($moved -ceq "moved") { return "created" }
    if ($moved -ceq "unconfirmed") { return "unconfirmed" }
    # "exists" only when a FILE has the name: a folder of that name is answered the same way by the move.
    if ($moved -ceq "exists" -and [System.IO.File]::Exists($entryPath)) { return "exists" }
    throw ("the entry " + $Name + " could not be put in place: its name is taken by something that is not a file (the move answered '" + $moved + "')")
}

function Get-HordeFilesStoreLastVersion {
    # The highest version of file -FileId that has a record, 0 when it has none. Read from the names
    # alone: no record is opened, so a damaged version still counts and its number is never given twice.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$FileId)
    if ($FileId -cnotmatch '\A[0-9a-f]{32}\z') { throw ("the file whose versions are asked for needs an id of 32 lower-case hex digits, not '" + $FileId + "'") }
    if (-not [System.IO.Directory]::Exists($Root)) { return 0 }
    $format = Get-HordeFilesStoreFormat
    $last = 0
    foreach ($full in @([System.IO.Directory]::GetFiles($Root, ($FileId + ".*.json")))) {
        $leaf = [System.IO.Path]::GetFileName($full)
        if ($leaf -cnotmatch $format.record -or $Matches[1] -cne $FileId) { continue }
        $version = [int]$Matches[2]
        if ($version -gt $last) { $last = $version }
    }
    return $last
}

function Read-HordeFilesRecordFile {
    # Read one record file. Returns { kind: ok | busy | torn | error; data; reason }.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][int]$HeldTries, [Parameter(Mandatory = $true)][int]$HeldWaitMs)
    # NEVER THROUGH A LINK: a link named like a record would hand back another file's words as a share.
    if (Test-HordeFilesStoreLink -Path $Path) { return [pscustomobject]@{ kind = "error"; data = $null; reason = "it is a link, or cannot be looked at; a record is never read through a link" } }
    $format = Get-HordeFilesStoreFormat
    # Strict: bytes that are not UTF-8 throw instead of becoming U+FFFD, so a damaged record is
    # reported and never read as different words.
    $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $text = $null
    for ($try = 1; $try -le $HeldTries; $try++) {
        $busy = $false
        try {
            $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            try {
                $reader = New-Object System.IO.StreamReader($fs, $utf8, $false)
                try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
            } finally { $fs.Dispose() }
        } catch {
            if ($format.busyCodes -contains (Get-HordeFilesStoreWin32Code $_)) { $busy = $true }
            else { return [pscustomobject]@{ kind = "error"; data = $null; reason = ("it could not be read: " + $_.Exception.Message) } }
        }
        if (-not $busy) { break }
        if ($try -eq $HeldTries) { return [pscustomobject]@{ kind = "busy"; data = $null; reason = ("it is still open in another process after " + ($HeldTries * $HeldWaitMs) + " ms; a writer is slow or stuck") } }
        Start-Sleep -Milliseconds $HeldWaitMs
    }
    if ("$text".Trim() -eq "") { return [pscustomobject]@{ kind = "torn"; data = $null; reason = "it is empty" } }
    $data = $null
    try { $data = $text | ConvertFrom-Json } catch { return [pscustomobject]@{ kind = "torn"; data = $null; reason = "it is not complete JSON: it was damaged, or made by hand" } }
    if ($null -eq $data -or $data -isnot [System.Management.Automation.PSCustomObject]) { return [pscustomobject]@{ kind = "torn"; data = $null; reason = "it is not a JSON object" } }
    return [pscustomobject]@{ kind = "ok"; data = $data; reason = "" }
}

function Get-HordeFilesRecords {
    # Every record of the store, in the order of its name (file id, then version), damaged ones
    # included. Returns { state: ok | absent | unknown; reason; records; strays }.
    #   absent   there is no store folder, so nothing was ever shared; records is empty.
    #   unknown  the folder is there and could not be listed, or a file is in its place.
    # Each record is { fileId; version; file; kind: ok | busy | torn | error; data; reason }.
    # strays is { file; reason }: a .json file whose name is not a record's, and a link named like a
    # writer's temporary file, which the sweep never follows and never removes. READS ONLY: no folder
    # is made and nothing is swept, so asking leaves no trace.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][int]$HeldTries, [Parameter(Mandatory = $true)][int]$HeldWaitMs)
    $rooted = [System.IO.Path]::IsPathRooted("$Root")
    if (-not $rooted) { return [pscustomobject]@{ state = "unknown"; reason = ("the files store needs an absolute folder, not '" + $Root + "'"); records = @(); strays = @() } }
    # A FILE of the store's name is not "no store yet": every write there fails.
    if ([System.IO.File]::Exists($Root)) { return [pscustomobject]@{ state = "unknown"; reason = ("the files store '" + $Root + "' is a file, not a folder"); records = @(); strays = @() } }
    if (-not [System.IO.Directory]::Exists($Root)) { return [pscustomobject]@{ state = "absent"; reason = "there is no files store yet"; records = @(); strays = @() } }
    $names = $null
    try { $names = [string[]]@([System.IO.Directory]::GetFiles($Root, "*.json") | ForEach-Object { [System.IO.Path]::GetFileName($_) }) }
    catch { return [pscustomobject]@{ state = "unknown"; reason = ("the files store '" + $Root + "' could not be listed: " + $_.Exception.Message); records = @(); strays = @() } }
    # Ordinal, so the order is the same on every machine: a file's versions follow each other.
    [Array]::Sort($names, [System.StringComparer]::Ordinal)
    $format = Get-HordeFilesStoreFormat
    $strays = New-Object System.Collections.ArrayList
    $records = New-Object System.Collections.ArrayList
    foreach ($leaf in $names) {
        if ($leaf -cnotmatch $format.record -or [int]$Matches[2] -lt 1) {
            [void]$strays.Add([pscustomobject]@{ file = $leaf; reason = "its name is not a file id and a version from 1 in six digits, so it is not a record" })
            continue
        }
        $fileId = $Matches[1]; $version = [int]$Matches[2]
        $read = Read-HordeFilesRecordFile -Path (Join-Path $Root $leaf) -HeldTries $HeldTries -HeldWaitMs $HeldWaitMs
        [void]$records.Add([pscustomobject]@{ fileId = $fileId; version = $version; file = $leaf; kind = $read.kind; data = $read.data; reason = $read.reason })
    }
    $temporaries = @()
    try { $temporaries = @([System.IO.Directory]::GetFiles($Root, "writing-*.part")) } catch { }
    foreach ($full in $temporaries) {
        $leaf = [System.IO.Path]::GetFileName($full)
        if ($leaf -cmatch $format.temporary -and (Test-HordeFilesStoreLink -Path $full)) {
            [void]$strays.Add([pscustomobject]@{ file = $leaf; reason = "it is a link named like a writer's temporary file; it is never followed and never removed, so whoever made it should remove it" })
        }
    }
    return [pscustomobject]@{ state = "ok"; reason = ""; records = @($records); strays = @($strays) }
}
