# fleet/Asleep.ps1 - which sessions are asleep in a hibernation now, for the wake watcher.
#
# WHY. A hibernated session is ended with its own exit command (fleet/Hibernate.ps1), and the pane it sat
# in is left holding the shell it ran in. The wake watcher (core/Wake.ps1) knocks on any session with
# unread mail, and a hibernated session goes on receiving mail - a knock there would type the fleet's
# pointer line into that shell, or start nothing at all and be counted against it. So while a session is
# asleep the watcher does not knock: it is skipped, said once, and its mail queues for when it is woken,
# whose own mail tells it to read what was left for it (fleet/Wake.ps1).
#
# ASLEEP, by the newest record that holds the session (records are named by the time they were taken, so
# the newest is the last word): its state is exited; or it is waking or failed with an exit in its
# history - a wake has started its pane, or tried to and could not tell it came up, and a knock then
# would type into a pane whose program may be the shell. woken, still-awake, recorded, asked and parked
# are awake: the session runs, or was never ended.
#
# FAIL CLOSED: a record that cannot be read makes the whole answer unknown, and the watcher then knocks on
# nobody until it can be read (core/Wake.ps1), because the unreadable record may be the one that says a
# session sleeps. A folder with no record.json is skipped: a record is written whole by rename, so such a
# folder is one whose record was never written, and it holds nobody.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). It runs under -Version Latest
# when the watcher loads it, so every member it reads may be missing and is read through
# Get-HordeFleetAsleepMember.
. (Join-Path $PSScriptRoot "Hibernation.ps1")

function Get-HordeFleetAsleepMember {
    # A member of a parsed record that may be left out, or $null - safe under strict mode.
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Test-HordeFleetSessionAsleep {
    # Is one session of a record asleep by the rule in the header?
    param([Parameter(Mandatory = $true)]$Session)
    $state = "" + (Get-HordeFleetAsleepMember $Session "state")
    if ($state -ceq "exited") { return $true }
    if (@("waking", "failed") -ccontains $state) {
        foreach ($h in @(Get-HordeFleetAsleepMember $Session "history")) { if ("" + (Get-HordeFleetAsleepMember $h "state") -ceq "exited") { return $true } }
    }
    return $false
}

function Get-HordeFleetAsleep {
    # The sessions asleep now, as an answer: known map session id -> one line saying where and since when;
    # unknown, naming the record, when one cannot be read. No hibernations at all is known and empty.
    param([string]$HordeHome = (Get-HordeHome))
    $dir = Get-HordeFleetHibernationsDir -HordeHome $HordeHome
    $out = @{}
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return (New-HordeKnown -Value $out) }
    $ids = @()
    try { $ids = @(Get-ChildItem -LiteralPath $dir -Directory -ErrorAction Stop | ForEach-Object { $_.Name } | Where-Object { $_ -cmatch $script:HordeFleetIdPattern } | Sort-Object) }
    catch { return (New-HordeUnknown -Reason ("the hibernations folder could not be listed: " + $_.Exception.Message)) }
    $last = @{}
    foreach ($id in $ids) {
        if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $dir $id) "record.json") -PathType Leaf)) { continue }
        $read = Read-HordeFleetRecord -Id $id -HordeHome $HordeHome
        if ($read.state -cne "known") { return (New-HordeUnknown -Reason ("which sessions are asleep cannot be told: " + $read.reason)) }
        foreach ($s in @(Get-HordeFleetAsleepMember $read.value "sessions")) { $last["" + $s.sessionId] = [pscustomobject]@{ id = $id; session = $s } }
    }
    foreach ($sid in @($last.Keys)) {
        $s = $last[$sid].session
        if (-not (Test-HordeFleetSessionAsleep -Session $s)) { continue }
        $since = ""
        foreach ($h in @(Get-HordeFleetAsleepMember $s "history")) { if ("" + (Get-HordeFleetAsleepMember $h "state") -ceq "exited") { $since = "" + (Get-HordeFleetAsleepMember $h "at") } }
        $out[$sid] = "asleep in hibernation " + $last[$sid].id + " since " + $since + " (" + $s.state + ")"
    }
    return (New-HordeKnown -Value $out)
}
