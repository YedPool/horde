# core/WakeTell - the watcher's way of telling the warchief what it cannot mend itself.
#
# WHY. The watcher rings doorbells and writes a journal. Four things it meets need somebody who can look,
# and until now the journal was the only place they were said - "telling the warchief" was a comment in
# core/Wake.ps1 and no code (review of PR #211):
#   gave-up             a session nudged as often as the cap allows for one mail, which it never took
#   fleet-read-failing  a reading of the fleet that has failed so many times in a row that it is permanent
#   bad-mail            a session whose mailbox holds records nobody can read, seen on two passes running
#   nudge-killed        a nudge the waker had to stop part-way, which may have left text in a session's box
#   fleet-silent        every nudge answered woken for five minutes and no session took any mail: a
#                       fleet that cannot answer (core/Wake.ps1, Update-HordeWakeSilence)
#   resume-untaken      a resume mail or stall notice the restore source posted that its session did not take in time (T-0391 slice 9)
#   duplicate-copies    a session with unread mail that has more than one running copy, so it cannot be nudged (T-0116)
#   silent-probes-ended the last stretched probe of a silent fleet went unanswered too: from there it is
#                       asked only every six hours, and somebody should look (Update-HordeWakeSilence)
#
# A SENDER, NOT PART OF THE WATCHER'S RULES, exactly as the restore source is (core/RestoreSource.ps1):
# the rules decide and journal; this posts mail, and only mail. The tick hands it the conditions.
#
# ONE MAIL A CONDITION, NEVER A STREAM. Each condition has an instance - which session, which mail,
# since when - and the mail's id is made from it (core/TextUuid.ps1), so the same condition met on a
# thousand passes is one message, and a post of it is idempotent. AND AT MOST maxTellsPerHour OF THEM:
# a fleet in trouble raises many conditions at once, and a warchief buried in automated mail reads none
# of it. What is over the limit is journaled as suppressed, once, and is not sent later: it is in the
# journal, and the mails that were sent say to look there.
#
# EVERY TEXT BEGINS "AUTOMATED, from the wake watcher:", so no session takes a machine's line for a
# person's instruction. The mail wears the label WW, reserved so no session can (core/ReservedLabels.ps1).
#
# IN SHADOW it journals would-tell and posts nothing.
# LIVE POSTING IS OFF, AND TURNS ON WITH THE RESTORE SOURCE'S, AT ONE SWITCH. The only messenger that
# reaches a real session types its own wake line on every post (messengers/wezfleet/Messenger.ps1, WOKEN,
# OR ONLY QUEUED), so a live tell would type into the warchief outside nudge.guarded and outside the
# watcher's rate limit - the very typing the watcher exists to do carefully. Both senders therefore run
# shadow in every mode until a post that does not knock exists; the one place that decides it is
# $script:HordeWakeSendersPost in core/WakeRun.ps1. The poster below is built and tested now, through the
# in-process messenger, so that day is a switch and not a design.
#
# PURE WHERE IT DECIDES: Invoke-HordeWakeTellPass reads no clock and no file. The file of what was told
# is at the bottom, apart.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). It runs under -Version Latest.

. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "TextUuid.ps1")
. (Join-Path $PSScriptRoot "ReadShared.ps1")
. (Join-Path $PSScriptRoot "WakeFiles.ps1")
. (Join-Path $PSScriptRoot "WakeMail.ps1")

# WHO A TELL IS FROM: this module, by a name of its own in place of a session id.
$script:HordeWakeTellFrom = "horde-wake-watcher"
# ITS AWAITING LIST (T-0391 slice 9): a tell the messenger accepted is POSTED, NOT TOLD, until the warchief's own session took it
# (wake\tells-taken.json, core/WakeMail.ps1). Until then its state is "awaiting".
$script:HordeWakeTellTakenKind = New-HordeWakeMailKind -Stem "tells" -Label "wake tells" -Notice "wake tell" -From "the wake watcher"
$script:HordeWakeTellKinds = @("gave-up", "fleet-read-failing", "bad-mail", "nudge-killed", "fleet-silent", "silent-probes-ended", "duplicate-copies", "resume-untaken")

function Get-HordeWakeTellSettings {
    # The tell sender's settings, with -Overrides laid over the defaults. A name that is not a setting
    # is refused: a mistyped one would otherwise silently leave the default.
    param([hashtable]$Overrides = @{})
    $s = [ordered]@{
        # At most this many tells in any hour (the header, ONE MAIL A CONDITION).
        maxTellsPerHour = 6
        # The same for the resume-untaken tells, counted apart (the pass, below): a restore of a whole fleet can leave dozens untaken.
        maxUntakenTellsPerHour = 30
        # A post that could not say is tried again after this long.
        retrySeconds = 300
        # What was told is forgotten after this long: a week. A condition that is still there then is
        # news again.
        keepSeconds = 604800
        # The hub label a tell wears as its sender, RESERVED so no session may be given it.
        fromLabel = "WW"
        mailTtlSeconds = 86400
        prefix = "AUTOMATED, from the wake watcher: "
    }
    foreach ($k in @($Overrides.Keys)) {
        if (-not $s.Contains("$k")) { throw ("'" + $k + "' is not a tell setting") }
        $s["$k"] = $Overrides[$k]
    }
    return [pscustomobject]$s
}

function New-HordeWakeTellCondition {
    # One thing the warchief must hear: { kind; subject; instance; text }. subject is the session it is
    # about, or "" for the fleet; instance is what makes this occurrence itself and not another (the
    # mail's time, when the failing began); text is the sentence, without the prefix.
    param([Parameter(Mandatory = $true)][string]$Kind, [string]$Subject = "", [Parameter(Mandatory = $true)][string]$Instance, [Parameter(Mandatory = $true)][string]$Text)
    if ($script:HordeWakeTellKinds -cnotcontains $Kind) { throw ("'" + $Kind + "' is not a condition the warchief is told of") }
    return [pscustomobject]@{ kind = $Kind; subject = $Subject; instance = $Instance; text = $Text }
}

function Get-HordeWakeTellMessageId {
    # The id of the mail for one condition, made from what the condition is: its kind, whom it is about
    # and its instance. The same condition is the same message, on every pass and after a restart.
    param([Parameter(Mandatory = $true)]$Condition)
    return (ConvertTo-HordeTextUuid -Text ("horde-wake-tell`n" + $Condition.kind + "`n" + ("$($Condition.subject)").ToLowerInvariant() + "`n" + $Condition.instance))
}

function Get-HordeWakeTellClass {
    # Which of the two budgets a told mark counts against: fleet or session. A mark saved before the
    # classes existed says neither, and is a session's.
    param($Mark)
    if ($null -eq $Mark) { return "session" }
    $p = $Mark.PSObject.Properties["class"]
    if ($null -ne $p -and "$($p.Value)" -ceq "fleet") { return "fleet" }
    if ($null -ne $p -and "$($p.Value)" -ceq "untaken") { return "untaken" }
    return "session"
}

function Invoke-HordeWakeTellPass {
    # ONE PASS of the tell sender: for each condition not yet handled, tell the warchief - or journal that
    # it would, or that it was suppressed. Returns { entries; told }. It reads no clock and no file.
    #   -Conditions  what the tick collected this pass (New-HordeWakeTellCondition)
    #   -Warchief    the session id to tell, or "" when the fleet has no one warchief
    #   -Shadow      JOURNAL would-tell, AND POST NOTHING
    #   -Post        param($Mail) -> a tristate answer, known when the mail was taken; $Mail is
    #                { kind; to; messageId; body }. Never called in shadow.
    #   -Told        messageId -> { at; state }, from the last pass: state told, would-tell, suppressed,
    #                unposted (nobody to tell, or nothing to post through) or failed (to be tried again)
    # THE ENTRIES: tell (outcome posted, unknown or unposted), would-tell, tell-suppressed.
    param($Conditions, [string]$Warchief = "", [Parameter(Mandatory = $true)][datetime]$Now, $Settings = (Get-HordeWakeTellSettings), [switch]$Shadow, [scriptblock]$Post = $null, $Told = @{})
    $entries = New-Object System.Collections.ArrayList
    $next = @{}
    if ($null -ne $Told) {
        foreach ($k in @($Told.Keys)) {
            $was = $Told[$k]
            if ($null -ne $was -and $was.at -is [datetime] -and ($Now - $was.at).TotalSeconds -le $Settings.keepSeconds) { $next["$k"] = $was }
        }
    }
    # A NOTICE ABOUT THE WHOLE FLEET IS NEVER CROWDED OUT BY NOTICES ABOUT SESSIONS. With six sessions or
    # more given up on, their six tells used up the hour, and the ONE tell that explained them all -
    # the fleet is silent, the fleet cannot be read - was the one suppressed (safety review of PR
    # 220). So the two are counted apart: a fleet's notice (no session is its subject) is sent first
    # and counts only against other fleet notices; a session's counts only against other sessions'.
    # Each class has maxTellsPerHour, and there are three kinds of fleet notice, each once per instance.
    $ordered = @(@($Conditions | Where-Object { $null -ne $_ -and "$($_.subject)" -ceq "" }) + @($Conditions | Where-Object { $null -ne $_ -and "$($_.subject)" -cne "" }))
    foreach ($c in $ordered) {
        if ($null -eq $c) { continue }
        $id = Get-HordeWakeTellMessageId -Condition $c
        $class = "session"
        if ("$($c.subject)" -ceq "") { $class = "fleet" }
        # A TELL ABOUT AN UNTAKEN RESUME MAIL HAS A BUDGET OF ITS OWN (T-0391 slice 9, round 3): a restore that leaves seven sessions untaken
        # would otherwise spend the six session tells of the hour, suppress the seventh for keepSeconds, and starve the gave-up, bad-mail and
        # duplicate-copies tells. One tell a mail id stays (the engine's design); only the cap is apart.
        $cap = [int]$Settings.maxTellsPerHour
        if ($c.kind -ceq "resume-untaken") { $class = "untaken"; $cap = [int]$Settings.maxUntakenTellsPerHour }
        if ($next.ContainsKey($id)) {
            # HANDLED ALREADY, unless it is a post that could not say and its retry is due.
            if ($next[$id].state -cne "failed" -or ($Now - $next[$id].at).TotalSeconds -lt $Settings.retrySeconds) { continue }
        }
        $body = "$($Settings.prefix)" + $c.text
        $sentLately = @($next.Values | Where-Object { ($_.state -ceq "told" -or $_.state -ceq "awaiting" -or $_.state -ceq "would-tell") -and ($Now - $_.at).TotalSeconds -lt 3600 -and "$(Get-HordeWakeTellClass $_)" -ceq $class }).Count
        if ($sentLately -ge $cap) {
            $next[$id] = [pscustomobject]@{ at = $Now; state = "suppressed"; class = $class }
            [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "tell-suppressed" -Id $c.subject -Outcome "suppressed" -Reason ($c.kind + ": over " + $cap + " tells in an hour, so this one is only here: " + $c.text) -MessageId $id))
            continue
        }
        # SHADOW: the tell is journaled once and marked, and nothing is handed to the poster.
        if ($Shadow) { $next[$id] = [pscustomobject]@{ at = $Now; state = "would-tell"; class = $class }; [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "would-tell" -Id $c.subject -Outcome "would-tell" -Reason ($c.kind + ": " + $c.text) -MessageId $id)); continue }
        if ($Warchief -ceq "") { $next[$id] = [pscustomobject]@{ at = $Now; state = "unposted"; class = $class }; [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "tell" -Id $c.subject -Outcome "unposted" -Reason ($c.kind + ": no one session is the warchief, so nobody can be told: " + $c.text) -MessageId $id)); continue }
        if ($null -eq $Post) { $next[$id] = [pscustomobject]@{ at = $Now; state = "unposted"; class = $class }; [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "tell" -Id $c.subject -Outcome "unposted" -Reason ($c.kind + ": the pass was given nothing to post through: " + $c.text) -MessageId $id)); continue }
        $took = $null
        try { $took = & $Post ([pscustomobject]@{ kind = $c.kind; to = $Warchief; messageId = $id; body = $body }) } catch { $took = New-HordeUnknown -Reason "the post failed" -ErrorRecord $_ }
        # THE LIST'S OWN ALARM (an oldest mark evicted unwatched because the list is full) is journaled, not dropped (core/WakeMail.ps1).
        foreach ($ln in @(Get-HordeWakeMailLines $took)) { [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "mail-taken" -Id "tells" -Outcome "evicted" -Reason "$ln" -MessageId $id)) }
        if ((Test-HordeAnswer $took) -and $took.state -ceq "known") {
            $next[$id] = [pscustomobject]@{ at = $Now; state = "told"; class = $class }
            [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "tell" -Id $c.subject -Outcome "posted" -Reason ($c.kind + ": " + $c.text) -MessageId $id))
        } elseif (Test-HordeWakeMailAlready $took) {
            # The messenger already held a copy and woke nobody: handled, never posted again, NOT told.
            $next[$id] = [pscustomobject]@{ at = $Now; state = "undelivered"; class = $class }
            [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "tell" -Id $c.subject -Outcome "already-posted" -Reason ($c.kind + ": the messenger already held a copy of it from an earlier post; the warchief is not counted as told: " + $c.text) -MessageId $id))
        } elseif (Test-HordeWakeMailAwaiting $took) {
            # POSTED, NOT TOLD: the warchief's session has not taken it. The state is "awaiting" (handled, never posted again, and it counts
            # against the hour's budget as a tell sent); the tick makes it "told" on the session's TAKEN (core/WakeRun.ps1).
            $next[$id] = [pscustomobject]@{ at = $Now; state = "awaiting"; class = $class }
            [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "tell" -Id $c.subject -Outcome "awaiting" -Reason ($c.kind + $(if ($took.awaiting.alreadyHeld) { ": the messenger said it was already posted earlier (" } else { ": the messenger accepted it (" }) + $took.awaiting.stage + "); the warchief is not counted as told until its session's own TAKEN: " + $c.text) -MessageId $id))
        } else {
            $why = "the post answered with something that is not an answer"
            if (Test-HordeAnswer $took) { $why = "$($took.reason)" }
            $next[$id] = [pscustomobject]@{ at = $Now; state = "failed"; class = $class }
            [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "tell" -Id $c.subject -Outcome "unknown" -Reason ($c.kind + ": " + $why) -MessageId $id))
        }
    }
    return [pscustomobject]@{ entries = $entries.ToArray(); told = $next }
}

function Send-HordeWakeTell {
    # Post one tell ({ to; messageId; body }, as Invoke-HordeWakeTellPass's -Post is handed) through the
    # messenger port (core/WakeMail.ps1), as this sender. A tristate answer.
    # T-0391 slice 9: the answer is NEVER known. A post the messenger accepted is unknown with .awaiting (Test-HordeWakeMailAwaiting): it
    # is marked on the awaiting list first and the warchief is told only on its session's own TAKEN.
    param([Parameter(Mandatory = $true)]$Mail, $Settings = (Get-HordeWakeTellSettings), $Messenger = $null, [string]$HordeHome = (Get-HordeHome), [datetime]$Now = [datetime]::UtcNow)
    return (Send-HordeWakeMail -Mail $Mail -From $script:HordeWakeTellFrom -Label "$($Settings.fromLabel)" -Kind $script:HordeWakeTellTakenKind -TtlSeconds ([int]$Settings.mailTtlSeconds) -Messenger $Messenger -HordeHome $HordeHome -Now $Now)
}

# ---- the file: <home>\wake\tells-<mode>.json ----
# Kept apart from everything above, which reads and writes none. Only the tick calls these.

function Save-HordeWakeTellState {
    # What was told, replaced whole, so a watcher that is restarted does not tell the warchief again.
    # -Mode names the run's own file (core/WakeFiles.ps1): what a shadow run only would have told is
    # never read by a live one as told.
    param($Told = @{}, [string]$Name = "tells", [string]$Mode = "", [switch]$Shadow, [string]$HordeHome = (Get-HordeHome))
    $rows = @()
    if ($null -ne $Told) { $rows = @($Told.Keys | Sort-Object | ForEach-Object { [ordered]@{ id = "$_"; at = (ConvertTo-HordeWakeTimeText $Told[$_].at); state = "$($Told[$_].state)"; class = (Get-HordeWakeTellClass $Told[$_]) } }) }
    $doc = [ordered]@{ schemaVersion = 1; told = $rows }
    Write-HordeWakeFile -Path (Get-HordeWakeStateFile -Name $Name -Mode $Mode -Shadow:$Shadow -HordeHome $HordeHome) -Text (ConvertTo-Json -InputObject $doc -Depth 5 -Compress)
}

function Read-HordeWakeTellState {
    # What Save-HordeWakeTellState wrote: known { told }, absent when there is none, or unknown when it
    # cannot be read - the caller then starts from nothing told and says so.
    param([string]$Name = "tells", [string]$Mode = "", [switch]$Shadow, [string]$HordeHome = (Get-HordeHome))
    $path = Get-HordeWakeStateFile -Name $Name -Mode $Mode -Shadow:$Shadow -HordeHome $HordeHome
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return (New-HordeAbsent -Note "nothing told was saved in this home") }
    try { $j = (Read-HordeSharedText -Path $path) | ConvertFrom-Json }
    catch { return (New-HordeUnknown -Reason "the saved tells could not be read" -ErrorRecord $_) }
    if ($null -eq $j -or $null -eq $j.PSObject.Properties["told"]) { return (New-HordeUnknown -Reason "the saved tells are not ones") }
    $told = @{}
    try {
        foreach ($row in @($j.told)) {
            if ($null -eq $row) { continue }
            $at = ConvertFrom-HordeWakeTimeText $row.at
            if ($null -eq $at -or "$($row.id)" -eq "") { return (New-HordeUnknown -Reason "the saved tells hold one with no id or no time") }
            $told["$($row.id)"] = [pscustomobject]@{ at = $at; state = "$($row.state)"; class = (Get-HordeWakeTellClass $row) }
        }
    } catch { return (New-HordeUnknown -Reason "the saved tells hold one that is not one" -ErrorRecord $_) }
    return (New-HordeKnown -Value ([pscustomobject]@{ told = $told }))
}
