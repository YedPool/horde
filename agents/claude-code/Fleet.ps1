# agents/claude-code/Fleet.ps1 - this harness's half of hibernation (fleet/Port.ps1): which of its
# sessions are running now, and the line that resumes one.
#
# Everything here names this harness's files, flags or variables, so it lives in this folder
# (CONTRIBUTING 14). Nothing here starts a process: the host adapter runs the line this file builds.
#
# THE LIVENESS RULE IS A PORT OF THE TERMINAL SESSION-RESTORE PLUGIN'S RESTORE GUARD
# (plugin/resurrect/restore_guard.lua, branch windows-cr-enter, read 2026-10-16), so that Horde and the
# plugin answer "is this session running?" the same way and a wake can never start a conversation a
# second time. Its spec (plugin/resurrect/spec/restore_guard_spec.lua) is ported case by case to
# agents/claude-code/test/test-fleet-liveness.ps1. The rule, in the guard's own words:
#   The harness keeps one control file per running process in <profile>\.claude\sessions\<pid>.json
#   with sessionId, pid and procStart (the process start time, FILETIME ticks). A session is LIVE when
#   a control file names it, that pid is a running process, AND the process start time equals
#   procStart within one second (a reused pid cannot have started within a second of the process that
#   owned it before). A pid alone proves nothing: Windows reuses pids.
#   FAIL CLOSED: a folder that cannot be read, an EMPTY folder (most likely the wrong folder was read),
#   or a running process whose control file cannot be parsed makes the whole reading unknown; a process
#   that runs but whose start time cannot be read makes its session unknown; and an id with no live
#   control file while a session runs in the SAME folder is unknown too, because the harness can give a
#   conversation a new id (compaction, /resume) and that is the only trace.
# WHAT IS NOT PORTED, and why: the guard's PowerShell child, its 10 s time limit and its text protocol
# (S/END/ERR lines) exist because Lua cannot read files or processes itself; here the reading is done in
# process, through -ProcessStart, which a test replaces. The guard's ten-second snapshot cache and its
# claims table belong to a restore that checks pane after pane; a wake reads afresh for every decision
# and passes the ids it has itself just started as -Ignore, which is what the claims were for.
#
# LICENCE. The plugin is a fork of an MIT-licensed session-restore plugin, under this notice, carried here as
# CONTRIBUTING 10 requires for code ported from it:
#   MIT License
#   Copyright (c) 2024 Malthe Larsen
#   Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
#   associated documentation files (the "Software"), to deal in the Software without restriction,
#   including without limitation the rights to use, copy, modify, merge, publish, distribute,
#   sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
#   furnished to do so, subject to the following conditions:
#   The above copyright notice and this permission notice shall be included in all copies or
#   substantial portions of the Software.
#   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
#   NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
#   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
#   OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
#   CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\JsonText.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\ReadShared.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\ModuleSettings.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "fleet\Port.ps1")

# procStart and a process's start time are FILETIME ticks (100 ns). One second of slack, the guard's
# start_time_tolerance: they were identical on every file the guard's author checked.
$script:ClaudeCodeFleetStartTolerance = 10000000
# A session id is a lower-case uuid and nothing else (the guard's UUID_PATTERN).
$script:ClaudeCodeFleetIdPattern = '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z'
# The variables a session sets for itself and for its tools. A pane opened by a command run inside a
# session inherits them (measured 2026-10-16 in a session's own shell: CLAUDECODE, CLAUDE_PID,
# CLAUDE_EFFORT and twelve CLAUDE_CODE_* names, among them its session id and a messaging token), and a
# resumed session must not start believing it is a child of the one that woke it. CLAUDE_CONFIG_DIR is
# kept: it says where the harness's files are, and the woken session must find the same ones.
$script:ClaudeCodeFleetKeepVariables = @("CLAUDE_CONFIG_DIR")

function Get-ClaudeCodeFleetControlDirs {
    # The folders the control files are read from: <profile>\.claude\sessions, which must exist, and
    # <profile>\.claude-alt\sessions, the second account's, read when present (the guard's
    # control_dirs). USERPROFILE, never HOME: Git Bash sets HOME elsewhere, and a stray .claude\sessions
    # there would read as "nothing is running" (the guard's spec, "looks under USERPROFILE").
    param([string]$ProfileDir = $env:USERPROFILE)
    return @((Join-Path $ProfileDir ".claude\sessions"), (Join-Path $ProfileDir ".claude-alt\sessions"))
}

function Get-ClaudeCodeFleetProcessStart {
    # The real process lookup: the start time of process -ProcessId as FILETIME ticks text, "" when no
    # such process runs, or "?" when it runs and its start time cannot be read (the guard's QUERY_WORK).
    param([Parameter(Mandatory = $true)][long]$ProcessId)
    $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($null -eq $p) { return "" }
    try { return ("" + $p.StartTime.ToFileTimeUtc()) } catch { return "?" }
}

function Read-ClaudeCodeFleetRecords {
    # The control files of -Dirs as records { sessionId; pid; procStart; running; startTime; cwd }, or
    # { error } when they cannot be read. -ProcessStart (a pid -> "" | "?" | ticks) replaces the real
    # process lookup in a test; -ListFiles (a folder -> file paths, throwing when it cannot list)
    # replaces the folder listing.
    param([string[]]$Dirs = (Get-ClaudeCodeFleetControlDirs), [scriptblock]$ProcessStart = $null, [scriptblock]$ListFiles = $null)
    $records = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt @($Dirs).Count; $i++) {
        $d = @($Dirs)[$i]
        $files = $null
        try {
            if ($null -ne $ListFiles) { $files = @(& $ListFiles $d) }
            else {
                if (-not (Test-Path -LiteralPath $d -PathType Container)) {
                    if ($i -eq 0) { return [pscustomobject]@{ records = @(); error = ("control directory not found: " + $d) } }
                    continue
                }
                $files = @(Get-ChildItem -LiteralPath $d -Filter "*.json" -File -ErrorAction Stop | ForEach-Object { $_.FullName })
            }
        } catch { return [pscustomobject]@{ records = @(); error = ("the control directory " + $d + " could not be listed: " + $_.Exception.Message) } }
        foreach ($f in @($files)) {
            if ($null -eq $f) { continue }
            $sid = ""; $procId = ""; $ps = ""; $cwd = ""
            try {
                $j = ConvertFrom-HordeJson -Text (Read-HordeSharedText -Path $f)
                $sid = "" + $j.sessionId; $procId = "" + $j.pid; $ps = "" + $j.procStart; $cwd = "" + $j.cwd
            } catch { $sid = ""; $procId = ""; $ps = ""; $cwd = "" }
            # The harness names the file after the pid, so an unreadable file still names its process.
            if ($procId -cnotmatch '\A[0-9]{1,10}\z') { $procId = [System.IO.Path]::GetFileNameWithoutExtension("" + $f) }
            $running = $true; $start = "?"
            if ($procId -cmatch '\A[0-9]{1,10}\z') {
                $st = $null
                if ($null -ne $ProcessStart) { $st = & $ProcessStart ([long]$procId) } else { $st = Get-ClaudeCodeFleetProcessStart -ProcessId ([long]$procId) }
                if ("" + $st -eq "") { $running = $false } else { $start = "" + $st }
            }
            [void]$records.Add([pscustomobject]@{ sessionId = $sid; pid = $procId; procStart = $ps; running = $running; startTime = $start; cwd = $cwd })
        }
    }
    return [pscustomobject]@{ records = $records.ToArray(); error = "" }
}

function Get-ClaudeCodeFleetRecordState {
    # "dead": no such process, or the pid now belongs to a process that started at another time.
    # "live": running, and started when the control file says. "unknown": running, times not comparable.
    param([Parameter(Mandatory = $true)]$Record)
    if (-not $Record.running) { return "dead" }
    $expected = [long]0; $actual = [long]0
    if ("" + $Record.pid -cnotmatch '\A[0-9]{1,10}\z') { return "unknown" }
    if ("" + $Record.procStart -cnotmatch '\A[0-9]{1,19}\z' -or -not [long]::TryParse("" + $Record.procStart, [ref]$expected)) { return "unknown" }
    if ("" + $Record.startTime -cnotmatch '\A[0-9]{1,19}\z' -or -not [long]::TryParse("" + $Record.startTime, [ref]$actual)) { return "unknown" }
    if ([Math]::Abs($expected - $actual) -le $script:ClaudeCodeFleetStartTolerance) { return "live" }
    return "dead"
}

function New-ClaudeCodeFleetSnapshot {
    # The reading as the guard's build_snapshot makes it: { sessions (id -> { state; pid }); records
    # (each with its state); error }. error is "" when the reading may be trusted.
    param([Parameter(Mandatory = $true)]$Read)
    $rank = @{ dead = 1; unknown = 2; live = 3 }
    $sessions = @{}
    $records = New-Object System.Collections.ArrayList
    $err = "" + $Read.error
    if ($err -eq "" -and @($Read.records).Count -eq 0) {
        $err = "no control files were found, so what is running cannot be established"
    }
    foreach ($r in @($Read.records)) {
        if ($null -eq $r) { continue }
        $state = Get-ClaudeCodeFleetRecordState -Record $r
        [void]$records.Add([pscustomobject]@{ sessionId = "" + $r.sessionId; pid = "" + $r.pid; cwd = "" + $r.cwd; state = $state; startTime = "" + $r.startTime })
        if ("" + $r.sessionId -cnotmatch $script:ClaudeCodeFleetIdPattern) {
            # A control file nobody could read: if its process is gone it cannot matter; if it runs,
            # some session is live and nobody knows which, so no answer from this reading is safe.
            if ($state -cne "dead" -and $err -eq "") { $err = "the control file of running process " + $r.pid + " could not be read" }
            continue
        }
        $known = $sessions[$r.sessionId]
        if ($null -eq $known -or $rank[$state] -gt $rank[$known.state]) { $sessions[$r.sessionId] = [pscustomobject]@{ state = $state; pid = "" + $r.pid } }
    }
    return [pscustomobject]@{ sessions = $sessions; records = $records.ToArray(); error = $err }
}

function ConvertTo-ClaudeCodeFleetCwd {
    # A folder compared the way Windows compares it: slash direction, case and a trailing separator do
    # not matter (the guard's normalize_cwd). The terminal reports /C:/..., the harness C:\...
    param([AllowEmptyString()][string]$Cwd)
    if ($Cwd -eq "") { return "" }
    $n = $Cwd.Replace([string][char]92, "/")
    if ($n -cmatch '\A/[A-Za-z]:') { $n = $n.Substring(1) }
    return $n.TrimEnd("/").ToLowerInvariant()
}

function Get-ClaudeCodeFleetVerdict {
    # Is session -SessionId, last in folder -Cwd, running per -Snapshot? The guard's inspect, as
    # { state; kind; reason; pid }:
    #   state  "stopped" (safe to resume), "running", or "unknown" - which a wake treats as running.
    #   kind   "live", "reading" (nothing could be read), "unconfirmed" (a process is there, its start
    #          time is not known), "rotated" (maybe running under a new id), or "" when stopped.
    # -Ignore holds the ids a wake has itself just started: a session it started in this folder does not
    # make the next one of the same folder "rotated" (the guard's claims, spec "a session this restore
    # resumed does not block the next pane of the same directory").
    # -Since NARROWS THE ROTATED CASE FOR HIBERNATION (review of PR 318): when the sleeper stopped, or, with
    # no exit known, when the hibernation was taken (no code writes an exit yet: hibernate, slice 2, will). A running session whose own process started at or
    # before it was running beside the sleeper while the sleeper still ran under its own id, so it cannot
    # be the sleeper under a new one. Orcs and their wargs share folders (13 recorded sessions sat in 6
    # folders on 2026-10-16), and the guard's unnarrowed rule refused most of them. A start time that
    # cannot be read still counts. With no -Since, or no -Process (below), the guard's rule stands as it is.
    param([Parameter(Mandatory = $true)]$Snapshot, [Parameter(Mandatory = $true)][string]$SessionId, [AllowEmptyString()][string]$Cwd = "", [string[]]$Ignore = @(), $Since = $null, $Process = $null)
    # -Process: the sleeper's own process as recorded, { pid; start } (FILETIME ticks text). THE NARROWING
    # NEEDS IT (second review of PR 318, P1): a session can take a new id inside the same process (/clear,
    # /resume, a compaction), and that process began before the sleeper "stopped", so -Since alone would
    # pass it over and call the sleeper stopped while it runs. So that very process running, under any id,
    # is the sleeper running, and -Since narrows only OTHER processes. With no recorded process (an older
    # record) -Since is not used at all: the guard's own rule.
    $procPid = ""; $procStart = [long]0
    if ($null -ne $Process -and "" + $Process.pid -cmatch '\A[0-9]{1,10}\z' -and "" + $Process.start -cmatch '\A[0-9]{1,19}\z' -and [long]::TryParse("" + $Process.start, [ref]$procStart)) { $procPid = "" + $Process.pid }
    $sinceTicks = $null
    if ($procPid -ne "" -and $Since -is [datetime]) { $sinceTicks = $Since.ToUniversalTime().ToFileTimeUtc() }
    if ("" + $Snapshot.error -ne "") { return [pscustomobject]@{ state = "unknown"; kind = "reading"; reason = ("liveness unreadable (" + $Snapshot.error + ")"); pid = "" } }
    $s = $Snapshot.sessions[$SessionId]
    if ($null -eq $s -or $s.state -ceq "dead") {
        if ($procPid -ne "") {
            foreach ($r in @($Snapshot.records)) {
                $began = [long]0
                if ($r.state -ceq "live" -and "" + $r.pid -ceq $procPid -and [long]::TryParse("" + $r.startTime, [ref]$began) -and [Math]::Abs($began - $procStart) -le $script:ClaudeCodeFleetStartTolerance) {
                    return [pscustomobject]@{ state = "running"; kind = "same-process"; reason = ("its own process, pid " + $r.pid + ", still runs, now as session " + $r.sessionId); pid = "" + $r.pid }
                }
            }
        }
        $wanted = ConvertTo-ClaudeCodeFleetCwd -Cwd $Cwd
        foreach ($r in @($Snapshot.records)) {
            if ($r.state -ceq "dead" -or @($Ignore) -ccontains $r.sessionId) { continue }
            $began = [long]0
            if ($null -ne $sinceTicks -and "" + $r.startTime -cmatch '\A[0-9]{1,19}\z' -and [long]::TryParse("" + $r.startTime, [ref]$began) -and $began -le $sinceTicks) { continue }
            # A RUNNING SESSION WITH NO FOLDER may be in the sleeper's (second review of PR 318, P2): it is
            # never passed over as a folder of its own.
            if ((ConvertTo-ClaudeCodeFleetCwd -Cwd $r.cwd) -eq "") {
                return [pscustomobject]@{ state = "unknown"; kind = "rotated"; reason = ("not running under this id, and running pid " + $r.pid + " names no folder in its control file, so it may be the same conversation under a new id - resume it by hand if it is not"); pid = "" + $r.pid }
            }
            if ($wanted -eq "" -or (ConvertTo-ClaudeCodeFleetCwd -Cwd $r.cwd) -ceq $wanted) {
                return [pscustomobject]@{ state = "unknown"; kind = "rotated"; reason = ("not running under this id, but in the same folder as running pid " + $r.pid + ", so it may be the same conversation under a new id - resume it by hand if it is not"); pid = "" + $r.pid }
            }
        }
        return [pscustomobject]@{ state = "stopped"; kind = ""; reason = ""; pid = "" }
    }
    if ($s.state -ceq "live") { return [pscustomobject]@{ state = "running"; kind = "live"; reason = ("already running pid " + $s.pid); pid = "" + $s.pid } }
    return [pscustomobject]@{ state = "unknown"; kind = "unconfirmed"; reason = ("liveness unreadable (pid " + $s.pid + " is running but its start time could not be confirmed)"); pid = "" + $s.pid }
}

function Get-ClaudeCodeFleetRunning {
    # The sessions -Snapshot shows live, { sessionId; pid; cwd; start } each: where a wake looks for a
    # session that came up under a new id, and where a record takes each session's process from.
    param([Parameter(Mandatory = $true)]$Snapshot)
    return @(@($Snapshot.records) | Where-Object { $_.state -ceq "live" -and $_.sessionId -cmatch $script:ClaudeCodeFleetIdPattern } | ForEach-Object { [pscustomobject]@{ sessionId = $_.sessionId; pid = $_.pid; cwd = $_.cwd; start = $_.startTime } })
}

# THE PROGRAM A WOKEN SESSION IS RESUMED WITH can be named in full (<HORDE_HOME>\settings\
# claude-code-fleet.json, setting command). Left out, it is the harness's command as the woken pane's shell
# finds it. WHY A SETTING: a terminal pane takes its PATH from the terminal, not from the process that
# spawns it (measured 2026-10-16 by test/e2e/e2e-fleet.ps1, whose stand-in, first on the
# spawning PATH, lost to the real command in all four panes); so a scenario that must never start the real
# harness names its stand-in here.
$script:ClaudeCodeFleetSettings = New-HordeModuleSettings -Module "claude-code-fleet" -Settings @(
    @{ name = "command"; kind = "text"; default = ""; min = 0; max = 400; what = "The program a woken session is resumed with, as an absolute path to a .ps1, .exe or .cmd; left out, the harness's own command as the pane's shell finds it." }
)

function Get-ClaudeCodeFleetSettings {
    # The settings as { state; values; findings; path }, from the one file under Horde's home.
    param([string]$HordeHome = "")
    return (Get-HordeModuleSettings -Declaration $script:ClaudeCodeFleetSettings -HordeHome $HordeHome)
}

function Get-ClaudeCodeFleetResumeLine {
    # The line a shell runs to resume one session: the program, --resume and the id, nothing else (the
    # guard's resume_target rebuilds exactly this from fixed parts). An id that is not a lower-case uuid
    # is refused, never quoted: the line is run by a shell. -Command, a program named in full, is called
    # with the call operator inside single quotes, so it must be absolute, end .ps1, .exe or .cmd, and hold
    # no quote and no control character; anything else builds no line.
    param([string]$SessionId = "", [string]$Command = "")
    if ($SessionId -cnotmatch $script:ClaudeCodeFleetIdPattern) { throw ("'" + $SessionId + "' is not a session id, so no resume line is built for it") }
    if ($Command -eq "") { return ("claude --resume " + $SessionId) }
    if ($Command -cmatch "['" + [char]34 + "\x00-\x1F\x7F]" -or $Command -notmatch '\A[A-Za-z]:\\' -or $Command -notmatch '\.(ps1|exe|cmd)\z') { throw ("'" + $Command + "' is not a program named in full (an absolute .ps1, .exe or .cmd with no quote), so no resume line is built") }
    return ("& '" + $Command + "' --resume " + $SessionId)
}

function Get-ClaudeCodeFleetScrub {
    # The environment map a resumed session's pane is started with: every variable of -Names that the
    # harness sets for a session and its tools, mapped to $null (removed). -Names defaults to this
    # process's own variables.
    param([string[]]$Names = $null)
    if ($null -eq $Names) { $Names = @(Get-ChildItem -Path Env: | ForEach-Object { $_.Name }) }
    $out = @{}
    foreach ($n in @($Names)) {
        if ("" + $n -imatch '\ACLAUDE' -and $script:ClaudeCodeFleetKeepVariables -inotcontains $n) { $out[$n] = $null }
    }
    return $out
}

# THE TURNS A PERSON TYPED (the port's LastTyped; hibernate never puts to sleep a session the founder
# typed into lately). Read from the transcript's TAIL, never the whole file: a transcript is appended to
# in time order, so the tail back to -Since is all that can hold one. Read 2026-10-16 from the user lines
# of the 80 newest local transcripts (shapes and first words only):
#   origin.kind "human"   every line typed into the box: promptSource typed 4,792, queued 270,
#                         suggestion_accepted 8. The fleet's mail pointer ("wezfleet: a message is
#                         waiting for you ...", 3,677 + 61 queued) and its spawn and handoff texts are
#                         typed into the box too and carry the same mark: they are returned here and told
#                         apart by fleet/Hibernate.ps1, which knows the fleet's lines.
#   no origin             "[Request interrupted by user..." (55: a person pressed Escape; the fleet's tools
#                         never send Escape) and "<command-name>/..." (a slash command typed, 32) - both
#                         returned. A compaction summary (99), a command's echoed output and every
#                         other no-origin line are not.
#   isMeta                mail handed over by a Stop hook ("Stop hook feedback:\nMESSAGE FROM ...", 800+),
#                         reminders and skill texts: never a person's, never returned.
# THE TIME IS THE LINE'S OWN "timestamp" TEXT, read as written (UTC, Z), not the parsed value: PowerShell 7
# turns a date-shaped string into a local [datetime] (agents/claude-code/Conversation.ps1 says so).
$script:ClaudeCodeFleetTypedTailBytes = 4194304
$script:ClaudeCodeFleetTypedMostBytes = 67108864
$script:ClaudeCodeFleetTypedTextChars = 200
$script:ClaudeCodeFleetStampPattern = '"timestamp":"([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,7})?Z)"'

function ConvertFrom-ClaudeCodeFleetStamp {
    # The first "timestamp" of -Line as a UTC [datetime], or $null.
    param([AllowEmptyString()][string]$Line)
    $m = [regex]::Match($Line, $script:ClaudeCodeFleetStampPattern)
    if (-not $m.Success) { return $null }
    $at = [datetime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
    if ([datetime]::TryParse($m.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$at)) { return $at }
    return $null
}

function ConvertFrom-ClaudeCodeFleetTypedLine {
    # One transcript line as a typed turn { at; text }, or $null when it is not one (the comment above).
    param([AllowEmptyString()][string]$Line)
    if ($Line.IndexOf('"type":"user"', [System.StringComparison]::Ordinal) -lt 0) { return $null }
    $j = $null
    try { $j = ConvertFrom-HordeJson -Text $Line } catch { return $null }
    if ($null -eq $j -or "" + $j.type -cne "user") { return $null }
    foreach ($flag in @("isSidechain", "isMeta", "isCompactSummary")) {
        $p = $j.PSObject.Properties[$flag]
        if ($null -ne $p -and $p.Value -eq $true) { return $null }
    }
    $msg = $j.PSObject.Properties["message"]
    if ($null -eq $msg -or $null -eq $msg.Value) { return $null }
    $content = $msg.Value.PSObject.Properties["content"]
    if ($null -eq $content) { return $null }
    $text = $null
    if ($content.Value -is [string]) { $text = $content.Value }
    else {
        foreach ($b in @($content.Value)) {
            if ($null -ne $b -and $b.PSObject.Properties["type"] -and "" + $b.type -ceq "text" -and $b.PSObject.Properties["text"]) { $text = "" + $b.text; break }
        }
    }
    if ($null -eq $text) { return $null }
    $kind = ""
    $origin = $j.PSObject.Properties["origin"]
    if ($null -ne $origin -and $null -ne $origin.Value -and $origin.Value.PSObject.Properties["kind"]) { $kind = "" + $origin.Value.kind }
    $typed = $false
    if ($kind -ceq "human") { $typed = $true }
    elseif ($null -eq $origin -and ($text.StartsWith("[Request interrupted by user", [System.StringComparison]::Ordinal) -or $text.StartsWith("<command-name>/", [System.StringComparison]::Ordinal))) { $typed = $true }
    if (-not $typed) { return $null }
    $at = ConvertFrom-ClaudeCodeFleetStamp -Line $Line
    if ($null -eq $at) { return $null }
    if ($text.Length -gt $script:ClaudeCodeFleetTypedTextChars) { $text = $text.Substring(0, $script:ClaudeCodeFleetTypedTextChars) }
    return [pscustomobject]@{ at = $at; text = $text }
}

function Get-ClaudeCodeFleetTyped {
    # The port's LastTyped: the turns a person typed into the session whose transcript is -Path, at or
    # after -Since, newest first, as an answer; unknown when the file cannot be read. The tail read grows
    # four times over until its first whole line is older than -Since or it reaches the file's start, and
    # past -MostBytes it gives up as unknown rather than answer from part of the window.
    param([AllowEmptyString()][string]$Path, [Parameter(Mandatory = $true)][datetime]$Since,
          [long]$TailBytes = $script:ClaudeCodeFleetTypedTailBytes, [long]$MostBytes = $script:ClaudeCodeFleetTypedMostBytes)
    if ($Path -eq "" -or -not [System.IO.Path]::IsPathRooted($Path)) { return (New-HordeUnknown -Reason "the registry names no transcript for it") }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return (New-HordeUnknown -Reason ("its transcript is not there: " + (Split-Path -Leaf $Path))) }
    $sinceUtc = $Since.ToUniversalTime()
    $want = [Math]::Max([long]1024, $TailBytes)
    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
        try {
            while ($true) {
                $len = $fs.Length
                $start = [Math]::Max([long]0, $len - $want)
                $count = [int]($len - $start)
                $buf = New-Object byte[] $count
                $fs.Position = $start
                $got = 0
                while ($got -lt $count) { $n = $fs.Read($buf, $got, $count - $got); if ($n -le 0) { break }; $got += $n }
                $lines = @([System.Text.Encoding]::UTF8.GetString($buf, 0, $got) -split "`n")
                # A tail that starts mid-line drops that part; the file's own first line is whole.
                if ($start -gt 0 -and $lines.Count -gt 0) { $lines = @($lines | Select-Object -Skip 1) }
                $first = $null
                foreach ($l in $lines) { $first = ConvertFrom-ClaudeCodeFleetStamp -Line $l; if ($null -ne $first) { break } }
                if ($start -eq 0 -or ($null -ne $first -and $first -lt $sinceUtc)) {
                    $out = New-Object System.Collections.ArrayList
                    foreach ($l in $lines) {
                        $t = ConvertFrom-ClaudeCodeFleetTypedLine -Line $l.TrimEnd([char]13)
                        if ($null -ne $t -and $t.at -ge $sinceUtc) { [void]$out.Add($t) }
                    }
                    return (New-HordeKnown -Value @($out | Sort-Object -Property at -Descending))
                }
                if ($want -ge $MostBytes) { return (New-HordeUnknown -Reason ("its transcript's last " + $want + " bytes are all newer than the window, so the window was not read whole")) }
                $want = [Math]::Min($MostBytes, $want * 4)
            }
        } finally { $fs.Dispose() }
    } catch { return (New-HordeUnknown -Reason ("its transcript could not be read: " + $_.Exception.Message)) }
}

Register-HordeFleetAgent -Name "claude-code" `
    -Snapshot { New-ClaudeCodeFleetSnapshot -Read (Read-ClaudeCodeFleetRecords) } `
    -Verdict { param($snapshot, $id, $cwd, $ignore, $since, $process) Get-ClaudeCodeFleetVerdict -Snapshot $snapshot -SessionId $id -Cwd $cwd -Ignore $ignore -Since $since -Process $process } `
    -Running { param($snapshot) Get-ClaudeCodeFleetRunning -Snapshot $snapshot } `
    -ResumeLine { param($id) $st = Get-ClaudeCodeFleetSettings; if ("" + $st.state -cne "defaults" -and "" + $st.state -cne "read") { throw ("the harness's fleet settings are refused, so no resume line is built: " + (@($st.findings) -join "; ")) }; Get-ClaudeCodeFleetResumeLine -SessionId $id -Command ("" + $st.values.command) } `
    -Scrub { Get-ClaudeCodeFleetScrub } `
    -LastTyped { param($path, $since) Get-ClaudeCodeFleetTyped -Path $path -Since $since }
