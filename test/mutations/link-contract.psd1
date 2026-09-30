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
           Find = '-and ($effect -ceq "spawn" -or $effect -ceq "kill")'
           Replace = '-and $false' }
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
           Find = 'if (-not $hasValue) { [void]$out.Add("$Path is known and carries no value") }'
           Replace = '' }
        @{ Name = "known-without-time"
           Find = 'if (-not $hasTime) { [void]$out.Add("$Path is known and says'
           Replace = 'if ($false) { [void]$out.Add("$Path is known and says' }
        @{ Name = "absent-with-value"
           Find = 'if ($hasValue) { [void]$out.Add("$Path is absent and carries a value") }'
           Replace = '' }
        @{ Name = "unknown-without-reason"
           Find = 'if ("$(Get-HordeLinkProp $Answer ''reason'')".Trim() -eq "") {'
           Replace = 'if ($false) {' }
        @{ Name = "null-value-allowed"
           Find = 'if ($hasValue -and $null -eq (Get-HordeLinkProp $Answer "value"))'
           Replace = 'if ($false)' }
        @{ Name = "nested-answers-skipped"
           Find = 'if ((Test-HordeLinkIsAnswerNode $x.node) -and'
           Replace = 'if ($false -and' }
        @{ Name = "frame-cap-above-ceiling-allowed"
           Find = 'if ($limits["frameBytes"] -gt $limits["frameBytesCeiling"])'
           Replace = 'if ($false)' }
        @{ Name = "ceiling-above-4-mib-allowed"
           Find = 'if ($limits["frameBytesCeiling"] -gt 4194304)'
           Replace = 'if ($limits["frameBytesCeiling"] -gt 8388608)' }
    )
}
