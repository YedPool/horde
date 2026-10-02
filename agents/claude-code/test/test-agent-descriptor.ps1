# DOES THIS HARNESS'S DESCRIPTOR LOAD, AND SAY WHAT THE ENGINES PLAN RELIES ON?
#
# agents/claude-code/agent.json, read by core/AgentDescriptor.ps1 (engines plan step E2). The generic
# loader rules are test/test-agent-descriptor.ps1's, on a neutral fixture; this suite holds only the
# checks that name this harness (CONTRIBUTING 14). Each fact asserted here is one a later step acts on,
# so a change to it must be a reviewed change to this suite too.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\AgentDescriptor.ps1")

$d = Read-HordeAgentDescriptor -Path (Join-Path $root "agents\claude-code\agent.json")
Check ($d.name -ceq "claude-code") "the descriptor loads strictly, and names its own folder"

Write-Host ""
Write-Host "--- what E3 pairs it with ---" -ForegroundColor Cyan
Check ((@($d.protocols) -join ",") -ceq "anthropic-messages") "it speaks the Anthropic Messages format and nothing else, so a provider serving only another format is refused (E3)"
Check ($d.nativeProvider -ceq "anthropic") "its own login is the anthropic provider's: that subscription runs on this harness alone (agent-engines decision 7)"

Write-Host ""
Write-Host "--- what the launcher scrubs (engines P2) ---" -ForegroundColor Cyan
$p2 = @("ANTHROPIC_BASE_URL", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY", "ANTHROPIC_MODEL",
    "ANTHROPIC_DEFAULT_OPUS_MODEL", "ANTHROPIC_DEFAULT_SONNET_MODEL", "ANTHROPIC_DEFAULT_HAIKU_MODEL", "ANTHROPIC_DEFAULT_FABLE_MODEL",
    "CLAUDE_CODE_SUBAGENT_MODEL", "API_TIMEOUT_MS", "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS", "CLAUDE_CODE_AUTO_COMPACT_WINDOW", "CLAUDE_CODE_EFFORT_LEVEL")
$owned = @($d.ownedEnv | ForEach-Object { $_.name })
Check (($owned | Sort-Object) -join "," -ceq (($p2 | Sort-Object) -join ",")) ("it owns exactly the " + $p2.Count + " variables the engines plan's step P2 lists")

Write-Host ""
Write-Host "--- what the plan's other steps read ---" -ForegroundColor Cyan
Check ((Test-HordeAgentCapability -Descriptor $d -Name "session.remoteName") -eq $true) "session.remoteName is yes: a web session can be named at birth (engines group I, N1)"
Check ((Test-HordeAgentCapability -Descriptor $d -Name "name-at-spawn") -eq $true) "a session is named at spawn"
Check ((Test-HordeAgentCapability -Descriptor $d -Name "session-id-preset") -eq $true) "a session id can be chosen before the session starts"
Check ((Test-HordeAgentCapability -Descriptor $d -Name "provider-select") -eq $false) "another provider stays unverified until engines P3 measures one"
Check ($d.events."turn-ended".hook -ceq "Stop" -and $d.events."turn-ended".support -ceq "yes") "a turn's end is its Stop hook, which the fleet runs on today"
Check ([regex]::IsMatch("2b0f2c5e-6a1d-4c3b-9e8f-0a1b2c3d4e5f", $d.sessionIdPattern)) "CONTROL: a session id of the shape it gives matches its pattern"
Check (-not [regex]::IsMatch("x2b0f2c5e-6a1d-4c3b-9e8f-0a1b2c3d4e5f", $d.sessionIdPattern)) "an id with anything before the UUID does not"

Write-Host ""
Write-Host "--- every permission level is a flag this harness has (remote R9) ---" -ForegroundColor Cyan
$frag = @{}
foreach ($l in @(Get-HordePermissionLevels)) { $frag[$l.name] = Get-HordePermissionArgs -Descriptor $d -Level $l.name }
Check (@($frag.Values | Where-Object { $_.state -cne "known" }).Count -eq 0) "every level of the vocabulary is expressible here"
Check ((@($frag["bypass"].value) -join " ") -ceq "--dangerously-skip-permissions") "bypass is the skip-permissions flag the fleet spawns with today"
Check ((@($frag["plan"].value) -join " ") -ceq "--permission-mode plan") "plan is the plan permission mode"
Check ((@($frag["edits"].value) -join " ") -ceq "--permission-mode acceptEdits") "edits is the mode that accepts edits"

Complete-HordeSuite -Success "this harness's descriptor loads and says what the plan relies on"
