# Mutations of core/Schedule.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\schedule.psd1
# Each breaks one rule of the job's definition; test\test-metrics-schedule.ps1 must fail for every one.
@{
    Target = "core\Schedule.ps1"
    Suite  = "test\test-metrics-schedule.ps1"
    Mutations = @(
        @{ Name = "home-baked-in"
           Find = '-Arguments @("metrics", "collect") -HordeHome $home2'
           Replace = '-Arguments @("metrics", "collect") -Environment @{ HORDE_HOME = $home2 } -HordeHome $home2' }
        @{ Name = "marker-not-written"
           Find = '$text = $Description + "`n" + $script:HordeJobMarker + "`nhorde-home: " + $HordeHome'
           Replace = '$text = $Description + "`nhorde-home: " + $HordeHome' }
        @{ Name = "marker-read-loosely"
           Find = 'marked = ($lines -ccontains $script:HordeJobMarker)'
           Replace = 'marked = $true' }
        @{ Name = "run-may-outlast-interval"
           Find = ' -or ($TimeLimitMinutes -gt $EveryMinutes -and -not $MayOutlastInterval)) {'
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
        @{ Name = "dash-argument-allowed"
           Find = 'foreach ($a in @($Arguments)) { if ("$a".Length -gt 0 -and $dashes -contains "$a"[0]) { throw'
           Replace = 'foreach ($a in @()) { if ("$a".Length -gt 0 -and $dashes -contains "$a"[0]) { throw' }
        @{ Name = "unicode-dash-allowed"
           Find = '$dashes = @([char]0x2D, [char]0x2010, [char]0x2011, [char]0x2012, [char]0x2013, [char]0x2014, [char]0x2015, [char]0x2212)'
           Replace = '$dashes = @([char]0x2D)' }
        @{ Name = "unavailable-scheduler-used"
           Find = '        if ($ok) { return (New-HordeKnown -Value $s) }'
           Replace = '        return (New-HordeKnown -Value $s)' }
        @{ Name = "with-person-not-carried"
           Find = 'withPerson = [bool]$WithPerson;'
           Replace = 'withPerson = $false;' }
        @{ Name = "any-job-may-outlast-its-interval"
           Find = '($TimeLimitMinutes -gt $EveryMinutes -and -not $MayOutlastInterval)'
           Replace = '($false)' }
        # --- the supervisor runs whether or not anyone is signed in (2026-10-14) ---
        @{ Name = "at-startup-not-carried"
           Find = 'atStartup = [bool]$AtStartup;'
           Replace = 'atStartup = $false;' }
        @{ Name = "start-up-job-in-the-persons-session"
           Find = 'if ($AtStartup -and $WithPerson) { throw'
           Replace = 'if ($false) { throw' }
            # --- review of PR 249 ---
        @{ Name = "at-logon-not-carried"
           Find = 'atLogon = [bool]$AtLogon }'
           Replace = 'atLogon = $false }' }
    )
}
