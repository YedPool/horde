# channels/trust - a phone announcing its identity key, vouched for by a founder passkey (relay design
# 2026-10-09, Q7; relay/Trust.ps1, PHONE KEYS).
#
# WHY A CHANNEL OF ITS OWN. A passkey signs and cannot open: what a machine seals for the founder (the
# decisions snapshot, later chat) goes to the phone identity key, which the phone makes and announces
# once, through the relay, to every machine of the horde. It belongs to no one channel that uses it, so
# it is not the decisions channel's: chat will seal to the same keys.
#
# IN, kind phone-key, from the founder's trusted passkeys only. The body is the phone's JSON:
#   {"v":1,"agreePublic":"<b64u>","authenticatorData":"<b64u>","clientDataJSON":"<b64u>","signature":"<b64u>"}
# - the key, and a SECOND passkey assertion (UV) over relay/Trust.ps1's vouch challenge for it in this
# horde, which the trust store keeps and verifies again on every read. The envelope's own signature
# proves who sent the body; the vouch is what stays provable once the envelope is gone, and it binds the
# horde. The vouch must be by the same passkey that signed the envelope.
#   done     the key is in the trust store (added now, or there already: its first vouch stands);
#   refused  the body, the vouch or the key is refused - final. The store was readable a moment before
#            (channels/Port.ps1 read the trusted senders to open this envelope), so a refusal here is
#            about this key; the rare write that fails is a refusal too, and the phone, seeing no
#            snapshot, announces its key again.
# IN, kind session: the opening of an unlocked phone session (Invoke-HordeTrustChannelSession, below).
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\JsonText.ps1")

$script:HordeTrustChannelFolder = $PSScriptRoot
$script:HordeTrustChannelMembers = @("v", "agreePublic", "authenticatorData", "clientDataJSON", "signature")

function Read-HordeTrustChannelBody {
    # The phone-key body, read strictly: { ok; reason; value } with value of byte arrays.
    param([AllowEmptyCollection()][byte[]]$Body)
    $fail = [pscustomobject]@{ ok = $false; reason = ""; value = $null }
    $strict = New-Object System.Text.UTF8Encoding -ArgumentList $false, $true
    try { $text = $strict.GetString($Body) } catch { $fail.reason = "the body is not UTF-8"; return $fail }
    if (-not $text.TrimStart().StartsWith("{")) { $fail.reason = "the body is not a JSON object"; return $fail }
    $dups = @(Find-HordeJsonDuplicateKey -Text $text)
    if ($dups.Count -gt 0) { $fail.reason = ("the body has a member more than once: " + $dups[0]); return $fail }
    try { $b = ConvertFrom-HordeJson -Text $text } catch { $fail.reason = "the body is not JSON"; return $fail }
    if ($b -isnot [System.Management.Automation.PSCustomObject]) { $fail.reason = "the body is not a JSON object"; return $fail }
    $names = @($b.PSObject.Properties | ForEach-Object { $_.Name })
    if ((@($names | Sort-Object) -join ",") -cne (@($script:HordeTrustChannelMembers | Sort-Object) -join ",")) { $fail.reason = ("the body's members are " + ($names -join ", ") + ", not " + ($script:HordeTrustChannelMembers -join ", ")); return $fail }
    if (-not ($b.v -is [int] -or $b.v -is [long]) -or $b.v -ne 1) { $fail.reason = "the body is not version 1"; return $fail }
    $out = @{}
    foreach ($m in @("agreePublic", "authenticatorData", "clientDataJSON", "signature")) {
        if ($b.$m -isnot [string]) { $fail.reason = ("the body's " + $m + " is not text"); return $fail }
        try { $out[$m] = [byte[]](ConvertFrom-HordeRelayBase64Url -Text $b.$m -What $m) } catch { $fail.reason = $_.Exception.Message; return $fail }
    }
    return [pscustomobject]@{ ok = $true; reason = ""; value = [pscustomobject]$out }
}

function Invoke-HordeTrustChannelAccept {
    # One opened phone-key announcement into the trust store. { outcome; reason }.
    param($Context, $Item)
    $r = Read-HordeTrustChannelBody -Body $Item.body
    if (-not $r.ok) { return [pscustomobject]@{ outcome = "refused"; reason = $r.reason } }
    $v = $r.value
    $added = Add-HordeRelayPhoneKey -HordeHome $Context.hordeHome -AgreePublic $v.agreePublic -By $Item.from -AuthenticatorData $v.authenticatorData -ClientDataJson $v.clientDataJSON -Signature $v.signature
    if ($added.state -cne "known") { return [pscustomobject]@{ outcome = "refused"; reason = ("the phone key is refused: " + $added.reason) } }
    return [pscustomobject]@{ outcome = "done"; reason = ("the phone key " + $added.value.record.agreeKeyId + " is " + $(if ($added.value.duplicate) { "already" } else { "now" }) + " in the trust store, vouched for by " + $added.value.record.by) }
}

function Invoke-HordeTrustChannelSession {
    # IN, kind session (relay/Session.ps1; relay/js/protocol.js, the opening): the envelope a phone sends
    # right after unlock, session-signed and carrying its vouch, so the PC records the vouch and starts
    # its idle clock before the first answer. By the time it is here the port has verified the vouch and
    # the session signature, recorded the vouch and journaled the envelope; this checks the body names
    # the same vouch, and says so. { outcome; reason }.
    param($Context, $Item)
    $p = $Item.PSObject.Properties["proof"]
    if ($null -eq $p -or "$($p.Value)" -cne "session") { return [pscustomobject]@{ outcome = "refused"; reason = "an opening is session-signed: this one is not" } }
    $text = ""
    try { $text = (New-Object System.Text.UTF8Encoding -ArgumentList $false, $true).GetString($Item.body) } catch { return [pscustomobject]@{ outcome = "refused"; reason = "the opening's body is not UTF-8" } }
    if ($text -cnotmatch '\A\{"v":1,"vouchId":"([0-9a-f]{32})"\}\z') { return [pscustomobject]@{ outcome = "refused"; reason = 'the opening body is not exactly {"v":1,"vouchId":"<32 hex>"}' } }
    if ($Matches[1] -cne $Item.vouchId) { return [pscustomobject]@{ outcome = "refused"; reason = ("the opening names the session " + $Matches[1] + " and is signed under " + $Item.vouchId) } }
    return [pscustomobject]@{ outcome = "done"; reason = ("the phone session " + $Item.vouchId + " of " + $Item.from + " is open") }
}

$null = Register-HordeRelayChannel -Folder $script:HordeTrustChannelFolder -Name "trust" -Kinds @("phone-key", "session") -Senders "founder" `
    -Accept { param($Context, $Item) if ($Item.kind -ceq "session") { return (Invoke-HordeTrustChannelSession -Context $Context -Item $Item) }; return (Invoke-HordeTrustChannelAccept -Context $Context -Item $Item) }
