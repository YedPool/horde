# DOES THE RESTORE SOURCE POST EXACTLY THE RESUME MAILS IT SHOULD, ONCE EACH, AND NONE IN SHADOW?
#
# core/RestoreSource.ps1 - the sender that tells the orcs to resume after every session was started or
# restored together. It only posts; the wake watcher (core/Wake.ps1, test/test-wake.ps1) is what knocks
# for that mail. Replayed on a clock this suite moves by hand, with a poster of this suite's:
#   - A REPLAY of a real timeline: twelve sessions restarted inside 150 s. Orcs are told to resume at
#     once; a subsession, or a session of no known role, never is - an orc mails the ones it still
#     needs; and the warchief is told at 300 s when nothing moved - each mail under an id that never
#     changes.
#   - NO RESTORE: a quiet night, one restarted session, too few, too small a share.
#   - A PASS posts each mail once, tries again what the poster could not take, and in shadow posts none.
#   - THE RUNNING SESSIONS are read from the two stores handed in, never from this machine.
# The file (restore.json) is written under a home this suite made and removes.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "test\lib\FleetPin.ps1")
. (Join-Path $root "test\lib\MessengerPins.ps1")
# PINNED FIRST: an empty fleet and a home of this suite's, so nothing below can read or write the real ones.
$fleetPin = Enter-HordeTestEmptyFleet
$pinned = Enter-HordeTestPinnedHome -Root $root
. (Join-Path $root "core\RestoreSource.ps1")

$settings = Get-HordeRestoreSettings
$t0 = New-Object System.DateTime(2026, 10, 12, 8, 0, 0, [System.DateTimeKind]::Utc)

function At { param([double]$Seconds) return $t0.AddSeconds($Seconds) }
function Sid { param([int]$N) return ("0a000000-0000-4000-8000-" + $N.ToString("000000000000")) }
function Kinds { param($Result) return (@($Result.entries | ForEach-Object { $_.kind }) -join ",") }

try {
Write-Host ""
Write-Host "--- the restore source: a replay of twelve sessions restarted inside 150 s ---" -ForegroundColor Cyan

# One warchief (1), three orcs (2 to 4), eight goblins (5 to 12: 5 to 7 under orc 2, 8 to 10 under orc 3,
# 11 and 12 under orc 4). Each started 13 s after the last, and wrote its status once, 4 s after starting.
function New-Restored {
    param([hashtable]$MovedAfter = @{})
    $out = @()
    for ($n = 1; $n -le 12; $n++) {
        $role = "goblin"; $parent = ""
        if ($n -eq 1) { $role = "warchief" } elseif ($n -le 4) { $role = "orc"; $parent = Sid 1 }
        elseif ($n -le 7) { $parent = Sid 2 } elseif ($n -le 10) { $parent = Sid 3 } else { $parent = Sid 4 }
        $start = At (($n - 1) * 13)
        $change = $start.AddSeconds(4)
        if ($MovedAfter.ContainsKey($n)) { $change = $start.AddSeconds($MovedAfter[$n]) }
        $out += [pscustomobject]@{ id = (Sid $n); role = $role; parent = $parent; startedAt = $start; lastChangeAt = $change }
    }
    return $out
}
$end = 143
$fleet = New-Restored
$f = Get-HordeRestoreFinding -Sessions $fleet -Now (At ($end + 10)) -Settings $settings
Check ($f.state -ceq "known") "twelve sessions that started inside 150 s are a restore"
Check ($f.state -ceq "known" -and $f.value.windowStart -eq $t0 -and $f.value.windowEnd -eq (At $end) -and @($f.value.members).Count -eq 12 -and @($f.value.notMoved).Count -eq 12) "its window runs from the first start to the last, with all twelve as members and none moved"
Check ($f.state -ceq "known" -and $f.value.restoreId -cmatch '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z') "its id is a lowercase uuid"
$again = Get-HordeRestoreFinding -Sessions $fleet -Now (At ($end + 250)) -Settings $settings
Check ($again.state -ceq "known" -and $again.value.restoreId -ceq $f.value.restoreId) "and the same id on a later pass"
$shifted = @($fleet | ForEach-Object { [pscustomobject]@{ id = $_.id; role = $_.role; parent = $_.parent; startedAt = $_.startedAt.AddMinutes(7); lastChangeAt = $_.lastChangeAt.AddMinutes(7) } })
$f7 = Get-HordeRestoreFinding -Sessions $shifted -Now (At 2000) -Settings $settings
Check ($f7.state -ceq "known" -and $f7.value.restoreId -cne $f.value.restoreId) "a restore that began in another minute has another id"

$plan = @(Get-HordeResumePlan -Finding $f -Now (At ($end + 10)) -Settings $settings)
$orcs = @(2, 3, 4 | ForEach-Object { Sid $_ })
Check ((@($plan | ForEach-Object { $_.to } | Sort-Object) -join ",") -ceq ($orcs -join ",") -and @($plan | Where-Object { $_.kind -cne "resume" }).Count -eq 0) "all three orcs are told to resume at once, and nobody else"
Check (@($plan | Where-Object { $_.body -cne $settings.resumeText }).Count -eq 0 -and $settings.resumeText.StartsWith("START OR RESTORE. Every session on this machine was started or restored together") -and $settings.resumeText.EndsWith("mail the subsessions you still need: they are not woken unless you ask.")) "each with the resume text, which covers a start as well as a restore and tells an orc its subsessions are not woken unless it asks"
$unroled = @($fleet | ForEach-Object { if ($_.id -ceq (Sid 12)) { [pscustomobject]@{ id = $_.id; role = "unknown"; parent = $_.parent; startedAt = $_.startedAt; lastChangeAt = $_.lastChangeAt } } else { $_ } })
foreach ($after in @(0, 180, 600)) {
    $planAt = @(Get-HordeResumePlan -Finding $f -Now (At ($end + $after)) -Settings $settings | Where-Object { $_.kind -ceq "resume" })
    Check ((@($planAt | ForEach-Object { $_.to } | Sort-Object) -join ",") -ceq ($orcs -join ",")) ("" + $after + " s after the last start, with no orc moved, the orcs are told and no goblin is")
    $planAt = @(Get-HordeResumePlan -Finding (Get-HordeRestoreFinding -Sessions $unroled -Now (At ($end + $after)) -Settings $settings) -Now (At ($end + $after)) -Settings $settings | Where-Object { $_.kind -ceq "resume" })
    Check ($planAt.Count -eq 3 -and @($planAt | Where-Object { $_.to -ceq (Sid 12) }).Count -eq 0) ("" + $after + " s after it, a session of no known role is not told either")
}
$oneMoved = Get-HordeRestoreFinding -Sessions (New-Restored -MovedAfter @{ 2 = 90 }) -Now (At ($end + 100)) -Settings $settings
$planMoved = @(Get-HordeResumePlan -Finding $oneMoved -Now (At ($end + 100)) -Settings $settings)
Check ((@($planMoved | ForEach-Object { $_.to } | Sort-Object) -join ",") -ceq (@(3, 4 | ForEach-Object { Sid $_ }) -join ",")) "once an orc has moved it is not told again - and its goblins are still not told: it mails the ones it needs"
$planMoved600 = @(Get-HordeResumePlan -Finding (Get-HordeRestoreFinding -Sessions (New-Restored -MovedAfter @{ 2 = 90 }) -Now (At ($end + 600)) -Settings $settings) -Now (At ($end + 600)) -Settings $settings)
Check ((@($planMoved600 | ForEach-Object { $_.to } | Sort-Object) -join ",") -ceq (@(3, 4 | ForEach-Object { Sid $_ }) -join ",")) "nor are they at 600 s"
Check (@($oneMoved.value.notMoved).Count -eq 11 -and @($oneMoved.value.members | Where-Object { $_.moved }).Count -eq 1) "a member has moved when its status changed at least movedSeconds after it started"
$barely = Get-HordeRestoreFinding -Sessions (New-Restored -MovedAfter @{ 2 = 59 }) -Now (At ($end + 100)) -Settings $settings
Check (@($barely.value.notMoved).Count -eq 12) "and has not at 59 s"
$plan180 = @(Get-HordeResumePlan -Finding $f -Now (At ($end + 180)) -Settings $settings)
Check ($plan180.Count -eq 3 -and @($plan180 | Where-Object { $_.to -ceq (Sid 1) }).Count -eq 0) "and the warchief is never told to resume"

$plan299 = @(Get-HordeResumePlan -Finding $f -Now (At ($end + 299)) -Settings $settings)
Check (@($plan299 | Where-Object { $_.kind -ceq "stall" }).Count -eq 0) "there is no stall notice 299 s after the last start"
$plan300 = @(Get-HordeResumePlan -Finding $f -Now (At ($end + 300)) -Settings $settings)
$stall = @($plan300 | Where-Object { $_.kind -ceq "stall" })
Check ($stall.Count -eq 1 -and $stall[0].to -ceq (Sid 1) -and $stall[0].body -ceq $settings.stallText) "at 300 s, with nothing moved, the warchief is told the restore has stalled"
$planLate = @(Get-HordeResumePlan -Finding (Get-HordeRestoreFinding -Sessions (New-Restored -MovedAfter @{ 7 = 200 }) -Now (At ($end + 400)) -Settings $settings) -Now (At ($end + 400)) -Settings $settings)
Check (@($planLate | Where-Object { $_.kind -ceq "stall" }).Count -eq 0) "and it is not, at any time, once one member has moved"
$noChief = Get-HordeRestoreFinding -Sessions @($fleet | Where-Object { $_.role -cne "warchief" }) -Now (At ($end + 300)) -Settings $settings
$stallNobody = @(@(Get-HordeResumePlan -Finding $noChief -Now (At ($end + 300)) -Settings $settings) | Where-Object { $_.kind -ceq "stall" })
Check ($stallNobody.Count -eq 1 -and $stallNobody[0].to -ceq "") "with no warchief among the restored sessions the stall notice is addressed to nobody, and says so"

$ids1 = (@($plan300 | Sort-Object to | ForEach-Object { $_.to + "=" + $_.messageId }) -join ";")
$ids2 = (@(Get-HordeResumePlan -Finding $again -Now (At ($end + 300)) -Settings $settings | Sort-Object to | ForEach-Object { $_.to + "=" + $_.messageId }) -join ";")
Check ($ids1 -ceq $ids2 -and $plan300.Count -eq 4) "a plan made again names every mail by the same messageId: three orcs and the stall notice"
Check (@($plan300 | ForEach-Object { $_.messageId } | Sort-Object -Unique).Count -eq 4 -and @($plan300 | Where-Object { $_.messageId -cnotmatch '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z' }).Count -eq 0) "each mail has an id of its own, a lowercase uuid"
$orcId = @($plan | Where-Object { $_.to -ceq (Sid 2) })[0].messageId
Check (@($plan300 | Where-Object { $_.to -ceq (Sid 2) })[0].messageId -ceq $orcId) "and an orc's resume mail has the id at 300 s that it had at 10 s"

Write-Host ""
Write-Host "--- the restore source in a pass: posted once, retried when the post could not say ---" -ForegroundColor Cyan

$script:mails = New-Object System.Collections.ArrayList
$script:postWorks = $true
$poster = { param($m) [void]$script:mails.Add($m); if ($script:postWorks) { New-HordeKnown -Value $true } else { New-HordeUnknown -Reason "the mailbox is locked" } }
$r = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 10)) -Settings $settings -Post $poster -Posted @{}
Check ($script:mails.Count -eq 3 -and (Kinds $r) -ceq "post,post,post" -and @($r.entries | Where-Object { $_.outcome -cne "posted" -or $_.messageId -eq "" }).Count -eq 0) "three resume mails are posted, each journaled with its messageId"
$r2 = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 13)) -Settings $settings -Post $poster -Posted $r.posted
Check ($script:mails.Count -eq 3 -and @($r2.entries).Count -eq 0) "the next pass posts none of them again"
$r180 = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 180)) -Settings $settings -Post $poster -Posted $r2.posted
Check ($script:mails.Count -eq 3 -and @($r180.entries).Count -eq 0) "nor, at 180 s, anything to a goblin"
$script:postWorks = $false
$script:mails.Clear()
$r3 = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 10)) -Settings $settings -Post $poster -Posted @{}
Check ($script:mails.Count -eq 3 -and @($r3.entries | Where-Object { $_.outcome -ceq "unknown" -and $_.reason -ceq "the mailbox is locked" }).Count -eq 3 -and $r3.posted.Count -eq 0) "a post that could not say is journaled unknown with its reason, and is not marked posted"
$script:postWorks = $true
$r4 = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 13)) -Settings $settings -Post $poster -Posted $r3.posted
$sameIds = ((@($script:mails[0..2] | ForEach-Object { $_.messageId } | Sort-Object) -join ",") -ceq (@($script:mails[3..5] | ForEach-Object { $_.messageId } | Sort-Object) -join ","))
Check ($script:mails.Count -eq 6 -and $r4.posted.Count -eq 3 -and $sameIds) "so the next pass tries those three again, under the same ids"
$r5 = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 300)) -Settings $settings -Post { param($m) throw "the poster fell over" } -Posted $r4.posted
Check ((Kinds $r5) -ceq "stall" -and $r5.entries[0].outcome -ceq "unknown" -and "$($r5.entries[0].reason)".Contains("fell over")) "a poster that throws is an unknown outcome, never a throw of the pass"
$r6 = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 300)) -Settings $settings -Posted $r4.posted
Check ((Kinds $r6) -ceq "stall" -and $r6.entries[0].outcome -ceq "unposted") "and a live pass given nothing to post through says the mail was not posted"

Write-Host ""
Write-Host "--- no restore: a quiet night, one restarted session, too few, too small a share ---" -ForegroundColor Cyan

$quiet = @(1..10 | ForEach-Object { [pscustomobject]@{ id = (Sid $_); role = "goblin"; parent = ""; startedAt = (At ($_ * -7200)); lastChangeAt = (At ($_ * -7200 + 3)) } })
$f = Get-HordeRestoreFinding -Sessions $quiet -Now $t0 -Settings $settings
Check ($f.state -ceq "absent" -and "$($f.reason)" -ne "") "a quiet night, with start times hours apart, is no restore, and the answer says why"
Check (@(Get-HordeResumePlan -Finding $f -Now $t0 -Settings $settings).Count -eq 0) "and nothing is planned for it"
$oneBack = @($quiet | ForEach-Object { $_ })
$oneBack[4] = [pscustomobject]@{ id = (Sid 5); role = "goblin"; parent = ""; startedAt = (At -30); lastChangeAt = (At -28) }
Check ((Get-HordeRestoreFinding -Sessions $oneBack -Now $t0 -Settings $settings).state -ceq "absent") "one restarted session among ten is no restore"
$two = @(1, 2 | ForEach-Object { [pscustomobject]@{ id = (Sid $_); role = "orc"; parent = ""; startedAt = (At ($_ * -5)); lastChangeAt = (At ($_ * -5 + 1)) } })
Check ((Get-HordeRestoreFinding -Sessions $two -Now $t0 -Settings $settings).state -ceq "absent") "two sessions that started together are fewer than a restore takes"
$twoOfThree = @($two) + [pscustomobject]@{ id = (Sid 3); role = "orc"; parent = ""; startedAt = (At -90000); lastChangeAt = (At -80000) }
Check ((Get-HordeRestoreFinding -Sessions $twoOfThree -Now $t0 -Settings $settings).state -ceq "absent") "two of three together is a large share and still fewer than a restore takes"
function New-Mixed { param([int]$Together) return @(1..10 | ForEach-Object { if ($_ -le $Together) { [pscustomobject]@{ id = (Sid $_); role = "orc"; parent = ""; startedAt = (At (-100 + $_)); lastChangeAt = (At (-98 + $_)) } } else { [pscustomobject]@{ id = (Sid $_); role = "orc"; parent = ""; startedAt = (At ($_ * -7200)); lastChangeAt = (At ($_ * -7200 + 900)) } } }) }
Check ((Get-HordeRestoreFinding -Sessions (New-Mixed 5) -Now $t0 -Settings $settings).state -ceq "absent") "five of ten together is under the share a restore takes"
$six = Get-HordeRestoreFinding -Sessions (New-Mixed 6) -Now $t0 -Settings $settings
Check ($six.state -ceq "known" -and @($six.value.members).Count -eq 6) "six of ten together is a restore, of those six"
$wide = @(1..4 | ForEach-Object { [pscustomobject]@{ id = (Sid $_); role = "orc"; parent = ""; startedAt = (At ($_ * 300)); lastChangeAt = (At ($_ * 300 + 1)) } })
$w = Get-HordeRestoreFinding -Sessions $wide -Now (At 2000) -Settings $settings
Check ($w.state -ceq "known" -and @($w.value.members).Count -eq 3 -and $w.value.windowStart -eq (At 300)) "the window is restoreWindowSeconds long: of four sessions 300 s apart, three fall in one"
Check ((Get-HordeRestoreFinding -Sessions $fleet -Now (At ($end + 86401)) -Settings $settings).state -ceq "absent") "a restore more than a day old is history"
Check ((Get-HordeRestoreFinding -Sessions @() -Now $t0 -Settings $settings).state -ceq "absent") "no sessions at all is no restore"


Write-Host ""
Write-Host "--- shadow: what it would post is journaled, and none of it is posted ---" -ForegroundColor Cyan

$script:posts = 0
$posted = @{}
$kinds = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt 40; $i++) {
    $r = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 250 + $i * 3)) -Settings $settings -Shadow -Post { param($m) $script:posts++; New-HordeKnown -Value $true } -Posted $posted
    $posted = $r.posted
    foreach ($e in @($r.entries)) { [void]$kinds.Add($e.kind) }
}
Check ($script:posts -eq 0) "forty shadow passes over a restore post zero mails, with a poster in hand"
Check ((@($kinds | Sort-Object) -join ",") -ceq "would-post,would-post,would-post,would-stall") ("the journal says would-post once for each of the three orcs and would-stall once, not once a pass (" + ($kinds -join ",") + ")")
Check (Throws { Get-HordeRestoreSettings -Overrides @{ stallSecond = 9 } } "not a restore setting") "a setting that is not one is refused, not silently left at its default"

Write-Host ""
Write-Host "--- the file: what was posted, under a home of this suite's ---" -ForegroundColor Cyan

Check ((Read-HordeRestoreState).state -ceq "absent") "with nothing saved the state is absent"
Save-HordeRestoreState -Posted @{ "0d000000-0000-4000-8000-000000000001" = $true }
$back = Read-HordeRestoreState
Check ($back.state -ceq "known" -and $back.value.posted.Count -eq 1 -and $back.value.posted.ContainsKey("0d000000-0000-4000-8000-000000000001")) "the mails already posted save and read back"
[System.IO.File]::WriteAllText((Join-Path (Get-HordeWakeFolder) "restore.json"), "{ not json")
Check ((Read-HordeRestoreState).state -ceq "unknown") "a saved state that cannot be read is unknown, not absent"

Write-Host ""
Write-Host "--- the running sessions, from the two stores handed in ---" -ForegroundColor Cyan

function New-Record {
    param($StartedAt, $StatusAt, [string]$Agent = "agent-one")
    $fields = @{}
    $fields["agent"] = New-HordeKnown -Value $Agent
    $fields["startedAt"] = $(if ($null -ne $StartedAt) { New-HordeKnown -Value $StartedAt } else { New-HordeUnknown -Reason "the agent writes no start" })
    $fields["liveStatus"] = $(if ($null -ne $StatusAt) { New-HordeKnown -Value "idle" -ObservedAt $StatusAt } else { New-HordeUnknown -Reason "the process is gone" })
    return [pscustomobject]@{ fields = $fields }
}
function New-Listing {
    param([hashtable]$Records, $Whole = (New-HordeKnown -Value $true), $WholeOne = (New-HordeKnown -Value $true))
    $complete = [ordered]@{ "agent-one" = $WholeOne; "agent-two" = $Whole }
    return [pscustomobject]@{ records = $Records; complete = $complete }
}
function New-Registry {
    param([hashtable]$Records, $Whole = (New-HordeKnown -Value $true))
    $held = @{}
    foreach ($k in $Records.Keys) { $held[$k] = [pscustomobject]@{ id = $k; record = [pscustomobject]$Records[$k] } }
    return [pscustomobject]@{ records = $held; complete = $Whole }
}
$records = @{}
$records[(Sid 1)] = New-Record (At 0) (At 4)
$records[(Sid 2)] = New-Record (At 13) (At 80)
$records[(Sid 3)] = New-Record (At 26) $null
$records[(Sid 4)] = New-Record $null (At 30)
$records[(Sid 5)] = New-Record (At 39) (At 41) "agent-two"
$registry = New-Registry @{ (Sid 1) = @{ role = "master" }; (Sid 2) = @{ role = "orchestrator"; parent = (Sid 1) }; (Sid 5) = @{ parent = (Sid 2); role = "" } }
$a = Get-HordeRestoreSessions -Identity (New-Listing $records) -Registry $registry
Check ($a.state -ceq "known" -and @($a.leftOut).Count -eq 0) "with every listing whole nothing is left out"
$got = @()
if ($a.state -ceq "known") { $got = @($a.value | Sort-Object id) }
Check ($a.state -ceq "known" -and (@($got | ForEach-Object { $_.id }) -join ",") -ceq (@(1, 2, 5 | ForEach-Object { Sid $_ }) -join ",")) "only a session whose start and live status are both known is a running session"
Check ($got.Count -eq 3 -and $got[0].role -ceq "warchief" -and $got[1].role -ceq "orc" -and $got[1].parent -ceq (Sid 1) -and $got[0].parent -ceq "") "role and parent come from the registry record, the stored role names read as Horde's"
Check ($got.Count -eq 3 -and $got[2].role -ceq "unknown" -and $got[2].parent -ceq (Sid 2)) "a record with no role is unknown, never guessed"
Check ($got.Count -eq 3 -and $got[1].startedAt -eq (At 13) -and $got[1].lastChangeAt -eq (At 80)) "startedAt is the session's own, and lastChangeAt is when its live status was written"
$a = Get-HordeRestoreSessions -Identity (New-Listing $records -Whole (New-HordeUnknown -Reason "one control file could not be read")) -Registry $registry
$got = @()
if ($a.state -ceq "known") { $got = @($a.value | Sort-Object id) }
Check ($a.state -ceq "known" -and (@($got | ForEach-Object { $_.id }) -join ",") -ceq (@(1, 2 | ForEach-Object { Sid $_ }) -join ",")) "with one agent's listing whole and the other's not, the answer is known, with the whole one's sessions and none of the other's"
Check ($a.state -ceq "known" -and @($a.leftOut).Count -eq 1 -and $a.leftOut[0].agent -ceq "agent-two" -and $a.leftOut[0].reason -ceq "one control file could not be read") "and it names the agent it left out, and why"
Check ((Get-HordeRestoreFinding -Sessions $a.value -Now (At 100) -Settings (Get-HordeRestoreSettings -Overrides @{ restoreMinSessions = 2 })).state -ceq "known") "its value is still the plain list the restore finding takes"
$a = Get-HordeRestoreSessions -Identity (New-Listing $records -Whole (New-HordeUnknown -Reason "one control file could not be read") -WholeOne (New-HordeUnknown -Reason "there is no control directory")) -Registry $registry
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("agent-one: there is no control directory") -and "$($a.reason)".Contains("agent-two: one control file could not be read")) "with no agent's listing whole the answer is unknown, naming each and why"
$a = Get-HordeRestoreSessions -Identity (New-Listing $records) -Registry (New-Registry @{} -Whole (New-HordeUnknown -Reason "there is no registry"))
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("registry")) "and so is a registry that is not whole"
$a = Get-HordeRestoreSessions -Identity (New-Listing @{}) -Registry (New-Registry @{})
Check ($a.state -ceq "known" -and @($a.value).Count -eq 0) "an empty fleet is a known empty list"

} finally {
    Exit-HordeTestPinnedHome -State $pinned
    Exit-HordeTestEmptyFleet -Pin $fleetPin
}

Complete-HordeSuite -Success "the restore source finds a restore, posts each orc its resume mail once, tells the warchief when nothing moved, and in shadow posts nothing"
