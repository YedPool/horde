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
# SENDING DURING THE WATCH (2026-10-13). Step 2 ran once a turn, and a turn is as long as its watch: so
# what a channel had to SEND a second into the watch - the Thrall's reply under a question, a line of
# chat, a new question - waited for the watch to end, up to 60 s on the hosted relay, while what came IN
# was always fast (a put ends the watch at once). Measured with a real run over the local relay and an
# 8 s watch: a note written about a second into the watch reached the phone's mailbox 6.9 s later, three
# times of three; the same run with what is described here, 0.7 to 0.9 s. A shorter watch was never the
# answer: the hosted relay counts requests (20,000 a day an account), a watch is one, and a 2 s watch
# is 43,200 a day.
# So, ON A RELAY THAT WATCHES IN SLICES (relays/Port.ps1, A WATCH IN SLICES), the turn's one watch is
# held open and waited on sendCheckMs at a time (1000 by default), and between two slices the run asks
# every channel's Glance (channels/Port.ps1) - a look at local state that costs the relay nothing - and
# runs the Tick, there and then, of each channel that says it has something. Only that Tick's own puts
# reach the relay: an idle watch is one request, as it was, and a send during it is that send's puts and
# no more (test/test-relay-run-send.ps1 counts both). What does not change:
#   - RETRY-SAFE, as below: the watch in slices is the same one watch, and its batch goes through the
#     same journal and ack; a Tick during the watch is the turn's Tick run sooner, recording before it
#     puts as it always does.
#   - A SEND THAT FAILS IS NOT TRIED AGAIN IN THAT WATCH. The first Tick that says it failed ends the
#     looking for the rest of the turn; the watch itself goes on to its end, so an outbound fault still
#     never holds an answer back, and the turn then counts as failed and waits out its backoff, exactly
#     as a failed Tick at the top of a turn does. A relay that is refusing is never asked once a second.
#   - NEVER A SPIN. A relay whose slice comes back sooner than it was asked to wait is waited for here,
#     to the end of the interval, before the next look: two looks are never closer than sendCheckMs.
#   - A STOP IS SEEN BETWEEN SLICES, and ends the watch there: within sendCheckMs, where it was watchMs.
#   - THE TURN IS NO LONGER THAN IT WAS: the watch's time runs while a Tick works, so the heartbeat's
#     tick, computed from the watch and the longest backoff, still describes how often the run beats.
#   - A RELAY THAT DOES NOT WATCH IN SLICES is watched by one blocking watch, by the very line that
#     always did it, and nothing is looked at during it.
# What a channel asks for with againMs is still the turn's: it shortens the turn's watch when the
# turn's Tick asks, and is not read from a Tick run during the watch.
#
# A FULL MAILBOX IS SAID PLAINLY, AND THE WARCHIEF IS TOLD ONCE (2026-10-13). A put the relay refuses
# because the mailbox or the account is full (status 507; channels/Port.ps1 keeps it in the context,
# WHAT A PUT TELLS THE RUN) was one more failed turn: backed off from, tried again, for ever, in a log
# nobody read, while nothing reached the founder's phone. Now, after every round of Ticks - the turn's
# own and one run during a watch - the run looks at what the puts told it (Invoke-HordeRelayRunPutNotes):
#   - the first time a mailbox is refused as full it says so in capitals, with what the relay answered,
#     and that nothing new reaches the phone until it is put right; and it tells the warchief, once,
#     through the messenger port (cli/RelayRunTell.ps1, which has why the words are fixed and why a
#     test's home tells nobody). A notice that could not be posted is tried again a minute later, and
#     why is said once; when the relay takes mail for that mailbox again the run says that too.
#   - the first time a put asked the relay to trim and the relay took the put without trimming
#     (relays/Port.ps1, A SENDER TRIMS ITS OWN STREAM: a relay with no such thing, or the hosted one
#     deployed before it), it says the mailbox is not being trimmed and will fill. Nothing failed, so
#     nobody is told: it is the state between two deployments, and the full mailbox it leads to is.
# The backoff is unchanged: a full mailbox is still a failed turn, and the relay is not asked faster.
#
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
# a request to the runs before it. A watch is at most watchMs - and on a relay that watches in
# slices a stop is seen between two of them, within sendCheckMs - and every wait - a backoff, a padded
# turn - is slept in slices of at most 500 ms with the stop asked between them (finding 6: a 15 s
# backoff hid a stop for 15 s).
#
# ONE RUN PER HOME (review of 3d837f0). A run holds <HORDE_HOME>\relay\run.lock open with no sharing
# from before its first turn to after its last; a second run on the same home cannot open it, says so
# plainly and does nothing. Two runs on one home would each keep a channel's memory and its state file
# (channels/chat) and race on them. The operating system closes a killed run's handle, so a crash never
# leaves the home locked. The stop file above still obeys every run started before it.
#
# THE WATCH. A relay that counts requests declares how long a runner watches it (relays/Port.ps1,
# -RunWatchMs: the hosted relay's is 60 s, so an always-on machine is 1,440 requests a day), and that is
# the run's watch on it; on any other relay, the setting watchMs, never past the relay's maxWatchMs.
#
# A HEARTBEAT, ONCE A TURN (core/Heartbeat.ps1): <HORDE_HOME>\relay\run-heartbeat.json, replaced whole
# at the top of every turn, holding this process and when it started. Until it was added, a run that had
# died looked exactly like one with nothing to do: its log simply stopped, and the founder found out
# when his phone went quiet. The supervisor of services (core/Services.ps1) reads it to tell a run that
# is going from one that is not. THE TICK IT PROMISES IS COMPUTED from this run's own settings - the
# longest a turn can last between two beats is its watch plus the longest backoff, moved by the jitter -
# so a run that is waiting out a long backoff, as designed, is never read as dead. A write that fails
# never ends the loop: it costs the heartbeat and one line said once, nothing else.
#
# A RUN THAT BEATS IS NOT A RUN THAT WORKS, so the heartbeat says which (review of PR 249, MUST 1).
# The supervisor runs whether or not anyone is signed in (cli/ServicesTend.ps1), and a run it starts
# before anyone has signed in since the machine started may not be able to use this machine's keys:
# the agreement key is a software key protected under the account's logon (relay/Keys.ps1), and with
# no logon there may be nothing to unlock it. Such a run used to beat on every turn while it could not
# open one answer from the phone. Now the keys are PROVED - opened, and each used once (a signature
# made and checked, an agreement made with a throwaway peer) - before the run's first healthy beat,
# and every turn the keys are not open beats the condition keys-unavailable, with why
# (core/Heartbeat.ps1). The supervisor never calls such a run alive: it restarts it with a back-off
# and tells the warchief once (core/Services.ps1). The run itself goes on trying its keys every turn,
# at its own back-off, so once they open - the person has signed in, or a run started after that - it
# beats well again. Keys that were opened and proved stay open for the run's life; the hourly reopen
# that fails keeps them (it says so) and is not a condition.
#
# THE SETTINGS are core/ModuleSettings.ps1's, module relay-run (<HORDE_HOME>\settings\relay-run.json),
# read when the run starts. A file that fails its checks refuses the run, in its own words.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

# What this file calls of core beyond what its command loads, loaded here so it works on its own.
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Heartbeat.ps1")
. (Join-Path $PSScriptRoot "RelayRunTell.ps1")

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
       what = "The shortest a turn may be, in milliseconds, when its watch came back at once with nothing." },
    # 1000 ms is "about a second": with a Tick's own work, what a channel has to send is at the relay
    # within about two of when it was written. 200 ms is the floor - five looks a second, each a few
    # milliseconds of local reads (channels/Port.ps1, Glance) - and 60000, the longest watch there is,
    # the ceiling: at the ceiling nothing is looked at during a watch, which is how it was before.
    @{ name = "sendCheckMs"; kind = "whole"; default = 1000; min = 200; max = 60000
       what = "How often, in milliseconds, the run looks during a watch for something a channel has to send." },
    # On unless switched off: a phone that has gone silent because the relay is full looks exactly like
    # a quiet day (A FULL MAILBOX IS SAID PLAINLY, in the header).
    @{ name = "tellWarchief"; kind = "truefalse"; default = $true
       what = "Whether the warchief's session is told when the relay refuses this machine's mail because a mailbox or the account is full." },
    # SV: the label the supervisor of services wears (core/Services.ps1), which is what keeps this run going.
    @{ name = "fromLabel"; kind = "label"; default = "SV"
       what = "The hub label that notice is from." }
)
# The longest one sleep of the loop: a stop is asked between slices (A CLEAN STOP, above).
$script:HordeRelayRunSliceMs = 500
# How long after a notice of a full mailbox could not be posted it is tried again: a minute, the run's
# own longest backoff, so a machine with no warchief's session is not asking for one every turn.
$script:HordeRelayRunTellRetrySeconds = 60

function Get-HordeRelayRunWatchMs {
    # How long one turn's watch waits on -Relay (THE WATCH, in the header): the relay's own run watch
    # when it declares one, else -SettingMs, never past the relay's maxWatchMs.
    param([Parameter(Mandatory = $true)][long]$SettingMs, [Parameter(Mandatory = $true)]$Relay)
    $declared = $Relay.PSObject.Properties["runWatchMs"]
    if ($null -ne $declared -and [int]$declared.Value -gt 0) { return [int]$declared.Value }
    return [int][System.Math]::Min([double]$SettingMs, [double]$Relay.limits.maxWatchMs)
}

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

function Get-HordeRelayRunHeartbeatPath {
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    return [System.IO.Path]::Combine($HordeHome, "relay", "run-heartbeat.json")
}

function Get-HordeRelayRunTickSeconds {
    # How often this run promises to beat, at the least (A HEARTBEAT, in the header): its watch, plus
    # the longer of the longest backoff with its jitter and the shortest turn, rounded up, plus 5 s for
    # the turn's own work. A reader calls the run stale after three of these (core/Heartbeat.ps1).
    param([Parameter(Mandatory = $true)][int]$WatchMs, [Parameter(Mandatory = $true)]$Settings)
    $wait = [double]$Settings.backoffMaxMs * (1 + [double]$Settings.backoffJitterPercent / 100)
    $wait = [System.Math]::Max($wait, [double]$Settings.minTurnMs)
    return [int]([System.Math]::Ceiling(([double]$WatchMs + $wait) / 1000) + 5)
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

# What Receive-HordeRelayInbox runs between two slices of the turn's watch (SENDING DURING THE WATCH, in
# the header): handed the context and the run's own table for the watch, it answers $true to end the
# watch (a stop was asked). A block, because that is what the channels' port takes; the work is a
# function, so it is tested by name.
$script:HordeRelayRunBetweenSlices = { param($Context, $Watching) return (Invoke-HordeRelayRunSendCheck -Context $Context -Watching $Watching) }

function New-HordeRelayRunWatching {
    # The run's table for its looks during a watch: what Invoke-HordeRelayRunSendCheck needs, and what
    # it learns. failed is set at the top of every turn's watch; said is the run's, so a Glance that
    # cannot look says so once a run and not once a second.
    # hordeHome, tell and fromLabel are for the notes below (A FULL MAILBOX IS SAID PLAINLY, in the
    # header); notes is what the run has already said and told, by mailbox.
    param([Parameter(Mandatory = $true)][scriptblock]$Say, [Parameter(Mandatory = $true)][scriptblock]$Sleep, [Parameter(Mandatory = $true)][string]$StopPath,
        [Parameter(Mandatory = $true)][long]$StartedMs, [Parameter(Mandatory = $true)][int]$CheckMs, [string]$HordeHome = "", [bool]$Tell = $true, [string]$FromLabel = "")
    return @{ say = $Say; sleep = $Sleep; stopPath = $StopPath; startedMs = $StartedMs; checkMs = $CheckMs
        failed = $false; said = @{}; sinceLook = [System.Diagnostics.Stopwatch]::StartNew()
        hordeHome = $HordeHome; tell = $Tell; fromLabel = $FromLabel; notes = @{ full = @{}; untrimmed = @{} } }
}

function Invoke-HordeRelayRunPutNotes {
    # WHAT THE PUTS TOLD THE RUN, SAID AND ACTED ON (A FULL MAILBOX IS SAID PLAINLY, in the header): run
    # after every round of Ticks. Each thing is said once - when it begins, and when it is over - and
    # the warchief is told once of each mailbox that is full. -Seat, -TempRoot and -Now are for a suite.
    # Returns nothing; never throws for a messenger or a seat (cli/RelayRunTell.ps1 does not).
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)][hashtable]$Watching, [scriptblock]$Seat = $null, [string]$TempRoot = "", $Now = $null)
    if ($null -eq $Now) { $Now = [datetime]::UtcNow }
    $notes = $Watching.notes
    foreach ($box in @($Context.untrimmed.Keys | Sort-Object)) {
        if ($notes.untrimmed.ContainsKey($box)) { continue }
        $notes.untrimmed[$box] = $true
        $null = & $Watching.say ("NOT TRIMMED: the relay took what was sent to " + $box + " and deleted nothing older, though it was asked to (a relay that does not trim, or one deployed before it could). That mailbox is growing, and a full one is refused everything: deploy the relay.")
    }
    foreach ($box in @($notes.untrimmed.Keys | Sort-Object)) {
        if ($Context.untrimmed.ContainsKey($box)) { continue }
        $notes.untrimmed.Remove($box)
        $null = & $Watching.say ("the relay now trims " + $box + " as it is asked to")
    }
    foreach ($box in @($notes.full.Keys | Sort-Object)) {
        if ($Context.full.ContainsKey($box)) { continue }
        $notes.full.Remove($box)
        $null = & $Watching.say ("the relay takes mail for " + $box + " again: it is no longer full")
    }
    foreach ($box in @($Context.full.Keys | Sort-Object)) {
        if (-not $notes.full.ContainsKey($box)) {
            $notes.full[$box] = @{ told = $false; problem = ""; nextTry = [datetime]::MinValue }
            $null = & $Watching.say ("MAILBOX FULL: the relay refuses what this machine sends to " + $box + ", so NOTHING NEW REACHES THE FOUNDER'S PHONE from this machine until that is put right. The run keeps trying. What the relay answered: " + $Context.full[$box].reason)
            if (-not $Watching.tell) { $null = & $Watching.say ("the warchief is not told of it: telling is switched off (the setting tellWarchief)") }
        }
        $mine = $notes.full[$box]
        if ($mine.told -or -not $Watching.tell -or $Now -lt $mine.nextTry) { continue }
        $sent = Send-HordeRelayFullNotice -Mailbox $box -HordeHome $Watching.hordeHome -FromLabel $Watching.fromLabel -Seat $Seat -TempRoot $TempRoot -Day $Now
        if ($sent.told) { $mine.told = $true; $mine.problem = ""; $null = & $Watching.say ("the warchief was told that " + $box + " is full"); continue }
        # NOT TOLD: tried again later, and why is said only when it is a new reason.
        $mine.nextTry = $Now.AddSeconds($script:HordeRelayRunTellRetrySeconds)
        if ($sent.problem -cne $mine.problem) { $mine.problem = $sent.problem; $null = & $Watching.say ("the warchief was NOT told that " + $box + " is full: " + $sent.problem + ". It is tried again.") }
    }
}

function Invoke-HordeRelayRunSendCheck {
    # ONE LOOK BETWEEN TWO SLICES OF THE WATCH (SENDING DURING THE WATCH, in the header). $true when a
    # stop was asked: the watch then ends here. Otherwise $false, after running the Tick of every
    # channel whose Glance says it has something to send - unless a Tick has already failed in this
    # turn, when nothing more is sent before the turn's backoff.
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)][hashtable]$Watching)
    if (Test-HordeRelayRunStopAsked -Path $Watching.stopPath -StartedMs $Watching.startedMs) { return $true }
    # NEVER A SPIN: a slice that came back sooner than the interval is waited for here, in slices that
    # ask for a stop, so two looks are never closer than checkMs whatever the relay does.
    $early = [long]$Watching.checkMs - $Watching.sinceLook.ElapsedMilliseconds
    if ($early -gt 0 -and (Wait-HordeRelayRunSliced -Ms $early -Why "check" -Sleep $Watching.sleep -StopPath $Watching.stopPath -StartedMs $Watching.startedMs)) { return $true }
    try {
        if ($Watching.failed) { return $false }
        $look = Find-HordeRelayChannelsToSend -Context $Context
        foreach ($l in @($look.lines)) { if (-not $Watching.said.ContainsKey($l)) { $Watching.said[$l] = $true; $null = & $Watching.say $l } }
        if (@($look.due).Count -eq 0) { return $false }
        $ticked = Invoke-HordeRelayChannelTicks -Context $Context -Only @($look.due)
        foreach ($l in @($ticked.lines)) { $null = & $Watching.say $l }
        Invoke-HordeRelayRunPutNotes -Context $Context -Watching $Watching
        # A SEND THAT FAILS IS NOT TRIED AGAIN IN THIS WATCH: the turn counts as failed and backs off.
        if ($ticked.failed) { $Watching.failed = $true }
        return $false
    } finally { $Watching.sinceLook.Restart() }
}

function Test-HordeRelayRunContextKeys {
    # Use each key of a run's context once (relay/Keys.ps1, Test-HordeRelayKeyWorks): the signing key,
    # and every agreement key that may open. "" when all work, else which did not and why.
    param([Parameter(Mandatory = $true)]$Context)
    $why = Test-HordeRelayKeyWorks -KeyObject $Context.signKey -Use "sign"
    if ("" + $why -ne "") { return ("the signing key " + $Context.signKeyId + " could not be used: " + $why) }
    foreach ($id in @($Context.openingKeys.Keys)) {
        $why = Test-HordeRelayKeyWorks -KeyObject $Context.openingKeys[$id] -Use "agree"
        if ("" + $why -ne "") { return ("the agreement key " + $id + " could not be used: " + $why) }
    }
    return ""
}

function Open-HordeRelayRunProvenContext {
    # The run's context with its keys PROVED (the header): known, or unknown with why. A context whose
    # keys opened and cannot be used is closed again, never handed on.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)]$Connection, [string]$DecisionsRoot = "")
    $made = New-HordeRelayRunContext -HordeHome $HordeHome -Connection $Connection -DecisionsRoot $DecisionsRoot
    if ($made.state -cne "known") { return $made }
    $why = ""
    try { $why = Test-HordeRelayRunContextKeys -Context $made.value } catch { $why = $_.Exception.Message }
    if ("" + $why -eq "") { return $made }
    Close-HordeRelayRunContext -Context $made.value
    return (New-HordeUnknown -Reason ("the keys opened and cannot be used - " + $why))
}

function Invoke-HordeRelayRun {
    # The loop (the header). -Connection is a relays/Port.ps1 connection the caller made; -Say receives
    # each line the loop has to say (the command prints them). Returns { turns; failures; stoppedBy }.
    # -MaxTurns 0 runs until stopped. -Random is for a suite that fixes the jitter. -OpenContext
    # { param($HordeHome, $Connection, $DecisionsRoot) } opens the run's context with its keys proved
    # (Open-HordeRelayRunProvenContext), for a suite whose keys fail and then open.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)]$Connection, [Parameter(Mandatory = $true)][scriptblock]$Say,
        [int]$MaxTurns = 0, [string]$DecisionsRoot = "", $Random = $null, [scriptblock]$Sleep = $null, [scriptblock]$OpenContext = $null)
    if ($HordeHome -ceq "") { $HordeHome = Get-HordeHome }
    if ($null -eq $OpenContext) { $OpenContext = { param($H, $C, $D) Open-HordeRelayRunProvenContext -HordeHome $H -Connection $C -DecisionsRoot $D } }
    if ($null -eq $Random) { $Random = New-Object System.Random }
    if ($null -eq $Sleep) { $Sleep = { param($Ms, $Why) Start-Sleep -Milliseconds $Ms } }
    $settings = Get-HordeRelayRunSettings -HordeHome $HordeHome
    if ($settings.state -cne "known") { $null = & $Say ("the run does not start: " + $settings.reason); return [pscustomobject]@{ turns = 0; failures = 0; stoppedBy = "settings" } }
    $set = $settings.value
    $watchMs = Get-HordeRelayRunWatchMs -SettingMs $set.watchMs -Relay $Connection.relay
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
    # The heartbeat (header): who this run is, where it beats, and the tick it promises.
    $beatSelf = Get-HordeHeartbeatSelf
    $beatPath = Get-HordeRelayRunHeartbeatPath -HordeHome $HordeHome
    $beatTick = Get-HordeRelayRunTickSeconds -WatchMs $watchMs -Settings $set
    $beatFailed = $false
    $watching = New-HordeRelayRunWatching -Say $Say -Sleep $Sleep -StopPath $stopPath -StartedMs $startedMs -CheckMs ([int]$set.sendCheckMs) -HordeHome $HordeHome -Tell ([bool]$set.tellWarchief) -FromLabel ("" + $set.fromLabel)
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
                if ($null -eq $ctx) { $made = @(& $OpenContext $HordeHome $Connection $DecisionsRoot) | Select-Object -Last 1; if (-not (Test-HordeAnswer $made)) { $made = New-HordeUnknown -Reason "opening the keys did not answer" } }
                else { $made = Update-HordeRelayRunContext -Context $ctx }
                if ($made.state -ceq "known") {
                    $moved = ($null -eq $ctx -or $made.value.mailbox -cne $ctx.mailbox)
                    $ctx = $made.value; $lastCheck = [datetime]::UtcNow
                    if ($moved) { $null = & $Say ("watching " + $ctx.mailbox) }
                }
                elseif ($null -eq $ctx) { $failed = "this machine's relay keys cannot be opened: " + $made.reason }
                else { $null = & $Say ("the keys could not be opened again, so the run goes on with those it has: " + $made.reason) }
            }
            # One small write a turn, AFTER the keys were tried, so the first beat of a run is never a
            # healthy one it has not earned (the header). A failure is said once, and when it mends.
            $beatArgs = @{ Path = $beatPath; At = ([datetime]::UtcNow); ProcessId = $beatSelf.pid; ProcessStartedAt = $beatSelf.startedAt; TickSeconds = $beatTick; Pass = $turns }
            if ($null -eq $ctx) { $beatArgs["Condition"] = "keys-unavailable"; $beatArgs["Why"] = $failed }
            $beat = Write-HordeHeartbeatQuietly @beatArgs
            if ($beat.state -cne "known" -and -not $beatFailed) { $beatFailed = $true; $null = & $Say ("the heartbeat could not be written, and the run goes on without it: " + $beat.reason) }
            elseif ($beat.state -ceq "known" -and $beatFailed) { $beatFailed = $false; $null = & $Say "the heartbeat is being written again" }
            if ($failed -ceq "") {
                $r1 = Invoke-HordeRelayUnfinished -Context $ctx
                foreach ($l in @(Get-HordeRelayRunLines -Report $r1.value)) { $null = & $Say $l }
                $ticks = Invoke-HordeRelayChannelTicks -Context $ctx
                foreach ($l in @($ticks.lines)) { $null = & $Say $l }
                Invoke-HordeRelayRunPutNotes -Context $ctx -Watching $watching
                # A channel that asked to be turned again sooner (the decisions bell, at the end of a
                # quiet period) is: this watch waits no longer than it asked. A put still ends it at once.
                $turnWatch = Get-HordeRelayRunTurnWatchMs -WatchMs $watchMs -AgainMs $ticks.againMs
                # On a relay that watches in slices the watch is held open and the channels are looked at
                # between its slices (SENDING DURING THE WATCH, in the header); on any other, -Between is
                # never run and this is the one blocking watch it always was. A turn whose own Tick could
                # not send begins its watch as failed: nothing more is sent before the turn's backoff.
                $watching.failed = [bool]$ticks.failed; $watching.sinceLook.Restart()
                $in = Receive-HordeRelayInbox -Context $ctx -TimeoutMs $turnWatch -SliceMs ([int]$set.sendCheckMs) -Between $script:HordeRelayRunBetweenSlices -With $watching
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
                if ($failed -ceq "" -and $watching.failed) { $failed = "a channel could not send during the watch (above)" }
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

function Get-HordeRelayRunTurnWatchMs {
    # How long this turn's watch waits: the run's watch, or the channels' againMs when that is sooner.
    # 0 or less from the channels means nobody asked.
    param([Parameter(Mandatory = $true)][int]$WatchMs, $AgainMs = 0)
    if ($AgainMs -is [int] -and $AgainMs -gt 0 -and $AgainMs -lt $WatchMs) { return [int]$AgainMs }
    return $WatchMs
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
