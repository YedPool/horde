# Mutations of cli/SetupStore.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\setup-store.psd1
# Each breaks one rule of CONTRIBUTING 16 (no Microsoft Store package); test\test-setup-store.ps1 must fail for every one.
@{
    Target = "cli\SetupStore.ps1"
    Suite  = "test\test-setup-store.ps1"
    Mutations = @(
        @{ Name = "any-policy-value-counts-as-off"
           Find = 'if ($null -ne $Policy -and [int]$Policy -eq 2) {'
           Replace = 'if ($null -ne $Policy) {' }
        @{ Name = "policy-not-elevated-says-nothing"
           Find = '$next = $(if ($Elevated) { "" } else { "needs one elevated run of horde setup (a PowerShell window opened as administrator); it will set '
           Replace = '$next = $(if ($true) { "" } else { "needs one elevated run of horde setup (a PowerShell window opened as administrator); it will set ' }
        @{ Name = "store-path-matches-any-windowsapps-word"
           Find = "'(?i)\\WindowsApps\\'"
           Replace = "'(?i)WindowsApps'" }
        @{ Name = "store-copy-counts-as-installed"
           Find = 'if ($MsiVersion -ne "") {'
           Replace = 'if ($MsiVersion -ne "" -or $store) {' }
        @{ Name = "hash-never-compared"
           Find = 'if ($got -cne $inst.sha256) {'
           Replace = 'if ($false) {' }
        @{ Name = "http-address-accepted"
           Find = '-cnotlike "https://*") {'
           Replace = '-cnotlike "*://*") {' }
        @{ Name = "restart-wanted-is-failure"
           Find = 'if ($code -ne 0 -and $code -ne 3010) {'
           Replace = 'if ($code -ne 0) {' }
        @{ Name = "version-never-verified"
           Find = 'if ($ver -eq "") {'
           Replace = 'if ($false) {' }
    )
}
