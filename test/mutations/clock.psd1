# Mutations of remote/Clock.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\clock.psd1
# Each breaks one rule of remote plan R6; test\test-clock.ps1 must fail for every one of them.
@{
    Target = "remote\Clock.ps1"
    Suite  = "test\test-clock.ps1"
    Mutations = @(
        @{ Name = "offset-sign-flipped"
           Find = '$offset = (($T2 - $T1).TotalSeconds + ($T3 - $T4).TotalSeconds) / 2'
           Replace = '$offset = (($T1 - $T2).TotalSeconds + ($T4 - $T3).TotalSeconds) / 2' }
        @{ Name = "offset-not-halved"
           Find = '($T3 - $T4).TotalSeconds) / 2'
           Replace = '($T3 - $T4).TotalSeconds)' }
        @{ Name = "round-trip-includes-node-time"
           Find = '$rtt = ($T4 - $T1).TotalSeconds - ($T3 - $T2).TotalSeconds'
           Replace = '$rtt = ($T4 - $T1).TotalSeconds' }
        @{ Name = "hub-clock-moved-accepted"
           Find = 'if ($T4 -lt $T1) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "node-answered-before-receiving-accepted"
           Find = 'if ($T3 -lt $T2) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "any-zone-accepted"
           Find = 'return ($Time -is [datetime] -and $Time.Kind -eq [System.DateTimeKind]::Utc)'
           Replace = 'return ($Time -is [datetime])' }
        @{ Name = "silence-window-off-by-one"
           Find = 'if ($silent -le $script:HordeLinkSilenceSeconds) {'
           Replace = 'if ($silent -lt $script:HordeLinkSilenceSeconds) {' }
        @{ Name = "silent-link-known-down"
           Find = 'return (New-HordeUnknown -Reason ("no frame since " + $LastFrameAt.ToString("o")'
           Replace = 'return (New-HordeKnown -Value $false); return (New-HordeUnknown -Reason ("no frame since " + $LastFrameAt.ToString("o")' }
        @{ Name = "silent-link-reason-unnamed"
           Find = '"no frame since " + $LastFrameAt.ToString("o") + ", "'
           Replace = '"no frame since a while, "' }
        @{ Name = "node-silent-is-stopped"
           Find = 'return (New-HordeUnknown -Reason $why)'
           Replace = 'return (New-HordeKnown -Value $false)' }
        @{ Name = "deregistered-ignored"
           Find = 'if ($Deregistered) { return (New-HordeAbsent -Note "the node was deregistered") }'
           Replace = '' }
        @{ Name = "link-lost-time-unnamed"
           Find = 'if (Test-HordeClockUtc $LinkLostAt) { $why = "link lost at " + $LinkLostAt.ToString("o") }'
           Replace = '' }
        @{ Name = "shut-down-node-sessions-dead"
           Find = 'if ($Node.state -ceq "known" -and $Node.value -eq $false) { return (New-HordeUnknown'
           Replace = 'if ($Node.state -ceq "known" -and $Node.value -eq $false) { return (New-HordeAbsent -Note "dead"); return (New-HordeUnknown' }
        @{ Name = "node-reason-dropped"
           Find = 'return (New-HordeUnknown -Reason ("the node cannot be heard: " + $Node.reason))'
           Replace = 'return (New-HordeUnknown -Reason "the node cannot be heard")' }
        @{ Name = "partial-inventory-absent"
           Find = 'if ($InventoryComplete) { return (New-HordeAbsent'
           Replace = 'if ($true) { return (New-HordeAbsent' }
        @{ Name = "session-not-aged"
           Find = 'return (Limit-HordeRemoteAge -Observation $Observation -TtlSeconds $TtlSeconds -Now $Now)'
           Replace = 'return $Observation.answer' }
        @{ Name = "fault-ignores-slow-clocks"
           Find = '$off = [math]::Abs($offset)'
           Replace = '$off = $offset' }
        @{ Name = "fault-at-the-allowance"
           Find = 'if ($off + $half -le $script:HordeClockSkewSeconds) {'
           Replace = 'if ($off + $half -lt $script:HordeClockSkewSeconds) {' }
        @{ Name = "fault-ignores-uncertainty"
           Find = 'if ($off - $half -gt $script:HordeClockSkewSeconds) {'
           Replace = 'if ($off -gt $script:HordeClockSkewSeconds) {' }
        @{ Name = "uncertain-is-no-fault"
           Find = 'return (New-HordeUnknown -Reason ("the offset reads "'
           Replace = 'return (New-HordeKnown -Value $false); return (New-HordeUnknown -Reason ("the offset reads "' }
        @{ Name = "no-sample-is-no-fault"
           Find = 'if (-not (Test-HordeClockAnswer $Sample) -or $Sample.state -cne "known") { return (New-HordeUnknown'
           Replace = 'if (-not (Test-HordeClockAnswer $Sample) -or $Sample.state -cne "known") { return (New-HordeKnown -Value $false); return (New-HordeUnknown' }
        @{ Name = "aged-by-the-node-stamp"
           Find = 'if ($Answer.state -ceq "known") { $kept = New-HordeKnown -Value $Answer.value -ObservedAt $hubObserved }'
           Replace = 'if ($Answer.state -ceq "known") { $kept = $Answer }' }
        @{ Name = "aged-from-receipt-only"
           Find = '$hubObserved = $ReceivedAt - (New-TimeSpan -Seconds $ageAtSend)'
           Replace = '$hubObserved = $ReceivedAt' }
        @{ Name = "absent-aged-by-the-node-stamp"
           Find = 'else { $kept = New-HordeAbsent -Note "$($Answer.reason)" -ObservedAt $hubObserved }'
           Replace = 'else { $kept = $Answer }' }
        @{ Name = "unstamped-answer-kept"
           Find = '$kept = New-HordeUnknown -Reason "the node''s answer has no UTC observation time, so its age cannot be checked"'
           Replace = '$kept = $Answer' }
        @{ Name = "observed-after-sent-trusted"
           Find = 'if ($ageAtSend -lt -$script:HordeClockSkewSeconds) {'
           Replace = 'if ($false) {' }
        @{ Name = "node-stamp-dropped"
           Find = 'return [pscustomobject]@{ answer = $kept; nodeObservedAt = $nodeStamp; nodeSentAt = $NodeSentAt; receivedAt = $ReceivedAt }'
           Replace = 'return [pscustomobject]@{ answer = $kept; nodeObservedAt = $ReceivedAt; nodeSentAt = $NodeSentAt; receivedAt = $ReceivedAt }' }
        @{ Name = "non-answer-accepted"
           Find = 'if (-not (Test-HordeClockAnswer $Answer)) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "state-any-case"
           Find = 'return ($state -is [string] -and $script:HordeClockAnswerStates -ccontains $state)'
           Replace = 'return ($state -is [string] -and $script:HordeClockAnswerStates -contains $state)' }
        @{ Name = "local-now-accepted-in-age"
           Find = 'if (-not (Test-HordeClockUtc $Now)) { throw "now must be a UTC [datetime] to age an observation" }'
           Replace = '' }
        @{ Name = "local-now-accepted-in-link"
           Find = 'if (-not (Test-HordeClockUtc $Now)) { throw "now must be a UTC [datetime] to measure a link''s silence" }'
           Replace = '' }
        @{ Name = "future-last-frame-is-up"
           Find = 'if ($silent -lt -$script:HordeClockSkewSeconds) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "local-last-frame-called-no-frame"
           Find = 'if (-not (Test-HordeClockUtc $LastFrameAt)) { return (New-HordeUnknown -Reason "the last frame''s time is not a UTC time'
           Replace = 'if (-not (Test-HordeClockUtc $LastFrameAt)) { return (New-HordeUnknown -Reason "no frame has arrived: the last frame''s time is not a UTC time' }
        @{ Name = "any-bye-is-stopped"
           Find = 'if ($byeReason -ceq "shutdown") {'
           Replace = 'if ($true) {' }
        @{ Name = "old-bye-beats-a-live-link"
           Find = 'if ((Test-HordeClockAnswer $Link) -and $Link.state -ceq "known" -and $Link.value -eq $true) { return (New-HordeKnown -Value $true) }'
           Replace = '' }
        @{ Name = "bye-time-unnamed"
           Find = 'if (Test-HordeClockUtc $byeWhen) { $byeAt = " at " + $byeWhen.ToString("o") }'
           Replace = 'if ($false) { }' }
        @{ Name = "no-node-record-is-heard"
           Find = 'if (-not (Test-HordeClockAnswer $Node)) { return (New-HordeUnknown'
           Replace = 'if (-not (Test-HordeClockAnswer $Node)) { return (New-HordeAbsent -Note "x"); return (New-HordeUnknown' }
        @{ Name = "listed-without-answer-is-absent"
           Find = 'if ($null -eq $Observation) { return (New-HordeUnknown'
           Replace = 'if ($null -eq $Observation) { return (New-HordeAbsent -Note "x"); return (New-HordeUnknown' }
    )
}
