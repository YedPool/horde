# DOES EVERY CORE FILE, LOADED ALONE, DEFINE EVERY HORDE FUNCTION IT CALLS?
#
# tools/CoreLoad.ps1 (review of #109: core/NodePolicy.ps1 called Assert-HordeAsciiBytes from a file it
# never loaded, and worked only because every caller loaded that file first). Each core file is loaded
# in a fresh runspace of its own; its calls are read from its parse. A call the runspace does not define
# fails this suite, unless tools/core-load-legacy.txt lists it - the files found when the guard was
# written, fixed in a follow-up - and a listed call that no longer fails fails too, so the list only
# shrinks.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "tools\CoreLoad.ps1")

$work = Join-Path $env:TEMP ("horde-core-load-" + [guid]::NewGuid().ToString("N"))
try {
Write-Host ""
Write-Host "--- CONTROL: the guard sees the bug it exists for ---" -ForegroundColor Cyan
$fc = Join-Path $work "core"
New-Item -ItemType Directory -Path $fc -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $fc "Helper.ps1"), "function Get-HordeFixtureHelp { return 1 }`r`n")
[System.IO.File]::WriteAllText((Join-Path $fc "Caller.ps1"), "function Get-HordeFixtureCall { return (Get-HordeFixtureHelp) }`r`n")
[System.IO.File]::WriteAllText((Join-Path $fc "Loader.ps1"), ". (Join-Path `$PSScriptRoot `"Helper.ps1`")`r`nfunction Get-HordeFixtureLoaded { return (Get-HordeFixtureHelp) }`r`n")
[System.IO.File]::WriteAllText((Join-Path $fc "Broken.ps1"), "throw 'the fixture breaks on load'`r`nfunction Get-HordeFixtureBroken { return 1 }`r`n")
$f = @(Find-HordeUnloadedCalls -Root $work)
Check (@($f | Where-Object { $_.file -ceq "core/Caller.ps1" -and $_.name -ceq "Get-HordeFixtureHelp" }).Count -eq 1) "a file calling a function from a file it never loads is found, by file and name"
Check (@($f | Where-Object { $_.file -ceq "core/Loader.ps1" }).Count -eq 0) "CONTROL: the same call from a file that loads the helper is not"
Check (@($f | Where-Object { $_.file -ceq "core/Broken.ps1" -and $_.name -ceq "<load error>" }).Count -eq 1) "a file that throws while loading is a finding, never a pass"

Write-Host ""
Write-Host "--- every core file of this tree ---" -ForegroundColor Cyan
$legacy = @{}
foreach ($line in @([System.IO.File]::ReadAllLines((Join-Path $root "tools\core-load-legacy.txt")))) {
    if ($line.Trim() -eq "" -or $line.StartsWith("#")) { continue }
    $legacy[$line.Trim()] = $true
}
$found = @(Find-HordeUnloadedCalls -Root $root)
$keys = @($found | ForEach-Object { $_.file + " | " + $_.name })
$new = @($found | Where-Object { -not $legacy.ContainsKey($_.file + " | " + $_.name) })
Check ($new.Count -eq 0) ("no core file calls a Horde function it neither defines nor loads, beyond the list (" + (@($new | ForEach-Object { $_.file + " :: " + $_.name + " line " + $_.line }) -join "; ") + ")")
$stale = @($legacy.Keys | Where-Object { $keys -cnotcontains $_ })
Check ($stale.Count -eq 0) ("every line of tools/core-load-legacy.txt is still a finding, so the list only shrinks (" + ($stale -join "; ") + ")")
Check (@($found | Where-Object { $_.file -ceq "core/NodePolicy.ps1" }).Count -eq 0) "core/NodePolicy.ps1, the file of #109's bug, loads everything it calls"
} finally {
    if ((Split-Path -Leaf $work) -match '^horde-core-load-[0-9a-f]{32}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

Complete-HordeSuite -Success "every core file, loaded alone, defines or loads every Horde function it calls, beyond the shrinking list"
