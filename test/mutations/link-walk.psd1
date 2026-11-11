# Mutations of the link walk's schema check. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\link-walk.psd1
# remote/Contract.ps1's Invoke-HordeLinkWalk does inline what Test-HordeSchema and Get-HordeLinkNodes did
# (fix/link-writer-speed). Each mutation breaks one of those rules as the walk applies it to a frame's
# arguments and result, and test\test-link-contracts.ps1 must fail for every one. The caps the same walk
# checks are test\mutations\link-walk-caps.psd1. Every find string occurs exactly once.
# SECTIONS (tools\Mutate.ps1; issue #83): each mutant runs only the section of test\test-link-contracts.ps1
# that failed first for it in a whole-suite run of this spec on the always-on box (bd6cdb5, 2026-10-07).
@{
    Target = "remote\Contract.ps1"
    Suite  = "test\test-link-contracts.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "wrong-type-accepted"
           Find = 'if (-not $ok) { [void]$schemaOut.Add($p + " should be " + $r.type); $live = $false }'
           Replace = ''
           Sections = @("frame") }
        @{ Name = "string-taken-for-integer"
           Find = 'elseif ($tt -ceq "integer" -and ($v -is [int] -or $v -is [long])) { $ok = $true }'
           Replace = 'elseif ($tt -ceq "integer") { $ok = $true }'
           Sections = @("frame") }
        @{ Name = "anything-taken-for-object"
           Find = 'elseif ($tt -ceq "object") { $ok = $isObject }'
           Replace = 'elseif ($tt -ceq "object") { $ok = $true }'
           Sections = @("answers") }
        @{ Name = "enum-unchecked"
           Find = 'if ($r.hasEnum) {'
           Replace = 'if ($false) {'
           Sections = @("frame") }
        @{ Name = "pattern-unchecked"
           Find = 'if (-not $r.regex.IsMatch($v)) {'
           Replace = 'if ($false) {'
           Sections = @("frame") }
        @{ Name = "minimum-unchecked"
           Find = 'if ($r.hasMin -and (Test-HordeSchemaIsNumber $v)) {'
           Replace = 'if ($false) {'
           Sections = @("frame") }
        @{ Name = "required-unchecked"
           Find = 'if (-not $has) { [void]$schemaOut.Add($p + " has no ''" + $req + "''") }'
           Replace = ''
           Sections = @("frame") }
        @{ Name = "required-matched-without-case"
           Find = '$has = ($null -ne $pr -and $pr.Name -ceq $req)'
           Replace = '$has = ($null -ne $pr)'
           Sections = @("frame") }
        @{ Name = "extra-member-allowed"
           Find = 'if ($schemaHere -and $null -eq $exact -and $r.addFalse) {'
           Replace = 'if ($false) {'
           Sections = @("frame") }
        @{ Name = "member-matched-without-case"
           Find = '$rec.props = New-Object ''System.Collections.Generic.Dictionary[string,object]'' ([System.StringComparer]::Ordinal)'
           Replace = '$rec.props = New-Object ''System.Collections.Generic.Dictionary[string,object]'' ([System.StringComparer]::OrdinalIgnoreCase)'
           Sections = @("frame") }
        @{ Name = "members-not-checked"
           Find = '$childLive = ($schemaHere -and $null -ne $exact)'
           Replace = '$childLive = $false'
           Sections = @("frame") }
        @{ Name = "items-not-walked"
           Find = 'foreach ($item in $v) { $order.Push(@(0, $item, $r.items.rec, ($p + "[" + $i + "]"), $live)); $i++ }'
           Replace = 'foreach ($item in $v) { $i++ }'
           Sections = @("answers") }
        @{ Name = "children-visited-last-first"
           Find = 'while ($order.Count -gt 0) { $stack.Push($order.Pop()) }'
           Replace = 'if ($order.Count -gt 0) { foreach ($o in @($order.ToArray()[($order.Count - 1)..0])) { $stack.Push($o) } }; while ($order.Count -gt 0) { $null = $order.Pop() }'
           Sections = @("frame") }
        @{ Name = "answer-rules-skipped"
           Find = 'foreach ($f in @(Test-HordeLinkAnswer -Answer $a[0] -Path $a[1])) { [void]$out.Add($f) }'
           Replace = ''
           Sections = @("answers") }
        @{ Name = "answer-rules-despite-schema-findings"
           Find = 'if ($w.schema.Count -gt 0) { return @($w.schema) }'
           Replace = ''
           Sections = @("frame") }
        @{ Name = "ref-chain-not-followed"
           Find = '        $Raw = Resolve-HordeLinkRef -Ref $ref -Root $Root'
           Replace = '        break'
           Sections = @("frame") }
    )
}
