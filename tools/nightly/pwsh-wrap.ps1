# tools/nightly/pwsh-wrap.ps1 - run ONE Horde suite under PowerShell 7 for the nightly net (T-0331).
# tools/HeavySlot.ps1 always starts a .ps1 under Windows PowerShell 5.1, so this is the .ps1 it starts; it hands
# the suite to PowerShell 7 (the MSI install, never the Store copy) and passes the suite's exit code back.
# No redirection here: a 5.1 redirect writes UTF-16 and the log then reads as having no checks
# (found 2026-10-16). Taken from the dual-shell net's wrapper, which this replaces.
param([Parameter(Mandatory = $true)][string]$Suite, [Parameter(Mandatory = $true)][string]$Tree)
$pwsh = Join-Path $env:ProgramFiles "PowerShell\7\pwsh.exe"
if (-not (Test-Path -LiteralPath $pwsh)) { Write-Output ("pwsh-wrap: PowerShell 7 is not at " + $pwsh); exit 127 }
Set-Location -LiteralPath $Tree
& $pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Suite
exit $LASTEXITCODE
