# orcs/Registry.ps1 - the Orc registry: ONE list of Orcs, in the founder's priority order, that the
# phone's Dash and every other view read. The one module that reads and writes it.
#
# WHY (design note "Dash: one list of Orcs", 2026-10-15, approved by C and M; this is its PR 1). Priority,
# order, name, domain and back-burner are decided by people and must be one source of truth; whether an
# Orc is working, how many of its questions wait on the founder and how many sessions it has open are
# facts of the fleet and are DERIVED each time, never stored, so they cannot go stale.
#
# WHAT IS STORED: a write-once journal of records, schema/orc-registry-event.v1, at
# <HORDE_HOME>\orcs\registry\ - one file per record, named by its sequence number, written by
# decisions/Store.ps1, the store the decisions list already trusts. NOT one registry.jsonl, as the
# design note first said: lines appended to one file give no way for exactly one of two writers to take
# record N + 1, and that is what "refused as stale" rests on. In the decisions store a record's name is
# its place in the order and the operating system lets exactly one move to a name succeed, so a write
# drawn from version N is written as N + 1 and a writer that finds N + 1 taken KNOWS the list moved.
# The registry's VERSION is its last sequence number (0 when it is empty).
#   orc-registered   {id, letter, name}   an Orc joins the list, at the END of the main list
#   orc-named        {id, name}           its name (by default "Orc <letter>")
#   orc-domain-set   {id, domain}         its one-line domain, at most 80 printable ASCII, stored exactly
#   orcs-ordered     {order, backBurner}  the WHOLE list in one record, so a reorder is never half done
#   orc-retired      {id, reason}         it leaves the list: by hand (stays off), or its lane was
#                                          retired in the lanes folder (registered again if it comes back)
#   orc-tier-set     {id, tier}           its tier, 1 or 2 (Set-HordeOrcTier; null on the dash until set)
# The current list is the fold of the records in order (Read-HordeOrcRegistry). A record that does not
# match the schema is reported by its sequence number and changes nothing; a record of a kind this
# version does not know is set aside and reported once for its kind (a later version wrote it).
#
# WHAT IS DERIVED (Get-HordeOrcDash), from four sources, each read and never written:
#   lanes       the lanes folder of the cards channel's own setting (relay-cards lanesFolder,
#               channels/cards/Sources.ps1), read with the fleet's one status reader
#               (fleet/StatusPanel.ps1): each lane folder is one lane, its id the folder's name.
#   questions   the decisions list (decisions/Operations.ps1): an open question whose turn is the
#               founder's is "open" for the lane of the Orc that asked it, by THE SAME LANE RULE the
#               decisions page uses (decisions/page/list.js, laneOf; Get-HordeOrcQuestionLane below
#               mirrors it, and test/test-orcs-registry.ps1 runs both on one table of names).
#   sessions    the fleet's session records (one JSON file per session, with its label, parent, owner,
#               lastSeen and retired). An open session (not retired) labelled with the Orc's letter is
#               the Orc's own; every other open session is a WARG, and is the Orc's when its parent
#               chain leads to the Orc's own session (Get-HordeOrcSessionLines says the rule, and that a
#               Warg no Orc can be told for is counted under none and said, never guessed). sessions is
#               the Orc's own and its Wargs; wargsActive the Wargs that moved within workingMinutes,
#               wargsInactive the open ones that did not (the founder, 2026-10-15: "Wargs: x/y").
#   progress    the progress log (the progress channel's own setting, channels/progress/Settings.ps1),
#               for the latest activity only (below).
#   the clock   working means moved within workingMinutes (15).
# LATEST ACTIVITY (lastActivityAt, the founder's "Latest" order, 2026-10-15): the newest of three times,
# each taken as it is written, UTC: the status file's last write (the work and status moving); the ts of
# the newest progress entry of the Orc's lane (its lane member is the Orc's id or letter, or its area
# maps to it by the cards channel's area map); and the newest question of its lane, by the same lane
# rule, asked (when it was added) or answered (when the founder last said something under it). Session
# movement is not one of them: it is what working means, not what the Orc did. An Orc none of them
# speaks for has no time ($null) and sorts last.
# STATUS, the rule C and M set (2026-10-15):
#   blocked   the lane's status file has a "waiting on:" line, OR one of its open questions blocks all
#             of its work (Blocks = all). A waiting-on line that begins "nothing" or "none" says it waits
#             on nothing (the live fleet writes "waiting on: nothing; ...") and does not block - the same
#             reading the Thrall's card gives it (channels/cards).
#   working   not blocked, and its status file or one of its sessions moved within the last 15 minutes.
#   idle      neither.
# The age goes with the word whenever the Orc is not working ("idle 3 h", "blocked 40 min"), with the
# moment it counts from (since), so idle is never a guess: blocked counts from its oldest cause (the
# status file's last write for a waiting-on line, the question's adding for a question), idle from the
# last time the status file or a session moved. Ages are in steps (5 minutes under an hour, hours under
# two days, then days) so the phone's snapshot changes when the words do, not every minute.
#
# WHICH LANES ARE ORCS. A lane folder with a status.txt. Not: a folder with no status.txt (a working
# folder, not an Orc), a folder the fleet retired (fleet/StatusPanel.ps1, Test-HordeFleetStatusRetired),
# a folder whose status names the letter M (the Thrall's own letter: the fleet analyst is the Thrall's
# helper, never an Orc card), and a folder named in the setting notOrcs. Each passed-over folder is said.
# A LANE SEEN BUT NOT YET REGISTERED is shown at the END of the main list, marked registered false, and
# is written into the registry by the next write (any write starts by registering what the lanes folder
# shows, and taking off what the fleet retired). Reads never write: the cards channel only reads, and a
# list asked for at a prompt changes nothing.
#
# EVERY WRITE CARRIES THE VERSION IT WAS DRAWN FROM, or none. With one, it is refused as STALE unless the
# registry is still at that version - so the founder's phone, which always sends one (PR 3), never
# overwrites a change made elsewhere. Without one (a command typed at a prompt that names the change
# whole), it is judged against the list as it is at the moment it is written, and a writer that loses
# the race judges it again against the winner's list.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Tristate.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Home.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\JsonText.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Schema.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\ModuleSettings.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\ReadShared.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Secrets.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "fleet\StatusPanel.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "channels\cards\Sources.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "channels\progress\Settings.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "decisions\Operations.ps1")

$script:HordeOrcSettings = New-HordeModuleSettings -Module "orcs" -Settings @(
    @{ name = "sessionsFolder"; kind = "folder"; default = ""; what = "The fleet's session records, one JSON file per session, as an absolute path; empty means progress\sessions under Horde's home." },
    @{ name = "notOrcs"; kind = "text"; default = ""; min = 0; max = 400; what = "Lane folders that are not Orcs, by folder name, separated by commas; they get no card on Dash." },
    @{ name = "workingMinutes"; kind = "whole"; default = 15; min = 1; max = 1440; what = "How recently a lane's status file or one of its sessions must have moved for it to be working, in minutes." }
)
# The kinds of record, each with the definition of its data in the schema. A kind this table does not
# hold is a later version's (the header).
$script:HordeOrcKinds = @("orc-registered", "orc-named", "orc-domain-set", "orcs-ordered", "orc-retired", "orc-tier-set")
$script:HordeOrcIdPattern = '\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z'
$script:HordeOrcDomainMost = 80
$script:HordeOrcNameMost = 40
$script:HordeOrcPrintable = '\A[\x20-\x7E]*\z'
$script:HordeOrcByPattern = '\A[A-Za-z0-9][A-Za-z0-9 ._()-]{0,63}\z'
# THE THRALL'S LETTER: a lane whose status names it is the Thrall's or its helper's, never an Orc card.
$script:HordeOrcThrallLetter = "M"
# How many times a write without a version is judged again after losing the race for its place. Each
# loss is another writer's record landing first, so 50 is fifty writes in the moment of one command.
$script:HordeOrcRaceTries = 50
# The cache of the open questions by lane, keyed on what the decisions store folder looks like: the
# list costs seconds to work out (decisions/Operations.ps1, KNOWN COST) and the cards channel asks
# every 30 seconds. Any new record changes the key.
$script:HordeOrcQuestionCache = @{ key = ""; value = $null }
# The same for the progress log, keyed on its length and last write and the area map's.
$script:HordeOrcProgressCache = @{ key = ""; value = $null }
# How much of the end of the progress log is read for each Orc's newest entry: 8 MB, far past the
# newest entry of every lane of a fleet that writes a few tens of entries a day (2 KB each at most).
$script:HordeOrcProgressTailBytes = 8388608

function Get-HordeOrcSettingsDeclaration { return $script:HordeOrcSettings }
function Get-HordeOrcKinds { return @($script:HordeOrcKinds) }

function Get-HordeOrcPaths {
    # Where everything the registry reads is, for -HordeHome: { ok; reason; registry; decisions; lanes;
    # areas; progress; sessions; notOrcs; workingMinutes; lanesRead }. The lanes folder and the area map
    # are the cards channel's settings, the progress log the progress channel's, so each is one setting
    # read by both. A settings file that is refused is ok $false, in its own words - never the defaults in
    # its place.
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    $cards = Get-HordeModuleSettings -Declaration (Get-HordeCardsChannelSettingsDeclaration) -HordeHome $HordeHome
    if ($cards.state -ceq "refused") { return [pscustomobject]@{ ok = $false; reason = (@($cards.findings) -join " ") } }
    $cardPaths = Get-HordeCardsChannelPaths -HordeHome $HordeHome -Settings $cards.values
    $prog = Get-HordeModuleSettings -Declaration (Get-HordeProgressChannelSettingsDeclaration) -HordeHome $HordeHome
    if ($prog.state -ceq "refused") { return [pscustomobject]@{ ok = $false; reason = (@($prog.findings) -join " ") } }
    $own = Get-HordeModuleSettings -Declaration $script:HordeOrcSettings -HordeHome $HordeHome
    if ($own.state -ceq "refused") { return [pscustomobject]@{ ok = $false; reason = (@($own.findings) -join " ") } }
    $sessions = "$($own.values.sessionsFolder)"
    if ($sessions -ceq "") { $sessions = [System.IO.Path]::Combine($HordeHome, "progress", "sessions") }
    $not = @("$($own.values.notOrcs)".Split([char]',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
    return [pscustomobject]@{
        ok = $true; reason = ""
        registry = [System.IO.Path]::Combine($HordeHome, "orcs", "registry")
        decisions = [System.IO.Path]::Combine($HordeHome, "store", "decisions")
        lanes = $cardPaths.lanes; areas = $cardPaths.areas; progress = (Get-HordeProgressChannelFilePath -HordeHome $HordeHome -Setting "$($prog.values.progressFile)")
        sessions = $sessions; notOrcs = $not; workingMinutes = [int]$own.values.workingMinutes; lanesRead = [int]$cards.values.lanesRead
    }
}

# --- THE FOLD -----------------------------------------------------------------------------------------

function New-HordeOrcState {
    # An empty registry: version 0, nobody on the list.
    return [pscustomobject]@{
        state = "ok"; reason = ""; version = [long]0
        orcs = (New-Object 'System.Collections.Specialized.OrderedDictionary' ([System.StringComparer]::Ordinal))
        main = (New-Object System.Collections.ArrayList); back = (New-Object System.Collections.ArrayList)
        unreadable = (New-Object System.Collections.ArrayList); ignored = (New-Object System.Collections.ArrayList)
        later = @{}; strays = @()
    }
}

function Get-HordeOrcSchema {
    if ($null -eq $script:HordeOrcSchemaRead) { $script:HordeOrcSchemaRead = Get-HordeSchema -Name "orc-registry-event.v1" }
    return $script:HordeOrcSchemaRead
}
$script:HordeOrcSchemaRead = $null

function Test-HordeOrcRecord {
    # Why -Record (parsed) is not an orc-registry-event.v1 record of -Sequence, as findings; none when it is.
    # A kind this version does not know passes here: only its envelope is checked (the header).
    param($Record, [long]$Sequence)
    $schema = Get-HordeOrcSchema
    $found = @(Test-HordeSchema -Value $Record -Schema $schema)
    if ($found.Count -gt 0) { return $found }
    if ([long]$Record.sequence -ne $Sequence) { return @("its sequence " + $Record.sequence + " is not its place in the order, " + $Sequence) }
    if ($script:HordeOrcKinds -cnotcontains "$($Record.kind)") { return @() }
    $def = $schema.definitions.PSObject.Properties["$($Record.kind)"].Value
    return @(Test-HordeSchema -Value $Record.data -Schema $def -Path '$.data' -Root $schema)
}

function Remove-HordeOrcFromLists {
    param($State, [string]$Id)
    while ($State.main -ccontains $Id) { $State.main.Remove($Id) }
    while ($State.back -ccontains $Id) { $State.back.Remove($Id) }
}

function Add-HordeOrcRecordToState {
    # Apply one checked record to -State. Returns "" when it applied, else why it changed nothing (the
    # record stays a fact; it is reported as ignored).
    param($State, $Record)
    $d = $Record.data
    switch -CaseSensitive ("$($Record.kind)") {
        "orc-registered" {
            $id = "$($d.id)"
            if ($State.orcs.Contains($id)) {
                $o = $State.orcs[$id]
                if (-not $o.retired) { return ("it registers " + $id + ", which is on the list already") }
                if ("$($o.retiredBy)" -ceq "hand") { return ("it registers " + $id + ", which was taken off by hand and stays off") }
                # A lane the fleet retired, come back: on the list again, at the end, with what was decided before.
                # The stored letter is a fallback only: the view reads the lane's own letter while it is seen.
                $o.retired = $false; $o.retiredBy = ""; $o.letter = "$($d.letter)"
                [void]$State.main.Add($id)
                return ""
            }
            $State.orcs[$id] = [pscustomobject]@{ id = $id; letter = "$($d.letter)"; name = "$($d.name)"; domain = ""; tier = $null; named = $false; retired = $false; retiredBy = "" }
            [void]$State.main.Add($id)
            return ""
        }
        "orcs-ordered" {
            # Checked whole when it was written (Get-HordeOrcRecordFor); read, it is applied to the ids
            # still on the list, and an id it does not name keeps its place at the end, never lost.
            $active = @($State.orcs.Values | Where-Object { -not $_.retired } | ForEach-Object { $_.id })
            $main = New-Object System.Collections.ArrayList; $back = New-Object System.Collections.ArrayList
            foreach ($x in @($d.order)) { if ($active -ccontains "$x" -and $main -cnotcontains "$x") { [void]$main.Add("$x") } }
            foreach ($x in @($d.backBurner)) { if ($active -ccontains "$x" -and $main -cnotcontains "$x" -and $back -cnotcontains "$x") { [void]$back.Add("$x") } }
            foreach ($x in @($State.main)) { if ($main -cnotcontains $x -and $back -cnotcontains $x) { [void]$main.Add($x) } }
            foreach ($x in @($State.back)) { if ($main -cnotcontains $x -and $back -cnotcontains $x) { [void]$back.Add($x) } }
            $State.main = $main; $State.back = $back
            return ""
        }
        default {
            $id = "$($d.id)"
            if (-not $State.orcs.Contains($id) -or $State.orcs[$id].retired) { return ("it names " + $id + ", which is not on the list") }
            $o = $State.orcs[$id]
            if ($Record.kind -ceq "orc-named") { $o.name = "$($d.name)"; $o.named = $true }
            elseif ($Record.kind -ceq "orc-domain-set") { $o.domain = "$($d.domain)" }
            elseif ($Record.kind -ceq "orc-tier-set") { $o.tier = [int]$d.tier }
            else { $o.retired = $true; $o.retiredBy = "$($d.reason)"; Remove-HordeOrcFromLists -State $State -Id $id }
            return ""
        }
    }
}

function Read-HordeOrcRegistry {
    # The registry at -Root folded to its current state: { state: ok | unknown; reason; version; orcs
    # (id -> { id; letter; name; domain; retired; retiredBy }); main; back; unreadable; ignored; later;
    # strays }. An absent registry is an empty one at version 0. A damaged record is in unreadable with
    # its sequence and reason, and the fold goes on past it.
    param([Parameter(Mandatory = $true)][string]$Root)
    $s = New-HordeOrcState
    $loaded = Get-HordeDecisionRecords -Root $Root
    if ($loaded.state -ceq "unknown") { $s.state = "unknown"; $s.reason = $loaded.reason; return $s }
    $s.version = [long]$loaded.last
    $s.strays = @($loaded.strays)
    foreach ($r in @($loaded.records)) {
        if ($r.kind -cne "ok") { [void]$s.unreadable.Add([pscustomobject]@{ sequence = [long]$r.sequence; reason = "$($r.reason)" }); continue }
        $why = @(Test-HordeOrcRecord -Record $r.data -Sequence ([long]$r.sequence))
        if ($why.Count -gt 0) { [void]$s.unreadable.Add([pscustomobject]@{ sequence = [long]$r.sequence; reason = ("it is not an orc-registry-event.v1 record: " + (@($why | Select-Object -First 3) -join "; ")) }); continue }
        $kind = "$($r.data.kind)"
        if ($script:HordeOrcKinds -cnotcontains $kind) {
            if (-not $s.later.ContainsKey($kind)) { $s.later[$kind] = 0 }
            $s.later[$kind] = [int]$s.later[$kind] + 1
            continue
        }
        $not = Add-HordeOrcRecordToState -State $s -Record $r.data
        if ($not -ne "") { [void]$s.ignored.Add([pscustomobject]@{ sequence = [long]$r.sequence; reason = $not }) }
    }
    return $s
}

# --- THE FLEET'S FACTS --------------------------------------------------------------------------------

function ConvertFrom-HordeOrcTime {
    # An ISO time with a zone (Z or +hh:mm) as UTC, or $null.
    param($Value)
    if ($Value -isnot [string] -or $Value -cnotmatch '(Z|[+-][0-9]{2}:[0-9]{2})\z') { return $null }
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse($Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) { return $parsed.ToUniversalTime() }
    return $null
}

function Read-HordeOrcLanes {
    # The lanes that are Orcs (WHICH LANES ARE ORCS, in the header), in folder-name order: { ok; reason;
    # lanes; fleetRetired; lines }. Each lane { id; letter; statusAt; waitingOn }: statusAt the status
    # file's last write (UTC), waitingOn its seventh line as the fleet's reader gives it ("" for none).
    # fleetRetired: the ids of folders the fleet retired. No lanes folder is ok with no lanes, said.
    param([Parameter(Mandatory = $true)][string]$Folder, [string[]]$NotOrcs = @(), [int]$Most = 64)
    $out = [pscustomobject]@{ ok = $true; reason = ""; lanes = @(); fleetRetired = @(); notOrcs = @($NotOrcs); lines = @() }
    if (-not [System.IO.Directory]::Exists($Folder)) { $out.lines = @("there is no lanes folder at " + $Folder + ", so no Orc is seen"); return $out }
    try { $dirs = @([System.IO.Directory]::GetDirectories($Folder) | Sort-Object { (Split-Path -Leaf $_).ToLowerInvariant() }) }
    catch { $out.ok = $false; $out.reason = "the lanes folder " + $Folder + " could not be listed: " + $_.Exception.Message; return $out }
    $lanes = New-Object System.Collections.ArrayList; $retired = New-Object System.Collections.ArrayList; $lines = New-Object System.Collections.ArrayList
    # ONE LETTER, ONE ORC: the folders are read in name order, so the first to claim a letter keeps it.
    $claimed = @{}
    foreach ($dir in $dirs) {
        $leaf = Split-Path -Leaf $dir
        if (Test-HordeFleetStatusRetired -Path $dir) { [void]$retired.Add($leaf); continue }
        if ($leaf -cnotmatch $script:HordeOrcIdPattern) { [void]$lines.Add("the lane folder '" + $leaf + "' is not named as a lane id is (letters, digits, dot, dash, underscore), so it is no Orc"); continue }
        if ($NotOrcs -ccontains $leaf) { continue }
        $file = Join-Path $dir "status.txt"
        if (-not [System.IO.File]::Exists($file)) { continue }
        if ($lanes.Count -ge $Most) { [void]$lines.Add("lane folders past the first " + $Most + " were not read"); break }
        $at = $null
        try { $at = (New-Object System.IO.FileInfo -ArgumentList $file).LastWriteTimeUtc } catch { $at = $null }
        $rec = Read-HordeFleetStatusFolder -Path $dir
        $letter = ""; $waiting = ""
        if ($rec.written) {
            $letter = "$($rec.orc)"
            if ($null -ne $rec.PSObject.Properties["waitingOn"]) { $waiting = "$($rec.waitingOn)" }
        } else { [void]$lines.Add("the status file of " + $leaf + " is not in the standard form (" + (@($rec.problems) -join "; ") + "), so its letter and waiting-on line are not read") }
        if ($letter -ceq $script:HordeOrcThrallLetter) { continue }
        # A LETTER ANOTHER FOLDER ALREADY CLAIMS is not this lane's (review of PR 319): it would count that Orc's
        # questions, sessions and Wargs twice. The later folder keeps no letter, names the one that has it
        # (letterTakenBy), and the clash is said; nothing of the letter's is counted for it.
        $takenBy = ""
        if ($letter -ne "") {
            if ($claimed.ContainsKey($letter)) { $takenBy = $claimed[$letter]; [void]$lines.Add("the lane folders " + $takenBy + " and " + $leaf + " both claim the letter " + $letter + ": " + $takenBy + " keeps it, and " + $leaf + " is shown with none until one of them changes"); $letter = "" }
            else { $claimed[$letter] = $leaf }
        }
        [void]$lanes.Add([pscustomobject]@{ id = $leaf; letter = $letter; statusAt = $at; waitingOn = $waiting; letterTakenBy = $takenBy })
    }
    $out.lanes = @($lanes.ToArray()); $out.fleetRetired = @($retired.ToArray()); $out.lines = @($lines.ToArray())
    return $out
}

function Read-HordeOrcSessions {
    # The fleet's session records: { ok; reason; sessions; skipped } - each { id; label; parent; owner;
    # retired; at }, at the session's lastSeen, else its record's last write (UTC). The file's name is the
    # session's id; only label, parent, owner, lastSeen and retired are read, so nothing here depends on
    # which agent ran the session. Retired records are kept: a Warg's parent may be an Orc session that
    # was retired since, and its label still says whose the Warg is.
    # RETIRED IS READ BY TRUTHINESS, as the fleet's own readers do (core/Roles.ps1): no field is live.
    # One record that does not read skips only itself, counted in skipped.
    param([Parameter(Mandatory = $true)][string]$Folder)
    $out = [pscustomobject]@{ ok = $false; reason = ""; sessions = @(); skipped = 0 }
    if (-not [System.IO.Directory]::Exists($Folder)) { $out.reason = "there is no sessions folder at " + $Folder; return $out }
    try { $files = @([System.IO.Directory]::GetFiles($Folder, "*.json")) } catch { $out.reason = "the sessions folder " + $Folder + " could not be listed"; return $out }
    $list = New-Object System.Collections.ArrayList
    $text = { param($r, [string]$Name) $p = $r.PSObject.Properties[$Name]; if ($null -ne $p -and $p.Value -is [string]) { return $p.Value }; return "" }
    foreach ($f in $files) {
        try {
            $r = ConvertFrom-HordeJson (Read-HordeSharedText -Path $f)
            if ($r -isnot [System.Management.Automation.PSCustomObject]) { $out.skipped++; continue }
            $ret = $r.PSObject.Properties["retired"]
            $at = ConvertFrom-HordeOrcTime (& $text $r "lastSeen")
            if ($null -eq $at) { $at = [System.IO.File]::GetLastWriteTimeUtc($f) }
            [void]$list.Add([pscustomobject]@{ id = [System.IO.Path]::GetFileNameWithoutExtension($f); label = (& $text $r "label"); parent = (& $text $r "parent"); owner = (& $text $r "owner")
                retired = ($null -ne $ret -and [bool]$ret.Value); at = $at })
        } catch { $out.skipped++ }
    }
    $out.ok = $true; $out.sessions = @($list.ToArray())
    return $out
}

function Get-HordeOrcSessionLines {
    # Whose each open session is (WHOSE A SESSION IS, below): { own; wargs; unknown } - own a table letter
    # -> the times its Orc's own sessions moved; wargs a table letter -> the times its Wargs moved;
    # unknown how many open Wargs no Orc can be told for (the Thrall's own are not counted there).
    # WHOSE A SESSION IS. A session not retired whose label is one capital letter is that Orc's own (or
    # the Thrall's, M). Every other open session is a Warg, and its Orc is found by its parent: the
    # parent's record, and up through its parents, to the first whose label is one capital letter. With
    # no parent record to follow, the record's own owner, when it is one capital letter: the fleet wrote
    # it there. Else its Orc cannot be told, and it is counted under none - never guessed from its label.
    param([object[]]$Sessions = @())
    $byId = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($s in @($Sessions)) { $byId[$s.id] = $s }
    $own = @{}; $wargs = @{}; $unknown = 0
    foreach ($s in @($Sessions)) {
        if ($s.retired) { continue }
        if ($s.label -cmatch '\A[A-Z]\z') { if (-not $own.ContainsKey($s.label)) { $own[$s.label] = New-Object System.Collections.ArrayList }; [void]$own[$s.label].Add($s.at); continue }
        $letter = ""; $cur = $s
        for ($i = 0; $i -lt 8 -and $cur.parent -ne "" -and $byId.ContainsKey($cur.parent); $i++) {
            $cur = $byId[$cur.parent]
            if ($cur.label -cmatch '\A[A-Z]\z') { $letter = $cur.label; break }
        }
        if ($letter -eq "" -and ($s.parent -eq "" -or -not $byId.ContainsKey($s.parent)) -and $s.owner -cmatch '\A[A-Z]\z') { $letter = $s.owner }
        if ($letter -eq "") { $unknown++; continue }
        if (-not $wargs.ContainsKey($letter)) { $wargs[$letter] = New-Object System.Collections.ArrayList }
        [void]$wargs[$letter].Add($s.at)
    }
    return [pscustomobject]@{ own = $own; wargs = $wargs; unknown = $unknown }
}

function Get-HordeOrcQuestionLane {
    # THE LANE A QUESTION IS OF, read from who asked: decisions/page/list.js's laneOf, mirrored line for
    # line so the phone's cards and the PC's counts cannot disagree (test/test-orcs-registry.ps1 runs both
    # on one table). "Orc C" is C and "Orc F1" is F1; else one capital letter standing alone is that
    # letter ("B (by hand)"); anybody else - and the keeper's own M - is the Thrall's lane, "thrall".
    param($AskedBy)
    $name = $(if ($AskedBy -is [string]) { $AskedBy } else { "" })
    $orc = [regex]::Match($name, '\AOrc ([A-Z][0-9]{0,3})(?![A-Za-z0-9])')
    if ($orc.Success) { return $orc.Groups[1].Value }
    $letter = "M"
    $m1 = [regex]::Match($name, '\AOrc ([A-Z])(?![A-Za-z])')
    if ($m1.Success) { $letter = $m1.Groups[1].Value }
    else { $m2 = [regex]::Match($name, '\A([A-Z])(?![A-Za-z])'); if ($m2.Success) { $letter = $m2.Groups[1].Value } }
    if ($letter -ceq "M") { return "thrall" }
    return $letter
}

function Test-HordeOrcLaneOfLetter {
    # Is -Lane (a question's lane, or a session's label) the Orc of -Letter's: the letter itself, or the
    # letter and up to three digits (its sub-sessions)?
    param([string]$Lane, [string]$Letter)
    if ($Letter -cnotmatch '\A[A-Z]\z') { return $false }
    return ($Lane -cmatch ('\A' + $Letter + '[0-9]{0,3}\z'))
}

function ConvertTo-HordeOrcJsText {
    # What JavaScript's String(x || "") makes of a parsed JSON value, for the members entryLanes reads:
    # nothing, false, 0 and "" are ""; a list is its items joined by commas; true is "true".
    param($Value)
    if ($null -eq $Value -or ($Value -is [string] -and $Value -eq "")) { return "" }
    if ($Value -is [bool]) { return $(if ($Value) { "true" } else { "" }) }
    if ($Value -is [System.Collections.IList]) { return (@($Value | ForEach-Object { ConvertTo-HordeOrcJsText $_ }) -join ",") }
    if ($Value -is [System.Management.Automation.PSCustomObject]) { return "[object Object]" }
    if ((Test-HordeSchemaIsNumber $Value) -and [double]$Value -eq 0) { return "" }
    return [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0}", $Value)
}

function Get-HordeOrcEntryLanes {
    # THE LANES A PROGRESS ENTRY BELONGS TO: relay/js/protocol.js's entryLanes, mirrored line for line so
    # the phone's lane streams and the PC's latest activity cannot disagree (test/test-orcs-registry.ps1
    # runs both on one table). The entry's own lane member split on commas and trimmed, when it names any
    # - it wins over its area; else the lanes the area map gives its area (trimmed, any letter case); else
    # none. An entry tagged "E,F" is each of E's and F's. -Areas is the map as
    # Read-HordeCardsChannelAreas reads it: { area; lanes } in the file's order, the first match taken.
    param($Entry, [object[]]$Areas = @())
    $get = { param($n) if ($null -eq $Entry) { return $null }; $p = $Entry.PSObject.Properties[$n]; if ($null -eq $p) { return $null }; return $p.Value }
    $own = @((ConvertTo-HordeOrcJsText (& $get "lane")).Split([char]',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
    if ($own.Count -gt 0) { return $own }
    $area = (ConvertTo-HordeOrcJsText (& $get "area")).Trim().ToLowerInvariant()
    if ($area -eq "") { return @() }
    foreach ($a in @($Areas)) { if ($null -ne $a -and "$($a.area)".Trim().ToLowerInvariant() -ceq $area) { return @($a.lanes) } }
    return @()
}

function Read-HordeOrcProgress {
    # The progress log's entries as { lanes; at }: { ok; reason; entries }. -Path is the progress channel's
    # own file (channels/progress/Settings.ps1); -AreasPath the cards channel's area-to-lane map, read by its
    # own reader (channels/cards/Sources.ps1, Read-HordeCardsChannelAreas). An entry's lanes are its lane
    # member (one or more, by commas) and, when it names an area, the lanes the map gives that area - the
    # rule the phone filters a lane's stream by. at is the entry's ts: when the thing happened, which is
    # what "latest activity" asks. Only the last 8 MB of the log are read (the newest entries are at its
    # end); a line that does not hold together is passed over, as the progress channel passes it over.
    # No log is no entries, not a fault. From the cache while both files look the same.
    param([Parameter(Mandatory = $true)][string]$Path, [string]$AreasPath = "")
    $out = [pscustomobject]@{ ok = $true; reason = ""; entries = @() }
    $key = ""
    try {
        foreach ($f in @($Path, $AreasPath)) { if ($f -ne "" -and [System.IO.File]::Exists($f)) { $i = New-Object System.IO.FileInfo -ArgumentList $f; $key = $key + $f + "|" + $i.Length + "|" + $i.LastWriteTimeUtc.Ticks + ";" } else { $key = $key + $f + "|none;" } }
    } catch { $key = "" }
    if ($key -ne "" -and $script:HordeOrcProgressCache.key -ceq $key -and $null -ne $script:HordeOrcProgressCache.value) { return $script:HordeOrcProgressCache.value }
    if (-not [System.IO.File]::Exists($Path)) { return $out }
    $areaList = @()
    if ($AreasPath -ne "") { $areaList = @((Read-HordeCardsChannelAreas -Path $AreasPath).areas) }
    try {
        $stream = Open-HordeSharedStream -Path $Path
        try {
            $from = [long][System.Math]::Max(0, $stream.Length - $script:HordeOrcProgressTailBytes)
            [void]$stream.Seek($from, [System.IO.SeekOrigin]::Begin)
            $bytes = New-Object byte[] ($stream.Length - $from)
            $got = 0
            while ($got -lt $bytes.Length) { $n = $stream.Read($bytes, $got, $bytes.Length - $got); if ($n -le 0) { break }; $got += $n }
        } finally { $stream.Dispose() }
    } catch { $out.ok = $false; $out.reason = "the progress log " + $Path + " could not be read"; return $out }
    $pieces = @(([System.Text.Encoding]::UTF8.GetString($bytes, 0, $got)) -split "\r?\n")
    # Read from the middle of the file, the first piece is the tail of a line; the last may be unfinished.
    $first = $(if ($from -gt 0) { 1 } else { 0 })
    $list = New-Object System.Collections.ArrayList
    for ($i = $first; $i -lt $pieces.Count; $i++) {
        $line = $pieces[$i]
        if ($line.Trim() -eq "") { continue }
        $e = $null
        try { $e = ConvertFrom-HordeJson $line } catch { continue }
        if ($e -isnot [System.Management.Automation.PSCustomObject]) { continue }
        $ts = $e.PSObject.Properties["ts"]
        $at = $(if ($null -ne $ts) { ConvertFrom-HordeOrcTime $ts.Value } else { $null })
        if ($null -eq $at) { continue }
        $lanes = @(Get-HordeOrcEntryLanes -Entry $e -Areas $areaList)
        if ($lanes.Count -eq 0) { continue }
        [void]$list.Add([pscustomobject]@{ lanes = $lanes; at = $at })
    }
    $out.entries = @($list.ToArray())
    if ($key -ne "") { $script:HordeOrcProgressCache = @{ key = $key; value = $out } }
    return $out
}

function Read-HordeOrcQuestions {
    # Every question of the list, each { lane; open; blocksAll; addedAt; answeredAt }: { ok; reason;
    # questions }. open: still to be answered by the founder - open, and his turn. addedAt: when it was
    # asked; answeredAt: when the founder last said something under it (his acts, park and unpark, are
    # not answers), or $null. From the cache while the store folder looks the same.
    param([Parameter(Mandatory = $true)][string]$Root)
    $key = "absent"
    try {
        if ([System.IO.Directory]::Exists($Root)) {
            $files = @([System.IO.Directory]::GetFiles($Root, "*.json"))
            $key = "" + $files.Count + "|" + [System.IO.Directory]::GetLastWriteTimeUtc($Root).Ticks + "|" + (@($files | Sort-Object | Select-Object -Last 1) -join "")
        }
    } catch { $key = "" }
    if ($key -ne "" -and $script:HordeOrcQuestionCache.key -ceq $key -and $null -ne $script:HordeOrcQuestionCache.value) { return $script:HordeOrcQuestionCache.value }
    $out = [pscustomobject]@{ ok = $false; reason = ""; questions = @() }
    $a = Invoke-HordeDecision -Operation "list" -Request @{ state = "all"; messages = $true } -Root $Root
    if ($a.state -cne "known") { $out.reason = "the decisions list could not be read: " + "$($a.reason)"; return $out }
    if ("$($a.value.outcome)" -cne "done") { $out.reason = "the decisions list was refused: " + $a.value.reason; return $out }
    $turn = Get-HordeDecisionFirstTurn
    $list = New-Object System.Collections.ArrayList
    foreach ($q in @($a.value.questions)) {
        $answered = $null
        foreach ($m in @($q.thread.messages)) {
            if ($null -eq $m -or "$($m.speaker)" -cne $turn) { continue }
            $act = $m.PSObject.Properties["act"]
            if ($null -ne $act -and "$($act.Value)" -ne "") { continue }
            $t = ConvertFrom-HordeOrcTime "$($m.at)"
            if ($null -ne $t -and ($null -eq $answered -or $t -gt $answered)) { $answered = $t }
        }
        $open = ("$($q.state)" -ceq "open" -and "$($q.thread.turn)" -ceq $turn)
        [void]$list.Add([pscustomobject]@{ lane = (Get-HordeOrcQuestionLane $q.askedBy); open = $open; blocksAll = ("$($q.blocks)" -ceq "all"); addedAt = (ConvertFrom-HordeOrcTime "$($q.addedAt)"); answeredAt = $answered })
    }
    $out.ok = $true; $out.questions = @($list.ToArray())
    if ($key -ne "") { $script:HordeOrcQuestionCache = @{ key = $key; value = $out } }
    return $out
}

# --- THE LIST AS IT IS SHOWN --------------------------------------------------------------------------

function New-HordeOrcDefaultName {
    param([string]$Letter, [string]$Id)
    if ($Letter -cmatch '\A[A-Z]\z') { return ("Orc " + $Letter) }
    if ($Id.Length -gt $script:HordeOrcNameMost) { return $Id.Substring(0, $script:HordeOrcNameMost) }
    return $Id
}

function Get-HordeOrcView {
    # The list as it is shown: the registry's Orcs, main then back-burner, less those whose lane the fleet
    # retired; and every lane seen but not yet registered at the end of the main list (registered false),
    # by folder name. Each { id; letter; name; domain; backBurner; registered; order } - order from 1
    # across the whole list. A lane taken off by hand is never shown again.
    # THE LETTER IS THE LANE'S AS IT IS NOW, the stored one only when the lane is not seen or its status
    # names none (review of PR 319: a lane registered while its status file was half written stored no
    # letter, and showed 0 open, 0 sessions and no Wargs for good; a lane that changed its letter kept the
    # old one). So is the default name: a name nobody set (orc-named) follows the letter.
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)]$Lanes)
    $lettersNow = @{}; $takenBy = @{}
    foreach ($l in @($Lanes.lanes)) {
        if ("$($l.letter)" -cmatch '\A[A-Z]\z') { $lettersNow[$l.id] = "$($l.letter)" }
        # A lane whose letter another folder keeps has none, not even the one stored when it was registered.
        if ($null -ne $l.PSObject.Properties["letterTakenBy"] -and "$($l.letterTakenBy)" -ne "") { $lettersNow[$l.id] = ""; $takenBy[$l.id] = "$($l.letterTakenBy)" }
    }
    # Not shown: an Orc whose lane the fleet retired, and a lane named in notOrcs, registered or not.
    $gone = @(@($Lanes.fleetRetired) + @($Lanes.notOrcs))
    $rows = New-Object System.Collections.ArrayList
    $add = {
        param($o, [bool]$Back, [bool]$Registered)
        $letter = $(if ($lettersNow.ContainsKey($o.id)) { $lettersNow[$o.id] } else { "$($o.letter)" })
        $name = $(if ($null -ne $o.PSObject.Properties["named"] -and -not $o.named) { New-HordeOrcDefaultName -Letter $letter -Id $o.id } else { "$($o.name)" })
        [void]$rows.Add([pscustomobject]@{ id = $o.id; letter = $letter; name = $name; domain = "$($o.domain)"; tier = $(if ($null -ne $o.PSObject.Properties["tier"] -and $null -ne $o.tier) { [int]$o.tier } else { $null }); backBurner = $Back; registered = $Registered; named = ($null -ne $o.PSObject.Properties["named"] -and [bool]$o.named); letterTakenBy = $(if ($takenBy.ContainsKey($o.id)) { $takenBy[$o.id] } else { "" }); order = 0 })
    }
    foreach ($id in @($State.main)) { if ($gone -cnotcontains $id) { & $add $State.orcs[$id] $false $true } }
    foreach ($l in @($Lanes.lanes)) {
        if ($State.orcs.Contains($l.id) -and (-not $State.orcs[$l.id].retired -or $State.orcs[$l.id].retiredBy -ceq "hand")) { continue }
        & $add ([pscustomobject]@{ id = $l.id; letter = $l.letter; name = (New-HordeOrcDefaultName -Letter $l.letter -Id $l.id); domain = $(if ($State.orcs.Contains($l.id)) { $State.orcs[$l.id].domain } else { "" }) }) $false $false
    }
    foreach ($id in @($State.back)) { if ($gone -cnotcontains $id) { & $add $State.orcs[$id] $true $true } }
    $n = 0
    foreach ($r in $rows) { $n++; $r.order = $n }
    return @($rows.ToArray())
}

function Format-HordeOrcAge {
    # An age in plain words, in steps (the header): "under 5 min", "40 min", "3 h", "4 d".
    param([double]$Seconds)
    if ($Seconds -lt 300) { return "under 5 min" }
    if ($Seconds -lt 3600) { return ("" + ([int][Math]::Floor($Seconds / 300) * 5) + " min") }
    if ($Seconds -lt 172800) { return ("" + [int][Math]::Floor($Seconds / 3600) + " h") }
    return ("" + [int][Math]::Floor($Seconds / 86400) + " d")
}

function Test-HordeOrcWaiting {
    # Does a waiting-on value say the lane waits on someone? Empty, or beginning with the word "nothing"
    # or "none", says it does not (the header, STATUS).
    param([string]$WaitingOn)
    $w = $WaitingOn.Trim()
    return ($w -ne "" -and $w -inotmatch '\A(nothing|none)\b')
}

function Get-HordeOrcStatus {
    # The status of one Orc (STATUS, in the header): { status; since; age; text }. -StatusAt the status
    # file's last write, -WaitingOn its waiting-on value, -SessionTimes when each of its open sessions
    # last moved, -BlocksAllSince when each of its open questions that blocks all was added.
    param($StatusAt, [string]$WaitingOn = "", [object[]]$SessionTimes = @(), [object[]]$BlocksAllSince = @(), [Parameter(Mandatory = $true)][datetime]$Now, [int]$WorkingMinutes = 15)
    $utcNow = $Now.ToUniversalTime()
    $causes = New-Object System.Collections.ArrayList
    $blocked = $false
    if (Test-HordeOrcWaiting -WaitingOn $WaitingOn) { $blocked = $true; if ($null -ne $StatusAt) { [void]$causes.Add([datetime]$StatusAt) } }
    foreach ($t in @($BlocksAllSince)) { $blocked = $true; if ($null -ne $t) { [void]$causes.Add([datetime]$t) } }
    $since = $null
    if ($blocked) {
        if ($causes.Count -gt 0) { $since = @($causes | Sort-Object)[0] }
        $word = "blocked"
    } else {
        foreach ($t in @(@($StatusAt) + @($SessionTimes))) { if ($null -ne $t -and ($null -eq $since -or [datetime]$t -gt $since)) { $since = [datetime]$t } }
        $word = "idle"
        if ($null -ne $since -and ($utcNow - $since).TotalMinutes -le $WorkingMinutes) { $word = "working" }
    }
    $age = ""; $text = $word
    if ($word -cne "working") {
        if ($null -ne $since) { $age = Format-HordeOrcAge -Seconds ([Math]::Max(0, ($utcNow - $since).TotalSeconds)); $text = $word + " " + $age }
        else { $text = $word + ", since when is not known" }
    }
    $sinceText = $(if ($null -ne $since) { $since.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture) } else { "" })
    return [pscustomobject]@{ status = $word; since = $sinceText; age = $age; text = $text }
}

function Get-HordeOrcDash {
    # THE DASH: the list as shown, each Orc with what is derived of it, for -HordeHome (or -Paths a caller
    # worked out). { ok; reason; version; orcs; lines }. Each Orc { id; letter; name; domain; order;
    # backBurner; registered; open; status; age; since; statusText; sessions; wargsActive; wargsInactive }
    # - open and the session counts $null when their source could not be read, said in lines. READS ONLY.
    param([string]$HordeHome = "", $Paths = $null, [datetime]$Now = [datetime]::UtcNow)
    if ($null -eq $Paths) {
        if ($HordeHome -eq "") { $HordeHome = Get-HordeHome }
        $Paths = Get-HordeOrcPaths -HordeHome $HordeHome
    }
    if (-not $Paths.ok) { return [pscustomobject]@{ ok = $false; reason = $Paths.reason; version = [long]0; orcs = @(); lines = @() } }
    $lines = New-Object System.Collections.ArrayList
    $state = Read-HordeOrcRegistry -Root $Paths.registry
    if ($state.state -cne "ok") { return [pscustomobject]@{ ok = $false; reason = ("the Orc registry could not be read: " + $state.reason); version = [long]0; orcs = @(); lines = @() } }
    foreach ($u in @($state.unreadable)) { [void]$lines.Add("record " + $u.sequence + " of the Orc registry could not be read and changed nothing: " + $u.reason) }
    foreach ($k in @($state.later.Keys)) { [void]$lines.Add("" + $state.later[$k] + " record(s) of the kind '" + $k + "' were written by a later version and are set aside") }
    $lanes = Read-HordeOrcLanes -Folder $Paths.lanes -NotOrcs $Paths.notOrcs -Most $Paths.lanesRead
    if (-not $lanes.ok) { return [pscustomobject]@{ ok = $false; reason = $lanes.reason; version = [long]$state.version; orcs = @(); lines = @($lines.ToArray()) } }
    foreach ($l in @($lanes.lines)) { [void]$lines.Add($l) }
    $sessions = Read-HordeOrcSessions -Folder $Paths.sessions
    if (-not $sessions.ok) { [void]$lines.Add("no sessions are counted: " + $sessions.reason) }
    elseif ($sessions.skipped -gt 0) { [void]$lines.Add("" + $sessions.skipped + " session record(s) could not be read and were passed over") }
    $whose = Get-HordeOrcSessionLines -Sessions @($sessions.sessions)
    if ($whose.unknown -gt 0) { [void]$lines.Add("" + $whose.unknown + " open Warg session(s) name no Orc that can be told (no parent leading to one, and no owner), so they are counted under no Orc") }
    $questions = Read-HordeOrcQuestions -Root $Paths.decisions
    if (-not $questions.ok) { [void]$lines.Add("no open questions are counted, and none is seen to block: " + $questions.reason) }
    $progress = Read-HordeOrcProgress -Path $Paths.progress -AreasPath $Paths.areas
    if (-not $progress.ok) { [void]$lines.Add("the progress log is not counted in anyone's latest activity: " + $progress.reason) }
    $byId = @{}
    foreach ($l in @($lanes.lanes)) { $byId[$l.id] = $l }
    $rows = New-Object System.Collections.ArrayList
    foreach ($v in @(Get-HordeOrcView -State $state -Lanes $lanes)) {
        $lane = $(if ($byId.ContainsKey($v.id)) { $byId[$v.id] } else { $null })
        $letter = $v.letter
        $open = $null; $blocks = New-Object System.Collections.ArrayList
        if ($questions.ok) {
            $open = 0
            foreach ($q in @($questions.questions)) {
                if (-not $q.open -or -not (Test-HordeOrcLaneOfLetter -Lane $q.lane -Letter $letter)) { continue }
                $open++
                if ($q.blocksAll) { [void]$blocks.Add($q.addedAt) }
            }
        }
        $count = $null; $active = $null; $inactive = $null; $times = New-Object System.Collections.ArrayList
        if ($sessions.ok -and $letter -cmatch '\A[A-Z]\z') {
            foreach ($t in @($whose.own[$letter])) { if ($null -ne $t) { [void]$times.Add($t) } }
            $active = 0; $inactive = 0
            foreach ($t in @($whose.wargs[$letter])) {
                if ($null -eq $t) { continue }
                [void]$times.Add($t)
                if (($Now.ToUniversalTime() - [datetime]$t).TotalMinutes -le $Paths.workingMinutes) { $active++ } else { $inactive++ }
            }
            $count = $times.Count
        } elseif ($sessions.ok) { $count = 0; $active = 0; $inactive = 0 }
        $statusAt = $null; $waiting = ""
        if ($null -ne $lane) { $statusAt = $lane.statusAt; $waiting = $lane.waitingOn }
        $st = Get-HordeOrcStatus -StatusAt $statusAt -WaitingOn $waiting -SessionTimes @($times.ToArray()) -BlocksAllSince @($blocks.ToArray()) -Now $Now -WorkingMinutes $Paths.workingMinutes
        $last = Get-HordeOrcLastActivity -Id $v.id -Letter $letter -StatusAt $statusAt -Progress $progress -Questions $questions
        [void]$rows.Add([pscustomobject]([ordered]@{ id = $v.id; letter = $letter; name = $v.name; domain = $v.domain; tier = $v.tier; order = [int]$v.order; backBurner = [bool]$v.backBurner; registered = [bool]$v.registered; letterTakenBy = "$($v.letterTakenBy)"
            open = $open; status = $st.status; age = $st.age; since = $st.since; statusText = $st.text; sessions = $count; wargsActive = $active; wargsInactive = $inactive
            lastActivityAt = $last.at; lastActivitySource = $last.source }))
    }
    return [pscustomobject]@{ ok = $true; reason = ""; version = [long]$state.version; orcs = @($rows.ToArray()); lines = @($lines.ToArray()) }
}

$script:HordeOrcDashFields = @("id", "letter", "name", "domain", "tier", "order", "backBurner", "registered", "open", "status", "age", "since", "statusText", "sessions", "wargsActive", "wargsInactive", "lastActivityAt", "lastActivitySource", "letterTakenBy")

function Get-HordeOrcLastActivity {
    # LATEST ACTIVITY (the header): { at; source } - at the newest of the lane's status file write
    # (-StatusAt), its newest progress entry (-Progress, Read-HordeOrcProgress; an entry is the lane's when
    # one of its entryLanes is the lane's id, or the Orc's letter or a sub-lane of it), and its newest
    # question asked or answered (-Questions, Read-HordeOrcQuestions, by the decisions page's lane rule),
    # as ISO text with a Z; source which of them it was: status, progress or decision. ONE DERIVATION for
    # the dash's Latest order and the cards' age (C, 2026-10-15): no second clock. On a tie the earlier
    # source in that order is named. None known: at $null and source "" - no time, sorted last.
    param([string]$Id = "", [string]$Letter = "", $StatusAt = $null, $Progress = $null, $Questions = $null)
    # Every candidate time with its source, in the order status, progress, decision.
    $seen = New-Object System.Collections.ArrayList
    [void]$seen.Add(@($StatusAt, "status"))
    if ($null -ne $Progress -and $Progress.ok) {
        foreach ($e in @($Progress.entries)) {
            foreach ($ln in @($e.lanes)) { if (($Id -ne "" -and "$ln" -ceq $Id) -or (Test-HordeOrcLaneOfLetter -Lane "$ln" -Letter $Letter)) { [void]$seen.Add(@($e.at, "progress")); break } }
        }
    }
    if ($null -ne $Questions -and $Questions.ok) {
        foreach ($q in @($Questions.questions)) {
            if (-not (Test-HordeOrcLaneOfLetter -Lane $q.lane -Letter $Letter)) { continue }
            [void]$seen.Add(@($q.addedAt, "decision")); [void]$seen.Add(@($q.answeredAt, "decision"))
        }
    }
    $best = $null; $source = ""
    foreach ($c in $seen) { if ($null -ne $c[0] -and ($null -eq $best -or [datetime]$c[0] -gt $best)) { $best = [datetime]$c[0]; $source = $c[1] } }
    if ($null -eq $best) { return [pscustomobject]@{ at = $null; source = "" } }
    return [pscustomobject]@{ at = $best.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture); source = $source }
}

function ConvertTo-HordeOrcDashDocument {
    # THE DASH AS IT LEAVES THE MACHINE, versioned and with every field named: { v: 1; ok; version; orcs }
    # - each Orc exactly the fields of $script:HordeOrcDashFields, in that order, so a field added later
    # is one more name and an old reader is not broken. A dash that could not be made is { v; ok false;
    # version 0; orcs [] }: its reason stays at the machine, since it can name a folder. -Protect is a
    # function applied to each person-written text (name, domain) on its way out (the cards channel
    # passes its secret refusal); without one they go as stored, which the writes already checked.
    param([Parameter(Mandatory = $true)]$Dash, [scriptblock]$Protect = $null)
    $rows = New-Object System.Collections.ArrayList
    foreach ($o in @($Dash.orcs)) {
        $row = [ordered]@{}
        foreach ($f in $script:HordeOrcDashFields) { $row[$f] = $o.$f }
        if ($null -ne $Protect) { foreach ($f in @("name", "domain")) { $row[$f] = & $Protect "$($row[$f])" $f } }
        [void]$rows.Add([pscustomobject]$row)
    }
    return [pscustomobject]([ordered]@{ v = 1; ok = [bool]$Dash.ok; version = [long]$Dash.version; orcs = @($rows.ToArray()) })
}

# --- WRITES -------------------------------------------------------------------------------------------

function Test-HordeOrcText {
    # Why -Text is not a -What of at most -Most printable ASCII characters (empty allowed with -Empty),
    # as findings; none when it is. A text that looks like a secret is refused, never stored.
    param([AllowEmptyString()][string]$Text, [string]$What, [int]$Most, [switch]$Empty)
    $found = New-Object System.Collections.ArrayList
    if ($Text -cnotmatch $script:HordeOrcPrintable) { [void]$found.Add("the " + $What + " holds a character that is not printable ASCII (letters, digits, spaces and punctuation, on one line)") }
    if ($Text.Length -gt $Most) { [void]$found.Add("the " + $What + " is " + $Text.Length + " characters, and the most is " + $Most) }
    if (-not $Empty -and $Text.Trim() -eq "") { [void]$found.Add("the " + $What + " is empty") }
    if ((Find-HordeSecretKind -Text $Text) -cne "") { [void]$found.Add("the " + $What + " looks like it holds a secret, so it is not stored") }
    return @($found)
}

function Add-HordeOrcRecord {
    # Write one record at -Sequence: "created", "exists" (another writer has that place) or "unconfirmed"
    # (it has its place but could not be confirmed on disk). The record is built as text, read back and
    # checked against its schema before it is written, so what is written is what a reader will parse.
    param([string]$Root, [long]$Sequence, [string]$Kind, $Data, [string]$Actor, [string]$By, [datetime]$Now)
    $envelope = [ordered]@{ schemaVersion = 1; sequence = $Sequence; kind = $Kind
        at = $Now.ToUniversalTime().ToString("o", [System.Globalization.CultureInfo]::InvariantCulture); actor = $Actor; by = $By; data = $Data }
    $text = ConvertTo-Json -InputObject $envelope -Compress -Depth 8
    if ($text -cnotmatch '\A[\x20-\x7E]*\z') { throw "a registry record must be printable ASCII" }
    $why = @(Test-HordeOrcRecord -Record (ConvertFrom-HordeJson $text) -Sequence $Sequence)
    if ($why.Count -gt 0) { throw ("a registry record that does not match its schema was not written: " + (@($why) -join "; ")) }
    return (Add-HordeDecisionRecord -Root $Root -Sequence $Sequence -Text $text)
}

function New-HordeOrcResult {
    param([string]$Outcome, [string]$Reason = "", [long]$Version = 0, [int]$Written = 0, $Lines = @())
    return [pscustomobject]@{ outcome = $Outcome; reason = $Reason; version = $Version; written = $Written; lines = @($Lines) }
}

function Sync-HordeOrcRegistry {
    # Make the registry follow the lanes folder (the header): register each lane seen and not on the list,
    # at the end, in folder-name order, and take off each Orc whose lane the fleet retired. Written as
    # actor fleet. Returns { ok; reason; written; version }.
    param([string]$Root, $Lanes, [string]$By, [datetime]$Now)
    $written = 0
    $done = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    for ($try = 1; $try -le $script:HordeOrcRaceTries; $try++) {
        $s = Read-HordeOrcRegistry -Root $Root
        if ($s.state -cne "ok") { return [pscustomobject]@{ ok = $false; reason = $s.reason; written = $written; version = [long]0 } }
        $next = $null
        foreach ($l in @($Lanes.lanes)) {
            $known = $s.orcs.Contains($l.id)
            if (-not $known -or ($s.orcs[$l.id].retired -and $s.orcs[$l.id].retiredBy -ceq "fleet")) {
                $next = @{ kind = "orc-registered"; data = [ordered]@{ id = $l.id; letter = $l.letter; name = (New-HordeOrcDefaultName -Letter $l.letter -Id $l.id) } }
                if ($known) { $next.data.name = $s.orcs[$l.id].name }
                break
            }
        }
        if ($null -eq $next) {
            foreach ($id in @($Lanes.fleetRetired)) {
                if ($s.orcs.Contains($id) -and -not $s.orcs[$id].retired) { $next = @{ kind = "orc-retired"; data = [ordered]@{ id = $id; reason = "fleet" } }; break }
            }
        }
        if ($null -eq $next) { return [pscustomobject]@{ ok = $true; reason = ""; written = $written; version = [long]$s.version } }
        # A RECORD THIS SYNC WROTE THAT THE FOLD DID NOT TAKE is not written again: the same step asked for
        # twice means the rule that picks it and the fold disagree, and writing on would never end
        # (measured 2026-10-16 by the mutant that registers a lane retired by hand: the fold ignores each
        # registration, so the sync wrote one after another until the run was killed at 900 s).
        $step = $next.kind + " " + $next.data.id
        if ($done.Contains($step)) { return [pscustomobject]@{ ok = $false; reason = ("nothing more was written: the registry did not take its own " + $step + " (the fold and the lanes disagree)"); written = $written; version = [long]$s.version } }
        $made = ""
        try { $made = Add-HordeOrcRecord -Root $Root -Sequence ($s.version + 1) -Kind $next.kind -Data $next.data -Actor "fleet" -By $By -Now $Now }
        catch { return [pscustomobject]@{ ok = $false; reason = ("record " + ($s.version + 1) + " could not be written: " + $_.Exception.Message); written = $written; version = [long]$s.version } }
        if ($made -ceq "unconfirmed") { return [pscustomobject]@{ ok = $false; reason = ("record " + ($s.version + 1) + " has its place but could not be confirmed written through to the disk"); written = $written; version = [long]($s.version + 1) } }
        if ($made -ceq "created") { $written++; $try = 0; [void]$done.Add($step) }
    }
    return [pscustomobject]@{ ok = $false; reason = ("the registry kept moving under " + $script:HordeOrcRaceTries + " tries to follow the lanes folder"); written = $written; version = [long]0 }
}

function Get-HordeOrcRecordFor {
    # The one record -Operation makes against -View (the list as shown, all registered), or why not:
    # { refuse; unchanged; kind; data }.
    param([string]$Operation, $Request, $View)
    $no = { param($why) return [pscustomobject]@{ refuse = $why; unchanged = $false; kind = ""; data = $null } }
    $same = [pscustomobject]@{ refuse = ""; unchanged = $true; kind = ""; data = $null }
    $ids = @($View | ForEach-Object { $_.id })
    $main = @($View | Where-Object { -not $_.backBurner } | ForEach-Object { $_.id })
    $back = @($View | Where-Object { $_.backBurner } | ForEach-Object { $_.id })
    $id = ""
    if ($Operation -cne "order") {
        $id = "$($Request.id)"
        if ($ids -cnotcontains $id) { return (& $no ("there is no Orc '" + $id + "' on the list; the Orcs are: " + ($ids -join ", "))) }
    }
    $row = @($View | Where-Object { $_.id -ceq $id }) | Select-Object -First 1
    switch -CaseSensitive ($Operation) {
        "name" {
            $text = "$($Request.name)"
            $f = @(Test-HordeOrcText -Text $text -What "name" -Most $script:HordeOrcNameMost)
            if ($f.Count -gt 0) { return (& $no ($f -join "; ")) }
            # A name the same as the default it shows now is still written when nobody has set one: written,
            # it stays when the letter changes (review of PR 319).
            if ($row.named -and $row.name -ceq $text) { return $same }
            return [pscustomobject]@{ refuse = ""; unchanged = $false; kind = "orc-named"; data = [ordered]@{ id = $id; name = $text } }
        }
        "domain" {
            $text = "$($Request.domain)"
            $f = @(Test-HordeOrcText -Text $text -What "domain" -Most $script:HordeOrcDomainMost -Empty)
            if ($f.Count -gt 0) { return (& $no ($f -join "; ")) }
            if ($row.domain -ceq $text) { return $same }
            return [pscustomobject]@{ refuse = ""; unchanged = $false; kind = "orc-domain-set"; data = [ordered]@{ id = $id; domain = $text } }
        }
        "retire" { return [pscustomobject]@{ refuse = ""; unchanged = $false; kind = "orc-retired"; data = [ordered]@{ id = $id; reason = "hand" } } }
        "tier" {
            # ONE OR TWO, nothing else: the tier an Orc is in (a whole number, not text that looks like one).
            $tier = $Request.tier
            if (-not (($tier -is [int] -or $tier -is [long]) -and (@(1, 2) -contains [int]$tier))) { return (& $no ("a tier is 1 or 2, not '" + $tier + "'")) }
            if ($null -ne $row.tier -and [int]$row.tier -eq [int]$tier) { return $same }
            return [pscustomobject]@{ refuse = ""; unchanged = $false; kind = "orc-tier-set"; data = [ordered]@{ id = $id; tier = [int]$tier } }
        }
        "backburner" {
            $on = [bool]$Request.on
            if ($on -eq [bool]$row.backBurner) { return $same }
            if ($on) { $newMain = @($main | Where-Object { $_ -cne $id }); $newBack = @(@($back) + $id) }
            else { $newBack = @($back | Where-Object { $_ -cne $id }); $newMain = @(@($main) + $id) }
            return [pscustomobject]@{ refuse = ""; unchanged = $false; kind = "orcs-ordered"; data = [ordered]@{ order = [string[]]@($newMain); backBurner = [string[]]@($newBack) } }
        }
        "order" {
            $o = @($Request.order | ForEach-Object { "$_" }); $b = @($Request.backBurner | ForEach-Object { "$_" })
            $named = @($o) + @($b)
            $problems = New-Object System.Collections.ArrayList
            $dups = @($named | Group-Object -CaseSensitive | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
            if ($dups.Count -gt 0) { [void]$problems.Add("it names " + ($dups -join ", ") + " more than once") }
            $missing = @($ids | Where-Object { $named -cnotcontains $_ })
            if ($missing.Count -gt 0) { [void]$problems.Add("it leaves out " + ($missing -join ", ")) }
            $extra = @($named | Where-Object { $ids -cnotcontains $_ } | Select-Object -Unique)
            if ($extra.Count -gt 0) { [void]$problems.Add("it names " + ($extra -join ", ") + ", which " + $(if ($extra.Count -eq 1) { "is" } else { "are" }) + " not on the list") }
            if ($problems.Count -gt 0) { return (& $no ("an order names every Orc on the list exactly once (" + ($ids -join ", ") + "); " + ($problems -join "; "))) }
            if ((@($o) -join ",") -ceq (@($main) -join ",") -and (@($b) -join ",") -ceq (@($back) -join ",")) { return $same }
            return [pscustomobject]@{ refuse = ""; unchanged = $false; kind = "orcs-ordered"; data = [ordered]@{ order = [string[]]@($o); backBurner = [string[]]@($b) } }
        }
    }
    return (& $no ("'" + $Operation + "' is not an operation on the Orc registry"))
}

function Invoke-HordeOrcWrite {
    # ONE CHANGE to the registry: -Operation name, domain, retire, backburner, order or tier, with -Request
    # (id and name / domain / on / tier; or order and backBurner). -Version: the version the change was
    # drawn from, or -1 for none (the header, EVERY WRITE CARRIES THE VERSION). Returns { outcome: done |
    # unchanged | refused | stale | unknown; reason; version; written; lines }. A refusal, or a version
    # already stale when the write begins, writes nothing, not even the lanes' registration. A version
    # found stale only after that registration (another writer landed between the two reads) writes
    # nothing of the change itself, but the lanes registered just before stay: they are what the lanes
    # folder shows, and written says how many.
    param([Parameter(Mandatory = $true)][string]$Operation, $Request, [string]$HordeHome = "", $Paths = $null, [long]$Version = -1,
        [string]$Actor = "cli", [string]$By = "console", [datetime]$Now = [datetime]::UtcNow)
    if ($By -cnotmatch $script:HordeOrcByPattern) { $By = "console" }
    if ($null -eq $Paths) {
        if ($HordeHome -eq "") { $HordeHome = Get-HordeHome }
        $Paths = Get-HordeOrcPaths -HordeHome $HordeHome
    }
    if (-not $Paths.ok) { return (New-HordeOrcResult -Outcome "unknown" -Reason $Paths.reason) }
    $root = $Paths.registry
    $first = Read-HordeOrcRegistry -Root $root
    if ($first.state -cne "ok") { return (New-HordeOrcResult -Outcome "unknown" -Reason ("nothing was written: the Orc registry could not be read: " + $first.reason)) }
    if ($Version -ge 0 -and $Version -ne $first.version) {
        return (New-HordeOrcResult -Outcome "stale" -Version $first.version -Reason ("the list was drawn from version " + $Version + ", and the registry is at version " + $first.version + ": it changed since, so nothing was written. Read the list again and draw the change from it"))
    }
    $lanes = Read-HordeOrcLanes -Folder $Paths.lanes -NotOrcs $Paths.notOrcs -Most $Paths.lanesRead
    if (-not $lanes.ok) { return (New-HordeOrcResult -Outcome "unknown" -Reason ("nothing was written: " + $lanes.reason) -Version $first.version) }
    # JUDGED FIRST against the list as shown, so a refusal writes nothing - not even the registration of
    # a new lane the view already shows.
    $judged = Get-HordeOrcRecordFor -Operation $Operation -Request $Request -View @(Get-HordeOrcView -State $first -Lanes $lanes)
    if ($judged.refuse -ne "") { return (New-HordeOrcResult -Outcome "refused" -Reason ("nothing was written: " + $judged.refuse) -Version $first.version) }
    $sync = Sync-HordeOrcRegistry -Root $root -Lanes $lanes -By $By -Now $Now
    if (-not $sync.ok) { return (New-HordeOrcResult -Outcome "unknown" -Reason $sync.reason -Written $sync.written) }
    $written = [int]$sync.written
    for ($try = 1; $try -le $script:HordeOrcRaceTries; $try++) {
        $s = Read-HordeOrcRegistry -Root $root
        if ($s.state -cne "ok") { return (New-HordeOrcResult -Outcome "unknown" -Reason $s.reason -Written $written) }
        # A versioned change whose list moved under it, other than by the registration just made for it,
        # is stale: it was drawn from a list that is no longer the one shown.
        if ($Version -ge 0 -and $s.version -ne ($first.version + $written)) {
            return (New-HordeOrcResult -Outcome "stale" -Version $s.version -Written $written -Reason ("the registry moved to version " + $s.version + " while this change was being written, so it was not written. Read the list again and draw the change from it"))
        }
        $step = Get-HordeOrcRecordFor -Operation $Operation -Request $Request -View @(Get-HordeOrcView -State $s -Lanes $lanes)
        if ($step.refuse -ne "") { return (New-HordeOrcResult -Outcome "refused" -Reason ("nothing more was written: " + $step.refuse) -Version $s.version -Written $written) }
        if ($step.unchanged) { return (New-HordeOrcResult -Outcome "unchanged" -Reason "the list already says that; nothing was written" -Version $s.version -Written $written) }
        # A record that cannot be written - one that would not match its schema, a folder that cannot be
        # made - is an unknown in words, never a throw out of the module (measured 2026-10-16: a domain
        # of 81 characters let past the check threw here and broke the caller).
        $made = ""
        try { $made = Add-HordeOrcRecord -Root $root -Sequence ($s.version + 1) -Kind $step.kind -Data $step.data -Actor $Actor -By $By -Now $Now }
        catch { return (New-HordeOrcResult -Outcome "unknown" -Version $s.version -Written $written -Reason ("record " + ($s.version + 1) + " could not be written, so nothing more changed: " + $_.Exception.Message)) }
        if ($made -ceq "created") { return (New-HordeOrcResult -Outcome "done" -Version ($s.version + 1) -Written ($written + 1)) }
        if ($made -ceq "unconfirmed") { return (New-HordeOrcResult -Outcome "unknown" -Version ($s.version + 1) -Written $written -Reason ("record " + ($s.version + 1) + " has its place in the registry but could not be confirmed written through to the disk, so it is NOT reported as saved")) }
    }
    return (New-HordeOrcResult -Outcome "unknown" -Written $written -Reason ("nothing was written: " + $script:HordeOrcRaceTries + " tries each found another writer had taken the next place first"))
}

function Set-HordeOrcTier {
    # Put Orc -Id in tier -Tier (1 or 2): one orc-tier-set record, by the same write as every other
    # change, so it carries -Version the same way and is refused as stale the same way. Returns
    # Invoke-HordeOrcWrite's answer.
    param([Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)]$Tier, [string]$HordeHome = "", $Paths = $null, [long]$Version = -1,
        [string]$Actor = "cli", [string]$By = "console", [datetime]$Now = [datetime]::UtcNow)
    return (Invoke-HordeOrcWrite -Operation "tier" -Request @{ id = $Id; tier = $Tier } -HordeHome $HordeHome -Paths $Paths -Version $Version -Actor $Actor -By $By -Now $Now)
}

function Invoke-HordeOrcSeed {
    # THE DOMAIN LINES SET ONCE, in one step (M writes them as the seed; C and M, 2026-10-15): -Domains a
    # table letter -> domain. Each Orc on the list with that letter gets it, by the same write as horde
    # orcs domain; one already holding it is left. Returns { ok; lines; written }.
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Domains, [string]$HordeHome = "", $Paths = $null, [string]$By = "console", [datetime]$Now = [datetime]::UtcNow)
    if ($null -eq $Paths) {
        if ($HordeHome -eq "") { $HordeHome = Get-HordeHome }
        $Paths = Get-HordeOrcPaths -HordeHome $HordeHome
    }
    $lines = New-Object System.Collections.ArrayList
    if (-not $Paths.ok) { return [pscustomobject]@{ ok = $false; lines = @($Paths.reason); written = 0 } }
    $bad = New-Object System.Collections.ArrayList
    foreach ($k in @($Domains.Keys)) {
        if ("$k" -cnotmatch '\A[A-Z]\z') { [void]$bad.Add("'" + $k + "' is not one capital letter") }
        foreach ($f in @(Test-HordeOrcText -Text "$($Domains[$k])" -What ("domain of " + $k) -Most $script:HordeOrcDomainMost -Empty)) { [void]$bad.Add($f) }
    }
    if ($bad.Count -gt 0) { return [pscustomobject]@{ ok = $false; lines = @("nothing was written: " + ($bad -join "; ")); written = 0 } }
    $lanes = Read-HordeOrcLanes -Folder $Paths.lanes -NotOrcs $Paths.notOrcs -Most $Paths.lanesRead
    $state = Read-HordeOrcRegistry -Root $Paths.registry
    $view = @(Get-HordeOrcView -State $state -Lanes $lanes)
    $ok = $true; $written = 0
    foreach ($k in @($Domains.Keys | Sort-Object)) {
        $rows = @($view | Where-Object { $_.letter -ceq "$k" })
        if ($rows.Count -eq 0) { [void]$lines.Add("no Orc on the list has the letter " + $k + "; its domain was not set"); continue }
        foreach ($row in $rows) {
            $r = Invoke-HordeOrcWrite -Operation "domain" -Request @{ id = $row.id; domain = "$($Domains[$k])" } -Paths $Paths -By $By -Now $Now
            $written += [int]$r.written
            if ($r.outcome -ceq "done") { [void]$lines.Add("Orc " + $k + " (" + $row.id + "): domain set") }
            elseif ($r.outcome -ceq "unchanged") { [void]$lines.Add("Orc " + $k + " (" + $row.id + "): already set") }
            else { $ok = $false; [void]$lines.Add("Orc " + $k + " (" + $row.id + "): " + $r.outcome + " - " + $r.reason) }
        }
    }
    return [pscustomobject]@{ ok = $ok; lines = @($lines.ToArray()); written = $written }
}
