# fleet/Hibernate.ps1 - `horde fleet hibernate`: put chosen Orcs and their Wargs to sleep, each one only
# after it has written where it got to, and only by its own exit command.
#
# WHY. A session that runs costs memory and, when woken by mail, money; one that is idle for hours costs
# both for nothing. Hibernation ends such sessions so that `horde fleet wake` (fleet/Wake.ps1) can start
# each again later, by its session id, in the place it sat, with a mail telling it to read its PARKED
# file. This is slice 2 (decided by M and F, 2026-10-16); slice 1 is the record and the wake.
#
# THE STEPS, and why each is where it is:
#   1. ONE AT A TIME. <hibernations>\hibernating.lock, made only if no file has that name, holding its
#      owner's pid and process start time, and removed when the run ends, whatever happened. Two runs
#      would each ask, and each send the exit command, to the same sessions. A lock whose owner is gone
#      (no such pid, or a pid now owned by a process that started at another time) is stale and taken
#      over, and that is said; one whose owner runs or may is "another hibernation is running, retry".
#      The rule is fleet/Wake.ps1's for its waking lock (Get-HordeFleetLockOwner).
#   2. SELECTION: `horde fleet hibernate -Tier 2`, THE TIER GATE. The Orcs the Orc registry (orcs/Registry.ps1,
#      `horde orcs tier <id> 1|2`) puts in tier 2 - every running one, or only those -Orcs names, each by its
#      label or by its lane folder's name as the Orc's status record says (fleet/StatusPanel.ps1) - and every
#      Warg under it by the fleet registry's parent links, among the sessions that are not retired and are
#      running (Get-HordeFleetCandidates, which refuses when the registry or the liveness reading cannot be
#      trusted). A TIER 1 ORC, ONE WITH NO TIER SET AND ONE THE REGISTRY DOES NOT KNOW IS NEVER HIBERNATED,
#      not even when named: a named Orc that is not in tier 2 refuses the whole run with a line saying so
#      (hibernating K and L must not read later as if L had been asked about), a registry that cannot be read
#      refuses it too, and the gate is checked again on whatever any selector picked
#      (Get-HordeFleetTierExclusion, reason "tier"). THE PLUG POINT: Invoke-HordeFleetHibernate -Selector, a
#      block handed the candidates that returns the ones to hibernate in the order to ask and end them. The
#      tier / explicit-list one (Select-HordeFleetOrcs) is the default.
#   3. NEVER SELECTED, each named with one plain word (Get-HordeFleetExclusion):
#        master                 the session labelled M, or holding the warchief's role
#        self                   the session running this command: its own box is refused to it, so it
#                               could only sit out the wait, and a run that ended itself would end mid-way
#        analyst                the fleet analyst service, by the session id its own files name
#        unlabelled             a session with no label: its PARKED file could not be named
#        founder-typed          the founder typed into it in the last 30 minutes (Test-HordeFleetFleetLine
#                               says which typed lines are the fleet's own and do not count)
#        transcript-unreadable  that could not be ruled out
#        question               an Orc with an open question on the founder's decisions list
#        tier                   an Orc not in tier 2, and every Warg under one (the gate, step 2)
#        warg-left-running      an Orc with a Warg of it left running: an Orc and its Wargs sleep together
#        orc-left-running       a Warg under an Orc left running, for the same reason (not when that Orc is
#                               "self": the Orc running this command may put its own Wargs to sleep)
#      A reading the whole selection rests on - the registry, liveness, the decisions list, the analyst's
#      files - that cannot be read REFUSES the run with nothing written: never an empty or a partial
#      choice that reads later as "nobody needed to stay up".
#   4. THE RECORD (fleet/Hibernation.ps1's writer, Invoke-HordeFleetRecord): the chosen sessions, where
#      each sits, phase asking, each session asked.
#   5. THE ASK, through the messenger port, Wargs before their Orc: write where you got to into the
#      fleet's parked folder (resolved from the fleet's own root, never a home path written here), reply
#      nothing, stop at the end of your turn. Its message id is made from the hibernation and the
#      session, so a repeated post is one.
#   6. PARKING, bounded by -WaitMinutes (phase parking), each session one call of ONE per-session step
#      (Invoke-HordeFleetParkSession, which the fleet's own park verb is to replace). A session is sent its exit command only when its
#      PARKED file is there AND was written at or after its ask (an older one is last time's) AND the
#      waker reads it idle=yes, boxEmpty=yes, midTurn=no - any unknown is "not yet" - AND, for an Orc,
#      every Warg of it chosen here has exited. JUST BEFORE THE COMMAND the founder's typing is looked at
#      again, since the ask: if he typed, the session is still-awake for good in this run - never retried,
#      never exited. The command goes through the waker port's Exit
#      (wakers/Port.ps1), whose real adapter uses the fleet's checked path; it is never a kill. It is
#      sent ONCE: after a submitted exit only the liveness reading is asked again, and a session whose
#      box may hold the typed command (left-behind, killed, or an answer nobody could read) is never sent
#      it again. A session is exited when the harness's liveness rule says its process is gone; its
#      history then holds the time, which a wake's narrowing rule reads (fleet/Wake.ps1, Get-HordeFleetSince).
#   6b. A "DO NOT RESTORE" MARKER for each session that exited (the host's Mark, fleet/Port.ps1), so the
#      terminal's session restore does not bring it back beside its wake. Written whole by rename.
#   7. THE DEADLINE, kept between sessions (the overshoot is at most one exit command): ONE LAST LIVENESS LOOK,
#      by the call the wake watcher makes, at every session that was sent its exit command or may have been
#      (a part-way or an unreadable answer): one whose process is gone is exited, with its no-restore marker,
#      and not recorded awake for having exited a moment after the wait ended. Every session still not exited
#      is still-awake, with the reason it was waiting on, and is left running, untouched. Phase done.
#   A SESSION FOUND RUNNING that a hibernation put to sleep has its stale "hibernated" no-restore marker
#      removed through the host (fleet/Port.ps1, Unmark), by this run, a wake and the wake watcher alike.
# -DryRun prints the selection, the exclusions with their reasons and the plan, and changes nothing: no
# lock, no record, no mail, no keystroke.
#
# EVERY OUTSIDE CALL COMES IN THROUGH -Deps (Invoke-HordeFleetHibernate's header lists them), chosen for
# real in one place, cli/commands/fleet.ps1. No step asks a person anything.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path $PSScriptRoot "Wake.ps1")

$script:HordeFleetHibernateLockName = "hibernating.lock"
# The founder's own typing keeps a session up for this long (the founder's brief, 2026-10-16).
$script:HordeFleetHibernateTypedMinutes = 30
# How often the parking loop looks again. Each look reads the PARKED files (cheap) and, for a parked
# session, one waker state (a pane read, about 1 to 5 s on this machine) and the liveness snapshot.
$script:HordeFleetHibernatePollMs = 15000
# The tier gate's words (Get-HordeFleetTierExclusion).
$script:HordeFleetTierRule = "only an Orc in tier 2 is ever hibernated"
$script:HordeFleetHibernateMostWaitMinutes = 240
# THE FLEET'S OWN LINES, typed into a session's box by its tools and marked by the harness exactly as a
# person's typing is (agents/<name>/Fleet.ps1, LastTyped, has the measurement). They are not the
# founder: the mail pointer ("wezfleet: a message is waiting for you (...)", 3,738 of the 5,070 typed
# lines in the 80 newest transcripts on 2026-10-16), a mail block, the spawn protocol, and any line
# typed through standard input, which carries a byte-order mark no keyboard types (the handoff
# delivery: 71 of them).
$script:HordeFleetFleetLinePrefixes = @("wezfleet:", "MESSAGE FROM ", "=== wezfleet session protocol ===")

function Get-HordeFleetParkedPath {
    # Where a session parks: <the fleet's parked folder>\PARKED-<label>.md.
    param([Parameter(Mandatory = $true)][string]$Folder, [Parameter(Mandatory = $true)][string]$Label)
    return (Join-Path $Folder ("PARKED-" + $Label + ".md"))
}

function Get-HordeFleetHibernateBody {
    # The ask each chosen session gets.
    param([Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)][string]$Path)
    return ("Hibernation " + $Id + ": write where you got to into " + $Path + ", reply nothing, stop at your turn end.")
}

function Get-HordeFleetHibernateMessageId {
    # The ask's message id: the same for the same hibernation and session, so a repeated post is one.
    param([Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)][string]$SessionId)
    return (ConvertTo-HordeTextUuid -Text ("horde-fleet-hibernate/" + $Id + "/" + $SessionId))
}

function Test-HordeFleetFleetLine {
    # Is a typed line one of the fleet's own (header, THE FLEET'S OWN LINES), not a person's?
    param([AllowEmptyString()][string]$Text)
    if ($Text.Length -gt 0 -and [int]$Text[0] -eq 0xFEFF) { return $true }
    $t = $Text.TrimStart()
    foreach ($p in $script:HordeFleetFleetLinePrefixes) { if ($t.StartsWith($p, [System.StringComparison]::Ordinal)) { return $true } }
    return $false
}

function Get-HordeFleetFounderTyped {
    # The newest turn a person typed, of -Turns (the port's LastTyped value), that is not a fleet line and
    # is at or after -Since: { at; text }, or $null.
    param([object[]]$Turns = @(), [Parameter(Mandatory = $true)][datetime]$Since)
    $best = $null
    foreach ($t in @($Turns)) {
        if ($null -eq $t -or $t.at -isnot [datetime]) { continue }
        if ($t.at.ToUniversalTime() -lt $Since.ToUniversalTime()) { continue }
        if (Test-HordeFleetFleetLine -Text ("" + $t.text)) { continue }
        if ($null -eq $best -or $t.at -gt $best.at) { $best = $t }
    }
    return $best
}

function Test-HordeFleetOrcWaits {
    # Does an open question of -Questions (each { number; askedBy; waiting }) wait on Orc -Label? Its asker
    # or one of whom it holds up names "Orc <label>" as whole words (the list writes "Orc C", "Orc C (the
    # reworked fix ...)": 81 questions read 2026-10-16). Returns the question's number, or 0.
    param([object[]]$Questions = @(), [Parameter(Mandatory = $true)][string]$Label)
    if ($Label -eq "") { return 0 }
    $pattern = '(?<![A-Za-z0-9])Orc\s+' + [regex]::Escape($Label) + '(?![A-Za-z0-9])'
    foreach ($q in @($Questions)) {
        if ($null -eq $q) { continue }
        $names = @(@("" + $q.askedBy) + @($q.waiting | ForEach-Object { "" + $_ }))
        foreach ($n in $names) { if ($n -cmatch $pattern) { return [int]$q.number } }
    }
    return 0
}

function Get-HordeFleetDescendants {
    # The candidates under -Root by the registry's parent links, at any depth, each with its depth (1 for a
    # direct Warg). A loop in the links is walked once.
    param([Parameter(Mandatory = $true)][object[]]$Candidates, [Parameter(Mandatory = $true)][string]$Root)
    $byId = @{}
    foreach ($c in $Candidates) { $byId["" + $c.sessionId] = $c }
    $out = New-Object System.Collections.ArrayList
    foreach ($c in $Candidates) {
        if ("" + $c.sessionId -ceq $Root) { continue }
        $depth = 0; $p = "" + $c.parent; $seen = @{}
        while ($p -ne "" -and -not $seen.ContainsKey($p)) {
            $seen[$p] = $true; $depth++
            if ($p -ceq $Root) { [void]$out.Add([pscustomobject]@{ candidate = $c; depth = $depth }); break }
            if (-not $byId.ContainsKey($p)) { break }
            $p = "" + $byId[$p].parent
        }
    }
    return @($out)
}

function Select-HordeFleetOrcs {
    # THE EXPLICIT-LIST SELECTION: of -Candidates (Get-HordeFleetCandidates), each Orc named in -Names and
    # its Wargs, IN THE ORDER THEY ARE ASKED AND ENDED: for each Orc, its deepest
    # Wargs first and the Orc last. A name is an Orc's label, or the name of its lane folder, which its
    # status record maps to its letter (-Status: Get-HordeFleetStatus's answer). A name that names no
    # running, unretired Orc - or two - is refused, never dropped: "hibernate K and L" that hibernates K
    # alone reads later as if L had been asked about.
    # It is a function and not a closure: a closure made here could not call this file's functions when
    # the file is dot-sourced inside a command's block (hosts/<name>/Fleet.ps1 measured the same, 2026-10-16).
    param([object[]]$Candidates = @(), [Parameter(Mandatory = $true)][string[]]$Names, $Status = $null)
    $wanted = @($Names | Where-Object { "" + $_ -ne "" })
        $all = @($Candidates)
        $orcs = @($all | Where-Object { "" + $_.role -ceq "orc" })
        $out = New-Object System.Collections.ArrayList
        foreach ($n in $wanted) {
            $hit = @($orcs | Where-Object { "" + $_.label -ceq $n })
            if ($hit.Count -eq 0) {
                $letter = ""
                if ($null -ne $Status -and "" + $Status.state -ceq "read") {
                    $lane = @(@($Status.orcs) | Where-Object { $_.written -and "" + $_.folder -ceq $n })
                    if ($lane.Count -eq 1) { $letter = "" + $lane[0].orc }
                }
                if ($letter -ne "") { $hit = @($orcs | Where-Object { "" + $_.label -ceq $letter }) }
                if ($hit.Count -eq 0) {
                    $how = $(if ($null -eq $Status -or "" + $Status.state -cne "read") { "; the lane folders could not be read (" + $(if ($null -ne $Status) { "" + $Status.reason } else { "no status was given" }) + ")" } elseif ($letter -ne "") { "; its lane folder says Orc " + $letter + ", which is not running" } else { "" })
                    throw ("no running, unretired Orc is named " + $n + ", by label or by lane folder" + $how + ", so nothing was hibernated")
                }
            }
            if ($hit.Count -gt 1) { throw ("" + $hit.Count + " running Orcs are labelled " + $n + "; which is meant cannot be told, so nothing was hibernated") }
            $orc = $hit[0]
            $under = @(Get-HordeFleetDescendants -Candidates $all -Root ("" + $orc.sessionId) | Sort-Object -Property @{ Expression = { $_.depth }; Descending = $true }, @{ Expression = { "" + $_.candidate.label } }, @{ Expression = { "" + $_.candidate.sessionId } })
            foreach ($u in $under) { if (-not $out.Contains($u.candidate)) { [void]$out.Add($u.candidate) } }
            if (-not $out.Contains($orc)) { [void]$out.Add($orc) }
        }
        return @($out)
}

function Get-HordeFleetExclusion {
    # Why one picked candidate is never hibernated (header, step 3): { reason; detail }, or $null.
    #   -Analysts   the analyst service's session ids
    #   -Questions  the open questions, each { number; askedBy; waiting }
    #   -Typed      the agent's LastTyped answer for this session
    #   -Caller     the session id of the session running the command, or ""
    param([Parameter(Mandatory = $true)]$Candidate, [string[]]$Analysts = @(), [object[]]$Questions = @(), $Typed = $null, [Parameter(Mandatory = $true)][datetime]$Now, [string]$Caller = "")
    $no = { param($r, $d) [pscustomobject]@{ reason = $r; detail = $d } }
    if (Test-HordeFleetMaster -Candidate $Candidate) { return (& $no "master" "the master is never put to sleep by hibernate") }
    if ($Caller -ne "" -and "" + $Candidate.sessionId -ceq $Caller) { return (& $no "self" "it is the session running this command, which cannot end itself and wait for itself") }
    if (@($Analysts) -ccontains ("" + $Candidate.sessionId)) { return (& $no "analyst" "the fleet analyst service runs always") }
    if ("" + $Candidate.label -eq "") { return (& $no "unlabelled" "it has no label, so its PARKED file could not be named") }
    if ($null -eq $Typed -or "" + $Typed.state -cne "known") { return (& $no "transcript-unreadable" ("whether the founder typed into it lately could not be read: " + $(if ($null -ne $Typed) { "" + $Typed.reason } else { "no reading" }))) }
    $since = $Now.AddMinutes(-$script:HordeFleetHibernateTypedMinutes)
    $hit = Get-HordeFleetFounderTyped -Turns @($Typed.value) -Since $since
    if ($null -ne $hit) { return (& $no "founder-typed" ("the founder typed into it at " + (Format-HordeFleetTime -At $hit.at) + ", within the last " + $script:HordeFleetHibernateTypedMinutes + " minutes")) }
    if ("" + $Candidate.role -ceq "orc") {
        $q = Test-HordeFleetOrcWaits -Questions $Questions -Label ("" + $Candidate.label)
        if ($q -gt 0) { return (& $no "question" ("question " + $q + " on the founder's decisions list waits on it")) }
    }
    return $null
}

function Test-HordeFleetOrcInTier2 {
    # Is the Orc labelled -Label in tier 2 by -Tiers (the Orc registry's answer: label -> 1, 2 or null)? Only a
    # tier that is the whole number 2 says yes: tier 1, no tier set (null), a tier that is not a number, an Orc the
    # registry does not know and a session with no label are all no.
    param($Tiers, [AllowEmptyString()][string]$Label)
    if ($null -eq $Tiers -or $Label -eq "") { return $false }
    if (@($Tiers.Keys) -cnotcontains $Label) { return $false }
    $t = $Tiers[$Label]
    return [bool](($t -is [int] -or $t -is [long]) -and [int]$t -eq 2)
}

function Get-HordeFleetAncestors {
    # The candidates above -Candidate by the registry's parent links, nearest first. A loop in the links is
    # walked once.
    param([Parameter(Mandatory = $true)][object[]]$All, [Parameter(Mandatory = $true)]$Candidate)
    $byId = @{}
    foreach ($c in $All) { $byId["" + $c.sessionId] = $c }
    $out = New-Object System.Collections.ArrayList
    $p = "" + $Candidate.parent; $seen = @{}
    while ($p -ne "" -and -not $seen.ContainsKey($p) -and $byId.ContainsKey($p)) {
        $seen[$p] = $true
        [void]$out.Add($byId[$p])
        $p = "" + $byId[$p].parent
    }
    return @($out)
}

function Get-HordeFleetTierExclusion {
    # THE TIER GATE, whoever chose the sessions (header, step 3): { reason = "tier"; detail }, or $null. An Orc is
    # hibernated only when the Orc registry puts it in tier 2, and a Warg only with an Orc that is: so a tier 1
    # Orc, one with no tier and one the registry does not know are left running, and so is every Warg under them,
    # even when a name, a selector or a list says otherwise.
    param([Parameter(Mandatory = $true)]$Candidate, [Parameter(Mandatory = $true)][object[]]$All, [Parameter(Mandatory = $true)]$Tiers)
    $tierWord = { param($label) if (@($Tiers.Keys) -ccontains $label -and $null -ne $Tiers[$label]) { "tier " + $Tiers[$label] } else { "no tier" } }
    if ("" + $Candidate.role -ceq "orc" -and -not (Test-HordeFleetOrcInTier2 -Tiers $Tiers -Label ("" + $Candidate.label))) {
        return [pscustomobject]@{ reason = "tier"; detail = ("it is an Orc in " + (& $tierWord ("" + $Candidate.label)) + " (" + $script:HordeFleetTierRule + ")") }
    }
    foreach ($a in @(Get-HordeFleetAncestors -All $All -Candidate $Candidate)) {
        if ("" + $a.role -ceq "orc" -and -not (Test-HordeFleetOrcInTier2 -Tiers $Tiers -Label ("" + $a.label))) {
            return [pscustomobject]@{ reason = "tier"; detail = ("its Orc " + $a.label + " is in " + (& $tierWord ("" + $a.label)) + " (" + $script:HordeFleetTierRule + ")") }
        }
    }
    return $null
}

function Test-HordeFleetIdleToExit {
    # May the exit command be sent, by the waker's full state (-State, its answer)? { ok; why }. Only
    # idle=yes, boxEmpty=yes and midTurn=no are yes; any other word, and any unknown, is not yet.
    param($State)
    if ($null -eq $State -or "" + $State.state -cne "known") { return [pscustomobject]@{ ok = $false; why = ("its state could not be read: " + $(if ($null -ne $State) { "" + $State.reason } else { "no answer" })) } }
    $v = $State.value
    foreach ($pair in @(@("idle", "yes"), @("boxEmpty", "yes"), @("midTurn", "no"))) {
        $p = $v.PSObject.Properties[$pair[0]]
        $word = $(if ($null -ne $p) { "" + $p.Value } else { "unknown" })
        if ($word -cne $pair[1]) { return [pscustomobject]@{ ok = $false; why = ("it is not yet idle with an empty box: " + $pair[0] + " is " + $word) } }
    }
    return [pscustomobject]@{ ok = $true; why = "" }
}

function Invoke-HordeFleetParkSession {
    # THE ONE PER-SESSION STEP OF A HIBERNATION: PARKED file there -> idle with an empty box -> the exit
    # command -> its process gone. Kept as one call on purpose: the fleet's own park verb is to do exactly
    # these four (decided for this lane, 2026-10-16), and this function then becomes one call to it,
    # through -Deps.Park, with no change to the loop that orders the sessions or to its tests.
    # Answers { outcome; reason; fileSeen; said }:
    #   parked    its process is gone (Invoke-HordeFleetHibernate records it exited, with the time)
    #   not-yet   look again next time; reason says what it waits on
    #   refused   final: its box may hold the typed command (left-behind, killed, or an answer nobody
    #             could read), so nothing more is ever typed into it
    # fileSeen: its PARKED file is there and newer than its ask. said: a line worth printing, or "".
    # -Request: { sessionId; label; cwd; parkedPath; askedAt; reason; others (ids that cannot be this
    # session under a new id); since (a process begun at or before it cannot be either); memo }. memo is
    # this step's own memory between calls - { fileSeen; exitSent; blocked } - which the caller only keeps.
    # -Deps: ParkedAt ($path), State ($sessionId), Exit ($sessionId, $reason), Agent (liveness).
    param([Parameter(Mandatory = $true)]$Request, [Parameter(Mandatory = $true)]$Deps)
    $m = $Request.memo
    # exitMaybe: the exit command may be in the box or may have gone through, so the process may yet go; the
    # caller looks at it ONE LAST TIME after the wait (Invoke-HordeFleetHibernate, the deadline).
    $ans = { param($o, $r, $said = "") [pscustomobject]@{ outcome = $o; reason = $r; fileSeen = [bool]$m.fileSeen; said = $said; exitMaybe = [bool]($m.exitSent -eq $true -or ($null -ne $m.PSObject.Properties["exitMaybe"] -and $m.exitMaybe -eq $true)) } }
    if ("" + $m.blocked -ne "") { return (& $ans "refused" $m.blocked) }
    if (-not $m.fileSeen) {
        $at = & $Deps.ParkedAt $Request.parkedPath
        if ($at -isnot [datetime]) { return (& $ans "not-yet" "it has not written its PARKED file") }
        if ($at.ToUniversalTime() -lt ([datetime]$Request.askedAt).ToUniversalTime()) { return (& $ans "not-yet" "its PARKED file is older than its ask, so it is last time's") }
        $m.fileSeen = $true
    }
    # SENT ONCE: after a submitted exit only the liveness reading is asked again.
    if ($m.exitSent) {
        # THE SAME LIVENESS CALL AS THE WATCHER'S (fleet/Asleep.ps1), process included: a harness that can tell
        # that very process still running under another id needs it to say so (T-0216).
        $v = & $Deps.Agent.verdict (& $Deps.Agent.snapshot) $Request.sessionId $Request.cwd @($Request.others) $Request.since (Get-HordeFleetMember $Request "process")
        if ("" + $v.state -ceq "stopped") { return (& $ans "parked" "") }
        return (& $ans "not-yet" ("it was sent its exit command and still runs: " + $v.reason))
    }
    $gate = Test-HordeFleetIdleToExit -State (& $Deps.State $Request.sessionId)
    if (-not $gate.ok) { return (& $ans "not-yet" ("it parked, and " + $gate.why)) }
    # THE FOUNDER'S TYPING, LOOKED AT AGAIN RIGHT BEFORE THE EXIT COMMAND (T-0216). Selection looked once, minutes
    # before: a session parks, sits idle with an empty box, and the founder may have started typing into it since.
    # The same check, for anything since the ask was sent. If he typed, the session is left running FOR GOOD in
    # this run - never retried, never exited. A reading that cannot be made is "not yet", and is made again.
    $typedFor = Get-HordeFleetMember $Request "typedFor"
    if ($null -eq $typedFor -or $null -eq $Deps.PSObject.Properties["Typed"]) { return (& $ans "not-yet" "whether the founder typed into it since its ask cannot be checked, so it is not sent its exit command") }
    # THE LOOK STARTS WHERE THE SELECTION's OWN LOOK-BACK STARTED, not at the ask (review of PR 326): the record, the
    # markers and the earlier sessions' asks come between the two, and he may type into this session in that gap.
    $typedFrom = $(if ($null -ne $Request.PSObject.Properties["typedSince"] -and $Request.typedSince -is [datetime]) { [datetime]$Request.typedSince } else { [datetime]$Request.askedAt })
    $typed = & $Deps.Typed $typedFor $typedFrom
    if ($null -eq $typed -or "" + $typed.state -cne "known") { return (& $ans "not-yet" ("whether the founder typed into it since its ask could not be read: " + $(if ($null -ne $typed) { "" + $typed.reason } else { "no reading" }))) }
    $hit = Get-HordeFleetFounderTyped -Turns @($typed.value) -Since $typedFrom
    if ($null -ne $hit) {
        $m.blocked = "the founder typed into it at " + (Format-HordeFleetTime -At $hit.at) + ", since it was looked at for selection, so it is left running and never sent its exit command"
        return (& $ans "refused" $m.blocked)
    }
    $sent = & $Deps.Exit $Request.sessionId $Request.reason
    if ($null -ne $sent -and "" + $sent.state -ceq "known" -and "" + $sent.value.outcome -ceq "submitted") {
        $m.exitSent = $true
        return (& $ans "not-yet" "it was sent its exit command" "sent its exit command")
    }
    if ($null -ne $sent -and "" + $sent.state -ceq "known" -and "" + $sent.value.outcome -ceq "refused") { return (& $ans "not-yet" ("its exit command was refused, nothing typed: " + $sent.value.reason)) }
    # left-behind, killed, or an answer nobody could read: its box may hold the command, and the command may
    # have gone through all the same - so its process is looked at once more after the wait.
    $m | Add-Member -NotePropertyName "exitMaybe" -NotePropertyValue $true -Force
    $m.blocked =$(if ($null -ne $sent -and "" + $sent.state -ceq "known") { "its exit command was " + $sent.value.outcome + ": " + $sent.value.reason } else { "what its exit command did is not known: " + $(if ($null -ne $sent) { "" + $sent.reason } else { "no answer" }) }) + "; it is never sent the command again"
    return (& $ans "refused" $m.blocked)
}

function Invoke-HordeFleetHibernate {
    # The whole of `horde fleet hibernate`. Returns { id; lines; outcomes }: lines are what is printed,
    # outcomes each { sessionId; label; outcome; reason }, outcome exited, still-awake, excluded or planned
    # (-DryRun). Throws, having changed nothing, when another hibernation runs, a reading the selection
    # rests on cannot be trusted, a name names no Orc, or nothing is left to hibernate.
    # -Deps:
    #   Now ()  Sleep (ms)  Registry ()  Agent  Host               as `horde fleet record` takes them
    #   Status ()            Get-HordeFleetStatus's answer: lane folder -> Orc letter
    #   Questions ()         answer: known list of open questions { number; askedBy; waiting }
    #   Analysts ()          answer: known list of the analyst service's session ids (none is @())
    #   OrcTiers ()          answer: known map Orc label -> its registry tier (1, 2 or $null), unknown when the
    #                        Orc registry cannot be read (the run is then refused)
    #   Typed ($candidate, $since)  the agent's LastTyped answer for one candidate
    #   ParkedFolder         the fleet's parked folder, absolute
    #   ParkedAt ($path)     the UTC time the file was last written, or $null when it is not there
    #   Post ($sessionId, $label, $body, $messageId)   answer, as fleet/Wake.ps1's
    #   State ($sessionId)   the waker's full state answer (wakers/Port.ps1, Get-HordeWakeState -Full)
    #   Exit ($sessionId, $reason)   the waker's exit answer (wakers/Port.ps1, Send-HordeWakeExit)
    #   optional: Park ($request) in place of Invoke-HordeFleetParkSession, the one per-session step (the
    #   fleet's park verb, when it comes); Caller () the session running this, or ""; PollMs, ProcessStart,
    #   Self (fleet/Wake.ps1's lock seams)
    # -Selector replaces the explicit-list one (header, step 2); -Names are what the selection says, and with none
    # every running Orc the registry puts in tier 2 is chosen. -Tier is 2, the only tier that sleeps: the gate
    # (Get-HordeFleetTierExclusion) is always on, so a tier 1 Orc, or one with no tier, is never hibernated, not
    # even when named, and a name that is not a tier 2 Orc refuses the whole run.
    param([Parameter(Mandatory = $true)]$Deps, [string[]]$Names = @(), [int]$Tier = 2, [switch]$DryRun, [int]$WaitMinutes = 15,
          [scriptblock]$Selector = $null, [string]$HordeHome = (Get-HordeHome))
    if ($Tier -ne 2) { throw ("-Tier is 2, not " + $Tier + ": only an Orc in tier 2 is ever hibernated, and a tier 1 Orc never") }
    if ($WaitMinutes -lt 1 -or $WaitMinutes -gt $script:HordeFleetHibernateMostWaitMinutes) { throw ("-WaitMinutes is 1 to " + $script:HordeFleetHibernateMostWaitMinutes + ", not " + $WaitMinutes) }
    $Names = @($Names | Where-Object { "" + $_ -ne "" })
    $lines = New-Object System.Collections.ArrayList
    $outcomes = New-Object System.Collections.ArrayList
    $say = { param($t) [void]$lines.Add($t) }
    $tell = { param($sid, $label, $o, $r) [void]$outcomes.Add([pscustomobject]@{ sessionId = "" + $sid; label = "" + $label; outcome = $o; reason = $r }) }
    $pollMs = $script:HordeFleetHibernatePollMs
    if ($null -ne $Deps.PSObject.Properties["PollMs"]) { $pollMs = [int]$Deps.PollMs }
    $procStart = $(if ($null -ne $Deps.PSObject.Properties["ProcessStart"]) { $Deps.ProcessStart } else { { param($p) Get-HordeFleetProcessStart -ProcessId $p } })
    $self = $(if ($null -ne $Deps.PSObject.Properties["Self"]) { & $Deps.Self } else { [pscustomobject]@{ pid = $PID; start = (Get-HordeFleetProcessStart -ProcessId $PID) } })

    # 1. ONE AT A TIME (checked before anything is read, so a refusal costs nothing).
    $hdir = Get-HordeFleetHibernationsDir -HordeHome $HordeHome
    $lockPath = Join-Path $hdir $script:HordeFleetHibernateLockName
    $staleNote = ""
    if (Test-Path -LiteralPath $lockPath) {
        $lockText = ""
        try { $lockText = Read-HordeSharedText -Path $lockPath } catch { $lockText = "" }
        $owner = Get-HordeFleetLockOwner -Text $lockText -ProcessStart $procStart
        if (-not $owner.stale) { throw ("another hibernation is running (" + $lockPath + " is held and " + $owner.reason + "); retry when it is done") }
        $staleNote = $(if ($DryRun) { "would take over" } else { "took over" }) + " a stale hibernating lock of pid " + $owner.owner + ": " + $owner.reason
    }

    # 2. AND 3. WHO: every reading the selection rests on, refused when it cannot be trusted.
    $now = & $Deps.Now
    $registry = & $Deps.Registry
    $snapshot = & $Deps.Agent.snapshot
    $found = Get-HordeFleetCandidates -Registry $registry -Agent $Deps.Agent -Snapshot $snapshot
    $q = & $Deps.Questions
    if ($null -eq $q -or "" + $q.state -cne "known") { throw ("the founder's decisions list could not be read, so which Orcs wait on him cannot be told and nothing was hibernated: " + $(if ($null -ne $q) { $q.reason } else { "no answer" })) }
    $an = & $Deps.Analysts
    if ($null -eq $an -or "" + $an.state -cne "known") { throw ("the fleet analyst service's files could not be read, so it could not be told apart and nothing was hibernated: " + $(if ($null -ne $an) { $an.reason } else { "no answer" })) }
    # THE ORC REGISTRY'S TIERS, read whole or the run is refused (a guess at who is in tier 2 is a session put to
    # sleep that should not be). Read in a dry run too: the plan must be the run's.
    if ($null -eq $Deps.PSObject.Properties["OrcTiers"]) { throw "no reading of the Orc registry's tiers was given, so which Orcs are in tier 2 cannot be told and nothing was hibernated" }
    $tiers = & $Deps.OrcTiers
    if ($null -eq $tiers -or "" + $tiers.state -cne "known") { throw ("the Orc registry's tiers could not be read, so which Orcs are in tier 2 cannot be told and nothing was hibernated: " + $(if ($null -ne $tiers) { "" + $tiers.reason } else { "no answer" })) }
    $tierMap = $tiers.value
    if ($null -eq $Selector) {
        $laneStatus = $(if ($Names.Count -gt 0) { & $Deps.Status } else { $null })
        $Selector = { param($cands)
            $wanted = @($Names)
            if ($wanted.Count -eq 0) {
                $wanted = @(@($cands) | Where-Object { "" + $_.role -ceq "orc" -and (Test-HordeFleetOrcInTier2 -Tiers $tierMap -Label ("" + $_.label)) } | ForEach-Object { "" + $_.label } | Sort-Object -Unique)
                if ($wanted.Count -eq 0) { throw "no running Orc is in tier 2, so nothing was hibernated" }
            }
            $sel = @(Select-HordeFleetOrcs -Candidates $cands -Names $wanted -Status $laneStatus)
            # A NAMED ORC THAT IS NOT IN TIER 2 REFUSES THE RUN, never dropped: "hibernate K and L" that hibernates
            # K alone reads later as if L had been asked about.
            $off = @($sel | Where-Object { "" + $_.role -ceq "orc" -and -not (Test-HordeFleetOrcInTier2 -Tiers $tierMap -Label ("" + $_.label)) })
            if ($off.Count -gt 0) {
                $words = @($off | ForEach-Object { "Orc " + $_.label + " is in " + $(if (@($tierMap.Keys) -ccontains ("" + $_.label) -and $null -ne $tierMap["" + $_.label]) { "tier " + $tierMap["" + $_.label] } else { "no tier" }) })
                throw ("only an Orc in tier 2 is ever hibernated, and " + ($words -join "; ") + ", so nothing was hibernated")
            }
            return $sel
        }
    }
    # THE INSTANT THE SELECTION's 30-MINUTE LOOK-BACK BEGAN, carried to the re-check before each exit command.
    $typedSince = $now.AddMinutes(-$script:HordeFleetHibernateTypedMinutes)
    $picked = @(& $Selector $found.candidates)
    $caller = $(if ($null -ne $Deps.PSObject.Properties["Caller"]) { "" + (& $Deps.Caller) } else { "" })
    $chosen = New-Object System.Collections.ArrayList
    $excluded = New-Object System.Collections.ArrayList
    foreach ($c in $picked) {
        # The tier gate first, whoever picked the session: nothing else is read for one it keeps up.
        $why = Get-HordeFleetTierExclusion -Candidate $c -All @($found.candidates) -Tiers $tierMap
        if ($null -eq $why) {
            $typed = $null
            if (-not (Test-HordeFleetMaster -Candidate $c)) { $typed = & $Deps.Typed $c $typedSince }
            $why = Get-HordeFleetExclusion -Candidate $c -Analysts @($an.value) -Questions @($q.value) -Typed $typed -Now $now -Caller $caller
        }
        if ($null -eq $why) { [void]$chosen.Add($c) } else { [void]$excluded.Add([pscustomobject]@{ candidate = $c; reason = $why.reason; detail = $why.detail }) }
    }
    $nameOf = { param($c) $l = "" + $c.label; $short = ("" + $c.sessionId).Substring(0, 8); if ($l -eq "") { $short } else { $l + " (" + $short + ")" } }
    # AN ORC AND ITS WARGS SLEEP TOGETHER OR NOT AT ALL (review of PR 326, nit a): a Warg is not put to sleep under an
    # Orc that stays up, and an Orc is not put to sleep with a Warg of it still running - the plan named both. Run
    # until nothing moves: one Orc left running keeps its whole tree up, which can keep the Orc above it up. The one
    # exception is "self": the Orc running this command may put its own Wargs to sleep, and stays up itself.
    $keepUp = { param($c, $r, $d) [void]$chosen.Remove($c); [void]$excluded.Add([pscustomobject]@{ candidate = $c; reason = $r; detail = $d }) }
    do {
        $moved = $false
        foreach ($c in @($chosen)) {
            $held = $null
            foreach ($a in @(Get-HordeFleetAncestors -All @($found.candidates) -Candidate $c)) {
                if ("" + $a.role -cne "orc") { continue }
                $ae = @($excluded | Where-Object { "" + $_.candidate.sessionId -ceq "" + $a.sessionId -and $_.reason -cne "self" })
                if ($ae.Count -gt 0) { $held = [pscustomobject]@{ reason = "orc-left-running"; detail = ("its Orc " + (& $nameOf $a) + " is left running (" + $ae[0].reason + "), and a Warg is not put to sleep under an Orc that stays up") }; break }
            }
            if ($null -eq $held -and "" + $c.role -ceq "orc") {
                $under = @(Get-HordeFleetDescendants -Candidates @($found.candidates) -Root ("" + $c.sessionId) | ForEach-Object { $_.candidate })
                $ue = @($excluded | Where-Object { $sid2 = "" + $_.candidate.sessionId; @($under | Where-Object { "" + $_.sessionId -ceq $sid2 }).Count -gt 0 })
                if ($ue.Count -gt 0) { $held = [pscustomobject]@{ reason = "warg-left-running"; detail = ("its Warg " + (& $nameOf $ue[0].candidate) + " is left running (" + $ue[0].reason + "), and an Orc is not put to sleep with a Warg of it still running") } }
            }
            if ($null -ne $held) { & $keepUp $c $held.reason $held.detail; $moved = $true }
        }
    } while ($moved)
    $folder = "" + $Deps.ParkedFolder
    $what = $(if ($Names.Count -gt 0) { ($Names -join ", ") + " (tier 2)" } else { "tier 2" })
    & $say ("hibernate " + $what + ": " + $chosen.Count + " to hibernate, " + $excluded.Count + " left running" + $(if ($DryRun) { " (dry run: nothing is changed, nothing is posted)" } else { "" }))
    if ($staleNote -ne "") { & $say ("  " + $staleNote) }
    foreach ($e in $excluded) {
        & $say ("  left running " + (& $nameOf $e.candidate) + ": " + $e.reason + " - " + $e.detail)
        & $tell $e.candidate.sessionId $e.candidate.label "excluded" ($e.reason + ": " + $e.detail)
    }
    foreach ($n in @($found.notes)) { & $say ("  note: " + $n) }
    if ($chosen.Count -eq 0) {
        if ($DryRun) { & $say "  nothing would be hibernated"; return [pscustomobject]@{ id = ""; lines = @($lines); outcomes = @($outcomes) } }
        throw ("nothing was hibernated: every session the selection named is left running (" + (@($excluded | ForEach-Object { (& $nameOf $_.candidate) + " " + $_.reason }) -join "; ") + ")")
    }
    if (-not [System.IO.Path]::IsPathRooted($folder)) { throw ("the fleet's parked folder is not an absolute path ('" + $folder + "'), so no session could be told where to park") }

    if ($DryRun) {
        & $say ("  each is asked, Wargs before their Orc, to write where it got to into " + $folder + "\PARKED-<label>.md, reply nothing, and stop:")
        $i = 0
        foreach ($c in $chosen) {
            $i++
            & $say ("    " + $i + ". " + (& $nameOf $c) + " " + $c.role + " -> " + (Get-HordeFleetParkedPath -Folder $folder -Label ("" + $c.label)))
            & $tell $c.sessionId $c.label "planned" ""
        }
        & $say ("  then, for up to " + $WaitMinutes + " minute(s), each whose PARKED file is newer than its ask and whose box is idle and empty is sent its exit command through the waker (an Orc only after its Wargs have exited); any not exited by then is left running as still-awake")
        return [pscustomobject]@{ id = ""; lines = @($lines); outcomes = @($outcomes) }
    }

    # THE LOCK, taken now (a stale one removed first).
    [void](New-Item -ItemType Directory -Path $hdir -Force)
    if ($staleNote -ne "") { Remove-Item -LiteralPath $lockPath -Force -ErrorAction Stop }
    $lockStream = $null
    try { $lockStream = New-Object System.IO.FileStream($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read) }
    catch { throw ("another hibernation is running: its lock " + $lockPath + " could not be created (" + $_.Exception.Message + "); retry when it is done") }
    $record = $null; $dir = ""; $id = ""
    $pending = @{}
    try {
        $b = [System.Text.Encoding]::ASCII.GetBytes("pid " + $self.pid + " start " + $self.start + " at " + (Format-HordeFleetTime -At (& $Deps.Now)) + "`n")
        $lockStream.Write($b, 0, $b.Length); $lockStream.Flush($true)

        # 4. THE RECORD, through fleet record's own writer, choosing exactly the sessions chosen here.
        $ids = @($chosen | ForEach-Object { "" + $_.sessionId })
        $fixed = { param($cands) @(@($cands) | Where-Object { $ids -ccontains ("" + $_.sessionId) }) }.GetNewClosure()
        $selLabels = $(if ($Names.Count -gt 0) { @($Names) } else { @(@($chosen | Where-Object { "" + $_.role -ceq "orc" } | ForEach-Object { "" + $_.label }) | Sort-Object -Unique) })
        $selection = [pscustomobject][ordered]@{ kind = "orcs"; labels = @($selLabels); exclude = @() }
        $candBySid = @{}
        foreach ($c in $chosen) { $candBySid["" + $c.sessionId] = $c }
        $made = Invoke-HordeFleetRecord -Deps ([pscustomobject]@{ Now = $Deps.Now; Registry = $Deps.Registry; Agent = $Deps.Agent; Host = $Deps.Host }) -Selector $fixed -Selection $selection -HordeHome $HordeHome
        $record = $made.record; $id = $made.id; $dir = Split-Path -Parent $made.path
        foreach ($n in @($made.notes)) { & $say ("  note: " + $n) }
        $bySid = @{}
        foreach ($s in @($record.sessions)) { $bySid["" + $s.sessionId] = $s }
        # The record holds the sessions in the order they are asked and ended (Wargs first).
        $ordered = @($chosen | Where-Object { $bySid.ContainsKey("" + $_.sessionId) } | ForEach-Object { $bySid["" + $_.sessionId] })
        foreach ($c in $chosen) { if (-not $bySid.ContainsKey("" + $c.sessionId)) { & $say ("  " + (& $nameOf $c) + ": no longer running when the record was taken, so it is not asked"); & $tell $c.sessionId $c.label "still-awake" "it stopped before the record was taken" } }
        $record.sessions = @($ordered)
        $ex = @($excluded | ForEach-Object { $o = [ordered]@{ sessionId = "" + $_.candidate.sessionId }; if ("" + $_.candidate.label -ne "") { $o["label"] = "" + $_.candidate.label }; $o["reason"] = $_.reason; $o["detail"] = $_.detail; [pscustomobject]$o })
        $record | Add-Member -NotePropertyName "excluded" -NotePropertyValue @($ex) -Force
        $record | Add-Member -NotePropertyName "phase" -NotePropertyValue "asking" -Force
        $askedAt = & $Deps.Now
        foreach ($s in $ordered) { Add-HordeFleetState -Session $s -State "asked" -At $askedAt }
        [void](Write-HordeFleetRecord -Dir $dir -Record $record)
        & $say ("hibernation " + $id + ": " + @($ordered).Count + " session(s), record in " + $made.path)
        # A STALE MARKER DOES NOT OUTLIVE A HAND RESTART (T-0216): each session chosen here runs, so a "hibernated"
        # no-restore marker an earlier hibernation left on it is removed through the host (that exact file, only when
        # it says hibernated and names the session). This run writes its own once a session has exited.
        foreach ($l in @(Clear-HordeFleetHibernatedMarker -HostAdapter $Deps.Host -Ids @($ordered | ForEach-Object { "" + $_.sessionId }))) { & $say ("  " + $l) }

        # 5. THE ASK, in order.
        foreach ($s in $ordered) {
            $label = "" + $s.label
            $path = Get-HordeFleetParkedPath -Folder $folder -Label $label
            $posted = & $Deps.Post ("" + $s.sessionId) $label (Get-HordeFleetHibernateBody -Id $id -Path $path) (Get-HordeFleetHibernateMessageId -Id $id -SessionId ("" + $s.sessionId))
            if ($null -eq $posted -or "" + $posted.state -cne "known") {
                $why = "its ask was not posted: " + $(if ($null -ne $posted) { "" + $posted.reason } else { "the messenger answered nothing" })
                Add-HordeFleetState -Session $s -State "still-awake" -At (& $Deps.Now) -Reason $why
                & $say ("  " + (Get-HordeFleetSessionName -Session $s) + ": still-awake - " + $why); & $tell $s.sessionId $label "still-awake" $why
                continue
            }
            $pending["" + $s.sessionId] = [pscustomobject]@{ session = $s; path = $path; askedAt = (& $Deps.Now); why = "it has not written its PARKED file yet"; memo = [pscustomobject]@{ fileSeen = $false; exitSent = $false; exitMaybe = $false; blocked = "" } }
            & $say ("  asked " + (Get-HordeFleetSessionName -Session $s) + " to park in " + $path)
        }
        $record.phase = "parking"
        [void](Write-HordeFleetRecord -Dir $dir -Record $record)

        # 6. PARKING, until all are exited or the deadline.
        $deadline = (& $Deps.Now).AddMinutes($WaitMinutes)
        $recordIds = @($ordered | ForEach-Object { "" + $_.sessionId })
        $since = Get-HordeFleetSince -Session ([pscustomobject]@{ history = @() }) -Record $record
        # THE ONE PER-SESSION STEP (Invoke-HordeFleetParkSession, or -Deps.Park in its place): this loop
        # only orders the sessions, gates an Orc on its Wargs, records what the step answers, and keeps
        # the deadline.
        $park = $(if ($null -ne $Deps.PSObject.Properties["Park"]) { $Deps.Park } else { { param($req) Invoke-HordeFleetParkSession -Request $req -Deps $Deps } })
        # A SESSION'S EXIT, written in one place: its record, what is said, and its no-restore marker. Used by the
        # pass that sees the process gone and by the last look after the wait.
        $doubtful = @{}
        $markExited = {
            param($s)
            $sid = "" + $s.sessionId
            $name = Get-HordeFleetSessionName -Session $s
            Add-HordeFleetState -Session $s -State "exited" -At (& $Deps.Now)
            [void](Write-HordeFleetRecord -Dir $dir -Record $record)
            & $say ("  " + $name + ": exited"); & $tell $sid $s.label "exited" ""
            # THE TERMINAL RESTORE'S "DO NOT RESTORE" MARKER, written now that its process is gone (T-0216): a
            # restore that ran before it would bring a sleeping session back beside its own wake. Only for a
            # session that exited, so a still-awake one is never barred from a restore it may need. The host
            # writes it whole by rename (fleet/Port.ps1, Mark); one that cannot be written is said, and the
            # exit stands - a wake removes the marker (Release), and an unwritten one bars nothing.
            $mark = $(if ($null -ne $Deps.Host -and $null -ne $Deps.Host.PSObject.Properties["mark"]) { $Deps.Host.mark } else { $null })
            if ($null -ne $mark) {
                $mk = $null
                try { $mk = & $mark $sid "hibernated" (& $Deps.Now) } catch { $mk = New-HordeUnknown -Reason ("" + $_.Exception.Message) }
                if ($null -eq $mk -or "" + $mk.state -cne "known") { & $say ("  " + $name + ": its no-restore marker could not be written (" + $(if ($null -ne $mk) { "" + $mk.reason } else { "the terminal's adapter answered nothing" }) + "), so a terminal restore may bring it back") }
            }
            $pending.Remove($sid)
            $doubtful.Remove($sid)
        }
        while ($pending.Count -gt 0) {
            foreach ($s in $ordered) {
                $sid = "" + $s.sessionId
                if (-not $pending.ContainsKey($sid)) { continue }
                # THE DEADLINE IS KEPT BETWEEN SESSIONS, not once a pass (review of PR 326, nit b): a pass reads a pane
                # for each session (1 to 5 s) and an exit command waits on the terminal, so the overshoot is at most
                # the one session in hand.
                if ((& $Deps.Now) -ge $deadline) { break }
                $p = $pending[$sid]
                $name = Get-HordeFleetSessionName -Session $s
                # An Orc goes after every Warg of it chosen here has exited.
                $waitingFor = @($ordered | Where-Object { "" + $_.sessionId -cne $sid -and (Get-HordeFleetDescendants -Candidates @($ordered) -Root $sid | ForEach-Object { "" + $_.candidate.sessionId }) -ccontains ("" + $_.sessionId) -and "" + $_.state -cne "exited" })
                if ($waitingFor.Count -gt 0) { $p.why = "it waits for its Wargs to exit first (" + (@($waitingFor | ForEach-Object { Get-HordeFleetSessionName -Session $_ }) -join ", ") + ")"; continue }
                $req = [pscustomobject]@{ sessionId = $sid; label = "" + $s.label; cwd = "" + $s.cwd; process = (Get-HordeFleetMember $s "process"); typedFor = $candBySid[$sid]; parkedPath = $p.path; askedAt = $p.askedAt; typedSince = $typedSince; reason = ("hibernation " + $id)
                    others = @($recordIds | Where-Object { $_ -cne $sid }); since = $since; memo = $p.memo }
                $step = & $park $req
                if ($null -eq $step) { $step = [pscustomobject]@{ outcome = "not-yet"; reason = "the park step answered nothing"; fileSeen = $false; said = "" } }
                if ($step.fileSeen -eq $true -and "" + $s.state -ceq "asked") {
                    $s | Add-Member -NotePropertyName "parkedFile" -NotePropertyValue $p.path -Force
                    Add-HordeFleetState -Session $s -State "parked" -At (& $Deps.Now)
                    [void](Write-HordeFleetRecord -Dir $dir -Record $record)
                    & $say ("  " + $name + ": parked")
                }
                if ("" + $step.said -ne "") { & $say ("  " + $name + ": " + $step.said) }
                $p.why = "" + $step.reason
                if ("" + $step.outcome -ceq "parked") {
                    & $markExited $s
                } elseif ("" + $step.outcome -ceq "refused") {
                    # Final: nothing more is ever typed into that box. A session whose exit command may have gone
                    # through is not told still-awake yet: its process may yet go, and is looked at once more after
                    # the wait. Any other is left running, and said now.
                    if ($step.exitMaybe -eq $true) {
                        $doubtful["" + $sid] = "" + $step.reason
                        $pending.Remove($sid)
                    } else {
                        $why = "" + $step.reason
                        Add-HordeFleetState -Session $s -State "still-awake" -At (& $Deps.Now) -Reason $why
                        [void](Write-HordeFleetRecord -Dir $dir -Record $record)
                        & $say ("  " + $name + ": still-awake - " + $why); & $tell $sid $s.label "still-awake" $why
                        $pending.Remove($sid)
                    }
                }
            }
            if ($pending.Count -eq 0 -or (& $Deps.Now) -ge $deadline) { break }
            & $Deps.Sleep $pollMs
        }
        # 7. THE DEADLINE. A session that exited just after it must not be recorded as awake (review of PR 326, MUST 1):
        # ONE LAST LIVENESS LOOK, by the call the watcher makes (fleet/Asleep.ps1: the record's ids, the since, the
        # process), at every session that was sent its exit command or may have been - a part-way or an unreadable
        # answer. A process that is gone is exited, with its marker; the rest are still-awake.
        $lastLook = @($ordered | Where-Object { $doubtful.ContainsKey("" + $_.sessionId) -or ($pending.ContainsKey("" + $_.sessionId) -and $pending["" + $_.sessionId].memo.exitSent -eq $true) })
        if ($lastLook.Count -gt 0) {
            $fresh = $null
            try { $fresh = & $Deps.Agent.snapshot } catch { $fresh = $null }
            foreach ($s in $lastLook) {
                $sid = "" + $s.sessionId
                $v = $null
                if ($null -ne $fresh) { try { $v = & $Deps.Agent.verdict $fresh $sid ("" + $s.cwd) @($recordIds | Where-Object { $_ -cne $sid }) $since (Get-HordeFleetMember $s "process") } catch { $v = $null } }
                if ($null -ne $v -and "" + $v.state -ceq "stopped") { & $markExited $s }
            }
        }
        foreach ($s in $ordered) {
            $sid = "" + $s.sessionId
            if (-not $doubtful.ContainsKey($sid)) { continue }
            $why = "" + $doubtful[$sid]
            Add-HordeFleetState -Session $s -State "still-awake" -At (& $Deps.Now) -Reason $why
            [void](Write-HordeFleetRecord -Dir $dir -Record $record)
            & $say ("  " + (Get-HordeFleetSessionName -Session $s) + ": still-awake - " + $why); & $tell $sid $s.label "still-awake" $why
            $doubtful.Remove($sid)
        }
        foreach ($s in $ordered) {
            $sid = "" + $s.sessionId
            if (-not $pending.ContainsKey($sid)) { continue }
            $why = "not exited within " + $WaitMinutes + " minute(s): " + $pending[$sid].why
            Add-HordeFleetState -Session $s -State "still-awake" -At (& $Deps.Now) -Reason $why
            & $say ("  " + (Get-HordeFleetSessionName -Session $s) + ": still-awake - " + $why); & $tell $sid $s.label "still-awake" $why
            $pending.Remove($sid)
        }
        $record.phase = "done"
        [void](Write-HordeFleetRecord -Dir $dir -Record $record)
        & $say ("hibernation " + $id + " done: " + @($outcomes | Where-Object { $_.outcome -ceq "exited" }).Count + " exited, " + @($outcomes | Where-Object { $_.outcome -ceq "still-awake" }).Count + " still awake")
        return [pscustomobject]@{ id = $id; lines = @($lines); outcomes = @($outcomes) }
    } finally {
        # A RUN THAT FAILED PART-WAY still leaves a record that says so: every session it had not finished
        # is still-awake with the error, and the phase is done, so no reader takes it for one in progress.
        if ($null -ne $record -and "" + $record.phase -cne "done") {
            try {
                $err = "the hibernation stopped before it finished"
                foreach ($s in @($record.sessions)) { if (@("asked", "parked", "recorded") -ccontains ("" + $s.state)) { Add-HordeFleetState -Session $s -State "still-awake" -At (& $Deps.Now) -Reason $err } }
                $record.phase = "done"
                [void](Write-HordeFleetRecord -Dir $dir -Record $record)
            } catch { }
        }
        if ($null -ne $lockStream) { $lockStream.Dispose(); Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue }
    }
}
