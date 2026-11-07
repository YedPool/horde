# DOES A NODE READ ITS OWNER'S ENGINE LAYERS EXACTLY AS WRITTEN, AND NAME EVERY FILE IT CANNOT TRUST?
#
# core/NodeEngineLayers.ps1, the one layer reader (moved from cli/NodeAct.ps1). Real files in a temporary
# Horde home: engine.json (L1) and engine-live.json (L4). Each file is checked as bytes before it is
# decoded, so a byte-order mark or a non-ASCII byte is a problem naming the file and the cause, and a file
# that does not parse is a problem carrying the parser's own words. The act path refuses every spawn on
# any problem (test/test-node-act.ps1 proves that through the node's real context).
#
# NEUTRAL NAMES ONLY (CONTRIBUTING 14): the fixture harness and the fixture L0 layer.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\NodeEngineLayers.ps1")

$aText = [System.IO.File]::ReadAllText((Join-Path $root "test\fixtures\agent-descriptor\agents\harness-a\agent.json"))
$descriptors = @{ "harness-a" = (Read-HordeAgentDescriptorText -Text $aText -ExpectedName "harness-a") }
$fx = Join-Path $root "test\fixtures\engine-config"
# The fixture L0 without its second profile, whose harness has no descriptor here.
$l0 = @(Read-HordeEngineLayerText -Text ([System.IO.File]::ReadAllText((Join-Path $fx "builtin.json")) -replace ',\s*\{ "name": "beta"[^}]*\}', '') -Layer "L0" -Source "fixture L0")
$home1 = Join-Path $env:TEMP ("horde-engine-layers-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $home1 | Out-Null
$l1 = Join-Path $home1 "engine.json"
$l4 = Join-Path $home1 "engine-live.json"
$good = '{ "schemaVersion": 1, "rules": [ { "id": "c", "match": {}, "set": { "remote.permissionCeiling": "edits" }, "writtenBy": "user" } ] }'
function Clear-Layers { foreach ($p in @($l1, $l4)) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p } } }
function Read-Layers { return (Get-HordeNodeEngineLayers -Root $root -HordeHome $home1 -Descriptors $descriptors -Builtin $l0) }
function Set-Bytes { param([string]$Path, [byte[]]$Bytes) [System.IO.File]::WriteAllBytes($Path, $Bytes) }
function Joined { param($Eng) return (@($Eng.problems) -join " | ") }

try {
Write-Host ""
Write-Host "--- the controls: no files, then good files ---" -ForegroundColor Cyan
Clear-Layers
$e = Read-Layers
Check (@($e.problems).Count -eq 0 -and @($e.layers).Count -eq 1) "with no owner files, L0 alone and no problem"
[System.IO.File]::WriteAllText($l1, $good)
[System.IO.File]::WriteAllText($l4, $good)
$e = Read-Layers
Check (@($e.problems).Count -eq 0 -and @($e.layers | Where-Object { $_.layer -ceq "L1" }).Count -eq 1 -and @($e.layers | Where-Object { $_.layer -ceq "L4" }).Count -eq 1) ("CONTROL: good engine.json and engine-live.json are read as L1 and L4, with no problem (" + (Joined $e) + ")")

Write-Host ""
Write-Host "--- every file checked as bytes before it is decoded (CONTRIBUTING 13) ---" -ForegroundColor Cyan
Clear-Layers
# A hand-edited engine.json, saved as UTF-8 with one e-acute inside an otherwise valid rule id.
$utf8 = [System.Text.Encoding]::UTF8.GetBytes($good.Replace('"id": "c"', ('"id": "caf' + [char]0x00E9 + '"')))
Set-Bytes $l1 $utf8
$e = Read-Layers
$p = Joined $e
Check ($p -like ("*" + $l1 + ": not ASCII - *holds a byte that is not ASCII*") -and $p -notlike "*not JSON*") ("a non-ASCII engine.json is a problem naming the file and the cause, never decoded silently (" + $p + ")")
Check (@($e.layers | Where-Object { $_.layer -ceq "L1" }).Count -eq 0) "and its layer is not read"
Clear-Layers
$bom = [byte[]](@(0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::ASCII.GetBytes($good))
Set-Bytes $l4 $bom
$e = Read-Layers
$p = Joined $e
Check ($p -like ("*" + $l4 + ": not ASCII - *byte-order mark*")) ("an engine-live.json that starts with a byte-order mark is a problem naming the file and the mark (" + $p + ")")
Check (@($e.layers | Where-Object { $_.layer -ceq "L4" }).Count -eq 0) "and its layer is not read"

Write-Host ""
Write-Host "--- a file that cannot be read refuses; it is never dropped (review of #109) ---" -ForegroundColor Cyan
Clear-Layers
[System.IO.File]::WriteAllText($l4, $good)
$hold = [System.IO.File]::Open($l4, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
try { $e = Read-Layers } finally { $hold.Dispose() }
$p = Joined $e
Check ($p -like ("*" + $l4 + ": cannot be read - *") -and @($e.layers | Where-Object { $_.layer -ceq "L4" }).Count -eq 0) ("an engine-live.json held open by another process is a problem naming the file, never a layer quietly left out (" + $p + ")")
$e = Read-Layers
Check (@($e.problems).Count -eq 0 -and @($e.layers | Where-Object { $_.layer -ceq "L4" }).Count -eq 1) "CONTROL: released, the same file is read as L4"
Clear-Layers
[System.IO.File]::WriteAllBytes($l1, [System.Text.Encoding]::Unicode.GetBytes($good))
$p = Joined (Read-Layers)
Check ($p -like ("*" + $l1 + ": not ASCII - *control byte 0x00, as a file saved as UTF-16 does*") -and $p -notlike "*not JSON*") ("an engine.json saved as UTF-16 with no mark is named as such, not as JSON that does not parse (" + $p + ")")

Write-Host ""
Write-Host "--- a file that does not parse carries the parser's own words ---" -ForegroundColor Cyan
Clear-Layers
[System.IO.File]::WriteAllText($l1, "{ not json")
$e = Read-Layers
$p = Joined $e
$expected = ""
try { $null = ConvertFrom-HordeJson "{ not json" } catch { $expected = $_.Exception.Message }
Check ($expected -ne "" -and $p -like ("*" + $l1 + ": not JSON - *") -and $p.Contains($expected)) ("an engine.json that does not parse names the file and the parser's reason (" + $p + ")")
Clear-Layers
[System.IO.File]::WriteAllText($l4, "[ 1,")
$e = Read-Layers
Check ((Joined $e) -like ("*" + $l4 + ": not JSON - *")) "and so does an engine-live.json"

Write-Host ""
Write-Host "--- what parses is checked: a value the key does not take ---" -ForegroundColor Cyan
Clear-Layers
[System.IO.File]::WriteAllText($l1, $good.Replace('"edits"', '"Plan"'))
$e = Read-Layers
$p = Joined $e
Check ($p -like ("*" + $l1 + "*Plan*")) ("a ceiling of 'Plan' is a problem naming the file (" + $p + ")")

Write-Host ""
Write-Host "--- the act path's read: policy and layers together ---" -ForegroundColor Cyan
Clear-Layers
Set-Bytes $l4 $bom
$c = Read-HordeNodeActConfig -Root $root -HordeHome $home1 -Descriptors $descriptors -Builtin $l0
Check ($c.policy.state -ne "known" -and ("" + $c.policy.reason) -like "*no policy file*" -and (@($c.problems) -join " ") -like "*byte-order mark*") "Read-HordeNodeActConfig returns the policy's answer and the layers' problems"
} finally {
    if ((Split-Path -Leaf $home1) -match '^horde-engine-layers-[0-9a-f]{32}$') { Remove-Item -LiteralPath $home1 -Recurse -Force -ErrorAction SilentlyContinue }
}

Complete-HordeSuite -Success "a node reads its owner's engine layers as written, and names every file it cannot trust, with the cause"
