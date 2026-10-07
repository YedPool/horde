# Enters a section it never declared: the selection could never name it.
. (Join-Path $PSScriptRoot "..\..\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Register-HordeSuiteSections -Ids @("alpha")
if (Enter-HordeSuiteSection "alpha" "the alpha section") { Check (1 -eq 1) "the alpha check" }
if (Enter-HordeSuiteSection "gamma" "the gamma section") { Check (1 -eq 1) "the gamma check" }
Complete-HordeSuite -Success "never"
