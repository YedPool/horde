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
. (Join-Path $PSScriptRoot "ReservedLabels.ps1")
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
        # At most this many such knocks for ONE unread mail of one session, whether its hour came or a
        # session of the fleet took mail (Get-HordeWakeHold, LIMITED WITH NO KNOWN END).
        maxLimitProbesPerMail = 6
        # For how long a session seen TAKING MAIL is evidence that sessions can take turns
        # (Get-HordeWakeLimit, LIMITED UNKNOWN).
        movingEvidenceSeconds = 600
        # THE PROBES OF A SILENT FLEET ARE STRETCHED AND CAPPED (Get-HordeWakeSilentProbeSeconds). One
        # session was asked every longest back-off step - 300 s, twelve lines an hour typed into a
        # fleet that cannot answer - for as long as nobody acknowledged mail, with no end (review of
        # PR 230). Now each probe waits silentProbeStretch times as long as the one before, up to
        # silentProbeMaxSeconds, and after maxSilentProbes of them only the very slow probe below is
        # sent: with these, at 5, 10, 20 and 40 minutes and then hourly, twelve probes in a little over
        # eight hours. The silence ends when any session acknowledges mail, which the watcher sees on
        # every pass whether it probes or not.
        # AT MOST ONE FREE KNOCK A SESSION IN THIS LONG, WHATEVER LIMIT IT IS FOR (Get-HordeWakeHold, A
        # LIMIT THAT IS OVER). The free knock skips the cap and the back-off, and was owed once per
        # limit - told apart by the time the limit ended. A waker whose past limitedUntil SHIFTS, a
        # new time on every reading, was then a new limit on every pass: a line typed every three
        # seconds, uncounted, for ever (review of PR 230). Inside the hour a knock under a limit that
        # is over is an ordinary attempt, counted and backed off.
        freeKnockSeconds = 3600
        silentProbeStretch = 2
        silentProbeMaxSeconds = 3600
        maxSilentProbes = 12
        # AFTER THE LAST OF THOSE, ONE VERY SLOW PROBE GOES ON: one session, in turn, every this long - six
        # hours. Stopping for good left mail waiting for ever in a fleet where no session takes a turn
        # by itself: the silence ends on an acknowledgement, and nothing was left that could bring one
        # about (review of PR 234). Four lines a day into a whole fleet is what finding out costs; and
        # when the twelfth has gone unanswered the warchief is told (Update-HordeWakeSilence). Counted
        # from the last probe of the silence, whichever it was, and that time is saved with the
        # silence, so a watcher started again does not probe at once (Get-HordeWakeDecisions).
        silentSlowProbeSeconds = 21600
    }
    foreach ($k in @($Overrides.Keys)) {
        if (-not $s.Contains("$k")) { throw ("'" + $k + "' is not a wake setting") }
        $s["$k"] = $Overrides[$k]
    }
    return [pscustomobject]$s
}

function Get-HordeWakeSilentProbeSeconds {
    # How long a silent fleet is left alone before its next probe, when -Probes have been sent since
    # it was found silent: the longest back-off step before the second, and silentProbeStretch
    # times as long before each one after, never more than silentProbeMaxSeconds (and never less
    # than that first step, whatever the settings say).
    param([int]$Probes = 0, $Settings = (Get-HordeWakeSettings))
    $steps = @($Settings.backoffSeconds)
    $first = 0
    if ($steps.Count -gt 0) { $first = [int]$steps[$steps.Count - 1] }
    $most = [System.Math]::Max([double]$first, [double]$Settings.silentProbeMaxSeconds)
    $wait = [double]$first
    for ($i = 1; $i -lt $Probes -and $wait -lt $most; $i++) { $wait = $wait * [System.Math]::Max(1.0, [double]$Settings.silentProbeStretch) }
    return [int][System.Math]::Min($wait, $most)
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
    # WHILE ANY MAIL IS HANDED OVER, THE ENTRY STANDS FOR ITS OWN MAIL, WHATEVER IS THE OLDEST UNREAD. Another
    # mail being the oldest unread was read as "the session took the one it was asked about" - but mail
    # handed over is out of the unread and not taken. A session nudged six times for one mail and given
    # up on had that mail handed over; a second mail arrived and was the oldest unread, so the entry was
    # rebuilt for it; when the first came back unread 600 s on, the entry was the second's, and the first
    # had a fresh budget - six more nudges and a second gave-up, and again at every new mail, for a session
    # that takes turns and never acknowledges (review of the before-live fixes). So while handedOverCount
    # is above 0 the entry is kept, with its mailAt, its count and its back-off, and a nudge sent then is
    # counted in it (the callers keep its mailAt, Get-HordeWakeEntryMailAt). The entry still goes only on
    # evidence the mail was taken: nothing unread AND nothing handed over (Update-HordeWakeLedger).
    param($Ledger, [string]$Id, $State = $null)
    if ($null -eq $Ledger -or -not $Ledger.ContainsKey($Id)) { return $null }
    $entry = $Ledger[$Id]
    $mailAt = Get-HordeWakeEntryValue $entry "mailAt"
    if ($null -ne $State -and (Get-HordeWakeHandedOver $State) -gt 0) { return $entry }
    if ($null -ne $State -and $mailAt -is [datetime] -and $State.oldestUnreadAt -is [datetime] -and $State.oldestUnreadAt -ne $mailAt) { return $null }
    return $entry
}

function Get-HordeWakeEntryMailAt {
    # The mail an entry written now is for: the mail of -Entry, the entry it replaces, when that names one,
    # and otherwise -State's oldest unread, or $null. An entry handed back by Get-HordeWakeLedgerEntry is
    # for the mail it names - the oldest unread, or the mail handed over that it was kept for - and a
    # nudge counted in it must not move it to another mail's time: that was the fresh budget again.
    param($Entry, $State)
    $mailAt = Get-HordeWakeEntryValue $Entry "mailAt"
    if ($mailAt -is [datetime]) { return $mailAt }
    $mailAt = Get-HordeWakeEntryValue $State "oldestUnreadAt"
    if ($mailAt -is [datetime]) { return $mailAt }
    return $null
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
    # probes is how many uncounted knocks a session LIMITED WITH NO KNOWN END has had for this mail
    # (Get-HordeWakeHold); it is taken from -Carry, the entry this one replaces, unless -Probes says.
    param([int]$Attempts, $LastAttemptAt, [string]$LastOutcome, $NothingAt = $null, $MailAt = $null, [bool]$GaveUp = $false, $ProbeAt = $null, $Carry = $null, [int]$Probes = -1, $FreeFor = $null, $FreeAt = $null)
    $row = [ordered]@{ attempts = $Attempts; lastAttemptAt = $LastAttemptAt; lastOutcome = $LastOutcome }
    $probed = $Probes
    if ($probed -lt 0) { $probed = 0; $was = Get-HordeWakeEntryValue $Carry "probes"; if ($was -is [int] -or $was -is [long]) { $probed = [int]$was } }
    if ($probed -gt 0) { $row["probes"] = $probed }
    # freeFor is the limit - the time it ended - whose one free knock this session has had; carried too.
    $free = $FreeFor
    if ($free -isnot [datetime]) { $free = Get-HordeWakeEntryValue $Carry "freeFor" }
    if ($free -is [datetime]) { $row["freeFor"] = $free }
    # freeAt is WHEN the session last had a free knock, for whichever limit; carried too.
    $freeWhen = $FreeAt
    if ($freeWhen -isnot [datetime]) { $freeWhen = Get-HordeWakeEntryValue $Carry "freeAt" }
    if ($freeWhen -is [datetime]) { $row["freeAt"] = $freeWhen }
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
    #   none   it is not limited, or its waker has no way to tell at all
    #   over   THE LIMIT IS OVER: the waker still says limited and the time it gives has passed. The
    #          fleet's command keeps a past reset in its row, so the comparison with now is made
    #          here. The session is knocked for ONCE, uncounted, in its fair turn, and under the
    #          normal rules from its next attempt on
    #   until  limited, and the limit ends at a known time still ahead: it is not nudged at all
    #   open   limited, and nobody knows until when - the waker gave no time (one it could not read,
    #          a clock-change hour, a dated weekly reset): Get-HordeWakeHold, LIMITED WITH NO KNOWN END
    # WHY (measured 2026-10-13, 04:36 to 05:55 UTC): the account's usage limit stopped every session
    # for about 80 minutes. Every knock in that window was typed and submitted, and no session could
    # answer. The six nudges a mail is allowed were spent in about 13 minutes, so the watcher had
    # given up on everybody and was silent at the moment the limit reset - nobody was woken after it.
    # A knock at a session that cannot answer proves nothing about the session and must cost nothing.
    # LIMITED UNKNOWN - the waker can tell, and for this session could not (wakers/Port.ps1) - IS NOT
    # "NOT LIMITED": it waits, exactly as a limit with no known end does (open), uncounted. BUT A SESSION
    # MUST NOT BE SILENCED FOR EVER BY A TRANSCRIPT NOBODY CAN READ - on the live fleet 1 of 23 reachable
    # sessions reads unknown, because its last transcript entry is longer than the tail the fleet's
    # command reads - so it is released by evidence that sessions CAN take turns: ANOTHER session
    # ACKNOWLEDGED MAIL within the last movingEvidenceSeconds. A session acknowledges mail only by
    # taking a turn - by reading it, or by its own side finding the mail's id in its transcript at
    # the end of a turn - and neither happens after a turn that ended in a usage-limit error. A limit
    # an account shares stops every session; one of them acknowledging mail says there is none now.
    # Then unknown is read as not limited and the normal rules hold.
    # WHAT IS NOT EVIDENCE, each of which was used or proposed once:
    #   - a nudge answered "woken": that is the waker's word that it typed, and in the incident above
    #     every knock was answered woken by sessions that could do nothing;
    #   - AN INBOX THAT CHANGED - a session's oldest unread mail becoming another, or none. The fleet's
    #     own repair moves a mailbox to a new session id after a resume, with no turn taken by
    #     anybody (safety review of PR 220). Nothing here reads an inbox as evidence any more;
    #   - the judged session's OWN acknowledgement: it is the one whose state could not be read.
    #   - AN ACKNOWLEDGEMENT THAT IS MERELY RECENT. Any time inside the window was taken, so a restore
    #     that stamps every session's acknowledgement to now, read by a watcher started just after it,
    #     released every session whose limit nobody could read for ten minutes (review of PR 234). The
    #     evidence is an acknowledgement SEEN TO INCREASE between two readings - the same rule that ends
    #     a silence (Update-HordeWakeAcksRose) - and the first reading after a start compares with nothing.
    # -Acks is session id -> the acknowledgement time at which it was seen to increase, for the sessions
    # the pass could reach and whose acknowledgements its waker could read (Invoke-HordeWakePass hands in
    # only those). A waker that cannot read them gives none, and then there is no evidence. THE EDGE: an acknowledgement exactly
    # movingEvidenceSeconds old still counts, one second older does not - the window is the last
    # 600 s, both ends in - and one dated in the future is no evidence at all.
    # THIS IS ONLY EVER ASKED OF A SESSION THAT IS REACHABLE (Get-HordeWakeHold asks reachable first):
    # the fleet says limited unknown for every row it cannot reach.
    param($State, [Parameter(Mandatory = $true)][datetime]$Now, $Settings = $null, $Acks = $null)
    $word = "$(Get-HordeWakeEntryValue $State "limited")"
    if ($word -ceq "unknown") {
        $window = 0
        if ($null -ne $Settings) { $window = [double]$Settings.movingEvidenceSeconds }
        # Never the judged session's own (the header).
        $latest = $null
        $self = "$(Get-HordeWakeEntryValue $State "id")"
        if ($Acks -is [System.Collections.IDictionary]) {
            foreach ($who in @($Acks.Keys)) {
                if ("$who" -ceq $self) { continue }
                $when = $Acks[$who]
                if ($when -is [datetime] -and $when -le $Now -and ($null -eq $latest -or $when -gt $latest)) { $latest = $when }
            }
        }
        if ($latest -is [datetime] -and ($Now - $latest).TotalSeconds -le $window) { return [pscustomobject]@{ kind = "none"; text = "" } }
        return [pscustomobject]@{ kind = "open"; text = "usage limit unknown: its waker could not tell whether it is limited" }
    }
    if ($word -cne "yes") { return [pscustomobject]@{ kind = "none"; text = "" } }
    $until = Get-HordeWakeEntryValue $State "limitedUntil"
    # THE LIMIT IS OVER: kind over, with the time it ended. Not "none": a session whose limit has just
    # ended is owed ONE knock that costs it nothing (Get-HordeWakeHold, A LIMIT THAT IS OVER).
    if ($until -is [datetime] -and $until -le $Now) { return [pscustomobject]@{ kind = "over"; text = ""; until = $until } }
    if ($until -is [datetime]) { return [pscustomobject]@{ kind = "until"; text = ("usage limit until " + $until.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)) } }
    return [pscustomobject]@{ kind = "open"; text = "usage limit, end unknown" }
}

function Get-HordeWakeHandedOver {
    # How much mail a state says was handed over to the session and not yet acknowledged: a whole
    # number, and 0 when the waker cannot say (the port's $null) - what is not known is not said.
    param($State)
    $n = Get-HordeWakeEntryValue $State "handedOverCount"
    if (($n -is [int] -or $n -is [long]) -and $n -gt 0) { return [long]$n }
    return [long]0
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
    #   THE FLEET IS SILENT (-Silent; Update-HordeWakeSilence): ONE session of the fleet is probed per
    #   longest step of the back-off, in turn (Get-HordeWakeDecisions), and the first to take mail
    #   ends it.
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
    param($Target, $StateAnswer, $Entry, [datetime]$Now, $Settings, [switch]$CanLook, [switch]$Silent, $Acks = $null, [switch]$NoProbe, [string]$Self = "", $FreeAt = $null, $Asleep = $null, [string]$AsleepUnknown = "")
    $retired = "$(Get-HordeWakeEntryValue $Target "retired")"
    if ($retired -ceq "yes") { return [pscustomobject]@{ action = "skip"; reason = "retired: a retired session is never nudged" } }
    if ($retired -cne "no") { return [pscustomobject]@{ action = "wait"; reason = "retired is unknown: a session that may be retired is not nudged" } }
    # A SENDER'S NAME IS NEVER A SESSION TO NUDGE, AND NEITHER IS THE WATCHER'S OWN SESSION. Two labels are
    # reserved for mail that is from no session - RS, the restore source's, and WW, this watcher's own
    # tells (core/ReservedLabels.ps1) - and nothing in the wake path ever asked about them (safety
    # review of PR 220): a session that came to wear one would be typed into as though the watcher
    # were answering itself. And a watcher started from inside a session would nudge that session
    # for its own unread mail, typing into the very box its own output goes to. Both are skip, in
    # every mode, whatever else is true of the session. -Self is that session's id, or "" when the
    # watcher was started from no session or cannot tell (core/WakeRun.ps1, New-HordeWakeRun).
    $worn = "$(Get-HordeWakeEntryValue $Target "label")"
    if (Test-HordeLabelReserved $worn) { return [pscustomobject]@{ action = "skip"; reason = ("its label, " + $worn + ", is reserved for a sender that is no session: it is never nudged") } }
    if ($Self -cne "" -and "$(Get-HordeWakeEntryValue $Target "id")" -ceq $Self) { return [pscustomobject]@{ action = "skip"; reason = "it is the session this watcher was started from: a watcher never nudges itself" } }
    # A SESSION ASLEEP IN A HIBERNATION IS NEVER KNOCKED (fleet/Asleep.ps1 says why): skip, like a retired
    # one, while its mail queues for its wake. -Asleep is session id -> where and since when. When which
    # sessions sleep cannot be told (-AsleepUnknown), nobody is knocked - wait - because the record that
    # could not be read may be the one that says this session sleeps, and its pane holds a shell.
    if ($AsleepUnknown -cne "") { return [pscustomobject]@{ action = "wait"; reason = ("which sessions are asleep in a hibernation cannot be told, so none is knocked: " + $AsleepUnknown) } }
    if ($null -ne $Asleep -and $Asleep.ContainsKey("$(Get-HordeWakeEntryValue $Target "id")")) { return [pscustomobject]@{ action = "skip"; reason = ("" + $Asleep["$(Get-HordeWakeEntryValue $Target "id")"] + ": a hibernated session is never knocked; its mail waits for its wake") } }
    if ($null -eq $StateAnswer -or "$($StateAnswer.state)" -cne "known") {
        $why = "nothing answered for it"
        if ($null -ne $StateAnswer) { $why = "$($StateAnswer.reason)" }
        return [pscustomobject]@{ action = "wait"; reason = ("its state is unknown: " + $why) }
    }
    $s = $StateAnswer.value
    # ONLY UNREAD MAIL IS NUDGED FOR. Mail HANDED OVER to a session - put before it by its own side and
    # not yet acknowledged - sits in its inbox and is not unread: the session has it. The fleet's command
    # holds such mail for a time and counts it unread again itself if it is never acknowledged; that
    # hold is the fleet's and is NOT worked out again here. Until then there is nothing to knock for,
    # and the reason says which of the two it was, so a reader sees why a session with mail in its inbox
    # was not nudged (Invoke-HordeWakePass journals it once, as held).
    if ($s.unreadCount -le 0) {
        $handed = Get-HordeWakeHandedOver $s
        if ($handed -gt 0) { return [pscustomobject]@{ action = "skip"; reason = ("no unread mail: " + $handed + " handed over and not yet acknowledged") } }
        return [pscustomobject]@{ action = "skip"; reason = "no unread mail" }
    }
    # REACHABLE IS DECIDED BEFORE THE LIMIT IS ASKED: a session that cannot be reached is held for that,
    # whatever is known or not known of its limit, and whatever evidence there is that others move.
    if ("$($Target.reachable)" -cne "yes") { return [pscustomobject]@{ action = "wait"; reason = ("reachable is " + $Target.reachable) } }
    # TWO RUNNING COPIES OF ONE SESSION ARE NEVER NUDGED (T-0116): the fleet's own nudge refuses such a
    # target (target-instance-ambiguous), and its idle is unknown, so it waited all the same - but it
    # waited without a word. This makes the wait explicit whatever idle says; the pass says it once.
    if ("$(Get-HordeWakeEntryValue $Target "duplicate")" -ceq "yes") { return [pscustomobject]@{ action = "wait"; reason = "it has more than one running copy: it is not nudged while that is so" } }
    $limit = Get-HordeWakeLimit -State $s -Now $Now -Settings $Settings -Acks $Acks
    if ($limit.kind -ceq "until") { return [pscustomobject]@{ action = "wait"; reason = $limit.text } }
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
    # A LIMIT THAT IS OVER (Get-HordeWakeLimit, over). It was treated as plain "not limited": every nudge
    # counted, and a session that had been knocked for through its limit - by a waker that did not
    # say, or before the limit showed - was already at its cap, or reached it at once, and was given
    # up on at the moment it could first answer (safety review of PR 220). So the FIRST knock after a
    # limit ends is free: it ignores the cap and the back-off, and is not counted
    # (Update-HordeWakeLedger records which limit it was for, freeFor). From the next attempt the
    # normal rules hold, the first step of the back-off counted from that free knock.
    # ONE PER LIMIT, AND NEVER MORE THAN ONE AN HOUR PER SESSION (below, freeKnockSeconds).
    $freeFor = Get-HordeWakeEntryValue $Entry "freeFor"
    $free = ($limit.kind -ceq "over" -and -not ($freeFor -is [datetime] -and $freeFor -eq $limit.until))
    # AND AT MOST ONE IN freeKnockSeconds, WHATEVER THE LIMIT (Get-HordeWakeSettings says why). -FreeAt is
    # when this session last had one, read from its ledger row AS IT STANDS - not from the entry for
    # its oldest mail, which is nothing when another mail has become the oldest: the bound is on the
    # session. One dated in the future counts as just sent.
    if ($free -and $FreeAt -is [datetime] -and ($Now - $FreeAt).TotalSeconds -lt [double]$Settings.freeKnockSeconds) { $free = $false }
    $probe = ($Silent -or $limit.kind -ceq "open")
    # A PASS CUT DOWN TO ONE SESSION SENDS NO PROBE (-NoProbe; Invoke-HordeWakePass sets it with -Only).
    # A probe is sent on a timer read from the ledger - an hour since the last, five minutes in a
    # silent fleet - and a proof run reads a ledger it did not write and that may be hours old: a
    # second proof an hour after the first would have typed into a session that is limited, because
    # its hour was up. A proof is there to show a nudge of a session that can take one; a session
    # that is limited, or whose limit nobody could read, waits, and the person is told why.
    if ($probe -and $NoProbe) { return [pscustomobject]@{ action = "wait"; reason = ($(if ($limit.kind -ceq "open") { $limit.text } else { "the fleet is silent" }) + ": a pass given one session sends no probe") } }
    if ($probe) {
        $why = "the fleet is silent"
        if ($limit.kind -ceq "open") { $why = $limit.text }
        $steps = @($Settings.backoffSeconds)
        $longest = 0
        if ($steps.Count -gt 0) { $longest = [int]$steps[$steps.Count - 1] }
        $last = Get-HordeWakeEntryValue $Entry "probeAt"
        if ($limit.kind -ceq "open") {
            # AND IT IS CAPPED. An hourly knock, and one more each time any session takes mail, was a
            # line typed into a session that cannot answer for as long as its limit lasted - days, for a
            # weekly one - with nothing ever said (safety review of PR 220). After
            # maxLimitProbesPerMail of them for one mail the watcher gives up on it: one gave-up entry
            # and one tell (Update-HordeWakeGaveUp), and nothing more until its oldest unread mail
            # becomes another or its waker stops saying it is limited.
            $knocks = Get-HordeWakeEntryValue $Entry "probes"
            if (($knocks -is [int] -or $knocks -is [long]) -and $knocks -ge [int]$Settings.maxLimitProbesPerMail) { return [pscustomobject]@{ action = "wait"; reason = ($why + ": gave up after " + $knocks + " knocks while it was limited; nothing more is tried until its mail changes or it is no longer limited") } }
            $every = [int]$Settings.limitedUnknownProbeSeconds
            if ($last -isnot [datetime]) { return [pscustomobject]@{ action = "wait"; reason = ($why + ": it waits for a session of the fleet to take mail, or " + $every + " s") } }
            if (($Now - $last).TotalSeconds -lt $every) { return [pscustomobject]@{ action = "wait"; reason = ($why + ": it waits for a session of the fleet to take mail, or " + [int][System.Math]::Ceiling($every - ($Now - $last).TotalSeconds) + " s more") } }
            $last = $null
        }
        if ($last -isnot [datetime] -and $null -ne $Entry -and $limit.kind -cne "open") { $last = $Entry.lastAttemptAt }
        if ($last -is [datetime] -and ($Now - $last).TotalSeconds -lt $longest) { return [pscustomobject]@{ action = "wait"; reason = ($why + ": it is asked only every " + $longest + " s, and no attempt is counted; " + [int][System.Math]::Ceiling($longest - ($Now - $last).TotalSeconds) + " s left") } }
    }
    if (-not $probe -and -not $free -and $null -ne $Entry -and [int]$Entry.attempts -ge [int]$Settings.maxNudgesPerMail) { return [pscustomobject]@{ action = "wait"; reason = ("gave up after " + $Entry.attempts + " nudges for this mail; nothing more is tried until it is taken or another mail becomes the oldest") } }
    if (-not $probe -and -not $free -and $null -ne $Entry) {
        # After a free knock the wait is at least the first step, though no attempt was counted for it.
        $steps = [int]$Entry.attempts
        if ($freeFor -is [datetime] -and $steps -lt 1) { $steps = 1 }
        $wait = Get-HordeWakeBackoffSeconds -Attempts $steps -Settings $Settings
        $since = ($Now - $Entry.lastAttemptAt).TotalSeconds
        if ($since -lt $wait) { return [pscustomobject]@{ action = "wait"; reason = ("back-off: " + [int][System.Math]::Ceiling($wait - $since) + " s left of " + $wait + " after attempt " + $Entry.attempts) } }
    }
    $unseen = ("$($s.midTurn)" -ceq "unknown" -or "$($s.boxEmpty)" -ceq "unknown")
    if ($CanLook -and $unseen -and "$($s.midTurn)" -cne "yes" -and "$($s.boxEmpty)" -cne "no") { return [pscustomobject]@{ action = "look"; reason = "its box and its turn have not been read" } }
    if ("$($s.midTurn)" -cne "no") { return [pscustomobject]@{ action = "wait"; reason = ("midTurn is " + $s.midTurn) } }
    if ("$($s.boxEmpty)" -cne "yes") { return [pscustomobject]@{ action = "wait"; reason = ("boxEmpty is " + $s.boxEmpty) } }
    return [pscustomobject]@{ action = "ready"; reason = ""; free = $free }
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
    #   -SilentProbes  how many probes were sent since it was found silent
    #   -SilentProbeAt when the last of them was sent, as the silence keeps it, or $null
    param($Targets, $States, $Ledger, [Parameter(Mandatory = $true)][datetime]$Now, $Settings = (Get-HordeWakeSettings), $Confirmed = @{}, [switch]$CanLook, [switch]$Silent, [int]$SilentProbes = 0, $Acks = $null, [switch]$NoProbe, [string]$Self = "", $SilentProbeAt = $null, $Asleep = $null, [string]$AsleepUnknown = "")
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
        $hold = Get-HordeWakeHold -Target $t -StateAnswer $answer -Entry $entry -Now $Now -Settings $Settings -CanLook:($CanLook -and -not $looked) -Silent:$Silent -Acks $Acks -NoProbe:$NoProbe -Self $Self -Asleep $Asleep -AsleepUnknown $AsleepUnknown -FreeAt $(if ($null -ne $Ledger -and $Ledger.ContainsKey($id)) { Get-HordeWakeEntryValue $Ledger[$id] "freeAt" } else { $null })
        $row = [pscustomobject]@{ id = $id; action = $hold.action; reason = $hold.reason; attempts = 0; nothing = 0; rank = $roles.Count; oldest = [datetime]::MaxValue; probed = [long]0; free = ((Get-HordeWakeEntryValue $hold "free") -eq $true); between = ("$(Get-HordeWakeEntryValue $stateNow "betweenTurns")" -ceq "yes") }
        $lastProbe = Get-HordeWakeEntryValue $entry "probeAt"
        if ($lastProbe -is [datetime]) { $row.probed = $lastProbe.Ticks }
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
    # A SILENT FLEET IS ASKED BY ONE PROBE AT A TIME, FOR THE WHOLE FLEET. Each session was probed at the
    # longest step by itself, so a fleet of twenty that could not answer had twenty lines typed into
    # it every five minutes - silence in name only (safety review of PR 220). The question a probe
    # asks is "can anybody answer yet", and one session can say that as well as twenty: so ONE session
    # is probed per longest step, counted from the last probe of ANY session, and it is the one that
    # was probed longest ago - the probe goes round. The first to take mail ends the silence, and
    # then everybody is knocked for (Update-HordeWakeSilence).
    # AND THAT ONE PROBE IS STRETCHED AND CAPPED (Get-HordeWakeSettings, silentProbeStretch): -SilentProbes
    # is how many were sent since the fleet was found silent (Update-HordeWakeSilence counts them).
    if ($Silent) {
        $longest = Get-HordeWakeSilentProbeSeconds -Probes $SilentProbes -Settings $Settings
        $lastOfAny = $null
        if ($null -ne $Ledger) { foreach ($e in @($Ledger.Values)) { $p = Get-HordeWakeEntryValue $e "probeAt"; if ($p -is [datetime] -and $p -le $Now -and ($null -eq $lastOfAny -or $p -gt $lastOfAny)) { $lastOfAny = $p } } }
        # AFTER THE LAST OF THEM, ONE VERY SLOW PROBE (Get-HordeWakeSettings, silentSlowProbeSeconds): one
        # session, in the same turn, every six hours, counted from the last probe of the silence. That
        # time is -SilentProbeAt, the silence's own (Update-HordeWakeSilence keeps it and it is saved
        # with it), or the ledger's latest probe, whichever is later: the ledger alone loses an entry
        # whose mail is taken, and the silence alone was not saved by a watcher before this one. When
        # neither knows one - a silence saved by such a watcher with no ledger beside it - the probe
        # is sent: waiting for a time nobody kept would be the silence that never ends again.
        # held is why nobody is probed on this pass, or $null when ONE session is.
        $held = $null
        if ($SilentProbes -ge [int]$Settings.maxSilentProbes) {
            $slow = [double]$Settings.silentSlowProbeSeconds
            $lastSlow = $lastOfAny
            if ($SilentProbeAt -is [datetime] -and $SilentProbeAt -le $Now -and ($lastSlow -isnot [datetime] -or $SilentProbeAt -gt $lastSlow)) { $lastSlow = $SilentProbeAt }
            if ($lastSlow -is [datetime] -and ($Now - $lastSlow).TotalSeconds -lt $slow) {
                $held = ("the fleet is silent: " + $SilentProbes + " probes went unanswered, and now one session of the fleet is asked every " + [int]$slow + " s; " + [int][System.Math]::Ceiling($slow - ($Now - $lastSlow).TotalSeconds) + " s are left. It ends when a session acknowledges mail")
            }
        }
        elseif ($lastOfAny -is [datetime] -and ($Now - $lastOfAny).TotalSeconds -lt $longest) {
            $held = ("the fleet is silent: one session of the fleet is asked every " + $longest + " s, and " + [int][System.Math]::Ceiling($longest - ($Now - $lastOfAny).TotalSeconds) + " s are left")
        }
        if ($null -ne $held) {
            foreach ($r in $ready) { $r.action = "wait"; $r.reason = $held }
            $ready = @()
        } else {
            $ready = @($ready | Sort-Object -Property probed, nothing, attempts, rank, oldest, id)
            $allowed = [System.Math]::Min($allowed, 1)
        }
    }
    for ($i = 0; $i -lt $ready.Count; $i++) {
        if ($i -ge $allowed) { $ready[$i].action = "wait"; $ready[$i].reason = "rate limit" }
        elseif ($ready[$i].action -ceq "ready") {
            # WHICH RULE SAID IDLE IS SAID WITH THE DECISION. A session is ordinarily idle because its own
            # status says so. One whose status says busy only for background work, its turn having
            # ended, is idle BY THE BETWEEN-TURNS RULE (wakers/Port.ps1, betweenTurns): a nudge it gets
            # was let through by that rule, and a reader of the journal must be able to see it was -
            # it is the nudge to look at first if a session is ever typed into mid-work. The box is
            # still read empty by a look at the session itself before any nudge, rule or no rule
            # (Get-HordeWakeHold): the rule says idle, never "the box is empty".
            $ready[$i].action = "nudge"
            $ready[$i].reason = "unread mail, idle, empty box"
            if ($ready[$i].between) { $ready[$i].reason = "unread mail, idle by the between-turns rule (between-turns-background-work), empty box" }
        }
    }
    # free says the nudge decided on is a free knock: the pass marks it so when it counts it beforehand.
    return @($rows | ForEach-Object { [pscustomobject]@{ id = $_.id; action = $_.action; reason = $_.reason; free = ($_.free -eq $true) } })
}

function Set-HordeWakeLedgerAsked {
    # -Ledger with ONE ATTEMPT COUNTED for -Id at -Now, its outcome not yet known, as a new table.
    # Invoke-HordeWakePass writes this BEFORE it asks the waker to nudge (there, A NUDGE IS COUNTED BEFORE
    # IT IS ASKED FOR); Update-HordeWakeLedger then works the pass out properly from the ledger as
    # it was, and this stands only if that never happens. -State is the session's state now: the
    # attempt is for the mail that is its oldest unread, as every entry is.
    # -Free: the nudge is a free knock (Get-HordeWakeHold). It is counted as an attempt all the same -
    # one nudge too few, never one too many - and when it was sent is kept, so the hour's bound on
    # free knocks holds over a pass that failed.
    param($Ledger, [Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)][datetime]$Now, $State = $null, [switch]$Free)
    $next = @{}
    if ($null -ne $Ledger) { foreach ($k in @($Ledger.Keys)) { $next["$k"] = $Ledger[$k] } }
    $had = Get-HordeWakeLedgerEntry -Ledger $next -Id $Id -State $State
    $count = 1
    if ($null -ne $had) { $count = [int]$had.attempts + 1 }
    $mailAt = Get-HordeWakeEntryMailAt -Entry $had -State $State
    $freeAt = $null
    if ($next.ContainsKey($Id)) { $freeAt = Get-HordeWakeEntryValue $next[$Id] "freeAt" }
    if ($Free) { $freeAt = $Now }
    $next[$Id] = New-HordeWakeLedgerRow -Attempts $count -LastAttemptAt $Now -LastOutcome "unknown" -MailAt $mailAt -GaveUp ((Get-HordeWakeEntryValue $had "gaveUp") -eq $true) -ProbeAt (Get-HordeWakeEntryValue $had "probeAt") -Carry $had -FreeAt $freeAt
    return $next
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
    # unread mail, and none handed over to it and not yet acknowledged (below, NOTHING UNREAD IS "MAIL
    # TAKEN" ONLY WHEN...), leaves the ledger, so its next message is knocked for at once.
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
    #   -Open       the ids of the sessions held this pass for a limit with no known end (or a limit
    #               nobody could read): each is noted, below, the first time it is seen so
    #   -Acks       session id -> when it last acknowledged mail (Get-HordeWakeLimit)
    #   -Listed     the ids of every session in the listing, WHEN THE LISTING WAS READ WHOLE; $null when
    #               it was not, or the caller has none. Only against it is a session called gone (below)
    param($Ledger, $Decisions, $Outcomes, $States, [Parameter(Mandatory = $true)][datetime]$Now, $Settings = (Get-HordeWakeSettings), [switch]$Silent, $Open = @(), $Acks = $null, $Listed = $null)
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
        $had = Get-HordeWakeLedgerEntry -Ledger $next -Id $id -State $stateNow
        $mailAt = Get-HordeWakeEntryMailAt -Entry $had -State $stateNow
        if ("$($Outcomes[$id])" -ceq "nothing") {
            $kept = New-HordeWakeLedgerRow -Attempts 0 -LastAttemptAt $Now -LastOutcome "nothing" -NothingAt $Now -MailAt $mailAt
            if ($null -ne $had) { $kept = New-HordeWakeLedgerRow -Attempts ([int]$had.attempts) -LastAttemptAt $had.lastAttemptAt -LastOutcome "$($had.lastOutcome)" -NothingAt $Now -MailAt $mailAt -GaveUp ((Get-HordeWakeEntryValue $had "gaveUp") -eq $true) -ProbeAt (Get-HordeWakeEntryValue $had "probeAt") -Carry $had }
            $next[$id] = $kept
            continue
        }
        $limitNow = Get-HordeWakeLimit -State $stateNow -Now $Now -Settings $Settings -Acks $Acks
        if ($Silent -or $limitNow.kind -ceq "open") {
            # A KNOCK AT A SESSION LIMITED WITH NO KNOWN END IS COUNTED AS A PROBE (the cap on those is in
            # Get-HordeWakeHold); one sent only because the fleet is silent is not: that has its own bound.
            $knocks = 0
            $was = Get-HordeWakeEntryValue $had "probes"
            if ($was -is [int] -or $was -is [long]) { $knocks = [int]$was }
            if ($limitNow.kind -ceq "open") { $knocks++ }
            $probed = New-HordeWakeLedgerRow -Attempts 0 -LastAttemptAt $Now -LastOutcome "$($Outcomes[$id])" -MailAt $mailAt -ProbeAt $Now -Probes $knocks
            if ($null -ne $had) { $probed = New-HordeWakeLedgerRow -Attempts ([int]$had.attempts) -LastAttemptAt $had.lastAttemptAt -LastOutcome "$($Outcomes[$id])" -MailAt $mailAt -GaveUp ((Get-HordeWakeEntryValue $had "gaveUp") -eq $true) -ProbeAt $Now -Probes $knocks }
            $next[$id] = $probed
            continue
        }
        # THE ONE FREE KNOCK AFTER A LIMIT ENDED (Get-HordeWakeHold): not counted, and marked with the limit
        # it was for, so a second knock under the same past limit is an ordinary attempt.
        $wasFree = Get-HordeWakeEntryValue $had "freeFor"
        # ...and bounded as the decision bounded it (Get-HordeWakeHold): by when this session last had one.
        $freeWas = $null
        if ($null -ne $Ledger -and $Ledger.ContainsKey($id)) { $freeWas = Get-HordeWakeEntryValue $Ledger[$id] "freeAt" }
        $recent = ($freeWas -is [datetime] -and ($Now - $freeWas).TotalSeconds -lt [double]$Settings.freeKnockSeconds)
        if ($limitNow.kind -ceq "over" -and -not ($wasFree -is [datetime] -and $wasFree -eq $limitNow.until) -and -not $recent) {
            $kept = 0
            if ($null -ne $had) { $kept = [int]$had.attempts }
            $next[$id] = New-HordeWakeLedgerRow -Attempts $kept -LastAttemptAt $Now -LastOutcome "$($Outcomes[$id])" -MailAt $mailAt -GaveUp ($null -ne $had -and (Get-HordeWakeEntryValue $had "gaveUp") -eq $true -and $kept -ge [int]$Settings.maxNudgesPerMail) -Probes 0 -FreeFor $limitNow.until -FreeAt $Now
            continue
        }
        $before = 0
        if ($null -ne $had) { $before = [int]$had.attempts }
        $count = $before + 1
        if ("$($Outcomes[$id])" -ceq "killed") { $count = [System.Math]::Max($count, @($Settings.backoffSeconds).Count) }
        # gaveUp is carried only when it was said for the ATTEMPTS: one said for the probes of a limited
        # session (Update-HordeWakeGaveUp) is about a limit that is over by the time an attempt is
        # counted, and must not swallow the line the cap on attempts would say later.
        # And the knocks it had while limited are not carried into a counted attempt: the limit is over.
        $stood = ($null -ne $had -and (Get-HordeWakeEntryValue $had "gaveUp") -eq $true -and [int]$had.attempts -ge [int]$Settings.maxNudgesPerMail)
        $next[$id] = New-HordeWakeLedgerRow -Attempts $count -LastAttemptAt $Now -LastOutcome "$($Outcomes[$id])" -MailAt $mailAt -GaveUp $stood -Probes 0 -FreeFor (Get-HordeWakeEntryValue $had "freeFor")
    }
    # FIRST SEEN LIMITED WITH NO KNOWN END: stamped now, as the entry's probeAt, which is what its hour
    # is counted from (Get-HordeWakeHold). An entry it already has keeps its count.
    if ($null -ne $States) {
        foreach ($id in @($Open)) {
            if (-not $States.ContainsKey("$id")) { continue }
            $a = $States["$id"]
            if ($null -eq $a -or "$($a.state)" -cne "known" -or $a.value.unreadCount -le 0) { continue }
            $had = Get-HordeWakeLedgerEntry -Ledger $next -Id "$id" -State $a.value
            if ((Get-HordeWakeEntryValue $had "probeAt") -is [datetime]) { continue }
            $seen = New-HordeWakeLedgerRow -Attempts 0 -LastAttemptAt $Now -LastOutcome "limited" -MailAt $a.value.oldestUnreadAt -ProbeAt $Now
            if ($null -ne $had) { $seen = New-HordeWakeLedgerRow -Attempts ([int]$had.attempts) -LastAttemptAt $had.lastAttemptAt -LastOutcome "$($had.lastOutcome)" -NothingAt (Get-HordeWakeNothingAt $had) -MailAt (Get-HordeWakeEntryMailAt -Entry $had -State $a.value) -GaveUp ((Get-HordeWakeEntryValue $had "gaveUp") -eq $true) -ProbeAt $Now -Carry $had }
            $next["$id"] = $seen
        }
    }
    foreach ($id in @($next.Keys)) {
        # NOTHING UNREAD IS "MAIL TAKEN" ONLY WHEN NOTHING IS HANDED OVER EITHER. Mail handed over to a session
        # is out of unreadCount and is not acknowledged; the fleet's command counts it unread again when
        # its hold runs out. "Nothing unread" alone was read as taken, and the entry dropped: nudge, the
        # hook hands the mail over, the entry goes, nobody acknowledges, ten minutes on the mail is
        # unread again to a session with no entry - a fresh budget - and it is nudged again. Six nudges
        # an hour for one session, never capped and never given up on (review of PR 234). So the entry
        # stands while anything is handed over, and goes when the state shows nothing unread AND
        # nothing handed over - which is how an acknowledgement shows here.
        # HOW THE ENTRY KNOWS ITS MAIL AGAIN: by mailAt, as always. That is the mail's own time, and the
        # command reports a hand-over that ran out under that same time (oldestUnreadAt), so the entry
        # for it applies again, count and all (Get-HordeWakeLedgerEntry; no oldest unread, as during the
        # hand-over, is no other mail). oldestHandedOverAt is NOT used to know it by: it is when the
        # hook handed the mail over, a new time at every hand-over, and no time of the mail's.
        # A waker that cannot say what was handed over (the port's $null) is read as none, as before.
        $taken = $false
        if ($null -ne $States -and $States.ContainsKey($id)) { $a = $States[$id]; $taken = ("$($a.state)" -ceq "known" -and $a.value.unreadCount -le 0 -and (Get-HordeWakeHandedOver $a.value) -eq 0) }
        $old = (($Now - $next[$id].lastAttemptAt).TotalSeconds -gt $script:HordeWakeLedgerKeepSeconds)
        # A SESSION GIVEN UP ON IS FORGOTTEN ONLY ON EVIDENCE, NEVER BY AGE ALONE AND NEVER FOR WHAT A PASS
        # DID NOT READ. Entries were dropped after a day whatever they said, so a session that never
        # takes its mail got its six nudges again every day (safety review of PR 220). The first
        # mending kept a gave-up entry only when that session's state had been READ in this pass and
        # showed the same mail - so a proof pass, which reads ONE session, deleted every other session's
        # gave-up entry older than a day, out of the ledger it shares with the live watcher; and a
        # state that passed through unknown did the same in a live run (safety review of PR 230). Each
        # deletion was six more nudges for a session that had been given up on. So a gave-up entry
        # stands unless there is evidence against it:
        #   - its session's state WAS read and its mail is taken (above) or another mail is now its
        #     oldest unread: the mail it was given up for is gone;
        #   - its session is not in the listing, AND THE LISTING WAS READ WHOLE (-Listed, the ids of a
        #     listing the port answered as known). An unreadable listing is no evidence that anybody
        #     is gone, and with none handed in nothing is dropped for being gone.
        # A state that was not read, or read as unknown, is no evidence, and the entry stays.
        $drop = $old
        if ((Get-HordeWakeEntryValue $next[$id] "gaveUp") -eq $true) {
            $drop = $false
            if ($old -and $null -ne $States -and $States.ContainsKey($id)) {
                $a = $States[$id]
                if ("$($a.state)" -ceq "known" -and $null -eq (Get-HordeWakeLedgerEntry -Ledger $next -Id $id -State $a.value)) { $drop = $true }
            }
            if ($old -and $null -ne $Listed -and @($Listed) -cnotcontains "$id") { $drop = $true }
        }
        if ($taken -or $drop) { $next.Remove($id) }
    }
    # WHEN A SESSION LAST HAD A FREE KNOCK OUTLIVES ITS ROW BEING REPLACED - for another mail, a probe,
    # a nothing - for as long as the session has a row at all: the bound is on the session.
    if ($null -ne $Ledger) {
        foreach ($id in @($next.Keys)) {
            if (-not $Ledger.ContainsKey($id)) { continue }
            $kept = Get-HordeWakeEntryValue $Ledger[$id] "freeAt"
            if ($kept -is [datetime] -and (Get-HordeWakeEntryValue $next[$id] "freeAt") -isnot [datetime]) { $next[$id] = New-HordeWakeLedgerRow -Attempts ([int]$next[$id].attempts) -LastAttemptAt $next[$id].lastAttemptAt -LastOutcome "$($next[$id].lastOutcome)" -NothingAt (Get-HordeWakeEntryValue $next[$id] "nothingAt") -MailAt (Get-HordeWakeEntryValue $next[$id] "mailAt") -GaveUp ((Get-HordeWakeEntryValue $next[$id] "gaveUp") -eq $true) -ProbeAt (Get-HordeWakeEntryValue $next[$id] "probeAt") -Carry $next[$id] -FreeAt $kept }
        }
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
            $knocks = 0
            $was = Get-HordeWakeEntryValue $e "probes"
            if ($was -is [int] -or $was -is [long]) { $knocks = [int]$was }
            $spent = ([int]$e.attempts -ge [int]$Settings.maxNudgesPerMail)
            $probedOut = ($knocks -ge [int]$Settings.maxLimitProbesPerMail)
            if (-not ($spent -or $probedOut) -or (Get-HordeWakeEntryValue $e "gaveUp") -eq $true) { continue }
            $mailAt = Get-HordeWakeEntryValue $e "mailAt"
            $next["$id"] = New-HordeWakeLedgerRow -Attempts ([int]$e.attempts) -LastAttemptAt $e.lastAttemptAt -LastOutcome "$($e.lastOutcome)" -NothingAt (Get-HordeWakeNothingAt $e) -MailAt $mailAt -GaveUp $true -ProbeAt (Get-HordeWakeEntryValue $e "probeAt") -Carry $e
            $since = ""
            if ($mailAt -is [datetime]) { $since = " unread since " + $mailAt.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture) }
            $what = ("" + $e.attempts + " nudges for its mail" + $since + ", the last answered " + $e.lastOutcome + ", and the mail was not taken; it is not nudged again for this mail")
            $tried = [int]$e.attempts
            if (-not $spent) { $what = ("" + $knocks + " knocks for its mail" + $since + " while it was under a usage limit with no known end, the last answered " + $e.lastOutcome + ", and the mail was not taken; it is not knocked for again until its mail changes or it is no longer limited"); $tried = $knocks }
            [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "gave-up" -Id "$id" -Outcome "gave-up" -Reason $what))
            [void]$sessions.Add([pscustomobject]@{ id = "$id"; mailAt = $mailAt; attempts = $tried })
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

function Update-HordeWakeAcksRose {
    # WHO WAS SEEN TO ACKNOWLEDGE MAIL, between the last reading and this one: { acks; rose; moved; risen }. The one
    # rule both a silence's end (Update-HordeWakeSilence) and the release of a session whose limit nobody
    # could read (Get-HordeWakeLimit) are judged by, kept in one place so the two cannot drift apart.
    #   -Seen   { acks; rose } from the last pass (the silence's seen carries both), or $null
    #   -Acks   session id -> when it last acknowledged mail, or $null for never, as this pass read it
    # acks is the reading to compare the next one with: this pass's, over what was known before of a
    # session this pass did not read. rose is session id -> the acknowledgement time at which it was
    # last SEEN TO INCREASE, kept from pass to pass; moved says one did on this pass.
    # AN INCREASE IS A SESSION SEEN BEFORE NOW SHOWING AN ACKNOWLEDGEMENT NEWER THAN THE ONE IT SHOWED, OR ITS
    # FIRST. A session seen for the first time proves nothing by what it already had - which is what makes
    # the first pass after a start, whose reading has nothing before it, no evidence of anything. And
    # one dated in the future is no increase.
    # THE READING KEPT IS THE LARGEST TIME SEEN, AND WHAT CANNOT BE READ IS UNKNOWN, NOT ZERO. Each reading
    # overwrote the last, so a row read as T, then with no time that could be read (acked known, the time
    # not one), then as T again, rose on the third pass from nothing to T: a silence ended, and every
    # session limited unknown was released, with nobody having taken a turn (review of the before-live
    # fixes). An older time read after a newer one did the same. So a session's reading is replaced only
    # by a newer time. A session seen for the first time is kept as it reads - none, if it reads none - so
    # its first acknowledgement after that is still a rise.
    param($Seen = $null, $Acks = @{}, [Parameter(Mandatory = $true)][datetime]$Now)
    $acksNow = @{}
    $wasAcks = Get-HordeWakeEntryValue $Seen "acks"
    if ($wasAcks -is [System.Collections.IDictionary]) { foreach ($id in @($wasAcks.Keys)) { $acksNow["$id"] = $wasAcks[$id] } }
    $rose = @{}
    $wasRose = Get-HordeWakeEntryValue $Seen "rose"
    if ($wasRose -is [System.Collections.IDictionary]) { foreach ($id in @($wasRose.Keys)) { $rose["$id"] = $wasRose[$id] } }
    $moved = $false
    if ($Acks -is [System.Collections.IDictionary]) {
        foreach ($id in @($Acks.Keys)) {
            $shown = $Acks[$id]
            if ($acksNow.ContainsKey("$id") -and $shown -is [datetime] -and $shown -le $Now -and ($acksNow["$id"] -isnot [datetime] -or $shown -gt $acksNow["$id"])) { $moved = $true; $rose["$id"] = $shown }
            if (-not $acksNow.ContainsKey("$id") -or ($shown -is [datetime] -and ($acksNow["$id"] -isnot [datetime] -or $shown -gt $acksNow["$id"]))) { $acksNow["$id"] = $shown }
        }
    }
    # risen: the sessions that rose on THIS pass, for a caller that must know whose it was - a session's own
    # rise releases nothing of its own (Set-HordeWakeLedgerProbesDue, -Risen).
    $risen = @($rose.Keys | Where-Object { -not ($wasRose -is [System.Collections.IDictionary] -and $wasRose.Contains($_) -and $wasRose[$_] -eq $rose[$_]) } | ForEach-Object { "$_" } | Sort-Object)
    return [pscustomobject]@{ acks = $acksNow; rose = $rose; moved = $moved; risen = $risen }
}

function Update-HordeWakeSilence {
    # WHEN NOBODY IN THE FLEET CAN ANSWER, AND NO WAKER SAYS WHY: { seen; entries; silent; declared;
    # moved; condition }. moved is true on a pass that saw a session take mail, silent before or not:
    # the caller then releases the sessions limited with no known end (Set-HordeWakeLedgerProbesDue). The net under Get-HordeWakeLimit, for a harness that reports no limit.
    #   -Seen     { silent; quietSince; nudges; acks; probes; probeAt }, from the last pass, or $null.
    #             probes is how many nudges were sent since the fleet was found silent: each is a
    #             probe, and the pass is told the count (Get-HordeWakeDecisions stretches and caps them
    #             by it). probeAt is when the last of them was sent, which the very slow probe after
    #             the cap is counted from.
    # AFTER THE LAST STRETCHED PROBE THE WARCHIEF IS TOLD. It was one journal line, silent-probes-ended,
    # and then nothing at all: a fleet that cannot answer, a watcher that has stopped asking, and
    # nobody who could look told either (review of PR 234). So the end of the stretched probes is a
    # FLEET NOTICE - condition silent-probes-ended, about no session, its instance the silence's
    # quietSince, so it is one notice per silence however often it is met - sent through the tell
    # sender as fleet-silent is (core/WakeTell.ps1), and journaled once as before. From there one
    # very slow probe goes on (Get-HordeWakeSettings, silentSlowProbeSeconds).
    #   -Entries  this pass's journal entries; its nudges are read from them
    #   -Acks     session id -> when it last acknowledged mail, or $null for never, for the sessions
    #             this pass could reach and whose acknowledgements its waker could read
    # THE FLEET IS SILENT when the watcher has been nudging for fleetSilentMinutes with no session taking
    # any mail, and in the last fleetSilentMinutes every nudge was answered woken, to at least
    # fleetSilentSessions different sessions. Woken and never taken, by everybody at once, is not three
    # stubborn sessions: it is a fleet that cannot answer (the incident Get-HordeWakeLimit describes).
    # ONE entry of kind fleet-silent, one condition for the warchief (core/WakeTell.ps1), and declared is
    # true on that pass alone: the caller then forgives the attempts spent on a fleet that could not
    # answer (Reset-HordeWakeLedgerAttempts). While it lasts the caller passes -Silent to the pass, so
    # every nudge is a probe - the longest step, uncounted. A NUDGE THAT IS NOT WOKEN - busy, mid-turn -
    # IS A SESSION AT WORK, and a fleet with one of those is not silent.
    # IT ENDS WHEN ANY SESSION ACKNOWLEDGES MAIL - a session seen before now shows an acknowledgement
    # newer than the one it showed, or its first: one entry of kind fleet-moving, and every session is
    # nudged as normal again, from no attempts, in the fair order. NEVER AN INBOX THAT CHANGED
    # (Get-HordeWakeLimit says why). A session seen for the first time proves nothing by what it
    # already had. AND A SILENCE IS DECLARED ONLY WHERE ITS END CAN BE SEEN: a waker that reads no
    # acknowledgements gives -Acks nothing, and for it the fleet is never called silent - it would
    # be a state with no way out.
    param($Seen = $null, $Entries = @(), $Acks = @{}, [Parameter(Mandatory = $true)][datetime]$Now, $Settings = (Get-HordeWakeSettings))
    $before = [pscustomobject]@{ silent = $false; quietSince = $null; nudges = @(); acks = @{}; probes = 0 }
    if ($null -ne $Seen) { $before = $Seen }
    $out = New-Object System.Collections.ArrayList
    # WHO ACKNOWLEDGED MAIL SINCE THE LAST PASS (Update-HordeWakeAcksRose). rose is kept in the seen, for the
    # next pass to judge a session whose limit nobody could read by (Invoke-HordeWakePass, -AcksSeen).
    $heard = Update-HordeWakeAcksRose -Seen $before -Acks $Acks -Now $Now
    $moved = $heard.moved
    $acksNow = $heard.acks
    $rose = $heard.rose
    if ($moved) {
        if ($before.silent -eq $true) { [void]$out.Add((New-HordeWakeEntry -At $Now -Kind "fleet-moving" -Outcome "moving" -Reason "a session acknowledged mail: the fleet is answering again, and every session is nudged as normal")) }
        return [pscustomobject]@{ seen = [pscustomobject]@{ silent = $false; quietSince = $null; nudges = @(); acks = $acksNow; probes = 0; rose = $rose }; entries = $out.ToArray(); silent = $false; declared = $false; moved = $true; condition = $null; risen = $heard.risen }
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
    $sent = 0
    $was = Get-HordeWakeEntryValue $before "probes"
    if ($was -is [int] -or $was -is [long]) { $sent = [int]$was }
    $next = [pscustomobject]@{ silent = ($before.silent -eq $true); quietSince = $quietSince; nudges = $nudges.ToArray(); acks = $acksNow; probes = 0; probeAt = $null; rose = $rose }
    if ($next.silent) {
        $most = [int]$Settings.maxSilentProbes
        $probedNow = @($Entries | Where-Object { $null -ne $_ -and @("nudge", "nudge-killed") -ccontains "$($_.kind)" }).Count
        $next.probes = $sent + $probedNow
        $lastProbe = Get-HordeWakeEntryValue $before "probeAt"
        if ($probedNow -gt 0) { $lastProbe = $Now }
        if ($lastProbe -is [datetime]) { $next.probeAt = $lastProbe }
        $condition = $null
        if ($sent -lt $most -and $next.probes -ge $most) {
            $every = ([double]$Settings.silentSlowProbeSeconds / 3600).ToString([System.Globalization.CultureInfo]::InvariantCulture) + " hours"
            [void]$out.Add((New-HordeWakeEntry -At $Now -Kind "silent-probes-ended" -Outcome "ended" -Reason ("the fleet has been silent through " + $next.probes + " probes, and the stretched probes have ended. From here one session is asked every " + $every + ", and the warchief is told; the silence ends, and everybody is nudged as normal, when a session acknowledges mail")))
            $instance = ""
            if ($quietSince -is [datetime]) { $instance = $quietSince.ToUniversalTime().ToString("o", [System.Globalization.CultureInfo]::InvariantCulture) }
            $condition = [pscustomobject]@{ kind = "silent-probes-ended"; subject = ""; instance = $instance; text = ("the fleet has been silent through " + $next.probes + " probes and no session has acknowledged mail. The watcher now asks one session only every " + $every + ", and wakes everybody when one takes mail. Somebody should look: a usage limit, perhaps, or sessions that cannot take a turn.") }
        }
        return [pscustomobject]@{ seen = $next; entries = $out.ToArray(); silent = $true; declared = $false; moved = $false; condition = $condition }
    }
    $who = @($nudges | ForEach-Object { $_.id } | Sort-Object -Unique)
    $notWoken = @($nudges | Where-Object { $_.outcome -cne "woken" })
    if ($acksNow.Count -gt 0 -and $quietSince -is [datetime] -and ($Now - $quietSince).TotalSeconds -ge $window -and $who.Count -ge [int]$Settings.fleetSilentSessions -and $notWoken.Count -eq 0) {
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
    # -Risen: the sessions seen to take mail on that pass (Update-HordeWakeSilence's risen). A SESSION'S OWN
    # ACKNOWLEDGEMENT RELEASES NOTHING OF ITS OWN, as it is no evidence for its own unknown limit
    # (Get-HordeWakeLimit): its probe is marked due only when ANOTHER session rose. A watcher started
    # with every acknowledgement stamped, whose judged session then moved its own, knocked it at once
    # by this path (review of PR 234). Without -Risen every probe is marked, as before.
    param($Ledger, $Risen = $null)
    $next = @{}
    if ($null -ne $Ledger) {
        foreach ($id in @($Ledger.Keys)) {
            $e = $Ledger[$id]
            $next["$id"] = $e
            if ((Get-HordeWakeEntryValue $e "probeAt") -isnot [datetime]) { continue }
            if ($null -ne $Risen -and @(@($Risen) | Where-Object { "$_" -cne "$id" }).Count -eq 0) { continue }
            $next["$id"] = New-HordeWakeLedgerRow -Attempts ([int]$e.attempts) -LastAttemptAt $e.lastAttemptAt -LastOutcome "$($e.lastOutcome)" -NothingAt (Get-HordeWakeNothingAt $e) -MailAt (Get-HordeWakeEntryValue $e "mailAt") -GaveUp ((Get-HordeWakeEntryValue $e "gaveUp") -eq $true) -ProbeAt $script:HordeWakeProbeDue -Carry $e
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
            $next["$id"] = New-HordeWakeLedgerRow -Attempts 0 -LastAttemptAt $e.lastAttemptAt -LastOutcome "$($e.lastOutcome)" -NothingAt (Get-HordeWakeNothingAt $e) -MailAt (Get-HordeWakeEntryValue $e "mailAt") -ProbeAt $e.lastAttemptAt -Carry $e
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
    #   -Send             SEND THE NUDGES IT DECIDES. WITHOUT IT THE PASS IS SHADOW: it journals what it
    #                     would do and does none of it - no nudge is sent. A would-nudge still counts as
    #                     an attempt in the ledger, so the journal shows the rhythm a live run would
    #                     have had instead of a line every pass. Sending is what a caller must ask for:
    #                     it was the other way round, the pass was live unless -Shadow was passed, and
    #                     a caller that left the word out ran a live pass over the whole fleet (safety
    #                     review of PR 220).
    # THE ENTRIES are the journal lines, kinds: nudge, nudge-killed (a nudge the waker had to stop
    # part-way), would-nudge and skip-unknown (a listing or a state the port could not give; id is ""
    # for the listing).
    #   -Silent           the fleet is silent (Update-HordeWakeSilence): every nudge of this pass is a probe
    #   -SilentProbes     how many probes were sent since it was found silent (the silence's probes)
    #   -SilentProbeAt    when the last of them was sent (the silence's probeAt), or $null
    #   -AcksSeen         the last pass's reading of who acknowledged mail - the silence's seen, which keeps
    #                     it - or $null when there was none: then no acknowledgement can be seen to rise,
    #                     and nobody's unknown limit is released by one (Get-HordeWakeLimit)
    # mail is session id -> its oldest unread mail's time, or $null, for the sessions whose state was
    # read; limited is session id -> its usage limit's text, for those with unread mail that are limited.
    #   -Only             ONE SESSION, AND NO OTHER: the pass is cut down to this id before any state is
    #                     read, so no other session can be looked at, decided on or nudged by it. It is
    #                     how a proof run is kept to the one session a person chose to have typed into
    #                     (core/WakeRun.ps1, PROOF). A session that is not in the listing - or a listing
    #                     that cannot be read - is one entry of kind proof-target-absent, and nobody is
    #                     nudged: the pass never falls back to "whoever is ready".
    param($Waker, [Parameter(Mandatory = $true)][datetime]$Now, $Settings = (Get-HordeWakeSettings), $Ledger = @{}, [switch]$Send, [switch]$Silent, [int]$SilentProbes = 0, [string]$Only = "", [string]$Self = "", $SilentProbeAt = $null, $AcksSeen = $null, $Asleep = $null, [string]$AsleepUnknown = "")
    $shadowPass = (-not $Send)
    # never is session id -> why a session with unread mail is NEVER nudged, for what it is: retired, a
    # reserved label, the watcher's own session (skip). held is session id -> why one is held for what
    # it MAY be: possibly retired (wait). Each for the tick to journal once, under its own kind.
    $mail = @{}
    $limited = @{}
    $held = @{}
    $never = @{}
    # duplicate is session id -> the line for a session with unread mail and two running copies (T-0116).
    $duplicate = @{}
    # duplicateOn is session id -> $true for every session READ this pass that has more than one running copy, with
    # mail or none: an episode lasts as long as the copies do, not as long as one batch of mail (T-0116, round 3).
    $duplicateOn = @{}
    $Acks = @{}
    $open = New-Object System.Collections.ArrayList
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
            # EVERY SESSION THE LISTING NAMED, kept before the pass is cut down to one (-Only): a session is
            # gone only when a whole listing does not name it (Update-HordeWakeLedger, -Listed).
            $listedIds = @($targets | ForEach-Object { "$($_.id)" })
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
            # WHO HAS ACKNOWLEDGED MAIL, AND WHEN (Get-HordeWakeLimit): read from the states of this pass, for
            # the sessions that can be reached and whose acknowledgements the waker could read. The
            # value is $null for one that has never acknowledged any.
            foreach ($t in $targets) {
                $a = $states[$t.id]
                if ($a.state -ceq "known" -and "$($t.reachable)" -ceq "yes" -and "$(Get-HordeWakeEntryValue $a.value "acked")" -ceq "known") { $Acks[$t.id] = Get-HordeWakeEntryValue $a.value "lastAckedAt" }
            }
            # THE EVIDENCE THAT SESSIONS CAN TAKE TURNS IS AN ACKNOWLEDGEMENT SEEN TO INCREASE (Get-HordeWakeLimit):
            # this reading against the last pass's (-AcksSeen), by the silence's own rule
            # (Update-HordeWakeAcksRose), and only for a session read in THIS pass as reachable with its
            # acknowledgements known. With no reading before - the first pass after a start - nothing rose.
            $heard = Update-HordeWakeAcksRose -Seen $AcksSeen -Acks $Acks -Now $Now
            $moving = @{}
            foreach ($who in @($heard.rose.Keys)) { if ($Acks.ContainsKey("$who")) { $moving["$who"] = $heard.rose[$who] } }
            $canLook = Test-HordeWakerConfirms $Waker
            $confirmed = @{}
            $decisions = @(Get-HordeWakeDecisions -Targets $targets -States $states -Ledger $Ledger -Now $Now -Settings $Settings -Confirmed $confirmed -CanLook:$canLook -Silent:$Silent -SilentProbes $SilentProbes -Acks $moving -NoProbe:($Only -cne "") -Self $Self -SilentProbeAt $SilentProbeAt -Asleep $Asleep -AsleepUnknown $AsleepUnknown)
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
                $decisions = @(Get-HordeWakeDecisions -Targets $targets -States $states -Ledger $Ledger -Now $Now -Settings $Settings -Confirmed $confirmed -CanLook:$canLook -Silent:$Silent -SilentProbes $SilentProbes -Acks $moving -NoProbe:($Only -cne "") -Self $Self -SilentProbeAt $SilentProbeAt -Asleep $Asleep -AsleepUnknown $AsleepUnknown)
            }
            foreach ($d in $decisions) { if ($d.action -ceq "look") { $d.action = "wait"; $d.reason = "its box and its turn were not read this pass: the pass's looks were used up" } }
            foreach ($t in $targets) {
                $a = $states[$t.id]
                if ($a.state -cne "known") { continue }
                $mail[$t.id] = $a.value.oldestUnreadAt
                if ($a.value.unreadCount -gt 0 -and "$($t.retired)" -ceq "yes") { $never[$t.id] = "retired, with " + $a.value.unreadCount + " unread: a retired session is never nudged, so this mail waits for nobody. It is not counted, and nobody is told" }
                elseif ($a.value.unreadCount -gt 0 -and (Test-HordeLabelReserved "$($t.label)")) { $never[$t.id] = "its label, " + $t.label + ", is reserved for a sender that is no session, and it has " + $a.value.unreadCount + " unread: it is never nudged" }
                elseif ($a.value.unreadCount -gt 0 -and $Self -cne "" -and "$($t.id)" -ceq $Self) { $never[$t.id] = "it is the session this watcher was started from, and it has " + $a.value.unreadCount + " unread: a watcher never nudges itself" }
                elseif ($a.value.unreadCount -gt 0 -and $null -ne $Asleep -and $Asleep.ContainsKey("$($t.id)")) { $never[$t.id] = "" + $Asleep["$($t.id)"] + ", with " + $a.value.unreadCount + " unread: a hibernated session is never knocked, and its mail waits for its wake" }
                elseif ($a.value.unreadCount -gt 0 -and "$($t.retired)" -cne "no") { $held[$t.id] = "it could not be told whether this session is retired, and it has " + $a.value.unreadCount + " unread: it is not nudged while that is so" }
                # MAIL HANDED OVER AND NOTHING UNREAD: said once, as held, for a session that would otherwise be
                # nudged - else its inbox shows mail and the journal shows nothing done about it.
                elseif ($a.value.unreadCount -le 0 -and (Get-HordeWakeHandedOver $a.value) -gt 0 -and "$($t.retired)" -ceq "no" -and -not (Test-HordeLabelReserved "$($t.label)") -and ($Self -ceq "" -or "$($t.id)" -cne $Self)) { $held[$t.id] = "handed-over mail: " + (Get-HordeWakeHandedOver $a.value) + " handed over to it and not yet acknowledged, and none unread. It is not nudged: it has that mail already, and the fleet counts it unread again if it is never acknowledged" }
                # TWO RUNNING COPIES, WITH MAIL: said once per episode (T-0116), by its own channel so that the
                # tick can tell M too. Only a session that would otherwise be waited on for no word: not one
                # that is never nudged for what it is, and not one with no unread mail.
                if ("$(Get-HordeWakeEntryValue $t "duplicate")" -ceq "yes" -and "$($t.retired)" -ceq "no") { $duplicateOn[$t.id] = $true }
                if ($a.value.unreadCount -gt 0 -and "$(Get-HordeWakeEntryValue $t "duplicate")" -ceq "yes" -and "$($t.retired)" -ceq "no" -and -not $never.ContainsKey($t.id) -and -not $held.ContainsKey($t.id)) { $duplicate[$t.id] = "the session " + $(if ("$($t.label)" -cne "") { "$($t.label) (" + $t.id + ")" } else { "" + $t.id }) + " is running as more than one copy and has " + $a.value.unreadCount + " unread. It is not nudged while that is so, so this mail waits until all but one copy is closed. The fleet's row does not say which processes or panes the two are." }
                # A LIMIT IS SAID ONLY OF A SESSION THAT COULD OTHERWISE BE NUDGED: reachable, not retired.
                $limit = Get-HordeWakeLimit -State $a.value -Now $Now -Settings $Settings -Acks $moving
                if ($a.value.unreadCount -gt 0 -and "$($t.reachable)" -ceq "yes" -and "$($t.retired)" -ceq "no" -and @("until", "open") -ccontains $limit.kind) {
                    $limited[$t.id] = $limit.text
                    if ($limit.kind -ceq "open") { [void]$open.Add($t.id) }
                }
            }
            $outcomes = @{}
            # A NUDGE IS COUNTED BEFORE IT IS ASKED FOR. The pass nudged, and then worked the ledger out
            # from what came back; anything that threw in between - in here, not in the tick, which
            # had been mended - left the function with the ledger as it was before the nudge. The
            # session had been typed into and nothing said so: the next pass, three seconds on,
            # typed into it again (review of PR 230). So the attempt is written into the ledger this
            # pass returns BEFORE the waker is asked, with its outcome unknown; the ordinary update
            # below replaces that with the whole truth; and if anything throws once a nudge has been
            # asked for, the pass does not throw it on - it returns, with that ledger, the lines it
            # has, and one more saying what failed. A probe or a free knock is counted as an attempt
            # in that case: one nudge too few, never one too many.
            # A throw BEFORE any nudge is asked for is thrown on as it always was: nothing was typed.
            $asked = New-Object System.Collections.ArrayList
            try {
            foreach ($d in $decisions) {
                if ($d.action -cne "nudge") { continue }
                # SHADOW: the nudge is journaled and counted, and nothing is asked of the waker.
                if ($shadowPass) { $outcomes[$d.id] = "would-nudge"; [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "would-nudge" -Id $d.id -Outcome "would-nudge" -Reason $d.reason)); continue }
                $nextLedger = Set-HordeWakeLedgerAsked -Ledger $nextLedger -Id $d.id -Now $Now -State $(if ($states.ContainsKey($d.id) -and "$($states[$d.id].state)" -ceq "known") { $states[$d.id].value } else { $null }) -Free:((Get-HordeWakeEntryValue $d "free") -eq $true)
                [void]$asked.Add($d.id)
                $rang = Send-HordeWakeNudge -Waker $Waker -Id $d.id
                if ($rang.state -ceq "known") {
                    $outcomes[$d.id] = $rang.value.outcome
                    # A RUN OF NOTHINGS IS JOURNALED ONCE, when it starts: the ledger's hold says one is under way.
                    if ($rang.value.outcome -ceq "nothing" -and $null -ne (Get-HordeWakeNothingAt (Get-HordeWakeLedgerEntry -Ledger $Ledger -Id $d.id))) { continue }
                    # A NUDGE THE WAKER HAD TO KILL IS ITS OWN KIND OF LINE, so nobody reads it as one more nudge.
                    $kind = "nudge"
                    if ($rang.value.outcome -ceq "killed") { $kind = "nudge-killed" }
                    # A REAL NUDGE'S LINE SAYS WHY IT WAS SENT, WHAT THE WAKER ANSWERED, AND - when the waker names one -
                    # THE RULE that let it type (wakers/Port.ps1, rule). A woken used to be journaled with
                    # no reason at all.
                    $told = "$($rang.value.reason)"
                    if ($d.reason -clike "*between-turns*") { $told = $(if ($told -ne "") { $told + "; " } else { "" }) + "sent because: " + $d.reason }
                    $rule = "$(Get-HordeWakeEntryValue $rang.value "rule")"
                    if ($rule -ne "") { $told = $(if ($told -ne "") { $told + "; " } else { "" }) + "the waker says the rule that let it type was " + $rule }
                    [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind $kind -Id $d.id -Outcome $rang.value.outcome -Reason $told -ElapsedMs (Get-HordeWakeEntryValue $rang.value "elapsedMs")))
                }
                else { $outcomes[$d.id] = "unknown"; [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "nudge" -Id $d.id -Outcome "unknown" -Reason "$($rang.reason)")) }
            }
            $nextLedger = Update-HordeWakeLedger -Ledger $Ledger -Decisions $decisions -Outcomes $outcomes -States $states -Now $Now -Settings $Settings -Silent:$Silent -Open $open.ToArray() -Acks $moving -Listed $listedIds
            # THE CAP: a session nudged maxNudgesPerMail times for one mail is given up on, said once.
            $gave = Update-HordeWakeGaveUp -Ledger $nextLedger -Now $Now -Settings $Settings
            $nextLedger = $gave.ledger
            $gaveUp = @($gave.sessions)
            foreach ($e in @($gave.entries)) { [void]$entries.Add($e) }
            } catch {
                if ($asked.Count -eq 0) { throw }
                $why = "$($_.Exception.Message)"
                # Nothing here may throw: it would lose the ledger again.
                try {
                    foreach ($id in @($asked)) {
                        if (@($entries | Where-Object { @("nudge", "nudge-killed") -ccontains "$($_.kind)" -and "$($_.id)" -ceq "$id" }).Count -eq 0) { [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "nudge" -Id "$id" -Outcome "unknown" -Reason "a nudge was asked for, and the pass failed before its answer was recorded")) }
                    }
                    [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "skip-unknown" -Id "pass-after-nudge" -Outcome "unknown" -Reason ("the pass failed after a nudge was asked for; the attempt is counted all the same, so the session is not nudged again at once: " + $why)))
                } catch { }
            }
        }
    }
    return [pscustomobject]@{ ledger = $nextLedger; entries = $entries.ToArray(); decisions = $decisions; unreadable = $unreadable; gaveUp = $gaveUp; listing = $listing; warchief = $warchief; mail = $mail; limited = $limited; held = $held; never = $never; duplicate = $duplicate; duplicateOn = $duplicateOn; acks = $Acks }
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
            $knocks = Get-HordeWakeEntryValue $Ledger[$id] "probes"
            if (($knocks -is [int] -or $knocks -is [long]) -and $knocks -gt 0) { $row["probes"] = [int]$knocks }
            $freeFor = Get-HordeWakeEntryValue $Ledger[$id] "freeFor"
            if ($freeFor -is [datetime]) { $row["freeFor"] = ConvertTo-HordeWakeTimeText $freeFor }
            $freeAt = Get-HordeWakeEntryValue $Ledger[$id] "freeAt"
            if ($freeAt -is [datetime]) { $row["freeAt"] = ConvertTo-HordeWakeTimeText $freeAt }
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
            if ($null -ne $row.PSObject.Properties["probes"]) { $entry["probes"] = [int]$row.probes }
            if ($null -ne $row.PSObject.Properties["freeFor"]) { $freeFor = ConvertFrom-HordeWakeTimeText $row.freeFor; if ($null -ne $freeFor) { $entry["freeFor"] = $freeFor } }
            if ($null -ne $row.PSObject.Properties["freeAt"]) { $freeAt = ConvertFrom-HordeWakeTimeText $row.freeAt; if ($null -ne $freeAt) { $entry["freeAt"] = $freeAt } }
            $ledger["$($row.id)"] = [pscustomobject]$entry
        }
    } catch { return (New-HordeUnknown -Reason "the saved ledger holds an entry that is not one" -ErrorRecord $_) }
    return (New-HordeKnown -Value ([pscustomobject]@{ ledger = $ledger }))
}

# ---- the file: <home>\wake\silence-<mode>.json ----

function Save-HordeWakeSilence {
    # WHETHER THE FLEET IS SILENT, AND SINCE WHEN, replaced whole. It lived
    # only in the running watcher: a watcher restarted in a silent fleet forgot the silence, counted
    # its knocks again from the forgiven ledger, and spent every session's budget a second time before
    # finding the silence anew (safety review of PR 220). The nudges and the mail it was worked out
    # from are not saved: they are read afresh, and a silence that is saved needs none of them to last.
    param($Seen, [string]$Mode = "", [string]$HordeHome = (Get-HordeHome))
    $since = $null
    $q = Get-HordeWakeEntryValue $Seen "quietSince"
    if ($q -is [datetime]) { $since = ConvertTo-HordeWakeTimeText $q }
    # probes - how many were sent since it was found silent - is saved with it: the cap on them is for
    # the whole silence, and a watcher started again must not be given twelve more.
    $sent = 0
    $p = Get-HordeWakeEntryValue $Seen "probes"
    if (($p -is [int] -or $p -is [long]) -and $p -gt 0) { $sent = [int]$p }
    # And when the last probe was sent, which the very slow probe after the cap is counted from: a watcher
    # started again would otherwise probe at once, and one restarted every hour would probe every hour.
    $lastProbe = $null
    $pa = Get-HordeWakeEntryValue $Seen "probeAt"
    if ($pa -is [datetime]) { $lastProbe = ConvertTo-HordeWakeTimeText $pa }
    $doc = [ordered]@{ schemaVersion = 1; silent = ((Get-HordeWakeEntryValue $Seen "silent") -eq $true); quietSince = $since; probes = $sent; probeAt = $lastProbe }
    Write-HordeWakeFile -Path (Get-HordeWakeStateFile -Name "silence" -Mode $Mode -HordeHome $HordeHome) -Text (ConvertTo-Json -InputObject $doc -Depth 5 -Compress)
}

function Save-HordeWakeDuplicate {
    # THE EPISODES OF A SESSION RUNNING AS MORE THAN ONE COPY, replaced whole (T-0116, round 3): session id ->
    # when it began and the line it was said by. Kept so a watcher that is started again does not say the line
    # again, and - the episode's start being the tell's instance - does not tell the warchief again either
    # (core/WakeTell.ps1: a restarted watcher does not repeat itself).
    param($Text, $At, [string]$Mode = "", [string]$HordeHome = (Get-HordeHome))
    $eps = [ordered]@{}
    foreach ($id in @($Text.Keys | Sort-Object)) {
        if (-not $At.ContainsKey("$id")) { continue }
        $eps["$id"] = [ordered]@{ at = (ConvertTo-HordeWakeTimeText $At["$id"]); text = "$($Text[$id])" }
    }
    $doc = [ordered]@{ schemaVersion = 1; episodes = $eps }
    Write-HordeWakeFile -Path (Get-HordeWakeStateFile -Name "duplicate" -Mode $Mode -HordeHome $HordeHome) -Text (ConvertTo-Json -InputObject $doc -Depth 5 -Compress)
}

function Read-HordeWakeDuplicate {
    # What Save-HordeWakeDuplicate wrote: known { text; at } (two tables by session id), absent when there is
    # none, unknown when it cannot be read - the caller then starts with no episode, and says so.
    param([string]$Mode = "", [string]$HordeHome = (Get-HordeHome))
    $path = Get-HordeWakeStateFile -Name "duplicate" -Mode $Mode -HordeHome $HordeHome
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return (New-HordeAbsent -Note "no episode of a duplicated session was saved in this home") }
    try { $j = (Read-HordeSharedText -Path $path) | ConvertFrom-Json }
    catch { return (New-HordeUnknown -Reason "what was saved of duplicated sessions could not be read" -ErrorRecord $_) }
    if ($null -eq $j -or $null -eq $j.PSObject.Properties["episodes"] -or $null -eq $j.episodes) { return (New-HordeUnknown -Reason "what was saved of duplicated sessions has no episodes") }
    $text = @{}; $at = @{}
    foreach ($p in @($j.episodes.PSObject.Properties)) {
        $when = $null
        if ($null -ne $p.Value -and $null -ne $p.Value.PSObject.Properties["at"]) { $when = ConvertFrom-HordeWakeTimeText $p.Value.at }
        if ($null -eq $when -or $null -eq $p.Value.PSObject.Properties["text"] -or $p.Value.text -isnot [string]) { return (New-HordeUnknown -Reason "what was saved of duplicated sessions holds an episode that is not one") }
        $text["$($p.Name)"] = [string]$p.Value.text
        $at["$($p.Name)"] = $when
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ text = $text; at = $at }))
}

function Read-HordeWakeSilence {
    # What Save-HordeWakeSilence wrote, as Update-HordeWakeSilence's -Seen: known { seen }, absent when
    # there is none, or unknown when it cannot be read - the caller then starts as though the fleet
    # were not silent, and says so.
    param([string]$Mode = "", [string]$HordeHome = (Get-HordeHome))
    $path = Get-HordeWakeStateFile -Name "silence" -Mode $Mode -HordeHome $HordeHome
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return (New-HordeAbsent -Note "nothing of a silent fleet was saved in this home") }
    try { $j = (Read-HordeSharedText -Path $path) | ConvertFrom-Json }
    catch { return (New-HordeUnknown -Reason "what was saved of a silent fleet could not be read" -ErrorRecord $_) }
    if ($null -eq $j -or $null -eq $j.PSObject.Properties["silent"] -or $j.silent -isnot [bool]) { return (New-HordeUnknown -Reason "what was saved of a silent fleet does not say whether it was silent") }
    $since = $null
    try {
        if ($null -ne $j.PSObject.Properties["quietSince"] -and $null -ne $j.quietSince) { $since = ConvertFrom-HordeWakeTimeText $j.quietSince; if ($null -eq $since) { return (New-HordeUnknown -Reason "what was saved of a silent fleet holds a time that is not one") } }
    } catch { return (New-HordeUnknown -Reason "what was saved of a silent fleet holds an entry that is not one" -ErrorRecord $_) }
    # WHEN THE FLEET WAS NOT SILENT, THE QUIET BEGINS AGAIN FROM NOTHING. quietSince is when the answers
    # now being counted began, and the nudges it was counted from are not saved. Read back alone it is an
    # old date with no history behind it: after a restart, or the passes of a proof, the first three
    # nudges answered woken were "three sessions, quiet for longer than the window" and the fleet was
    # called silent at once, on three answers (review of PR 230). A silence that WAS declared keeps its
    # date: it needs no history to last, only an acknowledgement to end.
    if (-not [bool]$j.silent) { $since = $null }
    # probes: a file written before they were counted has none, and that is 0. One that is there and is
    # no count is a file this does not read.
    $sent = 0
    $pp = $j.PSObject.Properties["probes"]
    if ($null -ne $pp -and $null -ne $pp.Value) {
        if (-not ($pp.Value -is [int] -or $pp.Value -is [long]) -or $pp.Value -lt 0 -or $pp.Value -gt 1000000) { return (New-HordeUnknown -Reason "what was saved of a silent fleet holds a count of probes that is not one") }
        $sent = [int]$pp.Value
    }
    if (-not [bool]$j.silent) { $sent = 0 }
    # probeAt: none in a file written before it was kept, and none for a fleet that was not silent. One
    # that is there and is no time is a file this does not read.
    $lastProbe = $null
    $pt = $j.PSObject.Properties["probeAt"]
    if ($null -ne $pt -and $null -ne $pt.Value) {
        try { $lastProbe = ConvertFrom-HordeWakeTimeText $pt.Value } catch { $lastProbe = $null }
        if ($null -eq $lastProbe) { return (New-HordeUnknown -Reason "what was saved of a silent fleet holds a time of its last probe that is not one") }
    }
    if (-not [bool]$j.silent) { $lastProbe = $null }
    return (New-HordeKnown -Value ([pscustomobject]@{ seen = [pscustomobject]@{ silent = [bool]$j.silent; quietSince = $since; nudges = @(); acks = @{}; probes = $sent; probeAt = $lastProbe } }))
}
