# CAN TWO PROCESSES BOTH CALL ONE ENVELOPE FRESH, OR A KILLED WRITER LOSE OR TEAR A RECORD?
#
# relay/Journal.ps1 against real processes, under BOTH PowerShell runtimes at once: half the racers are
# powershell.exe (Windows PowerShell 5.1) and half pwsh (PowerShell 7), all aimed at one journal
# (test/fixtures/relay/journal-worker.ps1). Each writes down what it was TOLD; the suite then compares.
#   I.   ONE ENVELOPE, MANY RACERS. Every racer registers the same envelopes on the same wall-clock
#        ticks, each envelope a stream of its own. Exactly one racer may be told fresh for each.
#   II.  ONE STREAM, MANY SEQS. Every racer registers seqs 1..N of one stream on the same ticks. No seq
#        may be fresh twice, and the records must have been made in seq order: the one writer per
#        stream is what makes "above the last" true when the record is made.
#   III. CROSS-RUNTIME. Racers of both runtimes won envelopes in I, and every other racer, of either
#        runtime, was told those were replays: each runtime reads the other's records.
#   IV.  A WRITER KILLED AT A NAMED STEP. A writer is stopped inside its write - before its record has
#        its name, and just after - and killed there. While it lives, a writer of the other runtime on
#        the same stream is told busy: the lock holds across processes and runtimes. After the kill
#        the lock is free, nothing is torn, and the envelope is fresh (killed before the move: nothing
#        was recorded) or a replay (killed after it: the whole record is there).
#
# A RACE THAT NEVER COLLIDES PROVES NOTHING (test/test-journal-race.ps1), so race I is run again against
# a BROKEN copy of the journal, made in a folder of the suite's own, whose stream lock is a no-op and
# whose write-once move is a copy that overwrites. The same harness must see an envelope told fresh
# twice there, or it could not have seen one here.
#
# Every journal is a fresh home under %TEMP% that this suite made and removes, and only processes it
# started are killed, by their handles (CONTRIBUTING 9). The dev box runs throttled, so each race is 4
# processes. PowerShell 7 missing: everything runs under 5.1, III is skipped, and the suite exits 3.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "relay\Journal.ps1")
. (Join-Path $root "relay\Keys.ps1")
Set-StrictMode -Version Latest

$streams = 30      # envelopes raced for in I, one stream each
$seqs = 30         # seqs raced for in II
$tickMs = 120
# Each runtime's racers wait this long on every other envelope, so each runtime has a head start on half
# of them; the two racers of one runtime still start each envelope together.
$headStartMs = 60
$worker = Join-Path $here "fixtures\relay\journal-worker.ps1"
$ps5 = (Get-Command -Name "powershell" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
$ps7 = (Get-Command -Name "pwsh" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
Check ($null -ne $ps5) "Windows PowerShell 5.1 is here to race with"
$both = ($null -ne $ps7)
if (-not $both) { Write-Host "  [SKIP] PowerShell 7 (pwsh) is not installed: every racer runs under 5.1, and the cross-runtime checks are skipped" -ForegroundColor Yellow }
$runtimes = @($ps5.Source, $(if ($both) { $ps7.Source } else { $ps5.Source }))

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$work = Join-Path $env:TEMP ("horde-relay-journal-race-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$signer = New-HordeRelayP256Key -Use "ecdsa"
$signerPub = ConvertTo-HordeRelayP256Public -Key $signer
$signerId = Get-HordeRelayKeyId -Public $signerPub
$phonePub = ConvertTo-HordeRelayP256Public -Key (New-HordeRelayP256Key -Use "ecdh")
$phoneId = Get-HordeRelayKeyId -Public $phonePub
$senderFile = Join-Path $work "sender.txt"
[System.IO.File]::WriteAllText($senderFile, (ConvertTo-HordeRelayHex -Bytes $signerPub))

function New-EnvelopesFile {
    # One envelope per line: -Count of them, on one channel (seqs 1..Count) or each on its own channel.
    param([string]$Path, [int]$Count, [switch]$OneStream)
    $lines = New-Object System.Collections.ArrayList
    for ($i = 1; $i -le $Count; $i++) {
        $ch = $(if ($OneStream) { "race" } else { "race-" + $i })
        $sq = $(if ($OneStream) { $i } else { 1 })
        [void]$lines.Add((New-HordeRelayEnvelope -Kind "answer" -Channel $ch -Seq $sq -Body ($utf8.GetBytes("racer body " + $i)) -Recipients @(, $phonePub) -Signer $signer))
    }
    [System.IO.File]::WriteAllLines($Path, [string[]]$lines.ToArray())
}

function Start-Worker {
    # Start one worker under -Runtime; the process. Streams are read through the process API, never
    # 2>&1 (CONTRIBUTING 12). PSModulePath is removed so each runtime finds its own modules
    # (test/test-relay-cross-runtime.ps1).
    param([string]$Runtime, [string]$Arguments)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Runtime
    $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"" + $worker + "`" " + $Arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    [void]$psi.EnvironmentVariables.Remove("PSModulePath")
    $p = [System.Diagnostics.Process]::Start($psi)
    return [pscustomobject]@{ p = $p; out = $p.StandardOutput.ReadToEndAsync(); err = $p.StandardError.ReadToEndAsync() }
}

function Read-WorkerLog {
    # A worker's lines, { racer; index; state; fresh; why }, or $null when it did not end its log.
    param([string]$Path, [int]$Racer)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $lines = @([System.IO.File]::ReadAllLines($Path))
    if ($lines.Count -eq 0 -or $lines[-1] -cne "END") { return $null }
    return @($lines[0..($lines.Count - 2)] | ForEach-Object {
        $parts = $_.Split([char]'|', 4)
        [pscustomobject]@{ racer = $Racer; index = [int]$parts[0]; state = $parts[1]; fresh = $parts[2]; why = $parts[3] }
    })
}

function Invoke-Race {
    # Four racers, two per runtime, on -EnvelopesFile against a fresh journal; { answers; problems; home }.
    param([string]$Name, [string]$EnvelopesFile, [string]$CodeRoot)
    $dir = Join-Path $work $Name
    $h = Join-Path $dir "home"
    New-Item -ItemType Directory -Path $h | Out-Null
    $null = Initialize-HordeRelayJournal -HordeHome $h
    $go = Join-Path $dir "go.txt"
    $procs = New-Object System.Collections.ArrayList
    $problems = New-Object System.Collections.ArrayList
    $answers = New-Object System.Collections.ArrayList
    try {
        for ($r = 0; $r -lt 4; $r++) {
            $args1 = ("-Mode race -CodeRoot `"" + $CodeRoot + "`" -HordeHome `"" + $h + "`" -EnvelopesFile `"" + $EnvelopesFile + "`" -RecipientKeyId " + $phoneId + " -SenderFile `"" + $senderFile +
                "`" -LogFile `"" + (Join-Path $dir ("log-" + $r + ".txt")) + "`" -GoFile `"" + $go + "`" -ReadyFile `"" + (Join-Path $dir ("ready-" + $r)) + "`" -TickMs " + $tickMs + " -DelayParity " + ($r % 2) + " -DelayMs " + $headStartMs)
            [void]$procs.Add((Start-Worker -Runtime $runtimes[$r % 2] -Arguments $args1))
        }
        $deadline = (Get-Date).AddSeconds(120)
        while (@(0..3 | Where-Object { -not (Test-Path -LiteralPath (Join-Path $dir ("ready-" + $_))) }).Count -gt 0) {
            if ((Get-Date) -gt $deadline) { [void]$problems.Add("not every racer was ready within 120 s"); break }
            if (@($procs | Where-Object { $_.p.HasExited }).Count -gt 0) { [void]$problems.Add("a racer exited before it was ready: " + (@($procs | Where-Object { $_.p.HasExited } | ForEach-Object { $_.err.Result }) -join " ")); break }
            Start-Sleep -Milliseconds 50
        }
        # Written under another name and renamed, so no racer reads it half-written.
        [System.IO.File]::WriteAllText(($go + ".tmp"), ([datetime]::UtcNow.AddMilliseconds(500).Ticks).ToString())
        [System.IO.File]::Move(($go + ".tmp"), $go)
        for ($r = 0; $r -lt 4; $r++) {
            $x = $procs[$r]
            if (-not $x.p.WaitForExit(120000)) { [void]$problems.Add("racer " + $r + " did not finish within 120 s") }
            $got = Read-WorkerLog -Path (Join-Path $dir ("log-" + $r + ".txt")) -Racer $r
            if ($null -eq $got) { [void]$problems.Add("racer " + $r + " left no complete log: " + $x.err.Result); continue }
            foreach ($a in @($got)) { [void]$answers.Add($a) }
        }
    } finally {
        foreach ($x in $procs) { if (-not $x.p.HasExited) { try { $x.p.Kill() } catch { } }; $x.p.Dispose() }
    }
    return [pscustomobject]@{ answers = @($answers); problems = @($problems); home = $h }
}

function Get-FreshCounts {
    # Per envelope index, how many racers were told fresh.
    param($Answers, [int]$Count)
    $c = @{}
    for ($i = 0; $i -lt $Count; $i++) { $c[$i] = 0 }
    foreach ($a in $Answers) { if ($a.state -ceq "known" -and $a.fresh -ceq "True") { $c[$a.index]++ } }
    return $c
}

try {
    Write-Host ""
    Write-Host ("--- I. one envelope, four racers: " + $streams + " envelopes, each its own stream ---") -ForegroundColor Cyan
    $envI = Join-Path $work "envelopes-i.txt"
    New-EnvelopesFile -Path $envI -Count $streams
    $race = Invoke-Race -Name "race-i" -EnvelopesFile $envI -CodeRoot $root
    Check ($race.problems.Count -eq 0) ("every racer started, raced and logged (" + ($race.problems -join "; ") + ")")
    Check ($race.answers.Count -eq 4 * $streams) ("every racer answered every envelope (" + $race.answers.Count + " of " + (4 * $streams) + ")")
    $counts = Get-FreshCounts -Answers $race.answers -Count $streams
    $twice = @($counts.Keys | Where-Object { $counts[$_] -gt 1 })
    $never = @($counts.Keys | Where-Object { $counts[$_] -eq 0 })
    Check ($twice.Count -eq 0) ("no envelope was told fresh to two racers (" + $twice.Count + ")")
    Check ($never.Count -eq 0) ("every envelope was told fresh to one racer (" + $never.Count + " to none)")
    $odd = @($race.answers | Where-Object { -not ($_.state -ceq "known" -and ($_.fresh -ceq "True" -or $_.why.StartsWith("a replay"))) -and -not ($_.state -ceq "unknown" -and $_.why.Contains("busy")) })
    Check ($odd.Count -eq 0) ("every other answer was a replay, or busy (" + (@($odd | Select-Object -First 3 | ForEach-Object { $_.state + " " + $_.why }) -join "; ") + ")")
    $winners = @($race.answers | Where-Object { $_.fresh -ceq "True" } | ForEach-Object { $_.racer } | Sort-Object -Unique)
    Check ($winners.Count -ge 2) ("CONTENTION: more than one racer won envelopes (" + ($winners -join ",") + "), so they met rather than took turns")
    $busy = @($race.answers | Where-Object { $_.state -ceq "unknown" }).Count
    Write-Host ("  told busy: " + $busy + " of " + $race.answers.Count + " answers") -ForegroundColor DarkGray
    $onDisk = @(Get-ChildItem -LiteralPath (Join-Path $race.home ("relay\journal\in\s-" + $signerId)) -Recurse -File -Filter "*.rec")
    Check ($onDisk.Count -eq $streams) ("and the journal holds exactly one record per envelope (" + $onDisk.Count + ")")

    Write-Host ""
    Write-Host "--- III. across runtimes ---" -ForegroundColor Cyan
    if ($both) {
        # Racers 0 and 2 run under 5.1, 1 and 3 under 7.
        $won5 = @($race.answers | Where-Object { $_.fresh -ceq "True" -and $_.racer % 2 -eq 0 }).Count
        $won7 = @($race.answers | Where-Object { $_.fresh -ceq "True" -and $_.racer % 2 -eq 1 }).Count
        Check ($won5 -ge 1 -and $won7 -ge 1) ("racers of both runtimes won envelopes (5.1: " + $won5 + ", 7: " + $won7 + ")")
        $readOther = @($race.answers | Where-Object { $_.why.StartsWith("a replay") } | Where-Object {
            $idx = $_.index; $me = $_.racer
            @($race.answers | Where-Object { $_.index -eq $idx -and $_.fresh -ceq "True" -and ($_.racer % 2) -ne ($me % 2) }).Count -eq 1 })
        Check ($readOther.Count -ge 1) ("a racer of one runtime was told replay for a record the other runtime made (" + $readOther.Count + " times)")
    } else { Write-Host "  [SKIP] one runtime only" -ForegroundColor Yellow }

    Write-Host ""
    Write-Host ("--- II. one stream, four racers: seqs 1 to " + $seqs + " ---") -ForegroundColor Cyan
    $envII = Join-Path $work "envelopes-ii.txt"
    New-EnvelopesFile -Path $envII -Count $seqs -OneStream
    $raceII = Invoke-Race -Name "race-ii" -EnvelopesFile $envII -CodeRoot $root
    Check ($raceII.problems.Count -eq 0) ("every racer started, raced and logged (" + ($raceII.problems -join "; ") + ")")
    $countsII = Get-FreshCounts -Answers $raceII.answers -Count $seqs
    Check (@($countsII.Keys | Where-Object { $countsII[$_] -gt 1 }).Count -eq 0) "no seq was told fresh to two racers"
    $freshII = @($countsII.Keys | Where-Object { $countsII[$_] -eq 1 }).Count
    Check ($freshII -ge [int]($seqs / 2)) ("most seqs were taken by someone (" + $freshII + " of " + $seqs + "); the rest were refused as out of order or busy")
    $sd = Join-Path $raceII.home ("relay\journal\in\s-" + $signerId + "\c-race")
    $recs = @(Get-ChildItem -LiteralPath $sd -File -Filter "*.rec" | Sort-Object Name | ForEach-Object {
        $first = [System.IO.File]::ReadAllText($_.FullName).Split([char]10)[0]
        [void]($first -cmatch '"seq":([0-9]+),.*"recordedAt":([0-9]+),')
        [pscustomobject]@{ seq = [long]$Matches[1]; at = [long]$Matches[2] } })
    Check ($recs.Count -eq $freshII) ("the stream holds one record per fresh answer (" + $recs.Count + ")")
    $backwards = 0
    for ($k = 1; $k -lt $recs.Count; $k++) { if ($recs[$k].at -lt $recs[$k - 1].at) { $backwards++ } }
    Check ($backwards -eq 0) ("records were made in seq order: none was made before a lower seq's (" + $backwards + ")")
    $refusedII = @($raceII.answers | Where-Object { $_.fresh -ceq "False" -and ($_.why.StartsWith("out of order") -or $_.why.StartsWith("a replay")) }).Count
    Check ($refusedII -ge 1) ("CONTROL: racers were refused as replays or out of order in the same stream (" + $refusedII + ")")

    Write-Host ""
    Write-Host "--- CONTROL: the same race against a journal with no lock and an overwriting write ---" -ForegroundColor Cyan
    $broken = Join-Path $work "broken"
    foreach ($d in @("core", "relay", "schema")) { Copy-Item -LiteralPath (Join-Path $root $d) -Destination (Join-Path $broken $d) -Recurse }
    $bj = Join-Path $broken "relay\Journal.ps1"
    $src = [System.IO.File]::ReadAllText($bj)
    $lockLine = '$lock = Enter-HordeRelayJournalLock -Dir $dir -WaitMs $ctx.settings.lockWaitMs'
    $moveLine = '$moved = Move-HordeFileNewDurable -From $tmp -To ([System.IO.Path]::Combine($Dir, $Name)) -Open $fs'
    Check (([regex]::Matches($src, [regex]::Escape($lockLine))).Count -eq 1 -and ([regex]::Matches($src, [regex]::Escape($moveLine))).Count -eq 1) "CONTROL: the lines the broken copy replaces occur once each"
    $src = $src.Replace($lockLine, '$lock = [pscustomobject]@{ ok = $true; held = (New-Object System.IO.MemoryStream); reason = "" }')
    $src = $src.Replace($moveLine, '$fs.Dispose(); [System.IO.File]::Copy($tmp, [System.IO.Path]::Combine($Dir, $Name), $true); [System.IO.File]::Delete($tmp); $moved = "moved"')
    [System.IO.File]::WriteAllText($bj, $src, $utf8)
    $raceB = Invoke-Race -Name "race-broken" -EnvelopesFile $envI -CodeRoot $broken
    Check ($raceB.problems.Count -eq 0) ("the broken race ran (" + ($raceB.problems -join "; ") + ")")
    $countsB = Get-FreshCounts -Answers $raceB.answers -Count $streams
    $twiceB = @($countsB.Keys | Where-Object { $countsB[$_] -gt 1 }).Count
    Check ($twiceB -ge 1) ("CONTROL: against the broken journal the harness sees envelopes told fresh twice (" + $twiceB + " of " + $streams + ")")

    Write-Host ""
    Write-Host "--- IV. a writer killed at a named step ---" -ForegroundColor Cyan
    $envK = Join-Path $work "envelopes-k.txt"
    New-EnvelopesFile -Path $envK -Count 3 -OneStream
    foreach ($step in @("stall-before-move", "stall-after-move")) {
        $dir = Join-Path $work $step
        $h = Join-Path $dir "home"
        New-Item -ItemType Directory -Path $h | Out-Null
        $null = Initialize-HordeRelayJournal -HordeHome $h
        $mark = Join-Path $dir "stalled"
        $common = "-CodeRoot `"" + $root + "`" -HordeHome `"" + $h + "`" -EnvelopesFile `"" + $envK + "`" -RecipientKeyId " + $phoneId + " -SenderFile `"" + $senderFile + "`""
        $w = Start-Worker -Runtime $runtimes[0] -Arguments ("-Mode " + $step + " -Index 0 -GoFile `"" + $mark + "`" -LogFile `"" + (Join-Path $dir "stalled-log.txt") + "`" " + $common)
        try {
            $deadline = (Get-Date).AddSeconds(120)
            while (-not (Test-Path -LiteralPath $mark) -and -not $w.p.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 20 }
            Check ((Test-Path -LiteralPath $mark) -and -not $w.p.HasExited) ($step + ": the writer reached its step and is alive there")
            # While it lives, a writer of the other runtime on the same stream waits for the lock and is
            # told busy (the default wait is 2000 ms).
            $o = Start-Worker -Runtime $runtimes[1] -Arguments ("-Mode once -Index 1 -LogFile `"" + (Join-Path $dir "while-log.txt") + "`" " + $common)
            [void]$o.p.WaitForExit(120000); $o.p.Dispose()
            $while = Read-WorkerLog -Path (Join-Path $dir "while-log.txt") -Racer 9
            Check ($null -ne $while -and $while[0].state -ceq "unknown" -and $while[0].why.Contains("busy")) ($step + ": meanwhile, a writer of the other runtime on the stream is told busy (" + $(if ($null -ne $while) { $while[0].why } else { "no log" }) + ")")
        } finally {
            if (-not $w.p.HasExited) { $w.p.Kill() }
            [void]$w.p.WaitForExit(30000)
            $w.p.Dispose()
        }
        Check (-not (Test-Path -LiteralPath (Join-Path $dir "stalled-log.txt"))) ($step + ": the killed writer was told nothing")
        $sd = Join-Path $h ("relay\journal\in\s-" + $signerId + "\c-race")
        $temps = @(Get-ChildItem -LiteralPath $sd -File -Filter "writing-*.part")
        $recs = @(Get-ChildItem -LiteralPath $sd -File -Filter "*.rec")
        if ($step -ceq "stall-before-move") {
            Check ($recs.Count -eq 0 -and $temps.Count -eq 1) ($step + ": killed before the move, no record and one leftover (" + $recs.Count + " records, " + $temps.Count + " leftovers)")
        } else {
            Check ($recs.Count -eq 1 -and $temps.Count -eq 0) ($step + ": killed after the move, the record and no leftover (" + $recs.Count + " records, " + $temps.Count + " leftovers)")
        }
        $a = Start-Worker -Runtime $runtimes[1] -Arguments ("-Mode once -Index 0 -LogFile `"" + (Join-Path $dir "after-log.txt") + "`" " + $common)
        [void]$a.p.WaitForExit(120000); $a.p.Dispose()
        $after = Read-WorkerLog -Path (Join-Path $dir "after-log.txt") -Racer 9
        if ($step -ceq "stall-before-move") {
            Check ($null -ne $after -and $after[0].fresh -ceq "True") ($step + ": the lock was freed by the kill, and the same envelope is fresh: nothing had been recorded")
            Check (@(Get-ChildItem -LiteralPath $sd -File -Filter "writing-*.part").Count -eq 0) ($step + ": and the dead writer's leftover was swept")
        } else {
            Check ($null -ne $after -and $after[0].fresh -ceq "False" -and $after[0].why.StartsWith("a replay")) ($step + ": the lock was freed by the kill, and the same envelope is a replay: the whole record is there")
        }
        $n = Start-Worker -Runtime $runtimes[0] -Arguments ("-Mode once -Index 2 -LogFile `"" + (Join-Path $dir "next-log.txt") + "`" " + $common)
        [void]$n.p.WaitForExit(120000); $n.p.Dispose()
        $next = Read-WorkerLog -Path (Join-Path $dir "next-log.txt") -Racer 9
        Check ($null -ne $next -and $next[0].fresh -ceq "True") ($step + ": and the stream goes on: the next seq is fresh, nothing torn")
    }
} finally {
    if ((Split-Path -Leaf $work) -match '^horde-relay-journal-race-[0-9a-f]{32}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
Check (-not (Test-Path -LiteralPath $work)) "every journal this suite made is gone"

if (-not $both) { Complete-HordeSuite -Success "partial: one runtime only, so the cross-runtime checks were skipped" -PassCode 3 }
Complete-HordeSuite -Success "racing processes of both runtimes never both took one envelope, and a killed writer left the journal whole"
