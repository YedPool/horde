# core/EngineConfig - check the layers of engine configuration before anything resolves them.
#
# ENGINES PLAN STEP E3 (planning/execution-plan-engines.md; engine-settings design, sections 2 to 4,
# and its "Decisions taken"). A layer is a document in schema/engine-config.v1: L0 built-in, L1 the
# user's file, L4 the live rules, and the rules a run spec (L3) or a spawn (L5) compile to. Resolving
# a target against them is engines E4 (core/EngineResolve.ps1); this file says whether they may be
# resolved at all. Test-HordeEngineConfig takes every layer at once, because a rule in one layer names
# a profile or provider defined in another.
#
# WHAT IT FINDS. Each finding is { severity; code; source; path; detail }. All are errors except the
# one marked warning. test/test-engine-config.ps1 has a case for every code:
#   not-json             the text does not parse
#   duplicate-key        a key appears twice in one object (ConvertFrom-Json would keep the last)
#   schema               the document does not fit schema/engine-config.v1
#   secret               a string is shaped like a key or token; the finding names WHERE, never what
#   layer-not-built      the document is L2, the project layer, which waits until a repo needs one
#   definition-layer     providers, aliases or profiles outside L0 and L1
#   revision-layer       a revision outside L4
#   tuner-layer          a rule written by the tuner outside L4 (it writes live rules only)
#   until-layer          an expiry outside L4
#   duplicate-name       a provider, alias or profile defined twice across L0 and L1 (ignoring case),
#                        or two rules of one id in one layer
#   undefined-provider   a profile, alias entry or rule names a provider nobody defined
#   undefined-profile    a rule names a profile nobody defined
#   undefined-harness    a profile or rule names a harness with no descriptor (agents/<name>/agent.json)
#   alias-provider-twice an alias with two entries for one provider
#   unknown-capability   a provider lacks a capability core/capabilities.json does not have
#   credential-ref       an env credential with no variable named, or a harness-login one naming one
#   protocol-unspoken    (warning) a provider whose protocol no harness speaks
#   empty-set            a rule that sets nothing
#   fleet-without-run    a rule matching a fleet id without its run (a fleet id is unique per run only)
#   unknown-key          a rule sets a key core/config-keys.json does not have
#   key-layer            a rule sets a key in a layer the registry does not allow it in
#   key-value            a rule sets a key to a value its kind does not allow
#   wire-format          a harness paired with a provider whose protocol its descriptor does not list
#   subscription         a harness-login provider paired with a harness whose nativeProvider is another:
#                        a subscription runs only on its vendor's own program (agent-engines decision 7).
#                        It is recognised from the credential kind, never from anything a file declares.
#   alias-missing        a model alias with no entry for the provider it is paired with; the alias's
#                        name is never passed through to a provider that does not know it
#   model-not-allowed    a concrete model, or the one an alias pins, outside the provider's allowlist
#
# A PAIR IS CHECKED WHEREVER ONE DOCUMENT STATES IT: a profile, or a rule whose set gives (directly or
# through a profile) both a harness and a provider, or both a provider and a model. A pair made only
# by combining rules of different layers is E4's to check, on the resolved binding.
#
# THE REGISTRY IS THE SEAM (core/config-keys.json). A rule's set may hold only keys the registry
# lists, in the layers it allows, with values of its kind. The binding keys are there today; a later
# setting - metrics.level (metrics M2), admission.tier (lifecycle 1), remote.permissionCeiling (remote
# R9, allowed only in L1 and L4) - is one entry there, and every check and the resolver read it.
#
# NEVER A SECRET IN OUTPUT. Every string value is scanned; a finding names its document and path only.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "Schema.ps1")
. (Join-Path $PSScriptRoot "JsonText.ps1")
. (Join-Path $PSScriptRoot "AgentDescriptor.ps1")

$script:HordeConfigLayers = @("L0", "L1", "L2", "L3", "L4", "L5")
$script:HordeConfigDefinitionLayers = @("L0", "L1")
$script:HordeConfigValueKinds = @{
    name = '^[a-z][a-z0-9-]{0,39}$'
    model = '^[A-Za-z0-9][A-Za-z0-9._:/@-]{0,99}$'
}
# Shapes of a secret. Measured against the golden fixtures and every descriptor in agents/ (no hit),
# and each has a planted case in test-engine-config. The last is a long token mixing upper case, lower
# case and digits, the shape of most generated keys; ids, names and model ids are shorter or lack one
# of the three.
$script:HordeSecretPatterns = @(
    '(?i)(^|[^A-Za-z0-9])sk-[A-Za-z0-9_-]{16,}',
    'AKIA[0-9A-Z]{16}',
    'AIza[0-9A-Za-z_-]{30,}',
    'gh[pousr]_[A-Za-z0-9]{20,}',
    'xox[abpr]-[A-Za-z0-9-]{10,}',
    '-----BEGIN',
    '(?i)bearer\s+[A-Za-z0-9._-]{16,}'
)

function Get-HordeConfigItems {
    # The items of a list property, enumerated, so @(Get-HordeConfigItems ...) is the flat list and an
    # absent list is empty. (Get-HordeAgentProp hands a list back as ONE object, which @() would wrap.)
    param($Object, [string]$Name)
    $v = Get-HordeAgentProp $Object $Name
    if ($null -eq $v) { return }
    foreach ($x in @($v)) { $x }
}

function Read-HordeConfigKeysText {
    # The settings registry from JSON text: rows { name; layers; value { kind; values } }. Throws,
    # naming every problem, when it is not well formed.
    param([Parameter(Mandatory = $true)][string]$Text)
    $problems = New-Object System.Collections.ArrayList
    foreach ($d in @(Find-HordeJsonDuplicateKey -Text $Text)) { [void]$problems.Add("" + $d) }
    $t = $Text | ConvertFrom-Json
    $rows = Get-HordeAgentProp $t "keys"
    if ($rows -isnot [System.Array] -or @($rows).Count -eq 0) { throw "the settings registry must hold a non-empty keys list" }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($r in @($rows)) {
        $n = Get-HordeAgentProp $r "name"
        if ($n -isnot [string] -or $n -cnotmatch '^[a-z][a-zA-Z0-9]*(\.[a-z][a-zA-Z0-9]*)*$') { [void]$problems.Add("a key has the name '" + $n + "'"); continue }
        if (-not $seen.Add($n)) { [void]$problems.Add("the key " + $n + " is listed twice") }
        $ly = @(Get-HordeConfigItems $r "layers")
        if ($ly.Count -eq 0 -or @($ly | Where-Object { $script:HordeConfigLayers -cnotcontains $_ }).Count -gt 0) { [void]$problems.Add("the key " + $n + " has layers outside L0 to L5") }
        $v = Get-HordeAgentProp $r "value"
        $kind = Get-HordeAgentProp $v "kind"
        if ($kind -ceq "enum") { if (@(Get-HordeConfigItems $v "values").Count -eq 0) { [void]$problems.Add("the key " + $n + " is an enum with no values") } }
        elseif (-not $script:HordeConfigValueKinds.ContainsKey("" + $kind)) { [void]$problems.Add("the key " + $n + " has the value kind '" + $kind + "'") }
    }
    if ($problems.Count -gt 0) { throw ("the settings registry is malformed: " + ($problems -join "; ")) }
    return @($rows)
}

function Get-HordeConfigKeys {
    # The registry from core/config-keys.json, or -Path. Plain ASCII, as every Horde data file.
    param([string]$Path = (Join-Path $PSScriptRoot "config-keys.json"))
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    Assert-HordeAsciiBytes -Bytes $bytes -What ("the settings registry at '" + $Path + "'")
    return (Read-HordeConfigKeysText -Text ([System.Text.Encoding]::ASCII.GetString($bytes)))
}

function Test-HordeConfigValue {
    # Does a value fit a registry entry's kind?
    param($Entry, $Value)
    $kind = "" + $Entry.value.kind
    if ($kind -ceq "enum") { return [bool]($Value -is [string] -and @($Entry.value.values) -ccontains $Value) }
    return [bool]($Value -is [string] -and $Value -cmatch $script:HordeConfigValueKinds[$kind])
}

function Test-HordeSecretShape {
    # Is this string shaped like a credential? Never returns or prints the string.
    param([string]$Text)
    foreach ($p in $script:HordeSecretPatterns) { if ($Text -cmatch $p) { return $true } }
    foreach ($m in [regex]::Matches($Text, '[A-Za-z0-9+/=_-]{32,}')) {
        $tok = $m.Value
        if ($tok -cmatch '[A-Z]' -and $tok -cmatch '[a-z]' -and $tok -cmatch '[0-9]') { return $true }
    }
    return $false
}

function Find-HordeSecretPaths {
    # The paths of every string in a parsed value that is shaped like a secret.
    param($Value, [string]$Path = '$')
    $out = New-Object System.Collections.ArrayList
    if ($Value -is [string]) { if (Test-HordeSecretShape -Text $Value) { [void]$out.Add($Path) } }
    elseif ($Value -is [System.Management.Automation.PSCustomObject]) { foreach ($p in @($Value.PSObject.Properties)) { foreach ($x in @(Find-HordeSecretPaths -Value $p.Value -Path ($Path + "." + $p.Name))) { [void]$out.Add($x) } } }
    elseif ($Value -is [System.Collections.IList]) { $i = 0; foreach ($item in $Value) { foreach ($x in @(Find-HordeSecretPaths -Value $item -Path ($Path + "[" + $i + "]"))) { [void]$out.Add($x) }; $i++ } }
    return $out.ToArray()
}

function Test-HordeEngineConfig {
    # Every finding across the given layers. -Documents: { layer; source; text } each. -Descriptors:
    # harness name -> descriptor (default: every agents/<name>/agent.json, which must all load).
    param([Parameter(Mandatory = $true)][object[]]$Documents, $Descriptors = $null, $Registry = $null, $Vocabulary = $null)
    if ($null -eq $Descriptors) {
        $all = Get-HordeAgentDescriptors
        if ($all.state -cne "known") { throw ("the agent descriptors are not usable, so no engine configuration can be checked: " + $all.reason + $all.note) }
        $Descriptors = $all.value
    }
    if ($null -eq $Registry) { $Registry = @(Get-HordeConfigKeys) }
    if ($null -eq $Vocabulary) { $Vocabulary = @(Get-HordeCapabilityVocabulary) }
    $capNames = @($Vocabulary | ForEach-Object { $_.name })
    $keyByName = @{}
    foreach ($k in @($Registry)) { $keyByName["" + $k.name] = $k }
    $out = New-Object System.Collections.ArrayList
    function Add-Finding { param([string]$Code, [string]$Source, [string]$Path, [string]$Detail, [string]$Severity = "error") [void]$out.Add([pscustomobject]@{ severity = $Severity; code = $Code; source = $Source; path = $Path; detail = $Detail }) }
    $schema = Get-HordeSchema -Name "engine-config.v1"

    # Parse every document; keep the ones that parse and fit.
    $docs = New-Object System.Collections.ArrayList
    foreach ($doc in @($Documents)) {
        $layer = "" + $doc.layer
        $src = "" + $doc.source
        if ($script:HordeConfigLayers -cnotcontains $layer) { throw ("'" + $layer + "' is not a configuration layer; one of " + ($script:HordeConfigLayers -join ", ")) }
        if ($layer -ceq "L2") { Add-Finding "layer-not-built" $src '$' "the project layer (L2) is not built yet: it waits until a repo needs one (engine-settings decision 3), so nothing in a project file is read"; continue }
        foreach ($d in @(Find-HordeJsonDuplicateKey -Text ("" + $doc.text))) { if ($null -ne $d) { Add-Finding "duplicate-key" $src '$' ("" + $d) } }
        $parsed = $null
        try { $parsed = ("" + $doc.text) | ConvertFrom-Json } catch { Add-Finding "not-json" $src '$' "the text is not JSON"; continue }
        foreach ($p in @(Find-HordeSecretPaths -Value $parsed)) { Add-Finding "secret" $src $p "this string is shaped like a key or token; a configuration names a variable, never a secret, and the value is not shown" }
        $bad = @(Test-HordeSchema -Value $parsed -Schema $schema)
        foreach ($p in $bad) { Add-Finding "schema" $src $p ("" + $p) }
        if ($bad.Count -gt 0) { continue }
        [void]$docs.Add([pscustomobject]@{ layer = $layer; source = $src; doc = $parsed })
    }

    # Definitions: L0 and L1 only, each name once across them.
    $providers = @{}; $aliases = @{}; $profiles = @{}
    foreach ($d in $docs) {
        foreach ($kind in @("providers", "aliases", "profiles")) {
            $list = Get-HordeAgentProp $d.doc $kind
            if ($null -eq $list) { continue }
            if ($script:HordeConfigDefinitionLayers -cnotcontains $d.layer) { Add-Finding "definition-layer" $d.source ('$.' + $kind) ($kind + " are defined only in the built-in and user layers, not " + $d.layer); continue }
            $table = $(if ($kind -ceq "providers") { $providers } elseif ($kind -ceq "aliases") { $aliases } else { $profiles })
            $i = 0
            foreach ($item in @($list)) {
                $key = ("" + $item.name).ToLowerInvariant()
                if ($table.ContainsKey($key)) { Add-Finding "duplicate-name" $d.source ('$.' + $kind + '[' + $i + ']') ("the name " + $item.name + " is defined twice (" + $table[$key].source + " and " + $d.source + ")") }
                else { $table[$key] = [pscustomobject]@{ item = $item; source = $d.source } }
                $i++
            }
        }
        if ($null -ne (Get-HordeAgentProp $d.doc "revision") -and $d.layer -cne "L4") { Add-Finding "revision-layer" $d.source '$.revision' ("a revision belongs to the live rules (L4), not " + $d.layer) }
    }
    function Get-Def { param($Table, [string]$Name) $k = $Name.ToLowerInvariant(); if ($Table.ContainsKey($k) -and $Table[$k].item.name -ceq $Name) { return $Table[$k].item }; return $null }

    # Providers: credentials, capabilities, protocols someone speaks.
    $spoken = @($Descriptors.Values | ForEach-Object { @($_.protocols) })
    foreach ($e in @($providers.Values)) {
        $pv = $e.item
        $cred = $pv.credential
        $ref = Get-HordeAgentProp $cred "ref"
        if ($cred.kind -ceq "env" -and $null -eq $ref) { Add-Finding "credential-ref" $e.source ('$.providers.' + $pv.name) ("the provider " + $pv.name + " reads its key from an environment variable but names none") }
        if ($cred.kind -ceq "harness-login" -and $null -ne $ref) { Add-Finding "credential-ref" $e.source ('$.providers.' + $pv.name) ("the provider " + $pv.name + " uses the harness's own login, so it names no variable") }
        foreach ($l in @(Get-HordeConfigItems $pv "lacks")) { if ($null -ne $l -and $capNames -cnotcontains $l) { Add-Finding "unknown-capability" $e.source ('$.providers.' + $pv.name + '.lacks') ("the provider " + $pv.name + " lacks " + $l + ", which core/capabilities.json does not have") } }
        if ($spoken -cnotcontains $pv.protocol) { Add-Finding "protocol-unspoken" $e.source ('$.providers.' + $pv.name) ("no harness speaks " + $pv.protocol + ", the protocol of the provider " + $pv.name) "warning" }
    }
    # Aliases: providers defined, one entry each.
    foreach ($e in @($aliases.Values)) {
        $seenP = @{}
        foreach ($m in @($e.item.map)) {
            if ($null -eq (Get-Def $providers $m.provider)) { Add-Finding "undefined-provider" $e.source ('$.aliases.' + $e.item.name) ("the alias " + $e.item.name + " maps the provider " + $m.provider + ", which nobody defined") }
            if ($seenP.ContainsKey($m.provider)) { Add-Finding "alias-provider-twice" $e.source ('$.aliases.' + $e.item.name) ("the alias " + $e.item.name + " has two entries for the provider " + $m.provider) }
            $seenP[$m.provider] = $true
        }
    }

    # A harness, provider and model stated together: the wire-format, subscription and pinning rules.
    function Test-Binding {
        param($Harness, $Provider, $Model, [string]$Where, [string]$Source, [string]$Path)
        $pv = $null
        if ($null -ne $Provider) { $pv = Get-Def $providers $Provider; if ($null -eq $pv) { Add-Finding "undefined-provider" $Source $Path ($Where + " names the provider " + $Provider + ", which nobody defined") } }
        $desc = $null
        if ($null -ne $Harness) { if ($Descriptors.Contains($Harness)) { $desc = $Descriptors[$Harness] } else { Add-Finding "undefined-harness" $Source $Path ($Where + " names the harness " + $Harness + ", which has no descriptor in agents/") } }
        if ($null -ne $desc -and $null -ne $pv) {
            if (@($desc.protocols) -cnotcontains $pv.protocol) { Add-Finding "wire-format" $Source $Path ($Where + " pairs the harness " + $Harness + " with the provider " + $Provider + ", whose protocol " + $pv.protocol + " that harness does not speak") }
            elseif ($pv.credential.kind -ceq "harness-login" -and $desc.nativeProvider -cne $pv.name) { Add-Finding "subscription" $Source $Path ($Where + " runs the provider " + $Provider + " on its own login under the harness " + $Harness + ", whose native provider is " + $desc.nativeProvider + "; a subscription runs only on its vendor's own program") }
        }
        if ($null -ne $pv -and $null -ne $Model) {
            $concrete = $Model
            $al = Get-Def $aliases $Model
            if ($null -ne $al) {
                $entry = @(@($al.map) | Where-Object { $_.provider -ceq $pv.name })
                if ($entry.Count -eq 0) { Add-Finding "alias-missing" $Source $Path ($Where + " uses the alias " + $Model + ", which has no entry for the provider " + $Provider + "; the alias's name is never passed to a provider"); return }
                $concrete = $entry[0].model
            }
            $allow = Get-HordeAgentProp $pv "models"
            if ($null -ne $allow -and @($allow) -cnotcontains $concrete) { Add-Finding "model-not-allowed" $Source $Path ($Where + " runs the model " + $concrete + " on the provider " + $Provider + ", whose allowlist does not hold it") }
        }
    }
    foreach ($e in @($profiles.Values)) { Test-Binding -Harness $e.item.harness -Provider $e.item.provider -Model (Get-HordeAgentProp $e.item "model") -Where ("the profile " + $e.item.name) -Source $e.source -Path ('$.profiles.' + $e.item.name) }

    # Rules.
    $ruleIds = @{}
    foreach ($d in $docs) {
        foreach ($r in @(Get-HordeConfigItems $d.doc "rules")) {
            if ($null -eq $r) { continue }
            $at = '$.rules.' + $r.id
            $idKey = $d.layer + "|" + $r.id
            if ($ruleIds.ContainsKey($idKey)) { Add-Finding "duplicate-name" $d.source $at ("two rules have the id " + $r.id + " in " + $d.layer) }
            $ruleIds[$idKey] = $true
            if ($r.writtenBy -ceq "tuner" -and $d.layer -cne "L4") { Add-Finding "tuner-layer" $d.source $at ("the rule " + $r.id + " was written by the tuner, which writes only live rules (L4), not " + $d.layer) }
            if ($null -ne (Get-HordeAgentProp $r "until") -and $d.layer -cne "L4") { Add-Finding "until-layer" $d.source $at ("the rule " + $r.id + " expires, and only live rules (L4) do") }
            if ($null -ne (Get-HordeAgentProp $r.match "fleetId") -and $null -eq (Get-HordeAgentProp $r.match "run")) { Add-Finding "fleet-without-run" $d.source $at ("the rule " + $r.id + " matches a fleet id without its run; a fleet id is unique only within a run") }
            $setProps = @($r.set.PSObject.Properties)
            if ($setProps.Count -eq 0) { Add-Finding "empty-set" $d.source $at ("the rule " + $r.id + " sets nothing") }
            foreach ($p in $setProps) {
                if (-not $keyByName.ContainsKey($p.Name)) { Add-Finding "unknown-key" $d.source ($at + '.set') ("the rule " + $r.id + " sets " + $p.Name + ", which is not a setting in core/config-keys.json"); continue }
                $entry = $keyByName[$p.Name]
                if (@($entry.layers) -cnotcontains $d.layer) { Add-Finding "key-layer" $d.source ($at + '.set') ("the rule " + $r.id + " sets " + $p.Name + " in " + $d.layer + "; it may be set only in " + (@($entry.layers) -join ", ")) }
                if (-not (Test-HordeConfigValue -Entry $entry -Value $p.Value)) { Add-Finding "key-value" $d.source ($at + '.set') ("the rule " + $r.id + " sets " + $p.Name + " to '" + $p.Value + "', which is not a " + $entry.value.kind + " value it allows") }
            }
            $prof = $null
            $pn = Get-HordeAgentProp $r.set "profile"
            if ($null -ne $pn) { $prof = Get-Def $profiles $pn; if ($null -eq $prof) { Add-Finding "undefined-profile" $d.source $at ("the rule " + $r.id + " sets the profile " + $pn + ", which nobody defined") } }
            $h = Get-HordeAgentProp $r.set "harness"; if ($null -eq $h -and $null -ne $prof) { $h = $prof.harness }
            $pr = Get-HordeAgentProp $r.set "provider"; if ($null -eq $pr -and $null -ne $prof) { $pr = $prof.provider }
            $mo = Get-HordeAgentProp $r.set "model"; if ($null -eq $mo -and $null -ne $prof) { $mo = Get-HordeAgentProp $prof "model" }
            $hNow = Get-HordeAgentProp $r.set "harness"
            # A pair the profile already stated was checked with the profile; re-check only what the
            # rule itself changes, so one mistake is one finding.
            if ($null -ne $hNow -or $null -ne (Get-HordeAgentProp $r.set "provider") -or $null -ne (Get-HordeAgentProp $r.set "model")) {
                Test-Binding -Harness $h -Provider $pr -Model $mo -Where ("the rule " + $r.id) -Source $d.source -Path $at
            }
        }
    }
    return $out.ToArray()
}
