# DOES THE PHONE'S MAILBOX STAY SMALL HOWEVER MUCH A MACHINE SENDS, WITH THE PHONE STILL SHOWN THE TRUTH -
# AND IS A FULL MAILBOX SAID OUT LOUD?
#
# relays/Port.ps1, A SENDER TRIMS ITS OWN STREAM (2026-10-13). The phone's mailbox, <horde>/phone, is
# read by every trusted phone and acked by none, so it only ever grew: a whole decisions snapshot at
# every change of the list, an envelope for every batch of chat and progress. The hosted relay refuses
# every put into a mailbox that holds 2,000 envelopes, and a put that is refused reaches nobody. This
# suite holds the fix to what it promises, with the real channels, over a relay in memory that counts
# every request made of it (test/lib/CountingRelay.ps1) and over the disk relay (relays/local):
#   - MANY SNAPSHOTS, ONE HELD: after every snapshot the mailbox holds that snapshot's pages and no
#     older one, however many were sent, and the phone opens the newest whole one. THE CONTROL IS THE
#     OLD BEHAVIOUR: with the relay's trimming taken away the same sends grow the mailbox by one each,
#     and the run is told so (untrimmed); given back, the next snapshot empties what had piled up.
#   - IT COSTS NO REQUEST: a snapshot is its puts and nothing else, and an idle turn is one watch.
#   - A SNAPSHOT ONLY PARTLY PUT TRIMS NOTHING: while the relay has taken some of its pages and not the
#     last, the snapshot before is still whole in the mailbox and is what the phone opens; once the
#     last page is taken, the old one goes.
#   - A PHONE PAIRED LATER GETS THE STATE: its key changes the fingerprint, a snapshot sealed to it too
#     is sent, and it opens that - it never needed what was trimmed, which was never sealed to it.
#   - ONE MACHINE'S TRIM LEAVES ANOTHER'S MAIL: two machines of one horde put into the one mailbox, and
#     each trims only its own stream. (That a machine CANNOT name another's stream, and that a phone
#     cannot trim at all, is the hosted relay's to enforce, by who signed the request: the suite of
#     its accounts, in its own folder, holds it to that.)
#   - CHAT AND PROGRESS KEEP THEIR LAST SO-MANY: every put names the seq to keep from, the channel's
#     keepEnvelopes back from its own.
#   - A FULL MAILBOX (the relay's 507) is said in the run's log in capitals, once, and the warchief is
#     told ONCE, through the messenger port, in fixed words that hold nothing the relay said; a test's
#     home tells nobody; and a put taken again is said too.
#
# NO REAL MESSENGER IS EVER ASKED HERE, and no real session told: the channels load every messenger
# folder, and this suite removes every one of them before anything is sent, then registers a stand-in
# that keeps its posts in this process (the fixture of test/test-decisions-notify.ps1).
#
# EVERY HORDE HOME IS A FOLDER OF THE SUITE'S OWN under %TEMP% (CONTRIBUTING 9); the fleet is pinned to an
# empty one of the suite's own (test/lib/FleetPin.ps1); every key is made with the software provider and
# removed in the finally block. Off Windows there is no key store: the suite says so and exits 3.

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
. (Join-Path $root "test\lib\CountingRelay.ps1")
# NO REAL MESSENGER (the header): every one the channels loaded is taken out of this process's list.
$loadedMessengers = @(Get-HordeMessengerNames)
foreach ($n in $loadedMessengers) { [void]$script:HordeMessengers.Remove($n) }
Set-StrictMode -Version Latest
Write-Host ("  runtime: PowerShell " + $PSVersionTable.PSVersion + " (" + $PSVersionTable.PSEdition + ")") -ForegroundColor DarkGray

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$script:homes = New-Object System.Collections.ArrayList
$script:contexts = New-Object System.Collections.ArrayList
$realHome = $env:HORDE_HOME
$script:skipped = $false
$diskRoot = Join-Path $env:TEMP ("horde-relay-phone-mailbox-disk-" + [guid]::NewGuid().ToString("N"))

if ((Get-HordeRelayKeyStore).state -cne "known") {
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Exit-HordeTestEmptyFleet -Pin $fleetPin
    Complete-HordeSuite -Success "no key store here: no machine identity can be made, so nothing was run" -PassCode 3
}

function New-Id { return [guid]::NewGuid().ToString("N") }
function New-TestHome {
    $h = Join-Path $env:TEMP ("horde-relay-phone-mailbox-" + [guid]::NewGuid().ToString("N"))
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
function Add-TrustedPhone {
    # A new phone, paired with the machine of -HordeHome and confirmed, its identity key trusted.
    param([string]$HordeHome)
    $phone = New-HordeTestPhone
    [void](Add-HordeTestPhonePairing -HordeHome $HordeHome -Phone $phone)
    $v = New-HordeTestPhoneVouch -Phone $phone -Horde "work"
    $k = Add-HordeRelayPhoneKey -HordeHome $HordeHome -AgreePublic $phone.agreePublic -By $phone.keyId -AuthenticatorData $v.authenticatorData -ClientDataJson $v.clientDataJson -Signature $v.signature
    if ($k.state -cne "known") { throw ("no phone key: " + $k.reason) }
    return $phone
}
function New-World {
    # A machine of the horde "work" (home, identity), a phone whose key it trusts, a run context over
    # -Connection, and one open question.
    param($Connection)
    $h = New-TestHome
    $id = New-HordeRelayMachineIdentity -HordeHome $h -Provider "software"
    if ($id.state -cne "known") { throw ("no identity: " + $id.reason) }
    $phone = Add-TrustedPhone -HordeHome $h
    $made = New-HordeRelayRunContext -HordeHome $h -Connection $Connection
    if ($made.state -cne "known") { throw ("no context: " + $made.reason) }
    [void]$script:contexts.Add($made.value)
    $w = [pscustomobject]@{ home = $h; id = $id.value; phone = $phone; ctx = $made.value; store = (Join-Path $h "store\decisions"); conn = $Connection }
    $q = Invoke-HordeDecision -Operation "add" -Root $w.store -Request @{ id = (New-Id); actor = "warchief"; question = @{ title = "Should the closing sound play when the assistant closes?"; kind = "yes-no"; whatItIs = "The app has no closing sound today."; group = "voice"; askedBy = "orc-b" } }
    if ($q.state -cne "known" -or $q.value.outcome -cne "done") { throw "the question was not added" }
    return $w
}
function Add-Note {
    # One more record in the world's store: the warchief's words under question 1. Each is a change of
    # the list, so the next look sends a whole new snapshot.
    param($World, [string]$Text)
    $a = Invoke-HordeDecision -Operation "say" -Root $World.store -Request @{ id = (New-Id); actor = "warchief"; number = 1; speaker = "warchief"; route = "command"; text = $Text; asks = $false }
    if ($a.state -cne "known" -or $a.value.outcome -cne "done") { throw ("the note was not saved: " + $a.reason) }
}
function Send-Snapshot {
    # The decisions channel's own look, and nothing else of the turn: { lines; failed; text }.
    param($World)
    $env:HORDE_HOME = $World.home
    $t = Invoke-HordeDecisionsChannelSnapshotTick -Context $World.ctx
    return [pscustomobject]@{ lines = @($t.lines); failed = [bool]$t.failed; text = (@($t.lines) -join " | ") }
}
function Get-Held {
    # What the phone's mailbox holds now, as { seq; key; text }: from the counting relay's own memory, or
    # read off the disk relay - never a request the counting relay would log.
    param($World)
    if ($World.conn.relay.name -ceq "counting") { return @(Get-HordeCountingRelayHeld -Mailbox "work/phone") }
    return @((Receive-HordeRelayItems -Connection $World.conn -Mailbox "work/phone" -Since 0).value.items)
}
function Get-StreamSeqs {
    # The seqs, in their own stream, of the decisions envelopes of -World's machine that the mailbox
    # holds, in order: the first is the first page of the oldest snapshot still there.
    param($World)
    return @(Get-Held $World | ForEach-Object { $n = Read-HordeRelayStreamKey -Key $_.key; if ($null -ne $n -and $n.stream -ceq ($World.id.sign.keyId + "/decisions/")) { $n.seq } } | Sort-Object)
}
function Get-StreamCount {
    # How many of the held items are of -Machine's stream on -Channel.
    param($World, [string]$Machine, [string]$Channel)
    return @(Get-Held $World | Where-Object { $_.key.StartsWith($Machine + "/" + $Channel + "/") }).Count
}
function Read-NewestSnapshot {
    # What a phone shows: of the snapshot pages of -World's machine that -Phone can open in the mailbox,
    # the newest snapshot that is WHOLE (every page there), as relay/js/protocol.js's newestSnapshot
    # picks it. { seq; hash; pages; text } - text every page's questions as JSON. NONE IS AN ANSWER TOO,
    # pages 0 and nothing else: a check that reads it then fails as a check, and never vanishes on a $null.
    param($World, $Phone)
    $groups = @{}
    foreach ($it in @(Get-Held $World)) {
        $o = Open-HordeTestPhoneEnvelope -Phone $Phone -Text $it.text -MachineSignPublic $World.id.sign.public
        if (-not $o.ok -or $o.header.channel -cne "decisions" -or $o.header.kind -cne "snapshot") { continue }
        $hash = "$($o.body.snapshot)"
        if (-not $groups.ContainsKey($hash)) { $groups[$hash] = [pscustomobject]@{ hash = $hash; pages = [int]$o.body.pages; seq = [long]0; byPage = @{} } }
        $g = $groups[$hash]
        $g.byPage[[int]$o.body.page] = (ConvertTo-Json -InputObject $o.body.questions -Compress -Depth 20)
        if ([long]$o.header.seq -gt $g.seq) { $g.seq = [long]$o.header.seq }
    }
    $best = $null
    foreach ($g in @($groups.Values)) {
        if ($g.byPage.Count -ne $g.pages) { continue }
        if ($null -eq $best -or $g.seq -gt $best.seq) { $best = $g }
    }
    if ($null -eq $best) { return [pscustomobject]@{ seq = [long]-1; hash = ""; pages = 0; text = "" } }
    return [pscustomobject]@{ seq = $best.seq; hash = $best.hash; pages = $best.pages; text = (@($best.byPage.Keys | Sort-Object | ForEach-Object { $best.byPage[$_] }) -join "") }
}
function Get-Ops { param([switch]$Requests) return (@(Get-HordeCountingRelayLog -Requests:$Requests | ForEach-Object { $_.op }) -join ",") }

try {
    $canAdd = Invoke-HordeDecision -Operation "add" -Root (Join-Path (New-TestHome) "store\decisions") -Request @{ id = (New-Id); actor = "warchief"; question = @{ title = "Can this runtime add a question here?"; kind = "yes-no"; whatItIs = "A probe."; group = "probe"; askedBy = "suite" } }
    if ($canAdd.state -cne "known" -or $canAdd.value.outcome -cne "done") {
        Write-Host "  [SKIP] the decisions list cannot add a question under this runtime (issue #173): nothing here can be run, and the suite exits 3" -ForegroundColor Yellow
        $script:skipped = $true
    } else {
    $script:skipped = $false
    Check ($loadedMessengers.Count -ge 1 -and @(Get-HordeMessengerNames).Count -eq 0) ("CONTROL: the channels loaded messengers (" + ($loadedMessengers -join ", ") + "), and none is left in this process before anything is sent")
    Reset-HordeCountingRelay
    $connected = Connect-HordeRelay -Name "counting" -Options @{}
    Check ($connected.state -ceq "known" -and (Test-HordeRelaySenderTrim $connected.value)) "CONTROL: the counting relay is connected, and trims a sender's stream on a put"
    $conn = $connected.value

    Write-Host ""
    Write-Host "--- many snapshots, one held: the mailbox does not grow, and the phone opens the newest ---" -ForegroundColor Cyan
    $W = New-World -Connection $conn
    $first = Send-Snapshot $W
    Check (-not $first.failed -and $first.text.Contains("snapshot of 1 open question(s)") -and @(Get-Held $W).Count -eq 1) ("CONTROL: the first look sends one snapshot, of one page (" + $first.text + ")")
    $sends = 25
    $most = 0
    $costs = New-Object System.Collections.ArrayList
    foreach ($i in 1..$sends) {
        Add-Note $W ("note number " + $i)
        Clear-HordeCountingRelayLog
        $t = Send-Snapshot $W
        if ($t.failed) { throw ("snapshot " + $i + " was not sent: " + $t.text) }
        [void]$costs.Add((Get-Ops -Requests))
        $most = [Math]::Max($most, @(Get-Held $W).Count)
    }
    $held = @(Get-Held $W)
    Check ($most -eq 1 -and $held.Count -eq 1) ("after " + $sends + " more snapshots, each a whole new one, the mailbox holds ONE envelope - it never held more after a send (most " + $most + ", now " + $held.Count + ")")
    Check ($held[0].seq -eq ($sends + 1)) ("and the relay did take every one of them: the one held is its item " + $held[0].seq + " of " + ($sends + 1) + " put")
    $shown = Read-NewestSnapshot $W $W.phone
    Check ($shown.pages -gt 0 -and $shown.text.Contains("note number " + $sends) -and $shown.pages -eq 1) "the phone opens the newest whole snapshot, with the last note in it"
    Check (@($costs | Where-Object { $_ -cne "put" }).Count -eq 0) ("IT COSTS NO REQUEST: each of those snapshots was one put and nothing else - the trim rode on it (" + (@($costs | Sort-Object -Unique) -join " / ") + ")")
    Check ($W.ctx.untrimmed.Count -eq 0 -and $W.ctx.full.Count -eq 0) "and the run was told of nothing: the relay trimmed as asked, and refused nothing"

    Write-Host ""
    Write-Host "--- the control: how it was, and a relay that does not trim yet ---" -ForegroundColor Cyan
    Set-HordeCountingRelayTrim -On $false
    foreach ($i in 1..5) { Add-Note $W ("untrimmed note " + $i); $null = Send-Snapshot $W }
    Check (@(Get-Held $W).Count -eq 6) ("CONTROL: on a relay with no trimming the very same sends grow the mailbox by one each, as they always did (" + @(Get-Held $W).Count + " held)")
    Check ($W.ctx.untrimmed.ContainsKey("work/phone")) "and the run is told that the mailbox is not being trimmed"
    $ctlSaid = New-Object System.Collections.ArrayList
    $ctlWatching = New-HordeRelayRunWatching -Say { param($Line) [void]$ctlSaid.Add($Line) } -Sleep { param($Ms, $Why) } -StopPath (Join-Path $W.home "relayun.stop") -StartedMs 0 -CheckMs 1000 -HordeHome $W.home -Tell $true -FromLabel "SV"
    foreach ($look in 1..3) { Invoke-HordeRelayRunPutNotes -Context $W.ctx -Watching $ctlWatching }
    Check ($ctlSaid.Count -eq 1 -and $ctlSaid[0] -clike "NOT TRIMMED: *work/phone*deploy the relay*") ("the run says so in its log - NOT TRIMMED, and that the relay is to be deployed - once, however often it looks (" + ($ctlSaid -join " | ") + ")")
    Set-HordeCountingRelayTrim -On $true
    Set-HordeCountingRelayFaults -Faults @("no-trim")
    Add-Note $W "an older deployment"
    $null = Send-Snapshot $W
    Check (@(Get-Held $W).Count -eq 7 -and $W.ctx.untrimmed.ContainsKey("work/phone")) ("a relay that takes the put and says nothing of a trim - the hosted relay as deployed before this - is told of the same way (" + @(Get-Held $W).Count + " held)")
    Set-HordeCountingRelayFaults -Faults @()
    Add-Note $W "the relay trims now"
    $null = Send-Snapshot $W
    Check (@(Get-Held $W).Count -eq 1 -and -not $W.ctx.untrimmed.ContainsKey("work/phone")) ("and the first snapshot put once the relay does trim deletes everything that had piled up (" + @(Get-Held $W).Count + " held)")
    Check ((Read-NewestSnapshot $W $W.phone).text.Contains("the relay trims now")) "with the phone still shown the newest"
    foreach ($look in 1..2) { Invoke-HordeRelayRunPutNotes -Context $W.ctx -Watching $ctlWatching }
    Check ($ctlSaid.Count -eq 2 -and $ctlSaid[1] -ceq "the relay now trims work/phone as it is asked to") ("and the run says, once, that the relay now trims (" + ($ctlSaid -join " | ") + ")")

    Write-Host ""
    Write-Host "--- a snapshot only partly put trims nothing: the phone is never left with none ---" -ForegroundColor Cyan
    # Small pages, so a snapshot of a few questions is several: the relay holds 16,000 characters.
    Reset-HordeCountingRelay
    Set-HordeCountingRelayTextChars -Chars 16000
    $G = New-World -Connection $conn
    $long = ("the quiet option " * 250).Substring(0, 4000)
    foreach ($i in 1..4) { $null = Invoke-HordeDecision -Operation "add" -Root $G.store -Request @{ id = (New-Id); actor = "warchief"; question = @{ title = ("Long question number " + $i); kind = "yes-no"; whatItIs = $long; group = "voice"; askedBy = "orc-b" } } }
    $paged = Send-Snapshot $G
    $before = Read-NewestSnapshot $G $G.phone
    Check (-not $paged.failed -and $before.pages -gt 0 -and $before.pages -ge 2 -and @(Get-Held $G).Count -eq $before.pages) ("CONTROL: a snapshot of " + $before.pages + " pages is whole in the mailbox, and is all the mailbox holds (" + $paged.text + ")")
    Add-Note $G "the note of the snapshot that stalls"
    Set-HordeCountingRelayPutsLeft -Puts 1
    Clear-HordeCountingRelayLog
    $stalled = Send-Snapshot $G
    $mid = Read-NewestSnapshot $G $G.phone
    Check ($stalled.failed -and $stalled.text.Contains("not delivered yet") -and @($G.ctx.state["decisions"].pending).Count -eq ($before.pages - 1)) ("the relay took one page of the next snapshot and refused the rest (" + @($G.ctx.state["decisions"].pending).Count + " waiting)")
    Check (@(Get-Held $G).Count -eq ($before.pages + 1)) ("NOTHING WAS TRIMMED: the mailbox holds the whole snapshot before, and the one page of the new one (" + @(Get-Held $G).Count + " held)")
    Check ($mid.pages -gt 0 -and $mid.hash -ceq $before.hash -and -not $mid.text.Contains("the snapshot that stalls")) "and the phone still opens the snapshot before - whole - not a part of the new one"
    $again = Send-Snapshot $G
    Check ($again.failed -and @(Get-Held $G).Count -eq ($before.pages + 1) -and (Read-NewestSnapshot $G $G.phone).hash -ceq $before.hash) "a turn later, the relay still refusing: the same, and nothing trimmed"
    Set-HordeCountingRelayPutsLeft -Puts -1
    $done = Send-Snapshot $G
    $after = Read-NewestSnapshot $G $G.phone
    Check (-not $done.failed -and $after.pages -gt 0 -and $after.hash -cne $before.hash -and $after.text.Contains("the snapshot that stalls")) "once the relay takes the last page, the phone opens the new snapshot"
    Check (@(Get-Held $G).Count -eq $after.pages) ("and only then is the one before deleted: the mailbox holds the new one's " + $after.pages + " pages and nothing else (" + @(Get-Held $G).Count + " held)")
    Clear-HordeCountingRelayLog
    Add-Note $G "a snapshot of several pages"
    $multi = Send-Snapshot $G
    $pagesNow = (Read-NewestSnapshot $G $G.phone).pages
    Check (-not $multi.failed -and (Get-Ops -Requests) -ceq ((@(1..$pagesNow) | ForEach-Object { "put" }) -join ",")) ("a snapshot of " + $pagesNow + " pages costs " + $pagesNow + " puts and not one request more (" + (Get-Ops -Requests) + ")")

    Write-Host ""
    Write-Host "--- every other page keeps from the last snapshot the relay wholly took, and that is remembered across a restart ---" -ForegroundColor Cyan
    # channels/decisions, EVERY OTHER PAGE KEEPS FROM THE LAST SNAPSHOT THE RELAY WHOLLY TOOK.
    $statePath = Get-HordeDecisionsChannelStatePath -Context $G.ctx
    $remembered = Read-HordeDecisionsChannelWhole -Context $G.ctx
    Check ($remembered -gt 0 -and $remembered -eq (Get-StreamSeqs $G)[0] -and [System.IO.File]::ReadAllText($statePath) -ceq ('{"v":1,"machine":"' + $G.id.sign.keyId + '","whole":' + $remembered + '}')) ("the first seq of the snapshot the relay last wholly took is kept in the channel's own file: the key id and that number (" + $remembered + ")")
    Clear-HordeCountingRelayLog
    Add-Note $G "pages that say what to keep from"
    $told = Send-Snapshot $G
    $asked = @(Get-HordeCountingRelayLog -Requests | ForEach-Object { [long]$_.keepFrom })
    $nowFirst = (Get-StreamSeqs $G)[0]
    Check (-not $told.failed -and $asked.Count -ge 2 -and @($asked | Select-Object -First ($asked.Count - 1) | Where-Object { $_ -ne $remembered }).Count -eq 0 -and $asked[$asked.Count - 1] -eq $nowFirst -and $nowFirst -gt $remembered) ("every page but the last says to keep from the snapshot before (" + $remembered + "), and the last from this one's own first page (" + $nowFirst + "): " + ($asked -join ","))
    # A restart: a new context on the same home has no memory but the file.
    $restarted = New-HordeRelayRunContext -HordeHome $G.home -Connection $conn
    [void]$script:contexts.Add($restarted.value)
    $G.ctx = $restarted.value
    Clear-HordeCountingRelayLog
    Add-Note $G "after a restart"
    $told = Send-Snapshot $G
    $asked = @(Get-HordeCountingRelayLog -Requests | ForEach-Object { [long]$_.keepFrom })
    Check (-not $told.failed -and $asked.Count -ge 2 -and $asked[0] -eq $nowFirst) ("a new run reads it back: its first page says to keep from the snapshot the run before it landed (" + ($asked -join ",") + ")")
    foreach ($bad in @(
            @{ text = "{ not the state"; why = "a file that does not read" },
            @{ text = ('{"v":1,"machine":"' + ("f" * 32) + '","whole":5}'); why = "a memory written under another key (the identity was rotated)" },
            @{ text = ('{"v":1,"machine":"' + $G.id.sign.keyId + '","whole":900000}'); why = "a memory that names a seq past the page's own" })) {
        [System.IO.File]::WriteAllText($statePath, $bad.text)
        $again = New-HordeRelayRunContext -HordeHome $G.home -Connection $conn
        [void]$script:contexts.Add($again.value)
        $G.ctx = $again.value
        Clear-HordeCountingRelayLog
        Add-Note $G ("with " + $bad.why)
        $told = Send-Snapshot $G
        $asked = @(Get-HordeCountingRelayLog -Requests | ForEach-Object { [long]$_.keepFrom })
        Check (-not $told.failed -and $asked.Count -ge 2 -and @($asked | Select-Object -First ($asked.Count - 1) | Where-Object { $_ -ne 0 }).Count -eq 0 -and $asked[$asked.Count - 1] -eq (Get-StreamSeqs $G)[0]) ($bad.why + " is no memory: the pages before the last ask for nothing, the snapshot still lands, and its last page trims as ever (" + ($asked -join ",") + ")")
    }
    Check ((Read-HordeDecisionsChannelWhole -Context $G.ctx) -eq (Get-StreamSeqs $G)[0]) "and the snapshot that landed is remembered again, over whatever was in the file"

    Write-Host ""
    Write-Host "--- a mailbox at its cap, a snapshot of several pages, nothing remembered: one page first makes the room ---" -ForegroundColor Cyan
    # channels/decisions, A FULL MAILBOX IS EMPTIED BY ONE PAGE SENT FIRST (review of PR 232). The mailbox is
    # filled as it was before any of this: snapshot after snapshot with nothing trimmed. Then it is given
    # the hosted relay's own cap rule at exactly what it holds.
    Reset-HordeCountingRelay
    Set-HordeCountingRelayTextChars -Chars 16000
    $C = New-World -Connection $conn
    foreach ($i in 1..6) { $null = Invoke-HordeDecision -Operation "add" -Root $C.store -Request @{ id = (New-Id); actor = "warchief"; question = @{ title = ("Long question number " + $i); kind = "yes-no"; whatItIs = $long; group = "voice"; askedBy = "orc-b" } } }
    Set-HordeCountingRelayTrim -On $false
    foreach ($i in 1..3) { Add-Note $C ("piled up " + $i); $null = Send-Snapshot $C }
    Set-HordeCountingRelayTrim -On $true
    $piled = @(Get-Held $C).Count
    $pagesEach = (Read-NewestSnapshot $C $C.phone).pages
    [System.IO.File]::Delete((Get-HordeDecisionsChannelStatePath -Context $C.ctx))
    $fresh = New-HordeRelayRunContext -HordeHome $C.home -Connection $conn
    [void]$script:contexts.Add($fresh.value)
    $C.ctx = $fresh.value
    Set-HordeCountingRelayCap -Items $piled
    $oneMore = Send-HordeRelayItem -Connection $conn -Mailbox "work/phone" -Text "one more, with no trim"
    Check ($pagesEach -ge 3 -and $piled -eq (3 * $pagesEach) -and $oneMore.state -ceq "unknown" -and $null -ne $oneMore.PSObject.Properties["status"] -and $oneMore.status -eq 507 -and @(Get-Held $C).Count -eq $piled) ("CONTROL: the mailbox holds " + $piled + " envelopes - three snapshots of " + $pagesEach + " pages, none trimmed - and is at its cap: one more put, with no trim, is refused 507")
    # ONLY A REFUSAL AS FULL: a page refused for a rate (429) is put again as it is, and no page is sent first.
    Set-HordeCountingRelayCap -Items 0
    Set-HordeCountingRelayFaults -Faults @("busy")
    Add-Note $C "written while the relay was busy"
    $busyPages = Send-Snapshot $C
    Set-HordeCountingRelayFaults -Faults @()
    Check ($busyPages.failed -and -not $busyPages.text.Contains("one page") -and @($C.ctx.state["decisions"].pending).Count -eq $pagesEach) ("a page refused for another reason than a full mailbox is no cause for one page first: the pages wait, all " + $pagesEach + " of them")
    [System.IO.File]::Delete((Get-HordeDecisionsChannelStatePath -Context $C.ctx))
    $fresh = New-HordeRelayRunContext -HordeHome $C.home -Connection $conn
    [void]$script:contexts.Add($fresh.value)
    $C.ctx = $fresh.value
    Set-HordeCountingRelayCap -Items $piled
    Add-Note $C "written when the mailbox was at its cap"
    # Two puts are let through and no more: the page that is refused, and the one page sent first.
    Set-HordeCountingRelayPutsLeft -Puts 2
    Clear-HordeCountingRelayLog
    $firstLook = Send-Snapshot $C
    $between = Read-NewestSnapshot $C $C.phone
    $asked = @(Get-HordeCountingRelayLog -Requests | ForEach-Object { [long]$_.keepFrom })
    Check ($firstLook.text.Contains("would not take a page of it") -and $firstLook.text.Contains("one page is sent first to make room")) ("page 1 of the snapshot is refused as full, and the run says one page is sent first (" + $firstLook.text.Substring(0, [Math]::Min(300, $firstLook.text.Length)) + ")")
    Check ($asked.Count -ge 2 -and $asked[0] -eq 0 -and $asked[1] -gt 0 -and $asked[1] -eq (Get-StreamSeqs $C)[0]) ("that first page asked for no trim - nothing is remembered - and the one page says to keep from itself (" + ($asked -join ",") + ")")
    Check (@(Get-Held $C).Count -eq 1 -and $between.pages -eq 1 -and $between.text.Contains("Should the closing sound play") -and -not $between.text.Contains("Long question number 6")) ("THE PHONE IS NEVER WITHOUT A WHOLE SNAPSHOT: with only that one page taken, the mailbox holds it alone, in place of the " + $piled + ", and it is whole - one page of one, with the questions that fit (" + @(Get-Held $C).Count + " held)")
    $onePageBody = @(Get-Held $C | ForEach-Object { Open-HordeTestPhoneEnvelope -Phone $C.phone -Text $_.text -MachineSignPublic $C.id.sign.public } | Where-Object { $_.ok })
    Check ($onePageBody.Count -eq 1 -and @($onePageBody[0].body.withheld).Count -ge 1 -and @($onePageBody[0].body.withheld | Where-Object { "$($_.reason)" -cnotlike "it is in the snapshot that follows*" }).Count -eq 0 -and (@($onePageBody[0].body.questions).Count + @($onePageBody[0].body.withheld).Count) -eq 7) ("and it is true: every open question it does not show is withheld by number, saying it is in the snapshot that follows (" + @($onePageBody[0].body.questions).Count + " shown, " + @($onePageBody[0].body.withheld).Count + " withheld, of 7)")
    Set-HordeCountingRelayPutsLeft -Puts -1
    $secondLook = Send-Snapshot $C
    $landed = Read-NewestSnapshot $C $C.phone
    Check (-not $secondLook.failed -and $landed.pages -ge 3 -and $landed.text.Contains("written when the mailbox was at its cap") -and $landed.text.Contains("Long question number 6")) ("the whole snapshot then lands in the room that made: " + $landed.pages + " pages, with the note and every question")
    Check (@(Get-Held $C).Count -eq $landed.pages -and @(Get-Held $C).Count -lt $piled -and $C.ctx.full.Count -eq 0) ("and the mailbox, still under the same cap, holds that snapshot and nothing else: " + @(Get-Held $C).Count + " where it held " + $piled)
    # In one look, with nothing stopped half way: the same from a mailbox filled again.
    Set-HordeCountingRelayCap -Items 0
    Set-HordeCountingRelayTrim -On $false
    foreach ($i in 1..2) { Add-Note $C ("piled up again " + $i); $null = Send-Snapshot $C }
    Set-HordeCountingRelayTrim -On $true
    [System.IO.File]::Delete((Get-HordeDecisionsChannelStatePath -Context $C.ctx))
    $fresh = New-HordeRelayRunContext -HordeHome $C.home -Connection $conn
    [void]$script:contexts.Add($fresh.value)
    $C.ctx = $fresh.value
    $piledAgain = @(Get-Held $C).Count
    Set-HordeCountingRelayCap -Items $piledAgain
    Add-Note $C "in one look"
    Clear-HordeCountingRelayLog
    $oneLook = Send-Snapshot $C
    $landed = Read-NewestSnapshot $C $C.phone
    Check (-not $oneLook.failed -and $landed.text.Contains("in one look") -and @(Get-Held $C).Count -eq $landed.pages -and (Get-Ops -Requests) -ceq ((@(1..($landed.pages + 2)) | ForEach-Object { "put" }) -join ",")) ("left alone, one look does all of it - the refused page, the one page, the whole snapshot - for " + ($landed.pages + 2) + " puts and no other request (" + $piledAgain + " held before, " + @(Get-Held $C).Count + " after)")
    # ONCE A RUN: a mailbox that is still full after the one page is not sent one page again and again.
    Set-HordeCountingRelayCap -Items 2
    Add-Note $C "the mailbox is too small for it"
    $tooSmall = Send-Snapshot $C
    Check ($tooSmall.failed -and @([regex]::Matches($tooSmall.text, "one page is sent first")).Count -eq 1 -and (Read-NewestSnapshot $C $C.phone).pages -eq 1 -and $C.ctx.full.ContainsKey("work/phone")) ("a mailbox too small for the whole snapshot gets the one page, once; the whole one is then refused, the look fails, and the run is told the mailbox is full (" + @(Get-Held $C).Count + " held)")
    $putsBefore = @(Get-HordeCountingRelayLog -Requests).Count
    $headBefore = (Get-Held $C | ForEach-Object { $_.seq } | Measure-Object -Maximum).Maximum
    foreach ($i in 1..3) { $stillSmall = Send-Snapshot $C }
    Check ($stillSmall.failed -and -not $stillSmall.text.Contains("one page is sent first") -and (Get-Held $C | ForEach-Object { $_.seq } | Measure-Object -Maximum).Maximum -eq $headBefore -and (@(Get-HordeCountingRelayLog -Requests).Count - $putsBefore) -eq 3) "and on the turns after it the waiting page is tried again, once a turn, and NO further one page is sent: the phone keeps the whole one it has"
    Set-HordeCountingRelayCap -Items 0
    $roomAgain = Send-Snapshot $C
    Check (-not $roomAgain.failed -and (Read-NewestSnapshot $C $C.phone).text.Contains("the mailbox is too small for it") -and $C.ctx.full.Count -eq 0) "with room again, the very pages that were waiting land, and the mailbox is no longer full"
    Reset-HordeCountingRelay
    Set-HordeCountingRelayTextChars -Chars 16000
    foreach ($w in @($G)) { $again = New-HordeRelayRunContext -HordeHome $w.home -Connection $conn; [void]$script:contexts.Add($again.value); $w.ctx = $again.value; $null = Send-Snapshot $w }

    Write-Host ""
    Write-Host "--- a phone paired later gets the state; a machine's trim leaves another machine's mail ---" -ForegroundColor Cyan
    $late = Add-TrustedPhone -HordeHome $G.home
    Check ((Read-NewestSnapshot $G $late).pages -eq 0) "CONTROL: nothing in the mailbox was sealed to a phone that was not there yet"
    $forBoth = Send-Snapshot $G
    $lateSees = Read-NewestSnapshot $G $late
    $firstSees = Read-NewestSnapshot $G $G.phone
    Check (-not $forBoth.failed -and $forBoth.text.Contains("for 2 phone key(s)")) ("its key alone - no change of the list - sends a snapshot sealed to both (" + $forBoth.text + ")")
    Check ($lateSees.pages -gt 0 -and $lateSees.text.Contains("a snapshot of several pages") -and $lateSees.text.Contains("Long question number 4")) "the phone paired later opens the whole current state"
    Check ($firstSees.pages -gt 0 -and $firstSees.hash -ceq $lateSees.hash -and @(Get-Held $G).Count -eq $lateSees.pages) "the first phone opens the same snapshot, and it is all the mailbox holds"
    $B = New-World -Connection $conn
    $fromB = Send-Snapshot $B
    $heldOfA = Get-StreamCount $G $G.id.sign.keyId "decisions"
    Check (-not $fromB.failed -and (Get-StreamCount $B $B.id.sign.keyId "decisions") -eq 1 -and $heldOfA -eq $lateSees.pages) ("a second machine of the horde puts its own snapshot into the same mailbox, and its trim deletes nothing of the first machine's (" + $heldOfA + " of the first, 1 of the second)")
    foreach ($i in 1..3) { Add-Note $G ("the first machine again " + $i); $null = Send-Snapshot $G }
    Check ((Get-StreamCount $B $B.id.sign.keyId "decisions") -eq 1 -and (Read-NewestSnapshot $B $B.phone).pages -eq 1) "and three more snapshots of the first machine, each trimming its own stream, leave the second machine's snapshot where it is"
    Check ((Read-NewestSnapshot $G $G.phone).text.Contains("the first machine again 3") -and (Get-StreamCount $G $G.id.sign.keyId "decisions") -eq (Read-NewestSnapshot $G $G.phone).pages) "while the first machine's own stream is still exactly its newest snapshot"

    Write-Host ""
    Write-Host "--- chat and progress say, on every put, to keep their last so-many envelopes ---" -ForegroundColor Cyan
    $key = { param([long]$Seq) return ($W.id.sign.keyId + "/chat/" + $Seq + "/" + ("ab" * 12)) }
    Check ((Get-HordeRelayChannelKeepFrom -Key (& $key 500) -Keep 150) -eq 351) "an envelope with seq 500, keeping 150, says to keep from 351: itself and the 149 before it"
    Check ((Get-HordeRelayChannelKeepFrom -Key (& $key 150) -Keep 150) -eq 1 -and (Get-HordeRelayChannelKeepFrom -Key (& $key 149) -Keep 150) -eq 0) "while the stream is not yet longer than that, nothing is asked"
    Check ((Get-HordeRelayChannelKeepFrom -Key "sha256-0000" -Keep 150) -eq 0 -and (Get-HordeRelayChannelKeepFrom -Key (& $key 500) -Keep 0) -eq 0) "a key that names no stream, or a count under one, asks for nothing"
    $chatKeep = @((Get-HordeChatChannelSettingsDeclaration).settings | Where-Object { $_.name -ceq "keepEnvelopes" })[0]
    $progressKeep = @((Get-HordeProgressChannelSettingsDeclaration).settings | Where-Object { $_.name -ceq "keepEnvelopes" })[0]
    Check ($chatKeep.default -eq 150 -and $progressKeep.default -eq 100 -and $chatKeep.max -le 1000 -and $progressKeep.max -le 1000) "chat keeps 150 envelopes and progress 100 unless set otherwise, and neither can be set past half a mailbox"
    # Through the port's own put, with real envelopes of this machine on a channel of the suite's:
    # twelve puts keeping four leave the last four, and the phone's mail of other streams alone.
    Reset-HordeCountingRelay
    $other = Send-HordeRelayItem -Connection $conn -Mailbox "work/phone" -Text "another stream's item" -Key ($B.id.sign.keyId + "/chat/1/" + ("cd" * 12))
    foreach ($i in 1..12) {
        $k = & $key $i
        $put = Send-HordeRelayChannelSaved -Context $W.ctx -Saved ([pscustomobject]@{ key = $k; text = ("chat-" + $i) }) -Mailbox "work/phone" -KeepFrom (Get-HordeRelayChannelKeepFrom -Key $k -Keep 4)
        if ($put.state -cne "known") { throw ("put " + $i + " failed: " + $put.reason) }
    }
    $left = @(Get-Held $W | ForEach-Object { $_.text })
    Check (($left -join ",") -ceq "another stream's item,chat-9,chat-10,chat-11,chat-12") ("twelve puts of one stream, each keeping its last four, leave those four - and the other stream's item (" + ($left -join ",") + ")")
    Check ((Get-Ops -Requests) -ceq ((@(1..13) | ForEach-Object { "put" }) -join ",")) "for thirteen requests in all: the puts"

    Write-Host ""
    Write-Host "--- a full mailbox is said in capitals, and the warchief is told once ---" -ForegroundColor Cyan
    # A machine of its own for this, with a short list: every look reads the whole list.
    Reset-HordeCountingRelay
    $F = New-World -Connection $conn
    $null = Send-Snapshot $F
    $fx = Join-Path $here "fixtures\decisions-notify"
    $script:posts = New-Object System.Collections.ArrayList
    $stubPost = {
        param($Message)
        [void]$script:posts.Add($Message)
        return (New-HordeKnown -Value ([pscustomobject]@{ messageId = "$($Message.messageId)"; stage = "accepted"; at = [datetime]::UtcNow; reason = "" }) -ObservedAt ([datetime]::UtcNow))
    }
    $stubStatus = { param($MessageId) return (New-HordeAbsent -Note "the stand-in keeps no status") }
    $script:seatAsked = 0
    $seat = { $script:seatAsked++; return (New-HordeKnown -Value ([pscustomobject]@{ sessionId = "warchief-session-1"; pane = "3"; instance = "t1" })) }
    $noSeat = { return (New-HordeAbsent -Note "no live session's record names the role warchief") }
    # A folder that is not above this suite's homes, so they are not taken for a test's (the suite's own).
    $notTemp = Join-Path $env:TEMP ("horde-relay-phone-mailbox-elsewhere-" + (New-Id))
    $said = New-Object System.Collections.ArrayList
    $watching = New-HordeRelayRunWatching -Say { param($Line) [void]$said.Add($Line) } -Sleep { param($Ms, $Fhy) } -StopPath (Join-Path $F.home "relay\run.stop") -StartedMs 0 -CheckMs 1000 -HordeHome $F.home -Tell $true -FromLabel "SV"
    $now = [datetime]::new(2026, 10, 13, 12, 0, 0, [System.DateTimeKind]::Utc)
    Reset-HordeCountingRelay
    Set-HordeCountingRelayFaults -Faults @("busy")
    Add-Note $F "written while the relay is busy"
    $busy = Send-Snapshot $F
    Check ($busy.failed -and $F.ctx.full.Count -eq 0) ("CONTROL: a put refused for another reason (429, a rate) fails the Tick and is NOT a full mailbox (" + $busy.text + ")")
    Check ($F.ctx.refusedWith.ContainsKey(429) -and -not $F.ctx.refusedWith.ContainsKey(507)) ("and the run is told this turn's put was refused with 429, for its backoff (cli/RelayRun.ps1, BACKOFF) (" + (@($F.ctx.refusedWith.Keys) -join ",") + ")")
    Set-HordeCountingRelayFaults -Faults @("full")
    Add-Note $F "written while the mailbox is full"
    $refused = Send-Snapshot $F
    Check ($F.ctx.refusedWith.ContainsKey(507)) "and that its put was refused with 507"
    Check ($refused.failed -and -not $refused.text.Contains("one page") -and $F.ctx.full.ContainsKey("work/phone") -and $F.ctx.full["work/phone"].reason.Contains("507")) ("a put the relay refuses with 507 fails the Tick as before, and the run is told the mailbox is full (" + $refused.text + ")")
    Invoke-HordeRelayRunPutNotes -Context $F.ctx -Watching $watching -Seat $seat -TempRoot $notTemp -Now $now
    $loud = @($said | Where-Object { $_ -clike "MAILBOX FULL: *work/phone*NOTHING NEW REACHES THE FOUNDER'S PHONE*" })
    Check ($loud.Count -eq 1 -and $loud[0].Contains("507")) ("the run says it plainly, with what the relay answered (" + ($said -join " | ") + ")")
    Check ($script:posts.Count -eq 0 -and @($said | Where-Object { $_ -clike "the warchief was NOT told*no messenger*" }).Count -eq 1) "with no messenger loaded nobody is told, and the run says why"
    $bell = Register-HordeMessenger -Folder (Join-Path $fx "doorbell") -Post $stubPost -Status $stubStatus
    Check ((@(Get-HordeMessengerNames) -join ",") -ceq "doorbell") "CONTROL: the stand-in messenger is the only one loaded"
    Invoke-HordeRelayRunPutNotes -Context $F.ctx -Watching $watching -Seat $seat -TempRoot $notTemp -Now $now.AddSeconds(10)
    Check ($script:posts.Count -eq 0) "within a minute of a notice that could not be posted, it is not tried again"
    Invoke-HordeRelayRunPutNotes -Context $F.ctx -Watching $watching -Seat $noSeat -TempRoot $notTemp -Now $now.AddSeconds(70)
    Check ($script:posts.Count -eq 0 -and @($said | Where-Object { $_ -clike "the warchief was NOT told*no session holds the role of warchief*" }).Count -eq 1) "a minute later, with a messenger and no warchief's session: still nobody told, and the new reason said"
    Invoke-HordeRelayRunPutNotes -Context $F.ctx -Watching $watching -Seat $noSeat -TempRoot $notTemp -Now $now.AddSeconds(135)
    Check ($script:posts.Count -eq 0 -and @($said | Where-Object { $_ -clike "the warchief was NOT told*" }).Count -eq 2) ("another minute on, for the same reason: tried again, and that reason is not said a second time (" + @($said | Where-Object { $_ -clike "the warchief was NOT told*" }).Count + " lines in all)")
    Invoke-HordeRelayRunPutNotes -Context $F.ctx -Watching $watching -Seat $seat -TempRoot $notTemp -Now $now.AddSeconds(200)
    Check ($script:posts.Count -eq 1 -and @($said | Where-Object { $_ -ceq "the notice that work/phone is full was posted to the warchief's session; it is delivered only when that session takes it" }).Count -eq 1) ("once there is a session to tell, the notice is posted (T-0391 slice 5: delivered only on the session's own TAKEN, test-relay-run-tell-taken.ps1) (" + $script:posts.Count + " post)")
    $notice = $script:posts[0]
    Check ($notice.sessionId -ceq "warchief-session-1" -and $notice.from.label -ceq "SV" -and $notice.from.sessionId -ceq "horde-relay-run" -and $notice.messageId -ceq (Get-HordeRelayFullNoticeId -HordeHome $F.home -Mailbox "work/phone" -Day $now)) "the notice goes to the warchief's session, from the run, under an id made of the home, the mailbox and the day"
    Check ($notice.body.Contains("work/phone") -and $notice.body.Contains("nothing new reaches the founder's phone") -and -not $notice.body.Contains("507") -and -not $notice.body.Contains("counting relay")) ("its words are fixed: the mailbox's name, and nothing the relay said (" + ($notice.body -replace "`n", " / ") + ")")
    foreach ($i in 1..5) {
        $null = Send-Snapshot $F
        Invoke-HordeRelayRunPutNotes -Context $F.ctx -Watching $watching -Seat $seat -TempRoot $notTemp -Now $now.AddSeconds(300 + 100 * $i)
    }
    Check ($script:posts.Count -eq 1 -and @($said | Where-Object { $_ -clike "MAILBOX FULL: *" }).Count -eq 1) ("five more refused turns, minutes apart: TOLD ONCE, said once (" + $script:posts.Count + " post, " + @($said | Where-Object { $_ -clike "MAILBOX FULL: *" }).Count + " line)")
    Set-HordeCountingRelayFaults -Faults @()
    $taken = Send-Snapshot $F
    Invoke-HordeRelayRunPutNotes -Context $F.ctx -Watching $watching -Seat $seat -TempRoot $notTemp -Now $now.AddSeconds(900)
    Check (-not $taken.failed -and $F.ctx.full.Count -eq 0 -and @($said | Where-Object { $_ -ceq "the relay takes mail for work/phone again: it is no longer full" }).Count -eq 1) "when the relay takes a put again, the run says that the mailbox is no longer full"
    Check ((Read-NewestSnapshot $F $F.phone).text.Contains("written while the mailbox is full")) "and the snapshot recorded while it was full is the one the phone now opens: nothing was lost"
    Set-HordeCountingRelayFaults -Faults @("full")
    Add-Note $F "full a second time"
    $null = Send-Snapshot $F
    Invoke-HordeRelayRunPutNotes -Context $F.ctx -Watching $watching -Seat $seat -TempRoot $notTemp -Now $now.AddSeconds(1000)
    Check ($script:posts.Count -eq 2 -and $script:posts[1].messageId -ceq $script:posts[0].messageId -and @($said | Where-Object { $_ -clike "MAILBOX FULL: *" }).Count -eq 2) "a mailbox that fills again the same day is said again, and its notice is the SAME notice: an idempotent messenger keeps it as one"
    Check ((Get-HordeRelayFullNoticeId -HordeHome $F.home -Mailbox "work/phone" -Day $now.AddDays(1)) -cne $notice.messageId -and (Get-HordeRelayFullNoticeId -HordeHome $F.home -Mailbox "other/phone" -Day $now) -cne $notice.messageId) "another day, or another mailbox, is another notice"
    # Switched off, and a test's home.
    $quiet = New-Object System.Collections.ArrayList
    $off = New-HordeRelayRunWatching -Say { param($Line) [void]$quiet.Add($Line) } -Sleep { param($Ms, $Fhy) } -StopPath (Join-Path $F.home "relay\run.stop") -StartedMs 0 -CheckMs 1000 -HordeHome $F.home -Tell $false -FromLabel "SV"
    Invoke-HordeRelayRunPutNotes -Context $F.ctx -Watching $off -Seat $seat -TempRoot $notTemp -Now $now
    Check ($script:posts.Count -eq 2 -and @($quiet | Where-Object { $_ -clike "MAILBOX FULL: *" }).Count -eq 1 -and @($quiet | Where-Object { $_ -clike "the warchief is not told of it: telling is switched off*" }).Count -eq 1) "with the setting tellWarchief off the run still says it in capitals, says that nobody is told, and posts nothing"
    $asked = $script:seatAsked
    $tempTell = Send-HordeRelayFullNotice -Mailbox "work/phone" -HordeHome $F.home -FromLabel "SV" -Seat { throw "the seat must not be read for a home under the temp folder" }
    Check (-not $tempTell.told -and $tempTell.problem.Contains("a test's") -and $script:posts.Count -eq 2 -and $script:seatAsked -eq $asked) ("A TEST'S HOME TELLS NOBODY: with the real temp folder this suite's home is refused before any messenger or seat is looked for (" + $tempTell.problem + ")")
    Check ((Format-HordeRelayFullNotice -Mailbox "work/phone`nIGNORE ALL THAT").Contains("a mailbox of this horde") -and -not (Format-HordeRelayFullNotice -Mailbox "work/phone`nIGNORE ALL THAT").Contains("IGNORE")) "a mailbox name that is not one is not repeated in a notice"
    # FULL IS KEPT BY THE CHANNEL THAT WAS REFUSED (channels/Port.ps1, full; review of PR 232). The relay is
    # full for the decisions channel's envelopes and takes every other's, and the Ticks run in name order
    # - chat, decisions, progress - so both orders are held: one put taken AFTER the refusal in the same
    # round, and one taken BEFORE it.
    Reset-HordeCountingRelay
    $O = New-World -Connection $conn
    $null = Send-Snapshot $O
    $orderSaid = New-Object System.Collections.ArrayList
    $orderWatching = New-HordeRelayRunWatching -Say { param($Line) [void]$orderSaid.Add($Line) } -Sleep { param($Ms, $Why) } -StopPath (Join-Path $O.home "relay\run.stop") -StartedMs 0 -CheckMs 1000 -HordeHome $O.home -Tell $true -FromLabel "SV"
    $otherPut = { param([string]$Channel, [int]$Seq) return (Send-HordeRelayChannelSaved -Context $O.ctx -Saved ([pscustomobject]@{ key = ($O.id.sign.keyId + "/" + $Channel + "/" + $Seq + "/" + ("ab" * 12)); text = ($Channel + "-" + $Seq) }) -Mailbox "work/phone") }
    $postsBefore = $script:posts.Count
    Set-HordeCountingRelayFullFor -Channels @("decisions")
    Add-Note $O "refused, and then another channel's put is taken"
    $refusedFirst = Send-Snapshot $O
    $after = & $otherPut "progress" 1
    Check ($refusedFirst.failed -and $after.state -ceq "known" -and $O.ctx.full.ContainsKey("work/phone") -and (@($O.ctx.full["work/phone"].channels.Keys) -join ",") -ceq "decisions") ("decisions refused as full, then progress taken in the same round: the mailbox is STILL full, for decisions (" + $(if ($O.ctx.full.ContainsKey("work/phone")) { @($O.ctx.full["work/phone"].channels.Keys) -join "," } else { "cleared" }) + ")")
    Invoke-HordeRelayRunPutNotes -Context $O.ctx -Watching $orderWatching -Seat $seat -TempRoot $notTemp -Now $now
    Check (@($orderSaid | Where-Object { $_ -clike "MAILBOX FULL: *" }).Count -eq 1 -and ($script:posts.Count - $postsBefore) -eq 1) ("so the run says it and the warchief is told (" + ($script:posts.Count - $postsBefore) + " post)")
    foreach ($round in 1..3) {
        $before = & $otherPut "chat" $round
        $refusedAfter = Send-Snapshot $O
        Invoke-HordeRelayRunPutNotes -Context $O.ctx -Watching $orderWatching -Seat $seat -TempRoot $notTemp -Now $now.AddSeconds(100 * $round)
    }
    Check ($before.state -ceq "known" -and $refusedAfter.failed -and $O.ctx.full.ContainsKey("work/phone") -and @($orderSaid | Where-Object { $_ -clike "MAILBOX FULL: *" }).Count -eq 1 -and @($orderSaid | Where-Object { $_ -clike "the relay takes mail for*" }).Count -eq 0 -and ($script:posts.Count - $postsBefore) -eq 1) ("three rounds of chat taken and THEN decisions refused: it does not flap - still one line, never 'takes mail again', still one post (" + ($orderSaid -join " | ").Length + " characters said)")
    Set-HordeCountingRelayFullFor -Channels @("decisions", "chat")
    $chatRefused = & $otherPut "chat" 9
    Set-HordeCountingRelayFullFor -Channels @("decisions")
    $chatTaken = & $otherPut "chat" 9
    Check ($chatRefused.state -ceq "unknown" -and $chatTaken.state -ceq "known" -and (@($O.ctx.full["work/phone"].channels.Keys) -join ",") -ceq "decisions") "a second channel refused there and then taken takes only its own name off: the mailbox is full while any channel is refused"
    Set-HordeCountingRelayFullFor -Channels @()
    $landedAtLast = Send-Snapshot $O
    Invoke-HordeRelayRunPutNotes -Context $O.ctx -Watching $orderWatching -Seat $seat -TempRoot $notTemp -Now $now.AddSeconds(900)
    Check (-not $landedAtLast.failed -and $O.ctx.full.Count -eq 0 -and @($orderSaid | Where-Object { $_ -clike "the relay takes mail for work/phone again*" }).Count -eq 1) "and when decisions' own put is taken, the mailbox is no longer full, and the run says so once"
    [void]$script:HordeMessengers.Remove("doorbell")

    Write-Host ""
    Write-Host "--- through the run itself: an idle turn costs what it did; a full mailbox is loud and still backs off ---" -ForegroundColor Cyan
    Reset-HordeCountingRelay
    $R = New-World -Connection $conn
    [System.IO.File]::WriteAllText((Join-Path $R.home "settings\relay-run.json"), '{"schemaVersion": 1, "settings": {"watchMs": 300, "sendCheckMs": 200, "minTurnMs": 50, "backoffMinMs": 50, "backoffMaxMs": 100}}', $utf8)
    $env:HORDE_HOME = $R.home
    $runSaid = New-Object System.Collections.ArrayList
    $run = Invoke-HordeRelayRun -HordeHome $R.home -Connection $conn -MaxTurns 1 -Say { param($Line) [void]$runSaid.Add($Line) }
    $firstTurn = Get-Ops -Requests
    Clear-HordeCountingRelayLog
    $idle = Invoke-HordeRelayRun -HordeHome $R.home -Connection $conn -MaxTurns 3 -Say { param($Line) [void]$runSaid.Add($Line) }
    Check ($run.turns -eq 1 -and $idle.turns -eq 3 -and (Get-Ops -Requests) -ceq "put,watch-open,watch-open,watch-open") ("three turns with nothing new are three watches - and the one snapshot a new run always sends: an idle turn costs the relay what it did (" + (Get-Ops -Requests) + "; the first turn: " + $firstTurn + ")")
    Check (@(Get-Held $R).Count -eq 1) ("and that repeat of the snapshot trimmed the one before it: the mailbox holds one (" + @(Get-Held $R).Count + ")")
    Set-HordeCountingRelayFaults -Faults @("full")
    Add-Note $R "the run meets a full mailbox"
    $runSaid.Clear()
    $fullRun = Invoke-HordeRelayRun -HordeHome $R.home -Connection $conn -MaxTurns 3 -Say { param($Line) [void]$runSaid.Add($Line) }
    $fullText = ($runSaid -join " | ")
    Check (@($runSaid | Where-Object { $_ -clike "MAILBOX FULL: *work/phone*" }).Count -eq 1) ("the run itself says MAILBOX FULL, once in three failing turns (" + $fullText + ")")
    Check (@($runSaid | Where-Object { $_ -clike "the warchief was NOT told that work/phone is full: this Horde home is under the temp folder*" }).Count -eq 1) "and that nobody was told, because this home is a test's - once"
    Check ($fullRun.failures -eq 3 -and @($runSaid | Where-Object { $_ -clike "a channel could not send*failure * in a row*" }).Count -eq 3) ("each of those turns still counts as failed and backs off, as before (" + $fullRun.failures + " failures)")
    Set-HordeCountingRelayFaults -Faults @()

    Write-Host ""
    Write-Host "--- the disk relay does the same, and never reuses a number ---" -ForegroundColor Cyan
    $disk = Connect-HordeRelay -Name "local" -Options @{ root = $diskRoot }
    Check ($disk.state -ceq "known" -and (Test-HordeRelaySenderTrim $disk.value)) "CONTROL: the disk relay is connected, and trims a sender's stream on a put"
    $D = New-World -Connection $disk.value
    $null = Send-Snapshot $D
    foreach ($i in 1..8) { Add-Note $D ("disk note " + $i); $t = Send-Snapshot $D; if ($t.failed) { throw ("disk snapshot " + $i + ": " + $t.text) } }
    $onDisk = @(Get-Held $D)
    Check ($onDisk.Count -eq 1 -and $onDisk[0].seq -eq 9 -and (Read-NewestSnapshot $D $D.phone).text.Contains("disk note 8")) ("nine snapshots on disk leave one item, the ninth, and the phone opens it (" + $onDisk.Count + " held, seq " + $(if ($onDisk.Count) { $onDisk[0].seq } else { 0 }) + ")")
    $files = @(Get-ChildItem -LiteralPath (Join-Path $diskRoot "work\phone") -Filter "*.item")
    Check ($files.Count -eq 1) ("and one item file is all that is left in the mailbox's folder (" + $files.Count + ")")
    } # the runtime can add a question
} finally {
    foreach ($c in @($script:contexts)) { Close-HordeRelayRunContext -Context $c }
    Reset-HordeCountingRelay
    if ($script:HordeMessengers.ContainsKey("doorbell")) { [void]$script:HordeMessengers.Remove("doorbell") }
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
    Check ($script:skipped -or ($made.Count -ge 4 -and $left.Count -eq 0)) ("every key the suite's homes name is gone (" + $made.Count + " names, " + $left.Count + " left)")
    foreach ($h in @($script:homes)) {
        if ((Split-Path -Leaf $h) -match '^horde-relay-phone-mailbox-[0-9a-f]{32}$') { Remove-Item -LiteralPath $h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    if ((Split-Path -Leaf $diskRoot) -match '^horde-relay-phone-mailbox-disk-[0-9a-f]{32}$' -and (Test-Path -LiteralPath $diskRoot)) { Remove-Item -LiteralPath $diskRoot -Recurse -Force -ErrorAction SilentlyContinue }
    Check (@($script:homes | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 0 -and -not (Test-Path -LiteralPath $diskRoot)) "every temporary home, and the disk relay's folder, is gone"
}
Check ($env:HORDE_HOME -ceq $realHome) "HORDE_HOME is what it was"

if ($script:skipped) { Complete-HordeSuite -Success "the decisions list cannot add a question under this runtime (issue #173): nothing was run" -PassCode 3 }
Complete-HordeSuite -Success "the phone's mailbox holds what a phone is shown and no more, however much is sent, for no request more than the puts; a snapshot partly put trims nothing; a phone paired later and a second machine lose nothing; and a full mailbox is said out loud and told once"
