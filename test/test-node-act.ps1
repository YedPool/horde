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
# THE TURN RECEIPT'S WORLD (issue #214): what each pane's input box holds, the user turns the fixture
# harness recorded, and the ways an Enter is lost. A line is lost by pattern: -clike against the box's
# text when Enter is pressed. loseFirstLike loses only the Enter typed with the text, so the one extra
# Enter submits it; loseAllLike loses every Enter; dropTurnLike empties the box and records no turn.
$script:box = @{}
$script:turns = New-Object System.Collections.ArrayList
$script:loseFirstLike = ""
$script:loseAllLike = ""
$script:dropTurnLike = ""
$script:lateLooks = 0
$script:noTranscript = $false
$script:noScreen = $false
# TIME, TURNS THAT TAKE IT, AND A SESSION THAT IS NOT READY AT ONCE (PR 239 round 2). The clock is the
# context's: every wait sleeps on it, so a wait's bound is wall time here as in the node. A submitted line
# starts a turn that runs turnMs; a line submitted while one runs is QUEUED, as measured on 2026-10-14
# (an enqueue, then a turn once the running one ends), not a turn. Until readyAtMs (or ever, with
# neverReady) the screen shows no box and every key typed is LOST, as the measured start-up lost one;
# slowScreenMs is what each look at the screen costs, as a host call can take up to its own timeout.
$script:clockMs = 0.0
$script:turnMs = 0
$script:busyUntil = @{}
$script:queued = @{}
$script:ends = New-Object System.Collections.ArrayList
$script:readyAtMs = 0
$script:neverReady = $false
$script:slowScreenMs = 0
$script:noModeLine = $false
# What each host call costs on the clock, and what one read of the mode record costs (review of PR 239,
# S-a and S-b): every call counted at the host's own timeout, and a mode read that ends past the limit.
$script:hostCallMs = 0
$script:slowModeMs = 0
$script:alerts = New-Object System.Collections.ArrayList
# How many texts had been typed when a session's mode was first read, by session id.
$script:readAt = @{}
$noOp = "Reply with OK only."
$hub = "7c9e6679-7425-40de-944b-e07fc1f90ae7"
$modeOf = @{ careful = "ask"; edit = "edits"; look = "plan" }

function Step-Fixture {
    # Let the world's time pass: a turn whose time is up ends, and a line queued behind it becomes a turn.
    foreach ($h in @($script:busyUntil.Keys)) {
        if ($script:clockMs -lt [double]$script:busyUntil[$h]) { continue }
        [void]$script:ends.Add([pscustomobject]@{ handle = $h; at = $script:busyUntil[$h] })
        $script:busyUntil.Remove($h)
        if ($script:queued.ContainsKey($h)) {
            [void]$script:turns.Add([pscustomobject]@{ handle = $h; text = $script:queued[$h] }); $script:queued.Remove($h)
            $script:busyUntil[$h] = $script:clockMs + $script:turnMs
        }
    }
}
function Test-FixtureReady { return [bool](-not $script:neverReady -and $script:clockMs -ge $script:readyAtMs) }

function Register-FixtureHarness {
    # harness-a; -Blind registers it without the turn receipt, as a kind that cannot tell; -NoReady
    # without InputReady and -NoTurnDone without TurnDone, each a kind that cannot tell that one thing.
    param([switch]$Blind, [switch]$NoReady, [switch]$NoTurnDone)
    $receipt = @{}
    if (-not $Blind) {
        $receipt["TurnMark"] = { param($id, $view) New-HordeKnown -Value ([pscustomobject]@{ n = $script:turns.Count; e = $script:ends.Count }) }
        $receipt["TurnSeen"] = { param($id, $view, $mark, $line)
            Step-Fixture
            if ($script:noTranscript) { return (New-HordeKnown -Value $false) }
            $h = $script:sessions[$id].handle
            $hit = $false
            for ($i = [int]$mark.n; $i -lt $script:turns.Count; $i++) { if ($script:turns[$i].handle -ceq $h -and $script:turns[$i].text -ceq $line) { $hit = $true } }
            if ($hit -and $script:lateLooks -gt 0) { $script:lateLooks--; $hit = $false }
            New-HordeKnown -Value $hit }
        $receipt["InputHolds"] = { param($screen, $line) if (-not ("" + @($screen)[0]).StartsWith("BOX:")) { New-HordeUnknown -Reason "no box on the fixture screen" } else { New-HordeKnown -Value (@($screen)[0] -ceq ("BOX:" + $line)) } }
        if (-not $NoTurnDone) {
            $receipt["TurnDone"] = { param($id, $view, $mark)
                Step-Fixture
                $h = $script:sessions[$id].handle
                New-HordeKnown -Value ([bool](@($script:ends | Select-Object -Skip ([int]$mark.e) | Where-Object { $_.handle -ceq $h }).Count -gt 0)) }
        }
        if (-not $NoReady) {
            $receipt["InputReady"] = { param($screen) if (("" + @($screen)[0]).StartsWith("BOX:") -and @($screen)[1] -ceq "IDLE") { New-HordeKnown -Value $true } else { New-HordeUnknown -Reason ("the fixture screen shows " + @($screen)[0]) } }
        }
    }
Register-HordeLaunchAdapter -Name "harness-a" -Program "harness-a" @receipt `
    -Argv { param($s) $a = @("--id", $s.sessionId); foreach ($g in @($s.addDirs)) { if ("" + $g -ne "") { $a += @("--grant", ("" + $g)) } }; $a += @($s.permissionArgs); if ("" + $s.name -ne "") { $a += @("--title", $s.name) }; if ("" + $s.prompt -ne "") { $a += @($s.prompt) }; New-HordeKnown -Value ([string[]]$a) } `
    -Preconditions { param($n) @() } `
    -Identify { param($id, $view) if ($script:sessions.ContainsKey($id) -and -not $script:noIdentify) { $x = $script:sessions[$id]; New-HordeKnown -Value ([pscustomobject]@{ pid = $x.pid; procStart = $x.procStart; name = $x.name; remoteControl = (New-HordeKnown -Value $true) }) } else { New-HordeAbsent -Note "no control file yet" } } `
    -ReadMode { param($id, $view) $script:clockMs += $script:slowModeMs; if (-not $script:readAt.ContainsKey($id)) { $script:readAt[$id] = $script:sent.Count }; if ($script:sessions.ContainsKey($id) -and $null -ne $script:sessions[$id].mode -and -not $script:noModeLine) { New-HordeKnown -Value $script:sessions[$id].mode } else { New-HordeAbsent -Note "no mode line yet" } } `
    -CloseText @("bye", "`r")
}
Register-FixtureHarness

# The fixture terminal: named explicitly by Own, as the real host names the node's own (review of #96).
$fakeTerm = [pscustomobject]@{ socket = "C:\fake\terminal-1"; guiPid = 1; guiStart = "1" }
Register-HordeHostActor -Name "fakehost" `
    -Own { $script:clockMs += $script:hostCallMs; if ($script:noOwn) { New-HordeUnknown -Reason "2 terminals are running; which one is this node's own cannot be told" } else { New-HordeKnown -Value $fakeTerm } } `
    -Resolve { param($n) $script:clockMs += $script:hostCallMs; if ($n -ceq "harness-a") { New-HordeKnown -Value "C:\bin\harness-a.exe" } else { New-HordeUnknown -Reason ("no " + $n) } } `
    -Start { param($term, $prog, $argv, $cwd, $envMap)
        $script:clockMs += $script:hostCallMs
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
        $script:clockMs += $script:hostCallMs
        if ("" + $t -cmatch '[\x00-\x1F]') { return (New-HordeUnknown -Reason "the fixture host, like the real one, types printable text only") }
        if ($script:noOpRefused -and "" + $t -ceq "Reply with OK only.") { return (New-HordeUnknown -Reason "the fixture host refuses this text") }
        if ($script:promptRefused -and "" + $t -ne "" -and "" + $t -cne "bye" -and "" + $t -cne "Reply with OK only.") { return (New-HordeUnknown -Reason "the fixture host refuses this text") }
        Step-Fixture
        $taking = Test-FixtureReady
        if ("" + $t -ne "") { [void]$script:sent.Add([pscustomobject]@{ handle = $h; text = $t; at = $script:clockMs }); if ($taking) { $script:box[$h] = ("" + $script:box[$h]) + $t } }
        if ($submit) {
            [void]$script:sent.Add([pscustomobject]@{ handle = $h; text = "<enter>"; at = $script:clockMs })
            if (-not $taking) { return (New-HordeKnown -Value $true) }
            $held = "" + $script:box[$h]
            $lost = ($script:loseAllLike -ne "" -and $held -clike $script:loseAllLike) -or ($script:loseFirstLike -ne "" -and "" + $t -ne "" -and $held -clike $script:loseFirstLike)
            if (-not $lost) {
                $script:box[$h] = ""
                # The close text then Enter: the fixture harness exits.
                if ($held -ceq "bye") { if (-not $script:stubborn) { foreach ($s in @($script:sessions.Values)) { if ($s.handle -ceq $h) { $script:procs.Remove($s.pid) } } } }
                elseif ($held -ne "" -and $script:busyUntil.ContainsKey($h)) { $script:queued[$h] = $held }
                elseif ($held -ne "" -and -not ($script:dropTurnLike -ne "" -and $held -clike $script:dropTurnLike)) { [void]$script:turns.Add([pscustomobject]@{ handle = $h; text = $held }); $script:busyUntil[$h] = $script:clockMs + $script:turnMs }
            }
        }
        New-HordeKnown -Value $true } `
    -Text { param($term, $h)
        Step-Fixture
        $script:clockMs += $script:slowScreenMs + $script:hostCallMs
        if ($script:noScreen) { return (New-HordeUnknown -Reason "the fixture host shows no screen") }
        if (-not (Test-FixtureReady)) { return (New-HordeKnown -Value ([string[]]@("STARTING", ""))) }
        New-HordeKnown -Value ([string[]]@(("BOX:" + $script:box[$h]), $(if ($script:busyUntil.ContainsKey($h)) { "BUSY" } else { "IDLE" }))) } `
    -Live { param($term, $h, $expect) New-HordeKnown -Value $true } `
    -Stop { param($term, $h, $expect)
        $script:clockMs += $script:hostCallMs
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
        sleep = { param($ms) $script:clockMs += $ms }; clock = { $script:clockMs }; now = { [datetime]::Parse("2026-10-05T12:00:00Z").ToUniversalTime() }
        bounds = [pscustomobject]@{ identifySeconds = 2; readySeconds = 2; modeSeconds = 2; closeSeconds = 2; receiptSeconds = 1; retrySeconds = 1; turnEndSeconds = 5; spawnSeconds = 60; pollMs = 100 }
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
function PromptFile { param($Ctx, [string]$Sid) return (Join-Path (Join-Path $Ctx.records $Sid) "prompt.txt") }
function PromptLine { param($Ctx, [string]$Sid) return ("Read " + (PromptFile $Ctx $Sid) + " and do what it says.") }
function Typed { return @($script:sent | ForEach-Object { $_.text }) }
function Reset { $script:panes.Clear(); $script:sent.Clear(); $script:stopped.Clear(); $script:reportMode = $null; $script:noIdentify = $false; $script:stubborn = $false; $script:reusedPid = $false; $script:noOwn = $false; $script:offByMicros = $false; $script:stopRefused = 0; $script:stopDenied = $false; $script:promptRefused = $false; $script:noOpRefused = $false; $script:alerts.Clear(); $script:readAt.Clear()
    $script:box.Clear(); $script:turns.Clear(); $script:loseFirstLike = ""; $script:loseAllLike = ""; $script:dropTurnLike = ""; $script:lateLooks = 0; $script:noTranscript = $false; $script:noScreen = $false
    $script:clockMs = 0.0; $script:turnMs = 0; $script:busyUntil.Clear(); $script:queued.Clear(); $script:ends.Clear(); $script:readyAtMs = 0; $script:neverReady = $false; $script:slowScreenMs = 0; $script:noModeLine = $false; $script:hostCallMs = 0; $script:slowModeMs = 0 }

try {
Write-Host ""
Write-Host "--- a spawn: policy, plan, pane, process, mode - then done, with the process to close it by ---" -ForegroundColor Cyan
Reset
$ctx0 = New-Context
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $ctx0
Check ("$($o.state)" -ceq "done") ("a spawn the policy allows is done" + $(if ("$($o.state)" -cne "done") { " (" + $o.reason + ")" } else { "" }))
$p = $script:panes[0]
Check ($script:panes.Count -eq 1 -and $p.program -ceq "C:\bin\harness-a.exe" -and $p.cwd -ceq $clone -and $p.term -eq $fakeTerm) "one pane, in the terminal the host named, running the absolute .exe it resolved, in the registered clone (no worktree given)"
Check ((@($p.argv) -join "|") -ceq ("--id|" + $o.sessionId + "|--grant|" + (Join-Path $ctx0.records $o.sessionId) + "|--mode|edit|--title|E client search orc")) "its argv is the launch plan's: the id the node chose, the level's flags, the name - and NO prompt (review of #104, F4)"
Check ((@($script:sent | Where-Object { $_.handle -ceq $p.handle } | ForEach-Object { $_.text }) -join "|") -ceq ($noOp + "|<enter>|" + (PromptLine $ctx0 $o.sessionId) + "|<enter>")) "once the mode was proven, the one line typed names the prompt's file; the hub's text is never typed (review of #104, F9)"
Check ([System.IO.File]::ReadAllText((PromptFile $ctx0 $o.sessionId)) -ceq "read the plan") "the file holds the prompt exactly"
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
    -Argv { param($s) $a = @("--id", $s.sessionId); foreach ($g in @($s.addDirs)) { if ("" + $g -ne "") { $a += @("--grant", ("" + $g)) } }; $a += @($s.permissionArgs); New-HordeKnown -Value ([string[]]$a) } `
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
# Back to the reporting adapter, with its turn receipt, for what follows.
Register-FixtureHarness

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
Check (@(Typed | Where-Object { $_ -clike "Read *" }).Count -eq 0 -and -not (Test-Path -LiteralPath (PromptFile $ctxU $o.sessionId))) "it never saw its work"
$script:stubborn = $false; $script:stopDenied = $false
$ctx = $ctxU
$c = CloseWith ([pscustomobject]@{ sessionId = $o.sessionId; expect = $o.expect; reason = "close the unkept session" })
Check ("$($c.state)" -ceq "done" -and -not $script:procs.ContainsKey($x.pid)) "CONTROL: the hub closes it with the process it was given"

Write-Host ""
Write-Host "--- the work is delivered only after the mode is proven (review of #104, F4: prevent, not detect) ---" -ForegroundColor Cyan
Reset; $script:reportMode = "plan"
$ctxP = New-Context
$o = Invoke-HordeNodeActRequest -Act (SpawnAct @{ prompt = [pscustomobject]@{ text = ("line one" + [char]10 + "line two") } }) -Context $ctxP
Check ("$($o.state)" -ceq "refused" -and @(Typed | Where-Object { $_ -like "*line one*" -or $_ -clike "Read *" }).Count -eq 0 -and @(Get-ChildItem -LiteralPath $ctxP.records -Recurse -Filter "prompt.txt" -ErrorAction SilentlyContinue).Count -eq 0) "a session whose mode reads back wrong never receives its prompt, typed or as a file"

Write-Host ""
Write-Host "--- every prompt goes by file; the hub's text never reaches the input box (review of #104, F9) ---" -ForegroundColor Cyan
$cases = @("!whoami", "/permissions", "#remember this", "@C:\secret.txt summarise", ("a" + [char]0x2028 + "b"), ("line one" + [char]13 + [char]10 + "line two"), ("x" * 1500))
$names = @("! (a shell command)", "/ (a command)", "# (memory)", "@ (a file)", "U+2028 (a line separator)", "a line break", "1500 characters")
for ($i = 0; $i -lt $cases.Count; $i++) {
    Reset
    $ctxF = New-Context
    $o = Invoke-HordeNodeActRequest -Act (SpawnAct @{ prompt = [pscustomobject]@{ text = $cases[$i] } }) -Context $ctxF
    $typed = Typed
    $pf = PromptFile $ctxF $o.sessionId
    Check ("$($o.state)" -ceq "done" -and ($typed -join "|") -ceq ($noOp + "|<enter>|" + (PromptLine $ctxF $o.sessionId) + "|<enter>") -and -not ($typed -ccontains $cases[$i])) ("a prompt starting with or holding " + $names[$i] + " never reaches send-text: the only lines typed are the constant no-op and the line naming its file")
    Check ((Test-Path -LiteralPath $pf) -and [System.IO.File]::ReadAllText($pf, [System.Text.Encoding]::UTF8) -ceq $cases[$i]) ("and the file holds it exactly: " + $names[$i])
}
foreach ($bad in @("!x", "/x", "#x", "@x", ("Read a" + [char]0x2028), ("Read " + [char]0x00E9), ("Read a" + [char]10), "")) {
    Check (-not (Test-HordeNodeTypedLine -Line $bad)) ("the typed-line check refuses '" + ($bad -replace '[^\x20-\x7E]', '?') + "'")
}
Check (Test-HordeNodeTypedLine -Line "Read C:\h\node\spawned\x\prompt.txt and do what it says.") "CONTROL: the line naming a plain path passes"

Write-Host ""
Write-Host "--- the prompt's folder: its own, this user's alone, granted to the session at launch (review of #104, F10) ---" -ForegroundColor Cyan
Reset
$ctxG = New-Context
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $ctxG
$pdir = Join-Path $ctxG.records $o.sessionId
$argv = @($script:panes[0].argv)
$gi = [array]::IndexOf($argv, "--grant")
Check ($gi -ge 0 -and $argv[$gi + 1] -ceq $pdir -and @($argv | Where-Object { $_ -ceq "--grant" }).Count -eq 1 -and -not ($argv -ccontains $ctxG.records)) "the session is granted its own prompt folder, and only it: never the records folder"
$acl = Get-Acl -LiteralPath $pdir
$me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
$rules = @($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
Check ($acl.AreAccessRulesProtected -and $rules.Count -ge 1 -and @($rules | Where-Object { $_.IdentityReference -ne $me }).Count -eq 0) ("the folder is this user's alone: inheritance cut, every rule this user's (" + $rules.Count + " rule(s))")
$rec = Read-HordeNodeSpawnRecord -Dir $ctxG.records -SessionId $o.sessionId
Check ("$($rec.value.promptDir)" -ceq $pdir) "the record names the prompt folder"
# Called directly: a session id is fresh, so only a folder planted ahead of it can be a junction.
$ctxJ2 = New-Context
New-Item -ItemType Directory -Path $ctxJ2.records, (Join-Path $work "elsewhere-prompt") -Force | Out-Null
$planted = "b0000000-0000-4000-8000-000000000001"
$null = cmd /c mklink /J "$(Join-Path $ctxJ2.records $planted)" "$(Join-Path $work 'elsewhere-prompt')"
if (Test-Path -LiteralPath (Join-Path $ctxJ2.records $planted)) {
    $pj = New-HordeNodePromptDir -Context $ctxJ2 -SessionId $planted
    Check ($pj.reason -like "*junction or link*" -and $pj.dir -eq "") ("a prompt folder that is a junction is refused, never granted (" + $pj.reason + ")")
    [System.IO.Directory]::Delete((Join-Path $ctxJ2.records $planted))
} else { Check $false "CONTROL: a junction could be made for the test" }
$hU = Join-Path $work ("home-" + [char]0x00E9)
New-Item -ItemType Directory -Path $hU -Force | Out-Null
Reset
$ctxU8 = New-Context; $ctxU8.home = $hU; $ctxU8.records = Join-Path $hU "spawned"
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $ctxU8
Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*could not be typed safely*" -and $script:panes.Count -eq 0) "a prompt folder whose path cannot be typed as printable ASCII refuses the spawn before anything starts"

Reset; $script:noOpRefused = $true
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $ctxP
Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*could not be read back*" -and @(Typed | Where-Object { $_ -clike "Read *" }).Count -eq 0) "a line that asks for nothing the host will not type is no readback: the session is closed and never sees its prompt"
Reset; $script:promptRefused = $true
$ctxP = New-Context
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $ctxP
$rec = Read-HordeNodeSpawnRecord -Dir $ctxP.records -SessionId $o.sessionId
Check ("$($o.state)" -ceq "failed" -and $o.reason -like "*prompt could not be typed*" -and $null -ne $o.expect -and "$($rec.value.outcome)" -ceq "running-no-prompt") ("a prompt the host will not type fails the spawn, with the process to close it by, recorded as running without its work (" + $o.state + " " + $o.reason + ")")

Write-Host ""
Write-Host "--- a typed line counts only once it is a turn in the transcript (issue #214) ---" -ForegroundColor Cyan
function SpawnOnce { param([scriptblock]$Tune = $null) $c = New-Context; if ($null -ne $Tune) { & $Tune $c }; $o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $c; $r = Read-HordeNodeSpawnRecord -Dir $c.records -SessionId $o.sessionId; return [pscustomobject]@{ o = $o; rec = $r.value; line = (PromptLine $c $o.sessionId) } }
function Alive { param($O) return [bool]($null -ne $O.expect -and $script:procs.ContainsKey([int]$O.expect.pid) -and @($script:stopped).Count -eq 0) }
Reset
$x = SpawnOnce
Check ("$($x.o.state)" -ceq "done" -and "$($x.rec.noOpTurn)" -ceq "taken" -and "$($x.rec.promptTurn)" -ceq "taken" -and ((Typed) -join "|") -ceq ($noOp + "|<enter>|" + $x.line + "|<enter>")) ("CONTROL: both turns seen at once: done, no extra Enter (" + $x.o.state + " " + $x.o.reason + ")")
Reset; $script:loseFirstLike = "*"
$x = SpawnOnce
Check ("$($x.o.state)" -ceq "done" -and ((Typed) -join "|") -ceq ($noOp + "|<enter>|<enter>|" + $x.line + "|<enter>|<enter>")) ("the first Enter of each line lost: ONE extra Enter per line, as its box still held it, and done (" + $x.o.state + " " + $x.o.reason + " / " + ((Typed) -join "|") + ")")
Reset; $script:loseAllLike = "Read *"
$x = SpawnOnce
Check ("$($x.o.state)" -ceq "failed" -and $x.o.reason -clike "prompt-not-submitted:*" -and $x.o.reason -like ("*session " + $x.o.sessionId + "*") -and $x.o.reason -like ("*pane " + $x.rec.handle + "*") -and $x.o.reason -like "*LEFT RUNNING*" -and (Alive $x.o) -and "$($x.rec.outcome)" -ceq "prompt-not-submitted") ("every Enter of the prompt line lost: failed prompt-not-submitted, naming the session and its pane, and the session is left running (" + $x.o.state + " " + $x.o.reason + ")")
Check (((Typed) -join "|") -ceq ($noOp + "|<enter>|" + $x.line + "|<enter>|<enter>") -and $x.o.reason -like "*ONE more Enter*") ("...with exactly one extra Enter for that line, never two (" + ((Typed) -join "|") + ")")
Reset; $script:loseAllLike = "*"
$x = SpawnOnce
Check ("$($x.o.state)" -ceq "failed" -and $x.o.reason -clike "prompt-not-submitted: the no-op line*" -and (Alive $x.o) -and ((Typed) -join "|") -ceq ($noOp + "|<enter>|<enter>")) ("every Enter of the no-op line lost: failed prompt-not-submitted, one extra Enter, the prompt line never typed after it, the session left running (" + $x.o.reason + " / " + ((Typed) -join "|") + ")")
Reset; $script:loseAllLike = "Reply*"; [void]$script:turns.Add([pscustomobject]@{ handle = "100"; text = $noOp })
$x = SpawnOnce
Check ("$($x.o.state)" -ceq "failed" -and $x.o.reason -clike "prompt-not-submitted: the no-op line*" -and $x.rec.handle -ceq "100") ("a turn holding the same line in that pane BEFORE it was typed is not its receipt (" + $x.o.state + " " + $x.o.reason + ")")
Reset; $script:lateLooks = 5
$x = SpawnOnce
Check ("$($x.o.state)" -ceq "done" -and ((Typed) -join "|") -ceq ($noOp + "|<enter>|" + $x.line + "|<enter>")) ("a turn that arrives late but inside the wait: done, no extra Enter (" + $x.o.state + " " + $x.o.reason + ")")
Reset; $script:noTranscript = $true
$x = SpawnOnce
Check ("$($x.o.state)" -ceq "failed" -and $x.o.reason -clike "prompt-not-submitted:*" -and $x.o.reason -like "*did not hold the line*" -and (Alive $x.o) -and ((Typed) -join "|") -ceq ($noOp + "|<enter>")) ("no transcript ever, the box emptied: not done, and no extra Enter (" + $x.o.reason + ")")
Reset; $script:dropTurnLike = "Read *"
$x = SpawnOnce
Check ("$($x.o.state)" -ceq "failed" -and $x.o.reason -clike "prompt-not-submitted:*" -and (Alive $x.o) -and ((Typed) -join "|") -ceq ($noOp + "|<enter>|" + $x.line + "|<enter>")) ("the box already empty with no turn: no extra Enter, failed prompt-not-submitted (" + $x.o.reason + ")")
# A kind that cannot tell readiness, so the unreadable screen is met first at the extra Enter: with
# InputReady, an unreadable screen is a session never ready (above), and nothing is typed at all.
Reset; $script:noScreen = $true; $script:loseAllLike = "Read *"
Register-FixtureHarness -NoReady
try { $x = SpawnOnce } finally { Register-FixtureHarness }
Check ("$($x.o.state)" -ceq "failed" -and $x.o.reason -like "*could not be read*" -and ((Typed) -join "|") -ceq ($noOp + "|<enter>|" + $x.line + "|<enter>")) ("a screen the host cannot show: no extra Enter is pressed blind (" + $x.o.reason + ")")
Reset
Register-FixtureHarness -Blind
try { $x = SpawnOnce } finally { Register-FixtureHarness }
Check ("$($x.o.state)" -ceq "failed" -and $x.o.reason -clike "prompt-unconfirmed:*cannot tell*" -and (Alive $x.o) -and "$($x.rec.outcome)" -ceq "prompt-unconfirmed" -and ((Typed) -join "|") -ceq ($noOp + "|<enter>|" + $x.line + "|<enter>")) ("a harness that cannot tell: NOT done, said plainly, the session left running, no extra Enter (" + $x.o.state + " " + $x.o.reason + ")")

Write-Host ""
Write-Host "--- nothing is typed before the session is ready for keys (PR 239 round 2) ---" -ForegroundColor Cyan
function FirstTypedAt { $f = @($script:sent | Where-Object { $_.text -cne "bye" } | Select-Object -First 1); if ($f.Count -eq 0) { return $null }; return [double]$f[0].at }
Reset
$x = SpawnOnce
Check ("$($x.o.state)" -ceq "done" -and "$($x.rec.ready)" -ceq "ready") ("CONTROL: a session ready at once is typed into at once, and done (" + $x.o.state + " " + $x.o.reason + ")")
Reset; $script:readyAtMs = 1500
$x = SpawnOnce
Check ("$($x.o.state)" -ceq "done" -and "$($x.rec.ready)" -ceq "ready" -and (FirstTypedAt) -ge 1500) ("a session ready late, inside the wait: nothing typed until it is ready (first key at " + (FirstTypedAt) + " ms), then done (" + $x.o.state + " " + $x.o.reason + ")")
Reset; $script:neverReady = $true
$x = SpawnOnce
Check ("$($x.o.state)" -ceq "failed" -and $x.o.reason -clike "not-ready:*" -and $x.o.reason -like ("*session " + $x.o.sessionId + "*") -and $x.o.reason -like ("*pane " + $x.rec.handle + "*") -and $x.o.reason -like "*LEFT RUNNING*") ("a session never ready: failed not-ready, naming the session and its pane (" + $x.o.reason + ")")
Check ($script:sent.Count -eq 0 -and (Alive $x.o) -and "$($x.rec.outcome)" -ceq "not-ready" -and "$($x.rec.ready)" -ceq "not-ready" -and $null -ne $x.o.expect -and @($script:alerts | Where-Object { $_ -like "*never became ready*" }).Count -eq 1) ("...nothing at all typed, the session left running with its process to close it by, recorded not-ready, and an alert raised (" + ((Typed) -join "|") + ")")
Reset; $script:neverReady = $true; $script:slowScreenMs = 20000
$ctxS = New-Context; $ctxS.bounds.readySeconds = 60
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $ctxS
Check ("$($o.state)" -ceq "failed" -and $o.reason -clike "not-ready:*" -and $script:clockMs -le (60000 + 20000 + 2000)) ("each look at the screen costing 20 s, the readiness wait still ends by its 60 s on the clock, plus the one look in flight (" + $script:clockMs + " ms in all) (S3)")
Reset; $script:neverReady = $true
$ctxD = New-Context; $ctxD.bounds.readySeconds = 600; $ctxD.bounds.spawnSeconds = 5
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $ctxD
Check ("$($o.state)" -ceq "failed" -and $o.reason -like "*own limit of 5 s*" -and $script:clockMs -le 5200) ("a wait longer than the spawn's own limit ends at that limit, and the reason says so (" + $script:clockMs + " ms: " + $o.reason + ")")
Reset; $script:readyAtMs = 1500
Register-FixtureHarness -NoReady
try { $x = SpawnOnce } finally { Register-FixtureHarness }
Check ("$($x.o.state)" -ceq "failed" -and "$($x.rec.ready)" -ceq "cannot-tell" -and (FirstTypedAt) -lt 1500 -and $x.o.reason -clike "prompt-not-submitted:*") ("a kind that cannot tell readiness is typed into at once, as before - here before it was ready, so its keys were lost - and the turn receipt still keeps it from being called done (" + $x.o.reason + ")")
Reset
Register-FixtureHarness -NoReady
try { $x = SpawnOnce } finally { Register-FixtureHarness }
Check ("$($x.o.state)" -ceq "done" -and "$($x.rec.ready)" -ceq "cannot-tell") "CONTROL: a kind that cannot tell, ready at once, is done"

Write-Host ""
Write-Host "--- not ready: kept only when its mode is proven, else ended by its process, nothing typed (review of PR 239, S-d) ---" -ForegroundColor Cyan
Reset; $script:neverReady = $true
$x = SpawnOnce
Check ("$($x.o.state)" -ceq "failed" -and $x.o.reason -clike "not-ready:*" -and $x.o.reason -like "*reads edits, as asked*LEFT RUNNING*" -and $script:sent.Count -eq 0 -and (Alive $x.o) -and "$($x.rec.outcome)" -ceq "not-ready" -and $script:readAt[$x.o.sessionId] -eq 0) ("never ready, its mode record reading the level asked for: kept, the mode read with nothing typed (" + $x.o.reason + ")")
Reset; $script:neverReady = $true; $script:reportMode = "bypass"
$x = SpawnOnce
Check ("$($x.o.state)" -ceq "failed" -and $x.o.reason -clike "not-ready:*" -and $x.o.reason -like "*reports the level bypass and was asked for edits*not kept*ended it by its process*" -and $script:sent.Count -eq 0 -and @($script:stopped).Count -eq 1 -and -not $script:procs.ContainsKey([int]$script:sessions[$x.o.sessionId].pid) -and $null -eq $x.o.expect -and "$($x.rec.outcome)" -ceq "not-ready-closed" -and "$($x.rec.closedAt)" -ne "") ("never ready, its mode wrong: ended by the host by its process, no close text typed into the unready box (" + ((Typed) -join "|") + " / " + $x.o.reason + ")")
Reset; $script:neverReady = $true; $script:noModeLine = $true
$x = SpawnOnce
Check ("$($x.o.state)" -ceq "failed" -and $x.o.reason -like "*mode could not be read*not kept*ended it by its process*" -and $script:sent.Count -eq 0 -and @($script:stopped).Count -eq 1 -and -not $script:procs.ContainsKey([int]$script:sessions[$x.o.sessionId].pid) -and "$($x.rec.outcome)" -ceq "not-ready-closed") ("never ready, its mode unreadable: ended by the host, nothing typed (" + $x.o.reason + ")")
Reset; $script:neverReady = $true; $script:reportMode = "bypass"; $script:stopDenied = $true
$x = SpawnOnce
Check ("$($x.o.state)" -ceq "failed" -and $x.o.reason -like "*could NOT be ended*" -and $script:sent.Count -eq 0 -and $null -ne $x.o.expect -and $script:procs.ContainsKey([int]$x.o.expect.pid) -and "$($x.rec.outcome)" -ceq "unkept-running" -and @($script:alerts | Where-Object { $_ -like "ALERT:*$($x.o.sessionId)*could not be ended*" }).Count -eq 1) ("never ready, its mode wrong, and the host will not end it: failed with its process to close it by, recorded still running, an alert raised (" + $x.o.reason + ")")

Write-Host ""
Write-Host "--- the prompt is typed only once the no-op's turn has ENDED (review of PR 239, M1) ---" -ForegroundColor Cyan
Reset; $script:turnMs = 3000
$x = SpawnOnce
$noopEnd = @($script:ends | Select-Object -First 1)
$promptAt = [double](@($script:sent | Where-Object { $_.text -clike "Read *" })[0].at)
Check ("$($x.o.state)" -ceq "done" -and "$($x.rec.noOpEnd)" -ceq "ended" -and $noopEnd.Count -eq 1 -and $promptAt -ge [double]$noopEnd[0].at -and $script:queued.Count -eq 0) ("a no-op turn of 3 s: the prompt is typed after it ended (" + $promptAt + " ms, the turn ended at " + $noopEnd[0].at + " ms), so it is a turn and not queued: done (" + $x.o.state + " " + $x.o.reason + ")")
Reset; $script:turnMs = 3000
Register-FixtureHarness -NoTurnDone
try { $x = SpawnOnce } finally { Register-FixtureHarness }
Check ("$($x.o.state)" -ceq "failed" -and $x.o.reason -clike "prompt-not-submitted:*" -and "$($x.rec.noOpEnd)" -ceq "cannot-tell") ("THE FIXTURE CAN FAIL: without the wait for the turn's end, the prompt typed during the 3 s no-op turn is queued, its receipt wait of 1 s passes, and the spawn is wrongly failed - the false FAILED of M1 (" + $x.o.reason + ")")
Reset; $script:turnMs = 600000
$x = SpawnOnce
Check ("$($x.o.state)" -ceq "failed" -and $x.o.reason -clike "not-ready: the no-op line's turn did not end*" -and @(Typed | Where-Object { $_ -clike "Read *" }).Count -eq 0 -and (Alive $x.o) -and "$($x.rec.outcome)" -ceq "not-ready") ("a no-op turn that never ends: failed not-ready, the prompt never typed, the session left running (" + $x.o.reason + ")")

Write-Host ""
Write-Host "--- no line is typed once too little of the spawn's limit is left for its wait (review of PR 239, S-b) ---" -ForegroundColor Cyan
# The limit is 10 s; a line's wait is receiptSeconds + retrySeconds, 2 s here.
$lim10 = { param($c) $c.bounds.spawnSeconds = 10 }
$lim10r = { param($c) $c.bounds.spawnSeconds = 10; $c.bounds.readySeconds = 60 }
Reset; $script:slowModeMs = 15000
$x = SpawnOnce $lim10
Check ("$($x.o.state)" -ceq "failed" -and $x.o.reason -clike "not-ready: less than 2 s*the prompt was not typed*" -and @(Typed | Where-Object { $_ -clike "Read *" }).Count -eq 0 -and (Alive $x.o) -and "$($x.rec.outcome)" -ceq "not-ready" -and $script:clockMs -ge 10000) ("the limit passed before the prompt (the mode read ended at " + $script:clockMs + " ms): the prompt is not typed, and the session, its mode proven, is left running (" + $x.o.reason + ")")
Reset; $script:slowModeMs = 9000
$x = SpawnOnce $lim10
Check ("$($x.o.state)" -ceq "failed" -and $x.o.reason -clike "not-ready: less than 2 s*" -and @(Typed | Where-Object { $_ -clike "Read *" }).Count -eq 0) ("1 s of the limit left, less than a line's wait: the prompt is not typed (" + $x.o.reason + ")")
Reset; $script:slowModeMs = 5000
$x = SpawnOnce $lim10
Check ("$($x.o.state)" -ceq "done" -and @(Typed | Where-Object { $_ -clike "Read *" }).Count -eq 1) ("CONTROL: 5 s of the limit left, the prompt is typed and taken (" + $x.o.state + " " + $x.o.reason + ")")
Reset; $script:readyAtMs = 9500
$x = SpawnOnce $lim10r
Check ("$($x.o.state)" -ceq "failed" -and $x.o.reason -like "*so the no-op line was not typed*" -and $script:sent.Count -eq 0 -and (Alive $x.o)) ("ready with 0.5 s of the limit left: not even the no-op line is typed, and the not-ready rule decides the session (" + $x.o.reason + ")")
Reset; $script:readyAtMs = 5000
$x = SpawnOnce $lim10r
Check ("$($x.o.state)" -ceq "done") ("CONTROL: ready with 5 s left, the no-op line and the prompt are typed (" + $x.o.reason + ")")
Reset; $script:hostCallMs = 3000
$x = SpawnOnce $lim10
Check ("$($x.o.state)" -ceq "failed" -and $x.o.reason -clike "not-ready:*" -and $script:sent.Count -eq 0) ("the limit counts from the act's start: three host calls before the pane spent 9 of its 10 s, so nothing is typed (" + $x.o.reason + ")")
Reset; $script:reportMode = "bypass"; $script:slowModeMs = 15000
$x = SpawnOnce $lim10
Check ("$($x.o.state)" -ceq "refused" -and @(Typed | Where-Object { $_ -ceq "bye" }).Count -eq 0 -and @($script:stopped).Count -eq 1) ("a wrong mode found past the limit: no close text, whose calls the limit does not count; the host ends the pane by its process (" + ((Typed) -join "|") + ")")
Reset
Register-FixtureHarness -Blind
$script:reportMode = "bypass"
try { $x = SpawnOnce } finally { Register-FixtureHarness }
Check ("$($x.o.state)" -ceq "refused" -and @(Typed | Where-Object { $_ -ceq "bye" }).Count -eq 0 -and @($script:stopped).Count -eq 1) ("a wrong mode after a no-op line whose turn cannot be told: no close text after it, the host ends the pane (F's nit) (" + ((Typed) -join "|") + ")")

# Inside one line's submit: past the limit the box is not looked at, and the extra Enter needs its wait.
$script:subLooks = @{ text = 0; enter = 0 }
$subActor = [pscustomobject]@{ name = "stubhost"
    send = { param($t, $h, $x, $s) if ("" + $x -eq "") { $script:subLooks.enter++ }; New-HordeKnown -Value $true }
    text = { param($t, $h) $script:subLooks.text++; New-HordeKnown -Value ([string[]]@("BOX:held")) } }
$subAdapter = [pscustomobject]@{ name = "stub"; turnMark = { param($i, $v) New-HordeKnown -Value 0 }; turnSeen = { param($i, $v, $m, $l) New-HordeKnown -Value $false }; inputHolds = { param($s, $l) New-HordeKnown -Value $true }
    inputReady = { param($s) New-HordeKnown -Value $true } }
function SubmitWith { param($DeadlineIn)
    $script:subLooks.text = 0; $script:subLooks.enter = 0; $script:clockMs = 0.0
    $c = New-Context; if ($null -ne $DeadlineIn) { $c | Add-Member -NotePropertyName deadlineMs -NotePropertyValue ([double]$DeadlineIn) -Force }
    return (Submit-HordeNodeLine -Context $c -Actor $subActor -Target $fakeTerm -Adapter $subAdapter -Handle "1" -SessionId "s" -Line "held") }
$u = SubmitWith $null
Check ("$($u.state)" -ceq "not-taken" -and $script:subLooks.text -eq 1 -and $script:subLooks.enter -eq 1) ("CONTROL: with no limit, a line still in the box gets its box looked at and ONE extra Enter (" + $u.reason + ")")
$u = SubmitWith 500
Check ("$($u.state)" -ceq "not-taken" -and $script:subLooks.text -eq 0 -and $script:subLooks.enter -eq 0 -and $u.reason -like "*limit ran out, so the box was not looked at*") ("the limit passed during the receipt wait: no host call after it - the box is not looked at, no extra Enter (" + $u.reason + ")")
$u = SubmitWith 1500
Check ("$($u.state)" -ceq "not-taken" -and $script:subLooks.text -eq 1 -and $script:subLooks.enter -eq 0 -and $u.reason -like "*less than 1 s of this spawn's own limit*no other Enter*") ("0.5 s of the limit left after the receipt wait: the box is looked at, but no extra Enter whose turn could not be waited for (" + $u.reason + ")")
$c = New-Context; $script:clockMs = 5000.0; $c | Add-Member -NotePropertyName deadlineMs -NotePropertyValue 4000.0 -Force
$script:subLooks.text = 0
$w = Wait-HordeNodeReady -Context $c -Actor $subActor -Target $fakeTerm -Adapter $subAdapter -Handle "1"
Check ("$($w.state)" -ceq "not-ready" -and $script:subLooks.text -eq 0 -and $w.reason -like "*limit ran out before the screen was looked at*") ("past the limit the readiness wait makes no host call (" + $w.reason + ")")
$c.deadlineMs = 9000.0
$w = Wait-HordeNodeReady -Context $c -Actor $subActor -Target $fakeTerm -Adapter $subAdapter -Handle "1"
Check ("$($w.state)" -ceq "ready" -and $script:subLooks.text -eq 1) "CONTROL: inside the limit it looks, and is ready"

Write-Host ""
Write-Host "--- a stuck no-op line gets no close text, and the reason names it (review of PR 239, S1 and S2) ---" -ForegroundColor Cyan
Reset; $script:reportMode = "bypass"; $script:loseAllLike = "Reply*"
$x = SpawnOnce
Check ("$($x.o.state)" -ceq "refused" -and @(Typed | Where-Object { $_ -ceq "bye" }).Count -eq 0 -and @($script:stopped).Count -eq 1 -and -not $script:procs.ContainsKey([int]$script:sessions[$x.o.sessionId].pid)) ("a wrong level with the no-op line stuck in the box: no close text typed after it, the host ends the pane by its process, refused (" + ((Typed) -join "|") + ")")
Reset; $script:reportMode = "bypass"
$x = SpawnOnce
Check ("$($x.o.state)" -ceq "refused" -and @(Typed | Where-Object { $_ -ceq "bye" }).Count -eq 1) "CONTROL: a wrong level with the no-op taken is closed by its close text first, as before"
Reset; $script:noModeLine = $true; $script:loseAllLike = "Reply*"
$x = SpawnOnce
Check ("$($x.o.state)" -ceq "refused" -and $x.o.reason -like "*could not be read back*" -and $x.o.reason -like "*no-op line 'Reply with OK only.' never became a turn (not-taken*") ("a mode that cannot be read while the no-op line never became a turn: the refusal names the stuck no-op (" + $x.o.reason + ")")
Reset; $script:noModeLine = $true
$x = SpawnOnce
Check ("$($x.o.state)" -ceq "refused" -and $x.o.reason -notlike "*never became a turn*") "CONTROL: with the no-op taken, the refusal does not blame it"

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
Reset
$ctxC = New-Context; $ctxC.now = { [datetime]::SpecifyKind([datetime]::Parse("2026-10-05T12:00:00"), [System.DateTimeKind]::Local) }
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $ctxC
Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*clock in UTC*" -and $script:panes.Count -eq 0) ("a spawn whose day cannot be counted is refused, never counted as room (" + $o.reason + ")")
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
$outside = ""
try { $outside = Test-HordeNodeRecordsChain -HordeHome $h6 -Dir (Join-Path $work "outside") } catch { $outside = "threw: " + $_.Exception.Message }
Check ($outside -like "*not inside this node's home*") ("a records folder outside the node's home is refused (" + $outside + ")")
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
    $c.sleep = { param($ms) $script:clockMs += $ms }; $c.clock = { $script:clockMs }; $c.now = { [datetime]::Parse("2026-10-05T12:00:00Z").ToUniversalTime() }
    $c.bounds = [pscustomobject]@{ identifySeconds = 2; readySeconds = 2; modeSeconds = 2; closeSeconds = 2; receiptSeconds = 1; retrySeconds = 1; turnEndSeconds = 5; spawnSeconds = 60; pollMs = 100 }
    $c.environment = @{}; $c.alert = { param($m) [void]$script:alerts.Add($m) }
    return $c
}
$rc = Real-Context
# THE WAITS FIT THE HUB'S (issue #214; review of PR 239, S3 and S-a). Every wait before the decision
# shares ONE limit, spawnSeconds from the act's start, measured by wall time on the context's clock. Past
# it no host call starts before the decision and the close types no close text, so with every host call
# counted at its timeout H (20 s for the first host) the longest path is a close begun just inside the
# limit: spawnSeconds + the close text (one call per item: two for the fixture harness, as for the first
# harness's /exit then Enter) + closeSeconds + the host's end + closeSeconds. Past the limit: at most one
# call in flight, then the host's end and closeSeconds. Then every path is RUN below on the fixture with
# the shipped bounds and every host call costing 20 s on the clock.
$dctx = New-HordeNodeActContext -Root $root -HordeHome $h1 -Namespace ([pscustomobject]@{ device = $device; space = "windows" })
$db = $dctx.bounds
$hostH = 20
$closeItems = @((Get-HordeLaunchAdapter -Name "harness-a").value.closeText).Count
$line = [double]$db.receiptSeconds + [double]$db.retrySeconds
$inside = [double]$db.spawnSeconds + $closeItems * $hostH + [double]$db.closeSeconds + $hostH + [double]$db.closeSeconds
$past = [double]$db.spawnSeconds + $hostH + $hostH + [double]$db.closeSeconds
$worst = [math]::Max($inside, $past)
Check ($closeItems -eq 2 -and $line -ge 20 -and $line -le 30 -and $worst -le 240 -and [double]$db.readySeconds -ge 30 -and [double]$db.turnEndSeconds -ge 30) ("a typed line's turn is waited for 20 to 30 s, the session's readiness and the no-op's end each at least 30 s, and a spawn's longest path, every host call counted at 20 s, is " + $worst + " s (a close begun inside the limit " + $inside + " s, past it " + $past + " s), inside the hub's 240 s")
function Measure-WorstSpawn {
    # Run every path of a spawn on the fixture, with -Bounds and every host call costing 20 s; returns the
    # longest act's milliseconds on the clock, and the case that took it.
    param($Bounds)
    $cases = New-Object System.Collections.ArrayList
    foreach ($rdy in @(0, 90000, 105000, 115000, 120000)) {
        foreach ($k in @("done", "never-ready", "never-ready-wrong", "never-ready-wrong-denied", "wrong", "wrong-stubborn-denied", "noop-lost-wrong", "prompt-lost", "turn-never-ends", "no-mode-stubborn", "unproven")) { [void]$cases.Add(@($rdy, $k)) }
    }
    $most = 0.0; $which = ""
    foreach ($cs in $cases) {
        Reset; $script:hostCallMs = 20000; $script:readyAtMs = $cs[0]
        switch ($cs[1]) {
            "never-ready" { $script:neverReady = $true }
            "never-ready-wrong" { $script:neverReady = $true; $script:reportMode = "bypass" }
            "never-ready-wrong-denied" { $script:neverReady = $true; $script:reportMode = "bypass"; $script:stopDenied = $true }
            "wrong" { $script:reportMode = "bypass" }
            "wrong-stubborn-denied" { $script:reportMode = "bypass"; $script:stubborn = $true; $script:stopDenied = $true }
            "noop-lost-wrong" { $script:loseAllLike = "Reply*"; $script:reportMode = "bypass"; $script:stubborn = $true }
            "prompt-lost" { $script:loseAllLike = "Read *" }
            "turn-never-ends" { $script:turnMs = 10000000 }
            "no-mode-stubborn" { $script:noModeLine = $true; $script:stubborn = $true; $script:stopDenied = $true }
            "unproven" { $script:noIdentify = $true }
        }
        $cw = New-Context; $cw.bounds = $Bounds.PSObject.Copy()
        $null = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $cw
        if ($script:clockMs -gt $most) { $most = $script:clockMs; $which = $cs[1] + " ready at " + $cs[0] + " ms" }
    }
    return [pscustomobject]@{ ms = $most; case = $which }
}
$wm = Measure-WorstSpawn -Bounds $db
Check ($wm.ms -le 240000 -and $wm.ms -le 1000 * $worst) ("RUN with the shipped bounds and every host call costing 20 s, the longest spawn took " + $wm.ms + " ms on the clock (" + $wm.case + "): inside the sum above and the hub's 240 s (S-a)")
$wide = $db.PSObject.Copy(); $wide.spawnSeconds = 200
$wm2 = Measure-WorstSpawn -Bounds $wide
Check ($wm2.ms -gt 240000) ("THE MEASURE CAN FAIL: with a limit of 200 s the same runs go past the hub's 240 s (" + $wm2.ms + " ms, " + $wm2.case + ")")
$c1 = & $dctx.clock
Start-Sleep -Milliseconds 30
Check ((& $dctx.clock) - $c1 -ge 25) "the node's own clock is wall time in milliseconds, so its waits are bounded by the stopwatch"
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
# A file not saved as plain ASCII refuses too, named with its cause (the reader checks bytes first).
[System.IO.File]::WriteAllBytes((Join-Path $h1 "engine.json"), [System.Text.Encoding]::UTF8.GetBytes('{ "schemaVersion": 1, "rules": [ { "id": "caf' + [char]0x00E9 + '", "match": {}, "set": { "remote.permissionCeiling": "edits" }, "writtenBy": "user" } ] }'))
Reset
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $rc
Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*engine.json: not ASCII*" -and $script:panes.Count -eq 0) ("a non-ASCII engine.json refuses the next spawn, naming the file and the cause (" + $o.reason + ")")
Remove-Item -LiteralPath (Join-Path $h1 "engine.json")
[System.IO.File]::WriteAllBytes((Join-Path $h1 "engine-live.json"), [byte[]](@(0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::ASCII.GetBytes('{ "schemaVersion": 1, "rules": [] }')))
Reset
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $rc
Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*engine-live.json: not ASCII*byte-order mark*" -and $script:panes.Count -eq 0) ("an engine-live.json with a byte-order mark refuses the next spawn, naming the file and the mark (" + $o.reason + ")")
Remove-Item -LiteralPath (Join-Path $h1 "engine-live.json")
# Held open by another process, it refuses too: a layer that cannot be read is never left out (review of #109).
Set-Layer "engine-live.json" '{ "schemaVersion": 1, "rules": [] }'
$hold = [System.IO.File]::Open((Join-Path $h1 "engine-live.json"), [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
Reset
try { $o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $rc } finally { $hold.Dispose() }
Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*engine-live.json: cannot be read*" -and $script:panes.Count -eq 0) ("an engine-live.json that cannot be read refuses the next spawn, naming the file (" + $o.reason + ")")
Remove-Item -LiteralPath (Join-Path $h1 "engine-live.json")
# And a policy file saved with a byte-order mark refuses, naming the mark rather than "not JSON".
[System.IO.File]::WriteAllBytes($polPath, [byte[]](@(0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::ASCII.GetBytes($policyText)))
Reset
$o = Invoke-HordeNodeActRequest -Act (SpawnAct) -Context $rc
Check ("$($o.state)" -ceq "refused" -and $o.reason -like "*not plain ASCII*byte-order mark*" -and $script:panes.Count -eq 0) ("a policy file with a byte-order mark refuses the next spawn, naming the cause (" + $o.reason + ")")
Set-Pol 3
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
Check ((@($script:sent | Where-Object { $_.handle -ceq $x.handle } | ForEach-Object { $_.text }) -join "|") -ceq ($noOp + "|<enter>|" + (PromptLine $ctx $s.sessionId) + "|<enter>|bye|<enter>") -and @($script:stopped).Count -eq 0) "it typed the harness's close text into that pane, then Enter by -Submit, and forced nothing"
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
