# Mutations of tools/NightlyNet.ps1 for T-0514 parts (a) and (c): a memory give-up is tried again as soon as a gate ran
# at its floor, and every unit and bisect step that did not run says so, with the runs that really happened. Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\nightly-not-run-lines.psd1
@{
    Target = "tools\NightlyNet.ps1"
    Suite  = "test\test-nightly-net.ps1"
    Mutations = @(
        @{ Name = "memory-retry-dropped"
           Find = '    if ([double]$back.freeGB -le 0) { return }'
           Replace = '    return' }
        @{ Name = "floor-ignored"
           Find = '$c.memoryLater.ContainsKey($_) -and [double]$c.memoryLater[$_].freeGB -le [double]$back.freeGB'
           Replace = '$c.memoryLater.ContainsKey($_) -and $true' }
        @{ Name = "slot-give-ups-retried-too"
           Find = '$q = @($c.later | Where-Object { $c.memoryLater.ContainsKey($_) -and'
           Replace = '$q = @($c.later | Where-Object { $true -or' }
        @{ Name = "retry-after-the-last-unit-dropped"
           Find = 'if (-not $Retries) { Invoke-NightlyMemoryRetries -RunCutoff $RunCutoff -Cutoff $Cutoff }'
           Replace = '$null = $Retries' }
        @{ Name = "not-run-line-dropped"
           Find = 'Write-NightlyNetLine ($Ctx.repo + " " + $u + " -> not run, " + $why)'
           Replace = '[void]$why' }
        @{ Name = "not-tried-unit-told-twice"
           Find = 'if ($Ctx.verdicts.ContainsKey($u) -or $Ctx.notRunTold.ContainsKey($u)) { continue }'
           Replace = 'if ($Ctx.verdicts.ContainsKey($u)) { continue }' }
        @{ Name = "bisect-gate-line-dropped"
           Find = 'Write-NightlyNetLine ($at + $(if (Test-HordeNightlyMemoryGiveUp'
           Replace = '[void]($at + $(if (Test-HordeNightlyMemoryGiveUp' }
        @{ Name = "bisect-clock-line-dropped"
           Find = 'if (-not (Test-NightlyMayStart -Cutoff $Cutoff -Seconds $RunSeconds)) { Write-NightlyNetLine ($at +'
           Replace = 'if (-not (Test-NightlyMayStart -Cutoff $Cutoff -Seconds $RunSeconds)) { [void]($at +' }
        @{ Name = "runs-counted-as-core-counts"
           Find = '$ran = [int]$script:BisectRan'
           Replace = '$ran = [int]$found.runs' }
    )
}
