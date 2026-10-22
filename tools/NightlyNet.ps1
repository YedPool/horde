# tools/NightlyNet.ps1 - THE NIGHTLY NET: one run per repo covers the whole day's merges. T-0331.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\NightlyNet.ps1 [-Repos <spec>,<spec>] [-Plan] [-NoTell]
#       [-Only <fragments>] [-Limit <n>] [-WorkRoot <dir>] [-HordeScript <horde.ps1>] [-SlotWaitSeconds 900]
#       [-RunSeconds 1500] [-BisectReserveMinutes 90] [-MaxBisectRuns 40] [-Target M]
#   -Repos entries are OWNER/REPO:KIND:BRANCH, KIND horde (PowerShell suites, in both shells, and the repo-wide guards)
#   or pytest (the whole pytest run, plus the critical flake8 classes). The default is horde first, then the
#   Orahvision-Universal repo.
#
# THE FOUNDER'S RULE (2026-10-22). Merges no longer wait for test runs during the day. This run is the one
# test run of the day: it covers every merge since the last one and reports to M by 07:00 EDT, naming the
# merge behind each NEW red. core/NightlyNet.ps1 holds what it decides (and is tested); this file is what it does.
#
# THE NIGHT. It starts at 22:00 or later and everything is over by 06:30 (a run is never started if it could
# end after that); started outside the window it refuses with exit 4 and runs nothing. Every run goes through
# tools/HeavySlot.ps1 in slot runs of -RunSeconds (at most 1800) and a SHORT -SlotWaitSeconds (default 900: a
# lane that waits is said unrun, it never queues for hours, 2026-10-22), so the slot is free between runs. HeavySlot
# itself waits for idle-or-night, which holds all night. THIS FILE REGISTERS NOTHING: whoever owns the
# schedule starts it at 22:00 (execution time limit 8.5 hours).
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
# short night widens tomorrow's range instead of losing a merge.
#
# Exit: 0 reported, 3 the tell failed (the report is in the report folder), 4 outside the night window, 1 an error.
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
    [ValidateRange(60, 1800)][int]$RunSeconds = 1500,
    [int]$BisectReserveMinutes = 90,
    [int]$MaxBisectRuns = 40,
    [switch]$Plan,
    [switch]$NoTell
)
$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\NightlyNet.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Home.ps1")

# powershell -File hands a comma list over as ONE string: split it here.
$Repos = @($Repos | ForEach-Object { $_ -split "," } | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() })
$Only = @($Only | ForEach-Object { $_ -split "," } | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() })
if ($WorkRoot -eq "") { $WorkRoot = Join-Path (Join-Path $env:LOCALAPPDATA "horde") "nightly" }
if ($HordeScript -eq "") { $HordeScript = Join-Path (Split-Path -Parent $PSScriptRoot) "horde.ps1" }
$HeavySlot = Join-Path $PSScriptRoot "HeavySlot.ps1"
$WrapDir = Join-Path $PSScriptRoot "nightly"
$Ps51 = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$Date = (Get-Date).ToString("yyyy-MM-dd")
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
    param([string]$Tree, [string[]]$GitArgs)
    $o = & git.exe -C $Tree @GitArgs
    return @($o | ForEach-Object { "" + $_ })
}

function Invoke-NightlySlot {
    # One slot run through the gate: { code; timedOut; gate; out }. A hidden child; the gate's own closing line is the
    # truth about the run (heavy-slot: released exit=N). The child is ended by ITS PID and the tree under it on
    # timeout or STOP, never by name.
    param([string]$Script, [string]$Worktree, [string[]]$ScriptArgs = @(), [string]$Tag)
    [void][System.IO.Directory]::CreateDirectory($RunDir)
    $safe = ($Tag -replace '[^A-Za-z0-9._-]', '_')
    $out = Join-Path $RunDir ($safe + ".log")
    $gateOut = Join-Path $RunDir ($safe + ".gate")
    $argv = @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", ('"' + $HeavySlot + '"'), "-Script", ('"' + $Script + '"'), "-Worktree", ('"' + $Worktree + '"'),
        "-Out", ('"' + $out + '"'), "-MinFreeGB", "4.5", "-WaitSeconds", $SlotWaitSeconds, "-RunSeconds", $RunSeconds)
    if (@($ScriptArgs).Count -gt 0) {
        $af = Join-Path $RunDir ($safe + ".args.json")
        Set-Content -LiteralPath $af -Value (ConvertTo-Json -InputObject @($ScriptArgs)) -Encoding Ascii
        $argv += @("-ArgsFile", ('"' + $af + '"'))
    }
    $p = Start-Process -FilePath $Ps51 -ArgumentList ($argv -join " ") -WorkingDirectory $WorkRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput $gateOut -RedirectStandardError ($gateOut + ".err")
    $null = $p.Handle
    try { $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Idle } catch { }
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $limit = $SlotWaitSeconds + $RunSeconds + 300
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
    return [pscustomobject]@{ code = $code; timedOut = $timedOut; gate = $gate; out = $out }
}

function Get-NightlyVerdict {
    # What a slot run's exit means for a suite: green 0; skip 3 (the suite skipped itself); unrun when the gate never
    # had the slot, the memory or the night (125, 127, 128) or the run was cut off by STOP; absent 126 (the suite
    # is not in this commit); red anything else, a timeout included.
    param($Run)
    if ($Run.timedOut) { return "unrun" }
    if ($Run.code -eq 0) { return "green" }
    if ($Run.code -eq 3) { return "skip" }
    if ($Run.code -eq 126) { return "absent" }
    if ($Run.code -eq 125 -or $Run.code -eq 127 -or $Run.code -eq 128) { return "unrun" }
    return "red"
}

function Invoke-NightlyUnit {
    # Run one unit at the checked-out tree: unit ids are "<suite rel path>|ps51", "<suite rel path>|pwsh7",
    # "pytest-node|<node id>" and "flake8-critical". Returns the verdict word of Get-NightlyVerdict ("red" included).
    param($Ctx, [string]$Unit, [string]$Tag)
    $tree = $Ctx.tree
    if ($Ctx.kind -ceq "horde") {
        $rel, $sh = $Unit -split '\|', 2
        if ($sh -ceq "pwsh7") {
            $abs = Join-Path $tree ($rel -replace '/', '\')
            return (Get-NightlyVerdict (Invoke-NightlySlot -Script "pwsh-wrap.ps1" -Worktree $WrapDir -ScriptArgs @($abs, $tree) -Tag $Tag))
        }
        return (Get-NightlyVerdict (Invoke-NightlySlot -Script ($rel -replace '/', '\') -Worktree $tree -Tag $Tag))
    }
    if ($Unit -ceq "flake8-critical") {
        return (Get-NightlyVerdict (Invoke-NightlySlot -Script "pytest-wrap.ps1" -Worktree $WrapDir -ScriptArgs @("-Tree", $tree, "-Mode", "flake8") -Tag $Tag))
    }
    $node = ($Unit -split '\|', 2)[1]
    $nf = Join-Path $RunDir (($Tag -replace '[^A-Za-z0-9._-]', '_') + ".nodes")
    [System.IO.File]::WriteAllText($nf, $node + "`n")
    $r = Invoke-NightlySlot -Script "pytest-wrap.ps1" -Worktree $WrapDir -ScriptArgs @("-Tree", $tree, "-Mode", "nodes", "-NodesFile", $nf) -Tag $Tag
    # pytest 4 (usage error: the file is not there) and 5 (nothing collected): the test is not in this commit.
    if (-not $r.timedOut -and ($r.code -eq 4 -or $r.code -eq 5)) { return "absent" }
    return (Get-NightlyVerdict $r)
}

function Read-NightlyState {
    param([string]$Path)
    $s = @{ lastTip = ""; units = @{} }
    if (-not (Test-Path -LiteralPath $Path)) { return $s }
    try {
        $o = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json
        $s.lastTip = "" + $o.lastTip
        foreach ($p in $o.units.PSObject.Properties) { $s.units["" + $p.Name] = "" + $p.Value }
    } catch { Say ("state unreadable, treated as empty: " + $Path + ": " + $_.Exception.Message); return @{ lastTip = ""; units = @{} } }
    return $s
}

function Write-NightlyState {
    param([string]$Path, $State)
    $u = [ordered]@{}
    foreach ($k in (@($State.units.Keys) | Sort-Object)) { $u[$k] = $State.units[$k] }
    $text = ([ordered]@{ lastTip = $State.lastTip; units = $u } | ConvertTo-Json -Depth 4)
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
    if (-not (Test-Path -LiteralPath (Join-Path $tree ".git"))) { & git.exe clone -q ("https://github.com/" + $repo + ".git") $tree; if ($LASTEXITCODE -ne 0) { throw ("git clone of " + $repo + " failed") } }
    [void](Invoke-NightlyGit $tree @("fetch", "--quiet", "origin"))
    [void](Invoke-NightlyGit $tree @("checkout", "--quiet", "--detach", ("origin/" + $branch)))
    [void](Invoke-NightlyGit $tree @("reset", "--hard", "--quiet", ("origin/" + $branch)))
    [void](Invoke-NightlyGit $tree @("clean", "-fdq"))
    $tip = (Invoke-NightlyGit $tree @("rev-parse", "HEAD"))[0].Trim()
    $statePath = Join-Path $dir "state.json"
    $state = Read-NightlyState $statePath
    $notes = @()
    $gitLines = @()
    if ($state.lastTip -ne "") {
        # --quiet prints nothing when the commit is not there; a 2> redirect would raise under 5.1 and Stop.
        $ok = $false
        $known = @(Invoke-NightlyGit $tree @("rev-parse", "--verify", "--quiet", ($state.lastTip + "^{commit}")))
        if ($known.Count -gt 0 -and $known[0] -match '^[0-9a-f]{40}$') { $ok = $true }
        $global:LASTEXITCODE = 0
        if ($ok) { $gitLines = Invoke-NightlyGit $tree @("log", "--first-parent", "--reverse", "--format=%H%x09%s", ($state.lastTip + ".." + $tip)) }
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
    param($Ctx, [datetime]$Cutoff)
    $tag = ($Ctx.repo -replace '/', '_')
    # THE GUARDS (horde): `horde merge -RunOwed -Json` through the gate (tools/nightly/guards-wrap.ps1 reads its -Json last line, F's shape of PR 375):
    if ($Ctx.kind -ceq "horde") {
        if (-not (Test-HordeNightlyMayStartRun -Now (Get-Date) -Cutoff $Cutoff -RunSeconds $RunSeconds)) { $Ctx.guards = [pscustomobject]@{ state = "not run"; text = "the night ran out before the guards could start" } }
        else {
            $g = Invoke-NightlySlot -Script "guards-wrap.ps1" -Worktree $WrapDir -ScriptArgs @("-Horde", $HordeScript, "-Repo", $Ctx.repo) -Tag ($tag + "-guards")
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
        if (-not (Test-HordeNightlyMayStartRun -Now (Get-Date) -Cutoff $Cutoff -RunSeconds $RunSeconds)) { $Ctx.incomplete = "the night ran out before every unit ran"; break }
        if ($u -ceq "pytest-all") {
            $nf = Join-Path $RunDir ($tag + "-nodes.txt")
            $r = Invoke-NightlySlot -Script "pytest-wrap.ps1" -Worktree $WrapDir -ScriptArgs @("-Tree", $Ctx.tree, "-Mode", "all", "-NodesFile", $nf) -Tag ($tag + "-pytest-all")
            $v = Get-NightlyVerdict $r
            if ($v -ceq "unrun" -or -not (Test-Path -LiteralPath $nf)) { $Ctx.incomplete = "the pytest run did not complete"; $Ctx.unrun++; continue }
            foreach ($n in @(Get-Content -LiteralPath $nf | Where-Object { $_.Trim() -ne "" })) { $Ctx.verdicts["pytest-node|" + $n.Trim()] = "red" }
            $Ctx.verdicts["pytest-all"] = "green"
            continue
        }
        $v = Invoke-NightlyUnit -Ctx $Ctx -Unit $u -Tag ($tag + "-" + $u)
        Say ($Ctx.repo + " " + $u + " -> " + $v)
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
    $shas = @($Ctx.merges | ForEach-Object { $_.sha })
    $budget = $MaxBisectRuns
    $memo = @{}
    foreach ($u in @($Ctx.compare.newlyRed)) {
        $isRed = {
            param($sha)
            $key = $sha + "|" + $u
            if ($memo.ContainsKey($key)) { return $memo[$key] }
            if (-not (Test-HordeNightlyMayStartRun -Now (Get-Date) -Cutoff $Cutoff -RunSeconds $RunSeconds) -or (Test-Path -LiteralPath $StopFile)) { return $null }
            [void](Invoke-NightlyGit $Ctx.tree @("checkout", "--quiet", "--detach", $sha))
            [void](Invoke-NightlyGit $Ctx.tree @("clean", "-fdq"))
            $v = Invoke-NightlyUnit -Ctx $Ctx -Unit $u -Tag (($Ctx.repo -replace '/', '_') + "-bisect-" + $sha.Substring(0, 8) + "-" + $u)
            $res = $null
            if ($v -ceq "red") { $res = $true } elseif ($v -ceq "green" -or $v -ceq "skip" -or $v -ceq "absent") { $res = $false }
            $memo[$key] = $res
            return $res
        }
        $found = Find-HordeNightlyCulprit -Merges $shas -IsRed $isRed -MaxRuns $budget
        $merge = $null
        if ($found.state -ceq "found") { $merge = @($Ctx.merges | Where-Object { $_.sha -ceq $found.sha })[0] }
        $Ctx.culprits += [pscustomobject]@{ unit = $u; state = $found.state; sha = $found.sha; merge = $merge; runs = $found.runs; between = $found.between }
        Say ($Ctx.repo + " bisect " + $u + " -> " + $found.state + " " + $found.sha + " in " + $found.runs + " runs")
    }
    [void](Invoke-NightlyGit $Ctx.tree @("checkout", "--quiet", "--detach", $Ctx.tip))
}

function Save-NightlyState {
    # Verdicts of the units that ran replace last night's; the tip moves only when every unit ran.
    param($Ctx)
    foreach ($k in @($Ctx.verdicts.Keys)) {
        $v = $Ctx.verdicts[$k]
        if ($v -ceq "green" -or $v -ceq "red" -or $v -ceq "skip") { $Ctx.state.units[$k] = $v }
    }
    if ($Ctx.kind -ceq "pytest" -and $Ctx.verdicts.ContainsKey("pytest-all")) {
        # The red list is what the whole run said: a node that passed is gone from it.
        foreach ($k in @($Ctx.state.units.Keys)) { if ($k -like "pytest-node|*" -and -not $Ctx.verdicts.ContainsKey($k)) { $Ctx.state.units.Remove($k) } }
    }
    if ($Ctx.incomplete -eq "" -and $Ctx.unrun -eq 0) { $Ctx.state.lastTip = $Ctx.tip }
    Write-NightlyState -Path $Ctx.statePath -State $Ctx.state
}

# ---------------------------------------------------------------- the run
[void][System.IO.Directory]::CreateDirectory($WorkRoot)
[void][System.IO.Directory]::CreateDirectory($ReportDir)
$now = Get-Date
$cutoff = Get-HordeNightlyDeadline -Now $now
$inWindow = Test-HordeNightlyWindow -Now $now
Say ("nightly net " + $Date + ": window " + $(if ($inWindow) { "open" } else { "CLOSED" }) + ", cutoff " + $cutoff.ToString("s") + ", repos " + ($Repos -join ", "))
if (-not $inWindow -and -not $Plan) { Say "outside the night window (22:00 to 06:30): nothing run"; exit 4 }

$mutex = New-Object System.Threading.Mutex($false, "Global\HordeNightlyNet")
if (-not $Plan -and -not $mutex.WaitOne(0)) { Say "another nightly run holds the mutex; exiting"; exit 0 }
try {
    $ctxs = @()
    foreach ($spec in $Repos) { $ctxs += (New-NightlyContext $spec) }
    if ($Plan) {
        foreach ($c in $ctxs) {
            Write-Host ("PLAN " + $c.repo + " (" + $c.kind + ") tip " + $c.tip.Substring(0, 8) + " last " + $(if ($c.state.lastTip -eq "") { "none" } else { $c.state.lastTip.Substring(0, 8) }) + ": " + @($c.merges).Count + " merges")
            foreach ($m in $c.merges) { Write-Host ("  merge " + (Format-HordeNightlyMerge -Merge $m) + " [" + $m.source + "]") }
            Write-Host ("  units: " + @(Get-NightlyUnits $c).Count)
            foreach ($n in $c.notes) { Write-Host ("  note: " + $n) }
        }
        exit 0
    }
    $suiteCutoff = $cutoff.AddMinutes(-$BisectReserveMinutes)
    foreach ($c in $ctxs) { Invoke-NightlyPhaseOne -Ctx $c -Cutoff $suiteCutoff; Complete-NightlyCompare $c }
    foreach ($c in $ctxs) { Invoke-NightlyBisect -Ctx $c -Cutoff $cutoff }
    foreach ($c in $ctxs) { Save-NightlyState $c }

    $repoRows = @()
    foreach ($c in $ctxs) {
        $repoRows += [pscustomobject]@{ repo = $c.repo; tip = $c.tip; lastTip = $c.state.lastTip; merges = $c.merges; guards = $c.guards
            suiteCount = @($c.verdicts.Keys).Count; unrunCount = $c.unrun; compare = $c.compare; culprits = $c.culprits; notes = $c.notes; incomplete = $c.incomplete }
    }
    $body = New-HordeNightlyReport -Date $Date -Repos $repoRows
    if ($body.Length -gt 6000) { $body = $body.Substring(0, 6000) + " ...cut, the full report is in the report folder." }
    $file = Join-Path $ReportDir ($Date + ".txt")
    [System.IO.File]::WriteAllText($file, $body + "`n")
    Say ("report written: " + $file)
    if ($NoTell) { exit 0 }
    & $TellProgram tell $Target -Kind report -MessageFile $file
    if ($LASTEXITCODE -ne 0) { Say ("the tell to " + $Target + " failed with exit " + $LASTEXITCODE + "; the report is at " + $file); exit 3 }
    Say ("report sent to " + $Target)
    exit 0
} finally {
    try { $mutex.ReleaseMutex() } catch { }
}
