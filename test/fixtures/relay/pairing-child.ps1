# The other runtime's half of test/test-relay-pairing.ps1: read a machine identity and a trust store
# that suite made, in a Horde home of its own under %TEMP%. Not a suite; run only by that suite.
#   pairing-child.ps1 -HordeHome <folder> -Out <file>
# Writes to Out: "<sign key id> <agree key id> <trusted sender key ids, sorted, comma-separated>", or
# "REFUSED <reason>".
param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$Out)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))
. (Join-Path $root "relay\Pairing.ps1")
$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false

$id = Get-HordeRelayMachineIdentity -HordeHome $HordeHome
if ($id.state -cne "known") { [System.IO.File]::WriteAllText($Out, "REFUSED " + $id.reason, $utf8); exit 0 }
$s = Find-HordeRelayTrustedSenders -HordeHome $HordeHome
if ($s.state -cne "known") { [System.IO.File]::WriteAllText($Out, "REFUSED " + $s.reason, $utf8); exit 0 }
[System.IO.File]::WriteAllText($Out, $id.value.sign.keyId + " " + $id.value.agree.keyId + " " + (@($s.value.Keys | Sort-Object) -join ","), $utf8)
exit 0
