# core/HeavySlotAcquire - how the local gate (tools/HeavySlot.ps1) gets its slot: WAIT FIRST, TAKE LAST.
# T-0331.
#
# WHY. Until 2026-10-22 the gate took the machine-wide slot and THEN waited for free memory. The wait
# limit of whoever held the slot was therefore the wait of every other lane: a nightly job that waited
# for 4.5 GB the box did not have held the slot for about 2.5 hours and stood the whole fleet's heavy
# queue still. Now nothing is held while waiting for anything:
#   1. wait for idle-or-night (core/IdleState.ps1: 10 minutes without input, or 22:00 to 07:00);
#   2. wait for free memory of at least -MinFreeGB;
#   3. only then try the slot, in short slices, going back to 1 and 2 between slices;
#   4. check again AFTER taking it. Memory can drop, or the person can sit down, between the check and
#      the take, so a slot taken while the floor no longer holds is RELEASED and the wait begins again,
#      rather than held.
# -WaitSeconds bounds the WHOLE of it - idle, memory and slot together - and never starts a run it was
# not allowed to start. On timeout the slot is not held, and which condition was the last unmet decides
# the answer: blocker "idle", "memory" or "slot".
#
# EVERYTHING IMPURE IS A SCRIPT BLOCK given by the caller, so test/test-heavy-slot-acquire.ps1 drives
# every path with a fake clock, fake memory and a fake slot, and no real wait.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

function Invoke-HordeHeavySlotAcquire {
    # { state = "held" | "timeout"; blocker = "" | "idle" | "memory" | "slot" }. "held" means the slot is
    # held NOW and idle-or-night and the memory floor were true when it was taken.
    #   -GetIdle    returns a Get-HordeIdleState answer (needs .allowed, .idleSeconds, .needSeconds, .time, .why)
    #   -GetFreeGB  returns the free memory in GB
    #   -TrySlot    param($ms): waits at most $ms for the slot, returns $true when it is now held
    #   -ReleaseSlot gives the slot back
    #   -Elapsed    seconds since the whole wait began;  -Sleep  param($ms);  -Say  param($line)
    param(
        [Parameter(Mandatory = $true)][scriptblock]$GetIdle,
        [Parameter(Mandatory = $true)][scriptblock]$GetFreeGB,
        [Parameter(Mandatory = $true)][scriptblock]$TrySlot,
        [Parameter(Mandatory = $true)][scriptblock]$ReleaseSlot,
        [Parameter(Mandatory = $true)][scriptblock]$Elapsed,
        [Parameter(Mandatory = $true)][scriptblock]$Sleep,
        [Parameter(Mandatory = $true)][scriptblock]$Say,
        [double]$MinFreeGB = 3,
        [int]$WaitSeconds = 7200,
        [int]$SliceMs = 500
    )
    $saidIdle = $false
    $saidMemory = $false
    while ($true) {
        $left = $WaitSeconds - [double](& $Elapsed)
        $blocker = ""
        $pause = $false
        $idle = & $GetIdle
        if (-not $idle.allowed) {
            $blocker = "idle"
            $pause = $true
            if (-not $saidIdle) {
                $saidIdle = $true
                & $Say ("heavy-slot: not taking the slot yet: waiting for the PC to be idle for " + $idle.needSeconds + " s or for night (local time " + $idle.time + ", " + $idle.why + ")")
            }
        } else {
            $free = [double](& $GetFreeGB)
            if ($free -lt $MinFreeGB) {
                $blocker = "memory"
                $pause = $true
                if (-not $saidMemory) {
                    $saidMemory = $true
                    & $Say ("heavy-slot: not taking the slot yet: waiting for " + $MinFreeGB + " GB of free memory (now " + $free + ")")
                }
            } elseif (& $TrySlot ([int][math]::Min($SliceMs, [math]::Max(0, $left * 1000)))) {
                # Held. The conditions again, now that nobody else can start: the person may have sat
                # down, or another program may have taken the memory, since the checks above.
                $idleNow = & $GetIdle
                $freeNow = [double](& $GetFreeGB)
                if ($idleNow.allowed -and $freeNow -ge $MinFreeGB) { return [pscustomobject]@{ state = "held"; blocker = "" } }
                & $ReleaseSlot
                $pause = $true
                if ($idleNow.allowed) { $blocker = "memory"; & $Say ("heavy-slot: free memory fell to " + $freeNow + " GB after the slot was taken; released it and waiting again") }
                else { $blocker = "idle"; & $Say "heavy-slot: the PC stopped being idle after the slot was taken; released it and waiting again" }
            } else {
                $blocker = "slot"
            }
        }
        if (($WaitSeconds - [double](& $Elapsed)) -le 0) { return [pscustomobject]@{ state = "timeout"; blocker = $blocker } }
        if ($pause) { & $Sleep ([int][math]::Min(5000, [math]::Max(200, ($WaitSeconds - [double](& $Elapsed)) * 1000))) }
    }
}
