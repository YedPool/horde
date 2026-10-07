# DOES THE NODE READ ITS OPT-IN LIST FROM ITS OWN LAYERS, THROUGH THE ONE LAYER READER, AND FROM NOWHERE ELSE?
#
# Remote plan steps R9 and R21 (decided 2026-10-05; amended 2026-10-06: one source of node configuration).
# A deliver may reach a session the hub spawned, or one whose label the node's own remote.deliverTo lists.
# That key is the node owner's, exactly like remote.permissionCeiling: core/config-keys.json allows it only
# in L1 (<HordeHome>\engine.json) and L4 (<HordeHome>\engine-live.json). Both files are read by the node's
# ONE layer reader, core/NodeEngineLayers.ps1's Get-HordeNodeEngineLayers - the one the spawn path uses - and every
# problem it finds refuses the whole list. Nothing on the link carries the key, and no environment
# variable moves it. Its value is a bounded list of hub labels, and every refusal names the entry.
# core/NodeDeliverTo.ps1 resolves the list; cli/NodeServe.ps1's Read-HordeNodeDeliverTo joins the two.
# Every file lives under a temp root that is removed at the end.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "Platform", "Namespace", "NodeDeliverTo")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "transports\Port.ps1")
foreach ($t in @(Get-HordeTransportFiles)) { . $t }
. (Join-Path $root "remote\NodeServe.ps1")
. (Join-Path $root "remote\Outbox.ps1")
. (Join-Path $root "cli\NodeServe.ps1")
. (Join-Path $root "cli\NodeAct.ps1")

function Doc { param([string]$Layer, [string]$Text) return [pscustomobject]@{ layer = $Layer; source = ("fixture " + $Layer); text = $Text } }
function Rules { param([string]$Body) return ('{ "schemaVersion": 1, "rules": [' + $Body + '] }') }
function Rule { param([string]$Id, [string]$Value, [string]$Match = '{}', [string]$By = "user") return ('{ "id": "' + $Id + '", "match": ' + $Match + ', "set": { "remote.deliverTo": "' + $Value + '" }, "writtenBy": "' + $By + '" }') }
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-deliverto-" + [guid]::NewGuid().ToString("N"))
$all = Get-HordeAgentDescriptors -Root $root
$descriptors = $all.value
$builtin = @(Get-HordeBuiltinLayer -Root $root)
function Home {
    # A fresh node home with the given L1 and L4 texts ("" leaves the file out).
    param([string]$User = "", [string]$Live = "")
    $h = Join-Path $tmp ([guid]::NewGuid().ToString("N"))
    [void][System.IO.Directory]::CreateDirectory($h)
    if ($User -ne "") { [System.IO.File]::WriteAllText((Join-Path $h "engine.json"), $User) }
    if ($Live -ne "") { [System.IO.File]::WriteAllText((Join-Path $h "engine-live.json"), $Live) }
    return $h
}
function Read { param([string]$HordeHome) return (Read-HordeNodeDeliverTo -Root $root -HordeHome $HordeHome -Descriptors $descriptors -Builtin $builtin) }

try {
Write-Host ""
Write-Host "--- the key is in the registry, for the node's own layers alone ---" -ForegroundColor Cyan
Check ($all.state -ceq "known" -and $builtin.Count -gt 0) "CONTROL: the shipped descriptors and built-in layer load, so the reader checks what a node checks"
$key = @(Get-HordeConfigKeys | Where-Object { "$($_.name)" -ceq "remote.deliverTo" })
Check ($key.Count -eq 1 -and (@($key[0].layers) -join ",") -ceq "L1,L4") "core/config-keys.json lists remote.deliverTo, settable only in L1 and L4, like remote.permissionCeiling"
$f = @(Test-HordeEngineConfig -Documents @(Doc "L3" (Rules (Rule "from-a-run" "Z9"))) -Descriptors $descriptors | Where-Object { "$($_.code)" -ceq "key-layer" })
Check ($f.Count -eq 1 -and "$($f[0].detail)" -clike "*may be set only in L1, L4*") "a run spec (L3) setting it is a finding of the configuration checker"
$f = @(Test-HordeEngineConfig -Documents @(Doc "L5" (Rules (Rule "spawn" "Z9" '{}' "cli"))) -Descriptors $descriptors | Where-Object { "$($_.code)" -ceq "key-layer" })
Check ($f.Count -eq 1) "and so is a spawn (L5) setting it"

Write-Host ""
Write-Host "--- the node's own files set it, through the one reader, and nothing else does ---" -ForegroundColor Cyan
$a = Read (Home)
Check ("$($a.error)" -eq "" -and @($a.deliverTo).Count -eq 0) "with neither file, no label is opted in"
$a = Read (Home -User (Rules (Rule "opt-in" "A12,B3")))
Check ("$($a.error)" -eq "" -and (@($a.deliverTo) -join ",") -ceq "A12,B3") "engine.json (L1) opts in the labels it lists"
$a = Read (Home -User (Rules (Rule "opt-in" "A12,B3")) -Live (Rules (Rule "live" "C7")))
Check ("$($a.error)" -eq "" -and (@($a.deliverTo) -join ",") -ceq "C7") "engine-live.json (L4) beats engine.json, as a higher layer does in the resolver"
$a = Read (Home -User (Rules (Rule "opt-in" "A12,B3")) -Live (Rules (Rule "withdraw" "")))
Check ("$($a.error)" -eq "" -and @($a.deliverTo).Count -eq 0) "a live rule setting it to nothing withdraws every opt-in"
$envHome = Home -User (Rules (Rule "opt-in" "A12,B3"))
$saved = @{}
foreach ($v in @("HORDE_REMOTE_DELIVERTO", "REMOTE_DELIVERTO", "remote.deliverTo")) { $saved[$v] = [System.Environment]::GetEnvironmentVariable($v); [System.Environment]::SetEnvironmentVariable($v, "Z9") }
try {
    $a = Read (Home)
    Check ("$($a.error)" -eq "" -and @($a.deliverTo).Count -eq 0) "an environment variable opts nothing in"
    $a = Read $envHome
    Check ((@($a.deliverTo) -join ",") -ceq "A12,B3") "CONTROL: with the same variables set, engine.json still decides, alone"
} finally { foreach ($v in @($saved.Keys)) { [System.Environment]::SetEnvironmentVariable($v, $saved[$v]) } }
$a = Read (Home -User (Rules (Rule "only-goblins" "A12" '{ "role": "goblin" }')))
Check ("$($a.error)" -clike "*node-wide*") "a rule that sets it for a match is refused: the list is node-wide, never per target"
$a = Read (Home -User (Rules ((Rule "one" "A12") + ", " + (Rule "two" "B3"))))
Check ("$($a.error)" -clike "*one*two*") "two rules of one layer that disagree are refused, naming both, never the last one read"

Write-Host ""
Write-Host "--- any problem the reader finds opts nothing in, with its text ---" -ForegroundColor Cyan
$a = Read (Home -User '{ "schemaVersion": 1, "rules": [')
Check (@($a.deliverTo).Count -eq 0 -and "$($a.error)" -clike "*engine.json*") "an engine.json that is not JSON opts nothing in, naming the file"
$a = Read (Home -User (Rules (Rule "opt-in" "A12")) -Live '{ "schemaVersion": 1, "rules": [')
Check (@($a.deliverTo).Count -eq 0 -and "$($a.error)" -clike "*engine-live.json*") "an engine-live.json that is not JSON opts nothing in either, even with a good engine.json"
$a = Read (Home -User (Rules (Rule "dup" "A12,A12")))
Check (@($a.deliverTo).Count -eq 0 -and "$($a.error)" -clike "*'A12'*twice*") "a list the checker refuses opts nothing in, with the checker's reason"
$a = Read (Home -User (Rules (Rule "opt-in" "A12")) -Live '{ "schemaVersion": 1, "rules": [ { "id": "other", "match": {}, "set": { "no.such.key": "x" }, "writtenBy": "cli" } ] }')
Check (@($a.deliverTo).Count -eq 0 -and "$($a.error)" -clike "*no.such.key*") "a problem in a layer that does not touch the list opts nothing in too: the node cannot say what its owner allows"
$a = Get-HordeNodeDeliverTo -Layers @(Doc "L1" (Rules (Rule "opt-in" "A12"))) -Problems @("x: not JSON", "y: key-layer")
Check ($a.state -ceq "unknown" -and "$($a.reason)" -clike "*x: not JSON*y: key-layer*") "the resolver quotes every problem the reader gave"
$a = Get-HordeNodeDeliverTo -Layers @(Doc "L3" (Rules (Rule "from-a-run" "Z9")))
Check ($a.state -ceq "unknown" -and "$($a.reason)" -clike "*only the node's own layers*") "the second line: a layer outside L1 and L4 that reached the resolver unchecked is refused"

Write-Host ""
Write-Host "--- the list is bounded, and every refusal names the entry ---" -ForegroundColor Cyan
function Finding { param([string]$Value) $f = @(Test-HordeEngineConfig -Documents @(Doc "L1" (Rules (Rule "opt-in" $Value))) -Descriptors $descriptors | Where-Object { "$($_.code)" -ceq "key-value" }); if ($f.Count -eq 0) { return "" }; return "$($f[0].detail)" }
Check ((Finding "A12,B3,M") -eq "") "CONTROL: hub labels, each once, are a value it allows"
$max = (1..64 | ForEach-Object { "A" + $_ }) -join ","
Check ((Finding $max) -eq "") "CONTROL: 64 labels are allowed"
Check ((Finding ($max + ",B1")) -clike "*65 labels*at most 64*") "65 labels are refused, saying how many and the cap"
Check ((Finding "A12,ABC1") -clike "*'ABC1'*") "a label that is not a hub label is refused, naming it"
Check ((Finding "A12,a12") -clike "*'a12'*") "a lower-case label is refused, naming it"
Check ((Finding "A12,AB10000") -clike "*'AB10000'*longer than 6*") "a label longer than a hub label can be is refused, naming it and the cap"
Check ((Finding "A12,B3,A12") -clike "*'A12'*twice*") "a label listed twice is refused, naming it"
Check ((Finding "A12,,B3") -clike "*empty entry*") "an empty entry between commas is refused"
Check ((Finding "A12, B3") -clike "*' B3'*") "a label with a space is refused, naming it as written"
} finally {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
Check (-not (Test-Path -LiteralPath $tmp)) "the temp root is gone"

Complete-HordeSuite -Success "remote.deliverTo is read from the node's own engine.json and engine-live.json through the one layer reader, bounded and named entry by entry, and any problem opts nothing in"
