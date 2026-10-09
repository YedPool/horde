# relay/Journal.ps1 - the relay journal: which envelopes this machine has accepted and sent, kept so
# that a replayed, reordered or reused envelope is refused, and kept whole as the record of each.
#
# WHAT IT ANSWERS. relay/Envelope.ps1 opens nothing without "a fresh verdict from the journal": a
# core/tristate answer, known, whose value is { key; fresh } with key the envelope's replay key
# (Get-HordeRelayReplayKey: from, channel, seq, nonce) and fresh the boolean $true. This file gives that
# answer, and the value carries more beside it, for whoever shows it:
#   key        the replay key of the envelope asked about;
#   fresh      $true only when THIS call recorded the envelope; $false for every refusal;
#   why        "" when fresh, otherwise the refusal in words (replay, out of order, too far ahead, ...);
#   gapBefore  how many sequence numbers were skipped just before this one: envelopes the relay
#              dropped, delayed or is withholding. Shown as "missing", never as silence (relay design,
#              Q11). 0 when nothing was skipped or the stream is new.
#   direction  in (received) or out (sent).
# Unknown, with a reason, whenever the journal cannot say: it is not a journal, it is damaged, it is
# busy past the wait, a setting is refused, or the record could not be made durable. Unknown opens
# nothing either, so every doubt costs an envelope and never lets a replay through.
#
# THE RULES OF FRESHNESS, per stream - one sender, one channel, one direction:
#   - THE SEQUENCE ONLY GOES UP. An envelope is fresh only if its seq is above every seq this stream has
#     recorded. A seq at or below it is refused: a replay if that very envelope was recorded (same seq,
#     same nonce), a reuse if the sender recorded another nonce under that seq, and out of order if the
#     seq was never recorded - it was skipped, so it was already reported missing, and an envelope that
#     arrives after a later one is refused rather than slotted in, because a window of seqs that may
#     still arrive late is exactly a window a replay can use. The relay is one ordered mailbox per
#     channel (relay design, architecture), so reordering is the relay misbehaving, not the norm.
#   - NOT TOO FAR AHEAD: a seq more than the setting seqWindow (100000) above the last is refused. Every
#     envelope is signed by a trusted sender, so this guards against that sender's own fault, not a
#     forger's: a seq of 2^53-1 would end the stream for good.
#   - THE NONCE is part of the identity and is compared on a repeated seq. It is not kept in an index of
#     its own: with the sequence strictly increasing, no envelope can be accepted twice whatever its
#     nonce, and a repeated nonce under a NEW seq is a sender's new, signed envelope.
#   - THE CLOCK, received envelopes only. ts is the sender's clock in milliseconds. An envelope more than
#     the setting clockSkewSeconds (600) ahead of this machine's clock is refused, and so is one sent
#     more than that before this journal was created: a journal made at T has never seen anything
#     older, so it cannot tell such an envelope from a replay of one it saw before it was wiped. That
#     second rule is what keeps a journal that was deleted and made again from reopening every old
#     replay. THERE IS NO "TOO OLD" WINDOW BEYOND IT, on purpose: the relay stores and forwards, and a
#     machine asleep for a day must still take the answers sent to it meanwhile; an old envelope that
#     was never recorded here is a late delivery, not a replay, and the sequence still refuses any
#     envelope at or below the last one.
#   - A REFUSAL RECORDS NOTHING, so an envelope refused for the clock is taken once the clock is right.
#
# THE FILES, under <HORDE_HOME>\relay\journal (Get-HordeRelayJournalRoot):
#   journal.json                     the marker, written once by Initialize-HordeRelayJournal:
#                                    {"v":1,"kind":"horde-relay-journal","createdAt":<ms>}.
#   in\s-<from>\c-<channel>\         one folder per received stream; out\s-<from>\c-<channel>\ per
#                                    sent one. The prefixes keep a channel named con or nul from being
#                                    a Windows device (Get-HordeRelayJournalStreamDir).
#     lock                           held, with no sharing, by the one writer of the stream (below).
#     0000000000000041.rec           one record per accepted seq, named by the seq in sixteen digits
#                                    (2^53-1 has sixteen), so names sort in seq order.
#     writing-<32 hex>.part          a writer's temporary file; it never has a record's name.
# A record is one line of metadata, then the envelope's wire text, exactly as it was signed:
#   {"v":1,"direction":"in","key":"..","from":"..","channel":"..","kind":"..","seq":41,"nonce":"..",
#    "ts":..,"recordedAt":..,"envelopeChars":..}<LF><the envelope>
# The metadata is canonical, like the envelope (relay/Envelope.ps1): one anchored pattern that admits
# exactly the text ConvertTo-HordeRelayJournalMeta writes - members in order, no spacing, no leading
# zeros - so it is never parsed loosely. The envelope is kept whole because it is the evidence: its signature
# - a machine's, or the founder's passkey assertion - proves who sent what was recorded (relay design,
# decision 4, option b). envelopeChars is how a record cut short is told from a whole one.
#
# ONE WRITER PER STREAM. A writer opens the stream's lock file with no sharing and holds it from before
# it reads the stream to after its record has its name. The operating system refuses that open to every
# other process while one holds it, and closes a dead process's handle, so a crashed writer never leaves
# the stream locked. That is what makes "above the last" a fact at the moment of the write: two racers
# with seqs 6 and 7 are taken one after the other, and the second is judged against the first. On a
# system whose file locks are advisory (.NET on Unix takes flock), every writer is this file, and they
# all ask.
#
# WRITE-ONCE, AS decisions/Store.ps1 DOES IT. A record is written whole into a temporary file the
# writer holds open, flushed through to disk, and given its name by core/FileAtomic.ps1's
# Move-HordeFileNewDurable: a move that never replaces and is written through. So a record is never
# seen half-written, never rewritten and never deleted here, and two writers can never both have one
# seq even if the lock above were not honoured: the second move is told "exists". What a writer killed
# at each step leaves:
#   before the move   a temporary file, swept by the next writer of the stream; no record; it was told
#                     nothing, so the same envelope is fresh when it comes again;
#   after the move    the whole record; it was told nothing; the same envelope is then a replay. The
#                     envelope was not opened, and the record holds it whole for a channel to find.
# So an envelope is opened at most once. "Fresh" is said only after the move answered "moved".
#
# A DAMAGED JOURNAL IS REFUSED, NEVER RESET. A record cut short, one whose metadata disagrees with its
# name or folder, a name the journal never writes, a folder or a link inside a stream, or a marker that
# is missing or not this version's: each makes the answer unknown, with the file and the reason, and
# the stream (or, for the marker, the journal) takes nothing until a person repairs it. Starting the
# stream again from nothing would accept every envelope it had already accepted. Write-once records do
# not tear in a crash (above), so a torn record is damage, not an interrupted write. And
# Initialize-HordeRelayJournal refuses a folder that holds streams but no marker: that is a journal that
# lost its marker, and a new marker would give it a later birth and say nothing about what it saw.
# THE HONEST LIMIT: a stream folder deleted whole reads as a stream never seen, and nothing here can
# tell. The clock rule above still refuses every envelope sent before the journal was made.
#
# THE PLATFORM IS NOT HERE. The durable move is core/FileAtomic.ps1's, which today has Windows' only
# and refuses elsewhere in words ("never falls back to a move that is not durable"). On any other system
# this file loads, reads, judges and answers - and every record it is asked to make is unknown with
# that reason, so nothing opens. A POSIX move for FileAtomic is that file's own change.
#
# THE SETTINGS are core/ModuleSettings.ps1's, module relay-journal, file
# <HORDE_HOME>\settings\relay-journal.json. They are read on every call, so a change takes effect at
# once; none of them can reopen a replay, because the sequence rule has no setting.
#
# Every function that judges an envelope answers a tristate and never throws for the far end's input.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Tristate.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Home.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\ModuleSettings.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\FileAtomic.ps1")
. (Join-Path $PSScriptRoot "Envelope.ps1")

$script:HordeRelayJournalSettings = New-HordeModuleSettings -Module "relay-journal" -Settings @(
    @{ name = "clockSkewSeconds"; kind = "whole"; default = 600; min = 0; max = 86400
       what = "How far, in seconds, a sender's clock may run ahead of this machine's, or behind its journal's creation." },
    @{ name = "seqWindow"; kind = "whole"; default = 100000; min = 1; max = 2147483647
       what = "How far past the last recorded sequence number one envelope may jump." },
    @{ name = "lockWaitMs"; kind = "whole"; default = 2000; min = 0; max = 60000
       what = "How long, in milliseconds, a writer waits for another writer of the same stream." }
)

$script:HordeRelayJournalMarkerName = "journal.json"
$script:HordeRelayJournalMarkerPattern = '\A\{"v":1,"kind":"horde-relay-journal","createdAt":(0|[1-9][0-9]{0,15})\}\z'
$script:HordeRelayJournalRecordPattern = '\A([0-9]{16})\.rec\z'
$script:HordeRelayJournalTempPattern = '\Awriting-[0-9a-f]{32}\.part\z'
$script:HordeRelayJournalLockName = "lock"
$script:HordeRelayJournalMetaPattern = ('\A\{"v":1,"direction":"(in|out)","key":"([0-9a-z/-]{1,128})","from":"([0-9a-f]{32})","channel":"([a-z][a-z0-9-]{0,31})",' +
    '"kind":"([a-z][a-z0-9-]{0,31})","seq":(0|[1-9][0-9]{0,15}),"nonce":"([0-9a-f]{24})","ts":(0|[1-9][0-9]{0,15}),' +
    '"recordedAt":(0|[1-9][0-9]{0,15}),"envelopeChars":(0|[1-9][0-9]{0,15})\}\z')
# Strict: bytes that are not UTF-8 throw instead of becoming U+FFFD, so damage is reported, not read.
$script:HordeRelayJournalUtf8 = New-Object System.Text.UTF8Encoding -ArgumentList @($false, $true)

function Get-HordeRelayJournalRoot {
    # The journal's folder: <home>\relay\journal. -HordeHome, when given, must be absolute; without it the
    # home is core/Home.ps1's, whose refusal of a relative HORDE_HOME is thrown as it is.
    param([string]$HordeHome = "")
    $base = $HordeHome
    if ($base -ceq "") { $base = Get-HordeHome }
    elseif (-not [System.IO.Path]::IsPathRooted($base)) { throw ("-HordeHome must be an absolute path, not '" + $base + "'") }
    return [System.IO.Path]::Combine($base, "relay", "journal")
}

function ConvertTo-HordeRelayJournalMs {
    # Milliseconds since 1970 UTC, the unit of an envelope's ts.
    param($Time)
    $when = $Time
    if ($null -eq $when) { $when = [datetime]::UtcNow }
    $epoch = New-Object datetime -ArgumentList 1970, 1, 1, 0, 0, 0, ([System.DateTimeKind]::Utc)
    return [long][System.Math]::Floor(($when.ToUniversalTime() - $epoch).TotalMilliseconds)
}

function New-HordeRelayJournalVerdict {
    param([string]$Key, [bool]$Fresh, [string]$Why, [long]$GapBefore, [string]$Direction)
    return (New-HordeKnown -Value ([pscustomobject]@{ key = $Key; fresh = $Fresh; why = $Why; gapBefore = $GapBefore; direction = $Direction }) -ObservedAt ([datetime]::UtcNow))
}

function Read-HordeRelayJournalText {
    # One file's text. { kind: ok | missing | error; text; reason }.
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        $fs = New-Object System.IO.FileStream -ArgumentList $Path, ([System.IO.FileMode]::Open), ([System.IO.FileAccess]::Read), ([System.IO.FileShare]::Read)
        try {
            $reader = New-Object System.IO.StreamReader -ArgumentList $fs, $script:HordeRelayJournalUtf8, $false
            try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
        } finally { $fs.Dispose() }
    } catch {
        $cause = $_.Exception
        while ($null -ne $cause.InnerException) { $cause = $cause.InnerException }
        if ($cause -is [System.IO.FileNotFoundException] -or $cause -is [System.IO.DirectoryNotFoundException]) { return [pscustomobject]@{ kind = "missing"; text = $null; reason = "it is not there" } }
        return [pscustomobject]@{ kind = "error"; text = $null; reason = ("it could not be read: " + $cause.Message) }
    }
    return [pscustomobject]@{ kind = "ok"; text = $text; reason = "" }
}

function Read-HordeRelayJournalMarker {
    # Is -Root a journal of this version? { ok; createdAt; reason }. No marker is NOT an empty journal: a
    # mistyped home or a disk not mounted would read as "nothing seen" and let every replay through.
    param([Parameter(Mandatory = $true)][string]$Root)
    $m = Read-HordeRelayJournalText -Path ([System.IO.Path]::Combine($Root, $script:HordeRelayJournalMarkerName))
    if ($m.kind -cne "ok") { return [pscustomobject]@{ ok = $false; createdAt = [long]-1; reason = ("'" + $Root + "' is not a relay journal: its marker " + $script:HordeRelayJournalMarkerName + " " + $m.reason + ". That is unknown, not an empty journal; Initialize-HordeRelayJournal makes one") } }
    if ($m.text -cnotmatch $script:HordeRelayJournalMarkerPattern) { return [pscustomobject]@{ ok = $false; createdAt = [long]-1; reason = ("the marker of the relay journal '" + $Root + "' is damaged or of another version, so the journal is unknown; it is not made again over it") } }
    return [pscustomobject]@{ ok = $true; createdAt = [long]$Matches[1]; reason = "" }
}

function ConvertTo-HordeRelayJournalMeta {
    # The canonical metadata line of a record. Every string was checked against its alphabet by
    # Read-HordeRelayEnvelope, so nothing needs escaping.
    param([string]$Direction, $Header, [string]$Key, [long]$RecordedAt, [long]$EnvelopeChars)
    return ('{"v":1,"direction":"' + $Direction + '","key":"' + $Key + '","from":"' + $Header.from + '","channel":"' + $Header.channel + '","kind":"' + $Header.kind +
        '","seq":' + $Header.seq + ',"nonce":"' + $Header.nonce + '","ts":' + $Header.ts + ',"recordedAt":' + $RecordedAt + ',"envelopeChars":' + $EnvelopeChars + '}')
}

function Get-HordeRelayJournalRecordName {
    param([Parameter(Mandatory = $true)][long]$Seq)
    return ($Seq.ToString("D16", [System.Globalization.CultureInfo]::InvariantCulture) + ".rec")
}

function Read-HordeRelayJournalRecord {
    # One record, checked against where it is: { ok; meta; reason }, meta { seq; nonce; key; recordedAt }.
    # Anything but a whole record of this direction, stream and seq is damage.
    param([string]$Dir, [string]$Direction, [string]$From, [string]$Channel, [long]$Seq)
    $name = Get-HordeRelayJournalRecordName -Seq $Seq
    $where = $Direction + "/" + $From + "/" + $Channel + "/" + $name
    $r = Read-HordeRelayJournalText -Path ([System.IO.Path]::Combine($Dir, $name))
    if ($r.kind -cne "ok") { return [pscustomobject]@{ ok = $false; meta = $null; reason = ("the record " + $where + " " + $r.reason) } }
    $cut = $r.text.IndexOf("`n")
    if ($cut -lt 0) { return [pscustomobject]@{ ok = $false; meta = $null; reason = ("the record " + $where + " is cut short: it has no envelope") } }
    $line = $r.text.Substring(0, $cut)
    if ($line -cnotmatch $script:HordeRelayJournalMetaPattern) { return [pscustomobject]@{ ok = $false; meta = $null; reason = ("the record " + $where + " is damaged: its first line is not a record's") } }
    $g = $Matches
    $mSeq = [long]$g[6]; $mNonce = $g[7]
    if ($g[1] -cne $Direction -or $g[3] -cne $From -or $g[4] -cne $Channel -or $mSeq -ne $Seq) { return [pscustomobject]@{ ok = $false; meta = $null; reason = ("the record " + $where + " is damaged: it says it is " + $g[1] + "/" + $g[3] + "/" + $g[4] + " seq " + $mSeq + ", not what its name and folder say") } }
    if ($g[2] -cne ($g[3] + "/" + $g[4] + "/" + $mSeq + "/" + $mNonce)) { return [pscustomobject]@{ ok = $false; meta = $null; reason = ("the record " + $where + " is damaged: its key is not its own from, channel, seq and nonce") } }
    if (($r.text.Length - $cut - 1) -ne [long]$g[10]) { return [pscustomobject]@{ ok = $false; meta = $null; reason = ("the record " + $where + " is cut short or grown: its envelope is " + ($r.text.Length - $cut - 1) + " characters, and it was written with " + $g[10]) } }
    return [pscustomobject]@{ ok = $true; meta = [pscustomobject]@{ seq = $mSeq; nonce = $mNonce; key = $g[2]; recordedAt = [long]$g[9] }; reason = "" }
}

function Get-HordeRelayJournalStreamDir {
    # A stream's folder: <root>\<in|out>\s-<from>\c-<channel>. THE PREFIXES ARE WHY NO NAME IS A DEVICE:
    # a channel is any lower-case word, and con, aux, nul, prn, com1 or lpt1 as a folder's whole name is
    # a device on Windows (review of 6f7e8c1, finding 1). Every folder named from an envelope carries one.
    param([string]$Root, [string]$Direction, [string]$From, [string]$Channel)
    return [System.IO.Path]::Combine($Root, $Direction, ("s-" + $From), ("c-" + $Channel))
}

function Get-HordeRelayJournalStream {
    # What one stream folder holds: { ok; reason; last; seqs; temps }. last is the highest recorded seq,
    # or -1 for a stream with no record (no folder yet). seqs is a hashtable of every recorded seq, as
    # text. The highest record is read and checked, since every verdict is judged against it; anything
    # in the folder the journal never writes is damage.
    #
    # -MustExist: the caller has just made the folder, so "not found" is not "no record yet" but a folder
    # the system will not show - damage, answered as such. Without it (a read that makes nothing), no
    # folder is a stream with no record.
    #
    # LISTED BY [System.IO.Directory], NOT Get-ChildItem. Review of 6f7e8c1, finding 1: under Windows
    # PowerShell 5.1, Get-ChildItem -LiteralPath on a folder named like a device (con, aux, nul, prn,
    # com1, lpt1) answers PathNotFound, so such a stream read as empty on every call and its sequence,
    # window and damage rules were off. Stream folders are prefixed now (Get-HordeRelayJournalStreamDir),
    # so no device name can occur; the listing is the framework's own as well, so nothing between this
    # file and the folder reinterprets a name.
    param([string]$Dir, [string]$Direction, [string]$From, [string]$Channel, [bool]$MustExist = $false)
    $seqs = @{}
    $temps = New-Object System.Collections.ArrayList
    $last = [long]-1
    $limit = (Get-HordeRelayEnvelopeLimits).maxInteger
    $where = $Direction + "/" + $From + "/" + $Channel
    $entries = @()
    try {
        $entries = @([System.IO.Directory]::EnumerateFileSystemEntries($Dir) | ForEach-Object { [pscustomobject]@{ path = $_; name = [System.IO.Path]::GetFileName($_); attrs = [System.IO.File]::GetAttributes($_) } })
    } catch {
        $cause = $_.Exception
        while ($null -ne $cause.InnerException) { $cause = $cause.InnerException }
        if ($cause -is [System.IO.DirectoryNotFoundException]) {
            if ($MustExist) { return [pscustomobject]@{ ok = $false; reason = ("the stream " + $where + " was just made and is not found: the system will not show this folder, so its records cannot be read"); last = $last; seqs = $seqs; temps = @() } }
            return [pscustomobject]@{ ok = $true; reason = ""; last = $last; seqs = $seqs; temps = @() }
        }
        return [pscustomobject]@{ ok = $false; reason = ("the stream " + $where + " could not be listed: " + $cause.Message); last = $last; seqs = $seqs; temps = @() }
    }
    foreach ($e in $entries) {
        $nm = "" + $e.name
        # The entry's own attributes: GetAttributes does not follow a link.
        if (($e.attrs -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return [pscustomobject]@{ ok = $false; reason = ("the stream " + $where + " holds a link, " + $nm + "; the journal never writes one and never follows one"); last = $last; seqs = $seqs; temps = @() } }
        if (($e.attrs -band [System.IO.FileAttributes]::Directory) -ne 0) { return [pscustomobject]@{ ok = $false; reason = ("the stream " + $where + " holds a folder, " + $nm + "; the journal never makes one there"); last = $last; seqs = $seqs; temps = @() } }
        if ($nm -ceq $script:HordeRelayJournalLockName) { continue }
        if ($nm -cmatch $script:HordeRelayJournalTempPattern) { [void]$temps.Add($e.path); continue }
        if ($nm -cnotmatch $script:HordeRelayJournalRecordPattern) { return [pscustomobject]@{ ok = $false; reason = ("the stream " + $where + " holds " + $nm + ", a file the journal never writes"); last = $last; seqs = $seqs; temps = @() } }
        $s = [long]$Matches[1]
        if ($s -gt $limit) { return [pscustomobject]@{ ok = $false; reason = ("the stream " + $where + " holds " + $nm + ", past the largest sequence number an envelope can carry"); last = $last; seqs = $seqs; temps = @() } }
        $seqs["" + $s] = $true
        if ($s -gt $last) { $last = $s }
    }
    if ($last -ge 0) {
        $top = Read-HordeRelayJournalRecord -Dir $Dir -Direction $Direction -From $From -Channel $Channel -Seq $last
        if (-not $top.ok) { return [pscustomobject]@{ ok = $false; reason = $top.reason; last = $last; seqs = $seqs; temps = @() } }
    }
    return [pscustomobject]@{ ok = $true; reason = ""; last = $last; seqs = $seqs; temps = @($temps) }
}

function Enter-HordeRelayJournalLock {
    # Hold the stream's lock: its lock file opened with no sharing. { ok; held; reason }. The caller
    # disposes held. Tried until -WaitMs has passed; a dead holder's handle is closed by the system.
    param([string]$Dir, [int]$WaitMs)
    $path = [System.IO.Path]::Combine($Dir, $script:HordeRelayJournalLockName)
    # In ticks, not AddMilliseconds or New-TimeSpan -Milliseconds: the first is not on tools/ExecScan.ps1's
    # list and the second is not in Windows PowerShell 5.1 (measured 2026-10-09).
    $deadline = [datetime]::UtcNow.Ticks + [long]$WaitMs * 10000
    $why = ""
    while ($true) {
        try {
            # Made once, empty, and never deleted: deleting a lock file is how two holders come to hold
            # two different files of one name.
            $made = New-Object System.IO.FileStream -ArgumentList $path, ([System.IO.FileMode]::CreateNew), ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::None)
            $made.Dispose()
        } catch { }
        try {
            $held = New-Object System.IO.FileStream -ArgumentList $path, ([System.IO.FileMode]::Open), ([System.IO.FileAccess]::Read), ([System.IO.FileShare]::None)
            return [pscustomobject]@{ ok = $true; held = $held; reason = "" }
        } catch { $why = $_.Exception.Message }
        if ([datetime]::UtcNow.Ticks -ge $deadline) { return [pscustomobject]@{ ok = $false; held = $null; reason = ("another writer held the stream's lock for longer than " + $WaitMs + " ms (" + $why + ")") } }
        Start-Sleep -Milliseconds 20
    }
}

function Remove-HordeRelayJournalLeftovers {
    # Remove temporary files that dead writers left in a stream. Called with the stream's lock held, so
    # no live writer of this file is writing there; each is still CLAIMED, opened with no sharing to be
    # deleted on close, which the system refuses while any process holds it (decisions/Store.ps1's
    # sweep, condition 3), in case a writer did not take the lock. A file that cannot be claimed is left.
    param([object[]]$Temps)
    foreach ($t in @($Temps)) {
        try {
            $claim = New-Object System.IO.FileStream -ArgumentList $t, ([System.IO.FileMode]::Open), ([System.IO.FileAccess]::Read), ([System.IO.FileShare]::None), 1, ([System.IO.FileOptions]::DeleteOnClose)
            $claim.Dispose()
        } catch { }
    }
}

function Write-HordeRelayJournalFile {
    # Put -Text under the name -Name in -Dir, write-once: written whole into a temporary file this
    # writer holds open, flushed to disk, and named by a durable move that never replaces. "moved",
    # "exists" or "unconfirmed" (core/FileAtomic.ps1); throws otherwise, leaving no temporary file.
    param([string]$Dir, [string]$Name, [string]$Text)
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Text)
    $tmp = [System.IO.Path]::Combine($Dir, ("writing-" + [guid]::NewGuid().ToString("N") + ".part"))
    # Shared for delete only: it can be renamed while held, and nothing reads it before it is whole.
    $fs = New-Object System.IO.FileStream -ArgumentList $tmp, ([System.IO.FileMode]::CreateNew), ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::Delete), 4096, ([System.IO.FileOptions]::WriteThrough)
    $moved = ""
    try {
        $fs.Write($bytes, 0, $bytes.Length)
        $fs.Flush($true)
        $moved = Move-HordeFileNewDurable -From $tmp -To ([System.IO.Path]::Combine($Dir, $Name)) -Open $fs
    } finally {
        $fs.Dispose()
        if ($moved -cne "moved" -and $moved -cne "unconfirmed") { try { [System.IO.File]::Delete($tmp) } catch { } }
    }
    return $moved
}

function Initialize-HordeRelayJournal {
    # Make the journal: its folder and its marker, once. Again on a journal that is there answers with
    # it unchanged. Refused, as unknown, when the marker is damaged or when the folder holds streams but
    # no marker (the header: a new marker over old streams is a repair, not a creation).
    # Known { root; createdAt } or unknown.
    param([string]$HordeHome = "", $Now = $null)
    try { $root = Get-HordeRelayJournalRoot -HordeHome $HordeHome } catch { return (New-HordeUnknown -Reason "the relay journal has no folder" -ErrorRecord $_) }
    $m = Read-HordeRelayJournalMarker -Root $root
    if ($m.ok) { return (New-HordeKnown -Value ([pscustomobject]@{ root = $root; createdAt = $m.createdAt }) -ObservedAt ([datetime]::UtcNow)) }
    $present = @()
    try { $present = @(Get-ChildItem -LiteralPath $root -Force -ErrorAction Stop | ForEach-Object { "" + $_.Name }) } catch { }
    if ($present -ccontains $script:HordeRelayJournalMarkerName) { return (New-HordeUnknown -Reason $m.reason) }
    if ($present -ccontains "in" -or $present -ccontains "out") { return (New-HordeUnknown -Reason ("'" + $root + "' holds a journal's streams and no marker: the marker was lost. A new one is not written over them; a person restores it")) }
    $createdAt = ConvertTo-HordeRelayJournalMs -Time $Now
    try {
        [void][System.IO.Directory]::CreateDirectory($root)
        $moved = Write-HordeRelayJournalFile -Dir $root -Name $script:HordeRelayJournalMarkerName -Text ('{"v":1,"kind":"horde-relay-journal","createdAt":' + $createdAt + '}')
    } catch { return (New-HordeUnknown -Reason ("the relay journal '" + $root + "' could not be made") -ErrorRecord $_) }
    if ($moved -ceq "unconfirmed") { return (New-HordeUnknown -Reason ("the marker of the relay journal '" + $root + "' has its name, but the flush after the move failed, so nothing says it is on disk")) }
    # "exists": another process made it at the same moment. Its marker is the journal's.
    $m = Read-HordeRelayJournalMarker -Root $root
    if (-not $m.ok) { return (New-HordeUnknown -Reason $m.reason) }
    return (New-HordeKnown -Value ([pscustomobject]@{ root = $root; createdAt = $m.createdAt }) -ObservedAt ([datetime]::UtcNow))
}

function Get-HordeRelayJournalContext {
    # The settings and the marker a call works under: { ok; reason; root; createdAt; settings }.
    param([string]$HordeHome)
    $fail = [pscustomobject]@{ ok = $false; reason = ""; root = ""; createdAt = [long]-1; settings = $null }
    try {
        $root = Get-HordeRelayJournalRoot -HordeHome $HordeHome
        $homeDir = $HordeHome
        if ($homeDir -ceq "") { $homeDir = Get-HordeHome }
        $s = Get-HordeModuleSettings -Declaration $script:HordeRelayJournalSettings -HordeHome $homeDir
    } catch { $fail.reason = ("the relay journal cannot be found: " + $_.Exception.Message); return $fail }
    if ($s.state -ceq "refused") { $fail.reason = ($s.findings -join " "); return $fail }
    $m = Read-HordeRelayJournalMarker -Root $root
    if (-not $m.ok) { $fail.reason = $m.reason; return $fail }
    return [pscustomobject]@{ ok = $true; reason = ""; root = $root; createdAt = $m.createdAt; settings = $s.values }
}

function Add-HordeRelayJournalEntry {
    # The one path both directions take: judge -Header against its stream, under the stream's lock, and
    # record -Text when it is fresh. A verdict (see the header) or unknown.
    param([string]$Direction, $Header, [string]$Text, [string]$HordeHome, $Now, [bool]$CheckClock)
    $ctx = Get-HordeRelayJournalContext -HordeHome $HordeHome
    if (-not $ctx.ok) { return (New-HordeUnknown -Reason ($ctx.reason + "; nothing was recorded")) }
    $key = Get-HordeRelayReplayKey -Header $Header
    $seq = [long]$Header.seq
    $nowMs = ConvertTo-HordeRelayJournalMs -Time $Now
    $skewMs = [long]$ctx.settings.clockSkewSeconds * 1000
    $dir = Get-HordeRelayJournalStreamDir -Root $ctx.root -Direction $Direction -From $Header.from -Channel $Header.channel
    try { [void][System.IO.Directory]::CreateDirectory($dir) } catch { return (New-HordeUnknown -Reason ("the stream folder of " + $key + " could not be made") -ErrorRecord $_) }
    $lock = Enter-HordeRelayJournalLock -Dir $dir -WaitMs $ctx.settings.lockWaitMs
    if (-not $lock.ok) { return (New-HordeUnknown -Reason ("the journal is busy for " + $key + ": " + $lock.reason + "; nothing was recorded")) }
    try {
        $st = Get-HordeRelayJournalStream -Dir $dir -Direction $Direction -From $Header.from -Channel $Header.channel -MustExist $true
        if (-not $st.ok) { return (New-HordeUnknown -Reason ($st.reason + ". The journal is damaged; it is not reset, because that would accept again what it already accepted, so this stream takes nothing until a person repairs it")) }
        Remove-HordeRelayJournalLeftovers -Temps $st.temps
        $last = $st.last
        if ($last -ge 0 -and $seq -le $last) {
            if ($st.seqs.ContainsKey("" + $seq)) {
                $same = Read-HordeRelayJournalRecord -Dir $dir -Direction $Direction -From $Header.from -Channel $Header.channel -Seq $seq
                if (-not $same.ok) { return (New-HordeUnknown -Reason ($same.reason + ". The journal is damaged; it is not reset, so this stream takes nothing until a person repairs it")) }
                if ($same.meta.nonce -ceq $Header.nonce) { return (New-HordeRelayJournalVerdict -Key $key -Fresh $false -Why ("a replay: this envelope was recorded at " + $same.meta.recordedAt + " ms") -GapBefore 0 -Direction $Direction) }
                return (New-HordeRelayJournalVerdict -Key $key -Fresh $false -Why ("seq " + $seq + " was already recorded with another nonce: the sender used one sequence number twice") -GapBefore 0 -Direction $Direction)
            }
            return (New-HordeRelayJournalVerdict -Key $key -Fresh $false -Why ("out of order: seq " + $seq + " arrived after seq " + $last + ", so it was skipped and is reported missing; it is not taken late") -GapBefore 0 -Direction $Direction)
        }
        if ($last -ge 0 -and ($seq - $last) -gt [long]$ctx.settings.seqWindow) {
            return (New-HordeRelayJournalVerdict -Key $key -Fresh $false -Why ("seq " + $seq + " is " + ($seq - $last) + " past the last recorded, " + $last + "; more than the window of " + $ctx.settings.seqWindow) -GapBefore 0 -Direction $Direction)
        }
        if ($CheckClock) {
            $ts = [long]$Header.ts
            if ($ts -gt ($nowMs + $skewMs)) { return (New-HordeRelayJournalVerdict -Key $key -Fresh $false -Why ("sent at " + $ts + " ms, more than " + $ctx.settings.clockSkewSeconds + " s ahead of this machine's clock (" + $nowMs + " ms)") -GapBefore 0 -Direction $Direction) }
            if ($ts -lt ($ctx.createdAt - $skewMs)) { return (New-HordeRelayJournalVerdict -Key $key -Fresh $false -Why ("sent at " + $ts + " ms, more than " + $ctx.settings.clockSkewSeconds + " s before this journal was made (" + $ctx.createdAt + " ms), so it cannot be told from a replay") -GapBefore 0 -Direction $Direction) }
        }
        $meta = ConvertTo-HordeRelayJournalMeta -Direction $Direction -Header $Header -Key $key -RecordedAt $nowMs -EnvelopeChars $Text.Length
        try { $moved = Write-HordeRelayJournalFile -Dir $dir -Name (Get-HordeRelayJournalRecordName -Seq $seq) -Text ($meta + "`n" + $Text) }
        catch { return (New-HordeUnknown -Reason ("the envelope " + $key + " could not be recorded, so it is not fresh") -ErrorRecord $_) }
        if ($moved -ceq "moved") {
            $gap = [long]0
            if ($last -ge 0) { $gap = $seq - $last - 1 }
            return (New-HordeRelayJournalVerdict -Key $key -Fresh $true -Why "" -GapBefore $gap -Direction $Direction)
        }
        if ($moved -ceq "exists") { return (New-HordeRelayJournalVerdict -Key $key -Fresh $false -Why ("another writer recorded seq " + $seq + " at the same moment") -GapBefore 0 -Direction $Direction) }
        return (New-HordeUnknown -Reason ("the envelope " + $key + " has its record, but the flush after the move failed, so nothing says it is on disk; it is not fresh"))
    } finally { $lock.held.Dispose() }
}

function Register-HordeRelayJournalReceived {
    # A received envelope, read by Read-HordeRelayEnvelope: verify its signature against -Senders (so
    # nothing unauthenticated is ever recorded), then judge and record it. The verdict
    # Unprotect-HordeRelayEnvelope takes as -Replay, or unknown.
    param([Parameter(Mandatory = $true)]$Envelope, [Parameter(Mandatory = $true)][hashtable]$Senders, [string]$HordeHome = "", $Now = $null)
    $verified = Test-HordeRelayEnvelope -Envelope $Envelope -Senders $Senders
    if (-not $verified.ok) { return (New-HordeUnknown -Reason ("the envelope is not verified, so the journal does not judge it: " + $verified.reason)) }
    $e = $verified.value.envelope
    # The wire text rebuilt from its parts: exactly what was signed, since Test checked the parts.
    $text = '{"header":' + $e.headerText + ',"recipients":' + $e.recipientsText + ',"ct":"' + $e.ctText + '","sig":' + (ConvertTo-HordeRelaySigText -Sig $e.sig) + '}'
    return (Add-HordeRelayJournalEntry -Direction "in" -Header $verified.value.header -Text $text -HordeHome $HordeHome -Now $Now -CheckClock $true)
}

function Register-HordeRelayJournalSent {
    # An envelope this machine is about to send, as wire text: recorded BEFORE it is put on the relay, so
    # its seq is taken for good whatever happens next. Fresh means "recorded; send it". A seq at or below
    # the last sent is refused: two different envelopes under one seq would make the second a "reuse"
    # at every recipient. Get-HordeRelayJournalNextSeq says which seq to use.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text, [string]$HordeHome = "", $Now = $null)
    $r = Read-HordeRelayEnvelope -Text $Text
    if (-not $r.ok) { return (New-HordeUnknown -Reason ("this is not an envelope, so it is not recorded: " + $r.reason)) }
    return (Add-HordeRelayJournalEntry -Direction "out" -Header $r.value.header -Text $Text -HordeHome $HordeHome -Now $Now -CheckClock $false)
}

function Get-HordeRelayJournalNextSeq {
    # The seq this machine's next envelope from -From on -Channel should carry: one past the last sent,
    # or 1 for a stream that has sent nothing. Known [long], or unknown. Two senders that ask at once are
    # told the same number; the second to record it is refused, and asks again.
    param([Parameter(Mandatory = $true)][string]$From, [Parameter(Mandatory = $true)][string]$Channel, [string]$HordeHome = "")
    if ($From -cnotmatch '\A[0-9a-f]{32}\z' -or $Channel -cnotmatch '\A[a-z][a-z0-9-]{0,31}\z') { return (New-HordeUnknown -Reason "a stream is a 32-hex key id and a lower-case channel word") }
    $ctx = Get-HordeRelayJournalContext -HordeHome $HordeHome
    if (-not $ctx.ok) { return (New-HordeUnknown -Reason $ctx.reason) }
    $st = Get-HordeRelayJournalStream -Dir (Get-HordeRelayJournalStreamDir -Root $ctx.root -Direction "out" -From $From -Channel $Channel) -Direction "out" -From $From -Channel $Channel
    if (-not $st.ok) { return (New-HordeUnknown -Reason ($st.reason + ". The journal is damaged and is not reset")) }
    if ($st.last -lt 0) { return (New-HordeKnown -Value ([long]1) -ObservedAt ([datetime]::UtcNow)) }
    if ($st.last -ge (Get-HordeRelayEnvelopeLimits).maxInteger) { return (New-HordeUnknown -Reason ("the stream out/" + $From + "/" + $Channel + " has used every sequence number an envelope can carry")) }
    return (New-HordeKnown -Value ([long]($st.last + 1)) -ObservedAt ([datetime]::UtcNow))
}
