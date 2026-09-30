# An error that does not stop the statement - a path that is not there - must still fail the suite.
. (Join-Path $PSScriptRoot "..\..\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Check (@(Get-ChildItem -LiteralPath "C:\no\such\horde\dir").Count -eq 0) "an empty listing of a missing folder"
Complete-HordeSuite -Success "should not be reached"
