# DOES THE LOCAL GATE RUN ONE HEAVY RUN AT A TIME, AND NEVER HANG OR LEAVE A RUN BEHIND?
#
# tools/HeavySlot.ps1 (CONTRIBUTING 15, rule 5). Its failure-case matrix (rule 7: gates get one before
# rollout): pass and fail pass the run's code through; two runs never overlap; a holder killed with its
# run still going does not let the next run start until that run ends; a slot held too long, and memory
# never free, each give up in plain words instead of waiting for ever; a run past its time is ended with
# every process it started; a missing script runs nothing. Every case uses its own slot name and holder
# file, so this suite never takes or frees the machine's real slot.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest

$gate = Join-Path $root "tools\HeavySlot.ps1"
$shell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-heavy-slot-test-" + [guid]::NewGuid().ToString("N"))
[void][System.IO.Directory]::CreateDirectory($work)

# The fixture run: writes "<tag> start <ticks>", sleeps, writes "<tag> end <ticks>", exits -Code.
[System.IO.File]::WriteAllText((Join-Path $work "sleeper.ps1"), @'
param([string]$Tag, [int]$Seconds, [int]$Code = 0, [string]$Log)
Add-Content -LiteralPath $Log -Value ($Tag + " start " + [DateTime]::UtcNow.Ticks)
Start-Sleep -Seconds $Seconds
Add-Content -LiteralPath $Log -Value ($Tag + " end " + [DateTime]::UtcNow.Ticks)
exit $Code
'@)

function New-Slot { return ("Local\HordeHeavySlotTest-" + [guid]::NewGuid().ToString("N")) }
function Start-Gate {
    # The gate in its own process, as an agent starts it: the process, with its output at <work>\<Tag>.gate.txt.
    param([string]$Slot, [string]$Tag, [int]$Seconds, [int]$Code = 0, [string[]]$More = @(), [string]$MinFreeGB = "0")
    $log = Join-Path $work ($Tag + ".log")
    $argv = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $gate, "-Worktree", $work, "-Script", "sleeper.ps1",
        "-ScriptArgs", ("-Tag," + $Tag + ",-Seconds," + $Seconds + ",-Code," + $Code + ",-Log," + $log), "-MinFreeGB", $MinFreeGB,
        "-SlotName", $Slot, "-HolderFile", (Join-Path $work ($Slot.Substring(6) + ".holder")), "-Out", (Join-Path $work ($Tag + ".out.txt"))) + $More
    $p = Start-Process -FilePath $shell -ArgumentList $argv -RedirectStandardOutput (Join-Path $work ($Tag + ".gate.txt")) -RedirectStandardError (Join-Path $work ($Tag + ".gate.err")) -NoNewWindow -PassThru
    $null = $p.Handle
    return $p
}
function Get-Times {
    # { start; end } of a fixture run, from its log, as ticks; 0 for a line not written.
    param([string]$Tag)
    $log = Join-Path $work ($Tag + ".log")
    $s = [long]0; $e = [long]0
    if (Test-Path -LiteralPath $log) { foreach ($l in @(Get-Content -LiteralPath $log)) { $w = $l -split " "; if ($w[1] -eq "start") { $s = [long]$w[2] } elseif ($w[1] -eq "end") { $e = [long]$w[2] } } }
    return [pscustomobject]@{ start = $s; end = $e }
}
function Get-GateText {
    # Read with sharing, as a run left running may still hold the file the gate's output went to.
    param([string]$Tag)
    $f = Join-Path $work ($Tag + ".gate.txt")
    if (-not (Test-Path -LiteralPath $f)) { return "" }
    $st = New-Object System.IO.FileStream($f, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try { return (New-Object System.IO.StreamReader($st)).ReadToEnd() } finally { $st.Dispose() }
}
function Get-LastLine { param([string]$Tag) $l = @((Get-GateText $Tag) -split "`r?`n" | Where-Object { $_.Trim() -ne "" }); if ($l.Count -eq 0) { return "" } return $l[-1] }
function Wait-For { param([scriptblock]$Until, [int]$Seconds = 30) $c = [System.Diagnostics.Stopwatch]::StartNew(); while (-not (& $Until) -and $c.Elapsed.TotalSeconds -lt $Seconds) { Start-Sleep -Milliseconds 100 }; return [bool](& $Until) }

try {
    Write-Host ""
    Write-Host "--- a run's own code comes through, and the closing line names it ---" -ForegroundColor Cyan
    $slot = New-Slot
    $p = Start-Gate -Slot $slot -Tag "pass" -Seconds 0
    $p.WaitForExit()
    Check ($p.ExitCode -eq 0) ("a passing run ends the gate with 0 (" + $p.ExitCode + ")")
    Check ((Get-LastLine "pass") -ceq "heavy-slot: released exit=0") ("its last line is the closing line (" + (Get-LastLine "pass") + ")")
    $p = Start-Gate -Slot $slot -Tag "fail" -Seconds 0 -Code 3
    $p.WaitForExit()
    Check ($p.ExitCode -eq 3) ("a run that exits 3 ends the gate with 3 (" + $p.ExitCode + ")")
    Check ((Get-LastLine "fail") -ceq "heavy-slot: released exit=3") "and its closing line says 3"

    Write-Host ""
    Write-Host "--- a missing script runs nothing ---" -ForegroundColor Cyan
    $argv = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $gate, "-Worktree", $work, "-Script", "no-such-suite.ps1", "-SlotName", (New-Slot), "-HolderFile", (Join-Path $work "none.holder"))
    $p = Start-Process -FilePath $shell -ArgumentList $argv -RedirectStandardOutput (Join-Path $work "missing.gate.txt") -RedirectStandardError (Join-Path $work "missing.gate.err") -NoNewWindow -PassThru
    $null = $p.Handle; $p.WaitForExit()
    Check ($p.ExitCode -eq 126) ("exit 126 (" + $p.ExitCode + ")")
    Check ((Get-GateText "missing") -match "there is no script") "it says there is no such script"

    Write-Host ""
    Write-Host "--- two runs never overlap ---" -ForegroundColor Cyan
    # CONTROL: the same two runs started directly DO overlap, so the check below can fail.
    $c1 = Start-Process -FilePath $shell -ArgumentList @("-NoProfile", "-File", (Join-Path $work "sleeper.ps1"), "-Tag", "ctl1", "-Seconds", "3", "-Log", (Join-Path $work "ctl1.log")) -NoNewWindow -PassThru
    $c2 = Start-Process -FilePath $shell -ArgumentList @("-NoProfile", "-File", (Join-Path $work "sleeper.ps1"), "-Tag", "ctl2", "-Seconds", "3", "-Log", (Join-Path $work "ctl2.log")) -NoNewWindow -PassThru
    $c1.WaitForExit(); $c2.WaitForExit()
    $t1 = Get-Times "ctl1"; $t2 = Get-Times "ctl2"
    Check ($t1.start -lt $t2.end -and $t2.start -lt $t1.end) "CONTROL: started directly, the two runs overlap"
    $slot = New-Slot
    $g1 = Start-Gate -Slot $slot -Tag "one" -Seconds 3
    $g2 = Start-Gate -Slot $slot -Tag "two" -Seconds 3
    $g1.WaitForExit(); $g2.WaitForExit()
    $t1 = Get-Times "one"; $t2 = Get-Times "two"
    Check ($t1.end -gt 0 -and $t2.end -gt 0) "through the gate, both runs ran to their end"
    Check ($t1.end -le $t2.start -or $t2.end -le $t1.start) "and one ended before the other started"
    Check (((Get-GateText "one") + (Get-GateText "two")) -notmatch "killed") "a slot released by its holder is never taken for a killed one"

    Write-Host ""
    Write-Host "--- a record naming a reused process id is not a run still going ---" -ForegroundColor Cyan
    $slot = New-Slot
    # A live process (this suite) with a start time that is not its own: the id was reused.
    [System.IO.File]::WriteAllText((Join-Path $work ($slot.Substring(6) + ".holder")), ("" + $PID + "`n" + "12345`n" + "other.ps1`n"))
    $g = Start-Gate -Slot $slot -Tag "reused" -Seconds 0 -More @("-WaitSeconds", "5")
    $g.WaitForExit()
    Check ($g.ExitCode -eq 0) ("the run went ahead, exit 0 (" + $g.ExitCode + ")")
    Check ((Get-GateText "reused") -notmatch "still going") "and did not wait on a process that only shares the id"

    Write-Host ""
    Write-Host "--- a killed holder's run still going holds back the next run ---" -ForegroundColor Cyan
    $slot = New-Slot
    $k1 = Start-Gate -Slot $slot -Tag "orphan" -Seconds 6
    Check (Wait-For { (Get-Times "orphan").start -gt 0 }) "the first run started"
    # Kill the GATE only, as a closed window or a killed agent does: its run keeps going.
    Stop-Process -Id $k1.Id -Force
    $k1.WaitForExit()
    $k2 = Start-Gate -Slot $slot -Tag "after" -Seconds 0
    $k2.WaitForExit()
    $to = Get-Times "orphan"; $ta = Get-Times "after"
    Check ($to.end -gt 0) "CONTROL: the killed gate's run went on to its end"
    Check ($ta.start -ge $to.end) "the next run started only after that run ended"
    Check ((Get-GateText "after") -match "killed holder's run is still going") "and it said why it waited"
    Check ($k2.ExitCode -eq 0) ("and then ran, exit 0 (" + $k2.ExitCode + ")")

    Write-Host ""
    Write-Host "--- a slot held too long, and memory never free, give up in words ---" -ForegroundColor Cyan
    $slot = New-Slot
    $h1 = Start-Gate -Slot $slot -Tag "holder" -Seconds 8
    Check (Wait-For { (Get-Times "holder").start -gt 0 }) "a run holds the slot"
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $w = Start-Gate -Slot $slot -Tag "waiter" -Seconds 0 -More @("-WaitSeconds", "2")
    $w.WaitForExit()
    Check ($w.ExitCode -eq 125) ("a run that cannot have the slot in 2 s ends with 125 (" + $w.ExitCode + ")")
    Check ($clock.Elapsed.TotalSeconds -lt 7) ("within its wait, not the holder's run (" + [int]$clock.Elapsed.TotalSeconds + " s)")
    Check ((Get-GateText "waiter") -match "gave up after 2 s waiting for the slot") "it says it gave up waiting for the slot"
    Check ((Get-Times "waiter").start -eq 0) "and its run never started"
    $h1.WaitForExit()
    $m = Start-Gate -Slot $slot -Tag "memory" -Seconds 0 -MinFreeGB "1000000" -More @("-WaitSeconds", "2")
    $m.WaitForExit()
    Check ($m.ExitCode -eq 125) ("a run that cannot have the memory in 2 s ends with 125 (" + $m.ExitCode + ")")
    Check ((Get-GateText "memory") -match "waiting for 1000000 GB of free memory") "it says it gave up waiting for memory"
    $n = Start-Gate -Slot $slot -Tag "next" -Seconds 0 -More @("-WaitSeconds", "5")
    $n.WaitForExit()
    Check ($n.ExitCode -eq 0) "the slot was released after the memory refusal: the next run had it"

    Write-Host ""
    Write-Host "--- a run past its time is ended with what it started ---" -ForegroundColor Cyan
    $slot = New-Slot
    $r = Start-Gate -Slot $slot -Tag "long" -Seconds 30 -More @("-RunSeconds", "2")
    $r.WaitForExit()
    Check ($r.ExitCode -eq 124) ("a run past 2 s ends the gate with 124 (" + $r.ExitCode + ")")
    Check ((Get-GateText "long") -match "TIMEOUT") "it says TIMEOUT"
    Start-Sleep -Seconds 1
    $left = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { ("" + $_.CommandLine) -like ("*-Tag long*") })
    Check ($left.Count -eq 0) ("and the run's process is gone (" + $left.Count + " left)")
    Check ((Get-Times "long").end -eq 0) "it never reached its end"
} finally {
    foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { ("" + $_.CommandLine) -like ("*" + $work + "*") })) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "the local gate runs one heavy run at a time, waits for a killed holder's run, gives up in words, and ends a run past its time"
