# DOES THE FOUNDER'S PHONE GET ONE CARD PER LANE AND ONE FOR THE THRALL - MADE ON THE MACHINE FROM WHAT EACH
# LANE SAYS NOW, SENT WHOLE, ONLY THE LATEST KEPT - WITH NO SECRET IN IT AND NO LANE MISSING?
#
# The cards channel (channels/cards; the founder asked for the Progress tab as cards, 2026-10-13), over
# relays/local in this process, with a phone held in memory (test/lib/RelayPhone.ps1) and a fleet of the
# suite's own: made-up lane folders, a made-up task ledger, a made-up area-to-lane map and made-up runs,
# all under a home of its own. It attacks:
#   - no lanes folder is "nothing yet": nothing sent, said once; every source is under Horde's own home;
#   - a card per lane in the standard form, with the ledger's counts (handed moves a task; done this week
#     counts only the last 7 days) and the Thrall card's fleet and census;
#   - a lane file in another form, a missing one and an unreadable one each still get a card that says so;
#   - a secret in a status line is refused: the card goes, with a notice in its place, never the text;
#   - the snapshot is replaced whole, only the latest kept in the mailbox; the same snapshot is not sent
#     again; the area-to-lane map rides in it;
#   - nothing comes in on the channel; refused settings stop it in words.
# The phone's side - two machines merged by name, the lane filters - is surfaces/pwa/test/units.mjs.
#
# NO REAL FLEET IS TOUCHED. The fleet root is pointed at an empty folder of the suite's own before any
# channel loads (test/lib/FleetPin.ps1); every home and every source is the suite's own under %TEMP%.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\FleetPin.ps1")
$fleetPin = Enter-HordeTestEmptyFleet
. (Join-Path $root "core\ModuleSettings.ps1")
. (Join-Path $root "channels\Port.ps1")
foreach ($f in @(Get-HordeRelayFiles)) { . $f }
foreach ($f in @(Get-HordeRelayChannelFiles)) { . $f }
. (Join-Path $root "test\lib\RelayPhone.ps1")
Set-StrictMode -Version Latest
Write-Host ("  runtime: PowerShell " + $PSVersionTable.PSVersion + " (" + $PSVersionTable.PSEdition + ")") -ForegroundColor DarkGray

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$script:homes = New-Object System.Collections.ArrayList
$script:worlds = New-Object System.Collections.ArrayList
$realHome = $env:HORDE_HOME

if ((Get-HordeRelayKeyStore).state -cne "known") {
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Complete-HordeSuite -Success "no key store here: no machine identity can be made, so nothing was run" -PassCode 3
}

function New-World {
    # A machine with its identity, a phone paired and its key trusted, a local relay and a run context.
    param([string]$Settings = '{"sendIntervalMs": 0, "machineName": "office-pc"}')
    $h = Join-Path $env:TEMP ("horde-relay-cards-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path (Join-Path $h "settings") -Force | Out-Null
    [void]$script:homes.Add($h)
    [System.IO.File]::WriteAllText((Join-Path $h "settings\relay.json"), '{"schemaVersion": 1, "settings": {"horde": "work"}}', $utf8)
    [System.IO.File]::WriteAllText((Join-Path $h "settings\relay-cards.json"), ('{"schemaVersion": 1, "settings": ' + $Settings + '}'), $utf8)
    $env:HORDE_HOME = $h
    $id = New-HordeRelayMachineIdentity -HordeHome $h -Provider "software"
    if ($id.state -cne "known") { throw ("no identity: " + $id.reason) }
    $phone = New-HordeTestPhone
    [void](Add-HordeTestPhonePairing -HordeHome $h -Phone $phone)
    $v = New-HordeTestPhoneVouch -Phone $phone -Horde "work"
    $k = Add-HordeRelayPhoneKey -HordeHome $h -AgreePublic $phone.agreePublic -By $phone.keyId -AuthenticatorData $v.authenticatorData -ClientDataJson $v.clientDataJson -Signature $v.signature
    if ($k.state -cne "known") { throw ("no phone key: " + $k.reason) }
    $c = Connect-HordeRelay -Name "local" -Options @{ root = (Join-Path $h "relay-mailboxes") }
    if ($c.state -cne "known") { throw ("no relay: " + $c.reason) }
    $ctx = New-HordeRelayRunContext -HordeHome $h -Connection $c.value
    if ($ctx.state -cne "known") { throw ("no context: " + $ctx.reason) }
    $w = [pscustomobject]@{ home = $h; id = $id.value; phone = $phone; conn = $c.value; ctx = $ctx.value; lanes = (Join-Path $h "progress\lanes"); progress = (Join-Path $h "progress") }
    [void]$script:worlds.Add($w)
    return $w
}
function Set-Lane {
    # A lane folder with its status.txt (-Text, LF ends), or none when -Text is $null.
    param($World, [string]$Folder, $Text)
    $dir = Join-Path $World.lanes $Folder
    [void][System.IO.Directory]::CreateDirectory($dir)
    if ($null -ne $Text) { [System.IO.File]::WriteAllText((Join-Path $dir "status.txt"), $Text, $utf8) }
}
function New-Status {
    param([string]$Orc, [string]$Lane, [string]$Doing = "building a thing", [string]$Finished = "merged a thing", [string]$Blocked = "no", [string]$Waiting = "nothing, since 2026-10-13")
    return ("horde-orc-status 1`norc: " + $Orc + "`nlane: " + $Lane + "`ndoing: " + $Doing + "`nfinished: " + $Finished + "`nblocked: " + $Blocked + "`nwaiting on: " + $Waiting + "`n")
}
function Invoke-Tick { param($World) $env:HORDE_HOME = $World.home; return (Invoke-HordeCardsChannelTick -Context $World.ctx) }
function Get-CardsMail {
    # What the phone opens of the cards items now in the mailbox, as { seq; body; raw }.
    param($World)
    $r = Receive-HordeRelayItems -Connection $World.conn -Mailbox "work/phone" -Since 0
    $out = New-Object System.Collections.ArrayList
    if ($r.state -cne "known") { return @() }
    foreach ($it in @($r.value.items)) {
        $env1 = Read-HordeRelayEnvelope -Text $it.text
        $hdr = $env1.value.header
        if ($hdr.channel -cne "cards") { continue }
        $machine = New-HordeRelaySender -Public $World.id.sign.public -Proof "es256"
        $verdict = New-HordeKnown -Value ([pscustomobject]@{ key = (Get-HordeRelayReplayKey -Header $hdr); fresh = $true })
        $o = Unprotect-HordeRelayEnvelope -Envelope $env1.value -Senders @{ ($machine.keyId) = $machine } -RecipientKeys @{ (Get-HordeRelayKeyId -Public $World.phone.agreePublic) = $World.phone.agree } -Replay $verdict -Channel $hdr.channel -Kind $hdr.kind
        if ($o.ok) { $raw = [System.Text.Encoding]::ASCII.GetString($o.value); [void]$out.Add([pscustomobject]@{ seq = [long]$hdr.seq; kind = $hdr.kind; body = ($raw | ConvertFrom-Json); raw = $raw }) }
    }
    return @($out.ToArray())
}
function Get-Card { param($Body, [string]$Lane) return @($Body.cards | Where-Object { $_.lane -ceq $Lane })[0] }
function Said { param($Tick) return (@($Tick.lines) -join " | ") }
function Iso { param([datetime]$At) return $At.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture) }

try {
    Write-Host ""
    Write-Host "--- 1. no lanes folder is nothing yet; every source is under Horde's own home ---" -ForegroundColor Cyan
    $A = New-World
    $t = Invoke-Tick $A
    $t2 = Invoke-Tick $A
    Check (@(Get-CardsMail $A).Count -eq 0 -and -not $t.failed -and (Said $t) -like "*no cards yet*" -and (Said $t).Contains($A.lanes) -and @($t2.lines).Count -eq 0) ("with no lanes folder nothing is sent, said once, not a failure, and the folder looked for is progress\lanes under the home (" + (Said $t) + ")")
    $defaults = Get-HordeModuleSettings -Declaration (Get-HordeCardsChannelSettingsDeclaration) -HordeHome (Join-Path $env:TEMP ("horde-relay-cards-none-" + [guid]::NewGuid().ToString("N")))
    $p = Get-HordeCardsChannelPaths -HordeHome "X:\home" -Settings $defaults.values
    Check ($defaults.state -ceq "defaults" -and $defaults.values.lanesFolder -ceq "" -and $defaults.values.ledgerFile -ceq "" -and $defaults.values.areaLanesFile -ceq "" -and $defaults.values.runsFolder -ceq "" -and $defaults.values.thrallStatusFile -ceq "" -and
        $p.lanes -ceq "X:\home\progress\lanes" -and $p.ledger -ceq "X:\home\progress\tasks.jsonl" -and $p.areas -ceq "X:\home\progress\area-lanes.json" -and $p.runs -ceq "X:\home\progress\runs" -and $p.thrall -ceq "X:\home\progress\thrall-status.txt") "by default every source is a place under Horde's own home, and no folder of anyone's machine is named"

    Write-Host ""
    Write-Host "--- 2. a card per lane in the standard form, the ledger's counts, the Thrall's card ---" -ForegroundColor Cyan
    $now = [datetime]::UtcNow
    Set-Lane $A "research" (New-Status -Orc "E" -Lane "research; now the phone" -Doing "two builders running" -Finished "the FILES tab refuses secret files")
    Set-Lane $A "voice-audio" (New-Status -Orc "B" -Lane "voice and audio" -Blocked "yes - the account hit its weekly usage limit" -Waiting "the founder, since 2026-10-13, for two questions")
    Set-Lane $A "decisions-page" (New-Status -Orc "F" -Lane "decisions page" -Waiting "the founder, since 2026-10-07")
    $ledger = @(
        ('{"ts": "' + (Iso $now.AddDays(-20)) + '", "task": "T-1", "event": "opened", "title": "a", "lane": "E"}'),
        ('{"ts": "' + (Iso $now.AddDays(-20)) + '", "task": "T-2", "event": "opened", "title": "b", "lane": "E"}'),
        ('{"ts": "' + (Iso $now.AddDays(-20)) + '", "task": "T-3", "event": "opened", "title": "c", "lane": "E"}'),
        ('{"ts": "' + (Iso $now.AddDays(-20)) + '", "task": "T-4", "event": "opened", "title": "d", "lane": "C"}'),
        ('{"ts": "' + (Iso $now.AddDays(-20)) + '", "task": "T-5", "event": "opened", "title": "e", "lane": "E"}'),
        ('{"ts": "' + (Iso $now.AddDays(-2)) + '", "task": "T-1", "event": "done", "by": "E"}'),
        ('{"ts": "' + (Iso $now.AddDays(-1)) + '", "task": "T-1", "event": "verified", "by": "M"}'),
        ('{"ts": "' + (Iso $now.AddDays(-10)) + '", "task": "T-2", "event": "done", "by": "E"}'),
        # Written later in the file and earlier in time: the time order decides, as the ledger's own tool reads it.
        ('{"ts": "' + (Iso $now.AddDays(-3)) + '", "task": "T-3", "event": "started", "by": "E"}'),
        ('{"ts": "' + (Iso $now.AddDays(-15)) + '", "task": "T-3", "event": "progress", "by": "E"}'),
        ('{"ts": "' + (Iso $now.AddDays(-4)) + '", "task": "T-4", "event": "handed", "to": "E"}'),
        ('{"ts": "' + (Iso $now.AddDays(-4)) + '", "task": "T-5", "event": "dropped", "reason": "not needed"}'),
        'not json at all'
    )
    [System.IO.File]::WriteAllText((Join-Path $A.progress "tasks.jsonl"), (($ledger -join "`n") + "`n"), $utf8)
    [System.IO.File]::WriteAllText((Join-Path $A.progress "area-lanes.json"), '{"v":1,"areas":{"Form fill":"C","Horde":"C,E,F","Ask voice":"B"}}', $utf8)
    # Runs: one open with a session working, one waiting on a person, one long quiet; one closed run.
    $runs = Join-Path $A.progress "runs"
    $mkRun = { param([string]$Name, [string]$Closed, [object[]]$Sessions)
        $d = Join-Path $runs $Name; [void][System.IO.Directory]::CreateDirectory((Join-Path $d "sessions"))
        [System.IO.File]::WriteAllText((Join-Path $d "run.json"), ('{"runId":"' + $Name + '","closedAt":' + $Closed + '}'), $utf8)
        foreach ($s in $Sessions) { $sd = Join-Path $d ("sessions\" + $s.id); [void][System.IO.Directory]::CreateDirectory($sd); $f = Join-Path $sd "events.jsonl"; [System.IO.File]::WriteAllText($f, ('{"event":"started"}' + "`n" + '{"event":"' + $s.event + '"}' + "`n"), $utf8); if ($s.ContainsKey("old")) { [System.IO.File]::SetLastWriteTimeUtc($f, $now.AddDays(-3)) } } }
    & $mkRun "run-1" "null" @(@{ id = "a"; event = "progress" }, @{ id = "b"; event = "blocked" }, @{ id = "c"; event = "done" }, @{ id = "d"; event = "progress"; old = $true })
    & $mkRun "run-2" '"2026-10-13T00:00:00Z"' @(@{ id = "e"; event = "progress" })
    $t = Invoke-Tick $A
    $mail = @(Get-CardsMail $A)
    Check (-not $t.failed -and $mail.Count -eq 1 -and $mail[0].body.kind -ceq "cards-snapshot" -and $mail[0].body.name -ceq "office-pc" -and $mail[0].body.machine -ceq $A.ctx.signKeyId) ("one snapshot is sent, sealed to the trusted phone key, naming its machine (" + (Said $t) + ")")
    $b = $mail[0].body
    $e = Get-Card $b "E"
    Check (@($b.cards).Count -eq 3 -and (@($b.cards | ForEach-Object { $_.lane }) -join ",") -ceq "F,E,B" -and $e.name -ceq "research; now the phone" -and $e.form -ceq "standard" -and $e.now -ceq "two builders running" -and $e.lastDone -ceq "the FILES tab refuses secret files" -and $e.waitingOn -ceq "nothing, since 2026-10-13" -and $e.blocked -ceq "no") ("a card per lane in the standard form, by its orc letter, with what it is doing, finished and waits on (" + (@($b.cards | ForEach-Object { $_.lane }) -join ",") + ")")
    Check ($e.asOf -cmatch '\A20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z\z') ("each card carries when its status file was last written, for the phone to say its age (" + $e.asOf + ")")
    Check ($e.tasksOpen -eq 2 -and $e.doneWeek -eq 1) ("from the ledger: E has T-3 and the task handed to it open, T-1 done (verified) this week, T-2 done too long ago, T-5 dropped; an unreadable line is passed over (open " + $e.tasksOpen + ", done " + $e.doneWeek + ")")
    Check ((Said $t) -like "*1 line(s) of the task ledger could not be read*") "and the passed-over ledger line is said at the machine"
    $bc = Get-Card $b "B"
    Check ($bc.blocked -ceq "yes" -and $bc.blockedText -ceq "the account hit its weekly usage limit" -and $bc.tasksOpen -eq 0) "a lane that says it is blocked is blocked, with its words and not its own yes again; a lane the ledger has no task of has none open"
    $th = $b.thrall
    Check ($th.orcs -eq 3 -and $th.working -eq 1 -and $th.waitingFounder -eq 1 -and $th.blocked -eq 1 -and (@($th.waitingFounderLanes) -join ",") -ceq "F" -and $th.census.running -eq 1 -and $th.census.waiting -eq 1 -and -not $th.hasStatus -and $th.now -ceq "") ("the Thrall's card: 3 Orcs - 1 working, 1 waiting on the founder (F), 1 blocked; sessions: of the open run, 1 working and 1 waiting on a person - a closed run and a session quiet for days are neither; no Thrall status file, no now (" + ($th | ConvertTo-Json -Compress) + ")")
    Check ((@($b.areas | ForEach-Object { $_.area + "=" + (@($_.lanes) -join "+") }) -join ";") -ceq "Form fill=C;Horde=C+E+F;Ask voice=B") "the area-to-lane map rides in the snapshot, in the file's order"

    Write-Host ""
    Write-Host "--- 3. a lane file in another form, a missing one, an unreadable one: each still a card ---" -ForegroundColor Cyan
    Set-Lane $A "stt-cpu-bench" ("LANE: stt-cpu-bench (Orc I)`nDOING: measuring more models one at a time`nWAITING ON: nothing`nUPDATED: 2026-10-13 21:00 UTC`n")
    Set-Lane $A "empty-lane" $null
    Set-Lane $A "huge-lane" ("horde-orc-status 1`n" + ("x" * 20000))
    $t = Invoke-Tick $A
    $mail = @(Get-CardsMail $A)
    $b = $mail[$mail.Count - 1].body
    $i = Get-Card $b "I"
    Check ($null -ne $i -and $i.form -ceq "other" -and $i.name -ceq "stt-cpu-bench (Orc I)" -and $i.now -ceq "measuring more models one at a time" -and $i.waitingOn -ceq "nothing" -and $i.note -like "*not in the standard form*") ("a status file in another form gets a card by the orc it names, from its lines, saying it is not in the standard form (" + ($i | ConvertTo-Json -Compress) + ")")
    $m = Get-Card $b "empty-lane"
    $u = Get-Card $b "huge-lane"
    Check ($null -ne $m -and $m.form -ceq "missing" -and $m.note -like "*no status file*" -and $null -ne $u -and $u.form -ceq "unreadable" -and $u.note -like "*could not be read*" -and $u.now -ceq "") "a lane with no status file and one whose file cannot be read each get a card that says so - never a missing card"
    Check ($b.thrall.orcs -eq 6 -and $b.thrall.unknown -eq 2) "and the Thrall's count says two lanes are not known"

    Write-Host ""
    Write-Host "--- 4. a secret in a status line: refused, a notice in its place, never the text ---" -ForegroundColor Cyan
    $token = "ghp_" + ("A1b2C3d4" * 5)
    Set-Lane $A "research" (New-Status -Orc "E" -Lane "research" -Doing ("pushing with " + $token) -Finished "fine words")
    $t = Invoke-Tick $A
    $mail = @(Get-CardsMail $A)
    $last = $mail[$mail.Count - 1]
    $e = Get-Card $last.body "E"
    Check ($null -ne $e -and $e.now -like "Not shown: this line looks like it holds a secret*" -and (@($e.refused) -join ",") -ceq "now" -and $e.lastDone -ceq "fine words") "a card whose line holds a secret is still sent: that line is a plain notice, the rest as it stands, the field named as refused"
    Check (-not $last.raw.Contains("A1b2C3d4") -and -not $last.raw.Contains("ghp_") -and (Said $t) -like "*research*now*notice in its place*" -and -not (Said $t).Contains("A1b2C3d4")) "and neither the secret nor its start is in what the phone opens, nor in the machine's own line"

    Write-Host ""
    Write-Host "--- 4b. a secret that straddles the 300-character cut: refused on the whole text, before the cut ---" -ForegroundColor Cyan
    # Review of PR 244 (F, 2026-10-14): the refusal ran on the text already cut to 297 characters and "...",
    # so a token across character 297 lost its tail, matched nothing, and its first part went out. Made-up
    # values: a 36-character token after its prefix, and a 40-character key with slashes in it.
    $pad = ("word " * 57).Substring(0, 285)
    $straddle = $pad + "ghp_" + "Zq7Xw2Lp9Rt4Vn6Bk1Mc8Hy3Jd5Fs0Ga2Ke7" + " and more words after it"
    $slashKey = "Qm9vX2Fy/Zk3LpT8vW2nB6cR1dY4hJ7sE0gU5aMx"
    $straddle2 = ("more " * 57).Substring(0, 280) + $slashKey + " then the end"
    Check ((Find-HordeSecretKind -Text $straddle) -cne "" -and (Find-HordeSecretKind -Text $straddle2) -cne "" -and (Find-HordeSecretKind -Text (Get-HordeCardsChannelPlain $straddle)) -ceq "" -and (Find-HordeSecretKind -Text (Get-HordeCardsChannelPlain $straddle2)) -ceq "" -and (Get-HordeCardsChannelPlain $straddle).Contains("ghp_Zq7")) "CONTROL: both texts are refused whole, and once cut to 300 characters neither is - the cut alone hides each from the refusal, and the token's start survives it"
    Set-Lane $A "research" (New-Status -Orc "E" -Lane "research" -Doing $straddle -Finished $straddle2)
    [System.IO.File]::WriteAllText((Join-Path $A.progress "thrall-status.txt"), (New-Status -Orc "M" -Lane "thrall" -Doing $straddle), $utf8)
    $t = Invoke-Tick $A
    $mail = @(Get-CardsMail $A)
    $last = $mail[$mail.Count - 1]
    $e = Get-Card $last.body "E"
    Check ($null -ne $e -and (@($e.refused) -join ",") -ceq "now,lastDone" -and $e.now -like "Not shown:*" -and $e.lastDone -like "Not shown:*") ("A LANE CARD: a token and a key that straddle the cut are refused, each field named (" + (@($e.refused) -join ",") + ")")
    Check ($last.body.thrall.hasStatus -and (@($last.body.thrall.refused) -join ",") -ceq "now" -and $last.body.thrall.now -like "Not shown:*") ("THE THRALL CARD: the same token in its own status is refused (" + (@($last.body.thrall.refused) -join ",") + ")")
    Check (-not $last.raw.Contains("ghp_") -and -not $last.raw.Contains("Zq7Xw2") -and -not $last.raw.Contains("Qm9vX2Fy") -and -not (Said $t).Contains("Zq7Xw2")) "and no first part of either goes to the phone or into the machine's own lines"
    $long = ("plain " * 80)
    Set-Lane $A "research" (New-Status -Orc "E" -Lane "research" -Doing $long -Finished "fine words")
    Remove-Item -LiteralPath (Join-Path $A.progress "thrall-status.txt")
    $t = Invoke-Tick $A
    $mail = @(Get-CardsMail $A)
    $e = Get-Card $mail[$mail.Count - 1].body "E"
    Check ($e.now.Length -eq 300 -and $e.now.EndsWith("...") -and @($e.refused).Count -eq 0) ("CONTROL: a long text with no secret is still cut to 300 characters and not refused (" + $e.now.Length + ")")

    Write-Host ""
    Write-Host "--- 5. replaced whole, only the latest kept; the same snapshot is not sent again ---" -ForegroundColor Cyan
    $before = @(Get-CardsMail $A)
    $t = Invoke-Tick $A
    $after = @(Get-CardsMail $A)
    Check ($after.Count -eq 1 -and $before.Count -eq 1 -and $after[0].seq -eq $before[0].seq -and @($t.lines | Where-Object { $_ -like "*sent*" }).Count -eq 0) ("nothing changed: nothing is sent, and the mailbox holds one cards snapshot (" + $after.Count + ")")
    Set-Lane $A "decisions-page" (New-Status -Orc "F" -Lane "decisions page" -Doing "something new")
    $t = Invoke-Tick $A
    $after = @(Get-CardsMail $A)
    Check ($after.Count -eq 1 -and $after[0].seq -gt $before[0].seq -and (Get-Card $after[0].body "F").now -ceq "something new") ("a lane's change sends a new snapshot, and the one before is gone from the mailbox: only the latest is kept (" + (@($after | ForEach-Object { $_.seq }) -join ",") + ")")
    $all = Receive-HordeRelayItems -Connection $A.conn -Mailbox "work/phone" -Since 0
    Check ($all.state -ceq "known" -and @($all.value.items).Count -eq 1) "CONTROL: the mailbox itself holds that one item, read without opening anything"
    Close-HordeRelayRunContext -Context $A.ctx
    $A.ctx = (New-HordeRelayRunContext -HordeHome $A.home -Connection $A.conn).value
    $t = Invoke-Tick $A
    $after2 = @(Get-CardsMail $A)
    Check ($after2.Count -eq 1 -and $after2[0].seq -gt $after[0].seq) "a new run sends one snapshot at its first look, and it replaces the one there"

    Write-Host ""
    Write-Host "--- 6. nothing comes in; settings refused stop it in words ---" -ForegroundColor Cyan
    $acc = Invoke-HordeCardsChannelAccept -Context $A.ctx -Item ([pscustomobject]@{ body = [byte[]]@() })
    $chan = Get-HordeRelayChannel -Name "cards"
    Check ($acc.outcome -ceq "refused" -and @($chan.kinds).Count -eq 0) "the cards channel takes no kind in, and refuses anything handed to it"
    [System.IO.File]::WriteAllText((Join-Path $A.home "settings\relay-cards.json"), '{"schemaVersion": 1, "settings": {"lanesFolder": "relative\\lanes"}}', $utf8)
    $t = Invoke-Tick $A
    Check ($t.failed -and (Said $t) -like "*cards are stopped*lanesFolder*") ("a lanesFolder that is not an absolute path refuses the settings, in words (" + (Said $t) + ")")
    $B = New-World -Settings ('{"sendIntervalMs": 0, "lanesFolder": "' + (Join-Path $env:TEMP ("horde-relay-cards-elsewhere-" + [guid]::NewGuid().ToString("N"))).Replace("\", "\\") + '"}')
    $t = Invoke-Tick $B
    Check ((Said $t) -like "*horde-relay-cards-elsewhere-*") "a lanesFolder setting is the folder read"

    Write-Host ""
    Write-Host "--- 7. one id is one card: two folders of one orc, and folder names no id can be made of ---" -ForegroundColor Cyan
    # Review of PR 244: two lanes with one id drew one card twice on the phone and the other never.
    $C = New-World
    Set-Lane $C "orc-f-first" (New-Status -Orc "F" -Lane "decisions page" -Doing "the first F")
    Set-Lane $C "orc-f-second" (New-Status -Orc "F" -Lane "decisions page too" -Doing "the second F")
    Set-Lane $C "!bad name one!" "just some words`n"
    Set-Lane $C "~bad name two~" "other words`n"
    Set-Lane $C "lane-4" "a folder named like a fallback id`n"
    $t = Invoke-Tick $C
    $mail = @(Get-CardsMail $C)
    $b = $mail[$mail.Count - 1].body
    $ids = @($b.cards | ForEach-Object { $_.lane })
    Check ($ids.Count -eq 5 -and @($ids | Select-Object -Unique).Count -eq 5) ("every card of a machine has its own id (" + ($ids -join ",") + ")")
    $f = @($b.cards | Where-Object { $_.lane -ceq "F" })
    $dup = @($b.cards | Where-Object { $_.name -ceq "decisions page too" })[0]
    Check ($f.Count -eq 1 -and $f[0].now -ceq "the first F" -and $null -ne $dup -and $dup.lane -cne "F" -and $dup.note -like "*(orc-f-first) gives the same id, F,*" -and (Said $t) -like "*orc-f-first and orc-f-second both give the id F*") ("TWO FOLDERS OF ONE ORC: the first by folder name keeps the id, the other gets its own and says why, on the phone and at the machine (" + $dup.lane + ": " + $dup.note + ")")
    $bad = @($b.cards | Where-Object { $_.name -like "*bad name*" })
    Check ($bad.Count -eq 2 -and $bad[0].lane -cne $bad[1].lane -and @($bad | Where-Object { $_.lane -cmatch '\Alane-[0-9]+\z' }).Count -eq 2) ("FOLDER NAMES NO ID IS MADE OF: each gets its own id by its place in the list, never one shared 'lane' (" + (@($bad | ForEach-Object { $_.lane }) -join ",") + ")")

    Write-Host ""
    Write-Host "--- 8. a map too large for the envelope is cut too, and the cards still go ---" -ForegroundColor Cyan
    # Review of PR 244: 200 areas against the budget left no card and a body still too large, so the save
    # was refused and retried every 30 s. The budget is the hosted relay's, for two phones: its text cap of
    # 65536 characters through the channel's own budget sum (47918). The local relay here allows about a
    # MiB, so the snapshot is made at that budget directly. A Hebrew letter is 6 bytes once written.
    $D = New-World
    Set-Lane $D "research" (New-Status -Orc "E" -Lane "research")
    Set-Lane $D "voice" (New-Status -Orc "B" -Lane "voice")
    $heb = -join (1..56 | ForEach-Object { [char](0x05D0 + ($_ % 27)) })
    $areaJson = (@(1..200 | ForEach-Object { '"' + $heb + ("{0:000}" -f $_) + '":"B,E"' }) -join ",")
    [System.IO.File]::WriteAllText((Join-Path $D.progress "area-lanes.json"), ('{"v":1,"areas":{' + $areaJson + '}}'), $utf8)
    $hosted = Get-HordeRelayChannelBodyBudget -Context ([pscustomobject]@{ connection = [pscustomobject]@{ relay = [pscustomobject]@{ limits = [pscustomobject]@{ maxTextChars = 65536 } } } }) -Recipients 2
    $setD = (Get-HordeModuleSettings -Declaration (Get-HordeCardsChannelSettingsDeclaration) -HordeHome $D.home).values
    $pathsD = Get-HordeCardsChannelPaths -HordeHome $D.home -Settings $setD
    $snap = New-HordeCardsChannelSnapshot -Context $D.ctx -Settings $setD -Paths $pathsD -Now ([datetime]::UtcNow) -Budget $hosted
    $sb = $snap.body | ConvertFrom-Json
    Check ($hosted -eq 47918 -and $snap.body.Length -le $hosted -and $snap.cards -eq 2 -and $snap.left -eq 0) ("200 AREAS: the body fits the hosted relay's budget for two phones and every card is kept (" + $snap.body.Length + " of " + $hosted + ", cards " + $snap.cards + ")")
    Check (@($sb.areas).Count -gt 0 -and @($sb.areas).Count -lt 200 -and $sb.areasLeftOut -eq (200 - @($sb.areas).Count) -and $sb.areas[0].area.EndsWith("001") -and (@($snap.lines) -join " | ") -like "*area(s) of the map did not fit*") ("the map is cut from its end, the rest counted for the phone and said at the machine (areas " + @($sb.areas).Count + ", left out " + $sb.areasLeftOut + ")")
    # 64 lanes, every text at its full 300 characters: 109185 bytes measured, so most are left out and counted.
    $G = New-World
    foreach ($n in 1..64) { $w = ("w" + $n + " ") * 100; Set-Lane $G ("lane{0:00}" -f $n) (New-Status -Orc ("L" + $n) -Lane $w -Doing $w -Finished $w -Waiting $w -Blocked ("yes " + $w)) }
    $setG = (Get-HordeModuleSettings -Declaration (Get-HordeCardsChannelSettingsDeclaration) -HordeHome $G.home).values
    $pathsG = Get-HordeCardsChannelPaths -HordeHome $G.home -Settings $setG
    $whole = New-HordeCardsChannelSnapshot -Context $G.ctx -Settings $setG -Paths $pathsG -Now ([datetime]::UtcNow) -Budget 1048576
    $snap = New-HordeCardsChannelSnapshot -Context $G.ctx -Settings $setG -Paths $pathsG -Now ([datetime]::UtcNow) -Budget $hosted
    $sb = $snap.body | ConvertFrom-Json
    Check ($whole.left -eq 0 -and $whole.body.Length -gt 100000 -and $snap.body.Length -le $hosted -and $snap.cards -gt 0 -and $snap.cards + $snap.left -eq 64 -and $sb.cardsLeftOut -eq $snap.left -and @($sb.cards).Count -eq $snap.cards -and (@($snap.lines) -join " | ") -like "*card(s) did not fit one envelope*") ("64 FULL CARDS do not fit the hosted budget: the last are left out, the phone told how many (whole " + $whole.body.Length + " bytes; kept " + $snap.cards + ", left out " + $snap.left + ")")
    # The map is cut further once no card is left: at every budget from 700 to 2000 bytes the body fits,
    # unless nothing but the Thrall's card and the name is left to cut.
    [System.IO.File]::WriteAllText((Join-Path $D.progress "area-lanes.json"), ('{"v":1,"areas":{' + (@(1..50 | ForEach-Object { '"area ' + $_ + '":"B"' }) -join ",") + '}}'), $utf8)
    $over = New-Object System.Collections.ArrayList
    foreach ($bud in @(700..2000 | Where-Object { $_ % 25 -eq 0 })) {
        $sn = New-HordeCardsChannelSnapshot -Context $D.ctx -Settings $setD -Paths $pathsD -Now ([datetime]::UtcNow) -Budget $bud
        $sj = $sn.body | ConvertFrom-Json
        if ($sn.body.Length -gt $bud -and ($sn.cards -gt 0 -or @($sj.areas).Count -gt 0)) { [void]$over.Add($bud) }
    }
    Check ($over.Count -eq 0) ("WITH NO CARD LEFT THE MAP IS CUT TOO: no budget leaves a body over it while a card or an area could still go (over at: " + ($over -join ",") + ")")

    Write-Host ""
    Write-Host "--- 9. the census: one bad run skips only itself; only the tail of an events file is read ---" -ForegroundColor Cyan
    $runsE = Join-Path $env:TEMP ("horde-relay-cards-" + [guid]::NewGuid().ToString("N"))
    [void]$script:homes.Add($runsE)
    $mk = { param([string]$Run, [string]$Manifest, [string]$Session, [string]$Events)
        $d = Join-Path $runsE $Run; [void][System.IO.Directory]::CreateDirectory((Join-Path $d ("sessions\" + $Session)))
        [System.IO.File]::WriteAllText((Join-Path $d "run.json"), $Manifest, $utf8)
        [System.IO.File]::WriteAllText((Join-Path $d ("sessions\" + $Session + "\events.jsonl")), $Events, $utf8) }
    & $mk "run-a-null" "null" "s1" ('{"event":"progress"}' + "`n")
    & $mk "run-b-list" "[1,2]" "s1" ('{"event":"progress"}' + "`n")
    & $mk "run-c-good" '{"runId":"c","closedAt":null}' "s1" ('{"event":"progress"}' + "`n")
    & $mk "run-d-good" '{"runId":"d"}' "s1" ('{"event":"blocked"}' + "`n")
    $cen = Read-HordeCardsChannelCensus -Path $runsE -Now ([datetime]::UtcNow)
    Check ($cen.ok -and $cen.running -eq 1 -and $cen.waiting -eq 1 -and $cen.skipped -eq 2) ("A RUN.JSON THAT IS NULL OR A LIST skips only that run: the good runs are still counted (ok " + $cen.ok + ", running " + $cen.running + ", waiting " + $cen.waiting + ", skipped " + $cen.skipped + ")")
    # A last line longer than the tail read is not read: what proves only the tail is read. Before it, a
    # megabyte of lines the census never needs.
    $bulk = ('{"event":"progress","pad":"' + ("p" * 200) + '"}' + "`n") * 5000
    & $mk "run-e-long" '{"runId":"e"}' "s1" ($bulk + '{"event":"blocked","pad":"' + ("q" * 70000) + '"}' + "`n")
    & $mk "run-f-big" '{"runId":"f"}' "s1" ($bulk + '{"event":"blocked"}' + "`n")
    # The tail begins inside a last line at exactly a JSON object's first byte: that piece is the end of a
    # line, not a line, and must not be read as one. 65536 bytes is the tail: the object and its newline.
    $obj = '{"event":"blocked","pad":"' + ("r" * (65535 - 28)) + '"}'
    Check ($obj.Length -eq 65535) "CONTROL: the crafted object and its newline are exactly the tail"
    & $mk "run-g-cut" '{"runId":"g"}' "s1" ($bulk + ("z" * 5000) + $obj + "`n")
    $cen = Read-HordeCardsChannelCensus -Path $runsE -Now ([datetime]::UtcNow)
    Check ($cen.ok -and $cen.running -eq 1 -and $cen.waiting -eq 2) ("ONLY THE TAIL IS READ: a megabyte file's last line is read from its end; a last line longer than the tail is not read at all (running " + $cen.running + ", waiting " + $cen.waiting + ")")

    Write-Host ""
    Write-Host "--- 10. a ledger field that is not text is no task ---" -ForegroundColor Cyan
    $ledgerE = Join-Path $runsE "tasks.jsonl"
    $ts = Iso ([datetime]::UtcNow.AddDays(-1))
    [System.IO.File]::WriteAllText($ledgerE, (@(
        ('{"ts":"' + $ts + '","task":"T-1","event":"opened","lane":"E"}'),
        ('{"ts":"' + $ts + '","task":{"a":1},"event":"opened","lane":"E"}'),
        ('{"ts":"' + $ts + '","task":"T-3","event":"opened","lane":["E"]}'),
        ('{"ts":"' + $ts + '","task":"T-4","event":7,"lane":"E"}')) -join "`n"), $utf8)
    $led = Read-HordeCardsChannelLedger -Path $ledgerE -Now ([datetime]::UtcNow)
    Check ($led.ok -and $led.lanes["E"].open -eq 1 -and $led.skipped -eq 3 -and -not $led.lanes.ContainsKey("@{a=1}") -and -not $led.lanes.ContainsKey("E E")) ("a task, event or lane that is an object, a list or a number is passed over and counted, never read as its printed form (open " + $led.lanes["E"].open + ", skipped " + $led.skipped + ")")
} finally {
    $env:HORDE_HOME = $realHome
    Exit-HordeTestEmptyFleet -Pin $fleetPin
    foreach ($w in $script:worlds) { Close-HordeRelayRunContext -Context $w.ctx }
    $keys = New-Object System.Collections.ArrayList
    foreach ($h in $script:homes) {
        $dir = Join-Path $h "relay\identity"
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter "machine-*.json")) {
            $mm = [regex]::Match([System.IO.File]::ReadAllText($f.FullName), '"scope":"([a-z]+)","signName":"([a-z0-9-]+)".*"agreeName":"([a-z0-9-]+)"')
            if ($mm.Success) { [void]$keys.Add(@{ n = $mm.Groups[2].Value; s = $mm.Groups[1].Value }); [void]$keys.Add(@{ n = $mm.Groups[3].Value; s = $mm.Groups[1].Value }) }
        }
    }
    foreach ($k in $keys) { try { [void](Remove-HordeRelayKey -Name $k.n -Scope $k.s) } catch { } }
    $left = @($keys | Where-Object { (Find-HordeRelayCngKey -Name $_.n -Scope $_.s) -cne "" })
    Check ($keys.Count -ge 2 -and $left.Count -eq 0) ("every key the suite made is gone (" + $keys.Count + ")")
    foreach ($h in $script:homes) { if ((Split-Path -Leaf $h) -match '^horde-relay-cards-[0-9a-f]{32}$') { Remove-Item -LiteralPath $h -Recurse -Force -ErrorAction SilentlyContinue } }
    Check (@($script:homes | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 0 -and -not (Test-Path -LiteralPath $fleetPin.path)) "every folder the suite made is gone"
}

Complete-HordeSuite -Success "the phone gets one card per lane and one for the Thrall, made from what each lane says now, sent whole with only the latest kept, with no secret in it and no lane missing"
