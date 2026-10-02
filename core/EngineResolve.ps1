# core/EngineResolve - which engine, and which setting, one target gets from the layers.
#
# ENGINES PLAN STEP E4 (planning/execution-plan-engines.md; engine-settings design, sections 2, 3 and
# 5, and its "Decisions taken"). A pure function: the layers, already parsed and already checked by
# core/EngineConfig.ps1, and a target in; one answer per setting with its provenance out. It reads no
# file and no environment variable, so nothing a shell inherited can move an answer (decision 1: no
# environment layer).
#
# HOW A SETTING IS CHOSEN, per key of core/config-keys.json, independently of every other key:
#   1. LAYER first. L5 (a spawn) beats L4 (live) beats L3 (the run spec) beats L1 (the user) beats L0
#      (built-in). L2, the project layer, is not built, and is refused.
#   2. SPECIFICITY inside the winning layer. A rule's specificity is the ranks of its match keys,
#      highest first, compared in order and then by length: session 70, fleetId 60, title and label
#      50 (51 when exact, without * or ?), parent 40, run 30, role 20. So {parent} beats {run, role},
#      and {parent, role} beats {parent} (design 3.2; decision 8).
#   3. A TIE that disagrees is unknown, naming every rule in it. Never file order, never last write.
#      A tie that agrees resolves.
# A profile in a rule expands to its harness, provider and model at that rule's layer and
# specificity; a key the same rule sets itself beats the profile's value for it.
#
# MATCHING. Every key of a match must hold for the target; a key the target does not have fails the
# match. role is compared after translating the target's role through core/roles.json (master,
# orchestrator and session are the old names); session and parent are UUIDs and compare ignoring case;
# label and title are globs (* and ?). A live rule whose until is a time already past does not apply;
# run-closed and session-retired are removed by the writer that knows those events (engines E7).
#
# A TUNER RAISES, NEVER LOWERS (decision 9). For a key the registry marks tuner = raise-only, a winning
# rule written by the tuner is refused when its value ranks below what the rules without it give;
# the refusal is recorded, and the value below stands.
#
# THE BINDING, AS A WHOLE (section 5). The model is pinned: an alias becomes the concrete id mapped
# for the resolved provider, and both are recorded; an alias with no entry for that provider is
# unknown, and the alias's name is never passed on. Then the wire-format and subscription rules of E3
# are applied to the resolved pair, because layers that are each clean can combine into a pair that
# is not.
#
# CAPABILITIES. The target role's requirements (core/role-requirements.json) against the resolved
# harness's descriptor, less what the provider lacks, or - for a capability core/capabilities.json
# says either port may give - the host's own declaration. Only yes satisfies; unverified never does.
# The host table is the host port's (core/HostPort.ps1: capability name -> yes, no, declined or
# unverified), passed in by the caller; with none, nothing is satisfied through the host.
#
# FOR REMOTE R9 (issue #67). The resolution carries the resolved descriptor, so a node can map a
# requested permission level with Get-HordePermissionArgs, and any node-policy key the registry gains
# (remote.permissionCeiling) resolves here like every other setting. Verifying a precondition against
# the real environment and reading back the effective mode are R9's.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path $PSScriptRoot "EngineConfig.ps1")
. (Join-Path $PSScriptRoot "ReadShared.ps1")
. (Join-Path $PSScriptRoot "Roles.ps1")

$script:HordeLayerOrder = @{ L0 = 0; L1 = 1; L3 = 3; L4 = 4; L5 = 5 }
$script:HordeMatchRanks = @{ session = 70; fleetId = 60; title = 50; label = 50; parent = 40; run = 30; role = 20 }
$script:HordeBindingKeys = @("harness", "provider", "model")

function Get-HordeRoleRequirements {
    # role -> capability names, from core/role-requirements.json or -Path. Every name must be in the
    # capability vocabulary, so a typo cannot quietly require nothing.
    param([string]$Path = (Join-Path $PSScriptRoot "role-requirements.json"), $Vocabulary = $null)
    if ($null -eq $Vocabulary) { $Vocabulary = @(Get-HordeCapabilityVocabulary) }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    Assert-HordeAsciiBytes -Bytes $bytes -What ("the role requirements at '" + $Path + "'")
    $t = [System.Text.Encoding]::ASCII.GetString($bytes) | ConvertFrom-Json
    $req = Get-HordeAgentProp $t "requires"
    $names = @($Vocabulary | ForEach-Object { $_.name })
    $problems = @()
    foreach ($role in @("warchief", "orc", "goblin")) {
        $list = Get-HordeAgentProp $req $role
        if ($null -eq $list) { $problems += ("the role " + $role + " has no requirement list"); continue }
        foreach ($c in @($list)) { if ($names -cnotcontains $c) { $problems += ("the role " + $role + " requires " + $c + ", which core/capabilities.json does not have") } }
    }
    if ($problems.Count -gt 0) { throw ("the role requirements are malformed: " + ($problems -join "; ")) }
    return $req
}

function Get-HordeRuleSpecificity {
    # The ranks of a match's keys, highest first.
    param($Match)
    $ranks = @()
    foreach ($p in @($Match.PSObject.Properties)) {
        $r = $script:HordeMatchRanks[$p.Name]
        if (($p.Name -ceq "label" -or $p.Name -ceq "title") -and "$($p.Value)" -notmatch '[*?]') { $r = $r + 1 }
        $ranks += $r
    }
    return @($ranks | Sort-Object -Descending)
}

function Compare-HordeSpecificity {
    # 1 when A is more specific than B, -1 when less, 0 when equal.
    param([int[]]$A, [int[]]$B)
    $n = [Math]::Min($A.Count, $B.Count)
    for ($i = 0; $i -lt $n; $i++) { if ($A[$i] -gt $B[$i]) { return 1 }; if ($A[$i] -lt $B[$i]) { return -1 } }
    if ($A.Count -gt $B.Count) { return 1 }
    if ($A.Count -lt $B.Count) { return -1 }
    return 0
}

function Test-HordeRuleMatch {
    # Does every key of the match hold for the target?
    param($Match, [hashtable]$Target)
    foreach ($p in @($Match.PSObject.Properties)) {
        if (-not $Target.ContainsKey($p.Name) -or $null -eq $Target[$p.Name] -or "$($Target[$p.Name])" -eq "") { return $false }
        $want = "" + $p.Value
        $have = "" + $Target[$p.Name]
        switch ($p.Name) {
            "session" { if ($want -ine $have) { return $false } }
            "parent" { if ($want -ine $have) { return $false } }
            "label" { if (-not ($have -clike $want)) { return $false } }
            "title" { if (-not ($have -clike $want)) { return $false } }
            default { if ($want -cne $have) { return $false } }
        }
    }
    return $true
}

function Get-HordeEngineSetting {
    # One setting of a resolution, by key: { key; answer; layer; source; rule; match; via; beaten; refused }.
    param([Parameter(Mandatory = $true)]$Resolution, [Parameter(Mandatory = $true)][string]$Key)
    if (-not $Resolution.settings.Contains($Key)) { throw ("'" + $Key + "' is not a setting of core/config-keys.json") }
    return $Resolution.settings[$Key]
}

function Resolve-HordeEngine {
    # Resolve every setting for one target, then the binding and the role's capabilities.
    # -Layers: { layer; source; doc } each, doc a parsed schema/engine-config.v1 document.
    # -Target: role, and any of parent, run, fleetId, session, label, title.
    param([Parameter(Mandatory = $true)][object[]]$Layers, [Parameter(Mandatory = $true)][hashtable]$Target,
        [Parameter(Mandatory = $true)]$Descriptors, $Registry = $null, $Requirements = $null, $HostCapabilities = $null,
        [datetime]$Now = [datetime]::UtcNow, $Vocabulary = $null)
    if ($null -eq $Registry) { $Registry = @(Get-HordeConfigKeys) }
    if ($null -eq $Vocabulary) { $Vocabulary = @(Get-HordeCapabilityVocabulary) }
    if ($null -eq $Requirements) { $Requirements = Get-HordeRoleRequirements -Vocabulary $Vocabulary }
    if ($null -eq $HostCapabilities) { $HostCapabilities = @{} }
    $nowUtc = $Now.ToUniversalTime()

    # The target, its role in the native vocabulary.
    $tgt = @{}
    foreach ($k in @($Target.Keys)) { $tgt[$k] = $Target[$k] }
    if ($tgt.ContainsKey("role") -and $null -ne $tgt["role"]) {
        $rr = Resolve-HordeRole -Raw $tgt["role"]
        if ($rr.role.state -eq "known") { $tgt["role"] = $rr.role.value } else { $tgt.Remove("role") }
    }

    # Definitions, from the built-in and user layers.
    $providers = @{}; $aliases = @{}; $profiles = @{}
    foreach ($l in @($Layers)) {
        if ($l.layer -ceq "L2") { throw "the project layer (L2) is not built; a project file cannot be resolved" }
        if (-not $script:HordeLayerOrder.ContainsKey("" + $l.layer)) { throw ("'" + $l.layer + "' is not a configuration layer") }
        if (@("L0", "L1") -cnotcontains $l.layer) { continue }
        foreach ($p in @(Get-HordeConfigItems $l.doc "providers")) { $providers[$p.name] = $p }
        foreach ($a in @(Get-HordeConfigItems $l.doc "aliases")) { $aliases[$a.name] = $a }
        foreach ($p in @(Get-HordeConfigItems $l.doc "profiles")) { $profiles[$p.name] = $p }
    }

    # Every applicable rule, expanded into (key, value) candidates.
    $cands = New-Object System.Collections.ArrayList
    foreach ($l in @($Layers)) {
        foreach ($r in @(Get-HordeConfigItems $l.doc "rules")) {
            $until = Get-HordeAgentProp $r "until"
            if ($null -ne $until -and "$until" -match '^[0-9]{4}-') {
                $t = [datetime]::Parse("$until", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal)
                if ($t -le $nowUtc) { continue }
            }
            if (-not (Test-HordeRuleMatch -Match $r.match -Target $tgt)) { continue }
            $spec = @(Get-HordeRuleSpecificity -Match $r.match)
            $values = [ordered]@{}
            $via = @{}
            $pn = Get-HordeAgentProp $r.set "profile"
            if ($null -ne $pn -and $profiles.ContainsKey($pn)) {
                $prof = $profiles[$pn]
                foreach ($k in $script:HordeBindingKeys) { $v = Get-HordeAgentProp $prof $k; if ($null -ne $v) { $values[$k] = $v; $via[$k] = $pn } }
            }
            foreach ($p in @($r.set.PSObject.Properties)) { if ($p.Name -cne "profile") { $values[$p.Name] = $p.Value; $via.Remove($p.Name) } }
            if ($null -ne $pn) { $values["profile"] = $pn }
            foreach ($k in @($values.Keys)) {
                [void]$cands.Add([pscustomobject]@{ key = $k; value = $values[$k]; layer = $l.layer; rank = $script:HordeLayerOrder[$l.layer]; spec = $spec; source = $l.source; rule = $r.id; match = $r.match; by = $r.writtenBy; via = $via[$k] })
            }
        }
    }

    function Select-HordeWinner {
        # The winning candidates of a list: the highest layer, then the most specific. Returns the
        # top group (one or more) and the rest.
        param([object[]]$List)
        if ($List.Count -eq 0) { return [pscustomobject]@{ top = @(); rest = @() } }
        $maxRank = ($List | Measure-Object -Property rank -Maximum).Maximum
        $inLayer = @($List | Where-Object { $_.rank -eq $maxRank })
        $best = $inLayer[0]
        foreach ($c in $inLayer) { if ((Compare-HordeSpecificity -A $c.spec -B $best.spec) -gt 0) { $best = $c } }
        $top = @($inLayer | Where-Object { (Compare-HordeSpecificity -A $_.spec -B $best.spec) -eq 0 })
        $rest = @($List | Where-Object { $top -notcontains $_ })
        return [pscustomobject]@{ top = $top; rest = $rest }
    }

    $settings = [ordered]@{}
    foreach ($entry in @($Registry)) {
        $key = "" + $entry.name
        $mine = @($cands | Where-Object { $_.key -ceq $key })
        $refused = @()
        $pick = Select-HordeWinner -List $mine
        $raiseOnly = ("" + (Get-HordeAgentProp $entry "tuner")) -ceq "raise-only"
        if ($raiseOnly -and $pick.top.Count -gt 0 -and @($pick.top | Where-Object { $_.by -ceq "tuner" }).Count -gt 0) {
            $values = @(Get-HordeConfigItems $entry.value "values")
            $without = Select-HordeWinner -List @($mine | Where-Object { $_.by -cne "tuner" })
            $agreed = @($without.top | ForEach-Object { "" + $_.value } | Select-Object -Unique)
            if ($agreed.Count -eq 1) {
                $floor = [array]::IndexOf($values, $agreed[0])
                $low = @($pick.top | Where-Object { $_.by -ceq "tuner" -and [array]::IndexOf($values, ("" + $_.value)) -lt $floor })
                if ($low.Count -gt 0) {
                    foreach ($c in $low) { $refused += [pscustomobject]@{ rule = $c.rule; layer = $c.layer; source = $c.source; value = $c.value; why = "refused: a tuner may only raise this setting, and " + $c.value + " is below " + $agreed[0] } }
                    $mine = @($mine | Where-Object { $low -notcontains $_ })
                    $pick = Select-HordeWinner -List $mine
                }
            }
        }
        $beaten = @(foreach ($c in $pick.rest) { [pscustomobject]@{ rule = $c.rule; layer = $c.layer; source = $c.source; value = $c.value; why = $(if ($c.rank -lt $pick.top[0].rank) { "lower layer" } else { "less specific" }) } })
        $answer = $null; $win = $null
        if ($pick.top.Count -eq 0) { $answer = New-HordeAbsent -Note ("no rule sets " + $key + " for this target") }
        else {
            $distinct = @($pick.top | ForEach-Object { "" + $_.value } | Select-Object -Unique)
            if ($distinct.Count -gt 1) {
                $answer = New-HordeUnknown -Reason ("equally specific rules in " + $pick.top[0].layer + " disagree on " + $key + ": " + (@($pick.top | ForEach-Object { $_.rule + " (" + $_.source + ") says " + $_.value }) -join ", "))
            } else { $win = $pick.top[0]; $answer = New-HordeKnown -Value $win.value }
        }
        $settings[$key] = [pscustomobject]@{
            key = $key; answer = $answer
            layer = $(if ($win) { $win.layer } else { $null }); source = $(if ($win) { $win.source } else { $null })
            rule = $(if ($win) { $win.rule } else { $null }); match = $(if ($win) { $win.match } else { $null }); via = $(if ($win) { $win.via } else { $null })
            beaten = $beaten; refused = $refused
        }
    }

    # The binding, pinned and checked whole.
    $binding = $null; $desc = $null; $pv = $null
    $h = $settings["harness"].answer; $p = $settings["provider"].answer; $m = $settings["model"].answer
    if ($h.state -ne "known") { $binding = New-HordeUnknown -Reason ("the harness is not resolved: " + $(if ($h.state -eq "absent") { $h.reason } else { $h.reason })) }
    elseif ($p.state -ne "known") { $binding = New-HordeUnknown -Reason ("the provider is not resolved: " + $p.reason) }
    elseif ($m.state -eq "unknown") { $binding = New-HordeUnknown -Reason ("the model is not resolved: " + $m.reason) }
    elseif (-not $Descriptors.Contains($h.value)) { $binding = New-HordeUnknown -Reason ("the harness " + $h.value + " has no descriptor") }
    elseif (-not $providers.ContainsKey($p.value)) { $binding = New-HordeUnknown -Reason ("the provider " + $p.value + " is not defined") }
    else {
        $desc = $Descriptors[$h.value]; $pv = $providers[$p.value]
        $model = $null; $alias = $null
        if ($m.state -eq "known") {
            $model = "" + $m.value
            if ($aliases.ContainsKey($model)) {
                $entry = @(@($aliases[$model].map) | Where-Object { $_.provider -ceq $pv.name })
                if ($entry.Count -eq 0) { $binding = New-HordeUnknown -Reason ("the alias " + $model + " has no entry for the provider " + $pv.name + "; the alias's name is never passed to a provider") }
                else { $alias = $model; $model = $entry[0].model }
            }
        }
        if ($null -eq $binding) {
            $allow = Get-HordeAgentProp $pv "models"
            if (@($desc.protocols) -cnotcontains $pv.protocol) { $binding = New-HordeUnknown -Reason ("the harness " + $h.value + " does not speak " + $pv.protocol + ", the protocol of the provider " + $pv.name) }
            elseif ($pv.credential.kind -ceq "harness-login" -and $desc.nativeProvider -cne $pv.name) { $binding = New-HordeUnknown -Reason ("the provider " + $pv.name + " runs on its own login, and the harness " + $h.value + "'s native provider is " + $desc.nativeProvider + "; a subscription runs only on its vendor's own program") }
            elseif ($null -ne $model -and $null -ne $allow -and @($allow) -cnotcontains $model) { $binding = New-HordeUnknown -Reason ("the model " + $model + " is not in the allowlist of the provider " + $pv.name) }
            else { $binding = New-HordeKnown -Value ([pscustomobject]@{ harness = $h.value; provider = $pv.name; model = $model; alias = $alias }) }
        }
    }

    # The role's capabilities.
    $caps = $null
    if (-not $tgt.ContainsKey("role")) { $caps = New-HordeUnknown -Reason "the target has no role Horde knows, so its requirements are not known" }
    elseif ($null -eq $desc) { $caps = New-HordeUnknown -Reason ("the binding is not resolved, so its capabilities cannot be checked: " + $binding.reason) }
    else {
        $missing = New-Object System.Collections.ArrayList
        $lacks = @(Get-HordeConfigItems $pv "lacks")
        foreach ($c in @(Get-HordeConfigItems $Requirements $tgt["role"])) {
            $row = @($Vocabulary | Where-Object { $_.name -ceq $c })[0]
            $agentYes = (Test-HordeAgentCapability -Descriptor $desc -Name $c) -and ($lacks -cnotcontains $c)
            $hostYes = $false
            if ($null -ne $row -and $row.port -cne "agent" -and $null -ne $row.host -and $HostCapabilities.ContainsKey($row.host)) { $hostYes = ("" + $HostCapabilities[$row.host]) -ceq "yes" }
            if ($agentYes -or $hostYes) { continue }
            $why = ""
            if ($lacks -ccontains $c) { $why = "the provider " + $pv.name + " lacks it" }
            else { $why = "the harness " + $h.value + " declares it " + $desc.capabilities.$c.support + ": " + $desc.capabilities.$c.evidence }
            if ($null -ne $row -and $row.port -ceq "either") { $why += "; nor does the host give " + $row.host }
            [void]$missing.Add([pscustomobject]@{ name = $c; why = $why })
        }
        $caps = New-HordeKnown -Value ([pscustomobject]@{ ok = [bool]($missing.Count -eq 0); missing = $missing.ToArray() })
    }

    return [pscustomobject]@{ target = $tgt; settings = $settings; binding = $binding; descriptor = $desc; capabilities = $caps }
}
