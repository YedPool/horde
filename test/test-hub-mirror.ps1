# WHAT DOES THE HUB SAY ABOUT A NODE'S SESSIONS, FROM WHAT IT LAST HEARD?
#
# Remote plan step R13a. remote/Mirror.ps1 is pure: a mirror, the pulls that change it, and the rows and
# faults read from it. This suite holds its four rules, each with a control that shows the check can see
# the opposite:
#   - a node whose pull failed makes every one of its sessions unknown, "node D unreachable since T",
#     T the first failure and not the latest retry; never absent;
#   - a partial inventory never marks a session absent: a session left out is carried, unknown;
#   - a dropped link resumes with nothing lost and nothing twice: a pull is a whole inventory;
#   - a key listed by two devices is a fault, never resolved by picking one.
# And the clock (R6) as the mirror uses it: a field is aged by the node's own age for it, on the hub's
# clock, so a fast node clock does not make old data fresh.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "remote\Mirror.ps1")

$devA = "0f8fad5b-d9cb-469f-a165-70867728950e"
$devB = "7c9e6679-7425-40de-944b-e07fc1f90ae7"
$s1 = "aaaaaaaa-0000-4000-8000-000000000001"
$s2 = "aaaaaaaa-0000-4000-8000-000000000002"
$s3 = "aaaaaaaa-0000-4000-8000-000000000003"
$t0 = [datetime]::SpecifyKind([datetime]"2026-10-05T12:00:00", [System.DateTimeKind]::Utc)
function At { param([double]$Seconds) return $t0.AddSeconds($Seconds) }
function T { param([double]$Seconds) return (Get-HordeLinkTime -At (At $Seconds)) }

function Known { param($Value, [string]$At) return [pscustomobject][ordered]@{ state = "known"; value = $Value; reason = ""; observedAt = $At } }
function Unknown { param([string]$Why) return [pscustomobject][ordered]@{ state = "unknown"; reason = $Why } }
function Summary {
    # One session-summary as a node sends it (link-verbs v1), every field known at -At unless named.
    param([string]$Id, [string]$Agent = "harness-a", [string]$At = (T 0), [string]$Role = "warg", [int]$Pad = 0)
    $agentAnswer = Known $Agent $At
    if ($Agent -eq "") { $agentAnswer = Unknown "the node could not say which harness" }
    $ns = [pscustomobject][ordered]@{ device = $devA; space = "windows" }
    $pidAnswer = Known 4242 $At
    $pidAnswer | Add-Member -NotePropertyName ns -NotePropertyValue $ns
    return [pscustomobject][ordered]@{
        sessionId = $Id; agent = $agentAnswer; fleetSessionId = (Unknown ("no fleet record" + ("x" * $Pad))); role = (Known $Role $At); label = (Known "A12" $At)
        parent = (Unknown ("no parent" + ("x" * $Pad))); liveStatus = (Known "busy" $At); workState = (Known "running" $At); startedAt = (Known (T -3600) $At)
        lastActivity = (Known $At $At); retired = (Known $false $At); pid = $pidAnswer; procStart = (Unknown ("not read" + ("x" * $Pad))); projectCwd = (Unknown ("not read" + ("x" * $Pad)))
    }
}
function Sid { param([int]$Block, [int]$N) return ("aaaaaaaa-0000-4000-8000-" + ("{0:d6}{1:d6}" -f $Block, $N)) }
function List {
    # A sessions.list value: complete known true or false, at -At.
    param([object[]]$Sessions, [bool]$Complete = $true, [string]$At = (T 0))
    $c = Known $Complete $At
    if (-not $Complete) { $c.reason = "not complete: not every store was readable: W2 (locked)" }
    return [pscustomobject][ordered]@{ complete = $c; sessions = @($Sessions); observedAt = $At }
}
function Pull {
    # A pull received at -At seconds, the node sending it at the same instant by its own clock plus -Skew.
    param($Mirror, $List, [double]$At, [double]$Skew = 0, $Clock = $null)
    return (Update-HordeNodeMirror -Mirror $Mirror -List $List -NodeSentAt (At ($At + $Skew)) -ReceivedAt (At $At) -Clock $Clock)
}
function Row { param([object[]]$Rows, [string]$Id) return @($Rows | Where-Object { $_.sessionId -ceq $Id }) }

Write-Host ""
Write-Host "--- link times ---" -ForegroundColor Cyan
$p = ConvertFrom-HordeMirrorTime "2026-10-05T12:00:00Z"
Check ($p -is [datetime] -and $p.Kind -eq [System.DateTimeKind]::Utc -and $p -eq $t0) "a link time in whole seconds reads as that UTC instant"
$p = ConvertFrom-HordeMirrorTime "2026-10-05T12:00:00.250Z"
Check ($p -is [datetime] -and $p.Kind -eq [System.DateTimeKind]::Utc -and $p -eq $t0.AddMilliseconds(250)) "a link time with a fraction reads as that UTC instant"
Check ($null -eq (ConvertFrom-HordeMirrorTime "2026-10-05 12:00:00") -and $null -eq (ConvertFrom-HordeMirrorTime "") -and $null -eq (ConvertFrom-HordeMirrorTime 5)) "anything else is not a time: no space-separated text, no empty text, no number"
$threw = $false; try { $null = Set-HordeNodeMirrorLost -Mirror (New-HordeNodeMirror -DeviceId $devA -DeviceName "a") -At ([datetime]"2026-10-05T12:00:00") -Reason "x" } catch { $threw = $true }
Check $threw "a time that is not UTC is refused, never read in this machine's zone"

Write-Host ""
Write-Host "--- a node not yet heard ---" -ForegroundColor Cyan
$m = New-HordeNodeMirror -DeviceId $devA -DeviceName "box-a"
$a = Get-HordeMirrorNodeAnswer -Mirror $m -Now (At 0)
Check ($a.state -ceq "unknown" -and $a.reason -clike ("node box-a (" + $devA + ") has not been heard from yet")) ("a node never heard is unknown, naming it (" + $a.reason + ")")
Check (@(Get-HordeMirrorRows -Mirror $m -Now (At 0)).Count -eq 0) "and has no rows"

Write-Host ""
Write-Host "--- a heard node, and a node whose link dropped ---" -ForegroundColor Cyan
$m = Pull (New-HordeNodeMirror -DeviceId $devA -DeviceName "box-a") (List @((Summary $s1), (Summary $s2))) 0
$rows = @(Get-HordeMirrorRows -Mirror $m -Now (At 5))
Check ($rows.Count -eq 2 -and @($rows | Where-Object { $_.presence.state -ceq "known" -and $_.presence.value -eq $true }).Count -eq 2) "CONTROL: while the node is heard, both sessions are known present"
Check (@($rows | Where-Object { $_.device -ceq $devA -and $_.deviceName -ceq "box-a" }).Count -eq 2) "every row carries its device"
$r1 = (Row $rows $s1)[0]
Check ($r1.fields["role"].state -ceq "known" -and $r1.fields["role"].value -ceq "warg" -and $r1.fields["fleetSessionId"].state -ceq "unknown" -and $r1.fields["fleetSessionId"].reason -ceq "no fleet record") "fields carry the node's answers: a known value, and an unknown with the node's reason"
Check ($null -eq $r1.lastKnown -and "$($r1.ns.device)" -ceq $devA) "a current row has no last-known copy, and keeps the namespace its pid was read in"
$lost = Set-HordeNodeMirrorLost -Mirror $m -At (At 20) -Reason "could not open a link: no node is listening"
$lost = Set-HordeNodeMirrorLost -Mirror $lost -At (At 40) -Reason "could not open a link: still nothing"
$since = T 20
$rows = @(Get-HordeMirrorRows -Mirror $lost -Now (At 45))
$want = "node box-a (" + $devA + ") unreachable since " + $since + ":*"
Check ($rows.Count -eq 2 -and @($rows | Where-Object { $_.presence.state -ceq "unknown" -and $_.presence.reason -clike $want }).Count -eq 2) ("after the drop, both sessions are unknown, 'node D unreachable since T' (" + $rows[0].presence.reason + ")")
Check (@($rows | Where-Object { $_.presence.state -ceq "absent" }).Count -eq 0) "and neither is absent"
Check ($rows[0].presence.reason -clike "*still nothing") "T stays the first failure while the reason is the latest try"
$allUnknown = @($rows | ForEach-Object { $row = $_; @($script:HordeMirrorFields | Where-Object { $row.fields[$_].state -cne "unknown" -or $row.fields[$_].reason -cnotlike $want }) }).Count -eq 0
Check $allUnknown "every field of every session is unknown with the same reason, never the stale value as current"
Check ($null -ne $rows[0].lastKnown -and "$($rows[0].lastKnown.role.value)" -ceq "warg") "and the last-known session is kept beside it, for a reader"
$na = Get-HordeMirrorNodeAnswer -Mirror $lost -Now (At 45)
Check ($na.state -ceq "unknown" -and $na.reason -clike $want) "the node itself is unknown with the same reason"

Write-Host ""
Write-Host "--- a hub that stopped pulling ---" -ForegroundColor Cyan
$a = Get-HordeMirrorNodeAnswer -Mirror $m -Now (At 30)
Check ($a.state -ceq "known" -and $a.value -eq $true) "CONTROL: 30 s after the last pull the node is still heard"
$a = Get-HordeMirrorNodeAnswer -Mirror $m -Now (At 61)
Check ($a.state -ceq "unknown" -and $a.reason -clike "node box-a (*) not heard since its last pull*") ("61 s after it, past the link's silence window, the node is unknown (" + $a.reason + ")")
$rows = @(Get-HordeMirrorRows -Mirror $m -Now (At 61))
Check (@($rows | Where-Object { $_.presence.state -ceq "unknown" -and $_.fields["role"].state -ceq "unknown" }).Count -eq 2) "and so are its sessions and their fields"

Write-Host ""
Write-Host "--- a partial inventory never marks a session absent ---" -ForegroundColor Cyan
$m1 = Pull (New-HordeNodeMirror -DeviceId $devA -DeviceName "box-a") (List @((Summary $s1), (Summary $s2))) 0
$part = Pull $m1 (List @((Summary $s1)) -Complete $false -At (T 20)) 20
$rows = @(Get-HordeMirrorRows -Mirror $part -Now (At 25))
$r2 = @(Row $rows $s2)
Check ($r2.Count -eq 1 -and $r2[0].presence.state -ceq "unknown" -and $r2[0].presence.reason -clike ("*partial*last seen " + (T 0))) ("a session left out of a partial inventory is unknown, saying when it was last seen (" + $r2[0].presence.reason + ")")
Check ($r2.Count -eq 1 -and $r2[0].fields["role"].state -ceq "unknown" -and $null -ne $r2[0].lastKnown) "its fields are unknown and its last-known copy is kept"
Check (@(Row $rows $s1)[0].presence.state -ceq "known") "CONTROL: the session the partial inventory lists is known present"
$fleet = Get-HordeFleetView -Mirrors @($part) -Now (At 25)
$f = Find-HordeFleetSession -Fleet $fleet -SessionId $s2
Check ($f.state -ceq "known" -and $f.value.presence.state -ceq "unknown") "a lookup finds it, carried, and present-unknown"
$f = Find-HordeFleetSession -Fleet $fleet -SessionId $s3
Check ($f.state -ceq "unknown" -and $f.reason -clike "*could not rule it out*box-a*") ("a session no partial inventory lists is unknown, never absent (" + $f.reason + ")")
$full = Pull $m1 (List @((Summary $s1)) -At (T 20)) 20
$rows = @(Get-HordeMirrorRows -Mirror $full -Now (At 25))
Check (@(Row $rows $s2).Count -eq 0) "CONTROL: a COMPLETE inventory without it drops it"
$f = Find-HordeFleetSession -Fleet (Get-HordeFleetView -Mirrors @($full) -Now (At 25)) -SessionId $s2
Check ($f.state -ceq "absent") "CONTROL: and only then is a lookup of it absent"
$again = Pull $part (List @((Summary $s1)) -Complete $false -At (T 40)) 40
$c = @(Row @(Get-HordeMirrorRows -Mirror $again -Now (At 45)) $s2)
Check ($c.Count -eq 1 -and $c[0].lastSeenAt -ceq (T 0)) "a second partial inventory keeps carrying it, and its last-seen time does not move"
$done = Pull $again (List @((Summary $s1)) -At (T 60)) 60
Check (@(Row @(Get-HordeMirrorRows -Mirror $done -Now (At 65)) $s2).Count -eq 0) "a later complete inventory drops it"
$lostPart = Set-HordeNodeMirrorLost -Mirror $part -At (At 30) -Reason "the link dropped"
$c = @(Row @(Get-HordeMirrorRows -Mirror $lostPart -Now (At 35)) $s2)
Check ($c.Count -eq 1 -and $c[0].presence.reason -clike "node box-a (*) unreachable since*last seen*") "a carried session of a node that drops is unknown for the node's reason, and still says when it was last seen"

Write-Host ""
Write-Host "--- a dropped link resumes with nothing lost and nothing twice ---" -ForegroundColor Cyan
$m = Pull (New-HordeNodeMirror -DeviceId $devA -DeviceName "box-a") (List @((Summary $s1), (Summary $s2))) 0
$m = Set-HordeNodeMirrorLost -Mirror $m -At (At 20) -Reason "the link dropped"
$m = Pull $m (List @((Summary $s1), (Summary $s2), (Summary $s3)) -At (T 40)) 40
$rows = @(Get-HordeMirrorRows -Mirror $m -Now (At 45))
$ids = @($rows | ForEach-Object { $_.sessionId })
Check ($ids.Count -eq 3 -and @($ids | Sort-Object -Unique).Count -eq 3 -and $ids -ccontains $s3) ("after the drop, the next pull holds the node's three sessions, each once (" + ($ids -join ", ") + ")")
Check ($null -eq (Get-HordeLinkProp $m "lost") -and @($rows | Where-Object { $_.presence.state -ceq "known" }).Count -eq 3) "the loss is cleared and every session is current again"
$m = Pull (New-HordeNodeMirror -DeviceId $devA -DeviceName "box-a") (List @((Summary $s1), (Summary $s2))) 0
$m = Pull $m (List @((Summary $s1)) -Complete $false -At (T 20)) 20
$m = Set-HordeNodeMirrorLost -Mirror $m -At (At 30) -Reason "the link dropped"
$m = Pull $m (List @((Summary $s1), (Summary $s2)) -Complete $false -At (T 40)) 40
$twice = @(Row @(Get-HordeMirrorRows -Mirror $m -Now (At 45)) $s2)
Check ($twice.Count -eq 1 -and $twice[0].presence.state -ceq "known") "a carried session listed again after a drop is one current row, not a current row and a carried one"

Write-Host ""
Write-Host "--- a key on two devices is a fault ---" -ForegroundColor Cyan
$ma = Pull (New-HordeNodeMirror -DeviceId $devA -DeviceName "box-a") (List @((Summary $s1))) 0
$mb = Pull (New-HordeNodeMirror -DeviceId $devB -DeviceName "box-b") (List @((Summary $s1), (Summary $s2))) 0
$fleet = Get-HordeFleetView -Mirrors @($ma, $mb) -Now (At 5)
$faults = @($fleet.faults)
Check ($faults.Count -eq 1 -and $faults[0].kind -ceq "session-on-two-devices" -and $faults[0].sessionId -ceq $s1 -and @($faults[0].devices).Count -eq 2) "the same (agent, sessionId) on two devices is one fault naming both"
$both = @(Row $fleet.sessions $s1)
Check ($both.Count -eq 2 -and @($both | Where-Object { @($_.twoDevices).Count -eq 2 }).Count -eq 2) "both rows stay, each marked with the fault"
$f = Find-HordeFleetSession -Fleet $fleet -SessionId $s1
Check ($f.state -ceq "unknown" -and $f.reason -clike ("*" + $devA + "*" + $devB + "*not resolved by picking one*")) ("a lookup of the key is unknown, naming both devices (" + $f.reason + ")")
$f = Find-HordeFleetSession -Fleet $fleet -SessionId $s2
Check ($f.state -ceq "known" -and $f.value.device -ceq $devB) "CONTROL: a key on one device is found, on that device"
$mb2 = Pull (New-HordeNodeMirror -DeviceId $devB -DeviceName "box-b") (List @((Summary $s1 -Agent "harness-b"))) 0
$fleet = Get-HordeFleetView -Mirrors @($ma, $mb2) -Now (At 5)
Check (@($fleet.faults).Count -eq 0) "CONTROL: one id under two harnesses is two sessions, not a fault"
$f = Find-HordeFleetSession -Fleet $fleet -SessionId $s1 -Agent "harness-b"
Check ($f.state -ceq "known" -and $f.value.device -ceq $devB) "and a lookup naming the agent finds the one"
$mb3 = Pull (New-HordeNodeMirror -DeviceId $devB -DeviceName "box-b") (List @((Summary $s1 -Agent ""))) 0
$fleet = Get-HordeFleetView -Mirrors @($ma, $mb3) -Now (At 5)
Check (@($fleet.faults).Count -eq 1) "an id on two devices where one cannot name its agent is a fault: an unknown agent cannot prove them apart"
$lostB = Set-HordeNodeMirrorLost -Mirror $mb -At (At 20) -Reason "the link dropped"
$fleet = Get-HordeFleetView -Mirrors @($ma, $lostB) -Now (At 25)
Check (@($fleet.faults).Count -eq 1) "the fault stands while one of the two devices cannot be heard: its last-known listing is not ruled out"
$fleet = Get-HordeFleetView -Mirrors @($ma) -Now (At 5)
Check (@($fleet.faults).Count -eq 0 -and (Find-HordeFleetSession -Fleet $fleet -SessionId $s1).state -ceq "known") "CONTROL: one device alone has no fault"

Write-Host ""
Write-Host "--- the node's clock ---" -ForegroundColor Cyan
# The node's clock 10 minutes fast: it stamps a field it read 11 minutes before it sent it. On the hub's
# clock the field is 11 minutes old, not 1 (remote/Clock.ps1, R6).
$fast = 600
$old = Summary $s1 -At (T ($fast - 660))
$m = Update-HordeNodeMirror -Mirror (New-HordeNodeMirror -DeviceId $devA -DeviceName "box-a") -List (List @($old) -At (T $fast)) -NodeSentAt (At $fast) -ReceivedAt (At 0)
$r = (Row @(Get-HordeMirrorRows -Mirror $m -Now (At 1)) $s1)[0]
$age = ((At 1) - [datetime]$r.fields["role"].observedAt).TotalSeconds
Check ($r.fields["role"].state -ceq "known" -and [math]::Abs($age - 661) -lt 1) ("a field the node held 11 minutes is 11 minutes old on the hub's clock, whatever the node's clock says (" + [int]$age + " s)")
$naive = ((At 1) - (ConvertFrom-HordeMirrorTime $old.role.observedAt)).TotalSeconds
Check ([math]::Abs($naive - 61) -lt 1) ("CONTROL: read by the node's own stamp it would look 1 minute old (" + [int]$naive + " s)")
$sample = New-HordeKnown -Value ([pscustomobject]@{ offsetSeconds = 600.0; roundTripSeconds = 0.2 })
$m = Pull (New-HordeNodeMirror -DeviceId $devA -DeviceName "box-a") (List @((Summary $s1))) 0 -Clock $sample
$n = @((Get-HordeFleetView -Mirrors @($m) -Now (At 5)).nodes)[0]
Check ($n.clockFault.state -ceq "known" -and $n.clockFault.value -eq $true -and [double]$m.clock.offsetSeconds -eq 600) "a node 600 s off is a clock fault in the fleet view, and the sample is kept"
$m = Pull (New-HordeNodeMirror -DeviceId $devA -DeviceName "box-a") (List @((Summary $s1))) 0 -Clock (New-HordeKnown -Value ([pscustomobject]@{ offsetSeconds = 0.1; roundTripSeconds = 0.2 }))
$n = @((Get-HordeFleetView -Mirrors @($m) -Now (At 5)).nodes)[0]
Check ($n.clockFault.state -ceq "known" -and $n.clockFault.value -eq $false) "CONTROL: a node 0.1 s off is not"
$n = @((Get-HordeFleetView -Mirrors @((Pull (New-HordeNodeMirror -DeviceId $devA -DeviceName "box-a") (List @((Summary $s1))) 0)) -Now (At 5)).nodes)[0]
Check ($n.clockFault.state -ceq "unknown") "a node with no sample has an unknown clock fault, never false"

Write-Host ""
Write-Host "--- the fleet view's nodes ---" -ForegroundColor Cyan
$m = Pull (New-HordeNodeMirror -DeviceId $devA -DeviceName "box-a") (List @((Summary $s1), (Summary $s2)) -Complete $false) 0
$n = @((Get-HordeFleetView -Mirrors @($m) -Now (At 5)).nodes)[0]
Check ($n.heard.state -ceq "known" -and $n.listed -eq 2 -and $n.complete.state -ceq "known" -and $n.complete.value -eq $false -and $n.complete.reason -clike "*W2 (locked)*") "a node's entry says it is heard, how many sessions it listed, and that its inventory is partial, with the node's reason"
$f = Find-HordeFleetSession -Fleet (Get-HordeFleetView -Mirrors @() -Now (At 5)) -SessionId $s1
Check ($f.state -ceq "unknown") "with no node mirrored, no session can be ruled out"

Write-Host ""
Write-Host "--- carried sessions fit one frame (review of PR #86, F1) ---" -ForegroundColor Cyan
# The reviewer's shape: a complete list A of 90 large sessions, then a partial list B of 90 others (A is
# carried), then a partial list C of one (A and B carried). Each list fits a frame; A and B together do not.
$a90 = @(1..90 | ForEach-Object { Summary (Sid 1000 $_) -Pad 2300 })
$b90 = @(1..90 | ForEach-Object { Summary (Sid 2000 $_) -Pad 2300 })
$m = Pull (New-HordeNodeMirror -DeviceId $devA -DeviceName "box-a") (List $a90) 0
$m = Pull $m (List $b90 -Complete $false -At (T 20)) 20
Check (@($m.inventory.carried).Count -eq 90) "CONTROL: one list of large sessions carried whole fits, and is kept whole"
$m = Pull $m (List @((Summary $s1)) -Complete $false -At (T 40)) 40
$carried = @($m.inventory.carried)
$bytes = 0
foreach ($c in $carried) { $bytes += (ConvertTo-HordeWireText $c.session).Length + 1 }
$aIds = @(1..90 | ForEach-Object { Sid 1000 $_ })
$bIds = @(1..90 | ForEach-Object { Sid 2000 $_ })
$keptB = @($carried | Where-Object { $bIds -ccontains $_.session.sessionId }).Count
$keptA = @($carried | Where-Object { $aIds -ccontains $_.session.sessionId }).Count
Check ($carried.Count -lt 180 -and $bytes -le (1048576 - 8192)) ("180 large carried sessions are cut to what fits one frame: " + $carried.Count + " kept, " + $bytes + " bytes")
Check ($keptB -eq 90 -and $keptA -lt 90) ("the oldest are shed first: all 90 of the newer list kept, " + $keptA + " of the older")
$rows = @(Get-HordeMirrorRows -Mirror $m -Now (At 45))
Check (@($rows | Where-Object { $_.presence.state -ceq "absent" }).Count -eq 0) "and a shed session is never absent"

Write-Host ""
Write-Host "--- the cost at the list cap (review of PR #86, F2) ---" -ForegroundColor Cyan
# Measured before the fix on the reviewer's box: 11.4 s then 30.0 s for one partial update at 256, and
# 54.7 s for a fleet view of 768 rows. The bounds below are a few times what the indexed code takes here,
# so a return to comparing every pair fails them. The suite opts itself out of Windows power throttling
# first: a busy background process is slowed about 7x after 3 s (core/Platform.ps1), which measured the
# throttle and not the code (4.7 s throttled against 0.78 s for one update, 2026-10-05).
. (Join-Path $root "core\Platform.ps1")
$opt = Set-HordeThrottlingOptOut
Check ($opt.state -ne "unknown") ("this suite's process is out of power throttling for the timings (" + $opt.state + ")")
$first = @(1..256 | ForEach-Object { Summary (Sid 3000 $_) })
$second = @(1..256 | ForEach-Object { Summary (Sid 4000 $_) })
$m = Pull (New-HordeNodeMirror -DeviceId $devA -DeviceName "box-a") (List $first) 0
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$m = Pull $m (List $second -Complete $false -At (T 20)) 20
$m = Pull $m (List $first -Complete $false -At (T 40)) 40
$sw.Stop()
$upd = $sw.Elapsed.TotalSeconds
Check (@($m.inventory.carried).Count -eq 256 -and $upd -lt 6) ("two partial updates at the 256 cap take " + [math]::Round($upd, 2) + " s, under 6 s")
$m2 = Pull (New-HordeNodeMirror -DeviceId $devB -DeviceName "box-b") (List $first) 40
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$fleet = Get-HordeFleetView -Mirrors @($m, $m2) -Now (At 45)
$sw.Stop()
$fv = $sw.Elapsed.TotalSeconds
Check (@($fleet.sessions).Count -eq 768 -and @($fleet.faults).Count -eq 256 -and $fv -lt 12) ("a fleet view of 768 rows, 256 of them faulted, takes " + [math]::Round($fv, 2) + " s, under 12 s")

Write-Host ""
Write-Host "--- absence needs a current, complete inventory (review of PR #86, F4 and F5) ---" -ForegroundColor Cyan
$fresh = Pull (New-HordeNodeMirror -DeviceId $devA -DeviceName "box-a") (List @((Summary $s1)) -At (T 0)) 0
$f = Find-HordeFleetSession -Fleet (Get-HordeFleetView -Mirrors @($fresh) -Now (At 5)) -SessionId $s3
Check ($f.state -ceq "absent") "CONTROL: a heard node's current, complete inventory rules a session out"
$old = Update-HordeNodeMirror -Mirror (New-HordeNodeMirror -DeviceId $devA -DeviceName "box-a") -List (List @((Summary $s1)) -At (T -600)) -NodeSentAt (At 0) -ReceivedAt (At 0)
$f = Find-HordeFleetSession -Fleet (Get-HordeFleetView -Mirrors @($old) -Now (At 5)) -SessionId $s3
Check ($f.state -ceq "unknown" -and $f.reason -clike "*could not rule it out*") ("a complete list observed 600 s before it was sent does not rule a session out (" + $f.reason + ")")
$ahead = Update-HordeNodeMirror -Mirror (New-HordeNodeMirror -DeviceId $devA -DeviceName "box-a") -List (List @((Summary $s1)) -At (T 3600)) -NodeSentAt (At 0) -ReceivedAt (At 0)
$f = Find-HordeFleetSession -Fleet (Get-HordeFleetView -Mirrors @($ahead) -Now (At 5)) -SessionId $s3
Check ($f.state -ceq "unknown") "nor does one dated an hour after it was sent"
$n = @((Get-HordeFleetView -Mirrors @($old) -Now (At 5)).nodes)[0]
Check ($n.fresh.state -ceq "unknown" -and $n.fresh.reason -clike "*not current*" -and $n.heard.state -ceq "known") "the node is heard, and its inventory says it is not current"
$gone = Set-HordeNodeMirrorLost -Mirror $fresh -At (At 10) -Reason "the link dropped"
$f = Find-HordeFleetSession -Fleet (Get-HordeFleetView -Mirrors @($gone) -Now (At 15)) -SessionId $s3
Check ($f.state -ceq "unknown" -and $f.reason -clike "*unreachable since*") ("a lost node's complete inventory does not rule a session out (" + $f.reason + ")")
$f = Find-HordeFleetSession -Fleet (Get-HordeFleetView -Mirrors @($fresh) -Now (At 61)) -SessionId $s3
Check ($f.state -ceq "unknown" -and $f.reason -clike "*not heard since*") ("nor does a node not heard within the silence window (" + $f.reason + ")")
$f = Find-HordeFleetSession -Fleet (Get-HordeFleetView -Mirrors @($gone) -Now (At 15)) -SessionId $s1
Check ($f.state -ceq "known" -and $f.value.presence.state -ceq "unknown") "a session a lost node listed is found, present-unknown"

Write-Host ""
Write-Host "--- one bad mirror is that node's answer (review of PR #86, F7) ---" -ForegroundColor Cyan
$p8 = ConvertFrom-HordeMirrorTime "2026-10-05T12:00:00.12345678Z"
Check ($p8 -is [datetime] -and $p8.Kind -eq [System.DateTimeKind]::Utc -and $p8.Ticks -eq $t0.AddTicks(1234567).Ticks) "a link time with eight fraction digits reads, cut to the seven .NET keeps"
$good = Pull (New-HordeNodeMirror -DeviceId $devB -DeviceName "box-b") (List @((Summary $s2))) 0
$eight = ConvertTo-HordeMirrorObject $fresh
$eight.inventory.nodeSentAt = "2026-10-05T12:00:00.12345678Z"
$view = $null; $threw = ""
try { $view = Get-HordeFleetView -Mirrors @($eight, $good) -Now (At 5) } catch { $threw = $_.Exception.Message }
Check ($threw -eq "" -and @($view.sessions | Where-Object { $_.presence.state -ceq "known" }).Count -eq 2) ("a mirror whose send time has eight fraction digits is read, not thrown on (" + $threw + ")")
$garbled = ConvertTo-HordeMirrorObject $fresh
$garbled.inventory.nodeSentAt = "not a time"
$view = Get-HordeFleetView -Mirrors @($garbled, $good) -Now (At 5)
$gRows = @($view.sessions | Where-Object { $_.device -ceq $devA })
Check ($gRows.Count -eq 1 -and $gRows[0].presence.state -ceq "unknown" -and $gRows[0].presence.reason -clike "*cannot be read*") ("a mirror whose send time cannot be read has its sessions unknown (" + $gRows[0].presence.reason + ")")
$broken = ConvertTo-HordeMirrorObject $fresh
$broken | Add-Member -NotePropertyName clock -NotePropertyValue ([pscustomobject]@{ at = (T 0); offsetSeconds = "not a number"; roundTripSeconds = 0.1 }) -Force
$view = $null; $threw = ""
try { $view = Get-HordeFleetView -Mirrors @($broken, $good) -Now (At 5) } catch { $threw = $_.Exception.Message }
$bad = @($view.nodes | Where-Object { $_.deviceId -ceq $devA })
$ok = @($view.nodes | Where-Object { $_.deviceId -ceq $devB })
Check ($threw -eq "" -and $bad.Count -eq 1 -and $bad[0].heard.state -ceq "unknown" -and $bad[0].heard.reason -clike "*its mirror could not be read*") ("a mirror that throws while it is read is that node's unknown, not the view's end (" + $threw + ")")
Check ($ok.Count -eq 1 -and $ok[0].heard.state -ceq "known" -and @($view.sessions | Where-Object { $_.device -ceq $devB }).Count -eq 1) "CONTROL: the other node is read as ever"
Check (@($view.sessions | Where-Object { $_.device -ceq $devA }).Count -eq 0) "and the bad node gives no rows"
$f = Find-HordeFleetSession -Fleet $view -SessionId $s3
Check ($f.state -ceq "unknown") "and no session can be ruled out while it cannot be read"

Complete-HordeSuite -Success "the hub's mirror says unknown for a node it cannot hear, never absent for a partial inventory, holds each inventory whole, and faults a key on two devices"
