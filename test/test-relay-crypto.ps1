# DOES THE RELAY'S CRYPTOGRAPHY COMPUTE WHAT THE STANDARDS SAY, ON EVERY BACKEND THIS RUNTIME HAS?
#
# relay/Bytes.ps1, relay/Backend.ps1 (the AES-GCM seam), relay/P256.ps1 and relay/Hpke.ps1. The answers
# come from outside Horde: RFC 4648 for base64url, RFC 5869 test case 1 for HKDF, the GCM
# specification's test case 16 for AES-256-GCM, and the CFRG's official RFC 9180 vector for
# DHKEM(P-256)/HKDF-SHA256/AES-256-GCM (test/fixtures/relay/hpke-p256-sha256-aes256gcm.json, with its
# source and hash). A value Horde computed itself is never the expected answer here.
#
# RUN IT UNDER BOTH RUNTIMES (direction of 2026-10-09): `powershell.exe` (5.1: the cng backend only)
# and `pwsh` (7: dotnet, and cng too on Windows). Where a runtime has two backends, every vector runs on
# each, and every message sealed by one is opened by the other. test/test-relay-cross-runtime.ps1
# crosses the two runtimes.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "relay\Hpke.ps1")
Set-StrictMode -Version Latest

function Hex { param([AllowEmptyCollection()][byte[]]$Bytes) return (ConvertTo-HordeRelayHex -Bytes $Bytes) }
function Unhex { param([AllowEmptyString()][string]$Text) return ,(ConvertFrom-HordeRelayHex -Text $Text) }
Write-Host ("  runtime: PowerShell " + $PSVersionTable.PSVersion + " (" + $PSVersionTable.PSEdition + ")") -ForegroundColor DarkGray

Write-Host ""
Write-Host "--- base64url and hex: one spelling per value ---" -ForegroundColor Cyan
$all = [byte[]](0..255)
Check ((ConvertTo-HordeRelayBase64Url -Bytes ([byte[]]@(0xfb, 0xff, 0xbf))) -ceq "-_-_") "the URL alphabet: 0xfbffbf is -_-_ (RFC 4648 section 5)"
Check ((ConvertTo-HordeRelayBase64Url -Bytes ([byte[]]@(0x66, 0x6f))) -ceq "Zm8") "no padding: 'fo' is Zm8"
Check ((Hex (ConvertFrom-HordeRelayBase64Url -Text (ConvertTo-HordeRelayBase64Url -Bytes $all))) -ceq (Hex $all)) "all 256 byte values survive the round trip"
$emptyDecoded = ConvertFrom-HordeRelayBase64Url -Text ""
Check ($emptyDecoded -is [byte[]] -and $emptyDecoded.Length -eq 0) "the empty text is the empty value"
Check (Throws { ConvertFrom-HordeRelayBase64Url -Text "Zm8=" } "not base64url") "padding is refused"
Check (Throws { ConvertFrom-HordeRelayBase64Url -Text "+/+/" } "not base64url") "the standard alphabet's + and / are refused"
Check (Throws { ConvertFrom-HordeRelayBase64Url -Text "Zm 8" } "not base64url") "whitespace is refused"
Check (Throws { ConvertFrom-HordeRelayBase64Url -Text "Zm9vY" } "whole number of bytes") "a length that is no whole number of bytes is refused"
Check ((Hex (ConvertFrom-HordeRelayBase64Url -Text "AA")) -ceq "00") "CONTROL: AA is the byte 00"
Check (Throws { ConvertFrom-HordeRelayBase64Url -Text "AB" } "not canonical") "AB, a second spelling of the byte 00 (stray low bits), is refused"
Check ((Hex (Unhex "00ff10")) -ceq "00ff10") "hex round trip"
Check ((Test-HordeRelayBytesEqual -Left (Unhex "0102") -Right (Unhex "0102")) -and -not (Test-HordeRelayBytesEqual -Left (Unhex "0102") -Right (Unhex "010203")) -and -not (Test-HordeRelayBytesEqual -Left (Unhex "0102") -Right (Unhex "0103"))) "bytes are equal only with the same length and every byte the same"
Check (Throws { Unhex "0F" } "hex") "upper-case hex is refused"
Check (Throws { Unhex "abc" } "hex") "hex of half a byte is refused"

Write-Host ""
Write-Host "--- HKDF-SHA256: RFC 5869 test case 1 ---" -ForegroundColor Cyan
$ikm = Unhex "0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"
$prk = Invoke-HordeRelayHkdfExtract -Salt (Unhex "000102030405060708090a0b0c") -Ikm $ikm
Check ((Hex $prk) -ceq "077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5") "Extract gives the RFC's PRK"
$okm = Invoke-HordeRelayHkdfExpand -Prk $prk -Info (Unhex "f0f1f2f3f4f5f6f7f8f9") -Length 42
Check ((Hex $okm) -ceq "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865") "Expand gives the RFC's 42-byte OKM (two blocks, the second cut short)"
Check (Throws { Invoke-HordeRelayHkdfExpand -Prk $prk -Info (Unhex "") -Length 8161 } "8160") "more than 255 blocks is refused"

Write-Host ""
Write-Host "--- the AES-GCM seam: which backends, and each one correct ---" -ForegroundColor Cyan
$backends = @(Get-HordeRelayAeadBackends)
foreach ($b in $backends) { Write-Host ("    " + $b.name + ": " + $(if ($b.available) { "available" } else { "not available - " + $b.reason })) -ForegroundColor DarkGray }
$live = @($backends | Where-Object { $_.available } | ForEach-Object { $_.name })
Check ($backends.Count -eq 2 -and (@($backends | ForEach-Object { $_.name }) -join ",") -ceq "dotnet,cng") "both backends are probed, dotnet first"
Check ($live.Count -ge 1) ("at least one backend passed its known-answer test (" + ($live -join ",") + ")")
$hasAesGcm = ($null -ne ("System.Security.Cryptography.AesGcm" -as [type]))
Check (($live -ccontains "dotnet") -eq $hasAesGcm) "dotnet is available exactly when the runtime has an AesGcm class"
$onWindows = ("" + [System.Environment]::OSVersion.Platform) -ceq "Win32NT"
Check (($live -ccontains "cng") -eq $onWindows) "cng is available exactly on Windows, whatever the runtime"
Check ((Get-HordeRelayAeadBackend) -ceq $live[0]) "the backend in use is the first available"
Check (Throws { Select-HordeRelayAeadBackend -Name "rot13" } "not available") "a backend that does not exist cannot be selected"
if (-not $hasAesGcm) { Check (Throws { Select-HordeRelayAeadBackend -Name "dotnet" } "no System.Security.Cryptography.AesGcm") "on this runtime dotnet cannot be selected, and the reason says why" }
$k = Unhex "feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308"
$n = Unhex "cafebabefacedbaddecaf888"
$a = Unhex "feedfacedeadbeeffeedfacedeadbeefabaddad2"
$p = Unhex "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39"
$want = "522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f66276fc6ece0f4e1768cddf8853bb2d551b"
foreach ($be in $live) {
    $s = Protect-HordeRelayAesGcm -Key $k -Nonce $n -Aad $a -Plaintext $p -Backend $be
    Check ((Hex $s) -ceq $want) ("[" + $be + "] GCM test case 16 seals to the specification's ciphertext and tag")
    Check ((Hex (Unprotect-HordeRelayAesGcm -Key $k -Nonce $n -Aad $a -Sealed $s -Backend $be)) -ceq (Hex $p)) ("[" + $be + "] and opens back")
    $t = [byte[]]$s.Clone(); $t[0] = $t[0] -bxor 1
    Check ($null -eq (Unprotect-HordeRelayAesGcm -Key $k -Nonce $n -Aad $a -Sealed $t -Backend $be)) ("[" + $be + "] a flipped ciphertext bit does not open")
    $t = [byte[]]$s.Clone(); $t[$t.Length - 1] = $t[$t.Length - 1] -bxor 0x80
    Check ($null -eq (Unprotect-HordeRelayAesGcm -Key $k -Nonce $n -Aad $a -Sealed $t -Backend $be)) ("[" + $be + "] a flipped tag bit does not open")
    $a2 = [byte[]]$a.Clone(); $a2[0] = $a2[0] -bxor 1
    Check ($null -eq (Unprotect-HordeRelayAesGcm -Key $k -Nonce $n -Aad $a2 -Sealed $s -Backend $be)) ("[" + $be + "] other additional data does not open")
    $n2 = [byte[]]$n.Clone(); $n2[11] = $n2[11] -bxor 1
    Check ($null -eq (Unprotect-HordeRelayAesGcm -Key $k -Nonce $n2 -Aad $a -Sealed $s -Backend $be)) ("[" + $be + "] another nonce does not open")
    $k2 = [byte[]]$k.Clone(); $k2[31] = $k2[31] -bxor 1
    Check ($null -eq (Unprotect-HordeRelayAesGcm -Key $k2 -Nonce $n -Aad $a -Sealed $s -Backend $be)) ("[" + $be + "] another key does not open")
    Check ($null -eq (Unprotect-HordeRelayAesGcm -Key $k -Nonce $n -Aad $a -Sealed (Unhex "00112233") -Backend $be)) ("[" + $be + "] input shorter than a tag does not open")
    $e = Protect-HordeRelayAesGcm -Key $k -Nonce $n -Aad (Unhex "") -Plaintext (Unhex "") -Backend $be
    $eo = Unprotect-HordeRelayAesGcm -Key $k -Nonce $n -Aad (Unhex "") -Sealed $e -Backend $be
    Check ($e.Length -eq 16 -and $null -ne $eo -and $eo.Length -eq 0) ("[" + $be + "] an empty message with no additional data is a tag alone, and opens to empty")
    Check (Throws { Protect-HordeRelayAesGcm -Key (Unhex "00112233445566778899aabbccddeeff") -Nonce $n -Aad $a -Plaintext $p -Backend $be } "32 bytes") ("[" + $be + "] a 16-byte (AES-128) key is refused: the suite is AES-256")
    Check (Throws { Protect-HordeRelayAesGcm -Key $k -Nonce (Unhex "00112233445566778899aabbccddeeff") -Aad $a -Plaintext $p -Backend $be } "12 bytes") ("[" + $be + "] a 16-byte nonce is refused")
}
foreach ($from in $live) {
    foreach ($to in $live) {
        if ($from -ceq $to) { continue }
        $msg = Get-HordeRelayRandomBytes -Count 1000
        $key = Get-HordeRelayRandomBytes -Count 32
        $non = Get-HordeRelayRandomBytes -Count 12
        $x = Protect-HordeRelayAesGcm -Key $key -Nonce $non -Aad $a -Plaintext $msg -Backend $from
        Check ((Hex (Unprotect-HordeRelayAesGcm -Key $key -Nonce $non -Aad $a -Sealed $x -Backend $to)) -ceq (Hex $msg)) ("sealed by " + $from + ", opened by " + $to)
    }
}

Write-Host ""
Write-Host "--- P-256 keys and ECDH ---" -ForegroundColor Cyan
$alice = New-HordeRelayP256Key -Use "ecdh"
$bob = New-HordeRelayP256Key -Use "ecdh"
$alicePub = ConvertTo-HordeRelayP256Public -Key $alice
$bobPub = ConvertTo-HordeRelayP256Public -Key $bob
Check ($alicePub.Length -eq 65 -and $alicePub[0] -eq 4) "a public key is the 65-byte uncompressed point"
$back = ConvertFrom-HordeRelayP256Public -Bytes $alicePub -Use "ecdh"
Check ((Hex (ConvertTo-HordeRelayP256Public -Key $back)) -ceq (Hex $alicePub)) "a public key survives import and export"
$offCurve = [byte[]]$alicePub.Clone(); $offCurve[64] = $offCurve[64] -bxor 1
Check (Throws { ConvertFrom-HordeRelayP256Public -Bytes $offCurve -Use "ecdh" } "not a point on P-256") "a point off the curve is refused (the invalid-curve attack)"
$compressed = New-Object byte[] 33; $compressed[0] = 2; [System.Array]::Copy($alicePub, 1, $compressed, 1, 32)
Check (Throws { ConvertFrom-HordeRelayP256Public -Bytes $compressed -Use "ecdh" } "65 bytes") "a compressed point is refused"
$wrongPrefix = [byte[]]$alicePub.Clone(); $wrongPrefix[0] = 6
Check (Throws { ConvertFrom-HordeRelayP256Public -Bytes $wrongPrefix -Use "ecdh" } "65 bytes") "a hybrid-form prefix is refused"
$salt = Get-HordeRelayRandomBytes -Count 32
$pre = Get-HordeRelayAsciiBytes -Text "label"
$ab = Invoke-HordeRelayEcdhExtract -Private $alice -PeerPublic $bobPub -Salt $salt -Prefix $pre
$ba = Invoke-HordeRelayEcdhExtract -Private $bob -PeerPublic $alicePub -Salt $salt -Prefix $pre
Check ($ab.Length -eq 32 -and (Hex $ab) -ceq (Hex $ba)) "both sides of an ECDH extract agree"
$ab2 = Invoke-HordeRelayEcdhExtract -Private $alice -PeerPublic $bobPub -Salt $salt -Prefix (Get-HordeRelayAsciiBytes -Text "lab")
Check ((Hex $ab2) -cne (Hex $ab)) "the prefix is part of what is extracted"
$kid = Get-HordeRelayKeyId -Public $alicePub
Check ($kid -cmatch '\A[0-9a-f]{32}\z' -and $kid -ceq (Hex (Get-HordeRelaySha256 -Bytes $alicePub)).Substring(0, 32)) "a key id is the first 16 bytes of SHA-256 of the point, as hex"

Write-Host ""
Write-Host "--- ECDSA P-256 and DER ---" -ForegroundColor Cyan
$signer = New-HordeRelayP256Key -Use "ecdsa"
$signerPub = ConvertTo-HordeRelayP256Public -Key $signer
$data = Get-HordeRelayAsciiBytes -Text "the thing that is signed"
$sig = New-HordeRelayEs256Signature -Key $signer -Bytes $data
Check ($sig.Length -eq 64) "a signature is 64 bytes, r || s"
Check (Test-HordeRelayEs256Signature -Public $signerPub -Bytes $data -Signature $sig) "it verifies"
$d2 = [byte[]]$data.Clone(); $d2[0] = $d2[0] -bxor 1
Check (-not (Test-HordeRelayEs256Signature -Public $signerPub -Bytes $d2 -Signature $sig)) "not over other data"
$s2 = [byte[]]$sig.Clone(); $s2[10] = $s2[10] -bxor 1
Check (-not (Test-HordeRelayEs256Signature -Public $signerPub -Bytes $data -Signature $s2)) "not with a changed signature"
$other = ConvertTo-HordeRelayP256Public -Key (New-HordeRelayP256Key -Use "ecdsa")
Check (-not (Test-HordeRelayEs256Signature -Public $other -Bytes $data -Signature $sig)) "not under another key"
Check (-not (Test-HordeRelayEs256Signature -Public $signerPub -Bytes $data -Signature (Unhex "00"))) "a signature of the wrong length is false, not an error"
Check (-not (Test-HordeRelayEs256Signature -Public $offCurve -Bytes $data -Signature $sig)) "a bad public key is false, not an error"
# DER built by hand from known r and s, so the converter is checked against the encoding, not itself.
$r = ("00" * 31) + "7f"; $sv = "80" + ("11" * 31)
$derOk = Unhex ("3026" + "0201" + "7f" + "0221" + "00" + $sv)
Check ($derOk.Length -eq 40) "CONTROL: the hand-built DER is 40 bytes"
Check ((Hex (ConvertFrom-HordeRelayDerSignature -Der $derOk)) -ceq ($r + $sv)) "DER with a short r and a 33-byte s (sign byte) is r || s, each left-padded to 32 bytes"
Check (Throws { ConvertFrom-HordeRelayDerSignature -Der (Unhex ("3027" + "0202" + "007f" + "0221" + "00" + $sv)) } "needless leading zero") "a needless leading zero is refused"
Check (Throws { ConvertFrom-HordeRelayDerSignature -Der (Unhex ("3025" + "0201" + "7f" + "0220" + $sv)) } "negative") "a negative INTEGER is refused"
Check (Throws { ConvertFrom-HordeRelayDerSignature -Der (Unhex ("3028" + "0201" + "7f" + "0221" + "00" + $sv + "0000")) } "after its second INTEGER") "bytes after the sequence are refused"
Check (Throws { ConvertFrom-HordeRelayDerSignature -Der (Unhex ("308126" + "0201" + "7f" + "0221" + "00" + $sv)) } "length does not match") "a long-form length is refused"
Check (Throws { ConvertFrom-HordeRelayDerSignature -Der (Unhex ("3126" + "0201" + "7f" + "0221" + "00" + $sv)) } "not a DER SEQUENCE") "a SET in place of the SEQUENCE is refused"
Check (Throws { ConvertFrom-HordeRelayDerSignature -Der (Unhex ("3026" + "0201" + "00" + "0221" + "00" + $sv)) } "zero") "r of zero is refused"
Check (Throws { ConvertFrom-HordeRelayDerSignature -Der (Unhex ("3027" + "0222" + "01" + $sv + "11" + "0201" + "7f")) } "33 bytes long") "an INTEGER longer than 33 bytes is refused"
Check (Throws { ConvertFrom-HordeRelayDerSignature -Der (Unhex ("3026" + "0221" + "01" + $sv + "0201" + "7f")) } "larger than 32 bytes") "a 33-byte INTEGER that is not a sign byte and 32 bytes is refused"

Write-Host ""
Write-Host "--- HPKE: the official RFC 9180 vector, on every backend ---" -ForegroundColor Cyan
$vec = [System.IO.File]::ReadAllText((Join-Path $here "fixtures\relay\hpke-p256-sha256-aes256gcm.json")) | ConvertFrom-Json
Check ($vec.mode -eq 0 -and $vec.kem_id -eq 16 -and $vec.kdf_id -eq 1 -and $vec.aead_id -eq 2 -and @($vec.encryptions).Count -eq 4) "CONTROL: the fixture is the base-mode P-256 / HKDF-SHA256 / AES-256-GCM vector with four encryptions"
$info = Unhex $vec.info
foreach ($be in $live) {
    Select-HordeRelayAeadBackend -Name $be
    $eph = ConvertFrom-HordeRelayP256Private -D (Unhex $vec.skEm) -Public (Unhex $vec.pkEm) -Use "ecdh"
    $sender = New-HordeRelayHpkeSender -RecipientPublic (Unhex $vec.pkRm) -Info $info -Ephemeral $eph
    Check ((Hex $sender.enc) -ceq $vec.enc) ("[" + $be + "] enc is the vector's")
    Check ((Hex $sender.sharedSecret) -ceq $vec.shared_secret) ("[" + $be + "] shared_secret is the vector's")
    Check ((Hex $sender.keyScheduleContext) -ceq $vec.key_schedule_context) ("[" + $be + "] key_schedule_context is the vector's")
    Check ((Hex $sender.secret) -ceq $vec.secret) ("[" + $be + "] secret is the vector's")
    Check ((Hex $sender.key) -ceq $vec.key -and (Hex $sender.baseNonce) -ceq $vec.base_nonce) ("[" + $be + "] key and base_nonce are the vector's")
    $skR = ConvertFrom-HordeRelayP256Private -D (Unhex $vec.skRm) -Public (Unhex $vec.pkRm) -Use "ecdh"
    $receiver = New-HordeRelayHpkeReceiver -RecipientKey $skR -Enc (Unhex $vec.enc) -Info $info
    Check ((Hex $receiver.sharedSecret) -ceq $vec.shared_secret -and (Hex $receiver.key) -ceq $vec.key) ("[" + $be + "] the receiver derives the same secret and key")
    foreach ($e in @($vec.encryptions)) {
        $sender.seq = [long]$e.seq
        Check ((Hex (Get-HordeRelayHpkeNonce -Context $sender)) -ceq $e.nonce) ("[" + $be + "] seq " + $e.seq + ": the nonce is the vector's")
        $ct = Protect-HordeRelayHpkeMessage -Context $sender -Aad (Unhex $e.aad) -Plaintext (Unhex $e.pt)
        Check ((Hex $ct) -ceq $e.ct -and $sender.seq -eq ([long]$e.seq + 1)) ("[" + $be + "] seq " + $e.seq + ": seals to the vector's ciphertext, and the sequence moves on")
        $receiver.seq = [long]$e.seq
        $bad = Unhex $e.aad; $bad[0] = $bad[0] -bxor 1
        Check ($null -eq (Unprotect-HordeRelayHpkeMessage -Context $receiver -Aad $bad -Sealed (Unhex $e.ct)) -and $receiver.seq -eq [long]$e.seq) ("[" + $be + "] seq " + $e.seq + ": other AAD does not open, and the sequence does not move")
        Check ((Hex (Unprotect-HordeRelayHpkeMessage -Context $receiver -Aad (Unhex $e.aad) -Sealed (Unhex $e.ct))) -ceq $e.pt) ("[" + $be + "] seq " + $e.seq + ": opens to the vector's plaintext")
    }
}

Write-Host ""
Write-Host "--- HPKE single-shot: what must not open ---" -ForegroundColor Cyan
$rk = New-HordeRelayP256Key -Use "ecdh"
$rkPub = ConvertTo-HordeRelayP256Public -Key $rk
$aad = Get-HordeRelayAsciiBytes -Text "header"
$msg = [System.Text.Encoding]::UTF8.GetBytes("answer: yes, ship it " + [string][char]0x05e9)
foreach ($from in $live) {
    foreach ($to in $live) {
        Select-HordeRelayAeadBackend -Name $from
        $box = Protect-HordeRelayHpke -RecipientPublic $rkPub -Info $info -Aad $aad -Plaintext $msg
        Select-HordeRelayAeadBackend -Name $to
        Check ((Hex (Unprotect-HordeRelayHpke -RecipientKey $rk -Enc $box.enc -Info $info -Aad $aad -Sealed $box.sealed)) -ceq (Hex $msg)) ("sealed on " + $from + ", opened on " + $to + ", non-ASCII intact")
    }
}
$box = Protect-HordeRelayHpke -RecipientPublic $rkPub -Info $info -Aad $aad -Plaintext $msg
$box2 = Protect-HordeRelayHpke -RecipientPublic $rkPub -Info $info -Aad $aad -Plaintext $msg
Check ((Hex $box.enc) -cne (Hex $box2.enc) -and (Hex $box.sealed) -cne (Hex $box2.sealed)) "two seals of one message differ: a fresh ephemeral key each time"
Check ($null -eq (Unprotect-HordeRelayHpke -RecipientKey (New-HordeRelayP256Key -Use "ecdh") -Enc $box.enc -Info $info -Aad $aad -Sealed $box.sealed)) "the wrong recipient's key does not open"
Check ($null -eq (Unprotect-HordeRelayHpke -RecipientKey $rk -Enc $box.enc -Info (Get-HordeRelayAsciiBytes -Text "other info") -Aad $aad -Sealed $box.sealed)) "other info does not open"
Check ($null -eq (Unprotect-HordeRelayHpke -RecipientKey $rk -Enc $box.enc -Info $info -Aad (Get-HordeRelayAsciiBytes -Text "headex") -Sealed $box.sealed)) "other AAD does not open"
$encOther = ConvertTo-HordeRelayP256Public -Key (New-HordeRelayP256Key -Use "ecdh")
Check ($null -eq (Unprotect-HordeRelayHpke -RecipientKey $rk -Enc $encOther -Info $info -Aad $aad -Sealed $box.sealed)) "another enc (a valid point) does not open"
$encBad = [byte[]]$box.enc.Clone(); $encBad[64] = $encBad[64] -bxor 1
Check ($null -eq (Unprotect-HordeRelayHpke -RecipientKey $rk -Enc $encBad -Info $info -Aad $aad -Sealed $box.sealed)) "an enc off the curve does not open, and does not throw"
Check (Throws { Protect-HordeRelayHpke -RecipientPublic $offCurve -Info $info -Aad $aad -Plaintext $msg } "not a point on P-256") "sealing to a recipient key off the curve is refused"

Complete-HordeSuite -Success "base64url, HKDF, AES-256-GCM on every backend, P-256 ECDH and ECDSA, DER, and HPKE match their standards' vectors, and every tamper fails"
