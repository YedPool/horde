# CAN THE LOCAL GATE SAY WHO HOLDS THE SLOT, NOW AND AFTERWARDS? (T-0445)
#
# tools/HeavySlot.ps1. On the night of 2026-11-07 a bisect gave up after 900 s waiting for the slot and the net's
# pytest-all waited 60 s, and nothing written anywhere could name what held the slot: the holder record lived only
# while its run did, and no waiter read it. Checked here: a waiter names the holder from its record (when it gives up,
# and once after 10 s of waiting); the slot log keeps one line per take, release and give-up, and never the run's
# arguments; the holder record keeps its first three lines as every older reader reads them (one such reader, frozen
# below, still works on the new record); a slot log that cannot be written costs one warning and never the run.
# Every case uses its own slot name and holder file, so this suite never takes or frees the machine's real slot.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest

$gate = Join-Path $root "tools\HeavySlot.ps1"
$shell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-heavy-slot-holder-test-" + [guid]::NewGuid().ToString("N"))
[void][System.IO.Directory]::CreateDirectory($work)
# Every hour is night for these gates (as in test-heavy-slot.ps1): the machine's clock and desk are not read.
$idleHome = Join-Path $work "home"
[void][System.IO.Directory]::CreateDirectory((Join-Path $idleHome "settings"))
[System.IO.File]::WriteAllText((Join-Path $idleHome "settings\idle.json"), '{ "schemaVersion": 1, "settings": { "nightStartHour": 0, "nightEndHour": 24 } }')
$env:HORDE_HOME = $idleHome

[System.IO.File]::WriteAllText((Join-Path $work "sleeper.ps1"), @'
param([string]$Tag, [int]$Seconds, [int]$Code = 0, [string]$Log)
Add-Content -LiteralPath $Log -Value ($Tag + " start " + [DateTime]::UtcNow.Ticks)
Start-Sleep -Seconds $Seconds
Add-Content -LiteralPath $Log -Value ($Tag + " end " + [DateTime]::UtcNow.Ticks)
exit $Code
'@)

# THE OLDER READER, frozen as main had it at b85d565d (Get-HordeHeavySlotLiveRun): older HeavySlot clones and the
# post-merge monitor read the record this way, so the new record must keep its first three lines for them.
function Get-OldReaderLiveRun {
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

function New-Slot { return ("Local\HordeHeavySlotHolderTest-" + [guid]::NewGuid().ToString("N")) }
function Get-HolderPath { param([string]$Slot) return (Join-Path $work ($Slot.Substring(6) + ".holder")) }
function Get-SlotLogPath { param([string]$Slot) return [System.IO.Path]::ChangeExtension((Get-HolderPath $Slot), ".log") }
function Start-Gate {
    param([string]$Slot, [string]$Tag, [int]$Seconds, [string[]]$More = @())
    $log = Join-Path $work ($Tag + ".log")
    $argv = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $gate, "-Worktree", $work, "-Script", "sleeper.ps1",
        "-ScriptArgs", ("-Tag," + $Tag + ",-Seconds," + $Seconds + ",-Log," + $log), "-MinFreeGB", "0",
        "-SlotName", $Slot, "-HolderFile", (Get-HolderPath $Slot), "-Out", (Join-Path $work ($Tag + ".out.txt"))) + $More
    $p = Start-Process -FilePath $shell -ArgumentList $argv -RedirectStandardOutput (Join-Path $work ($Tag + ".gate.txt")) -RedirectStandardError (Join-Path $work ($Tag + ".gate.err")) -NoNewWindow -PassThru
    $null = $p.Handle
    return $p
}
function Read-Shared {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "" }
    $st = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try { return (New-Object System.IO.StreamReader($st)).ReadToEnd() } finally { $st.Dispose() }
}
function Get-GateText { param([string]$Tag) return (Read-Shared (Join-Path $work ($Tag + ".gate.txt"))) }
function Get-Started { param([string]$Tag) return ((Read-Shared (Join-Path $work ($Tag + ".log"))) -match " start ") }
function Wait-For { param([scriptblock]$Until, [int]$Seconds = 30) $c = [System.Diagnostics.Stopwatch]::StartNew(); while (-not (& $Until) -and $c.Elapsed.TotalSeconds -lt $Seconds) { Start-Sleep -Milliseconds 100 }; return [bool](& $Until) }

try {
    Write-Host ""
    Write-Host "--- a waiter that gives up names the holder ---" -ForegroundColor Cyan
    $slot = New-Slot
    $a = Start-Gate -Slot $slot -Tag "holder" -Seconds 8
    Check (Wait-For { Get-Started "holder" }) "the holder's run started"
    $b = Start-Gate -Slot $slot -Tag "quitter" -Seconds 0 -More @("-WaitSeconds", "3")
    $b.WaitForExit()
    $qt = Get-GateText "quitter"
    Check ($b.ExitCode -eq 125) ("the waiter gave up with 125 (" + $b.ExitCode + ")")
    Check ($qt -match "gave up after 3 s waiting for the slot; nothing was run") "CONTROL: it gave up on the slot, in the words it always used"
    Check ($qt -match "heavy-slot: the slot is held by sleeper\.ps1 \(process \d+") "and it names the holder's script and process"
    Check ($qt -match [regex]::Escape("worktree " + $work)) "and the holder's worktree"

    Write-Host ""
    Write-Host "--- the holder record keeps the three lines every older reader reads ---" -ForegroundColor Cyan
    $rec = @((Read-Shared (Get-HolderPath $slot)) -split "`n")
    Check ($rec.Count -ge 5) ("the record has more than the old three lines (" + $rec.Count + ")")
    $old = Get-OldReaderLiveRun -Path (Get-HolderPath $slot)
    Check ($null -ne $old -and $old.script -ceq "sleeper.ps1") "the older reader still finds the live run in the new record, and its script"
    Check ($rec.Count -ge 4 -and $rec[3].Trim() -ceq $work) "line 4 is the worktree"

    $a.WaitForExit()

    Write-Host ""
    Write-Host "--- a waiter names the holder once, after 10 s ---" -ForegroundColor Cyan
    $slot2 = New-Slot
    $a2 = Start-Gate -Slot $slot2 -Tag "longholder" -Seconds 14
    Check (Wait-For { Get-Started "longholder" }) "the holder's run started"
    $b2 = Start-Gate -Slot $slot2 -Tag "patient" -Seconds 0 -More @("-WaitSeconds", "40")
    $b2.WaitForExit(); $a2.WaitForExit()
    $pt = Get-GateText "patient"
    Check ($b2.ExitCode -eq 0) ("the patient waiter ran in the end, exit 0 (" + $b2.ExitCode + ")")
    Check (@([regex]::Matches($pt, "the slot is held by sleeper\.ps1")).Count -eq 1) "it named the holder exactly once while it waited"

    Write-Host ""
    Write-Host "--- the slot log: one line per take, release and give-up, and no arguments ---" -ForegroundColor Cyan
    $log = Read-Shared (Get-SlotLogPath $slot)
    $lines = @($log -split "`r?`n" | Where-Object { $_.Trim() -ne "" })
    Check (@($lines | Where-Object { $_ -match "^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ take pid=\d+ script=sleeper\.ps1 worktree=.+ waited=\d+$" }).Count -eq 1) ("one take line, in the agreed fields (" + ($lines -join " / ") + ")")
    Check (@($lines | Where-Object { $_ -match " release pid=\d+ script=sleeper\.ps1 worktree=.+ waited=\d+ exit=0$" }).Count -eq 1) "one release line, with the run's exit"
    Check (@($lines | Where-Object { $_ -match " gave-up pid=\d+ script=sleeper\.ps1 worktree=.+ waited=\d+ exit=125$" }).Count -eq 1) "one give-up line, with 125"
    Check (@($lines | Where-Object { $_ -match " gave-up .* waited=([3-9]|\d\d+) " }).Count -eq 1) "and the give-up line says how long it waited (3 s or more), not 0"
    Check ($log -notmatch "-Tag|-Seconds|holder\.log|quitter") "no argument of either run is in the log"

    Write-Host ""
    Write-Host "--- a slot log that cannot be written costs one warning, never the run ---" -ForegroundColor Cyan
    $slot3 = New-Slot
    [void][System.IO.Directory]::CreateDirectory((Get-SlotLogPath $slot3))   # a folder where the log file should be
    $t = [System.Diagnostics.Stopwatch]::StartNew()
    $c = Start-Gate -Slot $slot3 -Tag "nolog" -Seconds 0 -More @("-WaitSeconds", "20")
    $c.WaitForExit()
    $nt = Get-GateText "nolog"
    Check ($c.ExitCode -eq 0) ("the run still ran, exit 0 (" + $c.ExitCode + ")")
    Check (@([regex]::Matches($nt, "heavy-slot: WARNING - the slot log")).Count -eq 1) "with exactly one warning, though the take and the release both failed to write"
    Check ($t.Elapsed.TotalSeconds -lt 15) ("and no wait was added (" + [int]$t.Elapsed.TotalSeconds + " s)")
    Check ((@($nt -split "`r?`n" | Where-Object { $_.Trim() -ne "" }))[-1] -ceq "heavy-slot: released exit=0") "the closing line is still last"

    Write-Host ""
    Write-Host "--- the slot log is capped ---" -ForegroundColor Cyan
    $slot4 = New-Slot
    [System.IO.File]::WriteAllText((Get-SlotLogPath $slot4), ("x" * 1100000))
    $d = Start-Gate -Slot $slot4 -Tag "capped" -Seconds 0
    $d.WaitForExit()
    Check ((Test-Path -LiteralPath ((Get-SlotLogPath $slot4) + ".1")) -and (Get-Item -LiteralPath (Get-SlotLogPath $slot4)).Length -lt 10000) "a log over 1 MB is moved aside to .1 and a new one started"
} finally {
    foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { ("" + $_.CommandLine) -like ("*" + $work + "*") })) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "the local gate names who holds the slot when a waiter gives up or waits long, logs every take, release and give-up without arguments, keeps the record older readers read, and a failed log write never costs the run"
