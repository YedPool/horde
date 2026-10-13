# DOES EVERY WAKER DO WHAT ITS capabilities.json SAYS, AND NOTHING IT DOES NOT?
#
# Generated from each waker's capabilities.json, as the messenger conformance suite is from each
# messenger's: this suite names no waker. It loads every wakers/<name>/Waker.ps1 and that waker's test
# fixture, and for each capability:
#   - a "yes" must be DEMONSTRATED by the case below, or the suite fails;
#   - any other word must be refused where it is required: a caller that asks for it by name is
#     refused, naming it, and the production path (Resolve-HordeProductionWaker) never returns that
#     waker. And for the two state capabilities, a waker that does not offer one is held to saying
#     unknown of it: it may not answer yes or no about a box or a turn it cannot read.
# A capability added to the closed list with no case here fails the suite, so the list and the cases
# cannot drift apart.
#
# THE FIXTURE. wakers/<name>/test/Fixture.ps1, run with -Root, returns one object of script blocks:
#   New      ()                      -> a state, everything the waker reads and writes kept inside it
#   Remove   param($State)
#   Seat     param($State, $Session) - makes ONE fake session the waker can see, as $Session describes
#            it: { id; label; role; parent; unreadCount; oldestUnreadAt; idle (yes or no); boxEmpty (yes
#            or no); midTurn (yes or no); body; unseen }. body is the text of its unread mail, put where
#            the waker's mail really is; unseen, true, means it has taken no turn since a restore.
#   Observe  param($State, $Id)      -> { nudges; typed }, READ FROM WHAT THE WAKER ACTUALLY DID to the
#            fake session, never from the waker's own answer: nudges, how many times it was rung;
#            typed, every text typed into it during the state's life.
# A fixture writes nothing outside the temp folder, touches no pane and no real session's mail.
#
# WHAT A TYPED TEXT MAY BE. Only the pointer line is ever typed: one line, no control character, never
# any part of a mail's body, and the same line whatever the mail says. Every case holds every typed text
# to that, so a waker that typed a body fails whichever case was running.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "test\lib\FleetPin.ps1")
. (Join-Path $root "test\lib\MessengerPins.ps1")
# PINNED before any waker is loaded: a waker may find a fleet or a program on its own. Under this home
# and this empty fleet, no case - and nothing a waker starts - can reach a real session.
$fleetPin = Enter-HordeTestEmptyFleet
$pinned = Enter-HordeTestPinnedHome -Root $root
. (Join-Path $root "wakers\Port.ps1")
foreach ($f in @(Get-HordeWakerFiles)) { . $f }

$t0 = New-Object System.DateTime(2026, 10, 12, 8, 0, 0, [System.DateTimeKind]::Utc)
$script:seq = 0
function New-Seat {
    # A fresh session description: idle, empty box, one unread mail a minute old. Every case uses its
    # own id and its own body, so no case can see another's session.
    param([hashtable]$Change = @{})
    $script:seq++
    $s = @{
        id = ("0a000000-0000-4000-8000-" + $script:seq.ToString("000000000000")); label = "A"; role = "orc"; parent = ""
        unreadCount = 1; oldestUnreadAt = $t0; idle = "yes"; boxEmpty = "yes"; midTurn = "no"; unseen = $false
        # Two lines: a body cut at a newline, or typed, would show its first line.
        body = ("conformance body " + [guid]::NewGuid().ToString("N") + "`nsecond line " + [guid]::NewGuid().ToString("N"))
    }
    foreach ($k in $Change.Keys) { $s[$k] = $Change[$k] }
    return [pscustomobject]$s
}

function Test-TypedClean {
    # Every typed text is a pointer line: one line, no control character, and none of the body - checked
    # against each line of the body.
    param($Observed, [string]$Body)
    foreach ($t in @($Observed.typed)) {
        if ("$t" -cmatch '[\x00-\x1F\x7F]') { return $false }
        foreach ($line in @($Body -split "`n" | Where-Object { $_.Trim() -ne "" })) { if ("$t".Contains($line.Trim())) { return $false } }
    }
    return $true
}

# Every capability of the closed list must have a case here. Each case gets the waker, its fixture and
# a fresh state, and returns $true when the capability was shown.
$cases = [ordered]@{
    "nudge.pointer-only" = {
        param($W, $Fx, $State)
        $one = New-Seat; $two = New-Seat
        & $Fx.Seat $State $one; & $Fx.Seat $State $two
        $a1 = Send-HordeWakeNudge -Waker $W -Id $one.id
        $a2 = Send-HordeWakeNudge -Waker $W -Id $two.id
        $o1 = & $Fx.Observe $State $one.id
        $o2 = & $Fx.Observe $State $two.id
        # RUNG ONCE EACH, with one line, and THE SAME LINE for two sessions holding different mail.
        $rang = ($a1.state -ceq "known" -and $a1.value.outcome -ceq "woken" -and $a2.state -ceq "known" -and $a2.value.outcome -ceq "woken" -and $o1.nudges -eq 1 -and $o2.nudges -eq 1)
        $typed = (@($o1.typed).Count -eq 1 -and @($o2.typed).Count -eq 1)
        return ($rang -and $typed -and "$(@($o1.typed)[0])" -ceq "$(@($o2.typed)[0])" -and (Test-TypedClean $o1 $one.body) -and (Test-TypedClean $o2 $two.body))
    }
    "state.box" = {
        param($W, $Fx, $State)
        $empty = New-Seat; $full = New-Seat @{ boxEmpty = "no" }
        & $Fx.Seat $State $empty; & $Fx.Seat $State $full
        # THE FULL READING: a waker whose state is cheap says the box only when it is asked to look.
        $a1 = Get-HordeWakeState -Waker $W -Id $empty.id -Full
        $a2 = Get-HordeWakeState -Waker $W -Id $full.id -Full
        # BOTH ANSWERS: a waker that always said yes would pass a check that seated only an empty box.
        return ($a1.state -ceq "known" -and $a1.value.boxEmpty -ceq "yes" -and $a2.state -ceq "known" -and $a2.value.boxEmpty -ceq "no")
    }
    "state.turn" = {
        param($W, $Fx, $State)
        # MID-TURN WHILE ITS STATUS STILL SAYS IDLE: the case the turn is read for. A session whose status
        # already says it is not idle is waited for whatever its turn is, and a waker may leave its
        # pane unread and answer unknown there (the wezfleet waker does, to read no pane it need not).
        $resting = New-Seat; $working = New-Seat @{ midTurn = "yes" }
        & $Fx.Seat $State $resting; & $Fx.Seat $State $working
        $a1 = Get-HordeWakeState -Waker $W -Id $resting.id -Full
        $a2 = Get-HordeWakeState -Waker $W -Id $working.id -Full
        return ($a1.state -ceq "known" -and $a1.value.midTurn -ceq "no" -and $a2.state -ceq "known" -and $a2.value.midTurn -ceq "yes")
    }
    "reach.unseen" = {
        param($W, $Fx, $State)
        $s = New-Seat @{ unseen = $true }
        & $Fx.Seat $State $s
        $a = Send-HordeWakeNudge -Waker $W -Id $s.id
        $o = & $Fx.Observe $State $s.id
        return ($a.state -ceq "known" -and $a.value.outcome -ceq "woken" -and $o.nudges -eq 1 -and (Test-TypedClean $o $s.body))
    }
    "nudge.guarded" = {
        param($W, $Fx, $State)
        # THE WATCHER IS NOT ASKED: the nudge is sent straight at a session that must not be typed into,
        # which is the session as it may be by the time a nudge decided a moment ago arrives.
        $typing = New-Seat @{ boxEmpty = "no" }; $working = New-Seat @{ midTurn = "yes"; idle = "no" }; $resting = New-Seat
        & $Fx.Seat $State $typing; & $Fx.Seat $State $working; & $Fx.Seat $State $resting
        $a1 = Send-HordeWakeNudge -Waker $W -Id $typing.id
        $a2 = Send-HordeWakeNudge -Waker $W -Id $working.id
        $a3 = Send-HordeWakeNudge -Waker $W -Id $resting.id
        $o1 = & $Fx.Observe $State $typing.id
        $o2 = & $Fx.Observe $State $working.id
        $o3 = & $Fx.Observe $State $resting.id
        $held = ($a1.state -ceq "known" -and $a1.value.outcome -ceq "busy" -and $o1.nudges -eq 0 -and @($o1.typed).Count -eq 0 -and $a2.state -ceq "known" -and $a2.value.outcome -ceq "busy" -and $o2.nudges -eq 0 -and @($o2.typed).Count -eq 0)
        # AND IT STILL RINGS: a guard that refused everybody would pass the two above.
        return ($held -and $a3.state -ceq "known" -and $a3.value.outcome -ceq "woken" -and $o3.nudges -eq 1)
    }
}
# What a waker that does not offer a state capability must say of it instead.
$mustBeUnknown = @{ "state.box" = "boxEmpty"; "state.turn" = "midTurn" }

Write-Host ""
Write-Host "--- the cases cover the closed list of capabilities, no more and no less ---" -ForegroundColor Cyan
$listed = @(Get-HordeWakerCapabilityNames)
Check ((@($listed | Sort-Object) -join ",") -ceq (@($cases.Keys | Sort-Object) -join ",")) ("every capability has a case here, and every case a capability (" + ($listed -join ", ") + ")")
Check (@(Get-HordeWakerNames).Count -ge 1) ("at least one waker is loaded (" + (@(Get-HordeWakerNames) -join ", ") + ")")

try {
    foreach ($name in @(Get-HordeWakerNames)) {
        $w = Get-HordeWaker -Name $name
        Write-Host ""
        Write-Host ("--- waker " + $name + " ---") -ForegroundColor Cyan
        $fxPath = Join-Path $w.folder "test\Fixture.ps1"
        Check (Test-Path -LiteralPath $fxPath -PathType Leaf) ("[" + $name + "] has a test fixture at test\Fixture.ps1")
        if (-not (Test-Path -LiteralPath $fxPath -PathType Leaf)) { continue }
        $fx = & $fxPath -Root $root
        $lacksOne = $false
        foreach ($cap in $listed) {
            $support = Get-HordeWakerSupport -Waker $w -Capability $cap
            $state = & $fx.New
            try {
                # A CLAIM IS SHOWN, VERIFIED OR NOT: unverified means not yet shown against the real thing,
                # never not shown at all. Its case runs against the waker's fixture like a yes.
                if ($support -ceq "yes" -or $support -ceq "unverified") {
                    $shown = & $cases[$cap] $w $fx $state
                    Check ($shown -eq $true) ("[" + $name + "] " + $cap + " is " + $support + ", and the case shows it")
                }
                if ($support -cne "yes") {
                    $lacksOne = $true
                    $r = Resolve-HordeWaker -Name $name -Require @($cap)
                    Check ($r.state -ceq "unknown" -and "$($r.reason)".Contains($cap)) ("[" + $name + "] " + $cap + " is " + $support + ", and a caller that requires it is refused, naming it")
                    if ($support -cne "unverified" -and $mustBeUnknown.ContainsKey($cap)) {
                        $s = New-Seat
                        & $fx.Seat $state $s
                        $a = Get-HordeWakeState -Waker $w -Id $s.id -Full
                        # Unknown as a whole, or known with that one word unknown: never a yes or a no.
                        $honest = ($a.state -ceq "unknown" -or ($a.state -ceq "known" -and "$($a.value.($mustBeUnknown[$cap]))" -ceq "unknown"))
                        Check $honest ("[" + $name + "] and it never answers yes or no for " + $mustBeUnknown[$cap] + ", which it cannot read")
                    }
                }
            } finally { & $fx.Remove $state }
        }
        if ($lacksOne) {
            $p = Resolve-HordeProductionWaker
            Check (-not ($p.state -ceq "known" -and $p.value.name -ceq $name)) ("[" + $name + "] lacks a capability, and the production path never picks it")
        }
        # Rules for every waker, whatever it declares.
        $state = & $fx.New
        try {
            $s = New-Seat @{ role = "goblin"; parent = "0b000000-0000-4000-8000-000000000001" }
            & $fx.Seat $state $s
            $a = Get-HordeWakeTargets -Waker $w
            $mine = @()
            if ($a.state -ceq "known") { $mine = @(@($a.value) | Where-Object { $_.id -ceq $s.id }) }
            Check ($mine.Count -eq 1 -and $mine[0].role -ceq "goblin" -and $mine[0].parent -ceq $s.parent) ("[" + $name + "] a session it was given is among its targets, once, with its role and parent")
            $a = Get-HordeWakeState -Waker $w -Id $s.id
            Check ($a.state -ceq "known" -and $a.value.unreadCount -eq 1 -and $a.value.oldestUnreadAt -eq $t0) ("[" + $name + "] its unread mail is counted, with the time of the oldest")
            $o = & $fx.Observe $state $s.id
            Check ($o.nudges -eq 0 -and @($o.typed).Count -eq 0) ("[" + $name + "] reading the targets and a state rings nobody and types nothing")
            $never = "0c000000-0000-4000-8000-000000000001"
            $a = Get-HordeWakeState -Waker $w -Id $never
            Check ($a.state -ceq "unknown") ("[" + $name + "] a session it does not know is unknown, never a state of zeros")
            $a = Send-HordeWakeNudge -Waker $w -Id $never
            $o = & $fx.Observe $state $never
            Check (-not ($a.state -ceq "known" -and $a.value.outcome -ceq "woken") -and $o.nudges -eq 0 -and @($o.typed).Count -eq 0) ("[" + $name + "] a nudge of a session it does not know wakes nobody and types nothing")
        } finally { & $fx.Remove $state }
    }
} finally {
    Exit-HordeTestPinnedHome -State $pinned
    Exit-HordeTestEmptyFleet -Pin $fleetPin
}

Complete-HordeSuite -Success "every waker shows each capability it claims and is refused where it lacks one"
