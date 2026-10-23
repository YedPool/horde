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

function Get-HordeNightlyDeadline {
    # The 06:30 this night ends at: the next one at or after Now (a Now before 06:30 means today's).
    param([datetime]$Now, [int]$EndHour = 6, [int]$EndMinute = 30)
    $today = $Now.Date.AddHours($EndHour).AddMinutes($EndMinute)
    if ($Now -lt $today) { return $today }
    return $today.AddDays(1)
}

function Test-HordeNightlyMayStartRun {
    # May a slot run of up to RunSeconds start now and still be over by the cutoff? A run is killed at its
    # own limit, so the worst case is Now plus RunSeconds.
    param([datetime]$Now, [datetime]$Cutoff, [int]$RunSeconds)
    return ($Now.AddSeconds($RunSeconds) -le $Cutoff)
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
    # Now against last night, per unit. -Now: unit -> "green" | "red" | "skip" | "unrun". -Last: unit -> "green" | "red" | ...
    # Answer: { newlyRed; stillRed; newRed; fixed; unrun } as sorted unit names. unrun (the slot was never had,
    # or the night ran out) says nothing either way and leaves the old verdict to stand.
    param($Now, $Last)
    $newly = @(); $still = @(); $new = @(); $fixed = @(); $unrun = @()
    foreach ($u in (@($Now.Keys) | Sort-Object)) {
        $v = "" + $Now[$u]
        $was = ""; if ($Last.ContainsKey($u)) { $was = "" + $Last[$u] }
        if ($v -ceq "unrun") { $unrun += $u; continue }
        if ($v -ceq "red") {
            if ($was -ceq "green") { $newly += $u } elseif ($was -ceq "red") { $still += $u } else { $new += $u }
        } elseif ($v -ceq "green" -and $was -ceq "red") { $fixed += $u }
    }
    return [pscustomobject]@{ newlyRed = @($newly); stillRed = @($still); newRed = @($new); fixed = @($fixed); unrun = @($unrun) }
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
    #   { repo; tip; lastTip; merges (list); guards = { state; text }; suiteCount; unrunCount; compare; culprits; notes; incomplete }
    # where culprits is a list of { unit; state; sha; merge; runs; between }. Returns the text, every line sanitized.
    param([string]$Date, [object[]]$Repos)
    $lines = @()
    $reds = 0
    foreach ($r in @($Repos)) { $reds += @($r.compare.newlyRed).Count + @($r.compare.newRed).Count + @($r.compare.stillRed).Count }
    $newly = 0; foreach ($r in @($Repos)) { $newly += @($r.compare.newlyRed).Count }
    $lines += ("Nightly net " + $Date + ": " + $newly + " newly red across " + @($Repos).Count + " repos.")
    foreach ($r in @($Repos)) {
        $lines += ""
        $tipShort = Format-HordeNightlySha $r.tip
        $lastShort = $(if ("" + $r.lastTip -eq "") { "none (first run)" } else { (Format-HordeNightlySha $r.lastTip) })
        $lines += ("REPO " + $r.repo + ": tip " + $tipShort + ", last night " + $lastShort + ", " + @($r.merges).Count + " merges in between.")
        if ($r.incomplete) { $lines += ("  INCOMPLETE: " + $r.incomplete) }
        $lines += ("  guards: " + $r.guards.state + $(if ("" + $r.guards.text -ne "") { " - " + $r.guards.text } else { "" }))
        $lines += ("  units run: " + $r.suiteCount + ", not run (slot, memory or night ran out): " + $r.unrunCount)
        $c = $r.compare
        $lines += ("  newly red (green last night): " + @($c.newlyRed).Count + ", still red: " + @($c.stillRed).Count + ", red with no verdict last night: " + @($c.newRed).Count + ", fixed: " + @($c.fixed).Count)
        foreach ($k in @($r.culprits)) {
            if ($k.state -ceq "found") { $lines += ("  RED " + $k.unit + " first red at merge " + (Format-HordeNightlyMerge -Merge $k.merge) + " (" + $k.runs + " runs)") }
            elseif ($k.state -ceq "flaky") { $lines += ("  RED " + $k.unit + " was not red when run again at the tip: flaky, no merge named") }
            elseif ($k.state -ceq "capped") { $lines += ("  RED " + $k.unit + " not bisected to one merge (run cap): after " + $(if ("" + $k.between[0] -eq "") { "last night" } else { (Format-HordeNightlySha $k.between[0]) }) + " up to " + (Format-HordeNightlySha $k.between[1])) }
            elseif ($k.state -ceq "none") { $lines += ("  RED " + $k.unit + " has no merge since last night to name") }
            else { $lines += ("  RED " + $k.unit + " bisect inconclusive (a run did not happen): " + $k.state) }
        }
        foreach ($u in @($c.stillRed | Select-Object -First 15)) { $lines += ("  still red: " + $u) }
        if (@($c.stillRed).Count -gt 15) { $lines += ("  still red: and " + (@($c.stillRed).Count - 15) + " more") }
        foreach ($u in @($c.newRed | Select-Object -First 15)) { $lines += ("  red, no verdict last night: " + $u) }
        foreach ($n in @($r.notes)) { $lines += ("  note: " + $n) }
    }
    return ((@($lines | ForEach-Object { ConvertTo-HordeNightlyText $_ })) -join "`n")
}
