# DOES THE GUARD LIST - ONE FILE, TWO READERS - NAME THE RIGHT GUARDS AND REFUSE A BAD LINE?
#
# core/GuardList.ps1 and test\guards.txt (T-0247). `horde merge` (cli/Merge.ps1) and the CI runner
# (tools/CiGuards.ps1) both read the repository's guards from test\guards.txt through core/GuardList.ps1.
# This suite holds the reading itself, which is pure text in and a list out:
#   - comments, blank lines, either slash and a byte-order mark are taken; a line that is no guard script
#     under test/ refuses the WHOLE list (a skipped line is a guard that silently does not run); a guard
#     listed twice, or a list with no guard, is refused;
#   - the guards to run are the base's and the checked tree's together, so a pull request can add a guard
#     but not drop one by editing the list;
#   - the repository's own list is valid, names only files that exist, and names all eight guards;
#   - PowerShell 5.1 is given the machine PSModulePath and 7 none; PowerShell 7 is the MSI by default.
# The runners that use the list have suites of their own (test/test-merge.ps1, test/test-ci-guards.ps1).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\GuardList.ps1")

Write-Host "== the list is read"
$gl = Read-HordeGuardList -Text "# a comment`r`n`r`ntest/test-a.ps1`r`n  test\test-b.ps1  `r`n"
Check ($gl.ok -and (@($gl.guards) -join "|") -ceq "test\test-a.ps1|test\test-b.ps1") "a list is read: comments and blank lines skipped, either slash taken, spelled with backslashes"
Check ((Read-HordeGuardList -Text ([string][char]0xFEFF + "test/test-a.ps1")).ok) "a byte-order mark at the top of the file is ignored"
foreach ($badLine in @("rm -rf /", "tools/Mutate.ps1", "test/../tools/x.ps1", "C:\x\test\a.ps1", "test/a.psm1", "test/sub/a.ps1", "test/a b.ps1", "/test/a.ps1", "test/-a.ps1")) {
    $b = Read-HordeGuardList -Text ("test/test-a.ps1`n" + $badLine + "`n")
    Check (-not $b.ok -and $b.why -clike "line 2 of test\guards.txt is not a guard script*") ("a line that is no guard refuses the whole list, never skipped: '" + $badLine + "'")
}
Check (-not (Read-HordeGuardList -Text "test/test-a.ps1`ntest\test-a.ps1`n").ok) "a guard listed twice (either slash) refuses the list"
Check (-not (Read-HordeGuardList -Text "# nothing`n").ok -and -not (Read-HordeGuardList -Text "").ok) "a list with no guard is refused: nothing could say the tree is green"
Check ((@(Join-HordeGuardLists -Tree @("test\b.ps1", "test\c.ps1") -Base @("test\a.ps1", "test\b.ps1")) -join "|") -ceq "test\a.ps1|test\b.ps1|test\c.ps1") "the guards run are the base's and the tree's together: a PR adds one, it cannot drop one"
Check ((@(Join-HordeGuardLists -Tree @("test\b.ps1") -Base $null) -join "|") -ceq "test\b.ps1") "a base with no list yet leaves the tree's list"
$realList = Read-HordeGuardList -Text ([System.IO.File]::ReadAllText((Join-Path $root "test\guards.txt")))
Check ($realList.ok -and @($realList.guards).Count -ge 8) ("the repository's own test\guards.txt is a valid list of " + @($realList.guards).Count + " guards")
Check (@($realList.guards | Where-Object { -not [System.IO.File]::Exists((Join-Path $root $_)) }).Count -eq 0) "  and every guard it names is a file of the repository"
foreach ($want in @("test-host-names", "test-mutation-specs", "test-function-names", "test-json-parse-allowlist", "test-param-shadow", "test-core-load", "test-exec-scan", "test-start-sites")) {
    Check (@($realList.guards) -ccontains ("test\" + $want + ".ps1")) ("  and it lists " + $want)
}


Write-Host "== the shells"
Check ((Get-HordeGuardEnvironment -Shell "5.1" -MachinePsModulePath "C:\m1;C:\m2").PSModulePath -ceq "C:\m1;C:\m2") "5.1 is given the machine value of PSModulePath"
Check ((Get-HordeGuardEnvironment -Shell "5.1" -MachinePsModulePath "").Count -eq 0) "  and none when the machine has none"
Check ((Get-HordeGuardEnvironment -Shell "7" -MachinePsModulePath "C:\m1").Count -eq 0) "PowerShell 7 is given none: it builds its own"
Check (((@(Get-HordeGuardShells) | ForEach-Object { $_.key }) -join ",") -ceq "5.1,7") "the guards run in 5.1 first, then 7"
Check ((Get-HordeGuardPwsh7 -Setting "D:\ps\pwsh.exe") -ceq "D:\ps\pwsh.exe") "the guardShell7 setting wins over the default"
$def = Get-HordeGuardPwsh7
Check ($def -clike "*\PowerShell\7\pwsh.exe" -and $def -cnotlike "*WindowsApps*") ("the default PowerShell 7 is the MSI install under Program Files, never the Store copy (" + $def + ")")

Complete-HordeSuite -Success "the guard list is read strictly, the base's guards cannot be dropped, and the repository's list names all eight guards"
