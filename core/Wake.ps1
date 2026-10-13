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
        # After this many readings of the fleet failed in a row, the failure is called permanent
        # (Update-HordeWakeFleetRead).
        maxFleetReadFailures = 10
        # At most this many full readings of a session - a look at its box and its turn - in one pass
        # (Invoke-HordeWakePass, THE LOOK COMES LAST). Each can take a pane's whole time-out.
        maxConfirmsPerPass = 3
        # THE FLEET IS SILENT when, for this many minutes, every nudge was answered woken and no
        # session took any mail - and at least fleetSilentSessions sessions were nudged in them
        # (Update-HordeWakeSilence).
        # FIVE MINUTES, BECAUSE THE SILENCE MUST BE FOUND BEFORE THE CAP IS SPENT: a session asked as
        # fast as the back-off allows is nudged at 0, 5, 20, 65, 200 and 500 s, and the sixth is the
        # one after which it is given up on. At ten minutes the silence was found at 600 s, after a
        # lone fast session had already been given up on at 500 (review of PR #220); at five it is
        # found at 300 s, after the fifth nudge and before the sixth. test/test-wake.ps1 holds that
        # order at these defaults, so changing this, the back-off or the cap so as to swap it fails.
        # Where a waker SAYS a session is limited, that fact is used and this inference is not needed.
        fleetSilentMinutes = 5
        fleetSilentSessions = 3
        # A session limited with no known end is knocked for once after this long, uncounted
        # (Get-HordeWakeHold, LIMITED WITH NO KNOWN END).
        limitedUnknownProbeSeconds = 3600
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
    # probeAt is when the session was last nudged WITHOUT the nudge being counted (Get-HordeWakeHold, A
    # PROBE).
    param([int]$Attempts, $LastAttemptAt, [string]$LastOutcome, $NothingAt = $null, $MailAt = $null, [bool]$GaveUp = $false, $ProbeAt = $null)
    $row = [ordered]@{ attempts = $Attempts; lastAttemptAt = $LastAttemptAt; lastOutcome = $LastOutcome }
    if ($ProbeAt -is [datetime]) { $row["probeAt"] = $ProbeAt }
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

function Get-HordeWakeLimit {
    # A session's usage limit as the watcher reads it at -Now: { kind; text }.
    #   none   it is not limited, or its waker cannot tell - or THE LIMIT IS OVER: the waker still says
    #          limited and the time it gives has passed. The fleet's command keeps a past reset in
    #          its row, so the comparison with now is made here, and a limit that is over is the same
    #          case as a restore: the session is knocked for under the normal rules, in its fair turn
    #   until  limited, and the limit ends at a known time still ahead: it is not nudged at all
    #   open   limited, and nobody knows until when - the waker gave no time (one it could not read,
    #          a clock-change hour, a dated weekly reset): Get-HordeWakeHold, LIMITED WITH NO KNOWN END
    # WHY (measured 2026-10-13, 04:36 to 05:55 UTC): the account's usage limit stopped every session
    # for about 80 minutes. Every knock in that window was typed and submitted, and no session could
    # answer. The six nudges a mail is allowed were spent in about 13 minutes, so the watcher had
    # given up on everybody and was silent at the moment the limit reset - nobody was woken after it.
    # A knock at a session that cannot answer proves nothing about the session and must cost nothing.
    param($State, [Parameter(Mandatory = $true)][datetime]$Now)
    if ((Get-HordeWakeEntryValue $State "limited") -ne $true) { return [pscustomobject]@{ kind = "none"; text = "" } }
    $until = Get-HordeWakeEntryValue $State "limitedUntil"
    if ($until -is [datetime] -and $until -le $Now) { return [pscustomobject]@{ kind = "none"; text = "" } }
    if ($until -is [datetime]) { return [pscustomobject]@{ kind = "until"; text = ("usage limit until " + $until.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)) } }
    return [pscustomobject]@{ kind = "open"; text = "usage limit, end unknown" }
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
    # A LIMITED SESSION WHOSE LIMIT ENDS AT A KNOWN TIME is wait until then: no knock, no attempt.
    # A PROBE is the nudge of a session that cannot be expected to answer. It is NOT COUNTED: neither the
    # cap nor the back-off's steps are spent on it (Update-HordeWakeLedger). There are two:
    #   THE FLEET IS SILENT (-Silent; Update-HordeWakeSilence): each session is probed at the longest
    #   step of the back-off, and the first to take mail ends it.
    #   LIMITED WITH NO KNOWN END: the session waits. It is NOT knocked on a timer every few minutes -
    #   that is a line typed into a session that cannot answer, twelve times an hour. It is released
    #   - one knock - when a session of the fleet takes mail (the caller then marks its probe due:
    #   Set-HordeWakeLedgerProbesDue), which is the sign a shared limit has reset; and, failing that,
    #   limitedUnknownProbeSeconds after it was first seen so or last probed. THAT HOURLY KNOCK IS WHAT
    #   KEEPS A LONE LIMITED SESSION FROM BEING STUCK FOR EVER when nothing else in the fleet moves: with
    #   no end known and nobody else to watch, asking is the only way left to find out. When it was first
    #   seen limited is its ledger entry's probeAt, stamped by the pass that saw it.
    # A RETIRED SESSION IS NEVER NUDGED, AND THIS IS THE FIRST THING ASKED: before its mail, its state or
    # anything else. A session that was retired and still has mail was a target like any other - the
    # fleet works out reachable and idle for it as for any session, and nothing here read retired
    # (safety review of PR 220) - so the watcher would have typed into a session whose work was over.
    # It is skip, like a session with no mail: not waiting for anything, not an attempt, not a failure,
    # never given up on and never told of. retired UNKNOWN - the waker could not tell - is held too:
    # wait, because it may yet be read as no. Either is journaled once (Invoke-HordeWakePass's held).
    param($Target, $StateAnswer, $Entry, [datetime]$Now, $Settings, [switch]$CanLook, [switch]$Silent)
    $retired = "$(Get-HordeWakeEntryValue $Target "retired")"
    if ($retired -ceq "yes") { return [pscustomobject]@{ action = "skip"; reason = "retired: a retired session is never nudged" } }
    if ($retired -cne "no") { return [pscustomobject]@{ action = "wait"; reason = "retired is unknown: a session that may be retired is not nudged" } }
    if ($null -eq $StateAnswer -or "$($StateAnswer.state)" -cne "known") {
        $why = "nothing answered for it"
        if ($null -ne $StateAnswer) { $why = "$($StateAnswer.reason)" }
        return [pscustomobject]@{ action = "wait"; reason = ("its state is unknown: " + $why) }
    }
    $s = $StateAnswer.value
    if ($s.unreadCount -le 0) { return [pscustomobject]@{ action = "skip"; reason = "no unread mail" } }
    $limit = Get-HordeWakeLimit -State $s -Now $Now
    if ($limit.kind -ceq "until") { return [pscustomobject]@{ action = "wait"; reason = $limit.text } }
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
    $probe = ($Silent -or $limit.kind -ceq "open")
    if ($probe) {
        $why = "the fleet is silent"
        if ($limit.kind -ceq "open") { $why = $limit.text }
        $steps = @($Settings.backoffSeconds)
        $longest = 0
        if ($steps.Count -gt 0) { $longest = [int]$steps[$steps.Count - 1] }
        $last = Get-HordeWakeEntryValue $Entry "probeAt"
        if ($limit.kind -ceq "open") {
            $every = [int]$Settings.limitedUnknownProbeSeconds
            if ($last -isnot [datetime]) { return [pscustomobject]@{ action = "wait"; reason = ($why + ": it waits for a session of the fleet to take mail, or " + $every + " s") } }
            if (($Now - $last).TotalSeconds -lt $every) { return [pscustomobject]@{ action = "wait"; reason = ($why + ": it waits for a session of the fleet to take mail, or " + [int][System.Math]::Ceiling($every - ($Now - $last).TotalSeconds) + " s more") } }
            $last = $null
        }
        if ($last -isnot [datetime] -and $null -ne $Entry -and $limit.kind -cne "open") { $last = $Entry.lastAttemptAt }
        if ($last -is [datetime] -and ($Now - $last).TotalSeconds -lt $longest) { return [pscustomobject]@{ action = "wait"; reason = ($why + ": it is asked only every " + $longest + " s, and no attempt is counted; " + [int][System.Math]::Ceiling($longest - ($Now - $last).TotalSeconds) + " s left") } }
    }
    if (-not $probe -and $null -ne $Entry -and [int]$Entry.attempts -ge [int]$Settings.maxNudgesPerMail) { return [pscustomobject]@{ action = "wait"; reason = ("gave up after " + $Entry.attempts + " nudges for this mail; nothing more is tried until it is taken or another mail becomes the oldest") } }
    if (-not $probe -and $null -ne $Entry) {
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
    # then by role (warchief, orc, warg, unknown), then the oldest unread mail. Fewest attempts first
    # is what makes a restore of everything a fair queue: without it the warchief's second knock, due
    # 5 s after its first, would go ahead of nine sessions nobody had knocked on yet. The rest get wait
    # "rate limit" and are ready again next pass.
    #   -Silent     the fleet is silent (Update-HordeWakeSilence): every nudge is a probe
    param($Targets, $States, $Ledger, [Parameter(Mandatory = $true)][datetime]$Now, $Settings = (Get-HordeWakeSettings), $Confirmed = @{}, [switch]$CanLook, [switch]$Silent)
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
        $hold = Get-HordeWakeHold -Target $t -StateAnswer $answer -Entry $entry -Now $Now -Settings $Settings -CanLook:($CanLook -and -not $looked) -Silent:$Silent
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
    # A PROBE IS NOT AN ATTEMPT EITHER (Get-HordeWakeHold): a nudge sent while the session's usage limit
    # has no known end, or while the fleet is silent (-Silent), leaves the count and the mail's cap as
    # they were and records only when it was sent, probeAt, which is what spaces the next one.
    param($Ledger, $Decisions, $Outcomes, $States, [Parameter(Mandatory = $true)][datetime]$Now, $Settings = (Get-HordeWakeSettings), [switch]$Silent)
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
            if ($null -ne $had) { $kept = New-HordeWakeLedgerRow -Attempts ([int]$had.attempts) -LastAttemptAt $had.lastAttemptAt -LastOutcome "$($had.lastOutcome)" -NothingAt $Now -MailAt $mailAt -GaveUp ((Get-HordeWakeEntryValue $had "gaveUp") -eq $true) -ProbeAt (Get-HordeWakeEntryValue $had "probeAt") }
            $next[$id] = $kept
            continue
        }
        if ($Silent -or (Get-HordeWakeLimit -State $stateNow -Now $Now).kind -ceq "open") {
            $probed = New-HordeWakeLedgerRow -Attempts 0 -LastAttemptAt $Now -LastOutcome "$($Outcomes[$id])" -MailAt $mailAt -ProbeAt $Now
            if ($null -ne $had) { $probed = New-HordeWakeLedgerRow -Attempts ([int]$had.attempts) -LastAttemptAt $had.lastAttemptAt -LastOutcome "$($Outcomes[$id])" -MailAt $mailAt -GaveUp ((Get-HordeWakeEntryValue $had "gaveUp") -eq $true) -ProbeAt $Now }
            $next[$id] = $probed
            continue
        }
        $before = 0
        if ($null -ne $had) { $before = [int]$had.attempts }
        $count = $before + 1
        if ("$($Outcomes[$id])" -ceq "killed") { $count = [System.Math]::Max($count, @($Settings.backoffSeconds).Count) }
        $next[$id] = New-HordeWakeLedgerRow -Attempts $count -LastAttemptAt $Now -LastOutcome "$($Outcomes[$id])" -MailAt $mailAt -GaveUp ($null -ne $had -and (Get-HordeWakeEntryValue $had "gaveUp") -eq $true)
    }
    # FIRST SEEN LIMITED WITH NO KNOWN END: stamped now, as the entry's probeAt, which is what its hour
    # is counted from (Get-HordeWakeHold). An entry it already has keeps its count.
    if ($null -ne $States) {
        foreach ($id in @($States.Keys)) {
            $a = $States[$id]
            if ($null -eq $a -or "$($a.state)" -cne "known" -or $a.value.unreadCount -le 0 -or (Get-HordeWakeLimit -State $a.value -Now $Now).kind -cne "open") { continue }
            $had = Get-HordeWakeLedgerEntry -Ledger $next -Id "$id" -State $a.value
            if ((Get-HordeWakeEntryValue $had "probeAt") -is [datetime]) { continue }
            $seen = New-HordeWakeLedgerRow -Attempts 0 -LastAttemptAt $Now -LastOutcome "limited" -MailAt $a.value.oldestUnreadAt -ProbeAt $Now
            if ($null -ne $had) { $seen = New-HordeWakeLedgerRow -Attempts ([int]$had.attempts) -LastAttemptAt $had.lastAttemptAt -LastOutcome "$($had.lastOutcome)" -NothingAt (Get-HordeWakeNothingAt $had) -MailAt $a.value.oldestUnreadAt -GaveUp ((Get-HordeWakeEntryValue $had "gaveUp") -eq $true) -ProbeAt $Now }
            $next["$id"] = $seen
        }
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
            $next["$id"] = New-HordeWakeLedgerRow -Attempts ([int]$e.attempts) -LastAttemptAt $e.lastAttemptAt -LastOutcome "$($e.lastOutcome)" -NothingAt (Get-HordeWakeNothingAt $e) -MailAt $mailAt -GaveUp $true -ProbeAt (Get-HordeWakeEntryValue $e "probeAt")
            $since = ""
            if ($mailAt -is [datetime]) { $since = " unread since " + $mailAt.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture) }
            [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "gave-up" -Id "$id" -Outcome "gave-up" -Reason ("" + $e.attempts + " nudges for its mail" + $since + ", the last answered " + $e.lastOutcome + ", and the mail was not taken; it is not nudged again for this mail")))
            [void]$sessions.Add([pscustomobject]@{ id = "$id"; mailAt = $mailAt; attempts = [int]$e.attempts })
        }
    }
    return [pscustomobject]@{ ledger = $next; entries = $entries.ToArray(); sessions = $sessions.ToArray() }
}

function Update-HordeWakeSaidOnce {
    # A STANDING FACT ABOUT A SESSION IS JOURNALED ONCE, AND AGAIN ONLY WHEN IT CHANGES: { seen; entries }.
    #   -Seen   session id -> what was last said of it, from the last pass
    #   -Said   session id -> what there is to say of it now (the entry's reason), for the sessions it
    #           holds of; a session not in it has nothing said of it any more and is forgotten
    #   -Known  the ids whose state was read this pass: one that was not is left as it was, so a pass
    #           that could not read a session does not say the same thing again on the next
    # A pass holds a retired session, or a limited one, on every pass for as long as it lasts; a line
    # every 3 s would bury the journal, and no line at all would hide why mail is not being knocked for.
    param($Seen = @{}, $Said = @{}, $Known = @(), [Parameter(Mandatory = $true)][datetime]$Now, [Parameter(Mandatory = $true)][string]$Kind, [Parameter(Mandatory = $true)][string]$Outcome)
    $next = @{}
    $entries = New-Object System.Collections.ArrayList
    if ($null -ne $Seen) { foreach ($id in @($Seen.Keys)) { if (@($Known) -cnotcontains "$id") { $next["$id"] = $Seen[$id] } } }
    if ($null -ne $Said) {
        foreach ($id in @($Said.Keys | Sort-Object)) {
            $text = "$($Said[$id])"
            $next["$id"] = $text
            if ($null -ne $Seen -and $Seen.ContainsKey("$id") -and "$($Seen[$id])" -ceq $text) { continue }
            [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind $Kind -Id "$id" -Outcome $Outcome -Reason $text))
        }
    }
    return [pscustomobject]@{ seen = $next; entries = $entries.ToArray() }
}

function Update-HordeWakeLimited {
    # A USAGE LIMIT IS JOURNALED ONCE PER SESSION PER LIMIT, not every pass: { seen; entries }
    # (Update-HordeWakeSaidOnce). -Limited is session id -> its limit's text now (Get-HordeWakeLimit),
    # for the sessions with unread mail that are limited. One entry of kind usage-limit when a session
    # becomes limited, and one more when its limit's end changes.
    param($Seen = @{}, $Limited = @{}, $Known = @(), [Parameter(Mandatory = $true)][datetime]$Now)
    $said = @{}
    if ($null -ne $Limited) {
        foreach ($id in @($Limited.Keys)) {
            $text = "$($Limited[$id])"
            $what = ": it is not nudged before then, and no attempt is counted against its mail"
            if ($text -cnotlike "usage limit until *") { $what = ": it is not nudged until a session of the fleet takes mail, or once an hour, and no attempt is counted against its mail" }
            $said["$id"] = $text + $what
        }
    }
    return (Update-HordeWakeSaidOnce -Seen $Seen -Said $said -Known $Known -Now $Now -Kind "usage-limit" -Outcome "limited")
}

function Update-HordeWakeSilence {
    # WHEN NOBODY IN THE FLEET CAN ANSWER, AND NO WAKER SAYS WHY: { seen; entries; silent; declared;
    # moved; condition }. moved is true on a pass that saw a session take mail, silent before or not:
    # the caller then releases the sessions limited with no known end (Set-HordeWakeLedgerProbesDue). The net under Get-HordeWakeLimit, for a harness that reports no limit.
    #   -Seen     { silent; quietSince; nudges; mail }, from the last pass, or $null
    #   -Entries  this pass's journal entries; its nudges are read from them
    #   -Mail     session id -> its oldest unread mail's time, or $null when it has none, for the
    #             sessions whose state was read this pass
    # THE FLEET IS SILENT when the watcher has been nudging for fleetSilentMinutes with no session taking
    # any mail, and in the last fleetSilentMinutes every nudge was answered woken, to at least
    # fleetSilentSessions different sessions. Woken and never taken, by everybody at once, is not three
    # stubborn sessions: it is a fleet that cannot answer (the incident Get-HordeWakeLimit describes).
    # ONE entry of kind fleet-silent, one condition for the warchief (core/WakeTell.ps1), and declared is
    # true on that pass alone: the caller then forgives the attempts spent on a fleet that could not
    # answer (Reset-HordeWakeLedgerAttempts). While it lasts the caller passes -Silent to the pass, so
    # every nudge is a probe - the longest step, uncounted. A NUDGE THAT IS NOT WOKEN - busy, mid-turn -
    # IS A SESSION AT WORK, and a fleet with one of those is not silent.
    # IT ENDS WHEN ANY SESSION TAKES MAIL - its oldest unread mail becomes another, or none: one entry of
    # kind fleet-moving, and every session is nudged as normal again, from no attempts, in the fair order.
    param($Seen = $null, $Entries = @(), $Mail = @{}, [Parameter(Mandatory = $true)][datetime]$Now, $Settings = (Get-HordeWakeSettings))
    $before = [pscustomobject]@{ silent = $false; quietSince = $null; nudges = @(); mail = @{} }
    if ($null -ne $Seen) { $before = $Seen }
    $out = New-Object System.Collections.ArrayList
    $moved = $false
    $mailNow = @{}
    foreach ($id in @($before.mail.Keys)) { $mailNow["$id"] = $before.mail[$id] }
    if ($null -ne $Mail) {
        foreach ($id in @($Mail.Keys)) {
            $had = $null
            if ($before.mail.ContainsKey("$id")) { $had = $before.mail[$id] }
            if ($had -is [datetime] -and ($Mail[$id] -isnot [datetime] -or $Mail[$id] -ne $had)) { $moved = $true }
            if ($Mail[$id] -is [datetime]) { $mailNow["$id"] = $Mail[$id] } else { $mailNow.Remove("$id") }
        }
    }
    if ($moved) {
        if ($before.silent -eq $true) { [void]$out.Add((New-HordeWakeEntry -At $Now -Kind "fleet-moving" -Outcome "moving" -Reason "a session took its mail: the fleet is answering again, and every session is nudged as normal")) }
        return [pscustomobject]@{ seen = [pscustomobject]@{ silent = $false; quietSince = $null; nudges = @(); mail = $mailNow }; entries = $out.ToArray(); silent = $false; declared = $false; moved = $true; condition = $null }
    }
    $window = [double]$Settings.fleetSilentMinutes * 60
    $nudges = New-Object System.Collections.ArrayList
    foreach ($n in @($before.nudges)) { if ($null -ne $n -and ($Now - $n.at).TotalSeconds -lt $window) { [void]$nudges.Add($n) } }
    $quietSince = $before.quietSince
    foreach ($e in @($Entries)) {
        if ($null -eq $e -or @("nudge", "nudge-killed") -cnotcontains "$($e.kind)") { continue }
        [void]$nudges.Add([pscustomobject]@{ id = "$($e.id)"; at = $Now; outcome = "$($e.outcome)" })
        if ($quietSince -isnot [datetime]) { $quietSince = $Now }
    }
    $next = [pscustomobject]@{ silent = ($before.silent -eq $true); quietSince = $quietSince; nudges = $nudges.ToArray(); mail = $mailNow }
    if ($next.silent) { return [pscustomobject]@{ seen = $next; entries = @(); silent = $true; declared = $false; moved = $false; condition = $null } }
    $who = @($nudges | ForEach-Object { $_.id } | Sort-Object -Unique)
    $notWoken = @($nudges | Where-Object { $_.outcome -cne "woken" })
    if ($quietSince -is [datetime] -and ($Now - $quietSince).TotalSeconds -ge $window -and $who.Count -ge [int]$Settings.fleetSilentSessions -and $notWoken.Count -eq 0) {
        $next.silent = $true
        $what = ("for " + $Settings.fleetSilentMinutes + " minutes every nudge - " + $nudges.Count + ", to " + $who.Count + " sessions - was answered woken, and no session took its mail")
        [void]$out.Add((New-HordeWakeEntry -At $Now -Kind "fleet-silent" -Outcome "silent" -Reason ($what + ". The fleet cannot answer: no attempt is counted against any mail from here, and each session is asked only at the longest back-off step until one takes mail")))
        $condition = [pscustomobject]@{ kind = "fleet-silent"; subject = ""; instance = $quietSince.ToUniversalTime().ToString("o", [System.Globalization.CultureInfo]::InvariantCulture); text = ($what + ". The fleet looks unable to answer - a usage limit, perhaps. The watcher keeps asking, slowly, and wakes everybody when one session takes mail.") }
        return [pscustomobject]@{ seen = $next; entries = $out.ToArray(); silent = $true; declared = $true; moved = $false; condition = $condition }
    }
    return [pscustomobject]@{ seen = $next; entries = @(); silent = $false; declared = $false; moved = $false; condition = $null }
}

# The time a probe is marked due with: long before any pass.
$script:HordeWakeProbeDue = New-Object System.DateTime(2000, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)

function Set-HordeWakeLedgerProbesDue {
    # The ledger with every probe marked due, for the pass on which a session of the fleet was seen
    # to take mail: a session limited with no known end is then knocked for once, in its fair turn
    # (Get-HordeWakeHold, LIMITED WITH NO KNOWN END). The mark stays until that knock is sent, so the
    # rate limit of one nudge a pass delays a release and never loses it.
    param($Ledger)
    $next = @{}
    if ($null -ne $Ledger) {
        foreach ($id in @($Ledger.Keys)) {
            $e = $Ledger[$id]
            $next["$id"] = $e
            if ((Get-HordeWakeEntryValue $e "probeAt") -isnot [datetime]) { continue }
            $next["$id"] = New-HordeWakeLedgerRow -Attempts ([int]$e.attempts) -LastAttemptAt $e.lastAttemptAt -LastOutcome "$($e.lastOutcome)" -NothingAt (Get-HordeWakeNothingAt $e) -MailAt (Get-HordeWakeEntryValue $e "mailAt") -GaveUp ((Get-HordeWakeEntryValue $e "gaveUp") -eq $true) -ProbeAt $script:HordeWakeProbeDue
        }
    }
    return $next
}

function Reset-HordeWakeLedgerAttempts {
    # The ledger with every attempt forgiven, for the pass on which the fleet is found silent
    # (Update-HordeWakeSilence): the nudges counted until then went to sessions that could not answer,
    # and a mail's cap spent on them would leave the watcher silent when the fleet comes back. Each
    # entry keeps when it was last asked - as its probe - so nobody is asked again at once.
    param($Ledger)
    $next = @{}
    if ($null -ne $Ledger) {
        foreach ($id in @($Ledger.Keys)) {
            $e = $Ledger[$id]
            $next["$id"] = New-HordeWakeLedgerRow -Attempts 0 -LastAttemptAt $e.lastAttemptAt -LastOutcome "$($e.lastOutcome)" -NothingAt (Get-HordeWakeNothingAt $e) -MailAt (Get-HordeWakeEntryValue $e "mailAt") -ProbeAt $e.lastAttemptAt
        }
    }
    return $next
}

function Update-HordeWakeFleetRead {
    # WHEN A FLEET THAT CANNOT BE READ STOPS BEING A HICCUP: { seen; entries; quiet; condition }.
    #   -Seen     { failures; since; told }, from the last pass, or $null
    #   -Listing  this pass's answer to "which sessions are there" (the port's Get-HordeWakeTargets)
    # A failing read was backed off and never capped (review of PR #211): a registry that cannot be read
    # until a person mends a file was retried for ever, with one journal line at the start and nothing
    # to tell anybody it had become the state of things. So after maxFleetReadFailures readings failed
    # IN A ROW the failure is PERMANENT: one entry of kind fleet-read-failing, one condition for the
    # warchief to be told (core/WakeTell.ps1), and then quiet - the journal's line for each unreadable
    # pass is dropped while it lasts - until a reading works, which is one entry of kind recovered.
    # THE COUNT IS THE WAKER'S WHEN IT GIVES ONE (the unknown's failures, wakers/Port.ps1): a waker that
    # backs its readings off makes far fewer readings than the watcher makes passes. Otherwise it is the
    # passes in a row on which the listing was unknown. The waker's own back-off is what spaces the
    # retries; by the count that makes a failure permanent it is long since at its longest step.
    param($Seen = $null, $Listing = $null, [Parameter(Mandatory = $true)][datetime]$Now, $Settings = (Get-HordeWakeSettings))
    $before = [pscustomobject]@{ failures = 0; since = $null; told = $false }
    if ($null -ne $Seen) { $before = $Seen }
    $entries = New-Object System.Collections.ArrayList
    if ($null -eq $Listing) { return [pscustomobject]@{ seen = $before; entries = @(); quiet = $false; condition = $null } }
    if ("$($Listing.state)" -ceq "known") {
        if ($before.told -eq $true) { [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "recovered" -Outcome "recovered" -Reason ("the fleet can be read again, after " + $before.failures + " readings in a row had failed"))) }
        return [pscustomobject]@{ seen = [pscustomobject]@{ failures = 0; since = $null; told = $false }; entries = $entries.ToArray(); quiet = $false; condition = $null }
    }
    $count = [int]$before.failures + 1
    $given = Get-HordeWakeEntryValue $Listing "failures"
    if ($given -is [int] -or $given -is [long]) { $count = [int]$given }
    $since = $before.since
    if ($since -isnot [datetime]) { $since = $Now }
    $told = ($before.told -eq $true)
    $condition = $null
    if (-not $told -and $count -ge [int]$Settings.maxFleetReadFailures) {
        $told = $true
        $what = ("" + $count + " readings of the fleet in a row have failed, the first at " + $since.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture) + ": " + $Listing.reason)
        [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "fleet-read-failing" -Outcome "permanent" -Reason ($what + ". No session can be woken while this lasts. It is tried again at the waker's longest back-off, and nothing more is said until it works")))
        $condition = [pscustomobject]@{ kind = "fleet-read-failing"; subject = ""; instance = $since.ToUniversalTime().ToString("o", [System.Globalization.CultureInfo]::InvariantCulture); text = ($what + ". No session can be woken by the watcher while this lasts.") }
    }
    return [pscustomobject]@{ seen = [pscustomobject]@{ failures = $count; since = $since; told = $told }; entries = $entries.ToArray(); quiet = $told; condition = $condition }
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
    # THE WARCHIEF IS TOLD OF IT by the tell sender (core/WakeTell.ps1), which the tick hands each entry
    # made here as a condition; this function only decides when there is something to say.
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
    # { ledger; entries; decisions; unreadable; gaveUp; listing; warchief }. It reads no clock and no file:
    # the loop passes -Now and keeps what comes back. unreadable is session id -> how many records of
    # its mail could not be read (Update-HordeWakeBadMail, which the loop calls with it); gaveUp is who
    # was given up on this pass; listing is what the waker answered to "which sessions are there"; and
    # warchief is the one session with that role, or "".
    #   -Waker            a registered waker, or $null when none is installed: then nobody is nudged
    #   -Ledger           session id -> { attempts; lastAttemptAt; lastOutcome }, from the last pass
    #   -Shadow           JOURNAL WHAT IT WOULD DO, AND DO NONE OF IT: no nudge is sent. A would-nudge
    #                     still counts as an attempt in the ledger, so the journal shows the rhythm a
    #                     live run would have had instead of a line every pass.
    # THE ENTRIES are the journal lines, kinds: nudge, nudge-killed (a nudge the waker had to stop
    # part-way), would-nudge and skip-unknown (a listing or a state the port could not give; id is ""
    # for the listing).
    #   -Silent           the fleet is silent (Update-HordeWakeSilence): every nudge of this pass is a probe
    # mail is session id -> its oldest unread mail's time, or $null, for the sessions whose state was
    # read; limited is session id -> its usage limit's text, for those with unread mail that are limited.
    #   -Only             ONE SESSION, AND NO OTHER: the pass is cut down to this id before any state is
    #                     read, so no other session can be looked at, decided on or nudged by it. It is
    #                     how a proof run is kept to the one session a person chose to have typed into
    #                     (core/WakeRun.ps1, PROOF). A session that is not in the listing - or a listing
    #                     that cannot be read - is one entry of kind proof-target-absent, and nobody is
    #                     nudged: the pass never falls back to "whoever is ready".
    param($Waker, [Parameter(Mandatory = $true)][datetime]$Now, $Settings = (Get-HordeWakeSettings), $Ledger = @{}, [switch]$Shadow, [switch]$Silent, [string]$Only = "")
    # held is session id -> why a session with unread mail is held for what it IS, not for what it is
    # doing: retired, or possibly so (Get-HordeWakeHold). For the tick to journal once.
    $mail = @{}
    $limited = @{}
    $held = @{}
    $entries = New-Object System.Collections.ArrayList
    $nextLedger = $Ledger
    $decisions = @()
    $unreadable = @{}
    $gaveUp = @()
    $listing = $null
    $warchief = ""
    if ($null -ne $Waker) {
        # A PASS BEGINS: the waker is told, so what it read of the fleet for the last pass is not reused
        # for this one and is read once for all of this one's questions (wakers/Port.ps1, Begin).
        Start-HordeWakePass -Waker $Waker
        $listing = Get-HordeWakeTargets -Waker $Waker
        if ($listing.state -cne "known") {
            [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "skip-unknown" -Outcome "unknown" -Reason ("the targets are unknown: " + $listing.reason)))
            if ($Only -cne "") { [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "proof-target-absent" -Id $Only -Outcome "absent" -Reason "the fleet's listing could not be read, so the one session this pass may nudge was not found: nobody is nudged")) }
        } else {
            $targets = @($listing.value)
            # WHO THE WARCHIEF IS, for whoever must tell it something (core/WakeTell.ps1): the one target
            # with that role. Two, or none, is nobody: one is never chosen over another.
            $chiefs = @($targets | Where-Object { $_.role -ceq "warchief" })
            if ($chiefs.Count -eq 1) { $warchief = $chiefs[0].id }
            # ONE SESSION, AND NO OTHER (-Only), cut here: before the first state is read.
            if ($Only -cne "") {
                $targets = @($targets | Where-Object { $_.id -ceq $Only })
                if ($targets.Count -ne 1) {
                    $targets = @()
                    [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "proof-target-absent" -Id $Only -Outcome "absent" -Reason "the one session this pass may nudge is not in the fleet's listing: nobody is nudged"))
                }
            }
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
            $decisions = @(Get-HordeWakeDecisions -Targets $targets -States $states -Ledger $Ledger -Now $Now -Settings $Settings -Confirmed $confirmed -CanLook:$canLook -Silent:$Silent)
            # THE LOOKS ARE COUNTED AS THEY ARE MADE, not by how many sessions have been looked at: the
            # bound must hold even if one session were looked at twice.
            $looks = 0
            while ($looks -lt [int]$Settings.maxConfirmsPerPass) {
                $toLook = @($decisions | Where-Object { $_.action -ceq "look" })
                if ($toLook.Count -eq 0) { break }
                foreach ($d in $toLook) {
                    if ($looks -ge [int]$Settings.maxConfirmsPerPass) { break }
                    $looks++
                    $confirmed[$d.id] = Get-HordeWakeState -Waker $Waker -Id $d.id -Full
                    if ($confirmed[$d.id].state -cne "known") { [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "skip-unknown" -Id $d.id -Outcome "unknown" -Reason "$($confirmed[$d.id].reason)")) }
                    else { $states[$d.id] = $confirmed[$d.id] }
                }
                $decisions = @(Get-HordeWakeDecisions -Targets $targets -States $states -Ledger $Ledger -Now $Now -Settings $Settings -Confirmed $confirmed -CanLook:$canLook -Silent:$Silent)
            }
            foreach ($d in $decisions) { if ($d.action -ceq "look") { $d.action = "wait"; $d.reason = "its box and its turn were not read this pass: the pass's looks were used up" } }
            foreach ($t in $targets) {
                $a = $states[$t.id]
                if ($a.state -cne "known") { continue }
                $mail[$t.id] = $a.value.oldestUnreadAt
                if ($a.value.unreadCount -gt 0 -and "$($t.retired)" -ceq "yes") { $held[$t.id] = "retired, with " + $a.value.unreadCount + " unread: a retired session is never nudged, so this mail waits for nobody. It is not counted, and nobody is told" }
                elseif ($a.value.unreadCount -gt 0 -and "$($t.retired)" -cne "no") { $held[$t.id] = "it could not be told whether this session is retired, and it has " + $a.value.unreadCount + " unread: it is not nudged while that is so" }
                $limit = Get-HordeWakeLimit -State $a.value -Now $Now
                if ($a.value.unreadCount -gt 0 -and $limit.kind -cne "none") { $limited[$t.id] = $limit.text }
            }
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
                    [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind $kind -Id $d.id -Outcome $rang.value.outcome -Reason $rang.value.reason -ElapsedMs (Get-HordeWakeEntryValue $rang.value "elapsedMs")))
                }
                else { $outcomes[$d.id] = "unknown"; [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "nudge" -Id $d.id -Outcome "unknown" -Reason "$($rang.reason)")) }
            }
            $nextLedger = Update-HordeWakeLedger -Ledger $Ledger -Decisions $decisions -Outcomes $outcomes -States $states -Now $Now -Settings $Settings -Silent:$Silent
            # THE CAP: a session nudged maxNudgesPerMail times for one mail is given up on, said once.
            $gave = Update-HordeWakeGaveUp -Ledger $nextLedger -Now $Now -Settings $Settings
            $nextLedger = $gave.ledger
            $gaveUp = @($gave.sessions)
            foreach ($e in @($gave.entries)) { [void]$entries.Add($e) }
        }
    }
    return [pscustomobject]@{ ledger = $nextLedger; entries = $entries.ToArray(); decisions = $decisions; unreadable = $unreadable; gaveUp = $gaveUp; listing = $listing; warchief = $warchief; mail = $mail; limited = $limited; held = $held }
}

# ---- the file: <home>\wake\ledger.json, or ledger-shadow.json for a shadow run ----
# Kept apart from everything above, which reads and writes none. Only the command's loop calls these.

function Save-HordeWakeLedger {
    # The ledger file, replaced whole: the back-off of every session being asked, so a watcher that is
    # restarted does not knock at once on a session it had been told to leave for five minutes.
    # -Shadow names the shadow run's own file (core/WakeFiles.ps1, Get-HordeWakeStateFile).
    param($Ledger, [switch]$Shadow, [string]$Mode = "", [string]$HordeHome = (Get-HordeHome))
    $sessions = New-Object System.Collections.ArrayList
    if ($null -ne $Ledger) {
        foreach ($id in @($Ledger.Keys | Sort-Object)) {
            $row = [ordered]@{ id = "$id"; attempts = [int]$Ledger[$id].attempts; lastAttemptAt = (ConvertTo-HordeWakeTimeText $Ledger[$id].lastAttemptAt); lastOutcome = "$($Ledger[$id].lastOutcome)" }
            $heldAt = Get-HordeWakeNothingAt $Ledger[$id]
            if ($null -ne $heldAt) { $row["nothingAt"] = ConvertTo-HordeWakeTimeText $heldAt }
            $mailAt = Get-HordeWakeEntryValue $Ledger[$id] "mailAt"
            if ($mailAt -is [datetime]) { $row["mailAt"] = ConvertTo-HordeWakeTimeText $mailAt }
            if ((Get-HordeWakeEntryValue $Ledger[$id] "gaveUp") -eq $true) { $row["gaveUp"] = $true }
            $probeAt = Get-HordeWakeEntryValue $Ledger[$id] "probeAt"
            if ($probeAt -is [datetime]) { $row["probeAt"] = ConvertTo-HordeWakeTimeText $probeAt }
            [void]$sessions.Add($row)
        }
    }
    $doc = [ordered]@{ schemaVersion = 1; sessions = $sessions.ToArray() }
    Write-HordeWakeFile -Path (Get-HordeWakeStateFile -Name "ledger" -Shadow:$Shadow -Mode $Mode -HordeHome $HordeHome) -Text (ConvertTo-Json -InputObject $doc -Depth 5 -Compress)
}

function Read-HordeWakeLedger {
    # What Save-HordeWakeLedger wrote: known { ledger }, absent when there is none, or unknown
    # when it cannot be read - the caller then starts from an empty ledger and says so.
    param([switch]$Shadow, [string]$Mode = "", [string]$HordeHome = (Get-HordeHome))
    $path = Get-HordeWakeStateFile -Name "ledger" -Shadow:$Shadow -Mode $Mode -HordeHome $HordeHome
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
            if ($null -ne $row.PSObject.Properties["probeAt"]) { $probeAt = ConvertFrom-HordeWakeTimeText $row.probeAt; if ($null -ne $probeAt) { $entry["probeAt"] = $probeAt } }
            $ledger["$($row.id)"] = [pscustomobject]$entry
        }
    } catch { return (New-HordeUnknown -Reason "the saved ledger holds an entry that is not one" -ErrorRecord $_) }
    return (New-HordeKnown -Value ([pscustomobject]@{ ledger = $ledger }))
}
