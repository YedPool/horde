# Mutations of the analyst supervisor's notices to the warchief (cli/AnalystTend.ps1), T-0391 slice 7: a notice is awaited BEFORE it is
# posted, is told only while watched until the warchief's own TAKEN, a refusal (and only a refusal) takes its mark off, one alarm and a
# re-ask cadence kept across passes and a 7-day give-up, a key's event has ONE id and a later event a new one, and the lines are handed back.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\analyst-tell-taken.psd1
# test\test-analyst-tell-taken.ps1 must fail for every one. The list's engine is in decisions-route-taken.psd1 (NoticeTaken.ps1).
@{
    Target = "cli\AnalystTend.ps1"
    Suite  = "test\test-analyst-tell-taken.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # A list that cannot be written no longer holds the post back.
        @{ Name = "analyst-tell-unlisted-notice-still-posted"
           Find = 'if (-not $awaited.ok) { return (& $done $false'
           Replace = 'if ($false) { return (& $done $false' }
        # The mark does not name the warchief's session.
        @{ Name = "analyst-tell-mark-without-session"
           Find = '-SessionId ("" + $where.value.sessionId) -Now $at'
           Replace = '-SessionId "" -Now $at' }
        # A known refusal keeps its mark (a never-sent notice alarms).
        @{ Name = "analyst-tell-refusal-keeps-mark"
           Find = '$removed = Remove-HordeDecisionNoticeTaken -Kind $script:HordeAnalystTellTakenKind -HordeHome $HordeHome -NoticeId $id'
           Replace = '$removed = [pscustomobject]@{ ok = $true; reason = "" }' }
        # An unknown result loses its mark (a notice that landed is no longer watched).
        @{ Name = "analyst-tell-unknown-loses-mark"
           Find = 'if ($r.known -eq $true -and -not $wasListed) {'
           Replace = 'if (-not $wasListed) {' }
        # A refusal removes a mark that was already listed (an earlier post that landed stops being watched, and never alarms).
        @{ Name = "analyst-tell-refusal-removes-listed-mark"
           Find = 'if ($r.known -eq $true -and -not $wasListed) {'
           Replace = 'if ($r.known -eq $true) {' }
        # A refused stage is counted as the messenger having taken it (a held post).
        @{ Name = "analyst-tell-refused-stage-counts-as-taken"
           Find = '$script:HordeAnalystTakenStages = @("accepted", "handed-over", "seen")'
           Replace = '$script:HordeAnalystTakenStages = @("accepted", "handed-over", "seen", "held")' }
        # An already-posted answer for a brand-new mark is counted as fresh (a false TAKEN follows).
        @{ Name = "analyst-tell-already-posted-counted-fresh"
           Find = 'if ($r.detail -clike "already-posted*" -and -not $wasListed) {'
           Replace = 'if ($false) {' }
        @{ Name = "analyst-tell-already-posted-keeps-mark"
           Find = '$null = Remove-HordeDecisionNoticeTaken -Kind $script:HordeAnalystTellTakenKind -HordeHome $HordeHome -NoticeId $id'
           Replace = '$null = 0' }
        @{ Name = "analyst-tell-already-posted-not-said"
           Find = '[void]$lines.Add("analyst: the notice " + $id'
           Replace = '$null = ("analyst: the notice " + $id' }
        # A mark that was already listed (a restart) is taken for a new one.
        @{ Name = "analyst-tell-listed-mark-counts-fresh"
           Find = '$wasListed = Test-HordeAnalystNoticeListed -HordeHome $HordeHome -NoticeId $id'
           Replace = '$wasListed = $false' }
        # The tool's lines are not handed back, nor said by the told step.
        @{ Name = "analyst-tell-lines-not-handed-back"
           Find = 'lines = [string[]]@($lines.ToArray()) } }'
           Replace = 'lines = [string[]]@() } }' }
        @{ Name = "analyst-tell-tail-not-said"
           Find = '$tail = $(if ($more.Count -gt 0)'
           Replace = '$tail = $(if ($false)' }
        # The key is told whatever the teller answered (an unusable list loses the notice for good).
        @{ Name = "analyst-tell-key-told-on-any-answer"
           Find = 'if ($null -ne $r -and $r.ok -eq $true) { $State.told'
           Replace = 'if ($null -ne $r) { $State.told' }
        # THE EVENT'S ID: the generation is not handed to the teller, is not in the id, or the key is not.
        @{ Name = "analyst-tell-generation-not-handed-over"
           Find = '-With @($Key, $body, $Values, $gen)'
           Replace = '-With @($Key, $body, $Values, 0)' }
        @{ Name = "analyst-tell-id-ignores-generation"
           Find = 'ConvertTo-HordeAnalystMessageId -Seed ("tell:" + $Key + ":" + $Gen)'
           Replace = 'ConvertTo-HordeAnalystMessageId -Seed ("tell:" + $Key)' }
        @{ Name = "analyst-tell-id-ignores-key"
           Find = 'ConvertTo-HordeAnalystMessageId -Seed ("tell:" + $Key + ":" + $Gen)'
           Replace = 'ConvertTo-HordeAnalystMessageId -Seed ("tell:" + $Gen)' }
        @{ Name = "analyst-tell-clear-keeps-generation"
           Find = '((Get-HordeAnalystTellGen -State $State -Key $k) + 1)'
           Replace = '((Get-HordeAnalystTellGen -State $State -Key $k) + 0)' }
        @{ Name = "analyst-tell-clear-forgets-other-generations"
           Find = '$Keys -cnotcontains $Matches[1]) { [void]$rows.Add("" + $row) }'
           Replace = '$Keys -cnotcontains $Matches[1]) { $null = 0 }' }
        # The list is asked with no messenger: only the clock speaks, so a TAKEN is never seen.
        @{ Name = "analyst-tell-tick-never-asks-the-messenger"
           Find = '{ $messenger = $found.value } } catch { $messenger = $null }'
           Replace = '{ $null = 0 } } catch { $messenger = $null }' }
        # The alarm limit, the re-ask cadence and the give-up are the engine's three clocks.
        @{ Name = "analyst-tell-alarm-limit-ignored"
           Find = '-Now $Now.ToUniversalTime() -AlarmSeconds $AlarmSeconds -AfterAlarmSeconds'
           Replace = '-Now $Now.ToUniversalTime() -AlarmSeconds 90 -AfterAlarmSeconds' }
        @{ Name = "analyst-tell-reask-every-pass"
           Find = '-AfterAlarmSeconds $AfterAlarmSeconds -TtlSeconds'
           Replace = '-AfterAlarmSeconds 0 -TtlSeconds' }
        @{ Name = "analyst-tell-never-given-up"
           Find = '-TtlSeconds $script:HordeAnalystTtlSeconds -Memory $memory'
           Replace = '-TtlSeconds 1e12 -Memory $memory' }
        # The cadence is kept across passes in a file: a table lost between passes asks every pass.
        @{ Name = "analyst-tell-asked-table-not-read"
           Find = '$memory = Read-HordeAnalystTellAsked -HordeHome $HordeHome'
           Replace = '$memory = @{}' }
        @{ Name = "analyst-tell-asked-table-not-written"
           Find = '[void](Write-HordeAnalystTellAsked -HordeHome $HordeHome -Table $memory)'
           Replace = '$null = 0' }
        @{ Name = "analyst-tell-asked-table-keeps-the-over"
           Find = 'if (-not $live.ContainsKey($id)) { continue }'
           Replace = '$null = 0' }
        # What the engine remembers is kept beside it (round 2, item 4): the alarm said and the taken said survive a new process.
        @{ Name = "analyst-tell-alarm-memory-not-kept"
           Find = '$script:HordeAnalystTellMemoryKeyPattern = ''alarmed-[0-9a-f]{32}|delivered-'
           Replace = '$script:HordeAnalystTellMemoryKeyPattern = ''alarmed-[0-9a-f]{3}|delivered-' }
        @{ Name = "analyst-tell-taken-memory-not-kept"
           Find = '|delivered-[0-9a-f]{8}-'
           Replace = '|delivered-[0-9a-f]{9}-' }
        @{ Name = "analyst-tell-memory-not-read"
           Find = ' 1\z'')) { $table[$Matches[1]] = $true }'
           Replace = ' 1\z'')) { $null = 0 }' }
        @{ Name = "analyst-tell-memory-not-written"
           Find = '-and $Table[$k] -eq $true) { $k + " 1" }'
           Replace = '-and $false) { $k + " 1" }' }
        @{ Name = "analyst-tell-taken-said-again"
           Find = '$saidTaken.ContainsKey("delivered-" + $Matches[1])'
           Replace = '$false' }
        # The look is made for a list with nothing on it (the file stays after the last mark).
        @{ Name = "analyst-tell-awaiting-when-file-exists"
           Find = 'return (@($r.value.awaiting).Count -gt 0)'
           Replace = 'return $true' }
        # An unreadable list is not awaited: the notice goes unwatched.
        @{ Name = "analyst-tell-unreadable-list-not-awaiting"
           Find = 'if ($r.state -cne "known") { return $true }'
           Replace = 'if ($r.state -cne "known") { return $false }' }
        # A quiet pass asks for nothing.
        @{ Name = "analyst-tell-always-awaiting"
           Find = 'if (-not [System.IO.File]::Exists($path)) { return $false }'
           Replace = 'if (-not [System.IO.File]::Exists($path)) { return $true }' }
        # THE RETRY (round 2, item 3): a tell the messenger refused is kept, told again next pass with its round, and not for an event that is over.
        @{ Name = "analyst-tell-retry-not-kept"
           Find = 'if ($Retry) { Set-HordeAnalystTellRetry -State $State -Key $Key -Round $Round }'
           Replace = '$null = 0' }
        @{ Name = "analyst-tell-retry-never-run"
           Find = 'foreach ($l in @(Invoke-HordeAnalystTellRetries -State $s -Tools $Tools -Values $v -Skip $skipRetry)) { & $say $l }'
           Replace = '$null = $skipRetry' }
        @{ Name = "analyst-tell-retry-forgets-the-round"
           Find = '-Values $Values -Round $round -Retry))'
           Replace = '-Values $Values -Round "" -Retry))' }
        @{ Name = "analyst-tell-retry-for-an-event-that-is-over"
           Find = 'if ($Skip -ccontains $key) { continue }'
           Replace = '$null = 0' }
        @{ Name = "analyst-tell-retry-kept-after-posted"
           Find = 'Remove-HordeAnalystTellRetry -State $State -Key $Key; return ("posted to the warchief: "'
           Replace = 'return ("posted to the warchief: "' }
        @{ Name = "analyst-tell-clear-keeps-the-retry"
           Find = 'foreach ($k in $Keys) { Remove-HordeAnalystTellRetry -State $State -Key $k }'
           Replace = '$null = 0' }
        @{ Name = "analyst-tell-started-not-retried"
           Find = '-Key ("started-" + $d.reason) -Tools $Tools -Values $v -Retry)'
           Replace = '-Key ("started-" + $d.reason) -Tools $Tools -Values $v)' }
        @{ Name = "analyst-tell-spawn-failed-not-retried"
           Find = '-Key "spawn-failed" -Tools $Tools -Values $v -Retry)'
           Replace = '-Key "spawn-failed" -Tools $Tools -Values $v)' }
        @{ Name = "analyst-tell-no-answer-not-retried"
           Find = '-Key "no-answer" -Tools $Tools -Values $v -Round $id -Retry)'
           Replace = '-Key "no-answer" -Tools $Tools -Values $v -Round $id)' }
        @{ Name = "analyst-tell-no-answer-loses-its-round"
           Find = '-Key "no-answer" -Tools $Tools -Values $v -Round $id -Retry)'
           Replace = '-Key "no-answer" -Tools $Tools -Values $v -Retry)' }
        # THE PASS: the look is never made, its lines are not said, its failure kills the pass, or the unreadable state hides its lines.
        @{ Name = "analyst-tell-pass-never-looks"
           Find = 'if ($null -ne $Tools["TellTaken"]) {'
           Replace = 'if ($false) {' }
        @{ Name = "analyst-tell-pass-drops-the-lines"
           Find = 'foreach ($l in @(& $Tools["TellTaken"] $Policy.values)) { & $say ("" + $l) }'
           Replace = 'foreach ($l in @(& $Tools["TellTaken"] $Policy.values)) { $null = $l }' }
        @{ Name = "analyst-tell-pass-look-failure-kills-pass"
           Find = 'catch { & $say ("the awaiting notices could not be asked: " + $_.Exception.Message) }'
           Replace = 'catch { throw }' }
        @{ Name = "analyst-tell-pass-unreadable-state-hides-lines"
           Find = 'lines = @($lines.ToArray()) + @("the supervisor''s state cannot be read: '
           Replace = 'lines = @("the supervisor''s state cannot be read: ' }
    )
}
