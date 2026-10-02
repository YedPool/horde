# remote/Journal.ps1 - the request journal: an act request's id is recorded before anything acts on it,
# so a request delivered twice acts once.
#
# WHY. A link can drop after a request was sent and before its answer came back. The hub cannot tell
# "never arrived" from "arrived and done", so it resends - and without a journal a resent spawn is a
# second goblin, a resent close a second kill. Remote plan step R3 (planning/execution-plan-remote.md)
# and the remote design, section 6.5.
#
# THE RULES, and what makes each one hold:
#   - ONE RECORD PER ID, CREATED WITH FileMode.CreateNew. The operating system lets exactly one
#     CreateNew of a path succeed; every other caller gets "file exists". So two deliveries of one
#     request, in any processes, at any moment, cannot both be told to act: "act twice" is impossible,
#     not unlikely. test/test-journal-race.ps1 races separate processes for the same ids, and runs a
#     control journal that overwrites instead, to show the race can see a double execution.
#   - THE RECORD IS ON DISK BEFORE THE CALLER ACTS. It is written through (FileOptions.WriteThrough,
#     then Flush($true)) and closed before Open-HordeJournalEntry returns "act".
#   - A RESEND REPLAYS. The same id with the same argsHash returns the recorded state and result, and
#     acts nothing.
#   - A REUSED ID IS REFUSED. The same id with another argsHash - other arguments, another verb, or
#     another issue time - is refused, and the record is not touched.
#   - WHAT CANNOT BE KNOWN IS UNKNOWN, AND NEVER RE-EXECUTED. See HALF-DONE below.
#
# THE FILES, in -Root:
#   journal.json            the marker: kind and windows, written once by Initialize-HordeJournal.
#   <id>.json               the record: id, verb, argsHash, issuedAt, receivedAt. Its existence is the
#                           state "accepted". Never rewritten.
#   <id>.outcome.json       the outcome: state done | failed | refused, the result as a tristate answer
#                           record, doneAt. Also created with CreateNew, so an id has one outcome.
#   hw-<ticks>              the high-water mark: the latest time a prune ran at (see CLOCKS below).
#   The design (section 6.5) drew one file whose state field is rewritten; two write-once files give
#   the same states without ever rewriting a file another process may be reading.
#
# HALF-DONE ENTRIES - what a crash leaves, and what each means:
#   - A record with no outcome: the process recorded the id and then either is acting right now, or
#     stopped between "recorded" and "outcome recorded". Whether the act happened cannot be told from
#     here. The answer is UNKNOWN ("accepted at T; outcome not recorded; the act is not repeated"), the
#     entry is never pruned, and nothing re-executes it. Resolving it needs a look at the world (did
#     the session start?), which is the caller's (step R19), never this file's guess.
#   - A torn record (empty or cut JSON): its writer stopped while writing it. By the write-then-act
#     order above it never acted - but that rests on the disk honouring a flush, so it is still
#     UNKNOWN, never re-executed, never overwritten, never pruned.
#   - A record another process is writing at this moment (it holds it open with FileShare.None): the
#     read fails with a sharing violation and the answer is UNKNOWN ("being recorded").
#   - A torn outcome: the act happened and its result was not kept. UNKNOWN.
#
# RETENTION, AND WHY PRUNING CANNOT UNDO IDEMPOTENCY. Pruning forgets ids, and a forgotten id that
# arrives again would act again. So a NEW id is admitted only when its issue time is within the
# admission window (default 7 days old, at most 60 minutes in the future), and an outcome is pruned
# only when it is older than retention (default 30 days, the design's figure) AND its request is out of
# the window. Initialize-HordeJournal refuses a journal whose window plus future allowance reaches
# its retention. Together: any request that could still be admitted finds its entry if it was ever
# recorded. The issue time is part of argsHash, so a resend cannot refresh it. Entries with no
# outcome, torn entries and busy entries are never pruned; the report names them.
#
# CLOCKS. The argument above holds only if the clock that pruned and the clock that admits agree. A
# node clock that ran 40 days ahead, pruned, and was then corrected let a resend of a pruned request
# act a second time (review of PR #39, 2026-09-30). So every prune first records a high-water mark
# (hw-<ticks> files: the latest time a prune ran at, never lowered), judges ages from the later of
# its clock and that mark, and admission judges "too old" from the later of its clock and the mark.
# Whatever the clock does, admission is measured from a time at least as late as any prune used.
# THE COST, ACCEPTED: after a forward jump that a prune saw, new requests are refused - visibly, with
# the mark in the reason - until real time comes within the admission window of the mark. A refused
# request is visible and can be resent; a request run twice cannot be undone. Removing the hw-* files
# by hand is a deliberate act that reopens the window, and only safe once nothing older can be resent.
#
# NOT A JOURNAL IS NOT EMPTY. A root with no marker - a mistyped path, an unmounted drive - would read
# as "no id ever seen" and let every resend act. Open, Get and Remove refuse to treat it as a journal
# and answer unknown; only Initialize-HordeJournal creates the marker.
#
# THE ROOT IS A PARAMETER. Its default home (<HordeHome>/node/journal, <HordeHome>/hub/journal/<device>)
# waits for Get-HordeHome (engines E6); nothing here guesses a location. The message journal of step
# R21 is the same code with -Kind message, keyed by messageId.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Tristate.ps1")

# \A and \z, not ^ and $: in .NET, $ also matches before a final LF, so '^...$' accepted
# "session.spawn" followed by an LF, and it was acted on (review of PR #39, 2026-09-30).
$script:HordeJournalIdPattern = '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z'
$script:HordeJournalVerbPattern = '\A[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)*\z'
$script:HordeJournalOutcomes = @("done", "failed", "refused")
$script:HordeJournalKinds = @("request", "message")
$script:HordeJournalMarker = "journal.json"
$script:HordeJournalMaxDepth = 64
# Win32 error codes, read from the low 16 bits of an IOException's HResult. 80 is ERROR_FILE_EXISTS
# (what CreateNew raises), 183 ERROR_ALREADY_EXISTS; 32 is ERROR_SHARING_VIOLATION and 33
# ERROR_LOCK_VIOLATION (the file is open elsewhere without sharing).
$script:HordeJournalExistsCodes = @(80, 183)
$script:HordeJournalBusyCodes = @(32, 33)
$script:HordeJournalUtf8 = New-Object System.Text.UTF8Encoding($false)

function Get-HordeJournalWin32Code {
    param($ErrorRecord)
    $ex = $ErrorRecord.Exception
    while ($null -ne $ex -and $ex -isnot [System.IO.IOException] -and $null -ne $ex.InnerException) { $ex = $ex.InnerException }
    if ($ex -isnot [System.IO.IOException]) { return -1 }
    return ($ex.HResult -band 0xFFFF)
}

function ConvertTo-HordeJournalCanonical {
    # One text for one value, whatever the key order or the .NET type that holds it, so that argsHash
    # compares meaning and not spelling. JSON, with:
    #   - keys sorted by ordinal comparison;
    #   - every character outside printable ASCII, and " and \, escaped (\uXXXX lowercase), so the text
    #     is ASCII and one character has one spelling;
    #   - a number with no fraction written as an integer, so 1 and 1.0 agree (a resend re-encoded by
    #     5.1's ConvertTo-Json turns 1.0 into 1), and any other number in round-trip form;
    #   - anything that is not JSON data (a date, NaN, a script block) refused, never stringified: the
    #     text of a date depends on the culture of the process that wrote it.
    # This is a hashing form, not the wire codec (step R2): nothing decodes it.
    param($Value, [int]$Depth = 0)
    if ($Depth -gt $script:HordeJournalMaxDepth) { throw ("a value nested deeper than " + $script:HordeJournalMaxDepth + " levels cannot be hashed") }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($null -eq $Value) { return "null" }
    if ($Value -is [bool]) { if ($Value) { return "true" } else { return "false" } }
    if ($Value -is [string]) {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append('"')
        foreach ($ch in $Value.ToCharArray()) {
            $c = [int]$ch
            if ($ch -eq '"') { [void]$sb.Append('\"') }
            elseif ($ch -eq '\') { [void]$sb.Append('\\') }
            elseif ($c -lt 0x20 -or $c -gt 0x7E) { [void]$sb.Append('\u').Append($c.ToString("x4", $inv)) }
            else { [void]$sb.Append($ch) }
        }
        [void]$sb.Append('"')
        return $sb.ToString()
    }
    if ($Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or $Value -is [uint16] -or $Value -is [int32] -or
        $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64]) { return $Value.ToString($inv) }
    if ($Value -is [decimal]) {
        if ($Value -eq [decimal]::Truncate($Value)) { return [decimal]::Truncate($Value).ToString("0", $inv) }
        # A decimal keeps its scale: 1.10 prints as "1.10" and 1.1 as "1.1", one number with two texts
        # (review of PR #39). Trailing zeros after the point are dropped, so both read 1.1, as the
        # double 1.1 does in round-trip form.
        return $Value.ToString($inv).TrimEnd('0')
    }
    if ($Value -is [double] -or $Value -is [single]) {
        $d = [double]$Value
        if ([double]::IsNaN($d) -or [double]::IsInfinity($d)) { throw ("the number " + $d + " cannot be hashed: JSON has no NaN or infinity") }
        # Below 2^53 every integer is exact in a double, so the integer text is the same number.
        if ([Math]::Floor($d) -eq $d -and [Math]::Abs($d) -lt 9007199254740992) { return ([long]$d).ToString($inv) }
        return $d.ToString("R", $inv)
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $keys = New-Object System.Collections.ArrayList
        foreach ($k in $Value.Keys) {
            if ($k -isnot [string]) { throw ("a key of type " + $k.PSObject.TypeNames[0] + " cannot be hashed: JSON keys are strings") }
            [void]$keys.Add($k)
        }
        $sorted = [string[]]$keys.ToArray()
        [Array]::Sort($sorted, [System.StringComparer]::Ordinal)
        $parts = foreach ($k in $sorted) { (ConvertTo-HordeJournalCanonical -Value $k -Depth ($Depth + 1)) + ":" + (ConvertTo-HordeJournalCanonical -Value $Value[$k] -Depth ($Depth + 1)) }
        return ("{" + (@($parts) -join ",") + "}")
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $map = @{}
        foreach ($p in $Value.PSObject.Properties) {
            if ($p.MemberType -ne "NoteProperty") { continue }
            # A hashtable would merge "a" and "A"; JSON keeps them apart, and so must the hash.
            if ($map.ContainsKey($p.Name)) { throw ("the keys '" + $p.Name + "' differ only in case and cannot be hashed apart") }
            $map[$p.Name] = $p.Value
        }
        $sorted = [string[]]@($map.Keys)
        [Array]::Sort($sorted, [System.StringComparer]::Ordinal)
        $parts = foreach ($k in $sorted) { (ConvertTo-HordeJournalCanonical -Value $k -Depth ($Depth + 1)) + ":" + (ConvertTo-HordeJournalCanonical -Value $map[$k] -Depth ($Depth + 1)) }
        return ("{" + (@($parts) -join ",") + "}")
    }
    if ($Value -is [System.Collections.IList]) {
        $parts = foreach ($item in $Value) { ConvertTo-HordeJournalCanonical -Value $item -Depth ($Depth + 1) }
        return ("[" + (@($parts) -join ",") + "]")
    }
    throw ("a value of type " + $Value.PSObject.TypeNames[0] + " cannot be hashed: only JSON data can")
}

function ConvertTo-HordeJournalTime {
    # A time as stored: UTC, round-trip text. A time with no zone is refused, not guessed (the same
    # rule core/Tristate.ps1 applies to observation times: text written in UTC and read as local was
    # four hours off at UTC-4).
    param([datetime]$Time, [string]$What)
    if ($Time.Kind -eq [System.DateTimeKind]::Unspecified) { throw ($What + " has no zone (Kind Unspecified), so it cannot be placed") }
    return $Time.ToUniversalTime().ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertFrom-HordeJournalTime {
    param($Text)
    $parsed = [datetime]::MinValue
    # 5.1's ConvertFrom-Json leaves ISO text as text; a [datetime] is taken only if it carries a zone.
    if ($Text -is [datetime]) { if ($Text.Kind -eq [System.DateTimeKind]::Unspecified) { return $null } else { return $Text.ToUniversalTime() } }
    if ($Text -isnot [string]) { return $null }
    if (-not [datetime]::TryParse($Text, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) { return $null }
    if ($parsed.Kind -eq [System.DateTimeKind]::Unspecified) { return $null }
    return $parsed.ToUniversalTime()
}

function Get-HordeJournalHighWater {
    # The high-water mark: the latest time a prune of this journal ran at, as UTC, or $null if none
    # has. It is the largest of the hw-<ticks> files' names, so it never goes down: two prunes racing
    # each add their own file, and neither can lower the other's.
    param([string]$Root)
    $best = [long]0
    foreach ($f in @(Get-ChildItem -LiteralPath $Root -File -Filter "hw-*" -ErrorAction SilentlyContinue)) {
        if ($f.Name -cmatch '\Ahw-([0-9]{19})\z') { $t = [long]$Matches[1]; if ($t -gt $best) { $best = $t } }
    }
    if ($best -eq 0) { return $null }
    return (New-Object datetime($best, [System.DateTimeKind]::Utc))
}

function Set-HordeJournalHighWater {
    # Record -Time as a high-water mark (an empty file named for its ticks), then remove the marks below
    # the highest one. Throws if the mark cannot be written.
    param([string]$Root, [datetime]$Time)
    $name = "hw-" + $Time.ToUniversalTime().Ticks.ToString("D19", [System.Globalization.CultureInfo]::InvariantCulture)
    $null = New-HordeJournalFile -Root $Root -Name $name -Text ""
    $top = Get-HordeJournalHighWater -Root $Root
    foreach ($f in @(Get-ChildItem -LiteralPath $Root -File -Filter "hw-*" -ErrorAction SilentlyContinue)) {
        if ($f.Name -cmatch '\Ahw-([0-9]{19})\z' -and [long]$Matches[1] -lt $top.Ticks) {
            # Resolved outside the try: a refused path throws, and is never swallowed as a busy file.
            $old = Resolve-HordeJournalPath -Root $Root -Name $f.Name
            try { [System.IO.File]::Delete($old) } catch { }
        }
    }
}

function Get-HordeJournalArgsHash {
    # SHA-256, lowercase hex, of the canonical form of { args, issuedAt, verb }. The verb and the issue
    # time are in it so that reusing an id for another verb, or resending with a fresh issue time (which
    # would slip past the admission window), is a reuse and is refused.
    param([Parameter(Mandatory = $true)][string]$Verb, $Arguments, [Parameter(Mandatory = $true)][datetime]$IssuedAt)
    $text = '{"args":' + (ConvertTo-HordeJournalCanonical -Value $Arguments) + ',"issuedAt":' +
        (ConvertTo-HordeJournalCanonical -Value (ConvertTo-HordeJournalTime -Time $IssuedAt -What "the issue time")) +
        ',"verb":' + (ConvertTo-HordeJournalCanonical -Value $Verb) + '}'
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $bytes = $sha.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($text)) } finally { $sha.Dispose() }
    return (($bytes | ForEach-Object { $_.ToString("x2") }) -join "")
}

function Test-HordeJournalReparse {
    # Is Path a junction or a symbolic link? False when it does not exist.
    param([string]$Path)
    $attrs = $null
    try { $attrs = [System.IO.File]::GetAttributes($Path) } catch { return $false }
    return (($attrs -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Resolve-HordeJournalPath {
    # The full path of the journal file Name, directly in Root, or a throw saying why not.
    #
    # EVERY PATH THE JOURNAL WRITES OR DELETES COMES THROUGH HERE (review of the fix for main,
    # 2026-10-02). The journal opens FileStreams and deletes files, and nothing else in remote/ may;
    # a write that left the root could put a file anywhere the node's user can, a startup folder
    # included. So Name must be a plain file name: no "..", no separator, no colon (a drive, or an
    # alternate stream), not rooted. Its normalised full path must sit directly in the normalised
    # root. And neither the root, nor any folder above it, nor the file itself may be a junction or a
    # symbolic link, because a path that normalises inside the root can still land outside it through
    # one. Refused, never repaired.
    param([string]$Root, [string]$Name)
    if ("$Root".Trim() -eq "") { throw "no journal root was given, so no journal path can be made" }
    if ("$Name" -eq "" -or $Name.Contains("..") -or $Name.IndexOfAny([char[]]@([char]92, [char]47, [char]58)) -ge 0 -or [System.IO.Path]::IsPathRooted($Name)) {
        throw ("refused: '" + $Name + "' is not a plain file name in the journal root (.., separators, drives and absolute paths are refused)")
    }
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([char]92)
    $full = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($rootFull, $Name))
    $parent = [System.IO.Path]::GetDirectoryName($full).TrimEnd([char]92)
    if (-not [string]::Equals($parent, $rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("refused: '" + $Name + "' resolves to '" + $full + "', outside the journal root '" + $rootFull + "'")
    }
    $walk = $rootFull
    while ("$walk" -ne "") {
        if (Test-HordeJournalReparse $walk) { throw ("refused: '" + $walk + "' is a junction or a symbolic link; the journal never writes or deletes through one") }
        $walk = [System.IO.Path]::GetDirectoryName($walk)
    }
    if (Test-HordeJournalReparse $full) { throw ("refused: '" + $full + "' is a junction or a symbolic link; the journal never writes or deletes through one") }
    return $full
}

function New-HordeJournalFile {
    # Create the journal file Name in Root, which must not exist yet, write it through to disk, and
    # close it. Returns "created", "exists", or throws - and throws before anything is opened when
    # Resolve-HordeJournalPath refuses the path. The file is held with FileShare.None while it is
    # written, so a reader never sees it half-written by a LIVE writer: it gets a sharing violation
    # instead, which Read-HordeJournalFile reports as busy.
    param([string]$Root, [string]$Name, [string]$Text)
    $Path = Resolve-HordeJournalPath -Root $Root -Name $Name
    try {
        $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None, 4096, [System.IO.FileOptions]::WriteThrough)
    } catch {
        if ($script:HordeJournalExistsCodes -contains (Get-HordeJournalWin32Code $_)) { return "exists" }
        throw
    }
    try {
        $bytes = $script:HordeJournalUtf8.GetBytes($Text)
        $fs.Write($bytes, 0, $bytes.Length)
        $fs.Flush($true)
    } finally { $fs.Dispose() }
    return "created"
}

function Read-HordeJournalFile {
    # Read one journal file. Returns { kind: absent | busy | torn | error | ok; data; reason }.
    param([string]$Path)
    $text = $null
    try {
        $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        try {
            $reader = New-Object System.IO.StreamReader($fs, $script:HordeJournalUtf8)
            try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
        } finally { $fs.Dispose() }
    } catch {
        $code = Get-HordeJournalWin32Code $_
        if ($code -eq 2 -or $code -eq 3) { return [pscustomobject]@{ kind = "absent"; data = $null; reason = "" } }
        if ($script:HordeJournalBusyCodes -contains $code) { return [pscustomobject]@{ kind = "busy"; data = $null; reason = "it is open in another process" } }
        if ($_.Exception -is [System.IO.FileNotFoundException] -or $_.Exception -is [System.IO.DirectoryNotFoundException] -or
            $_.Exception.InnerException -is [System.IO.FileNotFoundException]) { return [pscustomobject]@{ kind = "absent"; data = $null; reason = "" } }
        return [pscustomobject]@{ kind = "error"; data = $null; reason = ("it could not be read: " + $_.Exception.Message) }
    }
    if ("$text".Trim() -eq "") { return [pscustomobject]@{ kind = "torn"; data = $null; reason = "it is empty" } }
    try { $data = $text | ConvertFrom-Json } catch { return [pscustomobject]@{ kind = "torn"; data = $null; reason = "it is not complete JSON" } }
    if ($null -eq $data -or $data -isnot [System.Management.Automation.PSCustomObject]) { return [pscustomobject]@{ kind = "torn"; data = $null; reason = "it is not a JSON object" } }
    return [pscustomobject]@{ kind = "ok"; data = $data; reason = "" }
}

function Get-HordeJournalProp {
    param($Object, [string]$Name)
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Read-HordeJournalMarker {
    # The journal's settings, or a reason it is not a journal. Returns { ok; settings; reason }.
    param([string]$Root)
    if ("$Root".Trim() -eq "") { return [pscustomobject]@{ ok = $false; settings = $null; reason = "no journal root was given" } }
    $m = Read-HordeJournalFile -Path (Join-Path $Root $script:HordeJournalMarker)
    if ($m.kind -ne "ok") {
        $why = $m.reason
        if ($m.kind -eq "absent") { $why = "there is no " + $script:HordeJournalMarker }
        return [pscustomobject]@{ ok = $false; settings = $null; reason = ("'" + $Root + "' is not a journal (" + $why + "); that is unknown, not an empty journal") }
    }
    $d = $m.data
    $s = [pscustomobject]@{
        kind = Get-HordeJournalProp $d "kind"; retentionDays = Get-HordeJournalProp $d "retentionDays"
        admitDays = Get-HordeJournalProp $d "admitDays"; maxFutureMinutes = Get-HordeJournalProp $d "maxFutureMinutes"
    }
    $okNums = $true
    foreach ($n in @("retentionDays", "admitDays", "maxFutureMinutes")) { $v = Get-HordeJournalProp $s $n; if (-not ($v -is [int] -or $v -is [long]) -or $v -lt 0) { $okNums = $false } }
    if ((Get-HordeJournalProp $d "v") -ne 1 -or $script:HordeJournalKinds -cnotcontains "$($s.kind)" -or -not $okNums) {
        return [pscustomobject]@{ ok = $false; settings = $null; reason = ("the marker in '" + $Root + "' is not one this version writes, so the journal is unknown") }
    }
    return [pscustomobject]@{ ok = $true; settings = $s; reason = "" }
}

function Initialize-HordeJournal {
    # Make -Root a journal: create the folder if needed and write its marker once. Calling it again
    # with the same settings is allowed; with other settings it is refused, because the admission
    # window and retention of entries already recorded were decided under the old ones.
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Kind,
        [int]$RetentionDays = 30,
        [int]$AdmitDays = 7,
        [int]$MaxFutureMinutes = 60
    )
    if ($script:HordeJournalKinds -cnotcontains $Kind) { throw ("a journal kind is request or message, not '" + $Kind + "'") }
    if ($RetentionDays -lt 1 -or $AdmitDays -lt 1 -or $MaxFutureMinutes -lt 0) { throw "the journal's windows must be positive" }
    if ((New-TimeSpan -Days $AdmitDays -Minutes $MaxFutureMinutes) -ge (New-TimeSpan -Days $RetentionDays)) {
        throw ("the admission window (" + $AdmitDays + " days plus " + $MaxFutureMinutes + " minutes ahead) must be shorter than retention (" + $RetentionDays +
            " days), or a pruned id could be admitted again and act twice")
    }
    # The marker's path is checked before the folder is made, so a root that is or sits under a junction
    # is refused before anything is created through it.
    $null = Resolve-HordeJournalPath -Root $Root -Name $script:HordeJournalMarker
    [void][System.IO.Directory]::CreateDirectory($Root)
    $text = ([ordered]@{ v = 1; kind = $Kind; retentionDays = $RetentionDays; admitDays = $AdmitDays; maxFutureMinutes = $MaxFutureMinutes;
        createdAt = (ConvertTo-HordeJournalTime -Time ([datetime]::UtcNow) -What "now") } | ConvertTo-Json -Compress)
    $made = New-HordeJournalFile -Root $Root -Name $script:HordeJournalMarker -Text $text
    if ($made -eq "exists") {
        $m = Read-HordeJournalMarker -Root $Root
        if (-not $m.ok) { throw $m.reason }
        $s = $m.settings
        if ($s.kind -cne $Kind -or $s.retentionDays -ne $RetentionDays -or $s.admitDays -ne $AdmitDays -or $s.maxFutureMinutes -ne $MaxFutureMinutes) {
            throw ("'" + $Root + "' is already a journal with other settings (kind " + $s.kind + ", retention " + $s.retentionDays + " days, window " +
                $s.admitDays + " days, " + $s.maxFutureMinutes + " minutes ahead); its windows are fixed when it is created")
        }
    }
    return $Root
}

function New-HordeJournalDecision {
    param([string]$Decision, [string]$Reason, $Result = $null, [string]$State = "", $Entry = $null)
    return [pscustomobject]@{ decision = $Decision; reason = $Reason; result = $Result; state = $State; entry = $Entry }
}

function Get-HordeJournalEntryData {
    # The record and outcome of one id, read. Returns { kind: absent | unknown | ok; reason; entry }.
    # entry is { id; verb; argsHash; issuedAt; receivedAt; state; result; doneAt }, state "accepted"
    # when there is no outcome yet.
    param([string]$Root, [string]$Id)
    $rec = Read-HordeJournalFile -Path (Join-Path $Root ($Id + ".json"))
    switch ($rec.kind) {
        "absent" { return [pscustomobject]@{ kind = "absent"; reason = ""; entry = $null } }
        "busy"   { return [pscustomobject]@{ kind = "unknown"; reason = ("request " + $Id + " is being recorded by another attempt at this moment; it is not acted on twice"); entry = $null } }
        "torn"   { return [pscustomobject]@{ kind = "unknown"; reason = ("the record of request " + $Id + " is torn (" + $rec.reason + "): its writer stopped while recording it. It is not re-executed and not overwritten"); entry = $null } }
        "error"  { return [pscustomobject]@{ kind = "unknown"; reason = ("the record of request " + $Id + " " + $rec.reason); entry = $null } }
    }
    $d = $rec.data
    $issued = ConvertFrom-HordeJournalTime (Get-HordeJournalProp $d "issuedAt")
    $received = ConvertFrom-HordeJournalTime (Get-HordeJournalProp $d "receivedAt")
    $hash = Get-HordeJournalProp $d "argsHash"
    if ((Get-HordeJournalProp $d "v") -ne 1 -or "$(Get-HordeJournalProp $d 'id')" -cne $Id -or $hash -isnot [string] -or $null -eq $issued -or $null -eq $received) {
        return [pscustomobject]@{ kind = "unknown"; reason = ("the record of request " + $Id + " is torn (a field is missing or wrong). It is not re-executed and not overwritten"); entry = $null }
    }
    $entry = [pscustomobject]@{ id = $Id; verb = "$(Get-HordeJournalProp $d 'verb')"; argsHash = $hash; issuedAt = $issued; receivedAt = $received
        state = "accepted"; result = $null; doneAt = $null }
    $out = Read-HordeJournalFile -Path (Join-Path $Root ($Id + ".outcome.json"))
    switch ($out.kind) {
        "absent" { return [pscustomobject]@{ kind = "ok"; reason = ""; entry = $entry } }
        "busy"   { return [pscustomobject]@{ kind = "unknown"; reason = ("the outcome of request " + $Id + " is being recorded at this moment"); entry = $entry } }
        "torn"   { return [pscustomobject]@{ kind = "unknown"; reason = ("the outcome of request " + $Id + " is torn (" + $out.reason + "): the act happened and its result was not kept. It is not repeated"); entry = $entry } }
        "error"  { return [pscustomobject]@{ kind = "unknown"; reason = ("the outcome of request " + $Id + " " + $out.reason); entry = $entry } }
    }
    $o = $out.data
    $st = Get-HordeJournalProp $o "state"
    $done = ConvertFrom-HordeJournalTime (Get-HordeJournalProp $o "doneAt")
    $resRec = Get-HordeJournalProp $o "result"
    if ($script:HordeJournalOutcomes -cnotcontains "$st" -or $null -eq $done -or $null -eq $resRec) {
        return [pscustomobject]@{ kind = "unknown"; reason = ("the outcome of request " + $Id + " is torn (a field is missing or wrong): the act happened and its result was not kept. It is not repeated"); entry = $entry }
    }
    $entry.state = "$st"
    $entry.result = ConvertFrom-HordeAnswerRecord -Record $resRec
    $entry.doneAt = $done
    return [pscustomobject]@{ kind = "ok"; reason = ""; entry = $entry }
}

function Open-HordeJournalEntry {
    # Record an act request, or say what was recorded for it before. Call it BEFORE acting. Returns
    # { decision; reason; result; state; entry }, decision one of:
    #   act      the id was new and is now recorded. Act, then call Complete-HordeJournalEntry.
    #   replay   the id was recorded with the same arguments and has an outcome: return .result
    #            (a tristate answer) and .state. Do not act.
    #   refuse   the request is refused: a malformed id or verb, an id reused with other arguments, or
    #            a new id outside the admission window. .reason says which. Do not act.
    #   unknown  the journal cannot say what happened: a record with no outcome, a torn or busy one, or
    #            a root that is not a journal. .result is a tristate unknown with the reason. Do not act.
    # -IssuedAt is the time the SENDER first issued the request, carried unchanged on every resend.
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [string]$Id,
        [string]$Verb,
        $Arguments,
        [Parameter(Mandatory = $true)][datetime]$IssuedAt,
        [datetime]$Now = [datetime]::UtcNow
    )
    if ($Id -cnotmatch $script:HordeJournalIdPattern) { return (New-HordeJournalDecision -Decision "refuse" -Reason ("'" + $Id + "' is not a request id: an id is one lowercase UUID")) }
    if ($Verb -cnotmatch $script:HordeJournalVerbPattern) { return (New-HordeJournalDecision -Decision "refuse" -Reason ("'" + $Verb + "' is not a verb name")) }
    # Hashed before anything else, so a time with no zone or arguments that are not JSON data are
    # refused here, before a file exists. Refused, not thrown: the arguments came from the far end,
    # and bad input is answered like any other bad request (review of PR #39).
    try { $hash = Get-HordeJournalArgsHash -Verb $Verb -Arguments $Arguments -IssuedAt $IssuedAt }
    catch { return (New-HordeJournalDecision -Decision "refuse" -Reason ("request " + $Id + " cannot be recorded: " + $_.Exception.Message)) }
    $m = Read-HordeJournalMarker -Root $Root
    if (-not $m.ok) { return (New-HordeJournalDecision -Decision "unknown" -Reason $m.reason -Result (New-HordeUnknown -Reason $m.reason)) }
    $cfg = $m.settings
    $nowUtc = $Now.ToUniversalTime()
    $issuedUtc = $IssuedAt.ToUniversalTime()
    # "Too old" is measured from the later of this clock and the high-water mark, the latest time any
    # prune of this journal ran at - so a clock set back never reopens the window. See CLOCKS above.
    $ref = $nowUtc
    $hw = Get-HordeJournalHighWater -Root $Root
    if ($null -ne $hw -and $hw -gt $ref) { $ref = $hw }
    $tooOld = ($ref - $issuedUtc) -gt (New-TimeSpan -Days $cfg.admitDays)
    $tooNew = ($issuedUtc - $nowUtc) -gt (New-TimeSpan -Minutes $cfg.maxFutureMinutes)
    # The record's path, kept for test/mutations/journal-race.psd1's check-then-create mutant,
    # which writes it directly to prove the race suite catches a non-atomic create.
    $recPath = Join-Path $Root ($Id + ".json")
    if (-not $tooOld -and -not $tooNew) {
        $recText = ([ordered]@{ v = 1; id = $Id; verb = $Verb; argsHash = $hash; issuedAt = (ConvertTo-HordeJournalTime -Time $IssuedAt -What "the issue time")
            receivedAt = (ConvertTo-HordeJournalTime -Time $Now -What "now") } | ConvertTo-Json -Compress)
        try { $made = New-HordeJournalFile -Root $Root -Name ($Id + ".json") -Text $recText }
        catch {
            $why = "request " + $Id + " could not be recorded, so it was not acted on: " + $_.Exception.Message
            return (New-HordeJournalDecision -Decision "unknown" -Reason $why -Result (New-HordeUnknown -Reason $why))
        }
        if ($made -eq "created") { return (New-HordeJournalDecision -Decision "act" -Reason "" -State "accepted") }
    }
    $got = Get-HordeJournalEntryData -Root $Root -Id $Id
    if ($got.kind -eq "absent") {
        if ($tooOld) {
            $from = "this node's clock"
            if ($ref -gt $nowUtc) { $from = "the latest time this journal has seen, " + $ref.ToString("o") + ", which is later than this node's clock now (" + $nowUtc.ToString("o") + ")" }
            return (New-HordeJournalDecision -Decision "refuse" -Reason ("request " + $Id + " was issued at " + $issuedUtc.ToString("o") + ", older than this journal's " + $cfg.admitDays + "-day admission window measured from " + $from + "; an id that old may already be pruned, so a first sight of it cannot be told from a resend"))
        }
        if ($tooNew) { return (New-HordeJournalDecision -Decision "refuse" -Reason ("request " + $Id + " was issued at " + $issuedUtc.ToString("o") + ", more than " + $cfg.maxFutureMinutes + " minutes in the future of this node's clock")) }
        $why = "request " + $Id + " was reported as recorded and then could not be found"
        return (New-HordeJournalDecision -Decision "unknown" -Reason $why -Result (New-HordeUnknown -Reason $why))
    }
    if ($null -ne $got.entry -and $got.entry.argsHash -cne $hash) {
        return (New-HordeJournalDecision -Decision "refuse" -Reason ("request id " + $Id + " was reused: it was recorded for " + $got.entry.verb + " with other arguments or another issue time") -Entry $got.entry)
    }
    if ($got.kind -eq "unknown") { return (New-HordeJournalDecision -Decision "unknown" -Reason $got.reason -Result (New-HordeUnknown -Reason $got.reason) -Entry $got.entry) }
    $e = $got.entry
    if ($e.state -ceq "accepted") {
        $why = "request " + $Id + " was accepted at " + $e.receivedAt.ToString("o") + " and no outcome is recorded: it is in progress, or its process stopped between recording it and finishing; the act may have happened, so it is not repeated"
        return (New-HordeJournalDecision -Decision "unknown" -Reason $why -Result (New-HordeUnknown -Reason $why) -State "accepted" -Entry $e)
    }
    return (New-HordeJournalDecision -Decision "replay" -Reason "" -Result $e.result -State $e.state -Entry $e)
}

function Complete-HordeJournalEntry {
    # Record the outcome of an act that Open-HordeJournalEntry said to perform. Once: a second outcome
    # for one id is refused and the first stands. -Result must be a tristate answer, so what a resend
    # replays is never a bare value: ConvertTo-HordeAnswerRecord refuses anything else, before any file exists.
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$State,
        $Result,
        [datetime]$Now = [datetime]::UtcNow
    )
    if ($Id -cnotmatch $script:HordeJournalIdPattern) { throw ("'" + $Id + "' is not a request id") }
    if ($script:HordeJournalOutcomes -cnotcontains $State) { throw ("an outcome state is done, failed or refused, not '" + $State + "'") }
    $m = Read-HordeJournalMarker -Root $Root
    if (-not $m.ok) { throw $m.reason }
    $rec = Read-HordeJournalFile -Path (Join-Path $Root ($Id + ".json"))
    if ($rec.kind -ne "ok") { throw ("request " + $Id + " has no record to complete (" + $rec.kind + ")") }
    $text = ([ordered]@{ v = 1; id = $Id; state = $State; result = (ConvertTo-HordeAnswerRecord -Answer $Result)
        doneAt = (ConvertTo-HordeJournalTime -Time $Now -What "now") } | ConvertTo-Json -Compress -Depth 64)
    $made = New-HordeJournalFile -Root $Root -Name ($Id + ".outcome.json") -Text $text
    if ($made -eq "exists") { throw ("request " + $Id + " already has an outcome; the first one stands") }
    return $State
}

function Get-HordeJournalEntry {
    # request.status: what the journal knows about one id, as a tristate answer.
    #   absent   no record: the request never arrived (or was pruned, and is outside the window).
    #   known    the entry, with state accepted (no outcome yet), done, failed or refused.
    #   unknown  torn, busy, unreadable, a malformed id, or a root that is not a journal.
    param([Parameter(Mandatory = $true)][string]$Root, [string]$Id)
    if ($Id -cnotmatch $script:HordeJournalIdPattern) { return (New-HordeUnknown -Reason ("'" + $Id + "' is not a request id")) }
    $m = Read-HordeJournalMarker -Root $Root
    if (-not $m.ok) { return (New-HordeUnknown -Reason $m.reason) }
    $got = Get-HordeJournalEntryData -Root $Root -Id $Id
    if ($got.kind -eq "absent") { return (New-HordeAbsent -Note ("no request " + $Id + " is recorded")) }
    if ($got.kind -eq "unknown") { return (New-HordeUnknown -Reason $got.reason) }
    return (New-HordeKnown -Value $got.entry -ObservedAt ([datetime]::UtcNow))
}

function Remove-HordeJournalExpired {
    # Prune: remove each entry whose outcome is older than retention and whose request is outside the
    # admission window. Returns a tristate answer: known { removed = ids; kept = { id; reason } for
    # every entry that is old but may not be pruned }, or unknown when -Root is not a journal.
    #
    # THE RECORD IS DELETED BEFORE THE OUTCOME. If the record cannot be deleted (open elsewhere) the
    # entry stays whole. If the prune stops between the two deletions, what is left is an outcome with
    # no record, which the next prune removes. The other order would leave a record with no outcome -
    # an entry that reads unknown for ever and is never pruned.
    param([Parameter(Mandatory = $true)][string]$Root, [datetime]$Now = [datetime]::UtcNow)
    $m = Read-HordeJournalMarker -Root $Root
    if (-not $m.ok) { return (New-HordeUnknown -Reason ("nothing was pruned: " + $m.reason)) }
    $cfg = $m.settings
    # Ages are judged at the later of this clock and the high-water mark, and that time is recorded
    # as the new mark BEFORE anything is deleted: admission is then measured from a time at least as
    # late as any prune ever used, whatever the clock does next (CLOCKS above).
    $nowUtc = $Now.ToUniversalTime()
    $hw = Get-HordeJournalHighWater -Root $Root
    if ($null -ne $hw -and $hw -gt $nowUtc) { $nowUtc = $hw }
    try { Set-HordeJournalHighWater -Root $Root -Time $nowUtc }
    catch { return (New-HordeUnknown -Reason ("nothing was pruned: the high-water mark could not be recorded: " + $_.Exception.Message)) }
    $retention = New-TimeSpan -Days $cfg.retentionDays
    $window = New-TimeSpan -Days $cfg.admitDays -Minutes $cfg.maxFutureMinutes
    $removed = New-Object System.Collections.ArrayList
    $kept = New-Object System.Collections.ArrayList
    $files = @(Get-ChildItem -LiteralPath $Root -File -Filter "*.json" | ForEach-Object { $_.Name })
    foreach ($name in $files) {
        if ($name -cnotmatch '\A([0-9a-f-]{36})\.json\z') { continue }
        $id = $Matches[1]
        if ($id -cnotmatch $script:HordeJournalIdPattern) { continue }
        $got = Get-HordeJournalEntryData -Root $Root -Id $id
        if ($got.kind -eq "absent") { continue }
        if ($got.kind -eq "unknown") { [void]$kept.Add([pscustomobject]@{ id = $id; reason = ("never pruned: " + $got.reason) }); continue }
        $e = $got.entry
        # No outcome: never pruned, however old; reported once it is past retention.
        if ($e.state -ceq "accepted") { if (($nowUtc - $e.receivedAt) -gt $retention) { [void]$kept.Add([pscustomobject]@{ id = $id; reason = ("never pruned: no outcome recorded since " + $e.receivedAt.ToString("o") + "; forgetting it would let a resend act again") }) }; continue }
        if (($nowUtc - $e.doneAt) -le $retention -or ($nowUtc - $e.issuedAt) -le $window) { continue }
        try { [System.IO.File]::Delete((Resolve-HordeJournalPath -Root $Root -Name ($id + ".json"))) }
        catch { [void]$kept.Add([pscustomobject]@{ id = $id; reason = ("the record could not be deleted, so the entry was left whole: " + $_.Exception.Message) }); continue }
        try { [System.IO.File]::Delete((Resolve-HordeJournalPath -Root $Root -Name ($id + ".outcome.json"))) }
        catch { [void]$kept.Add([pscustomobject]@{ id = $id; reason = ("the record was deleted and the outcome could not be; the next prune removes it: " + $_.Exception.Message) }); continue }
        [void]$removed.Add($id)
    }
    # Outcomes whose record is gone: what a prune cut short between its two deletions leaves.
    foreach ($name in @(Get-ChildItem -LiteralPath $Root -File -Filter "*.outcome.json" | ForEach-Object { $_.Name })) {
        if ($name -cnotmatch '\A([0-9a-f-]{36})\.outcome\.json\z') { continue }
        $id = $Matches[1]
        if ($id -cnotmatch $script:HordeJournalIdPattern) { continue }
        if ((Read-HordeJournalFile -Path (Join-Path $Root ($id + ".json"))).kind -ne "absent") { continue }
        $out = Read-HordeJournalFile -Path (Join-Path $Root $name)
        $done = $null
        if ($out.kind -eq "ok") { $done = ConvertFrom-HordeJournalTime (Get-HordeJournalProp $out.data "doneAt") }
        if ($null -eq $done -or ($nowUtc - $done) -le $retention) { continue }
        try { [System.IO.File]::Delete((Resolve-HordeJournalPath -Root $Root -Name $name)); [void]$removed.Add($id) }
        catch { [void]$kept.Add([pscustomobject]@{ id = $id; reason = ("an outcome with no record could not be deleted: " + $_.Exception.Message) }) }
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ removed = @($removed); kept = @($kept) }) -ObservedAt ([datetime]::UtcNow))
}
