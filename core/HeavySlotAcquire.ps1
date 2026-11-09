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
# THE NET'S FIRST CLAIM (2026-11-06, -GetNetClaim, optional): on the night of 2026-11-05 another lane's long rerun took the
# slot between the net's units, and 10 of the net's 476 Horde units ran. While -GetNetClaim answers true the gate does not
# take the slot, holds nothing, and checks again after any take, so a net that starts in between still goes first. The
# gate of the net itself passes no -GetNetClaim. Blocker "claim".
# COMMIT HEADROOM (2026-10-24, optional): with -MinCommitHeadroomGB above 0 the gate also waits until the commit
# limit less the commit charge (Win32_OperatingSystem FreeVirtualMemory) is at least that much. On the night of
# 2026-10-23 the commit charge was 52.3 of 54.8 GB: a run started there can fail to allocate however much physical
# memory is free. At 0 (the default) it is never asked, so every caller that does not pass it waits as before.
# -WaitSeconds bounds the WHOLE of it - idle, memory and slot together - and never starts a run it was
# not allowed to start. On timeout the slot is not held, and which condition was the last unmet decides
# the answer: blocker "idle", "memory", "commit" or "slot".
#
# EVERYTHING IMPURE IS A SCRIPT BLOCK given by the caller, so test/test-heavy-slot-acquire.ps1 drives
# every path with a fake clock, fake memory and a fake slot, and no real wait.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

function Invoke-HordeHeavySlotAcquire {
    # { state = "held" | "timeout"; blocker = "" | "idle" | "claim" | "memory" | "commit" | "slot" }. "held" means the slot
    # is held NOW and idle-or-night, the memory floor and the commit floor were true when it was taken.
    #   -GetIdle    returns a Get-HordeIdleState answer (needs .allowed, .idleSeconds, .needSeconds, .time, .why)
    #   -GetFreeGB  returns the free memory in GB
    #   -GetCommitHeadroomGB returns the commit limit less the commit charge in GB; asked only when
    #               -MinCommitHeadroomGB is above 0, and then required
    #   -GetNetClaim returns $true while the nightly net has first claim on the slot; not given, there is no claim
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
        [scriptblock]$GetCommitHeadroomGB = $null,
        [scriptblock]$GetNetClaim = $null,
        [double]$MinCommitHeadroomGB = 0,
        [int]$WaitSeconds = 7200,
        [int]$SliceMs = 500
    )
    $useCommit = ($MinCommitHeadroomGB -gt 0)
    if ($useCommit -and $null -eq $GetCommitHeadroomGB) { throw "-MinCommitHeadroomGB needs -GetCommitHeadroomGB" }
    $saidIdle = $false
    $saidMemory = $false
    $saidCommit = $false
    $saidClaim = $false
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
        } elseif ($null -ne $GetNetClaim -and (& $GetNetClaim)) {
            $blocker = "claim"
            $pause = $true
            if (-not $saidClaim) {
                $saidClaim = $true
                & $Say "heavy-slot: not taking the slot yet: the nightly net has first claim on it until its report is written"
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
            } elseif ($useCommit -and ($commit = [double](& $GetCommitHeadroomGB)) -lt $MinCommitHeadroomGB) {
                $blocker = "commit"
                $pause = $true
                if (-not $saidCommit) {
                    $saidCommit = $true
                    & $Say ("heavy-slot: not taking the slot yet: waiting for " + $MinCommitHeadroomGB + " GB of commit headroom (now " + $commit + ")")
                }
            } elseif (& $TrySlot ([int][math]::Min($SliceMs, [math]::Max(0, $left * 1000)))) {
                # Held. The conditions again, now that nobody else can start: the person may have sat
                # down, or another program may have taken the memory, since the checks above.
                $idleNow = & $GetIdle
                $freeNow = [double](& $GetFreeGB)
                $commitNow = $(if ($useCommit) { [double](& $GetCommitHeadroomGB) } else { [double]::MaxValue })
                $claimNow = ($null -ne $GetNetClaim -and (& $GetNetClaim))
                if (-not $claimNow) {
                if ($idleNow.allowed -and $freeNow -ge $MinFreeGB -and $commitNow -ge $MinCommitHeadroomGB) { return [pscustomobject]@{ state = "held"; blocker = "" } }
                }
                & $ReleaseSlot
                $pause = $true
                if ($claimNow) { $blocker = "claim"; & $Say "heavy-slot: the nightly net took first claim after the slot was taken; released it and waiting again" }
                elseif (-not $idleNow.allowed) { $blocker = "idle"; & $Say "heavy-slot: the PC stopped being idle after the slot was taken; released it and waiting again" }
                elseif ($freeNow -lt $MinFreeGB) { $blocker = "memory"; & $Say ("heavy-slot: free memory fell to " + $freeNow + " GB after the slot was taken; released it and waiting again") }
                else { $blocker = "commit"; & $Say ("heavy-slot: commit headroom fell to " + $commitNow + " GB after the slot was taken; released it and waiting again") }
            } else {
                $blocker = "slot"
            }
        }
        if (($WaitSeconds - [double](& $Elapsed)) -le 0) { return [pscustomobject]@{ state = "timeout"; blocker = $blocker } }
        if ($pause) { & $Sleep ([int][math]::Min(5000, [math]::Max(200, ($WaitSeconds - [double](& $Elapsed)) * 1000))) }
    }
}

function Get-HordeHeavySlotMemoryHolders {
    # WHO HOLDS THE MEMORY when a wait for it gave up (2026-10-24): on the night of 2026-10-23 every gate gave up
    # after 900 s at 1.1 to 2.5 GB free, and nothing said which programs held the rest. -Processes are objects with
    # a name (ProcessName or Name) and WorkingSet64; they are grouped by name, summed, and the -Top largest groups
    # are returned as lines "heavy-slot: memory held by <name>, <count> processes, <GB> GB" (two decimals, a dot),
    # largest first. core/NightlyNet.ps1 Read-HordeNightlyMemoryHolders reads them back. Names only, no ids or
    # command lines: the lines go into a report.
    param([object[]]$Processes, [int]$Top = 8)
    $groups = @{}
    foreach ($p in @($Processes)) {
        if ($null -eq $p) { continue }
        $n = ""
        if ($p.PSObject.Properties["ProcessName"]) { $n = "" + $p.ProcessName } elseif ($p.PSObject.Properties["Name"]) { $n = "" + $p.Name }
        $n = ($n -replace '[^ -~]', '?').Trim()
        if ($n -eq "") { $n = "?" }
        $ws = [double]0
        if ($p.PSObject.Properties["WorkingSet64"]) { $ws = [double]$p.WorkingSet64 }
        if (-not $groups.ContainsKey($n)) { $groups[$n] = [pscustomobject]@{ name = $n; count = 0; bytes = [double]0 } }
        $groups[$n].count++
        $groups[$n].bytes += $ws
    }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    return @(@($groups.Values) | Sort-Object -Property @{ Expression = { $_.bytes }; Descending = $true }, @{ Expression = { $_.name }; Descending = $false } |
        Select-Object -First ([math]::Max(0, $Top)) | ForEach-Object {
            "heavy-slot: memory held by " + $_.name + ", " + $_.count + " processes, " + ($_.bytes / 1GB).ToString("0.00", $inv) + " GB" })
}
