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
#      has that pid AND that start time (to the microsecond both clocks keep); then, before anything is
#      typed, the session READY for keys - its input box drawn and nothing running, as the harness's
#      adapter reads the host's screen (Wait-HordeNodeReady). Never ready within readySeconds: the spawn
#      fails not-ready with nothing typed, and the session is kept only when its mode record already
#      reads the level asked for; otherwise the host ends it by its process, with no close text
#      (Complete-HordeNodeNotReady; review of PR 239, S-d). A kind that cannot tell goes on, and the
#      turn receipt below still decides. Every not-ready end - never ready, too near the limit for the
#      no-op line, or the no-op's turn never ended - kept or ended, first captures the pane's screen
#      into the spawn record (see THE SCREEN OF A SESSION THAT WAS NOT READY);
#   7. the mode the session reports (issue #67, decision 6): exactly the level asked for, or the
#      session is closed - its close text, then the host's end of the pane, which the host does only
#      once the process is proven in it - and the spawn refused. Unreadable within the bound: the same.
#      A session that cannot be ended either is NOT refused: it is failed, recorded as still running
#      (outcome unkept-running, no closedAt), its process returned so the hub can close it again, and
#      an ALERT line raised (review of #104, F2);
#      Before the readback one fixed line that asks for nothing, "Reply with OK only.", is typed and
#      submitted, so the harness writes its record of the mode (see $script:HordeNodeNoOpLine), and its
#      turn is waited for to END (Wait-HordeNodeTurnEnd): a line typed while it runs would be queued,
#      not a turn (review of PR 239, M1). A no-op line not proven a turn gets no close text: it could be
#      typed after the stuck line (S1);
#   8. only now the work: the session starts with NO prompt, so a session in the wrong mode is closed
#      before it ever sees work (review of #104, F4: prevent, not detect). The prompt is written to
#      <records>\<sessionId>\prompt.txt - a folder only this user may open, granted to the session
#      at launch - and the one line typed is "Read <that file> and do what it says." The hub's text
#      is never typed (F9).
# A pane whose harness never reports its process cannot be proven, so the host will not end it; the
# spawn fails, and the record names the pane left open for a person.
#
# A SPAWN HOLDS THE SERVE LOOP. The serve loop is single-threaded, and a spawn waits for its process
# (identifySeconds), the session ready for keys (readySeconds), the no-op line's turn (receiptSeconds,
# then retrySeconds after the one extra Enter a line may get) and its end (turnEndSeconds), its mode
# (modeSeconds), then the prompt line's turn (the same two) or, when it is not kept, its close and the
# host's end (closeSeconds each). Every wait is measured on the context's clock, by wall time, not by
# counting polls - a single look at a pane can take up to the host's own call timeout (review of PR 239,
# S3) - and everything before the decision shares ONE limit, spawnSeconds from the act's start. The rules
# that hold it (review of PR 239, S-a and S-b, and F's re-check of round 3):
#   - once it has run out no host call STARTS: no look at the screen, no extra Enter, no screen capture;
#   - a line is typed only while its own waits, receiptSeconds + retrySeconds (L), fit before it;
#   - ONCE A LINE IS TYPED its receipt and retry waits run whole, past the limit if need be: they read
#     only the harness's transcript, and a wait cut short judged a line on one look, 0.2 s to 0.5 s
#     before its turn could be written - the double run of issue #214 on a slow host (F's probe: the
#     extra Enter sent at 60 s, the limit at 70.5 s, the turn at 80.3 s, its one look at 80.0 s);
#   - the close text is typed only while it, and the close wait after it, fit before the limit; else
#     the host ends the pane by its process.
# THE SUM COUNTS TERMINAL CALLS, not port calls, each at its timeout c (hostCallSeconds: 20 s, the first
# host's own call timeout - the port declares none). The first host makes TWO terminal calls for a typed
# line with its Enter (text, 250 ms, Enter) and two for its end of a pane (list, then end), one for any
# other call. The longest tail after the limit is a no-op line typed just inside its L: its send
# (2c + 0.25) and receipt wait run to 2c + 0.25 + receiptSeconds - L = 30.25 s past the limit (an extra
# Enter just inside the limit, c + retrySeconds = 30 s, is less), then the host's end (2c) and its wait
# (closeSeconds): 30.25 + 40 + 20 = 90.25 s. So at the default bounds a spawn answers within
# 130 + 90.25 = 220.25 s, inside the hub's 240 s wait (cli/HubAct.ps1). A close with its close text ends
# by 60 s past the limit, and a session never ready by 20 + 40 + 20 = 80 s past it. test-node-act RUNS
# every path with each terminal call costing 20 s. The harness's own reads (its files, the process
# table) are not host calls; the 19.75 s left are theirs. Pings and reads on other links are not
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
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\JsonText.ps1")
$script:HordeNodeActCore = Split-Path -Parent $PSScriptRoot
foreach ($f in @("Tristate", "Namespace", "NodePolicy", "EngineResolve", "NodeEngineLayers", "AgentLaunch", "HostAct", "Secrets")) { . (Join-Path $script:HordeNodeActCore ("core\" + $f + ".ps1")) }
$script:HordeNodeSpawnLockName = ".spawn.lock"
# EVERY PROMPT GOES BY FILE (review of #104, F9). A harness's input box reads its first character as a
# mode - '!' a shell command run outside the permission mode just proven, '/' a command that can change
# it, '#' memory, '@' a file - so a hub's text is never typed. It is written to
# <records>\<sessionId>\prompt.txt, a folder of its own that only this user may open and that the
# session is granted at launch (F10), and the one line typed is built from these constants and that
# file's full path, then checked against Test-HordeNodeTypedLine before anything starts.
$script:HordeNodePromptLead = "Read "
$script:HordeNodePromptTail = " and do what it says."
$script:HordeNodePromptFile = "prompt.txt"
# The line typed before the mode is read back. A harness may keep its transcript in memory until the
# first user turn: MEASURED 2026-10-06, read-only over 279 transcripts of the founder's harness
# (versions 2.1.228 to 2.1.285), the file was created with the first user line in 192 of 199, lines timestamped up to 21
# minutes earlier written with it, so a session started with no prompt may have no permission-mode
# line on disk to read. One turn that asks for nothing makes it write one. A constant, never from the
# link; its cost is one model turn, and its window is that one turn, before the mode is proven
# (decision of 2026-10-06; a local command that forces the write without a model turn is to be
# measured live).
# THE MODE READ BACK DOES NOT PROVE THE LINE WAS SUBMITTED (issue #214). The harness adapter's READBACK
# note (measured 2026-10-05) has the mode line written at start, before the first turn; and on
# 2026-10-13 a live spawn read its mode back and was reported done while this line and the prompt's sat
# unsent in the input box. So each typed line is proven by its own receipt, a new user turn holding it
# in the session's transcript (Submit-HordeNodeLine), never by the mode.
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
    try { return (New-HordeKnown -Value (ConvertFrom-HordeJson -Text ([System.IO.File]::ReadAllText($p)))) }
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
        try { $r = ConvertFrom-HordeJson -Text ([System.IO.File]::ReadAllText($f.FullName)) } catch { $n++; continue }
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

function Get-HordeNodeClockMs {
    # The context's clock, in milliseconds that only move forward, or $null when it has none.
    param([Parameter(Mandatory = $true)]$Context)
    if ($null -eq $Context.PSObject.Properties["clock"] -or $null -eq $Context.clock) { return $null }
    return [double](& $Context.clock)
}

function Test-HordeNodeDeadlinePassed {
    # Has this spawn's own limit (deadlineMs, see A SPAWN HOLDS THE SERVE LOOP) run out, or will it within
    # -Within seconds from now?
    param([Parameter(Mandatory = $true)]$Context, [double]$Within = 0)
    $now = Get-HordeNodeClockMs -Context $Context
    return [bool]($null -ne $now -and $null -ne $Context.PSObject.Properties["deadlineMs"] -and $now + 1000 * $Within -ge [double]$Context.deadlineMs)
}

function Wait-HordeNodeUntil {
    # Ask -Probe until it answers something other than $null, or -Seconds pass. On a context with a clock
    # the seconds are wall time on that clock, and the wait also ends at the context's deadlineMs when it
    # has one: a probe that is slow itself cannot stretch a wait by its number of polls (review of PR 239,
    # S3). The probe is always asked at least once. A context with no clock counts polls. -Whole runs the
    # whole -Seconds past the deadline: for a typed line's waits, which read no host (see A SPAWN HOLDS
    # THE SERVE LOOP).
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)][scriptblock]$Probe, [Parameter(Mandatory = $true)][double]$Seconds, [switch]$Whole)
    $start = Get-HordeNodeClockMs -Context $Context
    if ($null -ne $start) {
        $until = $start + ($Seconds * 1000)
        if (-not $Whole -and $null -ne $Context.PSObject.Properties["deadlineMs"] -and [double]$Context.deadlineMs -lt $until) { $until = [double]$Context.deadlineMs }
        while ($true) {
            $v = & $Probe
            if ($null -ne $v) { return $v }
            $now = Get-HordeNodeClockMs -Context $Context
            if ($now -ge $until) { return $null }
            & $Context.sleep ([int][math]::Max(1, [math]::Min([double]$Context.bounds.pollMs, $until - $now)))
        }
    }
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

function Test-HordeNodeTypedLine {
    # May this line be typed into a session's input? Printable ASCII only - no line or format character
    # of any script - and not starting with a character the input box reads as a mode: ! / # @ (F9).
    param([AllowEmptyString()][string]$Line)
    if ($Line -cnotmatch '\A[\x20-\x7E]+\z') { return $false }
    return [bool]("!/#@".IndexOf($Line[0]) -lt 0)
}

function Set-HordeNodeOwnerOnly {
    # Make a folder this user's alone: inheritance cut, and one rule, full control for this user (F10).
    param([Parameter(Mandatory = $true)][string]$Path)
    $sec = New-Object System.Security.AccessControl.DirectorySecurity
    $sec.SetAccessRuleProtection($true, $false)
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $inherit = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    $sec.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($me, [System.Security.AccessControl.FileSystemRights]::FullControl, $inherit, [System.Security.AccessControl.PropagationFlags]::None, [System.Security.AccessControl.AccessControlType]::Allow)))
    [System.IO.Directory]::SetAccessControl($Path, $sec)
}

function New-HordeNodePromptDir {
    # The folder a session's prompt is put in, made before the session starts so it can be granted at
    # launch: { dir; file; line; reason }. reason is "" when the folder is made, this user's alone,
    # inside the node's home with no junction on the way, and the line that names its file may be typed.
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)][string]$SessionId)
    $out = [pscustomobject]@{ dir = ""; file = ""; line = ""; reason = "" }
    $dir = Join-Path $Context.records $SessionId
    $full = $null
    try { $full = [System.IO.Path]::GetFullPath($dir) } catch { $out.reason = "the prompt folder " + $dir + " is not a path"; return $out }
    if ($full -cne $dir -or -not [System.IO.Path]::IsPathRooted($dir)) { $out.reason = "the prompt folder " + $dir + " is not a full rooted path"; return $out }
    $chain = Test-HordeNodeRecordsChain -HordeHome $Context.home -Dir $dir
    if ($chain -ne "") { $out.reason = $chain; return $out }
    $file = Join-Path $dir $script:HordeNodePromptFile
    $line = $script:HordeNodePromptLead + $file + $script:HordeNodePromptTail
    if (-not (Test-HordeNodeTypedLine -Line $line)) { $out.reason = "the line naming the prompt file, " + $file + ", could not be typed safely (printable ASCII only), so nothing is started"; return $out }
    try { New-Item -ItemType Directory -Path $dir -Force | Out-Null; Set-HordeNodeOwnerOnly -Path $dir }
    catch { $out.reason = "the prompt folder " + $dir + " could not be made this user's alone: " + $_.Exception.Message; return $out }
    $out.dir = $dir; $out.file = $file; $out.line = $line
    return $out
}

# A TYPED LINE IS TAKEN ONLY WHEN ITS TURN IS SEEN (issue #214). The host answering known means only
# that the terminal took the keys. So the harness's adapter marks its transcript BEFORE the line is
# typed, and the line counts as taken once the adapter sees a new user turn holding it. When none comes
# within receiptSeconds, ONE more Enter is pressed - only when the turn is still not there AND the
# host's screen shows the harness's input box holding exactly that line - and the turn is waited for
# again for retrySeconds. Never a second extra Enter for one line: an Enter into a box that holds
# other text submits that text, and one into a dialog answers it. A harness or host that cannot tell
# answers unknown, and an unknown is never reported as taken.
function Submit-HordeNodeLine {
    # Type -Line with Enter into -Handle and prove it became a turn of -SessionId. Returns { state;
    # extraEnter; reason; mark }: state taken, not-taken (no turn came), unknown (it cannot be told) or
    # unsent (the host did not take the keys); reason says why for every state but taken; mark is the
    # transcript mark taken before typing, for the wait for that turn's end.
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)]$Actor, [Parameter(Mandatory = $true)]$Target, [Parameter(Mandatory = $true)]$Adapter,
        [Parameter(Mandatory = $true)][string]$Handle, [Parameter(Mandatory = $true)][string]$SessionId, [Parameter(Mandatory = $true)][string]$Line)
    $out = [pscustomobject]@{ state = "unknown"; extraEnter = $false; reason = ""; mark = $null }
    $canTell = ($null -ne $Adapter.PSObject.Properties["turnMark"] -and $null -ne $Adapter.turnMark -and $null -ne $Adapter.PSObject.Properties["turnSeen"] -and $null -ne $Adapter.turnSeen)
    $mark = $null
    if ($canTell) { $mark = & $Adapter.turnMark $SessionId $Context.environment }
    $r = & $Actor.send $Target $Handle $Line $true
    if ($null -eq $r -or $r.state -ne "known") { $out.state = "unsent"; $out.reason = $(if ($null -ne $r) { "" + $r.reason } else { "the host gave no answer" }); return $out }
    if (-not $canTell) { $out.reason = "the harness " + $Adapter.name + " cannot tell whether a typed line became a turn"; return $out }
    if ($null -eq $mark -or $mark.state -ne "known") { $out.reason = "the session's transcript could not be marked before the line was typed: " + $(if ($null -ne $mark) { "" + $mark.reason } else { "the harness gave no answer" }); return $out }
    $out.mark = $mark.value
    # Every look's answer is kept: a look that could not tell is looked at again, and only when no look
    # ever could is the answer unknown rather than not-taken.
    $seen = @{ known = $false; reason = "" }
    $look = {
        $a = & $Adapter.turnSeen $SessionId $Context.environment $mark.value $Line
        if ($null -ne $a -and $a.state -eq "known") { $seen.known = $true; if ($a.value -eq $true) { return $true } }
        elseif ($null -ne $a) { $seen.reason = "" + $a.reason }
        return $null
    }
    # The line is typed, so its waits run whole, past this spawn's limit if need be: they read only the
    # transcript, and a wait cut at the limit would judge the line on one look before its turn could be
    # written (F's re-check of round 3: the issue #214 double run on a slow host).
    if ($true -eq (Wait-HordeNodeUntil -Context $Context -Seconds $Context.bounds.receiptSeconds -Probe $look -Whole)) { $out.state = "taken"; return $out }
    $waited = "" + $Context.bounds.receiptSeconds
    $box = New-HordeUnknown -Reason ("the host " + $Actor.name + " cannot show a pane's screen")
    # Past this spawn's limit no host call starts, so the box is not looked at and no extra Enter is
    # pressed (review of PR 239, S-a). An Enter pressed inside it gets its whole retry wait after it.
    if (Test-HordeNodeDeadlinePassed -Context $Context) { $box = New-HordeUnknown -Reason "this spawn's own limit ran out, so the box was not looked at" }
    elseif ($null -ne $Actor.PSObject.Properties["text"] -and $null -ne $Actor.text) {
        $scr = & $Actor.text $Target $Handle
        if ($null -eq $scr -or $scr.state -ne "known") { $box = New-HordeUnknown -Reason ("the pane's screen could not be read: " + $(if ($null -ne $scr) { "" + $scr.reason } else { "the host gave no answer" })) }
        elseif ($null -eq $Adapter.PSObject.Properties["inputHolds"] -or $null -eq $Adapter.inputHolds) { $box = New-HordeUnknown -Reason ("the harness " + $Adapter.name + " cannot read its input box on a screen") }
        else { $box = & $Adapter.inputHolds ([string[]]@($scr.value)) $Line }
    }
    $boxSaid = ""
    if ($null -eq $box -or $box.state -ne "known") { $boxSaid = "its input box could not be read (" + $(if ($null -ne $box) { "" + $box.reason } else { "no answer" }) + "), so no other Enter was pressed" }
    elseif ($box.value -ne $true) { $boxSaid = "its input box did not hold the line, so no other Enter was pressed" }
    elseif ($true -eq (& $look)) { $out.state = "taken"; return $out }
    elseif (Test-HordeNodeDeadlinePassed -Context $Context) { $boxSaid = "its input box still held the line, but this spawn's own limit ran out while the box was read, so no other Enter was pressed" }
    else {
        $e = & $Actor.send $Target $Handle "" $true
        $out.extraEnter = $true
        if ($null -eq $e -or $e.state -ne "known") { $boxSaid = "its input box still held the line and one more Enter was sent, which the host did not take" }
        else {
            if ($true -eq (Wait-HordeNodeUntil -Context $Context -Seconds $Context.bounds.retrySeconds -Probe $look -Whole)) { $out.state = "taken"; return $out }
            $boxSaid = "its input box still held the line, so ONE more Enter was pressed, and no turn came in " + $Context.bounds.retrySeconds + " s more"
        }
    }
    if (-not $seen.known) { $out.state = "unknown"; $out.reason = "whether the line became a turn could not be told: " + $seen.reason + "; " + $boxSaid; return $out }
    $out.state = "not-taken"
    $out.reason = "no turn holding the typed line reached the session's transcript within " + $waited + " s; " + $boxSaid
    return $out
}

function Test-HordeNodeBlock {
    # Does an adapter or actor carry the optional block -Name?
    param([Parameter(Mandatory = $true)]$Port, [Parameter(Mandatory = $true)][string]$Name)
    return [bool]($null -ne $Port.PSObject.Properties[$Name] -and $null -ne $Port.$Name)
}

# READY BEFORE THE FIRST KEY (PR 239 round 2). On 2026-10-13 BOTH typed lines sat in the box, so even
# the first Enter was lost, and a key typed while a harness starts can be lost: measured 2026-10-14 in
# an isolated terminal (the harness adapter's READY FOR KEYS note), a key typed 2.3 s in, before the
# box was drawn, never arrived, while the two typed before it and every one after it did. So nothing is
# typed until the harness's adapter, reading the host's screen of the pane, says the session is ready.
function Wait-HordeNodeReady {
    # Wait until the session in -Handle is ready to take keys. Returns { state; reason }: ready;
    # not-ready, with the last reason it was not, after readySeconds (or this spawn's limit); or
    # cannot-tell, when the harness or the host has no block to read it with.
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)]$Actor, [Parameter(Mandatory = $true)]$Target, [Parameter(Mandatory = $true)]$Adapter, [Parameter(Mandatory = $true)][string]$Handle)
    if (-not (Test-HordeNodeBlock -Port $Adapter -Name "inputReady")) { return [pscustomobject]@{ state = "cannot-tell"; reason = ("the harness " + $Adapter.name + " cannot tell from a screen whether it is ready") } }
    if (-not (Test-HordeNodeBlock -Port $Actor -Name "text")) { return [pscustomobject]@{ state = "cannot-tell"; reason = ("the host " + $Actor.name + " cannot show a pane's screen") } }
    # No host call starts once this spawn's limit has run out (review of PR 239, S-a): a look is a host
    # call, which may take the host's whole call timeout.
    if (Test-HordeNodeDeadlinePassed -Context $Context) { return [pscustomobject]@{ state = "not-ready"; reason = "this spawn's own limit ran out before the screen was looked at" } }
    $last = @{ reason = "the screen was never looked at" }
    $ok = Wait-HordeNodeUntil -Context $Context -Seconds ([double]$Context.bounds.readySeconds) -Probe {
        $scr = & $Actor.text $Target $Handle
        if ($null -eq $scr -or $scr.state -ne "known") { $last.reason = "the pane's screen could not be read: " + $(if ($null -ne $scr) { "" + $scr.reason } else { "the host gave no answer" }); return $null }
        $a = & $Adapter.inputReady ([string[]]@($scr.value))
        if ($null -ne $a -and $a.state -eq "known" -and $a.value -eq $true) { return $true }
        $last.reason = $(if ($null -ne $a -and "" + $a.reason -ne "") { "" + $a.reason } else { "the harness did not say it was ready" })
        return $null
    }
    if ($ok -eq $true) { return [pscustomobject]@{ state = "ready"; reason = "" } }
    return [pscustomobject]@{ state = "not-ready"; reason = $last.reason }
}

function Wait-HordeNodeTurnEnd {
    # After a line was taken, wait until its turn ended (review of PR 239, M1): the harness records a
    # turn's end after -Mark. Returns { state; reason }: ended; not-ended after turnEndSeconds (or this
    # spawn's limit); or cannot-tell, when the harness has no block for it or there is no mark.
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)]$Adapter, [Parameter(Mandatory = $true)][string]$SessionId, $Mark)
    if (-not (Test-HordeNodeBlock -Port $Adapter -Name "turnDone")) { return [pscustomobject]@{ state = "cannot-tell"; reason = ("the harness " + $Adapter.name + " cannot tell when a turn ends") } }
    if ($null -eq $Mark) { return [pscustomobject]@{ state = "cannot-tell"; reason = "no transcript mark was taken before the line" } }
    $last = @{ reason = "no turn end was recorded" }
    $ok = Wait-HordeNodeUntil -Context $Context -Seconds ([double]$Context.bounds.turnEndSeconds) -Probe {
        $a = & $Adapter.turnDone $SessionId $Context.environment $Mark
        if ($null -ne $a -and $a.state -eq "known" -and $a.value -eq $true) { return $true }
        if ($null -ne $a -and $a.state -ne "known") { $last.reason = "" + $a.reason }
        return $null
    }
    if ($ok -eq $true) { return [pscustomobject]@{ state = "ended"; reason = "" } }
    return [pscustomobject]@{ state = "not-ended"; reason = $last.reason }
}

function Send-HordeNodePrompt {
    # Deliver a session's first prompt once its mode is proven (step 8): the prompt is written to its
    # file and the one line naming that file is typed and proven a turn (Submit-HordeNodeLine). Returns
    # { state; reason }: state taken (or none, for no prompt), not-taken, unknown, or unsent with why.
    # The hub's text is never typed (F9).
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)]$Actor, [Parameter(Mandatory = $true)]$Target, [Parameter(Mandatory = $true)]$Adapter,
        [Parameter(Mandatory = $true)][string]$Handle, [Parameter(Mandatory = $true)][string]$SessionId, [Parameter(Mandatory = $true)]$PromptDir, [AllowEmptyString()][string]$Prompt = "")
    if ($Prompt -eq "") { return [pscustomobject]@{ state = "none"; reason = "" } }
    try { [System.IO.File]::WriteAllText($PromptDir.file, $Prompt, (New-Object System.Text.UTF8Encoding($false))) }
    catch { return [pscustomobject]@{ state = "unsent"; reason = ("the prompt could not be written for the session to read: " + $_.Exception.Message) } }
    $line = $script:HordeNodePromptLead + $PromptDir.file + $script:HordeNodePromptTail
    if (-not (Test-HordeNodeTypedLine -Line $line)) { return [pscustomobject]@{ state = "unsent"; reason = "the line naming the prompt file could not be typed safely" } }
    $sub = Submit-HordeNodeLine -Context $Context -Actor $Actor -Target $Target -Adapter $Adapter -Handle $Handle -SessionId $SessionId -Line $line
    if ($sub.state -eq "unsent") { return [pscustomobject]@{ state = "unsent"; reason = ("the prompt could not be typed into the session's pane: " + $sub.reason) } }
    return [pscustomobject]@{ state = $sub.state; reason = $sub.reason }
}

function Stop-HordeNodeSession {
    # End a session this node just started and will not keep: its close text, then - only for a process
    # proven by pid and start time - the host's end of its pane. Returns whether the process is gone.
    # -SkipCloseText goes straight to the host's end: a box still holding a typed line would take the
    # close text as more of that line, and its Enter might run it as a turn (review of PR 239, S1).
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)]$Actor, [Parameter(Mandatory = $true)]$Target, [Parameter(Mandatory = $true)]$Adapter,
        [Parameter(Mandatory = $true)][string]$Handle, [Parameter(Mandatory = $true)][long]$ProcessId, [Parameter(Mandatory = $true)][string]$ProcStart, [switch]$SkipCloseText)
    if (-not $SkipCloseText) {
        $null = Send-HordeNodeCloseText -Actor $Actor -Target $Target -Handle $Handle -Adapter $Adapter
        $gone = Wait-HordeNodeUntil -Context $Context -Seconds $Context.bounds.closeSeconds -Probe { if (Test-HordeNodeProcessGone -Context $Context -ProcessId $ProcessId -ProcStart $ProcStart) { $true } else { $null } }
        if ($gone -eq $true) { return $true }
    }
    $null = & $Actor.stop $Target $Handle ([pscustomobject]@{ pid = $ProcessId; procStart = $ProcStart })
    $gone = Wait-HordeNodeUntil -Context $Context -Seconds $Context.bounds.closeSeconds -Probe { if (Test-HordeNodeProcessGone -Context $Context -ProcessId $ProcessId -ProcStart $ProcStart) { $true } else { $null } }
    return [bool]($gone -eq $true)
}

# THE SCREEN OF A SESSION THAT WAS NOT READY (issue #214, PR 239 round 4). A spawn that ends not ready -
# never ready, too near its limit for the no-op line, or the no-op's turn never ended - first reads the
# pane's screen once, through the host's Text block (the one the readiness wait reads), so a person sees
# which dialog was up without opening the pane. The look is a host call like any other: past this spawn's
# limit it is not made, and the report says so. WHERE IT GOES: the node's own spawn record (screen:
# { state; said; rows }), never the answer to the hub, whose reason carries at most 1024 bytes on the
# link (schema/link-frame.v1, reasonBytes) and is already a few hundred; the reason says which of these
# it was. WHAT IS KEPT: rows with blanks trimmed from their ends, blank rows trimmed from top and bottom
# and every run of them kept as one, then the LAST 40 rows (a dialog and the input box are drawn at the
# bottom), fewer while they are over 4000 characters; printable ASCII and the box-drawing glyphs
# (U+2500 to U+257F) as they are, a tab or a no-break space as a space, and every other character as
# '?', so the record reads alike in any console. NO SECRET IS SHOWN: see Find-HordeNodeScreenSecret;
# a screen that looks like it holds one is withheld whole - only the kind is said, never a row.
# WHERE THE ROWS ARE KEPT (F's re-check of round 4, REQUIRED): not in the record, whose folder takes the
# permissions of the node's home, but in <records>\<sid>\screen.json, inside the session's own folder,
# which is this user's alone (Set-HordeNodeOwnerOnly, F10). The record says only the state, the clause
# and that file. HOW LONG: 7 days from the look, by the node's clock; every spawn, and every start of
# `horde node serve` (Invoke-HordeNodeServeSweep), under the spawn lock, deletes the screen files older
# than that, and any it cannot read (Remove-HordeNodeOldScreens). A screen
# is for a person looking into a failed spawn the same week, and its rows are the one thing in a record
# that can hold what the session showed; a week is long enough to look and short enough that a screen
# nobody looked at does not stay forever.
# KNOWN LIMIT (F's re-check of round 6, issue 214): a secret wrapped onto a row LESS indented than its
# head is not joined, so it is still shown. That is how indented content wraps - a tool-output block or a
# nested bullet (probe6: a head at indent 7 with the rest at 5, a bullet at 4 with the rest at 2). The
# fix, a reading that joins every adjacent pair trimmed and ignoring indent, judged pair by pair, is a
# follow-up. Until then the screen stays on this machine only, in an owner-only file kept 7 days, and the
# same text is already in the session's own transcript in the same profile.
$script:HordeNodeScreenRows = 40
$script:HordeNodeScreenChars = 4000
$script:HordeNodeScreenFile = "screen.json"
$script:HordeNodeScreenKeepDays = 7
# The one kind core/Secrets.ps1 looks for only when it is named; misspelt, Find-HordeSecretKind throws.
$script:HordeNodeNamedSecretKind = "a secret written under a name such as client_secret or password"

function ConvertTo-HordeNodeScreenRow {
    # One screen row as the record keeps it: see THE SCREEN OF A SESSION THAT WAS NOT READY.
    param([AllowEmptyString()][string]$Row)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $Row.ToCharArray()) {
        $n = [int]$ch
        if (($n -ge 0x20 -and $n -le 0x7E) -or ($n -ge 0x2500 -and $n -le 0x257F)) { [void]$sb.Append($ch) }
        elseif ($n -eq 0x09 -or $n -eq 0xA0) { [void]$sb.Append(' ') }
        else { [void]$sb.Append('?') }
    }
    return $sb.ToString().TrimEnd()
}

function Find-HordeNodeScreenSecret {
    # The kind of secret a screen looks like it holds, or "". -Raw is the screen as read, one row each;
    # -Kept the rows as the record would keep them. A secret on a screen is not always on one row in one
    # piece, so every reading below is checked, with every default kind and then the named kind (F's
    # re-check of round 4, REQUIRED; each reading answers one of F's probe4 cases that the rows alone
    # showed, measured 2026-10-14):
    #   - rows joined by a line break, and joined by NOTHING: a terminal wraps a long token across two
    #     rows, and each half is too short for any shape (a 40-character cloud secret, a ghp token);
    #   - the raw rows, the raw rows with every character outside printable ASCII REMOVED (a zero-width
    #     space splits a token, and as '?' it still splits it), and the kept rows (a letter outside ASCII
    #     as '?' gives the name=value kind its word boundary: "Note" + U+00E9 + "password=" and a value
    #     under 8 characters, which the named kind does not take; measured 2026-10-14, only this reading
    #     finds it);
    #   - each of those as it is; SPACED, a space after every '=', because the look for a key with
    #     slashes refuses one with '=' right before it (NAME=<key> read as nothing); and DASHED, every
    #     underscore as a dash, because the name=value kind needs a word boundary that DB_PASSWORD's
    #     underscore does not give, and api_key and access_key take an underscore, a dash or nothing
    #     between their words, never a space. Round 5 turned underscores into SPACES, and so showed
    #     SOME_API_KEY=<value> and AWS_ACCESS_KEY=<value> (F's re-check of round 5, SHOULD TWO); a dash
    #     gives every name the boundary a space gave it, so the spaced form now spaces '=' alone;
    #   - and TRIMMED: the raw rows with every character outside printable ASCII removed (a box's
    #     vertical bars and the tool-output corner among them), each trimmed of spaces and '|' at both
    #     ends, then joined by nothing: the harness wraps a long token onto an INDENTED row, or inside a
    #     bordered box, so the gap between its halves is padding the other joins keep (F's re-check of
    #     round 5, SHOULD ONE: a continuation indented 2, a ghp token's indented 5, a cloud secret in a
    #     box, all shown on 5b0690c). A row is joined so only to a row above it that is indented no
    #     deeper - its leading spaces and '|' counted as its indent - because a harness
    #     puts a wrapped row's rest at its text's own left edge or deeper; a terminal's own wrap starts
    #     the rest at the left edge with no padding, which the join by nothing already reads. Joining
    #     every pair fused the suite's ordinary screen - a commit id row indented 2 over a dialog row
    #     indented 1 - into a long mixed run (measured 2026-10-14).
    # Withholding too much costs a person the screen of one failed spawn; showing a secret cannot be
    # taken back. Rows the 40-row window cuts are checked too, since the raw screen is. WHAT THAT COSTS,
    # measured on the suite's screens: a 40-character commit id ending a row, with a capitalised word
    # starting the next, joins into a long mixed run and is withheld; so is GH_TOKEN=<placeholder>.
    # STILL SHOWN, a known limit of the kinds themselves: a value after a NAME= that holds none of the
    # names the kinds know nor a key's shape, such as SESSION_CODE=short1234. (MY_API_KEY=short1234 and
    # DB_TOKEN=abc, shown in round 5, are withheld since the dashed form, measured 2026-10-14.)
    param([string[]]$Raw, [string[]]$Kept)
    $ascii = [string[]]@(@($Raw) | ForEach-Object { [regex]::Replace(("" + $_), '[^\x20-\x7E]', '') })
    $texts = New-Object System.Collections.ArrayList
    foreach ($source in @(@{ rows = @($Raw) }, @{ rows = @($ascii) }, @{ rows = @($Kept) })) {
        foreach ($glue in @("`n", "")) { [void]$texts.Add((@($source.rows) -join $glue)) }
    }
    $trim = New-Object System.Text.StringBuilder
    $lead = -1
    foreach ($r in @($Raw)) {
        $indent = [regex]::Match(("" + $r), '\A[\s|]*').Length
        $t = [regex]::Replace(("" + $r), '[^\x20-\x7E]', '').Trim(' ', '|')
        if ($lead -lt 0 -or $indent -lt $lead) { [void]$trim.Append("`n") }
        [void]$trim.Append($t); $lead = $indent
    }
    [void]$texts.Add($trim.ToString())
    foreach ($text in $texts) {
        foreach ($form in @($text, $text.Replace("=", "= "), $text.Replace("_", "-"))) {
            $kind = Find-HordeSecretKind -Text $form
            if ($kind -ceq "") { $kind = Find-HordeSecretKind -Text $form -Kinds @($script:HordeNodeNamedSecretKind) }
            if ($kind -cne "") { return $kind }
        }
    }
    return ""
}

function Get-HordeNodeScreenReport {
    # Read -Handle's screen once for a not-ready report. Returns { state; said; rows }: state shown (rows
    # kept), withheld (it looked like it held a secret: no rows), skipped (this spawn's limit had run out:
    # no look) or unreadable; said is the clause the outcome's reason carries.
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)]$Actor, [Parameter(Mandatory = $true)]$Target, [Parameter(Mandatory = $true)][string]$Handle)
    $none = [string[]]@()
    if (-not (Test-HordeNodeBlock -Port $Actor -Name "text")) { return [pscustomobject]@{ state = "unreadable"; said = ("its screen could not be read: the host " + $Actor.name + " cannot show a pane's screen"); rows = $none } }
    if (Test-HordeNodeDeadlinePassed -Context $Context) { return [pscustomobject]@{ state = "skipped"; said = "its screen was not read: this spawn's own limit had run out, and no host call starts after it"; rows = $none } }
    $scr = & $Actor.text $Target $Handle
    if ($null -eq $scr -or $scr.state -ne "known") { return [pscustomobject]@{ state = "unreadable"; said = ("its screen could not be read: " + $(if ($null -ne $scr) { "" + $scr.reason } else { "the host gave no answer" })); rows = $none } }
    $raw = @(@($scr.value) | ForEach-Object { ("" + $_) -split "`r?`n" })
    $rows = New-Object System.Collections.ArrayList
    foreach ($r in $raw) {
        $c = ConvertTo-HordeNodeScreenRow -Row $r
        if ($c -eq "" -and ($rows.Count -eq 0 -or $rows[$rows.Count - 1] -eq "")) { continue }
        [void]$rows.Add($c)
    }
    while ($rows.Count -gt 0 -and $rows[$rows.Count - 1] -eq "") { $rows.RemoveAt($rows.Count - 1) }
    $all = $rows.Count
    while ($rows.Count -gt $script:HordeNodeScreenRows) { $rows.RemoveAt(0) }
    while ($rows.Count -gt 1 -and ((@($rows) -join "`n").Length -gt $script:HordeNodeScreenChars)) { $rows.RemoveAt(0) }
    if ($rows.Count -eq 1 -and $rows[0].Length -gt $script:HordeNodeScreenChars) { $rows[0] = $rows[0].Substring(0, $script:HordeNodeScreenChars) }
    $kind = Find-HordeNodeScreenSecret -Raw ([string[]]@($raw)) -Kept ([string[]]@($rows))
    if ($kind -cne "") { return [pscustomobject]@{ state = "withheld"; said = ("its screen was WITHHELD because it looked like it held " + $kind + ", so it is shown nowhere"); rows = $none } }
    if ($rows.Count -eq 0) { return [pscustomobject]@{ state = "shown"; said = "its screen was blank"; rows = $none } }
    $cut = ""
    if ($all -gt $rows.Count) { $cut = ", the " + ($all - $rows.Count) + " rows above them left out" }
    return [pscustomobject]@{ state = "shown"; said = ("its screen as it was then, the last " + $rows.Count + " rows" + $cut + ", is kept for " + $script:HordeNodeScreenKeepDays + " days in this node's own folder of the session, this user's alone"); rows = [string[]]@($rows) }
}

function Save-HordeNodeScreenReport {
    # Capture -Handle's screen: its rows into the session's own folder, and { state; said; file } into
    # -Record (written later by the caller). Returns the reason's clause. See WHERE THE ROWS ARE KEPT.
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)]$Actor, [Parameter(Mandatory = $true)]$Target, [Parameter(Mandatory = $true)]$Record)
    $s = Get-HordeNodeScreenReport -Context $Context -Actor $Actor -Target $Target -Handle ("" + $Record.handle)
    $state = $s.state; $said = $s.said; $file = ""
    if (@($s.rows).Count -gt 0) {
        # Only the folder this node made for this session, which New-HordeNodePromptDir made this user's
        # alone: a record without one, or naming another, keeps no rows.
        $own = Join-Path $Context.records ("" + $Record.sessionId)
        $dir = ""
        if ($Record -is [System.Collections.IDictionary]) { if ($Record.Contains("promptDir")) { $dir = "" + $Record["promptDir"] } }
        elseif ($null -ne $Record.PSObject.Properties["promptDir"]) { $dir = "" + $Record.promptDir }
        if ($dir -ceq "" -or $dir -cne $own -or -not (Test-Path -LiteralPath $dir -PathType Container) -or (Test-HordeNodeReparse -Path $dir)) {
            $state = "unkept"; $said = "its screen was read but not kept: this spawn has no folder of its own, this user's alone, to keep it in"
        } else {
            try {
                $file = Join-Path $dir $script:HordeNodeScreenFile
                $tmp = Join-Path $dir ("." + [guid]::NewGuid().ToString("N") + ".tmp")
                $body = [pscustomobject][ordered]@{ sessionId = "" + $Record.sessionId; takenAt = (& $Context.now).ToUniversalTime().ToString("o"); rows = [string[]]@($s.rows) }
                [System.IO.File]::WriteAllText($tmp, ($body | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
                Move-Item -LiteralPath $tmp -Destination $file -Force
            } catch { $file = ""; $state = "unkept"; $said = "its screen was read but could not be kept: " + $_.Exception.Message }
        }
    }
    $screen = [pscustomobject][ordered]@{ state = $state; said = $said; file = $file }
    # A spawn's record is an ordered table; one read back from its file is an object.
    if ($Record -is [System.Collections.IDictionary]) { $Record["screen"] = $screen } else { $Record | Add-Member -NotePropertyName screen -NotePropertyValue $screen -Force }
    return $said
}

function Remove-HordeNodeOldScreens {
    # Delete every screen file under -Dir taken more than HordeNodeScreenKeepDays before or after -Now, and every
    # one whose time cannot be read (see WHERE THE ROWS ARE KEPT). Only a session's own folder is looked
    # in - a session id for a name, no junction or link - and only its screen file is deleted. Returns
    # how many were.
    param([Parameter(Mandatory = $true)][string]$Dir, [Parameter(Mandatory = $true)][datetime]$Now)
    if (-not (Test-Path -LiteralPath $Dir -PathType Container) -or (Test-HordeNodeReparse -Path $Dir)) { return 0 }
    $n = 0
    foreach ($d in @(Get-ChildItem -LiteralPath $Dir -Directory -Force)) {
        if ($d.Name -cnotmatch '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z' -or (Test-HordeNodeReparse -Path $d.FullName)) { continue }
        $f = Join-Path $d.FullName $script:HordeNodeScreenFile
        if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
        $old = $true
        try {
            $at = [datetime]::Parse(("" + (ConvertFrom-HordeJson -Text ([System.IO.File]::ReadAllText($f))).takenAt), [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
            # A takenAt AFTER the clock (the clock was set back) counts its distance too, so a screen is
            # never kept more than a week from the time it names, whichever way the clock moved.
            $old = ([Math]::Abs(($Now.ToUniversalTime() - $at).TotalDays) -gt $script:HordeNodeScreenKeepDays)
        } catch { $old = $true }
        if ($old) { Remove-Item -LiteralPath $f -Force; $n++ }
    }
    return $n
}

# NOT READY, NOTHING TYPED (review of PR 239, S-d). A session the node typed nothing into - never ready
# for keys, or this spawn's limit too near for a line's wait - is kept only when its mode is PROVEN the
# level asked for: the harness's mode record is read once, as it stands (nothing typed means nothing to
# wait for). Otherwise it is ended by the host, by its pid and start time, with no close text: a box that
# is not ready, or a dialog, would take the close text as its input or its answer. MEASURED 2026-10-14
# on 2.1.299 (the harness adapter's READBACK note): with no line typed the session has no transcript,
# so for that harness this path ends the session - fail closed, as round 1 did for any unproven session.
function Complete-HordeNodeNotReady {
    # Settle a spawn that typed nothing: returns its outcome. -Why starts "not-ready:" and says why nothing
    # was typed; -Context carries this spawn's limit, -Base the bounds the close gets after it.
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)]$Base, [Parameter(Mandatory = $true)]$Actor, [Parameter(Mandatory = $true)]$Target, [Parameter(Mandatory = $true)]$Adapter,
        [Parameter(Mandatory = $true)]$Record, [Parameter(Mandatory = $true)][string]$Level, [Parameter(Mandatory = $true)]$Expect, [Parameter(Mandatory = $true)][string]$Why)
    $sid = "" + $Record.sessionId
    $Why += "; " + (Save-HordeNodeScreenReport -Context $Context -Actor $Actor -Target $Target -Record $Record)
    $m = & $Adapter.readMode $sid $Context.environment
    if ($null -ne $m -and $m.state -eq "known" -and "" + $m.value -ceq $Level) {
        $Record.outcome = "not-ready"; Write-HordeNodeSpawnRecord -Dir $Context.records -Record $Record
        & $Context.alert ("ALERT: session " + $sid + " (pane " + $Record.handle + ", pid " + $Record.pid + ") never became ready for keys and is left running; its permission mode reads " + $Level + ", as asked")
        return (New-HordeNodeOutcome -State "failed" -SessionId $sid -Expect $Expect -Reason ($Why + "; nothing was typed; its permission mode reads " + $Level + ", as asked, so it is LEFT RUNNING: look at pane " + $Record.handle + ", or close it with this process"))
    }
    $modeSaid = $(if ($null -eq $m) { "its permission mode could not be read: the harness gave no answer" } elseif ($m.state -ne "known") { "its permission mode could not be read (" + $(if ("" + $m.reason -ne "") { "" + $m.reason } else { "" + $m.note }) + ")" } else { "it reports the level " + $m.value + " and was asked for " + $Level })
    $gone = Stop-HordeNodeSession -Context $Base -Actor $Actor -Target $Target -Adapter $Adapter -Handle $Record.handle -ProcessId $Record.pid -ProcStart $Record.procStart -SkipCloseText
    if (-not $gone) {
        $Record.outcome = "unkept-running"; Write-HordeNodeSpawnRecord -Dir $Context.records -Record $Record
        & $Context.alert ("ALERT: session " + $sid + " (pane " + $Record.handle + ", pid " + $Record.pid + ") never became ready, is not kept, and could not be ended: " + $modeSaid)
        return (New-HordeNodeOutcome -State "failed" -SessionId $sid -Expect $Expect -Reason ($Why + "; nothing was typed; " + $modeSaid + ", so it is not kept, and it could NOT be ended and is still running: close it again with this process, or end pane " + $Record.handle + " by hand"))
    }
    $Record.outcome = "not-ready-closed"; $Record.closedAt = (& $Context.now).ToUniversalTime().ToString("o"); Write-HordeNodeSpawnRecord -Dir $Context.records -Record $Record
    return (New-HordeNodeOutcome -State "failed" -SessionId $sid -Reason ($Why + "; nothing was typed; " + $modeSaid + ", so it is not kept: the host ended it by its process, with no close text typed"))
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
    # This spawn's own limit counts from here, so the host calls before the pane starts are inside it.
    $actStartMs = Get-HordeNodeClockMs -Context $Context
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
        # Screens past their week go now, under the lock (WHERE THE ROWS ARE KEPT). A sweep that fails
        # refuses nothing: it is said, and the next spawn sweeps again.
        try { $null = Remove-HordeNodeOldScreens -Dir $Context.records -Now (& $Context.now) }
        catch { & $Context.alert ("ALERT: this node could not delete its old screens of sessions that were not ready: " + $_.Exception.Message) }
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
        # The prompt's own folder, this user's alone, granted to the session at launch (F10).
        $pd = New-HordeNodePromptDir -Context $Context -SessionId $sid
        if ($pd.reason -ne "") { return (New-HordeNodeOutcome -State "refused" -Reason $pd.reason) }
        # No prompt in the argv: the work is delivered only once the mode is proven (step 8).
        $plan = New-HordeLaunchPlan -Resolution $res -Decision $d -SessionId $sid -Name $name -Prompt "" -Resolve $resolveProgram -AddDirs @($pd.dir)
        if ($plan.state -ne "known") { return (New-HordeNodeOutcome -State "refused" -Reason $plan.reason) }
        $adapter = (Get-HordeLaunchAdapter -Name $plan.value.harness).value
        # 6. The pane, recorded before it starts, under the lock, so the count already holds it.
        $record = [ordered]@{ sessionId = $sid; requestId = "" + $Act.requestId; hubId = $hubId; host = $actor.name; harness = $plan.value.harness; handle = ""; level = $d.level; name = $plan.value.name; workdir = $d.workdir; label = "" + $a.label; startedAt = (& $Context.now).ToUniversalTime().ToString("o"); pid = $null; procStart = ""; promptDir = $pd.dir; ready = ""; screen = $null; noOp = ""; noOpAt = ""; noOpTurn = ""; noOpEnd = ""; promptTurn = ""; closedAt = ""; outcome = "starting" }
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
    # THIS SPAWN'S OWN LIMIT (see A SPAWN HOLDS THE SERVE LOOP): every wait from here to the decision
    # ends by spawnSeconds after the act started. The closes after it get their own bounds, from the
    # context without the limit ($base), so a session that is not kept is still ended.
    $base = $Context
    if ($null -ne $actStartMs -and $null -ne $base.bounds.PSObject.Properties["spawnSeconds"]) {
        $Context = $base.PSObject.Copy()
        $Context | Add-Member -NotePropertyName deadlineMs -NotePropertyValue ($actStartMs + 1000 * [double]$base.bounds.spawnSeconds) -Force
    }
    # A line is typed only while its whole receipt wait still fits before the limit (review of PR 239,
    # S-b): a line typed later is looked for once, right after its Enter, before the harness can have
    # written its turn (0.2 s to 0.5 s after it, measured), and a prompt that ran would be reported
    # not submitted - the double run of issue #214.
    $lineSeconds = [double]$base.bounds.receiptSeconds + [double]$base.bounds.retrySeconds
    # The close text, one host call per item, and the close wait after it are typed and waited only while
    # they fit before the limit; else the host's end, whose calls the sum counts (F's re-check of round 3).
    # Bounds without it count the first host's 20 s, never 0: 0 would let the close text be typed 20 s
    # before the limit, with no time for its own calls (F's re-check of round 4, nit).
    $hostCall = 20.0
    if ($null -ne $base.bounds.PSObject.Properties["hostCallSeconds"]) { $hostCall = [double]$base.bounds.hostCallSeconds }
    $closeTextSeconds = @($adapter.closeText).Count * $hostCall + [double]$base.bounds.closeSeconds
    $limit = ""
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
    $expect = [pscustomobject][ordered]@{ ns = [pscustomobject][ordered]@{ device = "" + $Context.namespace.device; space = "" + $Context.namespace.space }; pid = [long]$record.pid; procStart = $record.procStart }
    $left = "; session " + $sid + " is LEFT RUNNING in pane " + $record.handle + " at the level asked for: press Enter in that pane, or close it with this process"
    # 6b. Ready for keys before the first one (Wait-HordeNodeReady). Not ready: nothing is typed, and the
    # session is kept only when its mode is proven right (Complete-HordeNodeNotReady).
    $ready = Wait-HordeNodeReady -Context $Context -Actor $actor -Target $term -Adapter $adapter -Handle $record.handle
    $record.ready = $ready.state
    if (Test-HordeNodeDeadlinePassed -Context $Context) { $limit = " (this spawn's own limit of " + $base.bounds.spawnSeconds + " s, inside the hub's wait, ran out)" }
    if ($ready.state -eq "not-ready") {
        return (Complete-HordeNodeNotReady -Context $Context -Base $base -Actor $actor -Target $term -Adapter $adapter -Record $record -Level $d.level -Expect $expect -Why ("not-ready: session " + $sid + " in pane " + $record.handle + " never showed it was ready for keys within " + $Context.bounds.readySeconds + " s" + $limit + ": " + $ready.reason))
    }
    if (Test-HordeNodeDeadlinePassed -Context $Context -Within $lineSeconds) {
        return (Complete-HordeNodeNotReady -Context $Context -Base $base -Actor $actor -Target $term -Adapter $adapter -Record $record -Level $d.level -Expect $expect -Why ("not-ready: session " + $sid + " in pane " + $record.handle + " was ready for keys with less than " + $lineSeconds + " s of this spawn's own limit of " + $base.bounds.spawnSeconds + " s left, too little to wait for a typed line's turn, so the no-op line was not typed"))
    }
    Write-HordeNodeSpawnRecord -Dir $Context.records -Record $record
    # 7. The mode, read back. Exactly the level asked for, or the session is not kept. First the fixed
    # line that asks for nothing, so the harness writes the record the mode is read from, proven a turn
    # (Submit-HordeNodeLine), and its turn waited for to end (Wait-HordeNodeTurnEnd). The mode is read
    # whether or not its turn came: a session at a level nobody asked for is ended either way.
    $record.noOpAt = (& $Context.now).ToUniversalTime().ToString("o")
    $noop = Submit-HordeNodeLine -Context $Context -Actor $actor -Target $term -Adapter $adapter -Handle $record.handle -SessionId $sid -Line $script:HordeNodeNoOpLine
    $record.noOp = $script:HordeNodeNoOpLine; $record.noOpTurn = $noop.state
    if ($noop.state -eq "unsent") { $record.noOp = ""; $record.noOpAt = "" }
    $noopEnd = [pscustomobject]@{ state = ""; reason = "" }
    if ($noop.state -eq "taken") { $noopEnd = Wait-HordeNodeTurnEnd -Context $Context -Adapter $adapter -SessionId $sid -Mark $noop.mark }
    $record.noOpEnd = $noopEnd.state
    Write-HordeNodeSpawnRecord -Dir $Context.records -Record $record
    $mode = $null
    if ($noop.state -ne "unsent") {
        $mode = Wait-HordeNodeUntil -Context $Context -Seconds $Context.bounds.modeSeconds -Probe { $m = & $adapter.readMode $sid $Context.environment; if ($m.state -eq "known") { $m } else { $null } }
    }
    if (Test-HordeNodeDeadlinePassed -Context $Context) { $limit = " (this spawn's own limit of " + $base.bounds.spawnSeconds + " s, inside the hub's wait, ran out)" }
    $why = ""
    if ($null -eq $mode) {
        $why = "the session's permission mode could not be read back within " + $Context.bounds.modeSeconds + " s" + $limit + ", so it is not kept (fail closed)"
        # The no-op line is what makes the harness write the mode's record; when it never became a turn,
        # that is the likelier cause, and the reason says so (review of PR 239, S2).
        if ($noop.state -ne "taken") { $why += "; the no-op line '" + $script:HordeNodeNoOpLine + "' never became a turn (" + $noop.state + ": " + $noop.reason + "), and a harness may write that record only with its first turn" }
    }
    elseif ("" + $mode.value -cne $d.level) { $why = "the session reports the level " + $mode.value + " and was asked for " + $d.level + ", so it is not kept" }
    if ($why -ne "") {
        # The close text goes only into a box whose no-op line became a turn: a line not proven taken may
        # still be in it, and the close text would run on into it (review of PR 239, S1 and its nit on an
        # unknown no-op); and only while it and its wait fit before this spawn's limit (S-a, and F's
        # re-check: begun just inside it, it ran 250 s). Otherwise the host ends the pane by its process.
        $gone = Stop-HordeNodeSession -Context $base -Actor $actor -Target $term -Adapter $adapter -Handle $record.handle -ProcessId $record.pid -ProcStart $record.procStart -SkipCloseText:($noop.state -ne "taken" -or (Test-HordeNodeDeadlinePassed -Context $Context -Within $closeTextSeconds))
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
    # A no-op line still in the box would run into the prompt line typed after it, so the prompt is not
    # typed, and the session is left running at the level asked for, for a person to press Enter.
    if ($noop.state -eq "not-taken") {
        $record.outcome = "prompt-not-submitted"; Write-HordeNodeSpawnRecord -Dir $Context.records -Record $record
        return (New-HordeNodeOutcome -State "failed" -SessionId $sid -Expect $expect -Reason ("prompt-not-submitted: the no-op line '" + $script:HordeNodeNoOpLine + "' was typed but never became a turn: " + $noop.reason + $limit + "; the prompt was not typed after it" + $left))
    }
    # The no-op's turn never ended: a prompt typed now would be queued behind it, not a turn (M1), so it is
    # not typed. The session runs at the level asked for, and a person can look at why it is busy.
    if ($noopEnd.state -eq "not-ended") {
        $screenSaid = Save-HordeNodeScreenReport -Context $Context -Actor $actor -Target $term -Record $record
        $record.outcome = "not-ready"; Write-HordeNodeSpawnRecord -Dir $Context.records -Record $record
        return (New-HordeNodeOutcome -State "failed" -SessionId $sid -Expect $expect -Reason ("not-ready: the no-op line's turn did not end within " + $Context.bounds.turnEndSeconds + " s" + $limit + " (" + $noopEnd.reason + "), so the prompt was not typed; " + $screenSaid + "; session " + $sid + " in pane " + $record.handle + " runs at the level asked for and is LEFT RUNNING: look at that pane, or close it with this process"))
    }
    # Too near this spawn's limit for the prompt line's wait: not typed (S-b). The mode is proven, so the
    # session is kept at the level asked for, without its work.
    if ($prompt -ne "" -and (Test-HordeNodeDeadlinePassed -Context $Context -Within $lineSeconds)) {
        $record.outcome = "not-ready"; Write-HordeNodeSpawnRecord -Dir $Context.records -Record $record
        return (New-HordeNodeOutcome -State "failed" -SessionId $sid -Expect $expect -Reason ("not-ready: less than " + $lineSeconds + " s of this spawn's own limit of " + $base.bounds.spawnSeconds + " s was left to wait for the prompt line's turn, so the prompt was not typed; session " + $sid + " in pane " + $record.handle + " runs at the level asked for, without its work, and is LEFT RUNNING: close it with this process"))
    }
    # 8. The work, now that the mode is proven. Done only when its line is seen as a turn (issue #214).
    $sent = Send-HordeNodePrompt -Context $Context -Actor $actor -Target $term -Adapter $adapter -Handle $record.handle -SessionId $sid -PromptDir $pd -Prompt $prompt
    $record.promptTurn = $sent.state
    if (Test-HordeNodeDeadlinePassed -Context $Context) { $limit = " (this spawn's own limit of " + $base.bounds.spawnSeconds + " s, inside the hub's wait, ran out)" }
    if ($sent.state -eq "unsent") {
        $record.outcome = "running-no-prompt"; Write-HordeNodeSpawnRecord -Dir $Context.records -Record $record
        return (New-HordeNodeOutcome -State "failed" -SessionId $sid -Expect $expect -Reason ($sent.reason + "; the session runs at the level asked for, without its work: close it with this process"))
    }
    if ($sent.state -eq "not-taken") {
        $record.outcome = "prompt-not-submitted"; Write-HordeNodeSpawnRecord -Dir $Context.records -Record $record
        return (New-HordeNodeOutcome -State "failed" -SessionId $sid -Expect $expect -Reason ("prompt-not-submitted: the line naming the prompt file was typed but never became a turn: " + $sent.reason + $limit + $left))
    }
    if ($sent.state -eq "unknown") {
        $record.outcome = "prompt-unconfirmed"; Write-HordeNodeSpawnRecord -Dir $Context.records -Record $record
        return (New-HordeNodeOutcome -State "failed" -SessionId $sid -Expect $expect -Reason ("prompt-unconfirmed: the line naming the prompt file was typed, and whether it became a turn cannot be told, so this is not reported done: " + $sent.reason + $left))
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
        # A typed line's turn (issue #214): receiptSeconds for it, then retrySeconds after the one extra
        # Enter, 30 s in all - a user line is written as it is submitted, before any model reply (the
        # file appeared with its first user line, the no-op note above), so this waits on the harness,
        # not the model. Measured live on 2026-10-14 (below).
        # The session ready for keys (readySeconds) and the no-op turn's end (turnEndSeconds), MEASURED
        # 2026-10-14 in an isolated terminal: the input box was drawn 2.8 s to 3.5 s after the pane started,
        # a one-line turn ended 1.8 s to 2.4 s after its user line, and a typed line's user row came 0.2 s to
        # 0.5 s after its Enter; each bound is many times that, for a slow or remote machine. spawnSeconds is
        # the one limit on all of it up to the decision (see A SPAWN HOLDS THE SERVE LOOP, which sums the
        # worst case to 220.25 s), hostCallSeconds the longest one terminal call of the host may take (the
        # first host's own call timeout), and clock is the wall clock every wait is measured on.
        bounds = [pscustomobject]@{ identifySeconds = 60; readySeconds = 60; modeSeconds = 60; closeSeconds = 20; receiptSeconds = 20; retrySeconds = 10; turnEndSeconds = 60; spawnSeconds = 130; hostCallSeconds = 20; pollMs = 500 }
        clock = { [double][System.Diagnostics.Stopwatch]::GetTimestamp() * 1000.0 / [double][System.Diagnostics.Stopwatch]::Frequency }
        workdirExists = { param($p) Test-Path -LiteralPath $p -PathType Container }
        note = $note
    }
}

function Invoke-HordeNodeServeSweep {
    # At serve start: delete the screens past their week (WHERE THE ROWS ARE KEPT), as a spawn does, so
    # a node that never spawns again does not keep them (F's re-check of round 5). The same folder rule
    # (Remove-HordeNodeOldScreens) under the same lock; a held lock or a failed sweep is an ALERT line and
    # stops nothing, since the next spawn sweeps again. Returns the lines for the serve log.
    param([Parameter(Mandatory = $true)]$Context)
    $lock = Enter-HordeNodeSpawnLock -Dir $Context.records
    if ($null -eq $lock) { return @("ALERT: old screens were not swept at serve start: another act holds the spawn lock; the next spawn sweeps them") }
    try {
        $n = Remove-HordeNodeOldScreens -Dir $Context.records -Now (& $Context.now)
        if ($n -gt 0) { return @("deleted " + $n + " screen(s) of sessions that were not ready, past their " + $script:HordeNodeScreenKeepDays + " days") }
        return @()
    } catch {
        return @("ALERT: this node could not delete its old screens of sessions that were not ready: " + $_.Exception.Message)
    } finally { $lock.Dispose() }
}

function Invoke-HordeNodeReconcile {
    # At serve start: settle every record a stopped node left "starting" (review of #104, F5). Its
    # process is looked for by pid and start time - the record's, or, when the node stopped before it
    # was proven, the harness's own record of the session, believed only when the live process has that
    # start time - and the record is marked running, with an ALERT (its mode was never read back), or
    # failed. First the screens past their week are swept (Invoke-HordeNodeServeSweep). Returns one line
    # per record settled, and one for the sweep when it deleted or failed, for the serve log.
    param([Parameter(Mandatory = $true)]$Context)
    $lines = New-Object System.Collections.ArrayList
    $dir = $Context.records
    $chain = Test-HordeNodeRecordsChain -HordeHome $Context.home -Dir $dir
    if ($chain -ne "") { [void]$lines.Add("ALERT: the spawn records were not reconciled: " + $chain); return $lines.ToArray() }
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return $lines.ToArray() }
    foreach ($l in @(Invoke-HordeNodeServeSweep -Context $Context)) { [void]$lines.Add($l) }
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter "*.json" -File)) {
        if ($f.Name.StartsWith(".")) { continue }
        $r = $null
        try { $r = ConvertFrom-HordeJson -Text ([System.IO.File]::ReadAllText($f.FullName)) } catch { [void]$lines.Add("ALERT: the spawn record " + $f.Name + " cannot be read, so it was not reconciled"); continue }
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
