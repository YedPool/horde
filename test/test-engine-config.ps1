# IS AN ENGINE CONFIGURATION REFUSED FOR EVERY FINDING ITS CHECKER LISTS, AND ONLY FOR THAT ONE?
#
# core/EngineConfig.ps1 (engines plan step E3) checks the files that say which harness, provider and
# model each part of the fleet runs on: the built-in layer (L0), the user's file (L1) and the live
# rules (L4). Each finding in its header has one case here: the golden documents with ONE edit, which
# must produce that finding's code, so a refusal for some other reason does not count.
#
# NEUTRAL NAMES ONLY (CONTRIBUTING 14): two fixture harnesses, harness-a (speaks anthropic-messages,
# native provider provider-a, from E2's fixture) and harness-b (speaks openai-responses, native
# provider-b), and fixture providers, aliases and profiles.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\EngineConfig.ps1")

$fx = Join-Path $root "test\fixtures\engine-config"
$texts = @{
    L0 = [System.IO.File]::ReadAllText((Join-Path $fx "builtin.json"))
    L1 = [System.IO.File]::ReadAllText((Join-Path $fx "user.json"))
    L4 = [System.IO.File]::ReadAllText((Join-Path $fx "live.json"))
}
$aText = [System.IO.File]::ReadAllText((Join-Path $root "test\fixtures\agent-descriptor\agents\harness-a\agent.json"))
$bText = $aText.Replace('"name": "harness-a"', '"name": "harness-b"').Replace('"protocols": ["anthropic-messages"]', '"protocols": ["openai-responses"]').Replace('"nativeProvider": "provider-a"', '"nativeProvider": "provider-b"')
$descriptors = @{
    "harness-a" = (Read-HordeAgentDescriptorText -Text $aText -ExpectedName "harness-a")
    "harness-b" = (Read-HordeAgentDescriptorText -Text $bText -ExpectedName "harness-b")
}
Check ($bText -ne $aText -and $descriptors["harness-b"].nativeProvider -ceq "provider-b") "CONTROL: the second fixture harness is the first with its protocol and native provider changed"

function New-Docs {
    # The three golden documents as parsed objects, fresh each time, so an edit touches one case only.
    return [ordered]@{ L0 = ($texts.L0 | ConvertFrom-Json); L1 = ($texts.L1 | ConvertFrom-Json); L4 = ($texts.L4 | ConvertFrom-Json) }
}
function ConvertTo-DocList {
    param($Docs)
    return @(foreach ($k in @($Docs.Keys)) { [pscustomobject]@{ layer = $k; source = ("fixture " + $k); text = ($Docs[$k] | ConvertTo-Json -Depth 12) } })
}
function Get-Findings {
    param($DocList, $Registry = $null)
    if ($null -eq $Registry) { return @(Test-HordeEngineConfig -Documents $DocList -Descriptors $descriptors) }
    return @(Test-HordeEngineConfig -Documents $DocList -Descriptors $descriptors -Registry $Registry)
}
function Test-Finding {
    # One case: the golden documents with one edit must give the finding Code (as an error unless
    # -Severity says otherwise), and its detail must contain Like when given.
    param([string]$What, [scriptblock]$Edit, [string]$Code, [string]$Like = "", [string]$Severity = "error")
    $docs = New-Docs
    & $Edit $docs
    $f = @(Get-Findings (ConvertTo-DocList $docs))
    $hit = @($f | Where-Object { $_.code -ceq $Code -and $_.severity -ceq $Severity -and ($Like -eq "" -or $_.detail -like ("*" + $Like + "*")) })
    $codes = (@($f | ForEach-Object { $_.severity + ":" + $_.code }) -join ", ")
    Check ($hit.Count -ge 1) ($What + " -> " + $Severity + " " + $Code + $(if ($hit.Count -eq 0) { " (got: " + $codes + ")" } else { "" }))
}
function Add-Prop { param($Object, [string]$Name, $Value) $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
function Get-Rule { param($Doc, [string]$Id) return @($Doc.rules | Where-Object { $_.id -ceq $Id })[0] }
function Get-Profile { param($Doc, [string]$Name) return @($Doc.profiles | Where-Object { $_.name -ceq $Name })[0] }

Write-Host ""
Write-Host "--- the golden documents are clean ---" -ForegroundColor Cyan
$golden = @(Get-Findings (ConvertTo-DocList (New-Docs)))
Check ($golden.Count -eq 0) ("CONTROL: the golden built-in, user and live documents give no finding" + $(if ($golden.Count) { " (got: " + (@($golden | ForEach-Object { $_.code + " " + $_.detail }) -join " | ") + ")" } else { "" }))
$fromFiles = @(Test-HordeEngineConfig -Documents @(
    [pscustomobject]@{ layer = "L0"; source = "builtin.json"; text = $texts.L0 },
    [pscustomobject]@{ layer = "L1"; source = "user.json"; text = $texts.L1 },
    [pscustomobject]@{ layer = "L4"; source = "live.json"; text = $texts.L4 }) -Descriptors $descriptors)
Check ($fromFiles.Count -eq 0) "CONTROL: and so do the files' own texts, before any round trip"

Write-Host ""
Write-Host "--- the text and the shape ---" -ForegroundColor Cyan
$dupList = @([pscustomobject]@{ layer = "L1"; source = "user"; text = $texts.L1.Replace('"schemaVersion": 1,', '"schemaVersion": 1, "schemaVersion": 1,') })
$f = @(Get-Findings $dupList)
Check (@($f | Where-Object { $_.code -ceq "duplicate-key" }).Count -ge 1) "a key repeated in one object -> duplicate-key"
Test-Finding "a field the schema does not have" { param($d) Add-Prop $d.L1 "vendor" "someone" } "schema" "vendor"
Test-Finding "a rule with no writtenBy" { param($d) (Get-Rule $d.L1 "user-default").PSObject.Properties.Remove("writtenBy") } "schema" "writtenBy"
Test-Finding "a credential kind the plan dropped" { param($d) $d.L1.providers[0].credential.kind = "os-store" } "schema" "kind"
$f = @(Get-Findings @([pscustomobject]@{ layer = "L1"; source = "user"; text = "{ not json" }))
Check (@($f | Where-Object { $_.code -ceq "not-json" }).Count -eq 1) "text that is not JSON -> not-json"

Write-Host ""
Write-Host "--- layers ---" -ForegroundColor Cyan
$f = @(Get-Findings @([pscustomobject]@{ layer = "L2"; source = "a repo"; text = $texts.L1 }))
Check (@($f | Where-Object { $_.code -ceq "layer-not-built" -and $_.detail -like "*project layer*not built*" }).Count -eq 1) "a document offered as L2, the project layer -> layer-not-built (engines plan: deferred until a repo needs one)"
Check (Throws { Test-HordeEngineConfig -Documents @([pscustomobject]@{ layer = "L9"; source = "x"; text = $texts.L1 }) -Descriptors $descriptors } "L9") "a layer that does not exist is a mistake in the caller, and throws"
Test-Finding "a provider defined in the live rules" { param($d) Add-Prop $d.L4 "providers" @($d.L1.providers[0]) } "definition-layer" "providers"
Test-Finding "a profile defined in the live rules" { param($d) Add-Prop $d.L4 "profiles" @($d.L1.profiles[0]) } "definition-layer" "profiles"
Test-Finding "a revision outside the live rules" { param($d) Add-Prop $d.L1 "revision" 1 } "revision-layer"
Test-Finding "a tuner's rule in the user file" { param($d) (Get-Rule $d.L1 "user-default").writtenBy = "tuner" } "tuner-layer" "user-default"
Test-Finding "an expiry on a rule outside the live rules" { param($d) Add-Prop (Get-Rule $d.L1 "user-default") "until" "run-closed" } "until-layer" "user-default"

Write-Host ""
Write-Host "--- names, once, and defined before use ---" -ForegroundColor Cyan
Test-Finding "the user file redefining a built-in provider" { param($d) $d.L1.providers = @($d.L1.providers) + @($d.L0.providers[0]) } "duplicate-name" "provider-a"
Test-Finding "two profiles of one name" { param($d) $d.L1.profiles = @($d.L1.profiles) + @($d.L1.profiles[0]) } "duplicate-name" "alpha-big"
Test-Finding "two rules of one id in one layer" { param($d) $d.L1.rules = @($d.L1.rules) + @($d.L1.rules[0]) } "duplicate-name" "user-default"
Test-Finding "a profile naming a provider nobody defined" { param($d) (Get-Profile $d.L1 "gamma").provider = "provider-z" } "undefined-provider" "provider-z"
Test-Finding "an alias entry naming a provider nobody defined" { param($d) $d.L1.aliases[1].map[0].provider = "provider-z" } "undefined-provider" "provider-z"
Test-Finding "a rule setting a profile nobody defined" { param($d) (Get-Rule $d.L1 "goblins-gamma").set.profile = "delta" } "undefined-profile" "delta"
Test-Finding "a profile naming a harness with no descriptor" { param($d) (Get-Profile $d.L1 "gamma").harness = "harness-z" } "undefined-harness" "harness-z"
Test-Finding "a rule setting a provider nobody defined" { param($d) (Get-Rule $d.L4 "live-1").set.provider = "provider-z" } "undefined-provider" "provider-z"
Test-Finding "an alias with two entries for one provider" { param($d) $d.L1.aliases[0].map = @($d.L1.aliases[0].map) + @([pscustomobject]@{ provider = "provider-a"; model = "model-a-other" }) } "alias-provider-twice" "big"
Test-Finding "a provider that lacks a capability nobody defined" { param($d) $d.L1.providers[0].lacks = @("telepathy") } "unknown-capability" "telepathy"

Write-Host ""
Write-Host "--- rules ---" -ForegroundColor Cyan
Test-Finding "a rule that sets nothing" { param($d) (Get-Rule $d.L1 "user-default").set = [pscustomobject]@{} } "empty-set" "user-default"
Test-Finding "a fleet id without its run" { param($d) (Get-Rule $d.L1 "one-session").match.PSObject.Properties.Remove("run") } "fleet-without-run" "one-session"
Test-Finding "a key no setting has" { param($d) Add-Prop (Get-Rule $d.L1 "user-default").set "colour" "red" } "unknown-key" "colour"
Test-Finding "a harness value that is not a name" { param($d) (Get-Rule $d.L4 "live-2").set.harness = "Harness B" } "key-value" "harness"

Write-Host ""
Write-Host "--- the wire-format, subscription and pinning rules ---" -ForegroundColor Cyan
Test-Finding "a profile pairing a harness with a provider whose protocol it does not speak" { param($d) (Get-Profile $d.L1 "gamma").harness = "harness-b" } "wire-format" "gamma"
Test-Finding "a rule pairing them directly" { param($d) Add-Prop (Get-Rule $d.L4 "live-1").set "harness" "harness-b" } "wire-format" "live-1"
Test-Finding "a harness-login provider on a harness whose native provider is another" { param($d) $d.L1.providers = @($d.L1.providers) + @([pscustomobject]@{ name = "provider-d"; protocol = "anthropic-messages"; credential = [pscustomobject]@{ kind = "harness-login" } }); (Get-Profile $d.L1 "gamma").provider = "provider-d"; (Get-Profile $d.L1 "gamma").PSObject.Properties.Remove("model") } "subscription" "provider-d"
# CONTROL: the same harness with its own native harness-login provider is legal (the golden alpha).
Test-Finding "a model alias with no entry for the profile's provider" { param($d) (Get-Profile $d.L1 "alpha-big").model = "small" } "alias-missing" "small"
Test-Finding "a rule pairing a provider with an alias that has no entry for it" { param($d) (Get-Rule $d.L4 "live-1").set.provider = "provider-a" } "alias-missing" "small"
Test-Finding "a concrete model outside the provider's allowlist" { param($d) (Get-Profile $d.L1 "gamma").model = "model-c9" } "model-not-allowed" "model-c9"
Test-Finding "a provider whose protocol no harness speaks" { param($d) $d.L1.providers = @($d.L1.providers) + @([pscustomobject]@{ name = "provider-e"; protocol = "openai-chat"; credential = [pscustomobject]@{ kind = "env"; ref = "PROVIDER_E_TOKEN" } }) } "protocol-unspoken" "provider-e" "warning"
Test-Finding "an env credential with no variable named" { param($d) $d.L1.providers[0].credential.PSObject.Properties.Remove("ref") } "credential-ref" "provider-c"
Test-Finding "a harness-login credential that names a variable" { param($d) Add-Prop $d.L0.providers[0].credential "ref" "SOME_VAR" } "credential-ref" "provider-a"

Write-Host ""
Write-Host "--- a secret is refused, and never repeated ---" -ForegroundColor Cyan
# Planted values, each shaped like a real credential. The finding names where it is, never what it is.
$planted = @("sk-ant-api03-Zq9XyW8vU7tS6rR5qP4oN3mM2lK1jJ0iI", "AKIAZQ9XYW8VU7TS6RR5", "AIzaSyZq9XyW8vU7tS6rR5qP4oN3mM2lK1jJ0iI", "Zq9XyW8vU7tS6rR5qP4oN3mM2lK1jJ0iIhH")
foreach ($secret in $planted) {
    $docs = New-Docs
    (Get-Rule $docs.L1 "one-session").note = $secret
    $list = ConvertTo-DocList $docs
    Check ((@($list | ForEach-Object { $_.text }) -join "") -like ("*" + $secret + "*")) ("CONTROL: the planted value " + $secret.Substring(0, 4) + "... is in the text checked")
    $f = @(Get-Findings $list)
    $all = (@($f | ForEach-Object { $_.code + " " + $_.source + " " + $_.path + " " + $_.detail }) -join "`n")
    Check (@($f | Where-Object { $_.code -ceq "secret" -and $_.path -like "*note*" }).Count -eq 1) ("a value shaped like a secret (" + $secret.Substring(0, 4) + "...) -> secret, naming where it is")
    Check ($all -notlike ("*" + $secret + "*") -and $all -notlike ("*" + $secret.Substring(4, 12) + "*")) "and no finding repeats the value or any long part of it"
}
$docs = New-Docs
(Get-Rule $docs.L1 "one-session").note = "rotate the key every quarter, see the runbook"
Check (@(Get-Findings (ConvertTo-DocList $docs) | Where-Object { $_.code -ceq "secret" }).Count -eq 0) "CONTROL: an ordinary sentence is not a secret"

Write-Host ""
Write-Host "--- the settings registry is the seam for keys beyond the binding (metrics.level, remote.*) ---" -ForegroundColor Cyan
$reg = @(Get-HordeConfigKeys)
Check (@($reg | ForEach-Object { $_.name }) -join "," -ceq "profile,harness,provider,model") "the registry holds the four binding keys today, in order"
# A neutral key restricted to the user and live layers, the shape a node policy key will have (remote R9).
$fixtureReg = @($reg) + @([pscustomobject]@{ name = "fixture.level"; layers = @("L1", "L4"); value = [pscustomobject]@{ kind = "enum"; values = @("off", "low", "high") } })
$docs = New-Docs
Add-Prop (Get-Rule $docs.L1 "user-default").set "fixture.level" "low"
Check (@(Get-Findings (ConvertTo-DocList $docs) -Registry $fixtureReg).Count -eq 0) "CONTROL: a registered key, in a layer it allows, with a value it allows, is clean"
$docs = New-Docs
Add-Prop (Get-Rule $docs.L0 "builtin-default").set "fixture.level" "low"
Check (@(Get-Findings (ConvertTo-DocList $docs) -Registry $fixtureReg | Where-Object { $_.code -ceq "key-layer" -and $_.detail -like "*fixture.level*L0*" }).Count -eq 1) "a registered key in a layer it does not allow -> key-layer"
$docs = New-Docs
Add-Prop (Get-Rule $docs.L1 "user-default").set "fixture.level" "medium"
Check (@(Get-Findings (ConvertTo-DocList $docs) -Registry $fixtureReg | Where-Object { $_.code -ceq "key-value" -and $_.detail -like "*medium*" }).Count -eq 1) "a value its kind does not allow -> key-value"
Check (@(Get-Findings (ConvertTo-DocList $docs) | Where-Object { $_.code -ceq "unknown-key" }).Count -eq 1) "CONTROL: without the fixture registry the same key is unknown"

function Get-RegRefusal { param([string]$Text) try { $null = Read-HordeConfigKeysText -Text $Text; return "" } catch { return "$($_.Exception.Message)" } }
$regText = [System.IO.File]::ReadAllText((Join-Path $root "core\config-keys.json"))
Check ((Get-RegRefusal $regText) -eq "") "CONTROL: the registry's own text loads through the text reader"
Check ((Get-RegRefusal ($regText.Replace('"name": "harness"', '"name": "profile"'))) -like "*profile*twice*") "the registry refuses a key listed twice"
Check ((Get-RegRefusal ($regText.Replace('"layers": ["L0", "L1", "L3", "L4", "L5"], "value": { "kind": "model" }', '"layers": ["L0", "L9"], "value": { "kind": "model" }'))) -like "*model*layers*") "the registry refuses a layer that does not exist"
Check ((Get-RegRefusal ($regText.Replace('"value": { "kind": "model" }', '"value": { "kind": "colour" }'))) -like "*colour*") "the registry refuses a value kind it does not know"
Check ((Get-RegRefusal ($regText.Replace('"value": { "kind": "model" }', '"value": { "kind": "enum", "values": [] }'))) -like "*enum with no values*") "the registry refuses an enum with no values"
Check ((Get-RegRefusal ($regText.Replace('{ "name": "model",', '{ "name": "model", "name": "model",'))) -like "*more than once*") "the registry refuses a key repeated in one object"

Complete-HordeSuite -Success "an engine configuration is refused for each listed finding, and the golden one for none"
