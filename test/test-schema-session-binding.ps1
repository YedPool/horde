# DOES schema/session-binding.v1 DESCRIBE EXACTLY THE BINDING RECORD A NODE STORES?
#
# Remote plan step R10. The stored session record is split in two, each with one writer: the fleet
# record (schema/session-record.v1), written only by the hub's engine, and this binding record,
# written only by the engine on the device that runs the session - owner `node` in
# core/ownership.json - and stored on that device; the hub keeps a read-only mirror (R13). A local
# session is the same split with both writers on one machine.
#
# As for the fleet record (test/test-schema-session-record.ps1), the field list is never written
# here: it is computed from the ownership table on every run, by test/lib/RecordDrift.ps1. A field
# whose owner moves between engine and node must move between the two schemas, and no field may be
# in both.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\Schema.ps1")
. (Join-Path $root "core\Ownership.ps1")
. (Join-Path $root "core\ReadShared.ps1")
. (Join-Path $root "test\lib\RecordDrift.ps1")

$schemaPath = Join-Path $root "schema\session-binding.v1.json"
$schemaText = Get-Content -LiteralPath $schemaPath -Raw
$schema = Get-HordeSchema -Name "session-binding.v1"
$fleet = Get-HordeSchema -Name "session-record.v1"
$own = Get-HordeOwnership
# The binding record has one key, the agent's session id. It has no device: it is stored on the
# device that runs the session, and the hub's mirror files it under that device (R13).
$bindingKeys = $script:HordeBindingRecordKeys
$fleetKeys = $script:HordeFleetRecordKeys

function Copy-HordeJson { param($Value) return (($Value | ConvertTo-Json -Depth 30) | ConvertFrom-Json) }
function Drifts { param($O, $S, [string]$Like) return (@(Get-HordeRecordDrift -Own $O -Schema $S -Owner "node" -Keys $bindingKeys | Where-Object { $_ -like $Like }).Count -gt 0) }

Write-Host ""
Write-Host "--- the schema stores exactly the node's own, non-derived fields ---" -ForegroundColor Cyan
Check ($null -ne $own.owners.PSObject.Properties["node"] -and "$($own.owners.node)".Trim() -ne "") "the ownership table lists the owner node, and says what it is"
$nodeNames = @($own.fields | Where-Object { "$($_.owner)" -ceq "node" -and $null -eq $_.PSObject.Properties["derived"] } | ForEach-Object { "$($_.name)" })
Check ($nodeNames.Count -ge 1) ("CONTROL: the table gives the node fields to store (" + $nodeNames.Count + ": " + ($nodeNames -join ", ") + ")")
Check ($nodeNames -ccontains "projectCwd") "projectCwd is the node's: the launch directory is a fact of the machine the session runs on"
$notNode = @("lastSeen", "lastTool", "spawnedAt" | Where-Object { $nodeNames -cnotcontains $_ })
Check ($notNode.Count -eq 0) ("lastSeen, lastTool and spawnedAt are the node's: only the session's own machine observes them, and a hub copy would freeze when the link drops (" + ($notNode -join ", ") + ")")
$drift = @(Get-HordeRecordDrift -Own $own -Schema $schema -Owner "node" -Keys $bindingKeys)
Check ($drift.Count -eq 0) ("the schema and the ownership table agree (" + ($drift -join "; ") + ")")
$dups = @(Find-HordeJsonDuplicateKey -Text $schemaText)
Check ($dups.Count -eq 0) ("the schema's text repeats no key in one object (" + ($dups -join "; ") + ")")
$wantRequired = (@(@("schemaVersion") + @($bindingKeys.Keys)) | Sort-Object) -join ","
Check (((@($schema.required) | Sort-Object) -join ",") -ceq $wantRequired) ("only schemaVersion and the record's key are required (" + $wantRequired + "): a field not set is absent")
Check ("$($schema.'$id')" -ceq "horde/schema/session-binding.v1") "the schema's id is its own name, not the fleet record's"
Check ($schema.additionalProperties -is [bool] -and $schema.additionalProperties -eq $false) "the schema allows no field it does not name"
Check ((@($schema.properties.schemaVersion.enum) -join ",") -ceq "1" -and $schema.properties.schemaVersion.type -ceq "integer") "schemaVersion is the integer 1"
Check ("$($schema.properties.sessionId.pattern)" -ceq "$($fleet.properties.sessionId.pattern)") "the session id has the fleet record's shape, so one id names both halves"
Check ($null -eq $schema.properties.PSObject.Properties["device"]) "the binding record carries no device: it lives on the device it describes"

Write-Host ""
Write-Host "--- every engine or node field is in exactly one of the two records ---" -ForegroundColor Cyan
function Get-HordeRecordSplitFindings {
    # Every stored field of either owner that is in neither schema or in both. Keys are left out: the
    # session id names both records on purpose.
    param($Own, $Fleet, $Binding)
    $out = New-Object System.Collections.ArrayList
    $inFleet = @($Fleet.properties.PSObject.Properties | ForEach-Object { $_.Name })
    $inBinding = @($Binding.properties.PSObject.Properties | ForEach-Object { $_.Name })
    foreach ($f in @($Own.fields | Where-Object { ("$($_.owner)" -ceq "engine" -or "$($_.owner)" -ceq "node") -and $null -eq $_.PSObject.Properties["derived"] -and "$($_.name)" -cne "sessionId" })) {
        $n = "$($f.name)"
        $a = $inFleet -ccontains $n
        $b = $inBinding -ccontains $n
        if ($a -and $b) { [void]$out.Add("'" + $n + "' is in both records") }
        elseif (-not $a -and -not $b) { [void]$out.Add("'" + $n + "' is in neither record") }
    }
    return @($out)
}
$split = @(Get-HordeRecordSplitFindings -Own $own -Fleet $fleet -Binding $schema)
Check ($split.Count -eq 0) ("each stored field is in exactly one record (" + ($split -join "; ") + ")")
$b2 = Copy-HordeJson $schema; $b2.properties | Add-Member -NotePropertyName role -NotePropertyValue ([pscustomobject]@{ type = "string"; "x-horde-owner" = "node" })
Check (@(Get-HordeRecordSplitFindings -Own $own -Fleet $fleet -Binding $b2 | Where-Object { $_ -like "'role' is in both records" }).Count -eq 1) "CONTROL: a field in both records is found"
$b3 = Copy-HordeJson $schema; $b3.properties.PSObject.Properties.Remove("projectCwd")
Check (@(Get-HordeRecordSplitFindings -Own $own -Fleet $fleet -Binding $b3 | Where-Object { $_ -like "'projectCwd' is in neither record" }).Count -eq 1) "CONTROL: a field in neither record is found"
# THE FLEET RECORD AGREES TOO, with its keys, so the split is checked from both sides in one place.
Check (@(Get-HordeRecordDrift -Own $own -Schema $fleet -Owner "engine" -Keys $fleetKeys).Count -eq 0) "the fleet record holds exactly the engine's fields at the same time"

Write-Host ""
Write-Host "--- a field has one owner, so it can be in only one record ---" -ForegroundColor Cyan
$o = Copy-HordeJson $own; (Get-HordeOwnershipField -Doc $o -Name "projectCwd").owner = @("engine", "node")
Check (@(Test-HordeOwnership -Doc $o | Where-Object { $_ -like "*'projectCwd' names more than one owner*" }).Count -eq 1) "a row with both owners is refused by the ownership gate"
$o = Copy-HordeJson $own; $o.owners.PSObject.Properties.Remove("node")
Check (@(Test-HordeOwnership -Doc $o | Where-Object { $_ -like "*'projectCwd' names owner 'node', which is not one of the listed owners*" }).Count -eq 1) "CONTROL: without the owner node listed, the node's field is refused"

Write-Host ""
Write-Host "--- the drift check notices each way the two can part ---" -ForegroundColor Cyan
$s = Copy-HordeJson $schema; $s.properties | Add-Member -NotePropertyName role -NotePropertyValue ([pscustomobject]@{ type = "string"; "x-horde-owner" = "node" })
Check (Drifts $own $s "'role' is stored, but its owner is engine*") "a fleet field in the binding record is noticed"
$s = Copy-HordeJson $schema; $s.properties | Add-Member -NotePropertyName device -NotePropertyValue ([pscustomobject]@{ type = "string"; "x-horde-owner" = "engine" })
Check (Drifts $own $s "'device' is stored, but the ownership table has no such field") "the fleet record's device key in the binding record is noticed"
$s = Copy-HordeJson $schema; $s.properties.PSObject.Properties.Remove("projectCwd")
Check (Drifts $own $s "'projectCwd' is owned by the node*") "a node field removed from the schema is noticed"
$o = Copy-HordeJson $own; (Get-HordeOwnershipField -Doc $o -Name "projectCwd").owner = "engine"
Check (Drifts $o $schema "'projectCwd' is stored, but its owner is engine*") "a field whose owner leaves the node must leave the binding record"
$o = Copy-HordeJson $own; $o.fields = @($o.fields) + @([pscustomobject]@{ name = "newThing"; owner = "node"; read = @() })
Check (Drifts $o $schema "'newThing' is owned by the node*") "a node field added to the table must be added to the binding record"
$o = Copy-HordeJson $own; (Get-HordeOwnershipField -Doc $o -Name "projectCwd") | Add-Member -NotePropertyName derived -NotePropertyValue "from somewhere"
Check (Drifts $o $schema "'projectCwd' is stored, but it is derived*") "a node field that becomes derived must leave the binding record"
$o = Copy-HordeJson $own; (Get-HordeOwnershipField -Doc $o -Name "projectCwd") | Add-Member -NotePropertyName provisional -NotePropertyValue "unmeasured"
Check (Drifts $o $schema "'projectCwd' is provisional*") "a stored node field that becomes provisional is noticed"
$o = Copy-HordeJson $own; (Get-HordeOwnershipField -Doc $o -Name "projectCwd").read = @([pscustomobject]@{ store = "W1"; field = "firstCwd" })
Check (Drifts $o $schema "'projectCwd' documents a read order*") "a read order changed in the table is noticed in the schema's documentation"
$s = Copy-HordeJson $schema; $s.properties.projectCwd.'x-horde-owner' = "engine"
Check (Drifts $own $s "'projectCwd' does not carry x-horde-owner node") "a stored field that names another owner is noticed"
$s = Copy-HordeJson $schema; $s.properties.sessionId.'x-horde-owner' = "node"
Check (Drifts $own $s "sessionId's x-horde-owner is not agent") "the key naming another owner is noticed"
$dupText = $schemaText.Replace('"properties": {', '"properties": { "projectCwd": { "type": "string" },')
Check ($dupText -ne $schemaText -and @(Find-HordeJsonDuplicateKey -Text $dupText | Where-Object { $_ -like "*'projectCwd'*" }).Count -gt 0) "CONTROL: a key repeated in the schema's text is found"

Write-Host ""
Write-Host "--- golden records: the valid ones pass ---" -ForegroundColor Cyan
$fx = Join-Path $root "test\fixtures\session-binding"
function Read-Fixture { param([string]$Rel) $t = Read-HordeSharedText -Path (Join-Path $fx $Rel); $v = $t | ConvertFrom-Json; return ,$v }
$valid = @(Get-ChildItem -LiteralPath (Join-Path $fx "valid") -Filter *.json -File)
Check ($valid.Count -eq 2) ("CONTROL: the valid fixtures are there (" + $valid.Count + ")")
foreach ($f in $valid) {
    $found = @(Test-HordeSchema -Value (Read-Fixture ("valid\" + $f.Name)) -Schema $schema)
    Check ($found.Count -eq 0) ("valid: " + $f.BaseName + $(if ($found.Count) { " (" + ($found -join "; ") + ")" } else { "" }))
}
$full = Read-Fixture "valid\full.json"
$unset = @($schema.properties.PSObject.Properties | Where-Object { $null -eq $full.PSObject.Properties[$_.Name] } | ForEach-Object { $_.Name })
Check ($unset.Count -eq 0) ("the full record sets every field the schema stores (" + ($unset -join ", ") + ")")

Write-Host ""
Write-Host "--- golden records: each invalid one fails for its one reason ---" -ForegroundColor Cyan
$invalid = [ordered]@{
    "no-session-id"         = "$ has no 'sessionId'"
    "no-schema-version"     = "$ has no 'schemaVersion'"
    "schema-version-2"      = '$.schemaVersion is ''2'', not one of: 1'
    "session-id-not-uuid"   = '$.sessionId does not match *'
    "project-cwd-empty"     = '$.projectCwd does not match *'
    "project-cwd-not-string" = '$.projectCwd should be string'
    "fleet-field-role"      = "$ has 'role', which the schema does not allow"
    "fleet-key-device"      = "$ has 'device', which the schema does not allow"
    "agent-field-pid"       = "$ has 'pid', which the schema does not allow"
    "last-seen-local-time"  = '$.lastSeen does not match *'
    "last-tool-empty"       = '$.lastTool does not match *'
    "spawned-at-no-zone"    = '$.spawnedAt does not match *'

}
$onDisk = @(Get-ChildItem -LiteralPath (Join-Path $fx "invalid") -Filter *.json -File | ForEach-Object { $_.BaseName })
$unlisted = @($onDisk | Where-Object { @($invalid.Keys) -cnotcontains $_ })
$absent = @($invalid.Keys | Where-Object { $onDisk -cnotcontains $_ })
Check ($unlisted.Count -eq 0 -and $absent.Count -eq 0) ("CONTROL: every invalid fixture on disk is listed here and every listed one is on disk (" + $onDisk.Count + " on disk; unlisted: " + ($unlisted -join ", ") + "; missing: " + ($absent -join ", ") + ")")
foreach ($k in $invalid.Keys) {
    if ($onDisk -cnotcontains $k) { continue }
    $found = @(Test-HordeSchema -Value (Read-Fixture ("invalid\" + $k + ".json")) -Schema $schema)
    Check ($found.Count -eq 1 -and $found[0] -like $invalid[$k]) ("invalid: " + $k + " (" + ($found -join "; ") + ")")
}

Complete-HordeSuite -Success "the binding record holds exactly the node's own fields, and no field is in both records"
