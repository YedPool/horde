# CAN TWO PROCESSES SHARING AT THE SAME MOMENT LOSE A RECORD, AND WHAT DOES A SHARE KILLED PART-WAY LEAVE?
#
# The race is real: separate powershell.exe processes (test/fixtures/files/race-worker.ps1), all aimed
# at one files store, acting on the same wall-clock ticks. Each writes down what it was TOLD. The suite
# then reads the store itself and compares.
#   I.   ONE FILE. Every racer shares the SAME path as the same session on the SAME tick, so all try
#        for the same next version. Every share must be told a version of its own, and the record
#        under that version must be that racer's.
#   II.  ONE SET OF BYTES. Every racer shares a file of its own holding the same words, so all put the
#        same bytes in the store at once. None may be refused or throw - which is what a racer that
#        saw another's bytes half-written would do - and the bytes are kept once.
#   III. A SHARE KILLED AT A NAMED STEP. A process is stopped inside one share - before and after its
#        bytes take their name, before and after its record does - and killed there. At each step:
#        the list holds the whole record, or nothing; and the writer was told nothing.
#
# A RACE THAT NEVER COLLIDES PROVES NOTHING, so race I has its controls (test/test-decisions-store-race.ps1):
#   - CONTENTION, measured: shares that say they took more than one try, which happens only when
#     another share took the version first.
#   - A BROKEN STORE: the same race against a copy of the store whose move-without-replace is replaced
#     by a write that overwrites. There the harness must see one version told to two racers.
# Race II has no control: a store that overwrites the same bytes with the same bytes loses nothing to
# see. It is kept for what it can show, and says so here.
#
# Every home is a fresh folder under %TEMP% that this suite made and removes (CONTRIBUTING 9). The
# machine this was written on was throttled (2026-10-13), so each race is 4 processes.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "files\Share.ps1")

$racers = 4
$perRacer = 6
$tickMs = 250
$total = $racers * $perRacer
$worker = Join-Path $root "test\fixtures\files\race-worker.ps1"
$script:work = Join-Path $env:TEMP ("horde-files-race-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
# Whatever this suite's own calls are not handed, they must not find the real home.
$env:HORDE_HOME = Join-Path $script:work "home-nobody-uses"

function Start-Worker {
    # One worker process: { p; out; err }. Its home is the one it is given, in its environment too.
    param([string]$Dir, [string]$Mode, [string]$Code, [string]$Source, [int]$Racer, [int]$Count, [string]$Extra = "")
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = ("-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"" + $worker + "`" -Mode " + $Mode + " -CodePath `"" + $Code + "`" -HordeHome `"" + (Join-Path $Dir "home") +
        "`" -Source `"" + $Source + "`" -GoFile `"" + (Join-Path $Dir "go.txt") + "`" -ReadyFile `"" + (Join-Path $Dir ("ready-" + $Racer)) + "`" -LogFile `"" + (Join-Path $Dir ("log-" + $Racer + ".txt")) +
        "`" -Racer " + $Racer + " -Count " + $Count + " -TickMs " + $tickMs + " " + $Extra)
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables["HORDE_HOME"] = (Join-Path $Dir "home")
    $p = [System.Diagnostics.Process]::Start($psi)
    return [pscustomobject]@{ p = $p; out = $p.StandardOutput.ReadToEndAsync(); err = $p.StandardError.ReadToEndAsync() }
}

function Invoke-Race {
    # Run one race. Returns { problems; told; home; store }: told is every racer's log, one object a share.
    param([string]$Name, [string]$Mode, [string]$Code)
    $dir = Join-Path $script:work $Name
    New-Item -ItemType Directory -Path $dir | Out-Null
    $go = Join-Path $dir "go.txt"
    $procs = New-Object System.Collections.ArrayList
    $problems = New-Object System.Collections.ArrayList
    try {
        for ($r = 0; $r -lt $racers; $r++) {
            # One file for all in race I; a file of its own for each in race II.
            $source = Join-Path $dir "shared.md"
            if ($Mode -ceq "same-bytes") { $source = Join-Path $dir ("own-" + $r + ".txt") }
            if (-not (Test-Path -LiteralPath $source)) { [System.IO.File]::WriteAllText($source, "the words every racer shares") }
            [void]$procs.Add((Start-Worker -Dir $dir -Mode $Mode -Code $Code -Source $source -Racer $r -Count $perRacer))
        }
        # Every racer has loaded its code before the clock starts, so start-up is not part of the race.
        $deadline = (Get-Date).AddSeconds(240)
        while (@(0..($racers - 1) | Where-Object { -not (Test-Path -LiteralPath (Join-Path $dir ("ready-" + $_))) }).Count -gt 0) {
            if ((Get-Date) -gt $deadline) { [void]$problems.Add("not every racer was ready within 240 s"); break }
            if (@($procs | Where-Object { $_.p.HasExited }).Count -gt 0) { [void]$problems.Add("a racer exited before it was ready"); break }
            Start-Sleep -Milliseconds 50
        }
        # Written under another name and renamed, so no racer reads it half-written.
        [System.IO.File]::WriteAllText(($go + ".tmp"), ([datetime]::UtcNow.AddMilliseconds(500).Ticks).ToString())
        [System.IO.File]::Move(($go + ".tmp"), $go)
        foreach ($x in $procs) {
            if (-not $x.p.WaitForExit(240000)) { [void]$problems.Add("a racer ran past 240 s without finishing"); continue }
            $x.p.WaitForExit()
            if ($x.p.ExitCode -ne 0) { [void]$problems.Add("a racer exited " + $x.p.ExitCode + ": " + $x.err.Result) }
        }
    } finally {
        # Only the processes this suite started, by the handles it holds.
        foreach ($x in $procs) { if (-not $x.p.HasExited) { try { $x.p.Kill() } catch { } }; $x.p.Dispose() }
    }
    $told = New-Object System.Collections.ArrayList
    for ($r = 0; $r -lt $racers; $r++) {
        $lf = Join-Path $dir ("log-" + $r + ".txt")
        if (-not (Test-Path -LiteralPath $lf)) { [void]$problems.Add("racer " + $r + " left no log"); continue }
        foreach ($line in [System.IO.File]::ReadAllLines($lf)) {
            if ($line -ceq "END") { continue }
            $f = $line.Split("|")
            [void]$told.Add([pscustomobject]@{ racer = $r; index = [int]$f[0]; outcome = $f[1]; fileId = $f[2]; version = [int]$f[3]; attempts = [int]$f[4]; sha256 = $f[5]; reason = $f[6]; title = ("racer " + $r + " share " + $f[0]) })
        }
    }
    return [pscustomobject]@{ problems = @($problems); told = @($told); home = (Join-Path $dir "home"); store = (Join-Path $dir "home\store\files") }
}

function Get-RaceFacts {
    # What the store holds, set against what the racers were told.
    param($Race)
    $shared = @($Race.told | Where-Object { $_.outcome -ceq "shared" })
    $list = Get-HordeFilesList -HordeHome $Race.home
    $byPlace = @{}
    foreach ($row in @($list.rows)) { $byPlace[($row.fileId + "." + $row.version)] = $row.title }
    $names = @()
    if (Test-Path -LiteralPath $Race.store) { $names = @(Get-ChildItem -LiteralPath $Race.store -Force | ForEach-Object { $_.Name }) }
    return [pscustomobject]@{ shared = $shared; list = $list
        notShared = @($Race.told | Where-Object { $_.outcome -cne "shared" })
        # Told "shared" and not in the store under the version it was told, or another racer's record there.
        lost = @($shared | Where-Object { -not $byPlace.ContainsKey(($_.fileId + "." + $_.version)) -or $byPlace[($_.fileId + "." + $_.version)] -cne $_.title })
        sharedPlace = @($shared | Group-Object { $_.fileId + "." + $_.version } | Where-Object { $_.Count -gt 1 })
        retries = [int](@($shared | ForEach-Object { $_.attempts - 1 }) | Measure-Object -Sum).Sum
        bytesFiles = @($names | Where-Object { $_ -cmatch '\A[0-9a-f]{64}\.bytes\z' })
        temporaries = @($names | Where-Object { $_ -cmatch '\Awriting-[0-9a-f]{32}\.part\z' })
        others = @($names | Where-Object { $_ -cnotmatch '\A[0-9a-f]{64}\.bytes\z' -and $_ -cnotmatch '\Awriting-[0-9a-f]{32}\.part\z' -and $_ -cnotmatch '\A[0-9a-f]{32}\.[0-9]{6}\.json\z' }) }
}

function Start-StalledWriter {
    # Start a writer that makes one share and stops inside it at move -Move, -When it. Returns
    # { problems; proc; dir; home; store; log }. THE CALLER KILLS IT, with Stop-StalledWriter.
    param([string]$Name, [int]$Move, [string]$When)
    $dir = Join-Path $script:work $Name
    New-Item -ItemType Directory -Path $dir | Out-Null
    $source = Join-Path $dir "stalled.md"
    [System.IO.File]::WriteAllText($source, "a share that is stopped part-way")
    $problems = New-Object System.Collections.ArrayList
    $w = Start-Worker -Dir $dir -Mode "stall" -Code (Join-Path $root "files\Share.ps1") -Source $source -Racer 0 -Count 1 -Extra ("-StallMove " + $Move + " -StallWhen " + $When)
    $mark = Join-Path $dir "go.txt"
    $deadline = (Get-Date).AddSeconds(240)
    while (-not (Test-Path -LiteralPath $mark) -and -not $w.p.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 20 }
    if (-not (Test-Path -LiteralPath $mark)) { [void]$problems.Add("the writer did not reach its step within 240 s" + $(if ($w.p.HasExited) { " (it exited " + $w.p.ExitCode + ": " + $w.err.Result + ")" } else { "" })) }
    elseif ($w.p.HasExited) { [void]$problems.Add("the writer had ended by itself at its step") }
    return [pscustomobject]@{ problems = $problems; proc = $w.p; dir = $dir; home = (Join-Path $dir "home"); store = (Join-Path $dir "home\store\files"); log = (Join-Path $dir "log-0.txt") }
}

function Stop-StalledWriter {
    param($Writer)
    try {
        if (-not $Writer.proc.HasExited) { try { $Writer.proc.Kill() } catch { [void]$Writer.problems.Add("the writer could not be killed: " + $_.Exception.Message) } }
        if (-not $Writer.proc.WaitForExit(30000)) { [void]$Writer.problems.Add("the writer was still running 30 s after the kill") }
    } finally { $Writer.proc.Dispose() }
}

function Get-StoreShape {
    # The store's names, each reduced to its kind, sorted and joined: "bytes,record,temporary".
    param([string]$Store)
    if (-not (Test-Path -LiteralPath $Store)) { return "" }
    return (@(Get-ChildItem -LiteralPath $Store -Force | ForEach-Object {
        if ($_.Name -cmatch '\A[0-9a-f]{64}\.bytes\z') { "bytes" } elseif ($_.Name -cmatch '\Awriting-[0-9a-f]{32}\.part\z') { "temporary" } elseif ($_.Name -cmatch '\A[0-9a-f]{32}\.[0-9]{6}\.json\z') { "record" } else { "other:" + $_.Name }
    } | Sort-Object) -join ",")
}

try {

$shareCode = Join-Path $root "files\Share.ps1"

Write-Host ""
Write-Host ("--- I. " + $racers + " processes share ONE path as one session, " + $perRacer + " times, each on one tick ---") -ForegroundColor Cyan
$race = Invoke-Race -Name "one-file" -Mode "same-path" -Code $shareCode
$f = Get-RaceFacts $race
Write-Host ("  real store: " + @($race.told).Count + " shares, told shared " + @($f.shared).Count + "; records listed " + @($f.list.rows).Count + "; lost " + @($f.lost).Count + "; versions told twice " + @($f.sharedPlace).Count + "; extra tries " + $f.retries) -ForegroundColor DarkGray
Check (@($race.problems).Count -eq 0) "every racer started, ran and exited cleanly"
foreach ($pr in @($race.problems)) { Write-Host ("         " + $pr) -ForegroundColor Red }
Check (@($race.told).Count -eq $total -and @($f.notShared).Count -eq 0) ("every share was told 'shared': none refused, none threw (" + @($f.shared).Count + " of " + $total + ")")
foreach ($odd in @($f.notShared | Select-Object -First 5)) { Write-Host ("         racer " + $odd.racer + " share " + $odd.index + ": " + $odd.outcome + " " + $odd.reason) -ForegroundColor Red }
Check (@($f.shared | ForEach-Object { $_.fileId } | Sort-Object -Unique).Count -eq 1) "every racer was told the SAME file id: one path from one session is one file"
Check (@($f.sharedPlace).Count -eq 0) "no version was told to two racers"
Check ((@($f.shared | ForEach-Object { $_.version } | Sort-Object) -join ",") -ceq ((1..$total) -join ",")) ("the versions told are exactly 1 to " + $total + ": none skipped, none repeated")
Check ($f.list.state -ceq "ok" -and @($f.list.rows).Count -eq $total -and @($f.list.unreadable).Count -eq 0 -and @($f.list.strays).Count -eq 0) ("the store holds " + $total + " records, every one readable (the store read, not the racers' word)")
Check (@($f.lost).Count -eq 0) "no record was lost: every share a racer was told is shared is in the store, under the version it was told, and is that racer's"
Check (@($f.bytesFiles).Count -eq 1 -and @($f.temporaries).Count -eq 0 -and @($f.others).Count -eq 0) ("the bytes all of them shared are kept once, and no temporary file is left (" + @($f.bytesFiles).Count + " bytes file(s), " + @($f.temporaries).Count + " temporary)")
# CONTENTION. How much the racers overlap depends on the machine, so no share is required: one share
# that lost a version and tried again already means two writers were inside the same moment.
Check ($f.retries -ge 1) ("CONTROL: at least one share lost a version to another racer and tried again, so the racers met (" + $f.retries + " extra tries)")

Write-Host ""
Write-Host "--- CONTROL: the same race against a store that overwrites instead of creating new ---" -ForegroundColor Cyan
# The copy needs what files/Share.ps1 loads by relative path: files/, core/ and schema/.
$broken = Join-Path $script:work "broken-tree"
foreach ($folder in @("files", "core", "schema")) { Copy-Item -LiteralPath (Join-Path $root $folder) -Destination (Join-Path $broken $folder) -Recurse }
$storeCopy = Join-Path $broken "files\Store.ps1"
$src = [System.IO.File]::ReadAllText($storeCopy)
$find = '$moved = Move-HordeFileNewDurable -From $tmpPath -To $entryPath -Open $fs'
Check (([regex]::Matches($src, [regex]::Escape($find))).Count -eq 1) "the control's edit matches exactly once in files/Store.ps1"
[System.IO.File]::WriteAllText($storeCopy, $src.Replace($find, '[System.IO.File]::WriteAllBytes($entryPath, $Bytes); $moved = "moved"'))
$bad = Invoke-Race -Name "one-file-broken" -Mode "same-path" -Code (Join-Path $broken "files\Share.ps1")
$bf = Get-RaceFacts $bad
Write-Host ("  overwriting store: told shared " + @($bf.shared).Count + "; records listed " + @($bf.list.rows).Count + "; lost " + @($bf.lost).Count + "; versions told to two or more racers " + @($bf.sharedPlace).Count) -ForegroundColor DarkGray
Check (@($bad.problems).Count -eq 0) "the control's racers ran cleanly"
Check ((@($bf.sharedPlace).Count + @($bf.lost).Count) -gt 0) ("CONTROL: the race sees the damage when the store allows it: " + @($bf.sharedPlace).Count + " version(s) told to two racers, " + @($bf.lost).Count + " share(s) told shared and lost")

Write-Host ""
Write-Host ("--- II. " + $racers + " processes each share a file of their own holding the SAME bytes, " + $perRacer + " rounds ---") -ForegroundColor Cyan
$race2 = Invoke-Race -Name "one-bytes" -Mode "same-bytes" -Code $shareCode
$f2 = Get-RaceFacts $race2
Write-Host ("  real store: " + @($race2.told).Count + " shares, told shared " + @($f2.shared).Count + "; records listed " + @($f2.list.rows).Count + "; bytes files " + @($f2.bytesFiles).Count) -ForegroundColor DarkGray
Check (@($race2.problems).Count -eq 0) "every racer started, ran and exited cleanly"
foreach ($pr in @($race2.problems)) { Write-Host ("         " + $pr) -ForegroundColor Red }
Check (@($race2.told).Count -eq $total -and @($f2.notShared).Count -eq 0) ("every share was told 'shared': no racer found another's bytes half-written (" + @($f2.shared).Count + " of " + $total + ")")
foreach ($odd in @($f2.notShared | Select-Object -First 5)) { Write-Host ("         racer " + $odd.racer + " share " + $odd.index + ": " + $odd.outcome + " " + $odd.reason) -ForegroundColor Red }
Check (@($f2.shared | ForEach-Object { $_.fileId } | Sort-Object -Unique).Count -eq $racers) ("each racer's own path is a file of its own (" + $racers + " file ids)")
Check (@($f2.shared | Group-Object fileId | Where-Object { (@($_.Group | ForEach-Object { $_.version } | Sort-Object) -join ",") -cne ((1..$perRacer) -join ",") }).Count -eq 0) ("and each has versions 1 to " + $perRacer)
Check (@($f2.shared | Group-Object index | Where-Object { @($_.Group | ForEach-Object { $_.sha256 } | Sort-Object -Unique).Count -ne 1 }).Count -eq 0) "CONTROL: in every round all the racers shared the same bytes (one sha256 a round)"
Check (@($f2.bytesFiles).Count -eq $perRacer) ("the bytes of each round are kept ONCE, whoever got there first: " + @($f2.bytesFiles).Count + " bytes files for " + $total + " shares")
$wrongBytes = @($f2.bytesFiles | Where-Object { (Get-HordeFilesHex -Bytes ([System.IO.File]::ReadAllBytes((Join-Path $race2.store $_)))) -cne $_.Substring(0, 64) })
Check ($wrongBytes.Count -eq 0) "and every bytes file holds exactly the bytes its name is the digest of"
Check ($f2.list.state -ceq "ok" -and @($f2.list.rows).Count -eq $total -and @($f2.list.unreadable).Count -eq 0 -and @($f2.lost).Count -eq 0 -and @($f2.temporaries).Count -eq 0) ("the store holds all " + $total + " records, readable, none lost, and no temporary file")

Write-Host ""
Write-Host "--- III. a share stopped at a named step, and killed there ---" -ForegroundColor Cyan
$farAhead = [datetime]::UtcNow.AddDays(400)
$steps = @(
    @{ move = 1; when = "before"; shape = "temporary"; rows = 0; what = "before its bytes take their name" },
    @{ move = 1; when = "after"; shape = "bytes"; rows = 0; what = "after its bytes took their name, before any record" },
    @{ move = 2; when = "before"; shape = "bytes,temporary"; rows = 0; what = "before its record takes its name" },
    @{ move = 2; when = "after"; shape = "bytes,record"; rows = 1; what = "after its record took its name" })
foreach ($step in $steps) {
    $w = Start-StalledWriter -Name ("stall-" + $step.move + "-" + $step.when) -Move $step.move -When $step.when
    try {
        Check (@($w.problems).Count -eq 0) ("a share was stopped " + $step.what)
        Check ((Get-StoreShape $w.store) -ceq $step.shape) ("at that step the store holds: " + $step.shape + " (" + (Get-StoreShape $w.store) + ")")
        if ($step.shape -like "*temporary*") {
            # THE SWEEP'S INVARIANT, ACROSS PROCESSES: this process sweeps, with a clock 400 days ahead,
            # while that one is alive and holds its file. It must take nothing.
            $swept = Remove-HordeFilesStoreLeftovers -Root $w.store -MinAgeSeconds 600 -Now $farAhead
            Check ($swept -eq 0 -and (Get-StoreShape $w.store) -ceq $step.shape) ("a sweep from another process, its clock 400 days ahead, takes nothing while the writer lives (" + $swept + " removed)")
        }
    } finally { Stop-StalledWriter $w }
    foreach ($pr in @($w.problems)) { Write-Host ("         " + $pr) -ForegroundColor Red }
    Check (-not (Test-Path -LiteralPath $w.log)) "the writer was killed before it was told anything"
    $left = Get-HordeFilesList -HordeHome $w.home
    Check (@($left.rows).Count -eq $step.rows -and @($left.unreadable).Count -eq 0 -and @($left.strays).Count -eq 0) ("after the kill the list holds " + $step.rows + " share(s) and nothing unreadable: " + $(if ($step.rows -eq 0) { "a share killed here left NOTHING in the list" } else { "the WHOLE record is there, and a share killed here lost nothing" }))
    Check ((Get-StoreShape $w.store) -ceq $step.shape) "and the store is as the kill left it"
    if ($step.rows -eq 1) { Check ($left.rows[0].title -ceq "A share stopped part-way" -and $left.rows[0].size -eq 32 -and [System.IO.File]::Exists((Join-Path $w.store (Get-HordeFilesBytesName -Sha256 $left.rows[0].sha256)))) "that record is whole, and the bytes it names are there" }
    if ($step.shape -like "*temporary*") {
        $swept = Remove-HordeFilesStoreLeftovers -Root $w.store -MinAgeSeconds 600 -Now $farAhead
        Check ($swept -eq 1 -and (Get-StoreShape $w.store) -ceq ($step.shape -replace ',?temporary', '')) ("CONTROL: now that its writer is dead the same sweep removes its temporary file (" + $swept + " removed)")
    }
    # The same file shared again, by a writer that lives: it is in the list exactly once more.
    $again = Add-HordeFilesShare -Path (Join-Path $w.dir "stalled.md") -Title "Shared again after the kill" -HordeHome $w.home -Asking (New-HordeKnown -Value "race-session")
    Check ($again.outcome -ceq "shared" -and $again.record.version -eq ($step.rows + 1) -and @((Get-HordeFilesList -HordeHome $w.home).rows).Count -eq ($step.rows + 1)) ("sharing the file again afterwards is version " + ($step.rows + 1) + ", and the list then holds " + ($step.rows + 1))
    Check (@(Get-ChildItem -LiteralPath $w.store -Filter "*.bytes").Count -eq 1) "with its bytes in the store once"
}

} finally {
    if ((Split-Path -Leaf $script:work) -match '\Ahorde-files-race-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) { Remove-Item -LiteralPath $script:work -Recurse -Force }
}
Check (-not (Test-Path -LiteralPath $script:work)) "the race's temp folder is removed"

Complete-HordeSuite -Success "processes sharing at the same moment lose no record and take no version twice, a share killed part-way leaves the whole record or nothing, and the race can see the failure it guards against"
