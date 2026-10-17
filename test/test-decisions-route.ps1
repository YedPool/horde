# DOES A FOUNDER'S ANSWER REACH THE ORC THAT ASKED, BY CODE, EXACTLY ONCE - AND IS AN ANSWERED QUESTION
# CLOSED, OR FLAGGED AND ITS ASKER REMINDED ONCE?
#
# decisions/Route.ps1, the rules it rests on (decisions/Rules.ps1, THE ANSWER GOES TO THE ONE WHO ASKED)
# and the operations route and ack, held without any real messenger, any real session or real mail:
#   - WHO ASKED is read from askedBy and never guessed: "Orc C" is Orc C; M or Thrall is the warchief;
#     anything else names nobody, and the answer goes to the warchief with that said in the record.
#   - ROUTED FROM EVERY ROUTE: his answer typed in the window, from his phone, and recorded by the
#     warchief from chat each reach the asking Orc's seat with the question's number, its title, his
#     words, and how they arrived; and one line reaches the analyst.
#   - EXACTLY ONCE: a second pass, a router with no memory (a restart), an answer the relay applies
#     again, and a crash between the messenger taking the notice and its record being written all
#     leave one message per answer; a NEW answer is routed. Each send is a record a later look can show.
#   - UNRESOLVABLE: askedBy that names nobody, an Orc whose seat cannot be had, and no warchief either
#     (nothing sent, nothing recorded, sent once the seat is back).
#   - THE HOUR: the list flags an answered question still open after unclosedMinutes, on a clock this
#     suite moves; its asker is reminded once, and only for an answer that was routed.
#   - ACK: the asking Orc closes it as the closer; a closed question, an unanswered one, another Orc,
#     a replaced answer and a question asked again are refused in words; the command line proves which
#     Orc runs it.
#
# NOTHING OF THIS MACHINE IS READ OR WRITTEN. The home is a folder of this suite's own, every messenger
# is pinned in it, the fleet's registry is a folder that does not exist, and the only messenger left is
# a stand-in registered here; the seats and the analyst's mail are stand-ins handed to the pass.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }

$work = Join-Path $env:TEMP ("horde-decisions-route-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$hordeHome = Join-Path $work "home"
$keepHome = $env:HORDE_HOME
$env:HORDE_HOME = $hordeHome
. (Join-Path $root "test\lib\MessengerPins.ps1")
$pins = @(Set-HordeTestMessengerPins -Root $root -HordeHome $hordeHome)
$keepFleet = $env:WEZFLEET_ROOT
$env:WEZFLEET_ROOT = Join-Path $work "no-fleet"
. (Join-Path $root "decisions\Route.ps1")
. (Join-Path $root "decisions\Console.ps1")
# NO REAL MESSENGER IS EVER ASKED. Route.ps1 loads every messenger folder; all are dropped, and the one
# left is this suite's stand-in. The control shows the loading did happen.
$loaded = @(Get-HordeMessengerNames)
foreach ($n in $loaded) { [void]$script:HordeMessengers.Remove($n) }
Check ($loaded.Count -ge 2) ("CONTROL: the router loads every messenger folder (" + ($loaded -join ", ") + ")")
Check ($pins.Count -ge 1) ("PIN: every messenger that has a pin is pinned in this suite's home (" + ($pins -join ", ") + ")")

# THE STAND-IN MESSENGER: every post, one record per messageId (idempotent, as declared), and a stage
# this suite chooses.
$script:posts = New-Object System.Collections.ArrayList
$script:taken = @{}
$script:postSays = "accepted"
$stubPost = {
    param($Message)
    [void]$script:posts.Add($Message)
    if ($script:postSays -ceq "unknown") { return (New-HordeUnknown -Reason "the stand-in could not tell") }
    $id = "$($Message.messageId)"
    if (-not $script:taken.ContainsKey($id)) { $script:taken[$id] = $Message }
    $reason = $(if ($script:postSays -ceq "held") { "the stand-in held it" } else { "woken" })
    return (New-HordeKnown -Value ([pscustomobject]@{ messageId = $id; stage = $script:postSays; at = [datetime]::UtcNow; reason = $reason; woken = $true }) -ObservedAt ([datetime]::UtcNow))
}
$stubStatus = { param($MessageId) return (New-HordeAbsent -Note "the stand-in keeps no status") }
$null = Register-HordeMessenger -Folder (Join-Path $here "fixtures\decisions-notify\doorbell") -Post $stubPost -Status $stubStatus

# THE SEATS: role and label to a session, as this suite says; a seat not named is absent.
$script:seats = @{ "orc C" = "orc-c-session"; "orc D" = "orc-d-session"; "warchief" = "warchief-session-1" }
$seat = {
    param([string]$Role, [string]$Label)
    $key = $(if ($Label -ceq "") { $Role } else { $Role + " " + $Label })
    if ($script:seats.ContainsKey($key)) { return (New-HordeKnown -Value ([pscustomobject]@{ sessionId = $script:seats[$key]; pane = "1"; instance = "t1" })) }
    if ($key -ceq "orc E") { return (New-HordeUnknown -Reason "two live sessions each wear the label E with the role orc") }
    return (New-HordeAbsent -Note ("no live session's record wears " + $key))
}
# THE ANALYST'S MAIL: every line, and the token each was found by.
$script:analystLines = New-Object System.Collections.ArrayList
$analyst = { param([string]$Text, [string]$Token, $Since) [void]$script:analystLines.Add([pscustomobject]@{ text = $Text; token = $Token }); return [pscustomobject]@{ ok = $true; said = ("left for the analyst as stand-in-" + $script:analystLines.Count) } }

# THE CLOCK this suite moves. Records are written at the clock's time, so the hour is the suite's own.
$script:now = [datetime]::UtcNow.AddMinutes(-600)
$clock = { return $script:now }
function Advance { param([double]$Minutes) $script:now = $script:now.AddMinutes($Minutes) }
function New-Id { return [guid]::NewGuid().ToString("N") }
function Op { param([string]$Operation, $Request) return (Invoke-HordeDecision -Operation $Operation -Request $Request -Now $script:now) }
function Add-Question { param([string]$AskedBy, [string]$Title, [string[]]$Parts = @())
    $q = @{ title = $Title; kind = "yes-no"; whatItIs = "A step is ready."; group = "A group"; askedBy = $AskedBy; waiting = @($AskedBy) }
    if ($Parts.Count -gt 0) { $q["kind"] = "parts"; $q["parts"] = $Parts }
    $a = Op "add" @{ id = (New-Id); actor = "warchief"; question = $q }
    if ($a.state -cne "known" -or $a.value.outcome -cne "done") { throw ("the question was not added: " + $a.reason) }
    return [int]$a.value.number }
function Say { param([int]$Number, [string]$Text, [string]$Route = "window", [string]$Id = "", [string]$Part = "")
    if ($Id -eq "") { $Id = New-Id }
    $actor = $(if ($Route -ceq "chat-recorded") { "warchief" } else { "founder" })
    $r = @{ id = $Id; actor = $actor; number = $Number; speaker = "founder"; route = $Route; text = $Text }
    if ($Route -cne "chat-recorded") { $r["wordingVersion"] = 1 }
    if ($Route -ceq "phone") { $r["evidence"] = ("{0:x64}" -f [long]($script:posts.Count + 77)); $r["signedBy"] = "0123456789abcdef0123456789abcdef" }
    if ($Part -ne "") { $r["part"] = $Part }
    $a = Op "say" $r
    if ($a.state -cne "known" -or @("done", "replayed") -cnotcontains $a.value.outcome) { throw ("the founder's words were not saved: " + $a.reason + " " + (@($a.value.findings) -join "; ")) }
    return [long]$a.value.sequence }
function Reply { param([int]$Number, [string]$Text)
    $a = Op "say" @{ id = (New-Id); actor = "warchief"; number = $Number; speaker = "warchief"; route = "command"; text = $Text }
    if ($a.state -cne "known" -or $a.value.outcome -cne "done") { throw ("the warchief's words were not saved: " + $a.reason + " " + (@($a.value.findings) -join "; ")) } }
function Pass { param([int]$Grace = 300) return (Invoke-HordeDecisionRoutePass -Clock $clock -Seat $seat -Analyst $analyst -HordeHome $hordeHome -SeatGraceSeconds $Grace) }
function Show { param([int]$Number) return (Op "show" @{ number = $Number }).value.question }
function Routes { param([int]$Number) $q = Show $Number; if ($null -eq $q.PSObject.Properties["routes"]) { return @() }; return @($q.routes) }
function PostsTo { param([string]$Session) return @($script:posts | Where-Object { "$($_.sessionId)" -ceq $Session }) }
function Ack { param([int]$Number, [string]$By, $Answer = $null, [string]$Id = "")
    if ($Id -eq "") { $Id = New-Id }
    $r = @{ id = $Id; actor = "orc"; number = $Number; by = $By }
    if ($null -ne $Answer) { $r["answer"] = [long]$Answer }
    return (Op "ack" $r) }

try {

Write-Host ""
Write-Host "--- who asked is read from askedBy, never guessed ---" -ForegroundColor Cyan
$c = Get-HordeDecisionAsker -AskedBy "Orc C"
Check ($c.seat -ceq "orc" -and $c.label -ceq "C" -and $c.shown -ceq "Orc C") "'Orc C' is Orc C's seat"
foreach ($w in @("M (Thrall)", "Thrall", "M", "M (Thrall), for the fleet-tool session (now closed)")) { Check ((Get-HordeDecisionAsker -AskedBy $w).seat -ceq "warchief") ("'" + $w + "' is the warchief, who asked for itself") }
foreach ($odd in @("orc c", "Orc-C", "C", "Orc CC", "Orc C ", "", "Mallory", "Orc 3")) {
    $o = Get-HordeDecisionAsker -AskedBy $odd
    Check ($o.seat -ceq "" -and $o.why -like "its askedBy, '*', is neither 'Orc' and one capital letter nor the warchief (M or Thrall), so it names no seat an answer can be sent to") ("'" + $odd + "' names nobody, and says so")
}

Write-Host ""
Write-Host "--- an answer from EACH route reaches the Orc that asked, once, with its number, title, words and route ---" -ForegroundColor Cyan
$qWindow = Add-Question "Orc C" "Should the window step go ahead?"
$qPhone = Add-Question "Orc C" "Should the phone step go ahead?"
$qChat = Add-Question "Orc D" "Should the chat step go ahead?"
Advance 1
$sWindow = Say $qWindow "Yes, typed in the window."
$sPhone = Say $qPhone "Yes, from my phone." -Route "phone"
$sChat = Say $qChat ("Yes, said in chat." + "`n" + "And a second line.") -Route "chat-recorded"
Advance 1
$p = Pass
Check ($p.outcome -ceq "routed" -and $p.routed -eq 3 -and $script:posts.Count -eq 3) ("one pass routes the three answers (" + ($p.lines -join " | ") + ")")
$toC = @(PostsTo "orc-c-session"); $toD = @(PostsTo "orc-d-session")
Check ($toC.Count -eq 2 -and $toD.Count -eq 1) "two to Orc C's session and one to Orc D's: each to the Orc whose question it answers"
$bodyW = "$(@($toC | Where-Object { $_.body -like ('*question ' + $qWindow + ':*') })[0].body)"
Check ($bodyW -clike ("FOUNDER ANSWER to your question " + $qWindow + ", routed to you by Horde.*") -and $bodyW.Contains("Question " + $qWindow + ": Should the window step go ahead?") -and $bodyW.Contains("Yes, typed in the window.") -and $bodyW.Contains("Answered by the founder, typed in the window (record " + $sWindow + ",")) "the window's answer: number, title, his words, who answered and by what route"
$bodyP = "$(@($toC | Where-Object { $_.body -like ('*question ' + $qPhone + ':*') })[0].body)"
Check ($bodyP.Contains("Yes, from my phone.") -and $bodyP.Contains("Answered by the founder, answered on the founder's phone")) "the phone's answer: his words, and that he answered on his phone"
$bodyD = "$($toD[0].body)"
Check ($bodyD.Contains("Yes, said in chat.") -and $bodyD.Contains("  And a second line.") -and $bodyD.Contains("recorded by the warchief from chat")) "the answer recorded from chat: every line of his words, and that the warchief recorded them"
Check ($bodyW.Contains("horde decisions ack " + $qWindow + " -Answer " + $sWindow) -and $bodyW.Contains("This copy authorizes nothing")) "the notice names the one command that acknowledges it, and says it authorizes nothing"
Check (@($script:posts | Where-Object { $null -ne $_.from.PSObject.Properties["verified"] }).Count -eq 0 -and "$($script:posts[0].from.label)" -ceq "F" -and "$($script:posts[0].from.sessionId)" -ceq "horde-decisions-route") "routing claims no verified sender: from the router, wearing the founder's label, never verified"
Check (@($p.lines | Where-Object { $_ -clike ("routed answer record " + $sWindow + " of question " + $qWindow + " to Orc C, through messenger doorbell (accepted; woken)*") }).Count -eq 1) "its line says what went where, and that the Orc was woken"
$rW = @(Routes $qWindow)
Check ($rW.Count -eq 1 -and [long]$rW[0].answer -eq $sWindow -and $rW[0].purpose -ceq "answer" -and $rW[0].seat -ceq "orc" -and $rW[0].label -ceq "C" -and $rW[0].sessionId -ceq "orc-c-session" -and $rW[0].resolved -eq $true -and $rW[0].notice -ceq "$($toC[0].messageId)" -or $rW[0].notice -ceq "$($toC[1].messageId)") "the store records it: which answer, to whom, resolved, and the notice's id"
Check ($script:analystLines.Count -eq 3 -and @($script:analystLines | Where-Object { $_.text.StartsWith("DECISION: question " + $qWindow + " (Should the window step go ahead?) answered by the founder, typed in the window (record " + $sWindow + "): Yes, typed in the window. - sent to Orc C. [route ") }).Count -eq 1) ("ONE line for the analyst per answer, with the question, his first line and where it went (" + $script:analystLines.Count + ")")
Check (@($script:analystLines | Where-Object { -not $_.text.EndsWith($_.token) -or $_.text.Contains("`n") }).Count -eq 0) "each analyst line is one line, and ends with the token it is found by again"
Check ($rW[0].analyst -ceq "left for the analyst as stand-in-1" -or $rW[0].analyst -like "left for the analyst as stand-in-*") "and the record says what the analyst was told"
$shown = @((Invoke-HordeDecisionCommand -Verb "show" -Given @{ Number = "$qWindow" }).lines)
Check (@($shown | Where-Object { $_ -like ("*answer record " + $sWindow + " to Orc C (session orc-c-session, notice *") }).Count -eq 1 -and @($shown | Where-Object { $_ -ceq "Routed:" }).Count -eq 1) "show prints the proof that it was routed"
$routeFile = Join-Path (Get-HordeDecisionStoreRoot) (([long]$rW[0].sequence).ToString("D10") + ".json")
$routeRecord = ConvertFrom-HordeJson ([System.IO.File]::ReadAllText($routeFile))
Check ("$($routeRecord.id)" -ceq (Get-HordeDecisionRouteRecordId -Purpose "answer" -Number $qWindow -Answer $sWindow) -and "$($routeRecord.kind)" -ceq "answer-routed" -and "$($routeRecord.actor)" -ceq "warchief") "the record's id is made from the purpose, the question and the answer: every router of the store asks for the same one"
# WHAT IS NOT AN ANSWER IS NOT ROUTED: the keeper's own note, and an act of the founder's (park).
$note = Op "say" @{ id = (New-Id); actor = "warchief"; number = $qWindow; speaker = "warchief"; route = "command"; text = "Noted, thanks."; asks = $false }
$park = Op "say" @{ id = (New-Id); actor = "founder"; number = $qWindow; speaker = "founder"; route = "window"; text = "Later."; wordingVersion = 1; act = "park" }
$p = Pass
Check ($note.value.outcome -ceq "done" -and $park.value.outcome -ceq "done" -and $p.outcome -ceq "nothing" -and $script:posts.Count -eq 3) ("the keeper's note and the founder's act (park) are no answers: nothing is routed (" + $p.outcome + ")")
foreach ($not in @(@{ seq = [long]$note.value.sequence; what = "the keeper's note" }, @{ seq = [long]$park.value.sequence; what = "an act of the founder's" })) {
    $r = Op "route" @{ id = (New-Id); actor = "warchief"; number = $qWindow; answer = $not.seq; purpose = "answer"; seat = "orc"; resolved = $true; notice = "00000000-0000-0000-0000-000000000000" }
    Check ($r.value.outcome -ceq "refused" -and $r.value.reason -ceq ("nothing was written: it routes record " + $not.seq + ", which is not an answer of the founder under question " + $qWindow)) ("the store refuses to record " + $not.what + " as a routed answer")
}

Write-Host ""
Write-Host "--- exactly once: again, after a restart, a re-applied answer, a crash between the post and the record ---" -ForegroundColor Cyan
$p = Pass
Check ($p.outcome -ceq "nothing" -and $script:posts.Count -eq 3 -and $script:analystLines.Count -eq 3) "a second pass sends nothing"
$fresh = Invoke-HordeDecisionRouteTurn -Memory @{} -Force -HordeHome $hordeHome -Clock $clock -Seat $seat -Analyst $analyst
Check ($fresh.outcome -ceq "nothing" -and $script:posts.Count -eq 3) ("a router with no memory - a restart - reads the store and sends nothing (" + $fresh.outcome + ")")
$replayId = New-Id
$sAgain = Say $qPhone "Again, the same envelope." -Route "phone" -Id $replayId
Advance 1
$p = Pass
Check ($p.routed -eq 1 -and $script:posts.Count -eq 4) "CONTROL: a NEW answer (he changed his words) is a new record and is routed"
$sSame = Say $qPhone "Again, the same envelope." -Route "phone" -Id $replayId
$p = Pass
Check ($sSame -eq $sAgain -and $p.outcome -ceq "nothing" -and $script:posts.Count -eq 4) "the same answer applied again is answered from its record, and nothing is routed twice"
# THE CRASH: the messenger takes the notice, and the record is not written.
$qCrash = Add-Question "Orc C" "Should the crash step go ahead?"
$sCrash = Say $qCrash "Yes, crash test."
$script:realInvoke = ${function:Invoke-HordeDecision}
$script:failRoute = $true
function Invoke-HordeDecision { param([string]$Operation, $Request = $null, [string]$Root = "", [datetime]$Now = [datetime]::UtcNow) if ($Operation -ceq "route" -and $script:failRoute) { return (New-HordeUnknown -Reason "the disk went away (stand-in)") }; return (& $script:realInvoke -Operation $Operation -Request $Request -Root $Root -Now $Now) }
try { $p = Pass } finally { Set-Item function:Invoke-HordeDecision $script:realInvoke }
$crashPosts = @($script:posts | Where-Object { $_.body -like ("*question " + $qCrash + ":*") })
Check ($crashPosts.Count -eq 1 -and $p.outcome -ceq "pending" -and @($p.lines | Where-Object { $_ -like "pending: answer record*was sent to Orc C*but its record could not be written (the disk went away (stand-in))*the messenger keeps as one" }).Count -eq 1 -and @(Routes $qCrash).Count -eq 0) ("the notice was taken, the record was not, and the line says so (" + ($p.lines -join " | ") + ")")
$analystBefore = $script:analystLines.Count
$p = Pass
$crashPosts = @($script:posts | Where-Object { $_.body -like ("*question " + $qCrash + ":*") })
Check ($crashPosts.Count -eq 2 -and "$($crashPosts[0].messageId)" -ceq "$($crashPosts[1].messageId)" -and @($script:taken.Keys | Where-Object { $_ -ceq "$($crashPosts[0].messageId)" }).Count -eq 1) "the next pass posts THE SAME notice, under the same id, which the messenger keeps as one"
Check (@(Routes $qCrash).Count -eq 1 -and $p.routed -eq 1) "and writes the record then"
Check ($script:analystLines.Count -eq $analystBefore + 1 -and $script:analystLines[$script:analystLines.Count - 1].token -ceq $script:analystLines[$script:analystLines.Count - 2].token) "the analyst's line is asked for again under the same token, which the analyst's mail looks for before writing (below)"
Check ((Get-HordeDecisionRouteNoticeId -HordeHome $hordeHome -Purpose "answer" -Number 3 -Answer 9 -SessionId "s") -ceq (Get-HordeDecisionRouteNoticeId -HordeHome ($hordeHome + "\") -Purpose "answer" -Number 3 -Answer 9 -SessionId "s") -and (Get-HordeDecisionRouteNoticeId -HordeHome $hordeHome -Purpose "nudge" -Number 3 -Answer 9 -SessionId "s") -cne (Get-HordeDecisionRouteNoticeId -HordeHome $hordeHome -Purpose "answer" -Number 3 -Answer 9 -SessionId "s")) "a notice's id is made from what it is about: the same answer the same id, a reminder another"
Check ((Get-HordeDecisionRouteNoticeId -HordeHome $hordeHome -Purpose "answer" -Number 3 -Answer 9 -SessionId "s") -cne (Get-HordeDecisionRouteNoticeId -HordeHome (Join-Path $work "other-home") -Purpose "answer" -Number 3 -Answer 9 -SessionId "s") -and (Get-HordeDecisionRouteNoticeId -HordeHome $hordeHome -Purpose "answer" -Number 3 -Answer 9 -SessionId "s") -cne (Get-HordeDecisionRouteNoticeId -HordeHome $hordeHome -Purpose "answer" -Number 3 -Answer 10 -SessionId "s")) "and another home's, or another answer's, is another id"
$twice = Op "route" @{ id = (New-Id); actor = "warchief"; number = $qWindow; answer = $sWindow; purpose = "answer"; seat = "orc"; label = "C"; sessionId = "orc-c-session"; resolved = $true; notice = "00000000-0000-0000-0000-000000000000" }
Check ($twice.value.outcome -ceq "refused" -and $twice.value.reason -like "*answer record $sWindow of question $qWindow was already routed for its answer (record *); an answer is routed once") "the store refuses a second record of one answer under any id: two routers cannot both record it"
$notHis = Op "route" @{ id = (New-Id); actor = "warchief"; number = $qWindow; answer = 1; purpose = "answer"; seat = "orc"; resolved = $true; notice = "00000000-0000-0000-0000-000000000000" }
Check ($notHis.value.outcome -ceq "refused" -and $notHis.value.reason -like "*it routes record 1, which is not an answer of the founder under question $qWindow") "nor is a record routed that is not his answer under that question"
$byOrc = Op "route" @{ id = (New-Id); actor = "orc"; number = $qWindow; answer = $sWindow; purpose = "nudge"; seat = "orc"; resolved = $true; notice = "00000000-0000-0000-0000-000000000000" }
Check ($byOrc.value.outcome -ceq "refused" -and $byOrc.value.reason -like "'orc' is not a role that may change the list*") "only the keeper's side records a route: an Orc may not"
$twoLines = Op "route" @{ id = (New-Id); actor = "warchief"; number = $qPhone; answer = $sAgain; purpose = "nudge"; seat = "orc"; resolved = $true; notice = "00000000-0000-0000-0000-000000000000"; note = ("one" + "`n" + "two") }
Check ($twoLines.value.outcome -ceq "refused" -and @($twoLines.value.findings | Where-Object { $_ -ceq "'note' must be one line, and it has a line break" }).Count -eq 1) "a route's note is one line"

Write-Host ""
Write-Host "--- askedBy that cannot be resolved goes to the warchief, and the record says so ---" -ForegroundColor Cyan
$qOdd = Add-Question "orc c" "Should the odd step go ahead?"
$qGone = Add-Question "Orc G" "Should the gone step go ahead?"
$qTwo = Add-Question "Orc E" "Should the doubled step go ahead?"
$qBoss = Add-Question "M (Thrall)" "Should the warchief step go ahead?"
$sOdd = Say $qOdd "Yes to the odd one."; $sGone = Say $qGone "Yes to the gone one."; $sTwo = Say $qTwo "Yes to the doubled one."; $sBoss = Say $qBoss "Yes to the warchief."
# GRACE 0 (the setting seatGraceSeconds): an unprovable seat falls back at once. The default grace is tested below.
$p = Pass 0
$toBoss = @(PostsTo "warchief-session-1")
Check ($p.routed -eq 4 -and $toBoss.Count -eq 4) ("all four went to the warchief's seat (" + ($p.lines -join " | ") + ")")
$rOdd = @(Routes $qOdd)[0]
Check ($rOdd.seat -ceq "warchief" -and $rOdd.resolved -eq $false -and $rOdd.note -ceq "its askedBy, 'orc c', is neither 'Orc' and one capital letter nor the warchief (M or Thrall), so it names no seat an answer can be sent to; it went to the warchief instead") ("askedBy that names nobody: resolved false, and the note says why (" + $rOdd.note + ")")
$rGone = @(Routes $qGone)[0]
Check ($rGone.seat -ceq "warchief" -and $rGone.resolved -eq $false -and $rGone.note -like "Orc G's seat could not be found (no live session's record wears orc G), so the answer went to the warchief instead") ("an Orc with no seat: resolved false, and why (" + $rGone.note + ")")
$rTwo = @(Routes $qTwo)[0]
Check ($rTwo.resolved -eq $false -and $rTwo.note -like "Orc E's seat could not be found (two live sessions each wear the label E with the role orc)*") "an Orc whose seat is unknown is never picked: it goes to the warchief"
$rBoss = @(Routes $qBoss)[0]
Check ($rBoss.seat -ceq "warchief" -and $rBoss.resolved -eq $true -and $rBoss.note -ceq "") "a question the warchief asked goes to the warchief, resolved"
$bodyOdd = "$(@($toBoss | Where-Object { $_.body -like ('*question ' + $qOdd + ':*') })[0].body)"
Check ($bodyOdd -clike ("FOUNDER ANSWER to question " + $qOdd + ", asked by 'orc c', sent to you, the warchief: its askedBy*") -and $bodyOdd.Contains("horde decisions close " + $qOdd + " -Outcome") -and -not $bodyOdd.Contains("decisions ack")) "the warchief's notice says why it came to it, and how to close it: ack is the asking Orc's"
Check (@($script:analystLines | Where-Object { $_.text -like ("*question " + $qOdd + " (*sent to the warchief (askedBy 'orc c' could not be resolved).*") }).Count -eq 1) "and the analyst's line says it could not be resolved"
# NO WAREHOUSE AT ALL: no warchief's seat either. Nothing is sent, nothing recorded; it waits.
$qLost = Add-Question "Orc G" "Should the lost step go ahead?"
$sLost = Say $qLost "Yes to the lost one."
$script:seats.Remove("warchief")
$before = $script:posts.Count
$p = Pass
Check ($p.outcome -ceq "pending" -and $p.pending -eq 1 -and $script:posts.Count -eq $before -and @(Routes $qLost).Count -eq 0 -and @($p.lines | Where-Object { $_ -like "pending: answer record $sLost of question $qLost was not sent: Orc G's seat could not be found*, and the warchief's seat cannot be had: no live session's record wears warchief. It is tried again" }).Count -eq 1) ("no seat at all: nothing sent, nothing recorded, and said (" + ($p.lines -join " | ") + ")")
$pendingMemory = @{}
$t1 = Invoke-HordeDecisionRouteTurn -Memory $pendingMemory -Force -HordeHome $hordeHome -Clock $clock -Seat $seat -Analyst $analyst
$t2 = Invoke-HordeDecisionRouteTurn -Memory $pendingMemory -Force -HordeHome $hordeHome -Clock $clock -Seat $seat -Analyst $analyst
Check ($t1.outcome -ceq "pending" -and @($t1.lines).Count -eq 1 -and $t2.outcome -ceq "pending" -and @($t2.lines).Count -eq 0) "a turn says a pending line once, not every time it passes"
$script:seats["warchief"] = "warchief-session-1"
$p = Pass
Check ($p.routed -eq 1 -and @(Routes $qLost).Count -eq 1) "once the warchief's seat is back, it is sent and recorded"
# A MESSENGER THAT DID NOT TAKE IT: nothing recorded, and tried again.
$qHeld = Add-Question "Orc C" "Should the held step go ahead?"
$sHeld = Say $qHeld "Yes to the held one."
$script:postSays = "held"
$p = Pass
Check ($p.outcome -ceq "pending" -and @(Routes $qHeld).Count -eq 0 -and @($p.lines | Where-Object { $_ -like "pending: answer record $sHeld*was not sent (the messenger answered held: the stand-in held it); nothing is recorded, and it is tried again" }).Count -eq 1) "a post the messenger held is not recorded as sent"
$script:postSays = "unknown"
$p = Pass
Check ($p.outcome -ceq "pending" -and @(Routes $qHeld).Count -eq 0) "nor one it could not say it took"
$script:postSays = "accepted"
$p = Pass
Check ($p.routed -eq 1 -and @(Routes $qHeld).Count -eq 1) "CONTROL: taken, it is recorded"
# NO MESSENGER: pending, said plainly.
$keepMessengers = $script:HordeMessengers
$script:HordeMessengers = @{}
$qNone = Add-Question "Orc C" "Should the messenger-less step go ahead?"
$sNone = Say $qNone "Yes with no messenger."
$p = Pass
$null = Register-HordeMessenger -Folder (Join-Path $here "fixtures\decisions-notify\doorbell-no-wake") -Post $stubPost -Status $stubStatus
$before = $script:posts.Count
$noWake = Pass
$script:HordeMessengers = $keepMessengers
Check ($p.outcome -ceq "pending" -and @($p.lines)[0] -like "pending: 1 answer(s) to route wait: no messenger on this machine can deliver to a session*" -and @(Routes $qNone).Count -eq 0) "no messenger: nothing recorded, and said"
Check ($noWake.outcome -ceq "pending" -and $script:posts.Count -eq $before -and @($noWake.lines)[0] -like "*does not offer wake*") ("a messenger that cannot wake the Orc is not used: a notice nobody wakes for is nobody told (" + @($noWake.lines)[0] + ")")
$null = Pass

Write-Host ""
Write-Host "--- an answer older than routeWithinHours, or under a closed question, is not sent days late ---" -ForegroundColor Cyan
$qOld = Add-Question "Orc C" "Should the old step go ahead?"
$sOld = Say $qOld "Yes, long ago."
Advance (49 * 60)
$before = $script:posts.Count
$p = Pass
$oldPosts = @($script:posts | Select-Object -Skip $before | Where-Object { $_.body -like ("*Question " + $qOld + ":*") -and $_.body -like "FOUNDER ANSWER*" })
Check ($oldPosts.Count -eq 0 -and @(Routes $qOld | Where-Object { $_.purpose -ceq "answer" }).Count -eq 0) "an answer 49 h old is not routed (decisions.answers.routeWithinHours is 48)"
$listNow = (Op "list" @{}).value
Check (@($listNow.unclosed | Where-Object { [int]$_.number -eq $qOld }).Count -eq 1) "CONTROL: its question is still flagged by the list"
Check (@($script:posts | Select-Object -Skip $before | Where-Object { $_.body -like ("UNCLOSED QUESTION " + $qOld + ":*") }).Count -eq 0) "and no reminder is sent for an answer that was never routed"
$qShut = Add-Question "Orc C" "Should the shut step go ahead?"
$null = Op "close" @{ id = (New-Id); actor = "warchief"; number = $qShut; outcome = "Done by hand." }
$sShut = Say $qShut "Too late."
$p = Pass
Check (@(Routes $qShut).Count -eq 0) "words under a closed question are not routed: nobody is waiting on them"
# Every question so far is closed now, so the hour below is about its own.
foreach ($n in @((Op "list" @{}).value.questions | ForEach-Object { [int]$_.number })) { $null = Op "close" @{ id = (New-Id); actor = "warchief"; number = $n; outcome = "Closed to clear the list." } }
$null = Pass
$script:posts.Clear()

Write-Host ""
Write-Host "--- the hour: answered and still open is flagged, and its asker reminded ONCE ---" -ForegroundColor Cyan
$qHour = Add-Question "Orc C" "Should the hour step go ahead?"
$sHour = Say $qHour "Yes, within the hour."
$p = Pass
Check ($p.routed -eq 1 -and $script:posts.Count -eq 1) "CONTROL: the answer is routed at once"
Advance 59
$l = (Op "list" @{}).value
Check (@($l.unclosed).Count -eq 0) "59 minutes on: not flagged"
$p = Pass
Check ($p.outcome -ceq "nothing" -and $script:posts.Count -eq 1) "and nobody is reminded"
Advance 2
$l = (Op "list" @{}).value
$u = @($l.unclosed)
Check ($u.Count -eq 1 -and [int]$u[0].number -eq $qHour -and [long]$u[0].answer -eq $sHour -and $u[0].line -ceq ("question " + $qHour + ": answered 1 h ago, not closed by Orc C") -and $u[0].reminded -eq $false) ("61 minutes on: flagged, in words (" + $(if ($u.Count) { $u[0].line } else { "none" }) + ")")
$closedOnly = (Op "list" @{ state = "closed" }).value
Check (@($closedOnly.unclosed).Count -eq 1) "the flag is in the list however it is filtered"
$text = @(Format-HordeDecisionList -Value $l -Kinds $null -Showing "open")
Check ($text[1] -ceq "ANSWERED AND NOT CLOSED: 1 question(s):" -and $text[2] -ceq ("  question " + $qHour + ": answered 1 h ago, not closed by Orc C")) "the list prints the flag first"
$p = Pass
Check ($p.routed -eq 1 -and $script:posts.Count -eq 2 -and "$($script:posts[1].sessionId)" -ceq "orc-c-session" -and "$($script:posts[1].body)" -clike ("UNCLOSED QUESTION " + $qHour + ": *") -and "$($script:posts[1].body)".Contains("horde decisions ack " + $qHour + " -Answer " + $sHour)) ("the pass reminds Orc C, once, with the command that closes it (" + ($p.lines -join " | ") + ")")
Check (@($p.lines | Where-Object { $_ -clike ("reminded Orc C of question " + $qHour + " (answer record " + $sHour + ", still open)*") }).Count -eq 1) "and says so"
$rH = @(Routes $qHour | Where-Object { $_.purpose -ceq "nudge" })
Check ($rH.Count -eq 1 -and [long]$rH[0].answer -eq $sHour) "the reminder is a record of its own"
Check ($script:analystLines[$script:analystLines.Count - 1].text -notlike "*UNCLOSED*" -and @($script:analystLines | Where-Object { $_.text -like ("DECISION: question " + $qHour + " *") }).Count -eq 1) "the analyst is told of the answer once, not of the reminder"
Advance 180
$p = Pass
Check ($script:posts.Count -eq 2 -and $p.outcome -ceq "nothing") "three hours later: no second reminder"
$l = (Op "list" @{}).value
Check (@($l.unclosed).Count -eq 1 -and $l.unclosed[0].reminded -eq $true -and $l.unclosed[0].line -ceq ("question " + $qHour + ": answered 4 h ago, not closed by Orc C")) "still flagged, as reminded, with its age"
# A NEW ANSWER re-arms it: it is routed, and in its own hour reminded once more.
$sHour2 = Say $qHour "Actually, wait for Monday."
$p = Pass
Check ($p.routed -eq 1 -and $script:posts.Count -eq 3 -and @((Op "list" @{}).value.unclosed).Count -eq 0) "a new answer is routed, and the flag starts again from it"
Advance 61
$p = Pass
Check ($script:posts.Count -eq 4 -and "$($script:posts[3].body)" -clike ("UNCLOSED QUESTION " + $qHour + ":*")) "and an hour on, it is reminded once for that answer"
# A PART LEFT UNANSWERED: still his turn, so neither flagged nor reminded - though the part he did answer
# is routed like any answer.
$qAsked = Add-Question "Orc D" "Should the two-part step go ahead?" -Parts @("(a) the first part", "(b) the second part")
$sPartA = Say $qAsked "Yes to the first." -Part "a"
$p = Pass
Check ($p.routed -eq 1 -and @(Routes $qAsked).Count -eq 1 -and [long]@(Routes $qAsked)[0].answer -eq $sPartA -and "$($script:posts[$script:posts.Count - 1].body)".Contains("(part a)")) "an answer to one part is routed, and the notice names the part"
Advance 61
$p = Pass
Check (@((Op "list" @{}).value.unclosed | Where-Object { [int]$_.number -eq $qAsked }).Count -eq 0 -and @($script:posts | Where-Object { $_.body -like ("UNCLOSED QUESTION " + $qAsked + ":*") }).Count -eq 0) "a question with a part he has not answered is his turn: not flagged, not reminded"

Write-Host ""
Write-Host "--- ack: the asking Orc closes it as the closer; every other ack is refused in words ---" -ForegroundColor Cyan
$wrong = Ack $qHour "D" $sHour2
Check ($wrong.value.outcome -ceq "refused" -and $wrong.value.reason -ceq ("nothing was written: question " + $qHour + " was asked by 'Orc C', not by Orc D: only the Orc that asked it acknowledges its answer")) "another Orc's ack is refused, in words"
$stale = Ack $qHour "C" $sHour
Check ($stale.value.outcome -ceq "refused" -and $stale.value.reason -ceq ("nothing was written: it acknowledges record " + $sHour + ", and the answer that stands under question " + $qHour + " is record " + $sHour2 + ": read that one (horde decisions show " + $qHour + "), then acknowledge it")) "an ack of an answer he has since replaced is refused, naming the one that stands"
$ok = Ack $qHour "C" $sHour2
Check ($ok.value.outcome -ceq "done" -and $ok.value.question.state -ceq "closed" -and $ok.value.question.closedBy -ceq "Orc C" -and $ok.value.question.outcome -ceq ("Acknowledged by Orc C: the founder's answer (record " + $sHour2 + ") reached the Orc that asked.") -and @($ok.value.question.history)[-1].actor -ceq "orc" -and @($ok.value.question.history)[-1].note -ceq "closed: acknowledged by Orc C" -and $ok.value.question.thread.turn -ceq "nobody") "the asking Orc's ack closes it, with that Orc as the closer, in the record and the history"
Check (@((Op "list" @{}).value.unclosed | Where-Object { [int]$_.number -eq $qHour }).Count -eq 0) "and it is no longer flagged"
$late = Ack $qHour "C" $sHour2
Check ($late.value.outcome -ceq "refused" -and $late.value.reason -ceq ("nothing was written: question " + $qHour + " is already closed: an acknowledgement closes only an open question, and never opens a closed one again") -and (Show $qHour).state -ceq "closed") "a late ack on a closed question is refused, and it stays closed"
$qBare = Add-Question "Orc C" "Should the unanswered step go ahead?"
$bare = Ack $qBare "C" 1
Check ($bare.value.outcome -ceq "refused" -and $bare.value.reason -ceq ("nothing was written: question " + $qBare + " has no answer of the founder to acknowledge: only an answered question is closed this way") -and (Show $qBare).state -ceq "open") "an ack of an unanswered question is refused, in words"
$bareNamed = Ack $qBare "C" 1
Check ($bareNamed.value.outcome -ceq "refused" -and $bareNamed.value.reason -like ("*question " + $qBare + " has no answer of the founder to acknowledge*")) "and so is one that names an answer the question does not have"
$askedAgain = Ack $qAsked "D" $sPartA
Check ($askedAgain.value.outcome -ceq "refused" -and $askedAgain.value.reason -like ("*question " + $qAsked + " is still waiting for the founder - a part of it is unanswered, or he was asked again after his answer - so it is not closed by an acknowledgement")) "an ack of a question still waiting for him is refused"
$qWarchief = Add-Question "M (Thrall)" "Should the keeper's own step go ahead?"
$sWarchief = Say $qWarchief "Yes, keeper."
$boss = Ack $qWarchief "M" $sWarchief
Check ($boss.value.outcome -ceq "refused" -and $boss.value.reason -like "*was asked by 'M (Thrall)', not by Orc M*") "a question the warchief asked is acknowledged by no Orc, M included"
$shape = Ack $qWarchief "C3" $sWarchief
Check ($shape.value.outcome -ceq "refused" -and $shape.value.reason -ceq "the request is not what 'ack' takes; nothing was done") "a lane letter that is not one capital letter is refused by the request's shape"
$bossC = Ack $qWarchief "C" $sWarchief
Check ($bossC.value.outcome -ceq "refused" -and $bossC.value.reason -like "*was asked by 'M (Thrall)', not by Orc C*") "no Orc acknowledges a question the warchief asked"
$byKeeper = Op "ack" @{ id = (New-Id); actor = "warchief"; number = $qWarchief; by = "C"; answer = $sWarchief }
Check ($byKeeper.value.outcome -ceq "refused" -and $byKeeper.value.reason -like "'warchief' is not a role that may acknowledge the founder's answer to a question it asked*") "the keeper closes with close: ack is an Orc's"
$qRepost = Add-Question "Orc C" "Should the repost step go ahead?"
$sRepost = Say $qRepost "Yes, repost."
$parked = Op "say" @{ id = (New-Id); actor = "founder"; number = $qRepost; speaker = "founder"; route = "window"; text = "Later."; wordingVersion = 1; act = "park" }
$ackId = New-Id
$first = Ack $qRepost "C" $sRepost -Id $ackId
$again = Ack $qRepost "C" $sRepost -Id $ackId
Check ($parked.value.outcome -ceq "done" -and $first.value.outcome -ceq "done" -and $again.value.outcome -ceq "replayed" -and [long]$again.value.sequence -eq [long]$first.value.sequence) "an act of his after the answer is no answer: the answer still stands and is acknowledged; and an ack sent twice under its id is the one record"
$qFill = Add-Question "Orc C" "Should the filled-in step go ahead?"
$sFill = Say $qFill "Yes, filled in."
$filled = Ack $qFill "C"
Check ($filled.value.outcome -ceq "refused" -and $filled.value.reason -like "*an acknowledgement names the answer it acknowledges*" -and (Show $qFill).state -ceq "open") "an ack that names no answer is refused at the operation, and writes nothing: it would close over whatever stands (finding 4)"
$filled = Ack $qFill "C" $sFill
$ackFile = Join-Path (Get-HordeDecisionStoreRoot) (([long]$filled.value.sequence).ToString("D10") + ".json")
Check ($filled.value.outcome -ceq "done" -and [long](ConvertFrom-HordeJson ([System.IO.File]::ReadAllText($ackFile))).data.answer -eq $sFill) "an ack that names the answer closes it, and its record says which"

Write-Host ""
Write-Host "--- the command line: ack proves which Orc runs it ---" -ForegroundColor Cyan
$qCli = Add-Question "Orc D" "Should the command-line step go ahead?"
$sCli = Say $qCli "Yes, from the command line."
$asD = { return [pscustomobject]@{ ok = $true; reason = ""; sessionId = "orc-d-session"; label = "D" } }
$asC3 = { return [pscustomobject]@{ ok = $true; reason = ""; sessionId = "c3-session"; label = "C3" } }
$seatOk = { param($Who) return [pscustomobject]@{ ok = $true; reason = "" } }
$nobody = { return [pscustomobject]@{ ok = $false; reason = "no notice was sent: this is not run from inside a session (no id)"; sessionId = ""; label = "" } }
Check (Throws { Invoke-HordeDecisionCommand -Verb "ack" -Given @{ Number = "$qCli" } -Sender $nobody -SeatProof $seatOk } "decisions ack is run by the Orc that asked, from inside its own session, and which session this is could not be proven: this is not run from inside a session (no id)") "run outside a session: refused, saying why"
Check (Throws { Invoke-HordeDecisionCommand -Verb "ack" -Given @{ Number = "$qCli" } -Sender $asC3 -SeatProof $seatOk } "this session's fleet label is 'C3', which is not an Orc's lane letter") "run by a session that is no Orc: refused"
Check (Throws { Invoke-HordeDecisionCommand -Verb "ack" -Given @{ Number = "$qCli"; Answer = "x" } -Sender $asD -SeatProof $seatOk } "-Answer is the record of the answer you were sent") "an -Answer that is not a record's number is refused"
$asC = { return [pscustomobject]@{ ok = $true; reason = ""; sessionId = "orc-c-session"; label = "C" } }
$cliWrong = Invoke-HordeDecisionCommand -Verb "ack" -Given @{ Number = "$qCli"; Answer = "$sCli" } -Sender $asC -SeatProof $seatOk
Check ($cliWrong.failure -like ("*question " + $qCli + " was asked by 'Orc D', not by Orc C*") -and (Show $qCli).state -ceq "open") "the Orc the session proves to be is the one held to askedBy: Orc C cannot close Orc D's question"
$cli = Invoke-HordeDecisionCommand -Verb "ack" -Given @{ Number = "$qCli"; Answer = "$sCli" } -Sender $asD -SeatProof $seatOk
Check ($cli.failure -ceq "" -and $cli.lines[0] -ceq ("Closed question " + $qCli + ": Should the command-line step go ahead?") -and $cli.lines[1] -like "  closed: acknowledged by Orc D. Acknowledged by Orc D:*") ("Orc D's own ack closes its question (" + ($cli.lines -join " | ") + ")")
$cliLate = Invoke-HordeDecisionCommand -Verb "ack" -Given @{ Number = "$qCli"; Answer = "$sCli" } -Sender $asD -SeatProof $seatOk
Check ($cliLate.failure -like "*question $qCli is already closed*" -and $cliLate.lines[0] -like "Refused:*already closed*") "and a second ack fails the command, in words"
$routeVerb = Invoke-HordeDecisionCommand -Verb "route" -Given @{}
Check ($routeVerb.routes -eq $true -and @($routeVerb.lines).Count -eq 0) "route is no operation of its own at the command line: it hands on to one pass of the router"

Write-Host ""
Write-Host "--- the turn: one router per home, and a line said once ---" -ForegroundColor Cyan
$memory = @{}
$qTurn = Add-Question "Orc C" "Should the turn step go ahead?"
$sTurn = Say $qTurn "Yes, turn."
$t = Invoke-HordeDecisionRouteTurn -Memory $memory -HordeHome $hordeHome -Clock $clock -Seat $seat -Analyst $analyst
Check ($t.outcome -ceq "routed" -and @($t.lines | Where-Object { $_ -clike ("routed answer record " + $sTurn + " of question " + $qTurn + " to Orc C*") }).Count -eq 1) "a first turn passes and says what it routed"
$t = Invoke-HordeDecisionRouteTurn -Memory $memory -HordeHome $hordeHome -Clock $clock -Seat $seat -Analyst $analyst
Check ($t.outcome -ceq "idle") "a turn with no change in the store and inside passSeconds does not read it"
Advance 2
$t = Invoke-HordeDecisionRouteTurn -Memory $memory -HordeHome $hordeHome -Clock $clock -Seat $seat -Analyst $analyst
Check ($t.outcome -ceq "nothing") "after passSeconds it reads it again"
$held = New-Object System.Threading.Mutex($false, (Get-HordeDecisionRouteMutexName -HordeHome $hordeHome))
[void]$held.WaitOne(0)
$runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace(); $runspace.Open()
$shell = [System.Management.Automation.PowerShell]::Create(); $shell.Runspace = $runspace
[void]$shell.AddScript('param($File, $HomeDir) . $File; (Invoke-HordeDecisionRouteTurn -Memory @{} -Force -HordeHome $HomeDir).outcome').AddArgument((Join-Path $root "decisions\Route.ps1")).AddArgument($hordeHome)
$elsewhere = @($shell.Invoke())
$shell.Dispose(); $runspace.Dispose()
$held.ReleaseMutex(); $held.Dispose()
Check (($elsewhere -join ",") -ceq "elsewhere") ("while another holds the home's router mutex, a turn does nothing (" + ($elsewhere -join ",") + ")")
$settingsFile = (Get-HordeDecisionRouteSettings -HordeHome $hordeHome).path
New-Item -ItemType Directory -Path (Split-Path -Parent $settingsFile) -Force | Out-Null
[System.IO.File]::WriteAllText($settingsFile, '{"schemaVersion":1,"settings":{"passSeconds":1}}')
$t3 = Invoke-HordeDecisionRouteTurn -Memory $memory -HordeHome $hordeHome -Clock $clock -Seat $seat -Analyst $analyst
$t4 = Invoke-HordeDecisionRouteTurn -Memory $memory -HordeHome $hordeHome -Clock $clock -Seat $seat -Analyst $analyst
Remove-Item -LiteralPath $settingsFile
Check ($t3.outcome -ceq "refused" -and @($t3.lines).Count -eq 1 -and $t3.lines[0] -like "answers are not routed, because the route settings file is refused:*" -and $t4.outcome -ceq "refused" -and @($t4.lines).Count -eq 0) "a refused settings file routes nothing and says so once"
$defaults = (Read-HordeModuleSettingsText -Declaration (Get-HordeDecisionRouteSettingsDeclaration) -Text $null).values
Check ($defaults.passSeconds -eq 60 -and $defaults.fromLabel -ceq "F" -and (Get-HordeDecisionSetting -Name "decisions.answers.unclosedMinutes") -eq 60 -and (Get-HordeDecisionSetting -Name "decisions.answers.routeWithinHours") -eq 48) "the defaults: a pass a minute, from F, flagged after 60 minutes, answers up to 48 h old routed"

Write-Host ""
Write-Host "--- the analyst's mail: one line, written once, found again by its token ---" -ForegroundColor Cyan
$analystHome = Join-Path $work "analyst-home"
New-Item -ItemType Directory -Path $analystHome | Out-Null
$a1 = Send-HordeDecisionRouteAnalyst -Text "DECISION: question 1 (t) answered. [route abc]" -Token "[route abc]" -HordeHome $analystHome -Since ([datetime]::UtcNow)
$mailDir = Join-Path $analystHome "analyst\mail"
$files = @(Get-ChildItem -LiteralPath $mailDir -Filter "*.txt")
Check ($a1.ok -and $a1.said -like "left for the analyst as *" -and $files.Count -eq 1 -and [System.IO.File]::ReadAllText($files[0].FullName) -ceq "DECISION: question 1 (t) answered. [route abc]") ("the line is left in the analyst's mail, as horde analyst mail leaves it (" + $a1.said + ")")
$a2 = Send-HordeDecisionRouteAnalyst -Text "DECISION: question 1 (t) answered. [route abc]" -Token "[route abc]" -HordeHome $analystHome -Since ([datetime]::UtcNow)
Check ($a2.ok -and $a2.said -ceq ("already left for the analyst as " + $files[0].Name) -and @(Get-ChildItem -LiteralPath $mailDir -Filter "*.txt").Count -eq 1) "the same token again writes nothing more"
New-Item -ItemType Directory -Path (Join-Path $mailDir "delivered") | Out-Null
Move-Item -LiteralPath $files[0].FullName -Destination (Join-Path $mailDir "delivered")
$a3 = Send-HordeDecisionRouteAnalyst -Text "DECISION: question 1 (t) answered. [route abc]" -Token "[route abc]" -HordeHome $analystHome -Since ([datetime]::UtcNow)
Check ($a3.said -like "already left for the analyst as *" -and @(Get-ChildItem -LiteralPath $mailDir -Filter "*.txt").Count -eq 0) "nor once the analyst's supervisor has delivered it"
$a4 = Send-HordeDecisionRouteAnalyst -Text "DECISION: question 2 (t) answered. [route def]" -Token "[route def]" -HordeHome $analystHome -Since ([datetime]::UtcNow)
Check ($a4.said -like "left for the analyst as *" -and @(Get-ChildItem -LiteralPath $mailDir -Filter "*.txt").Count -eq 1) "CONTROL: another token is another line"


Write-Host ""
Write-Host "--- an Orc seat that cannot be proven just now is waited for, not given up (review finding 1) ---" -ForegroundColor Cyan
$script:seats["orc F"] = "orc-f-session"
$script:fUnknown = $false
$script:seatBase = $seat
$seatF = {
    param([string]$Role, [string]$Label)
    if ($Role -ceq "orc" -and $Label -ceq "F" -and $script:fUnknown) { return (New-HordeUnknown -Reason "the registry could not be read (Orc F is restarting)") }
    return (& $script:seatBase $Role $Label)
}
function PassF { return (Invoke-HordeDecisionRoutePass -Clock $clock -Seat $seatF -Analyst $analyst -HordeHome $hordeHome) }
$qF1 = Add-Question "Orc F" "Should the restarting step go ahead?"
$sF1 = Say $qF1 "Yes, F1 words."
$script:fUnknown = $true
$p = PassF
Check ($p.outcome -ceq "pending" -and @($p.lines | Where-Object { $_ -ceq ("pending: answer record " + $sF1 + " of question " + $qF1 + " waits for Orc F's seat, which cannot be proven just now (the registry could not be read (Orc F is restarting)); waiting up to 300 s for that Orc's seat, then it goes to the warchief") }).Count -eq 1 -and @(Routes $qF1).Count -eq 0 -and @(PostsTo "warchief-session-1" | Where-Object { $_.body -like ("*question " + $qF1 + ":*") }).Count -eq 0) ("a seat that is unknown: nothing is sent to the warchief, nothing is recorded (" + ($p.lines -join " | ") + ")")
Advance 2
$p = PassF
Check (@(Routes $qF1).Count -eq 0 -and @(PostsTo "warchief-session-1" | Where-Object { $_.body -like ("*question " + $qF1 + ":*") }).Count -eq 0) "and it is still waiting inside the grace"
$script:fUnknown = $false
$p = PassF
$toF = @(PostsTo "orc-f-session" | Where-Object { $_.body -like ("*question " + $qF1 + ":*") })
$rF1 = @(Routes $qF1)
Check ($toF.Count -eq 1 -and $rF1.Count -eq 1 -and $rF1[0].seat -ceq "orc" -and $rF1[0].resolved -eq $true -and "$($rF1[0].sessionId)" -ceq "orc-f-session") "the seat back inside the grace: the answer reaches the Orc that asked, and the record says so"
# PAST THE GRACE: the warchief, as before, and the analyst's line says the seat was missing, not the asker.
$qF2 = Add-Question "Orc F" "Should the lost-seat step go ahead?"
$sF2 = Say $qF2 "Yes, F2 words."
$script:fUnknown = $true
$p = PassF
Advance 6
$p = PassF
$rF2 = @(Routes $qF2)
Check ($rF2.Count -eq 1 -and $rF2[0].seat -ceq "warchief" -and $rF2[0].resolved -eq $false -and $rF2[0].note -like "Orc F's seat could not be found (the registry could not be read*" -and @(PostsTo "warchief-session-1" | Where-Object { $_.body -like ("*question " + $qF2 + ":*") }).Count -eq 1) "still unprovable after the grace: it goes to the warchief"
Check (@($script:analystLines | Where-Object { $_.text -like ("*question " + $qF2 + " (*sent to the warchief (askedBy 'Orc F' is clear, but that Orc's seat was not found).*") }).Count -eq 1) "and the analyst is told the asker was clear and the seat was not found"
# THE REMINDER carries his words, and goes to the seat as it is then: an Orc that never saw the answer is not told to acknowledge it blind (finding 2).
$script:fUnknown = $false
Advance 61
$p = PassF
$nudgeF = @(PostsTo "orc-f-session" | Where-Object { $_.body -like ("UNCLOSED QUESTION " + $qF2 + ":*") })
Check ($nudgeF.Count -eq 1 -and "$($nudgeF[0].body)".Contains("Yes, F2 words.") -and "$($nudgeF[0].body)".Contains("horde decisions ack " + $qF2 + " -Answer " + $sF2)) "the reminder to an Orc that was sent nothing carries his words, beside the command that acknowledges them"

Write-Host ""
Write-Host "--- ack: the session must hold the Orc's seat (role orc), not merely wear its letter (review finding 3) ---" -ForegroundColor Cyan
. (Join-Path $root "notices\Sender.ps1")
$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$sessionVariable = ("" + (Get-HordeSelfSessionId -Environment @{}).reason).Split(" ")[0]
$t0 = (New-Object DateTime 2026, 10, 14, 1, 0, 0, ([DateTimeKind]::Utc)).AddTicks(1234560)
$ctl = Join-Path $work "ack-control"; New-Item -ItemType Directory -Path $ctl -Force | Out-Null
$proj = Join-Path $work "ack-projects"; New-Item -ItemType Directory -Path $proj -Force | Out-Null
$reg = Join-Path $work "ack-fleet"; New-Item -ItemType Directory -Path (Join-Path $reg "registry\sessions") -Force | Out-Null
function Sid { param([int]$N) return ("cccccccc-0000-4000-8000-" + $N.ToString("000000000000")) }
function New-AckSession {
    # A running session as the agent's own control file shows it, and its record in the fleet's registry.
    param([int]$ProcId, [string]$SessionId, [datetime]$Created, [string]$Role, [string]$Pane)
    $ms = ([DateTimeOffset]$Created.ToUniversalTime().AddSeconds(90)).ToUnixTimeMilliseconds()
    $o = [ordered]@{ pid = $ProcId; sessionId = $SessionId; cwd = "C:\work"; startedAt = $ms; procStart = "" + $Created.ToFileTimeUtc(); version = "9.9.9"; peerProtocol = 1; peerFeatures = @("f"); kind = "interactive"; entrypoint = "cli"; messagingSocketPath = ("\\.\pipe\LOCAL\ack-" + $ProcId); name = "C"; nameSource = "user"; nameSince = $ms; updatedAt = $ms; status = "busy"; statusUpdatedAt = $ms; bridgeSessionId = ("bridge-" + $ProcId) }
    [System.IO.File]::WriteAllText((Join-Path $ctl ("" + $ProcId + ".json")), ($o | ConvertTo-Json -Depth 4), $utf8)
    $r = [ordered]@{ claudeSessionId = $SessionId; label = "C"; role = $Role; pane = $Pane; instance = "t1"; lastSeen = "2026-10-14T02:00:00.0000000Z" }
    [System.IO.File]::WriteAllText((Join-Path $reg ("registry\sessions\" + $SessionId + ".json")), ($r | ConvertTo-Json -Compress), $utf8)
}
# Session 1 (process 100, shell 200, the command 300) is NOT an Orc, yet its fleet label is "C"; session 2
# (process 400, shell 500, command 600) is the Orc C.
New-AckSession -ProcId 100 -SessionId (Sid 1) -Created $t0 -Role "master" -Pane "5"
New-AckSession -ProcId 400 -SessionId (Sid 2) -Created $t0.AddSeconds(5) -Role "orchestrator" -Pane "6"
$rows = @{}
foreach ($r in @(@(100, 1, $t0), @(200, 100, $t0.AddSeconds(1)), @(300, 200, $t0.AddSeconds(2)), @(400, 1, $t0.AddSeconds(5)), @(500, 400, $t0.AddSeconds(6)), @(600, 500, $t0.AddSeconds(7)))) { $rows[[int]$r[0]] = [pscustomobject]@{ pid = [int]$r[0]; parent = [int]$r[1]; name = "p"; created = $r[2]; commandLine = "" } }
$procs = New-HordeKnown -Value $rows
$identArgs = @{ ClaudeDir = $ctl; ProjectsDir = $proj }
$identity = Get-HordeIdentity @identArgs -Processes $procs
$qNonOrc = Add-Question "Orc C" "Should the impostor step go ahead?"
$sNonOrc = Say $qNonOrc "Yes, for the real Orc C."
# THE SENDER IS NOT STUBBED: it is proven from the environment, the process table and the registry above.
$senderNonOrc = @{ Environment = @{ $sessionVariable = (Sid 1) }; Identity = $identArgs; Processes = $procs; RegistryRoot = $reg; Self = 300 }
$senderOrc = @{ Environment = @{ $sessionVariable = (Sid 2) }; Identity = $identArgs; Processes = $procs; RegistryRoot = $reg; Self = 600 }
$seatArgs = @{ Root = $reg; Identity = $identity }
$proven = Resolve-HordeNoticeSender @senderNonOrc
Check ($proven.ok -and $proven.label -ceq "C" -and $proven.sessionId -ceq (Sid 1)) ("CONTROL: the real sender proves session 1 as 'C' by its label alone (" + $proven.reason + ")")
Check (Throws { Invoke-HordeDecisionCommand -Verb "ack" -Given @{ Number = "$qNonOrc"; Answer = "$sNonOrc" } -SenderArgs $senderNonOrc -SeatArgs $seatArgs } "this session is not proven to be Orc C") "a session that is no Orc but wears the asker's letter is refused"
Check ((Show $qNonOrc).state -ceq "open") "and the question stays open"
$byOrc = Invoke-HordeDecisionCommand -Verb "ack" -Given @{ Number = "$qNonOrc"; Answer = "$sNonOrc" } -SenderArgs $senderOrc -SeatArgs $seatArgs
Check ($byOrc.failure -ceq "" -and (Show $qNonOrc).state -ceq "closed" -and (Show $qNonOrc).closedBy -ceq "Orc C") ("CONTROL: the session that holds the Orc C seat acknowledges it (" + $byOrc.failure + ")")
$qNeed = Add-Question "Orc D" "Should the unnamed-answer step go ahead?"
$sNeed = Say $qNeed "Yes, unnamed."
Check (Throws { Invoke-HordeDecisionCommand -Verb "ack" -Given @{ Number = "$qNeed" } -Sender $asD -SeatProof $seatOk } "decisions ack needs -Answer <record>") "the command line refuses an ack that names no answer (finding 4)"
Check ((Show $qNeed).state -ceq "open") "and writes nothing"

Write-Host ""
Write-Host "--- T-0263: the notice names the founder's home in the commands, and they run as pasted ---" -ForegroundColor Cyan
$qHome = Add-Question "Orc C" "Should the home step go ahead?"
$sHome = Say $qHome "Yes, from the home test."
Advance 1
$before = $script:posts.Count
$p = Pass
$bodyH = "$(@(PostsTo "orc-c-session" | Where-Object { $_.body -like ('*question ' + $qHome + ':*') })[0].body)"
Check ($p.routed -ge 1 -and $script:posts.Count -ge ($before + 1) -and $null -ne (PostsTo "orc-c-session" | Where-Object { $_.body -like ('*question ' + $qHome + ':*') })) "CONTROL: the home test's answer is routed"
$quotedHome = "'" + $hordeHome.Replace("'", "''") + "'"
Check ($bodyH.Contains('$env:HORDE_HOME = ' + $quotedHome + '; horde decisions ack ' + $qHome + ' -Answer ' + $sHome + ' }')) "the ack line sets the store's home for that command"
Check ($bodyH.Contains('$env:HORDE_HOME = ' + $quotedHome + '; horde decisions show ' + $qHome + ' }')) "the show line sets the store's home for that command"
Check (-not ($bodyH -match '(?m)^\s*horde decisions (ack|show)')) "no bare horde decisions command is left in the notice, where a default home would be read"
# THE LINES RUN AS PASTED, on whichever PowerShell runs this suite (the suite runs on 5.1 and on 7): parsed
# by the language's own parser, then run with a stand-in horde that reports the home it was run in.
$cmdLines = @($bodyH -split "\r?\n" | Where-Object { $_ -match '^\s+\$wasHordeHome' } | ForEach-Object { $_.Trim() })
Check ($cmdLines.Count -eq 2) "the notice holds two commands to paste: ack and show"
foreach ($cl in $cmdLines) {
    $errs = $null; $toks = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($cl, [ref]$toks, [ref]$errs)
    Check ($errs.Count -eq 0) ("a command line parses without errors: " + $cl.Substring(0, 60))
}
function horde { $script:ranIn = "$env:HORDE_HOME"; $script:ranArgs = ($args -join " ") }
$env:HORDE_HOME = "C:\the\orcs\own\home"
foreach ($cl in $cmdLines) {
    $script:ranIn = ""; $script:ranArgs = ""
    Invoke-Expression $cl
    Check ($script:ranIn -ceq $hordeHome -and $script:ranArgs -like ("decisions * " + $qHome + "*") -and $env:HORDE_HOME -ceq "C:\the\orcs\own\home") ("run as pasted: horde sees the store's home, and the Orc's own HORDE_HOME is put back (" + $script:ranArgs + ")")
}
Remove-Item Env:\HORDE_HOME
foreach ($cl in $cmdLines) { Invoke-Expression $cl; Check ($null -eq $env:HORDE_HOME) "and an unset HORDE_HOME is unset again afterwards" }
$env:HORDE_HOME = $hordeHome
$oddCmd = Format-HordeDecisionRouteCommand -Command "horde decisions show 7" -HordeHome "C:\O'Brien\home"
Check ($oddCmd.Contains("'C:\O''Brien\home'")) "a quote in the home is doubled, so the line stays one string"
Check ((Format-HordeDecisionRouteCommand -Command "horde decisions show 7") -ceq "horde decisions show 7") "with no home the command is as it was"
Check ((Get-HordeDecisionRouteStoreHome -StoreRoot "C:\x\home\store\decisions" -HordeHome "C:\y") -ceq "C:\x\home" -and (Get-HordeDecisionRouteStoreHome -HordeHome "C:\y") -ceq "C:\y" -and (Get-HordeDecisionRouteStoreHome -StoreRoot "C:\somewhere\else" -HordeHome "C:\y") -ceq "C:\y") "the home named is the one the store root belongs to, else the router's home"
# THE REMINDER and the warchief's notice name it too.
$qNudgeH = Add-Question "Orc C" "Should the home reminder go ahead?"
$sNudgeH = Say $qNudgeH "Yes, remind me."
Advance 1
[void](Pass)
Advance 70
[void](Pass)
$nudgeH = @(PostsTo "orc-c-session" | Where-Object { "$($_.body)" -clike ("UNCLOSED QUESTION " + $qNudgeH + ": *") })
Check ($nudgeH.Count -eq 1 -and "$($nudgeH[0].body)".Contains('$env:HORDE_HOME = ' + $quotedHome + '; horde decisions ack ' + $qNudgeH) -and "$($nudgeH[0].body)".Contains('$env:HORDE_HOME = ' + $quotedHome + '; horde decisions show ' + $qNudgeH)) "the one reminder carries the home in its ack and show lines"
$qBossH = Add-Question "Mallory" "Should the unnamed home step go ahead?"
$sBossH = Say $qBossH "Yes, boss."
Advance 1
[void](Pass)
$bossH = "$(@(PostsTo "warchief-session-1" | Where-Object { $_.body -like ('*question ' + $qBossH + ':*') })[0].body)"
Check ($bossH.Contains('$env:HORDE_HOME = ' + $quotedHome + '; horde decisions close ' + $qBossH + ' -Outcome') -and $bossH.Contains('$env:HORDE_HOME = ' + $quotedHome + '; horde decisions show ' + $qBossH)) "the warchief's notice names the home in close and show"

Write-Host ""
Write-Host "--- T-0264: a routed answer is from the verified founder when his passkey signed it and is trusted now ---" -ForegroundColor Cyan
$keyV = "0123456789abcdef0123456789abcdef"
$script:trustAsked = New-Object System.Collections.ArrayList
$trustYes = { param([string]$KeyId) [void]$script:trustAsked.Add($KeyId); return (New-HordeKnown -Value ([pscustomobject]@{ proof = "webauthn" })) }
$trustNo = { param([string]$KeyId) [void]$script:trustAsked.Add($KeyId); return (New-HordeAbsent -Note "revoked") }
$trustMachine = { param([string]$KeyId) return (New-HordeKnown -Value ([pscustomobject]@{ proof = "es256" })) }
$trustBroken = { param([string]$KeyId) return (New-HordeUnknown -Reason "the trust store is damaged") }
function PassTrust { param([scriptblock]$Trust) return (Invoke-HordeDecisionRoutePass -Clock $clock -Seat $seat -Analyst $analyst -HordeHome $hordeHome -Trust $Trust) }
function Last-Post { return $script:posts[$script:posts.Count - 1] }
function Verified-Of { param($Message) $v = $Message.from.PSObject.Properties["verified"]; if ($null -eq $v) { return $null }; return $v.Value }
$qV1 = Add-Question "Orc C" "Should the verified step go ahead?"
$sV1 = Say $qV1 "Yes, signed." -Route "phone"
Advance 1
$p = PassTrust $trustYes
$vv = Verified-Of (Last-Post)
Check ($p.routed -eq 1 -and $null -ne $vv -and $vv.kind -ceq "founder" -and $vv.by -ceq "passkey" -and $vv.keyId -ceq $keyV -and (Last-Post).from.label -ceq "F" -and $script:trustAsked -ccontains $keyV) ("a phone answer by a trusted passkey: from the founder, verified by passkey, naming that key id, wearing label F (" + ($p.lines -join " | ") + ")")
Check (@($p.lines | Where-Object { $_ -like "*as the founder, verified by his passkey $keyV*" }).Count -eq 1) "and the pass says so in its line"
$qV2 = Add-Question "Orc C" "Should the typed step go ahead?"
$sV2 = Say $qV2 "Yes, typed." -Route "window"
Advance 1
$script:trustAsked.Clear()
$p = PassTrust $trustYes
Check ($p.routed -eq 1 -and $null -eq (Verified-Of (Last-Post)) -and (Last-Post).from.label -ceq "F" -and $script:trustAsked.Count -eq 0) "an answer typed in the window: by label only, and the trust store is not asked"
$qV3 = Add-Question "Orc C" "Should the chat-recorded step go ahead?"
$sV3 = Say $qV3 "Yes, in chat." -Route "chat-recorded"
Advance 1
$p = PassTrust $trustYes
Check ($p.routed -eq 1 -and $null -eq (Verified-Of (Last-Post))) "an answer the warchief recorded from chat: by label only"
foreach ($case in @(@{ name = "revoked"; trust = $trustNo }, @{ name = "a machine's key"; trust = $trustMachine }, @{ name = "a trust store that cannot say"; trust = $trustBroken })) {
    $qx = Add-Question "Orc C" ("Should the " + $case.name + " step go ahead?")
    $sx = Say $qx "Yes, signed." -Route "phone"
    Advance 1
    $p = PassTrust $case.trust
    Check ($p.routed -eq 1 -and $null -eq (Verified-Of (Last-Post)) -and (Last-Post).from.label -ceq "F" -and @($p.lines | Where-Object { $_ -like "*by label only: *" }).Count -eq 1) ("a passkey that is " + $case.name + ": by label only, the answer still goes, and the line says why")
}
$qV4 = Add-Question "Orc C" "Should the reminded verified step go ahead?"
$sV4 = Say $qV4 "Yes, signed, and then left open." -Route "phone"
Advance 1
[void](PassTrust $trustYes)
Advance 70
[void](PassTrust $trustYes)
$nudgeV = @($script:posts | Where-Object { "$($_.body)" -clike ("UNCLOSED QUESTION " + $qV4 + ": *") })
Check ($nudgeV.Count -eq 1 -and $null -ne (Verified-Of $nudgeV[0]) -and (Verified-Of $nudgeV[0]).keyId -ceq $keyV) "the one reminder carries the same words, and the same verified founder"
# NOTHING NEW IS CLAIMED: the sender is still the router's own name, and no session id is made up.
Check ((Last-Post).from.sessionId -ceq "horde-decisions-route") "the sender is still the router, never a session it is not"

}
finally {
    $env:HORDE_HOME = $keepHome
    $env:WEZFLEET_ROOT = $keepFleet
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-HordeSuite -Success "each founder's answer reaches the Orc that asked exactly once, by any route, with a record that proves it; unresolvable askers go to the warchief; an answered question left open is flagged and reminded once; and only the asking Orc's ack closes it"
