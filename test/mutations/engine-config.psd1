# Mutations of core/EngineConfig.ps1 (engines E3).
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\engine-config.psd1
# Each removes or weakens one finding's condition; test\test-engine-config.ps1 must fail for every one.
# The secret and redaction mutants are in engine-config-secrets.psd1, which runs the secret sections;
# this spec runs every other section and never the 135-case secret matrix, most of a full run's time.
# A filtered run exits 3, so PassCodes accepts it for these runs and nowhere else.
@{
    Target = "core\EngineConfig.ps1"
    Suite  = "test\test-engine-config.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1"; HORDE_SECTIONS = "golden,text,layers,names,rules,pairings,review,registry" }
    PassCodes = @(3)
    Mutations = @(
        @{ Name = "l2-read-like-any-layer"
           Find = 'if ($layer -ceq "L2") {'
           Replace = 'if ($false) {' }
        @{ Name = "duplicate-key-ignored"
           Find = 'if ($null -ne $d) { Add-Finding "duplicate-key"'
           Replace = 'if ($false) { Add-Finding "duplicate-key"' }
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
           Find = 'if ($why -ne "") { Add-Finding "key-value"'
           Replace = 'if ($false) { Add-Finding "key-value"' }
        @{ Name = "enum-value-not-checked"
           Find = 'if ($kind -ceq "enum") { if (@($Entry.value.values) -ccontains $Value) { return "" };'
           Replace = 'if ($kind -ceq "enum") { if ($true) { return "" };' }
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
        @{ Name = "registry-value-fields-open"
           Find = 'if ($f -cne "kind" -and -not ($f -ceq "values" -and $kind -ceq "enum")) {'
           Replace = 'if ($false) {' }
    )
}
