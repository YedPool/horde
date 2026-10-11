# Mutations of where the wezfleet messenger finds the fleet: Set-HordeWezfleetMessengerRoot, then its
# setting root, then the checkout the wezfleet command on PATH runs. Run:
#   powershell -File tools\Mutate.ps1 -Spec messengers\wezfleet\test\mutations\root.psd1
# Each loosens one rule of messengers/wezfleet/Messenger.ps1, and test-wezfleet-messenger-root.ps1 must
# fail for every one. Every find string occurs exactly once, on one line.
@{
    Target = "messengers\wezfleet\Messenger.ps1"
    Suite  = "messengers\wezfleet\test\test-wezfleet-messenger-root.ps1"
    Mutations = @(
        @{ Name = "set-root-loses"
           Find = 'if ("$script:HordeWezfleetMessengerRoot" -ne "") {'
           Replace = 'if ($false) {' }
        @{ Name = "setting-ignored"
           Find = 'if ("$($s.values.root)" -ne "") {'
           Replace = 'if ($false) {' }
        @{ Name = "refused-settings-fall-back-to-path"
           Find = 'if ($s.state -cne "defaults" -and $s.state -cne "read") {'
           Replace = 'if ($false) {' }
        @{ Name = "path-never-searched"
           Find = 'return (Find-HordeWezfleetMessengerOnPath -SettingsPath $s.path)'
           Replace = 'return (New-HordeWezfleetMessengerChoice -Reason "no folder")' }
        @{ Name = "nothing-on-path-unsaid"
           Find = 'if ($null -eq $cmd) {'
           Replace = 'if ($false) {' }
        @{ Name = "ps1-on-path-not-followed"
           Find = 'if ($ext -ceq ".ps1") {'
           Replace = 'if ($false) {' }
        @{ Name = "shim-folder-dropped"
           Find = '$root = $(if ($rel -eq "") { $dir } else { $dir.TrimEnd(''\'') + ''\'' + $rel })'
           Replace = '$root = $dir' }
        @{ Name = "shim-folder-resolved"
           Find = '$root = $(if ($rel -eq "") { $dir } else { $dir.TrimEnd(''\'') + ''\'' + $rel })'
           Replace = '$root = [System.IO.Path]::GetFullPath($(if ($rel -eq "") { $dir } else { $dir.TrimEnd(''\'') + ''\'' + $rel }))' }
        @{ Name = "shim-naming-two-accepted"
           Find = 'if ($named.Count -ne 1) {'
           Replace = 'if ($named.Count -lt 1) {' }
        @{ Name = "how-chosen-unsaid"
           Find = 'reason = ($why + " (the folder was " + $choice.how + ")")'
           Replace = 'reason = $why' }
    )
}
