# Two sections, each with one passing check. HORDE_SECTIONS picks which run; HORDE_FIXTURE_FAIL_IN
# names a section whose check fails instead.
. (Join-Path $PSScriptRoot "..\..\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Register-HordeSuiteSections -Ids @("alpha", "beta")
if (Enter-HordeSuiteSection "alpha" "the alpha section") { Check ($env:HORDE_FIXTURE_FAIL_IN -cne "alpha") "the alpha check" }
if (Enter-HordeSuiteSection "beta" "the beta section") { Check ($env:HORDE_FIXTURE_FAIL_IN -cne "beta") "the beta check" }
Complete-HordeSuite -Success "sections"
