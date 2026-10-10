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
#              Q11). A new stream counts from 0, so its first seq 10 says 9 are missing; 0 when
#              nothing was skipped.
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
#   - NOT TOO FAR AHEAD: a seq more than the setting seqWindow (100000) above the last is refused, and a
#     new stream's first seq is measured from 0 the same way (review of 6f7e8c1, finding 3: the first
#     envelope was exempt, so a first seq of 2^53-1 ended the stream). Every envelope is signed by a
#     trusted sender, so this guards against that sender's own fault, not a forger's.
#   - THE NONCE is part of the identity and is compared on a repeated seq. It is not kept in an index of
#     its own: with the sequence strictly increasing, no envelope can be accepted twice whatever its
#     nonce, and a repeated nonce under a NEW seq is a sender's new, signed envelope.
#   - THE CLOCK, received envelopes only. ts is the sender's clock in milliseconds. An envelope more than
#     the setting clockSkewSeconds (600) ahead of this machine's clock is refused, and so is one sent
#     more than that before this journal was created: a journal made at T has never seen anything
#     older, so it cannot tell such an envelope from a replay of one it saw before it was wiped. That
#     second rule is what keeps a journal that was deleted and made again from reopening EVERY old
#     replay - though not the ones sent within the skew before it was remade (THE HONEST LIMIT, below).
#     THERE IS NO "TOO OLD" WINDOW BEYOND IT, on purpose: the relay stores and forwards, and a
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
#     0000000000000041.done          received streams only: the channel that opened record 41 has
#                                    finished with it (FINISHED AND UNFINISHED, below).
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
# THE HONEST LIMIT (review of 6f7e8c1, finding 5): THE JOURNAL DEFENDS AGAINST CRASHES AND DAMAGE,
# NOT AGAINST WHOEVER CAN WRITE TO ITS FOLDER. Anyone with local write access to <HORDE_HOME> can make it
# accept a replay, and nothing here can tell:
#   - deleting a stream's highest record lowers its last seq, and that envelope is fresh again;
#   - deleting a stream folder, or in\ whole, makes its streams read as never seen;
#   - deleting the whole journal and calling Initialize again makes a new journal, which takes every
#     envelope sent within clockSkewSeconds (600 by default, an hour at most) before it was remade.
# The clock rule bounds the last case and nothing bounds the first two. Such access is already the
# machine owner's and outside what a journal on that machine can defend. What the
# journal does promise is that it never resets ITSELF - a crash, a torn file or a lost marker is refused,
# not repaired.
#
# FINISHED AND UNFINISHED (relay PR 6, the decisions channel). A record is written BEFORE its envelope is
# opened, so a process killed between the record and the end of what its channel does with the body -
# put an answer into the decisions store, say - leaves a record whose envelope will never be fresh
# again. "After the move: the whole record ... for a channel to find" (above) is that case, and this is
# how a channel finds it:
#   - Complete-HordeRelayJournalReceived writes <seq>.done beside a received record, write-once, when its
#     channel has finished with it - done, or refused for good. Nothing else ever writes one, and a done
#     mark names a record of its stream or the stream is damaged.
#   - Get-HordeRelayJournalUnfinished lists every received record of a channel with no done mark, each
#     with its envelope's wire text, its EVIDENCE and a verdict for Unprotect-HordeRelayEnvelope: known,
#     the record's own replay key, fresh $true and resumed $true. "Fresh" keeps its meaning for the opener:
#     this journal recorded this envelope once and no channel has finished with it. The signature, the
#     channel and the kind are checked again by Unprotect against the senders trusted NOW, so a device
#     revoked since the record was made opens nothing.
#   - EXACTLY ONCE IS THE CHANNEL'S, ON TOP OF THIS. A process killed after the channel acted and before
#     the done mark hands the envelope to its channel again. So a channel's act is idempotent by the
#     record's replay key (the decisions channel derives its request id from it), and the done mark is
#     only what keeps a finished record from being opened for ever.
#   - EVIDENCE (Get-HordeRelayJournalEvidence) is the SHA-256, in lower-case hex, of the whole record
#     file - its metadata line and the envelope exactly as signed. A decision record holds this hash and
#     nothing more (the founder's decision of 2026-10-09); the record here is the proof it points to.
# The honest limit above holds here too: whoever can delete a done mark makes its record unfinished
# again, and its channel's idempotency is then the only thing that keeps it from acting twice.
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
    # At most an hour (review of 6f7e8c1, finding 5): the skew is also how far before its creation a
    # remade journal takes envelopes (THE HONEST LIMIT, above), so a larger one would widen what a wipe
    # reopens, and a sender's clock an hour wrong is broken, not skewed.
    @{ name = "clockSkewSeconds"; kind = "whole"; default = 600; min = 0; max = 3600
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
$script:HordeRelayJournalDonePattern = '\A([0-9]{16})\.done\z'
$script:HordeRelayJournalSenderDirPattern = '\As-([0-9a-f]{32})\z'
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
    return [pscustomobject]@{ ok = $true; meta = [pscustomobject]@{ seq = $mSeq; nonce = $mNonce; key = $g[2]; recordedAt = [long]$g[9]; kind = $g[5] }; reason = ""
        envelope = $r.text.Substring($cut + 1); whole = $r.text }
}

function Get-HordeRelayJournalStreamDir {
    # A stream's folder: <root>\<in|out>\s-<from>\c-<channel>. THE PREFIXES ARE WHY NO NAME IS A DEVICE:
    # a channel is any lower-case word, and con, aux, nul, prn, com1 or lpt1 as a folder's whole name is
    # a device on Windows (review of 6f7e8c1, finding 1). Every folder named from an envelope carries one.
    param([string]$Root, [string]$Direction, [string]$From, [string]$Channel)
    return [System.IO.Path]::Combine($Root, $Direction, ("s-" + $From), ("c-" + $Channel))
}

function Get-HordeRelayJournalStream {
    # What one stream folder holds: { ok; reason; last; seqs; temps; dones }. last is the highest
    # recorded seq, or -1 for a stream with no record (no folder yet). seqs is a hashtable of every
    # recorded seq, as text, and dones of every seq with a done mark (FINISHED AND UNFINISHED). The highest record is read and checked, since every verdict is judged against it; anything
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
    $dones = @{}
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
            return [pscustomobject]@{ ok = $true; reason = ""; last = $last; seqs = $seqs; temps = @(); dones = $dones }
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
        if ($Direction -ceq "in" -and $nm -cmatch $script:HordeRelayJournalDonePattern) { $dones["" + [long]$Matches[1]] = $true; continue }
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
    # A done mark names a record of its stream: one beside nothing marks what this journal never took.
    foreach ($d in @($dones.Keys)) {
        if (-not $seqs.ContainsKey($d)) { return [pscustomobject]@{ ok = $false; reason = ("the stream " + $where + " holds a done mark for seq " + $d + ", which it never recorded"); last = $last; seqs = $seqs; temps = @() } }
    }
    return [pscustomobject]@{ ok = $true; reason = ""; last = $last; seqs = $seqs; temps = @($temps); dones = $dones }
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
        # A new stream is measured from 0, for the window and for the gap (the header).
        $base = $(if ($last -ge 0) { $last } else { [long]0 })
        if (($seq - $base) -gt [long]$ctx.settings.seqWindow) {
            return (New-HordeRelayJournalVerdict -Key $key -Fresh $false -Why ("seq " + $seq + " is " + ($seq - $base) + " past " + $(if ($last -ge 0) { "the last recorded, " + $last } else { "0, where a new stream starts" }) + "; more than the window of " + $ctx.settings.seqWindow) -GapBefore 0 -Direction $Direction)
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
            $gap = [long][System.Math]::Max([long]0, $seq - $base - 1)
            return (New-HordeRelayJournalVerdict -Key $key -Fresh $true -Why "" -GapBefore $gap -Direction $Direction)
        }
        if ($moved -ceq "exists") { return (New-HordeRelayJournalVerdict -Key $key -Fresh $false -Why ("another writer recorded seq " + $seq + " at the same moment") -GapBefore 0 -Direction $Direction) }
        return (New-HordeUnknown -Reason ("the envelope " + $key + " has its record, but the flush after the move failed, so nothing says it is on disk; it is not fresh"))
    } finally { $lock.held.Dispose() }
}

function Register-HordeRelayJournalReceived {
    # A received envelope, read by Read-HordeRelayEnvelope: verify its signature against -Senders (so
    # nothing unauthenticated is ever recorded), require that it is addressed to one of this machine's
    # agree keys (-RecipientKeyIds) and is of the -Channel and -Kind the caller expects, then judge and
    # record it. The verdict Unprotect-HordeRelayEnvelope takes as -Replay, or unknown.
    #
    # WHY THE ADDRESS IS CHECKED HERE, BEFORE ANYTHING IS RECORDED (review of 6f7e8c1, finding 2). A
    # sender's seq is per channel, not per recipient, so an envelope it sent only to another machine
    # carries a seq too. Recorded here, it took the stream's place: this machine's own envelope with a
    # lower seq, arriving after it, was refused as out of order. Unprotect refuses such an envelope as
    # well, but only after the journal had already spent the seq.
    param([Parameter(Mandatory = $true)]$Envelope, [Parameter(Mandatory = $true)][hashtable]$Senders,
        [Parameter(Mandatory = $true)][string[]]$RecipientKeyIds, [Parameter(Mandatory = $true)][string]$Channel,
        [Parameter(Mandatory = $true)][string]$Kind, [string]$HordeHome = "", $Now = $null)
    $verified = Test-HordeRelayEnvelope -Envelope $Envelope -Senders $Senders
    if (-not $verified.ok) { return (New-HordeUnknown -Reason ("the envelope is not verified, so the journal does not judge it: " + $verified.reason)) }
    $vh = $verified.value.header
    if ($vh.channel -cne $Channel) { return (New-HordeUnknown -Reason ("the envelope is for the channel " + $vh.channel + ", not " + $Channel + ", so the journal does not judge it and records nothing")) }
    if ($vh.kind -cne $Kind) { return (New-HordeUnknown -Reason ("the envelope is of the kind " + $vh.kind + ", not " + $Kind + ", so the journal does not judge it and records nothing")) }
    $forMe = @(@($vh.to) | Where-Object { $RecipientKeyIds -ccontains $_ })
    if ($forMe.Count -eq 0) { return (New-HordeUnknown -Reason "the envelope is not addressed to this machine, so the journal does not judge it and records nothing") }
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

function Get-HordeRelayJournalDoneName {
    param([Parameter(Mandatory = $true)][long]$Seq)
    return ($Seq.ToString("D16", [System.Globalization.CultureInfo]::InvariantCulture) + ".done")
}

function Test-HordeRelayJournalStreamName {
    # "" when -From and -Channel can name a received stream, else why not.
    param([string]$From, [string]$Channel)
    if ($From -cnotmatch '\A[0-9a-f]{32}\z' -or $Channel -cnotmatch '\A[a-z][a-z0-9-]{0,31}\z') { return "a stream is a 32-hex key id and a lower-case channel word" }
    return ""
}

function Get-HordeRelayJournalEvidence {
    # The evidence of one RECEIVED record (FINISHED AND UNFINISHED, in the header): known, the SHA-256 in
    # lower-case hex of the whole record file; absent when there is no such record; unknown when the
    # journal cannot say, or the record is damaged.
    param([Parameter(Mandatory = $true)][string]$From, [Parameter(Mandatory = $true)][string]$Channel, [Parameter(Mandatory = $true)][long]$Seq, [string]$HordeHome = "")
    $why = Test-HordeRelayJournalStreamName -From $From -Channel $Channel
    if ($why -cne "") { return (New-HordeUnknown -Reason $why) }
    $ctx = Get-HordeRelayJournalContext -HordeHome $HordeHome
    if (-not $ctx.ok) { return (New-HordeUnknown -Reason $ctx.reason) }
    $dir = Get-HordeRelayJournalStreamDir -Root $ctx.root -Direction "in" -From $From -Channel $Channel
    $r = Read-HordeRelayJournalRecord -Dir $dir -Direction "in" -From $From -Channel $Channel -Seq $Seq
    if (-not $r.ok) {
        if ($r.reason -clike "*it is not there") { return (New-HordeAbsent -Note ("the journal holds no received record " + $From + "/" + $Channel + "/" + $Seq)) }
        return (New-HordeUnknown -Reason $r.reason)
    }
    return (New-HordeKnown -Value (ConvertTo-HordeRelayHex -Bytes (Get-HordeRelaySha256 -Bytes (Get-HordeRelayAsciiBytes -Text $r.whole))) -ObservedAt ([datetime]::UtcNow))
}

function Complete-HordeRelayJournalReceived {
    # A channel has finished with a received record - done, or refused for good: its done mark, write-once
    # beside it. Known { key; already } (already: the mark was there); unknown when the record is not
    # there or damaged, or the mark could not be made durable. Taken under no lock: a done mark is one
    # file put by a move that never replaces, so two channels finishing one record make one mark.
    param([Parameter(Mandatory = $true)][string]$From, [Parameter(Mandatory = $true)][string]$Channel, [Parameter(Mandatory = $true)][long]$Seq, [string]$HordeHome = "", $Now = $null)
    $why = Test-HordeRelayJournalStreamName -From $From -Channel $Channel
    if ($why -cne "") { return (New-HordeUnknown -Reason $why) }
    $ctx = Get-HordeRelayJournalContext -HordeHome $HordeHome
    if (-not $ctx.ok) { return (New-HordeUnknown -Reason ($ctx.reason + "; nothing was marked")) }
    $dir = Get-HordeRelayJournalStreamDir -Root $ctx.root -Direction "in" -From $From -Channel $Channel
    $r = Read-HordeRelayJournalRecord -Dir $dir -Direction "in" -From $From -Channel $Channel -Seq $Seq
    if (-not $r.ok) { return (New-HordeUnknown -Reason ($r.reason + "; a done mark is only ever written beside its record")) }
    $text = '{"v":1,"seq":' + $Seq + ',"doneAt":' + (ConvertTo-HordeRelayJournalMs -Time $Now) + '}'
    try { $moved = Write-HordeRelayJournalFile -Dir $dir -Name (Get-HordeRelayJournalDoneName -Seq $Seq) -Text $text }
    catch { return (New-HordeUnknown -Reason ("the done mark of " + $r.meta.key + " could not be written") -ErrorRecord $_) }
    if ($moved -ceq "moved" -or $moved -ceq "exists") { return (New-HordeKnown -Value ([pscustomobject]@{ key = $r.meta.key; already = ($moved -ceq "exists") }) -ObservedAt ([datetime]::UtcNow)) }
    return (New-HordeUnknown -Reason ("the done mark of " + $r.meta.key + " has its name, but the flush after the move failed, so nothing says it is on disk"))
}

function Get-HordeRelayJournalUnfinished {
    # Every RECEIVED record on -Channel that has no done mark (FINISHED AND UNFINISHED, in the header), in
    # order of sender and then seq: known list of { from; channel; kind; seq; key; text; evidence;
    # verdict }, where text is the envelope's wire text exactly as recorded, evidence its record's hash
    # and verdict what Unprotect-HordeRelayEnvelope takes as -Replay. Unknown when the journal cannot say
    # or any stream of the channel is damaged: a damaged stream is never skipped, because what it hides
    # may be exactly the unfinished record.
    param([Parameter(Mandatory = $true)][string]$Channel, [string]$HordeHome = "")
    if ($Channel -cnotmatch '\A[a-z][a-z0-9-]{0,31}\z') { return (New-HordeUnknown -Reason "a channel is a lower-case word") }
    $ctx = Get-HordeRelayJournalContext -HordeHome $HordeHome
    if (-not $ctx.ok) { return (New-HordeUnknown -Reason $ctx.reason) }
    $inDir = [System.IO.Path]::Combine($ctx.root, "in")
    $senders = @()
    try {
        $senders = @([System.IO.Directory]::EnumerateFileSystemEntries($inDir) | ForEach-Object { [pscustomobject]@{ name = [System.IO.Path]::GetFileName($_); attrs = [System.IO.File]::GetAttributes($_) } })
    } catch {
        $cause = $_.Exception
        while ($null -ne $cause.InnerException) { $cause = $cause.InnerException }
        if ($cause -is [System.IO.DirectoryNotFoundException]) { return (New-HordeKnown -Value @() -ObservedAt ([datetime]::UtcNow)) }
        return (New-HordeUnknown -Reason ("the received streams could not be listed: " + $cause.Message))
    }
    $out = New-Object System.Collections.ArrayList
    foreach ($e in @($senders | Sort-Object name)) {
        $nm = "" + $e.name
        if (($e.attrs -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or ($e.attrs -band [System.IO.FileAttributes]::Directory) -eq 0 -or $nm -cnotmatch $script:HordeRelayJournalSenderDirPattern) {
            return (New-HordeUnknown -Reason ("the journal's received streams hold " + $nm + ", which the journal never makes there; it is damaged, and nothing is resumed until a person repairs it"))
        }
        $from = $Matches[1]
        $dir = Get-HordeRelayJournalStreamDir -Root $ctx.root -Direction "in" -From $from -Channel $Channel
        $st = Get-HordeRelayJournalStream -Dir $dir -Direction "in" -From $from -Channel $Channel
        if (-not $st.ok) { return (New-HordeUnknown -Reason ($st.reason + ". The journal is damaged; nothing is resumed until a person repairs it")) }
        # Sorted as numbers, by [Array]::Sort: the relay profile of tools/ExecScan.ps1 gives Sort-Object
        # no script block, and sixteen digits sort as text the same way anyway.
        $nums = [long[]]@($st.seqs.Keys | ForEach-Object { [long]$_ })
        [System.Array]::Sort($nums)
        foreach ($n in $nums) {
            $seqText = "" + $n
            if ($st.dones.ContainsKey($seqText)) { continue }
            $r = Read-HordeRelayJournalRecord -Dir $dir -Direction "in" -From $from -Channel $Channel -Seq ([long]$seqText)
            if (-not $r.ok) { return (New-HordeUnknown -Reason ($r.reason + ". The journal is damaged; nothing is resumed until a person repairs it")) }
            $verdict = New-HordeKnown -Value ([pscustomobject]@{ key = $r.meta.key; fresh = $true; why = ""; gapBefore = [long]0; direction = "in"; resumed = $true }) -ObservedAt ([datetime]::UtcNow)
            [void]$out.Add([pscustomobject]@{ from = $from; channel = $Channel; kind = $r.meta.kind; seq = [long]$seqText; key = $r.meta.key; text = $r.envelope
                evidence = (ConvertTo-HordeRelayHex -Bytes (Get-HordeRelaySha256 -Bytes (Get-HordeRelayAsciiBytes -Text $r.whole))); verdict = $verdict })
        }
    }
    return (New-HordeKnown -Value @($out.ToArray()) -ObservedAt ([datetime]::UtcNow))
}

function Test-HordeRelayJournalSent {
    # Did this journal record, as SENT, the envelope with replay key -Key (from/channel/seq/nonce)? Known
    # { sent; kind } - sent $true only for a whole record of that very envelope, with its kind; $false for
    # a key that is not one, or that names a record this journal does not hold. Unknown when the journal
    # cannot say or the record is damaged. A channel that takes an answer only to something it sent asks
    # this (channels/decisions: an answer names the snapshot it was made from).
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Key, [string]$HordeHome = "")
    $m = [regex]::Match($Key, '\A([0-9a-f]{32})/([a-z][a-z0-9-]{0,31})/(0|[1-9][0-9]{0,15})/([0-9a-f]{24})\z')
    if (-not $m.Success) { return (New-HordeKnown -Value ([pscustomobject]@{ sent = $false; kind = "" }) -ObservedAt ([datetime]::UtcNow)) }
    $ctx = Get-HordeRelayJournalContext -HordeHome $HordeHome
    if (-not $ctx.ok) { return (New-HordeUnknown -Reason $ctx.reason) }
    $from = $m.Groups[1].Value
    $channel = $m.Groups[2].Value
    $dir = Get-HordeRelayJournalStreamDir -Root $ctx.root -Direction "out" -From $from -Channel $channel
    $r = Read-HordeRelayJournalRecord -Dir $dir -Direction "out" -From $from -Channel $channel -Seq ([long]$m.Groups[3].Value)
    if (-not $r.ok) {
        if ($r.reason -clike "*it is not there") { return (New-HordeKnown -Value ([pscustomobject]@{ sent = $false; kind = "" }) -ObservedAt ([datetime]::UtcNow)) }
        return (New-HordeUnknown -Reason $r.reason)
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ sent = ($r.meta.key -ceq $Key); kind = $r.meta.kind }) -ObservedAt ([datetime]::UtcNow))
}
