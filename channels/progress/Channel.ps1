# channels/progress - the fleet's progress log on the founder's phone, end to end encrypted: the entries
# of one append-only file on this machine, out to his phone, in the order they were written (the founder
# asked for it, 2026-10-12).
#
# WHAT IT READS. One file, the progress changelog: JSON Lines, UTF-8 with no byte-order mark, LF line
# ends, append-only, written "to be read continuously from any point". One entry a line:
#   {"v":1,"id":"<unique>","ts":"2026-10-12T18:15:00Z","kind":"merged","area":"Form fill","lane":"F",
#    "task":"T-0096","title":"<=100 chars","text":"<=2000 chars","corrects":"<id>"}
# v, id, ts, title and text are required; the rest may be missing. WHICH FILE is the setting progressFile
# (settings\relay-progress.json), an absolute path. Its default is empty, which means
# <HORDE_HOME>\progress\changelog.jsonl: shipped code names no folder of anyone's machine (CONTRIBUTING
# 11), and a suite's `horde relay run` on a home of its own must never read a real fleet's log.
# THIS CHANNEL ONLY READS THE FILE. It never writes it, moves it or locks it against its writer.
#
# MACHINE TO PHONE ONLY. The channel takes nothing in (it registers no kind), so an envelope sent to it,
# whoever signed it, is refused before the journal sees it (channels/Port.ps1, THE PATH IN, step 3).
#
# OUT (the Tick), sealed to every TRUSTED phone identity key of the horde and put into the horde's phone
# mailbox, exactly as the chat is (the same envelope, the same sealing: channels/Port.ps1):
#   - IN THE FILE'S ORDER, NEVER BY TIME. An entry's ts is when the thing HAPPENED, so a later line may
#     carry an earlier time. Entries are sent in the order of their lines, and each carries its line
#     number (n), which is what the phone orders by; ts is only shown.
#   - FROM THE END, THEN FOLLOWING. The first look ever sends at most the newest backfillEntries entries
#     (a setting, 200), marked backfill; after that every new entry goes to every trusted key. A phone
#     key trusted since is sent the newest backfillEntries entries of what was already read, sealed to
#     it alone.
#   - THE CURSOR IS A BYTE OFFSET, AND A LINE IS READ ONLY ONCE IT IS WHOLE. The file is read from the
#     offset to its last line end; what follows the last line end - a line its writer has not finished -
#     is left where it is and read on a later turn, never guessed at.
#   - A LINE THAT DOES NOT HOLD TOGETHER IS LEFT OUT, AND SAID, WITH ITS NUMBER: not UTF-8, not one JSON
#     object, a member repeated, a required member missing or of the wrong kind, a title or a text past
#     its length, a line of more than 65,536 bytes, something that looks like a secret (the same refusal
#     the decisions list makes, core/Secrets.ps1; never what tripped it). Never mended, never cut to fit.
#     The run's lines name each such line by its number; the phone is told how many were left out
#     (a notice, below), so a gap is never silence. A member this file does not list is ignored: the
#     format may grow without this channel leaving its entries out. A kind off the list is a note.
#   - ONE ID, ONE ENTRY. A line whose id an earlier line already carried is left out, and said: the
#     first stands. The state keeps the last 5,000 ids sent, each as a short hash and its line number,
#     so the same line read again after a crash is the same entry and not a repeat. The phone keeps
#     entries by id too, so one that reaches it twice (a backfill beside a live batch) is shown once.
#   - PAGES. A batch is as many envelopes as it needs, each body within the setting pageBytes and what
#     the relay holds (channels/Port.ps1, Get-HordeRelayChannelBodyBudget). The JSON is written with
#     everything past printable ASCII as \u escapes, so a byte is a character and a page is measured
#     exactly. An entry is never cut: one that no page can hold is left out, and said.
#   - A FILE REPLACED OR CUT SHORT IS NOTICED, SAID, AND NEVER SENT AGAIN OR STARTED OVER BY ITSELF. The
#     state keeps, beside the offset, the SHA-256 of the file's first bytes and of the last bytes before
#     the offset (up to 4,096 each): an append-only file never changes them. A file shorter than the
#     offset, gone, another file by the setting, or one whose marks differ STOPS the channel: the run
#     says so once, the phone is told (notice file-replaced), and nothing more is read. Put back as it
#     was, the channel goes on by itself (notice following). To follow a new file from its start a
#     person deletes the state file, which the run's line names; the phone shows each entry once.
#   - A MISSING FILE IS "NOTHING YET", not a fault: nothing is sent, said once, and the relay not blamed.
#   - THE STATE IS DURABLE AND JOURNAL-BACKED (<HORDE_HOME>\relay\progress\state.json, replaced whole in
#     one rename), as the chat's is: record every envelope in the journal; write the state - the new
#     offset and the replay keys recorded and not yet put; put them, dropping each key once the relay
#     took it. A crash before the state is written reads the same lines again (shown once: by id); a
#     crash after it puts the SAME envelopes, read back from the journal. A state file that cannot be
#     read stops the channel, in words, and is never quietly started over.
#   - NEVER PUT TO A KEY REVOKED SINCE IT WAS RECORDED. Before each put, the envelope's recipients are
#     compared with the phone keys trusted now; one sealed to a key no longer trusted is dropped - every
#     waiting envelope of entries with it - and the state goes back to where it was before the oldest
#     of them (rewind), so those lines are read again and sealed to the keys trusted now.
#   - NOTICES, kind notice: { code, count } - file-replaced, following, lines-skipped (count: how many).
#     Codes only: the phone shows its own fixed sentence for each (relay/js/protocol.js, PROGRESS_WORDS).
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\JsonText.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\ModuleSettings.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\FileAtomic.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\Home.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\Secrets.ps1")

$script:HordeProgressChannelFolder = $PSScriptRoot
$script:HordeProgressChannelSettings = New-HordeModuleSettings -Module "relay-progress" -Settings @(
    @{ name = "progressFile"; kind = "folder"; default = ""; what = "The progress changelog to follow, as an absolute path; empty means progress\changelog.jsonl under Horde's home." },
    # 200 entries is several working days of a fleet that writes a few tens a day: what a phone just
    # paired needs to pick up the thread, in two or three envelopes.
    @{ name = "backfillEntries"; kind = "whole"; default = 200; min = 0; max = 5000; what = "How many of the newest entries a phone key newly trusted, or the first look ever, is sent." },
    # 16,384 is the floor: an entry at its largest (a title of 100 and a text of 2,000 characters, every
    # one a six-byte escape) is about 13,000 bytes, so a page always holds at least one.
    @{ name = "pageBytes"; kind = "whole"; default = 262144; min = 16384; max = 1048576; what = "The largest body of one envelope of entries, in bytes; a longer batch is sent as more envelopes." },
    @{ name = "readBytes"; kind = "whole"; default = 1048576; min = 131072; max = 33554432; what = "The most bytes of the changelog read in one look." },
    @{ name = "sendIntervalMs"; kind = "whole"; default = 2000; min = 0; max = 600000; what = "The shortest time between two sends of entries, in milliseconds: lines written meanwhile go together." }
)
$script:HordeProgressChannelKinds = @("decision", "result", "merged", "blocked", "waiting", "started", "progress", "done", "note")
$script:HordeProgressChannelNoticeCodes = @("file-replaced", "following", "lines-skipped")
# An id: printable ASCII with no space, quote or backslash, so it is written into JSON as it stands.
$script:HordeProgressChannelIdPattern = '\A[\x21\x23-\x5B\x5D-\x7E]{1,128}\z'
$script:HordeProgressChannelTimePattern = '\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,7})?(Z|[+-][0-9]{2}:[0-9]{2})\z'
$script:HordeProgressChannelTitleChars = 100
$script:HordeProgressChannelTextChars = 2000
$script:HordeProgressChannelLabelChars = @{ area = 60; lane = 32; task = 64 }
# The longest line read: an entry at its largest is about 13,000 bytes, so five times that is no entry.
$script:HordeProgressChannelLineBytes = 65536
$script:HordeProgressChannelMarkBytes = 4096
$script:HordeProgressChannelIdsKept = 5000
# The most left-out lines one turn names one by one; the rest are counted.
$script:HordeProgressChannelSaidLines = 50

function Get-HordeProgressChannelSettingsDeclaration { return $script:HordeProgressChannelSettings }

function Get-HordeProgressChannelHome {
    param($Context)
    if ("$($Context.hordeHome)" -ne "") { return $Context.hordeHome }
    return (Get-HordeHome)
}

function Get-HordeProgressChannelSettings {
    param($Context)
    $s = Get-HordeModuleSettings -Declaration $script:HordeProgressChannelSettings -HordeHome (Get-HordeProgressChannelHome $Context)
    if ($s.state -ceq "refused") { return (New-HordeUnknown -Reason (@($s.findings) -join " ")) }
    return (New-HordeKnown -Value $s.values)
}

function Get-HordeProgressChannelFilePath {
    # The changelog this home follows (WHICH FILE, in the header).
    param([Parameter(Mandatory = $true)][string]$HordeHome, [AllowEmptyString()][string]$Setting = "")
    if ($Setting -cne "") { return $Setting }
    return [System.IO.Path]::Combine($HordeHome, "progress", "changelog.jsonl")
}

function Get-HordeProgressChannelStatePath {
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    return [System.IO.Path]::Combine($HordeHome, "relay", "progress", "state.json")
}

function ConvertTo-HordeProgressChannelJsonString {
    # A JSON string of -Text in printable ASCII: quote, backslash, every control character and everything
    # past 0x7E as a \u escape. One byte per character of output, so a page is measured exactly.
    param([AllowEmptyString()][string]$Text)
    $body = [regex]::Replace($Text, '[^\x20\x21\x23-\x5B\x5D-\x7E]', { param($m) '\u' + ([int][char]$m.Value).ToString("x4") })
    return ('"' + $body + '"')
}

function Get-HordeProgressChannelIdMark {
    # An id as the state keeps it: the first 16 hex digits of its SHA-256.
    param([Parameter(Mandatory = $true)][string]$Id)
    return (ConvertTo-HordeRelayHex -Bytes (Get-HordeRelaySha256 -Bytes ([System.Text.Encoding]::UTF8.GetBytes($Id)))).Substring(0, 16)
}

function Read-HordeProgressChannelEntry {
    # One line of the changelog, read strictly (A LINE THAT DOES NOT HOLD TOGETHER, in the header):
    # { ok; blank; reason; value } with value { id; ts; kind; title; text; area; lane; task; corrects } -
    # ts as UTC in one spelling, the optional ones "" when missing. blank: the line holds nothing at all.
    # Never throws for the line: its writer is code, and code has bugs.
    param([AllowEmptyCollection()][byte[]]$Bytes)
    $fail = [pscustomobject]@{ ok = $false; blank = $false; reason = ""; value = $null }
    $strict = New-Object System.Text.UTF8Encoding -ArgumentList $false, $true
    try { $text = $strict.GetString($Bytes) } catch { $fail.reason = "it is not UTF-8"; return $fail }
    if ($text.Trim() -eq "") { $fail.blank = $true; return $fail }
    if (-not $text.TrimStart().StartsWith("{")) { $fail.reason = "it is not a JSON object"; return $fail }
    if (@(Find-HordeJsonDuplicateKey -Text $text).Count -gt 0) { $fail.reason = "it has a member more than once"; return $fail }
    try { $e = ConvertFrom-Json -InputObject $text } catch { $fail.reason = "it is not JSON"; return $fail }
    if ($e -isnot [System.Management.Automation.PSCustomObject]) { $fail.reason = "it is not a JSON object"; return $fail }
    # Names are compared exactly: "ID" is not id.
    $has = New-Object System.Collections.Hashtable -ArgumentList ([System.StringComparer]::Ordinal)
    foreach ($p in @($e.PSObject.Properties)) { $has[$p.Name] = $p.Value }
    foreach ($need in @("v", "id", "ts", "title", "text")) { if (-not $has.ContainsKey($need)) { $fail.reason = ("it has no " + $need); return $fail } }
    if (-not ($has["v"] -is [int] -or $has["v"] -is [long]) -or $has["v"] -ne 1) { $fail.reason = "it is not version 1"; return $fail }
    if ($has["id"] -isnot [string] -or $has["id"] -cnotmatch $script:HordeProgressChannelIdPattern) { $fail.reason = "its id is not 1 to 128 plain characters with no space, quote or backslash"; return $fail }
    # A time with a zone, in one spelling. PowerShell 7 hands an ISO time over already read as a date.
    $when = $null
    if ($has["ts"] -is [datetime]) { if ($has["ts"].Kind -ne [System.DateTimeKind]::Unspecified) { $when = $has["ts"].ToUniversalTime() } }
    elseif ($has["ts"] -is [string] -and $has["ts"] -cmatch $script:HordeProgressChannelTimePattern) {
        $parsed = [datetime]::MinValue
        # The pattern has made sure of a zone, so what is parsed is a moment and not a wall clock's reading.
        if ([datetime]::TryParse($has["ts"], [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) { $when = $parsed.ToUniversalTime() }
    }
    if ($null -eq $when) { $fail.reason = "its ts is not a time with a zone (2026-10-12T18:15:00Z)"; return $fail }
    if ($has["title"] -isnot [string] -or $has["title"].Trim() -eq "") { $fail.reason = "its title is not words"; return $fail }
    if ($has["title"].Length -gt $script:HordeProgressChannelTitleChars) { $fail.reason = ("its title is " + $has["title"].Length + " characters; a title holds " + $script:HordeProgressChannelTitleChars); return $fail }
    if ($has["title"] -cmatch '\p{Cc}') { $fail.reason = "its title holds a control character"; return $fail }
    if ($has["text"] -isnot [string]) { $fail.reason = "its text is not text"; return $fail }
    $words = $has["text"].Replace("`r`n", "`n")
    if ($words.Length -gt $script:HordeProgressChannelTextChars) { $fail.reason = ("its text is " + $words.Length + " characters; a text holds " + $script:HordeProgressChannelTextChars); return $fail }
    if ($words -cmatch '[^\P{Cc}\n\t]') { $fail.reason = "its text holds a control character that is not a line end or a tab"; return $fail }
    $labels = @{}
    foreach ($name in @("area", "lane", "task")) {
        $labels[$name] = ""
        if (-not $has.ContainsKey($name) -or $null -eq $has[$name] -or ($has[$name] -is [string] -and $has[$name] -ceq "")) { continue }
        if ($has[$name] -isnot [string] -or $has[$name].Length -gt $script:HordeProgressChannelLabelChars[$name] -or $has[$name] -cmatch '\p{Cc}' -or $has[$name].Trim() -cne $has[$name]) { $fail.reason = ("its " + $name + " is not 1 to " + $script:HordeProgressChannelLabelChars[$name] + " plain characters"); return $fail }
        $labels[$name] = $has[$name]
    }
    $corrects = ""
    if ($has.ContainsKey("corrects") -and $null -ne $has["corrects"] -and -not ($has["corrects"] -is [string] -and $has["corrects"] -ceq "")) {
        if ($has["corrects"] -isnot [string] -or $has["corrects"] -cnotmatch $script:HordeProgressChannelIdPattern) { $fail.reason = "its corrects is not an entry's id"; return $fail }
        $corrects = $has["corrects"]
    }
    # A kind off the list - a new word, or none - is a note: the entry is never left out for its kind.
    $kind = "note"
    if ($has.ContainsKey("kind") -and $has["kind"] -is [string] -and $script:HordeProgressChannelKinds -ccontains $has["kind"]) { $kind = $has["kind"] }
    # NO SECRET LEAVES THE MACHINE: said by its kind, never by what tripped it.
    foreach ($t in @($has["id"], $has["title"], $words, $labels["area"], $labels["lane"], $labels["task"], $corrects)) {
        $secret = Find-HordeSecretKind -Text $t
        if ($secret -cne "") { $fail.reason = ("it holds what looks like " + $secret + ", so it stays at the machine"); return $fail }
    }
    return [pscustomobject]@{ ok = $true; blank = $false; reason = ""; value = [pscustomobject]@{
        id = $has["id"]; ts = $when.ToString("yyyy-MM-ddTHH:mm:ss.fffZ", [System.Globalization.CultureInfo]::InvariantCulture); kind = $kind; title = $has["title"]; text = $words
        area = $labels["area"]; lane = $labels["lane"]; task = $labels["task"]; corrects = $corrects } }
}

function Read-HordeProgressChannelBytes {
    # -Count bytes of -Path from -Offset (fewer at its end), shared with its writer: { ok; reason; bytes;
    # length } - length the file's whole length when it was opened.
    param([Parameter(Mandatory = $true)][string]$Path, [long]$Offset, [long]$Count)
    try {
        $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
        $fs = New-Object System.IO.FileStream -ArgumentList $Path, ([System.IO.FileMode]::Open), ([System.IO.FileAccess]::Read), $share
        try {
            $length = [long]$fs.Length
            $want = [long][System.Math]::Max(0, [System.Math]::Min([double]$Count, [double]($length - $Offset)))
            $buf = New-Object byte[] $want
            $got = 0
            if ($want -gt 0) {
                [void]$fs.Seek($Offset, [System.IO.SeekOrigin]::Begin)
                while ($got -lt $want) { $n = $fs.Read($buf, $got, [int]($want - $got)); if ($n -le 0) { break }; $got += $n }
            }
            if ($got -ne $want) { return [pscustomobject]@{ ok = $false; reason = "it ended while it was read"; bytes = $null; length = $length } }
            return [pscustomobject]@{ ok = $true; reason = ""; bytes = $buf; length = $length }
        } finally { $fs.Dispose() }
    } catch { return [pscustomobject]@{ ok = $false; reason = $_.Exception.Message; bytes = $null; length = [long]-1 } }
}

function Get-HordeProgressChannelMarks {
    # What an append-only file never changes, for the first -Offset bytes of -Path (A FILE REPLACED OR
    # CUT SHORT, in the header): { ok; reason; length; head; tail } - the SHA-256 of its first bytes and
    # of the last bytes before the offset, up to 4,096 each. A file shorter than the offset answers ok
    # with its length and no marks: the caller sees it was cut.
    param([Parameter(Mandatory = $true)][string]$Path, [long]$Offset)
    $take = [long][System.Math]::Min([double]$Offset, [double]$script:HordeProgressChannelMarkBytes)
    $h = Read-HordeProgressChannelBytes -Path $Path -Offset 0 -Count $take
    if (-not $h.ok) { return [pscustomobject]@{ ok = $false; reason = $h.reason; length = $h.length; head = ""; tail = "" } }
    if ($h.length -lt $Offset) { return [pscustomobject]@{ ok = $true; reason = ""; length = $h.length; head = ""; tail = "" } }
    $t = Read-HordeProgressChannelBytes -Path $Path -Offset ($Offset - $take) -Count $take
    if (-not $t.ok) { return [pscustomobject]@{ ok = $false; reason = $t.reason; length = $t.length; head = ""; tail = "" } }
    if ($t.length -lt $Offset) { return [pscustomobject]@{ ok = $true; reason = ""; length = $t.length; head = ""; tail = "" } }
    return [pscustomobject]@{ ok = $true; reason = ""; length = $t.length
        head = (ConvertTo-HordeRelayHex -Bytes (Get-HordeRelaySha256 -Bytes ([byte[]]$h.bytes)))
        tail = (ConvertTo-HordeRelayHex -Bytes (Get-HordeRelaySha256 -Bytes ([byte[]]$t.bytes))) }
}

function Read-HordeProgressChannelLines {
    # The whole lines of -Path from -Offset, at most -MaxBytes of them and never past -Upto (0: the
    # file's end): { ok; reason; entries; bad; offset; line; skip; more }. entries are { line; entry } in
    # the file's order; bad the lines left out, as "line N <why>"; offset, line and skip where the next
    # read begins - offset just past the last line end read, so a line not yet finished is read later
    # (THE CURSOR IS A BYTE OFFSET, in the header); skip: the read ended inside a line already longer
    # than a line may be, whose rest is passed over; more: there is more of the file to read now.
    param([Parameter(Mandatory = $true)][string]$Path, [long]$Offset, [long]$Line, [bool]$Skip, [long]$MaxBytes, [long]$Upto = 0)
    $count = $MaxBytes
    if ($Upto -gt 0) { $count = [long][System.Math]::Min([double]$MaxBytes, [double]($Upto - $Offset)) }
    $r = Read-HordeProgressChannelBytes -Path $Path -Offset $Offset -Count $count
    if (-not $r.ok) { return [pscustomobject]@{ ok = $false; reason = $r.reason; entries = @(); bad = @(); offset = $Offset; line = $Line; skip = $Skip; more = $false } }
    $buf = [byte[]]$r.bytes
    $n = $buf.Length
    $entries = New-Object System.Collections.ArrayList
    $bad = New-Object System.Collections.ArrayList
    $tooLong = "is longer than " + $script:HordeProgressChannelLineBytes + " bytes, which no entry is"
    $pos = 0
    if ($Skip) {
        $end = [System.Array]::IndexOf($buf, [byte]10, 0, $n)
        if ($end -lt 0) { $pos = $n }
        else { $Line++; [void]$bad.Add("line " + $Line + " " + $tooLong); $pos = $end + 1; $Skip = $false }
    }
    while (-not $Skip -and $pos -lt $n) {
        $end = [System.Array]::IndexOf($buf, [byte]10, $pos, $n - $pos)
        if ($end -lt 0) { break }
        $Line++
        $len = $end - $pos
        if ($len -gt $script:HordeProgressChannelLineBytes) { [void]$bad.Add("line " + $Line + " " + $tooLong) }
        else {
            $one = New-Object byte[] $len
            [System.Array]::Copy($buf, $pos, $one, 0, $len)
            $e = Read-HordeProgressChannelEntry -Bytes $one
            if ($e.ok) { [void]$entries.Add([pscustomobject]@{ line = [long]$Line; entry = $e.value }) }
            elseif (-not $e.blank) { [void]$bad.Add("line " + $Line + ": " + $e.reason) }
        }
        $pos = $end + 1
    }
    # What is left has no line end yet. Longer than a line may be, it is no entry: it is passed over now,
    # and named when its end is found.
    if (-not $Skip -and ($n - $pos) -gt $script:HordeProgressChannelLineBytes) { $Skip = $true; $pos = $n }
    $limit = $(if ($Upto -gt 0) { [long][System.Math]::Min([double]$Upto, [double]$r.length) } else { [long]$r.length })
    return [pscustomobject]@{ ok = $true; reason = ""; entries = @($entries.ToArray()); bad = @($bad.ToArray()); offset = [long]($Offset + $pos); line = [long]$Line; skip = $Skip
        more = (($Offset + $n) -lt $limit) }
}

function Read-HordeProgressChannelTail {
    # The newest -Keep entries of -Path from its start to -Upto (0: its end), each id once - the first
    # line that carries it stands: { ok; reason; entries; bad; offset; line; skip; marks } - marks every
    # id seen, as the state keeps them ("<id mark>:<line>"), newest last.
    param([Parameter(Mandatory = $true)][string]$Path, [int]$Keep, [long]$MaxBytes, [long]$Upto = 0)
    $queue = New-Object System.Collections.Generic.Queue[object]
    $seen = @{}
    $marks = New-Object System.Collections.ArrayList
    $bad = New-Object System.Collections.ArrayList
    $offset = [long]0; $line = [long]0; $skip = $false
    # A file of 10,000 reads is not one: 10 TiB at the smallest read.
    for ($i = 0; $i -lt 10000; $i++) {
        $r = Read-HordeProgressChannelLines -Path $Path -Offset $offset -Line $line -Skip $skip -MaxBytes $MaxBytes -Upto $Upto
        if (-not $r.ok) { return [pscustomobject]@{ ok = $false; reason = $r.reason; entries = @(); bad = @(); offset = $offset; line = $line; skip = $skip; marks = @() } }
        foreach ($b in @($r.bad)) { [void]$bad.Add($b) }
        foreach ($e in @($r.entries)) {
            if ($seen.ContainsKey($e.entry.id)) { [void]$bad.Add("line " + $e.line + " repeats the id of line " + $seen[$e.entry.id] + "; the first stands"); continue }
            $seen[$e.entry.id] = $e.line
            [void]$marks.Add((Get-HordeProgressChannelIdMark -Id $e.entry.id) + ":" + $e.line)
            $queue.Enqueue($e)
            if ($queue.Count -gt $Keep) { [void]$queue.Dequeue() }
        }
        $offset = $r.offset; $line = $r.line; $skip = $r.skip
        if (-not $r.more) { break }
    }
    return [pscustomobject]@{ ok = $true; reason = ""; entries = @($queue.ToArray()); bad = @($bad.ToArray()); offset = $offset; line = $line; skip = $skip
        marks = @($marks.ToArray() | Select-Object -Last $script:HordeProgressChannelIdsKept) }
}

function ConvertTo-HordeProgressChannelEntryText {
    # One entry as the phone gets it, as JSON text: its id, its line number (n: the order), its time and
    # kind, its words, and the optional labels it carries.
    param([Parameter(Mandatory = $true)]$Entry, [Parameter(Mandatory = $true)][long]$Line)
    $t = '{"id":' + (ConvertTo-HordeProgressChannelJsonString $Entry.id) + ',"n":' + $Line + ',"ts":"' + $Entry.ts + '","kind":"' + $Entry.kind + '"'
    foreach ($name in @("area", "lane", "task", "corrects")) { if ($Entry.$name -cne "") { $t += ',"' + $name + '":' + (ConvertTo-HordeProgressChannelJsonString $Entry.$name) } }
    return ($t + ',"title":' + (ConvertTo-HordeProgressChannelJsonString $Entry.title) + ',"text":' + (ConvertTo-HordeProgressChannelJsonString $Entry.text) + '}')
}

function New-HordeProgressChannelPages {
    # The bodies of one batch of entries (PAGES, in the header): { bodies; shown; bad } - as many bodies
    # as it needs, each within -Budget bytes, none when there is no entry; bad the entries no page holds.
    param($Context, [bool]$Backfill, [object[]]$Entries, [long]$Budget)
    $front = '{"v":1,"kind":"progress-entries","horde":"' + $Context.horde + '","machine":"' + $Context.signKeyId + '","backfill":' + $(if ($Backfill) { "true" } else { "false" }) + ',"entries":['
    $back = ']}'
    $room = $Budget - $front.Length - $back.Length
    $pages = New-Object System.Collections.ArrayList
    $bad = New-Object System.Collections.ArrayList
    $current = New-Object System.Collections.ArrayList
    $used = 0; $shown = 0
    foreach ($e in @($Entries)) {
        $text = ConvertTo-HordeProgressChannelEntryText -Entry $e.entry -Line $e.line
        if ($text.Length -gt $room) { [void]$bad.Add("line " + $e.line + " is " + $text.Length + " bytes as it is sent; a page holds " + $room + ", so it stays at the machine"); continue }
        $add = $text.Length + $(if ($current.Count -gt 0) { 1 } else { 0 })
        if ($current.Count -gt 0 -and $used + $add -gt $room) { [void]$pages.Add($front + ($current -join ",") + $back); $current = New-Object System.Collections.ArrayList; $used = 0; $add = $text.Length }
        [void]$current.Add($text)
        $used += $add
        $shown++
    }
    if ($current.Count -gt 0) { [void]$pages.Add($front + ($current -join ",") + $back) }
    return [pscustomobject]@{ bodies = @($pages.ToArray()); shown = $shown; bad = @($bad.ToArray()) }
}

function New-HordeProgressChannelNotice {
    # A notice body (NOTICES, in the header).
    param($Context, [Parameter(Mandatory = $true)][string]$Code, [long]$Count = 0)
    if ($script:HordeProgressChannelNoticeCodes -cnotcontains $Code) { throw ("'" + $Code + "' is not a progress notice") }
    return ('{"v":1,"kind":"progress-notice","horde":"' + $Context.horde + '","machine":"' + $Context.signKeyId + '","code":"' + $Code + '","count":' + $Count + '}')
}

function Read-HordeProgressChannelState {
    # The durable state: known, the empty state when there is no file yet, unknown when the file cannot
    # be read or does not hold together - never a guess.
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    $path = Get-HordeProgressChannelStatePath -HordeHome $HordeHome
    $empty = [pscustomobject]@{ started = $false; path = ""; offset = [long]0; line = [long]0; skip = $false; head = ""; tail = ""; phones = @(); pending = @(); sent = @(); rewind = $null; stopped = "" }
    if (-not [System.IO.File]::Exists($path)) { return (New-HordeKnown -Value $empty) }
    try { $bytes = [System.IO.File]::ReadAllBytes($path); Assert-HordeAsciiBytes -Bytes $bytes -What ("the progress state " + $path); $text = [System.Text.Encoding]::ASCII.GetString($bytes) }
    catch { return (New-HordeUnknown -Reason ("the progress state " + $path + " cannot be read: " + $_.Exception.Message)) }
    $why = "the progress state " + $path + " does not hold together"
    if (@(Find-HordeJsonDuplicateKey -Text $text).Count -gt 0) { return (New-HordeUnknown -Reason ($why + ": a member is repeated")) }
    try { $s = ConvertFrom-Json -InputObject $text } catch { return (New-HordeUnknown -Reason ($why + ": it is not JSON")) }
    if ($s -isnot [System.Management.Automation.PSCustomObject]) { return (New-HordeUnknown -Reason ($why + ": it is not an object")) }
    $names = @($s.PSObject.Properties | ForEach-Object { $_.Name }) | Sort-Object
    if (($names -join ",") -cne "head,line,offset,path,pending,phones,rewind,sent,skip,started,stopped,tail,v") { return (New-HordeUnknown -Reason ($why + ": its members are " + ($names -join ", "))) }
    $whole = { param($v) return (($v -is [int] -or $v -is [long]) -and $v -ge 0) }
    $hash = { param($v) return ($v -is [string] -and $v -cmatch '\A([0-9a-f]{64})?\z') }
    $keyIds = { param($v) return (@(@($v) | Where-Object { $_ -isnot [string] -or $_ -cnotmatch '\A[0-9a-f]{32}\z' }).Count -eq 0) }
    if (-not ($s.v -is [int] -or $s.v -is [long]) -or $s.v -ne 1) { return (New-HordeUnknown -Reason ($why + ": it is not version 1")) }
    if ($s.started -isnot [bool] -or $s.skip -isnot [bool]) { return (New-HordeUnknown -Reason ($why + ": started and skip are not true or false")) }
    if ($s.path -isnot [string] -or $s.path.Length -gt 1024) { return (New-HordeUnknown -Reason ($why + ": its path is not a path")) }
    if (-not (& $whole $s.offset) -or -not (& $whole $s.line)) { return (New-HordeUnknown -Reason ($why + ": its offset and line are not whole numbers")) }
    if (-not (& $hash $s.head) -or -not (& $hash $s.tail)) { return (New-HordeUnknown -Reason ($why + ": its marks are not hashes")) }
    if (-not (& $keyIds $s.phones)) { return (New-HordeUnknown -Reason ($why + ": a phone key is not a key id")) }
    foreach ($k in @($s.pending)) { if ($k -isnot [string] -or $k.Length -gt 160) { return (New-HordeUnknown -Reason ($why + ": a pending envelope is not a replay key")) } }
    foreach ($m in @($s.sent)) { if ($m -isnot [string] -or $m -cnotmatch '\A[0-9a-f]{16}:[1-9][0-9]{0,15}\z') { return (New-HordeUnknown -Reason ($why + ": a sent entry is not an id mark and a line")) } }
    if ($s.stopped -isnot [string] -or @("", "file-replaced") -cnotcontains $s.stopped) { return (New-HordeUnknown -Reason ($why + ": its stopped is not a reason this code knows")) }
    $rewind = $null
    if ($null -ne $s.rewind) {
        $rw = $s.rewind
        $rwNames = $(if ($rw -is [System.Management.Automation.PSCustomObject]) { (@($rw.PSObject.Properties | ForEach-Object { $_.Name }) | Sort-Object) -join "," } else { "" })
        if ($rwNames -cne "head,line,offset,phones,skip,started,tail" -or $rw.started -isnot [bool] -or $rw.skip -isnot [bool] -or -not (& $whole $rw.offset) -or -not (& $whole $rw.line) -or -not (& $hash $rw.head) -or -not (& $hash $rw.tail) -or -not (& $keyIds $rw.phones)) {
            return (New-HordeUnknown -Reason ($why + ": its rewind is not a place in the file"))
        }
        $rewind = [pscustomobject]@{ started = $rw.started; offset = [long]$rw.offset; line = [long]$rw.line; skip = $rw.skip; head = $rw.head; tail = $rw.tail; phones = @($rw.phones) }
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ started = $s.started; path = $s.path; offset = [long]$s.offset; line = [long]$s.line; skip = $s.skip; head = $s.head; tail = $s.tail
        phones = @($s.phones); pending = @($s.pending); sent = @($s.sent); rewind = $rewind; stopped = $s.stopped }))
}

function ConvertTo-HordeProgressChannelStateText {
    # The durable state as its file's text: what is written, and what tells whether it changed.
    param([Parameter(Mandatory = $true)]$State)
    $tf = { param($b) if ($b) { "true" } else { "false" } }
    $list = { param($items) (@($items) | ForEach-Object { ConvertTo-HordeProgressChannelJsonString "$_" }) -join "," }
    $rewind = "null"
    if ($null -ne $State.rewind) {
        $rw = $State.rewind
        $rewind = '{"started":' + (& $tf $rw.started) + ',"offset":' + [long]$rw.offset + ',"line":' + [long]$rw.line + ',"skip":' + (& $tf $rw.skip) + ',"head":"' + $rw.head + '","tail":"' + $rw.tail + '","phones":[' + (& $list $rw.phones) + ']}'
    }
    return ('{"v":1,"started":' + (& $tf $State.started) + ',"path":' + (ConvertTo-HordeProgressChannelJsonString "$($State.path)") + ',"offset":' + [long]$State.offset + ',"line":' + [long]$State.line + ',"skip":' + (& $tf $State.skip) +
        ',"head":"' + $State.head + '","tail":"' + $State.tail + '","phones":[' + (& $list $State.phones) + '],"pending":[' + (& $list $State.pending) + '],"sent":[' + (& $list $State.sent) + '],"rewind":' + $rewind + ',"stopped":"' + $State.stopped + '"}')
}

function Write-HordeProgressChannelState {
    # The durable state, replaced whole in one rename. Throws when it cannot be written.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)]$State)
    $path = Get-HordeProgressChannelStatePath -HordeHome $HordeHome
    $dir = [System.IO.Path]::GetDirectoryName($path)
    [void][System.IO.Directory]::CreateDirectory($dir)
    $tmp = [System.IO.Path]::Combine($dir, ("state-" + [guid]::NewGuid().ToString("N") + ".tmp"))
    $fs = New-Object System.IO.FileStream -ArgumentList $tmp, ([System.IO.FileMode]::CreateNew), ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::None)
    try { $b = [System.Text.Encoding]::ASCII.GetBytes((ConvertTo-HordeProgressChannelStateText -State $State)); $fs.Write($b, 0, $b.Length); $fs.Flush($true) } finally { $fs.Dispose() }
    try { Move-HordeFileAtomic -From $tmp -To $path } catch { try { [System.IO.File]::Delete($tmp) } catch { }; throw }
}

function Get-HordeProgressChannelMemory {
    # The channel's memory in this run's context, its durable state read on first use: { ok; reason; mine }.
    param($Context)
    if (-not $Context.state.ContainsKey("progress")) {
        $Context.state["progress"] = @{ loaded = $false; durable = $null; lastSentAt = [datetime]::MinValue; said = @{}; seenLength = [long]-1; seenWrite = [datetime]::MinValue }
    }
    $mine = $Context.state["progress"]
    if (-not $mine.loaded) {
        $s = Read-HordeProgressChannelState -HordeHome (Get-HordeProgressChannelHome $Context)
        if ($s.state -cne "known") { return [pscustomobject]@{ ok = $false; reason = $s.reason; mine = $mine } }
        $mine.durable = $s.value
        $mine.loaded = $true
    }
    return [pscustomobject]@{ ok = $true; reason = ""; mine = $mine }
}

function Get-HordeProgressChannelPhones {
    # The trusted phone keys, at most an envelope's recipients.
    param($Context)
    $phones = Find-HordeRelayPhoneKeys -HordeHome (Get-HordeProgressChannelHome $Context)
    if ($phones.state -cne "known") { return $phones }
    $keys = @($phones.value)
    $limit = (Get-HordeRelayEnvelopeLimits).recipients
    if ($keys.Count -gt $limit) { $keys = @($keys | Select-Object -First $limit) }
    return (New-HordeKnown -Value $keys)
}

function Add-HordeProgressChannelPending {
    # Keys recorded and to be put, after those waiting. The first to wait marks rewind: where the state
    # was before them (NEVER PUT TO A KEY REVOKED SINCE IT WAS RECORDED, in the header).
    param($State, [string[]]$Keys, $Before)
    if (@($Keys).Count -eq 0) { return }
    if (@($State.pending).Count -eq 0) { $State.rewind = $Before }
    $State.pending = @(@($State.pending) + @($Keys))
}

function Save-HordeProgressChannelBodies {
    # Record each body as one envelope of -Kind sealed to -Phones: { ok; reason; keys }, the keys in order.
    param($Context, [string]$Kind, [object[]]$Bodies, [object[]]$Phones)
    $recipients = @($Phones | ForEach-Object { , ([byte[]]$_.public) })
    $keys = New-Object System.Collections.ArrayList
    foreach ($b in @($Bodies)) {
        $saved = Save-HordeRelayChannelEnvelope -Context $Context -Channel "progress" -Kind $Kind -Body ([System.Text.Encoding]::ASCII.GetBytes([string]$b)) -Recipients $recipients
        if ($saved.state -cne "known") { return [pscustomobject]@{ ok = $false; reason = $saved.reason; keys = @($keys.ToArray()) } }
        [void]$keys.Add($saved.value.key)
    }
    return [pscustomobject]@{ ok = $true; reason = ""; keys = @($keys.ToArray()) }
}

function Send-HordeProgressChannelPending {
    # Put every envelope recorded and not yet taken, in order, from the journal; each one taken leaves
    # the state. "" when all were taken, else why not.
    param($Context, $Mine)
    $homeDir = Get-HordeProgressChannelHome $Context
    $mailbox = New-HordeRelayMailbox -Horde $Context.horde -Reader "phone"
    $d = $Mine.durable
    $trusted = $null
    while (@($d.pending).Count -gt 0) {
        $key = @($d.pending)[0]
        $rec = Test-HordeRelayJournalSent -Key $key -HordeHome $homeDir
        if ($rec.state -cne "known") { return ("the journal cannot give back " + $key + ": " + $rec.reason) }
        if ($rec.value.sent) {
            if ($null -eq $trusted) {
                $now = Get-HordeProgressChannelPhones -Context $Context
                if ($now.state -cne "known") { return ("the phone keys trusted now cannot be read, so nothing is put: " + $now.reason) }
                $trusted = @($now.value | ForEach-Object { $_.agreeKeyId })
            }
            $to = @((Read-HordeRelayEnvelope -Text $rec.value.text).value.header.to)
            if (@($to | Where-Object { $trusted -cnotcontains $_ }).Count -gt 0) {
                if ($rec.value.kind -ceq "entries") {
                    # Every waiting envelope of entries goes, and the lines are read again from rewind.
                    $keep = New-Object System.Collections.ArrayList
                    foreach ($k in @($d.pending)) {
                        $kr = Test-HordeRelayJournalSent -Key $k -HordeHome $homeDir
                        if ($kr.state -ceq "known" -and $kr.value.sent -and $kr.value.kind -ceq "entries") { continue }
                        [void]$keep.Add($k)
                    }
                    $d.pending = @($keep.ToArray())
                    if ($null -ne $d.rewind) {
                        $d.started = $d.rewind.started; $d.offset = $d.rewind.offset; $d.line = $d.rewind.line; $d.skip = $d.rewind.skip
                        $d.head = $d.rewind.head; $d.tail = $d.rewind.tail; $d.phones = @($d.rewind.phones)
                    }
                    $Mine.seenLength = [long]-1
                }
                else { $d.pending = @(@($d.pending) | Select-Object -Skip 1) }
                if (@($d.pending).Count -eq 0) { $d.rewind = $null }
                try { Write-HordeProgressChannelState -HordeHome $homeDir -State $d } catch { return ("the progress state could not be written: " + $_.Exception.Message) }
                continue
            }
            $put = Send-HordeRelayChannelSaved -Context $Context -Saved ([pscustomobject]@{ key = $key; text = $rec.value.text }) -Mailbox $mailbox
            if ($put.state -cne "known") { return $put.reason }
        }
        # A key the journal does not hold was never recorded (a state written by hand): nothing to put.
        $d.pending = @(@($d.pending) | Select-Object -Skip 1)
        if (@($d.pending).Count -eq 0) { $d.rewind = $null }
        try { Write-HordeProgressChannelState -HordeHome $homeDir -State $d } catch { return ("the progress state could not be written: " + $_.Exception.Message) }
    }
    return ""
}

function Test-HordeProgressChannelFile {
    # Is -Path still the file the state followed (A FILE REPLACED OR CUT SHORT, in the header)?
    # { broken; retry; length; write } - broken: why it is not, in words, or ""; retry: it could not be
    # looked at just now, which is not a verdict; length and write: the file's now.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$State)
    $answer = [pscustomobject]@{ broken = ""; retry = ""; exists = $false; length = [long]0; write = [datetime]::MinValue }
    if ($State.path -cne "" -and $State.path -cne $Path) { $answer.broken = "is not the file followed so far (" + $State.path + "): the setting progressFile names another"; return $answer }
    try {
        $info = New-Object System.IO.FileInfo -ArgumentList $Path
        $answer.exists = $info.Exists
        if ($info.Exists) { $answer.length = [long]$info.Length; $answer.write = $info.LastWriteTimeUtc }
    } catch { $answer.retry = $_.Exception.Message; return $answer }
    if (-not $State.started) { return $answer }
    if (-not $answer.exists) { if ($State.offset -gt 0) { $answer.broken = "is gone, after " + $State.offset + " bytes of it were read" }; return $answer }
    $marks = Get-HordeProgressChannelMarks -Path $Path -Offset $State.offset
    if (-not $marks.ok) { $answer.retry = $marks.reason; return $answer }
    if ($marks.length -lt $State.offset) { $answer.broken = "was cut short: " + $State.offset + " bytes of it were read, and it now holds " + $marks.length; return $answer }
    if ($marks.head -cne $State.head) { $answer.broken = "was replaced: its start is not the start that was read"; return $answer }
    if ($marks.tail -cne $State.tail) { $answer.broken = "was rewritten: the part already read is not what was read"; return $answer }
    return $answer
}

function Invoke-HordeProgressChannelTick {
    # OUT, in the header: { lines; failed }.
    param($Context)
    $m = Get-HordeProgressChannelMemory -Context $Context
    $mine = $m.mine
    $once = {
        param([string]$Key, [string]$Line, [bool]$Failed)
        if ($mine.said.ContainsKey($Key) -and $mine.said[$Key] -ceq $Line) { return [pscustomobject]@{ lines = @(); failed = $Failed } }
        $mine.said[$Key] = $Line
        return [pscustomobject]@{ lines = @($Line); failed = $Failed }
    }
    if (-not $m.ok) { return (& $once "state" ("progress is stopped: " + $m.reason + "; mend or move the file, and the channel starts again") $true) }
    $set = Get-HordeProgressChannelSettings -Context $Context
    if ($set.state -cne "known") { return (& $once "settings" ("progress is stopped: " + $set.reason) $true) }
    $set = $set.value
    $homeDir = Get-HordeProgressChannelHome $Context
    $path = Get-HordeProgressChannelFilePath -HordeHome $homeDir -Setting $set.progressFile
    $d = $mine.durable
    if (@($d.pending).Count -gt 0) {
        $why = Send-HordeProgressChannelPending -Context $Context -Mine $mine
        if ($why -cne "") { return [pscustomobject]@{ lines = @("progress not delivered yet (" + @($d.pending).Count + " envelope(s) recorded and waiting): " + $why); failed = $true } }
    }
    $phones = Get-HordeProgressChannelPhones -Context $Context
    if ($phones.state -cne "known") { return [pscustomobject]@{ lines = @("no progress sent: " + $phones.reason); failed = $true } }
    $all = @($phones.value)
    if ($all.Count -eq 0) { return (& $once "phones" "no progress sent: no phone identity key of this horde is trusted yet" $false) }
    $mine.said.Remove("phones")
    if ([long]$set.sendIntervalMs -gt 0 -and ([datetime]::UtcNow - $mine.lastSentAt).TotalMilliseconds -lt [long]$set.sendIntervalMs) { return [pscustomobject]@{ lines = @(); failed = $false } }
    $known = @($all | ForEach-Object { $_.agreeKeyId })
    $fresh = @($all | Where-Object { @($d.phones) -cnotcontains $_.agreeKeyId })

    # THE FILE: still the one that was followed?
    $file = Test-HordeProgressChannelFile -Path $path -State $d
    if ($file.retry -cne "") { return (& $once "read" ("no progress sent: the progress log " + $path + " cannot be looked at now: " + $file.retry) $false) }
    $was = ConvertTo-HordeProgressChannelStateText -State $d
    $before = [pscustomobject]@{ started = $d.started; offset = $d.offset; line = $d.line; skip = $d.skip; head = $d.head; tail = $d.tail; phones = @($d.phones) }
    $notices = New-Object System.Collections.ArrayList
    $lines = New-Object System.Collections.ArrayList
    if ($file.broken -cne "") {
        $stopLine = "progress is stopped: the progress log " + $path + " " + $file.broken + ". Nothing is sent again and nothing is started over by itself: put the file back as it was and the channel goes on; or, to follow the file from its start, delete " + (Get-HordeProgressChannelStatePath -HordeHome $homeDir) + " (the phone shows each entry once)"
        # Said once a run, however the broken file goes on changing under it.
        if ($d.stopped -ceq "file-replaced") { if ($mine.said.ContainsKey("stopped")) { return [pscustomobject]@{ lines = @(); failed = $false } }; $mine.said["stopped"] = $stopLine; return [pscustomobject]@{ lines = @($stopLine); failed = $false } }
        # Stopped now: said here, and to the phone, once.
        $d.stopped = "file-replaced"
        $saved = Save-HordeProgressChannelBodies -Context $Context -Kind "notice" -Bodies @((New-HordeProgressChannelNotice -Context $Context -Code "file-replaced")) -Phones $all
        Add-HordeProgressChannelPending -State $d -Keys @($saved.keys) -Before $before
        try { Write-HordeProgressChannelState -HordeHome $homeDir -State $d } catch { $d.stopped = ""; return [pscustomobject]@{ lines = @($stopLine, ("and the progress state could not be written: " + $_.Exception.Message)); failed = $true } }
        $mine.said["stopped"] = $stopLine
        $why = $(if ($saved.ok) { Send-HordeProgressChannelPending -Context $Context -Mine $mine } else { $saved.reason })
        if ($why -cne "") { return [pscustomobject]@{ lines = @($stopLine, ("the phone is not told yet: " + $why)); failed = $true } }
        return [pscustomobject]@{ lines = @($stopLine); failed = $false }
    }
    if ($d.stopped -cne "") {
        # As it was again: the channel goes on from where it stopped, and says so.
        $d.stopped = ""
        $mine.said.Remove("stopped")
        [void]$notices.Add((New-HordeProgressChannelNotice -Context $Context -Code "following"))
        [void]$lines.Add("the progress log " + $path + " is as it was again: the channel goes on from byte " + $d.offset)
    }
    if (-not $file.exists) {
        # NOTHING YET. (A state that had stopped is written as going on: there is nothing to be broken.)
        if ((ConvertTo-HordeProgressChannelStateText -State $d) -cne $was) { try { Write-HordeProgressChannelState -HordeHome $homeDir -State $d } catch { } }
        $quiet = & $once "file" ("no progress yet: there is no progress log at " + $path) $false
        return [pscustomobject]@{ lines = @(@($lines.ToArray()) + @($quiet.lines)); failed = $false }
    }
    $mine.said.Remove("file"); $mine.said.Remove("read")
    # Nothing new since the last look, and nobody new to send to: the file is not opened.
    if ($d.started -and $fresh.Count -eq 0 -and $notices.Count -eq 0 -and $file.length -eq $d.offset -and $file.length -eq $mine.seenLength -and $file.write -eq $mine.seenWrite) { return [pscustomobject]@{ lines = @(); failed = $false } }

    $batches = New-Object System.Collections.ArrayList
    $bad = New-Object System.Collections.ArrayList
    $sentMarks = @{}
    foreach ($s in @($d.sent)) { $p = $s.Split([char]':'); $sentMarks[$p[0]] = [long]$p[1] }
    if (-not $d.started) {
        # THE FIRST LOOK: the newest entries, for every key there is.
        $tail = Read-HordeProgressChannelTail -Path $path -Keep ([int]$set.backfillEntries) -MaxBytes ([long]$set.readBytes)
        if (-not $tail.ok) { return (& $once "read" ("no progress sent: the progress log " + $path + " could not be read: " + $tail.reason) $false) }
        foreach ($b in @($tail.bad)) { [void]$bad.Add($b) }
        if (@($tail.entries).Count -gt 0) { [void]$batches.Add([pscustomobject]@{ phones = $all; backfill = $true; entries = @($tail.entries) }) }
        $d.started = $true; $d.offset = $tail.offset; $d.line = $tail.line; $d.skip = $tail.skip; $d.sent = @($tail.marks)
    } else {
        if ($fresh.Count -gt 0 -and $d.offset -gt 0) {
            # A KEY TRUSTED SINCE: the newest entries of what was already read, to it alone.
            $tail = Read-HordeProgressChannelTail -Path $path -Keep ([int]$set.backfillEntries) -MaxBytes ([long]$set.readBytes) -Upto $d.offset
            if (-not $tail.ok) { return (& $once "read" ("no progress sent: the progress log " + $path + " could not be read: " + $tail.reason) $false) }
            if (@($tail.entries).Count -gt 0) { [void]$batches.Add([pscustomobject]@{ phones = $fresh; backfill = $true; entries = @($tail.entries) }) }
        }
        $r = Read-HordeProgressChannelLines -Path $path -Offset $d.offset -Line $d.line -Skip $d.skip -MaxBytes ([long]$set.readBytes)
        if (-not $r.ok) { return (& $once "read" ("no progress sent: the progress log " + $path + " could not be read: " + $r.reason) $false) }
        foreach ($b in @($r.bad)) { [void]$bad.Add($b) }
        $new = New-Object System.Collections.ArrayList
        $marks = New-Object System.Collections.ArrayList
        foreach ($e in @($r.entries)) {
            # ONE ID, ONE ENTRY: an id an earlier line carried is left out; the same line read again is not.
            $mark = Get-HordeProgressChannelIdMark -Id $e.entry.id
            if ($sentMarks.ContainsKey($mark) -and $sentMarks[$mark] -ne $e.line) { [void]$bad.Add("line " + $e.line + " repeats the id of line " + $sentMarks[$mark] + "; the first stands"); continue }
            if (-not $sentMarks.ContainsKey($mark)) { $sentMarks[$mark] = $e.line; [void]$marks.Add($mark + ":" + $e.line) }
            [void]$new.Add($e)
        }
        if ($new.Count -gt 0) { [void]$batches.Add([pscustomobject]@{ phones = $all; backfill = $false; entries = @($new.ToArray()) }) }
        $d.offset = $r.offset; $d.line = $r.line; $d.skip = $r.skip
        $d.sent = @(@($d.sent) + @($marks.ToArray()) | Select-Object -Last $script:HordeProgressChannelIdsKept)
    }
    # The marks of the file up to the new offset, which the next look checks.
    $marksNow = Get-HordeProgressChannelMarks -Path $path -Offset $d.offset
    if (-not $marksNow.ok -or $marksNow.length -lt $d.offset) {
        $d.started = $before.started; $d.offset = $before.offset; $d.line = $before.line; $d.skip = $before.skip
        return (& $once "read" ("no progress sent: the progress log " + $path + " changed while it was read; it is read again") $false)
    }
    $d.head = $marksNow.head; $d.tail = $marksNow.tail; $d.path = $path

    $keys = New-Object System.Collections.ArrayList
    $count = 0
    $fail = ""
    foreach ($b in $batches) {
        $budget = [long][System.Math]::Min([double]$set.pageBytes, [double](Get-HordeRelayChannelBodyBudget -Context $Context -Recipients @($b.phones).Count))
        $pages = New-HordeProgressChannelPages -Context $Context -Backfill $b.backfill -Entries @($b.entries) -Budget $budget
        if (@($b.phones).Count -eq $all.Count) { foreach ($x in @($pages.bad)) { [void]$bad.Add($x) } }
        $saved = Save-HordeProgressChannelBodies -Context $Context -Kind "entries" -Bodies @($pages.bodies) -Phones @($b.phones)
        foreach ($k in $saved.keys) { [void]$keys.Add($k) }
        if (-not $saved.ok) { $fail = $saved.reason; break }
        $count += $pages.shown
    }
    $entryEnvelopes = $keys.Count
    if ($fail -ceq "" -and $bad.Count -gt 0) { [void]$notices.Add((New-HordeProgressChannelNotice -Context $Context -Code "lines-skipped" -Count $bad.Count)) }
    if ($fail -ceq "" -and $notices.Count -gt 0) {
        $saved = Save-HordeProgressChannelBodies -Context $Context -Kind "notice" -Bodies @($notices.ToArray()) -Phones $all
        foreach ($k in $saved.keys) { [void]$keys.Add($k) }
        if (-not $saved.ok) { $fail = $saved.reason }
    }
    if ($fail -cne "") {
        # What was recorded is kept to be put; the place in the file stays, so the rest is read again.
        $d.started = $before.started; $d.offset = $before.offset; $d.line = $before.line; $d.skip = $before.skip; $d.head = $before.head; $d.tail = $before.tail
        Add-HordeProgressChannelPending -State $d -Keys @($keys.ToArray()) -Before $before
        try { Write-HordeProgressChannelState -HordeHome $homeDir -State $d } catch { }
        return [pscustomobject]@{ lines = @("progress not sent: " + $fail); failed = $true }
    }
    Add-HordeProgressChannelPending -State $d -Keys @($keys.ToArray()) -Before $before
    $d.phones = $known
    $mine.seenLength = $file.length; $mine.seenWrite = $file.write
    # Written only when it changed: a runner turns every second, and a quiet log is no reason to rewrite
    # a file each time.
    try { if ((ConvertTo-HordeProgressChannelStateText -State $d) -cne $was) { Write-HordeProgressChannelState -HordeHome $homeDir -State $d } }
    catch { return [pscustomobject]@{ lines = @("progress recorded, and the progress state could not be written: " + $_.Exception.Message + "; it is sent again after a restart, and the phone shows each entry once"); failed = $true } }
    $n = 0
    foreach ($b in @($bad.ToArray())) {
        $n++
        if ($n -le $script:HordeProgressChannelSaidLines) { [void]$lines.Add("left out of the progress sent: " + $b) }
    }
    if ($bad.Count -gt $script:HordeProgressChannelSaidLines) { [void]$lines.Add("and " + ($bad.Count - $script:HordeProgressChannelSaidLines) + " more line(s) left out") }
    if ($keys.Count -eq 0) { return [pscustomobject]@{ lines = @($lines.ToArray()); failed = $false } }
    $mine.lastSentAt = [datetime]::UtcNow
    $what = "" + $count + " progress entr" + $(if ($count -eq 1) { "y" } else { "ies" }) + " in " + $entryEnvelopes + " envelope(s)" + $(if ($keys.Count -gt $entryEnvelopes) { " and " + ($keys.Count - $entryEnvelopes) + " notice(s)" } else { "" })
    $why = Send-HordeProgressChannelPending -Context $Context -Mine $mine
    if ($why -cne "") { [void]$lines.Add($what + " recorded; not delivered yet: " + $why); return [pscustomobject]@{ lines = @($lines.ToArray()); failed = $true } }
    [void]$lines.Add($what + " sent")
    return [pscustomobject]@{ lines = @($lines.ToArray()); failed = $false }
}

function Invoke-HordeProgressChannelAccept {
    # MACHINE TO PHONE ONLY (in the header): nothing is ever taken in. The port refuses every kind
    # before this is reached; should a record of this channel ever be handed over, it is refused here.
    param($Context, $Item)
    return [pscustomobject]@{ outcome = "refused"; reason = "the progress channel takes nothing in: it only sends the progress log to the phone" }
}

$null = Register-HordeRelayChannel -Folder $script:HordeProgressChannelFolder -Name "progress" -Kinds @() -Senders "founder" `
    -Accept { param($Context, $Item) return (Invoke-HordeProgressChannelAccept -Context $Context -Item $Item) } `
    -Tick { param($Context) return (Invoke-HordeProgressChannelTick -Context $Context) }
