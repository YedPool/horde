# DOES THE NODE READ ITS OPT-IN LIST FROM ITS OWN CONFIGURATION, AND FROM NOWHERE ELSE?
#
# Remote plan steps R9 and R21 (decided 2026-10-05): a deliver may reach a session the hub spawned, or one
# whose label the node's own remote.deliverTo lists. That key is the node owner's: core/config-keys.json
# allows it only in L1, so the configuration checker refuses it in a run spec (L3), in a live rule (L4)
# or a spawn (L5); nothing on the link carries it; and, as for every setting, no environment variable
# moves it. core/NodeDeliverTo.ps1's Get-HordeNodeDeliverTo is the one reader.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\NodeDeliverTo.ps1")

function Doc { param([string]$Layer, [string]$Text) return [pscustomobject]@{ layer = $Layer; source = ("fixture " + $Layer); text = $Text } }
function Rules { param([string]$Body) return ('{ "schemaVersion": 1, "rules": [' + $Body + '] }') }
function Rule { param([string]$Id, [string]$Value, [string]$Match = '{}') return ('{ "id": "' + $Id + '", "match": ' + $Match + ', "set": { "remote.deliverTo": "' + $Value + '" }, "writtenBy": "user" }') }

Write-Host ""
Write-Host "--- the key is in the registry, for L1 alone ---" -ForegroundColor Cyan
$key = @(Get-HordeConfigKeys | Where-Object { "$($_.name)" -ceq "remote.deliverTo" })
Check ($key.Count -eq 1 -and (@($key[0].layers) -join ",") -ceq "L1") "core/config-keys.json lists remote.deliverTo, settable only in L1"

Write-Host ""
Write-Host "--- the node's own L1 sets it, and nothing else does ---" -ForegroundColor Cyan
$a = Get-HordeNodeDeliverTo -Documents @()
Check ($a.state -ceq "known" -and @($a.value).Count -eq 0) "with no configuration, no label is opted in"
$l1 = Doc "L1" (Rules (Rule "opt-in" "A12,B3"))
$a = Get-HordeNodeDeliverTo -Documents @($l1)
Check ($a.state -ceq "known" -and (@($a.value) -join ",") -ceq "A12,B3") "L1 opts in the labels it lists"
$saved = @{}
foreach ($v in @("HORDE_REMOTE_DELIVERTO", "REMOTE_DELIVERTO", "remote.deliverTo")) { $saved[$v] = [System.Environment]::GetEnvironmentVariable($v); [System.Environment]::SetEnvironmentVariable($v, "Z9") }
try {
    $a = Get-HordeNodeDeliverTo -Documents @()
    Check ($a.state -ceq "known" -and @($a.value).Count -eq 0) "an environment variable opts nothing in"
    $a = Get-HordeNodeDeliverTo -Documents @($l1)
    Check ((@($a.value) -join ",") -ceq "A12,B3") "CONTROL: with the same variables set, L1 still decides, alone"
} finally { foreach ($v in @($saved.Keys)) { [System.Environment]::SetEnvironmentVariable($v, $saved[$v]) } }
$l3 = Doc "L3" (Rules (Rule "from-a-run" "Z9"))
$f = @(Test-HordeEngineConfig -Documents @($l3) | Where-Object { "$($_.code)" -ceq "key-layer" })
Check ($f.Count -eq 1 -and "$($f[0].detail)" -clike "*may be set only in L1*") "a run spec (L3) setting it is a finding of the configuration checker"
$a = Get-HordeNodeDeliverTo -Documents @($l1, $l3)
Check ($a.state -ceq "unknown" -and "$($a.reason)" -clike "*may be set only in L1*") "and a node whose layers set it outside L1 opts nothing in: unknown, with the reason"
$l4 = Doc "L4" (Rules (Rule "live" "Z9"))
$a = Get-HordeNodeDeliverTo -Documents @($l1, $l4)
Check ($a.state -ceq "unknown") "a live rule (L4) setting it is refused too"
$a = Get-HordeNodeDeliverTo -Documents @(Doc "L1" (Rules (Rule "only-goblins" "A12" '{ "role": "goblin" }')))
Check ($a.state -ceq "unknown" -and "$($a.reason)" -clike "*node-wide*") "a rule that sets it for a match is refused: the list is node-wide, never per target"
$a = Get-HordeNodeDeliverTo -Documents @(Doc "L1" (Rules ((Rule "one" "A12") + ", " + (Rule "two" "B3"))))
Check ($a.state -ceq "unknown" -and "$($a.reason)" -clike "*one*two*") "two rules that disagree are unknown, naming both, never the last one read"
$a = Get-HordeNodeDeliverTo -Documents @(Doc "L1" (Rules (Rule "lower" "a12")))
Check ($a.state -ceq "unknown") "a value that is not a list of hub labels is refused"

Complete-HordeSuite -Success "remote.deliverTo is read from the node's own L1 and nowhere else, and anything doubtful opts nothing in"
