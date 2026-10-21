# core/NodeDeliverTo - which of this node's sessions its owner opts in to remote delivery, from its own layers.
#
# WHY (remote plan steps R9 and R21; decided 2026-10-05, and amended: one source of node configuration).
# A deliver may reach a session the hub spawned, or one whose label the node's own remote.deliverTo
# lists. The list is the node owner's word, exactly like remote.permissionCeiling: core/config-keys.json
# allows it only in L1 and L4, the node's own layers, <HordeHome>\engine.json and engine-live.json. They
# are read by the node's ONE layer reader, core/NodeEngineLayers.ps1's Get-HordeNodeEngineLayers, which the spawn
# path uses too and which runs the configuration checker over them, so a run spec or a spawn setting the
# key is a problem there; never from the link, and - like every setting (engine-settings decision 1) -
# never from an environment variable. A live rule (L4) beats L1, as a higher layer does in
# core/EngineResolve.ps1, and an empty value withdraws every opt-in.
#
# NODE-WIDE. The list belongs to the node, not to a target, so a rule that sets it for a match is refused
# rather than resolved for some target and not another. Two rules of one layer that disagree are unknown,
# naming both. ANY PROBLEM THE READER FOUND, in any layer, is unknown with its text, and the node then
# refuses EVERY deliver (remote/NodeServe.ps1), as the same problems refuse every spawn (cli/NodeAct.ps1).
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path $PSScriptRoot "JsonText.ps1")
. (Join-Path $PSScriptRoot "EngineConfig.ps1")

$script:HordeDeliverToKey = "remote.deliverTo"
# The layers the list may come from, highest first (core/config-keys.json says the same; this is the second line).
$script:HordeDeliverToLayers = @("L4", "L1")

function Get-HordeNodeDeliverTo {
    # The labels this node opts in to remote delivery, as a tristate answer: known (possibly empty), or
    # unknown with the reason. -Layers and -Problems are the node's one layer reader's answer
    # (Get-HordeNodeEngineLayers: { layers; problems }), every layer already checked by it.
    param([object[]]$Layers = @(), [object[]]$Problems = @())
    $bad = @($Problems | Where-Object { "$_" -ne "" })
    if ($bad.Count -gt 0) {
        return (New-HordeUnknown -Reason ("the node's engine configuration fails its checks, so it opts nothing in: " + ($bad -join " | ")))
    }
    $byLayer = @{}
    foreach ($d in @($Layers | Where-Object { $null -ne $_ })) {
        $parsed = $d.doc
        if ($null -eq $parsed) { $parsed = ConvertFrom-HordeJson -Text ("$($d.text)") }
        foreach ($r in @(Get-HordeConfigItems $parsed "rules")) {
            $p = $r.set.PSObject.Properties[$script:HordeDeliverToKey]
            if ($null -eq $p) { continue }
            if (@($r.match.PSObject.Properties).Count -gt 0) {
                return (New-HordeUnknown -Reason ($script:HordeDeliverToKey + " is node-wide, but the rule " + $r.id + " sets it for a match; no label is opted in"))
            }
            # The second line: the reader's checker already refuses the key outside L1 and L4.
            if ($script:HordeDeliverToLayers -cnotcontains "$($d.layer)") { return (New-HordeUnknown -Reason ($script:HordeDeliverToKey + " is set in " + $d.layer + ", and only the node's own layers (" + ($script:HordeDeliverToLayers -join ", ") + ") may set it")) }
            if (-not $byLayer.ContainsKey("$($d.layer)")) { $byLayer["$($d.layer)"] = @{} }
            $byLayer["$($d.layer)"]["" + $r.id] = "" + $p.Value
        }
    }
    # The highest layer that sets it decides (L4 over L1).
    $values = @{}
    foreach ($l in $script:HordeDeliverToLayers) { if ($byLayer.ContainsKey($l)) { $values = $byLayer[$l]; break } }
    $distinct = @($values.Values | Sort-Object -Unique -CaseSensitive)
    if ($distinct.Count -gt 1) {
        return (New-HordeUnknown -Reason ("the rules " + ((@($values.Keys) | Sort-Object) -join ", ") + " set " + $script:HordeDeliverToKey + " to different lists; no label is opted in"))
    }
    if ($distinct.Count -eq 0 -or $distinct[0] -eq "") { return (New-HordeKnown -Value @() -ObservedAt ([datetime]::UtcNow)) }
    return (New-HordeKnown -Value @($distinct[0].Split(",")) -ObservedAt ([datetime]::UtcNow))
}
