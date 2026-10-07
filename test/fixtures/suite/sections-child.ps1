# Starts a child process inside a selected section and prints what HORDE_SECTIONS the child sees: a
# suite's selection must not reach the suites and tools it starts (review of #115, B2).
. (Join-Path $PSScriptRoot "..\..\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Register-HordeSuiteSections -Ids @("alpha")
if (Enter-HordeSuiteSection "alpha" "the alpha section") {
    $seen = "$(& powershell -NoProfile -Command '$env:HORDE_SECTIONS')".Trim()
    Write-Host ("  child saw [" + $seen + "]")
    Check (1 -eq 1) "the alpha check"
}
Complete-HordeSuite -Success "child"
