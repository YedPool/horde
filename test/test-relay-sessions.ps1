# DOES THE PC TAKE A SESSION-SIGNED ANSWER EXACTLY WHILE THE SESSION IS ALIVE BY ITS OWN CLOCK AND
# RECORDS - AND REFUSE IT, BY NAME, EVERY WAY IT IS NOT?
#
# The unlocked session (relay/Session.ps1, channels/Sessions.ps1, design note "Unlocked session"): one
# passkey prompt at unlock vouches for a session key, which signs the answers after it. Every rule is a
# must-refuse beside its must-accept twin, through the REAL channel code - channels/Port.ps1's
# Receive-HordeRelayInbox and Invoke-HordeRelayUnfinished, the journal, the trust store, the decisions
# list - over relays/local, with the PC's clock handed in (-Now) so an hour or eight pass in a moment:
#   accepted in its window                         refused after the idle limit (the PC's own clock)
#   accepted before the 8-hour cap                 refused after it, and a vouch over 8 hours never read
#   accepted from a trusted device                 refused once the device is revoked
#   accepted before end-all                        refused after it (and the CLI command ends them)
#   a phone's own vouch                            another device's vouch, a forged vouch, a forged
#                                                  session signature
#   the envelope once                              the same envelope again (a replay)
#   an ordinary question by session                a needsPasskey question by session (needs-passkey),
#                                                  and the same answer then by passkey
#   a per-passkey envelope, before and after sessions exist, and after end-all
#   the vouch carried                              a vouchId the PC does not hold (session-unknown)
#   a new vouch above the last                     one at or below it (session-stale)
# and what the phone is told: the session member of its receipt (live, idle, ended), and its
# needsPasskey list.
#
# EVERY HORDE HOME IS A FOLDER OF THE SUITE'S OWN under %TEMP%, never the real one, and never one that
# answers the founder's phone. Every key is the software provider's, removed in the finally block.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\FleetPin.ps1")
$fleetPin = Enter-HordeTestEmptyFleet
. (Join-Path $root "core\ModuleSettings.ps1")
. (Join-Path $root "core\JsonText.ps1")
. (Join-Path $root "channels\Port.ps1")
foreach ($f in @(Get-HordeRelayFiles)) { . $f }
foreach ($f in @(Get-HordeRelayChannelFiles)) { . $f }
. (Join-Path $root "cli\RelayRun.ps1")
. (Join-Path $root "cli\RelaySessions.ps1")
. (Join-Path $root "test\lib\RelayPhone.ps1")
. (Join-Path $root "test\lib\Cli.ps1")
Set-StrictMode -Version Latest
Write-Host ("  runtime: PowerShell " + $PSVersionTable.PSVersion + " (" + $PSVersionTable.PSEdition + ")") -ForegroundColor DarkGray

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$script:homes = New-Object System.Collections.ArrayList
$script:worlds = New-Object System.Collections.ArrayList
$realHome = $env:HORDE_HOME

if ((Get-HordeRelayKeyStore).state -cne "known") {
    Exit-HordeTestEmptyFleet -Pin $fleetPin
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Complete-HordeSuite -Success "no key store here: no machine identity can be made, so nothing was run" -PassCode 3
}

function New-Id { return [guid]::NewGuid().ToString("N") }
function New-TestHome {
    $h = Join-Path $env:TEMP ("horde-relay-sessions-" + (New-Id))
    New-Item -ItemType Directory -Path (Join-Path $h "settings") -Force | Out-Null
    [void]$script:homes.Add($h)
    [System.IO.File]::WriteAllText((Join-Path $h "settings\relay.json"), '{"schemaVersion": 1, "settings": {"horde": "work"}}', $utf8)
    return $h
}
function Get-TestKeyNames {
    param([string]$HordeHome)
    $out = New-Object System.Collections.ArrayList
    $dir = Join-Path $HordeHome "relay\identity"
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter "machine-*.json")) {
        $m = [regex]::Match([System.IO.File]::ReadAllText($f.FullName), '"scope":"([a-z]+)","signName":"([a-z0-9-]+)".*"agreeName":"([a-z0-9-]+)"')
        if ($m.Success) { [void]$out.Add(@{ n = $m.Groups[2].Value; s = $m.Groups[1].Value }); [void]$out.Add(@{ n = $m.Groups[3].Value; s = $m.Groups[1].Value }) }
    }
    return @($out)
}
function Add-PhoneTo {
    # A phone paired, confirmed and its identity key vouched for, in -World's home.
    param($World)
    $p = New-HordeTestPhone
    [void](Add-HordeTestPhonePairing -HordeHome $World.home -Phone $p)
    $v = New-HordeTestPhoneVouch -Phone $p -Horde "work"
    $k = Add-HordeRelayPhoneKey -HordeHome $World.home -AgreePublic $p.agreePublic -By $p.keyId -AuthenticatorData $v.authenticatorData -ClientDataJson $v.clientDataJson -Signature $v.signature
    if ($k.state -cne "known") { throw ("no phone key: " + $k.reason) }
    return $p
}
function New-World {
    # A machine with one ordinary question and one flagged needsPasskey, a phone, a local relay, and
    # the first look sent (so an answer has a snapshot to name).
    $h = New-TestHome
    $env:HORDE_HOME = $h
    $id = New-HordeRelayMachineIdentity -HordeHome $h -Provider "software"
    if ($id.state -cne "known") { throw ("no identity: " + $id.reason) }
    $c = Connect-HordeRelay -Name "local" -Options @{ root = (Join-Path $h "relay-mailboxes") }
    if ($c.state -cne "known") { throw ("no relay: " + $c.reason) }
    $ctx = New-HordeRelayRunContext -HordeHome $h -Connection $c.value
    if ($ctx.state -cne "known") { throw ("no context: " + $ctx.reason) }
    $store = Join-Path $h "store\decisions"
    $w = [pscustomobject]@{ home = $h; id = $id.value; phone = $null; conn = $c.value; ctx = $ctx.value; store = $store; agree = @(, ([byte[]]$id.value.agree.public)); machine = $id.value.sign.keyId }
    [void]$script:worlds.Add($w)
    $w.phone = Add-PhoneTo -World $w
    $q1 = Invoke-HordeDecision -Operation "add" -Root $store -Request @{ id = (New-Id); actor = "warchief"; question = @{ title = "Should the closing sound play when the assistant closes?"; kind = "yes-no"; whatItIs = "The app has no closing sound today."; group = "voice"; askedBy = "orc-f" } }
    $q2 = Invoke-HordeDecision -Operation "add" -Root $store -Request @{ id = (New-Id); actor = "warchief"; needsPasskey = $true; question = @{ title = "Should the new relay worker be deployed to production now?"; kind = "yes-no"; whatItIs = "A production deploy of the hosted relay."; group = "relay"; askedBy = "orc-f" } }
    if ($q1.state -cne "known" -or $q1.value.outcome -cne "done" -or $q2.state -cne "known" -or $q2.value.outcome -cne "done") { throw ("the questions were not added: " + $q1.reason + " " + $q2.reason) }
    $null = Invoke-HordeRelayChannelTicks -Context $w.ctx
    return $w
}
function Get-SentKey {
    param($World)
    $dir = Join-Path $World.home ("relay\journal\out\s-" + $World.machine + "\c-decisions")
    $newest = @(Get-ChildItem -LiteralPath $dir -Filter "*.rec" | Sort-Object Name | Select-Object -Last 1)
    return [regex]::Match([System.IO.File]::ReadAllText($newest[0].FullName), '"key":"([^"]+)"').Groups[1].Value
}
function Send-ToMachine {
    param($World, [string]$Text, [string]$Key = "-")
    if ($Key -ceq "-") {
        # An envelope the reader refuses (a vouch over 8 hours) has no replay key: any key carries it.
        $read = Read-HordeRelayEnvelope -Text $Text
        $Key = $(if ($read.ok) { Get-HordeRelayReplayKey -Header $read.value.header } else { "unreadable-" + (New-Id) })
    }
    return (Send-HordeRelayItem -Connection $World.conn -Mailbox $World.ctx.mailbox -Text $Text -Key $Key)
}
function Invoke-Turn {
    # One inbound turn at the PC's clock -At: the mailbox read and journaled, every unfinished record
    # handed over. { text } - everything said, for a check to search.
    param($World, [datetime]$At)
    $env:HORDE_HOME = $World.home
    $in = Receive-HordeRelayInbox -Context $World.ctx -TimeoutMs 0 -Now $At
    $un = Invoke-HordeRelayUnfinished -Context $World.ctx -Now $At
    $lines = New-Object System.Collections.ArrayList
    if ($in.state -ceq "known") { foreach ($l in @($in.value.refused)) { [void]$lines.Add("refused " + $l) }; foreach ($l in @($in.value.held)) { [void]$lines.Add("held " + $l) } }
    else { [void]$lines.Add("inbox " + $in.state + ": " + $in.reason) }
    foreach ($l in @(Get-HordeRelayRunLines -Report $un.value)) { [void]$lines.Add($l) }
    return [pscustomobject]@{ text = (@($lines.ToArray()) -join " | ") }
}
function Get-Said {
    param($World)
    if (-not (Test-Path -LiteralPath $World.store)) { return @() }
    return @(Get-ChildItem -LiteralPath $World.store -Filter "*.json" | Sort-Object Name | ForEach-Object { ConvertFrom-HordeJson -Text ([System.IO.File]::ReadAllText($_.FullName, $utf8)) } | Where-Object { "$(Get-HordeTestMember $_ 'kind')" -ceq "message-said" })
}
function Test-Said { param($World, [string]$Text) return (@(Get-Said $World | Where-Object { "$(Get-HordeTestMember $_ 'data.text')" -ceq $Text }).Count -eq 1) }
function New-AnswerBody {
    param($World, [int]$Number, [string]$Text, [string]$AnswerId = "")
    return (New-HordeTestPhoneAnswerBody -AnswerId $AnswerId -Number $Number -Text $Text -Machine $World.machine -Snapshot (Get-SentKey $World))
}
function Send-SessionAnswer {
    # A session-signed answer at the phone's clock -At, put and taken in one turn at the PC's clock -Pc
    # (the same unless given). { turn; text; envelope }.
    param($World, $Session, [int]$Number = 1, [string]$Text, [datetime]$At, $Pc = $null, [switch]$WithVouch, $Phone = $null, [string]$AnswerId = "", $SignAs = $null)
    if ($null -eq $Phone) { $Phone = $World.phone }
    $e = New-HordeTestPhoneSessionEnvelope -Phone $Phone -Session $Session -Kind "answer" -Channel "decisions" -Body (New-AnswerBody $World $Number $Text $AnswerId) -To $World.agree -WithVouch:$WithVouch -Now $At -SignAs $SignAs
    [void](Send-ToMachine $World $e.text)
    $pcAt = $(if ($null -eq $Pc) { $At } else { $Pc })
    return [pscustomobject]@{ turn = (Invoke-Turn $World $pcAt); envelope = $e }
}
function Send-Opening {
    # The opening envelope of a session (channel trust, kind session), carrying the vouch.
    param($World, $Session, [datetime]$At, $Phone = $null)
    if ($null -eq $Phone) { $Phone = $World.phone }
    $body = $utf8.GetBytes('{"v":1,"vouchId":"' + $Session.vouchId + '"}')
    $e = New-HordeTestPhoneSessionEnvelope -Phone $Phone -Session $Session -Kind "session" -Channel "trust" -Body $body -To $World.agree -WithVouch -Now $At
    [void](Send-ToMachine $World $e.text)
    return (Invoke-Turn $World $At)
}
function Get-Receipt {
    # The receipt for -From in the decisions receipts as the PC would send them now, parsed.
    param($World, [string]$From)
    $r = Get-HordeDecisionsChannelReceipts -Context $World.ctx -Prefer @($From)
    return (@(ConvertFrom-HordeJson -Text $r.text) | ForEach-Object { $_ } | Where-Object { "$(Get-HordeTestMember $_ 'from')" -ceq $From }) | Select-Object -First 1
}

try {
    $T0 = [datetime]::UtcNow.AddSeconds(-2)
    $W = New-World
    $sid = 0

    Write-Host ""
    Write-Host "--- accepted in its window; the opening and the vouch ---" -ForegroundColor Cyan
    $s1 = New-HordeTestPhoneSession -Phone $W.phone -Machine $W.machine -NotBefore $T0 -Seq 1
    # Must-refuse first: a bare envelope under a vouch the PC does not hold yet.
    $r = Send-SessionAnswer -World $W -Session $s1 -Text "Bare, before the vouch." -At $T0.AddSeconds(10)
    Check ($r.turn.text.Contains("session-unknown") -and -not (Test-Said $W "Bare, before the vouch.")) ("a session answer under a vouch the PC does not hold is refused as session-unknown (" + $r.turn.text + ")")
    $o = Send-Opening -World $W -Session $s1 -At $T0.AddSeconds(20)
    Check ($o.text.Contains("is open") -and -not $o.text.Contains("refused")) ("the opening, carrying the vouch, is taken and the session is open (" + $o.text + ")")
    Check (Test-Path -LiteralPath (Join-Path $W.home ("relay\sessions\vouches\" + $s1.vouchId + ".json"))) "the vouch is journaled as a write-once record on this PC"
    $r = Send-SessionAnswer -World $W -Session $s1 -Text "Yes, play it." -At $T0.AddMinutes(1)
    Check ((Test-Said $W "Yes, play it.") -and $r.turn.text.Contains("done")) ("a session-signed answer in its window is applied, with no passkey prompt (" + $r.turn.text + ")")
    $said = @(Get-Said $W | Where-Object { "$(Get-HordeTestMember $_ 'data.text')" -ceq "Yes, play it." }) | Select-Object -First 1
    Check ("$(Get-HordeTestMember $said 'data.signedBy')" -ceq $W.phone.keyId -and "$(Get-HordeTestMember $said 'data.route')" -ceq "phone") "the record names the passkey that vouched for the session as its signer, route phone"

    Write-Host ""
    Write-Host "--- the vouch rides on the first answer; the opening is not needed first ---" -ForegroundColor Cyan
    $W2 = New-World
    $s2 = New-HordeTestPhoneSession -Phone $W2.phone -Machine $W2.machine -NotBefore $T0 -Seq 1
    # The bare opening is PUT FIRST, the answer carrying the vouch second, in one batch: the vouch is taken first.
    $a1 = New-HordeTestPhoneSessionEnvelope -Phone $W2.phone -Session $s2 -Kind "answer" -Channel "decisions" -Body (New-AnswerBody $W2 1 "Carried along.") -To $W2.agree -WithVouch -Now $T0.AddMinutes(1)
    $o2 = New-HordeTestPhoneSessionEnvelope -Phone $W2.phone -Session $s2 -Kind "session" -Channel "trust" -Body ($utf8.GetBytes('{"v":1,"vouchId":"' + $s2.vouchId + '"}')) -To $W2.agree -Now $T0.AddMinutes(1)
    [void](Send-ToMachine $W2 $o2.text); [void](Send-ToMachine $W2 $a1.text)
    $t = Invoke-Turn $W2 $T0.AddMinutes(1)
    Check ((Test-Said $W2 "Carried along.") -and $t.text.Contains("is open") -and -not $t.text.Contains("session-unknown")) ("a vouch in the batch is taken before any envelope under it, whatever the order (" + $t.text + ")")

    Write-Host ""
    Write-Host "--- idle: the PC's own clock ---" -ForegroundColor Cyan
    # Last use at T0+1m. 59 minutes later: taken; 50 minutes after that (110 after the vouch was
    # recorded): taken, so each use restarts the clock. Then 61 minutes after the last use: refused.
    $r = Send-SessionAnswer -World $W -Session $s1 -Text "Within the hour." -At $T0.AddMinutes(60)
    Check ((Test-Said $W "Within the hour.") -and -not $r.turn.text.Contains("session-idle")) ("59 minutes after the last use the session answers (" + $r.turn.text + ")")
    $r = Send-SessionAnswer -World $W -Session $s1 -Text "Again within the hour." -At $T0.AddMinutes(110)
    Check ((Test-Said $W "Again within the hour.") -and -not $r.turn.text.Contains("session-idle")) ("50 minutes after the last use, 110 after unlock, it answers: each use restarts the PC's idle clock (" + $r.turn.text + ")")
    $r = Send-SessionAnswer -World $W -Session $s1 -Text "Past the hour." -At $T0.AddMinutes(171)
    Check ($r.turn.text.Contains("session-idle") -and -not (Test-Said $W "Past the hour.")) ("61 minutes after the last use it is refused as session-idle (" + $r.turn.text + ")")
    $st = Get-HordeRelaySessionStatus -HordeHome $W.home -From $W.phone.keyId -NowMs (ConvertTo-HordeRelayRecordMs -Time $T0.AddMinutes(171))
    $mine = @(@($st.vouches) | Where-Object { $_.vouchId -ceq $s1.vouchId }) | Select-Object -First 1
    Check ($null -ne $mine -and $mine.state -ceq "session-idle" -and [long]$st.idleMs -eq 3600000) "what the phone is told says session-idle, with the PC's idle limit of 60 minutes"
    # A refused envelope keeps no session alive: still idle a minute later.
    $r = Send-SessionAnswer -World $W -Session $s1 -Text "Still past it." -At $T0.AddMinutes(172)
    Check ($r.turn.text.Contains("session-idle")) "a refused envelope does not wake the session (the idle clock moves only for one the journal took)"

    Write-Host ""
    Write-Host "--- a new vouch: above the last seq, not at or below it ---" -ForegroundColor Cyan
    $stale = New-HordeTestPhoneSession -Phone $W.phone -Machine $W.machine -NotBefore $T0.AddMinutes(123) -Seq 1
    $r = Send-SessionAnswer -World $W -Session $stale -Text "Stale vouch." -At $T0.AddMinutes(123) -WithVouch
    Check ($r.turn.text.Contains("session-stale") -and -not (Test-Said $W "Stale vouch.")) ("a new vouch whose seq is not above the last is refused as session-stale (" + $r.turn.text + ")")
    $s3 = New-HordeTestPhoneSession -Phone $W.phone -Machine $W.machine -NotBefore $T0.AddMinutes(123) -Seq 2
    $r = Send-SessionAnswer -World $W -Session $s3 -Text "Unlocked again." -At $T0.AddMinutes(124) -WithVouch
    Check ((Test-Said $W "Unlocked again.") -and -not $r.turn.text.Contains("session-")) ("a new vouch above it - the founder unlocked again - is taken (" + $r.turn.text + ")")

    Write-Host ""
    Write-Host "--- the 8-hour cap ---" -ForegroundColor Cyan
    # The idle limit set to its most (480 minutes), so the cap is what is tested.
    [System.IO.File]::WriteAllText((Join-Path $W.home "settings\relay-sessions.json"), '{"schemaVersion": 1, "settings": {"idleMinutes": 480}}', $utf8)
    $r = Send-SessionAnswer -World $W -Session $s3 -Text "Just inside the cap." -At $T0.AddMinutes(123 + 479)
    Check ((Test-Said $W "Just inside the cap.") -and -not $r.turn.text.Contains("session-")) ("a minute before the cap the session answers (" + $r.turn.text + ")")
    $r = Send-SessionAnswer -World $W -Session $s3 -Text "Past the cap." -At $T0.AddMinutes(123 + 482)
    Check ($r.turn.text.Contains("session-expired") -and -not (Test-Said $W "Past the cap.")) ("past notAfter it is refused as session-expired, whatever the idle (" + $r.turn.text + ")")
    $r = Send-SessionAnswer -World $W -Session $s3 -Text "Phone clock says inside." -At $T0.AddMinutes(123 + 479) -Pc $T0.AddMinutes(123 + 482)
    Check ($r.turn.text.Contains("session-expired") -and -not (Test-Said $W "Phone clock says inside.")) ("the PC's own clock past the cap refuses it even when the phone's says inside (" + $r.turn.text + ")")
    # A vouch over 8 hours cannot even be read: forged by hand, signed by the real passkey.
    $k = New-HordeRelayP256Key -Use "ecdsa"; $pub = ConvertTo-HordeRelayP256Public -Key $k
    $nb = ConvertTo-HordeRelayRecordMs -Time $T0.AddMinutes(700)
    $long = (ConvertTo-HordeRelaySessionVouchText -SessionPublicKey $pub -DeviceKeyId $W.phone.keyId -PhoneKeyId (Get-HordeRelayKeyId -Public $W.phone.agreePublic) -Horde "work" -Machine $W.machine -NotBefore $nb -NotAfter ($nb + 28800000) -Seq 9).Replace('"notAfter":' + ($nb + 28800000), '"notAfter":' + ($nb + 28800001))
    $la = New-HordeTestPhoneAssertion -Phone $W.phone -Challenge (Get-HordeRelaySessionVouchChallenge -Text $long)
    $longS = [pscustomobject]@{ key = $k; public = $pub; vouchId = (Get-HordeRelayKeyId -Public $pub); text = $long; assertion = $la }
    $r = Send-SessionAnswer -World $W -Session $longS -Text "Nine hours." -At $T0.AddMinutes(701) -WithVouch
    Check ($r.turn.text.Contains("longer than 8 hours") -and -not (Test-Said $W "Nine hours.")) ("a vouch whose window is over 8 hours is refused, even signed by the founder's passkey (" + $r.turn.text + ")")
    Remove-Item -LiteralPath (Join-Path $W.home "settings\relay-sessions.json") -Force

    Write-Host ""
    Write-Host "--- another device's vouch, a forged vouch, a forged session signature ---" -ForegroundColor Cyan
    $B = Add-PhoneTo -World $W2
    $sB = New-HordeTestPhoneSession -Phone $B -Machine $W2.machine -NotBefore $T0 -Seq 1
    $r = Send-SessionAnswer -World $W2 -Session $sB -Phone $B -Text "Phone B, its own vouch." -At $T0.AddMinutes(2) -WithVouch
    Check ((Test-Said $W2 "Phone B, its own vouch.") -and -not $r.turn.text.Contains("session-")) ("CONTROL TWIN: a second trusted phone's own session answers (" + $r.turn.text + ")")
    # Phone A sends under B's vouch (carried), signing with B's session key: the vouch is B's, not A's.
    $r = Send-SessionAnswer -World $W2 -Session $sB -Phone $W2.phone -Text "A under B's vouch." -At $T0.AddMinutes(3) -WithVouch
    Check ($r.turn.text.Contains("session-refused") -and -not (Test-Said $W2 "A under B's vouch.")) ("an envelope from one device under another device's vouch is refused as session-refused (" + $r.turn.text + ")")
    $r = Send-SessionAnswer -World $W2 -Session $sB -Phone $W2.phone -Text "A under B's vouch, bare." -At $T0.AddMinutes(3)
    Check ($r.turn.text.Contains("session-") -and -not (Test-Said $W2 "A under B's vouch, bare.")) ("and under its vouchId alone it is refused too (" + $r.turn.text + ")")
    $thief = New-HordeTestPhone
    $forged = New-HordeTestPhoneSession -Phone $W2.phone -Machine $W2.machine -NotBefore $T0 -Seq 5 -Signer $thief
    $r = Send-SessionAnswer -World $W2 -Session $forged -Text "Forged vouch." -At $T0.AddMinutes(4) -WithVouch
    Check ($r.turn.text.Contains("session-refused") -and $r.turn.text.Contains("assertion") -and -not (Test-Said $W2 "Forged vouch.")) ("a vouch signed by a passkey that is not the sender's is refused as session-refused (" + $r.turn.text + ")")
    $other = New-HordeTestPhoneSession -Phone $W2.phone -Machine $W2.machine -NotBefore $T0 -Seq 6
    $r = Send-SessionAnswer -World $W2 -Session $s2 -SignAs $other -Text "Forged session signature." -At $T0.AddMinutes(4)
    Check ($r.turn.text.Contains("session-refused") -and $r.turn.text.Contains("does not verify") -and -not (Test-Said $W2 "Forged session signature.")) ("a session signature by another key under an honest vouchId is refused (" + $r.turn.text + ")")
    $wrongMachine = New-HordeTestPhoneSession -Phone $W2.phone -Machine $W.machine -NotBefore $T0 -Seq 7
    $r = Send-SessionAnswer -World $W2 -Session $wrongMachine -Text "For the other machine." -At $T0.AddMinutes(4) -WithVouch
    Check ($r.turn.text.Contains("session-refused") -and -not (Test-Said $W2 "For the other machine.")) ("a vouch bound to another machine's mailbox is refused (" + $r.turn.text + ")")
    $r = Send-SessionAnswer -World $W2 -Session $s2 -Text "Honest, after the forgeries." -At $T0.AddMinutes(5)
    Check ((Test-Said $W2 "Honest, after the forgeries.") -and -not $r.turn.text.Contains("session-")) ("CONTROL TWIN: the honest session still answers after every forgery (" + $r.turn.text + ")")

    Write-Host ""
    Write-Host "--- a replayed envelope ---" -ForegroundColor Cyan
    $e = New-HordeTestPhoneSessionEnvelope -Phone $W2.phone -Session $s2 -Kind "answer" -Channel "decisions" -Body (New-AnswerBody $W2 1 "Said once.") -To $W2.agree -Now $T0.AddMinutes(6)
    [void](Send-ToMachine $W2 $e.text)
    $t = Invoke-Turn $W2 $T0.AddMinutes(6)
    Check (Test-Said $W2 "Said once.") ("CONTROL TWIN: the envelope is taken the first time (" + $t.text + ")")
    [void](Send-ToMachine $W2 $e.text ("replay-" + (New-Id)))
    $t = Invoke-Turn $W2 $T0.AddMinutes(7)
    Check ($t.text.Contains("replay") -and @(Get-Said $W2 | Where-Object { "$(Get-HordeTestMember $_ 'data.text')" -ceq "Said once." }).Count -eq 1) ("the same session envelope again is refused by the journal as a replay, and lands once (" + $t.text + ")")

    Write-Host ""
    Write-Host "--- a question flagged needsPasskey ---" -ForegroundColor Cyan
    $aid = New-Id
    $r = Send-SessionAnswer -World $W2 -Session $s2 -Number 2 -AnswerId $aid -Text "Deploy it." -At $T0.AddMinutes(8)
    Check ($r.turn.text.Contains("needs-passkey") -and -not (Test-Said $W2 "Deploy it.")) ("a session-signed answer to a needsPasskey question is refused as needs-passkey (" + $r.turn.text + ")")
    $rc = Get-Receipt $W2 $W2.phone.keyId
    Check (@(Get-HordeTestMember $rc "session.needsPasskey") -ccontains $aid -and @(Get-HordeTestMember $rc "refused") -cnotcontains $aid) "the receipt lists it under session.needsPasskey, not as refused: the phone asks the passkey and sends it again"
    $pk = New-HordeTestPhoneEnvelope -Phone $W2.phone -Kind "answer" -Channel "decisions" -Body (New-AnswerBody $W2 2 "Deploy it." $aid) -To $W2.agree -Now $T0.AddMinutes(9)
    [void](Send-ToMachine $W2 $pk.text)
    $t = Invoke-Turn $W2 $T0.AddMinutes(9)
    Check ((Test-Said $W2 "Deploy it.") -and $t.text.Contains("done")) ("the same answer with a fresh passkey assertion is applied (" + $t.text + ")")
    $rc = Get-Receipt $W2 $W2.phone.keyId
    Check (@(Get-HordeTestMember $rc "applied") -ccontains $aid -and @(Get-HordeTestMember $rc "session.needsPasskey") -cnotcontains $aid) "and it leaves the needsPasskey list for applied"
    $r = Send-SessionAnswer -World $W2 -Session $s2 -Number 1 -Text "An ordinary one, by session." -At $T0.AddMinutes(10)
    Check ((Test-Said $W2 "An ordinary one, by session.") -and -not $r.turn.text.Contains("needs-passkey")) ("CONTROL TWIN: an ordinary question by session in the same minute is applied (" + $r.turn.text + ")")

    Write-Host ""
    Write-Host "--- end all phone sessions ---" -ForegroundColor Cyan
    $before = Get-Receipt $W2 $W2.phone.keyId
    $live = @(@(Get-HordeTestMember $before "session.vouches") | Where-Object { "$(Get-HordeTestMember $_ 'vouchId')" -ceq $s2.vouchId -and "$(Get-HordeTestMember $_ 'state')" -ceq "live" }).Count
    Check ($live -eq 1) "before end-all the receipt says the phone's session is live"
    $cli = Invoke-HordeCliProcess -Root $root -HordeArgs @("relay", "sessions", "end", "-Reason", "suite end-all") -Env @{ HORDE_HOME = $W2.home }
    Check ($cli.code -eq 0 -and $cli.out.Contains("ended every phone session")) ("horde relay sessions end, the real CLI, ends them (exit " + $cli.code + ": " + $cli.out.Trim() + ")")
    $list = Invoke-HordeCliProcess -Root $root -HordeArgs @("relay", "sessions") -Env @{ HORDE_HOME = $W2.home }
    Check ($list.code -eq 0 -and $list.out.Contains($s2.vouchId) -and $list.out.Contains("session-ended")) ("horde relay sessions lists the session as session-ended (exit " + $list.code + ")")
    # The CLI ends them at the real clock; every answer after it is dated after both that and the last
    # answer above (T0 + 10 min), so no answer here is older than one before it (A STALE ANSWER NEVER WINS).
    $endedAt = $T0.AddMinutes(11)
    if ([datetime]::UtcNow -gt $endedAt) { $endedAt = [datetime]::UtcNow.AddSeconds(1) }
    $r = Send-SessionAnswer -World $W2 -Session $s2 -Text "After end-all." -At $endedAt.AddMinutes(1)
    Check ($r.turn.text.Contains("session-ended") -and -not (Test-Said $W2 "After end-all.")) ("after end-all a session answer is refused as session-ended (" + $r.turn.text + ")")
    $rc = Get-Receipt $W2 $W2.phone.keyId
    Check (@(@(Get-HordeTestMember $rc "session.vouches") | Where-Object { "$(Get-HordeTestMember $_ 'vouchId')" -ceq $s2.vouchId -and "$(Get-HordeTestMember $_ 'state')" -ceq "session-ended" }).Count -eq 1) "and the receipt tells the phone session-ended"
    $pkAfter = New-HordeTestPhoneEnvelope -Phone $W2.phone -Kind "answer" -Channel "decisions" -Body (New-AnswerBody $W2 1 "Per passkey after end-all.") -To $W2.agree -Now $endedAt.AddMinutes(2)
    [void](Send-ToMachine $W2 $pkAfter.text)
    $t = Invoke-Turn $W2 $endedAt.AddMinutes(2)
    Check ((Test-Said $W2 "Per passkey after end-all.") -and $t.text.Contains("done")) ("a per-passkey envelope after end-all is still applied (" + $t.text + ")")
    $s4 = New-HordeTestPhoneSession -Phone $W2.phone -Machine $W2.machine -NotBefore $endedAt.AddMinutes(14) -Seq 10
    $r = Send-SessionAnswer -World $W2 -Session $s4 -Text "Unlocked after end-all." -At $endedAt.AddMinutes(15) -WithVouch
    Check ((Test-Said $W2 "Unlocked after end-all.") -and -not $r.turn.text.Contains("session-")) ("a NEW unlock after end-all is taken (" + $r.turn.text + ")")

    Write-Host ""
    Write-Host "--- revoking the device voids its sessions ---" -ForegroundColor Cyan
    $r = Send-SessionAnswer -World $W2 -Session $sB -Phone $B -Text "Phone B before revoke." -At $endedAt.AddMinutes(16) -WithVouch
    # sB was made before end-all: B unlocks again first.
    $sB2 = New-HordeTestPhoneSession -Phone $B -Machine $W2.machine -NotBefore $endedAt.AddMinutes(16) -Seq 2
    $r = Send-SessionAnswer -World $W2 -Session $sB2 -Phone $B -Text "Phone B, unlocked again." -At $endedAt.AddMinutes(17) -WithVouch
    Check ((Test-Said $W2 "Phone B, unlocked again.") -and -not $r.turn.text.Contains("session-")) ("CONTROL TWIN: phone B's session answers before its device is revoked (" + $r.turn.text + ")")
    $rev = Revoke-HordeRelayTrust -HordeHome $W2.home -Subject "device" -Id $B.deviceId -Reason "phone lost"
    Check ($rev.state -ceq "known") "the device is revoked"
    $r = Send-SessionAnswer -World $W2 -Session $sB2 -Phone $B -Text "Phone B after revoke." -At $endedAt.AddMinutes(18)
    Check ($r.turn.text.Contains("refused") -and -not (Test-Said $W2 "Phone B after revoke.")) ("after the revoke its session answer is refused (" + $r.turn.text + ")")
    $r = Send-SessionAnswer -World $W2 -Session $s4 -Text "Phone A after B's revoke." -At $endedAt.AddMinutes(19)
    Check ((Test-Said $W2 "Phone A after B's revoke.") -and -not $r.turn.text.Contains("session-")) ("CONTROL TWIN: the other device's session still answers (" + $r.turn.text + ")")

    Write-Host ""
    Write-Host "--- the window's front edge, and damaged records ---" -ForegroundColor Cyan
    $r = Send-SessionAnswer -World $W2 -Session $s4 -Text "Before notBefore." -At ([System.DateTimeOffset]::FromUnixTimeMilliseconds($s4.notBefore - 1000).UtcDateTime) -Pc $endedAt.AddMinutes(20)
    Check ($r.turn.text.Contains("session-expired") -and -not (Test-Said $W2 "Before notBefore.")) ("an envelope dated before the session's notBefore is refused as session-expired (" + $r.turn.text + ")")
    $vf = Join-Path $W2.home ("relay\sessions\vouches\" + $s4.vouchId + ".json")
    $orig = [System.IO.File]::ReadAllText($vf)
    [System.IO.File]::WriteAllText($vf, $orig.Replace('"recordedAt":', '"recordedAt": '), [System.Text.Encoding]::ASCII)
    $r = Send-SessionAnswer -World $W2 -Session $s4 -Text "Records damaged." -At $endedAt.AddMinutes(21)
    Check ($r.turn.text.Contains("session-unknown") -and $r.turn.text.Contains("cannot be read") -and -not (Test-Said $W2 "Records damaged.")) ("a damaged session record stops every session until it is repaired (" + $r.turn.text + ")")
    $pkD = New-HordeTestPhoneEnvelope -Phone $W2.phone -Kind "answer" -Channel "decisions" -Body (New-AnswerBody $W2 1 "Passkey while damaged.") -To $W2.agree -Now $endedAt.AddMinutes(22)
    [void](Send-ToMachine $W2 $pkD.text)
    $t = Invoke-Turn $W2 $endedAt.AddMinutes(22)
    Check ((Test-Said $W2 "Passkey while damaged.") -and $t.text.Contains("done")) ("a per-passkey envelope is still applied while the session records are damaged (" + $t.text + ")")
    [System.IO.File]::WriteAllText($vf, $orig, [System.Text.Encoding]::ASCII)
    $r = Send-SessionAnswer -World $W2 -Session $s4 -Text "Records repaired." -At $endedAt.AddMinutes(23)
    Check ((Test-Said $W2 "Records repaired.") -and -not $r.turn.text.Contains("session-")) ("CONTROL TWIN: repaired, the session answers again (" + $r.turn.text + ")")

    # --- review of PR 302: the two must-fix rules, each beside its twin, in a world of their own ---
    Write-Host ""
    Write-Host "--- an unlock the PC never saw is idle from its own notBefore ---" -ForegroundColor Cyan
    $W3 = New-World
    $B3 = [datetime]::UtcNow.AddSeconds(-2)
    $s5 = New-HordeTestPhoneSession -Phone $W3.phone -Machine $W3.machine -NotBefore $B3 -Seq 1
    $r = Send-SessionAnswer -World $W3 -Session $s5 -Text "First use 71 minutes after unlock." -At $B3.AddMinutes(71) -WithVouch
    Check ($r.turn.text.Contains("session-idle") -and -not (Test-Said $W3 "First use 71 minutes after unlock.")) ("a first use past the idle limit (60) and the skew (10) after unlock is refused as session-idle, though the PC never held the vouch (" + $r.turn.text + ")")
    Check (-not (Test-Path -LiteralPath (Join-Path $W3.home ("relay\sessions\vouches\" + $s5.vouchId + ".json")))) "and that vouch is not recorded"
    $s6 = New-HordeTestPhoneSession -Phone $W3.phone -Machine $W3.machine -NotBefore $B3.AddMinutes(60) -Seq 2
    $r = Send-SessionAnswer -World $W3 -Session $s6 -Text "First use 69 minutes after unlock." -At $B3.AddMinutes(129) -WithVouch
    Check ((Test-Said $W3 "First use 69 minutes after unlock.") -and -not $r.turn.text.Contains("session-")) ("CONTROL TWIN: a first use within the idle limit and the skew is taken (" + $r.turn.text + ")")

    Write-Host ""
    Write-Host "--- end-all holds against a phone clock running ahead ---" -ForegroundColor Cyan
    $end3 = Stop-HordeRelaySessions -HordeHome $W3.home -Reason "suite end-all against a fast phone" -Now $B3.AddMinutes(130)
    Check ($end3.state -ceq "known") "every session is ended at the PC's T+130"
    # The phone runs 9 minutes fast: unlocked at the PC's T+130, it writes notBefore T+139. The page was
    # offline, so the PC never recorded the vouch; a thief's first answer comes at the PC's T+132.
    $s7 = New-HordeTestPhoneSession -Phone $W3.phone -Machine $W3.machine -NotBefore $B3.AddMinutes(139) -Seq 3
    $r = Send-SessionAnswer -World $W3 -Session $s7 -Text "Fast clock, after end-all." -At $B3.AddMinutes(140) -Pc $B3.AddMinutes(132) -WithVouch
    Check ($r.turn.text.Contains("session-ended") -and -not (Test-Said $W3 "Fast clock, after end-all.")) ("a vouch whose notBefore a fast phone clock put after the end-all is still ended (" + $r.turn.text + ")")
    $s8 = New-HordeTestPhoneSession -Phone $W3.phone -Machine $W3.machine -NotBefore $B3.AddMinutes(141) -Seq 4
    $r = Send-SessionAnswer -World $W3 -Session $s8 -Text "Unlocked well after end-all." -At $B3.AddMinutes(142) -WithVouch
    Check ((Test-Said $W3 "Unlocked well after end-all.") -and -not $r.turn.text.Contains("session-")) ("CONTROL TWIN: an unlock more than the skew after the end-all is taken (" + $r.turn.text + ")")

    Write-Host ""
    Write-Host "--- an envelope under a vouch the PC could not record waits, never taken as new ---" -ForegroundColor Cyan
    # Route 1, the name is another passkey's record: phone C vouches for a session key, then phone A
    # vouches for the very same key. A's vouch verifies, but its record's name is taken.
    $C3 = Add-PhoneTo -World $W3
    $sC = New-HordeTestPhoneSession -Phone $C3 -Machine $W3.machine -NotBefore $B3.AddMinutes(142) -Seq 1
    $o = Send-Opening -World $W3 -Session $sC -At $B3.AddMinutes(143) -Phone $C3
    Check ($o.text.Contains("is open")) ("CONTROL: phone C's session over the key is open (" + $o.text + ")")
    $sA = New-HordeTestPhoneSession -Phone $W3.phone -Machine $W3.machine -NotBefore $B3.AddMinutes(142) -Seq 5 -Key $sC.key
    Check ($sA.vouchId -ceq $sC.vouchId) "CONTROL: phone A's vouch names the same key, so the same vouchId"
    $r = Send-SessionAnswer -World $W3 -Session $sA -Text "Under a vouch recorded as another's." -At $B3.AddMinutes(144) -WithVouch
    Check ($r.turn.text.Contains("vouch " + $sA.vouchId + " could not be recorded") -and -not (Test-Said $W3 "Under a vouch recorded as another's.")) ("an envelope whose new vouch's name is another passkey's record waits, not taken (" + $r.turn.text + ")")
    # Route 2, the write itself fails: the vouches folder refuses new files for a moment.
    $vdir = Join-Path $W3.home "relay\sessions\vouches"
    $who = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $denied = $false
    try {
        $null = & icacls.exe $vdir /deny ("*" + $who + ":(WD,AD)")
        $probe = Join-Path $vdir ("probe-" + (New-Id) + ".tmp")
        try { [System.IO.File]::WriteAllText($probe, "x"); [System.IO.File]::Delete($probe) } catch { $denied = $true }
        Check ($denied) "CONTROL: the vouches folder refuses a new file while denied"
        $s9 = New-HordeTestPhoneSession -Phone $W3.phone -Machine $W3.machine -NotBefore $B3.AddMinutes(144) -Seq 6
        $r = Send-SessionAnswer -World $W3 -Session $s9 -Text "Under a vouch that could not be written." -At $B3.AddMinutes(145) -WithVouch
        Check ($r.turn.text.Contains("vouch " + $s9.vouchId + " could not be recorded") -and -not (Test-Said $W3 "Under a vouch that could not be written.")) ("an envelope whose new vouch could not be written waits, not taken (" + $r.turn.text + ")")
    } finally { $null = & icacls.exe $vdir /remove:d ("*" + $who) }
    $t = Invoke-Turn $W3 $B3.AddMinutes(146)
    Check ((Test-Said $W3 "Under a vouch that could not be written.") -and -not (Test-Said $W3 "Under a vouch recorded as another's.")) ("CONTROL TWIN: once the folder takes files again the waiting envelope is taken; the other passkey's name still never is (" + $t.text + ")")
} finally {
    Exit-HordeTestEmptyFleet -Pin $fleetPin
    $env:HORDE_HOME = $realHome
    foreach ($w in @($script:worlds)) { Close-HordeRelayRunContext -Context $w.ctx }
    $made = New-Object System.Collections.ArrayList
    foreach ($h in @($script:homes)) {
        foreach ($k in @(Get-TestKeyNames -HordeHome $h)) {
            [void]$made.Add($k)
            try { [void](Remove-HordeRelayKey -Name $k.n -Scope $k.s) } catch { Write-Host ("  cleanup of " + $k.n + " failed: " + $_.Exception.Message) -ForegroundColor Yellow }
        }
    }
    $left = @($made | Where-Object { (Find-HordeRelayCngKey -Name $_.n -Scope $_.s) -cne "" })
    Check ($made.Count -ge 2 -and $left.Count -eq 0) ("every key the suite's homes name is gone (" + $made.Count + " names, " + $left.Count + " left)")
    foreach ($h in @($script:homes)) {
        if ((Split-Path -Leaf $h) -match '^horde-relay-sessions-[0-9a-f]{32}$') { Remove-Item -LiteralPath $h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Check (@($script:homes | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 0) "every temporary home is gone"
}
Check ($env:HORDE_HOME -ceq $realHome) "HORDE_HOME is what it was"
Complete-HordeSuite -Success "a session answers exactly while the PC's own clock and records say it lives, and every other way is refused by name"
