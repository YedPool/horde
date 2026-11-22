# Mutations of core/WakeFiles.ps1, held by the CROSS-MODULE check in test\test-services.ps1 (T-0502): the wake watcher's
# own heartbeat, written by Write-HordeWakeHeartbeat, read by Read-HordeHeartbeat and judged by Get-HordeServiceLiveness.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-heartbeat-services.psd1
# test\mutations\wake-files.psd1 holds the same lines from the writer's own suite; these hold them from the supervisor's side,
# the side that read "started 100 s ago and has not written a heartbeat of its own yet" at a heartbeat 23 s old.
@{
    Target = "core\WakeFiles.ps1"
    Suite  = "test\test-services.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "the-wake-heartbeat-drops-the-process-start"
           Find = 'if ($ProcessStartedAt -is [datetime]) { $beat["startedAt"] = ConvertTo-HordeWakeTimeText $ProcessStartedAt }'
           Replace = '' }
        @{ Name = "the-wake-heartbeat-process-start-is-the-counts-start"
           Find = 'if ($ProcessStartedAt -is [datetime]) { $beat["startedAt"] = ConvertTo-HordeWakeTimeText $ProcessStartedAt }'
           Replace = 'if ($ProcessStartedAt -is [datetime] -and $null -ne $Counts) { $beat["startedAt"] = ConvertTo-HordeWakeTimeText $Counts.startedAt }' }
        @{ Name = "the-wake-heartbeat-process-start-is-now"
           Find = 'if ($ProcessStartedAt -is [datetime]) { $beat["startedAt"] = ConvertTo-HordeWakeTimeText $ProcessStartedAt }'
           Replace = 'if ($ProcessStartedAt -is [datetime]) { $beat["startedAt"] = ConvertTo-HordeWakeTimeText $At }' }
        @{ Name = "the-wake-heartbeat-process-start-is-local-time-with-no-zone"
           Find = '$beat["startedAt"] = ConvertTo-HordeWakeTimeText $ProcessStartedAt'
           Replace = '$beat["startedAt"] = $ProcessStartedAt.ToLocalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffff")' }
    )
}