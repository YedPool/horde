# CAN THE FOUNDER CHANGE HIS ANSWER (T-0152, his word on Q67: "On a phone it is easy to tap the wrong
# option") - AND DOES THE ORC THAT ACTED ON THE FIRST ONE HEAR OF IT, REPLY, AND GET HELD TO ITS WORD?
#
# decisions/Rules.ps1 (THE FOUNDER CHANGES HIS ANSWER), decisions/Operations.ps1 (say, change-reply),
# decisions/Route.ps1 (the notice) and decisions/Console.ps1 (the change-reply verb), held without any
# real messenger, any real session or real mail. The channel's two gates - a fresh passkey for a
# needsPasskey question, and the newest answer wins - are test/test-relay-decisions-change.ps1's; the
# page's button, box and status lines are decisions/page/test/browser-change.mjs's.
#   - WHAT A CHANGE IS: an ordinary answer of his that comes when an answer of his already stands to the
#     same part. The message says which answer it replaces and what that said; a first answer, a note, an
#     act, and an answer to another part say nothing of the kind. Newest stands.
#   - ACCEPTED WHILE OPEN, REFUSED BY NAME ONCE CLOSED: "This question is closed - Orc X has acted on it. To
#     change course, ask a follow-up." - for an answer of his by the window or the phone, naming whoever acted.
#     A first answer to a closed question is not a change, and his OTHER words (chat the keeper wrote down) are
#     kept under a closed question as they always were, marked as arrived after closing (coordinator, 10-17).
#   - THE ORC SAYS WHAT BECAME OF ITS WORK BEFORE IT CLOSES: an ack, or a close of a question an Orc asked, is
#     refused until change-reply has run for the change, with a sentence naming the command (review M1).
#   - A QUESTION THAT NEEDS A PASSKEY IS AUTHORIZED ONLY BY A PASSKEY: his words recorded from chat are kept and
#     shown, answer nothing, are routed as "not a passkey answer", and a passkey answer then authorizes it.
#   - THE ORC'S REPLY: one of three, only by the Orc that asked, only for a changed answer, cannot-undo only
#     with why, the newest reply to a change standing.
#   - THE EVENT: the asking Orc is routed the change with his OLD and NEW words and the time and the exact
#     reply commands, verified on the same terms as a first answer.
#   - THE VERB: the Orc is proven from its session, as for ack.
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


# --- this suite's own helpers ---
$keyV = "0123456789abcdef0123456789abcdef"
$script:trustAsked = New-Object System.Collections.ArrayList
$trustYes = { param([string]$KeyId) [void]$script:trustAsked.Add($KeyId); return (New-HordeKnown -Value ([pscustomobject]@{ proof = "webauthn" })) }
function PassTrust { param([scriptblock]$Trust) return (Invoke-HordeDecisionRoutePass -Clock $clock -Seat $seat -Analyst $analyst -HordeHome $hordeHome -Trust $Trust) }
function Last-Post { return $script:posts[$script:posts.Count - 1] }
function Verified-Of { param($Message) $v = $Message.from.PSObject.Properties["verified"]; if ($null -eq $v) { return $null }; return $v.Value }
function Test-FromHorde { param($Message) $f = $Message.from; return ($null -ne $f.PSObject.Properties["system"] -and "$($f.system)" -ceq "horde" -and $null -eq $f.PSObject.Properties["label"] -and $null -eq $f.PSObject.Properties["verified"]) }
function Try-Say {
    # The founder's words as a request, and the raw answer (so a refusal can be read).
    param([int]$Number, [string]$Text, [string]$Route = "window", [string]$Part = "")
    $r = @{ id = (New-Id); actor = "founder"; number = $Number; speaker = "founder"; route = $Route; text = $Text; wordingVersion = 1 }
    if ($Route -ceq "phone") { $r["evidence"] = ("{0:x64}" -f [long]($script:posts.Count + 91)); $r["signedBy"] = $keyV }
    if ($Part -ne "") { $r["part"] = $Part }
    return (Op "say" $r)
}
function Messages-Of { param([int]$Number) return @((Show $Number).thread.messages) }
function Changes-Of { param([int]$Number) $q = Show $Number; if ($null -eq $q.PSObject.Properties["answerChanges"]) { return @() }; return @($q.answerChanges) }
function Change-Reply {
    param([int]$Number, [string]$By, $Answer, [string]$Reply, [string]$Why = "", [string]$Actor = "orc")
    $r = @{ id = (New-Id); actor = $Actor; number = $Number; by = $By; answer = [long]$Answer; reply = $Reply }
    if ($Why -ne "") { $r["why"] = $Why }
    return (Op "change-reply" $r)
}
function Findings-Of { param($Answer) if ($Answer.state -cne "known") { return "unknown: " + $Answer.reason }; return (@($Answer.value.findings) -join " | ") }
$closedLine = { param([string]$Who) return ("This question is closed - " + $Who + " has acted on it. To change course, ask a follow-up.") }

try {

Write-Host ""
Write-Host "--- what a change is: an ordinary answer that comes when an answer of his already stands ---" -ForegroundColor Cyan
$qA = Add-Question "Orc C" "Should the first step go ahead?"
$a1 = Say $qA "Yes, go ahead."
$m = @(Messages-Of $qA)
Check ($m.Count -eq 1 -and $null -eq $m[0].PSObject.Properties["changedFrom"] -and @(Changes-Of $qA).Count -eq 0) "a first answer is no change: its message says nothing of one, and the question lists no change"
Advance 1
$a2 = Say $qA "No, wait."
$m = @(Messages-Of $qA)
Check ($m.Count -eq 2 -and [long](Get-HordeTestMember $m[1] "changedFrom") -eq $a1 -and (Get-HordeTestMember $m[1] "changedFromText") -ceq "Yes, go ahead.") "his second answer is a change: it names the record it replaces and the words that said"
$ch = @(Changes-Of $qA)
Check ($ch.Count -eq 1 -and [long]$ch[0].answer -eq $a2 -and [long]$ch[0].from -eq $a1 -and $ch[0].oldText -ceq "Yes, go ahead." -and $ch[0].newText -ceq "No, wait." -and $ch[0].orcShown -ceq "Orc C" -and $null -eq $ch[0].PSObject.Properties["reply"]) "the question lists it with the old and new words, the Orc to confirm, and no reply yet"
Advance 1
$a3 = Say $qA "Yes after all."
$m = @(Messages-Of $qA)
Check ([long](Get-HordeTestMember $m[2] "changedFrom") -eq $a2 -and @(Changes-Of $qA).Count -eq 2) "a third answer replaces the second: changes chain, each from the one before"
$qq = Op "show" @{ number = $qA }
Check ([long](Get-HordeDecisionStandingAnswer -Question $qq.value.question).sequence -eq $a3) "the newest answer is the one that stands"
$note = Op "say" @{ id = (New-Id); actor = "warchief"; number = $qA; speaker = "warchief"; route = "command"; text = "Noted."; asks = $false }
$park = Op "say" @{ id = (New-Id); actor = "founder"; number = $qA; speaker = "founder"; route = "window"; text = "Later."; wordingVersion = 1; act = "park" }
$m = @(Messages-Of $qA)
Check ($note.value.outcome -ceq "done" -and $park.value.outcome -ceq "done" -and $null -eq $m[3].PSObject.Properties["changedFrom"] -and $null -eq $m[4].PSObject.Properties["changedFrom"] -and @(Changes-Of $qA).Count -eq 2) "the keeper's note and his act (park) are no change"
$qP = Add-Question "Orc C" "Which of these steps go ahead?" -Parts @("(a) The first step", "(b) The second step")
$pa = Say $qP "Yes to a." -Part "a"
$pb = Say $qP "Yes to b." -Part "b"
$pb2 = Say $qP "No to b." -Part "b"
$pa2 = Say $qP "No to a." -Part "a"
$m = @(Messages-Of $qP)
Check ($null -eq $m[0].PSObject.Properties["changedFrom"] -and $null -eq $m[1].PSObject.Properties["changedFrom"] -and [long](Get-HordeTestMember $m[2] "changedFrom") -eq $pb -and [long](Get-HordeTestMember $m[3] "changedFrom") -eq $pa) "a part's answer changes only the answer to the SAME part"
$whole = Say $qP "Yes to both."
$m = @(Messages-Of $qP)
Check ($null -eq $m[4].PSObject.Properties["changedFrom"]) "an answer to the whole question is not a change of an answer to a part"
# ROUND 8: ONLY HIS OWN ANSWERS ARE EARLIER ANSWERS OF HIS. The keeper's words and his acts (park) are stepped over
# when the answer he replaces is looked for, and the keeper's words are never a change of anything of his.
$qK = Add-Question "Orc C" "Should the keeper step go ahead?"
Reply $qK "Which step do you mean?"
Reply $qK "Take your time."
$k1 = Say $qK "The first step."
$m = @(Messages-Of $qK)
Check ($m.Count -eq 3 -and $null -eq $m[1].PSObject.Properties["changedFrom"] -and $null -eq $m[2].PSObject.Properties["changedFrom"] -and @(Changes-Of $qK).Count -eq 0) "the keeper's words are no change of anything, and before his answer they are no earlier answer of his: his first answer is no change"
Advance 1
$k2 = Say $qK "The second step."
$m = @(Messages-Of $qK)
Check ([long](Get-HordeTestMember $m[3] "changedFrom") -eq $k1 -and (Get-HordeTestMember $m[3] "changedFromText") -ceq "The first step.") "and his second answer replaces his first, never the keeper's words before it"
$kPark = Op "say" @{ id = (New-Id); actor = "founder"; number = $qK; speaker = "founder"; route = "window"; text = "Later."; wordingVersion = 1; act = "park" }
$kUnpark = Op "say" @{ id = (New-Id); actor = "founder"; number = $qK; speaker = "founder"; route = "window"; text = "Now."; wordingVersion = 1; act = "unpark" }
Advance 1
$k3 = Say $qK "The third step."
$m = @(Messages-Of $qK)
Check ($kPark.value.outcome -ceq "done" -and $kUnpark.value.outcome -ceq "done" -and [long](Get-HordeTestMember $m[-1] "changedFrom") -eq $k2 -and (Get-HordeTestMember $m[-1] "changedFromText") -ceq "The second step." -and @(Changes-Of $qK).Count -eq 2) "his act (park, unpark) between two answers is no earlier answer of his: the third answer replaces the second"

Write-Host ""
Write-Host "--- accepted while the question is open, refused by name once it is closed ---" -ForegroundColor Cyan
$qC = Add-Question "Orc C" "Should the closing step go ahead?"
$c1 = Say $qC "Yes."
$c2 = Say $qC "No, hold on." -Route "phone"
Check ($c2 -gt $c1 -and @(Changes-Of $qC).Count -eq 1) "CONTROL: on an open question he changes his mind, from the window and from the phone, and it is taken"
Advance 1
$p = Pass
# M1: the Orc may not close over a change before it has said what became of its work. REFUSED without the reply...
$ak0 = Ack $qC "C" $c2
Check ($ak0.state -ceq "known" -and $ak0.value.outcome -ceq "refused" -and (Findings-Of $ak0) -like ("*horde decisions change-reply " + $qC + " -Answer " + $c2 + " -Reply <not-acted, undoing or cannot-undo>*") -and "$((Show $qC).state)" -ceq "open") ("M1: an ack of a changed answer is refused until the Orc has replied, naming the change-reply command (" + (Findings-Of $ak0) + ")")
$cl0 = Op "close" @{ id = (New-Id); actor = "orc"; number = $qC; outcome = "Closed by another Orc." }
Check ($cl0.value.outcome -ceq "refused" -and "$((Show $qC).state)" -ceq "open") ("S3: an Orc cannot close it at all - only the warchief changes the list (" + (Findings-Of $cl0) + ")")
$cl0 = Op "close" @{ id = (New-Id); actor = "warchief"; number = $qC; outcome = "   " }
Check ($cl0.value.outcome -ceq "refused" -and "$((Show $qC).state)" -ceq "open") ("S3: the warchief's close with no words of outcome is refused too (" + (Findings-Of $cl0) + ")")
# ...and ALLOWED after it.
$rp0 = Change-Reply $qC "C" $c2 "not-acted"
$ak = Ack $qC "C" $c2
Check ($rp0.value.outcome -ceq "done") "M1 twin: the Orc replies to the change"
Check ($ak.state -ceq "known" -and $ak.value.outcome -ceq "done" -and "$($ak.value.question.state)" -ceq "closed" -and "$($ak.value.question.actedBy)" -ceq "Orc C") "Orc C acknowledges the answer that stands: the question is closed, and the view says Orc C acted on it"
$before = @(Messages-Of $qC).Count
foreach ($route in @("window", "phone")) {
    $r = Try-Say $qC ("A change by " + $route) -Route $route
    Check ($r.state -ceq "known" -and $r.value.outcome -ceq "refused" -and (Findings-Of $r) -ceq (& $closedLine "Orc C")) ("a change to a closed question by route " + $route + " is refused by name: " + (Findings-Of $r))
}
Check (@(Messages-Of $qC).Count -eq $before -and "$((Show $qC).state)" -ceq "closed") "and nothing is written: the thread is as it was, the question closed"
# THE COORDINATOR'S RULING (10-17), each side: only a REPLACEMENT of his answer is refused. His chat words are kept.
$chatLate = Op "say" @{ id = (New-Id); actor = "warchief"; number = $qC; speaker = "founder"; route = "chat-recorded"; text = "Wait - and also use blue." }
Check ($chatLate.state -ceq "known" -and $chatLate.value.outcome -ceq "done" -and $chatLate.value.message.arrivedAfterClosing -eq $true -and "$((Show $qC).state)" -ceq "closed" -and @(Messages-Of $qC).Count -eq $before + 1) "MUST-ACCEPT: his chat words under a closed question are kept verbatim, marked as arrived after closing, and reopen nothing"
Check (@(Messages-Of $qC)[-1].text -ceq "Wait - and also use blue.") "and they are kept word for word"
$qD = Add-Question "Orc D" "Should the other closing step go ahead?"
[void](Say $qD "Yes.")
$cl = Op "close" @{ id = (New-Id); actor = "warchief"; number = $qD; outcome = "Done by hand." }
$r = Try-Say $qD "No."
Check ($cl.value.outcome -ceq "done" -and (Findings-Of $r) -ceq (& $closedLine "Orc D")) "a question the warchief closed by hand names the Orc that asked it, who acted: Orc D"
$qM = Add-Question "M (Thrall)" "Should the warchief's own step go ahead?"
[void](Say $qM "Yes.")
[void](Op "close" @{ id = (New-Id); actor = "warchief"; number = $qM; outcome = "Done." })
$r = Try-Say $qM "No."
Check ((Findings-Of $r) -ceq (& $closedLine "the warchief")) "a question the warchief asked itself names the warchief"
$qE = Add-Question "Orc C" "Should the never answered step go ahead?"
[void](Op "close" @{ id = (New-Id); actor = "warchief"; number = $qE; outcome = "Dropped." })
$r = Try-Say $qE "Yes, late."
Check ($r.state -ceq "known" -and $r.value.outcome -ceq "done" -and $r.value.message.arrivedAfterClosing -eq $true) "MUST-ACCEPT TWIN: a FIRST answer to a closed question is no change; it is kept, flagged as arrived after closing"
$qPC = Add-Question "Orc C" "Which of the closing steps go ahead?" -Parts @("(a) The first step", "(b) The second step")
[void](Say $qPC "Yes to a." -Part "a")
[void](Op "close" @{ id = (New-Id); actor = "warchief"; number = $qPC; outcome = "Done." })
$r = Try-Say $qPC "No to a." -Part "a"
Check ((Findings-Of $r) -ceq (& $closedLine "Orc C")) "a part answered before the question closed cannot be changed after it"
$r = Try-Say $qPC "Yes to b, late." -Part "b"
Check ($r.state -ceq "known" -and $r.value.outcome -ceq "done") "MUST-ACCEPT TWIN: the first answer to another part is no change of that part's answer, and is kept"
$r = Op "say" @{ id = (New-Id); actor = "warchief"; number = $qC; speaker = "warchief"; route = "command"; text = "For the record."; asks = $false }
Check ($r.value.outcome -ceq "done") "and the keeper's note under a closed question is kept as it always was"
$r = Op "say" @{ id = (New-Id); actor = "founder"; number = $qC; speaker = "founder"; route = "window"; text = "Later."; wordingVersion = 1; act = "park" }
Check ($r.value.outcome -ceq "done") "and so is his act (park)"
Check ("$((Show $qE).actedBy)" -ceq "Orc C" -and $null -eq (Show $qA).PSObject.Properties["actedBy"]) "the view says who acted on a closed question and says nothing for an open one"

Write-Host ""
Write-Host "--- the Orc's reply: one of three, only by the Orc that asked, only for a changed answer ---" -ForegroundColor Cyan
$qR = Add-Question "Orc C" "Should the reply step go ahead?"
$r1 = Say $qR "Yes, go."
Advance 1
$r2 = Say $qR "No, stop."
$bad = Change-Reply $qR "D" $r2 "not-acted"
Check ($bad.value.outcome -ceq "refused" -and (Findings-Of $bad) -like "*was asked by 'Orc C', not by Orc D*") ("another Orc's reply is refused: " + (Findings-Of $bad))
$bad = Change-Reply $qR "C" $r1 "undoing"
Check ($bad.value.outcome -ceq "refused" -and (Findings-Of $bad) -like "*which is not a changed answer of the founder under question*") ("a reply to a FIRST answer is refused: " + (Findings-Of $bad))
$bad = Change-Reply $qR "C" $r2 "maybe"
Check ($bad.state -ceq "known" -and $bad.value.outcome -ceq "refused" -and (Findings-Of $bad) -ceq "request.reply is 'maybe', not one of: not-acted, undoing, cannot-undo") ("a reply that is none of the three is refused by the request's schema, naming the three: " + (Findings-Of $bad))
$bad = Change-Reply $qR "C" $r2 "cannot-undo"
Check ($bad.value.outcome -ceq "refused" -and (Findings-Of $bad) -like "*says why*") ("cannot-undo without why is refused: " + (Findings-Of $bad))
$bad = Change-Reply $qR "C" $r2 "not-acted" -Why "because"
Check ($bad.value.outcome -ceq "refused" -and (Findings-Of $bad) -like "*a reason is given only with the reply 'cannot-undo'*") ("a reason with a reply that needs none is refused: " + (Findings-Of $bad))
$bad = Change-Reply $qR "C" $r2 "not-acted" -Actor "warchief"
Check ($bad.value.outcome -ceq "refused" -and (Findings-Of $bad) -like "*is not a role that may say what became of its work*") ("the warchief cannot reply for an Orc: " + (Findings-Of $bad))
Check (@(Changes-Of $qR).Count -eq 1 -and $null -eq (Changes-Of $qR)[0].PSObject.Properties["reply"]) "CONTROL: none of those left a reply behind"
$ok = Change-Reply $qR "C" $r2 "not-acted"
$rep = (Changes-Of $qR)[0].PSObject.Properties["reply"]
Check ($ok.value.outcome -ceq "done" -and $null -ne $rep -and $rep.Value.reply -ceq "not-acted" -and $rep.Value.replyShown -ceq "not acted yet, using the new answer" -and $rep.Value.by -ceq "C") "not-acted is taken, and shown in its plain words"
$ok = Change-Reply $qR "C" $r2 "undoing"
Check ($ok.value.outcome -ceq "done" -and (Changes-Of $qR)[0].reply.replyShown -ceq "already acted, undoing") "a later reply stands over the earlier one: undoing"
$ok = Change-Reply $qR "C" $r2 "cannot-undo" -Why "the deploy already went out"
Check ($ok.value.outcome -ceq "done" -and (Changes-Of $qR)[0].reply.replyShown -ceq "already acted, cannot undo" -and (Changes-Of $qR)[0].reply.why -ceq "the deploy already went out") "cannot-undo is taken with its reason"
Advance 1
$r3 = Say $qR "Back to yes."
Check (@(Changes-Of $qR).Count -eq 2 -and $null -ne (Changes-Of $qR)[0].PSObject.Properties["reply"] -and $null -eq (Changes-Of $qR)[1].PSObject.Properties["reply"]) "a newer change has no reply until the Orc gives it: replies belong to the change they name"
$lines = Change-Reply $qR "C" $r3 "cannot-undo" -Why ("a" + [char]10 + "b")
Check ($lines.value.outcome -ceq "refused") "a reason of more than one line is refused"
$h = @((Show $qR).history | Where-Object { $_.kind -ceq "answer-change-replied" })
Check ($h.Count -eq 3 -and $h[2].note -ceq "answer change replied by Orc C: already acted, cannot undo") "each reply is in the question's history"
$qMM = Add-Question "M (Thrall)" "Should the warchief's reply step go ahead?"
$mm1 = Say $qMM "Yes."
$mm2 = Say $qMM "No."
$bad = Change-Reply $qMM "C" $mm2 "undoing"
Check ($bad.value.outcome -ceq "refused" -and (Findings-Of $bad) -like "*was asked by 'M (Thrall)', not by Orc C*") "a question no Orc asked takes no Orc's reply"
Check ((Changes-Of $qMM)[0].orcShown -ceq "") "and the view names no Orc to wait for"
$qZ = Add-Question "Orc C" "Should the late reply step go ahead?"
$z1 = Say $qZ "Yes."; $z2 = Say $qZ "No."
[void](Pass)
$zr = Change-Reply $qZ "C" $z2 "not-acted"
$z = Ack $qZ "C" $z2
$late = Change-Reply $qZ "C" $z2 "undoing"
Check ($zr.value.outcome -ceq "done" -and $z.value.outcome -ceq "done" -and $late.value.outcome -ceq "done") "an Orc that closed the question may still change what it said became of the change"

Write-Host ""
Write-Host "--- the event: the asking Orc is routed the change, old and new, with the time and the reply commands ---" -ForegroundColor Cyan
$qN = Add-Question "Orc C" "Should the notice step go ahead?"
$n1 = Say $qN "Yes, ship it." -Route "phone"
Advance 1
$p = PassTrust $trustYes
$first = "$((Last-Post).body)"
Check ($p.routed -ge 1 -and $first.StartsWith("FOUNDER ANSWER to your question " + $qN) -and -not $first.Contains("CHANGED") -and -not $first.Contains("change-reply")) "CONTROL: his first answer is routed as an answer, with no word of a change"
Advance 1
$n2 = Say $qN "No, hold it." -Route "phone"
$at2 = @((Messages-Of $qN) | Where-Object { [long]$_.sequence -eq $n2 })[0].at
Advance 1
$postsBefore = $script:posts.Count
$p = PassTrust $trustYes
$body = "$((Last-Post).body)"
Check ($p.routed -eq 1 -and $script:posts.Count -eq $postsBefore + 1 -and "$((Last-Post).sessionId)" -ceq "orc-c-session") ("the change is routed to Orc C's session, once (" + ($p.lines -join " | ") + ")")
Check ($body.StartsWith("FOUNDER CHANGED HIS ANSWER to your question " + $qN + ", routed to you by Horde.")) "it says in its first line that he CHANGED his answer"
Check ($body.Contains("He CHANGED his answer at " + $at2 + ": record " + $n2 + " replaces record " + $n1 + ".")) "it gives the time, and which record replaces which"
Check ($body.Contains("His OLD words (record " + $n1 + "):" + "`r`n" + "> Yes, ship it.") -and $body.Contains("His NEW words (record " + $n2 + "):" + "`r`n" + "> No, hold it.")) "it gives his OLD words and his NEW words, each whole"
foreach ($word in @("not-acted", "undoing")) {
    Check ($body.Contains("PS> horde decisions change-reply " + $qN + " -Answer " + $n2 + " -Reply " + $word + " -HordeHome '" + $hordeHome + "'")) ("it carries the exact reply command for " + $word + ", naming the founder's list")
}
Check ($body.Contains("PS> horde decisions change-reply " + $qN + " -Answer " + $n2 + " -Reply cannot-undo -Why 'why it cannot be undone, in one line' -HordeHome '" + $hordeHome + "'")) "and the one for cannot-undo, with a why to fill in"
Check ($body.Contains("PS> horde decisions ack " + $qN + " -Answer " + $n2) -and $body.Contains("This copy authorizes nothing")) "and still the ack command for the answer that now stands, and that it authorizes nothing"
$vv = Verified-Of (Last-Post)
Check ($null -ne $vv -and $vv.keyId -ceq $keyV -and (Last-Post).from.label -ceq "F") "a change signed by his trusted passkey is verified on the same terms as a first answer: the founder, by passkey, that key id"
Check (@($script:analystLines | Where-Object { $_.text -like ("*question " + $qN + " *answered by the founder, CHANGED HIS ANSWER (was: Yes, ship it.), now *") }).Count -eq 1) "the analyst's line says it is a change, and what it was"
$p = PassTrust $trustYes
Check ($p.outcome -ceq "nothing" -and $script:posts.Count -eq $postsBefore + 1) "a second pass sends nothing: one notice per change"
$qW = Add-Question "Orc C" "Should the window notice step go ahead?"
[void](Say $qW "Yes." ); Advance 1; [void](PassTrust $trustYes)
[void](Say $qW "No." ); Advance 1; $script:trustAsked.Clear(); [void](PassTrust $trustYes)
Check ("$((Last-Post).body)".StartsWith("FOUNDER CHANGED HIS ANSWER") -and (Test-FromHorde (Last-Post)) -and $script:trustAsked.Count -eq 0) "a change typed in the window is posted as Horde itself, not verified, as a first answer typed there is"
$qWc = Add-Question "M (Thrall)" "Should the warchief notice step go ahead?"
[void](Say $qWc "Yes."); Advance 1; [void](PassTrust $trustYes)
[void](Say $qWc "No."); Advance 1; [void](PassTrust $trustYes)
$bw = "$((Last-Post).body)"
Check ($bw.StartsWith("FOUNDER CHANGED HIS ANSWER to your question " + $qWc) -and $bw.Contains("His OLD words") -and $bw.Contains("> Yes.") -and -not $bw.Contains("change-reply")) "a question the warchief asked: the warchief is told of the change, old and new, and given no reply command (only an Orc replies)"

Write-Host ""
Write-Host "--- the command line: change-reply proves which Orc runs it ---" -ForegroundColor Cyan
$qCli = Add-Question "Orc D" "Should the command-line change step go ahead?"
$k1 = Say $qCli "Yes."
$k2 = Say $qCli "No."
$asD = { return [pscustomobject]@{ ok = $true; reason = ""; sessionId = "orc-d-session"; label = "D" } }
$asC = { return [pscustomobject]@{ ok = $true; reason = ""; sessionId = "orc-c-session"; label = "C" } }
$asC3 = { return [pscustomobject]@{ ok = $true; reason = ""; sessionId = "c3-session"; label = "C3" } }
$seatOk = { param($Who) return [pscustomobject]@{ ok = $true; reason = "" } }
$seatNo = { param($Who) return [pscustomobject]@{ ok = $false; reason = "another session wears the label" } }
$nobody = { return [pscustomobject]@{ ok = $false; reason = "no notice was sent: this is not run from inside a session (no id)"; sessionId = ""; label = "" } }
Check (Throws { Invoke-HordeDecisionCommand -Verb "change-reply" -Given @{ Number = "$qCli"; Answer = "$k2"; Reply = "undoing" } -Sender $nobody -SeatProof $seatOk } "decisions change-reply is run by the Orc that asked, from inside its own session, and which session this is could not be proven: this is not run from inside a session (no id)") "run outside a session: refused, saying why"
Check (Throws { Invoke-HordeDecisionCommand -Verb "change-reply" -Given @{ Number = "$qCli"; Answer = "$k2"; Reply = "undoing" } -Sender $asC3 -SeatProof $seatOk } "this session's fleet label is 'C3', which is not an Orc's lane letter") "run by a session that is no Orc: refused"
Check (Throws { Invoke-HordeDecisionCommand -Verb "change-reply" -Given @{ Number = "$qCli"; Answer = "$k2"; Reply = "undoing" } -Sender $asD -SeatProof $seatNo } "this session is not proven to be Orc D") "run by a session that does not hold the Orc's seat: refused"
Check (Throws { Invoke-HordeDecisionCommand -Verb "change-reply" -Given @{ Number = "$qCli"; Reply = "undoing" } -Sender $asD -SeatProof $seatOk } "needs -Answer <record>") "no -Answer: refused, saying what to give"
Check (Throws { Invoke-HordeDecisionCommand -Verb "change-reply" -Given @{ Number = "$qCli"; Answer = "x"; Reply = "undoing" } -Sender $asD -SeatProof $seatOk } "-Answer is the record of the changed answer") "an -Answer that is not a record's number: refused"
Check (Throws { Invoke-HordeDecisionCommand -Verb "change-reply" -Given @{ Number = "$qCli"; Answer = "$k2" } -Sender $asD -SeatProof $seatOk } "needs -Reply <not-acted, undoing or cannot-undo>") "no -Reply: refused, saying what to give"
Check (Throws { Invoke-HordeDecisionCommand -Verb "change-reply" -Given @{ Number = "$qCli"; Answer = "$k2"; Reply = "cannot-undo"; Why = "a`nb" } -Sender $asD -SeatProof $seatOk } "-Why is one line") "a -Why of more than a line: refused"
Check (Throws { Invoke-HordeDecisionCommand -Verb "change-reply" -Given @{ Number = "$qCli"; Answer = "$k2"; Reply = "undoing"; Peek = $true } -Sender $asD -SeatProof $seatOk } "does not belong to decisions change-reply") "a flag of another verb: refused"
$waiting = @((Invoke-HordeDecisionCommand -Verb "show" -Given @{ Number = "$qCli" }).lines)
Check (@($waiting | Where-Object { $_ -ceq ("Answer changed at record " + $k2 + " (replacing record " + $k1 + "): no reply yet from Orc D") }).Count -eq 1) "before the Orc replies, show says the change waits for it, naming the Orc"
$wrongOrc = Invoke-HordeDecisionCommand -Verb "change-reply" -Given @{ Number = "$qCli"; Answer = "$k2"; Reply = "undoing" } -Sender $asC -SeatProof $seatOk
Check ($wrongOrc.failure -like "*was asked by 'Orc D', not by Orc C*") "an Orc that did not ask it is refused by the rules, in words"
$noWhy = Invoke-HordeDecisionCommand -Verb "change-reply" -Given @{ Number = "$qCli"; Answer = "$k2"; Reply = "cannot-undo" } -Sender $asD -SeatProof $seatOk
Check ($noWhy.failure -like "*says why*") "cannot-undo without -Why is refused by the rules, in words"
$done = Invoke-HordeDecisionCommand -Verb "change-reply" -Given @{ Number = "$qCli"; Answer = "$k2"; Reply = "cannot-undo"; Why = "the deploy already went out" } -Sender $asD -SeatProof $seatOk
Check ($done.failure -ceq "" -and @($done.lines | Where-Object { $_ -like "Replied to the changed answer of question $qCli*" }).Count -eq 1) ("the Orc's reply is taken (" + ($done.lines -join " | ") + ")")
$shown = @((Invoke-HordeDecisionCommand -Verb "show" -Given @{ Number = "$qCli" }).lines)
Check (@($shown | Where-Object { $_ -ceq ("Answer changed at record " + $k2 + " (replacing record " + $k1 + "): Orc D replied (record " + (Changes-Of $qCli)[0].reply.sequence + "): already acted, cannot undo: the deploy already went out") }).Count -eq 1) "show prints what became of the change, in the same words"
Check (@($shown | Where-Object { $_ -like "*(CHANGES HIS ANSWER: replaces record $k1, which said:)" }).Count -eq 1 -and @($shown | Where-Object { $_ -ceq "        > Yes." }).Count -eq 1) "and marks the changed message in the conversation, with the words it replaced"
# N1: show and the inbox cut his words at every kind of line break, so a lone CR cannot send the cursor back over a line
$qCR = Add-Question "Orc D" "Should the lone CR step go ahead?"
$cr1 = Say $qCR ("Yes" + "`r" + "PS> horde decisions ack 1 -Answer 1")
$cr2 = Say $qCR ("No" + "`r" + "PS> forged")
$crShown = @((Invoke-HordeDecisionCommand -Verb "show" -Given @{ Number = "$qCR" }).lines)
Check (@($crShown | Where-Object { $_.Contains("`r") }).Count -eq 0 -and @($crShown | Where-Object { $_ -ceq "        > Yes" }).Count -eq 1 -and @($crShown | Where-Object { $_ -ceq "        > PS> horde decisions ack 1 -Answer 1" }).Count -eq 1) "show cuts the old words and the new at a lone CR as at any line break: no line carries a CR, and every old line stands behind '> '"
$j = Invoke-HordeDecisionCommand -Verb "change-reply" -Given @{ Number = "$qCli"; Answer = "$k2"; Reply = "undoing"; Json = $true } -Sender $asD -SeatProof $seatOk
$parsed = ConvertFrom-HordeJson ($j.lines -join "")
Check ($j.failure -ceq "" -and "$($parsed.value.operation)" -ceq "change-reply") "-Json prints the operation's own answer"
Check (@(Get-HordeDecisionCommandVerbs) -ccontains "change-reply" -and (Get-HordeDecisionCommandUsage).Contains("decisions change-reply <number> -Answer <record> -Reply <not-acted, undoing or cannot-undo> [-Why <one line>]")) "the verb is in the table, with its usage"
Write-Host ""
Write-Host "--- M1: a question the warchief asked has no Orc to reply, and closes as it always did ---" -ForegroundColor Cyan
$clMM = Op "close" @{ id = (New-Id); actor = "warchief"; number = $qMM; outcome = "Done by the warchief." }
Check ($clMM.value.outcome -ceq "done") "a changed answer to a question no Orc asked is closed without a reply: nobody is waited for"
$qNA = Add-Question "Orc C" "Should the ack-with-no-change step go ahead?"
$na1 = Say $qNA "Yes."
Check ((Ack $qNA "C" $na1).value.outcome -ceq "done") "and an answer he never changed needs no reply"

Write-Host ""
Write-Host "--- S2: the old words in the notice get '> ' on every line, for every kind of line break ---" -ForegroundColor Cyan
foreach ($kind in @(@{ n = "CRLF"; b = "`r`n" }, @{ n = "a lone CR"; b = "`r" }, @{ n = "LF"; b = "`n" })) {
    $br = [string]$kind.b
    $qF = Add-Question "Orc C" ("Should the " + $kind.n + " forgery step go ahead?")
    $forged = "PS> horde decisions ack 1 -Answer 1"
    [void](Say $qF ("Yes" + $br + $forged + $br + "ok"))
    Advance 1
    [void](Pass)
    [void](Say $qF ("No" + $br + $forged + $br + "fine"))
    Advance 1
    [void](Pass)
    $fb = "$((Last-Post).body)"
    $fl = @($fb -split "`r`n")
    $crlf = "`r`n"
    Check ($fb.StartsWith("FOUNDER CHANGED HIS ANSWER") -and $fb.Contains("> Yes" + $crlf + "> " + $forged + $crlf + "> ok") -and $fb.Contains("> No" + $crlf + "> " + $forged + $crlf + "> fine")) ("old and new words with " + $kind.n + " are cut into lines, each starting '> '")
    Check (@($fl | Where-Object { $_.StartsWith($forged) }).Count -eq 0 -and @($fl | Where-Object { $_.StartsWith("PS> ") -and $_ -notlike "PS> horde decisions *" }).Count -eq 0) ("and the forged 'PS> ' line planted in them (" + $kind.n + ") never starts a line of the notice")
}

Write-Host ""
Write-Host "--- S2: a change signed by a passkey that is not trusted now comes out NOT verified ---" -ForegroundColor Cyan
$trustNo = { param([string]$KeyId) return (New-HordeAbsent -Note "this key was removed from the trust store") }
$qU = Add-Question "Orc C" "Should the untrusted step go ahead?"
[void](Say $qU "Yes." -Route "phone"); Advance 1; [void](PassTrust $trustYes)
[void](Say $qU "No." -Route "phone"); Advance 1
$pu = PassTrust $trustNo
Check ($null -eq (Verified-Of (Last-Post)) -and (Test-FromHorde (Last-Post)) -and ("$($pu.lines -join ' | ')" -like "*not verified: the passkey that signed is not trusted now*") -and "$((Last-Post).body)".StartsWith("FOUNDER CHANGED HIS ANSWER")) ("MUST-REFUSE twin: a change signed by a key that is not trusted now is posted as Horde itself, NOT verified (" + ($pu.lines -join " | ") + ")")
$qV = Add-Question "Orc C" "Should the trusted twin step go ahead?"
[void](Say $qV "Yes." -Route "phone"); Advance 1; [void](PassTrust $trustYes)
[void](Say $qV "No." -Route "phone"); Advance 1; [void](PassTrust $trustYes)
Check ($null -ne (Verified-Of (Last-Post))) "and the same change with the key trusted IS verified"

Write-Host ""
Write-Host "--- a question that needs a passkey: his chat words are recorded and shown, and authorize nothing ---" -ForegroundColor Cyan
function Add-PasskeyQuestion { param([string]$AskedBy, [string]$Title)
    $a = Op "add" @{ id = (New-Id); actor = "warchief"; needsPasskey = $true; question = @{ title = $Title; kind = "yes-no"; whatItIs = "A step is ready."; group = "A group"; askedBy = $AskedBy; waiting = @($AskedBy) } }
    if ($a.state -cne "known" -or $a.value.outcome -cne "done") { throw ("the question was not added: " + $a.reason) }
    return [int]$a.value.number }
$qK = Add-PasskeyQuestion "Orc C" "Should the passkey step go ahead?"
$k0 = Say $qK "Yes, do it." -Route "chat-recorded"
$vk = Show $qK
Check ($vk.needsPasskey -eq $true -and @(Messages-Of $qK).Count -eq 1 -and @(Messages-Of $qK)[0].text -ceq "Yes, do it." -and $vk.thread.turn -ceq "founder") "RECORDED AND SHOWN, NOT AUTHORIZING: from chat on a needsPasskey question the words are in the thread, and it is still the founder's turn"
Check ($null -eq (Get-HordeDecisionStandingAnswer -Question $vk) -and $null -ne @(Messages-Of $qK)[0].PSObject.Properties["notPasskey"]) "no answer stands, and the message says it is not a passkey answer"
Advance 1
$pk = PassTrust $trustYes
$nb = "$((Last-Post).body)"
Check ($pk.routed -eq 1 -and $nb.StartsWith("FOUNDER'S CHAT WORDS, NOT A PASSKEY ANSWER") -and $nb.Contains("THIS IS NOT A PASSKEY ANSWER") -and -not $nb.Contains("PS> horde decisions ack") -and $null -eq (Verified-Of (Last-Post))) "ROUTED, BUT SAID PLAINLY: the notice is not a passkey answer, offers no ack, and is not posted as verified"
$ackNo = Ack $qK "C" $k0
Check ($ackNo.value.outcome -ceq "refused" -and (Findings-Of $ackNo) -like "*needs a passkey*" -and "$((Show $qK).state)" -ceq "open") ("the Orc cannot acknowledge his chat words as the answer: " + (Findings-Of $ackNo))
Check (@((Op "list" @{ state = "all" }).value.unclosed | Where-Object { [int]$_.number -eq $qK }).Count -eq 0) "and the question is not flagged as answered-and-unclosed"
$k1 = Say $qK "Yes, by passkey." -Route "phone"
$vk = Show $qK
Check ([long](Get-HordeDecisionStandingAnswer -Question $vk).sequence -eq $k1 -and $vk.thread.turn -ceq "warchief" -and $null -eq @(Messages-Of $qK)[1].PSObject.Properties["changedFrom"]) "THEN A PASSKEY ANSWER AUTHORIZES IT: it stands, the turn passes, and it is a FIRST answer (his chat words were never an answer to change)"
Advance 1
[void](PassTrust $trustYes)
Check ($null -ne (Verified-Of (Last-Post)) -and "$((Last-Post).body)".StartsWith("FOUNDER ANSWER")) "and its notice is the ordinary verified one"
$k2 = Say $qK "Actually no, from chat." -Route "chat-recorded"
$vk = Show $qK
Check ([long](Get-HordeDecisionStandingAnswer -Question $vk).sequence -eq $k1 -and @(Changes-Of $qK).Count -eq 0 -and $null -ne @(Messages-Of $qK)[2].PSObject.Properties["notPasskey"]) "A CHANGE FROM CHAT does not displace the passkey answer: it is recorded, shown as not a passkey answer, and is no change of the standing answer"
Advance 1
[void](PassTrust $trustYes)
Check ("$((Last-Post).body)".StartsWith("FOUNDER'S CHAT WORDS, NOT A PASSKEY ANSWER") -and $null -eq (Verified-Of (Last-Post))) "and it is routed as not a passkey answer"
Check ((Ack $qK "C" $k1).value.outcome -ceq "done") "the Orc acknowledges the passkey answer that stands"
$qK2 = Add-PasskeyQuestion "Orc C" "Should the command-line passkey step go ahead?"
$cliAns = Invoke-HordeDecisionCommand -Verb "answer" -Given @{ Number = "$qK2"; Text = "Yes, typed in chat." }
Check ($cliAns.failure -ceq "" -and @($cliAns.lines | Where-Object { $_ -like ("  NOTE: question " + $qK2 + " needs a passkey. These words are kept and shown, but they are NOT a passkey answer*") }).Count -eq 1) ("horde decisions answer says plainly that the words are kept and are not a passkey answer (" + ($cliAns.lines -join " | ") + ")")
$qOK = Add-Question "Orc C" "Should the ordinary chat step go ahead?"
$o1 = Say $qOK "Yes, chat." -Route "chat-recorded"
Check ([long](Get-HordeDecisionStandingAnswer -Question (Show $qOK)).sequence -eq $o1 -and (Show $qOK).thread.turn -ceq "warchief") "CONTROL: a question that does NOT need a passkey is still answered by his chat words, as it always was"

Write-Host ""
Write-Host "--- S3: the warchief's way out when the asking Orc never replies ---" -ForegroundColor Cyan
# M1 (review 3): the CLI sends every write as the actor "warchief", so a close over an unreplied change relies on
# a PROVEN seat. The session that runs the command is proven as ack proves an Orc (the sender, then the seat
# the fleet's records give the role); the seam hands in a fleet of this suite's own: only warchief-session-1
# holds the warchief's seat.
$asM = { return [pscustomobject]@{ ok = $true; reason = ""; sessionId = "warchief-session-1"; label = "M" } }
$seatByRole = { param($Who, $Role)
    if ($Role -ceq "warchief" -and "$($Who.sessionId)" -ceq "warchief-session-1") { return [pscustomobject]@{ ok = $true; reason = "" } }
    return [pscustomobject]@{ ok = $false; reason = "that session does not hold the seat" } }
$qW = Add-Question "Orc C" "Should the abandoned step go ahead?"
[void](Say $qW "Yes.")
$w2 = Say $qW "No, stop." -Route "phone"
Advance 1
$outW = "Orc C is retired; nothing was deployed."
$clW0 = Op "close" @{ id = (New-Id); actor = "warchief"; number = $qW; outcome = $outW }
Check ($clW0.value.outcome -ceq "refused" -and "$((Show $qW).state)" -ceq "open" -and (Findings-Of $clW0) -like "*Run change-reply first*") ("M1: the actor 'warchief' alone proves nothing: a close with no proof of the seat is refused, and says to run change-reply first (" + (Findings-Of $clW0) + ")")
$cliOrc = Invoke-HordeDecisionCommand -Verb "close" -Given @{ Number = "$qW"; Outcome = "closed by whoever ran the CLI" } -Sender $asC -SeatProof $seatByRole
Check ($cliOrc.failure -like "*Run change-reply first*" -and "$((Show $qW).state)" -ceq "open" -and @(Messages-Of $qW).Count -eq 2) ("M1 MUST-REFUSE: from a session registered as Orc C, `horde decisions close` over an unreplied change is refused, in words that send the Orc to change-reply (" + $cliOrc.failure + ")")
$cliNone = Invoke-HordeDecisionCommand -Verb "close" -Given @{ Number = "$qW"; Outcome = "closed by nobody I can prove" } -Sender $nobody -SeatProof $seatByRole
$cliNone2 = Invoke-HordeDecisionCommand -Verb "close" -Given @{ Number = "$qW"; Outcome = "closed by nobody I can prove" } -Sender $nobody -SeatProof $seatOk
Check ($cliNone.failure -like "*Run change-reply first*" -and $cliNone2.failure -like "*Run change-reply first*" -and "$((Show $qW).state)" -ceq "open") "M1 MUST-REFUSE: from a session that cannot be proven at all, the same close is refused, whatever a seat reader would say"
$cliBlank = Invoke-HordeDecisionCommand -Verb "close" -Given @{ Number = "$qW"; Outcome = "   " } -Sender $asM -SeatProof $seatByRole
Check ($cliBlank.failure -ne "" -and "$((Show $qW).state)" -ceq "open") ("M1: even the proven warchief seat cannot close with no words of outcome (" + $cliBlank.failure + ")")
$cliM = Invoke-HordeDecisionCommand -Verb "close" -Given @{ Number = "$qW"; Outcome = $outW } -Sender $asM -SeatProof $seatByRole
$vW = Show $qW
Check ($cliM.failure -ceq "" -and "$($vW.state)" -ceq "closed" -and $vW.outcome -ceq $outW -and $vW.warchiefClosedUnreplied -eq $true) ("[" + $cliM.failure + "|" + $vW.state + "|" + $vW.warchiefClosedUnreplied + "] M1 MUST-ACCEPT: from the proven warchief seat the same close goes through, and the view says the warchief closed it over a change with no reply (the page then says 'The warchief closed it')")
Check ($null -eq (Show $qC).PSObject.Properties["warchiefClosedUnreplied"] -and $null -eq (Show $qE).PSObject.Properties["warchiefClosedUnreplied"]) "S3 twin: a close after the Orc's reply, and a close with no change, say nothing of the kind"
$qW2 = Add-Question "Orc C" "Should the second abandoned step go ahead?"
[void](Say $qW2 "Yes."); [void](Say $qW2 "No." -Route "phone")
$clW2 = Op "close" @{ id = (New-Id); actor = "orc"; number = $qW2; outcome = "I am another Orc." }
$ackW2 = Ack $qW2 "D" ([long](Get-HordeDecisionStandingAnswer -Question (Show $qW2)).sequence)
Check ($clW2.value.outcome -ceq "refused" -and $ackW2.value.outcome -ceq "refused" -and "$((Show $qW2).state)" -ceq "open") "S3 MUST-REFUSE: an Orc other than the asker can neither close nor acknowledge it"
$ak2 = Ack $qW2 "C" ([long](Get-HordeDecisionStandingAnswer -Question (Show $qW2)).sequence)
Check ($ak2.value.outcome -ceq "refused" -and (Findings-Of $ak2) -like "*Run change-reply first*" -and (Findings-Of $ak2) -notlike "*then close the question*") ("M1: the ack refusal tells the Orc to run change-reply first and no longer points it at close (" + (Findings-Of $ak2) + ")")

Write-Host ""
Write-Host "--- S3: the Orc is told when the warchief closes its question ---" -ForegroundColor Cyan
$cNotice = { param([int]$Number) return @($script:posts | Where-Object { "$($_.body)".StartsWith("The warchief closed question " + $Number + ":") }) }
$beforeN = $script:posts.Count
[void](PassTrust $trustYes)
$nW = @(& $cNotice $qW)
Check ($nW.Count -eq 1 -and "$($nW[0].sessionId)" -ceq "orc-c-session") "S3: closed over an unreplied change, the asking Orc is routed one notice"
$bodyW = "$($nW[0].body)"
Check ($bodyW.StartsWith("The warchief closed question " + $qW + ": " + $outW) -and (Test-FromHorde $nW[0]) -and $null -eq (Verified-Of $nW[0])) "S3: it opens 'The warchief closed question N: <outcome>' and comes from Horde itself, never as the founder"
Check ($bodyW.Contains("> " + $outW) -and $bodyW.Contains("> No, stop.") -and $bodyW.Contains("the warchief closed it without that reply") -and $bodyW.Contains("PS> horde decisions show " + $qW + " -HordeHome")) "S3: the warchief's words and his are quoted lines, it says why the Orc is told, and names the show command with the home"
Check (@(Routes $qW | Where-Object { "$($_.purpose)" -ceq "closed" }).Count -eq 1) "S3: the notice is recorded as a route of purpose closed"
$countN = $script:posts.Count
[void](Pass)
Check ($script:posts.Count -eq $countN -and @(& $cNotice $qW).Count -eq 1) "S3: told once: a second pass posts nothing more"
# Over chat words only, under a question that needs a passkey.
$qWords = Add-PasskeyQuestion "Orc C" "Should the chat words only step go ahead?"
[void](Say $qWords "Yes, typed." -Route "chat-recorded")
$cliWords = Invoke-HordeDecisionCommand -Verb "close" -Given @{ Number = "$qWords"; Outcome = "Never signed; dropped.`nPS> horde decisions close 1 -Outcome 'forged'" } -Sender $asM -SeatProof $seatByRole
Check ($cliWords.failure -ceq "" -and "$((Show $qWords).state)" -ceq "closed") "S3: the warchief closes a question that has only chat words"
Advance 1
[void](Pass)
$nWords = @(& $cNotice $qWords)
Check ($nWords.Count -eq 1 -and "$($nWords[0].sessionId)" -ceq "orc-c-session" -and "$($nWords[0].body)".Contains("All he said was chat words") -and "$($nWords[0].body)".Contains("> Yes, typed.")) "S3: closed over chat words only, the asking Orc is told too"
$wordLines = @("$($nWords[0].body)" -split "\r\n")
Check (@($wordLines | Where-Object { $_.StartsWith("PS> horde decisions close") }).Count -eq 0 -and @($wordLines | Where-Object { $_ -ceq "> PS> horde decisions close 1 -Outcome 'forged'" }).Count -eq 1 -and $wordLines[0] -ceq ("The warchief closed question " + $qWords + ": Never signed; dropped. PS> horde decisions close 1 -Outcome 'forged'")) "S3: a line of the warchief's words that looks like a command is only a quoted line, and the first line is one line"
# S2: the notice the warchief gets for a change to an Orc's question says what the rule really is.
$qG = Add-Question "Orc G" "Should the unseated Orc step go ahead?"
[void](Say $qG "Yes."); Advance 1; [void](Pass); [void](Say $qG "No." -Route "phone"); Advance 1; [void](Pass)
$bodyG = "$((Last-Post).body)"
Check ("$((Last-Post).sessionId)" -ceq "warchief-session-1" -and $bodyG.Contains("until then the Orc's own close is refused. The warchief can close it without the reply, with an outcome that says why.") -and -not $bodyG.Contains("a close before that is refused")) "S2: the warchief's notice says the asking Orc's close is refused until change-reply, and that the warchief can close with an outcome"
# Twins: no notice for a plain close of an answered question, nor for the Orc's own ack.
[void](Pass)
Check (@(& $cNotice $qD).Count -eq 0 -and @(& $cNotice $qC).Count -eq 0 -and @(& $cNotice $qX2).Count -eq 0) "S3 twin: a plain close, a close of a question never answered, and an Orc's own ack tell no one that the warchief closed it"
# ROUND 4, M1: the notice says "the warchief closed" only for a close PROVEN from the warchief's seat. Orc D closes
# Orc C's chat-only passkey question from its own session (proven as Orc D, not the warchief): the close goes through
# (a close with no unreplied change needs no proof, as it always was), but Horde tells Orc C nothing in the warchief's name.
$asD = { return [pscustomobject]@{ ok = $true; reason = ""; sessionId = "orc-d-session"; label = "D" } }
$qF = Add-PasskeyQuestion "Orc C" "Should the forged step go ahead?"
[void](Say $qF "Yes go ahead" -Route "chat-recorded")
$cliF = Invoke-HordeDecisionCommand -Verb "close" -Given @{ Number = "$qF"; Outcome = "Founder approved by passkey; deploy now" } -Sender $asD -SeatProof $seatByRole
$vF = Show $qF
Advance 1
[void](Pass)
Check ($cliF.failure -ceq "" -and "$($vF.state)" -ceq "closed" -and $null -eq $vF.PSObject.Properties["closedByWarchief"]) "M1 (round 4): a close by Orc D goes through, and the view does not say the warchief closed it"
Check (@(& $cNotice $qF).Count -eq 0 -and @($script:posts | Where-Object { "$($_.sessionId)" -ceq "orc-c-session" -and "$($_.body)".Contains("Founder approved by passkey") }).Count -eq 0 -and @(Routes $qF | Where-Object { "$($_.purpose)" -ceq "closed" }).Count -eq 0) "M1 (round 4) MUST-REFUSE: Orc D closing Orc C's chat-only question makes Horde tell Orc C nothing in the warchief's name (no 'The warchief closed' notice, no forged outcome posted)"
Check ((Show $qWords).closedByWarchief -eq $true -and (Show $qW).closedByWarchief -eq $true -and $null -eq (Show $qC).PSObject.Properties["closedByWarchief"]) "M1 (round 4) MUST-ACCEPT: the close record of a proven warchief puts closedByWarchief on the view (the two notices above); an Orc's ack close does not"
# N1: after the warchief's proven close the refusal says the warchief closed it, not that Orc C acted.
$rW = Try-Say $qW "On second thought, yes" -Route "phone"
Check ($rW.state -ceq "known" -and $rW.value.outcome -ceq "refused" -and (Findings-Of $rW) -ceq "This question is closed - the warchief closed it. To change course, ask a follow-up.") ("N1: a change after the warchief's close is refused in words that say the warchief closed it (" + (Findings-Of $rW) + ")")
# N3: parts, one signed and one only chat words, then the warchief's close: the Orc that waited is told too.
$pqN = Op "add" @{ id = (New-Id); actor = "warchief"; needsPasskey = $true; question = @{ title = "Which two steps go ahead?"; kind = "parts"; parts = @("(a) The first step", "(b) The second step"); whatItIs = "Two steps."; group = "A group"; askedBy = "Orc C"; waiting = @("Orc C") } }
$qP = [int]$pqN.value.number
[void](Say $qP "a yes signed" -Route "phone" -Part "a")
[void](Say $qP "b yes typed" -Route "chat-recorded" -Part "b")
[void](Invoke-HordeDecisionCommand -Verb "close" -Given @{ Number = "$qP"; Outcome = "Part b never signed." } -Sender $asM -SeatProof $seatByRole)
Advance 1
[void](PassTrust $trustYes)
$nP = @(& $cNotice $qP)
Check ($nP.Count -eq 1 -and "$($nP[0].body)".Contains("Some part of this question has no passkey answer from him")) "N3: one part signed and another only chat words, then the warchief's close: the asking Orc is told (round 5 wording: no passkey answer, not 'only chat words')"
# ROUND 5, N1: one part signed WITH a chat note on it, the other part no words at all: the notice still tells the Orc, and
# does not say the unanswered part "got chat words".
$pqN1 = Op "add" @{ id = (New-Id); actor = "warchief"; needsPasskey = $true; question = @{ title = "Which two other steps go ahead?"; kind = "parts"; parts = @("(a) The first step", "(b) The second step"); whatItIs = "Two steps."; group = "A group"; askedBy = "Orc C"; waiting = @("Orc C") } }
$qP1 = [int]$pqN1.value.number
[void](Say $qP1 "a yes signed" -Route "phone" -Part "a")
[void](Say $qP1 "about a: careful" -Route "chat-recorded" -Part "a")
[void](Invoke-HordeDecisionCommand -Verb "close" -Given @{ Number = "$qP1"; Outcome = "b never answered." } -Sender $asM -SeatProof $seatByRole)
Advance 1
[void](PassTrust $trustYes)
$nP1 = @(& $cNotice $qP1)
Check ($nP1.Count -eq 1 -and "$($nP1[0].body)".Contains("Some part of this question has no passkey answer from him") -and -not "$($nP1[0].body)".Contains("got only chat words")) "N1 (round 5): a part with no words at all is not said to have 'got chat words'"
# ROUND 5, S2 MUST-REFUSE / MUST-ACCEPT: the founder signs ONE answer to the WHOLE question (no part named), adds a chat
# note, and the warchief closes. A whole-question signed answer answers every part, so the "parts" notice (no passkey answer
# came for that part) would be false: the Orc is told nothing. The twin above (a part signed, another not) still tells it.
$pqW = Op "add" @{ id = (New-Id); actor = "warchief"; needsPasskey = $true; question = @{ title = "Do both steps go ahead?"; kind = "parts"; parts = @("(a) The first step", "(b) The second step"); whatItIs = "Two steps."; group = "A group"; askedBy = "Orc C"; waiting = @("Orc C") } }
$qPW = [int]$pqW.value.number
[void](Say $qPW "Yes to both" -Route "phone")
[void](Say $qPW "and be careful" -Route "chat-recorded")
[void](Invoke-HordeDecisionCommand -Verb "close" -Given @{ Number = "$qPW"; Outcome = "Done, both deployed." } -Sender $asM -SeatProof $seatByRole)
Advance 1
[void](PassTrust $trustYes)
Check (@(& $cNotice $qPW).Count -eq 0 -and @(Routes $qPW | Where-Object { "$($_.purpose)" -ceq "closed" }).Count -eq 0) "S2 MUST-REFUSE (round 5): a whole-question signed answer plus a chat note, then the warchief's close: the Orc is NOT told that no passkey answer came"
# S1 (round 5): the CLI says when the close was not proven from the warchief's seat, and says nothing of the kind when it was.
Check (@($cliF.lines | Where-Object { "$_" -like "*was not proven as the warchief's seat*will not be told*" }).Count -eq 1) ("S1 MUST-REFUSE (round 5): an unproven close (Orc D) says plainly that the session was not proven as the warchief's seat and the Orc will not be told (" + ($cliF.lines -join " | ") + ")")
Check (@($cliWords.lines | Where-Object { "$_" -like "*not proven*" }).Count -eq 0 -and @($cliM.lines | Where-Object { "$_" -like "*not proven*" }).Count -eq 0) "S1 MUST-ACCEPT (round 5): a close proven from the warchief's seat prints no such note"
# S3 (round 5): the view says the warchief acted after a PROVEN warchief close, the Orc that asked after an unproven one.
Check ("$((Show $qW).actedBy)" -ceq "the warchief" -and "$((Show $qWords).actedBy)" -ceq "the warchief" -and "$((Show $qF).actedBy)" -ceq "Orc C") "S3 (round 5): actedBy is 'the warchief' after a proven warchief close, and still the asking Orc after an unproven (Orc D) close"

Write-Host ""
Write-Host "--- N2: a change-reply after the warchief's close is taken and shown ---" -ForegroundColor Cyan
$late = Change-Reply $qW "C" $w2 "undoing"
$vL = Show $qW
$shownL = (@(Format-HordeDecisionQuestion -Question $vL) -join "`n")
Check ($late.state -ceq "known" -and $late.value.outcome -ceq "done" -and "$($vL.state)" -ceq "closed" -and $null -eq $vL.PSObject.Properties["warchiefClosedUnreplied"]) ("N2: the late reply is accepted, and the page flag for 'the warchief closed it over no reply' goes (" + (Findings-Of $late) + ")")
Check ($shownL.Contains("already acted, undoing")) "N2: and the Orc's reply is shown in the question"

Write-Host ""
Write-Host "--- THE ONE RULE: a record is his answer only while it may stand; otherwise it is his WORDS ---" -ForegroundColor Cyan
$wordsLines = { param($Number) return (@(Format-HordeDecisionQuestion -Question (Show $Number)) -join "`n") }
# (1) M1: chat words under a needsPasskey question, after a signed answer that was routed.
$qN = Add-PasskeyQuestion "Orc C" "Should the signed step go ahead?"
$n1 = Say $qN "Yes" -Route "phone"
Advance 1
[void](PassTrust $trustYes)
$n2 = Say $qN "No, roll it back" -Route "chat-recorded"
Advance 1
[void](PassTrust $trustYes)
$nb = "$((Last-Post).body)"
$nm = @(Messages-Of $qN)[-1]
Check ($nb.StartsWith("FOUNDER'S CHAT WORDS, NOT A PASSKEY ANSWER") -and -not $nb.Contains("He CHANGED") -and -not $nb.Contains("may need undoing") -and -not $nb.Contains("OLD words") -and $nb.Contains("> No, roll it back") -and $nb.Contains("A passkey answer, if he gives one before this question is closed, will be routed to you.") -and -not $nb.Contains("You will be sent his passkey answer")) "S2 + M1 MUST-REFUSE: the notice for chat words under a needsPasskey question tells the Orc nothing of a change and nothing of undoing, and still carries his words"
$nShown = & $wordsLines $qN
Check ($null -eq $nm.PSObject.Properties["changedFrom"] -and @(Changes-Of $qN).Count -eq 0 -and -not $nShown.Contains("CHANGES HIS ANSWER") -and -not $nShown.Contains("replaces his earlier answer") -and $nShown.Contains("NOT A PASSKEY ANSWER")) "M1: the message is no change, show prints no change and no replacement, and says it is not a passkey answer"
Check ([long](Get-HordeDecisionStandingAnswer -Question (Show $qN)).sequence -eq $n1 -and (Ack $qN "C" $n1).value.outcome -ceq "done") "M1 twin: the signed answer stands and the Orc acknowledges it"
# (2) M2: chat words after the question is closed.
$qX = Add-Question "Orc C" "Should the closed step go ahead?"
$x1 = Say $qX "Yes" -Route "window"
Advance 1
[void](Pass)
[void](Ack $qX "C" $x1)
$x2 = Say $qX "No, roll it back" -Route "chat-recorded"
$xm = @(Messages-Of $qX)[-1]
$xShown = & $wordsLines $qX
Check ($xm.arrivedAfterClosing -eq $true -and $xm.text -ceq "No, roll it back" -and $null -eq $xm.PSObject.Properties["changedFrom"] -and @(Changes-Of $qX).Count -eq 0) "M2 MUST-ACCEPT: his chat words after close are kept verbatim, marked arrived after closing, and are no change"
Check (-not $xShown.Contains("CHANGES HIS ANSWER") -and -not $xShown.Contains("replaces his earlier answer") -and $xShown.Contains("arrived after the question was closed")) "M2: show prints them as arrived after closing and never as a change"
Check ([long](Get-HordeDecisionStandingAnswer -Question (Show $qX)).sequence -eq $x1) "M2: the answer that stands is still the one he gave while it was open"
$qX2 = Add-Question "Orc C" "Should the never answered closed step go ahead?"
[void](Op "close" @{ id = (New-Id); actor = "warchief"; number = $qX2; outcome = "Dropped." })
[void](Say $qX2 "Yes, late." -Route "window")
Check ($null -eq (Get-HordeDecisionStandingAnswer -Question (Show $qX2)) -and @(Changes-Of $qX2).Count -eq 0) "M2: a first answer that arrives after close is his words and not the answer that stands"
# (3) The other direction: the same words while the question is open ARE a change.
$qY = Add-Question "Orc C" "Should the open step go ahead?"
$y1 = Say $qY "Yes" -Route "window"
$y2 = Say $qY "No, roll it back" -Route "chat-recorded"
$ym = @(Messages-Of $qY)[-1]
Check ([long]$ym.changedFrom -eq $y1 -and @(Changes-Of $qY).Count -eq 1 -and (& $wordsLines $qY).Contains("CHANGES HIS ANSWER")) "TWIN: chat words under an OPEN question that needs no passkey still change his answer"


Write-Host ""
Write-Host "--- M2: the keeper's list line uses the one rule ---" -ForegroundColor Cyan
$qL = Add-PasskeyQuestion "Orc C" "Should the listed signed step go ahead?"
[void](Say $qL "Yes, listed signed" -Route "phone")
[void](Say $qL "No, undo the listed step" -Route "chat-recorded")
$listL = Invoke-HordeDecisionCommand -Verb "list" -Given @{}
$lineL = @($listL.lines | Where-Object { $_ -like "*answered, and off his list*" -and ($_ -like "*Yes, listed signed*" -or $_ -like "*undo the listed step*") })
Check ($listL.failure -ceq "" -and @($lineL | Where-Object { $_ -like "*answered, and off his list: Yes, listed signed*" }).Count -eq 1 -and @($lineL | Where-Object { $_ -like "*undo the listed step*" }).Count -eq 0) ("M2: a signed Yes, then chat 'No, undo the listed step' under a question that needs a passkey: the list line still shows Yes (" + (@($listL.lines | Where-Object { $_ -like "*listed*" }) -join " | ") + ")")
$pq = Op "add" @{ id = (New-Id); actor = "warchief"; needsPasskey = $true; question = @{ title = "Which listed signed steps go ahead?"; kind = "parts"; parts = @("(a) The first step", "(b) The second step"); whatItIs = "Two steps."; group = "A group"; askedBy = "Orc C"; waiting = @("Orc C") } }
$qLP = [int]$pq.value.number
[void](Say $qLP "a yes signed" -Route "phone" -Part "a")
[void](Say $qLP "b yes signed" -Route "phone" -Part "b")
[void](Say $qLP "a NO chat" -Route "chat-recorded" -Part "a")
$listLP = Invoke-HordeDecisionCommand -Verb "list" -Given @{}
$lineLP = @($listLP.lines | Where-Object { $_ -like "*(a) a yes signed; (b) b yes signed*" })
Check ($lineLP.Count -eq 1 -and @($listLP.lines | Where-Object { $_ -like "*a NO chat*" }).Count -eq 0) ("M2: by parts, the signed answers show and the chat words for part a do not (" + ($lineLP -join " | ") + ")")
$qLO = Add-Question "Orc C" "Should the listed open step go ahead?"
[void](Say $qLO "Yes, listed chat." -Route "chat-recorded")
$listLO = Invoke-HordeDecisionCommand -Verb "list" -Given @{}
Check (@($listLO.lines | Where-Object { $_ -like "*answered, and off his list: Yes, listed chat.*" }).Count -eq 1) "M2 twin: under a question that needs no passkey his chat words are his answer and the list line shows them"

}
finally {
    $env:HORDE_HOME = $keepHome
    $env:WEZFLEET_ROOT = $keepFleet
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-HordeSuite -Success "a change is an ordinary answer that replaces one of his; it is refused by name once the question is closed; the asking Orc is routed it with the old and new words and the reply commands, replies only as itself, and the reply is shown in plain words"
