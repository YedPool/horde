# tools/NightlyNet.ps1 - THE NIGHTLY NET: one run per repo covers the whole day's merges. T-0331.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\NightlyNet.ps1 [-Repos <spec>,<spec>] [-Plan] [-NoTell]
#       [-Only <fragments>] [-Limit <n>] [-WorkRoot <dir>] [-HordeScript <horde.ps1>] [-SlotWaitSeconds 900]
#       [-RunSeconds 1500] [-LongRunSeconds 3600] [-BisectReserveMinutes 90] [-MaxBisectRuns 40] [-Target M]
#       [-MinFreeGB 4.5] [-MinCommitHeadroomGB 2] [-ShortSlotWaitSeconds 120] [-NoCloseApps] [-AppCloseWaitSeconds 60]
#       [-AppRetryMinutes 15] [-MinFitSeconds 600]
#   -Repos entries are OWNER/REPO:KIND:BRANCH, KIND horde (PowerShell suites, in both shells, and the repo-wide guards)
#   or pytest (the whole pytest run, plus the critical flake8 classes). The default is horde first, then the
#   Orahvision-Universal repo.
#
# THE FOUNDER'S RULE (2026-10-22). Merges no longer wait for test runs during the day. This run is the one
# test run of the day: it covers every merge since the last one and reports to M by 07:00 EDT, naming the
# merge behind each NEW red. core/NightlyNet.ps1 holds what it decides (and is tested); this file is what it does.
#
# THE NIGHT. It starts at 22:00 or later and everything is over by 06:30 (a run is never started if it could
# end after 06:15, which leaves -ReportReserveMinutes for the report and the tell); started outside the window it refuses
# with exit 4 and runs nothing. Every run goes through
# tools/HeavySlot.ps1 in slot runs of -RunSeconds (at most 1800) and a SHORT -SlotWaitSeconds (default 900: a
# lane that waits is said unrun, it never queues for hours, 2026-10-22), so the slot is free between runs. HeavySlot
# itself waits for idle-or-night, which holds all night. THIS FILE REGISTERS NOTHING: whoever owns the
# schedule starts it at 22:00 (execution time limit 8.5 hours).
#
# MEMORY (2026-10-24, after the night of 2026-10-23 ran 0 of 484 horde units: every gate waited its full 900 s for
# 4.5 GB free on a box that had 1.1 to 2.5 GB all night):
#   - ONE floor for every unit and the guards, -MinFreeGB (default 4.5 GB, the founder's 15 percent of this box), so
#     it changes in one place; plus -MinCommitHeadroomGB (2 GB) of commit limit less commit charge (52.3 of 54.8 GB
#     was committed that night);
#   - FAIL FAST: after one gate gives up on memory, later gates wait -ShortSlotWaitSeconds (120) until one gets its
#     memory, then -SlotWaitSeconds again (core Update-HordeNightlyMemoryShort); the night-start check uses the wait
#     in force;
#   - the repos run FEWEST UNITS FIRST (core Get-HordeNightlyRepoOrder), so a small repo is never starved by horde;
#   - a gate that gives up lists the top 8 process groups by working set in its .gate file, and the report names the
#     top 3 of the last give-up.
# NIGHT FLOORS (founder's YES, 2026-10-26, after 2026-10-25 ran 0 of 462 units again): inside 22:00 to 07:00 a gate
#   is given its repo kind's night floor (core Get-HordeNightlyNightFloors, the one place they are set: horde units and
#   the guards 1 GB free, the pytest run 2.5 GB free, 1 GB commit headroom for both); -MinFreeGB and
#   -MinCommitHeadroomGB stay the floor outside those hours. HeavySlot's own defaults and its other callers are untouched.
# THE APP CLOSER (founder's order, 2026-10-26; tools/nightly/AppCloser.ps1 says exactly what and how): once a night,
#   before the first unit and only when the PC has been idle 10 minutes (else again every -AppRetryMinutes until the
#   suite cutoff), the named desktop apps are asked to close; three tray apps are then fully quit. -NoCloseApps closes
#   nothing; -Plan lists what it would close. A run given -AtTime or -HeavySlotScript (a suite) never closes anything.
# THE SUITE PHASE starts a unit while its slot wait still ends before the suite cutoff, with a run limit that ends by the
#   run cutoff: -RunSeconds, or near the end what is left if at least -MinFitSeconds (core Get-HordeNightlySuiteRunSeconds).
#   The old rule kept the last 1620 s of the phase idle. The bisect reserve is kept only when a repo has a merge to bisect.
#
# EACH REPO, in three phases over all repos (phase 1 may use the night up to 06:30 minus -BisectReserveMinutes):
#   1. own clone at origin/<branch>; the day's merges (first-parent, since the last run's tip, labelled from
#      HORDE_HOME\merge\guards-owed.jsonl when present); the guards (horde: `horde merge -RunOwed -Json`, which this
#      file calls and never reimplements; a horde without the verb answers "could not run", never green) and the
#      full suite, every unit a verdict; compared with last night's (state.json): NEWLY RED = red now, green then.
#   2. for each newly red unit, a bisect over the day's merges only (first-parent), running only that unit
#      (a failing suite file in its shell, or a pytest node), tip first (a red that is not red twice is flaky).
#   3. one report to M: wezfleet tell M -Kind report -MessageFile <file>; the body has no double quote, semicolon
#      or angle bracket (core/NightlyNet.ps1, ConvertTo-HordeNightlyText). The same text is kept in the report folder.
# The state moves forward only for units that ran, and the tip only when the whole night's units ran, so a
# short night widens tomorrow's range instead of losing a merge. It is saved whether or not the tell got through;
# findings M was not told stay pending in state.json and every report re-lists them until one is told.
#
# Exit: 0 reported, 5 another run holds the lock (M is told), 3 the tell failed (the report is in the report folder, its findings pending in state.json), 4 outside
# the night window, 1 an error (or a state that could not be saved).
# -Plan runs nothing: it prints the window, the repos, the merges since the last run and the units it would run.
# Windows PowerShell 5.1. ASCII only.
param(
    [string[]]$Repos = @("YedPool/horde:horde:main", "OrahVision/Orahvision-Universal:pytest:master"),
    [string]$WorkRoot = "",
    [string]$HordeScript = "",
    [string]$Target = "M",
    [string]$TellProgram = "wezfleet",
    [string[]]$Only = @(),
    [int]$Limit = 0,
    [int]$SlotWaitSeconds = 900,
    [ValidateRange(0, 900)][int]$ShortSlotWaitSeconds = 120,
    [ValidateRange(0, 64)][double]$MinFreeGB = 4.5,
    [ValidateRange(0, 64)][double]$MinCommitHeadroomGB = 2,
    [string]$HeavySlotScript = "",
    [ValidateRange(60, 1800)][int]$RunSeconds = 1500,
    [ValidateRange(60, 7200)][int]$LongRunSeconds = 3600,
    [ValidateRange(60, 1800)][int]$MinFitSeconds = 600,
    [int]$BisectReserveMinutes = 90,
    [int]$MaxBisectRuns = 40,
    [ValidateRange(0, 120)][int]$ReportReserveMinutes = 15,
    [ValidateRange(0, 900)][int]$TellRetrySeconds = 120,
    [ValidateRange(30, 3600)][int]$GitSeconds = 900,
    [string]$MutexName = "Global\HordeNightlyNet",
    [string]$AtTime = "",
    [ValidateRange(0, 600)][int]$AppCloseWaitSeconds = 60,
    [ValidateRange(1, 120)][int]$AppRetryMinutes = 15,
    [string]$ChromeUserData = "",
    [switch]$NoCloseApps,
    [switch]$Plan,
    [switch]$NoTell
)
$ErrorActionPreference = "Stop"
# A git credential prompt must fail the clone, not hang the night (T-0331 N8): GIT_TERMINAL_PROMPT stops git's own
# prompt, and GCM_INTERACTIVE stops Git Credential Manager's window, which the first alone does not (review of PR 380,
# finding 4: the pytest repo is private, and an expired token could open a dialog in the task's session and wait).
$env:GIT_TERMINAL_PROMPT = "0"
$env:GCM_INTERACTIVE = "never"
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\NightlyNet.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Home.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\IdleState.ps1")
. (Join-Path $PSScriptRoot "nightly\AppCloser.ps1")

# powershell -File hands a comma list over as ONE string: split it here.
$Repos = @($Repos | ForEach-Object { $_ -split "," } | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() })
$Only = @($Only | ForEach-Object { $_ -split "," } | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() })
if ($WorkRoot -eq "") { $WorkRoot = Join-Path (Join-Path $env:LOCALAPPDATA "horde") "nightly" }
if ($HordeScript -eq "") { $HordeScript = Join-Path (Split-Path -Parent $PSScriptRoot) "horde.ps1" }
# -HeavySlotScript is for the suite: a stand-in gate, so a whole night can be driven with no real slot or memory.
$HeavySlot = $(if ($HeavySlotScript -ne "") { $HeavySlotScript } else { Join-Path $PSScriptRoot "HeavySlot.ps1" })
$Inv = [System.Globalization.CultureInfo]::InvariantCulture
# The night's memory state: short on memory after a give-up (core Update-HordeNightlyMemoryShort), how many gates
# gave up on memory, and the holders the last of them listed.
$script:MemoryShort = $false
$script:MemoryGiveUps = 0
$script:MemoryHolders = @()
# The app closer's night: acted or given up (done), when to try next, how many tries, its report lines.
$script:AppCloser = @{ done = $false; nextTry = [datetime]::MinValue; tries = 0; lines = @() }
$WrapDir = Join-Path $PSScriptRoot "nightly"
$Ps51 = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
# -AtTime is for the suite: the time to act as now (the window, the cutoff, the date), so it can drive the paths before
# any run outside the night.
$now = $(if ($AtTime -ne "") { [datetime]::Parse($AtTime, [System.Globalization.CultureInfo]::InvariantCulture) } else { Get-Date })
$Date = $now.ToString("yyyy-MM-dd")
$ReportDir = Join-Path $WorkRoot "reports"
$RunDir = Join-Path (Join-Path $WorkRoot "runs") (Get-Date).ToString("yyyyMMdd-HHmmss")
$LogFile = Join-Path $WorkRoot "nightly.log"
$StopFile = Join-Path $WorkRoot "STOP"
$Shells = @("ps51", "pwsh7")

function Say {
    param([string]$Line)
    $l = (Get-Date).ToString("s") + " " + ($Line -replace "[^\x20-\x7E]", "?")
    try { Add-Content -LiteralPath $LogFile -Value $l -Encoding Ascii -ErrorAction Stop } catch { }
    Write-Host $l
}

function Read-NightlyLog {
    # Logs a 5.1 redirect wrote may be UTF-16: decode by the byte order mark.
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return "" }
    $b = [System.IO.File]::ReadAllBytes($Path)
    if ($b.Length -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE) { return [System.Text.Encoding]::Unicode.GetString($b) }
    return ([System.Text.Encoding]::UTF8.GetString($b) -replace "`0", "")
}

function Invoke-NightlyGit {
    # git in a tree; a non-zero exit throws unless -AllowFail. The result is an array, but PowerShell unrolls a one-element
    # array on return: callers that index it or count it wrap the call in @( ).
    param([string]$Tree, [string[]]$GitArgs, [switch]$AllowFail)
    $o = & git.exe -C $Tree @GitArgs
    $code = $LASTEXITCODE
    if ($code -ne 0 -and -not $AllowFail) { throw ("git " + ($GitArgs -join " ") + " failed with exit " + $code) }
    return @($o | ForEach-Object { "" + $_ })
}

function Invoke-NightlyNetGit {
    # clone and fetch reach the network: each is time-boxed (-GitSeconds) and may never prompt (review of PR 380, finding 4).
    param([string[]]$GitArgs, [string]$What)
    $git = (Get-Command git.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $r = Invoke-HordeNightlyProcess -FilePath $git -ArgumentList (@("-c", "credential.interactive=never") + @($GitArgs)) -TimeoutSeconds $GitSeconds
    if ($r.timedOut) { throw ($What + " ran past " + $GitSeconds + " s and was ended") }
    if ($r.code -ne 0) { throw ($What + " failed with exit " + $r.code) }
}

function Get-NightlySlotWait {
    # The slot wait in force now: the short one while the night is short on memory.
    return (Get-HordeNightlySlotWait -MemoryShort $script:MemoryShort -Normal $SlotWaitSeconds -Short $ShortSlotWaitSeconds)
}

function Test-NightlyMayStart {
    # May a gated run of $Seconds start now and be over by the cutoff? The gate may wait for the slot first, for the
    # wait IN FORCE (Get-NightlySlotWait), not always the long one. With -RunCutoff (the suite phase): it may start
    # while its wait ends before -Cutoff, if its worst case ends by -RunCutoff (core Test-HordeNightlyMayStartSuiteRun).
    param([datetime]$Cutoff, [int]$Seconds, [Nullable[datetime]]$RunCutoff = $null)
    if ($null -ne $RunCutoff) { return (Test-HordeNightlyMayStartSuiteRun -Now (Get-Date) -SuiteCutoff $Cutoff -RunCutoff ([datetime]$RunCutoff) -WaitSeconds (Get-NightlySlotWait) -RunSeconds $Seconds) }
    return (Test-HordeNightlyMayStartRun -Now (Get-Date) -Cutoff $Cutoff -RunSeconds ($Seconds + (Get-NightlySlotWait)))
}

function Get-NightlyFloor {
    # The memory floor a gate of this repo kind gets now (core Get-HordeNightlyMemoryFloor): the night floor inside
    # 22:00 to 07:00, -MinFreeGB and -MinCommitHeadroomGB outside. -AtTime stands in for the clock (the suite).
    param([string]$Kind)
    $at = $(if ($AtTime -ne "") { $now } else { Get-Date })
    return (Get-HordeNightlyMemoryFloor -Now $at -Kind $Kind -DayFreeGB $MinFreeGB -DayCommitGB $MinCommitHeadroomGB)
}

function Get-NightlyFloorText {
    # "horde 1 GB free, pytest 2.5 GB free, 1 GB commit headroom" for the kinds of tonight's repos.
    param([string[]]$Kinds)
    $parts = @(); $commit = ""
    foreach ($k in @($Kinds | Select-Object -Unique)) { $f = Get-NightlyFloor $k; $parts += ($k + " " + $f.freeGB.ToString($Inv) + " GB free"); $commit = $f.commitGB.ToString($Inv) }
    return (($parts -join ", ") + ", " + $commit + " GB commit headroom")
}

function Get-NightlyChromeUserData {
    # Chrome's "User Data" folder, read only (-ChromeUserData for the suite).
    if ($ChromeUserData -ne "") { return $ChromeUserData }
    return (Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data")
}

function Invoke-NightlyAppCloser {
    # The app closer (tools/nightly/AppCloser.ps1), called before the guards and before every unit of the suite phase
    # until it has acted or given up for the night. Never in a suite run (-AtTime or -HeavySlotScript) and never with
    # -NoCloseApps. The night is the REAL clock's.
    param([datetime]$Cutoff)
    $s = $script:AppCloser
    if ($s.done) { return }
    if ($NoCloseApps -or $AtTime -ne "" -or $HeavySlotScript -ne "") {
        $s.done = $true
        $s.lines = @("APPS: nothing closed (" + $(if ($NoCloseApps) { "-NoCloseApps" } else { "a suite run: -AtTime or -HeavySlotScript" }) + ").")
        Say $s.lines[0]
        return
    }
    $real = Get-Date
    $idle = $null
    try { $idle = Read-HordeIdleSeconds } catch { $idle = $null }
    $need = 600
    try { $ic = Get-HordeIdleConfig; if ($ic.ok) { $need = [int]$ic.idleSeconds } } catch { }
    $step = Get-HordeNightlyAppCloserStep -Now $real -Night (Test-HordeNightlyWindow -Now $real) -Idle $idle -NeedSeconds $need -NextTry $s.nextTry -Cutoff $Cutoff
    if ($step -ceq "wait") { return }
    if ($step -ceq "stop") {
        $s.done = $true
        $s.lines = @("APPS: nothing closed, the PC was not idle " + $need + " s before " + $Cutoff.ToString("HH:mm") + " (" + $s.tries + " tries).")
        Say $s.lines[0]
        return
    }
    $s.tries++
    if ($step -ceq "busy") {
        $s.nextTry = $real.AddMinutes($AppRetryMinutes)
        $what = $(if ($null -ne $idle -and ("" + $idle.state) -ceq "known") { "idle " + $idle.seconds + " s of " + $need } else { "input clock unknown" })
        Say ("app closer: the PC is in use (" + $what + "), nothing closed, next try " + $s.nextTry.ToString("HH:mm"))
        return
    }
    $s.done = $true
    $targets = @(Select-HordeNightlyAppProcesses -Processes @(Get-Process) -Names (Get-HordeNightlyCloseAppNames))
    $r = Close-HordeNightlyApps -Targets $targets -ForceNames (Get-HordeNightlyForceQuitAppNames) -WaitSeconds $AppCloseWaitSeconds
    foreach ($x in @($r.closed)) { Say ("app closer: closed " + $x.name + " pid " + $x.pid + " " + $x.gb.ToString("0.000", $Inv) + " GB") }
    foreach ($x in @($r.forced)) { Say ("app closer: FORCE-QUIT " + $x.name + " pid " + $x.pid + " " + $x.gb.ToString("0.000", $Inv) + " GB") }
    foreach ($x in @($r.running)) { Say ("app closer: still running " + $x.name + " pid " + $x.pid + " " + $x.gb.ToString("0.000", $Inv) + " GB") }
    $s.lines = @(Format-HordeNightlyAppLines -Result $r) + @((Get-HordeNightlyChromeRestore -UserDataDir (Get-NightlyChromeUserData)).text)
    foreach ($l in $s.lines) { Say $l }
}

function Invoke-NightlySlot {
    # One slot run through the gate: { code; timedOut; gate; out }. A hidden child; the gate's own closing line is the
    # truth about the run (heavy-slot: released exit=N). The child is ended by ITS PID and the tree under it on
    # timeout or STOP, never by name.
    param([string]$Script, [string]$Worktree, [string[]]$ScriptArgs = @(), [string]$Tag, [int]$Seconds = 0, [string]$Kind = "horde")
    if ($Seconds -le 0) { $Seconds = $RunSeconds }
    $floor = Get-NightlyFloor $Kind
    [void][System.IO.Directory]::CreateDirectory($RunDir)
    $safe = ($Tag -replace '[^A-Za-z0-9._-]', '_')
    $out = Join-Path $RunDir ($safe + ".log")
    $gateOut = Join-Path $RunDir ($safe + ".gate")
    $wait = Get-NightlySlotWait
    $argv = @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", ('"' + $HeavySlot + '"'), "-Script", ('"' + $Script + '"'), "-Worktree", ('"' + $Worktree + '"'),
        "-Out", ('"' + $out + '"'), "-MinFreeGB", $floor.freeGB.ToString($Inv), "-MinCommitHeadroomGB", $floor.commitGB.ToString($Inv), "-WaitSeconds", $wait, "-RunSeconds", $Seconds)
    if (@($ScriptArgs).Count -gt 0) {
        $af = Join-Path $RunDir ($safe + ".args.json")
        Set-Content -LiteralPath $af -Value (ConvertTo-Json -InputObject @($ScriptArgs)) -Encoding Ascii
        $argv += @("-ArgsFile", ('"' + $af + '"'))
    }
    $p = Start-Process -FilePath $Ps51 -ArgumentList ($argv -join " ") -WorkingDirectory $WorkRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput $gateOut -RedirectStandardError ($gateOut + ".err")
    $null = $p.Handle
    try { $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Idle } catch { }
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $limit = $wait + $Seconds + 300
    $timedOut = $false
    while (-not $p.WaitForExit(15000)) {
        if ($clock.Elapsed.TotalSeconds -gt $limit -or (Test-Path -LiteralPath $StopFile)) {
            $timedOut = $true
            & taskkill.exe /PID $p.Id /T /F | Out-Null
            break
        }
    }
    $gate = Read-NightlyLog $gateOut
    $code = 124
    if (-not $timedOut) {
        $p.WaitForExit()
        $m = [regex]::Match($gate, 'heavy-slot: released exit=(\d+)')
        if ($m.Success) { $code = [int]$m.Groups[1].Value } else { $code = $p.ExitCode }
    }
    # Fail fast on memory, and keep who held it (core Update-HordeNightlyMemoryShort, Read-HordeNightlyMemoryHolders).
    $wasShort = $script:MemoryShort
    $script:MemoryShort = Update-HordeNightlyMemoryShort -Short $script:MemoryShort -Gate $gate
    if (Test-HordeNightlyMemoryGiveUp -Gate $gate) {
        $script:MemoryGiveUps++
        $h = @(Read-HordeNightlyMemoryHolders -Gate $gate)
        if ($h.Count -gt 0) { $script:MemoryHolders = $h }
    }
    if ($script:MemoryShort -and -not $wasShort) { Say ($Tag + " gave up on memory: slot waits are " + (Get-NightlySlotWait) + " s until a gate gets its memory") }
    elseif ($wasShort -and -not $script:MemoryShort) { Say ($Tag + " got its memory: slot waits are " + (Get-NightlySlotWait) + " s again") }
    return [pscustomobject]@{ code = $code; timedOut = $timedOut; gate = $gate; out = $out }
}

function Get-NightlyVerdict {
    # See Get-HordeNightlyVerdict (core): gate exit 124 is hung at the tip (-AtTip), unrun in a bisect, never red.
    param($Run, [switch]$AtTip)
    return (Get-HordeNightlyVerdict $Run -AtTip:$AtTip)
}

function Invoke-NightlyUnit {
    # Run one unit at the checked-out tree: unit ids are "<suite rel path>|ps51", "<suite rel path>|pwsh7",
    # "pytest-node|<node id>" and "flake8-critical". Returns the verdict word of Get-NightlyVerdict ("red" included);
    # -AtTip: this is the night's full run at the tip, not a bisect step.
    # -Seconds: the run limit (0: -RunSeconds), fitted to the end of the night by the suite phase.
    param($Ctx, [string]$Unit, [string]$Tag, [switch]$AtTip, [int]$Seconds = 0)
    $tree = $Ctx.tree
    if ($Ctx.kind -ceq "horde") {
        $rel, $sh = $Unit -split '\|', 2
        if ($sh -ceq "pwsh7") {
            $abs = Join-Path $tree ($rel -replace '/', '\')
            return (Get-NightlyVerdict (Invoke-NightlySlot -Script "pwsh-wrap.ps1" -Worktree $WrapDir -ScriptArgs @($abs, $tree) -Tag $Tag -Seconds $Seconds) -AtTip:$AtTip)
        }
        return (Get-NightlyVerdict (Invoke-NightlySlot -Script ($rel -replace '/', '\') -Worktree $tree -Tag $Tag -Seconds $Seconds) -AtTip:$AtTip)
    }
    if ($Unit -ceq "flake8-critical") {
        return (Get-NightlyVerdict (Invoke-NightlySlot -Kind "pytest" -Script "pytest-wrap.ps1" -Worktree $WrapDir -ScriptArgs @("-Tree", $tree, "-Mode", "flake8") -Tag $Tag -Seconds $Seconds) -AtTip:$AtTip)
    }
    $node = ($Unit -split '\|', 2)[1]
    $nf = Join-Path $RunDir (($Tag -replace '[^A-Za-z0-9._-]', '_') + ".nodes")
    [System.IO.File]::WriteAllText($nf, $node + "`n")
    $r = Invoke-NightlySlot -Kind "pytest" -Script "pytest-wrap.ps1" -Worktree $WrapDir -ScriptArgs @("-Tree", $tree, "-Mode", "nodes", "-NodesFile", $nf) -Tag $Tag -Seconds $Seconds
    # pytest 4 (usage error: the file is not there) and 5 (nothing collected): the test is not in this commit.
    if (-not $r.timedOut -and ($r.code -eq 4 -or $r.code -eq 5)) { return "absent" }
    return (Get-NightlyVerdict $r -AtTip:$AtTip)
}

function Read-NightlyState {
    param([string]$Path)
    $s = @{ lastTip = ""; units = @{}; pending = @() }
    if (-not (Test-Path -LiteralPath $Path)) { return $s }
    try {
        $o = ConvertFrom-HordeJson ([System.IO.File]::ReadAllText($Path))
        $s.lastTip = "" + $o.lastTip
        foreach ($p in $o.units.PSObject.Properties) { $s.units["" + $p.Name] = "" + $p.Value }
        if ($o.PSObject.Properties["pending"]) { $s.pending = @(@($o.pending) | Where-Object { "" + $_ -ne "" } | ForEach-Object { "" + $_ }) }
    } catch { Say ("state unreadable, treated as empty: " + $Path + ": " + $_.Exception.Message); return @{ lastTip = ""; units = @{}; pending = @() } }
    return $s
}

function Write-NightlyState {
    param([string]$Path, $State)
    $u = [ordered]@{}
    foreach ($k in (@($State.units.Keys) | Sort-Object)) { $u[$k] = $State.units[$k] }
    $text = ([ordered]@{ lastTip = $State.lastTip; units = $u; pending = @($State.pending) } | ConvertTo-Json -Depth 4)
    $tmp = $Path + ".tmp"
    [System.IO.File]::WriteAllText($tmp, $text)
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function New-NightlyContext {
    # Phase 0 of one repo: its clone at origin/<branch>, its state, its merges. Nothing is run.
    param([string]$Spec)
    $parts = $Spec -split ":"
    if ($parts.Count -ne 3 -or $parts[0] -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or @("horde", "pytest") -cnotcontains $parts[1]) { throw ("a -Repos entry must be OWNER/REPO:horde|pytest:BRANCH, not '" + $Spec + "'") }
    $repo = $parts[0]; $kind = $parts[1]; $branch = $parts[2]
    $dir = Join-Path $WorkRoot ($repo -replace '/', '__')
    $tree = Join-Path $dir "tree"
    [void][System.IO.Directory]::CreateDirectory($dir)
    if (-not (Test-Path -LiteralPath (Join-Path $tree ".git"))) { Invoke-NightlyNetGit -GitArgs @("-c", "core.longpaths=true", "clone", "-q", ("https://github.com/" + $repo + ".git"), $tree) -What ("git clone of " + $repo) }
    [void](Invoke-NightlyGit $tree @("config", "core.longpaths", "true"))
    Invoke-NightlyNetGit -GitArgs @("-C", $tree, "fetch", "--quiet", "origin") -What ("git fetch of " + $repo)
    [void](Invoke-NightlyGit $tree @("checkout", "--quiet", "--detach", ("origin/" + $branch)))
    [void](Invoke-NightlyGit $tree @("reset", "--hard", "--quiet", ("origin/" + $branch)))
    [void](Invoke-NightlyGit $tree @("clean", "-fdq"))
    $tip = ("" + @(Invoke-NightlyGit $tree @("rev-parse", "HEAD"))[0]).Trim()
    $statePath = Join-Path $dir "state.json"
    $state = Read-NightlyState $statePath
    $notes = @()
    $gitLines = @()
    if ($state.lastTip -ne "") {
        # --quiet prints nothing when the commit is not there; a 2> redirect would raise under 5.1 and Stop.
        $ok = $false
        $known = @(Invoke-NightlyGit $tree @("rev-parse", "--verify", "--quiet", ($state.lastTip + "^{commit}")) -AllowFail)
        if ($known.Count -gt 0 -and $known[0] -match '^[0-9a-f]{40}$') { $ok = $true }
        $global:LASTEXITCODE = 0
        if ($ok) { $gitLines = @(Invoke-NightlyGit $tree @("log", "--first-parent", "--reverse", "--format=%H%x09%s", ($state.lastTip + ".." + $tip))) }
        else { $notes += ("last night's tip " + $state.lastTip.Substring(0, 8) + " is not in the clone (history rewritten?), so no merge range could be listed") ; $state.lastTip = "" }
    } else { $notes += "first run for this repo: no baseline from last night, so no merge is named" }
    $owedPath = Join-Path (Join-Path (Get-HordeHome) "merge") "guards-owed.jsonl"
    $owed = $null
    if (Test-Path -LiteralPath $owedPath) {
        $owed = Read-HordeNightlyOwed -Lines @([System.IO.File]::ReadAllLines($owedPath)) -Repo $repo
        if ($owed.bad -gt 0) { $notes += ("" + $owed.bad + " lines of guards-owed.jsonl were not JSON and were skipped") }
    }
    $merges = @(Get-HordeNightlyMerges -GitLines $gitLines -Owed $owed)
    return [pscustomobject]@{ repo = $repo; kind = $kind; branch = $branch; dir = $dir; tree = $tree; tip = $tip; statePath = $statePath; state = $state
        merges = $merges; notes = @($notes); units = @(); verdicts = @{}; guards = [pscustomobject]@{ state = "not run"; text = "" }; unrun = 0; compare = $null; culprits = @(); incomplete = "" }
}

function Get-NightlyUnits {
    # The units of the full suite at the tip. horde: every suite of the tree's SuiteFiles, minus the machine-bound ones,
    # in both shells. pytest: the one whole run (its failing nodes become the units) and flake8.
    param($Ctx)
    if ($Ctx.kind -ceq "pytest") { return @("pytest-all", "flake8-critical") }
    . (Join-Path $Ctx.tree "test\lib\SuiteFiles.ps1")
    $full = (Get-Item -LiteralPath $Ctx.tree).FullName.TrimEnd('\')
    $bound = @{}
    foreach ($m in @(Get-HordeMachineBoundSuites)) { $bound[$m.path] = $true }
    $all = @()
    foreach ($f in @(Get-HordeSuiteFiles -Root $full)) { $rel = $f.FullName.Substring($full.Length + 1).Replace('\', '/'); if (-not $bound.ContainsKey($rel)) { $all += $rel } }
    if (@($Only).Count -gt 0) { $all = @($all | Where-Object { $r = $_; @($Only | Where-Object { $r -like ("*" + $_ + "*") }).Count -gt 0 }) }
    if ($Limit -gt 0 -and $all.Count -gt $Limit) { $all = @($all[0..($Limit - 1)]) }
    $units = @()
    foreach ($r in $all) { foreach ($s in $Shells) { $units += ($r + "|" + $s) } }
    return $units
}

function Invoke-NightlyPhaseOne {
    # The guards and the full suite of one repo, until -Cutoff. Fills verdicts, guards, unrun, incomplete.
    # -RunCutoff: the time every run must be over by (the suite phase may run into the bisect reserve, never past it).
    param($Ctx, [datetime]$Cutoff, [datetime]$RunCutoff)
    $tag = ($Ctx.repo -replace '/', '_')
    Invoke-NightlyAppCloser -Cutoff $Cutoff
    # THE GUARDS (horde): `horde merge -RunOwed -Json` through the gate (tools/nightly/guards-wrap.ps1 reads its -Json last line, F's shape of PR 375):
    if ($Ctx.kind -ceq "horde") {
        if (-not (Test-NightlyMayStart -Cutoff $Cutoff -Seconds $LongRunSeconds -RunCutoff $RunCutoff)) { $Ctx.guards = [pscustomobject]@{ state = "not run"; text = "the night ran out before the guards could start" } }
        else {
            $g = Invoke-NightlySlot -Script "guards-wrap.ps1" -Worktree $WrapDir -ScriptArgs @("-Horde", $HordeScript, "-Repo", $Ctx.repo) -Tag ($tag + "-guards") -Seconds $LongRunSeconds
            $text = ((Read-NightlyLog $g.out) -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -Last 10) -join " | "
            if ($text.Length -gt 700) { $text = $text.Substring($text.Length - 700) }
            $st = "could not run"
            if (-not $g.timedOut) { if ($g.code -eq 0) { $st = "green" } elseif ($g.code -eq 1) { $st = "RED" } elseif ($g.code -eq 125 -or $g.code -eq 128) { $st = "not run (no slot or no night)"; $text = "" } }
            $Ctx.guards = [pscustomobject]@{ state = $st; text = $text }
        }
    } else { $Ctx.guards = [pscustomobject]@{ state = "no repo-wide guard list (flake8 critical is a unit below)"; text = "" } }
    $units = Get-NightlyUnits $Ctx
    $Ctx.units = @($units)
    foreach ($u in $units) {
        if (Test-Path -LiteralPath $StopFile) { $Ctx.incomplete = "STOP file seen"; break }
        $need = $(if ($u -ceq "pytest-all") { $LongRunSeconds } else { $RunSeconds })
        Invoke-NightlyAppCloser -Cutoff $Cutoff
        # The run limit fitted to the night (core Get-HordeNightlySuiteRunSeconds); the whole pytest run is never cut short.
        $secs = Get-HordeNightlySuiteRunSeconds -Now (Get-Date) -SuiteCutoff $Cutoff -RunCutoff $RunCutoff -WaitSeconds (Get-NightlySlotWait) -RunSeconds $need -MinSeconds $(if ($u -ceq "pytest-all") { $need } else { $MinFitSeconds })
        if ($secs -le 0) { $Ctx.incomplete = "the night ran out before every unit ran"; break }
        if ($u -ceq "pytest-all") {
            $nf = Join-Path $RunDir ($tag + "-nodes.txt")
            if (Test-Path -LiteralPath $nf) { Remove-Item -LiteralPath $nf -Force }
            $r = Invoke-NightlySlot -Kind "pytest" -Script "pytest-wrap.ps1" -Worktree $WrapDir -ScriptArgs @("-Tree", $Ctx.tree, "-Mode", "all", "-NodesFile", $nf) -Tag ($tag + "-pytest-all") -Seconds $LongRunSeconds
            $nodes = @()
            if (Test-Path -LiteralPath $nf) { $nodes = @(Get-Content -LiteralPath $nf | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() }) }
            # Only a run that finished as pytest does (exit 0, or 1 with the failing nodes it named) is a verdict. A timeout,
            # a crash, a missing python or a failed collection (the wrap says 70 and 71) is UNRUN, never green.
            $finished = (-not $r.timedOut) -and (Test-Path -LiteralPath $nf) -and (($r.code -eq 0) -or ($r.code -eq 1 -and $nodes.Count -gt 0))
            if (-not $finished) { Say ($Ctx.repo + " pytest-all did not finish as pytest does (exit " + $r.code + ", timed out " + $r.timedOut + ")"); $Ctx.incomplete = "the pytest run did not complete"; $Ctx.unrun++; continue }
            foreach ($n in $nodes) { $Ctx.verdicts["pytest-node|" + $n] = "red" }
            $Ctx.verdicts["pytest-all"] = "green"
            continue
        }
        # Each unit's time, gate wait included, is logged: the measured night is tomorrow's time budget.
        $uclock = [System.Diagnostics.Stopwatch]::StartNew()
        $v = Invoke-NightlyUnit -Ctx $Ctx -Unit $u -Tag ($tag + "-" + $u) -AtTip -Seconds $secs
        # Past a limit cut short by the end of the night is not a hang: it is unrun, and runs again tomorrow.
        if ($v -ceq "hung" -and $secs -lt $need) { $v = "unrun" }
        Say ($Ctx.repo + " " + $u + " -> " + $v + " in " + [int]$uclock.Elapsed.TotalSeconds + " s")
        if ($v -ceq "absent") { continue }
        $Ctx.verdicts[$u] = $v
        if ($v -ceq "unrun") { $Ctx.unrun++ }
    }
    $Ctx.unrun += @($units | Where-Object { -not $Ctx.verdicts.ContainsKey($_) -and $_ -cne "pytest-all" }).Count
}

function Complete-NightlyCompare {
    # Verdicts against last night's, with the pytest rule: a node red now and not in last night's red list was GREEN then.
    param($Ctx)
    $last = @{}
    foreach ($k in @($Ctx.state.units.Keys)) { $last[$k] = $Ctx.state.units[$k] }
    if ($Ctx.kind -ceq "pytest" -and $Ctx.state.lastTip -ne "") {
        foreach ($k in @($Ctx.verdicts.Keys)) { if ($k -like "pytest-node|*" -and $Ctx.verdicts[$k] -ceq "red" -and -not $last.ContainsKey($k)) { $last[$k] = "green" } }
    }
    $now = @{}
    foreach ($k in @($Ctx.verdicts.Keys)) { if ($k -cne "pytest-all") { $now[$k] = $Ctx.verdicts[$k] } }
    $Ctx.compare = Compare-HordeNightlyVerdicts -Now $now -Last $last
}

function Invoke-NightlyBisect {
    param($Ctx, [datetime]$Cutoff)
    $script:BisectLeft = $MaxBisectRuns
    $shas = @($Ctx.merges | ForEach-Object { $_.sha })
    $memo = @{}
    $todo = @($Ctx.compare.newlyRed)
    $left = $todo.Count
    foreach ($u in $todo) {
        # The reserve is shared by the whole repo: each unit gets its fair share of what is left (at least 2 runs).
        $budget = [Math]::Max(2, [int][Math]::Ceiling($script:BisectLeft / [Math]::Max(1, $left)))
        $left--
        $isRed = {
            param($sha)
            $key = $sha + "|" + $u
            if ($memo.ContainsKey($key)) { return $memo[$key] }
            if (-not (Test-NightlyMayStart -Cutoff $Cutoff -Seconds $RunSeconds) -or (Test-Path -LiteralPath $StopFile)) { return $null }
            try {
                [void](Invoke-NightlyGit $Ctx.tree @("checkout", "--quiet", "--detach", $sha))
                [void](Invoke-NightlyGit $Ctx.tree @("clean", "-fdq"))
            } catch { Say ("bisect checkout of " + $sha + " failed: " + $_.Exception.Message); return $null }
            $v = Invoke-NightlyUnit -Ctx $Ctx -Unit $u -Tag (($Ctx.repo -replace '/', '_') + "-bisect-" + $sha.Substring(0, 8) + "-" + $u)
            $res = ConvertTo-HordeNightlyBisectAnswer $v
            $memo[$key] = $res
            return $res
        }
        $found = Find-HordeNightlyCulprit -Merges $shas -IsRed $isRed -MaxRuns $budget
        $merge = $null
        if ($found.state -ceq "found") { $merge = @($Ctx.merges | Where-Object { $_.sha -ceq $found.sha })[0] }
        $Ctx.culprits += [pscustomobject]@{ unit = $u; state = $found.state; sha = $found.sha; merge = $merge; runs = $found.runs; between = $found.between }
        $script:BisectLeft = [Math]::Max(0, $script:BisectLeft - [int]$found.runs)
        Say ($Ctx.repo + " bisect " + $u + " -> " + $found.state + " " + $found.sha + " in " + $found.runs + " runs")
    }
    [void](Invoke-NightlyGit $Ctx.tree @("checkout", "--quiet", "--detach", $Ctx.tip))
}

function Save-NightlyState {
    # core Update-HordeNightlyState decides: tonight's verdicts always, the tip only when every unit ran, and what M was
    # not told (the tell failed) kept pending for the next report.
    param($Ctx, $Row, [bool]$Told)
    $next = Update-HordeNightlyState -State $Ctx.state -Verdicts $Ctx.verdicts -Kind $Ctx.kind -Tip $Ctx.tip -Complete ($Ctx.incomplete -eq "" -and $Ctx.unrun -eq 0) -Told $Told -Findings @(Get-HordeNightlyFindingLines -Row $Row) -Date $Date
    Write-NightlyState -Path $Ctx.statePath -State $next
}

# ---------------------------------------------------------------- the run
# THE WORK FOLDER FIRST, before the first log line (review of PR 380, finding 6: Say ran before it existed, so a fresh
# box lost the window line). If it cannot be made (a bad -WorkRoot, an ACL, a full disk) the log and the report go to a
# folder under the temp path instead, and the run fails below through the catch, which tells M from there.
$setupError = ""
try { [void][System.IO.Directory]::CreateDirectory($WorkRoot); [void][System.IO.Directory]::CreateDirectory($ReportDir) }
catch {
    $setupError = "the work folder " + $WorkRoot + " could not be made: " + $_.Exception.Message
    $fallback = Join-Path ([System.IO.Path]::GetTempPath()) "horde-nightly-fallback"
    try { [void][System.IO.Directory]::CreateDirectory($fallback) } catch { }
    $LogFile = Join-Path $fallback "nightly.log"
    $ReportDir = $fallback
}
# Runs end -ReportReserveMinutes (15) before 06:30, so the report, the tell and the save are done by then.
$cutoff = Get-HordeNightlyRunCutoff -Now $now -ReportReserveMinutes $ReportReserveMinutes
$inWindow = Test-HordeNightlyWindow -Now $now
Say ("nightly net " + $Date + ": window " + $(if ($inWindow) { "open" } else { "CLOSED" }) + ", cutoff " + $cutoff.ToString("s") + ", repos " + ($Repos -join ", "))
if (-not $inWindow -and -not $Plan) { Say "outside the night window (22:00 to 06:30): nothing run"; exit 4 }

function Send-NightlyReport {
    # Tell M (core Invoke-HordeNightlyTell): 0 told, 3 not told, the report stays in the report folder.
    param([string]$File)
    return (Invoke-HordeNightlyTell -Program $TellProgram -Target $Target -File $File -NoTell:$NoTell -RetrySeconds $TellRetrySeconds -TimeoutSeconds 300 -Say { param($l) Say $l })
}

$mutex = $null
$held = $false
try {
    # Inside the try (T-0331 N7): a failure here is a FAILED night told to M, not a silent one.
    if ($setupError -ne "") { throw $setupError }
    $mutex = New-Object System.Threading.Mutex($false, $MutexName)
    if (-not $Plan) {
    # A killed run can leave the mutex abandoned: WaitOne then throws, and the mutex is ours.
    try { $held = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $held = $true }
    if (-not $held) {
        # Never a silent night (review of PR 380, finding 4): a run wedged from an earlier night holds the lock, and
        # every night after it would end here with exit 0 and a log line nobody reads. M hears it, and it exits 5.
        Say "another nightly run holds the lock: tonight runs nothing"
        $busy = Join-Path $ReportDir ($Date + "-BUSY.txt")
        [System.IO.File]::WriteAllText($busy, (ConvertTo-HordeNightlyText ("NIGHTLY NET " + $Date + ": NOT RUN, another nightly run still holds the lock (a run from an earlier night may be wedged). Log: " + $LogFile)) + "`n")
        [void](Send-NightlyReport $busy)
        exit 5
    }
    }
    $ctxs = @()
    foreach ($spec in $Repos) { $ctxs += (New-NightlyContext $spec) }
    # Fewest units first (core Get-HordeNightlyRepoOrder): the night of 2026-10-23 never reached the 2-unit repo.
    $counts = @($ctxs | ForEach-Object { @(Get-NightlyUnits $_).Count })
    $ctxs = @(@(Get-HordeNightlyRepoOrder -Counts $counts) | ForEach-Object { $ctxs[$_] })
    Say ("order: " + (@($ctxs | ForEach-Object { $_.repo }) -join ", ") + "; memory floor " + (Get-NightlyFloorText @($ctxs | ForEach-Object { $_.kind })) + " (night floors 22:00 to 07:00, by day " + $MinFreeGB.ToString($Inv) + " GB free and " + $MinCommitHeadroomGB.ToString($Inv) + " GB commit headroom); slot wait " + $SlotWaitSeconds + " s, " + $ShortSlotWaitSeconds + " s after a memory give-up")
    # The bisect reserve is kept only when there is a merge to bisect over: with none in any repo (a first night has
    # none), no unit can be bisected, and the suite phase gets the whole night.
    $reserve = $(if (@($ctxs | ForEach-Object { @($_.merges) }).Count -gt 0) { $BisectReserveMinutes } else { 0 })
    if ($Plan) {
        foreach ($c in $ctxs) {
            Write-Host ("PLAN " + $c.repo + " (" + $c.kind + ") tip " + $c.tip.Substring(0, 8) + " last " + $(if ($c.state.lastTip -eq "") { "none" } else { $c.state.lastTip.Substring(0, 8) }) + ": " + @($c.merges).Count + " merges")
            foreach ($m in $c.merges) { Write-Host ("  merge " + (Format-HordeNightlyMerge -Merge $m) + " [" + $m.source + "]") }
            Write-Host ("  units: " + @(Get-NightlyUnits $c).Count)
            foreach ($n in $c.notes) { Write-Host ("  note: " + $n) }
            $pf = Get-NightlyFloor $c.kind
            Write-Host ("  floor: " + $pf.freeGB.ToString($Inv) + " GB free, " + $pf.commitGB.ToString($Inv) + " GB commit headroom (" + $(if ($pf.night) { "night floor" } else { "day floor: -AtTime is outside 22:00 to 07:00" }) + ")")
        }
        # THE APPS, dry: what the closer would close now, and the Chrome restore setting (read only).
        if ($NoCloseApps) { Write-Host "PLAN apps: -NoCloseApps, nothing would be closed" }
        else {
            $dry = Close-HordeNightlyApps -Targets @(Select-HordeNightlyAppProcesses -Processes @(Get-Process) -Names (Get-HordeNightlyCloseAppNames)) -ForceNames (Get-HordeNightlyForceQuitAppNames) -DryRun
            Write-Host ("PLAN apps (named list: " + ((Get-HordeNightlyCloseAppNames) -join ", ") + "; force-quit only " + ((Get-HordeNightlyForceQuitAppNames) -join ", ") + "; only when idle " + $(try { (Get-HordeIdleConfig).idleSeconds } catch { "?" }) + " s, retry every " + $AppRetryMinutes + " min, graceful wait " + $AppCloseWaitSeconds + " s)")
            foreach ($l in @(Format-HordeNightlyAppLines -Result $dry)) { Write-Host ("  " + $l) }
        }
        Write-Host ("  " + (Get-HordeNightlyChromeRestore -UserDataDir (Get-NightlyChromeUserData)).text)
        # THE TIME BUDGET of the suite phase, from tonight's 22:00 (or now, inside the window).
        $real = Get-Date
        $bStart = $(if (Test-HordeNightlyWindow -Now $real) { $real } else { $now.Date.AddHours(22) })
        $bRun = Get-HordeNightlyRunCutoff -Now $bStart -ReportReserveMinutes $ReportReserveMinutes
        $bSuite = $bRun.AddMinutes(-$reserve)
        $bUnits = 0; foreach ($c in $ctxs) { $bUnits += @(Get-NightlyUnits $c).Count + $(if ($c.kind -ceq "horde") { 1 } else { 0 }) }
        $bSecs = [int]($bSuite - $bStart).TotalSeconds
        $lastStart = { param($w) $x = $bSuite.AddSeconds(-$w); $y = $bRun.AddSeconds(-($w + $MinFitSeconds)); if ($y -lt $x) { $y } else { $x } }
        Write-Host ("PLAN time: suite phase " + $bStart.ToString("HH:mm") + " to " + $bSuite.ToString("HH:mm") + " = " + $bSecs + " s for " + $bUnits + " gate runs (units and guards) = " + [int]($bSecs / [math]::Max(1, $bUnits)) + " s each on average, gate wait included (bisect reserve " + $reserve + " min). A unit may start until " + (& $lastStart $SlotWaitSeconds).ToString("HH:mm") + " (" + (& $lastStart $ShortSlotWaitSeconds).ToString("HH:mm") + " on the short wait): its wait must end by " + $bSuite.ToString("HH:mm") + " and its run limit, " + $RunSeconds + " s or fitted down to no less than " + $MinFitSeconds + " s, by " + $bRun.ToString("HH:mm") + ".")
        exit 0
    }
    $suiteCutoff = $cutoff.AddMinutes(-$reserve)
    foreach ($c in $ctxs) { Invoke-NightlyPhaseOne -Ctx $c -Cutoff $suiteCutoff -RunCutoff $cutoff; Complete-NightlyCompare $c }
    foreach ($c in $ctxs) { Invoke-NightlyBisect -Ctx $c -Cutoff $cutoff }

    $repoRows = @()
    foreach ($c in $ctxs) {
        $repoRows += [pscustomobject]@{ repo = $c.repo; tip = $c.tip; lastTip = $c.state.lastTip; merges = $c.merges; guards = $c.guards
            suiteCount = (Get-HordeNightlyRunCount -Verdicts $c.verdicts); unrunCount = $c.unrun; compare = $c.compare; culprits = $c.culprits; notes = $c.notes; incomplete = $c.incomplete
            pending = @($c.state.pending) }
    }
    $memory = [pscustomobject]@{ giveUps = $script:MemoryGiveUps; minFreeGB = (@($ctxs | ForEach-Object { $_.kind } | Select-Object -Unique | ForEach-Object { $_ + " " + (Get-NightlyFloor $_).freeGB.ToString($Inv) }) -join ", "); minCommitGB = (Get-NightlyFloor $ctxs[0].kind).commitGB.ToString($Inv); holders = @($script:MemoryHolders) }
    $body = New-HordeNightlyReport -Date $Date -Repos $repoRows -Memory $memory -AppLines @($script:AppCloser.lines)
    if ($body.Length -gt 6000) { $body = $body.Substring(0, 6000) + " ...cut, the full report is in the report folder." }
    $file = Join-Path $ReportDir ($Date + ".txt")
    [System.IO.File]::WriteAllText($file, $body + "`n")
    Say ("report written: " + $file)
    # The state is ALWAYS saved (review of PR 380, finding 2): tonight's verdicts and tip are test facts whether or not M
    # heard them. What M did not hear is kept apart, pending, and re-listed in every report until a tell succeeds. Each
    # repo's save is its own try: one that throws after the tell must not turn a delivered report into a FAILED night.
    $told = Send-NightlyReport $file
    if ($told -ne 0) { Say "the report was not told: tonight's findings stay pending and the next report lists them again" }
    $saved = $true
    for ($i = 0; $i -lt $ctxs.Count; $i++) {
        try { Save-NightlyState -Ctx $ctxs[$i] -Row $repoRows[$i] -Told ($told -eq 0) }
        catch { $saved = $false; Say ("report " + $(if ($told -eq 0) { "sent" } else { "not sent" }) + ", but the state of " + $ctxs[$i].repo + " was not saved: " + $_.Exception.Message) }
    }
    if ($told -ne 0) { exit $told }
    if (-not $saved) { exit 1 }
    exit 0
} catch {
    # A failed night must never be silent: one plain line to M, and the same line in the report folder.
    $why = ConvertTo-HordeNightlyText ("" + $_.Exception.Message)
    if ($why.Length -gt 400) { $why = $why.Substring(0, 400) }
    Say ("the nightly net FAILED: " + $why)
    if (-not $Plan) {
        $body = "NIGHTLY NET " + $Date + ": FAILED, the night did not complete and tonight's tests say nothing. Error: " + $why + ". Log: " + $LogFile
        # The report folder may be what failed: the temp path is the second place to write the line M is told.
        $sent = $false
        foreach ($dir in @($ReportDir, (Join-Path ([System.IO.Path]::GetTempPath()) "horde-nightly-fallback"))) {
            try {
                [void][System.IO.Directory]::CreateDirectory($dir)
                $file = Join-Path $dir ($Date + "-FAILED.txt")
                [System.IO.File]::WriteAllText($file, (ConvertTo-HordeNightlyText $body) + "`n")
                [void](Send-NightlyReport $file); $sent = $true; break
            } catch { Say ("could not report the failure from " + $dir + ": " + $_.Exception.Message) }
        }
        if (-not $sent) { Say "M was not told of the failure" }
    }
    exit 1
} finally {
    if ($held -and $null -ne $mutex) { try { $mutex.ReleaseMutex() } catch { } }
}
