# DOES THIS HARNESS'S DESCRIPTOR LOAD, AND SAY WHAT THE ENGINES PLAN RELIES ON?
#
# agents/gemini-cli/agent.json, read by core/AgentDescriptor.ps1 (engines plan step E2). The generic
# loader rules are test/test-agent-descriptor.ps1's, on a neutral fixture; this suite holds only the
# checks that name this harness (CONTRIBUTING 14).
#
# HOW ITS HELP WAS READ. `gemini --help` writes into ~/.gemini: on 2026-10-02 it left six
# projects.json.<uuid>.tmp files there, as the old system had also seen (YedPool/wezfleet
# lib/Agents.ps1). So the flags in agent.json were read with USERPROFILE and HOME pointed at a scratch
# folder, and this suite never runs the program at all.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\AgentDescriptor.ps1")

$d = Read-HordeAgentDescriptor -Path (Join-Path $root "agents\gemini-cli\agent.json")
Check ($d.name -ceq "gemini-cli") "the descriptor loads strictly, and names its own folder"

Write-Host ""
Write-Host "--- what E3 pairs it with ---" -ForegroundColor Cyan
Check ((@($d.protocols) -join ",") -ceq "google-genai") "it speaks the Google GenAI format and nothing else, so any provider but google's is refused (E3)"
Check ($d.nativeProvider -ceq "google") "its own login is the google provider's"

Write-Host ""
Write-Host "--- what the plan's other steps read ---" -ForegroundColor Cyan
$a = Get-HordeAgentCapability -Descriptor $d -Name "message-inject"
Check ($a.state -eq "unknown") "delivering into a live session is unverified until measured (engines G1), so this harness cannot yet be an orc or the warchief"
$a = Get-HordeAgentCapability -Descriptor $d -Name "session.remoteName"
Check ($a.state -eq "unknown") "session.remoteName is unverified, so a web session name is answered unknown, never ok (engines group I)"
Check ((Test-HordeAgentCapability -Descriptor $d -Name "session-id-preset") -eq $true) "a session id can be chosen before the session starts"
Check ($d.events."turn-ended".hook -ceq "AfterAgent" -and $d.events."turn-started".hook -ceq "BeforeAgent") "the plan's event map: AfterAgent ends a turn, BeforeAgent starts one (engines G1)"
Check (@($d.events.PSObject.Properties | Where-Object { $_.Value.support -ceq "yes" }).Count -eq 0) "no hook is claimed to fire before one has been seen firing"
Check ([regex]::IsMatch("2b0f2c5e-6a1d-4c3b-9e8f-0a1b2c3d4e5f", $d.sessionIdPattern)) "CONTROL: a UUID matches its pattern"

Write-Host ""
Write-Host "--- every permission level is a flag this harness has (remote R9) ---" -ForegroundColor Cyan
$frag = @{}
foreach ($l in @(Get-HordePermissionLevels)) { $frag[$l.name] = Get-HordePermissionArgs -Descriptor $d -Level $l.name }
Check (@($frag.Values | Where-Object { $_.state -cne "known" }).Count -eq 0) "every level of the vocabulary is expressible here"
Check ((@($frag["plan"].value) -join " ") -ceq "--approval-mode plan" -and (@($frag["ask"].value) -join " ") -ceq "--approval-mode default") "plan and ask are its plan and default approval modes"
Check ((@($frag["edits"].value) -join " ") -ceq "--approval-mode auto_edit" -and (@($frag["bypass"].value) -join " ") -ceq "--approval-mode yolo") "edits and bypass are its auto_edit and yolo approval modes"

Complete-HordeSuite -Success "this harness's descriptor loads and says what the plan relies on"
