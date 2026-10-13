# core/Wake - the wake watcher's rules: who is nudged, when and in what order.
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
# IT ONLY WAKES. It posts no mail and knows nothing of restores: the mail a restore needs is posted by
# a sender of its own (core/RestoreSource.ps1), and is unread mail like any other to these rules.
#
# PURE WHERE IT DECIDES. Get-HordeWakeDecisions and Update-HordeWakeLedger read no clock, no file and no
# port: everything is a parameter and the time is always -Now, so a test replays a real timeline second
# by second. Invoke-HordeWakePass is one pass over a waker and does no file I/O either. The ledger's
# file helpers are at the bottom, apart, and only the command's loop calls them.
#
# THE FIRST CORE FILE TO LOAD A PORT THAT LIVES BESIDE ITS ADAPTERS (wakers/Port.ps1). The other ports
# core calls are core files themselves (core/HostPort.ps1, core/FirewallPort.ps1); the families that came
# later keep theirs beside their adapters, and until now only modules outside core loaded those. The pass
# below calls the port's three reads, and a core file loads what it calls (tools/CoreLoad.ps1), so it is
# loaded here. It names no waker: which one is passed in, and the caller loads the adapters.
#
# EVERY TIME IS UTC. The port converts what an adapter gives it; a caller passes -Now as UTC.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). It runs under -Version Latest.


. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "ReadShared.ps1")
. (Join-Path $PSScriptRoot "WakeFiles.ps1")
# The port the pass reads and rings through (the header says why it is loaded from here).
. (Join-Path (Split-Path -Parent $PSScriptRoot) "wakers\Port.ps1")

# How long a ledger entry is kept for a session nothing has said anything about: a day. A session that
# is gone leaves the targets, so nothing would ever report its mail taken and drop its entry.
$script:HordeWakeLedgerKeepSeconds = 86400

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
        # At most this many nudges for ONE unread mail of one session (Update-HordeWakeGaveUp).
        maxNudgesPerMail = 6
        # At most this many full readings of a session - a look at its box and its turn - in one pass
        # (Invoke-HordeWakePass, THE LOOK COMES LAST). Each can take a pane's whole time-out.
        maxConfirmsPerPass = 3
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
    # One session's ledger entry, or $null when it has none. With -State (the session's state value now)
    # it is the entry FOR THE MAIL THAT IS NOW ITS OLDEST UNREAD, or $null: an entry counts the nudges
    # for one mail (its mailAt), and when another mail has become the oldest - the session took the one
    # it was being asked about - nothing is held against the new one. An entry that records no mail
    # (one written before entries did) is for whatever mail there is.
    param($Ledger, [string]$Id, $State = $null)
    if ($null -eq $Ledger -or -not $Ledger.ContainsKey($Id)) { return $null }
    $entry = $Ledger[$Id]
    $mailAt = Get-HordeWakeEntryValue $entry "mailAt"
    if ($null -ne $State -and $mailAt -is [datetime] -and $State.oldestUnreadAt -is [datetime] -and $State.oldestUnreadAt -ne $mailAt) { return $null }
    return $entry
}

function Get-HordeWakeEntryValue {
    # A member of a ledger entry, or $null when it has none. Looked up, never dereferenced: entries
    # written by earlier builds lack the later members, and under strict mode reading one is an error.
    param($Entry, [string]$Name)
    if ($null -eq $Entry) { return $null }
    $p = $Entry.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function New-HordeWakeLedgerRow {
    # A ledger entry: { attempts; lastAttemptAt; lastOutcome }, and nothingAt, mailAt and gaveUp when
    # there is something to say in them.
    param([int]$Attempts, $LastAttemptAt, [string]$LastOutcome, $NothingAt = $null, $MailAt = $null, [bool]$GaveUp = $false)
    $row = [ordered]@{ attempts = $Attempts; lastAttemptAt = $LastAttemptAt; lastOutcome = $LastOutcome }
    if ($NothingAt -is [datetime]) { $row["nothingAt"] = $NothingAt }
    if ($MailAt -is [datetime]) { $row["mailAt"] = $MailAt }
    if ($GaveUp) { $row["gaveUp"] = $true }
    return [pscustomobject]$row
}

function Get-HordeWakeNothingAt {
    # When a session's waker last answered "nothing" in the run of nothings it is in now, or $null when
    # it is in none. Looked up, never dereferenced: an entry made before the hold existed has no such
    # member, and under strict mode reading one that is not there is an error.
    param($Entry)
    if ($null -eq $Entry) { return $null }
    $p = $Entry.PSObject.Properties["nothingAt"]
    if ($null -eq $p -or $p.Value -isnot [datetime]) { return $null }
    return $p.Value
}

function Get-HordeWakeHold {
    # Why one session is not nudged now, as { action; reason }: skip (nothing to wake it for), wait
    # (something to wake it for, and a condition that does not hold), or ready (every condition holds;
    # only the fleet's rate limit can still hold it back). EACH CONDITION IS ITS OWN LINE, and each
    # unknown is wait: the file header says why.
    # THE BOX AND THE TURN ARE ASKED LAST, after everything that costs nothing to know, and with -CanLook
    # an unknown there is answered look - "everything else holds; go and read the session" - instead of
    # wait. A session that is backing off, held, out of reach or not idle is never looked at: its box
    # decides nothing (review of PR #211: every idle session with unread mail had its pane read on every
    # pass, even inside a 300 s back-off). A box that is known not empty, or a turn known under way, is
    # wait at once, with no look.
    param($Target, $StateAnswer, $Entry, [datetime]$Now, $Settings, [switch]$CanLook)
    if ($null -eq $StateAnswer -or "$($StateAnswer.state)" -cne "known") {
        $why = "nothing answered for it"
        if ($null -ne $StateAnswer) { $why = "$($StateAnswer.reason)" }
        return [pscustomobject]@{ action = "wait"; reason = ("its state is unknown: " + $why) }
    }
    $s = $StateAnswer.value
    if ($s.unreadCount -le 0) { return [pscustomobject]@{ action = "skip"; reason = "no unread mail" } }
    if ("$($Target.reachable)" -cne "yes") { return [pscustomobject]@{ action = "wait"; reason = ("reachable is " + $Target.reachable) } }
    if ("$($s.idle)" -cne "yes") { return [pscustomobject]@{ action = "wait"; reason = ("idle is " + $s.idle) } }
    $age = ($Now - $s.oldestUnreadAt).TotalSeconds
    if ($age -lt $Settings.minUnreadSeconds) { return [pscustomobject]@{ action = "wait"; reason = ("its oldest unread mail is younger than " + $Settings.minUnreadSeconds + " s") } }
    # THE HOLD AFTER "nothing" (Update-HordeWakeLedger says why): out of the ready set for the first
    # step of the back-off, and never longer - it does not grow, because nothing failed.
    $nothingAt = Get-HordeWakeNothingAt $Entry
    if ($null -ne $nothingAt) {
        $rest = Get-HordeWakeBackoffSeconds -Attempts 1 -Settings $Settings
        if (($Now - $nothingAt).TotalSeconds -lt $rest) { return [pscustomobject]@{ action = "wait"; reason = ("held " + $rest + " s: its waker found no unread mail to nudge for, while its state still shows some") } }
    }
    # THE CAP (Update-HordeWakeGaveUp says why): after maxNudgesPerMail nudges for this one mail, nothing
    # more is tried for it. A session that takes the mail, or whose oldest unread mail becomes another,
    # starts again from nothing (Get-HordeWakeLedgerEntry).
    if ($null -ne $Entry -and [int]$Entry.attempts -ge [int]$Settings.maxNudgesPerMail) { return [pscustomobject]@{ action = "wait"; reason = ("gave up after " + $Entry.attempts + " nudges for this mail; nothing more is tried until it is taken or another mail becomes the oldest") } }
    if ($null -ne $Entry) {
        $wait = Get-HordeWakeBackoffSeconds -Attempts $Entry.attempts -Settings $Settings
        $since = ($Now - $Entry.lastAttemptAt).TotalSeconds
        if ($since -lt $wait) { return [pscustomobject]@{ action = "wait"; reason = ("back-off: " + [int][System.Math]::Ceiling($wait - $since) + " s left of " + $wait + " after attempt " + $Entry.attempts) } }
    }
    $unseen = ("$($s.midTurn)" -ceq "unknown" -or "$($s.boxEmpty)" -ceq "unknown")
    if ($CanLook -and $unseen -and "$($s.midTurn)" -cne "yes" -and "$($s.boxEmpty)" -cne "no") { return [pscustomobject]@{ action = "look"; reason = "its box and its turn have not been read" } }
    if ("$($s.midTurn)" -cne "no") { return [pscustomobject]@{ action = "wait"; reason = ("midTurn is " + $s.midTurn) } }
    if ("$($s.boxEmpty)" -cne "yes") { return [pscustomobject]@{ action = "wait"; reason = ("boxEmpty is " + $s.boxEmpty) } }
    return [pscustomobject]@{ action = "ready"; reason = "" }
}

function Get-HordeWakeDecisions {
    # One decision per target, in the targets' order: { id; action (nudge, look, wait or skip); reason }.
    #   -Targets    the port's list (Get-HordeWakeTargets' value)
    #   -States     session id -> the port's state ANSWER for it (known or unknown; missing is unknown)
    #   -Confirmed  session id -> the port's FULL state answer, for the sessions already looked at this
    #               pass; it stands in place of the state
    #   -CanLook    the waker has a fuller reading than its state (wakers/Port.ps1, Confirm): then a
    #               session that holds on everything but an unread box or turn is decided look, for the
    #               pass to read it and decide again. Without it such a session waits.
    # A LOOK TAKES A PLACE IN THE QUEUE LIKE A NUDGE: only the sessions that would be nudged this pass
    # are looked at, in the same order, and the rest wait for the rate limit unlooked.
    #   -Ledger   session id -> { attempts; lastAttemptAt; lastOutcome }
    # WHO GOES FIRST when more are ready than one pass may nudge: a session whose waker last answered
    # "nothing" goes behind every other (Update-HordeWakeLedger); then the session asked the fewest times,
    # then by role (warchief, orc, goblin, unknown), then the oldest unread mail. Fewest attempts first
    # is what makes a restore of everything a fair queue: without it the warchief's second knock, due
    # 5 s after its first, would go ahead of nine sessions nobody had knocked on yet. The rest get wait
    # "rate limit" and are ready again next pass.
    param($Targets, $States, $Ledger, [Parameter(Mandatory = $true)][datetime]$Now, $Settings = (Get-HordeWakeSettings), $Confirmed = @{}, [switch]$CanLook)
    $roles = @(Get-HordeWakerRoles)
    $rows = New-Object System.Collections.ArrayList
    foreach ($t in @($Targets)) {
        if ($null -eq $t) { continue }
        $id = "$($t.id)"
        $answer = $null
        if ($null -ne $States -and $States.ContainsKey($id)) { $answer = $States[$id] }
        $looked = ($null -ne $Confirmed -and $Confirmed.ContainsKey($id))
        if ($looked) { $answer = $Confirmed[$id] }
        $stateNow = $null
        if ($null -ne $answer -and "$($answer.state)" -ceq "known") { $stateNow = $answer.value }
        $entry = Get-HordeWakeLedgerEntry -Ledger $Ledger -Id $id -State $stateNow
        $hold = Get-HordeWakeHold -Target $t -StateAnswer $answer -Entry $entry -Now $Now -Settings $Settings -CanLook:($CanLook -and -not $looked)
        $row = [pscustomobject]@{ id = $id; action = $hold.action; reason = $hold.reason; attempts = 0; nothing = 0; rank = $roles.Count; oldest = [datetime]::MaxValue }
        if ($hold.action -ceq "ready" -or $hold.action -ceq "look") {
            if ($null -ne $entry) { $row.attempts = [int]$entry.attempts }
            if ($null -ne (Get-HordeWakeNothingAt $entry)) { $row.nothing = 1 }
            $at = [System.Array]::IndexOf($roles, "$($t.role)")
            if ($at -ge 0) { $row.rank = $at }
            $row.oldest = $answer.value.oldestUnreadAt
        }
        [void]$rows.Add($row)
    }
    $ready = @($rows | Where-Object { $_.action -ceq "ready" -or $_.action -ceq "look" } | Sort-Object -Property nothing, attempts, rank, oldest, id)
    $allowed = [int]$Settings.maxNudgesPerPass
    for ($i = 0; $i -lt $ready.Count; $i++) {
        if ($i -ge $allowed) { $ready[$i].action = "wait"; $ready[$i].reason = "rate limit" }
        elseif ($ready[$i].action -ceq "ready") { $ready[$i].action = "nudge"; $ready[$i].reason = "unread mail, idle, empty box" }
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
    # BUT IT MUST NOT HOLD THE SLOT. The first version left the ledger untouched for it, and the review of
    # PR #207 followed that through: a session whose waker answers nothing while its state still shows
    # unread mail keeps 0 attempts, sorts first, takes the one nudge a pass allows on every pass, starves
    # the fleet and journals every 3 s. So a nothing is recorded as a HOLD, nothingAt, beside the attempts
    # it leaves alone: the session is out of the ready set for the first step of the back-off, and goes
    # behind every other ready session after that. A real attempt, or the mail being taken, ends the hold.
    # "killed" IS THE LONGEST BACK-OFF AT ONCE: the waker stopped its own nudge part-way, and the session's
    # box may hold the unsent line (wakers/Port.ps1). Asking again in 5 s would be typing into that. The
    # attempt is counted as though every step of the back-off had already been used.
    param($Ledger, $Decisions, $Outcomes, $States, [Parameter(Mandatory = $true)][datetime]$Now, $Settings = (Get-HordeWakeSettings))
    $next = @{}
    if ($null -ne $Ledger) { foreach ($k in @($Ledger.Keys)) { $next["$k"] = $Ledger[$k] } }
    foreach ($d in @($Decisions)) {
        if ($null -eq $d -or "$($d.action)" -cne "nudge") { continue }
        $id = "$($d.id)"
        if ($null -eq $Outcomes -or -not $Outcomes.ContainsKey($id)) { continue }
        # THE ENTRY FOR THIS MAIL: the nudges counted are those for the mail that is the oldest unread
        # now. An entry for another mail is not carried over (Get-HordeWakeLedgerEntry).
        $stateNow = $null
        if ($null -ne $States -and $States.ContainsKey($id) -and "$($States[$id].state)" -ceq "known") { $stateNow = $States[$id].value }
        $mailAt = $null
        if ($null -ne $stateNow -and $stateNow.oldestUnreadAt -is [datetime]) { $mailAt = $stateNow.oldestUnreadAt }
        $had = Get-HordeWakeLedgerEntry -Ledger $next -Id $id -State $stateNow
        if ("$($Outcomes[$id])" -ceq "nothing") {
            $kept = New-HordeWakeLedgerRow -Attempts 0 -LastAttemptAt $Now -LastOutcome "nothing" -NothingAt $Now -MailAt $mailAt
            if ($null -ne $had) { $kept = New-HordeWakeLedgerRow -Attempts ([int]$had.attempts) -LastAttemptAt $had.lastAttemptAt -LastOutcome "$($had.lastOutcome)" -NothingAt $Now -MailAt $mailAt -GaveUp ((Get-HordeWakeEntryValue $had "gaveUp") -eq $true) }
            $next[$id] = $kept
            continue
        }
        $before = 0
        if ($null -ne $had) { $before = [int]$had.attempts }
        $count = $before + 1
        if ("$($Outcomes[$id])" -ceq "killed") { $count = [System.Math]::Max($count, @($Settings.backoffSeconds).Count) }
        $next[$id] = New-HordeWakeLedgerRow -Attempts $count -LastAttemptAt $Now -LastOutcome "$($Outcomes[$id])" -MailAt $mailAt -GaveUp ($null -ne $had -and (Get-HordeWakeEntryValue $had "gaveUp") -eq $true)
    }
    foreach ($id in @($next.Keys)) {
        $taken = $false
        if ($null -ne $States -and $States.ContainsKey($id)) { $a = $States[$id]; $taken = ("$($a.state)" -ceq "known" -and $a.value.unreadCount -le 0) }
        $old = (($Now - $next[$id].lastAttemptAt).TotalSeconds -gt $script:HordeWakeLedgerKeepSeconds)
        if ($taken -or $old) { $next.Remove($id) }
    }
    return $next
}

function Update-HordeWakeGaveUp {
    # WHEN THE WATCHER STOPS ASKING, AND SAYS SO ONCE: { ledger; entries; sessions }.
    # A session that answers woken and never takes its mail was nudged for ever: about 15 times in its
    # first hour and 12 an hour after that, each a real line typed into its box (review of PR #211). A
    # doorbell rung six times that nobody answers is not going to be answered by a seventh ring; what
    # is needed then is somebody who can look. So after maxNudgesPerMail nudges for ONE mail - the
    # ledger entry is for the mail that is the session's oldest unread, its mailAt - the watcher gives
    # up on that mail: ONE entry of kind gave-up, and nothing more for that session (Get-HordeWakeHold)
    # until the mail is taken or another becomes the oldest. sessions is who was given up on this pass,
    # each { id; mailAt; attempts }, for the tell sender to tell the warchief (core/WakeTell.ps1).
    # -Ledger is not changed: the ledger returned has gaveUp set on the entries it was said for.
    param($Ledger, [Parameter(Mandatory = $true)][datetime]$Now, $Settings = (Get-HordeWakeSettings))
    $next = @{}
    $entries = New-Object System.Collections.ArrayList
    $sessions = New-Object System.Collections.ArrayList
    if ($null -ne $Ledger) {
        foreach ($id in @($Ledger.Keys | Sort-Object)) {
            $e = $Ledger[$id]
            $next["$id"] = $e
            if ([int]$e.attempts -lt [int]$Settings.maxNudgesPerMail -or (Get-HordeWakeEntryValue $e "gaveUp") -eq $true) { continue }
            $mailAt = Get-HordeWakeEntryValue $e "mailAt"
            $next["$id"] = New-HordeWakeLedgerRow -Attempts ([int]$e.attempts) -LastAttemptAt $e.lastAttemptAt -LastOutcome "$($e.lastOutcome)" -NothingAt (Get-HordeWakeNothingAt $e) -MailAt $mailAt -GaveUp $true
            $since = ""
            if ($mailAt -is [datetime]) { $since = " unread since " + $mailAt.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture) }
            [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "gave-up" -Id "$id" -Outcome "gave-up" -Reason ("" + $e.attempts + " nudges for its mail" + $since + ", the last answered " + $e.lastOutcome + ", and the mail was not taken; it is not nudged again for this mail")))
            [void]$sessions.Add([pscustomobject]@{ id = "$id"; mailAt = $mailAt; attempts = [int]$e.attempts })
        }
    }
    return [pscustomobject]@{ ledger = $next; entries = $entries.ToArray(); sessions = $sessions.ToArray() }
}

function Update-HordeWakeBadMail {
    # WHAT A MAILBOX WITH RECORDS NOBODY CAN READ IS TOLD ABOUT, AND WHEN: { seen; entries }.
    #   -Seen        session id -> { passes; told }, from the last pass
    #   -Unreadable  session id -> how many records of its mail could not be read, this pass
    # DEBOUNCED: a record being written as the fleet reads it is unreadable for one pass and whole the
    # next, so one sighting says nothing. Only when the same session shows unreadable mail on TWO PASSES
    # IN A ROW is one entry of kind bad-mail made, and then no other until it clears - a pass on which
    # the session shows none (or is not seen at all) forgets it, and a later return is told again.
    # THIS ONLY JOURNALS. It is never a reason not to nudge: the good mail beside a bad record is knocked
    # for as always (the waker port carries the count apart from unreadCount for exactly that).
    # THE SEAM FOR THE LIVE SLICE: telling the warchief by mail that a session's mailbox holds records
    # nobody can read belongs where this entry is made - a mail under an id made from the session and
    # the day, posted as core/RestoreSource.ps1 posts. Nothing posts it yet.
    param($Seen = @{}, $Unreadable = @{}, [Parameter(Mandatory = $true)][datetime]$Now)
    $next = @{}
    $entries = New-Object System.Collections.ArrayList
    if ($null -ne $Unreadable) {
        foreach ($id in @($Unreadable.Keys)) {
            $count = [int]$Unreadable[$id]
            if ($count -le 0) { continue }
            $passes = 1
            $told = $false
            if ($null -ne $Seen -and $Seen.ContainsKey($id)) { $passes = [int]$Seen[$id].passes + 1; $told = [bool]$Seen[$id].told }
            if ($passes -ge 2 -and -not $told) {
                $told = $true
                [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "bad-mail" -Id "$id" -Outcome "unreadable" -Reason ("" + $count + " record(s) of its mail cannot be read; the mail that can be is knocked for as always")))
            }
            $next["$id"] = [pscustomobject]@{ passes = $passes; told = $told }
        }
    }
    return [pscustomobject]@{ seen = $next; entries = $entries.ToArray() }
}

function Invoke-HordeWakePass {
    # ONE PASS. Reads the targets and each one's state through the port, decides, and acts; returns
    # { ledger; entries; decisions; unreadable }. It reads no clock and no file: the loop passes -Now and
    # keeps what comes back. unreadable is session id -> how many records of its mail could not be read,
    # for the sessions that have any (Update-HordeWakeBadMail, which the loop calls with it).
    #   -Waker            a registered waker, or $null when none is installed: then nobody is nudged
    #   -Ledger           session id -> { attempts; lastAttemptAt; lastOutcome }, from the last pass
    #   -Shadow           JOURNAL WHAT IT WOULD DO, AND DO NONE OF IT: no nudge is sent. A would-nudge
    #                     still counts as an attempt in the ledger, so the journal shows the rhythm a
    #                     live run would have had instead of a line every pass.
    # THE ENTRIES are the journal lines, kinds: nudge, nudge-killed (a nudge the waker had to stop
    # part-way), would-nudge and skip-unknown (a listing or a state the port could not give; id is ""
    # for the listing).
    param($Waker, [Parameter(Mandatory = $true)][datetime]$Now, $Settings = (Get-HordeWakeSettings), $Ledger = @{}, [switch]$Shadow)
    $entries = New-Object System.Collections.ArrayList
    $nextLedger = $Ledger
    $decisions = @()
    $unreadable = @{}
    $gaveUp = @()
    if ($null -ne $Waker) {
        # A PASS BEGINS: the waker is told, so what it read of the fleet for the last pass is not reused
        # for this one and is read once for all of this one's questions (wakers/Port.ps1, Begin).
        Start-HordeWakePass -Waker $Waker
        $listing = Get-HordeWakeTargets -Waker $Waker
        if ($listing.state -cne "known") {
            [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "skip-unknown" -Outcome "unknown" -Reason ("the targets are unknown: " + $listing.reason)))
        } else {
            $targets = @($listing.value)
            $states = @{}
            foreach ($t in $targets) {
                $states[$t.id] = Get-HordeWakeState -Waker $Waker -Id $t.id
                if ($states[$t.id].state -ceq "known" -and $states[$t.id].value.unreadableCount -gt 0) { $unreadable[$t.id] = $states[$t.id].value.unreadableCount }
                if ($states[$t.id].state -cne "known") { [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "skip-unknown" -Id $t.id -Outcome "unknown" -Reason "$($states[$t.id].reason)")) }
            }
            # THE LOOK COMES LAST, AND ONLY FOR A SESSION ABOUT TO BE NUDGED. The states above are the
            # waker's cheap reading. A session the decisions would nudge but for its unread box is
            # looked at - the waker's full reading - and the decisions are made again with it; a session
            # the look rules out gives its place to the next, which is looked at in turn, up to
            # maxConfirmsPerPass looks. What is still unlooked then waits for the next pass.
            $canLook = Test-HordeWakerConfirms $Waker
            $confirmed = @{}
            $decisions = @(Get-HordeWakeDecisions -Targets $targets -States $states -Ledger $Ledger -Now $Now -Settings $Settings -Confirmed $confirmed -CanLook:$canLook)
            while ($confirmed.Count -lt [int]$Settings.maxConfirmsPerPass) {
                $toLook = @($decisions | Where-Object { $_.action -ceq "look" })
                if ($toLook.Count -eq 0) { break }
                foreach ($d in $toLook) {
                    if ($confirmed.Count -ge [int]$Settings.maxConfirmsPerPass) { break }
                    $confirmed[$d.id] = Get-HordeWakeState -Waker $Waker -Id $d.id -Full
                    if ($confirmed[$d.id].state -cne "known") { [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "skip-unknown" -Id $d.id -Outcome "unknown" -Reason "$($confirmed[$d.id].reason)")) }
                    else { $states[$d.id] = $confirmed[$d.id] }
                }
                $decisions = @(Get-HordeWakeDecisions -Targets $targets -States $states -Ledger $Ledger -Now $Now -Settings $Settings -Confirmed $confirmed -CanLook:$canLook)
            }
            foreach ($d in $decisions) { if ($d.action -ceq "look") { $d.action = "wait"; $d.reason = "its box and its turn were not read this pass: the pass's looks were used up" } }
            $outcomes = @{}
            foreach ($d in $decisions) {
                if ($d.action -cne "nudge") { continue }
                # SHADOW: the nudge is journaled and counted, and nothing is asked of the waker.
                if ($Shadow) { $outcomes[$d.id] = "would-nudge"; [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "would-nudge" -Id $d.id -Outcome "would-nudge" -Reason $d.reason)); continue }
                $rang = Send-HordeWakeNudge -Waker $Waker -Id $d.id
                if ($rang.state -ceq "known") {
                    $outcomes[$d.id] = $rang.value.outcome
                    # A RUN OF NOTHINGS IS JOURNALED ONCE, when it starts: the ledger's hold says one is under way.
                    if ($rang.value.outcome -ceq "nothing" -and $null -ne (Get-HordeWakeNothingAt (Get-HordeWakeLedgerEntry -Ledger $Ledger -Id $d.id))) { continue }
                    # A NUDGE THE WAKER HAD TO KILL IS ITS OWN KIND OF LINE, so nobody reads it as one more nudge.
                    $kind = "nudge"
                    if ($rang.value.outcome -ceq "killed") { $kind = "nudge-killed" }
                    [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind $kind -Id $d.id -Outcome $rang.value.outcome -Reason $rang.value.reason))
                }
                else { $outcomes[$d.id] = "unknown"; [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "nudge" -Id $d.id -Outcome "unknown" -Reason "$($rang.reason)")) }
            }
            $nextLedger = Update-HordeWakeLedger -Ledger $Ledger -Decisions $decisions -Outcomes $outcomes -States $states -Now $Now -Settings $Settings
            # THE CAP: a session nudged maxNudgesPerMail times for one mail is given up on, said once.
            $gave = Update-HordeWakeGaveUp -Ledger $nextLedger -Now $Now -Settings $Settings
            $nextLedger = $gave.ledger
            $gaveUp = @($gave.sessions)
            foreach ($e in @($gave.entries)) { [void]$entries.Add($e) }
        }
    }
    return [pscustomobject]@{ ledger = $nextLedger; entries = $entries.ToArray(); decisions = $decisions; unreadable = $unreadable; gaveUp = $gaveUp }
}

# ---- the file: <home>\wake\ledger.json, or ledger-shadow.json for a shadow run ----
# Kept apart from everything above, which reads and writes none. Only the command's loop calls these.

function Save-HordeWakeLedger {
    # The ledger file, replaced whole: the back-off of every session being asked, so a watcher that is
    # restarted does not knock at once on a session it had been told to leave for five minutes.
    # -Shadow names the shadow run's own file (core/WakeFiles.ps1, Get-HordeWakeStateFile).
    param($Ledger, [switch]$Shadow, [string]$HordeHome = (Get-HordeHome))
    $sessions = New-Object System.Collections.ArrayList
    if ($null -ne $Ledger) {
        foreach ($id in @($Ledger.Keys | Sort-Object)) {
            $row = [ordered]@{ id = "$id"; attempts = [int]$Ledger[$id].attempts; lastAttemptAt = (ConvertTo-HordeWakeTimeText $Ledger[$id].lastAttemptAt); lastOutcome = "$($Ledger[$id].lastOutcome)" }
            $heldAt = Get-HordeWakeNothingAt $Ledger[$id]
            if ($null -ne $heldAt) { $row["nothingAt"] = ConvertTo-HordeWakeTimeText $heldAt }
            $mailAt = Get-HordeWakeEntryValue $Ledger[$id] "mailAt"
            if ($mailAt -is [datetime]) { $row["mailAt"] = ConvertTo-HordeWakeTimeText $mailAt }
            if ((Get-HordeWakeEntryValue $Ledger[$id] "gaveUp") -eq $true) { $row["gaveUp"] = $true }
            [void]$sessions.Add($row)
        }
    }
    $doc = [ordered]@{ schemaVersion = 1; sessions = $sessions.ToArray() }
    Write-HordeWakeFile -Path (Get-HordeWakeStateFile -Name "ledger" -Shadow:$Shadow -HordeHome $HordeHome) -Text (ConvertTo-Json -InputObject $doc -Depth 5 -Compress)
}

function Read-HordeWakeLedger {
    # What Save-HordeWakeLedger wrote: known { ledger }, absent when there is none, or unknown
    # when it cannot be read - the caller then starts from an empty ledger and says so.
    param([switch]$Shadow, [string]$HordeHome = (Get-HordeHome))
    $path = Get-HordeWakeStateFile -Name "ledger" -Shadow:$Shadow -HordeHome $HordeHome
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return (New-HordeAbsent -Note "no ledger was saved in this home") }
    try { $j = (Read-HordeSharedText -Path $path) | ConvertFrom-Json }
    catch { return (New-HordeUnknown -Reason "the saved ledger could not be read" -ErrorRecord $_) }
    if ($null -eq $j -or $null -eq $j.PSObject.Properties["sessions"]) { return (New-HordeUnknown -Reason "the saved ledger is not a ledger") }
    $ledger = @{}
    try {
        foreach ($row in @($j.sessions)) {
            if ($null -eq $row) { continue }
            $at = ConvertFrom-HordeWakeTimeText $row.lastAttemptAt
            if ($null -eq $at -or "$($row.id)" -eq "") { return (New-HordeUnknown -Reason "the saved ledger holds an entry with no session or no time") }
            $entry = [ordered]@{ attempts = [int]$row.attempts; lastAttemptAt = $at; lastOutcome = "$($row.lastOutcome)" }
            if ($null -ne $row.PSObject.Properties["nothingAt"]) { $heldAt = ConvertFrom-HordeWakeTimeText $row.nothingAt; if ($null -ne $heldAt) { $entry["nothingAt"] = $heldAt } }
            if ($null -ne $row.PSObject.Properties["mailAt"]) { $mailAt = ConvertFrom-HordeWakeTimeText $row.mailAt; if ($null -ne $mailAt) { $entry["mailAt"] = $mailAt } }
            if ($null -ne $row.PSObject.Properties["gaveUp"] -and $row.gaveUp -eq $true) { $entry["gaveUp"] = $true }
            $ledger["$($row.id)"] = [pscustomobject]$entry
        }
    } catch { return (New-HordeUnknown -Reason "the saved ledger holds an entry that is not one" -ErrorRecord $_) }
    return (New-HordeKnown -Value ([pscustomobject]@{ ledger = $ledger }))
}
