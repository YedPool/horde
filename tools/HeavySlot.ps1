# tools/HeavySlot.ps1 - THE LOCAL GATE: one heavy test run at a time on this machine, across every
# session and agent that runs one (CONTRIBUTING 15, rule 5: "locally, one run at a time, through the
# local gate, which holds one lock across every agent on the machine").
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\HeavySlot.ps1 -Script <suite, relative to -Worktree> [-Worktree <path>]
#       [-ScriptArgs <a>,<b>] [-Out <log>] [-MinFreeGB 3] [-WaitSeconds 7200] [-RunSeconds 3600]
#   -ScriptArgs is split on commas, and an argument with a space is quoted, so an argument may not hold a
#   comma or a double quote: such a run takes its values from a file or its own settings instead.
#
# Development tooling, not part of the engine. test/test-heavy-slot.ps1 is its suite.
#
# WHY (2026-10-14). Several agents each waited for free memory, then all started together when it freed,
# and this PC sat at 6 to 12 percent free all evening; two heavy runs started in the same minute while
# the founder's own sessions shared the machine. Waiting for memory is not enough: the WAIT must be one
# queue. So the slot is a machine-wide named mutex, and memory is waited for only by its holder.
#
# WHAT IT DOES, in order:
#   1. waits for the mutex -SlotName, up to -WaitSeconds;
#   2. A HOLDER THAT WAS KILLED leaves the mutex abandoned, and Windows hands it to the next waiter. Its
#      run may still be going: killing a PowerShell does not kill the child it started. So the holder
#      writes a record (-HolderFile: the run's process id, start time and script) when it starts the
#      run, and a later holder that finds a record of a run still alive - the same id AND the same
#      start time, so a reused id is not mistaken for it - waits for that run to end first;
#   3. waits, still holding the slot, until free memory is at least -MinFreeGB;
#   4. runs the script - a .ps1 under Windows PowerShell 5.1, a .mjs under node - with standard input
#      closed (an empty file) and PSModulePath cleared, output to -Out, for at most -RunSeconds; past
#      that its whole process tree is ended and the run is reported TIMEOUT;
#   5. ALWAYS, in finally (an error, Ctrl+C, a timeout): a run still alive is ended with its tree, so the
#      slot is never released while a run of it goes on; the record is removed; the mutex is released.
# Every exit says why in plain words, and the LAST line is always "heavy-slot: released exit=<n>"
# (CONTRIBUTING 15, rule 7: a run without its closing line proves nothing).
#
# EXIT CODES: the script's own; 124 the run passed -RunSeconds; 125 the slot, a killed holder's run or
# the memory was not had within -WaitSeconds (nothing was run); 126 the script is not there.
#
# A holder killed with taskkill /F runs no finally: its mutex is abandoned (step 2 covers its run), and
# its record stays until the next holder reads and replaces it. A suite uses its own -SlotName and
# -HolderFile, so a test never takes or frees the machine's real slot.

param(
    [Parameter(Mandatory = $true)][string]$Script,
    [string]$Worktree = "",
    [string[]]$ScriptArgs = @(),
    [string]$Out = "",
    [double]$MinFreeGB = 3,
    [int]$WaitSeconds = 7200,
    [int]$RunSeconds = 3600,
    [string]$SlotName = "Global\HordeHeavySlot",
    [string]$HolderFile = ""
)
$ErrorActionPreference = "Stop"

function Get-HordeHeavySlotFreeGB { return [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 2) }

function Get-HordeHeavySlotLiveRun {
    # The run a holder record names, if that very process is still alive: { pid; script } or $null.
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $rec = $null
    try { $rec = [System.IO.File]::ReadAllText($Path) -split "`n" } catch { return $null }
    if (@($rec).Count -lt 3) { return $null }
    $runPid = 0; $ticks = [long]0
    if (-not [int]::TryParse($rec[0].Trim(), [ref]$runPid) -or -not [long]::TryParse($rec[1].Trim(), [ref]$ticks)) { return $null }
    $p = Get-Process -Id $runPid -ErrorAction SilentlyContinue
    if ($null -eq $p) { return $null }
    try { if ($p.StartTime.ToUniversalTime().Ticks -ne $ticks) { return $null } } catch { return $null }
    return [pscustomobject]@{ pid = $runPid; script = $rec[2].Trim(); process = $p }
}

function Stop-HordeHeavySlotTree {
    # End a process and every process it started, by its id.
    param([int]$Id)
    # Started as a process, not called: under Windows PowerShell 5.1 a native command's error stream,
    # redirected, is raised as an error, and taskkill writes there for a process already gone.
    $null = Start-Process -FilePath (Join-Path $env:SystemRoot "System32\taskkill.exe") -ArgumentList @("/T", "/F", "/PID", ("" + $Id)) -WindowStyle Hidden -Wait -PassThru
}

if ($Worktree -eq "") { $Worktree = (Get-Location).Path }
# powershell -File hands a list to a [string[]] as ONE string, so a comma separates the run's arguments.
$ScriptArgs = @(@($ScriptArgs) | ForEach-Object { ("" + $_) -split "," } | Where-Object { $_ -ne "" })
# Start-Process joins its arguments with spaces and quotes none of them: an argument with a space is quoted here.
function ConvertTo-HordeHeavySlotArg { param([string]$A) if ($A -match '\s') { return ('"' + $A + '"') } return $A }
$name = ($SlotName -replace '[^A-Za-z0-9-]', '-')
if ($HolderFile -eq "") { $HolderFile = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-heavy-slot-" + $name + ".txt") }
$path = Join-Path $Worktree $Script
if ($Out -eq "") { $Out = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-heavy-slot-" + [System.IO.Path]::GetFileNameWithoutExtension($Script) + ".txt") }

# The body is a block, so each early exit is a return from it, and the code and the closing line come
# after it whatever happened. Its state lives in the script scope, where finally reads it.
$script:code = 125
$script:mutex = $null
$script:held = $false
$script:run = $null
$clock = [System.Diagnostics.Stopwatch]::StartNew()
$left = { [int][math]::Max(0, $WaitSeconds - $clock.Elapsed.TotalSeconds) }
$main = {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $script:code = 126; Write-Output ("heavy-slot: there is no script " + $path + "; nothing was run"); return }
    $script:mutex = New-Object System.Threading.Mutex($false, $SlotName)
    Write-Output ("heavy-slot: waiting for the slot " + $SlotName + " for " + $Script)
    try { $script:held = $mutex.WaitOne([int](& $left) * 1000) }
    catch [System.Threading.AbandonedMutexException] { $script:held = $true; Write-Output "heavy-slot: the last holder was killed before it released the slot" }
    if (-not $held) { Write-Output ("heavy-slot: gave up after " + $WaitSeconds + " s waiting for the slot; nothing was run"); return }

    $orphan = Get-HordeHeavySlotLiveRun -Path $HolderFile
    if ($null -ne $orphan) {
        Write-Output ("heavy-slot: a killed holder's run is still going (" + $orphan.script + ", process " + $orphan.pid + "): waiting for it to end first")
        if (-not $orphan.process.WaitForExit([int](& $left) * 1000)) { Write-Output ("heavy-slot: gave up after " + $WaitSeconds + " s waiting for that run to end; nothing was run"); return }
    }

    $said = $false
    while ((Get-HordeHeavySlotFreeGB) -lt $MinFreeGB) {
        if ((& $left) -le 0) { Write-Output ("heavy-slot: gave up after " + $WaitSeconds + " s waiting for " + $MinFreeGB + " GB of free memory (now " + (Get-HordeHeavySlotFreeGB) + "); nothing was run"); return }
        if (-not $said) { Write-Output ("heavy-slot: holding the slot, waiting for " + $MinFreeGB + " GB of free memory (now " + (Get-HordeHeavySlotFreeGB) + ")"); $said = $true }
        Start-Sleep -Milliseconds ([math]::Min(5000, [math]::Max(200, (& $left) * 1000)))
    }

    Write-Output ("heavy-slot: running " + $Script + " with " + (Get-HordeHeavySlotFreeGB) + " GB free, output in " + $Out)
    $empty = Join-Path ([System.IO.Path]::GetTempPath()) "horde-heavy-slot-empty-stdin.txt"
    [System.IO.File]::WriteAllText($empty, "")
    $env:PSModulePath = ""
    if ($Script -like "*.mjs") { $file = "node"; $argv = @($path) + @($ScriptArgs) }
    else { $file = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"; $argv = @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $path) + @($ScriptArgs) }
    $argv = @($argv | ForEach-Object { ConvertTo-HordeHeavySlotArg $_ })
    $script:run = Start-Process -FilePath $file -ArgumentList $argv -WorkingDirectory $Worktree -RedirectStandardOutput $Out -RedirectStandardError ($Out + ".err") -RedirectStandardInput $empty -NoNewWindow -PassThru
    # Read the handle at once: a Process from Start-Process -PassThru that nobody opened a handle on
    # can report no ExitCode once it has exited (Windows PowerShell 5.1).
    $null = $run.Handle
    [System.IO.File]::WriteAllText($HolderFile, ("" + $run.Id + "`n" + $run.StartTime.ToUniversalTime().Ticks + "`n" + $Script + "`n"))
    # Past its time, the run is ended by finally below, with every process it started - one place ends
    # every run still alive, whatever the way out.
    if (-not $run.WaitForExit($RunSeconds * 1000)) {
        $script:code = 124
        Write-Output ("heavy-slot: TIMEOUT - " + $Script + " ran past " + $RunSeconds + " s and was ended with every process it started")
        return
    }
    $run.WaitForExit()
    $script:code = $run.ExitCode
}
try { & $main } finally {
    if ($null -ne $run -and -not $run.HasExited) { Stop-HordeHeavySlotTree -Id $run.Id; $null = $run.WaitForExit(10000) }
    if ($null -ne $run) {
        try { if (Test-Path -LiteralPath $HolderFile) { $first = ([System.IO.File]::ReadAllText($HolderFile) -split "`n")[0].Trim(); if ($first -eq ("" + $run.Id)) { Remove-Item -LiteralPath $HolderFile -Force } } } catch { }
    }
    if ($held) { $mutex.ReleaseMutex() }
    if ($null -ne $mutex) { $mutex.Dispose() }
    Write-Output ("heavy-slot: released exit=" + $code)
}
exit $code
