# IS A NOTICE FROM THE ANALYST'S SUPERVISOR TOLD ONLY WHILE IT IS WATCHED UNTIL THE WARCHIEF'S OWN SESSION TOOK IT (T-0391, slice 7)?
#
# cli/AnalystTend.ps1 (Send-HordeAnalystTell, Send-HordeAnalystWarchiefTaken, Invoke-HordeAnalystTellTakenTick, the pass's look at the awaiting
# list), core/AnalystSession.ps1 (the state's tellGen), cli/commands/analyst.ps1 (the real Tell and TellTaken blocks) and
# decisions/NoticeTaken.ps1, held without any real messenger, session or analyst: a stand-in messenger and a stand-in seat. The bug: the
# supervisor counted a post the messenger ACCEPTED as the warchief being told, put the key in the told list, and never said it again; the
# session may never have been prompted, and nothing asked. The same cure as the services', the doorbell's and the routed answers':
#   - MARK FIRST, THEN POST: an unusable list means no post, a stated reason, and the key NOT told.
#   - A KNOWN refusal takes the mark off; an UNKNOWN result keeps it.
#   - POSTED AND WATCHED, NOT DELIVERED: only the session's own TAKEN (handed-over, seen) is delivered.
#   - ONE ALARM at takenAlarmSeconds, a re-ask cadence after it (kept across passes), and a 7-day give-up with an ALARM.
#   - A RESTART neither posts a second message (same notice id) nor alarms twice (the alarm is in the mark); a LATER EVENT of the same key
#     has a new id (the key's generation), so it wakes someone.
#   - Every line the list has reaches the pass's lines (the supervisor's log).
# Its mutation spec: test\mutations\analyst-tell-taken.psd1 (and decisions-route-taken.psd1 for the shared engine).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }

$work = Join-Path $env:TEMP ("horde-analyst-tell-taken-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$keepHome = $env:HORDE_HOME
$keepFleet = $env:WEZFLEET_ROOT
$env:WEZFLEET_ROOT = Join-Path $work "no-fleet"
try {
foreach ($f in @("Tristate", "Home", "ModuleSettings", "Heartbeat", "AnalystRounds", "AnalystSession", "SessionSeat", "Device")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "messengers\Port.ps1")
. (Join-Path $root "cli\AnalystTend.ps1")
$fx = Join-Path $here "fixtures\analyst-tell-taken"
# NO REAL MESSENGER IS EVER ASKED: only the folder of this suite's own is registered.
Check (@(Get-HordeMessengerNames).Count -eq 0) "CONTROL: no messenger is loaded until this suite registers its own"

# THE STAND-IN MESSENGER: every post, one record per messageId (idempotent), and an answer this suite chooses.
$script:posts = New-Object System.Collections.ArrayList
$script:postSays = "accepted"
# Ids the messenger already holds: a repost of one answers already-posted with the first copy's stage and wakes nobody, as wezfleet does
# (lib/MailPost.ps1).
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
    return (New-HordeKnown -Value ([pscustomobject]@{ messageId = $mid; stage = $script:postSays; at = [datetime]::UtcNow; reason = $(if ($script:postSays -ceq "held") { "the stand-in refused it" } else { "" }) }) -ObservedAt ([datetime]::UtcNow))
}
# WHAT THE WARCHIEF'S OWN SIDE SAYS OF A POST, BY THE MESSENGER'S ID: nothing is "taken" until a test sets the stage, as the session's own hook
# does. A notice not named keeps no status (absent).
$script:stages = @{}
$script:askedIds = @{}
$stubStatus = {
    param($MessageId)
    $script:askedIds["$MessageId"] = 1 + [int]$script:askedIds["$MessageId"]
    $st = "$($script:stages["$MessageId"])"
    if ($st -ceq "") { return (New-HordeAbsent -Note "the stand-in keeps no status") }
    return (New-HordeKnown -Value ([pscustomobject]@{ messageId = "$MessageId"; stage = $st; at = [datetime]::UtcNow; reason = $(if ($st -ceq "held") { "the stand-in holds it" } else { "" }) }))
}
$null = Register-HordeMessenger -Folder (Join-Path $fx "atell") -Post $stubPost -Status $stubStatus
$seat = { return (New-HordeKnown -Value ([pscustomobject]@{ sessionId = "warchief-session-1"; pane = "3"; instance = "t1" })) }
# TWO SHIMS over the real lookups the post makes before it reaches a messenger, so the two refusals that happen BEFORE any post (no messenger
# can be found; this machine's device id cannot be had) can be made on demand. Off, each is the real function.
$origFindMessenger = ${function:Find-HordeMessenger}
$origDeviceId = ${function:Get-HordeDeviceId}
$script:noMessenger = $false
$script:noDevice = $false
function Find-HordeMessenger { param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Require) if ($script:noMessenger) { return (New-HordeAbsent -Note "the shim holds no messenger") }; return (& $origFindMessenger -Require $Require) }
function Get-HordeDeviceId { param([string]$HomeRoot = "") if ($script:noDevice) { throw "the shim has no device id" }; return (& $origDeviceId -HomeRoot $HomeRoot) }
# A folder that is not above the suite's homes, so they are not taken for a test's (A TEST'S HOME TELLS NOBODY).
$notTemp = Join-Path $env:TEMP ("horde-analyst-tell-taken-elsewhere-" + [guid]::NewGuid().ToString("N"))
$t0 = [datetime]::new(2026, 10, 13, 12, 0, 0, [System.DateTimeKind]::Utc)
$vals = [pscustomobject]@{ fromLabel = "AS"; tellWarchief = $true; takenAlarmSeconds = 90; takenAfterAlarmSeconds = 60 }

function New-Home {
    # Every home starts a new world for the stand-in messenger: the ids are made from a key and a generation, so two homes tell the same id,
    # and a messenger that remembered the first would answer already-posted to the second.
    $script:held = @{}; $script:stages = @{}; $script:askedIds = @{}; $script:posts.Clear()
    $h = Join-Path $work ("home-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path (Join-Path $h "settings") -Force | Out-Null
    return $h
}
function Send-One {
    # One notice told at -Sec seconds after t0: the answer of the real tell tool.
    param([string]$Home_, [string]$Key = "no-analyst", [long]$Gen = 0, [double]$Sec = 0)
    return (Send-HordeAnalystWarchiefTaken -Key $Key -Body "FLEET ANALYST SUPERVISOR`nwords" -Values $vals -Gen $Gen -HordeHome $Home_ -Now $t0.AddSeconds($Sec) -Seat $seat -TempRoot $notTemp)
}
function Id-Of { param([string]$Key, [long]$Gen = 0) return (ConvertTo-HordeAnalystMessageId -Seed ("tell:" + $Key + ":" + $Gen)) }
function Tick {
    # One look at the awaiting list at -Sec seconds after t0, as a new call each time: the lines, joined.
    param([string]$Home_, [double]$Sec, [double]$Alarm = 90, [double]$After = 60)
    return (@(Invoke-HordeAnalystTellTakenTick -HordeHome $Home_ -Now $t0.AddSeconds($Sec) -AlarmSeconds $Alarm -AfterAlarmSeconds $After) -join " | ")
}
function Get-Marks {
    param([string]$Home_)
    $r = Read-HordeTakenLedgerFile -Path (Join-Path $Home_ "analyst\tell-taken.json") -What "the analyst notices" -Noun "notice"
    if ($r.state -cne "known") { return @() }
    return @(@($r.value.awaiting) | ForEach-Object { ConvertFrom-HordeChatTakenMark -Mark $_ })
}
function Marks-Of { param([string]$Home_, [string]$Id) return @(Get-Marks $Home_ | Where-Object { $_.messengerId -ceq $Id }) }
function Posts-Of { param([string]$Id) return @($script:posts.ToArray() | Where-Object { "$($_.messageId)" -ceq $Id }).Count }
function Alarms-In { param([string]$Text) return ([regex]::Matches($Text, "ALARM: analyst supervisor notice")).Count }

Write-Host ""
Write-Host "--- the settings: two numbers a person may tune ---" -ForegroundColor Cyan
$hS = New-Home
$d = (Get-HordeAnalystSettings -HordeHome $hS).values
Check ($d.takenAlarmSeconds -eq 90 -and $d.takenAfterAlarmSeconds -eq 300) "takenAlarmSeconds 90 and takenAfterAlarmSeconds 300 by default, the chat's and the doorbell's own"
[System.IO.File]::WriteAllText((Join-Path $hS "settings\analyst.json"), '{"schemaVersion":1,"settings":{"takenAlarmSeconds":5}}')
$bad = Get-HordeAnalystSettings -HordeHome $hS
Check ($bad.state -ceq "refused" -and "$($bad.findings -join ' ')".Contains("takenAlarmSeconds")) ("an alarm limit under 10 s refuses the file, by name (" + ($bad.findings -join " ") + ")")

Write-Host ""
Write-Host "--- BUG: accepted by the messenger is not delivered; the alarm, the re-ask, the restart ---" -ForegroundColor Cyan
$H1 = New-Home
$id1 = Id-Of "no-analyst" 0
$s = Send-One $H1 "no-analyst" 0 0
$m = @(Marks-Of $H1 $id1)
Check ($s.ok -eq $true -and (Posts-Of $id1) -eq 1 -and $m.Count -eq 1 -and -not $m[0].alarmed) ("BUG: the notice is posted once and sits on the awaiting list (" + $s.detail + ")")
Check ($m.Count -eq 1 -and $m[0].session -ceq "warchief-session-1") "the mark names the warchief's session"
Check ($script:posts[0].messageId -ceq $id1) "the notice id is made from the key and its generation"
$l = Tick $H1 0
Check ($l -ceq "" -and $script:askedIds[$id1] -eq 1) ("a first look says nothing, and asks the messenger once (" + $l + ")")
$l = Tick $H1 60
Check ((Alarms-In $l) -eq 0) ("no alarm before takenAlarmSeconds (" + $l + ")")
$l = Tick $H1 100
Check ((Alarms-In $l) -eq 1 -and $l.Contains("NOT TAKEN") -and @(Marks-Of $H1 $id1 | Where-Object { $_.alarmed }).Count -eq 1) ("ONE ALARM once it is not taken in time, kept in the mark (" + $l + ")")
$asks = [int]$script:askedIds[$id1]
$l = Tick $H1 112
Check ((Alarms-In $l) -eq 0 -and [int]$script:askedIds[$id1] -eq $asks) "no second alarm, and (a new call each look) it is not asked again before takenAfterAlarmSeconds"
$l = Tick $H1 170
Check ((Alarms-In $l) -eq 0 -and [int]$script:askedIds[$id1] -eq ($asks + 1) -and (Posts-Of $id1) -eq 1) "after the alarm it is asked again at the cadence, and still posted once"
Check ([System.IO.File]::Exists((Join-Path $H1 "analyst\tell-taken-asked.txt"))) "when each mark was last asked is kept in the home between passes"
# RESTART: the supervisor tells the same event again (its state file was not written); the same home.
$keep = @(Marks-Of $H1 $id1)[0]
$s = Send-One $H1 "no-analyst" 0 240
$m = @(Marks-Of $H1 $id1)
Check ($s.ok -eq $true -and $m.Count -eq 1 -and $m[0].postedMs -eq $keep.postedMs -and $m[0].alarmed) "RESTART: the mark keeps its first clock and its alarm"
Check ((Posts-Of $id1) -eq 2 -and @($script:posts | Where-Object { "$($_.messageId)" -cne $id1 }).Count -eq 0 -and @($s.lines).Count -eq 0) "RESTART: the notice is posted under the same id (the messenger keeps one message), and no other"
$l = Tick $H1 300
Check ((Alarms-In $l) -eq 0) ("RESTART: no second alarm (" + $l + ")")
# DELIVERED ONLY ON THE TAKEN.
$script:stages[$id1] = "handed-over"
$l = Tick $H1 400
Check ($l.Contains("TAKEN: analyst supervisor notice " + $id1) -and $l.Contains("after the alarm") -and $l.Contains("delivered") -and @(Marks-Of $H1 $id1).Count -eq 0) ("TAKEN is said, after the alarm, and the mark is gone (" + $l + ")")
Check (-not [System.IO.File]::Exists((Join-Path $H1 "analyst\tell-taken-asked.txt"))) "and the cadence file forgets a notice that is over"
$l = Tick $H1 500
Check ($l -ceq "") ("nothing is said again (" + $l + ")")

Write-Host ""
Write-Host "--- seen is taken too; a notice the session already has is delivered at the first look ---" -ForegroundColor Cyan
$H2 = New-Home
$id2 = Id-Of "start-silent" 0
$null = Send-One $H2 "start-silent" 0 0
$script:stages[$id2] = "seen"
$l = Tick $H2 20
Check ($l.Contains("TAKEN: analyst supervisor notice " + $id2) -and @(Marks-Of $H2 $id2).Count -eq 0) ("TWIN: seen is taken too (" + $l + ")")

Write-Host ""
Write-Host "--- a full awaiting list is said ---" -ForegroundColor Cyan
$H10 = New-Home
$old = @(1..200 | ForEach-Object { ConvertTo-HordeChatTakenMark -Entry ([pscustomobject]@{ messageId = ("{0:x32}" -f $_); messengerId = ("00000000-0000-4000-8000-{0:x12}" -f $_); postedMs = [long]((Get-HordeDecisionNoticeTakenNowMs -Now $t0) - 1000); from = "00000000000000000000000000000000"; seq = [long]0; alarmed = $false; woken = $false; session = "" }) })
Write-HordeTakenLedgerFile -Path (Join-Path $H10 "analyst\tell-taken.json") -Ledger ([pscustomobject]@{ awaiting = $old }) -TempPrefix "test"
$s = Send-One $H10 "no-spawn-gone" 0 0
$l = @($s.lines) -join " | "
Check ($l.Contains("ALARM: analyst supervisor notice 00000000-0000-4000-8000-000000000001") -and $l.Contains("left the awaiting list because it is full") -and @(Marks-Of $H10 (Id-Of "no-spawn-gone" 0)).Count -eq 1) ("a full awaiting list gives up its oldest mark WITH a line the caller can say (" + $l + ")")

Write-Host ""
Write-Host "--- ALREADY POSTED with a brand-new mark is never counted as delivered ---" -ForegroundColor Cyan
$H12 = New-Home
$idC = Id-Of "spawn-failed" 0
$script:held[$idC] = $true
$script:stages[$idC] = "seen"
$s = Send-One $H12 "spawn-failed" 0 0
$l = @($s.lines) -join " | "
Check ($s.ok -eq $true -and $l.Contains("was NOT sent again") -and @(Marks-Of $H12 $idC).Count -eq 0) ("the messenger answered already-posted for a mark this pass just wrote: said plainly, no mark, the key still told (" + $l + ")")
$l = Tick $H12 30
Check (-not $l.Contains("TAKEN:") -and (Posts-Of $idC) -eq 1) ("and the next look logs no delivery either (" + $l + ")")
$H13 = New-Home
$idD = Id-Of "no-answer" 0
$null = Send-One $H13 "no-answer" 0 0
$s = Send-One $H13 "no-answer" 0 30
Check ($s.ok -eq $true -and @(Marks-Of $H13 $idD).Count -eq 1 -and (@($s.lines) -join " ") -notlike "*NOT sent again*") "CONTROL: a repost of a notice already on the list (a restart) keeps its mark and is counted"

Write-Host ""
Write-Host "--- the alarm limit is the setting's ---" -ForegroundColor Cyan
$H3 = New-Home
$null = Send-One $H3 "start-too-soon-gone" 0 0
$l = Tick $H3 40 30
Check ((Alarms-In $l) -eq 1) ("an alarm limit of 30 s alarms at 40 s (" + $l + ")")

Write-Host ""
Write-Host "--- MARK FIRST: a list that cannot be read means no post, the reason said, the key not told ---" -ForegroundColor Cyan
$H4 = New-Home
$id4 = Id-Of "refused" 0
$ledger = Join-Path $H4 "analyst\tell-taken.json"
New-Item -ItemType Directory -Path (Split-Path -Parent $ledger) -Force | Out-Null
[System.IO.File]::WriteAllText($ledger, "this is not an awaiting list")
$s = Send-One $H4 "refused" 0 0
Check ((Posts-Of $id4) -eq 0 -and $s.ok -eq $false -and $s.detail.Contains("cannot be awaited")) ("UNUSABLE LIST: nothing is posted, and the reason is given (" + $s.detail + ")")
Remove-Item -LiteralPath $ledger -Force
$s = Send-One $H4 "refused" 0 60
Check ((Posts-Of $id4) -eq 1 -and $s.ok -eq $true -and @(Marks-Of $H4 $id4).Count -eq 1) "TWIN: once the list is usable the notice is marked, then posted"

Write-Host ""
Write-Host "--- a KNOWN refusal removes the mark; an UNKNOWN result keeps it ---" -ForegroundColor Cyan
$H5 = New-Home
$id5 = Id-Of "no-analyst" 0
$script:postSays = "held"
$s = Send-One $H5 "no-analyst" 0 0
Check (@(Marks-Of $H5 $id5).Count -eq 0 -and (Posts-Of $id5) -eq 1 -and $s.ok -eq $false -and $s.detail.Contains("answered held")) ("REFUSED: a post the messenger refused leaves no mark and is not told (" + $s.detail + ")")
$l = Tick $H5 300
Check ((Alarms-In $l) -eq 0) "and a refused post never alarms 'not taken' for something that was never sent"
$script:postSays = "accepted"
$s = Send-One $H5 "no-analyst" 0 400
Check (@(Marks-Of $H5 $id5).Count -eq 1 -and $s.ok -eq $true) "TWIN: the next accepted post of the same notice is marked and told"
$H6 = New-Home
$id6 = Id-Of "no-spawn-over-cap" 0
$script:postSays = "unknown"
$s = Send-One $H6 "no-spawn-over-cap" 0 0
Check (@(Marks-Of $H6 $id6).Count -eq 1 -and $s.ok -eq $false -and $s.detail.Contains("did not take it")) ("UNKNOWN: a post whose result is not known keeps its mark (it may have landed) and is not counted told (" + $s.detail + ")")
$l = Tick $H6 100
Check ((Alarms-In $l) -eq 1 -and $l.Contains($id6)) ("and, never taken, it alarms (" + $l + ")")
$script:postSays = "accepted"

Write-Host ""
Write-Host "--- A KNOWN refusal never removes a mark that was ALREADY on the list (T-0391 round 2, item 1) ---" -ForegroundColor Cyan
# The story: the post was accepted and marked, the supervisor restarted before it wrote its state, and the next pass cannot post (no
# messenger / no device id / a held answer). The first post is still in the warchief's mailbox, so its mark must stay.
foreach ($why in @("no-messenger", "no-device-id", "held")) {
    $HL = New-Home
    $idL = Id-Of "no-analyst" 0
    $null = Send-One $HL "no-analyst" 0 0
    $before = @(Marks-Of $HL $idL)
    if ($why -ceq "no-messenger") { $script:noMessenger = $true } elseif ($why -ceq "no-device-id") { $script:noDevice = $true } else { $script:postSays = "held" }
    $s = Send-One $HL "no-analyst" 0 60
    $script:noMessenger = $false; $script:noDevice = $false; $script:postSays = "accepted"
    $after = @(Marks-Of $HL $idL)
    Check ($before.Count -eq 1 -and $s.ok -eq $false -and $after.Count -eq 1 -and $after[0].postedMs -eq $before[0].postedMs) ("REFUSED AFTER A POST THAT LANDED (" + $why + "): the mark stays, with its clock (" + $s.detail + ")")
    $l = Tick $HL 100
    Check ((Alarms-In $l) -eq 1 -and $l.Contains($idL)) ("and the notice nobody took still alarms at takenAlarmSeconds (" + $why + "; " + $l + ")")
}
# The same after an UNKNOWN post that did land, then a refusal.
$HK = New-Home
$idK = Id-Of "no-spawn-gone" 0
$script:postSays = "unknown"
$null = Send-One $HK "no-spawn-gone" 0 0
$script:postSays = "held"
$s = Send-One $HK "no-spawn-gone" 0 30
$script:postSays = "accepted"
Check ($s.ok -eq $false -and @(Marks-Of $HK $idK).Count -eq 1) "UNKNOWN THEN REFUSED: the mark of a post that may have landed stays"
# CONTROLS: nothing was listed before, so a known refusal still leaves no mark, whatever the refusal.
foreach ($why in @("no-messenger", "no-device-id")) {
    $HN = New-Home
    if ($why -ceq "no-messenger") { $script:noMessenger = $true } else { $script:noDevice = $true }
    $s = Send-One $HN "no-analyst" 0 0
    $script:noMessenger = $false; $script:noDevice = $false
    Check ($s.ok -eq $false -and @(Marks-Of $HN (Id-Of "no-analyst" 0)).Count -eq 0 -and (Posts-Of (Id-Of "no-analyst" 0)) -eq 0) ("CONTROL: with nothing listed before, a refusal (" + $why + ") leaves no mark and posts nothing (" + $s.detail + ")")
}

Write-Host ""
Write-Host "--- GIVE-UP: held for good, and 7 days without a TAKEN, each with an ALARM ---" -ForegroundColor Cyan
$H7 = New-Home
$id7 = Id-Of "start-silent" 0
$null = Send-One $H7 "start-silent" 0 0
$script:stages[$id7] = "held"
$l = Tick $H7 20
Check ($l.Contains("ALARM:") -and $l.Contains("holds it for good") -and @(Marks-Of $H7 $id7).Count -eq 0) ("HELD: a notice the messenger holds for good alarms and is no longer watched (" + $l + ")")
$H8 = New-Home
$id8 = Id-Of "start-too-soon-over-cap" 0
$null = Send-One $H8 "start-too-soon-over-cap" 0 0
$null = Tick $H8 100
$l = Tick $H8 (604800 + 200)
Check ($l.Contains("NOT DELIVERED, given up") -and $l.Contains("ALARM:") -and @(Marks-Of $H8 $id8).Count -eq 0) ("GIVE-UP: a notice not taken in 7 days is given up with an ALARM (" + $l + ")")

Write-Host ""
Write-Host "--- ONE ID PER EVENT: the same event keeps its id, a later event of the same key has a new one ---" -ForegroundColor Cyan
$st = New-HordeAnalystState
Check ((Get-HordeAnalystTellGen -State $st -Key "no-answer") -eq 0) "a key never cleared is generation 0"
$st.told = [string[]]@("no-answer", "no-analyst")
Clear-HordeAnalystTold -State $st -Keys @("no-answer")
Check ((Get-HordeAnalystTellGen -State $st -Key "no-answer") -eq 1 -and (Get-HordeAnalystTellGen -State $st -Key "no-analyst") -eq 0 -and @($st.told) -ccontains "no-analyst" -and @($st.told) -cnotcontains "no-answer") "clearing a key ends its event: its generation rises, the others' do not"
Clear-HordeAnalystTold -State $st -Keys @("no-answer", "start-silent")
Check ((Get-HordeAnalystTellGen -State $st -Key "no-answer") -eq 2 -and (Get-HordeAnalystTellGen -State $st -Key "start-silent") -eq 1) "and again, each by itself"
Clear-HordeAnalystTold -State $st -Keys @("start-silent")
Check ((Get-HordeAnalystTellGen -State $st -Key "no-answer") -eq 2 -and (Get-HordeAnalystTellGen -State $st -Key "start-silent") -eq 2) "clearing one key keeps the generations of the keys not named"
$sp = Join-Path $work "state\supervisor.json"
Write-HordeAnalystState -Path $sp -State $st
$back = (Read-HordeAnalystState -Path $sp).value
Check ((Get-HordeAnalystTellGen -State $back -Key "no-answer") -eq 2 -and (Get-HordeAnalystTellGen -State $back -Key "start-silent") -eq 2) "the generations are in the state file and come back"
[System.IO.File]::WriteAllText($sp, '{"v":1,"phase":"none","sessionId":"","previousSessionId":"","startReason":"","startedAt":null,"lastRoundAt":null,"lastWakeAt":null,"contextAt":null,"findingsOffset":0,"contextTokens":-1,"transcriptLength":-1,"told":["no-answer"],"rounds":[]}', (New-Object System.Text.UTF8Encoding($false)))
$old2 = Read-HordeAnalystState -Path $sp
Check ($old2.state -ceq "known" -and (Get-HordeAnalystTellGen -State $old2.value -Key "no-answer") -eq 0) "a state file written before the generations existed is read, at generation 0"
Check ((Id-Of "no-answer" 0) -cne (Id-Of "no-answer" 1) -and (Id-Of "no-answer" 1) -cne (Id-Of "no-analyst" 1)) "a generation and a key each change the id"

Write-Host ""
Write-Host "--- THE PASS: the key is told when the post is accepted and watched; the lines reach the pass ---" -ForegroundColor Cyan
$script:now = $t0
$script:passHome = ""
$passTools = @{
    Now = { return $script:now }
    Identity = { return [pscustomobject]@{ records = (New-Object 'System.Collections.Generic.Dictionary[string,object]'); duplicates = @(); verifiedLive = (New-HordeKnown -Value @()) } }
    Length = { param($Path) return [long]-1 }
    Context = { param($Path) return (New-HordeAbsent -Note "none") }
    Post = $null; Notify = $null; Spawn = $null
    Tell = { param($Key, $Body, $Values, $Gen) return (Send-HordeAnalystWarchiefTaken -Key $Key -Body $Body -Values $Values -Gen ([long]$Gen) -HordeHome $script:passHome -Now $script:now -Seat $seat -TempRoot $notTemp) }
    TellTaken = { param($Values) if (-not (Test-HordeAnalystTellAwaiting -HordeHome $script:passHome)) { return @() }; return @(Invoke-HordeAnalystTellTakenTick -HordeHome $script:passHome -Now $script:now -AlarmSeconds ([double]$Values.takenAlarmSeconds) -AfterAlarmSeconds ([double]$Values.takenAfterAlarmSeconds)) }
}
function Pass-Of {
    param([string]$Home_, [double]$Sec)
    $script:passHome = $Home_
    $script:now = $t0.AddSeconds($Sec)
    $pol = Get-HordeAnalystPolicy -HordeHome $Home_
    if (-not $pol.ok) { throw $pol.reason }
    return (Invoke-HordeAnalystPass -Tools $passTools -Policy $pol -Folder (Get-HordeAnalystFolder -Values $pol.values -HordeHome $Home_))
}
function State-Of { param([string]$Home_) $pol = Get-HordeAnalystPolicy -HordeHome $Home_; return (Read-HordeAnalystState -Path (Join-Path (Get-HordeAnalystFolder -Values $pol.values -HordeHome $Home_) "supervisor.json")).value }
$HP = New-Home
$idP = Id-Of "no-analyst" 0
$r = Pass-Of $HP 0
$p = $r.lines -join " | "
Check ($r.problem -ceq "" -and @((State-Of $HP).told) -ccontains "no-analyst" -and (Posts-Of $idP) -eq 1 -and @(Marks-Of $HP $idP).Count -eq 1 -and $p.Contains("posted to the warchief: no-analyst") -and -not $p.Contains("told the warchief")) ("a first pass posts no-analyst, marks it, and says it is posted, not told (" + $p + ")")
$r = Pass-Of $HP 60
Check ((Posts-Of $idP) -eq 1 -and (Alarms-In ($r.lines -join " | ")) -eq 0) "the next pass posts nothing more and does not alarm yet"
$r = Pass-Of $HP 200
Check ((Alarms-In ($r.lines -join " | ")) -eq 1 -and @((State-Of $HP).told) -ccontains "no-analyst" -and (Posts-Of $idP) -eq 1) ("BUG: a notice the session never took raises an ALARM in the pass's lines, and the key stays told (" + ($r.lines -join " | ") + ")")
$r = Pass-Of $HP 210
Check ((Alarms-In ($r.lines -join " | ")) -eq 0) "and the next pass does not say it again"
$script:stages[$idP] = "seen"
$r = Pass-Of $HP 600
Check (($r.lines -join " | ").Contains("TAKEN: analyst supervisor notice " + $idP) -and @(Marks-Of $HP $idP).Count -eq 0 -and (Posts-Of $idP) -eq 1) ("and the TAKEN is among the pass's lines, with no second post (" + ($r.lines -join " | ") + ")")
# An unusable list: nothing is posted, the key is not told, the next pass tries again.
$HU = New-Home
New-Item -ItemType Directory -Path (Join-Path $HU "analyst") -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $HU "analyst\tell-taken.json"), "this is not an awaiting list")
$idU = Id-Of "no-analyst" 0
$r = Pass-Of $HU 0
Check ((Posts-Of $idU) -eq 0 -and @((State-Of $HU).told) -cnotcontains "no-analyst" -and ($r.lines -join " | ").Contains("cannot be awaited")) ("PASS: an unusable list means no post and the key not told, with the reason in the lines (" + ($r.lines -join " | ") + ")")
Remove-Item -LiteralPath (Join-Path $HU "analyst\tell-taken.json") -Force
$r = Pass-Of $HU 60
Check ((Posts-Of $idU) -eq 1 -and @((State-Of $HU).told) -ccontains "no-analyst") "and once it is usable the next pass posts and tells"
# A look that throws costs the look, not the pass.
$passTools2 = @{}
foreach ($k in $passTools.Keys) { $passTools2[$k] = $passTools[$k] }
$passTools2["TellTaken"] = { param($Values) throw "the look fell over" }
$HB = New-Home
$script:passHome = $HB
try { $pol = Get-HordeAnalystPolicy -HordeHome $HB; $boom = Invoke-HordeAnalystPass -Tools $passTools2 -Policy $pol -Folder (Get-HordeAnalystFolder -Values $pol.values -HordeHome $HB) }
catch { $boom = [pscustomobject]@{ problem = "IT THREW: " + $_.Exception.Message; lines = @() } }
Check ($boom.problem -ceq "" -and ($boom.lines -join " | ").Contains("the awaiting notices could not be asked: the look fell over")) "a look that throws costs the look, not the pass"
# The lines reach the log even when the state cannot be read.
$HR = New-Home
$null = Send-One $HR "no-analyst" 0 0
$pol = Get-HordeAnalystPolicy -HordeHome $HR
$fold = Get-HordeAnalystFolder -Values $pol.values -HordeHome $HR
New-Item -ItemType Directory -Path $fold -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $fold "supervisor.json"), "not json")
$script:passHome = $HR
$script:now = $t0.AddSeconds(500)
$r = Invoke-HordeAnalystPass -Tools $passTools -Policy $pol -Folder $fold
Check ($r.problem -ne "" -and (Alarms-In ($r.lines -join " | ")) -eq 1) ("an unreadable state does not hide an ALARM (" + ($r.lines -join " | ") + ")")

Write-Host ""
Write-Host "--- A LIST THAT CANNOT BE WRITTEN: one ALARM and one TAKEN for a notice, across looks that are new calls (T-0391 round 2, item 4) ---" -ForegroundColor Cyan
# The cadence file keeps what the engine remembers (alarmed-*, delivered-*) beside when each mark was asked, so a list that cannot be written
# does not make every look say the same ALARM and the same TAKEN again. Each Tick here is a new call, as each pass of a restarted supervisor is.
$HW = New-Home
$idW = Id-Of "no-analyst" 0
$null = Send-One $HW "no-analyst" 0 0
$listW = Join-Path $HW "analyst\tell-taken.json"
(Get-Item -LiteralPath $listW).IsReadOnly = $true
try {
    $said = New-Object System.Collections.ArrayList
    foreach ($sec in @(100, 160, 220, 280, 340)) { [void]$said.Add((Tick $HW $sec)) }
    $all = $said -join " | "
    Check ((Alarms-In $all) -eq 1) ("a list that cannot be written: ONE ALARM for the notice across five looks, not one at each (" + (Alarms-In $all) + ")")
    Check ($all.Contains("could not be written")) "and the failed write is still said, so a person can see the list is stuck"
    Check ([System.IO.File]::Exists((Join-Path $HW "analyst\tell-taken-asked.txt")) -and ([System.IO.File]::ReadAllText((Join-Path $HW "analyst\tell-taken-asked.txt"))).Contains("alarmed-")) "the alarm is kept in the analyst's own asked file, which the list's being stuck does not touch"
    $script:stages[$idW] = "handed-over"
    $said2 = New-Object System.Collections.ArrayList
    foreach ($sec in @(400, 460, 520)) { [void]$said2.Add((Tick $HW $sec)) }
    $all2 = $said2 -join " | "
    Check (([regex]::Matches($all2, "TAKEN: analyst supervisor notice")).Count -eq 1) ("and ONE TAKEN across three looks while the mark cannot be taken off (" + ([regex]::Matches($all2, "TAKEN: analyst supervisor notice")).Count + ")")
    Check (@(Marks-Of $HW $idW).Count -eq 1) "CONTROL: the mark is still there, as the list could not be written"
} finally { (Get-Item -LiteralPath $listW).IsReadOnly = $false }
$l = Tick $HW 580
Check (@(Marks-Of $HW $idW).Count -eq 0 -and -not $l.Contains("TAKEN: analyst supervisor notice")) ("once the list can be written the mark goes, and the TAKEN is not said a second time (" + $l + ")")
Check (-not [System.IO.File]::Exists((Join-Path $HW "analyst\tell-taken-asked.txt"))) "and the asked file forgets a notice that is over, its alarm and its taken with it"
# CONTROL: a writable list still says one ALARM and one TAKEN (the memory is no new silence).
$HW2 = New-Home
$idW2 = Id-Of "start-silent" 0
$null = Send-One $HW2 "start-silent" 0 0
$a1 = Tick $HW2 100
$script:stages[$idW2] = "seen"
$a2 = Tick $HW2 160
Check ((Alarms-In $a1) -eq 1 -and $a2.Contains("TAKEN: analyst supervisor notice " + $idW2) -and @(Marks-Of $HW2 $idW2).Count -eq 0) "CONTROL: with a writable list the ALARM and the TAKEN are each said once"

Write-Host ""
Write-Host "--- A REFUSED OR UNKNOWN TELL IS RETRIED ON THE NEXT PASS, FOR EVERY KEY, UNDER THE SAME ID (T-0391 round 2, item 3) ---" -ForegroundColor Cyan
# started-gone and spawn-failed are told in the pass that starts a session, and no-answer in the pass that finds a late round; none of them is
# decided again next pass, so a tell the messenger refused was lost for good. They are kept in the state (tellRetry) and told again.
$sidR = "11111111-2222-4333-8444-555555555555"
$spawnFile = Join-Path $work "spawn-stand-in.ps1"
[System.IO.File]::WriteAllText($spawnFile, "# stand-in")
$script:spawns = 0
$script:spawnOk = $true
$passToolsR = @{}
foreach ($k in $passTools.Keys) { $passToolsR[$k] = $passTools[$k] }
$passToolsR["Spawn"] = { param($Script, $Handover, $Reason, $Values) $script:spawns++; return [pscustomobject]@{ ok = $script:spawnOk; detail = "the stand-in spawner says no" } }
function Pass-R {
    param([string]$Home_, [double]$Sec)
    $script:passHome = $Home_
    $script:now = $t0.AddSeconds($Sec)
    $pol = Get-HordeAnalystPolicy -HordeHome $Home_
    if (-not $pol.ok) { throw $pol.reason }
    return (Invoke-HordeAnalystPass -Tools $passToolsR -Policy $pol -Folder (Get-HordeAnalystFolder -Values $pol.values -HordeHome $Home_))
}
function New-HomeR {
    # A home whose settings name a spawn script, with a state of the given shape.
    param([string]$Phase, $Rounds = @())
    $h = New-Home
    [System.IO.File]::WriteAllText((Join-Path $h "settings\analyst.json"), ('{"schemaVersion":1,"settings":{"spawnScript":' + (ConvertTo-Json -InputObject $spawnFile) + '}}'))
    $pol = Get-HordeAnalystPolicy -HordeHome $h
    $st = New-HordeAnalystState
    $st.phase = $Phase
    if ($Phase -ceq "running") { $st.sessionId = $sidR }
    $st.rounds = @($Rounds)
    Write-HordeAnalystState -Path (Join-Path (Get-HordeAnalystFolder -Values $pol.values -HordeHome $h) "supervisor.json") -State $st
    $script:spawns = 0; $script:spawnOk = $true
    return $h
}
function Retry-Of { param([string]$Home_) return @((State-Of $Home_).tellRetry) }
function Body-Of { param([string]$Id) return ("" + (@($script:posts.ToArray() | Where-Object { "$($_.messageId)" -ceq $Id })[0]).body) }

# started-gone: the session is gone, a fresh one is started, and the messenger is not there to be told.
$HG = New-HomeR "running"
# A start declares the old event over (Clear-HordeAnalystTold), so the first start of a key is generation 1.
$idG = Id-Of "started-gone" 1
$script:noMessenger = $true
$r = Pass-R $HG 0
Check ($script:spawns -eq 1 -and (Posts-Of $idG) -eq 0 -and @((State-Of $HG).told) -cnotcontains "started-gone" -and (Retry-Of $HG) -ccontains "started-gone=") ("started-gone refused: the key is not told and is kept to be told again (" + ($r.lines -join " | ") + ")")
$script:noMessenger = $false
$r = Pass-R $HG 60
Check ((Posts-Of $idG) -eq 1 -and @((State-Of $HG).told) -ccontains "started-gone" -and (Retry-Of $HG).Count -eq 0 -and $script:spawns -eq 1 -and @(Marks-Of $HG $idG).Count -eq 1) ("started-gone: the next pass tells it, once, under the same id, with no second start (" + ($r.lines -join " | ") + ")")
$null = Pass-R $HG 120
Check ((Posts-Of $idG) -eq 1 -and (Retry-Of $HG).Count -eq 0) "and the pass after that tells nothing more"

# spawn-failed, and an UNKNOWN result this time (the post may have landed: the retry is the same id, one mark).
$HF = New-HomeR "running"
$idF = Id-Of "spawn-failed" 1
$script:spawnOk = $false
$script:postSays = "unknown"
$null = Pass-R $HF 0
Check ($script:spawns -eq 1 -and @((State-Of $HF).told) -cnotcontains "spawn-failed" -and (Retry-Of $HF) -ccontains "spawn-failed=" -and @(Marks-Of $HF $idF).Count -eq 1) "spawn-failed, result unknown: not told, kept to be told again, its mark kept"
$script:postSays = "accepted"
$null = Pass-R $HF 60
Check (@((State-Of $HF).told) -ccontains "spawn-failed" -and (Retry-Of $HF).Count -eq 0 -and @($script:posts | Where-Object { "$($_.messageId)" -cne $idF }).Count -eq 0 -and @(Marks-Of $HF $idF).Count -eq 1 -and $script:spawns -eq 1) "spawn-failed: the next pass tells it under the same id, with one mark and no second start"
$script:spawnOk = $true

# no-answer: told once for a run of late rounds; the round is marked alerted before the tell, so it was lost until the next late round.
$lateRound = [pscustomobject]@{ id = "20261013T110000Z-r"; kind = "round"; at = $t0.AddMinutes(-60); sessionId = $sidR; alerted = $false; woken = "yes" }
$HN3 = New-HomeR "none" @($lateRound)
$idN = Id-Of "no-answer" 0
$script:noMessenger = $true
$null = Pass-R $HN3 0
Check (@((State-Of $HN3).told) -cnotcontains "no-answer" -and (Retry-Of $HN3) -ccontains "no-answer=20261013T110000Z-r" -and (Posts-Of $idN) -eq 0 -and @((State-Of $HN3).rounds)[0].alerted -eq $true) "no-answer refused: the round is alerted, the key not told, and the tell is kept with its round"
$script:noMessenger = $false
$r = Pass-R $HN3 60
Check ((Posts-Of $idN) -eq 1 -and @((State-Of $HN3).told) -ccontains "no-answer" -and (Retry-Of $HN3) -cnotcontains "no-answer=20261013T110000Z-r" -and (Body-Of $idN).Contains("Round: 20261013T110000Z-r")) ("no-answer: the next pass tells it, once, with the round it was kept with (" + ($r.lines -join " | ") + ")")
$null = Pass-R $HN3 120
Check ((Posts-Of $idN) -eq 1) "and no further pass tells it again"

# A pending tell for an event this very pass declares over is not told: the fresh session has written its handover, so "spawn-failed" is over.
$HS = New-HomeR "starting"
$polS = Get-HordeAnalystPolicy -HordeHome $HS
$foldS = Get-HordeAnalystFolder -Values $polS.values -HordeHome $HS
$stS = (Read-HordeAnalystState -Path (Join-Path $foldS "supervisor.json")).value
$stS.startedAt = $t0.AddMinutes(-2)
$stS.tellRetry = [string[]]@("spawn-failed=")
Write-HordeAnalystState -Path (Join-Path $foldS "supervisor.json") -State $stS
[System.IO.File]::WriteAllText((Join-Path $foldS "handover.json"), ('{"v":1,"sessionId":"' + $sidR + '","writtenAt":"' + $t0.ToString("o") + '","round":"","holds":"","told":"","followUps":""}'), (New-Object System.Text.UTF8Encoding($false)))
$null = Pass-R $HS 0
Check ((State-Of $HS).sessionId -ceq $sidR -and (Posts-Of (Id-Of "spawn-failed" 0)) -eq 0 -and (Posts-Of (Id-Of "spawn-failed" 1)) -eq 0 -and (Retry-Of $HS).Count -eq 0) "a pending tell for an event the pass declares over (a fresh session adopted) is dropped, not told"

# A key whose condition is over is not retried: adoption clears spawn-failed and its pending tell with it.
$stC = New-HordeAnalystState
$stC.tellRetry = [string[]]@("spawn-failed=", "started-gone=", "no-answer=20261013T110000Z-r")
Clear-HordeAnalystTold -State $stC -Keys @("spawn-failed", "no-answer")
Check (@($stC.tellRetry).Count -eq 1 -and @($stC.tellRetry)[0] -ceq "started-gone=") "a key whose condition is over takes its pending tell with it"
$sp3 = Join-Path $work "state3\supervisor.json"
$stC.tellRetry = [string[]]@("started-gone=", "no-answer=20261013T110000Z-r")
Write-HordeAnalystState -Path $sp3 -State $stC
$back3 = (Read-HordeAnalystState -Path $sp3).value
Check (@($back3.tellRetry).Count -eq 2 -and @($back3.tellRetry) -ccontains "no-answer=20261013T110000Z-r") "the pending tells are in the state file and come back"
[System.IO.File]::WriteAllText($sp3, '{"v":1,"phase":"none","sessionId":"","previousSessionId":"","startReason":"","startedAt":null,"lastRoundAt":null,"lastWakeAt":null,"contextAt":null,"findingsOffset":0,"contextTokens":-1,"transcriptLength":-1,"told":[],"rounds":[]}', (New-Object System.Text.UTF8Encoding($false)))
$old3 = Read-HordeAnalystState -Path $sp3
Check ($old3.state -ceq "known" -and @($old3.value.tellRetry).Count -eq 0) "a state file written before the pending tells existed is read, with none"
[System.IO.File]::WriteAllText($sp3, '{"v":1,"phase":"none","sessionId":"","previousSessionId":"","startReason":"","startedAt":null,"lastRoundAt":null,"lastWakeAt":null,"contextAt":null,"findingsOffset":0,"contextTokens":-1,"transcriptLength":-1,"told":[],"tellRetry":["not a row","started-gone="],"rounds":[]}', (New-Object System.Text.UTF8Encoding($false)))
$bad3 = Read-HordeAnalystState -Path $sp3
Check ($bad3.state -ceq "known" -and @($bad3.value.tellRetry).Count -eq 1 -and @($bad3.value.tellRetry)[0] -ceq "started-gone=") "and a row that is not a row is left out when it is read"

Write-Host ""
Write-Host "--- A LATER EVENT OF THE SAME KEY IS HEARD; A RESTART IS NOT HEARD TWICE (through the real clear and tell) ---" -ForegroundColor Cyan
$HE = New-Home
$pol = Get-HordeAnalystPolicy -HordeHome $HE
$stE = New-HordeAnalystState
$tools = @{ Tell = $passTools["Tell"] }
$script:passHome = $HE
$script:now = $t0
$null = Send-HordeAnalystTell -State $stE -Key "no-answer" -Tools $tools -Values $pol.values
$idE0 = Id-Of "no-answer" 0
Check (@($stE.told) -ccontains "no-answer" -and (Posts-Of $idE0) -eq 1) "event one of no-answer is posted under generation 0"
# The teller's own lines (a full list given up, an already-posted copy) are part of the journal line the pass says.
$toolsL = @{ Tell = { param($Key, $Body, $Values, $Gen) return [pscustomobject]@{ ok = $true; detail = ""; lines = @("ALARM: the teller's own line") } } }
$stL = New-HordeAnalystState
$jl = Send-HordeAnalystTell -State $stL -Key "spawn-failed" -Tools $toolsL -Values $pol.values
Check ($jl.Contains("posted to the warchief: spawn-failed") -and $jl.Contains("ALARM: the teller's own line")) ("the teller's own lines are in the journal line (" + $jl + ")")
$script:stages[$idE0] = "seen"
$null = Tick $HE 30
Check (@(Marks-Of $HE $idE0).Count -eq 0) "and taken"
$null = Send-HordeAnalystTell -State $stE -Key "no-answer" -Tools $tools -Values $pol.values
Check ((Posts-Of $idE0) -eq 1) "the same event is not posted again"
# A restart: the state was not written, so the clear happens again from the same state.
$snapshot = New-HordeAnalystState; $snapshot.told = [string[]]@("no-answer")
Clear-HordeAnalystTold -State $stE -Keys @("no-answer")
$null = Send-HordeAnalystTell -State $stE -Key "no-answer" -Tools $tools -Values $pol.values
$idE1 = Id-Of "no-answer" 1
Check ((Posts-Of $idE1) -eq 1 -and @($stE.told) -ccontains "no-answer") "event two is a new notice with a new id, so a messenger that keeps one message per id still takes it"
Clear-HordeAnalystTold -State $snapshot -Keys @("no-answer")
$null = Send-HordeAnalystTell -State $snapshot -Key "no-answer" -Tools $tools -Values $pol.values
Check ((Posts-Of $idE1) -eq 2 -and @($script:posts | Where-Object { "$($_.messageId)" -ceq $idE1 }).Count -eq 2 -and @(Marks-Of $HE $idE1).Count -eq 1) "a restart before the state was written clears to the SAME generation: the same id, one mark, nothing new for the messenger"

Write-Host ""
Write-Host "--- a test's home still tells nobody; the quiet pass pays for nothing ---" -ForegroundColor Cyan
$tempTell = Send-HordeAnalystWarchiefTaken -Key "no-analyst" -Body "x" -Values $vals -Gen 0 -HordeHome $H1 -Seat { throw "the seat must not be read for a home under the temp folder" }
Check ($tempTell.ok -eq $false -and $tempTell.detail.Contains("a test's") -and @($tempTell.lines).Count -eq 0) "A TEST'S HOME TELLS NOBODY: refused before any messenger, seat or list is looked for"
Check (-not (Test-HordeAnalystTellAwaiting -HordeHome (New-Home))) "a home with no awaiting list has nothing to ask about"
$HA = New-Home
$idA = Id-Of "no-analyst" 0
$null = Send-One $HA "no-analyst" 0 0
Check (Test-HordeAnalystTellAwaiting -HordeHome $HA) "and a home with a mark on the list has"
$script:stages[$idA] = "handed-over"
$null = Tick $HA 0
$listPath = Join-Path $HA "analyst\tell-taken.json"
Check ([System.IO.File]::Exists($listPath) -and @(Marks-Of $HA $idA).Count -eq 0) "CONTROL: once the mark is taken off the file is still there, with nothing on it"
Check (-not (Test-HordeAnalystTellAwaiting -HordeHome $HA)) "and then nothing is awaiting: a quiet pass asks no messenger (the file's being there says nothing)"
[System.IO.File]::WriteAllText($listPath, "not json")
Check (Test-HordeAnalystTellAwaiting -HordeHome $HA) "a list that cannot be read counts as awaiting, so the look is made and says why it cannot be"

Write-Host ""
Write-Host "--- the founder's notice and the relay watch's tell are as they were ---" -ForegroundColor Cyan
$cmdText = [System.IO.File]::ReadAllText((Join-Path $root "cli\commands\analyst.ps1"))
Check ($cmdText.Contains('$tools["Tell"] = { param($Key, $Body, $Values, $Gen) return (Send-HordeAnalystWarchiefTaken') -and $cmdText.Contains('$tools["TellTaken"]')) "the command's Tell tool is the marked one, and a TellTaken tool is beside it"
Check ($cmdText.Contains('$relayTools["Tell"] = { param($Body) return (Send-HordeAnalystWarchief -Key "relay"') -and $cmdText.Contains('$tools["Notify"] = { param($Line) return (Send-HordeAnalystFounderNotice')) "the relay watch tells through the unmarked teller, and the founder's notice is unchanged"

Write-Host ""
Write-Host "--- the REAL Tell and TellTaken blocks of cli/commands/analyst.ps1, cut out with the parser and run (T-0391 round 2, item 5) ---" -ForegroundColor Cyan
function Get-CommandBlock {
    # The right-hand side of $tools["<Name>"] = { ... } in the command file: the block as the file has it.
    param([string]$Name)
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root "cli\commands\analyst.ps1"), [ref]$null, [ref]$null)
    foreach ($a in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true))) {
        if ($a.Left.Extent.Text -ceq ('$tools["' + $Name + '"]') -and $a.Right.Expression -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { return $a.Right.Expression.ScriptBlock.GetScriptBlock() }
    }
    return $null
}
$blkTell = Get-CommandBlock "Tell"
$blkLook = Get-CommandBlock "TellTaken"
Check ($null -ne $blkTell -and $null -ne $blkLook) "CONTROL: the command file has both blocks, and the parser cut them out"
# The blocks read $hordeHome as the command has it. Its seat is the stand-in's; the folder the guard of a test's home looks at is pointed
# elsewhere for the length of these checks, so the real teller goes past the guard to the stand-in messenger.
# (Not $seat: the callee would read the teller's own -Seat parameter, which is null here.)
$script:standInSeat = $seat
function Get-HordeRoleSeat { param([string]$Role) return (& $script:standInSeat) }
$keepTemp = $env:TEMP; $keepTmp = $env:TMP
$env:TEMP = $notTemp; $env:TMP = $notTemp
try {
    $hordeHome = New-Home
    # 1. THE GENERATION REACHES THE ID: a block that drops -Gen tells every event as generation 0.
    $r = & $blkTell "no-analyst" "FLEET ANALYST SUPERVISOR`nwords" $vals 3
    Check ($r.ok -eq $true -and (Posts-Of (Id-Of "no-analyst" 3)) -eq 1 -and @(Marks-Of $hordeHome (Id-Of "no-analyst" 3)).Count -eq 1 -and (Posts-Of (Id-Of "no-analyst" 0)) -eq 0) ("the real Tell block: generation 3 is the id that is posted and marked (" + $r.detail + ")")
    $r = & $blkTell "no-analyst" "FLEET ANALYST SUPERVISOR`nwords" $vals 4
    Check ($r.ok -eq $true -and (Posts-Of (Id-Of "no-analyst" 4)) -eq 1 -and @(Marks-Of $hordeHome (Id-Of "no-analyst" 4)).Count -eq 1) "and generation 4 is a new notice with its own id"
    # 2. THE TWO SETTINGS REACH THE LOOK. A mark 30 s old, takenAlarmSeconds 10: it alarms (the default, 90, would not).
    $hordeHome = New-Home
    $tiny = [pscustomobject]@{ fromLabel = "AS"; tellWarchief = $true; takenAlarmSeconds = 10; takenAfterAlarmSeconds = 10 }
    $idS = Id-Of "no-analyst" 0
    $null = Send-HordeAnalystWarchiefTaken -Key "no-analyst" -Body "x" -Values $tiny -Gen 0 -HordeHome $hordeHome -Now ([datetime]::UtcNow.AddSeconds(-30)) -Seat $seat -TempRoot $notTemp
    $out = @(& $blkLook $tiny)
    Check ((Alarms-In ($out -join " | ")) -eq 1 -and @(Marks-Of $hordeHome $idS | Where-Object { $_.alarmed }).Count -eq 1) ("the real TellTaken block: takenAlarmSeconds reaches the look - a notice 30 s old alarms at 10 s (" + ($out -join " | ") + ")")
    # takenAfterAlarmSeconds: the alarmed mark was last asked 60 s ago; at a cadence of 10 s it is asked again (the default, 300, would not).
    $nowMs = Get-HordeDecisionNoticeTakenNowMs -Now ([datetime]::UtcNow)
    $okW = Write-HordeAnalystTellAsked -HordeHome $hordeHome -Table @{ ($idS.Replace("-", "")) = [long]($nowMs - 60000) }
    $asks = [int]$script:askedIds[$idS]
    $out = @(& $blkLook $tiny)
    Check ($okW -eq $true -and [int]$script:askedIds[$idS] -eq ($asks + 1)) ("and takenAfterAlarmSeconds reaches it - an alarmed notice last asked 60 s ago is asked again at 10 s (asked " + $script:askedIds[$idS] + " after " + $asks + ")")
    # A REAL MARK REACHES A REAL OUTCOME: the notice is taken, and the real look says so and takes the mark off.
    $script:stages[$idS] = "handed-over"
    $null = Write-HordeAnalystTellAsked -HordeHome $hordeHome -Table @{ ($idS.Replace("-", "")) = [long]((Get-HordeDecisionNoticeTakenNowMs -Now ([datetime]::UtcNow)) - 60000) }
    $out = @(& $blkLook $tiny)
    Check (($out -join " | ").Contains("TAKEN: analyst supervisor notice " + $idS) -and @(Marks-Of $hordeHome $idS).Count -eq 0) ("and a notice the session took is said TAKEN and its mark is off (" + ($out -join " | ") + ")")
    # No mark: the look asks nothing.
    $hordeHome = New-Home
    $out = @(& $blkLook $tiny)
    Check ($out.Count -eq 0 -and $script:askedIds.Count -eq 0) "and with nothing awaiting the real look says nothing and asks no messenger"
} finally { $env:TEMP = $keepTemp; $env:TMP = $keepTmp }

Write-Host ""
Write-Host "--- the load comes from the command itself, and its two tools run in one process in either order (a fresh process each) ---" -ForegroundColor Cyan
$shell = (Get-Process -Id $PID).Path
$loader = Join-Path $fx "run-command-blocks.ps1"
foreach ($order in @("TellTaken,Tell", "Tell,TellTaken")) {
    $got = @(& $shell -NoProfile -File $loader -Root $root -Order $order -Home_ (Join-Path $work ("loader-" + $order.Replace(",", "-"))) -TempAway $notTemp)
    $said = $got -join " | "
    Check ($said -match 'LOADED [^|]*wezfleet' -and -not $said.Contains("THREW")) ($order + ": the command's own statement loaded the messenger port and the fleet messenger, and no block threw (" + $said + ")")
    Check ($said -match "Tell ok=False detail=the warchief's session cannot be told" -and $said -match 'TellTaken lines=[^|]*cannot be read') ($order + ": the real Tell went past the guard to the warchief's seat, and the real look reached the awaiting list (" + $said + ")")
}
}
finally {
    $env:HORDE_HOME = $keepHome
    $env:WEZFLEET_ROOT = $keepFleet
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-HordeSuite -Success "an analyst supervisor notice is told only while it is watched until the warchief's own TAKEN, alarms once when it is not taken in time, is never dropped, a later event has a new id, and its lines reach the pass"
