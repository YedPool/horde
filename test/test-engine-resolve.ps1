# DOES EVERY TARGET RESOLVE TO EXACTLY THE ENGINE THE LAYERS AND SELECTORS SAY, AND NOTHING ELSE?
#
# core/EngineResolve.ps1 (engines plan step E4). A pure function: parsed layers and a target in, one
# answer per setting with its provenance out, then the binding (harness, provider, pinned model)
# checked as a whole, then the target role's required capabilities against the harness, the
# provider's lacks and the host. No file is read by the function; every case here is a unit case.
#
# NEUTRAL NAMES ONLY (CONTRIBUTING 14): the fixture harnesses of test-engine-config, harness-a
# (anthropic-messages, native provider-a) and harness-b (openai-responses, native provider-b).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\EngineResolve.ps1")

$aText = [System.IO.File]::ReadAllText((Join-Path $root "test\fixtures\agent-descriptor\agents\harness-a\agent.json"))
$bText = $aText.Replace('"name": "harness-a"', '"name": "harness-b"').Replace('"protocols": ["anthropic-messages"]', '"protocols": ["openai-responses"]').Replace('"nativeProvider": "provider-a"', '"nativeProvider": "provider-b"')
$descriptors = @{
    "harness-a" = (Read-HordeAgentDescriptorText -Text $aText -ExpectedName "harness-a")
    "harness-b" = (Read-HordeAgentDescriptorText -Text $bText -ExpectedName "harness-b")
}
$fx = Join-Path $root "test\fixtures\engine-config"
function Read-Fixture { param([string]$Name) return ([System.IO.File]::ReadAllText((Join-Path $fx $Name)) | ConvertFrom-Json) }
function New-Layer { param([string]$Layer, $Doc, [string]$Source = "") if ($Source -eq "") { $Source = "fixture " + $Layer }; return [pscustomobject]@{ layer = $Layer; source = $Source; doc = $Doc } }
function New-Doc { param([object[]]$Rules = @()) return [pscustomobject]@{ schemaVersion = 1; rules = @($Rules) } }
function New-Rule { param([string]$Id, [hashtable]$Match = @{}, [hashtable]$Set, [string]$By = "user", [string]$Until = "") $r = [pscustomobject]@{ id = $Id; match = [pscustomobject]$Match; set = [pscustomobject]$Set; writtenBy = $By }; if ($Until -ne "") { $r | Add-Member -NotePropertyName until -NotePropertyValue $Until }; return $r }
$base = @((New-Layer "L0" (Read-Fixture "builtin.json")), (New-Layer "L1" (Read-Fixture "user.json")))
$parent = "11111111-2222-4333-8444-555555555555"
$session = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
$goblin = @{ role = "goblin"; parent = $parent; run = "20261002-101500-audit"; fleetId = "f1"; session = $session; label = "D7"; title = "lane-x" }
$now = [datetime]::Parse("2026-10-02T12:00:00Z").ToUniversalTime()
function Resolve { param([object[]]$Layers, [hashtable]$Target = $goblin, $Registry = $null, $HostCaps = $null, $Requirements = $null)
    $a = @{ Layers = $Layers; Target = $Target; Descriptors = $descriptors; Now = $now }
    if ($null -ne $Registry) { $a.Registry = $Registry }
    if ($null -ne $HostCaps) { $a.HostCapabilities = $HostCaps }
    if ($null -ne $Requirements) { $a.Requirements = $Requirements }
    return (Resolve-HordeEngine @a)
}
function Get-Val { param($Res, [string]$Key) $s = Get-HordeEngineSetting -Resolution $Res -Key $Key; if ($s.answer.state -eq "known") { return "" + $s.answer.value }; return ("(" + $s.answer.state + ")") }

Write-Host ""
Write-Host "--- the layers: each beaten by the next ---" -ForegroundColor Cyan
$all = [ordered]@{}
foreach ($l in @("L0", "L1", "L3", "L4", "L5")) { $all[$l] = New-Layer $l (New-Doc @(New-Rule ("m-" + $l.ToLowerInvariant()) @{} @{ model = ("model-" + $l.ToLowerInvariant()) })) }
$order = @("L5", "L4", "L3", "L1", "L0")
for ($i = 0; $i -lt $order.Count; $i++) {
    $present = @($order[$i..($order.Count - 1)])
    $res = Resolve @($present | ForEach-Object { $all[$_] })
    $want = "model-" + $order[$i].ToLowerInvariant()
    Check ((Get-Val $res "model") -ceq $want) ("with " + ($present -join ", ") + " present, the model comes from " + $order[$i] + " (" + (Get-Val $res "model") + ")")
}
$s = Get-HordeEngineSetting -Resolution (Resolve @($all.Values)) -Key "model"
Check ($s.layer -ceq "L5" -and $s.rule -ceq "m-l5" -and @($s.beaten).Count -eq 4 -and @($s.beaten | Where-Object { $_.why -like "*lower layer*" }).Count -eq 4) "the winner records its layer and rule, and the four rules it beat, each as a lower layer"
Check (Throws { Resolve @((New-Layer "L2" (New-Doc))) } "project layer (L2) is not built") "a project layer (L2) is refused: it is not built"

Write-Host ""
Write-Host "--- fields resolve independently ---" -ForegroundColor Cyan
$res = Resolve ($base + @(New-Layer "L5" (New-Doc @(New-Rule "spawn" @{} @{ model = "model-a-small" }))))
Check ((Get-Val $res "model") -ceq "model-a-small" -and (Get-Val $res "harness") -ceq "harness-a" -and (Get-HordeEngineSetting -Resolution $res -Key "harness").layer -ceq "L1") "a spawn's model over a user profile keeps the profile's harness, from the user layer"
Check ((Get-HordeEngineSetting -Resolution $res -Key "harness").via -ceq "gamma") "and the harness says it came through the profile gamma (goblins' profile in the user layer)"

Write-Host ""
Write-Host "--- specificity, inside one layer ---" -ForegroundColor Cyan
function Test-Beats { param([string]$What, [hashtable]$Strong, [hashtable]$Weak, [hashtable]$Target = $goblin)
    $doc = New-Doc @((New-Rule "weak" $Weak @{ model = "model-weak" }), (New-Rule "strong" $Strong @{ model = "model-strong" }))
    $r1 = Resolve @((New-Layer "L1" $doc)) -Target $Target
    $doc2 = New-Doc @((New-Rule "strong" $Strong @{ model = "model-strong" }), (New-Rule "weak" $Weak @{ model = "model-weak" }))
    $r2 = Resolve @((New-Layer "L1" $doc2)) -Target $Target
    Check ((Get-Val $r1 "model") -ceq "model-strong" -and (Get-Val $r2 "model") -ceq "model-strong") ($What + " (in either file order)")
}
Test-Beats "{session} beats {run, fleetId}" @{ session = $session } @{ run = $goblin.run; fleetId = "f1" }
Test-Beats "{run, fleetId} beats {title}" @{ run = $goblin.run; fleetId = "f1" } @{ title = "lane-x" }
Test-Beats "{parent} beats {run, role}: this orc's goblins is narrower than goblins in this run" @{ parent = $parent } @{ run = $goblin.run; role = "goblin" }
Test-Beats "{parent, role} beats {parent}" @{ parent = $parent; role = "goblin" } @{ parent = $parent }
Test-Beats "{run} beats {role}" @{ run = $goblin.run } @{ role = "goblin" }
Test-Beats "{role} beats the empty match" @{ role = "goblin" } @{}
Test-Beats "an exact label beats a wildcard one" @{ label = "D7" } @{ label = "D*" }
$doc = New-Doc @((New-Rule "goblins-x" @{ role = "goblin" } @{ model = "model-x" }), (New-Rule "goblins-y" @{ role = "goblin" } @{ model = "model-y" }))
$s = Get-HordeEngineSetting -Resolution (Resolve @((New-Layer "L1" $doc))) -Key "model"
Check ($s.answer.state -eq "unknown" -and $s.answer.reason -like "*goblins-x*" -and $s.answer.reason -like "*goblins-y*") "two equally specific rules that disagree are unknown, naming both rules - never file order"
$doc = New-Doc @((New-Rule "goblins-x" @{ role = "goblin" } @{ model = "model-x" }), (New-Rule "goblins-x2" @{ role = "goblin" } @{ model = "model-x" }))
Check ((Get-Val (Resolve @((New-Layer "L1" $doc))) "model") -ceq "model-x") "two that agree resolve"
$doc = New-Doc @((New-Rule "goblins-x" @{ role = "goblin" } @{ model = "model-x" }), (New-Rule "goblins-y" @{ role = "goblin" } @{ model = "model-y" }), (New-Rule "this-one" @{ session = $session } @{ model = "model-z" }))
Check ((Get-Val (Resolve @((New-Layer "L1" $doc))) "model") -ceq "model-z") "CONTROL: a tie below the winner does not matter"

Write-Host ""
Write-Host "--- matching ---" -ForegroundColor Cyan
$doc = New-Doc @((New-Rule "orcs" @{ role = "orc" } @{ model = "model-orc" }), (New-Rule "all" @{} @{ model = "model-all" }))
Check ((Get-Val (Resolve @((New-Layer "L1" $doc)) -Target @{ role = "orchestrator" }) "model") -ceq "model-orc") "a target's role in the old vocabulary is translated through core/roles.json before it is matched"
Check ((Get-Val (Resolve @((New-Layer "L1" $doc)) -Target @{ role = "goblin" }) "model") -ceq "model-all") "CONTROL: another role does not match"
$doc = New-Doc @((New-Rule "in-run" @{ run = "20261002-101500-audit" } @{ model = "model-run" }), (New-Rule "all" @{} @{ model = "model-all" }))
Check ((Get-Val (Resolve @((New-Layer "L1" $doc)) -Target @{ role = "goblin" }) "model") -ceq "model-all") "a rule on a key the target does not have does not match it"
$doc = New-Doc @((New-Rule "d-star" @{ label = "D*" } @{ model = "model-d" }), (New-Rule "all" @{} @{ model = "model-all" }))
Check ((Get-Val (Resolve @((New-Layer "L1" $doc)) -Target @{ role = "goblin"; label = "D7" }) "model") -ceq "model-d") "a label glob matches"
Check ((Get-Val (Resolve @((New-Layer "L1" $doc)) -Target @{ role = "goblin"; label = "E7" }) "model") -ceq "model-all") "CONTROL: and a label outside it does not"
$doc = New-Doc @((New-Rule "by-id" @{ session = $session.ToUpperInvariant() } @{ model = "model-id" }), (New-Rule "all" @{} @{ model = "model-all" }))
Check ((Get-Val (Resolve @((New-Layer "L4" $doc))) "model") -ceq "model-id") "a session id matches ignoring case, as a UUID"
$live = New-Doc @((New-Rule "old" @{} @{ model = "model-old" } "cli" "2026-10-01T00:00:00Z"))
Check ((Get-Val (Resolve @((New-Layer "L0" (New-Doc @(New-Rule "base" @{} @{ model = "model-base" }))), (New-Layer "L4" $live))) "model") -ceq "model-base") "a live rule past its expiry does not apply"
$live = New-Doc @((New-Rule "new" @{} @{ model = "model-new" } "cli" "2026-10-09T00:00:00Z"))
Check ((Get-Val (Resolve @((New-Layer "L0" (New-Doc @(New-Rule "base" @{} @{ model = "model-base" }))), (New-Layer "L4" $live))) "model") -ceq "model-new") "CONTROL: one before its expiry does"

Write-Host ""
Write-Host "--- the binding: pinned, and checked as a whole ---" -ForegroundColor Cyan
$res = Resolve $base -Target @{ role = "orc" }
Check ($res.binding.state -eq "known" -and $res.binding.value.harness -ceq "harness-a" -and $res.binding.value.provider -ceq "provider-a" -and $res.binding.value.model -ceq "model-a-big" -and $res.binding.value.alias -ceq "big") "an alias is pinned to the concrete id for the resolved provider, and both are recorded"
$res = Resolve ($base + @(New-Layer "L5" (New-Doc @(New-Rule "spawn" @{} @{ model = "small"; profile = "alpha-big" })))) -Target @{ role = "orc" }
Check ($res.binding.state -eq "unknown" -and $res.binding.reason -like "*small*provider-a*") "an alias with no entry for the resolved provider is unknown, naming both; the alias is never passed through"
$res = Resolve ($base + @(New-Layer "L5" (New-Doc @(New-Rule "spawn" @{} @{ harness = "harness-b" })))) -Target @{ role = "orc" }
Check ($res.binding.state -eq "unknown" -and $res.binding.reason -like "*harness-b*protocol*provider-a*") "layers that combine into a harness and a provider it does not speak are refused (the wire-format rule)"
$u = Read-Fixture "user.json"
$u.providers = @($u.providers) + @([pscustomobject]@{ name = "provider-d"; protocol = "anthropic-messages"; credential = [pscustomobject]@{ kind = "harness-login" } })
$res = Resolve @((New-Layer "L0" (Read-Fixture "builtin.json")), (New-Layer "L1" $u), (New-Layer "L5" (New-Doc @(New-Rule "spawn" @{} @{ provider = "provider-d"; model = "x-1" })))) -Target @{ role = "orc" }
Check ($res.binding.state -eq "unknown" -and $res.binding.reason -like "*provider-d*own login*") "a harness-login provider under a harness whose native provider is another is refused (the subscription rule)"
$res = Resolve ($base + @(New-Layer "L5" (New-Doc @(New-Rule "spawn" @{} @{ model = "model-c9" })))) -Target @{ role = "goblin" }
Check ($res.binding.state -eq "unknown" -and $res.binding.reason -like "*model-c9*allowlist*provider-c*") "a model outside the resolved provider's allowlist is refused, though no single layer stated the pair"
$res = Resolve @((New-Layer "L0" (Read-Fixture "builtin.json"))) -Target @{ role = "goblin" }
Check ($res.binding.state -eq "known" -and $null -eq $res.binding.value.model) "with no model set, the binding carries none: the harness's own default"

Write-Host ""
Write-Host "--- capabilities: the role's requirements against harness, provider and host ---" -ForegroundColor Cyan
$req = [pscustomobject]@{ warchief = @("message-inject", "delivery-receipt", "resume", "report-hook"); orc = @("message-inject", "resume", "report-hook"); goblin = @("resume", "report-hook") }
$res = Resolve $base -Target @{ role = "goblin" } -Requirements $req
Check ($res.capabilities.state -eq "known" -and $res.capabilities.value.ok -eq $true) "a goblin on the fixture harness has what a goblin needs"
$res = Resolve $base -Target @{ role = "warchief" } -Requirements $req
$missing = @($res.capabilities.value.missing | ForEach-Object { $_.name })
Check ($res.capabilities.value.ok -eq $false -and ($missing -join ",") -ceq "message-inject,delivery-receipt") ("a warchief there lacks message-inject and delivery-receipt, unverified on the harness (" + ($missing -join ",") + ")")
Check (@($res.capabilities.value.missing | Where-Object { $_.why -like "*unverified*" }).Count -eq 2) "and each says it is unverified, which never counts as yes"
$res = Resolve $base -Target @{ role = "orc" } -Requirements $req -HostCaps @{ "text.send" = "yes" }
Check ($res.capabilities.value.ok -eq $true) "an orc there is satisfied when the host can type text, the capability either port may give"
$res = Resolve $base -Target @{ role = "orc" } -Requirements $req -HostCaps @{ "text.send" = "unverified" }
Check ($res.capabilities.value.ok -eq $false) "CONTROL: not when the host's text.send is only unverified"
$reqD = [pscustomobject]@{ warchief = @(); orc = @(); goblin = @("resume", "delivery-receipt") }
$descriptors["harness-a"].capabilities."delivery-receipt".support = "yes"
$res = Resolve $base -Target $goblin -Requirements $reqD
Check ($res.capabilities.value.ok -eq $false -and @($res.capabilities.value.missing | Where-Object { $_.name -ceq "delivery-receipt" -and $_.why -like "*provider-c lacks*" }).Count -eq 1) "a capability the harness has is still missing when the resolved provider lacks it"
$res = Resolve $base -Target @{ role = "orc" } -Requirements $reqD
Check ($res.capabilities.value.ok -eq $true) "CONTROL: on the native provider, which lacks nothing, it is there"
$descriptors["harness-a"].capabilities."delivery-receipt".support = "unverified"

Write-Host ""
Write-Host "--- a tuner may raise a setting on its own, never lower it (engine-settings decision 9) ---" -ForegroundColor Cyan
$reg = @(Get-HordeConfigKeys) + @([pscustomobject]@{ name = "fixture.reserve"; layers = @("L0", "L1", "L4"); value = [pscustomobject]@{ kind = "enum"; values = @("low", "mid", "high") }; tuner = "raise-only" })
$userDoc = New-Doc @(New-Rule "reserve" @{} @{ "fixture.reserve" = "mid" })
$raise = New-Doc @(New-Rule "tuned" @{} @{ "fixture.reserve" = "high" } "tuner" "2026-10-09T00:00:00Z")
$lower = New-Doc @(New-Rule "tuned" @{} @{ "fixture.reserve" = "low" } "tuner" "2026-10-09T00:00:00Z")
$byCli = New-Doc @(New-Rule "person" @{} @{ "fixture.reserve" = "low" } "cli")
Check ((Get-Val (Resolve ($base + @((New-Layer "L1" $userDoc -Source "u2"), (New-Layer "L4" $raise))) -Registry $reg) "fixture.reserve") -ceq "high") "a tuner's live rule that raises a reserve resolves"
$s = Get-HordeEngineSetting -Resolution (Resolve ($base + @((New-Layer "L1" $userDoc -Source "u2"), (New-Layer "L4" $lower))) -Registry $reg) -Key "fixture.reserve"
Check ($s.answer.state -eq "known" -and $s.answer.value -ceq "mid" -and @($s.refused | Where-Object { $_.rule -ceq "tuned" -and $_.why -like "*only raise*" }).Count -eq 1) "one that lowers it is refused, recorded as refused, and the value below stands"
Check ((Get-Val (Resolve ($base + @((New-Layer "L1" $userDoc -Source "u2"), (New-Layer "L4" $byCli))) -Registry $reg) "fixture.reserve") -ceq "low") "CONTROL: a person's live rule may lower it"
$twoLow = New-Doc @((New-Rule "tuned-goblins" @{ role = "goblin" } @{ "fixture.reserve" = "low" } "tuner" "2026-10-09T00:00:00Z"), (New-Rule "tuned-all" @{} @{ "fixture.reserve" = "low" } "tuner" "2026-10-09T00:00:00Z"))
$s = Get-HordeEngineSetting -Resolution (Resolve ($base + @((New-Layer "L1" $userDoc -Source "u2"), (New-Layer "L4" $twoLow))) -Registry $reg) -Key "fixture.reserve"
Check ($s.answer.value -ceq "mid" -and @($s.refused).Count -eq 2) "every tuner rule that lowers is refused, not only the most specific - a general one does not get through behind it"
# NEW-B: when the rules a person wrote tie, the tuner is held to the strictest of them, not let through.
$tieUser = New-Doc @((New-Rule "person-mid" @{} @{ "fixture.reserve" = "mid" }), (New-Rule "person-high" @{} @{ "fixture.reserve" = "high" }))
$s = Get-HordeEngineSetting -Resolution (Resolve ($base + @((New-Layer "L1" $tieUser -Source "u2"), (New-Layer "L4" $lower))) -Registry $reg) -Key "fixture.reserve"
Check ($s.answer.value -cne "low" -and @($s.refused | Where-Object { $_.rule -ceq "tuned" }).Count -eq 1) "a tuner that lowers below a tie of a person's rules is refused, tie or not"
$tieLowHigh = New-Doc @((New-Rule "person-low" @{} @{ "fixture.reserve" = "low" }), (New-Rule "person-high2" @{} @{ "fixture.reserve" = "high" }))
$midTuner = New-Doc @(New-Rule "tuned-mid" @{} @{ "fixture.reserve" = "mid" } "tuner" "2026-10-09T00:00:00Z")
$s = Get-HordeEngineSetting -Resolution (Resolve ($base + @((New-Layer "L1" $tieLowHigh -Source "u2"), (New-Layer "L4" $midTuner))) -Registry $reg) -Key "fixture.reserve"
Check (@($s.refused | Where-Object { $_.rule -ceq "tuned-mid" }).Count -eq 1) "held to the HIGHEST of the tied values: a tuner value between them is still a lowering of one, and refused"
$oddCase = New-Doc @(New-Rule "tuned-case" @{} @{ "fixture.reserve" = "low" } "Tuner" "2026-10-09T00:00:00Z")
$s = Get-HordeEngineSetting -Resolution (Resolve ($base + @((New-Layer "L1" $userDoc -Source "u2"), (New-Layer "L4" $oddCase))) -Registry $reg) -Key "fixture.reserve"
Check ($s.answer.value -ceq "mid") "a writer that is not exactly user or cli is held to the tuner's rule (fail closed): Tuner lowers nothing"

Write-Host ""
Write-Host "--- a key's direction: what a layer above the owner's may do to its value (review of PR #73, F3) ---" -ForegroundColor Cyan
# The shape of remote R9's ceiling: the owner's layers (L0, L1) set it freely; a run spec, a live rule
# or a spawn may only lower it, never raise it - an agent can write live rules.
$regD = @(Get-HordeConfigKeys) + @([pscustomobject]@{ name = "fixture.ceiling"; layers = @("L0", "L1", "L3", "L4", "L5"); value = [pscustomobject]@{ kind = "enum"; values = @("plan", "ask", "edits", "bypass") }; direction = "lower-only" }, [pscustomobject]@{ name = "fixture.floor"; layers = @("L0", "L1", "L4"); value = [pscustomobject]@{ kind = "enum"; values = @("low", "mid", "high") }; direction = "raise-only" })
function Get-Ceiling { param([object[]]$Extra, [string]$Key = "fixture.ceiling") return (Get-HordeEngineSetting -Resolution (Resolve ($base + $Extra) -Registry $regD) -Key $Key) }
$own = New-Layer "L1" (New-Doc @(New-Rule "owner" @{} @{ "fixture.ceiling" = "ask"; "fixture.floor" = "mid" })) -Source "owner"
$s = Get-Ceiling @($own, (New-Layer "L4" (New-Doc @(New-Rule "agent-raise" @{} @{ "fixture.ceiling" = "bypass" } "cli"))))
Check ($s.answer.value -ceq "ask" -and @($s.refused | Where-Object { $_.rule -ceq "agent-raise" -and $_.why -like "*lower-only*" }).Count -eq 1) "a live rule that raises a lower-only key above the owner's value is refused, recorded, and the owner's value stands"
$s = Get-Ceiling @($own, (New-Layer "L4" (New-Doc @(New-Rule "agent-lower" @{} @{ "fixture.ceiling" = "plan" } "cli"))))
Check ($s.answer.value -ceq "plan" -and @($s.refused).Count -eq 0) "CONTROL: one that lowers it resolves"
$ownHigh = New-Layer "L1" (New-Doc @(New-Rule "owner-high" @{} @{ "fixture.ceiling" = "bypass" })) -Source "owner"
$s = Get-Ceiling @($ownHigh, (New-Layer "L3" (New-Doc @(New-Rule "spec-lower" @{} @{ "fixture.ceiling" = "plan" }))), (New-Layer "L5" (New-Doc @(New-Rule "spawn-raise" @{} @{ "fixture.ceiling" = "edits" }))))
Check ($s.answer.value -ceq "plan" -and @($s.refused | Where-Object { $_.rule -ceq "spawn-raise" }).Count -eq 1) "each layer may only lower what the layers below it left: a spawn cannot raise back what a run spec lowered"
$s = Get-Ceiling @((New-Layer "L1" (New-Doc @(New-Rule "owner-raise" @{} @{ "fixture.ceiling" = "bypass" })) -Source "owner"))
Check ($s.answer.value -ceq "bypass") "the owner's own layer may set it anywhere: direction binds only the layers above L1"
$s = Get-HordeEngineSetting -Resolution (Resolve @((New-Layer "L4" (New-Doc @(New-Rule "alone" @{} @{ "fixture.ceiling" = "edits" } "cli")))) -Registry $regD) -Key "fixture.ceiling"
Check ($s.answer.state -ne "known" -and @($s.refused | Where-Object { $_.rule -ceq "alone" -and $_.why -like "*nothing below*" }).Count -eq 1) "with no owner's value to lower from, a higher layer's value is refused, never taken as the base"
# REVIEW OF PR #74 (HIGH): only the most specific rule of a layer was checked, so when it was refused a
# less specific rule of the same layer that raised just as far won instead. Every rule is checked
# before specificity chooses among the ones left.
$s = Get-Ceiling @($own, (New-Layer "L4" (New-Doc @((New-Rule "raise-goblins" @{ role = "goblin" } @{ "fixture.ceiling" = "bypass" } "cli"), (New-Rule "raise-all" @{} @{ "fixture.ceiling" = "bypass" } "cli")))))
Check ($s.answer.value -ceq "ask" -and @($s.refused | ForEach-Object { $_.rule } | Sort-Object) -join "," -ceq "raise-all,raise-goblins") "the reviewer's case in L4: a specific and a general rule both raising to bypass are both refused, and ask stands"
$s = Get-Ceiling @($own, (New-Layer "L5" (New-Doc @((New-Rule "spawn-goblins" @{ role = "goblin" } @{ "fixture.ceiling" = "edits" }), (New-Rule "spawn-all" @{} @{ "fixture.ceiling" = "edits" })))))
Check ($s.answer.value -ceq "ask" -and @($s.refused).Count -eq 2) "the reviewer's case in L5: both rules raising to edits are refused"
$s = Get-Ceiling @($own, (New-Layer "L4" (New-Doc @((New-Rule "to-bypass" @{ role = "goblin" } @{ "fixture.ceiling" = "bypass" } "cli"), (New-Rule "to-edits" @{} @{ "fixture.ceiling" = "edits" } "cli")))))
Check ($s.answer.value -ceq "ask" -and @($s.refused).Count -eq 2) "a layer whose two rules both raise, to different values, gives neither"
$s = Get-Ceiling @($own, (New-Layer "L4" (New-Doc @((New-Rule "to-bypass" @{ role = "goblin" } @{ "fixture.ceiling" = "bypass" } "cli"), (New-Rule "to-plan" @{} @{ "fixture.ceiling" = "plan" } "cli")))))
Check ($s.answer.value -ceq "plan" -and @($s.refused | Where-Object { $_.rule -ceq "to-bypass" }).Count -eq 1) "a layer where the specific rule raises and a less specific one lowers gives the lowered value"
$tieSpec = New-Layer "L3" (New-Doc @((New-Rule "tie-plan" @{ role = "goblin" } @{ "fixture.ceiling" = "plan" }), (New-Rule "tie-edits" @{ role = "goblin" } @{ "fixture.ceiling" = "edits" })))
$s = Get-Ceiling @($ownHigh, $tieSpec, (New-Layer "L5" (New-Doc @(New-Rule "after-tie" @{} @{ "fixture.ceiling" = "edits" }))))
Check (@($s.refused | Where-Object { $_.rule -ceq "after-tie" }).Count -eq 1) "after a tie in a lower layer, the next layer is held to the strictest of the tied values, never the most permissive"
# REVIEW OF PR #74, round 3, NEW-A (HIGH): a value outside the enum ranked as -1, which counted as a
# lowering and then stood as the MOST permissive level. The resolver must not rely on the checker
# having run: an unrankable value is refused and recorded, never ranked, and fails closed.
foreach ($bad in @("zzz", "Bypass", 3)) {
    $s = Get-Ceiling @($own, (New-Layer "L4" (New-Doc @(New-Rule "bad-value" @{} @{ "fixture.ceiling" = $bad } "cli"))), (New-Layer "L5" (New-Doc @(New-Rule "spawn-bypass" @{} @{ "fixture.ceiling" = "bypass" }))))
    Check ($s.answer.value -ceq "ask" -and @($s.refused | Where-Object { $_.rule -ceq "bad-value" -and $_.why -like "*not a value*" }).Count -eq 1 -and @($s.refused | Where-Object { $_.rule -ceq "spawn-bypass" }).Count -eq 1) ("an L4 value outside the enum (" + $bad + ") is refused, and does not open the way for an L5 bypass")
}
$s = Get-Ceiling @($own, (New-Layer "L4" (New-Doc @(New-Rule "only-bad" @{} @{ "fixture.ceiling" = "zzz" } "cli"))))
Check ($s.answer.value -ceq "ask") "a layer whose only rule is outside the enum contributes nothing"
$s = Get-Ceiling @($own, (New-Layer "L3" (New-Doc @((New-Rule "tie-plan" @{ role = "goblin" } @{ "fixture.ceiling" = "plan" }), (New-Rule "tie-bad" @{ role = "goblin" } @{ "fixture.ceiling" = "zzz" })))), (New-Layer "L5" (New-Doc @(New-Rule "spawn-bypass" @{} @{ "fixture.ceiling" = "bypass" }))))
Check ($s.answer.value -ceq "plan" -and @($s.refused | Where-Object { $_.rule -ceq "spawn-bypass" }).Count -eq 1) "a tie with a value outside the enum is no tie: the bad value is refused, and the good one holds the layers above"
$badBase = New-Layer "L1" (New-Doc @(New-Rule "owner-bad" @{} @{ "fixture.ceiling" = "zzz" })) -Source "owner"
$s = Get-Ceiling @($badBase, (New-Layer "L4" (New-Doc @(New-Rule "agent-any" @{} @{ "fixture.ceiling" = "edits" } "cli"))))
Check ($s.answer.state -ne "known" -and @($s.refused | Where-Object { $_.rule -ceq "owner-bad" }).Count -eq 1 -and @($s.refused | Where-Object { $_.rule -ceq "agent-any" }).Count -eq 1) "an owner's value outside the enum is no base: nothing above may stand on it"
$s = Get-Ceiling @($own, (New-Layer "L4" (New-Doc @(New-Rule "lower-floor" @{} @{ "fixture.floor" = "low" } "cli")))) "fixture.floor"
Check ($s.answer.value -ceq "mid" -and @($s.refused | Where-Object { $_.rule -ceq "lower-floor" -and $_.why -like "*raise-only*" }).Count -eq 1) "a raise-only key cannot be lowered from a layer above the owner's"
$s = Get-Ceiling @($own, (New-Layer "L4" (New-Doc @(New-Rule "raise-floor" @{} @{ "fixture.floor" = "high" } "cli")))) "fixture.floor"
Check ($s.answer.value -ceq "high") "CONTROL: and can be raised"

Write-Host ""
Write-Host "--- the registry, the role requirements and the built-in layer that resolution reads ---" -ForegroundColor Cyan
function Get-RegRefusal { param([string]$Text) try { $null = Read-HordeConfigKeysText -Text $Text; return "" } catch { return "$($_.Exception.Message)" } }
$regText = [System.IO.File]::ReadAllText((Join-Path $root "core\config-keys.json"))
Check ((Get-RegRefusal ($regText.Replace('"value": { "kind": "model" }', '"value": { "kind": "model" }, "tuner": "raise-only"'))) -like "*tuner*only on an enum*") "the registry refuses tuner raise-only on a key that is not an enum: there is no order to raise in"
Check ((Get-RegRefusal ($regText.Replace('"value": { "kind": "model" }', '"value": { "kind": "enum", "values": ["a", "b"] }, "tuner": "free"'))) -like "*tuner 'free'*") "and a tuner rule other than raise-only"
Check ((Get-RegRefusal ($regText.Replace('"value": { "kind": "model" }', '"value": { "kind": "enum", "values": ["a", "b"] }, "tuner": "raise-only"'))) -eq "") "CONTROL: raise-only on an enum loads"
$reqReal = Get-HordeRoleRequirements
Check (@($reqReal.goblin).Count -ge 1 -and @($reqReal.warchief).Count -ge @($reqReal.goblin).Count) "the role requirements load, and the warchief needs at least what a goblin needs"
$tmpReq = Join-Path $env:TEMP ("horde-role-req-" + [guid]::NewGuid().ToString("N") + ".json")
try {
    [System.IO.File]::WriteAllText($tmpReq, '{ "requires": { "warchief": ["telepathy"], "orc": [], "goblin": [] } }')
    Check (Throws { Get-HordeRoleRequirements -Path $tmpReq } "telepathy") "a requirement the capability vocabulary does not have is refused, so a typo cannot require nothing"
    [System.IO.File]::WriteAllText($tmpReq, '{ "requires": { "warchief": [], "orc": [] } }')
    Check (Throws { Get-HordeRoleRequirements -Path $tmpReq } "goblin has no requirement list") "a role with no requirement list is refused"

    # DUTIES: what a role must DO, beside what it needs from its harness. Each is checked when the
    # file is read, so a duty cannot name a role that does not exist, say nothing, or point at a
    # document that is not there.
    $okRequires = '"requires": { "warchief": [], "orc": [], "goblin": [] }'
    $okDoc = "planning/ledger/README.md"
    [System.IO.File]::WriteAllText($tmpReq, '{ ' + $okRequires + ', "duties": { "warchief": [ { "id": "keeps-x", "rule": "keep x", "doc": "' + $okDoc + '" } ] } }')
    Check (@((Get-HordeRoleDuties -Path $tmpReq).warchief).Count -eq 1) "CONTROL: a well-formed duty loads"
    Check ((Get-HordeRoleRequirements -Path $tmpReq).PSObject.Properties["warchief"] -ne $null) "CONTROL: and the requirements beside it still load"
    [System.IO.File]::WriteAllText($tmpReq, '{ ' + $okRequires + ' }')
    Check (@((Get-HordeRoleDuties -Path $tmpReq).PSObject.Properties).Count -eq 0) "a file with no duties section has no duties, and is not refused"
    [System.IO.File]::WriteAllText($tmpReq, '{ ' + $okRequires + ', "duties": { "warlord": [ { "id": "keeps-x", "rule": "keep x" } ] } }')
    Check (Throws { Get-HordeRoleRequirements -Path $tmpReq } "warlord, which is not a role") "a duty for a role that does not exist is refused, so a typo cannot bind nobody"
    [System.IO.File]::WriteAllText($tmpReq, '{ ' + $okRequires + ', "duties": { "warchief": [ { "id": "keeps-x", "rule": " " } ] } }')
    Check (Throws { Get-HordeRoleRequirements -Path $tmpReq } "keeps-x has no rule") "a duty with no rule text is refused"
    [System.IO.File]::WriteAllText($tmpReq, '{ ' + $okRequires + ', "duties": { "warchief": [ { "id": "Keeps X", "rule": "keep x" } ] } }')
    Check (Throws { Get-HordeRoleRequirements -Path $tmpReq } "id 'Keeps X'") "a duty id that is not lowercase-and-dashes is refused"
    [System.IO.File]::WriteAllText($tmpReq, '{ ' + $okRequires + ', "duties": { "warchief": [ { "id": "keeps-x", "rule": "keep x", "doc": "planning/roles/no-such-role.md" } ] } }')
    Check (Throws { Get-HordeRoleRequirements -Path $tmpReq } "no-such-role.md, which is not in the repository") "a duty pointing at a document that is not there is refused"
    [System.IO.File]::WriteAllText($tmpReq, '{ ' + $okRequires + ', "duties": { "warchief": [ { "id": "keeps-x", "rule": "keep x", "doc": "../outside.md" } ] } }')
    Check (Throws { Get-HordeRoleRequirements -Path $tmpReq } "repository-relative") "a duty document outside the repository is refused"
} finally { Remove-Item -LiteralPath $tmpReq -Force -ErrorAction SilentlyContinue }

# THE WARCHIEF'S ANALYST (protocol change, 2026-10-08). The rule is held as data, worded as
# given, and the role document it points at quotes it verbatim, so the two cannot drift apart.
$analystRule = "every warchief keeps one read-only analyst under it, reporting only to its warchief; speed, accuracy, efficiency and parallelisation first, cost second"
$dutiesReal = Get-HordeRoleDuties
$keeps = @(@($dutiesReal.warchief) | Where-Object { $_.id -ceq "keeps-analyst" })
Check ($keeps.Count -eq 1) "the warchief has exactly one keeps-analyst duty"
Check ($keeps.Count -eq 1 -and $keeps[0].rule -ceq $analystRule) "the duty is worded exactly as the rule was given"
Check ($keeps.Count -eq 1 -and $keeps[0].doc -ceq "planning/roles/fleet-analyst.md") "the duty points at the analyst's role document"
$docPath = Join-Path $root "planning\roles\fleet-analyst.md"
$docText = ""
if (Test-Path -LiteralPath $docPath) { $docText = [System.IO.File]::ReadAllText($docPath) }
Check ($docText.Length -gt 0) "CONTROL: the analyst's role document was read"
Check ($docText.Contains($analystRule)) "the role document quotes the warchief's duty verbatim"
Check (@([System.Text.Encoding]::UTF8.GetBytes($docText) | Where-Object { $_ -gt 127 }).Count -eq 0) "the role document is ASCII only"
Check ($docText -notmatch '(?i)[a-z]:\\|\\Users\\|/Users/|/home/|~/') "the role document names no absolute or home path"
Check ($docText.Contains("schema/finding.v1.json")) "the role document names the finding record by its schema"
foreach ($heading in @("## Reads", "## Never", "## Reports to", "## Produces")) {
    Check ($docText.Contains($heading)) ("the role document has the section '" + $heading + "'")
}
$l0 = @(Get-HordeBuiltinLayer -Root $root)
$realDesc = (Get-HordeAgentDescriptors -Root $root).value
Check ($l0.Count -ge 1 -and @($l0 | Where-Object { $_.layer -cne "L0" }).Count -eq 0) ("the repository's built-in layer is read from the harness folders, every file as L0 (" + $l0.Count + " files)")
$f = @(Test-HordeEngineConfig -Documents $l0 -Descriptors $realDesc)
Check ($f.Count -eq 0) ("the built-in layer passes its own checker" + $(if ($f.Count) { " (" + (@($f | ForEach-Object { $_.code + " " + $_.detail }) -join " | ") + ")" } else { "" }))
foreach ($role in @("warchief", "orc", "goblin")) {
    $res = Resolve-HordeEngine -Layers $l0 -Target @{ role = $role } -Descriptors $realDesc -Now $now
    Check ($res.binding.state -eq "known" -and $null -eq $res.binding.value.model) ("with no user file, a " + $role + " resolves to a whole binding with the harness's own model (zero configuration)")
}

Complete-HordeSuite -Success "every target resolves exactly as the layers and selectors say, and the binding and capabilities are checked whole"
