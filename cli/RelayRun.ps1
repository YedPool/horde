# cli/RelayRun - `horde relay run`: the long-running loop that keeps this machine's relay channels moving.
#
# WHY HERE (relay design 2026-10-09, PR plan item 6, "horde relay run (detached, retry-safe)"). The loop
# holds a relay connection, sleeps, and runs the channels' script blocks; relay/ may do none of that
# (tools/ExecScan.ps1), so the loop lives in cli/, as the node's serve loop does (cli/NodeServe.ps1).
# Everything it does to an envelope is channels/Port.ps1's, which calls relay/.
#
# ONE TURN, in this order:
#   1. resume: open every journaled record no channel has finished (a killed run's, or one a channel
#      asked to retry) - before anything new, so an old answer lands before a newer one;
#   2. out: every channel's Tick (the decisions snapshot, when it changed);
#   3. in: one watch of the machine's mailbox, up to watchMs, each envelope judged, journaled, acked;
#   4. resume again: what step 3 just journaled is opened and handed to its channel now, not a turn later.
# Every retiredAgreeCheckMinutes it calls Remove-HordeRelayRetiredAgreeKeys (relay/Identity.ps1), and
# opens its keys again, so a rotation since the run started is followed: the new mailbox is watched,
# and a retired agreement key opens only through its grace. What the run has learnt survives that
# reopen - the channels' memory always, the cursor and the ack while the mailbox is the same
# (channels/Port.ps1, Update-HordeRelayRunContext; review of 48bc492, finding 3).
# A MINIMUM TURN (finding 5): a turn whose watch came back at once with nothing - watchMs 0, or a relay
# that does not wait - is padded to minTurnMs (1000 by default, at least 50), so no setting and no relay
# makes the loop spin.
#
# RETRY-SAFE BY CONSTRUCTION. Nothing the loop holds is the only copy of anything: the relay keeps an
# item until it is acked, the journal records an envelope before it is opened and marks it done after,
# and the decisions list answers a repeated request from its record. So a run killed at any point - or
# two runs at once - loses nothing and doubles nothing; the next turn of either picks up what is left.
#
# BACKOFF. A turn that could not reach the relay, could not open this machine's keys, or whose channels
# could not send (a Tick that failed: finding 1) waits before the next: backoffMinMs, doubled for each failure in a row up to backoffMaxMs, each wait moved by up to
# backoffJitterPercent either way, so machines that lost one relay together do not come back together
# (the design's resilience rule; the long-poll itself is the wait when all is well). One good turn
# resets it.
#
# A CLEAN STOP. The loop ends after the turn in which a stop is asked (<HORDE_HOME>\relay\run.stop, made
# by `horde relay stop`), or after -MaxTurns, or on Ctrl+C; in every case it lets go of its keys. The
# stop file holds the moment it was asked, and EVERY run whose start is before that moment obeys it -
# no run that stops deletes it, so a second run on the same home stops too (finding 4: the first to stop
# deleted it, and the second ran on). A run that STARTS removes a stop asked before its start: that was
# a request to the runs before it. A watch is at most watchMs, and every wait - a backoff, a padded
# turn - is slept in slices of at most 500 ms with the stop asked between them (finding 6: a 15 s
# backoff hid a stop for 15 s).
#
# ONE RUN PER HOME (review of 3d837f0). A run holds <HORDE_HOME>\relay\run.lock open with no sharing
# from before its first turn to after its last; a second run on the same home cannot open it, says so
# plainly and does nothing. Two runs on one home would each keep a channel's memory and its state file
# (channels/chat) and race on them. The operating system closes a killed run's handle, so a crash never
# leaves the home locked. The stop file above still obeys every run started before it.
#
# THE SETTINGS are core/ModuleSettings.ps1's, module relay-run (<HORDE_HOME>\settings\relay-run.json),
# read when the run starts. A file that fails its checks refuses the run, in its own words.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

$script:HordeRelayRunSettings = New-HordeModuleSettings -Module "relay-run" -Settings @(
    # 25 s is the design's long-poll (Q8, spike S3: PS 5.1 long-polls end cleanly on timeout); 60 s is the
    # relay port's ceiling (relays/Port.ps1), and a relay's own maxWatchMs may be lower - the smaller wins.
    @{ name = "watchMs"; kind = "whole"; default = 25000; min = 0; max = 60000
       what = "How long, in milliseconds, one watch of the mailbox waits for something to arrive." },
    @{ name = "backoffMinMs"; kind = "whole"; default = 1000; min = 0; max = 60000
       what = "The first wait, in milliseconds, after a turn that could not reach the relay or open the keys." },
    @{ name = "backoffMaxMs"; kind = "whole"; default = 60000; min = 0; max = 3600000
       what = "The longest wait, in milliseconds, between turns that keep failing." },
    @{ name = "backoffJitterPercent"; kind = "whole"; default = 20; min = 0; max = 100
       what = "How far, in percent either way, each wait is moved at random." },
    @{ name = "retiredAgreeCheckMinutes"; kind = "whole"; default = 60; min = 1; max = 1440
       what = "How often, in minutes, retired agreement keys past their grace are released and the keys opened again." },
    # 50 ms is the floor: twenty empty turns a second at most, whatever watchMs and the relay do.
    @{ name = "minTurnMs"; kind = "whole"; default = 1000; min = 50; max = 60000
       what = "The shortest a turn may be, in milliseconds, when its watch came back at once with nothing." }
)
# The longest one sleep of the loop: a stop is asked between slices (A CLEAN STOP, above).
$script:HordeRelayRunSliceMs = 500

function Get-HordeRelayRunSettings {
    # The run's settings: known values, or unknown with the findings of a refused file.
    param([string]$HordeHome = "")
    $homeDir = $HordeHome
    try {
        if ($homeDir -ceq "") { $homeDir = Get-HordeHome }
        $s = Get-HordeModuleSettings -Declaration $script:HordeRelayRunSettings -HordeHome $homeDir
    } catch { return (New-HordeUnknown -Reason "the relay-run settings could not be read" -ErrorRecord $_) }
    if ($s.state -ceq "refused") { return (New-HordeUnknown -Reason ($s.findings -join " ")) }
    return (New-HordeKnown -Value $s.values)
}

function Get-HordeRelayRunBackoffMs {
    # The wait after -Failures failures in a row: min doubled per failure past the first, capped at max,
    # moved by up to jitter percent either way by -Random (a System.Random, so a suite can fix the seed).
    param([Parameter(Mandatory = $true)][int]$Failures, [Parameter(Mandatory = $true)]$Settings, [Parameter(Mandatory = $true)]$Random)
    if ($Failures -le 0) { return 0 }
    $base = [double]$Settings.backoffMinMs
    for ($i = 1; $i -lt $Failures -and $base -lt [double]$Settings.backoffMaxMs; $i++) { $base = $base * 2 }
    $base = [System.Math]::Min($base, [double]$Settings.backoffMaxMs)
    $spread = $base * [double]$Settings.backoffJitterPercent / 100
    $ms = $base - $spread + ($Random.NextDouble() * 2 * $spread)
    return [int][System.Math]::Max(0, [System.Math]::Round($ms))
}

function Get-HordeRelayRunStopPath {
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    return [System.IO.Path]::Combine($HordeHome, "relay", "run.stop")
}

function Get-HordeRelayRunLockPath {
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    return [System.IO.Path]::Combine($HordeHome, "relay", "run.lock")
}

function Request-HordeRelayRunStop {
    # Ask every run on this home that started before now to stop after its current turn: the stop file,
    # holding this moment in milliseconds since 1970 UTC (A CLEAN STOP, in the header).
    param([string]$HordeHome = "")
    if ($HordeHome -ceq "") { $HordeHome = Get-HordeHome }
    $path = Get-HordeRelayRunStopPath -HordeHome $HordeHome
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path))
    [System.IO.File]::WriteAllText($path, ("stop " + (ConvertTo-HordeRelayRecordMs)), [System.Text.Encoding]::ASCII)
    return $path
}

function Get-HordeRelayRunStopMs {
    # When the stop in -Path was asked, in milliseconds since 1970 UTC; -1 when there is none. A file that
    # does not say (written by hand, or by an earlier version) is dated by when it was last written.
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not [System.IO.File]::Exists($Path)) { return [long]-1 }
    $text = ""
    try { $text = [System.IO.File]::ReadAllText($Path) } catch { $text = "" }
    $m = [regex]::Match($text, '\Astop (0|[1-9][0-9]{0,15})\s*\z')
    if ($m.Success) { return [long]$m.Groups[1].Value }
    try { return (ConvertTo-HordeRelayRecordMs -Time ([System.IO.File]::GetLastWriteTimeUtc($Path))) } catch { return [long]-1 }
}

function Test-HordeRelayRunStopAsked {
    # Is a stop asked for a run that started at -StartedMs? Only a stop asked after it started counts.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][long]$StartedMs)
    return ((Get-HordeRelayRunStopMs -Path $Path) -gt $StartedMs)
}

function Wait-HordeRelayRunSliced {
    # Sleep -Ms in slices of at most 500 ms through -Sleep (handed -Why too: backoff or pace), asking for
    # a stop between them. $true when a stop was asked, and the wait cut short.
    param([Parameter(Mandatory = $true)][long]$Ms, [Parameter(Mandatory = $true)][string]$Why, [Parameter(Mandatory = $true)][scriptblock]$Sleep,
        [Parameter(Mandatory = $true)][string]$StopPath, [Parameter(Mandatory = $true)][long]$StartedMs)
    $left = $Ms
    while ($left -gt 0) {
        if (Test-HordeRelayRunStopAsked -Path $StopPath -StartedMs $StartedMs) { return $true }
        $slice = [long][System.Math]::Min([double]$left, [double]$script:HordeRelayRunSliceMs)
        $null = & $Sleep $slice $Why
        $left -= $slice
    }
    return (Test-HordeRelayRunStopAsked -Path $StopPath -StartedMs $StartedMs)
}

function Invoke-HordeRelayRun {
    # The loop (the header). -Connection is a relays/Port.ps1 connection the caller made; -Say receives
    # each line the loop has to say (the command prints them). Returns { turns; failures; stoppedBy }.
    # -MaxTurns 0 runs until stopped. -Random is for a suite that fixes the jitter.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)]$Connection, [Parameter(Mandatory = $true)][scriptblock]$Say,
        [int]$MaxTurns = 0, [string]$DecisionsRoot = "", $Random = $null, [scriptblock]$Sleep = $null)
    if ($HordeHome -ceq "") { $HordeHome = Get-HordeHome }
    if ($null -eq $Random) { $Random = New-Object System.Random }
    if ($null -eq $Sleep) { $Sleep = { param($Ms, $Why) Start-Sleep -Milliseconds $Ms } }
    $settings = Get-HordeRelayRunSettings -HordeHome $HordeHome
    if ($settings.state -cne "known") { $null = & $Say ("the run does not start: " + $settings.reason); return [pscustomobject]@{ turns = 0; failures = 0; stoppedBy = "settings" } }
    $set = $settings.value
    $watchMs = [int][System.Math]::Min([double]$set.watchMs, [double]$Connection.relay.limits.maxWatchMs)
    $lockPath = Get-HordeRelayRunLockPath -HordeHome $HordeHome
    $lock = $null
    try {
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($lockPath))
        $lock = New-Object System.IO.FileStream -ArgumentList $lockPath, ([System.IO.FileMode]::OpenOrCreate), ([System.IO.FileAccess]::ReadWrite), ([System.IO.FileShare]::None)
    } catch {
        $null = & $Say ("another relay run is already running on this home (it holds " + $lockPath + "); this one does not start")
        return [pscustomobject]@{ turns = 0; failures = 0; stoppedBy = "locked" }
    }
    $stopPath = Get-HordeRelayRunStopPath -HordeHome $HordeHome
    $startedMs = ConvertTo-HordeRelayRecordMs
    # A stop asked before this run started was asked of the runs before it.
    if ([System.IO.File]::Exists($stopPath) -and -not (Test-HordeRelayRunStopAsked -Path $stopPath -StartedMs $startedMs)) {
        try { [System.IO.File]::Delete($stopPath) } catch { }
        $null = & $Say "a stop file from before was removed: it asked the runs before this one to stop"
    }
    $ctx = $null
    $turns = 0
    $failures = 0
    $lastCheck = [datetime]::MinValue
    $stoppedBy = "turns"
    try {
        while ($true) {
            if (Test-HordeRelayRunStopAsked -Path $stopPath -StartedMs $startedMs) { $stoppedBy = "stop file"; break }
            if ($MaxTurns -gt 0 -and $turns -ge $MaxTurns) { $stoppedBy = "turns"; break }
            $turns++
            $clock = [System.Diagnostics.Stopwatch]::StartNew()
            $failed = ""
            $empty = $false
            if ($null -eq $ctx -or ([datetime]::UtcNow - $lastCheck).TotalMinutes -ge $set.retiredAgreeCheckMinutes) {
                # The periodic check: release what is past its grace, then open the keys again, keeping
                # what the run has learnt.
                $released = Remove-HordeRelayRetiredAgreeKeys -HordeHome $HordeHome
                if ($released.state -ceq "known" -and @($released.value.released).Count -gt 0) { $null = & $Say ("released the retired agreement key(s) of generation " + (@($released.value.released) -join ", ")) }
                elseif ($released.state -cne "known") { $null = & $Say ("retired agreement keys were not checked: " + $released.reason) }
                if ($null -eq $ctx) { $made = New-HordeRelayRunContext -HordeHome $HordeHome -Connection $Connection -DecisionsRoot $DecisionsRoot }
                else { $made = Update-HordeRelayRunContext -Context $ctx }
                if ($made.state -ceq "known") {
                    $moved = ($null -eq $ctx -or $made.value.mailbox -cne $ctx.mailbox)
                    $ctx = $made.value; $lastCheck = [datetime]::UtcNow
                    if ($moved) { $null = & $Say ("watching " + $ctx.mailbox) }
                }
                elseif ($null -eq $ctx) { $failed = "this machine's relay keys cannot be opened: " + $made.reason }
                else { $null = & $Say ("the keys could not be opened again, so the run goes on with those it has: " + $made.reason) }
            }
            if ($failed -ceq "") {
                $r1 = Invoke-HordeRelayUnfinished -Context $ctx
                foreach ($l in @(Get-HordeRelayRunLines -Report $r1.value)) { $null = & $Say $l }
                $ticks = Invoke-HordeRelayChannelTicks -Context $ctx
                foreach ($l in @($ticks.lines)) { $null = & $Say $l }
                $in = Receive-HordeRelayInbox -Context $ctx -TimeoutMs $watchMs
                if ($in.state -cne "known") { $failed = "the mailbox could not be read: " + $in.reason }
                else {
                    foreach ($l in @($in.value.refused)) { $null = & $Say ("refused " + $l) }
                    foreach ($l in @($in.value.held)) { $null = & $Say ("held " + $l) }
                    foreach ($l in @($in.value.missing)) { $null = & $Say ("missing " + $l) }
                    foreach ($l in @($in.value.anomalies)) { $null = & $Say ("relay: " + $l) }
                    $empty = (@($in.value.taken).Count + @($in.value.refused).Count + @($in.value.held).Count + @($in.value.missing).Count + @($in.value.anomalies).Count -eq 0)
                    $r2 = Invoke-HordeRelayUnfinished -Context $ctx
                    foreach ($l in @(Get-HordeRelayRunLines -Report $r2.value)) { $null = & $Say $l }
                }
                # A channel that could not send counts toward the backoff (finding 1), after the inbound
                # work of the turn is done: an outbound fault never holds an answer back.
                if ($failed -ceq "" -and $ticks.failed) { $failed = "a channel could not send (above)" }
            }
            $last = ($MaxTurns -gt 0 -and $turns -ge $MaxTurns)
            if ($failed -cne "") {
                $failures++
                $wait = Get-HordeRelayRunBackoffMs -Failures $failures -Settings $set -Random $Random
                $null = & $Say ($failed + "; waiting " + $wait + " ms (failure " + $failures + " in a row)")
                if (-not $last) { $null = Wait-HordeRelayRunSliced -Ms $wait -Why "backoff" -Sleep $Sleep -StopPath $stopPath -StartedMs $startedMs }
            } else {
                $failures = 0
                $left = [long]$set.minTurnMs - $clock.ElapsedMilliseconds
                if ($empty -and $left -gt 0 -and -not $last) { $null = Wait-HordeRelayRunSliced -Ms $left -Why "pace" -Sleep $Sleep -StopPath $stopPath -StartedMs $startedMs }
            }
        }
    } finally {
        Close-HordeRelayRunContext -Context $ctx
        $lock.Dispose()
    }
    $null = & $Say ("stopped after " + $turns + " turn(s): " + $stoppedBy)
    return [pscustomobject]@{ turns = $turns; failures = $failures; stoppedBy = $stoppedBy }
}

function Get-HordeRelayRunLines {
    # The lines of an Invoke-HordeRelayUnfinished report, each saying what became of one record.
    param($Report)
    $out = New-Object System.Collections.ArrayList
    if ($null -eq $Report) { return @() }
    foreach ($l in @($Report.done)) { [void]$out.Add("done " + $l) }
    foreach ($l in @($Report.refused)) { [void]$out.Add("refused " + $l) }
    foreach ($l in @($Report.retry)) { [void]$out.Add("retry " + $l) }
    return @($out.ToArray())
}
