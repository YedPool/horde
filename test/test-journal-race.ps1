# DO RACING PROCESSES, SENDING THE SAME REQUEST AT THE SAME MOMENT, ACT EXACTLY ONCE?
#
# Remote plan step R3: "two racing writers, one act". The race is real: separate powershell.exe
# processes (test/fixtures/journal/race-worker.ps1) call Open-HordeJournalEntry for the same ids on
# the same wall-clock ticks, and every one that is told "act" leaves an effect file. The suite counts
# effect files, not the journal's own claims: two for one id is a double execution, whatever the
# journal says.
#
# A RACE THAT NEVER COLLIDES PROVES NOTHING, so two controls run the same harness:
#   - CONTENTION: the suite counts the ids where a racer arrived while another's attempt was still in
#     flight (told "being recorded" or "no outcome recorded"). Those answers exist only when two
#     attempts overlap, so a high count shows the racers met rather than took turns.
#   - A BROKEN JOURNAL: the same race against a copy of remote/Journal.ps1 whose create-if-new is
#     replaced by create-or-overwrite. The harness must see double executions there, or it could not
#     have seen them here.
#
# Memory: the machine this was written on had about 700 MB free (2026-09-30), so the race uses 4
# processes, not more.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "remote\Journal.ps1")

$racers = 4
$idCount = 200
$tickMs = 40
$journalSrc = Join-Path $root "remote\Journal.ps1"
$worker = Join-Path $root "test\fixtures\journal\race-worker.ps1"
$script:work = Join-Path $env:TEMP ("horde-journal-race-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null

function Invoke-Race {
    # Run one race against the journal file at -Journal. Returns { ok; problems; perId; decisions }.
    param([string]$Name, [string]$Journal)
    $dir = Join-Path $script:work $Name
    $jroot = Join-Path $dir "journal"
    $eff = Join-Path $dir "effects"
    New-Item -ItemType Directory -Path $jroot, $eff | Out-Null
    Initialize-HordeJournal -Root $jroot -Kind "request" | Out-Null
    $idsFile = Join-Path $dir "ids.txt"
    $ids = @(1..$idCount | ForEach-Object { [guid]::NewGuid().ToString() })
    [System.IO.File]::WriteAllLines($idsFile, [string[]]$ids)
    $go = Join-Path $dir "go.txt"
    $procs = New-Object System.Collections.ArrayList
    $problems = New-Object System.Collections.ArrayList
    try {
        for ($r = 0; $r -lt $racers; $r++) {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "powershell.exe"
            $psi.Arguments = ("-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"" + $worker + "`" -JournalPath `"" + $Journal +
                "`" -Root `"" + $jroot + "`" -IdsFile `"" + $idsFile + "`" -EffectsDir `"" + $eff + "`" -GoFile `"" + $go +
                "`" -ReadyFile `"" + (Join-Path $dir ("ready-" + $r)) + "`" -LogFile `"" + (Join-Path $dir ("log-" + $r + ".txt")) +
                "`" -Racer " + $r + " -TickMs " + $tickMs)
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.CreateNoWindow = $true
            $p = [System.Diagnostics.Process]::Start($psi)
            [void]$procs.Add([pscustomobject]@{ p = $p; out = $p.StandardOutput.ReadToEndAsync(); err = $p.StandardError.ReadToEndAsync() })
        }
        # Every racer has loaded the journal and read its ids before the clock starts, so process
        # start-up time (seconds, under memory pressure) is not part of the race.
        $deadline = (Get-Date).AddSeconds(120)
        while (@(0..($racers - 1) | Where-Object { -not (Test-Path -LiteralPath (Join-Path $dir ("ready-" + $_))) }).Count -gt 0) {
            if ((Get-Date) -gt $deadline) { [void]$problems.Add("not every racer was ready within 120 s"); break }
            if (@($procs | Where-Object { $_.p.HasExited }).Count -gt 0) { [void]$problems.Add("a racer exited before it was ready"); break }
            Start-Sleep -Milliseconds 50
        }
        # Written under another name and then renamed: a racer that saw the go file while it was
        # still being written failed to read it ("being used by another process", measured
        # 2026-09-30). A rename within one folder is atomic, so the file appears complete.
        [System.IO.File]::WriteAllText(($go + ".tmp"), ([datetime]::UtcNow.AddMilliseconds(500).Ticks).ToString())
        [System.IO.File]::Move(($go + ".tmp"), $go)
        foreach ($x in $procs) {
            if (-not $x.p.WaitForExit(180000)) { [void]$problems.Add("a racer ran past 180 s") ; continue }
            $x.p.WaitForExit()
            if ($x.p.ExitCode -ne 0) { [void]$problems.Add("a racer exited " + $x.p.ExitCode + ": " + $x.err.Result) }
        }
    } finally {
        foreach ($x in $procs) { if (-not $x.p.HasExited) { try { $x.p.Kill() } catch { } }; $x.p.Dispose() }
    }
    $perId = @{}
    foreach ($id in $ids) { $perId[$id] = 0 }
    foreach ($f in @(Get-ChildItem -LiteralPath $eff -File)) {
        $idPart = $f.Name.Substring(0, $f.Name.LastIndexOf("."))
        if ($perId.ContainsKey($idPart)) { $perId[$idPart]++ } else { [void]$problems.Add("an effect for an id the race did not send: " + $f.Name) }
    }
    $decisions = New-Object System.Collections.ArrayList
    for ($r = 0; $r -lt $racers; $r++) {
        $lf = Join-Path $dir ("log-" + $r + ".txt")
        if (-not (Test-Path -LiteralPath $lf)) { [void]$problems.Add("racer " + $r + " left no log"); continue }
        foreach ($line in [System.IO.File]::ReadAllLines($lf)) {
            $parts = $line.Split(" ", 3)
            [void]$decisions.Add([pscustomobject]@{ racer = $r; index = [int]$parts[0]; decision = $parts[1]; reason = $(if ($parts.Count -gt 2) { $parts[2] } else { "" }) })
        }
    }
    return [pscustomobject]@{ problems = @($problems); perId = $perId; decisions = @($decisions); ids = $ids; root = $jroot }
}

function Show-Race {
    param($Race, [string]$Label)
    $d = @($Race.decisions)
    $acts = @($d | Where-Object { $_.decision -ceq "act" }).Count
    $replays = @($d | Where-Object { $_.decision -ceq "replay" }).Count
    $unknowns = @($d | Where-Object { $_.decision -ceq "unknown" }).Count
    $refuses = @($d | Where-Object { $_.decision -ceq "refuse" }).Count
    $doubles = @($Race.perId.Keys | Where-Object { $Race.perId[$_] -gt 1 }).Count
    Write-Host ("  " + $Label + ": " + $d.Count + " calls, act " + $acts + ", replay " + $replays + ", unknown " + $unknowns + ", refuse " + $refuses + "; ids executed twice or more: " + $doubles) -ForegroundColor DarkGray
}

try {

Write-Host ""
Write-Host ("--- " + $racers + " processes race for " + $idCount + " ids, one tick each ---") -ForegroundColor Cyan

$race = Invoke-Race -Name "real" -Journal $journalSrc
Show-Race $race "real journal"
Check (@($race.problems).Count -eq 0) "every racer started, ran and exited cleanly"
foreach ($pr in @($race.problems)) { Write-Host ("         " + $pr) -ForegroundColor Red }
Check (@($race.decisions | Where-Object { $_.decision -cne "complete-failed" }).Count -eq $racers * $idCount) "every racer answered every id"
Check (@($race.decisions | Where-Object { $_.decision -ceq "complete-failed" }).Count -eq 0) "every act recorded its outcome"
$doubled = @($race.ids | Where-Object { $race.perId[$_] -gt 1 })
$never = @($race.ids | Where-Object { $race.perId[$_] -eq 0 })
Check ($doubled.Count -eq 0) "no id was executed twice (effect files counted, not the journal's word)"
Check ($never.Count -eq 0) "every id was executed once: 'unknown' never swallowed the only attempt"
Check (@($race.decisions | Where-Object { $_.decision -ceq "act" }).Count -eq $idCount) "exactly one 'act' per id across all racers"
Check (@($race.decisions | Where-Object { $_.decision -ceq "refuse" }).Count -eq 0) "no racer was refused: the same id with the same arguments is never 'reused'"
$allDone = $true
foreach ($id in $race.ids) {
    $e = Get-HordeJournalEntry -Root $race.root -Id $id
    if ($e.state -cne "known" -or "$((Get-HordeValue $e).state)" -cne "done") { $allDone = $false }
}
Check ($allDone) "every id ends with its outcome recorded as done"

# CONTENTION. An 'unknown' in this race means a racer found another's attempt in flight: the record
# was being written, or was written with no outcome yet. Replays are the racers that came after.
$metIdx = @{}
foreach ($dd in @($race.decisions | Where-Object { $_.decision -ceq "unknown" })) { $metIdx[$dd.index] = $true }
$contended = @($metIdx.Keys)
Write-Host ("  ids where a racer met another's attempt in flight: " + $contended.Count + " of " + $idCount) -ForegroundColor DarkGray
$busyReasons = @($race.decisions | Where-Object { $_.decision -ceq "unknown" -and $_.reason -like "*being recorded*" }).Count
Write-Host ("  of those answers, 'being recorded' (the record itself was mid-write, held by its writer): " + $busyReasons) -ForegroundColor DarkGray
# How much the racers overlap depends on the machine's load, so no share of ids is required.
# Measured 2026-09-30: with an instant act, seven runs of 150 ids met an attempt in flight on 53,
# 39, 52, 30, 29, 20 and 2 ids; with the worker's 20 ms act, five runs of 200 ids met in flight on
# 191, 200, 195, 197 and 89 (the last in a fresh-clone gate, with other work on the machine), and found a
# record still being written 11, 4, 21, 14 and 26 times. A write-through of a few hundred bytes
# takes milliseconds, so ONE record found mid-write already means two processes were inside the
# same create at once, and that is what is required. The check-then-create mutant in
# test/mutations/journal-race.psd1 is caught as well, which needs the same overlap.
Check ($contended.Count -ge 1) "CONTROL: racers met another's attempt in flight (counts above)"
Check ($busyReasons -ge 1) "CONTROL: at least one racer found a record still being written, so racers met inside the create itself"

Write-Host ""
Write-Host "--- CONTROL: the same race against a journal that overwrites instead of creating new ---" -ForegroundColor Cyan

$src = [System.IO.File]::ReadAllText($journalSrc)
$find = '[System.IO.FileMode]::CreateNew'
$n = ([regex]::Matches($src, [regex]::Escape($find))).Count
Check ($n -eq 1) "the control's edit matches exactly once in remote/Journal.ps1"
$brokenPath = Join-Path $script:work "Journal-overwrites.ps1"
[System.IO.File]::WriteAllText($brokenPath, $src.Replace($find, '[System.IO.FileMode]::Create'))
# The copy dot-sources core/Tristate.ps1 by a path relative to itself, so it needs one beside it.
New-Item -ItemType Directory -Path (Join-Path $script:work "core") | Out-Null
Copy-Item -LiteralPath (Join-Path $root "core\Tristate.ps1") -Destination (Join-Path $script:work "core\Tristate.ps1")
$brokenDir = Join-Path $script:work "remote"
New-Item -ItemType Directory -Path $brokenDir | Out-Null
Move-Item -LiteralPath $brokenPath -Destination (Join-Path $brokenDir "Journal.ps1")
$bad = Invoke-Race -Name "broken" -Journal (Join-Path $brokenDir "Journal.ps1")
Show-Race $bad "overwriting journal"
Check (@($bad.problems).Count -eq 0) "the control's racers ran cleanly too"
foreach ($pr in @($bad.problems)) { Write-Host ("         " + $pr) -ForegroundColor Red }
$badDoubled = @($bad.ids | Where-Object { $bad.perId[$_] -gt 1 })
Write-Host ("  ids executed twice or more under the broken journal: " + $badDoubled.Count) -ForegroundColor DarkGray
Check ($badDoubled.Count -gt 0) "CONTROL: the harness sees double executions when the journal allows them"

} finally {
    if (Test-Path -LiteralPath $script:work) { Remove-Item -LiteralPath $script:work -Recurse -Force }
}
Check (-not (Test-Path -LiteralPath $script:work)) "the race's temp folder is removed"

Complete-HordeSuite -Success "racing processes act once per id, and the race can see a double execution"
