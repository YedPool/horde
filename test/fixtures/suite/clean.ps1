# Nothing wrong: exits 0.
. (Join-Path $PSScriptRoot "..\..\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Check (1 -eq 1) "one is one"
Complete-HordeSuite -Success "clean"
