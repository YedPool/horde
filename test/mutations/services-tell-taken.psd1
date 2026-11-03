# Mutations of the supervisor's notices to the warchief (cli/ServicesTell.ps1), T-0391 slice 6: a notice is awaited BEFORE it is posted,
# is delivered only on the warchief's own TAKEN, a refusal (and only a refusal) takes its mark off, one alarm and a re-ask cadence kept
# across the supervisor's passes and a 7-day give-up, and its lines are handed back.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\services-tell-taken.psd1
# test\test-services-tell-taken.ps1 must fail for every one. The list's engine is in decisions-route-taken.psd1 (NoticeTaken.ps1).
@{
    Target = "cli\ServicesTell.ps1"
    Suite  = "test\test-services-tell-taken.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # A list that cannot be written no longer holds the post back.
        @{ Name = "services-tell-unlisted-notice-still-posted"
           Find = 'if (-not $awaited.ok) { $problem'
           Replace = 'if ($false) { $problem' }
        # The mark does not name the warchief's session.
        @{ Name = "services-tell-mark-without-session"
           Find = '-SessionId ("" + $where.value.sessionId) -Now $at'
           Replace = '-SessionId "" -Now $at' }
        # A known refusal keeps its mark (a never-sent notice alarms).
        @{ Name = "services-tell-refusal-keeps-mark"
           Find = '$removed = Remove-HordeDecisionNoticeTaken -Kind $script:HordeServiceTellTakenKind -HordeHome $HordeHome -NoticeId $message.messageId'
           Replace = '$removed = [pscustomobject]@{ ok = $true; reason = "" }' }
        # An unknown result loses its mark (a notice that landed is no longer watched).
        @{ Name = "services-tell-unknown-loses-mark"
           Find = 'else { $problem = "messenger " + $messenger.name + " did not take it: " + $posted.reason }'
           Replace = 'else { $null = Remove-HordeDecisionNoticeTaken -Kind $script:HordeServiceTellTakenKind -HordeHome $HordeHome -NoticeId $message.messageId; $problem = "messenger " + $messenger.name + " did not take it: " + $posted.reason }' }
        # A known refusal is counted as the messenger having taken it (a held post).
        @{ Name = "services-tell-refused-stage-counts-as-taken"
           Find = '$script:HordeServiceTellStages = @("accepted", "handed-over", "seen")'
           Replace = '$script:HordeServiceTellStages = @("accepted", "handed-over", "seen", "held")' }
        # An already-posted answer for a brand-new mark is counted as fresh (a false TAKEN follows).
        @{ Name = "services-tell-already-posted-counted-fresh"
           Find = 'if ("$($posted.value.reason)" -clike "already-posted*" -and -not $wasListed) {'
           Replace = 'if ($false) {' }
        @{ Name = "services-tell-already-posted-keeps-mark"
           Find = '$null = Remove-HordeDecisionNoticeTaken -Kind $script:HordeServiceTellTakenKind -HordeHome $HordeHome -NoticeId $message.messageId'
           Replace = '$null = 0' }
        @{ Name = "services-tell-already-posted-not-said"
           Find = '[void]$lines.Add("services: the notice " + $message.messageId'
           Replace = '$null = ("services: the notice " + $message.messageId' }
        # A mark that was already listed (a restart) is taken for a new one.
        @{ Name = "services-tell-listed-mark-counts-fresh"
           Find = '$wasListed = Test-HordeServiceNoticeListed -HordeHome $HordeHome -NoticeId $message.messageId'
           Replace = '$wasListed = $false' }
        # The post's lines are not handed back (a full list given up, an already-posted copy).
        @{ Name = "services-tell-lines-not-handed-back"
           Find = 'lines = [string[]]@($lines.ToArray()) } }'
           Replace = 'lines = [string[]]@() } }' }
        # The list is asked with no messenger: only the clock speaks, so a TAKEN is never seen.
        @{ Name = "services-tell-tick-never-asks-the-messenger"
           Find = '{ $messenger = $found.value } } catch { $messenger = $null }'
           Replace = '{ $null = 0 } } catch { $messenger = $null }' }
        # The alarm limit, the re-ask cadence and the give-up are the engine's three clocks.
        @{ Name = "services-tell-alarm-limit-ignored"
           Find = '-Now $Now.ToUniversalTime() -AlarmSeconds $AlarmSeconds -AfterAlarmSeconds'
           Replace = '-Now $Now.ToUniversalTime() -AlarmSeconds 90 -AfterAlarmSeconds' }
        @{ Name = "services-tell-reask-every-pass"
           Find = '-AfterAlarmSeconds $AfterAlarmSeconds -TtlSeconds'
           Replace = '-AfterAlarmSeconds 0 -TtlSeconds' }
        @{ Name = "services-tell-never-given-up"
           Find = '-TtlSeconds $script:HordeServiceTellTtlSeconds -Memory $memory'
           Replace = '-TtlSeconds 1e12 -Memory $memory' }
        # The cadence is kept across passes in a file: a table lost between passes asks every pass.
        @{ Name = "services-tell-asked-table-not-read"
           Find = '$memory = Read-HordeServiceTellAsked -HordeHome $HordeHome'
           Replace = '$memory = @{}' }
        @{ Name = "services-tell-asked-table-not-written"
           Find = '[void](Write-HordeServiceTellAsked -HordeHome $HordeHome -Table $memory)'
           Replace = '$null = 0' }
        @{ Name = "services-tell-asked-table-keeps-the-over"
           Find = 'if ($live.ContainsKey($k) -and $Table[$k] -is [long])'
           Replace = 'if ($Table[$k] -is [long])' }
        # A quiet pass loads the port for nothing.
        @{ Name = "services-tell-always-awaiting"
           Find = 'return [bool][System.IO.File]::Exists((Get-HordeDecisionNoticeTakenPath -Kind $script:HordeServiceTellTakenKind -HordeHome $HordeHome))'
           Replace = 'return $true' }
    )
}
