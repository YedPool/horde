# Mutations of the restore-plan gate. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\restore-plan.psd1
# Each breaks one rule core\RestorePlan.ps1 adds to the schema; test\test-schema-restore-plan.ps1
# must fail for every one of them.
@{
    Target = "core\RestorePlan.ps1"
    Suite  = "test\test-schema-restore-plan.ps1"
    Mutations = @(
        @{ Name = "schema-not-run"
           Find = '$bySchema = @(Test-HordeSchema -Value $Plan -Schema $Schema)'
           Replace = '$bySchema = @()' }
        @{ Name = "schema-findings-dropped"
           Find = 'if ($bySchema.Count -gt 0) { return $bySchema }'
           Replace = 'if ($false) { return $bySchema }' }
        @{ Name = "dictionary-keys-not-read"
           Find = 'foreach ($k in $Object.Keys) { if ("$k" -ceq $Name) { return $true } }'
           Replace = '' }
        @{ Name = "dictionary-keys-ignore-case"
           Find = 'foreach ($k in $Object.Keys) { if ("$k" -ceq $Name) { return $Object[$k] } }'
           Replace = 'foreach ($k in $Object.Keys) { if ("$k" -eq $Name) { return $Object[$k] } }' }
        @{ Name = "dictionary-values-not-read"
           Find = 'foreach ($k in $Object.Keys) { if ("$k" -ceq $Name) { return $Object[$k] } }'
           Replace = '' }
        @{ Name = "split-not-a-container-key"
           Find = '$isContainer = ($hasSplit -or $hasRatio -or $hasChildren)'
           Replace = '$isContainer = ($hasRatio -or $hasChildren)' }
        @{ Name = "ratio-not-a-container-key"
           Find = '$isContainer = ($hasSplit -or $hasRatio -or $hasChildren)'
           Replace = '$isContainer = ($hasSplit -or $hasChildren)' }
        @{ Name = "children-not-a-container-key"
           Find = '$isContainer = ($hasSplit -or $hasRatio -or $hasChildren)'
           Replace = '$isContainer = ($hasSplit -or $hasRatio)' }
        @{ Name = "both-leaf-and-container-allowed"
           Find = 'if ($hasSlot -and $isContainer) {'
           Replace = 'if ($false) {' }
        @{ Name = "both-also-walked-as-leaf"
           Find = '-Slot $slot -Path $Path; return'
           Replace = '-Slot $slot -Path $Path' }
        @{ Name = "both-not-placed"
           Find = 'Add-HordePlanPlacement -Placements $Placements -Slot $slot -Path $Path; return'
           Replace = 'return' }
        @{ Name = "neither-allowed"
           Find = 'if (-not $hasSlot -and -not $isContainer) {'
           Replace = 'if ($false) {' }
        @{ Name = "split-optional"
           Find = 'if (-not $hasSplit) { [void]$Findings.Add('
           Replace = 'if ($false) { [void]$Findings.Add(' }
        @{ Name = "ratio-not-checked"
           Find = 'if ($hasRatio) {'
           Replace = 'if ($false) {' }
        @{ Name = "ratio-zero-allowed"
           Find = 'if (-not ($r -gt 0 -and $r -lt 1)) {'
           Replace = 'if (-not ($r -ge 0 -and $r -lt 1)) {' }
        @{ Name = "ratio-one-allowed"
           Find = 'if (-not ($r -gt 0 -and $r -lt 1)) {'
           Replace = 'if (-not ($r -gt 0 -and $r -le 1)) {' }
        @{ Name = "no-children-allowed"
           Find = 'if (-not $hasChildren) { [void]$Findings.Add($Path + " is a container with no children"); return }'
           Replace = 'if (-not $hasChildren) { return }' }
        @{ Name = "one-child-allowed"
           Find = 'if ($kids.Count -lt 2) {'
           Replace = 'if ($kids.Count -lt 1) {' }
        @{ Name = "children-not-walked"
           Find = 'Test-HordePlanNode -Node $kids[$i] -Path ($Path + ".children[" + $i + "]") -Placements $Placements -Findings $Findings'
           Replace = '' }
        @{ Name = "duplicate-slot-allowed"
           Find = 'if ($slotAt.ContainsKey($slot)) {'
           Replace = 'if ($false) {' }
        @{ Name = "duplicate-id-allowed"
           Find = 'if ($idAt.ContainsKey($id)) {'
           Replace = 'if ($false) {' }
        @{ Name = "session-ids-exact-case"
           Find = '$idAt = New-Object ''System.Collections.Generic.Dictionary[string,int]'' ([System.StringComparer]::OrdinalIgnoreCase)'
           Replace = '$idAt = New-Object ''System.Collections.Generic.Dictionary[string,int]'' ([System.StringComparer]::Ordinal)' }
        @{ Name = "resume-pairs-exact-case"
           Find = '$resumeAt = New-Object ''System.Collections.Generic.Dictionary[string,int]'' ([System.StringComparer]::OrdinalIgnoreCase)'
           Replace = '$resumeAt = New-Object ''System.Collections.Generic.Dictionary[string,int]'' ([System.StringComparer]::Ordinal)' }
        @{ Name = "resume-not-checked"
           Find = 'Test-HordePlanResume -Session $sessions[$i] -Index $i -ResumeAt $resumeAt -Findings $findings'
           Replace = '' }
        @{ Name = "duplicate-resume-allowed"
           Find = 'if ($ResumeAt.ContainsKey($key)) {'
           Replace = 'if ($false) {' }
        @{ Name = "empty-argv-allowed"
           Find = 'if ($argv.Count -eq 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "claude-rules-skipped"
           Find = 'if ($kind -cne "claude-resume") { return }'
           Replace = 'return' }
        @{ Name = "claude-resume-id-not-sessionId-allowed"
           Find = 'if ($rid -ine $sid) {'
           Replace = 'if ($false) {' }
        @{ Name = "claude-resume-id-exact-case"
           Find = 'if ($rid -ine $sid) {'
           Replace = 'if ($rid -cne $sid) {' }
        @{ Name = "claude-argv-without-resume-allowed"
           Find = 'if ($flags.Count -eq 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "claude-argv-resume-target-unchecked"
           Find = 'if ($null -eq $next -or $next -ine $rid) {'
           Replace = 'if ($null -eq $next) {' }
        @{ Name = "parent-self-exact-case"
           Find = 'if ("$parent" -ieq "$(Get-HordePlanProp $sessions[$i] "sessionId")") {'
           Replace = 'if ("$parent" -ceq "$(Get-HordePlanProp $sessions[$i] "sessionId")") {' }
        @{ Name = "parent-self-allowed"
           Find = 'if ("$parent" -ieq "$(Get-HordePlanProp $sessions[$i] "sessionId")") {'
           Replace = 'if ($false) {' }
        @{ Name = "parent-unknown-allowed"
           Find = 'elseif (-not $idAt.ContainsKey("$parent")) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "parent-never-read"
           Find = '$parent = Get-HordePlanProp $sessions[$i] "parent"'
           Replace = '$parent = $null' }
        @{ Name = "session-slots-ignore-case"
           Find = '$slotAt = New-Object ''System.Collections.Generic.Dictionary[string,int]'' ([System.StringComparer]::Ordinal)'
           Replace = '$slotAt = New-Object ''System.Collections.Generic.Dictionary[string,int]'' ([System.StringComparer]::OrdinalIgnoreCase)'
           Expect = "survives"
           Reason = "Since the review of PR #17 the schema's slot pattern, ^[a-z][a-z0-9-]*$, admits lower case only, so the gate never sees two slots that differ only in case (slot-case-differs is now refused by the schema). The ordinal comparison stays, carried by its comment, for a plan checked against another schema." }
        @{ Name = "placements-ignore-case"
           Find = 'System.Collections.ArrayList]'' ([System.StringComparer]::Ordinal)'
           Replace = 'System.Collections.ArrayList]'' ([System.StringComparer]::OrdinalIgnoreCase)'
           Expect = "survives"
           Reason = "Since the review of PR #17 the schema's slot pattern, ^[a-z][a-z0-9-]*$, admits lower case only, so the gate never sees two slots that differ only in case (slot-case-differs is now refused by the schema). The ordinal comparison stays, carried by its comment, for a plan checked against another schema." }
        @{ Name = "unknown-slot-allowed"
           Find = 'if (-not $slotAt.ContainsKey($slot)) {'
           Replace = 'if ($false) {' }
        @{ Name = "slot-placed-twice-allowed"
           Find = '} elseif ($placements[$slot].Count -gt 1) {'
           Replace = '} elseif ($false) {' }
        @{ Name = "dropped-session-allowed"
           Find = 'if (-not $placements.ContainsKey($slot)) { [void]$findings.Add('
           Replace = 'if ($false) { [void]$findings.Add(' }
        @{ Name = "tabs-after-the-first-skipped"
           Find = 'for ($t = 0; $t -lt $tabs.Count; $t++) {'
           Replace = 'for ($t = 0; $t -lt 1; $t++) {' }
    )
}
