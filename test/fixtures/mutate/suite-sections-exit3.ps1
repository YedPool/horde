# Section "four" ends the suite with exit 3 - a pass that skipped part of it - when Get-Four is wrong.
# A whole run that exits 3 is not a pass for a spec that does not declare it, rerun or not.
. (Join-Path $PSScriptRoot "..\..\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Register-HordeSuiteSections -Ids @("two", "four")
. (Join-Path $PSScriptRoot "target-sections.ps1")
if (Enter-HordeSuiteSection "two" "Get-Two") { Check ((Get-Two) -eq 2) "Get-Two returns two" }
if (Enter-HordeSuiteSection "four" "Get-Four") { if ((Get-Four) -ne 4) { Complete-HordeSuite -Success "skipped the rest" -PassCode 3 } }
Complete-HordeSuite -Success "two and four"
