# relay/Join.ps1 - PHONE-STARTED PAIRING ("Add this phone"), the machine's side, as data: a join request
# from a new phone, the offer the machine answers it with, and the approval that alone makes the new
# phone trusted. No network here (the join channel, channels/join, carries it); every rule is here.
#
# The founder, 2026-10-14: "allow pairing requests to start from the new phone once the Horde is already
# associated with a gmail account that was logged into." Design note: design-phone-started-pairing.md
# (Orc F, with C's conditions). IT REUSES TODAY'S PAIRING (relay/Pairing.ps1); only the direction of the
# first message changes:
#   1. THE JOIN REQUEST. The new phone, signed in to the account, asks to join ONE machine of it: a
#      canonical item (Get-HordeRelayJoinRequestSpec), kind horde-relay-join-request - request (a random
#      id, its nonce), horde, machine (that machine's signing key id), label (what it calls itself),
#      agent (its browser, in a few words), requestKey (a fresh P-256 agreement key: what the answer is
#      sealed to), country (the hosted relay's word; "" when none), requestedAt and expiresAt. It lands in
#      that machine's own mailbox under the key join/<request>. On the hosted relay ONLY the relay's join
#      route can put an item under such a key (its worker refuses a phone that tries): that route holds
#      the limits - one pending request an account, so many an hour an account and an address, 10
#      minutes each, a reject that frees the slot and blocks the address for the hour.
#      A REQUEST IS ONLY A REQUEST: whoever is signed in to the account can make one, and it grants
#      nothing (Receive-HordeRelayJoinRequest records it, after its own checks: this horde, this machine,
#      not expired, and no other request open on this machine).
#   2. THE ANSWER, AT ONCE. The machine makes a pairing offer (New-HordeRelayPairingOffer, its life the
#      request's) and seals its text to the request key (New-HordeRelayJoinOfferSealedText; HPKE with
#      info "horde-relay/join/v1 offer-key" and AAD "horde-relay/join/v1 offer aad" LF horde LF request LF
#      requestKeyId) into the reply mailbox <horde>/jr-<request>. That trusts nothing: it only gives the
#      new phone what a QR code gives it today - the machine's keys and its nonce (the offer id and
#      code, which the challenge hashes).
#   3. THE NEW PHONE pairs with that offer exactly as with a scanned one: it makes its passkey (its own
#      key and nonce: the credential's point and id), sends the sealed response to the offer's pairing
#      mailbox, and the machine enrolls the passkey PENDING (Complete-HordeRelayPairing). Both compute
#      THE 12-DIGIT NUMBER as today (relay/Pairing.ps1, the fingerprint: the challenge - so the offer
#      with both of the machine's keys and its nonce - the passkey's point, its credential id and the
#      rpId). It is shown ONLY on the new phone.
#   4. THE APPROVAL, by the founder typing that number on a device he holds, which compares it with the
#      number IT computes, and only then approves:
#        (a) at this machine: `horde relay approve <request> <number>` (Approve-HordeRelayJoin) - three
#            wrong numbers reject the request;
#        (b) on a trusted phone: the machine sends it the TRANSCRIPT (Get-HordeRelayJoinTranscriptText:
#            the request id, the horde and machine, the offer, its challenge, the device id, the
#            credential id, the passkey's point, the rpId, the label, agent, country and times), sealed
#            to the trusted phones and signed by this machine. The phone computes the number from it,
#            compares it with what he types, and on a match returns an approval - an envelope signed by
#            its passkey with user verification (channels/join, kind approve) - carrying only the
#            request id, the device id and the TRANSCRIPT HASH (Get-HordeRelayJoinTranscriptHash).
#            Approve-HordeRelayJoinByPhone grants trust only when that hash is the one of the transcript
#            this machine computes now for that request and that pending device.
#      THE NUMBER NEVER TRAVELS. The relay holds no number and no key that signs an approval.
#   5. Approved, the passkey is trusted, and the machine tells the new phone so (relay/Pairing.ps1,
#      the confirmed record), which then announces itself with one prompt (relay/Trust.ps1).
# REJECTED, EXPIRED, REVOKED: a reject (the CLI, or a trusted phone's envelope, kind reject) revokes the
# pending passkey, if one registered, and closes the request; a request not approved within its 10
# minutes is closed as expired, its offer voided and its passkey revoked; a pending passkey revoked by
# other means (relay trust revoke) closes its request. Nothing is retried by the machine; the new phone
# taps Add this phone again.
# REPLAY AND SWAP: an approval names its request and device, and its hash binds both keys and both
# nonces; a request is approved once (its device becomes trusted, after which nothing about the request
# is pending), and an approval for one request fails the hash of any other.
#
# WHERE: <HORDE_HOME>\relay\join\ (relay/Records.ps1, write-once):
#   requests\<request>.json        the request as received (Get-HordeRelayJoinReceivedSpec)
#   steps\<request>-<step>.json    what has been done for it, once each: offered (the offer id),
#                                  noticed, asked (the question), transcript, confirmed, told, tries-<n>
#   closed\<request>.json          its end: approved, rejected, expired or ended, and why
#
# Every function that judges far-end input answers { ok; reason; value } or { outcome; reason } and never
# throws for it.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path $PSScriptRoot "Pairing.ps1")

function Get-HordeRelayJoinLimits {
    # ttlMs: the founder's 10 minutes (design note, threat 2). maxItemChars: a request is a few hundred
    # characters (a 512-character agent at most). tries: wrong numbers typed at this machine before the
    # request is rejected, as `horde relay pair` allows.
    return [pscustomobject]@{ ttlMs = 600000; maxItemChars = 4096; tries = 3 }
}

function Get-HordeRelayJoinRequestSpec {
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "request", "hex32", "horde", "name", "machine", "hex32", "label", "label",
        "agent", "text", "requestKey", "point", "country", "text", "requestedAt", "int", "expiresAt", "int"))
}

function Get-HordeRelayJoinReceivedSpec {
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "request", "hex32", "horde", "name", "machine", "hex32", "label", "label",
        "agent", "text", "requestKey", "point", "country", "text", "requestedAt", "int", "expiresAt", "int", "receivedAt", "int"))
}

function Get-HordeRelayJoinStepSpec {
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "request", "hex32", "step", "name", "note", "text", "at", "int"))
}

function Get-HordeRelayJoinClosedSpec {
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "request", "hex32", "outcome", "name", "reason", "text", "closedAt", "int"))
}

function Get-HordeRelayJoinTranscriptSpec {
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "request", "hex32", "horde", "name", "machine", "hex32", "offer", "hex32",
        "challenge", "b64u", "device", "hex32", "credentialId", "b64u", "publicKey", "point", "rpId", "rpid", "label", "label", "agent", "text",
        "country", "text", "requestedAt", "int", "expiresAt", "int"))
}

function Get-HordeRelayJoinOfferSealedSpec {
    return (New-HordeRelayRecordSpec -Pairs @("v", "int", "kind", "name", "request", "hex32", "requestKeyId", "hex32", "enc", "point", "ct", "b64u"))
}

function Get-HordeRelayJoinKey {
    # The relay key a join request is put under (the header, 1).
    param([Parameter(Mandatory = $true)][string]$Request)
    return ("join/" + $Request)
}

function Get-HordeRelayJoinReplyMailbox {
    # Where the machine's sealed offer goes for the new phone (the header, 2).
    param([Parameter(Mandatory = $true)][string]$Horde, [Parameter(Mandatory = $true)][string]$Request)
    return ($Horde + "/jr-" + $Request)
}

function Test-HordeRelayJoinRequestText {
    # Does -Text say it is a join request (its first members)? Only a routing question.
    param([AllowNull()][AllowEmptyString()][string]$Text)
    return ($null -ne $Text -and $Text.StartsWith('{"v":1,"kind":"horde-relay-join-request",'))
}

function Get-HordeRelayJoinDir {
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][string]$Part)
    return ([System.IO.Path]::Combine((Get-HordeRelayStateDir -HordeHome $HordeHome -Part "join"), $Part))
}

function Read-HordeRelayJoinFolder {
    # Every record of one join folder: { ok; reason; records } - each { name; value }.
    param([string]$HordeHome = "", [string]$Part, [string]$Pattern, [object[]]$Spec, [string]$Kind)
    $dir = Get-HordeRelayJoinDir -HordeHome $HordeHome -Part $Part
    $list = Get-HordeRelayRecordNames -Dir $dir -Pattern $Pattern
    if (-not $list.ok) { return [pscustomobject]@{ ok = $false; reason = $list.reason; records = @() } }
    $out = New-Object System.Collections.ArrayList
    foreach ($n in @($list.names)) {
        $f = Read-HordeRelayRecordFile -Path ([System.IO.Path]::Combine($dir, $n))
        if (-not $f.ok) { return [pscustomobject]@{ ok = $false; reason = $f.reason; records = @() } }
        $r = Read-HordeRelayRecordText -Text $f.text -Spec $Spec -Kind $Kind -What ("the join record " + $n)
        if (-not $r.ok) { return [pscustomobject]@{ ok = $false; reason = $r.reason; records = @() } }
        [void]$out.Add([pscustomobject]@{ name = $n; value = $r.value })
    }
    return [pscustomobject]@{ ok = $true; reason = ""; records = @($out.ToArray()) }
}

function Get-HordeRelayJoins {
    # Every join request this machine received, as it stands at -Now: known list of { request (the
    # received record); steps (hashtable step -> note); closed (the closed record or $null); offer (the
    # offered id or ""); device (the trust store's device the offer enrolled, or $null); expired; open }
    # - open: not closed and not past its expiresAt. Unknown when a record or the trust store is damaged.
    param([string]$HordeHome = "", $Now = $null)
    try {
        $reqs = Read-HordeRelayJoinFolder -HordeHome $HordeHome -Part "requests" -Pattern '\A[0-9a-f]{32}\.json\z' -Spec (Get-HordeRelayJoinReceivedSpec) -Kind "horde-relay-join-received"
        $steps = Read-HordeRelayJoinFolder -HordeHome $HordeHome -Part "steps" -Pattern '\A[0-9a-f]{32}-[a-z0-9][a-z0-9-]{0,30}\.json\z' -Spec (Get-HordeRelayJoinStepSpec) -Kind "horde-relay-join-step"
        $closed = Read-HordeRelayJoinFolder -HordeHome $HordeHome -Part "closed" -Pattern '\A[0-9a-f]{32}\.json\z' -Spec (Get-HordeRelayJoinClosedSpec) -Kind "horde-relay-join-closed"
    } catch { return (New-HordeUnknown -Reason ("the join records cannot be read: " + $_.Exception.Message)) }
    foreach ($x in @($reqs, $steps, $closed)) { if (-not $x.ok) { return (New-HordeUnknown -Reason ("the join records are damaged: " + $x.reason)) } }
    $store = Read-HordeRelayTrustStore -HordeHome $HordeHome -Now $Now
    if (-not $store.ok) { return (New-HordeUnknown -Reason $store.reason) }
    $nowMs = ConvertTo-HordeRelayRecordMs -Time $Now
    $out = New-Object System.Collections.ArrayList
    foreach ($r in @($reqs.records)) {
        $q = $r.value
        if ($r.name -cne ($q.request + ".json")) { return (New-HordeUnknown -Reason ("the join record " + $r.name + " is filed under another request's name")) }
        $st = @{}
        foreach ($s in @($steps.records | Where-Object { $_.value.request -ceq $q.request })) { $st[$s.value.step] = $s.value.note }
        $c = @($closed.records | Where-Object { $_.value.request -ceq $q.request } | ForEach-Object { $_.value }) | Select-Object -First 1
        $offer = $(if ($st.ContainsKey("offered")) { "" + $st["offered"] } else { "" })
        $dev = $null
        if ($offer -cne "") { $dev = @($store.devices | Where-Object { $_.offer -ceq $offer }) | Select-Object -First 1 }
        $expired = ($nowMs -gt $q.expiresAt)
        [void]$out.Add([pscustomobject]@{ request = $q; steps = $st; closed = $c; offer = $offer; device = $dev; expired = $expired; open = ($null -eq $c -and -not $expired) })
    }
    return (New-HordeKnown -Value @($out.ToArray()))
}

function Get-HordeRelayJoin {
    # One join, as Get-HordeRelayJoins answers it, or absent.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][string]$Request, $Now = $null)
    if ($Request -cnotmatch '\A[0-9a-f]{32}\z') { return (New-HordeAbsent -Note ("'" + $Request + "' is not a join request id (32 hex)")) }
    $all = Get-HordeRelayJoins -HordeHome $HordeHome -Now $Now
    if ($all.state -cne "known") { return $all }
    $j = @($all.value | Where-Object { $_.request.request -ceq $Request }) | Select-Object -First 1
    if ($null -eq $j) { return (New-HordeAbsent -Note ("this machine has no join request " + $Request)) }
    return (New-HordeKnown -Value $j)
}

function Add-HordeRelayJoinStep {
    # Record that -Step was done for -Request, once: "moved" (now), "exists" (before), or the reason.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][string]$Request, [Parameter(Mandatory = $true)][string]$Step, [string]$Note = "", $Now = $null)
    try {
        $t = ConvertTo-HordeRelayRecordText -Spec (Get-HordeRelayJoinStepSpec) -Values @{ v = 1; kind = "horde-relay-join-step"; request = $Request; step = $Step; note = $Note; at = (ConvertTo-HordeRelayRecordMs -Time $Now) }
        return (Write-HordeRelayRecordFile -Dir (Get-HordeRelayJoinDir -HordeHome $HordeHome -Part "steps") -Name ($Request + "-" + $Step + ".json") -Text $t)
    } catch { return ("the step " + $Step + " could not be recorded: " + $_.Exception.Message) }
}

function Close-HordeRelayJoin {
    # The end of a join request, once: "moved" (now), "exists" (it had ended), or the reason.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][string]$Request, [Parameter(Mandatory = $true)][string]$Outcome, [string]$Reason = "", $Now = $null)
    if (@("approved", "rejected", "expired", "ended") -cnotcontains $Outcome) { throw ("a join ends approved, rejected, expired or ended, not '" + $Outcome + "'") }
    $why = $(if ($Reason.Length -gt 512) { $Reason.Substring(0, 512) } else { $Reason })
    $why = [regex]::Replace($why, '[^\x20\x21\x23-\x5B\x5D-\x7E]', '?')
    try {
        $t = ConvertTo-HordeRelayRecordText -Spec (Get-HordeRelayJoinClosedSpec) -Values @{ v = 1; kind = "horde-relay-join-closed"; request = $Request; outcome = $Outcome; reason = $why; closedAt = (ConvertTo-HordeRelayRecordMs -Time $Now) }
        return (Write-HordeRelayRecordFile -Dir (Get-HordeRelayJoinDir -HordeHome $HordeHome -Part "closed") -Name ($Request + ".json") -Text $t)
    } catch { return ("the join could not be closed: " + $_.Exception.Message) }
}

function Receive-HordeRelayJoinRequest {
    # One join request item from this machine's mailbox (the header, 1): recorded, or refused. -Key is
    # the relay key it came under. { outcome; reason; request } - outcome done (recorded, now or
    # before), refused (never: say why), held (the records cannot be read now). Never throws.
    param([string]$HordeHome = "", [AllowNull()][AllowEmptyString()][string]$Text, [string]$Key = "", $Now = $null)
    $limits = Get-HordeRelayJoinLimits
    if ($null -eq $Text) { $Text = "" }
    if ($Text.Length -gt $limits.maxItemChars) { return (New-HordeRelayRefusedOutcome -Reason ("the join request is " + $Text.Length + " characters, over the " + $limits.maxItemChars + " one may be; it is not read")) }
    $r = Read-HordeRelayRecordText -Text $Text -Spec (Get-HordeRelayJoinRequestSpec) -Kind "horde-relay-join-request" -What "the join request"
    if (-not $r.ok) { return (New-HordeRelayRefusedOutcome -Reason $r.reason) }
    $q = $r.value
    # ONLY UNDER ITS OWN KEY: on the hosted relay only the join route, which holds the limits, puts there.
    if ($Key -cne (Get-HordeRelayJoinKey -Request $q.request)) { return (New-HordeRelayRefusedOutcome -Reason ("the join request " + $q.request + " came under the key '" + $Key + "', not join/" + $q.request + ": only the relay's join route puts one")) }
    $id = Get-HordeRelayMachineIdentity -HordeHome $HordeHome
    if ($id.state -cne "known") { return [pscustomobject]@{ outcome = "held"; reason = ("this machine's identity cannot be read: " + $id.reason); request = $q.request } }
    if ($q.horde -cne $id.value.horde) { return (New-HordeRelayRefusedOutcome -Reason ("the join request is for the horde " + $q.horde + ", not this one (" + $id.value.horde + ")")) }
    if ($q.machine -cne $id.value.sign.keyId) { return (New-HordeRelayRefusedOutcome -Reason ("the join request asks the machine " + $q.machine + ", not this one")) }
    $nowMs = ConvertTo-HordeRelayRecordMs -Time $Now
    if ($nowMs -gt $q.expiresAt) { return (New-HordeRelayRefusedOutcome -Reason ("the join request " + $q.request + " expired before it was read; nothing is retried: the phone asks again")) }
    $all = Get-HordeRelayJoins -HordeHome $HordeHome -Now $Now
    if ($all.state -cne "known") { return [pscustomobject]@{ outcome = "held"; reason = $all.reason; request = $q.request } }
    if (@($all.value | Where-Object { $_.request.request -ceq $q.request }).Count -gt 0) { return [pscustomobject]@{ outcome = "done"; reason = ("the join request " + $q.request + " was already received"); request = $q.request } }
    # ONE PENDING REQUEST AT A TIME (threat 2): the second is refused, never queued.
    $open = @($all.value | Where-Object { $_.open }) | Select-Object -First 1
    if ($null -ne $open) { return (New-HordeRelayRefusedOutcome -Reason ("another join request (" + $open.request.request + ") is pending on this machine; this one is refused, never queued: reject that one, or let it expire, and ask again")) }
    # Its life is the request's, and never past 10 minutes from now, whatever the relay or the phone said.
    $exp = [long][System.Math]::Min([double]$q.expiresAt, [double]($nowMs + $limits.ttlMs))
    try {
        $t = ConvertTo-HordeRelayRecordText -Spec (Get-HordeRelayJoinReceivedSpec) -Values @{ v = 1; kind = "horde-relay-join-received"; request = $q.request; horde = $q.horde; machine = $q.machine
            label = $q.label; agent = $q.agent; requestKey = $q.requestKey; country = $q.country; requestedAt = $q.requestedAt; expiresAt = $exp; receivedAt = $nowMs }
        $moved = Write-HordeRelayRecordFile -Dir (Get-HordeRelayJoinDir -HordeHome $HordeHome -Part "requests") -Name ($q.request + ".json") -Text $t
    } catch { return [pscustomobject]@{ outcome = "held"; reason = ("the join request could not be recorded: " + $_.Exception.Message); request = $q.request } }
    if ($moved -ceq "exists") { return [pscustomobject]@{ outcome = "done"; reason = ("the join request " + $q.request + " was already received"); request = $q.request } }
    if ($moved -cne "moved") { return [pscustomobject]@{ outcome = "held"; reason = "the join request's record has its name, but nothing says it reached the disk"; request = $q.request } }
    return [pscustomobject]@{ outcome = "done"; reason = ("the join request " + $q.request + " from '" + $q.label + "' is received"); request = $q.request }
}

function Get-HordeRelayJoinSealedDomain {
    param([Parameter(Mandatory = $true)][string]$Part, [string]$Horde = "", [string]$Request = "", [string]$RequestKeyId = "")
    if ($Part -ceq "info") { return ,(Get-HordeRelayAsciiBytes -Text "horde-relay/join/v1 offer-key") }
    return ,(Get-HordeRelayAsciiBytes -Text ("horde-relay/join/v1 offer aad`n" + $Horde + "`n" + $Request + "`n" + $RequestKeyId))
}

function New-HordeRelayJoinOfferSealedText {
    # The offer's text sealed to the request key of -Join's request (the header, 2): the item the new
    # phone opens in its reply mailbox. relay/js/protocol.js's openJoinOffer is its reader.
    param([Parameter(Mandatory = $true)]$Request, [Parameter(Mandatory = $true)][string]$OfferText)
    $pub = ConvertFrom-HordeRelayBase64Url -Text $Request.requestKey
    $kid = Get-HordeRelayKeyId -Public $pub
    $box = Protect-HordeRelayHpke -RecipientPublic $pub -Info (Get-HordeRelayJoinSealedDomain -Part "info") `
        -Aad (Get-HordeRelayJoinSealedDomain -Part "aad" -Horde $Request.horde -Request $Request.request -RequestKeyId $kid) -Plaintext (Get-HordeRelayAsciiBytes -Text $OfferText)
    return (ConvertTo-HordeRelayRecordText -Spec (Get-HordeRelayJoinOfferSealedSpec) -Values @{ v = 1; kind = "horde-relay-join-offer"; request = $Request.request; requestKeyId = $kid
        enc = (ConvertTo-HordeRelayBase64Url -Bytes $box.enc); ct = (ConvertTo-HordeRelayBase64Url -Bytes $box.sealed) })
}

function Get-HordeRelayJoinTranscriptText {
    # The transcript of a join whose passkey registered (the header, 4b): its canonical text, which is
    # what the trusted phones are sent and what an approval's hash covers. Known text; unknown when the
    # join has no pending or trusted device yet, or its offer cannot be read.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)]$Join)
    if ($null -eq $Join.device) { return (New-HordeUnknown -Reason "no passkey has registered for this join request yet") }
    try { $root = Get-HordeRelayStateDir -HordeHome $HordeHome -Part "pairing" } catch { return (New-HordeUnknown -Reason $_.Exception.Message) }
    $pf = Read-HordeRelayRecordFile -Path ([System.IO.Path]::Combine($root, "offers", ($Join.offer + ".json")))
    if (-not $pf.ok -or -not $pf.found) { return (New-HordeUnknown -Reason ("the offer " + $Join.offer + " of this join cannot be read")) }
    $p = Read-HordeRelayRecordText -Text $pf.text -Spec (Get-HordeRelayPendingSpec) -Kind "horde-relay-pairing-pending" -What ("the pending offer " + $Join.offer)
    if (-not $p.ok) { return (New-HordeUnknown -Reason $p.reason) }
    $q = $Join.request
    $d = $Join.device
    try {
        $t = ConvertTo-HordeRelayRecordText -Spec (Get-HordeRelayJoinTranscriptSpec) -Values @{ v = 1; kind = "horde-relay-join-transcript"; request = $q.request; horde = $q.horde; machine = $q.machine
            offer = $Join.offer; challenge = $p.value.challenge; device = $d.id; credentialId = $d.credentialId; publicKey = $d.publicKey; rpId = $d.rpId; label = $q.label; agent = $q.agent
            country = $q.country; requestedAt = $q.requestedAt; expiresAt = $q.expiresAt }
    } catch { return (New-HordeUnknown -Reason ("the transcript could not be written: " + $_.Exception.Message)) }
    return (New-HordeKnown -Value $t)
}

function Get-HordeRelayJoinTranscriptHash {
    # What an approval carries: SHA-256 of the domain and the transcript's text, as base64url.
    param([Parameter(Mandatory = $true)][string]$Text)
    return (ConvertTo-HordeRelayBase64Url -Bytes (Get-HordeRelaySha256 -Bytes (Get-HordeRelayAsciiBytes -Text ("horde-relay/join/v1 transcript`n" + $Text))))
}

function Get-HordeRelayJoinOpenPending {
    # -Request's join when it is open and its passkey PENDING (what an approval needs): { ok; reason;
    # value (the join) }.
    param([string]$HordeHome = "", [string]$Request, $Now = $null)
    $fail = [pscustomobject]@{ ok = $false; reason = ""; value = $null }
    $j = Get-HordeRelayJoin -HordeHome $HordeHome -Request $Request -Now $Now
    if ($j.state -cne "known") { $fail.reason = $j.reason; return $fail }
    $v = $j.value
    if ($null -ne $v.closed) { $fail.reason = ("the join request " + $Request + " is closed (" + $v.closed.outcome + "); it is approved once, and never again"); return $fail }
    if ($v.expired) { $fail.reason = ("the join request " + $Request + " expired; nothing is approved after its 10 minutes"); return $fail }
    if ($null -eq $v.device) { $fail.reason = ("no passkey has registered for the join request " + $Request + " yet: the new phone must make it first"); return $fail }
    if ($v.device.state -cne "pending") { $fail.reason = ("the join request's passkey is " + $v.device.state + ", not pending"); return $fail }
    return [pscustomobject]@{ ok = $true; reason = ""; value = $v }
}

function Approve-HordeRelayJoin {
    # THE FOUNDER AT THIS MACHINE (the header, 4a): -Number is what the NEW phone shows; compared with
    # the number this machine computed (Confirm-HordeRelayDevice). A wrong one counts; the third rejects
    # the request. { ok; reason; value (the trusted device) }.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][string]$Request, [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Number, $Now = $null)
    $fail = [pscustomobject]@{ ok = $false; reason = ""; value = $null }
    $o = Get-HordeRelayJoinOpenPending -HordeHome $HordeHome -Request $Request -Now $Now
    if (-not $o.ok) { $fail.reason = $o.reason; return $fail }
    $c = Confirm-HordeRelayDevice -HordeHome $HordeHome -Id $o.value.device.id -Fingerprint $Number -Now $Now
    if ($c.ok) { return [pscustomobject]@{ ok = $true; reason = ""; value = $c.value.device } }
    if (-not $c.reason.Contains("does not match")) { $fail.reason = $c.reason; return $fail }
    $limits = Get-HordeRelayJoinLimits
    $tries = @($o.value.steps.Keys | Where-Object { $_ -cmatch '\Atry-[0-9]+\z' }).Count + 1
    $null = Add-HordeRelayJoinStep -HordeHome $HordeHome -Request $Request -Step ("try-" + $tries) -Now $Now
    if ($tries -ge $limits.tries) {
        $rj = Reject-HordeRelayJoin -HordeHome $HordeHome -Request $Request -Reason ("the number typed at the machine did not match the new phone's, " + $limits.tries + " times") -Now $Now
        $fail.reason = ("that number does not match either, " + $limits.tries + " times: the join request is rejected" + $(if ($rj.ok) { "" } else { " (" + $rj.reason + ")" }))
        return $fail
    }
    $fail.reason = ("that number does not match the one this machine computed for the new phone (" + ($limits.tries - $tries) + " tries left). If the new phone shows another number, it is not the phone that registered: reject it")
    return $fail
}

function Approve-HordeRelayJoinByPhone {
    # A TRUSTED PHONE'S APPROVAL (the header, 4b), already verified as an envelope signed by a trusted
    # passkey with user verification (channels/join). Trust is granted only when -Device is this
    # request's pending passkey and -Transcript is the hash of the transcript this machine computes now.
    # { ok; reason; value (the trusted device) }.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][string]$Request, [Parameter(Mandatory = $true)][string]$Device, [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Transcript,
        [Parameter(Mandatory = $true)][string]$From, $Now = $null)
    $fail = [pscustomobject]@{ ok = $false; reason = ""; value = $null }
    $o = Get-HordeRelayJoinOpenPending -HordeHome $HordeHome -Request $Request -Now $Now
    if (-not $o.ok) { $fail.reason = $o.reason; return $fail }
    $j = $o.value
    if ($j.device.id -cne $Device) { $fail.reason = ("the approval names the device " + $Device + ", not the passkey that registered for this request"); return $fail }
    if ($j.device.keyId -ceq $From) { $fail.reason = "a passkey does not approve itself"; return $fail }
    $t = Get-HordeRelayJoinTranscriptText -HordeHome $HordeHome -Join $j
    if ($t.state -cne "known") { $fail.reason = $t.reason; return $fail }
    $want = Get-HordeRelayJoinTranscriptHash -Text $t.value
    if (-not (Test-HordeRelayBytesEqual -Left (Get-HordeRelayAsciiBytes -Text $want) -Right (Get-HordeRelayAsciiBytes -Text $Transcript))) {
        $fail.reason = "the approval's transcript hash is not the one of this request's transcript: a replayed or swapped approval, or one for another phone; nothing is trusted"
        return $fail
    }
    $c = Add-HordeRelayDeviceConfirmation -HordeHome $HordeHome -Id $Device -Now $Now
    if ($c.state -cne "known") { $fail.reason = $c.reason; return $fail }
    return [pscustomobject]@{ ok = $true; reason = ""; value = $c.value.device }
}

function Reject-HordeRelayJoin {
    # Reject -Request (the CLI, or a trusted phone's envelope): its pending passkey, if one registered,
    # is revoked, and the request is closed rejected. A request already approved is not rejected here
    # (its passkey is trusted: revoke it with relay trust revoke). { ok; reason }.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][string]$Request, [string]$Reason = "rejected", $Now = $null)
    $j = Get-HordeRelayJoin -HordeHome $HordeHome -Request $Request -Now $Now
    if ($j.state -cne "known") { return [pscustomobject]@{ ok = $false; reason = $j.reason } }
    $v = $j.value
    if ($null -ne $v.closed) { return [pscustomobject]@{ ok = ($v.closed.outcome -ceq "rejected"); reason = ("the join request is already closed (" + $v.closed.outcome + ")") } }
    if ($null -ne $v.device -and $v.device.state -ceq "trusted") { return [pscustomobject]@{ ok = $false; reason = ("the join request was approved: its passkey " + $v.device.id + " is trusted; to end it, horde relay trust revoke " + $v.device.id) } }
    if ($null -ne $v.device -and $v.device.state -ceq "pending") {
        $rv = Revoke-HordeRelayTrust -HordeHome $HordeHome -Subject "device" -Id $v.device.id -Reason ("join request rejected: " + $Reason) -Now $Now
        if ($rv.state -cne "known") { return [pscustomobject]@{ ok = $false; reason = ("the join request's passkey could not be revoked: " + $rv.reason) } }
    }
    if ($v.offer -cne "") { $null = Close-HordeRelayPairingOffer -HordeHome $HordeHome -Offer $v.offer -Now $Now }
    $c = Close-HordeRelayJoin -HordeHome $HordeHome -Request $Request -Outcome "rejected" -Reason $Reason -Now $Now
    if ($c -cne "moved" -and $c -cne "exists") { return [pscustomobject]@{ ok = $false; reason = $c } }
    return [pscustomobject]@{ ok = $true; reason = ("the join request " + $Request + " is rejected") }
}

function Update-HordeRelayJoinEnds {
    # Close what has ended by itself, at -Now (the header, REJECTED, EXPIRED, REVOKED): an open request
    # whose passkey became trusted is approved; one whose passkey was revoked or expired is ended; one
    # past its 10 minutes is expired - its offer voided, its pending passkey revoked. Known list of
    # { request; outcome } closed now; unknown when the records cannot be read.
    param([string]$HordeHome = "", $Now = $null)
    $all = Get-HordeRelayJoins -HordeHome $HordeHome -Now $Now
    if ($all.state -cne "known") { return $all }
    $out = New-Object System.Collections.ArrayList
    foreach ($j in @($all.value | Where-Object { $null -eq $_.closed })) {
        $id = $j.request.request
        $outcome = ""
        $why = ""
        if ($null -ne $j.device -and $j.device.state -ceq "trusted") { $outcome = "approved"; $why = "its passkey was confirmed by the number" }
        elseif ($j.expired) {
            # Past its 10 minutes the request is expired, whatever its passkey's own confirm window says,
            # and a passkey it registered is revoked for good: an expired request leaves no trace of trust.
            $outcome = "expired"; $why = "nobody approved it within its 10 minutes"
            if ($null -ne $j.device -and $j.device.state -cne "revoked") { $null = Revoke-HordeRelayTrust -HordeHome $HordeHome -Subject "device" -Id $j.device.id -Reason "join request expired" -Now $Now }
            if ($j.offer -cne "") { $null = Close-HordeRelayPairingOffer -HordeHome $HordeHome -Offer $j.offer -Now $Now }
        }
        elseif ($null -ne $j.device -and ($j.device.state -ceq "revoked" -or $j.device.state -ceq "expired")) { $outcome = "ended"; $why = ("its passkey was " + $j.device.state) }
        if ($outcome -ceq "") { continue }
        $c = Close-HordeRelayJoin -HordeHome $HordeHome -Request $id -Outcome $outcome -Reason $why -Now $Now
        if ($c -ceq "moved") { [void]$out.Add([pscustomobject]@{ request = $id; outcome = $outcome }) }
    }
    return (New-HordeKnown -Value @($out.ToArray()))
}
