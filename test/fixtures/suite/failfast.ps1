# Two failing checks. Under HORDE_FAIL_FAST=1 the suite stops at the first.
. (Join-Path $PSScriptRoot "..\..\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Check (1 -eq 2) "the first failing check"
Check (1 -eq 3) "the second failing check"
Complete-HordeSuite -Success "never"
