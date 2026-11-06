# DOES `horde db sync` KEEP fleet.db CURRENT FROM THE SAVED FILES - ONE AT A TIME, WITHIN A TIME LIMIT, AND WITH A LOG?
#
# The PowerShell half of T-0389 (fleet-db/Sync.ps1, cli/commands/db.ps1, fleet-db/register-sync.ps1); the node half
# (what is due, the saved sources, the state) is fleet-db/test/sync.test.mjs. This drives the real horde command:
#   - no saved sources: refused in one line that names the -Save form, and the refusal is logged;
#   - -Save writes the settings and syncs; the log gets an ok line; `db status` ends with the last good sync;
#   - a second sync inside 5 minutes says the files step was skipped; flags of another verb are refused;
#   - THE LOCK: while another process holds fleet-db-sync.lock the sync says "skipped: a sync is still running",
#     exits 0, logs it, and runs again once the lock is let go;
#   - THE TIME LIMIT: node is pointed (HORDE_DB_SYNC_TEST_SCRIPT, a test-only seam) at a fixture that sleeps; it runs
#     below normal priority, is killed by its own pid after -TimeLimitSeconds, "timeout" is logged and kept in the
#     state, the command exits 1, and fleet.db is as it was;
#   - THE LOG is bounded: a log past 1 MB is cut to its newest half and ends with this run's line;
#   - THE SESSIONS STEP (T-0409): the snapshot is made by a child process (the test seam HORDE_DB_SYNC_TEST_SNAPSHOT names a fixture
#     that writes a fake one: no test ever asks a real terminal, registry or process table). It runs on every tick, also when the files
#     step is skipped; a snapshot that fails, or hangs past its share of the limit and is killed by its own pid, fails the sessions step
#     and never the files step; a files step that fails never stops the sessions step; the log line and the output name both; no
#     snapshot file is left behind; `db status` shows the step's line;
#   - the same sync under PowerShell 7;
#   - register-sync.ps1 -WhatIf lists the one task and registers nothing; its text holds every setting the header explains.
# NOTHING REAL IS READ OR WRITTEN: the home and the profile every child sees are folders this suite made and removes; no
# scheduled task is registered. Processes are stopped by their own pid only.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")

$node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $node) {
    Write-Host "  [SKIP] no node here: fleet.db cannot run" -ForegroundColor Yellow
    Complete-HordeSuite -Success "NOTHING RUN: no node" -PassCode 3
}

$work = Join-Path $env:TEMP ("horde-db-sync-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$hordeHome = Join-Path $work "home"
$fakeProfile = Join-Path $work "profile"
New-Item -ItemType Directory -Path $hordeHome, $fakeProfile | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
# The fake snapshot the sessions step reads: one session in pane 3 of a terminal that lists pane 3, its transcript idle. The fixture
# script stands in for fleet-db\SessionSnapshotRun.ps1 (HORDE_DB_SYNC_TEST_SNAPSHOT); its mode says fail, hang or write.
$fakeTranscript = Join-Path $work "fake-transcript.jsonl"
[System.IO.File]::WriteAllText($fakeTranscript, ('{"type":"user","timestamp":"2026-11-02T10:00:00.000Z","message":{"role":"user","content":"go"}}' + "`n" + '{"type":"assistant","timestamp":"2026-11-02T10:01:00.000Z","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text"}]}}' + "`n"), $utf8)
$fakeSession = "22222222-0000-4000-8000-000000000001"
$fakeRec = [ordered]@{ kind = "warg"; owner = "C"; instance = "term-100"; pane = "3"; cwd = $work; transcriptPath = $fakeTranscript; firstSeen = "2026-11-02T10:00:00Z"; lastSeen = "2026-11-02T10:01:00Z" }
$fakeSnap = [ordered]@{ v = 1; at = [long]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()); registry = [ordered]@{ complete = $true; reason = ""; sessions = @([ordered]@{ id = $fakeSession; rec = $fakeRec }) }; panes = [ordered]@{ state = "known"; reason = ""; sockets = @([ordered]@{ instance = "term-100"; state = "listed"; panes = @(3); reason = "" }) }; processes = [ordered]@{ state = "known"; reason = ""; running = @() } }
$fakeSnapFile = Join-Path $work "fake-snapshot.json"
[System.IO.File]::WriteAllText($fakeSnapFile, (ConvertTo-Json -InputObject $fakeSnap -Depth 8 -Compress), $utf8)
$fakeScript = Join-Path $work "fake-snapshot.ps1"
[System.IO.File]::WriteAllText($fakeScript, ('param([string]$Out)' + "`n" + 'if ($env:HORDE_FAKE_SNAPSHOT_MODE -eq "fail") { [Console]::Error.WriteLine("snapshot fixture failed"); exit 1 }' + "`n" + 'if ($env:HORDE_FAKE_SNAPSHOT_MODE -eq "hang") { [System.IO.File]::WriteAllText($env:HORDE_SLEEPER_PIDFILE, [string][System.Diagnostics.Process]::GetCurrentProcess().Id); Start-Sleep -Seconds 120 }' + "`n" + '[System.IO.File]::Copy($env:HORDE_FAKE_SNAPSHOT_JSON, $Out, $true)' + "`n"), $utf8)
$cliEnv = @{ HORDE_HOME = $hordeHome; USERPROFILE = $fakeProfile; HORDE_DB_SYNC_TEST_SNAPSHOT = $fakeScript; HORDE_FAKE_SNAPSHOT_JSON = $fakeSnapFile }
function Invoke-Db { param([string[]]$DbArgs, [hashtable]$Env = $cliEnv, [string]$Shell = "powershell.exe") return (Invoke-HordeCliProcess -Root $root -HordeArgs (@("db") + $DbArgs) -Env $Env -Shell $Shell) }
$logFile = Join-Path (Join-Path $hordeHome "logs") "fleet-db-sync.log"
$stateFile = Join-Path $hordeHome "fleet-db-sync-state.json"
$lockFile = Join-Path $hordeHome "fleet-db-sync.lock"
function Get-LogLines { if (Test-Path -LiteralPath $logFile) { return @([System.IO.File]::ReadAllLines($logFile)) } else { return @() } }
function Get-StatusLine { param([string]$Prefix) $o = (Invoke-Db @("status")).out; foreach ($l in ($o -split "`r?`n")) { if ($l.StartsWith($Prefix)) { return $l } }; return "" }

try {
    # The sources: a card, a ledger of two lines, a changelog of one.
    $cards = Join-Path $work "orcs"
    New-Item -ItemType Directory -Path (Join-Path $cards "form-fill") | Out-Null
    $card = (@("horde-orc-status 1", "orc: C", "lane: Form fill", "doing: working on the list", "finished: a part", "blocked: no") -join "`n") + "`n"
    [System.IO.File]::WriteAllText((Join-Path (Join-Path $cards "form-fill") "status.txt"), $card, $utf8)
    $ledger = Join-Path $work "tasks.jsonl"
    [System.IO.File]::WriteAllText($ledger, ('{"ts":"2026-11-01T10:00:00Z","task":"T-0001","event":"opened","title":"First","source":"founder","lane":"C","prio":2,"parent":null,"by":"C"}' + "`n" + '{"ts":"2026-11-01T11:00:00Z","task":"T-0001","event":"started","by":"C"}' + "`n"), $utf8)
    $changelog = Join-Path $work "changelog.jsonl"
    [System.IO.File]::WriteAllText($changelog, ('{"v":1,"id":"20261101T120000Z-01","ts":"2026-11-01T12:00:00Z","kind":"note","area":"Lane C","title":"one","text":"Happened: a","lane":"C","task":"T-0001"}' + "`n"), $utf8)

    Write-Host ""
    Write-Host "--- nothing saved: refused, in one line, and logged ---" -ForegroundColor Cyan
    $r = Invoke-Db @("init")
    Check ($r.code -eq 0) "CONTROL: horde db init makes the test home's fleet.db"
    $r = Invoke-Db @("sync")
    Check ($r.code -ne 0 -and $r.out -like "*no sources are saved*" -and $r.out -like "*db sync -Save*") "no saved sources: refused, and the line names the -Save form"
    Check (-not (Test-Path -LiteralPath $stateFile)) "   and a refusal leaves no state"
    Check ((Get-LogLines | Where-Object { $_ -match '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ failed \d+ ms \| ' }).Count -eq 1) "   and the log has one line for it: UTC time, failed, ms, the reason"
    Check ((Get-StatusLine "sync:") -ceq "sync: never synced") "db status says never synced"

    Write-Host ""
    Write-Host "--- -Save, then a sync, then a second one inside 5 minutes ---" -ForegroundColor Cyan
    $r = Invoke-Db @("sync", "-Save", "-Ledger", $ledger, "-Changelog", $changelog, "-Cards", $cards)
    Check ($r.code -eq 0 -and $r.out -like "*sync: files ran, *task_event +2*") ("-Save saves the sources and runs the files step (" + $r.code + ": " + $r.out.Trim() + ")")
    Check ($r.out -like "*; sessions ran, 1 sessions (0 live, 1 idle, 0 waiting-person, 0 dead, 0 unknown)*") "   and the sessions step, in the same tick, from the snapshot the child wrote"
    Check ((Get-StatusLine "session:") -ceq "session: 1 rows") "   the fake snapshot's session is a row"
    Check ((Get-StatusLine "sessions:") -like "sessions: last ok 20*Z, last run ok at 20*Z, live 0, idle 1, waiting-person 0, dead 0, unknown 0") "db status has one line for the sessions step, with the sessions by state"
    Check (@(Get-ChildItem -LiteralPath $hordeHome -Filter "fleet-db-sessions-*.snapshot.json" -ErrorAction SilentlyContinue).Count -eq 0) "no snapshot file is left in the home"
    Check (@(Get-LogLines | Where-Object { $_ -match '^\S+ ok \d+ ms \| sync: files ran, .*; sessions ran, 1 sessions' }).Count -eq 1) "the log line names both steps"
    Check (Test-Path -LiteralPath (Join-Path (Join-Path $hordeHome "settings") "fleet-db-sync.json")) "   the settings file is in HORDE_HOME\settings"
    Check ((Get-StatusLine "task_event:") -ceq "task_event: 2 rows" -and (Get-StatusLine "orc_status:") -ceq "orc_status: 1 rows") "   the events and the card's status are in fleet.db"
    Check ((Get-StatusLine "sync:") -like "sync: files last ok 20*Z, last run ok at 20*Z") "db status now ends with the last good sync"
    $okLines = @(Get-LogLines | Where-Object { $_ -match '^\S+ ok \d+ ms \| sync: files ran, ' })
    Check ($okLines.Count -eq 1) "the log got an ok line naming the step and the rows added"
    $r = Invoke-Db @("sync")
    Check ($r.code -eq 0 -and $r.out -like "*sync: files skipped (last ok *") "a second sync inside 5 minutes skips the files step and exits 0"
    Check ($r.out -like "*files skipped (last ok *); sessions ran, 1 sessions*") "   and the sessions step still ran: it is not paced by the files step"
    Check (@(Get-LogLines | Where-Object { $_ -match ' ok \d+ ms \| sync: files skipped' }).Count -eq 1) "   and logs it"
    $r = Invoke-Db @("sync", "-Force")
    Check ($r.code -eq 0 -and $r.out -like "*sync: files ran, no rows added*") "-Force runs the step at once, and adds nothing the second time"
    # A backslash before the closing quote of node's command line would escape that quote and save a path with a quote in it.
    $r = Invoke-Db @("sync", "-Save", "-Ledger", $ledger, "-Changelog", $changelog, "-Cards", ($cards + "\"))
    $saved = [System.IO.File]::ReadAllText((Join-Path (Join-Path $hordeHome "settings") "fleet-db-sync.json")) | ConvertFrom-Json
    Check ($r.code -eq 0 -and $r.out -like "*sync: files ran*") ("-Save runs inside 5 minutes too: new sources do not wait (" + $r.code + ": " + $r.out.Trim() + ")")
    Check ($saved.cards -ceq ($cards + "\") -and $saved.ledger -ceq $ledger) ("a path ending in a backslash is saved as given (" + $saved.cards + ")")

    Write-Host ""
    Write-Host "--- flags are for their own verb ---" -ForegroundColor Cyan
    $r = Invoke-Db @("sync", "-Ledger", $ledger)
    Check ($r.code -ne 0 -and $r.out -like "*only taken with -Save*") "source paths without -Save are refused (they are saved, not used once)"
    $r = Invoke-Db @("sync", "-Registry", $work)
    Check ($r.code -ne 0 -and $r.out -like "*-Registry belongs to db import, not db sync*") "the registry, decisions and lots are not the sync's"
    $r = Invoke-Db @("status", "-Force")
    Check ($r.code -ne 0 -and $r.out -like "*-Force belongs to db sync, not db status*") "-Force on another verb is refused"
    $r = Invoke-Db @("import", "-Save", "-Ledger", $ledger)
    Check ($r.code -ne 0 -and $r.out -like "*-Save belongs to db sync, not db import*") "-Save on import is refused"

    Write-Host ""
    Write-Host "--- one at a time: a held lock skips ---" -ForegroundColor Cyan
    $held = [System.IO.File]::Open($lockFile, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    try {
        $before = @(Get-LogLines).Count
        $r = Invoke-Db @("sync", "-Force")
        Check ($r.code -eq 0 -and $r.out -like "*skipped: a sync is still running*") "while another process holds the lock: 'skipped: a sync is still running', exit 0"
        $lines = @(Get-LogLines)
        Check ($lines.Count -eq $before + 1 -and $lines[$lines.Count - 1] -match ' skipped 0 ms \| a sync is still running$') "   and the log says so"
    } finally { $held.Dispose() }
    # A holder that shares: only the sync's OWN FileShare.None refuses here. Above, the holder's None would refuse any opener, so a sync that shared its lock (two syncs at once) would still pass.
    $held = [System.IO.File]::Open($lockFile, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::ReadWrite)
    try {
        $r = Invoke-Db @("sync", "-Force")
        Check ($r.code -eq 0 -and $r.out -like "*skipped: a sync is still running*") "the sync's own lock shares with nobody: an opener that allows sharing still makes it skip"
    } finally { $held.Dispose() }
    $r = Invoke-Db @("sync", "-Force")
    Check ($r.code -eq 0 -and $r.out -like "*sync: files ran*") "the lock is let go with the handle (no stale lock): the next sync runs"

    Write-Host ""
    Write-Host "--- the time limit: below normal, killed by its own pid, timeout logged, database unchanged ---" -ForegroundColor Cyan
    $pidFile = Join-Path $work "sleeper.pid"
    $sleeper = Join-Path $work "sleeper.mjs"
    [System.IO.File]::WriteAllText($sleeper, "import fs from 'node:fs';`nfs.writeFileSync(process.env.HORDE_SLEEPER_PIDFILE, String(process.pid));`nsetTimeout(() => {}, 120000);`n", $utf8)
    $eventsBefore = Get-StatusLine "task_event:"
    $sleepEnv = @{ HORDE_HOME = $hordeHome; USERPROFILE = $fakeProfile; HORDE_DB_SYNC_TEST_SCRIPT = $sleeper; HORDE_SLEEPER_PIDFILE = $pidFile; HORDE_DB_SYNC_TEST_SNAPSHOT = $fakeScript; HORDE_FAKE_SNAPSHOT_JSON = $fakeSnapFile }
    $started = Get-Date
    $run = Start-HordeCliRun -Root $root -HordeArgs @("db", "sync", "-Force", "-TimeLimitSeconds", "10") -Env $sleepEnv
    $sleeperPid = 0
    $deadline = (Get-Date).AddSeconds(8)
    while ($sleeperPid -eq 0 -and (Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $pidFile) { $t = ([System.IO.File]::ReadAllText($pidFile)).Trim(); if ($t -match '^\d+$') { $sleeperPid = [int]$t } }
        if ($sleeperPid -eq 0) { Start-Sleep -Milliseconds 100 }
    }
    Check ($sleeperPid -gt 0) "CONTROL: the fixture script was started as the sync's child"
    # The fixture writes its pid at once and the parent lowers it just after starting it, so this asks until it shows (a busy box is slow here).
    $priority = ""
    $deadline = (Get-Date).AddSeconds(5)
    while ($sleeperPid -gt 0 -and $priority -cne "BelowNormal" -and $priority -cne "gone" -and (Get-Date) -lt $deadline) {
        try { $priority = "" + (Get-Process -Id $sleeperPid -ErrorAction Stop).PriorityClass } catch { $priority = "gone" }
        if ($priority -cne "BelowNormal") { Start-Sleep -Milliseconds 100 }
    }
    Check ($priority -ceq "BelowNormal") ("the node child runs below normal priority (" + $priority + ")")
    $done = Complete-HordeCliRun -Run $run -Seconds 60
    $took = ((Get-Date) - $started).TotalSeconds
    Check ($done.code -eq 1 -and $done.out -like "*sync timeout*") ("past the limit: exit 1 and one line saying timeout (" + $done.code + ")")
    Check ($took -lt 40) ("   and it ended near the limit, not after the child's two minutes (" + [int]$took + " s)")
    $alive = $true
    if ($sleeperPid -gt 0) { try { $null = Get-Process -Id $sleeperPid -ErrorAction Stop } catch { $alive = $false } }
    Check (-not $alive) "the child was killed through its own pid"
    $lines = @(Get-LogLines)
    Check ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -match ' timeout \d+ ms \| killed after 10 s; the import is one transaction, so the database is unchanged$') "the log line says timeout"
    $state = [System.IO.File]::ReadAllText($stateFile)
    Check ($state -match '"lastResult": "timeout"' -and $state -match '"lastOkAt": \d+') "the state keeps lastResult timeout beside the last good time"
    Check ((Get-StatusLine "task_event:") -ceq $eventsBefore) "fleet.db is as it was"
    Check ((Get-StatusLine "sync:") -like "sync: files last ok 20*Z, last run timeout at 20*Z") "and db status says the last run timed out"
    Check ((Invoke-Db @("sync", "-Force")).out -like "*sync: files ran*") "the lock was released after the kill: the next sync runs"

    Write-Host ""
    Write-Host "--- the sessions step: its own failures, and neither step stops the other ---" -ForegroundColor Cyan
    # A snapshot the child cannot make: the sessions step fails, the files step runs (-Force), the line names both, the exit is 1.
    $failEnv = $cliEnv + @{ HORDE_FAKE_SNAPSHOT_MODE = "fail" }
    $r = Invoke-Db @("sync", "-Force") -Env $failEnv
    Check ($r.code -eq 1 -and $r.out -like "*files ran*sessions failed: no session snapshot this tick: snapshot fixture failed*") ("a failed snapshot: the files step ran, the sessions step failed with the child's reason, exit 1 (" + $r.code + ": " + $r.out.Trim() + ")")
    $lines = @(Get-LogLines)
    Check ($lines[$lines.Count - 1] -match ' failed \d+ ms \| fleet\.db: sync: files ran, .*; sessions failed: ') "   and the log line says failed and names both steps"
    $state = [System.IO.File]::ReadAllText($stateFile) | ConvertFrom-Json
    Check ($state.sessions.lastResult -ceq "failed" -and $state.files.lastResult -ceq "ok") "   and the state keeps each step's own result"
    Check ((Get-StatusLine "sessions:") -like "sessions: last ok 20*Z, last run failed at 20*Z, live 0, idle 1*") "   and db status says the sessions step's last run failed beside its last good one"
    # A snapshot that hangs: killed by its own pid after its share of the limit (40 percent of 10 s), and the files step still runs.
    $hangPid = Join-Path $work "hanger.pid"
    if (Test-Path -LiteralPath $hangPid) { Remove-Item -LiteralPath $hangPid -Force }
    $hangEnv = $cliEnv + @{ HORDE_FAKE_SNAPSHOT_MODE = "hang"; HORDE_SLEEPER_PIDFILE = $hangPid }
    $started = Get-Date
    $r = Invoke-Db @("sync", "-Force", "-TimeLimitSeconds", "10") -Env $hangEnv
    $took = ((Get-Date) - $started).TotalSeconds
    Check ($r.code -eq 1 -and $r.out -like "*files ran*sessions failed: no session snapshot this tick: the snapshot script was killed after 4 s*") ("a snapshot that hangs is killed at its share of the limit; the files step ran (" + $r.code + ": " + $r.out.Trim() + ")")
    Check ($took -lt 40) ("   and the tick ended near the limit, not after the child's two minutes (" + [int]$took + " s)")
    $hungPid = 0
    if (Test-Path -LiteralPath $hangPid) { $t = ([System.IO.File]::ReadAllText($hangPid)).Trim(); if ($t -match '^\d+$') { $hungPid = [int]$t } }
    Check ($hungPid -gt 0) "CONTROL: the hanging fixture started and wrote its pid"
    $hungAlive = $true
    if ($hungPid -gt 0) { try { $null = Get-Process -Id $hungPid -ErrorAction Stop } catch { $hungAlive = $false } }
    Check (-not $hungAlive) "   and it was killed through its own pid"
    Check (@(Get-ChildItem -LiteralPath $hordeHome -Filter "fleet-db-sessions-*.snapshot.json" -ErrorAction SilentlyContinue).Count -eq 0) "   and no snapshot file is left in the home"
    # The files step failing does not stop the sessions step: save a ledger that is not there.
    $missingLedger = Join-Path $work "no-such-ledger.jsonl"
    $r = Invoke-Db @("sync", "-Save", "-Ledger", $missingLedger, "-Changelog", $changelog, "-Cards", $cards)
    Check ($r.code -eq 1 -and $r.out -like "*files failed:*; sessions ran, 1 sessions*") ("a files step that fails does not stop the sessions step (" + $r.code + ": " + $r.out.Trim() + ")")
    $state = [System.IO.File]::ReadAllText($stateFile) | ConvertFrom-Json
    Check ($state.files.lastResult -ceq "failed" -and $state.sessions.lastResult -ceq "ok") "   and each records its own result"
    $r = Invoke-Db @("sync", "-Save", "-Ledger", $ledger, "-Changelog", $changelog, "-Cards", $cards)
    Check ($r.code -eq 0 -and $r.out -like "*files ran*; sessions ran*") "the good sources are saved again and both steps run"

    Write-Host ""
    Write-Host "--- the log is bounded ---" -ForegroundColor Cyan
    $filler = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt 14000; $i++) { [void]$filler.Append("2026-01-01T00:00:00Z ok 1 ms | filler line number " + $i + " padded out to a useful length for the size check`n") }
    [System.IO.File]::WriteAllText($logFile, $filler.ToString(), $utf8)
    $big = (New-Object System.IO.FileInfo($logFile)).Length
    Check ($big -gt 1048576) ("CONTROL: the log is past 1 MB before the run (" + $big + " bytes)")
    $r = Invoke-Db @("sync", "-Force")
    $small = (New-Object System.IO.FileInfo($logFile)).Length
    $lines = @(Get-LogLines)
    Check ($r.code -eq 0 -and $small -lt 1048576 -and $small -gt 100000) ("one run cuts it to about its newest half (" + $small + " bytes)")
    Check ($lines[$lines.Count - 1] -match ' ok \d+ ms \| sync: files ran' -and $lines[$lines.Count - 2] -like "*filler line number 13999*" -and -not ($lines[0] -like "*filler line number 0 *")) "   the newest lines stay, this run's line is last, the oldest are gone"

    Write-Host ""
    Write-Host "--- the same under PowerShell 7 ---" -ForegroundColor Cyan
    $pwsh7 = Join-Path $env:ProgramFiles "PowerShell\7\pwsh.exe"
    if (Test-Path -LiteralPath $pwsh7) {
        $r = Invoke-Db @("sync", "-Force") -Shell $pwsh7
        Check ($r.code -eq 0 -and $r.out -like "*sync: files ran*") "db sync -Force under PowerShell 7"
        $sleepRun = Invoke-Db @("sync", "-Force", "-TimeLimitSeconds", "3") -Env $sleepEnv -Shell $pwsh7
        Check ($sleepRun.code -eq 1 -and $sleepRun.out -like "*sync timeout*") "and the time limit under PowerShell 7 (the child and its tree are killed)"
    } else {
        Write-Host "  [SKIP] PowerShell 7 is not installed here" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "--- the scheduled task: listed with -WhatIf, nothing registered ---" -ForegroundColor Cyan
    $regPath = Join-Path $root "fleet-db\register-sync.ps1"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"" + $regPath + "`" -WhatIf"
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables["HORDE_HOME"] = $hordeHome
    $psi.EnvironmentVariables["USERPROFILE"] = $fakeProfile
    $p = [System.Diagnostics.Process]::Start($psi)
    try { $e = $p.StandardError.ReadToEndAsync(); $o = $p.StandardOutput.ReadToEnd(); $p.WaitForExit(); $what = $o + "`n" + $e.Result } finally { $p.Dispose() }
    Check ($what -like "*What if*every 1 min*below normal priority*one instance*db sync; exit*Fleet db sync*") ("-WhatIf lists the one task, its pace and its command (" + $what.Trim() + ")")
    Check ($what -notlike "*registered \Horde*") "   and registers nothing"
    $regText = [System.IO.File]::ReadAllText($regPath)
    # Each pattern is the CODE line, not the header comment that explains it, so a changed setting is not hidden by its own explanation.
    Check ($regText -match '-MultipleInstances IgnoreNew' -and $regText -match '\$settings\.Priority = 7' -and $regText -match '\$limitMinutes = 2' -and $regText -match '-LogonType Interactive -RunLevel Limited' -and $regText.Contains("'--headless `"'") -and $regText -match '\$everyMinutes = 1\b') "the task is single-instance, priority 7, 2-minute limit, every minute, interactive and limited, headless"
    Check ($regText -notmatch 'env:HORDE_HOME = ') "   and no HORDE_HOME is written into its command"
    Check ($regText -match 'Register-ScheduledTask' -and ([regex]::Matches($regText, 'Register-ScheduledTask')).Count -eq 1) "it registers exactly one task"
} finally {
    if ((Split-Path -Leaf $work) -match '\Ahorde-db-sync-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force }
}

Complete-HordeSuite -Success "horde db sync runs one at a time, within its time limit, below normal priority, and leaves a line for every run"
