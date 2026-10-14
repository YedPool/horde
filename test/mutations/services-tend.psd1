# Mutations of cli/ServicesTend.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\services-tend.psd1
# Each breaks one promise of the supervisor's pass; test\test-services-tend.ps1 must fail for every one.
@{
    Target = "cli\ServicesTend.ps1"
    Suite  = "test\test-services-tend.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "fetch-every-pass"
           Find = 'if (-not $NoFetch -and ($ForceFetch -or (Test-HordeServiceFetchDue -LastFetchAt $s.lastFetchAt -Now $Now -IntervalSeconds $Policy.fetchIntervalSeconds))) {'
           Replace = 'if (-not $NoFetch) {' }
        @{ Name = "status-fetches"
           Find = 'if (-not $NoFetch -and ($ForceFetch -or (Test-HordeServiceFetchDue -LastFetchAt $s.lastFetchAt -Now $Now -IntervalSeconds $Policy.fetchIntervalSeconds))) {'
           Replace = 'if ($true) {' }
        @{ Name = "failed-fetch-retried-every-pass"
           Find = '            $s.lastFetchAt = $Now.ToUniversalTime()'
           Replace = '            if ($null -ne $fetched -and $fetched.ok -eq $true) { $s.lastFetchAt = $Now.ToUniversalTime() }' }
        @{ Name = "fetch-problem-not-kept"
           Find = '$s.fetchProblem = $(if ($null -ne $fetched -and $fetched.ok -eq $true) { "" } else {'
           Replace = '$s.fetchProblem = $(if ($true) { "" } else {' }
        @{ Name = "idle-asked-every-pass"
           Find = '        if ($waiting -and $Definition.follow.restart -ceq "idle") {'
           Replace = '        if ($Definition.follow.restart -ceq "idle") {' }
        @{ Name = "throwing-tool-ends-the-pass"
           Find = '    } catch { return [pscustomobject]@{ ok = $false; detail = (Protect-HordeServiceText ("the " + $Decision.step + " failed: " + $_.Exception.Message)); process = $null; revision = "" } }'
           Replace = '    } catch { throw }' }
        @{ Name = "start-without-process-accepted"
           Find = 'if ($Decision.step -ceq "start" -and $ok -and ($null -eq $process -or $process.startedAt -isnot [datetime])) {'
           Replace = 'if ($false) {' }
        @{ Name = "unreadable-state-is-new"
           Find = 'if ($kept.state -ceq "unknown") { [void]$lines.Add($name + ": LEFT ALONE'
           Replace = 'if ($false) { [void]$lines.Add($name + ": LEFT ALONE' }
        @{ Name = "quiet-pass-writes-state"
           Find = '        if ($text -cne $written) { Write-HordeServiceState -State $State -HordeHome $HordeHome; Set-Variable -Name written -Value $text -Scope 1 }'
           Replace = '        Write-HordeServiceState -State $State -HordeHome $HordeHome' }
        @{ Name = "wait-journaled-every-pass"
           Find = '            if ($worth) { $null = Write-HordeServiceJournal -HordeHome $HordeHome -Entries @(New-HordeServiceJournalEntry -At $now -Service $name -Action $d.action -Code $d.code -Reason $d.reason) }'
           Replace = '            $null = Write-HordeServiceJournal -HordeHome $HordeHome -Entries @(New-HordeServiceJournalEntry -At $now -Service $name -Action $d.action -Code $d.code -Reason $d.reason)' }
        @{ Name = "step-not-journaled"
           Find = '        $null = Write-HordeServiceJournal -HordeHome $HordeHome -Entries @(New-HordeServiceJournalEntry -At $after -Service $name -Action $d.action -Step $d.step'
           Replace = '        $null = @(New-HordeServiceJournalEntry -At $after -Service $name -Action $d.action -Step $d.step' }
        @{ Name = "failed-step-retried-at-once"
           Find = '        if (-not $outcome.ok -or $steps -ge $script:HordeServiceStepsMost) { break }'
           Replace = '        if ($steps -ge $script:HordeServiceStepsMost) { break }' }
        @{ Name = "budget-ignored"
           Find = '        if ((Invoke-HordeServiceTool -Tools $Tools -Name "Now") -ge $Deadline) { break }'
           Replace = '' }
        @{ Name = "notice-not-kept"
           Find = 'if ($d.notify -ne "") { $s = Add-HordeServiceNotice -State $s -Decision $d'
           Replace = 'if ($false) { $s = Add-HordeServiceNotice -State $s -Decision $d' }
        @{ Name = "told-when-switched-off"
           Find = '    if ($Policy.tellWarchief -ne $true) { return @('
           Replace = '    if ($false) { return @(' }
        @{ Name = "untold-notice-forgotten"
           Find = '        $kept = @($s.notices | Where-Object { $told -cnotcontains $_.id })'
           Replace = '        $kept = @()' }
        @{ Name = "told-notice-kept"
           Find = '        if ($kept.Count -ne @($s.notices).Count) { $s.notices = $kept; Write-HordeServiceState -State $s -HordeHome $HordeHome }'
           Replace = '' }
        @{ Name = "throwing-teller-ends-the-pass"
           Find = '    catch { return @("" + $waiting.Count + " notice(s) wait untold: " + (Protect-HordeServiceText $_.Exception.Message) + "; they are tried again next pass") }'
           Replace = '    catch { throw }' }
        @{ Name = "refused-definitions-tended"
           Find = '    if ($defined.state -ceq "refused") { return (& $none ($defined.findings -join " ")) }'
           Replace = '' }
        @{ Name = "refused-settings-ignored"
           Find = '    if ($settings.state -ceq "refused") { return (& $none ($settings.findings -join " ")) }'
           Replace = '    if ($settings.state -ceq "refused") { $settings = Get-HordeModuleSettings -Declaration (Get-HordeServiceSettingsDeclaration) -HordeHome ([System.IO.Path]::GetTempPath()) }' }
        @{ Name = "unknown-service-name-ignored"
           Find = 'foreach ($n in @($Only)) { if (@($chosen | Where-Object { $_.name -ceq $n }).Count -eq 0) { return (& $none ('
           Replace = 'foreach ($n in @($Only)) { if ($false) { return (& $none (' }
        @{ Name = "only-tends-all"
           Find = '        $chosen = @($chosen | Where-Object { @($Only) -ccontains $_.name })'
           Replace = '' }
        @{ Name = "no-lock"
           Find = '    if ($null -eq $lock) { return (& $none $(if ($LockWaitSeconds -gt 0) {'
           Replace = '    if ($false) { return (& $none $(if ($LockWaitSeconds -gt 0) {' }
        @{ Name = "one-failure-ends-the-pass"
           Find = '                    $one = [pscustomobject]@{ name = $def.name; lines = @($def.name + ": THE PASS FAILED ON IT - " + $why)'
           Replace = '                    throw; $one = [pscustomobject]@{ name = $def.name; lines = @($def.name + ": THE PASS FAILED ON IT - " + $why)'
           Expect = "survives"
           Reason = "no tool of a pass can throw past Invoke-HordeServiceStep and the observation, which turn every throw into an outcome or an unknown; this catch is the last line behind them, and no suite input reaches it" }
        @{ Name = "pass-count-stuck"
           Find = '        if ($before.state -ceq "known") { $pass = [long]$before.value.pass + 1 }'
           Replace = '' }
        @{ Name = "roll-out-does-not-wait"
           Find = 'if ($SettleSeconds -le 0 -or $moving.Count -eq 0 -or (Invoke-HordeServiceTool -Tools $Tools -Name "Now") -ge $settleBy) { break }'
           Replace = 'if ($true) { break }' }
        @{ Name = "force-fetch-ignored"
           Find = '-IgnoreIdle:$IgnoreIdle -ForceFetch:($ForceFetch -and $first) -SupervisorGapSeconds'
           Replace = '-IgnoreIdle:$IgnoreIdle -SupervisorGapSeconds' }
        @{ Name = "now-not-passed-on"
           Find = '-IgnoreIdle:$IgnoreIdle -ForceFetch:($ForceFetch -and $first) -SupervisorGapSeconds'
           Replace = '-ForceFetch:($ForceFetch -and $first) -SupervisorGapSeconds' }
        @{ Name = "stale-supervisor-reads-as-running"
           Find = '        if ($verdict.value.fresh) { $supervisor.state = "running";'
           Replace = '        if ($true) { $supervisor.state = "running";' }
        @{ Name = "never-run-reads-as-running"
           Find = 'if ($verdict.state -ceq "absent") { $supervisor.state = "never";'
           Replace = 'if ($verdict.state -ceq "absent") { $supervisor.state = "running";' }
        @{ Name = "status-times-in-powershell-form"
           Find = 'if ($null -ne $_.lastAction) { $row["lastAction"] = [ordered]@{ at = (ConvertTo-HordeHeartbeatTimeText -At $_.lastAction.at);'
           Replace = 'if ($null -ne $_.lastAction) { $row["lastAction"] = [ordered]@{ at = $_.lastAction.at;' }
        @{ Name = "refused-definitions-not-said"
           Find = '[void]$lines.Add("definitions: NO SERVICE IS SUPERVISED until that file is mended") }'
           Replace = '}' }
        @{ Name = "job-not-at-start-up"
           Find = '{ @{ AtStartup = $true } }'
           Replace = '{ @{} }' }
        @{ Name = "job-home-not-carried"
           Find = '    $environment = @{ HORDE_HOME = $home2 }'
           Replace = '    $environment = @{}' }
        @{ Name = "install-unverified"
           Find = 'if ($st.state -ne "known" -or -not $st.value.marked) { throw ("the " + $s.name + " did not keep the job "'
           Replace = 'if ($false) { throw ("the " + $s.name + " did not keep the job "' }
        @{ Name = "schedule-any-folder"
           Find = '    foreach ($n in @($names.person, $names.startup)) { Assert-HordeJobName -Name $n -Folder $Folder }'
           Replace = '' }
        @{ Name = "roll-out-waiting-is-done"
           Find = '        [void]$out.Add([pscustomobject]@{ name = $def.name; reason = $one.reason })'
           Replace = '' }
        @{ Name = "roll-out-unseen-is-done"
           Find = 'if ($null -eq $one) { [void]$out.Add([pscustomobject]@{ name = $def.name; reason = "it was not looked at" }); continue }'
           Replace = 'if ($null -eq $one) { continue }' }
        # --- safety review of the first build ---
        @{ Name = "supervisors-own-gap-not-read"
           Find = 'if ($own.state -ceq "known" -and -not $own.value.fresh) { $gapSeconds ='
           Replace = 'if ($false) { $gapSeconds =' }
        @{ Name = "full-look-never-asked-for"
           Find = '[bool]($null -ne $s.moving)) }'
           Replace = '$false) }' }
        @{ Name = "exit-code-never-asked"
           Find = 'if ($null -ne $s.started -and $started.state -ceq "absent" -and $null -ne $Tools["ExitCode"] -and @($Definition.stop.deliberateExitCodes).Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "held-mark-written-after-the-stop"
           Find = '$s.held = $true; $s.heldWhy = "a person stopped it with horde services stop"; Write-HordeServiceState -State $s -HordeHome $HordeHome'
           Replace = '$s.held = $true; $s.heldWhy = "a person stopped it with horde services stop"' }
        @{ Name = "stubborn-service-left-running"
           Find = 'try { $ended = Invoke-HordeServiceTool -Tools $Tools -Name "Kill" -With @(, $live.process) }'
           Replace = 'try { $ended = [pscustomobject]@{ ok = $false; detail = "not ended" } }' }
        @{ Name = "let-go-stays-held"
           Find = '            $s.held = $false; $s.heldWhy = ""; $s.launchingAt = $null;'
           Replace = '            $s.heldWhy = ""; $s.launchingAt = $null;' }
        @{ Name = "let-go-keeps-the-telling"
           Find = '$s.told = [string[]]@(@($s.told) | Where-Object { @("ended-itself", "start-unrecorded") -cnotcontains $_ })'
           Replace = '' }
        @{ Name = "unreadable-state-held-anyway"
           Find = 'if ($kept.state -ceq "unknown") { return (& $answer ("nothing was done: " + $kept.reason)) }'
           Replace = '' }
        @{ Name = "pass-ended-at-one-minute"
           Find = '-EveryMinutes 1 -TimeLimitMinutes 5 -MayOutlastInterval @where'
           Replace = '-EveryMinutes 1 -TimeLimitMinutes 1 @where' }
        @{ Name = "held-is-not-done-for-a-roll-out"
           Find = 'if (@("current", "updated", "disabled", "held") -ccontains $one.code) { continue }'
           Replace = 'if (@("current", "updated", "disabled") -ccontains $one.code) { continue }' }
        # --- the supervisor runs whether or not anyone is signed in (2026-10-14) ---
        @{ Name = "job-back-in-the-persons-session"
           Find = '{ @{ AtStartup = $true } }'
           Replace = '{ @{ WithPerson = $true } }' }
        @{ Name = "desktop-never-asked"
           Find = '    if ($null -ne $needs -and $needs.Value -eq $true) {'
           Replace = '    if ($false) {' }
        @{ Name = "desktop-asked-of-every-service"
           Find = '    if ($null -ne $needs -and $needs.Value -eq $true) {'
           Replace = '    if ($true) {' }
        @{ Name = "desktop-not-handed-to-the-decision"
           Find = '-ExitCode $exit -Desktop $desktop -PersonPass $personPass); state = $s }'
           Replace = '-ExitCode $exit -PersonPass $personPass); state = $s }' }
        @{ Name = "install-says-the-persons-session"
           Find = 'says = "at start-up and every minute, whether or not anyone is signed in, with no password stored" }'
           Replace = 'says = "every minute, in the person''s own session" }' }
            # --- review of PR 249 ---
        @{ Name = "person-job-is-a-start-up-job"
           Find = '-Name $b.name -Folder $Folder -Kind $b.kind -PersonJob $names.person -Disabled:$Disabled'
           Replace = '-Name $b.name -Folder $Folder -Kind "startup" -PersonJob $names.person -Disabled:$Disabled' }
        @{ Name = "person-job-installed-first"
           Find = '            foreach ($b in @($both)) {'
           Replace = '            foreach ($b in @(@($both)[1, 0])) {' }
        @{ Name = "unschedule-leaves-one"
           Find = '$gone = & $s.remove $b.name $Folder'
           Replace = '$gone = $(if ($b.kind -ceq "person") { & $s.remove $b.name $Folder } else { $false })' }
        @{ Name = "missing-job-not-said"
           Find = 'elseif ($none -eq 1) { [void]$lines.Add("ONE OF THE TWO JOBS IS MISSING'
           Replace = 'elseif ($false) { [void]$lines.Add("ONE OF THE TWO JOBS IS MISSING' }
        @{ Name = "person-job-not-at-sign-in"
           Find = '@{ WithPerson = $true; AtLogon = $true }'
           Replace = '@{ WithPerson = $true }' }
        @{ Name = "install-names-no-account"
           Find = '                $as = $(if ($null -ne $st.value.PSObject.Properties["runsAs"]'
           Replace = '                $as = ""; $null = $(if ($null -ne $st.value.PSObject.Properties["runsAs"]' }
            # --- review of PR 249, round 2 ---
        @{ Name = "person-job-not-named-to-start-up"
           Find = 'if ($Kind -ceq "startup" -and $PersonJob -ne "") {'
           Replace = 'if ($false) {' }
        @{ Name = "person-job-never-asked"
           Find = 'if ($desktop.state -ceq "unknown" -and $null -ne $needs -and $needs.Value -eq $true -and $null -ne $Tools["PersonPass"]) {'
           Replace = 'if ($false) {' }
        @{ Name = "person-job-answer-dropped"
           Find = '-Desktop $desktop -PersonPass $personPass); state'
           Replace = '-Desktop $desktop); state' }
        @{ Name = "disabled-person-job-counts"
           Find = 'if ($st.state -ceq "known" -and $st.value.marked -eq $true -and $st.value.enabled -eq $true) { return (New-HordeKnown -Value $true) }'
           Replace = 'if ($st.state -ceq "known" -and $st.value.marked -eq $true) { return (New-HordeKnown -Value $true) }' }
        @{ Name = "unschedule-stops-at-first-failure"
           Find = '} catch { $failed++; [void]$lines.Add("COULD NOT REMOVE "'
           Replace = '} catch { throw; $failed++; [void]$lines.Add("COULD NOT REMOVE "' }
        @{ Name = "unschedule-failure-swallowed"
           Find = '            if ($failed -gt 0) { throw ($lines -join "; ") }'
           Replace = '' }
    )
}
