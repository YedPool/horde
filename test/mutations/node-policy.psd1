# Mutations of core/NodePolicy.ps1 (remote R9, the act path's A1). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\node-policy.psd1
# Each breaks one rule a node's policy exists for; test\test-node-policy.ps1 must fail for every one.
@{
    Target = "core\NodePolicy.ps1"
    Suite  = "test\test-node-policy.ps1"
    Mutations = @(
        @{ Name = "ceiling-from-any-layer"
           Find = 'if ($script:HordeCeilingLayers -cnotcontains ("" + $s.layer)) {'
           Replace = 'if ($false) {' }
        @{ Name = "default-ceiling-is-the-top"
           Find = '$default = "" + @($Levels)[@($Levels).Count - 2].name'
           Replace = '$default = "" + @($Levels)[@($Levels).Count - 1].name' }
        @{ Name = "above-ceiling-not-refused"
           Find = 'elseif (-not $ok.value) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "forged-ceiling-not-refused"
           Find = 'elseif ($cap.from -ceq "default" -and $cap.note -like "*only the node''s own layers*") {'
           Replace = 'elseif ($false) {' }
        @{ Name = "profile-not-checked"
           Find = 'if (@($pol.profiles) -cnotcontains $profile) {'
           Replace = 'if ($false) {' }
        @{ Name = "cap-off-by-one"
           Find = 'if ($SpawnsToday -ge [int]$pol.dailySpawnCap) {'
           Replace = 'if ($SpawnsToday -gt [int]$pol.dailySpawnCap) {' }
        @{ Name = "no-level-defaults-to-allowed"
           Find = 'if ($null -eq $lv -or $lv.answer.state -ne "known") {'
           Replace = 'if ($false) {' }
        @{ Name = "inside-by-prefix"
           Find = 'return $p.StartsWith($r + ''\'', [System.StringComparison]::OrdinalIgnoreCase)'
           Replace = 'return $p.StartsWith($r, [System.StringComparison]::OrdinalIgnoreCase)' }
        @{ Name = "root-inside-clone-allowed"
           Find = 'elseif (Test-HordePathInside -Path $root -Root ("" + $r.path)) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "dotdot-path-allowed"
           Find = 'if ($seg -ceq "." -or $seg -ceq "..") { return $false }'
           Replace = 'if ($false) { return $false }' }
        @{ Name = "repo-twice-allowed"
           Find = 'if (-not $ids.Add("" + $r.repoId)) {'
           Replace = 'if ($false) {' }
        @{ Name = "worktree-name-unchecked"
           Find = '-or $name.Contains("..") -or $name.EndsWith(".")) { return (New-HordeUnknown -Reason ("''" + $name + "'' is not a worktree name")) }'
           Replace = ') { return (New-HordeUnknown -Reason ("''" + $name + "'' is not a worktree name")) }' }
        @{ Name = "no-policy-allows"
           Find = 'elseif ($Policy.state -eq "absent") { [void]$reasons.Add($Policy.reason) }'
           Replace = 'elseif ($Policy.state -eq "absent") { }' }
        @{ Name = "only-first-reason"
           Find = '$out.reasons = $reasons.ToArray()'
           Replace = '$out.reasons = @($reasons.ToArray() | Select-Object -First 1)' }
    )
}
