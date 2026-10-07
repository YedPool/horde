# Mutations of core/SessionSeat.ps1, where the session that holds a role sits. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\session-seat.psd1
# test\test-session-seat.ps1 must fail for each.
@{
    Target = "core\SessionSeat.ps1"
    Suite  = "test\test-session-seat.ps1"
    Mutations = @(
        @{ Name = "an-unreadable-record-ignored"
           Find = 'if ($registry.complete.state -cne "known") {'
           Replace = 'if ($false) {' }
        @{ Name = "a-retired-holder-still-holds"
           Find = 'if ($retired.state -ceq "known" -and [bool]$retired.value) { continue }'
           Replace = '' }
        @{ Name = "any-role-is-the-role"
           Find = ' -and "$($named.value)" -ceq $Role) {'
           Replace = ') {' }
        @{ Name = "a-session-with-no-role-is-a-holder"
           Find = 'if ($named.state -ceq "known" -and '
           Replace = 'if ($named.state -cne "known" -or ' }
        @{ Name = "nobody-is-unknown-not-absent"
           Find = 'if ($holders.Count -eq 0) { return (New-HordeAbsent -Note'
           Replace = 'if ($holders.Count -eq 0) { return (New-HordeUnknown -Reason' }
        @{ Name = "the-first-of-two-is-chosen"
           Find = 'if ($holders.Count -gt 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-record-with-no-pane-gives-a-seat"
           Find = 'if ($text -eq "") { return (New-HordeUnknown -Reason'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason' }
        @{ Name = "a-blank-pane-is-a-pane"
           Find = '$text = ("" + $field.value).Trim() }'
           Replace = '$text = ("" + $field.value) }' }
        @{ Name = "a-list-of-panes-is-a-pane"
           Find = ' -and ($field.value -is [string] -or $field.value -is [int] -or $field.value -is [long])) {'
           Replace = ') {' }
        @{ Name = "only-the-pane-is-required"
           Find = 'foreach ($name in @("pane", "instance")) {'
           Replace = 'foreach ($name in @("pane")) {' }
        @{ Name = "the-stored-word-may-be-asked-for"
           Find = 'if ($Table.native -cnotcontains $Role) { throw'
           Replace = 'if ($false) { throw' }
    )
}
