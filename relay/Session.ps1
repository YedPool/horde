# relay/Session.ps1 - the unlocked session: one passkey prompt per unlock, not per answer (design note
# "Unlocked session", 2026-10-14; it changes the answer path, so it waits for the security review).
#
# WHY. Every envelope a phone sent was signed by its own passkey assertion, so every answer, chat line
# and photo was a prompt. Now the unlock's ONE assertion vouches for a SESSION KEY the page makes (an
# ECDSA P-256 key, non-extractable, in page memory only), and that key signs the envelopes after it.
# The PC still decides everything: the vouch is the founder's passkey assertion, verified with the same
# verifier as before (relay/WebAuthn.ps1, user verification required), and the PC's own clock and
# records say whether the session is still alive. This file is the WIRE: the bytes both sides write
# and read. relay/js/protocol.js holds the same strings for the phone; a string here that differs from
# its twin there is a bug (test/test-relay-session-wire.ps1 compares them byte for byte).
#
# THE VOUCH, one canonical text (relay/Records.ps1's rules: these members in this order, no spacing,
# every value of its kind), ASCII:
#   {"v":1,"kind":"horde-relay-session-vouch","sessionPublicKey":"<b64u, 65-byte P-256 point>",
#    "deviceKeyId":"<32 hex>","phoneKeyId":"<32 hex>","horde":"<horde>","machine":"<32 hex>",
#    "mailbox":"<horde>/<machine>","notBefore":<ms>,"notAfter":<ms>,"seq":<n>,"vouchId":"<32 hex>"}
#   sessionPublicKey  the session key's public point. The private half never leaves the page.
#   deviceKeyId       the key id of the founder passkey that signs the vouch: the envelopes' "from".
#   phoneKeyId        the key id of the phone identity key of the same page (relay/Trust.ps1, PHONE KEYS).
#   horde, machine    the horde and the key id of the ONE machine the session answers (a pairing is one
#                     machine: surfaces/pwa/page/phone-core.js, ONE HORDE, ONE ENTRY).
#   mailbox           that machine's mailbox, <horde>/<machine>: nothing else, checked on read.
#   notBefore,        the window, Unix milliseconds, phone clock: notBefore < notAfter, and notAfter at
#   notAfter          most notBefore + 8 h (the hard cap, whatever the idle setting).
#   seq               this device's vouch counter: each new vouch of a device above its last. The PC
#                     refuses a NEW vouch at or below the highest it has of that device (session-stale).
#   vouchId           the key id of sessionPublicKey (relay/P256.ps1's Get-HordeRelayKeyId): one id, one
#                     key, so a vouchId can never name two keys.
# ONE PROMPT: the unlock assertion's challenge IS the vouch's hash -
#   challenge = SHA-256("horde-relay/session/v1 vouch" LF <vouch text>)
# so the founder's one Face ID both unlocks the page and vouches for the key.
#
# THE SESSION SIGNATURE on an envelope (relay/Envelope.ps1's sig member), alg "session":
#   {"alg":"session","vouchId":"<32 hex>","value":"<b64u, 64 bytes>"}
# and, on the FIRST envelope of a session (and on any later one the phone chooses), the vouch with it:
#   {"alg":"session","vouchId":"<32 hex>","value":"<b64u>","vouch":"<b64u of the vouch text>",
#    "authenticatorData":"<b64u>","clientDataJSON":"<b64u>","signature":"<b64u, DER>"}
# value is ES256 (r || s, 64 bytes; either half of s - WebCrypto does not normalise it, and the
# signature is not part of an envelope's identity) by the session key over
#   "horde-relay/session/v1 envelope" LF <vouchId> LF  followed by the envelope's own signed bytes
# (relay/Envelope.ps1's Get-HordeRelaySigningInput), so a session signature can never be read as a
# machine's or a passkey's, and names the vouch it stands under. The envelope's header is unchanged:
# from is the PASSKEY's key id (the vouch's deviceKeyId), so seq, replay and the stale-answer rules
# (relay/Journal.ps1; channels/decisions, A STALE ANSWER NEVER WINS) are exactly as before.
#
# WHAT THE PC REFUSES, BY NAME (Get-HordeRelaySessionRefusals): every refusal of a session envelope
# starts with one of these codes, and the phone acts on the code:
#   session-expired  the PC's clock, or the envelope's time, is outside [notBefore, notAfter]: unlock again.
#   session-idle     the PC has not seen this session used within its idle limit (60 min, a setting the
#                    PC enforces itself): unlock again.
#   session-ended    the founder ended every phone session at the PC, or the device or its phone key is
#                    no longer trusted: unlock again.
#   session-unknown  the PC holds no vouch of that id: send the vouch with the next envelope.
#   session-stale    the vouch's seq is not above the device's last: unlock again (a new vouch).
#   session-refused  the vouch or the session signature does not verify, or binds another horde,
#                    machine, mailbox, device or phone key: never send under it again.
#   needs-passkey    the question is flagged needsPasskey: answer it with a fresh passkey assertion.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path $PSScriptRoot "Bytes.ps1")
. (Join-Path $PSScriptRoot "P256.ps1")
. (Join-Path $PSScriptRoot "Records.ps1")
. (Join-Path $PSScriptRoot "WebAuthn.ps1")

function Get-HordeRelaySessionLimits {
    # maxWindowMs: the hard cap of the design note, 8 hours, whatever any setting says.
    # idleDefaultMs: the idle limit the PC holds when nothing is set (the founder's 60 minutes).
    # vouchTextChars: the vouch text is about 420 characters at its longest names; 1024 is room.
    return [pscustomobject]@{ maxWindowMs = [long]28800000; idleDefaultMs = [long]3600000; vouchTextChars = 1024 }
}

function Get-HordeRelaySessionDomain {
    # The fixed prefixes of what a session signs, so its bytes are never another protocol's.
    param([string]$Part)
    if ($Part -ceq "vouch") { return "horde-relay/session/v1 vouch`n" }
    if ($Part -ceq "envelope") { return "horde-relay/session/v1 envelope`n" }
    throw ("no such session domain part: " + $Part)
}

function Get-HordeRelaySessionRefusals {
    # The refusal codes of the header, in the order they are listed there.
    return @("session-expired", "session-idle", "session-ended", "session-unknown", "session-stale", "session-refused", "needs-passkey")
}

function Get-HordeRelaySessionVouchSpec {
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "sessionPublicKey", "point", "deviceKeyId", "hex32", "phoneKeyId", "hex32",
        "horde", "name", "machine", "hex32", "mailbox", "mailbox", "notBefore", "int", "notAfter", "int", "seq", "int", "vouchId", "hex32"))
}

function ConvertTo-HordeRelaySessionVouchText {
    # The canonical vouch text for -SessionPublicKey (65 bytes) and the rest; vouchId and mailbox are
    # derived, never given. Throws on a value that is not of its kind or a window the rules refuse:
    # these are the caller's own values (the suites', a phone's twin), not the far end's.
    param([Parameter(Mandatory = $true)][byte[]]$SessionPublicKey, [Parameter(Mandatory = $true)][string]$DeviceKeyId,
        [Parameter(Mandatory = $true)][string]$PhoneKeyId, [Parameter(Mandatory = $true)][string]$Horde,
        [Parameter(Mandatory = $true)][string]$Machine, [Parameter(Mandatory = $true)][long]$NotBefore,
        [Parameter(Mandatory = $true)][long]$NotAfter, [Parameter(Mandatory = $true)][long]$Seq)
    if ($NotAfter -le $NotBefore -or ($NotAfter - $NotBefore) -gt (Get-HordeRelaySessionLimits).maxWindowMs) { throw "a session's notAfter is after its notBefore, and at most 8 hours after it" }
    $values = @{ v = 1; kind = "horde-relay-session-vouch"; sessionPublicKey = (ConvertTo-HordeRelayBase64Url -Bytes $SessionPublicKey); deviceKeyId = $DeviceKeyId
        phoneKeyId = $PhoneKeyId; horde = $Horde; machine = $Machine; mailbox = ($Horde + "/" + $Machine); notBefore = $NotBefore; notAfter = $NotAfter
        seq = $Seq; vouchId = (Get-HordeRelayKeyId -Public $SessionPublicKey) }
    return (ConvertTo-HordeRelayRecordText -Spec (Get-HordeRelaySessionVouchSpec) -Values $values)
}

function Read-HordeRelaySessionVouch {
    # A vouch text read strictly: { ok; reason; value } with value the record's members plus
    # sessionPublic (the point's bytes) and text (exactly as given, which the challenge hashes). What
    # the text alone can say is checked here: its one canonical form, vouchId the key id of its key,
    # mailbox its horde and machine, and the window. Whether the PC takes it is relay/Sessions.ps1's.
    param([AllowEmptyString()][AllowNull()][string]$Text)
    $fail = [pscustomobject]@{ ok = $false; reason = ""; value = $null }
    if ($null -eq $Text -or $Text.Length -eq 0) { $fail.reason = "session-refused: the vouch is empty"; return $fail }
    if ($Text.Length -gt (Get-HordeRelaySessionLimits).vouchTextChars) { $fail.reason = "session-refused: the vouch is longer than a vouch can be"; return $fail }
    $r = Read-HordeRelayRecordText -Text $Text -Spec (Get-HordeRelaySessionVouchSpec) -Kind "horde-relay-session-vouch" -What "the vouch"
    if (-not $r.ok) { $fail.reason = ("session-refused: " + $r.reason); return $fail }
    $v = $r.value
    $point = ConvertFrom-HordeRelayBase64Url -Text $v.sessionPublicKey -What "the session key"
    if ((Get-HordeRelayKeyId -Public $point) -cne $v.vouchId) { $fail.reason = "session-refused: the vouchId is not the key id of the session key"; return $fail }
    if ($v.mailbox -cne ($v.horde + "/" + $v.machine)) { $fail.reason = "session-refused: the vouch's mailbox is not its horde and machine"; return $fail }
    if ($v.notAfter -le $v.notBefore) { $fail.reason = "session-refused: the vouch's notAfter is not after its notBefore"; return $fail }
    if (($v.notAfter - $v.notBefore) -gt (Get-HordeRelaySessionLimits).maxWindowMs) { $fail.reason = "session-refused: the vouch's window is longer than 8 hours"; return $fail }
    $v | Add-Member -NotePropertyName sessionPublic -NotePropertyValue $point
    $v | Add-Member -NotePropertyName text -NotePropertyValue $Text
    return [pscustomobject]@{ ok = $true; reason = ""; value = $v }
}

function Get-HordeRelaySessionVouchChallenge {
    # What the unlock's passkey assertion signs (ONE PROMPT, in the header): 32 bytes.
    param([Parameter(Mandatory = $true)][string]$Text)
    return ,(Get-HordeRelaySha256 -Bytes (Get-HordeRelayAsciiBytes -Text ((Get-HordeRelaySessionDomain -Part "vouch") + $Text)))
}

function Get-HordeRelaySessionSigningInput {
    # The bytes a session key signs for one envelope: the domain, the vouchId, then the envelope's own
    # signed bytes (-Signed, relay/Envelope.ps1's Get-HordeRelaySigningInput).
    param([Parameter(Mandatory = $true)][string]$VouchId, [Parameter(Mandatory = $true)][byte[]]$Signed)
    return ,(Join-HordeRelayBytes -Parts @((Get-HordeRelayAsciiBytes -Text ((Get-HordeRelaySessionDomain -Part "envelope") + $VouchId + "`n")), $Signed))
}

# --- WHAT THE MACHINE TAKES (relay/Envelope.ps1's Test-HordeRelayEnvelope asks this for alg "session") ---
#
# The verdict is pure: everything the PC knows of its sessions NOW is handed in as data on the sender
# (channels/Sessions.ps1 builds it from its records and its own clock; relay/ runs no block it is
# given), as sender.session:
#   horde, machine, mailbox   this machine's horde, signing key id and mailbox
#   nowMs                     the PC's clock
#   idleMs                    the idle limit (the PC's setting, 60 minutes unless set)
#   skewMs                    how far a phone's clock may run ahead (the journal's clockSkewSeconds)
#   endedAt                   the newest "end all phone sessions" at the PC, 0 for none
#   broken                    "" or why the PC's session records cannot be read (then nothing is taken)
#   phoneKeyIds               the phone identity keys this passkey vouched for that are trusted NOW
#   vouches                   vouchId -> { vouch (Read-HordeRelaySessionVouch's value); recordedAt;
#                             lastSeen } - the vouches of THIS passkey the PC holds, with when the PC
#                             recorded each and last took an envelope under it (PC clock, 0 for never)
#   highestSeq                the highest vouch seq the PC holds of this passkey, -1 for none
# A sender with no session member takes no session (an older PC refuses it the same way, by name).
# The checks, each refusal by its code, in this order - the signatures first, so nothing about the
# PC's records is said to a forger:
#   1. the vouch: carried, its passkey assertion verifies under THIS sender's key with user
#      verification over the vouch's hash; or not carried, and the PC holds it (else session-unknown).
#      A carried vouch the PC already holds must be the very text it holds.
#   2. the vouch is this sender's (deviceKeyId is the envelope's from), and the session signature
#      verifies under the vouched key over the envelope's signed bytes and this vouchId;
#   3. it binds this horde, machine and mailbox; its phone key is trusted now (else session-ended);
#   4. a vouch the PC does not hold yet has a seq above the highest it holds (else session-stale);
#   5. not ended: no "end all" at or after the vouch's notBefore or the time the PC recorded it;
#   6. the window: the envelope's time and the PC's clock inside [notBefore, notAfter] (the PC's clock
#      may be behind notBefore by skewMs, a phone clock running ahead); else session-expired;
#   7. idle: the PC took an envelope under it, or recorded it, within idleMs of now; else session-idle.
# Revoking the device takes it out of the senders altogether, so nothing of it reaches here.

function Test-HordeRelaySessionEnvelope {
    # A read envelope whose sig is alg session, against -Sender (New-HordeRelaySender, webauthn, with
    # its session member) and -Signed (Get-HordeRelaySigningInput of the envelope). { ok; reason; value }
    # with value { vouchId; vouch; isNew } - isNew when the PC does not hold this vouch yet.
    param([Parameter(Mandatory = $true)]$Envelope, [Parameter(Mandatory = $true)]$Sender, [Parameter(Mandatory = $true)][byte[]]$Signed)
    $fail = [pscustomobject]@{ ok = $false; reason = ""; value = $null }
    $h = $Envelope.header
    $sig = $Envelope.sig
    $sp = $Sender.PSObject.Properties["session"]
    if ($null -eq $sp -or $null -eq $sp.Value) { $fail.reason = "session-refused: this machine takes no session signature from this sender"; return $fail }
    $p = $sp.Value
    if ("" + $p.broken -cne "") { $fail.reason = ("session-unknown: the PC's session records cannot be read (" + $p.broken + "), so no session is taken until they are repaired"); return $fail }
    $held = $null
    if ($p.vouches.ContainsKey($sig.vouchId)) { $held = $p.vouches[$sig.vouchId] }
    $vouch = $null
    if ($null -ne $sig.vouch) {
        $wa = Test-HordeRelayWebAuthnAssertion -Public $Sender.public -AuthenticatorData $sig.authenticatorData -ClientDataJson $sig.clientDataJson -Signature $sig.signature `
            -Challenge (Get-HordeRelaySessionVouchChallenge -Text $sig.vouch.text) -RpId $Sender.rpId -Origins $Sender.origins -RequireUserVerification $true
        if (-not $wa.ok) { $fail.reason = ("session-refused: the vouch's passkey assertion is refused: " + $wa.reason); return $fail }
        if ($null -ne $held -and $held.vouch.text -cne $sig.vouch.text) { $fail.reason = "session-refused: the vouch carried is not the one the PC holds under that vouchId"; return $fail }
        $vouch = $sig.vouch
    } elseif ($null -ne $held) {
        $vouch = $held.vouch
    } else {
        $fail.reason = ("session-unknown: the PC holds no vouch " + $sig.vouchId + " of this passkey: send the vouch with the next envelope"); return $fail
    }
    if ($vouch.deviceKeyId -cne $h.from) { $fail.reason = "session-refused: the vouch is another passkey's, not this envelope's sender's"; return $fail }
    $toVerify = Get-HordeRelaySessionSigningInput -VouchId $sig.vouchId -Signed $Signed
    # Either half of s: WebCrypto does not normalise it, and a signature is not an envelope's identity.
    if (-not (Test-HordeRelayEs256Signature -Public $vouch.sessionPublic -Bytes $toVerify -Signature $sig.value -AllowHighS)) { $fail.reason = "session-refused: the session signature does not verify under the vouched key"; return $fail }
    if ($vouch.horde -cne $p.horde -or $vouch.machine -cne $p.machine -or $vouch.mailbox -cne $p.mailbox) { $fail.reason = ("session-refused: the vouch is for " + $vouch.mailbox + ", not this machine's mailbox " + $p.mailbox); return $fail }
    if (@($p.phoneKeyIds) -cnotcontains $vouch.phoneKeyId) { $fail.reason = ("session-ended: the vouch's phone key " + $vouch.phoneKeyId + " is not one this passkey vouched for that is trusted now"); return $fail }
    $isNew = ($null -eq $held)
    if ($isNew -and [long]$vouch.seq -le [long]$p.highestSeq) { $fail.reason = ("session-stale: the vouch's seq " + $vouch.seq + " is not above " + $p.highestSeq + ", the highest this PC holds of this passkey"); return $fail }
    $recordedAt = $(if ($isNew) { [long]$p.nowMs } else { [long]$held.recordedAt })
    if ([long]$p.endedAt -gt 0 -and ([long]$vouch.notBefore -le [long]$p.endedAt -or $recordedAt -le [long]$p.endedAt)) { $fail.reason = ("session-ended: every phone session was ended at the PC at " + $p.endedAt + " ms"); return $fail }
    $ts = [long]$h.ts
    if ($ts -lt [long]$vouch.notBefore -or $ts -gt [long]$vouch.notAfter) { $fail.reason = ("session-expired: the envelope's time " + $ts + " is outside the session's window " + $vouch.notBefore + " to " + $vouch.notAfter); return $fail }
    if ([long]$p.nowMs -gt [long]$vouch.notAfter -or [long]$p.nowMs + [long]$p.skewMs -lt [long]$vouch.notBefore) { $fail.reason = ("session-expired: the PC's clock " + $p.nowMs + " is outside the session's window " + $vouch.notBefore + " to " + $vouch.notAfter); return $fail }
    $last = $recordedAt
    if (-not $isNew -and [long]$held.lastSeen -gt $last) { $last = [long]$held.lastSeen }
    if ([long]$p.nowMs - $last -gt [long]$p.idleMs) { $fail.reason = ("session-idle: the PC has not seen this session used for " + [long](([long]$p.nowMs - $last) / 60000) + " minutes; the limit is " + [long]([long]$p.idleMs / 60000)); return $fail }
    return [pscustomobject]@{ ok = $true; reason = ""; value = [pscustomobject]@{ vouchId = $sig.vouchId; vouch = $vouch; isNew = $isNew } }
}
