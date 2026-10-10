# Mutations of conversations/Port.ps1, the conversation-source port. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\conversation-port.psd1
# Each lets a secret through, believes a lying adapter, or picks a Thrall it should not;
# test\test-conversation-port.ps1 must fail for every one.
@{
    Target = "conversations\Port.ps1"
    Suite  = "test\test-conversation-port.ps1"
    Mutations = @(
        @{ Name = "turn-text-not-redacted"
           Find = '$protected = Protect-HordeSecretText -Text $text.value'
           Replace = '$protected = [pscustomobject]@{ text = $text.value; count = 0 }' }
        @{ Name = "redactions-not-counted"
           Find = 'if ($protected.count -gt 0) { $t["redactions"] = [int]$protected.count }'
           Replace = '$null = $protected' }
        @{ Name = "long-text-not-cut"
           Find = 'if ($words.Length -gt $script:HordeConversationTextChars) { $words = $words.Substring(0, $script:HordeConversationTextChars); $cut = $true }'
           Replace = '$null = $cut' }
        @{ Name = "adapter-anomaly-not-redacted"
           Find = 'foreach ($x in @($anM.value)) { [void]$anomalies.Add("adapter ''" + $name + "'': " + (Protect-HordeConversationNote $x)) }'
           Replace = 'foreach ($x in @($anM.value)) { [void]$anomalies.Add("adapter ''" + $name + "'': " + $x) }' }
        @{ Name = "adapter-exception-not-redacted"
           Find = 'failed the " + $What + ": " + (Protect-HordeConversationNote $_.Exception.Message)))'
           Replace = 'failed the " + $What + ": " + $_.Exception.Message))' }
        @{ Name = "any-role-kept"
           Find = ' -or $script:HordeConversationRoles -cnotcontains $role.value)'
           Replace = ')' }
        @{ Name = "empty-text-kept"
           Find = ' -or $text.value -notmatch ''\S'') { return'
           Replace = ') { return' }
        @{ Name = "bad-turn-id-kept"
           Find = ' -or $id.value -cnotmatch $script:HordeConversationIdPattern) { return'
           Replace = ') { return' }
        @{ Name = "repeated-turn-id-kept"
           Find = 'if ($ids.ContainsKey($c.turn.turnId)) {'
           Replace = 'if ($false) {' }
        @{ Name = "bad-group-id-kept"
           Find = 'if ($g.value -is [string] -and $g.value -cmatch $script:HordeConversationIdPattern) { $t["groupId"] = $g.value }'
           Replace = 'if ($true) { $t["groupId"] = "" + $g.value }' }
        @{ Name = "missing-time-not-noted"
           Find = 'elseif ($ClaimsTime) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "source-not-the-ports"
           Find = '$t["source"] = [pscustomobject]@{ vendor = $Source.vendor; session = $Source.session; fleet = $Source.fleet }'
           Replace = '$t["source"] = [pscustomobject]@{ vendor = $Source.vendor; session = $Source.session; fleet = $Source.vendor }' }
        @{ Name = "overfilled-batch-used"
           Find = 'if ($raw.Count -gt $MaxTurns) {'
           Replace = 'if ($false) {' }
        @{ Name = "position-not-checked"
           Find = 'if (-not $posM.has -or $posM.value -isnot [string] -or $posM.value.Length -gt $script:HordeConversationPositionChars -or $posM.value -cnotmatch $script:HordeConversationPositionPattern) {'
           Replace = 'if ($false) {' }
        @{ Name = "more-not-checked"
           Find = 'if (-not $moreM.has -or $moreM.value -isnot [bool]) {'
           Replace = 'if ($false) {' }
        @{ Name = "reset-not-checked"
           Find = 'if (-not $resetM.has -or $resetM.value -isnot [string] -or @("", "rotated") -cnotcontains $resetM.value) {'
           Replace = 'if ($false) {' }
        @{ Name = "rotation-from-the-start-believed"
           Find = 'if ($position -eq "") { return (New-HordeUnknown -Reason ("adapter ''" + $name + "'' reported a rotation on a read from the start")) }'
           Replace = '$null = $position' }
        @{ Name = "two-thralls-one-chosen"
           Find = 'if ($found.Count -gt 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "bad-session-id-believed"
           Find = ' -or $located.value -cnotmatch $script:HordeConversationSessionPattern) { [void]$unsure.Add'
           Replace = ') { [void]$unsure.Add' }
        @{ Name = "look-alike-source-read"
           Find = 'if (-not [object]::ReferenceEquals($script:HordeConversationSources[$id.Value], $Source)) { return $false }'
           Replace = '$null = $id' }
        @{ Name = "cursor-of-another-vendor-read"
           Find = ' -or $vendor.value -cne $Source.vendor) {'
           Replace = ') {' }
        @{ Name = "new-session-not-a-reset"
           Find = 'if ((Get-HordeConversationMember $Cursor "session").value -ceq $Source.session) {'
           Replace = 'if ($true) {' }
        @{ Name = "unverified-hazard-passes"
           Find = 'if ($sup -cne "no") { return ("adapter'
           Replace = 'if ($sup -ceq "yes") { return ("adapter' }
        @{ Name = "unverified-capability-satisfies"
           Find = 'if ($sup -cne "yes") { return ("adapter'
           Replace = 'if ($sup -ceq "no") { return ("adapter' }
        @{ Name = "batch-over-the-ceiling"
           Find = ' -or $MaxTurns -gt $script:HordeConversationMaxTurns) {'
           Replace = ') {' }
        @{ Name = "second-registration-swaps"
           Find = 'if ($script:HordeConversationAdapters.ContainsKey("$($caps.vendor)")) {'
           Replace = 'if ($false) {' }
        @{ Name = "delivered-not-a-role"
           Find = '$script:HordeConversationRoles = @("user", "assistant", "system", "delivered")'
           Replace = '$script:HordeConversationRoles = @("user", "assistant", "system")' }
        @{ Name = "asked-session-not-checked"
           Find = 'if ($Session -ne "" -and $located.value -cne $Session) {'
           Replace = 'if ($false) {' }
        @{ Name = "asked-session-not-passed"
           Find = '$request = [pscustomobject]@{ fleet = $Fleet; role = "warchief"; session = $Session; options = $Options }'
           Replace = '$request = [pscustomobject]@{ fleet = $Fleet; role = "warchief"; session = ""; options = $Options }' }
        @{ Name = "folder-name-not-checked"
           Find = 'if ($findings.Count -eq 0 -and "$($caps.vendor)" -cne $leaf) {'
           Replace = 'if ($false) {' }
    )
}
