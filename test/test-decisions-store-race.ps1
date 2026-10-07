# CAN TWO PROCESSES BOTH TAKE ONE SEQUENCE NUMBER OF THE DECISIONS STORE, OR A WRITE LOSE ITS RECORD?
#
# The race is real: separate powershell.exe processes (test/fixtures/decisions/race-worker.ps1), all
# aimed at one store folder, acting on the same wall-clock ticks. Each writes down what it was TOLD.
# The suite then reads the store itself and compares. Two races, because there are two promises:
#   I.  THE STORE. Every racer asks decisions/Store.ps1 for the SAME sequence number on the SAME tick.
#       Exactly one may be told "created", and the record on disk must be that one's.
#   II. A WHOLE WRITE. Every racer adds questions of its own through decisions/Operations.ps1. Each
#       must be told a sequence number and a question number of its own, and every question a racer
#       was told is done must be in the store, under the number it was told.
# And a third thing only a real process can show:
#   III. A KILLED WRITER. A process that does nothing but write records is killed at a random moment,
#       again and again. No kill may leave a record that cannot be read.
#
# A RACE THAT NEVER COLLIDES PROVES NOTHING, so each race has its controls, as test/test-journal-race.ps1
# has:
#   - CONTENTION, measured: in I, sequence numbers that more than one racer asked for and all but one
#     was refused; in II, writes that say they took more than one try, which happens only when another
#     writer took the sequence number first.
#   - A BROKEN STORE: the same two races against a copy of the module whose move-without-replace is
#     replaced by a copy that overwrites. There the harness must see two racers told "created" for one
#     number, and a question told done and gone - or it could not have seen them here. For III, a copy
#     that writes the record under its own name, which a kill must be seen to damage.
#
# Every store is a fresh folder under %TEMP% that this suite made and removes (CONTRIBUTING 9). The
# machine this was written on was throttled and short of memory (2026-10-06), so each race is 4
# processes.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "decisions\Operations.ps1")

$racers = 4
$storeCount = 120      # sequence numbers raced for in I
$storeTickMs = 40
$perRacer = 8          # questions each racer adds in II
$addTickMs = 250
$total = $racers * $perRacer
# Kills in III. Measured 2026-10-06: with the record written under its own name about 1 kill in 3 left it
# empty, so 15 clean kills would be a 1-in-200 accident for that store; the control stops at the first
# damaged record and gives up after 40 kills (1 in a million at that rate).
$killRounds = 15
$killControlRounds = 40
$worker = Join-Path $root "test\fixtures\decisions\race-worker.ps1"
$defs = Get-HordeDecisionDefinitions
$script:work = Join-Path $env:TEMP ("horde-decisions-race-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null

function Invoke-Race {
    # Run one race. Returns { problems; lines; store }: lines is every racer's log, each line split
    # into its fields with the racer's number in front; store is the folder they wrote to.
    param([string]$Name, [string]$Mode, [string]$Code, [int]$Count, [int]$TickMs)
    $dir = Join-Path $script:work $Name
    New-Item -ItemType Directory -Path $dir | Out-Null
    $store = Join-Path $dir "home\store\decisions"
    $go = Join-Path $dir "go.txt"
    $procs = New-Object System.Collections.ArrayList
    $problems = New-Object System.Collections.ArrayList
    try {
        for ($r = 0; $r -lt $racers; $r++) {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "powershell.exe"
            $psi.Arguments = ("-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"" + $worker + "`" -Mode " + $Mode + " -CodePath `"" + $Code + "`" -Root `"" + $store +
                "`" -GoFile `"" + $go + "`" -ReadyFile `"" + (Join-Path $dir ("ready-" + $r)) + "`" -LogFile `"" + (Join-Path $dir ("log-" + $r + ".txt")) +
                "`" -Racer " + $r + " -Count " + $Count + " -TickMs " + $TickMs)
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.CreateNoWindow = $true
            # A racer must never find the real store, whatever it is handed: its home is the race's own.
            $psi.EnvironmentVariables["HORDE_HOME"] = (Join-Path $dir "home")
            $p = [System.Diagnostics.Process]::Start($psi)
            [void]$procs.Add([pscustomobject]@{ p = $p; out = $p.StandardOutput.ReadToEndAsync(); err = $p.StandardError.ReadToEndAsync() })
        }
        # Every racer has loaded its code before the clock starts, so process start-up (seconds, on a
        # loaded machine) is not part of the race.
        $deadline = (Get-Date).AddSeconds(240)
        while (@(0..($racers - 1) | Where-Object { -not (Test-Path -LiteralPath (Join-Path $dir ("ready-" + $_))) }).Count -gt 0) {
            if ((Get-Date) -gt $deadline) { [void]$problems.Add("not every racer was ready within 240 s"); break }
            if (@($procs | Where-Object { $_.p.HasExited }).Count -gt 0) { [void]$problems.Add("a racer exited before it was ready"); break }
            Start-Sleep -Milliseconds 50
        }
        # Written under another name and renamed, so no racer reads it half-written (test-journal-race).
        [System.IO.File]::WriteAllText(($go + ".tmp"), ([datetime]::UtcNow.AddMilliseconds(500).Ticks).ToString())
        [System.IO.File]::Move(($go + ".tmp"), $go)
        foreach ($x in $procs) {
            if (-not $x.p.WaitForExit(480000)) { [void]$problems.Add("a racer ran past 480 s without finishing"); continue }
            $x.p.WaitForExit()
            if ($x.p.ExitCode -ne 0) { [void]$problems.Add("a racer exited " + $x.p.ExitCode + ": " + $x.err.Result) }
        }
    } finally {
        # Only the processes this suite started, by the handles it holds.
        foreach ($x in $procs) { if (-not $x.p.HasExited) { try { $x.p.Kill() } catch { } }; $x.p.Dispose() }
    }
    $lines = New-Object System.Collections.ArrayList
    for ($r = 0; $r -lt $racers; $r++) {
        $lf = Join-Path $dir ("log-" + $r + ".txt")
        if (-not (Test-Path -LiteralPath $lf)) { [void]$problems.Add("racer " + $r + " left no log"); continue }
        foreach ($line in [System.IO.File]::ReadAllLines($lf)) { if ($line -cne "END") { [void]$lines.Add([pscustomobject]@{ racer = $r; parts = $line.Split("|") }) } }
    }
    return [pscustomobject]@{ problems = @($problems); lines = @($lines); store = $store }
}

function Get-StoreRaceFacts {
    # Race I: for every sequence number, who was told "created", and whose record is on disk.
    param($Race)
    $told = @($Race.lines | ForEach-Object { [pscustomobject]@{ racer = $_.racer; sequence = ([int]$_.parts[0] + 1); answer = $_.parts[1] } })
    $created = @($told | Where-Object { $_.answer -ceq "created" })
    $bySeq = @{}
    foreach ($c in $created) { if (-not $bySeq.ContainsKey($c.sequence)) { $bySeq[$c.sequence] = New-Object System.Collections.ArrayList }; [void]$bySeq[$c.sequence].Add($c.racer) }
    $loaded = Get-HordeDecisionRecords -Root $Race.store
    $wrongOwner = New-Object System.Collections.ArrayList
    foreach ($rec in @($loaded.records)) {
        $seq = [int]$rec.sequence
        if ($rec.kind -cne "ok" -or -not $bySeq.ContainsKey($seq) -or @($bySeq[$seq]) -notcontains [int]$rec.data.racer) { [void]$wrongOwner.Add($seq) }
    }
    return [pscustomobject]@{ told = $told; created = $created; loaded = $loaded
        twice = @($bySeq.Keys | Where-Object { $bySeq[$_].Count -gt 1 })
        never = @(1..$storeCount | Where-Object { -not $bySeq.ContainsKey($_) })
        wrongOwner = @($wrongOwner)
        threw = @($told | Where-Object { $_.answer -ceq "threw" })
        refused = @($told | Where-Object { $_.answer -ceq "exists" }) }
}

function Get-AddRaceFacts {
    # Race II: what the store holds, set against what the racers were told.
    param($Race)
    $told = @($Race.lines | ForEach-Object { [pscustomobject]@{ racer = $_.racer; index = [int]$_.parts[0]; state = $_.parts[1]; outcome = $_.parts[2]; number = [int]$_.parts[3]; sequence = [long]$_.parts[4]; attempts = [int]$_.parts[5]
        reason = $_.parts[6]; title = ("Does racer " + $_.racer + " keep its question " + $_.parts[0] + " in this race?") } })
    $done = @($told | Where-Object { $_.state -ceq "known" -and $_.outcome -ceq "done" })
    $loaded = Get-HordeDecisionRecords -Root $Race.store
    $list = ConvertTo-HordeDecisionState -Records $loaded.records -Definitions $defs
    $byTitle = @{}
    foreach ($q in $list.questions.Values) { $byTitle["$($q.title)"] = [int]$q.number }
    return [pscustomobject]@{ told = $told; done = $done; loaded = $loaded; list = $list
        # Told "done" and not in the store, or there under another number than it was told.
        lost = @($done | Where-Object { -not $byTitle.ContainsKey($_.title) -or $byTitle[$_.title] -ne $_.number })
        sharedSequence = @($done | Group-Object sequence | Where-Object { $_.Count -gt 1 })
        sharedNumber = @($done | Group-Object number | Where-Object { $_.Count -gt 1 })
        retries = [int](@($done | ForEach-Object { $_.attempts - 1 }) | Measure-Object -Sum).Sum }
}

function Invoke-KillRounds {
    # Start a writer that does nothing but write records (the worker's loop mode), kill it at a random
    # moment, and read what it left with the store's own reader; -Rounds times, each in a store of its
    # own. Returns { problems; rounds; records; damaged; leftovers; strays }. -StopAtDamage ends at the
    # first round that left a damaged record. Only the process this started is killed, by its handle.
    param([string]$Name, [string]$Code, [int]$Rounds, [switch]$StopAtDamage)
    $problems = New-Object System.Collections.ArrayList
    $rand = New-Object System.Random(20261006)
    $done = 0; $records = 0; $damaged = 0; $leftovers = 0; $strays = 0
    for ($k = 1; $k -le $Rounds; $k++) {
        $dir = Join-Path $script:work ($Name + "-" + $k)
        New-Item -ItemType Directory -Path $dir | Out-Null
        $store = Join-Path $dir "home\store\decisions"
        $ready = Join-Path $dir "ready"
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = ("-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"" + $worker + "`" -Mode loop -CodePath `"" + $Code + "`" -Root `"" + $store +
            "`" -GoFile `"" + (Join-Path $dir "go.txt") + "`" -ReadyFile `"" + $ready + "`" -LogFile `"" + (Join-Path $dir "log.txt") + "`" -Racer " + $k + " -Count 1000000 -TickMs 0")
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.EnvironmentVariables["HORDE_HOME"] = (Join-Path $dir "home")
        $p = [System.Diagnostics.Process]::Start($psi)
        try {
            $deadline = (Get-Date).AddSeconds(240)
            while (-not (Test-Path -LiteralPath $ready) -and -not $p.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 5 }
            if (-not (Test-Path -LiteralPath $ready)) { [void]$problems.Add("writer " + $k + " was not ready within 240 s") }
            Start-Sleep -Milliseconds ($rand.Next(150, 700))
            if ($p.HasExited) { [void]$problems.Add("writer " + $k + " had ended by itself before it could be killed") }
            else { try { $p.Kill() } catch { [void]$problems.Add("writer " + $k + " could not be killed: " + $_.Exception.Message) } }
            if (-not $p.WaitForExit(30000)) { [void]$problems.Add("writer " + $k + " was still running 30 s after the kill") }
        } finally { $p.Dispose() }
        $done++
        $loaded = Get-HordeDecisionRecords -Root $store
        $records += @($loaded.records).Count
        $bad = @($loaded.records | Where-Object { $_.kind -cne "ok" }).Count
        $damaged += $bad
        if (Test-Path -LiteralPath $store) {
            $names = @(Get-ChildItem -LiteralPath $store -Force | ForEach-Object { $_.Name })
            $leftovers += @($names | Where-Object { $_ -cmatch '\Awriting-[0-9a-f]{32}\.part\z' }).Count
            $strays += @($names | Where-Object { $_ -cnotmatch '\Awriting-[0-9a-f]{32}\.part\z' -and $_ -cnotmatch '\A[0-9]{10}\.json\z' }).Count
        }
        if ($StopAtDamage -and $bad -gt 0) { break }
    }
    return [pscustomobject]@{ problems = @($problems); rounds = $done; records = $records; damaged = $damaged; leftovers = $leftovers; strays = $strays }
}

try {

$storeCode = Join-Path $root "decisions\Store.ps1"
$opsCode = Join-Path $root "decisions\Operations.ps1"

Write-Host ""
Write-Host ("--- I. " + $racers + " processes ask the store for the same " + $storeCount + " sequence numbers, each on one tick ---") -ForegroundColor Cyan
$race = Invoke-Race -Name "store-real" -Mode "store" -Code $storeCode -Count $storeCount -TickMs $storeTickMs
$facts = Get-StoreRaceFacts $race
Write-Host ("  real store: " + @($facts.told).Count + " asks, created " + @($facts.created).Count + ", exists " + @($facts.refused).Count + ", threw " + @($facts.threw).Count + "; numbers taken twice " + @($facts.twice).Count + ", never taken " + @($facts.never).Count) -ForegroundColor DarkGray
Check (@($race.problems).Count -eq 0) "every racer started, ran and exited cleanly"
foreach ($pr in @($race.problems)) { Write-Host ("         " + $pr) -ForegroundColor Red }
Check (@($facts.told).Count -eq $racers * $storeCount -and @($facts.threw).Count -eq 0) ("every racer was answered for every number, and the store never threw (" + @($facts.told).Count + " answers)")
Check (@($facts.twice).Count -eq 0) "no sequence number was told 'created' to two racers"
Check (@($facts.never).Count -eq 0) "every sequence number was taken by one of them"
Check (@($facts.created).Count -eq $storeCount) ("exactly one 'created' for each number across all racers (" + @($facts.created).Count + " of " + $storeCount + ")")
Check ($facts.loaded.last -eq $storeCount -and @($facts.wrongOwner).Count -eq 0) "and each record on disk is readable and is the record of the racer that was told 'created' (the store read, not the racers' word)"
# CONTENTION. Every racer asks for every number, so a number where all four were answered and three
# were refused is one they contended for. What matters is that the losers were refused by the
# operating system's own create and not by turn-taking, and the control below shows that: with the
# create replaced by an overwrite, the same racers on the same ticks ARE told "created" twice.
Check (@($facts.refused).Count -eq ($racers - 1) * $storeCount) ("CONTROL: the other " + ($racers - 1) + " racers were each told 'exists' for every number (" + @($facts.refused).Count + ")")

Write-Host ""
Write-Host ("--- II. " + $racers + " processes each add " + $perRacer + " questions to one store, on the same ticks ---") -ForegroundColor Cyan
$race2 = Invoke-Race -Name "add-real" -Mode "operations" -Code $opsCode -Count $perRacer -TickMs $addTickMs
$f2 = Get-AddRaceFacts $race2
Write-Host ("  real store: " + @($f2.told).Count + " answers, done " + @($f2.done).Count + "; records in the store " + $f2.loaded.last + "; questions " + $f2.list.questions.Count + "; lost " + @($f2.lost).Count +
    "; sequence numbers told to two racers " + @($f2.sharedSequence).Count + "; extra tries " + $f2.retries) -ForegroundColor DarkGray
Check (@($race2.problems).Count -eq 0) "every racer started, ran and exited cleanly"
foreach ($pr in @($race2.problems)) { Write-Host ("         " + $pr) -ForegroundColor Red }
Check (@($f2.told).Count -eq $total) ("every racer answered for every question (" + @($f2.told).Count + " of " + $total + ")")
Check (@($f2.done).Count -eq $total) ("every add was told done: none was refused, and none could not tell (" + @($f2.done).Count + " of " + $total + ")")
foreach ($odd in @($f2.told | Where-Object { -not ($_.state -ceq "known" -and $_.outcome -ceq "done") } | Select-Object -First 5)) { Write-Host ("         racer " + $odd.racer + " question " + $odd.index + ": " + $odd.state + " " + $odd.outcome + " " + $odd.reason) -ForegroundColor Red }
Check (@($f2.sharedSequence).Count -eq 0) "no two racers were told the same sequence number"
Check (@($f2.sharedNumber).Count -eq 0) "no two racers were told the same question number"
Check ((@($f2.done | ForEach-Object { $_.sequence } | Sort-Object) -join ",") -ceq ((1..$total) -join ",")) ("the sequence numbers told are exactly 1 to " + $total + ": none skipped, none repeated")
Check ((@($f2.done | ForEach-Object { $_.number } | Sort-Object) -join ",") -ceq ((1..$total) -join ",")) "and so are the question numbers"
Check ($f2.loaded.state -ceq "ok" -and $f2.loaded.last -eq $total -and @($f2.loaded.records | Where-Object { $_.kind -cne "ok" }).Count -eq 0) ("the store holds " + $total + " records, every one readable, with no gap (the store counted, not the racers' word)")
Check (@($f2.lost).Count -eq 0) "no record was lost: every question a racer was told is done is in the store, under the number it was told"
Check ($f2.list.questions.Count -eq $total -and $f2.list.unreadable.Count -eq 0 -and $f2.list.ignored.Count -eq 0) "and the list worked out from the store has all of them, with nothing unreadable and nothing ignored"
Check (@($f2.loaded.records | ForEach-Object { "$($_.data.id)" } | Sort-Object -Unique).Count -eq $total) "each record carries its own request's id"
# CONTENTION. How much the racers overlap depends on the machine, so no share is required: one write
# that lost a sequence number and tried again already means two writers were inside the same moment.
# Measured 2026-10-06 on a throttled machine, two runs: 72 and 71 extra tries for 32 adds. In the control,
# one run: 87 of 120 numbers told 'created' twice, and 19 of 32 questions told done and lost.
Check ($f2.retries -ge 1) ("CONTROL: at least one write lost a sequence number to another racer and tried again, so the racers met (" + $f2.retries + " extra tries)")

Write-Host ""
Write-Host "--- CONTROL: the same two races against a store that overwrites instead of creating new ---" -ForegroundColor Cyan
# The copy needs what decisions/Operations.ps1 loads by relative path: decisions/, core/ and schema/.
$broken = Join-Path $script:work "broken-tree"
foreach ($folder in @("decisions", "core", "schema")) { Copy-Item -LiteralPath (Join-Path $root $folder) -Destination (Join-Path $broken $folder) -Recurse }
$storeCopy = Join-Path $broken "decisions\Store.ps1"
$src = [System.IO.File]::ReadAllText($storeCopy)
$find = '[System.IO.File]::Move($tmpPath, $recPath)'
Check (([regex]::Matches($src, [regex]::Escape($find))).Count -eq 1) "the control's edit matches exactly once in decisions/Store.ps1"
[System.IO.File]::WriteAllText($storeCopy, $src.Replace($find, '[System.IO.File]::Copy($tmpPath, $recPath, $true)'))

$bad = Invoke-Race -Name "store-broken" -Mode "store" -Code $storeCopy -Count $storeCount -TickMs $storeTickMs
$badFacts = Get-StoreRaceFacts $bad
Write-Host ("  overwriting store, race I: created " + @($badFacts.created).Count + ", threw " + @($badFacts.threw).Count + "; numbers told 'created' to two or more racers " + @($badFacts.twice).Count) -ForegroundColor DarkGray
Check (@($bad.problems).Count -eq 0) "the control's racers ran cleanly in race I"
Check (@($badFacts.twice).Count -gt 0) ("CONTROL: race I sees two racers both told 'created' for one number when the store allows it (" + @($badFacts.twice).Count + " of " + $storeCount + " numbers)")

$bad2 = Invoke-Race -Name "add-broken" -Mode "operations" -Code (Join-Path $broken "decisions\Operations.ps1") -Count $perRacer -TickMs $addTickMs
$badF2 = Get-AddRaceFacts $bad2
Write-Host ("  overwriting store, race II: done " + @($badF2.done).Count + "; records in the store " + $badF2.loaded.last + "; lost " + @($badF2.lost).Count + "; sequence numbers told to two racers " + @($badF2.sharedSequence).Count) -ForegroundColor DarkGray
Check (@($bad2.problems).Count -eq 0) "the control's racers ran cleanly in race II"
Check ((@($badF2.sharedSequence).Count + @($badF2.lost).Count) -gt 0) ("CONTROL: race II sees the damage when the store allows it: " + @($badF2.sharedSequence).Count + " sequence number(s) told to two racers, " + @($badF2.lost).Count + " question(s) told done and lost")

Write-Host ""
Write-Host ("--- III. a writer killed while it writes: " + $killRounds + " kills, and what each left ---") -ForegroundColor Cyan
# The store writes a record under a temporary name and moves it into place, so that a writer killed
# part-way leaves no record at all, never an empty one (decisions/Store.ps1 has the measurement: 9 of 30
# kills left an empty record when the record was created under its own name and then written).
$kills = Invoke-KillRounds -Name "kill-real" -Code $storeCode -Rounds $killRounds
Write-Host ("  real store: " + $kills.rounds + " kills, " + $kills.records + " records written, damaged " + $kills.damaged + ", temporary files left " + $kills.leftovers) -ForegroundColor DarkGray
Check (@($kills.problems).Count -eq 0) "every writer started, was writing, and was killed by this suite"
foreach ($pr in @($kills.problems)) { Write-Host ("         " + $pr) -ForegroundColor Red }
Check ($kills.records -ge $killRounds) ("CONTROL: the writers were writing when they were killed (" + $kills.records + " records in " + $kills.rounds + " kills)")
Check ($kills.damaged -eq 0) ("no kill left a record that cannot be read: every record in every store is whole (" + $kills.damaged + " damaged)")
Check ($kills.strays -eq 0) "and nothing but records and the store's own temporary files was left"
# CONTROL: the same kills against a copy of the store that creates the record under its own name and
# writes into it. It runs until a kill leaves a damaged record, or gives up; one is enough to show
# these kills can land inside a write and that the reading above would have seen it.
# Beside the broken tree's own store, because the store loads its settings from its own folder.
$inPlace = Join-Path $broken "decisions\Store-in-place.ps1"
$nameFind = '$tmpPath = Join-Path $Root ("writing-" + [guid]::NewGuid().ToString("N") + ".part")'
$moveFind = 'try { [System.IO.File]::Move($tmpPath, $recPath) }'
Check (([regex]::Matches($src, [regex]::Escape($nameFind))).Count -eq 1 -and ([regex]::Matches($src, [regex]::Escape($moveFind))).Count -eq 1) "the kill control's two edits each match exactly once in decisions/Store.ps1"
[System.IO.File]::WriteAllText($inPlace, $src.Replace($nameFind, '$tmpPath = $recPath').Replace($moveFind, 'try { }'))
$badKills = Invoke-KillRounds -Name "kill-in-place" -Code $inPlace -Rounds $killControlRounds -StopAtDamage
Write-Host ("  store that writes in place: " + $badKills.rounds + " kills, " + $badKills.records + " records written, damaged " + $badKills.damaged) -ForegroundColor DarkGray
Check (@($badKills.problems).Count -eq 0) "the control's writers ran and were killed by this suite"
Check ($badKills.damaged -gt 0) ("CONTROL: a kill does leave a damaged record when the record is written under its own name (after " + $badKills.rounds + " kill(s))")

} finally {
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-decisions-race-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) { Remove-Item -LiteralPath $script:work -Recurse -Force }
}
Check (-not (Test-Path -LiteralPath $script:work)) "the race's temp folder is removed"

Complete-HordeSuite -Success "racing processes cannot both take a sequence number and lose no record, and each race can see the failure it guards against"
