# A suite built on test/lib/Suite.ps1. A mutant that makes Get-Two throw crashes it: [ERROR], not [FAIL].
. (Join-Path $PSScriptRoot "..\..\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $PSScriptRoot "target.ps1")
Check ((Get-Two) -eq 2) "Get-Two returns two"
Complete-HordeSuite -Success "Get-Two is two"
