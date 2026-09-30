# A condition that is a list, not a boolean, fails.
. (Join-Path $PSScriptRoot "..\..\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Check (@("a", "b") -like "a*") "a filtered list is not true"
Complete-HordeSuite -Success "should not be reached"
