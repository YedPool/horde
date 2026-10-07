# Declares a section it never enters: a section the suite forgot cannot be selected and pass.
. (Join-Path $PSScriptRoot "..\..\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Register-HordeSuiteSections -Ids @("alpha", "beta")
if (Enter-HordeSuiteSection "alpha" "the alpha section") { Check (1 -eq 1) "the alpha check" }
Complete-HordeSuite -Success "never"
