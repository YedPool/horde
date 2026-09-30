# Mutations of core/projection. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\projection.psd1
# with HORDE_SKIP_REALITY=1 set, one spec at a time. The suite's reality check reads this machine's
# real stores and took past tools\Mutate.ps1's 900 s limit per run beside another run (2026-09-30);
# a mutant must be caught by the fixture sections, and the skip is printed on every run.
# Each breaks one rule the module exists for; test\test-projection.ps1 must fail for every one of them
# except those declared Expect = "survives", which name a gap the suite cannot reach.
#
# The mutant that writes a file acts only under a horde-projection-* fixture folder: the suite's last
# section reads this machine's real stores, and a mutant must never touch those.
@{
    Target = "core\Projection.ps1"
    Suite  = "test\test-projection.ps1"
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
           Find = '$C.host = Get-HordeHostContext -HandlesAnswer (Read-HordeHostHandles -Port $HostPort)'
           Replace = '$C.host = Get-HordeHostContext -HandlesAnswer (Read-HordeHostHandles -Port (New-HordeUnavailableHostPort -Reason "mutant"))' }
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
           Find = 'if ($holder.ContainsKey($f.handle) -and $holder[$f.handle] -ine $f.sessionId) {'
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
           Find = 'if ($hits.Count -gt 1) {'
           Replace = 'if ($hits.Count -gt 1) { return [pscustomobject]@{ answer = (New-HordeKnown -Value $hits[0].run); ambiguous = @() } }; if ($false) {' }
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
