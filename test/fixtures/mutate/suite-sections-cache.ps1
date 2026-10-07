# Section "warm" fills the cache; section "use" checks the value. Run whole, "use" reads the cache; run
# alone, it computes - another path, which a mutant can break without the whole suite ever seeing it.
. (Join-Path $PSScriptRoot "..\..\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Register-HordeSuiteSections -Ids @("warm", "use")
. (Join-Path $PSScriptRoot "target-cache.ps1")
if (Enter-HordeSuiteSection "warm" "warm the cache") {
    trap { Register-HordeSuiteError $_; continue }
    Set-ValCache
    Check ((Get-Val) -eq 5) "the warmed value is five"
}
if (Enter-HordeSuiteSection "use" "use the value") {
    trap { Register-HordeSuiteError $_; continue }
    Check ((Get-Val) -eq 5) "Get-Val returns five"
}
Complete-HordeSuite -Success "warm, then use"
