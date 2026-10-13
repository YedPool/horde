# core/Wake - the wake watcher's rules: who is nudged, when, in what order, and what a restore needs.
#
# WHY (wakers/Port.ps1 has the whole account). Posting a message and waking its receiver were one act,
# done once, by whoever posted; a knock that landed on a busy session was lost and nobody knocked again,
# and after a restore of every session nobody was posting at all. So one watcher owns the doorbell, and
# these are its rules. `horde wake run` (cli/commands/wake.ps1) is the loop around them.
#
# LEVEL-TRIGGERED. A pass keeps no memory of events. It re-reads every session's state and nudges each
# one that has unread mail and is idle with an empty input box, and it does so again next pass, slower
# each time, until the mail is taken. So a missed wake heals itself, a watcher that was restarted misses
# nothing, and "every session was restored" needs no case of its own: it is ten sessions with unread
# mail instead of one.
#
# THE RULE THAT STOPS TYPING OVER SOMEBODY'S TEXT: unknown is never permission. A session is nudged
# only when it is reachable, has unread mail old enough to be worth a knock, is idle, has an empty input
# box, is not mid-turn, and its back-off has run out - and "I could not tell" for any of them is wait,
# with the reason. Nothing here reads unknown as yes, or as no.
#
# PURE WHERE IT DECIDES. Get-HordeWakeDecisions, Update-HordeWakeLedger, Get-HordeRestoreFinding and
# Get-HordeResumePlan read no clock, no file and no port: everything is a parameter and the time is
# always -Now, so a test replays a real timeline second by second. Invoke-HordeWakePass is one pass
# over a waker and does no file I/O either. The file helpers are at the bottom, apart, and only the
# command's loop calls them.
#
# EVERY TIME IS UTC. The port converts what an adapter gives it; a caller passes -Now as UTC.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). It runs under -Version Latest.

. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "Home.ps1")
. (Join-Path $PSScriptRoot "FileAtomic.ps1")
. (Join-Path $PSScriptRoot "ReadShared.ps1")
. (Join-Path $PSScriptRoot "Identity.ps1")
. (Join-Path $PSScriptRoot "WezfleetState.ps1")
# The port the pass reads and rings through. It names no waker; the caller loads those.
. (Join-Path (Split-Path -Parent $PSScriptRoot) "wakers\Port.ps1")

# How long a ledger entry is kept for a session nothing has said anything about: a day. A session that
# is gone leaves the targets, so nothing would ever report its mail taken and drop its entry.
$script:HordeWakeLedgerKeepSeconds = 86400
# After how long with no heartbeat the watcher is called stale: 40 passes at the default tick of 3 s.
$script:HordeWakeStaleSeconds = 120

function Get-HordeWakeSettings {
    # The watcher's settings, with -Overrides laid over the defaults (a test's, or the command's). A
    # name that is not a setting is refused: a mistyped one would otherwise silently leave the default.
    param([hashtable]$Overrides = @{})
    $s = [ordered]@{
        # A message a session is already reading as it arrives needs no knock: 3 s is one tick.
        minUnreadSeconds = 3
        # Wait after each attempt on one session: 5, 15, 45, 135, then 300 s for good. A session that
        # does not take its mail is asked again, but never hammered.
        backoffSeconds = @(5, 15, 45, 135, 300)
        # At most this many nudges in one pass over the whole fleet, so a restore of everything is a
        # queue and never a burst of typing into every session at once.
        maxNudgesPerPass = 1
        # A restore: at least this many sessions, and at least this share of all of them, started
        # inside one window of this many seconds.
        restoreMinSessions = 3
        restoreShare = 0.6
        restoreWindowSeconds = 600
        # A restored session has "moved" once its status changed this long after it started.
        movedSeconds = 60
        # A subsession is told to resume once its parent has moved, or after this long.
        goblinDelaySeconds = 180
        # With no session moved this long after the last one started, the warchief is told.
        stallSeconds = 300
        # A restore older than this is history: nothing is planned for it any more.
        restoreMaxAgeSeconds = 86400
        resumeText = "RESUME. Every session on this machine was restored and you have not taken a turn since. Background agents and shell commands from before the restore did not survive. Read your mail, check what of yours was in flight and whether it finished or died half-way, restart only what is needed, and nudge the subsessions you still need."
        stallText = "STALLED RESTORE. Every session on this machine was restored and none has taken a turn since. Each was told to resume. Check the sessions you still need."
    }
    foreach ($k in @($Overrides.Keys)) {
        if (-not $s.Contains("$k")) { throw ("'" + $k + "' is not a wake setting") }
        $s["$k"] = $Overrides[$k]
    }
    return [pscustomobject]$s
}

function Get-HordeWakeBackoffSeconds {
    # How long to wait after the -Attempts-th attempt on one session: the list's entry for it, and its
    # last entry for every attempt past the end. No attempt yet is no wait.
    param([int]$Attempts, $Settings)
    $steps = @($Settings.backoffSeconds)
    if ($Attempts -le 0 -or $steps.Count -eq 0) { return 0 }
    $index = [System.Math]::Min($Attempts, $steps.Count) - 1
    return [int]$steps[$index]
}

function Get-HordeWakeLedgerEntry {
    # One session's ledger entry, or $null when it has none.
    param($Ledger, [string]$Id)
    if ($null -eq $Ledger -or -not $Ledger.ContainsKey($Id)) { return $null }
    return $Ledger[$Id]
}

function Get-HordeWakeHold {
    # Why one session is not nudged now, as { action; reason }: skip (nothing to wake it for), wait
    # (something to wake it for, and a condition that does not hold), or ready (every condition holds;
    # only the fleet's rate limit can still hold it back). EACH CONDITION IS ITS OWN LINE, and each
    # unknown is wait: the file header says why.
    param($Target, $StateAnswer, $Entry, [datetime]$Now, $Settings)
    if ($null -eq $StateAnswer -or "$($StateAnswer.state)" -cne "known") {
        $why = "nothing answered for it"
        if ($null -ne $StateAnswer) { $why = "$($StateAnswer.reason)" }
        return [pscustomobject]@{ action = "wait"; reason = ("its state is unknown: " + $why) }
    }
    $s = $StateAnswer.value
    if ($s.unreadCount -le 0) { return [pscustomobject]@{ action = "skip"; reason = "no unread mail" } }
    if ("$($Target.reachable)" -cne "yes") { return [pscustomobject]@{ action = "wait"; reason = ("reachable is " + $Target.reachable) } }
    if ("$($s.midTurn)" -cne "no") { return [pscustomobject]@{ action = "wait"; reason = ("midTurn is " + $s.midTurn) } }
    if ("$($s.idle)" -cne "yes") { return [pscustomobject]@{ action = "wait"; reason = ("idle is " + $s.idle) } }
    if ("$($s.boxEmpty)" -cne "yes") { return [pscustomobject]@{ action = "wait"; reason = ("boxEmpty is " + $s.boxEmpty) } }
    $age = ($Now - $s.oldestUnreadAt).TotalSeconds
    if ($age -lt $Settings.minUnreadSeconds) { return [pscustomobject]@{ action = "wait"; reason = ("its oldest unread mail is younger than " + $Settings.minUnreadSeconds + " s") } }
    if ($null -ne $Entry) {
        $wait = Get-HordeWakeBackoffSeconds -Attempts $Entry.attempts -Settings $Settings
        $since = ($Now - $Entry.lastAttemptAt).TotalSeconds
        if ($since -lt $wait) { return [pscustomobject]@{ action = "wait"; reason = ("back-off: " + [int][System.Math]::Ceiling($wait - $since) + " s left of " + $wait + " after attempt " + $Entry.attempts) } }
    }
    return [pscustomobject]@{ action = "ready"; reason = "" }
}

function Get-HordeWakeDecisions {
    # One decision per target, in the targets' order: { id; action (nudge, wait or skip); reason }.
    #   -Targets  the port's list (Get-HordeWakeTargets' value)
    #   -States   session id -> the port's state ANSWER for it (known or unknown; missing is unknown)
    #   -Ledger   session id -> { attempts; lastAttemptAt; lastOutcome }
    # WHO GOES FIRST when more are ready than one pass may nudge: the session asked the fewest times,
    # then by role (warchief, orc, goblin, unknown), then the oldest unread mail. Fewest attempts first
    # is what makes a restore of everything a fair queue: without it the warchief's second knock, due
    # 5 s after its first, would go ahead of nine sessions nobody had knocked on yet. The rest get wait
    # "rate limit" and are ready again next pass.
    param($Targets, $States, $Ledger, [Parameter(Mandatory = $true)][datetime]$Now, $Settings = (Get-HordeWakeSettings))
    $roles = @(Get-HordeWakerRoles)
    $rows = New-Object System.Collections.ArrayList
    foreach ($t in @($Targets)) {
        if ($null -eq $t) { continue }
        $id = "$($t.id)"
        $answer = $null
        if ($null -ne $States -and $States.ContainsKey($id)) { $answer = $States[$id] }
        $entry = Get-HordeWakeLedgerEntry -Ledger $Ledger -Id $id
        $hold = Get-HordeWakeHold -Target $t -StateAnswer $answer -Entry $entry -Now $Now -Settings $Settings
        $row = [pscustomobject]@{ id = $id; action = $hold.action; reason = $hold.reason; attempts = 0; rank = $roles.Count; oldest = [datetime]::MaxValue }
        if ($hold.action -ceq "ready") {
            if ($null -ne $entry) { $row.attempts = [int]$entry.attempts }
            $at = [System.Array]::IndexOf($roles, "$($t.role)")
            if ($at -ge 0) { $row.rank = $at }
            $row.oldest = $answer.value.oldestUnreadAt
        }
        [void]$rows.Add($row)
    }
    $ready = @($rows | Where-Object { $_.action -ceq "ready" } | Sort-Object -Property attempts, rank, oldest, id)
    $allowed = [int]$Settings.maxNudgesPerPass
    for ($i = 0; $i -lt $ready.Count; $i++) {
        if ($i -lt $allowed) { $ready[$i].action = "nudge"; $ready[$i].reason = "unread mail, idle, empty box" }
        else { $ready[$i].action = "wait"; $ready[$i].reason = "rate limit" }
    }
    return @($rows | ForEach-Object { [pscustomobject]@{ id = $_.id; action = $_.action; reason = $_.reason } })
}

function Update-HordeWakeLedger {
    # The ledger after one pass, as a new table; -Ledger is not changed.
    #   -Decisions  the pass's decisions; only a session decided nudge can have been attempted
    #   -Outcomes   session id -> what the attempt came to (woken, busy, unreachable, nothing, unknown,
    #               or would-nudge in shadow)
    #   -States     session id -> the port's state answer
    # AN ATTEMPT COUNTS WHATEVER IT CAME TO: woken too, because "woken" is the waker's word and the
    # mail is what proves it - a session that was woken and still has unread mail next pass is asked
    # again after its back-off (a missed wake heals). MAIL TAKEN RESETS IT: a session known to have no
    # unread mail leaves the ledger, so its next message is knocked for at once.
    # "nothing" IS NOT AN ATTEMPT: the waker found the mail already taken and rang nobody, so nothing was
    # tried and nothing failed. It does not advance the back-off and is never counted against the session.
    param($Ledger, $Decisions, $Outcomes, $States, [Parameter(Mandatory = $true)][datetime]$Now)
    $next = @{}
    if ($null -ne $Ledger) { foreach ($k in @($Ledger.Keys)) { $next["$k"] = $Ledger[$k] } }
    foreach ($d in @($Decisions)) {
        if ($null -eq $d -or "$($d.action)" -cne "nudge") { continue }
        $id = "$($d.id)"
        if ($null -eq $Outcomes -or -not $Outcomes.ContainsKey($id)) { continue }
        if ("$($Outcomes[$id])" -ceq "nothing") { continue }
        $before = 0
        if ($next.ContainsKey($id)) { $before = [int]$next[$id].attempts }
        $next[$id] = [pscustomobject]@{ attempts = ($before + 1); lastAttemptAt = $Now; lastOutcome = "$($Outcomes[$id])" }
    }
    foreach ($id in @($next.Keys)) {
        $taken = $false
        if ($null -ne $States -and $States.ContainsKey($id)) { $a = $States[$id]; $taken = ("$($a.state)" -ceq "known" -and $a.value.unreadCount -le 0) }
        $old = (($Now - $next[$id].lastAttemptAt).TotalSeconds -gt $script:HordeWakeLedgerKeepSeconds)
        if ($taken -or $old) { $next.Remove($id) }
    }
    return $next
}

function ConvertTo-HordeWakeUuid {
    # A lowercase uuid made from text: its SHA-256, the first 32 hex digits, grouped. The recipe of the
    # decisions doorbell's notice id (decisions/Notify.ps1), copied so core does not load decisions.
    param([Parameter(Mandatory = $true)][string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hex = -join ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)) | ForEach-Object { $_.ToString("x2") }) } finally { $sha.Dispose() }
    return ($hex.Substring(0, 8) + "-" + $hex.Substring(8, 4) + "-" + $hex.Substring(12, 4) + "-" + $hex.Substring(16, 4) + "-" + $hex.Substring(20, 12))
}

function Get-HordeRestoreFinding {
    # Was every session restored? -Sessions is the fleet as it runs now, each { id; role; parent;
    # startedAt; lastChangeAt }. known { restoreId; windowStart; windowEnd; members; notMoved } when at
    # least restoreMinSessions of them, and at least restoreShare of all of them, started inside one
    # window of restoreWindowSeconds; absent, saying why, when not. Sessions do not start together by
    # chance: a quiet fleet's start times are hours apart, and one restarted session is one session.
    #
    # THE WINDOW is the one holding the most sessions, the earliest on a tie. windowStart is its first
    # start and windowEnd its last. restoreId is made from windowStart cut to the minute, so every pass
    # over the same restore - and a watcher restarted in the middle of it - names it the same way.
    # KNOWN LIMIT: a session that starts later, inside the window's length, joins the same restore; two
    # or more that start after it can make a later window the fullest and so give the restore a new id.
    # The resume mail is then posted once more to a session that still has not moved.
    #
    # A member has MOVED when its last status change is at least movedSeconds after its start: the
    # first status a restored session writes is its start, and one that never took a turn never
    # writes another.
    param($Sessions, [Parameter(Mandatory = $true)][datetime]$Now, $Settings = (Get-HordeWakeSettings))
    $all = @(@($Sessions) | Where-Object { $null -ne $_ -and $_.startedAt -is [datetime] -and $_.lastChangeAt -is [datetime] -and $_.startedAt -le $Now } | Sort-Object -Property startedAt, id)
    if ($all.Count -lt $Settings.restoreMinSessions) { return (New-HordeAbsent -Note ("" + $all.Count + " sessions are running, fewer than the " + $Settings.restoreMinSessions + " a restore takes")) }
    $best = @()
    for ($i = 0; $i -lt $all.Count; $i++) {
        $from = $all[$i].startedAt
        $until = $from.AddSeconds($Settings.restoreWindowSeconds)
        $inside = @($all | Where-Object { $_.startedAt -ge $from -and $_.startedAt -le $until })
        if ($inside.Count -gt $best.Count) { $best = $inside }
    }
    if ($best.Count -lt $Settings.restoreMinSessions) { return (New-HordeAbsent -Note ("at most " + $best.Count + " sessions started within " + $Settings.restoreWindowSeconds + " s of each other, fewer than the " + $Settings.restoreMinSessions + " a restore takes")) }
    if (($best.Count / $all.Count) -lt $Settings.restoreShare) { return (New-HordeAbsent -Note ("" + $best.Count + " of " + $all.Count + " sessions started within " + $Settings.restoreWindowSeconds + " s of each other, under the share of " + $Settings.restoreShare + " a restore takes")) }
    $windowStart = $best[0].startedAt
    $windowEnd = $best[$best.Count - 1].startedAt
    if (($Now - $windowEnd).TotalSeconds -gt $Settings.restoreMaxAgeSeconds) { return (New-HordeAbsent -Note ("the sessions were restored more than " + $Settings.restoreMaxAgeSeconds + " s ago, which is history")) }
    $members = @($best | ForEach-Object {
            $moved = (($_.lastChangeAt - $_.startedAt).TotalSeconds -ge $Settings.movedSeconds)
            [pscustomobject]@{ id = "$($_.id)"; role = "$($_.role)"; parent = "$($_.parent)"; startedAt = $_.startedAt; lastChangeAt = $_.lastChangeAt; moved = $moved }
        })
    $minute = New-Object System.DateTime($windowStart.Year, $windowStart.Month, $windowStart.Day, $windowStart.Hour, $windowStart.Minute, 0, [System.DateTimeKind]::Utc)
    $restoreId = ConvertTo-HordeWakeUuid -Text ("horde-wake-restore`n" + $minute.ToString("yyyy-MM-ddTHH:mm", [System.Globalization.CultureInfo]::InvariantCulture))
    $notMoved = @($members | Where-Object { -not $_.moved } | ForEach-Object { $_.id })
    return (New-HordeKnown -Value ([pscustomobject]@{ restoreId = $restoreId; windowStart = $windowStart; windowEnd = $windowEnd; members = $members; notMoved = $notMoved }) -ObservedAt $Now)
}

function Get-HordeResumePlan {
    # The mails this pass should post for a restore, each { kind (resume or stall); to; messageId; body }.
    # -Finding is Get-HordeRestoreFinding's answer; anything but known plans nothing.
    #   - EVERY ORC THAT HAS NOT MOVED, AT ONCE: an orc owns work and is the one that knows what of it
    #     was in flight.
    #   - A SUBSESSION THAT HAS NOT MOVED, ONLY ONCE ITS PARENT HAS, or after goblinDelaySeconds from the
    #     window's end: its orc decides which of its subsessions it still needs, and one resumed first
    #     would restart work its orc is about to cancel. A session whose role nobody recorded is held
    #     the same way; the warchief is not mailed to resume - it is the one told when nothing moves.
    #   - THE STALL NOTICE, for the warchief, when stallSeconds have passed since the window's end and
    #     NO member has moved. to is "" when no member is the warchief.
    # THE IDS ARE MADE FROM THE RESTORE AND THE SESSION, so a pass that plans the same mail again -
    # every pass does, until the session moves - names the same message, and a post of it is idempotent.
    param($Finding, [Parameter(Mandatory = $true)][datetime]$Now, $Settings = (Get-HordeWakeSettings))
    if ($null -eq $Finding -or "$($Finding.state)" -cne "known") { return @() }
    $f = $Finding.value
    $sinceEnd = ($Now - $f.windowEnd).TotalSeconds
    $movedIds = @{}
    foreach ($m in @($f.members)) { if ($m.moved) { $movedIds[$m.id] = $true } }
    $plan = New-Object System.Collections.ArrayList
    foreach ($m in @($f.members)) {
        if ($m.moved -or $m.role -ceq "warchief") { continue }
        $due = ($m.role -ceq "orc")
        if (-not $due) { $due = ($m.parent -cne "" -and $movedIds.ContainsKey($m.parent)) }
        if (-not $due) { $due = ($sinceEnd -ge $Settings.goblinDelaySeconds) }
        if (-not $due) { continue }
        [void]$plan.Add([pscustomobject]@{ kind = "resume"; to = $m.id; messageId = (ConvertTo-HordeWakeUuid -Text ("horde-wake-resume`n" + $f.restoreId + "`n" + $m.id.ToLowerInvariant())); body = "$($Settings.resumeText)" })
    }
    if ($sinceEnd -ge $Settings.stallSeconds -and $movedIds.Count -eq 0) {
        $chief = @($f.members | Where-Object { $_.role -ceq "warchief" }) | Select-Object -First 1
        $to = ""
        if ($null -ne $chief) { $to = $chief.id }
        [void]$plan.Add([pscustomobject]@{ kind = "stall"; to = $to; messageId = (ConvertTo-HordeWakeUuid -Text ("horde-wake-stall`n" + $f.restoreId)); body = "$($Settings.stallText)" })
    }
    return $plan.ToArray()
}

function New-HordeWakeEntry {
    # One journal line: { at; kind; id; outcome; reason }, and messageId for a mail.
    param([datetime]$At, [string]$Kind, [string]$Id = "", [string]$Outcome = "", [string]$Reason = "", [string]$MessageId = "")
    $e = [ordered]@{ at = $At; kind = $Kind; id = $Id; outcome = $Outcome; reason = $Reason }
    if ($MessageId -ne "") { $e["messageId"] = $MessageId }
    return [pscustomobject]$e
}

function Invoke-HordeWakePass {
    # ONE PASS. Reads the targets and each one's state through the port, decides, and acts; returns
    # { ledger; entries; posted; decisions }. It reads no clock and no file: the loop passes -Now and
    # keeps what comes back.
    #   -Waker            a registered waker, or $null when none is installed: then nobody is nudged,
    #                     and the restore half below still runs
    #   -Ledger           session id -> { attempts; lastAttemptAt; lastOutcome }, from the last pass
    #   -Shadow           JOURNAL WHAT IT WOULD DO, AND DO NONE OF IT: no nudge is sent and no mail is
    #                     posted. A would-nudge still counts as an attempt in the ledger, so the journal
    #                     shows the rhythm a live run would have had instead of a line every pass.
    #   -RestoreSessions  the running sessions (Get-HordeRestoreSessions' value), or $null to leave the
    #                     restore half out of this pass
    #   -Post             param($Mail) -> a tristate answer, known when the mail was taken; $Mail is
    #                     { kind; to; messageId; body }. Never called in shadow.
    #   -Posted           messageId -> $true for the mails already posted, from the last pass
    # THE ENTRIES are the journal lines, kinds: nudge, would-nudge, post, would-post, stall, would-stall
    # and skip-unknown (a listing or a state the port could not give; id is "" for the listing).
    param($Waker, [Parameter(Mandatory = $true)][datetime]$Now, $Settings = (Get-HordeWakeSettings), $Ledger = @{}, [switch]$Shadow, $RestoreSessions = $null, [scriptblock]$Post = $null, $Posted = @{})
    $entries = New-Object System.Collections.ArrayList
    $nextLedger = $Ledger
    $decisions = @()
    if ($null -ne $Waker) {
        $listing = Get-HordeWakeTargets -Waker $Waker
        if ($listing.state -cne "known") {
            [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "skip-unknown" -Outcome "unknown" -Reason ("the targets are unknown: " + $listing.reason)))
        } else {
            $targets = @($listing.value)
            $states = @{}
            foreach ($t in $targets) {
                $states[$t.id] = Get-HordeWakeState -Waker $Waker -Id $t.id
                if ($states[$t.id].state -cne "known") { [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "skip-unknown" -Id $t.id -Outcome "unknown" -Reason "$($states[$t.id].reason)")) }
            }
            $decisions = @(Get-HordeWakeDecisions -Targets $targets -States $states -Ledger $Ledger -Now $Now -Settings $Settings)
            $outcomes = @{}
            foreach ($d in $decisions) {
                if ($d.action -cne "nudge") { continue }
                # SHADOW: the nudge is journaled and counted, and nothing is asked of the waker.
                if ($Shadow) { $outcomes[$d.id] = "would-nudge"; [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "would-nudge" -Id $d.id -Outcome "would-nudge" -Reason $d.reason)); continue }
                $rang = Send-HordeWakeNudge -Waker $Waker -Id $d.id
                if ($rang.state -ceq "known") { $outcomes[$d.id] = $rang.value.outcome; [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "nudge" -Id $d.id -Outcome $rang.value.outcome -Reason $rang.value.reason)) }
                else { $outcomes[$d.id] = "unknown"; [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "nudge" -Id $d.id -Outcome "unknown" -Reason "$($rang.reason)")) }
            }
            $nextLedger = Update-HordeWakeLedger -Ledger $Ledger -Decisions $decisions -Outcomes $outcomes -States $states -Now $Now
        }
    }
    $nextPosted = @{}
    if ($null -ne $Posted) { foreach ($k in @($Posted.Keys)) { $nextPosted["$k"] = $true } }
    if ($null -ne $RestoreSessions) {
        $finding = Get-HordeRestoreFinding -Sessions $RestoreSessions -Now $Now -Settings $Settings
        foreach ($mail in @(Get-HordeResumePlan -Finding $finding -Now $Now -Settings $Settings)) {
            if ($nextPosted.ContainsKey($mail.messageId)) { continue }
            $kind = "post"
            if ($mail.kind -ceq "stall") { $kind = "stall" }
            # SHADOW: the mail is journaled once and marked, and nothing is handed to the poster.
            if ($Shadow) { $nextPosted[$mail.messageId] = $true; [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind ("would-" + $kind) -Id $mail.to -Outcome ("would-" + $kind) -Reason ("restore " + $finding.value.restoreId) -MessageId $mail.messageId)); continue }
            if ($mail.to -ceq "") { [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind $kind -Outcome "unposted" -Reason "no restored session is the warchief, so nobody can be told" -MessageId $mail.messageId)); continue }
            if ($null -eq $Post) { [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind $kind -Id $mail.to -Outcome "unposted" -Reason "the pass was given nothing to post through" -MessageId $mail.messageId)); continue }
            $took = $null
            try { $took = & $Post $mail } catch { $took = New-HordeUnknown -Reason "the post failed" -ErrorRecord $_ }
            if ((Test-HordeAnswer $took) -and $took.state -ceq "known") {
                $nextPosted[$mail.messageId] = $true
                [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind $kind -Id $mail.to -Outcome "posted" -Reason ("restore " + $finding.value.restoreId) -MessageId $mail.messageId))
            } else {
                $why = "the post answered with something that is not an answer"
                if (Test-HordeAnswer $took) { $why = "$($took.reason)" }
                [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind $kind -Id $mail.to -Outcome "unknown" -Reason $why -MessageId $mail.messageId))
            }
        }
    }
    return [pscustomobject]@{ ledger = $nextLedger; entries = $entries.ToArray(); posted = $nextPosted; decisions = $decisions }
}

function Select-HordeWakeNewEntries {
    # The entries worth a journal line, given what the last pass could not read. A skip-unknown is
    # written when it starts, or when its reason changes, and not on every pass while it lasts: at a
    # tick of 3 s one unreadable session would otherwise write 28,800 lines a day. Returns
    # { entries; unknown }, unknown being this pass's table (id -> reason) to hand to the next call.
    param($Entries, $Unknown = @{})
    $keep = New-Object System.Collections.ArrayList
    $now = @{}
    foreach ($e in @($Entries)) {
        if ($null -eq $e) { continue }
        if ("$($e.kind)" -cne "skip-unknown") { [void]$keep.Add($e); continue }
        $now["$($e.id)"] = "$($e.reason)"
        if ($null -ne $Unknown -and $Unknown.ContainsKey("$($e.id)") -and "$($Unknown["$($e.id)"])" -ceq "$($e.reason)") { continue }
        [void]$keep.Add($e)
    }
    return [pscustomobject]@{ entries = $keep.ToArray(); unknown = $now }
}

function Get-HordeRestoreSessions {
    # The running sessions, for Get-HordeRestoreFinding: known, a list of { id; role; parent; startedAt;
    # lastChangeAt } (and leftOut, below), or unknown with the reason. startedAt is the session's own (core/Identity.ps1);
    # lastChangeAt is when its live status was last written; role and parent are its registry record's
    # (role "unknown" and parent "" where the record says neither - never guessed, core/Roles.ps1).
    #
    # Both times are UTC as core/Identity.ps1 gives them (it reads epoch milliseconds), so neither is converted.
    # ONLY A SESSION SEEN ALIVE COUNTS: one whose start and live status are both known. A control file
    # left by a process that is gone has an unknown status and is not a running session.
    # AN AGENT WHOSE LISTING IS NOT WHOLE IS LEFT OUT, AND SAID SO; ONLY WHEN NONE IS WHOLE IS THE ANSWER
    # UNKNOWN. The first version made any one listing that was not whole the whole answer's unknown.
    # Measured 2026-10-13 on a machine that runs one agent program: it has no control directory for the
    # other, that listing is never whole, and the restore source never worked. So sessions are taken from
    # the agents whose listing is whole; a session under an agent whose listing is not is left out, since
    # part of a listing is not a count; and the known answer carries leftOut, a list of { agent; reason },
    # beside its value - which stays the plain list Get-HordeRestoreFinding takes - for the caller to
    # journal. The registry must be whole, as before: every session's role and parent come from it.
    # BOTH SOURCES ARE PARAMETERS, so a test hands in its own and never reads this machine.
    param($Identity = $null, $Registry = $null)
    try {
        if ($null -eq $Identity) { $Identity = Get-HordeIdentity }
        if ($null -eq $Registry) { $Registry = Read-HordeRegistry -Root (Get-HordeWezfleetRoot) }
    } catch { return (New-HordeUnknown -Reason "the sessions could not be read" -ErrorRecord $_) }
    $whole = @{}
    $leftOut = New-Object System.Collections.ArrayList
    foreach ($agent in @($Identity.complete.Keys)) {
        $listed = $Identity.complete[$agent]
        if ("$($listed.state)" -ceq "known") { $whole["$agent"] = $true }
        else { [void]$leftOut.Add([pscustomobject]@{ agent = "$agent"; reason = "$($listed.reason)" }) }
    }
    if ($whole.Count -eq 0) { return (New-HordeUnknown -Reason ("no agent's listing of sessions is whole: " + (@($leftOut | ForEach-Object { $_.agent + ": " + $_.reason }) -join "; "))) }
    if ("$($Registry.complete.state)" -cne "known") { return (New-HordeUnknown -Reason ("the session registry is not whole: " + $Registry.complete.reason)) }
    $out = New-Object System.Collections.ArrayList
    foreach ($id in @($Identity.records.Keys)) {
        $fields = $Identity.records[$id].fields
        $started = $fields["startedAt"]
        $status = $fields["liveStatus"]
        $of = $fields["agent"]
        if ("$($of.state)" -cne "known" -or -not $whole.ContainsKey("$($of.value)")) { continue }
        if ("$($started.state)" -cne "known" -or $started.value -isnot [datetime]) { continue }
        if ("$($status.state)" -cne "known" -or $status.observedAt -isnot [datetime]) { continue }
        $role = "unknown"
        $parent = ""
        if ($Registry.records.ContainsKey($id)) {
            $record = $Registry.records[$id].record
            $read = Read-HordeRecordRole -Record $record
            if ("$($read.role.state)" -ceq "known") { $role = "$($read.role.value)" }
            $held = Get-HordeStoredField -Record $record -Name "parent"
            if ("$($held.state)" -ceq "known") { $parent = "$($held.value)" }
        }
        [void]$out.Add([pscustomobject]@{ id = "$id"; role = $role; parent = $parent; startedAt = $started.value; lastChangeAt = $status.observedAt })
    }
    $answer = New-HordeKnown -Value $out.ToArray() -ObservedAt ([datetime]::UtcNow)
    Add-Member -InputObject $answer -MemberType NoteProperty -Name "leftOut" -Value $leftOut.ToArray()
    return $answer
}

# ---- the files: <home>\wake\journal.jsonl, heartbeat.json and ledger.json ----
# Kept apart from everything above, which reads and writes none. Only the command's loop calls these.

function Get-HordeWakeFolder {
    param([string]$HordeHome = (Get-HordeHome))
    return (Join-Path $HordeHome "wake")
}

function Get-HordeWakeStaleSeconds {
    return $script:HordeWakeStaleSeconds
}

function ConvertTo-HordeWakeTimeText {
    # A UTC time as text that reads back as the same instant.
    param([datetime]$At)
    return $At.ToUniversalTime().ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertFrom-HordeWakeTimeText {
    # The time ConvertTo-HordeWakeTimeText wrote, as UTC, or $null when it is not one. Text with no
    # zone is not a time here: it cannot be placed (core/Tristate.ps1).
    param($Text)
    if ($Text -is [datetime]) { return $Text.ToUniversalTime() }
    $parsed = [datetime]::MinValue
    if ($Text -isnot [string] -or -not [datetime]::TryParse($Text, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) { return $null }
    if ($parsed.Kind -eq [System.DateTimeKind]::Unspecified) { return $null }
    return $parsed.ToUniversalTime()
}

function Write-HordeWakeFile {
    # Replace one file under the wake folder whole: written beside it, then renamed over it in one step
    # (core/FileAtomic.ps1), so a reader sees the old file or the new one and never half of either.
    param([string]$Path, [string]$Text)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $temp = $Path + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    [System.IO.File]::WriteAllText($temp, $Text, (New-Object System.Text.UTF8Encoding($false)))
    try { Move-HordeFileAtomic -From $temp -To $Path }
    catch { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue; throw }
}

function Write-HordeWakeJournal {
    # Append each entry to journal.jsonl as one line of JSON. Returns how many lines it wrote.
    param($Entries, [string]$HordeHome = (Get-HordeHome))
    $lines = New-Object System.Collections.ArrayList
    foreach ($e in @($Entries)) {
        if ($null -eq $e) { continue }
        $row = [ordered]@{ at = (ConvertTo-HordeWakeTimeText $e.at); kind = "$($e.kind)"; id = "$($e.id)"; outcome = "$($e.outcome)"; reason = "$($e.reason)" }
        if ($null -ne $e.PSObject.Properties["messageId"]) { $row["messageId"] = "$($e.messageId)" }
        [void]$lines.Add((ConvertTo-Json -InputObject $row -Compress))
    }
    if ($lines.Count -eq 0) { return 0 }
    $dir = Get-HordeWakeFolder -HordeHome $HordeHome
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::AppendAllText((Join-Path $dir "journal.jsonl"), (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
    return $lines.Count
}

function Read-HordeWakeJournalTail {
    # The journal's last -Count lines, as they were written; none when there is no journal.
    param([int]$Count = 10, [string]$HordeHome = (Get-HordeHome))
    $path = Join-Path (Get-HordeWakeFolder -HordeHome $HordeHome) "journal.jsonl"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }
    $lines = @((Read-HordeSharedText -Path $path) -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
    if ($lines.Count -le $Count) { return $lines }
    return @($lines[($lines.Count - $Count)..($lines.Count - 1)])
}

function Write-HordeWakeHeartbeat {
    # heartbeat.json, replaced whole every pass: { at; pid; pass; shadow }. It is how anything else
    # tells a watcher that is running from one that is not.
    param([Parameter(Mandatory = $true)][datetime]$At, [Parameter(Mandatory = $true)][int]$ProcessId, [Parameter(Mandatory = $true)][long]$Pass, [switch]$Shadow, [string]$HordeHome = (Get-HordeHome))
    $beat = [ordered]@{ at = (ConvertTo-HordeWakeTimeText $At); pid = $ProcessId; pass = $Pass; shadow = [bool]$Shadow }
    Write-HordeWakeFile -Path (Join-Path (Get-HordeWakeFolder -HordeHome $HordeHome) "heartbeat.json") -Text (ConvertTo-Json -InputObject $beat -Compress)
}

function Read-HordeWakeHeartbeat {
    # The last heartbeat: known { at; pid; pass; shadow }, absent when the watcher never ran here, or
    # unknown when the file cannot be read as one.
    param([string]$HordeHome = (Get-HordeHome))
    $path = Join-Path (Get-HordeWakeFolder -HordeHome $HordeHome) "heartbeat.json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return (New-HordeAbsent -Note "the wake watcher has never run in this home: there is no heartbeat") }
    try { $j = (Read-HordeSharedText -Path $path) | ConvertFrom-Json }
    catch { return (New-HordeUnknown -Reason "the heartbeat could not be read" -ErrorRecord $_) }
    $at = $null
    if ($null -ne $j -and $null -ne $j.PSObject.Properties["at"]) { $at = ConvertFrom-HordeWakeTimeText $j.at }
    if ($null -eq $at) { return (New-HordeUnknown -Reason "the heartbeat holds no time") }
    $beat = [ordered]@{ at = $at; pid = 0; pass = [long]0; shadow = $false }
    foreach ($n in @("pid", "pass", "shadow")) { if ($null -ne $j.PSObject.Properties[$n]) { $beat[$n] = $j.$n } }
    return (New-HordeKnown -Value ([pscustomobject]$beat) -ObservedAt $at)
}

function Save-HordeWakeLedger {
    # ledger.json, replaced whole: the back-off of every session being asked, and the mails already
    # posted, so a watcher that is restarted neither knocks at once on a session it had been told to
    # leave for five minutes nor posts a resume mail a second time.
    param($Ledger, $Posted = @{}, [string]$HordeHome = (Get-HordeHome))
    $sessions = New-Object System.Collections.ArrayList
    if ($null -ne $Ledger) {
        foreach ($id in @($Ledger.Keys | Sort-Object)) {
            [void]$sessions.Add([ordered]@{ id = "$id"; attempts = [int]$Ledger[$id].attempts; lastAttemptAt = (ConvertTo-HordeWakeTimeText $Ledger[$id].lastAttemptAt); lastOutcome = "$($Ledger[$id].lastOutcome)" })
        }
    }
    $ids = @()
    if ($null -ne $Posted) { $ids = @($Posted.Keys | Sort-Object | ForEach-Object { "$_" }) }
    $doc = [ordered]@{ schemaVersion = 1; sessions = $sessions.ToArray(); posted = $ids }
    Write-HordeWakeFile -Path (Join-Path (Get-HordeWakeFolder -HordeHome $HordeHome) "ledger.json") -Text (ConvertTo-Json -InputObject $doc -Depth 5 -Compress)
}

function Read-HordeWakeLedger {
    # What Save-HordeWakeLedger wrote: known { ledger; posted }, absent when there is none, or unknown
    # when it cannot be read - the caller then starts from an empty ledger and says so.
    param([string]$HordeHome = (Get-HordeHome))
    $path = Join-Path (Get-HordeWakeFolder -HordeHome $HordeHome) "ledger.json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return (New-HordeAbsent -Note "no ledger was saved in this home") }
    try { $j = (Read-HordeSharedText -Path $path) | ConvertFrom-Json }
    catch { return (New-HordeUnknown -Reason "the saved ledger could not be read" -ErrorRecord $_) }
    if ($null -eq $j -or $null -eq $j.PSObject.Properties["sessions"] -or $null -eq $j.PSObject.Properties["posted"]) { return (New-HordeUnknown -Reason "the saved ledger is not a ledger") }
    $ledger = @{}
    try {
        foreach ($row in @($j.sessions)) {
            if ($null -eq $row) { continue }
            $at = ConvertFrom-HordeWakeTimeText $row.lastAttemptAt
            if ($null -eq $at -or "$($row.id)" -eq "") { return (New-HordeUnknown -Reason "the saved ledger holds an entry with no session or no time") }
            $ledger["$($row.id)"] = [pscustomobject]@{ attempts = [int]$row.attempts; lastAttemptAt = $at; lastOutcome = "$($row.lastOutcome)" }
        }
    } catch { return (New-HordeUnknown -Reason "the saved ledger holds an entry that is not one" -ErrorRecord $_) }
    $posted = @{}
    foreach ($id in @($j.posted)) { if ($null -ne $id -and "$id" -ne "") { $posted["$id"] = $true } }
    return (New-HordeKnown -Value ([pscustomobject]@{ ledger = $ledger; posted = $posted }))
}
