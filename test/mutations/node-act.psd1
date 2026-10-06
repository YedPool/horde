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
           Replace = 'if ($gone -ne $true) { $null = & $ac.value.stop $tg.value ("" + $r.handle) ([pscustomobject]@{ pid = [long]$r.pid; procStart = "" + $r.procStart }); return (New-HordeNodeOutcome -State "failed" -SessionId $sid -Reason ("the session is still running "' }
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
        @{ Name = "local-time-accepted"
           Find = 'if ($Now.Kind -ne [System.DateTimeKind]::Utc) {'
           Replace = 'if ($false) {' }
        @{ Name = "junction-counted"
           Find = 'if (Test-HordeNodeReparse -Path $Dir) {'
           Replace = 'if ($false) {' }
        @{ Name = "unread-count-allows"
           Find = 'if ($today.state -ne "known") { return (New-HordeNodeOutcome -State "refused" -Reason $today.reason) }'
           Replace = '' }
        @{ Name = "config-read-once"
           Find = 'try { $cfg = & $Context.readConfig $Context }'
           Replace = 'try { if ($null -eq $script:HordeNodeCfgCache) { $script:HordeNodeCfgCache = & $Context.readConfig $Context }; $cfg = $script:HordeNodeCfgCache }' }
        @{ Name = "context-config-frozen"
           Find = 'readConfig = { param($c) Read-HordeNodeActConfig -Root $c.root -HordeHome $c.home -Descriptors $c.descriptors -Builtin $c.builtin }'
           Replace = 'readConfig = { param($c) $now }.GetNewClosure()' }
        @{ Name = "unkept-answered-refused"
           Find = 'return (New-HordeNodeOutcome -State "failed" -SessionId $sid -Expect $expect -Reason ($why + "; it could NOT be ended'
           Replace = 'return (New-HordeNodeOutcome -State "refused" -SessionId $sid -Expect $expect -Reason ($why + "; it could NOT be ended' }
        @{ Name = "unkept-without-process"
           Find = 'return (New-HordeNodeOutcome -State "failed" -SessionId $sid -Expect $expect -Reason ($why + "; it could NOT be ended'
           Replace = 'return (New-HordeNodeOutcome -State "failed" -SessionId $sid -Reason ($why + "; it could NOT be ended' }
        @{ Name = "unkept-recorded-closed"
           Find = '$record.outcome = "unkept-running"; Write-HordeNodeSpawnRecord'
           Replace = '$record.outcome = "unkept-running"; $record.closedAt = "x"; Write-HordeNodeSpawnRecord' }
        @{ Name = "unkept-no-alert"
           Find = '& $Context.alert ("ALERT: session " + $sid + " (pane " + $record.handle + ", pid " + $record.pid + ") is still running and could not be ended: " + $why)'
           Replace = '' }
        @{ Name = "not-json-dropped"
           Find = 'catch { [void]$problems.Add($path + ": not JSON") }'
           Replace = 'catch { }' }
        @{ Name = "findings-dropped"
           Find = 'foreach ($f in $findings) { [void]$problems.Add($f.source + " " + $f.path + ": " + $f.code + " - " + $f.detail) }'
           Replace = '' }
        @{ Name = "live-layer-unread"
           Find = 'foreach ($pair in @(@("L1", "engine.json"), @("L4", "engine-live.json"))) {'
           Replace = 'foreach ($pair in @(,@("L1", "engine.json"))) {' }
        @{ Name = "prompt-in-argv"
           Find = '-Name $name -Prompt "" -Resolve $resolveProgram'
           Replace = '-Name $name -Prompt $prompt -Resolve $resolveProgram' }
        @{ Name = "prompt-failure-done"
           Find = 'if ($notSent -ne "") {'
           Replace = 'if ($false) {' }
        @{ Name = "reconcile-skipped"
           Find = 'if ("" + $r.outcome -cne "starting") { continue }'
           Replace = 'continue' }
        @{ Name = "reconcile-all-running"
           Find = 'if ($null -ne $pidv -and -not (Test-HordeNodeProcessGone -Context $Context -ProcessId $pidv -ProcStart $ps)) {'
           Replace = 'if ($null -ne $pidv) {' }
        @{ Name = "reconcile-believes-harness-without-start"
           Find = 'if ($null -ne $live -and (Test-HordeNodeSameStart $live $i.value.procStart)) { $pidv = [long]$i.value.pid; $ps = "" + $i.value.procStart }'
           Replace = '$pidv = [long]$i.value.pid; $ps = "" + $live' }
        @{ Name = "reconcile-no-alert"
           Find = '            & $Context.alert $msg'
           Replace = '' }
        @{ Name = "chain-leaf-only"
           Find = 'foreach ($seg in $full.Substring($base.Length + 1).Split($sep)) {'
           Replace = 'foreach ($seg in @()) {' }
        @{ Name = "chain-after-folder"
           Find = '$chain = Test-HordeNodeRecordsChain -HordeHome $Context.home -Dir $Context.records'
           Replace = 'New-Item -ItemType Directory -Path $Context.records -Force | Out-Null; $chain = Test-HordeNodeRecordsChain -HordeHome $Context.home -Dir $Context.records' }
        @{ Name = "chain-outside-home"
           Find = 'if (-not $full.StartsWith($base + $sep, [System.StringComparison]::OrdinalIgnoreCase)) {'
           Replace = 'if ($false) {' }
        @{ Name = "close-any-hub"
           Find = 'if ("" + $r.hubId -eq "" -or "" + $r.hubId -cne "" + $Act.hubId) {'
           Replace = 'if ($false) {' }
        @{ Name = "spawn-without-hub"
           Find = 'if ($hubId -eq "") { return (New-HordeNodeOutcome -State "refused" -Reason "the request names no hub, so no hub could close the session; nothing is started") }'
           Replace = '' }
        @{ Name = "prompt-sent-first"
           Find = '$noop = & $actor.send $term $record.handle $script:HordeNodeNoOpLine $true'
           Replace = '$noop = & $actor.send $term $record.handle $prompt $true' }
        @{ Name = "no-op-dropped"
           Find = '$noop = & $actor.send $term $record.handle $script:HordeNodeNoOpLine $true'
           Replace = '$noop = New-HordeKnown -Value $true' }
        @{ Name = "no-op-failure-read-anyway"
           Find = 'if ($null -ne $noop -and $noop.state -eq "known") {'
           Replace = 'if ($true) {' }
        @{ Name = "no-op-unrecorded"
           Find = '$record.noOp = $script:HordeNodeNoOpLine; $record.noOpAt'
           Replace = '$record.noOp = ""; $record.noOpAt' }
        @{ Name = "prompt-before-mode-kept"
           Find = '$gone = Stop-HordeNodeSession -Context $Context -Actor $actor -Target $term -Adapter $adapter -Handle $record.handle -ProcessId $record.pid -ProcStart $record.procStart'
           Replace = '$null = Send-HordeNodePrompt -Context $Context -Actor $actor -Target $term -Handle $record.handle -PromptDir $pd -Prompt $prompt; $gone = Stop-HordeNodeSession -Context $Context -Actor $actor -Target $term -Adapter $adapter -Handle $record.handle -ProcessId $record.pid -ProcStart $record.procStart' }
        @{ Name = "raw-prompt-typed"
           Find = '    $r = & $Actor.send $Target $Handle $line $true'
           Replace = '    $r = & $Actor.send $Target $Handle $Prompt $true' }
        @{ Name = "typed-line-mode-prefix-allowed"
           Find = 'return [bool]("!/#@".IndexOf($Line[0]) -lt 0)'
           Replace = 'return $true' }
        @{ Name = "typed-line-non-ascii-allowed"
           Find = 'if ($Line -cnotmatch ''\A[\x20-\x7E]+\z'') { return $false }'
           Replace = 'if ($Line -cmatch ''[\r\n]'') { return $false }' }
        @{ Name = "prompt-folder-not-granted"
           Find = '-Prompt "" -Resolve $resolveProgram -AddDirs @($pd.dir)'
           Replace = '-Prompt "" -Resolve $resolveProgram' }
        @{ Name = "records-root-granted"
           Find = '-Prompt "" -Resolve $resolveProgram -AddDirs @($pd.dir)'
           Replace = '-Prompt "" -Resolve $resolveProgram -AddDirs @($Context.records)' }
        @{ Name = "prompt-folder-inherits"
           Find = '$sec.SetAccessRuleProtection($true, $false)'
           Replace = '$sec.SetAccessRuleProtection($false, $true)' }
        @{ Name = "prompt-folder-chain-unchecked"
           Find = '    if ($chain -ne "") { $out.reason = $chain; return $out }'
           Replace = '' }
        @{ Name = "untypeable-path-started"
           Find = 'if (-not (Test-HordeNodeTypedLine -Line $line)) { $out.reason ='
           Replace = 'if ($false) { $out.reason =' }
    )
}
