# DOES THE FOUNDER'S PHONE SEE THE OPEN QUESTIONS, AND DOES EACH OF HIS SIGNED ANSWERS LAND IN THE
# DECISIONS LIST EXACTLY ONCE - AND NOTHING ELSE LAND AT ALL?
#
# The relay channels (relay design 2026-10-09, PR plan item 6): channels/Port.ps1, the decisions channel
# (channels/decisions), the trust channel (channels/trust), relay/Journal.ps1's done marks and resumption,
# relay/Trust.ps1's phone keys, and cli/RelayRun.ps1's loop - over relays/local, in this process, with a
# phone held in memory (test/lib/RelayPhone.ps1). It attacks:
#   - TRUST: only a trusted founder passkey answers or vouches; a pending, revoked, unknown or forged
#     sender, a machine key, an envelope for another machine, another channel or kind - all refused,
#     and none of them journaled;
#   - EXACTLY ONCE: a repeated put, a re-signed copy, a resent answer, a crash between the journal and the
#     list, a list that could not be written, and a relay that reorders, repeats, serves stale items,
#     conflicts and salts its batches with garbage - each answer is one record;
#   - THE FIRST ANSWER WINS: other words under one answerId are refused for good;
#   - THE SNAPSHOT: sealed to the trusted phone keys only, sent only when it changed, never carrying what
#     looks like a secret;
#   - THE RUNNER: turns, stops cleanly, backs off with jitter, refuses refused settings, releases
#     retired keys.
# The end to end, with a phone made by WebCrypto and the real horde command, is
# test/test-relay-phone-e2e.ps1.
#
# EVERY HORDE HOME IS A FOLDER OF THE SUITE'S OWN under %TEMP% (CONTRIBUTING 9), never the real one:
# HORDE_HOME is pointed at the home of each world for the decisions module's settings, and put back.
# Every key is made with the software provider, named by its home's install id, removed in the finally
# block, and checked gone. Off Windows there is no key store: the suite says so and exits 3.

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
# The doorbell for the founder's answers: what it says of a phone answer's signer is checked here, where
# the answer, its journal record and the trust store are all real.
. (Join-Path $root "decisions\Notify.ps1")
. (Join-Path $root "test\lib\RelayPhone.ps1")
. (Join-Path $root "test\lib\HostileRelay.ps1")
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

# THE DECISIONS MODULE UNDER POWERSHELL 7. Horde's JSON reads differ between the runtimes (issue #173),
# and on origin/main the decisions list cannot add a question under PowerShell 7 at all (measured
# 2026-10-09: test/test-decisions-threads.ps1 fails there the same way). The channels' own code runs
# under both; what needs the decisions list to work is skipped under a runtime where it does not, said
# so, and the suite then exits 3, a partial run - never 0.
$probeStore = Join-Path $env:TEMP ("horde-relay-channels-probe-" + [guid]::NewGuid().ToString("N"))
$probe = $null
try { $probe = Invoke-HordeDecision -Operation "add" -Root $probeStore -Request @{ id = [guid]::NewGuid().ToString("N"); actor = "warchief"; question = @{ title = "Can this runtime add a question here?"; kind = "yes-no"; whatItIs = "A probe."; group = "probe"; askedBy = "suite" } } } catch { $probe = $null }
$script:canDecide = ($null -ne $probe -and $probe.state -ceq "known" -and $probe.value.outcome -ceq "done")
if ((Split-Path -Leaf $probeStore) -match '^horde-relay-channels-probe-[0-9a-f]{32}$' -and (Test-Path -LiteralPath $probeStore)) { Remove-Item -LiteralPath $probeStore -Recurse -Force }
$script:partial = $false
if (-not $script:canDecide) { Write-Host ("  [SKIP] the decisions list cannot add a question under this runtime (issue #173): every check that needs it is skipped, and the suite exits 3") -ForegroundColor Yellow; $script:partial = $true }

function New-TestHome {
    param([string]$Horde = "work")
    $h = Join-Path $env:TEMP ("horde-relay-channels-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path (Join-Path $h "settings") -Force | Out-Null
    [void]$script:homes.Add($h)
    [System.IO.File]::WriteAllText((Join-Path $h "settings\relay.json"), ('{"schemaVersion": 1, "settings": {"horde": "' + $Horde + '"}}'), $utf8)
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
    # A machine (home, identity, decisions store with one open question), a phone paired and confirmed
    # and its identity key in the trust store, a local relay, and a run context over it.
    param([switch]$NoPhoneKey, $Connection = $null)
    $h = New-TestHome
    $env:HORDE_HOME = $h
    $id = New-HordeRelayMachineIdentity -HordeHome $h -Provider "software"
    if ($id.state -cne "known") { throw ("no identity: " + $id.reason) }
    $phone = New-HordeTestPhone
    [void](Add-HordeTestPhonePairing -HordeHome $h -Phone $phone)
    if (-not $NoPhoneKey) {
        $v = New-HordeTestPhoneVouch -Phone $phone -Horde "work"
        $k = Add-HordeRelayPhoneKey -HordeHome $h -AgreePublic $phone.agreePublic -By $phone.keyId -AuthenticatorData $v.authenticatorData -ClientDataJson $v.clientDataJson -Signature $v.signature
        if ($k.state -cne "known") { throw ("no phone key: " + $k.reason) }
    }
    $relayDir = Join-Path $h "relay-mailboxes"
    if ($null -eq $Connection) {
        $c = Connect-HordeRelay -Name "local" -Options @{ root = $relayDir }
        if ($c.state -cne "known") { throw ("no relay: " + $c.reason) }
        $Connection = $c.value
    }
    $ctx = New-HordeRelayRunContext -HordeHome $h -Connection $Connection
    if ($ctx.state -cne "known") { throw ("no context: " + $ctx.reason) }
    $store = Join-Path $h "store\decisions"
    if ($script:canDecide) {
    $q = Invoke-HordeDecision -Operation "add" -Root $store -Request @{ id = (New-Id); actor = "warchief"; question = @{ title = "Should the closing sound play when the assistant closes?"; kind = "yes-no"; whatItIs = "The app has no closing sound today."; group = "voice"; askedBy = "orc-b" } }
    if ($q.state -cne "known" -or $q.value.outcome -cne "done") { throw "the question was not added" }
    }
    $w = [pscustomobject]@{ home = $h; id = $id.value; phone = $phone; conn = $Connection; ctx = $ctx.value; store = $store; agree = @(, ([byte[]]$id.value.agree.public)) }
    [void]$script:worlds.Add($w)
    # The first look, so that an answer has a snapshot of this machine to name (review of 48bc492,
    # finding 2: an answer is bound to the machine and the snapshot it was made from).
    if (-not $NoPhoneKey -and $script:canDecide) { $null = Invoke-Tick $w }
    return $w
}
function Get-SentKey {
    # The replay key of the newest snapshot envelope this machine recorded as sent: what an answer made
    # from it names. A key no machine sent when there is none.
    param($World)
    $dir = Join-Path $World.home ("relay\journal\out\s-" + $World.id.sign.keyId + "\c-decisions")
    if (-not (Test-Path -LiteralPath $dir)) { return (("0" * 32) + "/decisions/1/" + ("0" * 24)) }
    $newest = @(Get-ChildItem -LiteralPath $dir -Filter "*.rec" | Sort-Object Name | Select-Object -Last 1)
    if ($newest.Count -eq 0) { return (("0" * 32) + "/decisions/1/" + ("0" * 24)) }
    return [regex]::Match([System.IO.File]::ReadAllText($newest[0].FullName), '"key":"([^"]+)"').Groups[1].Value
}
function New-Id { return [guid]::NewGuid().ToString("N") }
function Use-World { param($World) $env:HORDE_HOME = $World.home }
function Send-ToMachine {
    # Put an envelope text into the machine's mailbox, under its replay key unless -Key says otherwise.
    param($World, [string]$Text, [string]$Key = "-")
    if ($Key -ceq "-") { $Key = (Get-HordeRelayReplayKey -Header (Read-HordeRelayEnvelope -Text $Text).value.header) }
    return (Send-HordeRelayItem -Connection $World.conn -Mailbox $World.ctx.mailbox -Text $Text -Key $Key)
}
function Invoke-Turn {
    # One inbound turn: the mailbox read and journaled, then every unfinished record handed over.
    # { inbox; unfinished; lines } - lines everything said, for a check to search.
    param($World)
    Use-World $World
    $in = Receive-HordeRelayInbox -Context $World.ctx -TimeoutMs 0
    $un = Invoke-HordeRelayUnfinished -Context $World.ctx
    $lines = New-Object System.Collections.ArrayList
    if ($in.state -ceq "known") { foreach ($l in @($in.value.refused)) { [void]$lines.Add("refused " + $l) }; foreach ($l in @($in.value.held)) { [void]$lines.Add("held " + $l) }; foreach ($l in @($in.value.missing)) { [void]$lines.Add("missing " + $l) }; foreach ($l in @($in.value.anomalies)) { [void]$lines.Add("relay " + $l) } }
    else { [void]$lines.Add("inbox " + $in.state + ": " + $in.reason) }
    foreach ($l in @(Get-HordeRelayRunLines -Report $un.value)) { [void]$lines.Add($l) }
    return [pscustomobject]@{ inbox = $in; unfinished = $un; lines = @($lines.ToArray()); text = (@($lines.ToArray()) -join " | ") }
}
function Get-Said {
    # The message-said records of a store, parsed, in order.
    param([string]$Store)
    if (-not (Test-Path -LiteralPath $Store)) { return @() }
    return @(Get-ChildItem -LiteralPath $Store -Filter "*.json" | Sort-Object Name | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName, $utf8) | ConvertFrom-Json } | Where-Object { $_.kind -ceq "message-said" })
}
function Get-RecordFile {
    # The journal record file of one received envelope.
    param($World, $Header)
    return (Join-Path $World.home ("relay\journal\in\s-" + $Header.from + "\c-" + $Header.channel + "\" + ([long]$Header.seq).ToString("D16") + ".rec"))
}
function Get-FileHash256 { param([string]$Path) return (ConvertTo-HordeRelayHex -Bytes (Get-HordeRelaySha256 -Bytes ([System.IO.File]::ReadAllBytes($Path)))) }
function Get-PhoneMail {
    # The texts in the horde's phone mailbox.
    param($World)
    $r = Receive-HordeRelayItems -Connection $World.conn -Mailbox "work/phone" -Since 0
    if ($r.state -cne "known") { return @() }
    return @($r.value.items | ForEach-Object { $_.text })
}
function Get-Answer {
    # An answer envelope from the world's phone, made from the machine's newest snapshot unless -Machine
    # or -Snapshot say otherwise.
    param($World, [string]$AnswerId = "", [string]$Text = "Yes, play it.", [int]$Number = 1, $Phone = $null, [object[]]$To = $null, [string]$Machine = "", [string]$Snapshot = "", [string]$Part = "")
    if ($null -eq $Phone) { $Phone = $World.phone }
    if ($null -eq $To) { $To = $World.agree }
    if ($Machine -ceq "") { $Machine = $World.id.sign.keyId }
    if ($Snapshot -ceq "") { $Snapshot = Get-SentKey -World $World }
    return (New-HordeTestPhoneEnvelope -Phone $Phone -Kind "answer" -Channel "decisions" -Body (New-HordeTestPhoneAnswerBody -AnswerId $AnswerId -Text $Text -Number $Number -Machine $Machine -Snapshot $Snapshot -Part $Part) -To $To)
}
function Get-RawAnswer {
    # An answer envelope whose body is exactly -Json, for a body no honest phone makes. {machine} and
    # {snapshot} in it are this world's machine and its newest snapshot.
    param($World, [string]$Json)
    $body = $Json.Replace("{machine}", $World.id.sign.keyId).Replace("{snapshot}", (Get-SentKey -World $World))
    return (New-HordeTestPhoneEnvelope -Phone $World.phone -Kind "answer" -Channel "decisions" -Body ($utf8.GetBytes($body)) -To $World.agree)
}
function Has { param($Turn, [string]$Text) return [bool]($Turn.text.Contains($Text)) }
function Invoke-Tick {
    # The channels' ticks of one world, as lines.
    param($World)
    $t = Invoke-HordeRelayChannelTicks -Context $World.ctx
    if ($null -ne $t -and $t -isnot [string] -and $null -ne $t.PSObject.Properties["lines"]) { return @($t.lines) }
    return @($t)
}
function Get-Member2 { param($Object, [string]$Name) if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) { return $null }; return $Object.$Name }

try {
    Write-Host ""
    Write-Host "--- phone keys: vouched for by a trusted passkey, and trusted only while it is ---" -ForegroundColor Cyan
    $h = New-TestHome
    $env:HORDE_HOME = $h
    [void](New-HordeRelayMachineIdentity -HordeHome $h -Provider "software")
    $p = New-HordeTestPhone
    [void](Add-HordeTestPhonePairing -HordeHome $h -Phone $p -NoConfirm)
    $v = New-HordeTestPhoneVouch -Phone $p -Horde "work"
    $a = Add-HordeRelayPhoneKey -HordeHome $h -AgreePublic $p.agreePublic -By $p.keyId -AuthenticatorData $v.authenticatorData -ClientDataJson $v.clientDataJson -Signature $v.signature
    Check ($a.state -ceq "unknown" -and $a.reason.Contains("not a trusted device")) ("a pending passkey cannot vouch for a phone key (" + $a.reason + ")")
    $p2 = New-HordeTestPhone
    [void](Add-HordeTestPhonePairing -HordeHome $h -Phone $p2)
    $v2 = New-HordeTestPhoneVouch -Phone $p2 -Horde "work"
    $other = New-HordeTestPhoneVouch -Phone $p2 -Horde "personal"
    $x = Add-HordeRelayPhoneKey -HordeHome $h -AgreePublic $p2.agreePublic -By $p2.keyId -AuthenticatorData $other.authenticatorData -ClientDataJson $other.clientDataJson -Signature $other.signature
    Check ($x.state -ceq "unknown" -and $x.reason.Contains("challenge")) ("a vouch made for another horde is refused (" + $x.reason + ")")
    $byOther = New-HordeTestPhoneAssertion -Phone $p -Challenge (Get-HordeRelayPhoneKeyChallenge -Horde "work" -AgreePublic (ConvertTo-HordeRelayBase64Url -Bytes $p2.agreePublic))
    $y = Add-HordeRelayPhoneKey -HordeHome $h -AgreePublic $p2.agreePublic -By $p2.keyId -AuthenticatorData $byOther.authenticatorData -ClientDataJson $byOther.clientDataJson -Signature $byOther.signature
    Check ($y.state -ceq "unknown" -and $y.reason.Contains("does not verify")) ("a vouch signed by another passkey than the one named is refused (" + $y.reason + ")")
    $z = Add-HordeRelayPhoneKey -HordeHome $h -AgreePublic $p2.agreePublic -By $p2.keyId -AuthenticatorData $v2.authenticatorData -ClientDataJson $v2.clientDataJson -Signature $v2.signature
    Check ($z.state -ceq "known" -and -not $z.value.duplicate -and $z.value.record.state -ceq "trusted" -and $z.value.record.agreeKeyId -ceq (Get-HordeRelayKeyId -Public $p2.agreePublic)) "a trusted passkey's vouch adds the phone key, trusted"
    $z2 = Add-HordeRelayPhoneKey -HordeHome $h -AgreePublic $p2.agreePublic -By $p2.keyId -AuthenticatorData $v2.authenticatorData -ClientDataJson $v2.clientDataJson -Signature $v2.signature
    Check ($z2.state -ceq "known" -and $z2.value.duplicate) "the same key again is a duplicate, and the first vouch stands"
    $f = Find-HordeRelayPhoneKeys -HordeHome $h
    Check ($f.state -ceq "known" -and @($f.value).Count -eq 1 -and (Get-HordeRelayKeyId -Public $f.value[0].public) -ceq $z.value.record.agreeKeyId) "Find-HordeRelayPhoneKeys hands out the trusted key's point"
    [void](Revoke-HordeRelayTrust -HordeHome $h -Subject "device" -Id $p2.deviceId -Reason "phone lost")
    $f2 = Find-HordeRelayPhoneKeys -HordeHome $h
    $t2 = Get-HordeRelayTrust -HordeHome $h
    Check ($f2.state -ceq "known" -and @($f2.value).Count -eq 0 -and $t2.value.phones[0].state -ceq "untrusted" -and $t2.value.phones[0].why.Contains("revoked")) "revoking the passkey that vouched stops the phone key at once: nothing is sealed to it"
    $pf = @(Get-ChildItem -LiteralPath (Join-Path $h "relay\trust\phones") -Filter ($z.value.record.agreeKeyId + "-*.json") | ForEach-Object { $_.FullName })[0]
    $orig = [System.IO.File]::ReadAllText($pf)
    [System.IO.File]::WriteAllText($pf, $orig.Replace('"horde":"work"', '"horde":"evil"'), [System.Text.Encoding]::ASCII)
    $t3 = Get-HordeRelayTrust -HordeHome $h
    Check ($t3.state -ceq "unknown" -and $t3.reason.Contains("does not verify")) ("a phone key record changed on disk no longer verifies, and the whole store is unknown (" + $t3.reason + ")")
    [System.IO.File]::WriteAllText($pf, $orig, [System.Text.Encoding]::ASCII)
    Check ((Get-HordeRelayTrust -HordeHome $h).state -ceq "known") "CONTROL: put back, the store reads"
    # A NEW VOUCH FOR A KEY WHOSE VOUCHER WAS REVOKED (review of 48bc492, finding 7): the founder replaces
    # the passkey on his phone and vouches for the same phone key again. It must be trusted again - and
    # never answered "already in the store" while nothing seals to it.
    $again = Add-HordeRelayPhoneKey -HordeHome $h -AgreePublic $p2.agreePublic -By $p2.keyId -AuthenticatorData $v2.authenticatorData -ClientDataJson $v2.clientDataJson -Signature $v2.signature
    Check ($again.state -ceq "unknown" -and $again.reason.Contains("not a trusted device")) ("the revoked passkey's vouch, sent again, is refused - not answered as already there (" + $again.state + ": " + $again.reason + ")")
    $p3 = New-HordeTestPhone
    [void](Add-HordeTestPhonePairing -HordeHome $h -Phone $p3)
    $v3 = New-HordeTestPhoneAssertion -Phone $p3 -Challenge (Get-HordeRelayPhoneKeyChallenge -Horde "work" -AgreePublic (ConvertTo-HordeRelayBase64Url -Bytes $p2.agreePublic))
    $re = Add-HordeRelayPhoneKey -HordeHome $h -AgreePublic $p2.agreePublic -By $p3.keyId -AuthenticatorData $v3.authenticatorData -ClientDataJson $v3.clientDataJson -Signature $v3.signature
    $f3 = Find-HordeRelayPhoneKeys -HordeHome $h
    Check ($re.state -ceq "known" -and -not $re.value.duplicate -and $re.value.record.state -ceq "trusted" -and @($f3.value).Count -eq 1 -and $f3.value[0].by -ceq $p3.keyId) ("a valid vouch by a trusted passkey trusts the key again, vouched for by the new passkey (" + $(if ($re.state -ceq "known") { $re.value.record.state } else { $re.reason }) + ")")
    $re2 = Add-HordeRelayPhoneKey -HordeHome $h -AgreePublic $p2.agreePublic -By $p3.keyId -AuthenticatorData $v3.authenticatorData -ClientDataJson $v3.clientDataJson -Signature $v3.signature
    Check ($re2.state -ceq "known" -and $re2.value.duplicate -and $re2.value.record.state -ceq "trusted") "the same vouch again is a duplicate of a key that IS trusted"
    # THE HORDE ON READ (finding 8): a key vouched for in one horde is not sealed to once the home belongs
    # to another.
    [System.IO.File]::WriteAllText((Join-Path $h "settings\relay.json"), '{"schemaVersion": 1, "settings": {"horde": "personal"}}', $utf8)
    $f4 = Find-HordeRelayPhoneKeys -HordeHome $h
    $t4 = Get-HordeRelayTrust -HordeHome $h
    [System.IO.File]::WriteAllText((Join-Path $h "settings\relay.json"), '{"schemaVersion": 1, "settings": {"horde": "work"}}', $utf8)
    Check ($f4.state -ceq "known" -and @($f4.value).Count -eq 0 -and $t4.state -ceq "known" -and @($t4.value.phones | Where-Object { $_.state -ceq "trusted" }).Count -eq 0 -and @($t4.value.phones | Where-Object { "$($_.why)".Contains("horde") }).Count -ge 1) "with the home's horde renamed, a key vouched for in the old horde is untrusted, and says why"
    Check (@((Find-HordeRelayPhoneKeys -HordeHome $h).value).Count -eq 1) "CONTROL: named back, it is trusted again"

    Write-Host ""
    Write-Host "--- the journal: an unfinished record is resumable, a done mark finishes it, evidence is its hash ---" -ForegroundColor Cyan
    $W = New-World
    $e = Get-Answer $W
    $read = (Read-HordeRelayEnvelope -Text $e.text).value
    $senders = (Find-HordeRelayTrustedSenders -HordeHome $W.home).value
    $reg = Register-HordeRelayJournalReceived -Envelope $read -Senders $senders -RecipientKeyIds @($W.ctx.openingKeys.Keys) -Channel "decisions" -Kind "answer" -HordeHome $W.home
    Check ($reg.state -ceq "known" -and $reg.value.fresh) "CONTROL: the envelope is journaled, as a run killed before opening it would leave it"
    $u = Get-HordeRelayJournalUnfinished -Channel "decisions" -HordeHome $W.home
    $rec = Get-RecordFile -World $W -Header $e.header
    Check ($u.state -ceq "known" -and @($u.value).Count -eq 1 -and $u.value[0].key -ceq $e.key -and $u.value[0].text -ceq $e.text -and $u.value[0].kind -ceq "answer") "it is listed unfinished, with its envelope exactly as recorded"
    Check ($u.value[0].verdict.state -ceq "known" -and $u.value[0].verdict.value.fresh -eq $true -and $u.value[0].verdict.value.resumed -eq $true -and $u.value[0].verdict.value.key -ceq $e.key) "with a verdict Unprotect takes: this envelope's key, fresh, resumed"
    Check ($u.value[0].evidence -ceq (Get-FileHash256 $rec) -and $u.value[0].evidence -cmatch '\A[0-9a-f]{64}\z') "its evidence is the SHA-256 of the whole record file"
    $ev = Get-HordeRelayJournalEvidence -From $e.header.from -Channel "decisions" -Seq $e.header.seq -HordeHome $W.home
    Check ($ev.state -ceq "known" -and $ev.value -ceq $u.value[0].evidence) "Get-HordeRelayJournalEvidence says the same"
    Check ((Get-HordeRelayJournalEvidence -From $e.header.from -Channel "decisions" -Seq 99 -HordeHome $W.home).state -ceq "absent") "and there is no evidence of a record that is not there"
    $again = Register-HordeRelayJournalReceived -Envelope $read -Senders $senders -RecipientKeyIds @($W.ctx.openingKeys.Keys) -Channel "decisions" -Kind "answer" -HordeHome $W.home
    Check ($again.state -ceq "known" -and -not $again.value.fresh -and $again.value.why.Contains("replay")) "CONTROL: the journal still refuses it as a replay - only resumption opens it again"
    $mk = Complete-HordeRelayJournalReceived -From $e.header.from -Channel "decisions" -Seq $e.header.seq -HordeHome $W.home
    $mk2 = Complete-HordeRelayJournalReceived -From $e.header.from -Channel "decisions" -Seq $e.header.seq -HordeHome $W.home
    Check ($mk.state -ceq "known" -and -not $mk.value.already -and $mk2.state -ceq "known" -and $mk2.value.already) "a done mark is written once, and again is already"
    Check (@((Get-HordeRelayJournalUnfinished -Channel "decisions" -HordeHome $W.home).value).Count -eq 0) "a done record is not listed"
    # A throw is turned into an answer here, so a journal that throws instead of refusing FAILS this
    # check by name rather than ending the suite (tools/Mutate.ps1 counts only a failed check).
    $none = $null
    try { $none = Complete-HordeRelayJournalReceived -From $e.header.from -Channel "decisions" -Seq 7 -HordeHome $W.home } catch { $none = [pscustomobject]@{ state = "threw"; reason = $_.Exception.Message } }
    Check ($none.state -ceq "unknown" -and $none.reason.Contains("beside its record")) "no done mark is written for a record that is not there"
    $stray = Join-Path (Split-Path -Parent $rec) ("0000000000000009.done")
    [System.IO.File]::WriteAllText($stray, '{"v":1}', [System.Text.Encoding]::ASCII)
    $bad = Get-HordeRelayJournalUnfinished -Channel "decisions" -HordeHome $W.home
    Check ($bad.state -ceq "unknown" -and $bad.reason.Contains("never recorded")) ("a done mark beside nothing is damage, and nothing is resumed (" + $bad.reason + ")")
    Remove-Item -LiteralPath $stray
    New-Item -ItemType Directory -Path (Join-Path $W.home "relay\journal\in\stray") | Out-Null
    $bad2 = Get-HordeRelayJournalUnfinished -Channel "decisions" -HordeHome $W.home
    Check ($bad2.state -ceq "unknown" -and $bad2.reason.Contains("never makes")) "a folder the journal never makes among the received streams is damage"
    Remove-Item -LiteralPath (Join-Path $W.home "relay\journal\in\stray")
    Check ((Get-HordeRelayJournalUnfinished -Channel "decisions" -HordeHome $W.home).state -ceq "known") "CONTROL: put back, it reads"

    Write-Host ""
    Write-Host "--- the phone key arrives through the trust channel ---" -ForegroundColor Cyan
    $W = New-World -NoPhoneKey
    $tick = @(Invoke-Tick $W)
    Check ((@($tick) -join " | ").Contains("no phone identity key")) ("with no phone key, no snapshot is sent, and it says why (" + (@($tick) -join " | ") + ")")
    Check (@(Get-PhoneMail $W).Count -eq 0) "and the phone's mailbox is empty"
    $bodyOther = New-HordeTestPhoneKeyBody -Phone $W.phone -Horde "work" -Vouch (New-HordeTestPhoneVouch -Phone $W.phone -Horde "personal")
    $pk1 = New-HordeTestPhoneEnvelope -Phone $W.phone -Kind "phone-key" -Channel "trust" -Body $bodyOther -To $W.agree
    [void](Send-ToMachine $W $pk1.text)
    $t = Invoke-Turn $W
    Check ((Has $t "refused") -and (Has $t "the phone key is refused") -and @((Find-HordeRelayPhoneKeys -HordeHome $W.home).value).Count -eq 0) ("a vouch for another horde is refused, and no key is added (" + $t.text + ")")
    Check (@((Get-HordeRelayJournalUnfinished -Channel "trust" -HordeHome $W.home).value).Count -eq 0) "and it is finished for good, not tried again"
    $extra = $utf8.GetString((New-HordeTestPhoneKeyBody -Phone $W.phone -Horde "work"))
    $extra = $extra.Substring(0, $extra.Length - 1) + ',"note":"x"}'
    $pk0 = New-HordeTestPhoneEnvelope -Phone $W.phone -Kind "phone-key" -Channel "trust" -Body ($utf8.GetBytes($extra)) -To $W.agree
    [void](Send-ToMachine $W $pk0.text)
    $t = Invoke-Turn $W
    Check ((Has $t "the body's members are") -and @((Find-HordeRelayPhoneKeys -HordeHome $W.home).value).Count -eq 0) "a phone-key body with a member it should not have is refused, and says which"
    $pk2 = New-HordeTestPhoneEnvelope -Phone $W.phone -Kind "phone-key" -Channel "trust" -Body (New-HordeTestPhoneKeyBody -Phone $W.phone -Horde "work") -To $W.agree
    [void](Send-ToMachine $W $pk2.text)
    $t = Invoke-Turn $W
    $keys = Find-HordeRelayPhoneKeys -HordeHome $W.home
    Check ((Has $t "done") -and $keys.state -ceq "known" -and @($keys.value).Count -eq 1 -and $keys.value[0].by -ceq $W.phone.keyId) ("the phone's key announced through the trust channel is in the store, vouched for by its passkey (" + $t.text + ")")

    if ($script:canDecide) {
    Write-Host ""
    Write-Host "--- the snapshot: sealed to the phone, sent when it changed, never carrying a secret ---" -ForegroundColor Cyan
    $tick = @(Invoke-Tick $W)
    $mail = @(Get-PhoneMail $W)
    Check ((@($tick) -join " ").Contains("snapshot of 1 open question(s)") -and $mail.Count -eq 1) ("the first look sends a snapshot of the one open question (" + (@($tick) -join " | ") + ")")
    $o = Open-HordeTestPhoneEnvelope -Phone $W.phone -Text $mail[0] -MachineSignPublic $W.id.sign.public
    Check ($o.ok -and $o.header.channel -ceq "decisions" -and $o.header.kind -ceq "snapshot" -and $o.header.from -ceq $W.id.sign.keyId) ("the phone opens it, signed by the machine, on channel decisions, kind snapshot (" + $o.reason + ")")
    Check ($o.ok -and $o.body.kind -ceq "decisions-snapshot" -and @($o.body.questions).Count -eq 1 -and $o.body.questions[0].title -ceq "Should the closing sound play when the assistant closes?" -and $o.body.questions[0].wordingVersion -eq 1 -and $o.body.horde -ceq "work") "and it holds the open question as the window shows it, with its wording"
    $outSeq = (Read-HordeRelayEnvelope -Text $mail[0]).value.header.seq
    Check (Test-Path -LiteralPath (Join-Path $W.home ("relay\journal\out\s-" + $W.id.sign.keyId + "\c-decisions\" + ([long]$outSeq).ToString("D16") + ".rec"))) "the snapshot was recorded in the journal as sent, under its seq"
    $stranger = New-HordeTestPhone
    $so = Open-HordeTestPhoneEnvelope -Phone $stranger -Text $mail[0] -MachineSignPublic $W.id.sign.public
    Check (-not $so.ok) "a phone whose key was never vouched for cannot open it"
    $tick = @(Invoke-Tick $W)
    Check ($tick.Count -eq 0 -and @(Get-PhoneMail $W).Count -eq 1) "a look with nothing changed sends nothing"
    # And reads nothing: with the list made unreadable, a look at an unchanged store says nothing, because
    # the fingerprint - the record names and the phone keys - is all it asked.
    [System.IO.File]::WriteAllText((Join-Path $W.home "settings\decisions.json"), "{ not json", $utf8)
    $tick = @(Invoke-Tick $W)
    Remove-Item -LiteralPath (Join-Path $W.home "settings\decisions.json")
    Check ($tick.Count -eq 0) ("a look at an unchanged store does not read the list at all (" + (@($tick) -join " | ") + ")")
    $null = Invoke-HordeDecision -Operation "say" -Root $W.store -Request @{ id = (New-Id); actor = "warchief"; number = 1; speaker = "warchief"; route = "command"; text = "A short chime, or none?" }
    $tick = @(Invoke-Tick $W)
    $mail = @(Get-PhoneMail $W)
    $o2 = Open-HordeTestPhoneEnvelope -Phone $W.phone -Text $mail[$mail.Count - 1] -MachineSignPublic $W.id.sign.public
    Check ($mail.Count -eq 2 -and $o2.ok -and $o2.body.questions[0].thread.count -eq 1 -and $o2.body.questions[0].thread.turn -ceq "founder") "a change the window would show sends a new snapshot: the warchief's reply, and the turn is the founder's"
    # WHAT THE FOUNDER NEEDS TO ANSWER FROM THE PHONE (review of 48bc492, item 9): the question's whole
    # text and context, and the conversation under it with the warchief's replies - the window's view.
    $q1 = $(if ($o2.ok) { $o2.body.questions[0] } else { $null })
    $msgs = @(@(Get-Member2 (Get-Member2 $q1 "thread") "messages") | Where-Object { $null -ne $_ })
    Check ($msgs.Count -eq 1 -and $msgs[0].text -ceq "A short chime, or none?" -and $msgs[0].speaker -ceq "warchief") ("the snapshot carries the thread's messages, the warchief's reply word for word (" + $msgs.Count + ")")
    $names = $(if ($null -ne $q1) { @($q1.PSObject.Properties | ForEach-Object { $_.Name }) } else { @() })
    Check ($null -ne $q1 -and (Get-Member2 $q1 "whatItIs") -ceq "The app has no closing sound today." -and @(@("recommendation", "parts", "yesMeans", "groupNote", "options", "references") | Where-Object { $names -cnotcontains $_ }).Count -eq 0) "and every field of the question: its text, its context, the recommendation and its parts"
    Check ($o2.ok -and (Get-Member2 $o2.body "page") -eq 1 -and (Get-Member2 $o2.body "pages") -eq 1 -and "$(Get-Member2 $o2.body "snapshot")" -cmatch '\A[0-9a-f]{64}\z') "a snapshot that fits is one page of one, named by its hash"
    # The founder's words, unread by the warchief until he marks them: his mark is his inbox, not the
    # founder's, and must not send the phone a new snapshot.
    $null = Invoke-HordeDecision -Operation "say" -Root $W.store -Request @{ id = (New-Id); actor = "warchief"; number = 1; speaker = "founder"; route = "chat-recorded"; text = "A short one." }
    $tick = @(Invoke-Tick $W)
    $mailBefore = @(Get-PhoneMail $W).Count
    $upTo = @(Get-ChildItem -LiteralPath $W.store -Filter "*.json").Count
    $null = Invoke-HordeDecision -Operation "mark-read" -Root $W.store -Request @{ id = (New-Id); actor = "warchief"; upTo = $upTo }
    $tick = @(Invoke-Tick $W)
    Check ($mailBefore -eq 3 -and @(Get-PhoneMail $W).Count -eq $mailBefore) ("a change that shows nothing new (the warchief's read mark) sends nothing: the snapshot is the same (" + $mailBefore + ")")
    $token = "ghp_" + ("Ab3" * 10)
    $plantSeq = @(Get-ChildItem -LiteralPath $W.store -Filter "*.json").Count + 1
    $plantFile = Join-Path $W.store ($plantSeq.ToString("D10") + ".json")
    $planted = '{"schemaVersion":1,"sequence":' + $plantSeq + ',"id":"' + (New-Id) + '","kind":"question-added","at":"2026-10-09T12:00:00.0000000Z","actor":"warchief","requestHash":"' + ("0" * 64) + '","data":{"number":2,"question":{"title":"Rotate the deploy token please now","kind":"yes-no","whatItIs":"The token is ' + $token + '","group":"ops","askedBy":"orc-a"}}}'
    [System.IO.File]::WriteAllText($plantFile, $planted, $utf8)
    $tick = @(Invoke-Tick $W)
    $mail = @(Get-PhoneMail $W)
    $o3 = Open-HordeTestPhoneEnvelope -Phone $W.phone -Text $mail[$mail.Count - 1] -MachineSignPublic $W.id.sign.public
    Check ((@($tick) -join " ").Contains("1 withheld") -and $o3.ok -and @($o3.body.questions).Count -eq 1 -and @($o3.body.withheld).Count -eq 1 -and $o3.body.withheld[0].number -eq 2) ("a question holding what looks like a secret is withheld by number (" + (@($tick) -join " | ") + ")")
    $raw = $utf8.GetString([byte[]](Unprotect-HordeRelayEnvelope -Envelope (Read-HordeRelayEnvelope -Text $mail[$mail.Count - 1]).value -Senders @{ ($W.id.sign.keyId) = (New-HordeRelaySender -Public $W.id.sign.public -Proof "es256") } -RecipientKeys @{ (Get-HordeRelayKeyId -Public $W.phone.agreePublic) = $W.phone.agree } -Replay (New-HordeKnown -Value ([pscustomobject]@{ key = (Get-HordeRelayReplayKey -Header (Read-HordeRelayEnvelope -Text $mail[$mail.Count - 1]).value.header); fresh = $true })) -Channel "decisions" -Kind "snapshot").value)
    Check (-not $raw.Contains($token) -and -not $raw.Contains("ghp_")) "and nothing of the secret is anywhere in the snapshot's text"
    Remove-Item -LiteralPath $plantFile
    $q2 = Invoke-HordeDecision -Operation "add" -Root $W.store -Request @{ id = (New-Id); actor = "warchief"; question = @{ title = "Should the opening sound play when the assistant opens?"; kind = "yes-no"; whatItIs = "The app has no opening sound today."; group = "voice"; askedBy = "orc-b" } }
    $null = Invoke-HordeDecision -Operation "close" -Root $W.store -Request @{ id = (New-Id); actor = "warchief"; number = [int]$q2.value.number; outcome = "Decided at the desk." }
    $tick = @(Invoke-Tick $W)
    $mail = @(Get-PhoneMail $W)
    $o4 = Open-HordeTestPhoneEnvelope -Phone $W.phone -Text $mail[$mail.Count - 1] -MachineSignPublic $W.id.sign.public
    Check ($o4.ok -and @($o4.body.questions).Count -eq 1 -and @($o4.body.questions | Where-Object { $_.state -cne "open" }).Count -eq 0) "a closed question is not in the snapshot: it holds the open questions only"
    # PAGES AND THE CAP. Three questions of 400,000 characters do not fit one envelope's 1 MiB body: they
    # go as pages of one snapshot, each within what the relay holds. One question larger than any page is
    # withheld by number, never cut.
    $long = ("the quiet option " * 23600).Substring(0, 400000)
    foreach ($i in 1..3) { $null = Invoke-HordeDecision -Operation "add" -Root $W.store -Request @{ id = (New-Id); actor = "warchief"; question = @{ title = ("Long question number " + $i + " for paging"); kind = "yes-no"; whatItIs = $long; group = "voice"; askedBy = "orc-b" } } }
    $huge = Invoke-HordeDecision -Operation "add" -Root $W.store -Request @{ id = (New-Id); actor = "warchief"; question = @{ title = "A question too large for any page"; kind = "yes-no"; whatItIs = $long; group = "voice"; askedBy = "orc-b" } }
    foreach ($i in 1..3) { $null = Invoke-HordeDecision -Operation "say" -Root $W.store -Request @{ id = (New-Id); actor = "warchief"; number = [int]$huge.value.number; speaker = "warchief"; route = "command"; text = $long } }
    $before = @(Get-PhoneMail $W).Count
    $tick = @(Invoke-Tick $W)
    $mail = @(Get-PhoneMail $W)
    $pages = @($mail | Select-Object -Skip $before | ForEach-Object { Open-HordeTestPhoneEnvelope -Phone $W.phone -Text $_ -MachineSignPublic $W.id.sign.public })
    $okPages = @($pages | Where-Object { $_.ok })
    $numbers = @($okPages | ForEach-Object { @($_.body.questions) | ForEach-Object { [int]$_.number } } | Sort-Object)
    $hashes = @($okPages | ForEach-Object { "$($_.body.snapshot)" } | Sort-Object -Unique)
    Check ($pages.Count -ge 2 -and $okPages.Count -eq $pages.Count -and @($mail | Select-Object -Skip $before | Where-Object { $_.Length -gt $W.conn.relay.limits.maxTextChars }).Count -eq 0) ("a snapshot too large for one envelope goes as pages, each within what the relay holds (" + $pages.Count + " page(s); " + (@($tick) -join " | ") + ")")
    Check ($hashes.Count -eq 1 -and @($okPages | Where-Object { [int]$_.body.pages -ne $pages.Count }).Count -eq 0 -and ($numbers -join ",") -ceq ("1," + ((@(1..3) | ForEach-Object { [int]$huge.value.number - 4 + $_ }) -join ","))) ("the pages name one snapshot and together hold every open question that fits (" + ($numbers -join ",") + ")")
    Check (@($okPages | ForEach-Object { @($_.body.withheld) } | Where-Object { [int]$_.number -eq [int]$huge.value.number -and "$($_.reason)".Contains("too large") }).Count -ge 1) "the question larger than any page is withheld by number, and says it is too large - never cut"

    Write-Host ""
    Write-Host "--- an answer lands once: the first answer wins ---" -ForegroundColor Cyan
    $W = New-World
    $aid = New-Id
    $e1 = Get-Answer $W -AnswerId $aid
    [void](Send-ToMachine $W $e1.text)
    $t = Invoke-Turn $W
    $said = @(Get-Said $W.store)
    $rec = Get-RecordFile -World $W -Header $e1.header
    Check ((Has $t "done") -and $said.Count -eq 1 -and $said[0].data.route -ceq "phone" -and $said[0].data.speaker -ceq "founder" -and $said[0].actor -ceq "founder" -and $said[0].data.text -ceq "Yes, play it." -and $said[0].data.wordingVersion -eq 1) ("the answer is in the list once, as the founder's words by the route phone (" + $t.text + ")")
    Check ((Test-Path -LiteralPath $rec) -and $said[0].data.evidence -ceq (Get-FileHash256 $rec)) "its evidence is the hash of the journal record that holds the signed envelope"
    $idHash = Get-HordeRelaySha256 -Bytes ([System.Text.Encoding]::ASCII.GetBytes("horde-relay/decisions/v1 answer id`n" + $W.phone.keyId + "`n" + $aid))
    $wantId = (@($idHash[0..15] | ForEach-Object { $_.ToString("x2") }) -join "")
    Check ($said[0].id -ceq $wantId) "its id is the first 16 bytes of SHA-256 of the domain, the sender and the answerId, as the channel's header says"
    Check ($W.ctx.acked -ge 1 -and @((Receive-HordeRelayItems -Connection $W.conn -Mailbox $W.ctx.mailbox -Since 0).value.items).Count -eq 0) "the relay was acked through it, and has forgotten it"
    $dup = Send-ToMachine $W $e1.text
    $t = Invoke-Turn $W
    Check (@(Get-Said $W.store).Count -eq 1) ("the same envelope put again is still one answer (" + $t.text + ")")
    $re = New-HordeTestPhoneResigned -Phone $W.phone -Envelope $e1
    Check ($re -cne $e1.text) "CONTROL: a re-signed copy is another text"
    [void](Send-ToMachine $W $re (Get-HordeRelayContentKey -Text $re))
    $t = Invoke-Turn $W
    Check ((Has $t "replay") -and @(Get-Said $W.store).Count -eq 1) ("a re-signed copy of the same envelope is refused by the journal as a replay (" + $t.text + ")")
    $e2 = Get-Answer $W -AnswerId $aid
    [void](Send-ToMachine $W $e2.text)
    $t = Invoke-Turn $W
    Check ((Has $t "(replayed)") -and @(Get-Said $W.store).Count -eq 1) ("the same answer sent again in a new envelope is the first record answered again (" + $t.text + ")")
    $e3 = Get-Answer $W -AnswerId $aid -Text "No, keep it silent."
    [void](Send-ToMachine $W $e3.text)
    $t = Invoke-Turn $W
    Check ((Has $t "already used for a different request") -and @(Get-Said $W.store).Count -eq 1 -and (@(Get-Said $W.store))[0].data.text -ceq "Yes, play it.") ("other words under the same answerId are refused: the first answer wins (" + $t.text + ")")
    Check (@((Get-HordeRelayJournalUnfinished -Channel "decisions" -HordeHome $W.home).value).Count -eq 0) "and that refusal is final: nothing is left to retry"
    $e4 = Get-Answer $W -Text "No, keep it silent."
    [void](Send-ToMachine $W $e4.text)
    $t = Invoke-Turn $W
    Check ((Has $t "done") -and @(Get-Said $W.store).Count -eq 2) "a new answer is a second record, kept after the first"
    $e5 = Get-Answer $W -Number 9
    [void](Send-ToMachine $W $e5.text)
    $t = Invoke-Turn $W
    Check ((Has $t "there is no question 9") -and @(Get-Said $W.store).Count -eq 2 -and @((Get-HordeRelayJournalUnfinished -Channel "decisions" -HordeHome $W.home).value).Count -eq 0) "an answer to a question that does not exist is refused, for good"
    # AN ANSWER IS FOR ONE MACHINE (review of 48bc492, finding 2): one envelope sealed to two machines
    # answered question 1 on both, though question 1 is another question on each. The body names the
    # machine and the snapshot it was made from, and only that machine takes it.
    $B = New-World
    Use-World $B
    [void](Add-HordeTestPhonePairing -HordeHome $B.home -Phone $W.phone)
    $both = Get-Answer $W -Text "Yes, on machine A" -To @($W.agree[0], $B.agree[0])
    [void](Send-ToMachine $W $both.text)
    $tA = Invoke-Turn $W
    $Bsaid = @(Get-Said $B.store).Count
    [void](Send-ToMachine $B $both.text)
    $tB = Invoke-Turn $B
    Check ((Has $tA "done") -and (Has $tB "is for another machine") -and @(Get-Said $B.store).Count -eq $Bsaid) ("an answer sealed to two machines lands on the one it names, and the other refuses it (" + $tB.text + ")")
    $stale = Get-Answer $B -Phone $W.phone -Machine $B.id.sign.keyId -Snapshot (Get-SentKey $W) -Text "made from A's snapshot"
    [void](Send-ToMachine $B $stale.text)
    $tB = Invoke-Turn $B
    Check ((Has $tB "not a snapshot this machine sent") -and @(Get-Said $B.store).Count -eq $Bsaid) ("an answer naming a snapshot this machine never sent is refused (" + $tB.text + ")")
    $own = Get-SentKey $B
    $forgedKey = $own.Substring(0, $own.Length - 1) + $(if ($own.EndsWith("0")) { "1" } else { "0" })
    [void](Send-ToMachine $B (Get-Answer $B -Phone $W.phone -Machine $B.id.sign.keyId -Snapshot $forgedKey -Text "a snapshot of the right seq, not the right envelope").text)
    $tB = Invoke-Turn $B
    Check ((Has $tB "not a snapshot this machine sent") -and @(Get-Said $B.store).Count -eq $Bsaid) ("and so is one naming this machine's seq with another envelope's nonce (" + $tB.text + ")")
    Use-World $W
    $junk = New-HordeTestPhoneEnvelope -Phone $W.phone -Kind "answer" -Channel "decisions" -Body ($utf8.GetBytes('{"v":1,"answerId":"' + (New-Id) + '","machine":"' + $W.id.sign.keyId + '","snapshot":"' + (Get-SentKey $W) + '","number":1,"wordingVersion":1,"text":"x","extra":1}')) -To $W.agree
    [void](Send-ToMachine $W $junk.text)
    $t = Invoke-Turn $W
    Check ((Has $t "the answer's members are") -and @(Get-Said $W.store).Count -eq 3) ("a body with a member it should not have is refused, and says which (" + $t.text + ")")

    }
    Write-Host ""
    Write-Host "--- nothing but a trusted founder passkey answers, and nothing refused is journaled ---" -ForegroundColor Cyan
    $W = New-World
    $pending = New-HordeTestPhone
    [void](Add-HordeTestPhonePairing -HordeHome $W.home -Phone $pending -NoConfirm)
    [void](Send-ToMachine $W (Get-Answer $W -Phone $pending).text)
    $t = Invoke-Turn $W
    Check ((Has $t "pending") -and @(Get-Said $W.store).Count -eq 0) ("an answer from a passkey still pending is refused (" + $t.text + ")")
    $nobody = New-HordeTestPhone
    [void](Send-ToMachine $W (Get-Answer $W -Phone $nobody).text)
    $t = Invoke-Turn $W
    Check ((Has $t "no trusted sender has the key") -and @(Get-Said $W.store).Count -eq 0) "an answer from a passkey never paired is refused"
    $forged = New-HordeTestPhoneEnvelope -Phone $nobody -Kind "answer" -Channel "decisions" -Body (New-HordeTestPhoneAnswerBody) -To $W.agree -From $W.phone.keyId
    [void](Send-ToMachine $W $forged.text)
    $t = Invoke-Turn $W
    Check ((Has $t "does not verify") -and @(Get-Said $W.store).Count -eq 0) ("an answer that names the founder's passkey and is signed by another is refused (" + $t.text + ")")
    $peerHome = New-TestHome
    [void](New-HordeRelayMachineIdentity -HordeHome $peerHome -Provider "software")
    $card = (Export-HordeRelayMachineCard -HordeHome $peerHome -Label "Second machine").value
    $added = Add-HordeRelayPeerMachine -HordeHome $W.home -Card $card
    $cs = New-HordeTestPhoneAssertion -Phone $W.phone -Challenge (Get-HordeRelayCardChallenge -Card $card)
    $vouched = Confirm-HordeRelayPeerMachine -HordeHome $W.home -KeyId $added.value.record.keyId -By $W.phone.keyId -AuthenticatorData $cs.authenticatorData -ClientDataJson $cs.clientDataJson -Signature $cs.signature
    Check ($vouched.state -ceq "known" -and $vouched.value.record.state -ceq "trusted") "CONTROL: a peer machine of the horde is trusted, countersigned by the founder's passkey"
    $peerId = Get-HordeRelayMachineIdentity -HordeHome $peerHome -Open
    $peerAnswer = New-HordeRelayEnvelope -Kind "answer" -Channel "decisions" -Seq 1 -Body (New-HordeTestPhoneAnswerBody) -Recipients $W.agree -Signer $peerId.value.sign.key
    $peerId.value.sign.key.Dispose(); $peerId.value.agree.key.Dispose()
    [void](Send-ToMachine $W $peerAnswer)
    $t = Invoke-Turn $W
    Check ((Has $t "a trusted sender, but not one the channel decisions takes (founder)") -and @(Get-Said $W.store).Count -eq 0) ("a TRUSTED peer machine's answer is refused: only the founder's passkeys answer (" + $t.text + ")")
    $machineKey = New-HordeRelayP256Key -Use "ecdsa"
    $es = New-HordeRelayEnvelope -Kind "answer" -Channel "decisions" -Seq 1 -Body (New-HordeTestPhoneAnswerBody) -Recipients $W.agree -Signer $machineKey
    [void](Send-ToMachine $W $es)
    $t = Invoke-Turn $W
    Check ((Has $t "refused") -and @(Get-Said $W.store).Count -eq 0) "an answer signed by a machine key is refused"
    [void](Send-ToMachine $W (New-HordeTestPhoneEnvelope -Phone $W.phone -Kind "line" -Channel "notes" -Body (New-HordeTestPhoneAnswerBody) -To $W.agree).text)
    [void](Send-ToMachine $W (New-HordeTestPhoneEnvelope -Phone $W.phone -Kind "snapshot" -Channel "decisions" -Body (New-HordeTestPhoneAnswerBody) -To $W.agree).text)
    $t = Invoke-Turn $W
    Check ((Has $t "no channel 'notes' is registered") -and (Has $t "takes answer, not snapshot") -and @(Get-Said $W.store).Count -eq 0) ("another channel, and another kind on this one, are refused (" + $t.text + ")")
    $elsewhere = New-HordeRelayP256Key -Use "ecdh"
    [void](Send-ToMachine $W (Get-Answer $W -To @(, ([byte[]](ConvertTo-HordeRelayP256Public -Key $elsewhere)))).text)
    $t = Invoke-Turn $W
    Check ((Has $t "not addressed to any agreement key of this machine") -and @(Get-Said $W.store).Count -eq 0) "an answer sealed to another machine is refused"
    [void](Send-ToMachine $W "not an envelope at all" "k-garbage")
    $t = Invoke-Turn $W
    Check ((Has $t "not an envelope") -and @(Get-Said $W.store).Count -eq 0) "text that is not an envelope is refused"
    $cursorBefore = $W.ctx.cursor
    $junkDevice = Join-Path $W.home "relay\trust\devices\not-a-record.txt"
    [System.IO.File]::WriteAllText($junkDevice, "x", $utf8)
    $heldAnswer = Get-Answer $W
    [void](Send-ToMachine $W $heldAnswer.text)
    $t = Invoke-Turn $W
    Check ((Has $t "held ") -and $W.ctx.cursor -eq $cursorBefore -and $W.ctx.acked -le $cursorBefore) ("while the trust store cannot be read, an answer is held: neither judged nor acked, the cursor before it (" + $t.text + ")")
    Remove-Item -LiteralPath $junkDevice
    $inDir = Join-Path $W.home "relay\journal\in"
    $streams = @(Get-ChildItem -LiteralPath $inDir -Directory -ErrorAction SilentlyContinue)
    Check ($streams.Count -eq 0) ("none of the refused was journaled: the journal has no received stream (" + $streams.Count + ")")
    if ($script:canDecide) {
        $t = Invoke-Turn $W
        Check ((Has $t "done") -and @(Get-Said $W.store).Count -eq 1) ("once the store reads again, the held answer comes again and lands: the founder's own answer, after all that (" + $t.text + ")")
    }

    if ($script:canDecide) {
    Write-Host ""
    Write-Host "--- a record journaled and not finished is finished later, once ---" -ForegroundColor Cyan
    $W = New-World
    $badSettings = Join-Path $W.home "settings\decisions.json"
    [System.IO.File]::WriteAllText($badSettings, "{ this is not json", $utf8)
    [void](Send-ToMachine $W (Get-Answer $W -AnswerId "0123456789abcdef0123456789abcdef").text)
    $t = Invoke-Turn $W
    Check ((Has $t "retry") -and @(Get-Said $W.store).Count -eq 0) ("while the decisions list cannot be written, the answer is kept for later (" + $t.text + ")")
    Check (@((Get-HordeRelayJournalUnfinished -Channel "decisions" -HordeHome $W.home).value).Count -eq 1 -and $W.ctx.acked -ge 1) "it stays unfinished in the journal, and the relay may forget it: the journal holds it whole"
    Remove-Item -LiteralPath $badSettings
    $t = Invoke-Turn $W
    Check ((Has $t "done") -and @(Get-Said $W.store).Count -eq 1) ("once the list can be written, the next turn lands it (" + $t.text + ")")
    $t = Invoke-Turn $W
    Check (@(Get-Said $W.store).Count -eq 1 -and @((Get-HordeRelayJournalUnfinished -Channel "decisions" -HordeHome $W.home).value).Count -eq 0) "and only once"
    # A crash after the act and before the done mark: the act is done, the record still unfinished.
    $e = Get-Answer $W
    $read = (Read-HordeRelayEnvelope -Text $e.text).value
    [void](Register-HordeRelayJournalReceived -Envelope $read -Senders (Find-HordeRelayTrustedSenders -HordeHome $W.home).value -RecipientKeyIds @($W.ctx.openingKeys.Keys) -Channel "decisions" -Kind "answer" -HordeHome $W.home)
    $first = Invoke-HordeRelayUnfinished -Context $W.ctx
    $mark = Join-Path (Split-Path -Parent (Get-RecordFile -World $W -Header $e.header)) (([long]$e.header.seq).ToString("D16") + ".done")
    Remove-Item -LiteralPath $mark
    $second = Invoke-HordeRelayUnfinished -Context $W.ctx
    Check (@($first.value.done).Count -eq 1 -and @($second.value.done).Count -eq 1 -and (@($second.value.done)[0]).Contains("(replayed)") -and @(Get-Said $W.store).Count -eq 2) "a record handed over again after a crash before its done mark is the first record answered again: one record"
    $e = Get-Answer $W
    [void](Register-HordeRelayJournalReceived -Envelope (Read-HordeRelayEnvelope -Text $e.text).value -Senders (Find-HordeRelayTrustedSenders -HordeHome $W.home).value -RecipientKeyIds @($W.ctx.openingKeys.Keys) -Channel "decisions" -Kind "answer" -HordeHome $W.home)
    [void](Revoke-HordeRelayTrust -HordeHome $W.home -Subject "device" -Id $W.phone.deviceId -Reason "phone lost")
    $after = Invoke-HordeRelayUnfinished -Context $W.ctx
    Check (@($after.value.refused).Count -eq 1 -and (@($after.value.refused)[0]).Contains("not opened") -and @(Get-Said $W.store).Count -eq 2) "a record journaled before its passkey was revoked is not opened after: the senders are the ones trusted now"

    Write-Host ""
    Write-Host "--- a phone answer's record names the passkey that signed it, and notify says verified only while that passkey is trusted ---" -ForegroundColor Cyan
    if ($script:canDecide) {
    $W = New-World
    $e = Get-Answer $W -Text "From the phone."
    [void](Send-ToMachine $W $e.text)
    $t = Invoke-Turn $W
    $said = @(Get-Said $W.store)
    Check ((Has $t "done") -and $said.Count -eq 1 -and (Get-Member2 $said[0].data "signedBy") -ceq $W.phone.keyId -and $e.header.from -ceq $W.phone.keyId) ("the answer's record names the key id of the passkey its envelope was verified against (" + (Get-Member2 $said[0].data "signedBy") + ")")
    Check ((Get-Member2 $said[0].data "signedBy") -cne $W.id.sign.keyId -and (Get-Member2 $said[0].data "signedBy") -cmatch '\A[0-9a-f]{32}\z') "a key id, and the phone's, not this machine's"
    # Notify over that store, with the home's REAL trust store; only the messenger and the seat are
    # stand-ins, so nothing leaves the process. The registry is put back whatever happens.
    $keepMessengers = $script:HordeMessengers
    $script:HordeMessengers = @{}
    $script:notifyPosts = New-Object System.Collections.ArrayList
    try {
        $null = Register-HordeMessenger -Folder (Join-Path $root "test\fixtures\decisions-notify\doorbell") `
            -Post { param($Message) [void]$script:notifyPosts.Add($Message); return (New-HordeKnown -Value ([pscustomobject]@{ messageId = "$($Message.messageId)"; stage = "accepted"; at = [datetime]::UtcNow; reason = "" }) -ObservedAt ([datetime]::UtcNow)) } `
            -Status { param($MessageId) return (New-HordeAbsent -Note "the stand-in keeps no status") }
        $notifySeat = { return (New-HordeKnown -Value ([pscustomobject]@{ sessionId = "warchief-session-1"; pane = "3"; instance = "t1" })) }
        $notifyClock = { return [datetime]::UtcNow.AddSeconds(5) }
        Use-World $W
        $tracker = New-HordeDecisionNotifyTracker -QuietSeconds 0
        $p = Invoke-HordeDecisionNotifyPass -Tracker $tracker -Clock $notifyClock -Seat $notifySeat -HordeHome $W.home
        $v = $(if ($script:notifyPosts.Count -eq 1) { Get-Member2 $script:notifyPosts[0].from "verified" } else { $null })
        Check ($p.outcome -ceq "rang" -and $null -ne $v -and $v.kind -ceq "founder" -and $v.by -ceq "passkey" -and $v.keyId -ceq $W.phone.keyId) ("notify tells the warchief of it as the founder, verified by that passkey - read from the record, asked of the trust store (" + $p.said + ")")
        Check ($p.said.Contains("; as the founder, verified by his passkey " + $W.phone.keyId)) "and its line says so"
        $e2 = Get-Answer $W -Text "Sent before the phone was lost."
        [void](Send-ToMachine $W $e2.text)
        $t2 = Invoke-Turn $W
        Check ((Has $t2 "done") -and @(Get-Said $W.store).Count -eq 2) ("CONTROL: a second answer by the same passkey lands while it is trusted (" + $t2.text + ")")
        [void](Revoke-HordeRelayTrust -HordeHome $W.home -Subject "device" -Id $W.phone.deviceId -Reason "phone lost")
        $p = Invoke-HordeDecisionNotifyPass -Tracker $tracker -Clock $notifyClock -Seat $notifySeat -HordeHome $W.home
        Check ($p.outcome -ceq "rang" -and $script:notifyPosts.Count -eq 2 -and $null -eq (Get-Member2 $script:notifyPosts[1].from "verified") -and "$($script:notifyPosts[1].from.label)" -ceq "F") ("once the passkey is revoked, the notice for an answer it signed goes by label only (" + $p.said + ")")
        Check ($p.said.Contains("; by label only: the passkey that signed is not trusted now: ") -and $p.said.Contains("revoked") -and $p.said.Contains("phone lost")) "and its line gives the revocation as the reason"
    } finally { $script:HordeMessengers = $keepMessengers }
    }

    Write-Host ""
    Write-Host "--- a phone answer rings the warchief with no decisions window open: the Tick turns the bell ---" -ForegroundColor Cyan
    # The founder's bug of 2026-10-12: notify ran only beside the window, so an answer from the phone with
    # the window closed was stored and rang for nobody. The channel's Tick now turns notify's own pass.
    if ($script:canDecide) {
    $keepMessengers = $script:HordeMessengers
    $script:HordeMessengers = @{}
    $script:bellPosts = New-Object System.Collections.ArrayList
    try {
        $null = Register-HordeMessenger -Folder (Join-Path $root "test\fixtures\decisions-notify\doorbell") `
            -Post { param($Message) [void]$script:bellPosts.Add($Message); return (New-HordeKnown -Value ([pscustomobject]@{ messageId = "$($Message.messageId)"; stage = "accepted"; at = [datetime]::UtcNow; reason = "woken"; woken = $true }) -ObservedAt ([datetime]::UtcNow)) } `
            -Status { param($MessageId) return (New-HordeAbsent -Note "the stand-in keeps no status") }
        $script:HordeDecisionsChannelBellSeat = { return (New-HordeKnown -Value ([pscustomobject]@{ sessionId = "warchief-session-1"; pane = "3"; instance = "t1" })) }
        $B = New-World
        [System.IO.File]::WriteAllText((Join-Path $B.home "settings\decisions-notify.json"), '{"schemaVersion": 1, "settings": {"quietSeconds": 0}}', $utf8)
        [void](Send-ToMachine $B (Get-Answer $B -Text "From the phone, window closed.").text)
        $t = Invoke-Turn $B
        Check ((Has $t "done") -and $script:bellPosts.Count -eq 0) ("CONTROL: the answer landed, and landing it rang nothing by itself (" + $t.text + ")")
        Use-World $B
        $ticks = Invoke-HordeRelayChannelTicks -Context $B.ctx
        Check ($script:bellPosts.Count -eq 1 -and "$($script:bellPosts[0].sessionId)" -ceq "warchief-session-1" -and @("$($script:bellPosts[0].body)" -split "`r?`n")[0] -ceq "FOUNDER ANSWER from the decisions window") ("the next Tick rings the warchief for it: notify's own notice, once (" + (@($ticks.lines) -join " | ") + ")")
        Check (@($ticks.lines | Where-Object { $_ -clike "decisions: notify: rang for 1 answer, on question 1, through messenger doorbell (accepted; woken)*" }).Count -eq 1) "and the run's log has notify's own line for it, with whether the warchief was woken"
        $v = Get-Member2 $script:bellPosts[0].from "verified"
        Check ($null -ne $v -and $v.keyId -ceq $B.phone.keyId) "as the founder, verified by the passkey that signed the answer"
        $ticks = Invoke-HordeRelayChannelTicks -Context $B.ctx
        Check ($script:bellPosts.Count -eq 1 -and @($ticks.lines | Where-Object { $_ -clike "*notify:*" }).Count -eq 0) "a Tick after that rings nothing more and says nothing more"
        # IN ITS QUIET PERIOD an answer is not rung for yet, and the Tick asks to be turned again in time.
        $Q = New-World
        [System.IO.File]::WriteAllText((Join-Path $Q.home "settings\decisions-notify.json"), '{"schemaVersion": 1, "settings": {"quietSeconds": 20}}', $utf8)
        [void](Send-ToMachine $Q (Get-Answer $Q -Text "Wait for the quiet.").text)
        $null = Invoke-Turn $Q
        Use-World $Q
        $ticks = Invoke-HordeRelayChannelTicks -Context $Q.ctx
        Check ($script:bellPosts.Count -eq 1 -and $ticks.againMs -gt 0 -and $ticks.againMs -le 20000 -and -not $ticks.failed) ("inside the quiet period nothing is rung, and the Ticks ask for a turn when it ends (" + $ticks.againMs + " ms)")
        # THE RUN OBEYS: its next watch waits no longer than that, where the run's own watch is longer.
        [System.IO.File]::WriteAllText((Join-Path $Q.home "settings\relay-run.json"), '{"schemaVersion": 1, "settings": {"watchMs": 60000, "minTurnMs": 50}}', $utf8)
        $script:watched = New-Object System.Collections.ArrayList
        $script:realReceive = ${function:Receive-HordeRelayInbox}
        function Receive-HordeRelayInbox { param($Context, [int]$TimeoutMs = 0) [void]$script:watched.Add($TimeoutMs); return (& $script:realReceive -Context $Context -TimeoutMs 0) }
        try { $r = Invoke-HordeRelayRun -HordeHome $Q.home -Connection $Q.conn -MaxTurns 1 -Say { param($Line) } }
        finally { Set-Item function:Receive-HordeRelayInbox $script:realReceive }
        Check ($script:watched.Count -eq 1 -and $script:watched[0] -gt 0 -and $script:watched[0] -le 20000) ("a run whose watch is 60 s watches only until the quiet period ends (" + (@($script:watched) -join ",") + " ms)")
        $script:watched.Clear()
        function Receive-HordeRelayInbox { param($Context, [int]$TimeoutMs = 0) [void]$script:watched.Add($TimeoutMs); return (& $script:realReceive -Context $Context -TimeoutMs 0) }
        try { $r = Invoke-HordeRelayRun -HordeHome $B.home -Connection $B.conn -MaxTurns 1 -Say { param($Line) } }
        finally { Set-Item function:Receive-HordeRelayInbox $script:realReceive }
        [System.IO.File]::WriteAllText((Join-Path $B.home "settings\relay-run.json"), '{"schemaVersion": 1, "settings": {"watchMs": 60000, "minTurnMs": 50}}', $utf8)
        $script:watched.Clear()
        function Receive-HordeRelayInbox { param($Context, [int]$TimeoutMs = 0) [void]$script:watched.Add($TimeoutMs); return (& $script:realReceive -Context $Context -TimeoutMs 0) }
        try { $r = Invoke-HordeRelayRun -HordeHome $B.home -Connection $B.conn -MaxTurns 1 -Say { param($Line) } }
        finally { Set-Item function:Receive-HordeRelayInbox $script:realReceive }
        Check ($script:watched.Count -eq 1 -and $script:watched[0] -eq 60000) ("CONTROL: with nothing waiting to be rung, the run's watch is its own 60 s (" + (@($script:watched) -join ",") + ")")
    } finally { $script:HordeMessengers = $keepMessengers; $script:HordeDecisionsChannelBellSeat = $null }
    }
    Check ((Get-HordeRelayRunTurnWatchMs -WatchMs 60000 -AgainMs 20000) -eq 20000 -and (Get-HordeRelayRunTurnWatchMs -WatchMs 60000 -AgainMs 0) -eq 60000 -and (Get-HordeRelayRunTurnWatchMs -WatchMs 60000 -AgainMs $null) -eq 60000) "a turn's watch is what a channel asked when that is sooner, and the run's own when nobody asked"
    Check ((Get-HordeRelayRunTurnWatchMs -WatchMs 25000 -AgainMs 90000) -eq 25000 -and (Get-HordeRelayRunTurnWatchMs -WatchMs 0 -AgainMs 500) -eq 0 -and (Get-HordeRelayRunTurnWatchMs -WatchMs 60000 -AgainMs -5) -eq 60000) "a channel can only shorten a watch, never lengthen it, and a watch of 0 stays 0"

    Write-Host ""
    Write-Host "--- a relay that lies cannot make an answer land twice, or out of order ---" -ForegroundColor Cyan
    Reset-HordeHostileRelay
    $hc = Connect-HordeRelay -Name "hostile" -Options @{}
    $W = New-World -Connection $hc.value
    # Put in the REVERSE of the phone's order: the relay's seqs then run against the phone's, and only
    # the sort by sender and seq (channels/Port.ps1, step 2) keeps the journal from refusing 1 and 2.
    $answers = @(1..3 | ForEach-Object { Get-Answer $W -Text ("answer " + $_) })
    foreach ($a in @($answers[2], $answers[1], $answers[0])) { [void](Send-ToMachine $W $a.text) }
    Set-HordeHostileRelayFaults -Faults @("reorder", "duplicate", "garbage")
    $t = Invoke-Turn $W
    $said = @(Get-Said $W.store)
    Check ($said.Count -eq 3 -and (@($said | ForEach-Object { $_.data.text }) -join ",") -ceq "answer 1,answer 2,answer 3") ("reversed, doubled and salted with garbage, the three answers land once each, in the phone's order (" + (@($said | ForEach-Object { $_.data.text }) -join ",") + ")")
    Set-HordeHostileRelayFaults -Faults @("stale", "duplicate")
    $t = Invoke-Turn $W
    Check (@(Get-Said $W.store).Count -eq 3 -and (Has $t "at or before the cursor")) ("served again from the start, nothing lands twice: the port drops what is behind the cursor (" + $t.text + ")")
    [void](Send-ToMachine $W (Get-Answer $W -Text "answer 4").text)
    Set-HordeHostileRelayFaults -Faults @("conflict")
    $t = Invoke-Turn $W
    Check (@(Get-Said $W.store).Count -eq 4 -and (Has $t "came again with other text")) ("a conflicting copy after the real one is dropped, and the real one lands (" + $t.text + ")")
    # In the relay's own order a forgery may come FIRST: relays/Port.ps1 keeps the first, as it must
    # (it cannot tell which text is real). The forgery is not an envelope and is refused; the answer it
    # displaced is lost from the relay - as if dropped, which a relay can always do - and the journal
    # says so when the phone's next envelope arrives.
    @(5..6 | ForEach-Object { Get-Answer $W -Text ("answer " + $_) }) | ForEach-Object { [void](Send-ToMachine $W $_.text) }
    Set-HordeHostileRelayFaults -Faults @("conflict", "reorder")
    $t = Invoke-Turn $W
    $texts = (@(Get-Said $W.store) | ForEach-Object { $_.data.text }) -join ","
    Check ($texts -ceq "answer 1,answer 2,answer 3,answer 4,answer 6" -and (Has $t "not an envelope") -and (Has $t "1 envelope(s) of this sender before it are missing")) ("a forgery the relay puts first is refused, and the answer it displaced is reported missing, never landed wrong (" + $texts + ")")
    @(7..9 | ForEach-Object { Get-Answer $W -Text ("answer " + $_) }) | ForEach-Object { [void](Send-ToMachine $W $_.text) }
    Set-HordeHostileRelayFaults -Faults @("drop")
    $before = @(Get-Said $W.store).Count
    $t = Invoke-Turn $W
    $got = @(Get-Said $W.store)
    # The hostile relay drops every EVEN relay seq; these three are its 7, 8 and 9.
    Check (($got.Count - $before) -eq 2 -and (@($got | Select-Object -Last 2 | ForEach-Object { $_.data.text }) -join ",") -ceq "answer 7,answer 9" -and (Has $t "relay gap: seq 8 to 8") -and (Has $t "missing ")) ("an answer the relay drops is reported as a gap and as missing, not silence; the ones it delivers land (" + $t.text + ")")
    Set-HordeHostileRelayFaults -Faults @("throw")
    $before = @(Get-Said $W.store).Count
    $t = Invoke-Turn $W
    Check ($t.inbox.state -ceq "unknown" -and @(Get-Said $W.store).Count -eq $before) "a relay that throws is an unknown read, and changes nothing"
    Set-HordeHostileRelayFaults -Faults @()

    }
    if ($script:canDecide) {
    Write-Host ""
    Write-Host "--- a snapshot the relay will not take is recorded once and put again, never made again ---" -ForegroundColor Cyan
    # Review of 48bc492, finding 1: each turn journaled a new full snapshot and tried again, with no
    # backoff - 20 turns, 20 records, no wait.
    Reset-HordeHostileRelay
    $hc2 = Connect-HordeRelay -Name "hostile" -Options @{}
    $W = New-World -Connection $hc2.value
    [System.IO.File]::WriteAllText((Join-Path $W.home "settings\relay-run.json"), '{"schemaVersion": 1, "settings": {"watchMs": 0, "minTurnMs": 50, "backoffMinMs": 100, "backoffMaxMs": 400, "backoffJitterPercent": 0}}', $utf8)
    $outDir = Join-Path $W.home ("relay\journal\out\s-" + $W.id.sign.keyId + "\c-decisions")
    $recsBefore = @(Get-ChildItem -LiteralPath $outDir -Filter "*.rec" -ErrorAction SilentlyContinue).Count
    $savedPut = $hc2.value.relay.put
    $hc2.value.relay.put = { param($State, $Mailbox, $Key, $Text) return (New-HordeUnknown -Reason "put refused by the relay") }
    # The very tick that makes a snapshot and cannot put it says it failed.
    $fresh = (Update-HordeRelayRunContext -Context $W.ctx).value
    $fresh.state = @{}
    $W.ctx = $fresh
    $first = Invoke-HordeRelayChannelTicks -Context $W.ctx
    Check ($first.failed -eq $true -and (@($first.lines) -join " ").Contains("not delivered")) ("the tick that records a snapshot the relay will not take says it failed (" + (@($first.lines) -join " | ") + ")")
    # A new run is a new memory: from here, what it records is counted.
    $recsBefore = @(Get-ChildItem -LiteralPath $outDir -Filter "*.rec" -ErrorAction SilentlyContinue).Count
    # The relay takes puts again after the run's fifth backoff, in the same run: what it then puts must be
    # the envelope recorded before, not a new one.
    $slept = New-Object System.Collections.ArrayList
    $said = New-Object System.Collections.ArrayList
    $mend = { param($Ms, $Why) if ("$Why" -ceq "pace") { return }; [void]$slept.Add($Ms); if ($slept.Count -eq 5) { $hc2.value.relay.put = $savedPut } }
    try { $r = Invoke-HordeRelayRun -HordeHome $W.home -Connection $hc2.value -MaxTurns 8 -Say { param($Line) [void]$said.Add($Line) } -Sleep $mend }
    finally { $hc2.value.relay.put = $savedPut }
    $recsAfter = @(Get-ChildItem -LiteralPath $outDir -Filter "*.rec" -ErrorAction SilentlyContinue)
    Check (($recsAfter.Count - $recsBefore) -le 1) ("a run whose relay will not take the snapshot records it once, not once a turn (" + ($recsAfter.Count - $recsBefore) + " new record(s) in " + $r.turns + " turns)")
    Check ($slept.Count -ge 5 -and (@($said) -join " ").Contains("not delivered")) ("each turn that could not deliver it counts as a failure, and the run backs off (" + (@($slept) -join ",") + ")")
    $lastKey = Get-SentKey $W
    $phoneKeys = @((Receive-HordeRelayItems -Connection $hc2.value -Mailbox "work/phone" -Since 0).value.items | ForEach-Object { $_.key })
    Check ($phoneKeys -ccontains $lastKey -and $r.failures -eq 0) ("once the relay takes puts again, the envelope recorded before is the one put, and the run goes on clean (" + $r.failures + ")")
    $big = New-Object byte[] 5000
    $saved = $null
    try { $saved = Save-HordeRelayChannelEnvelope -Context $W.ctx -Channel "decisions" -Kind "snapshot" -Body $big -Recipients @(, ([byte[]]$W.phone.agreePublic)) } catch { $saved = [pscustomobject]@{ state = "threw"; reason = $_.Exception.Message } }
    Check ($saved.state -ceq "unknown" -and "$($saved.reason)".Contains("relay holds") -and @(Get-ChildItem -LiteralPath $outDir -Filter "*.rec").Count -eq $recsAfter.Count) ("an envelope larger than the relay holds is refused before it is journaled (" + $saved.state + ": " + $saved.reason + ")")

    Write-Host ""
    Write-Host "--- the run's memory survives the hourly reopen of its keys ---" -ForegroundColor Cyan
    # Finding 3: the reopen reset the cursor and the channels' memory, and sent the same snapshot again.
    $W = New-World
    $mailBefore = @(Get-PhoneMail $W).Count
    $W.ctx.cursor = [long]7; $W.ctx.acked = [long]7
    $re = $null
    try { $re = Update-HordeRelayRunContext -Context $W.ctx } catch { $re = [pscustomobject]@{ state = "threw"; reason = $_.Exception.Message } }
    Check ($re.state -ceq "known" -and $re.value.cursor -eq 7 -and $re.value.acked -eq 7 -and [object]::ReferenceEquals($re.value.state, $W.ctx.state)) ("reopened, the context keeps its cursor, its ack and the channels' memory (" + $re.state + ")")
    if ($re.state -ceq "known") {
        $old = $W.ctx; $W.ctx = $re.value; [void]$script:worlds.Add([pscustomobject]@{ ctx = $old })
        $tick = @(Invoke-Tick $W)
        Check ($tick.Count -eq 0 -and @(Get-PhoneMail $W).Count -eq $mailBefore) "and the same snapshot is not sent again after it"
    }
    }
    Write-Host ""
    Write-Host "--- the runner: turns, stops cleanly, backs off with jitter, releases retired keys ---" -ForegroundColor Cyan
    $set = [pscustomobject]@{ backoffMinMs = 1000; backoffMaxMs = 60000; backoffJitterPercent = 20 }
    $rnd = New-Object System.Random -ArgumentList 7
    $waits = @(1..8 | ForEach-Object { Get-HordeRelayRunBackoffMs -Failures $_ -Settings $set -Random $rnd })
    Check ($waits[0] -ge 800 -and $waits[0] -le 1200 -and $waits[2] -ge 3200 -and $waits[2] -le 4800 -and $waits[7] -ge 48000 -and $waits[7] -le 72000) ("the wait doubles per failure, is capped, and moves by up to 20% either way (" + ($waits -join ", ") + ")")
    $flat = [pscustomobject]@{ backoffMinMs = 500; backoffMaxMs = 1500; backoffJitterPercent = 0 }
    Check ((@(1..4 | ForEach-Object { Get-HordeRelayRunBackoffMs -Failures $_ -Settings $flat -Random $rnd }) -join ",") -ceq "500,1000,1500,1500" -and (Get-HordeRelayRunBackoffMs -Failures 0 -Settings $flat -Random $rnd) -eq 0) "with no jitter it is exactly 500, 1000, then the cap of 1500; and no wait after no failure"
    $spread = @(1..200 | ForEach-Object { Get-HordeRelayRunBackoffMs -Failures 1 -Settings $set -Random $rnd } | Sort-Object -Unique)
    Check ($spread.Count -gt 50) ("CONTROL: the jitter does vary (" + $spread.Count + " distinct waits in 200)")
    $W = New-World
    [System.IO.File]::WriteAllText((Join-Path $W.home "settings\relay-run.json"), '{"schemaVersion": 1, "settings": {"watchMs": 0, "minTurnMs": 50}}', $utf8)
    [void](Send-ToMachine $W (Get-Answer $W).text)
    $said = New-Object System.Collections.ArrayList
    $script:released = 0
    function Remove-HordeRelayRetiredAgreeKeys { param([string]$HordeHome = "", $Now = $null) $script:released++; return (New-HordeKnown -Value ([pscustomobject]@{ released = @(); problems = "" })) }
    $r = Invoke-HordeRelayRun -HordeHome $W.home -Connection $W.conn -MaxTurns 3 -Say { param($Line) [void]$said.Add($Line) }
    $sayText = (@($said) -join " | ")
    Check ($r.turns -eq 3 -and $r.stoppedBy -ceq "turns" -and $sayText.Contains("watching " + $W.ctx.mailbox) -and $sayText.Contains("stopped after 3 turn(s)")) ("it turns the number asked, watching the machine's mailbox, and says when it stops (" + $sayText + ")")
    if ($script:canDecide) { Check ($sayText.Contains("done ") -and $sayText.Contains("snapshot of 1 open question(s)") -and @(Get-Said $W.store).Count -eq 1) "in those turns the answer landed and the snapshot went out" }
    Check ($script:released -eq 1) ("retired agreement keys are checked when it starts, not on every turn (" + $script:released + ")")
    # THE HEARTBEAT (cli/RelayRun.ps1, A HEARTBEAT): one write a turn, naming this process by pid and start.
    $beat = Read-HordeHeartbeat -Path (Get-HordeRelayRunHeartbeatPath -HordeHome $W.home)
    $selfNow = Get-HordeHeartbeatSelf
    Check ($beat.state -ceq "known" -and $beat.value.pid -eq $PID -and $beat.value.pass -eq 3 -and $beat.value.startedAt -is [datetime] -and $beat.value.startedAt.Ticks -eq $selfNow.startedAt.Ticks) ("a run writes its heartbeat every turn: this process, by pid and start, and the turn it is on (" + $beat.reason + ")")
    Check ($beat.value.tickSeconds -eq 77 -and (Get-HordeRelayRunHeartbeatPath -HordeHome $W.home) -ceq (Join-Path $W.home "relay\run-heartbeat.json")) "the tick it promises is computed from its own settings: no watch, a 60 s longest backoff moved by 20 percent, and 5 s"
    $tickOf = { param([int]$Watch, [int]$Max, [int]$Jitter, [int]$Min) return (Get-HordeRelayRunTickSeconds -WatchMs $Watch -Settings ([pscustomobject]@{ backoffMaxMs = $Max; backoffJitterPercent = $Jitter; minTurnMs = $Min })) }
    Check ((& $tickOf 25000 60000 20 1000) -eq 102 -and (& $tickOf 60000 3600000 0 1000) -eq 3665 -and (& $tickOf 0 0 0 1000) -eq 6) "a longer watch or a longer backoff promises a longer tick, so a run waiting out a backoff as designed is never read as dead"
    # A heartbeat that cannot be written never ends the loop: a folder stands where the file should be.
    $beatFile = Get-HordeRelayRunHeartbeatPath -HordeHome $W.home
    [System.IO.File]::Delete($beatFile)
    [void][System.IO.Directory]::CreateDirectory($beatFile)
    $said = New-Object System.Collections.ArrayList
    try { $r = Invoke-HordeRelayRun -HordeHome $W.home -Connection $W.conn -MaxTurns 3 -Say { param($Line) [void]$said.Add($Line) } } catch { $r = [pscustomobject]@{ turns = -1; stoppedBy = ("threw: " + $_.Exception.Message) } }
    Check ($r.turns -eq 3 -and $r.stoppedBy -ceq "turns" -and @($said | Where-Object { $_ -like "the heartbeat could not be written, and the run goes on without it*" }).Count -eq 1) ("a heartbeat that cannot be written costs the heartbeat and one line, said once - the run turns on (" + (@($said) -join " | ") + ")")
    [System.IO.Directory]::Delete($beatFile)
    if ($script:canDecide) {
        [void](Send-ToMachine $W (Get-Answer $W -Text "in one turn").text)
        $r = Invoke-HordeRelayRun -HordeHome $W.home -Connection $W.conn -MaxTurns 1 -Say { param($Line) [void]$said.Add($Line) }
        Check ($r.turns -eq 1 -and @(@(Get-Said $W.store) | Where-Object { $_.data.text -ceq "in one turn" }).Count -eq 1) "an answer read in a turn lands in that same turn, not the next"
    }
    Request-HordeRelayRunStop -HordeHome $W.home | Out-Null
    $said.Clear()
    $r = Invoke-HordeRelayRun -HordeHome $W.home -Connection $W.conn -MaxTurns 2 -Say { param($Line) [void]$said.Add($Line) }
    Check ((@($said) -join " ").Contains("a stop file from before was removed") -and $r.turns -eq 2) "a stop file left from before is removed at the start, not obeyed"
    $said.Clear()
    $stopNow = { param($Line) [void]$said.Add($Line); if ("$Line".StartsWith("watching")) { [void](Request-HordeRelayRunStop -HordeHome $W.home) } }
    $r = Invoke-HordeRelayRun -HordeHome $W.home -Connection $W.conn -MaxTurns 5 -Say $stopNow
    Check ($r.stoppedBy -ceq "stop file" -and $r.turns -eq 1 -and (Test-Path -LiteralPath (Get-HordeRelayRunStopPath -HordeHome $W.home))) ("a stop asked during a turn ends the run after that turn, and the stop file stays for every other run that started before it (" + $r.stoppedBy + ", " + $r.turns + ")")
    # ONE RUN PER HOME (review of 3d837f0): a run while another holds the home refuses, plainly, and does nothing.
    # The holder here even shares the file: only a run that shares nothing can tell it is there.
    $lockPath = Get-HordeRelayRunLockPath -HordeHome $W.home
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($lockPath))
    $held = New-Object System.IO.FileStream -ArgumentList $lockPath, ([System.IO.FileMode]::OpenOrCreate), ([System.IO.FileAccess]::ReadWrite), ([System.IO.FileShare]::ReadWrite)
    $said.Clear()
    try { $r = Invoke-HordeRelayRun -HordeHome $W.home -Connection $W.conn -MaxTurns 1 -Say { param($Line) [void]$said.Add($Line) } } finally { $held.Dispose() }
    Check ($r.stoppedBy -ceq "locked" -and $r.turns -eq 0 -and (@($said) -join " ").Contains("another relay run is already running on this home")) ("while another run holds the home, a run refuses before its first turn, plainly (" + (@($said) -join " | ") + ")")
    $r = Invoke-HordeRelayRun -HordeHome $W.home -Connection $W.conn -MaxTurns 1 -Say { param($Line) }
    Check ($r.stoppedBy -ceq "turns" -and $r.turns -eq 1) "and once the other has let go, a run starts"
    [System.IO.File]::WriteAllText((Join-Path $W.home "settings\relay-run.json"), '{"schemaVersion": 1, "settings": {"watchMs": 999999}}', $utf8)
    $said.Clear()
    $r = $null
    try { $r = Invoke-HordeRelayRun -HordeHome $W.home -Connection $W.conn -MaxTurns 1 -Say { param($Line) [void]$said.Add($Line) } } catch { $r = [pscustomobject]@{ stoppedBy = ("threw: " + $_.Exception.Message); turns = -1 } }
    Check ($r.stoppedBy -ceq "settings" -and $r.turns -eq 0 -and (@($said) -join " ").Contains("watchMs")) "a refused settings file stops the run before it starts, in the settings' own words"
    [System.IO.File]::WriteAllText((Join-Path $W.home "settings\relay-run.json"), '{"schemaVersion": 1, "settings": {"watchMs": 0, "minTurnMs": 50, "backoffMinMs": 100, "backoffMaxMs": 400, "backoffJitterPercent": 0}}', $utf8)
    Reset-HordeHostileRelay
    Set-HordeHostileRelayFaults -Faults @("throw")
    $slept = New-Object System.Collections.ArrayList
    $said.Clear()
    $hostileConn = Connect-HordeRelay -Name "hostile" -Options @{}
    $r = Invoke-HordeRelayRun -HordeHome $W.home -Connection $hostileConn.value -MaxTurns 4 -Say { param($Line) [void]$said.Add($Line) } -Sleep { param($Ms, $Why) if ("$Why" -cne "pace") { [void]$slept.Add($Ms) } }
    Check ($r.failures -eq 4 -and (@($slept) -join ",") -ceq "100,200,400" -and (@($said) -join " ").Contains("the mailbox could not be read")) ("a relay that keeps failing is waited for 100, 200, 400 ms - doubled, capped - and said each time (" + (@($slept) -join ",") + ")")
    $slept.Clear()
    $heal = { param($Ms, $Why) if ("$Why" -ceq "pace") { return }; [void]$slept.Add($Ms); if ($slept.Count -ge 2) { Set-HordeHostileRelayFaults -Faults @() } }
    $r = Invoke-HordeRelayRun -HordeHome $W.home -Connection $hostileConn.value -MaxTurns 4 -Say { param($Line) [void]$said.Add($Line) } -Sleep $heal
    Set-HordeHostileRelayFaults -Faults @()
    Check ($r.failures -eq 0 -and (@($slept) -join ",") -ceq "100,200") ("once the relay answers again the run goes on, and its failures in a row start again from none (" + (@($slept) -join ",") + ", " + $r.failures + ")")
    # A MINIMUM TURN (finding 5): a watch that returns at once with nothing - watchMs 0, or a relay that
    # does not wait - is not allowed to spin; the turn is padded to minTurnMs.
    [System.IO.File]::WriteAllText((Join-Path $W.home "settings\relay-run.json"), '{"schemaVersion": 1, "settings": {"watchMs": 0, "minTurnMs": 300}}', $utf8)
    $paced = New-Object System.Collections.ArrayList
    $r = Invoke-HordeRelayRun -HordeHome $W.home -Connection $W.conn -MaxTurns 5 -Say { param($Line) } -Sleep { param($Ms, $Why) if ("$Why" -ceq "pace") { [void]$paced.Add($Ms) } }
    Check ($paced.Count -ge 2 -and @($paced | Where-Object { $_ -gt 300 -or $_ -le 0 }).Count -eq 0) ("turns that found nothing at once are padded to the minimum turn, not spun (" + (@($paced) -join ",") + ")")
    [System.IO.File]::WriteAllText((Join-Path $W.home "settings\relay-run.json"), '{"schemaVersion": 1, "settings": {"watchMs": 0, "minTurnMs": 10}}', $utf8)
    $r = $null
    $low = New-Object System.Collections.ArrayList
    try { $r = Invoke-HordeRelayRun -HordeHome $W.home -Connection $W.conn -MaxTurns 1 -Say { param($Line) [void]$low.Add($Line) } } catch { $r = $null }
    Check ($null -ne $r -and $r.stoppedBy -ceq "settings" -and (@($low) -join " ").Contains("minTurnMs")) "a minimum turn below 50 ms is refused by the settings"
    # A STOP DURING A BACKOFF (finding 6): a wait of seconds is slept in slices, and a stop is seen in it.
    [System.IO.File]::WriteAllText((Join-Path $W.home "settings\relay-run.json"), '{"schemaVersion": 1, "settings": {"watchMs": 0, "minTurnMs": 50, "backoffMinMs": 4000, "backoffMaxMs": 4000, "backoffJitterPercent": 0}}', $utf8)
    Set-HordeHostileRelayFaults -Faults @("throw")
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $stopAsk = { param($Line) if ("$Line".Contains("waiting")) { [void](Request-HordeRelayRunStop -HordeHome $W.home) } }
    $r = Invoke-HordeRelayRun -HordeHome $W.home -Connection $hostileConn.value -MaxTurns 5 -Say $stopAsk
    $clock.Stop()
    Set-HordeHostileRelayFaults -Faults @()
    Check ($r.stoppedBy -ceq "stop file" -and $clock.ElapsedMilliseconds -lt 2500) ("a stop asked during a 4 s backoff ends the run within a slice of it (" + $clock.ElapsedMilliseconds + " ms, " + $r.stoppedBy + ")")
    # And asked IN the middle of the wait: the wait is cut after the slice it came in.
    Set-HordeHostileRelayFaults -Faults @("throw")
    $slices = New-Object System.Collections.ArrayList
    $askInSleep = { param($Ms, $Why) if ("$Why" -ceq "backoff") { [void]$slices.Add($Ms); if ($slices.Count -eq 1) { Start-Sleep -Milliseconds 5; [void](Request-HordeRelayRunStop -HordeHome $W.home) } } }
    $r = Invoke-HordeRelayRun -HordeHome $W.home -Connection $hostileConn.value -MaxTurns 5 -Say { param($Line) } -Sleep $askInSleep
    Set-HordeHostileRelayFaults -Faults @()
    Check ($r.stoppedBy -ceq "stop file" -and $slices.Count -eq 1 -and [long]$slices[0] -le 500) ("a 4 s backoff is slept in slices of at most 500 ms, and a stop asked in one ends it after that slice (" + (@($slices) -join ",") + ")")
    # THE TRUST STORE ONCE PER BATCH (finding 5): five answers in one watch read the trusted senders once.
    if ($script:canDecide) {
        $W2 = New-World
        foreach ($i in 1..5) { [void](Send-ToMachine $W2 (Get-Answer $W2 -Text ("batch " + $i)).text) }
        $script:senderReads = 0
        $origFind = ${function:Find-HordeRelayTrustedSenders}
        function Find-HordeRelayTrustedSenders { $script:senderReads++; return (& $origFind @args) }
        $null = Receive-HordeRelayInbox -Context $W2.ctx -TimeoutMs 0
        $inReads = $script:senderReads
        $script:senderReads = 0
        $null = Invoke-HordeRelayUnfinished -Context $W2.ctx
        $openReads = $script:senderReads
        Set-Item -Path Function:\Find-HordeRelayTrustedSenders -Value $origFind
        Check ($inReads -le 1 -and $openReads -le 2 -and @(Get-Said $W2.store).Count -eq 5) ("five answers in one batch read the trust store once to judge and once a channel to open (" + $inReads + ", " + $openReads + ")")
    }
    Remove-Item Function:\Remove-HordeRelayRetiredAgreeKeys

    if ($script:canDecide) {
    Write-Host ""
    Write-Host "--- the founder's rules of 2026-10-12, on the phone: what the snapshot carries, and a part answered by itself ---" -ForegroundColor Cyan
    # A question of parts that matters and blocks, following up the world's first question, which is
    # answered here at the machine first.
    $P = New-World
    Use-World $P
    $null = Invoke-HordeDecision -Operation "say" -Root $P.store -Request @{ id = (New-Id); actor = "warchief"; number = 1; speaker = "founder"; route = "chat-recorded"; text = "Yes, a short chime." }
    $partsAdded = Invoke-HordeDecision -Operation "add" -Root $P.store -Request @{ id = (New-Id); actor = "warchief"; importance = "high"; blocks = "all"; followsUp = 1; question = @{ title = "Three follow-ups to settle about the closing chime, one by one."; kind = "parts"; whatItIs = "Follow-ups."; parts = @("(a) Which chime of the three?", "(b) Should it play on every close?", "(c) How loud should it be?"); group = "voice"; askedBy = "orc-b" } }
    $tick = @(Invoke-Tick $P)
    $mail = @(Get-PhoneMail $P)
    $snap = Open-HordeTestPhoneEnvelope -Phone $P.phone -Text $mail[$mail.Count - 1] -MachineSignPublic $P.id.sign.public
    $q2 = $(if ($snap.ok) { @($snap.body.questions | Where-Object { $_.number -eq 2 })[0] } else { $null })
    Check ($partsAdded.state -ceq "known" -and $partsAdded.value.outcome -ceq "done" -and $snap.ok -and $null -ne $q2) ("CONTROL: the question of parts is added and the phone opens the snapshot that holds it (" + (@($tick) -join " | ") + ")")
    Check ((Get-Member2 $snap.body "answers") -eq 2 -and $snap.body.v -eq 1) "THE SNAPSHOT SAYS WHICH ANSWERS THIS MACHINE READS - up to version 2, a part by itself - and is still a version 1 snapshot, which a phone that knows nothing of it reads as it always did"
    Check ((Get-Member2 $q2 "importance") -ceq "high" -and (Get-Member2 $q2 "importanceShown") -ceq "Important" -and (Get-Member2 $q2 "blocks") -ceq "all" -and (Get-Member2 $q2 "blocksShown") -ceq "Blocks all work") "THE SNAPSHOT CARRIES how much the question matters and how much it blocks, each with its plain words"
    $fu = Get-Member2 $q2 "followsUp"
    Check ($null -ne $fu -and $fu.number -eq 1 -and $fu.title -ceq "Should the closing sound play when the assistant closes?" -and $fu.answer -ceq "Yes, a short chime." -and $fu.answerCut -eq $false) "and the question it follows up, with what he answered there"
    Check ((@(@(Get-Member2 (Get-Member2 $q2 "thread") "parts") | ForEach-Object { $_.letter + ":" + $_.answered }) -join ",") -ceq "a:False,b:False,c:False") "and, for a question of parts, which of them are answered: none yet"
    $q1 = @($snap.body.questions | Where-Object { $_.number -eq 1 })[0]
    Check ($null -ne $q1 -and (Get-Member2 $q1 "importance") -ceq "normal" -and (Get-Member2 $q1 "blocks") -ceq "part" -and (Get-Member2 $q1 "importanceShown") -eq "" -and $null -eq (Get-Member2 $q1 "followsUp") -and $q1.thread.turn -ceq "warchief") "a question asked with neither word reads as normal and part, with no plain words; and the one he has answered is in the snapshot as the keeper's turn, for the phone to keep out of his list"
    # ONE PART, ANSWERED BY ITSELF: a version 2 answer.
    $idB = New-Id
    $b = Get-Answer $P -AnswerId $idB -Number 2 -Part "b" -Text "No, only when she closes it herself."
    [void](Send-ToMachine $P $b.text)
    $t = Invoke-Turn $P
    $said = @(Get-Said $P.store | Where-Object { $_.data.number -eq 2 })
    Check ((Has $t "done") -and (Has $t "question 2 part (b)") -and $said.Count -eq 1 -and (Get-Member2 $said[0].data "part") -ceq "b" -and $said[0].data.text -ceq "No, only when she closes it herself." -and $said[0].data.route -ceq "phone" -and $said[0].actor -ceq "founder") ("A PART ANSWERED ON THE PHONE lands as its own record, naming the part, by the route phone (" + $t.text + ")")
    Check ((Get-Member2 $said[0].data "signedBy") -ceq $P.phone.keyId -and "$(Get-Member2 $said[0].data 'evidence')" -cmatch '\A[0-9a-f]{64}\z') "and it carries what every phone answer carries: the passkey that signed it, and the hash of the proof"
    $shown = Invoke-HordeDecision -Operation "show" -Root $P.store -Request @{ number = 2 }
    Check ($shown.value.question.thread.turn -ceq "founder" -and (@($shown.value.question.thread.parts | ForEach-Object { $_.letter + ":" + $_.answered }) -join ",") -ceq "a:False,b:True,c:False" -and $shown.value.question.thread.messages[0].partWords -ceq "Should it play on every close?") "the list says part (b) is answered, the other two are not, and the question is still his"
    [void](Send-ToMachine $P (Get-Answer $P -AnswerId $idB -Number 2 -Part "b" -Text "No, only when she closes it herself.").text)
    $t = Invoke-Turn $P
    Check ((Has $t "done") -and (Has $t "replayed") -and @(Get-Said $P.store | Where-Object { $_.data.number -eq 2 }).Count -eq 1) ("THE SAME PART'S ANSWER SENT AGAIN, in a new envelope, is the first record answered again: one record (" + $t.text + ")")
    [void](Send-ToMachine $P (Get-Answer $P -AnswerId $idB -Number 2 -Part "c" -Text "No, only when she closes it herself.").text)
    $t = Invoke-Turn $P
    Check ((Has $t "refused") -and (Has $t "already used for a different request") -and @(Get-Said $P.store | Where-Object { $_.data.number -eq 2 }).Count -eq 1) "the same answerId and words for ANOTHER part is a different answer under a used id: refused, and part (c) is not answered by it"
    $tick = @(Invoke-Tick $P)
    $mail = @(Get-PhoneMail $P)
    $snap2 = Open-HordeTestPhoneEnvelope -Phone $P.phone -Text $mail[$mail.Count - 1] -MachineSignPublic $P.id.sign.public
    $q2 = $(if ($snap2.ok) { @($snap2.body.questions | Where-Object { $_.number -eq 2 })[0] } else { $null })
    $m2 = @(@(Get-Member2 (Get-Member2 $q2 "thread") "messages") | Where-Object { $null -ne $_ })
    Check ($m2.Count -eq 1 -and (Get-Member2 $m2[0] "part") -ceq "b" -and (@($q2.thread.parts | ForEach-Object { $_.letter + ":" + $_.answered }) -join ",") -ceq "a:False,b:True,c:False") "THE NEXT SNAPSHOT SHOWS THE PART ANSWERED: the message names its part, and the question says which parts are done"
    foreach ($letter in @("a", "c")) { [void](Send-ToMachine $P (Get-Answer $P -Number 2 -Part $letter -Text ("the answer to " + $letter)).text) }
    $t = Invoke-Turn $P
    $shown = Invoke-HordeDecision -Operation "show" -Root $P.store -Request @{ number = 2 }
    Check ($shown.value.question.thread.turn -ceq "warchief" -and @(Get-Said $P.store | Where-Object { $_.data.number -eq 2 }).Count -eq 3) ("with the last two parts answered, each by its own envelope, the question is the keeper's turn: off his list (" + $t.text + ")")
    # EACH VERSION IS HELD TO EXACTLY ITS OWN MEMBERS, and what this machine does not read is refused by name.
    $count = @(Get-Said $P.store).Count
    foreach ($case in @(
        @{ what = "a version 1 body that names a part"; json = '{"v":1,"answerId":"' + (New-Id) + '","machine":"{machine}","snapshot":"{snapshot}","number":2,"wordingVersion":1,"text":"x","part":"a"}'; says = "the answer's members are" }
        @{ what = "a version 2 body that names no part"; json = '{"v":2,"answerId":"' + (New-Id) + '","machine":"{machine}","snapshot":"{snapshot}","number":2,"wordingVersion":1,"text":"x"}'; says = "the answer's members are" }
        @{ what = "a part that is a capital letter"; json = '{"v":2,"answerId":"' + (New-Id) + '","machine":"{machine}","snapshot":"{snapshot}","number":2,"wordingVersion":1,"text":"x","part":"A"}'; says = "the answer's part is not one lower-case letter" }
        @{ what = "a part that is two letters"; json = '{"v":2,"answerId":"' + (New-Id) + '","machine":"{machine}","snapshot":"{snapshot}","number":2,"wordingVersion":1,"text":"x","part":"ab"}'; says = "the answer's part is not one lower-case letter" }
        @{ what = "a part that is a number"; json = '{"v":2,"answerId":"' + (New-Id) + '","machine":"{machine}","snapshot":"{snapshot}","number":2,"wordingVersion":1,"text":"x","part":1}'; says = "the answer's part is not one lower-case letter" }
        @{ what = "a version this machine does not read"; json = '{"v":3,"answerId":"' + (New-Id) + '","machine":"{machine}","snapshot":"{snapshot}","number":2,"wordingVersion":1,"text":"x","part":"a","more":true}'; says = "the answer is not a version this machine reads (1, 2)" }
        @{ what = "a version that is text"; json = '{"v":"2","answerId":"' + (New-Id) + '","machine":"{machine}","snapshot":"{snapshot}","number":2,"wordingVersion":1,"text":"x","part":"a"}'; says = "the answer is not a version this machine reads" }
        @{ what = "a part the question does not have"; json = '{"v":2,"answerId":"' + (New-Id) + '","machine":"{machine}","snapshot":"{snapshot}","number":2,"wordingVersion":1,"text":"x","part":"d"}'; says = "it answers part (d) of question 2, which has no such part" }
        @{ what = "a part of a question that has none"; json = '{"v":2,"answerId":"' + (New-Id) + '","machine":"{machine}","snapshot":"{snapshot}","number":1,"wordingVersion":1,"text":"x","part":"a"}'; says = "which is not a question of parts that are answered one by one" }
    )) {
        [void](Send-ToMachine $P (Get-RawAnswer $P $case.json).text)
        $t = Invoke-Turn $P
        Check ((Has $t "refused") -and (Has $t $case.says) -and @(Get-Said $P.store).Count -eq $count) ($case.what + " is refused, says why, and nothing lands (" + $t.text + ")")
    }
    # A PHONE THAT KNOWS NOTHING OF PARTS answers all of them in one version 1 message, as it always did.
    $O = New-World
    Use-World $O
    $null = Invoke-HordeDecision -Operation "add" -Root $O.store -Request @{ id = (New-Id); actor = "warchief"; question = @{ title = "Two things to settle about the chime, by an earlier phone."; kind = "parts"; whatItIs = "Follow-ups."; parts = @("(a) Which chime?", "(b) How loud?"); group = "voice"; askedBy = "orc-b" } }
    $null = Invoke-Tick $O
    [void](Send-ToMachine $O (Get-Answer $O -Number 2 -Text ("(a) the second" + "`n" + "(b) quiet")).text)
    $t = Invoke-Turn $O
    $shown = Invoke-HordeDecision -Operation "show" -Root $O.store -Request @{ number = 2 }
    $old = @(Get-Said $O.store | Where-Object { $_.data.number -eq 2 })
    Check ((Has $t "done") -and $old.Count -eq 1 -and $null -eq (Get-Member2 $old[0].data "part") -and $shown.value.question.thread.turn -ceq "warchief") ("AN EARLIER PHONE'S ANSWER TO ALL THE PARTS AT ONCE - version 1, no part - is still taken, as an answer to the whole question (" + $t.text + ")")
    }
} finally {
    Exit-HordeTestEmptyFleet -Pin $fleetPin
    $env:HORDE_HOME = $realHome
    foreach ($w in @($script:worlds)) { Close-HordeRelayRunContext -Context $w.ctx }
    $made = New-Object System.Collections.ArrayList
    foreach ($h in @($script:homes)) {
        foreach ($k in @(Get-TestKeyNames -HordeHome $h)) {
            [void]$made.Add($k)
            try { [void](Remove-HordeRelayKey -Name $k.n -Scope $k.s) } catch { Write-Host ("  cleanup of " + $k.n + " failed: " + $_.Exception.Message) -ForegroundColor Yellow }
        }
    }
    $left = @($made | Where-Object { (Find-HordeRelayCngKey -Name $_.n -Scope $_.s) -cne "" })
    Check ($made.Count -ge 2 -and $left.Count -eq 0) ("every key the suite's homes name is gone (" + $made.Count + " names, " + $left.Count + " left)")
    foreach ($h in @($script:homes)) {
        if ((Split-Path -Leaf $h) -match '^horde-relay-channels-[0-9a-f]{32}$') { Remove-Item -LiteralPath $h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Check (@($script:homes | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 0) "every temporary home is gone"
}
Check ($env:HORDE_HOME -ceq $realHome) "HORDE_HOME is what it was"

if ($script:partial) { Complete-HordeSuite -Success "the channels' own code holds under this runtime; what needs the decisions list was skipped (issue #173)" -PassCode 3 }
Complete-HordeSuite -Success "the phone sees the open questions sealed to it alone, each of its signed answers lands once, the first answer wins, and nothing untrusted lands at all"
