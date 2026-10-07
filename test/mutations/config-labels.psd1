# Mutations of the labels value kind (remote.deliverTo, R21 slice 4). Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\config-labels.psd1
# Each mutation drops one limit of a labels value in core/EngineConfig.ps1's Get-HordeConfigValueProblem,
# and test\test-node-deliverto.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "core\EngineConfig.ps1"
    Suite  = "test\test-node-deliverto.ps1"
    Mutations = @(
        @{ Name = "labels-count-unbounded"
           Find = 'if ($items.Count -gt $lk.maxEntries) {'
           Replace = 'if ($false) {' }
        @{ Name = "labels-cap-raised"
           Find = "labels = @{ entry = '\A[A-Z]{1,2}([1-9][0-9]{0,3})?\z'; maxEntries = 64;"
           Replace = "labels = @{ entry = '\A[A-Z]{1,2}([1-9][0-9]{0,3})?\z'; maxEntries = 65;" }
        @{ Name = "labels-empty-entry-accepted"
           Find = 'if ($it -eq "") { return ("it has an empty entry between commas") }'
           Replace = 'if ($false) { return ("it has an empty entry between commas") }' }
        @{ Name = "labels-length-unchecked"
           Find = 'if ($it.Length -gt $lk.maxChars) {'
           Replace = 'if ($false) {' }
        @{ Name = "labels-pattern-unchecked"
           Find = 'if ($it -cnotmatch $lk.entry) {'
           Replace = 'if ($false) {' }
        @{ Name = "labels-pattern-ignores-case"
           Find = 'if ($it -cnotmatch $lk.entry) {'
           Replace = 'if ($it -inotmatch $lk.entry) {' }
        @{ Name = "labels-duplicates-accepted"
           Find = 'if (-not $seen.Add($it)) {'
           Replace = 'if ($false -and -not $seen.Add($it)) {' }
    )
}
