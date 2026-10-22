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

Section "a process started to resume a session: it is never stopped (T-0320)"
# M resumed two lot members by hand; no control file named either, so the control files alone read both
# stopped and a wake would have started a second copy. The process command lines are the second witness.
$HAND = "eeeeeeee-5555-4555-8555-555555555555"
$HAND2 = "ffffffff-6666-4666-8666-666666666666"
$NOTMINE = "99999999-7777-4777-8777-777777777777"
function Proc { param([int]$ProcId, [string]$Name, [string]$Line) return [pscustomobject]@{ pid = $ProcId; name = $Name; commandLine = $Line } }
function Table-Of { param([object[]]$Rows) $h = @{}; foreach ($r in @($Rows)) { $h[[int]$r.pid] = $r }; $answer = New-HordeKnown -Value $h; return { $answer }.GetNewClosure() }
function Snap-With { param([object[]]$Rows) return (New-ClaudeCodeFleetSnapshot -Read (Read-ClaudeCodeFleetRecords -Dirs @($dir) -ProcessStart $processStart) -Resumed (Read-ClaudeCodeFleetResumeArgv -Table (Table-Of $Rows))) }
Usual-World
$exe = '"C:\Users\x\AppData\Roaming\npm\claude.exe"'
$snap = Snap-With @((Proc 28356 "claude.exe" ($exe + " --resume " + $HAND + " --dangerously-skip-permissions")))
Check ("" + $snap.error -eq "" -and "" + $snap.resumedError -eq "") "CONTROL: the listing reads with no error"
$v = Verdict $snap $HAND "C:\work\hand"
Check ($v.state -ceq "running" -and $v.pid -ceq "28356" -and $v.reason -like "*a process was started to resume it: pid 28356*") ("a session a process was started to resume, with no control file, is running (" + $v.state + "/" + $v.kind + ": " + $v.reason + ")")
$v = Verdict $snap $NOTMINE "C:\work\hand"
Check ($v.state -ceq "stopped") ("CONTROL: a session nothing resumed and no control file names is still stopped (" + $v.state + ")")
$v = Verdict $snap $LIVE "C:\work\live"
Check ($v.state -ceq "running" -and $v.kind -ceq "live") "CONTROL: a control file still works as before"
$v = Verdict $snap $DEAD "C:\work\dead"
Check ($v.state -ceq "stopped") "CONTROL: a dead control file with no resuming process is still stopped"
# a dead control file does not outvote a process that resumed the id
$snapD = Snap-With @((Proc 77 "claude.exe" ($exe + " --resume " + $DEAD)))
Check ((Verdict $snapD $DEAD "C:\work\dead").state -ceq "running") "a session whose control file is dead but whose id a process resumes is running"
# the other argv forms and the id's case
foreach ($form in @(@("--resume=" + $HAND), @("-r", $HAND), @("--resume", $HAND.ToUpperInvariant()), @("--resume=" + $HAND.ToUpperInvariant()), @("--model", "x", "-r", $HAND), @("--session-id", $HAND), @("--session-id=" + $HAND), @("--session-id=" + $HAND.ToUpperInvariant()))) {
    $line = $exe + " " + ($form -join " ")
    $v = Verdict (Snap-With @((Proc 31 "claude.exe" $line))) $HAND "C:\work\hand"
    Check ($v.state -ceq "running" -and $v.pid -ceq "31") ("the form '" + ($form -join " ") + "' resumes the session (" + $v.state + ")")
}
# argv that merely contains the id elsewhere does not count
$elsewhere = @(
    @("a path", ($exe + ' --add-dir "C:\work\' + $HAND + '"')),
    @("a prompt text after --resume of another id", ($exe + " --resume " + $NOTMINE + ' "please look at ' + $HAND + '"')),
    @("a prompt that says --resume", ($exe + ' "claude --resume ' + $HAND + '"')),
    @("another flag's value", ($exe + " --name " + $HAND)),
    @("a continue flag (it names no id)", ($exe + " --continue " + $HAND)),
    @("the id as a bare argument", ($exe + " " + $HAND)),
    @("--resume with no id then the id as a prompt", ($exe + " --resume --print " + $HAND)),
    @("a longer word", ($exe + " --resumed " + $HAND)),
    @("an id glued to text", ($exe + " --resume " + $HAND + "x")))
foreach ($e in $elsewhere) {
    $v = Verdict (Snap-With @((Proc 41 "claude.exe" $e[1]))) $HAND "C:\work\hand"
    Check ($v.state -ceq "stopped") ("an id in " + $e[0] + " is not a resume (" + $v.state + ")")
}
$v = Verdict (Snap-With @((Proc 41 "claude.exe" ($exe + " --resume " + $NOTMINE + ' "see ' + $HAND + '"')))) $NOTMINE "C:\work\hand"
Check ($v.state -ceq "running") "CONTROL: the id that does follow --resume in that same line is running"
# only the harness's own process image counts
$v = Verdict (Snap-With @((Proc 51 "pwsh.exe" ("pwsh -c claude --resume " + $HAND)))) $HAND "C:\work\hand"
Check ($v.state -ceq "stopped") "a command line of another program that mentions --resume does not count"
$v = Verdict (Snap-With @((Proc 52 "CLAUDE.EXE" ($exe + " --resume " + $HAND)))) $HAND "C:\work\hand"
Check ($v.state -ceq "running") "the process image is matched without regard to case"
# two processes
$snap2 = Snap-With @((Proc 61 "claude.exe" ($exe + " --resume " + $HAND)), (Proc 62 "claude.exe" ($exe + " --resume " + $HAND2)), (Proc 63 "node.exe" "node x"))
Check ((Verdict $snap2 $HAND "C:\work\hand").pid -ceq "61" -and (Verdict $snap2 $HAND2 "C:\work\hand").pid -ceq "62") "two resuming processes each keep their own session"
Check ((Verdict $snap2 $NOTMINE "C:\work\hand").state -ceq "stopped") "CONTROL: a third id is still stopped"
# --session-id STARTS a session with that id; a process running under it is a reason not to start another
# (erring toward running is the safe side), so unlike every other flag's value it counts.
# a harness process with no readable command line (another user's, elevated) may be the very resume: the
# listing is partly unreadable, so a session with no control file is unknown, never stopped
foreach ($blank in @($null, "", "   ", "`t `r`n")) {
    $snapB = Snap-With @((Proc 64 "claude.exe" $blank))
    $v = Verdict $snapB $HAND "C:\work\hand"
    Check ($v.state -ceq "unknown" -and $v.kind -ceq "reading" -and $v.reason -like "*harness process 64*" -and $v.reason -like "*resume it by hand if it is not*") ("a harness process with no readable command line makes a session with no control file unknown (" + $v.state + "/" + $v.kind + ")")
}
Check ((Verdict $snapB $LIVE "C:\work\live").state -ceq "running") "CONTROL: a live control file needs no command line"
$snapB2 = Snap-With @((Proc 64 "claude.exe" $null), (Proc 65 "claude.exe" ($exe + " --resume " + $HAND)))
Check ((Verdict $snapB2 $HAND "C:\work\hand").state -ceq "running") "an id found in a readable row is still running, whatever the blind row"
Check ((Verdict $snapB2 $NOTMINE "C:\work\hand").state -ceq "unknown") "and one found nowhere is unknown while a row is blind"
Check ((Verdict (Snap-With @((Proc 66 "pwsh.exe" $null))) $HAND "C:\work\hand").state -ceq "stopped") "CONTROL: a blind row of another program does not matter"
# listing unreadable: unknown, never stopped, for a session with no control file
$bad = New-HordeUnknown -Reason "CIM refused"
$snapU = New-ClaudeCodeFleetSnapshot -Read (Read-ClaudeCodeFleetRecords -Dirs @($dir) -ProcessStart $processStart) -Resumed (Read-ClaudeCodeFleetResumeArgv -Table { $bad })
$v = Verdict $snapU $HAND "C:\work\hand"
Check ($v.state -ceq "unknown" -and $v.kind -ceq "reading" -and $v.reason -like "*CIM refused*") ("an unreadable process listing leaves a session with no control file unknown (" + $v.state + "/" + $v.kind + ")")
$v = Verdict $snapU $DEAD "C:\work\dead"
Check ($v.state -ceq "unknown") "an unreadable process listing leaves a dead control file unknown too"
$v = Verdict $snapU $LIVE "C:\work\live"
Check ($v.state -ceq "running" -and $v.kind -ceq "live") "CONTROL: a live control file needs no listing"
$snapT = New-ClaudeCodeFleetSnapshot -Read (Read-ClaudeCodeFleetRecords -Dirs @($dir) -ProcessStart $processStart) -Resumed (Read-ClaudeCodeFleetResumeArgv -Table { throw "boom" })
Check ((Verdict $snapT $HAND "C:\work\hand").state -ceq "unknown") "a listing that throws is unknown, never stopped"
# a snapshot built without the listing (control-file tests) behaves as before
Check ((Verdict (Read-Snapshot) $HAND "C:\work\hand").state -ceq "stopped") "CONTROL: a snapshot taken without the listing is the control files alone"
# the command line splitter
$parts = @(Split-ClaudeCodeFleetCommandLine -Line 'a "b c" d\"e "f\\" g')
Check ($parts.Count -eq 5 -and $parts[1] -ceq "b c" -and $parts[2] -ceq 'd"e' -and $parts[3] -ceq 'f\' -and $parts[4] -ceq "g") ("the splitter reads quotes and backslashes as Windows does (" + ($parts -join "|") + ")")
Check (@(Split-ClaudeCodeFleetCommandLine -Line "").Count -eq 0 -and @(Split-ClaudeCodeFleetCommandLine -Line $null).Count -eq 0) "an empty command line has no arguments"
# the real listing reads this very box without error
$real = Read-ClaudeCodeFleetResumeArgv
Check ("" + $real.error -eq "") ("CONTROL: the real process listing reads (" + $real.error + ")")

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
# THE PROGRAM CAN BE NAMED (setting claude-code-fleet: command), so a scenario that must never start the real
# harness names a stand-in by its full path: a terminal pane takes its PATH from the terminal, not from the
# process that spawns it (measured 2026-10-16), so a stand-in first on a PATH is not enough.
$named = "C:\stand\in\agent.ps1"
Check ((Get-ClaudeCodeFleetResumeLine -SessionId $LIVE -Command $named) -ceq ("& '" + $named + "' --resume " + $LIVE)) "a named program is called by its full path, then --resume and the id"
foreach ($badCmd in @("agent.ps1", "C:\it's\agent.ps1", ("C:\a" + [char]34 + "b\agent.ps1"), "C:\stand\in\agent.ps1`r`ncalc", "C:\stand\in\agent.txt")) {
    Check (Throws { Get-ClaudeCodeFleetResumeLine -SessionId $LIVE -Command $badCmd } "not a program") ("no line is built for the program '" + ($badCmd -replace "`r`n", " ") + "'")
}
$home2 = Join-Path $work "home"
[void](New-Item -ItemType Directory -Path (Join-Path $home2 "settings") -Force)
Check ((Get-ClaudeCodeFleetSettings -HordeHome $home2).state -ceq "defaults" -and "" + (Get-ClaudeCodeFleetSettings -HordeHome $home2).values.command -ceq "") "with no settings file, no program is named"
[System.IO.File]::WriteAllText((Join-Path $home2 "settings\claude-code-fleet.json"), ('{"schemaVersion":1,"settings":{"command":' + (ConvertTo-Json -InputObject $named) + '}}'))
Check ("" + (Get-ClaudeCodeFleetSettings -HordeHome $home2).values.command -ceq $named) "the setting names the program"
$scrub = Get-ClaudeCodeFleetScrub -Names @("CLAUDECODE", "CLAUDE_CODE_SESSION_ID", "CLAUDE_PID", "CLAUDE_CODE_MESSAGING_TOKEN", "CLAUDE_CONFIG_DIR", "PATH")
Check ($scrub.ContainsKey("CLAUDECODE") -and $scrub.ContainsKey("CLAUDE_CODE_SESSION_ID") -and $scrub.ContainsKey("CLAUDE_PID") -and $scrub.ContainsKey("CLAUDE_CODE_MESSAGING_TOKEN") -and $null -eq $scrub["CLAUDECODE"]) "the woken pane does not inherit the waking session's own variables"
Check (-not $scrub.ContainsKey("CLAUDE_CONFIG_DIR") -and -not $scrub.ContainsKey("PATH")) "CONTROL: where the harness keeps its files, and everything else, is inherited"

Section "the adapter registers itself"
$a = Resolve-HordeFleetAdapter -Kind "agent"
Check ($a.state -ceq "known" -and $a.value.name -ceq "claude-code") "loading the file registers the fleet agent adapter"
Check ($a.value.snapshot.ToString() -like "*Read-ClaudeCodeFleetResumeArgv*") "and its snapshot reads the process command lines, not the control files alone"
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue

Complete-HordeSuite -Success "hibernation's liveness rule answers every case of the restore guard's spec the way the guard does"
