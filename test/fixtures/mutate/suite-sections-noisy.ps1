# Not built on test\lib\Suite.ps1. Run with the selection "silent" it exits 1 and prints nothing; with
# any other it prints an [ERROR] and still exits 3. Neither is a pass for a map's baseline. The
# declaration is here for the static reader only.
function Register-HordeSuiteSections { param([string[]]$Ids) }
Register-HordeSuiteSections -Ids @("quiet", "silent")
. (Join-Path $PSScriptRoot "target-sections.ps1")
if ((Get-Two) -ne 2) { Write-Host "  [FAIL] Get-Two returns two"; exit 1 }
if ("$env:HORDE_SECTIONS" -eq "silent") { exit 1 }
if ("$env:HORDE_SECTIONS" -ne "") { Write-Host "  [ERROR] an error no test expected"; exit 3 }
exit 0
