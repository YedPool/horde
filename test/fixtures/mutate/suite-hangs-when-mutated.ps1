# Hangs only when Get-Two is wrong: a mutant that hangs the suite.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "target.ps1")
if ((Get-Two) -ne 2) { Start-Sleep -Seconds 120 }
exit 0
