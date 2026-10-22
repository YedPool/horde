# tools/nightly/guards-wrap.ps1 - the repo-wide guards of the day's merges, for the nightly net (T-0331).
# Runs `horde merge -RunOwed -Repo <repo>` (T-0347), which runs the guards on the base tip and names the first
# queued merge behind each red guard; its exit code is passed back: 0 green, 1 red, 2 could not run. A horde
# that does not have the verb yet answers 2 (an unknown word), which reads as "could not run" - never as green.
# HeavySlot starts this under Windows PowerShell 5.1.
param([Parameter(Mandatory = $true)][string]$Horde, [Parameter(Mandatory = $true)][string]$Repo)
$ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
& $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Horde merge -RunOwed -Repo $Repo
$code = $LASTEXITCODE
if ($code -ne 0 -and $code -ne 1) { $code = 2 }
exit $code
