# Declares its sections twice and enters one twice: either would let the list a map is checked
# against differ from the list that runs.
. (Join-Path $PSScriptRoot "..\..\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Register-HordeSuiteSections -Ids @("alpha")
Register-HordeSuiteSections -Ids @("alpha")
if (Enter-HordeSuiteSection "alpha" "the alpha section") { Check (1 -eq 1) "the alpha check" }
if (Enter-HordeSuiteSection "alpha" "the alpha section again") { Check (1 -eq 1) "the alpha check again" }
Complete-HordeSuite -Success "never"
