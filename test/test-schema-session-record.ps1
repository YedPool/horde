# DOES schema/session-record.v1 DESCRIBE HORDE'S SESSION RECORD, AND ONLY THE FIELDS IT OWNS?
#
# Step 1.2. The record's field list is core/ownership.json's; this suite fails if the two ever differ,
# so a field cannot be added to one and forgotten in the other. Every field is stored as an answer in
# core/Tristate.ps1's form, and a record built with that module's own functions must validate.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\Schema.ps1")
. (Join-Path $root "core\Tristate.ps1")
. (Join-Path $root "core\Ownership.ps1")

$schema = Get-HordeSchema -Name "session-record.v1"
$own = Get-HordeOwnership
$props = @{}
foreach ($p in $schema.properties.PSObject.Properties) { $props[$p.Name] = $p.Value }

Write-Host ""
Write-Host "--- the schema and the ownership table name the same fields ---" -ForegroundColor Cyan
$ownNames = @($own.fields | ForEach-Object { "$($_.name)" })
$schemaNames = @($props.Keys | Where-Object { $_ -ne "schemaVersion" })
$missing = @($ownNames | Where-Object { $schemaNames -cnotcontains $_ })
$extra = @($schemaNames | Where-Object { $ownNames -cnotcontains $_ })
Check ($ownNames.Count -ge 30) ("CONTROL: the ownership table was read (" + $ownNames.Count + " fields)")
Check ($missing.Count -eq 0) ("every field the ownership table owns is in the schema (" + ($missing -join ", ") + ")")
Check ($extra.Count -eq 0) ("the schema has no field the ownership table does not own (" + ($extra -join ", ") + ")")
Check (-not $props.ContainsKey("remoteControl")) "a field the ownership table dropped is not in the record"
$ownerMismatch = @($own.fields | Where-Object { $_.name -ne "sessionId" -and "$($props[$_.name].'x-horde-owner')" -cne "$($_.owner)" } | ForEach-Object { $_.name })
Check ($ownerMismatch.Count -eq 0) ("each field's owner in the schema is the ownership table's (" + ($ownerMismatch -join ", ") + ")")

Write-Host ""
Write-Host "--- every field but the identity is an answer ---" -ForegroundColor Cyan
$notAnswer = @($props.Keys | Where-Object { $_ -notin @("schemaVersion", "sessionId") } | Where-Object {
    $s = $props[$_]
    -not ($s.type -eq "object" -and @($s.required) -contains "state" -and @($s.properties.state.enum) -join "," -eq "known,absent,unknown" -and $s.additionalProperties -eq $false) })
Check ($notAnswer.Count -eq 0) ("every field is stored in the answer form (" + ($notAnswer -join ", ") + ")")
Check ($props["sessionId"].type -eq "string") "the session id is a plain string: it is the record's identity, never an answer"

Write-Host ""
Write-Host "--- records built by core/tristate validate; malformed ones do not ---" -ForegroundColor Cyan
function Rec { param([hashtable]$Fields)
    $r = [ordered]@{ schemaVersion = 1; sessionId = "38d41f80-e534-4f43-9b23-82b80979b435" }
    foreach ($k in $Fields.Keys) { $r[$k] = ConvertTo-HordeAnswerRecord $Fields[$k] }
    # Through JSON and back, as a stored record would be.
    return (($r | ConvertTo-Json -Depth 10) | ConvertFrom-Json) }
$now = [datetime]::UtcNow
$good = Rec @{ role = (New-HordeKnown -Value "warchief" -ObservedAt $now); pane = (New-HordeUnknown -Reason "wezterm did not answer"); parent = (New-HordeAbsent -ObservedAt $now); dependsOn = (New-HordeKnown -Value @() -ObservedAt $now) }
$f = @(Test-HordeSchema -Value $good -Schema $schema)
Check ($f.Count -eq 0) ("a record of known, unknown and absent answers made by core/tristate is valid (" + ($f -join "; ") + ")")
$minimal = (([ordered]@{ schemaVersion = 1; sessionId = "x" } | ConvertTo-Json) | ConvertFrom-Json)
Check (@(Test-HordeSchema -Value $minimal -Schema $schema).Count -eq 0) "a record that has asked about nothing yet is valid"

function Bad { param($Obj, [string]$Like) $v = (($Obj | ConvertTo-Json -Depth 10) | ConvertFrom-Json); return (@(Test-HordeSchema -Value $v -Schema $schema | Where-Object { $_ -like $Like }).Count -gt 0) }
Check (Bad ([ordered]@{ schemaVersion = 1 }) "*has no 'sessionId'*") "a record with no session id is invalid"
Check (Bad ([ordered]@{ schemaVersion = 2; sessionId = "x" }) "*schemaVersion*not one of*") "a record claiming another schema version is invalid"
Check (Bad ([ordered]@{ schemaVersion = 1; sessionId = "x"; paneId = 3 }) "*'paneId'*does not allow*") "a field the ownership table does not own is invalid"
Check (Bad ([ordered]@{ schemaVersion = 1; sessionId = "x"; role = [ordered]@{ state = "maybe"; reason = "" } }) "*.role.state*not one of*") "an answer whose state is not known, absent or unknown is invalid"
Check (Bad ([ordered]@{ schemaVersion = 1; sessionId = "x"; role = [ordered]@{ state = "known"; value = "orc" } }) "*.role has no 'reason'*") "an answer with no reason field is invalid"
Check (Bad ([ordered]@{ schemaVersion = 1; sessionId = "x"; role = "orc" }) "*.role should be object*") "a bare value where an answer belongs is invalid"
Check (Bad ([ordered]@{ schemaVersion = 1; sessionId = "x"; role = [ordered]@{ state = "known"; value = "orc"; reason = ""; guess = $true } }) "*'guess'*does not allow*") "an answer with a key of its own is invalid"

Complete-HordeSuite -Success "the session record holds exactly the owned fields, each as an answer"
