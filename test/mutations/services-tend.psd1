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
           Find = '        if ($left -le 0) { break }'
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
           Find = '-IgnoreIdle:$IgnoreIdle -ForceFetch:($ForceFetch -and $first) }'
           Replace = '-IgnoreIdle:$IgnoreIdle }' }
        @{ Name = "now-not-passed-on"
           Find = '-IgnoreIdle:$IgnoreIdle -ForceFetch:($ForceFetch -and $first) }'
           Replace = '-ForceFetch:($ForceFetch -and $first) }' }
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
        @{ Name = "job-not-with-person"
           Find = '-EveryMinutes 1 -TimeLimitMinutes 1 -WithPerson -Disabled:$Disabled'
           Replace = '-EveryMinutes 1 -TimeLimitMinutes 1 -Disabled:$Disabled' }
        @{ Name = "job-home-not-carried"
           Find = '-Arguments @("services", "tend") -Environment @{ HORDE_HOME = $home2 }'
           Replace = '-Arguments @("services", "tend") -Environment @{}' }
        @{ Name = "install-unverified"
           Find = 'if ($st.state -ne "known" -or -not $st.value.marked) { throw ("the " + $s.name + " did not keep the job "'
           Replace = 'if ($false) { throw ("the " + $s.name + " did not keep the job "' }
        @{ Name = "schedule-any-folder"
           Find = '    Assert-HordeJobName -Name $TaskName -Folder $Folder'
           Replace = '' }
        @{ Name = "roll-out-waiting-is-done"
           Find = '        [void]$out.Add([pscustomobject]@{ name = $def.name; reason = $one.reason })'
           Replace = '' }
        @{ Name = "roll-out-unseen-is-done"
           Find = 'if ($null -eq $one) { [void]$out.Add([pscustomobject]@{ name = $def.name; reason = "it was not looked at" }); continue }'
           Replace = 'if ($null -eq $one) { continue }' }
    )
}
