# IS THIS HARNESS STARTED WITH THE ARGV ITS FLAGS PROMISE, AND IS WHAT IT REPORTS READ BACK EXACTLY?
#
# agents/claude-code/Launch.ps1 (the act path's A1; issue #67; decision 6 of 2026-10-05). Fixtures
# only: test/fixtures/launch/config is a harness folder whose transcript lines are copied from a real
# 2.1.289 interactive transcript, redacted (its README says which). Nothing is started, and nothing
# under the user's own harness folder is read or written.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\EngineResolve.ps1")
. (Join-Path $root "core\AgentLaunch.ps1")
. (Join-Path $root "core\ReadShared.ps1")
. (Join-Path $root "agents\claude-code\Launch.ps1")

$d = Read-HordeAgentDescriptor -Path (Join-Path $root "agents\claude-code\agent.json")
$cfg = Join-Path $here "fixtures\launch\config"
$view = @{ CLAUDE_CONFIG_DIR = $cfg; USERPROFILE = "C:\nobody" }
$sid = "aaaaaaaa-1111-4222-8333-444444444444"
$name = Format-HordeSessionName -Label "E" -Title "client search orc"

Write-Host ""
Write-Host "--- the argv ---" -ForegroundColor Cyan
$res = Resolve-HordeEngine -Layers @(Get-HordeBuiltinLayer -Root $root) -Target @{ role = "orc" } -Descriptors @{ "claude-code" = $d }
$exeOf = { param($n) New-HordeKnown -Value ("C:\tools\" + $n + ".exe") }
function Allow { param([string]$Level) return [pscustomobject]@{ allowed = $true; level = $Level; reasons = @() } }
$p = New-HordeLaunchPlan -Resolution $res -Decision (Allow "bypass") -SessionId $sid -Name $name -Prompt "read the plan" -Resolve $exeOf
Check ($p.state -eq "known") ("CONTROL: the built-in engine gives a plan for an orc" + $(if ($p.state -ne "known") { " (" + $p.reason + ")" } else { "" }))
$want = @("--session-id", $sid, "--dangerously-skip-permissions", "-n", "E client search orc", "--remote-control", "E client search orc", "read the plan")
Check ((@($p.value.argv) -join "|") -ceq ($want -join "|")) ("the argv: the id, the level's fragment from agent.json, the name twice, the prompt last (" + (@($p.value.argv) -join " ") + ")")
Check ($p.value.program -ceq "C:\tools\claude.exe") "the program is the absolute .exe the host resolved for the harness's command name"
$i = [array]::IndexOf(@($p.value.argv), "--remote-control")
Check ($i -ge 0 -and @($p.value.argv)[$i + 1] -ceq "E client search orc") "--remote-control is followed at once by the name, so it never takes the prompt as one (engines E9)"
foreach ($lv in @("plan", "ask", "edits")) {
    $pl = New-HordeLaunchPlan -Resolution $res -Decision (Allow $lv) -SessionId $sid -Name $name -Resolve $exeOf
    $frag = (Get-HordePermissionArgs -Descriptor $d -Level $lv -EntryPoint "interactive").value
    Check ($pl.state -eq "known" -and (@($pl.value.argv) -join " ") -like ("*" + (@($frag) -join " ") + "*")) ("the " + $lv + " level carries its agent.json fragment (" + (@($frag) -join " ") + ")")
}
$a = New-ClaudeCodeArgv -Spec ([pscustomobject]@{ sessionId = $sid; permissionArgs = @("--permission-mode", "plan"); model = "model-x1"; name = ""; prompt = "" })
Check ($a.state -eq "known" -and (@($a.value) -join " ") -ceq ("--session-id " + $sid + " --permission-mode plan --model model-x1")) "a pinned model is passed with --model; no name gives neither -n nor --remote-control; no prompt gives no prompt"
$gd = "C:\h\node\spawned\" + $sid
$a = New-ClaudeCodeArgv -Spec ([pscustomobject]@{ sessionId = $sid; permissionArgs = @("--permission-mode", "plan"); model = $null; name = "E"; prompt = ""; addDirs = @($gd) })
Check ($a.state -eq "known" -and (@($a.value) -join "|") -ceq ("--session-id|" + $sid + "|--add-dir|" + $gd + "|--permission-mode|plan|-n|E|--remote-control|E")) "a granted folder is passed with --add-dir right after the session id, where the next item is a flag"
$a = New-ClaudeCodeArgv -Spec ([pscustomobject]@{ sessionId = $sid; permissionArgs = @(); model = $null; name = ""; prompt = ""; addDirs = @("-x") })
Check ($a.state -eq "unknown" -and $a.reason -like "*starts with '-'*") "a granted folder starting with '-' is refused"
$a = New-ClaudeCodeArgv -Spec ([pscustomobject]@{ sessionId = $sid; permissionArgs = @(); model = "-p"; name = "E"; prompt = "" })
Check ($a.state -eq "unknown" -and $a.reason -like "*model*starts with '-'*") "a model starting with '-' is refused (review of PR #98, F5)"
$a = New-ClaudeCodeArgv -Spec ([pscustomobject]@{ sessionId = $sid; permissionArgs = @(); model = $null; name = "-p"; prompt = "" })
Check ($a.state -eq "unknown" -and $a.reason -like "*session name*starts with '-'*") "a name starting with '-' is refused here too, the second line behind Format-HordeSessionName's label"
$a = New-ClaudeCodeArgv -Spec ([pscustomobject]@{ sessionId = $sid; permissionArgs = @(); model = $null; name = "E"; prompt = "-p rm" })
Check ($a.state -eq "unknown" -and $a.reason -like "*starts with '-'*") "a prompt starting with '-' is refused: the harness would read it as a flag"
$a = New-ClaudeCodeArgv -Spec ([pscustomobject]@{ sessionId = $sid; permissionArgs = @(); model = $null; name = "E"; prompt = ("x" * 16001) })
Check ($a.state -eq "unknown" -and $a.reason -like "*16001*16000*") "a prompt longer than a command line carries is refused, never cut"
$a = New-ClaudeCodeArgv -Spec ([pscustomobject]@{ sessionId = $sid; permissionArgs = @(); model = $null; name = "E"; prompt = ("x" * 16000) })
Check ($a.state -eq "known") "CONTROL: one at the limit is passed"
$a = New-ClaudeCodeArgv -Spec ([pscustomobject]@{ sessionId = $sid; permissionArgs = @(); model = $null; name = "E"; prompt = ("a" + [char]27 + "[2J") })
Check ($a.state -eq "unknown") "a prompt holding a terminal escape is refused"
$a = New-ClaudeCodeArgv -Spec ([pscustomobject]@{ sessionId = $sid; permissionArgs = @(); model = $null; name = "E"; prompt = "line one`nline two`tend" })
Check ($a.state -eq "known") "CONTROL: line breaks and tabs are text, and pass"

Write-Host ""
Write-Host "--- the readback: the transcript's permission-mode line, mapped to a level (issue #67, item 2) ---" -ForegroundColor Cyan
$m = Read-ClaudeCodeMode -ConfigDir $cfg -SessionId $sid
Check ($m.state -eq "known" -and $m.value -ceq "bypass") "bypassPermissions reads back as bypass"
$m = Read-ClaudeCodeMode -ConfigDir $cfg -SessionId "cccccccc-1111-4222-8333-444444444444"
Check ($m.state -eq "known" -and $m.value -ceq "plan") "the LAST permission-mode line is the mode now (acceptEdits, then plan, reads plan)"
$m = Read-ClaudeCodeMode -ConfigDir $cfg -SessionId "dddddddd-1111-4222-8333-444444444444"
Check ($m.state -eq "unknown" -and $m.reason -like "*'auto'*") "a mode Horde does not map is unknown, never a guessed level"
$m = Read-ClaudeCodeMode -ConfigDir $cfg -SessionId "eeeeeeee-1111-4222-8333-444444444444"
Check ($m.state -eq "absent") "a transcript with no permission-mode line yet is absent, never a level"
$m = Read-ClaudeCodeMode -ConfigDir $cfg -SessionId "ffffffff-1111-4222-8333-444444444444"
Check ($m.state -eq "absent") "no transcript yet is absent"
# The bbbbbbbb line in the aaaaaaaa transcript says bypassPermissions too: a line of another session
# never counts. Its own mode is read only from lines naming it.
$m = Read-ClaudeCodeModeText -Text ('{"type":"permission-mode","permissionMode":"bypassPermissions","sessionId":"bbbbbbbb-1111-4222-8333-444444444444"}' + "`n") -SessionId $sid
Check ($m.state -eq "absent") "a permission-mode line naming another session is not this session's"
$m = Read-ClaudeCodeModeText -Text ('{"type":"user","permissionMode":"plan","sessionId":"' + $sid + '"}' + "`n") -SessionId $sid
Check ($m.state -eq "absent") "only a permission-mode line counts, not a field of the same name on another line"
foreach ($pair in @(@("plan", "plan"), @("default", "ask"), @("acceptEdits", "edits"), @("bypassPermissions", "bypass"))) {
    $m = Read-ClaudeCodeModeText -Text ('{"type":"permission-mode","permissionMode":"' + $pair[0] + '","sessionId":"' + $sid + '"}') -SessionId $sid
    Check ($m.state -eq "known" -and $m.value -ceq $pair[1]) ($pair[0] + " reads back as " + $pair[1])
}
$m = Read-ClaudeCodeModeText -Text ('{"type":"permission-mode","permissionMode":"BypassPermissions","sessionId":"' + $sid + '"}') -SessionId $sid
Check ($m.state -eq "unknown") "a mode is matched exactly: BypassPermissions is not bypassPermissions"
# The adapter's map and the descriptor agree: every level's readback evidence names the mode this
# file maps to it, so a descriptor and this file cannot drift apart unseen.
foreach ($row in @($d.permissionLevels)) {
    $modes = @($script:ClaudeCodeModeLevels.Keys | Where-Object { $script:ClaudeCodeModeLevels[$_] -ceq $row.level })
    Check ($modes.Count -eq 1 -and ("" + $row.readback) -clike ("*permissionMode " + $modes[0] + "*")) ("the " + $row.level + " level's readback evidence names the mode mapped to it (" + ($modes -join ",") + ")")
}

Write-Host ""
Write-Host "--- identifying the started process from its control file ---" -ForegroundColor Cyan
$s = Find-ClaudeCodeSession -ConfigDir $cfg -SessionId $sid
Check ($s.state -eq "known" -and $s.value.pid -eq 4242 -and $s.value.procStart -ceq "134350994347710308" -and $s.value.name -ceq "E probe bypass") "the control file naming the session gives its pid, start time and name"
Check ($s.value.remoteControl.state -eq "known" -and $s.value.remoteControl.value -eq $true) "a control file with a bridge session says Remote Control is up"
$s = Find-ClaudeCodeSession -ConfigDir $cfg -SessionId "cccccccc-1111-4222-8333-444444444444"
Check ($s.state -eq "known" -and $s.value.remoteControl.state -eq "unknown") "one without says it cannot tell yet, never that it is off"
$s = Find-ClaudeCodeSession -ConfigDir $cfg -SessionId "eeeeeeee-1111-4222-8333-444444444444"
Check ($s.state -eq "unknown" -and $s.reason -like "*names the pid 4545*") "a control file whose pid is not its own name is not believed"
$s = Find-ClaudeCodeSession -ConfigDir $cfg -SessionId "ffffffff-1111-4222-8333-444444444444"
Check ($s.state -eq "absent") "no control file yet is absent"

Write-Host ""
Write-Host "--- through the port, with the environment the harness sees ---" -ForegroundColor Cyan
$ad = (Get-HordeLaunchAdapter -Name "claude-code").value
$m = & $ad.readMode $sid $view
Check ($m.state -eq "known" -and $m.value -ceq "bypass") "the registered ReadMode finds the folder from CLAUDE_CONFIG_DIR in the environment it is given"
$m = & $ad.readMode $sid @{ USERPROFILE = (Join-Path $here "fixtures\launch\no-such-profile") }
Check ($m.state -eq "absent") "CONTROL: without CLAUDE_CONFIG_DIR it looks under the profile's .claude, and finds nothing there"
Check ((Get-ClaudeCodeConfigDir -Environment @{ USERPROFILE = "C:\u" }) -ceq "C:\u\.claude") "the default folder is .claude in the profile the harness sees"
$i = & $ad.identify $sid $view
Check ($i.state -eq "known" -and $i.value.pid -eq 4242) "the registered Identify finds the control file the same way"
Check (@(& $ad.preconditions @("folder-trusted")).Count -eq 0) "a precondition this file cannot check is never reported as verified"
Check ((@($ad.closeText) -join "|") -ceq ("/exit|" + "`r")) "a session is ended by typing /exit and then Enter"

Complete-HordeSuite -Success "the argv is the flags agent.json promises, and the mode, process and Remote Control state are read back exactly"
