# core/FleetWork - the fleet-work record: is one line one event that may be kept (schema/fleet-work-event.v1),
# and what do the lines of a record say now?
#
# THE ONE JOB of this file is to READ: one line's text to { state; event; findings }, and a whole
# record's text to the open waits and each lane's last status. Every function is PURE: text in, answer
# out. It opens no file but Horde's own schema, reads no clock and no environment. core/FleetWorkStore.ps1
# is the only writer, and it writes only what this file has read. NOTHING HERE OR THERE SENDS AN EVENT
# ANYWHERE: no network, no transport, no remote call.
#
# WHY A RECORD OF EVENTS AND NOT A FILE OF STATE. A status file replaced whole on every write keeps no
# history, and a wait that is only words in a "doing" line cannot be timed: a fleet analyst found four
# of nine lanes saying they were waiting while their blocked line said no (2026-10-07). Each change is
# therefore one line, appended and never changed; what is true NOW is folded from the lines, here.
#
# THE LINE: { schemaVersion; kind; lane; id; time; values }, flat, on one line. The kinds, and what
# their values hold, are the schema's. A line that ends another is a NEW line naming the other's id:
# a wait-end's values.ends. The current status of a lane is its LAST status line in the file - the
# file's order, not the times written in it, because the file's order is the order the writer took the
# file in, and two machines' clocks need not agree.
#
# THE ANSWER for one line: { state; event; findings }, as core/Finding.ps1 answers:
#   state     "read" or "refused";
#   event     the parsed event when read, $null when refused - never a part of it;
#   findings  every reason it was refused, each naming WHERE, never repeating the value.
#
# THE CHECKS, IN THIS ORDER, and why the order (core/Finding.ps1's, for the same reasons):
#   1. size: more than $script:HordeFleetWorkMaxLength characters is refused before anything walks it;
#   2. one line: a raw line break in the text would be two lines in the file;
#   3. ASCII: the record is ASCII; any other character is written as a \u escape;
#   4. JSON the parser can read, an object. Its own message is not passed on: it quotes the text;
#   5. CONTENT, over every text and every member name: what is not text, a credential, customer data,
#      conversation - core/Finding.ps1's Find-HordeFindingContentProblems, reused, not written again.
#      Before the schema, because the schema's findings repeat what they found;
#   6. a key repeated in one object (core/JsonText.ps1);
#   7. schema/fleet-work-event.v1: the line's shape, then values against the definition <kind>Values.
#      The subset of draft-07 core/Schema.ps1 implements has no oneOf, so the choice by kind is here;
#   8. what the schema cannot say: a time that does not exist, a wait that starts after its line was
#      written, an end that names itself.
#
# THE FOLD (Read-HordeFleetWorkLog) never refuses a whole record for one bad line: a record is appended
# to by many writers over weeks, and one bad line must not hide the rest. Each line that does not read
# is skipped and named by its number. A LAST LINE NOT ENDED BY A LINE BREAK is set apart as torn: it is
# being written, or its writer stopped mid-write, and it is neither read nor counted as broken. (The
# writer starts the next event on a line of its own, so a torn line becomes an ended broken line.)
# An id seen a second time, an end that names no open wait (or one already ended, or a wait in another
# lane) are named and change nothing. ITS LIMIT: an end written before its wait - the wait's writer
# retried late - closes nothing; the file's order is the record's.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path $PSScriptRoot "Schema.ps1")
. (Join-Path $PSScriptRoot "JsonText.ps1")
. (Join-Path $PSScriptRoot "Finding.ps1")

$script:HordeFleetWorkSchemaName = "fleet-work-event.v1"
# The longest line read. A status with every text at its bound, escaped, comes to about 900
# characters; a wait about 700. This leaves room for \u escapes and no more.
$script:HordeFleetWorkMaxLength = 2048

function ConvertFrom-HordeFleetWorkTime {
    # A time of the schema's form as a UTC DateTime, or $null for one that does not exist (February 30th).
    param([string]$Stamp)
    $parsedTime = [DateTime]::MinValue
    $forms = [string[]]@("yyyy-MM-dd'T'HH:mm'Z'", "yyyy-MM-dd'T'HH:mm:ss'Z'", "yyyy-MM-dd'T'HH:mm:ss.f'Z'", "yyyy-MM-dd'T'HH:mm:ss.ff'Z'", "yyyy-MM-dd'T'HH:mm:ss.fff'Z'")
    $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
    if ([DateTime]::TryParseExact($Stamp, $forms, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsedTime)) { return $parsedTime }
    return $null
}

function Test-HordeFleetWorkRules {
    # Findings for what schema/fleet-work-event.v1 cannot say, on an event that has passed it.
    param([Parameter(Mandatory = $true)]$FleetEvent)
    $out = New-Object System.Collections.ArrayList
    $e = Get-HordeObjectByKey $FleetEvent
    $v = Get-HordeObjectByKey $e["values"]
    $written = ConvertFrom-HordeFleetWorkTime -Stamp ("" + $e["time"])
    if ($null -eq $written) { [void]$out.Add("time is not a date and time that exists") }
    if ($e["kind"] -ceq "wait") {
        $since = ConvertFrom-HordeFleetWorkTime -Stamp ("" + $v["since"])
        if ($null -eq $since) { [void]$out.Add("values.since is not a date and time that exists") }
        elseif ($null -ne $written -and $since -gt $written) { [void]$out.Add("values.since is after the line's time: a wait cannot start after it was written") }
    }
    if ($e["kind"] -ceq "wait-end" -and ("" + $v["ends"]) -ceq ("" + $e["id"])) { [void]$out.Add("values.ends names the line's own id: an end ends another line, not itself") }
    # send: a step inside the send cannot take longer than the send. mail: a message does not answer
    # itself. restart: no more sessions repaired than were found.
    if ($e["kind"] -ceq "send") {
        foreach ($step in @("queuedMs", "wokenMs", "takenMs")) {
            if ($v.ContainsKey($step) -and $v[$step] -gt $v["ranMs"]) { [void]$out.Add("values." + $step + " is longer than values.ranMs: a step of a send cannot take longer than the send") }
        }
    }
    if ($e["kind"] -ceq "mail" -and $v.ContainsKey("answers") -and ("" + $v["answers"]) -ceq ("" + $v["mailId"])) { [void]$out.Add("values.answers names the message itself: a message answers another, not itself") }
    if ($e["kind"] -ceq "restart" -and $v["repaired"] -gt $v["found"]) { [void]$out.Add("values.repaired is more than values.found: only a session that was found can be repaired") }
    return @($out)
}

function New-HordeFleetWorkAnswer {
    param([string]$State, $FleetEvent, [string[]]$Problems)
    return [pscustomobject]@{ state = $State; event = $FleetEvent; findings = [string[]]@($Problems) }
}

function Read-HordeFleetWorkEventText {
    # One event from one line's TEXT, without its line break: { state; event; findings }. PURE. ANY
    # problem refuses, and a refusal carries no event. The checks and their order are in the header.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    if ($Text.Length -gt $script:HordeFleetWorkMaxLength) { return (New-HordeFleetWorkAnswer -State "refused" -FleetEvent $null -Problems @("the line is longer than " + $script:HordeFleetWorkMaxLength + " characters")) }
    if ($Text.IndexOfAny([char[]]@([char]10, [char]13)) -ge 0) { return (New-HordeFleetWorkAnswer -State "refused" -FleetEvent $null -Problems @("the text holds a line break: an event is one line")) }
    $wide = [regex]::Match($Text, '[^\x00-\x7F]')
    if ($wide.Success) {
        return (New-HordeFleetWorkAnswer -State "refused" -FleetEvent $null -Problems @("the line holds the character U+" + ([int][char]$wide.Value).ToString("X4") + ", which is not ASCII. Write the character as a \u escape"))
    }
    $parsedValue = $null
    # ConvertFrom-HordeJson (T-0366): under 7 bare ConvertFrom-Json read $.time as a [datetime], and every line was
    # refused as not fitting schema/fleet-work-event.v1.
    try { $parsedValue = ConvertFrom-HordeJson -Text $Text } catch { $parsedValue = $null }
    if ($null -eq $parsedValue -or $parsedValue -isnot [System.Management.Automation.PSCustomObject]) {
        return (New-HordeFleetWorkAnswer -State "refused" -FleetEvent $null -Problems @("the line is not a JSON object the parser can read"))
    }
    $content = @(Find-HordeFindingContentProblems -Value $parsedValue -Path "the event")
    if ($content.Count -gt 0) { return (New-HordeFleetWorkAnswer -State "refused" -FleetEvent $null -Problems $content) }
    $twice = @(Find-HordeJsonDuplicateKey -Text $Text)
    if ($twice.Count -gt 0) { return (New-HordeFleetWorkAnswer -State "refused" -FleetEvent $null -Problems @($twice | ForEach-Object { "the line says one thing twice: " + $_ })) }
    $schema = Get-HordeSchema -Name $script:HordeFleetWorkSchemaName
    $unfit = @(Test-HordeSchema -Value $parsedValue -Schema $schema)
    if ($unfit.Count -eq 0) {
        # The kind is one of the closed list here, so its definition exists.
        $definition = (Get-HordeObjectByKey (Get-HordeObjectByKey $schema)["definitions"])[$parsedValue.kind + "Values"]
        $unfit = @(Test-HordeSchema -Value $parsedValue.values -Schema $definition -Path '$.values' -Root $schema)
    }
    if ($unfit.Count -gt 0) { return (New-HordeFleetWorkAnswer -State "refused" -FleetEvent $null -Problems @($unfit | ForEach-Object { "the line does not fit schema/" + $script:HordeFleetWorkSchemaName + ": " + $_ })) }
    $broken = @(Test-HordeFleetWorkRules -FleetEvent $parsedValue)
    if ($broken.Count -gt 0) { return (New-HordeFleetWorkAnswer -State "refused" -FleetEvent $null -Problems $broken) }
    return (New-HordeFleetWorkAnswer -State "read" -FleetEvent $parsedValue -Problems @())
}

function Read-HordeFleetWorkLog {
    # A whole record's TEXT folded into what it says now. PURE. Returns { state = "read"; lines; skipped;
    # tornTail; ended; waits; statuses; findings }:
    #   lines     how many lines read as events;  skipped  how many ended lines did not;
    #   tornTail  the last line was not ended by a line break, and was set apart;
    #   ended     how many waits an end closed;
    #   waits     the open waits, oldest first: { id; lane; session; waitingOn; waitingOnName; since; endsWhen; time };
    #   statuses  each lane's last status, by lane: { lane; id; time; session; doing; finished; blocked };
    #   findings  every line skipped or ignored, by its number, and why.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    $findings = New-Object System.Collections.ArrayList
    $parts = $Text.Split([char]10)
    $torn = $false
    $last = $parts.Length - 1
    # Split leaves "" after a final line break; anything else there is a line its writer has not ended.
    if ($parts[$last].TrimEnd([char]13) -ne "") { $torn = $true; [void]$findings.Add("the last line is not ended by a line break: it is being written, or its writer stopped; it is not read") }
    $seen = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([System.StringComparer]::Ordinal)
    $open = New-Object System.Collections.Specialized.OrderedDictionary
    $endedIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $statuses = @{}
    $read = 0; $skipped = 0; $ended = 0
    for ($n = 0; $n -lt $last; $n++) {
        $lineText = $parts[$n].TrimEnd([char]13)
        $number = $n + 1
        if ($lineText -eq "") { continue }
        $a = Read-HordeFleetWorkEventText -Text $lineText
        if ($a.state -cne "read") { $skipped++; [void]$findings.Add("line " + $number + " is skipped: " + (@($a.findings) -join "; ")); continue }
        $read++
        $ev = $a.event
        if ($seen.ContainsKey($ev.id)) { [void]$findings.Add("line " + $number + " repeats the id of line " + $seen[$ev.id] + "; it is ignored"); continue }
        $seen[$ev.id] = $number
        if ($ev.kind -ceq "wait") {
            $open[$ev.id] = [pscustomobject]@{ id = $ev.id; lane = $ev.lane; session = $ev.values.session; waitingOn = $ev.values.waitingOn; waitingOnName = $(if ($ev.values.PSObject.Properties["waitingOnName"]) { $ev.values.waitingOnName } else { "" }); since = $ev.values.since; endsWhen = $ev.values.endsWhen; time = $ev.time }
        }
        elseif ($ev.kind -ceq "wait-end") {
            $target = $ev.values.ends
            if ($open.Contains($target)) {
                if ($open[$target].lane -cne $ev.lane) { [void]$findings.Add("line " + $number + " ends a wait of another lane; the wait stays open"); continue }
                $open.Remove($target); [void]$endedIds.Add($target); $ended++
            }
            elseif ($endedIds.Contains($target)) { [void]$findings.Add("line " + $number + " ends a wait already ended; it changes nothing") }
            else { [void]$findings.Add("line " + $number + " names no open wait; it changes nothing") }
        }
        elseif ($ev.kind -ceq "status") {
            $statuses[$ev.lane] = [pscustomobject]@{ lane = $ev.lane; id = $ev.id; time = $ev.time; session = $ev.values.session; doing = $ev.values.doing; finished = $ev.values.finished; blocked = $ev.values.blocked }
        }
    }
    $waits = @($open.Values | Sort-Object -Property @{ Expression = { ConvertFrom-HordeFleetWorkTime -Stamp $_.since } }, id)
    $byLane = @($statuses.Keys | Sort-Object | ForEach-Object { $statuses[$_] })
    return [pscustomobject]@{ state = "read"; lines = $read; skipped = $skipped; tornTail = $torn; ended = $ended; waits = $waits; statuses = $byLane; findings = [string[]]@($findings) }
}
