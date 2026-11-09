# IS A MAIL OF THE WAKE WATCHER'S SENDERS DELIVERED ONLY WHEN THE TARGET SESSION'S OWN SIDE TOOK IT (T-0391, slice 9)?
#
# core/WakeMail.ps1 (Send-HordeWakeMail, Invoke-HordeWakeMailTakenTick), core/RestoreSource.ps1 (the resume mails and the stall notice),
# core/WakeTell.ps1 (what the warchief must hear) and core/WakeRun.ps1 (Update-HordeWakeTaken, the tick's look at the two awaiting lists),
# with the in-process messenger and no real session. The bug: the messenger ACCEPTING a post was counted as the session being told. The
# restore source marked the mail posted (a restore counted done) and the tell sender marked the warchief told, and nothing ever asked
# whether the session had it. The same cure as slices 1 to 7 (decisions/NoticeTaken.ps1, used as it is):
#   - POSTED, NOT DELIVERED: an accepted post is awaiting, in the journal and in the marks; only the session's own TAKEN
#     (handed-over, seen) counts the restore done / the warchief told.
#   - MARK FIRST, THEN POST; a known refusal takes the mark off; an unknown result keeps it.
#   - ONE ALARM; a RESTART posts and alarms nothing twice; SHADOW writes no mark and posts nothing.
# Its mutation specs: test\mutations\wake-mail-taken.psd1 (and wake-mail.psd1, restore-source.psd1, wake-tell.psd1).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "test\lib\FleetPin.ps1")
. (Join-Path $root "test\lib\MessengerPins.ps1")
$fleetPin = Enter-HordeTestEmptyFleet
$pinned = Enter-HordeTestPinnedHome -Root $root
. (Join-Path $root "core\WakeRun.ps1")
. (Join-Path $root "messengers\memory\Messenger.ps1")

$settings = Get-HordeRestoreSettings -Overrides @{ restoreSettleSeconds = 0 }
$t0 = New-Object System.DateTime(2026, 10, 12, 8, 0, 0, [System.DateTimeKind]::Utc)
function At { param([double]$Seconds) return $t0.AddSeconds($Seconds) }
function Sid { param([int]$N) return ("0a000000-0000-4000-8000-" + $N.ToString("000000000000")) }
function New-Home {
    $h = Join-Path $pinned.home ("h-" + [guid]::NewGuid().ToString("N"))
    [void](New-Item -ItemType Directory -Path $h)
    return $h
}
function Mail { param([int]$N) return [pscustomobject]@{ kind = "resume"; to = (Sid 2); messageId = ("0d000000-0000-4000-8000-" + $N.ToString("000000000000")); body = "resume" } }
function Ids { param($Kind, [string]$H) return (@(Get-HordeWakeMailAwaitingIds -Kind $Kind -HordeHome $H) -join ",") }

try {
$inProcess = Get-HordeMessenger -Name "memory"

# ---- a twelve-session restore, as test-restore-source.ps1 has it: one warchief, three orcs, eight wargs ----
function New-Restored {
    $out = @()
    for ($n = 1; $n -le 12; $n++) {
        $role = "warg"; $parent = ""
        if ($n -eq 1) { $role = "warchief" } elseif ($n -le 4) { $role = "orc"; $parent = Sid 1 }
        elseif ($n -le 7) { $parent = Sid 2 } elseif ($n -le 10) { $parent = Sid 3 } else { $parent = Sid 4 }
        $start = At (($n - 1) * 13)
        $out += [pscustomobject]@{ id = (Sid $n); role = $role; parent = $parent; startedAt = $start; lastChangeAt = $start.AddSeconds(4); status = "idle"; firstSeenAt = $start.AddHours(-5) }
    }
    return $out
}
$fleet = New-Restored
$end = 143

Write-Host ""
Write-Host "--- RED ON MAIN: an accepted post is not delivered ---" -ForegroundColor Cyan
Reset-HordeMemoryMessenger
$h = New-Home
$through = { param($m) Send-HordeRestoreMail -Mail $m -Settings $settings -Messenger $inProcess -HordeHome $h }
$r = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 10)) -Settings $settings -Post $through -Posted @{}
Check ((Get-HordeMemoryMessengerLog).posts -eq 3) "CONTROL: the pass posted the three resume mails through the in-process messenger, which answers accepted and never handed-over"
Check (@($r.entries | Where-Object { $_.outcome -ceq "posted" }).Count -eq 0) "the restore source journals none of them as posted"
Check ($r.posted.Count -eq 0) "and counts no restore done: none is in the posted table until the session took it"
$ts = Get-HordeWakeTellSettings
$cond = New-HordeWakeTellCondition -Kind "gave-up" -Subject (Sid 2) -Instance "2026-10-12T08:00:00Z" -Text "x"
$tellThrough = { param($m) Send-HordeWakeTell -Mail $m -Settings $ts -Messenger $inProcess -HordeHome $h }
$tp = Invoke-HordeWakeTellPass -Conditions @($cond) -Warchief (Sid 1) -Now (At 0) -Settings $ts -Post $tellThrough
$tid = Get-HordeWakeTellMessageId -Condition $cond
Check (@($tp.entries | Where-Object { $_.outcome -ceq "posted" }).Count -eq 0 -and $tp.told[$tid].state -cne "told") "the tell sender does not count the warchief told on an accepted post"

Write-Host ""
Write-Host "--- what an accepted post answers, and what the pass does with it ---" -ForegroundColor Cyan
$rk = $script:HordeRestoreTakenKind
$tk = $script:HordeWakeTellTakenKind
Check ($rk.path[-1] -cne $tk.path[-1] -and $rk.path[-1] -ceq "restore-taken.json" -and $tk.path[-1] -ceq "tells-taken.json") "CONTROL: the two senders each have a list file of their own under the home"
Reset-HordeMemoryMessenger
$h = New-Home
$m1 = Mail 1
$a = Send-HordeRestoreMail -Mail $m1 -Settings $settings -Messenger $inProcess -HordeHome $h -Now (At 0)
Check ($a.state -ceq "unknown" -and (Test-HordeWakeMailAwaiting $a) -and $a.awaiting.stage -ceq "accepted" -and $a.awaiting.messenger -ceq "memory") "an accepted post is unknown with the facts of the post: awaiting, never known"
Check ((Ids $rk $h) -ceq $m1.messageId) "and its mark is on the restore source's list"
$none = Send-HordeRestoreMail -Mail (Mail 2) -Settings $settings -HordeHome $h
Check (-not (Test-HordeWakeMailAwaiting $none) -and $none.state -ceq "unknown" -and (Ids $rk $h) -ceq $m1.messageId) "no messenger to post through is unknown, not awaiting, and leaves no mark"
$bad = Send-HordeRestoreMail -Mail ([pscustomobject]@{ kind = "stall"; to = ""; messageId = (Mail 3).messageId; body = "x" }) -Settings $settings -Messenger $inProcess -HordeHome $h
Check ($bad.state -ceq "unknown" -and (Ids $rk $h) -ceq $m1.messageId) "a mail the port would refuse is never marked"
$one = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 10)) -Settings $settings -Post { param($m) Send-HordeRestoreMail -Mail $m -Settings $settings -Messenger $inProcess -HordeHome $h -Now (At ($end + 10)) } -Posted @{}
$ids = @($one.entries | ForEach-Object { $_.messageId })
Check (@($one.entries | Where-Object { $_.outcome -ceq "awaiting" -and $_.reason.Contains("not counted as delivered until the session's own TAKEN") }).Count -eq 3 -and $one.posted.Count -eq 0) "the pass journals each accepted mail as awaiting, says it is not delivered, and counts none posted"
$again = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 20)) -Settings $settings -Post { param($m) throw "must not post" } -Posted $one.posted -Awaiting @(Get-HordeWakeMailAwaitingIds -Kind $rk -HordeHome $h)
Check (@($again.entries).Count -eq 0) "a later pass does not post or journal what is on the awaiting list again"

Write-Host ""
Write-Host "--- mark before post; a refusal removes it; an unknown result keeps it ---" -ForegroundColor Cyan
$h = New-Home
$script:markAtPost = $null
$spy = Register-HordeMessenger -Folder (Join-Path $root "test\fixtures\messenger\caps\fixture-good") -Post { param($m) if ($null -eq $script:markAtPost) { $script:markAtPost = (Ids $script:rk $script:spyHome) }; New-HordeKnown -Value ([pscustomobject]@{ messageId = $m.messageId; stage = $script:spySays; at = [datetime]::UtcNow; reason = "stand-in" }) } -Status { param($id) New-HordeAbsent -Note "the stand-in keeps no status" }
$script:rk = $rk; $script:spyHome = $h; $script:spySays = "accepted"
$mk = Mail 10
$null = Send-HordeRestoreMail -Mail $mk -Settings $settings -Messenger $spy -HordeHome $h -Now (At 0)
Check ($script:markAtPost -ceq $mk.messageId) "the mark is on the list when the messenger is asked to post: mark first, then post"
$script:spySays = "held"; $mh = Mail 11
$held = Send-HordeRestoreMail -Mail $mh -Settings $settings -Messenger $spy -HordeHome $h -Now (At 0)
Check ($held.state -ceq "unknown" -and -not (Test-HordeWakeMailAwaiting $held) -and (Ids $rk $h) -ceq $mk.messageId) "a post the messenger refuses (held) is unknown, not awaiting, and its mark comes off"
[void]$script:HordeMessengers.Remove("fixture-good")
$spy2 = Register-HordeMessenger -Folder (Join-Path $root "test\fixtures\messenger\caps\fixture-good") -Post { param($m) New-HordeUnknown -Reason "the stand-in could not tell" } -Status { param($id) New-HordeAbsent -Note "none" }
$mu = Mail 12
$unk = Send-HordeRestoreMail -Mail $mu -Settings $settings -Messenger $spy2 -HordeHome $h -Now (At 0)
Check ($unk.state -ceq "unknown" -and -not (Test-HordeWakeMailAwaiting $unk) -and (Ids $rk $h).Contains($mu.messageId)) "an unknown result keeps the mark: a post that may have landed stays watched"
[void]$script:HordeMessengers.Remove("fixture-good")
# A list that cannot be written posts nothing.
$h2 = New-Home
[void](New-Item -ItemType Directory -Path (Join-Path $h2 "wake\restore-taken.json") -Force)
Reset-HordeMemoryMessenger
$blocked = Send-HordeRestoreMail -Mail (Mail 13) -Settings $settings -Messenger $inProcess -HordeHome $h2 -Now (At 0)
Check ($blocked.state -ceq "unknown" -and $blocked.reason.Contains("cannot be awaited") -and (Get-HordeMemoryMessengerLog).posts -eq 0) "a list that cannot be read or written means no post, and the reason is said"

Write-Host ""
Write-Host "--- TAKEN: handed-over and seen deliver; one ALARM; a restart does nothing twice ---" -ForegroundColor Cyan
Reset-HordeMemoryMessenger
$h = New-Home
$mem = @{}
$ma = Mail 20; $mb = Mail 21; $mc = Mail 22
foreach ($m in @($ma, $mb, $mc)) { $null = Send-HordeRestoreMail -Mail $m -Settings $settings -Messenger $inProcess -HordeHome $h -Now (At 0) }
$q = Invoke-HordeWakeMailTakenTick -Kind $rk -HordeHome $h -Now (At 60) -Messenger $inProcess -Memory $mem
Check (@($q.left).Count -eq 0 -and @($q.lines).Count -eq 0) "while the messenger's status says accepted, nothing is delivered and nothing is said"
Set-HordeMemoryMessengerStage -MessageId $ma.messageId -Stage "handed-over"
$q = Invoke-HordeWakeMailTakenTick -Kind $rk -HordeHome $h -Now (At 70) -Messenger $inProcess -Memory $mem
Check (@($q.left).Count -eq 1 -and $q.left[0].id -ceq $ma.messageId -and $q.left[0].delivered -and ($q.lines -join "|").Contains("TAKEN:")) "handed-over is the session's own TAKEN: delivered, said as TAKEN"
Set-HordeMemoryMessengerStage -MessageId $mb.messageId -Stage "seen"
$q = Invoke-HordeWakeMailTakenTick -Kind $rk -HordeHome $h -Now (At 80) -Messenger $inProcess -Memory $mem
Check (@($q.left).Count -eq 1 -and $q.left[0].id -ceq $mb.messageId -and $q.left[0].delivered) "and so is seen"
$q = Invoke-HordeWakeMailTakenTick -Kind $rk -HordeHome $h -Now (At 400) -Messenger $inProcess -Memory $mem
Check (@($q.lines | Where-Object { $_.StartsWith("ALARM:") }).Count -eq 1 -and ($q.lines -join "|").Contains("was NOT TAKEN") -and @($q.left).Count -eq 0) "the one still not taken alarms at the alarm time, once"
$q = Invoke-HordeWakeMailTakenTick -Kind $rk -HordeHome $h -Now (At 700) -Messenger $inProcess -Memory $mem
Check (@($q.lines | Where-Object { $_.StartsWith("ALARM:") }).Count -eq 0) "and is not alarmed a second time"
# A RESTART: a new process has no memory. The same mail is posted again under the same id and the alarm is in the mark.
$restartMem = @{}
$null = Send-HordeRestoreMail -Mail $mc -Settings $settings -Messenger $inProcess -HordeHome $h -Now (At 800)
Check ((Get-HordeMemoryMessengerLog -MessageId $mc.messageId).records -eq 1 -and @((Ids $rk $h) -split ",").Count -eq 1) "after a restart the same id is one message in the messenger and one mark on the list"
$q = Invoke-HordeWakeMailTakenTick -Kind $rk -HordeHome $h -Now (At 900) -Messenger $inProcess -Memory $restartMem
Check (@($q.lines | Where-Object { $_.StartsWith("ALARM:") }).Count -eq 0) "and a restarted tick alarms nothing twice"
Set-HordeMemoryMessengerStage -MessageId $mc.messageId -Stage "seen"
$q = Invoke-HordeWakeMailTakenTick -Kind $rk -HordeHome $h -Now (At 1300) -Messenger $inProcess -Memory $restartMem
Check (@($q.left).Count -eq 1 -and $q.left[0].delivered -and ($q.lines -join "|").Contains("after the alarm")) "a late TAKEN says so"

Write-Host ""
Write-Host "--- the tick: a restore is counted done, and the warchief told, only on the TAKEN ---" -ForegroundColor Cyan
Reset-HordeMemoryMessenger
$h = New-Home
$run = New-HordeWakeRun -Live -Self "" -HordeHome $h
$run.warchief = (Sid 1)
$postWas = $script:HordeWakeSendersPost
try {
    $script:HordeWakeSendersPost = $true
    $read = { New-HordeKnown -Value @($fleet) }
    $e1 = @(Invoke-HordeWakeTick -Run $run -Now (At ($end + 10)) -ReadSessions $read -RestoreSettings $settings -Messenger $inProcess -HordeHome $h)
    Check (@($e1 | Where-Object { $_.kind -ceq "post" -and $_.outcome -ceq "awaiting" }).Count -eq 3 -and @($e1 | Where-Object { $_.outcome -ceq "posted" }).Count -eq 0) "a live tick journals the three resume mails as awaiting, none as posted"
    Check ($run.posted.Count -eq 0) "and counts no restore done"
    Check (@(Get-HordeWakeMailAwaitingIds -Kind $rk -HordeHome $h).Count -eq 3) "the three are on the awaiting list"
    $e2 = @(Invoke-HordeWakeTick -Run $run -Now (At ($end + 50)) -ReadSessions $read -RestoreSettings $settings -Messenger $inProcess -HordeHome $h)
    Check ((Get-HordeMemoryMessengerLog).posts -eq 3 -and @($e2 | Where-Object { $_.kind -ceq "post" }).Count -eq 0) "a later tick posts nothing again"
    $first = @($e1 | Where-Object { $_.kind -ceq "post" })[0].messageId
    Set-HordeMemoryMessengerStage -MessageId $first -Stage "handed-over"
    $e3 = @(Invoke-HordeWakeTick -Run $run -Now (At ($end + 100)) -ReadSessions $read -RestoreSettings $settings -Messenger $inProcess -HordeHome $h)
    Check (@($e3 | Where-Object { $_.kind -ceq "mail-taken" -and $_.outcome -ceq "taken" }).Count -eq 1 -and $run.posted.Count -eq 1 -and $run.posted.ContainsKey($first)) "on a TAKEN the tick journals it and only then counts that restore mail done"
    $saved = Read-HordeRestoreState -Name (Get-HordeWakeSenderFile -Run $run -Stem "restore").name -Mode (Get-HordeWakeSenderFile -Run $run -Stem "restore").mode -HordeHome $h
    Check ($saved.state -ceq "known" -and $saved.value.posted.ContainsKey($first)) "and it is saved: a restarted watcher reads it back"
    $e4 = @(Invoke-HordeWakeTick -Run $run -Now (At ($end + 500)) -ReadSessions $read -RestoreSettings $settings -Messenger $inProcess -HordeHome $h)
    Check (@($e4 | Where-Object { $_.kind -ceq "mail-taken" -and $_.outcome -ceq "alarm" }).Count -eq 2) "the two not taken are alarmed, one line each"
    $e5 = @(Invoke-HordeWakeTick -Run $run -Now (At ($end + 530)) -ReadSessions $read -RestoreSettings $settings -Messenger $inProcess -HordeHome $h)
    Check (@($e5 | Where-Object { $_.kind -ceq "mail-taken" }).Count -eq 0) "and the next tick does not alarm them again"
    # A RESTARTED WATCHER reads the lists and the saved state back.
    $run2 = New-HordeWakeRun -Live -Self "" -HordeHome $h
    $e6 = @(Invoke-HordeWakeTick -Run $run2 -Now (At ($end + 560)) -ReadSessions $read -RestoreSettings $settings -Messenger $inProcess -HordeHome $h)
    Check ((Get-HordeMemoryMessengerLog).posts -eq 4 -and @($e6 | Where-Object { $_.outcome -ceq "alarm" -or $_.kind -ceq "post" }).Count -eq 0) "a restarted watcher posts nothing twice (three resume mails and the one stall notice, four posts in all) and alarms nothing twice"
    # THE TELL: the same, through the tell sender's state.
    $tid2 = Get-HordeWakeTellMessageId -Condition $cond
    $tm = Invoke-HordeWakeTellPass -Conditions @($cond) -Warchief (Sid 1) -Now (At 1000) -Settings $ts -Post { param($m) Send-HordeWakeTell -Mail $m -Settings $ts -Messenger $inProcess -HordeHome $h -Now (At 1000) } -Told $run.told
    $run.told = $tm.told
    Check ($run.told[$tid2].state -ceq "awaiting" -and @($tm.entries | Where-Object { $_.outcome -ceq "awaiting" }).Count -eq 1) "a tell the messenger accepted is awaiting in the told table, not told"
    $upd = @(Update-HordeWakeTaken -Run $run -Now (At 1010) -Messenger $inProcess -HordeHome $h)
    Check ($run.told[$tid2].state -ceq "awaiting") "and is still awaiting while the warchief's session has not taken it"
    Set-HordeMemoryMessengerStage -MessageId $tid2 -Stage "seen"
    $upd = @(Update-HordeWakeTaken -Run $run -Now (At 1020) -Messenger $inProcess -HordeHome $h)
    Check ($run.told[$tid2].state -ceq "told" -and @($upd | Where-Object { $_.id -ceq "tells" -and $_.outcome -ceq "taken" }).Count -eq 1) "on the warchief session's TAKEN it is told, and journaled"
    # A GIVE-UP IS NOT A DELIVERY: eight days on, with nothing taken, the lists give up with an ALARM, the tell is "undelivered" and not "told",
    # and the restore mails are not planned again.
    $late = At (8 * 86400)
    $gu = @(Update-HordeWakeTaken -Run $run -Now $late -Messenger $inProcess -HordeHome $h)
    Check (@($gu | Where-Object { $_.outcome -ceq "undelivered" }).Count -ge 1 -and @($gu | Where-Object { $_.outcome -ceq "taken" }).Count -eq 0) "a mail nobody took in seven days is journaled as undelivered (the ALARM of the give-up), never as taken"
    Check (@(Get-HordeWakeMailAwaitingIds -Kind $rk -HordeHome $h).Count -eq 0 -and $run.posted.Count -eq 4) "and the given-up restore mails leave the list and are not planned again"
    $cond2 = New-HordeWakeTellCondition -Kind "gave-up" -Subject (Sid 3) -Instance "2026-10-12T09:00:00Z" -Text "y"
    $tid3 = Get-HordeWakeTellMessageId -Condition $cond2
    $tm2 = Invoke-HordeWakeTellPass -Conditions @($cond2) -Warchief (Sid 1) -Now (At 2000) -Settings $ts -Post { param($m) Send-HordeWakeTell -Mail $m -Settings $ts -Messenger $inProcess -HordeHome $h -Now (At 2000) } -Told $run.told
    $run.told = $tm2.told
    $gu2 = @(Update-HordeWakeTaken -Run $run -Now (At (2000 + 8 * 86400)) -Messenger $inProcess -HordeHome $h)
    Check ($run.told[$tid3].state -ceq "undelivered") "a tell given up untaken is undelivered in the told table, not told"
} finally { $script:HordeWakeSendersPost = $postWas }

Write-Host ""
Write-Host "--- a tell awaiting its TAKEN still counts against the hour's budget ---" -ForegroundColor Cyan
Reset-HordeMemoryMessenger
$h = New-Home
$tight = Get-HordeWakeTellSettings -Overrides @{ maxTellsPerHour = 2 }
$conds = @(2, 3, 4 | ForEach-Object { New-HordeWakeTellCondition -Kind "gave-up" -Subject (Sid $_) -Instance "2026-10-12T08:00:00Z" -Text "z" })
$bp = Invoke-HordeWakeTellPass -Conditions $conds -Warchief (Sid 1) -Now (At 0) -Settings $tight -Post { param($m) Send-HordeWakeTell -Mail $m -Settings $tight -Messenger $inProcess -HordeHome $h -Now (At 0) }
Check (@($bp.entries | Where-Object { $_.outcome -ceq "awaiting" }).Count -eq 2 -and @($bp.entries | Where-Object { $_.kind -ceq "tell-suppressed" }).Count -eq 1 -and (Get-HordeMemoryMessengerLog).posts -eq 2) "two accepted tells use the hour's budget of two, and the third is suppressed and not posted"

Write-Host ""
Write-Host "--- shadow writes no mark and posts nothing ---" -ForegroundColor Cyan
Reset-HordeMemoryMessenger
$h = New-Home
$shadowPoster = { param($m) throw "shadow must not post" }
$sh = Invoke-HordeRestoreSourcePass -Sessions $fleet -Now (At ($end + 10)) -Settings $settings -Shadow -Post $shadowPoster -Posted @{}
Check (@($sh.entries | Where-Object { $_.kind -ceq "would-post" }).Count -eq 3 -and (Get-HordeMemoryMessengerLog).posts -eq 0) "a shadow pass journals would-post and posts nothing"
$shT = Invoke-HordeWakeTellPass -Conditions @($cond) -Warchief (Sid 1) -Now (At 0) -Settings $ts -Shadow -Post $shadowPoster
Check (@($shT.entries | Where-Object { $_.kind -ceq "would-tell" }).Count -eq 1) "a shadow tell pass journals would-tell"
$runS = New-HordeWakeRun -Self "" -HordeHome $h
$eS = @(Invoke-HordeWakeTick -Run $runS -Now (At ($end + 10)) -ReadSessions { New-HordeKnown -Value @($fleet) } -RestoreSettings $settings -Messenger $inProcess -HordeHome $h)
Check ((Get-HordeMemoryMessengerLog).posts -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $h "wake\restore-taken.json")) -and -not (Test-Path -LiteralPath (Join-Path $h "wake\tells-taken.json"))) "a whole shadow tick posts nothing and writes no awaiting list"
$runL = New-HordeWakeRun -Live -Self "" -HordeHome $h
$eL = @(Invoke-HordeWakeTick -Run $runL -Now (At ($end + 10)) -ReadSessions { New-HordeKnown -Value @($fleet) } -RestoreSettings $settings -Messenger $inProcess -HordeHome $h)
Check ((Get-HordeMemoryMessengerLog).posts -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $h "wake\restore-taken.json"))) "and so does a live tick while the senders' switch is off"
} finally {
    Exit-HordeTestPinnedHome -State $pinned
    Exit-HordeTestEmptyFleet -Pin $fleetPin
}

Complete-HordeSuite -Success "a wake sender's mail counts as delivered only on the target session's own TAKEN: marked before posted, a refusal unmarks it, one alarm, a restart does nothing twice, and shadow writes nothing"
