# Mutations of core/projection. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\projection.psd1
# One spec at a time. The spec sets HORDE_SKIP_REALITY=1 for its own runs (Environment below): the
# suite's reality check reads this machine's real stores and took past tools\Mutate.ps1's 900 s limit
# per run beside another run (2026-09-30), and a mutant must be caught by the fixture sections.
# Each breaks one rule the module exists for; test\test-projection.ps1 must fail for every one of them
# except those declared Expect = "survives", which name a gap the suite cannot reach.
#
# The mutant that writes a file acts only under a horde-projection-* fixture folder: the suite's last
# section reads this machine's real stores, and a mutant must never touch those.
@{
    Target = "core\Projection.ps1"
    Suite  = "test\test-projection.ps1"
    # Fixtures only, and stop at the first failed check: a caught mutant needs nothing more.
    # Only the sections that kill these mutants (test	est-projection.ps1 SECTIONS): every fixture section but the two that test core/HostPort.ps1 alone (instance-whole, one-writer).
    # Every mutant is still run; the whole list must come out as expected (PR #31, 2026-10-01).
    Environment = @{ HORDE_SKIP_REALITY = "1"; HORDE_FAIL_FAST = "1"; HORDE_SECTIONS = "view,precedence,pane,hostport,stored-handle,instance-proven,platform,judge,pane-guard,claim-guard,carry,cannot-tell,holes,runs,cardinality,parity,silent-winner,one-agent,layout,schema,writes" }
    # With the reality check skipped the suite passes with exit 3 (test\test-projection.ps1).
    PassCodes = @(3)
    Mutations = @(
        # The host: decision 2 and the instance rule.
        @{ Name = "no-instance-running-trusted"
           Find = 'elseif ($InstanceAnswer.value.running -eq 0) { $verify = New-HordeUnknown'
           Replace = 'elseif ($false) { $verify = New-HordeUnknown' }
        @{ Name = "ambiguous-instance-trusted"
           Find = 'elseif ($InstanceAnswer.value.ambiguous) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "other-instance-trusted"
           Find = 'if ($RecordInstance -ne "" -and "$($inst.id)" -ne "" -and $RecordInstance -cne "$($inst.id)") {'
           Replace = 'if ($false) {' }
        @{ Name = "written-before-instance-trusted"
           Find = 'if ($at -lt $inst.startedAt) {'
           Replace = 'if ($false) {' }
        @{ Name = "dead-handle-trusted"
           Find = 'if (-not $Context.live.ContainsKey($h)) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "host-port-ignored"
           Find = '$C.host = Get-HordeHostContext -HandlesAnswer (Read-HordeHostHandles -Port $HostPort -Platform $Platform)'
           Replace = '$C.host = Get-HordeHostContext -HandlesAnswer (Read-HordeHostHandles -Port (New-HordeUnavailableHostPort -Reason "mutant") -Platform $Platform)' }
        @{ Name = "any-host-trusts-stored-handles"
           Find = 'if (@($Context.wrote) -cnotcontains $Store) {'
           Replace = 'if ($false) {' }
        @{ Name = "running-session-assumed-in-this-instance"
           Find = 'if ($S.fields["pane"].answer.state -eq "known" -and $inst.state -eq "known" -and $inst.value.running -eq 1'
           Replace = 'if (($S.alive -or $S.fields["pane"].answer.state -eq "known") -and $inst.state -eq "known" -and $inst.value.running -eq 1' }
        # Decision 1: claimants.
        @{ Name = "claimed-handle-newest-wins"
           Find = 'if ($claims[$h].Count -lt 2) { continue }'
           Replace = 'continue' }
        # The pane-sessions guard.
        @{ Name = "session-in-two-handles-first-wins"
           Find = 'if ($g.Count -gt 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "hijack-ignored"
           Find = 'if ($holder.ContainsKey($f.handle) -and @($holder[$f.handle])[0] -ine $f.sessionId) {'
           Replace = 'if ($false) {' }
        @{ Name = "pane-files-read-under-two-instances"
           Find = 'if ($Context.instance.value.running -gt 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "pane-file-before-instance-trusted"
           Find = 'if ($f.writtenUtc -lt $Context.instance.value.startedAt) { continue }'
           Replace = '' }
        @{ Name = "pane-file-for-dead-handle-trusted"
           Find = 'if (-not $Context.live.ContainsKey($f.handle)) { continue }'
           Replace = '' }
        @{ Name = "missing-transcript-trusted"
           Find = 'if ($null -ne $S.x1 -and $S.x1.transcriptPath -ne "" -and (Test-Path -LiteralPath $S.x1.transcriptPath -PathType Leaf)) {'
           Replace = 'if ($null -ne $S.x1 -and $S.x1.transcriptPath -ne "") {' }
        # The registry's handle.
        @{ Name = "retired-record-holds-pane"
           Find = 'elseif ($S.w1Retired) { [void]$cands.Add('
           Replace = 'elseif ($false) { [void]$cands.Add(' }
        @{ Name = "running-session-reads-absent"
           Find = 'if ($S.alive) { $none = New-HordeUnknown'
           Replace = 'if ($false) { $none = New-HordeUnknown' }
        # Session identity.
        @{ Name = "environment-names-a-session"
           Find = 'foreach ($k in @($PaneVerdicts.bySession.Keys)) {'
           Replace = 'if ("$env:CLAUDE_CODE_SESSION_ID" -ne "") { $seen["$env:CLAUDE_CODE_SESSION_ID"] = "X2" }; foreach ($k in @($PaneVerdicts.bySession.Keys)) {' }
        # Runs.
        @{ Name = "two-spawning-open-runs-first-wins"
           Find = 'if ($openSpawned.Count -gt 1) {'
           Replace = 'if ($openSpawned.Count -gt 1) { return [pscustomobject]@{ answer = (New-HordeKnown -Value $openSpawned[0].run); ambiguous = @() } }; if ($false) {' }
        @{ Name = "closed-runs-first-wins"
           Find = 'if ($hits.Count -gt 1) { $ids = @($hits | ForEach-Object { $_.run.runId });'
           Replace = 'if ($hits.Count -gt 1) { return [pscustomobject]@{ answer = (New-HordeKnown -Value $hits[0].run); ambiguous = @() } }; if ($false) { $ids = @($hits | ForEach-Object { $_.run.runId });' }
        @{ Name = "roster-listing-twice-takes-first"
           Find = 'if ($e.Count -gt 1) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "pane-file-holder-last-wins"
           Find = 'if ($holder.ContainsKey($f.handle) -and $holder[$f.handle].Count -gt 1) { $unsure[$f.sessionId]'
           Replace = 'if ($false) { $unsure[$f.sessionId]' }
        # Work state and activity.
        @{ Name = "terminal-event-not-trusted"
           Find = 'if ($script:HordeTerminalEvents -ccontains $last) {'
           Replace = 'if ($false) {' }
        @{ Name = "unspawned-entry-not-pending"
           Find = 'if ($sp.state -eq "known" -and $sp.value -is [bool] -and -not $sp.value) {'
           Replace = 'if ($false) {' }
        @{ Name = "unknown-liveness-orphans"
           Find = '$goneNow = ((-not $S.alive) -and $pane.state -eq "absent" -and $fresh -eq $false)'
           Replace = '$goneNow = ((-not $S.alive) -and $pane.state -ne "known" -and $fresh -ne $true)' }
        @{ Name = "orphan-without-activity-check"
           Find = '$aliveNow = ($S.alive -or $pane.state -eq "known" -or $fresh -eq $true)'
           Replace = '$aliveNow = ($S.alive -or $pane.state -eq "known")' }
        @{ Name = "future-activity-trusted"
           Find = '$aged = Limit-HordeAge -Answer $a -TtlSeconds 1e15 -Now $C.now'
           Replace = '$aged = $a' }
        @{ Name = "first-activity-not-newest"
           Find = 'if ($null -eq $best -or $a.value -gt $best) {'
           Replace = 'if ($null -eq $best) {' }
        @{ Name = "no-activity-reads-now"
           Find = 'if ($null -eq $best) { return (New-HordeResolved -Answer (New-HordeUnknown -Reason "no activity source recorded anything for this session; that is unknown, never idle")) }'
           Replace = 'if ($null -eq $best) { return (New-HordeResolved -Answer (New-HordeKnown -Value $C.now -ObservedAt $C.now) -Store "W6" -Field "none") }' }
        @{ Name = "torn-event-log-read-shorter"
           Find = 'if ($ev.complete.state -ne "known") { return (New-HordeResolved -Answer $ev.complete) }'
           Replace = '' }
        # A skip proves none only over a whole store (review of PR #31, finding 1).
        @{ Name = "incomplete-registry-proves-no-record"
           Find = 'if ($S.regComplete.state -eq "known") { return (New-HordeCandidate -Store $Store -Field $Field -Skip "no registry record names this session") }'
           Replace = 'return (New-HordeCandidate -Store $Store -Field $Field -Skip "no registry record names this session")' }
        @{ Name = "unknown-run-proves-no-run"
           Find = 'if ($S.runState.state -eq "unknown") { return (New-HordeUnsure'
           Replace = 'if ($false) { return (New-HordeUnsure' }
        @{ Name = "cannot-tell-read-as-none"
           Find = 'return (New-HordeCandidate -Store $Store -Field $Field -Answer (New-HordeUnknown -Reason $Reason))'
           Replace = 'return (New-HordeCandidate -Store $Store -Field $Field -Skip $Reason)' }
        @{ Name = "unlistable-runs-prove-no-run"
           Find = 'if ($Runs.runsComplete.state -ne "known") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "unjudged-file-proves-no-handle"
           Find = 'elseif ($C.paneVerdicts.unsure.ContainsKey($S.id)) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "unread-command-line-proves-no-process"
           Find = 'elseif ($unreadLines.Count -gt 0) { $pidX5 = New-HordeUnsure'
           Replace = 'elseif ($false) { $pidX5 = New-HordeUnsure' }
        # The pane-file judge and the claim matcher (second review of PR #31, finding 8).
        @{ Name = "pane-files-judged-without-their-writer"
           Find = 'foreach ($st in @("X1", "W1")) { if (@($Context.wrote) -cnotcontains $st) {'
           Replace = 'foreach ($st in @("X1", "W1")) { if ($false) {' }
        @{ Name = "two-files-prove-no-handle"
           Find = '$unsure[$g[0].sessionId] = ("the session is named by the pane-sessions files of " + $g.Count + " handles, so none answers")'
           Replace = '$null = 0' }
        @{ Name = "contradicted-file-proves-no-handle"
           Find = '$unsure[$f.sessionId] = ("the pane-sessions file for handle " + $f.handle + " names this session, but a running session holds that handle, so where this one is is unknown")'
           Replace = '$null = 0' }
        @{ Name = "claim-matched-without-writing-claims"
           Find = 'if (@($C.host.wrote) -cnotcontains "W2") { return (New-HordeUnsure'
           Replace = 'if ($false) { return (New-HordeUnsure' }
        @{ Name = "claim-matched-beside-incomplete-registry"
           Find = 'if ($S.regComplete.state -ne "known") { return (New-HordeUnsure -Store "W2"'
           Replace = 'if ($false) { return (New-HordeUnsure -Store "W2"' }
        @{ Name = "unknown-handle-proves-no-claim"
           Find = 'if ($S.pane.answer.state -eq "unknown") { return (New-HordeUnsure -Store "W2"'
           Replace = 'if ($false) { return (New-HordeUnsure -Store "W2"' }
        # The engine's fields.
        @{ Name = "claim-read-beside-a-record"
           Find = 'if ($S.w1Unreadable -or $null -ne $S.w1) { return (New-HordeCandidate -Store "W2"'
           Replace = 'if ($S.w1Unreadable) { return (New-HordeCandidate -Store "W2"' }
        @{ Name = "claim-backstop-ignored"
           Find = 'if (-not (Test-HordeClaimPending -Claim ([pscustomobject]@{ spawnedAt = $spawned }) -Now $C.now)) {'
           Replace = 'if ($false) {' }
        @{ Name = "claim-cwd-ignored"
           Find = 'if ((ConvertTo-HordeClaudeProjectKey -Cwd "$($cc.Value)") -ine (ConvertTo-HordeClaudeProjectKey -Cwd $S.cwdForClaim)) {'
           Replace = 'if ($false) {' }
        @{ Name = "owner-founder-named-unowned"
           Find = '(New-HordeResolved -Answer (New-HordeKnown -Value "founder")'
           Replace = '(New-HordeResolved -Answer (New-HordeKnown -Value "(unowned)")' }
        @{ Name = "value-gate-dropped"
           Find = '$Resolved = Limit-HordeViewValue -Resolved $Resolved -Field $Name -ValueSchemas $C.valueSchemas -ViewSchema $C.viewSchema'
           Replace = '' }
        # Marks and provenance.
        @{ Name = "provisional-mark-dropped"
           Find = 'if ($null -ne $row -and $null -ne $row.PSObject.Properties["provisional"]) { $prov = "$($row.provisional)" }'
           Replace = '' }
        @{ Name = "source-dropped"
           Find = 'if ($Store -ne "" -and $Answer.state -ne "unknown") { $src ='
           Replace = 'if ($false) { $src =' }
        @{ Name = "layout-save-answers-resume"
           Find = '(New-HordeResolved -Answer (New-HordeUnknown -Reason "the resume command is computed by the AgentPort (step 5.1), not read; the layout saves and the report''s copy are shadows only"))'
           Replace = '(New-HordeResolved -Answer $(if ($shadow.Count -gt 0) { New-HordeKnown -Value $shadow[0].value } else { New-HordeUnknown -Reason "none" }) -Store "R1" -Field "process.argv")' }
        # The document rules.
        @{ Name = "rules-ignore-a-missing-value"
           Find = 'if ($a.state -eq "known" -and -not $hasValue) {'
           Replace = 'if ($false) {' }
        # Sources are parameters, and reading writes nothing.
        @{ Name = "injected-process-table-ignored"
           Find = 'identity = (Get-HordeIdentity -ClaudeDir $ClaudeDir -ProjectsDir $ProjectsDir -CodexDir $CodexDir -Processes $Processes'
           Replace = 'identity = (Get-HordeIdentity -ClaudeDir $ClaudeDir -ProjectsDir $ProjectsDir -CodexDir $CodexDir' }
        @{ Name = "plain-read-of-a-control-file"
           Find = 'try { return ((Read-HordeSharedText -Path $Record.source) | ConvertFrom-Json) } catch { return $null }'
           Replace = 'try { return ([System.IO.File]::ReadAllText($Record.source) | ConvertFrom-Json) } catch { return $null }' }
        @{ Name = "leaves-a-file-in-fixture-folders"
           Find = '$C.links = Get-HordeReportLinks -Runs $C.wf.runs'
           Replace = 'if ($WezfleetRoot -like "*horde-projection-*") { [System.IO.File]::WriteAllText((Join-Path $WezfleetRoot ([guid]::NewGuid().ToString("N") + ".seen")), "") }; $C.links = Get-HordeReportLinks -Runs $C.wf.runs' }
    )
}
