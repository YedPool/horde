# core/projection - one read-only view of the Horde: every session any store knows, every field an
# answer, with where it came from. Step 2.2 of planning/migration-plan.html.
#
# WHAT IT COMPOSES, each an injected source so a test never reads this machine:
#   core/identity        every agent's own control files (X2, W8) and the process table (X5)
#   core/WezfleetState   the registry (W1), spawn claims (W2), runs, rosters and reports (W3-W6)
#   core/PaneSessions    Claude's pane-sessions files (X1), validated against schema/pane-session.v1
#   core/HostPort        the live handles (X4) and the host instance, through a port: nothing here
#                        names a terminal (D12). The real adapter comes later under hosts/<name>/.
#   a layout port        the layout saves (R1), compared against and never used as an answer
#
# WHAT IT NEVER DOES. It writes no file, opens none for writing, and never signals a process. Every
# foreign file is read through Read-HordeSharedText (core/ReadShared.ps1). test/test-projection.ps1
# proves both on the syntax tree of this file and every file it loads, and by holding every fixture
# file open while it reads.
#
# PRECEDENCE IS core/ownership.json, NOT CODE. Each field walks that table's read list for the field,
# in order, and the first store whose guard and "when" pass answers; a store that cannot be read adds
# its reason and the walk goes on; if nothing answers, the answer is unknown with every reason, or
# absent where the stores together prove there is none. The table is loaded, and the test fails if a
# field reads a store the table does not list for it.
#
# ONE RULE ADDED ACROSS EVERY STORED HANDLE, and why. The ownership pane row says the pane is "the live
# host handle ... never identity", and gives the registry's handle only when "written in this
# terminal instance". A roster or report handle is a number written at spawn time just as much, and
# handles are reused (YedPool/wezfleet 562f0e8, 0e1c75a), so the same test is applied to every stored
# handle: it answers only when the host lists it as live now, and it was written after the host
# instance started. That is the reading of the row that keeps a reused handle from naming two sessions;
# it is recorded as parity difference P-17 in planning/parity-2.3.md.
#
# THE LEAD'S DECISIONS OF 2026-09-30, implemented here:
#   1. Several sessions answering one handle: every claimant's pane is UNKNOWN with a reason naming
#      all of them, and a handle-claimed-twice fault lists them. wezfleet census picked the newest
#      silently (lib/Registry.ps1:395); that is parity difference P-14, not adopted.
#   2. No handle list, no host instance, or a host reporting none running: a stored handle cannot be
#      verified, so every pane is UNKNOWN with that reason - never absent.
#   3. The view lists every live handle, including handles no session answers.
#   4. Stray records in wezfleet's store are real cases, reported as faults; Horde never writes them.
#
# voluntary facts are provenance W5: what a session CHOSE to report (report, workState's events) is
# kept apart from what it DID (lastActivity, from command logs and transcripts), because 12 of about
# 28 status fields were voluntary and a quiet session read as a dead one (YedPool/wezfleet cf5c370).
#
# the roster groups sessions into runs: title, dependsOn, spawnedAt and the run itself still come
# from it (YedPool/wezfleet 562f0e8 "GROUPING is the roster's proper job"); only identity and the
# handle moved off it.
#
# wezfleet status spawns before it reads (commands/status.ps1:8, the pump starts every session whose
# dependencies are met), so nothing here is modelled on the command; the run snapshot function it
# calls, Get-WfRunSnapshot, is the parity target for step 2.3.

# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "ReadShared.ps1")
. (Join-Path $PSScriptRoot "Schema.ps1")
. (Join-Path $PSScriptRoot "Roles.ps1")
. (Join-Path $PSScriptRoot "Identity.ps1")
. (Join-Path $PSScriptRoot "WezfleetState.ps1")
. (Join-Path $PSScriptRoot "PaneSessions.ps1")
. (Join-Path $PSScriptRoot "HostPort.ps1")
. (Join-Path $PSScriptRoot "Faults.ps1")

$script:HordeUuidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
# wezfleet's terminal events, trusted outright (YedPool/wezfleet lib/Protocol.ps1:11, :187-188).
$script:HordeTerminalEvents = @("done", "failed")
# How recent activity must be to count as proof of life when the handle is gone: wezfleet's orphan
# grace (lib/Protocol.ps1 Get-WfSessionState -OrphanGraceSeconds 120).
$script:HordeOrphanGraceSeconds = 120

function Get-HordeProjectionProcessTable {
    # The process table as core/identity reads it, plus each process's command line: the only
    # involuntary witness to one conversation running in two processes (YedPool/wezfleet
    # lib/Common.ps1:656-662, "THE COMMAND LINE IS THE ONLY INVOLUNTARY WITNESS"). Read-only CIM.
    # Its pids are in the windows namespace; a pid a host gives from any other namespace is never
    # looked up here (core/HostPort.ps1, "PID AND CWD CARRY A NAMESPACE").
    return (Invoke-HordeRead -What "the process table" -Read {
        $t = @{}
        foreach ($p in @(Get-CimInstance -ClassName Win32_Process -Property ProcessId, Name, CreationDate, CommandLine -ErrorAction Stop)) {
            $created = $null
            if ($null -ne $p.CreationDate) { $created = ([datetime]$p.CreationDate).ToUniversalTime() }
            $t[[int]$p.ProcessId] = [pscustomobject]@{ pid = [int]$p.ProcessId; name = "$($p.Name)"; created = $created; commandLine = $p.CommandLine }
        }
        return $t
    })
}

function Get-HordeOwnershipRules {
    # core/ownership.json, Horde's own file: fields by name, and the provisional marks.
    param([string]$Path = (Join-Path $PSScriptRoot "ownership.json"))
    $doc = (Read-HordeSharedText -Path $Path) | ConvertFrom-Json
    $byName = @{}
    foreach ($f in @($doc.fields)) { $byName["$($f.name)"] = $f }
    return [pscustomobject]@{ doc = $doc; fields = $byName; required = @($doc.required | ForEach-Object { "$_" }); dropped = @($doc.dropped) }
}

# ------------------------------------------------------------------------------------------ answers

function New-HordeViewAnswer {
    # One answer in the view: a core/tristate answer plus its provenance and marks.
    param($Answer, [string]$Store = "", [string]$Field = "", [string]$Provisional = "", $Shadow = $null)
    Assert-HordeAnswer $Answer
    $src = $null
    if ($Store -ne "" -and $Answer.state -ne "unknown") { $src = [pscustomobject]@{ store = $Store; field = $Field } }
    return [pscustomobject]@{ PSTypeName = "Horde.ViewAnswer"; answer = $Answer; source = $src; provisional = $Provisional; shadow = $Shadow }
}

function New-HordeCandidate {
    # One read of the ownership table's list, for one session: the store, the field, and either the
    # answer it gave or the reason it did not apply (-Skip).
    param([string]$Store, [string]$Field, $Answer = $null, [string]$Skip = "")
    return [pscustomobject]@{ store = $Store; field = $Field; answer = $Answer; skip = $Skip }
}

function Resolve-HordeCandidates {
    # The first candidate that answers - known or absent - wins, with its store as provenance. An
    # unknown candidate adds its reason and the walk goes on, as the table's order says; if none
    # answers, -WhenNone decides (default: unknown, naming every reason).
    param($Candidates, $WhenNone = $null)
    $why = New-Object System.Collections.ArrayList
    foreach ($c in @($Candidates)) {
        if ($null -eq $c) { continue }
        if ($c.skip -ne "") { [void]$why.Add($c.store + " " + $c.field + ": " + $c.skip); continue }
        if ($c.answer.state -eq "unknown") { [void]$why.Add($c.store + " " + $c.field + ": " + $c.answer.reason); continue }
        return [pscustomobject]@{ answer = $c.answer; store = $c.store; field = $c.field; why = @($why) }
    }
    if ($null -ne $WhenNone) { return [pscustomobject]@{ answer = $WhenNone; store = ""; field = ""; why = @($why) } }
    $reason = "no store answers"
    if ($why.Count -gt 0) { $reason = "no store answers: " + (@($why) -join "; ") }
    return [pscustomobject]@{ answer = (New-HordeUnknown -Reason $reason); store = ""; field = ""; why = @($why) }
}

function ConvertFrom-HordeIsoTime {
    # A stored ISO 8601 time as a UTC [datetime], or $null. A time with no zone cannot be placed and
    # is not a time (core/Tristate.ps1 ConvertFrom-HordeAnswerRecord).
    param($Text)
    if ($Text -is [datetime]) { if ($Text.Kind -eq [System.DateTimeKind]::Unspecified) { return $null }; return $Text.ToUniversalTime() }
    $parsed = [datetime]::MinValue
    if (-not [datetime]::TryParse("$Text", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) { return $null }
    if ($parsed.Kind -eq [System.DateTimeKind]::Unspecified) { return $null }
    return $parsed.ToUniversalTime()
}

function ConvertTo-HordeIsoText { param([datetime]$Time) return $Time.ToUniversalTime().ToString("o") }

function Get-HordeStoredField {
    # An ENGINE field of a wezfleet record, translated the way schema/session-record.v1 says: a
    # field that is not there, null, or an empty string is ABSENT - the store was read and holds
    # none - because wezfleet writes "" for none (fleetSessionId, lastTool, owner).
    param($Record, [string]$Name, [string]$What = "the record")
    $p = $Record.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value -or ($p.Value -is [string] -and $p.Value -eq "")) { return (New-HordeAbsent -Note ($What + " has no " + $Name)) }
    return (New-HordeKnown -Value $p.Value)
}

function Get-HordeAgentField {
    # An AGENT field from a file that is not the agent's own control file: missing is unknown.
    param($Record, [string]$Name)
    $f = Get-HordeField -Record $Record -Name $Name
    if ($f.state -eq "known" -and $f.value -is [string] -and $f.value -eq "") { return (New-HordeUnknown -Reason ("the record's '" + $Name + "' is empty")) }
    return $f
}

# ----------------------------------------------------------------------------------- the host side

function Get-HordeHostContext {
    # What the host lets us verify. Returns { handles; instance; live; verify } where verify is an
    # answer: known $true when a stored handle CAN be checked, unknown with the reason otherwise
    # (the lead's decision 2). live maps handle text to its row when the list is known.
    param($HandlesAnswer, $InstanceAnswer)
    $live = @{}
    if ($HandlesAnswer.state -eq "known") { foreach ($h in @($HandlesAnswer.value)) { $live[$h.handle] = $h } }
    $verify = New-HordeKnown -Value $true
    if ($HandlesAnswer.state -ne "known") { $verify = New-HordeUnknown -Reason ("the host's live handles are unknown (" + $HandlesAnswer.reason + "), so a stored handle cannot be verified") }
    elseif ($InstanceAnswer.state -ne "known") { $verify = New-HordeUnknown -Reason ("the host instance is unknown (" + $InstanceAnswer.reason + "), so a stored handle cannot be verified") }
    elseif ($InstanceAnswer.value.running -eq 0) { $verify = New-HordeUnknown -Reason "no terminal instance is running, so a stored handle cannot be verified" }
    elseif ($InstanceAnswer.value.ambiguous) { $verify = New-HordeUnknown -Reason "the host instance is ambiguous, and an ambiguous instance trusts no stored handle" }
    elseif (-not $InstanceAnswer.value.startedAtOffered) { $verify = New-HordeUnknown -Reason "the host does not offer instance.startedAt, so whether a record was written in this instance cannot be checked" }
    elseif ($null -eq $InstanceAnswer.value.startedAt) { $verify = New-HordeUnknown -Reason "the host did not say when its instance started, so whether a record was written in it cannot be checked" }
    return [pscustomobject]@{ handles = $HandlesAnswer; instance = $InstanceAnswer; live = $live; verify = $verify }
}

function Test-HordeWrittenInInstance {
    # Is a stored handle, written at $Written and naming $RecordInstance, evidence about THIS host
    # instance? The rule wezfleet learned after a restart named the wrong session for 7 of 10 handles
    # (YedPool/wezfleet 0e1c75a; lib/Common.ps1:611-641): the record's instance must be this one when
    # it names one, and it must have been written after this instance started. Returns "" when it
    # is, else the reason it is not. Only called once Get-HordeHostContext has said verify is known.
    param($Context, [string]$RecordInstance, $Written, [string]$What)
    $inst = $Context.instance.value
    if ($RecordInstance -ne "" -and "$($inst.id)" -ne "" -and $RecordInstance -cne "$($inst.id)") { return ($What + " names instance " + $RecordInstance + ", not this one (" + $inst.id + ")") }
    $at = ConvertFrom-HordeIsoTime $Written
    if ($null -eq $at) { return ($What + " has no placeable write time") }
    if ($at -lt $inst.startedAt) { return ($What + " was written " + (ConvertTo-HordeIsoText $at) + ", before this instance started " + (ConvertTo-HordeIsoText $inst.startedAt)) }
    return ""
}

function Get-HordeStoredHandleCandidate {
    # One stored handle as a candidate for a session's pane: it answers only when the host can be
    # asked, the handle is live now, and it was written in this instance (see the file header).
    param($Context, [string]$Store, [string]$Field, $Handle, [string]$RecordInstance, $Written, [string]$What)
    $h = ConvertTo-HordeHandleText $Handle
    if ($null -eq $h) { return (New-HordeCandidate -Store $Store -Field $Field -Skip ($What + " names no handle")) }
    if ($Context.verify.state -ne "known") { return (New-HordeCandidate -Store $Store -Field $Field -Answer (New-HordeUnknown -Reason ($What + " names handle " + $h + ", and " + $Context.verify.reason))) }
    $notHere = Test-HordeWrittenInInstance -Context $Context -RecordInstance $RecordInstance -Written $Written -What $What
    if ($notHere -ne "") { return (New-HordeCandidate -Store $Store -Field $Field -Skip $notHere) }
    if (-not $Context.live.ContainsKey($h)) { return (New-HordeCandidate -Store $Store -Field $Field -Skip ($What + " names handle " + $h + ", which is not live")) }
    return (New-HordeCandidate -Store $Store -Field $Field -Answer (New-HordeKnown -Value $h))
}

function Get-HordePaneFileVerdicts {
    # Every pane-sessions file judged against core/ownership.json's X1 guard, once. Returns
    # { bySession; findings; state } where bySession maps a session id to the ONE file that may answer
    # for it, and findings are { kind; subjects; detail } for session-in-two-handles and
    # pane-sessions-hijack. state is an answer: unknown when the files cannot be judged at all.
    #
    # The guard, in order: a numeric handle and a well-formed session_id (the reader and the schema);
    # at most one host instance running, because the file names no instance (YedPool/wezfleet 88aab20);
    # written after this instance started (0e1c75a); its handle live; the only live file naming that
    # session - the finder's rule, stricter than census's (lib/Registry.ps1:667-673); and no live
    # control-file session holding that handle in the registry, the hijack a hand-started session made
    # by inheriting another pane's number (YedPool/wezfleet f09f4e1).
    param($PaneRead, $Context, $Registry, $VerifiedLive)
    $bySession = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    $findings = New-Object System.Collections.ArrayList
    if ($Context.verify.state -ne "known") { return [pscustomobject]@{ bySession = $bySession; findings = $findings.ToArray(); state = (New-HordeUnknown -Reason ("no pane-sessions file can be judged: " + $Context.verify.reason)) } }
    # running counts instances - the namespaces handles are unique in - not server processes
    # (core/HostPort.ps1), so a host with one server per session reports 1 here and its files are read.
    if ($Context.instance.value.running -gt 1) { return [pscustomobject]@{ bySession = $bySession; findings = $findings.ToArray(); state = (New-HordeUnknown -Reason ("" + $Context.instance.value.running + " host instances are running, and a pane-sessions file names no instance, so none can be attributed")) } }
    if ($PaneRead.complete.state -ne "known") { return [pscustomobject]@{ bySession = $bySession; findings = $findings.ToArray(); state = (New-HordeUnknown -Reason ("the pane-sessions listing is incomplete (" + $PaneRead.complete.reason + "), so no file can be shown to be the only one naming its session")) } }
    $liveFiles = New-Object System.Collections.ArrayList
    foreach ($f in @($PaneRead.files)) {
        if (-not $Context.live.ContainsKey($f.handle)) { continue }
        if ($f.writtenUtc -lt $Context.instance.value.startedAt) { continue }
        [void]$liveFiles.Add($f)
    }
    $groups = @{}
    foreach ($f in $liveFiles) {
        $k = $f.sessionId.ToLowerInvariant()
        if (-not $groups.ContainsKey($k)) { $groups[$k] = New-Object System.Collections.ArrayList }
        [void]$groups[$k].Add($f)
    }
    # Which verified-live session the registry puts in each handle, for the hijack check.
    $holder = @{}
    if ($VerifiedLive.state -eq "known") {
        foreach ($sid in @($VerifiedLive.value)) {
            if (-not $Registry.records.ContainsKey($sid)) { continue }
            $r = $Registry.records[$sid].record
            $ret = Get-HordeField -Record $r -Name "retired"
            if ($ret.state -eq "known" -and [bool]$ret.value) { continue }
            $h = ConvertTo-HordeHandleText (Get-HordeField -Record $r -Name "pane").value
            if ($null -eq $h) { continue }
            $ri = Get-HordeField -Record $r -Name "instance"
            $ls = Get-HordeField -Record $r -Name "lastSeen"
            $inInstance = Test-HordeWrittenInInstance -Context $Context -RecordInstance $(if ($ri.state -eq "known") { "$($ri.value)" } else { "" }) -Written $ls.value -What "registry record"
            if ($inInstance -eq "") { $holder[$h] = $sid }
        }
    }
    foreach ($k in $groups.Keys) {
        $g = @($groups[$k])
        if ($g.Count -gt 1) {
            [void]$findings.Add([pscustomobject]@{ kind = "session-in-two-handles"; subjects = @(@($g[0].sessionId) + @($g | ForEach-Object { "handle " + $_.handle })); detail = ("pane-sessions files for handles " + (@($g | ForEach-Object { $_.handle }) -join ", ") + " all name session " + $g[0].sessionId + "; none of them answers") })
            continue
        }
        $f = $g[0]
        if ($holder.ContainsKey($f.handle) -and $holder[$f.handle] -ine $f.sessionId) {
            [void]$findings.Add([pscustomobject]@{ kind = "pane-sessions-hijack"; subjects = @($holder[$f.handle], $f.sessionId, ("handle " + $f.handle)); detail = ("the pane-sessions file for handle " + $f.handle + " names session " + $f.sessionId + ", while running session " + $holder[$f.handle] + " holds that handle in the registry; the file does not answer") })
            continue
        }
        $bySession[$f.sessionId] = $f
    }
    return [pscustomobject]@{ bySession = $bySession; findings = $findings.ToArray(); state = (New-HordeKnown -Value $true) }
}

# ------------------------------------------------------------------------------ transcripts, layout

function Get-HordeTranscriptIndex {
    # Session id -> every <id>.jsonl in any project folder, listed by name only (no transcript is
    # opened: they hold the session's raw text). For a session no longer running there is no control
    # file to derive the folder from, and one id can be filed in many folders, so the table takes
    # the file only when exactly one exists (core/ownership.json transcriptPath derived).
    param([string]$ProjectsDir)
    $index = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    if (-not (Test-Path -LiteralPath $ProjectsDir -PathType Container)) { return [pscustomobject]@{ index = $index; complete = (New-HordeUnknown -Reason ("there is no projects directory at " + $ProjectsDir)) } }
    try {
        foreach ($d in @(Get-ChildItem -LiteralPath $ProjectsDir -Directory -ErrorAction Stop)) {
            foreach ($f in @(Get-ChildItem -LiteralPath $d.FullName -File -Filter "*.jsonl" -ErrorAction Stop)) {
                $sid = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
                if (-not $index.ContainsKey($sid)) { $index[$sid] = New-Object System.Collections.ArrayList }
                [void]$index[$sid].Add($f.FullName)
            }
        }
    } catch { return [pscustomobject]@{ index = $index; complete = (New-HordeUnknown -Reason "the projects directory could not be listed" -ErrorRecord $_) } }
    return [pscustomobject]@{ index = $index; complete = (New-HordeKnown -Value $true) }
}

function Read-HordeLayoutSaves {
    # The layout saves (R1) through an injected port: a script block returning { sessionId; argv }
    # rows. Shadow only - a layout save is compared against, never used as an answer (D3;
    # core/ownership.json resumeCommand). No port means the saves are unknown, not empty.
    param($LayoutPort)
    if ($null -eq $LayoutPort) { return (New-HordeUnknown -Reason "no layout port is attached") }
    if ($LayoutPort -isnot [scriptblock]) { throw "-LayoutPort must be a script block returning { sessionId; argv } rows" }
    $got = Invoke-HordeRead -What "the layout saves" -Read { return , @(& $LayoutPort | ForEach-Object { $_ }) }
    if ($got.state -ne "known") { return $got }
    $by = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in @($got.value)) {
        $s = Get-HordeField -Record $row -Name "sessionId"
        $a = Get-HordeField -Record $row -Name "argv"
        if ($s.state -ne "known" -or $a.state -ne "known") { continue }
        if (-not $by.ContainsKey("$($s.value)")) { $by["$($s.value)"] = New-Object System.Collections.ArrayList }
        [void]$by["$($s.value)"].Add(("" + (@($a.value) -join " ")))
    }
    return (New-HordeKnown -Value $by)
}

# ------------------------------------------------------------------------------------------ runs

function Get-HordeReportLinks {
    # claude session id -> every (run, fleet id) whose event log names it. The event log carries
    # session.claudeSessionId (YedPool/wezfleet lib/Protocol.ps1 Write-WfEvent); that is the only
    # link from a roster entry to a session, since a roster names fleet ids.
    param($Runs)
    $links = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($run in @($Runs.runs)) {
        foreach ($fid in @($run.sessions.Keys)) {
            foreach ($e in @($run.sessions[$fid].events.events)) {
                $s = Get-HordeField -Record $e -Name "session"
                if ($s.state -ne "known") { continue }
                $c = Get-HordeField -Record $s.value -Name "claudeSessionId"
                if ($c.state -ne "known" -or "$($c.value)" -eq "") { continue }
                $k = "$($c.value)"
                if (-not $links.ContainsKey($k)) { $links[$k] = New-Object System.Collections.ArrayList }
                if (@($links[$k] | Where-Object { $_.run.dir -eq $run.dir -and $_.fleetId -eq $fid }).Count -eq 0) { [void]$links[$k].Add([pscustomobject]@{ run = $run; fleetId = $fid }) }
            }
        }
    }
    return $links
}

function Resolve-HordeRun {
    # The run a fleet id belongs to, by the ownership runId rule (YedPool/wezfleet lib/Common.ps1:331-347):
    # among OPEN runs whose roster lists the id, the one that spawned it; two open runs that both
    # spawned it, or several open runs none of which did, are ambiguous and reported, never chosen; a
    # closed run is used only when no open run lists it - and SEVERAL closed runs are ambiguous too,
    # where wezfleet returned the first (lib/Common.ps1:349; parity difference P-22).
    # Returns { answer (known run object, absent, or unknown); ambiguous (run ids) }.
    param($Runs, [string]$FleetId)
    $hits = New-Object System.Collections.ArrayList
    $unsure = New-Object System.Collections.ArrayList
    $listing = @()
    if ($Runs.byFleetId.ContainsKey($FleetId)) { $listing = @($Runs.byFleetId[$FleetId]) }
    foreach ($run in $listing) {
        $e = @($run.entries | Where-Object { $_.id -ceq $FleetId })
        if ($e.Count -eq 0) { continue }
        if ($run.closed.state -ne "known") { [void]$unsure.Add($run.runId); continue }
        $sp = Get-HordeField -Record $e[0].entry -Name "spawned"
        $spawned = $true
        if ($sp.state -eq "known") { $spawned = [bool]$sp.value }
        $pn = Get-HordeField -Record $e[0].entry -Name "pane"
        if ($pn.state -eq "known") { try { if ([int]$pn.value -lt 0) { $spawned = $false } } catch { } }
        [void]$hits.Add([pscustomobject]@{ run = $run; closed = [bool]$run.closed.value; spawned = $spawned })
    }
    if ($unsure.Count -gt 0) { return [pscustomobject]@{ answer = (New-HordeUnknown -Reason ("the manifest of run " + (@($unsure) -join ", ") + ", which lists " + $FleetId + ", could not be read")); ambiguous = @() } }
    $open = @($hits | Where-Object { -not $_.closed })
    $openSpawned = @($open | Where-Object { $_.spawned })
    if ($openSpawned.Count -eq 1) { return [pscustomobject]@{ answer = (New-HordeKnown -Value $openSpawned[0].run); ambiguous = @() } }
    if ($openSpawned.Count -gt 1) { $ids = @($openSpawned | ForEach-Object { $_.run.runId }); return [pscustomobject]@{ answer = (New-HordeUnknown -Reason ("fleet id " + $FleetId + " was spawned by " + $ids.Count + " open runs (" + ($ids -join ", ") + "); which one is not chosen")); ambiguous = $ids } }
    if ($open.Count -eq 1) { return [pscustomobject]@{ answer = (New-HordeKnown -Value $open[0].run); ambiguous = @() } }
    if ($open.Count -gt 1) { $ids = @($open | ForEach-Object { $_.run.runId }); return [pscustomobject]@{ answer = (New-HordeUnknown -Reason ("fleet id " + $FleetId + " is listed by " + $ids.Count + " open runs, none of which spawned it (" + ($ids -join ", ") + ")")); ambiguous = $ids } }
    if ($hits.Count -eq 1) { return [pscustomobject]@{ answer = (New-HordeKnown -Value $hits[0].run); ambiguous = @() } }
    if ($hits.Count -gt 1) { $ids = @($hits | ForEach-Object { $_.run.runId }); return [pscustomobject]@{ answer = (New-HordeUnknown -Reason ("fleet id " + $FleetId + " is listed only by closed runs, " + $ids.Count + " of them (" + ($ids -join ", ") + "); which one is not chosen")); ambiguous = $ids } }
    if ($Runs.rostersComplete.state -ne "known") { return [pscustomobject]@{ answer = (New-HordeUnknown -Reason ("no readable roster lists fleet id " + $FleetId + ", and the rosters are incomplete (" + $Runs.rostersComplete.reason + ")")); ambiguous = @() } }
    return [pscustomobject]@{ answer = (New-HordeAbsent -Note ("no roster lists fleet id " + $FleetId)); ambiguous = @() }
}

# ---------------------------------------------------------------------------------- the session

function Get-HordeSessionIds {
    # Every session id a store knows, by the ownership sessionId row: the agents' control files, the
    # registry (a record's file name, corrupt ones included, since the file still names the session),
    # a pane-sessions file that passed the guard, and a report's claudeSessionId. Never the
    # environment: CLAUDE_CODE_SESSION_ID is inherited, so it never identifies another session
    # (YedPool/wezfleet lib/Protocol.ps1:438-441, which mapped the caller's own id onto every pane
    # with no file - parity difference P-02).
    param($Identity, $Registry, $PaneVerdicts, $ReportLinks)
    $seen = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($k in @($Identity.records.Keys)) { if (-not $seen.ContainsKey($k)) { $seen[$k] = "X2" } }
    foreach ($d in @($Identity.duplicates)) { if (-not $seen.ContainsKey($d.sessionId)) { $seen[$d.sessionId] = "X2" } }
    foreach ($k in @($Registry.records.Keys)) { if (-not $seen.ContainsKey($k)) { $seen[$k] = "W1" } }
    foreach ($k in @($Registry.unreadable)) { if ((Test-HordeSessionId $k) -and -not $seen.ContainsKey($k)) { $seen[$k] = "W1" } }
    foreach ($k in @($PaneVerdicts.bySession.Keys)) { if (-not $seen.ContainsKey($k)) { $seen[$k] = "X1" } }
    foreach ($k in @($ReportLinks.Keys)) { if ((Test-HordeSessionId $k) -and -not $seen.ContainsKey($k)) { $seen[$k] = "W5" } }
    return $seen
}

function Get-HordeViewValueSchemas {
    # field name -> the schema of its value in schema/session-view.v1, so every answer the view gives
    # is checked against the type it promises before it is given (a value that does not fit becomes
    # unknown, naming why, instead of an invalid document).
    param($ViewSchema)
    $out = @{}
    $fieldsSchema = $ViewSchema.definitions.session.properties.fields.properties
    foreach ($p in $fieldsSchema.PSObject.Properties) {
        $name = "$($p.Value.'$ref')".Substring("#/definitions/".Length)
        $vp = $ViewSchema.definitions.PSObject.Properties[$name].Value.properties.PSObject.Properties["value"]
        if ($null -ne $vp) { $out[$p.Name] = $vp.Value }
    }
    return $out
}

function Limit-HordeViewValue {
    # A known answer whose value does not fit the field's type in the view becomes unknown, naming
    # the store and the problem. schema/session-record.v1's types are the view's for engine fields, so
    # a wezfleet value the stored record would refuse (a label of the wrong shape, a parent that is not
    # a session id, a lastSeen with no zone) is never passed on as known.
    param($Resolved, [string]$Field, $ValueSchemas, $ViewSchema)
    if ($Resolved.answer.state -ne "known" -or -not $ValueSchemas.ContainsKey($Field)) { return $Resolved }
    $problems = @(Test-HordeSchema -Value $Resolved.answer.value -Schema $ValueSchemas[$Field] -Path ('$.' + $Field) -Root $ViewSchema)
    if ($problems.Count -eq 0) { return $Resolved }
    $Resolved.answer = New-HordeUnknown -Reason ($Resolved.store + " " + $Resolved.field + " holds a value the view cannot carry: " + ($problems -join "; "))
    $Resolved.store = ""
    return $Resolved
}

function Read-HordeControlExtras {
    # The control file behind an identity record, read again for the fields identity does not carry
    # (the agent's updatedAt, a codex file's wezfleetSessionId). $null when it cannot be read.
    param($Record)
    if ($null -eq $Record) { return $null }
    try { return ((Read-HordeSharedText -Path $Record.source) | ConvertFrom-Json) } catch { return $null }
}

function Get-HordeResumeProcesses {
    # pid rows whose command line resumes this session (--resume <id> or -r <id>), from the process
    # table: the X5 read for pid, procStart and startedAt when "its --resume id matches".
    param($Processes, [string]$SessionId)
    $out = New-Object System.Collections.ArrayList
    if ($Processes.state -ne "known") { return $out.ToArray() }
    foreach ($p in $Processes.value.Values) {
        $cl = $p.PSObject.Properties["commandLine"]
        if ($null -eq $cl -or $null -eq $cl.Value) { continue }
        $m = [regex]::Match("$($cl.Value)", '(?:--resume|-r)(?:\s+|=)"?([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})')
        if ($m.Success -and $m.Groups[1].Value -ieq $SessionId) { [void]$out.Add($p) }
    }
    return $out.ToArray()
}

function Resolve-HordeField {
    # Resolve-HordeCandidates, then the absent-or-unknown rule for when no store answers: -WhenNone
    # (usually absent) is given ONLY when every store was read and simply holds nothing for this
    # session. If any store could not be read, or its guard could not be checked, the answer is
    # unknown: "none found" over a store with a hole in it is not "none".
    param($Candidates, $WhenNone = $null)
    $r = Resolve-HordeCandidates -Candidates $Candidates
    if ($r.answer.state -ne "unknown" -or $null -eq $WhenNone) { return $r }
    $anyUnknown = @(@($Candidates) | Where-Object { $null -ne $_ -and $_.skip -eq "" -and $_.answer.state -eq "unknown" }).Count -gt 0
    if ($anyUnknown) { return $r }
    return [pscustomobject]@{ answer = $WhenNone; store = ""; field = ""; why = $r.why }
}

function Get-HordeRegistryCandidate {
    # A W1 field for one session, or why W1 does not apply. Engine fields read empty as absent;
    # -Agentish reads a missing field as unknown instead.
    param($S, [string]$Field, [switch]$Agentish)
    if ($S.w1Unreadable) { return (New-HordeCandidate -Store "W1" -Field $Field -Answer (New-HordeUnknown -Reason "the session's registry record could not be read")) }
    if ($null -eq $S.w1) { return (New-HordeCandidate -Store "W1" -Field $Field -Skip "no registry record names this session") }
    if ($Agentish) { return (New-HordeCandidate -Store "W1" -Field $Field -Answer (Get-HordeAgentField -Record $S.w1 -Name $Field)) }
    return (New-HordeCandidate -Store "W1" -Field $Field -Answer (Get-HordeStoredField -Record $S.w1 -Name $Field -What "the registry record"))
}

function Get-HordeIdentityCandidate {
    # An agent field from the session's own control file: X2 for claude, W8 for codex.
    param($S, [string]$Field, [string]$StoreField = $Field)
    if ($S.dupe) { return (New-HordeCandidate -Store "X2" -Field $StoreField -Answer (New-HordeUnknown -Reason "more than one control file names this session, and none is chosen (core/identity)")) }
    if ($null -eq $S.rec) { return (New-HordeCandidate -Store "X2" -Field $StoreField -Skip "no agent control file names this session") }
    $store = "X2"
    if ($S.rec.fields.agent.state -eq "known" -and "$($S.rec.fields.agent.value)" -ceq "codex") { $store = "W8" }
    return (New-HordeCandidate -Store $store -Field $StoreField -Answer $S.rec.fields[$Field])
}

function Get-HordeNotRunning {
    # Absent, for a live-process field of a session no control file names, when both agents'
    # listings are whole: every running claude session has a control file (10 of 10, 2026-09-30).
    # Unknown otherwise, since the missing file may be the unreadable one.
    param($C, [string]$What)
    foreach ($a in @("claude", "codex")) {
        if ($C.identity.complete[$a].state -ne "known") { return (New-HordeUnknown -Reason ("no readable control file names this session, and the " + $a + " listing is incomplete (" + $C.identity.complete[$a].reason + ")")) }
    }
    return (New-HordeAbsent -Note ("no control file names this session, so it is not running and has no " + $What))
}

function Get-HordeReportEvents {
    # The event log of the session's own run folder, when its run is known.
    param($S)
    if ($null -eq $S.runFolder) { return $null }
    return $S.runFolder.events
}

function Get-HordeLastReportField {
    # The newest report's session.<Name>, from the run folder's log, as a W5 candidate.
    param($S, [string]$Name, [string]$Field)
    $ev = Get-HordeReportEvents $S
    if ($null -eq $ev) { return (New-HordeCandidate -Store "W5" -Field $Field -Skip "the session is in no known run") }
    if ($ev.complete.state -ne "known") { return (New-HordeCandidate -Store "W5" -Field $Field -Answer $ev.complete) }
    $list = @($ev.events)
    for ($i = $list.Count - 1; $i -ge 0; $i--) {
        $sess = Get-HordeField -Record $list[$i] -Name "session"
        if ($sess.state -ne "known") { continue }
        $v = Get-HordeField -Record $sess.value -Name $Name
        if ($v.state -eq "known" -and "$($v.value)" -ne "") { return (New-HordeCandidate -Store "W5" -Field $Field -Answer (New-HordeKnown -Value $v.value)) }
    }
    return (New-HordeCandidate -Store "W5" -Field $Field -Skip ("no report carries " + $Name))
}

function Get-HordeRosterCandidate {
    # A field of the session's roster entry (W4), or of its run manifest entry (W3 with -Manifest).
    param($S, [string]$Name, [string]$Field, [switch]$Manifest, [switch]$MissingIsUnknown)
    $store = "W4"; if ($Manifest) { $store = "W3" }
    if ($null -eq $S.run) { return (New-HordeCandidate -Store $store -Field $Field -Skip "the session is in no known run") }
    $entry = $null
    if ($Manifest) {
        if ($null -eq $S.run.manifest) { return (New-HordeCandidate -Store $store -Field $Field -Answer (New-HordeUnknown -Reason "the run manifest could not be read")) }
        $ms = $S.run.manifest.PSObject.Properties["sessions"]
        if ($null -ne $ms) { foreach ($x in @($ms.Value)) { if ($null -ne $x -and $null -ne $x.PSObject.Properties["id"] -and "$($x.id)" -ceq $S.fleetId) { $entry = $x; break } } }
    } else { $entry = $S.rosterEntry }
    if ($null -eq $entry) { return (New-HordeCandidate -Store $store -Field $Field -Skip "the run lists no entry for the session") }
    $p = $entry.PSObject.Properties[$Name]
    if ($null -eq $p) {
        if ($MissingIsUnknown) { return (New-HordeCandidate -Store $store -Field $Field -Answer (New-HordeUnknown -Reason ("the entry has no " + $Name + ", which entries written before the field lack; that is unknown, never fresh"))) }
        return (New-HordeCandidate -Store $store -Field $Field -Answer (New-HordeAbsent -Note ("the entry has no " + $Name)))
    }
    if ($null -eq $p.Value -or ($p.Value -is [string] -and $p.Value -eq "")) { return (New-HordeCandidate -Store $store -Field $Field -Answer (New-HordeAbsent -Note ("the entry's " + $Name + " is empty"))) }
    return (New-HordeCandidate -Store $store -Field $Field -Answer (New-HordeKnown -Value $p.Value))
}

function Get-HordeClaimCandidate {
    # A W2 field, under the table's guard: the claim for the session's handle, read only while the
    # session has no registry record (the hook consumes a claim on first sight), spawned at most
    # 10080 minutes ago, and naming the session's cwd by Claude path key, ignoring case, when both are
    # recorded (YedPool/wezfleet lib/Registry.ps1:1269-1307).
    #
    # the cwd guard barely discriminates: most sessions share a handful of directories (wezfleet
    # measured "94% of the time" the same cwd, lib/Registry.ps1:578-583), so it is one guard among
    # several and never the only one; a claim also needs the session's live handle and no record.
    param($S, $C, [string]$Name, [string]$Field)
    if ($S.w1Unreadable -or $null -ne $S.w1) { return (New-HordeCandidate -Store "W2" -Field $Field -Skip "the session has a registry record, so its claim was consumed") }
    if ($S.pane.answer.state -ne "known") { return (New-HordeCandidate -Store "W2" -Field $Field -Skip "the session's handle is not known, so no claim can be matched to it") }
    $h = "$($S.pane.answer.value)"
    if (-not $C.wf.claims.claims.ContainsKey($h)) {
        if ($C.wf.claims.complete.state -ne "known") { return (New-HordeCandidate -Store "W2" -Field $Field -Answer (New-HordeUnknown -Reason ("the claims are incomplete (" + $C.wf.claims.complete.reason + ")"))) }
        return (New-HordeCandidate -Store "W2" -Field $Field -Skip ("there is no claim for handle " + $h))
    }
    $claim = $C.wf.claims.claims[$h].claim
    $spawned = $null
    if ($null -ne $claim.PSObject.Properties["spawnedAt"]) { $spawned = $claim.spawnedAt }
    if (-not (Test-HordeClaimPending -Claim ([pscustomobject]@{ spawnedAt = $spawned }) -Now $C.now)) {
        return (New-HordeCandidate -Store "W2" -Field $Field -Skip ("the claim for handle " + $h + " is past wezfleet's 10080-minute backstop, or has no spawn time"))
    }
    $cc = $claim.PSObject.Properties["cwd"]
    if ($null -ne $cc -and "$($cc.Value)" -ne "" -and $S.cwdForClaim -ne "") {
        if ((ConvertTo-HordeClaudeProjectKey -Cwd "$($cc.Value)") -ine (ConvertTo-HordeClaudeProjectKey -Cwd $S.cwdForClaim)) {
            return (New-HordeCandidate -Store "W2" -Field $Field -Skip ("the claim for handle " + $h + " names another directory"))
        }
    }
    return (New-HordeCandidate -Store "W2" -Field $Field -Answer (Get-HordeStoredField -Record $claim -Name $Name -What "the claim"))
}

function New-HordeSessionState {
    # The per-session working set: which record each store holds for it, and whether it runs.
    param($C, [string]$Id)
    $rec = $null
    if ($C.identity.records.ContainsKey($Id)) { $rec = $C.identity.records[$Id] }
    $w1 = $null
    if ($C.wf.registry.records.ContainsKey($Id)) { $w1 = $C.wf.registry.records[$Id].record }
    $x1 = $null
    if ($C.paneVerdicts.bySession.ContainsKey($Id)) { $x1 = $C.paneVerdicts.bySession[$Id] }
    # RUNNING means a control file says so: process-verified, or a status the agent wrote within its
    # TTL (codex writes no pid). Used only to choose unknown over absent for a handle.
    $alive = $false
    if ($null -ne $rec -and "$($rec.processCheck)" -ceq "verified") { $alive = $true }
    elseif ($null -ne $rec -and $rec.fields.liveStatus.state -eq "known" -and @("idle", "busy") -ccontains "$($rec.fields.liveStatus.value)") { $alive = $true }
    $retired = $false
    if ($null -ne $w1) { $rt = Get-HordeField -Record $w1 -Name "retired"; $retired = ($rt.state -eq "known" -and [bool]$rt.value) }
    return [pscustomobject]@{
        id = $Id; rec = $rec; dupe = (@($C.identity.duplicates | Where-Object { $_.sessionId -ieq $Id }).Count -gt 0)
        w1 = $w1; w1Unreadable = $C.wf.registry.unreadable.Contains($Id); w1Retired = $retired; x1 = $x1; alive = $alive
        pane = $null; fleetId = ""; run = $null; rosterEntry = $null; runFolder = $null; runAmbiguous = @(); cwdForClaim = ""; fields = [ordered]@{}
    }
}

function Set-HordeRunLink {
    # Which run folder the session's reports live in, for a fleet id: the run Resolve-HordeRun picks,
    # its roster entry, and its sessions\<fleet id> folder.
    param($S, $C, [string]$FleetId)
    $S.fleetId = $FleetId; $S.run = $null; $S.rosterEntry = $null; $S.runFolder = $null
    if ($FleetId -eq "") { return }
    $r = Resolve-HordeRun -Runs $C.wf.runs -FleetId $FleetId
    if ($r.answer.state -ne "known") { return }
    $S.run = $r.answer.value
    foreach ($e in @($S.run.entries)) { if ($e.id -ceq $FleetId) { $S.rosterEntry = $e.entry; break } }
    if ($S.run.sessions.ContainsKey($FleetId)) { $S.runFolder = $S.run.sessions[$FleetId] }
}

function Get-HordePreliminaryFleetId {
    # The fleet id used to find a stored handle in a report or roster, before the claim can be read
    # (the claim needs the handle): the registry's, else the one run whose report names the session.
    param($S, $C)
    if ($null -ne $S.w1) { $f = Get-HordeStoredField -Record $S.w1 -Name "fleetSessionId"; if ($f.state -eq "known") { return "$($f.value)" } }
    if ($C.links.ContainsKey($S.id)) { $l = @($C.links[$S.id]); if ($l.Count -eq 1) { return $l[0].fleetId } }
    return ""
}

function Get-HordePaneAnswer {
    # A session's handle, by the pane row: W1 (not retired, this instance), X1 (guarded), W5, W4 -
    # each only when live and written in this instance (the file header). Claimants are settled
    # afterwards, across sessions, by Get-HordeProjection.
    param($S, $C)
    $cands = New-Object System.Collections.ArrayList
    if ($S.w1Unreadable) { [void]$cands.Add((New-HordeCandidate -Store "W1" -Field "pane" -Answer (New-HordeUnknown -Reason "the session's registry record could not be read"))) }
    elseif ($null -eq $S.w1) { [void]$cands.Add((New-HordeCandidate -Store "W1" -Field "pane" -Skip "no registry record names this session")) }
    elseif ($S.w1Retired) { [void]$cands.Add((New-HordeCandidate -Store "W1" -Field "pane" -Skip "the registry record is retired, and a retired record holds no handle")) }
    else {
        $ri = Get-HordeField -Record $S.w1 -Name "instance"
        $ls = Get-HordeField -Record $S.w1 -Name "lastSeen"
        $pn = Get-HordeField -Record $S.w1 -Name "pane"
        $riText = ""; if ($ri.state -eq "known") { $riText = "$($ri.value)" }
        $pnVal = $null; if ($pn.state -eq "known") { $pnVal = $pn.value }
        [void]$cands.Add((Get-HordeStoredHandleCandidate -Context $C.host -Store "W1" -Field "pane" -Handle $pnVal -RecordInstance $riText -Written $ls.value -What "the registry record"))
    }
    if ($C.paneVerdicts.state.state -ne "known") { [void]$cands.Add((New-HordeCandidate -Store "X1" -Field "file name" -Answer $C.paneVerdicts.state)) }
    elseif ($null -ne $S.x1) { [void]$cands.Add((New-HordeCandidate -Store "X1" -Field "file name" -Answer (New-HordeKnown -Value $S.x1.handle))) }
    else { [void]$cands.Add((New-HordeCandidate -Store "X1" -Field "file name" -Skip "no pane-sessions file passes the guard for this session")) }
    Set-HordeRunLink -S $S -C $C -FleetId (Get-HordePreliminaryFleetId -S $S -C $C)
    $ev = Get-HordeReportEvents $S
    if ($null -eq $ev) { [void]$cands.Add((New-HordeCandidate -Store "W5" -Field "session.pane" -Skip "the session is in no known run")) }
    elseif ($ev.complete.state -ne "known") { [void]$cands.Add((New-HordeCandidate -Store "W5" -Field "session.pane" -Answer $ev.complete)) }
    else {
        $last = $null
        foreach ($e in @($ev.events)) { $sess = Get-HordeField -Record $e -Name "session"; if ($sess.state -eq "known" -and (Get-HordeField -Record $sess.value -Name "pane").state -eq "known") { $last = $e } }
        if ($null -eq $last) { [void]$cands.Add((New-HordeCandidate -Store "W5" -Field "session.pane" -Skip "no report carries a handle")) }
        else { [void]$cands.Add((Get-HordeStoredHandleCandidate -Context $C.host -Store "W5" -Field "session.pane" -Handle $last.session.pane -RecordInstance "" -Written (Get-HordeField -Record $last -Name "ts").value -What "the last report")) }
    }
    if ($null -eq $S.rosterEntry) { [void]$cands.Add((New-HordeCandidate -Store "W4" -Field "pane" -Skip "the session is in no known run")) }
    else {
        $rp = Get-HordeField -Record $S.rosterEntry -Name "pane"
        $rs = Get-HordeField -Record $S.rosterEntry -Name "spawnedAt"
        $rpVal = $null; if ($rp.state -eq "known") { $rpVal = $rp.value }
        [void]$cands.Add((Get-HordeStoredHandleCandidate -Context $C.host -Store "W4" -Field "pane" -Handle $rpVal -RecordInstance "" -Written $rs.value -What "the roster entry"))
    }
    # Absent only when every store was read and none names a live handle - and never while the host
    # cannot be asked (decision 2): then the pane-sessions read above is itself unknown, carrying the
    # host's reason, so the walk cannot end absent.
    $none = New-HordeAbsent -Note "no store names a live handle for this session, and it is not running"
    if ($S.alive) { $none = New-HordeUnknown -Reason "the session is running, but no store names a live handle for it" }
    return (Resolve-HordeField -Candidates $cands -WhenNone $none)
}

function Set-HordeField {
    # Put one resolved field on the session, type-checked against the view, with its marks.
    param($S, $C, [string]$Name, $Resolved, [string]$ExtraProvisional = "", $Shadow = $null)
    if ($Resolved.answer.state -eq "known" -and $Resolved.answer.value -is [datetime]) {
        $Resolved.answer = New-HordeKnown -Value (ConvertTo-HordeIsoText $Resolved.answer.value) -ObservedAt $Resolved.answer.observedAt
    }
    $Resolved = Limit-HordeViewValue -Resolved $Resolved -Field $Name -ValueSchemas $C.valueSchemas -ViewSchema $C.viewSchema
    $prov = ""
    $row = $C.rules.fields[$Name]
    if ($null -ne $row -and $null -ne $row.PSObject.Properties["provisional"]) { $prov = "$($row.provisional)" }
    if ($ExtraProvisional -ne "") { if ($prov -ne "") { $prov = $prov + "; " + $ExtraProvisional } else { $prov = $ExtraProvisional } }
    $S.fields[$Name] = New-HordeViewAnswer -Answer $Resolved.answer -Store $Resolved.store -Field $Resolved.field -Provisional $prov -Shadow $Shadow
}

function New-HordeResolved {
    # A resolution built by hand, for a derived field.
    param($Answer, [string]$Store = "", [string]$Field = "")
    return [pscustomobject]@{ answer = $Answer; store = $Store; field = $Field; why = @() }
}

function Get-HordeActivityAnswer {
    # lastActivity: the newest of the command logs (W6, run-scoped and loose), the transcript's write
    # time (X3), and the agent's own status time (X2 updatedAt, W8 statusUpdatedAt) - every
    # involuntary source, where wezfleet's census read the transcript alone and its snapshot three
    # (YedPool/wezfleet lib/Registry.ps1:871-876, lib/Activity.ps1:245-282; parity difference P-10).
    # A source that cannot be read, or that says it was written more than 5 seconds in the future,
    # makes the answer unknown: wezfleet clamped a future time to "now" (lib/Activity.ps1:282), which
    # reads a clock error as proof of life. No source at all is unknown too - never zero, never idle
    # (YedPool/wezfleet b2e59c6 "-1 means UNKNOWN, never idle").
    param($S, $C)
    $srcs = New-Object System.Collections.ArrayList
    if ($null -ne $S.runFolder) { [void]$srcs.Add(@("W6", "cmdlog.txt", $S.runFolder.cmdlogAt)) }
    [void]$srcs.Add(@("W6", "loose cmdlog", (Get-HordeWriteTime -Path (Join-Path $C.wf.looseDir ($S.id + ".cmdlog.txt")))))
    if ($S.fields.Contains("transcriptPath") -and $S.fields["transcriptPath"].answer.state -eq "known") {
        [void]$srcs.Add(@("X3", "write time", (Get-HordeWriteTime -Path "$($S.fields['transcriptPath'].answer.value)")))
    }
    if ($null -ne $S.rec) {
        $extra = Read-HordeControlExtras -Record $S.rec
        $isCodex = ($S.rec.fields.agent.state -eq "known" -and "$($S.rec.fields.agent.value)" -ceq "codex")
        $name = "updatedAt"; $store = "X2"
        if ($isCodex) { $name = "statusUpdatedAt"; $store = "W8" }
        if ($null -eq $extra) { [void]$srcs.Add(@($store, $name, (New-HordeUnknown -Reason "the control file could not be read again for its time"))) }
        else {
            $t = ConvertFrom-HordeEpochMs (Get-HordeField -Record $extra -Name $name).value
            if ($null -eq $t) { [void]$srcs.Add(@($store, $name, (New-HordeAbsent -Note ("the control file has no " + $name)))) }
            else { [void]$srcs.Add(@($store, $name, (New-HordeKnown -Value $t -ObservedAt $t))) }
        }
    }
    $best = $null; $bestStore = ""; $bestField = ""
    $why = New-Object System.Collections.ArrayList
    foreach ($src in $srcs) {
        $a = $src[2]
        if ($a.state -eq "absent") { continue }
        if ($a.state -eq "unknown") { [void]$why.Add($src[0] + " " + $src[1] + ": " + $a.reason); continue }
        # A future time is refused by the same rule core/tristate ages every answer with.
        $aged = Limit-HordeAge -Answer $a -TtlSeconds 1e15 -Now $C.now
        if ($aged.state -ne "known") { [void]$why.Add($src[0] + " " + $src[1] + ": " + $aged.reason); continue }
        if ($null -eq $best -or $a.value -gt $best) { $best = $a.value; $bestStore = $src[0]; $bestField = $src[1] }
    }
    if ($why.Count -gt 0) { return (New-HordeResolved -Answer (New-HordeUnknown -Reason ("an activity source cannot be trusted: " + (@($why) -join "; ")))) }
    if ($null -eq $best) { return (New-HordeResolved -Answer (New-HordeUnknown -Reason "no activity source recorded anything for this session; that is unknown, never idle")) }
    return (New-HordeResolved -Answer (New-HordeKnown -Value $best -ObservedAt $best) -Store $bestStore -Field $bestField)
}

function Get-HordeWorkState {
    # workState, derived as the table says: from reported events, liveness and activity; terminal
    # events are trusted outright; a roster entry never spawned is pending. Two rules wezfleet's own
    # tests pinned hold here as tristate (lib/Protocol.ps1:121-199):
    #   - orphaned needs BOTH the handle gone and the activity stopped (test-wezfleet.ps1:310, :1030);
    #   - unknown liveness never makes an orphan (test-wezfleet.ps1:328; core-tristate L-029).
    param($S, $C)
    $fa = $S.fields["fleetSessionId"].answer
    if ($fa.state -eq "unknown") { return (New-HordeResolved -Answer (New-HordeUnknown -Reason ("the session's fleet id is unknown: " + $fa.reason))) }
    if ($fa.state -eq "absent") { return (New-HordeResolved -Answer (New-HordeAbsent -Note "the session is in no run, so it has no work state")) }
    $ra = $S.fields["runId"].answer
    if ($ra.state -ne "known") {
        if ($ra.state -eq "absent") { return (New-HordeResolved -Answer (New-HordeAbsent -Note ("no run holds the session: " + $ra.reason))) }
        return (New-HordeResolved -Answer (New-HordeUnknown -Reason ("the session's run is not known: " + $ra.reason)))
    }
    $ev = Get-HordeReportEvents $S
    $last = ""
    if ($null -ne $ev) {
        if ($ev.complete.state -ne "known") { return (New-HordeResolved -Answer $ev.complete) }
        $list = @($ev.events)
        if ($list.Count -gt 0) { $le = Get-HordeField -Record $list[$list.Count - 1] -Name "event"; if ($le.state -eq "known") { $last = "$($le.value)" } }
    }
    if ($script:HordeTerminalEvents -ccontains $last) { return (New-HordeResolved -Answer (New-HordeKnown -Value $last) -Store "W5" -Field "event") }
    if ($last -eq "" -and $null -ne $S.rosterEntry) {
        $sp = Get-HordeField -Record $S.rosterEntry -Name "spawned"
        if ($sp.state -eq "known" -and $sp.value -is [bool] -and -not $sp.value) { return (New-HordeResolved -Answer (New-HordeKnown -Value "pending") -Store "W4" -Field "spawned") }
    }
    $act = $S.fields["lastActivity"].answer
    $fresh = $null
    if ($act.state -eq "known") { $fresh = (($C.now.ToUniversalTime() - ([datetime]$act.observedAt).ToUniversalTime()).TotalSeconds -le $script:HordeOrphanGraceSeconds) }
    $pane = $S.fields["pane"].answer
    $aliveNow = ($S.alive -or $pane.state -eq "known" -or $fresh -eq $true)
    $goneNow = ((-not $S.alive) -and $pane.state -eq "absent" -and $fresh -eq $false)
    if ($aliveNow) {
        $v = "starting"
        if ($last -eq "blocked") { $v = "blocked" } elseif ($last -eq "started" -or $last -eq "progress") { $v = "running" } elseif ($fresh -eq $true) { $v = "running" }
        return (New-HordeResolved -Answer (New-HordeKnown -Value $v) -Store "W5" -Field "event")
    }
    if ($goneNow) { return (New-HordeResolved -Answer (New-HordeKnown -Value "orphaned") -Store "W5" -Field "event") }
    return (New-HordeResolved -Answer (New-HordeUnknown -Reason "whether the session is alive is unknown - its handle is unknown or its activity cannot be read - and unknown liveness never makes an orphan"))
}

function Get-HordeRegistryCwdCandidate {
    # W1 cwd, read only when the record is not retired and was written in this host instance.
    param($S, $C)
    if ($S.w1Unreadable -or $null -eq $S.w1) { return (Get-HordeRegistryCandidate $S "cwd" -Agentish) }
    if ($S.w1Retired) { return (New-HordeCandidate -Store "W1" -Field "cwd" -Skip "the registry record is retired") }
    if ($C.host.verify.state -ne "known") { return (New-HordeCandidate -Store "W1" -Field "cwd" -Answer (New-HordeUnknown -Reason ("whether the record was written in this instance cannot be checked: " + $C.host.verify.reason))) }
    $ri = Get-HordeField -Record $S.w1 -Name "instance"; $ls = Get-HordeField -Record $S.w1 -Name "lastSeen"
    $riText = ""; if ($ri.state -eq "known") { $riText = "$($ri.value)" }
    $nh = Test-HordeWrittenInInstance -Context $C.host -RecordInstance $riText -Written $ls.value -What "the registry record"
    if ($nh -ne "") { return (New-HordeCandidate -Store "W1" -Field "cwd" -Skip $nh) }
    return (Get-HordeRegistryCandidate $S "cwd" -Agentish)
}

function Complete-HordeSession {
    # Every field but the pane, once every session's pane is settled.
    param($S, $C)
    $id = $S.id

    $idField = "session.claudeSessionId"
    switch ($C.idSources[$id]) { "X2" { $idField = "sessionId" } "W1" { $idField = "file name" } "X1" { $idField = "session_id" } }
    Set-HordeField $S $C "sessionId" (New-HordeResolved -Answer (New-HordeKnown -Value $id) -Store $C.idSources[$id] -Field $idField)
    Set-HordeField $S $C "agent" (Resolve-HordeField @((Get-HordeIdentityCandidate $S "agent" "presence")))

    # cwd first: the claim guard compares it.
    Set-HordeField $S $C "cwd" (Resolve-HordeField @((Get-HordeIdentityCandidate $S "cwd"), (Get-HordeRegistryCwdCandidate $S $C), (Get-HordeLastReportField $S "cwd" "session.cwd"), (Get-HordeRosterCandidate $S "cwd" "cwd")))
    if ($S.fields["cwd"].answer.state -eq "known") { $S.cwdForClaim = "$($S.fields['cwd'].answer.value)" }

    # projectCwd: the launch directory (it names the transcript folder), never the current one.
    $pc = New-Object System.Collections.ArrayList
    if ($null -ne $S.rec -and "$($S.rec.processCheck)" -ceq "verified") { [void]$pc.Add((Get-HordeIdentityCandidate $S "cwd")) }
    else { [void]$pc.Add((New-HordeCandidate -Store "X2" -Field "cwd" -Skip "the session is not running under a verified control file")) }
    [void]$pc.Add((Get-HordeRegistryCandidate $S "firstCwd"))
    if ($null -ne $S.x1 -and $S.x1.cwd -ne "" -and $S.x1.transcriptPath -ne "" -and (ConvertTo-HordeClaudeProjectKey -Cwd $S.x1.cwd) -ieq (Split-Path -Leaf (Split-Path -Parent $S.x1.transcriptPath))) {
        [void]$pc.Add((New-HordeCandidate -Store "X1" -Field "cwd" -Answer (New-HordeKnown -Value $S.x1.cwd)))
    } else { [void]$pc.Add((New-HordeCandidate -Store "X1" -Field "cwd" -Skip "no guarded pane-sessions file whose cwd names its own transcript folder")) }
    if ($null -ne $S.w1 -and $null -eq $S.w1.PSObject.Properties["firstCwd"]) { [void]$pc.Add((Get-HordeRegistryCandidate $S "cwd")) }
    Set-HordeField $S $C "projectCwd" (Resolve-HordeField $pc)

    # The engine's own fields: W1, then the guarded claim. A role that is not there is unknown,
    # never goblin (core/roles).
    $roleCand = $null
    if ($S.w1Unreadable) { $roleCand = New-HordeCandidate -Store "W1" -Field "role" -Answer (New-HordeUnknown -Reason "the session's registry record could not be read") }
    elseif ($null -eq $S.w1) { $roleCand = New-HordeCandidate -Store "W1" -Field "role" -Skip "no registry record names this session" }
    else { $roleCand = New-HordeCandidate -Store "W1" -Field "role" -Answer (Read-HordeRecordRole -Record $S.w1 -Table $C.roleTable).role }
    $claimRole = Get-HordeClaimCandidate $S $C "role" "role"
    if ($claimRole.skip -eq "" -and $claimRole.answer.state -eq "known") { $claimRole = New-HordeCandidate -Store "W2" -Field "role" -Answer (Resolve-HordeRole -Raw $claimRole.answer.value -Table $C.roleTable).role }
    Set-HordeField $S $C "role" (Resolve-HordeField @($roleCand, $claimRole))
    foreach ($n in @("parent", "label")) { Set-HordeField $S $C $n (Resolve-HordeField @((Get-HordeRegistryCandidate $S $n), (Get-HordeClaimCandidate $S $C $n $n))) }
    # labelCycle: -1 is wezfleet's "none" in a claim; a labelled record with no labelCycle is cycle 0,
    # as wezfleet reads it (schema/session-record.v1 labelCycle).
    $lc = Get-HordeRegistryCandidate $S "labelCycle"
    if ($lc.skip -eq "" -and $lc.answer.state -eq "absent" -and $S.fields["label"].answer.state -eq "known" -and $null -ne $S.fields["label"].source -and $S.fields["label"].source.store -eq "W1") {
        $lc = New-HordeCandidate -Store "W1" -Field "labelCycle (none on a labelled record, read as 0)" -Answer (New-HordeKnown -Value 0)
    }
    $lcClaim = Get-HordeClaimCandidate $S $C "labelCycle" "labelCycle"
    foreach ($x in @($lc, $lcClaim)) { if ($x.skip -eq "" -and $x.answer.state -eq "known" -and "$($x.answer.value)" -eq "-1") { $x.answer = New-HordeAbsent -Note "-1 is wezfleet's none" } }
    Set-HordeField $S $C "labelCycle" (Resolve-HordeField @($lc, $lcClaim))
    Set-HordeField $S $C "origin" (Resolve-HordeField @((Get-HordeRegistryCandidate $S "origin")))
    # retired is read as wezfleet reads it, by truthiness: a record with no retired field is live
    # (core/Roles.ps1, the one missing field not read as unknown).
    if ($null -ne $S.w1) { Set-HordeField $S $C "retired" (New-HordeResolved -Answer (New-HordeKnown -Value $S.w1Retired) -Store "W1" -Field "retired") }
    else { Set-HordeField $S $C "retired" (Resolve-HordeField @((Get-HordeRegistryCandidate $S "retired"))) }
    foreach ($n in @("lastSeen", "retiredAt", "lastTool")) { Set-HordeField $S $C $n (Resolve-HordeField @((Get-HordeRegistryCandidate $S $n))) }

    # fleetSessionId: W1, the claim, a roster or manifest a report links to this session, a codex file.
    $fl = New-Object System.Collections.ArrayList
    [void]$fl.Add((Get-HordeRegistryCandidate $S "fleetSessionId"))
    [void]$fl.Add((Get-HordeClaimCandidate $S $C "fleetSessionId" "fleetSessionId"))
    foreach ($pair in @(@("W4", "sessions[].id"), @("W3", "sessions[].id"))) {
        if (-not $C.links.ContainsKey($id)) { [void]$fl.Add((New-HordeCandidate -Store $pair[0] -Field $pair[1] -Skip "no report names this session")); continue }
        $useManifest = ($pair[0] -eq "W3")
        $fids = @($C.links[$id] | Where-Object { -not $useManifest -or $null -ne $_.run.manifest } | ForEach-Object { $_.fleetId } | Sort-Object -Unique)
        if ($fids.Count -eq 1) { [void]$fl.Add((New-HordeCandidate -Store $pair[0] -Field $pair[1] -Answer (New-HordeKnown -Value $fids[0]))) }
        elseif ($fids.Count -gt 1) { [void]$fl.Add((New-HordeCandidate -Store $pair[0] -Field $pair[1] -Answer (New-HordeUnknown -Reason ("reports in several runs name this session under different fleet ids: " + ($fids -join ", "))))) }
        else { [void]$fl.Add((New-HordeCandidate -Store $pair[0] -Field $pair[1] -Skip "no readable run links this session")) }
    }
    $codexExtra = $null
    if ($null -ne $S.rec -and $S.rec.fields.agent.state -eq "known" -and "$($S.rec.fields.agent.value)" -ceq "codex") { $codexExtra = Read-HordeControlExtras -Record $S.rec }
    if ($null -ne $codexExtra) { [void]$fl.Add((New-HordeCandidate -Store "W8" -Field "wezfleetSessionId" -Answer (Get-HordeStoredField -Record $codexExtra -Name "wezfleetSessionId" -What "the codex file"))) }
    else { [void]$fl.Add((New-HordeCandidate -Store "W8" -Field "wezfleetSessionId" -Skip "no codex control file names this session")) }
    Set-HordeField $S $C "fleetSessionId" (Resolve-HordeField $fl -WhenNone (New-HordeAbsent -Note "no store links this session to a fleet id"))

    # runId, then everything the run holds.
    $fa = $S.fields["fleetSessionId"].answer
    if ($fa.state -eq "known") {
        $rr = Resolve-HordeRun -Runs $C.wf.runs -FleetId "$($fa.value)"
        Set-HordeRunLink -S $S -C $C -FleetId "$($fa.value)"
        $S.runAmbiguous = @($rr.ambiguous)
        if ($rr.answer.state -eq "known") { Set-HordeField $S $C "runId" (New-HordeResolved -Answer (New-HordeKnown -Value $rr.answer.value.runId) -Store "W4" -Field "runId") }
        elseif ($rr.answer.state -eq "absent") { Set-HordeField $S $C "runId" (New-HordeResolved -Answer $rr.answer -Store "W4" -Field "runId") }
        else { Set-HordeField $S $C "runId" (New-HordeResolved -Answer $rr.answer) }
    } else {
        Set-HordeRunLink -S $S -C $C -FleetId ""
        $ra = New-HordeAbsent -Note "the session has no fleet id, so it is in no run"
        if ($fa.state -eq "unknown") { $ra = New-HordeUnknown -Reason ("the session's fleet id is unknown: " + $fa.reason) }
        Set-HordeField $S $C "runId" (New-HordeResolved -Answer $ra)
    }
    $noRun = New-HordeAbsent -Note "the session is in no run"
    Set-HordeField $S $C "title" (Resolve-HordeField @((Get-HordeRosterCandidate $S "title" "sessions[].title"), (Get-HordeRosterCandidate $S "title" "sessions[].title" -Manifest)) -WhenNone $noRun)
    Set-HordeField $S $C "dependsOn" (Resolve-HordeField @((Get-HordeRosterCandidate $S "dependsOn" "sessions[].dependsOn"), (Get-HordeRosterCandidate $S "dependsOn" "sessions[].dependsOn" -Manifest)) -WhenNone $noRun)
    Set-HordeField $S $C "spawnedAt" (Resolve-HordeField @((Get-HordeRosterCandidate $S "spawnedAt" "sessions[].spawnedAt" -MissingIsUnknown), (Get-HordeClaimCandidate $S $C "spawnedAt" "spawnedAt")) -WhenNone (New-HordeAbsent -Note "no roster entry or claim records a spawn"))

    # window: the live handle's, else the roster's, else the run's.
    $wc = New-Object System.Collections.ArrayList
    $pa = $S.fields["pane"].answer
    if ($pa.state -eq "known" -and $C.host.live.ContainsKey("$($pa.value)") -and $null -ne $C.host.live["$($pa.value)"].window) { [void]$wc.Add((New-HordeCandidate -Store "X4" -Field "window_id" -Answer (New-HordeKnown -Value $C.host.live["$($pa.value)"].window))) }
    else { [void]$wc.Add((New-HordeCandidate -Store "X4" -Field "window_id" -Skip "the session's live handle is not known")) }
    $rw = Get-HordeRosterCandidate $S "window" "window" -MissingIsUnknown
    if ($rw.skip -eq "" -and $rw.answer.state -eq "known") { $wt = ConvertTo-HordeHandleText $rw.answer.value; if ($null -eq $wt) { $rw.answer = New-HordeUnknown -Reason "the roster's window is not an id" } else { $rw.answer = New-HordeKnown -Value $wt } }
    [void]$wc.Add($rw)
    $mw = $null
    if ($null -ne $S.run -and $null -ne $S.run.manifest -and $null -ne $S.run.manifest.PSObject.Properties["windowId"]) { $mw = ConvertTo-HordeHandleText $S.run.manifest.windowId }
    if ($null -ne $mw) { [void]$wc.Add((New-HordeCandidate -Store "W3" -Field "windowId" -Answer (New-HordeKnown -Value $mw))) }
    else { [void]$wc.Add((New-HordeCandidate -Store "W3" -Field "windowId" -Skip "no run manifest gives a window")) }
    Set-HordeField $S $C "window" (Resolve-HordeField $wc)

    # hostInstance: as the hook recorded it, else the one instance running, for a running session.
    $inst = $C.host.instance
    $x5i = New-HordeCandidate -Store "X5" -Field "instance" -Skip "not a running session under exactly one known host instance"
    if ($S.alive -and $inst.state -eq "known" -and $inst.value.running -eq 1 -and -not $inst.value.ambiguous -and $null -ne $inst.value.id) { $x5i = New-HordeCandidate -Store "X5" -Field "instance" -Answer (New-HordeKnown -Value $inst.value.id) }
    Set-HordeField $S $C "hostInstance" (Resolve-HordeField @((Get-HordeRegistryCandidate $S "instance" -Agentish), $x5i))

    # The agent's own fields.
    $procs = @(Get-HordeResumeProcesses -Processes $C.processes -SessionId $id)
    $x5 = $null
    if ($procs.Count -eq 1) { $x5 = $procs[0] }
    $pidX5 = New-HordeCandidate -Store "X5" -Field "pid" -Skip "no process's command line resumes this session"
    if ($null -ne $x5) { $pidX5 = New-HordeCandidate -Store "X5" -Field "pid" -Answer (New-HordeKnown -Value ([int]$x5.pid)) }
    elseif ($procs.Count -gt 1) { $pidX5 = New-HordeCandidate -Store "X5" -Field "pid" -Answer (New-HordeUnknown -Reason ("" + $procs.Count + " processes resume this session")) }
    $notRunning = $null
    if ($null -eq $S.rec -and -not $S.dupe -and $procs.Count -eq 0) { $notRunning = Get-HordeNotRunning -C $C -What "process" }
    Set-HordeField $S $C "pid" (Resolve-HordeField @((Get-HordeIdentityCandidate $S "pid"), $pidX5) -WhenNone $notRunning)
    $startX5 = New-HordeCandidate -Store "X5" -Field "start time" -Skip "no single process resumes this session"
    $ticksX5 = New-HordeCandidate -Store "X5" -Field "start time" -Skip "no single process resumes this session"
    if ($null -ne $x5 -and $null -ne $x5.created) { $startX5 = New-HordeCandidate -Store "X5" -Field "start time" -Answer (New-HordeKnown -Value $x5.created); $ticksX5 = New-HordeCandidate -Store "X5" -Field "start time" -Answer (New-HordeKnown -Value ([long]$x5.created.ToFileTimeUtc())) }
    Set-HordeField $S $C "procStart" (Resolve-HordeField @((Get-HordeIdentityCandidate $S "procStart"), $ticksX5) -WhenNone $notRunning)
    $saR = Resolve-HordeField @((Get-HordeIdentityCandidate $S "startedAt"), $startX5, (Get-HordeRegistryCandidate $S "firstSeen" -Agentish))
    if ($saR.answer.state -eq "known" -and $saR.store -eq "W1") { $t = ConvertFrom-HordeIsoTime $saR.answer.value; if ($null -eq $t) { $saR.answer = New-HordeUnknown -Reason "the registry's firstSeen is not a placeable time"; $saR.store = "" } else { $saR.answer = New-HordeKnown -Value $t } }
    Set-HordeField $S $C "startedAt" $saR
    Set-HordeField $S $C "liveStatus" (Resolve-HordeField @((Get-HordeIdentityCandidate $S "liveStatus" "status")) -WhenNone $notRunning)
    # waitingFor: what a waiting session waits on, as its own control file says - a live fact like
    # liveStatus, so a session no control file names waits on nothing (core-ownership L-055).
    Set-HordeField $S $C "waitingFor" (Resolve-HordeField @((Get-HordeIdentityCandidate $S "waitingFor")) -WhenNone $notRunning)
    Set-HordeField $S $C "messagingAddress" (Resolve-HordeField @((Get-HordeIdentityCandidate $S "messagingAddress" "messagingSocketPath")) -WhenNone $notRunning)
    $x1Title = New-HordeCandidate -Store "X1" -Field "session_title" -Skip "no guarded pane-sessions file gives a title"
    if ($null -ne $S.x1 -and $null -ne $S.x1.sessionTitle) { $x1Title = New-HordeCandidate -Store "X1" -Field "session_title" -Answer (New-HordeKnown -Value $S.x1.sessionTitle) }
    Set-HordeField $S $C "name" (Resolve-HordeField @((Get-HordeIdentityCandidate $S "name"), $x1Title))
    foreach ($pair in @(@("nameSource", "nameSource"), @("nameSince", "nameSince"), @("bridgeSessionId", "bridgeSessionId"), @("agentVersion", "version"),
                        @("peerProtocol", "peerProtocol"), @("peerFeatures", "peerFeatures"), @("sessionKind", "kind"), @("entrypoint", "entrypoint"), @("pidDomain", "pidDomain"), @("formerNames", "formerNames"))) {
        Set-HordeField $S $C $pair[0] (Resolve-HordeField @((Get-HordeIdentityCandidate $S $pair[0] $pair[1])))
    }

    # transcriptPath: derived from the control file; else the one file for the id in any project
    # folder; else a guarded pane-sessions file's path, when it exists; else the report's.
    $tc = New-Object System.Collections.ArrayList
    [void]$tc.Add((Get-HordeIdentityCandidate $S "transcriptPath" "cwd (derived)"))
    if ($C.transcripts.complete.state -ne "known") { [void]$tc.Add((New-HordeCandidate -Store "X3" -Field "file name" -Answer $C.transcripts.complete)) }
    elseif (-not $C.transcripts.index.ContainsKey($id)) { [void]$tc.Add((New-HordeCandidate -Store "X3" -Field "file name" -Skip "no project folder holds a transcript for this id")) }
    elseif (@($C.transcripts.index[$id]).Count -eq 1) { [void]$tc.Add((New-HordeCandidate -Store "X3" -Field "file name" -Answer (New-HordeKnown -Value @($C.transcripts.index[$id])[0]))) }
    else { [void]$tc.Add((New-HordeCandidate -Store "X3" -Field "file name" -Skip ("" + @($C.transcripts.index[$id]).Count + " project folders hold a transcript for this id, so none is taken"))) }
    if ($null -ne $S.x1 -and $S.x1.transcriptPath -ne "" -and (Test-Path -LiteralPath $S.x1.transcriptPath -PathType Leaf)) { [void]$tc.Add((New-HordeCandidate -Store "X1" -Field "transcript_path" -Answer (New-HordeKnown -Value $S.x1.transcriptPath))) }
    else { [void]$tc.Add((New-HordeCandidate -Store "X1" -Field "transcript_path" -Skip "no guarded pane-sessions file names a transcript that exists")) }
    [void]$tc.Add((Get-HordeLastReportField $S "transcriptPath" "session.transcriptPath"))
    $tExtra = ""
    if ($null -ne $S.rec -and $null -ne $S.rec.provisional -and $S.rec.provisional.ContainsKey("transcriptPath")) { $tExtra = "" + $S.rec.provisional["transcriptPath"] }
    Set-HordeField $S $C "transcriptPath" (Resolve-HordeField $tc) -ExtraProvisional $tExtra
    if ($null -ne $S.rec -and $null -ne $S.rec.provisional -and $S.rec.provisional.ContainsKey("formerNames")) {
        $fnv = $S.fields["formerNames"]; if ("$($fnv.provisional)" -eq "") { $fnv.provisional = "" + $S.rec.provisional["formerNames"] }
    }

    # resumeCommand: computed by the AgentPort (step 5.1), so unknown here; the layout saves and the
    # stored copy in the report are shadows - compared, never the answer (D3).
    $shadow = New-Object System.Collections.ArrayList
    if ($C.layout.state -eq "known" -and $C.layout.value.ContainsKey($id)) { foreach ($a in @($C.layout.value[$id])) { [void]$shadow.Add([pscustomobject]@{ store = "R1"; value = "$a" }) } }
    $ev = Get-HordeReportEvents $S
    if ($null -ne $ev -and $ev.complete.state -eq "known") {
        $list = @($ev.events)
        for ($i = $list.Count - 1; $i -ge 0; $i--) { $r = Get-HordeField -Record $list[$i] -Name "resumeCommand"; if ($r.state -eq "known" -and "$($r.value)" -ne "") { [void]$shadow.Add([pscustomobject]@{ store = "W5"; value = "$($r.value)" }); break } }
    }
    Set-HordeField $S $C "resumeCommand" (New-HordeResolved -Answer (New-HordeUnknown -Reason "the resume command is computed by the AgentPort (step 5.1), not read; the layout saves and the report's copy are shadows only")) -Shadow $shadow.ToArray()

    # owner: derived - the parent's label, else founder. The stored owner name is display only;
    # wezfleet printed it, and "(unowned)" when empty (commands/census.ps1:17; parity difference P-11).
    $par = $S.fields["parent"]
    if ($par.answer.state -eq "absent") { Set-HordeField $S $C "owner" (New-HordeResolved -Answer (New-HordeKnown -Value "founder") -Store $par.source.store -Field "parent (none, so founder)") }
    elseif ($par.answer.state -ne "known") { Set-HordeField $S $C "owner" (New-HordeResolved -Answer (New-HordeUnknown -Reason ("the parent is unknown: " + $par.answer.reason))) }
    elseif (-not $C.wf.registry.records.ContainsKey("$($par.answer.value)")) { Set-HordeField $S $C "owner" (New-HordeResolved -Answer (New-HordeUnknown -Reason ("the parent " + $par.answer.value + " has no readable registry record, so its label is unknown"))) }
    else {
        $pl = Get-HordeStoredField -Record $C.wf.registry.records["$($par.answer.value)"].record -Name "label" -What "the parent's record"
        if ($pl.state -eq "known") { Set-HordeField $S $C "owner" (New-HordeResolved -Answer $pl -Store "W1" -Field "label of the parent") }
        else { Set-HordeField $S $C "owner" (New-HordeResolved -Answer (New-HordeUnknown -Reason ("the parent " + $par.answer.value + " has no label"))) }
    }

    # report: the last event in the log, which is the truth; status.json is only its cache.
    $runA = $S.fields["runId"].answer
    if ($runA.state -ne "known") {
        $rep = New-HordeAbsent -Note "the session is in no run"
        if ($runA.state -eq "unknown") { $rep = New-HordeUnknown -Reason ("the session's run is not known: " + $runA.reason) }
        Set-HordeField $S $C "report" (New-HordeResolved -Answer $rep)
    } elseif ($null -eq $ev -or -not $ev.present -or @($ev.events).Count -eq 0) {
        if ($null -ne $ev -and $ev.complete.state -ne "known") { Set-HordeField $S $C "report" (New-HordeResolved -Answer $ev.complete) }
        else { Set-HordeField $S $C "report" (New-HordeResolved -Answer (New-HordeAbsent -Note "the session has reported nothing") -Store "W5" -Field "events.jsonl") }
    } elseif ($ev.complete.state -ne "known") { Set-HordeField $S $C "report" (New-HordeResolved -Answer $ev.complete) }
    else {
        $list = @($ev.events)
        $le = $list[$list.Count - 1]
        $v = [ordered]@{}
        $e1 = Get-HordeField -Record $le -Name "event"; if ($e1.state -eq "known") { $v["event"] = "$($e1.value)" }
        $e2 = Get-HordeField -Record $le -Name "summary"; if ($e2.state -eq "known") { $v["summary"] = "$($e2.value)" }
        $at = ConvertFrom-HordeIsoTime (Get-HordeField -Record $le -Name "ts").value
        if ($null -ne $at) { $v["at"] = ConvertTo-HordeIsoText $at }
        Set-HordeField $S $C "report" (New-HordeResolved -Answer (New-HordeKnown -Value ([pscustomobject]$v) -ObservedAt $at) -Store "W5" -Field "events.jsonl")
    }

    Set-HordeField $S $C "lastActivity" (Get-HordeActivityAnswer -S $S -C $C)
    Set-HordeField $S $C "workState" (Get-HordeWorkState -S $S -C $C)

    foreach ($d in @($C.rules.dropped)) {
        Set-HordeField $S $C "$($d.name)" (New-HordeResolved -Answer (New-HordeUnknown -Reason ("not carried: core/ownership.json drops it - " + $d.reason)))
    }
    # The fields in the table's order.
    $ordered = [ordered]@{}
    foreach ($n in $C.rules.required) { $ordered[$n] = $S.fields[$n] }
    $S.fields = $ordered
}

function Get-HordeProjection {
    # THE READ MODEL. Every store read once, nothing written. Returns
    #   { observedAt; host { name; instance }; sessions; handles; faults; complete; inputs }
    # sessions is a list of { sessionId; fields }, fields in core/ownership.json's required order,
    # each a view answer (New-HordeViewAnswer). inputs keeps what was read, for tests and for the
    # step 2.3 parity harness.
    param(
        [string]$WezfleetRoot = (Get-HordeWezfleetRoot),
        [string]$ClaudeDir = (Get-HordeClaudeSessionsDir),
        [string]$ProjectsDir = (Get-HordeClaudeProjectsDir),
        [string]$CodexDir = (Get-HordeCodexSessionsDir),
        [string]$PaneSessionsDir = (Get-HordePaneSessionsDir),
        $Processes = (Get-HordeProjectionProcessTable),
        $HostPort = (New-HordeUnavailableHostPort -Reason "no host adapter is attached (the first one arrives under hosts/ in a later step)"),
        $LayoutPort = $null,
        $TtlSeconds = (Get-HordeCodexTtlSeconds),
        [datetime]$Now = (Get-Date)
    )
    Assert-HordeProcessTable $Processes
    Assert-HordeHostPort $HostPort
    $rules = Get-HordeOwnershipRules
    $viewSchema = Get-HordeSchema -Name "session-view.v1"
    $C = [pscustomobject]@{
        rules = $rules; viewSchema = $viewSchema; valueSchemas = (Get-HordeViewValueSchemas -ViewSchema $viewSchema)
        roleTable = (Get-HordeRoleTable); now = $Now; processes = $Processes
        identity = (Get-HordeIdentity -ClaudeDir $ClaudeDir -ProjectsDir $ProjectsDir -CodexDir $CodexDir -Processes $Processes -TtlSeconds $TtlSeconds -Now $Now)
        wf = (Read-HordeWezfleetState -Root $WezfleetRoot)
        paneRead = (Read-HordePaneSessions -Dir $PaneSessionsDir)
        host = $null; paneVerdicts = $null; transcripts = (Get-HordeTranscriptIndex -ProjectsDir $ProjectsDir)
        layout = (Read-HordeLayoutSaves -LayoutPort $LayoutPort); links = $null; idSources = $null
    }
    $C.host = Get-HordeHostContext -HandlesAnswer (Read-HordeHostHandles -Port $HostPort) -InstanceAnswer (Read-HordeHostInstance -Port $HostPort)
    $C.paneVerdicts = Get-HordePaneFileVerdicts -PaneRead $C.paneRead -Context $C.host -Registry $C.wf.registry -VerifiedLive $C.identity.verifiedLive
    $C.links = Get-HordeReportLinks -Runs $C.wf.runs
    $C.idSources = Get-HordeSessionIds -Identity $C.identity -Registry $C.wf.registry -PaneVerdicts $C.paneVerdicts -ReportLinks $C.links

    # Pass 1: every session's handle.
    $states = New-Object System.Collections.ArrayList
    foreach ($sid in @($C.idSources.Keys | Sort-Object)) {
        $S = New-HordeSessionState -C $C -Id $sid
        $S.pane = Get-HordePaneAnswer -S $S -C $C
        [void]$states.Add($S)
    }
    # Several sessions answering one handle: every claimant is unknown, naming them all (decision 1).
    $claims = @{}
    foreach ($S in $states) { if ($S.pane.answer.state -eq "known") { $h = "$($S.pane.answer.value)"; if (-not $claims.ContainsKey($h)) { $claims[$h] = New-Object System.Collections.ArrayList }; [void]$claims[$h].Add($S.id) } }
    $claimed = @{}
    foreach ($h in @($claims.Keys)) {
        if ($claims[$h].Count -lt 2) { continue }
        $ids = @($claims[$h] | Sort-Object)
        $claimed[$h] = $ids
        foreach ($S in $states) { if ($ids -contains $S.id) { $S.pane = New-HordeResolved -Answer (New-HordeUnknown -Reason ("handle " + $h + " is claimed by " + $ids.Count + " sessions (" + ($ids -join ", ") + "), and none is chosen")) } }
    }
    # Pass 2: everything else.
    foreach ($S in $states) {
        Set-HordeField $S $C "pane" $S.pane
        Complete-HordeSession -S $S -C $C
    }

    # Handles, including those no session answers (decision 3).
    $handles = $C.host.handles
    if ($C.host.handles.state -eq "known") {
        $rows = New-Object System.Collections.ArrayList
        foreach ($h in @($C.host.handles.value)) {
            $ans = @($states | Where-Object { $_.fields["pane"].answer.state -eq "known" -and "$($_.fields['pane'].answer.value)" -eq $h.handle } | ForEach-Object { $_.id })
            $cl = @(); if ($claimed.ContainsKey($h.handle)) { $cl = @($claimed[$h.handle]) }
            [void]$rows.Add([pscustomobject]@{ handle = $h.handle; window = $h.window; tab = $h.tab; hostTitle = $h.hostTitle; sessions = $ans; claimants = $cl })
        }
        $handles = New-HordeKnown -Value $rows.ToArray()
    }

    $x4 = New-HordeKnown -Value $true; if ($C.host.handles.state -ne "known") { $x4 = New-HordeUnknown -Reason $C.host.handles.reason }
    $x5c = New-HordeKnown -Value $true; if ($Processes.state -ne "known") { $x5c = New-HordeUnknown -Reason $Processes.reason }
    $r1 = New-HordeKnown -Value $true; if ($C.layout.state -ne "known") { $r1 = New-HordeUnknown -Reason $C.layout.reason }
    # W6 is read by write time only; a log whose time cannot be read is its one way to be incomplete.
    $w6gaps = @($C.wf.runs.runs | ForEach-Object { foreach ($k in @($_.sessions.Keys)) { $a = $_.sessions[$k].cmdlogAt; if ($a.state -eq "unknown") { $a.reason } } })
    $w6 = New-HordeKnown -Value $true; if ($w6gaps.Count -gt 0) { $w6 = New-HordeUnknown -Reason ($w6gaps -join "; ") }
    $complete = [ordered]@{
        R1 = $r1; W1 = $C.wf.registry.complete; W2 = $C.wf.claims.complete; W3 = $C.wf.runs.runsComplete; W4 = $C.wf.runs.rostersComplete
        W5 = $C.wf.runs.reportsComplete; W6 = $w6; W8 = $C.identity.complete["codex"]; X1 = $C.paneRead.complete
        X2 = $C.identity.complete["claude"]; X3 = $C.transcripts.complete; X4 = $x4; X5 = $x5c
        X6 = (New-HordeKnown -Value $true)
    }
    $sessions = @($states | ForEach-Object { [pscustomobject]@{ sessionId = $_.id; fields = $_.fields } })
    $faults = @(Get-HordeFaults -States $states -C $C -Claimed $claimed)
    return [pscustomobject]@{
        PSTypeName = "Horde.Projection"; observedAt = $Now.ToUniversalTime()
        host = [pscustomobject]@{ name = "$($HostPort.name)"; instance = $C.host.instance }
        sessions = $sessions; handles = $handles; faults = $faults; complete = $complete; inputs = $C
    }
}

# ------------------------------------------------------------------------------- the document

function ConvertTo-HordeAnswerDocument {
    # One answer as schema/session-view.v1 stores it: state and reason always; value only when known;
    # observedAt, source, provisional and shadow only when there are any.
    param($ViewAnswer)
    $a = $ViewAnswer
    if (@($a.PSObject.TypeNames) -contains "Horde.Answer") { $a = New-HordeViewAnswer -Answer $a }
    $o = [ordered]@{ state = $a.answer.state; reason = "$($a.answer.reason)" }
    if ($a.answer.state -eq "known") { $o["value"] = $a.answer.value }
    if ($null -ne $a.answer.observedAt) { $o["observedAt"] = ConvertTo-HordeIsoText $a.answer.observedAt }
    if ($null -ne $a.source) { $o["source"] = [ordered]@{ store = $a.source.store; field = $a.source.field } }
    if ("$($a.provisional)" -ne "") { $o["provisional"] = "$($a.provisional)" }
    if ($null -ne $a.shadow -and @($a.shadow).Count -gt 0) { $o["shadow"] = @($a.shadow | ForEach-Object { [ordered]@{ store = $_.store; value = $_.value } }) }
    return $o
}

function ConvertTo-HordeSessionViewDocument {
    # The projection as a schema/session-view.v1 document: plain values, times as ISO 8601 UTC text.
    # Serialise it with ConvertTo-Json -Depth 30 or deeper (core/Tristate.ps1: the default depth
    # writes nested values as type names).
    param($Projection)
    $inst = $Projection.host.instance
    if ($inst.state -eq "known") {
        $v = [ordered]@{}
        if ($null -ne $inst.value.id) { $v["id"] = $inst.value.id }
        if ($null -ne $inst.value.startedAt) { $v["startedAt"] = ConvertTo-HordeIsoText $inst.value.startedAt }
        $v["running"] = [int]$inst.value.running; $v["ambiguous"] = [bool]$inst.value.ambiguous
        $inst = New-HordeKnown -Value $v
    }
    $handles = $Projection.handles
    if ($handles.state -eq "known") {
        $rows = New-Object System.Collections.ArrayList
        foreach ($hr in @($handles.value)) {
            $r = [ordered]@{ handle = $hr.handle }
            if ($null -ne $hr.window) { $r["window"] = $hr.window }
            if ($null -ne $hr.tab) { $r["tab"] = $hr.tab }
            if ($null -ne $hr.hostTitle) { $r["hostTitle"] = $hr.hostTitle }
            $r["sessions"] = @($hr.sessions); $r["claimants"] = @($hr.claimants)
            [void]$rows.Add($r)
        }
        $handles = New-HordeKnown -Value $rows.ToArray()
    }
    $complete = [ordered]@{}
    foreach ($k in @($Projection.complete.Keys | Sort-Object)) { $complete[$k] = ConvertTo-HordeAnswerDocument $Projection.complete[$k] }
    $sessions = New-Object System.Collections.ArrayList
    foreach ($s in @($Projection.sessions)) {
        $f = [ordered]@{}
        foreach ($k in @($s.fields.Keys)) { $f[$k] = ConvertTo-HordeAnswerDocument $s.fields[$k] }
        [void]$sessions.Add([ordered]@{ sessionId = $s.sessionId; fields = $f })
    }
    $faults = New-Object System.Collections.ArrayList
    foreach ($ft in @($Projection.faults)) {
        $found = @($ft.found | ForEach-Object { [ordered]@{ subjects = @($_.subjects | ForEach-Object { "$_" }); detail = "$($_.detail)" } })
        [void]$faults.Add([ordered]@{ kind = $ft.kind; answer = (ConvertTo-HordeAnswerDocument $ft.answer); found = $found })
    }
    return [ordered]@{
        schemaVersion = 1
        observedAt = (ConvertTo-HordeIsoText $Projection.observedAt)
        host = [ordered]@{ name = "$($Projection.host.name)"; instance = (ConvertTo-HordeAnswerDocument $inst) }
        sessions = $sessions.ToArray()
        handles = (ConvertTo-HordeAnswerDocument $handles)
        faults = $faults.ToArray()
        complete = $complete
    }
}

function Test-HordeSessionViewRules {
    # The rules schema/session-view.v1 states and core/Schema.ps1 cannot check, because it implements
    # no oneOf, anyOf, if/then or dependencies: a value exactly when known; a non-blank reason when
    # unknown; a fault's found list empty unless it is known true, and not empty when it is. Takes
    # the PARSED document (ConvertTo-Json then ConvertFrom-Json), so it checks what a reader sees.
    param($Document)
    $out = New-Object System.Collections.ArrayList
    $answers = New-Object System.Collections.ArrayList
    [void]$answers.Add(@('$.host.instance', $Document.host.instance))
    [void]$answers.Add(@('$.handles', $Document.handles))
    $i = 0
    foreach ($s in @($Document.sessions)) { foreach ($p in $s.fields.PSObject.Properties) { [void]$answers.Add(@(('$.sessions[' + $i + '].fields.' + $p.Name), $p.Value)) }; $i++ }
    $i = 0
    foreach ($f in @($Document.faults)) { [void]$answers.Add(@(('$.faults[' + $i + '].answer'), $f.answer)); $i++ }
    foreach ($p in $Document.complete.PSObject.Properties) { [void]$answers.Add(@(('$.complete.' + $p.Name), $p.Value)) }
    foreach ($pair in $answers) {
        $path = $pair[0]; $a = $pair[1]
        $hasValue = ($null -ne $a.PSObject.Properties["value"])
        if ($a.state -eq "known" -and -not $hasValue) { [void]$out.Add($path + " is known and has no value") }
        if ($a.state -ne "known" -and $hasValue) { [void]$out.Add($path + " is " + $a.state + " and has a value") }
        if ($a.state -eq "unknown" -and "$($a.reason)".Trim() -eq "") { [void]$out.Add($path + " is unknown and gives no reason") }
    }
    $i = 0
    foreach ($f in @($Document.faults)) {
        $isTrue = ($f.answer.state -eq "known" -and $f.answer.value -eq $true)
        if ($f.answer.state -eq "known" -and -not $isTrue -and @($f.found).Count -gt 0) { [void]$out.Add('$.faults[' + $i + '] (' + $f.kind + ') lists what it found but is known false') }
        if ($isTrue -and @($f.found).Count -eq 0) { [void]$out.Add('$.faults[' + $i + '] (' + $f.kind + ') is known true and lists nothing') }
        $i++
    }
    return @($out)
}
