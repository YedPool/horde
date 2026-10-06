# cli/NodeAct - what a node does when a hub asks it to start or close a session: the half of an act
# that touches the machine.
#
# REMOTE PLAN R19 AND R9, THE ACT PATH'S A3 (planning/execution-plan-remote.md; decisions of
# 2026-10-05). remote/NodeServe.ps1 records each act request in the journal and hands it here once;
# this file decides and acts, and returns the outcome { state; sessionId; expect; reason } that the
# journal keeps and the hub is answered with. It lives in cli/ because it reaches the machine - the
# host's panes (core/HostAct.ps1 and hosts/<name>/Act.ps1), the harness's own records
# (core/AgentLaunch.ps1 and agents/<name>/Launch.ps1) and the process table - none of which remote/
# may touch (tools/ExecScan.ps1). Process launching itself is the host's; nothing here starts one.
#
# A SPAWN, in order, each step a refusal with its reason if it does not hold:
#   1. the node's policy and ceiling (core/NodePolicy.ps1), over the engine resolution of the node's
#      own layers plus the request compiled into the spawn layer (L5): its profile, model and level;
#   2. a profile on the harness's own login only: a provider's key belongs to engines E10's launch
#      stub, so a profile that needs one is refused until it exists (decision of 2026-10-05);
#   3. the folder: the registered clone, or an existing worktree under its root - none is created;
#   4. the launch plan (core/AgentLaunch.ps1) and the program, resolved by the host;
#   5. the pane, then the harness's own record of its process, believed only when the live process
#      has that pid AND that start time; never reported within the bound, the pane is ended;
#   6. the mode the session reports (issue #67, decision 6): exactly the level asked for, or the
#      session is closed - gracefully, then by the host - and the spawn refused. Unreadable within the
#      bound is the same: fail closed.
# The node keeps a record of each session it started for a hub (<HordeHome>\node\spawned), with its
# pane: the only sessions a close may name, and the count behind the daily cap.
#
# A CLOSE is graceful only. The node refuses unless it started that session, the hub's expected
# process is on this device and space (R11) and is exactly the node's own view, pid and start time;
# then it types the harness's close text and waits. A process gone by pid and start time is done; one
# still running is failed, and nothing is forced.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
$script:HordeNodeActCore = Split-Path -Parent $PSScriptRoot
foreach ($f in @("Tristate", "Namespace", "NodePolicy", "EngineResolve", "AgentLaunch", "HostAct")) { . (Join-Path $script:HordeNodeActCore ("core\" + $f + ".ps1")) }

function Get-HordeNodeSpawnDir {
    # Where a node keeps its records of the sessions it started for a hub.
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    return (Join-Path (Join-Path $HordeHome "node") "spawned")
}

function Read-HordeNodeSpawnRecord {
    # One spawn record, as an answer: known, absent when the node never started that session, unknown
    # when the file cannot be read.
    param([Parameter(Mandatory = $true)][string]$Dir, [Parameter(Mandatory = $true)][string]$SessionId)
    if ($SessionId -cnotmatch '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z') { return (New-HordeAbsent -Note ("'" + $SessionId + "' is not a session id this node gives")) }
    $p = Join-Path $Dir ($SessionId + ".json")
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return (New-HordeAbsent -Note ("this node did not start the session " + $SessionId + " for a hub")) }
    try { return (New-HordeKnown -Value ([System.IO.File]::ReadAllText($p) | ConvertFrom-Json)) }
    catch { return (New-HordeUnknown -Reason ("this node's record of " + $SessionId + " cannot be read: " + $_.Exception.Message)) }
}

function Write-HordeNodeSpawnRecord {
    # Write one spawn record whole: a temporary file, then one rename over the old one.
    param([Parameter(Mandatory = $true)][string]$Dir, [Parameter(Mandatory = $true)]$Record)
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }
    $final = Join-Path $Dir ("" + $Record.sessionId + ".json")
    $tmp = Join-Path $Dir ("." + $Record.sessionId + "." + [guid]::NewGuid().ToString("N") + ".tmp")
    [System.IO.File]::WriteAllText($tmp, ($Record | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $final -Force
}

function Get-HordeNodeSpawnsToday {
    # How many sessions this node started for a hub on the UTC day of -Now, from its records.
    param([Parameter(Mandatory = $true)][string]$Dir, [Parameter(Mandatory = $true)][datetime]$Now)
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { return 0 }
    $day = $Now.ToUniversalTime().ToString("yyyy-MM-dd")
    $n = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Filter "*.json" -File)) {
        try { $r = [System.IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json } catch { $n++; continue }
        # A record that cannot be read still counts: the cap is never raised by a torn file.
        if ("" + $r.startedAt -like ($day + "*")) { $n++ }
    }
    return $n
}

function Get-HordeLocalProcessStart {
    # A live process's start time as FILETIME ticks (UTC) in text, the unit the harnesses' control files
    # and core/Projection.ps1 use, or $null when no process has that pid.
    param([Parameter(Mandatory = $true)][int]$ProcessId)
    $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($null -eq $p) { return $null }
    try { return ("" + $p.StartTime.ToUniversalTime().ToFileTimeUtc()) } catch { return $null }
}

function New-HordeNodeOutcome {
    param([Parameter(Mandatory = $true)][string]$State, [string]$SessionId = "", $Expect = $null, [string]$Reason = "")
    return [pscustomobject]@{ state = $State; sessionId = $SessionId; expect = $Expect; reason = $Reason }
}

function Wait-HordeNodeUntil {
    # Ask -Probe until it answers something other than $null, or -Seconds pass on the context's clock.
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)][scriptblock]$Probe, [Parameter(Mandatory = $true)][double]$Seconds)
    $polls = [math]::Max(1, [int][math]::Ceiling(($Seconds * 1000) / [math]::Max(1, $Context.bounds.pollMs)))
    for ($i = 0; $i -le $polls; $i++) {
        $v = & $Probe
        if ($null -ne $v) { return $v }
        if ($i -lt $polls) { & $Context.sleep $Context.bounds.pollMs }
    }
    return $null
}

function Test-HordeNodeProcessGone {
    # Is the process -ProcessId with start time -ProcStart gone: no process has that pid, or the one that
    # has it started at another time?
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)][long]$ProcessId, [Parameter(Mandatory = $true)][string]$ProcStart)
    $live = & $Context.processStart $ProcessId
    return [bool]($null -eq $live -or "" + $live -cne $ProcStart)
}

function Stop-HordeNodeSession {
    # End a session this node just started and will not keep: its close text, then the host's end of
    # its pane. Returns whether the process is gone (known by pid and start time when given).
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)]$Actor, [Parameter(Mandatory = $true)]$Adapter, [Parameter(Mandatory = $true)][string]$Handle, $ProcessId = $null, [string]$ProcStart = "")
    foreach ($t in @($Adapter.closeText)) { $null = & $Actor.send $Handle $t }
    if ($null -ne $ProcessId) {
        $gone = Wait-HordeNodeUntil -Context $Context -Seconds $Context.bounds.closeSeconds -Probe { if (Test-HordeNodeProcessGone -Context $Context -ProcessId $ProcessId -ProcStart $ProcStart) { $true } else { $null } }
        if ($gone -eq $true) { return $true }
    }
    $null = & $Actor.stop $Handle
    if ($null -eq $ProcessId) { return $false }
    $gone = Wait-HordeNodeUntil -Context $Context -Seconds $Context.bounds.closeSeconds -Probe { if (Test-HordeNodeProcessGone -Context $Context -ProcessId $ProcessId -ProcStart $ProcStart) { $true } else { $null } }
    return [bool]($gone -eq $true)
}

function Get-HordeNodeActor {
    # The host actor a session starts in: the one named, or the only one loaded.
    param([string]$Name)
    if ($Name -ne "") { return (Get-HordeHostActor -Name $Name) }
    $all = @($script:HordeHostActors)
    if ($all.Count -eq 1) { return (New-HordeKnown -Value $all[0]) }
    if ($all.Count -eq 0) { return (New-HordeUnknown -Reason "no host on this node can act") }
    return (New-HordeUnknown -Reason ("more than one host can act here (" + (@($all | ForEach-Object { $_.name }) -join ", ") + "); the request must name one"))
}

function Test-HordeNodeOwnLogin {
    # Does the resolved provider run on the harness's own login? Read from the definitions in the layers.
    param([Parameter(Mandatory = $true)][object[]]$Layers, [Parameter(Mandatory = $true)][string]$Provider)
    foreach ($l in @($Layers)) {
        foreach ($pv in @(Get-HordeConfigItems $l.doc "providers")) { if ("" + $pv.name -ceq $Provider) { return [bool]("" + $pv.credential.kind -ceq "harness-login") } }
    }
    return $false
}

function Invoke-HordeNodeSpawn {
    param([Parameter(Mandatory = $true)]$Act, [Parameter(Mandatory = $true)]$Context)
    $a = $Act.args
    # 1. The request as the spawn layer, then the node's policy and ceiling over the resolution.
    $set = [ordered]@{ profile = "" + $a.profile }
    if ($null -ne $a.PSObject.Properties["model"] -and "" + $a.model -ne "") { $set["model"] = "" + $a.model }
    if ($null -ne $a.PSObject.Properties["permission"] -and "" + $a.permission -ne "") { $set["permission"] = "" + $a.permission }
    $l5 = [pscustomobject]@{ layer = "L5"; source = ("spawn request " + $Act.requestId); doc = [pscustomobject]@{ schemaVersion = 1; rules = @([pscustomobject]@{ id = "spawn"; match = [pscustomobject]@{}; set = [pscustomobject]$set; writtenBy = "cli" }) } }
    $layers = @($Context.layers) + @($l5)
    $target = @{ role = "" + $a.role; run = "" + $a.runId; label = "" + $a.label }
    if ($null -ne $a.PSObject.Properties["title"]) { $target["title"] = "" + $a.title }
    if ($null -ne $a.PSObject.Properties["parent"]) { $target["parent"] = "" + $a.parent }
    $res = $null
    try { $res = Resolve-HordeEngine -Layers $layers -Target $target -Descriptors $Context.descriptors -Now (& $Context.now) }
    catch { return (New-HordeNodeOutcome -State "refused" -Reason ("the engine could not be resolved: " + $_.Exception.Message)) }
    $wt = $null
    if ($null -ne $a.PSObject.Properties["worktree"]) { $wt = $a.worktree }
    $req = [pscustomobject]@{ profile = "" + $a.profile; repoId = "" + $a.repoId; worktree = $wt }
    $today = Get-HordeNodeSpawnsToday -Dir $Context.records -Now (& $Context.now)
    $d = Test-HordeRemotePolicy -Policy $Context.policy -Resolution $res -Request $req -SpawnsToday $today
    if (-not $d.allowed) { return (New-HordeNodeOutcome -State "refused" -Reason (@($d.reasons) -join "; ")) }
    # 2. Own login only.
    if (-not (Test-HordeNodeOwnLogin -Layers $layers -Provider ("" + $res.binding.value.provider))) { return (New-HordeNodeOutcome -State "refused" -Reason ("the provider " + $res.binding.value.provider + " needs a key, which only engines E10's launch stub may hand a session; until it exists only a profile on the harness's own login is started remotely")) }
    # 3. The folder.
    if (-not (& $Context.workdirExists $d.workdir)) { return (New-HordeNodeOutcome -State "refused" -Reason ("the folder " + $d.workdir + " does not exist; this version starts sessions only in existing folders and creates no worktree")) }
    # 4. The plan, the program and the host.
    $sid = [guid]::NewGuid().ToString()
    $title = $null
    if ($null -ne $a.PSObject.Properties["title"]) { $title = "" + $a.title }
    $name = Format-HordeSessionName -Label ("" + $a.label) -Title $title
    $prompt = ""
    if ($null -ne $a.prompt.PSObject.Properties["text"]) { $prompt = "" + $a.prompt.text }
    $plan = New-HordeLaunchPlan -Resolution $res -Level $d.level -SessionId $sid -Name $name -Prompt $prompt
    if ($plan.state -ne "known") { return (New-HordeNodeOutcome -State "refused" -Reason $plan.reason) }
    $hostName = "" + $Context.hostName
    if ($null -ne $a.PSObject.Properties["host"] -and "" + $a.host -ne "") { $hostName = "" + $a.host }
    $ac = Get-HordeNodeActor -Name $hostName
    if ($ac.state -ne "known") { return (New-HordeNodeOutcome -State "refused" -Reason $ac.reason) }
    $actor = $ac.value
    $adapter = (Get-HordeLaunchAdapter -Name $plan.value.harness).value
    $prog = & $actor.resolve $plan.value.program
    if ($prog.state -ne "known") { return (New-HordeNodeOutcome -State "refused" -Reason $prog.reason) }
    # 5. The pane, recorded before it starts so a node that stops halfway leaves a trace.
    $started = (& $Context.now).ToUniversalTime().ToString("o")
    $record = [ordered]@{ sessionId = $sid; requestId = "" + $Act.requestId; host = $actor.name; harness = $plan.value.harness; handle = ""; level = $d.level; name = $plan.value.name; workdir = $d.workdir; label = "" + $a.label; startedAt = $started; pid = $null; procStart = ""; closedAt = ""; outcome = "starting" }
    Write-HordeNodeSpawnRecord -Dir $Context.records -Record $record
    # The pane inherits the environment of the spawn call (issue #95): every variable the harness owns
    # is removed from it, so nothing of the node's own engine settings reaches the session.
    $envMap = @{}
    # Assigned before it is listed: Get-HordeAgentProp hands a list back as one object.
    $owned = Get-HordeAgentProp $res.descriptor "ownedEnv"
    foreach ($o in @($owned)) { if ($null -ne $o) { $envMap["" + $o.name] = $null } }
    $pane = & $actor.start $prog.value @($plan.value.argv) $d.workdir $envMap
    if ($pane.state -ne "known") {
        $record.outcome = "failed"; Write-HordeNodeSpawnRecord -Dir $Context.records -Record $record
        return (New-HordeNodeOutcome -State "failed" -SessionId $sid -Reason ("the host did not start the session's pane: " + $pane.reason))
    }
    $record.handle = "" + $pane.value.handle
    Write-HordeNodeSpawnRecord -Dir $Context.records -Record $record
    $proc = Wait-HordeNodeUntil -Context $Context -Seconds $Context.bounds.identifySeconds -Probe {
        $i = & $adapter.identify $sid $Context.environment
        if ($i.state -ne "known") { return $null }
        $live = & $Context.processStart $i.value.pid
        if ($null -ne $live -and "" + $live -ceq "" + $i.value.procStart) { return $i.value }
        return $null
    }
    if ($null -eq $proc) {
        $null = Stop-HordeNodeSession -Context $Context -Actor $actor -Adapter $adapter -Handle $record.handle
        $record.outcome = "failed"; $record.closedAt = (& $Context.now).ToUniversalTime().ToString("o"); Write-HordeNodeSpawnRecord -Dir $Context.records -Record $record
        return (New-HordeNodeOutcome -State "failed" -SessionId $sid -Reason ("the harness never reported its process within " + $Context.bounds.identifySeconds + " s as one the process table shows with that start time; its pane was ended"))
    }
    $record.pid = [long]$proc.pid; $record.procStart = "" + $proc.procStart
    Write-HordeNodeSpawnRecord -Dir $Context.records -Record $record
    # 6. The mode, read back. Exactly the level asked for, or the session is not kept.
    $mode = Wait-HordeNodeUntil -Context $Context -Seconds $Context.bounds.modeSeconds -Probe { $m = & $adapter.readMode $sid $Context.environment; if ($m.state -eq "known") { $m } else { $null } }
    $why = ""
    if ($null -eq $mode) { $why = "the session's permission mode could not be read back within " + $Context.bounds.modeSeconds + " s, so it is not kept (fail closed)" }
    elseif ("" + $mode.value -cne $d.level) { $why = "the session reports the level " + $mode.value + " and was asked for " + $d.level + ", so it is not kept" }
    if ($why -ne "") {
        $gone = Stop-HordeNodeSession -Context $Context -Actor $actor -Adapter $adapter -Handle $record.handle -ProcessId $record.pid -ProcStart $record.procStart
        if (-not $gone) { $why += "; WARNING: it could not be proven ended" }
        $record.outcome = "refused"; $record.closedAt = (& $Context.now).ToUniversalTime().ToString("o"); Write-HordeNodeSpawnRecord -Dir $Context.records -Record $record
        return (New-HordeNodeOutcome -State "refused" -SessionId $sid -Reason $why)
    }
    $record.outcome = "running"; Write-HordeNodeSpawnRecord -Dir $Context.records -Record $record
    $expect = [pscustomobject][ordered]@{ ns = [pscustomobject][ordered]@{ device = "" + $Context.namespace.device; space = "" + $Context.namespace.space }; pid = [long]$record.pid; procStart = $record.procStart }
    return (New-HordeNodeOutcome -State "done" -SessionId $sid -Expect $expect)
}

function Invoke-HordeNodeClose {
    param([Parameter(Mandatory = $true)]$Act, [Parameter(Mandatory = $true)]$Context)
    $a = $Act.args
    $sid = "" + $a.sessionId
    $rec = Read-HordeNodeSpawnRecord -Dir $Context.records -SessionId $sid
    if ($rec.state -ne "known") { return (New-HordeNodeOutcome -State "refused" -SessionId $sid -Reason $rec.reason) }
    $r = $rec.value
    # The hub's expected process: on this device and space, and exactly the node's own view.
    $local = Test-HordeNamespaceLocal -Namespace $a.expect.ns -Local $Context.namespace
    if ($local.state -ne "known" -or -not $local.value) { return (New-HordeNodeOutcome -State "refused" -SessionId $sid -Reason ("the expected process is not this node's to look up: " + $local.reason)) }
    $mine = [pscustomobject]@{ ns = $Context.namespace; pid = $r.pid; procStart = "" + $r.procStart }
    $same = Test-HordeSameProcess -A $mine -B $a.expect
    if ($same.state -ne "known" -or -not $same.value) { return (New-HordeNodeOutcome -State "refused" -SessionId $sid -Reason ("the expected process (pid " + $a.expect.pid + ", start " + $a.expect.procStart + ") differs from this node's view of the session (pid " + $r.pid + ", start " + $r.procStart + "); nothing was done")) }
    if (Test-HordeNodeProcessGone -Context $Context -ProcessId ([long]$r.pid) -ProcStart ("" + $r.procStart)) {
        if ("" + $r.closedAt -eq "") { $r.closedAt = (& $Context.now).ToUniversalTime().ToString("o"); $r.outcome = "ended"; Write-HordeNodeSpawnRecord -Dir $Context.records -Record $r }
        return (New-HordeNodeOutcome -State "done" -SessionId $sid -Reason "the session had already ended: no process has its pid and start time")
    }
    $ac = Get-HordeNodeActor -Name ("" + $r.host)
    if ($ac.state -ne "known") { return (New-HordeNodeOutcome -State "failed" -SessionId $sid -Reason $ac.reason) }
    $ad = Get-HordeLaunchAdapter -Name ("" + $r.harness)
    if ($ad.state -ne "known") { return (New-HordeNodeOutcome -State "failed" -SessionId $sid -Reason $ad.reason) }
    foreach ($t in @($ad.value.closeText)) {
        $sent = & $ac.value.send ("" + $r.handle) $t
        if ($sent.state -ne "known") { return (New-HordeNodeOutcome -State "failed" -SessionId $sid -Reason ("the close text could not be typed into the session's pane: " + $sent.reason)) }
    }
    $gone = Wait-HordeNodeUntil -Context $Context -Seconds $Context.bounds.closeSeconds -Probe { if (Test-HordeNodeProcessGone -Context $Context -ProcessId ([long]$r.pid) -ProcStart ("" + $r.procStart)) { $true } else { $null } }
    if ($gone -ne $true) { return (New-HordeNodeOutcome -State "failed" -SessionId $sid -Reason ("the session is still running " + $Context.bounds.closeSeconds + " s after its close text; a close is graceful, so nothing was forced")) }
    $r.closedAt = (& $Context.now).ToUniversalTime().ToString("o"); $r.outcome = "closed"
    Write-HordeNodeSpawnRecord -Dir $Context.records -Record $r
    return (New-HordeNodeOutcome -State "done" -SessionId $sid)
}

function Get-HordeNodeEngineLayers {
    # The node's own engine layers: L0 from the harness folders, L1 from <HordeHome>\engine.json and L4
    # from <HordeHome>\engine-live.json when they exist - the names engines E6 and E7 will read and
    # write. Returns { layers; problems }: layers that fail the checker are left out, and each problem
    # is named, so a node with a broken file acts on the layers it can trust and says which it could not.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$HordeHome, $Descriptors)
    $docs = New-Object System.Collections.ArrayList
    foreach ($l in @(Get-HordeBuiltinLayer -Root $Root)) { [void]$docs.Add($l) }
    foreach ($pair in @(@("L1", "engine.json"), @("L4", "engine-live.json"))) {
        $path = Join-Path $HordeHome $pair[1]
        if (Test-Path -LiteralPath $path -PathType Leaf) { [void]$docs.Add((Read-HordeEngineLayerText -Text ([System.IO.File]::ReadAllText($path)) -Layer $pair[0] -Source $path)) }
    }
    $problems = New-Object System.Collections.ArrayList
    $findings = @(Test-HordeEngineConfig -Documents $docs.ToArray() -Descriptors $Descriptors | Where-Object { $_.severity -ceq "error" })
    foreach ($f in $findings) { [void]$problems.Add($f.source + " " + $f.path + ": " + $f.code + " - " + $f.detail) }
    $bad = @($findings | ForEach-Object { "" + $_.source } | Select-Object -Unique)
    $kept = @($docs | Where-Object { $bad -cnotcontains ("" + $_.source) })
    return [pscustomobject]@{ layers = $kept; problems = $problems.ToArray() }
}

function New-HordeNodeActContext {
    # What a node acts with, read once when it starts serving: its policy, its engine layers, the
    # harness descriptors, its namespace and its spawn records, the real clock and process table.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)]$Namespace)
    $all = Get-HordeAgentDescriptors -Root $Root
    $descriptors = @{}
    if ($all.state -eq "known") { $descriptors = $all.value }
    $policyPath = Get-HordeNodePolicyPath -HordeHome $HordeHome
    $policy = Get-HordeNodePolicy -Path $policyPath
    $eng = Get-HordeNodeEngineLayers -Root $Root -HordeHome $HordeHome -Descriptors $descriptors
    $note = "policy " + $policy.state + " (" + $policyPath + ")"
    if (@($eng.problems).Count -gt 0) { $note += "; engine layers left out: " + (@($eng.problems) -join " | ") }
    # The environment the harness will see is the one the spawn call passes on (issue #95): this
    # process's, less what the spawn removes. A harness finds its own files from it.
    $view = @{}
    foreach ($e in @([System.Environment]::GetEnvironmentVariables().GetEnumerator())) { $view["" + $e.Key] = "" + $e.Value }
    return [pscustomobject]@{
        policy = $policy; layers = @($eng.layers); descriptors = $descriptors; namespace = $Namespace
        records = (Get-HordeNodeSpawnDir -HordeHome $HordeHome); environment = $view; hostName = ""
        processStart = { param($p) Get-HordeLocalProcessStart -ProcessId $p }
        sleep = { param($ms) Start-Sleep -Milliseconds $ms }; now = { [datetime]::UtcNow }
        # MEASURED 2026-10-05 on 2.1.289 (an isolated terminal): the control file and the first
        # permission-mode line were written within 15 s of the spawn; the bounds give four times that.
        bounds = [pscustomobject]@{ identifySeconds = 60; modeSeconds = 60; closeSeconds = 20; pollMs = 500 }
        workdirExists = { param($p) Test-Path -LiteralPath $p -PathType Container }
        note = $note
    }
}

function Invoke-HordeNodeActRequest {
    # One act request, decided and done: { state; sessionId; expect; reason }. A throw inside is a
    # failed outcome with its reason: the journal must always get an outcome for what it recorded.
    param([Parameter(Mandatory = $true)]$Act, [Parameter(Mandatory = $true)]$Context)
    try {
        switch ("" + $Act.verb) {
            "session.spawn" { return (Invoke-HordeNodeSpawn -Act $Act -Context $Context) }
            "session.close" { return (Invoke-HordeNodeClose -Act $Act -Context $Context) }
        }
        return (New-HordeNodeOutcome -State "refused" -Reason ("this node does not act on " + $Act.verb))
    } catch {
        return (New-HordeNodeOutcome -State "failed" -Reason ("the node failed while acting: " + $_.Exception.Message))
    }
}
