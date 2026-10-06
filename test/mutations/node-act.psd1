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
        @{ Name = "process-believed-without-start-time"
           Find = 'if ($null -ne $live -and "" + $live -ceq "" + $i.value.procStart) { return $i.value }'
           Replace = 'return $i.value' }
        @{ Name = "unidentified-pane-left-running"
           Find = '$null = Stop-HordeNodeSession -Context $Context -Actor $actor -Adapter $adapter -Handle ("" + $record.handle)'
           Replace = '$null = $record.handle' }
        @{ Name = "unreadable-mode-kept"
           Find = 'if ($null -eq $mode) { $why = "the session''s permission mode could not be read back within " + $Context.bounds.modeSeconds + " s, so it is not kept (fail closed)" }'
           Replace = 'if ($false) { }' }
        @{ Name = "other-mode-kept"
           Find = 'elseif ("" + $mode.value -cne $d.level) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "refused-session-not-forced"
           Find = '    $null = & $Actor.stop $Handle'
           Replace = '' }
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
        @{ Name = "cap-counts-nothing"
           Find = 'if ("" + $r.startedAt -like ($day + "*")) { $n++ }'
           Replace = '' }
        @{ Name = "expect-without-namespace"
           Find = '$expect = [pscustomobject][ordered]@{ ns = [pscustomobject][ordered]@{ device = "" + $Context.namespace.device; space = "" + $Context.namespace.space }; pid = [long]$record.pid; procStart = $record.procStart }'
           Replace = '$expect = [pscustomobject][ordered]@{ ns = $null; pid = [long]$record.pid; procStart = $record.procStart }' }
        @{ Name = "level-from-request-ignored"
           Find = 'if ($null -ne $a.PSObject.Properties["permission"] -and "" + $a.permission -ne "") { $set["permission"] = "" + $a.permission }'
           Replace = '' }
    )
}
