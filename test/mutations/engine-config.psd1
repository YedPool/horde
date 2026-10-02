# Mutations of core/EngineConfig.ps1 (engines E3).
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\engine-config.psd1
# Each removes or weakens one finding's condition; test\test-engine-config.ps1 must fail for every one.
@{
    Target = "core\EngineConfig.ps1"
    Suite  = "test\test-engine-config.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "l2-read-like-any-layer"
           Find = 'if ($layer -ceq "L2") {'
           Replace = 'if ($false) {' }
        @{ Name = "duplicate-key-ignored"
           Find = 'if ($null -ne $d) { Add-Finding "duplicate-key"'
           Replace = 'if ($false) { Add-Finding "duplicate-key"' }
        @{ Name = "secret-scan-skipped"
           Find = 'foreach ($p in @(Find-HordeSecretPaths -Value $parsed)) {'
           Replace = 'foreach ($p in @()) {' }
        @{ Name = "secret-entropy-shape-dropped"
           Find = "if (`$tok -cmatch '[A-Z]' -and `$tok -cmatch '[a-z]' -and `$tok -cmatch '[0-9]') { return `$true }"
           Replace = "if (`$false) { return `$true }" }
        @{ Name = "secret-patterns-dropped"
           Find = 'foreach ($p in $script:HordeSecretPatterns) { if ($Text -cmatch $p) { return $true } }'
           Replace = '' }
        @{ Name = "schema-findings-dropped"
           Find = 'foreach ($p in $bad) { Add-Finding "schema"'
           Replace = 'foreach ($p in @()) { Add-Finding "schema"' }
        @{ Name = "definitions-allowed-in-any-layer"
           Find = 'if ($script:HordeConfigDefinitionLayers -cnotcontains $d.layer) {'
           Replace = 'if ($false) {' }
        @{ Name = "definition-names-compared-with-case"
           Find = '$key = ("" + $item.name).ToLowerInvariant()'
           Replace = '$key = ("" + $item.name)'
           Expect = "survives"
           Reason = "schema/engine-config.v1 allows only lower-case names (^[a-z][a-z0-9-]{0,39}$), so two names that differ only in case never reach this comparison; it ignores case so that a later, looser name pattern cannot let one name be defined twice." }
        @{ Name = "definition-defined-twice-accepted"
           Find = 'if ($table.ContainsKey($key)) { Add-Finding "duplicate-name"'
           Replace = 'if ($false) { Add-Finding "duplicate-name"' }
        @{ Name = "revision-in-any-layer"
           Find = 'if ($null -ne (Get-HordeAgentProp $d.doc "revision") -and $d.layer -cne "L4") {'
           Replace = 'if ($false) {' }
        @{ Name = "env-credential-without-ref"
           Find = 'if ($cred.kind -ceq "env" -and $null -eq $ref) {'
           Replace = 'if ($false) {' }
        @{ Name = "login-credential-with-ref"
           Find = 'if ($cred.kind -ceq "harness-login" -and $null -ne $ref) {'
           Replace = 'if ($false) {' }
        @{ Name = "lacks-not-checked"
           Find = 'if ($null -ne $l -and $capNames -cnotcontains $l) {'
           Replace = 'if ($false) {' }
        @{ Name = "unspoken-protocol-not-warned"
           Find = 'if ($spoken -cnotcontains $pv.protocol) {'
           Replace = 'if ($false) {' }
        @{ Name = "alias-provider-not-checked"
           Find = 'if ($null -eq (Get-Def $providers $m.provider)) {'
           Replace = 'if ($false) {' }
        @{ Name = "alias-provider-twice-accepted"
           Find = 'if ($seenP.ContainsKey($m.provider)) {'
           Replace = 'if ($false) {' }
        @{ Name = "undefined-provider-accepted"
           Find = 'if ($null -eq $pv) { Add-Finding "undefined-provider" $Source'
           Replace = 'if ($false) { Add-Finding "undefined-provider" $Source' }
        @{ Name = "undefined-harness-accepted"
           Find = 'if ($Descriptors.Contains($Harness)) { $desc = $Descriptors[$Harness] } else { Add-Finding'
           Replace = 'if ($Descriptors.Contains($Harness)) { $desc = $Descriptors[$Harness] } elseif ($false) { Add-Finding' }
        @{ Name = "wire-format-not-checked"
           Find = 'if (@($desc.protocols) -cnotcontains $pv.protocol) {'
           Replace = 'if ($false) {' }
        @{ Name = "subscription-not-checked"
           Find = 'elseif ($pv.credential.kind -ceq "harness-login" -and $desc.nativeProvider -cne $pv.name) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "subscription-read-from-a-declared-field"
           Find = 'elseif ($pv.credential.kind -ceq "harness-login" -and $desc.nativeProvider -cne $pv.name) {'
           Replace = 'elseif ($pv.subscription -eq $true -and $desc.nativeProvider -cne $pv.name) {' }
        @{ Name = "alias-passed-through"
           Find = 'if ($entry.Count -eq 0) { Add-Finding "alias-missing"'
           Replace = 'if ($false) { Add-Finding "alias-missing"' }
        @{ Name = "allowlist-ignored"
           Find = 'if ($null -ne $allow -and @($allow) -cnotcontains $concrete) {'
           Replace = 'if ($false) {' }
        @{ Name = "allowlist-checks-the-alias-name"
           Find = '$concrete = $entry[0].model'
           Replace = '$concrete = $Model' }
        @{ Name = "rule-id-twice-accepted"
           Find = 'if ($ruleIds.ContainsKey($idKey)) {'
           Replace = 'if ($false) {' }
        @{ Name = "tuner-anywhere"
           Find = 'if ($r.writtenBy -ceq "tuner" -and $d.layer -cne "L4") {'
           Replace = 'if ($false) {' }
        @{ Name = "until-anywhere"
           Find = 'if ($null -ne (Get-HordeAgentProp $r "until") -and $d.layer -cne "L4") {'
           Replace = 'if ($false) {' }
        @{ Name = "fleet-id-alone"
           Find = 'if ($null -ne (Get-HordeAgentProp $r.match "fleetId") -and $null -eq (Get-HordeAgentProp $r.match "run")) {'
           Replace = 'if ($false) {' }
        @{ Name = "empty-set-accepted"
           Find = 'if ($setProps.Count -eq 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "unknown-key-accepted"
           Find = 'if (-not $keyByName.ContainsKey($p.Name)) {'
           Replace = 'if ($false) {' }
        @{ Name = "key-layer-not-checked"
           Find = 'if (@($entry.layers) -cnotcontains $d.layer) {'
           Replace = 'if ($false) {' }
        @{ Name = "key-value-not-checked"
           Find = 'if (-not (Test-HordeConfigValue -Entry $entry -Value $p.Value)) {'
           Replace = 'if ($false) {' }
        @{ Name = "enum-value-not-checked"
           Find = 'if ($kind -ceq "enum") { return [bool]($Value -is [string] -and @($Entry.value.values) -ccontains $Value) }'
           Replace = 'if ($kind -ceq "enum") { return $true }' }
        @{ Name = "undefined-profile-accepted"
           Find = 'if ($null -eq $prof) { Add-Finding "undefined-profile"'
           Replace = 'if ($false) { Add-Finding "undefined-profile"' }
        @{ Name = "rule-pair-not-checked"
           Find = 'Test-Binding -Harness $h -Provider $pr -Model $mo -Where ("the rule " + $r.id) -Source $d.source -Path $at'
           Replace = '$null = $h' }
        @{ Name = "profile-pair-not-checked"
           Find = 'foreach ($e in @($profiles.Values)) { Test-Binding'
           Replace = 'foreach ($e in @()) { Test-Binding' }
        @{ Name = "registry-repeat-accepted"
           Find = 'if (-not $seen.Add($n)) { [void]$problems.Add("the key " + $n + " is listed twice") }'
           Replace = '$null = $seen.Add($n)' }
        @{ Name = "registry-empty-enum-accepted"
           Find = 'if (@(Get-HordeConfigItems $v "values").Count -eq 0) {'
           Replace = 'if ($false) {' }
    )
}
