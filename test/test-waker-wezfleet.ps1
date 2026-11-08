# DOES THE FLEET'S WAKER READ WHAT THE FLEET'S COMMAND SAYS, AND NEVER MORE THAN IT SAID?
#
# wakers/wezfleet: the first waker that reaches real sessions, by starting the fleet's own command. Every
# case here runs it against a FAKE of that command in a temp folder (the waker's own test\Fixture.ps1 and
# test\FakeWezfleet.ps1); no suite ever starts the real one, which reads and types into real terminals.
# What happened is read from the fake's own records - what it was handed, what it "typed" - never from
# what the waker answered. Held here:
#   - THE MAPPING: which rows are targets, the fleet's words for a role as Horde's, one whole-fleet call
#     a pass, and a pane read only for a candidate.
#   - THE SIX RULES of the waker's header, each by name: a row with a reason is still nudged; a count
#     that is null is unknown, never 0; a failing read backs off and says the same thing while it
#     waits; every call has a deadline; an answer that is not one line of JSON of the expected shape is
#     unknown or unreachable, never a throw; unreadableCount is carried.
#   - THE NUDGE: the fleet's four outcomes as the port's, and nothing typed but by the fleet.
#   - WHERE THE FLEET IS: the one setting the messenger reads, and the command on PATH, read not run.
# This suite names the waker only by its folder and through its fixture: its functions are its own.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "test\lib\FleetPin.ps1")
. (Join-Path $root "test\lib\MessengerPins.ps1")
# PINNED FIRST: an empty fleet, and a home in which the fleet's checkout is named as an empty folder, so
# nothing below can find the fleet's real command before a case points the waker at its fake.
$fleetPin = Enter-HordeTestEmptyFleet
$pinned = Enter-HordeTestPinnedHome -Root $root
. (Join-Path $root "core\Wake.ps1")
foreach ($f in @(Get-HordeWakerFiles)) { . $f }

$w = Get-HordeWaker -Name "wezfleet"
$fx = & (Join-Path $w.folder "test\Fixture.ps1") -Root $root
$t0 = New-Object System.DateTime(2026, 10, 12, 8, 0, 0, [System.DateTimeKind]::Utc)
function Sid { param([int]$N) return ("0a000000-0000-4000-8000-" + $N.ToString("000000000000")) }
function New-Row {
    # A row as the fleet prints one: an idle orc with one unread mail an hour old and an empty box, with
    # -Change laid over it. A member set to "(none)" is left out of the row altogether.
    param([int]$N = 1, [hashtable]$Change = @{})
    $r = [ordered]@{ id = (Sid $N); label = "A"; role = "orchestrator"; parent = ""; retired = $false; reachable = "yes"; mail = "known"; unreadCount = 1; unreadableCount = 0
        oldestUnreadAt = "2026-10-12T07:00:00.0000000Z"; idle = "yes"; boxEmpty = "yes"; midTurn = "no"; reason = ""; reasons = @(); limited = "no"; limitedUntil = $null
        # ...and what the command says since its main 5224296, in the shapes its real output has (read 2026-10-13).
        handedOverCount = 0; oldestHandedOverAt = $null; acked = "known"; lastAckedAt = $null; betweenTurns = "no" }
    foreach ($k in $Change.Keys) { if ("$($Change[$k])" -ceq "(none)") { $r.Remove($k) } else { $r[$k] = $Change[$k] } }
    return $r
}
function Get-Asked { param($State) return @(& $fx.Runs $State | ForEach-Object { @($_.argv) -join " " }) }
function Get-Count { param($State, [string]$Like) return @(Get-Asked $State | Where-Object { $_ -clike $Like }).Count }
function Get-Typed { param($State) $n = 0; foreach ($r in @(& $fx.Rows $State)) { $n += (& $fx.Observe $State $r.id).nudges }; return $n }
function Set-Answer { param($State, [string]$Form, [int]$Exit, [string]$Stdout, [string]$Stderr = "") $m = @{}; $m[$Form] = @{ exit = $Exit; stdout = $Stdout; stderr = $Stderr }; & $fx.SetMode $State $m; & $fx.Forget $State }

$state = $null
try {

Write-Host ""
Write-Host "--- the mapping: targets, roles, one whole-fleet call a pass, a pane read only for a candidate ---" -ForegroundColor Cyan

Check ((Resolve-HordeProductionWaker).state -ceq "absent" -and (@(Get-HordeWakerUnverified -Waker $w) -join ",") -ceq "nudge.pointer-only,state.box,state.turn,reach.unseen,nudge.guarded,state.limit,state.between-turns") "this waker says all seven of its capabilities are unverified - shown against the fake, never yet against the fleet's real command - so no live run can pick it"
Check ((Resolve-HordeProductionWaker -AllowUnverified).state -ceq "known" -and (Resolve-HordeProductionWaker -AllowUnverified).value.name -ceq "wezfleet") "and a run that may go through unverified capabilities - shadow, proof - picks this one, never the test waker loaded beside it"
Check (@($w.capabilities.capabilities.PSObject.Properties | Where-Object { -not "$($_.Value.evidence)".Contains("STILL TO BE RUN against the fleet's real command") }).Count -eq 0) "each one's evidence says what is still to be run"
$away = Get-HordeWakeTargets -Waker $w
Check ($away.state -ceq "unknown" -and "$($away.reason)".Contains("not a wezfleet checkout") -and "$($away.reason)".Contains("set as root in")) "CONTROL: in the pinned home, before any fake, the fleet is not found - and the answer says the folder came from the settings file"

$state = & $fx.New
& $fx.SetRow $state (New-Row 1 @{ role = "master"; label = "M" })
& $fx.SetRow $state (New-Row 2 @{ parent = (Sid 1); unreadCount = 0; oldestUnreadAt = $null })
& $fx.SetRow $state (New-Row 3 @{ role = "session"; parent = (Sid 2); reachable = "no" })
& $fx.SetRow $state (New-Row 4 @{ role = "helper"; idle = "no" })
& $fx.SetRow $state (New-Row 5 @{ retired = $true; unreadCount = 0; oldestUnreadAt = $null })
& $fx.SetRow $state (New-Row 6 @{ retired = $true; reachable = "unknown"; idle = "no" })
$a = Get-HordeWakeTargets -Waker $w
$list = @(); if ($a.state -ceq "known") { $list = @($a.value | Sort-Object id) }
Check ($a.state -ceq "known" -and (@($list | ForEach-Object { $_.id }) -join ",") -ceq (@(1, 2, 3, 4, 6 | ForEach-Object { Sid $_ }) -join ",")) "the targets are the fleet's rows that are not retired, and a retired one that still has unread mail - not a retired one with none"
Check ($list.Count -eq 5 -and $list[0].role -ceq "warchief" -and $list[1].role -ceq "orc" -and $list[2].role -ceq "warg" -and $list[3].role -ceq "unknown") "master is warchief, orchestrator is orc, session is warg, and a word it does not know is unknown"
Check ($list.Count -eq 5 -and (@($list | ForEach-Object { $_.retired }) -join ",") -ceq "no,no,no,no,yes") "each says whether it is retired: the retired one that still has mail is listed as retired, for the watcher to hold"
Check ($list.Count -eq 5 -and $list[0].label -ceq "M" -and $list[1].parent -ceq (Sid 1) -and $list[2].reachable -ceq "no" -and $list[4].reachable -ceq "unknown") "label, parent and reachable are carried as the fleet said them"
$s1 = Get-HordeWakeState -Waker $w -Id (Sid 1)
$s1full = Get-HordeWakeState -Waker $w -Id (Sid 1) -Full
$s2 = Get-HordeWakeState -Waker $w -Id (Sid 2)
$s3 = Get-HordeWakeState -Waker $w -Id (Sid 3)
$s4 = Get-HordeWakeState -Waker $w -Id (Sid 4)
Check ($s1.state -ceq "known" -and $s1.value.unreadCount -eq 1 -and $s1.value.boxEmpty -ceq "unknown" -and $s1.value.midTurn -ceq "unknown" -and $s1.value.idle -ceq "yes" -and $s1.value.oldestUnreadAt -eq $t0.AddHours(-1)) "a state is answered from the whole-fleet call and reads no pane: the box and the turn are unknown, never yes, and the oldest unread time is the fleet's, in UTC"
Check ($s1full.state -ceq "known" -and $s1full.value.boxEmpty -ceq "yes" -and $s1full.value.midTurn -ceq "no" -and $s1full.value.unreadCount -eq 1) "the full reading, asked for one session, reads its pane: the box and the turn are answered"
Check ($s2.state -ceq "known" -and $s2.value.unreadCount -eq 0 -and $s2.value.boxEmpty -ceq "unknown" -and $s2.value.midTurn -ceq "unknown") "a session with no unread mail is answered the same way"
Check ($s3.state -ceq "known" -and $s3.value.boxEmpty -ceq "unknown" -and $s4.state -ceq "known" -and $s4.value.boxEmpty -ceq "unknown" -and $s4.value.idle -ceq "no") "and so is one that cannot be reached, and one that has unread mail and can be reached but is not idle"
Check ((Get-Count $state "mail state -Json") -eq 1) ("the targets, four states and the full reading were answered from ONE whole-fleet call (" + (Get-Count $state "mail state -Json") + ")")
Check ((Get-Count $state "mail state -To *") -eq 1 -and (Get-Count $state ("mail state -To " + (Sid 1) + " -TimeoutSeconds 5 -Json")) -eq 1) "and exactly one pane was read, the one asked for in full, with the 5 s the fleet's command is given"
Check ((Get-Typed $state) -eq 0 -and (Get-Count $state "mail nudge*") -eq 0) "reading rings nobody"
$unseen = Get-HordeWakeState -Waker $w -Id (Sid 9)
Check ($unseen.state -ceq "unknown" -and "$($unseen.reason)".Contains("no session")) "a session the fleet does not list is unknown"
# THE LIFE OF ONE ANSWER: a pass's calls come within moments; the next pass, a tick later, asks again.
& $fx.Forget $state
& $fx.Clock $state $t0
$before = Get-Count $state "mail state -Json"
$null = Get-HordeWakeTargets -Waker $w
& $fx.Clock $state $t0.AddSeconds(1)
$null = Get-HordeWakeState -Waker $w -Id (Sid 2)
Check ((Get-Count $state "mail state -Json") -eq ($before + 1)) "a state asked a second after the targets is the same pass: no second call"
& $fx.Clock $state $t0.AddSeconds(3)
$null = Get-HordeWakeTargets -Waker $w
Check ((Get-Count $state "mail state -Json") -eq ($before + 2)) "three seconds on is the next pass: the fleet is asked again"
& $fx.Clock $state $null
# A PASS BEGINS: the watcher says so, and the fleet is read again whatever the clock says.
& $fx.Forget $state
$before = Get-Count $state "mail state -Json"
$null = Get-HordeWakeTargets -Waker $w
$null = Get-HordeWakeState -Waker $w -Id (Sid 2)
Start-HordeWakePass -Waker $w
$null = Get-HordeWakeTargets -Waker $w
$null = Get-HordeWakeState -Waker $w -Id (Sid 2)
Check ((Get-Count $state "mail state -Json") -eq ($before + 2)) "told a pass begins, the waker reads the fleet again at once - one call for each pass, two for two"
# A FLEET SLOWER THAN THE ANSWER'S LIFE: 3 s to answer, a life of 2 s. Stamped when the call was made,
# the answer was already expired when it arrived, and every state of the pass asked again.
& $fx.SetMode $state @{ fleet = @{ hangSeconds = 3 } }
Start-HordeWakePass -Waker $w
$before = Get-Count $state "mail state -Json"
$null = Get-HordeWakeTargets -Waker $w
foreach ($n in 2, 3, 4) { $null = Get-HordeWakeState -Waker $w -Id (Sid $n) }
Check ((Get-Count $state "mail state -Json") -eq ($before + 1)) "a fleet that takes 3 s to answer is still asked once for the whole pass: the answer's life is counted from when it arrived"
& $fx.SetMode $state $null
& $fx.Remove $state; $state = $null

Write-Host ""
Write-Host "--- the watcher decides who is looked at: a pane per nudge, not per session ---" -ForegroundColor Cyan

$state = & $fx.New
foreach ($n in 1..4) { & $fx.SetRow $state (New-Row $n) }
& $fx.SetRow $state (New-Row 5 @{ idle = "no" })
$first = Invoke-HordeWakePass -Send -Waker $w -Now ([datetime]::UtcNow) -Ledger @{}
Check ((Get-Count $state "mail state -To *") -eq 1 -and @($first.decisions | Where-Object { $_.action -ceq "nudge" }).Count -eq 1 -and (Get-Typed $state) -eq 1) ("a pass over four idle sessions with unread mail reads ONE pane, the pane of the session it nudges, and no other (" + (Get-Count $state "mail state -To *") + ")")
Check ((Get-Count $state "mail state -Json") -eq 1) "having read the whole fleet once"
$second = Invoke-HordeWakePass -Send -Waker $w -Now ([datetime]::UtcNow.AddSeconds(1)) -Ledger $first.ledger
$nudgedFirst = @($first.decisions | Where-Object { $_.action -ceq "nudge" })[0].id
Check ((Get-Count $state ("mail state -To " + $nudgedFirst + " *")) -eq 1 -and (Get-Count $state "mail state -To *") -eq 2) "on the next pass the session that is backing off has no pane read: the one pane read is the next session's"
& $fx.Remove $state; $state = $null

Write-Host ""
Write-Host "--- rule 1: a row is never skipped or distrusted because it carries a reason ---" -ForegroundColor Cyan

$state = & $fx.New
& $fx.SetRow $state (New-Row 1 @{ unreadableCount = 1; reason = "mail-unreadable"; reasons = @("mail-unreadable", "record-truncated") })
$a = Get-HordeWakeState -Waker $w -Id (Sid 1) -Full
Check ($a.state -ceq "known" -and $a.value.unreadCount -eq 1 -and $a.value.boxEmpty -ceq "yes" -and $a.value.midTurn -ceq "no") "a row with good mail and one corrupt record - mail known, unread 1, reason mail-unreadable - is a known state with unread mail"
Check ($a.state -ceq "known" -and $a.value.unreadableCount -eq 1) "RULE 6: and the count of what could not be read is carried beside it"
& $fx.Forget $state
$pass = Invoke-HordeWakePass -Send -Waker $w -Now ([datetime]::UtcNow) -Ledger @{}
Check (@($pass.decisions | Where-Object { $_.id -ceq (Sid 1) -and $_.action -ceq "nudge" }).Count -eq 1 -and (& $fx.Observe $state (Sid 1)).nudges -eq 1) "the watcher nudges it: the fleet's record shows the one line typed"
Check ($pass.unreadable[(Sid 1)] -eq 1) "and the pass hands the unreadable count on for the tick to say bad-mail"
& $fx.Remove $state; $state = $null

Write-Host ""
Write-Host "--- the fake is started as the fleet's command is: a process of its own, by -File ---" -ForegroundColor Cyan

$state = & $fx.New
& $fx.SetRow $state (New-Row 1)
& $fx.Clock $state $t0
$null = Get-HordeWakeTargets -Waker $w
$null = Get-HordeWakeState -Waker $w -Id (Sid 1) -Full
$null = Send-HordeWakeNudge -Waker $w -Id (Sid 1)
$src = Get-HordeWakerSource -Waker $w
Check ($src.state -ceq "known" -and $src.value.fixed -eq $true) "CONTROL: a folder a test pointed the waker at is named, so the cases here may run"
$started = @(& $fx.Runs $state)
$system = [System.IO.Path]::Combine([System.Environment]::SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe")
$script = Join-Path $state.dir "wezfleet.ps1"
Check ($started.Count -eq 3 -and @($started | Where-Object { "$($_.argv[0])" -ceq "mail" }).Count -eq 3) "CONTROL: a listing, a look and a nudge are three runs of the fleet's command"
Check (@($started | Where-Object { [int]$_.pid -eq $PID }).Count -eq 0 -and @($started | ForEach-Object { [int]$_.pid } | Sort-Object -Unique).Count -eq 3) "each ran in a process of its own - never in this one: the script is not called in-process"
Check (@($started | Where-Object { "$($_.program)" -ine $system }).Count -eq 0) ("the program running it is the system's own PowerShell (" + (@($started | ForEach-Object { $_.program } | Sort-Object -Unique) -join ", ") + ")")
$shape = @($started | Where-Object { $c = @($_.commandLine); $at = [System.Array]::IndexOf($c, "-File"); $at -ge 1 -and $c.Count -gt ($at + 1) -and "$($c[$at + 1])" -ieq $script -and ($c -ccontains "-NoProfile") -and ($c -ccontains "-NonInteractive") -and -not ($c -ccontains "-Command") })
Check ($shape.Count -eq 3) "and its command line is -NoProfile -NonInteractive ... -File <the checkout's wezfleet.ps1>, then the arguments: the script itself, not a shim and not a command string"
& $fx.Remove $state; $state = $null

Write-Host ""
Write-Host "--- what the fleet's command printed is cut short and cleaned before it is a reason ---" -ForegroundColor Cyan

$state = & $fx.New
& $fx.SetRow $state (New-Row 1)
$long = "the registry at C:\Users\somebody\Documents\private notes\fleet\registry\sessions\x.json is not JSON, nor is \\server\share\deep\folder\y.json, and here is a great deal more of what the command had to say about it: " + ("lorem ipsum dolor sit amet " * 20)
Set-Answer $state "fleet" 1 (([ordered]@{ at = "2026-10-12T08:00:00Z"; sessions = $null; reason = "records-unreadable"; detail = $long } | ConvertTo-Json -Compress))
& $fx.Clock $state $t0
$a = Get-HordeWakeTargets -Waker $w
Check ($a.state -ceq "unknown" -and "$($a.reason)".StartsWith("records-unreadable: ") -and "$($a.reason)".Contains("x.json is not JSON")) "CONTROL: a failing read still says the fleet's code and what was wrong, by the file's own name"
Check (-not "$($a.reason)".Contains("somebody") -and -not "$($a.reason)".Contains("C:\") -and -not "$($a.reason)".Contains("\\server") -and -not "$($a.reason)".Contains("Documents")) ("no path of the command's output is in the reason: only each file's last name (" + $a.reason + ")")
Check ("$($a.reason)".Length -le 220 -and -not "$($a.reason)".Contains("lorem ipsum dolor sit amet lorem ipsum dolor sit amet lorem")) ("and at most 120 characters of the command's own words are kept (" + "$($a.reason)".Length + " in all)")
& $fx.SetMode $state @{ fleet = @{ exit = 0; stdout = ("usage: wezfleet <command>  see C:\Users\somebody\AppData\Local\thing\help.txt " + ("x" * 500)) } }
& $fx.Forget $state
& $fx.Clock $state $t0.AddSeconds(400)
$a = Get-HordeWakeTargets -Waker $w
Check ($a.state -ceq "unknown" -and -not "$($a.reason)".Contains("somebody") -and "$($a.reason)".Contains("help.txt") -and "$($a.reason)".Length -le 260) ("output that is not JSON at all is cleaned the same way (" + "$($a.reason)".Length + " characters)")
Check ((ConvertTo-HordeWezfleetWakerLine "found from the wezfleet command on PATH, C:\tools\bin\wezfleet.cmd") -ceq "found from the wezfleet command on PATH, C:\tools\bin\wezfleet.cmd" -and (ConvertTo-HordeWezfleetWakerLine "a/b and 3/4 done, see C:\a\b\c.txt" -Tool) -ceq "a/b and 3/4 done, see c.txt") "what this waker says itself keeps its paths - a person must be told which folder - and a word with one slash in it is no path"
# A NUDGE THAT PRINTS WITHOUT END is stopped part-way: killed, never "unreachable".
& $fx.SetMode $state @{ nudge = @{ exit = 0; stdout = ("y" * 1100000) } }
$a = Send-HordeWakeNudge -Waker $w -Id (Sid 1)
Check ($a.state -ceq "known" -and $a.value.outcome -ceq "killed" -and "$($a.value.reason)".StartsWith("nudge-killed: ") -and "$($a.value.reason)".Contains("box may now hold")) ("a nudge stopped for printing more than a megabyte is killed, not unreachable: nobody knows it typed nothing (" + $a.value.outcome + ")")
& $fx.SetMode $state $null
& $fx.Remove $state; $state = $null

Write-Host ""
Write-Host "--- rows of the newer command and of the older one are both read: what an older row lacks is unknown, never an error ---" -ForegroundColor Cyan

$state = & $fx.New
$older = @{ betweenTurns = "(none)"; acked = "(none)"; lastAckedAt = "(none)"; handedOverCount = "(none)"; oldestHandedOverAt = "(none)"; limited = "(none)"; limitedUntil = "(none)" }
# THE NEWER SHAPE: each member is carried as the port's.
& $fx.SetRow $state (New-Row 1 @{ betweenTurns = "yes"; acked = "known"; lastAckedAt = "2026-10-12T07:55:00.0000000Z"; handedOverCount = 2; oldestHandedOverAt = "2026-10-12T07:58:00Z" })
& $fx.Clock $state $t0
$a = Get-HordeWakeState -Waker $w -Id (Sid 1)
Check ($a.state -ceq "known" -and $a.value.betweenTurns -ceq "yes" -and $a.value.acked -ceq "known" -and $a.value.lastAckedAt -eq (New-Object System.DateTime(2026, 10, 12, 7, 55, 0, [System.DateTimeKind]::Utc)) -and $a.value.handedOverCount -eq 2 -and $a.value.oldestHandedOverAt -eq (New-Object System.DateTime(2026, 10, 12, 7, 58, 0, [System.DateTimeKind]::Utc))) "a row of the newer command: betweenTurns, what was last acknowledged and what was handed over are each carried"
foreach ($word in @("no", "unknown")) {
    & $fx.SetRow $state (New-Row 1 @{ betweenTurns = $word })
    Check ((Get-HordeWakeState -Waker $w -Id (Sid 1)).value.betweenTurns -ceq $word) ("betweenTurns " + $word + " is carried as " + $word)
}
& $fx.SetRow $state (New-Row 1 @{ acked = "unknown"; lastAckedAt = "2026-10-12T07:55:00Z" })
$a = Get-HordeWakeState -Waker $w -Id (Sid 1)
Check ($a.state -ceq "known" -and $a.value.acked -ceq "unknown" -and $null -eq $a.value.lastAckedAt) "acked unknown: the time beside it is not read - what could not be read is not evidence"
& $fx.SetRow $state (New-Row 1 @{ acked = "known"; lastAckedAt = "2026-10-12 07:55" })
Check ($null -eq (Get-HordeWakeState -Waker $w -Id (Sid 1)).value.lastAckedAt) "a lastAckedAt that names no zone cannot be placed, and is no time"
& $fx.SetRow $state (New-Row 1 @{ handedOverCount = 0; oldestHandedOverAt = "2026-10-12T07:58:00Z" })
$a = Get-HordeWakeState -Waker $w -Id (Sid 1)
Check ($a.value.handedOverCount -eq 0 -and $null -eq $a.value.oldestHandedOverAt) "nothing handed over is a known 0, with no oldest"
# THE OLDER SHAPE: the command installed before those members. Every one reads as unknown; the row is a row.
& $fx.SetRow $state (New-Row 1 $older)
& $fx.SetRow $state (New-Row 2)
$listing = Get-HordeWakeTargets -Waker $w
Check ($listing.state -ceq "known" -and @($listing.value).Count -eq 2) "a fleet with a row of the older command beside one of the newer is listed whole: the older row does not blank the listing"
$a = Get-HordeWakeState -Waker $w -Id (Sid 1)
Check ($a.state -ceq "known" -and $a.value.unreadCount -eq 1 -and $a.value.betweenTurns -ceq "unknown" -and $a.value.acked -ceq "unknown" -and $null -eq $a.value.lastAckedAt -and $null -eq $a.value.handedOverCount -and $null -eq $a.value.oldestHandedOverAt -and $a.value.limited -ceq "unknown") "the older row's state is known, and each thing it does not say is unknown: never no, never 0, never 'never acknowledged'"
$full = Get-HordeWakeState -Waker $w -Id (Sid 1) -Full
Check ($full.state -ceq "known" -and $full.value.boxEmpty -ceq "yes" -and $full.value.betweenTurns -ceq "unknown") "and so through the per-session reading of it"
# A MEMBER THAT IS THERE AND OF THE WRONG KIND is a row this waker does not read (rule 5).
foreach ($case in @(
        @{ what = "betweenTurns that is none of the three words"; change = @{ betweenTurns = "maybe" } },
        @{ what = "acked that is neither known nor unknown"; change = @{ acked = "yes" } },
        @{ what = "lastAckedAt that is a number"; change = @{ lastAckedAt = 5 } },
        @{ what = "handedOverCount below 0"; change = @{ handedOverCount = -1 } },
        @{ what = "handedOverCount that is text"; change = @{ handedOverCount = "2" } },
        @{ what = "oldestHandedOverAt that is a number"; change = @{ handedOverCount = 1; oldestHandedOverAt = 7 } })) {
    & $fx.SetRow $state (New-Row 1 $case.change)
    Check ((Get-HordeWakeState -Waker $w -Id (Sid 1)).state -ceq "unknown") ("a row with " + $case.what + " is not read: it is not taken for one that does not say")
}
$newest = @(& $fx.Runs $state)
Check ($newest.Count -gt 0 -and @($newest | Where-Object { [int]$_.pid -eq $PID }).Count -eq 0) "every reading above went through the fake started as the fleet's command is: a process of its own"
& $fx.Remove $state; $state = $null

Write-Host ""
Write-Host "--- between turns, through the fleet's command: idle by the rule, the box read by -To, the rule in the answer ---" -ForegroundColor Cyan

$state = & $fx.New
# As the fleet form says it: idle yes BY THE RULE, betweenTurns yes, and the box unknown - that form reads no box.
& $fx.SetRow $state (New-Row 1 @{ betweenTurns = "yes" })
& $fx.Clock $state $t0
$cheap = Get-HordeWakeState -Waker $w -Id (Sid 1)
Check ($cheap.state -ceq "known" -and $cheap.value.idle -ceq "yes" -and $cheap.value.betweenTurns -ceq "yes" -and $cheap.value.boxEmpty -ceq "unknown") "the fleet form answers idle yes and betweenTurns yes with the box unknown: enough to ask about the session, never enough to type on"
$pass = Invoke-HordeWakePass -Send -Waker $w -Now $t0 -Settings (Get-HordeWakeSettings) -Ledger @{}
$line = @($pass.entries | Where-Object { $_.kind -ceq "nudge" })
Check ((Get-Count $state ("mail state -To " + (Sid 1) + " *")) -eq 1 -and (Get-Typed $state) -eq 1 -and $line.Count -eq 1) "the pass reads the session's own box with -To before it nudges, and nudges once"
Check ($line.Count -eq 1 -and "$($line[0].reason)".Contains("idle by the between-turns rule (between-turns-background-work)") -and "$($line[0].reason)".Contains("the waker says the rule that let it type was between-turns-background-work")) ("the nudge's journal line says the between-turns rule let it through, and carries the rule the fleet's answer names (" + $(if ($line.Count -eq 1) { $line[0].reason } else { "" }) + ")")
& $fx.SetRow $state (New-Row 2 @{ betweenTurns = "yes"; boxEmpty = "no" })
& $fx.Forget $state
$pass = Invoke-HordeWakePass -Send -Waker $w -Now $t0.AddSeconds(1) -Settings (Get-HordeWakeSettings) -Ledger $pass.ledger
Check ((& $fx.Observe $state (Sid 2)).nudges -eq 0 -and @($pass.decisions | Where-Object { $_.id -ceq (Sid 2) -and $_.reason -ceq "boxEmpty is no" }).Count -eq 1) "a session between turns whose own box holds text is not nudged: the rule never stands in for the box"
& $fx.SetRow $state (New-Row 3)
$a = Send-HordeWakeNudge -Waker $w -Id (Sid 3)
Check ($a.state -ceq "known" -and $a.value.outcome -ceq "woken" -and $null -eq $a.value.PSObject.Properties["rule"]) "a nudge of a session idle by its own word carries no rule"
& $fx.Remove $state; $state = $null

Write-Host ""
Write-Host "--- handed-over mail, through the fleet's command: not nudged for, and held by name ---" -ForegroundColor Cyan

$state = & $fx.New
& $fx.SetRow $state (New-Row 1 @{ unreadCount = 0; oldestUnreadAt = $null; handedOverCount = 2; oldestHandedOverAt = "2026-10-12T07:59:30Z" })
& $fx.Clock $state $t0
$pass = Invoke-HordeWakePass -Send -Waker $w -Now $t0 -Settings (Get-HordeWakeSettings) -Ledger @{}
Check ((Get-Count $state "mail nudge*") -eq 0 -and (Get-Count $state "mail state -To *") -eq 0 -and $pass.held.ContainsKey((Sid 1)) -and "$($pass.held[(Sid 1)])".StartsWith("handed-over mail: 2 ")) "a row with two handed over and none unread: no nudge is asked for, its pane is not read, and the pass holds it by name"
& $fx.SetRow $state (New-Row 1 @{ unreadCount = 0; oldestUnreadAt = $null; handedOverCount = "(none)"; oldestHandedOverAt = "(none)" })
& $fx.Forget $state
$pass = Invoke-HordeWakePass -Send -Waker $w -Now $t0 -Settings (Get-HordeWakeSettings) -Ledger @{}
Check ($pass.held.Count -eq 0 -and (Get-Count $state "mail nudge*") -eq 0) "a row of the older command, which does not say what was handed over, has nothing said for it"
& $fx.Remove $state; $state = $null

Write-Host ""
Write-Host "--- retired: true is yes, and false is no only for a row the fleet had a record for ---" -ForegroundColor Cyan

$state = & $fx.New
function Get-Retired { param([int]$N) $l = Get-HordeWakeTargets -Waker $w; if ($l.state -cne "known") { return ("listing " + $l.state) }; return "$(@($l.value | Where-Object { $_.id -ceq (Sid $N) })[0].retired)" }
& $fx.SetRow $state (New-Row 1 @{ retired = $true })
Check ((Get-Retired 1) -ceq "yes") "retired true is yes"
& $fx.SetRow $state (New-Row 1)
Check ((Get-Retired 1) -ceq "no") "retired false, for a row with a label and a role, is no"
& $fx.SetRow $state (New-Row 1 @{ reason = "record-unreadable"; reasons = @("record-unreadable") })
Check ((Get-Retired 1) -ceq "unknown") "retired false for a row whose record could not be read is unknown: the fleet's false there is 'could not tell'"
& $fx.SetRow $state (New-Row 1 @{ reason = "mail-unreadable"; reasons = @("mail-unreadable", "record-unreadable") })
Check ((Get-Retired 1) -ceq "unknown") "and so when record-unreadable is one reason among several"
& $fx.SetRow $state (New-Row 1 @{ label = ""; role = "" })
Check ((Get-Retired 1) -ceq "unknown") "a row with no label and no role it knows shows nothing a record gives: unknown"
& $fx.SetRow $state (New-Row 1 @{ label = ""; role = "session" })
Check ((Get-Retired 1) -ceq "no") "a row with a role and no label had a record: no"
& $fx.SetRow $state (New-Row 1 @{ reason = "mail-unreadable"; reasons = @("mail-unreadable") })
Check ((Get-Retired 1) -ceq "no") "a reason that is about the mail says nothing of the record: no"
& $fx.SetRow $state (New-Row 1 @{ retired = $true; reason = "record-unreadable"; reasons = @("record-unreadable") })
Check ((Get-Retired 1) -ceq "yes") "retired true is yes whatever else the row says"
# T-0116: duplicate-process in reason or reasons is the one word read for duplicate; anything else is no.
function Get-Dup { param([int]$N) $l = Get-HordeWakeTargets -Waker $w; if ($l.state -cne "known") { return ("listing " + $l.state) }; return "$(@($l.value | Where-Object { $_.id -ceq (Sid $N) })[0].duplicate)" }
& $fx.SetRow $state (New-Row 1)
Check ((Get-Dup 1) -ceq "no") "duplicate: a row with no such reason is no"
& $fx.SetRow $state (New-Row 1 @{ reason = "duplicate-process"; reasons = @("duplicate-process"); idle = "unknown" })
Check ((Get-Dup 1) -ceq "yes") "duplicate: reason duplicate-process is yes"
& $fx.SetRow $state (New-Row 1 @{ reason = "mail-unreadable"; reasons = @("mail-unreadable", "duplicate-process") })
Check ((Get-Dup 1) -ceq "yes") "duplicate: and so when it is one reason among several"
& $fx.SetRow $state (New-Row 1 @{ reason = "duplicate-processes-later"; reasons = @("not-duplicate-process") })
Check ((Get-Dup 1) -ceq "no") "duplicate: only the exact word counts"
& $fx.SetRow $state (New-Row 1 @{ reason = "duplicate-process"; reasons = @("duplicate-process"); idle = "unknown" })
$st = Get-HordeWakeState -Waker $w -Id (Sid 1)
Check ($st.state -ceq "known" -and $st.value.unreadCount -eq 1) "duplicate: the row is still a state like any other (rule 1): its mail is read"
# THE WATCHER, THROUGH THIS WAKER: a retired session with mail, idle and with an empty box, is not nudged.
& $fx.SetRow $state (New-Row 1 @{ retired = $true; oldestUnreadAt = "2026-10-12T07:00:00Z" })
& $fx.Clock $state $t0
$pass = Invoke-HordeWakePass -Send -Waker $w -Now $t0 -Settings (Get-HordeWakeSettings) -Ledger @{}
Check ((Get-Count $state "mail nudge*") -eq 0 -and (Get-Typed $state) -eq 0 -and @($pass.decisions | Where-Object { $_.action -ceq "skip" -and "$($_.reason)".StartsWith("retired") }).Count -eq 1 -and $pass.never.Count -eq 1) "a pass over a retired session with unread mail asks for no nudge and types nothing"
# THE FLEET'S OWN DOOR: asked all the same, its nudge refuses a retired target, and that is nothing.
$a = Send-HordeWakeNudge -Waker $w -Id (Sid 1)
Check ($a.state -ceq "known" -and $a.value.outcome -ceq "nothing" -and "$($a.value.reason)".StartsWith("retired") -and (Get-Typed $state) -eq 0) "a nudge the fleet refuses because the target is retired is the port's nothing, with the fleet's reason, and nothing was typed"
& $fx.Remove $state; $state = $null

Write-Host ""
Write-Host "--- a usage limit is read from the row when the row says it ---" -ForegroundColor Cyan

$state = & $fx.New
& $fx.SetRow $state (New-Row 1)
# A USAGE LIMIT, as the fleet's rows say it. A row of a command too old to say is a row all the same.
& $fx.SetRow $state (New-Row 1 @{ limited = "(none)"; limitedUntil = "(none)" })
$a = Get-HordeWakeState -Waker $w -Id (Sid 1)
Check ($a.state -ceq "known" -and $a.value.limited -ceq "unknown" -and $null -eq $a.value.limitedUntil) "a row with no limited member - a command too old to say - is unknown, never not limited"
foreach ($word in @("no", "unknown")) {
    & $fx.SetRow $state (New-Row 1 @{ limited = $word; limitedUntil = "2026-10-13T05:55:00Z" })
    $a = Get-HordeWakeState -Waker $w -Id (Sid 1)
    Check ($a.state -ceq "known" -and $a.value.limited -ceq $word -and $null -eq $a.value.limitedUntil) ("limited " + $word + " is carried as " + $word + ", and the time beside it is not read")
}
# THE WATCHER, THROUGH THIS WAKER: a row that cannot say, idle with an empty box and old mail, is not nudged.
& $fx.SetRow $state (New-Row 1 @{ limited = "unknown" })
& $fx.Clock $state $t0
$pass = Invoke-HordeWakePass -Send -Waker $w -Now $t0 -Settings (Get-HordeWakeSettings) -Ledger @{}
Check ((Get-Count $state "mail nudge*") -eq 0 -and @($pass.decisions | Where-Object { $_.action -ceq "wait" -and "$($_.reason)".StartsWith("usage limit unknown") }).Count -eq 1) "a pass over a session whose row says limited unknown asks for no nudge: it waits"
& $fx.Forget $state
& $fx.SetRow $state (New-Row 9 @{ unreadCount = 0; oldestUnreadAt = $null; acked = "known"; lastAckedAt = $t0.AddSeconds(-5).ToString("o", [System.Globalization.CultureInfo]::InvariantCulture) })
& $fx.Clock $state $t0
# The evidence is an acknowledgement SEEN TO RISE since the last pass (core/Wake.ps1, Update-HordeWakeAcksRose):
# the last pass read session 9 with none.
$before = [pscustomobject]@{ acks = @{ (Sid 9) = $null } }
$pass = Invoke-HordeWakePass -Send -Waker $w -Now $t0 -Settings (Get-HordeWakeSettings) -Ledger @{} -AcksSeen $before
Check ((Get-Count $state "mail nudge*") -eq 1 -and (Get-Typed $state) -eq 1 -and $pass.acks[(Sid 9)] -eq $t0.AddSeconds(-5)) "with ANOTHER session's row saying it acknowledged mail five seconds ago, and none on the pass before, the same session is nudged: the evidence is read from the fleet's own rows"
$heard = Update-HordeWakeAcksRose -Seen $before -Acks $pass.acks -Now $t0
& $fx.SetRow $state (New-Row 9 @{ unreadCount = 0; oldestUnreadAt = $null; acked = "(none)"; lastAckedAt = "(none)" })
& $fx.SetRow $state (New-Row 1 @{ limited = "unknown" })
& $fx.Clock $state $t0
$pass = Invoke-HordeWakePass -Send -Waker $w -Now $t0 -Settings (Get-HordeWakeSettings) -Ledger @{} -AcksSeen $heard
Check ((Get-Count $state "mail nudge*") -eq 1 -and $pass.acks.Count -eq 1) "a row of the older command, which says nothing of what was acknowledged, is no evidence: no second nudge"
& $fx.SetRow $state (New-Row 1 @{ limited = "yes"; limitedUntil = "2031-01-01T05:55:00Z" })
$a = Get-HordeWakeState -Waker $w -Id (Sid 1)
Check ($a.state -ceq "known" -and $a.value.limited -ceq "yes" -and $a.value.limitedUntil -eq (New-Object System.DateTime(2031, 1, 1, 5, 55, 0, [System.DateTimeKind]::Utc))) "limited yes with a time is limited until then"
& $fx.SetRow $state (New-Row 1 @{ limited = "yes"; limitedUntil = "2020-01-01T05:55:00Z" })
$a = Get-HordeWakeState -Waker $w -Id (Sid 1)
Check ($a.state -ceq "known" -and $a.value.limited -ceq "yes" -and $a.value.limitedUntil -eq (New-Object System.DateTime(2020, 1, 1, 5, 55, 0, [System.DateTimeKind]::Utc))) "a reset that has passed is carried as the fleet gave it - still yes, with the past time: whether it is over is the watcher's to say, with the pass's clock"
foreach ($until in @($null, "next Tuesday", "2026-10-13 05:55")) {
    & $fx.SetRow $state (New-Row 1 @{ limited = "yes"; limitedUntil = $until })
    $a = Get-HordeWakeState -Waker $w -Id (Sid 1)
    Check ($a.state -ceq "known" -and $a.value.limited -ceq "yes" -and $null -eq $a.value.limitedUntil) ("limited yes with a limitedUntil of '" + $until + "' - none, or one that cannot be placed - is limited, and nobody knows until when")
}
& $fx.SetRow $state (New-Row 1 @{ limited = "yes" })
$a = Get-HordeWakeState -Waker $w -Id (Sid 1)
Check ($a.state -ceq "known" -and $a.value.limited -ceq "yes" -and $null -eq $a.value.limitedUntil) "and so is limited yes with no limitedUntil member at all"
& $fx.SetRow $state (New-Row 1 @{ limited = "maybe" })
Check ((Get-HordeWakeState -Waker $w -Id (Sid 1)).state -ceq "unknown") "a limited that is none of the three words is a row this waker does not read"
& $fx.SetRow $state (New-Row 1 @{ limited = "yes"; limitedUntil = 5 })
Check ((Get-HordeWakeState -Waker $w -Id (Sid 1)).state -ceq "unknown") "and so is a limitedUntil that is neither a time nor null"
& $fx.Remove $state; $state = $null

Write-Host ""
Write-Host "--- rule 2: a count that is null is unknown, never 0 ---" -ForegroundColor Cyan

$state = & $fx.New
& $fx.SetRow $state (New-Row 1 @{ unreadCount = $null; oldestUnreadAt = $null })
& $fx.SetRow $state (New-Row 2 @{ unreadableCount = $null })
& $fx.SetRow $state (New-Row 3 @{ mail = "unknown"; unreadCount = $null; unreadableCount = $null; oldestUnreadAt = $null; reason = "mailbox-unreadable" })
& $fx.SetRow $state (New-Row 4 @{ oldestUnreadAt = $null })
& $fx.SetRow $state (New-Row 5 @{ oldestUnreadAt = "2026-10-12T07:00:00" })
$a = Get-HordeWakeState -Waker $w -Id (Sid 1)
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("unreadCount is null")) "an unreadCount of null is an unknown state, saying so - not a session with no mail"
$a = Get-HordeWakeState -Waker $w -Id (Sid 2)
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("unreadableCount is null")) "an unreadableCount of null is an unknown state too"
$a = Get-HordeWakeState -Waker $w -Id (Sid 3)
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("mail is unknown")) "mail the fleet could not read is an unknown state"
$a = Get-HordeWakeState -Waker $w -Id (Sid 4)
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("no time for the oldest")) "unread mail with no time for the oldest is unknown"
$a = Get-HordeWakeState -Waker $w -Id (Sid 5)
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("no time for the oldest")) "and so is one whose time has no zone: it cannot be placed"
& $fx.Forget $state
$pass = Invoke-HordeWakePass -Send -Waker $w -Now ([datetime]::UtcNow) -Ledger @{}
Check (@($pass.decisions | Where-Object { $_.action -ceq "nudge" }).Count -eq 0 -and (Get-Typed $state) -eq 0 -and (Get-Count $state "mail nudge*") -eq 0 -and @($pass.entries | Where-Object { $_.kind -ceq "skip-unknown" }).Count -eq 5) "the watcher nudges none of the five, asks for no nudge, and journals each as unknown"
& $fx.Remove $state; $state = $null

Write-Host ""
Write-Host "--- rule 3: a failing read backs off - 5, 15, 45 s - and says the same thing while it waits ---" -ForegroundColor Cyan

$state = & $fx.New
& $fx.SetRow $state (New-Row 1)
Set-Answer $state "fleet" 1 '{"at":"2026-10-12T08:00:00Z","sessions":null,"reason":"records-unreadable","detail":"registry\\sessions\\x.json is not JSON"}'
& $fx.Clock $state $t0
$first = Get-HordeWakeTargets -Waker $w
Check ($first.state -ceq "unknown" -and "$($first.reason)".StartsWith("records-unreadable: ") -and "$($first.reason)".Contains("exit 1") -and "$($first.reason)".Contains("x.json is not JSON")) "a non-zero exit is unknown, the fleet's reason code first, then its exit and its detail"
Check ($first.failures -eq 1) "and the answer says it is the first failure in a row"
$calls = Get-Count $state "mail state -Json"
$same = @()
foreach ($s in @(1, 3, 4.9)) { & $fx.Clock $state $t0.AddSeconds($s); $same += (Get-HordeWakeTargets -Waker $w).reason; $same += (Get-HordeWakeState -Waker $w -Id (Sid 1)).reason }
Check ((Get-Count $state "mail state -Json") -eq $calls) "for the next 5 s the fleet is not asked again, however often the watcher asks"
Check (@($same | Where-Object { $_ -cne $first.reason }).Count -eq 0 -and $same.Count -eq 6) "and every answer meanwhile is the same unknown in the same words, so the journal says it once"
& $fx.Clock $state $t0.AddSeconds(5)
$second = Get-HordeWakeTargets -Waker $w
Check ((Get-Count $state "mail state -Json") -eq ($calls + 1) -and $second.failures -eq 2) "at 5 s it is asked again, and that is the second failure in a row: the count is of its readings, not of how often it was asked"
& $fx.Clock $state $t0.AddSeconds(19.9)
$null = Get-HordeWakeTargets -Waker $w
Check ((Get-Count $state "mail state -Json") -eq ($calls + 1)) "after the second failure it waits 15 s: not asked at 19.9 s"
& $fx.Clock $state $t0.AddSeconds(20)
$null = Get-HordeWakeTargets -Waker $w
& $fx.Clock $state $t0.AddSeconds(64.9)
$null = Get-HordeWakeTargets -Waker $w
Check ((Get-Count $state "mail state -Json") -eq ($calls + 2)) "asked at 20 s, and after the third failure it waits 45 s: not asked at 64.9 s"
& $fx.SetMode $state $null
& $fx.Clock $state $t0.AddSeconds(65)
$mended = Get-HordeWakeTargets -Waker $w
Check ($mended.state -ceq "known" -and @($mended.value).Count -eq 1) "when the fleet answers again the targets are known"
Set-Answer $state "fleet" 1 '{"at":"2026-10-12T08:00:00Z","sessions":null,"reason":"registry-absent","detail":"no registry"}'
& $fx.Clock $state $t0.AddSeconds(100)
$again = Get-HordeWakeTargets -Waker $w
$calls = Get-Count $state "mail state -Json"
& $fx.Clock $state $t0.AddSeconds(105)
$null = Get-HordeWakeTargets -Waker $w
Check ("$($again.reason)".StartsWith("registry-absent: ") -and (Get-Count $state "mail state -Json") -eq ($calls + 1)) "and a failure after that starts the back-off over, at 5 s"
& $fx.Clock $state $null
# THE PANE READ BACKS OFF TOO, for its session alone.
& $fx.SetMode $state @{ pane = @{ exit = 1; stdout = '{"at":"2026-10-12T08:00:00Z","to":"x","reason":"records-unreadable","detail":"its record is not JSON"}' } }
& $fx.SetRow $state (New-Row 2)
& $fx.Clock $state $t0.AddSeconds(200)
$p1 = Get-HordeWakeState -Waker $w -Id (Sid 1) -Full
$p2 = Get-HordeWakeState -Waker $w -Id (Sid 1) -Full
Check ($p1.state -ceq "unknown" -and "$($p1.reason)".StartsWith("records-unreadable: ") -and $p2.reason -ceq $p1.reason -and (Get-Count $state ("mail state -To " + (Sid 1) + " *")) -eq 1) "a pane read that fails is unknown with the fleet's code, and that session's pane is not read again at once"
$null = Get-HordeWakeState -Waker $w -Id (Sid 2) -Full
Check ((Get-Count $state ("mail state -To " + (Sid 2) + " *")) -eq 1) "while another session's pane is still read: the back-off is the one session's"
& $fx.Clock $state $null
& $fx.Remove $state; $state = $null

Write-Host ""
Write-Host "--- rule 4: every call runs under the waker's own deadline, and the loop never waits on one ---" -ForegroundColor Cyan

$state = & $fx.New
& $fx.SetRow $state (New-Row 1)
& $fx.Deadlines $state 2 1 2
& $fx.SetMode $state @{ fleet = @{ hangSeconds = 60 } }
$clock = [System.Diagnostics.Stopwatch]::StartNew()
$a = Get-HordeWakeTargets -Waker $w
Check ($a.state -ceq "unknown" -and "$($a.reason)".StartsWith("timed-out: ") -and "$($a.reason)".Contains("within 2 s") -and $clock.Elapsed.TotalSeconds -lt 30) ("a whole-fleet call that hangs is stopped at its deadline and answered unknown, timed-out (" + [int]$clock.Elapsed.TotalSeconds + " s for a command that would have hung 60)")
Check ("$($a.reason)".Contains("was stopped") -and -not "$($a.reason)".Contains("could not be listed")) "and the answer says the process was stopped"
# THE PROCESS TABLE DOES NOT ANSWER IN TIME: the stop must not hang on it.
& $fx.NoSnapshot $state $true
& $fx.Forget $state
$clock.Restart()
$a = Get-HordeWakeTargets -Waker $w
Check ($a.state -ceq "unknown" -and "$($a.reason)".StartsWith("timed-out: ") -and "$($a.reason)".Contains("was stopped, alone") -and "$($a.reason)".Contains("could not be listed within 5 s") -and $clock.Elapsed.TotalSeconds -lt 30) "when the processes it started cannot be listed in time, the hung command is stopped alone, and the answer says the rest may still be running"
& $fx.NoSnapshot $state $false
& $fx.SetMode $state @{ pane = @{ hangSeconds = 60 } }
& $fx.Forget $state
$clock.Restart()
$a = Get-HordeWakeState -Waker $w -Id (Sid 1) -Full
Check ($a.state -ceq "unknown" -and "$($a.reason)".StartsWith("timed-out: ") -and "$($a.reason)".Contains("within 3 s") -and $clock.Elapsed.TotalSeconds -lt 30) "a pane read that hangs is stopped at three times the seconds it gave the fleet's command, and answered unknown, timed-out"
Check ((Get-Count $state ("mail state -To " + (Sid 1) + " -TimeoutSeconds 1 -Json")) -eq 1) "having given the fleet's command a third of its own deadline"
& $fx.SetMode $state @{ nudge = @{ hangSeconds = 60 } }
& $fx.Deadlines $state 2 1 10
$clock.Restart()
$a = Send-HordeWakeNudge -Waker $w -Id (Sid 1)
Check ($a.state -ceq "known" -and $a.value.outcome -ceq "killed" -and "$($a.value.reason)".StartsWith("nudge-killed: ") -and "$($a.value.reason)".Contains("past 30 s, three times its budget") -and "$($a.value.reason)".Contains("box may now hold") -and $clock.Elapsed.TotalSeconds -lt 50 -and $clock.Elapsed.TotalSeconds -ge 29) ("a nudge that hangs is stopped only at THREE TIMES its budget, and the outcome is killed, said first in its reason (" + [int]$clock.Elapsed.TotalSeconds + " s for a budget of 10)")
Check ((Get-Count $state ("mail nudge -To " + (Sid 1) + " -BudgetSeconds 10 -Json")) -eq 1) "having handed the fleet's command its budget, a third of the kill deadline"
& $fx.Remove $state; $state = $null

Write-Host ""
Write-Host "--- rule 5: an answer that is not one line of JSON of the expected shape is unknown, never a throw ---" -ForegroundColor Cyan

$state = & $fx.New
& $fx.SetRow $state (New-Row 1)
$good = (& $fx.Rows $state)[0] | ConvertTo-Json -Compress -Depth 4
foreach ($case in @(
        @{ what = "the host's own words for an argument it does not know"; exit = 1; out = ""; err = "wezfleet.ps1 : A parameter cannot be found that matches parameter name 'Json'."; like = "not one line of JSON" },
        @{ what = "usage text from a fleet too old to have the command"; exit = 0; out = "usage: wezfleet <command> [arguments]`r`n  spawn  start a session`r`n"; like = "not one line of JSON" },
        @{ what = "one line that is not JSON"; exit = 0; out = "all good"; like = "not JSON" },
        @{ what = "a JSON list where an object belongs"; exit = 0; out = "[1,2]"; like = "not JSON" },
        @{ what = "an object with no sessions"; exit = 0; out = '{"at":"2026-10-12T08:00:00Z"}'; like = "without a list of sessions" },
        @{ what = "sessions that is text"; exit = 0; out = '{"at":"x","sessions":"none"}'; like = "without a list of sessions" },
        @{ what = "a row that is not an object"; exit = 0; out = '{"at":"x","sessions":[7]}'; like = "not an object" },
        @{ what = "a row with a member missing"; exit = 0; out = ('{"at":"x","sessions":[' + ($good -replace '"midTurn":"no",', '') + ']}'); like = "no 'midTurn'" },
        @{ what = "a row whose idle is not one of the three words"; exit = 0; out = ('{"at":"x","sessions":[' + ($good -replace '"idle":"yes"', '"idle":"maybe"') + ']}'); like = "not yes, no or unknown" },
        @{ what = "a row whose retired is a word"; exit = 0; out = ('{"at":"x","sessions":[' + ($good -replace '"retired":false', '"retired":"no"') + ']}'); like = "retired" },
        @{ what = "a row whose unreadCount is text"; exit = 0; out = ('{"at":"x","sessions":[' + ($good -replace '"unreadCount":1', '"unreadCount":"1"') + ']}'); like = "unreadCount" },
        @{ what = "one session listed twice"; exit = 0; out = ('{"at":"x","sessions":[' + $good + ',' + $good + ']}'); like = "twice" },
        @{ what = "a failure that gives no reason code"; exit = 1; out = '{"at":"x","sessions":null,"reason":"It did not work.","detail":"d"}'; like = "without a reason code" })) {
    Set-Answer $state "fleet" $case.exit $case.out $(if ($case.ContainsKey("err")) { $case.err } else { "" })
    $a = $null
    try { $a = Get-HordeWakeTargets -Waker $w } catch { $a = $null }
    Check ($null -ne $a -and $a.state -ceq "unknown" -and "$($a.reason)".Contains($case.like)) ("the whole-fleet call answering " + $case.what + " is unknown, saying so")
}
foreach ($case in @(
        @{ what = "text"; exit = 0; out = "no such session"; like = "not JSON" },
        @{ what = "an object with no session"; exit = 0; out = '{"at":"x"}'; like = "without a session" },
        @{ what = "another session's row"; exit = 0; out = ('{"at":"x","session":' + ($good -replace (Sid 1), (Sid 7)) + '}'); like = "state -To answered about" },
        @{ what = "exit 3, absent"; exit = 3; out = ('{"at":"x","to":"' + (Sid 1) + '","reason":"absent","detail":"nobody answers to it"}'); like = "absent: " },
        @{ what = "exit 2, a bad timeout"; exit = 2; out = '{"at":"x","to":"","reason":"bad-timeout","detail":"not a number"}'; like = "bad-timeout: " })) {
    Set-Answer $state "pane" $case.exit $case.out
    $a = $null
    try { $a = Get-HordeWakeState -Waker $w -Id (Sid 1) -Full } catch { $a = $null }
    Check ($null -ne $a -and $a.state -ceq "unknown" -and "$($a.reason)".Contains($case.like)) ("a pane read answering " + $case.what + " is an unknown state, saying so")
}
foreach ($case in @(
        @{ what = "text"; exit = 1; out = ""; err = "wezfleet.ps1 : A parameter cannot be found that matches parameter name 'To'."; like = "not one line of JSON" },
        @{ what = "exit 1, a failure of its own"; exit = 1; out = '{"outcome":"unreachable","reason":"internal-error","target":"","pane":"","instance":"","detail":"it fell over"}'; like = "internal-error: " })) {
    Set-Answer $state "nudge" $case.exit $case.out $(if ($case.ContainsKey("err")) { $case.err } else { "" })
    $a = $null
    try { $a = Send-HordeWakeNudge -Waker $w -Id (Sid 1) } catch { $a = $null }
    Check ($null -ne $a -and $a.state -ceq "known" -and $a.value.outcome -ceq "unreachable" -and "$($a.value.reason)".Contains($case.like)) ("a nudge answering " + $case.what + " is unreachable, saying so: nothing is known to have been typed")
}
# THE OUTCOME WORDS ARE A CLOSED SET: one outside it, or none, is unknown - never woken, never "not rung".
foreach ($case in @(
        @{ what = "an outcome it does not know"; out = ('{"outcome":"typed","reason":"x","target":"' + (Sid 1) + '","pane":"1","instance":"i","detail":""}') },
        @{ what = "an outcome in another casing"; out = ('{"outcome":"Woken","reason":"woken","target":"' + (Sid 1) + '","pane":"1","instance":"i","detail":""}') },
        @{ what = "an outcome that is not text"; out = ('{"outcome":true,"reason":"x","target":"' + (Sid 1) + '","pane":"1","instance":"i","detail":""}') },
        @{ what = "no outcome at all"; out = '{"reason":"x"}' })) {
    Set-Answer $state "nudge" 0 $case.out
    $a = $null
    try { $a = Send-HordeWakeNudge -Waker $w -Id (Sid 1) } catch { $a = $null }
    Check ($null -ne $a -and $a.state -ceq "unknown" -and "$($a.reason)".Contains("without an outcome")) ("a nudge answering " + $case.what + " is UNKNOWN: an outcome outside the four is never permission, and never taken for one of them")
}
Set-Answer $state "nudge" 0 ('{"outcome":"woken","reason":"woken","target":"' + (Sid 7) + '","pane":"1","instance":"i","detail":""}')
$a = Send-HordeWakeNudge -Waker $w -Id (Sid 1)
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("answered about")) "a nudge answered about ANOTHER session is unknown: the waker cannot say what happened to the one it was asked about"
& $fx.Remove $state; $state = $null

Write-Host ""
Write-Host "--- the nudge: the fleet's four outcomes as the port's, and only the fleet types ---" -ForegroundColor Cyan

$state = & $fx.New
& $fx.SetRow $state (New-Row 1)
& $fx.SetRow $state (New-Row 2 @{ boxEmpty = "no" })
& $fx.SetRow $state (New-Row 3 @{ unreadCount = 0; oldestUnreadAt = $null })
& $fx.SetRow $state (New-Row 4 @{ reachable = "no" })
$a = Send-HordeWakeNudge -Waker $w -Id (Sid 1)
$o = & $fx.Observe $state (Sid 1)
Check ($a.state -ceq "known" -and $a.value.outcome -ceq "woken" -and $o.nudges -eq 1 -and (Get-Count $state ("mail nudge -To " + (Sid 1) + " -BudgetSeconds 60 -Json")) -eq 1) "woken is woken: the fleet typed its one line, having been asked with the session's id and a budget of 60 s, and nothing else"
Check ($null -ne $a.value.PSObject.Properties["elapsedMs"] -and $a.value.elapsedMs -ge 0) "and its answer carries how long the fleet's command says the nudge took"
& $fx.SetMode $state @{ nudge = @{ slowStartSeconds = 31 } }
$a = Send-HordeWakeNudge -Waker $w -Id (Sid 1)
Check ($a.state -ceq "known" -and $a.value.outcome -ceq "nothing" -and "$($a.value.reason)".StartsWith("budget-too-small") -and (& $fx.Observe $state (Sid 1)).nudges -eq 1) "a nudge the fleet's command refuses to START - it took 31 s to start, so under 30 s of its 60 s budget is left - is the port's nothing, with the reason, and nothing more was typed"
& $fx.SetMode $state @{ nudge = @{ slowStartSeconds = 29 } }
$a = Send-HordeWakeNudge -Waker $w -Id (Sid 1)
Check ($a.state -ceq "known" -and $a.value.outcome -ceq "woken" -and (& $fx.Observe $state (Sid 1)).nudges -eq 2) "with 29 s gone the default budget of 60 s still leaves room, and the nudge is typed: 60 is twice what the command needs to begin"
& $fx.SetMode $state $null
& $fx.Deadlines $state 10 5 34
$a = Send-HordeWakeNudge -Waker $w -Id (Sid 1)
Check ($a.state -ceq "known" -and $a.value.outcome -ceq "unreachable" -and "$($a.value.reason)".StartsWith("bad-budget: ") -and (& $fx.Observe $state (Sid 1)).nudges -eq 2) "a budget under 35 s is one the command refuses"
& $fx.Deadlines $state
& $fx.SetMode $state @{ nudge = @{ exit = 1; stdout = ""; stderr = "wezfleet.ps1 : A parameter cannot be found that matches parameter name 'BudgetSeconds'." } }
$a = Send-HordeWakeNudge -Waker $w -Id (Sid 1)
Check ($a.state -ceq "known" -and $a.value.outcome -ceq "unreachable" -and "$($a.value.reason)".StartsWith("tool-too-old: ") -and "$($a.value.reason)".Contains("BudgetSeconds")) "a fleet command too old to know -BudgetSeconds is unreachable, with a reason that says it is too old"
Check ((Get-Count $state "mail nudge*") -eq (Get-Count $state "mail nudge -To * -BudgetSeconds * -Json") -and (& $fx.Observe $state (Sid 1)).nudges -eq 2) "and it is never asked again without the budget: every nudge ever asked for carried one"
& $fx.SetMode $state $null
& $fx.Deadlines $state 10 5 301
$a = Send-HordeWakeNudge -Waker $w -Id (Sid 1)
Check ($a.state -ceq "known" -and $a.value.outcome -ceq "unreachable" -and "$($a.value.reason)".StartsWith("bad-budget: ") -and -not "$($a.value.reason)".Contains("tool-too-old") -and (& $fx.Observe $state (Sid 1)).nudges -eq 2) "a budget the command refuses - exit 2, bad-budget - is unreachable with the command's own code, and is not called an old tool"
& $fx.Deadlines $state
$a = Send-HordeWakeNudge -Waker $w -Id (Sid 2)
Check ($a.state -ceq "known" -and $a.value.outcome -ceq "busy" -and "$($a.value.reason)".StartsWith("box-not-empty") -and (& $fx.Observe $state (Sid 2)).nudges -eq 0) "busy is busy, with the fleet's reason code first: a box that is not empty, and nothing typed"
$a = Send-HordeWakeNudge -Waker $w -Id (Sid 3)
Check ($a.state -ceq "known" -and $a.value.outcome -ceq "nothing" -and "$($a.value.reason)".StartsWith("no-unread-mail") -and (& $fx.Observe $state (Sid 3)).nudges -eq 0) "refused is the port's nothing: there was no mail to nudge for by then, and that is no failure"
$a = Send-HordeWakeNudge -Waker $w -Id (Sid 4)
Check ($a.state -ceq "known" -and $a.value.outcome -ceq "unreachable" -and "$($a.value.reason)".StartsWith("no-pane")) "unreachable is unreachable, with the fleet's reason"
Set-Answer $state "nudge" 0 ('{"outcome":"busy","reason":"","target":"' + (Sid 1) + '","pane":"1","instance":"i","detail":""}')
$a = Send-HordeWakeNudge -Waker $w -Id (Sid 1)
Check ($a.state -ceq "known" -and $a.value.outcome -ceq "busy" -and "$($a.value.reason)" -ne "") "an outcome the fleet gave no reason for still says why, in the waker's words: the port asks every outcome but woken to"
& $fx.Remove $state; $state = $null

Write-Host ""
Write-Host "--- a reason word this waker has never seen is text, never an error: a new word from the fleet does not blind the watcher ---" -ForegroundColor Cyan

$state = & $fx.New
& $fx.SetRow $state (New-Row 1)
# NUDGE ANSWERS, each printed by the fake started as the fleet's command is. The first four are the
# real command's words (read 2026-10-13, its main 680754f); the fifth is one nobody has written yet.
foreach ($word in @("mid-turn", "status-unreadable", "pointer-stale", "sender-busy", "a-word-from-next-year")) {
    Set-Answer $state "nudge" 0 ('{"outcome":"busy","reason":"' + $word + '","target":"' + (Sid 1) + '","pane":"1","instance":"i","detail":"nothing typed","elapsedMs":12}')
    $a = Send-HordeWakeNudge -Waker $w -Id (Sid 1)
    Check ($a.state -ceq "known" -and $a.value.outcome -ceq "busy" -and "$($a.value.reason)" -ceq ($word + ": nothing typed")) ("busy / " + $word + " is busy, and the word is passed on as the fleet gave it (" + $(if ($a.state -ceq "known") { $a.value.reason } else { $a.reason }) + ")")
}
Set-Answer $state "nudge" 0 ('{"outcome":"refused","reason":"no-unread-mail","target":"' + (Sid 1) + '","pane":"1","instance":"i","detail":"mail was waiting when asked first, and by the moment of typing none was"}')
$a = Send-HordeWakeNudge -Waker $w -Id (Sid 1)
Check ($a.state -ceq "known" -and $a.value.outcome -ceq "nothing" -and "$($a.value.reason)".StartsWith("no-unread-mail: ")) "refused / no-unread-mail from INSIDE the fleet's lock - the mail was handed over or acknowledged between its two looks - is the port's nothing, as the first look's refusal is"
Set-Answer $state "nudge" 0 ('{"outcome":"refused","reason":"a-refusal-from-next-year","target":"' + (Sid 1) + '","pane":"1","instance":"i","detail":""}')
$a = Send-HordeWakeNudge -Waker $w -Id (Sid 1)
Check ($a.state -ceq "known" -and $a.value.outcome -ceq "nothing" -and "$($a.value.reason)" -ceq "a-refusal-from-next-year") "a refusal for a reason never seen is still nothing, with the word"
# CLEANED AND CAPPED: a reason is journaled, and may be mailed.
$long = "Shouting With Spaces " + ("x" * 300)
Set-Answer $state "nudge" 0 ('{"outcome":"busy","reason":"' + $long + '\tand a tab\u0007","target":"' + (Sid 1) + '","pane":"1","instance":"i","detail":""}')
$a = Send-HordeWakeNudge -Waker $w -Id (Sid 1)
Check ($a.state -ceq "known" -and $a.value.outcome -ceq "busy" -and "$($a.value.reason)".Length -eq 80 -and "$($a.value.reason)".StartsWith("Shouting With Spaces xxx") -and "$($a.value.reason)" -cmatch '\A[\x20-\x7E]+\z') "a reason that is no tidy word - long, spaced, with control characters - is cut to 80 printable characters and the outcome stands"
Set-Answer $state "nudge" 0 ('{"outcome":"busy","reason":7,"target":"' + (Sid 1) + '","pane":"1","instance":"i","detail":""}')
$a = Send-HordeWakeNudge -Waker $w -Id (Sid 1)
Check ($a.state -ceq "known" -and $a.value.outcome -ceq "busy" -and "$($a.value.reason)" -ceq "the fleet answered busy") "and one that is not text at all is left out: busy is still busy"
# THE JOURNAL carries the word, through a whole pass.
Set-Answer $state "nudge" 0 ('{"outcome":"busy","reason":"a-word-from-next-year","target":"' + (Sid 1) + '","pane":"1","instance":"i","detail":"nothing typed"}')
& $fx.Clock $state $t0
$pass = Invoke-HordeWakePass -Send -Waker $w -Now $t0 -Settings (Get-HordeWakeSettings) -Ledger @{}
$line = @($pass.entries | Where-Object { $_.kind -ceq "nudge" -and $_.id -ceq (Sid 1) })
Check ($line.Count -eq 1 -and $line[0].outcome -ceq "busy" -and "$($line[0].reason)" -ceq "a-word-from-next-year: nothing typed" -and $pass.ledger[(Sid 1)].lastOutcome -ceq "busy") "the pass journals that nudge as busy with the fleet's new word in the line, and the ledger counts it as any busy"
# STATE ROWS: reason and reasons with words never seen, in the fleet form and the per-session one.
& $fx.SetMode $state $null
& $fx.SetRow $state (New-Row 1 @{ reason = "a-word-from-next-year"; reasons = @("mid-turn", "status-unreadable", "a-word-from-next-year", "Another One, With Spaces") })
& $fx.SetRow $state (New-Row 2)
& $fx.Forget $state
$listing = Get-HordeWakeTargets -Waker $w
Check ($listing.state -ceq "known" -and @($listing.value).Count -eq 2) "a fleet with a row whose reason and reasons hold words this waker has never seen is listed WHOLE: the listing is not blanked for it"
$a = Get-HordeWakeState -Waker $w -Id (Sid 1)
$full = Get-HordeWakeState -Waker $w -Id (Sid 1) -Full
Check ($a.state -ceq "known" -and $a.value.unreadCount -eq 1 -and $a.value.idle -ceq "yes" -and $full.state -ceq "known" -and $full.value.boxEmpty -ceq "yes") "that row's state is known in both readings: what it says of mail, idle and the box is read, and the new word decides nothing"
& $fx.Forget $state
$pass = Invoke-HordeWakePass -Send -Waker $w -Now $t0.AddSeconds(1) -Settings (Get-HordeWakeSettings) -Ledger @{}
Check ($pass.listing.state -ceq "known" -and @($pass.decisions).Count -eq 2 -and @($pass.decisions | Where-Object { $_.id -ceq (Sid 1) -and $_.action -ceq "nudge" }).Count -eq 1 -and (& $fx.Observe $state (Sid 1)).nudges -eq 1 -and @($pass.entries | Where-Object { $_.kind -clike "skip-unknown*" }).Count -eq 0) ("a pass over that fleet decides on both sessions and nudges the one with the new word, which the fleet's record shows typed: the watcher saw all of it (" + (@($pass.decisions | ForEach-Object { $_.action + "/" + $_.reason }) -join ", ") + ")")
$runs = @(& $fx.Runs $state)
Check ($runs.Count -gt 0 -and @($runs | Where-Object { [int]$_.pid -eq $PID }).Count -eq 0) "every answer above was printed by the fake started as the fleet's command is: a process of its own"
& $fx.Remove $state; $state = $null

Write-Host ""
Write-Host "--- the fleet's own list of reserved labels: asked of its command, compared both ways, and 'could not ask' is never 'equal' ---" -ForegroundColor Cyan

. (Join-Path $root "core\ReservedLabels.ps1")
$state = & $fx.New
$a = Get-HordeWakerReservedLabels -Waker $w
$runs = @(& $fx.Runs $state)
Check ($a.state -ceq "known" -and (@($a.value.labels) -join ",") -ceq "RS,WW,SV" -and (Get-Count $state "labels reserved -Json") -eq 1 -and @($runs | Where-Object { [int]$_.pid -eq $PID }).Count -eq 0) ("the list is asked of the fleet's command - labels reserved -Json, in a process of its own - and read: RS, WW, SV (" + $(if ($a.state -ceq "known") { @($a.value.labels) -join "," } else { $a.reason }) + ")")
$same = Compare-HordeReservedLabels -Theirs $a.value.labels
Check ($same.equal -and @($same.onlyOurs).Count -eq 0 -and @($same.onlyTheirs).Count -eq 0) "and it is Horde's own list: neither has a label the other lacks"
# A DIFFERENCE IN EITHER DIRECTION IS FOUND.
foreach ($case in @(
        @{ what = "the fleet lacks one Horde reserves"; list = '["RS","WW"]'; ours = "SV"; theirs = "" },
        @{ what = "the fleet reserves one Horde does not"; list = '["RS","WW","SV","XX"]'; ours = ""; theirs = "XX" },
        @{ what = "each has one the other lacks"; list = '["RS","WW","ZZ"]'; ours = "SV"; theirs = "ZZ" },
        @{ what = "the fleet's is in another casing"; list = '["RS","WW","sv"]'; ours = "SV"; theirs = "sv" },
        @{ what = "the fleet reserves none"; list = '[]'; ours = "RS,WW,SV"; theirs = "" })) {
    Set-Answer $state "labels" 0 ('{"schema":"wezfleet.labels.reserved","version":1,"labels":' + $case.list + '}')
    $a = Get-HordeWakerReservedLabels -Waker $w
    $d = $(if ($a.state -ceq "known") { Compare-HordeReservedLabels -Theirs $a.value.labels } else { $null })
    Check ($null -ne $d -and -not $d.equal -and (@($d.onlyOurs) -join ",") -ceq $case.ours -and (@($d.onlyTheirs) -join ",") -ceq $case.theirs) ("when " + $case.what + " the two are NOT equal, and the comparison names which labels and whose")
}
Set-Answer $state "labels" 0 '{"schema":"wezfleet.labels.reserved","version":1,"labels":["SV","RS","WW","RS"]}'
Check ((Compare-HordeReservedLabels -Theirs (Get-HordeWakerReservedLabels -Waker $w).value.labels).equal) "CONTROL: the same labels in another order, one of them twice, are the same list"
# COULD NOT ASK IS SAID, AND IS NEVER EQUAL.
foreach ($case in @(
        @{ what = "a wezfleet from before the verb, which calls the command unknown and exits 1"; exit = 1; out = ""; err = "wezfleet: unknown command 'labels'" },
        @{ what = "one that exits 2 for it"; exit = 2; out = ""; err = "usage: wezfleet <command>" },
        @{ what = "one that exits non-zero having printed the very list"; exit = 3; out = '{"schema":"wezfleet.labels.reserved","version":1,"labels":["RS","WW","SV"]}'; err = "" })) {
    Set-Answer $state "labels" $case.exit $case.out $case.err
    $a = Get-HordeWakerReservedLabels -Waker $w
    Check ($a.state -ceq "absent" -and "$($a.reason)".Contains("could not ask") -and "$($a.reason)".Contains("exit " + $case.exit)) ($case.what + ": ABSENT - not asked, with the exit - and so not compared: never a list, never equal (" + $a.state + ")")
}
& $fx.SetMode $state $null
Set-HordeWezfleetWakerRoot -Path (Join-Path $state.dir "no-checkout-here")
$a = Get-HordeWakerReservedLabels -Waker $w
Check ($a.state -ceq "absent" -and "$($a.reason)".Contains("could not be run")) ("a fleet command that cannot be found is absent too: not asked (" + $a.state + ": " + $a.reason + ")")
Set-HordeWezfleetWakerRoot -Path $state.dir
# IT ANSWERED, AND THIS WAKER CANNOT READ IT: unknown. Not a list, and not "could not ask".
foreach ($case in @(
        @{ what = "another schema"; out = '{"schema":"wezfleet.labels.other","version":1,"labels":["RS","WW","SV"]}' },
        @{ what = "the schema in another casing"; out = '{"schema":"Wezfleet.Labels.Reserved","version":1,"labels":["RS","WW","SV"]}' },
        @{ what = "a later version"; out = '{"schema":"wezfleet.labels.reserved","version":2,"labels":["RS","WW","SV"]}' },
        @{ what = "no schema"; out = '{"labels":["RS","WW","SV"]}' },
        @{ what = "no list"; out = '{"schema":"wezfleet.labels.reserved","version":1}' },
        @{ what = "a label as text, not a list"; out = '{"schema":"wezfleet.labels.reserved","version":1,"labels":"RS"}' },
        @{ what = "a number in the list"; out = '{"schema":"wezfleet.labels.reserved","version":1,"labels":["RS",7]}' },
        @{ what = "the plain form, a label a line"; out = "RS`nWW`nSV" },
        @{ what = "nothing at all"; out = "" })) {
    Set-Answer $state "labels" 0 $case.out
    $a = Get-HordeWakerReservedLabels -Waker $w
    Check ($a.state -ceq "unknown") ("exit 0 with " + $case.what + " is unknown: the fleet answered, and it is not read as a list or as not asked (" + $a.state + ")")
}
& $fx.Remove $state; $state = $null

Write-Host ""
Write-Host "--- where the fleet is: the one setting the messenger reads, and the command on PATH, read not run ---" -ForegroundColor Cyan

$state = & $fx.New
& $fx.SetRow $state (New-Row 1)
# THE SETTING: the fixture's own pointer is taken away, and the home's settings file names the folder.
$oldPath = $env:PATH
$scratch = Join-Path $pinned.home ("where-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $scratch | Out-Null
try {
    $bin = Join-Path $scratch "bin"
    New-Item -ItemType Directory -Path $bin | Out-Null
    $env:PATH = $bin + ";" + $oldPath
    # A SHIM ON PATH, FIRST: whatever this machine has installed is behind it. It names an EMPTY folder,
    # so if it were ever followed where a setting should win, the answer would say so.
    New-Item -ItemType Directory -Path (Join-Path $bin "nothing-here") | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $bin "wezfleet.cmd"), "@echo off`r`npowershell -NoProfile -File ""%~dp0nothing-here\wezfleet.ps1"" %*`r`n")
    & $fx.Forget $state
    $settingsDir = Join-Path $state.home "settings"
    New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    $doc = [pscustomobject]@{ schemaVersion = 1; settings = [pscustomobject]@{ root = $state.dir } } | ConvertTo-Json -Compress -Depth 3
    [System.IO.File]::WriteAllText((Join-Path $settingsDir "messenger-wezfleet.json"), $doc, (New-Object System.Text.UTF8Encoding($false)))
    # The fixture's New pointed the waker at the folder directly; New's own Remove unsets that, so the
    # same is done here by handing the fixture an empty state to remove, and the setting is what is left.
    & $fx.Remove @{ dir = ""; home = ""; oldHome = $state.home }
    $a = Get-HordeWakeTargets -Waker $w
    Check ($a.state -ceq "known" -and @($a.value).Count -eq 1) "with no folder set in the process, the fleet is found by root in the home's messenger-wezfleet.json - the setting the messenger reads - over the command on PATH"
    $src = Get-HordeWakerSource -Waker $w
    Check ($src.state -ceq "known" -and $src.value.fixed -eq $true -and "$($src.value.how)".Contains("set as root in")) "a folder named by the root setting is a program a person named: fixed"
    Remove-Item -LiteralPath (Join-Path $settingsDir "messenger-wezfleet.json")
    & $fx.Forget $state
    $a = Get-HordeWakeTargets -Waker $w
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("nothing-here") -and "$($a.reason)".Contains("found from the wezfleet command on PATH")) "with no setting either, the folder is the one the shim on PATH names - read from the shim, which was never run"
    [System.IO.File]::WriteAllText((Join-Path $bin "wezfleet.cmd"), ("@echo off`r`npowershell -NoProfile -File ""%~dp0..\..\" + (Split-Path -Leaf $scratch) + "\checkout\wezfleet.ps1"" %*`r`n"))
    & $fx.Forget $state
    $a = Get-HordeWakeTargets -Waker $w
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("without ..")) "a shim that names a folder through .. is refused, as a configured folder with .. is"
    $src = Get-HordeWakerSource -Waker $w
    Check ($src.state -ceq "known" -and $src.value.fixed -eq $false -and "$($src.value.how)".Contains("found from the wezfleet command on PATH")) "a folder found from the command on PATH is NOT a program a person named, whatever it holds: not fixed, and how says it came from PATH"
    Remove-Item -LiteralPath (Join-Path $bin "wezfleet.cmd")
    $src = Get-HordeWakerSource -Waker $w
    Check ($src.state -ceq "unknown" -or ($src.state -ceq "known" -and $src.value.fixed -eq $false)) "with no setting and nothing of this scenario's on PATH, the source is unknown or whatever this machine has on PATH - never fixed"
    [System.IO.File]::WriteAllText((Join-Path $bin "wezfleet.cmd"), ("@echo off`r`npowershell -NoProfile -File ""%~dp0..\..\" + (Split-Path -Leaf $scratch) + "\checkout\wezfleet.ps1"" %*`r`n"))
    [System.IO.File]::WriteAllText((Join-Path $settingsDir "messenger-wezfleet.json"), "{ not json")
    & $fx.Forget $state
    $a = Get-HordeWakeTargets -Waker $w
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("settings are refused")) "a settings file that is refused is no folder at all: the command on PATH is not asked in its place"
    Check ((Get-HordeWakerSource -Waker $w).state -ceq "unknown") "and where the program comes from is unknown then"
} finally {
    $env:PATH = $oldPath
    $env:HORDE_HOME = $state.oldHome
}
foreach ($d in @($state.dir, $state.home)) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force } }
$state = $null

Write-Host ""
Write-Host "--- the exit (hibernation): box slash /exit through the one start site, read by its exit code ---" -ForegroundColor Cyan
$state = & $fx.New
$why = "hibernation 20261016-120000"
$e = Send-HordeWakeExit -Waker $w -Id (Sid 9) -Reason $why
Check (Test-HordeWakerExits $w) "this waker can end a session"
Check ($e.state -ceq "known" -and $e.value.outcome -ceq "submitted" -and $e.value.id -ceq (Sid 9)) ("exit 0 is submitted (" + $e.state + " " + $(if ($e.state -ceq "known") { $e.value.outcome } else { $e.reason }) + ")")
Check ((@(Get-Asked $state)[-1]) -ceq ("box slash " + (Sid 9) + " /exit -Expect exit -Reason " + $why)) ("the fleet's checked path is asked, with the exit command, the word its menu must say, and the reason, each one argument (" + (@(Get-Asked $state)[-1]) + ")")
Check (@((& $fx.Observe $state (Sid 9)).typed) -ccontains "/exit") "CONTROL: the fake played the command typed"
Set-Answer $state "box" 6 "box slash x (pane 1): TEXT LEFT BEHIND."
$e = Send-HordeWakeExit -Waker $w -Id (Sid 9) -Reason $why
Check ($e.state -ceq "known" -and $e.value.outcome -ceq "left-behind" -and "$($e.value.reason)".Contains("LEFT BEHIND")) "exit 6 is left-behind, with the verb's own words"
foreach ($code in @(1, 3, 4, 5, 7)) {
    Set-Answer $state "box" $code "box slash x (pane 1): NOT DONE (busy)."
    $e = Send-HordeWakeExit -Waker $w -Id (Sid 9) -Reason $why
    Check ($e.state -ceq "known" -and $e.value.outcome -ceq "refused" -and "$($e.value.reason)".Contains("exit " + $code)) ("exit " + $code + " is refused: nothing was typed")
}
Set-Answer $state "box" 9 "something new"
$e = Send-HordeWakeExit -Waker $w -Id (Sid 9) -Reason $why
Check ($e.state -ceq "unknown") "an exit code the verb does not document is unknown: whether it typed is not known"
$before = @(Get-Asked $state).Count
$e = Send-HordeWakeExit -Waker $w -Id (Sid 9) -Reason ""
Check ($e.state -ceq "unknown" -and @(Get-Asked $state).Count -eq $before) "an exit with no reason is refused by the port, and the fleet is not asked"
& $fx.ExitDeadline $state 1
& $fx.SetMode $state @{ box = @{ hangSeconds = 6; exit = 0; stdout = "late" } }
$e = Send-HordeWakeExit -Waker $w -Id (Sid 9) -Reason $why
& $fx.ExitDeadline $state
Check ($e.state -ceq "known" -and $e.value.outcome -ceq "killed") "a box slash past its deadline is stopped and answered killed: its box may hold the command"
& $fx.Remove $state
$state = $null

} finally {
    if ($null -ne $state) { & $fx.Remove $state }
    Exit-HordeTestPinnedHome -State $pinned
    Exit-HordeTestEmptyFleet -Pin $fleetPin
}

Complete-HordeSuite -Success "the fleet's waker reads what the fleet's command says and no more: it backs off a failing read, times every call, and only the fleet types"
