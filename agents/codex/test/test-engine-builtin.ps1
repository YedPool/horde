# WHAT DOES THIS HARNESS GIVE THE ENGINE RESOLVER, AND WHICH ROLES CAN IT RUN TODAY?
#
# agents/codex/engine.json is part of the built-in layer (L0, engines E4): its native provider and
# its profile, and no default rule - the fleet's default is another harness's. A user rule choosing
# the profile for wargs is the founder's route to codex wargs; whether a role may run here is
# decided by the role's requirements against this harness's descriptor.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\EngineResolve.ps1")

$l0 = @(Get-HordeBuiltinLayer -Root $root)
$desc = (Get-HordeAgentDescriptors -Root $root).value
$now = [datetime]::UtcNow
$user = Read-HordeEngineLayerText -Layer "L1" -Source "a user file" -Text '{ "schemaVersion": 1, "rules": [ { "id": "codex-wargs", "match": { "role": "warg" }, "set": { "profile": "codex" }, "writtenBy": "user" }, { "id": "codex-orcs", "match": { "role": "orc" }, "set": { "profile": "codex" }, "writtenBy": "user" } ] }'
Check (@(Test-HordeEngineConfig -Documents (@($l0) + @($user)) -Descriptors $desc).Count -eq 0) "a user file sending wargs and orcs to this harness's profile is clean"
$g = Resolve-HordeEngine -Layers (@($l0) + @($user)) -Target @{ role = "warg" } -Descriptors $desc -Now $now
Check ($g.binding.state -eq "known" -and $g.binding.value.harness -ceq "codex" -and $g.binding.value.provider -ceq "openai") "a warg then runs on this harness, on its own login"
Check ($g.capabilities.value.ok -eq $true) "and has what a warg needs: resume and the report hook"
# Orcs since the measurement of 2026-10-02: delivery into a running session and its receipt are both
# measured yes, so an orc no longer needs the host to type for it.
$o = Resolve-HordeEngine -Layers (@($l0) + @($user)) -Target @{ role = "orc" } -Descriptors $desc -Now $now
Check ($o.binding.state -eq "known" -and $o.capabilities.value.ok -eq $true) "an orc runs on this harness too, on any host: message-inject and delivery-receipt are measured"
$w = Resolve-HordeEngine -Layers (@($l0) + @($user)) -Target @{ role = "warchief" } -Descriptors $desc -Now $now
Check ($w.binding.value.harness -cne "codex") "CONTROL: the warchief, which no rule sends here, stays on the default harness"

Complete-HordeSuite -Success "this harness can run wargs and orcs"
