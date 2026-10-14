# DO THE PHONE AND THE PC WRITE AND READ THE UNLOCKED SESSION'S BYTES THE SAME WAY?
#
# relay/Session.ps1 and relay/js/protocol.js are one wire in two languages: the vouch text, the hash a
# passkey signs at unlock, the bytes a session key signs, the sig member of an envelope, the opening
# body. This suite pins them three ways:
#   1. GOLDEN VALUES worked out by a third implementation (Python's hashlib, 2026-10-14) for one fixed
#      input: both languages must give exactly them, byte for byte;
#   2. the two languages against each other on the same input (test/fixtures/relay/session-wire.mjs);
#   3. a LIVE unlock made in JavaScript - a real non-extractable WebCrypto key and a software passkey's
#      ONE assertion - read by PowerShell's own envelope reader, its vouch verified by the same
#      WebAuthn verifier the PC uses, and its session signatures verified under the vouched key.
# And every refusal of the reader beside an accepted twin. What the PC TAKES (idle, window, revoke, end
# all) is test/test-relay-sessions.ps1's.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "relay\Envelope.ps1")
. (Join-Path $root "core\JsonText.ps1")
Set-StrictMode -Version Latest

$node = Get-Command -Name "node" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $node) {
    Write-Host "  [SKIP] node is not installed here, so there is no phone side to compare" -ForegroundColor Yellow
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Complete-HordeSuite -Success "skipped: no node" -PassCode 3
}

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$g = ConvertFrom-HordeRelayHex -Text "046b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c2964fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5"
$vec = [ordered]@{ sessionPublicKey = (ConvertTo-HordeRelayHex -Bytes $g); deviceKeyId = "00112233445566778899aabbccddeeff"; phoneKeyId = "ffeeddccbbaa99887766554433221100"
    horde = "work"; machine = "0123456789abcdef0123456789abcdef"; notBefore = [long]1760400000000; notAfter = [long]1760428800000; seq = 7
    ht = "HT"; rt = "RT"; ct = "CT"; value = ("ab" * 64); authenticatorData = ("01" * 37); clientDataJSON = (ConvertTo-HordeRelayHex -Bytes $utf8.GetBytes('{"type":"webauthn.get"}')); signature = ("30" * 8) }
$goldenVouchId = "698bea63dc44a344663ff1429aea1084"
$goldenText = '{"v":1,"kind":"horde-relay-session-vouch","sessionPublicKey":"BGsX0fLhLEJH-Lzm5WOkQPJ3A32BLeszoPShOUXYmMKWT-NC4v4af5uO5-tKfA-eFivOM1drMV7Oy7ZAaDe_UfU","deviceKeyId":"00112233445566778899aabbccddeeff","phoneKeyId":"ffeeddccbbaa99887766554433221100","horde":"work","machine":"0123456789abcdef0123456789abcdef","mailbox":"work/0123456789abcdef0123456789abcdef","notBefore":1760400000000,"notAfter":1760428800000,"seq":7,"vouchId":"698bea63dc44a344663ff1429aea1084"}'
$goldenChallenge = "15eeec83c2342644ff5196ce9c026360f604d9d2f36fc764111503680be20a0c"
$goldenSignedHash = "8fb319cfcfb566e14fb41fe3144fdb135c1da965f0d76b3c0f7335d0ee62d735"

# The machine side of the live part: an agreement key to seal to, and the relying party.
$agree = New-HordeRelayP256Key -Use "ecdh"
$agreePub = ConvertTo-HordeRelayP256Public -Key $agree
$rpId = "phone.example"; $origin = "https://phone.example"
$now = [long]1760400000000
$work = Join-Path $env:TEMP ("horde-session-wire-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $in = [ordered]@{ vectors = $vec; live = [ordered]@{ recipientPublic = (ConvertTo-HordeRelayHex -Bytes $agreePub); rpId = $rpId; origin = $origin; horde = "work"; machine = $vec.machine; phoneKeyId = $vec.phoneKeyId; now = $now } }
    [System.IO.File]::WriteAllText((Join-Path $work "in.json"), (ConvertTo-Json -InputObject $in -Compress -Depth 6), $utf8)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $node.Source
    $psi.Arguments = '"' + (Join-Path $here "fixtures\relay\session-wire.mjs") + '" "' + (Join-Path $work "in.json") + '" "' + (Join-Path $work "out.json") + '"'
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $null = $p.StandardOutput.ReadToEnd()
    if (-not $p.WaitForExit(60000)) { $p.Kill(); throw "the phone side did not answer in 60 s" }
    Check ($p.ExitCode -eq 0) ("the phone side ran" + $(if ($p.ExitCode -ne 0) { ": " + $errTask.Result } else { "" }))
    $js = ConvertFrom-HordeJson -Text ([System.IO.File]::ReadAllText((Join-Path $work "out.json"), $utf8))

    Write-Host ""
    Write-Host "--- the vouch: golden, PowerShell, JavaScript ---" -ForegroundColor Cyan
    $psText = ConvertTo-HordeRelaySessionVouchText -SessionPublicKey $g -DeviceKeyId $vec.deviceKeyId -PhoneKeyId $vec.phoneKeyId -Horde "work" -Machine $vec.machine -NotBefore $vec.notBefore -NotAfter $vec.notAfter -Seq 7
    Check ($psText -ceq $goldenText) "PowerShell writes the golden vouch text"
    Check ((Get-HordeTestMember $js "vouchText") -ceq $goldenText) "JavaScript writes the golden vouch text, byte for byte"
    Check ((Get-HordeTestMember $js "vouchId") -ceq $goldenVouchId -and (Get-HordeRelayKeyId -Public $g) -ceq $goldenVouchId) "both name the vouch by the key id of the session key"
    $psChallenge = ConvertTo-HordeRelayHex -Bytes (Get-HordeRelaySessionVouchChallenge -Text $goldenText)
    Check ($psChallenge -ceq $goldenChallenge) "PowerShell's unlock challenge is the golden SHA-256 of the domain and the vouch"
    Check ((Get-HordeTestMember $js "challenge") -ceq $goldenChallenge) "JavaScript's unlock challenge is the same 32 bytes"

    Write-Host ""
    Write-Host "--- what a session key signs, and the sig member ---" -ForegroundColor Cyan
    $signedPs = Get-HordeRelaySessionSigningInput -VouchId $goldenVouchId -Signed (Get-HordeRelaySigningInput -HeaderText "HT" -RecipientsText "RT" -CtText "CT")
    Check ((ConvertTo-HordeRelayHex -Bytes (Get-HordeRelaySha256 -Bytes $signedPs)) -ceq $goldenSignedHash) "PowerShell's session signing input hashes to the golden value"
    Check ((Get-HordeTestMember $js "signed") -ceq (ConvertTo-HordeRelayHex -Bytes $signedPs)) "JavaScript's session signing input is the same bytes"
    $valueB = ConvertTo-HordeRelayBase64Url -Bytes (ConvertFrom-HordeRelayHex -Text $vec.value)
    $bare = '{"alg":"session","vouchId":"' + $goldenVouchId + '","value":"' + $valueB + '"}'
    Check ((Get-HordeTestMember $js "sigBare") -ceq $bare) "JavaScript writes the bare session sig as PowerShell reads it"
    $psBare = ConvertTo-HordeRelaySigText -Sig ([pscustomobject]@{ alg = "session"; vouchId = $goldenVouchId; valueText = $valueB; vouchText = ""; authenticatorDataText = ""; clientDataJsonText = ""; signatureText = "" })
    Check ($psBare -ceq $bare) "PowerShell writes the same bare session sig"
    $b = { param($h) ConvertTo-HordeRelayBase64Url -Bytes (ConvertFrom-HordeRelayHex -Text $h) }
    $withVouch = '{"alg":"session","vouchId":"' + $goldenVouchId + '","value":"' + $valueB + '","vouch":"' + (ConvertTo-HordeRelayBase64Url -Bytes (Get-HordeRelayAsciiBytes -Text $goldenText)) +
        '","authenticatorData":"' + (& $b $vec.authenticatorData) + '","clientDataJSON":"' + (& $b $vec.clientDataJSON) + '","signature":"' + (& $b $vec.signature) + '"}'
    Check ((Get-HordeTestMember $js "sigWithVouch") -ceq $withVouch) "JavaScript writes the session sig carrying its vouch, members in their one order"
    Check ((Get-HordeTestMember $js "openBody") -ceq ('{"v":1,"vouchId":"' + $goldenVouchId + '"}')) "the opening body is {v:1, vouchId}"
    Check ((@(Get-HordeTestMember $js "refusals") -join ",") -ceq ((Get-HordeRelaySessionRefusals) -join ",")) "both languages list the same refusal codes, in the same order"
    Check ([long](Get-HordeTestMember $js "maxMs") -eq (Get-HordeRelaySessionLimits).maxWindowMs) "both hold the same 8-hour cap"

    Write-Host ""
    Write-Host "--- the writers refuse what the reader would ---" -ForegroundColor Cyan
    Check ("" + (Get-HordeTestMember $js "throws.atCap") -ceq "") "JavaScript writes a window of exactly 8 hours"
    Check ("" + (Get-HordeTestMember $js "throws.overCap") -cne "") "JavaScript refuses a window of 8 hours and 1 ms"
    Check ("" + (Get-HordeTestMember $js "throws.backwards") -cne "") "JavaScript refuses notAfter at notBefore"
    Check ("" + (Get-HordeTestMember $js "throws.badHorde") -cne "") "JavaScript refuses a horde that is not a name"
    Check ("" + (Get-HordeTestMember $js "throws.badKeyId") -cne "") "JavaScript refuses a key id that is not 32 hex"
    Check (Throws { ConvertTo-HordeRelaySessionVouchText -SessionPublicKey $g -DeviceKeyId $vec.deviceKeyId -PhoneKeyId $vec.phoneKeyId -Horde "work" -Machine $vec.machine -NotBefore 0 -NotAfter 28800001 -Seq 1 } "8 hours") "PowerShell refuses a window of 8 hours and 1 ms"
    Check (-not (Throws { $null = ConvertTo-HordeRelaySessionVouchText -SessionPublicKey $g -DeviceKeyId $vec.deviceKeyId -PhoneKeyId $vec.phoneKeyId -Horde "work" -Machine $vec.machine -NotBefore 0 -NotAfter 28800000 -Seq 1 })) "CONTROL: PowerShell writes a window of exactly 8 hours"

    Write-Host ""
    Write-Host "--- reading a vouch: each refusal beside its accepted twin ---" -ForegroundColor Cyan
    $ok = Read-HordeRelaySessionVouch -Text $goldenText
    Check ($ok.ok) "the golden vouch is read"
    $cases = @(
        @{ what = "a member out of order"; text = $goldenText.Replace('"deviceKeyId":"00112233445566778899aabbccddeeff","phoneKeyId":"ffeeddccbbaa99887766554433221100"', '"phoneKeyId":"ffeeddccbbaa99887766554433221100","deviceKeyId":"00112233445566778899aabbccddeeff"') },
        @{ what = "a space"; text = $goldenText.Replace('"v":1,', '"v": 1,') },
        @{ what = "a vouchId that is not the key's"; text = $goldenText.Replace($goldenVouchId, "698bea63dc44a344663ff1429aea1085") },
        @{ what = "a mailbox of another machine"; text = $goldenText.Replace('"mailbox":"work/0123456789abcdef', '"mailbox":"work/1123456789abcdef') },
        @{ what = "a window over 8 hours"; text = $goldenText.Replace('"notAfter":1760428800000', '"notAfter":1760428800001') },
        @{ what = "a notAfter before notBefore"; text = $goldenText.Replace('"notAfter":1760428800000', '"notAfter":1760399999999') },
        @{ what = "another kind"; text = $goldenText.Replace('"kind":"horde-relay-session-vouch"', '"kind":"horde-relay-session-vouce"') }
    )
    foreach ($c in $cases) {
        Check ($c.text -cne $goldenText) ("CONTROL: the copy with " + $c.what + " differs")
        $r = Read-HordeRelaySessionVouch -Text $c.text
        Check (-not $r.ok -and $r.reason.StartsWith("session-refused: ")) ("a vouch with " + $c.what + " is refused as session-refused (" + $r.reason + ")")
    }

    Write-Host ""
    Write-Host "--- a live unlock from JavaScript, read and verified by PowerShell ---" -ForegroundColor Cyan
    $live = Get-HordeTestMember $js "live"
    Check ([int](Get-HordeTestMember $live "prompts") -eq 1) "the unlock took exactly one passkey assertion"
    Check ((Get-HordeTestMember $live "extractable") -eq $false -and ("" + (Get-HordeTestMember $live "exportRefused")) -cne "") ("the session key is non-extractable: exportKey was refused (" + (Get-HordeTestMember $live "exportRefused") + ")")
    $devicePub = ConvertFrom-HordeRelayHex -Text (Get-HordeTestMember $live "devicePublic")
    $envs = @(Get-HordeTestMember $live "envelopes")
    $first = Read-HordeRelayEnvelope -Text $envs[0]
    Check ($first.ok) ("the first session envelope, carrying the vouch, is read: " + $first.reason)
    if ($first.ok) {
        $s = $first.value.sig
        Check ($s.alg -ceq "session" -and $null -ne $s.vouch -and $s.vouch.text -ceq (Get-HordeTestMember $live "vouchText")) "it carries the vouch text the phone made"
        Check ($first.value.header.from -ceq (Get-HordeTestMember $live "deviceKeyId") -and $s.vouch.deviceKeyId -ceq $first.value.header.from) "its from is the passkey's key id, as the vouch's deviceKeyId says"
        $wa = Test-HordeRelayWebAuthnAssertion -Public $devicePub -AuthenticatorData $s.authenticatorData -ClientDataJson $s.clientDataJson -Signature $s.signature `
            -Challenge (Get-HordeRelaySessionVouchChallenge -Text $s.vouch.text) -RpId $rpId -Origins @($origin) -RequireUserVerification $true
        Check ($wa.ok -and $wa.userVerified) ("the unlock assertion verifies with the PC's own WebAuthn verifier over PowerShell's own challenge, user verified: " + $wa.reason)
        $signed = Get-HordeRelaySessionSigningInput -VouchId $s.vouchId -Signed (Get-HordeRelaySigningInput -HeaderText $first.value.headerText -RecipientsText $first.value.recipientsText -CtText $first.value.ctText)
        Check (Test-HordeRelayEs256Signature -Public $s.vouch.sessionPublic -Bytes $signed -Signature $s.value -AllowHighS) "its session signature verifies under the vouched key"
        $other = Get-HordeRelaySessionSigningInput -VouchId "00000000000000000000000000000000" -Signed (Get-HordeRelaySigningInput -HeaderText $first.value.headerText -RecipientsText $first.value.recipientsText -CtText $first.value.ctText)
        Check (-not (Test-HordeRelayEs256Signature -Public $s.vouch.sessionPublic -Bytes $other -Signature $s.value -AllowHighS)) "and not over the same envelope under another vouchId: the vouchId is signed"
        $rebuilt = Complete-HordeRelayEnvelope -Draft ([pscustomobject]@{ headerText = $first.value.headerText; recipientsText = $first.value.recipientsText; ctText = $first.value.ctText }) `
            -SessionVouchId $s.vouchId -SessionValue $s.value -VouchText $s.vouch.text -AuthenticatorData $s.authenticatorData -ClientDataJson $s.clientDataJson -Signature $s.signature
        Check ($rebuilt -ceq $envs[0]) "PowerShell's writer rebuilds the phone's envelope text exactly"
    }
    $second = Read-HordeRelayEnvelope -Text $envs[1]
    Check ($second.ok -and $second.value.sig.alg -ceq "session" -and $null -eq $second.value.sig.vouch -and $second.value.sig.vouchId -ceq (Get-HordeTestMember $live "vouchId")) "a later envelope carries the vouchId alone"
    if ($second.ok -and $first.ok) {
        $signed2 = Get-HordeRelaySessionSigningInput -VouchId $second.value.sig.vouchId -Signed (Get-HordeRelaySigningInput -HeaderText $second.value.headerText -RecipientsText $second.value.recipientsText -CtText $second.value.ctText)
        Check (Test-HordeRelayEs256Signature -Public $first.value.sig.vouch.sessionPublic -Bytes $signed2 -Signature $second.value.sig.value -AllowHighS) "and is signed by the same session key, with no prompt"
    }

    Write-Host ""
    Write-Host "--- reading the sig member: each refusal beside its accepted twin ---" -ForegroundColor Cyan
    $t1 = $envs[1]
    $sigAt = $t1.IndexOf('"sig":')
    $head = $t1.Substring(0, $sigAt)
    $vid = $second.value.sig.vouchId; $val = $second.value.sig.valueText
    $variants = @(
        @{ what = "members reordered"; sig = '{"alg":"session","value":"' + $val + '","vouchId":"' + $vid + '"}' },
        @{ what = "an added member"; sig = '{"alg":"session","vouchId":"' + $vid + '","value":"' + $val + '","x":"y"}' },
        @{ what = "a vouchId in upper case"; sig = '{"alg":"session","vouchId":"' + $vid.ToUpperInvariant() + '","value":"' + $val + '"}' },
        @{ what = "a value of 63 bytes"; sig = '{"alg":"session","vouchId":"' + $vid + '","value":"' + (ConvertTo-HordeRelayBase64Url -Bytes (New-Object byte[] 63)) + '"}' },
        @{ what = "a vouch without its assertion"; sig = '{"alg":"session","vouchId":"' + $vid + '","value":"' + $val + '","vouch":"' + (ConvertTo-HordeRelayBase64Url -Bytes (Get-HordeRelayAsciiBytes -Text $goldenText)) + '"}' }
    )
    Check ((Read-HordeRelayEnvelope -Text ($head + '"sig":{"alg":"session","vouchId":"' + $vid + '","value":"' + $val + '"}}')).ok) "CONTROL: the bare sig rebuilt by hand is read"
    foreach ($v in $variants) {
        $r = Read-HordeRelayEnvelope -Text ($head + '"sig":' + $v.sig + '}')
        Check (-not $r.ok) ("a session sig with " + $v.what + " is refused (" + $r.reason + ")")
    }
    if ($first.ok) {
        # A vouch whose id is not the signature's: the golden vouch carried under the live vouchId.
        $s = $first.value.sig
        $swapped = Complete-HordeRelayEnvelope -Draft ([pscustomobject]@{ headerText = $first.value.headerText; recipientsText = $first.value.recipientsText; ctText = $first.value.ctText }) `
            -SessionVouchId $s.vouchId -SessionValue $s.value -VouchText $goldenText -AuthenticatorData $s.authenticatorData -ClientDataJson $s.clientDataJson -Signature $s.signature
        $r = Read-HordeRelayEnvelope -Text $swapped
        Check (-not $r.ok -and $r.reason -like "*not the one the signature names*") ("a sig carrying another session's vouch is refused (" + $r.reason + ")")
    }

    Write-Host ""
    Write-Host "--- a PC that takes no session yet refuses it by name ---" -ForegroundColor Cyan
    if ($second.ok) {
        $senders = @{}
        $senders[$second.value.header.from] = New-HordeRelaySender -Public $devicePub -Proof "webauthn" -RpId $rpId -Origins @($origin)
        $t = Test-HordeRelayEnvelope -Envelope $second.value -Senders $senders
        Check (-not $t.ok -and $t.reason.StartsWith("session-")) ("a session envelope to a sender with no session is refused by a session code (" + $t.reason + ")")
    }
} finally {
    $agree.Dispose()
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-HordeSuite -Success "the session wire is one dialect in both languages, and its reader refuses every other spelling"
