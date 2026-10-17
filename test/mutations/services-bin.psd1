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
           Find = 'if ($Read.ahead -gt 0) { return "diverged" }'
           Replace = 'if ($false) { return "diverged" }' }
        @{ Name = "no-proof-it-loads"
           Find = 'try { $proof = @(& $Tools["Probe"] $path $Policy) | Select-Object -Last 1 }'
           Replace = 'try { $proof = [pscustomobject]@{ ok = $true; detail = "" } }' }
        @{ Name = "failed-update-not-put-back"
           Find = '$back = Invoke-HordeServiceGit -Checkout $path -Arguments @("reset", "--hard", "--quiet", $read.head) -TimeoutSeconds ([System.Math]::Max($gitSeconds, 60))'
           Replace = '$back = [pscustomobject]@{ ok = $true }' }
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
           Find = 'return (& $row "behind" ('
           Replace = 'return (& $row "current" (' }
        @{ Name = "status-count-swapped"
           Find = '$ahead = [int]$Matches[1]; $behind = [int]$Matches[2]'
           Replace = '$ahead = [int]$Matches[2]; $behind = [int]$Matches[1]' }
        @{ Name = "default-folder-wrong"
           Find = '"UserProfile"), "bin", "horde")'
           Replace = '"UserProfile"), "bin", "horde2")' }
        @{ Name = "test-home-reaches-real-cli"
           Find = 'if ("" + $Policy.installedCliFolder -eq "" -and (Test-HordeServiceHomeIsATests -HordeHome $HordeHome -TempRoot $TempRoot)) {'
           Replace = 'if ($false) {' }
    )
}
