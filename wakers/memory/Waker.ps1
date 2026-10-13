# wakers/memory - a waker inside one process, for tests only.
#
# WHY IT EXISTS. The wake watcher's rules (core/Wake.ps1) - when a session is nudged, how it backs off,
# who goes first, what a restore of everything looks like - are tested end to end without any real
# session, input box or mailbox; this is the waker they run on. It DECLINES reach.unseen in its
# capabilities.json, and the production path requires it (Resolve-HordeProductionWaker in
# wakers/Port.ps1), so no production path can pick it. The port and conformance suites prove both
# halves of that.
#
# THE STORE is a table in this script scope, keyed by session id: what a test says the session is
# (Set-HordeMemoryWakerSession), read back as the port asks for it. Every nudge it is asked for is
# recorded (Get-HordeMemoryWakerNudges) with the one line a real waker would have typed, and nothing
# else happens: a nudge takes no mail, because mail is taken by a session, and here the test plays it.
# A test can also make any of the three calls throw or answer rubbish (Set-HordeMemoryWakerFault), to
# show the watcher never nudges on an answer it could not read. Nothing else in Horde calls these.

$script:HordeMemoryWakerSessions = [ordered]@{}
$script:HordeMemoryWakerNudges = New-Object System.Collections.ArrayList
$script:HordeMemoryWakerAsks = New-Object System.Collections.ArrayList
$script:HordeMemoryWakerBegins = 0
$script:HordeMemoryWakerLooks = New-Object System.Collections.ArrayList
$script:HordeMemoryWakerReads = New-Object System.Collections.ArrayList
$script:HordeMemoryWakerCheap = $false
$script:HordeMemoryWakerFaults = @{}
$script:HordeMemoryWakerClock = $null
# THE ONE LINE A NUDGE TYPES: fixed, the same for every session and every mail, and no part of a body.
$script:HordeMemoryWakerPointer = "You have unread mail. Read it now."

function Reset-HordeMemoryWaker {
    # Empty the store, the record of nudges, the faults and the clock, so each test starts from nothing.
    $script:HordeMemoryWakerSessions = [ordered]@{}
    $script:HordeMemoryWakerNudges = New-Object System.Collections.ArrayList
    $script:HordeMemoryWakerAsks = New-Object System.Collections.ArrayList
    $script:HordeMemoryWakerBegins = 0
    $script:HordeMemoryWakerLooks = New-Object System.Collections.ArrayList
    $script:HordeMemoryWakerReads = New-Object System.Collections.ArrayList
    $script:HordeMemoryWakerCheap = $false
    $script:HordeMemoryWakerFaults = @{}
    $script:HordeMemoryWakerClock = $null
}

function Get-HordeMemoryWakerReads {
    # The sessions whose state this waker was asked for since the last reset, in order, looks included:
    # how a test sees that a session was never so much as read.
    return @($script:HordeMemoryWakerReads | ForEach-Object { "$_" })
}

function Set-HordeMemoryWakerClock {
    # The time this waker stamps its answers with; $null puts the real clock back.
    param($Now)
    $script:HordeMemoryWakerClock = $Now
}

function Get-HordeMemoryWakerTime {
    if ($null -ne $script:HordeMemoryWakerClock) { return ([datetime]$script:HordeMemoryWakerClock) }
    return [datetime]::UtcNow
}

function Set-HordeMemoryWakerSession {
    # Says what one session is, whole: a session not named before is added, and one named before is
    # replaced. -Outcome is what a nudge of it answers. A word outside the port's lists is accepted on
    # purpose: a test of the port's refusals needs a waker that says the wrong thing.
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [string]$Label = "",
        [string]$Role = "warg",
        [string]$Parent = "",
        [string]$Reachable = "yes",
        [string]$Retired = "no",
        [int]$UnreadCount = 0,
        $OldestUnreadAt = $null,
        [string]$Idle = "yes",
        [string]$BoxEmpty = "yes",
        [string]$MidTurn = "no",
        [string]$Outcome = "woken",
        [string]$OutcomeReason = "",
        $UnreadableCount = $null,
        [string]$Limited = "no",
        $LimitedUntil = $null
    )
    $script:HordeMemoryWakerSessions[$Id] = @{ id = $Id; label = $Label; role = $Role; parent = $Parent; reachable = $Reachable; retired = $Retired; unreadCount = $UnreadCount;
        oldestUnreadAt = $OldestUnreadAt; idle = $Idle; boxEmpty = $BoxEmpty; midTurn = $MidTurn; outcome = $Outcome; outcomeReason = $OutcomeReason; unreadableCount = $UnreadableCount; limited = $Limited; limitedUntil = $LimitedUntil }
}

function Set-HordeMemoryWakerFault {
    # Makes one call misbehave from now on: -Call targets, state or nudge; -Kind throw (the call throws),
    # garbage (it answers with something that is not an answer), or "" (it behaves again).
    param([Parameter(Mandatory = $true)][ValidateSet("targets", "state", "nudge")][string]$Call, [ValidateSet("", "throw", "garbage")][string]$Kind = "")
    $script:HordeMemoryWakerFaults[$Call] = $Kind
}

function Get-HordeMemoryWakerNudges {
    # Every nudge this waker was asked for and rang since the last reset, in order: { id; at; text }.
    # For one session with -Id.
    param([string]$Id = "")
    $all = @($script:HordeMemoryWakerNudges | ForEach-Object { $_ })
    if ($Id -ne "") { return @($all | Where-Object { $_.id -ceq $Id }) }
    return $all
}

function Get-HordeMemoryWakerAsks {
    # The session of every nudge this waker was ASKED for since the last reset, in order, whatever it
    # answered: a test of who holds the one nudge a pass allows counts the asks, not the rings.
    return @($script:HordeMemoryWakerAsks | ForEach-Object { "$_" })
}

function Set-HordeMemoryWakerCheap {
    # Plays a waker whose State is cheap: with -On, State answers the box and the turn unknown whatever
    # the session holds, and only the full reading (the port's Confirm) says them - as a waker that reads
    # a whole fleet in one call does. Off, which is how it starts, State says everything.
    param([bool]$On)
    $script:HordeMemoryWakerCheap = $On
}

function Get-HordeMemoryWakerLooks {
    # The session of every full reading this waker was asked for since the last reset, in order.
    return @($script:HordeMemoryWakerLooks | ForEach-Object { "$_" })
}

function Get-HordeMemoryWakerState {
    # One session's state as an answer; -Full is the full reading, which a cheap waker's State is not.
    param([string]$Id, [switch]$Full)
    [void]$script:HordeMemoryWakerReads.Add($Id)
    if (Invoke-HordeMemoryWakerFault "state") { return @{ idle = "yes"; boxEmpty = "yes" } }
    if (-not $script:HordeMemoryWakerSessions.Contains($Id)) { return (New-HordeUnknown -Reason ("the memory waker has no session " + $Id)) }
    $s = $script:HordeMemoryWakerSessions[$Id]
    $value = [ordered]@{ id = $s.id; unreadCount = $s.unreadCount; oldestUnreadAt = $s.oldestUnreadAt; idle = $s.idle; boxEmpty = $s.boxEmpty; midTurn = $s.midTurn }
    if ($script:HordeMemoryWakerCheap -and -not $Full) { $value["boxEmpty"] = "unknown"; $value["midTurn"] = "unknown" }
    # Reported only when a test said so: left out, the port reads it as none.
    if ($null -ne $s.unreadableCount) { $value["unreadableCount"] = $s.unreadableCount }
    $value["limited"] = $s.limited
    if ($null -ne $s.limitedUntil) { $value["limitedUntil"] = $s.limitedUntil }
    return (New-HordeKnown -Value ([pscustomobject]$value) -ObservedAt (Get-HordeMemoryWakerTime))
}

function Get-HordeMemoryWakerBegins {
    # How many times this waker was told a pass begins, since the last reset.
    return $script:HordeMemoryWakerBegins
}

function Invoke-HordeMemoryWakerFault {
    # Throws when -Call is set to throw; returns $true when it is set to answer rubbish.
    param([string]$Call)
    $kind = ""
    if ($script:HordeMemoryWakerFaults.ContainsKey($Call)) { $kind = "$($script:HordeMemoryWakerFaults[$Call])" }
    if ($kind -ceq "throw") { throw ("the memory waker was told to fail its " + $Call) }
    return ($kind -ceq "garbage")
}

$null = Register-HordeWaker -Name "memory" `
    -Targets {
        if (Invoke-HordeMemoryWakerFault "targets") { return "not an answer" }
        $list = @($script:HordeMemoryWakerSessions.Values | ForEach-Object { [pscustomobject]@{ id = $_.id; label = $_.label; role = $_.role; parent = $_.parent; reachable = $_.reachable; retired = $_.retired } })
        return (New-HordeKnown -Value $list -ObservedAt (Get-HordeMemoryWakerTime))
    } `
    -State { param([string]$Id) Get-HordeMemoryWakerState -Id $Id } `
    -Confirm { param([string]$Id) [void]$script:HordeMemoryWakerLooks.Add($Id); Get-HordeMemoryWakerState -Id $Id -Full } `
    -Nudge {
        param([string]$Id)
        if (Invoke-HordeMemoryWakerFault "nudge") { return $true }
        if (-not $script:HordeMemoryWakerSessions.Contains($Id)) { return (New-HordeUnknown -Reason ("the memory waker has no session " + $Id)) }
        $s = $script:HordeMemoryWakerSessions[$Id]
        $at = Get-HordeMemoryWakerTime
        [void]$script:HordeMemoryWakerAsks.Add($Id)
        # THE NUDGE GUARDS ITSELF (wakers/Port.ps1): the box and the turn as they are NOW, whatever the
        # watcher read a moment ago. A test changes the session between the two to show it.
        if ("$($s.boxEmpty)" -cne "yes") { return (New-HordeKnown -Value ([pscustomobject]@{ id = $Id; outcome = "busy"; reason = "its input box is not empty, so nothing was typed"; at = $at }) -ObservedAt $at) }
        if ("$($s.midTurn)" -cne "no") { return (New-HordeKnown -Value ([pscustomobject]@{ id = $Id; outcome = "busy"; reason = "it is in the middle of a turn, so nothing was typed"; at = $at }) -ObservedAt $at) }
        # RECORDED ONLY WHEN IT WOULD HAVE BEEN TYPED: busy, unreachable and nothing are the waker saying
        # it did not ring, so nothing was typed for them; killed is a nudge stopped part-way, which a
        # test asks for by name.
        if ("$($s.outcome)" -ceq "woken") { [void]$script:HordeMemoryWakerNudges.Add([pscustomobject]@{ id = $Id; at = $at; text = $script:HordeMemoryWakerPointer }) }
        return (New-HordeKnown -Value ([pscustomobject]@{ id = $Id; outcome = $s.outcome; reason = $s.outcomeReason; at = $at }) -ObservedAt $at)
    } `
    -Begin { $script:HordeMemoryWakerBegins++ }
