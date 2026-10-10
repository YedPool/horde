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
# and a retired agreement key opens only through its grace.
#
# RETRY-SAFE BY CONSTRUCTION. Nothing the loop holds is the only copy of anything: the relay keeps an
# item until it is acked, the journal records an envelope before it is opened and marks it done after,
# and the decisions list answers a repeated request from its record. So a run killed at any point - or
# two runs at once - loses nothing and doubles nothing; the next turn of either picks up what is left.
#
# BACKOFF. A turn that could not reach the relay, or could not open this machine's keys, waits before
# the next: backoffMinMs, doubled for each failure in a row up to backoffMaxMs, each wait moved by up to
# backoffJitterPercent either way, so machines that lost one relay together do not come back together
# (the design's resilience rule; the long-poll itself is the wait when all is well). One good turn
# resets it.
#
# A CLEAN STOP. The loop ends after the turn in which the stop file appears (<HORDE_HOME>\relay\run.stop,
# made by `horde relay stop`), or after -MaxTurns, or on Ctrl+C; in every case it lets go of its keys. A
# watch is at most watchMs, so a stop is seen within that. A stop file left from before is removed when
# a run starts: it was a request to an earlier run.
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
       what = "How often, in minutes, retired agreement keys past their grace are released and the keys opened again." }
)

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

function Request-HordeRelayRunStop {
    # Ask every run on this home to stop after its current turn: the stop file.
    param([string]$HordeHome = "")
    if ($HordeHome -ceq "") { $HordeHome = Get-HordeHome }
    $path = Get-HordeRelayRunStopPath -HordeHome $HordeHome
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path))
    [System.IO.File]::WriteAllText($path, "stop", [System.Text.Encoding]::ASCII)
    return $path
}

function Invoke-HordeRelayRun {
    # The loop (the header). -Connection is a relays/Port.ps1 connection the caller made; -Say receives
    # each line the loop has to say (the command prints them). Returns { turns; failures; stoppedBy }.
    # -MaxTurns 0 runs until stopped. -Random is for a suite that fixes the jitter.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)]$Connection, [Parameter(Mandatory = $true)][scriptblock]$Say,
        [int]$MaxTurns = 0, [string]$DecisionsRoot = "", $Random = $null, [scriptblock]$Sleep = $null)
    if ($HordeHome -ceq "") { $HordeHome = Get-HordeHome }
    if ($null -eq $Random) { $Random = New-Object System.Random }
    if ($null -eq $Sleep) { $Sleep = { param($Ms) Start-Sleep -Milliseconds $Ms } }
    $settings = Get-HordeRelayRunSettings -HordeHome $HordeHome
    if ($settings.state -cne "known") { $null = & $Say ("the run does not start: " + $settings.reason); return [pscustomobject]@{ turns = 0; failures = 0; stoppedBy = "settings" } }
    $set = $settings.value
    $watchMs = [int][System.Math]::Min([double]$set.watchMs, [double]$Connection.relay.limits.maxWatchMs)
    $stopPath = Get-HordeRelayRunStopPath -HordeHome $HordeHome
    if ([System.IO.File]::Exists($stopPath)) { [System.IO.File]::Delete($stopPath); $null = & $Say "a stop file from before was removed: it asked an earlier run to stop" }
    $ctx = $null
    $turns = 0
    $failures = 0
    $lastCheck = [datetime]::MinValue
    $stoppedBy = "turns"
    try {
        while ($true) {
            if ([System.IO.File]::Exists($stopPath)) { $stoppedBy = "stop file"; break }
            if ($MaxTurns -gt 0 -and $turns -ge $MaxTurns) { $stoppedBy = "turns"; break }
            $turns++
            $failed = ""
            if ($null -eq $ctx -or ([datetime]::UtcNow - $lastCheck).TotalMinutes -ge $set.retiredAgreeCheckMinutes) {
                # The periodic check: release what is past its grace, then open the keys again.
                $released = Remove-HordeRelayRetiredAgreeKeys -HordeHome $HordeHome
                if ($released.state -ceq "known" -and @($released.value.released).Count -gt 0) { $null = & $Say ("released the retired agreement key(s) of generation " + (@($released.value.released) -join ", ")) }
                elseif ($released.state -cne "known") { $null = & $Say ("retired agreement keys were not checked: " + $released.reason) }
                Close-HordeRelayRunContext -Context $ctx
                $ctx = $null
                $made = New-HordeRelayRunContext -HordeHome $HordeHome -Connection $Connection -DecisionsRoot $DecisionsRoot
                if ($made.state -ceq "known") { $ctx = $made.value; $lastCheck = [datetime]::UtcNow; $null = & $Say ("watching " + $ctx.mailbox) }
                else { $failed = "this machine's relay keys cannot be opened: " + $made.reason }
            }
            if ($failed -ceq "") {
                $r1 = Invoke-HordeRelayUnfinished -Context $ctx
                foreach ($l in @(Get-HordeRelayRunLines -Report $r1.value)) { $null = & $Say $l }
                foreach ($l in @(Invoke-HordeRelayChannelTicks -Context $ctx)) { $null = & $Say $l }
                $in = Receive-HordeRelayInbox -Context $ctx -TimeoutMs $watchMs
                if ($in.state -cne "known") { $failed = "the mailbox could not be read: " + $in.reason }
                else {
                    foreach ($l in @($in.value.refused)) { $null = & $Say ("refused " + $l) }
                    foreach ($l in @($in.value.held)) { $null = & $Say ("held " + $l) }
                    foreach ($l in @($in.value.missing)) { $null = & $Say ("missing " + $l) }
                    foreach ($l in @($in.value.anomalies)) { $null = & $Say ("relay: " + $l) }
                    $r2 = Invoke-HordeRelayUnfinished -Context $ctx
                    foreach ($l in @(Get-HordeRelayRunLines -Report $r2.value)) { $null = & $Say $l }
                }
            }
            if ($failed -cne "") {
                $failures++
                $wait = Get-HordeRelayRunBackoffMs -Failures $failures -Settings $set -Random $Random
                $null = & $Say ($failed + "; waiting " + $wait + " ms (failure " + $failures + " in a row)")
                if ($MaxTurns -le 0 -or $turns -lt $MaxTurns) { & $Sleep $wait }
            } else { $failures = 0 }
        }
    } finally {
        Close-HordeRelayRunContext -Context $ctx
    }
    if ($stoppedBy -ceq "stop file") { try { [System.IO.File]::Delete($stopPath) } catch { } }
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
