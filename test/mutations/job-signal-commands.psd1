# Mutations of the PowerShell half shared by horde job and horde signal (fleet-db/Jobs.ps1): the home, the empty and quoted values, the exit
# message. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\job-signal-commands.psd1
# test\test-job-signal.ps1 must fail a check for every one. Every find string occurs once.
@{
    Target = "fleet-db\Jobs.ps1"
    Suite  = "test\test-job-signal.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "default-home-accepted"
           Find = 'if ($resolved.source -eq "default") { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "empty-value-passed-on"
           Find = 'if ($value.Trim() -eq "") { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "double-quote-passed-on"
           Find = 'if ($value.Contains(''"'')) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "bare-flags-dropped"
           Find = 'foreach ($s in $Switches) { $nodeArgs += $s }'
           Replace = 'foreach ($s in @()) { $nodeArgs += $s }' }
        @{ Name = "trailing-backslash-not-doubled"
           Find = '$_ -replace ''(\\+)$'', ''$1$1'''
           Replace = '$_' }
        @{ Name = "node-failure-not-reported"
           Find = 'if ($code -ne 0) { throw ('
           Replace = 'if ($false) { throw (' }
        @{ Name = "node-exit-code-not-named"
           Find = '" stopped with exit code " + $code'
           Replace = '" stopped"' }
    )
}
