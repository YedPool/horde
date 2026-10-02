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
        @{ Name = "secret-mixed-token-dropped"
           Find = "if (`$Token -cmatch '[A-Z]' -and `$Token -cmatch '[a-z]' -and `$Token -cmatch '[0-9]') { return `$true }"
           Replace = "if (`$false) { return `$true }" }
        @{ Name = "secret-lower-token-dropped"
           Find = "if (`$Token.Length -ge 40 -and `$Token -cmatch '^[a-z0-9]+`$' -and `$Token -cmatch '[a-z]' -and `$Token -cmatch '[0-9]') { return `$true }"
           Replace = "if (`$false) { return `$true }" }
        @{ Name = "secret-patterns-dropped"
           Find = 'foreach ($pt in $script:HordeSecretPatterns) { $t = [regex]::Replace($t, $pt, $script:HordeRedacted) }'
           Replace = '' }
        @{ Name = "secret-zai-shape-dropped"
           Find = "'[0-9a-fA-F]{32}\.[A-Za-z0-9]{16,}',"
           Replace = "" }
        @{ Name = "secret-hex-shape-dropped"
           Find = "'(?<![0-9A-Za-z])[0-9a-fA-F]{40,}(?![0-9A-Za-z])'"
           Replace = "'(?!)'" }
        @{ Name = "secret-gitlab-shape-dropped"
           Find = "'glpat-[A-Za-z0-9_-]{20,}',"
           Replace = "" }
        @{ Name = "secret-google-oauth-shape-dropped"
           Find = "'ya29\.[A-Za-z0-9_-]{20,}',"
           Replace = "" }
        @{ Name = "secret-key-names-not-scanned"
           Find = 'if (Test-HordeSecretShape -Text $p.Name) { [void]$out.Add($Path + "." + $p.Name) }'
           Replace = '' }
        @{ Name = "findings-not-redacted"
           Find = 'source = (Protect-HordeText $Source); path = (Protect-HordeText $Path); detail = (Protect-HordeText $Detail)'
           Replace = 'source = $Source; path = $Path; detail = $Detail' }
        @{ Name = "finding-detail-not-redacted"
           Find = 'detail = (Protect-HordeText $Detail)'
           Replace = 'detail = $Detail' }
        @{ Name = "layer-label-not-redacted"
           Find = 'throw (Protect-HordeText ("'
           Replace = 'throw (("' }
        @{ Name = "login-endpoint-accepted"
           Find = 'if ($cred.kind -ceq "harness-login" -and $null -ne (Get-HordeAgentProp $pv "endpoint")) {'
           Replace = 'if ($false) {' }
        @{ Name = "keys-matched-ignoring-case"
           Find = "`$keyByName = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)"
           Replace = "`$keyByName = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)" }
        @{ Name = "non-ascii-accepted"
           Find = "elseif (`$txt -cmatch '[^\x00-\x7F]') {"
           Replace = "elseif (`$false) {" }
        @{ Name = "bom-not-named"
           Find = 'if ($txt.Length -gt 0 -and [int]$txt[0] -eq 0xFEFF) {'
           Replace = 'if ($false) {' }
        @{ Name = "registry-unknown-field-ignored"
           Find = 'if ($script:HordeConfigKeyFields -cnotcontains $f) {'
           Replace = 'if ($false) {' }
        @{ Name = "registry-layers-text-accepted"
           Find = 'if ($lyRaw -isnot [System.Array]) {'
           Replace = 'if ($false) {' }
        @{ Name = "registry-enum-repeat-accepted"
           Find = 'foreach ($x in $vals) { if (-not $seenV.Add("" + $x))'
           Replace = 'foreach ($x in @()) { if (-not $seenV.Add("" + $x))' }
        @{ Name = "registry-direction-unchecked"
           Find = 'if ($script:HordeConfigDirections -cnotcontains ("" + $dir)) {'
           Replace = 'if ($false) {' }
        @{ Name = "registry-direction-off-an-enum"
           Find = 'elseif ("" + $dir -cne "any" -and $kind -cne "enum") {'
           Replace = 'elseif ($false) {' }
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
           Find = 'if ($vals.Count -eq 0) {'
           Replace = 'if ($false) {' }
    )
}
