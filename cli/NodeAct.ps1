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
#   -. no folder from the node's home down to its records is a junction or link (see THE COUNT), then
#      the spawn lock; then what the owner controls is READ AGAIN, under the lock, for this spawn -
#      policy.json, engine.json (L1) and engine-live.json (L4) - so a cap set to 0, a ceiling lowered
#      in engine-live.json or a deleted policy holds from the next spawn, with no restart (review of
#      #104, F1). Nothing the owner controls is kept from when serving started;
#   0. the node's engine layer files pass their checker: a file that fails refuses every spawn, never
#      dropped, because a dropped L1 or L4 would drop the owner's ceiling with it (review of #98, F1);
#   1. the node's policy and ceiling (core/NodePolicy.ps1), over the engine resolution of the node's
#      own layers plus the request compiled into the spawn layer (L5), and the day's count, taken under
#      the node's spawn lock (see THE COUNT);
#   2. a profile on the harness's own login only: a provider's key belongs to engines E10's launch
#      stub, so a profile that needs one is refused until it exists (decision of 2026-10-05);
#   3. the folder: the registered clone, or an existing worktree under its root - none is created;
#   4. the terminal: the host names this node's own, explicitly (Own), or the spawn is refused;
#   5. the launch plan (core/AgentLaunch.ps1), given the policy's decision and the host's program
#      lookup, so the program is an absolute .exe and the level is the one the policy allowed;
#   6. the pane, then the harness's own record of its process, believed only when the live process
#      has that pid AND that start time (to the microsecond both clocks keep);
#   7. the mode the session reports (issue #67, decision 6): exactly the level asked for, or the
#      session is closed - its close text, then the host's end of the pane, which the host does only
#      once the process is proven in it - and the spawn refused. Unreadable within the bound: the same.
#      A session that cannot be ended either is NOT refused: it is failed, recorded as still running
#      (outcome unkept-running, no closedAt), its process returned so the hub can close it again, and
#      an ALERT line raised (review of #104, F2);
#      Before the readback one fixed line that asks for nothing, "Reply with OK only.", is typed and
#      submitted, so the harness writes its record of the mode (see $script:HordeNodeNoOpLine);
#   8. only now the work: the session starts with NO prompt, so a session in the wrong mode is closed
#      before it ever sees work (review of #104, F4: prevent, not detect). The prompt is typed as one
#      line and submitted; a prompt holding a line break or any other control character, or too long
#      to type, is written to <records>\<sessionId>.prompt.txt and the session is told in one typed
#      line to read it - the text itself is never typed raw.
# A pane whose harness never reports its process cannot be proven, so the host will not end it; the
# spawn fails, and the record names the pane left open for a person.
#
# A SPAWN HOLDS THE SERVE LOOP. The serve loop is single-threaded, and a spawn waits for its process
# (identifySeconds), its mode (modeSeconds) and, when it is not kept, its close and the host's end
# (closeSeconds each): up to about 160 s at the default bounds. Pings and reads on other links are not
# answered meanwhile, so a hub must wait at least that long before judging the node gone (review of
# #104, F7). Acting asynchronously is later work.
#
# AT SERVE START (Invoke-HordeNodeReconcile, review of #104, F5) every record a stopped node left
# "starting" is settled: its process is looked for by pid and start time - from the record, or from the
# harness's own record of the session - and the record is marked running (with an ALERT: its mode was
# never read back) or failed. None is left as it was.
#
# THE COUNT behind the daily cap is the node's records of what it started, by UTC day: every record
# whose start is at or after today's UTC midnight - a record dated in the future (the clock was set
# back) counts too, so moving the clock never frees the cap - and every record that cannot be read. The
# count and the new record are taken under one lock file opened with FileShare None, so two acts can
# never both see room for one. A junction or a symbolic link anywhere from the node's home down to the
# records folder refuses every spawn, checked before anything is created there: the count would be
# another folder's (review of #104, F6).
#
# A CLOSE is graceful only. The node refuses unless it started that session FOR THE HUB ASKING - the
# record keeps the spawning hub's device id, and a close from another hub is refused (review of #104,
# F8) - the hub's expected
# process is on this device and space (R11) and is exactly the node's own view, pid and start time;
# then it types the harness's close text and waits. A process gone by pid and start time is done; one
# still running is failed, and nothing is forced.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
$script:HordeNodeActCore = Split-Path -Parent $PSScriptRoot
foreach ($f in @("Tristate", "Namespace", "NodePolicy", "EngineResolve", "AgentLaunch", "HostAct")) { . (Join-Path $script:HordeNodeActCore ("core\" + $f + ".ps1")) }
$script:HordeNodeSpawnLockName = ".spawn.lock"
# The longest prompt typed into a pane as one line. The host types at most 1024 characters a call
# (hosts/<name>/Act.ps1); a longer prompt goes to a file the session is told to read.
$script:HordeNodePromptTypedMax = 1000
# The line typed before the mode is read back. A harness may keep its transcript in memory until the
# first user turn: MEASURED 2026-10-06, read-only over 279 transcripts of the founder's harness
# (versions 2.1.228 to 2.1.285), the file was created with the first user line in 192 of 199, lines timestamped up to 21
# minutes earlier written with it, so a session started with no prompt has no permission-mode line
# on disk to read. One turn that asks for nothing makes it write one. A constant, never from the link;
# its cost is one model turn, and its window is that one turn, before the mode is proven (decision of
# 2026-10-06; a local command that forces the write without a model turn is to be measured live).
$script:HordeNodeNoOpLine = "Reply with OK only."

function Get-HordeNodeSpawnDir {
    # Where a node keeps its records of the sessions it started for a hub.
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    return (Join-Path (Join-Path $HordeHome "node") "spawned")
}

function Test-HordeNodeReparse {
    # Is -Path a junction or symbolic link? A missing path is not.
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    return [bool](((Get-Item -LiteralPath $Path -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Test-HordeNodeRecordsChain {
    # "" when no folder from -HordeHome down to -Dir is a junction or symbolic link, else the refusal.
    # Every segment is checked, the home itself included, before anything is created under it (review
    # of #104, F6: a junction at <home>\node passed while only the records folder itself was checked).
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$Dir)
    $sep = [System.IO.Path]::DirectorySeparatorChar
    $base = [System.IO.Path]::GetFullPath($HordeHome).TrimEnd($sep)
    $full = [System.IO.Path]::GetFullPath($Dir).TrimEnd($sep)
    if (-not $full.StartsWith($base + $sep, [System.StringComparison]::OrdinalIgnoreCase)) { return ("the records folder " + $Dir + " is not inside this node's home " + $HordeHome) }
    $p = $base
    if (Test-HordeNodeReparse -Path $p) { return ("the folder " + $p + ", on the way to the records, is a junction or link, so what it holds is another folder's") }
    foreach ($seg in $full.Substring($base.Length + 1).Split($sep)) {
        $p = Join-Path $p $seg
        if (Test-HordeNodeReparse -Path $p) { return ("the folder " + $p + ", on the way to the records, is a junction or link, so what it holds is another folder's") }
    }
    return ""
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
    # How many sessions this node started for a hub on the UTC day of -Now, as an answer (see THE COUNT
    # in the header). Unknown when the folder is a junction or link: then the count is another folder's.
    param([Parameter(Mandatory = $true)][string]$Dir, [Parameter(Mandatory = $true)][datetime]$Now)
    # THE CLOCK IS UTC. A time of another kind is refused rather than converted, so no caller can count
    # by a local day (the gate's local-day mutant survived while a local time was quietly converted).
    if ($Now.Kind -ne [System.DateTimeKind]::Utc) { return (New-HordeUnknown -Reason "the daily count needs the clock in UTC; a local or unspecified time is refused") }
    if (Test-HordeNodeReparse -Path $Dir) { return (New-HordeUnknown -Reason ("the records folder " + $Dir + " is a junction or link, so what it counts is another folder's")) }
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { return (New-HordeKnown -Value 0) }
    $midnight = [datetime]::SpecifyKind($Now.Date, [System.DateTimeKind]::Utc)
    $n = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Filter "*.json" -File -Force)) {
        if ($f.Name.StartsWith(".")) { continue }
        if (($f.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { $n++; continue }
        $r = $null
        try { $r = [System.IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json } catch { $n++; continue }
        $t = [datetime]::MinValue
        $ok = [datetime]::TryParse("" + $r.startedAt, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$t)
        # An unreadable start counts: the cap is never raised by a torn file. A start at or after today's
        # UTC midnight counts, and so does one in the future: setting the clock back frees nothing.
        if (-not $ok -or $t -ge $midnight) { $n++ }
    }
    return (New-HordeKnown -Value $n)
}

function Enter-HordeNodeSpawnLock {
    # The node's spawn lock: a file opened with FileShare None, held until disposed, so the count and
    # the new record are one step (see THE COUNT). Returns the stream, or $null when another act holds it.
    param([Parameter(Mandatory = $true)][string]$Dir)
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }
    try { return [System.IO.File]::Open((Join-Path $Dir $script:HordeNodeSpawnLockName), [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None) }
    catch { return $null }
}

function Get-HordeLocalProcessStart {
    # A live process's start time as FILETIME ticks (UTC) in text, or $null when no process has that pid.
    param([Parameter(Mandatory = $true)][long]$ProcessId)
    $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($null -eq $p) { return $null }
    try { return ("" + $p.StartTime.ToUniversalTime().ToFileTimeUtc()) } catch { return $null }
}

function Test-HordeNodeSameStart {
    # Two start times (FILETIME ticks as text) naming one instant to the microsecond: the precision the
    # process table and Get-Process share (measured 2026-10-06, #96). Unreadable is never the same.
    param($A, $B)
    $x = [decimal]0; $y = [decimal]0
    if (-not [decimal]::TryParse("" + $A, [ref]$x) -or -not [decimal]::TryParse("" + $B, [ref]$y)) { return $false }
    return [bool]([decimal]::Floor($x / 10) -eq [decimal]::Floor($y / 10))
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
    return [bool]($null -eq $live -or -not (Test-HordeNodeSameStart $live $ProcStart))
}

function Send-HordeNodeCloseText {
    # Type a harness's close text into its pane: each item typed, and a lone CR pressed as Enter
    # (-Submit), since the host types printable text only (review of #96).
    param([Parameter(Mandatory = $true)]$Actor, [Parameter(Mandatory = $true)]$Target, [Parameter(Mandatory = $true)][string]$Handle, [Parameter(Mandatory = $true)]$Adapter)
    foreach ($t in @($Adapter.closeText)) {
        $r = $null
        if ("" + $t -ceq "`r") { $r = & $Actor.send $Target $Handle "" $true } else { $r = & $Actor.send $Target $Handle ("" + $t) $false }
        if ($null -eq $r -or $r.state -ne "known") { return $r }
    }
    return (New-HordeKnown -Value $true)
}

function Send-HordeNodePrompt {
    # Deliver a session's first prompt once its mode is proven (step 8): "" when it is typed and
    # submitted, else why not. Printable text is typed as one line with Enter (-Submit). A prompt
    # holding any control character - a line break included - or longer than the typed maximum is
    # written to <records>\<sessionId>.prompt.txt, and the session is told, in one typed line, to read
    # that file: the text itself is never typed raw.
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)]$Actor, [Parameter(Mandatory = $true)]$Target,
        [Parameter(Mandatory = $true)][string]$Handle, [Parameter(Mandatory = $true)][string]$SessionId, [AllowEmptyString()][string]$Prompt = "")
    if ($Prompt -eq "") { return "" }
    $line = $Prompt
    if ($Prompt -cmatch '[\x00-\x1F\x7F-\x9F]' -or $Prompt.Length -gt $script:HordeNodePromptTypedMax) {
        $file = Join-Path $Context.records ($SessionId + ".prompt.txt")
        try { [System.IO.File]::WriteAllText($file, $Prompt, (New-Object System.Text.UTF8Encoding($false))) }
        catch { return ("the prompt could not be written for the session to read: " + $_.Exception.Message) }
        $line = "Read the file " + $file + " and do what it says."
    }
    $r = & $Actor.send $Target $Handle $line $true
    if ($null -eq $r -or $r.state -ne "known") { return ("the prompt could not be typed into the session's pane: " + $(if ($null -ne $r) { $r.reason } else { "the host gave no answer" })) }
    return ""
}

function Stop-HordeNodeSession {
    # End a session this node just started and will not keep: its close text, then - only for a process
    # proven by pid and start time - the host's end of its pane. Returns whether the process is gone.
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)]$Actor, [Parameter(Mandatory = $true)]$Target, [Parameter(Mandatory = $true)]$Adapter,
        [Parameter(Mandatory = $true)][string]$Handle, [Parameter(Mandatory = $true)][long]$ProcessId, [Parameter(Mandatory = $true)][string]$ProcStart)
    $null = Send-HordeNodeCloseText -Actor $Actor -Target $Target -Handle $Handle -Adapter $Adapter
    $gone = Wait-HordeNodeUntil -Context $Context -Seconds $Context.bounds.closeSeconds -Probe { if (Test-HordeNodeProcessGone -Context $Context -ProcessId $ProcessId -ProcStart $ProcStart) { $true } else { $null } }
    if ($gone -eq $true) { return $true }
    $null = & $Actor.stop $Target $Handle ([pscustomobject]@{ pid = $ProcessId; procStart = $ProcStart })
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
    # The hub that asks is the only one that may close what starts (review of #104, F8).
    $hubId = "" + $Act.hubId
    if ($hubId -eq "") { return (New-HordeNodeOutcome -State "refused" -Reason "the request names no hub, so no hub could close the session; nothing is started") }
    # The way to the records, before anything is created there (see THE COUNT).
    $chain = Test-HordeNodeRecordsChain -HordeHome $Context.home -Dir $Context.records
    if ($chain -ne "") { return (New-HordeNodeOutcome -State "refused" -Reason $chain) }
    $lock = Enter-HordeNodeSpawnLock -Dir $Context.records
    if ($null -eq $lock) { return (New-HordeNodeOutcome -State "refused" -Reason "another spawn on this node holds its spawn lock; the cap is never counted by two at once") }
    try {
        # What the owner controls, read again for this spawn, under the lock (review of #104, F1).
        $cfg = $null
        try { $cfg = & $Context.readConfig $Context }
        catch { return (New-HordeNodeOutcome -State "refused" -Reason ("this node's policy and engine configuration could not be read, so it starts nothing: " + $_.Exception.Message)) }
        # 0. The node's own layer files must all pass: one that fails could carry the owner's ceiling.
        $bad = @(@($cfg.problems) | Where-Object { "" + $_ -ne "" })
        if ($bad.Count -gt 0) { return (New-HordeNodeOutcome -State "refused" -Reason ("this node's engine configuration fails its checks, so it starts nothing until it is fixed: " + ($bad -join " | "))) }
        # 1. The request as the spawn layer, then the node's policy and ceiling over the resolution.
        $set = [ordered]@{ profile = "" + $a.profile }
        if ($null -ne $a.PSObject.Properties["model"] -and "" + $a.model -ne "") { $set["model"] = "" + $a.model }
        if ($null -ne $a.PSObject.Properties["permission"] -and "" + $a.permission -ne "") { $set["permission"] = "" + $a.permission }
        $l5 = [pscustomobject]@{ layer = "L5"; source = ("spawn request " + $Act.requestId); doc = [pscustomobject]@{ schemaVersion = 1; rules = @([pscustomobject]@{ id = "spawn"; match = [pscustomobject]@{}; set = [pscustomobject]$set; writtenBy = "cli" }) } }
        $layers = @($cfg.layers) + @($l5)
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
        if ($today.state -ne "known") { return (New-HordeNodeOutcome -State "refused" -Reason $today.reason) }
        $d = Test-HordeRemotePolicy -Policy $cfg.policy -Resolution $res -Request $req -SpawnsToday $today.value
        if (-not $d.allowed) { return (New-HordeNodeOutcome -State "refused" -Reason (@($d.reasons) -join "; ")) }
        # 2. Own login only.
        if (-not (Test-HordeNodeOwnLogin -Layers $layers -Provider ("" + $res.binding.value.provider))) { return (New-HordeNodeOutcome -State "refused" -Reason ("the provider " + $res.binding.value.provider + " needs a key, which only engines E10's launch stub may hand a session; until it exists only a profile on the harness's own login is started remotely")) }
        # 3. The folder.
        if (-not (& $Context.workdirExists $d.workdir)) { return (New-HordeNodeOutcome -State "refused" -Reason ("the folder " + $d.workdir + " does not exist; this version starts sessions only in existing folders and creates no worktree")) }
        # 4. The host and this node's own terminal, named.
        $hostName = "" + $Context.hostName
        if ($null -ne $a.PSObject.Properties["host"] -and "" + $a.host -ne "") { $hostName = "" + $a.host }
        $ac = Get-HordeNodeActor -Name $hostName
        if ($ac.state -ne "known") { return (New-HordeNodeOutcome -State "refused" -Reason $ac.reason) }
        $actor = $ac.value
        $tg = & $actor.own
        if ($null -eq $tg -or $tg.state -ne "known") { return (New-HordeNodeOutcome -State "refused" -Reason ("this node cannot name its own terminal: " + $(if ($null -ne $tg) { $tg.reason } else { "the host gave no answer" }))) }
        $term = $tg.value
        # 5. The plan: the policy's decision, and the host's lookup of an absolute .exe.
        $sid = [guid]::NewGuid().ToString()
        $title = $null
        if ($null -ne $a.PSObject.Properties["title"]) { $title = "" + $a.title }
        $name = Format-HordeSessionName -Label ("" + $a.label) -Title $title
        $prompt = ""
        if ($null -ne $a.prompt.PSObject.Properties["text"]) { $prompt = "" + $a.prompt.text }
        $resolveProgram = { param($n) & $actor.resolve $n }
        # No prompt in the argv: the work is delivered only once the mode is proven (step 8).
        $plan = New-HordeLaunchPlan -Resolution $res -Decision $d -SessionId $sid -Name $name -Prompt "" -Resolve $resolveProgram
        if ($plan.state -ne "known") { return (New-HordeNodeOutcome -State "refused" -Reason $plan.reason) }
        $adapter = (Get-HordeLaunchAdapter -Name $plan.value.harness).value
        # 6. The pane, recorded before it starts, under the lock, so the count already holds it.
        $record = [ordered]@{ sessionId = $sid; requestId = "" + $Act.requestId; hubId = $hubId; host = $actor.name; harness = $plan.value.harness; handle = ""; level = $d.level; name = $plan.value.name; workdir = $d.workdir; label = "" + $a.label; startedAt = (& $Context.now).ToUniversalTime().ToString("o"); pid = $null; procStart = ""; noOp = ""; noOpAt = ""; closedAt = ""; outcome = "starting" }
        Write-HordeNodeSpawnRecord -Dir $Context.records -Record $record
    } finally { $lock.Dispose() }
    # The pane inherits the environment of the spawn call (issue #95): every variable the harness owns
    # is removed from it, so nothing of the node's own engine settings reaches the session.
    $envMap = @{}
    $owned = Get-HordeAgentProp $res.descriptor "ownedEnv"
    foreach ($o in @($owned)) { if ($null -ne $o) { $envMap["" + $o.name] = $null } }
    $pane = & $actor.start $term $plan.value.program @($plan.value.argv) $d.workdir $envMap
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
        if ($null -ne $live -and (Test-HordeNodeSameStart $live $i.value.procStart)) { return $i.value }
        return $null
    }
    if ($null -eq $proc) {
        # Not proven, so not ended: the host ends a pane only for a process proven in it. Its close text
        # is typed, and the record names the pane for a person.
        $null = Send-HordeNodeCloseText -Actor $actor -Target $term -Handle $record.handle -Adapter $adapter
        $record.outcome = "unproven"; Write-HordeNodeSpawnRecord -Dir $Context.records -Record $record
        return (New-HordeNodeOutcome -State "failed" -SessionId $sid -Reason ("the harness never reported its process within " + $Context.bounds.identifySeconds + " s as one the process table shows with that start time; its close text was typed, and its pane " + $record.handle + " is left for a person, since a pane is ended only for a proven process"))
    }
    $record.pid = [long]$proc.pid; $record.procStart = "" + $proc.procStart
    Write-HordeNodeSpawnRecord -Dir $Context.records -Record $record
    # 7. The mode, read back. Exactly the level asked for, or the session is not kept. First the fixed
    # line that asks for nothing, so the harness writes the record the mode is read from.
    $noop = & $actor.send $term $record.handle $script:HordeNodeNoOpLine $true
    $record.noOp = $script:HordeNodeNoOpLine; $record.noOpAt = (& $Context.now).ToUniversalTime().ToString("o")
    if ($null -eq $noop -or $noop.state -ne "known") { $record.noOp = ""; $record.noOpAt = "" }
    Write-HordeNodeSpawnRecord -Dir $Context.records -Record $record
    $mode = $null
    if ($null -ne $noop -and $noop.state -eq "known") {
        $mode = Wait-HordeNodeUntil -Context $Context -Seconds $Context.bounds.modeSeconds -Probe { $m = & $adapter.readMode $sid $Context.environment; if ($m.state -eq "known") { $m } else { $null } }
    }
    $why = ""
    if ($null -eq $mode) { $why = "the session's permission mode could not be read back within " + $Context.bounds.modeSeconds + " s, so it is not kept (fail closed)" }
    elseif ("" + $mode.value -cne $d.level) { $why = "the session reports the level " + $mode.value + " and was asked for " + $d.level + ", so it is not kept" }
    $expect = [pscustomobject][ordered]@{ ns = [pscustomobject][ordered]@{ device = "" + $Context.namespace.device; space = "" + $Context.namespace.space }; pid = [long]$record.pid; procStart = $record.procStart }
    if ($why -ne "") {
        $gone = Stop-HordeNodeSession -Context $Context -Actor $actor -Target $term -Adapter $adapter -Handle $record.handle -ProcessId $record.pid -ProcStart $record.procStart
        if (-not $gone) {
            # Still running, at a level nobody asked for: never reported as refused or recorded as closed
            # (review of #104, F2). The hub gets the process to close it by, and a person gets an alert.
            $record.outcome = "unkept-running"; Write-HordeNodeSpawnRecord -Dir $Context.records -Record $record
            & $Context.alert ("ALERT: session " + $sid + " (pane " + $record.handle + ", pid " + $record.pid + ") is still running and could not be ended: " + $why)
            return (New-HordeNodeOutcome -State "failed" -SessionId $sid -Expect $expect -Reason ($why + "; it could NOT be ended and is still running: close it again with this process, or end pane " + $record.handle + " by hand"))
        }
        $record.outcome = "refused"; $record.closedAt = (& $Context.now).ToUniversalTime().ToString("o"); Write-HordeNodeSpawnRecord -Dir $Context.records -Record $record
        return (New-HordeNodeOutcome -State "refused" -SessionId $sid -Reason $why)
    }
    # 8. The work, now that the mode is proven.
    $notSent = Send-HordeNodePrompt -Context $Context -Actor $actor -Target $term -Handle $record.handle -SessionId $sid -Prompt $prompt
    if ($notSent -ne "") {
        $record.outcome = "running-no-prompt"; Write-HordeNodeSpawnRecord -Dir $Context.records -Record $record
        return (New-HordeNodeOutcome -State "failed" -SessionId $sid -Expect $expect -Reason ($notSent + "; the session runs at the level asked for, without its work: close it with this process"))
    }
    $record.outcome = "running"; Write-HordeNodeSpawnRecord -Dir $Context.records -Record $record
    return (New-HordeNodeOutcome -State "done" -SessionId $sid -Expect $expect)
}

function Invoke-HordeNodeClose {
    param([Parameter(Mandatory = $true)]$Act, [Parameter(Mandatory = $true)]$Context)
    $a = $Act.args
    $sid = "" + $a.sessionId
    $rec = Read-HordeNodeSpawnRecord -Dir $Context.records -SessionId $sid
    if ($rec.state -ne "known") { return (New-HordeNodeOutcome -State "refused" -SessionId $sid -Reason $rec.reason) }
    $r = $rec.value
    # Only the hub that asked for the session may close it (review of #104, F8).
    if ("" + $r.hubId -eq "" -or "" + $r.hubId -cne "" + $Act.hubId) { return (New-HordeNodeOutcome -State "refused" -SessionId $sid -Reason ("the session was started for the hub " + $r.hubId + ", and a close from the hub " + $Act.hubId + " is refused; nothing was done")) }
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
    $tg = & $ac.value.own
    if ($null -eq $tg -or $tg.state -ne "known") { return (New-HordeNodeOutcome -State "failed" -SessionId $sid -Reason ("this node cannot name its own terminal: " + $(if ($null -ne $tg) { $tg.reason } else { "the host gave no answer" }))) }
    $sent = Send-HordeNodeCloseText -Actor $ac.value -Target $tg.value -Handle ("" + $r.handle) -Adapter $ad.value
    if ($null -eq $sent -or $sent.state -ne "known") { return (New-HordeNodeOutcome -State "failed" -SessionId $sid -Reason ("the close text could not be typed into the session's pane: " + $(if ($null -ne $sent) { $sent.reason } else { "no answer" }))) }
    $gone = Wait-HordeNodeUntil -Context $Context -Seconds $Context.bounds.closeSeconds -Probe { if (Test-HordeNodeProcessGone -Context $Context -ProcessId ([long]$r.pid) -ProcStart ("" + $r.procStart)) { $true } else { $null } }
    if ($gone -ne $true) { return (New-HordeNodeOutcome -State "failed" -SessionId $sid -Reason ("the session is still running " + $Context.bounds.closeSeconds + " s after its close text; a close is graceful, so nothing was forced")) }
    $r.closedAt = (& $Context.now).ToUniversalTime().ToString("o"); $r.outcome = "closed"
    Write-HordeNodeSpawnRecord -Dir $Context.records -Record $r
    return (New-HordeNodeOutcome -State "done" -SessionId $sid)
}

function Get-HordeNodeEngineLayers {
    # The node's own engine layers: L0 from the harness folders, L1 from <HordeHome>\engine.json and L4
    # from <HordeHome>\engine-live.json when they exist - the names engines E6 and E7 inherit. Returns
    # { layers; problems }. Every problem refuses every spawn (step 0): a file that fails is never
    # dropped and acted on without it. -Builtin: L0 already read (shipped code, which changes only with
    # a restart); without it L0 is read from -Root.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$HordeHome, $Descriptors, $Builtin = $null)
    $docs = New-Object System.Collections.ArrayList
    if ($null -eq $Builtin) { $Builtin = @(Get-HordeBuiltinLayer -Root $Root) }
    foreach ($l in @($Builtin)) { [void]$docs.Add($l) }
    $problems = New-Object System.Collections.ArrayList
    foreach ($pair in @(@("L1", "engine.json"), @("L4", "engine-live.json"))) {
        $path = Join-Path $HordeHome $pair[1]
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        try { [void]$docs.Add((Read-HordeEngineLayerText -Text ([System.IO.File]::ReadAllText($path)) -Layer $pair[0] -Source $path)) }
        catch { [void]$problems.Add($path + ": not JSON") }
    }
    $findings = @(Test-HordeEngineConfig -Documents $docs.ToArray() -Descriptors $Descriptors | Where-Object { $_.severity -ceq "error" })
    foreach ($f in $findings) { [void]$problems.Add($f.source + " " + $f.path + ": " + $f.code + " - " + $f.detail) }
    return [pscustomobject]@{ layers = $docs.ToArray(); problems = $problems.ToArray() }
}

function Read-HordeNodeActConfig {
    # What the node's owner controls, read now: { policy; layers; problems }. A spawn calls it under the
    # spawn lock (review of #104, F1), so nothing the owner changes waits for a restart.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$HordeHome, $Descriptors, $Builtin = $null)
    $policy = Get-HordeNodePolicy -Path (Get-HordeNodePolicyPath -HordeHome $HordeHome)
    $eng = Get-HordeNodeEngineLayers -Root $Root -HordeHome $HordeHome -Descriptors $Descriptors -Builtin $Builtin
    return [pscustomobject]@{ policy = $policy; layers = @($eng.layers); problems = @($eng.problems) }
}

function New-HordeNodeActContext {
    # What a node acts with: the harness descriptors and the shipped L0 layer (code, which changes only
    # with a restart), its namespace, home and spawn records, the real clock and process table - and
    # readConfig, which each spawn calls for the policy and the owner's layers, read fresh (review of
    # #104, F1). note says what the configuration is as serving starts.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)]$Namespace)
    $all = Get-HordeAgentDescriptors -Root $Root
    $descriptors = @{}
    if ($all.state -eq "known") { $descriptors = $all.value }
    $builtin = @(Get-HordeBuiltinLayer -Root $Root)
    $policyPath = Get-HordeNodePolicyPath -HordeHome $HordeHome
    $now = Read-HordeNodeActConfig -Root $Root -HordeHome $HordeHome -Descriptors $descriptors -Builtin $builtin
    $note = "policy " + $now.policy.state + " (" + $policyPath + ")"
    if ($now.policy.state -ne "known") { $note = "acts: OFF until a policy is readable (" + $policyPath + ": " + $now.policy.state + $(if ("" + $now.policy.reason -ne "") { ", " + $now.policy.reason } elseif ("" + $now.policy.note -ne "") { ", " + $now.policy.note } else { "" }) + "); it is read again at every spawn" }
    if (@($now.problems).Count -gt 0) { $note += "; ENGINE CONFIGURATION FAILS ITS CHECKS, every spawn is refused: " + (@($now.problems) -join " | ") }
    # The environment the harness will see is the one the spawn call passes on (issue #95): this
    # process's, less what the spawn removes. A harness finds its own files from it.
    $view = @{}
    foreach ($e in @([System.Environment]::GetEnvironmentVariables().GetEnumerator())) { $view["" + $e.Key] = "" + $e.Value }
    return [pscustomobject]@{
        root = $Root; home = $HordeHome; builtin = $builtin; descriptors = $descriptors; namespace = $Namespace
        readConfig = { param($c) Read-HordeNodeActConfig -Root $c.root -HordeHome $c.home -Descriptors $c.descriptors -Builtin $c.builtin }
        records = (Get-HordeNodeSpawnDir -HordeHome $HordeHome); environment = $view; hostName = ""
        processStart = { param($p) Get-HordeLocalProcessStart -ProcessId $p }
        sleep = { param($ms) Start-Sleep -Milliseconds $ms }; now = { [datetime]::UtcNow }
        alert = { param($m) Write-Host $m -ForegroundColor Red }
        # MEASURED 2026-10-05 on 2.1.289 (an isolated terminal): the control file and the first
        # permission-mode line were written within 15 s of the spawn; the bounds give four times that.
        bounds = [pscustomobject]@{ identifySeconds = 60; modeSeconds = 60; closeSeconds = 20; pollMs = 500 }
        workdirExists = { param($p) Test-Path -LiteralPath $p -PathType Container }
        note = $note
    }
}

function Invoke-HordeNodeReconcile {
    # At serve start: settle every record a stopped node left "starting" (review of #104, F5). Its
    # process is looked for by pid and start time - the record's, or, when the node stopped before it
    # was proven, the harness's own record of the session, believed only when the live process has that
    # start time - and the record is marked running, with an ALERT (its mode was never read back), or
    # failed. Returns one line per record settled, for the serve log.
    param([Parameter(Mandatory = $true)]$Context)
    $lines = New-Object System.Collections.ArrayList
    $dir = $Context.records
    $chain = Test-HordeNodeRecordsChain -HordeHome $Context.home -Dir $dir
    if ($chain -ne "") { [void]$lines.Add("ALERT: the spawn records were not reconciled: " + $chain); return $lines.ToArray() }
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return $lines.ToArray() }
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter "*.json" -File)) {
        if ($f.Name.StartsWith(".")) { continue }
        $r = $null
        try { $r = [System.IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json } catch { [void]$lines.Add("ALERT: the spawn record " + $f.Name + " cannot be read, so it was not reconciled"); continue }
        if ("" + $r.outcome -cne "starting") { continue }
        $sid = "" + $r.sessionId
        $pidv = $null; $ps = ""
        if ($null -ne $r.pid -and "" + $r.pid -ne "") { $pidv = [long]$r.pid; $ps = "" + $r.procStart }
        else {
            $ad = Get-HordeLaunchAdapter -Name ("" + $r.harness)
            if ($ad.state -eq "known") {
                $i = & $ad.value.identify $sid $Context.environment
                if ($null -ne $i -and $i.state -eq "known") {
                    $live = & $Context.processStart $i.value.pid
                    if ($null -ne $live -and (Test-HordeNodeSameStart $live $i.value.procStart)) { $pidv = [long]$i.value.pid; $ps = "" + $i.value.procStart }
                }
            }
        }
        $at = (& $Context.now).ToUniversalTime().ToString("o")
        if ($null -ne $pidv -and -not (Test-HordeNodeProcessGone -Context $Context -ProcessId $pidv -ProcStart $ps)) {
            $r.pid = $pidv; $r.procStart = $ps; $r.outcome = "running"
            $r | Add-Member -NotePropertyName reconciled -NotePropertyValue ("found running at serve start, " + $at + ", after the node stopped mid-spawn; its permission mode was never read back") -Force
            Write-HordeNodeSpawnRecord -Dir $dir -Record $r
            $msg = "ALERT: session " + $sid + " (pane " + $r.handle + ", pid " + $pidv + ") was left starting by a stopped node and is running; its permission mode was never read back"
            & $Context.alert $msg
            [void]$lines.Add($msg)
        } else {
            $r.outcome = "failed"; $r.closedAt = $at
            $r | Add-Member -NotePropertyName reconciled -NotePropertyValue ("settled at serve start, " + $at + ": the node stopped mid-spawn and no process with this session's pid and start time runs") -Force
            Write-HordeNodeSpawnRecord -Dir $dir -Record $r
            [void]$lines.Add("session " + $sid + " was left starting by a stopped node and is not running: recorded failed")
        }
    }
    return $lines.ToArray()
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
