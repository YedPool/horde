# core/WakeRun - one tick of `horde wake run`: the wake pass, the restore source beside it, and the files.
#
# WHY NOT IN THE COMMAND. The loop was written in cli/commands/wake.ps1, where no suite could drive it,
# and the review of PR #207 found what that hid:
#   - NOTHING CAUGHT AN ERROR. One failed rename of the heartbeat ended the loop, and with it the only
#     process that wakes anybody. A tick now catches what each of its parts throws, journals it once
#     for as long as it lasts, and returns; the loop goes on.
#   - -Shadow WAS A WORD AT TWO CALL SITES, and deleting it there passed every suite.
#
# THE MODE BELONGS TO THE RUN, AND IS SET IN ONE PLACE. A run is made shadow (New-HordeWakeRun) or live
# (New-HordeWakeRun -Live), says which in its own live member, and reads and writes that mode's files
# and no other (core/WakeFiles.ps1: ledger, restore state, journal, heartbeat and lock are each per
# mode). A tick takes its mode from the run it is handed and offers no parameter that could change it:
# a shadow run cannot be ticked live, and a caller has no word to drop.
#   SHADOW  journals what a tick would do - would-nudge, would-post, would-stall - and does none of it.
#   LIVE    sends the nudges the wake pass decided, through the waker it was handed, and nothing else.
#
# THE TWO SENDERS STAY SHADOW EVEN IN A LIVE RUN: the restore source (core/RestoreSource.ps1) and the
# tell sender (core/WakeTell.ps1). They journal would-post, would-stall and would-tell, and post
# nothing. Why: the only messenger that reaches a real session types its own wake line on every post
# (messengers/wezfleet/Messenger.ps1, WOKEN, OR ONLY QUEUED: "wezfleet's post knocks once for each new
# message"). A live resume post would therefore type into every orc at once - outside nudge.guarded,
# which is the nudge's own last look at the box and the turn, and outside maxNudgesPerPass, which is
# what makes a restore of everything a queue and not a burst. That is exactly the typing this watcher
# exists to do carefully. The source goes live only when a post that does not knock exists; until then
# its mail is something a person reads in the journal. Its would-post marks are kept in a file of the
# live run's own (restore-of-live-run-shadow.json): not the shadow run's, which another process may
# be writing, and not restore-live.json, which is for mails that were really posted.
#
# THE TWO PASSES STAY APART (core/Wake.ps1, core/RestoreSource.ps1): the watcher only wakes, the restore
# source only posts, and a tick runs the second beside the first, every restoreEverySeconds, because it
# reads the process table and a restore is measured in minutes (the first resume is due at once, the
# stall notice at 300 s).
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). It runs under -Version Latest.

. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "WakeFiles.ps1")
. (Join-Path $PSScriptRoot "Wake.ps1")
. (Join-Path $PSScriptRoot "RestoreSource.ps1")
. (Join-Path $PSScriptRoot "WakeTell.ps1")

# THE ONE SWITCH FOR BOTH SENDERS. While it is $false, the restore source and the tell sender run SHADOW in
# every mode of the run - they journal would-post, would-stall and would-tell, and post nothing - for the
# reason the header gives: a post types a wake line. When a post that does not knock exists, this is
# what turns on, and nothing else has to: with it $true, a live run hands both senders their posters
# (Send-HordeRestoreMail, Send-HordeWakeTell) and keeps their marks in its own live files.
$script:HordeWakeSendersPost = $false
# How often a tick runs the restore source.
$script:HordeWakeRestoreEverySeconds = 30

function New-HordeWakeRun {
    # What a run carries from tick to tick, read from its own mode's files: { live; ledger; posted;
    # restores; unknown; notes; badMail; restoreAt; pass; said }. SHADOW UNLESS -Live IS GIVEN, and live
    # is never changed afterwards (the header). said is what the caller should print once: a saved
    # file that could not be read is started from empty, and says so.
    param([switch]$Live, [string]$HordeHome = (Get-HordeHome))
    $run = [pscustomobject]@{ live = [bool]$Live; ledger = @{}; posted = @{}; restores = @(); unknown = @{}; notes = @(); badMail = @{}; fleetRead = $null; told = @{}; warchief = ""; restoreAt = [datetime]::MinValue; pass = [long]0; said = @() }
    $saved = Read-HordeWakeLedger -Shadow:(-not $run.live) -HordeHome $HordeHome
    if ($saved.state -ceq "known") { $run.ledger = $saved.value.ledger }
    elseif ($saved.state -ceq "unknown") { $run.said = @($run.said) + ("starting from an empty ledger - " + $saved.reason) }
    $savedRestore = Read-HordeRestoreState -Name (Get-HordeWakeSenderFile -Run $run -Stem "restore").name -Mode (Get-HordeWakeSenderFile -Run $run -Stem "restore").mode -HordeHome $HordeHome
    if ($savedRestore.state -ceq "known") { $run.posted = $savedRestore.value.posted; $run.restores = @($savedRestore.value.known) }
    elseif ($savedRestore.state -ceq "unknown") { $run.said = @($run.said) + ("starting with no mail marked posted - " + $savedRestore.reason) }
    $place = Get-HordeWakeSenderFile -Run $run -Stem "tells"
    $savedTells = Read-HordeWakeTellState -Name $place.name -Mode $place.mode -HordeHome $HordeHome
    if ($savedTells.state -ceq "known") { $run.told = $savedTells.value.told }
    elseif ($savedTells.state -ceq "unknown") { $run.said = @($run.said) + ("starting with nothing marked told - " + $savedTells.reason) }
    return $run
}

function Get-HordeWakeRunPlan {
    # How `horde wake run` starts, decided here so a suite can hold it: { ok; live; waker; banner; reason }.
    #   -Live    the person asked for a live run; without it the run is SHADOW, whatever else is true
    #   -Picked  Resolve-HordeProductionWaker's answer
    # A LIVE RUN WITH NO WAKER TO RING THROUGH IS REFUSED (ok false, with the reason): it would beat a
    # live heartbeat, look alive, and wake nobody. A shadow run with none still runs: the restore source
    # needs no waker. THE BANNER SAYS THE MODE FIRST, IN CAPITALS: which of the two is running is the
    # one thing a person starting it must not be able to misread.
    param([switch]$Live, [Parameter(Mandatory = $true)]$Picked)
    $waker = $null
    if ((Test-HordeAnswer $Picked) -and $Picked.state -ceq "known") { $waker = $Picked.value }
    $why = "the answer about the installed waker is not one"
    if (Test-HordeAnswer $Picked) { $why = "$($Picked.reason)" }
    if (-not $Live) {
        if ($null -ne $waker) { return [pscustomobject]@{ ok = $true; live = $false; waker = $waker; reason = ""; banner = ("SHADOW - nothing is nudged and nothing is posted; what would be is journaled. Reading state through the waker '" + $waker.name + "'") } }
        return [pscustomobject]@{ ok = $true; live = $false; waker = $null; reason = ""; banner = ("SHADOW - nothing is nudged and nothing is posted. No waker is installed, so no session is watched for unread mail; the restore source still runs (" + $why + ")") }
    }
    if ($null -eq $waker) { return [pscustomobject]@{ ok = $false; live = $false; waker = $null; banner = ""; reason = ("wake run -Live needs an installed waker to send its nudges through, and there is none: " + $why) } }
    return [pscustomobject]@{ ok = $true; live = $true; waker = $waker; reason = ""; banner = ("LIVE - REAL NUDGES are sent through the waker '" + $waker.name + "'. The restore source stays shadow: it journals what it would post and posts nothing") }
}

function Test-HordeWakeSendersShadow {
    # Do the two senders - the restore source and the tell sender - run shadow in this run? Always in a
    # shadow run; and in every other while THE ONE SWITCH is off (the top of this file).
    param([Parameter(Mandatory = $true)]$Run)
    if ($Run.live -ne $true) { return $true }
    return ($script:HordeWakeSendersPost -ne $true)
}

function Get-HordeWakeSenderFile {
    # Where a sender's marks are kept for this run: { name; mode }, for Get-HordeWakeStateFile. A shadow
    # run's are <stem>-shadow. A live run whose senders are shadow keeps them in a shadow file OF ITS
    # OWN, <stem>-of-live-run-shadow - not the shadow run's, which another process may be writing, and
    # not <stem>-live, which is for mail that was really posted. With the switch on, <stem>-live.
    param([Parameter(Mandatory = $true)]$Run, [Parameter(Mandatory = $true)][string]$Stem)
    if ($Run.live -ne $true) { return [pscustomobject]@{ name = $Stem; mode = "shadow" } }
    if (Test-HordeWakeSendersShadow -Run $Run) { return [pscustomobject]@{ name = ($Stem + "-of-live-run"); mode = "shadow" } }
    return [pscustomobject]@{ name = $Stem; mode = "live" }
}

function Invoke-HordeWakeTick {
    # ONE TICK, in the mode of -Run (the header). Changes -Run in place and returns the entries it
    # journaled. It never throws: what a part of it throws becomes a skip-unknown entry named after the
    # part, which the journal says once for as long as it lasts.
    #   -Waker         a registered waker, or $null when none is installed
    #   -ReadSessions  () -> Get-HordeRestoreSessions' answer; a test hands in its own, and the default
    #                  reads the two stores of this machine
    #   -TickSeconds   the loop's tick, written into the heartbeat so a reader knows what stale is
    #   -Messenger     what the two senders post through when they post at all (THE ONE SWITCH); found
    #                  through the messenger port when it is not given. A test hands in the in-process one.
    param(
        [Parameter(Mandatory = $true)]$Run,
        [Parameter(Mandatory = $true)][datetime]$Now,
        $Waker = $null,
        $Settings = (Get-HordeWakeSettings),
        $RestoreSettings = (Get-HordeRestoreSettings),
        [scriptblock]$ReadSessions = { Get-HordeRestoreSessions },
        [int]$TickSeconds = 3,
        [int]$ProcessId = 0,
        $Messenger = $null,
        [string]$HordeHome = (Get-HordeHome)
    )
    # ONLY A RUN MADE LIVE IS LIVE: anything else in that member - nothing, a word, a number - is shadow.
    $shadow = ($Run.live -ne $true)
    $Run.pass = [long]$Run.pass + 1
    $entries = New-Object System.Collections.ArrayList
    $failed = New-Object System.Collections.ArrayList
    # THE RESTORE SOURCE, every restoreEverySeconds, and SHADOW IN BOTH MODES (the header). What it could
    # not read is kept as notes and offered on every tick until the next reading, so it is journaled
    # once when it starts and not every 30 s.
    if (($Now - $Run.restoreAt).TotalSeconds -ge $script:HordeWakeRestoreEverySeconds) {
        $Run.restoreAt = $Now
        try {
            $read = & $ReadSessions
            if ((Test-HordeAnswer $read) -and $read.state -ceq "known") {
                $sourceShadow = Test-HordeWakeSendersShadow -Run $Run
                $sourcePoster = $null
                if (-not $sourceShadow) { $sourcePoster = { param($m) Send-HordeRestoreMail -Mail $m -Settings $RestoreSettings -Messenger $Messenger -HordeHome $HordeHome }.GetNewClosure() }
                $sourced = Invoke-HordeRestoreSourcePass -Sessions @($read.value) -Now $Now -Settings $RestoreSettings -Shadow:$sourceShadow -Post $sourcePoster -Posted $Run.posted -Known $Run.restores
                foreach ($e in @($sourced.entries)) { [void]$entries.Add($e) }
                $dirty = (@($sourced.entries).Count -gt 0 -or @($sourced.known).Count -ne @($Run.restores).Count -or $sourced.posted.Count -ne $Run.posted.Count)
                $Run.posted = $sourced.posted
                $Run.restores = @($sourced.known)
                if ($dirty) { Save-HordeRestoreState -Posted $Run.posted -Known $Run.restores -Name (Get-HordeWakeSenderFile -Run $Run -Stem "restore").name -Mode (Get-HordeWakeSenderFile -Run $Run -Stem "restore").mode -HordeHome $HordeHome }
                $left = @()
                $p = $read.PSObject.Properties["leftOut"]
                if ($null -ne $p) { $left = @($p.Value) }
                $Run.notes = @($left | ForEach-Object { [pscustomobject]@{ id = ("restore:" + $_.agent); reason = ("the restore source left out the " + $_.agent + " sessions, whose listing is not whole: " + $_.reason) } })
            } else {
                $why = "it answered with something that is not an answer"
                if (Test-HordeAnswer $read) { $why = "$($read.reason)" }
                $Run.notes = @([pscustomobject]@{ id = "restore"; reason = ("the restore source could not read the sessions: " + $why) })
            }
        } catch { $Run.notes = @([pscustomobject]@{ id = "restore"; reason = ("the restore source failed: " + $_.Exception.Message) }) }
    }
    foreach ($n in @($Run.notes)) { [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "skip-unknown" -Id $n.id -Outcome "unknown" -Reason $n.reason)) }
    # THE WAKE PASS, in the run's mode: this is the one call whose mode differs between the two.
    try {
        $result = Invoke-HordeWakePass -Waker $Waker -Now $Now -Settings $Settings -Ledger $Run.ledger -Shadow:$shadow
        # A FLEET THAT CANNOT BE READ (core/Wake.ps1, Update-HordeWakeFleetRead): permanent after ten failures
        # in a row - said once - and then the line for each unreadable pass is dropped until it works.
        $fleetRead = Update-HordeWakeFleetRead -Seen $Run.fleetRead -Listing $result.listing -Now $Now -Settings $Settings
        $Run.fleetRead = $fleetRead.seen
        foreach ($e in @($result.entries)) {
            if ($fleetRead.quiet -and $e.kind -ceq "skip-unknown" -and "$($e.id)" -ceq "") { continue }
            [void]$entries.Add($e)
        }
        foreach ($e in @($fleetRead.entries)) { [void]$entries.Add($e) }
        # MAIL NOBODY CAN READ, said once when it lasts two passes (core/Wake.ps1, Update-HordeWakeBadMail).
        $bad = Update-HordeWakeBadMail -Seen $Run.badMail -Unreadable $result.unreadable -Now $Now
        $Run.badMail = $bad.seen
        foreach ($e in @($bad.entries)) { [void]$entries.Add($e) }
        # WHAT THE WARCHIEF MUST HEAR (core/WakeTell.ps1): the four things this pass may have met.
        $conditions = New-Object System.Collections.ArrayList
        foreach ($g in @($result.gaveUp)) {
            $mail = "unknown"
            if ($g.mailAt -is [datetime]) { $mail = $g.mailAt.ToUniversalTime().ToString("o", [System.Globalization.CultureInfo]::InvariantCulture) }
            [void]$conditions.Add((New-HordeWakeTellCondition -Kind "gave-up" -Subject $g.id -Instance $mail -Text ("the session " + $g.id + " was nudged " + $g.attempts + " times for its mail unread since " + $mail + " and did not take it. It is not nudged again for that mail. Look at that session.")))
        }
        foreach ($e in @($result.entries | Where-Object { $_.kind -ceq "nudge-killed" })) {
            [void]$conditions.Add((New-HordeWakeTellCondition -Kind "nudge-killed" -Subject $e.id -Instance $Now.ToUniversalTime().ToString("o", [System.Globalization.CultureInfo]::InvariantCulture) -Text ("a nudge of the session " + $e.id + " had to be stopped part-way, and its input box may now hold the unsent line; while it does, that session cannot be woken. Look at its box. " + $e.reason)))
        }
        foreach ($e in @($bad.entries)) {
            [void]$conditions.Add((New-HordeWakeTellCondition -Kind "bad-mail" -Subject $e.id -Instance $Now.ToUniversalTime().ToString("yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture) -Text ("the mailbox of the session " + $e.id + " holds mail nobody can read: " + $e.reason)))
        }
        if ($null -ne $fleetRead.condition) { [void]$conditions.Add((New-HordeWakeTellCondition -Kind $fleetRead.condition.kind -Subject $fleetRead.condition.subject -Instance $fleetRead.condition.instance -Text $fleetRead.condition.text)) }
        # WHO THE WARCHIEF IS IS REMEMBERED from the last pass that could say: the pass on which the fleet
        # cannot be read is the one that most needs somebody told, and it is the one that cannot say who.
        if ("$($result.warchief)" -cne "") { $Run.warchief = "$($result.warchief)" }
        if ($conditions.Count -gt 0) {
            $sendersShadow = Test-HordeWakeSendersShadow -Run $Run
            $poster = $null
            if (-not $sendersShadow) { $poster = { param($m) Send-HordeWakeTell -Mail $m -Messenger $Messenger -HordeHome $HordeHome }.GetNewClosure() }
            $toldNow = Invoke-HordeWakeTellPass -Conditions $conditions.ToArray() -Warchief "$($Run.warchief)" -Now $Now -Shadow:$sendersShadow -Post $poster -Told $Run.told
            foreach ($e in @($toldNow.entries)) { [void]$entries.Add($e) }
            $Run.told = $toldNow.told
            $place = Get-HordeWakeSenderFile -Run $Run -Stem "tells"
            Save-HordeWakeTellState -Told $Run.told -Name $place.name -Mode $place.mode -HordeHome $HordeHome
        }
        $changed = (@($result.entries).Count -gt 0 -or $result.ledger.Count -ne $Run.ledger.Count)
        $Run.ledger = $result.ledger
        if ($changed) { Save-HordeWakeLedger -Ledger $Run.ledger -Shadow:$shadow -HordeHome $HordeHome }
    } catch { [void]$failed.Add([pscustomobject]@{ id = "pass"; reason = ("the wake pass failed: " + $_.Exception.Message) }) }
    # THE HEARTBEAT, whatever happened above: a tick that got this far is a watcher that is alive.
    try { Write-HordeWakeHeartbeat -At $Now -ProcessId $ProcessId -Pass $Run.pass -TickSeconds $TickSeconds -Shadow:$shadow -HordeHome $HordeHome }
    catch { [void]$failed.Add([pscustomobject]@{ id = "heartbeat"; reason = ("the heartbeat could not be written: " + $_.Exception.Message) }) }
    foreach ($f in @($failed)) { [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "skip-unknown" -Id $f.id -Outcome "unknown" -Reason $f.reason)) }
    $fresh = Select-HordeWakeNewEntries -Entries $entries.ToArray() -Unknown $Run.unknown
    $Run.unknown = $fresh.unknown
    # THE JOURNAL LAST, and its own failure is the one thing a tick can only hand back: the caller
    # prints the entries it returns, so they are not lost with the file.
    try { $null = Write-HordeWakeJournal -Entries $fresh.entries -Shadow:$shadow -HordeHome $HordeHome }
    catch { return @(@($fresh.entries) + (New-HordeWakeEntry -At $Now -Kind "skip-unknown" -Id "journal" -Outcome "unknown" -Reason ("the journal could not be written: " + $_.Exception.Message))) }
    return @($fresh.entries)
}
