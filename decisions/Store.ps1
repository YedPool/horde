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
# EVERY NUMBER THIS FILE CAN BE TUNED BY IS A NAMED SETTING (decisions/Settings.ps1 and its table,
# decisions/settings.json): the largest gap believed, how long a held record is waited for, how old a
# leftover must be. None is written here. What is written here is what the store IS - its name
# patterns and the error codes it reads - which no setting could change without making it another
# store. THE WIDTH OF A NAME is that kind of thing too, and is not a setting: it is the one constant of
# decisions/Format.ps1, which the rules read as well, and that file says why.
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
#     (FileOptions.WriteThrough, then Flush($true)), and only then moved.
#   - A RECORD IS NEVER SEEN HALF-WRITTEN. It has no name until it is whole.
#   - THE RECORD IS DURABLE BEFORE ITS WRITER IS TOLD "CREATED". See the next section.
#
# THE ORDER OF A WRITE, and what a writer killed after each step leaves:
#   1. the temporary file is created, new, and HELD OPEN from here to the end;
#        killed: an empty leftover. Nothing in the list. The caller was told nothing.
#   2. the record is written into it and flushed to disk;
#        killed: a leftover, part or whole. Nothing in the list. The caller was told nothing.
#   3. the file is given the record's name by core/FileAtomic.ps1's Move-HordeFileNewDurable: a move
#      that does not replace, written through, and then a flush of the handle this writer still holds;
#        killed after the move: the WHOLE record is in the list. The caller was told nothing, and
#        sending the same request again is answered from that record (decisions/Operations.ps1).
#   4. the handle is let go, and only now is the caller told "created".
# So at every step: either the whole record is in the store, or nothing is and its writer was not told
# it was saved. test/test-decisions-store-race.ps1 stops a real writer at steps 2 and 3 and kills it.
#
# WHY THE MOVE ITSELF MUST BE DURABLE. With a plain File.Move, as this file first had, the record's
# bytes were on disk but its NAME was not: after a power cut in the seconds after a write the record
# could be absent though its writer had been told "created", its bytes sitting in a temporary file
# the next writer's sweep would then remove. The durable move closes that: "created" is said only
# after the operating system has been asked, by two means, to put the rename on disk.
# THE HONEST LIMIT: no test can cut the power. What IS proven, by test/test-decisions-store.ps1 and
# test/test-file-move-new.ps1: the order above, step by step; that the move is handed the
# write-through flag and not the replace flag; that the handle is flushed to disk after the move; that
# "created" is said for the move's "moved" and for nothing else. That the operating system and the
# disk then keep their word is reasoned (core/FileAtomic.ps1 has the reasoning and one measurement),
# and a disk that acknowledges a flush it has not done defeats it.
#
# THE PLATFORM IS NOT HERE. How a move is made durable differs by system, and is core/FileAtomic.ps1's:
# this file asks for "that name, if free, durably" and is answered moved, exists or unconfirmed.
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
#
# TEMPORARY FILES LEFT BY A KILLED WRITER are swept at the start of the next write. THE SWEEP'S
# INVARIANT: a file is removed only when ALL THREE hold -
#   (1) its name is exactly this file's own temporary pattern: a record is never a candidate;
#   (2) it was last written longer ago than the age (the setting decisions.store.leftoverMinAgeSeconds);
#   (3) NO PROCESS HOLDS IT OPEN. It is removed by opening it with no sharing at all, to be deleted
#       when that handle closes: the operating system refuses that open while any other handle exists.
# (3) is what makes it safe, and has no clock in it. A writer holds its file open from the moment the
# file exists until it has its record's name (the order above), and the operating system closes a
# dead process's handles; so "nobody holds it" is "its writer is dead, and never moved it". A writer
# that is merely slow - suspended, or on a machine put to sleep between its write and its move - is
# old and alive, and age alone took its file (measured 2026-10-06 against the sweep by age: of four
# leftovers 400 days old, three of them held open, it removed three).
# (2) is kept as a second condition for a store on a file system that does not enforce sharing (some
# network shares): there (3) may prove nothing, and the age is what is left.
# AND IT NEVER REMOVES THE ONLY COPY OF A RECORD ITS WRITER WAS TOLD IS SAVED: "created" is said only
# after the file has its record's name, durably, and a file with a record's name is not a candidate.
#
# WHAT A CRASH OR A DAMAGED DISK LEAVES, and what the reader says of each. The list is still handed
# back, every time; the damaged record is in it, marked, with the reason:
#   - torn      an empty file or cut JSON: it was damaged after it was written, or made by hand.
#   - missing   a gap in the order: record 7 is not there and record 8 is. Someone deleted it. A gap
#               of several records is ONE entry, saying from where to where.
#   - busy      still open in another process after the wait below. A writer is slow, or stuck.
#   - error     it could not be read at all (access denied, a disk error, bytes that are not UTF-8).
# This file never decides what a damaged record costs. It reports; Rules.ps1 decides.
# And one thing that is not damage: a STRAY, a file with a record's kind of name that is too far past
# the end of the order to be a record (see the gap limit below), or whose number is not ten digits or
# is zero. A stray is reported by name and is not part of the order at all.
#
# NOT DONE HERE, AND WHY. remote/Journal.ps1 refuses a root reached through a junction and a name that
# is not a plain file name, because its names come from the far end of a link. Every name here is ten
# digits this file formats from an integer, and the root is Horde's own home, so there is no name to
# refuse. And there is no marker file saying "this folder is a store": a home with no store folder is
# a list nobody has added to yet, which is what a first run must see.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path $PSScriptRoot "Settings.ps1")
. (Join-Path $PSScriptRoot "Format.ps1")

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\FileAtomic.ps1")

# Win32 error codes of a READ, from the low 16 bits of an IOException's HResult: 32
# ERROR_SHARING_VIOLATION, 33 ERROR_LOCK_VIOLATION. (What a move onto a taken name raises is no longer
# read here: the durable move answers "exists" in words.)
$script:HordeDecisionStoreBusyCodes = @(32, 33)
# Strict: bytes that are not UTF-8 throw instead of becoming U+FFFD, so a damaged record is reported
# and never read as different words.
$script:HordeDecisionStoreUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
# HOW LONG A READER WAITS FOR A RECORD ANOTHER PROCESS HOLDS OPEN is two settings,
# decisions.store.heldReadTries and decisions.store.heldReadWaitMs: by default 40 tries 50 ms apart,
# 2 s. A record is a few kilobytes written through, which takes milliseconds, so a healthy writer is
# done long before.
# Any name made only of digits: a record's name when it is exactly ten of them and not zero, a stray
# otherwise. A name with anything else in it is somebody else's file and is not looked at.
$script:HordeDecisionStoreDigitsPattern = '\A([0-9]+)\.json\z'
# THE LARGEST GAP THAT IS BELIEVED. Records missing from the middle of the order may have been
# questions, so each one costs a question number (Rules.ps1) - right for a handful of records deleted
# by hand, and ruinous for a file that was never a record. Measured 2026-10-06, before this limit: ONE
# file named 0000002000.json beside two records made a list take 11.6 s, report 1998 unreadable
# records, and number the next question 2001 for good; one named 9999999999.json and the list never
# came back. A hundred lost records in a row is not something a hand or a crash does to a folder of
# small files; a stray copy or a mistyped name is. So a name more than this far past the last record
# before it is a stray, and so is every name after it. The limit is the setting decisions.store.maxGap,
# 100 by default.
# A writer's temporary file: the only other name this file makes, and the only kind it ever deletes.
$script:HordeDecisionStoreTempPattern = '\Awriting-[0-9a-f]{32}\.part\z'
# How old a temporary file must be before the next writer removes it is the setting
# decisions.store.leftoverMinAgeSeconds, ten minutes by default. A live writer holds its file for
# milliseconds (a few kilobytes, written through); ten minutes is far past any writer that is merely
# slow, so what is removed was left by one that died.

function Get-HordeDecisionStoreNamePattern {
    # What a record's file name matches: exactly that many digits, then .json.
    # \A and \z, not ^ and $: in .NET, $ also matches before a final newline (remote/Journal.ps1).
    return ('\A([0-9]{' + (Get-HordeDecisionSequenceDigits) + '})\.json\z')
}

function Get-HordeDecisionStoreWin32Code {
    param($ErrorRecord)
    $ex = $ErrorRecord.Exception
    while ($null -ne $ex -and $ex -isnot [System.IO.IOException] -and $null -ne $ex.InnerException) { $ex = $ex.InnerException }
    if ($ex -isnot [System.IO.IOException]) { return -1 }
    return ($ex.HResult -band 0xFFFF)
}

function Get-HordeDecisionRecordName {
    # The file name of record -Sequence. Ten digits by default, so names sort in sequence order and a
    # store of 9,999,999,999 records fits; the name is the order, and nothing else is.
    param([Parameter(Mandatory = $true)][long]$Sequence)
    $most = Get-HordeDecisionMaxSequence
    if ($Sequence -lt 1 -or $Sequence -gt $most) { throw ("a record's sequence number is 1 to " + $most + ", not " + $Sequence) }
    return ($Sequence.ToString(("D" + (Get-HordeDecisionSequenceDigits)), [System.Globalization.CultureInfo]::InvariantCulture) + ".json")
}

function Remove-HordeDecisionStoreLeftovers {
    # Remove the temporary files dead writers left in -Root. Returns how many were removed. The header
    # states the invariant: this file's own name pattern, older than the age, AND held open by no
    # process. A file that cannot be removed is left for the next write; this never fails a write.
    param([Parameter(Mandatory = $true)][string]$Root, [datetime]$Now = [datetime]::UtcNow)
    $removed = 0
    $minAgeSeconds = Get-HordeDecisionSetting -Name "decisions.store.leftoverMinAgeSeconds"
    $found = @()
    try { $found = @([System.IO.Directory]::GetFiles($Root, "writing-*.part")) } catch { return 0 }
    foreach ($leftover in $found) {
        if ([System.IO.Path]::GetFileName($leftover) -cnotmatch $script:HordeDecisionStoreTempPattern) { continue }
        try {
            if (($Now - [System.IO.File]::GetLastWriteTimeUtc($leftover)).TotalSeconds -lt $minAgeSeconds) { continue }
            # CLAIMED, NOT JUST DELETED. A delete by name succeeds on a file its writer holds with
            # delete sharing, and takes it from under a live writer. This open is refused while ANY
            # other handle exists; if it is granted, nobody else has the file, and closing it deletes it.
            $claim = New-Object System.IO.FileStream($leftover, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None, 1, [System.IO.FileOptions]::DeleteOnClose)
            $claim.Dispose()
            $removed++
        } catch { }
    }
    return $removed
}

function Add-HordeDecisionRecord {
    # Put record -Sequence, holding -Text, in the store, in the order the header gives: written whole
    # into a temporary file this writer holds open, flushed to disk, and given the record's name by a
    # durable move that does not replace. Returns
    #   "created"      the record is in the store, and everything that makes it durable returned success;
    #   "exists"       another writer has that place in the order. Not an error: it is how a writer
    #                  learns it lost, and its caller reads the list again;
    #   "unconfirmed"  the record HAS its name, but the flush after the move failed. It must not be
    #                  reported as saved, and it must not be reported as "nothing was written" either.
    # Throws when the folder or the file cannot be made, or the move fails any other way.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][long]$Sequence, [Parameter(Mandatory = $true)][string]$Text)
    if (-not [System.IO.Path]::IsPathRooted("$Root")) { throw ("the decisions store needs an absolute folder, not '" + $Root + "'") }
    [void][System.IO.Directory]::CreateDirectory($Root)
    $recPath = Join-Path $Root (Get-HordeDecisionRecordName -Sequence $Sequence)
    $null = Remove-HordeDecisionStoreLeftovers -Root $Root
    # Encoded before any file is made: text that cannot be written as UTF-8 throws here and leaves nothing.
    $bytes = $script:HordeDecisionStoreUtf8.GetBytes($Text)
    $tmpPath = Join-Path $Root ("writing-" + [guid]::NewGuid().ToString("N") + ".part")
    # Sharing delete and nothing else: the file can be renamed while this handle is open, and nothing
    # can read or write it until it is whole and let go.
    $fs = New-Object System.IO.FileStream($tmpPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Delete, 4096, [System.IO.FileOptions]::WriteThrough)
    $moved = ""
    try {
        $fs.Write($bytes, 0, $bytes.Length)
        $fs.Flush($true)
        $moved = Move-HordeFileNewDurable -From $tmpPath -To $recPath -Open $fs
    } finally {
        $fs.Dispose()
        # Whatever went wrong, this writer's own temporary file does not stay. After a move there is no
        # file of that name, and this does nothing.
        if ($moved -cne "moved" -and $moved -cne "unconfirmed") { try { [System.IO.File]::Delete($tmpPath) } catch { } }
    }
    if ($moved -ceq "moved") { return "created" }
    if ($moved -ceq "unconfirmed") { return "unconfirmed" }
    # "exists" only when a RECORD has the name. A folder of that name is answered the same way by the
    # move, and answering "exists" for it would send the caller round its retry loop for nothing.
    if ($moved -ceq "exists" -and [System.IO.File]::Exists($recPath)) { return "exists" }
    throw ("record " + $Sequence + " could not be put in place: its name is taken by something that is not a record (the move answered '" + $moved + "')")
}

function Confirm-HordeDecisionRecord {
    # Have record -Sequence, which is already in the store, flushed through to the disk: "confirmed",
    # "unconfirmed" or "missing". For a caller about to say of an existing record "this was saved" -
    # a request sent again under the id of a save that may have been unconfirmed. The flush is core's
    # (Confirm-HordeFileDurable), the same path the move's own flush takes; this file still opens no
    # record for writing, and no byte of a record is ever changed.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][long]$Sequence)
    return (Confirm-HordeFileDurable -Path (Join-Path $Root (Get-HordeDecisionRecordName -Sequence $Sequence)))
}

function Read-HordeDecisionRecordFile {
    # Read one record file. Returns { kind: ok | missing | busy | torn | error; data; reason }.
    param([Parameter(Mandatory = $true)][string]$Path)
    $text = $null
    $heldTries = Get-HordeDecisionSetting -Name "decisions.store.heldReadTries"
    $heldWaitMs = Get-HordeDecisionSetting -Name "decisions.store.heldReadWaitMs"
    for ($try = 1; $try -le $heldTries; $try++) {
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
        if ($try -eq $heldTries) {
            return [pscustomobject]@{ kind = "busy"; data = $null; reason = ("it is still open in another process after " + ($heldTries * $heldWaitMs) + " ms; a writer is slow or stuck") }
        }
        Start-Sleep -Milliseconds $heldWaitMs
    }
    if ("$text".Trim() -eq "") { return [pscustomobject]@{ kind = "torn"; data = $null; reason = "it is empty: its writer stopped before writing it" } }
    try { $data = $text | ConvertFrom-Json } catch { return [pscustomobject]@{ kind = "torn"; data = $null; reason = "it is not complete JSON: its writer stopped while writing it, or it was damaged" } }
    if ($null -eq $data -or $data -isnot [System.Management.Automation.PSCustomObject]) { return [pscustomobject]@{ kind = "torn"; data = $null; reason = "it is not a JSON object" } }
    return [pscustomobject]@{ kind = "ok"; data = $data; reason = "" }
}

function Get-HordeDecisionRecords {
    # Every record of the store, in sequence order, damaged ones included. Returns
    #   { state: ok | absent | unknown; reason; last; records; strays }
    # state absent: there is no store folder, so nothing was ever added; records is empty and last is 0.
    # state unknown: the folder is there and could not be listed, or a file is in its place; reason says why.
    # Each record is { sequence; span; file; kind: ok | missing | busy | torn | error; data; reason }.
    # Every number from 1 to last is covered exactly once: by a record of span 1, or by ONE "missing"
    # entry whose span is how many numbers in a row have no file. A gap is never left out, because the
    # order is what a question's number is worked out from, and never walked number by number.
    # last is the end of the order: the next record a writer makes is last + 1.
    # strays is { file; reason } for every stray (see the gap limit above); none is in records or in last.
    #
    # Files whose name is not digits and .json are not looked at: they cannot be mistaken for a record.
    param([Parameter(Mandatory = $true)][string]$Root)
    $none = [pscustomobject]@{ state = "absent"; reason = "there is no decisions store yet"; last = [long]0; records = @(); strays = @() }
    $absolute = [System.IO.Path]::IsPathRooted("$Root")
    if (-not $absolute) {
        return [pscustomobject]@{ state = "unknown"; reason = ("the decisions store needs an absolute folder, not '" + $Root + "'"); last = [long]0; records = @(); strays = @() }
    }
    # A FILE of the store's name is not "no store yet": every write there fails, so a read that said
    # "an empty list" would be an answer no write could ever agree with (measured 2026-10-06).
    if ([System.IO.File]::Exists($Root)) {
        return [pscustomobject]@{ state = "unknown"; reason = ("the decisions store '" + $Root + "' is a file, not a folder"); last = [long]0; records = @(); strays = @() }
    }
    if (-not [System.IO.Directory]::Exists($Root)) { return $none }
    $names = $null
    try { $names = [System.IO.Directory]::GetFiles($Root, "*.json") }
    catch { return [pscustomobject]@{ state = "unknown"; reason = ("the decisions store '" + $Root + "' could not be listed: " + $_.Exception.Message); last = [long]0; records = @(); strays = @() } }
    $namePattern = Get-HordeDecisionStoreNamePattern
    $digits = Get-HordeDecisionSequenceDigits
    $maxGap = Get-HordeDecisionSetting -Name "decisions.store.maxGap"
    $strays = New-Object System.Collections.ArrayList
    $numbered = New-Object 'System.Collections.Generic.List[long]'
    foreach ($full in $names) {
        $leaf = [System.IO.Path]::GetFileName($full)
        if ($leaf -cnotmatch $script:HordeDecisionStoreDigitsPattern) { continue }
        if ($leaf -cnotmatch $namePattern -or [long]$Matches[1] -lt 1) {
            [void]$strays.Add([pscustomobject]@{ file = $leaf; reason = ("its name is not a sequence number from 1 written in " + $digits + " digits, so it is not a record") })
            continue
        }
        $numbered.Add([long]$Matches[1])
    }
    $numbered.Sort()
    $records = New-Object System.Collections.ArrayList
    $last = [long]0
    foreach ($seq in $numbered) {
        $leaf = Get-HordeDecisionRecordName -Sequence $seq
        $gap = $seq - $last - 1
        if ($gap -gt $maxGap) {
            [void]$strays.Add([pscustomobject]@{ file = $leaf; reason = ("it is " + $gap + " places past record " + $last + ", the last before it; more than " + $maxGap + " is too far to be a record, so it is not read and not counted") })
            continue
        }
        if ($gap -gt 0) {
            $why = "it is not in the store folder, though a later record is: it was deleted"
            if ($gap -gt 1) { $why = "records " + ($last + 1) + " to " + ($seq - 1) + " (" + $gap + " of them) are not in the store folder, though a later record is: they were deleted" }
            [void]$records.Add([pscustomobject]@{ sequence = ($last + 1); span = $gap; file = (Get-HordeDecisionRecordName -Sequence ($last + 1)); kind = "missing"; data = $null; reason = $why })
        }
        $read = Read-HordeDecisionRecordFile -Path (Join-Path $Root $leaf)
        [void]$records.Add([pscustomobject]@{ sequence = $seq; span = [long]1; file = $leaf; kind = $read.kind; data = $read.data; reason = $read.reason })
        $last = $seq
    }
    return [pscustomobject]@{ state = "ok"; reason = ""; last = $last; records = @($records); strays = @($strays) }
}
