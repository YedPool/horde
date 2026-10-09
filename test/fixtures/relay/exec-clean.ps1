# Clean file for the relay profile of tools/ExecScan.ps1 (test/test-exec-scan.ps1, section II): written
# the way relay/ is - its loader lines, the one admitted Add-Type, the cryptography it names - and it
# must have no finding under the relay profile, while the remote profile refuses it. Never run.

. (Join-Path $PSScriptRoot "Neighbour.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\JsonText.ps1")

function Initialize-FixtureGcm {
    if ($null -eq ("HordeRelayGcmV1" -as [type])) {
        Add-Type -Path (Join-Path $PSScriptRoot "Gcm.cs")
    }
}

function Get-FixtureSignature {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes, [object[]]$Parts)
    $key = [System.Security.Cryptography.ECDsa]::Create([System.Security.Cryptography.ECCurve]::CreateFromFriendlyName("nistP256"))
    $sig = $key.SignData($Bytes, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    $dups = @(Find-HordeJsonDuplicateKey -Text "{}")
    return [System.Convert]::ToBase64String($sig)
}
