# Mutations of what the channels' port does for the runner's sending during its watch
# (channels/Port.ps1: the Glance, a Tick of named channels, and the inbox watched in slices;
# 2026-10-13). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-channels-port-send.psd1
# test\test-relay-run-send.ps1 must fail for every one. Every find string occurs exactly once. The
# port's other rules are test\mutations\relay-channels-port.psd1's, against test\test-relay-channels.ps1.
@{
    Target = "channels\Port.ps1"
    Suite  = "test\test-relay-run-send.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # --- the Glance
        @{ Name = "any-answer-of-a-glance-is-a-yes"
           Find = 'if ($said -is [bool] -and $said) { [void]$due.Add($name) }'
           Replace = 'if ($said) { [void]$due.Add($name) }' }
        @{ Name = "a-glance-that-throws-is-a-yes"
           Find = 'catch { [void]$lines.Add($name + ": could not look for something to send, so it is sent at the end of the watch: " + $_.Exception.Message) }'
           Replace = 'catch { [void]$due.Add($name) }' }
        @{ Name = "a-glance-that-throws-is-silent"
           Find = 'catch { [void]$lines.Add($name + ": could not look for something to send, so it is sent at the end of the watch: " + $_.Exception.Message) }'
           Replace = 'catch { }' }
        @{ Name = "glance-with-no-tick-registered"
           Find = 'if ($null -ne $Glance -and $null -eq $Tick) {'
           Replace = 'if ($false) {' }
        @{ Name = "glance-not-kept-at-registration"
           Find = 'tick = $Tick; glance = $Glance }'
           Replace = 'tick = $Tick; glance = $null }' }
        # --- a Tick of the channels named
        @{ Name = "named-tick-ticks-every-channel"
           Find = '        if ($null -ne $Only -and @($Only) -cnotcontains $name) { continue }'
           Replace = '' }
        # --- the inbox watched in slices
        @{ Name = "inbox-never-watched-in-slices"
           Find = 'if ($null -ne $Between -and $SliceMs -gt 0 -and (Test-HordeRelayWatchInSlices $Context.connection)) {'
           Replace = 'if ($false) {' }
        @{ Name = "slices-asked-of-a-relay-that-has-none"
           Find = '-and $SliceMs -gt 0 -and (Test-HordeRelayWatchInSlices $Context.connection)) {'
           Replace = '-and $SliceMs -gt 0) {' }
        @{ Name = "between-cannot-end-the-watch"
           Find = 'if ($stop -is [bool] -and $stop) {'
           Replace = 'if ($false) {' }
        @{ Name = "stop-leaves-the-last-arrivals-unread"
           Find = 'if ($stop -is [bool] -and $stop) { return (Wait-HordeRelayWatch -Watch $opened.value -Last) }'
           Replace = 'if ($stop -is [bool] -and $stop) { return (New-HordeKnown -Value ([pscustomobject]@{ mailbox = $Context.mailbox; since = $Context.cursor; next = $Context.cursor; items = @(); anomalies = @() })) }' }
        @{ Name = "watch-in-slices-never-let-go"
           Find = '    } finally { Close-HordeRelayWatch -Watch $opened.value }'
           Replace = '    } finally { }' }
        @{ Name = "slice-longer-than-the-relay-allows"
           Find = '[System.Math]::Min([double]$SliceMs, [double]$Context.connection.relay.limits.maxWatchMs)'
           Replace = '[double]$SliceMs' }
    )
}
