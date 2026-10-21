# relay/Envelope.ps1 - the relay envelope, version 1: build, read, verify, open.
#
# WHAT ONE ENVELOPE IS (schema/relay-envelope.v1.json has the shape):
#   header      { v, kind, channel, from, to[], seq, nonce, ts } - who, to whom, which stream, which
#               message; never encrypted, so the relay can route and the journal can order.
#   body        AES-256-GCM under a fresh 32-byte content key, nonce = header.nonce,
#               additional data = the canonical header. A changed header does not open.
#   recipients  the content key, HPKE-sealed (relay/Hpke.ps1) to each recipient's agree key, with the
#               canonical header as additional data too.
#   sig         the sender signs the header, the recipients and the ciphertext: ES256 with a machine's
#               sign key (relay/Keys.ps1), or a WebAuthn assertion with the founder's passkey, whose
#               challenge is SHA-256 of the same bytes (relay/WebAuthn.ps1), or - alg "session" - ES256 by
#               a session key a passkey vouched for at unlock (relay/Session.ps1 has its wire, and
#               relay/Sessions.ps1 what the machine takes).
# HPKE base mode authenticates nobody, so the signature is what says who sent it; the AEAD's
# additional data is what ties the header to the body and to every wrapped key.
#
# ONE SPELLING PER SIGNED CONTENT. The wire text is the canonical form written here - members in schema
# order, no whitespace, strings from restricted ASCII alphabets, numbers as plain integers - and
# Read-HordeRelayEnvelope rebuilds that text from what it parsed and refuses the envelope unless the two
# are identical. That one rule refuses repeated members (ConvertFrom-Json keeps the last silently),
# members in another order, unknown members, escapes, whitespace and number spellings like 1.0 or 1e0,
# so two parties can never read the header, recipients and ciphertext two ways. The PWA (a later pull
# request) writes the same text; the strings below that build it are the whole specification.
#
# THE SIGNATURE IS NOT PART OF AN ENVELOPE'S IDENTITY (review of 3bf4657, finding 3). An ES256
# signature has one spelling (low-S, relay/P256.ps1), but a passkey's does not: an authenticator emits
# either half of s, and could sign the same challenge again with other clientDataJSON. So two texts
# can carry the same signed content under different signatures. What identifies an envelope - to the
# journal, to a channel, to anything that dedupes - is Get-HordeRelayReplayKey (from, channel, seq,
# nonce) and nothing else: never a hash of the wire text.
#
# NOT KEY-COMMITTING (review of 3bf4657, finding 5). AES-GCM does not bind a ciphertext to one key: a
# sender can build a ciphertext that opens under two content keys to two different bodies, and wrap a
# different content key for each recipient. The signature covers the ciphertext and every wrapped key,
# so only a TRUSTED sender can do this - but it can. Nothing may rely on "every recipient of one
# envelope saw the same body"; a channel that needs that must compare what its recipients opened.
#
# STRICT BEFORE ANYTHING ELSE. A reader refuses, in this order: text over the size cap, text that is not
# ASCII, text that is not JSON, an unknown version (by name: "unknown envelope version 2"), anything the
# schema refuses, a field of the wrong size or encoding, and a text that is not canonical. Caps are in
# code (Get-HordeRelayEnvelopeLimits): core/Schema.ps1 has no maxLength or maxItems.
#
# REPLAY IS THE JOURNAL'S, AND THIS FILE MAKES IT UNSKIPPABLE. The journal of seen (from, channel,
# seq, nonce) comes in a later pull request. Until then the hook is an interface of data, not a
# callback (tools/ExecScan.ps1 holds relay/ to running no script block it is given):
#   1. Read-HordeRelayEnvelope, then Test-HordeRelayEnvelope (the signature) - so nothing
#      unauthenticated ever reaches the journal;
#   2. the caller asks the journal about Get-HordeRelayReplayKey of the verified header;
#   3. Unprotect-HordeRelayEnvelope takes the READ envelope and the trusted senders and verifies the
#      signature again itself - a verified result is never taken as data (review of 3bf4657, finding
#      1: a hand-made one wrapping an untrusted signer's envelope opened) - then requires the channel
#      and kind the caller expects, then the journal's verdict as a core/tristate answer: known, fresh
#      as the boolean $true, and for this very envelope's replay key. Anything else is refused, and
#      nothing is decrypted.
#
# Every function that judges far-end input answers { ok; reason; ... } and never throws for it.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Schema.ps1")
. (Join-Path $PSScriptRoot "Bytes.ps1")
. (Join-Path $PSScriptRoot "Backend.ps1")
. (Join-Path $PSScriptRoot "P256.ps1")
. (Join-Path $PSScriptRoot "Hpke.ps1")
. (Join-Path $PSScriptRoot "WebAuthn.ps1")
. (Join-Path $PSScriptRoot "Session.ps1")

function Get-HordeRelayEnvelopeLimits {
    # bodyBytes: a decisions snapshot is the largest planned body. Decisions caps one message at
    # 500,000 characters (decisions/Rules.ps1); 1 MiB holds a snapshot of several such, and keeps one
    # envelope well inside a relay's request and storage limits. A larger body is the channel's to split.
    # recipients: a phone identity key and a few machines; 8 is room, not a target.
    # textChars: the base64url of the largest ciphertext, plus 16 KiB for header, recipients and
    # signature (8 recipients are about 1.4 KB; a WebAuthn signature about 2 KB at its caps).
    $body = 1048576
    return [pscustomobject]@{
        bodyBytes = $body
        recipients = 8
        textChars = ([long][System.Math]::Ceiling(($body + 16) * 4 / 3) + 16384)
        maxInteger = [long]9007199254740991
    }
}

function Get-HordeRelayEnvelopeDomain {
    # The fixed prefixes of what is authenticated, so an envelope's bytes can never be read as another
    # protocol's, nor its additional data as its signed input.
    param([string]$Part)
    if ($Part -ceq "aad") { return "horde-relay/envelope/v1 aad`n" }
    if ($Part -ceq "info") { return "horde-relay/envelope/v1 content-key" }
    if ($Part -ceq "signed") { return "horde-relay/envelope/v1 signed`n" }
    throw ("no such domain part: " + $Part)
}

function New-HordeRelayEnvelopeAnswer {
    param([string]$Reason, $Value = $null)
    return [pscustomobject]@{ ok = ($Reason -ceq ""); reason = $Reason; value = $Value }
}

function ConvertTo-HordeRelayHeaderText {
    # The canonical header text. Every string was checked against its alphabet before it got here, so
    # nothing needs escaping.
    param($Header)
    $to = (@($Header.to) | ForEach-Object { '"' + $_ + '"' }) -join ","
    return ('{"v":' + $Header.v + ',"kind":"' + $Header.kind + '","channel":"' + $Header.channel + '","from":"' + $Header.from +
        '","to":[' + $to + '],"seq":' + $Header.seq + ',"nonce":"' + $Header.nonce + '","ts":' + $Header.ts + '}')
}

function ConvertTo-HordeRelayRecipientsText {
    param($Recipients)
    $items = @($Recipients | ForEach-Object { '{"kid":"' + $_.kid + '","enc":"' + $_.encText + '","key":"' + $_.keyText + '"}' })
    return ("[" + ($items -join ",") + "]")
}

function ConvertTo-HordeRelaySigText {
    param($Sig)
    if ($Sig.alg -ceq "ES256") { return ('{"alg":"ES256","value":"' + $Sig.valueText + '"}') }
    if ($Sig.alg -ceq "session") {
        # relay/Session.ps1, THE SESSION SIGNATURE: the vouch and its assertion ride along, or none of them.
        $text = '{"alg":"session","vouchId":"' + $Sig.vouchId + '","value":"' + $Sig.valueText + '"'
        if ("" + $Sig.vouchText -cne "") { $text += ',"vouch":"' + $Sig.vouchText + '","authenticatorData":"' + $Sig.authenticatorDataText + '","clientDataJSON":"' + $Sig.clientDataJsonText + '","signature":"' + $Sig.signatureText + '"' }
        return ($text + "}")
    }
    return ('{"alg":"webauthn.get","authenticatorData":"' + $Sig.authenticatorDataText + '","clientDataJSON":"' + $Sig.clientDataJsonText + '","signature":"' + $Sig.signatureText + '"}')
}

function Get-HordeRelaySigningInput {
    # The bytes the sender signs (ES256), and whose SHA-256 is a passkey's challenge.
    param([string]$HeaderText, [string]$RecipientsText, [string]$CtText)
    return ,(Get-HordeRelayAsciiBytes -Text ((Get-HordeRelayEnvelopeDomain -Part "signed") + $HeaderText + "`n" + $RecipientsText + "`n" + $CtText))
}

function Test-HordeRelayInteger {
    # A JSON integer as ConvertFrom-Json gives one (Int32 or Int64 - never Decimal, Double or BigInteger)
    # within 0 .. 2^53-1, the range both .NET and JavaScript hold exactly.
    param($Value)
    if ($Value -isnot [int] -and $Value -isnot [long]) { return $false }
    return [bool]($Value -ge 0 -and $Value -le (Get-HordeRelayEnvelopeLimits).maxInteger)
}

function New-HordeRelayEnvelopeDraft {
    # Everything of an envelope but its signature: { header; headerText; recipients; recipientsText;
    # ct; ctText; signingInput; challenge }. New-HordeRelayEnvelope signs it with a machine key; a
    # passkey signs SHA-256(signingInput), which is challenge, and Complete-HordeRelayEnvelope adds it.
    # Throws on a bad argument: these are the sender's own values, not the far end's.
    param([Parameter(Mandatory = $true)][string]$Kind, [Parameter(Mandatory = $true)][string]$Channel,
        [Parameter(Mandatory = $true)][string]$From, [Parameter(Mandatory = $true)][long]$Seq,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Body, [Parameter(Mandatory = $true)][object[]]$Recipients,
        $Now = $null)
    $limits = Get-HordeRelayEnvelopeLimits
    if ($Kind -cnotmatch '\A[a-z][a-z0-9-]{0,31}\z') { throw ("an envelope kind is a lower-case word of up to 32 characters, not '" + $Kind + "'") }
    if ($Channel -cnotmatch '\A[a-z][a-z0-9-]{0,31}\z') { throw ("an envelope channel is a lower-case word of up to 32 characters, not '" + $Channel + "'") }
    if ($From -cnotmatch '\A[0-9a-f]{32}\z') { throw "the sender is named by its 32-hex key id" }
    if (-not (Test-HordeRelayInteger -Value $Seq)) { throw ("the sequence number must be 0 to 2^53-1, not " + $Seq) }
    if ($Body.Length -gt $limits.bodyBytes) { throw ("the body is " + $Body.Length + " bytes; an envelope holds at most " + $limits.bodyBytes + ": split it") }
    if ($Recipients.Count -lt 1 -or $Recipients.Count -gt $limits.recipients) { throw ("an envelope has 1 to " + $limits.recipients + " recipients") }
    $when = $Now
    if ($null -eq $when) { $when = [System.DateTime]::UtcNow }
    $ts = [long][System.Math]::Floor(($when.ToUniversalTime() - (New-Object datetime -ArgumentList 1970, 1, 1, 0, 0, 0, ([System.DateTimeKind]::Utc))).TotalMilliseconds)
    $kids = New-Object System.Collections.ArrayList
    foreach ($r in $Recipients) {
        $kid = Get-HordeRelayKeyId -Public ([byte[]]$r)
        if ($kids -ccontains $kid) { throw "a recipient is named twice" }
        [void]$kids.Add($kid)
    }
    $header = [pscustomobject]@{ v = 1; kind = $Kind; channel = $Channel; from = $From; to = @($kids); seq = $Seq; nonce = (ConvertTo-HordeRelayHex -Bytes (Get-HordeRelayRandomBytes -Count 12)); ts = $ts }
    $headerText = ConvertTo-HordeRelayHeaderText -Header $header
    $aad = Get-HordeRelayAsciiBytes -Text ((Get-HordeRelayEnvelopeDomain -Part "aad") + $headerText)
    $info = Get-HordeRelayAsciiBytes -Text (Get-HordeRelayEnvelopeDomain -Part "info")
    $cek = Get-HordeRelayRandomBytes -Count 32
    $ct = Protect-HordeRelayAesGcm -Key $cek -Nonce (ConvertFrom-HordeRelayHex -Text $header.nonce) -Aad $aad -Plaintext $Body
    $wrapped = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $Recipients.Count; $i++) {
        $box = Protect-HordeRelayHpke -RecipientPublic ([byte[]]$Recipients[$i]) -Info $info -Aad $aad -Plaintext $cek
        [void]$wrapped.Add([pscustomobject]@{ kid = $kids[$i]; enc = $box.enc; key = $box.sealed; encText = (ConvertTo-HordeRelayBase64Url -Bytes $box.enc); keyText = (ConvertTo-HordeRelayBase64Url -Bytes $box.sealed) })
    }
    [System.Array]::Clear($cek, 0, $cek.Length)
    $recipientsText = ConvertTo-HordeRelayRecipientsText -Recipients $wrapped
    $ctText = ConvertTo-HordeRelayBase64Url -Bytes $ct
    $signingInput = Get-HordeRelaySigningInput -HeaderText $headerText -RecipientsText $recipientsText -CtText $ctText
    return [pscustomobject]@{ header = $header; headerText = $headerText; recipients = @($wrapped); recipientsText = $recipientsText; ct = $ct; ctText = $ctText; signingInput = $signingInput; challenge = (Get-HordeRelaySha256 -Bytes $signingInput) }
}

function Complete-HordeRelayEnvelope {
    # The wire text of a draft with its signature: -Es256 (64 bytes), or the three parts of a WebAuthn
    # assertion over the draft's challenge.
    # -SessionVouchId with -SessionValue (64 bytes) is a session signature (relay/Session.ps1); with
    # -VouchText too, the vouch and its assertion (the three WebAuthn parts) ride along.
    param([Parameter(Mandatory = $true)]$Draft, [byte[]]$Es256 = $null, [byte[]]$AuthenticatorData = $null, [byte[]]$ClientDataJson = $null, [byte[]]$Signature = $null,
        [string]$SessionVouchId = "", [byte[]]$SessionValue = $null, [string]$VouchText = "")
    if ($SessionVouchId -cne "") {
        if ($null -eq $SessionValue -or $SessionValue.Length -ne 64) { throw "a session signature is 64 bytes" }
        $sig = [pscustomobject]@{ alg = "session"; vouchId = $SessionVouchId; valueText = (ConvertTo-HordeRelayBase64Url -Bytes $SessionValue); vouchText = ""; authenticatorDataText = ""; clientDataJsonText = ""; signatureText = "" }
        if ($VouchText -cne "") {
            if ($null -eq $AuthenticatorData -or $null -eq $ClientDataJson -or $null -eq $Signature) { throw "a vouch rides with all three parts of its WebAuthn assertion" }
            $sig.vouchText = ConvertTo-HordeRelayBase64Url -Bytes (Get-HordeRelayAsciiBytes -Text $VouchText)
            $sig.authenticatorDataText = ConvertTo-HordeRelayBase64Url -Bytes $AuthenticatorData; $sig.clientDataJsonText = ConvertTo-HordeRelayBase64Url -Bytes $ClientDataJson; $sig.signatureText = ConvertTo-HordeRelayBase64Url -Bytes $Signature
        }
    } elseif ($null -ne $Es256) {
        $sig = [pscustomobject]@{ alg = "ES256"; valueText = (ConvertTo-HordeRelayBase64Url -Bytes $Es256) }
    } elseif ($null -ne $AuthenticatorData -and $null -ne $ClientDataJson -and $null -ne $Signature) {
        $sig = [pscustomobject]@{ alg = "webauthn.get"; authenticatorDataText = (ConvertTo-HordeRelayBase64Url -Bytes $AuthenticatorData); clientDataJsonText = (ConvertTo-HordeRelayBase64Url -Bytes $ClientDataJson); signatureText = (ConvertTo-HordeRelayBase64Url -Bytes $Signature) }
    } else { throw "an envelope is signed with -Es256, or with all three parts of a WebAuthn assertion" }
    return ('{"header":' + $Draft.headerText + ',"recipients":' + $Draft.recipientsText + ',"ct":"' + $Draft.ctText + '","sig":' + (ConvertTo-HordeRelaySigText -Sig $sig) + '}')
}

function New-HordeRelayEnvelope {
    # Seal Body to every recipient's 65-byte agree key and sign it with Signer, a machine's ECDsa sign
    # key (relay/Keys.ps1). The wire text.
    param([Parameter(Mandatory = $true)][string]$Kind, [Parameter(Mandatory = $true)][string]$Channel,
        [Parameter(Mandatory = $true)][long]$Seq, [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Body,
        [Parameter(Mandatory = $true)][object[]]$Recipients, [Parameter(Mandatory = $true)]$Signer, $Now = $null)
    $from = Get-HordeRelayKeyId -Public (ConvertTo-HordeRelayP256Public -Key $Signer)
    $draft = New-HordeRelayEnvelopeDraft -Kind $Kind -Channel $Channel -From $from -Seq $Seq -Body $Body -Recipients $Recipients -Now $Now
    return (Complete-HordeRelayEnvelope -Draft $draft -Es256 (New-HordeRelayEs256Signature -Key $Signer -Bytes $draft.signingInput))
}

function Get-HordeRelayDecodedField {
    # A base64url field decoded and of an allowed length, or a reason in .reason.
    param([string]$Text, [string]$What, [int]$Min, [int]$Max)
    try { $b = ConvertFrom-HordeRelayBase64Url -Text $Text -What $What } catch { return [pscustomobject]@{ bytes = $null; reason = $_.Exception.Message } }
    if ($b.Length -lt $Min -or $b.Length -gt $Max) {
        $range = $(if ($Min -eq $Max) { "" + $Min } else { "" + $Min + " to " + $Max })
        return [pscustomobject]@{ bytes = $null; reason = ($What + " is " + $b.Length + " bytes, not " + $range) }
    }
    return [pscustomobject]@{ bytes = $b; reason = "" }
}

function Read-HordeRelaySessionSig {
    # A session signature's members read strictly (relay/Session.ps1, THE SESSION SIGNATURE): the sig
    # object Read-HordeRelayEnvelope keeps, or the reason it is refused, as a string. The vouch it
    # carries is read in full here; whether the machine takes it is relay/Sessions.ps1's.
    param($Sig, [string[]]$Names)
    $joined = $Names -join ","
    $bare = ($joined -ceq "alg,vouchId,value")
    if (-not $bare -and $joined -cne "alg,vouchId,value,vouch,authenticatorData,clientDataJSON,signature") { return "session-refused: a session signature has exactly alg, vouchId and value, and with its vouch also vouch, authenticatorData, clientDataJSON and signature" }
    if ($Sig.vouchId -isnot [string] -or $Sig.vouchId -cnotmatch '\A[0-9a-f]{32}\z') { return "session-refused: the session signature's vouchId is not 32 lower-case hex" }
    $v = Get-HordeRelayDecodedField -Text $Sig.value -What "the session signature" -Min 64 -Max 64
    if ($v.reason -cne "") { return ("session-refused: " + $v.reason) }
    $out = [pscustomobject]@{ alg = "session"; vouchId = $Sig.vouchId; value = $v.bytes; valueText = $Sig.value; vouch = $null; vouchText = ""
        authenticatorData = $null; clientDataJson = $null; signature = $null; authenticatorDataText = ""; clientDataJsonText = ""; signatureText = "" }
    if ($bare) { return $out }
    $wa = Get-HordeRelayWebAuthnLimits
    $vb = Get-HordeRelayDecodedField -Text $Sig.vouch -What "the vouch" -Min 1 -Max (Get-HordeRelaySessionLimits).vouchTextChars
    if ($vb.reason -cne "") { return ("session-refused: " + $vb.reason) }
    foreach ($b in $vb.bytes) { if ($b -lt 0x20 -or $b -gt 0x7E) { return "session-refused: the vouch is not printable ASCII" } }
    $vouch = Read-HordeRelaySessionVouch -Text ([System.Text.Encoding]::UTF8.GetString($vb.bytes))
    if (-not $vouch.ok) { return $vouch.reason }
    if ($vouch.value.vouchId -cne $Sig.vouchId) { return "session-refused: the vouch carried is not the one the signature names" }
    $ad = Get-HordeRelayDecodedField -Text $Sig.authenticatorData -What "the vouch's authenticatorData" -Min 37 -Max $wa.authenticatorDataBytes
    if ($ad.reason -cne "") { return ("session-refused: " + $ad.reason) }
    $cd = Get-HordeRelayDecodedField -Text $Sig.clientDataJSON -What "the vouch's clientDataJSON" -Min 1 -Max $wa.clientDataJsonBytes
    if ($cd.reason -cne "") { return ("session-refused: " + $cd.reason) }
    $der = Get-HordeRelayDecodedField -Text $Sig.signature -What "the vouch's WebAuthn signature" -Min 8 -Max 72
    if ($der.reason -cne "") { return ("session-refused: " + $der.reason) }
    $out.vouch = $vouch.value; $out.vouchText = $Sig.vouch
    $out.authenticatorData = $ad.bytes; $out.clientDataJson = $cd.bytes; $out.signature = $der.bytes
    $out.authenticatorDataText = $Sig.authenticatorData; $out.clientDataJsonText = $Sig.clientDataJSON; $out.signatureText = $Sig.signature
    return $out
}

function Read-HordeRelayEnvelope {
    # Parse envelope text strictly. { ok; reason; value } where value is { header; headerText;
    # recipients; recipientsText; ct; ctText; sig } with every field decoded and checked.
    param([AllowEmptyString()][AllowNull()][string]$Text)
    $limits = Get-HordeRelayEnvelopeLimits
    if ($null -eq $Text -or $Text.Length -eq 0) { return (New-HordeRelayEnvelopeAnswer -Reason "the envelope is empty") }
    if ($Text.Length -gt $limits.textChars) { return (New-HordeRelayEnvelopeAnswer -Reason ("the envelope is larger than " + $limits.textChars + " characters")) }
    if ($Text -cnotmatch '\A[\x20-\x7E]*\z') { return (New-HordeRelayEnvelopeAnswer -Reason "the envelope is not printable ASCII") }
    try { $e = ConvertFrom-HordeJson -Text $Text } catch { return (New-HordeRelayEnvelopeAnswer -Reason "the envelope is not JSON") }
    if ($e -isnot [System.Management.Automation.PSCustomObject]) { return (New-HordeRelayEnvelopeAnswer -Reason "the envelope is not a JSON object") }
    $top = @($e.PSObject.Properties | ForEach-Object { $_.Name })
    if ($top -cnotcontains "header" -or $e.header -isnot [System.Management.Automation.PSCustomObject]) { return (New-HordeRelayEnvelopeAnswer -Reason "the envelope has no header object") }
    $hNames = @($e.header.PSObject.Properties | ForEach-Object { $_.Name })
    if ($hNames -cnotcontains "v") { return (New-HordeRelayEnvelopeAnswer -Reason "the envelope header has no version") }
    if (-not (Test-HordeRelayInteger -Value $e.header.v)) { return (New-HordeRelayEnvelopeAnswer -Reason "the envelope version is not a whole number") }
    if ($e.header.v -ne 1) { return (New-HordeRelayEnvelopeAnswer -Reason ("unknown envelope version " + $e.header.v + ": this reader knows version 1 only")) }

    $findings = @(Test-HordeSchema -Value $e -Schema (Get-HordeSchema -Name "relay-envelope.v1"))
    if ($findings.Count -gt 0) { return (New-HordeRelayEnvelopeAnswer -Reason ("the envelope does not match schema/relay-envelope.v1: " + $findings[0])) }

    $h = $e.header
    if (-not (Test-HordeRelayInteger -Value $h.seq)) { return (New-HordeRelayEnvelopeAnswer -Reason "the header's seq is not a whole number from 0 to 2^53-1") }
    if (-not (Test-HordeRelayInteger -Value $h.ts)) { return (New-HordeRelayEnvelopeAnswer -Reason "the header's ts is not a whole number from 0 to 2^53-1") }
    $to = @($h.to)
    if ($to.Count -lt 1 -or $to.Count -gt $limits.recipients) { return (New-HordeRelayEnvelopeAnswer -Reason ("the header names " + $to.Count + " recipients; an envelope has 1 to " + $limits.recipients)) }
    if (@($to | Sort-Object -Unique).Count -ne $to.Count) { return (New-HordeRelayEnvelopeAnswer -Reason "the header names a recipient twice") }
    $recs = @($e.recipients)
    if ($recs.Count -ne $to.Count) { return (New-HordeRelayEnvelopeAnswer -Reason "the recipients do not match the header's to") }
    $decodedRecs = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $recs.Count; $i++) {
        if ($recs[$i].kid -cne $to[$i]) { return (New-HordeRelayEnvelopeAnswer -Reason "the recipients do not match the header's to, in order") }
        $enc = Get-HordeRelayDecodedField -Text $recs[$i].enc -What "a recipient's enc" -Min 65 -Max 65
        if ($enc.reason -cne "") { return (New-HordeRelayEnvelopeAnswer -Reason $enc.reason) }
        $key = Get-HordeRelayDecodedField -Text $recs[$i].key -What "a recipient's sealed key" -Min 48 -Max 48
        if ($key.reason -cne "") { return (New-HordeRelayEnvelopeAnswer -Reason $key.reason) }
        [void]$decodedRecs.Add([pscustomobject]@{ kid = $recs[$i].kid; enc = $enc.bytes; key = $key.bytes; encText = $recs[$i].enc; keyText = $recs[$i].key })
    }
    $ct = Get-HordeRelayDecodedField -Text $e.ct -What "the ciphertext" -Min 16 -Max ($limits.bodyBytes + 16)
    if ($ct.reason -cne "") { return (New-HordeRelayEnvelopeAnswer -Reason $ct.reason) }

    $s = $e.sig
    $sNames = @($s.PSObject.Properties | ForEach-Object { $_.Name })
    $wa = Get-HordeRelayWebAuthnLimits
    if ($s.alg -ceq "ES256") {
        if (($sNames -join ",") -cne "alg,value") { return (New-HordeRelayEnvelopeAnswer -Reason "an ES256 signature has exactly alg and value") }
        $v = Get-HordeRelayDecodedField -Text $s.value -What "the ES256 signature" -Min 64 -Max 64
        if ($v.reason -cne "") { return (New-HordeRelayEnvelopeAnswer -Reason $v.reason) }
        $sig = [pscustomobject]@{ alg = "ES256"; value = $v.bytes; valueText = $s.value }
    } elseif ($s.alg -ceq "session") {
        $sig = Read-HordeRelaySessionSig -Sig $s -Names $sNames
        if ($sig -is [string]) { return (New-HordeRelayEnvelopeAnswer -Reason $sig) }
    } else {
        if (($sNames -join ",") -cne "alg,authenticatorData,clientDataJSON,signature") { return (New-HordeRelayEnvelopeAnswer -Reason "a webauthn.get signature has exactly alg, authenticatorData, clientDataJSON and signature") }
        $ad = Get-HordeRelayDecodedField -Text $s.authenticatorData -What "authenticatorData" -Min 37 -Max $wa.authenticatorDataBytes
        if ($ad.reason -cne "") { return (New-HordeRelayEnvelopeAnswer -Reason $ad.reason) }
        $cd = Get-HordeRelayDecodedField -Text $s.clientDataJSON -What "clientDataJSON" -Min 1 -Max $wa.clientDataJsonBytes
        if ($cd.reason -cne "") { return (New-HordeRelayEnvelopeAnswer -Reason $cd.reason) }
        $der = Get-HordeRelayDecodedField -Text $s.signature -What "the WebAuthn signature" -Min 8 -Max 72
        if ($der.reason -cne "") { return (New-HordeRelayEnvelopeAnswer -Reason $der.reason) }
        $sig = [pscustomobject]@{ alg = "webauthn.get"; authenticatorData = $ad.bytes; clientDataJson = $cd.bytes; signature = $der.bytes; authenticatorDataText = $s.authenticatorData; clientDataJsonText = $s.clientDataJSON; signatureText = $s.signature }
    }

    $header = [pscustomobject]@{ v = 1; kind = $h.kind; channel = $h.channel; from = $h.from; to = $to; seq = [long]$h.seq; nonce = $h.nonce; ts = [long]$h.ts }
    $headerText = ConvertTo-HordeRelayHeaderText -Header $header
    $recipientsText = ConvertTo-HordeRelayRecipientsText -Recipients $decodedRecs
    $canonical = '{"header":' + $headerText + ',"recipients":' + $recipientsText + ',"ct":"' + $e.ct + '","sig":' + (ConvertTo-HordeRelaySigText -Sig $sig) + '}'
    if ($canonical -cne $Text) { return (New-HordeRelayEnvelopeAnswer -Reason "the envelope is not in its canonical form (member order, spacing, escapes or number spelling differ)") }
    return (New-HordeRelayEnvelopeAnswer -Reason "" -Value ([pscustomobject]@{ header = $header; headerText = $headerText; recipients = @($decodedRecs); recipientsText = $recipientsText; ct = $ct.bytes; ctText = $e.ct; sig = $sig }))
}

function New-HordeRelaySender {
    # A sender the machine trusts, by its pinned public key: a machine (es256) or a passkey credential
    # (webauthn, with the relying party and origins its assertions must name). Pairing (a later pull
    # request) builds these; the suites build them by hand.
    param([Parameter(Mandatory = $true)][byte[]]$Public, [Parameter(Mandatory = $true)][string]$Proof,
        [string]$RpId = "", [string[]]$Origins = @(), [bool]$RequireUserVerification = $true)
    if (@("es256", "webauthn") -cnotcontains $Proof) { throw ("a sender proves itself by es256 or webauthn, not '" + $Proof + "'") }
    if ($Proof -ceq "webauthn" -and ($RpId -ceq "" -or $Origins.Count -eq 0)) { throw "a passkey sender needs its relying party id and its origins" }
    return [pscustomobject]@{ keyId = (Get-HordeRelayKeyId -Public $Public); public = $Public; proof = $Proof; rpId = $RpId; origins = @($Origins); requireUserVerification = $RequireUserVerification }
}

function Test-HordeRelayEnvelope {
    # Verify a read envelope's signature against the trusted senders (a hashtable of key id to
    # New-HordeRelaySender). { ok; reason; value } where value is { envelope; header; proof; signCount;
    # userVerified }. Nothing is decrypted here.
    param([Parameter(Mandatory = $true)]$Envelope, [Parameter(Mandatory = $true)][hashtable]$Senders)
    $env = $Envelope
    $h = $env.header
    # The parts that are used must be the parts that are signed: the signature covers the texts, while
    # decryption and the replay key use the decoded header, recipients and ciphertext. Rebuilt and
    # compared, so an envelope object whose parts were swapped after Read is refused.
    $rebuiltRecipients = ConvertTo-HordeRelayRecipientsText -Recipients @($env.recipients | ForEach-Object { [pscustomobject]@{ kid = $_.kid; encText = (ConvertTo-HordeRelayBase64Url -Bytes $_.enc); keyText = (ConvertTo-HordeRelayBase64Url -Bytes $_.key) } })
    if ((ConvertTo-HordeRelayHeaderText -Header $h) -cne $env.headerText -or $rebuiltRecipients -cne $env.recipientsText -or (ConvertTo-HordeRelayBase64Url -Bytes $env.ct) -cne $env.ctText) {
        return (New-HordeRelayEnvelopeAnswer -Reason "the envelope's parts do not match its signed text")
    }
    if (-not $Senders.ContainsKey($h.from)) { return (New-HordeRelayEnvelopeAnswer -Reason ("the sender " + $h.from + " is not one this machine trusts")) }
    $sender = $Senders[$h.from]
    if ($sender.keyId -cne $h.from) { return (New-HordeRelayEnvelopeAnswer -Reason "the trusted-sender entry for this key id holds another key") }
    $signed = Get-HordeRelaySigningInput -HeaderText $env.headerText -RecipientsText $env.recipientsText -CtText $env.ctText
    if ($env.sig.alg -ceq "ES256") {
        if ($sender.proof -cne "es256") { return (New-HordeRelayEnvelopeAnswer -Reason "the envelope is signed ES256, but this sender signs with a passkey") }
        if (-not (Test-HordeRelayEs256Signature -Public $sender.public -Bytes $signed -Signature $env.sig.value)) { return (New-HordeRelayEnvelopeAnswer -Reason "the ES256 signature does not verify under the sender's key") }
        return (New-HordeRelayEnvelopeAnswer -Reason "" -Value ([pscustomobject]@{ envelope = $env; header = $h; proof = "es256"; signCount = $null; userVerified = $false }))
    }
    if ($env.sig.alg -ceq "session") {
        # relay/Session.ps1, WHAT THE MACHINE TAKES: the vouch, the session signature, and the PC's own
        # records and clock, handed in on the sender.
        if ($sender.proof -ceq "es256") { return (New-HordeRelayEnvelopeAnswer -Reason "session-refused: the envelope is session-signed, but this sender signs ES256") }
        $sv = Test-HordeRelaySessionEnvelope -Envelope $env -Sender $sender -Signed $signed
        if (-not $sv.ok) { return (New-HordeRelayEnvelopeAnswer -Reason $sv.reason) }
        return (New-HordeRelayEnvelopeAnswer -Reason "" -Value ([pscustomobject]@{ envelope = $env; header = $h; proof = "session"; signCount = $null; userVerified = $true; vouchId = $sv.value.vouchId; vouch = $sv.value.vouch; newVouch = $sv.value.isNew }))
    }
    if ($sender.proof -cne "webauthn") { return (New-HordeRelayEnvelopeAnswer -Reason "the envelope is signed by a passkey, but this sender signs ES256") }
    $wa = Test-HordeRelayWebAuthnAssertion -Public $sender.public -AuthenticatorData $env.sig.authenticatorData -ClientDataJson $env.sig.clientDataJson `
        -Signature $env.sig.signature -Challenge (Get-HordeRelaySha256 -Bytes $signed) -RpId $sender.rpId -Origins $sender.origins -RequireUserVerification $sender.requireUserVerification
    if (-not $wa.ok) { return (New-HordeRelayEnvelopeAnswer -Reason ("the passkey assertion is refused: " + $wa.reason)) }
    return (New-HordeRelayEnvelopeAnswer -Reason "" -Value ([pscustomobject]@{ envelope = $env; header = $h; proof = "webauthn"; signCount = $wa.signCount; userVerified = $wa.userVerified }))
}

function Get-HordeRelayReplayKey {
    # What the journal must have seen at most once: from, channel, seq and nonce.
    param([Parameter(Mandatory = $true)]$Header)
    return ($Header.from + "/" + $Header.channel + "/" + $Header.seq + "/" + $Header.nonce)
}

function Unprotect-HordeRelayEnvelope {
    # Open a read envelope's body with this machine's agree keys (a hashtable of key id to key). Its
    # signature is verified here against Senders, its channel and kind must be the ones the caller
    # expects, and the journal's verdict must say it is fresh. { ok; reason; value } where value is the
    # body's bytes.
    #
    # Replay is a core/tristate answer from the journal: known, with value { key; fresh }, where key is
    # Get-HordeRelayReplayKey of THIS envelope's header and fresh is the boolean $true. Anything else
    # refuses, before a single byte is decrypted.
    param([Parameter(Mandatory = $true)]$Envelope, [Parameter(Mandatory = $true)][hashtable]$Senders,
        [Parameter(Mandatory = $true)][hashtable]$RecipientKeys, [Parameter(Mandatory = $true)][AllowNull()]$Replay,
        [Parameter(Mandatory = $true)][string]$Channel, [Parameter(Mandatory = $true)][string]$Kind)
    $verified = Test-HordeRelayEnvelope -Envelope $Envelope -Senders $Senders
    if (-not $verified.ok) { return (New-HordeRelayEnvelopeAnswer -Reason $verified.reason) }
    $env = $Envelope
    $h = $env.header
    if ($h.channel -cne $Channel) { return (New-HordeRelayEnvelopeAnswer -Reason ("the envelope is for the channel " + $h.channel + ", not " + $Channel)) }
    if ($h.kind -cne $Kind) { return (New-HordeRelayEnvelopeAnswer -Reason ("the envelope is of the kind " + $h.kind + ", not " + $Kind)) }
    $rk = Get-HordeRelayReplayKey -Header $h
    # Members are looked up, not dereferenced: under strict mode a missing one would throw, and a verdict
    # is checked here precisely because it may be malformed.
    $state = $(if ($null -eq $Replay) { $null } else { $Replay.PSObject.Properties["state"] })
    if ($null -eq $state -or $state.Value -cne "known") {
        $why = "none was given"
        if ($null -ne $state) {
            $reasonProp = $Replay.PSObject.Properties["reason"]
            $why = "it is " + $state.Value + $(if ($null -ne $reasonProp -and "" + $reasonProp.Value -cne "") { ": " + $reasonProp.Value } else { "" })
        }
        return (New-HordeRelayEnvelopeAnswer -Reason ("no fresh verdict from the journal (" + $why + "), so the envelope is not opened"))
    }
    $verdict = $Replay.PSObject.Properties["value"]
    $vKey = $null; $vFresh = $null
    if ($null -ne $verdict -and $null -ne $verdict.Value) {
        $vKey = $verdict.Value.PSObject.Properties["key"]
        $vFresh = $verdict.Value.PSObject.Properties["fresh"]
    }
    if ($null -eq $vKey -or "" + $vKey.Value -cne $rk) { return (New-HordeRelayEnvelopeAnswer -Reason "the journal's verdict is about another envelope, so this one is not opened") }
    # The boolean $true only: -ne $true let 1 and "true" through (review of 3bf4657, finding 2).
    if ($null -eq $vFresh -or $vFresh.Value -isnot [bool]) { return (New-HordeRelayEnvelopeAnswer -Reason "the journal's answer is not a fresh verdict: fresh must be the boolean true, so this envelope is not opened") }
    if (-not $vFresh.Value) {
        # The journal says why it refused (relay/Journal.ps1's why: a replay, out of order, the clock);
        # passed on, so a clock or window refusal is not reported as a replay (review of the journal PR).
        $vWhy = $verdict.Value.PSObject.Properties["why"]
        if ($null -ne $vWhy -and "" + $vWhy.Value -cne "") { return (New-HordeRelayEnvelopeAnswer -Reason ("the journal refuses this envelope (" + $vWhy.Value + "), so it is not opened")) }
        return (New-HordeRelayEnvelopeAnswer -Reason "the journal has seen this envelope already: a replay is refused")
    }

    $mine = $null
    foreach ($r in @($env.recipients)) { if ($RecipientKeys.ContainsKey($r.kid)) { $mine = $r; break } }
    if ($null -eq $mine) { return (New-HordeRelayEnvelopeAnswer -Reason "the envelope is not addressed to any key of this machine") }
    $key = $RecipientKeys[$mine.kid]
    if ((Get-HordeRelayKeyId -Public (ConvertTo-HordeRelayP256Public -Key $key)) -cne $mine.kid) { return (New-HordeRelayEnvelopeAnswer -Reason "the agree key given for this key id is another key") }
    $aad = Get-HordeRelayAsciiBytes -Text ((Get-HordeRelayEnvelopeDomain -Part "aad") + $env.headerText)
    $info = Get-HordeRelayAsciiBytes -Text (Get-HordeRelayEnvelopeDomain -Part "info")
    $cek = Unprotect-HordeRelayHpke -RecipientKey $key -Enc $mine.enc -Info $info -Aad $aad -Sealed $mine.key
    if ($null -eq $cek -or $cek.Length -ne 32) { return (New-HordeRelayEnvelopeAnswer -Reason "the content key does not open for this machine's key") }
    $body = Unprotect-HordeRelayAesGcm -Key $cek -Nonce (ConvertFrom-HordeRelayHex -Text $h.nonce) -Aad $aad -Sealed $env.ct
    [System.Array]::Clear($cek, 0, $cek.Length)
    if ($null -eq $body) { return (New-HordeRelayEnvelopeAnswer -Reason "the body does not open: the ciphertext or the header was changed") }
    return (New-HordeRelayEnvelopeAnswer -Reason "" -Value ([byte[]]$body))
}
