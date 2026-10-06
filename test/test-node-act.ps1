# DOES A NODE START AND CLOSE A HUB'S SESSIONS EXACTLY AS ITS POLICY, ITS CEILING AND THE PROCESS ITSELF
# ALLOW, AND PROVE EACH BY PID AND START TIME?
#
# cli/NodeAct.ps1 (remote plan R19 and R9, the act path's A3; decisions of 2026-10-05). It is the half of
# an act that touches the machine: policy, resolution, launch plan, the host's pane, the harness's own
# record of its process and mode. Every machine-facing part is injected here - a fixture launch adapter
# (harness-a), a fixture host actor and a fixture process table - so nothing is started and every
# branch is reached. The real host is proven by hosts/wezterm/test/e2e/e2e-act.ps1, the real harness
# by agents/claude-code/test/test-launch.ps1.
#
# NEUTRAL NAMES ONLY (CONTRIBUTING 14).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "cli\NodeAct.ps1")

$aText = [System.IO.File]::ReadAllText((Join-Path $root "test\fixtures\agent-descriptor\agents\harness-a\agent.json"))
$aText = $aText.Replace('"session.remoteName": { "support": "unverified"', '"session.remoteName": { "support": "yes"')
$descriptors = @{ "harness-a" = (Read-HordeAgentDescriptorText -Text $aText -ExpectedName "harness-a") }
$fx = Join-Path $root "test\fixtures\engine-config"
$builtinDoc = [System.IO.File]::ReadAllText((Join-Path $fx "builtin.json")) | ConvertFrom-Json
$device = "0f8fad5b-d9cb-469f-a165-70867728950e"

# THE FIXTURE WORLD: processes by pid, sessions by id, what each pane received.
$script:procs = @{}
$script:sessions = @{}
$script:panes = New-Object System.Collections.ArrayList
$script:sent = New-Object System.Collections.ArrayList
$script:stopped = New-Object System.Collections.ArrayList
$script:nextPid = 5000
$script:reportMode = $null
$script:noIdentify = $false
$script:stubborn = $false
$script:reusedPid = $false
$modeOf = @{ careful = "ask"; edit = "edits"; look = "plan" }

Register-HordeLaunchAdapter -Name "harness-a" -Program "harness-a" `
    -Argv { param($s) $a = @("--id", $s.sessionId) + @($s.permissionArgs); if ("" + $s.name -ne "") { $a += @("--title", $s.name) }; if ("" + $s.prompt -ne "") { $a += @($s.prompt) }; New-HordeKnown -Value ([string[]]$a) } `
    -Preconditions { param($n) @() } `
    -Identify { param($id, $view) if ($script:sessions.ContainsKey($id) -and -not $script:noIdentify) { $x = $script:sessions[$id]; New-HordeKnown -Value ([pscustomobject]@{ pid = $x.pid; procStart = $x.procStart; name = $x.name; remoteControl = (New-HordeKnown -Value $true) }) } else { New-HordeAbsent -Note "no control file yet" } } `
    -ReadMode { param($id, $view) if ($script:sessions.ContainsKey($id) -and $null -ne $script:sessions[$id].mode) { New-HordeKnown -Value $script:sessions[$id].mode } else { New-HordeAbsent -Note "no mode line yet" } } `
    -CloseText @("bye", "`r")

Register-HordeHostActor -Name "fakehost" `
    -Resolve { param($n) if ($n -ceq "harness-a") { New-HordeKnown -Value "C:\bin\harness-a.exe" } else { New-HordeUnknown -Reason ("no " + $n) } } `
    -Start { param($prog, $argv, $cwd, $envMap)
        $h = "" + (100 + $script:panes.Count)
        [void]$script:panes.Add([pscustomobject]@{ handle = $h; program = $prog; argv = @($argv); cwd = $cwd; env = $envMap })
        $sidv = $argv[[array]::IndexOf(@($argv), "--id") + 1]
        $pidv = $script:nextPid; $script:nextPid++
        $ticks = "" + (134000000000000000 + $pidv)
        $script:procs[$pidv] = $ticks
        $i = [array]::IndexOf(@($argv), "--mode"); $mode = $null; if ($i -ge 0) { $mode = $modeOf[$argv[$i + 1]] }
        if ($null -ne $script:reportMode) { $mode = $script:reportMode }
        $claimed = $ticks; if ($script:reusedPid) { $claimed = "" + (133000000000000000 + $pidv) }
        $nm = ""; $j = [array]::IndexOf(@($argv), "--title"); if ($j -ge 0) { $nm = $argv[$j + 1] }
        $script:sessions[$sidv] = [pscustomobject]@{ pid = $pidv; procStart = $claimed; name = $nm; mode = $mode; handle = $h }
        New-HordeKnown -Value ([pscustomobject]@{ handle = $h; program = $prog; cwd = $cwd }) } `
    -Send { param($h, $t) [void]$script:sent.Add([pscustomobject]@{ handle = $h; text = $t })
        if ($t -eq "`r" -and -not $script:stubborn) { foreach ($s in @($script:sessions.Values)) { if ($s.handle -ceq $h) { $script:procs.Remove($s.pid) } } }
        New-HordeKnown -Value $true } `
    -Live { param($h) New-HordeKnown -Value $true } `
    -Stop { param($h) [void]$script:stopped.Add($h); foreach ($s in @($script:sessions.Values)) { if ($s.handle -ceq $h) { $script:procs.Remove($s.pid) } }; New-HordeKnown -Value $true }

$work = Join-Path $env:TEMP ("horde-node-act-" + [guid]::NewGuid().ToString("N"))
$clone = Join-Path $work "code\app"
New-Item -ItemType Directory -Path $clone, (Join-Path $work "code\app-worktrees\act-a3"), (Join-Path $work "records") -Force | Out-Null
$policyText = '{ "schemaVersion": 1, "repos": [ { "repoId": "github.com/example/app", "path": "' + $clone.Replace([string][char]92, ([string][char]92) * 2) + '" } ], "profiles": ["alpha", "beta"], "dailySpawnCap": 3 }'

function New-Context {
    param([object[]]$UserRules = @(), [string]$HostName = "", $Policy = $null)
    if ($null -eq $Policy) { $Policy = Read-HordeNodePolicyText -Text $policyText }
    $layers = @([pscustomobject]@{ layer = "L0"; source = "fixture L0"; doc = $builtinDoc })
    if ($UserRules.Count -gt 0) { $layers += [pscustomobject]@{ layer = "L1"; source = "fixture L1"; doc = [pscustomobject]@{ schemaVersion = 1; rules = @($UserRules) } } }
    return [pscustomobject]@{
        policy = $Policy; layers = $layers; descriptors = $descriptors
        namespace = [pscustomobject]@{ device = $device; space = "windows" }
        records = (Join-Path $work ("records-" + [guid]::NewGuid().ToString("N"))); environment = @{}; hostName = $HostName
        processStart = { param($p) if ($script:procs.ContainsKey([int]$p)) { $script:procs[[int]$p] } else { $null } }
        sleep = { param($ms) }; now = { [datetime]::Parse("2026-10-05T12:00:00Z").ToUniversalTime() }
        bounds = [pscustomobject]@{ identifySeconds = 2; modeSeconds = 2; closeSeconds = 2; pollMs = 100 }
        workdirExists = { param($p) Test-Path -LiteralPath $p -PathType Container }
    }
}
function Rule { param([string]$Id, [hashtable]$Set) return [pscustomobject]@{ id = $Id; match = [pscustomobject]@{}; set = [pscustomobject]$Set; writtenBy = "user" } }
function SpawnAct {
    param([hashtable]$Extra = @{})
    $a = [ordered]@{ label = "E"; role = "orc"; runId = "20261005-120000-act"; profile = "alpha"; repoId = "github.com/example/app"; prompt = [pscustomobject]@{ text = "read the plan" }; closeOn = "proof"; title = "client search orc"; permission = "edits" }
    foreach ($k in $Extra.Keys) { if ($null -eq $Extra[$k]) { $a.Remove($k) } else { $a[$k] = $Extra[$k] } }
    return [pscustomobject]@{ verb = "session.spawn"; args = ([pscustomobject]$a); requestId = [guid]::NewGuid().ToString() }
}
function Reset { $script:panes.Clear(); $script:sent.Clear(); $script:stopped.Clear(); $script:reportMode = $null; $script:noIdentify = $false; $script:stubborn = $false; $script:reusedPid = $false }

try {
Write-Host ""
Write-Host "--- a spawn: policy, plan, pane, process, mode - then done, with the process to close it by ---" -ForegroundColor Cyan
Reset
$ctx0 = New-Context
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $ctx0
Check ("$($o.state)" -ceq "done") ("a spawn the policy allows is done" + $(if ("$($o.state)" -cne "done") { " (" + $o.reason + ")" } else { "" }))
$p = $script:panes[0]
Check ($script:panes.Count -eq 1 -and $p.program -ceq "C:\bin\harness-a.exe" -and $p.cwd -ceq $clone) "one pane, running the program the host resolved, in the registered clone (no worktree given)"
Check ((@($p.argv) -join "|") -ceq ("--id|" + $o.sessionId + "|--mode|edit|--title|E client search orc|read the plan")) "its argv is the launch plan's: the id the node chose, the level's flags, the name, the prompt"
Check ($null -ne $p.env -and $p.env.ContainsKey("PROVIDER_A_TOKEN") -and $null -eq $p.env["PROVIDER_A_TOKEN"] -and $p.env.ContainsKey("PROVIDER_A_BASE_URL") -and $null -eq $p.env["PROVIDER_A_BASE_URL"]) "every variable the harness owns is removed from the spawn, so the node's own engine settings never reach the session"
Check ($o.expect.pid -eq $script:sessions[$o.sessionId].pid -and "$($o.expect.procStart)" -ceq $script:procs[$script:sessions[$o.sessionId].pid] -and "$($o.expect.ns.device)" -ceq $device -and "$($o.expect.ns.space)" -ceq "windows") "the outcome carries the process, proved against the process table, placed by device and space"
$rec = Read-HordeNodeSpawnRecord -Dir $ctx0.records -SessionId $o.sessionId
Check ($rec.state -eq "known" -and "$($rec.value.handle)" -ceq $p.handle -and "$($rec.value.host)" -ceq "fakehost" -and "$($rec.value.level)" -ceq "edits" -and "$($rec.value.name)" -ceq "E client search orc") "the node keeps its own record: the pane, the host, the level and the name"

Reset
$o = Invoke-HordeNodeActRequest -Act (SpawnAct @{ worktree = [pscustomobject]@{ name = "act-a3"; branch = "feature/act-a3-verbs"; base = "origin/main" } }) -Context (New-Context)
Check ("$($o.state)" -ceq "done" -and $script:panes[0].cwd -ceq (Join-Path $work "code\app-worktrees\act-a3")) "a named worktree runs in <clone>-worktrees\<name>"
Reset
$o = Invoke-HordeNodeActRequest -Act (SpawnAct @{ worktree = [pscustomobject]@{ name = "not-made"; branch = "b"; base = "origin/main" } }) -Context (New-Context)
Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*does not exist*" -and $script:panes.Count -eq 0) "a worktree that does not exist is refused, and no pane starts: this version creates none"

Write-Host ""
Write-Host "--- refused before anything starts ---" -ForegroundColor Cyan
Reset
$o = Invoke-HordeNodeActRequest -Act (SpawnAct @{ permission = "edits" }) -Context (New-Context -UserRules @(Rule "ceiling" @{ "remote.permissionCeiling" = "ask" }))
Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*edits is above this node's ceiling, ask*" -and $script:panes.Count -eq 0) "a level above the node's ceiling is refused, never lowered, and nothing starts"
Reset
$o = Invoke-HordeNodeActRequest -Act (SpawnAct @{ permission = $null }) -Context (New-Context)
Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*no permission level is resolved*" -and $script:panes.Count -eq 0) "a spawn with no level, from the request or the node's own rules, is refused"
Reset
$o = Invoke-HordeNodeActRequest -Act (SpawnAct @{ permission = $null }) -Context (New-Context -UserRules @(Rule "orcs" @{ permission = "ask" }))
Check ("$($o.state)" -ceq "done" -and (@($script:panes[0].argv) -join " ") -like "*--mode careful*") "CONTROL: the node's own rule may choose the level when the request does not"
Reset
$o = Invoke-HordeNodeActRequest -Act (SpawnAct @{ profile = "gamma" }) -Context (New-Context)
Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*does not offer the profile 'gamma'*" -and $script:panes.Count -eq 0) "a profile the node does not offer is refused"
Reset
$o = Invoke-HordeNodeActRequest -Act (SpawnAct @{ permission = "bypass" }) -Context (New-Context -UserRules @(Rule "ceiling" @{ "remote.permissionCeiling" = "bypass" }))
Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*cannot express*bypass*" -and $script:panes.Count -eq 0) "a level the harness cannot express is refused, even under a ceiling that allows it"
Reset
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context (New-Context -HostName "otherhost")
Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*otherhost*" -and $script:panes.Count -eq 0) "a host with no acting adapter here is refused"
Reset
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context (New-Context -Policy (New-HordeAbsent -Note "this node has no policy file"))
Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*no policy file*") "a node with no policy starts nothing"

Write-Host ""
Write-Host "--- a session that is not what was asked is closed, never kept (decision 6: fail closed) ---" -ForegroundColor Cyan
Reset; $script:reportMode = "bypass"
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context (New-Context)
$x = $script:sessions[$o.sessionId]
Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*reports the level bypass*asked for edits*" -and -not $script:procs.ContainsKey($x.pid)) "a session that reports a level above the one asked for is closed and the spawn refused"
Check (@($script:sent | Where-Object { $_.text -ceq "bye" }).Count -eq 1) "it was closed gracefully first, with the harness's own close text"
Reset; $script:reportMode = "plan"
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context (New-Context)
Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*reports the level plan*asked for edits*") "a session in another level than asked, even a lower one, is closed: the hub gets what it asked or nothing"
Reset
$o = Invoke-HordeNodeActRequest -Act (SpawnAct @{ permission = "edits" }) -Context (New-Context)
Check ("$($o.state)" -ceq "done") "CONTROL: a session reporting exactly the level asked for is kept"
Reset
$ctx = New-Context
# A harness that never reports its mode: the session is closed when the bound passes.
Register-HordeLaunchAdapter -Name "harness-a" -Program "harness-a" `
    -Argv { param($s) $a = @("--id", $s.sessionId) + @($s.permissionArgs); New-HordeKnown -Value ([string[]]$a) } `
    -Preconditions { param($n) @() } `
    -Identify { param($id, $view) if ($script:sessions.ContainsKey($id) -and -not $script:noIdentify) { $x = $script:sessions[$id]; New-HordeKnown -Value ([pscustomobject]@{ pid = $x.pid; procStart = $x.procStart; name = ""; remoteControl = (New-HordeKnown -Value $true) }) } else { New-HordeAbsent -Note "none" } } `
    -ReadMode { param($id, $view) New-HordeAbsent -Note "no mode line yet" } -CloseText @("bye", "`r")
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context (New-Context)
$x = $script:sessions[$o.sessionId]
Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*could not be read back*" -and -not $script:procs.ContainsKey($x.pid)) "a session whose mode cannot be read back within the bound is closed and the spawn refused"
Reset; $script:stubborn = $true
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context (New-Context)
$x = $script:sessions[$o.sessionId]
Check ("$($o.state)" -ceq "refused" -and @($script:stopped).Count -eq 1 -and -not $script:procs.ContainsKey($x.pid)) "one that ignores the close text is ended by the host, so a refused session never keeps running"
Reset; $script:noIdentify = $true
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context (New-Context)
Check ("$($o.state)" -ceq "failed" -and $o.reason -like "*never reported its process*" -and @($script:stopped).Count -eq 1) "a harness that never reports its process fails the spawn, and its pane is ended"
Reset; $script:reusedPid = $true
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context (New-Context)
Check ("$($o.state)" -ceq "failed" -and @($script:stopped).Count -eq 1) "a reported process whose start time is not the live one's is not believed: the spawn fails and the pane is ended"
# Back to the reporting adapter for what follows.
Register-HordeLaunchAdapter -Name "harness-a" -Program "harness-a" `
    -Argv { param($s) $a = @("--id", $s.sessionId) + @($s.permissionArgs); if ("" + $s.name -ne "") { $a += @("--title", $s.name) }; New-HordeKnown -Value ([string[]]$a) } `
    -Preconditions { param($n) @() } `
    -Identify { param($id, $view) if ($script:sessions.ContainsKey($id) -and -not $script:noIdentify) { $x = $script:sessions[$id]; New-HordeKnown -Value ([pscustomobject]@{ pid = $x.pid; procStart = $x.procStart; name = $x.name; remoteControl = (New-HordeKnown -Value $true) }) } else { New-HordeAbsent -Note "none" } } `
    -ReadMode { param($id, $view) if ($script:sessions.ContainsKey($id) -and $null -ne $script:sessions[$id].mode) { New-HordeKnown -Value $script:sessions[$id].mode } else { New-HordeAbsent -Note "none" } } `
    -CloseText @("bye", "`r")

Write-Host ""
Write-Host "--- the daily cap counts what this node started today ---" -ForegroundColor Cyan
$capDir = Join-Path $work "records-cap"
New-Item -ItemType Directory -Path $capDir | Out-Null
$ctx = New-Context; $ctx.records = $capDir
$done = 0
foreach ($i in 1..3) { Reset; if ("$((Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $ctx).state)" -ceq "done") { $done++ } }
Reset
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $ctx
Check ($done -eq 3 -and "$($o.state)" -ceq "refused" -and $o.reason -like "*daily spawn cap of 3 is reached*") "three spawns under a cap of 3 start; the fourth is refused"

Write-Host ""
Write-Host "--- a close: only a session this node started, only the process the hub names, gracefully ---" -ForegroundColor Cyan
Reset
$ctx = New-Context
$s = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $ctx
$closeArgs = [pscustomobject]@{ sessionId = $s.sessionId; expect = $s.expect; reason = "the work is done" }
$c = Invoke-HordeNodeActRequest -Act ([pscustomobject]@{ verb = "session.close"; args = $closeArgs; requestId = [guid]::NewGuid().ToString() }) -Context $ctx
$x = $script:sessions[$s.sessionId]
Check ("$($c.state)" -ceq "done" -and -not $script:procs.ContainsKey($x.pid) -and "$($c.sessionId)" -ceq $s.sessionId) "a close ends the session: done, and no process has its pid and start time"
Check ((@($script:sent | Where-Object { $_.handle -ceq $x.handle } | ForEach-Object { $_.text }) -join "|") -ceq ("bye|" + "`r") -and @($script:stopped).Count -eq 0) "it typed the harness's close text into that pane, and forced nothing"
$rec = Read-HordeNodeSpawnRecord -Dir $ctx.records -SessionId $s.sessionId
Check ($rec.state -eq "known" -and "$($rec.value.closedAt)" -ne "") "the node's record says when it was closed"
$c = Invoke-HordeNodeActRequest -Act ([pscustomobject]@{ verb = "session.close"; args = $closeArgs; requestId = [guid]::NewGuid().ToString() }) -Context $ctx
Check ("$($c.state)" -ceq "done" -and $c.reason -like "*already ended*") "closing a session that has already ended is done, saying so"
function CloseWith { param($CloseArgs) return (Invoke-HordeNodeActRequest -Act ([pscustomobject]@{ verb = "session.close"; args = $CloseArgs; requestId = [guid]::NewGuid().ToString() }) -Context $ctx) }
Reset
$s = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $ctx
$x = $script:sessions[$s.sessionId]
$wrong = [pscustomobject]@{ ns = $s.expect.ns; pid = $s.expect.pid; procStart = "" + ([long]$s.expect.procStart + 1) }
$c = CloseWith ([pscustomobject]@{ sessionId = $s.sessionId; expect = $wrong; reason = "x" })
Check ("$($c.state)" -ceq "refused" -and $c.reason -like "*differs*" -and $script:procs.ContainsKey($x.pid) -and $script:sent.Count -eq 0) "a close naming another start time than the node's view is refused, and nothing is typed"
$far = [pscustomobject]@{ ns = [pscustomobject]@{ device = "11111111-2222-4333-8444-555555555555"; space = "windows" }; pid = $s.expect.pid; procStart = $s.expect.procStart }
$c = CloseWith ([pscustomobject]@{ sessionId = $s.sessionId; expect = $far; reason = "x" })
Check ("$($c.state)" -ceq "refused" -and $c.reason -like "*device*" -and $script:procs.ContainsKey($x.pid)) "a close naming a process of another device is refused: a pid is looked up only on its own device"
$c = CloseWith ([pscustomobject]@{ sessionId = "99999999-1111-4222-8333-444444444444"; expect = $s.expect; reason = "x" })
Check ("$($c.state)" -ceq "refused" -and $c.reason -like "*did not start*") "a session this node did not start for a hub is refused"
$script:stubborn = $true
$c = CloseWith ([pscustomobject]@{ sessionId = $s.sessionId; expect = $s.expect; reason = "x" })
Check ("$($c.state)" -ceq "failed" -and $c.reason -like "*still running*" -and $script:procs.ContainsKey($x.pid) -and @($script:stopped).Count -eq 0) "a session that ignores the close is answered failed and left running: a close is graceful, nothing is forced"
} finally {
    if ((Split-Path -Leaf $work) -match '^horde-node-act-[0-9a-f]{32}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

Complete-HordeSuite -Success "a node starts and closes a hub's sessions exactly as its policy, its ceiling and the process allow, each proved by pid and start time"
