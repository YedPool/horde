# test/lib/RecordDrift.ps1 - does a stored-record schema hold exactly one owner's fields?
#
# Shared by test/test-schema-session-record.ps1 (the fleet record, owner engine) and
# test/test-schema-session-binding.ps1 (the binding record, owner node). Remote plan step R10 split
# the one stored record into those two, each written by one owner: the fleet record only by the hub's
# engine, the binding record only by the engine on the device that runs the session. Each record's
# field list is never written down; it is computed from core/ownership.json on every run, so a field
# whose owner changes must move from one schema to the other, or both suites fail.
#
# Not a suite: dot-sourced by the two above, after core/Ownership.ps1.

# THE FIELDS EACH RECORD HOLDS THAT THE OWNERSHIP TABLE DOES NOT OWN, with the owner each schema
# names for them, kept here once so a later edit (engines K1 changes the key) is one edit. sessionId
# is the key that names both records. device, in the fleet record only, says which machine the
# session runs on; it is not a fact of the session, and enters the table with the session view at
# remote plan R13.
$script:HordeFleetRecordKeys = @{ sessionId = "agent"; device = "engine" }
$script:HordeBindingRecordKeys = @{ sessionId = "agent" }

function Get-HordeReadOrder {
    # The ownership table's read precedence for one field, in the form the schemas document it: store
    # and field only. A store's guard and a read's `when` clause are left out on purpose - the schemas
    # say so, and core/ownership.json is where they are read - so a changed guard or when is not
    # drift here; test/test-ownership.ps1 owns those.
    param($Field)
    return ((@($Field.read) | ForEach-Object { "$($_.store) $($_.field)" }) -join ", then ")
}

function Get-HordeRecordDrift {
    # Every way a record schema and the ownership table disagree about what -Owner stores. Empty means
    # they agree. Takes both as arguments so the controls can hand it a changed copy.
    #
    # -Keys names the schema's properties the ownership table does not own ($HordeFleetRecordKeys or
    # $HordeBindingRecordKeys above), compared apart: each is checked only for its declared owner
    # here; the suites check its shape.
    param($Own, $Schema, [Parameter(Mandatory = $true)][string]$Owner, [hashtable]$Keys = @{ sessionId = "agent" })
    $out = New-Object System.Collections.ArrayList
    $props = @{}
    foreach ($p in @($Schema.properties.PSObject.Properties)) { $props[$p.Name] = $p.Value }
    # WHAT BELONGS IN THIS RECORD, computed and never listed: this owner, and no derived mark.
    $expected = @($Own.fields | Where-Object { "$($_.owner)" -ceq $Owner -and $null -eq $_.PSObject.Properties["derived"] -and -not $Keys.ContainsKey("$($_.name)") } | ForEach-Object { "$($_.name)" })
    $stored = @($props.Keys | Where-Object { $_ -cne "schemaVersion" -and -not $Keys.ContainsKey($_) })
    foreach ($n in $expected) { if ($stored -cnotcontains $n) { [void]$out.Add("'" + $n + "' is owned by the " + $Owner + " and not derived, but the schema does not store it") } }
    foreach ($n in $stored) {
        if ($expected -ccontains $n) { continue }
        $f = Get-HordeOwnershipField -Doc $Own -Name $n
        if ($null -eq $f) { [void]$out.Add("'" + $n + "' is stored, but the ownership table has no such field") }
        elseif ("$($f.owner)" -cne $Owner) { [void]$out.Add("'" + $n + "' is stored, but its owner is " + $f.owner + ", not the " + $Owner) }
        else { [void]$out.Add("'" + $n + "' is stored, but it is derived: " + $f.derived) }
    }
    # A DROPPED FIELD IS NOT CARRIED. Read from the table, so a field dropped later is covered too.
    foreach ($d in @($Own.dropped | Where-Object { $null -ne $_ })) {
        if ($props.ContainsKey("$($d.name)")) { [void]$out.Add("'" + $d.name + "' is dropped by the ownership table but stored by the schema") }
    }
    # A STORED FIELD IS NEVER PROVISIONAL. The table marks a rule provisional when it rests on
    # something unmeasured; a record stores a plain value and has nowhere to carry that mark, so a
    # stored provisional value would read as fact.
    foreach ($n in $expected) {
        $f = Get-HordeOwnershipField -Doc $Own -Name $n
        if ($null -ne $f.PSObject.Properties["provisional"]) { [void]$out.Add("'" + $n + "' is provisional in the ownership table (" + $f.provisional + "), and the stored record has no way to mark it") }
    }
    # EACH STORED FIELD SAYS WHO WRITES IT AND HOW IT IS READ UNTIL THE SWITCH, as the table does.
    foreach ($n in $stored) {
        $f = Get-HordeOwnershipField -Doc $Own -Name $n
        if ("$($props[$n].'x-horde-owner')" -cne $Owner) { [void]$out.Add("'" + $n + "' does not carry x-horde-owner " + $Owner) }
        if ($null -ne $f -and "$($props[$n].'x-horde-read')" -cne (Get-HordeReadOrder $f)) { [void]$out.Add("'" + $n + "' documents a read order that is not the ownership table's (" + (Get-HordeReadOrder $f) + ")") }
    }
    # THE KEYS: present, and each names its declared owner. sessionId's must also be the table's.
    foreach ($k in @($Keys.Keys)) {
        if (-not $props.ContainsKey($k)) { [void]$out.Add("the schema has no " + $k); continue }
        if ("$($props[$k].'x-horde-owner')" -cne "$($Keys[$k])") { [void]$out.Add($k + "'s x-horde-owner is not " + $Keys[$k]) }
    }
    if ($Keys.ContainsKey("sessionId")) {
        $sid = Get-HordeOwnershipField -Doc $Own -Name "sessionId"
        if ($null -eq $sid) { [void]$out.Add("the ownership table has no sessionId") }
        elseif ("$($sid.owner)" -cne "$($Keys['sessionId'])") { [void]$out.Add("sessionId's owner in the ownership table is " + $sid.owner + ", not the " + $Keys['sessionId']) }
    }
    return @($out)
}
