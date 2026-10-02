# Mutations of core/EngineResolve.ps1 (engines E4).
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\engine-resolve.psd1
# Each breaks one rule of resolution; test\test-engine-resolve.ps1 must fail for every one.
@{
    Target = "core\EngineResolve.ps1"
    Suite  = "test\test-engine-resolve.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "lowest-layer-wins"
           Find = '$maxRank = ($List | Measure-Object -Property rank -Maximum).Maximum'
           Replace = '$maxRank = ($List | Measure-Object -Property rank -Minimum).Minimum' }
        @{ Name = "specificity-reversed"
           Find = 'if ($A[$i] -gt $B[$i]) { return 1 }; if ($A[$i] -lt $B[$i]) { return -1 }'
           Replace = 'if ($A[$i] -gt $B[$i]) { return -1 }; if ($A[$i] -lt $B[$i]) { return 1 }' }
        @{ Name = "more-keys-not-more-specific"
           Find = 'if ($A.Count -gt $B.Count) { return 1 }'
           Replace = '' }
        @{ Name = "exact-glob-no-bonus"
           Find = '$r = $r + 1'
           Replace = '$r = $r' }
        @{ Name = "tie-goes-to-file-order"
           Find = 'if ($distinct.Count -gt 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "role-not-translated"
           Find = '$tgt["role"] = $rr.role.value'
           Replace = '$tgt["role"] = $tgt["role"]' }
        @{ Name = "session-compared-with-case"
           Find = '"session" { if ($want -ine $have) { return $false } }'
           Replace = '"session" { if ($want -cne $have) { return $false } }' }
        @{ Name = "label-glob-read-as-exact"
           Find = '"label" { if (-not ($have -clike $want)) { return $false } }'
           Replace = '"label" { if ($have -cne $want) { return $false } }' }
        @{ Name = "missing-target-key-matches"
           Find = 'if (-not $Target.ContainsKey($p.Name) -or $null -eq $Target[$p.Name] -or "$($Target[$p.Name])" -eq "") { return $false }'
           Replace = 'if (-not $Target.ContainsKey($p.Name)) { continue }' }
        @{ Name = "expiry-ignored"
           Find = 'if ($t -le $nowUtc) { continue }'
           Replace = '' }
        @{ Name = "profile-beats-the-rules-own-key"
           Find = 'if ($p.Name -cne "profile") { $values[$p.Name] = $p.Value; $via.Remove($p.Name) }'
           Replace = 'if ($p.Name -cne "profile" -and -not $values.Contains($p.Name)) { $values[$p.Name] = $p.Value; $via.Remove($p.Name) }' }
        @{ Name = "tuner-may-lower"
           Find = 'if ($low.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "alias-passed-through"
           Find = 'if ($entry.Count -eq 0) { $binding = New-HordeUnknown'
           Replace = 'if ($false) { $binding = New-HordeUnknown' }
        @{ Name = "alias-not-pinned"
           Find = '$alias = $model; $model = $entry[0].model'
           Replace = '$alias = $model' }
        @{ Name = "wire-format-not-checked"
           Find = 'if (@($desc.protocols) -cnotcontains $pv.protocol) { $binding'
           Replace = 'if ($false) { $binding' }
        @{ Name = "subscription-not-checked"
           Find = 'elseif ($pv.credential.kind -ceq "harness-login" -and $desc.nativeProvider -cne $pv.name) { $binding'
           Replace = 'elseif ($false) { $binding' }
        @{ Name = "allowlist-not-checked"
           Find = 'elseif ($null -ne $model -and $null -ne $allow -and @($allow) -cnotcontains $model) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "unverified-satisfies"
           Find = '$agentYes = (Test-HordeAgentCapability -Descriptor $desc -Name $c) -and ($lacks -cnotcontains $c)'
           Replace = '$agentYes = ("" + $desc.capabilities.$c.support -cne "no") -and ($lacks -cnotcontains $c)' }
        @{ Name = "provider-lacks-ignored"
           Find = '$agentYes = (Test-HordeAgentCapability -Descriptor $desc -Name $c) -and ($lacks -cnotcontains $c)'
           Replace = '$agentYes = (Test-HordeAgentCapability -Descriptor $desc -Name $c)' }
        @{ Name = "host-unverified-satisfies"
           Find = '$hostYes = ("" + $HostCapabilities[$row.host]) -ceq "yes"'
           Replace = '$hostYes = ("" + $HostCapabilities[$row.host]) -cne "no"' }
        @{ Name = "host-never-consulted"
           Find = '$hostYes = ("" + $HostCapabilities[$row.host]) -ceq "yes"'
           Replace = '$hostYes = $false' }
        @{ Name = "requirement-typo-accepted"
           Find = 'if ($names -cnotcontains $c) { $problems +='
           Replace = 'if ($false) { $problems +=' }
        @{ Name = "role-without-list-accepted"
           Find = 'if ($null -eq $list) { $problems +='
           Replace = 'if ($false) { $problems +=' }
        @{ Name = "project-layer-resolved"
           Find = 'if ($l.layer -ceq "L2") { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "beaten-all-called-less-specific"
           Find = '$(if ($c.rank -lt $pick.top[0].rank) { "lower layer" } else { "less specific" })'
           Replace = '"less specific"' }
        @{ Name = "direction-ignored"
           Find = 'if (($dir -ceq "lower-only" -or $dir -ceq "raise-only") -and @($mine | Where-Object { $_.rank -gt 1 }).Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "lower-only-may-raise"
           Find = 'if ($dir -ceq "lower-only" -and $iNew -gt $iCur) { $why'
           Replace = 'if ($false) { $why' }
        @{ Name = "raise-only-may-lower"
           Find = 'if ($dir -ceq "raise-only" -and $iNew -lt $iCur) { $why'
           Replace = 'if ($false) { $why' }
        @{ Name = "no-base-taken-as-base"
           Find = 'if ($null -eq $current) { $why = "refused: "'
           Replace = 'if ($false) { $why = "refused: "' }
        @{ Name = "compared-with-the-owner-only"
           Find = '$lv = @($lp.top | ForEach-Object { "" + $_.value } | Select-Object -Unique)'
           Replace = '$lv = @(); continue' }
        @{ Name = "direction-checks-the-winner-only"
           Find = '                foreach ($c in $inLayer) {'
           Replace = 'foreach ($c in @((Select-HordeWinner -List $inLayer).top)) {' }
        @{ Name = "tie-held-to-the-most-permissive"
           Find = 'if ($dir -ceq "lower-only") { $current = $values[$idx[0]] } else { $current = $values[$idx[$idx.Count - 1]] }'
           Replace = 'if ($dir -ceq "lower-only") { $current = $values[$idx[$idx.Count - 1]] } else { $current = $values[$idx[0]] }' }
        @{ Name = "tuner-checks-the-winner-only"
           Find = '$low = @($mine | Where-Object { -not (& $byPerson $_) -and'
           Replace = '$low = @(@((Select-HordeWinner -List $mine).top) | Where-Object { -not (& $byPerson $_) -and' }
        @{ Name = "value-outside-enum-ranked"
           Find = 'if ($c.value -isnot [string] -or $enumVals -cnotcontains $c.value) {'
           Replace = 'if ($false) {' }
        @{ Name = "enum-value-matched-ignoring-case"
           Find = 'if ($c.value -isnot [string] -or $enumVals -cnotcontains $c.value) {'
           Replace = 'if ($c.value -isnot [string] -or $enumVals -notcontains $c.value) {' }
        @{ Name = "tuner-check-skipped-on-a-tie"
           Find = 'if ($agreed.Count -ge 1) {'
           Replace = 'if ($agreed.Count -eq 1) {' }
        @{ Name = "tuner-held-to-the-lowest-of-a-tie"
           Find = '$floor = $floorIdx[$floorIdx.Count - 1]'
           Replace = '$floor = $floorIdx[0]' }
        @{ Name = "writer-other-than-tuner-trusted"
           Find = '$byPerson = { param($c) ($c.by -ceq "user" -or $c.by -ceq "cli") }'
           Replace = '$byPerson = { param($c) ($c.by -cne "tuner") }' }
    )
}
