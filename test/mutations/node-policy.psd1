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
           Find = '$default = $names[$names.Count - 2]'
           Replace = '$default = $names[$names.Count - 1]' }
        @{ Name = "above-ceiling-not-refused"
           Find = 'elseif (-not $ok.value) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "forged-ceiling-believed"
           Find = 'return [pscustomobject]@{ level = $null; from = ("" + $s.layer + " " + $s.rule); note = ("the ceiling rule " + $s.rule + " is in "'
           Replace = 'return [pscustomobject]@{ level = ("" + $s.answer.value); from = ("" + $s.layer + " " + $s.rule); note = ("the ceiling rule " + $s.rule + " is in "' }
        @{ Name = "profile-not-checked"
           Find = 'if (@($pol.profiles) -cnotcontains $profile) {'
           Replace = 'if ($false) {' }
        @{ Name = "cap-off-by-one"
           Find = 'elseif ($SpawnsToday -ge $capN) {'
           Replace = 'elseif ($SpawnsToday -gt $capN) {' }
        @{ Name = "no-level-defaults-to-allowed"
           Find = 'if ($null -eq $lv -or $lv.answer.state -ne "known") {'
           Replace = 'if ($false) {' }
        @{ Name = "inside-by-prefix"
           Find = 'return $p.StartsWith($r + ''\'', [System.StringComparison]::OrdinalIgnoreCase)'
           Replace = 'return $p.StartsWith($r, [System.StringComparison]::OrdinalIgnoreCase)' }
        @{ Name = "root-inside-clone-allowed"
           Find = 'elseif (Test-HordeNodePathInside -Path $root -Root ("" + $r.path)) {'
           Replace = 'elseif ($false) {' }
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
        @{ Name = "rejected-ceiling-falls-to-default"
           Find = 'if ($script:HordeCeilingLayers -ccontains ("" + $r.layer) -and ($r.value -isnot [string] -or $names -cnotcontains ("" + $r.value))) {'
           Replace = 'if ($false) {' }
        @{ Name = "l4-lowering-ignored"
           Find = 'if ($vals.Count -eq 1 -and [array]::IndexOf($names, $vals[0]) -lt [array]::IndexOf($names, $default)) {'
           Replace = 'if ($false) {' }
        @{ Name = "l4-may-raise"
           Find = 'if ($vals.Count -eq 1 -and [array]::IndexOf($names, $vals[0]) -lt [array]::IndexOf($names, $default)) {'
           Replace = 'if ($vals.Count -eq 1) {' }
        @{ Name = "l4-disagreement-picks-one"
           Find = 'if ($vals.Count -gt 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "cap-overflow-cast"
           Find = 'if ($Value -isnot [int] -and $Value -isnot [long]) { return $null }'
           Replace = 'if ($Value -isnot [int] -and $Value -isnot [long] -and $Value -isnot [decimal] -and $Value -isnot [double]) { return $null }' }
        @{ Name = "unreadable-cap-allows"
           Find = 'if ($null -eq $capN) { [void]$reasons.Add('
           Replace = 'if ($false) { [void]$reasons.Add(' }
        @{ Name = "trailing-dot-segment-allowed"
           Find = 'if ($seg.EndsWith(".") -or $seg.EndsWith(" ")) { return $false }'
           Replace = '' }
        @{ Name = "device-name-allowed"
           Find = 'if ($name -imatch ''\A(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?\z'') {'
           Replace = 'if ($false) {' }
        @{ Name = "policy-bytes-unchecked"
           Find = '    try { Assert-HordeAsciiBytes -Bytes $bytes -What ("the node policy at " + $Path) } catch {'
           Replace = '    try { } catch {' }
    )
}
