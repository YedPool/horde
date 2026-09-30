# core/RestorePlan.ps1 - is a restore plan one a host can be handed?
#
# Step 1.3. schema/restore-plan.v1.json says the shape of a plan. What the subset of JSON Schema
# Horde validates cannot say, Test-HordeRestorePlan says here, and this list is every finding it
# adds:
#
#   nodes     - a node that is both a leaf (slot) and a container (split, ratio or children), or
#               neither; a container with no split, with no children, or with fewer than two; a ratio
#               that is not strictly between 0 and 1 (0 and 1 would give one child the whole space).
#   sessions  - a slot or a sessionId used by two sessions; a parent that names the session itself,
#               or no session in the plan.
#   placement - a layout slot that names no session; a session whose slot is not in the layout; a slot
#               placed more than once.
#
# EVERY SESSION IS PLACED EXACTLY ONCE. Section 4's first degradation rule is "sessions are never
# dropped", and D3 says the session list is authoritative. Checking it on every plan makes the rule
# mechanical: a plan that loses a session, or shows one in two places, is refused before any host
# sees it - so a degraded plan cannot quietly leave a session behind.
#
# THE SCHEMA RUNS FIRST, AND ITS FINDINGS STAND ALONE. The checks here walk the shape the schema
# guarantees; on a plan that fails it they would be reading a shape nobody promised, and would add
# findings about symptoms of the same fault. So a plan the schema refuses gets the schema's findings
# only, and a plan it accepts gets every finding below, not just the first.
#
# Names - slots, session ids - are compared exactly, case included, as the JSON holds them.

# No Set-StrictMode here: this file is dot-sourced, so a file-scope Set-StrictMode would set the
# caller's mode (see core/Tristate.ps1). The functions run under -Version Latest.
. (Join-Path $PSScriptRoot "Schema.ps1")

function Get-HordePlanProp {
    # A property's value, or $null when the object has none - safe under strict mode.
    param($Object, [string]$Name)
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Test-HordePlanNode {
    # One node and everything below it. Placements records, per slot, the paths it is placed at.
    param($Node, [string]$Path, $Placements, $Findings)
    Set-StrictMode -Version Latest
    $slot = $Node.PSObject.Properties["slot"]
    $split = $Node.PSObject.Properties["split"]
    $ratio = $Node.PSObject.Properties["ratio"]
    $children = $Node.PSObject.Properties["children"]
    $isContainer = ($null -ne $split -or $null -ne $ratio -or $null -ne $children)
    if ($null -ne $slot -and $isContainer) {
        # Counted as placed, so the one fault is not reported a second time as a dropped session;
        # its children are not walked, because which of the two it was meant to be is unknown.
        [void]$Findings.Add($Path + " is both a leaf and a container: it has a slot and a split, ratio or children")
        Add-HordePlanPlacement -Placements $Placements -Slot "$($slot.Value)" -Path $Path; return
    }
    if ($null -eq $slot -and -not $isContainer) {
        [void]$Findings.Add($Path + " is neither a leaf nor a container: it has no slot, split or children")
        return
    }
    if ($null -ne $slot) {
        Add-HordePlanPlacement -Placements $Placements -Slot "$($slot.Value)" -Path $Path
        return
    }
    if ($null -eq $split) { [void]$Findings.Add($Path + " is a container with no split") }
    if ($null -ne $ratio) {
        $r = [double]$ratio.Value
        if (-not ($r -gt 0 -and $r -lt 1)) { [void]$Findings.Add($Path + ".ratio is " + $ratio.Value + "; a ratio lies strictly between 0 and 1") }
    }
    if ($null -eq $children) { [void]$Findings.Add($Path + " is a container with no children"); return }
    $kids = @($children.Value)
    if ($kids.Count -lt 2) {
        $noun = "children"; if ($kids.Count -eq 1) { $noun = "child" }
        [void]$Findings.Add($Path + " is a container with " + $kids.Count + " " + $noun + "; a container has at least 2")
    }
    for ($i = 0; $i -lt $kids.Count; $i++) {
        Test-HordePlanNode -Node $kids[$i] -Path ($Path + ".children[" + $i + "]") -Placements $Placements -Findings $Findings
    }
}

function Add-HordePlanPlacement {
    param($Placements, [string]$Slot, [string]$Path)
    if (-not $Placements.ContainsKey($Slot)) { $Placements[$Slot] = New-Object System.Collections.ArrayList }
    [void]$Placements[$Slot].Add($Path)
}

function Test-HordeRestorePlan {
    # Findings for one parsed plan; empty means valid. Schema defaults to schema/restore-plan.v1.
    param($Plan, $Schema = $null)
    Set-StrictMode -Version Latest
    if ($null -eq $Schema) { $Schema = Get-HordeSchema -Name "restore-plan.v1" }
    $bySchema = @(Test-HordeSchema -Value $Plan -Schema $Schema)
    if ($bySchema.Count -gt 0) { return $bySchema }

    $findings = New-Object System.Collections.ArrayList
    # Ordinal dictionaries: a PowerShell hashtable ignores case, and "S1" is not "s1".
    $slotAt = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([System.StringComparer]::Ordinal)
    $idAt = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([System.StringComparer]::Ordinal)
    $sessions = @($Plan.sessions)
    for ($i = 0; $i -lt $sessions.Count; $i++) {
        $slot = "$($sessions[$i].slot)"; $id = "$($sessions[$i].sessionId)"
        if ($slotAt.ContainsKey($slot)) { [void]$findings.Add('$.sessions[' + $i + "].slot '" + $slot + "' is also the slot of " + '$.sessions[' + $slotAt[$slot] + "]") }
        else { $slotAt[$slot] = $i }
        if ($idAt.ContainsKey($id)) { [void]$findings.Add('$.sessions[' + $i + "].sessionId '" + $id + "' is also the sessionId of " + '$.sessions[' + $idAt[$id] + "]") }
        else { $idAt[$id] = $i }
    }
    for ($i = 0; $i -lt $sessions.Count; $i++) {
        $parent = Get-HordePlanProp $sessions[$i] "parent"
        if ($null -eq $parent) { continue }
        if ("$parent" -ceq "$($sessions[$i].sessionId)") { [void]$findings.Add('$.sessions[' + $i + "].parent names the session itself") }
        elseif (-not $idAt.ContainsKey("$parent")) { [void]$findings.Add('$.sessions[' + $i + "].parent '" + $parent + "' names no session in the plan") }
    }

    $placements = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.ArrayList]' ([System.StringComparer]::Ordinal)
    $ws = @($Plan.layout.workspaces)
    for ($w = 0; $w -lt $ws.Count; $w++) {
        $wins = @($ws[$w].windows)
        for ($n = 0; $n -lt $wins.Count; $n++) {
            $tabs = @($wins[$n].tabs)
            for ($t = 0; $t -lt $tabs.Count; $t++) {
                $at = '$.layout.workspaces[' + $w + '].windows[' + $n + '].tabs[' + $t + '].root'
                Test-HordePlanNode -Node $tabs[$t].root -Path $at -Placements $placements -Findings $findings
            }
        }
    }
    foreach ($slot in $placements.Keys) {
        if (-not $slotAt.ContainsKey($slot)) {
            foreach ($p in $placements[$slot]) { [void]$findings.Add($p + " names slot '" + $slot + "', which no session in the plan has") }
        } elseif ($placements[$slot].Count -gt 1) {
            [void]$findings.Add("slot '" + $slot + "' is placed " + $placements[$slot].Count + " times (" + ($placements[$slot] -join ", ") + "); a session is placed exactly once")
        }
    }
    for ($i = 0; $i -lt $sessions.Count; $i++) {
        $slot = "$($sessions[$i].slot)"
        if (-not $placements.ContainsKey($slot)) { [void]$findings.Add('$.sessions[' + $i + "] (slot '" + $slot + "') is not in the layout; a plan never drops a session") }
    }
    return @($findings)
}
