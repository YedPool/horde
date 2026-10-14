# Mutations of remote/NodeServe.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\node-serve.psd1
# Each breaks one rule of what a node answers (remote plan R12a); test\test-node-serve.ps1 must fail for
# every one of them. HORDE_FAIL_FAST stops a mutant's run at its first failed check: the suite ends with
# the loop over the memory transport, and a caught mutant need not wait for it.
@{
    Target = "remote\NodeServe.ps1"
    Suite  = "test\test-node-serve.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "unserved-verb-not-refused"
           Find = 'if ($script:HordeNodeServedVerbs -cnotcontains $verb) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "act-verb-served"
           Find = '$script:HordeNodeServedVerbs = @("node.info", "sessions.list", "session.get", "request.status", "session.deliver",'
           Replace = '$script:HordeNodeServedVerbs = @("node.info", "sessions.list", "session.get", "request.status", "session.close", "session.deliver",' }
        @{ Name = "complete-ignores-unreadable-stores"
           Find = 'if (-not ($st -ceq "known" -and $v -is [bool] -and $v)) {'
           Replace = 'if ($false) {' }
        @{ Name = "transcript-path-crosses"
           Find = '        sessionId = "$(Get-HordeLinkProp $Session ''sessionId'')"'
           Replace = '        sessionId = "$(Get-HordeLinkProp $Session ''sessionId'')"; transcriptPath = Get-HordeNodeFieldAnswer -Fields $f -Name "transcriptPath" -Kind "place" -ViewObservedAt $ViewObservedAt' }
        @{ Name = "namespace-dropped"
           Find = 'if ($null -ne $Namespace) { $w["ns"] ='
           Replace = 'if ($false) { $w["ns"] =' }
        @{ Name = "unrepresentable-value-sent"
           Find = 'if (-not $fits) { $w ='
           Replace = 'if ($false) { $w =' }
        @{ Name = "no-journal-is-absent"
           Find = '[ordered]@{ state = "unknown"; reason = "this node keeps no request journal yet" }'
           Replace = '[ordered]@{ state = "absent"; reason = "this node keeps no request journal yet"; observedAt = $now }' }
        @{ Name = "hub-bye-not-closing"
           Find = 'if ($kind -ceq "bye") { return (New-HordeNodeReply -Close $true) }'
           Replace = 'if ($kind -ceq "bye") { return (New-HordeNodeReply -Close $false) }' }
        @{ Name = "bad-line-not-closing"
           Find = '-Reason "$($got.reason)" -Seq (Get-HordeNodeNextSeq $State) -Contract $State.contract) -Close $true)'
           Replace = '-Reason "$($got.reason)" -Seq (Get-HordeNodeNextSeq $State) -Contract $State.contract) -Close $false)' }
        @{ Name = "no-common-protocol-accepted"
           Find = 'if ($null -ne $r.bye) {'
           Replace = 'if ($false) {' }
        @{ Name = "pong-forgets-t1"
           Find = 't1 = "$($f.ping.t1)"'
           Replace = 't1 = $t2' }
        @{ Name = "hello-names-another-device"
           Find = '$h = [ordered]@{ role = "node"; id = $State.nodeId;'
           Replace = '$h = [ordered]@{ role = "node"; id = "7c9e6679-7425-40de-944b-e07fc1f90ae7";' }
        @{ Name = "request-before-hello-answered"
           Find = 'if ($kind -ceq "req") { return (New-HordeNodeReply -Reply (New-HordeNodeError -State $State -Request $f -Code "refused" -Reason "no request is answered before the hello")) }'
           Replace = '' }
        @{ Name = "view-not-asked-for"
           Find = 'if ($null -eq $Data.view) { return (New-HordeNodeReply -NeedView $true) }'
           Replace = '' }
        @{ Name = "view-error-ignored"
           Find = 'if ("$($Data.viewError)" -ne "") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "no-store-is-complete"
           Find = 'if ($pairs.Count -eq 0) { [void]$bad.Add('
           Replace = 'if ($false) { [void]$bad.Add(' }
        @{ Name = "missing-from-incomplete-is-absent"
           Find = 'if ($unread.Count -eq 0) { return'
           Replace = 'if ($true) { return' }
        @{ Name = "session-id-ignoring-case"
           Find = '"$(Get-HordeLinkProp $s ''sessionId'')" -cne $want) { continue }'
           Replace = '"$(Get-HordeLinkProp $s ''sessionId'')" -ne $want) { continue }' }
        @{ Name = "twin-ids-answered-first-found"
           Find = 'if ($found.Count -gt 1) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "agent-not-matched"
           Find = 'if ("$(Get-HordeLinkProp $ag ''value'')" -cne $wantAgent) { continue }'
           Replace = '' }
        @{ Name = "reason-not-cut"
           Find = '$out["reason"] = Limit-HordeNodeReason $reason'
           Replace = '$out["reason"] = $reason' }
        @{ Name = "uncarriable-id-sent"
           Find = 'if (-not (Test-HordeNodeSessionId -Id "$(Get-HordeLinkProp $s ''sessionId'')" -Contract $Contract)) { $skipped++; continue }'
           Replace = '' }
        @{ Name = "list-cap-ignored"
           Find = 'if ($list.Count -ge $script:HordeNodeListItems) { $over++; continue }'
           Replace = '' }
        @{ Name = "place-bytes-unchecked"
           Find = ' -and (Measure-HordeWireString $v) -le $script:HordeNodeNameBytes'
           Replace = '' }
        @{ Name = "view-time-not-defaulted"
           Find = '    if ($at -cmatch $script:HordeNodeTimePattern) { return $at }'
           Replace = '    return $at' }
        @{ Name = "hub-role-unchecked"
           Find = 'if ("$($f.hello.role)" -cne "hub") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "second-hello-renegotiates"
           Find = 'if ($State.helloDone) { return (New-HordeNodeBye'
           Replace = 'if ($false) { return (New-HordeNodeBye' }
        @{ Name = "answer-names-another-frame"
           Find = 'requestId = "$($Request.requestId)"; re = "$($Request.id)"; result = $result'
           Replace = 'requestId = "$($Request.requestId)"; re = (New-HordeLinkFrameId); result = $result' }
        @{ Name = "seq-not-advanced"
           Find = '    $State.seq = $State.seq + 1'
           Replace = '    $State.seq = 1' }
        @{ Name = "retired-not-a-bool"
           Find = '"bool" { $fits = ($v -is [bool]) }'
           Replace = '"bool" { $fits = $true }' }
        @{ Name = "contract-read-per-frame"
           Find = '$got = ConvertFrom-HordeFrameBytes -Bytes $bytes -Contract $State.contract'
           Replace = '$got = ConvertFrom-HordeFrameBytes -Bytes $bytes' }
        @{ Name = "contract-read-per-session"
           Find = '$pattern = "$($Contract.verbs.definitions.''session-id''.pattern)"'
           Replace = '$pattern = "$((Get-HordeLinkContract).verbs.definitions.''session-id''.pattern)"' }
        # membershipComplete, verbs version 2 (ledger core-projection L-101): every guard of the claim
        # that the list names every session the node has.
        @{ Name = "membership-store-read-whole-unchecked"
           Find = 'if ("$(Get-HordeLinkProp $a ''state'')" -ceq "known" -and $v -is [bool] -and $v) { return "" }'
           Replace = 'return ""' }
        @{ Name = "membership-no-declaration-reason-lost"
           Find = 'if ("$(Get-HordeLinkProp $decl ''state'')" -cne "known") {'
           Replace = 'if ($false) {' }
        @{ Name = "membership-no-declaration-claims"
           Find = 'if ($stores.Count -eq 0) { return @('
           Replace = 'if ($false) { return @(' }
        # An undeclared store only ever takes the claim away (review of PR #243).
        @{ Name = "membership-undeclared-store-ignored"
           Find = 'if ($stores -ccontains $s) { continue }'
           Replace = 'continue' }
        @{ Name = "membership-undeclared-store-without-folder-counts"
           Find = 'if ($has -is [bool] -and -not $has) { continue }'
           Replace = '' }
        @{ Name = "membership-undeclared-pane-folder-trusted"
           Find = 'if ($s -ceq "X1") { [void]$gaps.Add("the store X1 is not declared'
           Replace = 'if ($false) { [void]$gaps.Add("the store X1 is not declared' }
        @{ Name = "membership-store-naming-nothing-counts"
           Find = 'if ($script:HordeNodeDeclarableStores -cnotcontains $s) {'
           Replace = 'if ($false) {' }
        @{ Name = "membership-store-id-case-ignored"
           Find = 'if ($script:HordeNodeDeclarableStores -cnotcontains $s) {'
           Replace = 'if ($script:HordeNodeDeclarableStores -notcontains $s) {' }
        @{ Name = "membership-x1-declarable"
           Find = '$script:HordeNodeDeclarableStores = @("X2", "W8", "W1", "W5")'
           Replace = '$script:HordeNodeDeclarableStores = @("X2", "W8", "W1", "X1", "W5")' }
        @{ Name = "membership-ignores-the-scope"
           Find = 'if ($scope -ne "" -and $scope -ne "all") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "membership-reports-without-rosters"
           Find = 'W5 = @("W3", "W4", "W5")'
           Replace = 'W5 = @("W5")' }
        @{ Name = "membership-ignores-a-cut-list"
           Find = '-Missing (@(Get-HordeNodeMembershipGaps -View $View) + @($cut))'
           Replace = '-Missing @(Get-HordeNodeMembershipGaps -View $View)' }
        @{ Name = "membership-sent-to-a-version-1-hub"
           Find = '-Membership:($State.verbsVersion -ge $script:HordeNodeMembershipVerbs)'
           Replace = '-Membership' }
        @{ Name = "verbs-version-not-negotiated"
           Find = '$State.verbsVersion = [Math]::Max(1, (Select-HordeLinkProtocol'
           Replace = '$State.verbsVersion = 1; $null = [Math]::Max(1, (Select-HordeLinkProtocol' }
        @{ Name = "node-offers-only-verbs-version-1"
           Find = '$script:HordeNodeVerbsVersions = @(1, 2)'
           Replace = '$script:HordeNodeVerbsVersions = @(1)' }
    )
}
