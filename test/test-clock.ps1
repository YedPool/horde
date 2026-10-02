# DOES THE HUB TELL TIME ACROSS A LINK WITHOUT TRUSTING THE NODE'S CLOCK, AND SAY "UNKNOWN" WHEN IT CANNOT HEAR?
#
# Remote plan step R6 (planning/execution-plan-remote.md), from the remote design's sections 7.1 and
# 7.4. remote/Clock.ps1 is pure: every input is a time or an answer the caller hands it.
#   - The four-timestamp offset and round trip of one ping (t1 hub sends, t2 node receives, t3 node
#     answers, t4 hub receives), and a node fault when the offset is past HordeClockSkewSeconds.
#   - Every remote observation keeps the node's own stamp beside the hub's receive time, and its age is
#     judged on the receive time: a node clock that runs fast must not make old data look fresh.
#   - The three liveness answers of design 7.1, each a core/tristate answer: the link, the node, and one
#     session. "I cannot hear the node" is unknown with the reason, never absent and never false.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "remote\Clock.ps1")

$t0 = [datetime]::new(2026, 10, 2, 12, 0, 0, [System.DateTimeKind]::Utc)
function At { param([double]$Seconds) return $t0.AddSeconds($Seconds) }
function IsKnown { param($A, $V) return ($A.state -ceq "known" -and $A.value -eq $V) }

Write-Host ""
Write-Host "--- loading the module ---" -ForegroundColor Cyan
$strictKept = & { Set-StrictMode -Version Latest; . (Join-Path $root "remote\Clock.ps1"); try { $null = $hordeNeverAssignedVariable; $false } catch { $true } }
Check ($strictKept -eq $true) "dot-sourcing remote/Clock leaves the caller's strict mode on"

Write-Host ""
Write-Host "--- one ping: offset and round trip from four timestamps ---" -ForegroundColor Cyan
# The node's clock is 30 s ahead; the wire takes 0.1 s each way and the node answers in 0.05 s.
$s = Get-HordeClockSample -T1 (At 0) -T2 (At 30.1) -T3 (At 30.15) -T4 (At 0.25)
Check ($s.state -ceq "known") "a well-ordered ping gives a known sample"
Check ([math]::Abs($s.value.offsetSeconds - 30.0) -lt 0.0001) ("the offset is the node's clock minus the hub's: 30 s (" + $s.value.offsetSeconds + ")")
Check ([math]::Abs($s.value.roundTripSeconds - 0.2) -lt 0.0001) ("the round trip leaves out the node's own answering time: 0.2 s (" + $s.value.roundTripSeconds + ")")
$slow = Get-HordeClockSample -T1 (At 0) -T2 (At -59.9) -T3 (At -59.85) -T4 (At 0.25)
Check ([math]::Abs($slow.value.offsetSeconds - -60.0) -lt 0.0001) "a node clock behind the hub's gives a negative offset"
$neg = Get-HordeClockSample -T1 (At 0) -T2 (At 30.1) -T3 (At 30.15) -T4 (At -1)
Check ($neg.state -ceq "unknown" -and $neg.reason -clike "*before its ping was sent*") "a pong received before its ping was sent is unknown: the hub's own clock moved"
$rev = Get-HordeClockSample -T1 (At 0) -T2 (At 30.2) -T3 (At 30.1) -T4 (At 0.25)
Check ($rev.state -ceq "unknown" -and $rev.reason -clike "*before it received*") "a node that says it answered before it received is unknown"
$local = Get-HordeClockSample -T1 ([datetime]::new(2026, 10, 2, 12, 0, 0, [System.DateTimeKind]::Local)) -T2 (At 30.1) -T3 (At 30.15) -T4 (At 0.25)
Check ($local.state -ceq "unknown" -and $local.reason -clike "*UTC*") "a time that is not UTC is unknown, never read in some zone"
$missing = Get-HordeClockSample -T1 (At 0) -T2 $null -T3 (At 30.15) -T4 (At 0.25)
Check ($missing.state -ceq "unknown") "a ping missing a timestamp is unknown"

Write-Host ""
Write-Host "--- a clock past the skew allowance, beyond the sample's own uncertainty, is a node fault ---" -ForegroundColor Cyan
# A sample is uncertain by half its round trip, so the edges are tested with a round trip of zero.
function Sample0 { param([double]$Offset) return (Get-HordeClockSample -T1 (At 0) -T2 (At $Offset) -T3 (At $Offset) -T4 (At 0)) }
Check (IsKnown (Test-HordeClockFault -Sample $s) $true) "a node 30 s off is a fault: its own ages cannot be trusted"
Check (IsKnown (Test-HordeClockFault -Sample (Sample0 2)) $false) "a node 2 s off is within the 5 s allowance"
Check (IsKnown (Test-HordeClockFault -Sample (Sample0 5)) $false) "exactly the allowance is not a fault"
Check (IsKnown (Test-HordeClockFault -Sample (Sample0 5.01)) $true) "just past the allowance is a fault"
Check (IsKnown (Test-HordeClockFault -Sample (Sample0 -5.01)) $true) "a node behind by more than the allowance is a fault too"
# 11 s out and 0.2 s back against a node that is not off: the sample reads 5.4 s with a 11.2 s round trip.
$lopsided = Get-HordeClockSample -T1 (At 0) -T2 (At 11) -T3 (At 11) -T4 (At 11.2)
Check ([math]::Abs($lopsided.value.offsetSeconds - 5.4) -lt 0.0001) "CONTROL: a lopsided ping reads 5.4 s off against a node that is not off"
$lf = Test-HordeClockFault -Sample $lopsided
Check ($lf.state -ceq "unknown" -and $lf.reason -clike "*too uncertain*") "a reading inside its own uncertainty is unknown, never a fault"
Check ((Test-HordeClockFault -Sample $neg).state -ceq "unknown") "with no sample, whether the clock is at fault is unknown"
Check ((Test-HordeClockFault -Sample "30").state -ceq "unknown") "a sample that is not an answer is unknown, not an error"
Check ((Test-HordeClockFault -Sample (New-HordeKnown -Value ([pscustomobject]@{ other = 1 }))).state -ceq "unknown") "a sample without an offset is unknown, not an error"

Write-Host ""
Write-Host "--- an observation keeps the node's stamps and is aged on the hub's clock ---" -ForegroundColor Cyan
# A node whose clock runs 10 minutes fast stamps everything 10 minutes late. It observed a fact and
# sent it at once; the hub received it 11 minutes ago. By the node's stamp it is 1 minute old.
$now = At 3600
$received = $now.AddMinutes(-11)
$nodeStamp = $received.AddMinutes(10)
$answer = New-HordeKnown -Value "busy" -ObservedAt $nodeStamp
$obs = New-HordeRemoteObservation -Answer $answer -NodeSentAt $nodeStamp -ReceivedAt $received
Check ($obs.nodeObservedAt -eq $nodeStamp -and $obs.nodeSentAt -eq $nodeStamp -and $obs.receivedAt -eq $received) "the node's stamps and the hub's receive time are all kept"
Check ($obs.answer.observedAt -eq $received -and "$($obs.answer.value)" -ceq "busy") "a fact sent as soon as it was observed is observed, on the hub's clock, when the hub received it"
$aged = Limit-HordeRemoteAge -Observation $obs -TtlSeconds 300 -Now $now
Check ($aged.state -ceq "unknown" -and $aged.reason -clike "*stale*") "a node clock 10 min fast does not make 11-minute-old data fresh"
$naive = Limit-HordeAge -Answer $answer -TtlSeconds 300 -Now $now
Check ($naive.state -ceq "known") "CONTROL: aged by the node's own stamp, the same data would pass as fresh"
# A node with a right clock sends a fact it observed a day before sending it.
$old = New-HordeRemoteObservation -Answer (New-HordeKnown -Value "busy" -ObservedAt $now.AddDays(-1)) -NodeSentAt $now.AddSeconds(-1) -ReceivedAt $now.AddSeconds(-1)
Check ($old.answer.observedAt -lt $now.AddHours(-23)) "a fact the node held for a day before sending is a day old on the hub's clock"
Check ((Limit-HordeRemoteAge -Observation $old -TtlSeconds 60 -Now $now).state -ceq "unknown") "so it is stale one second after it arrives, never fresh because it just arrived"
$oldAbsent = New-HordeRemoteObservation -Answer (New-HordeAbsent -Note "no such worktree" -ObservedAt $now.AddDays(-1)) -NodeSentAt $now.AddSeconds(-1) -ReceivedAt $now.AddSeconds(-1)
Check ($oldAbsent.answer.state -ceq "absent" -and (Limit-HordeRemoteAge -Observation $oldAbsent -TtlSeconds 60 -Now $now).state -ceq "unknown") "an absent answer ages the same way: a day-old absent is stale"
$fastAbsent = New-HordeRemoteObservation -Answer (New-HordeAbsent -Note "no such worktree" -ObservedAt $nodeStamp) -NodeSentAt $nodeStamp -ReceivedAt $received
Check ((Limit-HordeRemoteAge -Observation $fastAbsent -TtlSeconds 300 -Now $now).state -ceq "unknown") "a node clock 10 min fast does not make an 11-minute-old absent fresh either"
$fresh = Limit-HordeRemoteAge -Observation (New-HordeRemoteObservation -Answer (New-HordeKnown -Value "idle" -ObservedAt $now.AddSeconds(-25)) -NodeSentAt $now.AddSeconds(-20) -ReceivedAt $now.AddSeconds(-20)) -TtlSeconds 300 -Now $now
Check (IsKnown $fresh "idle") "data received within its window stays known"
$noStamp = New-HordeRemoteObservation -Answer (New-HordeKnown -Value "busy") -NodeSentAt $received -ReceivedAt $received
Check ($noStamp.answer.state -ceq "unknown" -and $noStamp.answer.reason -clike "*no UTC observation time*") "a known answer with no observation time cannot be aged, so it is unknown"
$after = New-HordeRemoteObservation -Answer (New-HordeKnown -Value "busy" -ObservedAt $received.AddMinutes(5)) -NodeSentAt $received -ReceivedAt $received
Check ($after.answer.state -ceq "unknown" -and $after.answer.reason -clike "*after it sent it*") "a fact the node says it observed after sending it is unknown"
$unk = New-HordeRemoteObservation -Answer (New-HordeUnknown -Reason "the node could not read its store") -NodeSentAt $received -ReceivedAt $received
Check ($unk.answer.state -ceq "unknown" -and $unk.answer.reason -clike "*could not read its store*") "a node's unknown arrives unknown, with the node's reason"
Check (Throws { New-HordeRemoteObservation -Answer $answer -NodeSentAt $nodeStamp -ReceivedAt ([datetime]::new(2026, 10, 2, 12, 0, 0, [System.DateTimeKind]::Local)) } "UTC") "a receive time that is not UTC is refused"
Check (Throws { New-HordeRemoteObservation -Answer $answer -NodeSentAt "2026-10-02T12:00:00Z" -ReceivedAt $received } "UTC") "a send time that is not a UTC [datetime] is refused"
Check (Throws { New-HordeRemoteObservation -Answer "busy" -NodeSentAt $nodeStamp -ReceivedAt $received } "Horde answer") "a value that is not a Horde answer is refused at the door"
Check (Throws { New-HordeRemoteObservation -Answer ([pscustomobject]@{ state = "KNOWN"; value = 1; reason = ""; observedAt = $null }) -NodeSentAt $nodeStamp -ReceivedAt $received } "Horde answer") "a state not spelled exactly is not an answer"
Check (Throws { Limit-HordeRemoteAge -Observation $obs -TtlSeconds 300 -Now ([datetime]::new(2026, 10, 2, 13, 0, 0, [System.DateTimeKind]::Unspecified)) } "UTC") "a now that is not UTC is refused, never read in this machine's zone"

Write-Host ""
Write-Host "--- is the link up? ---" -ForegroundColor Cyan
$l = Get-HordeLinkLiveness -LastFrameAt (At 10) -Now (At 60)
Check (IsKnown $l $true) "a frame 50 s ago: the link is up"
$l = Get-HordeLinkLiveness -LastFrameAt (At 0) -Now (At 60)
Check (IsKnown $l $true) "a frame exactly 60 s ago: still up"
$l = Get-HordeLinkLiveness -LastFrameAt (At 0) -Now (At 61)
Check ($l.state -ceq "unknown" -and $l.reason -clike ("*" + (At 0).ToString("o") + "*")) "silent past 60 s: unknown, naming the last frame's time"
Check ($l.state -cne "absent" -and -not ($l.state -ceq "known" -and $l.value -eq $false)) "a silent link is never absent and never known down"
$l = Get-HordeLinkLiveness -LastFrameAt $null -Now (At 61)
Check ($l.state -ceq "unknown" -and $l.reason -clike "*no frame*") "a link that never carried a frame is unknown"
$l = Get-HordeLinkLiveness -LastFrameAt ([datetime]::new(2026, 10, 2, 12, 0, 0, [System.DateTimeKind]::Local)) -Now (At 61)
Check ($l.state -ceq "unknown" -and $l.reason -clike "*not a UTC time*" -and $l.reason -cnotlike "*no frame has arrived*") "a last frame time that is not UTC is unknown, and the reason says so rather than that no frame came"
$l = Get-HordeLinkLiveness -LastFrameAt (At 3600) -Now (At 60)
Check ($l.state -ceq "unknown" -and $l.reason -clike "*in the future*") "a last frame an hour in the future is unknown, never a live link"
Check (Throws { Get-HordeLinkLiveness -LastFrameAt (At 0) -Now ([datetime]::new(2026, 10, 2, 12, 0, 30, [System.DateTimeKind]::Unspecified)) } "UTC") "a now that is not UTC is refused"

Write-Host ""
Write-Host "--- is the node running? ---" -ForegroundColor Cyan
$up = New-HordeKnown -Value $true
$silent = Get-HordeLinkLiveness -LastFrameAt (At 0) -Now (At 200)
Check (IsKnown (Get-HordeNodeLiveness -Link $up) $true) "with the link up, the node is running"
$n = Get-HordeNodeLiveness -Link $silent -LastFrameAt (At 0) -LinkLostAt (At 60)
Check ($n.state -ceq "unknown" -and $n.reason -clike ("*link lost at " + (At 60).ToString("o") + "*") -and $n.reason -clike ("*last frame " + (At 0).ToString("o") + "*")) "link down without bye: unknown, naming when the link was lost and the last frame"
Check (-not ($n.state -ceq "known" -and $n.value -eq $false)) "a node that went silent without bye is never known stopped"
$n = Get-HordeNodeLiveness -Link $silent -Bye ([pscustomobject]@{ reason = "shutdown"; at = (At 30) })
Check (IsKnown $n $false) "bye with reason shutdown: the node is known stopped"
$n = Get-HordeNodeLiveness -Link $silent -Bye ([pscustomobject]@{ reason = "restart"; at = (At 30) })
Check ($n.state -ceq "unknown" -and $n.reason -clike "*restart*") "bye for any other reason (a restart) is unknown, naming it: the node means to come back"
$n = Get-HordeNodeLiveness -Link $up -Bye ([pscustomobject]@{ reason = "shutdown"; at = (At 30) })
Check (IsKnown $n $true) "a frame after an old bye: the link being up wins, the node came back"
$n = Get-HordeNodeLiveness -Link $silent -Deregistered
Check ($n.state -ceq "absent") "a node the founder deregistered is absent"
$n = Get-HordeNodeLiveness -Link $silent
Check ($n.state -ceq "unknown") "link down with no bye and no times recorded: still unknown, never false"
$n = Get-HordeNodeLiveness -Link $silent -Bye ([pscustomobject]@{ at = (At 30) })
Check ($n.state -ceq "unknown") "a bye that gives no reason is unknown, not an error and never a stop"
$n = Get-HordeNodeLiveness -Link $silent -Bye ([pscustomobject]@{ reason = "restart" })
Check ($n.state -ceq "unknown" -and $n.reason -clike "*restart*") "a bye with no time is still read"
$n = Get-HordeNodeLiveness -Link $silent -Bye ([pscustomobject]@{ reason = "restart"; at = "2026-10-02T12:00:30Z" })
Check ($n.reason -clike "*at 2026-10-02T12:00:30Z*") "a bye time read from text is named in the reason"
$n = Get-HordeNodeLiveness -Link $silent -Bye ([pscustomobject]@{ reason = "restart"; at = (At 30) })
Check ($n.reason -clike ("*at " + (At 30).ToString("o") + "*")) "a bye's time is named in the reason"
$n = Get-HordeNodeLiveness -Link $null
Check ($n.state -ceq "unknown") "no link record at all: the node is unknown"

Write-Host ""
Write-Host "--- is session S alive? ---" -ForegroundColor Cyan
$nodeUp = New-HordeKnown -Value $true
$fresh = New-HordeRemoteObservation -Answer (New-HordeKnown -Value $true -ObservedAt (At 100)) -NodeSentAt (At 100) -ReceivedAt (At 100)
$s1 = Get-HordeSessionLiveness -Node $nodeUp -Observation $fresh -InventoryComplete $true -InInventory $true -TtlSeconds 60 -Now (At 120)
Check (IsKnown $s1 $true) "the node answered within the freshness window: known"
$s1 = Get-HordeSessionLiveness -Node $nodeUp -Observation $fresh -InventoryComplete $true -InInventory $true -TtlSeconds 60 -Now (At 200)
Check ($s1.state -ceq "unknown" -and $s1.reason -clike "*stale*") "the node's answer past the window: unknown, never the last value shown as current"
$s1 = Get-HordeSessionLiveness -Node $nodeUp -Observation $null -InventoryComplete $true -InInventory $false -TtlSeconds 60 -Now (At 120)
Check ($s1.state -ceq "absent") "the node's complete inventory lacks the session: absent"
$s1 = Get-HordeSessionLiveness -Node $nodeUp -Observation $null -InventoryComplete $false -InInventory $false -TtlSeconds 60 -Now (At 120)
Check ($s1.state -ceq "unknown") "a partial inventory that lacks the session is unknown, never absent"
$nodeLost = Get-HordeNodeLiveness -Link $silent -LastFrameAt (At 0) -LinkLostAt (At 60)
$s1 = Get-HordeSessionLiveness -Node $nodeLost -Observation $fresh -InventoryComplete $true -InInventory $true -TtlSeconds 600 -Now (At 120)
Check ($s1.state -ceq "unknown" -and $s1.reason -clike "*link lost at*") "the node unheard: the session is unknown, and the node's reason is carried through"
$s1 = Get-HordeSessionLiveness -Node (Get-HordeNodeLiveness -Link $silent -Bye ([pscustomobject]@{ reason = "shutdown"; at = (At 30) })) -Observation $fresh -InventoryComplete $true -InInventory $false -TtlSeconds 600 -Now (At 120)
Check ($s1.state -ceq "unknown" -and $s1.reason -clike "*shut down*") "a session on a node that shut down is unknown, never declared dead"
$nodeUnknownAnswer = New-HordeRemoteObservation -Answer (New-HordeUnknown -Reason "the node's projection could not read the host") -NodeSentAt (At 100) -ReceivedAt (At 100)
$s1 = Get-HordeSessionLiveness -Node $null -Observation $fresh -InventoryComplete $true -InInventory $true -TtlSeconds 60 -Now (At 120)
Check ($s1.state -ceq "unknown") "no node record at all: the session is unknown"
$s1 = Get-HordeSessionLiveness -Node $nodeUp -Observation $null -InventoryComplete $true -InInventory $true -TtlSeconds 60 -Now (At 120)
Check ($s1.state -ceq "unknown" -and $s1.reason -clike "*sent no answer*") "a session the node listed but sent nothing for is unknown"
$s1 = Get-HordeSessionLiveness -Node (Get-HordeNodeLiveness -Link $silent -Deregistered) -Observation $fresh -InventoryComplete $true -InInventory $false -TtlSeconds 60 -Now (At 120)
Check ($s1.state -ceq "unknown" -and $s1.reason -clike "*deregistered*") "a session on a deregistered node is unknown, never absent"
$s1 = Get-HordeSessionLiveness -Node $nodeUp -Observation $nodeUnknownAnswer -InventoryComplete $true -InInventory $true -TtlSeconds 60 -Now (At 120)
Check ($s1.state -ceq "unknown" -and $s1.reason -clike "*could not read the host*") "the node's own unknown is carried through with its reason"

Complete-HordeSuite -Success "the hub ages remote facts by its own clock, faults a skewed node, and says unknown whenever it cannot hear"
