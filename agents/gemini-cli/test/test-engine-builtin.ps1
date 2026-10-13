# WHAT DOES THIS HARNESS GIVE THE ENGINE RESOLVER, AND WHICH ROLES CAN IT RUN TODAY?
#
# agents/gemini-cli/engine.json is part of the built-in layer (L0, engines E4): its native provider
# and its profile. A warg needs resume and the report hook (core/role-requirements.json); here both
# are unverified until engines G1 and G3 measure them, so this suite pins that a warg is REFUSED on
# this harness today, with those two named. When a measurement moves either to yes, this suite fails
# and is updated in the same pull request - the refusal never silently becomes an acceptance.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\EngineResolve.ps1")

$l0 = @(Get-HordeBuiltinLayer -Root $root)
$desc = (Get-HordeAgentDescriptors -Root $root).value
$now = [datetime]::UtcNow
$user = Read-HordeEngineLayerText -Layer "L1" -Source "a user file" -Text '{ "schemaVersion": 1, "rules": [ { "id": "gemini-wargs", "match": { "role": "warg" }, "set": { "profile": "gemini" }, "writtenBy": "user" } ] }'
Check (@(Test-HordeEngineConfig -Documents (@($l0) + @($user)) -Descriptors $desc).Count -eq 0) "a user file sending wargs to this harness's profile is clean"
$g = Resolve-HordeEngine -Layers (@($l0) + @($user)) -Target @{ role = "warg" } -Descriptors $desc -Now $now
Check ($g.binding.state -eq "known" -and $g.binding.value.harness -ceq "gemini-cli" -and $g.binding.value.provider -ceq "google") "the binding resolves: this harness, on its own login"
$missing = @($g.capabilities.value.missing | ForEach-Object { $_.name })
Check ($g.capabilities.value.ok -eq $false -and ($missing -join ",") -ceq "resume,report-hook") ("but a warg is refused today: resume and report-hook are unverified until G1 and G3 measure them (" + ($missing -join ",") + ")")

Complete-HordeSuite -Success "this harness resolves, and its wargs wait on two measurements"
