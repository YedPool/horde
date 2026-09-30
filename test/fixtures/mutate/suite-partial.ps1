# Checks Get-Two, and passes with exit 3 - a pass that skipped part of the suite - when the spec's
# environment reached it; exit 0 otherwise, which spec-passcodes does not accept.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "target.ps1")
if ((Get-Two) -ne 2) { Write-Host "  [FAIL] Get-Two returns two"; exit 1 }
if ($env:HORDE_MUTATE_FIXTURE_ENV -eq "set") { exit 3 }
exit 0
