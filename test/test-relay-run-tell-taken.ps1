# IS THE RELAY RUN'S "MAILBOX FULL" NOTICE DELIVERED ONLY WHEN THE WARCHIEF'S OWN SESSION TOOK IT (T-0391, slice 5 of 6)?
#
# cli/RelayRunTell.ps1, cli/RelayRun.ps1 (Invoke-HordeRelayRunPutNotes) and decisions/NoticeTaken.ps1, held without any real messenger,
# session or relay: a stand-in messenger, a stand-in seat and a context that only says which mailboxes are full. The bug: the run said
# "the warchief was told that <mailbox> is full" the moment the messenger ACCEPTED the post; the session may never have been prompted,
# and nothing asked. The same cure as the routed answers', the doorbell's and the photo notice's:
#   - MARK FIRST, THEN POST: an unusable list means no post, a stated reason, and the notice tried again later.
#   - A KNOWN refusal takes the mark off; an UNKNOWN result keeps it.
#   - POSTED, NOT DELIVERED: the line says so; only the session's own TAKEN (handed-over, seen) is delivered.
#   - ONE ALARM at takenAlarmSeconds, a re-ask cadence after it, and a 7-day give-up with an ALARM.
#   - A RESTART neither posts a second message (same notice id) nor alarms twice (the alarm is in the mark).
#   - Every line the list has reaches the run's log (the Say of the run), even with the mailbox no longer full.
# Its mutation specs: test\mutations\relay-run-tell-taken.psd1 (and decisions-route-taken.psd1 for the shared engine).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }

$work = Join-Path $env:TEMP ("horde-relay-run-tell-taken-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$keepHome = $env:HORDE_HOME
$keepFleet = $env:WEZFLEET_ROOT
$env:WEZFLEET_ROOT = Join-Path $work "no-fleet"
try {
. (Join-Path $root "core\Tristate.ps1")
. (Join-Path $root "core\ModuleSettings.ps1")
. (Join-Path $root "messengers\Port.ps1")
. (Join-Path $root "cli\RelayRun.ps1")
. (Join-Path $root "channels\chat\Taken.ps1")
$fx = Join-Path $here "fixtures\relay-run-tell"
# NO REAL MESSENGER IS EVER ASKED: only the folder of this suite's own is registered.
Check (@(Get-HordeMessengerNames).Count -eq 0) "CONTROL: no messenger is loaded until this suite registers its own"

# THE STAND-IN MESSENGER: every post, one record per messageId (idempotent), and an answer this suite chooses.
$script:posts = New-Object System.Collections.ArrayList
$script:postSays = "accepted"
# Ids the messenger already holds (posted before this pass): a repost of one answers already-posted with the first copy's stage and
# wakes nobody, as wezfleet does (lib/MailPost.ps1).
$script:held = @{}
$stubPost = {
    param($Message)
    [void]$script:posts.Add($Message)
    $mid = "$($Message.messageId)"
    if ($script:held.ContainsKey($mid) -and $script:postSays -ceq "accepted") {
        return (New-HordeKnown -Value ([pscustomobject]@{ messageId = $mid; stage = "handed-over"; at = [datetime]::UtcNow; reason = "already-posted: already posted; nothing written and nobody woken again" }) -ObservedAt ([datetime]::UtcNow))
    }
    if ($script:postSays -ceq "accepted") { $script:held[$mid] = $true }
    if ($script:postSays -ceq "unknown") { return (New-HordeUnknown -Reason "the stand-in could not tell") }
    return (New-HordeKnown -Value ([pscustomobject]@{ messageId = "$($Message.messageId)"; stage = $script:postSays; at = [datetime]::UtcNow; reason = $(if ($script:postSays -ceq "held") { "the stand-in refused it" } else { "" }) }) -ObservedAt ([datetime]::UtcNow))
}
# WHAT THE WARCHIEF'S OWN SIDE SAYS OF A POST, BY THE MESSENGER'S ID: nothing is "taken" until a test sets the stage, as the session's own
# hook does. A notice not named keeps no status (absent).
$script:stages = @{}
$script:askedIds = @{}
$stubStatus = {
    param($MessageId)
    $script:askedIds["$MessageId"] = 1 + [int]$script:askedIds["$MessageId"]
    $st = "$($script:stages["$MessageId"])"
    if ($st -ceq "") { return (New-HordeAbsent -Note "the stand-in keeps no status") }
    return (New-HordeKnown -Value ([pscustomobject]@{ messageId = "$MessageId"; stage = $st; at = [datetime]::UtcNow; reason = $(if ($st -ceq "held") { "the stand-in holds it" } else { "" }) }))
}
$null = Register-HordeMessenger -Folder (Join-Path $fx "relayrun") -Post $stubPost -Status $stubStatus
$seat = { return (New-HordeKnown -Value ([pscustomobject]@{ sessionId = "warchief-session-1"; pane = "3"; instance = "t1" })) }
# A folder that is not above the suite's homes, so they are not taken for a test's (A TEST'S HOME TELLS NOBODY).
$notTemp = Join-Path $env:TEMP ("horde-relay-run-tell-taken-elsewhere-" + [guid]::NewGuid().ToString("N"))
$t0 = [datetime]::new(2026, 10, 13, 12, 0, 0, [System.DateTimeKind]::Utc)

function New-Home {
    $h = Join-Path $work ("home-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path (Join-Path $h "settings") -Force | Out-Null
    return $h
}
function New-Run {
    # One run's table for its looks (a new one is a restart): { w; said }.
    param([string]$Home_, [double]$Alarm = 90, [double]$Check = 10, [double]$After = 60)
    $said = New-Object System.Collections.ArrayList
    $sayBlock = { param($Line) [void]$said.Add($Line) }.GetNewClosure()
    $w = New-HordeRelayRunWatching -Say $sayBlock -Sleep { param($Ms, $Why) } -StopPath (Join-Path $Home_ "relay\run.stop") -StartedMs 0 -CheckMs 1000 -HordeHome $Home_ -Tell $true -FromLabel "SV" -TakenAlarmSeconds $Alarm -TakenCheckSeconds $Check -TakenAfterAlarmSeconds $After
    return [pscustomobject]@{ w = $w; said = $said }
}
function New-Ctx {
    param([string[]]$Full = @("work/phone"))
    $fullMap = @{}
    foreach ($b in $Full) { $fullMap[$b] = [pscustomobject]@{ reason = "507 the relay's mailbox is full" } }
    return [pscustomobject]@{ untrimmed = @{}; full = $fullMap }
}
function Look {
    param($Run, $Ctx, [double]$Sec)
    $before = $Run.said.Count
    Invoke-HordeRelayRunPutNotes -Context $Ctx -Watching $Run.w -Seat $seat -TempRoot $notTemp -Now $t0.AddSeconds($Sec)
    return (@($Run.said.ToArray() | Select-Object -Skip $before) -join " | ")
}
function Get-Marks {
    param([string]$Home_)
    $r = Read-HordeTakenLedgerFile -Path (Join-Path $Home_ "relay\run-full-taken.json") -What "the relay-full notices" -Noun "notice"
    if ($r.state -cne "known") { return @() }
    return @(@($r.value.awaiting) | ForEach-Object { ConvertFrom-HordeChatTakenMark -Mark $_ })
}
function Marks-Of { param([string]$Home_, [string]$Id) return @(Get-Marks $Home_ | Where-Object { $_.messengerId -ceq $Id }) }
function Posts-Of { param([string]$Id) return @($script:posts.ToArray() | Where-Object { "$($_.messageId)" -ceq $Id }).Count }
function Alarms-In { param([string]$Text) return ([regex]::Matches($Text, "ALARM: relay-full notice")).Count }
function Id-Of {
    # The notice id of the fill that began -StartSec seconds after t0 (the run's first look at the full mailbox).
    param([string]$Home_, [string]$Box, [double]$StartSec = 0)
    return (Get-HordeRelayFullNoticeId -HordeHome $Home_ -Mailbox $Box -Fill (Get-HordeDecisionNoticeTakenNowMs -Now $t0.AddSeconds($StartSec)))
}

Write-Host ""
Write-Host "--- the settings: three numbers a person may tune ---" -ForegroundColor Cyan
$hS = New-Home
$d = (Get-HordeRelayRunSettings -HordeHome $hS).value
Check ($d.takenAlarmSeconds -eq 90 -and $d.takenCheckSeconds -eq 10 -and $d.takenAfterAlarmSeconds -eq 60) "takenAlarmSeconds 90, takenCheckSeconds 10 and takenAfterAlarmSeconds 60 by default, the chat's and the doorbell's own"
[System.IO.File]::WriteAllText((Join-Path $hS "settings\relay-run.json"), '{"schemaVersion":1,"settings":{"takenAlarmSeconds":5}}')
$bad = Get-HordeRelayRunSettings -HordeHome $hS
Check ($bad.state -cne "known" -and "$($bad.reason)".Contains("takenAlarmSeconds")) ("an alarm limit under 10 s refuses the file, by name (" + $bad.reason + ")")

Write-Host ""
Write-Host "--- BUG: accepted by the messenger is not delivered; the alarm, the re-ask, the restart ---" -ForegroundColor Cyan
$H1 = New-Home
$ctx = New-Ctx
$id1 = Id-Of $H1 "work/phone"
$run = New-Run $H1
$l = Look $run $ctx 0
$m = @(Marks-Of $H1 $id1)
Check ((Posts-Of $id1) -eq 1 -and $m.Count -eq 1 -and -not $m[0].alarmed) ("BUG: the notice is posted once and sits on the awaiting list (" + $l + ")")
Check ($m.Count -eq 1 -and $m[0].session -ceq "warchief-session-1") "the mark names the warchief's session"
Check (-not $l.Contains("was told") -and -not $l.Contains("TAKEN:") -and $l.Contains("delivered only when that session takes it")) "the run does NOT say the warchief was told for a notice nobody took"
Check ($script:posts[0].messageId -ceq $id1 -and $id1 -ceq (Id-Of $H1 "work/phone" 0)) "the notice id is the mailbox's and its fill's own: the same on every pass"
$asks0 = [int]$script:askedIds[$id1]
$null = Look $run $ctx 12
$null = Look $run $ctx 15
Check ([int]$script:askedIds[$id1] -eq ($asks0 + 1)) ("the list is asked about at takenCheckSeconds, not at every look (" + ($script:askedIds[$id1] - $asks0) + " asks for two looks 3 s apart)")
$l = Look $run $ctx 60
Check ((Alarms-In $l) -eq 0) ("no alarm before takenAlarmSeconds (" + $l + ")")
$l = Look $run $ctx 100
Check ((Alarms-In $l) -eq 1 -and $l.Contains("NOT TAKEN") -and @(Marks-Of $H1 $id1 | Where-Object { $_.alarmed }).Count -eq 1) ("ONE ALARM once it is not taken in time, said to the run's log and kept in the mark (" + $l + ")")
$asks = [int]$script:askedIds[$id1]
$l = Look $run $ctx 112
Check ((Alarms-In $l) -eq 0 -and [int]$script:askedIds[$id1] -eq $asks) "no second alarm, and it is not asked again before takenAfterAlarmSeconds"
$l = Look $run $ctx 170
Check ((Alarms-In $l) -eq 0 -and [int]$script:askedIds[$id1] -eq ($asks + 1) -and (Posts-Of $id1) -eq 1) "after the alarm it is asked again at the cadence, and still posted once"
# RESTART: a new table, the same home, the mailbox still full.
$keep = @(Marks-Of $H1 $id1)[0]
$run = New-Run $H1
$l = Look $run $ctx 240
$m = @(Marks-Of $H1 $id1)
Check ((Alarms-In $l) -eq 0 -and $m.Count -eq 1 -and $m[0].postedMs -eq $keep.postedMs -and $m[0].alarmed) ("RESTART: no second alarm, and the mark keeps its first clock (" + $l + ")")
Check ((Posts-Of $id1) -eq 2 -and @($script:posts | Where-Object { "$($_.messageId)" -cne $id1 }).Count -eq 0) "RESTART: the notice is posted under the same id (the messenger keeps one message), and no other"
# DELIVERED ONLY ON THE TAKEN.
$script:stages[$id1] = "handed-over"
$l = Look $run $ctx 300
Check ($l.Contains("TAKEN: relay-full notice " + $id1) -and $l.Contains("after the alarm") -and $l.Contains("delivered") -and @(Marks-Of $H1 $id1).Count -eq 0) ("TAKEN is said in the run's log, after the alarm, and the mark is gone (" + $l + ")")
$l = Look $run $ctx 400
Check ($l -ceq "") ("nothing is said again (" + $l + ")")

Write-Host ""
Write-Host "--- seen is taken too; a late TAKEN is said with the mailbox no longer full ---" -ForegroundColor Cyan
$H2 = New-Home
$run = New-Run $H2
$id2 = Id-Of $H2 "work/phone"
$null = Look $run (New-Ctx) 0
$script:stages[$id2] = "seen"
$l = Look $run (New-Ctx -Full @()) 20
Check ($l.Contains("TAKEN: relay-full notice " + $id2) -and $l.Contains("no longer full") -and @(Marks-Of $H2 $id2).Count -eq 0) ("TWIN: seen is taken too, and the log has it though the mailbox emptied (" + $l + ")")
$H2b = New-Home
$run = New-Run $H2b
$id2b = Id-Of $H2b "work/phone"
$null = Look $run (New-Ctx) 0
$null = Look $run (New-Ctx -Full @()) 30
$run = New-Run $H2b
$l = Look $run (New-Ctx -Full @()) 200
Check ((Alarms-In $l) -eq 1) ("the alarm for a notice whose mailbox emptied is still raised, after a restart too (" + $l + ")")
$script:stages[$id2b] = "handed-over"
$l = Look $run (New-Ctx -Full @()) 270
Check ($l.Contains("TAKEN: relay-full notice " + $id2b) -and @(Marks-Of $H2b $id2b).Count -eq 0) ("and the late TAKEN is said after the restart (" + $l + ")")

Write-Host ""
Write-Host "--- a notice the session already has is delivered in the pass that posts it; a full list is said ---" -ForegroundColor Cyan
$H9 = New-Home
$run = New-Run $H9
$id9 = Id-Of $H9 "work/phone"
$script:stages[$id9] = "handed-over"
$l = Look $run (New-Ctx) 0
Check ($l.Contains("TAKEN: relay-full notice " + $id9) -and @(Marks-Of $H9 $id9).Count -eq 0) ("a notice already taken (a restart of the same day) is delivered in the same pass (" + $l + ")")
$H10 = New-Home
$run = New-Run $H10
$id10 = Id-Of $H10 "work/phone"
$old = @(1..200 | ForEach-Object { ConvertTo-HordeChatTakenMark -Entry ([pscustomobject]@{ messageId = ("{0:x32}" -f $_); messengerId = ("00000000-0000-4000-8000-{0:x12}" -f $_); postedMs = [long]((Get-HordeDecisionNoticeTakenNowMs -Now $t0) - 1000); from = "00000000000000000000000000000000"; seq = [long]0; alarmed = $false; woken = $false; session = "" }) })
Write-HordeTakenLedgerFile -Path (Join-Path $H10 "relay\run-full-taken.json") -Ledger ([pscustomobject]@{ awaiting = $old }) -TempPrefix "test"
$l = Look $run (New-Ctx) 0
Check ($l.Contains("ALARM: relay-full notice 00000000-0000-4000-8000-000000000001") -and $l.Contains("left the awaiting list because it is full") -and @(Marks-Of $H10 $id10).Count -eq 1) ("a full awaiting list gives up its oldest mark WITH a line in the run's log (" + $l + ")")

Write-Host ""
Write-Host "--- EACH FILL HAS ITS OWN NOTICE: a refill on the same day posts a new id and is not a false TAKEN ---" -ForegroundColor Cyan
$H11 = New-Home
$run = New-Run $H11
$idA = Id-Of $H11 "work/phone" 0
$null = Look $run (New-Ctx) 0
$script:stages[$idA] = "seen"
$l = Look $run (New-Ctx) 20
Check ($l.Contains("TAKEN: relay-full notice " + $idA) -and @(Marks-Of $H11 $idA).Count -eq 0) ("the first fill's notice is taken (" + $l + ")")
$l = Look $run (New-Ctx -Full @()) 30
Check ($l.Contains("no longer full")) "the mailbox empties"
$postsBefore = $script:posts.Count
$l = Look $run (New-Ctx) 100
$idB = Id-Of $H11 "work/phone" 100
Check ($idB -cne $idA -and $script:posts.Count -eq ($postsBefore + 1) -and "$($script:posts[$script:posts.Count - 1].messageId)" -ceq $idB) ("a refill on the same day posts a NEW id, so the session is woken again (" + $l + ")")
Check (@(Marks-Of $H11 $idB).Count -eq 1 -and -not $l.Contains("TAKEN:") -and -not $l.Contains("NOT sent again")) "and the refill's notice waits for ITS OWN TAKEN: no TAKEN is logged for a notice never taken"
$l = Look $run (New-Ctx) 130
Check (-not $l.Contains("TAKEN:") -and @(Marks-Of $H11 $idB).Count -eq 1) "the next look does not log a TAKEN either"
# A restart inside one fill reuses the id (the fill start is kept in the home).
$run = New-Run $H11
$pre = $script:posts.Count
$l = Look $run (New-Ctx) 400
Check ("$($script:posts[$script:posts.Count - 1].messageId)" -ceq $idB -and (Posts-Of $idB) -eq 2 -and @(Marks-Of $H11 $idB).Count -eq 1) ("a restart inside one fill reuses the same id and keeps the mark (" + $l + ")")
Check ((Get-HordeRelayRunFillStart -HordeHome $H11 -Mailbox "work/phone" -NowMs 5) -eq (Get-HordeDecisionNoticeTakenNowMs -Now $t0.AddSeconds(100))) "the fill start survives in the home"

Write-Host ""
Write-Host "--- ALREADY POSTED with a brand-new mark is never logged as delivered ---" -ForegroundColor Cyan
$H12 = New-Home
$idC = Id-Of $H12 "work/phone" 0
$script:held[$idC] = $true
$script:stages[$idC] = "seen"
$run = New-Run $H12
$l = Look $run (New-Ctx) 0
Check ($l.Contains("was NOT sent again") -and -not $l.Contains("TAKEN:") -and @(Marks-Of $H12 $idC).Count -eq 0) ("the messenger answered already-posted for a mark this pass just wrote: said plainly, no mark, no TAKEN (" + $l + ")")
$l = Look $run (New-Ctx) 30
Check (-not $l.Contains("TAKEN:") -and (Posts-Of $idC) -eq 1) ("and the next look logs no delivery either, and the notice is not posted again (" + $l + ")")

Write-Host ""
Write-Host "--- the alarm limit is the setting's ---" -ForegroundColor Cyan
$H3 = New-Home
$run = New-Run $H3 -Alarm 30
$id3 = Id-Of $H3 "work/phone"
$null = Look $run (New-Ctx) 0
$l = Look $run (New-Ctx) 40
Check ((Alarms-In $l) -eq 1) ("an alarm limit of 30 s alarms at 40 s (" + $l + ")")

Write-Host ""
Write-Host "--- MARK FIRST: a list that cannot be read means no post, the reason said, tried again ---" -ForegroundColor Cyan
$H4 = New-Home
$run = New-Run $H4
$id4 = Id-Of $H4 "work/phone"
$ledger = Join-Path $H4 "relay\run-full-taken.json"
New-Item -ItemType Directory -Path (Split-Path -Parent $ledger) -Force | Out-Null
[System.IO.File]::WriteAllText($ledger, "this is not an awaiting list")
$ctx4 = New-Ctx
$l = Look $run $ctx4 0
Check ((Posts-Of $id4) -eq 0 -and $l.Contains("cannot be awaited") -and $l.Contains("NOT told")) ("UNUSABLE LIST: nothing is posted, and the reason is said (" + $l + ")")
$l = Look $run $ctx4 70
Check ((Posts-Of $id4) -eq 0 -and -not $l.Contains("cannot be awaited") -and -not $l.Contains("cannot be read")) ("tried again a minute later, and the same reasons are not said twice (" + $l + ")")
Remove-Item -LiteralPath $ledger -Force
$l = Look $run $ctx4 140
Check ((Posts-Of $id4) -eq 1 -and @(Marks-Of $H4 $id4).Count -eq 1) ("TWIN: once the list is usable the notice is marked, then posted (" + $l + ")")

Write-Host ""
Write-Host "--- a KNOWN refusal removes the mark; an UNKNOWN result keeps it ---" -ForegroundColor Cyan
$H5 = New-Home
$run = New-Run $H5
$id5 = Id-Of $H5 "work/phone"
$script:postSays = "held"
$ctx5 = New-Ctx
$l = Look $run $ctx5 0
Check (@(Marks-Of $H5 $id5).Count -eq 0 -and (Posts-Of $id5) -eq 1 -and $l.Contains("NOT told") -and $l.Contains("answered held")) ("REFUSED: a post the messenger refused leaves no mark and is said not told (" + $l + ")")
$l = Look $run $ctx5 300
Check ((Alarms-In $l) -eq 0) "and a refused post never alarms 'not taken' for something that was never sent"
$script:postSays = "accepted"
$l = Look $run $ctx5 400
Check (@(Marks-Of $H5 $id5).Count -eq 1 -and (Posts-Of $id5) -ge 2) "TWIN: the next accepted post is marked"
$H6 = New-Home
$run = New-Run $H6
$id6 = Id-Of $H6 "work/phone"
$script:postSays = "unknown"
$ctx6 = New-Ctx
$l = Look $run $ctx6 0
Check (@(Marks-Of $H6 $id6).Count -eq 1) ("UNKNOWN: a post whose result is not known keeps its mark, for it may have landed (" + $l + ")")
$l = Look $run $ctx6 100
Check ((Alarms-In $l) -eq 1 -and $l.Contains($id6)) ("and, never taken, it alarms (" + $l + ")")
$script:postSays = "accepted"

Write-Host ""
Write-Host "--- GIVE-UP: held for good, and 7 days without a TAKEN, each with an ALARM ---" -ForegroundColor Cyan
$H7 = New-Home
$run = New-Run $H7
$id7 = Id-Of $H7 "work/phone"
$null = Look $run (New-Ctx) 0
$script:stages[$id7] = "held"
$l = Look $run (New-Ctx) 20
Check ($l.Contains("ALARM:") -and $l.Contains("holds it for good") -and @(Marks-Of $H7 $id7).Count -eq 0) ("HELD: a notice the messenger holds for good alarms and is no longer watched (" + $l + ")")
$H8 = New-Home
$run = New-Run $H8
$id8 = Id-Of $H8 "work/phone"
$null = Look $run (New-Ctx) 0
$null = Look $run (New-Ctx) 100
$l = Look $run (New-Ctx) (604800 + 200)
Check ($l.Contains("NOT DELIVERED, given up") -and $l.Contains("ALARM:") -and @(Marks-Of $H8 $id8).Count -eq 0) ("GIVE-UP: a notice not taken in 7 days is given up with an ALARM (" + $l + ")")

Write-Host ""
Write-Host "--- through the run itself: the settings reach the list (the alarm limit of the settings file is the one used) ---" -ForegroundColor Cyan
# The run's channels, keys and relay are stood in for (this suite has no key store); the loop, its settings and its look at the list are real.
function Invoke-HordeRelayUnfinished { param($Context) return (New-HordeKnown -Value ([pscustomobject]@{ none = $true })) }
function Get-HordeRelayRunLines { param($Report) return @() }
function Invoke-HordeRelayChannelTicks { param($Context, $Only) return [pscustomobject]@{ lines = @(); failed = $false; againMs = 0 } }
function Receive-HordeRelayInbox { param($Context, $TimeoutMs, $SliceMs, $Between, $With) return (New-HordeKnown -Value ([pscustomobject]@{ vouched = @(); joined = @(); refused = @(); held = @(); missing = @(); anomalies = @(); taken = @(); data = @(); opened = $null })) }
function Close-HordeRelayRunContext { param($Context) }
function Remove-HordeRelayRetiredAgreeKeys { param($HordeHome) return (New-HordeKnown -Value ([pscustomobject]@{ released = @() })) }
function ConvertTo-HordeRelayRecordMs { return [long](Get-HordeDecisionNoticeTakenNowMs -Now ([datetime]::UtcNow)) }
$openStub = { param($H, $C, $D) return (New-HordeKnown -Value ([pscustomobject]@{ mailbox = "work/phone"; full = @{}; untrimmed = @{}; refusedWith = @{} })) }
$conn = [pscustomobject]@{ relay = [pscustomobject]@{ limits = [pscustomobject]@{ maxWatchMs = 60000 } } }
function New-RunHome {
    param([string]$SettingsJson)
    $h = New-Home
    [System.IO.File]::WriteAllText((Join-Path $h "settings\relay-run.json"), $SettingsJson)
    $ageMs = [long](Get-HordeDecisionNoticeTakenNowMs -Now ([datetime]::UtcNow)) - 100000
    $mark = ConvertTo-HordeChatTakenMark -Entry ([pscustomobject]@{ messageId = ("ab" * 16); messengerId = "abababab-abab-abab-abab-abababababab"; postedMs = $ageMs; from = "00000000000000000000000000000000"; seq = [long]0; alarmed = $false; woken = $false; session = "" })
    Write-HordeTakenLedgerFile -Path (Join-Path $h "relay\run-full-taken.json") -Ledger ([pscustomobject]@{ awaiting = @($mark) }) -TempPrefix "test"
    return $h
}
$base = '"minTurnMs": 50, "watchMs": 300, "sendCheckMs": 200'
$HR1 = New-RunHome ('{"schemaVersion": 1, "settings": {' + $base + ', "takenAlarmSeconds": 3600}}')
$ran1 = New-Object System.Collections.ArrayList
$r1 = Invoke-HordeRelayRun -HordeHome $HR1 -Connection $conn -MaxTurns 1 -Say { param($Line) [void]$ran1.Add($Line) } -OpenContext $openStub
Check ($r1.turns -eq 1 -and @($ran1 | Where-Object { $_ -clike "ALARM: relay-full notice*" }).Count -eq 0 -and @(Get-Marks $HR1 | Where-Object { $_.alarmed }).Count -eq 0) ("a notice 100 s old with takenAlarmSeconds 3600 in the settings file raises NO alarm (" + ($ran1 -join " | ") + ")")
$HR2 = New-RunHome ('{"schemaVersion": 1, "settings": {' + $base + '}}')
$ran2 = New-Object System.Collections.ArrayList
$r2 = Invoke-HordeRelayRun -HordeHome $HR2 -Connection $conn -MaxTurns 1 -Say { param($Line) [void]$ran2.Add($Line) } -OpenContext $openStub
Check ($r2.turns -eq 1 -and @($ran2 | Where-Object { $_ -clike "ALARM: relay-full notice*" }).Count -eq 1) ("CONTROL: the same notice with the default 90 s alarms once through the run (" + ($ran2 -join " | ") + ")")

Write-Host ""
Write-Host "--- another mailbox is another notice; a test's home still tells nobody ---" -ForegroundColor Cyan
Check ((Id-Of $H1 "other/phone") -cne $id1) "another mailbox is another notice id"
$tempTell = Send-HordeRelayFullNotice -Mailbox "work/phone" -HordeHome $H1 -FromLabel "SV" -Seat { throw "the seat must not be read for a home under the temp folder" }
Check (-not $tempTell.told -and $tempTell.problem.Contains("a test's") -and @($tempTell.lines).Count -eq 0) "A TEST'S HOME TELLS NOBODY: refused before any messenger, seat or list is looked for"
}
finally {
    $env:HORDE_HOME = $keepHome
    $env:WEZFLEET_ROOT = $keepFleet
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-HordeSuite -Success "the relay run's full-mailbox notice is delivered only on the warchief's own TAKEN, alarms once when it is not taken in time, and is never dropped"
