# Passes under Windows PowerShell 5.1 and fails under PowerShell 7, unmutated: a baseline that only one
# shell breaks.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "target-shells.ps1")
if (("" + $PSVersionTable.PSEdition) -ceq "Core") { Write-Host "  [FAIL] this suite does not hold under PowerShell 7"; exit 1 }
exit 0
