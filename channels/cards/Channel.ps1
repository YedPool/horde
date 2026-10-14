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
#                     blocked: and waiting on: lines (waiting on: may be missing). Read by THIS file and
#                     not by fleet/StatusPanel.ps1, whose record is exactly six lines: every lane file on
#                     the founder's machine had a seventh, waiting on:, on 2026-10-13, so that reader
#                     would show none of them.
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
# WHAT A CARD SAYS (OUT, below): the lane's id (its orc letter, else its folder's name), its name, the
# time its status file was last written (asOf: the phone shows its age), now, last done, waiting on,
# blocked yes or no, and from the ledger the tasks open and done in the last 7 days. A status file in
# another form still gets a card: its first lines as now, its waiting on line, and form "other", which
# the phone says. A file that is missing or cannot be read gets a card that says so - never no card.
#
# NO SECRET LEAVES THE MACHINE. Every text that goes out is put through core/Secrets.ps1's refusal, the
# one the log's entries get. A text that trips it is replaced by a fixed sentence, and the card is still
# sent, with the field's name in its refused list: never the text, never what tripped it.
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
#     many (cardsLeftOut). Each text is at most 300 characters, so 64 lanes fit any relay this runs on.
#   - NO LANES FOLDER IS "NOTHING YET": nothing is sent, and it is said once.
#   - MACHINE TO PHONE ONLY: the channel takes nothing in.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\JsonText.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\ModuleSettings.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\Home.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\Secrets.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\ReadShared.ps1")

$script:HordeCardsChannelFolder = $PSScriptRoot
$script:HordeCardsChannelSettings = New-HordeModuleSettings -Module "relay-cards" -Settings @(
    @{ name = "lanesFolder"; kind = "folder"; default = ""; what = "The folder of lane folders, each with its status.txt, as an absolute path; empty means progress\lanes under Horde's home." },
    @{ name = "ledgerFile"; kind = "folder"; default = ""; what = "The fleet's task ledger, as an absolute path; empty means progress\tasks.jsonl under Horde's home." },
    @{ name = "areaLanesFile"; kind = "folder"; default = ""; what = "Which lanes each area of the progress log belongs to, as an absolute path; empty means progress\area-lanes.json under Horde's home." },
    @{ name = "runsFolder"; kind = "folder"; default = ""; what = "The fleet's runs, for the count of sessions running, as an absolute path; empty means progress\runs under Horde's home." },
    @{ name = "thrallStatusFile"; kind = "folder"; default = ""; what = "The Thrall's own status file, as an absolute path; empty means progress\thrall-status.txt under Horde's home." },
    @{ name = "machineName"; kind = "text"; default = ""; min = 0; max = 64; what = "The name each card gives its machine; empty means this computer's name." },
    @{ name = "sendIntervalMs"; kind = "whole"; default = 30000; min = 0; max = 3600000; what = "The shortest time between two looks at the lanes, in milliseconds." },
    # 64: the most lanes read, as fleet/StatusPanel.ps1 reads; the rest are counted.
    @{ name = "lanesRead"; kind = "whole"; default = 64; min = 1; max = 256; what = "The most lane folders read; the rest are counted and said." }
)
$script:HordeCardsChannelTextChars = 300
$script:HordeCardsChannelStatusBytes = 16384
$script:HordeCardsChannelLedgerBytes = 33554432
$script:HordeCardsChannelAreasMost = 200
$script:HordeCardsChannelRecentHours = 24
$script:HordeCardsChannelDoneDays = 7
$script:HordeCardsChannelSecretWords = "Not shown: this line looks like it holds a secret, so it stays at the machine."
$script:HordeCardsChannelLanePattern = '\A[A-Za-z0-9][A-Za-z0-9 ._-]{0,31}\z'
$script:HordeCardsChannelOrcPattern = '\A[A-Z][A-Z0-9]{0,3}\z'
$script:HordeCardsChannelStandardKeys = @("orc", "lane", "doing", "finished", "blocked")
$script:HordeCardsChannelClosed = @("done", "verified", "dropped", "superseded")

function Get-HordeCardsChannelSettingsDeclaration { return $script:HordeCardsChannelSettings }

function Get-HordeCardsChannelHome {
    param($Context)
    if ("$($Context.hordeHome)" -ne "") { return $Context.hordeHome }
    return (Get-HordeHome)
}

function Get-HordeCardsChannelPaths {
    # Every source this home reads (WHAT IT READS, in the header): a setting, or its place under the home.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)]$Settings)
    $under = { param([string]$Set, [string]$Leaf) if ($Set -cne "") { return $Set }; return [System.IO.Path]::Combine($HordeHome, "progress", $Leaf) }
    return [pscustomobject]@{
        lanes = (& $under $Settings.lanesFolder "lanes"); ledger = (& $under $Settings.ledgerFile "tasks.jsonl"); areas = (& $under $Settings.areaLanesFile "area-lanes.json")
        runs = (& $under $Settings.runsFolder "runs"); thrall = (& $under $Settings.thrallStatusFile "thrall-status.txt") }
}

function ConvertTo-HordeCardsChannelJsonString {
    # A JSON string of -Text in printable ASCII (as channels/progress writes its entries): one byte a
    # character, so the envelope's size is measured exactly.
    param([AllowEmptyString()][string]$Text)
    return ('"' + [regex]::Replace($Text, '[^\x20\x21\x23-\x5B\x5D-\x7E]', { param($m) '\u' + ([int][char]$m.Value).ToString("x4") }) + '"')
}

function Get-HordeCardsChannelPlain {
    # A text as a card holds it: control characters as spaces, trimmed, and at most 300 characters - a
    # card is a glance, and the whole story is the lane's stream.
    param([AllowEmptyString()][string]$Text)
    $t = ([regex]::Replace($Text, '\p{Cc}', ' ')).Trim()
    if ($t.Length -gt $script:HordeCardsChannelTextChars) { $t = $t.Substring(0, $script:HordeCardsChannelTextChars - 3).TrimEnd() + "..." }
    return $t
}

function Read-HordeCardsChannelStatusText {
    # What a lane's status file says: { form; lines } - form "standard", "other", "missing" or
    # "unreadable" (with why in reason), lines a table of its "key: value" lines by key in lower case,
    # first holds its first lines that hold words, header aside.
    param([Parameter(Mandatory = $true)][string]$Path)
    $out = [pscustomobject]@{ form = "missing"; reason = ""; keys = @{}; first = @(); asOf = "" }
    try {
        $info = New-Object System.IO.FileInfo -ArgumentList $Path
        if (-not $info.Exists) { return $out }
        $out.asOf = $info.LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
        if ($info.Length -gt $script:HordeCardsChannelStatusBytes) { $out.form = "unreadable"; $out.reason = "it is " + $info.Length + " bytes, far more than a status"; return $out }
        $text = Read-HordeSharedText -Path $Path
    } catch { $out.form = "unreadable"; $out.reason = "it could not be read"; return $out }
    $lines = @($text -split "\r?\n" | Where-Object { $_.Trim() -ne "" })
    $keys = @{}
    $first = New-Object System.Collections.ArrayList
    foreach ($line in $lines) {
        $m = [regex]::Match($line, '\A\s*([A-Za-z][A-Za-z ]{0,20}?)\s*:\s*(.*)\z')
        if ($m.Success) { $k = $m.Groups[1].Value.ToLowerInvariant(); if (-not $keys.ContainsKey($k)) { $keys[$k] = $m.Groups[2].Value.Trim() } }
        if ($line.Trim() -cne "horde-orc-status 1" -and $first.Count -lt 2) { [void]$first.Add($line.Trim()) }
    }
    $out.keys = $keys
    $out.first = @($first.ToArray())
    $standard = ($lines.Count -gt 0 -and $lines[0].Trim() -ceq "horde-orc-status 1")
    foreach ($k in $script:HordeCardsChannelStandardKeys) { if (-not $keys.ContainsKey($k)) { $standard = $false } }
    $out.form = $(if ($standard) { "standard" } else { "other" })
    return $out
}

function Protect-HordeCardsChannelField {
    # NO SECRET LEAVES THE MACHINE (the header): the text, or the fixed sentence in its place, and the
    # field's name added to -Refused.
    param([AllowEmptyString()][string]$Text, [string]$Field, [System.Collections.ArrayList]$Refused)
    if ((Find-HordeSecretKind -Text $Text) -cne "") { [void]$Refused.Add($Field); return $script:HordeCardsChannelSecretWords }
    return $Text
}

function New-HordeCardsChannelLaneCard {
    # One lane's card from its folder (WHAT A CARD SAYS, in the header): { lane; name; form; asOf; now;
    # lastDone; waitingOn; blocked; blockedText; note; refused }.
    param([Parameter(Mandatory = $true)][string]$Folder)
    $leaf = Split-Path -Leaf $Folder
    $s = Read-HordeCardsChannelStatusText -Path (Join-Path $Folder "status.txt")
    $k = $s.keys
    $get = { param($name) if ($k.ContainsKey($name)) { return (Get-HordeCardsChannelPlain $k[$name]) }; return "" }
    $orc = & $get "orc"
    if ($orc -cnotmatch $script:HordeCardsChannelOrcPattern) {
        # Another form may still say whose lane it is: "LANE: stt-cpu-bench (Orc I)".
        $orc = ""
        foreach ($v in @($k.Values) + @($s.first)) { $m = [regex]::Match("$v", '\(Orc ([A-Z][A-Z0-9]{0,3})\)'); if ($m.Success) { $orc = $m.Groups[1].Value; break } }
    }
    $lane = $(if ($orc -cne "") { $orc } elseif ($leaf -cmatch $script:HordeCardsChannelLanePattern) { $leaf } else { "lane" })
    # "thrall" is the Thrall card's id on every page of the phone (surfaces/pwa/page/lane-card.js): no lane takes it.
    if ($lane -ceq "thrall") { $lane = "lane" }
    $name = & $get "lane"
    if ($name -ceq "") { $name = Get-HordeCardsChannelPlain $leaf }
    $card = [ordered]@{ lane = $lane; name = $name; form = $s.form; asOf = $s.asOf; now = ""; lastDone = ""; waitingOn = ""; blocked = ""; blockedText = ""; note = "" }
    if ($s.form -ceq "missing") { $card.note = "This lane has no status file." }
    elseif ($s.form -ceq "unreadable") { $card.note = "This lane's status file could not be read: " + $s.reason + "." }
    else {
        $card.now = & $get "doing"
        if ($s.form -ceq "other" -and $card.now -ceq "") { $card.now = Get-HordeCardsChannelPlain (@($s.first) -join " - ") }
        $card.lastDone = & $get "finished"
        $card.waitingOn = & $get "waiting on"
        $b = & $get "blocked"
        if ($b -cne "") {
            if ($b -imatch '\Ano\b') { $card.blocked = "no" } else { $card.blocked = "yes"; $card.blockedText = [regex]::Replace($b, '\A(?i:yes)\b\s*[-:,.]?\s*', '') }
        }
        if ($s.form -ceq "other") { $card.note = "This lane's status file is not in the standard form; what it says is shown as it stands." }
    }
    $refused = New-Object System.Collections.ArrayList
    foreach ($f in @("lane", "name", "now", "lastDone", "waitingOn", "blockedText")) { $card[$f] = Protect-HordeCardsChannelField -Text $card[$f] -Field $f -Refused $refused }
    # A refused id cannot name a stream: the lane is then its folder's place in the list, said plainly.
    if (@($refused) -ccontains "lane") { $card.lane = "lane" }
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
        foreach ($name in @("ts", "task", "event", "lane", "to")) { $pp = $r.PSObject.Properties[$name]; $field[$name] = $(if ($null -ne $pp) { $pp.Value } else { $null }) }
        $when = ConvertFrom-HordeCardsChannelTime $field["ts"]
        if ($null -eq $when -or "$($field['task'])" -ceq "" -or "$($field['event'])" -ceq "") { $answer.skipped++; continue }
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

function Read-HordeCardsChannelAreas {
    # The area-to-lane map (areaLanesFile, in the header): { ok; reason; areas; refused } - areas a list
    # of { area; lanes } in the file's order. No file is an empty map and says so; a file that does not
    # hold together is an empty map, said, never half of one. An area or a lane that trips the secret
    # refusal is left out and counted.
    param([Parameter(Mandatory = $true)][string]$Path)
    $answer = [pscustomobject]@{ ok = $false; reason = ""; areas = @(); refused = 0 }
    if (-not [System.IO.File]::Exists($Path)) { $answer.reason = "there is no area-to-lane map at " + $Path + ", so the log's entries that name no lane show only in the Thrall's stream"; return $answer }
    try { $text = Read-HordeSharedText -Path $Path } catch { $answer.reason = "the area-to-lane map " + $Path + " could not be read"; return $answer }
    $why = "the area-to-lane map " + $Path + " does not hold together"
    if (@(Find-HordeJsonDuplicateKey -Text $text).Count -gt 0) { $answer.reason = $why + ": a member is repeated"; return $answer }
    try { $m = ConvertFrom-Json -InputObject $text } catch { $answer.reason = $why + ": it is not JSON"; return $answer }
    if ($m -isnot [System.Management.Automation.PSCustomObject] -or $null -eq $m.PSObject.Properties["v"] -or $m.v -ne 1 -or $null -eq $m.PSObject.Properties["areas"] -or $m.areas -isnot [System.Management.Automation.PSCustomObject]) { $answer.reason = $why + ": it is not {""v"":1,""areas"":{...}}"; return $answer }
    $list = New-Object System.Collections.ArrayList
    foreach ($p in @($m.areas.PSObject.Properties)) {
        if ($list.Count -ge $script:HordeCardsChannelAreasMost) { $answer.reason = "the area-to-lane map holds more than " + $script:HordeCardsChannelAreasMost + " areas; the rest are left out"; break }
        $area = "$($p.Name)"
        if ($p.Value -isnot [string] -or $area.Trim() -eq "" -or $area.Length -gt 60 -or $area -cmatch '\p{Cc}') { $answer.reason = $why + ": the area '" + (Get-HordeCardsChannelPlain $area) + "' is not 1 to 60 plain characters naming lanes"; $answer.areas = @(); return $answer }
        $lanes = @($p.Value.Split([char]',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
        if ($lanes.Count -eq 0 -or @($lanes | Where-Object { $_ -cnotmatch $script:HordeCardsChannelLanePattern }).Count -gt 0) { $answer.reason = $why + ": the lanes of '" + (Get-HordeCardsChannelPlain $area) + "' are not lane ids separated by commas"; $answer.areas = @(); return $answer }
        if ((Find-HordeSecretKind -Text ($area + " " + ($lanes -join ","))) -cne "") { $answer.refused++; continue }
        [void]$list.Add([pscustomobject]@{ area = $area; lanes = $lanes })
    }
    $answer.ok = $true
    $answer.areas = @($list.ToArray())
    return $answer
}

function Read-HordeCardsChannelCensus {
    # The sessions running and waiting on a person (runsFolder, in the header): { ok; reason; running;
    # waiting }. Only the last bytes of each events file are read: its last line is all that is asked.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][datetime]$Now)
    $answer = [pscustomobject]@{ ok = $false; reason = ""; running = 0; waiting = 0 }
    if (-not [System.IO.Directory]::Exists($Path)) { $answer.reason = "there is no runs folder at " + $Path; return $answer }
    $recent = $Now.ToUniversalTime().AddHours(-$script:HordeCardsChannelRecentHours)
    try {
        foreach ($run in @([System.IO.Directory]::GetDirectories($Path))) {
            $manifest = Join-Path $run "run.json"
            if (-not [System.IO.File]::Exists($manifest)) { continue }
            try { $m = ConvertFrom-Json -InputObject (Read-HordeSharedText -Path $manifest) } catch { continue }
            $closed = $m.PSObject.Properties["closedAt"]
            if ($null -ne $closed -and "$($closed.Value)" -cne "") { continue }
            $sessions = Join-Path $run "sessions"
            if (-not [System.IO.Directory]::Exists($sessions)) { continue }
            foreach ($s in @([System.IO.Directory]::GetDirectories($sessions))) {
                $events = Join-Path $s "events.jsonl"
                $info = New-Object System.IO.FileInfo -ArgumentList $events
                if (-not $info.Exists -or $info.LastWriteTimeUtc -lt $recent) { continue }
                $last = @((Read-HordeSharedText -Path $events) -split "\r?\n" | Where-Object { $_.Trim() -ne "" } | Select-Object -Last 1)
                if ($last.Count -eq 0) { continue }
                $event = ""
                try { $ev = (ConvertFrom-Json -InputObject $last[0]).PSObject.Properties["event"]; if ($null -ne $ev) { $event = "$($ev.Value)" } } catch { continue }
                if ($event -ceq "started" -or $event -ceq "progress") { $answer.running++ }
                elseif ($event -ceq "blocked") { $answer.waiting++ }
            }
        }
    } catch { $answer.reason = "the runs folder " + $Path + " could not be read"; return $answer }
    $answer.ok = $true
    return $answer
}

function New-HordeCardsChannelThrallCard {
    # The Thrall's card: its own status when it writes one, and the fleet at large from the lane cards
    # and the census. A lane is blocked when it says so; else waiting on the founder when its waiting on
    # line names him and does not open with "nothing"; else working.
    param([object[]]$Cards, $Census, [string]$StatusPath)
    $s = Read-HordeCardsChannelStatusText -Path $StatusPath
    $now = ""
    if ($s.form -ceq "standard" -or $s.form -ceq "other") { $now = $(if ($s.keys.ContainsKey("doing")) { Get-HordeCardsChannelPlain $s.keys["doing"] } else { Get-HordeCardsChannelPlain (@($s.first) -join " - ") }) }
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
    if ($folders.Count -gt [int]$Settings.lanesRead) { [void]$lines.Add("" + ($folders.Count - [int]$Settings.lanesRead) + " lane folder(s) past the first " + $Settings.lanesRead + " were not read"); $folders = @($folders | Select-Object -First ([int]$Settings.lanesRead)) }
    $ledger = Read-HordeCardsChannelLedger -Path $Paths.ledger -Now $Now
    if (-not $ledger.ok) { [void]$lines.Add("the cards show no task counts: " + $ledger.reason) }
    elseif ($ledger.skipped -gt 0) { [void]$lines.Add("" + $ledger.skipped + " line(s) of the task ledger could not be read and were passed over") }
    $cards = New-Object System.Collections.ArrayList
    foreach ($f in $folders) {
        $c = New-HordeCardsChannelLaneCard -Folder $f
        $count = $(if ($ledger.ok -and $ledger.lanes.ContainsKey($c.lane)) { $ledger.lanes[$c.lane] } elseif ($ledger.ok) { [pscustomobject]@{ open = 0; doneWeek = 0 } } else { $null })
        $c | Add-Member -NotePropertyName "tasksOpen" -NotePropertyValue $(if ($null -ne $count) { [int]$count.open } else { $null })
        $c | Add-Member -NotePropertyName "doneWeek" -NotePropertyValue $(if ($null -ne $count) { [int]$count.doneWeek } else { $null })
        [void]$cards.Add($c)
        if (@($c.refused).Count -gt 0) { [void]$lines.Add("a card of " + (Split-Path -Leaf $f) + " holds what looks like a secret in " + (@($c.refused) -join ", ") + ": the phone is shown a notice in its place") }
    }
    $areas = Read-HordeCardsChannelAreas -Path $Paths.areas
    if ($areas.reason -cne "") { [void]$lines.Add($areas.reason) }
    $census = Read-HordeCardsChannelCensus -Path $Paths.runs -Now $Now
    $thrall = New-HordeCardsChannelThrallCard -Cards @($cards.ToArray()) -Census $census -StatusPath $Paths.thrall
    $name = $(if ("$($Settings.machineName)" -cne "") { $Settings.machineName } else { [System.Environment]::MachineName })
    $nameRefused = New-Object System.Collections.ArrayList
    $name = Protect-HordeCardsChannelField -Text (Get-HordeCardsChannelPlain $name) -Field "name" -Refused $nameRefused
    if ($nameRefused.Count -gt 0) { $name = "this machine" }
    $areasText = ConvertTo-HordeCardsChannelValueText @($areas.areas)
    if (@($areas.areas).Count -eq 0) { $areasText = "[]" }
    $kept = New-Object System.Collections.ArrayList -ArgumentList (, @($cards.ToArray()))
    $left = 0
    while ($true) {
        $cardsText = $(if ($kept.Count -eq 0) { "[]" } else { "[" + ((@($kept.ToArray()) | ForEach-Object { ConvertTo-HordeCardsChannelValueText $_ }) -join ",") + "]" })
        $content = '"name":' + (ConvertTo-HordeCardsChannelJsonString $name) + ',"thrall":' + (ConvertTo-HordeCardsChannelValueText $thrall) + ',"cards":' + $cardsText + ',"cardsLeftOut":' + $left + ',"areas":' + $areasText
        $hash = ConvertTo-HordeRelayHex -Bytes (Get-HordeRelaySha256 -Bytes ([System.Text.Encoding]::ASCII.GetBytes($content)))
        $body = '{"v":1,"kind":"cards-snapshot","horde":"' + $Context.horde + '","machine":"' + $Context.signKeyId + '","snapshot":"' + $hash + '","made":"' + $Now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture) + '",' + $content + '}'
        if ($body.Length -le $Budget -or $kept.Count -eq 0) { break }
        $kept.RemoveAt($kept.Count - 1)
        $left++
    }
    if ($left -gt 0) { [void]$lines.Add("" + $left + " card(s) did not fit one envelope and were left out; the phone is told how many") }
    return [pscustomobject]@{ hash = $hash; body = $body; cards = $kept.Count; left = $left; lines = @($lines.ToArray()) }
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
    if ($saved.state -cne "known") { return [pscustomobject]@{ lines = @(@($said.ToArray()) + @("no cards sent: " + $saved.reason)); failed = $true } }
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
