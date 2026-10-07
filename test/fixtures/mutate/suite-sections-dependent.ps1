# Two sections, the second reading what the first set: run alone, "use" fails with no mutant at all.
. (Join-Path $PSScriptRoot "..\..\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Register-HordeSuiteSections -Ids @("setup", "use")
. (Join-Path $PSScriptRoot "target-sections.ps1")
$ready = $false
if (Enter-HordeSuiteSection "setup" "setup") { $ready = ((Get-Two) -eq 2); Check $ready "Get-Two returns two" }
if (Enter-HordeSuiteSection "use" "use") { Check ($ready -and (Get-Three) -eq 3) "Get-Three returns three, after setup" }
Complete-HordeSuite -Success "setup, then use"
