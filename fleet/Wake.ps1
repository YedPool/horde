# fleet/Wake.ps1 - wake one hibernation: start its sessions again, laid out as they were, and tell each
# one why it is awake.
#
# THE ORDER, and why each step is where it is:
#   1. THE WAKING LOCK. <record folder>\waking.lock, created only if no file has that name
#      (FileMode.CreateNew, one step in the file system). A second wake of the same record is refused
#      while the first runs: two wakes would each see every session stopped and start each one twice.
#      The lock holds its owner's pid and process start time, and is removed when the wake ends,
#      whatever happened. A lock whose owner is not alive by the liveness rule's test (no such pid, or
#      the pid now belongs to a process that started at another time) is stale: a killed wake left it,
#      and the next wake takes it over and says so. A lock whose owner runs, or may (a start time that
#      cannot be read, a lock that names no owner), still refuses (review of PR 318). A dry run takes
#      no lock, refuses while a live one is held, and says when it would take over a stale one.
#   1b. THE RECORD IS READ AGAIN UNDER THE LOCK (second review of PR 318): a record read before the lock
#      may since have been changed by a wake that held it, and acting on - and writing back - the older
#      copy would start a session that wake already woke and drop its wokenAs and history.
#   2. NOTHING RUNNING IS STARTED AGAIN. Each session is checked by the harness adapter's liveness rule
#      (agents/<name>/Fleet.ps1, the restore guard's port): running is refused, and so is UNKNOWN - a
#      session nobody can prove is stopped is treated as running, because a conversation started twice
#      writes one transcript from two processes. Refused sessions become still-awake, with the reason.
#      The verdict is given the session's recorded process ({ pid; start }), so that very process still
#      running under another id counts as the session running (second review of PR 318, P1). And it is
#      asked AGAIN, from a fresh reading, right before each spawn (first review, finding 1): the first
#      reading can be minutes old by a late spawn.
#      HELD UNTIL -Retry (second review, finding 2): a session an earlier wake left waking (stopped part
#      way), or failed after its pane was started (a resume slower than the wait), may be loading in that
#      pane right now. It is not started again, and its state is left as it is, unless the run says
#      -Retry - and even then only once the liveness check finds it stopped.
#   3. ONE NEW WINDOW PER ORC, its wargs as tabs, laid out as saved (decided by M and F, 2026-10-16). A
#      session joins the window of its nearest owning orc in this record (its parent chain); one with
#      none gets a window of its own. Within a window, a session that shared a saved tab with one
#      started before it is split from that one's pane, on the side and in the share the saved geometry
#      shows; any other is a new tab, in saved tab order.
#   4. FREE MEMORY BEFORE EVERY SPAWN. At least 15 percent of physical memory must be free (the fleet's
#      rule for this machine, 2026-10-14: it sat at 6 to 12 percent free with several heavy runs, and
#      runs were reaped). Below it the wake STOPS: every session not yet started stays asleep and is
#      reported, and nothing is retried later on its own. A reading that FAILS (the query throws) stops
#      the wake the same way, said in words (first review, finding b), and what was printed is kept.
#   5. WAIT, BOUNDED, FOR EACH STARTED SESSION TO RUN. When its own id comes up, it is woken. When it
#      does not but a NEW running session sits in the same folder AND in the very pane this wake
#      spawned, the harness gave the resumed conversation a new id: that id is recorded as wokenAs.
#      Neither within the bound is failed. A pane that started but whose window could not be read back
#      is not failed (it runs, and is waited for), but the rest of its group is left asleep: without the
#      window, the next warg's tab would open a stray window of its own (second review of PR 318).
#   5b. THE REGISTRY ROW NAMES THE NEW PANE, or it is said (live finding of 2026-10-16: after a mass resume
#      the fleet registry still named the OLD pane of resumed sessions, so mail could be posted but could
#      not knock them). Within the same bounded wait, the woken id's row must name the pane this wake
#      spawned (Deps.RegistryPane, read only); if it does not, the session is still woken, noted
#      registry-stale, and the wake says mail will not knock it until its next turn. Nothing is written
#      to the registry.
#   6. ONE MAIL, through the messenger port (messengers/Port.ps1), never typed into the pane: "You were
#      woken from hibernation <id>. Read your PARKED-<label>.md and carry on." Its message id is made
#      from the hibernation and the session (core/TextUuid.ps1), so a repeated wake posts it once.
#   7. EXPECTED STARTS are written into the record BEFORE the first spawn: { hibernationId; from; to;
#      ids }, so Horde's restore source can later tell these starts from a restore it did not make (it
#      does not read them yet).
# EVERY OUTSIDE CALL COMES IN THROUGH -Deps (Invoke-HordeFleetWake): the clock, sleep, free memory, the
# two adapters, the opened terminal and the mail. A test hands in its own; the real ones are chosen in
# exactly one place, cli/commands/fleet.ps1. No step asks a person anything.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path $PSScriptRoot "Hibernation.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\TextUuid.ps1")

$script:HordeFleetWakeMinFreePercent = 15
# How long a started session has to show up running. MEASURED 2026-10-16, read only, on this machine's 13
# running sessions: each one's control file was created 1.4 to 23.4 s after its process started (median
# 7.6 s; the 23.4 s one was resumed while a dozen others started at once). The isolated end-to-end scenario
# (test/e2e/e2e-fleet.ps1) measures the spawn-to-running time of its stand-in, which is a
# lower bound: a stand-in does not read a transcript. 90 s stays, about four times the slowest real start
# seen, so one stuck pane still cannot hold the wake for minutes; a slower resume is failed and then held
# (HELD UNTIL -Retry, above), never started twice.
$script:HordeFleetWakeWaitSeconds = 90
$script:HordeFleetWakePollMs = 1500
$script:HordeFleetWakeMailTtlSeconds = 86400
$script:HordeFleetWakeLockName = "waking.lock"

function Get-HordeFleetProcessStart {
    # The real process lookup for the lock: start time of -ProcessId as FILETIME ticks text, "" when no
    # such process runs, "?" when it runs and its start cannot be read.
    param([Parameter(Mandatory = $true)][long]$ProcessId)
    $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($null -eq $p) { return "" }
    try { return ("" + $p.StartTime.ToFileTimeUtc()) } catch { return "?" }
}

function Get-HordeFleetLockOwner {
    # Is the owner of a waking lock alive? -Text is the lock's text, "pid <pid> start <ticks> at <utc>";
    # -ProcessStart looks a pid up ("" gone, "?" unreadable, ticks). Returns { stale; owner; reason }.
    # The rule is the liveness rule's (agents/<name>/Fleet.ps1): the owner is alive when its pid runs
    # with a start time within one second of the one written; gone, or a pid now owned by a process that
    # started at another time, is stale. Text that names no owner, or a start that cannot be read, is NOT
    # stale: an owner nobody can rule out still holds the record.
    param([AllowEmptyString()][string]$Text, [Parameter(Mandatory = $true)][scriptblock]$ProcessStart)
    $m = [regex]::Match($Text, '\Apid ([1-9][0-9]{0,9}) start ([0-9]{1,19})(\s|\z)')
    if (-not $m.Success) { return [pscustomobject]@{ stale = $false; owner = ""; reason = "it does not name its owner's process and start time, so whether its wake still runs cannot be told" } }
    $owner = $m.Groups[1].Value
    $now = "" + (& $ProcessStart ([long]$owner))
    if ($now -eq "") { return [pscustomobject]@{ stale = $true; owner = $owner; reason = ("its owner, pid " + $owner + ", is not running") } }
    $a = [long]0; $b = [long]0
    if ($now -cnotmatch '\A[0-9]{1,19}\z' -or -not [long]::TryParse($now, [ref]$a) -or -not [long]::TryParse($m.Groups[2].Value, [ref]$b)) { return [pscustomobject]@{ stale = $false; owner = $owner; reason = ("pid " + $owner + " runs and its start time cannot be read, so it may be the owner") } }
    if ([Math]::Abs($a - $b) -le 10000000) { return [pscustomobject]@{ stale = $false; owner = $owner; reason = ("its owner, pid " + $owner + ", is running") } }
    return [pscustomobject]@{ stale = $true; owner = $owner; reason = ("pid " + $owner + " now belongs to a process that started at another time") }
}

function Get-HordeFleetSince {
    # From when a running session could be -Session under a new id: its last exit in the history, or,
    # with none, when the hibernation was taken - a session already running then ran beside it. NO CODE
    # WRITES "exited" YET: hibernate (slice 2), which parks and stops sessions, will. Until then this is
    # always the time the hibernation was taken.
    param([Parameter(Mandatory = $true)]$Session, [Parameter(Mandatory = $true)]$Record)
    $exits = @(@($Session.history) | Where-Object { "" + $_.state -ceq "exited" })
    $text = $(if ($exits.Count -gt 0) { "" + $exits[-1].at } else { "" + $Record.createdAt })
    $at = [datetime]::MinValue
    if ([datetime]::TryParseExact($text, "yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture, ([System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal), [ref]$at)) { return $at }
    return $null
}

function Get-HordeFleetWakeBody {
    # The mail a woken session gets.
    param([Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)][string]$Label)
    return ("You were woken from hibernation " + $Id + ". Read your PARKED-" + $Label + ".md and carry on.")
}

function New-HordeFleetWakeSender {
    # Who a wake's mail is from: the session that ran the wake, when it knows its own id (-SelfSessionId, an
    # answer of core/Identity.ps1's Get-HordeSelfSessionId); else the reserved system sender "horde"
    # (messengers/Port.ps1, from.system). Never the master's label M: a wake started from the phone or a
    # service is not M's act, and nothing sends as M unless M's own session ran the command (third review of
    # PR 318). The sessionId member is required by the port; a system sender's is never shown or passed on.
    param([Parameter(Mandatory = $true)][string]$DeviceId, [Parameter(Mandatory = $true)]$SelfSessionId)
    if ($SelfSessionId.state -ceq "known") { return [pscustomobject]@{ deviceId = $DeviceId; sessionId = "" + $SelfSessionId.value } }
    return [pscustomobject]@{ deviceId = $DeviceId; sessionId = "horde-fleet-wake"; system = "horde" }
}

function Get-HordeFleetWakeMessageId {
    # The mail's message id: the same for the same hibernation and session, so a repeated post is one.
    param([Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)][string]$SessionId)
    return (ConvertTo-HordeTextUuid -Text ("horde-fleet-wake/" + $Id + "/" + $SessionId))
}

function Get-HordeFleetSessionName {
    # A session as a person reads it in the output: its label and short id.
    param([Parameter(Mandatory = $true)]$Session)
    $l = "" + (Get-HordeFleetMember $Session "label")
    $short = ("" + $Session.sessionId).Substring(0, 8)
    if ($l -eq "") { return $short }
    return ($l + " (" + $short + ")")
}

function Get-HordeFleetMember {
    # A member of a parsed record that may be left out, or "" / $null.
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Get-HordeFleetCurrentId {
    # The id a session runs under now: the one it was woken as, else its own.
    param([Parameter(Mandatory = $true)]$Session)
    $w = "" + (Get-HordeFleetMember $Session "wokenAs")
    if ($w -ne "") { return $w }
    return ("" + $Session.sessionId)
}

function ConvertTo-HordeFleetFolder {
    # A folder as text that compares the way Windows compares folders: slash direction, case, a trailing
    # separator and a leading slash before a drive do not matter.
    param([AllowEmptyString()][string]$Path)
    $n = $Path.Replace([string][char]92, "/")
    if ($n -cmatch '\A/[A-Za-z]:') { $n = $n.Substring(1) }
    return $n.TrimEnd("/").ToLowerInvariant()
}

function Get-HordeFleetGroups {
    # The windows a wake opens: one per orc, holding the sessions of -Sessions whose nearest owning orc in
    # this record it is - whether or not that orc is itself being woken, so an orc left running or not
    # chosen does not scatter its wargs into windows of their own. A session with no orc above it is a
    # window of its own. Each group lists its orc first when the orc is being woken, then the rest in
    # saved order (same saved window as the orc first, by tab, then top, then left; then by label). -All
    # is every session of the record, for walking parent chains through sessions not being woken.
    param([Parameter(Mandatory = $true)][object[]]$Sessions, [object[]]$All = $null)
    if ($null -eq $All) { $All = $Sessions }
    $byId = @{}
    foreach ($s in @($All)) { $byId["" + $s.sessionId] = $s }
    $headOf = @{}
    foreach ($s in @($Sessions)) {
        $head = $null
        if ("" + $s.role -ceq "orc") { $head = "" + $s.sessionId }
        else {
            $seen = @{}
            $p = "" + (Get-HordeFleetMember $s "parent")
            while ($p -ne "" -and $byId.ContainsKey($p) -and -not $seen.ContainsKey($p)) {
                $seen[$p] = $true
                if ("" + $byId[$p].role -ceq "orc") { $head = $p; break }
                $p = "" + (Get-HordeFleetMember $byId[$p] "parent")
            }
            if ($null -eq $head) { $head = "" + $s.sessionId }
        }
        $headOf["" + $s.sessionId] = $head
    }
    $groups = New-Object System.Collections.ArrayList
    $heads = New-Object System.Collections.ArrayList
    foreach ($s in @($Sessions)) { $h = $headOf["" + $s.sessionId]; if (-not $heads.Contains($h)) { [void]$heads.Add($h) } }
    # Windows open in the record's order of their orcs, not in the order a warg happened to come first.
    $order = @{}
    $i = 0
    foreach ($s in @($All)) { $order["" + $s.sessionId] = $i; $i++ }
    $sortedHeads = @($heads | Sort-Object -Property @{ Expression = { if ($order.ContainsKey($_)) { $order[$_] } else { [int]::MaxValue } } })
    foreach ($h in $sortedHeads) {
        $headSession = $byId[$h]
        $headWin = "" + (Get-HordeFleetMember (Get-HordeFleetMember $headSession "placement") "windowKey")
        $first = @($Sessions | Where-Object { "" + $_.sessionId -ceq $h })
        $members = @($Sessions | Where-Object { $headOf["" + $_.sessionId] -ceq $h -and "" + $_.sessionId -cne $h })
        $sorted = @($members | Sort-Object -Property @(
            @{ Expression = { $pl = Get-HordeFleetMember $_ "placement"; if ($null -ne $pl -and $headWin -ne "" -and "" + $pl.windowKey -ceq $headWin) { 0 } else { 1 } } },
            @{ Expression = { $pl = Get-HordeFleetMember $_ "placement"; if ($null -ne $pl) { [int]$pl.tabIndex } else { 9999 } } },
            @{ Expression = { $pl = Get-HordeFleetMember $_ "placement"; if ($null -ne $pl) { [int]$pl.top } else { 0 } } },
            @{ Expression = { $pl = Get-HordeFleetMember $_ "placement"; if ($null -ne $pl) { [int]$pl.left } else { 0 } } },
            @{ Expression = { "" + (Get-HordeFleetMember $_ "label") } }))
        [void]$groups.Add([pscustomobject]@{ head = $headSession; sessions = @($first + $sorted) })
    }
    return @($groups)
}

function Get-HordeFleetSplit {
    # How -Session's saved pane sat beside -First's in their shared saved tab: { direction; percent },
    # direction right when it began at or past the first's right edge, bottom when at or past its bottom
    # edge, else right; percent its share of the two along that axis, kept between 10 and 90.
    param([Parameter(Mandatory = $true)]$Session, [Parameter(Mandatory = $true)]$First)
    $a = $First.placement; $b = $Session.placement
    $dir = "right"
    if ([int]$b.left -lt ([int]$a.left + [int]$a.cols) -and [int]$b.top -ge ([int]$a.top + [int]$a.rows)) { $dir = "bottom" }
    $mine = [int]$b.cols; $theirs = [int]$a.cols
    if ($dir -ceq "bottom") { $mine = [int]$b.rows; $theirs = [int]$a.rows }
    $pct = 50
    if (($mine + $theirs) -gt 0) { $pct = [int][Math]::Round(100.0 * $mine / ($mine + $theirs)) }
    if ($pct -lt 10) { $pct = 10 }
    if ($pct -gt 90) { $pct = 90 }
    return [pscustomobject]@{ direction = $dir; percent = $pct }
}

function New-HordeFleetWakeStep {
    # The spawn request for one session, given what this group has started so far (-Started: saved tab
    # key -> { session; pane }, and -Window, the group's window, "" before its first). Pure.
    param([Parameter(Mandatory = $true)]$Session, [Parameter(Mandatory = $true)][string]$Line, $Environment = @{},
          [AllowEmptyString()][string]$Window = "", [hashtable]$Started = @{}, [string]$WindowName = "")
    $req = [ordered]@{ mode = "window"; cwd = "" + $Session.cwd; line = $Line; environment = $Environment; window = ""; pane = ""; direction = ""; percent = "" }
    if ($Window -ne "" -or $WindowName -ne "") {
        $req.mode = "tab"; $req.window = $(if ($Window -ne "") { $Window } else { $WindowName })
        $pl = Get-HordeFleetMember $Session "placement"
        if ($null -ne $pl) {
            $key = "" + $pl.windowKey + "#" + $pl.tabIndex
            if ($Started.ContainsKey($key)) {
                $first = $Started[$key]
                $split = Get-HordeFleetSplit -Session $Session -First $first.session
                $req.mode = "split"; $req.window = ""; $req.pane = "" + $first.pane; $req.direction = $split.direction; $req.percent = "" + $split.percent
            }
        }
    }
    return [pscustomobject]$req
}

function Find-HordeFleetWokenId {
    # Has session -Session come up? Returns { found; id; rotated }. Its own id running is found as
    # itself. Otherwise a running session that is not in -Known (every id this record names, and every
    # one running before the wake), sits in the session's folder, and runs in -Pane (by -PaneOf) is the
    # same conversation under a new id. A pane that cannot be read is never taken as a match.
    param([Parameter(Mandatory = $true)]$Agent, [Parameter(Mandatory = $true)]$Snapshot, [Parameter(Mandatory = $true)]$Session,
          [AllowEmptyString()][string]$Pane, [string[]]$Known = @(), [scriptblock]$PaneOf = $null)
    $id = Get-HordeFleetCurrentId -Session $Session
    $v = & $Agent.verdict $Snapshot $id ("" + $Session.cwd) $Known
    if ("" + $v.state -ceq "running") { return [pscustomobject]@{ found = $true; id = $id; rotated = $false } }
    if ($null -eq $PaneOf -or $Pane -eq "") { return [pscustomobject]@{ found = $false; id = ""; rotated = $false } }
    $want = ConvertTo-HordeFleetFolder -Path ("" + $Session.cwd)
    foreach ($r in @(& $Agent.running $Snapshot)) {
        if ($null -eq $r -or @($Known) -ccontains ("" + $r.sessionId)) { continue }
        if ((ConvertTo-HordeFleetFolder -Path ("" + $r.cwd)) -cne $want) { continue }
        $p = & $PaneOf $r.pid
        if ($null -ne $p -and $p.state -eq "known" -and ("" + $p.value) -ceq $Pane) { return [pscustomobject]@{ found = $true; id = "" + $r.sessionId; rotated = $true } }
    }
    return [pscustomobject]@{ found = $false; id = ""; rotated = $false }
}

function Invoke-HordeFleetWake {
    # The whole of `horde fleet wake`. Returns { id; lines; outcomes }, lines being what is printed, and
    # outcomes each { sessionId; label; outcome; reason } with outcome still-awake, woken, failed, asleep
    # (left by the memory gate, or after a window that could not be read back), held (an earlier wake's
    # pane may be loading it; -Retry) or planned (-DryRun). Throws, changing nothing, when the record cannot be
    # read, another wake holds it, or -Only names a label it does not hold.
    # -Deps: Now (), Sleep (ms), FreePercent () -> number, Agent, Host (fleet/Port.ps1), Post ($sessionId,
    # $label, $body, $messageId) -> answer, and optionally WaitSeconds, PollMs and RegistryPane ($sessionId)
    # -> answer known pane id text of that session's fleet registry row.
    param([Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)]$Deps, [switch]$DryRun, [string[]]$Only = @(), [string]$HordeHome = (Get-HordeHome), [switch]$Retry)
    $read = Read-HordeFleetRecord -Id $Id -HordeHome $HordeHome
    if ($read.state -ne "known") { throw $read.reason }
    $record = $read.value
    $dir = Join-Path (Get-HordeFleetHibernationsDir -HordeHome $HordeHome) $Id
    $lockPath = Join-Path $dir $script:HordeFleetWakeLockName
    $waitSeconds = $script:HordeFleetWakeWaitSeconds
    if ($null -ne $Deps.PSObject.Properties["WaitSeconds"]) { $waitSeconds = [int]$Deps.WaitSeconds }
    $pollMs = $script:HordeFleetWakePollMs
    if ($null -ne $Deps.PSObject.Properties["PollMs"]) { $pollMs = [int]$Deps.PollMs }
    $lines = New-Object System.Collections.ArrayList
    $outcomes = New-Object System.Collections.ArrayList
    $say = { param($t) [void]$lines.Add($t) }
    $tell = { param($s, $o, $r) [void]$outcomes.Add([pscustomobject]@{ sessionId = "" + $s.sessionId; label = "" + (Get-HordeFleetMember $s "label"); outcome = $o; reason = $r }) }

    $procStart = $(if ($null -ne $Deps.PSObject.Properties["ProcessStart"]) { $Deps.ProcessStart } else { { param($p) Get-HordeFleetProcessStart -ProcessId $p } })
    $self = $(if ($null -ne $Deps.PSObject.Properties["Self"]) { & $Deps.Self } else { [pscustomobject]@{ pid = $PID; start = (Get-HordeFleetProcessStart -ProcessId $PID) } })
    # A LOCK THAT COULD NEVER BE TAKEN OVER is not taken (first review of PR 318, finding c): without its
    # own start time this wake would write "start ?", which every later wake must read as a live owner.
    if (-not $DryRun -and "" + $self.start -cnotmatch '\A[0-9]{1,19}\z') { throw ("this wake cannot read its own start time (pid " + $self.pid + "), so a lock it took could never be told stale; nothing was started") }
    # 1. THE LOCK names its owner; a stale one (owner gone, or its pid reused) is taken over and said.
    $staleNote = ""
    if (Test-Path -LiteralPath $lockPath) {
        $lockText = ""
        try { $lockText = Read-HordeSharedText -Path $lockPath } catch { $lockText = "" }
        $owner = Get-HordeFleetLockOwner -Text $lockText -ProcessStart $procStart
        if (-not $owner.stale) { throw ("hibernation " + $Id + " is being woken already: " + $lockPath + " is held and " + $owner.reason) }
        $staleNote = $(if ($DryRun) { "would take over" } else { "took over" }) + " a stale waking lock of pid " + $owner.owner + ": " + $owner.reason
        # THIS DELETE RELIES ON WINDOWS REFUSING to delete a file another process holds open with
        # FileShare.Read, as every live wake holds its lock (probed on PowerShell 5.1 by the review of PR
        # 318: Remove-Item of a held lock threw). So a lock wrongly judged stale cannot be removed from
        # under a wake that still runs; the CreateNew below is the gate either way.
        if (-not $DryRun) { Remove-Item -LiteralPath $lockPath -Force -ErrorAction Stop }
    }
    $onlyLabels = @($Only | Where-Object { "" + $_ -ne "" })
    $choose = { param($rec)
        $all = @($rec.sessions)
        if ($onlyLabels.Count -eq 0) { return $all }
        foreach ($l in $onlyLabels) { if (@($all | Where-Object { "" + (Get-HordeFleetMember $_ "label") -ceq $l }).Count -eq 0) { throw ("hibernation " + $Id + " holds no session labelled " + $l + ", so nothing was woken") } }
        return @($all | Where-Object { $onlyLabels -ccontains ("" + (Get-HordeFleetMember $_ "label")) })
    }
    $sessions = @(& $choose $record)
    $lockStream = $null
    if (-not $DryRun) {
        try { $lockStream = New-Object System.IO.FileStream($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read) }
        catch { throw ("hibernation " + $Id + " is being woken already: its lock " + $lockPath + " could not be created (" + $_.Exception.Message + ")") }
    }
    try {
        if ($null -ne $lockStream) {
            $b = [System.Text.Encoding]::ASCII.GetBytes("pid " + $self.pid + " start " + $self.start + " at " + (Format-HordeFleetTime -At (& $Deps.Now)) + "`n")
            $lockStream.Write($b, 0, $b.Length); $lockStream.Flush($true)
            # 1b. Read again, under the lock.
            $again = Read-HordeFleetRecord -Id $Id -HordeHome $HordeHome
            if ($again.state -ne "known") { throw $again.reason }
            $record = $again.value
            $sessions = @(& $choose $record)
        }
        $agent = $Deps.Agent
        $snapshot = & $agent.snapshot
        $runningBefore = @(@(& $agent.running $snapshot) | ForEach-Object { "" + $_.sessionId })
        $recordIds = @(@($record.sessions) | ForEach-Object { "" + $_.sessionId; $w = "" + (Get-HordeFleetMember $_ "wokenAs"); if ($w -ne "") { $w } })
        $known = @($recordIds + $runningBefore)
        $now = & $Deps.Now
        # 2. Nothing running is started again.
        $spawnable = New-Object System.Collections.ArrayList
        $refused = New-Object System.Collections.ArrayList
        $heldBack = New-Object System.Collections.ArrayList
        foreach ($s in $sessions) {
            # HELD UNTIL -Retry (header, 2): its state is left as it is, so the next wake holds it too.
            $last = @($s.history)[-1]
            $holdWhy = ""
            if ("" + $s.state -ceq "waking") { $holdWhy = "an earlier wake was starting it and never saw it come up (it may have been stopped part way), so a pane may be loading it now" }
            elseif ("" + $s.state -ceq "failed" -and "" + (Get-HordeFleetMember $last "pane") -ne "") { $holdWhy = "an earlier wake started it in pane " + (Get-HordeFleetMember $last "pane") + " and did not see it come up, so it may still be loading there" }
            if ($holdWhy -ne "" -and -not $Retry) { [void]$heldBack.Add([pscustomobject]@{ session = $s; reason = $holdWhy }); continue }
            # Every id of this record is passed as one that cannot be this sleeper's new id (orcs and their
            # wargs share folders), with the moment before which nothing running can be either.
            $v = & $agent.verdict $snapshot (Get-HordeFleetCurrentId -Session $s) ("" + $s.cwd) $recordIds (Get-HordeFleetSince -Session $s -Record $record) (Get-HordeFleetMember $s "process")
            if ("" + $v.state -ceq "stopped") { [void]$spawnable.Add($s) }
            else {
                $why = $(if ("" + $v.state -ceq "running") { "still running: " + $v.reason } else { "may be running, so it is left alone: " + $v.reason })
                [void]$refused.Add([pscustomobject]@{ session = $s; reason = $why })
            }
        }
        & $say ("hibernation " + $Id + ": " + @($sessions).Count + " session(s); " + $spawnable.Count + " to wake, " + $refused.Count + " refused" + $(if ($heldBack.Count -gt 0) { ", " + $heldBack.Count + " held" } else { "" }) + $(if ($DryRun) { " (dry run: nothing is changed)" } else { "" }))
        if ($staleNote -ne "") { & $say ("  " + $staleNote) }
        foreach ($hb in $heldBack) {
            & $say ("  held " + (Get-HordeFleetSessionName -Session $hb.session) + ": " + $hb.reason + "; wake it again with -Retry once you know it is not running there")
            & $tell $hb.session "held" $hb.reason
        }
        foreach ($r in $refused) {
            & $say ("  refused " + (Get-HordeFleetSessionName -Session $r.session) + ": " + $r.reason)
            if (-not $DryRun) { Add-HordeFleetState -Session $r.session -State "still-awake" -At $now -Reason $r.reason }
            & $tell $r.session "still-awake" $r.reason
        }
        $groups = @()
        if ($spawnable.Count -gt 0) { $groups = @(Get-HordeFleetGroups -Sessions @($spawnable) -All @($record.sessions)) }
        $scrub = @{}
        $scrubbed = & $agent.scrub
        if ($null -ne $scrubbed) { foreach ($k in @($scrubbed.Keys)) { $scrub[$k] = $scrubbed[$k] } }

        if ($DryRun) {
            foreach ($g in $groups) {
                & $say ("  window for " + (Get-HordeFleetSessionName -Session $g.head) + ":")
                $started = @{}; $named = ""
                foreach ($s in $g.sessions) {
                    $req = New-HordeFleetWakeStep -Session $s -Line (& $agent.resumeLine (Get-HordeFleetCurrentId -Session $s)) -Environment $scrub -WindowName $named -Started $started
                    & $say ("    " + (Get-HordeFleetSessionName -Session $s) + ": " + (& $Deps.Host.describe $req))
                    if ($named -eq "") { $named = "" + (Get-HordeFleetMember $s "label"); if ($named -eq "") { $named = ("" + $s.sessionId).Substring(0, 8) } }
                    $pl = Get-HordeFleetMember $s "placement"
                    if ($null -ne $pl) { $k = "" + $pl.windowKey + "#" + $pl.tabIndex; if (-not $started.ContainsKey($k)) { $started[$k] = [pscustomobject]@{ session = $s; pane = (Get-HordeFleetSessionName -Session $s) } } }
                    & $tell $s "planned" ""
                }
            }
            $free = $null
            try { $free = [double](& $Deps.FreePercent) } catch { $free = $null; & $say ("  free memory could not be read (" + $_.Exception.Message + "); a wake would stop at its first spawn") }
            if ($null -ne $free) { & $say ("  free memory now " + [Math]::Round($free, 1) + " percent; each spawn needs at least " + $script:HordeFleetWakeMinFreePercent) }
            return [pscustomobject]@{ id = $Id; lines = @($lines); outcomes = @($outcomes) }
        }

        # 7. Expected starts, before anything starts.
        $spawnIds = @($spawnable | ForEach-Object { Get-HordeFleetCurrentId -Session $_ })
        if ($spawnIds.Count -gt 0) {
            $to = $now.AddSeconds([double](($waitSeconds + 30) * $spawnIds.Count + 60))
            $exp = [pscustomobject][ordered]@{ hibernationId = $Id; from = (Format-HordeFleetTime -At $now); to = (Format-HordeFleetTime -At $to); ids = @($spawnIds) }
            $record | Add-Member -NotePropertyName "expectedStarts" -NotePropertyValue $exp -Force
        }
        [void](Write-HordeFleetRecord -Dir $dir -Record $record)
        if ($spawnIds.Count -eq 0) { & $say "  nothing to wake"; return [pscustomobject]@{ id = $Id; lines = @($lines); outcomes = @($outcomes) } }

        $opened = & $Deps.Host.open
        if ($null -eq $opened -or $opened.state -ne "known") { throw ("no terminal to wake into, so nothing was started: " + $(if ($null -ne $opened) { $opened.reason } else { "the host answered nothing" })) }
        $term = $opened.value
        $stopped = $false
        $startedIds = New-Object System.Collections.ArrayList
        foreach ($g in $groups) {
            $window = ""; $started = @{}; $groupStop = ""
            & $say ("  window for " + (Get-HordeFleetSessionName -Session $g.head) + ":")
            foreach ($s in $g.sessions) {
                $name = Get-HordeFleetSessionName -Session $s
                if ($stopped) { & $say ("    " + $name + ": left asleep (the wake stopped on free memory)"); & $tell $s "asleep" "the wake stopped on free memory"; continue }
                if ($groupStop -ne "") { & $say ("    " + $name + ": left asleep - " + $groupStop); & $tell $s "asleep" $groupStop; continue }
                # 4. Free memory before every spawn; a reading that fails stops the wake the same way.
                $free = $null; $readFailed = ""
                try { $free = [double](& $Deps.FreePercent) } catch { $readFailed = "" + $_.Exception.Message }
                if ($readFailed -ne "" -or ($null -ne $free -and $free -lt $script:HordeFleetWakeMinFreePercent)) {
                    $stopped = $true
                    $why = $(if ($readFailed -ne "") { "free memory could not be read (" + $readFailed + ")" } else { "free memory is " + [Math]::Round($free, 1) + " percent, under " + $script:HordeFleetWakeMinFreePercent }) + "; the wake stopped here and the rest stay asleep"
                    & $say ("    " + $name + ": left asleep - " + $why)
                    & $tell $s "asleep" $why
                    continue
                }
                $cur = Get-HordeFleetCurrentId -Session $s
                # 2, AGAIN: A FRESH READING RIGHT BEFORE THIS SPAWN (review of PR 318, finding 1). Every
                # earlier session of the wake was waited for, up to the wake wait each, so the first reading
                # can be minutes old; a sleeper resumed by hand meanwhile would be started a second time.
                # The ids this wake has already started cannot be this sleeper under a new id either.
                $fresh = & $agent.snapshot
                $recheck = & $agent.verdict $fresh $cur ("" + $s.cwd) @($recordIds + @($startedIds)) (Get-HordeFleetSince -Session $s -Record $record) (Get-HordeFleetMember $s "process")
                if ("" + $recheck.state -cne "stopped") {
                    $why = $(if ("" + $recheck.state -ceq "running") { "still running: " + $recheck.reason } else { "may be running, so it is left alone: " + $recheck.reason })
                    Add-HordeFleetState -Session $s -State "still-awake" -At (& $Deps.Now) -Reason $why
                    [void](Write-HordeFleetRecord -Dir $dir -Record $record)
                    & $say ("    " + $name + ": refused on a fresh reading before its spawn - " + $why); & $tell $s "still-awake" $why
                    continue
                }
                $req = New-HordeFleetWakeStep -Session $s -Line (& $agent.resumeLine $cur) -Environment $scrub -Window $window -Started $started
                Add-HordeFleetState -Session $s -State "waking" -At (& $Deps.Now)
                [void](Write-HordeFleetRecord -Dir $dir -Record $record)
                # THE TERMINAL RESTORE'S MARKER GOES NOW, after the last liveness check and just before
                # the spawn (the host's Release; fleet/Port.ps1): a session started again must not stay
                # barred from the next restore. Only this session's. A marker that will not go does not stop
                # the wake - the restore would refuse the session, the safe side - but it is said.
                $hostRelease = $(if ($null -ne $Deps.Host.PSObject.Properties["release"]) { $Deps.Host.release } else { $null })
                if ($null -ne $hostRelease) {
                    foreach ($rid in @(@(("" + $s.sessionId), $cur) | Select-Object -Unique)) {
                        $rel = $null
                        try { $rel = & $hostRelease $rid } catch { $rel = New-HordeUnknown -Reason ("" + $_.Exception.Message) }
                        if ($null -eq $rel -or $rel.state -ne "known") { & $say ("    " + $name + ": its no-restore marker could not be removed (" + $(if ($null -ne $rel) { $rel.reason } else { "the terminal answered nothing" }) + "); the wake goes on, and a terminal restore may still refuse it") }
                    }
                }
                $sp = & $term.spawn $req
                if ($null -eq $sp -or $sp.state -ne "known") {
                    # ONLY A REQUEST REFUSED BEFORE ANY CALL TO THE TERMINAL (the host answers absent) is "not
                    # started". Every other answer - a 20 s cli timeout (exit -1, process killed), a failed
                    # call, a reply that is not a pane id - may have made the pane (third review of PR 318, P1:
                    # the next wake started the session a second time), so it is held like a pane that started
                    # and was not seen: failed with the pane "?", until -Retry, which still runs the liveness check.
                    if ($null -ne $sp -and $sp.state -ceq "absent") {
                        $why = "its pane was not started: " + $sp.reason
                        Add-HordeFleetState -Session $s -State "failed" -At (& $Deps.Now) -Reason $why
                    } else {
                        $why = "its pane may have started, so it is held until -Retry: " + $(if ($null -ne $sp) { $sp.reason } else { "the terminal answered nothing" })
                        Add-HordeFleetState -Session $s -State "failed" -At (& $Deps.Now) -Reason $why -Pane "?"
                    }
                    [void](Write-HordeFleetRecord -Dir $dir -Record $record)
                    & $say ("    " + $name + ": failed - " + $why); & $tell $s "failed" $why
                    continue
                }
                if ($window -eq "") { $window = "" + $sp.value.window }
                # The pane runs, but without its window the next warg's tab would open a window of its own:
                # this one is still waited for, and the rest of its group stays asleep (header, 5).
                if ($window -eq "") { $groupStop = "the window of " + $name + "'s pane " + $sp.value.pane + " could not be read back, so the rest of its group was not placed" }
                $pl = Get-HordeFleetMember $s "placement"
                if ($null -ne $pl) { $k = "" + $pl.windowKey + "#" + $pl.tabIndex; if (-not $started.ContainsKey($k)) { $started[$k] = [pscustomobject]@{ session = $s; pane = "" + $sp.value.pane } } }
                # 5. Wait, bounded, for it to run.
                $found = $null
                $deadline = (& $Deps.Now).AddSeconds($waitSeconds)
                while ($true) {
                    $snap = & $agent.snapshot
                    $found = Find-HordeFleetWokenId -Agent $agent -Snapshot $snap -Session $s -Pane ("" + $sp.value.pane) -Known @($known + @($startedIds)) -PaneOf $term.paneOf
                    if ($found.found -or (& $Deps.Now) -ge $deadline) { break }
                    & $Deps.Sleep $pollMs
                }
                if (-not $found.found) {
                    $why = "its pane " + $sp.value.pane + " was started, but it was not seen running within " + $waitSeconds + " s"
                    Add-HordeFleetState -Session $s -State "failed" -At (& $Deps.Now) -Reason $why -Pane ("" + $sp.value.pane)
                    [void](Write-HordeFleetRecord -Dir $dir -Record $record)
                    & $say ("    " + $name + ": failed - " + $why); & $tell $s "failed" $why
                    continue
                }
                [void]$startedIds.Add($found.id)
                if ($found.rotated) { $s | Add-Member -NotePropertyName "wokenAs" -NotePropertyValue $found.id -Force }
                # 5b. The registry row of the woken id names the spawned pane, within the same bound.
                $regNote = ""
                $regRead = $(if ($null -ne $Deps.PSObject.Properties["RegistryPane"]) { $Deps.RegistryPane } else { $null })
                if ($null -ne $regRead) {
                    $rowPane = ""
                    while ($true) {
                        $rp = $null
                        try { $rp = & $regRead $found.id } catch { $rp = $null }
                        $rowPane = $(if ($null -ne $rp -and $rp.state -eq "known") { "" + $rp.value } else { "" })
                        if ($rowPane -ceq ("" + $sp.value.pane) -or (& $Deps.Now) -ge $deadline) { break }
                        & $Deps.Sleep $pollMs
                    }
                    if ($rowPane -cne ("" + $sp.value.pane)) { $regNote = "registry-stale: the fleet registry still names " + $(if ($rowPane -ne "") { "pane " + $rowPane } else { "no pane" }) + " for it, not pane " + $sp.value.pane + " it was woken in, so its mail is posted but will not knock it until its next turn" }
                }
                # 6. One mail.
                $label = "" + (Get-HordeFleetMember $s "label")
                if ($label -eq "") { $label = ("" + $s.sessionId).Substring(0, 8) }
                $posted = & $Deps.Post $found.id ("" + (Get-HordeFleetMember $s "label")) (Get-HordeFleetWakeBody -Id $Id -Label $label) (Get-HordeFleetWakeMessageId -Id $Id -SessionId ("" + $s.sessionId))
                $as = $(if ($found.rotated) { " as " + $found.id } else { "" })
                if ($null -eq $posted -or $posted.state -ne "known") {
                    $why = "it runs again" + $as + ", but its wake mail was not posted: " + $(if ($null -ne $posted) { $posted.reason } else { "the messenger answered nothing" })
                    Add-HordeFleetState -Session $s -State "failed" -At (& $Deps.Now) -Reason $why -Pane ("" + $sp.value.pane)
                    [void](Write-HordeFleetRecord -Dir $dir -Record $record)
                    & $say ("    " + $name + ": failed - " + $why); & $tell $s "failed" $why
                    continue
                }
                $note = $(if ($found.rotated) { "it came back under a new id, " + $found.id } else { "" })
                if ($regNote -ne "") { $note = $regNote + $(if ($note -ne "") { "; " + $note } else { "" }) }
                Add-HordeFleetState -Session $s -State "woken" -At (& $Deps.Now) -Reason $note
                [void](Write-HordeFleetRecord -Dir $dir -Record $record)
                & $say ("    " + $name + ": woken in pane " + $sp.value.pane + $as + ", and told" + $(if ($regNote -ne "") { "; " + $regNote } else { "" }))
                & $tell $s "woken" $note
            }
        }
        return [pscustomobject]@{ id = $Id; lines = @($lines); outcomes = @($outcomes) }
    } finally {
        if ($null -ne $lockStream) { $lockStream.Dispose(); Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue }
    }
}
