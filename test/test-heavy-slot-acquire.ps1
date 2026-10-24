# DOES THE GATE WAIT FIRST AND TAKE LAST, AND HOLD NOTHING WHILE IT WAITS?
#
# core/HeavySlotAcquire.ps1 (T-0331). The incident: on 2026-10-22 a gate took the one heavy slot and then
# waited 2.5 hours for memory the box did not have, so every lane's heavy queue stood still behind it. This
# suite drives the acquire logic with a FAKE clock, FAKE memory, a FAKE idle answer and a FAKE slot, so no real
# time passes and every path is reached: the slot is never taken while memory is below the floor or the PC
# is busy; a slot taken just before the memory fell or the person sat down is RELEASED, not held; and
# -WaitSeconds bounds idle, memory and slot together, with the slot free at the end of every timeout.
# test/test-heavy-slot.ps1 is the real gate, in processes of its own.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\HeavySlotAcquire.ps1")

# The world. t is seconds on the fake clock; Sleep and a slot wait that fails both advance it.
# memory and idle are scripts of t (and of how many times they were asked), so a test says WHEN things change.
function New-World {
    param([scriptblock]$Memory = { 100 }, [scriptblock]$Idle = { $true }, [bool]$SlotBusy = $false, [double]$SlotFreeAt = 0, [scriptblock]$Commit = { 100 })
    $script:world = @{ t = 0.0; memory = $Memory; idle = $Idle; slotBusy = $SlotBusy; slotFreeAt = $SlotFreeAt; held = $false; commit = $Commit
        takes = 0; releases = 0; takesWhileLow = 0; takesWhileBusy = 0; takesWhileCommitLow = 0; sleeps = 0; memAsks = 0; idleAsks = 0; commitAsks = 0; said = @() }
}
function Run-Acquire {
    # -CommitFloor 0 (the default) is every existing caller: the commit getter is passed but must never be asked.
    param([double]$Floor = 4, [int]$Wait = 7200, [double]$CommitFloor = 0)
    $script:commitFloor = $CommitFloor
    return (Invoke-HordeHeavySlotAcquire -MinFreeGB $Floor -MinCommitHeadroomGB $CommitFloor -WaitSeconds $Wait -SliceMs 500 `
        -GetCommitHeadroomGB { $script:world.commitAsks++; return [double](& $script:world.commit $script:world.t $script:world.commitAsks) } `
        -GetIdle {
            $script:world.idleAsks++
            [pscustomobject]@{ allowed = [bool](& $script:world.idle $script:world.t $script:world.idleAsks); needSeconds = 600; time = "12:00:00"; why = "busy" }
        } `
        -GetFreeGB { $script:world.memAsks++; return [double](& $script:world.memory $script:world.t $script:world.memAsks) } `
        -TrySlot {
            param($ms)
            $w = $script:world
            $busy = $w.slotBusy -and $w.t -lt $w.slotFreeAt
            if ($busy) { $w.t += $ms / 1000.0; return $false }
            $w.held = $true; $w.takes++
            if ([double](& $w.memory $w.t ($w.memAsks + 1)) -lt $script:floor) { $w.takesWhileLow++ }
            if (-not [bool](& $w.idle $w.t ($w.idleAsks + 1))) { $w.takesWhileBusy++ }
            if ($script:commitFloor -gt 0 -and [double](& $w.commit $w.t ($w.commitAsks + 1)) -lt $script:commitFloor) { $w.takesWhileCommitLow++ }
            return $true
        } `
        -ReleaseSlot { $script:world.held = $false; $script:world.releases++ } `
        -Elapsed { $script:world.t } `
        -Sleep { param($ms) $script:world.sleeps++; $script:world.t += $ms / 1000.0 } `
        -Say { param($line) $script:world.said += $line })
}
$script:floor = 4

Write-Host ""
Write-Host "--- everything fine: the slot is taken at once, with no wait ---" -ForegroundColor Cyan
New-World
$r = Run-Acquire
Check ($r.state -ceq "held" -and $r.blocker -ceq "") "held, no blocker"
Check ($script:world.takes -eq 1 -and $script:world.sleeps -eq 0 -and $script:world.t -eq 0) "one take, no sleep, no time passed"
Check ($script:world.held) "and the slot is held"

Write-Host ""
Write-Host "--- memory below the floor: the slot is NOT taken while it stays there ---" -ForegroundColor Cyan
New-World -Memory { param($t, $n) if ($t -lt 30) { 1 } else { 10 } }
$r = Run-Acquire
Check ($r.state -ceq "held") "held once memory is back"
Check ($script:world.takesWhileLow -eq 0) "the slot was never taken while memory was under the floor"
Check ($script:world.takes -eq 1 -and $script:world.t -ge 30) ("taken once, at or after 30 s (t=" + $script:world.t + ")")
$memLines = @($script:world.said | Where-Object { $_ -like "*waiting for 4 GB of free memory*" })
Check ($memLines.Count -eq 1) ("the wait is said once, not every poll (" + $memLines.Count + ")")

Write-Host ""
Write-Host "--- memory never free: it gives up at -WaitSeconds, holding nothing ---" -ForegroundColor Cyan
New-World -Memory { 1 }
$r = Run-Acquire -Wait 20
Check ($r.state -ceq "timeout" -and $r.blocker -ceq "memory") "timeout, blocked on memory"
Check ($script:world.takes -eq 0 -and -not $script:world.held) "the slot was never taken and is not held"
Check ($script:world.t -ge 20 -and $script:world.t -lt 26) ("it stopped at about 20 s, not later (t=" + $script:world.t + ")")

Write-Host ""
Write-Host "--- the PC is busy: the slot is NOT taken until it is idle ---" -ForegroundColor Cyan
New-World -Idle { param($t, $n) $t -ge 40 }
$r = Run-Acquire
Check ($r.state -ceq "held" -and $script:world.takesWhileBusy -eq 0 -and $script:world.t -ge 40) ("held only after the PC was idle (t=" + $script:world.t + ")")
New-World -Idle { $false }
$r = Run-Acquire -Wait 10
Check ($r.state -ceq "timeout" -and $r.blocker -ceq "idle" -and $script:world.takes -eq 0 -and -not $script:world.held) "never idle: timeout, blocked on idle, nothing taken or held"
Check (@($script:world.said | Where-Object { $_ -like "*idle for 600 s or for night*" }).Count -eq 1) "the idle wait is said once"
New-World -Idle { $false } -Memory { 1 }
$r = Run-Acquire -Wait 10
Check ($r.blocker -ceq "idle") "idle is looked at first: with both unmet the blocker is idle"

Write-Host ""
Write-Host "--- memory falls between the check and the take: the slot is released, not held ---" -ForegroundColor Cyan
# Asked in order: 1 pre-check ok, 2 post-take LOW, 3 pre-check ok, 4 post-take ok.
$seq = @(10, 1, 10, 10)
New-World -Memory { param($t, $n) $seq[[math]::Min($n - 1, $seq.Count - 1)] }
$script:seqMemAsks = 0
$r = Run-Acquire
Check ($r.state -ceq "held") "it ends holding the slot once the floor holds after the take"
Check ($script:world.releases -eq 1) ("the slot taken under a falling floor was released once (" + $script:world.releases + ")")
Check ($script:world.takes -eq 2) ("and taken again afterwards (" + $script:world.takes + ")")
Check (@($script:world.said | Where-Object { $_ -like "*free memory fell to*released it*" }).Count -eq 1) "and said so"
New-World -Memory { param($t, $n) if ($n % 2 -eq 1) { 10 } else { 1 } }
$r = Run-Acquire -Wait 12
Check ($r.state -ceq "timeout" -and $r.blocker -ceq "memory" -and -not $script:world.held) "a floor that always fails after the take ends in timeout with the slot released"
Check ($script:world.takes -eq $script:world.releases) ("every slot taken was released (" + $script:world.takes + " takes, " + $script:world.releases + " releases)")

Write-Host ""
Write-Host "--- the person sits down between the check and the take ---" -ForegroundColor Cyan
New-World -Idle { param($t, $n) $n -ne 2 }
$r = Run-Acquire
Check ($r.state -ceq "held" -and $script:world.releases -eq 1) "released once, then held when idle again"
Check (@($script:world.said | Where-Object { $_ -like "*stopped being idle after the slot was taken*" }).Count -eq 1) "and said so"

Write-Host ""
Write-Host "--- the slot busy: it gives up in words of the slot, nothing released ---" -ForegroundColor Cyan
New-World -SlotBusy $true -SlotFreeAt 1000000
$r = Run-Acquire -Wait 3
Check ($r.state -ceq "timeout" -and $r.blocker -ceq "slot") "timeout, blocked on the slot"
Check ($script:world.releases -eq 0 -and $script:world.takes -eq 0) "nothing taken, nothing released"
Check ($script:world.t -ge 3 -and $script:world.t -lt 4) ("after about 3 s (t=" + $script:world.t + ")")

Write-Host ""
Write-Host "--- -WaitSeconds bounds memory, idle and slot TOGETHER ---" -ForegroundColor Cyan
# Memory is low for 15 s, then fine; the slot is busy until 1000000. If the memory wait did not count, the
# slot would be given its own 20 s after the 15 and the run would end at 35.
New-World -Memory { param($t, $n) if ($t -lt 15) { 1 } else { 10 } } -SlotBusy $true -SlotFreeAt 1000000
$r = Run-Acquire -Wait 20
Check ($r.state -ceq "timeout" -and $r.blocker -ceq "slot") "after memory came back the slot was the blocker"
Check ($script:world.t -ge 20 -and $script:world.t -lt 21) ("and the whole wait ended at 20 s, memory wait included (t=" + $script:world.t + ")")
New-World -Idle { param($t, $n) $t -ge 8 } -Memory { param($t, $n) if ($t -lt 16) { 1 } else { 10 } } -SlotBusy $true -SlotFreeAt 1000000
$r = Run-Acquire -Wait 24
Check ($r.state -ceq "timeout" -and $script:world.t -ge 24 -and $script:world.t -lt 25) ("idle, memory and slot in turn still end at 24 s (t=" + $script:world.t + ")")

Write-Host ""
Write-Host "--- a wait of 0 looks once ---" -ForegroundColor Cyan
New-World
$r = Run-Acquire -Wait 0
Check ($r.state -ceq "held") "everything fine with -WaitSeconds 0 still takes the slot"
New-World -Memory { 1 }
$r = Run-Acquire -Wait 0
Check ($r.state -ceq "timeout" -and $r.blocker -ceq "memory" -and $script:world.sleeps -eq 0) "memory low with -WaitSeconds 0: timeout at once, no sleep"

Write-Host ""
Write-Host "--- commit headroom (2026-10-24): off by default, a floor of its own when asked ---" -ForegroundColor Cyan
New-World -Commit { 0 }
$r = Run-Acquire
Check ($r.state -ceq "held" -and $script:world.commitAsks -eq 0) ("with no commit floor the headroom is never asked, and a box with none still runs (" + $script:world.commitAsks + " asks)")
New-World -Commit { param($t, $n) if ($t -lt 30) { 1 } else { 5 } }
$r = Run-Acquire -CommitFloor 2
Check ($r.state -ceq "held" -and $script:world.t -ge 30) ("held only once the headroom is back (t=" + $script:world.t + ")")
Check ($script:world.takesWhileCommitLow -eq 0) "the slot was never taken while the headroom was under its floor"
Check (@($script:world.said | Where-Object { $_ -like "*waiting for 2 GB of commit headroom*" }).Count -eq 1) "the commit wait is said once"
New-World -Commit { 1 }
$r = Run-Acquire -CommitFloor 2 -Wait 20
Check ($r.state -ceq "timeout" -and $r.blocker -ceq "commit") ("headroom never back: timeout, blocked on commit (" + $r.blocker + ")")
Check ($script:world.takes -eq 0 -and -not $script:world.held) "nothing taken, nothing held"
New-World -Memory { 1 } -Commit { 1 }
$r = Run-Acquire -CommitFloor 2 -Wait 10
Check ($r.blocker -ceq "memory") "free memory is looked at before commit: with both unmet the blocker is memory"
# Asked in order: 1 pre-check ok, 2 post-take LOW, 3 pre-check ok, 4 post-take ok.
$cseq = @(5, 1, 5, 5)
New-World -Commit { param($t, $n) $cseq[[math]::Min($n - 1, $cseq.Count - 1)] }
$r = Run-Acquire -CommitFloor 2
Check ($r.state -ceq "held" -and $script:world.releases -eq 1 -and $script:world.takes -eq 2) ("headroom that fell after the take: released once, then held (" + $script:world.releases + " releases)")
Check (@($script:world.said | Where-Object { $_ -like "*commit headroom fell to 1 GB*released it*" }).Count -eq 1) "and said so"
Check (Throws { Invoke-HordeHeavySlotAcquire -MinCommitHeadroomGB 2 -GetIdle { } -GetFreeGB { 9 } -TrySlot { $true } -ReleaseSlot { } -Elapsed { 0 } -Sleep { } -Say { } } "needs -GetCommitHeadroomGB") "a commit floor with no way to read the headroom is an error, not a floor that always passes"

Write-Host ""
Write-Host "--- who holds the memory: the top process groups by working set ---" -ForegroundColor Cyan
$procs = @()
foreach ($i in 1..3) { $procs += [pscustomobject]@{ ProcessName = "alpha"; WorkingSet64 = [long](1GB) } }
$procs += [pscustomobject]@{ ProcessName = "beta"; WorkingSet64 = [long](2.5GB) }
foreach ($i in 1..2) { $procs += [pscustomobject]@{ ProcessName = "gamma"; WorkingSet64 = [long](512MB) } }
foreach ($n in 1..9) { $procs += [pscustomobject]@{ ProcessName = ("small" + $n); WorkingSet64 = [long](1MB * $n) } }
$hl = @(Get-HordeHeavySlotMemoryHolders -Processes $procs -Top 8)
Check ($hl.Count -eq 8) ("at most -Top groups (" + $hl.Count + ")")
Check ($hl[0] -ceq "heavy-slot: memory held by alpha, 3 processes, 3.00 GB") ("the largest group first, its processes counted and summed (" + $hl[0] + ")")
Check ($hl[1] -ceq "heavy-slot: memory held by beta, 1 processes, 2.50 GB" -and $hl[2] -ceq "heavy-slot: memory held by gamma, 2 processes, 1.00 GB") ("then the next by size (" + $hl[1] + " / " + $hl[2] + ")")
Check ($hl[7] -like "*small5,*") ("the smallest groups are cut (" + $hl[7] + ")")
Check (@(Get-HordeHeavySlotMemoryHolders -Processes @() -Top 8).Count -eq 0) "no processes, no lines"

Complete-HordeSuite -Success "the gate waits for idle-or-night, memory and (when asked) commit headroom before it takes the slot, releases a slot taken as a floor failed, bounds the whole wait, and names who holds the memory"
