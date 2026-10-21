# channels/cards - the fleet at a glance on the founder's phone: one card per lane and one for the Thrall,
# made on this machine and sent whole, end to end encrypted (the founder asked for the Progress tab as
# cards, 2026-10-13). The progress log (channels/progress) is the history under them, unchanged: a card
# opens that lane's part of it on the phone.
#
# WHY A SNAPSHOT AND NOT THE LOG. The phone holds the last 100 envelopes of the log
# (channels/progress/Channel.ps1, keepEnvelopes), so a lane that has been quiet for a week would have no
# card at all if cards were made from it. A card is made here, from what each lane says of itself now,
# and sent whole, beside the log and never inside it.
#
# WHAT IT READS - every source a SETTING (settings\relay-cards.json), each empty by default, which means a
# place under Horde's own home: shipped code names no folder of anyone's machine (CONTRIBUTING 11), and a
# suite's `horde relay run` on a home of its own never reads a real fleet. THIS CHANNEL ONLY READS.
#   lanesFolder       <HORDE_HOME>\progress\lanes. Each direct subfolder is one lane, its status.txt what
#                     the lane says of itself: "horde-orc-status 1", then orc:, lane:, doing:, finished:,
#                     blocked: and waiting on: lines (waiting on: may be missing). A folder with
#                     status.retired.txt and no status.txt is a retired lane: no card. Whether a file is in
#                     the standard form is fleet/StatusPanel.ps1's to say, by the record's own rules
#                     (Read-HordeCardsChannelStatusText); one that breaks them still gets its card.
#   ledgerFile        <HORDE_HOME>\progress\tasks.jsonl: the fleet's task ledger, one JSON event a line
#                     (opened, started, waiting, done, verified, handed, ...), read the way its own tool
#                     reads it: opened first, the rest in time order; handed moves a task to another lane.
#   areaLanesFile     <HORDE_HOME>\progress\area-lanes.json: {"v":1,"areas":{"<area>":"<lane>[,<lane>]"}}.
#                     THE ONE PLACE that says which lanes an entry of the log belongs to when the entry
#                     names none: on 2026-10-13, 170 of 178 entries carried only an area. It rides in the
#                     snapshot, and the phone filters a lane's stream with it (relay/js/protocol.js,
#                     entryLanes). The map is data, not code: its words name private work.
#   runsFolder        <HORDE_HOME>\progress\runs: the fleet's runs, one folder each with run.json and
#                     sessions\<id>\events.jsonl. The census: a session of a run not closed whose last
#                     event, written within the last 24 hours, is started or progress is running, and
#                     blocked is waiting on a person. Older than that it is counted as neither: 96 runs
#                     were open on 2026-10-13 and most had long finished.
#   thrallStatusFile  <HORDE_HOME>\progress\thrall-status.txt: the Thrall's own status, in the lane form.
#                     NOTHING WRITES ONE TODAY (2026-10-13): the Thrall card is then made from the census
#                     and the lanes alone, and its "now" is empty.
#   machineName       what each card says it came from; empty means this computer's name.
#
# WHAT A CARD SAYS (OUT, below): the lane's id (its orc letter, else its folder's name), its name, its
# latest activity (asOf: the phone shows its age) and which source that was (asOfSource: status, progress
# or decision) - the newest of its status file's last write, its newest progress entry and its newest
# question asked or answered, the one derivation the dash's Latest order uses (C, 2026-10-15; before,
# asOf was the status file's alone, and a lane that logged progress but forgot its status looked days
# old) - now, last done, waiting on,
# blocked yes or no, and from the ledger the tasks open and done in the last 7 days. A status file in
# another form still gets a card: its first lines as now, its waiting on line, and form "other" with
# the rules it breaks in plain words (problems), which the phone says. A file that is missing or cannot be read gets a card that says so - never no card.
#
# THE DASH RIDES IN THE SAME SNAPSHOT (design "Dash: one list of Orcs", PR 1, 2026-10-15): "dash" is the
# Orc registry's list in the founder's order (orcs/Registry.ps1, ConvertTo-HordeOrcDashDocument): v, ok,
# the registry version, and per Orc its id, letter, name, domain, place, back-burner flag, open questions,
# status word with its age, sessions open and Wargs active and inactive; then orcsLeftOut. WHY HERE AND
# NOT A CHANNEL OF ITS OWN: the relay keeps one envelope per channel from this machine (KeepFrom, below),
# so a second snapshot kind on this channel would push the cards out, and a channel of its own would read
# the same lanes folder a second time on a timer of its own. Here it is one look, one envelope, the same
# lanes setting, the same secret refusal - and the cards stay exactly as they are until PR 2 moves the
# phone over.
#
# NO SECRET LEAVES THE MACHINE. Every text that goes out is put through core/Secrets.ps1's refusal, the
# one the log's entries get. A text that trips it is replaced by a fixed sentence, and the card is still
# sent, with the field's name in its refused list: never the text, never what tripped it. THE REFUSAL
# LOOKS AT THE WHOLE TEXT, AND ONLY THEN IS IT CUT to 300 characters: review of PR 244 (2026-10-14)
# measured the other order letting 23 characters of a token and 31 of a 40-character key out, since a
# token across the cut loses its tail and then matches no pattern.
#
# OUT (the Tick), sealed to every TRUSTED phone identity key, exactly as the log is (channels/Port.ps1):
#   - ONE ENVELOPE, REPLACED WHOLE, ONLY THE LATEST KEPT. A snapshot is one envelope; its put says to keep,
#     of this machine's cards envelopes, from its own seq on (channels/Port.ps1, WHAT GOES TO THE PHONE
#     IS TRIMMED BY ITS SENDER), so the one before goes the moment this one is in the mailbox. As the
#     decisions snapshot does with its last page; a cards snapshot is its own last page.
#   - SENT WHEN IT CHANGED. Its hash leaves out when it was made; the same snapshot for the same phone
#     keys is not sent again. A new run sends one at its first look.
#   - LOOKED AT EVERY sendIntervalMs (30 s), not every turn: a look reads every lane file and the ledger.
#     There is no Glance: a card a minute late is still a card.
#   - RECORDED ONCE, PUT UNTIL IT IS TAKEN: the same envelope is put again next turn, and no new snapshot
#     is made while one waits (as channels/decisions).
#   - TOO LARGE FOR ONE ENVELOPE: the last cards are left out until it fits, and the snapshot says how
#     many (cardsLeftOut). The map is held to a quarter of the budget while cards are cut, and fills
#     the room the cards leave once every card is in; its last areas are left out and counted
#     (areasLeftOut): the cards are the glance, and an area left out only sends its entries to
#     the Thrall's stream. Each text is at most 300 characters, and that is NOT small: a non-ASCII
#     character is written as 6 bytes (\u05d0), so one 300-character Hebrew field is 1802 bytes, and 64
#     cards with every text full are 122049 bytes (128321 while each card still carried a note), against
#     47918 bytes for two phones on a relay whose text cap is 65536 (review of PR 244, measured again
#     2026-10-14; test/test-relay-channel-cards.ps1, 8).
#   - NO LANES FOLDER IS "NOTHING YET": nothing is sent, and it is said once.
#   - MACHINE TO PHONE ONLY: the channel takes nothing in.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\JsonText.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\ModuleSettings.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\Home.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\Secrets.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\ReadShared.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "fleet\StatusPanel.ps1")

$script:HordeCardsChannelFolder = $PSScriptRoot
# The settings and the paths they give are channels/cards/Sources.ps1 (it says why), with the area map's reader; the Orc registry
# the dash is made from is orcs/Registry.ps1, which reads the same lanes folder.
. (Join-Path $PSScriptRoot "Sources.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "orcs\Registry.ps1")
$script:HordeCardsChannelStatusBytes = 16384
$script:HordeCardsChannelLedgerBytes = 33554432
$script:HordeCardsChannelTailBytes = 65536
$script:HordeCardsChannelRecentHours = 24
$script:HordeCardsChannelDoneDays = 7
$script:HordeCardsChannelSecretWords = "Not shown: this line looks like it holds a secret, so it stays at the machine."
$script:HordeCardsChannelOrcPattern = '\A[A-Z][A-Z0-9]{0,3}\z'
$script:HordeCardsChannelClosed = @("done", "verified", "dropped", "superseded")

function Get-HordeCardsChannelHome {
    param($Context)
    if ("$($Context.hordeHome)" -ne "") { return $Context.hordeHome }
    return (Get-HordeHome)
}

function ConvertTo-HordeCardsChannelJsonString {
    # A JSON string of -Text in printable ASCII (as channels/progress writes its entries): one byte a
    # character, so the envelope's size is measured exactly.
    param([AllowEmptyString()][string]$Text)
    return ('"' + [regex]::Replace($Text, '[^\x20\x21\x23-\x5B\x5D-\x7E]', { param($m) '\u' + ([int][char]$m.Value).ToString("x4") }) + '"')
}

function Read-HordeCardsChannelStatusText {
    # What a lane's status file says: { form; reason; keys; first; asOf } - form "standard", "other",
    # "missing" or "unreadable"; reason, for "other", the rules it breaks in the status reader's own
    # words, and for "unreadable" why; keys a table of its "key: value" lines by key in lower case;
    # first its first lines that hold words, header aside.
    # STANDARD MEANS WHAT THE FLEET'S ONE STATUS READER SAYS IT IS: fleet/StatusPanel.ps1's
    # ConvertFrom-HordeFleetStatusBytes, the record's rules (header, one capital letter, doing and
    # finished at most 120 characters with no bare reference or path, the optional waiting-on line at
    # most 200, ASCII, no control character), which the decisions window uses too. No second copy of
    # them here (review of PR 244, 2026-10-14). A file that breaks them still gets its card, "other",
    # read loosely below and shown as it stands, with the reader's problems as the reason.
    param([Parameter(Mandatory = $true)][string]$Path)
    $out = [pscustomobject]@{ form = "missing"; reason = ""; keys = @{}; first = @(); asOf = "" }
    try {
        $info = New-Object System.IO.FileInfo -ArgumentList $Path
        if (-not $info.Exists) { return $out }
        $out.asOf = $info.LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
        if ($info.Length -gt $script:HordeCardsChannelStatusBytes) { $out.form = "unreadable"; $out.reason = "it is " + $info.Length + " bytes, far more than a status"; return $out }
        $stream = Open-HordeSharedStream -Path $Path
        try { $mem = New-Object System.IO.MemoryStream; $stream.CopyTo($mem); $bytes = $mem.ToArray() } finally { $stream.Dispose() }
    } catch { $out.form = "unreadable"; $out.reason = "it could not be read"; return $out }
    $judged = ConvertFrom-HordeFleetStatusBytes -Bytes $bytes
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    $lines = @($text -split "\r?\n" | Where-Object { $_.Trim() -ne "" })
    $keys = @{}
    $first = New-Object System.Collections.ArrayList
    foreach ($line in $lines) {
        $m = [regex]::Match($line, '\A\s*([A-Za-z][A-Za-z ]{0,20}?)\s*:\s*(.*)\z')
        if ($m.Success) { $k = $m.Groups[1].Value.ToLowerInvariant(); if (-not $keys.ContainsKey($k)) { $keys[$k] = $m.Groups[2].Value.Trim() } }
        if ($line.Trim() -cne "horde-orc-status 1" -and $first.Count -lt 2) { [void]$first.Add($line.Trim()) }
    }
    $out.first = @($first.ToArray())
    if (@($judged.problems).Count -eq 0) {
        # A standard record's values are the reader's, exactly as it hands them to the decisions window.
        $keys = @{}
        foreach ($k in @($judged.fields.Keys)) { $keys[$k] = $judged.fields[$k] }
        $out.form = "standard"
    } else {
        $out.form = "other"
        $out.reason = (@($judged.problems) -join "; ")
    }
    $out.keys = $keys
    return $out
}

function Protect-HordeCardsChannelField {
    # NO SECRET LEAVES THE MACHINE (the header): -Text WHOLE, as read, and what goes out - the text cut
    # as a card holds it, or the fixed sentence in its place with the field's name added to -Refused.
    # The refusal looks at the whole text first; only a text it lets through is cut.
    param([AllowEmptyString()][string]$Text, [string]$Field, [System.Collections.ArrayList]$Refused)
    $whole = Get-HordeCardsChannelClean $Text
    if ((Find-HordeSecretKind -Text $whole) -cne "") { [void]$Refused.Add($Field); return $script:HordeCardsChannelSecretWords }
    return (Get-HordeCardsChannelPlain $whole)
}

function New-HordeCardsChannelLaneCard {
    # One lane's card from its folder (WHAT A CARD SAYS, in the header): { lane; name; form; asOf; now;
    # lastDone; waitingOn; blocked; blockedText; problems; idNote; refused }. -Place: the folder's place in the list,
    # from 1, which names a lane no id can be made for ("lane-3"), so no two such lanes share one id.
    param([Parameter(Mandatory = $true)][string]$Folder, [int]$Place = 1)
    $leaf = Split-Path -Leaf $Folder
    $s = Read-HordeCardsChannelStatusText -Path (Join-Path $Folder "status.txt")
    $k = $s.keys
    # Every text WHOLE here: Protect-HordeCardsChannelField refuses on it, and only then cuts it.
    $get = { param($name) if ($k.ContainsKey($name)) { return (Get-HordeCardsChannelClean $k[$name]) }; return "" }
    $orc = & $get "orc"
    if ($orc -cnotmatch $script:HordeCardsChannelOrcPattern) {
        # Another form may still say whose lane it is: "LANE: stt-cpu-bench (Orc I)".
        $orc = ""
        foreach ($v in @($k.Values) + @($s.first)) { $m = [regex]::Match("$v", '\(Orc ([A-Z][A-Z0-9]{0,3})\)'); if ($m.Success) { $orc = $m.Groups[1].Value; break } }
    }
    $fallback = "lane-" + $Place
    $lane = $(if ($orc -cne "") { $orc } elseif ($leaf -cmatch $script:HordeCardsChannelLanePattern) { $leaf } else { $fallback })
    # "thrall" is the Thrall card's id on every page of the phone (surfaces/pwa/page/lane-card.js): no lane takes it.
    if ($lane -ceq "thrall") { $lane = $fallback }
    $name = & $get "lane"
    if ($name -ceq "") { $name = Get-HordeCardsChannelClean $leaf }
    $card = [ordered]@{ lane = $lane; name = $name; form = $s.form; asOf = $s.asOf; now = ""; lastDone = ""; waitingOn = ""; blocked = ""; blockedText = ""; problems = ""; idNote = "" }
    # No note on a card: the phone says what each form means (relay/js/protocol.js, cardFormNote) and
    # never read the machine's sentence, so it was bytes for nobody (C and F, 2026-10-14). A missing or
    # unreadable file has its form alone; why it could not be read was only ever in that note, and goes.
    if ($s.form -cne "missing" -and $s.form -cne "unreadable") {
        $card.now = & $get "doing"
        if ($s.form -ceq "other" -and $card.now -ceq "") { $card.now = Get-HordeCardsChannelClean (@($s.first) -join " - ") }
        $card.lastDone = & $get "finished"
        $card.waitingOn = & $get "waiting on"
        $b = & $get "blocked"
        if ($b -cne "") {
            if ($b -imatch '\Ano\b') { $card.blocked = "no" } else { $card.blocked = "yes"; $card.blockedText = [regex]::Replace($b, '\A(?i:yes)\b\s*[-:,.]?\s*', '') }
        }
        if ($s.form -ceq "other") { $card.problems = $s.reason }
    }
    $refused = New-Object System.Collections.ArrayList
    foreach ($f in @("lane", "name", "now", "lastDone", "waitingOn", "blockedText", "problems")) { $card[$f] = Protect-HordeCardsChannelField -Text $card[$f] -Field $f -Refused $refused }
    # A refused id cannot name a stream: the lane is then its folder's place in the list, said plainly.
    if (@($refused) -ccontains "lane") { $card.lane = $fallback }
    $card["refused"] = @($refused.ToArray())
    return [pscustomobject]$card
}

function ConvertFrom-HordeCardsChannelTime {
    # An ISO time with a zone as UTC, or $null.
    param($Value)
    if ($Value -is [datetime]) { if ($Value.Kind -eq [System.DateTimeKind]::Unspecified) { return $null }; return $Value.ToUniversalTime() }
    if ($Value -isnot [string]) { return $null }
    $parsed = [datetime]::MinValue
    if ($Value -cnotmatch '(Z|[+-][0-9]{2}:[0-9]{2})\z') { return $null }
    if ([datetime]::TryParse($Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) { return $parsed.ToUniversalTime() }
    return $null
}

function Read-HordeCardsChannelLedger {
    # The ledger's counts by lane: { ok; reason; lanes } - lanes a table lane -> { open; doneWeek }.
    # A task is open until it is done, verified, dropped or superseded; done this week when it is done or
    # verified and its last such event is within 7 days of -Now. A line that does not read is passed over
    # (its own tool does the same) and counted in skipped.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][datetime]$Now)
    $answer = [pscustomobject]@{ ok = $false; reason = ""; lanes = @{}; skipped = 0 }
    try {
        $info = New-Object System.IO.FileInfo -ArgumentList $Path
        if (-not $info.Exists) { $answer.reason = "there is no task ledger at " + $Path; return $answer }
        if ($info.Length -gt $script:HordeCardsChannelLedgerBytes) { $answer.reason = "the task ledger " + $Path + " is " + $info.Length + " bytes, more than is read"; return $answer }
        $text = Read-HordeSharedText -Path $Path
    } catch { $answer.reason = "the task ledger " + $Path + " could not be read"; return $answer }
    $opened = New-Object System.Collections.ArrayList
    $events = New-Object System.Collections.ArrayList
    $i = 0
    foreach ($line in ($text -split "\r?\n")) {
        if ($line.Trim() -eq "") { continue }
        $r = $null
        try { $r = ConvertFrom-Json -InputObject $line } catch { $r = $null }
        if ($null -eq $r -or $r -isnot [System.Management.Automation.PSCustomObject]) { $answer.skipped++; continue }
        # A member a line does not have is "": under -Version Latest a missing member read bare throws.
        $field = @{}
        # Assigned bare: $( ) would unroll a one-item list ["E"] into the text "E".
        foreach ($name in @("ts", "task", "event", "lane", "to")) { $pp = $r.PSObject.Properties[$name]; $field[$name] = $null; if ($null -ne $pp) { $field[$name] = $pp.Value } }
        $when = ConvertFrom-HordeCardsChannelTime $field["ts"]
        # A task, event, lane or to that is not text is no line: printed, an object is "@{a=1}" and a
        # list its items joined, each read as a task or a lane that is not one (review of PR 244).
        $typed = $true
        foreach ($name in @("task", "event", "lane", "to")) { if ($null -ne $field[$name] -and $field[$name] -isnot [string]) { $typed = $false } }
        if ($null -eq $when -or -not $typed -or "$($field['task'])" -ceq "" -or "$($field['event'])" -ceq "") { $answer.skipped++; continue }
        $i++
        $e = [pscustomobject]@{ task = "$($field['task'])"; event = "$($field['event'])"; at = $when; lane = "$($field['lane'])"; to = "$($field['to'])"; i = $i }
        if ($e.event -ceq "opened") { [void]$opened.Add($e) } else { [void]$events.Add($e) }
    }
    $tasks = @{}
    foreach ($e in $opened) { $tasks[$e.task] = @{ lane = $e.lane; state = "opened"; doneAt = $null } }
    foreach ($e in @($events | Sort-Object -Property at, i)) {
        if (-not $tasks.ContainsKey($e.task)) { continue }
        $t = $tasks[$e.task]
        switch -CaseSensitive ($e.event) {
            "progress" { }
            "priority" { }
            "resumed" { $t.state = "started" }
            "reopened" { $t.state = "started" }
            "handed" { if ($e.to -cne "") { $t.lane = $e.to }; $t.state = "opened" }
            default { $t.state = $e.event; if ($e.event -ceq "done" -or $e.event -ceq "verified") { $t.doneAt = $e.at } }
        }
    }
    $since = $Now.ToUniversalTime().AddDays(-$script:HordeCardsChannelDoneDays)
    foreach ($t in $tasks.Values) {
        if ($t.lane -ceq "") { continue }
        if (-not $answer.lanes.ContainsKey($t.lane)) { $answer.lanes[$t.lane] = [pscustomobject]@{ open = 0; doneWeek = 0 } }
        $c = $answer.lanes[$t.lane]
        if ($script:HordeCardsChannelClosed -cnotcontains $t.state) { $c.open++ }
        if (($t.state -ceq "done" -or $t.state -ceq "verified") -and $null -ne $t.doneAt -and $t.doneAt -ge $since) { $c.doneWeek++ }
    }
    $answer.ok = $true
    return $answer
}

function Read-HordeCardsChannelCensus {
    # The sessions running and waiting on a person (runsFolder, in the header): { ok; reason; running;
    # waiting; skipped }. ONE RUN THAT DOES NOT READ SKIPS ONLY ITSELF, counted in skipped: a run.json
    # that was JSON null wiped the whole count (review of PR 244, 2026-10-14).
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][datetime]$Now)
    $answer = [pscustomobject]@{ ok = $false; reason = ""; running = 0; waiting = 0; skipped = 0 }
    if (-not [System.IO.Directory]::Exists($Path)) { $answer.reason = "there is no runs folder at " + $Path; return $answer }
    $recent = $Now.ToUniversalTime().AddHours(-$script:HordeCardsChannelRecentHours)
    try { $runs = @([System.IO.Directory]::GetDirectories($Path)) } catch { $answer.reason = "the runs folder " + $Path + " could not be read"; return $answer }
    foreach ($run in $runs) {
        try {
            $manifest = Join-Path $run "run.json"
            if (-not [System.IO.File]::Exists($manifest)) { continue }
            $m = ConvertFrom-Json -InputObject (Read-HordeSharedText -Path $manifest)
            if ($m -isnot [System.Management.Automation.PSCustomObject]) { $answer.skipped++; continue }
            $closed = $m.PSObject.Properties["closedAt"]
            if ($null -ne $closed -and "$($closed.Value)" -cne "") { continue }
            $sessions = Join-Path $run "sessions"
            if (-not [System.IO.Directory]::Exists($sessions)) { continue }
            foreach ($s in @([System.IO.Directory]::GetDirectories($sessions))) {
                $events = Join-Path $s "events.jsonl"
                $info = New-Object System.IO.FileInfo -ArgumentList $events
                if (-not $info.Exists -or $info.LastWriteTimeUtc -lt $recent) { continue }
                $last = Read-HordeCardsChannelLastLine -Path $events
                if ($last -ceq "") { continue }
                $event = ""
                try { $r = ConvertFrom-Json -InputObject $last } catch { continue }
                if ($r -isnot [System.Management.Automation.PSCustomObject]) { continue }
                $ev = $r.PSObject.Properties["event"]
                if ($null -ne $ev -and $ev.Value -is [string]) { $event = $ev.Value }
                if ($event -ceq "started" -or $event -ceq "progress") { $answer.running++ }
                elseif ($event -ceq "blocked") { $answer.waiting++ }
            }
        } catch { $answer.skipped++ }
    }
    $answer.ok = $true
    return $answer
}

function Read-HordeCardsChannelLastLine {
    # The last line that holds words of a file, read FROM ITS END, at most 64 KiB of it: the census asks
    # only that line, every 30 s, of every recent session (review of PR 244: each events file was read
    # whole). A last line longer than that is "" - not read, never half read. Throws if the file cannot
    # be read; the caller counts that run as skipped.
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = Open-HordeSharedStream -Path $Path
    try {
        $from = [long][System.Math]::Max(0, $stream.Length - $script:HordeCardsChannelTailBytes)
        [void]$stream.Seek($from, [System.IO.SeekOrigin]::Begin)
        $bytes = New-Object byte[] ($stream.Length - $from)
        $got = 0
        while ($got -lt $bytes.Length) { $n = $stream.Read($bytes, $got, $bytes.Length - $got); if ($n -le 0) { break }; $got += $n }
    } finally { $stream.Dispose() }
    $pieces = @(([System.Text.Encoding]::UTF8.GetString($bytes, 0, $got)) -split "\r?\n")
    # Read from the middle of the file, the first piece is the tail of a line, not a line.
    $start = $(if ($from -gt 0) { 1 } else { 0 })
    for ($i = $pieces.Count - 1; $i -ge $start; $i--) { if ($pieces[$i].Trim() -ne "") { return $pieces[$i] } }
    return ""
}

function New-HordeCardsChannelThrallCard {
    # The Thrall's card: its own status when it writes one, and the fleet at large from the lane cards
    # and the census. A lane is blocked when it says so; else waiting on the founder when its waiting on
    # line names him and does not open with "nothing"; else working.
    param([object[]]$Cards, $Census, [string]$StatusPath)
    $s = Read-HordeCardsChannelStatusText -Path $StatusPath
    $now = ""
    # WHOLE here, refused below, and only then cut (NO SECRET LEAVES THE MACHINE, in the header).
    if ($s.form -ceq "standard" -or $s.form -ceq "other") { $now = $(if ($s.keys.ContainsKey("doing")) { $s.keys["doing"] } else { @($s.first) -join " - " }) }
    $blocked = 0; $founder = New-Object System.Collections.ArrayList; $working = 0; $unknown = 0
    foreach ($c in @($Cards)) {
        if ($c.form -ceq "missing" -or $c.form -ceq "unreadable") { $unknown++ }
        elseif ($c.blocked -ceq "yes") { $blocked++ }
        elseif ($c.waitingOn -imatch 'founder' -and $c.waitingOn -inotmatch '\Anothing') { [void]$founder.Add($c.lane) }
        else { $working++ }
    }
    $refused = New-Object System.Collections.ArrayList
    $now = Protect-HordeCardsChannelField -Text $now -Field "now" -Refused $refused
    return [pscustomobject]([ordered]@{ asOf = $s.asOf; now = $now; hasStatus = ($s.form -ceq "standard" -or $s.form -ceq "other"); orcs = @($Cards).Count; working = $working; waitingFounder = $founder.Count
        blocked = $blocked; unknown = $unknown; waitingFounderLanes = @($founder.ToArray()); census = $(if ($Census.ok) { [pscustomobject]@{ running = $Census.running; waiting = $Census.waiting } } else { $null }); refused = @($refused.ToArray()) })
}

function ConvertTo-HordeCardsChannelValueText {
    # A value of a card as JSON text: a string, a whole number, true or false, null, a list or an object -
    # what New-HordeCardsChannel*Card make, nothing else.
    param($Value)
    if ($null -eq $Value) { return "null" }
    if ($Value -is [bool]) { return $(if ($Value) { "true" } else { "false" }) }
    if ($Value -is [int] -or $Value -is [long]) { return ("" + $Value) }
    if ($Value -is [string]) { return (ConvertTo-HordeCardsChannelJsonString $Value) }
    if ($Value -is [System.Management.Automation.PSCustomObject]) { return ("{" + ((@($Value.PSObject.Properties) | ForEach-Object { (ConvertTo-HordeCardsChannelJsonString $_.Name) + ":" + (ConvertTo-HordeCardsChannelValueText $_.Value) }) -join ",") + "}") }
    if ($Value -is [System.Collections.IEnumerable]) { return ("[" + ((@($Value) | ForEach-Object { ConvertTo-HordeCardsChannelValueText $_ }) -join ",") + "]") }
    return (ConvertTo-HordeCardsChannelJsonString ("" + $Value))
}

function New-HordeCardsChannelSnapshot {
    # What this machine's lanes say now, as the body of one envelope: { hash; body; cards; left; lines }.
    # -Budget: the largest body; cards are left out from the end until it fits (OUT, in the header).
    param($Context, [Parameter(Mandatory = $true)]$Settings, [Parameter(Mandatory = $true)]$Paths, [Parameter(Mandatory = $true)][datetime]$Now, [long]$Budget)
    $lines = New-Object System.Collections.ArrayList
    $folders = @([System.IO.Directory]::GetDirectories($Paths.lanes) | Sort-Object { (Split-Path -Leaf $_).ToLowerInvariant() })
    # A RETIRED LANE HAS NO CARD (F, after the merge of PR 244): a folder with status.retired.txt and no
    # status.txt is a lane that ended, and it leaves the phone as it leaves the panel - no card, not
    # counted on the Thrall's. A folder with neither file is still "no status file"; with both, the lane
    # came back and its status.txt stands. Passed over before lanesRead counts, or old lanes would push
    # live ones out of the folders read. The rule is fleet/StatusPanel.ps1's (Test-HordeFleetStatusRetired),
    # the one the panel uses, so the two cannot drift.
    $folders = @($folders | Where-Object { -not (Test-HordeFleetStatusRetired -Path $_) })
    if ($folders.Count -gt [int]$Settings.lanesRead) { [void]$lines.Add("" + ($folders.Count - [int]$Settings.lanesRead) + " lane folder(s) past the first " + $Settings.lanesRead + " were not read"); $folders = @($folders | Select-Object -First ([int]$Settings.lanesRead)) }
    $ledger = Read-HordeCardsChannelLedger -Path $Paths.ledger -Now $Now
    if (-not $ledger.ok) { [void]$lines.Add("the cards show no task counts: " + $ledger.reason) }
    elseif ($ledger.skipped -gt 0) { [void]$lines.Add("" + $ledger.skipped + " line(s) of the task ledger could not be read and were passed over") }
    $cards = New-Object System.Collections.ArrayList
    # What every card's age is worked out from besides its status file (below): the progress log and the
    # decisions list, read once for the snapshot, through the registry's readers (cached while unchanged).
    $actProgress = $null; $actQuestions = $null
    try {
        $orcPaths = Get-HordeOrcPaths -HordeHome (Get-HordeCardsChannelHome $Context)
        if ($orcPaths.ok) { $actProgress = Read-HordeOrcProgress -Path $orcPaths.progress -AreasPath $orcPaths.areas; $actQuestions = Read-HordeOrcQuestions -Root $orcPaths.decisions }
        else { [void]$lines.Add("the cards' ages are their status files' alone: " + $orcPaths.reason) }
    } catch { [void]$lines.Add("the cards' ages are their status files' alone: " + $_.Exception.Message) }
    # ONE ID IS ONE CARD: the phone finds a card by its machine and its id, so two cards of one id drew the
    # first twice and the second never (review of PR 244, 2026-10-14). The first folder by name keeps the
    # id; a later one gets the first free "lane-<place>", and both the card and the machine say why.
    $taken = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::Ordinal)
    $place = 0
    foreach ($f in $folders) {
        $place++
        $c = New-HordeCardsChannelLaneCard -Folder $f -Place $place
        if ($taken.ContainsKey($c.lane)) {
            $was = $c.lane
            $k = $place
            while ($taken.ContainsKey("lane-" + $k)) { $k++ }
            $c.lane = "lane-" + $k
            $why = New-Object System.Collections.ArrayList
            # Its own field, idNote, and not a note: the phone makes a card's note from its form alone
            # (relay/js/protocol.js, cardFormNote), so a reason put in the note never reached the founder
            # (F, review of PR 244), and a card can be both renamed and not in the standard form.
            $c.idNote = Protect-HordeCardsChannelField -Text ("Another lane folder here (" + $taken[$was] + ") gives the same id, " + $was + ", so this card has its own.") -Field "idNote" -Refused $why
            if ($why.Count -gt 0) { $c.refused = @(@($c.refused) + "idNote") }
            [void]$lines.Add("the lane folders " + $taken[$was] + " and " + (Split-Path -Leaf $f) + " both give the id " + $was + ": the card of " + (Split-Path -Leaf $f) + " is " + $c.lane + " on the phone")
        }
        $taken[$c.lane] = (Split-Path -Leaf $f)
        $count = $(if ($ledger.ok -and $ledger.lanes.ContainsKey($c.lane)) { $ledger.lanes[$c.lane] } elseif ($ledger.ok) { [pscustomobject]@{ open = 0; doneWeek = 0 } } else { $null })
        $c | Add-Member -NotePropertyName "tasksOpen" -NotePropertyValue $(if ($null -ne $count) { [int]$count.open } else { $null })
        $c | Add-Member -NotePropertyName "doneWeek" -NotePropertyValue $(if ($null -ne $count) { [int]$count.doneWeek } else { $null })
        # THE CARD'S AGE IS THE LANE'S LATEST ACTIVITY (C, 2026-10-15): the one derivation the dash's
        # Latest order uses (orcs/Registry.ps1, Get-HordeOrcLastActivity) - the newest of the status file's
        # write, the lane's newest progress entry and its newest question asked or answered - and which of
        # them it was, so a lane that forgot its status file but logs progress is not shown days old.
        # The lane is known by its folder's name and, when its id is one capital letter, by that letter; a
        # card renamed for a repeated id ("lane-3") is known by its folder alone, since its letter is not its own.
        $actLetter = $(if ("$($c.lane)" -cmatch '\A[A-Z]\z') { "$($c.lane)" } else { "" })
        $act = Get-HordeOrcLastActivity -Id (Split-Path -Leaf $f) -Letter $actLetter -StatusAt (ConvertFrom-HordeOrcTime $c.asOf) -Progress $actProgress -Questions $actQuestions
        if ($null -ne $act.at) { $c.asOf = $act.at }
        $c | Add-Member -NotePropertyName "asOfSource" -NotePropertyValue $act.source
        [void]$cards.Add($c)
        if (@($c.refused).Count -gt 0) { [void]$lines.Add("a card of " + (Split-Path -Leaf $f) + " holds what looks like a secret in " + (@($c.refused) -join ", ") + ": the phone is shown a notice in its place") }
    }
    $areas = Read-HordeCardsChannelAreas -Path $Paths.areas
    if ($areas.reason -cne "") { [void]$lines.Add($areas.reason) }
    $census = Read-HordeCardsChannelCensus -Path $Paths.runs -Now $Now
    if ($census.skipped -gt 0) { [void]$lines.Add("" + $census.skipped + " run(s) of " + $Paths.runs + " could not be read and were passed over in the count of sessions") }
    $thrall = New-HordeCardsChannelThrallCard -Cards @($cards.ToArray()) -Census $census -StatusPath $Paths.thrall
    $name = $(if ("$($Settings.machineName)" -cne "") { $Settings.machineName } else { [System.Environment]::MachineName })
    $nameRefused = New-Object System.Collections.ArrayList
    $name = Protect-HordeCardsChannelField -Text $name -Field "name" -Refused $nameRefused
    if ($nameRefused.Count -gt 0) { $name = "this machine" }
    # THE MAP IS HELD TO A QUARTER OF THE BUDGET (TOO LARGE FOR ONE ENVELOPE, in the header): it was never
    # cut, and 200 areas left no card and a body still too large to save (review of PR 244, 2026-10-14).
    $areaTexts = @(@($areas.areas) | ForEach-Object { ConvertTo-HordeCardsChannelValueText $_ })
    $areasKept = 0; $areaBytes = 2
    while ($areasKept -lt $areaTexts.Count -and $areaBytes + $areaTexts[$areasKept].Length + 1 -le [long]($Budget / 4)) { $areaBytes += $areaTexts[$areasKept].Length + 1; $areasKept++ }
    # Each card is written once; what follows only joins the texts.
    $cardTexts = @(@($cards.ToArray()) | ForEach-Object { ConvertTo-HordeCardsChannelValueText $_ })
    $thrallText = ConvertTo-HordeCardsChannelValueText $thrall
    # THE DASH (orcs/Registry.ps1): the one list of Orcs in his order, with what is derived of each, read
    # from the same lanes folder. It rides in this snapshot, beside the cards, until the phone moves to it
    # (design "Dash", PR 2); the cards stay as they are. Its notes go to this machine's lines, never to
    # the phone; a name or a domain that trips the secret refusal goes as the refusal's sentence.
    $dash = $null
    try { $dash = Get-HordeOrcDash -HordeHome (Get-HordeCardsChannelHome $Context) -Now $Now }
    catch { $dash = [pscustomobject]@{ ok = $false; reason = ("the dash could not be made: " + $_.Exception.Message); version = [long]0; orcs = @(); lines = @() } }
    if (-not $dash.ok) { [void]$lines.Add("the dash is empty: " + $dash.reason) }
    foreach ($l in @($dash.lines)) { [void]$lines.Add("dash: " + $l) }
    $dashDoc = ConvertTo-HordeOrcDashDocument -Dash $dash -Protect { param($Text, $Field) $no = New-Object System.Collections.ArrayList; return (Protect-HordeCardsChannelField -Text $Text -Field $Field -Refused $no) }
    $dashTexts = @(@($dashDoc.orcs) | ForEach-Object { ConvertTo-HordeCardsChannelValueText $_ })
    $dashHead = '{"v":' + $dashDoc.v + ',"ok":' + $(if ($dashDoc.ok) { "true" } else { "false" }) + ',"version":' + $dashDoc.version + ',"orcs":['
    $made = $Now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
    $build = {
        param([int]$CardsKept, [int]$AreasKept, [int]$DashKept)
        $content = '"name":' + (ConvertTo-HordeCardsChannelJsonString $name) + ',"thrall":' + $thrallText + ',"cards":[' + (@($cardTexts | Select-Object -First $CardsKept) -join ",") + '],"cardsLeftOut":' + ($cardTexts.Count - $CardsKept) + ',"areas":[' + (@($areaTexts | Select-Object -First $AreasKept) -join ",") + '],"areasLeftOut":' + ($areaTexts.Count - $AreasKept)
        $content = $content + ',"dash":' + $dashHead + (@($dashTexts | Select-Object -First $DashKept) -join ",") + '],"orcsLeftOut":' + ($dashTexts.Count - $DashKept) + '}'
        $h = ConvertTo-HordeRelayHex -Bytes (Get-HordeRelaySha256 -Bytes ([System.Text.Encoding]::ASCII.GetBytes($content)))
        return [pscustomobject]@{ hash = $h; body = ('{"v":1,"kind":"cards-snapshot","horde":"' + $Context.horde + '","machine":"' + $Context.signKeyId + '","snapshot":"' + $h + '","made":"' + $made + '",' + $content + '}') }
    }
    $cardsKept = $cardTexts.Count
    $dashKept = $dashTexts.Count
    while ($true) {
        $made1 = & $build $cardsKept $areasKept $dashKept
        if ($made1.body.Length -le $Budget) { break }
        # Cards first, from the end; with none left, the rest of the map; the dash last, from its end
        # (its back-burner first): an Orc is a line of at most a few hundred bytes, so 64 of them fit.
        if ($cardsKept -gt 0) { $cardsKept-- }
        elseif ($areasKept -gt 0) { $areasKept-- }
        elseif ($dashKept -gt 0) { $dashKept-- }
        else { break }
    }
    # THE MAP THEN FILLS THE ROOM THE CARDS LEAVE (F, review of PR 244: two small cards and 200 areas
    # made a body of 12815 of 47918 bytes, measured; test/test-relay-channel-cards.ps1, 8). Cards were cut
    # first, so what is left is less than the next card.
    if ($made1.body.Length -le $Budget) {
        while ($areasKept -lt $areaTexts.Count) {
            $more = & $build $cardsKept ($areasKept + 1) $dashKept
            if ($more.body.Length -gt $Budget) { break }
            $made1 = $more; $areasKept++
        }
    }
    $hash = $made1.hash; $body = $made1.body; $left = $cardTexts.Count - $cardsKept
    if ($left -gt 0) { [void]$lines.Add("" + $left + " card(s) did not fit one envelope and were left out; the phone is told how many") }
    if ($areasKept -lt $areaTexts.Count) { [void]$lines.Add("" + ($areaTexts.Count - $areasKept) + " area(s) of the map did not fit one envelope and were left out; on the phone their entries show only in the Thrall's stream") }
    if ($dashKept -lt $dashTexts.Count) { [void]$lines.Add("" + ($dashTexts.Count - $dashKept) + " Orc(s) of the dash did not fit one envelope and were left out; the phone is told how many") }
    return [pscustomobject]@{ hash = $hash; body = $body; cards = $cardsKept; left = $left; lines = @($lines.ToArray()) }
}

function Send-HordeCardsChannelPending {
    # Put the snapshot recorded and not yet taken, keeping only it (ONE ENVELOPE, REPLACED WHOLE, in the
    # header). "" when it was taken, else why not.
    param($Context, $Mine)
    if ($null -eq $Mine.pending) { return "" }
    $p = $Mine.pending
    $put = Send-HordeRelayChannelSaved -Context $Context -Saved $p -Mailbox (New-HordeRelayMailbox -Horde $Context.horde -Reader "phone") -KeepFrom ([long]$p.seq)
    if ($put.state -cne "known") { return $put.reason }
    $Mine.pending = $null
    return ""
}

function Invoke-HordeCardsChannelTick {
    # OUT, in the header: { lines; failed }.
    param($Context)
    if (-not $Context.state.ContainsKey("cards")) { $Context.state["cards"] = @{ pending = $null; sent = ""; lastLook = [datetime]::MinValue; said = @{} } }
    $mine = $Context.state["cards"]
    $once = {
        param([string]$Key, [string]$Line, [bool]$Failed)
        if ($mine.said.ContainsKey($Key) -and $mine.said[$Key] -ceq $Line) { return [pscustomobject]@{ lines = @(); failed = $Failed } }
        $mine.said[$Key] = $Line
        return [pscustomobject]@{ lines = @($Line); failed = $Failed }
    }
    # RECORDED ONCE, PUT UNTIL IT IS TAKEN: the same envelope, and no new snapshot while it waits.
    if ($null -ne $mine.pending) {
        $why = Send-HordeCardsChannelPending -Context $Context -Mine $mine
        if ($why -cne "") { return [pscustomobject]@{ lines = @("cards not delivered yet (a snapshot recorded and waiting): " + $why); failed = $true } }
    }
    $homeDir = Get-HordeCardsChannelHome $Context
    $s = Get-HordeModuleSettings -Declaration $script:HordeCardsChannelSettings -HordeHome $homeDir
    if ($s.state -ceq "refused") { return (& $once "settings" ("cards are stopped: " + (@($s.findings) -join " ")) $true) }
    $set = $s.values
    $now = [datetime]::UtcNow
    if ([long]$set.sendIntervalMs -gt 0 -and ($now - $mine.lastLook).TotalMilliseconds -lt [long]$set.sendIntervalMs) { return [pscustomobject]@{ lines = @(); failed = $false } }
    $paths = Get-HordeCardsChannelPaths -HordeHome $homeDir -Settings $set
    if (-not [System.IO.Directory]::Exists($paths.lanes)) { return (& $once "lanes" ("no cards yet: there is no lanes folder at " + $paths.lanes) $false) }
    $mine.said.Remove("lanes")
    $phones = Find-HordeRelayPhoneKeys -HordeHome $homeDir
    if ($phones.state -cne "known") { return [pscustomobject]@{ lines = @("no cards sent: " + $phones.reason); failed = $true } }
    $keys = @($phones.value)
    if ($keys.Count -eq 0) { return (& $once "phones" "no cards sent: no phone identity key of this horde is trusted yet" $false) }
    $mine.said.Remove("phones")
    $limit = (Get-HordeRelayEnvelopeLimits).recipients
    if ($keys.Count -gt $limit) { $keys = @($keys | Select-Object -First $limit) }
    $mine.lastLook = $now
    try { $snap = New-HordeCardsChannelSnapshot -Context $Context -Settings $set -Paths $paths -Now $now -Budget (Get-HordeRelayChannelBodyBudget -Context $Context -Recipients $keys.Count) }
    catch { return (& $once "read" ("no cards sent: the lanes at " + $paths.lanes + " could not be read: " + $_.Exception.Message) $false) }
    $said = New-Object System.Collections.ArrayList
    foreach ($l in @($snap.lines)) { $r = & $once ("line:" + $l) $l $false; foreach ($x in @($r.lines)) { [void]$said.Add($x) } }
    # SENT WHEN IT CHANGED: the same snapshot for the same phone keys is not sent again.
    $sentAs = $snap.hash + "|" + (@($keys | ForEach-Object { $_.agreeKeyId }) -join ",")
    if ($sentAs -ceq $mine.sent) { return [pscustomobject]@{ lines = @($said.ToArray()); failed = $false } }
    $saved = Save-HordeRelayChannelEnvelope -Context $Context -Channel "cards" -Kind "snapshot" -Body ([System.Text.Encoding]::ASCII.GetBytes($snap.body)) -Recipients @($keys | ForEach-Object { , ([byte[]]$_.public) })
    # Said once while it stays the same: a save refused every 30 s wrote a fresh line each time (review of PR 244).
    if ($saved.state -cne "known") { $r = & $once "save" ("no cards sent: " + $saved.reason) $true; return [pscustomobject]@{ lines = @(@($said.ToArray()) + @($r.lines)); failed = $true } }
    $mine.said.Remove("save")
    $mine.pending = $saved.value
    $mine.sent = $sentAs
    $what = "cards of " + $snap.cards + " lane(s) and the Thrall for " + $keys.Count + " phone key(s), as " + $saved.value.key
    $why = Send-HordeCardsChannelPending -Context $Context -Mine $mine
    if ($why -cne "") { [void]$said.Add($what + " recorded; not delivered yet: " + $why); return [pscustomobject]@{ lines = @($said.ToArray()); failed = $true } }
    [void]$said.Add($what + " sent")
    return [pscustomobject]@{ lines = @($said.ToArray()); failed = $false }
}

function Invoke-HordeCardsChannelAccept {
    # MACHINE TO PHONE ONLY (in the header): nothing is ever taken in.
    param($Context, $Item)
    return [pscustomobject]@{ outcome = "refused"; reason = "the cards channel takes nothing in: it only sends the fleet's cards to the phone" }
}

$null = Register-HordeRelayChannel -Folder $script:HordeCardsChannelFolder -Name "cards" -Kinds @() -Senders "founder" `
    -Accept { param($Context, $Item) return (Invoke-HordeCardsChannelAccept -Context $Context -Item $Item) } `
    -Tick { param($Context) return (Invoke-HordeCardsChannelTick -Context $Context) }
