# Checks Get-Two only. Get-Label is deliberately untested, so a mutation of it survives.
. (Join-Path $PSScriptRoot "target.ps1")
if ((Get-Two) -ne 2) { Write-Host "  [FAIL] Get-Two returns two"; exit 1 }
exit 0
