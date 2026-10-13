# CAN TWO PROCESSES SHARING AT THE SAME MOMENT LOSE A RECORD, AND WHAT DOES A SHARE KILLED PART-WAY LEAVE?
#
# The race is real: separate powershell.exe processes (test/fixtures/files/race-worker.ps1), all aimed
# at one files store, acting on the same wall-clock ticks. Each writes down what it was TOLD. The suite
# then reads the store itself and compares.
#   I.   ONE FILE. Every racer shares the SAME path as the same session on the SAME tick, so all try
#        for the same next version. Every share must be told a version of its own, and the record
#        under that version must be that racer's.
#   I-b. THE FIRST SHARE OF A HOME. Every round is a home with no key, and every racer's share of
#        that round is its first: all of them find no key, and then make one, one after another in
#        an order the worker stages (it says why, and why not by the clock). They must end with ONE
#        key, and all be told the one file id it gives (files/Key.ps1). Race I, on a new home too,
#        is the same thing left to the machine: there the four really are inside the making of the
#        key at one moment.
#   II.  ONE SET OF BYTES. Every racer shares a file of its own holding the same words, so all put the
#        same bytes in the store at once. None may be refused or throw - which is what a racer that
#        saw another's bytes half-written would do - and the bytes are kept once.
#   III. A SHARE KILLED AT A NAMED STEP. A process is stopped inside one share - before and after its
#        key takes its name, its bytes theirs, and its record its own - and killed there. At each
#        step: the list holds the whole record, or nothing; the writer was told nothing; and the
#        next share of that home has one whole key.
#
# A RACE THAT NEVER COLLIDES PROVES NOTHING, so race I has its controls (test/test-decisions-store-race.ps1):
#   - CONTENTION, measured: shares that say they took more than one try, which happens only when
#     another share took the version first.
#   - A BROKEN STORE: the same race against a copy of the store whose move-without-replace is replaced
#     by a write that overwrites. There the harness must see one version told to two racers.
# And race I-b has its own: the same race against a copy whose KEY is put in place by a copy that
# replaces. There the harness must see racers told different ids for one path in EVERY round: the
# order is staged by the racers telling each other where they are, never by the clock, so a busy
# machine makes the race slower and no round is left to chance. That the staging held in every
# round is a check of its own, in the real race and in the control.
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
        "`" -Racer " + $Racer + " -Racers " + $racers + " -Count " + $Count + " -TickMs " + $tickMs + " " + $Extra)
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
            # One file for all in races I and I-b; a file of its own for each in race II.
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
    # What the racers of a staged race told each other (race-worker.ps1): every share that was DONE
    # in its turn, and every share for which the staging did not hold. Both are 0 in a race that
    # stages nothing.
    $staged = @(Get-ChildItem -LiteralPath $dir -Filter "stage-*-done-*" -File).Count
    $stageFailed = @(Get-ChildItem -LiteralPath $dir -Filter "stage-*-failed-*" -File).Count
    return [pscustomobject]@{ problems = @($problems); told = @($told); home = (Join-Path $dir "home"); store = (Join-Path $dir "home\store\files"); staged = $staged; stageFailed = $stageFailed }
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

function Get-KeyFolder {
    # What a home's keys folder holds: { names; keyLength }, names sorted and joined, "" when there is none.
    param([string]$TestHome)
    $folder = Join-Path $TestHome "keys"
    if (-not (Test-Path -LiteralPath $folder)) { return [pscustomobject]@{ names = ""; keyLength = -1 } }
    $length = -1
    if ([System.IO.File]::Exists((Join-Path $folder "files-id.key"))) { $length = (New-Object System.IO.FileInfo((Join-Path $folder "files-id.key"))).Length }
    return [pscustomobject]@{ names = (@(Get-ChildItem -LiteralPath $folder -Force | Sort-Object Name | ForEach-Object { $_.Name -replace '\Amaking-[0-9a-f]{32}\.part\z', 'making' }) -join ","); keyLength = $length }
}

function Get-FirstShareFacts {
    # A first-share race, round by round: every round is a new home, so every round is a race for the key.
    param($Race)
    $rounds = @($Race.told | Group-Object index)
    return [pscustomobject]@{
        rounds = $rounds.Count
        notShared = @($Race.told | Where-Object { $_.outcome -cne "shared" })
        # Rounds whose racers were told more than one file id: they did not all use one key.
        split = @($rounds | Where-Object { @($_.Group | Where-Object { $_.outcome -ceq "shared" } | ForEach-Object { $_.fileId } | Sort-Object -Unique).Count -gt 1 })
        # Homes whose keys folder is not exactly one whole key.
        badKeys = @(0..($perRacer - 1) | Where-Object { $k = Get-KeyFolder ($Race.home + "-" + $_); $k.names -cne "files-id.key" -or $k.keyLength -ne 32 })
    }
}

function Test-KilledShare {
    # A share stopped at the store's move number -Move (1 the key, 2 the bytes, 3 the record), -When
    # it, and killed there. One call is one statement of the suite: after an error no check expected,
    # the suite's trap goes on with the next call, so one step's error cannot hide the other steps.
    param([int]$Move, [string]$When, [string]$Shape, [int]$Rows, [string]$Keys, [string]$What)
    $farAhead = [datetime]::UtcNow.AddDays(400)
    $w = Start-StalledWriter -Name ("stall-" + $Move + "-" + $When) -Move $Move -When $When
    try {
        Check (@($w.problems).Count -eq 0) ("a share was stopped " + $What)
        Check ((Get-StoreShape $w.store) -ceq $Shape) ("at that step the store holds: '" + $Shape + "' (" + (Get-StoreShape $w.store) + ")")
        Check ((Get-KeyFolder $w.home).names -ceq $Keys) ("and the keys folder holds: '" + $Keys + "' (" + (Get-KeyFolder $w.home).names + ")")
        if ($Shape -like "*temporary*") {
            # THE SWEEP'S INVARIANT, ACROSS PROCESSES: this process sweeps, with a clock 400 days ahead,
            # while that one is alive and holds its file. It must take nothing.
            $swept = Remove-HordeFilesStoreLeftovers -Root $w.store -MinAgeSeconds 600 -Now $farAhead
            Check ($swept -eq 0 -and (Get-StoreShape $w.store) -ceq $Shape) ("a sweep from another process, its clock 400 days ahead, takes nothing while the writer lives (" + $swept + " removed)")
        }
    } finally { Stop-StalledWriter $w }
    foreach ($pr in @($w.problems)) { Write-Host ("         " + $pr) -ForegroundColor Red }
    Check (-not (Test-Path -LiteralPath $w.log)) "the writer was killed before it was told anything"
    $left = Get-HordeFilesList -HordeHome $w.home
    Check (@($left.rows).Count -eq $Rows -and @($left.unreadable).Count -eq 0 -and @($left.strays).Count -eq 0) ("after the kill the list holds " + $Rows + " share(s) and nothing unreadable: " + $(if ($Rows -eq 0) { "a share killed here left NOTHING in the list" } else { "the WHOLE record is there, and a share killed here lost nothing" }))
    Check ((Get-StoreShape $w.store) -ceq $Shape) "and the store is as the kill left it"
    $killedId = ""
    if ($Rows -eq 1 -and @($left.rows).Count -eq 1) {
        $killedId = $left.rows[0].fileId
        Check ($left.rows[0].title -ceq "A share stopped part-way" -and $left.rows[0].size -eq 32 -and [System.IO.File]::Exists((Join-Path $w.store (Get-HordeFilesBytesName -Sha256 $left.rows[0].sha256)))) "that record is whole, and the bytes it names are there"
    }
    if ($Shape -like "*temporary*") {
        $swept = Remove-HordeFilesStoreLeftovers -Root $w.store -MinAgeSeconds 600 -Now $farAhead
        Check ($swept -eq 1 -and (Get-StoreShape $w.store) -ceq ($Shape -replace ',?temporary', '')) ("CONTROL: now that its writer is dead the same sweep removes its temporary file (" + $swept + " removed)")
    }
    # The same file shared again, by a writer that lives: it is in the list exactly once more.
    $again = Add-HordeFilesShare -Path (Join-Path $w.dir "stalled.md") -Title "Shared again after the kill" -HordeHome $w.home -Asking (New-HordeKnown -Value "race-session")
    Check ($again.outcome -ceq "shared" -and $again.record.version -eq ($Rows + 1) -and @((Get-HordeFilesList -HordeHome $w.home).rows).Count -eq ($Rows + 1)) ("sharing the file again afterwards is version " + ($Rows + 1) + ", and the list then holds " + ($Rows + 1))
    Check (@(Get-ChildItem -LiteralPath $w.store -Filter "*.bytes").Count -eq 1) "with its bytes in the store once"
    $keysAfter = Get-KeyFolder $w.home
    Check ($keysAfter.keyLength -eq 32 -and @($keysAfter.names.Split(",") | Where-Object { $_ -ceq "files-id.key" }).Count -eq 1) ("and the home has one whole key (" + $keysAfter.names + ")")
    if ($killedId -ne "") { Check ($again.record.fileId -ceq $killedId) "the later share has the SAME file id as the killed one's record: both used the one key" }
    if ($Keys -ceq "making") {
        # The killed key writer's temporary file is not the key, and is left: it names nothing.
        $leftover = @(Get-ChildItem -LiteralPath (Join-Path $w.home "keys") -Filter "making-*.part")
        Check ($leftover.Count -eq 1 -and [System.BitConverter]::ToString([System.IO.File]::ReadAllBytes($leftover[0].FullName)) -cne [System.BitConverter]::ToString([System.IO.File]::ReadAllBytes((Join-Path $w.home "keys\files-id.key")))) "the key the killed writer never named is still there as a temporary file, and is NOT the key the home now has"
    }
}

# NOT ONE try AROUND THE CHECKS (test/test-files-store.ps1 has the measurement): after an error no check
# expected, the suite's trap goes on with the next statement of the script, and one try around
# everything is one statement. Every process this suite starts is stopped in the finally of the
# function that started it, so the sections are plain statements.
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
Check (@($f.shared | ForEach-Object { $_.fileId } | Sort-Object -Unique).Count -eq 1) "every racer was told the SAME file id: one path from one session is one file, and all of them made that id with one key"
Check (@($f.sharedPlace).Count -eq 0) "no version was told to two racers"
Check ((@($f.shared | ForEach-Object { $_.version } | Sort-Object) -join ",") -ceq ((1..$total) -join ",")) ("the versions told are exactly 1 to " + $total + ": none skipped, none repeated")
Check ($f.list.state -ceq "ok" -and @($f.list.rows).Count -eq $total -and @($f.list.unreadable).Count -eq 0 -and @($f.list.strays).Count -eq 0) ("the store holds " + $total + " records, every one readable (the store read, not the racers' word)")
Check (@($f.lost).Count -eq 0) "no record was lost: every share a racer was told is shared is in the store, under the version it was told, and is that racer's"
Check (@($f.bytesFiles).Count -eq 1 -and @($f.temporaries).Count -eq 0 -and @($f.others).Count -eq 0) ("the bytes all of them shared are kept once, and no temporary file is left (" + @($f.bytesFiles).Count + " bytes file(s), " + @($f.temporaries).Count + " temporary)")
$raceKeys = Get-KeyFolder $race.home
Check ($raceKeys.names -ceq "files-id.key" -and $raceKeys.keyLength -eq 32) ("the home has ONE key of 32 bytes and no key writer's temporary file (" + $raceKeys.names + ")")
# CONTENTION. How much the racers overlap depends on the machine, so no share is required: one share
# that lost a version and tried again already means two writers were inside the same moment.
Check ($f.retries -ge 1) ("CONTROL: at least one share lost a version to another racer and tried again, so the racers met (" + $f.retries + " extra tries)")

Write-Host ""
Write-Host "--- CONTROL: the same race against a store that overwrites instead of creating new ---" -ForegroundColor Cyan
# The copy needs what files/Share.ps1 loads by relative path: files/, core/ and schema/.
# The agents folder is part of the tree: without it a share refuses, not knowing which folders are a
# harness's (files/Deny.ps1), and a control whose every share is refused sees no damage at all.
$broken = Join-Path $script:work "broken-tree"
foreach ($folder in @("files", "core", "schema", "agents")) { Copy-Item -LiteralPath (Join-Path $root $folder) -Destination (Join-Path $broken $folder) -Recurse }
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
Write-Host ("--- I-b. THE FIRST SHARE of a home, raced: " + $racers + " processes, " + $perRacer + " rounds, each round a home with no key ---") -ForegroundColor Cyan
$first = Invoke-Race -Name "first-share" -Mode "first-share" -Code $shareCode
$ff = Get-FirstShareFacts $first
Write-Host ("  real key: " + @($first.told).Count + " shares in " + $ff.rounds + " new homes; not shared " + @($ff.notShared).Count + "; rounds told two ids " + @($ff.split).Count + "; homes without exactly one key " + @($ff.badKeys).Count + "; shares staged " + $first.staged + ", staging failed " + $first.stageFailed) -ForegroundColor DarkGray
Check (@($first.problems).Count -eq 0) "every racer started, ran and exited cleanly"
Check ($first.staged -eq $total -and $first.stageFailed -eq 0) ("THE ORDER WAS STAGED IN EVERY ROUND, and not by the clock: every racer had found no key before any made one, and they went on one at a time (" + $first.staged + " of " + $total + " shares staged, " + $first.stageFailed + " for which the staging did not hold)")
Check ($race.staged -eq 0 -and $race.stageFailed -eq 0) "CONTROL: race I stages nothing - there the racers are left to the machine"
foreach ($pr in @($first.problems)) { Write-Host ("         " + $pr) -ForegroundColor Red }
Check (@($first.told).Count -eq $total -and $ff.rounds -eq $perRacer -and @($ff.notShared).Count -eq 0) ("every first share was told 'shared': the racer that lost the key read the winner's, none refused, none threw (" + (@($first.told).Count - @($ff.notShared).Count) + " of " + $total + ")")
foreach ($odd in @($ff.notShared | Select-Object -First 5)) { Write-Host ("         racer " + $odd.racer + " share " + $odd.index + ": " + $odd.outcome + " " + $odd.reason) -ForegroundColor Red }
Check (@($ff.split).Count -eq 0) "in every round all the racers were told ONE file id: the first shares of a home at one moment end with one key, and all of them use it"
Check (@($ff.badKeys).Count -eq 0) ("and every one of the " + $perRacer + " homes has exactly one key file of 32 bytes, with no temporary file beside it")
Check (@($first.told | Where-Object { $_.outcome -ceq "shared" } | ForEach-Object { $_.fileId } | Sort-Object -Unique).Count -eq $perRacer) ("CONTROL: the " + $perRacer + " homes made " + $perRacer + " different keys: the same path is a different id in each")

Write-Host ""
Write-Host "--- CONTROL: the same first-share race when the key's move replaces what is there ---" -ForegroundColor Cyan
$brokenKey = Join-Path $script:work "broken-key-tree"
foreach ($folder in @("files", "core", "schema", "agents")) { Copy-Item -LiteralPath (Join-Path $root $folder) -Destination (Join-Path $brokenKey $folder) -Recurse }
$keyCopy = Join-Path $brokenKey "files\Key.ps1"
$src = [System.IO.File]::ReadAllText($keyCopy)
$find = '$moved = Move-HordeFileNewDurable -From $tmpPath -To $Path'
Check (([regex]::Matches($src, [regex]::Escape($find))).Count -eq 1) "the control's edit matches exactly once in files/Key.ps1"
[System.IO.File]::WriteAllText($keyCopy, $src.Replace($find, '[System.IO.File]::Copy($tmpPath, $Path, $true); $moved = "moved"'))
$badFirst = Invoke-Race -Name "first-share-broken" -Mode "first-share" -Code (Join-Path $brokenKey "files\Share.ps1")
$bff = Get-FirstShareFacts $badFirst
Write-Host ("  replacing key: " + @($badFirst.told).Count + " shares; not shared " + @($bff.notShared).Count + "; rounds told two or more ids " + @($bff.split).Count + "; shares staged " + $badFirst.staged + ", staging failed " + $badFirst.stageFailed) -ForegroundColor DarkGray
Check (@($badFirst.told).Count -eq $total) "the control's racers each wrote down what they were told"
Check ($badFirst.staged -eq $total -and $badFirst.stageFailed -eq 0) ("the control's order was staged in every round too (" + $badFirst.staged + " of " + $total + " shares staged, " + $badFirst.stageFailed + " failed)")
# EVERY ROUND, NOT HALF OF THEM. While the order was staged by the clock, half was asked for,
# because a busy machine could hold a racer back past its turn; three runs of 2026-10-13 saw 0, 0
# and 1 of 6. Staged by the racers themselves, the order holds whatever the load, so a round that
# does not split is the control failing and never the machine.
Check (@($bff.split).Count -eq $perRacer) ("CONTROL: the race sees two keys when the code allows them, in EVERY round: " + @($bff.split).Count + " of " + $perRacer + " rounds in which racers were told different ids for one path (" + @($bff.notShared).Count + " share(s) not shared)")

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
Test-KilledShare -Move 1 -When "before" -Shape "" -Rows 0 -Keys "making" -What "before its key takes its name"
Test-KilledShare -Move 1 -When "after" -Shape "" -Rows 0 -Keys "files-id.key" -What "after its key took its name, before anything is in the store"
Test-KilledShare -Move 2 -When "before" -Shape "temporary" -Rows 0 -Keys "files-id.key" -What "before its bytes take their name"
Test-KilledShare -Move 2 -When "after" -Shape "bytes" -Rows 0 -Keys "files-id.key" -What "after its bytes took their name, before any record"
Test-KilledShare -Move 3 -When "before" -Shape "bytes,temporary" -Rows 0 -Keys "files-id.key" -What "before its record takes its name"
Test-KilledShare -Move 3 -When "after" -Shape "bytes,record" -Rows 1 -Keys "files-id.key" -What "after its record took its name"

if ((Split-Path -Leaf $script:work) -match '\Ahorde-files-race-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $script:work)) { Remove-Item -LiteralPath $script:work -Recurse -Force }
Check (-not (Test-Path -LiteralPath $script:work)) "the race's temp folder is removed"

Complete-HordeSuite -Success "processes sharing at the same moment lose no record and take no version twice, the first shares of a home end with one key, a share killed part-way leaves the whole record or nothing, and each race can see the failure it guards against"
