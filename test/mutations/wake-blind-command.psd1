# Mutations of the counts line of wake status in cli/commands/wake.ps1 (T-0116). Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-blind-command.psd1
# test\test-wake-blind.ps1 must fail for every one.
@{
    Target = "cli\commands\wake.ps1"
    Suite  = "test\test-wake-blind.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "status-shows-the-looks-as-the-blind-ones"
           Find = '", blind " + $counts.blindLooks'
           Replace = '", blind " + $counts.looks' }
        @{ Name = "status-shows-all-passes-as-the-blind-ones"
           Find = '" (" + $counts.blindPasses + " passes)'
           Replace = '" (" + $counts.passes + " passes)' }
        @{ Name = "status-shows-no-counts"
           Find = 'if ($null -ne $counts) {'
           Replace = 'if ($false) {' }
    )
}
