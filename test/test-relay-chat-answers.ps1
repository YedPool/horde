# DOES THE FOUNDER'S ANSWER TO AN ITEM OF A PUBLISHED LIST REACH THE ORC THAT OWNS THE LIST - ONCE, FROM HIS PASSKEY ONLY, NEVER
# ANYWHERE ELSE - AND DOES HIS PHONE GET A SENT / DELIVERED RECEIPT WITH HIS WORDS?
#
# Task T-0352, the founder's, 2026-10-23: since the published lists came to the phone (PR 365) he could read every item and answer
# none (most carry no question number). channels/chat/Answer.ps1 is the way in; this suite attacks its rules with the fleet played
# by test messengers and a seat reader:
#   - a good answer to an item of the Thrall's list and of an Orc's list is posted to THAT list's owner's session, with the body the
#     Orc reads (header, the item's text as published, his words exactly), from.verified naming his passkey; the receipt says
#     queued (Sent), then delivered when the receiving session's own side takes it (any session, not only the Thrall's);
#   - the recipient is resolved on the machine: a body that names one is refused as not exactly its members, and a lane that is not
#     the snapshot's own is refused (wrong-lane) with nothing posted;
#   - a snapshot or an index that never existed is refused (no-such-item); an older snapshot still in the store resolves; a retired
#     Orc is refused; fleet.db that cannot be asked holds the answer and it comes again;
#   - an Orc with no live session is HELD with a code (no-session), told once, not dropped, not sent to another seat, and goes when
#     the session is back; a seat that cannot be proven is held too;
#   - only the founder's trusted passkeys (an unknown, a pending and a revoked one are refused before the journal);
#   - exactly once: the same envelope again and the same answer in a new envelope are one post; other words are another post;
#   - not taken in takenAlarmSeconds: ONE alarm receipt (held, not-now), never dropped, a late confirmation turns it into delivered;
#     held by the fleet for good: told at once; a restart loses nothing; the Glance says an answer is due;
#   - wrong machine, wrong horde, no words, too long.
# NO REAL FLEET IS TOUCHED: see test-relay-chat-taken.ps1, whose scaffold this is. Seats and fleet.db are readers of the suite's own.


$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
# No adapter may find this machine's real Thrall (test/lib/FleetPin.ps1): first thing, before any loads.
. (Join-Path $root "test\lib\FleetPin.ps1")
$fleetPin = Enter-HordeTestEmptyFleet
. (Join-Path $root "core\ModuleSettings.ps1")
. (Join-Path $root "channels\Port.ps1")
foreach ($f in @(Get-HordeRelayFiles)) { . $f }
foreach ($f in @(Get-HordeRelayChannelFiles)) { . $f }
. (Join-Path $root "cli\RelayRun.ps1")
. (Join-Path $root "test\lib\RelayPhone.ps1")
. (Join-Path $root "test\lib\HostileRelay.ps1")
. (Join-Path $root "test\lib\MemoryConversation.ps1")
Set-StrictMode -Version Latest
Write-Host ("  runtime: PowerShell " + $PSVersionTable.PSVersion + " (" + $PSVersionTable.PSEdition + ")") -ForegroundColor DarkGray

# EVERY MESSENGER THE CHANNEL LOADED IS UNREGISTERED: only the suite's own may be asked.
$loaded = @(Get-HordeMessengerNames)
foreach ($n in $loaded) { [void]$script:HordeMessengers.Remove($n) }
Check (@(Get-HordeMessengerNames).Count -eq 0 -and $loaded.Count -ge 1) ("CONTROL: the messengers the channel loaded (" + ($loaded -join ", ") + ") are unregistered, so nothing reaches a real session")

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$script:homes = New-Object System.Collections.ArrayList
$script:worlds = New-Object System.Collections.ArrayList
$realHome = $env:HORDE_HOME
$fx = Join-Path $root "test\fixtures\relay-chat"

if ((Get-HordeRelayKeyStore).state -cne "known") {
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Complete-HordeSuite -Success "no key store here: no machine identity can be made, so nothing was run" -PassCode 3
}

# THE TEST MESSENGERS: each keeps one record per message id in this table, and counts every post.
$script:posts = @{}
$script:postCalls = 0
$script:postFails = $false
$postBlock = {
    param($Message)
    $script:postCalls++
    if ($script:postFails) { throw "the test messenger cannot take it now" }
    $id = "$($Message.messageId)"
    if (-not $script:posts.ContainsKey($id)) { $script:posts[$id] = @{ message = $Message; by = $null } }
    $said = [ordered]@{ messageId = $id; stage = $(if ($script:postStage) { $script:postStage } else { "accepted" }); at = [datetime]::UtcNow; reason = $script:postWhy }
    if ($null -ne $script:postWoken) { $said["woken"] = $script:postWoken }
    return (New-HordeKnown -Value ([pscustomobject]$said))
}
# What a test messenger says of its knock: $null says nothing, as before; true or false is its woken.
$script:postWoken = $null
$script:postStage = ""
$script:postWhy = ""
# WHAT THE FLEET SAYS OF A POST, BY THE MESSENGER'S ID: the stage its own side has reached. Nothing here
# makes a post "taken": a test says so by setting the stage, as the Thrall's own hook does.
$script:stages = @{}
$script:statusAsks = 0
$statusBlock = {
    param([string]$MessageId)
    $script:statusAsks++
    $st = "accepted"
    if ($script:stages.ContainsKey($MessageId)) { $st = $script:stages[$MessageId] }
    if ($st -ceq "throw") { throw "the fleet cannot say" }
    if ($st -ceq "absent") { return (New-HordeAbsent -Note "no record") }
    $v = [ordered]@{ messageId = $MessageId; stage = $st; at = [datetime]::UtcNow; reason = $(if ($st -ceq "held") { "stale-session" } else { "" }) }
    return (New-HordeKnown -Value ([pscustomobject]$v))
}
function Register-TestMessenger {
    param([string]$Name)
    $postFor = [scriptblock]::Create('param($Message) $a = & $postBlock $Message; $script:posts["$($Message.messageId)"].by = "' + $Name + '"; return $a')
    return (Register-HordeMessenger -Folder (Join-Path $fx $Name) -Post $postFor -Status $statusBlock)
}
function Remove-TestMessengers { foreach ($n in @(Get-HordeMessengerNames)) { [void]$script:HordeMessengers.Remove($n) } }

function New-TestHome {
    param([string]$Settings = '{"sendIntervalMs": 0, "startTurns": 3}')
    $h = Join-Path $env:TEMP ("horde-relay-chat-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path (Join-Path $h "settings") -Force | Out-Null
    [void]$script:homes.Add($h)
    [System.IO.File]::WriteAllText((Join-Path $h "settings\relay.json"), '{"schemaVersion": 1, "settings": {"horde": "work"}}', $utf8)
    [System.IO.File]::WriteAllText((Join-Path $h "settings\relay-chat.json"), ('{"schemaVersion": 1, "settings": ' + $Settings + '}'), $utf8)
    return $h
}
function Set-ChatSettings { param($World, [string]$Settings) [System.IO.File]::WriteAllText((Join-Path $World.home "settings\relay-chat.json"), ('{"schemaVersion": 1, "settings": ' + $Settings + '}'), $utf8) }
function Add-PhoneKey {
    param([string]$HordeHome, $Phone)
    $v = New-HordeTestPhoneVouch -Phone $Phone -Horde "work"
    $k = Add-HordeRelayPhoneKey -HordeHome $HordeHome -AgreePublic $Phone.agreePublic -By $Phone.keyId -AuthenticatorData $v.authenticatorData -ClientDataJson $v.clientDataJson -Signature $v.signature
    if ($k.state -cne "known") { throw ("no phone key: " + $k.reason) }
}
function New-World {
    # A machine with its identity, a phone paired, confirmed and its key trusted, a local relay, a run
    # context, and a Thrall of five turns in a memory store of its own.
    param([switch]$NoPhoneKey, [switch]$NoThrall, [string]$Settings = '{"sendIntervalMs": 0, "startTurns": 3}')
    $h = New-TestHome -Settings $Settings
    $env:HORDE_HOME = $h
    $id = New-HordeRelayMachineIdentity -HordeHome $h -Provider "software"
    if ($id.state -cne "known") { throw ("no identity: " + $id.reason) }
    $phone = New-HordeTestPhone
    [void](Add-HordeTestPhonePairing -HordeHome $h -Phone $phone)
    if (-not $NoPhoneKey) { Add-PhoneKey -HordeHome $h -Phone $phone }
    $c = Connect-HordeRelay -Name "local" -Options @{ root = (Join-Path $h "relay-mailboxes") }
    if ($c.state -cne "known") { throw ("no relay: " + $c.reason) }
    $ctx = New-HordeRelayRunContext -HordeHome $h -Connection $c.value
    if ($ctx.state -cne "known") { throw ("no context: " + $ctx.reason) }
    $store = New-HordeMemoryConversationStore
    if (-not $NoThrall) {
        foreach ($i in 1..5) { Add-HordeMemoryConversationTurn -Store $store -Fleet "work" -Role $(if ($i % 2) { "user" } else { "assistant" }) -Text ("turn " + $i) }
    }
    $w = [pscustomobject]@{ home = $h; id = $id.value; phone = $phone; conn = $c.value; ctx = $ctx.value; store = $store; agree = @(, ([byte[]]$id.value.agree.public)); seen = 0 }
    [void]$script:worlds.Add($w)
    return $w
}
function Use-World { param($World) $env:HORDE_HOME = $World.home; Set-HordeChatChannelSource -Options @{ memory = $World.store } -Vendor "memory" }
function Invoke-Tick {
    param($World)
    Use-World $World
    return (Invoke-HordeChatChannelTick -Context $World.ctx)
}
function Get-ThrallSession { param($World) return (Get-HordeMemoryConversationHorde -Store $World.store -Fleet "work").session }
function Get-PhoneItems {
    # Every item in the horde's phone mailbox: { seq; key; text }.
    param($World)
    $r = Receive-HordeRelayItems -Connection $World.conn -Mailbox "work/phone" -Since 0
    if ($r.state -cne "known") { return @() }
    return @($r.value.items)
}
function Get-NewMail {
    # What the phone opens of the items after the last look, as { header; body; to }. -Phone opens as
    # another phone. Items it cannot open are { header = $null; reason }.
    param($World, $Phone = $null, [switch]$All)
    if ($null -eq $Phone) { $Phone = $World.phone }
    $items = @(Get-PhoneItems $World | Where-Object { $All -or $_.seq -gt $World.seen })
    if (-not $All -and $items.Count -gt 0) { $World.seen = ($items | ForEach-Object { [long]$_.seq } | Measure-Object -Maximum).Maximum }
    $out = New-Object System.Collections.ArrayList
    foreach ($it in $items) {
        # A body that is not JSON (a machine that wrote it wrong) is a failure to open, not a crash.
        try { $o = Open-HordeTestPhoneEnvelope -Phone $Phone -Text $it.text -MachineSignPublic $World.id.sign.public }
        catch { $o = [pscustomobject]@{ ok = $false; reason = ("the body does not read: " + $_.Exception.Message); body = $null } }
        $hdr = (Read-HordeRelayEnvelope -Text $it.text).value.header
        if ($o.ok) { [void]$out.Add([pscustomobject]@{ header = $hdr; body = $o.body; to = @($hdr.to); reason = ""; length = $utf8.GetByteCount((Get-OpenedText $Phone $it.text $World)) }) }
        else { [void]$out.Add([pscustomobject]@{ header = $hdr; body = $null; to = @($hdr.to); reason = $o.reason; length = 0 }) }
    }
    return @($out.ToArray())
}
function Get-OpenedText {
    # The opened body's bytes as text (for its length).
    param($Phone, [string]$Text, $World)
    $r = Read-HordeRelayEnvelope -Text $Text
    $machine = New-HordeRelaySender -Public $World.id.sign.public -Proof "es256"
    $verdict = New-HordeKnown -Value ([pscustomobject]@{ key = (Get-HordeRelayReplayKey -Header $r.value.header); fresh = $true })
    $o = Unprotect-HordeRelayEnvelope -Envelope $r.value -Senders @{ ($machine.keyId) = $machine } -RecipientKeys @{ (Get-HordeRelayKeyId -Public $Phone.agreePublic) = $Phone.agree } -Replay $verdict -Channel $r.value.header.channel -Kind $r.value.header.kind
    if (-not $o.ok) { return "" }
    return [System.Text.Encoding]::ASCII.GetString($o.value)
}
function Get-TurnTexts { param($Mail) return (@($Mail | Where-Object { $null -ne $_.body -and $_.body.kind -ceq "chat-turns" } | ForEach-Object { @($_.body.turns) } | ForEach-Object { $_.text }) -join "|") }
function Get-Receipts { param($Mail) return @($Mail | Where-Object { $null -ne $_.body -and $_.body.kind -ceq "chat-receipt" } | ForEach-Object { $_.body }) }
function Send-ToMachine {
    param($World, [string]$Text, [string]$Key = "-")
    if ($Key -ceq "-") { $Key = (Get-HordeRelayReplayKey -Header (Read-HordeRelayEnvelope -Text $Text).value.header) }
    return (Send-HordeRelayItem -Connection $World.conn -Mailbox $World.ctx.mailbox -Text $Text -Key $Key)
}
function Invoke-Turn {
    # One inbound turn: the mailbox read and journaled, every unfinished record handed over. { text }.
    param($World)
    Use-World $World
    $in = Receive-HordeRelayInbox -Context $World.ctx -TimeoutMs 0
    $un = Invoke-HordeRelayUnfinished -Context $World.ctx
    $lines = New-Object System.Collections.ArrayList
    if ($in.state -ceq "known") { foreach ($l in @($in.value.refused)) { [void]$lines.Add("refused " + $l) }; foreach ($l in @($in.value.held)) { [void]$lines.Add("held " + $l) } }
    else { [void]$lines.Add("inbox " + $in.state + ": " + $in.reason) }
    foreach ($l in @(Get-HordeRelayRunLines -Report $un.value)) { [void]$lines.Add($l) }
    return [pscustomobject]@{ text = (@($lines.ToArray()) -join " | ") }
}
function Get-Line {
    # A line envelope from -Phone (the world's), written to the Thrall's session now unless told otherwise.
    param($World, [string]$MessageId = "", [string]$Text = "Carry on.", $Phone = $null, [string]$Session = "", [string]$Machine = "", [string]$Horde = "work")
    if ($null -eq $Phone) { $Phone = $World.phone }
    if ($Session -ceq "") { $Session = Get-ThrallSession $World }
    if ($Machine -ceq "") { $Machine = $World.id.sign.keyId }
    return (New-HordeTestPhoneEnvelope -Phone $Phone -Kind "line" -Channel "chat" -Body (New-HordeTestPhoneLineBody -MessageId $MessageId -Horde $Horde -Machine $Machine -Session $Session -Text $Text) -To $World.agree)
}
function Has { param($Turn, [string]$Text) return [bool]($Turn.text.Contains($Text)) }
function Get-Records { return @($script:posts.Values) }
function Reset-Posts { $script:stages = @{}; $script:statusAsks = 0; $script:posts = @{}; $script:postCalls = 0; $script:postFails = $false; $script:postWoken = $null; $script:postWhy = "" }


# One line from the phone, through a turn of the runner; { id; words; messengerId }.
function Send-OneLine {
    param($World, [string]$Text)
    $mid = [guid]::NewGuid().ToString("N")
    [void](Send-ToMachine $World (Get-Line $World -MessageId $mid -Text $Text).text)
    $turn = Invoke-Turn $World
    $mine = $null
    foreach ($r in @(Get-Records)) { if ($r.message.body -like ("*" + $mid + "*")) { $mine = $r } }
    return [pscustomobject]@{ id = $mid; words = $Text; turn = $turn; messengerId = $(if ($null -ne $mine) { "$($mine.message.messageId)" } else { "" }) }
}
function Get-SessionLine {
    # A line signed with the unlocked SESSION key (what every real phone line is), not a fresh passkey.
    param($World, $Sess, [string]$MessageId, [string]$Text, [switch]$WithVouch)
    $body = New-HordeTestPhoneLineBody -MessageId $MessageId -Horde "work" -Machine $World.id.sign.keyId -Session (Get-ThrallSession $World) -Text $Text
    return (New-HordeTestPhoneSessionEnvelope -Phone $World.phone -Session $Sess -Kind "line" -Channel "chat" -Body $body -To $World.agree -WithVouch:$WithVouch)
}
function Send-OneSessionLine {
    # One session-signed line through a turn of the runner; { id; words; turn; messengerId }.
    param($World, $Sess, [string]$Text)
    $mid = [guid]::NewGuid().ToString("N")
    [void](Send-ToMachine $World (Get-SessionLine $World $Sess $mid $Text -WithVouch).text)
    $turn = Invoke-Turn $World
    $mine = $null
    foreach ($r in @(Get-Records)) { if ($r.message.body -like ("*" + $mid + "*")) { $mine = $r } }
    return [pscustomobject]@{ id = $mid; words = $Text; turn = $turn; messengerId = $(if ($null -ne $mine) { "$($mine.message.messageId)" } else { "" }) }
}
function Get-ReceiptsOf {
    # Every receipt of one line the phone has not yet seen, in order, as "status/code".
    param($World, [string]$Id)
    return @(Get-Receipts @(Get-NewMail $World) | Where-Object { $_.messageId -ceq $Id } | ForEach-Object { $_.status + "/" + $_.code })
}
function Get-Awaiting {
    param($World)
    $rs = Read-HordeChatChannelState -HordeHome $World.home
    if ($rs.state -cne "known") { return @("unreadable state: " + $rs.reason) }
    return @($rs.value.awaiting)
}
function Get-NowMs { return [long]([datetime]::UtcNow - [datetime]"1970-01-01T00:00:00Z").TotalMilliseconds }


# --- THE ANSWERS' OWN HELPERS ---
$SNAP_T = "01JTTTTTTTTTTTTTTTTTTTTTTT"
$SNAP_B = "01JBBBBBBBBBBBBBBBBBBBBBBB"
$SNAP_OLD = "01JDDDDDDDDDDDDDDDDDDDDDDD"
$SNAP_R = "01JRRRRRRRRRRRRRRRRRRRRRRR"
# fleet.db as the suite plays it: snapshot id -> the lists it holds (orc letter, rank, retired, live, items), read by position.
$script:lists = @{}
$script:itemAsks = 0
$script:itemDown = $false
function Reset-Lists {
    $script:itemAsks = 0; $script:itemDown = $false
    $script:lists = @{
        $SNAP_T = @{ orc = "M"; rank = "thrall"; retired = $false; live = $true; items = @("Sales queue?", "Notifications on fleet.db?", "Line one`nline two of an item") }
        $SNAP_B = @{ orc = "B"; rank = "orc"; retired = $false; live = $true; items = @("Build on fleet.db?", "Park the lab?") }
        $SNAP_OLD = @{ orc = "B"; rank = "orc"; retired = $false; live = $false; items = @("An older B item") }
        $SNAP_R = @{ orc = "Q"; rank = "orc"; retired = $true; live = $false; items = @("Q's last item") }
    }
}
Reset-Lists
$itemReader = {
    param($Snapshot, $Position, $HordeHome)
    $script:itemAsks++
    if ($script:itemDown) { return [pscustomobject]@{ code = 1; out = ""; err = "node is not installed" } }
    $l = $script:lists[$Snapshot]
    if ($null -eq $l) { return [pscustomobject]@{ code = 0; out = '{"found":false,"reason":"no such list was ever published"}'; err = "" } }
    if ($Position -lt 1 -or $Position -gt $l.items.Count) { return [pscustomobject]@{ code = 0; out = ('{"found":false,"reason":"that list has no item ' + $Position + '"}'); err = "" } }
    $j = ConvertTo-Json -Compress -InputObject ([ordered]@{ found = $true; orc = $l.orc; rank = $l.rank; retired = $l.retired; live = $l.live; count = $l.items.Count; text = $l.items[$Position - 1] })
    return [pscustomobject]@{ code = 0; out = $j; err = "" }
}
# Seats as the suite plays them: "warchief" and "orc <letter>" -> a session id, or $null for none, or "?" for unprovable.
$script:seats = @{}
$script:seatAsks = New-Object System.Collections.ArrayList
$seatReader = {
    param([string]$Role, [string]$Label)
    [void]$script:seatAsks.Add($Role + "/" + $Label)
    $k = $(if ($Label -ceq "") { $Role } else { $Role + " " + $Label })
    if (-not $script:seats.ContainsKey($k) -or $null -eq $script:seats[$k]) { return (New-HordeAbsent -Note "no live session wears it") }
    if ($script:seats[$k] -ceq "?") { return (New-HordeUnknown -Reason "two live sessions claim it") }
    return (New-HordeKnown -Value ([pscustomobject]@{ sessionId = $script:seats[$k]; pane = "1"; instance = "x" }))
}
function Reset-Seats { $script:seats = @{ "warchief" = "11111111-1111-4111-8111-111111111111"; "orc B" = "22222222-2222-4222-8222-222222222222"; "orc Q" = "33333333-3333-4333-8333-333333333333" }; $script:seatAsks.Clear() }
Reset-Seats
Set-HordeChatAnswerItemReader -Reader $itemReader
Set-HordeChatAnswerSeat -Reader $seatReader

function New-AnswerBody {
    param($World, [string]$MessageId = "", [string]$Lane = "thrall", [string]$Snapshot = "", [int]$Index = 1, [string]$Text = "Do the first one.", [string]$Horde = "work", [string]$Machine = "", [hashtable]$Extra = @{})
    if ($MessageId -ceq "") { $MessageId = [guid]::NewGuid().ToString("N") }
    if ($Snapshot -ceq "") { $Snapshot = $SNAP_T }
    if ($Machine -ceq "") { $Machine = $World.id.sign.keyId }
    $o = [ordered]@{ v = 1; messageId = $MessageId; horde = $Horde; machine = $Machine; lane = $Lane; snapshot = $Snapshot; index = $Index; text = $Text }
    foreach ($k in $Extra.Keys) { $o[$k] = $Extra[$k] }
    return ,($utf8.GetBytes((ConvertTo-Json -InputObject $o -Compress)))
}
function Get-AnswerEnvelope {
    param($World, $Body, $Phone = $null)
    if ($null -eq $Phone) { $Phone = $World.phone }
    return (New-HordeTestPhoneEnvelope -Phone $Phone -Kind "answer" -Channel "chat" -Body $Body -To $World.agree)
}
function Send-OneAnswer {
    # One answer through a turn of the runner; { id; words; turn; messengerId; post }.
    param($World, [string]$Lane = "thrall", [string]$Snapshot = "", [int]$Index = 1, [string]$Text = "Do the first one.", [string]$MessageId = "")
    if ($MessageId -ceq "") { $MessageId = [guid]::NewGuid().ToString("N") }
    $body = New-AnswerBody -World $World -MessageId $MessageId -Lane $Lane -Snapshot $Snapshot -Index $Index -Text $Text
    [void](Send-ToMachine $World (Get-AnswerEnvelope $World $body).text)
    $turn = Invoke-Turn $World
    $mine = $null
    foreach ($r in @(Get-Records)) { if ($r.message.body -like ("*(answer " + $MessageId + ")*")) { $mine = $r } }
    return [pscustomobject]@{ id = $MessageId; words = $Text; turn = $turn; messengerId = $(if ($null -ne $mine) { "$($mine.message.messageId)" } else { "" }); post = $mine }
}
function Get-AnswerReceiptsOf {
    # Every answer receipt for one answer the phone has not yet seen, in order, as "status/code".
    param($World, [string]$Id)
    return @(Get-NewMail $World | Where-Object { $null -ne $_.body -and $_.body.kind -ceq "chat-answer-receipt" -and $_.body.messageId -ceq $Id } | ForEach-Object { $_.body.status + "/" + $_.body.code })
}
function Get-AnswerAwaiting {
    param($World)
    $r = Read-HordeChatAnswerLedger -HordeHome $World.home
    if ($r.state -cne "known") { return @("unreadable: " + $r.reason) }
    return @($r.value.awaiting)
}

try {
    $base = Get-NowMs
    Set-HordeChatTakenClock -Ms $base
    $S = '{"sendIntervalMs": 0, "startTurns": 3, "takenAlarmSeconds": 90, "takenCheckSeconds": 10, "takenAfterAlarmSeconds": 60, "ttlSeconds": 3600, "lineChars": 200}'
    Write-Host ""
    Write-Host "--- ANS 1. a good answer to the Thrall's list goes to the Thrall's seat, with the body the session reads ---" -ForegroundColor Cyan
    $W = New-World -Settings $S
    $null = Invoke-Tick $W
    $null = Get-NewMail $W
    Reset-Posts
    $null = Register-TestMessenger "chat-wakes"
    $script:postWoken = $true
    $a = Send-OneAnswer $W -Lane "thrall" -Snapshot $SNAP_T -Index 2 -Text "Wait for fleet.db, then do it."
    Check ($null -ne $a.post -and @(Get-Records).Count -eq 1) ("the answer is posted once (" + $a.turn.text + ")")
    Check ($a.post.message.sessionId -ceq "11111111-1111-4111-8111-111111111111") "to the session that holds the Thrall's seat (role warchief)"
    $want = "FOUNDER ANSWER from the phone (answer " + $a.id + ") to your published list item 2 (snapshot " + $SNAP_T + "):`n`"Notifications on fleet.db?`"`n`nWait for fleet.db, then do it."
    Check ($a.post.message.body -ceq $want) ("the body is the header naming the answer, the item and its list, the item's text as published, a blank line, and his words exactly (" + ($a.post.message.body -replace "`n", "|") + ")")
    Check ($a.post.message.from.verified.kind -ceq "founder" -and $a.post.message.from.verified.keyId -ceq $W.phone.keyId) "from.verified names the founder by the passkey that signed it"
    $rc = @(Get-AnswerReceiptsOf $W $a.id)
    Check (($rc -join ",") -ceq "accepted/queued") ("his phone's receipt is Sent: accepted/queued (" + ($rc -join ",") + ")")
    $mail = @(Get-NewMail $W -All | Where-Object { $null -ne $_.body -and $_.body.kind -ceq "chat-answer-receipt" })
    Check ($mail.Count -ge 1 -and $mail[0].body.text -ceq "Wait for fleet.db, then do it." -and $mail[0].body.lane -ceq "thrall" -and $mail[0].body.snapshot -ceq $SNAP_T -and $mail[0].body.index -eq 2 -and $mail[0].header.kind -ceq "answer-receipt") "the receipt carries his words, the list and the item, in an envelope of kind answer-receipt"
    Check (@(Get-NewMail $W -All | Where-Object { $null -ne $_.body -and $_.body.kind -ceq "chat-receipt" }).Count -eq 0) "and it is not a chat line's receipt: the chat shows nothing of it"
    $aw = @(Get-AnswerAwaiting $W)
    Check ($aw.Count -eq 1 -and $aw[0].StartsWith($a.id + ":")) "the answer is awaited in its own ledger from the moment its record was done"
    Check (@(Get-Awaiting $W).Count -eq 0) "and the Thrall's lines' list is untouched"
    $stateText = [System.IO.File]::ReadAllText((Join-Path $W.home "relay\chat\answers.json"))
    Check (-not $stateText.Contains("Wait for fleet.db")) "the ledger holds the mark and no word of his"
    $script:stages[$a.messengerId] = "handed-over"
    Set-HordeChatTakenClock -Ms ($base + 20000)
    $null = Invoke-Tick $W
    $rc = @(Get-AnswerReceiptsOf $W $a.id)
    Check (($rc -join ",") -ceq "accepted/delivered") ("taken by the receiving session's own hook: Delivered (" + ($rc -join ",") + ")")
    Check (@(Get-AnswerAwaiting $W).Count -eq 0) "and it leaves the list"
    Set-HordeChatTakenClock -Ms ($base + 400000)
    $null = Invoke-Tick $W
    Check (@(Get-AnswerReceiptsOf $W $a.id).Count -eq 0) "delivered is said once"

    Write-Host ""
    Write-Host "--- ANS 2. an answer to an ORC's list goes to that Orc's seat, never the Thrall's ---" -ForegroundColor Cyan
    Set-HordeChatTakenClock -Ms ($base + 1000000)
    Reset-Posts; $script:postWoken = $true; $script:seatAsks.Clear()
    $b = Send-OneAnswer $W -Lane "B" -Snapshot $SNAP_B -Index 1 -Text "Yes, straight on it."
    Check ($null -ne $b.post -and $b.post.message.sessionId -ceq "22222222-2222-4222-8222-222222222222") "posted to the session that wears the label B with the role orc"
    Check ($script:seatAsks -contains "orc/B" -and -not ($script:seatAsks -contains "warchief/")) ("the Thrall's seat was never asked (" + ($script:seatAsks -join ",") + ")")
    Check ($b.post.message.body.StartsWith("FOUNDER ANSWER from the phone (answer " + $b.id + ") to your published list item 1 (snapshot " + $SNAP_B + "):`n`"Build on fleet.db?`"")) "and the body names Orc B's item"
    Check ((@(Get-AnswerReceiptsOf $W $b.id) -join ",") -ceq "accepted/queued") "Sent"
    $script:stages[$b.messengerId] = "seen"
    Set-HordeChatTakenClock -Ms ($base + 1030000)
    $null = Invoke-Tick $W
    Check ((@(Get-AnswerReceiptsOf $W $b.id) -join ",") -ceq "accepted/delivered") "Delivered, by an Orc's session taking it: the taken rule serves any session"
    # An older snapshot still resolves; an item with a line break is quoted on one line.
    $o = Send-OneAnswer $W -Lane "B" -Snapshot $SNAP_OLD -Index 1 -Text "About the older list."
    Check ($null -ne $o.post -and $o.post.message.sessionId -ceq "22222222-2222-4222-8222-222222222222" -and $o.post.message.body.Contains("`"An older B item`"")) ("an answer to an item of a list since replaced still resolves, and goes to the Orc that published it (" + $o.turn.text + ")")
    $ml = Send-OneAnswer $W -Lane "thrall" -Snapshot $SNAP_T -Index 3 -Text "Multi-line item."
    Check ($null -ne $ml.post -and $ml.post.message.body.Contains("`"Line one line two of an item`"")) "an item with a line break is quoted on one line"

    Write-Host ""
    Write-Host "--- ANS 3. the phone never names a recipient, and a lane that is not the list's own is refused ---" -ForegroundColor Cyan
    Reset-Posts
    $x = New-AnswerBody -World $W -Lane "B" -Snapshot $SNAP_B -Index 1 -Extra @{ to = "Q" }
    [void](Send-ToMachine $W (Get-AnswerEnvelope $W $x).text)
    $turn = Invoke-Turn $W
    Check ($script:postCalls -eq 0 -and $turn.text -like "*refused*members*") ("a body with a member added (a recipient) is refused as not exactly its members, nothing posted (" + $turn.text + ")")
    $w1 = Send-OneAnswer $W -Lane "thrall" -Snapshot $SNAP_B -Index 1 -Text "B's item under the Thrall's lane."
    Check ($script:postCalls -eq 0 -and (@(Get-AnswerReceiptsOf $W $w1.id) -join ",") -ceq "refused/wrong-lane") ("the Thrall's lane named on Orc B's list is refused wrong-lane, nothing posted, no seat chosen for it")
    $w2 = Send-OneAnswer $W -Lane "B" -Snapshot $SNAP_T -Index 1 -Text "Thrall's item under B."
    Check ($script:postCalls -eq 0 -and (@(Get-AnswerReceiptsOf $W $w2.id) -join ",") -ceq "refused/wrong-lane") "and Orc B's lane named on the Thrall's list too"
    $nx = Send-OneAnswer $W -Lane "thrall" -Snapshot "01JXXXXXXXXXXXXXXXXXXXXXXX" -Index 1 -Text "A list that never existed."
    Check ($script:postCalls -eq 0 -and (@(Get-AnswerReceiptsOf $W $nx.id) -join ",") -ceq "refused/no-such-item") "a snapshot that never existed is refused no-such-item"
    $ni = Send-OneAnswer $W -Lane "thrall" -Snapshot $SNAP_T -Index 9 -Text "An item that never existed."
    Check ($script:postCalls -eq 0 -and (@(Get-AnswerReceiptsOf $W $ni.id) -join ",") -ceq "refused/no-such-item") "an index that never existed is refused no-such-item"
    $rt = Send-OneAnswer $W -Lane "Q" -Snapshot $SNAP_R -Index 1 -Text "To a retired Orc."
    Check ($script:postCalls -eq 0 -and (@(Get-AnswerReceiptsOf $W $rt.id) -join ",") -ceq "refused/orc-retired") "an Orc retired in fleet.db is refused orc-retired, nothing posted"
    $bad1 = New-AnswerBody -World $W -Snapshot "short"
    [void](Send-ToMachine $W (Get-AnswerEnvelope $W $bad1).text)
    $bad2 = New-AnswerBody -World $W -Index 0
    [void](Send-ToMachine $W (Get-AnswerEnvelope $W $bad2).text)
    $turn = Invoke-Turn $W
    Check ($script:postCalls -eq 0 -and ([regex]::Matches($turn.text, "refused")).Count -ge 2) ("a malformed snapshot and an index of 0 are refused by the strict reader (" + $turn.text + ")")

    Write-Host ""
    Write-Host "--- ANS 4. no session is HELD with a code, kept, told once, and goes when the session is back ---" -ForegroundColor Cyan
    Reset-Posts; $script:postWoken = $true
    $script:seats["orc B"] = $null
    $pid1 = [guid]::NewGuid().ToString("N")
    $h1 = Send-OneAnswer $W -Lane "B" -Snapshot $SNAP_B -Index 2 -Text "While B is away." -MessageId $pid1
    Check ($script:postCalls -eq 0 -and (@(Get-AnswerReceiptsOf $W $pid1) -join ",") -ceq "held/no-session") ("B has no live session: held/no-session, nothing posted anywhere (" + $h1.turn.text + ")")
    Check (@(Get-Records).Count -eq 0) "not to the Thrall's seat, not to another Orc's"
    $turn = Invoke-Turn $W
    Check (@(Get-AnswerReceiptsOf $W $pid1).Count -eq 0 -and $script:postCalls -eq 0) "it comes again on the next turn and says nothing new (told once)"
    $script:seats["orc B"] = "22222222-2222-4222-8222-222222222222"
    $turn = Invoke-Turn $W
    Check ($script:postCalls -eq 1 -and (@(Get-AnswerReceiptsOf $W $pid1) -join ",") -ceq "accepted/queued") ("B's session is back: the same answer is posted, to it, and Sent follows (" + $turn.text + ")")
    $script:seats["orc B"] = "?"
    $uid = [guid]::NewGuid().ToString("N")
    $u1 = Send-OneAnswer $W -Lane "B" -Snapshot $SNAP_B -Index 1 -Text "Seat unprovable." -MessageId $uid
    Check ($script:postCalls -eq 1 -and (@(Get-AnswerReceiptsOf $W $uid) -join ",") -ceq "held/not-now") "a seat that cannot be proven (two claimants) is held not-now, never guessed"
    $script:seats["orc B"] = "22222222-2222-4222-8222-222222222222"
    $null = Invoke-Turn $W
    Check ($script:postCalls -eq 2) "and goes when it can be"
    $script:itemDown = $true
    $did = [guid]::NewGuid().ToString("N")
    $d1 = Send-OneAnswer $W -Lane "B" -Snapshot $SNAP_B -Index 1 -Text "fleet.db is down." -MessageId $did
    Check ($script:postCalls -eq 2 -and (@(Get-AnswerReceiptsOf $W $did) -join ",") -ceq "held/not-now") "fleet.db that cannot be asked holds the answer (not-now), not refused"
    $script:itemDown = $false
    $null = Invoke-Turn $W
    Check ($script:postCalls -eq 3) "and it goes when fleet.db answers"

    Write-Host ""
    Write-Host "--- ANS 5. only the founder's trusted passkeys ---" -ForegroundColor Cyan
    Reset-Posts
    $stranger = New-HordeTestPhone
    [void](Send-ToMachine $W (Get-AnswerEnvelope $W (New-AnswerBody -World $W) -Phone $stranger).text)
    $pending = New-HordeTestPhone
    [void](Add-HordeTestPhonePairing -HordeHome $W.home -Phone $pending -NoConfirm)
    [void](Send-ToMachine $W (Get-AnswerEnvelope $W (New-AnswerBody -World $W) -Phone $pending).text)
    $revoked = New-HordeTestPhone
    [void](Add-HordeTestPhonePairing -HordeHome $W.home -Phone $revoked)
    [void](Revoke-HordeRelayTrust -HordeHome $W.home -Subject "device" -Id $revoked.deviceId -Reason "lost")
    [void](Send-ToMachine $W (Get-AnswerEnvelope $W (New-AnswerBody -World $W) -Phone $revoked).text)
    $turn = Invoke-Turn $W
    Check (([regex]::Matches($turn.text, "refused ")).Count -eq 3 -and $script:postCalls -eq 0) ("an unknown, a pending and a revoked passkey are each refused, and nothing is posted (" + $turn.text + ")")

    Write-Host ""
    Write-Host "--- ANS 6. exactly once: a replay, the same answer resent, other words ---" -ForegroundColor Cyan
    Reset-Posts; $script:postWoken = $true
    $rid = [guid]::NewGuid().ToString("N")
    $env1 = Get-AnswerEnvelope $W (New-AnswerBody -World $W -MessageId $rid -Lane "B" -Snapshot $SNAP_B -Index 1 -Text "Once only.")
    [void](Send-ToMachine $W $env1.text)
    $null = Invoke-Turn $W
    Check ($script:postCalls -eq 1 -and @(Get-Records).Count -eq 1) "the answer is posted"
    [void](Send-ToMachine $W $env1.text -Key ($env1.key + "-again"))
    [void](Send-ToMachine $W (New-HordeTestPhoneResigned -Phone $W.phone -Envelope $env1) -Key ($env1.key + "-resigned"))
    $turn = Invoke-Turn $W
    Check ($script:postCalls -eq 1) ("the same envelope again and a re-signed copy are refused by the journal; the messenger is not asked (" + $turn.text + ")")
    $env2 = Get-AnswerEnvelope $W (New-AnswerBody -World $W -MessageId $rid -Lane "B" -Snapshot $SNAP_B -Index 1 -Text "Once only.")
    [void](Send-ToMachine $W $env2.text)
    $null = Invoke-Turn $W
    Check (@(Get-Records).Count -eq 1 -and $script:postCalls -eq 2) ("the same answer resent in a new envelope is the same post: one record (" + $script:postCalls + " posts)")
    Check (@(Get-AnswerAwaiting $W | Where-Object { $_.StartsWith($rid + ":") }).Count -eq 1) "and one entry in the awaiting list"
    $env3 = Get-AnswerEnvelope $W (New-AnswerBody -World $W -MessageId $rid -Lane "B" -Snapshot $SNAP_B -Index 1 -Text "Other words.")
    [void](Send-ToMachine $W $env3.text)
    $null = Invoke-Turn $W
    Check (@(Get-Records).Count -eq 2) "other words under one message id are another post"
    $env4 = Get-AnswerEnvelope $W (New-AnswerBody -World $W -MessageId $rid -Lane "B" -Snapshot $SNAP_B -Index 2 -Text "Once only.")
    [void](Send-ToMachine $W $env4.text)
    $null = Invoke-Turn $W
    Check (@(Get-Records).Count -eq 3) "and the same words about another item are another post too"

    Write-Host ""
    Write-Host "--- ANS 7. not taken in time: ONE alarm, never dropped, a late confirmation turns it into delivered ---" -ForegroundColor Cyan
    Set-HordeChatTakenClock -Ms ($base + 2000000)
    Reset-Posts; $script:postWoken = $false; $script:postWhy = "send-refused"
    $z = Send-OneAnswer $W -Lane "B" -Snapshot $SNAP_B -Index 1 -Text "Slow to be taken."
    $null = Get-NewMail $W
    Set-HordeChatTakenClock -Ms ($base + 2030000)
    $t = Invoke-Tick $W
    Check (@(Get-AnswerReceiptsOf $W $z.id).Count -eq 0 -and -not (($t.lines -join "|").Contains("ALARM: answer " + $z.id))) "30 s on, inside the window: asked, nothing said of this answer"
    Set-HordeChatTakenClock -Ms ($base + 2095000)
    $t = Invoke-Tick $W
    Check ((@(Get-AnswerReceiptsOf $W $z.id) -join ",") -ceq "held/not-now") "95 s on, not taken: the phone gets ONE alarm receipt held/not-now"
    Check (($t.lines -join "|").Contains("ALARM: answer " + $z.id) -and ($t.lines -join "|").Contains("the session was not woken")) ("and the runner's log carries an ALARM line (" + ($t.lines -join "|") + ")")
    foreach ($ms in 100000, 160000, 400000) { Set-HordeChatTakenClock -Ms ($base + 2000000 + $ms); $null = Invoke-Tick $W }
    Check (@(Get-AnswerReceiptsOf $W $z.id).Count -eq 0 -and @(Get-AnswerAwaiting $W | Where-Object { $_.StartsWith($z.id + ":") }).Count -eq 1) "asked again and again, never alarmed twice, still awaited"
    # S8: an answer already awaited and alarmed, sent again in a new envelope, gets no receipt over its alarm.
    $dupEnv = Get-AnswerEnvelope $W (New-AnswerBody -World $W -MessageId $z.id -Lane "B" -Snapshot $SNAP_B -Index 1 -Text "Slow to be taken.")
    [void](Send-ToMachine $W $dupEnv.text)
    $null = Invoke-Turn $W
    Check (@(Get-AnswerReceiptsOf $W $z.id).Count -eq 0 -and @(Get-AnswerAwaiting $W | Where-Object { $_.StartsWith($z.id + ":") }).Count -eq 1 -and @(Get-AnswerAwaiting $W | Where-Object { $_.StartsWith($z.id + ":") })[0].EndsWith(":1:0")) "the same answer sent again after its alarm is not told Sent over the alarm, and stays awaited and alarmed"
    $script:stages[$z.messengerId] = "seen"
    Set-HordeChatTakenClock -Ms ($base + 2520000)
    $null = Invoke-Tick $W
    Check ((@(Get-AnswerReceiptsOf $W $z.id) -join ",") -ceq "accepted/delivered") "seen late: Delivered, after the alarm"
    Set-HordeChatTakenClock -Ms ($base + 3000000)
    Reset-Posts
    $hh = Send-OneAnswer $W -Lane "thrall" -Snapshot $SNAP_T -Index 1 -Text "Held by the fleet."
    $null = Get-NewMail $W
    $script:stages[$hh.messengerId] = "held"
    Set-HordeChatTakenClock -Ms ($base + 3012000)
    $null = Invoke-Tick $W
    Check ((@(Get-AnswerReceiptsOf $W $hh.id) -join ",") -ceq "held/not-delivered" -and @(Get-AnswerAwaiting $W | Where-Object { $_.StartsWith($hh.id + ":") }).Count -eq 0) "held by the fleet for good: told at once, and it leaves the list"
    Set-HordeChatTakenClock -Ms ($base + 4000000)
    $ee = Send-OneAnswer $W -Lane "thrall" -Snapshot $SNAP_T -Index 1 -Text "Expires."
    $null = Get-NewMail $W
    $script:stages[$ee.messengerId] = "throw"
    Set-HordeChatTakenClock -Ms ($base + 4000000 + 3700000)
    $null = Invoke-Tick $W
    $erc = @(Get-AnswerReceiptsOf $W $ee.id)
    Check ($erc -contains "held/expired" -and @(Get-AnswerAwaiting $W | Where-Object { $_.StartsWith($ee.id + ":") }).Count -eq 0) ("an answer not taken in ttlSeconds is given up held/expired, with a receipt (" + ($erc -join ",") + ")")

    Write-Host ""
    Write-Host "--- ANS 8. a restart loses nothing, and the Glance says an answer is due ---" -ForegroundColor Cyan
    Set-HordeChatTakenClock -Ms ($base + 8000000)
    Reset-Posts
    $r1 = Send-OneAnswer $W -Lane "B" -Snapshot $SNAP_B -Index 2 -Text "Across a restart."
    $null = Get-NewMail $W
    [void]$W.ctx.state.Remove("chat")
    Check ((@(Get-AnswerAwaiting $W | Where-Object { $_.StartsWith($r1.id + ":") })).Count -eq 1) "the answer is in the ledger on disk"
    $script:stages[$r1.messengerId] = "handed-over"
    Set-HordeChatTakenClock -Ms ($base + 8020000)
    $null = Invoke-Tick $W
    Check ((@(Get-AnswerReceiptsOf $W $r1.id) -join ",") -ceq "accepted/delivered") "a new run reads the ledger and delivers it"
    Set-HordeChatTakenClock -Ms ($base + 9000000)
    Reset-Posts
    $g1 = Send-OneAnswer $W -Lane "B" -Snapshot $SNAP_B -Index 2 -Text "For the Glance."
    $null = Invoke-Tick $W
    Set-HordeChatTakenClock -Ms ($base + 9030000)
    Use-World $W
    Check ((Test-HordeChatChannelGlance -Context $W.ctx) -eq $true) "the Glance says yes when an awaiting answer is due to be asked about"
    $null = Invoke-Tick $W
    Set-HordeChatTakenClock -Ms ($base + 9030500)
    Check ((Test-HordeChatChannelGlance -Context $W.ctx) -eq $false) "and no right after it was asked"

    Write-Host ""
    Write-Host "--- ANS 9. wrong machine, wrong horde, no words, too long ---" -ForegroundColor Cyan
    Reset-Posts
    $m1 = [guid]::NewGuid().ToString("N")
    [void](Send-ToMachine $W (Get-AnswerEnvelope $W (New-AnswerBody -World $W -MessageId $m1 -Machine ("0" * 32))).text)
    $m2 = [guid]::NewGuid().ToString("N")
    [void](Send-ToMachine $W (Get-AnswerEnvelope $W (New-AnswerBody -World $W -MessageId $m2 -Horde "other")).text)
    $m3 = [guid]::NewGuid().ToString("N")
    [void](Send-ToMachine $W (Get-AnswerEnvelope $W (New-AnswerBody -World $W -MessageId $m3 -Text "   ")).text)
    $m4 = [guid]::NewGuid().ToString("N")
    [void](Send-ToMachine $W (Get-AnswerEnvelope $W (New-AnswerBody -World $W -MessageId $m4 -Text ("x" * 201))).text)
    $null = Invoke-Turn $W
    $all = @(Get-NewMail $W | Where-Object { $null -ne $_.body -and $_.body.kind -ceq "chat-answer-receipt" } | ForEach-Object { $_.body.messageId + "=" + $_.body.status + "/" + $_.body.code })
    Check ($script:postCalls -eq 0 -and ($all -contains ($m1 + "=refused/wrong-machine")) -and ($all -contains ($m2 + "=refused/wrong-horde")) -and ($all -contains ($m3 + "=refused/empty")) -and ($all -contains ($m4 + "=refused/too-long"))) ("each is refused with its code and nothing is posted (" + ($all -join ", ") + ")")

    Write-Host ""
    Write-Host "--- ANS 10. the phone's own sentences cover every code the machine can send ---" -ForegroundColor Cyan
    $phoneJs = [System.IO.File]::ReadAllText((Join-Path $root "relay\js\protocol.js"))
    $block = [regex]::Match($phoneJs, '(?s)export const ITEM_ANSWER_WORDS = \{(.*?)\n\};').Groups[1].Value
    $missing = New-Object System.Collections.ArrayList
    foreach ($st in $script:HordeChatAnswerCodes.Keys) { foreach ($c in $script:HordeChatAnswerCodes[$st]) { if (-not ($block -match ('(?:"' + [regex]::Escape($c) + '"|\b' + [regex]::Escape($c) + '\b):'))) { [void]$missing.Add($st + "/" + $c) } } }
    Check ($block.Length -gt 100 -and $missing.Count -eq 0) ("every code the machine can send has a sentence in the phone (" + ($missing -join ",") + ")")


    Write-Host ""
    Write-Host "--- ANS 11. review of PR 382: an age limit, an older list said so, the byte cap, an immediate Delivered ---" -ForegroundColor Cyan
    Reset-Posts; $script:postWoken = $true
    Set-HordeChatTakenClock -Ms ($base + 10000000)
    # S3: signed two days ago and never delivered: given up with a receipt, not carried to a session that comes back later.
    # (The journal itself refuses an envelope signed over ten minutes ago, so what can be old is one HELD and coming again: it is held first, the real clock then moves.)
    $oldId = [guid]::NewGuid().ToString("N")
    $script:seats["orc B"] = $null
    $oldA = Send-OneAnswer $W -Lane "B" -Snapshot $SNAP_B -Index 1 -Text "Signed on Friday." -MessageId $oldId
    Check ((@(Get-AnswerReceiptsOf $W $oldId) -join ",") -ceq "held/no-session") "CONTROL: an answer for an Orc with no session is held"
    $script:seats["orc B"] = "22222222-2222-4222-8222-222222222222"
    Set-HordeChatAnswerClock -Ms ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + 2 * 86400000)
    $turn = Invoke-Turn $W
    Set-HordeChatAnswerClock -Ms 0
    Check ($script:postCalls -eq 0 -and (@(Get-AnswerReceiptsOf $W $oldId) -join ",") -ceq "held/expired") ("an answer signed longer ago than ttlSeconds is given up held/expired with a receipt and posted nowhere (" + $turn.text + ")")
    $script:seats["orc B"] = $null
    $freshId = [guid]::NewGuid().ToString("N")
    $f1 = Send-OneAnswer $W -Lane "B" -Snapshot $SNAP_B -Index 1 -Text "Fresh, but B is away." -MessageId $freshId
    Check ((@(Get-AnswerReceiptsOf $W $freshId) -join ",") -ceq "held/no-session") "CONTROL: a fresh answer for an Orc with no session is still held, not expired"
    $script:seats["orc B"] = "22222222-2222-4222-8222-222222222222"
    $null = Invoke-Turn $W
    Check ($script:postCalls -eq 1) "and goes when the session is back"
    # N1: an answer to an item of a list that is no longer the Orc's newest says so.
    Reset-Posts; $script:postWoken = $true
    $ol = Send-OneAnswer $W -Lane "B" -Snapshot $SNAP_OLD -Index 1 -Text "About the older list."
    Check ($null -ne $ol.post -and $ol.post.message.body.Contains("NOTE: this is an older list of yours; your newest published list is not this one, so item 1 there may be another item.")) "an answer to an item of an older list tells the Orc so"
    $lv = Send-OneAnswer $W -Lane "B" -Snapshot $SNAP_B -Index 1 -Text "About the live list."
    Check ($null -ne $lv.post -and -not $lv.post.message.body.Contains("NOTE:")) "and an answer to the live list does not"
    # S8: the whole body is held to the messenger port's cap.
    Reset-Posts
    $capWas = $script:HordeMessengerBodyBytes
    try {
        $script:HordeMessengerBodyBytes = 200
        $cap = Send-OneAnswer $W -Lane "B" -Snapshot $SNAP_B -Index 1 -Text ("w" * 150)
        Check ($script:postCalls -eq 0 -and (@(Get-AnswerReceiptsOf $W $cap.id) -join ",") -ceq "refused/too-long") "a message over the messenger port's cap is refused too-long, nothing posted"
    } finally { $script:HordeMessengerBodyBytes = $capWas }
    # S8: a post the receiving side already took (stage seen) is Delivered at once, and is not awaited.
    Reset-Posts; $script:postWoken = $true; $script:postStage = "seen"
    $im = Send-OneAnswer $W -Lane "B" -Snapshot $SNAP_B -Index 2 -Text "Taken as it is posted."
    $script:postStage = ""
    Check ((@(Get-AnswerReceiptsOf $W $im.id) -join ",") -ceq "accepted/delivered" -and @(Get-AnswerAwaiting $W | Where-Object { $_.StartsWith($im.id + ":") }).Count -eq 0) "a post whose stage is already seen is Delivered at once and not awaited"

    Write-Host ""
    Write-Host "--- ANS 12. the REAL seat reader and the REAL item reader, together, against a temp fleet.db and an empty registry ---" -ForegroundColor Cyan
    Set-HordeChatAnswerSeat -Reader $null
    Set-HordeChatAnswerItemReader -Reader $null
    try {
        Reset-Posts; $script:postWoken = $true
        $nodeExe = (Get-Command node -ErrorAction SilentlyContinue)
        Check ($null -ne $nodeExe) "CONTROL: node is on this machine"
        $seedJs = Join-Path $root "test\fixtures\phone-published-seed.mjs"
        $itemsF = Join-Path $W.home "real-items.json"
        [System.IO.File]::WriteAllText($itemsF, '[{"text":"A real item one?"},{"text":"A real item two?"}]', $utf8)
        & $nodeExe.Source $seedJs seed $W.home
        $okSeed = ($LASTEXITCODE -eq 0)
        if ($okSeed) { & $nodeExe.Source $seedJs publish $W.home thrall $itemsF; $okSeed = ($LASTEXITCODE -eq 0) }
        Check $okSeed "CONTROL: fleet.db in the temp home holds the Thrall's list of two"
        $pub = Invoke-HordeDecisionNode -NodeArgs @("published", "--json") -FleetHome $W.home
        $realSnap = ""
        if ([int]$pub.code -eq 0) { $realSnap = "" + (@((ConvertFrom-HordeJson $pub.out).lists)[0].snapshot) }
        Check ($realSnap -cmatch $script:HordeChatAnswerSnapshotPattern) ("the list's snapshot id is read from the real node call (" + $realSnap + ")")
        $rk = Send-OneAnswer $W -Lane "thrall" -Snapshot $realSnap -Index 2 -Text "Through the real readers."
        $rrc = @(Get-AnswerReceiptsOf $W $rk.id)
        Check ($script:postCalls -eq 0 -and ($rrc -join ",") -ceq "held/no-session") ("the real item reader found the item (else this would be refused no-such-item) and the real seat reader found no session for the Thrall in the empty registry: held/no-session, nothing posted (" + ($rrc -join ",") + ")")
        $rw = Send-OneAnswer $W -Lane "B" -Snapshot $realSnap -Index 1 -Text "Wrong lane, real readers."
        Check ((@(Get-AnswerReceiptsOf $W $rw.id) -join ",") -ceq "refused/wrong-lane") "and the real item reader's owner is the Thrall's: another lane named on it is refused wrong-lane"
        $rn = Send-OneAnswer $W -Lane "thrall" -Snapshot $realSnap -Index 7 -Text "No such item, real readers."
        Check ((@(Get-AnswerReceiptsOf $W $rn.id) -join ",") -ceq "refused/no-such-item") "and an index the real list never had is refused no-such-item"
        $ob = Find-HordeChatAnswerSeat -Rank "orc" -Orc "B"
        Check ($ob.state -ceq "absent") ("the real label seat reader answers absent for Orc B in an empty registry (" + $ob.state + ")")
    } finally {
        Set-HordeChatAnswerSeat -Reader $seatReader
        Set-HordeChatAnswerItemReader -Reader $itemReader
    }

    Set-HordeChatTakenClock -Ms 0
    Reset-Posts
} finally {
    Set-HordeChatTakenClock -Ms 0
    Set-HordeChatAnswerSeat -Reader $null
    Set-HordeChatAnswerItemReader -Reader $null
    $env:HORDE_HOME = $realHome
    Exit-HordeTestEmptyFleet -Pin $fleetPin
    Set-HordeChatChannelSource -Options @{} -Vendor ""
    foreach ($w in $script:worlds) { Close-HordeRelayRunContext -Context $w.ctx }
    $keys = New-Object System.Collections.ArrayList
    foreach ($h in $script:homes) {
        $dir = Join-Path $h "relay\identity"
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter "machine-*.json")) {
            $mm = [regex]::Match([System.IO.File]::ReadAllText($f.FullName), '"scope":"([a-z]+)","signName":"([a-z0-9-]+)".*"agreeName":"([a-z0-9-]+)"')
            if ($mm.Success) { [void]$keys.Add(@{ n = $mm.Groups[2].Value; s = $mm.Groups[1].Value }); [void]$keys.Add(@{ n = $mm.Groups[3].Value; s = $mm.Groups[1].Value }) }
        }
    }
    foreach ($k in $keys) { try { [void](Remove-HordeRelayKey -Name $k.n -Scope $k.s) } catch { } }
    $left = @($keys | Where-Object { (Find-HordeRelayCngKey -Name $_.n -Scope $_.s) -cne "" })
    Check ($keys.Count -ge 2 -and $left.Count -eq 0) ("every key the suite made is gone (" + $keys.Count + ")")
    foreach ($h in $script:homes) { if ((Split-Path -Leaf $h) -match '^horde-relay-chat-[0-9a-f]{32}$') { Remove-Item -LiteralPath $h -Recurse -Force -ErrorAction SilentlyContinue } }
    Check (@($script:homes | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 0 -and -not (Test-Path -LiteralPath $fleetPin.path)) "every folder the suite made is gone"
}

Complete-HordeSuite -Success "an answer to an item of a published list goes once, from the founder's passkey only, to the session that owns the list and nowhere else; a list with no session is held and comes again; his phone is told Sent, then Delivered when that session takes it, with his words, and an answer not taken in time is an alarm once and never dropped"
