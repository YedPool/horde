# core/RestoreSource - after every session was started or restored together, tell the orcs to resume.
#
# A SENDER, NOT PART OF THE WATCHER. The wake watcher (core/Wake.ps1) only wakes: it types one pointer
# line into a session that has unread mail. It knows nothing of restores, and needs to know nothing: to
# it, a restore of everything is ten sessions with unread mail instead of one. What a restore DOES need
# is for somebody to post that mail, because after a restore nobody is running to post anything. That
# somebody is this module, and posting is all it does: it finds that the fleet's sessions were brought
# back together, posts one resume mail to each orc that has not taken a turn since, and tells the
# warchief when nothing moved. The watcher then knocks for that mail like any other. The first version
# (PR #207) had the watcher's pass do both; its review (2026-10-13) asked for the two responsibilities
# to be kept apart, as posting and waking are everywhere else (wakers/Port.ps1).
#
# PURE WHERE IT DECIDES. Get-HordeRestoreFinding and Get-HordeResumePlan read no clock, no file and no
# port; the time is always -Now. Invoke-HordeRestoreSourcePass is one pass and does no file I/O. The
# reader of the running sessions and the file of what was posted are apart, at the bottom.
#
# IT POSTS THROUGH THE MESSENGER PORT, as the decisions doorbell does (decisions/Notify.ps1): it names no
# messenger, states what it needs, and takes the one loaded messenger that offers it
# (Send-HordeRestoreMail). It needs body.untyped (a resume mail typed into an input box is the defect
# family the fleet's mail was built to end), idempotent.post (every mail's id is made from the restore
# and the session, and a pass that plans it again must be the same one message), and receipt.receiver.
# NOT wake: waking is the watcher's, and a sender that also knocked would be the two responsibilities
# joined again. WHY receipt.receiver, which this module never reads: the in-process test messenger
# offers the first two, so with only those required a machine that has it and a real messenger loaded
# has two that qualify, and the port never chooses between two - nothing would ever be posted. It
# declines receipt.receiver so that production paths cannot pick it (messengers/Port.ps1), and requiring
# it here is how this one does not. Like core/Wake.ps1 with the waker port, this core file loads a port
# that lives beside its adapters, because it calls it.
# NOTHING POSTS LIVE YET: `horde wake run` refuses without -Shadow, and the shadow tick (core/WakeRun.ps1)
# hands the pass no poster. The poster is built and tested here so that the day the live tick lands it
# is a call, not a design.
#
# EVERY TIME IS UTC.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). It runs under -Version Latest.

. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "TextUuid.ps1")
. (Join-Path $PSScriptRoot "ReadShared.ps1")
. (Join-Path $PSScriptRoot "Identity.ps1")
. (Join-Path $PSScriptRoot "WezfleetState.ps1")
. (Join-Path $PSScriptRoot "WakeFiles.ps1")
. (Join-Path $PSScriptRoot "Device.ps1")
# The port the mails are posted through (the header says why it is loaded from here).
. (Join-Path (Split-Path -Parent $PSScriptRoot) "messengers\Port.ps1")

# What the restore source needs of a messenger (the header).
$script:HordeRestoreSourceMessengerNeeds = @("body.untyped", "idempotent.post", "receipt.receiver")
# WHO A RESUME MAIL IS FROM: this module, by a name of its own in place of a session id - it is not a
# session - as the decisions doorbell names itself.
$script:HordeRestoreSourceFrom = "horde-restore-source"
# The stages at which a mail is in the session's mailbox or further (messengers/Port.ps1, THE STAGES).
$script:HordeRestoreSourceStages = @("accepted", "handed-over", "seen")

function Get-HordeRestoreSettings {
    # The restore source's settings, with -Overrides laid over the defaults. A name that is not a
    # setting is refused: a mistyped one would otherwise silently leave the default.
    param([hashtable]$Overrides = @{})
    $s = [ordered]@{
        # A restore: at least this many sessions, and at least this share of all of them, started
        # inside one window of this many seconds.
        restoreMinSessions = 3
        restoreShare = 0.6
        restoreWindowSeconds = 600
        # A session has an earlier life when its registry record was first seen at least this long before
        # it started. A session writes its record seconds AFTER it starts, so any margin tells a session
        # that was brought back from one that was just spawned; 60 s is far outside clock jitter and far
        # inside the hours that lie between a session's first life and its restore.
        earlierLifeSeconds = 60
        # A restored session that is idle has "moved" once its status changed this long after it started.
        movedSeconds = 60
        # With no session moved this long after the last one started, the warchief is told.
        stallSeconds = 300
        # A restore older than this is history: nothing is planned for it any more.
        restoreMaxAgeSeconds = 86400
        # The hub label a resume mail wears as its sender. A messenger that knows senders by session id
        # or by label needs one of the two, and this sender is no session.
        fromLabel = "RS"
        # How long a resume mail may wait to be taken: as long as a restore is not yet history.
        mailTtlSeconds = 86400
        resumeText = "START OR RESTORE. Every session on this machine was started or restored together and you have not taken a turn since. Background agents and shell commands from before did not survive. Read your mail, check what of yours was in flight and whether it finished or died half-way, restart only what is needed, and mail the subsessions you still need: they are not woken unless you ask."
        stallText = "STALLED START OR RESTORE. Every session on this machine was started or restored together and none has taken a turn since. Each orc was told to resume. Check the sessions you still need."
    }
    foreach ($k in @($Overrides.Keys)) {
        if (-not $s.Contains("$k")) { throw ("'" + $k + "' is not a restore setting") }
        $s["$k"] = $Overrides[$k]
    }
    return [pscustomobject]$s
}

function Get-HordeRestoreFinding {
    # Was every session restored? -Sessions is the fleet as it runs now, each { id; role; parent;
    # startedAt; lastChangeAt; status; firstSeenAt }. known { restoreId; windowStart; windowEnd; members;
    # notMoved; anchor } when at least restoreMinSessions of the sessions that have an earlier life, and at least
    # restoreShare of them, started inside one window of restoreWindowSeconds; absent, saying why, when
    # not. Sessions do not start together by chance: a quiet fleet's start times are hours apart, and one
    # restarted session is one session.
    #
    # ONLY A SESSION WITH EVIDENCE OF AN EARLIER LIFE CAN HAVE BEEN RESTORED: its registry record was
    # first seen (firstSeenAt) at least earlierLifeSeconds BEFORE this start. The first version counted
    # every session that started in the window, and the review of PR #207 showed what that finds: three
    # subsessions spawned within ten minutes in a fleet of five are 3 of 5, a "restore", and each would
    # have been told every session was restored. A freshly spawned session has no earlier life and is
    # never a member. A session with no record, or a record with no first-seen time, is unknown, and
    # unknown is not a member and is never mailed. The share is taken among the sessions that have an
    # earlier life, so new sessions spawned around a real restore neither hide it nor join it.
    # THIS ALSO SETTLES THE MORNING START. A fleet of EXISTING sessions brought back up has an earlier
    # life and is handled exactly like a restore, which is wanted, and the resume text says "started or
    # restored" truthfully. A cold start of new sessions has none, and nothing is sent.
    #
    # THE WINDOW is the one holding the most sessions, the earliest on a tie. windowStart is its first
    # start and windowEnd its last.
    #
    # THE ID IS ANCHORED THE FIRST TIME A RESTORE IS FOUND. A new restore's id is made from windowStart
    # cut to the minute (core/TextUuid.ps1). But windowStart is the earliest member's start, and the
    # review of PR #207 found what follows from deriving the id from it on every pass: when that session
    # closes, the window starts later, the id changes, every mail's id changes with it, and each session
    # that has not moved is mailed again. So the caller hands back what it was given to save: -Known is
    # the saved restores, each { restoreId; windowStart; windowEnd }, and a window that overlaps a saved
    # one IS that restore and keeps its id, whoever has left or joined since. The answer's anchor is what
    # to save: the id, with the window widened to cover both. The function stays pure: it reads no file.
    #
    # A MEMBER HAS NOT MOVED ONLY WHEN IT IS IDLE NOW AND ITS LAST STATUS CHANGE IS LESS THAN movedSeconds
    # AFTER ITS START. The first version read the time alone, and the review of PR #207 found the hole:
    # a session in a long FIRST turn changed its status seconds after it started and has not changed it
    # since, so it read as not moved and would have been mailed RESUME in the middle of its work. A
    # session that is busy or waiting now is in a turn, and that is moving. A status that is not known is
    # never "not moved" either: unknown means no mail. The time rule that remains, for an idle session: the
    # first status a restored session writes is its start, and one that never took a turn never
    # writes another.
    param($Sessions, [Parameter(Mandatory = $true)][datetime]$Now, $Settings = (Get-HordeRestoreSettings), $Known = @())
    $all = @(@($Sessions) | Where-Object { $null -ne $_ -and $_.startedAt -is [datetime] -and $_.startedAt -le $Now } | Sort-Object -Property startedAt, id)
    $lived = @($all | Where-Object { $_.firstSeenAt -is [datetime] -and ($_.startedAt - $_.firstSeenAt).TotalSeconds -ge $Settings.earlierLifeSeconds })
    if ($lived.Count -lt $Settings.restoreMinSessions) { return (New-HordeAbsent -Note ("" + $lived.Count + " of the " + $all.Count + " running sessions have an earlier life, fewer than the " + $Settings.restoreMinSessions + " a restore takes")) }
    $best = @()
    for ($i = 0; $i -lt $lived.Count; $i++) {
        $from = $lived[$i].startedAt
        $until = $from.AddSeconds($Settings.restoreWindowSeconds)
        $inside = @($lived | Where-Object { $_.startedAt -ge $from -and $_.startedAt -le $until })
        if ($inside.Count -gt $best.Count) { $best = $inside }
    }
    if ($best.Count -lt $Settings.restoreMinSessions) { return (New-HordeAbsent -Note ("at most " + $best.Count + " sessions started within " + $Settings.restoreWindowSeconds + " s of each other, fewer than the " + $Settings.restoreMinSessions + " a restore takes")) }
    if (($best.Count / $lived.Count) -lt $Settings.restoreShare) { return (New-HordeAbsent -Note ("" + $best.Count + " of the " + $lived.Count + " sessions that have an earlier life started within " + $Settings.restoreWindowSeconds + " s of each other, under the share of " + $Settings.restoreShare + " a restore takes")) }
    $windowStart = $best[0].startedAt
    $windowEnd = $best[$best.Count - 1].startedAt
    if (($Now - $windowEnd).TotalSeconds -gt $Settings.restoreMaxAgeSeconds) { return (New-HordeAbsent -Note ("the sessions were restored more than " + $Settings.restoreMaxAgeSeconds + " s ago, which is history")) }
    $members = @($best | ForEach-Object {
            $resting = ("$($_.status)" -ceq "idle" -and $_.lastChangeAt -is [datetime])
            $moved = (-not $resting -or ($_.lastChangeAt - $_.startedAt).TotalSeconds -ge $Settings.movedSeconds)
            [pscustomobject]@{ id = "$($_.id)"; role = "$($_.role)"; parent = "$($_.parent)"; startedAt = $_.startedAt; lastChangeAt = $_.lastChangeAt; status = "$($_.status)"; moved = $moved }
        })
    $minute = New-Object System.DateTime($windowStart.Year, $windowStart.Month, $windowStart.Day, $windowStart.Hour, $windowStart.Minute, 0, [System.DateTimeKind]::Utc)
    $restoreId = ConvertTo-HordeTextUuid -Text ("horde-wake-restore`n" + $minute.ToString("yyyy-MM-ddTHH:mm", [System.Globalization.CultureInfo]::InvariantCulture))
    $anchor = [pscustomobject]@{ restoreId = $restoreId; windowStart = $windowStart; windowEnd = $windowEnd }
    $same = @(@($Known) | Where-Object { $null -ne $_ -and $_.windowStart -is [datetime] -and $_.windowEnd -is [datetime] -and $_.windowStart -le $windowEnd -and $_.windowEnd -ge $windowStart } | Sort-Object -Property windowStart) | Select-Object -First 1
    if ($null -ne $same) {
        $restoreId = "$($same.restoreId)"
        $from = $windowStart; if ($same.windowStart -lt $from) { $from = $same.windowStart }
        $until = $windowEnd; if ($same.windowEnd -gt $until) { $until = $same.windowEnd }
        $anchor = [pscustomobject]@{ restoreId = $restoreId; windowStart = $from; windowEnd = $until }
    }
    $notMoved = @($members | Where-Object { -not $_.moved } | ForEach-Object { $_.id })
    return (New-HordeKnown -Value ([pscustomobject]@{ restoreId = $restoreId; windowStart = $windowStart; windowEnd = $windowEnd; members = $members; notMoved = $notMoved; anchor = $anchor }) -ObservedAt $Now)
}

function Get-HordeResumePlan {
    # The mails this pass should post for a restore, each { kind (resume or stall); to; messageId; body }.
    # -Finding is Get-HordeRestoreFinding's answer; anything but known plans nothing.
    #   - EVERY ORC THAT HAS NOT MOVED, AT ONCE: an orc owns work and is the one that knows what of it
    #     was in flight.
    #   - NOBODY ELSE, EVER. A subsession, and a session whose role nobody recorded, is never mailed by
    #     the restore source - not when its parent has moved, and not after a delay (the first version
    #     released them after 180 s). Measured 2026-10-13 on a live fleet: the ten sessions a shadow pass
    #     would have resumed were mostly idle subsessions with nothing in flight, and waking those costs
    #     memory and tokens for nothing. An orc knows which of its subsessions it still needs and mails
    #     those itself; that mail is unread mail, which the wake rules above already knock for. The
    #     warchief is not mailed to resume either - it is the one told when nothing moves.
    #   - A START OF THE WHOLE FLEET LOOKS THE SAME AND IS HANDLED THE SAME: every session started inside
    #     one window and none has taken a turn. The resume text says "started or restored" for that.
    #   - THE STALL NOTICE, for the warchief, when stallSeconds have passed since the window's end and
    #     NO member has moved. to is "" when no member is the warchief.
    # THE IDS ARE MADE FROM THE RESTORE AND THE SESSION, so a pass that plans the same mail again -
    # every pass does, until the session moves - names the same message, and a post of it is idempotent.
    param($Finding, [Parameter(Mandatory = $true)][datetime]$Now, $Settings = (Get-HordeRestoreSettings))
    if ($null -eq $Finding -or "$($Finding.state)" -cne "known") { return @() }
    $f = $Finding.value
    $sinceEnd = ($Now - $f.windowEnd).TotalSeconds
    $movedIds = @{}
    foreach ($m in @($f.members)) { if ($m.moved) { $movedIds[$m.id] = $true } }
    $plan = New-Object System.Collections.ArrayList
    foreach ($m in @($f.members)) {
        if ($m.moved) { continue }
        if ($m.role -cne "orc") { continue }
        [void]$plan.Add([pscustomobject]@{ kind = "resume"; to = $m.id; messageId = (ConvertTo-HordeTextUuid -Text ("horde-wake-resume`n" + $f.restoreId + "`n" + $m.id.ToLowerInvariant())); body = "$($Settings.resumeText)" })
    }
    if ($sinceEnd -ge $Settings.stallSeconds -and $movedIds.Count -eq 0) {
        $chief = @($f.members | Where-Object { $_.role -ceq "warchief" }) | Select-Object -First 1
        $to = ""
        if ($null -ne $chief) { $to = $chief.id }
        [void]$plan.Add([pscustomobject]@{ kind = "stall"; to = $to; messageId = (ConvertTo-HordeTextUuid -Text ("horde-wake-stall`n" + $f.restoreId)); body = "$($Settings.stallText)" })
    }
    return $plan.ToArray()
}

function Invoke-HordeRestoreSourcePass {
    # ONE PASS of the restore source: find a restore among -Sessions, plan its mails, and post the ones
    # not posted yet. Returns { entries; posted; known }. It reads no clock and no file.
    #   -Sessions  the running sessions (Get-HordeRestoreSessions' value)
    #   -Shadow    JOURNAL WHAT IT WOULD POST, AND POST NONE OF IT. A would-post is marked so the journal
    #              says it once, not every pass.
    #   -Post      param($Mail) -> a tristate answer, known when the mail was taken; $Mail is
    #              { kind; to; messageId; body }. Never called in shadow.
    #   -Posted    messageId -> when it was posted, for the mails already posted, from the last pass
    #   -Known     the restores already found, each { restoreId; windowStart; windowEnd }, from the last
    #              pass: what keeps a restore's id the same (Get-HordeRestoreFinding). What comes back
    #              as known is that list with this pass's restore added or widened.
    # THE ENTRIES are journal lines of kind post or stall, or would-post and would-stall in shadow.
    param($Sessions, [Parameter(Mandatory = $true)][datetime]$Now, $Settings = (Get-HordeRestoreSettings), [switch]$Shadow, [scriptblock]$Post = $null, $Posted = @{}, $Known = @())
    $entries = New-Object System.Collections.ArrayList
    # WHAT IS OLDER THAN A RESTORE CAN BE IS DROPPED, from both tables: a restore older than
    # restoreMaxAgeSeconds is history and plans nothing, so neither its mails' ids nor its window can
    # matter again. The first version never dropped an id (review of PR #207), and the file only grew.
    $nextPosted = @{}
    if ($null -ne $Posted) {
        foreach ($k in @($Posted.Keys)) {
            $when = $Posted[$k]
            if ($when -isnot [datetime]) { $when = $Now }
            if (($Now - $when).TotalSeconds -le $Settings.restoreMaxAgeSeconds) { $nextPosted["$k"] = $when }
        }
    }
    $finding = Get-HordeRestoreFinding -Sessions $Sessions -Now $Now -Settings $Settings -Known $Known
    $nextKnown = @(@($Known) | Where-Object { $null -ne $_ -and $_.windowEnd -is [datetime] -and ($Now - $_.windowEnd).TotalSeconds -le $Settings.restoreMaxAgeSeconds })
    if ($finding.state -ceq "known") { $nextKnown = @(@($nextKnown | Where-Object { "$($_.restoreId)" -cne $finding.value.anchor.restoreId }) + $finding.value.anchor) }
    foreach ($mail in @(Get-HordeResumePlan -Finding $finding -Now $Now -Settings $Settings)) {
        if ($nextPosted.ContainsKey($mail.messageId)) { continue }
        $kind = "post"
        if ($mail.kind -ceq "stall") { $kind = "stall" }
        # SHADOW: the mail is journaled once and marked, and nothing is handed to the poster.
        if ($Shadow) { $nextPosted[$mail.messageId] = $Now; [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind ("would-" + $kind) -Id $mail.to -Outcome ("would-" + $kind) -Reason ("restore " + $finding.value.restoreId) -MessageId $mail.messageId)); continue }
        if ($mail.to -ceq "") { [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind $kind -Outcome "unposted" -Reason "no restored session is the warchief, so nobody can be told" -MessageId $mail.messageId)); continue }
        if ($null -eq $Post) { [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind $kind -Id $mail.to -Outcome "unposted" -Reason "the pass was given nothing to post through" -MessageId $mail.messageId)); continue }
        $took = $null
        try { $took = & $Post $mail } catch { $took = New-HordeUnknown -Reason "the post failed" -ErrorRecord $_ }
        if ((Test-HordeAnswer $took) -and $took.state -ceq "known") {
            $nextPosted[$mail.messageId] = $Now
            [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind $kind -Id $mail.to -Outcome "posted" -Reason ("restore " + $finding.value.restoreId) -MessageId $mail.messageId))
        } else {
            $why = "the post answered with something that is not an answer"
            if (Test-HordeAnswer $took) { $why = "$($took.reason)" }
            [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind $kind -Id $mail.to -Outcome "unknown" -Reason $why -MessageId $mail.messageId))
        }
    }
    return [pscustomobject]@{ entries = $entries.ToArray(); posted = $nextPosted; known = $nextKnown }
}

function Send-HordeRestoreMail {
    # Post one planned mail ({ kind; to; messageId; body }, Get-HordeResumePlan's) to its session through
    # the messenger port. A tristate answer, as Invoke-HordeRestoreSourcePass's -Post must give: known
    # { messageId; stage; messenger } when the mail is in the session's mailbox or further, and unknown
    # with the reason for everything else - no messenger that offers what is needed, two that do, no
    # device id, a mail the port refused, a messenger that held it. NOTHING IS CLAIMED THAT DID NOT
    # HAPPEN: only known is marked posted, and what is not is planned and tried again by the next pass.
    # -Messenger is for a caller that holds one - a test hands in the in-process one - and is found
    # through the port when it is not given.
    param([Parameter(Mandatory = $true)]$Mail, $Settings = (Get-HordeRestoreSettings), $Messenger = $null, [string]$HordeHome = (Get-HordeHome))
    $through = $Messenger
    if ($null -eq $through) {
        $found = Find-HordeMessenger -Require $script:HordeRestoreSourceMessengerNeeds
        if ($found.state -cne "known") { return (New-HordeUnknown -Reason ("there is no messenger to post through: " + $found.reason)) }
        $through = $found.value
    }
    $deviceId = ""
    try { $deviceId = Get-HordeDeviceId -HomeRoot $HordeHome } catch { return (New-HordeUnknown -Reason "this machine's device id could not be had" -ErrorRecord $_) }
    $from = [pscustomobject]@{ deviceId = $deviceId; sessionId = $script:HordeRestoreSourceFrom; label = "$($Settings.fromLabel)" }
    $message = [pscustomobject]@{ messageId = "$($Mail.messageId)"; sessionId = "$($Mail.to)"; from = $from; body = "$($Mail.body)"; ttlSeconds = [int]$Settings.mailTtlSeconds }
    $posted = Send-HordeMessengerMessage -Messenger $through -Message $message
    if ($posted.state -cne "known") { return $posted }
    if ($script:HordeRestoreSourceStages -cnotcontains "$($posted.value.stage)") {
        $why = ""
        $p = $posted.value.PSObject.Properties["reason"]
        if ($null -ne $p) { $why = ": " + $p.Value }
        return (New-HordeUnknown -Reason ("the messenger answered " + $posted.value.stage + $why))
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ messageId = "$($Mail.messageId)"; stage = "$($posted.value.stage)"; messenger = "$($through.name)" }) -ObservedAt $posted.observedAt)
}

function Get-HordeRestoreSessions {
    # The running sessions, for Get-HordeRestoreFinding: known, a list of { id; role; parent; startedAt;
    # lastChangeAt; status; firstSeenAt } (and leftOut, below), or unknown with the reason. firstSeenAt
    # is when its registry record was first seen, or $null where it has no record or the record has no
    # such time: it is the evidence of an earlier life (Get-HordeRestoreFinding), and is never guessed. status is the session's
    # live status word as its agent wrote it (idle, busy, waiting): whether a session has moved since a
    # restore cannot be told from a time alone (Get-HordeRestoreFinding). startedAt is the session's own (core/Identity.ps1);
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
        $firstSeenAt = $null
        if ($Registry.records.ContainsKey($id)) {
            $record = $Registry.records[$id].record
            $read = Read-HordeRecordRole -Record $record
            if ("$($read.role.state)" -ceq "known") { $role = "$($read.role.value)" }
            $held = Get-HordeStoredField -Record $record -Name "parent"
            if ("$($held.state)" -ceq "known") { $parent = "$($held.value)" }
            $seen = Get-HordeStoredField -Record $record -Name "firstSeen"
            if ("$($seen.state)" -ceq "known") { $firstSeenAt = ConvertFrom-HordeWakeTimeText $seen.value }
        }
        [void]$out.Add([pscustomobject]@{ id = "$id"; role = $role; parent = $parent; startedAt = $started.value; lastChangeAt = $status.observedAt; status = "$($status.value)"; firstSeenAt = $firstSeenAt })
    }
    $answer = New-HordeKnown -Value $out.ToArray() -ObservedAt ([datetime]::UtcNow)
    Add-Member -InputObject $answer -MemberType NoteProperty -Name "leftOut" -Value $leftOut.ToArray()
    return $answer
}

# ---- the file: <home>\wake\restore.json, or restore-shadow.json for a shadow run ----
# Kept apart from everything above, which reads and writes none. Only the command's loop calls these.

function Save-HordeRestoreState {
    # restore.json, replaced whole: the ids of the mails already posted and the restores already found,
    # so a source that is restarted neither posts a resume mail a second time nor gives a restore it
    # had already named a new id. -Shadow names the shadow run's own file (core/WakeFiles.ps1,
    # Get-HordeWakeStateFile): a mail a shadow run only would have posted is never marked posted where
    # a live run reads.
    param($Posted = @{}, $Known = @(), [switch]$Shadow, [string]$HordeHome = (Get-HordeHome))
    $ids = @()
    if ($null -ne $Posted) { $ids = @($Posted.Keys | Sort-Object | ForEach-Object { [ordered]@{ id = "$_"; at = $(if ($Posted[$_] -is [datetime]) { ConvertTo-HordeWakeTimeText $Posted[$_] } else { "" }) } }) }
    $restores = @(@($Known) | Where-Object { $null -ne $_ } | ForEach-Object { [ordered]@{ restoreId = "$($_.restoreId)"; windowStart = (ConvertTo-HordeWakeTimeText $_.windowStart); windowEnd = (ConvertTo-HordeWakeTimeText $_.windowEnd) } })
    $doc = [ordered]@{ schemaVersion = 1; posted = $ids; restores = $restores }
    Write-HordeWakeFile -Path (Get-HordeWakeStateFile -Name "restore" -Shadow:$Shadow -HordeHome $HordeHome) -Text (ConvertTo-Json -InputObject $doc -Depth 5 -Compress)
}

function Read-HordeRestoreState {
    # What Save-HordeRestoreState wrote: known { posted; known }, absent when there is none, or unknown when it
    # cannot be read - the caller then starts from nothing posted and says so.
    param([switch]$Shadow, [string]$HordeHome = (Get-HordeHome))
    $path = Get-HordeWakeStateFile -Name "restore" -Shadow:$Shadow -HordeHome $HordeHome
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return (New-HordeAbsent -Note "no restore state was saved in this home") }
    try { $j = (Read-HordeSharedText -Path $path) | ConvertFrom-Json }
    catch { return (New-HordeUnknown -Reason "the saved restore state could not be read" -ErrorRecord $_) }
    if ($null -eq $j -or $null -eq $j.PSObject.Properties["posted"]) { return (New-HordeUnknown -Reason "the saved restore state is not one") }
    $posted = @{}
    try {
        foreach ($row in @($j.posted)) {
            if ($null -eq $row) { continue }
            if ("$($row.id)" -eq "") { return (New-HordeUnknown -Reason "the saved restore state holds a posted mail with no id") }
            # A mail with no time was posted at a time nobody wrote down; the next pass stamps it.
            $posted["$($row.id)"] = ConvertFrom-HordeWakeTimeText $row.at
        }
    } catch { return (New-HordeUnknown -Reason "the saved restore state holds a posted mail that is not one" -ErrorRecord $_) }
    $restores = New-Object System.Collections.ArrayList
    if ($null -ne $j.PSObject.Properties["restores"]) {
        try {
            foreach ($row in @($j.restores)) {
                if ($null -eq $row) { continue }
                $from = ConvertFrom-HordeWakeTimeText $row.windowStart
                $until = ConvertFrom-HordeWakeTimeText $row.windowEnd
                if ($null -eq $from -or $null -eq $until -or "$($row.restoreId)" -eq "") { return (New-HordeUnknown -Reason "the saved restore state holds a restore with no id or no time") }
                [void]$restores.Add([pscustomobject]@{ restoreId = "$($row.restoreId)"; windowStart = $from; windowEnd = $until })
            }
        } catch { return (New-HordeUnknown -Reason "the saved restore state holds a restore that is not one" -ErrorRecord $_) }
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ posted = $posted; known = $restores.ToArray() }))
}
