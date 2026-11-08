# Mutations of tools/HeavySlot.ps1 for naming the slot's holder (T-0445). Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\heavy-slot-holder.psd1
# Each breaks one rule of naming the holder, the slot log or the holder record; test\test-heavy-slot-holder.ps1
# must fail for every one of them.
@{
    Target = "tools\HeavySlot.ps1"
    Suite  = "test\test-heavy-slot-holder.ps1"
    Mutations = @(
        @{ Name = "holder-not-named"
           Find = '$t = $rec[2] + " (process " + $rec[0]'
           Replace = '$t = "someone (process ?"' }
        @{ Name = "holder-worktree-dropped"
           Find = 'if ($rec.Count -gt 3 -and $rec[3] -ne "") { $t += ", worktree " + $rec[3] }'
           Replace = 'if ($false) { }' }
        @{ Name = "holder-named-on-every-try"
           Find = '$script:holderSaid = $true'
           Replace = '$script:holderSaid = $false' }
        @{ Name = "holder-never-named-while-waiting"
           Find = '$clock.Elapsed.TotalSeconds -ge 10)'
           Replace = '$clock.Elapsed.TotalSeconds -ge 1000)' }
        @{ Name = "record-loses-new-fields"
           Find = '"`n" + $Worktree + "`n" + $script:takenAt + "`n"))'
           Replace = '"`n"))' }
        @{ Name = "record-old-lines-moved"
           Find = '("" + $job.pid + "`n" + $start + "`n" + $Script + "`n" + $Worktree'
           Replace = '("" + $Worktree + "`n" + $job.pid + "`n" + $start + "`n" + $Script' }
        @{ Name = "log-carries-the-arguments"
           Find = '" script=" + $Script + " worktree="'
           Replace = '" script=" + $Script + " " + ($ScriptArgs -join " ") + " worktree="' }
        @{ Name = "take-not-logged"
           Find = 'Write-HordeHeavySlotLog -Event "take"'
           Replace = '$null = 0' }
        @{ Name = "release-not-logged"
           Find = 'if ($held) { Write-HordeHeavySlotLog -Event "release"'
           Replace = 'if ($false) { Write-HordeHeavySlotLog -Event "release"' }
        @{ Name = "give-up-not-logged"
           Find = 'elseif (-not $everHeld -and ($code -eq 125'
           Replace = 'elseif ($false -and ($code -eq 125' }
        @{ Name = "give-up-logs-no-wait"
           Find = '{ $script:waited = [int]$clock.Elapsed.TotalSeconds; Write-HordeHeavySlotLog -Event "gave-up"'
           Replace = '{ Write-HordeHeavySlotLog -Event "gave-up"' }
        @{ Name = "warning-on-every-failed-write"
           Find = 'if (-not $script:logWarned) { $script:logWarned = $true;'
           Replace = 'if ($true) { $script:logWarned = $true;' }
        @{ Name = "failed-log-write-fails-the-run"
           Find = '$script:logWarned = $true; Write-HordeHeavySlotLine'
           Replace = '$script:logWarned = $true; throw "the slot log"; Write-HordeHeavySlotLine' }
        @{ Name = "log-never-capped"
           Find = '.Length -gt 1MB)'
           Replace = '.Length -gt 1GB)' }
    )
}
