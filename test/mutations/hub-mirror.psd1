# Mutations of remote/Mirror.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\hub-mirror.psd1
# Each breaks one rule of what the hub may say from its mirror of a node (remote plan R13a);
# test\test-hub-mirror.ps1 must fail for every one of them. The suite is pure and takes seconds.
@{
    Target = "remote\Mirror.ps1"
    Suite  = "test\test-hub-mirror.ps1"
    Mutations = @(
        @{ Name = "unreachable-since-moves-with-each-retry"
           Find = 'if ($null -ne (ConvertFrom-HordeMirrorTime $oldSince)) { $since = $oldSince }'
           Replace = '' }
        @{ Name = "lost-node-still-heard"
           Find = 'if ($null -ne $lost) {'
           Replace = 'if ($false) {' }
        @{ Name = "silence-window-ignored"
           Find = 'if ($link.state -ceq "known") { return (New-HordeKnown -Value $true -ObservedAt $heard) }'
           Replace = 'return (New-HordeKnown -Value $true -ObservedAt $heard)' }
        @{ Name = "stale-field-shown-as-current"
           Find = 'if ($Node.state -cne "known") { return (New-HordeUnknown -Reason $Node.reason) }'
           Replace = '' }
        @{ Name = "unreachable-presence-from-the-old-list"
           Find = 'if ($node.state -cne "known") { $presence = New-HordeUnknown -Reason $node.reason }'
           Replace = '' }
        @{ Name = "partial-inventory-carries-nothing"
           Find = 'if (-not (Test-HordeMirrorComplete $List)) {'
           Replace = 'if ($false) {' }
        @{ Name = "complete-inventory-carries-too"
           Find = 'if (-not (Test-HordeMirrorComplete $List)) {'
           Replace = 'if ($true) {' }
        @{ Name = "carried-session-absent"
           Find = '-Presence (New-HordeUnknown -Reason $why)'
           Replace = '-Presence (New-HordeAbsent -Note $why)' }
        @{ Name = "carried-and-listed-twice"
           Find = 'if ($listed.Count -eq 0 -and $twice.Count -eq 0) {'
           Replace = 'if ($twice.Count -eq 0) {' }
        @{ Name = "carried-last-seen-moves"
           Find = '[void]$seen.Add([ordered]@{ lastSeenAt = "$(Get-HordeLinkProp $c ''lastSeenAt'')";'
           Replace = '[void]$seen.Add([ordered]@{ lastSeenAt = $oldAt;' }
        @{ Name = "carried-fields-current"
           Find = 'if ($Carried) { $fields[$n] = New-HordeUnknown -Reason $Presence.reason; continue }'
           Replace = '' }
        @{ Name = "last-known-dropped"
           Find = 'if ($Carried -or $Node.state -cne "known") { $last = $Session }'
           Replace = '' }
        @{ Name = "row-without-device"
           Find = '[pscustomobject][ordered]@{ device = "$(Get-HordeLinkProp $Mirror ''deviceId'')";'
           Replace = '[pscustomobject][ordered]@{ device = "";' }
        @{ Name = "two-devices-no-fault"
           Find = 'if ($devices.Count -lt 2) { continue }'
           Replace = 'if ($true) { continue }' }
        @{ Name = "two-devices-resolved-by-picking-one"
           Find = 'if ($devices.Count -gt 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "unknown-agent-proves-sessions-apart"
           Find = 'return ($x -eq "" -or $y -eq "" -or $x -ceq $y)'
           Replace = 'return ($x -ceq $y)' }
        @{ Name = "agent-not-part-of-the-key"
           Find = 'return ($x -eq "" -or $y -eq "" -or $x -ceq $y)'
           Replace = 'return $true' }
        @{ Name = "absent-while-a-node-is-partial"
           Find = 'if ($silent.Count -eq 0) { return (New-HordeAbsent'
           Replace = 'if ($true) { return (New-HordeAbsent' }
        @{ Name = "node-clock-trusted"
           Find = 'return (New-HordeRemoteObservation -Answer $a -NodeSentAt $NodeSentAt -ReceivedAt $ReceivedAt).answer'
           Replace = 'return $a' }
        @{ Name = "clock-sample-dropped"
           Find = 'if ($null -ne $Clock -and "$(Get-HordeLinkProp $Clock ''state'')" -ceq "known") {'
           Replace = 'if ($false) {' }
        @{ Name = "non-utc-time-read-in-local-zone"
           Find = 'if (-not (Test-HordeClockUtc $Time)) { throw ($What + " must be a UTC [datetime]") }'
           Replace = '' }
    )
}
