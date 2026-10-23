# tools/nightly/guards-wrap.ps1 - the repo-wide guards of the day's merges, for the nightly net (T-0331).
# Runs `horde merge -RunOwed -Repo <repo> -Json` (T-0347, PR 375), which runs the guards on the base tip and names the
# first queued merge behind each red guard. The PROCESS exits 0 (green or nothing owed) or 1 (red or could not run);
# 2 is a bad command line, which is also what a horde without the verb answers. The real answer is the exit field
# of the -Json last line (0 green, 1 red, 2 could not run): core/NightlyNet.ps1 Get-HordeNightlyGuardsAnswer reads it, and a
# process exit of 2 or a last line that is missing or unreadable is could-not-run, never green. This wrapper prints
# horde's output as it was, then exits with that answer. HeavySlot starts it under Windows PowerShell 5.1.
param([Parameter(Mandatory = $true)][string]$Horde, [Parameter(Mandatory = $true)][string]$Repo)
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\NightlyNet.ps1")
$ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$lines = @(& $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Horde merge -RunOwed -Repo $Repo -Json)
$processExit = $LASTEXITCODE
$lines | ForEach-Object { Write-Output $_ }
$answer = Get-HordeNightlyGuardsAnswer -ProcessExit $processExit -Lines @($lines | ForEach-Object { "" + $_ })
Write-Output ("guards-wrap: " + $answer.state)
exit $answer.code