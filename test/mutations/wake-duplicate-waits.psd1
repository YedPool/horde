# Mutations of core/Wake.ps1's saved duplicate episodes (the two waits kept with them, T-0116). Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-duplicate-waits.psd1
# The file is written and read by the wake run, so test\test-wake-run.ps1 (a watcher started again) must fail for every one.
@{
    Target = "core\Wake.ps1"
    Suite  = "test\test-wake-run.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "save-drops-the-not-wait"
           Find = 'if ($null -ne $Not -and $Not.ContainsKey("$id")) { $ep["notAt"]'
           Replace = 'if ($false) { $ep["notAt"]' }
        @{ Name = "save-drops-the-gone-wait"
           Find = 'if ($null -ne $Gone -and $Gone.ContainsKey("$id")) { $ep["goneAt"]'
           Replace = 'if ($false) { $ep["goneAt"]' }
        @{ Name = "read-drops-the-not-wait"
           Find = '@{ field = "notAt"; into = $notDup }'
           Replace = '@{ field = "notAt"; into = @{} }' }
        @{ Name = "read-drops-the-gone-wait"
           Find = '@{ field = "goneAt"; into = $gone }'
           Replace = '@{ field = "goneAt"; into = @{} }' }
        @{ Name = "mark-ignores-the-waits"
           Find = 'a = @($At.Keys | Sort-Object); g = $g; n = $n })'
           Replace = 'a = @($At.Keys | Sort-Object); g = @(); n = @() })' }
    )
}
