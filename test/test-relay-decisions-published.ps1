# DOES EACH ORC'S PUBLISHED LIST REACH THE FOUNDER'S PHONE, SEALED WITH HIS QUESTIONS, AND ONLY WHAT IT MUST?
#
# T-0328: the founder opened the Thrall's questions on his phone and saw one, while the Thrall had published a list
# of four with `horde decisions publish`. channels/decisions/Channel.ps1 now reads the live lists from fleet.db
# (read only, through fleet-db/decisions-cli.mjs `published --json`) and carries them in every snapshot page as
# "published" (EACH ORC'S PUBLISHED LIST in that file's header). Three parts:
#   1. THE SHAPE, no relay: ConvertTo-HordeDecisionsChannelPublished - the Thrall's lane named "thrall" and an
#      Orc's by its letter; an empty list kept as an empty list; the question an item links carried by number;
#      a secret-looking item sent as its number and a refusal, never its words; 20 items to a list and 16 KB in
#      all, the longest list losing its last item first and saying how many it left out; ASCII only.
#   2. THE READ, no relay: Get-HordeDecisionsChannelPublished against a reader that stands in for the node
#      side - read only when fleet.db changed; a failed read keeps the lists last read and says so once; a first
#      read that fails, or no fleet.db, sends no member at all.
#   3. THE SNAPSHOT, over relays/local, with a real fleet.db seeded by test/fixtures/phone-published-seed.mjs and a
#      phone held in memory (test/lib/RelayPhone.ps1): the phone opens a snapshot whose published member holds
#      the Thrall's list (lane thrall), Orc F's empty list and no entry for Orc G, who never published; what the
#      relay holds is sealed (the list's words are nowhere in a mailbox file); the same lists again send no new
#      snapshot; a changed list sends one; a home with no fleet.db sends none of it.
# Each refusal has its must-accept twin. NODE 24 IS NEEDED for part 3 (node:sqlite): without it that part says so.
#
# EVERY HORDE HOME IS A FOLDER OF THE SUITE'S OWN under %TEMP% (CONTRIBUTING 9), never the real one, and every key
# is made with the software provider and removed at the end. Off Windows there is no key store: the suite says so
# and exits 3.

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
$node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$seedJs = Join-Path $root "test\fixtures\phone-published-seed.mjs"

if ((Get-HordeRelayKeyStore).state -cne "known") {
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Complete-HordeSuite -Success "no key store here: no machine identity can be made, so nothing was run" -PassCode 3
}

function New-TestHome {
    $h = Join-Path $env:TEMP ("horde-relay-published-" + [guid]::NewGuid().ToString("N"))
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
    # A machine with an identity, a phone paired with its identity key trusted, a local relay and a run context.
    $h = New-TestHome
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
    $w = [pscustomobject]@{ home = $h; id = $id.value; phone = $phone; conn = $c.value; ctx = $ctx.value }
    [void]$script:worlds.Add($w)
    return $w
}
function Get-PhoneSnapshot {
    # The newest snapshot page in the phone's mailbox, opened by the phone: { body; mail } or $null.
    param($World)
    $r = Receive-HordeRelayItems -Connection $World.conn -Mailbox "work/phone" -Since 0
    $mail = @($r.value.items | ForEach-Object { $_.text })
    if ($mail.Count -eq 0) { return $null }
    $o = Open-HordeTestPhoneEnvelope -Phone $World.phone -Text $mail[$mail.Count - 1] -MachineSignPublic $World.id.sign.public
    if (-not $o.ok) { return $null }
    return [pscustomobject]@{ body = $o.body; mail = $mail }
}
function Get-Published {
    # The published member of the newest snapshot, as an array of lists ($null for no member).
    param($World)
    $s = Get-PhoneSnapshot $World
    if ($null -eq $s -or -not (Test-HordeTestMember $s.body "published")) { return $null }
    return @($s.body.published | ForEach-Object { $_ })
}
function Write-Items { param([string]$Name, [string]$Json) $p = Join-Path $env:TEMP ("horde-published-" + $Name + "-" + [guid]::NewGuid().ToString("N") + ".json"); [System.IO.File]::WriteAllText($p, $Json, $utf8); return $p }
function Invoke-Seed { param([string[]]$SeedArgs) & $node.Source $seedJs @SeedArgs; return ($LASTEXITCODE -eq 0) }
function New-FleetList {
    param([string]$Orc, [string]$Rank = "orc", [int]$Items = 1, [string]$Text = "Item")
    $list = @()
    for ($i = 1; $i -le $Items; $i++) { $list += [pscustomobject]@{ position = $i; questionNumber = $null; text = ($Text + " " + $i); recommendation = $null; importance = $null; blocks = $null } }
    return [pscustomobject]@{ orc = $Orc; rank = $Rank; snapshot = "X"; publishedAt = "2026-10-21T17:01:31.698Z"; confirmedAt = "2026-10-21T18:22:18.181Z"; count = $Items; items = $list }
}

try {
    Write-Host ""
    Write-Host "--- 1. the shape of the member ---" -ForegroundColor Cyan
    $thrallList = [pscustomobject]@{ orc = "M"; rank = "thrall"; snapshot = "S1"; publishedAt = "2026-10-21T17:01:31.698Z"; confirmedAt = "2026-10-21T18:22:18.181Z"; count = 2; items = @(
            [pscustomobject]@{ position = 1; questionNumber = $null; text = "Sales queue: forward the page?"; recommendation = $null; importance = "high"; blocks = "part" },
            [pscustomobject]@{ position = 2; questionNumber = 31; text = "Q31 (b): end the call?"; recommendation = "yes"; importance = "normal"; blocks = "none" }) }
    $emptyList = [pscustomobject]@{ orc = "E"; rank = "orc"; snapshot = "S2"; publishedAt = "2026-10-21T16:24:27.644Z"; confirmedAt = "2026-10-21T16:56:17.608Z"; count = 0; items = @() }
    $text = ConvertTo-HordeDecisionsChannelPublished -Lists @($thrallList, $emptyList)
    $m = @(ConvertFrom-HordeJson $text | ForEach-Object { $_ })
    Check ($m.Count -eq 2 -and $m[0].lane -ceq "thrall" -and $m[0].orc -ceq "M" -and $m[0].count -eq 2 -and $m[0].more -eq 0 -and $m[0].publishedAt -ceq "2026-10-21T17:01:31.698Z" -and $m[0].confirmedAt -ceq "2026-10-21T18:22:18.181Z") ("the Thrall's list is the lane 'thrall', with both times and its count (" + $text.Substring(0, [Math]::Min(160, $text.Length)) + ")")
    $i1 = @($m[0].items | ForEach-Object { $_ })
    Check ($i1.Count -eq 2 -and $i1[0].text -ceq "Sales queue: forward the page?" -and $i1[0].importance -ceq "high" -and $i1[0].blocks -ceq "part" -and $null -eq $i1[0].question -and $null -eq $i1[0].recommendation -and $i1[1].question -eq 31 -and $i1[1].recommendation -ceq "yes") "each item carries its text, recommendation, importance, blocking and the question it links, null where there is none"
    Check ($m[1].lane -ceq "E" -and $m[1].count -eq 0 -and @($m[1].items).Count -eq 0 -and $text.Contains('"items":[]')) "AN EMPTY LIST is a list with no items - not left out, not a list of one empty item"
    Check ((ConvertTo-HordeDecisionsChannelPublished -Lists @()) -ceq "[]") "no lists at all is an empty array"
    $oneItem = ConvertTo-HordeDecisionsChannelPublished -Lists @((New-FleetList -Orc "F" -Items 1))
    Check ($oneItem.Contains('"items":[{') -and (@(ConvertFrom-HordeJson $oneItem | ForEach-Object { $_ })[0].items | Measure-Object).Count -eq 1) "a list of one item is still an array of one (PowerShell 5.1 unrolls it if not careful)"

    # A SECRET NEVER LEAVES: built from pieces so this file holds none.
    $key = "AKIA" + "IOSFODNN7" + "EXAMPLE"
    Check ((Find-HordeSecretKind -Text $key) -cne "") "CONTROL: the secret check sees the key the suite uses"
    $leaky = [pscustomobject]@{ orc = "F"; rank = "orc"; snapshot = "S3"; publishedAt = "2026-10-21T17:00:00.000Z"; confirmedAt = "2026-10-21T17:00:00.000Z"; count = 2; items = @(
            [pscustomobject]@{ position = 1; questionNumber = 5; text = ("Use this key " + $key + " for the deploy?"); recommendation = "yes"; importance = "high"; blocks = "all" },
            [pscustomobject]@{ position = 2; questionNumber = $null; text = "A plain question?"; recommendation = $null; importance = $null; blocks = $null }) }
    $t = ConvertTo-HordeDecisionsChannelPublished -Lists @($leaky)
    $ls = @(ConvertFrom-HordeJson $t | ForEach-Object { $_ })[0]
    $li = @($ls.items | ForEach-Object { $_ })
    Check (-not $t.Contains($key) -and -not $t.Contains("AKIA") -and $li[0].question -eq 5 -and $li[0].text.Contains("not sent") -and $null -eq $li[0].recommendation -and $null -eq $li[0].importance) "MUST-REFUSE: an item that looks like a secret is sent as its number and a refusal - its words, its recommendation and its levels do not travel"
    Check ($li[1].text -ceq "A plain question?") "MUST-ACCEPT TWIN: the plain item beside it is sent as it is"

    # THE SIZE.
    $big = ConvertTo-HordeDecisionsChannelPublished -Lists @((New-FleetList -Orc "F" -Items 25))
    $bm = @(ConvertFrom-HordeJson $big | ForEach-Object { $_ })[0]
    Check (@($bm.items).Count -eq 20 -and $bm.more -eq 5 -and $bm.count -eq 25) "A LIST OF 25 sends 20 and says 5 more (and its true count, 25)"
    $twenty = ConvertTo-HordeDecisionsChannelPublished -Lists @((New-FleetList -Orc "F" -Items 20))
    Check ((@(ConvertFrom-HordeJson $twenty | ForEach-Object { $_ })[0].more) -eq 0) "MUST-ACCEPT TWIN: a list of exactly 20 loses nothing"
    $fat = New-FleetList -Orc "F" -Items 20 -Text ("x" * 390)
    $fat2 = New-FleetList -Orc "G" -Items 6 -Text ("y" * 390)
    $capped = ConvertTo-HordeDecisionsChannelPublished -Lists @($fat, $fat2, (New-FleetList -Orc "H" -Items 20 -Text ("z" * 390)), (New-FleetList -Orc "J" -Items 20 -Text ("w" * 390)))
    $cm = @(ConvertFrom-HordeJson $capped | ForEach-Object { $_ })
    $utf8n = New-Object System.Text.UTF8Encoding -ArgumentList $false
    Check ($utf8n.GetByteCount($capped) -le 16384 -and $cm[0].more -gt 0 -and @($cm[0].items).Count + $cm[0].more -eq 20 -and $cm[1].more -eq 0 -and @($cm[1].items).Count -eq 6) ("OVER 16 KB, the longest lists lose their last items first, each list saying how many it lost, the short one untouched (" + $utf8n.GetByteCount($capped) + " bytes; F kept " + @($cm[0].items).Count + ", G kept " + @($cm[1].items).Count + ")")
    Check (@($cm[0].items)[0].text.EndsWith(" 1") -and @($cm[0].items)[@($cm[0].items).Count - 1].text.EndsWith(" " + @($cm[0].items).Count) -and @($cm[0].items).Count -lt 20) "and it is the END of the list that goes: the first items are the ones kept"
    $uni = New-FleetList -Orc "F" -Items 1 -Text ("caf" + [char]0x00E9)
    $ut = ConvertTo-HordeDecisionsChannelPublished -Lists @($uni)
    Check ($ut -cmatch '\A[\x20-\x7E]*\z' -and $ut.Contains('caf' + [char]92 + 'u00e9')) "whatever is not plain ASCII is escaped"

    Write-Host ""
    Write-Host "--- 2. the read: only when fleet.db changed, and a failed read keeps what was read ---" -ForegroundColor Cyan
    $rh = New-TestHome
    $script:reads = 0
    $script:answer = [pscustomobject]@{ code = 0; out = '{"lists":[{"orc":"M","rank":"thrall","snapshot":"S","publishedAt":"2026-10-21T17:01:31.698Z","confirmedAt":"2026-10-21T17:01:31.698Z","count":1,"items":[{"position":1,"questionNumber":null,"text":"First?","recommendation":null,"importance":null,"blocks":null}]}]}'; err = "" }
    $script:HordeDecisionsChannelPublishedReader = { param($HordeHome) $script:reads++; return $script:answer }
    $mine = @{}
    $ctx = [pscustomobject]@{ hordeHome = $rh }
    $r0 = Get-HordeDecisionsChannelPublished -Context $ctx -Mine $mine
    Check ($r0.text -ceq "" -and $r0.problem -ceq "" -and $script:reads -eq 0) "NO FLEET.DB: no member, no problem, and the reader was not asked"
    [System.IO.File]::WriteAllBytes((Join-Path $rh "fleet.db"), [byte[]](1, 2, 3))
    $r1 = Get-HordeDecisionsChannelPublished -Context $ctx -Mine $mine
    Check ($script:reads -eq 1 -and $r1.text.Contains('"lane":"thrall"') -and $r1.text.Contains("First?") -and $r1.problem -ceq "") "a fleet.db that is there is read once and its lists are the member"
    $r2 = Get-HordeDecisionsChannelPublished -Context $ctx -Mine $mine
    Check ($script:reads -eq 1 -and $r2.text -ceq $r1.text) "THE SAME FILE is not read again (the reader was asked once)"
    [System.IO.File]::WriteAllBytes((Join-Path $rh "fleet.db"), [byte[]](1, 2, 3, 4))
    $script:answer = [pscustomobject]@{ code = 0; out = '{"lists":[]}'; err = "" }
    $r3 = Get-HordeDecisionsChannelPublished -Context $ctx -Mine $mine
    Check ($script:reads -eq 2 -and $r3.text -ceq "[]" -and $r3.problem -ceq "") "MUST-READ TWIN: a fleet.db that changed is read again, and no lists at all is the member [] - none published, which is not 'no member'"
    [System.IO.File]::WriteAllBytes((Join-Path $rh "fleet.db"), [byte[]](1, 2, 3, 4, 5))
    $script:answer = [pscustomobject]@{ code = 1; out = ""; err = "fleet.db: database is locked" }
    $r4 = Get-HordeDecisionsChannelPublished -Context $ctx -Mine $mine
    Check ($r4.text -ceq "[]" -and $r4.problem.Contains("database is locked")) ("A READ THAT FAILS keeps the lists last read and says why (" + $r4.problem + ")")
    [System.IO.File]::WriteAllBytes((Join-Path $rh "fleet.db"), [byte[]](1, 2, 3, 4, 5, 6))
    $r5 = Get-HordeDecisionsChannelPublished -Context $ctx -Mine $mine
    Check ($r5.text -ceq "[]" -and $r5.problem -ceq "") "and says it once: the same trouble again is not said again"
    $script:answer = [pscustomobject]@{ code = 0; out = "not json at all"; err = "" }
    [System.IO.File]::WriteAllBytes((Join-Path $rh "fleet.db"), [byte[]](1, 2, 3, 4, 5, 6, 7))
    $r6 = Get-HordeDecisionsChannelPublished -Context $ctx -Mine $mine
    Check ($r6.text -ceq "[]" -and $r6.problem.StartsWith("the published lists could not be read")) "an answer that is not the lists is a failed read too, never a member"
    $fresh = @{}
    $rh2 = New-TestHome
    [System.IO.File]::WriteAllBytes((Join-Path $rh2 "fleet.db"), [byte[]](9))
    $script:answer = [pscustomobject]@{ code = 1; out = ""; err = "fleet.db: no" }
    $r7 = Get-HordeDecisionsChannelPublished -Context ([pscustomobject]@{ hordeHome = $rh2 }) -Mine $fresh
    Check ($r7.text -ceq "" -and $r7.problem.Contains("fleet.db: no")) "A FIRST READ THAT FAILS sends no member at all, and says why"
    $script:HordeDecisionsChannelPublishedReader = $null

    Write-Host ""
    Write-Host "--- 3. the snapshot: sealed to the phone, with a real fleet.db ---" -ForegroundColor Cyan
    if ($null -eq $node) {
        Write-Host "  [SKIP] no node here: fleet.db cannot run" -ForegroundColor Yellow
    } else {
        $W = New-World
        $thrallFile = Write-Items "thrall" '[{"text":"Sales queue: forward the contract page?","recommendation":"yes, today","importance":"high","blocks":"part"},{"questionNumber":1,"text":"Closing sound: play it?","recommendation":"play it","importance":"normal","blocks":"none"}]'
        $emptyFile = Write-Items "empty" '[]'
        Check (Invoke-Seed @("seed", $W.home)) "CONTROL: fleet.db is seeded in the machine's home"
        Check (Invoke-Seed @("publish", $W.home, "thrall", $thrallFile)) "CONTROL: the Thrall publishes a list of two, one linking question 1"
        Check (Invoke-Seed @("publish", $W.home, "F", $emptyFile)) "CONTROL: Orc F publishes an empty list (Orc G never publishes)"
        $env:HORDE_HOME = $W.home
        $tick = Invoke-HordeRelayChannelTicks -Context $W.ctx
        $pub = Get-Published $W
        Check ($null -ne $pub -and $pub.Count -eq 2) ("the phone opens a snapshot with the published member: two lists (" + $(if ($null -eq $pub) { "no member" } else { $pub.Count }) + ")")
        $tl = @($pub | Where-Object { $_.lane -ceq "thrall" })
        $fl = @($pub | Where-Object { $_.lane -ceq "F" })
        Check ($tl.Count -eq 1 -and @($tl[0].items).Count -eq 2 -and @($tl[0].items)[0].text -ceq "Sales queue: forward the contract page?" -and @($tl[0].items)[1].question -eq 1 -and @($tl[0].items)[1].recommendation -ceq "play it") "the Thrall's list is there, with its recommendation, and the item that links question 1 says so"
        Check ($fl.Count -eq 1 -and @($fl[0].items).Count -eq 0 -and $fl[0].count -eq 0) "Orc F's empty list is there, empty"
        Check (@($pub | Where-Object { $_.orc -ceq "G" }).Count -eq 0) "Orc G, who never published, has no entry"
        $s = Get-PhoneSnapshot $W
        $allMail = ($s.mail -join "`n")
        Check (-not $allMail.Contains("contract page") -and -not $allMail.Contains("Sales queue") -and -not $allMail.Contains("published")) "SEALED: the list's words, and the word 'published', are nowhere in what the relay holds"
        $first = $s.body.snapshot
        $null = Invoke-HordeRelayChannelTicks -Context $W.ctx
        Check ((Get-PhoneSnapshot $W).body.snapshot -ceq $first -and $s.mail.Count -eq (Get-PhoneSnapshot $W).mail.Count) "THE SAME LISTS send no new snapshot"
        $conf = Invoke-Seed @("confirm", $W.home, "thrall", $thrallFile)
        $null = Invoke-HordeRelayChannelTicks -Context $W.ctx
        $afterConfirm = Get-PhoneSnapshot $W
        $tc = @($afterConfirm.body.published | Where-Object { $_.lane -ceq "thrall" })
        Check ($conf -and $afterConfirm.body.snapshot -cne $first -and $tc.Count -eq 1 -and $tc[0].confirmedAt -cne $tl[0].confirmedAt -and $tc[0].publishedAt -ceq $tl[0].publishedAt) "an Orc confirming its list again (nothing changed) sends a new snapshot with the later 'checked' time and the same published time"
        $thrallFile2 = Write-Items "thrall2" '[{"text":"Sales queue: forward the contract page, v3?","recommendation":"yes, today"}]'
        Check (Invoke-Seed @("publish", $W.home, "thrall", $thrallFile2)) "the Thrall publishes a changed list"
        $null = Invoke-HordeRelayChannelTicks -Context $W.ctx
        $changed = @((Get-Published $W) | Where-Object { $_.lane -ceq "thrall" })
        Check ($changed.Count -eq 1 -and @($changed[0].items).Count -eq 1 -and @($changed[0].items)[0].text.Contains("v3")) "a changed list is sent: one new snapshot with the new words and the dropped item gone"

        $B = New-World
        $env:HORDE_HOME = $B.home
        $null = Invoke-HordeRelayChannelTicks -Context $B.ctx
        $bare = Get-PhoneSnapshot $B
        Check ($null -ne $bare -and -not (Test-HordeTestMember $bare.body "published")) "MUST-STAY-OUT: a machine with no fleet.db sends a snapshot with no published member at all (the phone says it has none to show)"
    }
} finally {
    $env:HORDE_HOME = $realHome
    $script:HordeDecisionsChannelPublishedReader = $null
    foreach ($w in @($script:worlds)) { Close-HordeRelayRunContext -Context $w.ctx }
    $made = New-Object System.Collections.ArrayList
    foreach ($h in @($script:homes)) {
        foreach ($k in @(Get-TestKeyNames -HordeHome $h)) {
            [void]$made.Add($k)
            try { [void](Remove-HordeRelayKey -Name $k.n -Scope $k.s) } catch { Write-Host ("  cleanup of " + $k.n + " failed: " + $_.Exception.Message) -ForegroundColor Yellow }
        }
    }
    $left = @($made | Where-Object { (Find-HordeRelayCngKey -Name $_.n -Scope $_.s) -cne "" })
    Check ($left.Count -eq 0) ("every key the suite's homes name is gone (" + $made.Count + " names, " + $left.Count + " left)")
    foreach ($h in @($script:homes)) {
        if ((Split-Path -Leaf $h) -match '^horde-relay-published-[0-9a-f]{32}$') { Remove-Item -LiteralPath $h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Get-ChildItem -LiteralPath $env:TEMP -Filter "horde-published-*.json" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Check (@($script:homes | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 0) "every temporary home is gone"
    Exit-HordeTestEmptyFleet -Pin $fleetPin
}
Check ($env:HORDE_HOME -ceq $realHome) "HORDE_HOME is what it was"
Complete-HordeSuite -Success "each Orc's published list reaches the phone sealed with the questions: the Thrall's as a lane of its own, an empty list as empty, a secret never, 20 items and 16 KB at most, read from fleet.db only when it changed, and none at all where there is no fleet.db"
