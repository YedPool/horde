# A suite in three sections, one function each. Get-Label is deliberately untested, so a mutation of it
# survives. When HORDE_MUTATE_SECTIONS_LOG names a file, each run appends the selection it was given,
# so test\test-mutate.ps1 can see which runs tools\Mutate.ps1 made, not only what it reported.
. (Join-Path $PSScriptRoot "..\..\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
# Logged before Register-HordeSuiteSections, which removes HORDE_SECTIONS from this process once read.
if ("$env:HORDE_MUTATE_SECTIONS_LOG" -ne "") { [System.IO.File]::AppendAllText($env:HORDE_MUTATE_SECTIONS_LOG, ("run sections=[" + $env:HORDE_SECTIONS + "]`r`n")) }
Register-HordeSuiteSections -Ids @("two", "three", "four")
. (Join-Path $PSScriptRoot "target-sections.ps1")
if (Enter-HordeSuiteSection "two" "Get-Two") { Check ((Get-Two) -eq 2) "Get-Two returns two" }
if (Enter-HordeSuiteSection "three" "Get-Three") { Check ((Get-Three) -eq 3) "Get-Three returns three" }
if (Enter-HordeSuiteSection "four" "Get-Four") { Check ((Get-Four) -eq 4) "Get-Four returns four" }
Complete-HordeSuite -Success "two, three and four"
