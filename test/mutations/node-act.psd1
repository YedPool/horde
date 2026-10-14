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
           Find = '        $why = "the session''s permission mode could not be read back within " + $Context.bounds.modeSeconds + " s" + $limit + ", so it is not kept (fail closed)"'
           Replace = '        $why = ""' }
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
        @{ Name = "prompt-in-argv"
           Find = '-Name $name -Prompt "" -Resolve $resolveProgram'
           Replace = '-Name $name -Prompt $prompt -Resolve $resolveProgram' }
        @{ Name = "prompt-failure-done"
           Find = 'if ($sent.state -eq "unsent") {'
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
           Find = '-SessionId $sid -Line $script:HordeNodeNoOpLine'
           Replace = '-SessionId $sid -Line $prompt' }
        @{ Name = "no-op-dropped"
           Find = '    $noop = Submit-HordeNodeLine -Context $Context -Actor $actor -Target $term -Adapter $adapter -Handle $record.handle -SessionId $sid -Line $script:HordeNodeNoOpLine'
           Replace = '    $noop = [pscustomobject]@{ state = "taken"; extraEnter = $false; reason = "" }' }
        @{ Name = "no-op-failure-read-anyway"
           Find = 'if ($noop.state -ne "unsent") {'
           Replace = 'if ($true) {' }
        @{ Name = "no-op-unrecorded"
           Find = '$record.noOp = $script:HordeNodeNoOpLine; $record.noOpTurn'
           Replace = '$record.noOp = ""; $record.noOpTurn' }
        @{ Name = "prompt-before-mode-kept"
           Find = '$gone = Stop-HordeNodeSession -Context $base -Actor $actor -Target $term -Adapter $adapter -Handle $record.handle -ProcessId $record.pid -ProcStart $record.procStart -SkipCloseText:($noop.state -ne "taken" -or (Test-HordeNodeDeadlinePassed -Context $Context -Within $closeTextSeconds))'
           Replace = '$null = Send-HordeNodePrompt -Context $Context -Actor $actor -Target $term -Adapter $adapter -Handle $record.handle -SessionId $sid -PromptDir $pd -Prompt $prompt; $gone = Stop-HordeNodeSession -Context $base -Actor $actor -Target $term -Adapter $adapter -Handle $record.handle -ProcessId $record.pid -ProcStart $record.procStart -SkipCloseText:($noop.state -ne "taken" -or (Test-HordeNodeDeadlinePassed -Context $Context -Within $closeTextSeconds))' }
        @{ Name = "raw-prompt-typed"
           Find = '-SessionId $SessionId -Line $line'
           Replace = '-SessionId $SessionId -Line $Prompt' }
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
        # Issue #214: a spawn is done only when its prompt line became a turn.
        @{ Name = "prompt-not-submitted-reported-done"
           Find = '    if ($sent.state -eq "not-taken") {'
           Replace = '    if ($false) {' }
        @{ Name = "prompt-unconfirmed-reported-done"
           Find = '    if ($sent.state -eq "unknown") {'
           Replace = '    if ($false) {' }
        @{ Name = "noop-not-submitted-ignored"
           Find = '    if ($noop.state -eq "not-taken") {'
           Replace = '    if ($false) {' }
        @{ Name = "extra-enter-into-an-empty-box"
           Find = '    elseif ($box.value -ne $true) {'
           Replace = '    elseif ($false) {' }
        @{ Name = "unreadable-box-not-said"
           Find = '    if ($null -eq $box -or $box.state -ne "known") { $boxSaid ='
           Replace = '    if ($false) { $boxSaid =' }
        @{ Name = "second-extra-enter"
           Find = '            if ($true -eq (Wait-HordeNodeUntil -Context $Context -Seconds $Context.bounds.retrySeconds -Probe $look -Whole)) { $out.state = "taken"; return $out }'
           Replace = '            $null = & $Actor.send $Target $Handle "" $true; if ($true -eq (Wait-HordeNodeUntil -Context $Context -Seconds $Context.bounds.retrySeconds -Probe $look -Whole)) { $out.state = "taken"; return $out }' }
        @{ Name = "mark-from-the-start"
           Find = '    if ($canTell) { $mark = & $Adapter.turnMark $SessionId $Context.environment }'
           Replace = '    if ($canTell) { $mark = New-HordeKnown -Value ([pscustomobject]@{ n = 0; size = [long]0 }) }' }
        @{ Name = "receipt-not-waited"
           Find = '-Seconds $Context.bounds.receiptSeconds -Probe $look'
           Replace = '-Seconds 0 -Probe $look' }
        @{ Name = "cannot-tell-taken"
           Find = '    if (-not $canTell) { $out.reason ='
           Replace = '    if (-not $canTell) { $out.state = "taken"; $out.reason =' }
        @{ Name = "receipt-wait-past-the-hub"
           Find = 'receiptSeconds = 20; retrySeconds = 10;'
           Replace = 'receiptSeconds = 120; retrySeconds = 10;' }
        @{ Name = "not-ready-typed-into"
           Find = '    if ($ready.state -eq "not-ready") {'
           Replace = '    if ($false) {' }
        @{ Name = "ready-not-waited"
           Find = '$ok = Wait-HordeNodeUntil -Context $Context -Seconds ([double]$Context.bounds.readySeconds)'
           Replace = '$ok = Wait-HordeNodeUntil -Context $Context -Seconds 0' }
        @{ Name = "turn-end-not-waited"
           Find = '    if ($noop.state -eq "taken") { $noopEnd = Wait-HordeNodeTurnEnd'
           Replace = '    if ($false) { $noopEnd = Wait-HordeNodeTurnEnd' }
        @{ Name = "unended-turn-typed-into"
           Find = '    if ($noopEnd.state -eq "not-ended") {'
           Replace = '    if ($false) {' }
        @{ Name = "close-text-into-a-stuck-box"
           Find = '-SkipCloseText:($noop.state -ne "taken" -or (Test-HordeNodeDeadlinePassed -Context $Context -Within $closeTextSeconds))'
           Replace = '-SkipCloseText:$false' }
        @{ Name = "stuck-noop-not-named"
           Find = '        if ($noop.state -ne "taken") { $why += '
           Replace = '        if ($false) { $why += ' }
        @{ Name = "waits-count-polls"
           Find = '    if ($null -ne $start) {'
           Replace = '    if ($false) {' }
        @{ Name = "spawn-limit-ignored"
           Find = '        if (-not $Whole -and $null -ne $Context.PSObject.Properties["deadlineMs"] -and [double]$Context.deadlineMs -lt $until) { $until = [double]$Context.deadlineMs }'
           Replace = '' }
        @{ Name = "spawn-limit-past-the-hub"
           Find = 'spawnSeconds = 130;'
           Replace = 'spawnSeconds = 200;' }
        @{ Name = "prompt-typed-past-the-limit"
           Find = '    if ($prompt -ne "" -and (Test-HordeNodeDeadlinePassed -Context $Context -Within $lineSeconds)) {'
           Replace = '    if ($false) {' }
        @{ Name = "line-typed-without-its-wait"
           Find = '$lineSeconds = [double]$base.bounds.receiptSeconds + [double]$base.bounds.retrySeconds'
           Replace = '$lineSeconds = 0' }
        @{ Name = "limit-within-ignored"
           Find = '$now + 1000 * $Within -ge [double]$Context.deadlineMs'
           Replace = '$now -ge [double]$Context.deadlineMs' }
        @{ Name = "noop-typed-past-the-limit"
           Find = 'if (Test-HordeNodeDeadlinePassed -Context $Context -Within $lineSeconds) {'
           Replace = 'if ($false) {' }
        @{ Name = "not-ready-unproven-kept"
           Find = 'if ($null -ne $m -and $m.state -eq "known" -and "" + $m.value -ceq $Level) {'
           Replace = 'if ($null -ne $m) {' }
        @{ Name = "not-ready-proven-closed"
           Find = 'if ($null -ne $m -and $m.state -eq "known" -and "" + $m.value -ceq $Level) {'
           Replace = 'if ($false) {' }
        @{ Name = "not-ready-close-text-typed"
           Find = '-ProcessId $Record.pid -ProcStart $Record.procStart -SkipCloseText'
           Replace = '-ProcessId $Record.pid -ProcStart $Record.procStart' }
        @{ Name = "ready-look-past-the-limit"
           Find = '    if (Test-HordeNodeDeadlinePassed -Context $Context) { return [pscustomobject]@{ state = "not-ready"; reason = "this spawn''s own limit ran out before the screen was looked at" } }'
           Replace = '' }
        @{ Name = "box-read-past-the-limit"
           Find = 'if (Test-HordeNodeDeadlinePassed -Context $Context) { $box = '
           Replace = 'if ($false) { $box = ' }
        @{ Name = "extra-enter-past-the-limit"
           Find = 'elseif (Test-HordeNodeDeadlinePassed -Context $Context) { $boxSaid = '
           Replace = 'elseif ($false) { $boxSaid = ' }
        @{ Name = "close-text-past-the-limit"
           Find = '-SkipCloseText:($noop.state -ne "taken" -or (Test-HordeNodeDeadlinePassed -Context $Context -Within $closeTextSeconds))'
           Replace = '-SkipCloseText:($noop.state -ne "taken")' }
        @{ Name = "close-text-after-an-unknown-noop"
           Find = '-SkipCloseText:($noop.state -ne "taken" -or (Test-HordeNodeDeadlinePassed -Context $Context -Within $closeTextSeconds))'
           Replace = '-SkipCloseText:($noop.state -eq "not-taken" -or (Test-HordeNodeDeadlinePassed -Context $Context -Within $closeTextSeconds))' }
        @{ Name = "limit-from-the-pane-start"
           Find = '-NotePropertyValue ($actStartMs + 1000 * [double]$base.bounds.spawnSeconds)'
           Replace = '-NotePropertyValue ((Get-HordeNodeClockMs -Context $base) + 1000 * [double]$base.bounds.spawnSeconds)' }
        # PR 239 round 4 (F's re-check of round 3): a typed line's waits run whole; the close text only
        # while it and its wait fit; the sum counts terminal calls.
        @{ Name = "receipt-wait-cut-at-the-limit"
           Find = '-Seconds $Context.bounds.receiptSeconds -Probe $look -Whole)'
           Replace = '-Seconds $Context.bounds.receiptSeconds -Probe $look)' }
        @{ Name = "retry-wait-cut-at-the-limit"
           Find = '-Seconds $Context.bounds.retrySeconds -Probe $look -Whole)'
           Replace = '-Seconds $Context.bounds.retrySeconds -Probe $look)' }
        @{ Name = "whole-wait-ignored"
           Find = 'if (-not $Whole -and $null -ne $Context.PSObject.Properties["deadlineMs"]'
           Replace = 'if ($null -ne $Context.PSObject.Properties["deadlineMs"]' }
        @{ Name = "close-text-without-its-wait"
           Find = '$closeTextSeconds = @($adapter.closeText).Count * $hostCall + [double]$base.bounds.closeSeconds'
           Replace = '$closeTextSeconds = 0' }
        @{ Name = "host-call-uncounted"
           Find = 'hostCallSeconds = 20;'
           Replace = 'hostCallSeconds = 0;' }
        # PR 239 round 4 (issue 214): the screen of a session that was not ready, into its record.
        @{ Name = "screen-not-on-never-ready"
           Find = '    $Why += "; " + (Save-HordeNodeScreenReport -Context $Context -Actor $Actor -Target $Target -Record $Record)'
           Replace = '' }
        @{ Name = "screen-not-on-noop-end"
           Find = '        $screenSaid = Save-HordeNodeScreenReport -Context $Context -Actor $actor -Target $term -Record $record'
           Replace = '        $screenSaid = ""' }
        @{ Name = "screen-on-done"
           Find = '    $record.outcome = "running"; Write-HordeNodeSpawnRecord'
           Replace = '    $null = Save-HordeNodeScreenReport -Context $Context -Actor $actor -Target $term -Record $record; $record.outcome = "running"; Write-HordeNodeSpawnRecord' }
        @{ Name = "screen-past-the-limit"
           Find = '    if (Test-HordeNodeDeadlinePassed -Context $Context) { return [pscustomobject]@{ state = "skipped";'
           Replace = '    if ($false) { return [pscustomobject]@{ state = "skipped";' }
        @{ Name = "screen-secret-shown"
           Find = 'if ($kind -cne "") { return [pscustomobject]@{ state = "withheld";'
           Replace = 'if ($false) { return [pscustomobject]@{ state = "withheld";' }
        # F's re-check of round 4, REQUIRED: every reading of the screen is checked (Find-HordeNodeScreenSecret).
        @{ Name = "screen-secret-raw-unchecked"
           Find = 'foreach ($source in @(@{ rows = @($Raw) }, '
           Replace = 'foreach ($source in @(' }
        @{ Name = "screen-secret-kept-unchecked"
           Find = ', @{ rows = @($Kept) })) {'
           Replace = ')) {' }
        @{ Name = "screen-secret-ascii-unstripped"
           Find = ' @{ rows = @($ascii) },'
           Replace = '' }
        @{ Name = "screen-secret-rows-only-by-line"
           Find = 'foreach ($glue in @("`n", "")) {'
           Replace = 'foreach ($glue in @("`n")) {' }
        @{ Name = "screen-secret-never-spaced"
           Find = 'foreach ($form in @($text, $text.Replace("_", " ").Replace("=", "= "))) {'
           Replace = 'foreach ($form in @($text)) {' }
        @{ Name = "screen-secret-underscore-kept"
           Find = '$text.Replace("_", " ").Replace("=", "= ")'
           Replace = '$text.Replace("=", "= ")' }
        @{ Name = "screen-secret-equals-unspaced"
           Find = '.Replace("_", " ").Replace("=", "= ")'
           Replace = '.Replace("_", " ")' }
        @{ Name = "screen-secret-named-kind-unasked"
           Find = '                if ($kind -ceq "") { $kind = Find-HordeSecretKind -Text $form -Kinds @($script:HordeNodeNamedSecretKind) }'
           Replace = '' }
        @{ Name = "screen-secret-finder-unused"
           Find = '    $kind = Find-HordeNodeScreenSecret -Raw ([string[]]@($raw)) -Kept ([string[]]@($rows))'
           Replace = '    $kind = Find-HordeSecretKind -Text ($raw -join "`n")' }
        @{ Name = "screen-rows-uncut"
           Find = '    while ($rows.Count -gt $script:HordeNodeScreenRows) { $rows.RemoveAt(0) }'
           Replace = '' }
        @{ Name = "screen-kept-from-the-top"
           Find = '    while ($rows.Count -gt $script:HordeNodeScreenRows) { $rows.RemoveAt(0) }'
           Replace = '    while ($rows.Count -gt $script:HordeNodeScreenRows) { $rows.RemoveAt($rows.Count - 1) }' }
        @{ Name = "screen-chars-uncut"
           Find = '    while ($rows.Count -gt 1 -and ((@($rows) -join "`n").Length -gt $script:HordeNodeScreenChars)) { $rows.RemoveAt(0) }'
           Replace = '' }
        @{ Name = "screen-blank-runs-kept"
           Find = 'if ($c -eq "" -and ($rows.Count -eq 0 -or $rows[$rows.Count - 1] -eq "")) { continue }'
           Replace = 'if ($false) { continue }' }
        @{ Name = "screen-other-characters-kept"
           Find = '        else { [void]$sb.Append(''?'') }'
           Replace = '        else { [void]$sb.Append($ch) }' }
        @{ Name = "screen-box-glyphs-dropped"
           Find = ' -or ($n -ge 0x2500 -and $n -le 0x257F))'
           Replace = ')' }
        # F's nit of round 4: bounds without hostCallSeconds count 20 s a call.
        @{ Name = "host-call-default-zero"
           Find = '    $hostCall = 20.0'
           Replace = '    $hostCall = 0.0' }
    )
}
