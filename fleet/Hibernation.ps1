# fleet/Hibernation.ps1 - the hibernation record: which sessions were running, where each sat, and what
# has happened to each since. Horde's own record (decided by M and F, 2026-10-16): a wake reads this and
# never a terminal plugin's saved layouts.
#
#   <HORDE_HOME>\fleet\hibernations\<yyyymmdd-hhmmss>\record.json     schema/fleet-hibernation.v1
#
# A SESSION IS KEYED BY ITS SESSION ID, NEVER BY ITS PANE NUMBER: a terminal reuses pane ids after it
# restarts (the terminal adapter's acting half says so in its header), and a hibernation is meant to
# outlive exactly that.
#
# WHAT IS RECORDED. Only sessions the fleet registry holds (core/WezfleetState.ps1, store W1, read and
# never written) that are not retired AND are running now by the harness adapter's liveness rule
# (agents/<name>/Fleet.ps1). Unknown is not running here: a record is a list of what to wake, and a
# session nobody can prove is running is reported and left out, never guessed in.
#
# FAIL CLOSED, NEVER EMPTY. A registry that cannot be read whole, a liveness reading that cannot be
# trusted, or a selection that comes to nothing is a refusal with the reason, and nothing is written:
# an empty record would read later as "nothing was asleep" (the old reader's "one corrupt file costs
# ONE row" made the fleet shorter instead of unknown; core/WezfleetState.ps1's header).
#
# THE MASTER IS NEVER RECORDED unless -Labels names it: the session labelled M, or any session whose
# role reads as the warchief (core/Roles.ps1). Putting the one session that coordinates the rest to
# sleep is never the side effect of "all".
#
# SELECTION IS A PLUGGABLE BLOCK (New-HordeFleetSelector*): it is handed the running, unretired
# sessions and returns the ones to record. -All and -Labels are the first two; the Orc registry's tiers
# (an Orc's id is its lane folder name) will be a third, with no change here.
#
# THE ID IS THE TIME, UTC, TO THE SECOND. Its record.json is claimed with CreateNew, one step in the file
# system, before anything else: a second record in the same second is refused, never merged into the
# first (review of PR 318, finding a).
#
# EACH SESSION KEEPS ITS PROCESS, { pid; start } as the harness names it, so a wake can tell that very
# process still running under another id (second review of PR 318, P1).
#
# WRITTEN WHOLE OR NOT AT ALL: to a temporary file beside it, then renamed over it in one step
# (core/FileAtomic.ps1). The text is ASCII: any other character is written as a \u escape.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Tristate.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Home.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\JsonText.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\ReadShared.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\FileAtomic.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Schema.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\WezfleetState.ps1")
. (Join-Path $PSScriptRoot "Port.ps1")

$script:HordeFleetIdPattern = '\A[0-9]{8}-[0-9]{6}\z'
$script:HordeFleetSessionPattern = '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z'
$script:HordeFleetMasterLabel = "M"
$script:HordeFleetStates = @("recorded", "asked", "parked", "exited", "still-awake", "waking", "woken", "failed")

function Get-HordeFleetHibernationsDir {
    param([string]$HordeHome = (Get-HordeHome))
    return (Join-Path $HordeHome "fleet\hibernations")
}

function Format-HordeFleetTime {
    # A UTC time as the record writes every time: yyyy-MM-ddTHH:mm:ssZ.
    param([Parameter(Mandatory = $true)][datetime]$At)
    return $At.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
}

function New-HordeFleetHibernationId {
    # The id of a hibernation taken at -At: its UTC time, yyyymmdd-hhmmss.
    param([Parameter(Mandatory = $true)][datetime]$At)
    return $At.ToUniversalTime().ToString("yyyyMMdd-HHmmss", [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-HordeFleetAsciiJson {
    # -Value as indented JSON with every character past ASCII written as a \u escape, so the file is
    # ASCII whatever a path or a label holds (CONTRIBUTING 13).
    param([Parameter(Mandatory = $true)]$Value)
    $json = ConvertTo-Json -InputObject $Value -Depth 20
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $json.ToCharArray()) {
        if ([int]$ch -gt 126) { [void]$sb.Append(("\u{0:x4}" -f [int]$ch)) } else { [void]$sb.Append($ch) }
    }
    return $sb.ToString()
}

function Test-HordeFleetRecord {
    # Findings for a parsed record: the schema's, and what the schema cannot say - every session id
    # once, every state one of the record's, and the id the folder's name.
    param([Parameter(Mandatory = $true)]$Record, [string]$Id = "")
    $out = New-Object System.Collections.ArrayList
    foreach ($f in @(Test-HordeSchema -Value $Record -Schema (Get-HordeSchema -Name "fleet-hibernation.v1"))) { [void]$out.Add($f) }
    if ($out.Count -gt 0) { return @($out) }
    if ($Id -ne "" -and "" + $Record.id -cne $Id) { [void]$out.Add("the record says it is " + $Record.id + " but sits in the folder " + $Id) }
    if (@($Record.sessions).Count -eq 0) { [void]$out.Add("the record holds no session: an empty hibernation is never written") }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($s in @($Record.sessions)) {
        if (-not $seen.Add("" + $s.sessionId)) { [void]$out.Add("session " + $s.sessionId + " is in the record twice") }
    }
    return @($out)
}

function Write-HordeFleetRecord {
    # Replace <Dir>\record.json with -Record, whole, in one step. Throws, writing nothing, when the record
    # breaks its schema: a record that does not read back is worse than none.
    param([Parameter(Mandatory = $true)][string]$Dir, [Parameter(Mandatory = $true)]$Record)
    $findings = @(Test-HordeFleetRecord -Record $Record -Id (Split-Path -Leaf $Dir))
    if ($findings.Count -gt 0) { throw ("the hibernation record was not written, it breaks its schema: " + ($findings -join "; ")) }
    $path = Join-Path $Dir "record.json"
    $tmp = Join-Path $Dir ("record.json." + [guid]::NewGuid().ToString("N") + ".tmp")
    [System.IO.File]::WriteAllText($tmp, (ConvertTo-HordeFleetAsciiJson -Value $Record), (New-Object System.Text.UTF8Encoding($false)))
    try { Move-HordeFileAtomic -From $tmp -To $path }
    catch { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; throw }
    return $path
}

function Read-HordeFleetRecord {
    # The record of hibernation -Id, as an answer: known record, absent when there is none, unknown when
    # it cannot be read or breaks its schema.
    param([Parameter(Mandatory = $true)][string]$Id, [string]$HordeHome = (Get-HordeHome))
    if ($Id -cnotmatch $script:HordeFleetIdPattern) { return (New-HordeUnknown -Reason ("'" + $Id + "' is not a hibernation id (yyyymmdd-hhmmss)")) }
    $path = Join-Path (Join-Path (Get-HordeFleetHibernationsDir -HordeHome $HordeHome) $Id) "record.json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return (New-HordeAbsent -Note ("there is no hibernation " + $Id + " (no " + $path + ")")) }
    $rec = $null
    try { $rec = ConvertFrom-HordeJson -Text (Read-HordeSharedText -Path $path) }
    catch { return (New-HordeUnknown -Reason ("the record of hibernation " + $Id + " could not be read") -ErrorRecord $_) }
    $findings = @(Test-HordeFleetRecord -Record $rec -Id $Id)
    if ($findings.Count -gt 0) { return (New-HordeUnknown -Reason ("the record of hibernation " + $Id + " breaks its schema: " + ($findings -join "; "))) }
    return (New-HordeKnown -Value $rec)
}

function Add-HordeFleetState {
    # Move one session of a record to -State at -At, keeping the history. -Reason is optional. -Pane names
    # the pane a wake started for it, when one was: a later wake holds a session failed after its pane
    # started until -Retry (fleet/Wake.ps1).
    param([Parameter(Mandatory = $true)]$Session, [Parameter(Mandatory = $true)][string]$State, [Parameter(Mandatory = $true)][datetime]$At, [string]$Reason = "", [string]$Pane = "")
    if ($script:HordeFleetStates -cnotcontains $State) { throw ("'" + $State + "' is not a session state of a hibernation") }
    $entry = [ordered]@{ state = $State; at = (Format-HordeFleetTime -At $At) }
    if ($Reason -ne "") { $entry["reason"] = $Reason }
    if ($Pane -ne "") { $entry["pane"] = $Pane }
    $Session.state = $State
    $Session.history = @(@($Session.history) + @([pscustomobject]$entry))
}

function Get-HordeFleetRole {
    # A registry record's role in the record's words: orc, warg, warchief (the master, never recorded
    # unless named) or other - a role that is missing or unknown is "other", never guessed
    # (core/Roles.ps1: 123 of 135 records on 2026-10-16 had no role).
    param([Parameter(Mandatory = $true)]$Record)
    $r = Read-HordeRecordRole -Record $Record
    if ($r.role.state -ne "known") { return "other" }
    return ("" + $r.role.value)
}

function Test-HordeFleetMaster {
    # Is this candidate the master: labelled M, or holding the warchief's role?
    param([Parameter(Mandatory = $true)]$Candidate)
    return ([bool](("" + $Candidate.label) -ceq $script:HordeFleetMasterLabel -or ("" + $Candidate.role) -ceq "warchief"))
}

function New-HordeFleetSelectorAll {
    # Every candidate but the master.
    return { param($candidates) @(@($candidates) | Where-Object { -not (Test-HordeFleetMaster -Candidate $_) }) }
}

function New-HordeFleetSelectorLabels {
    # Exactly the sessions labelled -Labels, each of which must name exactly one candidate: a label that
    # names none is refused, never dropped, because "record K and L" that records only K reads later as
    # if L had been asked about. The master is recorded when it is named here, and only then.
    param([Parameter(Mandatory = $true)][string[]]$Labels)
    $wanted = @($Labels | Where-Object { "" + $_ -ne "" })
    return {
        param($candidates)
        $out = New-Object System.Collections.ArrayList
        foreach ($l in $wanted) {
            $hit = @(@($candidates) | Where-Object { ("" + $_.label) -ceq $l })
            if ($hit.Count -eq 0) { throw ("no running, unretired session is labelled " + $l + ", so nothing was recorded") }
            if ($hit.Count -gt 1) { throw ("" + $hit.Count + " running sessions are labelled " + $l + "; which is meant cannot be told, so nothing was recorded") }
            if (-not $out.Contains($hit[0])) { [void]$out.Add($hit[0]) }
        }
        return @($out)
    }.GetNewClosure()
}

function Get-HordeFleetCandidates {
    # The registry's sessions that are not retired and are running now, as candidates { sessionId;
    # label; role; parent; cwd; transcriptPath; instance; pane }, and notes on the ones left out for a
    # reason a person should see. THROWS, naming why, when the registry cannot be read whole or the
    # liveness reading cannot be trusted: then no answer about who runs is safe.
    param([Parameter(Mandatory = $true)]$Registry, [Parameter(Mandatory = $true)]$Agent, [Parameter(Mandatory = $true)]$Snapshot)
    if ($Registry.complete.state -ne "known") { throw ("the fleet registry cannot be read whole, so nothing was recorded: " + $Registry.complete.reason) }
    if ($Registry.records.Count -eq 0) { throw "the fleet registry holds no session at all, which is more likely a wrong folder than an empty fleet, so nothing was recorded" }
    $cands = New-Object System.Collections.ArrayList
    $notes = New-Object System.Collections.ArrayList
    foreach ($id in @($Registry.records.Keys | Sort-Object)) {
        if ($id -cnotmatch $script:HordeFleetSessionPattern) { continue }
        $rec = $Registry.records[$id].record
        $retired = Get-HordeField -Record $rec -Name "retired"
        if ($retired.state -eq "known" -and $retired.value -eq $true) { continue }
        $cwd = Get-HordeStoredField -Record $rec -Name "cwd"
        $cwdText = ""
        if ($cwd.state -eq "known") { $cwdText = "" + $cwd.value }
        $v = & $Agent.verdict $Snapshot $id $cwdText @()
        if ("" + $v.kind -ceq "reading") { throw ("which sessions run cannot be read, so nothing was recorded: " + $v.reason) }
        if ("" + $v.state -ceq "stopped") { continue }
        $label = Get-HordeStoredField -Record $rec -Name "label"
        $labelText = ""
        if ($label.state -eq "known") { $labelText = "" + $label.value }
        if ("" + $v.state -cne "running") {
            # Only an id whose own control file proves it is left out with a note: a stale record in a
            # folder where another session runs (kind rotated) is the normal case, not news.
            if ("" + $v.kind -cne "rotated") { [void]$notes.Add(("" + $labelText + " " + $id).Trim() + ": left out, " + $v.reason) }
            continue
        }
        $parent = Get-HordeStoredField -Record $rec -Name "parent"
        $tp = Get-HordeStoredField -Record $rec -Name "transcriptPath"
        $inst = Get-HordeStoredField -Record $rec -Name "instance"
        $pane = Get-HordeStoredField -Record $rec -Name "pane"
        [void]$cands.Add([pscustomobject]@{
            sessionId = $id; label = $labelText; role = (Get-HordeFleetRole -Record $rec)
            parent = $(if ($parent.state -eq "known") { "" + $parent.value } else { "" })
            cwd = $cwdText; transcriptPath = $(if ($tp.state -eq "known") { "" + $tp.value } else { "" })
            instance = $(if ($inst.state -eq "known") { "" + $inst.value } else { "" })
            pane = $(if ($pane.state -eq "known") { "" + $pane.value } else { "" })
        })
    }
    return [pscustomobject]@{ candidates = @($cands); notes = @($notes) }
}

function New-HordeFleetRecord {
    # Build the record of a hibernation from the chosen candidates. Pure but for -ParkedExists, the one
    # read: a block (path -> bool) that says whether a session's PARKED-<label>.md is there yet.
    param([Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)][datetime]$At, [Parameter(Mandatory = $true)][object[]]$Chosen,
          [Parameter(Mandatory = $true)][string]$AgentName, [Parameter(Mandatory = $true)][string]$HostName, [Parameter(Mandatory = $true)]$Selection,
          $Placed = @{}, [scriptblock]$ParkedExists = $null)
    if ($null -eq $ParkedExists) { $ParkedExists = { param($p) Test-Path -LiteralPath $p -PathType Leaf } }
    $sessions = New-Object System.Collections.ArrayList
    foreach ($c in @($Chosen)) {
        $role = "" + $c.role
        if (@("orc", "warg") -cnotcontains $role) { $role = "other" }
        $s = [ordered]@{ sessionId = $c.sessionId; role = $role; cwd = $c.cwd; state = "recorded"; history = @([pscustomobject][ordered]@{ state = "recorded"; at = (Format-HordeFleetTime -At $At) }) }
        if ("" + $c.label -ne "") { $s["label"] = "" + $c.label }
        if ("" + $c.parent -cmatch $script:HordeFleetSessionPattern) { $s["parent"] = "" + $c.parent }
        if ("" + $c.transcriptPath -ne "") { $s["transcriptPath"] = "" + $c.transcriptPath }
        if ($null -ne $Placed -and $Placed.ContainsKey("" + $c.sessionId)) { $s["placement"] = $Placed["" + $c.sessionId] }
        $pr = $c.PSObject.Properties["process"]
        if ($null -ne $pr -and $null -ne $pr.Value -and "" + $pr.Value.pid -cmatch '\A[0-9]{1,10}\z' -and "" + $pr.Value.start -cmatch '\A[0-9]{1,19}\z') { $s["process"] = [pscustomobject][ordered]@{ pid = "" + $pr.Value.pid; start = "" + $pr.Value.start } }
        if ("" + $c.label -ne "" -and "" + $c.cwd -ne "" -and [System.IO.Path]::IsPathRooted("" + $c.cwd)) {
            $pf = Join-Path ("" + $c.cwd) ("PARKED-" + $c.label + ".md")
            if ([bool](& $ParkedExists $pf)) { $s["parkedFile"] = $pf }
        }
        [void]$sessions.Add([pscustomobject]$s)
    }
    return [pscustomobject][ordered]@{ schemaVersion = 1; id = $Id; createdAt = (Format-HordeFleetTime -At $At); agent = $AgentName; host = $HostName; selection = $Selection; sessions = @($sessions) }
}

function Invoke-HordeFleetRecord {
    # The whole of `horde fleet record`: read, choose, place, write. Returns { id; path; record; notes }.
    # Every outside read comes in through -Deps, so a test hands in its own and the real ones are
    # chosen in exactly one place (cli/commands/fleet.ps1):
    #   Now       ()        the time
    #   Registry  ()        Read-HordeRegistry's answer for the fleet registry
    #   Agent, Host         the fleet adapters (fleet/Port.ps1)
    #   ParkedExists (path) optional, whether a PARKED file is there
    param([Parameter(Mandatory = $true)]$Deps, [Parameter(Mandatory = $true)][scriptblock]$Selector, [Parameter(Mandatory = $true)]$Selection,
          [string[]]$Exclude = @(), [string]$HordeHome = (Get-HordeHome))
    $registry = & $Deps.Registry
    $snapshot = & $Deps.Agent.snapshot
    $found = Get-HordeFleetCandidates -Registry $registry -Agent $Deps.Agent -Snapshot $snapshot
    $chosen = @(& $Selector $found.candidates)
    $drop = @($Exclude | Where-Object { "" + $_ -ne "" })
    $chosen = @($chosen | Where-Object { $drop -cnotcontains ("" + $_.label) })
    if ($chosen.Count -eq 0) { throw "no running session was chosen, so nothing was recorded (an empty hibernation would read as one that had nothing to wake)" }
    $refs = @($chosen | ForEach-Object { [pscustomobject]@{ sessionId = $_.sessionId; instance = $_.instance; pane = $_.pane } })
    $notes = New-Object System.Collections.ArrayList
    foreach ($n in @($found.notes)) { [void]$notes.Add($n) }
    $placed = @{}
    $pl = & $Deps.Host.placement $refs
    if ($null -ne $pl -and $pl.state -eq "known") {
        $placed = $pl.value.placed
        foreach ($n in @($pl.value.notes)) { [void]$notes.Add("placement unknown for " + $n) }
    } else { [void]$notes.Add("no placement was read: " + $(if ($null -ne $pl) { $pl.reason } else { "the host answered nothing" })) }
    # Each chosen session's own process, as the harness names it (second review of PR 318, P1): a wake
    # then tells that very process still running under another id from a new one.
    $procs = @{}
    foreach ($r in @(& $Deps.Agent.running $snapshot)) { if ($null -ne $r -and "" + $r.sessionId -ne "") { $procs["" + $r.sessionId] = $r } }
    foreach ($c in $chosen) { if ($procs.ContainsKey("" + $c.sessionId)) { $c | Add-Member -NotePropertyName "process" -NotePropertyValue $procs["" + $c.sessionId] -Force } }
    $at = & $Deps.Now
    $id = New-HordeFleetHibernationId -At $at
    $dir = Join-Path (Get-HordeFleetHibernationsDir -HordeHome $HordeHome) $id
    $taken = "a hibernation was already recorded at " + $id + "; ids are the second they were taken, so try again in a second"
    # THE CLAIM IS ONE STEP (review of PR 318, finding a): record.json is created with CreateNew, which the
    # file system grants to one caller only, BEFORE anything else is done. A check followed by a folder
    # made with -Force let a second run of the same second in between, and the two merged into one record;
    # so there is no separate check: the claim is the only gate.
    # The empty file is then replaced whole by the writer; a run that fails after its claim removes it.
    [void](New-Item -ItemType Directory -Path $dir -Force)
    $path = Join-Path $dir "record.json"
    try { (New-Object System.IO.FileStream($path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)).Dispose() }
    catch {
        # A constructor's error reaches PowerShell wrapped; the file being there is an IOException inside.
        $e = $_.Exception
        while ($null -ne $e -and $e -isnot [System.IO.IOException]) { $e = $e.InnerException }
        if ($null -ne $e -and (Test-Path -LiteralPath $path)) { throw $taken }
        throw
    }
    try {
        $parked = $null
        if ($null -ne $Deps.PSObject.Properties["ParkedExists"]) { $parked = $Deps.ParkedExists }
        $record = New-HordeFleetRecord -Id $id -At $at -Chosen $chosen -AgentName $Deps.Agent.name -HostName $Deps.Host.name -Selection $Selection -Placed $placed -ParkedExists $parked
        $path = Write-HordeFleetRecord -Dir $dir -Record $record
    } catch {
        if ((Test-Path -LiteralPath $path -PathType Leaf) -and (Get-Item -LiteralPath $path).Length -eq 0) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
        if (@(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue).Count -eq 0) { Remove-Item -LiteralPath $dir -Force -ErrorAction SilentlyContinue }
        throw
    }
    return [pscustomobject]@{ id = $id; path = $path; record = $record; notes = @($notes) }
}
