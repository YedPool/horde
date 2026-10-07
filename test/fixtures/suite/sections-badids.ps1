# Section ids a selection could not name exactly: one in capitals, one declared twice.
. (Join-Path $PSScriptRoot "..\..\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Register-HordeSuiteSections -Ids @("Alpha", "beta", "beta")
if (Enter-HordeSuiteSection "Alpha" "the alpha section") { Check (1 -eq 1) "the alpha check" }
if (Enter-HordeSuiteSection "beta" "the beta section") { Check (1 -eq 1) "the beta check" }
Complete-HordeSuite -Success "never"
