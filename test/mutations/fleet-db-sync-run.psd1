# Mutations of the sync's PowerShell half (fleet-db/Sync.ps1): the lock, the time limit, the priority, the log. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-sync-run.psd1
# test\test-db-sync.ps1 must fail a check for every one. Every find string occurs once.
@{
    Target = "fleet-db\Sync.ps1"
    Suite  = "test\test-db-sync.ps1"
    Mutations = @(
        @{ Name = "lock-shared"
           Find = '[System.IO.FileShare]::None)'
           Replace = '[System.IO.FileShare]::ReadWrite)' }
        @{ Name = "held-lock-is-a-failure"
           Find = 'return [pscustomobject]@{ code = 0; outcome = "skipped"'
           Replace = 'return [pscustomobject]@{ code = 1; outcome = "skipped"' }
        @{ Name = "held-lock-not-logged"
           Find = 'Write-HordeDbSyncLog -Path $log -Line ($stamp + " skipped 0 ms | a sync is still running") -MaxBytes $MaxLogBytes'
           Replace = '$null = $stamp' }
        @{ Name = "child-not-killed-on-timeout"
           Find = 'try { if ($p.GetType().GetMethod("Kill", [Type[]]@([bool]))) { $p.Kill($true) } else { $p.Kill() } } catch { }'
           Replace = '$null = $p' }
        @{ Name = "time-limit-five-times-too-long"
           Find = '$p.WaitForExit($TimeLimitSeconds * 1000)'
           Replace = '$p.WaitForExit($TimeLimitSeconds * 5000)' }
        @{ Name = "timeout-exits-zero"
           Find = 'return [pscustomobject]@{ code = 1; outcome = "timeout"'
           Replace = 'return [pscustomobject]@{ code = 0; outcome = "timeout"' }
        @{ Name = "node-not-lowered"
           Find = 'try { $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal } catch { }'
           Replace = '$null = $p' }
        @{ Name = "failure-logged-as-ok"
           Find = '$stamp + " failed " + $ms'
           Replace = '$stamp + " ok " + $ms' }
        @{ Name = "log-never-cut"
           Find = 'if ($MayCut -and [System.IO.File]::Exists($Path)'
           Replace = 'if ($false -and [System.IO.File]::Exists($Path)' }
        @{ Name = "log-cut-keeps-everything"
           Find = 'if ($size -gt ($MaxBytes / 2)) { break }'
           Replace = 'if ($false) { break }' }
    )
}
