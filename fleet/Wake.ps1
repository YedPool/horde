# fleet/Wake.ps1 - wake one hibernation: start its sessions again, laid out as they were, and tell each
# one why it is awake.
#
# THE ORDER, and why each step is where it is:
#   1. THE WAKING LOCK. <record folder>\waking.lock, created only if no file has that name
#      (FileMode.CreateNew, one step in the file system). A second wake of the same record is refused
#      while the first runs: two wakes would each see every session stopped and start each one twice.
#      The lock is removed when the wake ends, whatever happened; a wake that was killed leaves it, and
#      the refusal names the file, to be deleted once no wake runs. A dry run takes no lock and refuses
#      while one is held, because its plan would be wrong.
#   2. NOTHING RUNNING IS STARTED AGAIN. Each session is checked by the harness adapter's liveness rule
#      (agents/<name>/Fleet.ps1, the restore guard's port): running is refused, and so is UNKNOWN - a
#      session nobody can prove is stopped is treated as running, because a conversation started twice
#      writes one transcript from two processes. Refused sessions become still-awake, with the reason.
#   3. ONE NEW WINDOW PER ORC, its wargs as tabs, laid out as saved (decided by M and F, 2026-10-16). A
#      session joins the window of its nearest owning orc in this record (its parent chain); one with
#      none gets a window of its own. Within a window, a session that shared a saved tab with one
#      started before it is split from that one's pane, on the side and in the share the saved geometry
#      shows; any other is a new tab, in saved tab order.
#   4. FREE MEMORY BEFORE EVERY SPAWN. At least 15 percent of physical memory must be free (the fleet's
#      rule for this machine, 2026-10-14: it sat at 6 to 12 percent free with several heavy runs, and
#      runs were reaped). Below it the wake STOPS: every session not yet started stays asleep and is
#      reported, and nothing is retried later on its own.
#   5. WAIT, BOUNDED, FOR EACH STARTED SESSION TO RUN. When its own id comes up, it is woken. When it
#      does not but a NEW running session sits in the same folder AND in the very pane this wake
#      spawned, the harness gave the resumed conversation a new id: that id is recorded as wokenAs.
#      Neither within the bound is failed.
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
# How long a started session has to show up running. NOT MEASURED YET: no real wake has run (slice 1's
# proof is a dry run). 90 s is a deliberately loose bound - a resume reads its whole transcript before it
# writes its control file - that still keeps one stuck pane from holding the wake for minutes. The first
# real wake should measure it and set it from that.
$script:HordeFleetWakeWaitSeconds = 90
$script:HordeFleetWakePollMs = 1500
$script:HordeFleetWakeMailTtlSeconds = 86400
$script:HordeFleetWakeLockName = "waking.lock"

function Get-HordeFleetWakeBody {
    # The mail a woken session gets.
    param([Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)][string]$Label)
    return ("You were woken from hibernation " + $Id + ". Read your PARKED-" + $Label + ".md and carry on.")
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
    foreach ($h in $heads) {
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
    # (left by the memory gate) or planned (-DryRun). Throws, changing nothing, when the record cannot be
    # read, another wake holds it, or -Only names a label it does not hold.
    # -Deps: Now (), Sleep (ms), FreePercent () -> number, Agent, Host (fleet/Port.ps1), Post ($sessionId,
    # $label, $body, $messageId) -> answer, and optionally WaitSeconds and PollMs.
    param([Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)]$Deps, [switch]$DryRun, [string[]]$Only = @(), [string]$HordeHome = (Get-HordeHome))
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

    if (Test-Path -LiteralPath $lockPath) { throw ("hibernation " + $Id + " is being woken already, or a wake of it was killed: " + $lockPath + " exists. Delete it once no wake of " + $Id + " runs") }
    $only = @($Only | Where-Object { "" + $_ -ne "" })
    $sessions = @($record.sessions)
    if ($only.Count -gt 0) {
        foreach ($l in $only) { if (@($sessions | Where-Object { "" + (Get-HordeFleetMember $_ "label") -ceq $l }).Count -eq 0) { throw ("hibernation " + $Id + " holds no session labelled " + $l + ", so nothing was woken") } }
        $sessions = @($sessions | Where-Object { $only -ccontains ("" + (Get-HordeFleetMember $_ "label")) })
    }
    $lockStream = $null
    if (-not $DryRun) {
        try { $lockStream = New-Object System.IO.FileStream($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read) }
        catch { throw ("hibernation " + $Id + " is being woken already: its lock " + $lockPath + " could not be created (" + $_.Exception.Message + ")") }
    }
    try {
        if ($null -ne $lockStream) {
            $b = [System.Text.Encoding]::ASCII.GetBytes("pid " + $PID + " at " + (Format-HordeFleetTime -At (& $Deps.Now)) + "`n")
            $lockStream.Write($b, 0, $b.Length); $lockStream.Flush($true)
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
        foreach ($s in $sessions) {
            $v = & $agent.verdict $snapshot (Get-HordeFleetCurrentId -Session $s) ("" + $s.cwd) @()
            if ("" + $v.state -ceq "stopped") { [void]$spawnable.Add($s) }
            else {
                $why = $(if ("" + $v.state -ceq "running") { "still running: " + $v.reason } else { "may be running, so it is left alone: " + $v.reason })
                [void]$refused.Add([pscustomobject]@{ session = $s; reason = $why })
            }
        }
        & $say ("hibernation " + $Id + ": " + @($sessions).Count + " session(s); " + $spawnable.Count + " to wake, " + $refused.Count + " refused" + $(if ($DryRun) { " (dry run: nothing is changed)" } else { "" }))
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
            $free = & $Deps.FreePercent
            & $say ("  free memory now " + [Math]::Round([double]$free, 1) + " percent; each spawn needs at least " + $script:HordeFleetWakeMinFreePercent)
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
            $window = ""; $started = @{}
            & $say ("  window for " + (Get-HordeFleetSessionName -Session $g.head) + ":")
            foreach ($s in $g.sessions) {
                $name = Get-HordeFleetSessionName -Session $s
                if ($stopped) { & $say ("    " + $name + ": left asleep (the wake stopped on free memory)"); & $tell $s "asleep" "the wake stopped on free memory"; continue }
                # 4. Free memory before every spawn.
                $free = [double](& $Deps.FreePercent)
                if ($free -lt $script:HordeFleetWakeMinFreePercent) {
                    $stopped = $true
                    $why = "free memory is " + [Math]::Round($free, 1) + " percent, under " + $script:HordeFleetWakeMinFreePercent + "; the wake stopped here and the rest stay asleep"
                    & $say ("    " + $name + ": left asleep - " + $why)
                    & $tell $s "asleep" $why
                    continue
                }
                $cur = Get-HordeFleetCurrentId -Session $s
                $req = New-HordeFleetWakeStep -Session $s -Line (& $agent.resumeLine $cur) -Environment $scrub -Window $window -Started $started
                Add-HordeFleetState -Session $s -State "waking" -At (& $Deps.Now)
                [void](Write-HordeFleetRecord -Dir $dir -Record $record)
                $sp = & $term.spawn $req
                if ($null -eq $sp -or $sp.state -ne "known") {
                    $why = "its pane was not started: " + $(if ($null -ne $sp) { $sp.reason } else { "the terminal answered nothing" })
                    Add-HordeFleetState -Session $s -State "failed" -At (& $Deps.Now) -Reason $why
                    [void](Write-HordeFleetRecord -Dir $dir -Record $record)
                    & $say ("    " + $name + ": failed - " + $why); & $tell $s "failed" $why
                    continue
                }
                if ($window -eq "") { $window = "" + $sp.value.window }
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
                    Add-HordeFleetState -Session $s -State "failed" -At (& $Deps.Now) -Reason $why
                    [void](Write-HordeFleetRecord -Dir $dir -Record $record)
                    & $say ("    " + $name + ": failed - " + $why); & $tell $s "failed" $why
                    continue
                }
                [void]$startedIds.Add($found.id)
                if ($found.rotated) { $s | Add-Member -NotePropertyName "wokenAs" -NotePropertyValue $found.id -Force }
                # 6. One mail.
                $label = "" + (Get-HordeFleetMember $s "label")
                if ($label -eq "") { $label = ("" + $s.sessionId).Substring(0, 8) }
                $posted = & $Deps.Post $found.id ("" + (Get-HordeFleetMember $s "label")) (Get-HordeFleetWakeBody -Id $Id -Label $label) (Get-HordeFleetWakeMessageId -Id $Id -SessionId ("" + $s.sessionId))
                $as = $(if ($found.rotated) { " as " + $found.id } else { "" })
                if ($null -eq $posted -or $posted.state -ne "known") {
                    $why = "it runs again" + $as + ", but its wake mail was not posted: " + $(if ($null -ne $posted) { $posted.reason } else { "the messenger answered nothing" })
                    Add-HordeFleetState -Session $s -State "failed" -At (& $Deps.Now) -Reason $why
                    [void](Write-HordeFleetRecord -Dir $dir -Record $record)
                    & $say ("    " + $name + ": failed - " + $why); & $tell $s "failed" $why
                    continue
                }
                $note = $(if ($found.rotated) { "it came back under a new id, " + $found.id } else { "" })
                Add-HordeFleetState -Session $s -State "woken" -At (& $Deps.Now) -Reason $note
                [void](Write-HordeFleetRecord -Dir $dir -Record $record)
                & $say ("    " + $name + ": woken in pane " + $sp.value.pane + $as + ", and told")
                & $tell $s "woken" $note
            }
        }
        return [pscustomobject]@{ id = $Id; lines = @($lines); outcomes = @($outcomes) }
    } finally {
        if ($null -ne $lockStream) { $lockStream.Dispose(); Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue }
    }
}
