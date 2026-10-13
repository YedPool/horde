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
# EVERY TIME IS UTC.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). It runs under -Version Latest.

. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "TextUuid.ps1")
. (Join-Path $PSScriptRoot "ReadShared.ps1")
. (Join-Path $PSScriptRoot "Identity.ps1")
. (Join-Path $PSScriptRoot "WezfleetState.ps1")
. (Join-Path $PSScriptRoot "WakeFiles.ps1")

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
        # A restored session that is idle has "moved" once its status changed this long after it started.
        movedSeconds = 60
        # With no session moved this long after the last one started, the warchief is told.
        stallSeconds = 300
        # A restore older than this is history: nothing is planned for it any more.
        restoreMaxAgeSeconds = 86400
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
    # startedAt; lastChangeAt }. known { restoreId; windowStart; windowEnd; members; notMoved } when at
    # least restoreMinSessions of them, and at least restoreShare of all of them, started inside one
    # window of restoreWindowSeconds; absent, saying why, when not. Sessions do not start together by
    # chance: a quiet fleet's start times are hours apart, and one restarted session is one session.
    #
    # THE WINDOW is the one holding the most sessions, the earliest on a tie. windowStart is its first
    # start and windowEnd its last. restoreId is made from windowStart cut to the minute (core/TextUuid.ps1), so every pass
    # over the same restore - and a watcher restarted in the middle of it - names it the same way.
    # KNOWN LIMIT: a session that starts later, inside the window's length, joins the same restore; two
    # or more that start after it can make a later window the fullest and so give the restore a new id.
    # The resume mail is then posted once more to a session that still has not moved.
    #
    # A MEMBER HAS NOT MOVED ONLY WHEN IT IS IDLE NOW AND ITS LAST STATUS CHANGE IS LESS THAN movedSeconds
    # AFTER ITS START. The first version read the time alone, and the review of PR #207 found the hole:
    # a session in a long FIRST turn changed its status seconds after it started and has not changed it
    # since, so it read as not moved and would have been mailed RESUME in the middle of its work. A
    # session that is busy or waiting now is in a turn, and that is moving. A status that is not known is
    # never "not moved" either: unknown means no mail. The time rule that remains, for an idle session: the
    # first status a restored session writes is its start, and one that never took a turn never
    # writes another.
    param($Sessions, [Parameter(Mandatory = $true)][datetime]$Now, $Settings = (Get-HordeRestoreSettings))
    $all = @(@($Sessions) | Where-Object { $null -ne $_ -and $_.startedAt -is [datetime] -and $_.startedAt -le $Now } | Sort-Object -Property startedAt, id)
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
            $resting = ("$($_.status)" -ceq "idle" -and $_.lastChangeAt -is [datetime])
            $moved = (-not $resting -or ($_.lastChangeAt - $_.startedAt).TotalSeconds -ge $Settings.movedSeconds)
            [pscustomobject]@{ id = "$($_.id)"; role = "$($_.role)"; parent = "$($_.parent)"; startedAt = $_.startedAt; lastChangeAt = $_.lastChangeAt; status = "$($_.status)"; moved = $moved }
        })
    $minute = New-Object System.DateTime($windowStart.Year, $windowStart.Month, $windowStart.Day, $windowStart.Hour, $windowStart.Minute, 0, [System.DateTimeKind]::Utc)
    $restoreId = ConvertTo-HordeTextUuid -Text ("horde-wake-restore`n" + $minute.ToString("yyyy-MM-ddTHH:mm", [System.Globalization.CultureInfo]::InvariantCulture))
    $notMoved = @($members | Where-Object { -not $_.moved } | ForEach-Object { $_.id })
    return (New-HordeKnown -Value ([pscustomobject]@{ restoreId = $restoreId; windowStart = $windowStart; windowEnd = $windowEnd; members = $members; notMoved = $notMoved }) -ObservedAt $Now)
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
    # not posted yet. Returns { entries; posted }. It reads no clock and no file.
    #   -Sessions  the running sessions (Get-HordeRestoreSessions' value)
    #   -Shadow    JOURNAL WHAT IT WOULD POST, AND POST NONE OF IT. A would-post is marked so the journal
    #              says it once, not every pass.
    #   -Post      param($Mail) -> a tristate answer, known when the mail was taken; $Mail is
    #              { kind; to; messageId; body }. Never called in shadow.
    #   -Posted    messageId -> $true for the mails already posted, from the last pass
    # THE ENTRIES are journal lines of kind post or stall, or would-post and would-stall in shadow.
    param($Sessions, [Parameter(Mandatory = $true)][datetime]$Now, $Settings = (Get-HordeRestoreSettings), [switch]$Shadow, [scriptblock]$Post = $null, $Posted = @{})
    $entries = New-Object System.Collections.ArrayList
    $nextPosted = @{}
    if ($null -ne $Posted) { foreach ($k in @($Posted.Keys)) { $nextPosted["$k"] = $true } }
    $finding = Get-HordeRestoreFinding -Sessions $Sessions -Now $Now -Settings $Settings
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
    return [pscustomobject]@{ entries = $entries.ToArray(); posted = $nextPosted }
}

function Get-HordeRestoreSessions {
    # The running sessions, for Get-HordeRestoreFinding: known, a list of { id; role; parent; startedAt;
    # lastChangeAt; status } (and leftOut, below), or unknown with the reason. status is the session's
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
        if ($Registry.records.ContainsKey($id)) {
            $record = $Registry.records[$id].record
            $read = Read-HordeRecordRole -Record $record
            if ("$($read.role.state)" -ceq "known") { $role = "$($read.role.value)" }
            $held = Get-HordeStoredField -Record $record -Name "parent"
            if ("$($held.state)" -ceq "known") { $parent = "$($held.value)" }
        }
        [void]$out.Add([pscustomobject]@{ id = "$id"; role = $role; parent = $parent; startedAt = $started.value; lastChangeAt = $status.observedAt; status = "$($status.value)" })
    }
    $answer = New-HordeKnown -Value $out.ToArray() -ObservedAt ([datetime]::UtcNow)
    Add-Member -InputObject $answer -MemberType NoteProperty -Name "leftOut" -Value $leftOut.ToArray()
    return $answer
}

# ---- the file: <home>\wake\restore.json ----
# Kept apart from everything above, which reads and writes none. Only the command's loop calls these.

function Save-HordeRestoreState {
    # restore.json, replaced whole: the ids of the mails already posted, so a source that is restarted
    # does not post a resume mail a second time.
    param($Posted = @{}, [string]$HordeHome = (Get-HordeHome))
    $ids = @()
    if ($null -ne $Posted) { $ids = @($Posted.Keys | Sort-Object | ForEach-Object { "$_" }) }
    $doc = [ordered]@{ schemaVersion = 1; posted = $ids }
    Write-HordeWakeFile -Path (Join-Path (Get-HordeWakeFolder -HordeHome $HordeHome) "restore.json") -Text (ConvertTo-Json -InputObject $doc -Depth 5 -Compress)
}

function Read-HordeRestoreState {
    # What Save-HordeRestoreState wrote: known { posted }, absent when there is none, or unknown when it
    # cannot be read - the caller then starts from nothing posted and says so.
    param([string]$HordeHome = (Get-HordeHome))
    $path = Join-Path (Get-HordeWakeFolder -HordeHome $HordeHome) "restore.json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return (New-HordeAbsent -Note "no restore state was saved in this home") }
    try { $j = (Read-HordeSharedText -Path $path) | ConvertFrom-Json }
    catch { return (New-HordeUnknown -Reason "the saved restore state could not be read" -ErrorRecord $_) }
    if ($null -eq $j -or $null -eq $j.PSObject.Properties["posted"]) { return (New-HordeUnknown -Reason "the saved restore state is not one") }
    $posted = @{}
    foreach ($id in @($j.posted)) { if ($null -ne $id -and "$id" -ne "") { $posted["$id"] = $true } }
    return (New-HordeKnown -Value ([pscustomobject]@{ posted = $posted }))
}
