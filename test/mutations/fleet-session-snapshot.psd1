# Mutations of the port side of the fleet.db sessions step (fleet/SessionSnapshot.ps1). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-session-snapshot.psd1
# test\test-fleet-session-snapshot.ps1 must fail a check for every one. Every find string occurs once.
@{
    Target = "fleet\SessionSnapshot.ps1"
    Suite  = "test\test-fleet-session-snapshot.ps1"
    Mutations = @(
        @{ Name = "registry-always-complete"
           Find = '$complete = ($Registry.complete.state -ceq "known")'
           Replace = '$complete = $true' }
        @{ Name = "whole-record-carried"
           Find = 'foreach ($n in $script:HordeFleetSnapshotRecordFields) {'
           Replace = 'foreach ($n in @($Record.PSObject.Properties | ForEach-Object { $_.Name })) {' }
        @{ Name = "datetime-written-in-the-locale-form"
           Find = 'return $Value.ToUniversalTime().ToString("o")'
           Replace = 'return ("" + $Value)' }
        @{ Name = "unknown-panes-read-as-none"
           Find = 'if ($a.state -cne "known") { return (& $none ("" + $a.reason)) }'
           Replace = 'if ($a.state -cne "known") { return [pscustomobject][ordered]@{ state = "known"; reason = ""; sockets = @() } }' }
        @{ Name = "partly-unreadable-process-list-trusted"
           Find = 'if ($null -ne $re -and "" + $re.Value -ne "") {'
           Replace = 'if ($false) {' }
        @{ Name = "unreadable-control-files-trusted"
           Find = 'if ("" + $snap.error -ne "") { return (& $none ("" + $snap.error)) }'
           Replace = '' }
        @{ Name = "hand-resumed-sessions-left-out"
           Find = 'foreach ($id in @($rs.Value.Keys)) {'
           Replace = 'foreach ($id in @()) {' }
        @{ Name = "running-ids-not-lowered"
           Find = 'sessionId = ("" + $r.sessionId).ToLowerInvariant(); pid'
           Replace = 'sessionId = ("" + $r.sessionId); pid' }
        @{ Name = "non-ascii-written-as-is"
           Find = 'if ([int]$ch -gt 126) {'
           Replace = 'if ($false) {' }
    )
}
