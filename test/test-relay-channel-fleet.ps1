# DOES THE PC TAKE EXACTLY THE FLEET BODIES THE CONTRACT LISTS, ACT ON EACH ONCE, ANSWER EVERY ONE IN THE NEXT
# SNAPSHOT - AND DOES IT SEND EXACTLY THE SNAPSHOT SHAPE THE CONTRACT LISTS?
#
# The fleet channel (channels/fleet) against test/fixtures/fleet/ (README.md, fleet-snapshot.json, tier.json,
# hibernate.json, wake.json), the contract the phone side builds to. Every outside effect is a stand-in
# handed in through the channel's seams ($Context.state["fleet.seams"]): the Orc registry's reader and
# its tier write, the never list, the hibernation records, "is one running", and the background start. So
# no hibernation, wake or registry write happens here. The real registry reader and tier write are
# attacked once in section 8, against a registry under a home of the suite's own.
# It attacks:
#   1. EACH FIXTURE IS TAKEN (with this machine's key id in place of the fixture's), and does what it says.
#   2. EVERY MALFORMED BODY IS REFUSED, and acts on nothing: each member added, removed, repeated, of the
#      wrong type or outside its range, for each kind, and a body that is not UTF-8 or not an object.
#   3. THE PROOF: a fresh passkey and the unlocked session are taken; es256 and no proof are not.
#   4. THE ANSWERS: a stale version is retry, an Orc in never is refused, a hibernation while one runs is
#      retry, and the same setId twice is acted on once - but a retried setId is a new attempt.
#   5. THE SNAPSHOT: built from the fixture's own facts it is the fixture, member for member; the reader
#      refuses a member added, missing, repeated, an overlap of tiers and never, and a state from the OTHER
#      state list ("exited" in a finished hibernation, "woken" in a running one).
#   6. OUT, end to end: a request signed by the founder's passkey is answered in lastResult of the snapshot
#      the phone opens; nothing is sent again when nothing changed; a phone key trusted since is sent it.
#   7. WHAT RUNS: a held lock, a started process that lives, a stale lock; the records that count.
#   8. THE REAL REGISTRY: the channel's reader and tier write against orcs/Registry.ps1.
#
# NO REAL FLEET, HOME OR RELAY IS TOUCHED: the fleet root is an empty folder of the suite's own
# (test/lib/FleetPin.ps1); every home and mailbox is under %TEMP% and is removed at the end.

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
. (Join-Path $root "cli\RelayRun.ps1")
. (Join-Path $root "test\lib\RelayPhone.ps1")
Set-StrictMode -Version Latest
Write-Host ("  runtime: PowerShell " + $PSVersionTable.PSVersion + " (" + $PSVersionTable.PSEdition + ")") -ForegroundColor DarkGray

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$script:homes = New-Object System.Collections.ArrayList
$script:worlds = New-Object System.Collections.ArrayList
$realHome = $env:HORDE_HOME
$fixtures = Join-Path $root "test\fixtures\fleet"
$fixtureMachine = "9f8e7d6c5b4a39281706f5e4d3c2b1a0"

if ((Get-HordeRelayKeyStore).state -cne "known") {
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Complete-HordeSuite -Success "no key store here: no machine identity can be made, so nothing was run" -PassCode 3
}

# --- the stand-in world: what the seams answer and what they were asked ---
$script:Stand = $null
function Reset-Stand {
    $script:Stand = @{
        version = 7
        orcs = @(
            [pscustomobject]@{ id = "sleeping-sessions"; tier = 1 }, [pscustomobject]@{ id = "decisions-page"; tier = 1 },
            [pscustomobject]@{ id = "relay-port"; tier = 1 }, [pscustomobject]@{ id = "phone-app"; tier = 2 })
        registryState = "known"
        never = @([pscustomobject]@{ orc = "analyst-service"; reason = "the fleet analyst runs as a service and is never parked" }, [pscustomobject]@{ orc = "thrall-lane"; reason = "the master coordinates the fleet and is never put to sleep" })
        records = @([pscustomobject]@{ id = "20261015-221030"; createdAt = "2026-10-15T22:10:30Z"; phase = "done"; sessions = @() })
        hibernating = $false; waking = @(); busyState = "known"
        setTierCalls = New-Object System.Collections.ArrayList; startCalls = New-Object System.Collections.ArrayList
        setTierAnswer = $null; startAnswer = $null
        registryReads = 0
    }
}
function New-Seams {
    return @{
        Registry = { param($h) $script:Stand.registryReads++; if ($script:Stand.registryState -cne "known") { return (New-HordeUnknown -Reason "the registry folder is held by another process") }; New-HordeKnown -Value ([pscustomobject]@{ version = [long]$script:Stand.version; orcs = @($script:Stand.orcs) }) }
        Never = { param($h) New-HordeKnown -Value @($script:Stand.never) }
        SetTier = { param($h, $id, $tier, $version)
            [void]$script:Stand.setTierCalls.Add([pscustomobject]@{ id = $id; tier = $tier; version = $version })
            if ($null -ne $script:Stand.setTierAnswer) { return $script:Stand.setTierAnswer }
            $o = @($script:Stand.orcs | Where-Object { $_.id -ceq $id })[0]
            if ($o.tier -eq $tier) { return [pscustomobject]@{ outcome = "unchanged"; reason = "the list already says that"; version = $script:Stand.version } }
            $o.tier = $tier; $script:Stand.version++
            return [pscustomobject]@{ outcome = "done"; reason = ""; version = $script:Stand.version } }
        Records = { param($h) New-HordeKnown -Value ([pscustomobject]@{ records = @($script:Stand.records); lines = @() }) }
        Busy = { param($ctx, $h, $children) if ($script:Stand.busyState -cne "known") { return (New-HordeUnknown -Reason "the lock cannot be read") }; New-HordeKnown -Value ([pscustomobject]@{ hibernating = $script:Stand.hibernating; waking = @($script:Stand.waking) }) }
        Start = { param($words)
            [void]$script:Stand.startCalls.Add(($words -join " "))
            if ($null -ne $script:Stand.startAnswer) { return $script:Stand.startAnswer }
            New-HordeKnown -Value ([pscustomobject]@{ pid = 4242; start = "133000000000000000" }) }
        ProcessStart = { param($p) "" }
    }
}

# --- worlds, as the notices suite makes them ---
function New-TestHome {
    param([string]$Settings = '{"keepEnvelopes": 5, "sessionsMost": 12, "lookMs": 0}')
    $h = Join-Path $env:TEMP ("horde-relay-fleet-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path (Join-Path $h "settings") -Force | Out-Null
    [void]$script:homes.Add($h)
    [System.IO.File]::WriteAllText((Join-Path $h "settings\relay.json"), '{"schemaVersion": 1, "settings": {"horde": "work"}}', $utf8)
    [System.IO.File]::WriteAllText((Join-Path $h "settings\relay-fleet.json"), ('{"schemaVersion": 1, "settings": ' + $Settings + '}'), $utf8)
    return $h
}
function Add-PhoneKey {
    param([string]$HordeHome, $Phone)
    $v = New-HordeTestPhoneVouch -Phone $Phone -Horde "work"
    $k = Add-HordeRelayPhoneKey -HordeHome $HordeHome -AgreePublic $Phone.agreePublic -By $Phone.keyId -AuthenticatorData $v.authenticatorData -ClientDataJson $v.clientDataJson -Signature $v.signature
    if ($k.state -cne "known") { throw ("no phone key: " + $k.reason) }
}
function New-World {
    param([string]$Settings = '{"keepEnvelopes": 5, "sessionsMost": 12, "lookMs": 0}')
    $h = New-TestHome -Settings $Settings
    $env:HORDE_HOME = $h
    $id = New-HordeRelayMachineIdentity -HordeHome $h -Provider "software"
    if ($id.state -cne "known") { throw ("no identity: " + $id.reason) }
    $phone = New-HordeTestPhone
    [void](Add-HordeTestPhonePairing -HordeHome $h -Phone $phone)
    Add-PhoneKey -HordeHome $h -Phone $phone
    $c = Connect-HordeRelay -Name "local" -Options @{ root = (Join-Path $h "relay-mailboxes") }
    if ($c.state -cne "known") { throw ("no relay: " + $c.reason) }
    $ctx = New-HordeRelayRunContext -HordeHome $h -Connection $c.value
    if ($ctx.state -cne "known") { throw ("no context: " + $ctx.reason) }
    $ctx.value.state["fleet.seams"] = (New-Seams)
    $w = [pscustomobject]@{ home = $h; id = $id.value; phone = $phone; conn = $c.value; ctx = $ctx.value; agree = @(, ([byte[]]$id.value.agree.public)); seen = 0 }
    [void]$script:worlds.Add($w)
    return $w
}
function Invoke-Tick { param($World) $env:HORDE_HOME = $World.home; return (Invoke-HordeFleetChannelTick -Context $World.ctx) }
function Said { param($Tick) return (@($Tick.lines) -join " | ") }
function Get-NewMail {
    # What -Phone (the world's) opens of the fleet items after the last look: { seq; ok; body; to }.
    param($World, $Phone = $null, [switch]$All)
    if ($null -eq $Phone) { $Phone = $World.phone }
    $r = Receive-HordeRelayItems -Connection $World.conn -Mailbox "work/phone" -Since 0
    if ($r.state -cne "known") { return @() }
    $items = @($r.value.items | Where-Object { $All -or $_.seq -gt $World.seen })
    if (-not $All -and $items.Count -gt 0) { $World.seen = ($items | ForEach-Object { [long]$_.seq } | Measure-Object -Maximum).Maximum }
    $out = New-Object System.Collections.ArrayList
    foreach ($it in $items) {
        $hdr = (Read-HordeRelayEnvelope -Text $it.text).value.header
        if ($hdr.channel -cne "fleet") { continue }
        $o = Open-HordeTestPhoneEnvelope -Phone $Phone -Text $it.text -MachineSignPublic $World.id.sign.public
        [void]$out.Add([pscustomobject]@{ seq = [long]$it.seq; ok = $o.ok; body = $o.body; to = @($hdr.to); kind = $hdr.kind })
    }
    return @($out.ToArray())
}
function Send-ToMachine { param($World, [string]$Text) return (Send-HordeRelayItem -Connection $World.conn -Mailbox $World.ctx.mailbox -Text $Text -Key (Get-HordeRelayReplayKey -Header (Read-HordeRelayEnvelope -Text $Text).value.header)) }
function Invoke-Turn {
    param($World)
    $env:HORDE_HOME = $World.home
    $in = Receive-HordeRelayInbox -Context $World.ctx -TimeoutMs 0
    $un = Invoke-HordeRelayUnfinished -Context $World.ctx
    $lines = New-Object System.Collections.ArrayList
    if ($in.state -ceq "known") { foreach ($l in @($in.value.refused)) { [void]$lines.Add("refused " + $l) }; foreach ($l in @($in.value.held)) { [void]$lines.Add("held " + $l) } }
    else { [void]$lines.Add("inbox " + $in.state + ": " + $in.reason) }
    foreach ($l in @(Get-HordeRelayRunLines -Report $un.value)) { [void]$lines.Add($l) }
    return [pscustomobject]@{ text = (@($lines.ToArray()) -join " | ") }
}

# --- bodies ---
function Get-FixtureText { param([string]$Name) return [System.IO.File]::ReadAllText((Join-Path $fixtures ($Name + ".json"))) }
function New-SetId { return [guid]::NewGuid().ToString("N") }
function Get-BodyFor {
    # A fixture's body for -World's machine, with a setId of its own unless -KeepSetId. Compact JSON.
    param($World, [string]$Name, [switch]$KeepSetId)
    $o = Get-FixtureText $Name | ConvertFrom-Json
    $o.machine = $World.id.sign.keyId
    if (-not $KeepSetId) { $o.setId = New-SetId }
    return ($o | ConvertTo-Json -Compress -Depth 5)
}
function Get-Parsed { param($World, [string]$Name) return (Get-BodyFor $World $Name | ConvertFrom-Json) }
function Out-Body { param($Object) return ($Object | ConvertTo-Json -Compress -Depth 5) }
function New-Item2 {
    param([string]$Kind, $Body, [string]$Proof = "webauthn", [switch]$NoProof)
    $bytes = $(if ($Body -is [byte[]]) { $Body } else { $utf8.GetBytes([string]$Body) })
    $i = [ordered]@{ from = ("a" * 32); channel = "fleet"; kind = $Kind; seq = 1; key = ("k/fleet/1/" + (New-SetId).Substring(0, 8)); evidence = ""; ts = 0; body = [byte[]]$bytes }
    if (-not $NoProof) { $i["proof"] = $Proof }
    return [pscustomobject]$i
}
function Accept { param($World, [string]$Kind, $Body, [string]$Proof = "webauthn") $env:HORDE_HOME = $World.home; return (Invoke-HordeFleetChannelAccept -Context $World.ctx -Item (New-Item2 -Kind $Kind -Body $Body -Proof $Proof)) }
function Get-Last {
    # The channel's lastResult as the state file holds it.
    param($World)
    $r = Read-HordeFleetChannelState -HordeHome $World.home
    if ($r.state -cne "known") { return $null }
    return $r.value.lastResult
}
function Acted { return ($script:Stand.setTierCalls.Count + $script:Stand.startCalls.Count) }

try {
    Write-Host ""
    Write-Host "--- 1. each fixture is taken, and does what it says ---" -ForegroundColor Cyan
    Reset-Stand
    $W0 = New-World
    $W = $W0
    $b = Get-BodyFor $W "tier"
    $a = Accept $W "tier" $b
    $tc = @($script:Stand.setTierCalls)
    Check ($a.outcome -ceq "done" -and $a.answer -ceq "done" -and $tc.Count -eq 1 -and $tc[0].id -ceq "relay-port" -and $tc[0].tier -eq 2 -and $tc[0].version -eq 7) ("tier.json: relay-port goes to tier 2, against registry version 7 (" + $a.reason + ")")
    $l = Get-Last $W
    Check ($null -ne $l -and $l.outcome -ceq "done" -and $l.setId -ceq ($b | ConvertFrom-Json).setId) "and the answer is kept as the last result, under the request's setId"
    Reset-Stand; $W = $W0
    $a = Accept $W "hibernate" (Get-BodyFor $W "hibernate")
    Check ($a.outcome -ceq "done" -and $script:Stand.startCalls.Count -eq 1 -and $script:Stand.startCalls[0] -ceq "hibernate -Tier 2") ("hibernate.json: `horde fleet hibernate -Tier 2` is started in the background (" + $a.reason + ")")
    Reset-Stand; $W = $W0
    $a = Accept $W "wake" (Get-BodyFor $W "wake")
    Check ($a.outcome -ceq "done" -and $script:Stand.startCalls.Count -eq 1 -and $script:Stand.startCalls[0] -ceq "wake 20261015-221030") ("wake.json: `horde fleet wake 20261015-221030` is started in the background (" + $a.reason + ")")
    Reset-Stand; $W = $W0
    $a = Accept $W "tier" (Get-FixtureText "tier")
    Check ($a.outcome -ceq "refused" -and $a.reason -like "*another machine*" -and (Acted) -eq 0) ("the fixture as it stands, for a machine that is not this one, is refused (" + $a.reason + ")")

    Write-Host ""
    Write-Host "--- 2. every malformed body is refused, and acts on nothing ---" -ForegroundColor Cyan
    Reset-Stand; $W = $W0
    $bad = New-Object System.Collections.ArrayList
    $cases = New-Object System.Collections.ArrayList
    function Add-Case { param([string]$Name, $Body) [void]$cases.Add([pscustomobject]@{ name = $Name; body = $Body }) }
    foreach ($kind in @("tier", "hibernate", "wake")) {
        $base = Get-Parsed $W $kind
        $members = @($base.PSObject.Properties | ForEach-Object { $_.Name })
        Add-Case ($kind + ": a member added") (Out-Body (& { $o = Get-Parsed $W $kind; $o | Add-Member -NotePropertyName "extra" -NotePropertyValue 1; $o }))
        foreach ($m in $members) {
            Add-Case ($kind + ": " + $m + " missing") (Out-Body (& { $o = Get-Parsed $W $kind; $o.PSObject.Properties.Remove($m); $o }))
            Add-Case ($kind + ": " + $m + " twice") ((Get-BodyFor $W $kind).Replace('{"v":1,', '{"v":1,"' + $m + '":1,'))
            Add-Case ($kind + ": " + $m + " null") (Out-Body (& { $o = Get-Parsed $W $kind; $o.$m = $null; $o }))
        }
        $sets = @(
            @("v", 2), @("v", "1"), @("v", $true), @("v", 1.5), @("setId", "6F1C0B9E2D4A48F7A3B5C6D7E8F90A1B"), @("setId", "6f1c0b9e2d4a48f7a3b5c6d7e8f90a1"), @("setId", ("a" * 33)), @("setId", 12),
            @("machine", "9f8e7d6c"), @("machine", ("A" * 32)), @("machine", 5))
        foreach ($s in $sets) { Add-Case ($kind + ": " + $s[0] + " = " + $s[1]) (Out-Body (& { $o = Get-Parsed $W $kind; $o.($s[0]) = $s[1]; $o })) }
        $text = Get-BodyFor $W $kind
        Add-Case ($kind + ": a member in another case") ($text.Replace('"setId"', '"SetId"'))
        Add-Case ($kind + ": not JSON") "not json"
        Add-Case ($kind + ": a list") "[]"
        Add-Case ($kind + ": a string") '"x"'
        Add-Case ($kind + ": empty") ""
        Add-Case ($kind + ": a byte-order mark") ([string][char]0xFEFF + $text)
        Add-Case ($kind + ": not UTF-8") ([byte[]](@(0x7B, 0x22, 0xFF, 0xFE, 0x22, 0x7D)))
    }
    foreach ($s in @(@("tier", 0), @("tier", 3), @("tier", "2"), @("tier", 2.5), @("tier", $true), @("version", -1), @("version", 7.5), @("version", "7"), @("orc", ""), @("orc", "-x"), @("orc", "a b"), @("orc", 7), @("orc", ("a" * 65)))) {
        Add-Case ("tier: " + $s[0] + " = " + $s[1]) (Out-Body (& { $o = Get-Parsed $W "tier"; $o.($s[0]) = $s[1]; $o }))
    }
    foreach ($s in @(@("tier", 1), @("tier", 3), @("tier", "2"), @("version", -1), @("version", "7"), @("version", 7.5))) {
        Add-Case ("hibernate: " + $s[0] + " = " + $s[1]) (Out-Body (& { $o = Get-Parsed $W "hibernate"; $o.($s[0]) = $s[1]; $o }))
    }
    foreach ($s in @("2026-10-16", "20261016-09150", "20261016-0915000", "20261016_091500", 20261016)) {
        Add-Case ("wake: hibernationId = " + $s) (Out-Body (& { $o = Get-Parsed $W "wake"; $o.hibernationId = $s; $o }))
    }
    Add-Case "wake: a version added (it carries none on purpose)" (Out-Body (& { $o = Get-Parsed $W "wake"; $o | Add-Member -NotePropertyName "version" -NotePropertyValue 7; $o }))
    Add-Case "tier: a hibernationId in place of orc" (Out-Body (& { $o = Get-Parsed $W "tier"; $o.PSObject.Properties.Remove("orc"); $o | Add-Member -NotePropertyName "hibernationId" -NotePropertyValue "20261015-221030"; $o }))
    foreach ($c in $cases) {
        $kind = $c.name.Split(":")[0]
        $got = $null
        try { $got = Accept $W $kind $c.body } catch { $got = [pscustomobject]@{ outcome = "threw: " + $_.Exception.Message } }
        # By the PARSER's reason: a body that breaks its shape is refused for that, never by a later check
        # (the registry not listing an Orc named "a b") that would pass it if the shape check were gone.
        if ($got.outcome -cne "refused") { [void]$bad.Add($c.name + " -> " + $got.outcome) }
        elseif ("" + (Get-HordeTestMember $got "reason") -notlike "*request*") { [void]$bad.Add($c.name + " -> refused for " + $got.reason) }
    }
    Check ($cases.Count -ge 100 -and $bad.Count -eq 0) ("each of " + $cases.Count + " malformed bodies is refused at the port (" + (@($bad | Select-Object -First 4) -join "; ") + ")")
    Check ((Acted) -eq 0) "and none of them changed a tier or started anything"
    Reset-Stand; $W = $W0
    $a = Accept $W "tier" (Out-Body (& { $o = Get-Parsed $W "tier"; $o | Add-Member -NotePropertyName "extra" -NotePropertyValue 1; $o }))
    $l = Get-Last $W
    Check ($null -ne $l -and $l.outcome -ceq "refused" -and $l.reason -like "*members*") ("a refused body that carries a setId is answered to it in lastResult (" + $(if ($null -ne $l) { $l.reason } else { "no last result" }) + ")")
    $a = Accept $W "tier" "not json"
    Check ($a.outcome -ceq "refused" -and (Get-Last $W).outcome -ceq "refused") "a body with no setId to answer to is refused and leaves the last result as it was"
    $a = Accept $W "tier" (Get-FixtureText "wake")
    Check ($a.outcome -ceq "refused") "a wake body on the tier kind is refused (its members are not tier's)"

    Write-Host ""
    Write-Host "--- 3. the proof: a fresh passkey or his unlocked session, nothing else ---" -ForegroundColor Cyan
    foreach ($kind in @("tier", "hibernate", "wake")) {
        foreach ($proof in @("webauthn", "session")) {
            Reset-Stand; $W = $W0
            $a = Accept $W $kind (Get-BodyFor $W $kind) $proof
            Check ($a.outcome -ceq "done" -and (Acted) -eq 1) ("a " + $kind + " signed with proof " + $proof + " is taken (" + $a.reason + ")")
        }
        Reset-Stand; $W = $W0
        $a = Accept $W $kind (Get-BodyFor $W $kind) "es256"
        Check ($a.outcome -ceq "refused" -and (Acted) -eq 0 -and $a.reason -like "*es256*") ("a " + $kind + " signed by a machine (es256) is refused (" + $a.reason + ")")
        $env:HORDE_HOME = $W.home
        $a = Invoke-HordeFleetChannelAccept -Context $W.ctx -Item (New-Item2 -Kind $kind -Body (Get-BodyFor $W $kind) -NoProof)
        Check ($a.outcome -ceq "refused" -and (Acted) -eq 0 -and $a.reason -like "*no proof named*") ("a " + $kind + " that says nothing of its proof is refused, never guessed to be a passkey's (" + $a.reason + ")")
    }

    Write-Host ""
    Write-Host "--- 4. the answers: stale is retry, never is refused, a running hibernation is retry, a setId is acted on once ---" -ForegroundColor Cyan
    Reset-Stand; $W = $W0
    $o = Get-Parsed $W "tier"; $o.version = 6
    $a = Accept $W "tier" (Out-Body $o)
    $l = Get-Last $W
    Check ($a.answer -ceq "retry" -and $a.outcome -ceq "refused" -and (Acted) -eq 0 -and $l.outcome -ceq "retry" -and $l.reason -like "*version 7*") ("a tier request drawn from version 6 against version 7 is answered retry, nothing written (" + $a.reason + ")")
    Check ($a.outcome -cne "retry") "and it is finished at the port, so it is not handed over again to act on a list that has moved"
    Reset-Stand; $W = $W0
    $script:Stand.setTierAnswer = [pscustomobject]@{ outcome = "stale"; reason = "the registry moved to version 8"; version = 8 }
    $a = Accept $W "tier" (Get-BodyFor $W "tier")
    Check ($a.answer -ceq "retry" -and $script:Stand.setTierCalls.Count -eq 1 -and $script:Stand.setTierCalls[0].version -eq 7) ("the registry's own stale answer, a race lost, is retry too - and the write carried the version it was drawn from (" + $a.reason + ")")
    Reset-Stand; $W = $W0
    $script:Stand.setTierAnswer = [pscustomobject]@{ outcome = "unknown"; reason = "record 8 could not be written"; version = 7 }
    $a = Accept $W "tier" (Get-BodyFor $W "tier")
    Check ($a.outcome -ceq "retry") ("a write that could not be made is handed over again by the port (" + $a.reason + ")")
    foreach ($never in @("analyst-service", "thrall-lane")) {
        Reset-Stand; $W = $W0
        $o = Get-Parsed $W "tier"; $o.orc = $never
        $a = Accept $W "tier" (Out-Body $o)
        Check ($a.answer -ceq "refused" -and (Acted) -eq 0 -and $a.reason -like "*never put to sleep*") ("a tier for " + $never + ", which is never put to sleep, is refused (" + $a.reason + ")")
    }
    Reset-Stand; $W = $W0
    $o = Get-Parsed $W "tier"; $o.orc = "no-such-orc"
    $a = Accept $W "tier" (Out-Body $o)
    Check ($a.answer -ceq "refused" -and (Acted) -eq 0) ("a tier for an Orc the registry does not list is refused (" + $a.reason + ")")
    Reset-Stand; $W = $W0
    $o = Get-Parsed $W "tier"; $o.orc = "relay-port"; $o.tier = 1
    $a = Accept $W "tier" (Out-Body $o)
    Check ($a.answer -ceq "done" -and $a.reason -like "*already in tier 1*") ("a tier the Orc already has is done and says nothing was written (" + $a.reason + ")")
    Reset-Stand; $W = $W0
    $script:Stand.registryState = "unknown"
    $a = Accept $W "tier" (Get-BodyFor $W "tier")
    Check ($a.outcome -ceq "retry" -and (Acted) -eq 0) ("a registry that cannot be read now is a port retry, nothing done (" + $a.reason + ")")
    Reset-Stand; $W = $W0
    $script:Stand.hibernating = $true
    $a = Accept $W "hibernate" (Get-BodyFor $W "hibernate")
    $l = Get-Last $W
    Check ($a.answer -ceq "retry" -and $script:Stand.startCalls.Count -eq 0 -and $l.outcome -ceq "retry" -and $l.reason -like "*running*") ("a hibernate while one runs is answered retry, nothing started (" + $a.reason + ")")
    Check ($a.outcome -cne "retry") "and is finished at the port, so it does not start a hibernation the moment the first ends"
    Reset-Stand; $W = $W0
    $o = Get-Parsed $W "hibernate"; $o.version = 3
    $a = Accept $W "hibernate" (Out-Body $o)
    Check ($a.answer -ceq "retry" -and $script:Stand.startCalls.Count -eq 0) ("a hibernate drawn from a stale registry is retry (" + $a.reason + ")")
    Reset-Stand; $W = $W0
    foreach ($x in $script:Stand.orcs) { $x.tier = 1 }
    $a = Accept $W "hibernate" (Get-BodyFor $W "hibernate")
    Check ($a.answer -ceq "refused" -and $script:Stand.startCalls.Count -eq 0 -and $a.reason -like "*tier 2*") ("a hibernate with no Orc in tier 2 is refused, in words (" + $a.reason + ")")
    Reset-Stand; $W = $W0
    $before = @((Read-HordeFleetChannelState -HordeHome $W.home).value.children).Count
    $a = Accept $W "hibernate" (Get-BodyFor $W "hibernate")
    $kids = @((Read-HordeFleetChannelState -HordeHome $W.home).value.children)
    Check ($kids.Count -eq $before + 1 -and $kids[-1].kind -ceq "hibernate" -and $kids[-1].pid -eq 4242) "the process started for a hibernation is kept in the state, so a second request can see it"
    Reset-Stand; $W = $W0
    $script:Stand.startAnswer = New-HordeUnknown -Reason "horde.ps1 is not there"
    $a = Accept $W "hibernate" (Get-BodyFor $W "hibernate")
    Check ($a.answer -ceq "refused" -and $a.reason -like "*could not be started*") ("a hibernation that could not be started is refused with why, not left to start later (" + $a.reason + ")")
    Reset-Stand; $W = $W0
    $a = Accept $W "wake" (Get-BodyFor $W "wake")
    $o = Get-Parsed $W "wake"; $o.hibernationId = "20250101-000000"
    $a2 = Accept $W "wake" (Out-Body $o)
    Check ($a2.answer -ceq "refused" -and $script:Stand.startCalls.Count -eq 1 -and $a2.reason -like "*no hibernation 20250101-000000*") ("a wake of a hibernation that does not exist is refused (" + $a2.reason + ")")
    Reset-Stand; $W = $W0
    $script:Stand.waking = @("20261015-221030")
    $a = Accept $W "wake" (Get-BodyFor $W "wake")
    Check ($a.answer -ceq "retry" -and $script:Stand.startCalls.Count -eq 0) ("a wake of a hibernation being woken now is retry (" + $a.reason + ")")
    Reset-Stand; $W = $W0
    $script:Stand.hibernating = $true
    $a = Accept $W "wake" (Get-BodyFor $W "wake")
    Check ($a.answer -ceq "retry" -and $script:Stand.startCalls.Count -eq 0) ("a wake while a hibernation runs is retry (" + $a.reason + ")")

    Write-Host ""
    Write-Host "--- 4b. a setId is acted on once ---" -ForegroundColor Cyan
    Reset-Stand; $W = $W0
    $b = Get-BodyFor $W "tier"
    $a1 = Accept $W "tier" $b
    $a2 = Accept $W "tier" $b
    Check ($script:Stand.setTierCalls.Count -eq 1 -and $a1.outcome -ceq "done" -and $a2.outcome -ceq "done") ("the same tier request twice writes once, and answers done both times (" + $a2.reason + ")")
    Reset-Stand; $W = $W0
    $b = Get-BodyFor $W "hibernate"
    $a1 = Accept $W "hibernate" $b
    $script:Stand.hibernating = $false
    $a2 = Accept $W "hibernate" $b
    Check ($script:Stand.startCalls.Count -eq 1) "the same hibernate twice starts one hibernation, even when the first has ended"
    Reset-Stand; $W = $W0
    $b = Get-BodyFor $W "wake"
    $null = Accept $W "wake" $b; $null = Accept $W "wake" $b; $null = Accept $W "wake" $b
    Check ($script:Stand.startCalls.Count -eq 1) "the same wake three times starts one wake"
    Reset-Stand; $W = $W0
    $script:Stand.hibernating = $true
    $b = Get-BodyFor $W "hibernate"
    $a1 = Accept $W "hibernate" $b
    $script:Stand.hibernating = $false
    $a2 = Accept $W "hibernate" $b
    Check ($a1.answer -ceq "retry" -and $a2.answer -ceq "done" -and $script:Stand.startCalls.Count -eq 1) "a request answered retry is not remembered: the phone asks again with the same setId and that is a new attempt"
    Reset-Stand; $W = $W0
    $b = Get-BodyFor $W "tier"
    $null = Accept $W "tier" $b
    $W.ctx.state.Remove("fleet")
    $a2 = Accept $W "tier" $b
    Check ($script:Stand.setTierCalls.Count -eq 1 -and $a2.outcome -ceq "done") "and what was answered survives a restart (the state file), not only the run"

    Write-Host ""
    Write-Host "--- 5. the snapshot: the fixture's facts build the fixture, and the reader refuses what the contract refuses ---" -ForegroundColor Cyan
    $fix = Get-FixtureText "fleet-snapshot"
    $own = Test-HordeFleetChannelSnapshot -Text $fix
    Check ($own.ok) ("CONTROL: the fixture passes the channel's own reader (" + $own.reason + ")")
    $rec = {
        param($id, $at, $phase, $sessions)
        [pscustomobject]@{ id = $id; createdAt = $at; phase = $phase; sessions = @($sessions | ForEach-Object { [pscustomobject]@{ sessionId = ("00000000-0000-4000-8000-" + "{0:d12}" -f (Get-Random)); label = $_[0]; role = $_[1]; state = $_[2] } }) }
    }
    $reg = [pscustomobject]@{ version = 7; orcs = @([pscustomobject]@{ id = "sleeping-sessions"; tier = 1 }, [pscustomobject]@{ id = "decisions-page"; tier = 1 }, [pscustomobject]@{ id = "relay-port"; tier = 2 }, [pscustomobject]@{ id = "phone-app"; tier = 2 }, [pscustomobject]@{ id = "analyst-service"; tier = 1 }) }
    $nv = @([pscustomobject]@{ orc = "analyst-service"; reason = "the fleet analyst runs as a service and is never parked" })
    $recs = @(
        (& $rec "20261016-091500" "2026-10-16T09:15:00Z" "parking" @(@("R", "orc", "parked"), @("R1", "warg", "asked"), @("L", "orc", "asked"))),
        (& $rec "20261015-221030" "2026-10-15T22:10:30Z" "done" @(@("R", "orc", "woken"), @("R1", "warg", "woken"), @("L", "orc", "still-awake"), @("L2", "warg", "failed"), @("X1", "warg", "exited"), @("X2", "warg", "exited"), @("X3", "warg", "exited"))),
        (& $rec "20261014-183005" "2026-10-14T18:30:05Z" "done" @(, @("L", "orc", "exited"))),
        ([pscustomobject]@{ id = "20261013-120000"; createdAt = "2026-10-13T12:00:00Z"; sessions = @() }))
    $last = [pscustomobject]@{ setId = "6f1c0b9e2d4a48f7a3b5c6d7e8f90a1b"; outcome = "done"; reason = "hibernation 20261016-091500 started for tier 2" }
    $built = Build-HordeFleetChannelSnapshot -Registry $reg -Never $nv -Records $recs -Busy $true -LastResult $last -SessionsMost 4
    $canon = { param($t) ($t | ConvertFrom-Json | ConvertTo-Json -Compress -Depth 20) }
    Check ((& $canon $built) -ceq (& $canon $fix)) "BUILT FROM THE FIXTURE'S OWN FACTS, THE SNAPSHOT IS THE FIXTURE: every member, in its order, with its words"
    Check ((Test-HordeFleetChannelSnapshot -Text $built).ok) "and it passes the reader"
    $idle = Build-HordeFleetChannelSnapshot -Registry $reg -Never $nv -Records $recs -Busy $false -LastResult $null -SessionsMost 4
    $p = $idle | ConvertFrom-Json
    Check ($null -eq $p.running -and @($p.hibernations).Count -eq 3 -and $p.hibernations[0].id -ceq "20261016-091500" -and $null -eq $p.lastResult -and (Test-HordeFleetChannelSnapshot -Text $idle).ok) "with no run alive, a record left in a phase is a finished hibernation, running is null and lastResult is null, never left out"
    Check (@($p.hibernations[0].sessions | ForEach-Object { $_.state }) -join "," -ceq "still-awake,still-awake,still-awake") "and its sessions that never exited read still-awake in the finished list (asked and parked are not words of it)"
    Check (@($p.hibernations | Where-Object { $_.id -ceq "20261013-120000" }).Count -eq 0) "a record with no phase (made by fleet record) is no hibernation and is not listed"
    Check ($p.tiers.PSObject.Properties.Name -cnotcontains "analyst-service" -and $p.never[0].orc -ceq "analyst-service") "an Orc in never is left out of tiers"
    $many = @(1..14 | ForEach-Object { & $rec ("202610{0:d2}-000000" -f $_) ("2026-10-{0:d2}T00:00:00Z" -f $_) "done" @(, @("K", "orc", "exited")) } | Sort-Object { $_.id } -Descending)
    $p = (Build-HordeFleetChannelSnapshot -Registry $reg -Never $nv -Records $many -Busy $false -LastResult $null -SessionsMost 4) | ConvertFrom-Json
    Check (@($p.hibernations).Count -eq 10 -and $p.hibernations[0].id -ceq "20261014-000000" -and $p.hibernations[9].id -ceq "20261005-000000") "the newest ten hibernations, newest first"
    Check ($p.hibernations[0].sessions[0].state -ceq "asleep") "an exited session of a finished hibernation is asleep"

    $mut = {
        param([scriptblock]$Edit)
        $o = $fix | ConvertFrom-Json
        & $Edit $o
        return (Test-HordeFleetChannelSnapshot -Text ($o | ConvertTo-Json -Compress -Depth 20))
    }
    $refuse = { param([string]$Name, [scriptblock]$Edit, [string]$Like = "*") $r = & $mut $Edit; Check (-not $r.ok -and $r.reason -like $Like) ("the reader refuses " + $Name + " (" + $r.reason + ")") }
    & $refuse "a state of the OTHER list: exited in a finished hibernation" { param($o) $o.hibernations[0].sessions[0].state = "exited" } "*exited*"
    & $refuse "a state of the OTHER list: woken in a running one" { param($o) $o.running.sessions[0].state = "woken" } "*woken*"
    & $refuse "asleep in a running one" { param($o) $o.running.sessions[0].state = "asleep" } "*asleep*"
    & $refuse "asked in a finished one" { param($o) $o.hibernations[0].sessions[0].state = "asked" } "*asked*"
    & $refuse "parked in a finished one" { param($o) $o.hibernations[1].sessions[0].state = "parked" } "*parked*"
    & $refuse "a state nobody lists" { param($o) $o.running.sessions[0].state = "sleeping" } "*sleeping*"
    foreach ($shared in @("still-awake", "failed")) {
        $r = & $mut { param($o) $o.running.sessions[0].state = $shared; $o.hibernations[0].sessions[0].state = $shared }
        Check ($r.ok) ("CONTROL: " + $shared + " is a word of both lists, and is taken in both")
    }
    & $refuse "a member added at the top" { param($o) $o | Add-Member -NotePropertyName "extra" -NotePropertyValue 1 } "*members*"
    foreach ($m in @("v", "version", "tiers", "never", "running", "hibernations", "lastResult")) {
        $mm = $m
        & $refuse ("the member " + $m + " missing") { param($o) $o.PSObject.Properties.Remove($mm) } "*members*"
    }
    & $refuse "a member added to running" { param($o) $o.running | Add-Member -NotePropertyName "x" -NotePropertyValue 1 } "*running*"
    & $refuse "a member missing from a session" { param($o) $o.running.sessions[0].PSObject.Properties.Remove("role") } "*session*"
    & $refuse "a member added to a hibernation" { param($o) $o.hibernations[0] | Add-Member -NotePropertyName "x" -NotePropertyValue 1 } "*hibernation*"
    & $refuse "a member missing from lastResult" { param($o) $o.lastResult.PSObject.Properties.Remove("reason") } "*lastResult*"
    & $refuse "a lastResult outcome of its own" { param($o) $o.lastResult.outcome = "ok" } "*lastResult*"
    & $refuse "a tier of 3" { param($o) $o.tiers."relay-port" = 3 } "*tier*"
    & $refuse "an Orc in both never and tiers" { param($o) $o.tiers | Add-Member -NotePropertyName "analyst-service" -NotePropertyValue 1 } "*both*"
    & $refuse "a running phase of its own" { param($o) $o.running.phase = "sleeping" } "*phase*"
    & $refuse "a hibernation both running and finished" { param($o) $o.hibernations[0].id = $o.running.id } "*both running and finished*"
    & $refuse "hibernations not newest first" { param($o) $t = $o.hibernations[0]; $o.hibernations[0] = $o.hibernations[1]; $o.hibernations[1] = $t } "*newest first*"
    & $refuse "a time that is not UTC to the second" { param($o) $o.running.startedAt = "2026-10-16 09:15" } "*startedAt*"
    & $refuse "a role that is neither orc nor warg" { param($o) $o.running.sessions[0].role = "master" } "*role*"
    & $refuse "more as text" { param($o) $o.hibernations[0].more = "3" } "*more*"
    $dup = $fix.Replace('"version": 7,', '"version": 7, "version": 7,')
    $r = Test-HordeFleetChannelSnapshot -Text $dup
    Check (-not $r.ok -and $r.reason -like "*twice*") ("the reader refuses a member there twice (" + $r.reason + ")")

    Write-Host ""
    Write-Host "--- 6. out, end to end: signed by the founder's passkey, answered in the snapshot he opens ---" -ForegroundColor Cyan
    Reset-Stand; $W = New-World
    $t = Invoke-Tick $W
    $mail = @(Get-NewMail $W)
    Check ($mail.Count -eq 1 -and $mail[0].ok -and $mail[0].kind -ceq "snapshot" -and $null -eq $mail[0].body.lastResult -and $mail[0].body.version -eq 7) ("the first Tick sends the snapshot, lastResult null (" + (Said $t) + ")")
    Check ($mail.Count -eq 1 -and @($mail[0].to).Count -eq 1 -and $mail[0].to[0] -ceq (Get-HordeRelayKeyId -Public $W.phone.agreePublic)) "sealed to the one trusted phone key, and to nothing else"
    Check ((Test-HordeFleetChannelSnapshot -Text ($mail[0].body | ConvertTo-Json -Compress -Depth 20)).ok) "and what the phone opens passes the contract's reader"
    $t = Invoke-Tick $W
    Check (@(Get-NewMail $W).Count -eq 0 -and @($t.lines).Count -eq 0) "nothing changed: nothing sent, nothing said"
    $setId = New-SetId
    $o = Get-Parsed $W "tier"; $o.setId = $setId
    $env1 = New-HordeTestPhoneEnvelope -Phone $W.phone -Kind "tier" -Channel "fleet" -Body ([byte[]]$utf8.GetBytes((Out-Body $o))) -To $W.agree
    [void](Send-ToMachine $W $env1.text)
    $turn = Invoke-Turn $W
    Check ($script:Stand.setTierCalls.Count -eq 1 -and $turn.text -like "*relay-port is now in tier 2*") ("the founder's signed tier request, through the real inbox, changes the tier (" + $turn.text + ")")
    Check ((Test-HordeFleetChannelGlance -Context $W.ctx) -eq $true) "the Glance says yes for a request answered since the last look"
    $t = Invoke-Tick $W
    $mail = @(Get-NewMail $W)
    Check ($mail.Count -eq 1 -and $mail[0].ok -and $mail[0].body.lastResult.setId -ceq $setId -and $mail[0].body.lastResult.outcome -ceq "done" -and $mail[0].body.version -eq 8 -and $mail[0].body.tiers."relay-port" -eq 2) ("THE ANSWER IS IN THE NEXT SNAPSHOT: lastResult names the setId, and the tier and the version have moved (" + (Said $t) + ")")
    Check ((Test-HordeFleetChannelGlance -Context $W.ctx) -eq $false) "and after the Tick the Glance says no"
    [void](Send-HordeRelayItem -Connection $W.conn -Mailbox $W.ctx.mailbox -Text (New-HordeTestPhoneResigned -Phone $W.phone -Envelope $env1) -Key $env1.key)
    $turn = Invoke-Turn $W
    $null = Invoke-Tick $W
    Check ($script:Stand.setTierCalls.Count -eq 1) "the same envelope again does not write again"
    $nobody = New-HordeTestPhone
    $forged = New-HordeTestPhoneEnvelope -Phone $nobody -Kind "tier" -Channel "fleet" -Body ([byte[]]$utf8.GetBytes((Get-BodyFor $W "tier"))) -To $W.agree -From $W.phone.keyId
    [void](Send-ToMachine $W $forged.text)
    $turn = Invoke-Turn $W
    Check ($script:Stand.setTierCalls.Count -eq 1) ("a request forged in the founder's name acts on nothing (" + $turn.text + ")")
    $env2 = New-HordeTestPhoneEnvelope -Phone $W.phone -Kind "restart" -Channel "fleet" -Body ([byte[]]$utf8.GetBytes((Get-BodyFor $W "wake"))) -To $W.agree
    [void](Send-ToMachine $W $env2.text)
    $turn = Invoke-Turn $W
    Check ($script:Stand.startCalls.Count -eq 0 -and $turn.text -like "*restart*") ("a kind the channel does not take is refused at the gate (" + $turn.text + ")")
    $env3 = New-HordeTestPhoneEnvelope -Phone $W.phone -Kind "hibernate" -Channel "fleet" -Body ([byte[]]$utf8.GetBytes((Get-BodyFor $W "hibernate"))) -To $W.agree
    [void](Send-ToMachine $W $env3.text)
    $turn = Invoke-Turn $W
    Check ($script:Stand.startCalls.Count -eq 0 -and $script:Stand.version -eq 8) ("a signed hibernate drawn from version 7, once the registry is at 8, starts nothing (" + $turn.text + ")")
    $null = Invoke-Tick $W
    $mail = @(Get-NewMail $W)
    Check ($mail.Count -eq 1 -and $mail[0].body.lastResult.outcome -ceq "retry") "a hibernate drawn from version 7 once the registry is at 8 shows retry in the next snapshot, and started nothing"
    $phone2 = New-HordeTestPhone
    [void](Add-HordeTestPhonePairing -HordeHome $W.home -Phone $phone2)
    Add-PhoneKey -HordeHome $W.home -Phone $phone2
    $t = Invoke-Tick $W
    $mail2 = @(Get-NewMail $W -Phone $phone2 -All)
    Check ($mail2.Count -ge 1 -and $mail2[-1].ok -and $mail2[-1].body.version -eq 8) ("a phone key trusted since is sent the snapshot (" + (Said $t) + ")")
    $K = New-World -Settings '{"keepEnvelopes": 2, "sessionsMost": 12, "lookMs": 0}'
    foreach ($i in 1..4) { $script:Stand.version = 100 + $i; $null = Invoke-Tick $K }
    $held = @(Get-NewMail $K -All)
    Check ($held.Count -eq 2 -and $held[-1].body.version -eq 104) ("with keepEnvelopes 2 the phone's mailbox holds this machine's last two snapshots (" + $held.Count + ")")
    Reset-Stand
    $I = New-World -Settings '{"keepEnvelopes": 5, "sessionsMost": 12, "lookMs": 600000}'
    $null = Invoke-Tick $I
    $reads = $script:Stand.registryReads
    $t = Invoke-Tick $I
    Check ($script:Stand.registryReads -eq $reads -and @($t.lines).Count -eq 0) "IDLE: inside lookMs, with no request answered, a Tick reads nothing"
    $null = Accept $I "tier" (Get-BodyFor $I "tier")
    $null = Invoke-Tick $I
    Check ($script:Stand.registryReads -gt $reads) "and a request answered makes the next Tick look at once"
    Reset-Stand; $W = New-World
    $script:Stand.registryState = "unknown"
    $t = Invoke-Tick $W
    Check ($t.failed -and (Said $t) -like "*Orc registry cannot be read*" -and @(Get-NewMail $W).Count -eq 0) ("a registry that cannot be read sends nothing, and says why (" + (Said $t) + ")")

    Write-Host ""
    Write-Host "--- 7. what runs: the lock, the process this channel started, the records that count ---" -ForegroundColor Cyan
    Reset-Stand; $W = $W0
    $dir = Get-HordeFleetHibernationsDir -HordeHome $W.home
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $start = Get-HordeFleetProcessStart -ProcessId $PID
    $seams = @{ ProcessStart = { param($p) Get-HordeFleetProcessStart -ProcessId $p } }
    $W.ctx.state["fleet.seams"] = $seams
    $none = Get-HordeFleetChannelBusyReal -Context $W.ctx -HordeHome $W.home -Children @()
    Check ($none.state -ceq "known" -and -not $none.value.hibernating -and @($none.value.waking).Count -eq 0) "with no lock and no child, nothing runs"
    [System.IO.File]::WriteAllText((Join-Path $dir "hibernating.lock"), ("pid " + $PID + " start " + $start + " at 2026-10-16T09:15:00Z`n"))
    $held = Get-HordeFleetChannelBusyReal -Context $W.ctx -HordeHome $W.home -Children @()
    Check ($held.value.hibernating) "a hibernating.lock whose owner runs is a hibernation running"
    [System.IO.File]::WriteAllText((Join-Path $dir "hibernating.lock"), "pid 1999999 start 1 at 2026-10-16T09:15:00Z`n")
    $stale = Get-HordeFleetChannelBusyReal -Context $W.ctx -HordeHome $W.home -Children @()
    Check (-not $stale.value.hibernating) "a lock whose owner is gone is not a run"
    Remove-Item -LiteralPath (Join-Path $dir "hibernating.lock") -Force
    $child = [pscustomobject]@{ kind = "hibernate"; id = ""; pid = [long]$PID; start = "" + $start }
    $kid = Get-HordeFleetChannelBusyReal -Context $W.ctx -HordeHome $W.home -Children @($child)
    Check ($kid.value.hibernating) "a process this channel started and that still runs is a run, before it has taken the lock"
    $gone = [pscustomobject]@{ kind = "hibernate"; id = ""; pid = [long]$PID; start = "1" }
    $reused = Get-HordeFleetChannelBusyReal -Context $W.ctx -HordeHome $W.home -Children @($gone)
    Check (-not $reused.value.hibernating) "a pid reused by another process (another start time) is not the child"
    $wk = [pscustomobject]@{ kind = "wake"; id = "20261015-221030"; pid = [long]$PID; start = "" + $start }
    $w2 = Get-HordeFleetChannelBusyReal -Context $W.ctx -HordeHome $W.home -Children @($wk)
    Check (-not $w2.value.hibernating -and @($w2.value.waking) -ccontains "20261015-221030") "a wake this channel started is a wake of that hibernation, not a hibernation"
    # The records that count, written by the shipped writer.
    $mkrec = {
        param($id, $phase)
        $r = [ordered]@{ schemaVersion = 1; id = $id; createdAt = ($id.Substring(0, 4) + "-" + $id.Substring(4, 2) + "-" + $id.Substring(6, 2) + "T" + $id.Substring(9, 2) + ":" + $id.Substring(11, 2) + ":" + $id.Substring(13, 2) + "Z"); agent = "stand-in"; host = "stand-in"
            selection = [pscustomobject]@{ kind = "orcs"; labels = @("K"); exclude = @() } }
        if ($phase -ne "") { $r["phase"] = $phase }
        $r["sessions"] = @([pscustomobject]@{ sessionId = "11111111-0000-4000-8000-000000000001"; label = "K"; role = "orc"; cwd = "C:\x"; state = "exited"; history = @([pscustomobject]@{ state = "recorded"; at = "2026-10-16T09:15:00Z" }) })
        $d = Join-Path $dir $id
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        [void](Write-HordeFleetRecord -Dir $d -Record ([pscustomobject]$r))
    }
    & $mkrec "20261014-183005" "done"; & $mkrec "20261015-221030" "done"; & $mkrec "20261016-091500" "parking"; & $mkrec "20261016-100000" ""
    $rr = Get-HordeFleetChannelRecordsReal -HordeHome $W.home
    Check ($rr.state -ceq "known" -and (@($rr.value.records | ForEach-Object { $_.id }) -join ",") -ceq "20261016-091500,20261015-221030,20261014-183005") ("the records read are those with a phase, newest first (" + (@($rr.value.records | ForEach-Object { $_.id }) -join ",") + ")")
    New-Item -ItemType Directory -Path (Join-Path $dir "20261013-000000") -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path (Join-Path $dir "20261013-000000") "record.json"), "{ not json")
    $rr = Get-HordeFleetChannelRecordsReal -HordeHome $W.home
    Check ($rr.state -ceq "known" -and @($rr.value.lines).Count -eq 1 -and $rr.value.lines[0] -like "*20261013-000000*" -and @($rr.value.records).Count -eq 3) "a record that cannot be read is said and passed over; the others are still shown"
    $bad = Start-HordeFleetChannelCommand -Words @("wake", "2026; calc")
    Check ($bad.state -ceq "unknown" -and $bad.reason -like "*plain word*") "the real start refuses a word that is not plain, so nothing a phone sent reaches a command line unchecked"

    Write-Host ""
    Write-Host "--- 8. the real registry: the channel's reader and tier write against orcs/Registry.ps1 ---" -ForegroundColor Cyan
    $R = New-World
    $R.ctx.state.Remove("fleet.seams")
    $lanes = Join-Path $R.home "progress\lanes"
    foreach ($pair in @(@("sleeping-sessions", "K"), @("relay-port", "R"), @("thrall-lane", "M"))) {
        New-Item -ItemType Directory -Path (Join-Path $lanes $pair[0]) -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path (Join-Path $lanes $pair[0]) "status.txt"), ("horde-orc-status 1`norc: " + $pair[1] + "`nlane: " + $pair[0] + "`ndoing: testing`nfinished: nothing yet`nblocked: no`n"), $utf8)
    }
    $env:HORDE_HOME = $R.home
    $reg0 = Get-HordeFleetChannelRegistryReal -HordeHome $R.home
    Check ($reg0.state -ceq "known" -and @($reg0.value.orcs | ForEach-Object { $_.id }) -join "," -ceq "relay-port,sleeping-sessions" -and @($reg0.value.orcs | Where-Object { $null -ne $_.tier }).Count -eq 0) ("the real reader lists the lanes that are Orcs, not the master's, with no tier until set (" + $(if ($reg0.state -ceq "known") { @($reg0.value.orcs | ForEach-Object { $_.id }) -join "," } else { $reg0.reason }) + ")")
    $nv0 = Get-HordeFleetChannelNeverReal -HordeHome $R.home
    Check ($nv0.state -ceq "known" -and (@($nv0.value | ForEach-Object { $_.orc }) -join ",") -ceq "thrall-lane,analyst-service") ("the never list names the master's lane and the analyst service (" + (@($nv0.value | ForEach-Object { $_.orc }) -join ",") + ")")
    $set0 = Set-HordeFleetChannelTierReal -HordeHome $R.home -Id "relay-port" -Tier 2 -Version ([long]$reg0.value.version)
    Check ($set0.outcome -ceq "done") ("the real tier write puts relay-port in tier 2 (" + $set0.outcome + ": " + $set0.reason + ")")
    $reg1 = Get-HordeFleetChannelRegistryReal -HordeHome $R.home
    Check ($reg1.state -ceq "known" -and @($reg1.value.orcs | Where-Object { $_.id -ceq "relay-port" })[0].tier -eq 2 -and $reg1.value.version -gt $reg0.value.version) "and the reader sees tier 2 and a later version"
    $stale0 = Set-HordeFleetChannelTierReal -HordeHome $R.home -Id "relay-port" -Tier 1 -Version ([long]$reg0.value.version)
    Check ($stale0.outcome -ceq "stale") ("a write drawn from the old version is stale (" + $stale0.outcome + ")")
    $o = [ordered]@{ v = 1; setId = (New-SetId); machine = $R.id.sign.keyId; orc = "sleeping-sessions"; tier = 2; version = [long]$reg1.value.version }
    $a = Invoke-HordeFleetChannelAccept -Context $R.ctx -Item (New-Item2 -Kind "tier" -Body (Out-Body ([pscustomobject]$o)))
    $reg2 = Get-HordeFleetChannelRegistryReal -HordeHome $R.home
    Check ($a.outcome -ceq "done" -and @($reg2.value.orcs | Where-Object { $_.id -ceq "sleeping-sessions" })[0].tier -eq 2) ("an Accept through the real seams writes the real registry (" + $a.reason + ")")
    $t = Invoke-Tick $R
    $mail = @(Get-NewMail $R)
    Check ($mail.Count -eq 1 -and $mail[0].ok -and $mail[0].body.tiers."sleeping-sessions" -eq 2 -and $mail[0].body.tiers."relay-port" -eq 2 -and $mail[0].body.never[1].orc -ceq "analyst-service" -and $mail[0].body.lastResult.outcome -ceq "done") ("and the snapshot made from the real registry carries it (" + (Said $t) + ")")
    Check ((Test-HordeFleetChannelSnapshot -Text ($mail[0].body | ConvertTo-Json -Compress -Depth 20)).ok) "and passes the contract's reader"
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
    foreach ($h in $script:homes) { if ((Split-Path -Leaf $h) -match '^horde-relay-fleet-[0-9a-f]{32}$') { Remove-Item -LiteralPath $h -Recurse -Force -ErrorAction SilentlyContinue } }
    Check (@($script:homes | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 0 -and -not (Test-Path -LiteralPath $fleetPin.path)) "every folder the suite made is gone"
}

Complete-HordeSuite -Success "the fleet channel takes exactly the contract's three bodies from the founder's passkey or session, acts on each setId once, answers every request in the next snapshot, and sends exactly the contract's snapshot shape"
