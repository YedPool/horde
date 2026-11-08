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
Check ((@(Get-HordeWakerRoles) -join ",") -ceq "warchief,orc,warg,unknown") "the roles are listed in the order the watcher serves them"

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
Write-Host "--- which labels a waker's fleet reserves: the list, NOT ASKED, or unknown - three answers, never mixed ---" -ForegroundColor Cyan

Check ((Get-HordeWakerReservedLabels -Waker $memory).state -ceq "absent" -and "$((Get-HordeWakerReservedLabels -Waker $memory).reason)".Contains("no fleet")) "a waker that registered no Reserved has no fleet to ask: absent, saying so"
$script:reservedAnswer = { New-HordeKnown -Value ([pscustomobject]@{ answered = $true; labels = @("RS", "WW", "SV") }) }
$reserving = Register-HordeWaker -Name "fixture-reserved" -Folder (Join-Path $fx "fixture-reserved") -Targets { New-HordeKnown -Value @() } -State { param($id) New-HordeUnknown -Reason "a fixture" } -Nudge { param($id) New-HordeUnknown -Reason "a fixture" } -Reserved { & $script:reservedAnswer }
$a = Get-HordeWakerReservedLabels -Waker $reserving
Check ($a.state -ceq "known" -and (@($a.value.labels) -join ",") -ceq "RS,WW,SV") "a fleet that answered is known, with its list as it gave it"
$script:reservedAnswer = { New-HordeKnown -Value ([pscustomobject]@{ answered = $true; labels = @() }) }
$a = Get-HordeWakerReservedLabels -Waker $reserving
Check ($a.state -ceq "known" -and @($a.value.labels).Count -eq 0) "a fleet that answered with no labels is a KNOWN empty list: that is an answer, and a comparison with it is made"
$script:reservedAnswer = { New-HordeKnown -Value ([pscustomobject]@{ answered = $false; why = "its tool is older than the question" }) }
$a = Get-HordeWakerReservedLabels -Waker $reserving
Check ($a.state -ceq "absent" -and "$($a.reason)".Contains("could not ask") -and "$($a.reason)".Contains("its tool is older than the question")) "a fleet that could not be asked is ABSENT, with why: never a known empty list, never known at all"
foreach ($bad in @(
        @{ what = "throws"; answer = { throw "boom" } },
        @{ what = "answers with something that is no answer"; answer = { "RS" } },
        @{ what = "does not say whether the fleet was asked"; answer = { New-HordeKnown -Value ([pscustomobject]@{ labels = @("RS") }) } },
        @{ what = "says asked as a word, not true or false"; answer = { New-HordeKnown -Value ([pscustomobject]@{ answered = "yes"; labels = @("RS") }) } },
        @{ what = "says asked and gives no list"; answer = { New-HordeKnown -Value ([pscustomobject]@{ answered = $true }) } },
        @{ what = "gives one label as text, not a list"; answer = { New-HordeKnown -Value ([pscustomobject]@{ answered = $true; labels = "RS" }) } },
        @{ what = "lists a number"; answer = { New-HordeKnown -Value ([pscustomobject]@{ answered = $true; labels = @("RS", 7) }) } },
        @{ what = "lists a blank"; answer = { New-HordeKnown -Value ([pscustomobject]@{ answered = $true; labels = @("RS", " ") }) } },
        @{ what = "lists two words as one label"; answer = { New-HordeKnown -Value ([pscustomobject]@{ answered = $true; labels = @("RS WW") }) } },
        @{ what = "says not asked and does not say why"; answer = { New-HordeKnown -Value ([pscustomobject]@{ answered = $false }) } },
        @{ what = "says not asked with a why of two lines"; answer = { New-HordeKnown -Value ([pscustomobject]@{ answered = $false; why = "one`ntwo" }) } },
        @{ what = "answers absent itself"; answer = { New-HordeAbsent -Note "nothing" } })) {
    $script:reservedAnswer = $bad.answer
    $a = $null
    try { $a = Get-HordeWakerReservedLabels -Waker $reserving } catch { $a = $null }
    Check ($null -ne $a -and $a.state -ceq "unknown") ("a waker that " + $bad.what + " is unknown: not a list, and not 'could not ask'")
}
Check ((Get-HordeWakerReservedLabels -Waker ([pscustomobject]@{ name = "fixture-reserved"; reserved = { New-HordeKnown -Value ([pscustomobject]@{ answered = $true; labels = @("RS") }) } })).state -ceq "unknown") "an object that was never registered is not asked"

Write-Host ""
Write-Host "--- where a waker's program comes from, and whether a person named it ---" -ForegroundColor Cyan

Check ((Get-HordeWakerSource -Waker $memory).state -ceq "absent" -and (Get-HordeWakerSource -Waker $good).state -ceq "absent") "a waker that registered no Source runs no program whose place has to be named: absent"
$script:sourceAnswer = { New-HordeKnown -Value ([pscustomobject]@{ fixed = $true; how = "set as root in a settings file" }) }
$sourced = Register-HordeWaker -Name "fixture-source" -Folder (Join-Path $fx "fixture-source") -Targets { New-HordeKnown -Value @() } -State { param($id) New-HordeUnknown -Reason "a fixture" } -Nudge { param($id) New-HordeUnknown -Reason "a fixture" } -Source { & $script:sourceAnswer }
$a = Get-HordeWakerSource -Waker $sourced
Check ($a.state -ceq "known" -and $a.value.fixed -eq $true -and $a.value.how -ceq "set as root in a settings file") "a program a person named is known, fixed, with how it was named"
$script:sourceAnswer = { New-HordeKnown -Value ([pscustomobject]@{ fixed = $false; how = "found on PATH" }) }
$a = Get-HordeWakerSource -Waker $sourced
Check ($a.state -ceq "known" -and $a.value.fixed -eq $false -and $a.value.how -ceq "found on PATH") "and one that was only found is known, not fixed"
foreach ($case in @(
        @{ what = "something that is not an answer"; answer = { "on PATH" } },
        @{ what = "a value that is not an object"; answer = { New-HordeKnown -Value "on PATH" } },
        @{ what = "fixed as a word"; answer = { New-HordeKnown -Value ([pscustomobject]@{ fixed = "yes"; how = "x" }) } },
        @{ what = "no fixed at all"; answer = { New-HordeKnown -Value ([pscustomobject]@{ how = "x" }) } },
        @{ what = "no how"; answer = { New-HordeKnown -Value ([pscustomobject]@{ fixed = $true }) } },
        @{ what = "a blank how"; answer = { New-HordeKnown -Value ([pscustomobject]@{ fixed = $true; how = "  " }) } },
        @{ what = "a how of two lines"; answer = { New-HordeKnown -Value ([pscustomobject]@{ fixed = $true; how = "one`ntwo" }) } },
        @{ what = "a throw"; answer = { throw "no settings" } },
        @{ what = "its own unknown"; answer = { New-HordeUnknown -Reason "the settings are refused" } })) {
    $script:sourceAnswer = $case.answer
    $a = Get-HordeWakerSource -Waker $sourced
    Check ($a.state -ceq "unknown") ("source: " + $case.what + " is unknown - never read as a program somebody named")
}
Check ((Get-HordeWakerSource -Waker ([pscustomobject]@{ name = "fixture-source"; source = { New-HordeKnown -Value ([pscustomobject]@{ fixed = $true; how = "x" }) } })).state -ceq "unknown") "source: a look-alike that was never registered is not asked"
$script:HordeWakers.Remove("fixture-source")

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
function New-Target { param([hashtable]$Change = @{}) $t = @{ id = $sid; label = "A"; role = "orc"; parent = ""; reachable = "yes"; retired = "no" }; foreach ($k in $Change.Keys) { if ($null -eq $Change[$k]) { $t.Remove($k) } else { $t[$k] = $Change[$k] } }; return [pscustomobject]$t }
function New-State { param([hashtable]$Change = @{}) $s = @{ id = $sid; unreadCount = 1; oldestUnreadAt = $t0; idle = "yes"; boxEmpty = "yes"; midTurn = "no" }; foreach ($k in $Change.Keys) { if ($null -eq $Change[$k]) { $s.Remove($k) } else { $s[$k] = $Change[$k] } }; return [pscustomobject]$s }
function New-Rang { param([hashtable]$Change = @{}) $n = @{ id = $sid; outcome = "woken"; reason = ""; at = $t0 }; foreach ($k in $Change.Keys) { if ($null -eq $Change[$k]) { $n.Remove($k) } else { $n[$k] = $Change[$k] } }; return [pscustomobject]$n }

$script:targetsAnswer = { New-HordeKnown -Value @((New-Target)) }
Check ((Get-HordeWakeTargets -Waker $scripted).state -ceq "known") "CONTROL: the scripted waker's good listing is known"
# retired is carried, and required: a listing that leaves it out is no listing.
foreach ($word in @("yes", "no", "unknown")) {
    $script:retiredWord = $word
    $script:targetsAnswer = { New-HordeKnown -Value @((New-Target @{ retired = $script:retiredWord })) }
    $got = Get-HordeWakeTargets -Waker $scripted
    Check ($got.state -ceq "known" -and @($got.value)[0].retired -ceq $word) ("targets: retired " + $word + " is carried")
}
foreach ($bad in @($null, $true, "maybe", "")) {
    $script:retiredWord = $bad
    $script:targetsAnswer = { New-HordeKnown -Value @((New-Target @{ retired = $script:retiredWord })) }
    $got = Get-HordeWakeTargets -Waker $scripted
    Check ($got.state -ceq "unknown" -and "$($got.reason)".Contains("retired")) ("targets: a retired that is '" + $bad + "' - left out, a boolean, a word outside the list - makes the listing unknown: never read as not retired")
}
$script:targetsAnswer = { New-HordeKnown -Value @((New-Target)) }
# duplicate (T-0116) is OPTIONAL: left out it is no, and only the exact word yes is yes.
$script:targetsAnswer = { New-HordeKnown -Value @((New-Target)) }
Check (@((Get-HordeWakeTargets -Waker $scripted).value)[0].duplicate -ceq "no") "targets: a listing without duplicate carries it as no"
foreach ($pair in @(@("yes", "yes"), @("no", "no"), @("unknown", "no"), @("maybe", "no"), @($true, "no"))) {
    $script:dupWord = $pair[0]
    $script:targetsAnswer = { New-HordeKnown -Value @((New-Target @{ duplicate = $script:dupWord })) }
    $got = Get-HordeWakeTargets -Waker $scripted
    Check ($got.state -ceq "known" -and @($got.value)[0].duplicate -ceq $pair[1]) ("targets: duplicate '" + $pair[0] + "' is carried as " + $pair[1])
}
$script:targetsAnswer = { New-HordeKnown -Value @((New-Target)) }
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

# limited and limitedUntil: three-valued like every other fact, and unknown is never read as no.
$script:stateAnswer = { param($id) New-HordeKnown -Value (New-State) }
$a = Get-HordeWakeState -Waker $scripted -Id $sid
Check ($a.state -ceq "known" -and $a.value.limited -ceq "unknown" -and $null -eq $a.value.limitedUntil) "state: a waker that claims state.limit and says nothing of the limit has not said: unknown, never not limited"
foreach ($word in @("yes", "no", "unknown")) {
    $script:limitWord = $word
    $script:stateAnswer = { param($id) New-HordeKnown -Value (New-State @{ limited = $script:limitWord }) }
    $a = Get-HordeWakeState -Waker $scripted -Id $sid
    Check ($a.state -ceq "known" -and $a.value.limited -ceq $word -and $null -eq $a.value.limitedUntil) ("state: limited " + $word + " is carried")
}
$script:stateAnswer = { param($id) New-HordeKnown -Value (New-State @{ limited = "yes"; limitedUntil = $t0.AddHours(1) }) }
$a = Get-HordeWakeState -Waker $scripted -Id $sid
Check ($a.state -ceq "known" -and $a.value.limited -ceq "yes" -and $a.value.limitedUntil -eq $t0.AddHours(1) -and $a.value.limitedUntil.Kind -eq [System.DateTimeKind]::Utc) "state: limited yes and the time it ends are carried, the time as UTC"
foreach ($word in @("no", "unknown")) {
    $script:limitWord = $word
    $script:stateAnswer = { param($id) New-HordeKnown -Value (New-State @{ limited = $script:limitWord; limitedUntil = $t0.AddHours(1) }) }
    $a = Get-HordeWakeState -Waker $scripted -Id $sid
    Check ($a.state -ceq "known" -and $a.value.limited -ceq $word -and $null -eq $a.value.limitedUntil) ("state: a time beside limited " + $word + " is not read")
}
foreach ($bad in @($true, $false, "maybe", 1)) {
    $script:limitWord = $bad
    $script:stateAnswer = { param($id) New-HordeKnown -Value (New-State @{ limited = $script:limitWord }) }
    $a = Get-HordeWakeState -Waker $scripted -Id $sid
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("limited")) ("state: a limited of '" + $bad + "' - a boolean, a word outside the list - is unknown")
}
$script:stateAnswer = { param($id) New-HordeKnown -Value (New-State @{ limited = "yes"; limitedUntil = (New-Object System.DateTime(2026, 10, 12, 9, 0, 0)) }) }
$a = Get-HordeWakeState -Waker $scripted -Id $sid
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("limitedUntil")) "state: a limitedUntil with no zone cannot be placed, and is unknown"
$script:stateAnswer = { param($id) New-HordeKnown -Value (New-State @{ limited = "yes"; limitedUntil = "soon" }) }
Check ((Get-HordeWakeState -Waker $scripted -Id $sid).state -ceq "unknown") "state: and so is one that is no time"
# betweenTurns: three-valued, on the rule of limited.
$script:stateAnswer = { param($id) New-HordeKnown -Value (New-State) }
$a = Get-HordeWakeState -Waker $scripted -Id $sid
Check ($a.state -ceq "known" -and $a.value.betweenTurns -ceq "unknown" -and $a.value.acked -ceq "unknown" -and $null -eq $a.value.lastAckedAt -and $null -eq $a.value.handedOverCount -and $null -eq $a.value.oldestHandedOverAt) "state: a waker that says nothing of betweenTurns, of what was acknowledged or of what was handed over has not said: each is unknown - never no, never 0, never 'never'"
foreach ($word in @("yes", "no", "unknown")) {
    $script:limitWord = $word
    $script:stateAnswer = { param($id) New-HordeKnown -Value (New-State @{ betweenTurns = $script:limitWord }) }
    $a = Get-HordeWakeState -Waker $scripted -Id $sid
    Check ($a.state -ceq "known" -and $a.value.betweenTurns -ceq $word) ("state: betweenTurns " + $word + " is carried")
}
foreach ($bad in @($true, "maybe", 1)) {
    $script:limitWord = $bad
    $script:stateAnswer = { param($id) New-HordeKnown -Value (New-State @{ betweenTurns = $script:limitWord }) }
    Check ((Get-HordeWakeState -Waker $scripted -Id $sid).state -ceq "unknown") ("state: a betweenTurns of '" + $bad + "' is unknown")
}
# acked and lastAckedAt; handedOverCount and oldestHandedOverAt.
$script:stateAnswer = { param($id) New-HordeKnown -Value (New-State @{ acked = "known"; lastAckedAt = $t0.AddMinutes(-5); handedOverCount = 2; oldestHandedOverAt = $t0.AddMinutes(-1) }) }
$a = Get-HordeWakeState -Waker $scripted -Id $sid
Check ($a.state -ceq "known" -and $a.value.acked -ceq "known" -and $a.value.lastAckedAt -eq $t0.AddMinutes(-5) -and $a.value.lastAckedAt.Kind -eq [System.DateTimeKind]::Utc -and $a.value.handedOverCount -eq 2 -and $a.value.oldestHandedOverAt -eq $t0.AddMinutes(-1)) "state: what a session last acknowledged, and what was handed over to it, are carried, the times as UTC"
$script:stateAnswer = { param($id) New-HordeKnown -Value (New-State @{ acked = "known" }) }
$a = Get-HordeWakeState -Waker $scripted -Id $sid
Check ($a.state -ceq "known" -and $a.value.acked -ceq "known" -and $null -eq $a.value.lastAckedAt) "state: acked known with no time is a session that has never acknowledged any"
$script:stateAnswer = { param($id) New-HordeKnown -Value (New-State @{ acked = "unknown"; lastAckedAt = $t0 }) }
$a = Get-HordeWakeState -Waker $scripted -Id $sid
Check ($a.state -ceq "known" -and $a.value.acked -ceq "unknown" -and $null -eq $a.value.lastAckedAt) "state: a time beside acked unknown is not read: it is no evidence of anything"
$script:stateAnswer = { param($id) New-HordeKnown -Value (New-State @{ handedOverCount = 0; oldestHandedOverAt = $t0 }) }
$a = Get-HordeWakeState -Waker $scripted -Id $sid
Check ($a.state -ceq "known" -and $a.value.handedOverCount -eq 0 -and $null -eq $a.value.oldestHandedOverAt) "state: a handed-over count of 0 is known, and has no oldest"
foreach ($case in @(
        @{ what = "an acked that is a boolean"; change = @{ acked = $true } },
        @{ what = "an acked outside its two words"; change = @{ acked = "yes" } },
        @{ what = "a lastAckedAt with no zone"; change = @{ acked = "known"; lastAckedAt = (New-Object System.DateTime(2026, 10, 12, 9, 0, 0)) } },
        @{ what = "a lastAckedAt that is no time"; change = @{ acked = "known"; lastAckedAt = "lately" } },
        @{ what = "a handedOverCount below 0"; change = @{ handedOverCount = -1 } },
        @{ what = "a handedOverCount that is text"; change = @{ handedOverCount = "2" } },
        @{ what = "an oldestHandedOverAt with no zone"; change = @{ handedOverCount = 1; oldestHandedOverAt = (New-Object System.DateTime(2026, 10, 12, 9, 0, 0)) } })) {
    $script:changeNow = $case.change
    $script:stateAnswer = { param($id) New-HordeKnown -Value (New-State $script:changeNow) }
    Check ((Get-HordeWakeState -Waker $scripted -Id $sid).state -ceq "unknown") ("state: " + $case.what + " is unknown")
}
# A WAKER THAT DOES NOT CLAIM state.limit cannot tell at all, and for it alone the answer is no.
$script:noLimit = $null; $script:noBetween = $null
$deaf = Register-HordeWaker -Name "fixture-no-limit" -Folder (Join-Path $fx "fixture-no-limit") -Targets { New-HordeKnown -Value @() } -Nudge { param($id) New-HordeUnknown -Reason "a fixture" } -State {
    param($id)
    $v = [ordered]@{ id = $id; unreadCount = 0; oldestUnreadAt = $null; idle = "yes"; boxEmpty = "yes"; midTurn = "no" }
    if ($null -ne $script:noLimit) { $v["limited"] = $script:noLimit }
    if ($null -ne $script:noBetween) { $v["betweenTurns"] = $script:noBetween }
    New-HordeKnown -Value ([pscustomobject]$v)
}
Check (-not (Test-HordeWakerClaims -Waker $deaf -Capability "state.limit") -and (Test-HordeWakerClaims -Waker $scripted -Capability "state.limit")) "CONTROL: one waker says it cannot tell a usage limit at all, and one says it can"
$a = Get-HordeWakeState -Waker $deaf -Id $sid
Check ($a.state -ceq "known" -and $a.value.limited -ceq "no") "state: a waker that does not offer state.limit and says nothing of the limit is read as not limited - the one case where saying nothing is no"
$script:noLimit = "no"
Check ((Get-HordeWakeState -Waker $deaf -Id $sid).value.limited -ceq "no") "state: and it may say no"
foreach ($word in @("yes", "unknown")) {
    $script:noLimit = $word
    $a = Get-HordeWakeState -Waker $deaf -Id $sid
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("state.limit")) ("state: one that does not offer state.limit and still says limited " + $word + " is unknown: what it cannot read, it cannot claim")
}
$script:noLimit = $null
# ...and the same for state.between-turns, which this waker does not offer either.
$a = Get-HordeWakeState -Waker $deaf -Id $sid
Check ($a.state -ceq "known" -and $a.value.betweenTurns -ceq "no") "state: a waker that does not offer state.between-turns and says nothing of it is read as no"
foreach ($word in @("yes", "unknown")) {
    $script:noBetween = $word
    $a = Get-HordeWakeState -Waker $deaf -Id $sid
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("state.between-turns")) ("state: one that does not offer state.between-turns and still says betweenTurns " + $word + " is unknown")
}
$script:noBetween = $null
# It is not one of the five a live run requires: a harness with no usage limit can still be the waker.
Check ((Resolve-HordeWaker -Name "fixture-no-limit" -Require @("nudge.pointer-only", "state.box", "state.turn", "reach.unseen", "nudge.guarded")).state -ceq "known" -and (Resolve-HordeWaker -Name "fixture-no-limit" -Require @("state.limit")).state -ceq "unknown") "state.limit is not one of the five a live run requires, and a caller that requires it of this waker is refused"

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
$script:nudgeAnswer = { param($id) New-HordeKnown -Value (New-Rang @{ rule = "between-turns-background-work" }) }
$a = Send-HordeWakeNudge -Waker $scripted -Id $sid
Check ($a.state -ceq "known" -and $null -ne $a.value.PSObject.Properties["rule"] -and $a.value.rule -ceq "between-turns-background-work") "nudge: the rule the waker names is carried"
$script:nudgeAnswer = { param($id) New-HordeKnown -Value (New-Rang @{ rule = "a-rule-nobody-has-heard-of-yet" }) }
$a = Send-HordeWakeNudge -Waker $scripted -Id $sid
Check ($a.state -ceq "known" -and $a.value.rule -ceq "a-rule-nobody-has-heard-of-yet") "nudge: and so is one the port has never heard of: a new name is not an error"
foreach ($bad in @("", "  ", 7, "two`nlines")) {
    $script:badRule = $bad
    $script:nudgeAnswer = { param($id) New-HordeKnown -Value (New-Rang @{ rule = $script:badRule }) }
    $a = Send-HordeWakeNudge -Waker $scripted -Id $sid
    Check ($a.state -ceq "known" -and $a.value.outcome -ceq "woken" -and $null -eq $a.value.PSObject.Properties["rule"]) ("nudge: a rule that is '" + "$bad".Trim() + "' - blank, not text, two lines - is left out, and the outcome stands")
}
$script:nudgeAnswer = { param($id) New-HordeKnown -Value (New-Rang @{ outcome = "killed"; reason = "nudge-killed: stopped part-way" }) }
$a = Send-HordeWakeNudge -Waker $scripted -Id $sid
Check ($a.state -ceq "known" -and $a.value.outcome -ceq "killed" -and $a.value.reason -ceq "nudge-killed: stopped part-way") "nudge: killed - the waker stopped its own nudge part-way - is carried with its reason"
$script:nudgeAnswer = { param($id) New-HordeUnknown -Reason "the terminal did not answer" }
$a = Send-HordeWakeNudge -Waker $scripted -Id $sid
Check ($a.state -ceq "unknown" -and "$($a.reason)" -ceq "the terminal did not answer") "nudge: an adapter's own unknown is passed on with its reason"

Write-Host ""
Write-Host "--- a read-only view of a waker reads as it does and cannot nudge (T-0116) ---" -ForegroundColor Cyan

$script:calls = 0
$view = Get-HordeWakerReadOnly -Waker $good
Check ($null -ne $view -and $view.name -ceq "fixture-good" -and $null -eq $view.nudge) "the view of a registered waker has its name and no nudge"
Check ($null -ne $good.nudge) "and the registered waker keeps its own"
Check ([object]::ReferenceEquals($view, (Get-HordeWakerReadOnly -Waker $good))) "asked twice, it is the same view"
Check ([object]::ReferenceEquals($view, (Get-HordeWakerReadOnly -Waker $view))) "the view of a view is the view"
Check ((Get-HordeWakeTargets -Waker $view).state -ceq "known" -and $script:calls -eq 1) "the view's targets are read by the real waker's block"
$null = Get-HordeWakeState -Waker $view -Id $sid
Check ($script:calls -eq 2) "and so is its state"
$a = Send-HordeWakeNudge -Waker $view -Id $sid
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("without a nudge") -and $script:calls -eq 2) "a nudge through the view is refused with the reason, and no block ran"
$null = Send-HordeWakeNudge -Waker $good -Id $sid
Check ($script:calls -eq 3) "CONTROL: the same nudge through the registered waker does run"
$copy = [pscustomobject]@{ PSTypeName = "Horde.Waker"; name = "fixture-good"; folder = $good.folder; capabilities = $good.capabilities; targets = { $script:calls++ }; state = { $script:calls++ }; nudge = { $script:calls++ } }
$a = Send-HordeWakeNudge -Waker $copy -Id $sid
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("not registered") -and $script:calls -eq 3) "a look-alike carrying a nudge is still refused: the view is the port's own object, not a shape"
Check ([object]::ReferenceEquals($copy, (Get-HordeWakerReadOnly -Waker $copy))) "the view of a look-alike is the look-alike, which the port refuses for every call"
Check ($null -eq (Get-HordeWakerReadOnly -Waker $null)) "and of nothing is nothing"

Reset-HordeMemoryWaker
Complete-HordeSuite -Success "a waker is registered only with valid capabilities, only yes counts, and no answer of an adapter is passed on unchecked"
