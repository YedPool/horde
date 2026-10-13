# wakers/wezfleet - the wake watcher's eyes and doorbell on a fleet that wezfleet runs.
#
# A THIN CALLER OF THREE FORMS OF TWO COMMANDS, AND NONE OF THE FLEET'S LIBRARY CODE. What a session's
# mailbox holds, whether its pane is idle, what is in its input box and how a line is typed into it are
# the fleet's own knowledge, and it answers for them through its command line:
#   (A) mail state -Json                                   the whole fleet, cheap, no terminal read:
#       { at; sessions: [ row ] }; on failure a non-zero exit and { at; sessions: null; reason; detail }
#       with reason registry-unreadable or registry-absent
#   (B) mail state -To <id> -TimeoutSeconds <n> -Json      one session, reading its pane: { at; session: row };
#       exit 3 { at; to; reason: absent; detail } for a session nobody answers to, exit 1
#       records-unreadable, exit 2 bad arguments
#   (C) mail nudge -To <id> -BudgetSeconds <35-300> -Json   { outcome; reason; target; pane; instance; detail;
#       elapsedMs }, outcome woken, busy, unreachable or refused, exit 0 for every outcome and 2 for an
#       empty -To or a bad budget. It does not START typing when less than 30 s of its budget is left,
#       and answers refused, budget-too-small, for that.
# (A row may also carry limited and limitedUntil - Get-HordeWezfleetWakerLimit.)
# A row is { id; label; role; parent; retired; reachable; mail; unreadCount; unreadableCount;
# oldestUnreadAt; idle; boxEmpty; midTurn; reason; reasons }. In form A boxEmpty and midTurn are always
# unknown: reading them means reading a pane, which is form B's.
# THE NUDGE IS THE FLEET'S. Form C types only its one pointer line, finds the pane and the terminal
# instance itself - so it reaches a session that has not been seen since a restore - and itself refuses
# a box that is not empty or a session that is not idle, at the moment it would type. That is where this
# waker's nudge.pointer-only, reach.unseen and nudge.guarded come from: it adds nothing to them and can
# take nothing away, because it never types.
#
# THE MAPPING onto the port (wakers/Port.ps1):
#   Targets  form A's rows that are not retired, or that have unread mail. role master is warchief,
#            orchestrator is orc, session is warg, anything else unknown (core/Roles.ps1's table,
#            read here from the row's own word); reachable as the row says.
#   State    from form A's answer of THIS pass, with boxEmpty and midTurn unknown: no pane is read.
#   Confirm  form B, for the one session the watcher is about to nudge: its box and its turn. So a pass
#            over a quiet fleet reads no pane at all, and a busy one reads a pane per nudge.
#   Nudge    form C. refused is the port's nothing (there was nothing to nudge for by then); woken,
#            busy and unreachable pass through with the fleet's reason.
#
# SIX RULES, each from the review of this adapter's contract, and each a test in
# test/test-waker-wezfleet.ps1:
#   1. A ROW IS NEVER SKIPPED OR DISTRUSTED BECAUSE IT CARRIES A REASON. A mailbox with good mail and one
#      corrupt record has mail known, unreadCount above 0 and reason mail-unreadable, and it MUST still
#      be nudged. Nothing here reads reason or reasons to decide; only mail, the counts and the three words.
#   2. A COUNT IS A WHOLE NUMBER OR NULL, AND NULL IS UNKNOWN. It is never read as 0: "no unread mail"
#      and "I could not count" are different answers, and the second makes the state unknown, saying so.
#   3. A FAILURE CAN BE PERMANENT (records-unreadable is, until a person mends the file). The answer is
#      unknown with the fleet's reason code, and the fleet is not asked again on every pass: after
#      consecutive failures the next read waits 5, 15, 45, 135, then 300 s, and until then the same
#      unknown is answered, in the same words, so the journal says it once (core/WakeFiles.ps1). The
#      count of failures in a row goes with the answer, and after ten the watcher calls it permanent:
#      one line, one mail to the warchief, and silence until a read works (core/Wake.ps1).
#   4. EVERY CALL RUNS UNDER THIS ADAPTER'S OWN DEADLINE: form A 10 s, form B three times the
#      -TimeoutSeconds it passes (5, so 15 s), form C three times the budget it passes (60, so 180 s).
#      Past it the child and everything it started are stopped and the answer is unknown with the
#      reason timed-out - or, for a nudge, the outcome killed (Send-HordeWezfleetWakerNudge says why
#      that is not just another failure). The loop that wakes every session never waits on one.
#   5. AN ANSWER THAT IS NOT ONE LINE OF JSON OF THE EXPECTED SHAPE - a binding error prints text - is
#      unknown, or unreachable for a nudge, with the reason. Never a throw.
#   6. unreadableCount IS CARRIED, not acted on here: the port's state has it, and the watcher's tick
#      says "bad-mail" once when it lasts (core/Wake.ps1).
#
# WHERE THE FLEET IS: EXACTLY WHERE THE MESSENGER FINDS IT, and by the same setting. A person names the
# fleet's checkout once, as root in <HORDE_HOME>\settings\messenger-wezfleet.json; this waker reads that
# same file and declares that same setting, so the two can never run two different checkouts and a home
# pinned for a suite (the messenger's test\Pin.ps1, run by test\lib\MessengerPins.ps1) pins both. In
# order, and never a guess: Set-HordeWezfleetWakerRoot when it named a folder (tests); the setting when
# it names one - a refused file is no folder at all, and PATH is never asked in its place; else the
# checkout the wezfleet command on PATH runs, a .ps1 there being the checkout's own script and a .cmd or
# .bat shim READ, NEVER RUN, for the one %~dp0<folder>wezfleet.ps1 it names. The folder must be an
# absolute local folder with no .., no reparse point on it or above it, holding the checkout's markers.
# Decided on every call: a person who installs the fleet must not have to restart the watcher.
# THAT CODE IS A COPY of the messenger's (messengers/wezfleet/Messenger.ps1: the choice of folder, the
# checkout test, the one quoting function, the start with its deadline and drain, the stop of the whole
# tree), because a port's folder is the only place that may name it and one adapter does not load
# another's (CONTRIBUTING 14). The reasons each line is the way it is are written there, with their
# measurements and reviews (#102, #106), and are not repeated here; a change to one belongs in both.
#
# THE ONE START SITE. Start-HordeWezfleetWakerProcess starts the fixed PowerShell from the system folder
# on the fleet's wezfleet.ps1, which it finds itself, with its arguments as separate elements joined by
# one quoting function. wakers/start-sites.txt lists the start, each property it sets and each call of
# it, and test/test-start-sites.ps1 refuses anything else.
#
# ALWAYS A CHILD PROCESS, NEVER THE SCRIPT CALLED IN-PROCESS: powershell.exe from the system folder, with
# -NoProfile -NonInteractive -ExecutionPolicy Bypass -File <checkout>\wezfleet.ps1 and the arguments
# after it - the .ps1 directly, never the .cmd shim, which is only read to find the checkout. HOW THE
# FLEET'S SCRIPT IS STARTED CHANGES WHAT IT DOES: its nudge had a fault that showed only when the entry
# script was called in-process from another PowerShell script (& wezfleet.ps1) - it answered busy for
# ever - and not when it was started as a process with -File (found on the fleet's side, 2026-10-13).
# A fault in a script's own scope is invisible to a caller in the same process and to that caller's
# tests. So the suites start the fake by this same start site, with this same command line - the
# fixture only copies the fake to wezfleet.ps1 in a folder and names the folder - and
# test/test-waker-wezfleet.ps1 reads, from the fake's own log, that every run of it was a process of
# its own started so.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced, after wakers/Port.ps1.

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\Home.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\ModuleSettings.ps1")

# Set only by Set-HordeWezfleetWakerRoot; "" means the setting, then the command on PATH, decide.
$script:HordeWezfleetWakerRoot = ""
# THE MESSENGER'S SETTING, declared again in the same words (the header, WHERE THE FLEET IS).
$script:HordeWezfleetWakerSettings = New-HordeModuleSettings -Module "messenger-wezfleet" -Settings @(
    @{ name = "root"; kind = "folder"; default = ""; what = "The wezfleet checkout whose mail commands are run; empty means the one the wezfleet command on PATH runs." }
)
$script:HordeWezfleetWakerCommand = "wezfleet"
$script:HordeWezfleetWakerShimMaxBytes = 65536
$script:HordeWezfleetWakerShimPattern = '%~dp0((?:[^"%:*?<>|\r\n\\/]+[\\/])*)wezfleet\.ps1'
$script:HordeWezfleetWakerScript = "wezfleet.ps1"
# What makes a folder a wezfleet checkout with mail commands, beside the script itself. Whether THIS
# checkout has mail state and mail nudge is not read from a file name: one that does not answers with
# usage text, which rule 5 reads as unknown.
$script:HordeWezfleetWakerMarkers = @("wezfleet.ps1", "lib\Mail.ps1", "commands\mail.ps1")
$script:HordeWezfleetWakerDrainMs = 500
# The most a command may print before it is stopped. Form A is one row a session: 200 sessions of
# 1,000 bytes are far below this.
$script:HordeWezfleetWakerMaxBytes = 1048576
$script:HordeWezfleetWakerDetailChars = 300
# RULE 4, the deadlines: form A, the -TimeoutSeconds form B passes (its own deadline is three times
# that), and form C.
# The budget a nudge is given, in one place: the table below and the function that resets it both read it.
$script:HordeWezfleetWakerNudgeBudget = 60
$script:HordeWezfleetWakerDeadlines = @{ fleet = 10; paneFlag = 5; nudgeBudget = $script:HordeWezfleetWakerNudgeBudget }
# RULE 3, the wait after each consecutive failure of a read.
$script:HordeWezfleetWakerBackoff = @(5, 15, 45, 135, 300)
# How long one form A answer serves a caller that never says a pass begins, counted from its arrival.
# The watcher does say (the port's Begin), and for it an answer serves exactly one pass.
$script:HordeWezfleetWakerFleetLifeSeconds = 2
$script:HordeWezfleetWakerRoles = @{ "master" = "warchief"; "orchestrator" = "orc"; "session" = "warg" }
$script:HordeWezfleetWakerWords = @("yes", "no", "unknown")
$script:HordeWezfleetWakerOutcomes = @{ "woken" = "woken"; "busy" = "busy"; "unreachable" = "unreachable"; "refused" = "nothing" }
$script:HordeWezfleetWakerCodePattern = '\A[a-z][a-z0-9]*(-[a-z0-9]+)*\z'
$script:HordeWezfleetWakerRowMembers = @("id", "label", "role", "parent", "retired", "reachable", "mail", "unreadCount", "unreadableCount", "oldestUnreadAt", "idle", "boxEmpty", "midTurn")
# What this process remembers between calls: the last form A answer and its failures, each session's
# form B failures, and the clock a test may set.
$script:HordeWezfleetWakerFleet = $null
$script:HordeWezfleetWakerFleetFailures = @{ count = 0; nextAt = [datetime]::MinValue; reason = "" }
$script:HordeWezfleetWakerPaneFailures = @{}
$script:HordeWezfleetWakerClock = $null
# How long the snapshot of the process table may take when a deadline has passed, and a test's way to
# play one that could not be had (Set-HordeWezfleetWakerSnapshotFault).
$script:HordeWezfleetWakerSnapshotSeconds = 5
$script:HordeWezfleetWakerSnapshotFault = $false

function Set-HordeWezfleetWakerRoot {
    # For tests: name the folder holding the fleet's wezfleet.ps1, over the setting and the command on
    # PATH. "" unsets it. Whatever it is set to, what this process remembered of the fleet is forgotten.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Path)
    $script:HordeWezfleetWakerRoot = $Path
    Clear-HordeWezfleetWakerMemory
}

function Set-HordeWezfleetWakerDeadlines {
    # For tests: the deadlines of rule 4, in seconds, so a case that waits one out waits a second or two.
    param([int]$FleetSeconds = 10, [int]$PaneFlagSeconds = 5, [int]$NudgeBudgetSeconds = $script:HordeWezfleetWakerNudgeBudget)
    if ($FleetSeconds -lt 1 -or $PaneFlagSeconds -lt 1 -or $NudgeBudgetSeconds -lt 1) { throw "a deadline is at least 1 s" }
    $script:HordeWezfleetWakerDeadlines = @{ fleet = $FleetSeconds; paneFlag = $PaneFlagSeconds; nudgeBudget = $NudgeBudgetSeconds }
}

function Set-HordeWezfleetWakerSnapshotFault {
    # For tests: play a process table that cannot be listed in time, so the stop of a hung command is
    # seen to stop the child alone and say so.
    param([bool]$On)
    $script:HordeWezfleetWakerSnapshotFault = $On
}

function Set-HordeWezfleetWakerClock {
    # For tests: the time this waker takes as now, for the life of a form A answer and the back-off of a
    # failing read; $null puts the real clock back.
    param($Now)
    $script:HordeWezfleetWakerClock = $Now
}

function Get-HordeWezfleetWakerTime {
    if ($null -ne $script:HordeWezfleetWakerClock) { return ([datetime]$script:HordeWezfleetWakerClock) }
    return [datetime]::UtcNow
}

function Clear-HordeWezfleetWakerMemory {
    # Forget the last form A answer and every failure counted: the next call asks the fleet.
    $script:HordeWezfleetWakerFleet = $null
    $script:HordeWezfleetWakerFleetFailures = @{ count = 0; nextAt = [datetime]::MinValue; reason = "" }
    $script:HordeWezfleetWakerPaneFailures = @{}
}

function New-HordeWezfleetWakerChoice {
    # A choice of folder: { ok; root; how; reason; fixed }. how finishes "the folder was ...". fixed says
    # a person NAMED the folder - the root setting, or a test's own pointer - and is false for one that
    # was only found, by looking the command up on PATH.
    param([string]$Root = "", [string]$How = "", [string]$Reason = "", [switch]$Fixed)
    return [pscustomobject]@{ ok = ($Reason -eq ""); root = $Root; how = $How; reason = $Reason; fixed = [bool]$Fixed }
}

function Find-HordeWezfleetWakerOnPath {
    # The checkout the wezfleet command on PATH runs, as a choice. The shim is read as text and never run.
    param([Parameter(Mandatory = $true)][string]$SettingsPath)
    $instead = "; name its checkout as root in " + $SettingsPath
    $cmd = $null
    try { $cmd = @(Get-Command -Name $script:HordeWezfleetWakerCommand -CommandType Application, ExternalScript -ErrorAction SilentlyContinue) | Select-Object -First 1 } catch { $cmd = $null }
    if ($null -eq $cmd) { return (New-HordeWezfleetWakerChoice -Reason ("no wezfleet command is on PATH and no root is set, so the fleet's command was not run" + $instead)) }
    $src = [string]$cmd.Path
    $from = "found from the wezfleet command on PATH, " + $src
    $ext = [System.IO.Path]::GetExtension($src).ToLowerInvariant()
    $dir = Split-Path -Parent $src
    if ($ext -ceq ".ps1") { return (New-HordeWezfleetWakerChoice -Root $dir -How $from) }
    if ($ext -cne ".cmd" -and $ext -cne ".bat") {
        return (New-HordeWezfleetWakerChoice -Reason ("the wezfleet command on PATH is '" + $src + "', neither a .ps1 nor a .cmd or .bat shim, so its checkout is not known" + $instead))
    }
    $text = ""
    try {
        $info = New-Object System.IO.FileInfo($src)
        if ($info.Length -gt $script:HordeWezfleetWakerShimMaxBytes) { return (New-HordeWezfleetWakerChoice -Reason ("the wezfleet command on PATH, the shim '" + $src + "', is larger than " + $script:HordeWezfleetWakerShimMaxBytes + " bytes, so it was not read" + $instead)) }
        $text = [System.IO.File]::ReadAllText($src)
    } catch { return (New-HordeWezfleetWakerChoice -Reason ("the wezfleet command on PATH, the shim '" + $src + "', could not be read: " + $_.Exception.Message + $instead)) }
    $named = @([regex]::Matches($text, $script:HordeWezfleetWakerShimPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) | ForEach-Object { $_.Groups[1].Value.Replace('/', '\').ToLowerInvariant() } | Select-Object -Unique)
    if ($named.Count -ne 1) {
        return (New-HordeWezfleetWakerChoice -Reason ("the wezfleet command on PATH is the shim '" + $src + "', which names " + $named.Count + " scripts as %~dp0<folder>wezfleet.ps1, not one, so its checkout is not known" + $instead))
    }
    $m = [regex]::Match($text, $script:HordeWezfleetWakerShimPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $rel = $m.Groups[1].Value.Replace('/', '\').TrimEnd('\')
    $root = $(if ($rel -eq "") { $dir } else { $dir.TrimEnd('\') + '\' + $rel })
    return (New-HordeWezfleetWakerChoice -Root $root -How $from)
}

function Get-HordeWezfleetWakerChoice {
    # Which folder, and how it was chosen (header, WHERE THE FLEET IS), as a choice. Read on every call.
    if ("$script:HordeWezfleetWakerRoot" -ne "") { return (New-HordeWezfleetWakerChoice -Root $script:HordeWezfleetWakerRoot -How "set by Set-HordeWezfleetWakerRoot" -Fixed) }
    $s = $null
    try { $s = Get-HordeModuleSettings -Declaration $script:HordeWezfleetWakerSettings }
    catch { return (New-HordeWezfleetWakerChoice -Reason ("the wezfleet settings could not be read, so the fleet's command was not run: " + $_.Exception.Message)) }
    if ($s.state -cne "defaults" -and $s.state -cne "read") { return (New-HordeWezfleetWakerChoice -Reason ("the fleet's command was not run, because the wezfleet settings are refused: " + (@($s.findings) -join "; "))) }
    if ("$($s.values.root)" -ne "") { return (New-HordeWezfleetWakerChoice -Root $s.values.root -How ("set as root in " + $s.path) -Fixed) }
    return (Find-HordeWezfleetWakerOnPath -SettingsPath $s.path)
}

function Get-HordeWezfleetWakerSource {
    # The port's Source: where the fleet's command comes from, and whether a person named it.
    # A COMMAND FOUND ON PATH IS NOT FIXED: it is whatever answers to the name wezfleet first on PATH at
    # that moment, and a folder put ahead of it on PATH - by an installer, by another checkout, by
    # anything that can write an environment variable - becomes the program that types into sessions.
    # Reading a fleet through it is one thing; a run that SENDS must be told which program, in the
    # root setting (safety review of PR 220). So this says which it was, and the watcher refuses.
    $choice = Get-HordeWezfleetWakerChoice
    if (-not $choice.ok) { return (New-HordeUnknown -Reason $choice.reason) }
    return (New-HordeKnown -Value ([pscustomobject]@{ fixed = [bool]$choice.fixed; how = (ConvertTo-HordeWezfleetWakerLine ("the fleet's command is in the folder " + $choice.how) -Max 400) }) -ObservedAt (Get-HordeWezfleetWakerTime))
}

function Test-HordeWezfleetWakerCheckout {
    # Why -Folder is not a folder to run the fleet's script from, or "" when it is.
    param([Parameter(Mandatory = $true)][string]$Folder)
    $dir = $Folder
    if (-not [System.IO.Path]::IsPathRooted($dir) -or $dir -notmatch '\A[A-Za-z]:\\' -or @($dir -split '[\\/]') -contains "..") {
        return ("the wezfleet folder '" + $dir + "' is not an absolute local folder without .., so it was not used")
    }
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return ("the wezfleet folder '" + $dir + "' does not exist") }
    $d = New-Object System.IO.DirectoryInfo($dir)
    while ($null -ne $d) {
        if (($d.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            return ("the wezfleet folder '" + $dir + "' has a reparse point on its path ('" + $d.FullName + "'), so it was not used")
        }
        $d = $d.Parent
    }
    foreach ($marker in $script:HordeWezfleetWakerMarkers) {
        if (-not (Test-Path -LiteralPath (Join-Path $dir $marker) -PathType Leaf)) {
            return ("'" + $dir + "' is not a wezfleet checkout with the mail commands: no " + $marker + " in it")
        }
    }
    return ""
}

function Get-HordeWezfleetWakerScriptPath {
    # The fleet's script, as { ok; path; reason }, whichever way the folder was chosen; a refusal says which.
    $choice = Get-HordeWezfleetWakerChoice
    if (-not $choice.ok) { return [pscustomobject]@{ ok = $false; path = ""; reason = $choice.reason } }
    $why = Test-HordeWezfleetWakerCheckout -Folder $choice.root
    if ($why -ne "") { return [pscustomobject]@{ ok = $false; path = ""; reason = ($why + " (the folder was " + $choice.how + ")") } }
    return [pscustomobject]@{ ok = $true; path = (Join-Path $choice.root $script:HordeWezfleetWakerScript); reason = "" }
}

function ConvertTo-HordeWezfleetWakerCommandLine {
    # Separate argument elements as one Windows command line, each quoted the way CommandLineToArgvW reads
    # it back. The one place arguments become a string.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Argv)
    $parts = New-Object System.Collections.ArrayList
    foreach ($a in $Argv) {
        if ($a -ne "" -and $a -notmatch '[\s"]') { [void]$parts.Add($a); continue }
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append('"')
        $slashes = 0
        foreach ($ch in $a.ToCharArray()) {
            if ($ch -eq '\') { $slashes++; continue }
            if ($ch -eq '"') { [void]$sb.Append('\' * ($slashes * 2 + 1)); [void]$sb.Append('"'); $slashes = 0; continue }
            if ($slashes -gt 0) { [void]$sb.Append('\' * $slashes); $slashes = 0 }
            [void]$sb.Append($ch)
        }
        if ($slashes -gt 0) { [void]$sb.Append('\' * ($slashes * 2)) }
        [void]$sb.Append('"')
        [void]$parts.Add($sb.ToString())
    }
    return ($parts -join " ")
}

function Get-HordeWezfleetWakerDescendants {
    # The processes the started one started, and theirs, from one snapshot of the process table, as
    # { id; start } in UTC; a process counts only if it was created at or after its parent started.
    # $null WHEN THE SNAPSHOT COULD NOT BE HAD - it failed, or it did not come within its own time limit.
    # THE SNAPSHOT HAS A TIME LIMIT OF ITS OWN (review of PR #211). It is taken at the moment a deadline
    # has already passed, to stop a hung command; without a limit a process table that does not answer
    # hangs the stop itself, and with it the loop the deadline exists to protect. No list is not "no
    # descendants": the caller then stops the child alone and says so.
    param([Parameter(Mandatory = $true)][int]$RootId, [Parameter(Mandatory = $true)][datetime]$RootStart)
    if ($script:HordeWezfleetWakerSnapshotFault) { return $null }
    $all = @()
    try { $all = @(Get-CimInstance -ClassName Win32_Process -Property ProcessId, ParentProcessId, CreationDate -OperationTimeoutSec $script:HordeWezfleetWakerSnapshotSeconds -ErrorAction Stop) } catch { return $null }
    $byParent = @{}
    foreach ($q in $all) {
        $k = [int]$q.ParentProcessId
        if (-not $byParent.ContainsKey($k)) { $byParent[$k] = New-Object System.Collections.ArrayList }
        [void]$byParent[$k].Add($q)
    }
    $out = New-Object System.Collections.ArrayList
    $seen = @{ $RootId = $true }
    $todo = New-Object System.Collections.Queue
    $todo.Enqueue([pscustomobject]@{ id = $RootId; start = $RootStart.ToUniversalTime() })
    while ($todo.Count -gt 0) {
        $parent = $todo.Dequeue()
        if (-not $byParent.ContainsKey($parent.id)) { continue }
        foreach ($c in $byParent[$parent.id]) {
            $cid = [int]$c.ProcessId
            if ($seen.ContainsKey($cid) -or $null -eq $c.CreationDate) { continue }
            $cstart = ([datetime]$c.CreationDate).ToUniversalTime()
            if ($cstart -lt $parent.start) { continue }
            $seen[$cid] = $true
            $d = [pscustomobject]@{ id = $cid; start = $cstart }
            [void]$out.Add($d)
            $todo.Enqueue($d)
        }
    }
    return @($out)
}

function Stop-HordeWezfleetWakerProcess {
    # Stop the process this call started, by its handle, and every process it started; a descendant only
    # if the process now holding its pid started when the snapshot said. Says what it stopped.
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process)
    $tree = $null
    try { $tree = Get-HordeWezfleetWakerDescendants -RootId $Process.Id -RootStart $Process.StartTime } catch { $tree = $null }
    $listed = ($null -ne $tree)
    $tree = @($tree | Where-Object { $null -ne $_ })
    try { if (-not $Process.HasExited) { $Process.Kill() } } catch { }
    $stopped = 0
    foreach ($d in $tree) {
        try {
            $q = Get-Process -Id $d.id -ErrorAction Stop
            if ([Math]::Abs(($q.StartTime.ToUniversalTime() - $d.start).TotalSeconds) -lt 1) { $q.Kill(); $stopped++ }
        } catch { }
    }
    $null = $Process.WaitForExit(5000)
    $also = $(if ($stopped -gt 0) { ", with " + $stopped + " process(es) it had started" } else { "" })
    # SAID, NOT HIDDEN: with no list, whatever the child had started may still be running.
    if (-not $listed) { $also = ", alone: the processes it had started could not be listed within " + $script:HordeWezfleetWakerSnapshotSeconds + " s, so any of them are still running" }
    if ($Process.HasExited) { return ("the process it started was stopped" + $also) }
    return ("the process it started did not stop within 5 s" + $also)
}

function Start-HordeWezfleetWakerProcess {
    # THE ONE START SITE: the fixed PowerShell on the fleet's wezfleet.ps1, which it finds itself, with
    # -Argv after it, under a deadline of -DeadlineSeconds (rule 4). Returns { ok; exit; stdout; stderr;
    # reason; timedOut }. Never throws for the child.
    param([Parameter(Mandatory = $true)][string[]]$Argv, [Parameter(Mandatory = $true)][int]$DeadlineSeconds)
    $where = Get-HordeWezfleetWakerScriptPath
    if (-not $where.ok) { return [pscustomobject]@{ ok = $false; exit = -1; stdout = ""; stderr = ""; reason = $where.reason; timedOut = $false } }
    $all = @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $where.path) + @($Argv)
    $psi = [System.Diagnostics.ProcessStartInfo]::new([System.IO.Path]::Combine([System.Environment]::SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe"), (ConvertTo-HordeWezfleetWakerCommandLine -Argv $all))
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $p = $null
    try { $p = [System.Diagnostics.Process]::Start($psi) } catch { return [pscustomobject]@{ ok = $false; exit = -1; stdout = ""; stderr = ""; reason = ("the fleet's command could not be started: " + $_.Exception.Message); timedOut = $false } }
    $deadline = (Get-Date).AddSeconds($DeadlineSeconds)
    $err = $p.StandardError.ReadToEndAsync()
    $stream = $p.StandardOutput.BaseStream
    $buf = New-Object byte[] 4096
    $got = New-Object System.IO.MemoryStream
    $exitedAt = $null
    $drained = $false
    while (-not $drained) {
        $read = $stream.ReadAsync($buf, 0, $buf.Length)
        while (-not $read.Wait(100)) {
            if ((Get-Date) -ge $deadline) { return [pscustomobject]@{ ok = $false; exit = -1; stdout = ""; stderr = ""; reason = ("timed-out: the fleet's command did not answer within " + $DeadlineSeconds + " s; " + (Stop-HordeWezfleetWakerProcess -Process $p)); timedOut = $true } }
            if ($p.HasExited) {
                if ($null -eq $exitedAt) { $exitedAt = Get-Date }
                elseif (((Get-Date) - $exitedAt).TotalMilliseconds -ge $script:HordeWezfleetWakerDrainMs) { $drained = $true; break }
            }
        }
        if ($drained) { break }
        $n = $read.Result
        if ($n -eq 0) { break }
        $got.Write($buf, 0, $n)
        if ($got.Length -gt $script:HordeWezfleetWakerMaxBytes) { return [pscustomobject]@{ ok = $false; exit = -1; stdout = ""; stderr = ""; reason = ("the fleet's command printed more than " + $script:HordeWezfleetWakerMaxBytes + " bytes; " + (Stop-HordeWezfleetWakerProcess -Process $p)); timedOut = $false } }
    }
    $left = [int][Math]::Max(0, ($deadline - (Get-Date)).TotalMilliseconds)
    if (-not $p.WaitForExit($left)) { return [pscustomobject]@{ ok = $false; exit = -1; stdout = ""; stderr = ""; reason = ("timed-out: the fleet's command did not exit within " + $DeadlineSeconds + " s; " + (Stop-HordeWezfleetWakerProcess -Process $p)); timedOut = $true } }
    $errText = ""
    if ($err.Wait(1000)) { $errText = "$($err.Result)" }
    return [pscustomobject]@{ ok = $true; exit = $p.ExitCode; stdout = [System.Text.Encoding]::UTF8.GetString($got.ToArray()); stderr = $errText; reason = ""; timedOut = $false }
}

function ConvertTo-HordeWezfleetWakerLine {
    # One line of another program's text, fit for a reason: its first line, every character outside
    # printable ASCII made '?', at most -Max characters.
    param([string]$Text, [int]$Max = 200)
    $first = @("$Text" -split "`r?`n" | Where-Object { $_.Trim() -ne "" }) | Select-Object -First 1
    $clean = ("$first" -replace '[^\x20-\x7E]', '?').Trim()
    if ($clean.Length -gt $Max) { $clean = $clean.Substring(0, $Max) }
    return $clean
}

function Read-HordeWezfleetWakerJson {
    # RULE 5. The one line of JSON a run printed, as { ok; json; reason }: ok only when the command ran,
    # printed exactly one line, and that line is a JSON object. Whatever else it printed - nothing, two
    # lines, the host's own words for an argument it does not know - is the reason, in one clean line.
    param([Parameter(Mandatory = $true)]$Run, [Parameter(Mandatory = $true)][string]$What)
    if (-not $Run.ok) { return [pscustomobject]@{ ok = $false; json = $null; reason = "$($Run.reason)" } }
    $said = $What + " exit " + $Run.exit
    $lines = @("$($Run.stdout)" -split "`r?`n" | Where-Object { $_.Trim() -ne "" })
    if ($lines.Count -ne 1) {
        $detail = ConvertTo-HordeWezfleetWakerLine ("$($Run.stdout)" + "`n" + "$($Run.stderr)")
        return [pscustomobject]@{ ok = $false; json = $null; reason = ($said + " printed " + $lines.Count + " lines, not one line of JSON" + $(if ($detail) { ": " + $detail } else { "" })) }
    }
    $j = $null
    try { $j = $lines[0] | ConvertFrom-Json } catch { $j = $null }
    if ($null -eq $j -or $j -isnot [System.Management.Automation.PSCustomObject]) { return [pscustomobject]@{ ok = $false; json = $null; reason = ($said + " printed something that is not JSON: " + (ConvertTo-HordeWezfleetWakerLine $lines[0])) } }
    return [pscustomobject]@{ ok = $true; json = $j; reason = "" }
}

function Get-HordeWezfleetWakerFailure {
    # What a failed read says of itself, for a reason: the fleet's code when it gave one, then its
    # detail. RULE 3: the code comes first and whole, so "records-unreadable" is what a person reads.
    param($Json, [string]$Said)
    $code = ""
    $p = $Json.PSObject.Properties["reason"]
    if ($null -ne $p -and $p.Value -is [string] -and $p.Value -cmatch $script:HordeWezfleetWakerCodePattern) { $code = $p.Value }
    $detail = ""
    $d = $Json.PSObject.Properties["detail"]
    if ($null -ne $d -and $d.Value -is [string]) { $detail = ConvertTo-HordeWezfleetWakerLine $d.Value -Max $script:HordeWezfleetWakerDetailChars }
    if ($code -eq "") { return ($Said + " without a reason code this waker reads" + $(if ($detail -ne "") { ": " + $detail } else { "" })) }
    return ($code + ": " + $Said + $(if ($detail -ne "") { ": " + $detail } else { "" }))
}

function Test-HordeWezfleetWakerRow {
    # Why a row is not one this waker reads, or "" when it is. THE SHAPE ONLY (rule 5): every member it
    # reads is there and of its kind. NOT what the row says: reason and reasons are not looked at at all
    # (rule 1), and a count that is null is a shape this accepts and Read-HordeWezfleetWakerState refuses
    # by name (rule 2).
    param($Row)
    if ($null -eq $Row -or $Row -isnot [System.Management.Automation.PSCustomObject]) { return "a row is not an object" }
    $names = @($Row.PSObject.Properties | ForEach-Object { $_.Name })
    foreach ($k in $script:HordeWezfleetWakerRowMembers) { if ($names -cnotcontains $k) { return ("a row has no '" + $k + "'") } }
    foreach ($k in @("id", "label", "role", "parent", "reachable", "mail", "idle", "boxEmpty", "midTurn")) { if ($Row.$k -isnot [string]) { return ("a row's " + $k + " is not text") } }
    if ($Row.retired -isnot [bool]) { return "a row's retired is not true or false" }
    foreach ($k in @("unreadCount", "unreadableCount")) {
        $v = $Row.$k
        if ($null -ne $v -and -not (($v -is [int] -or $v -is [long]) -and $v -ge 0)) { return ("a row's " + $k + " is neither a whole number, 0 or more, nor null") }
    }
    if ($null -ne $Row.oldestUnreadAt -and $Row.oldestUnreadAt -isnot [string] -and $Row.oldestUnreadAt -isnot [datetime]) { return "a row's oldestUnreadAt is neither a time nor null" }
    # limited AND limitedUntil ARE READ WHEN A ROW HAS THEM, and a row of a command too old to say
    # either is still a row (Get-HordeWezfleetWakerLimit).
    if ($names -ccontains "limited" -and ($Row.limited -isnot [string] -or $script:HordeWezfleetWakerWords -cnotcontains $Row.limited)) { return "a row's limited is not yes, no or unknown" }
    if ($names -ccontains "limitedUntil" -and $null -ne $Row.limitedUntil -and $Row.limitedUntil -isnot [string] -and $Row.limitedUntil -isnot [datetime]) { return "a row's limitedUntil is neither a time nor null" }
    foreach ($k in @("reachable", "idle", "boxEmpty", "midTurn")) { if ($script:HordeWezfleetWakerWords -cnotcontains $Row.$k) { return ("a row's " + $k + " is '" + (ConvertTo-HordeWezfleetWakerLine $Row.$k -Max 40) + "', not yes, no or unknown") } }
    return ""
}

function Get-HordeWezfleetWakerWait {
    # RULE 3. How long to wait after the -Failures-th consecutive failure: 5, 15, 45, 135, then 300 s.
    param([int]$Failures)
    $steps = $script:HordeWezfleetWakerBackoff
    if ($Failures -le 0) { return 0 }
    return [int]$steps[[System.Math]::Min($Failures, $steps.Count) - 1]
}

function Read-HordeWezfleetWakerFleet {
    # FORM A, ONCE A PASS: { ok; rows; reason }, rows keyed by session id. One answer serves every call
    # made within its short life; a failing read is not repeated until its back-off has run out, and
    # answers in the same words meanwhile (rule 3).
    # THE ANSWER IS KEPT FOR THE PASS, AND STAMPED WHEN IT ARRIVES. It was stamped when the call was
    # MADE (review of PR #211): a fleet that took longer than the answer's 2 s life to reply left an
    # answer already expired, so every state of that pass asked again - N + 1 process starts a pass on
    # exactly the machine too slow to bear them. Two things now: the watcher says when a pass begins
    # (the port's Begin, Clear-HordeWezfleetWakerPass), and that alone ends a kept answer's use by the
    # watcher; and for a caller that never says so, the life is counted from the answer's arrival.
    $now = Get-HordeWezfleetWakerTime
    $kept = $script:HordeWezfleetWakerFleet
    if ($null -ne $kept -and ($now - $kept.at).TotalSeconds -ge 0 -and ($now - $kept.at).TotalSeconds -lt $script:HordeWezfleetWakerFleetLifeSeconds) { return $kept.answer }
    $fail = $script:HordeWezfleetWakerFleetFailures
    if ($fail.count -gt 0 -and $now -lt $fail.nextAt) { return [pscustomobject]@{ ok = $false; rows = $null; reason = $fail.reason } }
    $answer = Get-HordeWezfleetWakerFleetAnswer
    if ($answer.ok) { $script:HordeWezfleetWakerFleetFailures = @{ count = 0; nextAt = [datetime]::MinValue; reason = "" } }
    else {
        $count = [int]$fail.count + 1
        $script:HordeWezfleetWakerFleetFailures = @{ count = $count; nextAt = $now.AddSeconds((Get-HordeWezfleetWakerWait -Failures $count)); reason = $answer.reason }
    }
    $script:HordeWezfleetWakerFleet = [pscustomobject]@{ at = (Get-HordeWezfleetWakerTime); answer = $answer }
    return $answer
}

function Clear-HordeWezfleetWakerPass {
    # A pass begins: the last pass's reading of the fleet is not this one's. What was counted of
    # failures is kept - a back-off runs across passes, which is its whole point.
    $script:HordeWezfleetWakerFleet = $null
}

function Get-HordeWezfleetWakerFleetAnswer {
    # One form A call, read: { ok; rows; reason }.
    $run = Start-HordeWezfleetWakerProcess -Argv @("mail", "state", "-Json") -DeadlineSeconds $script:HordeWezfleetWakerDeadlines.fleet
    $read = Read-HordeWezfleetWakerJson -Run $run -What "wezfleet mail state"
    if (-not $read.ok) { return [pscustomobject]@{ ok = $false; rows = $null; reason = $read.reason } }
    $said = "wezfleet mail state exit " + $run.exit
    if ([int]$run.exit -ne 0) { return [pscustomobject]@{ ok = $false; rows = $null; reason = (Get-HordeWezfleetWakerFailure -Json $read.json -Said $said) } }
    $p = $read.json.PSObject.Properties["sessions"]
    # ConvertFrom-Json gives one row as an object and none as nothing; a string or a number is no list.
    if ($null -eq $p -or $null -eq $p.Value -or $p.Value -is [string] -or $p.Value -is [System.ValueType]) { return [pscustomobject]@{ ok = $false; rows = $null; reason = ($said + " answered without a list of sessions: not the shape this waker reads") } }
    $rows = [ordered]@{}
    foreach ($row in @($p.Value)) {
        $why = Test-HordeWezfleetWakerRow -Row $row
        if ($why -ne "") { return [pscustomobject]@{ ok = $false; rows = $null; reason = ($said + ": " + $why + ", so it is not the shape this waker reads") } }
        if ($rows.Contains($row.id)) { return [pscustomobject]@{ ok = $false; rows = $null; reason = ($said + " listed the session " + (ConvertTo-HordeWezfleetWakerLine $row.id -Max 60) + " twice") } }
        $rows[$row.id] = $row
    }
    return [pscustomobject]@{ ok = $true; rows = $rows; reason = "" }
}

function Read-HordeWezfleetWakerPane {
    # FORM B for one session: { ok; row; reason }. Its failures back off too (rule 3): a session whose
    # pane does not answer costs a deadline once, then is left for 5, 15, 45, 135, 300 s.
    param([Parameter(Mandatory = $true)][string]$Id)
    $now = Get-HordeWezfleetWakerTime
    if ($script:HordeWezfleetWakerPaneFailures.ContainsKey($Id)) {
        $fail = $script:HordeWezfleetWakerPaneFailures[$Id]
        if ($now -lt $fail.nextAt) { return [pscustomobject]@{ ok = $false; row = $null; reason = $fail.reason } }
    }
    $flag = [int]$script:HordeWezfleetWakerDeadlines.paneFlag
    $run = Start-HordeWezfleetWakerProcess -Argv @("mail", "state", "-To", $Id, "-TimeoutSeconds", ("" + $flag), "-Json") -DeadlineSeconds (3 * $flag)
    $answer = $null
    $read = Read-HordeWezfleetWakerJson -Run $run -What "wezfleet mail state -To"
    if (-not $read.ok) { $answer = [pscustomobject]@{ ok = $false; row = $null; reason = $read.reason } }
    elseif ([int]$run.exit -ne 0) { $answer = [pscustomobject]@{ ok = $false; row = $null; reason = (Get-HordeWezfleetWakerFailure -Json $read.json -Said ("wezfleet mail state -To exit " + $run.exit)) } }
    else {
        $p = $read.json.PSObject.Properties["session"]
        $why = "it answered without a session"
        if ($null -ne $p) { $why = Test-HordeWezfleetWakerRow -Row $p.Value }
        if ($why -ne "") { $answer = [pscustomobject]@{ ok = $false; row = $null; reason = ("wezfleet mail state -To exit 0: " + $why + ", so it is not the shape this waker reads") } }
        elseif ($p.Value.id -cne $Id) { $answer = [pscustomobject]@{ ok = $false; row = $null; reason = ("wezfleet mail state -To answered about " + (ConvertTo-HordeWezfleetWakerLine $p.Value.id -Max 60) + ", not " + $Id) } }
        else { $answer = [pscustomobject]@{ ok = $true; row = $p.Value; reason = "" } }
    }
    if ($answer.ok) { $script:HordeWezfleetWakerPaneFailures.Remove($Id) }
    else {
        $count = 1
        if ($script:HordeWezfleetWakerPaneFailures.ContainsKey($Id)) { $count = [int]$script:HordeWezfleetWakerPaneFailures[$Id].count + 1 }
        $script:HordeWezfleetWakerPaneFailures[$Id] = @{ count = $count; nextAt = $now.AddSeconds((Get-HordeWezfleetWakerWait -Failures $count)); reason = $answer.reason }
    }
    return $answer
}

function ConvertTo-HordeWezfleetWakerRole {
    # The fleet's word for a role as Horde's; anything it does not know is unknown, never guessed.
    param([string]$Word)
    if ($script:HordeWezfleetWakerRoles.ContainsKey($Word) -and $script:HordeWezfleetWakerRoles[$Word] -is [string]) { return $script:HordeWezfleetWakerRoles[$Word] }
    return "unknown"
}

function Get-HordeWezfleetWakerLimit {
    # A row's usage limit, as the port's two members: { limited; limitedUntil }.
    # A session whose last turn ended in a usage-limit error cannot answer a knock until the limit
    # resets (measured 2026-10-13, 04:36 to 05:55 UTC: every session of the account was stopped for
    # about 80 minutes, every knock in that window was typed and nobody could answer). The fleet's
    # command says so in each row: limited (yes, no, unknown) and limitedUntil (a time, or null).
    #   limited no                                             -> no
    #   limited unknown, or NO SUCH MEMBER (a command too old  -> unknown. NEVER no: it was read as
    #   to say)                                                   "not limited" at first, and the
    #                                                             session was nudged and counted (safety
    #                                                             review of PR 220). What unknown is
    #                                                             owed - a wait, and its release - is
    #                                                             the watcher's (core/Wake.ps1)
    #   limited yes, with a limitedUntil that can be placed    -> yes, until then. The command keeps a
    #                                                             reset that has passed in the row,
    #                                                             still saying yes: whether the time is
    #                                                             ahead or over is the watcher's to say,
    #                                                             with the pass's clock
    #   limited yes, limitedUntil null or not a time           -> yes, and nobody knows until when
    # The fleet says unknown for every row it cannot reach, and for a session whose last transcript
    # entry is longer than the tail it reads (1 of 23 reachable sessions, measured on the live fleet).
    param([Parameter(Mandatory = $true)]$Row)
    $p = $Row.PSObject.Properties["limited"]
    if ($null -eq $p -or $p.Value -cne "yes") {
        $word = "unknown"
        if ($null -ne $p -and $p.Value -ceq "no") { $word = "no" }
        return [pscustomobject]@{ limited = $word; limitedUntil = $null }
    }
    $until = $null
    $u = $Row.PSObject.Properties["limitedUntil"]
    if ($null -ne $u) {
        if ($u.Value -is [datetime]) { if ($u.Value.Kind -ne [System.DateTimeKind]::Unspecified) { $until = $u.Value.ToUniversalTime() } }
        elseif ($u.Value -is [string]) {
            $parsed = [datetime]::MinValue
            if ([datetime]::TryParse($u.Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed) -and $parsed.Kind -ne [System.DateTimeKind]::Unspecified) { $until = $parsed.ToUniversalTime() }
        }
    }
    return [pscustomobject]@{ limited = "yes"; limitedUntil = $until }
}

function Read-HordeWezfleetWakerState {
    # A row as the port's state, or why it is none: { ok; value; reason }.
    #   RULE 1: reason and reasons are NOT read. A row with good mail and one corrupt record is a row
    #           with unread mail, and is answered as one.
    #   RULE 2: mail that is not known, or a count that is null, is unknown - never 0.
    param([Parameter(Mandatory = $true)]$Row)
    if ($Row.mail -cne "known") { return [pscustomobject]@{ ok = $false; value = $null; reason = ("the fleet could not read the mail of " + $Row.id + " (mail is " + (ConvertTo-HordeWezfleetWakerLine $Row.mail -Max 40) + ")") } }
    if ($null -eq $Row.unreadCount) { return [pscustomobject]@{ ok = $false; value = $null; reason = ("the fleet gave no count of the unread mail of " + $Row.id + " (unreadCount is null), which is unknown and not none") } }
    if ($null -eq $Row.unreadableCount) { return [pscustomobject]@{ ok = $false; value = $null; reason = ("the fleet gave no count of the unreadable mail of " + $Row.id + " (unreadableCount is null), which is unknown and not none") } }
    $oldest = $null
    if ($Row.unreadCount -gt 0) {
        if ($Row.oldestUnreadAt -is [datetime]) { if ($Row.oldestUnreadAt.Kind -ne [System.DateTimeKind]::Unspecified) { $oldest = $Row.oldestUnreadAt.ToUniversalTime() } }
        elseif ($Row.oldestUnreadAt -is [string]) {
            $parsed = [datetime]::MinValue
            if ([datetime]::TryParse($Row.oldestUnreadAt, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed) -and $parsed.Kind -ne [System.DateTimeKind]::Unspecified) { $oldest = $parsed.ToUniversalTime() }
        }
        if ($null -eq $oldest) { return [pscustomobject]@{ ok = $false; value = $null; reason = ("the fleet says " + $Row.id + " has unread mail and gave no time for the oldest that can be placed") } }
    }
    $limit = Get-HordeWezfleetWakerLimit -Row $Row
    return [pscustomobject]@{ ok = $true; reason = ""; value = [pscustomobject]@{ id = $Row.id; unreadCount = $Row.unreadCount; unreadableCount = $Row.unreadableCount; oldestUnreadAt = $oldest; idle = $Row.idle; boxEmpty = $Row.boxEmpty; midTurn = $Row.midTurn; limited = $limit.limited; limitedUntil = $limit.limitedUntil } }
}

function Get-HordeWezfleetWakerRetired {
    # Is this row's session retired, as the port's word: yes, no or unknown.
    # THE ROW'S retired IS A BOOLEAN THAT IS FALSE FOR "COULD NOT TELL" (read from the fleet's own code,
    # 2026-10-13): a session with no readable registry record is listed with retired false, because
    # there was no record to read it from. So false is "no" only for a row the fleet had a record for:
    #   retired true                                                    -> yes
    #   retired false, and the row says its record could not be read
    #     (record-unreadable in reason or reasons), or shows none of
    #     what a record gives - no label and a role this waker does
    #     not know                                                      -> unknown
    #   retired false otherwise                                         -> no
    # reason and reasons are read HERE AND ONLY FOR THIS (rule 1 keeps them out of the state): they are
    # the one place the fleet says the record itself was unreadable.
    # THE FLEET HOLDS NOTHING BACK FOR A RETIRED SESSION: it works out reachable, idle and mail for one
    # like any other, and a retired session with a live process reads reachable yes. So the hold is
    # the watcher's (core/Wake.ps1), and this only reports.
    param([Parameter(Mandatory = $true)]$Row)
    if ($Row.retired -eq $true) { return "yes" }
    $said = New-Object System.Collections.ArrayList
    foreach ($n in @("reason", "reasons")) {
        $p = $Row.PSObject.Properties[$n]
        if ($null -eq $p) { continue }
        foreach ($v in @($p.Value)) { if ($v -is [string]) { [void]$said.Add($v) } }
    }
    if (@($said) -ccontains "record-unreadable") { return "unknown" }
    if ("$($Row.label)" -ceq "" -and (ConvertTo-HordeWezfleetWakerRole $Row.role) -ceq "unknown") { return "unknown" }
    return "no"
}

function Get-HordeWezfleetWakerTargets {
    # The port's Targets: form A's rows that are not retired, or that have unread mail (the header). A
    # retired one with mail is LISTED, saying retired, so the watcher can say once that its mail waits
    # for nobody; it is never nudged (core/Wake.ps1). And should the watcher ever ask, the fleet's own
    # nudge refuses a retired target too (refused, retired: the port's nothing) - two doors, both shut.
    $fleet = Read-HordeWezfleetWakerFleet
    if (-not $fleet.ok) {
        # HOW MANY READS IN A ROW HAVE FAILED goes with the unknown (wakers/Port.ps1, Targets): this waker
        # backs its reads off, so only it knows, and the watcher needs it to say when a failure has
        # stopped being a hiccup. After the fifth the read is already retried only every 300 s.
        $unknown = New-HordeUnknown -Reason $fleet.reason
        Add-Member -InputObject $unknown -MemberType NoteProperty -Name "failures" -Value ([int]$script:HordeWezfleetWakerFleetFailures.count)
        return $unknown
    }
    $list = New-Object System.Collections.ArrayList
    foreach ($row in @($fleet.rows.Values)) {
        $hasMail = ($null -ne $row.unreadCount -and $row.unreadCount -gt 0)
        if ($row.retired -and -not $hasMail) { continue }
        [void]$list.Add([pscustomobject]@{ id = $row.id; label = $row.label; role = (ConvertTo-HordeWezfleetWakerRole $row.role); parent = $row.parent; reachable = $row.reachable; retired = (Get-HordeWezfleetWakerRetired -Row $row) })
    }
    return (New-HordeKnown -Value $list.ToArray() -ObservedAt (Get-HordeWezfleetWakerTime))
}

function Get-HordeWezfleetWakerState {
    # The port's State (the header): form A's row, with no pane read; and, with -Full, the port's
    # Confirm: form B for that one session. THE WATCHER DECIDES WHO IS LOOKED AT, not this waker: it asks
    # -Full only for a session it is about to nudge, so a session that is backing off, capped or behind
    # the rate limit has no pane read at all (review of PR #211; core/Wake.ps1, THE LOOK COMES LAST).
    param([Parameter(Mandatory = $true)][string]$Id, [switch]$Full)
    $fleet = Read-HordeWezfleetWakerFleet
    if (-not $fleet.ok) { return (New-HordeUnknown -Reason $fleet.reason) }
    if (-not $fleet.rows.Contains($Id)) { return (New-HordeUnknown -Reason ("the fleet's state has no session " + $Id)) }
    $row = $fleet.rows[$Id]
    $state = Read-HordeWezfleetWakerState -Row $row
    if (-not $state.ok) { return (New-HordeUnknown -Reason $state.reason) }
    if ($Full) {
        $pane = Read-HordeWezfleetWakerPane -Id $Id
        if (-not $pane.ok) { return (New-HordeUnknown -Reason $pane.reason) }
        $state = Read-HordeWezfleetWakerState -Row $pane.row
        if (-not $state.ok) { return (New-HordeUnknown -Reason $state.reason) }
    }
    return (New-HordeKnown -Value $state.value -ObservedAt (Get-HordeWezfleetWakerTime))
}

function Send-HordeWezfleetWakerNudge {
    # The port's Nudge: form C. Every way the call can fail to say what happened is unreachable with the
    # reason (rules 4 and 5) - nothing is known to have been typed, and the watcher backs off and asks
    # again - except an answer about ANOTHER session, which is unknown: this waker cannot say what
    # happened to the one it was asked about.
    #
    # THE FLEET'S COMMAND OWNS THE TYPING, SO IT IS THE ONE THAT DECIDES WHEN THERE IS NO TIME LEFT TO TYPE.
    # This waker's deadline used to be 20 s and killed the process tree at it. On a throttled machine a
    # real nudge can run longer, and a kill that falls between the line being typed and Enter being
    # pressed leaves text in the box: the box is then never empty, and that session is never woken
    # again (review of PR #211). So the command is handed its BUDGET (-BudgetSeconds, 35 to 300) and
    # refuses to START typing when less than 30 s of it is left - the worst case of its own type-and-send
    # step, counted from its own process start - answering refused, budget-too-small, which is the
    # port's nothing with its reason: no attempt, and the first step of the back-off. THE BUDGET IS 60 s,
    # twice what the command needs to begin, so a start-up of up to 30 s still leaves it room; and this
    # waker's own kill is at three times the budget, 180 s, far above it. THE COMMAND'S RULE FOR ITS
    # CALLERS: never kill mail nudge before its budget + 40 s - 100 s here, which 180 s satisfies,
    # as three times any budget of 20 s or more does and the command takes none under 35. It is for a process that
    # hung, never a way to hurry one that is typing. Every answer carries elapsedMs, which is passed on
    # so the journal shows what a real nudge takes here.
    # IF THE KILL DOES FIRE, the outcome is killed, and it says so first in its reason: the box may hold
    # text now, and the watcher puts the session on its longest back-off and tells the warchief.
    # A COMMAND TOO OLD TO KNOW -BudgetSeconds answers with a usage error, which is not JSON. That is
    # unreachable, with a reason that says the command is too old. IT IS NEVER ASKED AGAIN WITHOUT THE
    # FLAG: an unbudgeted nudge is the defect this is here to end. A budget the command refuses (exit 2,
    # bad-budget) is this waker's own mistake and is said as that, with the command's code.
    param([Parameter(Mandatory = $true)][string]$Id)
    $at = Get-HordeWezfleetWakerTime
    $budget = [int]$script:HordeWezfleetWakerDeadlines.nudgeBudget
    $run = Start-HordeWezfleetWakerProcess -Argv @("mail", "nudge", "-To", $Id, "-BudgetSeconds", ("" + $budget), "-Json") -DeadlineSeconds (3 * $budget)
    if ($run.timedOut) { return (New-HordeKnown -Value ([pscustomobject]@{ id = $Id; outcome = "killed"; reason = ("nudge-killed: the nudge ran past " + (3 * $budget) + " s, three times its budget, and was stopped; its box may now hold the unsent line. " + $run.reason); at = $at }) -ObservedAt $at) }
    $read = Read-HordeWezfleetWakerJson -Run $run -What "wezfleet mail nudge"
    $tooOld = "tool-too-old: the fleet's command did not take mail nudge -BudgetSeconds as this waker asks it, so it may be older than the nudge budget, and it is not asked without one: "
    if (-not $read.ok) {
        $why = $read.reason
        if ($run.ok) { $why = $tooOld + $why }
        return (New-HordeKnown -Value ([pscustomobject]@{ id = $Id; outcome = "unreachable"; reason = $why; at = $at }) -ObservedAt $at)
    }
    $j = $read.json
    $said = "wezfleet mail nudge exit " + $run.exit
    if ([int]$run.exit -ne 0) { return (New-HordeKnown -Value ([pscustomobject]@{ id = $Id; outcome = "unreachable"; reason = (Get-HordeWezfleetWakerFailure -Json $j -Said $said); at = $at }) -ObservedAt $at) }
    $outcome = $j.PSObject.Properties["outcome"]
    if ($null -eq $outcome -or $outcome.Value -isnot [string] -or -not $script:HordeWezfleetWakerOutcomes.ContainsKey($outcome.Value) -or $script:HordeWezfleetWakerOutcomes[$outcome.Value] -isnot [string]) {
        return (New-HordeKnown -Value ([pscustomobject]@{ id = $Id; outcome = "unreachable"; reason = ($said + " answered without an outcome this waker reads: not the shape it reads"); at = $at }) -ObservedAt $at)
    }
    $target = $j.PSObject.Properties["target"]
    if ($null -ne $target -and $target.Value -is [string] -and $target.Value -cne "" -and $target.Value -cne $Id) { return (New-HordeUnknown -Reason ("wezfleet mail nudge answered about " + (ConvertTo-HordeWezfleetWakerLine $target.Value -Max 60) + ", not " + $Id)) }
    $code = ""
    $rp = $j.PSObject.Properties["reason"]
    if ($null -ne $rp -and $rp.Value -is [string]) { $code = ConvertTo-HordeWezfleetWakerLine $rp.Value -Max 80 }
    $detail = ""
    $dp = $j.PSObject.Properties["detail"]
    if ($null -ne $dp -and $dp.Value -is [string]) { $detail = ConvertTo-HordeWezfleetWakerLine $dp.Value -Max $script:HordeWezfleetWakerDetailChars }
    $why = $code
    if ($detail -ne "") { $why = $(if ($why -ne "") { $why + ": " + $detail } else { $detail }) }
    $mapped = $script:HordeWezfleetWakerOutcomes[$outcome.Value]
    # The port asks every outcome but woken to say why; the fleet's own word stands in when it gave none.
    if ($why -eq "" -and $mapped -cne "woken") { $why = "the fleet answered " + $outcome.Value }
    $answer = [ordered]@{ id = $Id; outcome = $mapped; reason = $why; at = $at }
    $took = $j.PSObject.Properties["elapsedMs"]
    if ($null -ne $took -and ($took.Value -is [int] -or $took.Value -is [long]) -and $took.Value -ge 0) { $answer["elapsedMs"] = [long]$took.Value }
    return (New-HordeKnown -Value ([pscustomobject]$answer) -ObservedAt $at)
}

$null = Register-HordeWaker -Name "wezfleet" `
    -Targets { Get-HordeWezfleetWakerTargets } `
    -State { param([string]$Id) Get-HordeWezfleetWakerState -Id $Id } `
    -Confirm { param([string]$Id) Get-HordeWezfleetWakerState -Id $Id -Full } `
    -Nudge { param([string]$Id) Send-HordeWezfleetWakerNudge -Id $Id } `
    -Source { Get-HordeWezfleetWakerSource } `
    -Begin { Clear-HordeWezfleetWakerPass }
