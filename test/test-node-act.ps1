# DOES A NODE START AND CLOSE A HUB'S SESSIONS EXACTLY AS ITS POLICY, ITS CEILING AND THE PROCESS ITSELF
# ALLOW, AND PROVE EACH BY PID AND START TIME?
#
# cli/NodeAct.ps1 (remote plan R19 and R9, the act path's A3; decisions of 2026-10-05). It is the half of
# an act that touches the machine: policy, resolution, launch plan, the host's pane, the harness's own
# record of its process and mode. Every machine-facing part is injected here - a fixture launch adapter
# (harness-a), a fixture host actor and a fixture process table - so nothing is started and every
# branch is reached. The real host and the real harness are proven by their own folders' suites.
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
$script:noOwn = $false
$script:offByMicros = $false
$script:stopRefused = 0
$script:stopDenied = $false
$script:promptRefused = $false
$script:noOpRefused = $false
$script:alerts = New-Object System.Collections.ArrayList
# How many texts had been typed when a session's mode was first read, by session id.
$script:readAt = @{}
$noOp = "Reply with OK only."
$hub = "7c9e6679-7425-40de-944b-e07fc1f90ae7"
$modeOf = @{ careful = "ask"; edit = "edits"; look = "plan" }

Register-HordeLaunchAdapter -Name "harness-a" -Program "harness-a" `
    -Argv { param($s) $a = @("--id", $s.sessionId) + @($s.permissionArgs); if ("" + $s.name -ne "") { $a += @("--title", $s.name) }; if ("" + $s.prompt -ne "") { $a += @($s.prompt) }; New-HordeKnown -Value ([string[]]$a) } `
    -Preconditions { param($n) @() } `
    -Identify { param($id, $view) if ($script:sessions.ContainsKey($id) -and -not $script:noIdentify) { $x = $script:sessions[$id]; New-HordeKnown -Value ([pscustomobject]@{ pid = $x.pid; procStart = $x.procStart; name = $x.name; remoteControl = (New-HordeKnown -Value $true) }) } else { New-HordeAbsent -Note "no control file yet" } } `
    -ReadMode { param($id, $view) if (-not $script:readAt.ContainsKey($id)) { $script:readAt[$id] = $script:sent.Count }; if ($script:sessions.ContainsKey($id) -and $null -ne $script:sessions[$id].mode) { New-HordeKnown -Value $script:sessions[$id].mode } else { New-HordeAbsent -Note "no mode line yet" } } `
    -CloseText @("bye", "`r")

# The fixture terminal: named explicitly by Own, as the real host names the node's own (review of #96).
$fakeTerm = [pscustomobject]@{ socket = "C:\fake\terminal-1"; guiPid = 1; guiStart = "1" }
Register-HordeHostActor -Name "fakehost" `
    -Own { if ($script:noOwn) { New-HordeUnknown -Reason "2 terminals are running; which one is this node's own cannot be told" } else { New-HordeKnown -Value $fakeTerm } } `
    -Resolve { param($n) if ($n -ceq "harness-a") { New-HordeKnown -Value "C:\bin\harness-a.exe" } else { New-HordeUnknown -Reason ("no " + $n) } } `
    -Start { param($term, $prog, $argv, $cwd, $envMap)
        $h = "" + (100 + $script:panes.Count)
        [void]$script:panes.Add([pscustomobject]@{ handle = $h; program = $prog; argv = @($argv); cwd = $cwd; env = $envMap; term = $term })
        $sidv = $argv[[array]::IndexOf(@($argv), "--id") + 1]
        $pidv = $script:nextPid; $script:nextPid++
        $ticks = "" + (134000000000000000 + $pidv)
        $script:procs[$pidv] = $ticks
        $i = [array]::IndexOf(@($argv), "--mode"); $mode = $null; if ($i -ge 0) { $mode = $modeOf[$argv[$i + 1]] }
        if ($null -ne $script:reportMode) { $mode = $script:reportMode }
        $claimed = $ticks; if ($script:reusedPid) { $claimed = "" + (133000000000000000 + $pidv) }
        if ($script:offByMicros) { $claimed = "" + ([long]$ticks + 1000) }
        $nm = ""; $j = [array]::IndexOf(@($argv), "--title"); if ($j -ge 0) { $nm = $argv[$j + 1] }
        $script:sessions[$sidv] = [pscustomobject]@{ pid = $pidv; procStart = $claimed; name = $nm; mode = $mode; handle = $h }
        New-HordeKnown -Value ([pscustomobject]@{ handle = $h; program = $prog; cwd = $cwd }) } `
    -Send { param($term, $h, $t, $submit)
        if ("" + $t -cmatch '[\x00-\x1F]') { return (New-HordeUnknown -Reason "the fixture host, like the real one, types printable text only") }
        if ($script:noOpRefused -and "" + $t -ceq "Reply with OK only.") { return (New-HordeUnknown -Reason "the fixture host refuses this text") }
        if ($script:promptRefused -and "" + $t -ne "" -and "" + $t -cne "bye" -and "" + $t -cne "Reply with OK only.") { return (New-HordeUnknown -Reason "the fixture host refuses this text") }
        if ("" + $t -ne "") { [void]$script:sent.Add([pscustomobject]@{ handle = $h; text = $t }) }
        if ($submit) { [void]$script:sent.Add([pscustomobject]@{ handle = $h; text = "<enter>" }) }
        if ($submit -and "" + $t -eq "" -and -not $script:stubborn) { foreach ($s in @($script:sessions.Values)) { if ($s.handle -ceq $h) { $script:procs.Remove($s.pid) } } }
        New-HordeKnown -Value $true } `
    -Live { param($term, $h, $expect) New-HordeKnown -Value $true } `
    -Stop { param($term, $h, $expect)
        # Like the real host: ends a pane only for the expected process, alive with its start time.
        if ($script:stopDenied -or $null -eq $expect -or -not $script:procs.ContainsKey([int]$expect.pid) -or "" + $script:procs[[int]$expect.pid] -cne "" + $expect.procStart) { $script:stopRefused++; return (New-HordeUnknown -Reason "nothing was ended: the expected process is not proven") }
        [void]$script:stopped.Add($h); foreach ($s in @($script:sessions.Values)) { if ($s.handle -ceq $h) { $script:procs.Remove($s.pid) } }; New-HordeKnown -Value $true }

$work = Join-Path $env:TEMP ("horde-nodeact-" + [guid]::NewGuid().ToString("N"))
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
        home = $work; records = (Join-Path $work ("records-" + [guid]::NewGuid().ToString("N"))); environment = @{}; hostName = $HostName
        # The configuration as this context holds it; the real reader is proven against real files below.
        readConfig = { param($c) [pscustomobject]@{ policy = $c.policy; layers = $c.layers; problems = @(@($c.PSObject.Properties["layerProblems"] | ForEach-Object { $_.Value }) | ForEach-Object { $_ }) } }
        alert = { param($m) [void]$script:alerts.Add($m) }
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
    return [pscustomobject]@{ verb = "session.spawn"; args = ([pscustomobject]$a); requestId = [guid]::NewGuid().ToString(); hubId = $hub }
}
# A close as the hub sends it; the context is the script's current $ctx.
function CloseWith { param($CloseArgs, [string]$From = $hub) return (Invoke-HordeNodeActRequest -Act ([pscustomobject]@{ verb = "session.close"; args = $CloseArgs; requestId = [guid]::NewGuid().ToString(); hubId = $From }) -Context $ctx) }
function Reset { $script:panes.Clear(); $script:sent.Clear(); $script:stopped.Clear(); $script:reportMode = $null; $script:noIdentify = $false; $script:stubborn = $false; $script:reusedPid = $false; $script:noOwn = $false; $script:offByMicros = $false; $script:stopRefused = 0; $script:stopDenied = $false; $script:promptRefused = $false; $script:noOpRefused = $false; $script:alerts.Clear(); $script:readAt.Clear() }

try {
Write-Host ""
Write-Host "--- a spawn: policy, plan, pane, process, mode - then done, with the process to close it by ---" -ForegroundColor Cyan
Reset
$ctx0 = New-Context
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $ctx0
Check ("$($o.state)" -ceq "done") ("a spawn the policy allows is done" + $(if ("$($o.state)" -cne "done") { " (" + $o.reason + ")" } else { "" }))
$p = $script:panes[0]
Check ($script:panes.Count -eq 1 -and $p.program -ceq "C:\bin\harness-a.exe" -and $p.cwd -ceq $clone -and $p.term -eq $fakeTerm) "one pane, in the terminal the host named, running the absolute .exe it resolved, in the registered clone (no worktree given)"
Check ((@($p.argv) -join "|") -ceq ("--id|" + $o.sessionId + "|--mode|edit|--title|E client search orc")) "its argv is the launch plan's: the id the node chose, the level's flags, the name - and NO prompt (review of #104, F4)"
Check ((@($script:sent | Where-Object { $_.handle -ceq $p.handle } | ForEach-Object { $_.text }) -join "|") -ceq ($noOp + "|<enter>|read the plan|<enter>")) "the prompt is typed into the pane as one line and submitted, once the mode was proven"
$k = $script:readAt[$o.sessionId]
Check ($k -eq 2 -and (@($script:sent[0..($k - 1)] | ForEach-Object { $_.text }) -join "|") -ceq ($noOp + "|<enter>")) "before the mode is read, the only text typed is the fixed line that asks for nothing, and the prompt comes after"
$rec0 = Read-HordeNodeSpawnRecord -Dir $ctx0.records -SessionId $o.sessionId
Check ("$($rec0.value.noOp)" -ceq $noOp -and "$($rec0.value.noOpAt)" -ne "") "the record says the line was typed, and when"
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
Check ((@($script:sent | ForEach-Object { $_.text }) -join "|") -ceq ($noOp + "|<enter>|bye|<enter>")) "it was closed gracefully first: the harness's close text typed, then Enter by -Submit - and the only text before was the line that asks for nothing"
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
Check ("$($o.state)" -ceq "failed" -and $o.reason -like "*never reported its process*left for a person*" -and @($script:stopped).Count -eq 0) "a harness that never reports its process fails the spawn; its pane is NOT ended, since a pane is ended only for a proven process, and the reason names it"
Check ((@($script:sent | ForEach-Object { $_.text }) -join "|") -ceq "bye|<enter>") "but its close text is typed, so a harness that started late still ends itself"
Reset; $script:reusedPid = $true
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context (New-Context)
Check ("$($o.state)" -ceq "failed" -and @($script:stopped).Count -eq 0) "a reported process whose start time is not the live one's is not believed: the spawn fails, and nothing unproven is ended"
Reset; $script:offByMicros = $true
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context (New-Context)
Check ("$($o.state)" -ceq "failed" -and $o.reason -like "*never reported its process*") "a reported start 100 microseconds off the live one is another process: start times are compared to the microsecond, not the millisecond"
Check ((Test-HordeNodeSameStart "133000000000000207" "133000000000000200") -eq $true -and (Test-HordeNodeSameStart "133000000000001200" "133000000000000200") -eq $false) "the same instant read to 100 ns matches; 100 microseconds apart does not"
# Back to the reporting adapter for what follows.
Register-HordeLaunchAdapter -Name "harness-a" -Program "harness-a" `
    -Argv { param($s) $a = @("--id", $s.sessionId) + @($s.permissionArgs); if ("" + $s.name -ne "") { $a += @("--title", $s.name) }; New-HordeKnown -Value ([string[]]$a) } `
    -Preconditions { param($n) @() } `
    -Identify { param($id, $view) if ($script:sessions.ContainsKey($id) -and -not $script:noIdentify) { $x = $script:sessions[$id]; New-HordeKnown -Value ([pscustomobject]@{ pid = $x.pid; procStart = $x.procStart; name = $x.name; remoteControl = (New-HordeKnown -Value $true) }) } else { New-HordeAbsent -Note "none" } } `
    -ReadMode { param($id, $view) if (-not $script:readAt.ContainsKey($id)) { $script:readAt[$id] = $script:sent.Count }; if ($script:sessions.ContainsKey($id) -and $null -ne $script:sessions[$id].mode) { New-HordeKnown -Value $script:sessions[$id].mode } else { New-HordeAbsent -Note "none" } } `
    -CloseText @("bye", "`r")

Write-Host ""
Write-Host "--- a wrong-mode session that cannot be ended (review of #104, F2) ---" -ForegroundColor Cyan
Reset; $script:stubborn = $true; $script:stopDenied = $true; $script:reportMode = "bypass"
$ctxU = New-Context
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $ctxU
$x = $script:sessions[$o.sessionId]
$rec = Read-HordeNodeSpawnRecord -Dir $ctxU.records -SessionId $o.sessionId
Check ("$($o.state)" -ceq "failed" -and $o.reason -like "*could NOT be ended*" -and $script:procs.ContainsKey($x.pid) -and $script:stopRefused -ge 1) "a wrong-mode session that ignores its close and that the host will not end is answered FAILED, never refused (review of #104, F2)"
Check ($null -ne $o.expect -and $o.expect.pid -eq $x.pid -and "$($o.expect.procStart)" -ceq $script:procs[$x.pid]) "and the answer carries its process, so the hub can close it again"
Check ("$($rec.value.outcome)" -ceq "unkept-running" -and "$($rec.value.closedAt)" -eq "") "the node records it as still running, with no time it was closed"
Check (@($script:alerts | Where-Object { $_ -like "ALERT:*$($o.sessionId)*still running*" }).Count -eq 1) "and raises an alert naming it"
Check (-not (@($script:sent | ForEach-Object { $_.text }) -ccontains "read the plan")) "it never saw its work"
$script:stubborn = $false; $script:stopDenied = $false
$ctx = $ctxU
$c = CloseWith ([pscustomobject]@{ sessionId = $o.sessionId; expect = $o.expect; reason = "close the unkept session" })
Check ("$($c.state)" -ceq "done" -and -not $script:procs.ContainsKey($x.pid)) "CONTROL: the hub closes it with the process it was given"

Write-Host ""
Write-Host "--- the work is delivered only after the mode is proven (review of #104, F4: prevent, not detect) ---" -ForegroundColor Cyan
Reset; $script:reportMode = "plan"
$ctxP = New-Context
$o = Invoke-HordeNodeActRequest -Act (SpawnAct @{ prompt = [pscustomobject]@{ text = ("line one" + [char]10 + "line two") } }) -Context $ctxP
Check ("$($o.state)" -ceq "refused" -and @($script:sent | Where-Object { $_.text -like "*line one*" -or $_.text -like "Read the file*" }).Count -eq 0 -and @(Get-ChildItem -LiteralPath $ctxP.records -Filter "*.prompt.txt" -ErrorAction SilentlyContinue).Count -eq 0) "a session whose mode reads back wrong never receives its prompt, typed or as a file"
Reset
$ctxP = New-Context
$multi = "line one" + [char]13 + [char]10 + "line two"
$o = Invoke-HordeNodeActRequest -Act (SpawnAct @{ prompt = [pscustomobject]@{ text = $multi } }) -Context $ctxP
$pf = Join-Path $ctxP.records ($o.sessionId + ".prompt.txt")
$texts = @($script:sent | ForEach-Object { $_.text })
Check ("$($o.state)" -ceq "done" -and (Test-Path -LiteralPath $pf) -and [System.IO.File]::ReadAllText($pf) -ceq $multi) ("a prompt holding a line break is written whole to a file beside the records (" + $o.state + " " + $o.reason + ")")
Check (($texts -join "|") -ceq ($noOp + "|<enter>|Read the file " + $pf + " and do what it says.|<enter>")) "and the session is told in one typed line to read it: the text itself is never typed raw"
Reset
$long = "x" * 1500
$o = Invoke-HordeNodeActRequest -Act (SpawnAct @{ prompt = [pscustomobject]@{ text = $long } }) -Context $ctxP
Check ("$($o.state)" -ceq "done" -and -not (@($script:sent | ForEach-Object { $_.text }) -ccontains $long) -and [System.IO.File]::ReadAllText((Join-Path $ctxP.records ($o.sessionId + ".prompt.txt"))) -ceq $long) ("a prompt longer than one typed line goes to a file the same way (" + $o.state + " " + $o.reason + ")")
Reset; $script:noOpRefused = $true
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $ctxP
Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*could not be read back*" -and -not (@($script:sent | ForEach-Object { $_.text }) -ccontains "read the plan")) "a line that asks for nothing the host will not type is no readback: the session is closed and never sees its prompt"
Reset; $script:promptRefused = $true
$ctxP = New-Context
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $ctxP
$rec = Read-HordeNodeSpawnRecord -Dir $ctxP.records -SessionId $o.sessionId
Check ("$($o.state)" -ceq "failed" -and $o.reason -like "*prompt could not be typed*" -and $null -ne $o.expect -and "$($rec.value.outcome)" -ceq "running-no-prompt") ("a prompt the host will not type fails the spawn, with the process to close it by, recorded as running without its work (" + $o.state + " " + $o.reason + ")")

Write-Host ""
Write-Host "--- refused before anything starts: a profile that needs a key (round 1: this had no test) ---" -ForegroundColor Cyan
Reset
$keyed = [pscustomobject]@{ schemaVersion = 1; providers = @([pscustomobject]@{ name = "provider-k"; protocol = "anthropic-messages"; credential = [pscustomobject]@{ kind = "env"; ref = "PROVIDER_K_TOKEN" } }); profiles = @([pscustomobject]@{ name = "keyed"; harness = "harness-a"; provider = "provider-k" }); rules = @() }
$ctxK = New-Context
$ctxK.layers = @($ctxK.layers) + @([pscustomobject]@{ layer = "L1"; source = "fixture L1 keyed"; doc = $keyed })
$ctxK.policy = Read-HordeNodePolicyText -Text ($policyText.Replace('"profiles": ["alpha", "beta"]', '"profiles": ["alpha", "keyed"]'))
$o = Invoke-HordeNodeActRequest -Act (SpawnAct @{ profile = "keyed" }) -Context $ctxK
Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*provider-k needs a key*E10*" -and $script:panes.Count -eq 0) "a profile whose provider needs a key is refused until the launch stub exists: only the harness's own login is started remotely"
Reset
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $ctxK
Check ("$($o.state)" -ceq "done") "CONTROL: the same node starts an own-login profile"

Write-Host ""
Write-Host "--- refused before anything starts: the node's own configuration and terminal ---" -ForegroundColor Cyan
Reset
$ctx = New-Context; $ctx | Add-Member -NotePropertyName layerProblems -NotePropertyValue @("C:\h\engine.json $.rules[0].set: key-value - 'Plan' is not a value of remote.permissionCeiling") -Force
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $ctx
Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*engine configuration fails its checks*Plan*" -and $script:panes.Count -eq 0) "a layer file that fails its checks refuses every spawn, never dropped and acted on without it (review of #98, F1)"
Reset; $script:noOwn = $true
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context (New-Context)
Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*cannot name its own terminal*" -and $script:panes.Count -eq 0) "a node that cannot name its own terminal starts nothing: no call ever falls back to whatever terminal the environment points at"
Reset
Register-HordeHostActor -Name "fakehost2" -Own { New-HordeKnown -Value $fakeTerm } -Resolve { param($n) New-HordeKnown -Value "C:\npm\harness-a.cmd" } -Start { param($t, $p, $a, $c, $e) [void]$script:panes.Add($p); New-HordeKnown -Value ([pscustomobject]@{ handle = "1" }) } -Send { param($t, $h, $x, $s) New-HordeKnown -Value $true } -Live { param($t, $h, $e) New-HordeKnown -Value $true } -Stop { param($t, $h, $e) New-HordeKnown -Value $true }
$o = Invoke-HordeNodeActRequest -Act (SpawnAct @{ host = "fakehost2" }) -Context (New-Context)
Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*absolute path to an .exe*" -and $script:panes.Count -eq 0) "a host that resolves the harness to a .cmd shim starts nothing: the program is an absolute .exe or no program (review of #98, F3)"
$script:HordeHostActors.Remove(@($script:HordeHostActors | Where-Object { $_.name -ceq "fakehost2" })[0])

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
# THE COUNT, case by case (review of #98: clock skew, the UTC-day boundary, concurrency, junctions).
$cd = Join-Path $work "count"
New-Item -ItemType Directory -Path $cd | Out-Null
$noon = [datetime]::SpecifyKind([datetime]::Parse("2026-10-05T12:00:00"), [System.DateTimeKind]::Utc)
function Rec { param([string]$Name, [string]$At) [System.IO.File]::WriteAllText((Join-Path $cd ($Name + ".json")), ('{ "sessionId": "' + $Name + '", "startedAt": "' + $At + '" }')) }
Rec "a" "2026-10-04T23:59:59.9990000Z"
Check ((Get-HordeNodeSpawnsToday -Dir $cd -Now $noon).value -eq 0) "a start one millisecond before UTC midnight is yesterday's"
Rec "b" "2026-10-05T00:00:00.0000000Z"
Check ((Get-HordeNodeSpawnsToday -Dir $cd -Now $noon).value -eq 1) "a start at UTC midnight is today's"
Rec "c" "2026-10-07T09:00:00.0000000Z"
Check ((Get-HordeNodeSpawnsToday -Dir $cd -Now $noon).value -eq 2) "a start in the future counts: setting the clock back frees nothing"
[System.IO.File]::WriteAllText((Join-Path $cd "d.json"), "{ torn")
Check ((Get-HordeNodeSpawnsToday -Dir $cd -Now $noon).value -eq 3) "a record that cannot be read counts: a torn file never raises the cap"
Check ((Get-HordeNodeSpawnsToday -Dir $cd -Now ([datetime]::Parse("2026-10-04T22:30:00Z").ToUniversalTime())).value -eq 4) "the day is the UTC day: at 22:30 UTC on the 4th, the 4th's start counts, with everything after it and the torn one"
$localNow = [datetime]::SpecifyKind([datetime]::Parse("2026-10-05T00:30:00"), [System.DateTimeKind]::Local)
$lc = Get-HordeNodeSpawnsToday -Dir $cd -Now $localNow
Check ($lc.state -eq "unknown" -and $lc.reason -like "*clock in UTC*") "a local time is refused, never quietly taken as a UTC day"
$uc = Get-HordeNodeSpawnsToday -Dir $cd -Now ([datetime]::SpecifyKind([datetime]::Parse("2026-10-05T00:30:00"), [System.DateTimeKind]::Unspecified))
Check ($uc.state -eq "unknown") "and so is a time of unspecified kind"
$lk = Enter-HordeNodeSpawnLock -Dir $cd
try {
    Check ($null -ne $lk -and $null -eq (Enter-HordeNodeSpawnLock -Dir $cd)) "the spawn lock is held by one act at a time"
    $ctxL = New-Context; $ctxL.records = $cd
    Reset
    $o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $ctxL
    Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*spawn lock*" -and $script:panes.Count -eq 0) "a spawn while another holds the lock is refused: the cap is never counted by two at once"
} finally { if ($null -ne $lk) { $lk.Dispose() } }
$jdir = Join-Path $work "junction"
$null = cmd /c mklink /J "$jdir" "$cd"
if (Test-Path -LiteralPath $jdir) {
    $jc = Get-HordeNodeSpawnsToday -Dir $jdir -Now $noon
    Check ($jc.state -eq "unknown" -and $jc.reason -like "*junction or link*") "a records folder that is a junction refuses: what it counts is another folder's"
    $ctxJ = New-Context; $ctxJ.records = $jdir
    Reset
    $o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $ctxJ
    Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*junction or link*") "and so does a spawn counted through it"
    [System.IO.Directory]::Delete($jdir)
} else { Check $false "CONTROL: a junction could be made for the test" }

Write-Host ""
Write-Host "--- the way to the records: no junction anywhere from the node's home down (review of #104, F6) ---" -ForegroundColor Cyan
$h6 = Join-Path $work "home-f6"
$elsewhere = Join-Path $work "elsewhere-f6"
New-Item -ItemType Directory -Path $h6, $elsewhere -Force | Out-Null
$null = cmd /c mklink /J "$(Join-Path $h6 'node')" "$elsewhere"
if (Test-Path -LiteralPath (Join-Path $h6 "node")) {
    $ctx6 = New-Context; $ctx6.home = $h6; $ctx6.records = Join-Path $h6 "node\spawned"
    Reset
    $o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $ctx6
    Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*node, on the way to the records, is a junction or link*" -and $script:panes.Count -eq 0) "a junction above the records folder - <home>\node - refuses the spawn, not only one at the folder itself"
    Check (@(Get-ChildItem -LiteralPath $elsewhere -Force).Count -eq 0) "and nothing was created through it: the check comes before the lock file and the folder"
    [System.IO.Directory]::Delete((Join-Path $h6 "node"))
} else { Check $false "CONTROL: a junction could be made for the test" }
Check ((Test-HordeNodeRecordsChain -HordeHome $h6 -Dir (Join-Path $work "outside")) -like "*not inside this node's home*") "a records folder outside the node's home is refused"
Check ((Test-HordeNodeRecordsChain -HordeHome $h6 -Dir (Join-Path $h6 "node\spawned")) -eq "") "CONTROL: plain folders, or folders not made yet, pass"

Write-Host ""
Write-Host "--- the owner's files are read at every spawn, not when serving starts (review of #104, F1 and F3) ---" -ForegroundColor Cyan
$h1 = Join-Path $work "home-live"
New-Item -ItemType Directory -Path (Join-Path $h1 "node") -Force | Out-Null
$polPath = Join-Path $h1 "node\policy.json"
function Set-Pol { param([int]$Cap) [System.IO.File]::WriteAllText($polPath, $policyText.Replace('"dailySpawnCap": 3', ('"dailySpawnCap": ' + $Cap))) }
function Set-Layer { param([string]$Name, [string]$Text) [System.IO.File]::WriteAllText((Join-Path $h1 $Name), $Text) }
function Real-Context {
    # The node's own context, built by the real function from real files, with only the machine swapped
    # for the fixture world: harness descriptors, L0, clock and process table.
    $c = New-HordeNodeActContext -Root $root -HordeHome $h1 -Namespace ([pscustomobject]@{ device = $device; space = "windows" })
    $c.descriptors = $descriptors; $c.builtin = @(Read-HordeEngineLayerText -Text ([System.IO.File]::ReadAllText((Join-Path $fx "builtin.json")) -replace ',\s*\{ "name": "beta"[^}]*\}', '') -Layer "L0" -Source "fixture L0")
    $c.processStart = { param($p) if ($script:procs.ContainsKey([int]$p)) { $script:procs[[int]$p] } else { $null } }
    $c.sleep = { param($ms) }; $c.now = { [datetime]::Parse("2026-10-05T12:00:00Z").ToUniversalTime() }
    $c.bounds = [pscustomobject]@{ identifySeconds = 2; modeSeconds = 2; closeSeconds = 2; pollMs = 100 }
    $c.environment = @{}; $c.alert = { param($m) [void]$script:alerts.Add($m) }
    return $c
}
$rc = Real-Context
Check ($rc.note -like "*acts: OFF*no policy file*") ("a node with no policy says, as it starts serving, that it acts on nothing (" + $rc.note + ")")
Set-Pol 3
Reset
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $rc
Check ("$($o.state)" -ceq "done") ("CONTROL: the policy written after serving started is read by the next spawn: done" + $(if ("$($o.state)" -cne "done") { " (" + $o.reason + ")" } else { "" }))
Set-Layer "engine-live.json" '{ "schemaVersion": 1, "rules": [ { "id": "owner-cut", "match": {}, "set": { "remote.permissionCeiling": "plan" }, "writtenBy": "user" } ] }'
Reset
$o = Invoke-HordeNodeActRequest -Act (SpawnAct @{ permission = "edits" }) -Context $rc
Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*above this node's ceiling, plan*" -and $script:panes.Count -eq 0) ("a ceiling lowered to plan in engine-live.json holds from the next spawn, with no restart (" + $o.reason + ")")
Remove-Item -LiteralPath (Join-Path $h1 "engine-live.json")
Set-Pol 0
Reset
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $rc
Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*cap of 0*" -and $script:panes.Count -eq 0) ("a daily cap set to 0 holds from the next spawn (" + $o.reason + ")")
Remove-Item -LiteralPath $polPath
Reset
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $rc
Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*no policy file*" -and $script:panes.Count -eq 0) "a deleted policy holds from the next spawn: nothing starts"
Set-Pol 3
foreach ($case in @(@("not JSON", "{ not json"), @("the enum value 'Plan'", '{ "schemaVersion": 1, "rules": [ { "id": "c", "match": {}, "set": { "remote.permissionCeiling": "Plan" }, "writtenBy": "user" } ] }'), @("null", "null"), @("an array", "[]"))) {
    Set-Layer "engine.json" $case[1]
    $eng = Get-HordeNodeEngineLayers -Root $root -HordeHome $h1 -Descriptors $descriptors -Builtin $rc.builtin
    Check (@($eng.problems).Count -ge 1 -and (@($eng.problems) -join " ") -like ("*" + (Join-Path $h1 "engine.json") + "*")) ("engine.json holding " + $case[0] + " is a problem naming the file (" + (@($eng.problems) -join " | ") + ")")
    Reset
    $o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $rc
    Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*fails its checks*" -and $script:panes.Count -eq 0) ("and the next spawn is refused for it: " + $case[0])
}
Check ((Real-Context).note -like "*ENGINE CONFIGURATION FAILS ITS CHECKS*") "the note a node prints as it starts serving says its configuration fails"
Set-Layer "engine.json" '{ "schemaVersion": 1, "rules": [ { "id": "c", "match": {}, "set": { "remote.permissionCeiling": "edits" }, "writtenBy": "user" } ] }'
$eng = Get-HordeNodeEngineLayers -Root $root -HordeHome $h1 -Descriptors $descriptors -Builtin $rc.builtin
Check (@($eng.problems).Count -eq 0 -and @($eng.layers | Where-Object { $_.layer -ceq "L1" }).Count -eq 1) "CONTROL: a good engine.json is no problem, and is read as L1"
Set-Layer "engine-live.json" "[]"
$eng = Get-HordeNodeEngineLayers -Root $root -HordeHome $h1 -Descriptors $descriptors -Builtin $rc.builtin
Check (@($eng.problems).Count -ge 1 -and (@($eng.problems) -join " ") -like "*engine-live.json*") "engine-live.json is read and checked as well (L4)"
Remove-Item -LiteralPath (Join-Path $h1 "engine-live.json")
Reset
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $rc
Check ("$($o.state)" -ceq "done") "CONTROL: fixed again, the next spawn is done, still with no restart"

Write-Host ""
Write-Host "--- at serve start, records a stopped node left starting are settled (review of #104, F5) ---" -ForegroundColor Cyan
Reset
$ctxR = New-Context
New-Item -ItemType Directory -Path $ctxR.records -Force | Out-Null
function Starting { param([string]$Sid, $ProcId, [string]$Start, [string]$Outcome = "starting") Write-HordeNodeSpawnRecord -Dir $ctxR.records -Record ([pscustomobject][ordered]@{ sessionId = $Sid; requestId = "r"; hubId = $hub; host = "fakehost"; harness = "harness-a"; handle = "900"; level = "edits"; name = "n"; workdir = $clone; label = "E"; startedAt = "2026-10-05T11:00:00.0000000Z"; pid = $ProcId; procStart = $Start; closedAt = ""; outcome = $Outcome }) }
$script:procs[7001] = "134000000000007001"
Starting "a0000000-0000-4000-8000-000000000001" 7001 "134000000000007001"
Starting "a0000000-0000-4000-8000-000000000002" 7002 "134000000000007002"
$script:procs[7003] = "134000000000007003"; $script:sessions["a0000000-0000-4000-8000-000000000003"] = [pscustomobject]@{ pid = 7003; procStart = "134000000000007003"; name = "n"; mode = "edits"; handle = "903" }
Starting "a0000000-0000-4000-8000-000000000003" $null ""
Starting "a0000000-0000-4000-8000-000000000004" $null ""
$script:procs[7005] = "134000000000007005"; $script:sessions["a0000000-0000-4000-8000-000000000005"] = [pscustomobject]@{ pid = 7005; procStart = "133000000000007005"; name = "n"; mode = "edits"; handle = "905" }
Starting "a0000000-0000-4000-8000-000000000005" $null ""
$script:procs[7006] = "134000000000007006"
Starting "a0000000-0000-4000-8000-000000000006" 7006 "134000000000007006" "running"
$lines = @(Invoke-HordeNodeReconcile -Context $ctxR)
function Rc { param([string]$Sid) (Read-HordeNodeSpawnRecord -Dir $ctxR.records -SessionId $Sid).value }
$r1 = Rc "a0000000-0000-4000-8000-000000000001"
Check ("$($r1.outcome)" -ceq "running" -and "$($r1.reconciled)" -like "*mode was never read back*" -and @($script:alerts | Where-Object { $_ -like "ALERT:*a0000000-0000-4000-8000-000000000001*" }).Count -eq 1) "a starting record whose process runs with its pid and start time is marked running, with an alert: its mode was never read back"
$r2 = Rc "a0000000-0000-4000-8000-000000000002"
Check ("$($r2.outcome)" -ceq "failed" -and "$($r2.closedAt)" -ne "") "one whose process is gone is marked failed, with the time it was settled"
$r3 = Rc "a0000000-0000-4000-8000-000000000003"
Check ("$($r3.outcome)" -ceq "running" -and [long]$r3.pid -eq 7003 -and "$($r3.procStart)" -ceq "134000000000007003") "one never proven is looked up in the harness's own record, and kept with the process proven by its start time"
Check ("$((Rc 'a0000000-0000-4000-8000-000000000004').outcome)" -ceq "failed") "one the harness has no record of is marked failed"
Check ("$((Rc 'a0000000-0000-4000-8000-000000000005').outcome)" -ceq "failed") "one whose harness names a pid now running with another start time is marked failed, not believed"
Check ("$((Rc 'a0000000-0000-4000-8000-000000000006').outcome)" -ceq "running" -and "$((Rc 'a0000000-0000-4000-8000-000000000006').reconciled)" -eq "") "a record that was not left starting is not touched"
Check ($lines.Count -eq 5) ("one line for each record settled (" + $lines.Count + ")")

Write-Host ""
Write-Host "--- a close: only a session this node started, only the process the hub names, gracefully ---" -ForegroundColor Cyan
Reset
$ctx = New-Context
$s = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $ctx
$closeArgs = [pscustomobject]@{ sessionId = $s.sessionId; expect = $s.expect; reason = "the work is done" }
$c = Invoke-HordeNodeActRequest -Act ([pscustomobject]@{ verb = "session.close"; args = $closeArgs; requestId = [guid]::NewGuid().ToString(); hubId = $hub }) -Context $ctx
$x = $script:sessions[$s.sessionId]
Check ("$($c.state)" -ceq "done" -and -not $script:procs.ContainsKey($x.pid) -and "$($c.sessionId)" -ceq $s.sessionId) "a close ends the session: done, and no process has its pid and start time"
Check ((@($script:sent | Where-Object { $_.handle -ceq $x.handle } | ForEach-Object { $_.text }) -join "|") -ceq ($noOp + "|<enter>|read the plan|<enter>|bye|<enter>") -and @($script:stopped).Count -eq 0) "it typed the harness's close text into that pane, then Enter by -Submit, and forced nothing"
$rec = Read-HordeNodeSpawnRecord -Dir $ctx.records -SessionId $s.sessionId
Check ($rec.state -eq "known" -and "$($rec.value.closedAt)" -ne "") "the node's record says when it was closed"
$c = Invoke-HordeNodeActRequest -Act ([pscustomobject]@{ verb = "session.close"; args = $closeArgs; requestId = [guid]::NewGuid().ToString(); hubId = $hub }) -Context $ctx
Check ("$($c.state)" -ceq "done" -and $c.reason -like "*already ended*") "closing a session that has already ended is done, saying so"
Reset
$s = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $ctx
$x = $script:sessions[$s.sessionId]
$wrong = [pscustomobject]@{ ns = $s.expect.ns; pid = $s.expect.pid; procStart = "" + ([long]$s.expect.procStart + 1) }
$typed = $script:sent.Count
$c = CloseWith ([pscustomobject]@{ sessionId = $s.sessionId; expect = $wrong; reason = "x" })
Check ("$($c.state)" -ceq "refused" -and $c.reason -like "*differs*" -and $script:procs.ContainsKey($x.pid) -and $script:sent.Count -eq $typed) "a close naming another start time than the node's view is refused, and nothing is typed"
$far = [pscustomobject]@{ ns = [pscustomobject]@{ device = "11111111-2222-4333-8444-555555555555"; space = "windows" }; pid = $s.expect.pid; procStart = $s.expect.procStart }
$c = CloseWith ([pscustomobject]@{ sessionId = $s.sessionId; expect = $far; reason = "x" })
Check ("$($c.state)" -ceq "refused" -and $c.reason -like "*device*" -and $script:procs.ContainsKey($x.pid)) "a close naming a process of another device is refused: a pid is looked up only on its own device"
$typed = $script:sent.Count
$c = CloseWith ([pscustomobject]@{ sessionId = $s.sessionId; expect = $s.expect; reason = "x" }) -From "22222222-3333-4444-8555-666666666666"
Check ("$($c.state)" -ceq "refused" -and $c.reason -like "*started for the hub $hub*" -and $script:procs.ContainsKey($x.pid) -and $script:sent.Count -eq $typed) "a close from another hub than the one that asked for the session is refused, and nothing is typed (review of #104, F8)"
$rec = Read-HordeNodeSpawnRecord -Dir $ctx.records -SessionId $s.sessionId
Check ("$($rec.value.hubId)" -ceq $hub) "the node's record keeps the hub that asked for the session"
$noHub = SpawnAct; $noHub.hubId = ""
$panesBefore = $script:panes.Count
$o = Invoke-HordeNodeActRequest -Act $noHub -Context $ctx
Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*names no hub*" -and $script:panes.Count -eq $panesBefore) "a spawn that names no hub is refused: no hub could ever close it"
$c = CloseWith ([pscustomobject]@{ sessionId = "99999999-1111-4222-8333-444444444444"; expect = $s.expect; reason = "x" })
Check ("$($c.state)" -ceq "refused" -and $c.reason -like "*did not start*") "a session this node did not start for a hub is refused"
$script:stubborn = $true
$c = CloseWith ([pscustomobject]@{ sessionId = $s.sessionId; expect = $s.expect; reason = "x" })
Check ("$($c.state)" -ceq "failed" -and $c.reason -like "*still running*" -and $script:procs.ContainsKey($x.pid) -and @($script:stopped).Count -eq 0) "a session that ignores the close is answered failed and left running: a close is graceful, nothing is forced"
} finally {
    if ((Split-Path -Leaf $work) -match '^horde-nodeact-[0-9a-f]{32}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

Complete-HordeSuite -Success "a node starts and closes a hub's sessions exactly as its policy, its ceiling and the process allow, each proved by pid and start time"
