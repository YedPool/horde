# core/NightlyNet - the pure and injectable parts of the nightly net (tools/NightlyNet.ps1). T-0331.
#
# THE FOUNDER'S RULE (2026-10-22): merges no longer wait for test runs during the day. ONE nightly run per
# repo covers the whole day's merges and reports to M by 07:00, naming the merge behind each new red. This
# file holds what that run DECIDES; the orchestrator holds what it DOES (clones, slot runs, the tell).
#
#   - the night window: starts at 22:00 or later, every unit of work must be over by 06:30;
#   - the day's merges: the first-parent merge commits of main since the last nightly run (git), labelled
#     with the pull request, task and lane from HORDE_HOME\merge\guards-owed.jsonl when the merge command
#     recorded them. Git is the truth for WHICH merges; the owed file only says more about them;
#   - the verdicts: a unit (a suite file in a shell, or a pytest node) is NEWLY RED when it is red now and was
#     green last night. A unit red last night too is STILL RED: reported, never bisected (its merge is
#     older than the day). A unit with no verdict from last night is NEW: reported as red, not bisected;
#   - the bisect: over the day's merges only (oldest first), binary search for the first merge at which the
#     unit is red, knowing the last night's tip was green and tonight's tip is red. A unit that is
#     not red at the tip when asked again is FLAKY, not blamed on a merge;
#   - the report: plain ASCII with no double quote, semicolon or angle bracket (the fleet's mail line is
#     parsed by a shell first).
#
# EVERYTHING IMPURE IS INJECTED (the clock, git, the test runner, the tell), so test/test-nightly-net.ps1
# needs no real wait, slot or repository. No Set-StrictMode here: this file is dot-sourced.

. (Join-Path $PSScriptRoot "JsonText.ps1")

function ConvertTo-HordeNightlyText {
    # One line of text safe for a tell: ASCII only, and no double quote, semicolon, angle bracket, backtick,
    # dollar sign or line break. Each is replaced by a character that keeps it readable.
    param([string]$Text)
    $t = "" + $Text
    $t = $t -replace "[`r`n`t]+", " "
    $t = $t.Replace('"', "'").Replace(";", ",").Replace("<", "(").Replace(">", ")").Replace('`', "'").Replace('$', "S")
    $t = $t -replace "[^\x20-\x7E]", "?"
    return ($t -replace "\s{2,}", " ").Trim()
}

function Test-HordeNightlyWindow {
    # May a nightly run START now? From StartHour (22) until the deadline hour:minute (06:30), local.
    param([datetime]$Now, [int]$StartHour = 22, [int]$EndHour = 6, [int]$EndMinute = 30)
    $m = $Now.Hour * 60 + $Now.Minute
    $end = $EndHour * 60 + $EndMinute
    return ($m -ge $StartHour * 60 -or $m -lt $end)
}

function Get-HordeNightlyTaskBoundary {
    # The StartBoundary of the scheduled task's daily trigger for a date: WALL-CLOCK time, no offset and no Z
    # (T-0397). An offset pins one UTC instant, so the task registered with -05:00 on 10-23 fired at 21:00 on the
    # nights after the clocks changed (11-01 to 11-03) and the run refused itself. No offset means 22:00 local, always.
    param([datetime]$Date, [int]$Hour = 22, [int]$Minute = 0)
    return ($Date.Date.AddHours($Hour).AddMinutes($Minute).ToString("yyyy-MM-dd'T'HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture))
}

function Get-HordeNightlyDeadline {
    # The 06:30 this night ends at: the next one at or after Now (a Now before 06:30 means today's).
    param([datetime]$Now, [int]$EndHour = 6, [int]$EndMinute = 30)
    $today = $Now.Date.AddHours($EndHour).AddMinutes($EndMinute)
    if ($Now -lt $today) { return $today }
    return $today.AddDays(1)
}

function Get-HordeNightlyRunCutoff {
    # The time every RUN must be over by: the night's deadline less -ReportReserveMinutes (15), which are kept for the
    # report, the tell (with its retries) and the save. Runs used to end exactly at 06:30, so a task stopped at its
    # 06:30 limit could die before the tell, a silent night (review of PR 380, finding 10).
    param([datetime]$Now, [int]$ReportReserveMinutes = 15, [int]$EndHour = 6, [int]$EndMinute = 30)
    return (Get-HordeNightlyDeadline -Now $Now -EndHour $EndHour -EndMinute $EndMinute).AddMinutes(-[math]::Max(0, $ReportReserveMinutes))
}

function ConvertTo-HordeNightlyBisectAnswer {
    # A unit's verdict at one bisect step as Find-HordeNightlyCulprit's answer: $true red, $false green or absent (the
    # suite is not in that commit yet), $null anything else, so the search stops inconclusive. A SKIP is $null: the
    # suite said nothing at that commit, and taking it as green moved the search past it to a later, innocent merge
    # (review of PR 380, finding 9).
    param([string]$Verdict)
    if ($Verdict -ceq "red") { return $true }
    if ($Verdict -ceq "green" -or $Verdict -ceq "absent") { return $false }
    return $null
}

function Test-HordeNightlyMayStartRun {
    # May a slot run of up to RunSeconds start now and still be over by the cutoff? A run is killed at its
    # own limit, so the worst case is Now plus RunSeconds.
    param([datetime]$Now, [datetime]$Cutoff, [int]$RunSeconds)
    return ($Now.AddSeconds($RunSeconds) -le $Cutoff)
}

function Test-HordeNightlyMemoryGiveUp {
    # Did this gate give up waiting for memory (free memory, or commit headroom)? Its own words say so
    # (tools/HeavySlot.ps1); exit 125 alone does not, as 125 is also a slot that was not had.
    param([string]$Gate)
    return (("" + $Gate) -match 'heavy-slot: gave up after \d+ s waiting for [0-9.]+ GB of (free memory|commit headroom)')
}

function Update-HordeNightlyMemoryShort {
    # FAIL FAST (2026-10-24). On the night of 2026-10-23 every gate waited the full 900 s for memory the box never
    # had, so only 25 units were even tried and the second repo never got a turn. After one memory give-up the
    # night is SHORT ON MEMORY and later gates wait only the short wait; the first gate that gets its memory (its
    # "heavy-slot: running" line) ends that, and the normal wait returns. Any other gate leaves it as it was.
    param([bool]$Short, [string]$Gate)
    if (Test-HordeNightlyMemoryGiveUp -Gate $Gate) { return $true }
    if (("" + $Gate) -match '(?m)^heavy-slot: running ') { return $false }
    return $Short
}

function Get-HordeNightlySlotWait {
    # The slot wait in force: -Short while the night is short on memory (never longer than -Normal), else -Normal.
    param([bool]$MemoryShort, [int]$Normal, [int]$Short)
    if ($MemoryShort) { return [math]::Min($Normal, $Short) }
    return $Normal
}

function Get-HordeNightlyNightFloors {
    # THE NIGHT FLOORS, the one place they are set (founder's YES, 2026-10-26). On the nights of 2026-10-23 and
    # 2026-10-25 free memory was 1.1 to 2.5 GB all night and the 4.5 GB floor ran 0 of 462 units; a horde suite
    # file was measured at 0.1 to 0.4 GB peak, so 1 GB free covers one with room, and the whole pytest run
    # of the Python repo gets 2.5 GB. Commit headroom (commit limit less commit charge) 1 GB for every kind.
    # Keys are the -Repos kinds; the guards are a horde run.
    return @{ freeGB = @{ horde = 1.0; pytest = 2.5 }; commitGB = 1.0; startHour = 22; endHour = 7 }
}

function Get-HordeNightlyMemoryFloor {
    # The floor a gate of this repo kind is given now: { freeGB; commitGB; night }. Inside the night hours
    # (22:00 to 07:00, Get-HordeNightlyNightFloors) the night floor of the kind; outside them the day floor the
    # caller passes (-MinFreeGB, -MinCommitHeadroomGB of tools/NightlyNet.ps1), so nothing changes by day. A
    # kind with no night floor keeps the day floor.
    param([datetime]$Now, [string]$Kind, [double]$DayFreeGB, [double]$DayCommitGB)
    $f = Get-HordeNightlyNightFloors
    $h = $Now.Hour
    $night = ($h -ge $f.startHour -or $h -lt $f.endHour)
    if (-not $night -or -not $f.freeGB.ContainsKey($Kind)) { return [pscustomobject]@{ freeGB = $DayFreeGB; commitGB = $DayCommitGB; night = $false } }
    return [pscustomobject]@{ freeGB = [double]$f.freeGB[$Kind]; commitGB = [double]$f.commitGB; night = $true }
}

function Test-HordeNightlyMayStartSuiteRun {
    # May a run of the full-suite phase start now? Before 2026-10-26 a unit needed Now + its slot wait + its whole
    # -RunSeconds (1500) before the SUITE cutoff (06:15 less the 90 min bisect reserve), so the last 1620 s of the
    # phase started nothing (2026-10-25: the last unit was tried at 04:18), though units take a minute or so. Now
    # it may start while Now + its slot wait is before the suite cutoff, as long as its worst case (wait plus
    # RunSeconds) still ends by the RUN cutoff: a long unit eats into the bisect reserve, never past 06:15.
    param([datetime]$Now, [datetime]$SuiteCutoff, [datetime]$RunCutoff, [int]$WaitSeconds, [int]$RunSeconds)
    return ((Get-HordeNightlySuiteRunSeconds -Now $Now -SuiteCutoff $SuiteCutoff -RunCutoff $RunCutoff -WaitSeconds $WaitSeconds -RunSeconds $RunSeconds -MinSeconds $RunSeconds) -gt 0)
}

function Get-HordeNightlySuiteRunSeconds {
    # The run limit a unit of the suite phase is given if it starts now, or 0 when it may not start. It may start
    # while its wait ends by the suite cutoff. It gets -RunSeconds when that still ends by the run cutoff; near the
    # end it gets what is left, if that is at least -MinSeconds (a per-unit limit FITTED to the night: a horde
    # suite file takes well under 600 s, the longest measured about 540 s, so a 1500 s reservation kept the last 25
    # minutes of the night idle). A unit past its fitted limit is ended and reported unrun, never green.
    param([datetime]$Now, [datetime]$SuiteCutoff, [datetime]$RunCutoff, [int]$WaitSeconds, [int]$RunSeconds, [int]$MinSeconds = 600)
    if ($Now.AddSeconds($WaitSeconds) -gt $SuiteCutoff) { return 0 }
    $left = [int][math]::Floor(($RunCutoff - $Now).TotalSeconds - $WaitSeconds)
    if ($left -ge $RunSeconds) { return $RunSeconds }
    if ($left -ge [math]::Min($MinSeconds, $RunSeconds)) { return $left }
    return 0
}

function Read-HordeNightlyMemoryHolders {
    # The memory holders a gate listed when it gave up (core/HeavySlotAcquire.ps1 Get-HordeHeavySlotMemoryHolders):
    # [{ name; count; gb }], in the gate's order (largest first).
    param([string]$Gate)
    $out = @()
    foreach ($m in [regex]::Matches(("" + $Gate), '(?m)^heavy-slot: memory held by (.+?), (\d+) processes, ([0-9.]+) GB\s*$')) {
        $out += [pscustomobject]@{ name = $m.Groups[1].Value; count = [int]$m.Groups[2].Value; gb = [double]::Parse($m.Groups[3].Value, [System.Globalization.CultureInfo]::InvariantCulture) }
    }
    return @($out)
}

function Get-HordeNightlyRepoOrder {
    # THE ORDER THE REPOS RUN IN (2026-10-24): fewest units first, ties in the order given. On the night of
    # 2026-10-23 horde (484 units) ran first and the pytest repo (2 units) never got a turn. A small repo first
    # costs the big one at most its few runs; the big one first can take the whole night. -Counts are the units
    # per repo in -Repos order; the answer is their indexes in run order.
    param([int[]]$Counts)
    $c = @($Counts)
    $idx = @(0..($c.Count - 1) | Where-Object { $c.Count -gt 0 })
    return @($idx | Sort-Object -Property @{ Expression = { $c[$_] } }, @{ Expression = { $_ } })
}

function Get-HordeNightlyRunCount {
    # How many units RAN: every verdict but unrun and skipped. A gate that exits 125, 127, 128 or 71 ran nothing, and on
    # the night of 2026-10-23 the report said "units run: 24" when all 24 had exited 125 (it counted every verdict). A
    # unit SKIPPED because the night lacks what it needs (Get-HordeNightlySkipReason) never ran either.
    param($Verdicts)
    $n = 0
    foreach ($k in @($Verdicts.Keys)) { $v = "" + $Verdicts[$k]; if ($v -cne "unrun" -and $v -cne "skipped") { $n++ } }
    return $n
}

# WHAT A UNIT NEEDS FROM THE NIGHT (T-0331, 2026-10-27). On the night of 2026-10-26, 14 horde units were red only because
# the scheduled task (non-elevated) lacked something, not because the code was wrong: the privilege to make a symbolic
# link (decisions-store, files-cli, files-deny, files-store), an elevated token (setup-store-folder: a folder only
# SYSTEM and Administrators may list cannot be removed without one), WSL (the multiplexer host's isolation suite), and a
# wezfleet checkout (roles' drift check), each in both shells. A suite DECLARES such a need in its own header, one line:
#     # nightly-needs: symlink, elevated
# so the need sits beside the code that has it and a grep for "nightly-needs:" lists them all (as names.txt and the
# suites' own headers carry their facts, not a list kept elsewhere). The runner probes each need once a night and marks
# a unit whose need is not met SKIPPED with the reason: not red, not green, and said in the report.
function Get-HordeNightlyNeedNames {
    # The needs the runner can probe (tools/nightly/Probes.ps1). Any other name is answered "no probe" and skipped.
    return @("symlink", "elevated", "wsl", "wezfleet-repo")
}

function Read-HordeNightlyNeeds {
    # The needs a suite file declares: its "# nightly-needs: a, b" lines, read from the LEADING COMMENT BLOCK only (up to
    # the first line that is neither blank nor a # comment), so a string later in a suite that holds the same words is
    # never a declaration. A name is lower-case letters, digits and dashes; a line that starts a declaration but is not
    # of that shape is the need "malformed", which no probe answers, so its unit is skipped and the reason names it,
    # never run as if it had declared nothing.
    param([string[]]$Lines)
    $needs = @()
    foreach ($l in @($Lines)) {
        $t = ("" + $l).Trim()
        if ($t -eq "") { continue }
        if (-not $t.StartsWith("#")) { break }
        if ($t -notmatch '^#\s*nightly-needs\s*:') { continue }
        $m = [regex]::Match($t, '^#\s*nightly-needs:\s*([a-z0-9-]+(?:\s*,\s*[a-z0-9-]+)*)\s*$')
        if (-not $m.Success) { $needs += "malformed"; continue }
        foreach ($n in ($m.Groups[1].Value -split ",")) { $needs += $n.Trim() }
    }
    return @($needs | Select-Object -Unique)
}

function Get-HordeNightlySkipReason {
    # Why a unit is SKIPPED tonight, or "" when it runs. -Needs: Read-HordeNightlyNeeds. -Probes: the night's probe
    # answers, a hashtable name -> { ok; why }. A need whose probe says ok is met; any other need (probe false, or no
    # probe answer at all) is not, and the reason names each unmet need with its probe's why.
    param([string[]]$Needs, [hashtable]$Probes)
    $why = @()
    foreach ($n in @($Needs | Where-Object { "" + $_ -ne "" })) {
        $p = $null; if ($null -ne $Probes -and $Probes.ContainsKey($n)) { $p = $Probes[$n] }
        if ($null -eq $p) { $why += ("needs " + $n + ", which no probe answers"); continue }
        if ($p.ok -eq $true) { continue }
        $w = "" + $p.why; if ($w -eq "") { $w = "the probe said no" }
        $why += ("needs " + $n + ": " + $w)
    }
    return ($why -join ", and ")
}

function Read-HordeNightlyOwed {
    # The lines of guards-owed.jsonl for one repo: { entries; bad } - entries are objects with mergeSha, pr,
    # task, by, at, firstParent...; bad counts lines that were not JSON objects (skipped, said in the report).
    param([string[]]$Lines, [string]$Repo)
    $entries = @(); $bad = 0
    foreach ($l in @($Lines)) {
        if ("" + $l -eq "" -or ("" + $l).Trim() -eq "") { continue }
        $o = $null
        try { $o = ConvertFrom-HordeJson ("" + $l) } catch { $o = $null }
        if ($null -eq $o -or $o -isnot [pscustomobject]) { $bad++; continue }
        $r = ""; if ($o.PSObject.Properties["repo"]) { $r = "" + $o.repo }
        if ($Repo -ne "" -and $r -ne "" -and $r -ine $Repo) { continue }
        $entries += $o
    }
    return [pscustomobject]@{ entries = @($entries); bad = $bad }
}

function Get-HordeNightlyMerges {
    # The day's merges, OLDEST FIRST: [{ sha; subject; pr; task; by; source }].
    # -GitLines are `git log --first-parent --reverse --format=%H<TAB>%s <last>..<tip>` lines, so git decides which
    # merges there were. -Owed is Read-HordeNightlyOwed's answer: an entry for the same merge sha only adds its
    # pull request, task and lane. A first-parent commit that is not a merge (a direct push) is a merge-sized
    # change of main all the same and is listed.
    param([string[]]$GitLines, $Owed = $null)
    $byRef = @{}
    if ($null -ne $Owed) {
        foreach ($e in @($Owed.entries)) {
            $s = ""; if ($e.PSObject.Properties["mergeSha"]) { $s = ("" + $e.mergeSha).ToLowerInvariant() }
            if ($s -ne "") { $byRef[$s] = $e }
        }
    }
    $out = @()
    foreach ($l in @($GitLines)) {
        $parts = ("" + $l) -split "`t", 2
        $sha = $parts[0].Trim().ToLowerInvariant()
        if ($sha -notmatch '^[0-9a-f]{7,40}$') { continue }
        $subject = ""; if ($parts.Count -gt 1) { $subject = $parts[1].Trim() }
        $pr = ""; $task = ""; $by = ""; $source = "git"
        $hit = $null
        foreach ($k in @($byRef.Keys)) { if ($k.StartsWith($sha) -or $sha.StartsWith($k)) { $hit = $byRef[$k]; break } }
        if ($null -ne $hit) {
            $source = "owed"
            foreach ($f in @("pr", "task", "by")) { if ($hit.PSObject.Properties[$f]) { Set-Variable -Name $f -Value ("" + $hit.$f) } }
        }
        if ($pr -eq "") { $m = [regex]::Match($subject, 'Merge pull request #(\d+)'); if ($m.Success) { $pr = $m.Groups[1].Value } }
        $out += [pscustomobject]@{ sha = $sha; subject = $subject; pr = $pr; task = $task; by = $by; source = $source }
    }
    return @($out)
}

function Compare-HordeNightlyVerdicts {
    # Now against last night, per unit. -Now: unit -> "green" | "red" | "skip" | "skipped" | "unrun" | "hung". -Last: unit -> "green" | "red" | ...
    # Answer: { newlyRed; stillRed; newRed; fixed; unrun; hung; skipped } as sorted unit names. unrun (the slot was never
    # had, or the night ran out) says nothing either way and leaves the old verdict to stand. hung (it ran past its limit
    # at the tip) is a finding of its own: reported every night it hangs, never bisected. skipped (the night lacks what
    # the unit needs) is listed apart: never green, never fixed.
    param($Now, $Last)
    $newly = @(); $still = @(); $new = @(); $fixed = @(); $unrun = @(); $hung = @(); $skipped = @()
    foreach ($u in (@($Now.Keys) | Sort-Object)) {
        $v = "" + $Now[$u]
        $was = ""; if ($Last.ContainsKey($u)) { $was = "" + $Last[$u] }
        if ($v -ceq "unrun") { $unrun += $u; continue }
        if ($v -ceq "skipped") { $skipped += $u; continue }
        if ($v -ceq "hung") { $hung += $u; continue }
        if ($v -ceq "red") {
            if ($was -ceq "green") { $newly += $u } elseif ($was -ceq "red") { $still += $u } else { $new += $u }
        } elseif ($v -ceq "green" -and $was -ceq "red") { $fixed += $u }
    }
    return [pscustomobject]@{ newlyRed = @($newly); stillRed = @($still); newRed = @($new); fixed = @($fixed); unrun = @($unrun); hung = @($hung); skipped = @($skipped) }
}

function Find-HordeNightlyCulprit {
    # Which of the day's merges first made a unit red? -Merges oldest first (their shas); -IsRed is
    # param($sha): $true when the unit is red with that merge checked out, $false when green, $null when it
    # could not be told (the run did not happen). The last night's tip (before the first merge) was green and the tip
    # (the last merge) is red, and that is CHECKED first: a tip that is not red now is "flaky". A bisect that gets
    # an unreadable answer ends "inconclusive" with what it knew. -MaxRuns caps the runs (the tip check counts).
    # { state = "found" | "flaky" | "inconclusive" | "capped" | "none"; sha; runs; between }
    #   between: when not found, the pair (last known green sha or "" , first known red sha) the search had narrowed to.
    param([string[]]$Merges, [scriptblock]$IsRed, [int]$MaxRuns = 40)
    $m = @($Merges)
    $runs = 0
    if ($m.Count -eq 0) { return [pscustomobject]@{ state = "none"; sha = ""; runs = 0; between = @("", "") } }
    $tip = $m[$m.Count - 1]
    $runs++
    $r = & $IsRed $tip
    if ($null -eq $r) { return [pscustomobject]@{ state = "inconclusive"; sha = ""; runs = $runs; between = @("", $tip) } }
    if (-not $r) { return [pscustomobject]@{ state = "flaky"; sha = ""; runs = $runs; between = @("", $tip) } }
    $lo = -1                   # index of the last merge known green (-1: the last night's tip)
    $hi = $m.Count - 1         # index of the first merge known red
    while ($hi - $lo -gt 1) {
        $mid = [int][math]::Floor(($lo + $hi) / 2)
        if ($runs -ge $MaxRuns) { return [pscustomobject]@{ state = "capped"; sha = ""; runs = $runs; between = @($(if ($lo -ge 0) { $m[$lo] } else { "" }), $m[$hi]) } }
        $runs++
        $r = & $IsRed $m[$mid]
        if ($null -eq $r) { return [pscustomobject]@{ state = "inconclusive"; sha = ""; runs = $runs; between = @($(if ($lo -ge 0) { $m[$lo] } else { "" }), $m[$hi]) } }
        if ($r) { $hi = $mid } else { $lo = $mid }
    }
    return [pscustomobject]@{ state = "found"; sha = $m[$hi]; runs = $runs; between = @($(if ($lo -ge 0) { $m[$lo] } else { "" }), $m[$hi]) }
}

function Get-HordeNightlyGuardsAnswer {
    # What `horde merge -RunOwed -Repo X -Json` said (F's shape, PR 375): the PROCESS exits 0 (green or nothing
    # owed) or 1 (red or could not run); 2 means a bad command line, which is also what a horde without the verb
    # gives. The real split is the exit field of the -Json LAST line: 0 green, 1 red, 2 could not run. So:
    # a process exit of 2 (or any other than 0 or 1), a missing last line, a line that is not a JSON object, or an
    # exit field that is not 0, 1 or 2 is COULD NOT RUN, never green. { code (0, 1 or 2); state; text }.
    param([int]$ProcessExit, [string[]]$Lines)
    $non = @(@($Lines) | Where-Object { "" + $_ -ne "" -and ("" + $_).Trim() -ne "" })
    $last = ""; if ($non.Count -gt 0) { $last = ("" + $non[$non.Count - 1]).Trim() }
    $text = ""
    if ($last -ne "") { $text = $last; if ($text.Length -gt 700) { $text = $text.Substring(0, 700) } }
    if ($ProcessExit -ne 0 -and $ProcessExit -ne 1) { return [pscustomobject]@{ code = 2; state = "could not run"; text = ("process exit " + $ProcessExit + " (a horde without the verb answers 2)") } }
    $o = $null
    if ($last -ne "") { try { $o = ConvertFrom-HordeJson $last } catch { $o = $null } }
    if ($null -eq $o -or $o -isnot [pscustomobject] -or -not $o.PSObject.Properties["exit"]) { return [pscustomobject]@{ code = 2; state = "could not run"; text = "no -Json last line to read" } }
    $e = $o.exit
    if ($e -isnot [int] -and $e -isnot [long]) { return [pscustomobject]@{ code = 2; state = "could not run"; text = ("the -Json exit field is not a number: " + $text) } }
    if ($e -eq 0) { return [pscustomobject]@{ code = 0; state = "green"; text = $text } }
    if ($e -eq 1) { return [pscustomobject]@{ code = 1; state = "RED"; text = $text } }
    if ($e -eq 2) { return [pscustomobject]@{ code = 2; state = "could not run"; text = $text } }
    return [pscustomobject]@{ code = 2; state = "could not run"; text = ("the -Json exit field is " + $e + ": " + $text) }
}

function Get-HordeNightlyVerdict {
    # What a slot run's exit means for a suite: green 0, skip 3 (the suite skipped itself), absent 126 (the suite is not in
    # this commit), UNRUN when the gate never had the slot, the memory or the night (125, 127, 128, 71), or the run was
    # cut off by STOP or by the night's own limit (timedOut); red anything else.
    # GATE EXIT 124, the suite ran past its limit: inside a bisect it is UNRUN, so a slow box never blames a merge
    # (T-0331 N2). At the TIP (-AtTip) it is HUNG, a finding reported as such: as unrun it held the tip back every night
    # a suite hangs, so the merge range grew without end and the hang was never reported (review of PR 380, finding 3).
    # A run with NO exit code is red: [int]$null is 0, which read it as green (review of PR 380, finding 5).
    param($Run, [switch]$AtTip)
    if ($Run.timedOut) { return "unrun" }
    if ($null -eq $Run.code -or "" + $Run.code -eq "") { return "red" }
    $c = [int]$Run.code
    if ($c -eq 0) { return "green" }
    if ($c -eq 3) { return "skip" }
    if ($c -eq 126) { return "absent" }
    if ($c -eq 124) { if ($AtTip) { return "hung" } return "unrun" }
    if ($c -eq 125 -or $c -eq 127 -or $c -eq 128 -or $c -eq 71) { return "unrun" }
    return "red"
}

function Get-HordeNightlyStoredVerdict {
    # The verdict to keep in state.json for a unit: -Verdict is tonight's, -Previous is what is stored ("" for none).
    # green, red and hung replace; anything else (unrun, absent) changes nothing. Returns "" for no change.
    # A SKIP carries a stored RED forward (a skip says nothing, so it must not clear a red, T-0331 N3) but NEVER a
    # stored green: the tip moves on over a skip, so a green kept across it would make the next red "newly red" and
    # bisect only the latest day's merges, naming an innocent one when the break came in a skipped day (review of
    # PR 380, finding 1). Stored "skip" is no verdict, so that red is reported with no merge named. A unit SKIPPED for a
    # need the night lacks is kept exactly as a skip: it says nothing about the code either.
    param([string]$Verdict, [string]$Previous = "")
    if ($Verdict -ceq "green" -or $Verdict -ceq "red" -or $Verdict -ceq "hung") { return $Verdict }
    if ($Verdict -ceq "skip" -or $Verdict -ceq "skipped") { if ($Previous -ceq "red") { return "" } return "skip" }
    return ""
}

function Format-HordeNightlyArgument {
    # One argument for a Windows command line (CommandLineToArgvW rules): bare when it holds no space or double quote,
    # otherwise quoted, with backslashes before a quote and at the end doubled.
    param([string]$Arg)
    if ($Arg -eq "") { return '""' }
    if ($Arg -notmatch '[\s"]') { return $Arg }
    $q = [regex]::Replace($Arg, '(\\*)"', { param($m) $m.Groups[1].Value + $m.Groups[1].Value + '\"' })
    $q = [regex]::Replace($q, '(\\+)$', { param($m) $m.Groups[1].Value + $m.Groups[1].Value })
    return ('"' + $q + '"')
}

function Invoke-HordeNightlyProcess {
    # Run a program with a TIME LIMIT (review of PR 380, finding 4: clone, fetch and the tell had none, and a wedged
    # one kept the night's lock, so every following night exited at the lock). A hidden child, its output and error
    # collected from files; past -TimeoutSeconds the child and the tree under it are ended BY ITS PID, never by name.
    # A .ps1 is run by this shell's own executable. { code ($null when it timed out or none was read); timedOut; lines }.
    param([string]$FilePath, [string[]]$ArgumentList = @(), [int]$TimeoutSeconds = 300)
    $argv = @($ArgumentList)
    if ($FilePath -like "*.ps1") { $argv = @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $FilePath) + $argv; $FilePath = (Get-Process -Id $PID).Path }
    $base = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-nightly-proc-" + [guid]::NewGuid().ToString("N"))
    $outF = $base + ".out"; $errF = $base + ".err"
    $line = (@($argv | ForEach-Object { Format-HordeNightlyArgument ("" + $_) })) -join " "
    $sp = @{ FilePath = $FilePath; PassThru = $true; WindowStyle = "Hidden"; RedirectStandardOutput = $outF; RedirectStandardError = $errF }
    if ($line -ne "") { $sp["ArgumentList"] = $line }
    $code = $null; $timedOut = $false; $lines = @()
    try {
        $p = Start-Process @sp
        $null = $p.Handle
        if (-not $p.WaitForExit([math]::Max(1, $TimeoutSeconds) * 1000)) {
            $timedOut = $true
            & taskkill.exe /PID $p.Id /T /F | Out-Null
            [void]$p.WaitForExit(10000)
        } else { $p.WaitForExit(); $code = $p.ExitCode }
        foreach ($f in @($outF, $errF)) { if (Test-Path -LiteralPath $f) { $lines += @(Get-Content -LiteralPath $f | ForEach-Object { "" + $_ }) } }
    } finally { Remove-Item -LiteralPath $outF, $errF -Force -ErrorAction SilentlyContinue }
    return [pscustomobject]@{ code = $code; timedOut = $timedOut; lines = @($lines) }
}

function Get-HordeNightlyTellOutcome {
    # What the tell program's exit means: "told", "unconfirmed" or "retry" (review of PR 380, finding 2). Its exit codes:
    # 0 delivered and 6 posted to the target's mailbox, handed over at its next turn end ("delayed, NOT lost ... DO NOT
    # RESEND"): both are TOLD. 2 the text left the box, unconfirmed: a resend could double it, so it is not retried, and
    # the findings stay pending for the next report. Anything else (1 not typed, 3 the box held other text, 4 the
    # reader failed, 5 a fragment, no exit code at all) is worth another try.
    param($Code)
    if ($null -eq $Code) { return "retry" }
    $c = [int]$Code
    if ($c -eq 0 -or $c -eq 6) { return "told" }
    if ($c -eq 2) { return "unconfirmed" }
    return "retry"
}

function Invoke-HordeNightlyTell {
    # Tell the target the report in -File: 0 told, 3 not told (no program, a throw, an exit that is not told after
    # -Tries tries, -RetrySeconds apart). Returns exactly one int: the program's output is collected, never left loose
    # (left loose it would join the return value, T-0331 N1), and each line of it goes to -Say, so the log keeps the
    # program's reason and mail id (review of PR 380, finding 7). -Say is a scriptblock taking one line.
    # Each try is time-boxed (-TimeoutSeconds, Invoke-HordeNightlyProcess): a tell that hangs is a failed try.
    param([string]$Program, [string]$Target, [string]$File, [scriptblock]$Say = { param($l) }, [switch]$NoTell, [int]$Tries = 3, [int]$RetrySeconds = 120, [int]$TimeoutSeconds = 300)
    if ($NoTell) { return 0 }
    $cmd = Get-Command $Program -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $cmd) { & $Say ("the tell program '" + $Program + "' is not on the PATH, the report is at " + $File); return 3 }
    for ($try = 1; $try -le [math]::Max(1, $Tries); $try++) {
        $code = $null
        try {
            $run = Invoke-HordeNightlyProcess -FilePath $cmd.Source -ArgumentList @("tell", $Target, "-Kind", "report", "-MessageFile", $File) -TimeoutSeconds $TimeoutSeconds
            $code = $run.code
            foreach ($l in @($run.lines)) { $t = ConvertTo-HordeNightlyText ("" + $l); if ($t -ne "") { & $Say ("tell: " + $t) } }
            if ($run.timedOut) { & $Say ("the tell to " + $Target + " ran past " + $TimeoutSeconds + " s and was ended") }
        } catch { & $Say ("the tell to " + $Target + " threw: " + $_.Exception.Message) }
        $what = Get-HordeNightlyTellOutcome $code
        if ($what -ceq "told") { & $Say ("report sent to " + $Target + " (exit " + $code + ")"); return 0 }
        if ($what -ceq "unconfirmed") { & $Say ("the tell to " + $Target + " is unconfirmed (exit 2), not resent: the report is at " + $File); return 3 }
        & $Say ("the tell to " + $Target + " failed with exit " + $code + " (try " + $try + " of " + $Tries + "), the report is at " + $File)
        if ($try -lt $Tries -and $RetrySeconds -gt 0) { Start-Sleep -Seconds $RetrySeconds }
    }
    return 3
}

function Get-HordeNightlyFindingLines {
    # The findings of one repo row, one line each and not indented: every bisected unit's line (named merge, flaky,
    # capped, inconclusive) and the red units with no verdict last night. The report prints them, and a night whose
    # tell failed keeps them pending for the next report.
    param($Row)
    $lines = @()
    foreach ($k in @($Row.culprits)) {
        if ($k.state -ceq "found") { $lines += ("RED " + $k.unit + " first red at merge " + (Format-HordeNightlyMerge -Merge $k.merge) + " (" + $k.runs + " runs)") }
        elseif ($k.state -ceq "flaky") { $lines += ("RED " + $k.unit + " was not red when run again at the tip: flaky, no merge named") }
        elseif ($k.state -ceq "capped") { $lines += ("RED " + $k.unit + " not bisected to one merge (run cap): after " + $(if ("" + $k.between[0] -eq "") { "last night" } else { (Format-HordeNightlySha $k.between[0]) }) + " up to " + (Format-HordeNightlySha $k.between[1])) }
        elseif ($k.state -ceq "none") { $lines += ("RED " + $k.unit + " has no merge since last night to name") }
        else { $lines += ("RED " + $k.unit + " bisect inconclusive (a run did not happen): " + $k.state) }
    }
    $c = $Row.compare
    if ($c.PSObject.Properties["hung"]) { foreach ($u in @($c.hung)) { $lines += ("HUNG " + $u + " ran past its time limit at the tip: no merge named (a bisect cannot tell a slow box from a hang)") } }
    foreach ($u in @($c.newRed | Select-Object -First 15)) { $lines += ("red, no verdict last night: " + $u) }
    if (@($c.newRed).Count -gt 15) { $lines += ("red, no verdict last night: and " + (@($c.newRed).Count - 15) + " more") }
    return @($lines | ForEach-Object { ConvertTo-HordeNightlyText $_ })
}

function Update-HordeNightlyState {
    # The state.json to keep after a night, as data: @{ lastTip; units; pending }. -State is last night's (the same
    # shape; pending may be missing). TEST STATE AND TOLD STATE ARE SEPARATE (review of PR 380, finding 2): tonight's
    # verdicts are kept whether or not M was told, so a red is never re-labelled newly red night after night and
    # re-bisected; what M has not been told is kept apart, in pending: when -Told is false, tonight's -Findings join it
    # (each prefixed with -Date), and the next report re-lists all of it until a tell succeeds, which empties it.
    # The verdicts of the units that ran replace last night's (Get-HordeNightlyStoredVerdict); for a pytest repo whose
    # whole run finished, a stored red node that is not red tonight is gone. The tip moves only when -Complete (every
    # unit ran), so a short night widens tomorrow's range instead of losing a merge.
    param($State, $Verdicts, [string]$Kind = "horde", [string]$Tip = "", [bool]$Complete = $false, [bool]$Told = $false, [string[]]$Findings = @(), [string]$Date = "", [int]$MaxPending = 40)
    $units = @{}
    foreach ($k in @($State.units.Keys)) { $units[$k] = $State.units[$k] }
    foreach ($k in @($Verdicts.Keys)) {
        $prev = ""; if ($units.ContainsKey($k)) { $prev = "" + $units[$k] }
        $keep = Get-HordeNightlyStoredVerdict -Verdict ("" + $Verdicts[$k]) -Previous $prev
        if ($keep -ne "") { $units[$k] = $keep }
    }
    if ($Kind -ceq "pytest" -and $Verdicts.ContainsKey("pytest-all")) {
        foreach ($k in @($units.Keys)) { if ($k -like "pytest-node|*" -and -not $Verdicts.ContainsKey($k)) { $units.Remove($k) } }
    }
    $last = "" + $State.lastTip
    if ($Complete) { $last = $Tip }
    $pending = @()
    if ($State.ContainsKey("pending")) { $pending = @($State.pending | Where-Object { "" + $_ -ne "" } | ForEach-Object { "" + $_ }) }
    if ($Told) { $pending = @() }
    else { foreach ($f in @($Findings)) { if ("" + $f -ne "") { $pending += (ConvertTo-HordeNightlyText ($Date + ": " + $f)) } } }
    if ($pending.Count -gt $MaxPending) { $pending = @($pending[($pending.Count - $MaxPending)..($pending.Count - 1)]) }
    return @{ lastTip = $last; units = $units; pending = @($pending) }
}

function Get-HordeNightlyHeadlineStatus {
    # COMPLETE, or INCOMPLETE with why: units not run, an incomplete repo, guards that did not run (T-0331 N4/N5), a
    # bisect that named no merge.
    param([object[]]$Repos)
    $why = @()
    $unrun = 0; $inc = @(); $gbad = @(); $gred = @(); $hung = 0; $unnamed = 0
    foreach ($r in @($Repos)) {
        if ($r.PSObject.Properties["culprits"]) { $unnamed += @(@($r.culprits) | Where-Object { @("capped", "inconclusive", "flaky") -ccontains ("" + $_.state) }).Count }
        $unrun += [int]$r.unrunCount
        if ($r.compare.PSObject.Properties["hung"]) { $hung += @($r.compare.hung).Count }
        if ("" + $r.incomplete -ne "") { $inc += $r.repo }
        $gs = "" + $r.guards.state
        if ($gs -ceq "RED") { $gred += $r.repo }
        elseif ($gs -cne "green" -and $gs -notlike "no repo-wide guard*") { $gbad += $r.repo }
    }
    if ($inc.Count -gt 0) { $why += ("the night did not finish in " + ($inc -join ", ")) }
    if ($unrun -gt 0) { $why += ("" + $unrun + " units not run") }
    if ($gbad.Count -gt 0) { $why += ("guards could not run or did not run in " + ($gbad -join ", ")) }
    # A newly red unit whose bisect named no merge (capped, inconclusive or flaky) is not a finished answer: COMPLETE
    # read as every new red has a name (review of PR 380, finding 11).
    if ($unnamed -gt 0) { $why += ("" + $unnamed + " bisects named no merge (capped, inconclusive or flaky)") }
    $t = $(if ($why.Count -gt 0) { "INCOMPLETE: " + ($why -join ", ") + "." } else { "COMPLETE." })
    if ($gred.Count -gt 0) { $t += " GUARDS RED in " + ($gred -join ", ") + "." }
    if ($hung -gt 0) { $t += " HUNG: " + $hung + " units ran past their time limit." }
    # Skipped units are not INCOMPLETE (the night lacks the same thing every night, so it would never read COMPLETE), but
    # the headline says how many, so a night that skipped half the suite never reads as a whole one.
    $skipped = 0
    foreach ($r in @($Repos)) { if ($r.compare.PSObject.Properties["skipped"]) { $skipped += @($r.compare.skipped).Count } }
    if ($skipped -gt 0) { $t += " SKIPPED: " + $skipped + " units, the night lacks what they need (never green)." }
    return $t
}

function Format-HordeNightlySha {
    # The first 8 characters of a sha, or all of a shorter one.
    param($Sha)
    $s = "" + $Sha
    return $s.Substring(0, [math]::Min(8, $s.Length))
}

function Format-HordeNightlyMerge {
    # "<short sha> PR 123 T-0331 by lane: subject", as far as it is known. Sanitized by the caller's line.
    param($Merge)
    $s = Format-HordeNightlySha $Merge.sha
    $bits = @($s)
    if ("" + $Merge.pr -ne "") { $bits += ("PR " + $Merge.pr) }
    if ("" + $Merge.task -ne "") { $bits += ("" + $Merge.task) }
    if ("" + $Merge.by -ne "") { $bits += ("by " + $Merge.by) }
    $line = $bits -join " "
    if ("" + $Merge.subject -ne "") { $line += ": " + $Merge.subject }
    return $line
}

function New-HordeNightlyReport {
    # The body of the tell to M, one repo or many: -Repos is a list of
    #   { repo; tip; lastTip; merges (list); guards = { state; text }; suiteCount; unrunCount; compare; culprits; notes; incomplete;
    #     pending (optional: findings of earlier nights whose tell failed) }
    # where culprits is a list of { unit; state; sha; merge; runs; between }. Returns the text, every line sanitized.
    # -Memory (optional): { giveUps; minFreeGB; minCommitGB; holders = [{ name; count; gb }] } - when a gate gave up
    # waiting for memory, one line says how often and names the top 3 holders of the last give-up.
    # -AppLines (optional): the lines of the night's app closer (tools/nightly/AppCloser.ps1), CLOSED first.
    param([string]$Date, [object[]]$Repos, $Memory = $null, [string[]]$AppLines = @())
    $lines = @()
    $newly = 0; foreach ($r in @($Repos)) { $newly += @($r.compare.newlyRed).Count }
    $lines += ("Nightly net " + $Date + ": " + $newly + " newly red across " + @($Repos).Count + " repos. " + (Get-HordeNightlyHeadlineStatus -Repos $Repos))
    foreach ($a in @($AppLines)) { if ("" + $a -ne "") { $lines += ("" + $a) } }
    if ($null -ne $Memory -and [int]$Memory.giveUps -gt 0) {
        $inv = [System.Globalization.CultureInfo]::InvariantCulture
        $who = @(@($Memory.holders) | Select-Object -First 3 | ForEach-Object { $_.name + " " + $_.count + " processes " + ([double]$_.gb).ToString("0.0", $inv) + " GB" })
        $lines += ("MEMORY: " + $Memory.giveUps + " slot waits gave up on memory (floor " + $Memory.minFreeGB + " GB free, " + $Memory.minCommitGB + " GB commit headroom). Held by: " + $(if ($who.Count -gt 0) { $who -join ", " } else { "not listed" }) + ".")
    }
    foreach ($r in @($Repos)) {
        $lines += ""
        $tipShort = Format-HordeNightlySha $r.tip
        $lastShort = $(if ("" + $r.lastTip -eq "") { "none (first run)" } else { (Format-HordeNightlySha $r.lastTip) })
        $lines += ("REPO " + $r.repo + ": tip " + $tipShort + ", last night " + $lastShort + ", " + @($r.merges).Count + " merges in between.")
        if ($r.incomplete) { $lines += ("  INCOMPLETE: " + $r.incomplete) }
        $lines += ("  guards: " + $r.guards.state + $(if ("" + $r.guards.text -ne "") { " - " + $r.guards.text } else { "" }))
        $lines += ("  units run: " + $r.suiteCount + ", not run (slot, memory or night ran out): " + $r.unrunCount)
        $c = $r.compare
        # SKIPPED units, one line per reason (the same need skips the same suite in both shells): -Repos rows may carry
        # skipReasons, unit -> why; a unit compared as skipped with no reason given is still listed.
        $sk = @(); if ($c.PSObject.Properties["skipped"]) { $sk = @($c.skipped) }
        if ($sk.Count -gt 0) {
            $why = @{}; if ($r.PSObject.Properties["skipReasons"] -and $null -ne $r.skipReasons) { $why = $r.skipReasons }
            $lines += ("  skipped (the night lacks what they need, not run, never green): " + $sk.Count)
            $groups = [ordered]@{}
            foreach ($u in $sk) {
                $w = $(if ($why.ContainsKey($u) -and "" + $why[$u] -ne "") { "" + $why[$u] } else { "no reason recorded" })
                if (-not $groups.Contains($w)) { $groups[$w] = @() }
                $groups[$w] += $u
            }
            foreach ($w in @($groups.Keys)) { $lines += ("  SKIPPED " + (@($groups[$w]) -join ", ") + " - " + $w) }
        }
        $lines += ("  newly red (green last night): " + @($c.newlyRed).Count + ", still red: " + @($c.stillRed).Count + ", red with no verdict last night: " + @($c.newRed).Count + ", fixed: " + @($c.fixed).Count)
        foreach ($f in @(Get-HordeNightlyFindingLines -Row $r)) { $lines += ("  " + $f) }
        foreach ($u in @($c.stillRed | Select-Object -First 15)) { $lines += ("  still red: " + $u) }
        if (@($c.stillRed).Count -gt 15) { $lines += ("  still red: and " + (@($c.stillRed).Count - 15) + " more") }
        if ($r.PSObject.Properties["pending"]) { foreach ($p in @($r.pending)) { if ("" + $p -ne "") { $lines += ("  NOT TOLD BEFORE (that night's tell failed): " + $p) } } }
        foreach ($n in @($r.notes)) { $lines += ("  note: " + $n) }
    }
    return ((@($lines | ForEach-Object { ConvertTo-HordeNightlyText $_ })) -join "`n")
}

# ---------------------------------------------------------------------------------------------------------------
# T-0397: THE MISSED-RUN WATCHER (tools/nightly/NightlyWatch.ps1). A separate checker, run once each morning by its
# own scheduled task, that judges the night that began yesterday at 22:00 by the evidence the nightly net left on
# disk, and raises it so a person hears when the night did not run. The net's own refused-start tell (PR 420) lives
# inside the net, so it cannot catch a task that never fired, a disabled or deleted task, a PC that was off, a run
# killed midway or a tell that failed. Everything impure (clock, files, the task XML, the senders) is injected.
# THE WATCHER NEVER SAYS A RUN WAS RIGHT: only whether it happened and was reported.
# ---------------------------------------------------------------------------------------------------------------

function Get-HordeNightlyWatchNight {
    # The night to judge at -Now: the one that began yesterday at 22:00 LOCAL, by the calendar (a clock-change day is 23
    # or 25 hours long, so the date is walked, never a count of hours). Before 06:30 that night is still running, so the
    # one before it is judged. { date (yyyy-MM-dd); start; end }.
    param([datetime]$Now, [int]$EndHour = 6, [int]$EndMinute = 30)
    $night = $Now.Date.AddDays(-1)
    if ($Now -lt $Now.Date.AddHours($EndHour).AddMinutes($EndMinute)) { $night = $night.AddDays(-1) }
    return [pscustomobject]@{
        date  = $night.ToString("yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
        start = $night.AddHours(22)
        end   = $night.AddDays(1).AddHours($EndHour).AddMinutes($EndMinute)
    }
}

function Get-HordeNightlyWatchDates {
    # -Count dates (yyyy-MM-dd), newest first, starting at -Date and walking back by the calendar.
    param([string]$Date, [int]$Count = 14)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $d = [datetime]::ParseExact($Date, "yyyy-MM-dd", $inv)
    $out = @()
    for ($i = 0; $i -lt $Count; $i++) { $out += $d.AddDays(-$i).ToString("yyyy-MM-dd", $inv) }
    return @($out)
}

function Get-HordeNightlyWatchTaskFindings {
    # What is wrong with the scheduled task, from its XML (as schtasks /Query /XML or Export-ScheduledTask gives it).
    # An empty -TaskXml means the task could not be read: missing. Findings count even on a night that ran, because the
    # next night is what they threaten: a disabled task, a trigger that is off, no trigger, or a StartBoundary that
    # carries an offset or a Z (it pins one UTC instant, so the start moves an hour at every clock change: 11-01 to 11-03).
    param([string]$TaskXml = "")
    if ("" + $TaskXml -eq "") { return @("the scheduled task is missing or could not be read") }
    $doc = New-Object System.Xml.XmlDocument
    try { $doc.LoadXml($TaskXml) } catch { return @("the scheduled task definition could not be parsed") }
    $found = @()
    $enabled = $doc.SelectSingleNode("//*[local-name()='Settings']/*[local-name()='Enabled']")
    if ($null -ne $enabled -and $enabled.InnerText.Trim() -ieq "false") { $found += "the scheduled task is disabled" }
    $triggers = @($doc.SelectNodes("//*[local-name()='Triggers']/*"))
    if ($triggers.Count -eq 0) { $found += "the scheduled task has no trigger" }
    foreach ($t in $triggers) {
        $te = $t.SelectSingleNode("*[local-name()='Enabled']")
        if ($null -ne $te -and $te.InnerText.Trim() -ieq "false") { $found += "a trigger of the scheduled task is disabled" }
        $sb = $t.SelectSingleNode("*[local-name()='StartBoundary']")
        if ($null -ne $sb -and $sb.InnerText.Trim() -match '(Z|[+-]\d\d:?\d\d)$') { $found += ("a trigger StartBoundary carries an offset (" + $sb.InnerText.Trim() + "), so the start moves at a clock change") }
    }
    return @($found | ForEach-Object { ConvertTo-HordeNightlyText $_ })
}

function Get-HordeNightlyWatchVerdict {
    # What happened to the night -Date, from the evidence only. -LogText is nightly.log, -ReportNames the file names in the
    # reports folder, -ReportText the night's report (for the headline), -PendingCount the findings M was not told
    # (state.json pending, summed over repos), -FolderMissing that the work folder is not there at all.
    # { date; status; missed; detail; incomplete; incompleteWhy }. status is one of RAN, NOT STARTED, REFUSED, FAILED,
    # BUSY, NOT REPORTED, NOT TOLD; every one but RAN is MISSED. A night that RAN but headlines INCOMPLETE is not missed.
    param([string]$Date, [string]$LogText = "", [string[]]$ReportNames = @(), [string]$ReportText = "", [int]$PendingCount = 0, [bool]$FolderMissing = $false)
    $names = @($ReportNames | ForEach-Object { ("" + $_).ToLowerInvariant() })
    $header = '\bnightly net (\d{4}-\d\d-\d\d): window (open|CLOSED)'
    $lines = @(("" + $LogText) -split "`r?`n")
    $openAt = -1; $closed = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $m = [regex]::Match($lines[$i], $header)
        if (-not $m.Success -or $m.Groups[1].Value -cne $Date) { continue }
        if ($m.Groups[2].Value -ceq "open") { $openAt = $i } else { $closed = $true }
    }
    # The run's own lines: from its window line to the next window line.
    $segment = @()
    if ($openAt -ge 0) {
        for ($i = $openAt + 1; $i -lt $lines.Count; $i++) {
            if ([regex]::IsMatch($lines[$i], $header)) { break }
            $segment += $lines[$i]
        }
    }
    $sent = (@($segment | Where-Object { $_ -match 'report sent to ' }).Count -gt 0)
    $tellFailed = (@($segment | Where-Object { $_ -match 'the tell to .* (failed with exit|is unconfirmed|ran past)|is not on the PATH|the report was not told' }).Count -gt 0)
    $haveReport = ($names -contains ($Date + ".txt"))
    $haveFailed = ($names -contains ($Date + "-failed.txt"))
    $haveBusy = ($names -contains ($Date + "-busy.txt"))
    $haveRefused = ($names -contains ($Date + "-refused.txt"))
    $status = ""; $detail = ""
    if ($haveReport) {
        if ($sent) { $status = "RAN"; $detail = "the net started, wrote its report and the log shows it was sent to M" }
        else {
            $status = "NOT TOLD"
            $why = @()
            if ($tellFailed) { $why += "the log shows the tell failed" }
            if ($PendingCount -gt 0) { $why += ("" + $PendingCount + " findings are still pending in state.json") }
            if ($why.Count -eq 0) { $why += "the log has no report sent line" }
            $detail = "the net wrote its report but M was not told: " + ($why -join ", ")
        }
    }
    elseif ($haveFailed) { $status = "FAILED"; $detail = "the net started and failed: a FAILED report is in the report folder, and there is no report" }
    elseif ($haveBusy) { $status = "BUSY"; $detail = "the net found another run holding its lock and ran nothing (a run from an earlier night may be wedged)" }
    elseif ($openAt -ge 0) { $status = "NOT REPORTED"; $detail = "the net started (the log shows the window open) but there is no report: it was killed or crashed midway, or the PC was switched off" }
    elseif ($closed -or $haveRefused) { $status = "REFUSED"; $detail = "the net was started outside its 22:00 to 06:30 window (the log shows the window CLOSED) and ran nothing" }
    else {
        $status = "NOT STARTED"
        $detail = "nightly.log has no line for this night with the window open: the task did not fire, or the PC was off"
        if ($FolderMissing) { $detail += " (the work folder does not exist)" }
        elseif ("" + $LogText -eq "" -and $names.Count -eq 0) { $detail += " (the work folder holds no log and no report)" }
    }
    $inc = $false; $incWhy = ""
    if ($status -ceq "RAN") {
        $head = (("" + $ReportText) -split "`r?`n")[0]
        $im = [regex]::Match($head, 'INCOMPLETE:.*?(?:\.(?:\s|$)|$)')
        if ($im.Success) { $inc = $true; $incWhy = ConvertTo-HordeNightlyText $im.Value.Trim() }
    }
    return [pscustomobject]@{ date = $Date; status = $status; missed = ($status -cne "RAN"); detail = (ConvertTo-HordeNightlyText $detail); incomplete = $inc; incompleteWhy = $incWhy }
}

function Get-HordeNightlyWatchStreak {
    # How many nights in a row, newest first, were missed: the count of leading verdicts that are missed.
    param([object[]]$Verdicts = @())
    $n = 0
    foreach ($v in @($Verdicts)) { if (-not $v.missed) { break }; $n++ }
    return $n
}

function Read-HordeNightlyWatchState {
    # The watcher's own memory from its file text: { problem; signature; delivered; streak; noteDate }. Missing, empty or
    # corrupt text is the empty state, never an error and never a reason to stay quiet (a lost memory means one more
    # alarm, not none).
    param([string]$Text = "")
    $s = @{ problem = $false; signature = ""; delivered = $false; streak = 0; noteDate = "" }
    if ("" + $Text -eq "") { return $s }
    try {
        $o = ConvertFrom-HordeJson $Text
        if ($o.PSObject.Properties["problem"]) { $s.problem = [bool]$o.problem }
        if ($o.PSObject.Properties["signature"]) { $s.signature = "" + $o.signature }
        if ($o.PSObject.Properties["delivered"]) { $s.delivered = [bool]$o.delivered }
        if ($o.PSObject.Properties["streak"]) { $s.streak = [int]$o.streak }
        if ($o.PSObject.Properties["noteDate"]) { $s.noteDate = "" + $o.noteDate }
    } catch { return @{ problem = $false; signature = ""; delivered = $false; streak = 0; noteDate = "" } }
    return $s
}

function Get-HordeNightlyWatchDecision {
    # What this morning does. kind: "alarm" (a missed night or a task finding: a person must hear), "recovered" (it was
    # broken and now ran: said once), "note" (RAN but INCOMPLETE: M only, not a miss), "duplicate" (the same alarm,
    # note or recovery already got through this morning: not sent again) or "quiet". The signature holds the date and the
    # streak, so a still-broken night alarms again each morning, and the same morning only once.
    param($Verdict, [int]$Streak = 0, [string[]]$TaskFindings = @(), $State = $null)
    if ($null -eq $State) { $State = Read-HordeNightlyWatchState }
    $findings = @($TaskFindings | Where-Object { "" + $_ -ne "" })
    $problem = ($Verdict.missed -or $findings.Count -gt 0)
    $sig = ""; $kind = "quiet"
    if ($problem) {
        $sig = "alarm|" + $Verdict.date + "|" + $Verdict.status + "|" + $Streak + "|" + ($findings -join "/")
        $kind = "alarm"
    }
    elseif ($State.problem) { $sig = "recovered|" + $Verdict.date; $kind = "recovered" }
    elseif ($Verdict.incomplete) { $sig = "note|" + $Verdict.date; $kind = "note" }
    if ($kind -cne "quiet" -and $State.signature -ceq $sig -and $State.delivered) { $kind = "duplicate" }
    return [pscustomobject]@{ kind = $kind; signature = $sig; problem = $problem; streak = $Streak; taskFindings = @($findings) }
}

function Update-HordeNightlyWatchState {
    # The state to save after a morning: -Delivered is whether any channel got the message through. An alarm that got
    # through stays remembered (the same morning does not repeat it); one that did not is sent again at the next run. A
    # recovery that did not get through keeps the problem flag, so the next morning says it. Quiet and duplicate change nothing.
    param($Decision, $Verdict, $State, [bool]$Delivered = $false)
    $s = @{ problem = [bool]$State.problem; signature = "" + $State.signature; delivered = [bool]$State.delivered; streak = [int]$State.streak; noteDate = "" + $State.noteDate }
    if ($Decision.kind -ceq "alarm") { $s.problem = $true; $s.signature = $Decision.signature; $s.delivered = $Delivered; $s.streak = [int]$Decision.streak }
    elseif ($Decision.kind -ceq "recovered") {
        $s.signature = $Decision.signature; $s.delivered = $Delivered
        if ($Delivered) { $s.problem = $false; $s.streak = 0 }
    }
    elseif ($Decision.kind -ceq "note") { $s.signature = $Decision.signature; $s.delivered = $Delivered; $s.noteDate = $Verdict.date }
    return $s
}

function Format-HordeNightlyWatchMessage {
    # The two texts of a morning: .m for M (several lines) and .founder for the phone (one plain line, "" when the
    # founder is not told: a note, or nothing). -Prior is the streak that was broken, said in a recovery. -Lookback is how
    # far back nights were counted. Every line is ASCII with no double quote, semicolon or angle bracket.
    param($Decision, $Verdict, [int]$Prior = 0, [int]$Lookback = 14, [string]$Evidence = "")
    $lines = @(); $phone = ""
    $date = $Verdict.date
    $row = ""
    if ($Decision.streak -gt 1) { $row = "That is " + $Decision.streak + " nights in a row" + $(if ($Decision.streak -ge $Lookback) { " or more (counted back " + $Lookback + " nights)" } else { "" }) + "." }
    $tasks = @($Decision.taskFindings)
    if ($Decision.kind -ceq "alarm") {
        if ($Verdict.missed) {
            $lines += ("NIGHTLY WATCH " + $date + ": MISSED, " + $Verdict.status + ". " + $Verdict.detail + ".")
            if ($row -ne "") { $lines += $row }
            # What really happened differs by status (T-0397): NOT TOLD ran and only the report failed, NOT REPORTED and
            # FAILED started, so "did not run" would be false for those three.
            $said = switch ($Verdict.status) {
                "NOT TOLD" { "Nightly tests ran on the night of " + $date + ", but the report did not reach M." }
                "NOT REPORTED" { "Nightly tests started on the night of " + $date + " but did not finish." }
                "FAILED" { "Nightly tests started on the night of " + $date + " but failed." }
                "REFUSED" { "Nightly tests did not run for the night of " + $date + ": they were started outside their allowed hours." }
                "BUSY" { "Nightly tests did not run for the night of " + $date + ": an earlier run was still in the way." }
                default { "Nightly tests did not run for the night of " + $date + "." }
            }
            $phone = $said + $(if ($row -ne "") { " " + $row } else { "" })
            if ($tasks.Count -gt 0) { $phone += " The task also looks wrong: " + $tasks[0] + "." }
        } else {
            $lines += ("NIGHTLY WATCH " + $date + ": the night ran, but the scheduled task looks wrong.")
            $phone = "The nightly tests ran for " + $date + ", but their scheduled task looks wrong: " + $tasks[0] + "."
        }
        $phone += " Details are with M."
        foreach ($f in $tasks) { $lines += ("TASK: " + $f + ".") }
    }
    elseif ($Decision.kind -ceq "recovered") {
        $lines += ("NIGHTLY WATCH " + $date + ": RECOVERED, the night ran and its report was sent" + $(if ($Prior -gt 0) { " (it had missed " + $Prior + " nights in a row)" } else { "" }) + ".")
        $phone = "The nightly tests ran again for " + $date + $(if ($Prior -gt 0) { " after " + $Prior + " missed nights" } else { "" }) + "."
    }
    elseif ($Decision.kind -ceq "note") { $lines += ("NIGHTLY WATCH " + $date + ": the night ran.") }
    if ($Verdict.incomplete -and $Decision.kind -cne "duplicate" -and $Decision.kind -cne "quiet") { $lines += ("NOTE for M only, not a miss: the night ran but was headed " + $Verdict.incompleteWhy) }
    $lines += "The watcher only says whether a run happened and was reported. It does not say the run was right."
    if ($Evidence -ne "") { $lines += ("Evidence: " + $Evidence) }
    $m = (@($lines | ForEach-Object { ConvertTo-HordeNightlyText $_ }) -join "`n")
    $p = ConvertTo-HordeNightlyText $phone
    if ($p.Length -gt 260) { $p = $p.Substring(0, 257) + "..." }
    return [pscustomobject]@{ m = $m; founder = $p }
}

function Invoke-HordeNightlyWatchSend {
    # Run every channel, one after the other, whatever the earlier ones did: a channel is { name; send } where send is a
    # scriptblock taking the results so far (an ordered table name -> $true or $false) and returning $true when it got
    # through. A throw is a failure. { results; attempted; ok; allFailed } - allFailed only when something was
    # attempted and nothing got through.
    param([object[]]$Channels = @(), [scriptblock]$Say = { param($l) })
    $results = [ordered]@{}
    foreach ($ch in @($Channels)) {
        $ok = $false
        try { $ok = ((& $ch.send $results) -eq $true) } catch { & $Say ("channel " + $ch.name + " threw: " + $_.Exception.Message) }
        $results[$ch.name] = $ok
        & $Say ("channel " + $ch.name + ": " + $(if ($ok) { "sent" } else { "NOT sent" }))
    }
    $okCount = @($results.Values | Where-Object { $_ -eq $true }).Count
    return [pscustomobject]@{ results = $results; attempted = $results.Count; ok = $okCount; allFailed = ($results.Count -gt 0 -and $okCount -eq 0) }
}
