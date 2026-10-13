# Mutations of the session lookup in agents/claude-code/Conversation.ps1 (Get-ClaudeCodeSessionRecord). Run:
#   powershell -File tools\Mutate.ps1 -Spec agents\claude-code\test\mutations\conversation-session.psd1
# Each answers for a record it did not read, or hides that it could not read one;
# agents\claude-code\test\test-conversation.ps1 must fail for every one. (The adapter's turns and its
# Thrall are conversation.psd1's.)
@{
    Target = "agents\claude-code\Conversation.ps1"
    Suite  = "agents\claude-code\test\test-conversation.ps1"
    Mutations = @(
        @{ Name = "unreadable-own-record-not-said"
           Find = 'if ($registry.unreadable.Contains($Session)) {'
           Replace = 'if ($false) {' }
        @{ Name = "missing-record-in-a-damaged-registry-absent"
           Find = 'if (-not $whole) {'
           Replace = 'if ($false) {' }
        @{ Name = "missing-record-always-unknowable"
           Find = '$whole = ($registry.complete.state -ceq "known")'
           Replace = '$whole = $false' }
        @{ Name = "id-case-ignored"
           Find = 'if ($null -eq $entry -or "$($entry.id)" -cne $Session) {'
           Replace = 'if ($null -eq $entry) {' }
        @{ Name = "field-not-text-passed"
           Find = 'if ($held.state -ceq "known" -and $held.value -isnot [string]) {'
           Replace = 'if ($false) {' }
        @{ Name = "label-read-from-another-field"
           Find = 'label = (Get-ClaudeCodeRecordText -Record $entry.record -Name "label")'
           Replace = 'label = (Get-ClaudeCodeRecordText -Record $entry.record -Name "owner")' }
        @{ Name = "parent-read-from-another-field"
           Find = 'parent = (Get-ClaudeCodeRecordText -Record $entry.record -Name "parent") }))'
           Replace = 'parent = (Get-ClaudeCodeRecordText -Record $entry.record -Name "owner") }))' }
        @{ Name = "role-not-translated"
           Find = 'role = (Read-HordeRecordRole -Record $entry.record -Table (Get-HordeRoleTable)).role'
           Replace = 'role = (Get-ClaudeCodeRecordText -Record $entry.record -Name "role")' }
    )
}
