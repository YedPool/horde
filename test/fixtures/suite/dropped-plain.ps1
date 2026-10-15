# A member a mutant dropped, read plainly under strict mode inside one top-level try: the error skips
# the rest of the try, so the suite ends with no failed check - a crash, not a catch (issue 216).
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "..\..\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
$body = [pscustomobject]@{ thrall = [pscustomobject]@{ orcs = 3 } }
try {
    Check ($body.thrall.census.running -eq 1) "the Thrall's card counts one run"
    Check ($true) "a check after the dropped member"
} finally { }
Complete-HordeSuite -Success "should not be reached"
