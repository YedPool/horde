# Mutations of the link contract checker. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\link-contract.psd1
# Each mutation switches off, loosens or misreads one rule of remote/Contract.ps1, and
# test\test-link-contracts.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "remote\Contract.ps1"
    Suite  = "test\test-link-contracts.ps1"
    Mutations = @(
        @{ Name = "absent-verbs-allowed"
           Find = 'if ($absent.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "argument-names-unchecked"
           Find = 'if ($Role -ceq "args") { $refused = @('
           Replace = 'if ($false) { $refused = @(' }
        @{ Name = "result-names-unchecked"
           Find = 'elseif ($Role -ceq "result") { $refused = @('
           Replace = 'elseif ($false) { $refused = @(' }
        @{ Name = "open-object-allowed"
           Find = 'if ((Get-HordeLinkProp $Node "additionalProperties") -isnot [bool] -or'
           Replace = 'if ($false -and' }
        @{ Name = "untyped-node-allowed"
           Find = 'if ($null -eq $type) { return @("$Where has no type, so it accepts anything") }'
           Replace = 'if ($null -eq $type) { return @() }' }
        @{ Name = "object-without-properties-allowed"
           Find = 'if ($null -eq $props) { [void]$out.Add('
           Replace = 'if ($false) { [void]$out.Add(' }
        @{ Name = "array-cap-unchecked"
           Find = 'if ("$cap" -cne "listItems") {'
           Replace = 'if ($false) {' }
        @{ Name = "array-items-unchecked"
           Find = 'if ($null -eq $items) { [void]$out.Add('
           Replace = 'if ($false) { [void]$out.Add(' }
        @{ Name = "string-cap-unchecked"
           Find = 'if ($null -eq $cap) { [void]$out.Add("$Where is a string that names no cap") }'
           Replace = 'if ($false) { }' }
        @{ Name = "cap-existence-unchecked"
           Find = 'elseif (-not $Limits.ContainsKey("$cap"))'
           Replace = 'elseif ($false)' }
        @{ Name = "result-cap-class-unchecked"
           Find = 'elseif ($Role -ceq "result" -and $script:HordeLinkResultCaps -cnotcontains "$cap")'
           Replace = 'elseif ($false)' }
        @{ Name = "result-may-hold-text"
           Find = '$script:HordeLinkResultCaps = @("nameBytes", "reasonBytes", "summaryBytes")'
           Replace = '$script:HordeLinkResultCaps = @("nameBytes", "reasonBytes", "summaryBytes", "textBytes")' }
        @{ Name = "row-rules-from-the-table-itself"
           Find = '-Doc (Get-HordeSchema -Name "link-verbs.v1") -Ref "#/definitions/verb-row"'
           Replace = '-Doc $Verbs -Ref "#/definitions/verb-row"' }
        @{ Name = "duplicate-verb-allowed"
           Find = 'if ($seen.ContainsKey($name)) {'
           Replace = 'if ($false) {' }
        @{ Name = "since-unchecked"
           Find = '-and $since -gt $protocol)'
           Replace = '-and $false)' }
        @{ Name = "node-may-ask-hub-to-spawn"
           Find = '-and ($effect -ceq "spawn" -or $effect -ceq "drive" -or $effect -ceq "kill")'
           Replace = '-and $false' }
        @{ Name = "node-may-ask-hub-to-drive"
           Find = '$effect -ceq "spawn" -or $effect -ceq "drive" -or'
           Replace = '$effect -ceq "spawn" -or' }
        @{ Name = "effect-class-not-pinned"
           Find = 'if ($effect -cne $pinned) {'
           Replace = 'if ($false) {' }
        @{ Name = "args-need-not-be-object"
           Find = 'if ($part -ceq "args" -and "$(Get-HordeLinkProp $t.node ''type'')" -cne "object")'
           Replace = 'if ($false)' }
        @{ Name = "camel-case-not-split"
           Find = '''([a-z0-9])([A-Z])'', ''$1 $2'''
           Replace = '''([a-z0-9])([A-Z])'', ''$1$2''' }
        @{ Name = "kind-required-unchecked"
           Find = 'if ($null -ne $m -and $members -cnotcontains $m)'
           Replace = 'if ($false)' }
        @{ Name = "kind-allowed-unchecked"
           Find = 'foreach ($m in $members) { if (@(Get-HordeLinkProp $rule "allowed") -cnotcontains $m)'
           Replace = 'foreach ($m in $members) { if ($false)' }
        @{ Name = "one-of-allows-neither"
           Find = '@($one | Where-Object { $members -ccontains $_ }).Count -ne 1'
           Replace = '@($one | Where-Object { $members -ccontains $_ }).Count -gt 1' }
        @{ Name = "unsupported-verb-passes"
           Find = 'return @("unsupported-verb: ''" + $Frame.verb + "'' is not a verb of link-verbs v1")'
           Replace = 'return @()' }
        @{ Name = "evt-frames-accepted"
           Find = 'if ($kind -ceq "evt") { return @('
           Replace = 'if ($false) { return @(' }
        @{ Name = "req-args-unchecked"
           Find = 'if ($kind -ceq "req") {'
           Replace = 'if ($kind -ceq "req" -and $false) {' }
        @{ Name = "known-value-not-typed-by-verb"
           Find = 'if ("$($answer.state)" -ceq "known") {'
           Replace = 'if ($false) {' }
        @{ Name = "known-without-value"
           Find = 'if (-not $hasValue) { $out += @("$Path is known and carries no value") }'
           Replace = '' }
        @{ Name = "known-without-time"
           Find = 'if (-not $hasTime) { $out += @("$Path is known and says'
           Replace = 'if ($false) { $out += @("$Path is known and says' }
        @{ Name = "absent-with-value"
           Find = 'if ($hasValue) { $out += @("$Path is absent and carries a value") }'
           Replace = '' }
        @{ Name = "unknown-without-reason"
           Find = 'if ("$reason".Trim() -eq "") {'
           Replace = 'if ($false) {' }
        @{ Name = "null-value-allowed"
           Find = 'if ($hasValue -and $null -eq $value)'
           Replace = 'if ($false)' }
        @{ Name = "nested-answers-skipped"
           Find = 'if ($r.isAnswer -and $isObject) {'
           Replace = 'if ($false) {' }
        @{ Name = "frame-cap-above-ceiling-allowed"
           Find = 'if ($limits["frameBytes"] -gt $limits["frameBytesCeiling"])'
           Replace = 'if ($false)' }
        @{ Name = "ceiling-above-4-mib-allowed"
           Find = 'if ($limits["frameBytesCeiling"] -gt 4194304)'
           Replace = 'if ($limits["frameBytesCeiling"] -gt 8388608)' }
        @{ Name = "resend-may-move-issued-at"
           Find = 'foreach ($m in @("requestId", "issuedAt", "verb")) {'
           Replace = 'foreach ($m in @("requestId", "verb")) {' }
        @{ Name = "resend-args-unchecked"
           Find = 'if (-not [string]::Equals($a1, $a2, [System.StringComparison]::Ordinal)) {'
           Replace = 'if ($false) {' }
        @{ Name = "resend-args-compared-by-culture"
           Find = 'if (-not [string]::Equals($a1, $a2, [System.StringComparison]::Ordinal)) {'
           Replace = 'if ($a1 -cne $a2) {' }
        @{ Name = "resend-may-reuse-frame-id"
           Find = 'if ("$($Again.id)" -ceq "$($First.id)") {'
           Replace = 'if ($false) {' }
        @{ Name = "verb-allowlist-off"
           Find = 'else { [void]$out.Add("$at is not a verb of remote/Contract.ps1''s allowlist'
           Replace = 'elseif ($false) { [void]$out.Add("$at is not a verb of remote/Contract.ps1''s allowlist' }
        @{ Name = "argument-allowlist-off"
           Find = 'if (@($allow) -cnotcontains $path) {'
           Replace = 'if ($false) {' }
        @{ Name = "argument-paths-not-nested"
           Find = '$path = $Prefix + "." + $p.Name'
           Replace = '$path = $p.Name' }
        @{ Name = "argument-paths-skip-array-items"
           Find = 'if ($null -ne $items) { foreach ($x in @(Get-HordeLinkArgPaths'
           Replace = 'if ($false) { foreach ($x in @(Get-HordeLinkArgPaths' }
        @{ Name = "issued-at-not-parsed"
           Find = 'if ($members -ccontains "issuedAt") {'
           Replace = 'if ($false) {' }
        @{ Name = "resend-of-any-kind"
           Find = 'if ("$(Get-HordeLinkProp $pair[1] ''kind'')" -cne "req") {'
           Replace = 'if ($false) {' }
        # Messaging over the link (plan step R21, 2026-10-05): each new argument list is the allowlist.
        @{ Name = "mail-receipt-may-name-a-session"
           Find = '"mail.receipt"    = @{ effect = "write"; args = @("messageId", "stage", "at", "reason") }'
           Replace = '"mail.receipt"    = @{ effect = "write"; args = @("messageId", "stage", "at", "reason", "sessionId") }' }
        @{ Name = "mail-next-may-take-a-label"
           Find = '"mail.next"       = @{ effect = "read";  args = @() }'
           Replace = '"mail.next"       = @{ effect = "read";  args = @("label") }' }
        @{ Name = "deliver-may-take-a-pane"
           Find = '"session.deliver" = @{ effect = "drive"; args = @("messageId", "sessionId", "label",'
           Replace = '"session.deliver" = @{ effect = "drive"; args = @("messageId", "sessionId", "label", "pane",' }
        # Review of PR #97: direction pinned (F4), stage lists in step (F8), the ttl ceiling (F7).
        @{ Name = "direction-unpinned"
           Find = 'elseif ($direction -cne $script:HordeLinkVerbDirection[$name]) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "mail-next-pinned-node-to-hub"
           Find = '"mail.next" = "hub-to-node"; "mail.receipt" = "hub-to-node"'
           Replace = '"mail.next" = "node-to-hub"; "mail.receipt" = "hub-to-node"' }
        @{ Name = "mail-receipt-pinned-node-to-hub"
           Find = '"mail.next" = "hub-to-node"; "mail.receipt" = "hub-to-node"'
           Replace = '"mail.next" = "hub-to-node"; "mail.receipt" = "node-to-hub"' }
        @{ Name = "stage-lists-unchecked"
           Find = 'foreach ($f in @(Test-HordeLinkStageLists -Verbs $Verbs)) { [void]$out.Add($f) }'
           Replace = '' }
        @{ Name = "ttl-ceiling-doubled"
           Find = '-gt $script:HordeMailTtlMaxSeconds) {'
           Replace = '-gt ($script:HordeMailTtlMaxSeconds * 2)) {' }
        @{ Name = "ttl-of-a-request-unchecked"
           Find = 'if ("req" -ceq $kind) { return @(Test-HordeLinkTtlCeiling -Value (Get-HordeLinkProp $Frame "args") -Path ''$.args'') }'
           Replace = 'if ("req" -ceq $kind) { return @() }' }
        @{ Name = "ttl-of-a-result-unchecked"
           Find = 'return @(Test-HordeLinkTtlCeiling -Value (Get-HordeLinkProp (Get-HordeLinkProp $answer "value") "mail")'
           Replace = 'return @(); $null = @(Test-HordeLinkTtlCeiling -Value (Get-HordeLinkProp (Get-HordeLinkProp $answer "value") "mail")' }
    )
}
