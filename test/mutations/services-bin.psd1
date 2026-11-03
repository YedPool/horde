# Mutations of cli/ServicesBin.ps1 (the installed CLI follows main). Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\services-bin.psd1
# Each breaks one promise of the follower; test\test-services-bin.ps1 must fail for every one.
@{
    Target = "cli\ServicesBin.ps1"
    Suite  = "test\test-services-bin.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "fetch-every-pass"
           Find = 'if (-not $NoFetch -and (Test-HordeServiceFetchDue -LastFetchAt $state.lastFetchAt -Now $Now -IntervalSeconds $interval)) {'
           Replace = 'if (-not $NoFetch) {' }
        @{ Name = "fetch-floor-dropped"
           Find = '$interval = [System.Math]::Max([int]$Policy.fetchIntervalSeconds, $script:HordeInstalledCliFetchFloorSeconds)'
           Replace = '$interval = [int]$Policy.fetchIntervalSeconds' }
        @{ Name = "fetch-time-not-kept"
           Find = '$state.lastFetchAt = $Now.ToUniversalTime(); $dirty = $true'
           Replace = '$dirty = $true' }
        @{ Name = "dirty-tree-moved"
           Find = 'if (-not $Read.clean) { return "dirty" }'
           Replace = 'if ($false) { return "dirty" }' }
        @{ Name = "other-branch-moved"
           Find = 'if ($Read.branch -cne $script:HordeInstalledCliBranch) { return "branch" }'
           Replace = 'if ($false) { return "branch" }' }
        @{ Name = "diverged-tree-moved"
           Find = 'if ($Read.ahead -gt 0 -and $Read.behind -gt 0) { return "diverged" }'
           Replace = 'if ($false) { return "diverged" }' }
        @{ Name = "ahead-tree-moved"
           Find = 'if ($Read.ahead -gt 0) { return "ahead" }'
           Replace = 'if ($false) { return "ahead" }' }
        @{ Name = "no-proof-it-loads"
           Find = 'try { $proof = @(& $Tools["Probe"] $Folder $Policy) | Select-Object -Last 1 }'
           Replace = 'try { $proof = [pscustomobject]@{ ok = $true; detail = "" } }' }
        @{ Name = "probe-words-wrong"
           Find = '-Words @("version")'
           Replace = '-Words @("versionx")' }
        @{ Name = "failed-update-not-put-back"
           Find = '$back = Invoke-HordeServiceGit -Checkout $Path -Arguments @("reset", "--keep", "--quiet", $Head) -TimeoutSeconds ([System.Math]::Max($GitSeconds, 60))'
           Replace = '$back = [pscustomobject]@{ ok = $true }' }
        @{ Name = "put-back-discards-edits"
           Find = '@("reset", "--keep", "--quiet", $Head)'
           Replace = '@("reset", "--hard", "--quiet", $Head)' }
        @{ Name = "put-back-target-wrong"
           Find = '@("reset", "--keep", "--quiet", $Head)'
           Replace = '@("reset", "--keep", "--quiet", "HEAD")' }
        @{ Name = "tip-not-tried-before-move"
           Find = '$pre = Test-HordeInstalledCliTip -Path $path -Tip $read.tip -Policy $Policy -Tools $Tools'
           Replace = '$pre = [pscustomobject]@{ ok = $true; exported = $true; detail = "" }' }
        @{ Name = "transient-failure-pins-revision"
           Find = '# A trouble of this moment (a lock, a timeout): nothing is pinned, the next pass tries again.'
           Replace = '$state.failedTip = $read.tip'
        }
        @{ Name = "stuck-not-remembered"
           Find = 'else { $code = "stuck"; $state.broken = $read.tip }'
           Replace = 'else { $code = "stuck" }' }
        @{ Name = "broken-clone-not-reprobed"
           Find = 'if ($state.broken -ceq $read.head) {'
           Replace = 'if ($false) {' }
        @{ Name = "status-calls-broken-current"
           Find = 'if ($kept.broken -ceq $read.head) { return (& $row "blocked" ('
           Replace = 'if ($false) { return (& $row "blocked" (' }
        @{ Name = "tried-revision-not-remembered"
           Find = '$state.triedTip = $read.tip; $dirty = $true'
           Replace = '$dirty = $true' }
        @{ Name = "new-bad-revision-not-told"
           Find = 'if (@("failed", "apply", "stuck") -ccontains $state.told) { $state.told = "" }'
           Replace = 'if ($false) { $state.told = "" }' }
        @{ Name = "failed-revision-retried"
           Find = 'elseif ($state.failedTip -ceq $read.tip) { $code = "failed-held" }'
           Replace = 'elseif ($false) { $code = "failed-held" }' }
        @{ Name = "told-every-pass"
           Find = 'if ($tellWhat -ne "" -and $state.told -cne $tellWhat) {'
           Replace = 'if ($tellWhat -ne "") {' }
        @{ Name = "untaken-tell-counted-as-told"
           Find = 'if ($null -ne $answer -and $null -ne $answer.PSObject.Properties["told"] -and @($answer.told | ForEach-Object { "" + $_ }) -ccontains $notice.id) {'
           Replace = 'if ($null -ne $answer) {' }
        @{ Name = "recovery-forgets-nothing"
           Find = 'if ($state.said -ne "" -or $state.told -ne "" -or $state.failedTip -ne "") {'
           Replace = 'if ($false) {' }
        @{ Name = "foreign-repository-acted-on"
           Find = 'if ($own -ne "") { return @("installed CLI: left alone - " + $own) }'
           Replace = 'if ($false) { return @("installed CLI: left alone - " + $own) }' }
        @{ Name = "switched-off-still-followed"
           Find = 'if ($Policy.followInstalledCli -ne $true) { return @() }'
           Replace = 'if ($false) { return @() }' }
        @{ Name = "status-behind-called-current"
           Find = 'return (& $row "behind" ("origin/main is " + $read.behind + " commit(s) ahead; the next pass moves it")'
           Replace = 'return (& $row "current" ("origin/main is " + $read.behind + " commit(s) ahead; the next pass moves it")' }
        @{ Name = "status-count-swapped"
           Find = '$ahead = [int]$Matches[1]; $behind = [int]$Matches[2]'
           Replace = '$ahead = [int]$Matches[2]; $behind = [int]$Matches[1]' }
        @{ Name = "default-folder-wrong"
           Find = '"UserProfile"), "bin", "horde")'
           Replace = '"UserProfile"), "bin", "horde2")' }
        @{ Name = "test-home-reaches-real-cli"
           Find = 'if ("" + $Policy.installedCliFolder -eq "" -and (Test-HordeServiceHomeIsATests -HordeHome $HordeHome -TempRoot $TempRoot)) {'
           Replace = 'if ($false) {' }
        @{ Name = "export-failure-pins-revision"
           Find = 'if (-not $pre.ok -and $pre.exported -and -not $pre.transient) {'
           Replace = 'if (-not $pre.ok) {' }
        @{ Name = "timed-out-probe-pins-revision"
           Find = 'if (-not $pre.ok -and $pre.exported -and -not $pre.transient) {'
           Replace = 'if (-not $pre.ok -and $pre.exported) {' }
        @{ Name = "export-failure-ignored-flag"
           Find = 'if (-not $pre.ok -and $pre.exported -and -not $pre.transient) {'
           Replace = 'if (-not $pre.ok -and -not $pre.transient) {' }
        @{ Name = "probe-transient-flag-dropped"
           Find = 'transient = [bool]($null -ne $proof -and $null -ne $proof.PSObject.Properties["transient"] -and $proof.transient -eq $true);'
           Replace = 'transient = $false;' }
        @{ Name = "slow-backstop-rolls-back"
           Find = 'if ($proof.ok -or $proof.transient) {'
           Replace = 'if ($proof.ok) {' }
        # T-0391 slice 6: an untold notice is tried again under ONE id, and the teller's own lines are the pass's.
        @{ Name = "untold-notice-gets-a-new-id-every-pass"
           Find = 'if ($state.pendingNotice -cnotmatch (''\A'' + [regex]::Escape($tellWhat) + '':[0-9a-f-]{36}\z'')) {'
           Replace = 'if ($true) {' }
        @{ Name = "teller-lines-dropped"
           Find = 'foreach ($tl in @($answer.lines)) { [void]$lines.Add("" + $tl) }'
           Replace = '$null = 0' }
    )
}
