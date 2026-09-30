# DOES schema/session-record.v1 DESCRIBE EXACTLY THE RECORD HORDE'S ENGINE STORES?
#
# Step 1.2. The stored record holds the fields core/ownership.json gives to the engine and does not
# mark derived - nothing else. A field another owner holds lives in that owner's store, and a
# derived field is computed; a stored copy of either would be the second writer step 0.6 forbids.
# So the field list is not written here: it is computed from the ownership table on every run, and
# this suite fails when the schema and the table disagree in either direction.
#
# The answer-per-field VIEW over all owners (unknowns, provenance, provisional marks) is a separate
# schema, session-view, produced by `horde status --json` at step 2.3. It is not tested here.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\Schema.ps1")
. (Join-Path $root "core\Ownership.ps1")
. (Join-Path $root "core\ReadShared.ps1")

$schemaPath = Join-Path $root "schema\session-record.v1.json"
$schemaText = Get-Content -LiteralPath $schemaPath -Raw
$schema = Get-HordeSchema -Name "session-record.v1"
$own = Get-HordeOwnership

function Copy-HordeJson { param($Value) return (($Value | ConvertTo-Json -Depth 30) | ConvertFrom-Json) }

function Get-HordeReadOrder {
    # The ownership table's read precedence for one field, in the form the schema documents it.
    param($Field)
    return ((@($Field.read) | ForEach-Object { "$($_.store) $($_.field)" }) -join ", then ")
}

function Get-HordeRecordDrift {
    # Every way the schema and the ownership table disagree about what the engine stores. Empty
    # means they agree. Takes both as arguments so the controls below can hand it a changed copy.
    param($Own, $Schema)
    $out = New-Object System.Collections.ArrayList
    $props = @{}
    foreach ($p in @($Schema.properties.PSObject.Properties)) { $props[$p.Name] = $p.Value }
    # WHAT BELONGS IN THE STORED RECORD, computed and never listed: owner engine, and no derived
    # mark. sessionId is the key whatever its owner, so it is compared separately below.
    $expected = @($Own.fields | Where-Object { "$($_.owner)" -ceq "engine" -and $null -eq $_.PSObject.Properties["derived"] -and "$($_.name)" -cne "sessionId" } | ForEach-Object { "$($_.name)" })
    $stored = @($props.Keys | Where-Object { $_ -cne "schemaVersion" -and $_ -cne "sessionId" })
    foreach ($n in $expected) { if ($stored -cnotcontains $n) { [void]$out.Add("'" + $n + "' is owned by the engine and not derived, but the schema does not store it") } }
    foreach ($n in $stored) {
        if ($expected -ccontains $n) { continue }
        $f = Get-HordeOwnershipField -Doc $Own -Name $n
        if ($null -eq $f) { [void]$out.Add("'" + $n + "' is stored, but the ownership table has no such field") }
        elseif ("$($f.owner)" -cne "engine") { [void]$out.Add("'" + $n + "' is stored, but its owner is " + $f.owner + ", not the engine") }
        else { [void]$out.Add("'" + $n + "' is stored, but it is derived: " + $f.derived) }
    }
    # A DROPPED FIELD IS NOT CARRIED. Read from the table, so a field dropped later is covered too.
    foreach ($d in @($Own.dropped | Where-Object { $null -ne $_ })) {
        if ($props.ContainsKey("$($d.name)")) { [void]$out.Add("'" + $d.name + "' is dropped by the ownership table but stored by the schema") }
    }
    # EACH STORED FIELD SAYS WHO WRITES IT AND HOW IT IS READ UNTIL THE SWITCH, as the table does.
    foreach ($n in $stored) {
        $f = Get-HordeOwnershipField -Doc $Own -Name $n
        if ("$($props[$n].'x-horde-owner')" -cne "engine") { [void]$out.Add("'" + $n + "' does not carry x-horde-owner engine") }
        if ($null -ne $f -and "$($props[$n].'x-horde-read')" -cne (Get-HordeReadOrder $f)) { [void]$out.Add("'" + $n + "' documents a read order that is not the ownership table's (" + (Get-HordeReadOrder $f) + ")") }
    }
    # THE KEY: its owner in the schema is the table's, and the table's is the agent.
    $sid = Get-HordeOwnershipField -Doc $Own -Name "sessionId"
    if ($null -eq $sid) { [void]$out.Add("the ownership table has no sessionId") }
    elseif ("$($sid.owner)" -cne "agent") { [void]$out.Add("sessionId's owner in the ownership table is " + $sid.owner + ", not the agent") }
    if (-not $props.ContainsKey("sessionId")) { [void]$out.Add("the schema has no sessionId") }
    elseif ($null -ne $sid -and "$($props['sessionId'].'x-horde-owner')" -cne "$($sid.owner)") { [void]$out.Add("sessionId's x-horde-owner is not the ownership table's owner (" + $sid.owner + ")") }
    return @($out)
}

Write-Host ""
Write-Host "--- the schema stores exactly the engine's own, non-derived fields ---" -ForegroundColor Cyan
$expectedNames = @($own.fields | Where-Object { "$($_.owner)" -ceq "engine" -and $null -eq $_.PSObject.Properties["derived"] } | ForEach-Object { "$($_.name)" })
Check (@($own.fields).Count -ge 30) ("CONTROL: the ownership table was read (" + @($own.fields).Count + " fields)")
Check ($expectedNames.Count -ge 10) ("CONTROL: the table gives the engine fields to store (" + $expectedNames.Count + ": " + ($expectedNames -join ", ") + ")")
$drift = @(Get-HordeRecordDrift -Own $own -Schema $schema)
Check ($drift.Count -eq 0) ("the schema and the ownership table agree (" + ($drift -join "; ") + ")")
$dups = @(Find-HordeJsonDuplicateKey -Text $schemaText)
Check ($dups.Count -eq 0) ("the schema's text repeats no key in one object (" + ($dups -join "; ") + ")")
Check (@($schema.required).Count -eq 2 -and @($schema.required) -ccontains "schemaVersion" -and @($schema.required) -ccontains "sessionId") "only schemaVersion and sessionId are required: a field not set is absent"
Check ($schema.additionalProperties -is [bool] -and $schema.additionalProperties -eq $false) "the schema allows no field it does not name"
Check ((@($schema.properties.schemaVersion.enum) -join ",") -ceq "1" -and $schema.properties.schemaVersion.type -ceq "integer") "schemaVersion is the integer 1"
Check ((@($schema.properties.role.enum) -join ",") -ceq ((@((Get-Content -LiteralPath (Join-Path $root "core\roles.json") -Raw | ConvertFrom-Json).native)) -join ",")) "role takes exactly core/roles.json's native roles"

Write-Host ""
Write-Host "--- the drift check notices each way the two can part ---" -ForegroundColor Cyan
# CONTROLS: the check above is only evidence if it goes red when the table or the schema changes.
# Each change is made to a copy in memory; nothing on disk is touched.
function Drifts { param($O, $S, [string]$Like) return (@(Get-HordeRecordDrift -Own $O -Schema $S | Where-Object { $_ -like $Like }).Count -gt 0) }
$o = Copy-HordeJson $own; (Get-HordeOwnershipField -Doc $o -Name "label").owner = "agent"
Check (Drifts $o $schema "'label' is stored, but its owner is agent*") "a field whose owner leaves the engine must leave the record"
$o = Copy-HordeJson $own; (Get-HordeOwnershipField -Doc $o -Name "role") | Add-Member -NotePropertyName derived -NotePropertyValue "from somewhere"
Check (Drifts $o $schema "'role' is stored, but it is derived*") "a field that becomes derived must leave the record"
$o = Copy-HordeJson $own; (Get-HordeOwnershipField -Doc $o -Name "owner").PSObject.Properties.Remove("derived")
Check (Drifts $o $schema "'owner' is owned by the engine and not derived, but the schema does not store it") "an engine field that stops being derived must enter the record"
$o = Copy-HordeJson $own; (Get-HordeOwnershipField -Doc $o -Name "pid").owner = "engine"
Check (Drifts $o $schema "'pid' is owned by the engine*") "a field whose owner becomes the engine must enter the record"
$o = Copy-HordeJson $own; $o.fields = @($o.fields) + @([pscustomobject]@{ name = "newThing"; owner = "engine"; read = @() })
Check (Drifts $o $schema "'newThing' is owned by the engine*") "a field added to the table must be added to the schema"
$o = Copy-HordeJson $own; $o.fields = @($o.fields | Where-Object { $_.name -cne "title" })
Check (Drifts $o $schema "'title' is stored, but the ownership table has no such field") "a field removed from the table must be removed from the schema"
$o = Copy-HordeJson $own; (Get-HordeOwnershipField -Doc $o -Name "sessionId").owner = "engine"
Check (Drifts $o $schema "sessionId's*") "sessionId's owner changing is noticed"
$o = Copy-HordeJson $own; (Get-HordeOwnershipField -Doc $o -Name "role").read = @([pscustomobject]@{ store = "W2"; field = "role" }, [pscustomobject]@{ store = "W1"; field = "role" })
Check (Drifts $o $schema "'role' documents a read order*") "a read order changed in the table is noticed in the schema's documentation"
$s = Copy-HordeJson $schema; $s.properties | Add-Member -NotePropertyName pid -NotePropertyValue ([pscustomobject]@{ type = "integer"; "x-horde-owner" = "agent" })
Check (Drifts $own $s "'pid' is stored, but its owner is agent*") "a field added to the schema that the engine does not own is noticed"
$s = Copy-HordeJson $schema; $s.properties.PSObject.Properties.Remove("spawnedAt")
Check (Drifts $own $s "'spawnedAt' is owned by the engine*") "a field removed from the schema is noticed"
$droppedName = "$(@($own.dropped)[0].name)"
Check ($droppedName -ne "") ("CONTROL: the table drops a field (" + $droppedName + ")")
$s = Copy-HordeJson $schema; $s.properties | Add-Member -NotePropertyName $droppedName -NotePropertyValue ([pscustomobject]@{ type = "string"; "x-horde-owner" = "engine" })
Check (Drifts $own $s ("'" + $droppedName + "' is dropped*")) "a dropped field stored by the schema is noticed"
$s = Copy-HordeJson $schema; $s.properties.label.'x-horde-owner' = "agent"
Check (Drifts $own $s "'label' does not carry x-horde-owner engine") "a stored field that names another owner is noticed"
$dupText = $schemaText.Replace('"properties": {', '"properties": { "label": { "type": "string" },')
Check ($dupText -ne $schemaText -and @(Find-HordeJsonDuplicateKey -Text $dupText | Where-Object { $_ -like "*'label'*" }).Count -gt 0) "CONTROL: a key repeated in the schema's text is found"

Write-Host ""
Write-Host "--- golden records: the valid ones pass ---" -ForegroundColor Cyan
$fx = Join-Path $root "test\fixtures\session-record"
function Read-Fixture { param([string]$Rel) $t = Read-HordeSharedText -Path (Join-Path $fx $Rel); $v = $t | ConvertFrom-Json; return ,$v }
$valid = @(Get-ChildItem -LiteralPath (Join-Path $fx "valid") -Filter *.json -File)
Check ($valid.Count -eq 2) ("CONTROL: the valid fixtures are there (" + $valid.Count + ")")
foreach ($f in $valid) {
    $found = @(Test-HordeSchema -Value (Read-Fixture ("valid\" + $f.Name)) -Schema $schema)
    Check ($found.Count -eq 0) ("valid: " + $f.BaseName + $(if ($found.Count) { " (" + ($found -join "; ") + ")" } else { "" }))
}
# THE FULL RECORD SETS EVERY STORED FIELD, so no field's type goes unexercised by a valid value.
$full = Read-Fixture "valid\full.json"
$unset = @($schema.properties.PSObject.Properties | Where-Object { $null -eq $full.PSObject.Properties[$_.Name] } | ForEach-Object { $_.Name })
Check ($unset.Count -eq 0) ("the full record sets every field the schema stores (" + ($unset -join ", ") + ")")

Write-Host ""
Write-Host "--- golden records: each invalid one fails for its one reason ---" -ForegroundColor Cyan
# Each invalid fixture is a valid record with ONE fault, and must produce exactly ONE finding, the
# expected one: a fixture that failed for some other reason would prove nothing about its rule.
$invalid = [ordered]@{
    "no-session-id"              = "$ has no 'sessionId'"
    "bad-session-id"             = '$.sessionId does not match *'
    "schema-version-2"           = '$.schemaVersion is ''2'', not one of: 1'
    "role-old-vocabulary"        = '$.role is ''master'', not one of: *'
    "role-unknown"               = '$.role is ''banana'', not one of: *'
    "retired-not-boolean"        = '$.retired should be boolean'
    "depends-on-string"          = '$.dependsOn should be array'
    "depends-on-item-not-string" = '$.dependsOn`[0`] should be string'
    "retired-at-no-zone"         = '$.retiredAt does not match *'
    "last-seen-local-time"       = '$.lastSeen does not match *'
    "spawned-at-no-zone"         = '$.spawnedAt does not match *'
    "agent-field-pid"            = "$ has 'pid', which the schema does not allow"
    "host-field-pane"            = "$ has 'pane', which the schema does not allow"
    "derived-field-owner"        = "$ has 'owner', which the schema does not allow"
    "unknown-key"                = "$ has 'paneId', which the schema does not allow"
    "parent-not-session-id"      = '$.parent does not match *'
    "label-malformed"            = '$.label does not match *'
    "label-number-leading-zero"  = '$.label does not match *'
    "label-number-five-digits"   = '$.label does not match *'
    "origin-unknown"             = '$.origin is ''robot'', not one of: *'
    "label-cycle-not-integer"    = '$.labelCycle should be integer'
    "run-id-malformed"           = '$.runId does not match *'
    "fleet-session-id-empty"     = '$.fleetSessionId does not match *'
    "project-cwd-empty"          = '$.projectCwd does not match *'
    "last-tool-empty"            = '$.lastTool does not match *'
    "title-not-string"           = '$.title should be string'
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

Complete-HordeSuite -Success "the stored session record holds exactly the engine's own fields, typed"
