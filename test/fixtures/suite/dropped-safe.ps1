# The same dropped member read through Get-HordeTestMember: the check that names the rule fails, and
# the checks after it still run.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "..\..\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
$body = [pscustomobject]@{ thrall = [pscustomobject]@{ orcs = 3 } }
try {
    Check ((Get-HordeTestMember $body "thrall.census.running") -eq 1) "the Thrall's card counts one run"
    Check ($true) "a check after the dropped member"
} finally { }
Complete-HordeSuite -Success "should not be reached"
