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
# NEVER A SECRET IN OUTPUT. Every string value and key name is scanned, and every finding's text is
# redacted (Protect-HordeText). WHAT THIS DOES NOT CATCH: a secret split across two strings - half in a
# note, half in another field, or broken by a space or punctuation inside one string - matches no
# shape, so neither half is refused and each may be quoted. The shapes find keys as they are issued,
# not keys someone has taken apart.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "Schema.ps1")
. (Join-Path $PSScriptRoot "JsonText.ps1")
. (Join-Path $PSScriptRoot "AgentDescriptor.ps1")

$script:HordeConfigLayers = @("L0", "L1", "L2", "L3", "L4", "L5")
$script:HordeConfigDefinitionLayers = @("L0", "L1")
$script:HordeConfigKeyFields = @("name", "layers", "value", "direction", "tuner")
$script:HordeConfigDirections = @("any", "lower-only", "raise-only")
$script:HordeConfigValueKinds = @{
    name = '^[a-z][a-z0-9-]{0,39}$'
    model = '^[A-Za-z0-9][A-Za-z0-9._:/@-]{0,99}$'
    # A comma-separated list of hub labels (link-verbs v1 label), for remote.deliverTo (remote plan R21):
    # the labels of this node's sessions its owner opts in to remote delivery.
    labels = '^[A-Z]{1,2}([1-9][0-9]{0,3})?(,[A-Z]{1,2}([1-9][0-9]{0,3})?){0,63}$'
}
# SHAPES OF A SECRET, each a pattern whose MATCH is the secret, so the same list both finds and
# redacts. Each has a planted case in test-engine-config, and near misses (39 hex digits, the bare
# prefixes, a UUID, a model id, an endpoint, a variable name, a run id, a sentence) are controls.
# Widened in the review of PR #73 (F4): Z.ai keys, long hex, GitLab and Google OAuth tokens.
$script:HordeSecretPatterns = @(
    '(?i)(?<![A-Za-z0-9])sk-[A-Za-z0-9_-]{16,}',
    'AKIA[0-9A-Z]{16}',
    'AIza[0-9A-Za-z_-]{30,}',
    'gh[pousr]_[A-Za-z0-9]{20,}',
    'glpat-[A-Za-z0-9_-]{20,}',
    'ya29\.[A-Za-z0-9_-]{20,}',
    'xox[abpr]-[A-Za-z0-9-]{10,}',
    '-----BEGIN[^\r\n]*',
    '(?i)bearer\s+[A-Za-z0-9._-]{16,}',
    '[0-9a-fA-F]{32}\.[A-Za-z0-9]{16,}',
    '(?<![0-9A-Za-z])[0-9a-fA-F]{40,}(?![0-9A-Za-z])'
)
# A long token is a secret when it mixes upper case, lower case and digits (most generated keys), or
# is 40 or more lower-case letters and digits with both in it. Ids, names and model ids are shorter.
$script:HordeSecretTokenPattern = '[A-Za-z0-9+/=_-]{32,}'
$script:HordeRedacted = "<redacted>"

function Test-HordeSecretToken {
    param([string]$Token)
    if ($Token -cmatch '[A-Z]' -and $Token -cmatch '[a-z]' -and $Token -cmatch '[0-9]') { return $true }
    if ($Token.Length -ge 40 -and $Token -cmatch '^[a-z0-9]+$' -and $Token -cmatch '[a-z]' -and $Token -cmatch '[0-9]') { return $true }
    return $false
}

function Protect-HordeText {
    # The text with every secret-shaped part replaced by <redacted>. Every message this file builds
    # passes through it (review of PR #73, F1: a second finding on a secret printed it whole), so a
    # finding may quote any value it likes and still never carries a key.
    param([string]$Text)
    if ($null -eq $Text -or $Text -eq "") { return $Text }
    $t = $Text
    foreach ($pt in $script:HordeSecretPatterns) { $t = [regex]::Replace($t, $pt, $script:HordeRedacted) }
    return [regex]::Replace($t, $script:HordeSecretTokenPattern, { param($m) if (Test-HordeSecretToken -Token $m.Value) { $script:HordeRedacted } else { $m.Value } })
}

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
        # A FIELD NOBODY READS IS REFUSED (review of PR #73, F3): a direction the reader did not know
        # would otherwise be ignored, and a lower-only key would silently be any.
        foreach ($f in @($r.PSObject.Properties | ForEach-Object { $_.Name })) { if ($script:HordeConfigKeyFields -cnotcontains $f) { [void]$problems.Add("the key " + $n + " has the field '" + $f + "', which the registry does not have") } }
        $lyRaw = Get-HordeAgentProp $r "layers"
        if ($lyRaw -isnot [System.Array]) { [void]$problems.Add("the key " + $n + "'s layers must be a list") }
        $ly = @(Get-HordeConfigItems $r "layers")
        if ($ly.Count -eq 0 -or @($ly | Where-Object { $script:HordeConfigLayers -cnotcontains $_ }).Count -gt 0) { [void]$problems.Add("the key " + $n + " has layers outside L0 to L5") }
        $v = Get-HordeAgentProp $r "value"
        $kind = Get-HordeAgentProp $v "kind"
        # Closed inside value as well (review of PR #74, F3): kind, and values for an enum alone.
        if ($v -is [System.Management.Automation.PSCustomObject]) {
            foreach ($f in @($v.PSObject.Properties | ForEach-Object { $_.Name })) {
                if ($f -cne "kind" -and -not ($f -ceq "values" -and $kind -ceq "enum")) { [void]$problems.Add("the key " + $n + "'s value has the field '" + $f + "', which a " + $kind + " value does not have") }
            }
        }
        if ($kind -ceq "enum") {
            $vals = @(Get-HordeConfigItems $v "values")
            if ($vals.Count -eq 0) { [void]$problems.Add("the key " + $n + " is an enum with no values") }
            $seenV = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($x in $vals) { if (-not $seenV.Add("" + $x)) { [void]$problems.Add("the key " + $n + " lists the value " + $x + " twice, ignoring case") } }
        }
        elseif (-not $script:HordeConfigValueKinds.ContainsKey("" + $kind)) { [void]$problems.Add("the key " + $n + " has the value kind '" + $kind + "'") }
        # DIRECTION (review of PR #73, F3; the coordinator's decision): which way a layer above the
        # first one that sets the key may move its value. lower-only is remote R9's ceiling, which an
        # agent-writable live rule must never raise. Meaningful only for an enum, written lowest first.
        $dir = Get-HordeAgentProp $r "direction"
        if ($script:HordeConfigDirections -cnotcontains ("" + $dir)) { [void]$problems.Add("the key " + $n + " has the direction '" + $dir + "'; one of " + ($script:HordeConfigDirections -join ", ")) }
        elseif ("" + $dir -cne "any" -and $kind -cne "enum") { [void]$problems.Add("the key " + $n + " has the direction " + $dir + ", which needs an enum: only an enum's values are ordered") }
        # tuner: raise-only (engine-settings decision 9) compares values by their place in the list, so
        # it is meaningful only for an enum, whose values are written lowest first.
        $tuner = Get-HordeAgentProp $r "tuner"
        if ($null -ne $tuner -and ("" + $tuner -cne "raise-only" -or $kind -cne "enum")) { [void]$problems.Add("the key " + $n + " has tuner '" + $tuner + "'; the only one is raise-only, and only on an enum") }
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

function Read-HordeEngineLayerText {
    # One layer document from its text: { layer; source; text; doc }. The text is kept for
    # Test-HordeEngineConfig and the parsed doc for Resolve-HordeEngine; parsing is not checking.
    param([Parameter(Mandatory = $true)][string]$Text, [Parameter(Mandatory = $true)][string]$Layer, [Parameter(Mandatory = $true)][string]$Source)
    return [pscustomobject]@{ layer = $Layer; source = $Source; text = $Text; doc = ($Text | ConvertFrom-Json) }
}

function Get-HordeBuiltinLayer {
    # The built-in layer (L0): every agents/<name>/engine.json, in folder order. Each harness ships its
    # own native provider and profile there, so core names none (CONTRIBUTING 14); the default profile
    # is a rule in exactly one of them, and two would tie, which resolution refuses.
    param([string]$Root = (Split-Path -Parent $PSScriptRoot))
    $agents = Join-Path $Root "agents"
    if (-not (Test-Path -LiteralPath $agents -PathType Container)) { return @() }
    $out = @()
    foreach ($dir in @(Get-ChildItem -LiteralPath $agents -Directory | Sort-Object Name)) {
        $f = Join-Path $dir.FullName "engine.json"
        if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
        $bytes = [System.IO.File]::ReadAllBytes($f)
        Assert-HordeAsciiBytes -Bytes $bytes -What ("the built-in engine layer of " + $dir.Name)
        $out += (Read-HordeEngineLayerText -Text ([System.Text.Encoding]::ASCII.GetString($bytes)) -Layer "L0" -Source ("agents/" + $dir.Name + "/engine.json"))
    }
    return $out
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
    return [bool]((Protect-HordeText -Text $Text) -cne $Text)
}

function Find-HordeSecretPaths {
    # The paths of every string in a parsed value that is shaped like a secret.
    param($Value, [string]$Path = '$')
    $out = New-Object System.Collections.ArrayList
    if ($Value -is [string]) { if (Test-HordeSecretShape -Text $Value) { [void]$out.Add($Path) } }
    elseif ($Value -is [System.Management.Automation.PSCustomObject]) {
        foreach ($p in @($Value.PSObject.Properties)) {
            # A KEY can be the secret too (a key pasted where a setting's name goes), so names are scanned.
            if (Test-HordeSecretShape -Text $p.Name) { [void]$out.Add($Path + "." + $p.Name) }
            foreach ($x in @(Find-HordeSecretPaths -Value $p.Value -Path ($Path + "." + $p.Name))) { [void]$out.Add($x) }
        }
    }
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
    # Matched exactly, as the resolver matches them (review of PR #73, F5): Model is not model.
    $keyByName = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
    foreach ($k in @($Registry)) { $keyByName["" + $k.name] = $k }
    $out = New-Object System.Collections.ArrayList
    # EVERY FINDING IS REDACTED HERE, whatever built its text - this file, the schema's own messages, a
    # code added later - so no path to output can carry a secret (review of PR #73, F1).
    function Add-Finding { param([string]$Code, [string]$Source, [string]$Path, [string]$Detail, [string]$Severity = "error") [void]$out.Add([pscustomobject]@{ severity = $Severity; code = $Code; source = (Protect-HordeText $Source); path = (Protect-HordeText $Path); detail = (Protect-HordeText $Detail) }) }
    $schema = Get-HordeSchema -Name "engine-config.v1"

    # Parse every document; keep the ones that parse and fit.
    $docs = New-Object System.Collections.ArrayList
    foreach ($doc in @($Documents)) {
        $layer = "" + $doc.layer
        $src = "" + $doc.source
        if ($script:HordeConfigLayers -cnotcontains $layer) { throw (Protect-HordeText ("'" + $layer + "' is not a configuration layer; one of " + ($script:HordeConfigLayers -join ", "))) }
        if ($layer -ceq "L2") { Add-Finding "layer-not-built" $src '$' "the project layer (L2) is not built yet: it waits until a repo needs one (engine-settings decision 3), so nothing in a project file is read"; continue }
        # PLAIN ASCII (CONTRIBUTING 13; review of PR #73, F7). A byte-order mark is named, because it
        # otherwise surfaces only as "not JSON", the right refusal for the wrong reason.
        $txt = "" + $doc.text
        if ($txt.Length -gt 0 -and [int]$txt[0] -eq 0xFEFF) { Add-Finding "not-ascii" $src '$' "the text starts with a byte-order mark; save it as plain ASCII" }
        elseif ($txt -cmatch '[^\x00-\x7F]') { Add-Finding "not-ascii" $src '$' "the text holds a character that is not ASCII (CONTRIBUTING 13)" }
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
        # A SUBSCRIPTION GOES ONLY TO ITS VENDOR (review of PR #73, F2). The vendor's own program sends
        # its login to the provider's endpoint, so a harness-login provider may not name one.
        if ($cred.kind -ceq "harness-login" -and $null -ne (Get-HordeAgentProp $pv "endpoint")) { Add-Finding "login-endpoint" $e.source ('$.providers.' + $pv.name) ("the provider " + $pv.name + " uses the harness's own login and names an endpoint; a subscription's login goes only to its vendor's own endpoint") }
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
