# DOES THIS HARNESS'S DESCRIPTOR LOAD, AND SAY WHAT THE ENGINES PLAN RELIES ON?
#
# agents/codex/agent.json, read by core/AgentDescriptor.ps1 (engines plan step E2). The generic loader
# rules are test/test-agent-descriptor.ps1's, on a neutral fixture; this suite holds only the checks
# that name this harness (CONTRIBUTING 14).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\AgentDescriptor.ps1")

$d = Read-HordeAgentDescriptor -Path (Join-Path $root "agents\codex\agent.json")
Check ($d.name -ceq "codex") "the descriptor loads strictly, and names its own folder"

Write-Host ""
Write-Host "--- what E3 pairs it with ---" -ForegroundColor Cyan
Check ((@($d.protocols) -join ",") -ceq "openai-responses") "it speaks the OpenAI Responses format and nothing else (E3)"
Check ($d.nativeProvider -ceq "openai") "its own login is the openai provider's: that subscription runs on this harness alone (agent-engines decision 7)"

Write-Host ""
Write-Host "--- what the plan's other steps read ---" -ForegroundColor Cyan
Check ((Test-HordeAgentCapability -Descriptor $d -Name "name-at-spawn") -eq $false) "no session is named at spawn: the old system measured no name flag (engines E0's lesson), and 0.159.2 still has none"
$a = Get-HordeAgentCapability -Descriptor $d -Name "session.remoteName"
Check ($a.state -eq "unknown") "session.remoteName is unverified, so a web session name is answered unknown, never ok (engines group I)"
$a = Get-HordeAgentCapability -Descriptor $d -Name "message-inject"
Check ($a.state -eq "unknown") "delivering into a live session is unverified, so it is not counted as an agent capability (a host's text.send may still satisfy it)"
Check ((Test-HordeAgentCapability -Descriptor $d -Name "resume") -eq $true -and (Test-HordeAgentCapability -Descriptor $d -Name "report-hook") -eq $true) "it resumes by id and reports through hooks: what a goblin needs (engine-settings design 4.3)"
Check ($d.events."turn-ended".hook -ceq "Stop" -and $d.events."turn-ended".evidence -like "*only on a turn that completes*") "a turn's end is its Stop hook, and the descriptor carries that it does not fire on a failed or interrupted turn"
Check ([regex]::IsMatch("01a0cccc-1111-7222-8333-444455556666", $d.sessionIdPattern)) "CONTROL: the id of a rollout fixture in this folder matches its pattern"
Check (-not [regex]::IsMatch("rollout-01a0cccc-1111-7222-8333-444455556666", $d.sessionIdPattern)) "a rollout file name, with its prefix, does not"

Complete-HordeSuite -Success "this harness's descriptor loads and says what the plan relies on"
