# Checks both functions of target-shells.ps1. A mutant of its Core branch fails here only under 7.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "target-shells.ps1")
if ((Get-Two) -ne 2) { Write-Host "  [FAIL] Get-Two returns two"; exit 1 }
if ((Get-EditionTwo) -ne 2) { Write-Host ("  [FAIL] Get-EditionTwo returns two under " + $PSVersionTable.PSEdition); exit 1 }
if ((Get-EditionThree) -ne 3) { Write-Host ("  [FAIL] Get-EditionThree returns three under " + $PSVersionTable.PSEdition); exit 1 }
exit 0
