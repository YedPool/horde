# Mutations of remote/NodeServe.ps1's act half (remote R19, the act path's A3). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\node-serve-act.psd1
# test\test-node-serve-act.ps1 must fail for every one: each lets an act happen twice, happen without
# a record, or answer something other than what was recorded.
@{
    Target = "remote\NodeServe.ps1"
    Suite  = "test\test-node-serve-act.ps1"
    Mutations = @(
        # R17c (2026-10-07): read-only decides before the act dispatch.
        @{ Name = "act-before-read-only"
           Find = 'if ($null -ne $roAct) { return $roAct }'
           Replace = '' }
        @{ Name = "acts-without-journal"
           Find = 'if ($journal -eq "") { return (New-HordeNodeReply -Reply (New-HordeNodeError -State $State -Request $Frame -Code "refused" -Reason "this node keeps no request journal'
           Replace = 'if ($false) { return (New-HordeNodeReply -Reply (New-HordeNodeError -State $State -Request $Frame -Code "refused" -Reason "this node keeps no request journal' }
        @{ Name = "replay-acts-again"
           Find = '            "replay" {'
           Replace = '            "replay-off" {' }
        @{ Name = "reused-id-acts"
           Find = '            "refuse" { return (New-HordeNodeReply -Reply (New-HordeNodeError -State $State -Request $Frame -Code "refused" -Reason "$($o.reason)")) }'
           Replace = '            "refuse" { return (New-HordeNodeReply -NeedAct $true -Act ([pscustomobject]@{ verb = $verb; args = $Frame.args; requestId = "$($Frame.requestId)" })) }' }
        @{ Name = "prompt-both-accepted"
           Find = 'if ($hasText -and $hasRef) { return "a spawn''s prompt is text or a handoff reference, not both" }'
           Replace = '' }
        @{ Name = "handoff-ref-accepted"
           Find = 'if ($hasRef) { return "a prompt given as a handoff reference is not served yet (R14); send its text" }'
           Replace = '' }
        @{ Name = "second-outcome-overwrites"
           Find = 'if ($existing.state -ceq "known" -and "$($existing.value.state)" -cne "accepted") {'
           Replace = 'if ($false) {' }
        @{ Name = "outcome-drops-process"
           Find = '            $out["expect"] = [ordered]@{'
           Replace = '            $out["expectX"] = [ordered]@{' }
        @{ Name = "acts-served-always"
           Find = 'if ($script:HordeNodeActVerbs -ccontains $verb -and (Get-HordeLinkProp $Data "acts") -eq $true) {'
           Replace = 'if ($script:HordeNodeActVerbs -ccontains $verb) {' }
        @{ Name = "act-without-hub"
           Find = 'requestId = "$($Frame.requestId)"; hubId = "$($State.peerId)" })) }'
           Replace = 'requestId = "$($Frame.requestId)"; hubId = "" })) }' }
    )
}
