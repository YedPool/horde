# DOES THE WAKER PORT KEEP A WAKER HONEST ABOUT WHAT IT CAN SEE, AND NEVER PASS ON A GUESS?
#
# wakers/Port.ps1. A waker tells the wake watcher which sessions there are, what state each is in, and
# rings one session's doorbell. The watcher types into a session on the strength of those answers, so
# the port is where a wrong one is stopped. Pinned here, without any real waker, so every outcome is
# exact and repeatable:
#   - REGISTRATION AND CAPABILITIES. A waker folder whose capabilities.json breaks
#     schema/waker-capabilities.v1, or names another waker, is refused. Only "yes" counts as having a
#     capability. The production path requires all five, so the in-process test waker, which declines
#     reach.unseen, is never picked there - and two wakers that both could be are never chosen between.
#   - THE ADAPTER'S WORD IS CHECKED. An adapter that throws, answers with something that is not a
#     core/tristate answer, answers about another session, uses a word outside yes, no and unknown,
#     reports unread mail with no time, or claims to see a box it declared it cannot read, comes back
#     unknown with the reason; the port never throws for a failure of the far end.
#   - ONLY A REGISTERED WAKER IS CALLED. A look-alike object is refused, and its blocks never run.
#
# Every conformance case for the real wakers is test/test-waker-conformance.ps1.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "wakers\Port.ps1")
. (Join-Path $root "wakers\memory\Waker.ps1")

$fx = Join-Path $here "fixtures\waker\caps"
$script:calls = 0
$sid = "22222222-3333-4444-8555-666666666666"
$other = "33333333-4444-4555-8666-777777777777"
$t0 = New-Object System.DateTime(2026, 10, 12, 8, 0, 0, [System.DateTimeKind]::Utc)

function Reg {
    # Register a fixture folder under its own name, with blocks that answer well unless given others.
    param([string]$Name,
          [scriptblock]$Targets = { $script:calls++; New-HordeKnown -Value @() },
          [scriptblock]$State = { param($id) $script:calls++; New-HordeUnknown -Reason "the fixture knows no session" },
          [scriptblock]$Nudge = { param($id) $script:calls++; New-HordeUnknown -Reason "the fixture rings nobody" },
          [scriptblock]$Begin = $null)
    return (Register-HordeWaker -Name $Name -Folder (Join-Path $fx $Name) -Targets $Targets -State $State -Nudge $Nudge -Begin $Begin)
}

Write-Host ""
Write-Host "--- a waker folder is registered only with valid capabilities, naming itself ---" -ForegroundColor Cyan

$good = Reg "fixture-good"
Check ($good.name -ceq "fixture-good") "a folder with valid capabilities registers under its own name"
Check (@(Get-HordeWakerNames) -contains "fixture-good") "and is listed"
foreach ($case in @(
        @{ n = "fixture-misnamed"; like = "sits in the folder"; what = "capabilities that name another waker than their folder" },
        @{ n = "fixture-missing-cap"; like = "reach.unseen"; what = "capabilities missing one of the closed list" },
        @{ n = "fixture-extra-cap"; like = "keystrokes"; what = "a capability outside the closed list" },
        @{ n = "fixture-bad-word"; like = "maybe"; what = "a support word outside yes, no, declined, unverified" },
        @{ n = "fixture-blank-evidence"; like = "evidence"; what = "a capability with blank evidence" },
        @{ n = "fixture-no-file"; like = "no capabilities.json"; what = "a folder with no capabilities.json" })) {
    Check (Throws { Reg $case.n } $case.like) ("refused: " + $case.what)
    Check (@(Get-HordeWakerNames) -notcontains $case.n) ("and " + $case.n + " is not registered")
}
Check (Throws { Register-HordeWaker -Name "fixture-renamed" -Folder (Join-Path $fx "fixture-good") -Targets { } -State { } -Nudge { } } "names the waker") "refused: a name that is not the folder its capabilities sit in"
Check (Throws { Get-HordeWaker -Name "fixture-none" } "no waker") "asking for a waker nobody registered is an error, not a quiet default"
$firstGood = Get-HordeWaker -Name "fixture-good"
Check (Throws { Reg "fixture-good" -Targets { "replaced" } } "already registered") "registering a name a second time is refused"
Check ([object]::ReferenceEquals((Get-HordeWaker -Name "fixture-good"), $firstGood)) "and the first registration still stands"
Check (@(@(Get-HordeWakerFiles) | Where-Object { "$_" -like "*\memory\Waker.ps1" }).Count -eq 1) "Get-HordeWakerFiles finds the memory waker's Waker.ps1"
Check ((@(Get-HordeWakerRoles) -join ",") -ceq "warchief,orc,goblin,unknown") "the roles are listed in the order the watcher serves them"

Write-Host ""
Write-Host "--- only 'yes' is having a capability; the production path requires all five, and never chooses ---" -ForegroundColor Cyan

$memory = Get-HordeWaker -Name "memory"
Check (Test-HordeWakerCapability -Waker $good -Capability "state.box") "yes is having it"
Check (-not (Test-HordeWakerCapability -Waker $memory -Capability "reach.unseen")) "declined is not having it"
$blind = Reg "fixture-blind" -State { param($id) New-HordeKnown -Value ([pscustomobject]@{ id = $id; unreadCount = 0; oldestUnreadAt = $null; idle = "yes"; boxEmpty = $script:blindBox; midTurn = $script:blindTurn }) }
Check (-not (Test-HordeWakerCapability -Waker $blind -Capability "state.box")) "no is not having it"
Check (-not (Test-HordeWakerCapability -Waker $blind -Capability "state.turn")) "declined is not having it, here either"
Check (-not (Test-HordeWakerClaims -Waker $blind -Capability "state.box") -and -not (Test-HordeWakerClaims -Waker $blind -Capability "state.turn") -and (Test-HordeWakerClaims -Waker $good -Capability "state.box")) "no and declined are not claims; yes is"
Check (Throws { Test-HordeWakerCapability -Waker $good -Capability "teleport" } "not a waker capability") "asking about a capability outside the list is an error"
$r = Resolve-HordeWaker -Name "memory" -Require @("reach.unseen")
Check ($r.state -ceq "unknown" -and "$($r.reason)".Contains("reach.unseen") -and "$($r.reason)".Contains("declined")) "a caller that requires what the memory waker declines is refused, with the waker's own word for it"
Check ((Resolve-HordeWaker -Name "memory" -Require @("state.box", "state.turn")).state -ceq "known") "and one that requires only what it offers gets it"
Check ((Resolve-HordeWaker -Name "fixture-none" -Require @()).state -ceq "unknown") "a waker nobody loaded is unknown, not a throw"
$p = Resolve-HordeProductionWaker
Check ($p.state -ceq "known" -and [object]::ReferenceEquals($p.value, $good)) "the production path picks the one waker that offers all five"
Check ($p.state -ceq "known" -and $p.value.name -cne "memory") "and it is never the memory waker"
$unguarded = Reg "fixture-unguarded"
$p = Resolve-HordeProductionWaker
Check ($p.state -ceq "known" -and [object]::ReferenceEquals($p.value, $good)) "a waker whose nudge does not guard itself is not one the production path can pick: still the one"
Check ((Resolve-HordeWaker -Name "fixture-unguarded" -Require @("nudge.guarded")).state -ceq "unknown") "and a caller that requires nudge.guarded of it is refused"
# UNVERIFIED: a claim not yet shown. Never picked for a live run; picked, when asked for, only if no
# waker offers all five.
$script:claimTurn = "no"
$claimed = Reg "fixture-unverified" -State { param($id) New-HordeKnown -Value ([pscustomobject]@{ id = $id; unreadCount = 0; oldestUnreadAt = $null; idle = "yes"; boxEmpty = "yes"; midTurn = $script:claimTurn }) }
Check (-not (Test-HordeWakerCapability -Waker $claimed -Capability "state.turn") -and (Test-HordeWakerClaims -Waker $claimed -Capability "state.turn")) "unverified is not having it, and it is claiming it"
Check ((@(Get-HordeWakerUnverified -Waker $claimed) -join ",") -ceq "state.turn,nudge.guarded" -and @(Get-HordeWakerUnverified -Waker $good).Count -eq 0 -and @(Get-HordeWakerUnverified -Waker $memory).Count -eq 0) "a waker's unverified capabilities are named, in the port's order; declined is not one of them"
$a = Get-HordeWakeState -Waker $claimed -Id "0a000000-0000-4000-8000-000000000001"
Check ($a.state -ceq "known" -and $a.value.midTurn -ceq "no") "a waker that claims state.turn, unverified, may answer about the turn"
Check ((Resolve-HordeWaker -Name "fixture-unverified" -Require @("state.turn")).state -ceq "unknown") "a caller that requires the capability of it is still refused"
$p = Resolve-HordeProductionWaker -AllowUnverified
Check ($p.state -ceq "known" -and [object]::ReferenceEquals($p.value, $good)) "with a waker that offers all five loaded, it is the one picked, allowed or not: unverified is never preferred"
$second = Reg "fixture-second"
$p = Resolve-HordeProductionWaker
Check ($p.state -ceq "unknown" -and "$($p.reason)".Contains("never chosen")) "with two that could be picked the production path is unknown: one is never chosen over another"
Check ((Resolve-HordeProductionWaker -AllowUnverified).state -ceq "unknown") "and allowing unverified does not choose between them either"
# With only wakers that do not offer all five: the memory waker, which declines one, and those that claim.
$kept = @{}; foreach ($k in @($script:HordeWakers.Keys)) { $kept[$k] = $script:HordeWakers[$k] }
try {
    foreach ($k in @("fixture-good", "fixture-second", "fixture-unguarded")) { $script:HordeWakers.Remove($k) }
    $p = Resolve-HordeProductionWaker
    Check ($p.state -ceq "absent" -and "$($p.reason)".Contains("fixture-unverified: does not offer state.turn (it says unverified)")) "with no waker that offers all five the production path finds none, and says the unverified one's word for what it lacks"
    $p = Resolve-HordeProductionWaker -AllowUnverified
    Check ($p.state -ceq "known" -and [object]::ReferenceEquals($p.value, $claimed)) "allowed, it picks the one that claims all five - never the memory waker, which declines one, nor one that says no"
    $script:HordeWakers["fixture-unguarded"] = $kept["fixture-unguarded"]
    $p = Resolve-HordeProductionWaker -AllowUnverified
    Check ($p.state -ceq "unknown" -and "$($p.reason)".Contains("never chosen")) "two that claim all five - the other has an unverified guard - are unknown: one is never chosen over another"
} finally { $script:HordeWakers.Clear(); foreach ($k in @($kept.Keys)) { $script:HordeWakers[$k] = $kept[$k] } }

Write-Host ""
Write-Host "--- only a waker registered through the port is called ---" -ForegroundColor Cyan

$script:calls = 0
$fake = [pscustomobject]@{ PSTypeName = "Horde.Waker"; name = "fixture-good"; folder = $good.folder; capabilities = $good.capabilities; targets = { $script:calls++ }; state = { $script:calls++ }; nudge = { $script:calls++ } }
Check ((Get-HordeWakeTargets -Waker $fake).state -ceq "unknown") "a look-alike's targets are unknown"
Check ((Get-HordeWakeState -Waker $fake -Id $sid).state -ceq "unknown") "a look-alike's state is unknown"
$a = Send-HordeWakeNudge -Waker $fake -Id $sid
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("not registered")) "a look-alike is not asked to nudge, and the answer says why"
Check ((Send-HordeWakeNudge -Waker $null -Id $sid).state -ceq "unknown") "no waker at all is unknown, not a throw"
Check ($script:calls -eq 0) "and none of the look-alike's blocks ever ran"
$a = Get-HordeWakeState -Waker $good -Id "not a session id"
Check ($a.state -ceq "unknown" -and $script:calls -eq 0) "an id that is not a session id never reaches the adapter's state"
$a = Send-HordeWakeNudge -Waker $good -Id ""
Check ($a.state -ceq "unknown" -and $script:calls -eq 0) "and an empty id never reaches its nudge"

Write-Host ""
Write-Host "--- the memory waker's good answers pass through, in the port's shape ---" -ForegroundColor Cyan

Reset-HordeMemoryWaker
Set-HordeMemoryWakerSession -Id $sid -Label "A" -Role "orc" -Parent $other -UnreadCount 2 -OldestUnreadAt $t0 -Idle "yes" -BoxEmpty "no" -MidTurn "unknown"
Set-HordeMemoryWakerSession -Id $other -Label "M" -Role "warchief" -Reachable "unknown"
$a = Get-HordeWakeTargets -Waker $memory
$list = @()
if ($a.state -ceq "known") { $list = @($a.value) }
Check ($a.state -ceq "known" -and $list.Count -eq 2) "the targets are a known list of both sessions"
$one = @($list | Where-Object { $_.id -ceq $sid })
Check ($one.Count -eq 1 -and $one[0].label -ceq "A" -and $one[0].role -ceq "orc" -and $one[0].parent -ceq $other -and $one[0].reachable -ceq "yes") "a target carries its id, label, role, parent and reachable"
Check (@($list | Where-Object { $_.id -ceq $other -and $_.reachable -ceq "unknown" -and $_.parent -ceq "" }).Count -eq 1) "reachable unknown, and no parent, are carried as they are"
$a = Get-HordeWakeState -Waker $memory -Id $sid
Check ($a.state -ceq "known" -and $a.value.id -ceq $sid -and $a.value.unreadCount -eq 2 -and $a.value.oldestUnreadAt -eq $t0 -and $a.value.idle -ceq "yes" -and $a.value.boxEmpty -ceq "no" -and $a.value.midTurn -ceq "unknown") "a state carries the unread count, the oldest unread time, and yes, no and unknown as they were said"
Check ($a.state -ceq "known" -and $a.value.oldestUnreadAt.Kind -eq [System.DateTimeKind]::Utc) "and its time is UTC"
$a = Get-HordeWakeState -Waker $memory -Id $other
Check ($a.state -ceq "known" -and $a.value.unreadCount -eq 0 -and $null -eq $a.value.oldestUnreadAt) "a session with no unread mail has no oldest unread time"
$a = Get-HordeWakeState -Waker $memory -Id "44444444-5555-4666-8777-888888888888"
Check ($a.state -ceq "unknown") "a session the waker does not know is unknown, never a state of zeros"
Set-HordeMemoryWakerSession -Id $sid -UnreadCount 2 -OldestUnreadAt $t0
Set-HordeMemoryWakerClock $t0.AddSeconds(30)
$a = Send-HordeWakeNudge -Waker $memory -Id $sid
Check ($a.state -ceq "known" -and $a.value.id -ceq $sid -and $a.value.outcome -ceq "woken" -and $a.value.at -eq $t0.AddSeconds(30)) "a nudge answers its session, its outcome and when"
Check (@(Get-HordeMemoryWakerNudges -Id $sid).Count -eq 1) "and the memory waker recorded the one nudge it was asked for"
Set-HordeMemoryWakerSession -Id $sid -UnreadCount 1 -OldestUnreadAt $t0 -Outcome "busy" -OutcomeReason "it began a turn as the nudge arrived"
$a = Send-HordeWakeNudge -Waker $memory -Id $sid
Check ($a.state -ceq "known" -and $a.value.outcome -ceq "busy" -and $a.value.reason -ceq "it began a turn as the nudge arrived") "busy is carried with its reason"

Set-HordeMemoryWakerSession -Id $sid -UnreadCount 1 -OldestUnreadAt $t0 -BoxEmpty "no"
$a = Send-HordeWakeNudge -Waker $memory -Id $sid
Check ($a.state -ceq "known" -and $a.value.outcome -ceq "busy" -and "$($a.value.reason)".Contains("input box") -and @(Get-HordeMemoryWakerNudges -Id $sid).Count -eq 1) "the memory waker's nudge guards itself: asked to ring a session whose box is not empty, it answers busy and rings nobody"
Set-HordeMemoryWakerSession -Id $sid -Outcome "nothing" -OutcomeReason "its mail was taken before the nudge"
$a = Send-HordeWakeNudge -Waker $memory -Id $sid
Check ($a.state -ceq "known" -and $a.value.outcome -ceq "nothing" -and $a.value.reason -ceq "its mail was taken before the nudge" -and @(Get-HordeMemoryWakerNudges -Id $sid).Count -eq 1) "nothing - the mail was taken before the nudge - is carried with its reason, and nobody was rung for it"

Start-HordeWakePass -Waker $memory
Start-HordeWakePass -Waker $memory
Check ((Get-HordeMemoryWakerBegins) -eq 2) "a waker that registered a Begin is told each time a pass begins"
$said = "returned"
try { Start-HordeWakePass -Waker $good; Start-HordeWakePass -Waker $null; Start-HordeWakePass -Waker ([pscustomobject]@{ PSTypeName = "Horde.Waker"; name = "fixture-good"; begin = { throw "a look-alike was called" } }) } catch { $said = "threw: " + $_.Exception.Message }
Check ($said -ceq "returned") "a waker with no Begin, no waker at all and a look-alike are told nothing, and none of them is a throw"
Reset-HordeMemoryWaker
Set-HordeMemoryWakerSession -Id $sid -UnreadCount 1 -OldestUnreadAt $t0 -BoxEmpty "no"
Set-HordeMemoryWakerCheap $true
$cheap = Get-HordeWakeState -Waker $memory -Id $sid
$whole = Get-HordeWakeState -Waker $memory -Id $sid -Full
Check ($cheap.state -ceq "known" -and $cheap.value.boxEmpty -ceq "unknown" -and $whole.state -ceq "known" -and $whole.value.boxEmpty -ceq "no" -and (@(Get-HordeMemoryWakerLooks) -join ",") -ceq $sid) "-Full is the waker's Confirm, where it registered one: its state said the box unknown, and the full reading says it"
Check ((Test-HordeWakerConfirms $memory) -and -not (Test-HordeWakerConfirms $good) -and -not (Test-HordeWakerConfirms $null)) "a waker says whether it has a fuller reading than its state; one that registered none, and no waker, have none"
$script:calls = 0
$null = Get-HordeWakeState -Waker $good -Id $sid -Full
Check ($script:calls -eq 1) "for a waker with no Confirm, -Full is its state"
Reset-HordeMemoryWaker
$thrower = Reg "fixture-second-begin" -Begin { throw "the fleet fell over" }
$said = "returned"
try { Start-HordeWakePass -Waker $thrower } catch { $said = "threw" }
Check ($said -ceq "returned") "a Begin that throws is not a throw of the port"

Write-Host ""
Write-Host "--- an adapter's bad answer is unknown with the reason, never passed on and never a throw ---" -ForegroundColor Cyan

$script:targetsAnswer = $null
$script:stateAnswer = $null
$script:nudgeAnswer = $null
$scripted = Reg "fixture-scripted" -Targets { & $script:targetsAnswer } -State { param($id) & $script:stateAnswer $id } -Nudge { param($id) & $script:nudgeAnswer $id }
function New-Target { param([hashtable]$Change = @{}) $t = @{ id = $sid; label = "A"; role = "orc"; parent = ""; reachable = "yes" }; foreach ($k in $Change.Keys) { if ($null -eq $Change[$k]) { $t.Remove($k) } else { $t[$k] = $Change[$k] } }; return [pscustomobject]$t }
function New-State { param([hashtable]$Change = @{}) $s = @{ id = $sid; unreadCount = 1; oldestUnreadAt = $t0; idle = "yes"; boxEmpty = "yes"; midTurn = "no" }; foreach ($k in $Change.Keys) { if ($null -eq $Change[$k]) { $s.Remove($k) } else { $s[$k] = $Change[$k] } }; return [pscustomobject]$s }
function New-Rang { param([hashtable]$Change = @{}) $n = @{ id = $sid; outcome = "woken"; reason = ""; at = $t0 }; foreach ($k in $Change.Keys) { if ($null -eq $Change[$k]) { $n.Remove($k) } else { $n[$k] = $Change[$k] } }; return [pscustomobject]$n }

$script:targetsAnswer = { New-HordeKnown -Value @((New-Target)) }
Check ((Get-HordeWakeTargets -Waker $scripted).state -ceq "known") "CONTROL: the scripted waker's good listing is known"
foreach ($case in @(
        @{ what = "a listing that throws"; block = { throw "the far end fell over" }; like = "fell over" },
        @{ what = "a listing that is not an answer"; block = { @((New-Target)) }; like = "not an answer" },
        @{ what = "a listing that answers nothing at all"; block = { }; like = "not an answer" },
        @{ what = "a listing that is absent"; block = { New-HordeAbsent -Note "none" }; like = "absent" },
        @{ what = "a listing that is one record, not a list"; block = { New-HordeKnown -Value (New-Target) }; like = "not a list" },
        @{ what = "a listing that is text"; block = { New-HordeKnown -Value "s-1,s-2" }; like = "not a list" },
        @{ what = "a target that is not an object"; block = { New-HordeKnown -Value @("s-1") }; like = "not an object" },
        @{ what = "a target with no id"; block = { New-HordeKnown -Value @((New-Target @{ id = $null })) }; like = "not a session id" },
        @{ what = "a target whose id holds a line break"; block = { New-HordeKnown -Value @((New-Target @{ id = "s-1`n" })) }; like = "not a session id" },
        @{ what = "one session listed twice"; block = { New-HordeKnown -Value @((New-Target), (New-Target)) }; like = "twice" },
        @{ what = "a label that is not text"; block = { New-HordeKnown -Value @((New-Target @{ label = 7 })) }; like = "label" },
        @{ what = "a role outside the list"; block = { New-HordeKnown -Value @((New-Target @{ role = "master" })) }; like = "role" },
        @{ what = "a role in the wrong case"; block = { New-HordeKnown -Value @((New-Target @{ role = "Orc" })) }; like = "role" },
        @{ what = "a parent that is not a session id"; block = { New-HordeKnown -Value @((New-Target @{ parent = "two words" })) }; like = "parent" },
        @{ what = "reachable given as true"; block = { New-HordeKnown -Value @((New-Target @{ reachable = $true })) }; like = "reachable" },
        @{ what = "reachable given as maybe"; block = { New-HordeKnown -Value @((New-Target @{ reachable = "maybe" })) }; like = "reachable" },
        @{ what = "reachable left out"; block = { New-HordeKnown -Value @((New-Target @{ reachable = $null })) }; like = "reachable" })) {
    $script:targetsAnswer = $case.block
    $a = Get-HordeWakeTargets -Waker $scripted
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains($case.like)) ("targets: " + $case.what + " is unknown, saying so")
}
$script:targetsAnswer = { New-HordeUnknown -Reason "the fleet's store is locked" }
$a = Get-HordeWakeTargets -Waker $scripted
Check ($a.state -ceq "unknown" -and "$($a.reason)" -ceq "the fleet's store is locked") "targets: an adapter's own unknown is passed on with its reason"
$script:targetsAnswer = { New-HordeKnown -Value @() }
$a = Get-HordeWakeTargets -Waker $scripted
Check ($a.state -ceq "known" -and @($a.value).Count -eq 0) "targets: an empty fleet is a known empty list, not unknown"

$script:stateAnswer = { param($id) New-HordeKnown -Value (New-State) }
Check ((Get-HordeWakeState -Waker $scripted -Id $sid).state -ceq "known") "CONTROL: the scripted waker's good state is known"
foreach ($case in @(
        @{ what = "a state that throws"; block = { param($id) throw "the box could not be read" }; like = "could not be read" },
        @{ what = "a state that is not an answer"; block = { param($id) New-State }; like = "not an answer" },
        @{ what = "a state that answers true"; block = { param($id) $true }; like = "not an answer" },
        @{ what = "a state that is absent"; block = { param($id) New-HordeAbsent -Note "none" }; like = "absent" },
        @{ what = "a state that is text"; block = { param($id) New-HordeKnown -Value "idle" }; like = "not an object" },
        @{ what = "a state that names no session"; block = { param($id) New-HordeKnown -Value (New-State @{ id = $null }) }; like = "without naming" },
        @{ what = "a state about another session"; block = { param($id) New-HordeKnown -Value (New-State @{ id = $other }) }; like = "answered about" },
        @{ what = "an unread count below zero"; block = { param($id) New-HordeKnown -Value (New-State @{ unreadCount = -1 }) }; like = "unreadCount" },
        @{ what = "an unread count given as text"; block = { param($id) New-HordeKnown -Value (New-State @{ unreadCount = "2" }) }; like = "unreadCount" },
        @{ what = "an unread count that is a fraction"; block = { param($id) New-HordeKnown -Value (New-State @{ unreadCount = 1.5 }) }; like = "unreadCount" },
        @{ what = "unread mail with no time for the oldest"; block = { param($id) New-HordeKnown -Value (New-State @{ oldestUnreadAt = $null }) }; like = "no time" },
        @{ what = "unread mail whose oldest time is text"; block = { param($id) New-HordeKnown -Value (New-State @{ oldestUnreadAt = "2026-10-12T08:00:00Z" }) }; like = "no time" },
        @{ what = "unread mail whose oldest time has no zone"; block = { param($id) New-HordeKnown -Value (New-State @{ oldestUnreadAt = (New-Object System.DateTime(2026, 10, 12, 8, 0, 0)) }) }; like = "no zone" },
        @{ what = "idle given as true"; block = { param($id) New-HordeKnown -Value (New-State @{ idle = $true }) }; like = "idle" },
        @{ what = "idle given as Yes"; block = { param($id) New-HordeKnown -Value (New-State @{ idle = "Yes" }) }; like = "idle" },
        @{ what = "boxEmpty left out"; block = { param($id) New-HordeKnown -Value (New-State @{ boxEmpty = $null }) }; like = "boxEmpty" },
        @{ what = "boxEmpty given as empty text"; block = { param($id) New-HordeKnown -Value (New-State @{ boxEmpty = "" }) }; like = "boxEmpty" },
        @{ what = "midTurn given as a number"; block = { param($id) New-HordeKnown -Value (New-State @{ midTurn = 0 }) }; like = "midTurn" })) {
    $script:stateAnswer = $case.block
    $a = Get-HordeWakeState -Waker $scripted -Id $sid
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains($case.like)) ("state: " + $case.what + " is unknown, saying so")
}
$script:stateAnswer = { param($id) New-HordeKnown -Value (New-State @{ unreadCount = [long]3; oldestUnreadAt = $t0.ToLocalTime() }) }
$a = Get-HordeWakeState -Waker $scripted -Id $sid
Check ($a.state -ceq "known" -and $a.value.unreadCount -eq 3 -and $a.value.oldestUnreadAt -eq $t0 -and $a.value.oldestUnreadAt.Kind -eq [System.DateTimeKind]::Utc) "state: a local time is carried as the same instant in UTC"

# Caught here on purpose: the port must ANSWER for a count that does not fit, and a throw must fail
# this check rather than end it (a check whose expression throws records an error, not a failure).
$script:stateAnswer = { param($id) New-HordeKnown -Value (New-State @{ unreadCount = [long]3000000000 }) }
$a = $null
try { $a = Get-HordeWakeState -Waker $scripted -Id $sid } catch { $a = $null }
Check ($null -ne $a -and $a.state -ceq "unknown" -and "$($a.reason)".Contains("no count of mail")) "state: an unread count too large to be one is unknown, saying so - answered, not thrown"
$script:stateAnswer = { param($id) New-HordeKnown -Value (New-State @{ unreadCount = [long]2147483647 }) }
$a = Get-HordeWakeState -Waker $scripted -Id $sid
Check ($a.state -ceq "known" -and $a.value.unreadCount -eq 2147483647 -and $a.value.unreadCount -is [int]) "state: the largest count that fits is carried"
$script:nudgeAnswer = { param($id) New-HordeKnown -Value (New-Rang @{ at = $t0.ToLocalTime() }) }
$a = Send-HordeWakeNudge -Waker $scripted -Id $sid
Check ($a.state -ceq "known" -and $a.value.at -eq $t0 -and $a.value.at.Kind -eq [System.DateTimeKind]::Utc) "nudge: a local time is carried as the same instant in UTC"

Check ($a.state -ceq "known") "CONTROL: the nudge above is known"
$script:stateAnswer = { param($id) New-HordeKnown -Value (New-State) }
$a = Get-HordeWakeState -Waker $scripted -Id $sid
Check ($a.state -ceq "known" -and $a.value.unreadableCount -eq 0) "state: a waker that does not report unreadableCount is read as reporting none"
$script:stateAnswer = { param($id) New-HordeKnown -Value (New-State @{ unreadableCount = 2 }) }
$a = Get-HordeWakeState -Waker $scripted -Id $sid
Check ($a.state -ceq "known" -and $a.value.unreadableCount -eq 2 -and $a.value.unreadCount -eq 1) "state: unreadableCount is carried beside unreadCount, and takes nothing from it"
foreach ($case in @(
        @{ what = "below zero"; v = -1 }, @{ what = "given as text"; v = "2" }, @{ what = "a fraction"; v = 1.5 }, @{ what = "too large to be a count"; v = [long]3000000000 })) {
    $script:badCount = $case.v
    $script:stateAnswer = { param($id) New-HordeKnown -Value (New-State @{ unreadableCount = $script:badCount }) }
    $a = $null
    try { $a = Get-HordeWakeState -Waker $scripted -Id $sid } catch { $a = $null }
    Check ($null -ne $a -and $a.state -ceq "unknown" -and "$($a.reason)".Contains("unreadableCount")) ("state: an unreadableCount " + $case.what + " is unknown, saying so")
}
$script:stateAnswer = { param($id) $s = New-State; Add-Member -InputObject $s -MemberType NoteProperty -Name "unreadableCount" -Value $null; New-HordeKnown -Value $s }
$a = Get-HordeWakeState -Waker $scripted -Id $sid
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("unreadableCount")) "state: an unreadableCount of null is 'I could not count', which is unknown and never 0"

# limited and limitedUntil: optional, carried, and held to their kinds.
$script:stateAnswer = { param($id) New-HordeKnown -Value (New-State) }
$a = Get-HordeWakeState -Waker $scripted -Id $sid
Check ($a.state -ceq "known" -and $a.value.limited -eq $false -and $null -eq $a.value.limitedUntil) "state: a waker that says nothing of a usage limit is read as not limited"
$script:stateAnswer = { param($id) New-HordeKnown -Value (New-State @{ limited = $true; limitedUntil = $t0.AddHours(1) }) }
$a = Get-HordeWakeState -Waker $scripted -Id $sid
Check ($a.state -ceq "known" -and $a.value.limited -eq $true -and $a.value.limitedUntil -eq $t0.AddHours(1) -and $a.value.limitedUntil.Kind -eq [System.DateTimeKind]::Utc) "state: limited and the time it ends are carried, the time as UTC"
$script:stateAnswer = { param($id) New-HordeKnown -Value (New-State @{ limited = $true }) }
$a = Get-HordeWakeState -Waker $scripted -Id $sid
Check ($a.state -ceq "known" -and $a.value.limited -eq $true -and $null -eq $a.value.limitedUntil) "state: limited with no time is limited, and nobody knows until when"
$script:stateAnswer = { param($id) New-HordeKnown -Value (New-State @{ limited = $false; limitedUntil = $t0.AddHours(1) }) }
$a = Get-HordeWakeState -Waker $scripted -Id $sid
Check ($a.state -ceq "known" -and $a.value.limited -eq $false -and $null -eq $a.value.limitedUntil) "state: a time beside a limited that is false is not read"
$script:stateAnswer = { param($id) New-HordeKnown -Value (New-State @{ limited = "yes" }) }
$a = Get-HordeWakeState -Waker $scripted -Id $sid
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("limited")) "state: a limited that is not true or false is unknown"
$script:stateAnswer = { param($id) New-HordeKnown -Value (New-State @{ limited = $true; limitedUntil = (New-Object System.DateTime(2026, 10, 12, 9, 0, 0)) }) }
$a = Get-HordeWakeState -Waker $scripted -Id $sid
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("limitedUntil")) "state: a limitedUntil with no zone cannot be placed, and is unknown"
$script:stateAnswer = { param($id) New-HordeKnown -Value (New-State @{ limited = $true; limitedUntil = "soon" }) }
Check ((Get-HordeWakeState -Waker $scripted -Id $sid).state -ceq "unknown") "state: and so is one that is no time"

$script:blindBox = "unknown"; $script:blindTurn = "unknown"
Check ((Get-HordeWakeState -Waker $blind -Id $sid).state -ceq "known") "state: a waker that cannot read the box or the turn may say unknown of both"
$script:blindBox = "yes"; $script:blindTurn = "unknown"
$a = Get-HordeWakeState -Waker $blind -Id $sid
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("state.box")) "state: one that does not offer state.box and still says the box is empty is unknown"
$script:blindBox = "unknown"; $script:blindTurn = "no"
$a = Get-HordeWakeState -Waker $blind -Id $sid
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("state.turn")) "state: one that does not offer state.turn and still says it is not mid-turn is unknown"

$script:nudgeAnswer = { param($id) New-HordeKnown -Value (New-Rang) }
Check ((Send-HordeWakeNudge -Waker $scripted -Id $sid).state -ceq "known") "CONTROL: the scripted waker's good nudge is known"
foreach ($case in @(
        @{ what = "a nudge that throws"; block = { param($id) throw "the pane is gone" }; like = "pane is gone" },
        @{ what = "a nudge that is not an answer"; block = { param($id) "woken" }; like = "not an answer" },
        @{ what = "a nudge that is absent"; block = { param($id) New-HordeAbsent -Note "none" }; like = "absent" },
        @{ what = "a nudge that is text"; block = { param($id) New-HordeKnown -Value "woken" }; like = "not an object" },
        @{ what = "a nudge that names no session"; block = { param($id) New-HordeKnown -Value (New-Rang @{ id = $null }) }; like = "without naming" },
        @{ what = "a nudge about another session"; block = { param($id) New-HordeKnown -Value (New-Rang @{ id = $other }) }; like = "answered about" },
        @{ what = "an outcome outside the list"; block = { param($id) New-HordeKnown -Value (New-Rang @{ outcome = "sent" }) }; like = "outcome" },
        @{ what = "an outcome given as true"; block = { param($id) New-HordeKnown -Value (New-Rang @{ outcome = $true }) }; like = "outcome" },
        @{ what = "a time that is text"; block = { param($id) New-HordeKnown -Value (New-Rang @{ at = "now" }) }; like = "not a time" },
        @{ what = "a time with no zone"; block = { param($id) New-HordeKnown -Value (New-Rang @{ at = (New-Object System.DateTime(2026, 10, 12, 8, 0, 0)) }) }; like = "no zone" },
        @{ what = "busy with no reason"; block = { param($id) New-HordeKnown -Value (New-Rang @{ outcome = "busy" }) }; like = "without saying why" },
        @{ what = "unreachable with a blank reason"; block = { param($id) New-HordeKnown -Value (New-Rang @{ outcome = "unreachable"; reason = "  " }) }; like = "without saying why" },
        @{ what = "nothing with no reason"; block = { param($id) New-HordeKnown -Value (New-Rang @{ outcome = "nothing" }) }; like = "without saying why" },
        @{ what = "killed with no reason"; block = { param($id) New-HordeKnown -Value (New-Rang @{ outcome = "killed" }) }; like = "without saying why" },
        @{ what = "a reason of two lines"; block = { param($id) New-HordeKnown -Value (New-Rang @{ outcome = "busy"; reason = "one`ntwo" }) }; like = "line break" })) {
    $script:nudgeAnswer = $case.block
    $a = Send-HordeWakeNudge -Waker $scripted -Id $sid
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains($case.like)) ("nudge: " + $case.what + " is unknown, saying so")
}
$script:nudgeAnswer = { param($id) New-HordeKnown -Value (New-Rang @{ elapsedMs = 1234 }) }
$a = Send-HordeWakeNudge -Waker $scripted -Id $sid
Check ($a.state -ceq "known" -and $null -ne $a.value.PSObject.Properties["elapsedMs"] -and $a.value.elapsedMs -eq 1234) "nudge: elapsedMs is carried when the waker timed the nudge"
$script:nudgeAnswer = { param($id) New-HordeKnown -Value (New-Rang @{ elapsedMs = "soon" }) }
$a = Send-HordeWakeNudge -Waker $scripted -Id $sid
Check ($a.state -ceq "known" -and $a.value.outcome -ceq "woken" -and $null -eq $a.value.PSObject.Properties["elapsedMs"]) "nudge: an elapsedMs that is no whole number is left out, and the outcome stands"
$script:nudgeAnswer = { param($id) New-HordeKnown -Value (New-Rang @{ outcome = "killed"; reason = "nudge-killed: stopped part-way" }) }
$a = Send-HordeWakeNudge -Waker $scripted -Id $sid
Check ($a.state -ceq "known" -and $a.value.outcome -ceq "killed" -and $a.value.reason -ceq "nudge-killed: stopped part-way") "nudge: killed - the waker stopped its own nudge part-way - is carried with its reason"
$script:nudgeAnswer = { param($id) New-HordeUnknown -Reason "the terminal did not answer" }
$a = Send-HordeWakeNudge -Waker $scripted -Id $sid
Check ($a.state -ceq "unknown" -and "$($a.reason)" -ceq "the terminal did not answer") "nudge: an adapter's own unknown is passed on with its reason"

Reset-HordeMemoryWaker
Complete-HordeSuite -Success "a waker is registered only with valid capabilities, only yes counts, and no answer of an adapter is passed on unchecked"
