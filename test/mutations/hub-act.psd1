# Mutations of cli/HubAct.ps1 (the act path's A4). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\hub-act.psd1
# test\test-hub-act.ps1 must fail for every one: each makes the hub report what did not happen, or
# close a session by something other than what its node said it started.
@{
    Target = "cli\HubAct.ps1"
    Suite  = "test\test-hub-act.ps1"
    Mutations = @(
        @{ Name = "lost-answer-read-as-answered"
           Find = 'if ($null -eq $got.frame) { $res.reason = $got.reason + "; whether the node acted is unknown'
           Replace = 'if ($null -eq $got.frame) { $res.answered = $true; $res.reason = $got.reason + "; whether the node acted is unknown' }
        @{ Name = "unanswered-printed-as-refused"
           Find = 'if (-not $Res.answered) { return ("UNKNOWN request " + $RequestId + ": " + $Res.reason) }'
           Replace = 'if (-not $Res.answered) { return ("REFUSED request " + $RequestId + ": " + $Res.reason) }' }
        @{ Name = "spawn-found-twice-picks-one"
           Find = 'if ($hits.Count -gt 1) { return (New-HordeUnknown -Reason ("" + $hits.Count + " of the hub''s records claim the session " + $SessionId)) }'
           Replace = '' }
        @{ Name = "refused-spawn-closable"
           Find = '$closable = (@("done", "failed") -ccontains ("" + $r.answer.state)) -and $null -ne $ex -and "" + $ex.pid -ne ""'
           Replace = '$closable = $true' }
        @{ Name = "any-verb-sent"
           Find = 'if ($script:HordeHubActVerbs -cnotcontains $Verb) {'
           Replace = 'if ($false) {' }
        @{ Name = "wrong-node-accepted"
           Find = 'elseif ("$($f.hello.id)" -cne "$($Entry.deviceId)") {'
           Replace = 'elseif ($false) {' }
        @{ Name = "process-not-printed"
           Find = 'if ($null -ne $ex) { $line += " pid " + $ex.pid + " procStart " + $ex.procStart }'
           Replace = '' }
        @{ Name = "status-names-itself"
           Find = '    if ("" + $v.requestId -ne "") { $rid = "" + $v.requestId }'
           Replace = '' }
        @{ Name = "failed-spawn-unclosable"
           Find = '$closable = (@("done", "failed") -ccontains ("" + $r.answer.state)) -and'
           Replace = '$closable = (@("done") -ccontains ("" + $r.answer.state)) -and' }
        @{ Name = "unreadable-record-skipped"
           Find = 'try { $r = ConvertFrom-HordeJson -Text ([System.IO.File]::ReadAllText($f.FullName)) } catch { return (New-HordeUnknown'
           Replace = 'try { $r = ConvertFrom-HordeJson -Text ([System.IO.File]::ReadAllText($f.FullName)) } catch { continue; return (New-HordeUnknown' }
        @{ Name = "close-other-node-allowed"
           Find = '    if ($named -cne $own) {'
           Replace = '    if ($false) {' }
        @{ Name = "contract-unchecked"
           Find = '    if ($bad -ne "") { $res.refusedHere = $true;'
           Replace = '    if ($false) { $res.refusedHere = $true;' }
        @{ Name = "refusal-printed-unknown"
           Find = '    if ($null -ne $Res.PSObject.Properties["refusedHere"] -and $Res.refusedHere) {'
           Replace = '    if ($false) {' }
    )
}
