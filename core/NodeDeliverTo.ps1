# core/NodeDeliverTo - which of this node's sessions its owner opts in to remote delivery, from its own L1.
#
# WHY (remote plan steps R9 and R21; decided 2026-10-05). A deliver may reach a session the hub spawned,
# or one whose label the node's own remote.deliverTo lists. The list is the node owner's word: it is read
# ONLY from L1, the node's own configuration (core/config-keys.json allows the key there alone, so the
# configuration checker refuses it in a run spec, a live rule or a spawn), never from the link, and - like
# every setting (engine-settings decision 1) - never from an environment variable.
#
# NODE-WIDE. The list belongs to the node, not to a target, so a rule that sets it for a match is refused
# rather than resolved for some target and not another. Two rules that disagree are unknown, naming both.
# Anything doubtful opts nothing in: the answer is unknown with the reason, and the node then delivers
# only to sessions the hub spawned.
#
# WHERE L1 LIVES on a node: <HordeHome>\config\user.json (Get-HordeNodeConfigDocuments), a
# schema/engine-config.v1 document. PROVISIONAL: no step has named the user layer's file yet; this is the
# one place that names it, so the step that does moves one line.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path $PSScriptRoot "EngineConfig.ps1")

$script:HordeDeliverToKey = "remote.deliverTo"
$script:HordeNodeConfigFile = "config\user.json"

function Get-HordeNodeConfigDocuments {
    # The node's own configuration as checker documents ({ layer; source; text }): its L1 file when there is
    # one, else none.
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    $path = Join-Path $HordeHome $script:HordeNodeConfigFile
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }
    return @([pscustomobject]@{ layer = "L1"; source = $path; text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) })
}

function Get-HordeNodeDeliverTo {
    # The labels this node opts in to remote delivery, as a tristate answer: known (possibly empty), or
    # unknown with the reason when the configuration is refused or doubtful.
    param([object[]]$Documents = @(), $Descriptors = $null)
    $docs = @($Documents | Where-Object { $null -ne $_ })
    if ($docs.Count -eq 0) { return (New-HordeKnown -Value @() -ObservedAt ([datetime]::UtcNow)) }
    $findings = @(Test-HordeEngineConfig -Documents $docs -Descriptors $Descriptors | Where-Object { "$($_.severity)" -ceq "error" })
    if ($findings.Count -gt 0) {
        return (New-HordeUnknown -Reason ("the node's configuration is refused, so no label is opted in: " + $findings[0].code + " at " + $findings[0].path + ": " + $findings[0].detail))
    }
    $values = @{}
    foreach ($d in $docs) {
        $parsed = $d.text | ConvertFrom-Json
        foreach ($r in @(Get-HordeConfigItems $parsed "rules")) {
            $p = $r.set.PSObject.Properties[$script:HordeDeliverToKey]
            if ($null -eq $p) { continue }
            if (@($r.match.PSObject.Properties).Count -gt 0) {
                return (New-HordeUnknown -Reason ($script:HordeDeliverToKey + " is node-wide, but the rule " + $r.id + " sets it for a match; no label is opted in"))
            }
            $values["" + $r.id] = "" + $p.Value
        }
    }
    $distinct = @($values.Values | Sort-Object -Unique -CaseSensitive)
    if ($distinct.Count -gt 1) {
        return (New-HordeUnknown -Reason ("the rules " + ((@($values.Keys) | Sort-Object) -join ", ") + " set " + $script:HordeDeliverToKey + " to different lists; no label is opted in"))
    }
    if ($distinct.Count -eq 0) { return (New-HordeKnown -Value @() -ObservedAt ([datetime]::UtcNow)) }
    return (New-HordeKnown -Value @($distinct[0].Split(",")) -ObservedAt ([datetime]::UtcNow))
}
