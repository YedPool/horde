# Mutations of the sync's PowerShell half (fleet-db/Sync.ps1): the lock, the time limit, the priority, the log. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-sync-run.psd1
# test\test-db-sync.ps1 must fail a check for every one. Every find string occurs once.
@{
    Target = "fleet-db\Sync.ps1"
    Suite  = "test\test-db-sync.ps1"
    Mutations = @(
        @{ Name = "trailing-backslash-escapes-the-quote"
           Find = '($_ -replace ''(\\+)$'', ''$1$1'')'
           Replace = '$_' }
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
           Find = '$p.WaitForExit($leftMs)'
           Replace = '$p.WaitForExit($leftMs * 5)' }
        @{ Name = "timeout-exits-zero"
           Find = 'return [pscustomobject]@{ code = 1; outcome = "timeout"'
           Replace = 'return [pscustomobject]@{ code = 0; outcome = "timeout"' }
        @{ Name = "node-not-lowered"
           Find = 'try { $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal } catch { }'
           Replace = '$null = $p' }
        @{ Name = "failure-logged-as-ok"
           Find = '$stamp + " failed " + $ms'
           Replace = '$stamp + " ok " + $ms' }
        @{ Name = "snapshot-never-handed-to-node"
           Find = 'if ($snapshot.file -ne "") { $snapArgs = @("--snapshot", $snapshot.file) }'
           Replace = '' }
        @{ Name = "snapshot-child-not-killed"
           Find = 'try { if ($null -ne $p.GetType().GetMethod("Kill", [Type[]]@([bool]))) { $p.Kill($true) } else { $p.Kill() } } catch { }'
           Replace = '$null = $p' }
        @{ Name = "snapshot-limit-ignored"
           Find = 'if (-not $p.WaitForExit($LimitSeconds * 1000)) {'
           Replace = 'if (-not $p.WaitForExit($LimitSeconds * 100000)) {' }
        @{ Name = "snapshot-gets-the-whole-limit"
           Find = '[int][Math]::Floor($TimeLimitSeconds * 0.4)'
           Replace = '$TimeLimitSeconds' }
        @{ Name = "snapshot-file-left-behind"
           Find = 'if ($snapshot.file -ne "" -and [System.IO.File]::Exists($snapshot.file)) { try { [System.IO.File]::Delete($snapshot.file) } catch { } }'
           Replace = '$null = $snapshot' }
        @{ Name = "log-never-cut"
           Find = 'if ($MayCut -and [System.IO.File]::Exists($Path)'
           Replace = 'if ($false -and [System.IO.File]::Exists($Path)' }
        @{ Name = "log-cut-keeps-everything"
           Find = 'if ($size -gt ($MaxBytes / 2)) { break }'
           Replace = 'if ($false) { break }' }
    )
}
