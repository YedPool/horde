# DOES THE RELAY PORT KEEP AN UNTRUSTED RELAY HONEST ABOUT WHAT IT CAN DO, AND NEVER BELIEVE ITS ITEMS?
#
# Relay design 2026-10-09, PR plan item 3 (relays/Port.ps1). A relay is an untrusted mailbox store:
# put an opaque text into a mailbox, read it back by cursor, wait for more, ack what was read. Pinned
# here without any real relay, so every outcome is exact and repeatable:
#   - REGISTRATION AND CAPABILITIES. A relay folder whose capabilities.json breaks
#     schema/relay-capabilities.v1, names another folder, or declares a limit above the port's ceiling
#     is refused. Only "yes" counts. Find-HordeRelay picks by requirements and says why each relay was
#     passed over.
#   - ADDRESSING. A mailbox is <horde>/<reader>, two safe segments; anything else never reaches a relay.
#   - EVERYTHING IS CHECKED BEFORE A RELAY SEES IT, each refusal for its own reason, and the relay is
#     asserted never to have been called.
#   - THE RELAY'S WORD IS CHECKED TOO. An answer that is not a tristate answer, a throw, a malformed
#     put receipt or ack, and every kind of malformed, stale, repeated, conflicting, reordered or
#     excess item (test/lib/HostileRelay.ps1) comes back unknown or is dropped with an anomaly that
#     says why. The cursor never moves backwards and never past an item that was not delivered.
#
# Every conformance case for the real relays is test/test-relay-conformance.ps1.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "relays\Port.ps1")
. (Join-Path $root "test\lib\HostileRelay.ps1")

$fx = Join-Path $here "fixtures\relays\caps"
$script:calls = 0
$script:lastPut = $null

function Reg {
    # A fixture relay whose script blocks the test controls. The defaults are honest and count calls.
    param([string]$Name,
          [scriptblock]$Connect = { param($o) $script:calls++; New-HordeKnown -Value @{ fixture = $true } },
          [scriptblock]$Put = { param($s, $m, $k, $t) $script:calls++; $script:lastPut = @($m, $k, $t); New-HordeKnown -Value ([pscustomobject]@{ seq = [long]1; duplicate = $false }) },
          [scriptblock]$Get = { param($s, $m, $since, $max) $script:calls++; New-HordeKnown -Value ([pscustomobject]@{ items = @() }) },
          [scriptblock]$Watch = { param($s, $m, $since, $max, $ms) $script:calls++; New-HordeKnown -Value ([pscustomobject]@{ items = @() }) },
          [scriptblock]$Ack = { param($s, $m, $through) $script:calls++; New-HordeKnown -Value ([pscustomobject]@{ through = $through }) })
    return (Register-HordeRelay -Folder (Join-Path $fx $Name) -Connect $Connect -Put $Put -Get $Get -Watch $Watch -Ack $Ack)
}
function Says { param($Findings, [string]$Text) return (@($Findings | Where-Object { "$_".Contains($Text) }).Count -gt 0) }
function Conn {
    param([string]$Name)
    $a = Connect-HordeRelay -Name $Name -Options @{}
    if ($a.state -cne "known") { throw ("could not connect to fixture relay " + $Name + ": " + $a.reason) }
    return $a.value
}
$mb = "horde-a/phone"

Write-Host ""
Write-Host "--- a relay folder is registered only with valid capabilities, naming itself, within the ceilings ---" -ForegroundColor Cyan

$good = Reg "fixture-good"
Check ($good.name -ceq "fixture-good") "a folder with valid capabilities registers under its own name"
Check (@(Get-HordeRelayNames) -ccontains "fixture-good") "and is listed"
foreach ($case in @(
        @{ n = "fixture-misnamed"; like = "sits in the folder"; what = "capabilities that name another relay than their folder" },
        @{ n = "fixture-missing-cap"; like = "trim.on.ack"; what = "capabilities missing one of the closed list" },
        @{ n = "fixture-extra-cap"; like = "telepathy"; what = "a capability outside the closed list" },
        @{ n = "fixture-bad-word"; like = "maybe"; what = "a support word outside yes, no, declined, unverified" },
        @{ n = "fixture-no-limits"; like = "limits"; what = "no limits" },
        @{ n = "fixture-text-over-ceiling"; like = "maxTextChars"; what = "a text limit above the envelope's own cap" },
        @{ n = "fixture-batch-over-ceiling"; like = "maxBatch"; what = "a batch limit above the port's ceiling" },
        @{ n = "fixture-watch-over-ceiling"; like = "maxWatchMs"; what = "a watch limit above the port's ceiling" })) {
    Check (Throws { Reg $case.n } $case.like) ("refused: " + $case.what + " (the refusal names '" + $case.like + "')")
    Check (@(Get-HordeRelayNames) -cnotcontains $case.n) ("and " + $case.n + " is not listed")
}
Check (Throws { Register-HordeRelay -Folder (Join-Path $fx "no-such-folder") -Connect {} -Put {} -Get {} -Watch {} -Ack {} } "no capabilities.json") "refused: a folder with no capabilities.json"
Check (Throws { Reg "fixture-good" } "already registered") "refused: a second registration under a name already taken - the first stands"
Check ([object]::ReferenceEquals((Get-HordeRelay -Name "fixture-good"), $good)) "and the first registration is still the one returned"
Check (Throws { Get-HordeRelay -Name "no-such-relay" } "no relay named") "asking for a relay nobody registered is a programming error, and throws"

$c = Get-HordeRelayCeilings
Check ($c.textChars -eq 1414507 -and $c.batch -eq 256 -and $c.watchMs -eq 60000 -and $c.seqMax -eq [long]9007199254740991) ("the ceilings are the envelope's text cap, 256 items, 60 s and 2^53-1 (" + $c.textChars + ", " + $c.batch + ", " + $c.watchMs + ", " + $c.seqMax + ")")
# THE TEXT CEILING IS THE ENVELOPE'S, COPIED NOT LOADED: the port treats texts as opaque and must not
# load the envelope code, so the two numbers are compared here and nowhere else.
. (Join-Path $root "relay\Envelope.ps1")
Check ([long]$c.textChars -eq [long](Get-HordeRelayEnvelopeLimits).textChars) "the port's text ceiling equals relay/Envelope.ps1's text cap"

Write-Host ""
Write-Host "--- only yes counts, and selection says why it passed a relay over ---" -ForegroundColor Cyan

$lo = Reg "fixture-local-only"
$small = Reg "fixture-small-text"
Check ((Test-HordeRelayCapability -Relay $good -Capability "reach.remote") -eq $true) "yes is having it"
Check ((Test-HordeRelayCapability -Relay $lo -Capability "reach.remote") -eq $false) "no is not having it"
Check ((Test-HordeRelayCapability -Relay $lo -Capability "realtime") -eq $false) "unverified is not having it"
Check (Throws { Test-HordeRelayCapability -Relay $good -Capability "telepathy" } "not a relay capability") "a capability outside the list is a programming error, and throws"
$r = Resolve-HordeRelay -Name "fixture-local-only" -Require @("reach.remote")
Check ($r.state -ceq "unknown" -and "$($r.reason)".Contains("reach.remote") -and "$($r.reason)".Contains("one disk")) "a relay lacking a requirement is refused by name, with its own evidence"
$r = Resolve-HordeRelay -Name "fixture-local-only" -Require @("durable")
Check ($r.state -ceq "known" -and [object]::ReferenceEquals($r.value, $lo)) "a relay that has every requirement resolves to itself"
$r = Resolve-HordeRelay -Name "no-such-relay" -Require @()
Check ($r.state -ceq "unknown" -and "$($r.reason)".Contains("no relay named")) "a name nobody registered resolves to unknown"
$f = Find-HordeRelay -Require @("reach.remote", "durable")
Check ($f.state -ceq "known" -and (@($f.value) -ccontains "fixture-good") -and (@($f.value) -cnotcontains "fixture-local-only") -and (@($f.value) -cnotcontains "hostile")) ("Find picks every relay with all requirements and no other (" + (@($f.value) -join ", ") + ")")
Check ((@($f.value) -join ",") -ceq (@(@($f.value) | Sort-Object) -join ",")) "and lists them in name order"
$f = Find-HordeRelay -Require @("durable") -MinTextChars 65
Check ($f.state -ceq "known" -and (@($f.value) -cnotcontains "fixture-small-text") -and (@($f.value) -ccontains "fixture-good")) "Find passes over a relay whose text limit is below what the caller needs"
$f = Find-HordeRelay -Require @("durable") -MinTextChars 2000000
Check ($f.state -ceq "unknown" -and "$($f.reason)".Contains("fixture-small-text") -and "$($f.reason)".Contains("maxTextChars")) "no relay fits: unknown, naming each one and why"
$f = Find-HordeRelay -Require @("trim.on.ack")
Check ($f.state -ceq "known" -and (@($f.value) -cnotcontains "hostile")) "the hostile test relay declines everything, so no requirement ever picks it"

Write-Host ""
Write-Host "--- a mailbox is <horde>/<reader>: two safe segments ---" -ForegroundColor Cyan

Check ((New-HordeRelayMailbox -Horde "work" -Reader "phone") -ceq "work/phone") "a horde and a reader make one mailbox id"
Check ((New-HordeRelayMailbox -Horde "work" -Reader "0123456789abcdef0123456789abcdef") -ceq "work/0123456789abcdef0123456789abcdef") "a machine key id is a reader"
Check (@(Test-HordeRelayMailbox -Mailbox "work/phone").Count -eq 0) "a valid mailbox has no finding"
foreach ($bad in @(
        @{ v = "work"; why = "one segment" },
        @{ v = "a/b/c"; why = "three segments" },
        @{ v = "Work/phone"; why = "upper case" },
        @{ v = "work/../phone"; why = "a dot-dot" },
        @{ v = "work/ph.one"; why = "a dot" },
        @{ v = "work\phone"; why = "a backslash" },
        @{ v = "/phone"; why = "an empty horde" },
        @{ v = "work/"; why = "an empty reader" },
        @{ v = "-work/phone"; why = "a leading hyphen" },
        @{ v = ("work/" + ("a" * 64)); why = "a segment of 64" },
        @{ v = "work/phone`n"; why = "a trailing line break" },
        @{ v = "work/con"; why = "a device name (con)" },
        @{ v = "nul/phone"; why = "a device name (nul)" },
        @{ v = "work/com1"; why = "a device name (com1)" },
        @{ v = "work/lpt9"; why = "a device name (lpt9)" },
        @{ v = ""; why = "empty" })) {
    Check (@(Test-HordeRelayMailbox -Mailbox $bad.v).Count -ge 1) ("refused: a mailbox with " + $bad.why)
}
Check (@(Test-HordeRelayMailbox -Mailbox ("work/" + ("a" * 63))).Count -eq 0) "a segment of 63 is allowed"
Check (@(Test-HordeRelayMailbox -Mailbox "work/console").Count -eq 0) "a name that only starts like a device is allowed"
Check (Throws { New-HordeRelayMailbox -Horde "Work" -Reader "phone" } "not a mailbox") "New-HordeRelayMailbox throws for a bad part: a caller building an id has a bug, not a state"

Write-Host ""
Write-Host "--- the key: the caller's replay key, or the text's own hash ---" -ForegroundColor Cyan

$k = Get-HordeRelayContentKey -Text "abc"
Check ($k -ceq "sha256-ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") "with no key given, the key is sha256- and the text's SHA-256 in lower-case hex (FIPS 180-2 vector for abc)"
$cn = Conn "fixture-good"
$script:calls = 0
$a = Send-HordeRelayItem -Connection $cn -Mailbox $mb -Text "abc"
Check ($a.state -ceq "known" -and $script:lastPut[1] -ceq $k -and $a.value.key -ceq $k) "a put with no key hands the relay the content hash, and says so"
$rk = "0123456789abcdef0123456789abcdef/decisions/7/00112233445566778899aabb"
$a = Send-HordeRelayItem -Connection $cn -Mailbox $mb -Text "abc" -Key $rk
Check ($a.state -ceq "known" -and $script:lastPut[1] -ceq $rk) "an envelope's replay key (from/channel/seq/nonce) is a key"

Write-Host ""
Write-Host "--- a put is checked before the relay sees it ---" -ForegroundColor Cyan

$script:calls = 0
foreach ($bad in @(
        @{ m = "Work/phone"; t = "x"; k = ""; like = "mailbox"; why = "a bad mailbox" },
        @{ m = $mb; t = ""; k = ""; like = "empty"; why = "an empty text" },
        @{ m = $mb; t = ("caf" + [char]0x00e9); k = ""; like = "printable ASCII"; why = "a non-ASCII text" },
        @{ m = $mb; t = "a`nb"; k = ""; like = "printable ASCII"; why = "a text with a line break" },
        @{ m = $mb; t = "a`tb"; k = ""; like = "printable ASCII"; why = "a text with a tab" },
        @{ m = $mb; t = ("x" * 4097); k = ""; like = "4096"; why = "a text over the relay's own limit" },
        @{ m = $mb; t = "x"; k = "has space"; like = "key"; why = "a key with a space" },
        @{ m = $mb; t = "x"; k = ("k" * 161); like = "key"; why = "a key of 161" })) {
    $a = Send-HordeRelayItem -Connection $cn -Mailbox $bad.m -Text $bad.t -Key $bad.k
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains($bad.like)) ("refused before the relay: " + $bad.why + " (" + $a.reason + ")")
}
$a = Send-HordeRelayItem -Connection $cn -Mailbox $mb -Text $null
Check ($a.state -ceq "unknown") "refused before the relay: no text at all"
$a = Send-HordeRelayItem -Connection $cn -Mailbox $mb -Text 42
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("not a string")) "refused before the relay: a number in place of a text"
Check ($script:calls -eq 0) ("and the relay was never called for any of them (" + $script:calls + " calls)")
$a = Send-HordeRelayItem -Connection $cn -Mailbox $mb -Text ("x" * 4096)
Check ($a.state -ceq "known") "a text of exactly the relay's limit is put"
Check ((Send-HordeRelayItem -Connection $cn -Mailbox $mb -Text "x" -Key ("k" * 160)).state -ceq "known") "a key of 160 is put"
Check ((Send-HordeRelayItem -Connection $cn -Mailbox $mb -Text " ~").state -ceq "known") "space and tilde, the ends of printable ASCII, are put"

Write-Host ""
Write-Host "--- the relay's answer to a put is checked ---" -ForegroundColor Cyan

foreach ($case in @(
        @{ n = "throws"; put = { param($s, $m, $k, $t) throw "disk on fire" }; like = "disk on fire" },
        @{ n = "answers a string"; put = { param($s, $m, $k, $t) "ok" }; like = "not an answer" },
        @{ n = "answers absent"; put = { param($s, $m, $k, $t) New-HordeAbsent -Note "?" }; like = "absent" },
        @{ n = "passes on its own unknown"; put = { param($s, $m, $k, $t) New-HordeUnknown -Reason "relay full" }; like = "relay full" },
        @{ n = "gives no seq"; put = { param($s, $m, $k, $t) New-HordeKnown -Value ([pscustomobject]@{ duplicate = $false }) }; like = "seq" },
        @{ n = "gives seq as text"; put = { param($s, $m, $k, $t) New-HordeKnown -Value ([pscustomobject]@{ seq = "1"; duplicate = $false }) }; like = "seq" },
        @{ n = "gives seq 0"; put = { param($s, $m, $k, $t) New-HordeKnown -Value ([pscustomobject]@{ seq = 0; duplicate = $false }) }; like = "seq" },
        @{ n = "gives a seq past 2^53-1"; put = { param($s, $m, $k, $t) New-HordeKnown -Value ([pscustomobject]@{ seq = [long]9007199254740992; duplicate = $false }) }; like = "seq" },
        @{ n = "gives no duplicate flag"; put = { param($s, $m, $k, $t) New-HordeKnown -Value ([pscustomobject]@{ seq = 1 }) }; like = "duplicate" },
        @{ n = "gives duplicate as text"; put = { param($s, $m, $k, $t) New-HordeKnown -Value ([pscustomobject]@{ seq = 1; duplicate = "false" }) }; like = "duplicate" })) {
    $script:HordeRelays.Remove("fixture-good")
    $null = Reg "fixture-good" -Put $case.put
    $cx = Conn "fixture-good"
    $a = Send-HordeRelayItem -Connection $cx -Mailbox $mb -Text "x"
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains($case.like)) ("a relay that " + $case.n + " is unknown with the reason (" + $a.reason + ")")
}
$script:HordeRelays.Remove("fixture-good")
$null = Reg "fixture-good" -Put { param($s, $m, $k, $t) New-HordeKnown -Value ([pscustomobject]@{ seq = [int]5; duplicate = $true }) }
$cx = Conn "fixture-good"
$a = Send-HordeRelayItem -Connection $cx -Mailbox $mb -Text "x" -Key "k1"
Check ($a.state -ceq "known" -and $a.value.seq -eq 5 -and $a.value.seq -is [long] -and $a.value.duplicate -eq $true -and $a.value.mailbox -ceq $mb -and $a.value.key -ceq "k1") "a good receipt is known: mailbox, key, seq (as a long) and duplicate, built by the port"

Write-Host ""
Write-Host "--- only a connection the port made is used ---" -ForegroundColor Cyan

$a = Connect-HordeRelay -Name "no-such-relay" -Options @{}
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("no relay named")) "connecting to a relay nobody registered is unknown"
$script:HordeRelays.Remove("fixture-good")
$null = Reg "fixture-good" -Connect { param($o) throw "cannot reach" }
$a = Connect-HordeRelay -Name "fixture-good" -Options @{}
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("cannot reach")) "a relay whose connect throws is unknown with the reason"
$script:HordeRelays.Remove("fixture-good")
$null = Reg "fixture-good" -Connect { param($o) "a state that is not an answer" }
$a = Connect-HordeRelay -Name "fixture-good" -Options @{}
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("not an answer")) "a relay whose connect answers with something that is not an answer is unknown"
$script:HordeRelays.Remove("fixture-good")
$null = Reg "fixture-good"
$real = Conn "fixture-good"
$fake = [pscustomobject]@{ PSTypeName = "Horde.RelayConnection"; id = $real.id; relay = $real.relay; state = $real.state }
$script:calls = 0
$a = Send-HordeRelayItem -Connection $fake -Mailbox $mb -Text "x"
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("Connect-HordeRelay")) "a look-alike connection, even copying a real one's id, is refused"
$a = Receive-HordeRelayItems -Connection "a string" -Mailbox $mb -Since 0
Check ($a.state -ceq "unknown") "a string in place of a connection is refused"
$a = Receive-HordeRelayItems -Connection $null -Mailbox $mb -Since 0
Check ($a.state -ceq "unknown") "no connection at all is refused"
Check ($script:calls -eq 0) "and the relay was never called"

Write-Host ""
Write-Host "--- a read and a watch are checked before the relay sees them ---" -ForegroundColor Cyan

$script:calls = 0
foreach ($case in @(
        @{ s = [long]-1; x = 1; like = "cursor"; why = "a negative cursor" },
        @{ s = [long]9007199254740992; x = 1; like = "cursor"; why = "a cursor past 2^53-1" },
        @{ s = [long]0; x = 0; like = "batch"; why = "a batch of 0" },
        @{ s = [long]0; x = 9; like = "batch"; why = "a batch over the relay's maxBatch (8)" })) {
    $a = Receive-HordeRelayItems -Connection $real -Mailbox $mb -Since $case.s -Max $case.x
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains($case.like)) ("a read refused: " + $case.why)
}
$a = Receive-HordeRelayItems -Connection $real -Mailbox "nope" -Since 0
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("mailbox")) "a read refused: a bad mailbox"
$a = Wait-HordeRelayItems -Connection $real -Mailbox $mb -Since 0 -TimeoutMs 2001
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("2000")) "a watch refused: a timeout over the relay's maxWatchMs"
$a = Wait-HordeRelayItems -Connection $real -Mailbox $mb -Since 0 -TimeoutMs -1
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("timeout")) "a watch refused: a negative timeout"
$a = Confirm-HordeRelayItems -Connection $real -Mailbox $mb -Through -1
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("cursor")) "an ack refused: a negative cursor"
Check ($script:calls -eq 0) ("and the relay was never called for any of them (" + $script:calls + " calls)")
$a = Receive-HordeRelayItems -Connection $real -Mailbox $mb -Since 0
Check ($a.state -ceq "known" -and @($a.value.items).Count -eq 0 -and $a.value.next -eq 0 -and $a.value.since -eq 0) "an empty read is known: no items, and the cursor stays where it was"
$a = Wait-HordeRelayItems -Connection $real -Mailbox $mb -Since 3 -TimeoutMs 2000
Check ($a.state -ceq "known" -and $a.value.next -eq 3) "an empty watch is known too, and keeps the cursor"
$a = Confirm-HordeRelayItems -Connection $real -Mailbox $mb -Through 3
Check ($a.state -ceq "known" -and $a.value.through -eq 3 -and $a.value.mailbox -ceq $mb) "an ack is known: mailbox and through"
$script:HordeRelays.Remove("fixture-good")
$null = Reg "fixture-good" -Ack { param($s, $m, $through) New-HordeKnown -Value ([pscustomobject]@{ through = $through + 1 }) }
$cx = Conn "fixture-good"
$a = Confirm-HordeRelayItems -Connection $cx -Mailbox $mb -Through 3
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("4")) "a relay that acks a cursor other than the one asked is unknown"
$script:HordeRelays.Remove("fixture-good")
$null = Reg "fixture-good" -Ack { param($s, $m, $through) throw "no ack today" }
$cx = Conn "fixture-good"
$a = Confirm-HordeRelayItems -Connection $cx -Mailbox $mb -Through 3
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("no ack today")) "a relay whose ack throws is unknown with the reason"
$script:HordeRelays.Remove("fixture-good")
$null = Reg "fixture-good" -Watch { param($s, $m, $since, $max, $ms) throw "watch broke" }
$cx = Conn "fixture-good"
$a = Wait-HordeRelayItems -Connection $cx -Mailbox $mb -Since 0 -TimeoutMs 10
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("watch broke")) "a relay whose watch throws is unknown with the reason"
# A REFUSAL'S STATUS AND RETRY-AFTER are carried to the caller (the ADAPTER CONTRACT), so `horde relay
# pair` can wait as long as the relay asks and say a refusal plainly (founder's first live use,
# 2026-10-11); a value that is not a whole number in range is left out, never passed on.
foreach ($c in @(
        @{ what = "a 429 with its Retry-After"; status = 429; after = [long]7000; wantStatus = $true; wantAfter = $true },
        @{ what = "a 401 with none"; status = 401; after = $null; wantStatus = $true; wantAfter = $false },
        @{ what = "a status that is not one"; status = "429; drop"; after = [long]7000; wantStatus = $false; wantAfter = $true },
        @{ what = "a status out of range"; status = 9999; after = $null; wantStatus = $false; wantAfter = $false },
        @{ what = "a negative Retry-After"; status = 429; after = [long]-5; wantStatus = $true; wantAfter = $false },
        @{ what = "a Retry-After over a day"; status = 429; after = [long]86400001; wantStatus = $true; wantAfter = $false })) {
    $script:HordeRelays.Remove("fixture-good")
    $script:refusal = $c
    $null = Reg "fixture-good" -Watch { param($s, $m, $since, $max, $ms) $u = New-HordeUnknown -Reason "refused (a stand-in)"; $u | Add-Member -NotePropertyName status -NotePropertyValue $script:refusal.status; if ($null -ne $script:refusal.after) { $u | Add-Member -NotePropertyName retryAfterMs -NotePropertyValue $script:refusal.after }; return $u }
    try { $a = Wait-HordeRelayItems -Connection (Conn "fixture-good") -Mailbox $mb -Since 0 -TimeoutMs 10 } catch { $a = New-HordeKnown -Value ("it threw: " + $_.Exception.Message) }
    $s = $a.PSObject.Properties["status"]
    $r = $a.PSObject.Properties["retryAfterMs"]
    $okS = $(if ($c.wantStatus) { $null -ne $s -and $s.Value -eq $c.status } else { $null -eq $s })
    $okR = $(if ($c.wantAfter) { $null -ne $r -and $r.Value -eq $c.after } else { $null -eq $r })
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("refused (a stand-in)") -and $okS -and $okR -and (Test-HordeAnswer $a)) ("a watch refused with " + $c.what + " comes back unknown, carrying what holds (status " + $(if ($null -ne $s) { $s.Value } else { "-" }) + ", retryAfterMs " + $(if ($null -ne $r) { $r.Value } else { "-" }) + ")")
}

Write-Host ""
Write-Host "--- the items a relay hands back are never believed ---" -ForegroundColor Cyan

Reset-HordeHostileRelay
$h = Conn "hostile"
$texts = @{}
for ($i = 1; $i -le 6; $i++) {
    $t = "item-" + $i
    $a = Send-HordeRelayItem -Connection $h -Mailbox $mb -Text $t
    $texts[[long]$a.value.seq] = $t
}
function Read-Hostile {
    param([string[]]$Faults, [long]$Since = 0, [int]$Max = 8, [switch]$Watch)
    Set-HordeHostileRelayFaults -Faults $Faults
    if ($Watch) { return (Wait-HordeRelayItems -Connection $h -Mailbox $mb -Since $Since -Max $Max -TimeoutMs 0) }
    return (Receive-HordeRelayItems -Connection $h -Mailbox $mb -Since $Since -Max $Max)
}
function Seqs { param($Answer) return (@($Answer.value.items | ForEach-Object { $_.seq }) -join ",") }

$a = Read-Hostile @()
Check ($a.state -ceq "known" -and (Seqs $a) -ceq "1,2,3,4,5,6" -and $a.value.next -eq 6 -and @($a.value.anomalies).Count -eq 0) "honest: every item in order, the cursor at the last, no anomaly"
Check (@($a.value.items | Where-Object { $texts[[long]$_.seq] -cne $_.text }).Count -eq 0) "and each text is the one put under that seq"
$a = Read-Hostile @("reorder")
Check ((Seqs $a) -ceq "1,2,3,4,5,6" -and $a.value.next -eq 6) "reordered: put back in seq order"
$a = Read-Hostile @("duplicate")
Check ((Seqs $a) -ceq "1,2,3,4,5,6" -and (Says $a.value.anomalies "came twice")) "repeated: each seq once, and the repeat is an anomaly"
$a = Read-Hostile @("stale") -Since 3
Check ((Seqs $a) -ceq "4,5,6" -and $a.value.next -eq 6 -and (Says $a.value.anomalies "at or before the cursor")) "stale items at or before the cursor are dropped, as an anomaly"
$a = Read-Hostile @("conflict")
Check ((Seqs $a) -ceq "1,2,3,4,5,6" -and $a.value.items[0].text -ceq "item-1" -and (Says $a.value.anomalies "other text")) "two texts under one seq: the first stands, the other is an anomaly"
$a = Read-Hostile @("conflict", "reorder")
Check ((Seqs $a) -ceq "1,2,3,4,5,6" -and (Says $a.value.anomalies "other text")) "the conflict is still caught when the forged copy comes first (one of the two is delivered, and the journal judges it)"
$a = Read-Hostile @("drop")
Check ((Seqs $a) -ceq "1,3,5" -and $a.value.next -eq 5 -and (Says $a.value.anomalies "gap")) "thinned: the cursor moves past what came, and every hole between items is an anomaly"
$a = Read-Hostile @("drop") -Since 1
Check ((Seqs $a) -ceq "3,5" -and (Says $a.value.anomalies "gap: seq 2 to 2")) "after a cursor, a hole before the first item is a gap too"
$a = Read-Hostile @("drop") -Since 0
Check (-not (Says $a.value.anomalies "gap: seq 0")) "from cursor 0 nothing before the first item is owed, so no gap is invented"
$a = Read-Hostile @("overbatch") -Max 4
Check ((Seqs $a) -ceq "1,2,3,4" -and $a.value.next -eq 4 -and (Says $a.value.anomalies "more than")) "overfilled: only the batch asked for is delivered, the cursor stops at its end, and the excess is an anomaly"
$a = Read-Hostile @("garbage")
$g = @(New-HordeHostileRelayGarbage -Since 0).Count
Check ((Seqs $a) -ceq "1,2,3,4,5,6" -and @($a.value.anomalies).Count -eq $g) ("garbage: every malformed item is dropped, each as its own anomaly (" + @($a.value.anomalies).Count + " of " + $g + ")")
foreach ($w in @("not an object", "seq", "key", "printable ASCII", "empty", "4096", "not a string")) {
    Check (Says $a.value.anomalies $w) ("  and an anomaly says '" + $w + "'")
}
Check (@($a.value.items | Where-Object { $texts[[long]$_.seq] -cne $_.text }).Count -eq 0) "and no malformed text was delivered in place of a real one"
$a = Read-Hostile @("reorder", "duplicate", "stale", "conflict", "garbage", "drop", "overbatch") -Since 1 -Max 2
Check ($a.state -ceq "known" -and (Seqs $a) -ceq "3,5" -and $a.value.next -eq 5) "every fault at once: still in order, each seq once, nothing stale, nothing malformed, the batch kept"
$a = Read-Hostile @("garbage", "reorder") -Watch
Check ($a.state -ceq "known" -and (Seqs $a) -ceq "1,2,3,4,5,6") "a watch's items are held to the same rules as a read's"
$a = Read-Hostile @("throw")
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("threw on purpose")) "a relay that throws on a read is unknown with the reason"
$a = Read-Hostile @("bad-answer")
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("not an answer")) "a relay that answers a read with something else is unknown"
$script:HordeRelays.Remove("fixture-good")
$null = Reg "fixture-good" -Get { param($s, $m, $since, $max) New-HordeKnown -Value ([pscustomobject]@{ nothing = 1 }) }
$cx = Conn "fixture-good"
$a = Receive-HordeRelayItems -Connection $cx -Mailbox $mb -Since 0
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("items")) "a relay whose read has no items member is unknown"
$script:HordeRelays.Remove("fixture-good")
$null = Reg "fixture-good" -Get { param($s, $m, $since, $max) New-HordeKnown -Value ([pscustomobject]@{ items = [pscustomobject]@{ seq = 1; key = "k"; text = "one" } }) }
$cx = Conn "fixture-good"
$a = Receive-HordeRelayItems -Connection $cx -Mailbox $mb -Since 0
Check ($a.state -ceq "known" -and (Seqs $a) -ceq "1") "a single item not wrapped in a list is still read (PowerShell unrolls one-element arrays)"
Set-HordeHostileRelayFaults -Faults @()

Write-Host ""
Write-Host "--- deploying: only a relay that registered a deploy, and only its answer believed ---" -ForegroundColor Cyan
$siteDir = Join-Path $env:TEMP ("horde-relay-port-site-" + [guid]::NewGuid().ToString("N").Substring(0, 12))
New-Item -ItemType Directory -Path (Join-Path $siteDir "app") -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $siteDir "app\index.html"), "<!doctype html>")
try {
    $script:HordeRelays.Remove("fixture-good")
    $null = Reg "fixture-good"
    Check (@(Get-HordeRelayDeployable) -cnotcontains "fixture-good") "a relay with no deploy block is not deployable"
    $a = Publish-HordeRelay -Name "fixture-good" -Site $siteDir
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("not one that is deployed")) "and publishing it is refused, in words"
    $script:HordeRelays.Remove("fixture-good")
    $script:deployArgs = $null
    $null = Register-HordeRelay -Folder (Join-Path $fx "fixture-good") -Connect { New-HordeKnown -Value 1 } -Put {} -Get {} -Watch {} -Ack {} -Deploy {
        param($Site, $Say, $HordeHome)
        $script:deployArgs = @($Site, $HordeHome)
        & $Say "deploying"
        New-HordeKnown -Value ([pscustomobject]@{ origin = "https://relay.example.test" })
    }
    Check (@(Get-HordeRelayDeployable) -ccontains "fixture-good") "a relay that registered a deploy block is deployable"
    $said = New-Object System.Collections.ArrayList
    $a = Publish-HordeRelay -Name "fixture-good" -Site $siteDir -Say { param($Line) [void]$said.Add($Line) } -HordeHome "C:\home-x"
    Check ($a.state -ceq "known" -and $a.value.origin -ceq "https://relay.example.test" -and $a.value.relay -ceq "fixture-good") "its deploy runs, and its origin comes back"
    Check ($null -ne $script:deployArgs -and $script:deployArgs[0] -ceq $siteDir -and $script:deployArgs[1] -ceq "C:\home-x" -and @($said) -ccontains "deploying") "it is handed the site, the home and the caller's voice"
    $empty = Join-Path $siteDir "empty"
    New-Item -ItemType Directory -Path $empty -Force | Out-Null
    $script:deployArgs = $null
    $a = Publish-HordeRelay -Name "fixture-good" -Site $empty
    Check ($a.state -ceq "unknown" -and $null -eq $script:deployArgs) "a folder with no app in it is refused before the relay is asked"
    foreach ($c in @(
            @{ what = "throws"; b = { param($Site, $Say, $HordeHome) throw "boom" }; like = "failed to deploy" },
            @{ what = "answers with something that is not an answer"; b = { param($Site, $Say, $HordeHome) "done" }; like = "not an answer" },
            @{ what = "answers unknown"; b = { param($Site, $Say, $HordeHome) New-HordeUnknown -Reason "no login" }; like = "no login" },
            @{ what = "answers known with no origin"; b = { param($Site, $Say, $HordeHome) New-HordeKnown -Value ([pscustomobject]@{ x = 1 }) }; like = "https origin" },
            @{ what = "answers an http origin"; b = { param($Site, $Say, $HordeHome) New-HordeKnown -Value ([pscustomobject]@{ origin = "http://relay.example.test" }) }; like = "https origin" })) {
        $script:HordeRelays.Remove("fixture-good")
        $null = Register-HordeRelay -Folder (Join-Path $fx "fixture-good") -Connect { New-HordeKnown -Value 1 } -Put {} -Get {} -Watch {} -Ack {} -Deploy $c.b
        $a = Publish-HordeRelay -Name "fixture-good" -Site $siteDir
        Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains($c.like)) ("a deploy that " + $c.what + " is unknown (" + $a.reason + ")")
    }
    Check ((Publish-HordeRelay -Name "no-such-relay" -Site $siteDir).state -ceq "unknown") "a relay nobody loaded is unknown"
} finally { Remove-Item -LiteralPath $siteDir -Recurse -Force -ErrorAction SilentlyContinue }

Complete-HordeSuite -Success "the relay port refuses what it cannot vouch for, checks every answer, and never believes an item"
