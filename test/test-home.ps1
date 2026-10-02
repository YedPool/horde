# DOES HORDE FIND ITS HOME FROM HORDE_HOME, AND ONLY AS A PATH?
#
# core/Home.ps1. Every check restores the two variables it changes, so the suite leaves the process
# as it found it.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\Home.ps1")

$origHome = $env:HORDE_HOME
$origProfile = $env:USERPROFILE
try {
    Write-Host ""
    Write-Host "--- the home ---" -ForegroundColor Cyan
    $fake = Join-Path $env:TEMP ("horde-home-test-" + [guid]::NewGuid().ToString("N"))
    $env:HORDE_HOME = $fake
    Check ((Get-HordeHome) -eq $fake) "HORDE_HOME names the home when it is set"
    $env:HORDE_HOME = ""
    $env:USERPROFILE = "C:\profile-for-test"
    Check ((Get-HordeHome) -eq "C:\profile-for-test\.horde") "with HORDE_HOME unset the home is .horde in the user profile"
    $env:HORDE_HOME = "relative\home"
    Check (Throws { Get-HordeHome } "absolute") "a relative HORDE_HOME is refused, not resolved against the current folder"
    $env:HORDE_HOME = ""
    $env:USERPROFILE = ""
    Check (Throws { Get-HordeHome } "no home") "with neither variable there is no home, and it says so"
    $env:HORDE_HOME = $fake
    $null = Get-HordeHome
    Check (-not (Test-Path -LiteralPath $fake)) "finding the home does not create it"
} finally {
    $env:HORDE_HOME = $origHome
    $env:USERPROFILE = $origProfile
}

Complete-HordeSuite -Success "Horde's home comes from HORDE_HOME or the user profile, and is never guessed"
