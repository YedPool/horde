# Mutations of core/Heartbeat.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\heartbeat.psd1
# Each breaks one promise of a heartbeat; test\test-heartbeat.ps1 must fail for every one.
@{
    Target = "core\Heartbeat.ps1"
    Suite  = "test\test-heartbeat.ps1"
    Mutations = @(
        @{ Name = "stale-is-a-constant"
           Find = '$ticks = [long]$script:HordeHeartbeatStaleTicks * [long][System.Math]::Max(0, $TickSeconds)'
           Replace = '$ticks = [long]0' }
        @{ Name = "no-floor"
           Find = 'return [int][System.Math]::Min([long][int]::MaxValue, [System.Math]::Max([long]$FloorSeconds, $ticks))'
           Replace = 'return [int][System.Math]::Min([long][int]::MaxValue, $ticks)' }
        @{ Name = "pid-alone-is-the-identity"
           Find = 'if ($One -isnot [datetime] -or $Other -isnot [datetime]) { return $false }'
           Replace = 'if ($One -isnot [datetime] -or $Other -isnot [datetime]) { return $true }' }
        @{ Name = "any-start-is-the-same"
           Find = '.TotalSeconds) -le $script:HordeHeartbeatStartSlackSeconds)'
           Replace = '.TotalSeconds) -le 86400)' }
        @{ Name = "start-not-written"
           Find = 'if ($ProcessStartedAt -is [datetime]) { $beat["startedAt"] = ConvertTo-HordeHeartbeatTimeText -At $ProcessStartedAt }'
           Replace = '' }
        @{ Name = "relative-path-taken"
           Find = 'if (-not [System.IO.Path]::IsPathRooted($Path)) { throw ("a heartbeat is written to an absolute path'
           Replace = 'if ($false) { throw ("a heartbeat is written to an absolute path' }
        @{ Name = "quiet-write-throws"
           Find = '} catch { return (New-HordeUnknown -Reason "the heartbeat could not be written" -ErrorRecord $_) }'
           Replace = '} catch { throw }' }
        @{ Name = "no-file-is-unknown"
           Find = 'if (-not [System.IO.File]::Exists($Path)) { return (New-HordeAbsent -Note "there is no heartbeat: it has never run here") }'
           Replace = 'if (-not [System.IO.File]::Exists($Path)) { return (New-HordeUnknown -Reason "there is no heartbeat") }' }
        @{ Name = "no-time-accepted"
           Find = 'if ($null -eq $at) { return (New-HordeUnknown -Reason "the heartbeat holds no time") }'
           Replace = 'if ($null -eq $at) { $at = [datetime]::UtcNow }' }
        @{ Name = "zoneless-time-accepted"
           Find = 'if ($parsed.Kind -eq [System.DateTimeKind]::Unspecified) { return $null }'
           Replace = '' }
        @{ Name = "no-pid-accepted"
           Find = 'if ($processId -eq 0) { return (New-HordeUnknown -Reason "the heartbeat names no process") }'
           Replace = '' }
        @{ Name = "oversize-read"
           Find = 'if ($text.Length -gt $script:HordeHeartbeatMaxBytes) {'
           Replace = 'if ($false) {' }
        @{ Name = "writer-tick-ignored"
           Find = '    if ($tick -le 0) { $tick = $DefaultTickSeconds }'
           Replace = '    $tick = $DefaultTickSeconds' }
        @{ Name = "future-is-fresh"
           Find = 'if ($age -lt (0 - $stale)) { return (New-HordeUnknown -Reason ("the heartbeat is dated "'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ("the heartbeat is dated "' }
        @{ Name = "stale-boundary-moved"
           Find = 'fresh = [bool]($age -le $stale)'
           Replace = 'fresh = [bool]($age -lt $stale)' }
        @{ Name = "absent-verdict-is-fresh"
           Find = '    if ($Heartbeat.state -cne "known") { return $Heartbeat }'
           Replace = '    if ($Heartbeat.state -cne "known") { return (New-HordeKnown -Value ([pscustomobject]@{ fresh = $true; ageSeconds = [long]0; staleAfterSeconds = 0; tickSeconds = 0 })) }' }
            # --- review of PR 249 ---
        @{ Name = "condition-not-written"
           Find = 'if ($Condition -ne "") { $beat["condition"] = $Condition;'
           Replace = 'if ($false) { $beat["condition"] = $Condition;' }
        @{ Name = "condition-not-read"
           Find = '$condition = $(if (("" + $c.Value) -cmatch $script:HordeHeartbeatConditionPattern) { "" + $c.Value } else { "unwell" })'
           Replace = '$condition = ""' }
        @{ Name = "odd-condition-read-as-well"
           Find = '{ "" + $c.Value } else { "unwell" })'
           Replace = '{ "" + $c.Value } else { "" })' }
        @{ Name = "condition-word-unchecked"
           Find = 'if ($Condition -ne "" -and $Condition -cnotmatch $script:HordeHeartbeatConditionPattern) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "why-keeps-line-breaks"
           Find = '$t = ("" + $Text) -replace ''\p{Cc}+'', '' '''
           Replace = '$t = ("" + $Text)' }
        @{ Name = "why-not-capped"
           Find = 'if ($t.Length -gt $script:HordeHeartbeatWhyMost) {'
           Replace = 'if ($false) {' }
    )
}
