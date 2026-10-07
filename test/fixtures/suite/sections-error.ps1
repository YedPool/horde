# An unexpected error in a section, then a failing check in the same section: the check must still run.
. (Join-Path $PSScriptRoot "..\..\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Register-HordeSuiteSections -Ids @("alpha")
if (Enter-HordeSuiteSection "alpha" "the alpha section") {
    trap { Register-HordeSuiteError $_; continue }
    throw "boom"
    Check (1 -eq 2) "the check after the error"
}
Complete-HordeSuite -Success "never"
