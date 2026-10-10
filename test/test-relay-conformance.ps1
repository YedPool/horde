# DOES EVERY RELAY KEEP THE MAILBOX CONTRACT, SHOW EACH CAPABILITY IT CLAIMS, AND DOES THE CLIENT SURVIVE ONE THAT LIES?
#
# Relay design 2026-10-09, PR plan item 3. Generated from each relay's capabilities.json, as the
# transport and messenger conformance suites are from theirs: this suite names no relay. It loads every
# relays/<name>/Relay.ps1 and that relay's test fixture, and holds each one to three things.
#
# I. THE CONTRACT EVERY RELAY KEEPS, whatever it declares: an empty mailbox reads empty; seqs start at
#    1, are contiguous and come back in put order; a read is bounded by its batch and resumes from its
#    cursor, on a new connection too; mailboxes are separate; a put is idempotent by key (an envelope's
#    replay key, or with none the text's hash) and the first put stands; a text of exactly maxTextChars
#    is kept whole and one character more is refused - by the port, and by the relay itself when the
#    port is bypassed; a watch returns at once when there is something, waits out its timeout when
#    there is not, and is bounded by it; an ack past the head is refused and an ack does not disturb
#    a read after it.
# II. EACH CAPABILITY OF THE CLOSED LIST: a "yes" must be DEMONSTRATED by the case below, or the suite
#    fails; any other word must make a caller that requires it refuse the relay, by name. durable is
#    shown across a fresh runspace (no state of this one survives into it), and realtime by a put from a
#    fresh runspace while this one is already waiting. A capability added to the list with no case here
#    fails the suite.
# III. THE CLIENT SURVIVES A HOSTILE RELAY (test/lib/HostileRelay.ps1): read to the end through a
#    relay that reorders, repeats, drops, re-serves stale items, overfills batches and mixes in
#    malformed items, the client gets each seq at most once, in order, with the text that was put under
#    it, never a malformed one; the loop ends; and every hole between delivered items is reported.
#    What a relay drops after the last delivered item cannot be seen here: that is the journal's to
#    catch, by each sender's own seq inside the envelope.
#
# THE FIXTURE. relays/<name>/test/Fixture.ps1, run with -Root, returns one object of script blocks:
#   New     ()            -> a state whose .options connect to an empty relay of the test's own
#   Remove  param($State) -  removes everything New made
#   Remote  param($State) -> options for a second client that reaches the same relay as another
#                            machine would; required only of a relay that says reach.remote yes
# A fixture writes nothing outside the temp folder and the relay it made.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "relays\Port.ps1")
foreach ($f in @(Get-HordeRelayFiles)) { . $f }
# Only the relays under relays/ are held to the contract; the hostile one is loaded after, for III.
$relayNames = @(Get-HordeRelayNames)
. (Join-Path $root "test\lib\HostileRelay.ps1")

function Connect-Fixture {
    param($Relay, $Options)
    $a = Connect-HordeRelay -Name $Relay.name -Options $Options
    if ($a.state -cne "known") { throw ("could not connect to relay " + $Relay.name + ": " + $a.reason) }
    return $a.value
}
function Seqs { param($Answer) return (@($Answer.value.items | ForEach-Object { $_.seq }) -join ",") }
function Texts { param($Answer) return (@($Answer.value.items | ForEach-Object { $_.text }) -join ",") }

# A FRESH RUNSPACE: the port and every relay loaded anew, connected with the same options, and -Body run
# there with the connection. The body travels as TEXT and is made into a script block over there: a
# script block object carried across would run back in this runspace, and prove nothing.
$script:FreshCode = @'
param($Port, $Name, $Options, $Body, $Arguments)
. $Port
foreach ($f in @(Get-HordeRelayFiles)) { . $f }
$a = Connect-HordeRelay -Name $Name -Options $Options
if ($a.state -cne "known") { return ("connect failed: " + $a.reason) }
& ([scriptblock]::Create($Body)) $a.value @Arguments
'@
function New-Fresh {
    param([string]$Name, $Options, [scriptblock]$Body, [object[]]$Arguments = @())
    $ps = [PowerShell]::Create()
    [void]$ps.AddScript($script:FreshCode).AddArgument((Join-Path $root "relays\Port.ps1")).AddArgument($Name).AddArgument($Options).AddArgument($Body.ToString()).AddArgument($Arguments)
    return $ps
}
function Invoke-Fresh {
    param([string]$Name, $Options, [scriptblock]$Body, [object[]]$Arguments = @())
    $ps = New-Fresh -Name $Name -Options $Options -Body $Body -Arguments $Arguments
    try { return @($ps.Invoke() | ForEach-Object { "$_" }) } finally { $ps.Dispose() }
}

# Every capability of the closed list must have a case here. Each case gets the relay, its fixture and
# a fresh state, and returns $true when the capability was shown.
$cases = [ordered]@{
    "durable" = {
        param($R, $Fx, $State)
        $c = Connect-Fixture $R $State.options
        $mb = "conf/durable"
        foreach ($t in @("durable-1", "durable-2", "durable-3")) { $null = Send-HordeRelayItem -Connection $c -Mailbox $mb -Text $t }
        $first = Receive-HordeRelayItems -Connection $c -Mailbox $mb -Since 0 -Max 2
        $out = @(Invoke-Fresh -Name $R.name -Options $State.options -Arguments @($mb, $first.value.next) -Body {
                param($Conn, $Mailbox, $Since)
                $r = Receive-HordeRelayItems -Connection $Conn -Mailbox $Mailbox -Since $Since
                $p = Send-HordeRelayItem -Connection $Conn -Mailbox $Mailbox -Text "durable-4"
                return @((@($r.value.items | ForEach-Object { $_.text }) -join ","), $p.value.seq)
            })
        return ((Seqs $first) -ceq "1,2" -and $out.Count -eq 2 -and $out[0] -ceq "durable-3" -and $out[1] -ceq "4")
    }
    "realtime" = {
        param($R, $Fx, $State)
        $c = Connect-Fixture $R $State.options
        $mb = "conf/realtime"
        $timeout = [Math]::Min(15000, $R.limits.maxWatchMs)
        # THREE ROUNDS, EVERY ONE WITHIN A SECOND: where the put lands in a slow relay's poll depends on how
        # long the other runspace took to start, so one round is luck. A relay polling every 1.5 s passed
        # a single round and failed the next run (mutation runs, 2026-10-09); every round must hold.
        $ok = $true
        for ($round = 1; $round -le 3; $round++) {
            $ps = New-Fresh -Name $R.name -Options $State.options -Arguments @($mb, $round) -Body {
                param($Conn, $Mailbox, $Round)
                Start-Sleep -Milliseconds 400
                $p = Send-HordeRelayItem -Connection $Conn -Mailbox $Mailbox -Text ("realtime-" + $Round)
                return @($p.state, [datetime]::UtcNow.Ticks)
            }
            try {
                $h = $ps.BeginInvoke()
                $w = Wait-HordeRelayItems -Connection $c -Mailbox $mb -Since ($round - 1) -TimeoutMs $timeout
                $back = [datetime]::UtcNow.Ticks
                $out = @($ps.EndInvoke($h) | ForEach-Object { "$_" })
            } finally { $ps.Dispose() }
            if ($out.Count -ne 2 -or $out[0] -cne "known") { Write-Host ("    the other runspace's put: " + ($out -join " | ")); return $false }
            $lagMs = ($back - [long]$out[1]) / 10000
            Write-Host ("    round " + $round + ": the watch returned " + [Math]::Round($lagMs) + " ms after the other runspace's put, having waited " + $w.value.waitedMs + " ms")
            $ok = $ok -and ($w.state -ceq "known" -and (Texts $w) -ceq ("realtime-" + $round) -and $w.value.waitedMs -lt $timeout -and $lagMs -lt 1000)
        }
        return $ok
    }
    "reach.remote" = {
        param($R, $Fx, $State)
        if ($null -eq $Fx.PSObject.Properties["Remote"]) { Write-Host "    the fixture has no Remote: nothing can show another machine reaching it"; return $false }
        $c = Connect-Fixture $R $State.options
        $far = Connect-Fixture $R (& $Fx.Remote $State)
        $mb = "conf/remote"
        $p = Send-HordeRelayItem -Connection $far -Mailbox $mb -Text "remote-1"
        $r = Receive-HordeRelayItems -Connection $c -Mailbox $mb -Since 0
        return ($p.state -ceq "known" -and (Texts $r) -ceq "remote-1")
    }
    "trim.on.ack" = {
        param($R, $Fx, $State)
        $c = Connect-Fixture $R $State.options
        $mb = "conf/trim"
        foreach ($t in @("trim-1", "trim-2", "trim-3")) { $null = Send-HordeRelayItem -Connection $c -Mailbox $mb -Text $t }
        $k = Confirm-HordeRelayItems -Connection $c -Mailbox $mb -Through 2
        $r = Receive-HordeRelayItems -Connection $c -Mailbox $mb -Since 0
        $p = Send-HordeRelayItem -Connection $c -Mailbox $mb -Text "trim-4"
        # EVERYTHING ACKED, THEN A PUT: with no item left to count from, only the relay's memory of what it
        # trimmed keeps the next seq from being 1 again (the local relay's floor marker; a mutant that
        # forgot it survived the case above, 2026-10-09).
        $all = Confirm-HordeRelayItems -Connection $c -Mailbox $mb -Through 4
        $empty = Receive-HordeRelayItems -Connection $c -Mailbox $mb -Since 0
        $p5 = Send-HordeRelayItem -Connection $c -Mailbox $mb -Text "trim-5"
        return ($k.state -ceq "known" -and (Seqs $r) -ceq "3" -and $p.value.seq -eq 4 -and $all.state -ceq "known" -and @($empty.value.items).Count -eq 0 -and $p5.value.seq -eq 5)
    }
}

Write-Host ""
Write-Host "--- the cases cover the closed list of capabilities, no more and no less ---" -ForegroundColor Cyan
$listed = @(Get-HordeRelayCapabilityNames)
Check ((@($listed | Sort-Object) -join ",") -ceq (@($cases.Keys | Sort-Object) -join ",")) ("every capability has a case here, and every case a capability (" + ($listed -join ", ") + ")")
Check ($relayNames.Count -ge 1) ("at least one relay is loaded from relays/ (" + ($relayNames -join ", ") + ")")
Check ($relayNames -cnotcontains "hostile") "and the hostile test relay is not among them"

foreach ($name in $relayNames) {
    $r = Get-HordeRelay -Name $name
    $lim = $r.limits
    Write-Host ""
    Write-Host ("--- relay " + $name + ": I. the contract ---") -ForegroundColor Cyan
    $fxPath = Join-Path $r.folder "test\Fixture.ps1"
    Check (Test-Path -LiteralPath $fxPath -PathType Leaf) ("[" + $name + "] has a test fixture at test\Fixture.ps1")
    if (-not (Test-Path -LiteralPath $fxPath -PathType Leaf)) { continue }
    $fx = & $fxPath -Root $root
    $state = & $fx.New
    try {
        $c = Connect-Fixture $r $state.options
        $a = Receive-HordeRelayItems -Connection $c -Mailbox "conf/empty" -Since 0
        Check ($a.state -ceq "known" -and @($a.value.items).Count -eq 0 -and $a.value.next -eq 0 -and @($a.value.anomalies).Count -eq 0) ("[" + $name + "] a mailbox nobody wrote reads empty, known")

        $mb = "conf/ordering"
        $puts = @(1..5 | ForEach-Object { Send-HordeRelayItem -Connection $c -Mailbox $mb -Text ("ordering-" + $_) })
        Check ((@($puts | ForEach-Object { "$($_.state):$($_.value.seq):$($_.value.duplicate)" }) -join ",") -ceq "known:1:False,known:2:False,known:3:False,known:4:False,known:5:False") ("[" + $name + "] five puts are numbered 1 to 5, none a duplicate")
        $a = Receive-HordeRelayItems -Connection $c -Mailbox $mb -Since 0
        Check ((Seqs $a) -ceq "1,2,3,4,5" -and (Texts $a) -ceq "ordering-1,ordering-2,ordering-3,ordering-4,ordering-5" -and @($a.value.anomalies).Count -eq 0) ("[" + $name + "] they read back in put order, each with its own text, with no anomaly")
        $a = Receive-HordeRelayItems -Connection $c -Mailbox $mb -Since 0 -Max 2
        Check ((Seqs $a) -ceq "1,2" -and $a.value.next -eq 2 -and @($a.value.anomalies).Count -eq 0) ("[" + $name + "] a read of 2 gets the first two, and the cursor is at 2, with no anomaly: the relay itself kept to the batch")
        $a = Receive-HordeRelayItems -Connection $c -Mailbox $mb -Since $a.value.next
        Check ((Seqs $a) -ceq "3,4,5" -and $a.value.next -eq 5 -and @($a.value.anomalies).Count -eq 0) ("[" + $name + "] resuming from that cursor gets the rest, with no anomaly")
        $a = Receive-HordeRelayItems -Connection $c -Mailbox $mb -Since 5
        Check ($a.state -ceq "known" -and @($a.value.items).Count -eq 0 -and $a.value.next -eq 5) ("[" + $name + "] resuming from the head gets nothing, and the cursor stays")
        $c2 = Connect-Fixture $r $state.options
        $a = Receive-HordeRelayItems -Connection $c2 -Mailbox $mb -Since 3
        Check ((Seqs $a) -ceq "4,5") ("[" + $name + "] a second connection resumes from a cursor the first one handed out")
        $a = Receive-HordeRelayItems -Connection $c -Mailbox $mb -Since 1000
        Check ($a.state -ceq "known" -and @($a.value.items).Count -eq 0 -and $a.value.next -eq 1000) ("[" + $name + "] a cursor past the head reads empty")

        $o = Send-HordeRelayItem -Connection $c -Mailbox "conf/other" -Text "other-1"
        $a = Receive-HordeRelayItems -Connection $c -Mailbox $mb -Since 0
        Check ($o.value.seq -eq 1 -and (Seqs $a) -ceq "1,2,3,4,5") ("[" + $name + "] a second mailbox numbers from 1 and leaves the first untouched")
        $o = Send-HordeRelayItem -Connection $c -Mailbox "conf2/ordering" -Text "other-horde-1"
        Check ($o.value.seq -eq 1) ("[" + $name + "] the same reader in another horde is another mailbox")

        $mb = "conf/idempotent"
        $key = "0123456789abcdef0123456789abcdef/decisions/1/00112233445566778899aabb"
        $p1 = Send-HordeRelayItem -Connection $c -Mailbox $mb -Text "idem-a" -Key $key
        $p2 = Send-HordeRelayItem -Connection $c -Mailbox $mb -Text "idem-a" -Key $key
        $p3 = Send-HordeRelayItem -Connection $c -Mailbox $mb -Text "idem-a-resigned" -Key $key
        Check ($p1.value.duplicate -eq $false -and $p2.value.duplicate -eq $true -and $p3.value.duplicate -eq $true -and $p2.value.seq -eq $p1.value.seq -and $p3.value.seq -eq $p1.value.seq) ("[" + $name + "] a put of a key already held is a duplicate with the held seq, whatever its text")
        $h1 = Send-HordeRelayItem -Connection $c -Mailbox $mb -Text "idem-b"
        $h2 = Send-HordeRelayItem -Connection $c -Mailbox $mb -Text "idem-b"
        Check ($h1.value.duplicate -eq $false -and $h2.value.duplicate -eq $true -and $h2.value.seq -eq $h1.value.seq -and $h1.value.seq -eq 2) ("[" + $name + "] with no key, the same text twice is a duplicate by its hash")
        $a = Receive-HordeRelayItems -Connection $c -Mailbox $mb -Since 0
        Check ((Texts $a) -ceq "idem-a,idem-b" -and $a.value.items[0].key -ceq $key) ("[" + $name + "] the mailbox holds each once, the first text standing, under its key")

        # TWO WRITERS AT ONCE, each in its own runspace with its own connection: no seq is given twice and
        # none is skipped, and every put is kept.
        $mb = "conf/concurrent"
        $writers = @(foreach ($w in @("a", "b")) {
                New-Fresh -Name $r.name -Options $state.options -Arguments @($mb, $w) -Body {
                    param($Conn, $Mailbox, $Who)
                    $bad = 0
                    for ($i = 1; $i -le 15; $i++) { if ((Send-HordeRelayItem -Connection $Conn -Mailbox $Mailbox -Text ("concurrent-" + $Who + "-" + $i)).state -cne "known") { $bad++ } }
                    return $bad
                }
            })
        try {
            $handles = @($writers | ForEach-Object { $_.BeginInvoke() })
            $bad = 0
            for ($i = 0; $i -lt $writers.Count; $i++) { foreach ($o in @($writers[$i].EndInvoke($handles[$i]))) { $bad += [int]"$o" } }
        } finally { foreach ($w in $writers) { $w.Dispose() } }
        $a = Receive-HordeRelayItems -Connection $c -Mailbox $mb -Since 0 -Max ([Math]::Min(256, $lim.maxBatch))
        $want = (1..30) -join ","
        Check ($bad -eq 0 -and (Seqs $a) -ceq $want -and @($a.value.items | ForEach-Object { $_.text } | Sort-Object -Unique).Count -eq 30) ("[" + $name + "] two writers putting at once get seqs 1 to 30 between them, each put kept once (" + $bad + " failed)")

        $mb = "conf/size"
        $max = $lim.maxTextChars
        $big = "y" * $max
        $p = Send-HordeRelayItem -Connection $c -Mailbox $mb -Text $big
        $a = Receive-HordeRelayItems -Connection $c -Mailbox $mb -Since 0
        Check ($p.state -ceq "known" -and @($a.value.items).Count -eq 1 -and $a.value.items[0].text -ceq $big) ("[" + $name + "] a text of exactly maxTextChars (" + $max + ") is kept whole")
        $p = Send-HordeRelayItem -Connection $c -Mailbox $mb -Text ($big + "y")
        Check ($p.state -ceq "unknown") ("[" + $name + "] one character more is refused by the port")
        $raw = $null
        try { $raw = & $r.put $c.state $mb "raw-oversize" ("z" * ($max + 1)) } catch { $raw = $null }
        $a = Receive-HordeRelayItems -Connection $c -Mailbox $mb -Since 0
        Check (-not ((Test-HordeAnswer $raw) -and $raw.state -ceq "known") -and @($a.value.items).Count -eq 1) ("[" + $name + "] and by the relay itself when the port is bypassed: nothing is stored")

        $t = [Math]::Min(600, $lim.maxWatchMs)
        $w = Wait-HordeRelayItems -Connection $c -Mailbox "conf/watch-empty" -Since 0 -TimeoutMs $t
        Check ($w.state -ceq "known" -and @($w.value.items).Count -eq 0 -and $w.value.waitedMs -ge ($t - 100) -and $w.value.waitedMs -lt ($t + 3000)) ("[" + $name + "] a watch with nothing to see waits out its " + $t + " ms and no more than 3 s past it (" + $w.value.waitedMs + " ms)")
        $w = Wait-HordeRelayItems -Connection $c -Mailbox "conf/ordering" -Since 3 -TimeoutMs ([Math]::Min(10000, $lim.maxWatchMs))
        Check ($w.state -ceq "known" -and (Seqs $w) -ceq "4,5" -and $w.value.waitedMs -lt 1000) ("[" + $name + "] a watch with something to see returns it at once (" + $w.value.waitedMs + " ms)")
        $w = Wait-HordeRelayItems -Connection $c -Mailbox "conf/watch-empty" -Since 0 -TimeoutMs 0
        Check ($w.state -ceq "known" -and $w.value.waitedMs -lt 1000) ("[" + $name + "] a watch of 0 ms is a read (" + $w.value.waitedMs + " ms)")

        $k = Confirm-HordeRelayItems -Connection $c -Mailbox "conf/ordering" -Through 6
        Check ($k.state -ceq "unknown") ("[" + $name + "] an ack past the head (5) is refused")
        $k1 = Confirm-HordeRelayItems -Connection $c -Mailbox "conf/ordering" -Through 2
        $k2 = Confirm-HordeRelayItems -Connection $c -Mailbox "conf/ordering" -Through 2
        $k0 = Confirm-HordeRelayItems -Connection $c -Mailbox "conf/ordering" -Through 0
        Check ($k1.state -ceq "known" -and $k2.state -ceq "known" -and $k0.state -ceq "known") ("[" + $name + "] an ack is repeatable, and an ack behind an earlier one is accepted")
        $a = Receive-HordeRelayItems -Connection $c -Mailbox "conf/ordering" -Since 2
        Check ((Seqs $a) -ceq "3,4,5") ("[" + $name + "] a read after the acked cursor is untouched")
        $p = Send-HordeRelayItem -Connection $c -Mailbox "conf/ordering" -Text "ordering-6"
        Check ($p.value.seq -eq 6) ("[" + $name + "] numbering continues after an ack")
    } finally { & $fx.Remove $state }

    Write-Host ""
    Write-Host ("--- relay " + $name + ": II. what it claims ---") -ForegroundColor Cyan
    foreach ($cap in $listed) {
        $support = Get-HordeRelaySupport -Relay $r -Capability $cap
        $state = & $fx.New
        try {
            if ($support -ceq "yes") {
                $shown = & $cases[$cap] $r $fx $state
                Check ($shown -eq $true) ("[" + $name + "] " + $cap + " is yes, and the case shows it")
            } else {
                $res = Resolve-HordeRelay -Name $name -Require @($cap)
                $found = Find-HordeRelay -Require @($cap)
                Check ($res.state -ceq "unknown" -and "$($res.reason)".Contains($cap) -and -not ($found.state -ceq "known" -and @($found.value) -ccontains $name)) ("[" + $name + "] " + $cap + " is " + $support + ", and a caller that requires it is refused it")
            }
        } finally { & $fx.Remove $state }
    }
}

Write-Host ""
Write-Host "--- III. the client survives a hostile relay ---" -ForegroundColor Cyan

Reset-HordeHostileRelay
$hc = (Connect-HordeRelay -Name "hostile" -Options @{}).value
$mb = "conf/hostile"
$put = @{}
for ($i = 1; $i -le 10; $i++) { $p = Send-HordeRelayItem -Connection $hc -Mailbox $mb -Text ("hostile-" + $i); $put[[long]$p.value.seq] = "hostile-" + $i }
Set-HordeHostileRelayFaults -Faults @("reorder", "duplicate", "drop", "stale", "garbage", "overbatch")
$since = [long]0; $got = New-Object System.Collections.ArrayList; $anoms = New-Object System.Collections.ArrayList; $rounds = 0; $allKnown = $true
while ($rounds -lt 30) {
    $rounds++
    $a = Wait-HordeRelayItems -Connection $hc -Mailbox $mb -Since $since -Max 3 -TimeoutMs 0
    if ($a.state -cne "known") { $allKnown = $false; break }
    foreach ($it in @($a.value.items)) { [void]$got.Add($it) }
    foreach ($x in @($a.value.anomalies)) { [void]$anoms.Add($x) }
    if ($a.value.next -eq $since) { break }
    if ($a.value.next -lt $since) { $allKnown = $false; break }
    $since = $a.value.next
}
$seqs = @($got | ForEach-Object { $_.seq })
Check ($allKnown -and $rounds -lt 30) ("reading to the end ends, every answer known and no cursor moving back (" + $rounds + " rounds)")
Check (($seqs -join ",") -ceq "1,3,5,7,9") ("each seq at most once, in order, through reorder, repeats, stale items and overfilled batches (" + ($seqs -join ",") + ")")
Check (@($got | Where-Object { $put[[long]$_.seq] -cne $_.text }).Count -eq 0) "every text delivered is the one put under its seq: no malformed item got through"
foreach ($hole in @(2, 4, 6, 8)) {
    Check (@($anoms | Where-Object { "$_".Contains("gap: seq " + $hole + " to " + $hole) }).Count -ge 1) ("the dropped seq " + $hole + ", between two delivered ones, is reported as a gap")
}
Check (@($anoms | Where-Object { "$_".Contains("not an object") }).Count -ge 1 -and @($anoms | Where-Object { "$_".Contains("at or before the cursor") }).Count -ge 1 -and @($anoms | Where-Object { "$_".Contains("came twice") }).Count -ge 1) "and the malformed, stale and repeated items are reported, not delivered"
Set-HordeHostileRelayFaults -Faults @()

Complete-HordeSuite -Success "every relay keeps the mailbox contract and shows what it claims, and the client survives one that lies"
