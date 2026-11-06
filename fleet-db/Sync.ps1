# fleet-db/Sync.ps1 - the PowerShell half of `horde db sync` (T-0389, piece 1 of T-0299).
#
# WHY TWO HALVES. The node half (fleet-db/sync.mjs) knows what is due and imports; this half owns what only the
# operating system can promise: that two syncs never run at once, that one never runs past its time limit, that it runs
# below normal priority, and that every run leaves a line to read. The scheduled task ticks every minute
# (fleet-db/register-sync.ps1); this runs the tick.
#
# TWO STEPS IN ONE TICK (T-0409). The node half runs the files step (when due) and the sessions step (every tick). The sessions
# step needs facts only the machine has - the registry, the live panes, the running processes - so BEFORE node starts, this half
# runs fleet-db/SessionSnapshotRun.ps1 as a child of its own (Invoke-HordeDbSyncSnapshot), with its own limit, and hands node the
# file it wrote (--snapshot) or the reason there is none (--snapshot-error). A snapshot that fails or hangs costs the tick its sessions
# step, recorded as failed; it never blocks the files step, and the files step never blocks it. THE ONE TIME LIMIT COVERS BOTH: the
# snapshot gets at most 40 percent of it and node gets what is left of the whole.
#
# SINGLE INSTANCE: an OS-exclusive handle on HORDE_HOME\fleet-db-sync.lock (FileShare.None) is held for the whole run and
# released in finally. If the process dies the OS closes the handle, so there is no stale lock to clean up and no
# pid to check. A tick that cannot open the file says "skipped: a sync is still running", logs it and exits 0: a
# slow sync is not a failure of the next tick. (The task itself is MultipleInstances IgnoreNew; the lock covers a hand
# `horde db sync` racing the task.)
#
# HARD TIME LIMIT: node is started as a child Process and waited for at most -TimeLimitSeconds. On timeout THAT child is
# killed through its own Process object (never by name; with its tree on PowerShell 7). The import is ONE
# transaction (importFleet), so a killed run leaves the database as it was: the half-done work is rolled back by SQLite
# at the next open, from the WAL. The kill is then written down with `sync --note-timeout`, because a killed node cannot
# say so itself. The run log keeps "timeout", and the state keeps lastResult timeout beside an unmoved lastOkAt, so the
# next tick tries again.
#
# THE LOG (HORDE_HOME\logs\fleet-db-sync.log): one ASCII line per run. The scheduled task's own "last result" says nothing
# (conhost --headless exits 0 whatever PowerShell did; see fleet-metrics/register-schedule.ps1), so this log is how a
# person sees that the sync is alive. Bounded: past MaxLogBytes the newest half is kept.
#
# No Set-StrictMode here: this file is dot-sourced. POWERSHELL 5.1: no 2>&1, no $Args/$Home/$PID parameters (CONTRIBUTING 12).

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\FileAtomic.ps1")

function Write-HordeDbSyncLog {
    # One line, appended; the log is cut to its newest half first when it is past -MaxBytes. Never throws: a log
    # that cannot be written (a reader holds it, a full disk) must not turn a good sync into a failed one.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Line, [int]$MaxBytes = 1048576, [switch]$MayCut)
    try {
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path))
        if ($MayCut -and [System.IO.File]::Exists($Path) -and (New-Object System.IO.FileInfo($Path)).Length -gt $MaxBytes) {
            # Only the run that holds the lock cuts, so two cuts never race. A whole-file swap, never an in-place rewrite.
            $all = @([System.IO.File]::ReadAllLines($Path))
            $keep = New-Object System.Collections.Generic.List[string]
            $size = 0
            for ($i = $all.Count - 1; $i -ge 0; $i--) {
                $size += $all[$i].Length + 1
                if ($size -gt ($MaxBytes / 2)) { break }
                $keep.Insert(0, $all[$i])
            }
            $temp = $Path + ".tmp-" + [guid]::NewGuid().ToString("N")
            # A cut that fails (a reader holds the file) must not cost this run its line: the line is appended below regardless.
            try {
                [System.IO.File]::WriteAllText($temp, ((@($keep) -join "`n") + "`n"), (New-Object System.Text.ASCIIEncoding))
                Move-HordeFileAtomic -From $temp -To $Path
            } catch { } finally { if ([System.IO.File]::Exists($temp)) { [System.IO.File]::Delete($temp) } }
        }
        [System.IO.File]::AppendAllText($Path, ($Line + "`n"), (New-Object System.Text.ASCIIEncoding))
    } catch { }
}

function ConvertTo-HordeDbSyncText {
    # One short ASCII line from any text: line breaks and anything outside printable ASCII become a space or "?".
    param([AllowEmptyString()][string]$Text, [int]$Max = 300)
    $one = (("" + $Text) -replace "[\r\n]+", " ") -replace "[^\x20-\x7E]", "?"
    $one = $one.Trim()
    if ($one.Length -gt $Max) { $one = $one.Substring(0, $Max) }
    return $one
}

function Start-HordeDbSyncNode {
    # Starts node on a script with arguments; below normal priority at once. Returns the Process, with its two
    # output streams already being read (a full pipe would stall the child).
    param([Parameter(Mandatory = $true)][string]$NodePath, [Parameter(Mandatory = $true)][string]$Script, [string[]]$NodeArgs = @(), [Parameter(Mandatory = $true)][string]$HordeHome)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $NodePath
    # Backslashes just before the closing quote are doubled, or a path saved as C:\x\ would escape that quote and swallow the next argument.
    $quoted = @($NodeArgs | ForEach-Object { '"' + ($_ -replace '(\\+)$', '$1$1') + '"' })
    $psi.Arguments = '"' + $Script + '"' + $(if ($quoted.Count -gt 0) { " " + ($quoted -join " ") } else { "" })
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables["HORDE_HOME"] = $HordeHome
    $p = [System.Diagnostics.Process]::Start($psi)
    # The child may already have exited (a refusal takes milliseconds); then there is nothing to lower.
    try { $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal } catch { }
    return [pscustomobject]@{ process = $p; outTask = $p.StandardOutput.ReadToEndAsync(); errTask = $p.StandardError.ReadToEndAsync() }
}

function Invoke-HordeDbSyncSnapshot {
    # Runs the snapshot script as a child with a limit and returns { file; error }: the file it wrote, or the one-line reason
    # there is none. On a timeout THAT child is killed through its own Process object (never by name; with its tree on
    # PowerShell 7). The script runs in the same PowerShell as this one (the 5.1 and 7 traps differ, so one tick must not mix them).
    param([Parameter(Mandatory = $true)][string]$Script, [Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][int]$LimitSeconds)
    $file = Join-Path $HordeHome ("fleet-db-sessions-" + [guid]::NewGuid().ToString("N") + ".snapshot.json")
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $self = [System.Diagnostics.Process]::GetCurrentProcess()
    try { $psi.FileName = $self.MainModule.FileName } finally { $self.Dispose() }
    $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $Script + '" -Out "' + $file + '"'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables["HORDE_HOME"] = $HordeHome
    $p = $null
    try { $p = [System.Diagnostics.Process]::Start($psi) } catch { return [pscustomobject]@{ file = ""; error = (ConvertTo-HordeDbSyncText ("the snapshot script could not be started: " + $_.Exception.Message)) } }
    try {
        try { $p.PriorityClass = "BelowNormal" } catch { }
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($LimitSeconds * 1000)) {
            try { if ($null -ne $p.GetType().GetMethod("Kill", [Type[]]@([bool]))) { $p.Kill($true) } else { $p.Kill() } } catch { }
            [void]$p.WaitForExit(5000)
            if ([System.IO.File]::Exists($file)) { [System.IO.File]::Delete($file) }
            # A kill between the child's temp write and its move leaves the temp file, and this runs every minute.
            foreach ($left in [System.IO.Directory]::GetFiles($HordeHome, ([System.IO.Path]::GetFileName($file) + ".tmp-*"))) { try { [System.IO.File]::Delete($left) } catch { } }
            return [pscustomobject]@{ file = ""; error = ("the snapshot script was killed after " + $LimitSeconds + " s") }
        }
        $p.WaitForExit()
        if ($p.ExitCode -eq 0 -and [System.IO.File]::Exists($file)) { return [pscustomobject]@{ file = $file; error = "" } }
        $why = (("" + $errTask.Result) -split "\r?\n" | Where-Object { $_.Trim() -ne "" } | Select-Object -Last 1)
        if (-not $why) { $why = "the snapshot script stopped with exit code " + $p.ExitCode }
        return [pscustomobject]@{ file = ""; error = (ConvertTo-HordeDbSyncText $why 200) }
    } finally { $p.Dispose() }
}

function Invoke-HordeDbSync {
    # One tick. Returns { code; outcome; lines } - outcome is ok, skipped, failed or timeout; lines is what to print.
    # code: 0 ok or skipped, 1 failed or timed out or refused.
    param(
        [Parameter(Mandatory = $true)][string]$HordeHome,
        [Parameter(Mandatory = $true)][string]$NodePath,
        [Parameter(Mandatory = $true)][string]$CliScript,
        [string]$SyncScript = "",
        [string]$SnapshotScript = "",
        [string[]]$SyncArgs = @(),
        [int]$TimeLimitSeconds = 50,
        [int]$MaxLogBytes = 1048576
    )
    $log = Join-Path (Join-Path $HordeHome "logs") "fleet-db-sync.log"
    $stamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    # THE TEST SEAM: a suite points the sync run at a fixture script (one that sleeps) to prove the time limit; the
    # `--note-timeout` call below always uses the real script.
    if ($SyncScript -eq "") { $SyncScript = $CliScript }
    # The same for the snapshot: a suite points it at a fixture that writes a fake one (no real terminal is ever asked in a test).
    if ($SnapshotScript -eq "") { $SnapshotScript = Join-Path $PSScriptRoot "SessionSnapshotRun.ps1" }
    $lock = $null
    $snapshot = $null
    try {
        # The folder first: a missing one would answer the open below with an IOException too (DirectoryNotFound), and be taken for a held lock.
        [void][System.IO.Directory]::CreateDirectory($HordeHome)
        try {
            $lock = [System.IO.File]::Open((Join-Path $HordeHome "fleet-db-sync.lock"), [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        } catch {
            # A method call wraps what .NET threw; the sharing violation is the inner IOException with Windows error 32 (or 33, a
            # lock violation). Anything else is not "a sync is running": a broken home must fail, not look like a busy sync forever.
            $thrown = $_.Exception
            if ($null -ne $thrown.InnerException) { $thrown = $thrown.InnerException }
            if ($thrown -isnot [System.IO.IOException] -or @(32, 33) -notcontains ($thrown.HResult -band 0xFFFF)) { throw }
            Write-HordeDbSyncLog -Path $log -Line ($stamp + " skipped 0 ms | a sync is still running") -MaxBytes $MaxLogBytes
            return [pscustomobject]@{ code = 0; outcome = "skipped"; lines = @("skipped: a sync is still running") }
        }
        # The snapshot first, inside the same limit: at most 40 percent of it, and node gets what is left.
        $snapshot = Invoke-HordeDbSyncSnapshot -Script $SnapshotScript -HordeHome $HordeHome -LimitSeconds ([Math]::Max(1, [int][Math]::Floor($TimeLimitSeconds * 0.4)))
        $snapArgs = @("--snapshot-error", $(if ($snapshot.error -ne "") { $snapshot.error -replace '"', "'" } else { "no snapshot was made" }))
        if ($snapshot.file -ne "") { $snapArgs = @("--snapshot", $snapshot.file) }
        $leftMs = [Math]::Max(1000, ($TimeLimitSeconds * 1000) - [int]$watch.ElapsedMilliseconds)
        $run = Start-HordeDbSyncNode -NodePath $NodePath -Script $SyncScript -NodeArgs (@("sync") + $SyncArgs + $snapArgs) -HordeHome $HordeHome
        $p = $run.process
        try {
            if (-not $p.WaitForExit($leftMs)) {
                # Only the child started above. On PowerShell 7 its tree goes with it; Windows PowerShell 5.1 has no such overload.
                try { if ($p.GetType().GetMethod("Kill", [Type[]]@([bool]))) { $p.Kill($true) } else { $p.Kill() } } catch { }
                [void]$p.WaitForExit(5000)
                $ms = [int]$watch.ElapsedMilliseconds
                $note = Start-HordeDbSyncNode -NodePath $NodePath -Script $CliScript -NodeArgs @("sync", "--note-timeout", ("" + $ms)) -HordeHome $HordeHome
                try { if (-not $note.process.WaitForExit(15000)) { try { $note.process.Kill() } catch { } } } finally { $note.process.Dispose() }
                $why = "killed after " + $TimeLimitSeconds + " s; the import is one transaction, so the database is unchanged"
                Write-HordeDbSyncLog -Path $log -Line ($stamp + " timeout " + $ms + " ms | " + $why) -MaxBytes $MaxLogBytes -MayCut
                return [pscustomobject]@{ code = 1; outcome = "timeout"; lines = @("fleet.db: sync timeout: " + $why) }
            }
            $p.WaitForExit()
            $ms = [int]$watch.ElapsedMilliseconds
            $said = (("" + $run.outTask.Result) -split "\r?\n" | Where-Object { $_ -match '^sync: ' } | Select-Object -Last 1)
            if ($p.ExitCode -eq 0 -and $said) {
                Write-HordeDbSyncLog -Path $log -Line ($stamp + " ok " + $ms + " ms | " + (ConvertTo-HordeDbSyncText $said)) -MaxBytes $MaxLogBytes -MayCut
                return [pscustomobject]@{ code = 0; outcome = "ok"; lines = @(ConvertTo-HordeDbSyncText $said) }
            }
            # The node half says its reason on a line of its own ("fleet.db: ..."); a crash or warning printed around it is not the reason.
            $why = (("" + $run.errTask.Result) -split "\r?\n" | Where-Object { $_ -match '^fleet\.db' } | Select-Object -Last 1)
            if (-not $why) { $why = "fleet.db: the sync stopped with exit code " + $p.ExitCode + " (fleet.db needs Node.js 24 or later)" }
            Write-HordeDbSyncLog -Path $log -Line ($stamp + " failed " + $ms + " ms | " + (ConvertTo-HordeDbSyncText $why)) -MaxBytes $MaxLogBytes -MayCut
            return [pscustomobject]@{ code = 1; outcome = "failed"; lines = @(ConvertTo-HordeDbSyncText $why) }
        } finally {
            $p.Dispose()
        }
    } finally {
        # Here, not with the child: node failing to start must not leave one snapshot file a minute in the home.
        if ($null -ne $snapshot -and $snapshot.file -ne "" -and [System.IO.File]::Exists($snapshot.file)) { try { [System.IO.File]::Delete($snapshot.file) } catch { } }
        if ($null -ne $lock) { $lock.Dispose() }
    }
}
