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
#   2. SELECTION (New-HordeFleetSelectorOrcs): each Orc named - by its label, or by its lane folder's name
#      as the Orc's status record says (fleet/StatusPanel.ps1) - and every Warg under it by the fleet
#      registry's parent links, among the sessions that are not retired and are running
#      (Get-HordeFleetCandidates, which refuses when the registry or the liveness reading cannot be
#      trusted). THE PLUG POINT: Invoke-HordeFleetHibernate -Selector, a block handed the candidates that
#      returns the ones to hibernate in the order to ask and end them. The explicit list
#      (Select-HordeFleetOrcs) is the default; the Orc registry's tiers will be another such block.
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
#      every Warg of it chosen here has exited. The command goes through the waker port's Exit
#      (wakers/Port.ps1), whose real adapter uses the fleet's checked path; it is never a kill. It is
#      sent ONCE: after a submitted exit only the liveness reading is asked again, and a session whose
#      box may hold the typed command (left-behind, killed, or an answer nobody could read) is never sent
#      it again. A session is exited when the harness's liveness rule says its process is gone; its
#      history then holds the time, which a wake's narrowing rule reads (fleet/Wake.ps1, Get-HordeFleetSince).
#   6b. A "DO NOT RESTORE" MARKER for each session that exited (the host's Mark, fleet/Port.ps1), so the
#      terminal's session restore does not bring it back beside its wake. Written whole by rename.
#   7. THE DEADLINE: every session not exited by then is still-awake, with the reason it was waiting on,
#      and is left running, untouched. Phase done.
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
    $ans = { param($o, $r, $said = "") [pscustomobject]@{ outcome = $o; reason = $r; fileSeen = [bool]$m.fileSeen; said = $said } }
    if ("" + $m.blocked -ne "") { return (& $ans "refused" $m.blocked) }
    if (-not $m.fileSeen) {
        $at = & $Deps.ParkedAt $Request.parkedPath
        if ($at -isnot [datetime]) { return (& $ans "not-yet" "it has not written its PARKED file") }
        if ($at.ToUniversalTime() -lt ([datetime]$Request.askedAt).ToUniversalTime()) { return (& $ans "not-yet" "its PARKED file is older than its ask, so it is last time's") }
        $m.fileSeen = $true
    }
    # SENT ONCE: after a submitted exit only the liveness reading is asked again.
    if ($m.exitSent) {
        $v = & $Deps.Agent.verdict (& $Deps.Agent.snapshot) $Request.sessionId $Request.cwd @($Request.others) $Request.since
        if ("" + $v.state -ceq "stopped") { return (& $ans "parked" "") }
        return (& $ans "not-yet" ("it was sent its exit command and still runs: " + $v.reason))
    }
    $gate = Test-HordeFleetIdleToExit -State (& $Deps.State $Request.sessionId)
    if (-not $gate.ok) { return (& $ans "not-yet" ("it parked, and " + $gate.why)) }
    $sent = & $Deps.Exit $Request.sessionId $Request.reason
    if ($null -ne $sent -and "" + $sent.state -ceq "known" -and "" + $sent.value.outcome -ceq "submitted") {
        $m.exitSent = $true
        return (& $ans "not-yet" "it was sent its exit command" "sent its exit command")
    }
    if ($null -ne $sent -and "" + $sent.state -ceq "known" -and "" + $sent.value.outcome -ceq "refused") { return (& $ans "not-yet" ("its exit command was refused, nothing typed: " + $sent.value.reason)) }
    # left-behind, killed, or an answer nobody could read: its box may hold the command.
    $m.blocked = $(if ($null -ne $sent -and "" + $sent.state -ceq "known") { "its exit command was " + $sent.value.outcome + ": " + $sent.value.reason } else { "what its exit command did is not known: " + $(if ($null -ne $sent) { "" + $sent.reason } else { "no answer" }) }) + "; it is never sent the command again"
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
    #   Typed ($candidate, $since)  the agent's LastTyped answer for one candidate
    #   ParkedFolder         the fleet's parked folder, absolute
    #   ParkedAt ($path)     the UTC time the file was last written, or $null when it is not there
    #   Post ($sessionId, $label, $body, $messageId)   answer, as fleet/Wake.ps1's
    #   State ($sessionId)   the waker's full state answer (wakers/Port.ps1, Get-HordeWakeState -Full)
    #   Exit ($sessionId, $reason)   the waker's exit answer (wakers/Port.ps1, Send-HordeWakeExit)
    #   optional: Park ($request) in place of Invoke-HordeFleetParkSession, the one per-session step (the
    #   fleet's park verb, when it comes); Caller () the session running this, or ""; PollMs, ProcessStart,
    #   Self (fleet/Wake.ps1's lock seams)
    # -Selector replaces the explicit-list one (header, step 2); -Names are what the selection says.
    param([Parameter(Mandatory = $true)]$Deps, [Parameter(Mandatory = $true)][string[]]$Names, [switch]$DryRun, [int]$WaitMinutes = 15,
          [scriptblock]$Selector = $null, [string]$HordeHome = (Get-HordeHome))
    if ($WaitMinutes -lt 1 -or $WaitMinutes -gt $script:HordeFleetHibernateMostWaitMinutes) { throw ("-WaitMinutes is 1 to " + $script:HordeFleetHibernateMostWaitMinutes + ", not " + $WaitMinutes) }
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
    if ($null -eq $Selector) {
        $laneStatus = & $Deps.Status
        $Selector = { param($cands) Select-HordeFleetOrcs -Candidates $cands -Names $Names -Status $laneStatus }
    }
    $picked = @(& $Selector $found.candidates)
    $caller = $(if ($null -ne $Deps.PSObject.Properties["Caller"]) { "" + (& $Deps.Caller) } else { "" })
    $chosen = New-Object System.Collections.ArrayList
    $excluded = New-Object System.Collections.ArrayList
    foreach ($c in $picked) {
        $typed = $null
        if (-not (Test-HordeFleetMaster -Candidate $c)) { $typed = & $Deps.Typed $c $now.AddMinutes(-$script:HordeFleetHibernateTypedMinutes) }
        $why = Get-HordeFleetExclusion -Candidate $c -Analysts @($an.value) -Questions @($q.value) -Typed $typed -Now $now -Caller $caller
        if ($null -eq $why) { [void]$chosen.Add($c) } else { [void]$excluded.Add([pscustomobject]@{ candidate = $c; reason = $why.reason; detail = $why.detail }) }
    }
    $nameOf = { param($c) $l = "" + $c.label; $short = ("" + $c.sessionId).Substring(0, 8); if ($l -eq "") { $short } else { $l + " (" + $short + ")" } }
    $folder = "" + $Deps.ParkedFolder
    & $say ("hibernate " + ($Names -join ", ") + ": " + $chosen.Count + " to hibernate, " + $excluded.Count + " left running" + $(if ($DryRun) { " (dry run: nothing is changed, nothing is posted)" } else { "" }))
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
        $selection = [pscustomobject][ordered]@{ kind = "orcs"; labels = @($Names); exclude = @() }
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
            $pending["" + $s.sessionId] = [pscustomobject]@{ session = $s; path = $path; askedAt = (& $Deps.Now); why = "it has not written its PARKED file yet"; memo = [pscustomobject]@{ fileSeen = $false; exitSent = $false; blocked = "" } }
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
        while ($pending.Count -gt 0) {
            foreach ($s in $ordered) {
                $sid = "" + $s.sessionId
                if (-not $pending.ContainsKey($sid)) { continue }
                $p = $pending[$sid]
                $name = Get-HordeFleetSessionName -Session $s
                # An Orc goes after every Warg of it chosen here has exited.
                $waitingFor = @($ordered | Where-Object { "" + $_.sessionId -cne $sid -and (Get-HordeFleetDescendants -Candidates @($ordered) -Root $sid | ForEach-Object { "" + $_.candidate.sessionId }) -ccontains ("" + $_.sessionId) -and "" + $_.state -cne "exited" })
                if ($waitingFor.Count -gt 0) { $p.why = "it waits for its Wargs to exit first (" + (@($waitingFor | ForEach-Object { Get-HordeFleetSessionName -Session $_ }) -join ", ") + ")"; continue }
                $req = [pscustomobject]@{ sessionId = $sid; label = "" + $s.label; cwd = "" + $s.cwd; parkedPath = $p.path; askedAt = $p.askedAt; reason = ("hibernation " + $id)
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
                } elseif ("" + $step.outcome -ceq "refused") {
                    # Final: nothing more is ever typed into that box. Left running, and said now.
                    $why = "" + $step.reason
                    Add-HordeFleetState -Session $s -State "still-awake" -At (& $Deps.Now) -Reason $why
                    [void](Write-HordeFleetRecord -Dir $dir -Record $record)
                    & $say ("  " + $name + ": still-awake - " + $why); & $tell $sid $s.label "still-awake" $why
                    $pending.Remove($sid)
                }
            }
            if ($pending.Count -eq 0 -or (& $Deps.Now) -ge $deadline) { break }
            & $Deps.Sleep $pollMs
        }
        # 7. THE DEADLINE.
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
