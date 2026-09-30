# Fails while asking for a pass code: a failure still exits 1.
. (Join-Path $PSScriptRoot "..\..\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Check (1 -eq 2) "one is two"
Complete-HordeSuite -Success "partial" -PassCode 3
