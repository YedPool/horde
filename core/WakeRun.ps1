# core/WakeRun - one tick of `horde wake run`: the wake pass, the restore source beside it, and the files.
#
# WHY NOT IN THE COMMAND. The loop was written in cli/commands/wake.ps1, where no suite could drive it,
# and the review of PR #207 found what that hid:
#   - NOTHING CAUGHT AN ERROR. One failed rename of the heartbeat ended the loop, and with it the only
#     process that wakes anybody. A tick now catches what each of its parts throws, journals it once
#     for as long as it lasts, and returns; the loop goes on.
#   - -Shadow WAS A WORD AT TWO CALL SITES, and deleting it there passed every suite. A tick here is a
#     SHADOW tick by its name and by construction: this file makes both passes with -Shadow and offers
#     no parameter that could take it away, so the command has nothing to drop. When the first real
#     waker lands, the live tick is a function of its own, added here beside its tests.
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

# How often a tick runs the restore source.
$script:HordeWakeRestoreEverySeconds = 30

function New-HordeWakeShadowRun {
    # What a shadow run carries from tick to tick, read from the shadow run's own files (core/WakeFiles.ps1,
    # Get-HordeWakeStateFile): { ledger; posted; restores; unknown; notes; badMail; restoreAt; pass; said }. said is
    # what the caller should print once: a saved file that could not be read is started from empty, and
    # says so.
    param([string]$HordeHome = (Get-HordeHome))
    $run = [pscustomobject]@{ ledger = @{}; posted = @{}; restores = @(); unknown = @{}; notes = @(); badMail = @{}; restoreAt = [datetime]::MinValue; pass = [long]0; said = @() }
    $saved = Read-HordeWakeLedger -Shadow -HordeHome $HordeHome
    if ($saved.state -ceq "known") { $run.ledger = $saved.value.ledger }
    elseif ($saved.state -ceq "unknown") { $run.said = @($run.said) + ("starting from an empty ledger - " + $saved.reason) }
    $savedRestore = Read-HordeRestoreState -Shadow -HordeHome $HordeHome
    if ($savedRestore.state -ceq "known") { $run.posted = $savedRestore.value.posted; $run.restores = @($savedRestore.value.known) }
    elseif ($savedRestore.state -ceq "unknown") { $run.said = @($run.said) + ("starting with no mail marked posted - " + $savedRestore.reason) }
    return $run
}

function Invoke-HordeWakeShadowTick {
    # ONE SHADOW TICK. Changes -Run in place and returns the entries it journaled. It nudges nobody and
    # posts nothing (the header), and it never throws: what a part of it throws becomes a skip-unknown
    # entry named after the part, which the journal says once for as long as it lasts.
    #   -Waker         a registered waker, or $null when none is installed
    #   -ReadSessions  () -> Get-HordeRestoreSessions' answer; a test hands in its own, and the default
    #                  reads the two stores of this machine
    #   -TickSeconds   the loop's tick, written into the heartbeat so a reader knows what stale is
    param(
        [Parameter(Mandatory = $true)]$Run,
        [Parameter(Mandatory = $true)][datetime]$Now,
        $Waker = $null,
        $Settings = (Get-HordeWakeSettings),
        $RestoreSettings = (Get-HordeRestoreSettings),
        [scriptblock]$ReadSessions = { Get-HordeRestoreSessions },
        [int]$TickSeconds = 3,
        [int]$ProcessId = 0,
        [string]$HordeHome = (Get-HordeHome)
    )
    $Run.pass = [long]$Run.pass + 1
    $entries = New-Object System.Collections.ArrayList
    $failed = New-Object System.Collections.ArrayList
    # THE RESTORE SOURCE, every restoreEverySeconds. What it could not read is kept as notes and offered
    # on every tick until the next reading, so it is journaled once when it starts and not every 30 s.
    if (($Now - $Run.restoreAt).TotalSeconds -ge $script:HordeWakeRestoreEverySeconds) {
        $Run.restoreAt = $Now
        try {
            $read = & $ReadSessions
            if ((Test-HordeAnswer $read) -and $read.state -ceq "known") {
                $sourced = Invoke-HordeRestoreSourcePass -Sessions @($read.value) -Now $Now -Settings $RestoreSettings -Shadow -Posted $Run.posted -Known $Run.restores
                foreach ($e in @($sourced.entries)) { [void]$entries.Add($e) }
                $dirty = (@($sourced.entries).Count -gt 0 -or @($sourced.known).Count -ne @($Run.restores).Count -or $sourced.posted.Count -ne $Run.posted.Count)
                $Run.posted = $sourced.posted
                $Run.restores = @($sourced.known)
                if ($dirty) { Save-HordeRestoreState -Posted $Run.posted -Known $Run.restores -Shadow -HordeHome $HordeHome }
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
    # THE WAKE PASS.
    try {
        $result = Invoke-HordeWakePass -Waker $Waker -Now $Now -Settings $Settings -Ledger $Run.ledger -Shadow
        foreach ($e in @($result.entries)) { [void]$entries.Add($e) }
        # MAIL NOBODY CAN READ, said once when it lasts two passes (core/Wake.ps1, Update-HordeWakeBadMail).
        $bad = Update-HordeWakeBadMail -Seen $Run.badMail -Unreadable $result.unreadable -Now $Now
        $Run.badMail = $bad.seen
        foreach ($e in @($bad.entries)) { [void]$entries.Add($e) }
        $changed = (@($result.entries).Count -gt 0 -or $result.ledger.Count -ne $Run.ledger.Count)
        $Run.ledger = $result.ledger
        if ($changed) { Save-HordeWakeLedger -Ledger $Run.ledger -Shadow -HordeHome $HordeHome }
    } catch { [void]$failed.Add([pscustomobject]@{ id = "pass"; reason = ("the wake pass failed: " + $_.Exception.Message) }) }
    # THE HEARTBEAT, whatever happened above: a tick that got this far is a watcher that is alive.
    try { Write-HordeWakeHeartbeat -At $Now -ProcessId $ProcessId -Pass $Run.pass -TickSeconds $TickSeconds -Shadow -HordeHome $HordeHome }
    catch { [void]$failed.Add([pscustomobject]@{ id = "heartbeat"; reason = ("the heartbeat could not be written: " + $_.Exception.Message) }) }
    foreach ($f in @($failed)) { [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "skip-unknown" -Id $f.id -Outcome "unknown" -Reason $f.reason)) }
    $fresh = Select-HordeWakeNewEntries -Entries $entries.ToArray() -Unknown $Run.unknown
    $Run.unknown = $fresh.unknown
    # THE JOURNAL LAST, and its own failure is the one thing a tick can only hand back: the caller
    # prints the entries it returns, so they are not lost with the file.
    try { $null = Write-HordeWakeJournal -Entries $fresh.entries -HordeHome $HordeHome }
    catch { return @(@($fresh.entries) + (New-HordeWakeEntry -At $Now -Kind "skip-unknown" -Id "journal" -Outcome "unknown" -Reason ("the journal could not be written: " + $_.Exception.Message))) }
    return @($fresh.entries)
}
