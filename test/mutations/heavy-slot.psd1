# Mutations of tools/HeavySlot.ps1, the local gate. Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\heavy-slot.psd1
# Each breaks one rule of the gate; test\test-heavy-slot.ps1 must fail for every one of them. The wait
# for memory that never gives up is not a mutant here: it would hang the suite rather than fail a check.
@{
    Target = "tools\HeavySlot.ps1"
    Suite  = "test\test-heavy-slot.ps1"
    Mutations = @(
        @{ Name = "slot-never-released"
           Find = '    if ($held) { $mutex.ReleaseMutex() }'
           Replace = '    if ($false) { $mutex.ReleaseMutex() }' }
        @{ Name = "slot-waited-for-ever"
           Find = 'try { $script:held = $mutex.WaitOne([int](& $left) * 1000) }'
           Replace = 'try { $script:held = $mutex.WaitOne() }' }
        @{ Name = "killed-holder-run-not-waited-for"
           Find = '    if ($null -ne $orphan) {'
           Replace = '    if ($false) {' }
        @{ Name = "reused-id-taken-for-the-run"
           Find = 'try { if ($p.StartTime.ToUniversalTime().Ticks -ne $ticks) { return $null } } catch { return $null }'
           Replace = 'try { $null = $p.StartTime } catch { return $null }' }
        @{ Name = "memory-not-waited-for"
           Find = '    while ((Get-HordeHeavySlotFreeGB) -lt $MinFreeGB) {'
           Replace = '    while ($false) {' }
        @{ Name = "run-past-its-time-left-running"
           Find = '    if ($null -ne $run -and -not $run.HasExited) { Stop-HordeHeavySlotTree -Id $run.Id; $null = $run.WaitForExit(10000) }'
           Replace = '    if ($false) { Stop-HordeHeavySlotTree -Id $run.Id; $null = $run.WaitForExit(10000) }' }
        @{ Name = "run-code-lost"
           Find = '    $script:code = $run.ExitCode'
           Replace = '    $script:code = 0' }
        @{ Name = "missing-script-run-anyway"
           Find = 'if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $script:code = 126;'
           Replace = 'if ($false) { $script:code = 126;' }
    )
}
