# decisions/Store.ps1 - the decisions store: write-once records in one folder, in one total order.
#
# THE ONE JOB of this file is to keep records and hand them back in order. It knows nothing of
# questions, numbers, rules, callers or how anything is shown: a record is "a JSON object in the file
# named for its sequence number". What the records mean is decisions/Rules.ps1's; what may be asked of
# the list is decisions/Operations.ps1's. Nothing but Operations.ps1 calls this file.
#
# THE FILES, in -Root (by default <HordeHome>\store\decisions, which Operations.ps1 works out):
#   0000000001.json, 0000000002.json, ...   one record each, named by its sequence number in ten digits.
# Nothing else is kept: no index, no counter, no "current list". The folder is the single source of truth.
#
# THE RULES, and what makes each one hold:
#   - ONE RECORD PER SEQUENCE NUMBER, PUT IN PLACE BY A MOVE THAT DOES NOT REPLACE. The record is written
#     whole into a temporary file of its own (writing-<32 hex>.part), and that file is then moved to the
#     record's name. The operating system lets exactly one move to a name succeed; every other is told
#     the name exists. So two writers, in any processes, at any moment, cannot both take sequence 7: the
#     loser is told "exists" and its caller reads the list again. test/test-decisions-store-race.ps1
#     races separate processes, and runs a control store that overwrites instead, to show the race can
#     see a lost record.
#   - A RECORD IS NEVER REWRITTEN AND NEVER DELETED. Nothing here opens a record for writing, and the
#     only files deleted are this file's own temporary ones, by their name pattern.
#   - THE RECORD'S BYTES ARE ON DISK BEFORE IT TAKES ITS NAME: written through
#     (FileOptions.WriteThrough, then Flush($true)) and closed, and only then moved.
#   - A RECORD IS NEVER SEEN HALF-WRITTEN. It has no name until it is whole.
#
# WHERE THIS DIFFERS FROM remote/Journal.ps1, AND WHY. The journal creates the record itself with
# FileMode.CreateNew and writes into it; this store did the same at first. A writer killed between the
# create and the write leaves an empty record under a real name, and here that costs for ever: the
# record is reported on every list and one question number is never given. Measured 2026-10-06, a
# writer doing nothing but writing 600-character records, killed at a random moment, the store then
# read back, 30 kills each way:
#     create-then-write   9 of 30 kills left an empty last record (11 of 30 with 400,000 characters)
#     write-then-move     0 of 30, and 0 of 30; 18 and 19 temporary files left behind
# (a control that tears on purpose was seen in 6 of 8, so the reading can see a tear). That is the rate
# for a kill landing while a record is being written, not for a kill of a real command, which spends
# about a second starting and milliseconds writing; what differs is what is left. A journal entry is
# pruned after its replay window; a decision record is kept for good, so the damage is too.
# WHAT THE MOVE DOES NOT GIVE: the rename itself is not written through (.NET Framework has no call
# for it), so after a power cut in the seconds after a write the record may be absent - never torn -
# though its writer was told "created". No test here can cut the power.
#
# TEMPORARY FILES LEFT BY A KILLED WRITER are swept at the start of the next write: only names of this
# file's own pattern, and only ones older than the age below, so a live writer's file is never taken.
#
# WHAT A CRASH OR A DAMAGED DISK LEAVES, and what the reader says of each. The list is still handed
# back, every time; the damaged record is in it, marked, with the reason:
#   - torn      an empty file or cut JSON: it was damaged after it was written, or made by hand.
#   - missing   a gap in the order: record 7 is not there and record 8 is. Someone deleted it.
#   - busy      still open in another process after the wait below. A writer is slow, or stuck.
#   - error     it could not be read at all (access denied, a disk error, bytes that are not UTF-8).
# This file never decides what a damaged record costs. It reports; Rules.ps1 decides.
#
# NOT DONE HERE, AND WHY. remote/Journal.ps1 refuses a root reached through a junction and a name that
# is not a plain file name, because its names come from the far end of a link. Every name here is ten
# digits this file formats from an integer, and the root is Horde's own home, so there is no name to
# refuse. And there is no marker file saying "this folder is a store": a home with no store folder is
# a list nobody has added to yet, which is what a first run must see.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

# Win32 error codes, read from the low 16 bits of an IOException's HResult: 80 ERROR_FILE_EXISTS,
# 183 ERROR_ALREADY_EXISTS (what a move onto a taken name raises, measured 2026-10-06, for a file and
# for a folder alike); 32 ERROR_SHARING_VIOLATION, 33 ERROR_LOCK_VIOLATION.
$script:HordeDecisionStoreExistsCodes = @(80, 183)
$script:HordeDecisionStoreBusyCodes = @(32, 33)
# Strict: bytes that are not UTF-8 throw instead of becoming U+FFFD, so a damaged record is reported
# and never read as different words.
$script:HordeDecisionStoreUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
# \A and \z, not ^ and $: in .NET, $ also matches before a final newline (remote/Journal.ps1).
$script:HordeDecisionStoreNamePattern = '\A([0-9]{10})\.json\z'
# How long a reader waits for a record another process holds open: 40 tries 50 ms apart, 2 s. A record
# is a few kilobytes written through, which takes milliseconds, so a healthy writer is done long before.
$script:HordeDecisionStoreBusyTries = 40
$script:HordeDecisionStoreBusyWaitMs = 50
# A writer's temporary file: the only other name this file makes, and the only kind it ever deletes.
$script:HordeDecisionStoreTempPattern = '\Awriting-[0-9a-f]{32}\.part\z'
# How old a temporary file must be before the next writer removes it. A live writer holds its file for
# milliseconds (a few kilobytes, written through); ten minutes is far past any writer that is merely
# slow, so what is removed was left by one that died.
$script:HordeDecisionStoreTempStaleMinutes = 10

function Get-HordeDecisionStoreWin32Code {
    param($ErrorRecord)
    $ex = $ErrorRecord.Exception
    while ($null -ne $ex -and $ex -isnot [System.IO.IOException] -and $null -ne $ex.InnerException) { $ex = $ex.InnerException }
    if ($ex -isnot [System.IO.IOException]) { return -1 }
    return ($ex.HResult -band 0xFFFF)
}

function Get-HordeDecisionRecordName {
    # The file name of record -Sequence. Ten digits, so names sort in sequence order and a store of
    # 9,999,999,999 records fits; the name is the order, and nothing else is.
    param([Parameter(Mandatory = $true)][long]$Sequence)
    if ($Sequence -lt 1 -or $Sequence -gt 9999999999) { throw ("a record's sequence number is 1 to 9999999999, not " + $Sequence) }
    return ($Sequence.ToString("D10", [System.Globalization.CultureInfo]::InvariantCulture) + ".json")
}

function Remove-HordeDecisionStoreLeftovers {
    # Remove the temporary files dead writers left in -Root. Returns how many were removed. Only a name
    # of this file's own temporary pattern, and only one last written more than the stale age ago: a
    # record is never a candidate, whatever its age, and a live writer's file is too young. A file
    # that cannot be removed is left for the next write; this never fails a write.
    param([Parameter(Mandatory = $true)][string]$Root, [datetime]$Now = [datetime]::UtcNow)
    $removed = 0
    $found = @()
    try { $found = @([System.IO.Directory]::GetFiles($Root, "writing-*.part")) } catch { return 0 }
    foreach ($leftover in $found) {
        if ([System.IO.Path]::GetFileName($leftover) -cnotmatch $script:HordeDecisionStoreTempPattern) { continue }
        try {
            if (($Now - [System.IO.File]::GetLastWriteTimeUtc($leftover)).TotalMinutes -lt $script:HordeDecisionStoreTempStaleMinutes) { continue }
            [System.IO.File]::Delete($leftover)
            $removed++
        } catch { }
    }
    return $removed
}

function Add-HordeDecisionRecord {
    # Put record -Sequence, holding -Text, in the store: written whole into a temporary file, written
    # through to disk, closed, and then moved to the record's name by a move that does not replace.
    # Returns "created" or "exists"; throws when the folder or the file cannot be made.
    # "exists" is not an error: it is how a writer learns another one took that place in the order.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][long]$Sequence, [Parameter(Mandatory = $true)][string]$Text)
    if (-not [System.IO.Path]::IsPathRooted("$Root")) { throw ("the decisions store needs an absolute folder, not '" + $Root + "'") }
    [void][System.IO.Directory]::CreateDirectory($Root)
    $recPath = Join-Path $Root (Get-HordeDecisionRecordName -Sequence $Sequence)
    $null = Remove-HordeDecisionStoreLeftovers -Root $Root
    # Encoded before any file is made: text that cannot be written as UTF-8 throws here and leaves nothing.
    $bytes = $script:HordeDecisionStoreUtf8.GetBytes($Text)
    $tmpPath = Join-Path $Root ("writing-" + [guid]::NewGuid().ToString("N") + ".part")
    $fs = New-Object System.IO.FileStream($tmpPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None, 4096, [System.IO.FileOptions]::WriteThrough)
    try {
        $fs.Write($bytes, 0, $bytes.Length)
        $fs.Flush($true)
    } finally { $fs.Dispose() }
    try { [System.IO.File]::Move($tmpPath, $recPath) }
    catch {
        $code = Get-HordeDecisionStoreWin32Code $_
        try { [System.IO.File]::Delete($tmpPath) } catch { }
        # "exists" only when a RECORD has the name. A folder of that name raises the same code, and
        # answering "exists" for it would send the caller round its retry loop for nothing.
        if (($script:HordeDecisionStoreExistsCodes -contains $code) -and [System.IO.File]::Exists($recPath)) { return "exists" }
        throw
    }
    return "created"
}

function Read-HordeDecisionRecordFile {
    # Read one record file. Returns { kind: ok | missing | busy | torn | error; data; reason }.
    param([Parameter(Mandatory = $true)][string]$Path)
    $text = $null
    for ($try = 1; $try -le $script:HordeDecisionStoreBusyTries; $try++) {
        $busy = $false
        try {
            $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            try {
                $reader = New-Object System.IO.StreamReader($fs, $script:HordeDecisionStoreUtf8, $false)
                try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
            } finally { $fs.Dispose() }
        } catch {
            $code = Get-HordeDecisionStoreWin32Code $_
            if ($code -eq 2 -or $code -eq 3) { return [pscustomobject]@{ kind = "missing"; data = $null; reason = "it is not in the store folder, though a later record is: it was deleted" } }
            if ($script:HordeDecisionStoreBusyCodes -contains $code) { $busy = $true }
            else { return [pscustomobject]@{ kind = "error"; data = $null; reason = ("it could not be read: " + $_.Exception.Message) } }
        }
        if (-not $busy) { break }
        if ($try -eq $script:HordeDecisionStoreBusyTries) {
            return [pscustomobject]@{ kind = "busy"; data = $null; reason = ("it is still open in another process after " + ($script:HordeDecisionStoreBusyTries * $script:HordeDecisionStoreBusyWaitMs) + " ms; a writer is slow or stuck") }
        }
        Start-Sleep -Milliseconds $script:HordeDecisionStoreBusyWaitMs
    }
    if ("$text".Trim() -eq "") { return [pscustomobject]@{ kind = "torn"; data = $null; reason = "it is empty: its writer stopped before writing it" } }
    try { $data = $text | ConvertFrom-Json } catch { return [pscustomobject]@{ kind = "torn"; data = $null; reason = "it is not complete JSON: its writer stopped while writing it, or it was damaged" } }
    if ($null -eq $data -or $data -isnot [System.Management.Automation.PSCustomObject]) { return [pscustomobject]@{ kind = "torn"; data = $null; reason = "it is not a JSON object" } }
    return [pscustomobject]@{ kind = "ok"; data = $data; reason = "" }
}

function Get-HordeDecisionRecords {
    # Every record of the store, in sequence order, damaged ones included. Returns
    #   { state: ok | absent | unknown; reason; last; records }
    # state absent: there is no store folder, so nothing was ever added; records is empty and last is 0.
    # state unknown: the folder is there and could not be listed, or a file is in its place; reason says why.
    # Each record is { sequence; file; kind: ok | missing | busy | torn | error; data; reason }, and
    # there is exactly one for every number from 1 to last: a number with no file is "missing", never
    # left out, because the order is what a question's number is worked out from.
    #
    # Files of any other name are not records and are not read: only this file's own ten-digit names
    # are. They cannot be mistaken for a record, so they cannot change the list.
    param([Parameter(Mandatory = $true)][string]$Root)
    $none = [pscustomobject]@{ state = "absent"; reason = "there is no decisions store yet"; last = [long]0; records = @() }
    $absolute = [System.IO.Path]::IsPathRooted("$Root")
    if (-not $absolute) {
        return [pscustomobject]@{ state = "unknown"; reason = ("the decisions store needs an absolute folder, not '" + $Root + "'"); last = [long]0; records = @() }
    }
    # A FILE of the store's name is not "no store yet": every write there fails, so a read that said
    # "an empty list" would be an answer no write could ever agree with (measured 2026-10-06).
    if ([System.IO.File]::Exists($Root)) {
        return [pscustomobject]@{ state = "unknown"; reason = ("the decisions store '" + $Root + "' is a file, not a folder"); last = [long]0; records = @() }
    }
    if (-not [System.IO.Directory]::Exists($Root)) { return $none }
    $names = $null
    try { $names = [System.IO.Directory]::GetFiles($Root, "*.json") }
    catch { return [pscustomobject]@{ state = "unknown"; reason = ("the decisions store '" + $Root + "' could not be listed: " + $_.Exception.Message); last = [long]0; records = @() } }
    $last = [long]0
    foreach ($full in $names) {
        $leaf = [System.IO.Path]::GetFileName($full)
        if ($leaf -cnotmatch $script:HordeDecisionStoreNamePattern) { continue }
        $seq = [long]$Matches[1]
        if ($seq -gt $last) { $last = $seq }
    }
    $records = New-Object System.Collections.ArrayList
    for ($seq = [long]1; $seq -le $last; $seq++) {
        # Every number up to the last is read by its own name, so one with no file reads as "missing".
        $leaf = Get-HordeDecisionRecordName -Sequence $seq
        $read = Read-HordeDecisionRecordFile -Path (Join-Path $Root $leaf)
        [void]$records.Add([pscustomobject]@{ sequence = $seq; file = $leaf; kind = $read.kind; data = $read.data; reason = $read.reason })
    }
    return [pscustomobject]@{ state = "ok"; reason = ""; last = $last; records = @($records) }
}
