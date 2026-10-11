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
        # --- the seat is trusted only while the session is still there (review finding C5)
        @{ Name = "a-session-that-ended-still-holds"
           Find = 'if ($running.state -cne "known") { return (New-HordeUnknown -Reason ("the " + $Role + "''s session ("'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ("the " + $Role + "''s session ("' }
        @{ Name = "a-process-that-is-not-verified-counts-as-running"
           Find = 'if ("$($record.processCheck)" -cne "verified" -or $started.state -cne "known") {'
           Replace = 'if ($false) {' }
        @{ Name = "a-reading-that-is-not-whole-is-nobody"
           Find = 'if ($Identity.verifiedLive.state -cne "known") { return (New-HordeUnknown -Reason $Identity.verifiedLive.reason) }'
           Replace = '' }
        @{ Name = "a-record-of-an-earlier-run-is-believed"
           Find = 'if ($written -lt $running.value) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-record-of-this-run-is-refused"
           Find = 'if ($written -lt $running.value) {'
           Replace = 'if ($written -gt $running.value) {' }
        @{ Name = "a-record-with-no-time-is-believed"
           Find = 'if ($null -eq $written) { return (New-HordeUnknown'
           Replace = 'if ($null -eq $written) { $written = $running.value }; if ($false) { return (New-HordeUnknown' }
        @{ Name = "two-running-sessions-in-one-pane-and-one-is-chosen"
           Find = 'if ($sharing.Count -gt 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-record-of-an-ended-session-counts-as-in-the-pane"
           Find = 'if ("$id" -ieq $one.id -or (Get-HordeSeatProcessStart -Identity $Identity -SessionId "$id").state -ceq "known") {'
           Replace = 'if ($true) {' }
        @{ Name = "a-retired-record-counts-as-in-the-pane"
           Find = 'if ($left.state -ceq "known" -and [bool]$left.value) { continue }'
           Replace = '' }
        @{ Name = "the-same-pane-number-in-another-terminal-counts"
           Find = ' -or "$((Get-HordeField -Record $other -Name ''instance'').value)".Trim() -cne $seat["instance"]) { continue }'
           Replace = ') { continue }' }
        @{ Name = "any-pane-of-the-terminal-counts"
           Find = 'if ("$((Get-HordeField -Record $other -Name ''pane'').value)".Trim() -cne $seat["pane"] -or '
           Replace = 'if (' }
        @{ Name = "the-machine-is-not-asked-when-no-reading-is-given"
           Find = 'if ($null -eq $Identity) { $Identity = Get-HordeIdentity }'
           Replace = '' }
        @{ Name = "the-stored-word-may-be-asked-for"
           Find = 'if ($Table.native -cnotcontains $Role) { throw'
           Replace = 'if ($false) { throw' }
    )
}
