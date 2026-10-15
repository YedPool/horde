# DO THE FOUNDER'S NOTICES REACH HIS PHONE SEALED, CARRYING THE FOLLOW SWITCHES THE MACHINE HOLDS - AND DOES
# A SWITCH HE SETS REACH THE MACHINE ONLY WHEN HIS PASSKEY SIGNED IT FOR THIS MACHINE, AND MAKE A FOLLOWED
# LANE'S NEW PROGRESS ENTRIES, AND NEVER ITS OLD ONES, NOTICES?
#
# The notices channel (channels/notices) over relays/local in this process, with a phone held in memory
# (test/lib/RelayPhone.ps1), a progress log and an area map of the suite's own, under homes of its own.
# It attacks:
#   1. OUT: a notice is sealed to the trusted phone key and opened by it, with the switches; nothing is
#      sent again when nothing changed; a phone key trusted since is sent the newest, to it alone; the
#      mailbox holds the last keepEnvelopes; the Glance says yes for a new notice and no after the Tick.
#   2. IN: a switch signed by the founder's passkey turns a lane on and the next envelope carries it; the
#      same switch again is done and changes nothing; a switch for another machine, a body with a member
#      added, a FORGED one (named for his passkey, signed by another), one from an UNKNOWN passkey and one
#      from a TRUSTED PEER MACHINE are refused, and none changes a switch.
#   3. FOLLOWING THE LOG: what the log held before the first look never becomes a notice, even of a
#      followed lane; a followed lane's new entry is one notice; an unfollowed lane's none; an entry whose
#      AREA maps to two lanes is one notice when either is followed; a log replaced, by a shorter file or by
#      a longer one, is followed again from its new end, said, and nothing in it before that end becomes a
#      notice; every notices envelope carries the switches the machine holds.
#   4. NOTHING ELSE comes in on the channel: a kind it does not take is refused at the gate.
#
# NO REAL FLEET, HOME OR RELAY IS TOUCHED: the fleet root is an empty folder of the suite's own
# (test/lib/FleetPin.ps1); every home, log and mailbox is under %TEMP% and is removed at the end.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\FleetPin.ps1")
$fleetPin = Enter-HordeTestEmptyFleet
. (Join-Path $root "core\ModuleSettings.ps1")
. (Join-Path $root "channels\Port.ps1")
foreach ($f in @(Get-HordeRelayFiles)) { . $f }
foreach ($f in @(Get-HordeRelayChannelFiles)) { . $f }
. (Join-Path $root "cli\RelayRun.ps1")
. (Join-Path $root "test\lib\RelayPhone.ps1")
Set-StrictMode -Version Latest
Write-Host ("  runtime: PowerShell " + $PSVersionTable.PSVersion + " (" + $PSVersionTable.PSEdition + ")") -ForegroundColor DarkGray

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$script:homes = New-Object System.Collections.ArrayList
$script:worlds = New-Object System.Collections.ArrayList
$realHome = $env:HORDE_HOME

if ((Get-HordeRelayKeyStore).state -cne "known") {
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Complete-HordeSuite -Success "no key store here: no machine identity can be made, so nothing was run" -PassCode 3
}

function New-TestHome {
    param([string]$Settings = '{"keepEnvelopes": 100, "backfillNotices": 50, "idleLookMs": 0}')
    $h = Join-Path $env:TEMP ("horde-relay-notices-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path (Join-Path $h "settings") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $h "progress") -Force | Out-Null
    [void]$script:homes.Add($h)
    [System.IO.File]::WriteAllText((Join-Path $h "settings\relay.json"), '{"schemaVersion": 1, "settings": {"horde": "work"}}', $utf8)
    [System.IO.File]::WriteAllText((Join-Path $h "settings\relay-notices.json"), ('{"schemaVersion": 1, "settings": ' + $Settings + '}'), $utf8)
    return $h
}
function Add-PhoneKey {
    param([string]$HordeHome, $Phone)
    $v = New-HordeTestPhoneVouch -Phone $Phone -Horde "work"
    $k = Add-HordeRelayPhoneKey -HordeHome $HordeHome -AgreePublic $Phone.agreePublic -By $Phone.keyId -AuthenticatorData $v.authenticatorData -ClientDataJson $v.clientDataJson -Signature $v.signature
    if ($k.state -cne "known") { throw ("no phone key: " + $k.reason) }
}
function New-World {
    param([string]$Settings = '{"keepEnvelopes": 100, "backfillNotices": 50, "idleLookMs": 0}')
    $h = New-TestHome -Settings $Settings
    $env:HORDE_HOME = $h
    $id = New-HordeRelayMachineIdentity -HordeHome $h -Provider "software"
    if ($id.state -cne "known") { throw ("no identity: " + $id.reason) }
    $phone = New-HordeTestPhone
    [void](Add-HordeTestPhonePairing -HordeHome $h -Phone $phone)
    Add-PhoneKey -HordeHome $h -Phone $phone
    $c = Connect-HordeRelay -Name "local" -Options @{ root = (Join-Path $h "relay-mailboxes") }
    if ($c.state -cne "known") { throw ("no relay: " + $c.reason) }
    $ctx = New-HordeRelayRunContext -HordeHome $h -Connection $c.value
    if ($ctx.state -cne "known") { throw ("no context: " + $ctx.reason) }
    $w = [pscustomobject]@{ home = $h; id = $id.value; phone = $phone; conn = $c.value; ctx = $ctx.value; agree = @(, ([byte[]]$id.value.agree.public)); seen = 0; log = (Join-Path $h "progress\changelog.jsonl") }
    [void]$script:worlds.Add($w)
    return $w
}
function Invoke-Tick { param($World) $env:HORDE_HOME = $World.home; return (Invoke-HordeNoticesChannelTick -Context $World.ctx) }
function Said { param($Tick) return (@($Tick.lines) -join " | ") }
function Get-NewMail {
    # What -Phone (the world's) opens of the notices items after the last look: { seq; body; to }.
    param($World, $Phone = $null, [switch]$All)
    if ($null -eq $Phone) { $Phone = $World.phone }
    $r = Receive-HordeRelayItems -Connection $World.conn -Mailbox "work/phone" -Since 0
    if ($r.state -cne "known") { return @() }
    $items = @($r.value.items | Where-Object { $All -or $_.seq -gt $World.seen })
    if (-not $All -and $items.Count -gt 0) { $World.seen = ($items | ForEach-Object { [long]$_.seq } | Measure-Object -Maximum).Maximum }
    $out = New-Object System.Collections.ArrayList
    foreach ($it in $items) {
        $hdr = (Read-HordeRelayEnvelope -Text $it.text).value.header
        if ($hdr.channel -cne "notices") { continue }
        $o = Open-HordeTestPhoneEnvelope -Phone $Phone -Text $it.text -MachineSignPublic $World.id.sign.public
        [void]$out.Add([pscustomobject]@{ seq = [long]$it.seq; ok = $o.ok; body = $o.body; to = @($hdr.to) })
    }
    return @($out.ToArray())
}
function Get-Texts { param($Mail) return (@($Mail | Where-Object { $_.ok } | ForEach-Object { @($_.body.notices) } | ForEach-Object { $_.text }) -join "|") }
function Send-ToMachine { param($World, [string]$Text) return (Send-HordeRelayItem -Connection $World.conn -Mailbox $World.ctx.mailbox -Text $Text -Key (Get-HordeRelayReplayKey -Header (Read-HordeRelayEnvelope -Text $Text).value.header)) }
function Invoke-Turn {
    # One inbound turn: the mailbox read and journaled, every unfinished record handed over. { text }.
    param($World)
    $env:HORDE_HOME = $World.home
    $in = Receive-HordeRelayInbox -Context $World.ctx -TimeoutMs 0
    $un = Invoke-HordeRelayUnfinished -Context $World.ctx
    $lines = New-Object System.Collections.ArrayList
    if ($in.state -ceq "known") { foreach ($l in @($in.value.refused)) { [void]$lines.Add("refused " + $l) }; foreach ($l in @($in.value.held)) { [void]$lines.Add("held " + $l) } }
    else { [void]$lines.Add("inbox " + $in.state + ": " + $in.reason) }
    foreach ($l in @(Get-HordeRelayRunLines -Report $un.value)) { [void]$lines.Add($l) }
    return [pscustomobject]@{ text = (@($lines.ToArray()) -join " | ") }
}
function New-FollowBody {
    param($World, [string]$Lane, [bool]$On, [string]$Machine = "", [string]$Extra = "")
    if ($Machine -ceq "") { $Machine = $World.id.sign.keyId }
    return ,($utf8.GetBytes('{"v":1,"setId":"' + [guid]::NewGuid().ToString("N") + '","machine":"' + $Machine + '","lane":"' + $Lane + '","on":' + $(if ($On) { "true" } else { "false" }) + $Extra + '}'))
}
function Get-Follows { param($World) $r = Read-HordeNoticeFollows -Store (Join-Path $World.home "notices"); if ($r.state -cne "known") { throw $r.reason }; return $r.value }
function Add-Entry {
    # One line appended to the world's progress log.
    param($World, [string]$Id, [string]$Title, [string]$Lane = "", [string]$Area = "", [string]$Kind = "merged")
    $t = '{"v":1,"id":"' + $Id + '","ts":"2026-10-14T03:00:00Z","kind":"' + $Kind + '"' + $(if ($Area -cne "") { ',"area":"' + $Area + '"' } else { "" }) + $(if ($Lane -cne "") { ',"lane":"' + $Lane + '"' } else { "" }) + ',"title":"' + $Title + '","text":"t"}' + "`n"
    $fs = New-Object System.IO.FileStream -ArgumentList $World.log, ([System.IO.FileMode]::Append), ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::ReadWrite)
    try { $b = $utf8.GetBytes($t); $fs.Write($b, 0, $b.Length) } finally { $fs.Dispose() }
}
function Get-Carried {
    # The switches one opened envelope carries, as text in the machine's own form ({"E":true}), or
    # "(none)" when it carries no follows member. Read through Get-HordeTestMember (test\lib\Suite.ps1):
    # under Set-StrictMode a missing member is an error, and an error here broke the suite with no failed
    # check (PR 259's after-merge net, the-switches-are-not-sent) instead of failing the check that names
    # the rule.
    param($Mail)
    $f = Get-HordeTestMember $Mail "body.follows"
    if ($null -eq $f) { return "(none)" }
    return ('{' + ((@($f.PSObject.Properties | Sort-Object { $_.Name } -CaseSensitive) | ForEach-Object { (ConvertTo-HordeNoticeJsonString $_.Name) + ':' + $(if ($_.Value -eq $true) { "true" } else { "false" }) }) -join ",") + '}')
}
function Test-CarriesHeld {
    # Every opened notices envelope in -Mail carries exactly the switches -World's machine holds now.
    param($World, $Mail)
    $held = Get-HordeNoticesChannelFollowsText -Follows (Get-Follows $World)
    return (@($Mail).Count -gt 0 -and @($Mail | Where-Object { -not $_.ok -or (Get-Carried $_) -cne $held }).Count -eq 0)
}
function Get-Notices { param($World) $r = Read-HordeNoticeLog -Store (Join-Path $World.home "notices"); if ($r.state -cne "known") { throw $r.reason }; return @($r.value) }
function Proven { param([string]$Label) return [pscustomobject]@{ ok = $true; reason = ""; sessionId = ("cccccccc-0000-4000-8000-" + ("" + $Label.Length).PadLeft(12, "0")); label = $Label } }

try {
    Write-Host ""
    Write-Host "--- 1. out: sealed to the trusted phone key, with the switches ---" -ForegroundColor Cyan
    $W = New-World
    $t = Invoke-Tick $W
    $mail = @(Get-NewMail $W)
    Check ($mail.Count -eq 0 -and -not $t.failed) ("NOTHING TO SAY, NOTHING SENT: with no notice and no switch, the phone's mailbox gets nothing (" + (Said $t) + ")")
    $null = Submit-HordeNotify -Sender (Proven "E") -Text ("the cards are merged " + [char]0x05D0) -HordeHome $W.home
    Check ((Test-HordeNoticesChannelGlance -Context $W.ctx) -eq $true) "THE GLANCE says yes for a notice written since the last look"
    $t = Invoke-Tick $W
    $mail = @(Get-NewMail $W)
    Check ($mail.Count -eq 1 -and $mail[0].ok -and (Get-Texts $mail) -ceq ("the cards are merged " + [char]0x05D0) -and @($mail[0].body.notices)[0].from -ceq "E" -and @($mail[0].body.notices)[0].n -eq 1 -and $mail[0].body.machine -ceq $W.id.sign.keyId -and $mail[0].body.horde -ceq "work") ("the notice goes at once, sealed: its words exact, its sender, its number, this machine (" + (Said $t) + ")")
    Check ($mail.Count -eq 1 -and @($mail[0].to).Count -eq 1 -and $mail[0].to[0] -ceq (Get-HordeRelayKeyId -Public $W.phone.agreePublic)) "sealed to the one trusted phone key, and to nothing else"
    Check ((Test-HordeNoticesChannelGlance -Context $W.ctx) -eq $false) "and after the Tick the Glance says no"
    $t = Invoke-Tick $W
    Check (@(Get-NewMail $W).Count -eq 0 -and @($t.lines).Count -eq 0) "nothing new: nothing sent, nothing said"
    $phone2 = New-HordeTestPhone
    [void](Add-HordeTestPhonePairing -HordeHome $W.home -Phone $phone2)
    Add-PhoneKey -HordeHome $W.home -Phone $phone2
    $t = Invoke-Tick $W
    $mail2 = @(Get-NewMail $W -Phone $phone2)
    Check ($mail2.Count -eq 1 -and $mail2[0].ok -and (Get-Texts $mail2) -like "the cards are merged*" -and @($mail2[0].to).Count -eq 1 -and $mail2[0].to[0] -ceq (Get-HordeRelayKeyId -Public $phone2.agreePublic)) ("a phone key trusted since is sent the newest notices, to it alone (" + (Said $t) + ")")
    $K = New-World -Settings '{"keepEnvelopes": 2, "backfillNotices": 50, "idleLookMs": 0}'
    foreach ($i in 1..4) { $null = Submit-HordeNotify -Sender (Proven "E") -Text ("n" + $i) -HordeHome $K.home; $null = Invoke-Tick $K }
    $held = @(Get-NewMail $K -All)
    Check ($held.Count -eq 2 -and (Get-Texts $held) -ceq "n3|n4") ("with keepEnvelopes 2 the phone's mailbox holds this machine's last two envelopes of notices (" + (Get-Texts $held) + ")")

    Write-Host ""
    Write-Host "--- 2. in: a switch signed by his passkey, for this machine, and nothing else ---" -ForegroundColor Cyan
    $W.seen = 0; $null = Get-NewMail $W
    $env1 = New-HordeTestPhoneEnvelope -Phone $W.phone -Kind "follow" -Channel "notices" -Body (New-FollowBody $W "E" $true) -To $W.agree
    [void](Send-ToMachine $W $env1.text)
    $turn = Invoke-Turn $W
    Check ((Get-Follows $W).ContainsKey("E") -and (Get-Follows $W)["E"].on -and (Get-Follows $W)["E"].key -ceq $env1.key -and $turn.text -like "*following Orc E is now on*") ("the founder's signed switch turns Orc E on, kept with the envelope that set it (" + $turn.text + ")")
    Check ((Test-HordeNoticesChannelGlance -Context $W.ctx) -eq $true) "the Glance sees the switch"
    $t = Invoke-Tick $W
    $mail = @(Get-NewMail $W)
    Check ($mail.Count -eq 1 -and $mail[0].ok -and (Get-Carried $mail[0]) -ceq '{"E":true}' -and @($mail[0].body.notices).Count -eq 0) ("THE PHONE SHOWS WHAT THE MACHINE HOLDS: the next envelope carries the switch on (" + (Said $t) + ")")
    [void](Send-HordeRelayItem -Connection $W.conn -Mailbox $W.ctx.mailbox -Text (New-HordeTestPhoneResigned -Phone $W.phone -Envelope $env1) -Key $env1.key)
    $turn = Invoke-Turn $W
    Check ((Get-Follows $W)["E"].on -and $turn.text -notlike "*now on*") ("the same envelope again is not a second setting (" + $turn.text + ")")
    $before = ConvertTo-HordeNoticeFollowsText -Follows (Get-Follows $W)
    $other = New-HordeTestPhoneEnvelope -Phone $W.phone -Kind "follow" -Channel "notices" -Body (New-FollowBody $W "B" $true -Machine ("a" * 32)) -To $W.agree
    [void](Send-ToMachine $W $other.text)
    $turn = Invoke-Turn $W
    Check ($turn.text -like "*for another machine*" -and (ConvertTo-HordeNoticeFollowsText -Follows (Get-Follows $W)) -ceq $before) ("a switch for another machine is refused (" + $turn.text + ")")
    $extra = New-HordeTestPhoneEnvelope -Phone $W.phone -Kind "follow" -Channel "notices" -Body (New-FollowBody $W "B" $true -Extra ',"all":true') -To $W.agree
    [void](Send-ToMachine $W $extra.text)
    $turn = Invoke-Turn $W
    Check ($turn.text -like "*members*" -and (ConvertTo-HordeNoticeFollowsText -Follows (Get-Follows $W)) -ceq $before) ("a switch with a member added is refused (" + $turn.text + ")")
    $nobody = New-HordeTestPhone
    $forged = New-HordeTestPhoneEnvelope -Phone $nobody -Kind "follow" -Channel "notices" -Body (New-FollowBody $W "B" $true) -To $W.agree -From $W.phone.keyId
    [void](Send-ToMachine $W $forged.text)
    $turn = Invoke-Turn $W
    Check ($turn.text -like "*does not verify*" -and (ConvertTo-HordeNoticeFollowsText -Follows (Get-Follows $W)) -ceq $before) ("A FORGED SWITCH - named for his passkey, signed by another - is refused (" + $turn.text + ")")
    $stranger = New-HordeTestPhoneEnvelope -Phone $nobody -Kind "follow" -Channel "notices" -Body (New-FollowBody $W "B" $true) -To $W.agree
    [void](Send-ToMachine $W $stranger.text)
    $turn = Invoke-Turn $W
    Check ($turn.text -like ("*refused*" + $nobody.keyId + "*") -and (ConvertTo-HordeNoticeFollowsText -Follows (Get-Follows $W)) -ceq $before) ("a switch from a passkey this machine does not trust is refused (" + $turn.text + ")")
    $peerHome = New-TestHome
    [void](New-HordeRelayMachineIdentity -HordeHome $peerHome -Provider "software")
    $card = (Export-HordeRelayMachineCard -HordeHome $peerHome -Label "Second machine").value
    $added = Add-HordeRelayPeerMachine -HordeHome $W.home -Card $card
    $cs = New-HordeTestPhoneAssertion -Phone $W.phone -Challenge (Get-HordeRelayCardChallenge -Card $card)
    $vouched = Confirm-HordeRelayPeerMachine -HordeHome $W.home -KeyId $added.value.record.keyId -By $W.phone.keyId -AuthenticatorData $cs.authenticatorData -ClientDataJson $cs.clientDataJson -Signature $cs.signature
    Check ($vouched.state -ceq "known" -and $vouched.value.record.state -ceq "trusted") "CONTROL: a peer machine of the horde is trusted"
    $peerId = Get-HordeRelayMachineIdentity -HordeHome $peerHome -Open
    $peerSwitch = New-HordeRelayEnvelope -Kind "follow" -Channel "notices" -Seq 1 -Body (New-FollowBody $W "B" $true) -Recipients $W.agree -Signer $peerId.value.sign.key
    $peerId.value.sign.key.Dispose(); $peerId.value.agree.key.Dispose()
    [void](Send-ToMachine $W $peerSwitch)
    $turn = Invoke-Turn $W
    Check ($turn.text -like "*not one the channel notices takes (founder)*" -and (ConvertTo-HordeNoticeFollowsText -Follows (Get-Follows $W)) -ceq $before) ("a TRUSTED PEER MACHINE's switch is refused: only the founder's passkeys set switches (" + $turn.text + ")")
    $wrongKind = New-HordeTestPhoneEnvelope -Phone $W.phone -Kind "notices" -Channel "notices" -Body ($utf8.GetBytes('{"v":1}')) -To $W.agree
    [void](Send-ToMachine $W $wrongKind.text)
    $turn = Invoke-Turn $W
    Check ($turn.text -like "*the channel notices takes follow, not notices*") ("nothing but a switch comes in on the channel (" + $turn.text + ")")

    Write-Host ""
    Write-Host "--- 3. following the log: new entries of a followed lane, never old ones ---" -ForegroundColor Cyan
    $P = New-World
    [System.IO.File]::WriteAllText((Join-Path $P.home "progress\area-lanes.json"), '{"v":1,"areas":{"Horde phone":"F,E"}}', $utf8)
    Add-Entry $P "old-1" "an old entry of E" -Lane "E"
    Add-Entry $P "old-2" "another old one" -Area "Horde phone"
    $null = Set-HordeNoticeFollow -Lane "E" -On $true -At 1000 -Key "k/notices/1/a" -HordeHome $P.home
    $t = Invoke-Tick $P
    Check (@(Get-Notices $P).Count -eq 0) ("OLD ENTRIES NEVER BECOME NOTICES: what the log held before the first look is passed over, though Orc E is followed (" + (Said $t) + ")")
    Add-Entry $P "new-1" "the switch works" -Lane "E"
    Add-Entry $P "new-2" "voice fixed" -Lane "B"
    $t = Invoke-Tick $P
    $all = @(Get-Notices $P)
    Check ($all.Count -eq 1 -and $all[0].entry -ceq "new-1" -and $all[0].from -ceq "Orc E" -and $all[0].text -ceq "Merged: the switch works") ("a followed lane's new entry is one notice; an unfollowed lane's none (" + (Said $t) + ")")
    $mail = @(Get-NewMail $P)
    Check ((Get-Texts $mail) -ceq "Merged: the switch works" -and @($mail[-1].body.notices)[0].lane -ceq "E" -and @($mail[-1].body.notices)[0].entry -ceq "new-1") "and it is on the phone in the same Tick, naming its lane and its entry, so a tap opens that stream"
    Check (Test-CarriesHeld $P $mail) ("EVERY NOTICES ENVELOPE CARRIES THE SWITCHES THE MACHINE HOLDS, a notice's envelope too (" + (@($mail | ForEach-Object { Get-Carried $_ }) -join " ") + ")")
    Add-Entry $P "new-3" "a phone fix for two lanes" -Area "horde PHONE"
    $t = Invoke-Tick $P
    $all = @(Get-Notices $P)
    Check ($all.Count -eq 2 -and $all[-1].entry -ceq "new-3" -and $all[-1].from -ceq "Orc E") ("AN ENTRY WHOSE AREA MAPS TO TWO LANES (F, E) is one notice when one of them is followed (" + (Said $t) + ")")
    $null = Set-HordeNoticeFollow -Lane "F" -On $true -At 1000 -Key "k/notices/2/a" -HordeHome $P.home
    Add-Entry $P "new-4" "both followed now" -Area "Horde phone"
    $null = Invoke-Tick $P
    Check (@(Get-Notices $P).Count -eq 3 -and @(Get-Notices $P)[-1].from -ceq "Orc F") "with both followed it is still one notice"
    $null = Invoke-Tick $P
    Check (@(Get-Notices $P).Count -eq 3) "a look with nothing new makes no notice"
    # REPLACED BY A SHORTER FILE: a new file with one entry of E, shorter than where the channel stood, so
    # this is the "cut short" path. Followed again from its new end; the entry in it is old.
    [System.IO.File]::WriteAllText($P.log, '{"v":1,"id":"r-1","ts":"2026-10-14T03:00:00Z","kind":"merged","lane":"E","title":"in the new file already","text":"t"}' + "`n", $utf8)
    $t = Invoke-Tick $P
    Check (@(Get-Notices $P).Count -eq 3 -and (Said $t) -like "*followed again from its present end*" -and (Said $t) -like "*cut short*") ("A LOG REPLACED BY A SHORTER ONE is followed again from its new end, said, and what it already held is no notice (" + (Said $t) + ")")
    Add-Entry $P "r-2" "after the replace" -Lane "E"
    $null = Invoke-Tick $P
    Check (@(Get-Notices $P).Count -eq 4 -and @(Get-Notices $P)[-1].entry -ceq "r-2") "and an entry written after that is a notice"
    $state = [System.IO.File]::ReadAllText((Join-Path $P.home "relay\notices\state.json"))
    Check (-not $state.Contains("after the replace") -and $state.Contains('"pending":[]')) "the channel's state holds its places and nothing of the words, and nothing waiting"
    $null = @(Get-NewMail $P)
    Close-HordeRelayRunContext -Context $P.ctx
    $P.ctx = (New-HordeRelayRunContext -HordeHome $P.home -Connection $P.conn).value
    $null = Invoke-Tick $P
    Check (@(Get-Notices $P).Count -eq 4 -and @(Get-NewMail $P).Count -eq 0) "a new run on the same home sends nothing again and makes no notice again"

    # REPLACED BY A LONGER FILE (PR 259's after-merge mutation net: a-replaced-log-is-read-from-its-start
    # survived, because the replace above is shorter than where the channel stood and so goes down the
    # "cut short" path). Here the new file already holds more bytes than the old place, so only the marks
    # (the hash of its first and last bytes before that place) can tell it was replaced. Read on from the
    # old place, every whole entry past it would become a notice and flood the founder.
    $R = New-World
    Add-Entry $R "o-1" "an old entry of E" -Lane "E"
    Add-Entry $R "o-2" "another old entry of E" -Lane "E"
    $null = Set-HordeNoticeFollow -Lane "E" -On $true -At 1000 -Key "k/notices/1/a" -HordeHome $R.home
    $null = Invoke-Tick $R
    $stood = [long](ConvertFrom-Json ([System.IO.File]::ReadAllText((Join-Path $R.home "relay\notices\state.json")))).offset
    $newFile = $R.log + ".new"
    $sb = New-Object System.Text.StringBuilder
    foreach ($i in 1..6) { [void]$sb.Append('{"v":1,"id":"n-' + $i + '","ts":"2026-10-14T03:00:00Z","kind":"merged","lane":"E","title":"in the new file already, number ' + $i + '","text":"t"}' + "`n") }
    [System.IO.File]::WriteAllText($newFile, $sb.ToString(), $utf8)
    # A real replace: a new file renamed over the old name.
    [System.IO.File]::Delete($R.log); [System.IO.File]::Move($newFile, $R.log)
    $len = (New-Object System.IO.FileInfo -ArgumentList $R.log).Length
    Check ($stood -gt 0 -and $len -gt (2 * $stood)) ("CONTROL: the new file is longer than where the channel stood, so this is not the cut-short path (" + $stood + " then " + $len + " bytes)")
    $t = Invoke-Tick $R
    Check (@(Get-Notices $R).Count -eq 0 -and (Said $t) -like "*followed again from its present end*" -and (Said $t) -like "*replaced or rewritten*") ("A LOG REPLACED BY A LONGER ONE is followed again from its new end, said, and none of the entries it already held is a notice (" + (Said $t) + ")")
    Add-Entry $R "after" "written after the replace" -Lane "E"
    $null = Invoke-Tick $R
    $rn = @(Get-Notices $R)
    Check ($rn.Count -eq 1 -and $rn[0].entry -ceq "after") ("and one entry appended after it is exactly one notice, for that entry (" + (@($rn | ForEach-Object { $_.entry }) -join ",") + ")")

    Write-Host ""
    Write-Host "--- 4. idle: nothing changed, nothing read; anything to send is a full look ---" -ForegroundColor Cyan
    $I = New-World -Settings '{"keepEnvelopes": 100, "backfillNotices": 50, "idleLookMs": 600000}'
    $null = Submit-HordeNotify -Sender (Proven "E") -Text "first" -HordeHome $I.home
    $null = Invoke-Tick $I
    $null = @(Get-NewMail $I)
    $phone3 = New-HordeTestPhone
    [void](Add-HordeTestPhonePairing -HordeHome $I.home -Phone $phone3)
    Add-PhoneKey -HordeHome $I.home -Phone $phone3
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $t = Invoke-Tick $I
    $sw.Stop()
    Check (@(Get-NewMail $I -Phone $phone3).Count -eq 0 -and @($t.lines).Count -eq 0) ("IDLE: with nothing changed, a Tick inside idleLookMs reads nothing and sends nothing - a phone key trusted since waits for the next full look (" + $sw.ElapsedMilliseconds + " ms)")
    $null = Submit-HordeNotify -Sender (Proven "E") -Text "second" -HordeHome $I.home
    $t = Invoke-Tick $I
    $mail = @(Get-NewMail $I -Phone $phone3 -All)
    Check ((Get-Texts $mail) -ceq "first|second" -and (Get-Texts @(Get-NewMail $I)) -ceq "second") ("a new notice is a full look at once: sent to the old key, and the key trusted since gets its backfill (" + (Said $t) + ")")
    Add-Entry $I "i-1" "an entry" -Lane "E"
    $null = Set-HordeNoticeFollow -Lane "E" -On $true -At 1000 -Key "k/notices/1/a" -HordeHome $I.home
    $null = Invoke-Tick $I
    Add-Entry $I "i-2" "followed while idle" -Lane "E"
    $null = Invoke-Tick $I
    Check (@(Get-Notices $I).Count -eq 3 -and @(Get-Notices $I)[-1].entry -ceq "i-2") "a new line in the followed log is a full look at once, and its followed entry a notice"
} finally {
    $env:HORDE_HOME = $realHome
    Exit-HordeTestEmptyFleet -Pin $fleetPin
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
    foreach ($h in $script:homes) { if ((Split-Path -Leaf $h) -match '^horde-relay-notices-[0-9a-f]{32}$') { Remove-Item -LiteralPath $h -Recurse -Force -ErrorAction SilentlyContinue } }
    Check (@($script:homes | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 0 -and -not (Test-Path -LiteralPath $fleetPin.path)) "every folder the suite made is gone"
}

Complete-HordeSuite -Success "the founder's notices reach his phone sealed with the switches the machine holds; a switch reaches the machine only signed by his passkey for this machine; a followed lane's new entries, never its old ones, become notices"
