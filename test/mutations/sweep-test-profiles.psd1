# Mutations of the post-merge net's test-profile sweep (tools/SweepTestProfiles.ps1): the must-fail
# twins. Each breaks one rule that keeps the sweep from deleting the wrong thing.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\sweep-test-profiles.psd1
# test\test-sweep-test-profiles.ps1 must fail for each.
@{
    Target = "tools\SweepTestProfiles.ps1"
    Suite  = "test\test-sweep-test-profiles.ps1"
    Mutations = @(
        @{ Name = "loose-prefix-match"
           Find = "'\Ahorde-cf-accounts-[0-9a-f]{12}\z',"
           Replace = "'\Ahorde-cf-accounts-'," }
        @{ Name = "end-anchor-dropped"
           Find = "'\Ahorde-cf-accounts-[0-9a-f]{12}\z',"
           Replace = "'\Ahorde-cf-accounts-[0-9a-f]{12}'," }
        @{ Name = "start-anchor-dropped"
           Find = "'\Ahorde-browser-[0-9a-f]{32}\z',"
           Replace = "'horde-browser-[0-9a-f]{32}\z'," }
        @{ Name = "empty-fleet-loose-prefix"
           Find = "'\Ahorde-empty-fleet-[0-9a-f]{32}\z'"
           Replace = "'\Ahorde-empty-fleet'" }
        @{ Name = "empty-fleet-missing"
           Find = "'\Ahorde-empty-fleet-[0-9a-f]{32}\z'"
           Replace = "'\Ahorde-empty-fleet-[0-9a-f]{33}\z'" }
        @{ Name = "pwa-browser-loose-length"
           Find = "'\Ahorde-pwa-browser-[0-9a-f]{32}\z',"
           Replace = "'\Ahorde-pwa-browser-[0-9a-f]{31,32}\z'," }
        @{ Name = "case-insensitive-match"
           Find = 'if ($Name -cmatch $p) { return $true }'
           Replace = 'if ($Name -match $p) { return $true }' }
        @{ Name = "one-pattern-missing"
           Find = "'\Ahorde-decisions-browser-[0-9a-f]{32}\z'"
           Replace = "'\Ahorde-decisions-browser-[0-9a-f]{31}\z'" }
        @{ Name = "top-link-not-skipped"
           Find = 'if (($d.Attributes -band $script:HordeSweepLink) -ne 0) { $why = '
           Replace = 'if ($false) { $why = ' }
        @{ Name = "in-use-not-checked"
           Find = '$_.IndexOf($name, [System.StringComparison]::OrdinalIgnoreCase) -ge 0'
           Replace = '$false' }
        @{ Name = "age-not-checked"
           Find = 'elseif (Test-HordeSweepYoung -Dir $d -CutoffUtc $cutoff) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "age-of-folder-only"
           Find = 'if ($e -is [System.IO.DirectoryInfo] -and (Test-HordeSweepYoung -Dir $e -CutoffUtc $CutoffUtc)) { return $true }'
           Replace = '' }
        @{ Name = "inner-link-followed"
           Find = 'if (($e.Attributes -band $script:HordeSweepLink) -ne 0) { [System.IO.Directory]::Delete($e.FullName, $false) }'
           Replace = 'if ($false) { }' }
        @{ Name = "whatif-ignored"
           Find = 'if ($WhatIf) { Write-Output ("WOULD REMOVE " + $name); $removed++; continue }'
           Replace = '' }
        @{ Name = "files-swept-too"
           Find = 'foreach ($d in @($rootInfo.GetDirectories() | Sort-Object Name)) {'
           Replace = 'foreach ($d in @($rootInfo.GetFileSystemInfos() | Sort-Object Name)) {' }
        @{ Name = "root-not-temp"
           Find = 'if ($Root -eq "") { $Root = [System.IO.Path]::GetTempPath() }'
           Replace = 'if ($Root -eq "") { $Root = Join-Path ([System.IO.Path]::GetTempPath()) "elsewhere" }' }
        @{ Name = "exit-nonzero"
           Find = 'Write-Output ("swept " + $shown + ": " + $removed + $verb + $skipped + " skipped")'
           Replace = 'Write-Output ("swept " + $shown + ": " + $removed + $verb + $skipped + " skipped"); exit 1' }
        @{ Name = "long-paths-refused"
           Find = '$rootInfo = New-Object System.IO.DirectoryInfo -ArgumentList $long'
           Replace = '$rootInfo = New-Object System.IO.DirectoryInfo -ArgumentList $shown' }
    )
}
