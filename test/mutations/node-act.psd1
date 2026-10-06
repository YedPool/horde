# Mutations of cli/NodeAct.ps1 (remote R19 and R9, the act path's A3). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\node-act.psd1
# test\test-node-act.ps1 must fail for every one. Each breaks a rule that keeps a hub from starting,
# keeping or ending a session the node's owner did not allow.
@{
    Target = "cli\NodeAct.ps1"
    Suite  = "test\test-node-act.ps1"
    Mutations = @(
        @{ Name = "policy-ignored"
           Find = 'if (-not $d.allowed) { return (New-HordeNodeOutcome -State "refused" -Reason (@($d.reasons) -join "; ")) }'
           Replace = 'if ($false) { }' }
        @{ Name = "env-credential-allowed"
           Find = 'if (-not (Test-HordeNodeOwnLogin -Layers $layers -Provider ("" + $res.binding.value.provider))) {'
           Replace = 'if ($false) {' }
        @{ Name = "missing-folder-allowed"
           Find = 'if (-not (& $Context.workdirExists $d.workdir)) {'
           Replace = 'if ($false) {' }
        @{ Name = "owned-variables-kept"
           Find = 'foreach ($o in @($owned)) { if ($null -ne $o) { $envMap["" + $o.name] = $null } }'
           Replace = '' }
        @{ Name = "unreadable-mode-kept"
           Find = 'if ($null -eq $mode) { $why = "the session''s permission mode could not be read back within " + $Context.bounds.modeSeconds + " s, so it is not kept (fail closed)" }'
           Replace = 'if ($false) { }' }
        @{ Name = "other-mode-kept"
           Find = 'elseif ("" + $mode.value -cne $d.level) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "close-without-record"
           Find = 'if ($rec.state -ne "known") { return (New-HordeNodeOutcome -State "refused" -SessionId $sid -Reason $rec.reason) }'
           Replace = 'if ($rec.state -ne "known") { $rec = [pscustomobject]@{ value = [pscustomobject]@{ pid = $a.expect.pid; procStart = $a.expect.procStart; host = "fakehost"; harness = "harness-a"; handle = "100"; closedAt = ""; outcome = "" } } }' }
        @{ Name = "close-other-device"
           Find = 'if ($local.state -ne "known" -or -not $local.value) {'
           Replace = 'if ($false) {' }
        @{ Name = "close-other-start-time"
           Find = 'if ($same.state -ne "known" -or -not $same.value) {'
           Replace = 'if ($false) {' }
        @{ Name = "close-forces"
           Find = 'if ($gone -ne $true) { return (New-HordeNodeOutcome -State "failed" -SessionId $sid -Reason ("the session is still running "'
           Replace = 'if ($gone -ne $true) { $null = & $ac.value.stop ("" + $r.handle); return (New-HordeNodeOutcome -State "failed" -SessionId $sid -Reason ("the session is still running "' }
        @{ Name = "expect-without-namespace"
           Find = '$expect = [pscustomobject][ordered]@{ ns = [pscustomobject][ordered]@{ device = "" + $Context.namespace.device; space = "" + $Context.namespace.space }; pid = [long]$record.pid; procStart = $record.procStart }'
           Replace = '$expect = [pscustomobject][ordered]@{ ns = $null; pid = [long]$record.pid; procStart = $record.procStart }' }
        @{ Name = "level-from-request-ignored"
           Find = 'if ($null -ne $a.PSObject.Properties["permission"] -and "" + $a.permission -ne "") { $set["permission"] = "" + $a.permission }'
           Replace = '' }
        @{ Name = "process-believed-without-start-time"
           Find = 'if ($null -ne $live -and (Test-HordeNodeSameStart $live $i.value.procStart)) { return $i.value }'
           Replace = 'return $i.value' }
        @{ Name = "start-compared-to-the-millisecond"
           Find = 'return [bool]([decimal]::Floor($x / 10) -eq [decimal]::Floor($y / 10))'
           Replace = 'return [bool]([decimal]::Floor($x / 10000) -eq [decimal]::Floor($y / 10000))' }
        @{ Name = "refused-session-not-forced"
           Find = '    $null = & $Actor.stop $Target $Handle ([pscustomobject]@{ pid = $ProcessId; procStart = $ProcStart })'
           Replace = '' }
        @{ Name = "unproven-pane-not-told"
           Find = '$null = Send-HordeNodeCloseText -Actor $actor -Target $term -Handle $record.handle -Adapter $adapter'
           Replace = '$null = $record.handle' }
        @{ Name = "layer-problems-ignored"
           Find = 'if ($bad.Count -gt 0) { return (New-HordeNodeOutcome -State "refused" -Reason ("this node''s engine configuration fails its checks'
           Replace = 'if ($false) { return (New-HordeNodeOutcome -State "refused" -Reason ("this node''s engine configuration fails its checks' }
        @{ Name = "own-terminal-unchecked"
           Find = 'if ($null -eq $tg -or $tg.state -ne "known") { return (New-HordeNodeOutcome -State "refused" -Reason ("this node cannot name its own terminal: "'
           Replace = 'if ($false) { return (New-HordeNodeOutcome -State "refused" -Reason ("this node cannot name its own terminal: "' }
        @{ Name = "lock-not-taken"
           Find = 'if ($null -eq $lock) { return (New-HordeNodeOutcome -State "refused" -Reason "another spawn on this node holds its spawn lock'
           Replace = 'if ($false) { return (New-HordeNodeOutcome -State "refused" -Reason "another spawn on this node holds its spawn lock' }
        @{ Name = "lock-shared"
           Find = '[System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)'
           Replace = '[System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::ReadWrite)' }
        @{ Name = "future-records-free-the-cap"
           Find = 'if (-not $ok -or $t -ge $midnight) { $n++ }'
           Replace = 'if (-not $ok -or ($t -ge $midnight -and $t -lt $midnight.AddDays(1))) { $n++ }' }
        @{ Name = "torn-records-free-the-cap"
           Find = 'try { $r = [System.IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json } catch { $n++; continue }'
           Replace = 'try { $r = [System.IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json } catch { continue }' }
        @{ Name = "local-day-not-utc"
           Find = '$midnight = $Now.ToUniversalTime().Date'
           Replace = '$midnight = $Now.Date' }
        @{ Name = "junction-counted"
           Find = 'if (Test-HordeNodeReparse -Path $Dir) {'
           Replace = 'if ($false) {' }
        @{ Name = "unread-count-allows"
           Find = 'if ($today.state -ne "known") { return (New-HordeNodeOutcome -State "refused" -Reason $today.reason) }'
           Replace = '' }
    )
}
