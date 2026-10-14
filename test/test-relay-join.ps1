# CAN A NEW PHONE BECOME TRUSTED BY ASKING - ONLY WHEN THE FOUNDER TYPES THE NUMBER IT SHOWS ON A DEVICE HE
# HOLDS - AND IN NO OTHER WAY?
#
# Phone-started pairing (relay/Join.ps1, channels/join; design-phone-started-pairing.md and C's
# conditions in it), the machine's side, over relays/local in this process, with phones held in memory
# (test/lib/RelayPhone.ps1): the new phone's request and passkey, a trusted phone that approves. Every
# condition has a must-refuse and a must-accept twin:
#   1. a STRANGER signed in to the same Google account asks and registers a passkey: it stays PENDING and
#      trusts nothing; nothing approves it without the number; the founder's request, approved with the
#      right number at the machine, is trusted (the twin);
#   2. a WRONG NUMBER at the machine is refused, three reject the request; the right one approves;
#   3. a SECOND PENDING request is refused while one is open; once that one ends, a new one is taken;
#      a reject frees the slot at once;
#   4. an EXPIRED request is closed, its passkey revoked, its offer voided - and NOTHING IS RETRIED: no
#      second offer; a request that arrives expired is refused;
#   5. a REPLAYED, SWAPPED or TAMPERED approval from a trusted phone fails: another request's transcript
#      hash, a tampered hash, another device, an approval after the request closed; the right one is
#      taken (the twin);
#   6. THE RELAY ALONE CANNOT APPROVE: an approve envelope signed by a passkey that is not trusted, the
#      new phone's own pending passkey approving itself, and a join request under another key than its
#      own are each refused;
#   7. EVERY TRUSTED DEVICE IS TOLD: a notice for the request and one for each outcome - approved,
#      rejected, expired - naming the device; a decisions question asked and closed;
#   8. REVOCATION ENDS a pending request.
# And `horde relay joins / approve / reject`, the shipped command, once each.
#
# Every home is the suite's own under %TEMP%; keys are software keys, removed and checked gone.

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
. (Join-Path $root "test\lib\RelayPhone.ps1")
. (Join-Path $root "test\lib\Cli.ps1")
Set-StrictMode -Version Latest

if ((Get-HordeRelayKeyStore).state -cne "known") {
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Complete-HordeSuite -Success "no key store here: no machine identity can be made, so nothing was run" -PassCode 3
}

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$realHome = $env:HORDE_HOME
$work = Join-Path $env:TEMP ("horde-relay-join-" + [guid]::NewGuid().ToString("N"))
$hh = Join-Path $work "home"
New-Item -ItemType Directory -Path (Join-Path $hh "settings") -Force | Out-Null
$keysMade = @()
# The suite's time: now, or a moment it set (Move-Clock) for a turn that must be later.
$script:clockAt = $null
function Get-Clock { if ($null -ne $script:clockAt) { return $script:clockAt }; return [datetime]::UtcNow }

function New-Id { return [guid]::NewGuid().ToString("N") }
function New-NewPhone {
    # A new phone: the request key it asks with, and the passkey it will make.
    $k = New-HordeRelayP256Key -Use "ecdh"
    return [pscustomobject]@{ key = $k; public = (ConvertTo-HordeRelayP256Public -Key $k); phone = (New-HordeTestPhone); request = (New-Id); offerText = ""; number = "" }
}
function Send-Join {
    # The new phone's request into the machine's mailbox, as the relay's join route puts it.
    param($Np, [string]$Key = "", [long]$ExpiresInMs = 600000, [string]$Machine = "", [string]$Label = "Pixel 9")
    $nowMs = ConvertTo-HordeRelayRecordMs -Time (Get-Clock)
    $t = ConvertTo-HordeRelayRecordText -Spec (Get-HordeRelayJoinRequestSpec) -Values @{ v = 1; kind = "horde-relay-join-request"; request = $Np.request; horde = "work"
        machine = $(if ($Machine -cne "") { $Machine } else { $script:id.sign.keyId }); label = $Label; agent = "Chrome on Android"; requestKey = (ConvertTo-HordeRelayBase64Url -Bytes $Np.public)
        country = "IL"; requestedAt = $nowMs; expiresAt = ($nowMs + $ExpiresInMs) }
    return (Send-HordeRelayItem -Connection $script:conn -Mailbox $script:ctx.mailbox -Text $t -Key $(if ($Key -cne "") { $Key } else { "join/" + $Np.request }))
}
function Invoke-Turn {
    # One turn of the runner's path in and of the join channel's Tick, at the suite's clock.
    $in = Receive-HordeRelayInbox -Context $script:ctx -TimeoutMs 0 -Now (Get-Clock)
    $done = Invoke-HordeRelayUnfinished -Context $script:ctx -Now (Get-Clock)
    $tick = Invoke-HordeJoinChannelTick -Context $script:ctx -Now (Get-Clock)
    return [pscustomobject]@{ in = $in; done = $done; tick = $tick }
}
function Get-Offer {
    # What the new phone finds in its reply mailbox, opened with its request key: the offer text, or "".
    param($Np)
    $r = Receive-HordeRelayItems -Connection $script:conn -Mailbox ("work/jr-" + $Np.request) -Since 0
    if ($r.state -cne "known") { return "" }
    foreach ($it in @($r.value.items)) {
        $s = Read-HordeRelayRecordText -Text $it.text -Spec (Get-HordeRelayJoinOfferSealedSpec) -Kind "horde-relay-join-offer"
        if (-not $s.ok) { continue }
        $plain = Unprotect-HordeRelayHpke -RecipientKey $Np.key -Enc (ConvertFrom-HordeRelayBase64Url -Text $s.value.enc) -Info (Get-HordeRelayJoinSealedDomain -Part "info") `
            -Aad (Get-HordeRelayJoinSealedDomain -Part "aad" -Horde "work" -Request $Np.request -RequestKeyId (Get-HordeRelayKeyId -Public $Np.public)) -Sealed (ConvertFrom-HordeRelayBase64Url -Text $s.value.ct)
        if ($null -ne $plain) { return [System.Text.Encoding]::ASCII.GetString($plain) }
    }
    return ""
}
function Get-ReplyCount { param($Np) $r = Receive-HordeRelayItems -Connection $script:conn -Mailbox ("work/jr-" + $Np.request) -Since 0; if ($r.state -cne "known") { return -1 }; return @($r.value.items).Count }
function Send-Passkey {
    # The new phone pairs with the offer: its passkey's response, sealed, in the offer's pairing mailbox.
    # Its number is kept as the new phone shows it.
    param($Np)
    $o = (Read-HordeRelayPairingOffer -Text $Np.offerText).value
    $challenge = Get-HordeRelayPairingChallenge -OfferText $Np.offerText
    $resp = New-HordeTestPhonePairingResponse -Offer ([pscustomobject]@{ offer = $o.offer; code = $o.code; challenge = (ConvertTo-HordeRelayBase64Url -Bytes $challenge) }) -Phone $Np.phone -Label "Pixel 9"
    $Np.number = Get-HordeRelayPairingFingerprint -Challenge $challenge -Public $Np.phone.public -CredentialId $Np.phone.credentialId -RpId "relay.example.test"
    return (Send-HordeRelayItem -Connection $script:conn -Mailbox $o.pairMailbox -Text (New-HordeRelayPairingSealedText -OfferText $Np.offerText -Response $resp) -Key ("pairing/" + $o.offer))
}
function Start-Join {
    # Request, answer, passkey, transcript: a join waiting for its number. The new phone.
    param([string]$Label = "Pixel 9")
    $np = New-NewPhone
    [void](Send-Join -Np $np -Label $Label)
    [void](Invoke-Turn)
    $np.offerText = Get-Offer -Np $np
    if ($np.offerText -cne "") { [void](Send-Passkey -Np $np); [void](Invoke-Turn) }
    return $np
}
function Get-Join { param($Np) $j = Get-HordeRelayJoin -HordeHome $hh -Request $Np.request -Now (Get-Clock); if ($j.state -cne "known") { return $null }; return $j.value }
function Get-Transcripts {
    # The join envelopes the trusted phone finds in the phone mailbox, opened: { kind; text } each.
    $r = Receive-HordeRelayItems -Connection $script:conn -Mailbox "work/phone" -Since 0
    $out = New-Object System.Collections.ArrayList
    foreach ($it in @($r.value.items)) {
        $e = Read-HordeRelayEnvelope -Text $it.text
        if (-not $e.ok -or $e.value.header.channel -cne "join") { continue }
        $machine = New-HordeRelaySender -Public $script:id.sign.public -Proof "es256"
        $verdict = New-HordeKnown -Value ([pscustomobject]@{ key = (Get-HordeRelayReplayKey -Header $e.value.header); fresh = $true })
        $o = Unprotect-HordeRelayEnvelope -Envelope $e.value -Senders @{ ($machine.keyId) = $machine } -RecipientKeys @{ (Get-HordeRelayKeyId -Public $script:T.agreePublic) = $script:T.agree } -Replay $verdict -Channel "join" -Kind $e.value.header.kind
        if ($o.ok) { [void]$out.Add([pscustomobject]@{ kind = $e.value.header.kind; text = [System.Text.Encoding]::ASCII.GetString($o.value) }) }
    }
    return @($out.ToArray())
}
function Send-Approval {
    # The trusted phone's approve envelope (or -By another passkey's), as phone-core.js's approveJoin.
    param($Np, [string]$Transcript, [string]$Device = "", $By = $null, [string]$Kind = "approve")
    if ($null -eq $By) { $By = $script:T }
    $j = Get-Join $Np
    $dev = $(if ($Device -cne "") { $Device } elseif ($null -ne $j -and $null -ne $j.device) { $j.device.id } else { "0" * 32 })
    $body = $(if ($Kind -ceq "approve") { '{"v":1,"request":"' + $Np.request + '","device":"' + $dev + '","transcript":"' + $Transcript + '"}' } else { '{"v":1,"request":"' + $Np.request + '"}' })
    $env = New-HordeTestPhoneEnvelope -Phone $By -Kind $Kind -Channel "join" -Body ($utf8.GetBytes($body)) -To @(, ([byte[]]$script:id.agree.public))
    return (Send-HordeRelayItem -Connection $script:conn -Mailbox $script:ctx.mailbox -Text $env.text -Key $env.key)
}
function Get-NoticeTexts {
    $p = Join-Path $hh "notices\notices.jsonl"
    if (-not (Test-Path -LiteralPath $p)) { return @() }
    return @(Get-Content -LiteralPath $p | Where-Object { $_.Trim() } | ForEach-Object { ($_ | ConvertFrom-Json).text })
}
function Get-DeviceState { param($Np) $j = Get-Join $Np; if ($null -eq $j -or $null -eq $j.device) { return "none" }; return $j.device.state }
function Move-Clock { param([int]$Ms) $script:clockAt = $(if ($Ms -eq 0) { $null } else { [datetime]::UtcNow.AddMilliseconds($Ms) }) }

try {
    $env:HORDE_HOME = $hh
    [System.IO.File]::WriteAllText((Join-Path $hh "settings\relay.json"), '{"schemaVersion": 1, "settings": {"horde": "work", "pairRpId": "relay.example.test", "pairOrigin": "https://relay.example.test"}}', $utf8)
    $made = New-HordeRelayMachineIdentity -HordeHome $hh -Provider "software"
    Check ($made.state -ceq "known") "CONTROL: the machine has its relay identity"
    $script:id = $made.value
    $keysMade = @(@{ n = $script:id.sign.name; s = $script:id.scope }, @{ n = $script:id.agree.name; s = $script:id.scope })
    $c = Connect-HordeRelay -Name "local" -Options @{ root = (Join-Path $work "relay") }
    $script:conn = $c.value
    $ctxMade = New-HordeRelayRunContext -HordeHome $hh -Connection $script:conn
    $script:ctx = $ctxMade.value
    # The founder's trusted phone: paired, confirmed, its phone key in the store.
    $script:T = New-HordeTestPhone
    [void](Add-HordeTestPhonePairing -HordeHome $hh -Phone $script:T)
    $v = New-HordeTestPhoneVouch -Phone $script:T -Horde "work"
    $pk = Add-HordeRelayPhoneKey -HordeHome $hh -AgreePublic $script:T.agreePublic -By $script:T.keyId -AuthenticatorData $v.authenticatorData -ClientDataJson $v.clientDataJson -Signature $v.signature
    Check ($c.state -ceq "known" -and $ctxMade.state -ceq "known" -and $pk.state -ceq "known") "CONTROL: a local relay, a run context, and the founder's trusted phone with its key"

    Write-Host ""
    Write-Host "--- 1. a stranger in the same Google account asks: a request trusts nothing ---" -ForegroundColor Cyan
    $s = Start-Join -Label "Stranger"
    $sj = Get-Join $s
    Check ($s.offerText -cne "" -and (Read-HordeRelayPairingOffer -Text $s.offerText).ok) "THE MACHINE ANSWERS AT ONCE: its offer, sealed to the request key, opens with that key only"
    $o = (Read-HordeRelayPairingOffer -Text $s.offerText).value
    Check ($o.machine -ceq $script:id.sign.keyId -and $o.horde -ceq "work") "the offer is this machine's, of this horde"
    Check ($null -ne $sj -and $sj.open -and (Get-DeviceState $s) -ceq "pending") ("the stranger's passkey registered and is PENDING: it trusts nothing (" + (Get-DeviceState $s) + ")")
    Check (@((Find-HordeRelayTrustedSenders -HordeHome $hh).value.Keys) -cnotcontains $s.phone.keyId) "it signs nothing the machine takes"
    $tx = @(Get-Transcripts | Where-Object { $_.kind -ceq "request" })
    Check ($tx.Count -eq 1 -and $tx[0].text.Contains('"request":"' + $s.request + '"') -and -not $tx[0].text.Contains($s.number) -and -not $tx[0].text.Contains($s.number.Replace("-", ""))) "the trusted phone is sent the transcript - and never the number"
    $notes = @(Get-NoticeTexts)
    Check (@($notes | Where-Object { $_.Contains("A new phone asks to join this PC: 'Stranger', Chrome on Android, IL") -and $_.Contains("If this is not your phone, reject it") -and $_.Contains("change your Google password") }).Count -eq 1) ("EVERY TRUSTED DEVICE IS TOLD of the request, naming the device, browser, country and time (" + ($notes -join " | ") + ")")
    $qs = Invoke-HordeDecision -Operation "list" -Root $script:ctx.decisionsRoot -Request @{}
    $asked = @($(if ($qs.state -ceq "known") { @($qs.value.questions) } else { @() }) | Where-Object { "$($_.title)".StartsWith("A new phone asks to join: 'Stranger'") })
    Check ($asked.Count -eq 1) "and it is a decisions question"
    $before = @((Get-HordeRelayTrust -HordeHome $hh).value.devices | ForEach-Object { $_.id + " " + $_.state }) -join "; "
    $wrong = $(if ($s.number -ceq "0000-0000-0000") { "1111-1111-1111" } else { "0000-0000-0000" })
    $w1 = Approve-HordeRelayJoin -HordeHome $hh -Request $s.request -Number $wrong -Now (Get-Clock)
    Check (-not $w1.ok -and $w1.reason.Contains("does not match") -and (Get-DeviceState $s) -ceq "pending") ("WITHOUT THE NUMBER IT STAYS PENDING: a guess is refused (" + $w1.reason + ")")
    $rj = Reject-HordeRelayJoin -HordeHome $hh -Request $s.request -Reason "not my phone" -Now (Get-Clock)
    $null = Invoke-Turn
    Check ($rj.ok -and (Get-DeviceState $s) -ceq "revoked" -and (Get-Join $s).closed.outcome -ceq "rejected") "rejected, its passkey is revoked for good, and the request is closed"
    Check (@(Get-NoticeTexts | Where-Object { $_.Contains("'Stranger'") -and $_.Contains("was rejected") }).Count -eq 1) "a notice says it was rejected"
    $qs = Invoke-HordeDecision -Operation "list" -Root $script:ctx.decisionsRoot -Request @{}
    $stillOpen = @($(if ($qs.state -ceq "known") { @($qs.value.questions) } else { @() }) | Where-Object { "$($_.title)".StartsWith("A new phone asks to join: 'Stranger'") })
    Check ($stillOpen.Count -eq 0) "and its question is closed"
    $tc = @(Get-Transcripts | Where-Object { $_.kind -ceq "closed" -and $_.text.Contains($s.request) -and $_.text.Contains("rejected") })
    Check ($tc.Count -eq 1) "and the trusted phone is told it ended"

    Write-Host ""
    Write-Host "--- 2 and 3. the founder's own phone, a second request, the number typed at the machine ---" -ForegroundColor Cyan
    $f = Start-Join -Label "Founder new phone"
    Check ((Get-Join $f).open -and (Get-DeviceState $f) -ceq "pending") "A REJECT FREES THE SLOT AT ONCE: the next request is taken right after"
    $second = New-NewPhone
    [void](Send-Join -Np $second -Label "Second")
    $t2 = Invoke-Turn
    $ref2 = @(Get-HordeTestMember -Object $t2.in -Path "value.refused")
    Check ($ref2.Count -eq 1 -and $ref2[0].Contains("another join request") -and $null -eq (Get-Join $second) -and (Get-ReplyCount $second) -eq 0) ("A SECOND PENDING REQUEST IS REFUSED, never queued, and answered with nothing (" + ($ref2 -join " | ") + ")")
    $wrongF = $(if ($f.number -ceq "0000-0000-0000") { "1111-1111-1111" } else { "0000-0000-0000" })
    $a1 = Approve-HordeRelayJoin -HordeHome $hh -Request $f.request -Number $wrongF -Now (Get-Clock)
    Check (-not $a1.ok -and $a1.reason.Contains("2 tries left") -and (Get-DeviceState $f) -ceq "pending") ("A WRONG NUMBER is refused, with the tries left (" + $a1.reason + ")")
    $a2 = Approve-HordeRelayJoin -HordeHome $hh -Request $f.request -Number $f.number -Now (Get-Clock)
    $null = Invoke-Turn
    Check ($a2.ok -and (Get-DeviceState $f) -ceq "trusted" -and (Get-Join $f).closed.outcome -ceq "approved") "THE RIGHT NUMBER, typed at the machine, approves it: trusted, and the request closed approved"
    $pm = Receive-HordeRelayItems -Connection $script:conn -Mailbox (Read-HordeRelayPairingOffer -Text $f.offerText).value.pairMailbox -Since 0
    Check ($pm.state -ceq "known" -and @($pm.value.items | Where-Object { $_.key -ceq ("confirmed/" + (Read-HordeRelayPairingOffer -Text $f.offerText).value.offer) }).Count -eq 1) "the new phone is told it is confirmed, so it offers Finish pairing"
    Check (@(Get-NoticeTexts | Where-Object { $_.Contains("'Founder new phone'") -and $_.Contains("was approved") }).Count -eq 1) "a notice says it was approved"
    $again = Approve-HordeRelayJoin -HordeHome $hh -Request $f.request -Number $f.number -Now (Get-Clock)
    Check (-not $again.ok -and $again.reason.Contains("closed")) "an approved request is approved once: again, it is refused"
    $third = Start-Join -Label "Third"
    Check ((Get-Join $third).open) "ONCE THE PENDING ONE ENDED, a new request is taken (the twin of the refusal above)"
    foreach ($n in 1..2) { $null = Approve-HordeRelayJoin -HordeHome $hh -Request $third.request -Number $wrongF -Now (Get-Clock) }
    $a3 = Approve-HordeRelayJoin -HordeHome $hh -Request $third.request -Number $wrongF -Now (Get-Clock)
    $null = Invoke-Turn
    Check (-not $a3.ok -and $a3.reason.Contains("rejected") -and (Get-DeviceState $third) -ceq "revoked" -and (Get-Join $third).closed.outcome -ceq "rejected") ("THREE WRONG NUMBERS reject the request and revoke its passkey (" + $a3.reason + ")")

    Write-Host ""
    Write-Host "--- 4. an expired request is gone, and never retried ---" -ForegroundColor Cyan
    $x = Start-Join -Label "Late"
    $repliesBefore = Get-ReplyCount $x
    Move-Clock -Ms 600500
    $null = Invoke-Turn
    $xj = Get-Join $x
    Check ($null -ne $xj -and $null -ne $xj.closed -and $xj.closed.outcome -ceq "expired" -and (Get-DeviceState $x) -ceq "revoked") ("past its 10 minutes it is closed expired, its passkey revoked (" + $(if ($null -ne $xj -and $null -ne $xj.closed) { $xj.closed.outcome } else { "open" }) + ")")
    $null = Invoke-Turn
    Move-Clock -Ms 0
    Check ((Get-ReplyCount $x) -eq $repliesBefore -and $repliesBefore -eq 1) ("NOT RETRIED: no second offer, however many turns (" + (Get-ReplyCount $x) + " item(s))")
    $late = Approve-HordeRelayJoin -HordeHome $hh -Request $x.request -Number $x.number -Now (Get-Clock)
    Check (-not $late.ok -and (Get-DeviceState $x) -ceq "revoked") "and its right number approves nothing any more"
    Check (@(Get-NoticeTexts | Where-Object { $_.Contains("'Late'") -and $_.Contains("was expired") }).Count -eq 1) "a notice says it expired"
    $dead = New-NewPhone
    [void](Send-Join -Np $dead -ExpiresInMs -1000)
    $td = Invoke-Turn
    Check (@(Get-HordeTestMember -Object $td.in -Path "value.refused" | Where-Object { "$_".Contains("expired before it was read") }).Count -eq 1 -and $null -eq (Get-Join $dead)) "a request that arrives expired is refused, and nothing is made for it"

    Write-Host ""
    Write-Host "--- 5 and 6. a trusted phone's approval: replayed, swapped, tampered, forged - and the right one ---" -ForegroundColor Cyan
    $p = Start-Join -Label "Phone P"
    $tp = @(Get-Transcripts | Where-Object { $_.kind -ceq "request" -and $_.text.Contains($p.request) })
    Check ($tp.Count -eq 1) "CONTROL: the trusted phone holds P's transcript"
    $hashP = Get-HordeRelayJoinTranscriptHash -Text $tp[0].text
    # Its number, as the trusted phone computes it from the transcript alone: the new phone's number.
    $tv = (Read-HordeRelayRecordText -Text $tp[0].text -Spec (Get-HordeRelayJoinTranscriptSpec) -Kind "horde-relay-join-transcript").value
    $computed = Get-HordeRelayPairingFingerprint -Challenge (ConvertFrom-HordeRelayBase64Url -Text $tv.challenge) -Public (ConvertFrom-HordeRelayBase64Url -Text $tv.publicKey) -CredentialId (ConvertFrom-HordeRelayBase64Url -Text $tv.credentialId) -RpId $tv.rpId
    Check ($computed -ceq $p.number) "the number the trusted phone computes from the transcript is the one the new phone shows"
    $old = @(Get-Transcripts | Where-Object { $_.kind -ceq "request" -and $_.text.Contains($x.request) })
    $hashOld = Get-HordeRelayJoinTranscriptHash -Text $old[0].text
    $tampered = $hashP.Substring(0, 42) + $(if ($hashP.Substring(42, 1) -ceq "A") { "B" } else { "A" })
    $stranger = New-HordeTestPhone
    [void](Send-Approval -Np $p -Transcript $hashOld)
    [void](Send-Approval -Np $p -Transcript $tampered)
    [void](Send-Approval -Np $p -Transcript $hashP -Device ("ab" * 16))
    [void](Send-Approval -Np $p -Transcript $hashP -By $stranger)
    [void](Send-Approval -Np $p -Transcript $hashP -By $p.phone)
    $tr = Invoke-Turn
    $refused = @(@(Get-HordeTestMember -Object $tr.in -Path "value.refused") + @(Get-HordeTestMember -Object $tr.done -Path "value.refused"))
    Check (@($refused | Where-Object { "$_".Contains("transcript hash is not the one") }).Count -eq 2) ("A SWAPPED approval (another request's transcript) and a TAMPERED hash are refused (" + ($refused -join " | ") + ")")
    Check (@($refused | Where-Object { "$_".Contains("names the device") }).Count -eq 1) "one naming another device is refused"
    Check (@($refused | Where-Object { "$_".Contains("the sender " + $stranger.keyId) }).Count -eq 1) "THE RELAY ALONE CANNOT APPROVE: an approval signed by a passkey that is not trusted is refused before it is opened"
    Check (@($refused | Where-Object { "$_".Contains("the sender " + $p.phone.keyId) }).Count -eq 1) "nor can the new phone's own pending passkey approve itself"
    Check ((Get-DeviceState $p) -ceq "pending" -and (Get-Join $p).open) "and none of them trusted anything"
    [void](Send-Approval -Np $p -Transcript $hashP)
    $null = Invoke-Turn
    $null = Invoke-Turn
    Check ((Get-DeviceState $p) -ceq "trusted" -and (Get-Join $p).closed.outcome -ceq "approved") "THE RIGHT APPROVAL from the trusted phone - this request, this device, this transcript's hash - is taken: trusted"
    [void](Send-Approval -Np $p -Transcript $hashP)
    $rp = Invoke-Turn
    Check (@(@(Get-HordeTestMember -Object $rp.in -Path "value.refused") + @(Get-HordeTestMember -Object $rp.done -Path "value.refused")) | Where-Object { "$_".Contains("approved once") -or "$_".Contains("closed") -or "$_".Contains("already") -or "$_".Contains("replay") }).Count -ge 1 "A REPLAYED approval, after it was taken, changes nothing"
    $k = New-NewPhone
    [void](Send-Join -Np $k -Key ("join/" + (New-Id)))
    $tk = Invoke-Turn
    Check (@(Get-HordeTestMember -Object $tk.in -Path "value.refused" | Where-Object { "$_".Contains("only the relay's join route puts one") }).Count -eq 1 -and $null -eq (Get-Join $k)) "a join request under another key than its own is refused"
    $other = New-NewPhone
    [void](Send-Join -Np $other -Machine ("cd" * 16))
    $to = Invoke-Turn
    Check (@(Get-HordeTestMember -Object $to.in -Path "value.refused" | Where-Object { "$_".Contains("not this one") }).Count -eq 1) "and one for another machine"

    Write-Host ""
    Write-Host "--- 7 and 8. revocation ends a pending request; the shipped command ---" -ForegroundColor Cyan
    $r = Start-Join -Label "Revoked"
    $rv = Revoke-HordeRelayTrust -HordeHome $hh -Subject "device" -Id (Get-Join $r).device.id -Reason "ended at the machine"
    $null = Invoke-Turn
    Check ($rv.state -ceq "known" -and (Get-Join $r).closed.outcome -ceq "ended") "REVOKING the pending passkey ends its request"
    $cli = Start-Join -Label "By the command"
    $list = Invoke-HordeCliProcess -Root $root -HordeArgs @("relay", "joins") -Env @{ HORDE_HOME = $hh }
    Check ($list.code -eq 0 -and $list.out.Contains("join " + $cli.request) -and $list.out.Contains("waiting for the number") -and -not $list.out.Contains($cli.number) -and -not $list.out.Contains($cli.number.Replace("-", ""))) ("horde relay joins lists the request - never its number (exit " + $list.code + ")")
    $bad = Invoke-HordeCliProcess -Root $root -HordeArgs @("relay", "approve", $cli.request, "0000-0000-0001") -Env @{ HORDE_HOME = $hh }
    Check ($bad.code -ne 0 -and $bad.out.Contains("does not match") -and (Get-DeviceState $cli) -ceq "pending") ("horde relay approve with a wrong number fails, and trusts nothing (exit " + $bad.code + ")")
    $good = Invoke-HordeCliProcess -Root $root -HordeArgs @("relay", "approve", $cli.request, $cli.number) -Env @{ HORDE_HOME = $hh }
    Check ($good.code -eq 0 -and $good.out.Contains("is trusted") -and (Get-DeviceState $cli) -ceq "trusted") ("with the new phone's number it approves (exit " + $good.code + ")")
    $null = Invoke-Turn
    $rc = Start-Join -Label "Rejected by the command"
    $rej = Invoke-HordeCliProcess -Root $root -HordeArgs @("relay", "reject", $rc.request) -Env @{ HORDE_HOME = $hh }
    Check ($rej.code -eq 0 -and (Get-DeviceState $rc) -ceq "revoked" -and (Get-Join $rc).closed.outcome -ceq "rejected") ("horde relay reject rejects it (exit " + $rej.code + ")")
} finally {
    Close-HordeRelayRunContext -Context $script:ctx
    Exit-HordeTestEmptyFleet -Pin $fleetPin
    $env:HORDE_HOME = $realHome
    foreach ($k in @($keysMade)) { try { [void](Remove-HordeRelayKey -Name $k.n -Scope $k.s) } catch { } }
    $left = @($keysMade | Where-Object { (Find-HordeRelayCngKey -Name $_.n -Scope $_.s) -cne "" })
    Check (@($keysMade).Count -eq 2 -and $left.Count -eq 0) "both keys of the suite's identity are gone"
    if ((Split-Path -Leaf $work) -match '^horde-relay-join-[0-9a-f]{32}$' -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    Check (-not (Test-Path -LiteralPath $work)) "the suite's folder is gone"
}

Complete-HordeSuite -Success "a new phone that asks is answered at once and trusted only when the number it shows is typed on a device the founder holds; strangers, wrong numbers, second requests, expired requests, swapped, tampered, replayed and forged approvals trust nothing; every trusted device is told"
