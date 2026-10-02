# Mutations of core/Schedule.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\schedule.psd1
# Each breaks one rule of the job's definition; test\test-metrics-schedule.ps1 must fail for every one.
@{
    Target = "core\Schedule.ps1"
    Suite  = "test\test-metrics-schedule.ps1"
    Mutations = @(
        @{ Name = "home-not-carried"
           Find = '-Arguments @("metrics", "collect") -Environment @{ HORDE_HOME = $home2 }'
           Replace = '-Arguments @("metrics", "collect") -Environment @{}' }
        @{ Name = "marker-not-written"
           Find = '$text = $Description + "`n" + $script:HordeJobMarker + "`nhorde-home: " + $HordeHome'
           Replace = '$text = $Description + "`nhorde-home: " + $HordeHome' }
        @{ Name = "marker-read-loosely"
           Find = 'marked = ($lines -ccontains $script:HordeJobMarker)'
           Replace = 'marked = $true' }
        @{ Name = "run-may-outlast-interval"
           Find = ' -or $TimeLimitMinutes -gt $EveryMinutes) {'
           Replace = ') {' }
        @{ Name = "job-name-unchecked"
           Find = "    if (`$Name -notmatch '\A[A-Za-z0-9][A-Za-z0-9 ._-]{0,100}\z') {"
           Replace = '    if ($false) {' }
        @{ Name = "any-folder-allowed"
           Find = '    if ($script:HordeJobFolders -cnotcontains $Folder) {'
           Replace = '    if ($false) {' }
        @{ Name = "env-name-unchecked"
           Find = 'if ("$k" -cnotmatch ''\A[A-Z_][A-Z0-9_]*\z'') {'
           Replace = 'if ($false) {' }
        @{ Name = "unavailable-scheduler-used"
           Find = '        if ($ok) { return (New-HordeKnown -Value $s) }'
           Replace = '        return (New-HordeKnown -Value $s)' }
    )
}
