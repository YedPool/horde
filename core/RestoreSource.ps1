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
# IT POSTS THROUGH THE MESSENGER PORT, by core/WakeMail.ps1, which says what such a sender needs of a
# messenger and why (Send-HordeRestoreMail).
# NOTHING POSTS LIVE YET: the tick runs this source in shadow in every mode of the run (core/WakeRun.ps1
# says why, at the one switch that will turn it on). The poster is built and tested so that day is a
# switch, not a design.
#
# WHY THE WARCHIEF IS MAILED THE STALL NOTICE, WHEN "ONLY ORCS ARE MAILED RESUME". The two are different
# mails for different readers, and the difference is on purpose. A resume mail tells a session to pick
# its own work back up, and only an orc has work of its own to pick up. The stall notice tells nobody
# to do anything of its own: it says that every session was brought back and NOT ONE has moved, which
# is the state of the whole fleet, and the warchief is the one session whose business that is. Without
# it a fleet where nothing moved would sit silent, each orc holding a resume mail nobody wakes it for.
# Confirmed by the fleet's owner when the resume mails were narrowed to orcs: the stall line stays.
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
# How a sender that is not a session posts mail (the messenger port, and what it needs of a messenger).
. (Join-Path $PSScriptRoot "WakeMail.ps1")

# WHO A RESUME MAIL IS FROM: this module, by a name of its own in place of a session id - it is not a
# session - as the decisions doorbell names itself.
$script:HordeRestoreSourceFrom = "horde-restore-source"

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
        # A restored session has "moved" once its status changed this long after it started
        # (Get-HordeRestoreFinding, THREE ANSWERS, says where 30 comes from and what it cannot see).
        movedSeconds = 30
        # No resume mail is planned until this long after the last session of the restore started
        # (Get-HordeResumePlan, THE SETTLE TIME).
        restoreSettleSeconds = 120
        # With no session moved this long after the last one started, the warchief is told.
        stallSeconds = 300
        # A stall notice held back because a session named by more than one control file is uncounted is
        # held at most this long past stallSeconds (T-0116). A duplicate is normally one stray copy a
        # person closes within minutes; 30 minutes is long enough for that, and far inside
        # restoreMaxAgeSeconds, after which the restore is history and a notice held for ever would be
        # lost for good. Past it the warchief gets a true notice that names the sessions that could not be read.
        stallHeldSeconds = 1800
        # A restore older than this is history: nothing is planned for it any more.
        restoreMaxAgeSeconds = 86400
        # The hub label a resume mail wears as its sender. A messenger that knows senders by session id
        # or by label needs one of the two, and this sender is no session. RS is RESERVED: no session
        # may be given it (core/ReservedLabels.ps1), so a line from RS is never a session's.
        fromLabel = "RS"
        # How long a resume mail may wait to be taken: as long as a restore is not yet history.
        mailTtlSeconds = 86400
        # BOTH TEXTS SAY FIRST THAT THEY ARE AUTOMATED: the reader is an agent session, and it must not
        # take a machine's line for a person's instruction or answer it as one (review of PR #208).
        resumeText = "AUTOMATED, from the restore source: START OR RESTORE. Every session on this machine was started or restored together and you have not taken a turn since. Background agents and shell commands from before did not survive. Read your mail, check what of yours was in flight and whether it finished or died half-way, restart only what is needed, and mail the subsessions you still need: they are not woken unless you ask."
        stallDuplicatesText = "AUTOMATED, from the restore source: STALLED START OR RESTORE, BUT NOT ALL SESSIONS COULD BE READ. Every session on this machine that could be read was started or restored together and none of them has taken a turn since. {0} session(s) are each named by more than one control file and could not be told apart, so they were not counted and one of them may have moved: {1}. Each orc was told to resume. Check the sessions you still need."
        stallText = "AUTOMATED, from the restore source: STALLED START OR RESTORE. Every session on this machine was started or restored together and none has taken a turn since. Each orc was told to resume. Check the sessions you still need."
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
    # A DUPLICATE IS NOT A SESSION WE CAN COUNT, BUT IT IS NOT NOTHING (T-0116). A session named by more
    # than one control file is left out of -Sessions (core/Identity.ps1 chooses neither file), and
    # -UncountedDuplicates says how many. Each has an earlier life we cannot see, so ALL are counted in
    # the share's denominator: a duplicate may only LOWER the share, never raise it. Without that, 3
    # of 6 sessions that started together (no restore, under the 0.6 share) become 3 of 3 once the
    # three outside the window are dropped as duplicates, and orcs are told everything was restored.
    # The minimum counts (restoreMinSessions) stay on real members only. A true restore whose members
    # fall below that minimum while duplicates last is found when they clear, inside
    # restoreMaxAgeSeconds. The answer carries uncountedDuplicates, so Get-HordeResumePlan can hold the
    # stall notice: the duplicate may be the very session that moved.
    #
    # THE WINDOW is the one holding the most sessions, the earliest on a tie. windowStart is its first
    # start and windowEnd its last.
    #
    # THE ID IS ANCHORED THE FIRST TIME A RESTORE IS FOUND. A new restore's id is made from windowStart
    # cut to the minute (core/TextUuid.ps1). But windowStart is the earliest member's start, and the
    # review of PR #207 found what follows from deriving the id from it on every pass: when that session
    # closes, the window starts later, the id changes, every mail's id changes with it, and each session
    # that has not moved is mailed again. So the caller hands back what it was given to save: -Known is
    # the saved restores, each { restoreId; windowStart; windowEnd; members }, and the answer's anchor is
    # what to save: the id, the window widened to cover both, and each member's start. The function stays
    # pure: it reads no file.
    # THE SAME RESTORE IS ONE WHOSE SESSIONS ARE THE SAME LIVES (Test-HordeRestoreSame). The first anchor
    # went by the window alone, and the review of PR #208 found what that misses: a SECOND restore that
    # begins inside the first one's window overlaps it, took its id, and so every mail of it was already
    # "posted" and nobody was told. A restore gives every session a new start. So a window that overlaps
    # a saved restore is that restore only if most of the saved members that are still running started
    # when the saved restore says they did; if most of them started later, they were restored again, and
    # this is a new restore with an id of its own.
    #
    # THREE ANSWERS TO "HAS IT MOVED", each member's moved being yes, no or neither:
    #   yes      it is busy now, or its status last changed at least movedSeconds after it started
    #   no       it is idle now and its status last changed less than movedSeconds after it started
    #   neither  it has ended, its status is not known, or it is waiting and that status is as old as
    #            its start
    # ONLY yes SUPPRESSES THE STALL NOTICE, AND ONLY A no ORC IS MAILED. The first version read the time
    # alone, and the review of PR #207 found a session in a long FIRST turn read as not moved. The second
    # called everything that was not idle moved, and the review of PR #208 found the other side: one
    # session that had ended, or one stuck waiting on a prompt it met as it started, counted as "something
    # moved" and silenced the stall notice for a fleet that was dead. So what is neither proves nothing
    # either way: it is not mailed, because nobody knows it has not moved, and it does not speak for
    # the fleet, because nobody knows it has.
    # WHY 30 s, AND WHAT IT CANNOT SEE. A session's control file gives one time, that of its last status
    # change, so "took a turn and came back to idle" can only be told from "never took one" by how long
    # after the start that change was. Measured 2026-10-12 on ten sessions that had not taken a turn
    # since a restore: last change minus start was 0.3 to 11 s. 30 s is well clear of that, and half of
    # the 60 s this began with, which read an orc whose first turn ended inside a minute as not moved.
    # THE LIMIT THAT REMAINS: a first turn that ends within 30 s of the start still reads as no, and that
    # orc is sent the one resume line, which is harmless to a session that has in fact moved. No cheap
    # and sound second signal of a turn was found: the registry's lastSeen is rewritten by the start hook,
    # so it says nothing of a turn, and reading a transcript is neither cheap nor this module's to do.
    param($Sessions, [Parameter(Mandatory = $true)][datetime]$Now, $Settings = (Get-HordeRestoreSettings), $Known = @(), [int]$UncountedDuplicates = 0, [string[]]$DuplicateNames = @())
    if ($UncountedDuplicates -lt 0) { $UncountedDuplicates = 0 }
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
    $denominator = $lived.Count + $UncountedDuplicates
    if (($best.Count / $denominator) -lt $Settings.restoreShare) { return (New-HordeAbsent -Note ("" + $best.Count + " of the " + $denominator + " sessions that have an earlier life (" + $UncountedDuplicates + " of them duplicates, counted but not listed) started within " + $Settings.restoreWindowSeconds + " s of each other, under the share of " + $Settings.restoreShare + " a restore takes")) }
    $windowStart = $best[0].startedAt
    $windowEnd = $best[$best.Count - 1].startedAt
    if (($Now - $windowEnd).TotalSeconds -gt $Settings.restoreMaxAgeSeconds) { return (New-HordeAbsent -Note ("the sessions were restored more than " + $Settings.restoreMaxAgeSeconds + " s ago, which is history")) }
    $members = @($best | ForEach-Object {
            $late = ($_.lastChangeAt -is [datetime] -and ($_.lastChangeAt - $_.startedAt).TotalSeconds -ge $Settings.movedSeconds)
            $moved = "neither"
            if ("$($_.status)" -ceq "busy") { $moved = "yes" }
            elseif ("$($_.status)" -ceq "idle" -and $_.lastChangeAt -is [datetime]) { $moved = $(if ($late) { "yes" } else { "no" }) }
            elseif ("$($_.status)" -ceq "waiting" -and $late) { $moved = "yes" }
            [pscustomobject]@{ id = "$($_.id)"; role = "$($_.role)"; parent = "$($_.parent)"; startedAt = $_.startedAt; lastChangeAt = $_.lastChangeAt; status = "$($_.status)"; moved = $moved }
        })
    $minute = New-Object System.DateTime($windowStart.Year, $windowStart.Month, $windowStart.Day, $windowStart.Hour, $windowStart.Minute, 0, [System.DateTimeKind]::Utc)
    $restoreId = ConvertTo-HordeTextUuid -Text ("horde-wake-restore`n" + $minute.ToString("yyyy-MM-ddTHH:mm", [System.Globalization.CultureInfo]::InvariantCulture))
    $starts = New-Object System.Collections.Hashtable ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($b in $best) { $starts["$($b.id)"] = $b.startedAt }
    $same = @(@($Known) | Where-Object { Test-HordeRestoreSame -Saved $_ -Sessions $all -WindowStart $windowStart -WindowEnd $windowEnd } | Sort-Object -Property windowStart) | Select-Object -First 1
    if ($null -ne $same) {
        $restoreId = "$($same.restoreId)"
        $from = $windowStart; if ($same.windowStart -lt $from) { $from = $same.windowStart }
        $until = $windowEnd; if ($same.windowEnd -gt $until) { $until = $same.windowEnd }
        # Every start the saved restore recorded is kept, and this pass's members are added to them.
        foreach ($k in @($same.members.Keys)) { $starts["$k"] = $same.members[$k] }
        $windowOfAnchor = [pscustomobject]@{ from = $from; until = $until }
    } else {
        $windowOfAnchor = [pscustomobject]@{ from = $windowStart; until = $windowEnd }
        # A NEW RESTORE WHOSE ID A SAVED ONE ALREADY HAS: the second restore began in the first one's
        # minute. It is named from its own start to the second, so the two can never be one message.
        if (@(@($Known) | Where-Object { $null -ne $_ -and "$($_.restoreId)" -ceq $restoreId }).Count -gt 0) {
            $restoreId = ConvertTo-HordeTextUuid -Text ("horde-wake-restore`n" + $windowStart.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture) + "`nafter " + $restoreId)
        }
    }
    $anchor = [pscustomobject]@{ restoreId = $restoreId; windowStart = $windowOfAnchor.from; windowEnd = $windowOfAnchor.until; members = $starts }
    $notMoved = @($members | Where-Object { $_.moved -ceq "no" } | ForEach-Object { $_.id })
    return (New-HordeKnown -Value ([pscustomobject]@{ restoreId = $restoreId; windowStart = $windowStart; windowEnd = $windowEnd; members = $members; notMoved = $notMoved; anchor = $anchor; uncountedDuplicates = $UncountedDuplicates; duplicateNames = @($DuplicateNames) }) -ObservedAt $Now)
}

function Test-HordeRestoreSame {
    # Is the restore found now - its window from -WindowStart to -WindowEnd, among the running -Sessions -
    # the saved restore -Saved? Only when the windows overlap AND most of the saved members that are still
    # running have the start the saved restore recorded for them (Get-HordeRestoreFinding, THE SAME
    # RESTORE). A saved restore none of whose members is still running, or one saved before members were
    # recorded, shares no session with anything, and is not the same as anything.
    param($Saved, $Sessions, [datetime]$WindowStart, [datetime]$WindowEnd)
    if ($null -eq $Saved -or $Saved.windowStart -isnot [datetime] -or $Saved.windowEnd -isnot [datetime]) { return $false }
    if ($Saved.windowStart -gt $WindowEnd -or $Saved.windowEnd -lt $WindowStart) { return $false }
    $recorded = $null
    $p = $Saved.PSObject.Properties["members"]
    if ($null -ne $p) { $recorded = $p.Value }
    if ($recorded -isnot [System.Collections.IDictionary]) { return $false }
    $present = 0
    $unchanged = 0
    foreach ($s in @($Sessions)) {
        if ($null -eq $s -or -not $recorded.Contains("$($s.id)")) { continue }
        $present++
        # To the second: a start is saved as text and read back, and a fraction must not make a life new.
        if ([System.Math]::Abs(($s.startedAt - $recorded["$($s.id)"]).TotalSeconds) -lt 1) { $unchanged++ }
    }
    return ($present -gt 0 -and ($unchanged * 2) -gt $present)
}

function Get-HordeResumePlan {
    # The mails this pass should post for a restore, each { kind (resume or stall); to; messageId; body }.
    # -Finding is Get-HordeRestoreFinding's answer; anything but known plans nothing.
    #   - EVERY ORC THAT HAS NOT MOVED (moved no), ONCE THE SETTLE TIME HAS PASSED: an orc owns work and
    #     is the one that knows what of it was in flight.
    #   - THE SETTLE TIME: nothing is mailed to resume until restoreSettleSeconds after the window's end.
    #     The review of PR #208 raised a case nothing decided: a person restarts three long-lived
    #     sessions by hand within ten minutes, out of five. By the numbers that IS a restore - three
    #     sessions with an earlier life, 3 of 5, in one window - and it stays one: no count can tell a
    #     hand from a crash. What differs is that the person is there, and about to type to each. So the
    #     source waits two minutes before it mails anybody: a session its person talks to in that time
    #     reads as moved and is sent nothing, and an orc nobody came back to is mailed once the time is up.
    #     The stall notice does not wait on it: its time is stallSeconds, as before.
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
    #     NO member has moved (moved yes; a member that is neither does not count as one that has). to
    #     is "" when no member is the warchief.
    # THE IDS ARE MADE FROM THE RESTORE AND THE SESSION, so a pass that plans the same mail again -
    # every pass does, until the session moves - names the same message, and a post of it is idempotent.
    param($Finding, [Parameter(Mandatory = $true)][datetime]$Now, $Settings = (Get-HordeRestoreSettings))
    if ($null -eq $Finding -or "$($Finding.state)" -cne "known") { return @() }
    $f = $Finding.value
    $sinceEnd = ($Now - $f.windowEnd).TotalSeconds
    $movedIds = @{}
    foreach ($m in @($f.members)) { if ($m.moved -ceq "yes") { $movedIds[$m.id] = $true } }
    $plan = New-Object System.Collections.ArrayList
    foreach ($m in @($f.members)) {
        if ($sinceEnd -lt $Settings.restoreSettleSeconds) { continue }
        if ($m.moved -cne "no") { continue }
        if ($m.role -cne "orc") { continue }
        [void]$plan.Add([pscustomobject]@{ kind = "resume"; to = $m.id; messageId = (ConvertTo-HordeTextUuid -Text ("horde-wake-resume`n" + $f.restoreId + "`n" + $m.id.ToLowerInvariant())); body = "$($Settings.resumeText)" })
    }
    $dupes = 0
    if ($null -ne $f.PSObject.Properties["uncountedDuplicates"]) { $dupes = [int]$f.uncountedDuplicates }
    $heldFor = $Settings.stallSeconds
    if ($null -ne $Settings.PSObject.Properties["stallHeldSeconds"]) { $heldFor = $Settings.stallSeconds + $Settings.stallHeldSeconds }
    if ($sinceEnd -ge $heldFor -and $movedIds.Count -eq 0 -and $dupes -gt 0) {
        # THE HOLD HAS A BOUND (T-0116, stallHeldSeconds): a notice held for ever is lost once the restore is
        # history. Past the bound the warchief is told what is true - nothing counted moved, and these
        # sessions could not be read. It is the stall notice's own mail id, so it is posted once, counts as
        # told only when taken, and the plain notice that would follow if the duplicates clear is the same
        # mail and is not sent a second time.
        $chief = @($f.members | Where-Object { $_.role -ceq "warchief" }) | Select-Object -First 1
        $to = ""
        if ($null -ne $chief) { $to = $chief.id }
        $names = @()
        if ($null -ne $f.PSObject.Properties["duplicateNames"]) { $names = @($f.duplicateNames) }
        $namesText = "unnamed"
        if ($names.Count -gt 0) { $namesText = ($names -join ", ") }
        [void]$plan.Add([pscustomobject]@{ kind = "stall"; to = $to; messageId = (ConvertTo-HordeTextUuid -Text ("horde-wake-stall`n" + $f.restoreId)); body = ("$($Settings.stallDuplicatesText)" -f $dupes, $namesText) })
    } elseif ($sinceEnd -ge $Settings.stallSeconds -and $movedIds.Count -eq 0 -and $dupes -gt 0) {
        # NO STALL NOTICE WHILE A DUPLICATE LASTS (T-0116): the duplicate may be the one that moved. A
        # held kind is planned so the pass can say so once; the notice itself comes once the duplicate
        # clears (or the bound above passes), if it is still true.
        [void]$plan.Add([pscustomobject]@{ kind = "stall-held"; to = ""; messageId = (ConvertTo-HordeTextUuid -Text ("horde-wake-stall-held`n" + $f.restoreId)); body = "" })
    } elseif ($sinceEnd -ge $Settings.stallSeconds -and $movedIds.Count -eq 0) {
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
    #   -Known     the restores already found, each { restoreId; windowStart; windowEnd; members }, from the last
    #              pass: what keeps a restore's id the same (Get-HordeRestoreFinding). What comes back
    #              as known is that list with this pass's restore added or widened.
    # THE ENTRIES are journal lines of kind post or stall, or would-post and would-stall in shadow.
    param($Sessions, [Parameter(Mandatory = $true)][datetime]$Now, $Settings = (Get-HordeRestoreSettings), [switch]$Shadow, [scriptblock]$Post = $null, $Posted = @{}, $Known = @(), [int]$UncountedDuplicates = 0, [string[]]$DuplicateNames = @())
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
    $finding = Get-HordeRestoreFinding -Sessions $Sessions -Now $Now -Settings $Settings -Known $Known -UncountedDuplicates $UncountedDuplicates -DuplicateNames $DuplicateNames
    $nextKnown = @(@($Known) | Where-Object { $null -ne $_ -and $_.windowEnd -is [datetime] -and ($Now - $_.windowEnd).TotalSeconds -le $Settings.restoreMaxAgeSeconds })
    if ($finding.state -ceq "known") { $nextKnown = @(@($nextKnown | Where-Object { "$($_.restoreId)" -cne $finding.value.anchor.restoreId }) + $finding.value.anchor) }
    foreach ($mail in @(Get-HordeResumePlan -Finding $finding -Now $Now -Settings $Settings)) {
        if ($nextPosted.ContainsKey($mail.messageId)) { continue }
        # A STALL HELD BACK BY A DUPLICATE is journaled once per restore and posts nothing, shadow or not.
        if ($mail.kind -ceq "stall-held") {
            $nextPosted[$mail.messageId] = $Now
            [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "stall" -Id "" -Outcome "held" -Reason ("restore " + $finding.value.restoreId + ": no stall notice while " + $finding.value.uncountedDuplicates + " session(s) named by more than one control file are uncounted - one of them may be the one that moved; it comes once they clear, if still true") -MessageId $mail.messageId))
            continue
        }
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
    return (Send-HordeWakeMail -Mail $Mail -From $script:HordeRestoreSourceFrom -Label "$($Settings.fromLabel)" -TtlSeconds ([int]$Settings.mailTtlSeconds) -Messenger $Messenger -HordeHome $HordeHome)
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
    # A LISTING THAT IS NOT WHOLE ONLY BECAUSE OF NAMED DUPLICATES COUNTS AS WHOLE HERE (T-0116). One
    # session with two running copies made one agent's listing not whole, and another agent's listing is
    # never whole on a machine with no control folder of its own, so no listing was whole and the source was blind
    # for the whole fleet while one duplicate lasted (seen 2026-11-06). core/Identity.ps1 keeps complete
    # as it was, for every other reader, and says in wholeButDuplicates which agents are short only by
    # duplicates. A duplicate is in no record, so none is chosen; the answer carries duplicates, each
    # { sessionId; agents; sources }, for the caller to journal by name and to count against the share
    # (Get-HordeRestoreFinding, -UncountedDuplicates). Any other fault in the listing still leaves it out.
    # BOTH SOURCES ARE PARAMETERS, so a test hands in its own and never reads this machine.
    param($Identity = $null, $Registry = $null)
    try {
        if ($null -eq $Identity) { $Identity = Get-HordeIdentity }
        if ($null -eq $Registry) { $Registry = Read-HordeRegistry -Root (Get-HordeWezfleetRoot) }
    } catch { return (New-HordeUnknown -Reason "the sessions could not be read" -ErrorRecord $_) }
    $whole = @{}
    $leftOut = New-Object System.Collections.ArrayList
    $dupOnly = $null
    if ($null -ne $Identity.PSObject.Properties["wholeButDuplicates"]) { $dupOnly = $Identity.wholeButDuplicates }
    foreach ($agent in @($Identity.complete.Keys)) {
        $listed = $Identity.complete[$agent]
        if ("$($listed.state)" -ceq "known") { $whole["$agent"] = $true }
        elseif ($dupOnly -is [System.Collections.IDictionary] -and $dupOnly.Contains("$agent") -and $dupOnly["$agent"] -eq $true) { $whole["$agent"] = $true }
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
    # The duplicates that cost a counted agent a session. One only in a left-out agent is already out.
    $dupes = New-Object System.Collections.ArrayList
    if ($null -ne $Identity.PSObject.Properties["duplicates"]) {
        foreach ($d in @($Identity.duplicates)) {
            if ($null -eq $d) { continue }
            # A DUPLICATE WHOSE FILES ARE ALL PROVEN STALE IS NOT RUNNING (T-0116, core/Identity.ps1 allStale):
            # a ghost, like every dead session, is no session seen alive, so it is not in the denominator
            # either. That cannot make a false restore: the share is taken among running sessions with an
            # earlier life, and a session that is not running was never among them. A tie where any file is
            # verified or cannot be checked is not stale and is still counted.
            if ($null -ne $d.PSObject.Properties["allStale"] -and $d.allStale -eq $true) { continue }
            $agents = @()
            if ($null -ne $d.PSObject.Properties["agents"]) { $agents = @($d.agents) }
            $counted = ($agents.Count -eq 0)
            foreach ($a in $agents) { if ($whole.ContainsKey("$a")) { $counted = $true } }
            if ($counted) { [void]$dupes.Add([pscustomobject]@{ sessionId = "$($d.sessionId)"; agents = $agents; sources = @($d.sources) }) }
        }
    }
    $answer = New-HordeKnown -Value $out.ToArray() -ObservedAt ([datetime]::UtcNow)
    Add-Member -InputObject $answer -MemberType NoteProperty -Name "leftOut" -Value $leftOut.ToArray()
    Add-Member -InputObject $answer -MemberType NoteProperty -Name "duplicates" -Value $dupes.ToArray()
    return $answer
}

# ---- the file: <home>\wake\restore.json, or restore-shadow.json for a shadow run ----
# Kept apart from everything above, which reads and writes none. Only the command's loop calls these.

function Save-HordeRestoreState {
    # The restore state file, replaced whole: the ids of the mails already posted and the restores already found,
    # so a source that is restarted neither posts a resume mail a second time nor gives a restore it
    # had already named a new id. -Shadow names the shadow run's own file (core/WakeFiles.ps1,
    # Get-HordeWakeStateFile): a mail a shadow run only would have posted is never marked posted where
    # a live run reads.
    # -Name is the file's stem, restore unless a caller keeps a second state (core/WakeRun.ps1 does, for
    # what the source only would have posted during a live run).
    param($Posted = @{}, $Known = @(), [switch]$Shadow, [string]$Name = "restore", [string]$Mode = "", [string]$HordeHome = (Get-HordeHome))
    $ids = @()
    if ($null -ne $Posted) { $ids = @($Posted.Keys | Sort-Object | ForEach-Object { [ordered]@{ id = "$_"; at = $(if ($Posted[$_] -is [datetime]) { ConvertTo-HordeWakeTimeText $Posted[$_] } else { "" }) } }) }
    $restores = @(@($Known) | Where-Object { $null -ne $_ } | ForEach-Object {
            $row = [ordered]@{ restoreId = "$($_.restoreId)"; windowStart = (ConvertTo-HordeWakeTimeText $_.windowStart); windowEnd = (ConvertTo-HordeWakeTimeText $_.windowEnd); members = @() }
            $held = $_.PSObject.Properties["members"]
            if ($null -ne $held -and $held.Value -is [System.Collections.IDictionary]) { $row["members"] = @($held.Value.Keys | Sort-Object | ForEach-Object { [ordered]@{ id = "$_"; startedAt = (ConvertTo-HordeWakeTimeText $held.Value[$_]) } }) }
            $row
        })
    $doc = [ordered]@{ schemaVersion = 1; posted = $ids; restores = $restores }
    Write-HordeWakeFile -Path (Get-HordeWakeStateFile -Name $Name -Shadow:$Shadow -Mode $Mode -HordeHome $HordeHome) -Text (ConvertTo-Json -InputObject $doc -Depth 5 -Compress)
}

function Read-HordeRestoreState {
    # What Save-HordeRestoreState wrote: known { posted; known }, absent when there is none, or unknown when it
    # cannot be read - the caller then starts from nothing posted and says so.
    param([switch]$Shadow, [string]$Name = "restore", [string]$Mode = "", [string]$HordeHome = (Get-HordeHome))
    $path = Get-HordeWakeStateFile -Name $Name -Shadow:$Shadow -Mode $Mode -HordeHome $HordeHome
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
                # A restore saved before members were recorded has none: it then matches no later finding
                # (Test-HordeRestoreSame), which costs at most one resume line posted a second time.
                $starts = New-Object System.Collections.Hashtable ([System.StringComparer]::OrdinalIgnoreCase)
                if ($null -ne $row.PSObject.Properties["members"]) {
                    foreach ($m in @($row.members)) {
                        if ($null -eq $m) { continue }
                        $at = ConvertFrom-HordeWakeTimeText $m.startedAt
                        if ($null -eq $at -or "$($m.id)" -eq "") { return (New-HordeUnknown -Reason "the saved restore state holds a member with no id or no start") }
                        $starts["$($m.id)"] = $at
                    }
                }
                [void]$restores.Add([pscustomobject]@{ restoreId = "$($row.restoreId)"; windowStart = $from; windowEnd = $until; members = $starts })
            }
        } catch { return (New-HordeUnknown -Reason "the saved restore state holds a restore that is not one" -ErrorRecord $_) }
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ posted = $posted; known = $restores.ToArray() }))
}
