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
        [void]$records.Add([pscustomobject]@{ sessionId = "" + $r.sessionId; pid = "" + $r.pid; cwd = "" + $r.cwd; state = $state })
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
    param([Parameter(Mandatory = $true)]$Snapshot, [Parameter(Mandatory = $true)][string]$SessionId, [AllowEmptyString()][string]$Cwd = "", [string[]]$Ignore = @())
    if ("" + $Snapshot.error -ne "") { return [pscustomobject]@{ state = "unknown"; kind = "reading"; reason = ("liveness unreadable (" + $Snapshot.error + ")"); pid = "" } }
    $s = $Snapshot.sessions[$SessionId]
    if ($null -eq $s -or $s.state -ceq "dead") {
        $wanted = ConvertTo-ClaudeCodeFleetCwd -Cwd $Cwd
        foreach ($r in @($Snapshot.records)) {
            if ($r.state -ceq "dead" -or @($Ignore) -ccontains $r.sessionId) { continue }
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
    # The sessions -Snapshot shows live, { sessionId; pid; cwd } each: where a wake looks for a session
    # that came up under a new id.
    param([Parameter(Mandatory = $true)]$Snapshot)
    return @(@($Snapshot.records) | Where-Object { $_.state -ceq "live" -and $_.sessionId -cmatch $script:ClaudeCodeFleetIdPattern } | ForEach-Object { [pscustomobject]@{ sessionId = $_.sessionId; pid = $_.pid; cwd = $_.cwd } })
}

function Get-ClaudeCodeFleetResumeLine {
    # The line a shell runs to resume one session: the program, --resume and the id, nothing else (the
    # guard's resume_target rebuilds exactly this from fixed parts). An id that is not a lower-case uuid
    # is refused, never quoted: the line is run by a shell.
    param([string]$SessionId = "")
    if ($SessionId -cnotmatch $script:ClaudeCodeFleetIdPattern) { throw ("'" + $SessionId + "' is not a session id, so no resume line is built for it") }
    return ("claude --resume " + $SessionId)
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

Register-HordeFleetAgent -Name "claude-code" `
    -Snapshot { New-ClaudeCodeFleetSnapshot -Read (Read-ClaudeCodeFleetRecords) } `
    -Verdict { param($snapshot, $id, $cwd, $ignore) Get-ClaudeCodeFleetVerdict -Snapshot $snapshot -SessionId $id -Cwd $cwd -Ignore $ignore } `
    -Running { param($snapshot) Get-ClaudeCodeFleetRunning -Snapshot $snapshot } `
    -ResumeLine { param($id) Get-ClaudeCodeFleetResumeLine -SessionId $id } `
    -Scrub { Get-ClaudeCodeFleetScrub }
