# Passes only when the spec's Environment reached it, then checks Get-Two as suite.ps1 does.
$ErrorActionPreference = "Stop"
if ($env:HORDE_MUTATE_FIXTURE_ENV -ne "set") { Write-Host "  [FAIL] the spec's environment reached the suite"; exit 1 }
. (Join-Path $PSScriptRoot "target.ps1")
if ((Get-Two) -ne 2) { Write-Host "  [FAIL] Get-Two returns two"; exit 1 }
exit 0
