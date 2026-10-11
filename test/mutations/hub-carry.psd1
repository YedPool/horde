# Mutations of cli/HubCarry.ps1 (mesh v1: the hub carries `horde session`'s requests over a dialled
# link). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\hub-carry.psd1
# test\test-hub-carry.ps1 must fail for every one: each sends a request blind, twice, to a node no longer
# admitted, or out of turn, or reports what did not happen.
@{
    Target = "cli\HubCarry.ps1"
    Suite  = "test\test-hub-carry.ps1"
    Mutations = @(
        @{ Name = "lost-answer-resent-blind"
           Find = 'if ($isAct -and $sent.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "sent-never-written-down"
           Find = 'Set-HordeHubActProp -Record $rec -Name "sentAt" -Value @(@($sent) + @(Get-HordeLinkTime))'
           Replace = '$null = 0' }
        @{ Name = "revoked-before-send-sent-anyway"
           Find = 'if ($cutSend -ne "") {'
           Replace = 'if ($false) {' }
        @{ Name = "revoked-before-status-asked-anyway"
           Find = 'if ($cutAsk -ne "") {'
           Replace = 'if ($false) {' }
        @{ Name = "sent-request-refused-by-hub"
           Find = '        if (@(Get-HordeLinkProp $rec "sentAt" | Where-Object { "$_" -ne "" }).Count -gt 0) { continue }'
           Replace = '' }
        @{ Name = "absent-taken-as-unknown"
           Find = 'elseif ("$($sv.state)" -cne "absent") {'
           Replace = 'elseif ($true) {' }
        @{ Name = "accepted-taken-as-final"
           Find = '@("done", "failed", "refused") -ccontains "$($sv.value.state)"'
           Replace = '$true' }
        @{ Name = "status-unanswered-link-reused"
           Find = '                if (-not $st.answered) { break }'
           Replace = ''
           Expect = "survives"
           Reason = "a request.status that gets no answer needs a node that answers its acts but not its reads; the fixture node answers every read at once. The rule is the same one lost-answer-link-reused proves for the send path." }
        @{ Name = "lost-answer-link-reused"
           Find = '            break  # an answer was lost'
           Replace = '            # an answer was lost' }
        @{ Name = "queue-takes-other-devices"
           Find = '-or "$($r.deviceId)" -cne $DeviceId) { continue }'
           Replace = ') { continue }' }
        @{ Name = "queue-takes-undialled"
           Find = 'if ("$(Get-HordeLinkProp $r ''via'')" -cne $script:HordeHubDialledRoute -or'
           Replace = 'if ($false -or' }
        @{ Name = "queue-takes-settled"
           Find = '        if (-not (Test-HordeHubActPending -Record $r)) { continue }'
           Replace = '' }
        @{ Name = "queue-ignores-file-name"
           Find = 'if ($f.Name -cne ("$($r.requestId)" + ".json")) {'
           Replace = 'if ($false) {' }
        @{ Name = "queue-out-of-issue-order"
           Find = '$sorted = @($out | Sort-Object -Property @{ Expression = { "$($_.issuedAt)" } }, @{ Expression = { "$($_.requestId)" } })'
           Replace = '$sorted = @($out)' }
        @{ Name = "unreadable-record-silent"
           Find = 'catch { [void]$skipped.Add("the hub''s record " + $f.Name + " cannot be read, so it is not carried: " + $_.Exception.Message); continue }'
           Replace = 'catch { continue }' }
        @{ Name = "read-treated-as-act"
           Find = '$isAct = $script:HordeHubCarryActVerbs -ccontains $verb'
           Replace = '$isAct = $true' }
        @{ Name = "node-cannot-say-taken-as-answer"
           Find = 'elseif ("$($r.result.state)" -ceq "known" -and $isAct) {'
           Replace = 'elseif ($isAct) {' }
        @{ Name = "node-refusal-not-kept"
           Find = 'if ($null -ne $r.error) { Set-HordeHubActProp -Record $rec -Name "error" -Value $r.error }'
           Replace = 'if ($null -ne $r.error) { }' }
        @{ Name = "unsendable-sent-anyway"
           Find = '        if ($bad -ne "") {'
           Replace = '        if ($false) {' }
        @{ Name = "uncarried-verb-sent"
           Find = 'if ($script:HordeHubActVerbs -cnotcontains $verb) { $bad = "the hub does not carry " + $verb }'
           Replace = 'if ($false) { $bad = "the hub does not carry " + $verb }' }
        @{ Name = "queued-printed-unknown"
           Find = 'if (@(Get-HordeLinkProp $Record "sentAt" | Where-Object { "$_" -ne "" }).Count -eq 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "wait-returns-before-answer"
           Find = 'if ($null -ne $last -and -not (Test-HordeHubActPending -Record $last)) { return $last }'
           Replace = 'if ($null -ne $last) { return $last }' }
    )
}
