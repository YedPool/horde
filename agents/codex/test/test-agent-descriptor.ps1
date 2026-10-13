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
# Measured 2026-10-02 on 0.159.2 (planning/drafts/codex-delivery-measurement-2026-10-02.md): a message
# queued from outside reached a running session, and the rollout recorded each submitted message.
Check ((Test-HordeAgentCapability -Descriptor $d -Name "message-inject") -eq $true -and $d.capabilities."message-inject".evidence -like "*queue*running*") "a message can be delivered into a running session, by its own queue command - measured, not read off the help"
Check ((Test-HordeAgentCapability -Descriptor $d -Name "delivery-receipt") -eq $true -and $d.capabilities."delivery-receipt".evidence -like "*rollout*" -and $d.capabilities."delivery-receipt".evidence -like "*never submitted*") "and its arrival is confirmed from the rollout, with the control that unsubmitted text leaves no receipt"
Check ((Test-HordeAgentCapability -Descriptor $d -Name "resume") -eq $true -and (Test-HordeAgentCapability -Descriptor $d -Name "report-hook") -eq $true) "it resumes by id and reports through hooks: what a warg needs (engine-settings design 4.3)"
Check ($d.events."turn-ended".hook -ceq "Stop" -and $d.events."turn-ended".evidence -like "*only on a turn that completes*") "a turn's end is its Stop hook, and the descriptor carries that it does not fire on a failed or interrupted turn"
Check ([regex]::IsMatch("01a0cccc-1111-7222-8333-444455556666", $d.sessionIdPattern)) "CONTROL: the id of a rollout fixture in this folder matches its pattern"
Check (-not [regex]::IsMatch("rollout-01a0cccc-1111-7222-8333-444455556666", $d.sessionIdPattern)) "a rollout file name, with its prefix, does not"

Write-Host ""
Write-Host "--- every permission level is a flag this harness has (remote R9) ---" -ForegroundColor Cyan
$frag = @{}
$sandboxSet = @("windows-sandbox-configured")
foreach ($l in @(Get-HordePermissionLevels)) { $frag[$l.name] = Get-HordePermissionArgs -Descriptor $d -Level $l.name -EntryPoint "interactive" -Verified $sandboxSet }
Check (@($frag.Values | Where-Object { $_.state -cne "known" }).Count -eq 0) "every level of the vocabulary is expressible here, with the sandbox setting verified"
$e = Get-HordePermissionArgs -Descriptor $d -Level "edits" -EntryPoint "interactive"
Check ($e.state -eq "unknown" -and $e.reason -like "*windows-sandbox-configured*silently read-only*") "edits without the sandbox setting verified is refused: it would silently be read-only (review r60, F3)"
Check ((Get-HordePermissionArgs -Descriptor $d -Level "plan" -EntryPoint "interactive").state -eq "known") "CONTROL: plan needs no such setting"
Check (@(@(Get-HordePermissionLevels) | Where-Object { (Get-HordePermissionArgs -Descriptor $d -Level $_.name -EntryPoint "headless" -Verified $sandboxSet).state -ceq "known" }).Count -eq 0) "no fragment is offered for the headless start, which rejects --ask-for-approval (review r60, F4)"
Check ((@($frag["bypass"].value) -join " ") -ceq "--dangerously-bypass-approvals-and-sandbox") "bypass is this harness's own skip flag, spelt differently from other harnesses' (engines E0's lesson)"
Check ((@($frag["plan"].value) -join " ") -ceq "--sandbox read-only --ask-for-approval never") "plan is a read-only sandbox that never escalates"
Check ((@($frag["ask"].value) -join " ") -ceq "--sandbox read-only --ask-for-approval on-request") "ask is a read-only sandbox whose escalations a person approves"
Check ((@($frag["edits"].value) -join " ") -ceq "--sandbox workspace-write --ask-for-approval on-request -c sandbox_workspace_write.exclude_tmpdir_env_var=true -c sandbox_workspace_write.exclude_slash_tmp=true") "edits writes inside the working tree only - the TEMP folder and /tmp excluded (review r60, F2) - and asks for anything else"

Complete-HordeSuite -Success "this harness's descriptor loads and says what the plan relies on"
