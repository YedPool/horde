# Mutations of core/projection's serving rule for a node: Get-HordeSessionEndProof's rules,
# Remove-HordeEndedSessions and ConvertTo-HordeNodeViewDocument (ledger core-projection L-100). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\projection-ended.psd1
# test\test-projection.ps1 must fail for each. Only the ended section runs: each rule has its own case
# there. The reality check is skipped, as in projection.psd1, so a passing run exits 3.
@{
    Target = "core\Projection.ps1"
    Suite  = "test\test-projection.ps1"
    Environment = @{ HORDE_SKIP_REALITY = "1"; HORDE_FAIL_FAST = "1"; HORDE_SECTIONS = "ended" }
    PassCodes = @(3)
    Mutations = @(
        # The proof itself.
        @{ Name = "unknown-liveness-taken-as-ended"
           Find = 'if (@("gone", "reused") -cnotcontains $kind) { return "" }'
           Replace = 'if (@("gone", "reused", "uncheckable", "no-table") -cnotcontains $kind) { return "" }' }
        @{ Name = "reused-pid-not-proof"
           Find = 'if (@("gone", "reused") -cnotcontains $kind) { return "" }'
           Replace = 'if (@("gone") -cnotcontains $kind) { return "" }' }
        # The listing is whole.
        @{ Name = "incomplete-listing-ignored"
           Find = 'if (-not $C.identity.complete.Contains($agent) -or $C.identity.complete[$agent].state -ne "known") { return "" }'
           Replace = 'if ($false) { return "" }' }
        # The file is older than the table.
        @{ Name = "table-read-time-taken-after-the-read"
           Find = 'if ($null -eq $Processes) { $tableAt = [datetime]::UtcNow; $Processes = Read-HordePlatformProcessTable -Platform $Platform }'
           Replace = 'if ($null -eq $Processes) { $Processes = Read-HordePlatformProcessTable -Platform $Platform; $tableAt = [datetime]::UtcNow }' }
        @{ Name = "table-race-ignored"
           Find = 'if ($born -ge $C.tableAt) { return "" }'
           Replace = 'if ($false) { return "" }' }
        # Reused by another program.
        @{ Name = "agent-at-reused-pid-taken-as-proof"
           Find = 'if ($kind -ceq "reused" -and ($procs.imagePids.ContainsKey($procId) -or $procs.hostPids.ContainsKey($procId))) { return "" }'
           Replace = 'if ($false) { return "" }' }
        @{ Name = "host-image-at-reused-pid-taken-as-proof"
           Find = '($procs.imagePids.ContainsKey($procId) -or $procs.hostPids.ContainsKey($procId))'
           Replace = '($procs.imagePids.ContainsKey($procId))' }
        # No process of the agent is unread.
        @{ Name = "unread-command-line-ignored"
           Find = 'if ($null -eq $C.processes.value[$k].commandLine) { return "" }'
           Replace = 'if ($false) { return "" }' }
        @{ Name = "unread-host-command-line-ignored"
           Find = 'foreach ($k in @(@($procs.imagePids.Keys) + @($procs.hostPids.Keys))) {'
           Replace = 'foreach ($k in @($procs.imagePids.Keys)) {' }
        # No unaccounted agent process.
        @{ Name = "later-orphan-ignored"
           Find = 'if ($null -eq $cr -or ([datetime]$cr) -gt $born.AddHours(-1)) { return "" }'
           Replace = 'if ($false) { return "" }' }
        @{ Name = "orphan-with-no-start-trusted"
           Find = 'if ($null -eq $cr -or ([datetime]$cr) -gt $born.AddHours(-1)) { return "" }'
           Replace = 'if ($null -ne $cr -and ([datetime]$cr) -gt $born.AddHours(-1)) { return "" }' }
        @{ Name = "host-image-orphan-ignored"
           Find = '@(@($procs.imagePids.Keys) + @($procs.hostPids.Keys) | Select-Object -Unique)'
           Replace = '@($procs.imagePids.Keys)' }
        @{ Name = "verified-process-counted-as-orphan"
           Find = 'if ($procs.verifiedPids.ContainsKey($k)) { continue }'
           Replace = '' }
        # The other stores are whole.
        @{ Name = "wezfleet-holes-ignored"
           Find = 'if ($w.state -ne "known") { return "" }'
           Replace = 'if ($false) { return "" }' }
        @{ Name = "run-holes-ignored"
           Find = '@($C.wf.registry.complete, $C.wf.runs.runsComplete, $C.wf.runs.rostersComplete, $C.wf.runs.reportsComplete)'
           Replace = '@($C.wf.registry.complete)' }
        @{ Name = "no-wezfleet-taken-as-holes"
           Find = 'if ($C.wf.present) {'
           Replace = 'if ($true) {' }
        # No other signal.
        @{ Name = "live-handle-ignored"
           Find = 'foreach ($row in @($Handles.value)) { if (@($row.sessions) -contains $id -or @($row.claimants) -contains $id) { return "" } }'
           Replace = '' }
        @{ Name = "claimed-handle-ignored"
           Find = 'if (@($row.sessions) -contains $id -or @($row.claimants) -contains $id) { return "" }'
           Replace = 'if (@($row.sessions) -contains $id) { return "" }' }
        @{ Name = "handle-rows-not-passed"
           Find = '$why = Get-HordeSessionEndProof -C $C -Session $s -Handles $Projection.handles'
           Replace = '$why = Get-HordeSessionEndProof -C $C -Session $s' }
        @{ Name = "other-live-signals-ignored"
           Find = 'if ((Get-HordeLiveSignal -C $C -Id $id -NotItsControlFile) -ne "") { return "" }'
           Replace = 'if ($false) { return "" }' }
        @{ Name = "stale-control-file-counted-as-a-signal"
           Find = 'if (-not $NotItsControlFile -and $C.identity.records.ContainsKey($Id)) { return "a control file names it" }'
           Replace = 'if ($C.identity.records.ContainsKey($Id)) { return "a control file names it" }' }
        @{ Name = "pane-file-signal-ignored"
           Find = 'if ($C.paneVerdicts.bySession.ContainsKey($Id)) { return "a guarded pane-sessions file names it" }'
           Replace = ''
           Expect = "survives"
           Reason = "Defence in depth: a pane-sessions file passes the guard only for a live handle, and then X1 answers the session's pane before claimants are settled, so the session is in that handle's row - as the one answering it, or as a claimant when another session answers it too (the ended-pane-file-claimed case) - and the live-handle rule keeps it first. A W1 answer that comes before X1 needs an unretired registry record, which keeps it as a signal of its own. The signal stays for the day the pane is answered another way." }
        @{ Name = "unretired-record-signal-ignored"
           Find = 'if (-not ($rt.state -eq "known" -and [bool]$rt.value)) { return "its registry record is not retired" }'
           Replace = '' }
        @{ Name = "open-run-signal-ignored"
           Find = 'foreach ($run in @(Get-HordeSessionRuns -C $C -Id $Id)) { if ($run.closed.state -ne "known" -or -not [bool]$run.closed.value) { return "it is in a run that is open, or may be" } }'
           Replace = '' }
        # What is served.
        @{ Name = "nothing-left-out"
           Find = 'if ($why -eq "") { [void]$kept.Add($s) } else {'
           Replace = '[void]$kept.Add($s); if ($false) {' }
        @{ Name = "ended-agent-not-noted"
           Find = 'agent = "$($s.fields[''agent''].answer.value)"; reason = $why }'
           Replace = 'agent = ""; reason = $why }' }
        @{ Name = "ended-sessions-not-noted"
           Find = '$doc["endedSessions"] = @($served.ended | ForEach-Object { [ordered]@{ sessionId = $_.sessionId; agent = $_.agent; reason = $_.reason } })'
           Replace = '$doc["endedSessions"] = @()' }
    )
}
