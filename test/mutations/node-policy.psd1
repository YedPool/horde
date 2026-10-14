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
        # The founder's decision of 2026-10-11: the default is the top, not the level below it.
        @{ Name = "default-ceiling-below-the-top"
           Find = '$default = $names[$names.Count - 1]'
           Replace = '$default = $names[$names.Count - 2]' }
        @{ Name = "default-cap-is-no-cap"
           Find = 'if ($null -eq $Policy.PSObject.Properties["dailySpawnCap"]) { return $script:HordeNodeSpawnCapDefault }'
           Replace = 'if ($null -eq $Policy.PSObject.Properties["dailySpawnCap"]) { return $script:HordeNodeSpawnCapMax }' }
        @{ Name = "default-cap-not-32"
           Find = '$script:HordeNodeSpawnCapDefault = 32'
           Replace = '$script:HordeNodeSpawnCapDefault = 31' }
        @{ Name = "policy-without-cap-refused"
           Find = 'if ($null -ne $doc.PSObject.Properties["dailySpawnCap"] -and $null -eq (ConvertTo-HordeNodeSpawnCap'
           Replace = 'if ($null -eq (ConvertTo-HordeNodeSpawnCap' }
        @{ Name = "owner-cap-ignored"
           Find = '$capV = Get-HordeNodeSpawnCap -Policy $pol'
           Replace = '$capV = $script:HordeNodeSpawnCapDefault' }
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
           Replace = 'if ($vals.Count -eq 1) {'
           Expect = "survives"
           Reason = "equivalent since the default became the top (founder, 2026-10-11): no level is above it, so an L4 rule reaching this branch can only equal or lower the default, and the mutant only changes the from field of an equal one; L4 raising an L1 ceiling is the resolver's lower-only walk, held by 'a live rule (L4) may not raise it'" }
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
        # The session stores a node declares, in their own file (ledger core-projection L-101).
        @{ Name = "empty-session-store-declaration-allowed"
           Find = 'if ($stores.Count -eq 0) { [void]$problems.Add('
           Replace = 'if ($false) { [void]$problems.Add(' }
        @{ Name = "session-store-declared-twice-allowed"
           Find = 'foreach ($s in $stores) { if (-not $seen.Add("" + $s)) {'
           Replace = 'foreach ($s in $stores) { if ($false) {' }
        @{ Name = "no-declaration-file-declares-stores"
           Find = 'return (New-HordeAbsent -Note ("this node declares no session stores: there is no " + $Path))'
           Replace = 'return (New-HordeKnown -Value @("X2"))' }
        @{ Name = "session-stores-schema-unchecked"
           Find = 'foreach ($b in @(Test-HordeSchema -Value $doc -Schema (Get-HordeSchema -Name "node-session-stores.v1")))'
           Replace = 'foreach ($b in @())' }
    )
}
