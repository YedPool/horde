# fleet/Asleep.ps1 - which sessions are asleep in a hibernation now, for the wake watcher.
#
# WHY. A hibernated session is ended with its own exit command (fleet/Hibernate.ps1), and the pane it sat
# in is left holding the shell it ran in. The wake watcher (core/Wake.ps1) knocks on any session with
# unread mail, and a hibernated session goes on receiving mail - a knock there would type the fleet's
# pointer line into that shell, or start nothing at all and be counted against it. So while a session is
# asleep the watcher does not knock: it is skipped, said once, and its mail queues for when it is woken,
# whose own mail tells it to read what was left for it (fleet/Wake.ps1).
#
# ASLEEP IS TWO THINGS AT ONCE (T-0216): the session is in a hibernation record as asleep, AND its process
# is not running. By the newest record that holds the session (records are named by the time they were
# taken, so the newest is the last word): its state is exited; or it is waking or failed with an exit in its
# history - a wake has started its pane, or tried to and could not tell it came up, and a knock then
# would type into a pane whose program may be the shell. woken, still-awake, recorded, asked and parked
# are awake: the session runs, or was never ended. And a session such a record names that runs again - a
# hand restart, a terminal restore, a wake that did not write its record - is awake whatever the record
# says: the harness's own liveness rule (the adapter's verdict, asked as a wake asks it) decides, so a
# stale record never silences a live session. A session not PROVEN running stays asleep: a knock on a shell
# is the harm, and its mail only queues.
#
# A RECORD THAT CANNOT BE READ IS SKIPPED, REPORTED, AND THE WATCHER CARRIES ON (T-0216). It used to make
# the whole answer unknown, and the watcher knocked on nobody for as long as one corrupt file lay there; a
# fleet's mail stopped for a file nobody was told about. The answer now carries `skipped`, one line each
# naming the record, and the watcher journals them (core/WakeRun.ps1). What still makes the answer unknown
# is the liveness reading: with no word on which processes run, "asleep" cannot be told.
# A folder with no record.json is skipped quietly: a record is written whole by rename, so such a
# folder is one whose record was never written, and it holds nobody.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). It runs under -Version Latest
# when the watcher loads it, so every member it reads may be missing and is read through
# Get-HordeFleetAsleepMember.
. (Join-Path $PSScriptRoot "Hibernation.ps1")
# The wake's own readings of a session's id and of from when a stranger could be it (Get-HordeFleetSince).
. (Join-Path $PSScriptRoot "Wake.ps1")

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
    # The sessions asleep now, as an answer: known map session id -> one line saying where and since when,
    # with `skipped` (one line per record that could not be read); unknown, naming the reason, when which
    # processes run cannot be read. No hibernations at all is known and empty. -Agent is the harness adapter
    # whose liveness decides (fleet/Port.ps1); when not given, the one loaded one.
    # A SESSION A RECORD HOLDS THAT RUNS has its stale "hibernated" no-restore marker removed through the host
    # (-HostAdapter, fleet/Port.ps1, Unmark; when not given, the one loaded host if there is one), so a hand
    # restart does not leave it barred from the next terminal restore (T-0216). The answer's `cleared` lists
    # what was said about a marker, one line each.
    # -KeepMarkers: a watcher that must change nothing (SHADOW or PROOF) reads who sleeps and removes no marker.
    param([string]$HordeHome = (Get-HordeHome), $Agent = $null, $HostAdapter = $null, [switch]$KeepMarkers)
    $dir = Get-HordeFleetHibernationsDir -HordeHome $HordeHome
    $out = @{}
    $skipped = New-Object System.Collections.ArrayList
    $running = New-Object System.Collections.ArrayList
    $done = {
        param($map)
        $cleared = @()
        if ($running.Count -gt 0 -and -not $KeepMarkers) {
            $h = $HostAdapter
            if ($null -eq $h) { $foundHost = Resolve-HordeFleetAdapter -Kind "host"; if ($foundHost.state -ceq "known") { $h = $foundHost.value } }
            $cleared = @(Clear-HordeFleetHibernatedMarker -HostAdapter $h -Ids @($running))
        }
        $a = New-HordeKnown -Value $map
        Add-Member -InputObject $a -MemberType NoteProperty -Name "skipped" -Value @($skipped)
        Add-Member -InputObject $a -MemberType NoteProperty -Name "cleared" -Value @($cleared)
        return $a
    }
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return (& $done $out) }
    $ids = @()
    try { $ids = @(Get-ChildItem -LiteralPath $dir -Directory -ErrorAction Stop | ForEach-Object { $_.Name } | Where-Object { $_ -cmatch $script:HordeFleetIdPattern } | Sort-Object) }
    catch { return (New-HordeUnknown -Reason ("the hibernations folder could not be listed: " + $_.Exception.Message)) }
    $last = @{}
    foreach ($id in $ids) {
        if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $dir $id) "record.json") -PathType Leaf)) { continue }
        $read = Read-HordeFleetRecord -Id $id -HordeHome $HordeHome
        if ($read.state -cne "known") { [void]$skipped.Add("hibernation " + $id + " is skipped, its record cannot be read: " + $read.reason); continue }
        foreach ($s in @(Get-HordeFleetAsleepMember $read.value "sessions")) { $last["" + $s.sessionId] = [pscustomobject]@{ id = $id; record = $read.value; session = $s } }
    }
    $sleepers = @($last.Keys | Where-Object { Test-HordeFleetSessionAsleep -Session $last[$_].session })
    if ($sleepers.Count -eq 0) { return (& $done $out) }
    # WHICH PROCESSES RUN, asked as a wake asks it, so the two agree on who is gone.
    $adapter = $Agent
    if ($null -eq $adapter) {
        $found = Resolve-HordeFleetAdapter -Kind "agent"
        if ($found.state -cne "known") { return (New-HordeUnknown -Reason ("which sessions are asleep cannot be told, because which run cannot: " + $found.reason)) }
        $adapter = $found.value
    }
    $snapshot = $null
    try { $snapshot = & $adapter.snapshot } catch { return (New-HordeUnknown -Reason ("which sessions are asleep cannot be told, because which run cannot be read: " + $_.Exception.Message)) }
    foreach ($sid in $sleepers) {
        $s = $last[$sid].session
        $rec = $last[$sid].record
        $recordIds = @(@(Get-HordeFleetAsleepMember $rec "sessions") | ForEach-Object { "" + $_.sessionId; $w = "" + (Get-HordeFleetAsleepMember $_ "wokenAs"); if ($w -ne "") { $w } })
        $v = $null
        try { $v = & $adapter.verdict $snapshot (Get-HordeFleetCurrentId -Session $s) ("" + (Get-HordeFleetAsleepMember $s "cwd")) $recordIds (Get-HordeFleetSince -Session $s -Record $rec) (Get-HordeFleetAsleepMember $s "process") }
        catch { return (New-HordeUnknown -Reason ("which sessions are asleep cannot be told, because whether " + $sid + " runs cannot be read: " + $_.Exception.Message)) }
        if ($null -eq $v) { return (New-HordeUnknown -Reason ("which sessions are asleep cannot be told, because the harness answered nothing about " + $sid)) }
        if ("" + (Get-HordeFleetAsleepMember $v "kind") -ceq "reading") { return (New-HordeUnknown -Reason ("which sessions are asleep cannot be told, because which run cannot be read: " + (Get-HordeFleetAsleepMember $v "reason"))) }
        if ("" + (Get-HordeFleetAsleepMember $v "state") -ceq "running") {
            # RUNNING, so not asleep, and any hibernated marker it still carries is stale: its ids are collected
            # (the record's own and the one it came back as) for the marker to go once the answer is made.
            [void]$running.Add("" + $sid); [void]$running.Add("" + (Get-HordeFleetCurrentId -Session $s))
            continue
        }
        $since = ""
        foreach ($h in @(Get-HordeFleetAsleepMember $s "history")) { if ("" + (Get-HordeFleetAsleepMember $h "state") -ceq "exited") { $since = "" + (Get-HordeFleetAsleepMember $h "at") } }
        $out[$sid] = "asleep in hibernation " + $last[$sid].id + " since " + $since + " (" + $s.state + ")"
    }
    return (& $done $out)
}
