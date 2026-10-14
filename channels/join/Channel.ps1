# channels/join - PHONE-STARTED PAIRING ("Add this phone"), carried: relay/Join.ps1 has every rule; this
# channel moves its messages. The founder, 2026-10-14: "allow pairing requests to start from the new
# phone once the Horde is already associated with a gmail account that was logged into."
#
# IN, kinds approve and reject, from the founder's TRUSTED passkeys only (an envelope signed with user
# verification, as every answer is - never a plain web click):
#   approve  {"v":1,"request":"<32 hex>","device":"<32 hex>","transcript":"<base64url SHA-256>"} - the
#            trusted phone typed the number the new phone shows, computed it itself from the transcript
#            this machine sent it, and they matched. Approve-HordeRelayJoinByPhone grants trust only when
#            the hash is the one of this request's transcript now.
#   reject   {"v":1,"request":"<32 hex>"} - Reject-HordeRelayJoin.
#   done once the approval or the reject is applied; refused, final, otherwise (a closed, expired,
#   approved or unknown request; another device; another transcript; a malformed body).
# The join REQUEST itself is no envelope: it arrives in this machine's mailbox as an item channels/Port.ps1
# hands to relay/Join.ps1 (Receive-HordeRelayJoinRequest), which records it.
#
# THE TICK, every turn, for every request recorded (each step done once, recorded in relay/Join.ps1's
# steps, so a run killed half way does the rest next turn and nothing twice):
#   - ends what ended by itself: approved (its passkey confirmed), expired (its 10 minutes), ended (its
#     passkey revoked) - Update-HordeRelayJoinEnds;
#   - OPEN: answers AT ONCE with a pairing offer sealed to the request key, in the reply mailbox; tells
#     every trusted device (a notice: who asks, browser, country, time, how to approve or reject, and "if
#     this is not your phone, reject it and change your Google password"); asks it as a decisions question
#     (do then say: what to do at this PC or on a trusted phone - never a place to type the number, which
#     would travel); reads the offer's pairing mailbox for the new phone's passkey and enrolls it PENDING;
#     once it is, sends the TRANSCRIPT to the trusted phones (kind request, sealed to their keys);
#   - CLOSED: tells the new phone it is confirmed (approved only: relay/Pairing.ps1's confirmed record);
#     tells the relay (the hosted one frees the account's one pending slot, and a reject blocks the
#     asking address for the hour: relays/Port.ps1, Close-HordeRelayJoinAtRelay); tells every trusted
#     device the outcome; closes the question; tells the trusted phones (kind closed).
# A step that fails is said, counts as a failed send (the runner backs off), and is tried next turn.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "notices\Decide.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "decisions\Operations.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\Device.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\JsonText.ps1")

$script:HordeJoinChannelFolder = $PSScriptRoot

function Get-HordeJoinChannelId {
    # A decisions request id of this join's own, so a repeated add or close is the same request: the
    # first 16 bytes of SHA-256 of what it is for, as hex.
    param([Parameter(Mandatory = $true)][string]$For)
    $h = Get-HordeRelaySha256 -Bytes (Get-HordeRelayAsciiBytes -Text ("horde-join/v1 " + $For))
    $first = New-Object byte[] 16
    [System.Array]::Copy($h, 0, $first, 0, 16)
    return (ConvertTo-HordeRelayHex -Bytes $first)
}

function Get-HordeJoinChannelWho {
    # The new phone as every notice and question names it: its name, browser, country and time (UTC).
    param($Request)
    $t = [System.DateTimeOffset]::FromUnixTimeMilliseconds([long]$Request.requestedAt).UtcDateTime.ToString("yyyy-MM-dd HH:mm 'UTC'", [System.Globalization.CultureInfo]::InvariantCulture)
    $parts = @("'" + $Request.label + "'")
    if ("" + $Request.agent -cne "") { $parts += $Request.agent }
    $parts += $(if ("" + $Request.country -cne "") { $Request.country } else { "country unknown" })
    $parts += $t
    return ($parts -join ", ")
}

function Read-HordeJoinChannelBody {
    # An approve or reject body, read strictly: { ok; reason; value }.
    param([AllowEmptyCollection()][byte[]]$Body, [string]$Kind)
    $fail = [pscustomobject]@{ ok = $false; reason = ""; value = $null }
    $strict = New-Object System.Text.UTF8Encoding -ArgumentList $false, $true
    try { $text = $strict.GetString($Body) } catch { $fail.reason = "the body is not UTF-8"; return $fail }
    if (-not $text.TrimStart().StartsWith("{")) { $fail.reason = "the body is not a JSON object"; return $fail }
    $dups = @(Find-HordeJsonDuplicateKey -Text $text)
    if ($dups.Count -gt 0) { $fail.reason = ("the body has a member more than once: " + $dups[0]); return $fail }
    try { $b = ConvertFrom-Json -InputObject $text } catch { $fail.reason = "the body is not JSON"; return $fail }
    if ($b -isnot [System.Management.Automation.PSCustomObject]) { $fail.reason = "the body is not a JSON object"; return $fail }
    $want = $(if ($Kind -ceq "approve") { @("device", "request", "transcript", "v") } else { @("request", "v") })
    $names = @($b.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object)
    if (($names -join ",") -cne ($want -join ",")) { $fail.reason = ("the body's members are " + ($names -join ", ") + ", not " + ($want -join ", ")); return $fail }
    if (-not ($b.v -is [int] -or $b.v -is [long]) -or $b.v -ne 1) { $fail.reason = "the body is not version 1"; return $fail }
    if ($b.request -isnot [string] -or $b.request -cnotmatch '\A[0-9a-f]{32}\z') { $fail.reason = "the request is not a join request id"; return $fail }
    if ($Kind -ceq "approve") {
        if ($b.device -isnot [string] -or $b.device -cnotmatch '\A[0-9a-f]{32}\z') { $fail.reason = "the device is not a device id"; return $fail }
        if ($b.transcript -isnot [string] -or $b.transcript -cnotmatch '\A[A-Za-z0-9_-]{43}\z') { $fail.reason = "the transcript is not a SHA-256 in base64url"; return $fail }
    }
    return [pscustomobject]@{ ok = $true; reason = ""; value = $b }
}

function Invoke-HordeJoinChannelAccept {
    # One opened approve or reject (the header, IN). { outcome; reason }.
    param($Context, $Item)
    $r = Read-HordeJoinChannelBody -Body $Item.body -Kind $Item.kind
    if (-not $r.ok) { return [pscustomobject]@{ outcome = "refused"; reason = $r.reason } }
    $b = $r.value
    if ($Item.kind -ceq "approve") {
        $a = Approve-HordeRelayJoinByPhone -HordeHome $Context.hordeHome -Request $b.request -Device $b.device -Transcript $b.transcript -From $Item.from
        if (-not $a.ok) { return [pscustomobject]@{ outcome = "refused"; reason = ("the approval is refused: " + $a.reason) } }
        return [pscustomobject]@{ outcome = "done"; reason = ("the join request " + $b.request + " is approved by the trusted passkey " + $Item.from + ": the device " + $b.device + " is trusted") }
    }
    $j = Reject-HordeRelayJoin -HordeHome $Context.hordeHome -Request $b.request -Reason ("rejected on the trusted phone " + $Item.from)
    if (-not $j.ok) { return [pscustomobject]@{ outcome = "refused"; reason = ("the reject is refused: " + $j.reason) } }
    return [pscustomobject]@{ outcome = "done"; reason = $j.reason }
}

function Get-HordeJoinChannelOrigin {
    # The phone app the offer names (relay settings pairRpId and pairOrigin, as horde relay pair reads
    # them). Known { rpId; origins }, or unknown saying what to set.
    param([string]$HordeHome)
    $s = Get-HordeRelaySettingValues -HordeHome $HordeHome
    if ($s.state -cne "known") { return $s }
    $rp = "" + $s.value.values.pairRpId
    $or = "" + $s.value.values.pairOrigin
    if ($rp -ceq "" -or $or -ceq "") { return (New-HordeUnknown -Reason "no phone app is named: set pairRpId and pairOrigin in the relay settings (settings\relay.json)") }
    return (New-HordeKnown -Value ([pscustomobject]@{ rpId = $rp; origins = @($or) }))
}

function Send-HordeJoinChannelOffer {
    # The answer, at once (the header): a pairing offer for the request's life, sealed to its key, in its
    # reply mailbox. "" when sent, else why not. An offer whose put failed is voided.
    param($Context, $Join, $Now)
    $q = $Join.request
    $where = Get-HordeJoinChannelOrigin -HordeHome $Context.hordeHome
    if ($where.state -cne "known") { return $where.reason }
    $nowMs = ConvertTo-HordeRelayRecordMs -Time $Now
    $ttl = [int][System.Math]::Max(30, [System.Math]::Min(900, [System.Math]::Ceiling(($q.expiresAt - $nowMs) / 1000)))
    $o = New-HordeRelayPairingOffer -HordeHome $Context.hordeHome -RpId $where.value.rpId -Origins $where.value.origins -TtlSeconds $ttl -Now $Now -Label (ConvertTo-HordeDeviceName -Text "$env:COMPUTERNAME")
    if ($o.state -cne "known") { return ("no offer was made: " + $o.reason) }
    $sealed = New-HordeRelayJoinOfferSealedText -Request $q -OfferText $o.value.text
    $put = Send-HordeRelayItem -Connection $Context.connection -Mailbox (Get-HordeRelayJoinReplyMailbox -Horde $q.horde -Request $q.request) -Text $sealed -Key ("offer/" + $q.request)
    if ($put.state -cne "known") { $null = Close-HordeRelayPairingOffer -HordeHome $Context.hordeHome -Offer $o.value.offer; return ("the offer did not reach the relay: " + $put.reason) }
    $s = Add-HordeRelayJoinStep -HordeHome $Context.hordeHome -Request $q.request -Step "offered" -Note $o.value.offer -Now $Now
    if ($s -cne "moved" -and $s -cne "exists") { return $s }
    return ""
}

function Receive-HordeJoinChannelPasskey {
    # The new phone's sealed response, from the offer's pairing mailbox, enrolled PENDING
    # (relay/Pairing.ps1). "" when one was, or nothing came yet; else why not.
    param($Context, $Join, $Now)
    $mb = Get-HordeRelayPairingMailbox -Horde $Join.request.horde -Offer $Join.offer
    $got = Receive-HordeRelayItems -Connection $Context.connection -Mailbox $mb -Since 0 -Max 16
    if ($got.state -cne "known") { return ("the pairing mailbox could not be read: " + $got.reason) }
    $last = [long]0
    $said = ""
    foreach ($item in @($got.value.items)) {
        $last = [long]$item.seq
        $o = Open-HordeRelayPairingSealed -HordeHome $Context.hordeHome -Offer $Join.offer -Text $item.text -Now $Now
        if (-not $o.ok) { $said = ("refused what the pairing mailbox brought: " + $o.reason); continue }
        $c = Complete-HordeRelayPairing -HordeHome $Context.hordeHome -Response $o.value -Label $Join.request.label -Now $Now
        if ($c.ok) { $said = ""; break }
        $said = ("the new phone's passkey is refused: " + $c.reason)
    }
    if ($last -gt 0) { $null = Confirm-HordeRelayItems -Connection $Context.connection -Mailbox $mb -Through $last }
    return $said
}

function Invoke-HordeJoinChannelTick {
    # The header, THE TICK. { lines; failed }.
    param($Context, $Now = $null)
    $lines = New-Object System.Collections.ArrayList
    $failed = $false
    # -Now: a suite's moment; the runner's Tick is now.
    $now = $(if ($null -ne $Now) { $Now } else { [datetime]::UtcNow })
    $ends = Update-HordeRelayJoinEnds -HordeHome $Context.hordeHome -Now $now
    if ($ends.state -cne "known") { return [pscustomobject]@{ lines = @("join: the join records cannot be read: " + $ends.reason); failed = $true } }
    foreach ($e in @($ends.value)) { [void]$lines.Add("join: the request " + $e.request + " is " + $e.outcome) }
    $all = Get-HordeRelayJoins -HordeHome $Context.hordeHome -Now $now
    if ($all.state -cne "known") { return [pscustomobject]@{ lines = @("join: " + $all.reason); failed = $true } }
    $phoneMailbox = $Context.horde + "/phone"
    foreach ($j in @($all.value)) {
        $q = $j.request
        $id = $q.request
        $who = Get-HordeJoinChannelWho -Request $q
        $step = { param($Name, $Note) $null = Add-HordeRelayJoinStep -HordeHome $Context.hordeHome -Request $id -Step $Name -Note $Note -Now $now }
        $fail = { param($Why) [void]$lines.Add("join: " + $id + ": " + $Why); $script:HordeJoinTickFailed = $true }
        $script:HordeJoinTickFailed = $false
        if ($j.open) {
            if (-not $j.steps.ContainsKey("offered")) {
                $why = Send-HordeJoinChannelOffer -Context $Context -Join $j -Now $now
                if ($why -cne "") { & $fail $why } else { [void]$lines.Add("join: answered the request " + $id + " from " + $who + " with an offer") }
            }
            if (-not $j.steps.ContainsKey("noticed")) {
                $n = Submit-HordeSystemNotice -HordeHome $Context.hordeHome -Now $now -Text ("A new phone asks to join this PC: " + $who + ". If this is not your phone, reject it and change your Google password. To approve, type the number it shows on a trusted phone, or at this PC (horde relay joins).")
                if ($n.outcome -ceq "failed") { & $fail ("the notice was not written: " + $n.reason) } else { & $step "noticed" "" }
            }
            if (-not $j.steps.ContainsKey("asked")) {
                $a = Invoke-HordeDecision -Operation "add" -Root $Context.decisionsRoot -Now $now -Request @{ id = (Get-HordeJoinChannelId -For ("ask " + $id)); actor = "warchief"; importance = "high"
                    question = @{ title = ("A new phone asks to join: " + $who); kind = "do-then-say"; group = "security"; askedBy = "relay"
                        whatItIs = ("Approve only if it is your phone: read the 12-digit number on the NEW phone and type it at this PC (horde relay approve " + $id + " <number>) or on a trusted phone's join request - never here. If this is not your phone, reject it (horde relay reject " + $id + ") and change your Google password. It expires by itself in 10 minutes.") } }
                if ($a.state -ceq "known" -and $a.value.outcome -cne "refused" -and $null -ne $a.value.PSObject.Properties["number"]) { & $step "asked" ("" + $a.value.number) }
                else { & $fail ("the decisions question was not asked: " + $(if ($a.state -ceq "known") { $a.value.reason } else { $a.reason })) }
            }
            if ($j.steps.ContainsKey("offered") -and $null -eq $j.device) {
                $why = Receive-HordeJoinChannelPasskey -Context $Context -Join $j -Now $now
                if ($why -cne "") { [void]$lines.Add("join: " + $id + ": " + $why) }
            }
            $again = Get-HordeRelayJoin -HordeHome $Context.hordeHome -Request $id -Now $now
            if ($again.state -ceq "known" -and $null -ne $again.value.device -and $again.value.device.state -ceq "pending" -and -not $again.value.steps.ContainsKey("transcript")) {
                $t = Get-HordeRelayJoinTranscriptText -HordeHome $Context.hordeHome -Join $again.value
                $phones = Find-HordeRelayPhoneKeys -HordeHome $Context.hordeHome -Now $now
                if ($t.state -cne "known") { & $fail $t.reason }
                elseif ($phones.state -cne "known") { & $fail ("the trusted phones cannot be read: " + $phones.reason) }
                elseif (@($phones.value).Count -eq 0) { & $step "transcript" "no trusted phone: approve at this PC" }
                else {
                    $sent = Send-HordeRelayChannelEnvelope -Context $Context -Channel "join" -Kind "request" -Body (Get-HordeRelayAsciiBytes -Text $t.value) -Recipients @($phones.value | ForEach-Object { , ([byte[]]$_.public) }) -Mailbox $phoneMailbox -Now $now
                    if ($sent.state -ceq "known") { & $step "transcript" ""; [void]$lines.Add("join: the new phone's passkey registered for " + $id + "; its transcript is sent to " + @($phones.value).Count + " trusted phone(s)") }
                    else { & $fail ("the transcript did not reach the trusted phones: " + $sent.reason) }
                }
            }
        } elseif ($null -ne $j.closed) {
            $outcome = $j.closed.outcome
            if ($outcome -ceq "approved" -and -not $j.steps.ContainsKey("confirmed") -and $null -ne $j.device) {
                $w = New-HordeRelayPairingConfirmedText -HordeHome $Context.hordeHome -Offer $j.offer -Device $j.device.id -Now $now
                if ($w.state -ceq "known") {
                    $put = Send-HordeRelayItem -Connection $Context.connection -Mailbox (Get-HordeRelayPairingMailbox -Horde $q.horde -Offer $j.offer) -Text $w.value.text -Key $w.value.key
                    if ($put.state -ceq "known") { & $step "confirmed" "" } else { & $fail ("the new phone was not told it is confirmed: " + $put.reason) }
                } else { & $fail ("the confirmed record was not made: " + $w.reason) }
            }
            if (-not $j.steps.ContainsKey("told")) {
                $tl = Close-HordeRelayJoinAtRelay -Connection $Context.connection -Request $id -Outcome $outcome
                if ($tl.state -ceq "known") { & $step "told" $(if ($tl.value.asked) { "freed " + $tl.value.freed } else { "no join route" }) } else { & $fail ("the relay was not told the request ended: " + $tl.reason) }
            }
            if (-not $j.steps.ContainsKey("endnoticed")) {
                $n = Submit-HordeSystemNotice -HordeHome $Context.hordeHome -Now $now -Text ("The new phone " + $who + " was " + $outcome + ": " + $j.closed.reason + ".")
                if ($n.outcome -ceq "failed") { & $fail ("the notice was not written: " + $n.reason) } else { & $step "endnoticed" "" }
            }
            if ($j.steps.ContainsKey("asked") -and -not $j.steps.ContainsKey("unasked")) {
                $c = Invoke-HordeDecision -Operation "close" -Root $Context.decisionsRoot -Now $now -Request @{ id = (Get-HordeJoinChannelId -For ("close " + $id)); actor = "warchief"; number = [int]$j.steps["asked"]; outcome = ("The new phone was " + $outcome + ": " + $j.closed.reason) }
                if ($c.state -ceq "known" -and ($c.value.outcome -cne "refused" -or ("" + $c.value.reason).Contains("already closed"))) { & $step "unasked" "" }
                else { & $fail ("the decisions question was not closed: " + $(if ($c.state -ceq "known") { $c.value.reason } else { $c.reason })) }
            }
            if ($j.steps.ContainsKey("transcript") -and "" + $j.steps["transcript"] -ceq "" -and -not $j.steps.ContainsKey("phonesclosed")) {
                $phones = Find-HordeRelayPhoneKeys -HordeHome $Context.hordeHome -Now $now
                if ($phones.state -ceq "known" -and @($phones.value).Count -gt 0) {
                    $body = Get-HordeRelayAsciiBytes -Text ('{"v":1,"request":"' + $id + '","outcome":"' + $outcome + '"}')
                    $sent = Send-HordeRelayChannelEnvelope -Context $Context -Channel "join" -Kind "closed" -Body $body -Recipients @($phones.value | ForEach-Object { , ([byte[]]$_.public) }) -Mailbox $phoneMailbox -Now $now
                    if ($sent.state -ceq "known") { & $step "phonesclosed" "" } else { & $fail ("the trusted phones were not told the request ended: " + $sent.reason) }
                } else { & $step "phonesclosed" "no trusted phone" }
            }
        }
        if ($script:HordeJoinTickFailed) { $failed = $true }
    }
    return [pscustomobject]@{ lines = @($lines.ToArray()); failed = $failed }
}

$null = Register-HordeRelayChannel -Folder $script:HordeJoinChannelFolder -Name "join" -Kinds @("approve", "reject") -Senders "founder" `
    -Accept { param($Context, $Item) return (Invoke-HordeJoinChannelAccept -Context $Context -Item $Item) } `
    -Tick { param($Context) return (Invoke-HordeJoinChannelTick -Context $Context) }
