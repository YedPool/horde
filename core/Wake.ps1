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

function Invoke-HordeWakePass {
    # ONE PASS. Reads the targets and each one's state through the port, decides, and acts; returns
    # { ledger; entries; decisions }. It reads no clock and no file: the loop passes -Now and keeps what
    # comes back.
    #   -Waker            a registered waker, or $null when none is installed: then nobody is nudged
    #   -Ledger           session id -> { attempts; lastAttemptAt; lastOutcome }, from the last pass
    #   -Shadow           JOURNAL WHAT IT WOULD DO, AND DO NONE OF IT: no nudge is sent. A would-nudge
    #                     still counts as an attempt in the ledger, so the journal shows the rhythm a
    #                     live run would have had instead of a line every pass.
    # THE ENTRIES are the journal lines, kinds: nudge, would-nudge and skip-unknown (a listing or a state
    # the port could not give; id is "" for the listing).
    param($Waker, [Parameter(Mandatory = $true)][datetime]$Now, $Settings = (Get-HordeWakeSettings), $Ledger = @{}, [switch]$Shadow)
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
    return [pscustomobject]@{ ledger = $nextLedger; entries = $entries.ToArray(); decisions = $decisions }
}

# ---- the file: <home>\wake\ledger.json ----
# Kept apart from everything above, which reads and writes none. Only the command's loop calls these.

function Save-HordeWakeLedger {
    # ledger.json, replaced whole: the back-off of every session being asked, so a watcher that is
    # restarted does not knock at once on a session it had been told to leave for five minutes.
    param($Ledger, [string]$HordeHome = (Get-HordeHome))
    $sessions = New-Object System.Collections.ArrayList
    if ($null -ne $Ledger) {
        foreach ($id in @($Ledger.Keys | Sort-Object)) {
            [void]$sessions.Add([ordered]@{ id = "$id"; attempts = [int]$Ledger[$id].attempts; lastAttemptAt = (ConvertTo-HordeWakeTimeText $Ledger[$id].lastAttemptAt); lastOutcome = "$($Ledger[$id].lastOutcome)" })
        }
    }
    $doc = [ordered]@{ schemaVersion = 1; sessions = $sessions.ToArray() }
    Write-HordeWakeFile -Path (Join-Path (Get-HordeWakeFolder -HordeHome $HordeHome) "ledger.json") -Text (ConvertTo-Json -InputObject $doc -Depth 5 -Compress)
}

function Read-HordeWakeLedger {
    # What Save-HordeWakeLedger wrote: known { ledger }, absent when there is none, or unknown
    # when it cannot be read - the caller then starts from an empty ledger and says so.
    param([string]$HordeHome = (Get-HordeHome))
    $path = Join-Path (Get-HordeWakeFolder -HordeHome $HordeHome) "ledger.json"
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
            $ledger["$($row.id)"] = [pscustomobject]@{ attempts = [int]$row.attempts; lastAttemptAt = $at; lastOutcome = "$($row.lastOutcome)" }
        }
    } catch { return (New-HordeUnknown -Reason "the saved ledger holds an entry that is not one" -ErrorRecord $_) }
    return (New-HordeKnown -Value ([pscustomobject]@{ ledger = $ledger }))
}
