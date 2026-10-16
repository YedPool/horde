# DOES HIBERNATION ASK "IS THIS SESSION RUNNING?" EXACTLY AS THE RESTORE GUARD DOES, AND FAIL CLOSED?
#
# agents/claude-code/Fleet.ps1 ports the terminal session-restore plugin's restore guard
# (plugin/resurrect/restore_guard.lua). Each section below is one case of the guard's own spec
# (plugin/resurrect/spec/restore_guard_spec.lua, read 2026-10-16), named by its it(...) text, so the two
# can be compared line by line. The control files are real files in a folder this suite creates under
# TEMP; the process table is the one seam (-ProcessStart), and the real lookup is checked on its own
# against this very process. Nothing here reads the user's own control files or starts anything.
#
# NOT PORTED, and why: "the answer from the process query is cut short" and "an answer that took too
# long" test the guard's text protocol and its child PowerShell, which the port does not have (it reads
# in process); "reads the control files once for a whole restore" tests its cache, which a wake does not
# use (it reads afresh for every decision); the cases about typing, panes, windows and the selector are
# the guard's restore, not its liveness rule.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "agents\claude-code\Fleet.ps1")

function Section { param([string]$Title) Write-Host ""; Write-Host ("--- " + $Title + " ---") -ForegroundColor Cyan }

$LIVE = "aaaaaaaa-1111-4111-8111-111111111111"
$DEAD = "bbbbbbbb-2222-4222-8222-222222222222"
$REUSED = "cccccccc-3333-4333-8333-333333333333"
$OTHER = "dddddddd-4444-4444-8444-444444444444"
$START = "134364209037804403"
$work = Join-Path $env:TEMP ("horde-fleet-liveness-" + [guid]::NewGuid().ToString("N"))
$dir = Join-Path $work "sessions"
[void](New-Item -ItemType Directory -Path $dir -Force)

function Set-ControlFiles {
    # Replace the folder's control files with -Rows: @{ sid; pid; ps; cwd } each, or @{ pid; raw } for a
    # file that is not JSON.
    param([object[]]$Rows = @())
    Get-ChildItem -LiteralPath $dir -File | Remove-Item -Force
    foreach ($r in @($Rows)) {
        $path = Join-Path $dir ("" + $r.pid + ".json")
        if ($r.ContainsKey("raw")) { [System.IO.File]::WriteAllText($path, $r.raw); continue }
        $j = [ordered]@{ pid = [int]$r.pid; sessionId = $r.sid; cwd = $r.cwd; procStart = $r.ps; kind = "interactive" }
        [System.IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject $j))
    }
}

# The usual world of the guard's spec: LIVE runs with its start time; DEAD's process is gone; REUSED's
# pid now belongs to a process that started two seconds later.
$table = @{ "4242" = $START; "6161" = ("" + ([long]$START + 20000000)) }
$processStart = { param($p) $k = "" + $p; if ($table.ContainsKey($k)) { $table[$k] } else { "" } }.GetNewClosure()
function Usual-World {
    Set-ControlFiles @(
        @{ sid = $LIVE; pid = 4242; ps = $START; cwd = "C:\work\live" },
        @{ sid = $DEAD; pid = 5151; ps = $START; cwd = "C:\work\dead" },
        @{ sid = $REUSED; pid = 6161; ps = $START; cwd = "C:\work\reused" })
}
function Read-Snapshot { param([scriptblock]$ListFiles = $null) return (New-ClaudeCodeFleetSnapshot -Read (Read-ClaudeCodeFleetRecords -Dirs @($dir) -ProcessStart $processStart -ListFiles $ListFiles)) }
function Verdict { param($Snap, [string]$Id, [string]$Cwd = "", [string[]]$Ignore = @(), $Since = $null, $Process = $null) return (Get-ClaudeCodeFleetVerdict -Snapshot $Snap -SessionId $Id -Cwd $Cwd -Ignore $Ignore -Since $Since -Process $Process) }

# NOT ONE try AROUND THE CHECKS (test/test-files-cli.ps1 says why): after an error no check expected, the
# trap goes on with the next statement of the script, and one try around everything is one statement.
Section "restore guard: resume commands"
Usual-World
$snap = Read-Snapshot
Check ("" + $snap.error -eq "") ("CONTROL: the usual world reads with no error (" + $snap.error + ")")
$v = Verdict $snap $LIVE "C:\work\live"
Check ($v.state -ceq "running" -and $v.kind -ceq "live") ("a session whose control file names a running process with a matching start time is running (" + $v.state + "/" + $v.kind + ")")
$v = Verdict $snap $DEAD "C:\work\dead"
Check ($v.state -ceq "stopped") ("a session whose control file names a process that is gone is stopped (" + $v.state + ")")
$v = Verdict $snap $REUSED "C:\work\reused"
Check ($v.state -ceq "stopped") ("a session whose pid was reused by a process with another start time is stopped (" + $v.state + ")")
$v = Verdict $snap $OTHER "C:\work\elsewhere"
Check ($v.state -ceq "stopped") ("a session that has no control file is stopped (" + $v.state + ")")

# The tolerance itself: half a second apart is the same process, a second and a half is not.
$table["6161"] = "" + ([long]$START + 5000000)
$v = Verdict (Read-Snapshot) $REUSED "C:\work\reused"
Check ($v.state -ceq "running") ("start times half a second apart are the same process: one second of slack, as the guard's start_time_tolerance (" + $v.state + ")")
$table["6161"] = "" + ([long]$START + 15000000)
$v = Verdict (Read-Snapshot) $REUSED "C:\work\reused"
Check ($v.state -ceq "stopped") ("start times a second and a half apart are another process (" + $v.state + ")")
$table["6161"] = "" + ([long]$START + 20000000)

# "resumes nothing when the control directory cannot be read"
$snap = Read-Snapshot -ListFiles { param($d) throw "Access to the path is denied." }
$a = Verdict $snap $DEAD "C:\work\dead"; $b = Verdict $snap $OTHER "C:\work\elsewhere"
Check ($a.state -ceq "unknown" -and $a.kind -ceq "reading" -and $b.state -ceq "unknown") ("a control folder that cannot be listed makes every session unknown, never stopped (" + $a.state + ", " + $b.state + ")")
$snap = New-ClaudeCodeFleetSnapshot -Read (Read-ClaudeCodeFleetRecords -Dirs @((Join-Path $work "no-such"), $dir) -ProcessStart $processStart)
Check ((Verdict $snap $DEAD).state -ceq "unknown" -and $snap.error -like "*control directory not found*") ("a FIRST control folder that is not there is unknown (" + $snap.error + ")")
$snap = New-ClaudeCodeFleetSnapshot -Read (Read-ClaudeCodeFleetRecords -Dirs @($dir, (Join-Path $work "no-such")) -ProcessStart $processStart)
Check ("" + $snap.error -eq "" -and (Verdict $snap $DEAD "C:\work\dead").state -ceq "stopped") "CONTROL: a later folder that is not there (the second account's) is skipped"

# "does not resume when the process is running but its start time cannot be read"
Set-ControlFiles @(@{ sid = $OTHER; pid = 7171; ps = $START; cwd = "C:\work" })
$table["7171"] = "?"
$v = Verdict (Read-Snapshot) $OTHER "C:\work"
Check ($v.state -ceq "unknown" -and $v.kind -ceq "unconfirmed") ("a running process whose start time cannot be read is unknown (" + $v.state + "/" + $v.kind + ")")
$table.Remove("7171")

# "resumes nothing when a running process's control file could not be parsed"
$table["8181"] = $START
Set-ControlFiles @(@{ sid = $DEAD; pid = 5151; ps = $START; cwd = "C:\work\dead" }, @{ pid = 8181; raw = "{ not json" })
$v = Verdict (Read-Snapshot) $DEAD "C:\work\dead"
Check ($v.state -ceq "unknown" -and $v.kind -ceq "reading") ("a running process whose control file cannot be parsed makes the whole reading unknown (" + $v.state + "/" + $v.kind + ")")
# "ignores an unparseable control file whose process is gone"
$table.Remove("8181")
$v = Verdict (Read-Snapshot) $DEAD "C:\work\dead"
Check ($v.state -ceq "stopped") ("an unparseable control file whose process is gone is ignored (" + $v.state + ")")
# The pid of an unreadable file is its name: the harness names the file after the pid.
$table["8181"] = $START
$r = Read-ClaudeCodeFleetRecords -Dirs @($dir) -ProcessStart $processStart
Check (@($r.records | Where-Object { $_.pid -ceq "8181" -and $_.running }).Count -eq 1) "an unparseable control file still names its process, by its file name"
$table.Remove("8181")

Section "restore guard: the control folder"
# "an existing but empty control folder is unknown, not 'nothing running'"
Set-ControlFiles @()
$v = Verdict (Read-Snapshot) $DEAD "C:\work\dead"
Check ($v.state -ceq "unknown" -and $v.reason -like "*no control files*") ("an empty control folder is unknown, not 'nothing running' (" + $v.reason + ")")
# "looks under USERPROFILE on Windows even when HOME points elsewhere"
$dirs = @(Get-ClaudeCodeFleetControlDirs -ProfileDir "C:\Users\me")
Check ($dirs[0] -ceq "C:\Users\me\.claude\sessions" -and $dirs[1] -ceq "C:\Users\me\.claude-alt\sessions") ("the control folders are the profile's: " + ($dirs -join ", "))
$savedHome = $env:HOME
try { $env:HOME = "C:\stray\home"; $d0 = @(Get-ClaudeCodeFleetControlDirs)[0] } finally { $env:HOME = $savedHome }
Check (-not $d0.Contains("stray") -and $d0.EndsWith("\.claude\sessions")) ("HOME is never read for them (" + $d0 + ")")

Section "restore guard: a running session in the same directory"
Usual-World
$snap = Read-Snapshot
foreach ($saved in @("C:\work\live", "c:/WORK/Live/", "C:\work\live\", "/C:/work/live")) {
    $v = Verdict $snap $OTHER $saved
    Check ($v.state -ceq "unknown" -and $v.kind -ceq "rotated") ("an id with no control file while a session runs in " + $saved + " is unknown: it may be the same conversation under a new id (" + $v.state + "/" + $v.kind + ")")
}
$v = Verdict $snap $OTHER "C:\work\elsewhere"
Check ($v.state -ceq "stopped") "CONTROL: it is stopped when the running sessions are in other folders"
$v = Verdict $snap $OTHER ""
Check ($v.state -ceq "unknown" -and $v.kind -ceq "rotated") "with no folder to compare and a session running, it is unknown"
$v = Verdict $snap $OTHER "C:\work\live" -Ignore @($LIVE)
Check ($v.state -ceq "stopped") "a session this wake started itself does not block the next one of the same folder"
$v = Verdict $snap $DEAD "C:\work\live"
Check ($v.state -ceq "unknown" -and $v.kind -ceq "rotated") "a dead control file in a folder where another session runs is unknown too, as in the guard"

Section "narrowed for hibernation: only a session that started after the sleeper stopped can be its new id"
# Orcs and their wargs share folders (13 of 13 sessions recorded on 2026-10-16 sat in 6 folders). The
# guard's rule refused a sleeper whenever ANY session ran in its folder; a session that was already
# running while the sleeper still ran under its own id cannot be the sleeper under a new one. -Since is
# when the sleeper stopped (or the hibernation was taken): only a session started after it counts.
# THE NARROWING NEEDS THE SLEEPER'S OWN PROCESS (review of PR 318): a session can change its id inside
# the same process (/clear, /resume, a compaction), and that process started before the sleeper "stopped".
# So -Since is used only with -Process, the pid and start time recorded for the sleeper: that very process
# running under any id is the sleeper running, and only OTHER processes are narrowed. With no -Process
# (an older record) the guard's own rule stands.
$startedAt = [DateTime]::FromFileTimeUtc([long]$START)
$gone = [pscustomobject]@{ pid = "9393"; start = $START }
Usual-World
$snap = Read-Snapshot
$v = Verdict $snap $OTHER "C:\work\live" -Since $startedAt.AddMinutes(5) -Process $gone
Check ($v.state -ceq "stopped") ("a session that started before the sleeper stopped is not its new id: stopped (" + $v.state + "/" + $v.kind + ")")
$v = Verdict $snap $OTHER "C:\work\live" -Since $startedAt.AddMinutes(-5) -Process $gone
Check ($v.state -ceq "unknown" -and $v.kind -ceq "rotated") ("CONTROL: one that started after the sleeper stopped may be its new id: unknown (" + $v.state + "/" + $v.kind + ")")
$v = Verdict $snap $OTHER "C:\work\live" -Since $startedAt -Process $gone
Check ($v.state -ceq "stopped") "one that started at the very moment counts as already running"
$v = Verdict $snap $OTHER "C:\work\live"
Check ($v.state -ceq "unknown" -and $v.kind -ceq "rotated") "with no -Since, the guard's own rule stands: unknown"
$table["4242"] = "?"
$v = Verdict (Read-Snapshot) $OTHER "C:\work\live" -Since $startedAt.AddMinutes(5) -Process $gone
$table["4242"] = $START
Check ($v.state -ceq "unknown" -and $v.kind -ceq "rotated") ("a running session whose start cannot be read may be the new id: unknown (" + $v.state + "/" + $v.kind + ")")
# P1 of the review: the sleeper OTHER was recorded in pid 4242, and that same process now runs as LIVE.
$v = Verdict $snap $OTHER "C:\work\live" -Since $startedAt.AddMinutes(5) -Process ([pscustomobject]@{ pid = "4242"; start = $START })
Check ($v.state -ceq "running" -and $v.pid -ceq "4242" -and $v.reason -like "*4242*") ("its own recorded process still running under another id is the sleeper running, however early it started (" + $v.state + "/" + $v.kind + ": " + $v.reason + ")")
$v = Verdict $snap $OTHER "C:\work\elsewhere" -Process ([pscustomobject]@{ pid = "4242"; start = $START })
Check ($v.state -ceq "running") "in whatever folder it now runs"
$v = Verdict $snap $OTHER "C:\work\live" -Since $startedAt.AddMinutes(5) -Process ([pscustomobject]@{ pid = "4242"; start = ("" + ([long]$START - 50000000)) })
Check ($v.state -ceq "stopped") ("CONTROL: the same pid with another start time is another process, and is narrowed like any other (" + $v.state + ")")
$v = Verdict $snap $OTHER "C:\work\live" -Since $startedAt.AddMinutes(5)
Check ($v.state -ceq "unknown" -and $v.kind -ceq "rotated") ("with no recorded process -Since is not used: the guard's own rule, unknown (" + $v.state + "/" + $v.kind + ")")
$v = Verdict $snap $OTHER "C:\work\live" -Since $startedAt.AddMinutes(5) -Process ([pscustomobject]@{ pid = ""; start = "" })
Check ($v.state -ceq "unknown") "and so with an empty one"

Section "a running session whose folder cannot be read may be the sleeper"
# P2 of the review: a live control file with no cwd was compared as a folder of its own and passed over.
Set-ControlFiles @(@{ sid = $LIVE; pid = 4242; ps = $START; cwd = "" })
$v = Verdict (Read-Snapshot) $OTHER "C:\work\live" -Since $startedAt.AddMinutes(-5) -Process $gone
Check ($v.state -ceq "unknown" -and $v.reason -like "*4242*") ("a live session with no folder in its control file is unknown, never passed over (" + $v.state + "/" + $v.kind + ")")
$v = Verdict (Read-Snapshot) $OTHER "C:\work\live" -Ignore @($LIVE)
Check ($v.state -ceq "stopped") "CONTROL: unless it is one the wake started itself"

Section "the real process lookup"
$mine = Get-ClaudeCodeFleetProcessStart -ProcessId $PID
Check ($mine -ceq ("" + (Get-Process -Id $PID).StartTime.ToFileTimeUtc())) ("this process's own start time is read as FILETIME ticks (" + $mine + ")")
$none = Get-ClaudeCodeFleetProcessStart -ProcessId 999999991
Check ($none -ceq "") "a pid no process has reads as not running"
Usual-World
$r = Read-ClaudeCodeFleetRecords -Dirs @($dir)
Check ("" + $r.error -eq "" -and @($r.records).Count -eq 3) "CONTROL: the default lookup reads the same folder"

Section "the running sessions carry their start time, for a record to keep"
Usual-World
$run = @(Get-ClaudeCodeFleetRunning -Snapshot (Read-Snapshot))
Check ($run.Count -eq 1 -and $run[0].sessionId -ceq $LIVE -and $run[0].pid -ceq "4242" -and $run[0].start -ceq $START) ("each live session comes with its pid and its process start time (" + (@($run | ForEach-Object { $_.sessionId + "/" + $_.pid + "/" + $_.start }) -join ", ") + ")")

Section "the resume line and the environment"
Check ((Get-ClaudeCodeFleetResumeLine -SessionId $LIVE) -ceq ("claude --resume " + $LIVE)) "the resume line is exactly the program, --resume and the id"
foreach ($bad in @("AAAAAAAA-1111-4111-8111-111111111111", ($LIVE + " --x"), ($LIVE + "; calc"), "")) {
    Check (Throws { Get-ClaudeCodeFleetResumeLine -SessionId $bad } "not a session id") ("no line is built for the id '" + $bad + "'")
}
$scrub = Get-ClaudeCodeFleetScrub -Names @("CLAUDECODE", "CLAUDE_CODE_SESSION_ID", "CLAUDE_PID", "CLAUDE_CODE_MESSAGING_TOKEN", "CLAUDE_CONFIG_DIR", "PATH")
Check ($scrub.ContainsKey("CLAUDECODE") -and $scrub.ContainsKey("CLAUDE_CODE_SESSION_ID") -and $scrub.ContainsKey("CLAUDE_PID") -and $scrub.ContainsKey("CLAUDE_CODE_MESSAGING_TOKEN") -and $null -eq $scrub["CLAUDECODE"]) "the woken pane does not inherit the waking session's own variables"
Check (-not $scrub.ContainsKey("CLAUDE_CONFIG_DIR") -and -not $scrub.ContainsKey("PATH")) "CONTROL: where the harness keeps its files, and everything else, is inherited"

Section "the adapter registers itself"
$a = Resolve-HordeFleetAdapter -Kind "agent"
Check ($a.state -ceq "known" -and $a.value.name -ceq "claude-code") "loading the file registers the fleet agent adapter"
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue

Complete-HordeSuite -Success "hibernation's liveness rule answers every case of the restore guard's spec the way the guard does"
