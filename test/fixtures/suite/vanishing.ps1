# A check whose expression raises an error must not vanish: the suite has to fail.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "..\..\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
$o = [pscustomobject]@{ a = 1 }
Check ($o.missing -eq 1) "reads a property that is not there"
Check ($true) "a check after the error still runs"
Complete-HordeSuite -Success "should not be reached"
