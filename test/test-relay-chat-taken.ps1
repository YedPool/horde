# DOES A LINE OF THE FOUNDER'S COUNT AS DELIVERED ONLY WHEN THE THRALL'S OWN SIDE SAYS SO - AND IS HE TOLD ON
# HIS PHONE WHEN IT DOES NOT?
#
# Task T-0281, the founder's bug of 2026-10-19: a line from the app was posted to the Thrall's mail, the
# knock was refused (the box was occupied), the runner marked the record done, and nothing ever said the
# Thrall had not been prompted; it read the line 11 minutes later. channels/chat/Taken.ps1 is the fix; this
# suite attacks its rule with the Thrall's own side played by the test messenger's stage:
#   - a line accepted but not taken is awaited, in the durable state, before its record is done;
#   - it is delivered ONLY when the stage is handed-over or seen; an unknown, absent or accepted stage is
#     never a confirmation;
#   - not taken in takenAlarmSeconds: ONE alarm receipt (held, not-now: still trying) to the phone, never two, and
#     the line is not dropped: a late confirmation turns the alarm into delivered;
#   - a stale seat (held by the fleet), a target that is not running (no answer), a receipt that never
#     comes (ttl), a receipt that comes late, a duplicate line, a restart, a state that cannot be written,
#     the Glance, and a state from before the list.
# NO REAL FLEET IS TOUCHED: see test-relay-channel-chat.ps1, whose scaffold this is.

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
    $said = [ordered]@{ messageId = $id; stage = "accepted"; at = [datetime]::UtcNow; reason = $script:postWhy }
    if ($null -ne $script:postWoken) { $said["woken"] = $script:postWoken }
    return (New-HordeKnown -Value ([pscustomobject]$said))
}
# What a test messenger says of its knock: $null says nothing, as before; true or false is its woken.
$script:postWoken = $null
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

try {
    $base = Get-NowMs
    Set-HordeChatTakenClock -Ms $base
    $S = '{"sendIntervalMs": 0, "startTurns": 3, "takenAlarmSeconds": 90, "takenCheckSeconds": 10, "takenAfterAlarmSeconds": 60, "ttlSeconds": 3600}'
    Write-Host ""
    Write-Host "--- TAKEN 1. a line accepted but not woken is awaited, and the founder is told when it is not taken ---" -ForegroundColor Cyan
    $W = New-World -Settings $S
    $null = Invoke-Tick $W
    $null = Get-NewMail $W
    Reset-Posts
    $null = Register-TestMessenger "chat-wakes"
    $script:postWoken = $false; $script:postWhy = "send-refused"
    $a = Send-OneLine $W "Park the Orcs by date."
    $rc = @(Get-ReceiptsOf $W $a.id)
    Check ((($rc -join ",") -ceq "accepted/queued")) ("the line is accepted and its receipt says only queued (" + ($rc -join ",") + ")")
    $aw = @(Get-Awaiting $W)
    Check ($aw.Count -eq 1 -and $aw[0].StartsWith($a.id + ":")) ("and it is AWAITED in the durable state, owned by the list from the moment its record was done (" + $aw.Count + ")")
    Check ($aw.Count -eq 1 -and $aw[0].EndsWith(":0:0")) "not alarmed, and the knock did not wake the Thrall"
    $state = [System.IO.File]::ReadAllText((Join-Path $W.home "relay\chat\state.json"))
    Check (-not $state.Contains("Park the Orcs")) "the state holds the mark and no word of the line"
    Check ((Has $a.turn "done ") -and (Has $a.turn "awaiting the Thrall")) ("the runner's line says it is done only as AWAITING the Thrall's own side (" + $a.turn.text + ")")
    # 30 s on: still inside the window, nothing is said.
    Set-HordeChatTakenClock -Ms ($base + 30000)
    $t = Invoke-Tick $W
    Check (@(Get-ReceiptsOf $W $a.id).Count -eq 0 -and -not (($t.lines -join "|").Contains("ALARM"))) "30 s on, inside the window: the line was asked about, and nothing is said"
    Check ($script:statusAsks -ge 1) ("the fleet was asked where the line is (" + $script:statusAsks + " asks)")
    # 95 s on: past takenAlarmSeconds, still accepted: ONE alarm to the phone.
    Set-HordeChatTakenClock -Ms ($base + 95000)
    $t = Invoke-Tick $W
    $rc = @(Get-ReceiptsOf $W $a.id)
    Check ((($rc -join ",") -ceq "held/not-now")) ("95 s on, not taken: the phone gets ONE alarm receipt, held/not-now, still trying (" + ($rc -join ",") + ")")
    Check ((($t.lines -join "|").Contains("ALARM: chat line " + $a.id)) -and (($t.lines -join "|").Contains("Thrall was not woken"))) ("and the runner's log carries an ALARM line that says the Thrall was not woken (" + ($t.lines -join " | ") + ")")
    $aw = @(Get-Awaiting $W)
    Check ($aw.Count -eq 1 -and $aw[0].EndsWith(":1:0")) "the line is NOT dropped: it is still awaited, marked alarmed"
    foreach ($ms in 100000, 160000, 400000) {
        Set-HordeChatTakenClock -Ms ($base + $ms)
        $null = Invoke-Tick $W
    }
    Check (@(Get-ReceiptsOf $W $a.id).Count -eq 0) "asked again and again after the alarm, never alarmed a second time"
    Check (@(Get-Awaiting $W).Count -eq 1) "and still awaited"

    Write-Host ""
    Write-Host "--- TAKEN 2. the receipt that comes LATE turns the alarm into delivered ---" -ForegroundColor Cyan
    $script:stages[$a.messengerId] = "seen"
    Set-HordeChatTakenClock -Ms ($base + 520000)
    $t = Invoke-Tick $W
    $rc = @(Get-ReceiptsOf $W $a.id)
    Check ((($rc -join ",") -ceq "accepted/delivered")) ("seen by the Thrall's own hook, late: delivered, after the alarm (" + ($rc -join ",") + ")")
    Check (@(Get-Awaiting $W).Count -eq 0) "and the line leaves the list"
    Check (($t.lines -join "|").Contains("TAKEN by the Thrall's own side")) "the log says it was TAKEN"
    $null = Invoke-Tick $W
    Set-HordeChatTakenClock -Ms ($base + 700000)
    $null = Invoke-Tick $W
    Check (@(Get-ReceiptsOf $W $a.id).Count -eq 0) "and delivered is said once, however often the fleet is asked after"

    Write-Host ""
    Write-Host "--- TAKEN 3. a line taken in time is delivered, and never alarmed ---" -ForegroundColor Cyan
    Set-HordeChatTakenClock -Ms ($base + 1000000)
    $b = Send-OneLine $W "Done in time."
    $null = Get-NewMail $W
    $script:stages[$b.messengerId] = "handed-over"
    Set-HordeChatTakenClock -Ms ($base + 1020000)
    $null = Invoke-Tick $W
    $rc = @(Get-ReceiptsOf $W $b.id)
    Check ((($rc -join ",") -ceq "accepted/delivered")) ("handed over by the Thrall's own hook 20 s after the post: delivered (" + ($rc -join ",") + ")")
    Set-HordeChatTakenClock -Ms ($base + 1500000)
    $null = Invoke-Tick $W
    Check (@(Get-ReceiptsOf $W $b.id).Count -eq 0 -and @(Get-Awaiting $W).Count -eq 0) "long after, no alarm: it was confirmed"

    Write-Host ""
    Write-Host "--- TAKEN 4. a stale seat: the fleet holds the line for good ---" -ForegroundColor Cyan
    Set-HordeChatTakenClock -Ms ($base + 2000000)
    $c = Send-OneLine $W "To a seat that moved."
    $null = Get-NewMail $W
    $script:stages[$c.messengerId] = "held"
    Set-HordeChatTakenClock -Ms ($base + 2012000)
    $null = Invoke-Tick $W
    $rc = @(Get-ReceiptsOf $W $c.id)
    Check ((($rc -join ",") -ceq "held/not-delivered")) ("held by the fleet (the seat is another session's now): the phone is told at once, not at 90 s (" + ($rc -join ",") + ")")
    Check (@(Get-Awaiting $W).Count -eq 0) "and it leaves the list: it is final"

    Write-Host ""
    Write-Host "--- TAKEN 5. the target is not running: no answer is not a confirmation ---" -ForegroundColor Cyan
    Set-HordeChatTakenClock -Ms ($base + 3000000)
    $d = Send-OneLine $W "Nobody home."
    $null = Get-NewMail $W
    $script:stages[$d.messengerId] = "throw"
    Set-HordeChatTakenClock -Ms ($base + 3050000)
    $null = Invoke-Tick $W
    Check (@(Get-ReceiptsOf $W $d.id).Count -eq 0 -and @(Get-Awaiting $W).Count -eq 1) "within the window a status that cannot be had says nothing and the line stays awaited"
    Set-HordeChatTakenClock -Ms ($base + 3100000)
    $null = Invoke-Tick $W
    $rc = @(Get-ReceiptsOf $W $d.id)
    Check ((($rc -join ",") -ceq "held/not-now")) ("past the window an unknown status is alarmed on the clock alone (" + ($rc -join ",") + ")")
    $script:stages[$d.messengerId] = "absent"
    Set-HordeChatTakenClock -Ms ($base + 3200000)
    $null = Invoke-Tick $W
    Check (@(Get-ReceiptsOf $W $d.id).Count -eq 0 -and @(Get-Awaiting $W).Count -eq 1) "the fleet having no record of it is not a confirmation either: still awaited, still one alarm"

    Write-Host ""
    Write-Host "--- TAKEN 6. a receipt that never comes: the line is given up at ttlSeconds, and the phone is told ---" -ForegroundColor Cyan
    Set-HordeChatTakenClock -Ms ($base + 3100000 + 3700000)
    $null = Invoke-Tick $W
    $rc = @(Get-ReceiptsOf $W $d.id)
    Check ((($rc -join ",") -ceq "held/expired")) ("an hour on, never taken: held/expired (" + ($rc -join ",") + ")")
    Check (@(Get-Awaiting $W).Count -eq 0) "and the list is empty"

    Write-Host ""
    Write-Host "--- TAKEN 7. a duplicate line is one awaited line, with its own first clock ---" -ForegroundColor Cyan
    Set-HordeChatTakenClock -Ms ($base + 8000000)
    $e = Send-OneLine $W "Say it twice."
    $null = Get-NewMail $W
    $first = @(Get-Awaiting $W)
    Set-HordeChatTakenClock -Ms ($base + 8060000)
    [void](Send-ToMachine $W (Get-Line $W -MessageId $e.id -Text "Say it twice.").text)
    $turn = Invoke-Turn $W
    $second = @(Get-Awaiting $W)
    Check ($first.Count -eq 1 -and $second.Count -eq 1 -and $first[0] -ceq $second[0]) ("the same line sent again (re-signed) is not awaited twice and does not get a new clock (" + $second.Count + ")")
    $script:stages[$e.messengerId] = "seen"
    Set-HordeChatTakenClock -Ms ($base + 8070000)
    $null = Invoke-Tick $W
    Set-HordeChatTakenClock -Ms ($base + 8200000)
    $null = Invoke-Tick $W
    $rc = @(Get-ReceiptsOf $W $e.id)
    Check (@($rc | Where-Object { $_ -ceq "accepted/delivered" }).Count -eq 1 -and -not ($rc -contains "held/not-now")) ("one confirmation, one delivered receipt, no alarm (" + ($rc -join ",") + ")")

    Write-Host ""
    Write-Host "--- TAKEN 8. a restart loses nothing: the list is durable and the words come back from the journal ---" -ForegroundColor Cyan
    Set-HordeChatTakenClock -Ms ($base + 9000000)
    $f = Send-OneLine $W "Across a restart."
    $null = Get-NewMail $W
    Close-HordeRelayRunContext -Context $W.ctx
    $W.ctx = (New-HordeRelayRunContext -HordeHome $W.home -Connection $W.conn).value
    Check (@(Get-Awaiting $W).Count -eq 1) "the list survived: one line awaited on disk"
    Set-HordeChatTakenClock -Ms ($base + 9100000)
    $t = Invoke-Tick $W
    $rcAll = @(Get-Receipts @(Get-NewMail $W) | Where-Object { $_.messageId -ceq $f.id })
    Check ($rcAll.Count -eq 1 -and $rcAll[0].code -ceq "not-now" -and $rcAll[0].text -ceq "Across a restart.") ("after the restart the alarm still comes, with the line's own words read back from the journal (" + ($t.lines -join " | ") + ")")

    Write-Host ""
    Write-Host "--- TAKEN 9. the list is written BEFORE the record is done: a state that cannot be written holds the record ---" -ForegroundColor Cyan
    $G = New-World -Settings $S
    $null = Invoke-Tick $G
    $null = Get-NewMail $G
    $statePath = Join-Path $G.home "relay\chat\state.json"
    Remove-Item -LiteralPath $statePath -Force
    New-Item -ItemType Directory -Path $statePath | Out-Null
    $g1 = Send-OneLine $G "Hold me until the state can be written."
    Check ((Has $g1.turn "retry") -and -not (Has $g1.turn "done ")) ("state unwritable: the record is retried, not done (" + $g1.turn.text + ")")
    Use-World $G
    $mem = Get-HordeChatChannelMemory -Context $G.ctx
    Check ($mem.ok -and @($mem.mine.durable.awaiting).Count -eq 0) "and the line is not left on the list in memory either, so the retry adds it again and writes it"
    Remove-Item -LiteralPath $statePath -Recurse -Force
    $turn = Invoke-Turn $G
    Check ((Has $turn "done ") -and @(Get-Awaiting $G).Count -eq 1) ("once it can be written the record is done, and awaited (" + $turn.text + ")")
    Check (@(Get-Records | Where-Object { $_.message.body -like "*Hold me until*" }).Count -eq 1) "and the messenger kept the repeated post as one"

    Write-Host ""
    Write-Host "--- TAKEN 10. the Glance says yes when a line is due to be asked about, and no when it is not ---" -ForegroundColor Cyan
    $H = New-World -Settings $S
    Set-HordeChatTakenClock -Ms ($base + 20000000)
    $null = Invoke-Tick $H
    $null = Get-NewMail $H
    $h1 = Send-OneLine $H "Glance at me."
    $null = Invoke-Tick $H
    Use-World $H
    Check (-not (Test-HordeChatChannelGlance -Context $H.ctx)) "just posted and just asked: not due, the Glance says no"
    Set-HordeChatTakenClock -Ms ($base + 20011000)
    Check (Test-HordeChatChannelGlance -Context $H.ctx) "11 s on: due, so the Glance says yes and the Tick runs inside the watch, not after it"
    $script:stages[$h1.messengerId] = "seen"
    $null = Invoke-Tick $H

    Write-Host ""
    Write-Host "--- TAKEN 11. a state written before the list existed still reads ---" -ForegroundColor Cyan
    $old = Join-Path $env:TEMP ("horde-relay-chat-" + [guid]::NewGuid().ToString("N"))
    [void]$script:homes.Add($old)
    New-Item -ItemType Directory -Path (Join-Path $old "relay\chat") -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $old "relay\chat\state.json"), '{"v":1,"cursor":null,"session":"","phones":[],"pending":[],"lines":[],"rewind":null}', $utf8)
    $rs = Read-HordeChatChannelState -HordeHome $old
    Check ($rs.state -ceq "known" -and @($rs.value.awaiting).Count -eq 0) "a state with no awaiting member reads as an empty list"
    [System.IO.File]::WriteAllText((Join-Path $old "relay\chat\state.json"), '{"v":1,"cursor":null,"session":"","phones":[],"pending":[],"lines":[],"awaiting":["not a mark"],"rewind":null}', $utf8)
    $rs = Read-HordeChatChannelState -HordeHome $old
    Check ($rs.state -ceq "unknown") "and an awaiting entry that is not a mark stops the channel, in words, never a guess"

    Write-Host ""
    Write-Host "--- TAKEN 12. the pure rule ---" -ForegroundColor Cyan
    $known = { param([string]$St) New-HordeKnown -Value ([pscustomobject]@{ stage = $St }) }
    Check ((Get-HordeChatTakenAction -Status (& $known "accepted") -AgeSeconds 5 -Alarmed $false -AlarmSeconds 90 -TtlSeconds 3600) -ceq "wait") "accepted and young: wait"
    Check ((Get-HordeChatTakenAction -Status (& $known "accepted") -AgeSeconds 90 -Alarmed $false -AlarmSeconds 90 -TtlSeconds 3600) -ceq "alarm") "accepted at the alarm age: alarm"
    Check ((Get-HordeChatTakenAction -Status (& $known "accepted") -AgeSeconds 900 -Alarmed $true -AlarmSeconds 90 -TtlSeconds 3600) -ceq "wait") "already alarmed: wait, never a second alarm"
    Check ((Get-HordeChatTakenAction -Status (& $known "seen") -AgeSeconds 900 -Alarmed $true -AlarmSeconds 90 -TtlSeconds 3600) -ceq "confirmed") "seen: confirmed, whatever its age"
    Check ((Get-HordeChatTakenAction -Status (& $known "handed-over") -AgeSeconds 1 -Alarmed $false -AlarmSeconds 90 -TtlSeconds 3600) -ceq "confirmed") "handed over: confirmed"
    Check ((Get-HordeChatTakenAction -Status (New-HordeUnknown -Reason "x") -AgeSeconds 91 -Alarmed $false -AlarmSeconds 90 -TtlSeconds 3600) -ceq "alarm") "an unknown status is not a confirmation: the clock decides"
    Check ((Get-HordeChatTakenAction -Status (New-HordeAbsent -Note "x") -AgeSeconds 3600 -Alarmed $true -AlarmSeconds 90 -TtlSeconds 3600) -ceq "expired") "an absent status at ttl: expired"
    Check ((Get-HordeChatTakenAction -Status (& $known "expired") -AgeSeconds 1 -Alarmed $false -AlarmSeconds 90 -TtlSeconds 3600) -ceq "expired") "given up by the fleet: expired"
    Check ((Get-HordeChatTakenAction -Status (& $known "held") -AgeSeconds 1 -Alarmed $false -AlarmSeconds 90 -TtlSeconds 3600) -ceq "held") "held by the fleet: held"
    Write-Host ""
    Write-Host "--- TAKEN 13. the cadence of the asking, and a line the phone cannot be told of is not forgotten ---" -ForegroundColor Cyan
    $base2 = $base + 20000000
    Set-HordeChatTakenClock -Ms $base2
    $W2 = New-World -NoPhoneKey -Settings $S
    $null = Invoke-Tick $W2
    Reset-Posts
    Remove-TestMessengers
    $null = Register-TestMessenger "chat-wakes"
    $e = Send-OneLine $W2 "No phone key yet."
    Check ($e.messengerId -cne "" -and @(Get-Awaiting $W2).Count -eq 1) ("the line is accepted and awaited even though no phone key is trusted yet (" + @(Get-Awaiting $W2).Count + ")")
    $script:statusAsks = 0
    Set-HordeChatTakenClock -Ms ($base2 + 2000)
    $null = Invoke-Tick $W2
    Check ($script:statusAsks -eq 0) ("2 s on, inside takenCheckSeconds: the fleet is not asked again (" + $script:statusAsks + " asks)")
    Set-HordeChatTakenClock -Ms ($base2 + 12000)
    $null = Invoke-Tick $W2
    $null = Invoke-Tick $W2
    Check ($script:statusAsks -eq 1) ("12 s on: asked once, and not again by the next turn of the runner (" + $script:statusAsks + " asks)")
    $script:stages[$e.messengerId] = "handed-over"
    Set-HordeChatTakenClock -Ms ($base2 + 25000)
    $t = Invoke-Tick $W2
    Check (@(Get-Awaiting $W2).Count -eq 1) ("taken, but the phone cannot be told (no key): the line stays awaited, not forgotten (" + ($t.lines -join " | ") + ")")
    Add-PhoneKey -HordeHome $W2.home -Phone $W2.phone
    Set-HordeChatTakenClock -Ms ($base2 + 40000)
    $null = Invoke-Tick $W2
    $rc = @(Get-ReceiptsOf $W2 $e.id)
    Check (@(Get-Awaiting $W2).Count -eq 0 -and $rc -ccontains "accepted/delivered") ("once the phone can be told it gets delivered, and the list is empty (" + ($rc -join ",") + ")")

    Write-Host ""
    Write-Host "--- TAKEN 14. a SESSION-signed line keeps its receipts whatever happens to the session later (M1) ---" -ForegroundColor Cyan
    # (a) accepted, every phone session ended at the PC, then the Thrall takes it: delivered.
    Set-HordeChatTakenClock -Ms ($base + 30000000)
    $W3 = New-World -Settings $S
    $null = Invoke-Tick $W3
    $null = Get-NewMail $W3
    Reset-Posts
    Remove-TestMessengers
    $null = Register-TestMessenger "chat-wakes"
    $sess = New-HordeTestPhoneSession -Phone $W3.phone -Machine $W3.id.sign.keyId -Seq 1
    $s1 = Send-OneSessionLine $W3 $sess "Session words, ended then taken."
    $rc = @(Get-ReceiptsOf $W3 $s1.id)
    Check ((($rc -join ",") -ceq "accepted/queued") -and @(Get-Awaiting $W3).Count -eq 1) ("CONTROL: the session-signed line is accepted, queued and awaited (" + ($rc -join ",") + "; " + $s1.turn.text + ")")
    $end = Stop-HordeRelaySessions -HordeHome $W3.home -Reason "T-0281 suite: end all"
    Check ($end.state -ceq "known") "CONTROL: every phone session was ended at the PC"
    $script:stages[$s1.messengerId] = "seen"
    Set-HordeChatTakenClock -Ms ($base + 30020000)
    $t = Invoke-Tick $W3
    $rc = @(Get-ReceiptsOf $W3 $s1.id)
    Check ((($rc -join ",") -ceq "accepted/delivered")) ("session ENDED, then the Thrall took the line: delivered (" + ($rc -join ",") + "; " + ($t.lines -join " | ") + ")")
    Check (@(Get-Awaiting $W3).Count -eq 0) "and it left the list"
    $rcw = @(Get-Receipts @(Get-NewMail $W3 -All) | Where-Object { $_.messageId -ceq $s1.id -and $_.code -ceq "delivered" })
    Check ($rcw.Count -ge 1 -and $rcw[0].text -ceq "Session words, ended then taken.") "with the line's own words read back"
    # (b) accepted, sessions ended, never taken: ONE alarm, and the line stays awaited. (A world of its
    # own: an unlock made just after an end-all is itself ended.)
    $W3b = New-World -Settings $S
    $null = Invoke-Tick $W3b
    $null = Get-NewMail $W3b
    $sessB = New-HordeTestPhoneSession -Phone $W3b.phone -Machine $W3b.id.sign.keyId -Seq 1
    Set-HordeChatTakenClock -Ms ($base + 30100000)
    $s2 = Send-OneSessionLine $W3b $sessB "Session words, ended, never taken."
    $null = Get-NewMail $W3b
    $end = Stop-HordeRelaySessions -HordeHome $W3b.home -Reason "T-0281 suite: end all two"
    Set-HordeChatTakenClock -Ms ($base + 30200000)
    $t = Invoke-Tick $W3b
    $rc = @(Get-ReceiptsOf $W3b $s2.id)
    Check ((($rc -join ",") -ceq "held/not-now")) ("session ENDED, never taken: ONE alarm on the phone (" + ($rc -join ",") + "; " + ($t.lines -join " | ") + "; accept: " + $s2.turn.text + ")")
    Check (@(Get-Awaiting $W3b).Count -eq 1) "and the line is still awaited"
    $script:stages[$s2.messengerId] = "handed-over"
    Set-HordeChatTakenClock -Ms ($base + 30400000)
    $null = Invoke-Tick $W3b
    $rc = @(Get-ReceiptsOf $W3b $s2.id)
    Check ((($rc -join ",") -ceq "accepted/delivered")) ("and a late TAKEN, the session long gone, turns the alarm into delivered (" + ($rc -join ",") + ")")
    # (c) idle limit 1 minute: alarmed while the session is fresh, the session idles, the Thrall takes it.
    $W4 = New-World -Settings $S
    [System.IO.File]::WriteAllText((Join-Path $W4.home (Join-Path "settings" "relay-sessions.json")), '{"schemaVersion": 1, "settings": {"idleMinutes": 1}}', $utf8)
    $null = Invoke-Tick $W4
    $null = Get-NewMail $W4
    $sessC = New-HordeTestPhoneSession -Phone $W4.phone -Machine $W4.id.sign.keyId -Seq 1
    Set-HordeChatTakenClock -Ms ($base + 31000000)
    $s3 = Send-OneSessionLine $W4 $sessC "Session words, idle then taken."
    Set-HordeChatTakenClock -Ms ($base + 31100000)
    $null = Invoke-Tick $W4
    $rc = @(Get-ReceiptsOf $W4 $s3.id)
    Check ((($rc -join ",") -ceq "accepted/queued,held/not-now")) ("CONTROL: queued, then the alarm while the session is fresh (" + ($rc -join ",") + ")")
    Start-Sleep -Seconds 70
    $script:stages[$s3.messengerId] = "seen"
    Set-HordeChatTakenClock -Ms ($base + 31200000)
    $t = Invoke-Tick $W4
    $rc = @(Get-ReceiptsOf $W4 $s3.id)
    Check ((($rc -join ",") -ceq "accepted/delivered")) ("session IDLE (limit 1 min), then the Thrall took it: the alarm becomes delivered (" + ($rc -join ",") + "; " + ($t.lines -join " | ") + ")")
    Check (@(Get-Awaiting $W4).Count -eq 0) "and it left the list"
    # (d) a record that truly cannot be opened is never dropped in silence: an ALARM line names the line.
    Set-HordeChatTakenClock -Ms ($base + 32000000)
    $s4 = Send-OneSessionLine $W4 (New-HordeTestPhoneSession -Phone $W4.phone -Machine $W4.id.sign.keyId -Seq 2) "Session words, record lost."
    $null = Get-NewMail $W4
    $awm = @(Get-Awaiting $W4)
    $e4 = ConvertFrom-HordeChatTakenMark -Mark $awm[0]
    Use-World $W4
    $e4.seq = [long]99999
    $words4 = Get-HordeChatTakenWords -Context $W4.ctx -Entry $e4
    Check ($words4.state -cne "ok") ("CONTROL: a mark whose record is not in the journal gives no words (" + $words4.state + ")")
    $rs = Read-HordeChatChannelState -HordeHome $W4.home
    $st = $rs.value
    $st.awaiting = @(ConvertTo-HordeChatTakenMark -Entry $e4)
    Write-HordeChatChannelState -HordeHome $W4.home -State $st
    Close-HordeRelayRunContext -Context $W4.ctx
    $W4.ctx = (New-HordeRelayRunContext -HordeHome $W4.home -Connection $W4.conn).value
    $script:stages[$s4.messengerId] = "seen"
    Set-HordeChatTakenClock -Ms ($base + 32000000 + 3700000)
    $t = Invoke-Tick $W4
    Check ((($t.lines -join "|").Contains("ALARM: chat line " + $s4.id)) -and (($t.lines -join "|").Contains("could NOT be told"))) ("a line whose record cannot be opened leaves with an ALARM line naming it, not in silence (" + ($t.lines -join " | ") + ")")

    Write-Host ""
    Write-Host "--- TAKEN 15. a line already awaited and ALARMED is not answered 'Sent' again over its alarm (S1) ---" -ForegroundColor Cyan
    $W5 = New-World -Settings $S
    Set-HordeChatTakenClock -Ms ($base + 40000000)
    $null = Invoke-Tick $W5
    $null = Get-NewMail $W5
    Reset-Posts
    Remove-TestMessengers
    $null = Register-TestMessenger "chat-wakes"
    $r1 = Send-OneLine $W5 "Duplicate after the alarm."
    $null = Get-NewMail $W5
    Set-HordeChatTakenClock -Ms ($base + 40100000)
    $null = Invoke-Tick $W5
    $rc = @(Get-ReceiptsOf $W5 $r1.id)
    Check ((($rc -join ",") -ceq "held/not-now")) ("the alarm is out (" + ($rc -join ",") + ")")
    $awA = @(Get-Awaiting $W5)
    [void](Send-ToMachine $W5 (Get-Line $W5 -MessageId $r1.id -Text "Duplicate after the alarm.").text)
    $turn = Invoke-Turn $W5
    $rc = @(Get-ReceiptsOf $W5 $r1.id)
    Check ($rc.Count -eq 0) ("the same line coming again (re-signed) sends no 'Sent' over the alarm (" + ($rc -join ",") + "; " + $turn.text + ")")
    $awB = @(Get-Awaiting $W5)
    Check ($awB.Count -eq 1 -and $awB[0] -ceq $awA[0] -and $awB[0].EndsWith(":1:0")) "and the line keeps its alarmed mark and its own clock"
    Check (Has $turn "done ") "and the duplicate's record is done, not stuck"

    Write-Host ""
    Write-Host "--- TAKEN 16. past the list's size the oldest line is never dropped in silence (S2) ---" -ForegroundColor Cyan
    $script:HordeChatTakenKept = 3
    try {
        $W6 = New-World -Settings $S
        Set-HordeChatTakenClock -Ms ($base + 50000000)
        $null = Invoke-Tick $W6
        $null = Get-NewMail $W6
        Reset-Posts
        Remove-TestMessengers
        $null = Register-TestMessenger "chat-wakes"
        $ov = @()
        foreach ($i in 1..4) { $ov += Send-OneLine $W6 ("Overflow line " + $i + ".") }
        $aw = @(Get-Awaiting $W6)
        Check ($aw.Count -eq 3 -and -not ($aw -join ",").Contains($ov[0].id)) ("the list holds 3, the oldest is off it (" + $aw.Count + ")")
        $rc = @(Get-ReceiptsOf $W6 $ov[0].id)
        Check (($rc -join ",") -ceq "accepted/queued,held/not-delivered") ("the oldest line's phone was told it was NOT delivered (" + ($rc -join ",") + ")")
        Check ((Has $ov[3].turn ("ALARM: chat line " + $ov[0].id)) -and (Has $ov[3].turn "awaiting list is full")) ("and the runner's log carries an ALARM line naming it (" + $ov[3].turn.text + ")")
        $rc3 = @(Get-ReceiptsOf $W6 $ov[3].id)
        Check ($rc3.Count -eq 0 -or ($rc3 -join ",") -ceq "accepted/queued") "the newest line is not touched"
    } finally { $script:HordeChatTakenKept = 200 }

    Write-Host ""
    Write-Host "--- TAKEN 17. the fleet is asked about a bounded number of lines per tick, the longest-unasked first (S3) ---" -ForegroundColor Cyan
    $script:HordeChatTakenAsksPerTick = 4
    try {
        $W7 = New-World -Settings $S
        Set-HordeChatTakenClock -Ms ($base + 60000000)
        $null = Invoke-Tick $W7
        $null = Get-NewMail $W7
        Reset-Posts
        Remove-TestMessengers
        $null = Register-TestMessenger "chat-wakes"
        $many = @()
        foreach ($i in 1..9) { $many += Send-OneLine $W7 ("Bounded line " + $i + ".") }
        $script:statusAsks = 0
        # The LAST line is taken already: a tick that asks the oldest four first does not reach it yet.
        $script:stages[$many[8].messengerId] = "handed-over"
        Set-HordeChatTakenClock -Ms ($base + 60015000)
        $t = Invoke-Tick $W7
        Check (@(Get-ReceiptsOf $W7 $many[8].id | Where-Object { $_ -ceq "accepted/delivered" }).Count -eq 0) "the longest-waiting four were asked first: the newest line was not yet reached"
        Check ($script:statusAsks -eq 4) ("9 lines due: the fleet is asked about 4 and no more (" + $script:statusAsks + " asks)")
        Check (($t.lines -join "|").Contains("5 of 9 awaiting lines wait for the next tick")) ("and the log says how many wait (" + ($t.lines -join " | ") + ")")
        $script:statusAsks = 0
        $t = Invoke-Tick $W7
        Check ($script:statusAsks -eq 4) ("the next tick asks the next 4 - the ones not yet asked first (" + $script:statusAsks + " asks)")
        $script:statusAsks = 0
        $t = Invoke-Tick $W7
        Check ($script:statusAsks -eq 1) ("then the last one (" + $script:statusAsks + " asks): every line is asked in turn, none starved")
        Check (@(Get-ReceiptsOf $W7 $many[8].id | Where-Object { $_ -ceq "accepted/delivered" }).Count -eq 1) "and it was reached in its turn: delivered"
        # A line posted while the others wait is accepted at once: the tick does not hold the inbound path.
        Set-HordeChatTakenClock -Ms ($base + 60016000)
        $fresh = Send-OneLine $W7 "A new line of the founder."
        Check ($fresh.messengerId -cne "" -and (Has $fresh.turn "done ")) "a new founder line is accepted in the same breath, not behind the status checks"
    } finally { $script:HordeChatTakenAsksPerTick = 10 }

    Write-Host ""
    Write-Host "--- TAKEN 18. the alarm reads as still-trying and differs from the final held outcome (S4) ---" -ForegroundColor Cyan
    Check ($script:HordeChatTakenAlarmCode -ceq "not-now" -and $script:HordeChatTakenAlarmCode -cne "not-delivered") "the alarm code is held/not-now, not the final held/not-delivered"
    $phoneJs = [System.IO.File]::ReadAllText((Join-Path $root "relay\js\protocol.js"))
    $mm = [regex]::Match($phoneJs, '"not-now": "([^"]+)"')
    Check ($mm.Success -and $mm.Groups[1].Value -match 'try again') ("the phone's own sentence for that code says it will try again (" + $mm.Groups[1].Value + ")")

    Set-HordeChatTakenClock -Ms 0
    Reset-Posts
} finally {
    Set-HordeChatTakenClock -Ms 0
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

Complete-HordeSuite -Success "a line of the founder is delivered only when the Thrall's own side has taken it; one not taken in time is an alarm on his phone, once, never dropped, and a late confirmation turns it into delivered"
