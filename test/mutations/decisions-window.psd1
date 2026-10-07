# Mutations of decisions/Window.ps1, which puts the decisions window together. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-window.psd1
# test\test-decisions-window.ps1 must fail for each. That suite opens no window, so this spec holds what
# can be broken without one: the closed list, what the page is handed, when the list is pushed, the
# watch, the attachment and the report. Opening, following and closing a real window are
# test\e2e\e2e-decisions-window.ps1's and the terminal host's own end-to-end scenario's.
@{
    Target = "decisions\Window.ps1"
    Suite  = "test\test-decisions-window.ps1"
    Mutations = @(
        # --- what the page is handed
        @{ Name = "only-open-questions-handed-to-the-page"
           Find = 'return (Get-HordeDecisionWindowRecord -Operation "list" -Request @{ state = "all" })'
           Replace = 'return (Get-HordeDecisionWindowRecord -Operation "list" -Request @{ state = "open" })' }
        @{ Name = "the-time-of-reading-handed-on"
           Find = 'return [pscustomobject]@{ state = "$($record.state)"; value = $record.value; reason = "$($record.reason)" }'
           Replace = 'return $record' }
        @{ Name = "attachment-always-says-attached"
           Find = 'return [pscustomobject]@{ attached = [bool]$State.attachment.attached; reason = "$($State.attachment.reason)" } } }'
           Replace = 'return [pscustomobject]@{ attached = $true; reason = "$($State.attachment.reason)" } } }' }
        @{ Name = "the-page-may-report-anything"
           Find = 'rows = @{ type = "integer"; most = 100000 }; open'
           Replace = 'rows = @{ type = "string"; most = 100000 }; open' }
        @{ Name = "what-the-page-reported-is-not-kept"
           Find = '$State.reports = [int]$State.reports + 1'
           Replace = '' }
        # --- the title
        @{ Name = "title-counts-closed-questions-as-open"
           Find = '$open = @($Record.value.questions | Where-Object { "$($_.state)" -ceq "open" })'
           Replace = '$open = @($Record.value.questions)' }
        @{ Name = "title-counts-everyone-as-waiting"
           Find = '$waiting = @($open | Where-Object { @($_.waiting).Count -gt 0 }).Count'
           Replace = '$waiting = $open.Count' }
        @{ Name = "an-unreadable-list-titled-as-empty"
           Find = 'if ($null -eq $Record -or "$($Record.state)" -cne "known" -or "$($Record.value.outcome)" -cne "done") {'
           Replace = 'if ($null -eq $Record) {' }
        @{ Name = "title-not-set-when-the-list-is-handed-over"
           Find = 'if ($null -ne $Window) { & $Window.setTitle $State.title }'
           Replace = '' }
        # --- pushed when it changed, and only then
        @{ Name = "the-same-list-pushed-again"
           Find = 'if ($json -ceq $State.listJson) { return $false }'
           Replace = '' }
        @{ Name = "a-list-the-page-already-has-is-pushed"
           Find = '$State.listJson = ConvertTo-HordeSurfaceJson -Value $record'
           Replace = '' }
        @{ Name = "a-changed-list-is-not-pushed"
           Find = '& $Window.post (ConvertTo-HordeSurfaceEvent -Bridge $State.bridge -Name "list-changed" -Value $record)'
           Replace = '' }
        @{ Name = "a-change-acted-on-at-once"
           Find = '($now - $State.dirtyAt).TotalMilliseconds -ge $script:HordeDecisionWindowQuietMs) {'
           Replace = '($now - $State.dirtyAt).TotalMilliseconds -ge 0) {' }
        @{ Name = "a-change-asked-for-on-every-tick"
           Find = '$State.dirtyAt = $null'
           Replace = '' }
        # --- the watch
        @{ Name = "a-watch-with-nothing-to-marshal-through"
           Find = 'if ($null -eq $Sync) { return $false }'
           Replace = '' }
        @{ Name = "the-watch-on-every-file"
           Find = 'New-Object System.IO.FileSystemWatcher($State.storeRoot, "*.json")'
           Replace = 'New-Object System.IO.FileSystemWatcher($State.storeRoot, "*.*")' }
        @{ Name = "the-watch-never-raises"
           Find = '$watcher.EnableRaisingEvents = $true'
           Replace = '$watcher.EnableRaisingEvents = $false' }
        @{ Name = "starting-the-watch-notes-nothing"
           Find = '$State.dirtyAt = [datetime]::UtcNow'
           Replace = '' }
        @{ Name = "a-change-is-not-counted"
           Find = '$s.dirtyAt = [datetime]::UtcNow; $s.changes = [int]$s.changes + 1 }'
           Replace = '$s.dirtyAt = [datetime]::UtcNow }' }
        @{ Name = "closing-leaves-the-watch-running"
           Find = '$State.watcher.Dispose() } catch { }; $State.watcher = $null }'
           Replace = '$State.watcher.Dispose() } catch { } }' }
        # --- a second open
        @{ Name = "a-second-open-is-not-seen"
           Find = 'if ($null -ne $State.showEvent -and $State.showEvent.WaitOne(0)) { & $Window.show }'
           Replace = '' }
        @{ Name = "every-home-shares-one-window"
           Find = '[System.IO.Path]::GetFullPath($HordeHome).TrimEnd(''\'').ToLowerInvariant()'
           Replace = '"one"' }
        @{ Name = "a-home-in-another-case-is-another-window"
           Find = '[System.IO.Path]::GetFullPath($HordeHome).TrimEnd(''\'').ToLowerInvariant()'
           Replace = '[System.IO.Path]::GetFullPath($HordeHome).TrimEnd(''\'')' }
        # --- beside a terminal window, or saying why not
        @{ Name = "a-hidden-window-is-attached"
           Find = 'if ($Hidden) { return (& $free "it was opened hidden, and a hidden window stands beside nothing") }'
           Replace = '' }
        @{ Name = "an-unknown-seat-is-looked-for-anyway"
           Find = 'if ($seat.state -cne "known") { return (& $free $seat.reason) }'
           Replace = '' }
        @{ Name = "an-unproven-window-is-stood-beside"
           Find = 'if ($window.state -cne "known") { return (& $free $window.reason) }'
           Replace = 'if ($window.state -cne "known") { return [pscustomobject]@{ attached = $true; handle = [long]1; reason = "" } }' }
        @{ Name = "another-role-is-stood-beside"
           Find = '$script:HordeDecisionWindowRole = "warchief"'
           Replace = '$script:HordeDecisionWindowRole = "orc"' }
        # --- the report
        @{ Name = "the-report-written-only-once"
           Find = '[System.IO.File]::Replace($temp, $State.reportPath, [NullString]::Value)'
           Replace = '[System.IO.File]::Delete($temp)' }
        @{ Name = "the-report-does-not-say-what-was-refused"
           Find = 'refused = [int]$State.bridge.refused; watching'
           Replace = 'refused = 0; watching' }
    )
}
