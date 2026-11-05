# Mutations of core/NightlyNet.ps1's restart-retry deciding and the watcher's retry reading (T-0397). Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\nightly-retry.psd1
# Each breaks one rule of the retry; test\test-nightly-retry.ps1 must fail a named check for every one of them.
@{
    Target = "core\NightlyNet.ps1"
    Suite  = "test\test-nightly-retry.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "retry-outside-the-window"
           Find = '    if (-not (Test-HordeNightlyWindow -Now $Now)) { $cond = "outside the night window" }'
           Replace = '    if ($false) { $cond = "outside the night window" }' }
        @{ Name = "retry-with-too-little-time"
           Find = '    elseif ($left -lt $MinMinutes) { $cond = "too little time" }'
           Replace = '    elseif ($false) { $cond = "too little time" }' }
        @{ Name = "time-limit-off-by-one-minute"
           Find = '    elseif ($left -lt $MinMinutes) { $cond = "too little time" }'
           Replace = '    elseif ($left -le $MinMinutes) { $cond = "too little time" }' }
        @{ Name = "retry-despite-a-report"
           Find = '    elseif ($names -contains ($night + ".txt")) { $cond = "report exists" }'
           Replace = '    elseif ($false) { $cond = "report exists" }' }
        @{ Name = "retry-despite-a-busy-file"
           Find = '$names -contains ($night + "-busy.txt") -or'
           Replace = '$false -or' }
        @{ Name = "retry-despite-a-failed-file"
           Find = '    elseif ($names -contains ($night + "-failed.txt") -or'
           Replace = '    elseif ($false -or' }
        @{ Name = "retry-despite-a-marker"
           Find = '    elseif ($MarkerExists) { $cond = "already retried" }'
           Replace = '    elseif ($false) { $cond = "already retried" }' }
        @{ Name = "retry-while-the-net-runs"
           Find = '    elseif ($NetAlive) { $cond = "net is running" }'
           Replace = '    elseif ($false) { $cond = "net is running" }' }
        @{ Name = "retry-night-label-is-the-calendar-day"
           Find = '    $night = Get-HordeNightlyNightLabel -Time $Now'
           Replace = '    $night = $Now.ToString("yyyy-MM-dd")' }
        @{ Name = "retry-line-of-any-night-counts"
           Find = '("(?m)\bnightly retry " + [regex]::Escape($Date) + ": ")'
           Replace = '("(?m)\bnightly retry ")' }
        @{ Name = "phone-silent-about-the-retry"
           Find = '$Verdict.PSObject.Properties["retried"] -and $Verdict.retried) {'
           Replace = '$false) {' }
    )
}
