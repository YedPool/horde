# DOES `horde decisions notify` RING ONCE PER SET OF THE FOUNDER'S ANSWERS, NEVER WITH HIS WORDS, AND
# NEVER CLAIM A NOTICE IT DID NOT HAND TO A MESSENGER?
#
# decisions/Notify.ps1, held without any real messenger and without any real session:
#   - THE SETTINGS of the module decisions-notify, and the ONE list of what a messenger must offer.
#   - THE QUIET RULE, pure, on a clock this suite moves: no ring before the quiet period has passed
#     since the newest answer, and none on a reading that began before it ended.
#   - THE TOLD RECORD under the home: written whole, read back, and a record that cannot be read
#     REFUSES (nothing is rung from an empty memory, and the file is left as it was).
#   - THE SEND, through messengers/Port.ps1 to a stand-in messenger registered the way a real one is:
#     one post per set, a messageId made from the set (a retry after a crash is the same message), no
#     answer text in the notice, nothing recorded for a post that was not accepted, a back-off.
#   - NO MESSENGER: pending, said plainly, nothing recorded, and rung once one appears.
#   - THE FOUNDER, VERIFIED - OR ONLY HIS LABEL: the notice says from.verified only for a set in which
#     every answer's record names, by the route phone and with its evidence, one passkey that the trust
#     store holds as trusted when the notice is made. Attacked with: an answer typed in the window, a
#     window record forged to hold a signedBy, a phone record with its evidence taken away, a record
#     written before records named the passkey, a passkey revoked after the answer, a key the store holds
#     as a machine's, a key it never held, a store that cannot say, two passkeys in one set, a mixed
#     set, and key ids in every wrong spelling. The trust store here is a stand-in handed to the pass;
#     the real one, with a real passkey and a real revocation, is test/test-relay-channels.ps1's.
#   - THE LOOP: one per home; asked to stop, it still rings for an answer in its quiet period.
# The CLI's notify verb is test/test-decisions-cli.ps1's; the window starting notify is
# test/e2e/e2e-decisions-notify.ps1's.
#
# NOTHING OF THIS MACHINE IS READ. The home is a folder of this suite's own; the warchief's seat is a
# stand-in handed to the pass, so no fleet record is read.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }

$work = Join-Path $env:TEMP ("horde-decisions-notify-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$hordeHome = Join-Path $work "home"
$keepHome = $env:HORDE_HOME
$env:HORDE_HOME = $hordeHome
# PINNED, for what this process starts that this suite cannot reach into: Start-HordeDecisionNotifyBeside
# loads Notify.ps1 afresh in a runspace of its own, with every messenger and the real seat reader. The
# messengers' pins hold in this home, and the fleet's registry is a folder that does not exist.
. (Join-Path $root "test\lib\MessengerPins.ps1")
$pins = @(Set-HordeTestMessengerPins -Root $root -HordeHome $hordeHome)
$keepFleet = $env:WEZFLEET_ROOT
$env:WEZFLEET_ROOT = Join-Path $work "no-fleet"
. (Join-Path $root "decisions\Notify.ps1")
$fx = Join-Path $here "fixtures\decisions-notify"
# NO REAL MESSENGER IS EVER ASKED HERE. Notify loads every messenger folder (a real one included, which
# would start the fleet's mail command); this suite keeps only the in-process test messenger and its own
# stand-ins, so a post can never leave the process. The control shows notify did load more than that.
$loadedByNotify = @(Get-HordeMessengerNames)
foreach ($n in $loadedByNotify) { if ($n -cne "memory") { [void]$script:HordeMessengers.Remove($n) } }
Check ($loadedByNotify.Count -ge 2 -and $loadedByNotify -ccontains "memory") ("CONTROL: notify loads every messenger folder (" + ($loadedByNotify -join ", ") + ")")
Check ($pins.Count -ge 1 -and @($pins | Where-Object { -not (Test-Path -LiteralPath (Join-Path $hordeHome ("settings\messenger-" + $_ + ".json")) -PathType Leaf) }).Count -eq 0) ("PIN: every messenger that has a pin is pinned in this suite's home, for the runspace beside a window (" + ($pins -join ", ") + ")")
Check ((@(Get-HordeMessengerNames) -join ",") -ceq "memory") ("only the test messenger is left before any notice is tried (" + (@(Get-HordeMessengerNames) -join ",") + ")")

# THE CLOCK this suite moves, and the seat it hands in.
$script:now = [datetime]::new(2026, 10, 9, 12, 0, 0, [System.DateTimeKind]::Utc)
$clock = { return $script:now }
$script:seatSays = "known"
$seat = { if ($script:seatSays -ceq "known") { return (New-HordeKnown -Value ([pscustomobject]@{ sessionId = "warchief-session-1"; pane = "3"; instance = "t1" })) }; if ($script:seatSays -ceq "absent") { return (New-HordeAbsent -Note "no live session's record names the role warchief") }; return (New-HordeUnknown -Reason "two live sessions each say they are the warchief") }
# THE STAND-IN MESSENGERS' MAIL: every post, and one record per messageId (idempotent, as declared).
$script:posts = New-Object System.Collections.ArrayList
$script:taken = @{}
$script:postSays = "accepted"
# What the stand-in adds to an accepted post's answer, as a messenger that could not show a verified
# sender does (messengers/wezfleet: "posted without the verified label: ...").
$script:postNote = ""
$stubPost = {
    param($Message)
    [void]$script:posts.Add($Message)
    if ($script:postSays -ceq "throw") { throw "the stand-in's line is down" }
    if ($script:postSays -ceq "unknown") { return (New-HordeUnknown -Reason "the stand-in could not tell") }
    $id = "$($Message.messageId)"
    if (-not $script:taken.ContainsKey($id)) { $script:taken[$id] = $Message }
    $reason = $script:postWhy; if ($script:postSays -ceq "held") { $reason = "the stand-in held it" } elseif ($script:postNote -ne "") { $reason = $script:postNote }
    $said = [ordered]@{ messageId = $id; stage = $script:postSays; at = [datetime]::UtcNow; reason = $reason }
    if ($null -ne $script:postWoken) { $said["woken"] = $script:postWoken }
    return (New-HordeKnown -Value ([pscustomobject]$said) -ObservedAt ([datetime]::UtcNow))
}
# What the stand-in says of its knock: $null says nothing; true or false is its woken, with its reason.
$script:postWoken = $null
$script:postWhy = ""
$stubStatus = { param($MessageId) return (New-HordeAbsent -Note "the stand-in keeps no status") }

$script:n = 0
function Add-Question { param([int]$N)
    $q = [ordered]@{ title = ("Should step " + $N + " go ahead?"); kind = "yes-no"; whatItIs = ("Step " + $N + " is ready."); recommendation = "yes"; group = "A group"; askedBy = "Orc A"; waiting = @("Orc A") }
    $a = Invoke-HordeDecision -Operation "add" -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = $q }
    if ($a.state -cne "known" -or $a.value.outcome -cne "done") { throw ("question " + $N + " was not added: " + $a.reason) } }
function Say-Founder { param([int]$Number, [string]$Text)
    $a = Invoke-HordeDecision -Operation "say" -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "founder"; number = $Number; speaker = "founder"; route = "window"; text = $Text; wordingVersion = 1 }
    if ($a.state -cne "known" -or $a.value.outcome -cne "done") { throw ("the founder's words under " + $Number + " were not saved: " + $a.reason + " " + (@($a.value.findings) -join "; ")) }
    return [long]$a.value.sequence }
function Say-Warchief { param([int]$Number, [string]$Text)
    $a = Invoke-HordeDecision -Operation "say" -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; number = $Number; speaker = "warchief"; route = "command"; text = $Text }
    if ($a.state -cne "known" -or $a.value.outcome -cne "done") { throw ("the warchief's words were not saved: " + $a.reason) } }
function Mark-Read { param([long]$UpTo)
    $a = Invoke-HordeDecision -Operation "mark-read" -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; upTo = $UpTo }
    if ($a.state -cne "known" -or $a.value.outcome -cne "done") { throw ("mark-read failed: " + $a.reason) } }
function Say-Phone { param([int]$Number, [string]$Text, [string]$SignedBy = "")
    # The founder's answer from his phone, as the relay's decisions channel records it: the route phone,
    # the hash of a journal record, and - unless -SignedBy is empty, a record from before 2026-10-12 -
    # the key id of the passkey that signed.
    $script:n++
    $request = @{ id = [guid]::NewGuid().ToString("N"); actor = "founder"; number = $Number; speaker = "founder"; route = "phone"; text = $Text; wordingVersion = 1; evidence = ("{0:x64}" -f [long]$script:n) }
    if ($SignedBy -ne "") { $request["signedBy"] = $SignedBy }
    $a = Invoke-HordeDecision -Operation "say" -Request $request
    if ($a.state -cne "known" -or $a.value.outcome -cne "done") { throw ("the founder's phone answer under " + $Number + " was not saved: " + $a.reason + " " + (@($a.value.findings) -join "; ")) }
    return [long]$a.value.sequence }
function Edit-Record { param([long]$Sequence, [string]$Find, [string]$Replace)
    # One record of this suite's store rewritten by hand, as nothing in Horde does: true when it changed.
    $path = Join-Path (Get-HordeDecisionStoreRoot) ($Sequence.ToString("D10") + ".json")
    $enc = New-Object System.Text.UTF8Encoding($false)
    $text = [System.IO.File]::ReadAllText($path, $enc)
    $new = $text.Replace($Find, $Replace)
    [System.IO.File]::WriteAllText($path, $new, $enc)
    return [bool]($new -cne $text) }
function Get-Verified { param($Message) $p = $Message.from.PSObject.Properties["verified"]; if ($null -eq $p) { return $null }; return $p.Value }
function Test-Verified { param($Message, [string]$KeyId)
    $v = Get-Verified $Message
    if ($null -eq $v) { return $false }
    return [bool]((@($v.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object) -join ",") -ceq "by,keyId,kind" -and $v.kind -ceq "founder" -and $v.by -ceq "passkey" -and $v.keyId -ceq $KeyId) }
# A pass, as the loop makes one: the stand-in seat, this suite's clock, the real store and the real port.
function Pass { param($Tracker) return (Invoke-HordeDecisionNotifyPass -Tracker $Tracker -Clock $clock -Seat $seat) }
$recordPath = Get-HordeDecisionNotifyRecordPath -HordeHome $hordeHome
function Told { $r = Read-HordeDecisionNotifyRecord -Path $recordPath; return @($r.entries | ForEach-Object { [int]$_.question }) }
$defaults = (Read-HordeModuleSettingsText -Declaration (Get-HordeDecisionNotifySettingsDeclaration) -Text $null).values

try {

Write-Host ""
Write-Host "--- every number a person might tune is one setting of the module decisions-notify ---" -ForegroundColor Cyan
$names = @($defaults.PSObject.Properties | ForEach-Object { $_.Name })
Check (($names -join ",") -ceq "quietSeconds,pollSeconds,rereadSeconds,startWithWindow,fromLabel") ("the module declares five settings (" + ($names -join ",") + ")")
Check ($defaults.quietSeconds -eq 30 -and $defaults.pollSeconds -eq 3 -and $defaults.rereadSeconds -eq 30 -and $defaults.startWithWindow -eq $true) "their defaults: 30 s of quiet, the store looked at every 3 s, the inbox read at least every 30 s, started with the window"
Check ($defaults.fromLabel -ceq "F") ("the notice is from the founder's hub label, F, by default (" + $defaults.fromLabel + ")")
$person = Read-HordeModuleSettingsText -Declaration (Get-HordeDecisionNotifySettingsDeclaration) -Text '{"schemaVersion":1,"settings":{"fromLabel":"B12"}}'
Check ($person.state -ceq "read" -and $person.values.fromLabel -ceq "B12") "a person's file may name another hub label"
$badLabel = Read-HordeModuleSettingsText -Declaration (Get-HordeDecisionNotifySettingsDeclaration) -Text '{"schemaVersion":1,"settings":{"fromLabel":"founder"}}'
Check ($badLabel.state -ceq "refused" -and $null -eq $badLabel.values -and @($badLabel.findings).Count -eq 1 -and $badLabel.findings[0] -clike "the settings file 'settings\decisions-notify.json' of decisions-notify is refused: its key 'fromLabel' must be a hub label*") ("a label that is not a hub label refuses the file, by name (" + (@($badLabel.findings) -join " / ") + ")")
Check ((Get-HordeDecisionNotifySettings -HordeHome "C:\h").path -ceq "C:\h\settings\decisions-notify.json") "they are read from settings\decisions-notify.json under Horde's home"
$zero = Read-HordeModuleSettingsText -Declaration (Get-HordeDecisionNotifySettingsDeclaration) -Text '{"schemaVersion":1,"settings":{"quietSeconds":0,"startWithWindow":false}}'
Check ($zero.state -ceq "read" -and $zero.values.quietSeconds -eq 0 -and $zero.values.startWithWindow -eq $false) "a person's file may ring at once (0 s) and keep notify off beside the window"
$long = Read-HordeModuleSettingsText -Declaration (Get-HordeDecisionNotifySettingsDeclaration) -Text '{"schemaVersion":1,"settings":{"quietSeconds":3601}}'
Check ($long.state -ceq "refused" -and $long.findings[0] -like "*quietSeconds*") "a quiet period over an hour refuses the file, by name"

Write-Host ""
Write-Host "--- what a messenger must offer is ONE list: untyped body, idempotent post, wake ---" -ForegroundColor Cyan
Check (((Get-HordeDecisionNotifyMessengerNeeds) -join ",") -ceq "body.untyped,idempotent.post,wake") ("the list is body.untyped, idempotent.post and wake (" + ((Get-HordeDecisionNotifyMessengerNeeds) -join ",") + ")")
Check (@(Get-HordeDecisionNotifyMessengerNeeds) -cnotcontains "receipt.receiver") "and not receipt.receiver: told means handed to the session's mailbox; whether he read it is the store's own mark"
Check (@(Get-HordeMessengerNames) -ccontains "memory") "CONTROL: the in-process test messenger is loaded with the port"

Write-Host ""
Write-Host "--- the quiet rule, on a clock this suite moves ---" -ForegroundColor Cyan
$t0 = $script:now
$item = [pscustomobject]@{ question = 1; message = "5"; at = $t0.ToString("o") }
$seen = @{ "5" = $t0 }
$d = Get-HordeDecisionNotifyDue -Pending @() -FirstSeen @{} -Now $t0 -QuietSeconds 30 -ReadStartedAt $t0 -NextAttemptAt ([datetime]::MinValue)
Check (-not $d.due -and -not $d.reread -and $null -eq $d.wakeAt) "nothing waiting: nothing due and nothing to wake for"
$d = Get-HordeDecisionNotifyDue -Pending @($item) -FirstSeen $seen -Now $t0.AddSeconds(29) -QuietSeconds 30 -ReadStartedAt $t0.AddSeconds(29) -NextAttemptAt ([datetime]::MinValue)
Check (-not $d.due -and $d.wakeAt -eq $t0.AddSeconds(30)) "29 s after the answer: not due, and it wakes when the quiet period ends"
$d = Get-HordeDecisionNotifyDue -Pending @($item) -FirstSeen $seen -Now $t0.AddSeconds(31) -QuietSeconds 30 -ReadStartedAt $t0.AddSeconds(29.5) -NextAttemptAt ([datetime]::MinValue)
Check (-not $d.due -and $d.reread) "quiet has passed, but the reading began before it ended: read again first, never ring on it"
$d = Get-HordeDecisionNotifyDue -Pending @($item) -FirstSeen $seen -Now $t0.AddSeconds(31) -QuietSeconds 30 -ReadStartedAt $t0.AddSeconds(30) -NextAttemptAt ([datetime]::MinValue)
Check ($d.due -and -not $d.reread) "quiet has passed and the reading began at its end: due"
$later = [pscustomobject]@{ question = 2; message = "6"; at = $t0.AddSeconds(20).ToString("o") }
$d = Get-HordeDecisionNotifyDue -Pending @($item, $later) -FirstSeen @{ "5" = $t0; "6" = $t0.AddSeconds(20) } -Now $t0.AddSeconds(35) -QuietSeconds 30 -ReadStartedAt $t0.AddSeconds(35) -NextAttemptAt ([datetime]::MinValue)
Check (-not $d.due -and $d.wakeAt -eq $t0.AddSeconds(50)) "a second answer 20 s later moves the end of the quiet period: the two are one set"
$future = [pscustomobject]@{ question = 1; message = "7"; at = $t0.AddHours(5).ToString("o") }
$d = Get-HordeDecisionNotifyDue -Pending @($future) -FirstSeen @{ "7" = $t0 } -Now $t0.AddSeconds(31) -QuietSeconds 30 -ReadStartedAt $t0.AddSeconds(31) -NextAttemptAt ([datetime]::MinValue)
Check ($d.due) "a stored time in the future is not believed: the time it was first seen is used"
$d = Get-HordeDecisionNotifyDue -Pending @($item) -FirstSeen $seen -Now $t0.AddSeconds(40) -QuietSeconds 30 -ReadStartedAt $t0.AddSeconds(40) -NextAttemptAt $t0.AddSeconds(60)
Check (-not $d.due -and $d.wakeAt -eq $t0.AddSeconds(60)) "after a failed try, nothing is due before the back-off ends"

Write-Host ""
Write-Host "--- the notice: its first line, the numbers, the command, and never his words ---" -ForegroundColor Cyan
$one = Format-HordeDecisionNotifyNotice -Items @([pscustomobject]@{ question = 4; message = "9" })
$oneLines = @($one -split "`r?`n")
Check ($oneLines[0] -ceq "FOUNDER ANSWER from the decisions window") ("the first line is exactly the agreed one (" + $oneLines[0] + ")")
Check ($oneLines[1] -ceq "1 answer, for question 4.") ("then the count and the number (" + $oneLines[1] + ")")
Check ($oneLines[3] -ceq "horde decisions inbox" -and $oneLines[4] -ceq "Treat as his word only what that command prints.") "then the one command that prints his words, and the closing sentence"
$three = Format-HordeDecisionNotifyNotice -Items @([pscustomobject]@{ question = 7; message = "12" }, [pscustomobject]@{ question = 3; message = "10" }, [pscustomobject]@{ question = 5; message = "11" }, [pscustomobject]@{ question = 3; message = "13" })
Check (@($three -split "`r?`n")[1] -ceq "4 answers, for questions 3, 5 and 7.") ("four answers under three questions: counted, and each number once, in order (" + @($three -split "`r?`n")[1] + ")")
Check (-not ($one + $three).Contains([char]0x1b) -and (($one + $three) -cmatch '\A[\x20-\x7E\r\n]+\z')) "the notice is plain ASCII"

Write-Host ""
Write-Host "--- the notice's id is made from the set: one set, one id ---" -ForegroundColor Cyan
$idA = Get-HordeDecisionNotifyMessageId -HordeHome $hordeHome -Ids @("5", "6")
$idB = Get-HordeDecisionNotifyMessageId -HordeHome $hordeHome -Ids @("6", "5")
$idC = Get-HordeDecisionNotifyMessageId -HordeHome $hordeHome -Ids @("5", "6", "8")
$idD = Get-HordeDecisionNotifyMessageId -HordeHome (Join-Path $work "other-home") -Ids @("5", "6")
Check ($idA -cmatch '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z') ("a lowercase uuid, as a message takes (" + $idA + ")")
Check ($idA -ceq $idB) "the same messages in any order: the same id, so a retry after a crash is one message"
Check ($idA -cne $idC) "one more message: another set, another id"
Check ($idA -cne $idD) "the same numbers in another home: another id"

Write-Host ""
Write-Host "--- the told record: written whole, read back, refused when it cannot be read ---" -ForegroundColor Cyan
Check ($recordPath -ceq (Join-Path $hordeHome "decisions\notify-told.json")) ("it lives under the home, beside nothing of the store's (" + $recordPath + ")")
$r = Read-HordeDecisionNotifyRecord -Path $recordPath
Check ($r.state -ceq "none" -and @($r.entries).Count -eq 0 -and $r.problem -like "*is not there yet*") "no record yet: nothing told, and the problem says so"
$side = Join-Path $work "side\told.json"
Write-HordeDecisionNotifyRecord -Path $side -Entries @([pscustomobject]@{ question = 2; message = "14"; at = "2026-10-09T12:00:00Z"; notice = $idA })
$back = Read-HordeDecisionNotifyRecord -Path $side
Check ($back.state -ceq "read" -and @($back.entries).Count -eq 1 -and $back.told.Contains("14") -and [int]$back.entries[0].question -eq 2 -and "$($back.entries[0].notice)" -ceq $idA) "written, then read back: question 2's message 14 is told"
$bytes = [System.IO.File]::ReadAllBytes($side)
Check ($bytes[0] -eq 0x7B -and @($bytes | Where-Object { $_ -gt 0x7E }).Count -eq 0) "UTF-8 with no byte-order mark, and ASCII"
Check (@(Get-ChildItem -LiteralPath (Split-Path -Parent $side)).Count -eq 1) "and no temporary file is left beside it"
$bad = @(
    @{ text = "this is not JSON {"; like = "could not be read as JSON"; what = "text that is not JSON" },
    @{ text = '{"schemaVersion":2,"rung":[]}'; like = "not version 1"; what = "another version" },
    @{ text = '{"schemaVersion":1,"rung":[{"question":1,"message":"x1","at":"2026-10-09T12:00:00Z"}]}'; like = "record number"; what = "an entry whose message is not a record number" },
    @{ text = '{"schemaVersion":1,"rung":[],"rung":[{"question":1,"message":"3","at":"2026-10-09T12:00:00Z"}]}'; like = "twice"; what = "a key given twice" })
foreach ($c in $bad) {
    [System.IO.File]::WriteAllText($side, $c.text)
    $got = Read-HordeDecisionNotifyRecord -Path $side
    Check ($got.state -ceq "refused" -and $got.told.Count -eq 0 -and $got.problem -like ("*" + $c.like + "*")) ("refused, nothing told, and said why: " + $c.what + " (" + $got.problem + ")")
}

Write-Host ""
Write-Host "--- no messenger that can deliver to a session: pending, said plainly, nothing recorded ---" -ForegroundColor Cyan
Add-Question 1; Add-Question 2; Add-Question 3; Add-Question 4; Add-Question 5; Add-Question 6; Add-Question 7; Add-Question 8
$planted = "zebra answer: purple hippo waltz"
$script:now = $t0
$s1 = Say-Founder -Number 1 -Text ($planted + " go ahead")
$tracker = New-HordeDecisionNotifyTracker -QuietSeconds 30
$script:now = [datetime]::UtcNow
$p = Pass $tracker
Check ($p.outcome -ceq "waiting" -and $script:posts.Count -eq 0 -and $p.said -like "waiting:*1 answer*question 1*quiet*") ("an answer just stored waits out its quiet period (" + $p.said + ")")
$script:now = $script:now.AddSeconds(31)
$p = Pass $tracker
Check ($p.outcome -ceq "pending" -and $p.said -like "pending: no messenger on this machine can deliver to a session*") ("then, with only the test messenger loaded: pending, in plain words (" + $p.said + ")")
Check ($p.said -like "*memory*wake*") "and it says what the loaded messenger lacks"
Check ((Read-HordeDecisionNotifyRecord -Path $recordPath).state -ceq "none" -and $script:posts.Count -eq 0) "nothing is recorded as told and nothing was posted"
$noWake = Register-HordeMessenger -Folder (Join-Path $fx "doorbell-no-wake") -Post $stubPost -Status $stubStatus
$script:now = $script:now.AddSeconds(31)
$p = Pass $tracker
Check ($p.outcome -ceq "pending" -and $script:posts.Count -eq 0 -and $p.said -like "*doorbell-no-wake*wake*") ("a messenger that cannot wake is not a doorbell: still pending, nothing posted (" + $p.said + ")")

Write-Host ""
Write-Host "--- a messenger appears: one post for the set, recorded as told, never his words ---" -ForegroundColor Cyan
$bell = Register-HordeMessenger -Folder (Join-Path $fx "doorbell") -Post $stubPost -Status $stubStatus
$script:now = $script:now.AddSeconds(5)
$p = Pass $tracker
Check ($p.outcome -ceq "pending" -and $script:posts.Count -eq 0) "within the back-off after the last try nothing is tried, even with a messenger now there"
$script:now = $script:now.AddSeconds(120)
$p = Pass $tracker
Check ($p.outcome -ceq "rang" -and $script:posts.Count -eq 1) ("after it, one post (" + $p.said + ")")
Check ($p.said -ceq ("rang for 1 answer, on question 1, through messenger doorbell (accepted)")) ("and it says so plainly (" + $p.said + ")")
$m = $script:posts[0]
Check ("$($m.sessionId)" -ceq "warchief-session-1") "addressed to the warchief's session, from its seat"
Check ("$($m.messageId)" -ceq (Get-HordeDecisionNotifyMessageId -HordeHome $hordeHome -Ids @("" + $s1))) "its messageId is the set's"
Check ("$($m.from.sessionId)" -ceq "horde-decisions-notify" -and "$($m.from.deviceId)" -ceq (Get-HordeDeviceId)) "from this machine, as notify"
Check ($null -ne $m.from.PSObject.Properties["label"] -and "$($m.from.label)" -ceq "F") ("and wearing the label F, the founder's, the setting's default (" + $(if ($null -ne $m.from.PSObject.Properties["label"]) { "$($m.from.label)" } else { "no label" }) + ")")
Check (@("$($m.body)" -split "`r?`n")[0] -ceq "FOUNDER ANSWER from the decisions window" -and "$($m.body)".Contains("1 answer, for question 1.")) "the body is the notice"
Check (-not "$($m.body)".Contains("zebra") -and -not "$($m.body)".Contains($planted)) "CONTROL beside it: the planted answer is in the store, and NOT in the notice"
Check ((Invoke-HordeDecision -Operation "show" -Request @{ number = 1 }).value.question.thread.messages[0].text.Contains($planted)) "CONTROL: the store does hold the planted words"
Check (((Told) -join ",") -ceq "1") "the record now tells question 1"
$p = Pass $tracker
Check ($p.outcome -ceq "nothing" -and $script:posts.Count -eq 1) ("a second pass rings nothing (" + $p.said + ")")
$fresh = New-HordeDecisionNotifyTracker -QuietSeconds 30
$p = Pass $fresh
Check ($p.outcome -ceq "nothing" -and $script:posts.Count -eq 1) "a restart (a tracker with no memory) does not ring again for what was told"

Write-Host ""
Write-Host "--- two answers close together are one set; a later answer rings once more ---" -ForegroundColor Cyan
$script:now = [datetime]::UtcNow.AddMinutes(10)
[void](Say-Founder -Number 2 -Text "yes")
[void](Say-Founder -Number 3 -Text "no")
# WOKEN, OR ONLY QUEUED (the founder's bug of 2026-10-12): the bell says whether the warchief was woken
# for the notice or only has it in its mailbox, in the messenger's own words.
$script:postWoken = $true; $script:postWhy = "woken"
$p = Pass $tracker
Check ($p.outcome -ceq "rang" -and $script:posts.Count -eq 2 -and "$($script:posts[1].body)".Contains("2 answers, for questions 2 and 3.")) ("one post for both (" + $p.said + ")")
Check ($p.said -clike "rang for 2 answers*through messenger doorbell (accepted; woken)") ("and the line says the warchief was woken (" + $p.said + ")")
[void](Say-Founder -Number 2 -Text "and one more thing")
$script:now = [datetime]::UtcNow.AddMinutes(20)
$script:postWoken = $false; $script:postWhy = "send-refused: not woken (occupied)"
$p = Pass $tracker
Check ($p.outcome -ceq "rang" -and $script:posts.Count -eq 3 -and "$($script:posts[2].body)".Contains("1 answer, for question 2.")) "a new answer under a question already told rings once more, for itself"
Check ($p.said -clike "rang for 1 answer*through messenger doorbell (accepted; queued, NOT woken: send-refused: not woken (occupied))") ("a notice in the mailbox of a warchief nobody woke says queued, NOT woken, and why (" + $p.said + ")")
Check (((Told) -join ",") -ceq "1,2,3,2") "and the record holds every message told: in the mailbox is told, woken or not"
$script:postWoken = $null; $script:postWhy = ""

Write-Host ""
Write-Host "--- what does not ring: the warchief's own words, and answers he has read ---" -ForegroundColor Cyan
# The inbox hands the warchief only others' words; today those are the founder's alone. Should a third
# speaker ever have words there, they are not the founder's answer and are not rung for.
$mixed = New-HordeKnown -Value ([pscustomobject]@{ outcome = "done"; messages = @(
    [pscustomobject]@{ number = 2; message = [pscustomobject]@{ speaker = "orc"; sequence = 40; at = "2026-10-09T12:00:00Z" } },
    [pscustomobject]@{ number = 3; message = [pscustomobject]@{ speaker = "founder"; sequence = 41; at = "2026-10-09T12:00:01Z" } }) })
$u = Get-HordeDecisionNotifyUnread -Answer $mixed
Check ($u.ok -and @($u.items).Count -eq 1 -and $u.items[0].message -ceq "41" -and $u.items[0].question -eq 3) "only the founder's words in an inbox are rung for"
Say-Warchief -Number 4 -Text "a note from the warchief"
$script:now = [datetime]::UtcNow.AddMinutes(30)
$p = Pass $tracker
Check ($p.outcome -ceq "nothing" -and $script:posts.Count -eq 3) "the warchief's own message is not the founder's answer"
$s5 = Say-Founder -Number 5 -Text "read before the bell"
Mark-Read -UpTo $s5
$script:now = [datetime]::UtcNow.AddMinutes(40)
$p = Pass $tracker
Check ($p.outcome -ceq "nothing" -and $script:posts.Count -eq 3) "an answer the warchief read before the quiet period ended is not rung for"

Write-Host ""
Write-Host "--- a post that is not accepted: nothing recorded, tried again with back-off, the same id ---" -ForegroundColor Cyan
$s6 = Say-Founder -Number 6 -Text "six"
$script:postSays = "unknown"
$script:now = [datetime]::UtcNow.AddMinutes(50)
$p = Pass $tracker
Check ($p.outcome -ceq "pending" -and $script:posts.Count -eq 4 -and $p.said -like "pending:*could not tell*") ("an unknown answer from the messenger: pending, with its reason (" + $p.said + ")")
Check (-not ((Told) -contains 6)) "and nothing recorded"
$firstTry = $script:now
$script:now = $firstTry.AddSeconds(29)
$p = Pass $tracker
Check ($script:posts.Count -eq 4) "no second try within 30 s"
$script:postSays = "held"
$script:now = $firstTry.AddSeconds(31)
$p = Pass $tracker
Check ($script:posts.Count -eq 5 -and $p.outcome -ceq "pending" -and $p.said -like "*held*") ("tried again after 30 s; held is not told (" + $p.said + ")")
$script:postSays = "throw"
$script:now = $firstTry.AddSeconds(31 + 59)
$p = Pass $tracker
Check ($script:posts.Count -eq 5) "the back-off doubled: no try within 60 s of the second"
$script:now = $firstTry.AddSeconds(31 + 61)
$p = Pass $tracker
Check ($script:posts.Count -eq 6 -and $p.outcome -ceq "pending" -and -not ((Told) -contains 6)) "a messenger that throws: pending, nothing recorded"
$script:postSays = "accepted"
$script:now = $firstTry.AddSeconds(31 + 61 + 121)
$p = Pass $tracker
Check ($p.outcome -ceq "rang" -and ((Told) -contains 6)) "accepted at last: told"
$ids = @($script:posts[3..6] | ForEach-Object { "$($_.messageId)" } | Sort-Object -Unique)
Check ($ids.Count -eq 1) "every try of the one set carried the one id"

Write-Host ""
Write-Host "--- a crash between the post and the record: the retry is the same message ---" -ForegroundColor Cyan
$s7 = Say-Founder -Number 7 -Text "seven"
$keep = [System.IO.File]::ReadAllBytes($recordPath)
$script:now = [datetime]::UtcNow.AddMinutes(60)
$p = Pass $tracker
Check ($p.outcome -ceq "rang") "rung for question 7"
[System.IO.File]::WriteAllBytes($recordPath, $keep)
$p = Pass (New-HordeDecisionNotifyTracker -QuietSeconds 30 -FromLabel "B12")
$sevenId = Get-HordeDecisionNotifyMessageId -HordeHome $hordeHome -Ids @("" + $s7)
Check ("$($script:posts[-1].from.label)" -ceq "B12") ("a notify started with a person's label posts wearing it (" + "$($script:posts[-1].from.label)" + ")")
Check ($p.outcome -ceq "rang" -and @($script:posts | Where-Object { "$($_.messageId)" -ceq $sevenId }).Count -eq 2 -and @($script:taken.Keys | Where-Object { $_ -ceq $sevenId }).Count -eq 1) "the record lost it, so it is posted again - with the same id, which the messenger keeps as one message"

Write-Host ""
Write-Host "--- the founder, verified: only for answers his passkey signed, by a passkey trusted now ---" -ForegroundColor Cyan
# THE STAND-IN TRUST STORE: key id -> what relay's store answers for it now, and every key it was asked for.
$keyA = "0a" * 16; $keyB = "0b" * 16; $keyM = "0c" * 16; $keyNever = "0d" * 16
$passkey = { return (New-HordeKnown -Value ([pscustomobject]@{ proof = "webauthn" })) }
$script:trust = @{ $keyA = (& $passkey); $keyB = (& $passkey); $keyM = (New-HordeKnown -Value ([pscustomobject]@{ proof = "es256" })) }
$script:asked = New-Object System.Collections.ArrayList
$trustBook = { param([string]$KeyId) [void]$script:asked.Add($KeyId); if ($script:trust.ContainsKey($KeyId)) { return $script:trust[$KeyId] }; return (New-HordeAbsent -Note ("no trusted sender has the key " + $KeyId)) }
function PassT { param($Tracker) return (Invoke-HordeDecisionNotifyPass -Tracker $Tracker -Clock $clock -Seat $seat -Trust $trustBook) }
$script:now = [datetime]::UtcNow.AddMinutes(61)
$plain = "rang for 1 answer, on question {0}, through messenger doorbell (accepted)"

$sp = Say-Phone -Number 1 -Text "answered on the phone" -SignedBy $keyA
$inboxItem = @((Get-HordeDecisionNotifyUnread -Answer (Invoke-HordeDecision -Operation "inbox" -Request @{ actor = "warchief" })).items | Where-Object { $_.message -ceq ("" + $sp) })
Check ($inboxItem.Count -eq 1 -and $inboxItem[0].route -ceq "phone" -and $inboxItem[0].signedBy -ceq $keyA -and $inboxItem[0].evidence -cmatch '\A[0-9a-f]{64}\z') "CONTROL: an unread phone answer is read with its route, its evidence and the passkey its record names"
$before = $script:posts.Count
$p = PassT $tracker
$m = $script:posts[-1]
Check ($p.outcome -ceq "rang" -and $script:posts.Count -eq ($before + 1) -and (Test-Verified $m $keyA)) ("a phone answer signed by a trusted passkey: the notice is from the founder, verified, by passkey, naming that key id and no more (" + $p.said + ")")
Check ("$($m.from.label)" -ceq "F" -and "$($m.from.sessionId)" -ceq "horde-decisions-notify" -and @("$($m.body)" -split "`r?`n")[0] -ceq "FOUNDER ANSWER from the decisions window") "it still wears the label, and the rest of the notice is what it was"
Check ($p.said -ceq (($plain -f 1) + "; as the founder, verified by his passkey " + $keyA)) ("and the line says so, with the key id (" + $p.said + ")")
Check ($script:asked.Count -eq 1 -and $script:asked[0] -ceq $keyA) "the trust store was asked once, for the key the record names"
Check (((Told) | Select-Object -Last 1) -eq 1) "and the answer is told, as any other"

[void](Say-Founder -Number 2 -Text "typed in the window")
$p = PassT $tracker
Check ($p.outcome -ceq "rang" -and $null -eq (Get-Verified $script:posts[-1]) -and "$($script:posts[-1].from.label)" -ceq "F") "an answer typed in the window: by label only, exactly as before - no passkey signed it"
Check ($p.said -ceq ($plain -f 2) -and $script:asked.Count -eq 1) ("its line is the line it always was, and the trust store was not even asked (" + $p.said + ")")

[void](Say-Phone -Number 3 -Text "phone" -SignedBy $keyA)
[void](Say-Founder -Number 3 -Text "and typed")
$p = PassT $tracker
Check ($p.outcome -ceq "rang" -and $null -eq (Get-Verified $script:posts[-1])) "a set of one phone answer and one typed in the window: by label only - a notice never says verified over an answer nobody verified"
Check ($p.said -like "rang for 2 answers, on question 3, *; by label only: *typed in the window*") ("and the line says why (" + $p.said + ")")

[void](Say-Phone -Number 4 -Text "an old phone answer")
$p = PassT $tracker
Check ($p.outcome -ceq "rang" -and $null -eq (Get-Verified $script:posts[-1]) -and $p.said -like "*; by label only: *written before*") ("a phone record written before records named the passkey: by label only, and the line says why (" + $p.said + ")")

$sw = Say-Founder -Number 5 -Text "typed, then forged"
Check (Edit-Record -Sequence $sw -Find '"route":"window"' -Replace ('"route":"window","signedBy":"' + $keyA + '"')) "CONTROL: a window record is rewritten by hand to hold a trusted passkey's key id"
$forged = @((Get-HordeDecisionNotifyUnread -Answer (Invoke-HordeDecision -Operation "inbox" -Request @{ actor = "warchief" })).items | Where-Object { $_.message -ceq ("" + $sw) })
Check ($forged.Count -eq 1 -and $forged[0].route -ceq "window" -and $forged[0].signedBy -ceq $keyA) "CONTROL: the store reads it, a fact, and the inbox hands the forged member on"
$askedBefore = $script:asked.Count
$p = PassT $tracker
Check ($p.outcome -ceq "rang" -and $null -eq (Get-Verified $script:posts[-1]) -and $script:asked.Count -eq $askedBefore) "a signedBy forged onto a window record makes nobody verified: the route decides, and the trust store is not asked"
Check ($p.said -like "*; by label only: *typed in the window*") ("and the line says a record named a passkey it may not name (" + $p.said + ")")

$se = Say-Phone -Number 6 -Text "its evidence will go" -SignedBy $keyA
Check (Edit-Record -Sequence $se -Find (',"evidence":"' + ("{0:x64}" -f [long]$script:n) + '"') -Replace '') "CONTROL: a phone record is rewritten by hand to hold no evidence"
$p = PassT $tracker
Check ($p.outcome -ceq "rang" -and $null -eq (Get-Verified $script:posts[-1]) -and $p.said -like "*; by label only: *no evidence*") ("a phone record that names a passkey but holds no evidence of the proof: by label only (" + $p.said + ")")

[void](Say-Phone -Number 7 -Text "signed, and then the phone was lost" -SignedBy $keyB)
$script:trust[$keyB] = New-HordeAbsent -Note ("the key " + $keyB + " was revoked at 2026-10-12T09:00:00Z: phone lost")
$p = PassT $tracker
Check ($p.outcome -ceq "rang" -and $null -eq (Get-Verified $script:posts[-1])) "a passkey revoked after it signed the answer: by label only - trust is asked when the notice is made"
Check ($p.said -like ("*; by label only: the passkey that signed is not trusted now: *" + $keyB + " was revoked*phone lost*")) ("and the line gives the trust store's reason (" + $p.said + ")")
[void](Say-Phone -Number 7 -Text "from the phone he still has" -SignedBy $keyA)
$p = PassT $tracker
Check ($p.outcome -ceq "rang" -and (Test-Verified $script:posts[-1] $keyA)) "CONTROL: the next answer, by the passkey still trusted, is verified again"
[void](Say-Phone -Number 7 -Text "signed while B was not trusted" -SignedBy $keyB)
$script:trust[$keyB] = & $passkey
$p = PassT $tracker
Check ($p.outcome -ceq "rang" -and (Test-Verified $script:posts[-1] $keyB)) "and nothing of an earlier answer is remembered: a key trusted when the notice is made is named"

[void](Say-Phone -Number 1 -Text "signed by a machine's key" -SignedBy $keyM)
$p = PassT $tracker
Check ($p.outcome -ceq "rang" -and $null -eq (Get-Verified $script:posts[-1]) -and $p.said -like "*; by label only: *machine's*") ("a key the store trusts as a machine's is not the founder's passkey: by label only (" + $p.said + ")")
[void](Say-Phone -Number 1 -Text "signed by a key nobody enrolled" -SignedBy $keyNever)
$p = PassT $tracker
Check ($p.outcome -ceq "rang" -and $null -eq (Get-Verified $script:posts[-1]) -and $p.said -like ("*; by label only: *not trusted now*" + $keyNever + "*")) ("a key the trust store never held: by label only (" + $p.said + ")")
[void](Say-Phone -Number 1 -Text "while the store cannot be read" -SignedBy $keyA)
$script:trust[$keyA] = New-HordeUnknown -Reason "the trust store is damaged; no sender is trusted until it is repaired"
$p = PassT $tracker
Check ($p.outcome -ceq "rang" -and $null -eq (Get-Verified $script:posts[-1]) -and $p.said -like "*; by label only: the trust store could not say*damaged*") ("a trust store that cannot say: by label only, never a guess - and the notice still goes (" + $p.said + ")")
$script:trust[$keyA] = & $passkey
[void](Say-Phone -Number 1 -Text "one passkey" -SignedBy $keyA)
[void](Say-Phone -Number 2 -Text "and another" -SignedBy $keyB)
$p = PassT $tracker
Check ($p.outcome -ceq "rang" -and $null -eq (Get-Verified $script:posts[-1]) -and $p.said -like ("*; by label only: *2 passkeys*" + $keyA + "*" + $keyB + "*")) ("two passkeys in one set: by label only - a notice names one, and does not pick (" + $p.said + ")")
[void](Say-Phone -Number 1 -Text "one passkey, twice" -SignedBy $keyA)
[void](Say-Phone -Number 2 -Text "the same one" -SignedBy $keyA)
$p = PassT $tracker
Check ($p.outcome -ceq "rang" -and (Test-Verified $script:posts[-1] $keyA) -and $p.said -like "rang for 2 answers, on questions 1 and 2, *; as the founder, verified by his passkey*") "CONTROL: two answers by one trusted passkey are one verified notice"

[void](Say-Phone -Number 1 -Text "to a messenger that cannot show it" -SignedBy $keyA)
$script:postNote = "posted without the verified label: the wezfleet it runs does not declare -FromVerified"
$p = PassT $tracker
$script:postNote = ""
Check ($p.outcome -ceq "rang" -and (Test-Verified $script:posts[-1] $keyA) -and $p.said -like "*; as the founder, verified by his passkey*; posted without the verified label: *") ("what the messenger says of a verified sender it could not show is in the line (" + $p.said + ")")
[void](Say-Phone -Number 1 -Text "verified, and the warchief's box was occupied" -SignedBy $keyA)
$script:postWoken = $false; $script:postWhy = "send-refused: not woken (occupied)"
$p = PassT $tracker
$script:postWoken = $null; $script:postWhy = ""
Check ($p.outcome -ceq "rang" -and $p.said -like "*(accepted; queued, NOT woken: send-refused: not woken (occupied)); as the founder, verified by his passkey*" -and ([regex]::Matches($p.said, "send-refused")).Count -eq 1) ("a verified phone answer that woke nobody says so, and the messenger's reason is in the line once, not twice (" + $p.said + ")")

# WITHOUT A STAND-IN the pass asks relay's own trust store of this home - which holds nobody.
[void](Say-Phone -Number 1 -Text "asked of the real store of an empty home" -SignedBy $keyA)
$p = Pass $tracker
Check ($p.outcome -ceq "rang" -and $null -eq (Get-Verified $script:posts[-1]) -and $p.said -like "*; by label only: *") ("left to itself, the pass asks the trust store under the home, where nobody is trusted: by label only (" + $p.said + ")")

# THE RULE BY ITSELF, with a trust store that says yes to every key: only the record's shape can stop it.
$yes = { param([string]$KeyId) [void]$script:asked.Add($KeyId); return (& $passkey) }
$proofHex = "ab" * 32
$item = { param([string]$Route, [string]$Evidence, [string]$SignedBy, [int]$Question = 1, [string]$Message = "90") return [pscustomobject]@{ question = $Question; message = $Message; at = "2026-10-12T09:00:00Z"; route = $Route; evidence = $Evidence; signedBy = $SignedBy } }
$good = Get-HordeDecisionNotifyVerified -Items @((& $item "phone" $proofHex $keyA)) -Trust $yes
Check ($null -ne $good.verified -and $good.verified.keyId -ceq $keyA -and $good.why -ceq "" -and $good.claimed) "CONTROL: a phone item with its evidence and a key id, and a store that says yes: verified"
$askedBefore = $script:asked.Count
foreach ($bad in @(("A" * 32), ("a" * 31), ("a" * 33), ("0a" * 16 + "`n"), ("g" * 32), ("0a" * 32), "F", "founder", ("founder:passkey:" + $keyA))) {
    $got = Get-HordeDecisionNotifyVerified -Items @((& $item "phone" $proofHex $bad)) -Trust $yes
    Check ($null -eq $got.verified -and $got.claimed -and $got.why -like "*not a key id*") ("a key id spelled wrong names nobody ('" + $bad.Trim() + "', " + $bad.Length + " characters)")
}
foreach ($route in @("window", "chat-recorded", "command", "")) {
    $got = Get-HordeDecisionNotifyVerified -Items @((& $item $route $proofHex $keyA)) -Trust $yes
    Check ($null -eq $got.verified -and $got.claimed) ("by the route '" + $route + "' nobody is verified, whatever the item holds")
}
$got = Get-HordeDecisionNotifyVerified -Items @((& $item "phone" "" $keyA)) -Trust $yes
Check ($null -eq $got.verified -and $got.claimed) "a phone item with no evidence: nobody"
$got = Get-HordeDecisionNotifyVerified -Items @((& $item "phone" $proofHex $keyA 1 "90"), (& $item "window" "" "" 2 "91")) -Trust $yes
Check ($null -eq $got.verified -and $got.why -like "*question 2 (record 91)*") ("one unsigned answer in the set: nobody, and the reason names it (" + $got.why + ")")
Check ($script:asked.Count -eq $askedBefore) "and for none of those was the trust store asked: a key that is not named by the rules is never looked up"
$got = Get-HordeDecisionNotifyVerified -Items @((& $item "window" "" "")) -Trust $yes
Check ($null -eq $got.verified -and -not $got.claimed) "a window item that holds neither member: nobody, and nothing was claimed, so nothing is said"
$got = Get-HordeDecisionNotifyVerified -Items @() -Trust $yes
Check ($null -eq $got.verified -and -not $got.claimed) "no items: nobody"
$got = Get-HordeDecisionNotifyVerified -Items @((& $item "phone" $proofHex $keyA)) -Trust { param([string]$KeyId) throw "the stand-in store fell over" }
Check ($null -eq $got.verified -and $got.why -like "*could not say*fell over*") ("a trust store that throws: nobody, with its words (" + $got.why + ")")
$got = Get-HordeDecisionNotifyVerified -Items @((& $item "phone" $proofHex $keyA)) -Trust { param([string]$KeyId) return $null }
Check ($null -eq $got.verified -and $got.why -like "*could not say*") "a trust store that answers nothing: nobody"
# Made by hand: New-HordeKnown refuses a value of nothing, and this is the answer a broken store could still give.
$got = $null
try { $got = Get-HordeDecisionNotifyVerified -Items @((& $item "phone" $proofHex $keyA)) -Trust { param([string]$KeyId) return [pscustomobject]@{ state = "known"; value = $null; reason = "" } } } catch { $got = [pscustomobject]@{ verified = "THREW: " + $_.Exception.Message } }
Check ($null -eq $got.verified) ("a trust store that says known and hands no sender: nobody, and no throw (" + $got.verified + ")")
# What the inbox hands on is taken as text only: a member that is not text is no key id.
$odd = New-HordeKnown -Value ([pscustomobject]@{ outcome = "done"; messages = @(
    [pscustomobject]@{ number = 1; message = [pscustomobject]@{ speaker = "founder"; sequence = 50; at = "2026-10-12T09:00:00Z"; route = "phone"; evidence = $proofHex; signedBy = @($keyA) } },
    [pscustomobject]@{ number = 1; message = [pscustomobject]@{ speaker = "founder"; sequence = 51; at = "2026-10-12T09:00:01Z"; route = "phone"; evidence = $proofHex; signedBy = $keyA } },
    [pscustomobject]@{ number = 1; message = [pscustomobject]@{ speaker = "founder"; sequence = 52; at = "2026-10-12T09:00:02Z" } }) })
$u = Get-HordeDecisionNotifyUnread -Answer $odd
Check ($u.ok -and @($u.items).Count -eq 3 -and $u.items[0].signedBy -ceq "" -and $u.items[1].signedBy -ceq $keyA -and $u.items[2].route -ceq "" -and $u.items[2].evidence -ceq "" -and $u.items[2].signedBy -ceq "") "an inbox message's signedBy is read only when it is text, and a message from before the member reads as holding none"

Write-Host ""
Write-Host "--- one turn of the bell, for the relay runner: the same pass, and one bell a home ---" -ForegroundColor Cyan
# The founder's bug of 2026-10-12: an answer from his phone with the decisions window closed was written
# to the store by the relay runner and rang for nobody, because notify ran only beside the window. The
# runner now turns the bell itself, through Invoke-HordeDecisionNotifyTurn - this suite's pass, no other.
$mem = @{}
function Turn { return (Invoke-HordeDecisionNotifyTurn -Memory $mem -HordeHome $hordeHome -Clock $clock -Seat $seat) }
$script:now = [datetime]::UtcNow
$before = $script:posts.Count
$toldBefore = @(Told).Count
$t = Turn
Check ($t.outcome -ceq "nothing" -and $t.said -ceq "" -and $t.againMs -eq 0 -and $script:posts.Count -eq $before) ("with nothing untold a turn rings nothing, says nothing and asks for no turn (" + $t.outcome + ")")
[void](Say-Founder -Number 3 -Text "from the phone, with the window closed")
$t = Turn
Check ($t.outcome -ceq "waiting" -and $t.said -ceq "" -and $script:posts.Count -eq $before) ("a new answer is in its quiet period: nothing rung, and no line for a log (" + $t.outcome + ")")
Check ($t.againMs -gt 0 -and $t.againMs -le 30000) ("and the turn asks to be turned again when the quiet period ends, not a watch later (" + $t.againMs + " ms)")
$script:inboxReads = 0
$countingInbox = { $script:inboxReads++; return (Invoke-HordeDecision -Operation "inbox" -Request @{ actor = "warchief" }) }
$t = Invoke-HordeDecisionNotifyTurn -Memory $mem -HordeHome $hordeHome -Clock $clock -Seat $seat -Inbox $countingInbox
Check ($t.outcome -ceq "idle" -and $script:inboxReads -eq 0 -and $t.againMs -gt 0 -and $t.againMs -le 30000) ("a turn with the store unchanged and the time not come does not read the inbox, and still says when (" + $t.outcome + ", " + $script:inboxReads + " reads, " + $t.againMs + " ms)")
# 60 s on: past the quiet period whichever clock stamped the answer, the store's or this suite's.
$script:now = $script:now.AddSeconds(60)
$t = Invoke-HordeDecisionNotifyTurn -Memory $mem -HordeHome $hordeHome -Clock $clock -Seat $seat -Inbox $countingInbox
Check ($t.outcome -ceq "rang" -and $script:inboxReads -ge 1 -and $script:posts.Count -eq ($before + 1) -and "$($script:posts[-1].body)".Contains("1 answer, for question 3.")) ("once the time has come the turn reads, and rings once (" + $t.outcome + ")")
Check ($t.said -clike "rang for 1 answer, on question 3, through messenger doorbell (accepted)*" -and $t.againMs -eq 0) ("and it says the pass's own line, once (" + $t.said + ")")
Check (@(Told)[-1] -eq 3 -and @(Told).Count -eq ($toldBefore + 1)) "the set is in the told record the loop reads too"
$t = Turn
Check ($script:posts.Count -eq ($before + 1) -and $t.said -ceq "") "the next turn rings nothing more"
# ONE BELL A HOME: while a notify loop holds the home's bell (the window is open), a turn stands aside.
$bellName = "Local\" + (Get-HordeDecisionNotifyName -HordeHome $hordeHome)
$gate = New-Object System.Threading.ManualResetEvent($false)
$got = New-Object System.Threading.ManualResetEvent($false)
$holder = [powershell]::Create()
[void]$holder.AddScript('param($Name, $Gate, $Got) $m = New-Object System.Threading.Mutex($false, $Name); [void]$m.WaitOne(); [void]$Got.Set(); [void]$Gate.WaitOne(); $m.ReleaseMutex(); $m.Dispose()').AddArgument($bellName).AddArgument($gate).AddArgument($got)
$holding = $holder.BeginInvoke()
try {
    Check ($got.WaitOne(15000)) "CONTROL: another thread holds the home's bell, as a running notify loop does"
    [void](Say-Founder -Number 3 -Text "while the window's notify runs")
    $script:now = $script:now.AddMinutes(5)
    $t = Turn
    Check ($t.outcome -ceq "elsewhere" -and $t.said -ceq "" -and $script:posts.Count -eq ($before + 1)) ("a turn beside a running notify rings nothing: that one rings (" + $t.outcome + ")")
} finally { [void]$gate.Set(); $holder.EndInvoke($holding); $holder.Dispose() }
$t = Turn
Check ($t.outcome -ceq "rang" -and $script:posts.Count -eq ($before + 2)) ("and once nobody holds it, the next turn rings for what waits (" + $t.outcome + ")")
# A REFUSED SETTINGS FILE: said once, not on every turn, and nothing rung from guessed settings.
$notifySettingsPath = (Get-HordeDecisionNotifySettings -HordeHome $hordeHome).path
[void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $notifySettingsPath))
[System.IO.File]::WriteAllText($notifySettingsPath, "{ not json")
[void](Say-Founder -Number 3 -Text "while the settings are broken")
$script:now = $script:now.AddMinutes(5)
$t = Turn
$t2 = Turn
Remove-Item -LiteralPath $notifySettingsPath -Force
Check ($t.outcome -ceq "refused" -and $t.said -clike "*not rung for*settings file is refused*" -and $script:posts.Count -eq ($before + 2)) ("with its settings file refused the turn rings nothing and says why (" + $t.said + ")")
Check ($t2.outcome -ceq "refused" -and $t2.said -ceq "") "and says it once, not on every turn"
$t = Turn
Check ($t.outcome -ceq "rang" -and $script:posts.Count -eq ($before + 3)) "with the file mended the answer that waited is rung for"

Write-Host ""
Write-Host "--- no seat, a record that cannot be read, two messengers: pending or refused, never a guess ---" -ForegroundColor Cyan
[void](Say-Founder -Number 8 -Text "eight")
$script:now = [datetime]::UtcNow.AddMinutes(70)
$before = $script:posts.Count
$script:seatSays = "absent"
$p = Pass $tracker
Check ($p.outcome -ceq "pending" -and $script:posts.Count -eq $before -and $p.said -like "pending:*warchief*") ("no warchief's session: pending (" + $p.said + ")")
$script:seatSays = "unknown"
$script:now = $script:now.AddSeconds(31)
$p = Pass $tracker
Check ($p.outcome -ceq "pending" -and $script:posts.Count -eq $before -and $p.said -like "*two live sessions*") "a seat that cannot be told: pending, in the seat's own words"
$script:seatSays = "known"
$good = [System.IO.File]::ReadAllBytes($recordPath)
[System.IO.File]::WriteAllText($recordPath, "this is not JSON {")
$script:now = $script:now.AddMinutes(5)
$p = Pass $tracker
Check ($p.outcome -ceq "refused" -and $script:posts.Count -eq $before -and $p.said -like "refused:*could not be read*") ("a record that cannot be read refuses: nothing rung from an empty memory (" + $p.said + ")")
Check ([System.IO.File]::ReadAllText($recordPath) -ceq "this is not JSON {") "and the record is left exactly as it was"
[System.IO.File]::WriteAllBytes($recordPath, $good)
$two = Register-HordeMessenger -Folder (Join-Path $fx "doorbell-two") -Post $stubPost -Status $stubStatus
$p = Pass $tracker
Check ($p.outcome -ceq "pending" -and $script:posts.Count -eq $before -and $p.said -like "*doorbell*doorbell-two*") ("two messengers that could: pending, one is never chosen over the other (" + $p.said + ")")

Write-Host ""
Write-Host "--- the loop: one per home; asked to stop, it rings for an answer still in its quiet period ---" -ForegroundColor Cyan
$script:HordeMessengers.Remove("doorbell-two")
[void](Say-Founder -Number 8 -Text "eight, again")
$script:now = [datetime]::UtcNow.AddSeconds(2)
$stopAsked = $script:now
$stop = New-Object System.Threading.ManualResetEvent($true)
$sleep = { param([double]$Seconds) $script:now = $script:now.AddSeconds([Math]::Max($Seconds, 0.5)) }
$before = $script:posts.Count
# The person's settings file names another label: the loop reads it and its notice wears it.
$settingsFile = (Get-HordeDecisionNotifySettings -HordeHome $hordeHome).path
New-Item -ItemType Directory -Path (Split-Path -Parent $settingsFile) -Force | Out-Null
[System.IO.File]::WriteAllText($settingsFile, '{"schemaVersion":1,"settings":{"fromLabel":"C"}}')
$lines = @(Invoke-HordeDecisionNotifyLoop -Stop $stop -Clock $clock -Sleep $sleep -Seat $seat)
Remove-Item -LiteralPath $settingsFile
Check ("$($script:posts[-1].from.label)" -ceq "C") ("the loop's notice wears the label of the person's settings file (" + "$($script:posts[-1].from.label)" + ")")
Check ($script:posts.Count -eq ($before + 1) -and ((Told) -contains 8) -and ($script:now - $stopAsked).TotalSeconds -ge 25) ("asked to stop with an answer 2 s old: it stayed out the quiet period, rang once, and left (" + ($lines -join " / ") + ")")
Check (@($lines | Where-Object { $_ -like "rang for 2 answers, on question 8*" }).Count -eq 1 -and $lines[-1] -like "stopped*") "and said so, one line per change, ending with stopped"
$once = @(Invoke-HordeDecisionNotifyLoop -Once -Clock $clock -Sleep $sleep -Seat $seat)
Check ($once.Count -eq 1 -and $once[0] -like "nothing to ring for*") ("-Once: one pass, one line (" + ($once -join " / ") + ")")
$beside = Start-HordeDecisionNotifyBeside
$deadline = [datetime]::UtcNow.AddSeconds(60)
while ([datetime]::UtcNow -lt $deadline -and "$($beside.status.said)" -eq "") { Start-Sleep -Milliseconds 200 }
$held = @(Invoke-HordeDecisionNotifyLoop -Once -Clock $clock -Sleep $sleep -Seat $seat)
Check ($held.Count -eq 1 -and $held[0] -like "not run: notify is already running for this home*") ("a second notify for the home leaves at once, saying why (" + ($held -join " / ") + ")")
$last = Stop-HordeDecisionNotifyBeside -Helper $beside -Seconds 60
Check ($beside.status.running -eq $false -and "$last" -like "stopped*") ("the one started beside a window stops when asked (" + $last + ")")
$after = @(Invoke-HordeDecisionNotifyLoop -Once -Clock $clock -Sleep $sleep -Seat $seat)
Check ($after.Count -eq 1 -and $after[0] -notlike "not run*") "and once it has, the home is free again"

}
finally {
    $env:HORDE_HOME = $keepHome
    $env:WEZFLEET_ROOT = $keepFleet
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-HordeSuite -Success "notify rings once per set, through the port, never with his words, never claims what it did not send, and says the founder is verified only for answers a passkey trusted now signed"
