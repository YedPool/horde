# WHAT DOES THIS HARNESS GIVE THE ENGINE RESOLVER WITH NO USER FILE AT ALL?
#
# agents/claude-code/engine.json is part of the built-in layer (L0, engines E4): its native provider,
# its profile, and the fleet's default rule. Zero configuration must keep behaving as the old system
# does - this harness, its own login, the model it picks - and every role must be able to run on it.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\EngineResolve.ps1")

$l0 = @(Get-HordeBuiltinLayer -Root $root)
$desc = (Get-HordeAgentDescriptors -Root $root).value
$now = [datetime]::UtcNow
foreach ($role in @("warchief", "orc", "warg")) {
    $res = Resolve-HordeEngine -Layers $l0 -Target @{ role = $role } -Descriptors $desc -Now $now
    Check ($res.binding.state -eq "known" -and $res.binding.value.harness -ceq "claude-code" -and $res.binding.value.provider -ceq "anthropic") ("with no user file a " + $role + " runs on this harness, on its own login")
    Check ($res.capabilities.state -eq "known" -and $res.capabilities.value.ok -eq $true) ("and has every capability a " + $role + " needs")
}
$s = Get-HordeEngineSetting -Resolution (Resolve-HordeEngine -Layers $l0 -Target @{ role = "warg" } -Descriptors $desc -Now $now) -Key "harness"
Check ($s.layer -ceq "L0" -and $s.source -ceq "agents/claude-code/engine.json" -and $s.rule -ceq "builtin-default") "and the answer says it came from this folder's default rule"

Complete-HordeSuite -Success "zero configuration runs every role on this harness"
