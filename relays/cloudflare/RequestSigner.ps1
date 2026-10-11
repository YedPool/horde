# relays/cloudflare/RequestSigner.ps1 - how this machine proves to the hosted relay that a request is its
# own: no token, no password, no session - a signature, per request, by this machine's relay signing
# key (relay/Identity.ps1: non-exportable, in the TPM where it can be), the key a signed-in phone
# registered to its account while it paired (relay/Pairing.ps1, THE ACCOUNT GRANT).
#
# THE WIRE is worker/request-signature.js's, which this file writes and that one reads (twins: a change
# to one is a change to both, and test-cloudflare-accounts.ps1 sends what this writes to the real
# Worker):
#   Authorization: Horde-Machine key=<key id>,time=<ms>,nonce=<32 hex>,sig=<86 base64url>
#   signed: "horde-relay/request/v1" LF origin LF METHOD LF path?query LF time LF nonce LF key id LF
#           base64url(SHA-256(body))
# The signature is relay/P256.ps1's New-HordeRelayEs256Signature - ES256, 64 bytes r || s, low-S - made
# by whichever crypto backend opened the key (CNG under Windows PowerShell 5.1, .NET under pwsh 7).
# The nonce is 128 random bits; the time this machine's clock, which the relay takes within a minute.
#
# No Set-StrictMode here: dot-sourced.

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "relay\Identity.ps1")

$script:HordeCloudflareRelayRequestDomain = "horde-relay/request/v1`n"
$script:HordeCloudflareRelayAuthScheme = "Horde-Machine"

function Get-HordeCloudflareRelaySignedBytes {
    # What a request's signature covers (the header).
    param([string]$Origin, [string]$Method, [string]$Target, [long]$Time, [string]$Nonce, [string]$KeyId, [string]$BodyHash)
    return ,(Get-HordeRelayAsciiBytes -Text ($script:HordeCloudflareRelayRequestDomain + $Origin + "`n" + $Method + "`n" + $Target + "`n" + $Time + "`n" + $Nonce + "`n" + $KeyId + "`n" + $BodyHash))
}

function New-HordeCloudflareRelayMachineAuthorization {
    # The Authorization value for one request: -Target is its path and query, -Body its bytes (none for
    # a read or a watch). -Time and -Nonce are for a suite that must make a stale or a repeated one.
    param([Parameter(Mandatory = $true)]$Key, [Parameter(Mandatory = $true)][string]$KeyId, [Parameter(Mandatory = $true)][string]$Origin,
        [Parameter(Mandatory = $true)][string]$Method, [Parameter(Mandatory = $true)][string]$Target, [AllowEmptyCollection()][byte[]]$Body = @(),
        [long]$Time = -1, [string]$Nonce = "")
    if ($Time -lt 0) { $Time = [System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }
    if ($Nonce -eq "") { $Nonce = ConvertTo-HordeRelayHex -Bytes (Get-HordeRelayRandomBytes -Count 16) }
    if ($null -eq $Body) { $Body = @() }
    $hash = ConvertTo-HordeRelayBase64Url -Bytes (Get-HordeRelaySha256 -Bytes ([byte[]]$Body))
    $sig = New-HordeRelayEs256Signature -Key $Key -Bytes (Get-HordeCloudflareRelaySignedBytes -Origin $Origin -Method $Method -Target $Target -Time $Time -Nonce $Nonce -KeyId $KeyId -BodyHash $hash)
    return ($script:HordeCloudflareRelayAuthScheme + " key=" + $KeyId + ",time=" + $Time + ",nonce=" + $Nonce + ",sig=" + (ConvertTo-HordeRelayBase64Url -Bytes $sig))
}

function Open-HordeCloudflareRelaySigner {
    # This machine's signing key, opened to sign requests: known { keyId; key } (the caller keeps it for
    # the connection's life), or the identity's own answer - absent with no identity yet, unknown when it
    # is damaged - so the founder reads what to do. The agreement key is closed at once: it is not
    # needed here.
    param([string]$HordeHome = "")
    $id = Get-HordeRelayMachineIdentity -HordeHome $HordeHome -Open
    if ($id.state -cne "known") { return $id }
    $id.value.agree.key.Dispose()
    return (New-HordeKnown -Value ([pscustomobject]@{ keyId = $id.value.sign.keyId; key = $id.value.sign.key; horde = $id.value.horde }))
}
