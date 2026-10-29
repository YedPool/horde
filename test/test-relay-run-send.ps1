# DOES WHAT THE MACHINE HAS TO SEND GO OUT WHILE ITS WATCH IS STILL OPEN - WITHIN ABOUT A SECOND, NOT AT
# THE END OF THE WATCH - AND DOES LOOKING FOR IT COST THE RELAY NOTHING?
#
# cli/RelayRun.ps1, SENDING DURING THE WATCH (2026-10-13). The founder saw his own message go from his
# phone and then nothing for up to a minute: the runner sent only once a turn, and a turn is as long as
# its watch of the mailbox (60 s on the hosted relay). The runner now holds that one watch open and
# looks between its slices for something to send. This suite holds the runner to what that promises,
# over a relay in memory that COUNTS EVERY REQUEST made of it (test/lib/CountingRelay.ps1), because the
# hosted relay allows an account 20,000 requests a day and the promise is a number of requests:
#   - AN IDLE WATCH COSTS WHAT IT DID: one request a turn, however many times the run looked during it -
#     the same count as over the same relay with its watch in slices taken away;
#   - A CHANGE DURING THE WATCH IS SENT WITHIN THE LOOK'S INTERVAL, in that same watch (it is not ended
#     and opened again), and costs exactly the puts of that one send; over the blocking watch - how it
#     was - the same change waits for the watch to end (the control: the old behaviour fails this);
#   - A SEND THAT FAILS IS NOT TRIED AGAIN IN THAT WATCH, and the turn backs off as it always did;
#   - NO SPIN: a relay whose slices come back at once is looked at no more often than the interval;
#   - A STOP IS SEEN BETWEEN SLICES; and what arrived just before it is still read, journaled and acked;
#   - THE TURN IS NO LONGER THAN ITS WATCH, so the heartbeat's tick still says how often the run beats;
#   - A GLANCE THAT THROWS, or answers anything but a plain true, costs speed only: its channel is
#     ticked once a turn as before, and the fault is said once a run, not once a second;
#   - EACH REAL CHANNEL'S GLANCE - decisions, chat, progress - says yes exactly when its Tick has
#     something to send, and no for what it does not look at; and through a real turn the warchief's
#     note, the Thrall's reply and a progress entry written during the watch are each opened by the
#     phone from an envelope put during that same watch.
# THE PROBE CHANNEL. The runner's own rules are tested with a channel of the suite's (probe), whose Glance
# and Tick do exactly what a check sets, in a home with no phone key, so that no other channel sends and
# every request counted is the probe's or the run's own watch.
#
# The end to end with the real horde command as its own process is test/test-relay-phone-e2e.ps1.
#
# EVERY HORDE HOME IS A FOLDER OF THE SUITE'S OWN under %TEMP% (CONTRIBUTING 9); the fleet is pinned to an
# empty one of the suite's own, then to a synthetic one (test/lib/FleetPin.ps1, test/lib/ChatFleet.ps1);
# every key is made with the software provider and removed in the finally block. Off Windows there is no
# key store: the suite says so and exits 3.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
# No channel may find this machine's real Thrall (test/lib/FleetPin.ps1): first thing, before any loads.
. (Join-Path $root "test\lib\FleetPin.ps1")
$fleetPin = Enter-HordeTestEmptyFleet
. (Join-Path $root "core\ModuleSettings.ps1")
. (Join-Path $root "channels\Port.ps1")
foreach ($f in @(Get-HordeRelayFiles)) { . $f }
foreach ($f in @(Get-HordeRelayChannelFiles)) { . $f }
. (Join-Path $root "cli\RelayRun.ps1")
. (Join-Path $root "test\lib\RelayPhone.ps1")
. (Join-Path $root "test\lib\ChatFleet.ps1")
. (Join-Path $root "test\lib\CountingRelay.ps1")

# THE PROBE CHANNEL (the header). has: there is something to send; a Tick sends it - one put into the
# phone's mailbox - and has none left, unless the put was refused. Everything a check needs to count.
$script:probe = @{ has = $false; glances = 0; ticks = 0; throws = $false; says = $null; tickMs = 0; onGlance = $null }
$null = Register-HordeRelayChannel -Folder (Join-Path $env:TEMP "probe") -Name "probe" -Kinds @() -Senders "founder" `
    -Accept { param($Context, $Item) return [pscustomobject]@{ outcome = "refused"; reason = "the probe takes nothing in" } } `
    -Tick {
        param($Context)
        $script:probe.ticks++
        if (-not $script:probe.has) { return [pscustomobject]@{ lines = @(); failed = $false } }
        if ($script:probe.tickMs -gt 0) { Start-Sleep -Milliseconds $script:probe.tickMs }
        $put = Send-HordeRelayItem -Connection $Context.connection -Mailbox "work/phone" -Text ("probe-" + $script:probe.ticks)
        if ($put.state -cne "known") { return [pscustomobject]@{ lines = @("not sent: " + $put.reason); failed = $true } }
        $script:probe.has = $false
        return [pscustomobject]@{ lines = @("sent"); failed = $false }
    } `
    -Glance {
        param($Context)
        $script:probe.glances++
        if ($null -ne $script:probe.onGlance) { $null = & $script:probe.onGlance $script:probe.glances }
        if ($script:probe.throws) { throw "the probe's glance broke" }
        if ($null -ne $script:probe.says) { return $script:probe.says }
        return [bool]$script:probe.has
    }
Set-StrictMode -Version Latest
Write-Host ("  runtime: PowerShell " + $PSVersionTable.PSVersion + " (" + $PSVersionTable.PSEdition + ")") -ForegroundColor DarkGray

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$script:homes = New-Object System.Collections.ArrayList
$realHome = $env:HORDE_HOME
$thrall = $null

if ((Get-HordeRelayKeyStore).state -cne "known") {
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Exit-HordeTestEmptyFleet -Pin $fleetPin
    Complete-HordeSuite -Success "no key store here: no machine identity can be made, so nothing was run" -PassCode 3
}

function New-Id { return [guid]::NewGuid().ToString("N") }
function New-TestHome {
    $h = Join-Path $env:TEMP ("horde-relay-run-send-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path (Join-Path $h "settings") -Force | Out-Null
    [void]$script:homes.Add($h)
    [System.IO.File]::WriteAllText((Join-Path $h "settings\relay.json"), '{"schemaVersion": 1, "settings": {"horde": "work"}}', $utf8)
    return $h
}
function Get-TestKeyNames {
    param([string]$HordeHome)
    $out = New-Object System.Collections.ArrayList
    $dir = Join-Path $HordeHome "relay\identity"
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter "machine-*.json")) {
        $m = [regex]::Match([System.IO.File]::ReadAllText($f.FullName), '"scope":"([a-z]+)","signName":"([a-z0-9-]+)".*"agreeName":"([a-z0-9-]+)"')
        if ($m.Success) { [void]$out.Add(@{ n = $m.Groups[2].Value; s = $m.Groups[1].Value }); [void]$out.Add(@{ n = $m.Groups[3].Value; s = $m.Groups[1].Value }) }
    }
    return @($out)
}
function New-World {
    # A machine (home, identity), a phone paired and confirmed - and, unless -NoPhoneKey, its identity key
    # in the trust store, which is what makes the real channels send - over the counting relay.
    param([switch]$NoPhoneKey)
    $h = New-TestHome
    $id = New-HordeRelayMachineIdentity -HordeHome $h -Provider "software"
    if ($id.state -cne "known") { throw ("no identity: " + $id.reason) }
    $phone = New-HordeTestPhone
    [void](Add-HordeTestPhonePairing -HordeHome $h -Phone $phone)
    if (-not $NoPhoneKey) {
        $v = New-HordeTestPhoneVouch -Phone $phone -Horde "work"
        $k = Add-HordeRelayPhoneKey -HordeHome $h -AgreePublic $phone.agreePublic -By $phone.keyId -AuthenticatorData $v.authenticatorData -ClientDataJson $v.clientDataJson -Signature $v.signature
        if ($k.state -cne "known") { throw ("no phone key: " + $k.reason) }
    }
    return [pscustomobject]@{ home = $h; id = $id.value; phone = $phone; store = (Join-Path $h "store\decisions") }
}
function Set-RunSettings {
    param($World, [string]$Json)
    [System.IO.File]::WriteAllText((Join-Path $World.home "settings\relay-run.json"), ('{"schemaVersion": 1, "settings": ' + $Json + '}'), $utf8)
}
function Invoke-Run {
    # The loop itself, in this process, over the counting relay: { r; said; text; ms; slept }. -Sleep
    # $true records every wait the loop asks for, with why, and then really waits it.
    param($World, [int]$Turns = 1)
    $env:HORDE_HOME = $World.home
    $said = New-Object System.Collections.ArrayList
    $script:slept = New-Object System.Collections.ArrayList
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $r = Invoke-HordeRelayRun -HordeHome $World.home -Connection $script:conn -MaxTurns $Turns -Say { param($Line) [void]$said.Add($Line) } -Sleep { param($Ms, $Why) [void]$script:slept.Add([pscustomobject]@{ ms = [long]$Ms; why = "$Why" }); Start-Sleep -Milliseconds $Ms }
    $sw.Stop()
    return [pscustomobject]@{ r = $r; said = @($said.ToArray()); text = (@($said.ToArray()) -join " | "); ms = $sw.ElapsedMilliseconds; slept = @($script:slept.ToArray()) }
}
function Reset-Probe { $script:probe.has = $false; $script:probe.glances = 0; $script:probe.ticks = 0; $script:probe.throws = $false; $script:probe.says = $null; $script:probe.tickMs = 0; $script:probe.onGlance = $null }
function Get-Ops { param([switch]$Requests) return (@(Get-HordeCountingRelayLog -Requests:$Requests | ForEach-Object { $_.op }) -join ",") }
function Get-PhoneBodies {
    # What the world's phone opens of its mailbox after relay seq -Since: each envelope's body.
    param($World, [long]$Since = 0)
    $got = Receive-HordeRelayItems -Connection $script:conn -Mailbox "work/phone" -Since $Since
    $out = New-Object System.Collections.ArrayList
    if ($got.state -cne "known") { return @() }
    foreach ($it in @($got.value.items)) {
        $o = Open-HordeTestPhoneEnvelope -Phone $World.phone -Text $it.text -MachineSignPublic $World.id.sign.public
        if ($o.ok) { [void]$out.Add($o.body) }
    }
    return @($out.ToArray())
}

try {
    Reset-HordeCountingRelay
    $connected = Connect-HordeRelay -Name "counting" -Options @{}
    Check ($connected.state -ceq "known" -and (Test-HordeRelayWatchInSlices $connected.value)) "CONTROL: the counting relay is connected, and watches in slices"
    $script:conn = $connected.value

    Write-Host ""
    Write-Host "--- an idle watch costs the relay what it always did: one request, however often the run looks ---" -ForegroundColor Cyan
    $P = New-World -NoPhoneKey
    Set-RunSettings $P '{"watchMs": 1000, "sendCheckMs": 200, "minTurnMs": 50}'
    Reset-Probe
    $a = Invoke-Run $P -Turns 3
    $sliced = Get-Ops -Requests
    $waits = @(Get-HordeCountingRelayLog | Where-Object { $_.op -ceq "wait" }).Count
    Check ($a.r.turns -eq 3 -and $sliced -ceq "watch-open,watch-open,watch-open") ("three idle turns, each a watch held open in slices, are three requests - one a watch, and nothing else (" + $sliced + ")")
    Check ($waits -ge 9 -and $script:probe.glances -ge 9) ("while those three watches were open the run waited on them a slice at a time and looked at its channels between slices, costing no request (" + $waits + " slices, " + $script:probe.glances + " looks)")
    Check ($script:probe.ticks -eq 3) ("and a channel with nothing to send was ticked once a turn, as before, not once a look (" + $script:probe.ticks + ")")
    # THE HEARTBEAT STAYS TRUTHFUL: the tick it promises is still computed from the watch and the longest
    # backoff, and three turns of a 1 s watch took about three seconds - the looking added no time to a turn.
    $beat = Read-HordeHeartbeat -Path (Get-HordeRelayRunHeartbeatPath -HordeHome $P.home)
    $promised = Get-HordeRelayRunTickSeconds -WatchMs 1000 -Settings (Get-HordeRelayRunSettings -HordeHome $P.home).value
    Check ($beat.state -ceq "known" -and $beat.value.pass -eq 3 -and $beat.value.tickSeconds -eq $promised -and $promised -eq 78) ("the heartbeat's tick is what it was - the watch, the longest backoff with its jitter, and 5 s (" + $promised + " s)")
    $spans = @(Get-HordeCountingRelayLog | Where-Object { $_.op -ceq "watch-open" -or $_.op -ceq "watch-close" })
    $lengths = @(0..2 | ForEach-Object { [long]($spans[2 * $_ + 1].at - $spans[2 * $_].at).TotalMilliseconds })
    Check ($spans.Count -eq 6 -and @($lengths | Where-Object { $_ -lt 900 -or $_ -gt 1600 }).Count -eq 0) ("and each watch was open for its own second, no longer for having been looked into: " + ($lengths -join ", ") + " ms")
    # THE SAME RELAY WITH ITS WATCH IN SLICES TAKEN AWAY is how every relay was watched before: the same count.
    Set-HordeCountingRelaySlices -On $false
    Clear-HordeCountingRelayLog
    Reset-Probe
    $b = Invoke-Run $P -Turns 3
    $blocking = Get-Ops -Requests
    Check ($b.r.turns -eq 3 -and $blocking -ceq "watch,watch,watch" -and @(Get-HordeCountingRelayLog -Requests).Count -eq @($sliced -split ",").Count) ("over the blocking watch the same three idle turns are the same three requests (" + $blocking + "): looking during the watch added none")
    Check ($script:probe.glances -eq 0 -and $script:probe.ticks -eq 3 -and @(Get-HordeCountingRelayLog | Where-Object { $_.op -ceq "wait" }).Count -eq 0) ("and a relay that does not watch in slices is watched exactly as before: nothing is looked at during its watch (" + $script:probe.glances + " looks)")
    Set-HordeCountingRelaySlices -On $true

    Write-Host ""
    Write-Host "--- a change during the watch is sent in that watch, within the interval, for the cost of the send alone ---" -ForegroundColor Cyan
    Set-RunSettings $P '{"watchMs": 20000, "sendCheckMs": 200, "minTurnMs": 50}'
    Clear-HordeCountingRelayLog
    Reset-Probe
    $script:changedAt = $null
    # In the watch's second slice something appears to send; once it is at the relay, the run is asked to stop.
    Set-HordeCountingRelayHook -Hook {
        param($n)
        if ($n -eq 2) { $script:probe.has = $true; $script:changedAt = [datetime]::UtcNow }
        if (@(Get-HordeCountingRelayLog | Where-Object { $_.op -ceq "put" }).Count -gt 0) { [void](Request-HordeRelayRunStop -HordeHome $P.home) }
    }
    $c = Invoke-Run $P -Turns 5
    Set-HordeCountingRelayHook -Hook $null
    $log = @(Get-HordeCountingRelayLog)
    $put = @($log | Where-Object { $_.op -ceq "put" })
    $opened = @($log | Where-Object { $_.op -ceq "watch-open" })
    $closed = @($log | Where-Object { $_.op -ceq "watch-close" })
    $delay = $(if ($put.Count -ge 1 -and $null -ne $script:changedAt) { [long]($put[0].at - $script:changedAt).TotalMilliseconds } else { [long]-1 })
    Check ($put.Count -eq 1 -and $delay -ge 0 -and $delay -lt 1000) ("what a channel has to send two tenths of a second into a 20 s watch is at the relay " + $delay + " ms later - within the 200 ms interval and the send's own work - not at the end of the watch")
    Check ($opened.Count -eq 1 -and $closed.Count -eq 1 -and $put.Count -eq 1 -and $put[0].n -gt $opened[0].n -and $put[0].n -lt $closed[0].n) ("it is sent while the watch is open: the one watch is not ended and opened again for it (" + (Get-Ops) + ")")
    Check ((Get-Ops -Requests) -ceq "watch-open,put") ("and the whole turn cost the relay the watch and that one put - the requests of one send and no more (" + (Get-Ops -Requests) + ")")
    Check ($script:probe.ticks -eq 2 -and $c.text.Contains("probe: sent")) ("the channel was ticked at the top of the turn and once more when its Glance said yes, and the run said what it sent (" + $script:probe.ticks + " ticks)")
    # A STOP ASKED DURING THE WATCH is seen between two slices: the 20 s watch did not have to run out.
    Check ($c.r.stoppedBy -ceq "stop file" -and $c.r.turns -eq 1 -and $c.ms -lt 8000) ("a stop asked during a 20 s watch ends the run between two slices of it (" + $c.ms + " ms, " + $c.r.stoppedBy + ", " + $c.r.turns + " turn)")

    # THE CONTROL - HOW IT WAS. Over the blocking watch the same change waits for the watch to end.
    Set-HordeCountingRelaySlices -On $false
    Set-RunSettings $P '{"watchMs": 1500, "sendCheckMs": 200, "minTurnMs": 50}'
    Clear-HordeCountingRelayLog
    Reset-Probe
    $script:changedAt = $null
    Set-HordeCountingRelayHook -Hook { param($n) if ($null -eq $script:changedAt -and $n -ge 5) { $script:probe.has = $true; $script:changedAt = [datetime]::UtcNow } }
    $d = Invoke-Run $P -Turns 2
    Set-HordeCountingRelayHook -Hook $null
    Set-HordeCountingRelaySlices -On $true
    $log = @(Get-HordeCountingRelayLog)
    $put = @($log | Where-Object { $_.op -ceq "put" })
    $ended = @($log | Where-Object { $_.op -ceq "watch-end" })
    $late = $(if ($put.Count -ge 1 -and $null -ne $script:changedAt) { [long]($put[0].at - $script:changedAt).TotalMilliseconds } else { [long]-1 })
    Check ($put.Count -eq 1 -and $ended.Count -ge 1 -and $put[0].n -gt $ended[0].n -and $late -ge 1000) ("CONTROL, how it was: over a blocking watch of 1.5 s the same change, a tenth of a second in, is sent only after the watch has ended, " + $late + " ms later - the old behaviour fails the check above (" + (Get-Ops) + ")")

    Write-Host ""
    Write-Host "--- a send that fails is not tried again in that watch, and the turn backs off as it always did ---" -ForegroundColor Cyan
    Set-RunSettings $P '{"watchMs": 1500, "sendCheckMs": 200, "minTurnMs": 50, "backoffMinMs": 100, "backoffMaxMs": 400, "backoffJitterPercent": 0}'
    Clear-HordeCountingRelayLog
    Reset-Probe
    Set-HordeCountingRelayFaults -Faults @("refuse-put")
    Set-HordeCountingRelayHook -Hook { param($n) if ($n -eq 2 -and $script:probe.ticks -le 1) { $script:probe.has = $true } }
    $e = Invoke-Run $P -Turns 2
    Set-HordeCountingRelayHook -Hook $null
    $log = @(Get-HordeCountingRelayLog)
    $firstClose = @($log | Where-Object { $_.op -ceq "watch-close" })[0].n
    $putsInWatch = @($log | Where-Object { $_.op -ceq "put" -and $_.n -lt $firstClose }).Count
    $slicesAfter = @($log | Where-Object { $_.op -ceq "wait" -and $_.n -lt $firstClose -and $_.n -gt @($log | Where-Object { $_.op -ceq "put" })[0].n }).Count
    Check ($putsInWatch -eq 1 -and $slicesAfter -ge 3) ("a put the relay refuses during the watch is made once, and not again in the " + $slicesAfter + " slices of that watch that follow, though the channel still has it to send (" + $putsInWatch + " put)")
    Check ($e.text.Contains("a channel could not send during the watch (above); waiting 100 ms (failure 1 in a row)") -and @($e.slept | Where-Object { $_.why -ceq "backoff" }).Count -eq 1 -and @($e.slept | Where-Object { $_.why -ceq "backoff" })[0].ms -eq 100) ("the turn counts as failed and waits out its backoff before the next, exactly as a failed send at the top of a turn does (" + (@($e.slept | ForEach-Object { $_.why + " " + $_.ms }) -join ", ") + ")")
    Check ($e.r.failures -eq 2 -and @($log | Where-Object { $_.op -ceq "put" }).Count -eq 2) ("the next turn's own Tick tries it again, once, and its failure is the second in a row (" + $e.r.failures + ")")
    Set-HordeCountingRelayFaults -Faults @()
    Clear-HordeCountingRelayLog
    $e2 = Invoke-Run $P -Turns 1
    Check ($e2.r.failures -eq 0 -and $script:probe.has -eq $false -and (Get-Ops -Requests).StartsWith("put,watch-open")) ("and once the relay takes puts again, the turn's Tick sends it and the failures start again from none (" + (Get-Ops -Requests) + ")")

    Write-Host ""
    Write-Host "--- no spin: a relay whose slices come back at once is looked at no more often than the interval ---" -ForegroundColor Cyan
    Set-RunSettings $P '{"watchMs": 1000, "sendCheckMs": 200, "minTurnMs": 50}'
    Clear-HordeCountingRelayLog
    Reset-Probe
    Set-HordeCountingRelayFaults -Faults @("instant")
    $s = Invoke-Run $P -Turns 1
    Set-HordeCountingRelayFaults -Faults @()
    $pads = @($s.slept | Where-Object { $_.why -ceq "check" })
    Check ($script:probe.glances -ge 3 -and $script:probe.glances -le 7) ("over a relay whose every slice returns at once, a 1 s watch is looked into about five times - once an interval of 200 ms - not as fast as the loop can turn (" + $script:probe.glances + " looks)")
    Check ($pads.Count -ge 3 -and @($pads | Where-Object { $_.ms -gt 200 -or $_.ms -le 0 }).Count -eq 0) ("because the run itself waits out what is left of each interval, in waits that ask for a stop (" + (@($pads | ForEach-Object { $_.ms }) -join ",") + ")")
    Check ((Get-Ops -Requests) -ceq "watch-open") ("and it is still one request (" + (Get-Ops -Requests) + ")")

    Write-Host ""
    Write-Host "--- a stop between slices; and what arrived just before it is still read, journaled and acked ---" -ForegroundColor Cyan
    Set-RunSettings $P '{"watchMs": 20000, "sendCheckMs": 200, "minTurnMs": 50}'
    Clear-HordeCountingRelayLog
    Reset-Probe
    Set-HordeCountingRelayHook -Hook { param($n) if ($n -eq 2) { [void](Request-HordeRelayRunStop -HordeHome $P.home) } }
    $t = Invoke-Run $P -Turns 5
    Set-HordeCountingRelayHook -Hook $null
    Check ($t.r.stoppedBy -ceq "stop file" -and $t.r.turns -eq 1 -and $t.ms -lt 6000) ("a stop asked in the second slice of a 20 s watch ends the run after that slice, not after the watch (" + $t.ms + " ms)")
    # Something arrives AFTER the last slice returned and BEFORE the run sees the stop: here, while the
    # run waits out the rest of an interval over a relay whose slices return at once. It must be in this
    # turn's batch - asked for once more, without waiting, before the watch is let go.
    Clear-HordeCountingRelayLog
    Reset-Probe
    Set-HordeCountingRelayFaults -Faults @("instant")
    $env:HORDE_HOME = $P.home
    $said = New-Object System.Collections.ArrayList
    $script:arrived = $false
    $late = {
        param($Ms, $Why)
        if ("$Why" -ceq "check" -and -not $script:arrived) {
            $script:arrived = $true
            [void](Send-HordeRelayItem -Connection $script:conn -Mailbox $P.id.mailbox -Text "this-is-not-an-envelope")
            [void](Request-HordeRelayRunStop -HordeHome $P.home)
        }
        Start-Sleep -Milliseconds $Ms
    }
    $r = Invoke-HordeRelayRun -HordeHome $P.home -Connection $script:conn -MaxTurns 5 -Say { param($Line) [void]$said.Add($Line) } -Sleep $late
    Set-HordeCountingRelayFaults -Faults @()
    $ops = Get-Ops -Requests
    Check ($r.stoppedBy -ceq "stop file" -and $r.turns -eq 1 -and (@($said) -join " | ").Contains("refused item 1: not an envelope") -and $ops -ceq "watch-open,put,ack") ("an item that arrives as the stop is asked is in that turn's batch: judged, and the relay acked through it, before the watch is let go (" + $ops + ")")

    Write-Host ""
    Write-Host "--- the watch's time runs while a send works: a turn is no longer than its watch ---" -ForegroundColor Cyan
    Set-RunSettings $P '{"watchMs": 1500, "sendCheckMs": 200, "minTurnMs": 50}'
    Clear-HordeCountingRelayLog
    Reset-Probe
    $script:probe.tickMs = 700
    Set-HordeCountingRelayHook -Hook { param($n) if ($n -eq 2 -and $script:probe.ticks -le 1) { $script:probe.has = $true } }
    $h = Invoke-Run $P -Turns 1
    Set-HordeCountingRelayHook -Hook $null
    $log = @(Get-HordeCountingRelayLog)
    $open = @($log | Where-Object { $_.op -ceq "watch-open" })[0]
    $close = @($log | Where-Object { $_.op -ceq "watch-close" })[0]
    $watchMs = [long]($close.at - $open.at).TotalMilliseconds
    Check (@($log | Where-Object { $_.op -ceq "put" }).Count -eq 1 -and $watchMs -ge 1400 -and $watchMs -lt 2100) ("a send that took 0.7 s of a 1.5 s watch did not make the watch 2.2 s: it was open " + $watchMs + " ms, so the turn the heartbeat's tick is computed from is as long as it was")

    Write-Host ""
    Write-Host "--- a Glance that throws, or answers anything but a plain true, costs speed and nothing else ---" -ForegroundColor Cyan
    Set-RunSettings $P '{"watchMs": 1000, "sendCheckMs": 200, "minTurnMs": 50}'
    Clear-HordeCountingRelayLog
    Reset-Probe
    $script:probe.throws = $true
    $g = Invoke-Run $P -Turns 2
    $told = @($g.said | Where-Object { "$_".Contains("probe: could not look for something to send") })
    Check ($script:probe.glances -ge 6 -and $told.Count -eq 1 -and "$($told[0])".Contains("the probe's glance broke")) ("a Glance that throws on every look is said once in a run, with its reason, not once a look (" + $script:probe.glances + " looks, " + $told.Count + " line)")
    Check ($g.r.turns -eq 2 -and $g.r.failures -eq 0 -and $script:probe.ticks -eq 2 -and (Get-Ops -Requests) -ceq "watch-open,watch-open") ("and its channel is ticked once a turn, as with no Glance at all: the run turns on, and nothing counts as failed (" + $script:probe.ticks + " ticks)")
    foreach ($word in @("yes", 1, "true")) {
        Reset-Probe
        $script:probe.says = $word
        $look = Find-HordeRelayChannelsToSend -Context ([pscustomobject]@{ state = @{} })
        Check (@($look.due) -cnotcontains "probe" -and @($look.lines).Count -eq 0) ("a Glance that answers " + $word.GetType().Name + " '" + $word + "' is a no: only a plain true is a yes")
    }
    Reset-Probe
    $script:probe.has = $true
    $look = Find-HordeRelayChannelsToSend -Context ([pscustomobject]@{ state = @{} })
    Check ((@($look.due) -join ",") -ceq "probe") ("a Glance that answers true is the one channel to tick: the others, with nothing a look can see, are not (" + (@($look.due) -join ",") + ")")
    Check (Throws { Register-HordeRelayChannel -Folder (Join-Path $env:TEMP "glanceonly") -Name "glanceonly" -Kinds @() -Senders "founder" -Accept { } -Glance { $true } } "a Glance and no Tick") "a channel may not register a Glance with no Tick: there would be nothing it asks about"

    Write-Host ""
    Write-Host "--- the interval is a setting, held between a fifth of a second and the longest watch ---" -ForegroundColor Cyan
    $defaults = New-TestHome
    Check ((Get-HordeRelayRunSettings -HordeHome $defaults).value.sendCheckMs -eq 1000) "with no settings file the run looks once a second"
    foreach ($bad in @(199, 60001)) {
        Set-RunSettings $P ('{"sendCheckMs": ' + $bad + '}')
        $refusedRun = Invoke-Run $P -Turns 1
        Check ($refusedRun.r.stoppedBy -ceq "settings" -and $refusedRun.text.Contains("sendCheckMs")) ("an interval of " + $bad + " ms is refused by the settings, in their own words, and the run does not start")
    }

    # ---------------------------------------------------------------------------------------------
    # THE REAL CHANNELS, with a phone whose key is trusted, a synthetic Thrall and a progress log.
    # ---------------------------------------------------------------------------------------------
    $canAdd = Invoke-HordeDecision -Operation "add" -Root (Join-Path (New-TestHome) "store\decisions") -Request @{ id = (New-Id); actor = "warchief"; question = @{ title = "Can this runtime add a question here?"; kind = "yes-no"; whatItIs = "A probe."; group = "probe"; askedBy = "suite" } }
    $script:canDecide = ($canAdd.state -ceq "known" -and $canAdd.value.outcome -ceq "done")
    Reset-Probe
    Reset-HordeCountingRelay
    $chatFixtures = @(Get-HordeTestChatFixtureFiles | ForEach-Object { . $_ -Root $root })
    $thrall = New-HordeTestChatThrall -Fixtures $chatFixtures
    Check ($null -ne $thrall) "CONTROL: a conversation adapter's fixture made a synthetic fleet with a Thrall"
    Add-HordeTestChatTurns -Thrall $thrall -Turns @(@{ role = "user"; text = "are you there?" }, @{ role = "assistant"; text = "here." })
    $W = New-World
    $env:HORDE_HOME = $W.home
    [System.IO.File]::WriteAllText((Join-Path $W.home "settings\relay-chat.json"), '{"schemaVersion": 1, "settings": {"sendIntervalMs": 0, "startTurns": 3}}', $utf8)
    [System.IO.File]::WriteAllText((Join-Path $W.home "settings\relay-progress.json"), '{"schemaVersion": 1, "settings": {"sendIntervalMs": 0}}', $utf8)
    $logFile = Join-Path $W.home "progress\changelog.jsonl"
    New-Item -ItemType Directory -Path (Split-Path -Parent $logFile) -Force | Out-Null
    [System.IO.File]::WriteAllText($logFile, ('{"v":1,"id":"e1","ts":"2026-10-13T08:00:00Z","title":"first","text":"the first entry"}' + "`n"), $utf8)
    if ($script:canDecide) {
        $q = Invoke-HordeDecision -Operation "add" -Root $W.store -Request @{ id = (New-Id); actor = "warchief"; question = @{ title = "Should the closing sound play when the assistant closes?"; kind = "yes-no"; whatItIs = "The app has no closing sound today."; group = "voice"; askedBy = "orc-b" } }
        Check ($q.state -ceq "known" -and $q.value.outcome -ceq "done") "CONTROL: the world has one open question"
    } else { Write-Host "  [SKIP] the decisions list cannot add a question under this runtime (issue #173): the decisions channel's checks are skipped, and the suite exits 3" -ForegroundColor Yellow }

    Write-Host ""
    Write-Host "--- each channel's Glance says yes exactly when its Tick has something to send ---" -ForegroundColor Cyan
    $made = New-HordeRelayRunContext -HordeHome $W.home -Connection $script:conn
    $ctx = $made.value
    try {
        $due = { return (@((Find-HordeRelayChannelsToSend -Context $ctx).due | Where-Object { $_ -cne "probe" }) -join ",") }
        Check ((& $due) -ceq "") ("before the first Tick no Glance says yes: the first look, and whom to send to, are the Tick's (" + (& $due) + ")")
        $first = Invoke-HordeRelayChannelTicks -Context $ctx
        $firstText = (@($first.lines) -join " | ")
        Check ($firstText.Contains("2 turn(s) of the Thrall") -and $firstText.Contains("1 progress entry") -and (-not $script:canDecide -or $firstText.Contains("snapshot of 1 open question(s)")) -and -not $first.failed) ("CONTROL: the first Tick of each channel sends what there is (" + $firstText + ")")
        Check ((& $due) -ceq "") ("with nothing new, no Glance says yes (" + (& $due) + ")")
        $ticksBefore = $script:probe.ticks
        $null = Invoke-HordeRelayChannelTicks -Context $ctx -Only @("progress")
        Check ($script:probe.ticks -eq $ticksBefore) "a Tick asked of one channel by name ticks that one and no other"
        # A SLICE IS NEVER LONGER THAN THE RELAY LETS A WATCH BE: asked for more, the watch is still made.
        $script:between = 0
        $held = Receive-HordeRelayInbox -Context $ctx -TimeoutMs 150 -SliceMs 999999 -Between { param($c, $with) $script:between++; return $false } -With $null
        Check ($held.state -ceq "known" -and @($held.value.taken).Count -eq 0) ("a watch asked for in slices longer than the relay's longest watch is made all the same, in slices of the relay's longest (" + $held.state + ")")
        Clear-HordeCountingRelayLog
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        foreach ($i in 1..20) { $null = Find-HordeRelayChannelsToSend -Context $ctx }
        $each = [Math]::Round($sw.ElapsedMilliseconds / 20, 1)
        Check ((Get-Ops) -ceq "" -and $each -lt 100) ("twenty rounds of every Glance make no request of the relay at all, and are cheap (" + $each + " ms a round)")
        # DECISIONS: a record written to the store - the warchief's note under the question.
        if ($script:canDecide) {
            $null = Invoke-HordeDecision -Operation "say" -Root $W.store -Request @{ id = (New-Id); actor = "warchief"; number = 1; speaker = "warchief"; route = "command"; text = "A chime it is."; asks = $false }
            Check ((& $due) -ceq "decisions") ("a record written to the decisions store is seen by the decisions Glance, and by no other (" + (& $due) + ")")
            $again = Invoke-HordeRelayChannelTicks -Context $ctx -Only @("decisions")
            Check ((@($again.lines) -join " ").Contains("snapshot of 1 open question(s)") -and (& $due) -ceq "") "its Tick sends the new snapshot, and the Glance is a no again"
            # WAITING ENVELOPES ARE THE TURN'S, NOT THE GLANCE'S: a no while one is recorded and not put.
            Set-HordeCountingRelayFaults -Faults @("refuse-put")
            $null = Invoke-HordeDecision -Operation "say" -Root $W.store -Request @{ id = (New-Id); actor = "warchief"; number = 1; speaker = "warchief"; route = "command"; text = "The second of the three."; asks = $false }
            $refusedTick = Invoke-HordeRelayChannelTicks -Context $ctx -Only @("decisions")
            $null = Invoke-HordeDecision -Operation "say" -Root $W.store -Request @{ id = (New-Id); actor = "warchief"; number = 1; speaker = "warchief"; route = "command"; text = "And quiet."; asks = $false }
            Check ($refusedTick.failed -and (& $due) -ceq "") ("while a snapshot is recorded and the relay has not taken it, the decisions Glance says no even to a newer record: putting it again is the turn's Tick's, after the backoff (" + (& $due) + ")")
            Set-HordeCountingRelayFaults -Faults @()
            $null = Invoke-HordeRelayChannelTicks -Context $ctx -Only @("decisions")
        }
        # CHAT AND PROGRESS THE SAME: with turns, or entries, recorded and not taken by the relay, a no.
        Set-HordeCountingRelayFaults -Faults @("refuse-put")
        Add-HordeTestChatTurns -Thrall $thrall -Turns @(@{ role = "assistant"; text = "recorded, and the relay will not take it" })
        [System.IO.File]::AppendAllText($logFile, ('{"v":1,"id":"w1","ts":"2026-10-13T08:00:30Z","title":"waiting","text":"recorded, and the relay will not take it"}' + "`n"), $utf8)
        $refusedTick = Invoke-HordeRelayChannelTicks -Context $ctx -Only @("chat", "progress")
        Add-HordeTestChatTurns -Thrall $thrall -Turns @(@{ role = "assistant"; text = "written while the first waits" })
        [System.IO.File]::AppendAllText($logFile, ('{"v":1,"id":"w2","ts":"2026-10-13T08:00:40Z","title":"waiting too","text":"written while the first waits"}' + "`n"), $utf8)
        Check ($refusedTick.failed -and (& $due) -ceq "") ("while turns and entries are recorded and the relay has not taken them, the chat and the progress Glance say no even to newer ones (" + (& $due) + ")")
        Set-HordeCountingRelayFaults -Faults @()
        $null = Invoke-HordeRelayChannelTicks -Context $ctx -Only @("chat", "progress")
        $null = Invoke-HordeRelayChannelTicks -Context $ctx -Only @("chat", "progress")
        Check ((& $due) -ceq "") ("CONTROL: once the relay takes them, and what was written meanwhile is sent, every Glance is a no again (" + (& $due) + ")")
        # CHAT: the Thrall writes a turn.
        Add-HordeTestChatTurns -Thrall $thrall -Turns @(@{ role = "assistant"; text = "the build is green" })
        Check ((& $due) -ceq "chat") ("a turn the Thrall writes is seen by the chat Glance, and by no other (" + (& $due) + ")")
        $again = Invoke-HordeRelayChannelTicks -Context $ctx -Only @("chat")
        Check ((@($again.lines) -join " ").Contains("1 turn(s) of the Thrall") -and (& $due) -ceq "") "its Tick sends the turn, and the Glance is a no again"
        # INSIDE sendIntervalMs OF THE LAST SEND the Tick would send nothing, so the Glance says no.
        [System.IO.File]::WriteAllText((Join-Path $W.home "settings\relay-chat.json"), '{"schemaVersion": 1, "settings": {"sendIntervalMs": 60000, "startTurns": 3}}', $utf8)
        $null = Invoke-HordeRelayChannelTicks -Context $ctx -Only @("chat")
        Add-HordeTestChatTurns -Thrall $thrall -Turns @(@{ role = "assistant"; text = "said inside the interval" })
        $ctx.state["chat"].lastSentAt = [datetime]::UtcNow
        $inside = & $due
        $ctx.state["chat"].lastSentAt = [datetime]::UtcNow.AddMinutes(-2)
        Check ($inside -ceq "" -and (& $due) -ceq "chat") ("inside sendIntervalMs of the last send the chat Glance says no, and once it has passed, yes (" + $inside + " / " + (& $due) + ")")
        [System.IO.File]::WriteAllText((Join-Path $W.home "settings\relay-chat.json"), '{"schemaVersion": 1, "settings": {"sendIntervalMs": 0, "startTurns": 3}}', $utf8)
        $null = Invoke-HordeRelayChannelTicks -Context $ctx -Only @("chat")
        # PROGRESS: a line appended to the log; and a line its writer has not finished.
        [System.IO.File]::AppendAllText($logFile, ('{"v":1,"id":"e2","ts":"2026-10-13T08:01:00Z","title":"second","text":"the second entry"}' + "`n"), $utf8)
        Check ((& $due) -ceq "progress") ("a line appended to the progress log is seen by the progress Glance, and by no other (" + (& $due) + ")")
        $again = Invoke-HordeRelayChannelTicks -Context $ctx -Only @("progress")
        Check ((@($again.lines) -join " ").Contains("1 progress entry") -and (& $due) -ceq "") "its Tick sends the entry, and the Glance is a no again"
        [System.IO.File]::AppendAllText($logFile, ('{"v":1,"id":"e2b","ts":"2026-10-13T08:01:30Z","title":"second and a half","text":"written inside the interval"}' + "`n"), $utf8)
        $ctx.state["progress"]["sendIntervalMs"] = [long]60000
        $ctx.state["progress"].lastSentAt = [datetime]::UtcNow
        $inside = & $due
        $ctx.state["progress"].lastSentAt = [datetime]::UtcNow.AddMinutes(-2)
        Check ($inside -ceq "" -and (& $due) -ceq "progress") ("inside sendIntervalMs of the last send the progress Glance says no, and once it has passed, yes (" + $inside + " / " + (& $due) + ")")
        $null = Invoke-HordeRelayChannelTicks -Context $ctx -Only @("progress")
        # A PHONE KEY TRUSTED SINCE is not something a Glance looks for: the trust store is the Tick's.
        $second = New-HordeTestPhone
        [void](Add-HordeTestPhonePairing -HordeHome $W.home -Phone $second)
        $v2 = New-HordeTestPhoneVouch -Phone $second -Horde "work"
        $k2 = Add-HordeRelayPhoneKey -HordeHome $W.home -AgreePublic $second.agreePublic -By $second.keyId -AuthenticatorData $v2.authenticatorData -ClientDataJson $v2.clientDataJson -Signature $v2.signature
        Check ($k2.state -ceq "known" -and (& $due) -ceq "") ("a phone key trusted since is NOT seen by any Glance - none reads the trust store - and is the turn's own Tick's to send to, as it always was (" + (& $due) + ")")
        $catchUp = Invoke-HordeRelayChannelTicks -Context $ctx
        Check (-not $catchUp.failed -and (@($catchUp.lines) -join " ").Contains("turn(s) of the Thrall")) "and the turn's Tick does send to it"
    } finally { Close-HordeRelayRunContext -Context $ctx }

    Write-Host ""
    Write-Host "--- through a real turn: a note, the Thrall's reply and a progress entry written during the watch are opened by the phone from that same watch ---" -ForegroundColor Cyan
    Set-RunSettings $W '{"watchMs": 30000, "sendCheckMs": 200, "minTurnMs": 50}'
    $before = @((Receive-HordeRelayItems -Connection $script:conn -Mailbox "work/phone" -Since 0).value.items).Count
    Clear-HordeCountingRelayLog
    $script:changedAt = $null
    $script:wrote = 0
    $script:want = $(if ($script:canDecide) { 3 } else { 2 })
    $script:sendCapMs = 20000
    $script:capHit = $false
    # Slice 3 of the turn's watch: all three are written, as a warchief, a Thrall and a fleet's log would.
    # When the three envelopes that follow are at the relay, the run is asked to stop.
    Set-HordeCountingRelayHook -Hook {
        param($n)
        if ($n -eq 3 -and $script:wrote -eq 0) {
            $script:wrote = 1
            if ($script:canDecide) { $null = Invoke-HordeDecision -Operation "say" -Root $W.store -Request @{ id = (New-Id); actor = "warchief"; number = 1; speaker = "warchief"; route = "command"; text = "Written while the watch was open."; asks = $false } }
            if ($env:HORDE_TEST_RUNSEND_WITHHOLD -cne "1") { Add-HordeTestChatTurns -Thrall $thrall -Turns @(@{ role = "assistant"; text = "replied while the watch was open" }) }
            [System.IO.File]::AppendAllText($logFile, ('{"v":1,"id":"e3","ts":"2026-10-13T08:02:00Z","title":"third","text":"logged while the watch was open"}' + "`n"), $utf8)
            $script:changedAt = [datetime]::UtcNow
            # TEST-ONLY KNOBS (never read by production code), to prove this check waits on the event and not on a clock:
            # HORDE_TEST_RUNSEND_DELAY_MS holds the run this long before it can send; HORDE_TEST_RUNSEND_WITHHOLD=1 sends nothing.
            if ($env:HORDE_TEST_RUNSEND_DELAY_MS) { Start-Sleep -Milliseconds ([int]$env:HORDE_TEST_RUNSEND_DELAY_MS) }
        }
        # THE EVENT IS WHAT IS WAITED ON: the watch stays open until all the envelopes are at the relay, or until the cap.
        if ($script:wrote -eq 1 -and ([datetime]::UtcNow - $script:changedAt).TotalMilliseconds -ge $script:sendCapMs) { $script:capHit = $true; [void](Request-HordeRelayRunStop -HordeHome $W.home) }
        if ($script:wrote -eq 1 -and @(Get-HordeCountingRelayLog | Where-Object { $_.op -ceq "put" -and $_.at -gt $script:changedAt }).Count -ge $script:want) { [void](Request-HordeRelayRunStop -HordeHome $W.home) }
    }
    $live = Invoke-Run $W -Turns 5
    Set-HordeCountingRelayHook -Hook $null
    $log = @(Get-HordeCountingRelayLog)
    $opened = @($log | Where-Object { $_.op -ceq "watch-open" })
    $closed = @($log | Where-Object { $_.op -ceq "watch-close" })
    $during = @($log | Where-Object { $_.op -ceq "put" -and $null -ne $script:changedAt -and $_.at -gt $script:changedAt })
    $slowest = $(if ($during.Count -gt 0) { [long](($during | ForEach-Object { ($_.at - $script:changedAt).TotalMilliseconds } | Measure-Object -Maximum).Maximum) } else { [long]-1 })
    Check ($live.r.turns -eq 1 -and $live.r.stoppedBy -ceq "stop file" -and $opened.Count -eq 1 -and $closed.Count -eq 1) ("CONTROL: it all happened in one turn, in one watch, which the stop then ended (" + $live.r.turns + " turn, " + $opened.Count + " watch)")
    Check ($during.Count -eq $script:want -and @($during | Where-Object { $_.n -lt $opened[0].n -or $_.n -gt $closed[0].n }).Count -eq 0 -and $slowest -ge 0) ("each channel's envelope was put while that watch was open, the last of them " + $slowest + " ms after the three were written, the watch held open for them up to " + $script:sendCapMs + " ms (" + $during.Count + " puts)")
    if ($script:capHit -or $during.Count -ne $script:want) { Write-Host ("  NEVER ARRIVED: " + ($script:want - $during.Count) + " of " + $script:want + " envelopes (the decisions note, the Thrall's chat reply, the progress entry) were not at the relay " + $script:sendCapMs + " ms after they were written; the cap was " + $(if ($script:capHit) { "hit" } else { "not hit" })) -ForegroundColor Red }
    Check (@($log | Where-Object { $_.request -and $_.n -gt $opened[0].n }).Count -eq $script:want) ("and after the watch was opened the relay was asked for those " + $script:want + " puts and nothing else: " + (@($log | Where-Object { $_.request -and $_.n -gt $opened[0].n } | ForEach-Object { $_.op }) -join ","))
    $bodies = @(Get-PhoneBodies -World $W -Since $before)
    $chatSeen = @($bodies | Where-Object { $_.kind -ceq "chat-turns" } | ForEach-Object { @($_.turns) } | ForEach-Object { $_.text })
    $progressSeen = @($bodies | Where-Object { $_.kind -ceq "progress-entries" } | ForEach-Object { @($_.entries) } | ForEach-Object { $_.text })
    Check ($chatSeen -ccontains "replied while the watch was open") ("the phone opens the Thrall's reply from an envelope of that watch (" + ($chatSeen -join " | ") + ")")
    Check ($progressSeen -ccontains "logged while the watch was open") ("and the progress entry (" + ($progressSeen -join " | ") + ")")
    if ($script:canDecide) {
        $snaps = @($bodies | Where-Object { $_.kind -ceq "decisions-snapshot" })
        $notes = @($snaps | ForEach-Object { @($_.questions) } | ForEach-Object { @($_.thread.messages) } | ForEach-Object { $_.text })
        Check ($notes -ccontains "Written while the watch was open.") ("and the warchief's note, in the snapshot of the open question (" + (@($notes | Select-Object -Last 2) -join " | ") + ")")
    }

    Write-Host ""
    Write-Host "--- what a Glance must not hurry: a progress log that was replaced, and a home with no phone to send to ---" -ForegroundColor Cyan
    $made = New-HordeRelayRunContext -HordeHome $W.home -Connection $script:conn
    $ctx = $made.value
    try {
        $null = Invoke-HordeRelayChannelTicks -Context $ctx
        [System.IO.File]::WriteAllText($logFile, ('{"v":1,"id":"x1","ts":"2026-10-13T09:00:00Z","title":"another file","text":"not the log that was followed"}' + "`n"), $utf8)
        $stopped = Invoke-HordeRelayChannelTicks -Context $ctx -Only @("progress")
        [System.IO.File]::AppendAllText($logFile, ('{"v":1,"id":"x2","ts":"2026-10-13T09:00:10Z","title":"more of it","text":"and it goes on changing"}' + "`n"), $utf8)
        $look = @((Find-HordeRelayChannelsToSend -Context $ctx).due)
        Check ((@($stopped.lines) -join " ").Contains("progress is stopped") -and $look -cnotcontains "progress") ("a progress log that was replaced stops the channel, and its Glance then says no however the file goes on changing: nothing of it is sent (" + ($look -join ",") + ")")
    } finally { Close-HordeRelayRunContext -Context $ctx }
    if ($script:canDecide) {
        $env:HORDE_HOME = $P.home
        $made = New-HordeRelayRunContext -HordeHome $P.home -Connection $script:conn
        $ctx = $made.value
        try {
            $null = Invoke-HordeRelayChannelTicks -Context $ctx
            $null = Invoke-HordeDecision -Operation "add" -Root $P.store -Request @{ id = (New-Id); actor = "warchief"; question = @{ title = "A question in a home with no phone?"; kind = "yes-no"; whatItIs = "Nobody to send it to."; group = "voice"; askedBy = "orc-b" } }
            $look = @((Find-HordeRelayChannelsToSend -Context $ctx).due)
            Check ($look -cnotcontains "decisions") ("with no phone key trusted the decisions Tick has made no fingerprint, and its Glance says no to a new record: there is nobody to send it to (" + ($look -join ",") + ")")
        } finally { Close-HordeRelayRunContext -Context $ctx }
    }
} finally {
    Set-HordeCountingRelayHook -Hook $null
    Remove-HordeTestChatThrall -Thrall $thrall
    Exit-HordeTestEmptyFleet -Pin $fleetPin
    $env:HORDE_HOME = $realHome
    $made = New-Object System.Collections.ArrayList
    foreach ($h in @($script:homes)) {
        foreach ($k in @(Get-TestKeyNames -HordeHome $h)) {
            [void]$made.Add($k)
            try { [void](Remove-HordeRelayKey -Name $k.n -Scope $k.s) } catch { Write-Host ("  cleanup of " + $k.n + " failed: " + $_.Exception.Message) -ForegroundColor Yellow }
        }
    }
    $left = @($made | Where-Object { (Find-HordeRelayCngKey -Name $_.n -Scope $_.s) -cne "" })
    Check ($made.Count -ge 4 -and $left.Count -eq 0) ("every key the suite's homes name is gone (" + $made.Count + " names, " + $left.Count + " left)")
    foreach ($h in @($script:homes)) {
        if ((Split-Path -Leaf $h) -match '^horde-relay-run-send-[0-9a-f]{32}$') { Remove-Item -LiteralPath $h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Check (@($script:homes | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 0) "every temporary home is gone"
}
Check ($env:HORDE_HOME -ceq $realHome) "HORDE_HOME is what it was"

if (-not $script:canDecide) { Complete-HordeSuite -Success "the runner's own rules and the chat and progress channels hold under this runtime; what needs the decisions list was skipped (issue #173)" -PassCode 3 }
Complete-HordeSuite -Success "what the machine has to send goes out while its watch is open, within the interval, for the cost of the send alone; an idle watch costs what it did; a failed send backs off; nothing spins; and a stop is prompt"
