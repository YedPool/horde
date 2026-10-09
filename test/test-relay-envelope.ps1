# DOES AN ENVELOPE OPEN EXACTLY WHEN IT IS THE SENDER'S, UNCHANGED, FOR THIS MACHINE, AND NEW?
#
# relay/Envelope.ps1 over the primitives the other relay suites prove. Three layers are tested apart:
#   - READ refuses every text that is not one canonical version-1 envelope within its caps;
#   - TEST refuses every signature that is not a trusted sender's over these exact bytes - ES256 for a
#     machine, a WebAuthn assertion for the founder's passkey (made here by a small authenticator
#     written in the suite, since WebCrypto-made assertions are test-relay-webauthn's);
#   - UNPROTECT refuses without a fresh journal verdict for this envelope, and refuses a body or a
#     wrapped key that was changed even when the sender re-signed the change - which is what shows the
#     header is bound to the ciphertext by the AEAD and not only by the signature.
# Run under powershell.exe and pwsh alike.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "relay\Envelope.ps1")
. (Join-Path $root "core\Tristate.ps1")
. (Join-Path $root "relay\Keys.ps1")
Set-StrictMode -Version Latest
Write-Host ("  runtime: PowerShell " + $PSVersionTable.PSVersion + " (" + $PSVersionTable.PSEdition + "), AES-GCM backend " + (Get-HordeRelayAeadBackend)) -ForegroundColor DarkGray

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$machineSign = New-HordeRelayP256Key -Use "ecdsa"
$machineSignPub = ConvertTo-HordeRelayP256Public -Key $machineSign
$machineId = Get-HordeRelayKeyId -Public $machineSignPub
$phone = New-HordeRelayP256Key -Use "ecdh"
$phonePub = ConvertTo-HordeRelayP256Public -Key $phone
$phoneId = Get-HordeRelayKeyId -Public $phonePub
$senders = @{ $machineId = (New-HordeRelaySender -Public $machineSignPub -Proof "es256") }
$keys = @{ $phoneId = $phone }

function Fresh {
    # The verdict the journal will give for an envelope it has not seen.
    param($Header)
    return (New-HordeKnown -Value ([pscustomobject]@{ key = (Get-HordeRelayReplayKey -Header $Header); fresh = $true }))
}
function Open-All {
    # Read, test and unprotect, as a receiver would; the first refusal's reason, or the body as text.
    param([string]$Text, [hashtable]$Senders = $senders, [hashtable]$Keys = $keys, $Replay = "fresh", [string]$Kind = "snapshot", [string]$Channel = "decisions")
    $r = Read-HordeRelayEnvelope -Text $Text
    if (-not $r.ok) { return [pscustomobject]@{ stage = "read"; reason = $r.reason; body = $null } }
    $t = Test-HordeRelayEnvelope -Envelope $r.value -Senders $Senders
    if (-not $t.ok) { return [pscustomobject]@{ stage = "test"; reason = $t.reason; body = $null } }
    $verdict = $Replay
    if ("$Replay" -ceq "fresh") { $verdict = Fresh -Header $t.value.header }
    $u = Unprotect-HordeRelayEnvelope -Envelope $r.value -Senders $Senders -RecipientKeys $Keys -Replay $verdict -Channel $Channel -Kind $Kind
    if (-not $u.ok) { return [pscustomobject]@{ stage = "unprotect"; reason = $u.reason; body = $null } }
    return [pscustomobject]@{ stage = "opened"; reason = ""; body = $utf8.GetString($u.value) }
}
function Seal {
    param([string]$Body = "merge PR 1605?", [object[]]$To = @(, $phonePub), [long]$Seq = 41)
    return (New-HordeRelayEnvelope -Kind "snapshot" -Channel "decisions" -Seq $Seq -Body ($utf8.GetBytes($Body)) -Recipients $To -Signer $machineSign)
}
function Resign {
    # Rebuild a read envelope with some parts replaced, and sign it again with the machine's real key:
    # the sender itself making the change, so only the AEAD can refuse it.
    param($Read, [string]$HeaderText = "", [string]$RecipientsText = "", [string]$CtText = "")
    $ht = $(if ($HeaderText) { $HeaderText } else { $Read.headerText })
    $rt = $(if ($RecipientsText) { $RecipientsText } else { $Read.recipientsText })
    $ct = $(if ($CtText) { $CtText } else { $Read.ctText })
    $draft = [pscustomobject]@{ headerText = $ht; recipientsText = $rt; ctText = $ct }
    $sig = New-HordeRelayEs256Signature -Key $machineSign -Bytes (Get-HordeRelaySigningInput -HeaderText $ht -RecipientsText $rt -CtText $ct)
    return (Complete-HordeRelayEnvelope -Draft $draft -Es256 $sig)
}
function Flip-B64 {
    # The same base64url text with one byte of its decoded value changed at Index.
    param([string]$Text, [int]$Index)
    $b = ConvertFrom-HordeRelayBase64Url -Text $Text
    $b[$Index] = $b[$Index] -bxor 1
    return (ConvertTo-HordeRelayBase64Url -Bytes $b)
}
function Replace-Once {
    # Text with Old replaced by New exactly once, or a throw: an edit that matched nothing would make
    # its test pass for the wrong reason (CONTRIBUTING 12, "assert the match count after every edit").
    param([string]$Text, [string]$Old, [string]$New)
    $at = $Text.IndexOf($Old, [System.StringComparison]::Ordinal)
    if ($at -lt 0 -or $Text.IndexOf($Old, $at + 1, [System.StringComparison]::Ordinal) -ge 0) { throw ("the edit '" + $Old + "' does not match exactly once") }
    return ($Text.Substring(0, $at) + $New + $Text.Substring($at + $Old.Length))
}

Write-Host ""
Write-Host "--- a machine's envelope to the phone, end to end ---" -ForegroundColor Cyan
$text = Seal
$o = Open-All -Text $text
Check ($o.stage -ceq "opened" -and $o.body -ceq "merge PR 1605?") ("it opens to its body (" + $o.stage + " " + $o.reason + ")")
Check ($text -cmatch '\A\{"header":\{"v":1,"kind":"snapshot","channel":"decisions","from":"[0-9a-f]{32}","to":\["[0-9a-f]{32}"\],"seq":41,"nonce":"[0-9a-f]{24}","ts":[0-9]+\},"recipients":\[\{"kid":"[0-9a-f]{32}","enc":"[A-Za-z0-9_-]{87}","key":"[A-Za-z0-9_-]{64}"\}\],"ct":"[A-Za-z0-9_-]+","sig":\{"alg":"ES256","value":"[A-Za-z0-9_-]{86}"\}\}\z') "the wire text is the canonical form, member by member"
$read = (Read-HordeRelayEnvelope -Text $text).value
Check ($read.header.from -ceq $machineId -and @($read.header.to)[0] -ceq $phoneId -and $read.header.seq -eq 41) "the header names the signer's key id, the recipient's, and the sequence"
$nowMs = [long][System.Math]::Floor(([System.DateTime]::UtcNow - (New-Object System.DateTime -ArgumentList 1970, 1, 1, 0, 0, 0, ([System.DateTimeKind]::Utc))).TotalMilliseconds)
Check ([System.Math]::Abs($nowMs - $read.header.ts) -lt 60000) "ts is now, in Unix milliseconds"
Check ((Read-HordeRelayEnvelope -Text (Seal)).value.header.nonce -cne $read.header.nonce) "two envelopes never share a nonce"
$uni = "answer: yes " + [string][char]0x05e9 + [string][char]0x05dc + [string][char]0x05d5 + [string][char]0x05dd
Check ((Open-All -Text (Seal -Body $uni)).body -ceq $uni) "a non-ASCII body arrives intact"
Check ((Open-All -Text (Seal -Body "")).body -ceq "") "an empty body arrives as empty"
$m2 = New-HordeRelayP256Key -Use "ecdh"; $m3 = New-HordeRelayP256Key -Use "ecdh"
$multi = Seal -To @($phonePub, (ConvertTo-HordeRelayP256Public -Key $m2), (ConvertTo-HordeRelayP256Public -Key $m3))
$ok3 = @($phone, $m2, $m3 | ForEach-Object { (Open-All -Text $multi -Keys @{ (Get-HordeRelayKeyId -Public (ConvertTo-HordeRelayP256Public -Key $_)) = $_ }).body })
Check (($ok3 -join "|") -ceq "merge PR 1605?|merge PR 1605?|merge PR 1605?") "with three recipients, each opens it with its own key"
$limits = Get-HordeRelayEnvelopeLimits
$bigBody = New-Object byte[] $limits.bodyBytes
$bigText = New-HordeRelayEnvelope -Kind "snapshot" -Channel "decisions" -Seq 1 -Body $bigBody -Recipients @(, $phonePub) -Signer $machineSign
Check ($bigText.Length -le $limits.textChars -and (Open-All -Text $bigText).stage -ceq "opened") ("a body of exactly the cap (" + $limits.bodyBytes + " bytes) is sealed and opened, and its text is within the text cap")
Check (Throws { New-HordeRelayEnvelope -Kind "snapshot" -Channel "decisions" -Seq 1 -Body (New-Object byte[] ($limits.bodyBytes + 1)) -Recipients @(, $phonePub) -Signer $machineSign } "split it") "a body one byte over the cap is refused at the sender"
Check (Throws { Seal -To @($phonePub, $phonePub) } "named twice") "a recipient named twice is refused at the sender"
Check (Throws { New-HordeRelayEnvelope -Kind "Snapshot" -Channel "decisions" -Seq 1 -Body $bigBody -Recipients @(, $phonePub) -Signer $machineSign } "kind") "a kind outside its alphabet is refused at the sender"
Check (Throws { Seal -Seq -1 } "sequence") "a negative sequence is refused at the sender"

Write-Host ""
Write-Host "--- the construction, pinned: what a second implementation (the PWA) must compute ---" -ForegroundColor Cyan
# Opened here by hand from the published construction, not through Unprotect-HordeRelayEnvelope, so a
# change to the domain strings or to what the AAD covers fails even when both ends change together.
$aadByHand = Get-HordeRelayAsciiBytes -Text ("horde-relay/envelope/v1 aad" + [string][char]10 + $read.headerText)
$cekByHand = Unprotect-HordeRelayHpke -RecipientKey $phone -Enc $read.recipients[0].enc -Info (Get-HordeRelayAsciiBytes -Text "horde-relay/envelope/v1 content-key") -Aad $aadByHand -Sealed $read.recipients[0].key
Check ($null -ne $cekByHand -and $cekByHand.Length -eq 32) "the content key is HPKE-sealed with info 'horde-relay/envelope/v1 content-key' and AAD 'horde-relay/envelope/v1 aad' LF header"
$bodyByHand = $(if ($null -ne $cekByHand) { Unprotect-HordeRelayAesGcm -Key $cekByHand -Nonce (ConvertFrom-HordeRelayHex -Text $read.header.nonce) -Aad $aadByHand -Sealed $read.ct } else { $null })
Check ($null -ne $bodyByHand -and $utf8.GetString($bodyByHand) -ceq "merge PR 1605?") "the body is AES-256-GCM under that key, with the header's nonce and the same AAD"
$signedByHand = Get-HordeRelayAsciiBytes -Text ("horde-relay/envelope/v1 signed" + [string][char]10 + $read.headerText + [string][char]10 + $read.recipientsText + [string][char]10 + $read.ctText)
Check (Test-HordeRelayEs256Signature -Public $machineSignPub -Bytes $signedByHand -Signature $read.sig.value) "the signature is ES256 over 'horde-relay/envelope/v1 signed' LF header LF recipients LF ct"

Write-Host ""
Write-Host "--- tamper: the signature catches every changed byte ---" -ForegroundColor Cyan
$hdrOther = Replace-Once -Text $text -Old '"kind":"snapshot"' -New '"kind":"answers"'
Check ((Open-All -Text $hdrOther).reason -ceq "the ES256 signature does not verify under the sender's key") "a changed header field"
$ctOther = Replace-Once -Text $text -Old ('"ct":"' + $read.ctText + '"') -New ('"ct":"' + (Flip-B64 -Text $read.ctText -Index 0) + '"')
Check ((Open-All -Text $ctOther).reason -ceq "the ES256 signature does not verify under the sender's key") "a changed ciphertext byte"
$tagOther = Replace-Once -Text $text -Old ('"ct":"' + $read.ctText + '"') -New ('"ct":"' + (Flip-B64 -Text $read.ctText -Index ($read.ct.Length - 1)) + '"')
Check ((Open-All -Text $tagOther).reason -ceq "the ES256 signature does not verify under the sender's key") "a changed tag byte"
$keyOther = Replace-Once -Text $text -Old $read.recipients[0].keyText -New (Flip-B64 -Text $read.recipients[0].keyText -Index 3)
Check ((Open-All -Text $keyOther).reason -ceq "the ES256 signature does not verify under the sender's key") "a changed wrapped key"
$sigOther = Replace-Once -Text $text -Old $read.sig.valueText -New (Flip-B64 -Text $read.sig.valueText -Index 5)
Check ((Open-All -Text $sigOther).reason -ceq "the ES256 signature does not verify under the sender's key") "a changed signature"

Write-Host ""
Write-Host "--- tamper the sender re-signs: the AEAD still refuses (header bound to ciphertext) ---" -ForegroundColor Cyan
$o = Open-All -Text (Resign -Read $read)
Check ($o.stage -ceq "opened") "CONTROL: re-signing the unchanged parts opens"
$o = Open-All -Text (Resign -Read $read -HeaderText (Replace-Once -Text $read.headerText -Old '"seq":41' -New '"seq":42'))
Check ($o.stage -ceq "unprotect" -and $o.reason.Contains("content key does not open")) ("a changed header (the AAD) opens nothing: " + $o.reason)
$o = Open-All -Text (Resign -Read $read -HeaderText (Replace-Once -Text $read.headerText -Old ('"nonce":"' + $read.header.nonce + '"') -New ('"nonce":"' + ("0" * 24) + '"')))
Check ($o.stage -ceq "unprotect" -and $o.reason.Contains("content key does not open")) "a changed nonce opens nothing"
$o = Open-All -Text (Resign -Read $read -CtText (Flip-B64 -Text $read.ctText -Index 0))
Check ($o.stage -ceq "unprotect" -and $o.reason.Contains("body does not open")) ("a changed ciphertext does not open: " + $o.reason)
$o = Open-All -Text (Resign -Read $read -CtText (Flip-B64 -Text $read.ctText -Index ($read.ct.Length - 1)))
Check ($o.stage -ceq "unprotect" -and $o.reason.Contains("body does not open")) "a changed tag does not open"
$o = Open-All -Text (Resign -Read $read -RecipientsText (Replace-Once -Text $read.recipientsText -Old $read.recipients[0].keyText -New (Flip-B64 -Text $read.recipients[0].keyText -Index 3)))
Check ($o.stage -ceq "unprotect" -and $o.reason.Contains("content key does not open")) "a changed wrapped key does not open"
$o = Open-All -Text (Resign -Read $read -RecipientsText (Replace-Once -Text $read.recipientsText -Old $read.recipients[0].encText -New (ConvertTo-HordeRelayBase64Url -Bytes (ConvertTo-HordeRelayP256Public -Key (New-HordeRelayP256Key -Use "ecdh")))))
Check ($o.stage -ceq "unprotect" -and $o.reason.Contains("content key does not open")) "another valid enc does not open"
$rm = (Read-HordeRelayEnvelope -Text $multi).value
$swapped = "[" + ('{"kid":"' + $rm.recipients[0].kid + '","enc":"' + $rm.recipients[1].encText + '","key":"' + $rm.recipients[1].keyText + '"}') + "," + ('{"kid":"' + $rm.recipients[1].kid + '","enc":"' + $rm.recipients[0].encText + '","key":"' + $rm.recipients[0].keyText + '"}') + "," + ($rm.recipientsText.Substring($rm.recipientsText.IndexOf('},{"kid":"' + $rm.recipients[2].kid) + 2))
$o = Open-All -Text (Resign -Read $rm -RecipientsText $swapped)
Check ($o.stage -ceq "unprotect" -and $o.reason.Contains("content key does not open")) ("one recipient's wrapped key moved to another's kid does not open for it (" + $o.reason + ")")

Write-Host ""
Write-Host "--- wrong recipient ---" -ForegroundColor Cyan
$stranger = New-HordeRelayP256Key -Use "ecdh"
$o = Open-All -Text $text -Keys @{ (Get-HordeRelayKeyId -Public (ConvertTo-HordeRelayP256Public -Key $stranger)) = $stranger }
Check ($o.stage -ceq "unprotect" -and $o.reason.Contains("not addressed to any key of this machine")) "a machine the envelope is not for cannot open it"
$o = Open-All -Text $text -Keys @{ $phoneId = $stranger }
Check ($o.stage -ceq "unprotect" -and $o.reason.Contains("is another key")) "a wrong key filed under the right key id is caught before it is used"

Write-Host ""
Write-Host "--- the sender must be trusted, and prove itself its own way ---" -ForegroundColor Cyan
$o = Open-All -Text $text -Senders @{}
Check ($o.stage -ceq "test" -and $o.reason.Contains("not one this machine trusts")) "an unknown sender is refused"
$imposter = ConvertTo-HordeRelayP256Public -Key (New-HordeRelayP256Key -Use "ecdsa")
$o = Open-All -Text $text -Senders @{ $machineId = (New-HordeRelaySender -Public $imposter -Proof "es256") }
Check ($o.stage -ceq "test" -and $o.reason.Contains("holds another key")) "a trusted-sender table filed under the wrong key id is caught"
$o = Open-All -Text $text -Senders @{ $machineId = (New-HordeRelaySender -Public $machineSignPub -Proof "webauthn" -RpId "relay.example.test" -Origins @("https://relay.example.test")) }
Check ($o.stage -ceq "test" -and $o.reason.Contains("signs with a passkey")) "a passkey sender cannot be satisfied by a plain ES256 signature"

Write-Host ""
Write-Host "--- the founder's answer, signed by a passkey ---" -ForegroundColor Cyan
# A minimal authenticator: what a phone's passkey does for navigator.credentials.get().
$passkey = New-HordeRelayP256Key -Use "ecdsa"
$passkeyPub = ConvertTo-HordeRelayP256Public -Key $passkey
$passkeyId = Get-HordeRelayKeyId -Public $passkeyPub
$machineAgree = New-HordeRelayP256Key -Use "ecdh"
$machineAgreePub = ConvertTo-HordeRelayP256Public -Key $machineAgree
$machineKeys = @{ (Get-HordeRelayKeyId -Public $machineAgreePub) = $machineAgree }
$rp = "relay.example.test"; $origin = "https://relay.example.test"
$founder = @{ $passkeyId = (New-HordeRelaySender -Public $passkeyPub -Proof "webauthn" -RpId $rp -Origins @($origin)) }
function ConvertTo-Der {
    param([byte[]]$P1363)
    $parts = @(0, 32 | ForEach-Object {
        $v = New-Object byte[] 32; [System.Array]::Copy($P1363, $_, $v, 0, 32)
        $i = 0; while ($i -lt 31 -and $v[$i] -eq 0) { $i++ }
        $t = New-Object byte[] (32 - $i); [System.Array]::Copy($v, $i, $t, 0, $t.Length)
        if ($t[0] -band 0x80) { $t = Join-HordeRelayBytes -Parts @([byte[]]@(0), $t) }
        , (Join-HordeRelayBytes -Parts @([byte[]]@(2, $t.Length), $t))
    })
    return ,(Join-HordeRelayBytes -Parts @([byte[]]@(0x30, ($parts[0].Length + $parts[1].Length)), $parts[0], $parts[1]))
}
function Answer {
    # A founder's answer envelope to the machine, signed by the passkey over the draft's challenge.
    param([string]$Body = "yes, ship it", [byte[]]$Challenge = $null, [string]$Origin = $origin, [int]$Flags = 5)
    $draft = New-HordeRelayEnvelopeDraft -Kind "answer" -Channel "decisions" -From $passkeyId -Seq 7 -Body ($utf8.GetBytes($Body)) -Recipients @(, $machineAgreePub)
    $ch = $(if ($null -ne $Challenge) { $Challenge } else { $draft.challenge })
    $ad = Join-HordeRelayBytes -Parts @((Get-HordeRelaySha256 -Bytes ($utf8.GetBytes($rp))), [byte[]]@($Flags, 0, 0, 0, 0))
    $cdj = $utf8.GetBytes('{"type":"webauthn.get","challenge":"' + (ConvertTo-HordeRelayBase64Url -Bytes $ch) + '","origin":"' + $Origin + '","crossOrigin":false}')
    $p1363 = New-HordeRelayEs256Signature -Key $passkey -Bytes (Join-HordeRelayBytes -Parts @($ad, (Get-HordeRelaySha256 -Bytes $cdj)))
    return [pscustomobject]@{ draft = $draft; text = (Complete-HordeRelayEnvelope -Draft $draft -AuthenticatorData $ad -ClientDataJson $cdj -Signature (ConvertTo-Der -P1363 $p1363)) }
}
$a = Answer
$o = Open-All -Text $a.text -Senders $founder -Keys $machineKeys -Kind "answer"
Check ($o.stage -ceq "opened" -and $o.body -ceq "yes, ship it") ("a passkey-signed answer opens on the machine (" + $o.stage + " " + $o.reason + ")")
$t = Test-HordeRelayEnvelope -Envelope (Read-HordeRelayEnvelope -Text $a.text).value -Senders $founder
Check ($t.value.proof -ceq "webauthn" -and $t.value.userVerified -eq $true -and $t.value.signCount -eq 0) "it reports the passkey proof, user verification and the counter"
$other = Answer -Body "no"
$stolen = Answer -Challenge $other.draft.challenge
$o = Open-All -Text $stolen.text -Senders $founder -Keys $machineKeys
Check ($o.stage -ceq "test" -and $o.reason.Contains("challenge")) "an assertion made for another envelope does not sign this one"
$o = Open-All -Text (Answer -Origin "https://relay.example.test.evil.test").text -Senders $founder -Keys $machineKeys
Check ($o.stage -ceq "test" -and $o.reason.Contains("origin")) "an assertion from another origin is refused"
$o = Open-All -Text (Answer -Flags 1).text -Senders $founder -Keys $machineKeys
Check ($o.stage -ceq "test" -and $o.reason.Contains("user verification")) "an answer without user verification is refused"
$o = Open-All -Text $a.text -Senders @{ $passkeyId = (New-HordeRelaySender -Public $passkeyPub -Proof "es256") } -Keys $machineKeys
Check ($o.stage -ceq "test" -and $o.reason.Contains("signs ES256")) "a passkey assertion does not satisfy a machine sender"

Write-Host ""
Write-Host "--- the replay hook: no fresh verdict for this envelope, no body ---" -ForegroundColor Cyan
$rv = (Read-HordeRelayEnvelope -Text $text).value
$v = (Test-HordeRelayEnvelope -Envelope $rv -Senders $senders).value
$rk = Get-HordeRelayReplayKey -Header $v.header
Check ($rk -ceq ($machineId + "/decisions/41/" + $v.header.nonce)) "the replay key is from/channel/seq/nonce"
$cases = @(
    @{ what = "no verdict at all"; verdict = $null; want = "none was given" },
    @{ what = "an absent verdict"; verdict = (New-HordeAbsent -Note "journal empty"); want = "it is absent" },
    @{ what = "an unknown verdict (the journal could not be read)"; verdict = (New-HordeUnknown -Reason "journal folder locked"); want = "it is unknown: journal folder locked" },
    @{ what = "a verdict that it was seen"; verdict = (New-HordeKnown -Value ([pscustomobject]@{ key = $rk; fresh = $false })); want = "a replay is refused" },
    @{ what = "a fresh verdict about another envelope"; verdict = (New-HordeKnown -Value ([pscustomobject]@{ key = ($machineId + "/decisions/40/" + $v.header.nonce); fresh = $true })); want = "about another envelope" },
    @{ what = "a fresh verdict with no key"; verdict = (New-HordeKnown -Value ([pscustomobject]@{ fresh = $true })); want = "about another envelope" },
    @{ what = "fresh given as the number 1"; verdict = (New-HordeKnown -Value ([pscustomobject]@{ key = $rk; fresh = 1 })); want = "not a fresh verdict" },
    @{ what = "fresh given as the text true"; verdict = (New-HordeKnown -Value ([pscustomobject]@{ key = $rk; fresh = "true" })); want = "not a fresh verdict" },
    @{ what = "fresh given as the text True"; verdict = (New-HordeKnown -Value ([pscustomobject]@{ key = $rk; fresh = "True" })); want = "not a fresh verdict" }
)
foreach ($c in $cases) {
    $u = Unprotect-HordeRelayEnvelope -Envelope $rv -Senders $senders -RecipientKeys $keys -Replay $c.verdict -Channel "decisions" -Kind "snapshot"
    Check (-not $u.ok -and $null -eq $u.value -and $u.reason.Contains($c.want)) ($c.what + ": not opened (" + $u.reason + ")")
}
$u = Unprotect-HordeRelayEnvelope -Envelope $rv -Senders $senders -RecipientKeys $keys -Replay (Fresh -Header $v.header) -Channel "decisions" -Kind "snapshot"
Check ($u.ok -and $utf8.GetString($u.value) -ceq "merge PR 1605?") "CONTROL: the fresh verdict for this envelope opens it"

Write-Host ""
Write-Host "--- Unprotect checks the signature itself: nothing reaches the body unverified ---" -ForegroundColor Cyan
# Review of 3bf4657, finding 1: Unprotect took a verified result as plain data, so a hand-made one
# wrapping an untrusted signer's envelope, with a fresh verdict, opened.
$evil = New-HordeRelayP256Key -Use "ecdsa"
$forged = (Read-HordeRelayEnvelope -Text (New-HordeRelayEnvelope -Kind "snapshot" -Channel "decisions" -Seq 6 -Body ($utf8.GetBytes("forged")) -Recipients @(, $phonePub) -Signer $evil)).value
$u = Unprotect-HordeRelayEnvelope -Envelope $forged -Senders $senders -RecipientKeys $keys -Replay (Fresh -Header $forged.header) -Channel "decisions" -Kind "snapshot"
Check (-not $u.ok -and $null -eq $u.value -and $u.reason.Contains("not one this machine trusts")) ("an untrusted signer's envelope with a fresh verdict is not opened (" + $u.reason + ")")
$swappedSig = (Read-HordeRelayEnvelope -Text (Replace-Once -Text $text -Old $read.sig.valueText -New (Flip-B64 -Text $read.sig.valueText -Index 5))).value
$u = Unprotect-HordeRelayEnvelope -Envelope $swappedSig -Senders $senders -RecipientKeys $keys -Replay (Fresh -Header $swappedSig.header) -Channel "decisions" -Kind "snapshot"
Check (-not $u.ok -and $u.reason.Contains("does not verify")) "a trusted sender's envelope with a broken signature is not opened"
Check (Throws { Unprotect-HordeRelayEnvelope -Envelope $rv -RecipientKeys $keys -Replay (Fresh -Header $rv.header) -Channel "decisions" -Kind "snapshot" }) "the trusted senders cannot be left out"
# The signature covers the texts; decryption and the replay key use the decoded parts. An envelope
# object whose decoded parts were changed after Read must not pass as the signed one.
function Copy-Read { param($R) return [pscustomobject]@{ header = $R.header; headerText = $R.headerText; recipients = $R.recipients; recipientsText = $R.recipientsText; ct = $R.ct; ctText = $R.ctText; sig = $R.sig } }
$h2 = [pscustomobject]@{ v = 1; kind = $rv.header.kind; channel = $rv.header.channel; from = $rv.header.from; to = $rv.header.to; seq = [long]99; nonce = $rv.header.nonce; ts = $rv.header.ts }
$c1 = Copy-Read $rv; $c1.header = $h2
$t1 = Test-HordeRelayEnvelope -Envelope $c1 -Senders $senders
Check (-not $t1.ok -and $t1.reason.Contains("do not match its signed text")) "a header object changed after Read (seq 41 to 99) does not verify as the signed one"
$c2 = Copy-Read $rv; $c2.ct = (Read-HordeRelayEnvelope -Text (Seal -Body "other")).value.ct
Check (-not (Test-HordeRelayEnvelope -Envelope $c2 -Senders $senders).ok) "nor does a ciphertext swapped after Read"
$c3 = Copy-Read $rv; $other = (Read-HordeRelayEnvelope -Text (Seal)).value; $c3.recipients = $other.recipients
Check (-not (Test-HordeRelayEnvelope -Envelope $c3 -Senders $senders).ok) "nor do recipients swapped after Read"
Check ((Test-HordeRelayEnvelope -Envelope (Copy-Read $rv) -Senders $senders).ok) "CONTROL: an unchanged copy verifies"

Write-Host ""
Write-Host "--- Unprotect opens only the channel and kind the caller expects ---" -ForegroundColor Cyan
$u = Unprotect-HordeRelayEnvelope -Envelope $rv -Senders $senders -RecipientKeys $keys -Replay (Fresh -Header $rv.header) -Channel "chat" -Kind "snapshot"
Check (-not $u.ok -and $u.reason.Contains("channel")) ("an envelope of another channel is not opened (" + $u.reason + ")")
$u = Unprotect-HordeRelayEnvelope -Envelope $rv -Senders $senders -RecipientKeys $keys -Replay (Fresh -Header $rv.header) -Channel "decisions" -Kind "answer"
Check (-not $u.ok -and $u.reason.Contains("kind")) ("an envelope of another kind is not opened (" + $u.reason + ")")
Check (Throws { Unprotect-HordeRelayEnvelope -Envelope $rv -Senders $senders -RecipientKeys $keys -Replay (Fresh -Header $rv.header) -Kind "snapshot" }) "the expected channel cannot be left out"
Check (Throws { Unprotect-HordeRelayEnvelope -Envelope $rv -Senders $senders -RecipientKeys $keys -Replay (Fresh -Header $rv.header) -Channel "decisions" }) "the expected kind cannot be left out"

Write-Host ""
Write-Host "--- strict reading: one spelling, version 1, within the caps ---" -ForegroundColor Cyan
function Refused {
    param([string]$Text, [string]$Want, [string]$What)
    $r = Read-HordeRelayEnvelope -Text $Text
    Check (-not $r.ok -and $r.reason.Contains($Want)) ($What + " (" + $r.reason + ")")
}
Refused -Text (Replace-Once -Text $text -Old '"v":1' -New '"v":2') -Want "unknown envelope version 2" -What "version 2 is refused by name"
Refused -Text (Replace-Once -Text $text -Old '"v":1' -New '"v":0') -Want "unknown envelope version 0" -What "version 0 is refused by name"
Refused -Text (Replace-Once -Text $text -Old '"v":1' -New '"v":"1"') -Want "not a whole number" -What "a version written as text is refused"
Refused -Text (Replace-Once -Text $text -Old '"v":1' -New '"v":1.0') -Want "not a whole number" -What "a version written 1.0 is refused"
Refused -Text (Replace-Once -Text $text -Old '"v":1,' -New '') -Want "no version" -What "a header with no version is refused"
Refused -Text (Replace-Once -Text $text -Old '{"header":' -New '{ "header":') -Want "canonical" -What "a space is refused"
Refused -Text (Replace-Once -Text $text -Old '"kind":"snapshot","channel":"decisions"' -New '"channel":"decisions","kind":"snapshot"') -Want "canonical" -What "members in another order are refused"
Refused -Text (Replace-Once -Text $text -Old '"kind":"snapshot"' -New '"kind":"answers","kind":"snapshot"') -Want "canonical" -What "a repeated member (the parser keeps the last) is refused"
Refused -Text (Replace-Once -Text $text -Old '"kind":"snapshot"' -New ('"kind":"snap' + [string][char]92 + 'u0073hot"')) -Want "canonical" -What "an escaped spelling of the same text (s as a JSON unicode escape) is refused"
Refused -Text (Replace-Once -Text $text -Old '"seq":41' -New '"seq":4.1e1') -Want "seq" -What "a sequence number spelled with an exponent is refused"
Refused -Text (Replace-Once -Text $text -Old '"seq":41' -New '"seq":-1') -Want "relay-envelope.v1" -What "a negative sequence number is refused by the schema"
Refused -Text (Replace-Once -Text $text -Old '"seq":41' -New '"seq":9007199254740992') -Want "seq" -What "a sequence number past 2^53-1 is refused"
Refused -Text (Replace-Once -Text $text -Old ('"ts":' + $read.header.ts) -New '"ts":"2026-10-09T12:00:00Z"') -Want "relay-envelope.v1" -What "a time written as a date string is refused"
Refused -Text (Replace-Once -Text $text -Old '"kind":"snapshot"' -New '"kind":"Snapshot"') -Want "relay-envelope.v1" -What "a kind outside its alphabet is refused"
Refused -Text (Replace-Once -Text $text -Old '{"header":' -New '{"extra":1,"header":') -Want "relay-envelope.v1" -What "an unknown member at the top is refused"
Refused -Text (Replace-Once -Text $text -Old '"v":1,' -New '"v":1,"mailbox":"x",') -Want "relay-envelope.v1" -What "an unknown header member is refused"
Refused -Text (Replace-Once -Text $text -Old '"alg":"ES256"' -New '"alg":"ES384"') -Want "relay-envelope.v1" -What "an algorithm other than the two is refused"
Refused -Text (Replace-Once -Text $text -Old ('"value":"' + $read.sig.valueText + '"') -New ('"value":"' + $read.sig.valueText + '","signature":"AAAA"')) -Want "exactly alg and value" -What "an ES256 signature carrying WebAuthn members is refused"
Refused -Text (Replace-Once -Text $text -Old ('"ct":"' + $read.ctText + '"') -New ('"ct":"' + $read.ctText + '="')) -Want "relay-envelope.v1" -What "base64 padding is refused"
$lastChar = $read.sig.valueText.Substring($read.sig.valueText.Length - 1)
$alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
$strayBits = $alphabet[($alphabet.IndexOf($lastChar) -bor 1)]
if ($strayBits -ceq $lastChar) { $strayBits = $alphabet[($alphabet.IndexOf($lastChar) -bor 2)] }
Refused -Text (Replace-Once -Text $text -Old $read.sig.valueText -New ($read.sig.valueText.Substring(0, $read.sig.valueText.Length - 1) + $strayBits)) -Want "not canonical base64url" -What "a second base64url spelling of the signature (stray bits) is refused"
Refused -Text (Replace-Once -Text $text -Old ('"to":["' + $phoneId + '"]') -New ('"to":["' + $phoneId + '","' + $phoneId + '"]')) -Want "twice" -What "a recipient named twice in the header is refused"
Refused -Text (Replace-Once -Text $text -Old ('"to":["' + $phoneId + '"]') -New ('"to":["' + $phoneId + '","' + $machineId + '"]')) -Want "do not match the header" -What "a header naming more recipients than are wrapped is refused"
Refused -Text (Replace-Once -Text $text -Old ('"to":["' + $phoneId + '"]') -New '"to":[]') -Want "1 to 8" -What "no recipients is refused"
$nine = @(1..9 | ForEach-Object { ConvertTo-HordeRelayP256Public -Key (New-HordeRelayP256Key -Use "ecdh") })
Check (Throws { Seal -To $nine } "1 to 8") "nine recipients are refused at the sender"
Refused -Text (Replace-Once -Text $multi -Old ('"kid":"' + $rm.recipients[0].kid + '"') -New ('"kid":"' + $rm.recipients[1].kid + '"')) -Want "in order" -What "recipients out of the header's order are refused"
Refused -Text (Replace-Once -Text $text -Old $read.recipients[0].encText -New (ConvertTo-HordeRelayBase64Url -Bytes (New-Object byte[] 64))) -Want "65" -What "an enc of 64 bytes is refused"
Refused -Text (Replace-Once -Text $text -Old $read.recipients[0].keyText -New (ConvertTo-HordeRelayBase64Url -Bytes (New-Object byte[] 47))) -Want "48" -What "a sealed key of 47 bytes is refused"
Refused -Text (Replace-Once -Text $text -Old ('"ct":"' + $read.ctText + '"') -New ('"ct":"' + (ConvertTo-HordeRelayBase64Url -Bytes (New-Object byte[] 15)) + '"')) -Want "ciphertext" -What "a ciphertext shorter than a tag is refused"
Refused -Text (Replace-Once -Text $text -Old $read.sig.valueText -New (ConvertTo-HordeRelayBase64Url -Bytes (New-Object byte[] 63))) -Want "64" -What "an ES256 signature of 63 bytes is refused"
Refused -Text (Replace-Once -Text $text -Old '"kind":"snapshot"' -New ('"kind":"snaps' + [string][char]0x00e9 + 'ot"')) -Want "not printable ASCII" -What "non-ASCII text is refused before it is parsed"
Refused -Text ($text.Substring(0, 40)) -Want "not JSON" -What "a cut-off envelope is refused"
Refused -Text "[1,2]" -Want "not a JSON object" -What "an array is refused"
Refused -Text "" -Want "empty" -What "an empty text is refused"
Refused -Text ('{"header":{"v":1}' + (" " * $limits.textChars) + '}') -Want "larger than" -What "a text over the cap is refused before it is parsed"

Write-Host ""
Write-Host "--- non-exportable machine keys, end to end ---" -ForegroundColor Cyan
if ((Get-HordeRelayKeyStore).state -ceq "known") {
    $tag = [guid]::NewGuid().ToString("N").Substring(0, 12)
    $sn = "horde-relay-test-" + $tag + "-es"; $an = "horde-relay-test-" + $tag + "-ea"
    try {
        [void](New-HordeRelayKey -Name $sn -Use "sign")
        [void](New-HordeRelayKey -Name $an -Use "agree")
        $sk = (Get-HordeRelayKey -Name $sn -Use "sign").value
        $ak = (Get-HordeRelayKey -Name $an -Use "agree").value
        $env1 = New-HordeRelayEnvelope -Kind "ack" -Channel "decisions" -Seq 3 -Body ($utf8.GetBytes("from a key that cannot leave")) -Recipients @(, $ak.publicKey) -Signer $sk.key
        $o = Open-All -Text $env1 -Senders @{ $sk.keyId = (New-HordeRelaySender -Public $sk.publicKey -Proof "es256") } -Keys @{ $ak.keyId = $ak.key } -Kind "ack"
        Check ($o.stage -ceq "opened" -and $o.body -ceq "from a key that cannot leave") ("signed by a non-exportable " + $sk.provider + " key and opened by a non-exportable " + $ak.provider + " key")
    } finally {
        [void](Remove-HordeRelayKey -Name $sn); [void](Remove-HordeRelayKey -Name $an)
    }
} else {
    Write-Host "    no non-exportable key store here; covered by test-relay-keys" -ForegroundColor DarkGray
}

Complete-HordeSuite -Success "an envelope opens exactly when it is canonical version 1, signed by a trusted sender, addressed here, unchanged, and fresh by the journal's verdict"
