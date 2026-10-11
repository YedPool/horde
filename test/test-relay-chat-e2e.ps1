# DOES A PAIRED PHONE SEE ITS THRALL'S TURNS, AND DOES ITS SIGNED LINE REACH THE THRALL EXACTLY ONCE -
# END TO END, THROUGH THE REAL horde COMMAND?
#
# The chat channel's end-to-end scenario (relay design 2026-10-09, PR plan item 10; CONTRIBUTING 2).
#   - THE PHONE is test/fixtures/relay/phone/phone.mjs: a passkey and a phone identity key made by
#     WebCrypto, every byte built by relay/js/protocol.js, the module the PWA runs.
#   - THE MACHINE is the shipped horde.ps1, `horde relay run`, as its own process, over relays/local in
#     the suite's folder.
#   - THE THRALL is a synthetic fleet, and THE MESSENGER a stand-in that records every post in its own
#     folder (test/lib/ChatFleet.ps1): no real Thrall can be found and nothing reaches a real session.
#   1. the phone pairs and announces its key; a run sends the Thrall's last turns, from the end, which
#      the phone opens; new turns come after;
#   2. the phone's signed line, bound to the horde, the machine and the Thrall's session, is posted to
#      the Thrall's session once, his words under the line's header, and a receipt comes back;
#   3. the same envelope again, a re-signed copy and the same line resent: still one post;
#   4. a line from an unknown, a pending and a revoked passkey, and one signed by a TRUSTED peer machine,
#      are refused, and nothing more is posted;
#   5. a clear: the Thrall's last words before it reach the phone, then the new session, and a line
#      written to the old session is refused as ended.
#
# NODE IS NEEDED for the phone. Without it the suite says so and exits 3, a partial run, never 0.

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
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "test\lib\RelayPhone.ps1")
. (Join-Path $root "test\lib\ChatFleet.ps1")
Set-StrictMode -Version Latest

$node = Get-Command -Name "node" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $node) {
    Write-Host "  [SKIP] node is not installed here, so there is no phone to run" -ForegroundColor Yellow
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Exit-HordeTestEmptyFleet -Pin $fleetPin
    Complete-HordeSuite -Success "skipped: no node, so no phone" -PassCode 3
}
if ((Get-HordeRelayKeyStore).state -cne "known") {
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Exit-HordeTestEmptyFleet -Pin $fleetPin
    Complete-HordeSuite -Success "skipped: no key store here, so no machine identity" -PassCode 3
}

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$realHome = $env:HORDE_HOME
$work = Join-Path $env:TEMP ("horde-chat-e2e-" + [guid]::NewGuid().ToString("N"))
$hh = Join-Path $work "home"
$mailboxes = Join-Path $work "relay"
$phoneDir = Join-Path $work "phone"
$fake = Join-Path $work "fleet-messenger"
New-Item -ItemType Directory -Path (Join-Path $hh "settings"), $mailboxes, $phoneDir, $fake -Force | Out-Null
$script:n = 0
$phoneScript = Join-Path $here "fixtures\relay\phone\phone.mjs"
$keysMade = New-Object System.Collections.ArrayList
$thrall = $null

function Invoke-Phone {
    # One command of a phone (phone.mjs) whose keys are in -State; the output, parsed.
    param([string]$Command, [hashtable]$In = @{}, [string]$State = "state")
    $script:n++
    $inFile = Join-Path $phoneDir ("in-" + $script:n + ".json")
    $outFile = Join-Path $phoneDir ("out-" + $script:n + ".json")
    [System.IO.File]::WriteAllText($inFile, (ConvertTo-Json -InputObject $In -Compress -Depth 6), $utf8)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $node.Source
    $psi.Arguments = '"' + $phoneScript + '" ' + $Command + ' "' + (Join-Path $phoneDir ($State + ".json")) + '" "' + $inFile + '" "' + $outFile + '"'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $null = $p.StandardOutput.ReadToEnd()
    if (-not $p.WaitForExit(60000)) { $p.Kill(); throw "the phone did not answer in 60 s" }
    if ($p.ExitCode -ne 0) { throw ("the phone failed: " + $errTask.Result) }
    return ([System.IO.File]::ReadAllText($outFile, $utf8) | ConvertFrom-Json)
}
function Invoke-Run {
    # `horde relay run` as its own process; the fleet root it inherits is the synthetic one.
    param([int]$Turns = 1)
    return (Invoke-HordeCliProcess -Root $root -HordeArgs @("relay", "run", "-Relay", "local", "-RelayRoot", $mailboxes, "-MaxTurns", "" + $Turns) -Env @{ HORDE_HOME = $hh })
}
$script:seen = 0
function Get-ChatMail {
    # What the phone opens of the chat envelopes in its mailbox since the last look.
    param($Connection)
    $r = Receive-HordeRelayItems -Connection $Connection -Mailbox "work/phone" -Since $script:seen
    if ($r.state -cne "known") { return @() }
    $out = New-Object System.Collections.ArrayList
    foreach ($it in @($r.value.items)) {
        $script:seen = [long]$it.seq
        $o = Invoke-Phone "open" @{ envelope = $it.text }
        if ($o.ok -and $o.header.channel -ceq "chat") { [void]$out.Add($o.body) }
    }
    return @($out.ToArray())
}
function Get-Texts { param($Bodies) return (@($Bodies | Where-Object { $_.kind -ceq "chat-turns" } | ForEach-Object { @($_.turns) } | ForEach-Object { $_.text }) -join "|") }
function Get-Posts { return @(Get-HordeTestFleetPosts -Folder $fake) }
function Send-Line {
    param($Connection, [string]$Mailbox, $Line)
    return (Send-HordeRelayItem -Connection $Connection -Mailbox $Mailbox -Text $Line.envelope -Key $Line.key)
}

try {
    $env:HORDE_HOME = $hh
    [System.IO.File]::WriteAllText((Join-Path $hh "settings\relay.json"), '{"schemaVersion": 1, "settings": {"horde": "work"}}', $utf8)
    [System.IO.File]::WriteAllText((Join-Path $hh "settings\relay-run.json"), '{"schemaVersion": 1, "settings": {"watchMs": 200}}', $utf8)
    [System.IO.File]::WriteAllText((Join-Path $hh "settings\relay-chat.json"), '{"schemaVersion": 1, "settings": {"sendIntervalMs": 0, "startTurns": 3}}', $utf8)

    $chatFixtures = @(Get-HordeTestChatFixtureFiles | ForEach-Object { . $_ -Root $root })
    $thrall = New-HordeTestChatThrall -Fixtures $chatFixtures
    Check ($null -ne $thrall) "CONTROL: a conversation adapter's fixture made a synthetic fleet with a Thrall"
    Add-HordeTestChatTurns -Thrall $thrall -Turns @(1..5 | ForEach-Object { @{ role = $(if ($_ % 2) { "user" } else { "assistant" }); text = ("synthetic turn " + $_) } })
    $src = Find-HordeConversationSource -Fleet "work" -Require @() -Refuse @()
    Check ($src.state -ceq "known" -and $src.value.session -ceq $thrall.state.session) ("CONTROL: the synthetic fleet's Thrall is the one found, and no other (" + $src.state + ")")
    $messengerName = New-HordeTestFleetMessenger -HordeHome $hh -Folder $fake
    Check ($messengerName -cne "") ("CONTROL: the messenger that ships a stand-in is pointed at it (" + $messengerName + ")")

    $id = New-HordeRelayMachineIdentity -HordeHome $hh -Provider "software"
    Check ($id.state -ceq "known") "CONTROL: the machine has its relay identity"
    [void]$keysMade.Add(@{ n = $id.value.sign.name; s = $id.value.scope }); [void]$keysMade.Add(@{ n = $id.value.agree.name; s = $id.value.scope })
    $c = Connect-HordeRelay -Name "local" -Options @{ root = $mailboxes }
    $machineBox = $id.value.mailbox

    Write-Host ""
    Write-Host "--- 1. the phone pairs; the Thrall's last turns reach it, then the new ones ---" -ForegroundColor Cyan
    $offer = New-HordeRelayPairingOffer -HordeHome $hh -RpId "relay.example.test" -Origins @("https://relay.example.test")
    $reg = Invoke-Phone "register" @{ offer = $offer.value.text; label = "Founder phone" }
    $done = Complete-HordeRelayPairing -HordeHome $hh -Response $reg.response
    $confirmed = Confirm-HordeRelayDevice -HordeHome $hh -Id $done.value.device.id -Fingerprint $reg.fingerprint
    Check ($confirmed.ok -and $confirmed.value.device.state -ceq "trusted") "CONTROL: the phone's passkey is trusted"
    $pk = Invoke-Phone "phone-key"
    [void](Send-HordeRelayItem -Connection $c.value -Mailbox $machineBox -Text $pk.envelope -Key $pk.key)
    $run = Invoke-Run -Turns 2
    Check ($run.code -eq 0 -and $run.out.Contains("is now in the trust store") -and $run.out.Contains("turn(s) of the Thrall")) ("horde relay run takes the phone's key and sends the Thrall's turns (exit " + $run.code + ")")
    $mail = @(Get-ChatMail $c.value)
    Check ((Get-Texts $mail) -ceq "synthetic turn 3|synthetic turn 4|synthetic turn 5" -and $mail[0].backfill -eq $true) ("the phone opens them: the last three, from the end (" + (Get-Texts $mail) + ")")
    $session = $(if ($mail.Count) { "$($mail[0].session)" } else { "" })
    Check ($session -ceq $thrall.state.session) "and it learns the Thrall's session from them"
    Add-HordeTestChatTurns -Thrall $thrall -Turns @(@{ role = "user"; text = "is the build green?" }, @{ role = "assistant"; text = ("green, and " + [char]0x05D9 + [char]0x05E9 + " shipped") })
    $run = Invoke-Run -Turns 1
    $mail = @(Get-ChatMail $c.value)
    Check ((Get-Texts $mail) -ceq ("is the build green?|green, and " + [char]0x05D9 + [char]0x05E9 + " shipped")) ("the next run sends just the two new turns, words exact (" + (Get-Texts $mail) + ")")

    Write-Host ""
    Write-Host "--- 2. the founder's signed line reaches the Thrall once, and a receipt comes back ---" -ForegroundColor Cyan
    $words = "Merge it, then " + [char]0x05E1 + [char]0x05D9 + [char]0x05D9 + [char]0x05DD + "."
    $line = Invoke-Phone "line" @{ machine = $id.value.sign.keyId; session = $session; text = $words }
    [void](Send-Line $c.value $machineBox $line)
    $run = Invoke-Run -Turns 1
    $posts = @(Get-Posts)
    Check ($run.code -eq 0 -and $posts.Count -eq 1) ("the line is posted once (" + $posts.Count + " post(s); exit " + $run.code + ")")
    Check ($posts.Count -eq 1 -and $posts[0].to -ceq $thrall.state.session -and $posts[0].body -ceq ("FOUNDER LINE from the phone (line " + $line.messageId + ")`n`n" + $words) -and $posts[0].fromLabel -ceq "F") "to the Thrall's session, his words exactly under the line's header, from the founder's label"
    $mail = @(Get-ChatMail $c.value)
    $rc = @($mail | Where-Object { $_.kind -ceq "chat-receipt" })
    Check ($rc.Count -eq 1 -and $rc[0].messageId -ceq $line.messageId -and $rc[0].status -ceq "accepted" -and $rc[0].text -ceq $words) ("the phone opens a receipt: accepted (" + $(if ($rc.Count) { $rc[0].status + "/" + $rc[0].code } else { "none" }) + ")")

    Write-Host ""
    Write-Host "--- 3. replayed, re-signed, resent: still one post ---" -ForegroundColor Cyan
    [void](Send-HordeRelayItem -Connection $c.value -Mailbox $machineBox -Text $line.envelope -Key ($line.key + "-again"))
    $re = Invoke-Phone "resign" @{ envelope = $line.envelope }
    [void](Send-HordeRelayItem -Connection $c.value -Mailbox $machineBox -Text $re.envelope -Key (Get-HordeRelayContentKey -Text $re.envelope))
    $again = Invoke-Phone "line" @{ machine = $id.value.sign.keyId; session = $session; text = $words; messageId = $line.messageId }
    [void](Send-Line $c.value $machineBox $again)
    $run = Invoke-Run -Turns 1
    Check (([regex]::Matches($run.out, "a replay")).Count -eq 2) "the same envelope again and its re-signed copy are refused by the journal as replays"
    Check (@(Get-Posts).Count -eq 1 -and $run.out.Contains("accepted")) ("the same line resent in a new envelope is the same post: one record (" + @(Get-Posts).Count + ")")
    $null = Get-ChatMail $c.value

    Write-Host ""
    Write-Host "--- 4. only the founder's trusted passkeys speak to the Thrall ---" -ForegroundColor Cyan
    $o2 = New-HordeRelayPairingOffer -HordeHome $hh -RpId "relay.example.test" -Origins @("https://relay.example.test")
    $unknown = Invoke-Phone "register" @{ offer = $o2.value.text; label = "Never paired" } -State "unknown"
    [void](Send-Line $c.value $machineBox (Invoke-Phone "line" @{ machine = $id.value.sign.keyId; session = $session; text = "from nobody" } -State "unknown"))
    $o3 = New-HordeRelayPairingOffer -HordeHome $hh -RpId "relay.example.test" -Origins @("https://relay.example.test")
    $pend = Invoke-Phone "register" @{ offer = $o3.value.text; label = "Pending phone" } -State "pending"
    $null = Complete-HordeRelayPairing -HordeHome $hh -Response $pend.response
    [void](Send-Line $c.value $machineBox (Invoke-Phone "line" @{ machine = $id.value.sign.keyId; session = $session; text = "from pending" } -State "pending"))
    $o4 = New-HordeRelayPairingOffer -HordeHome $hh -RpId "relay.example.test" -Origins @("https://relay.example.test")
    $lost = Invoke-Phone "register" @{ offer = $o4.value.text; label = "Lost phone" } -State "lost"
    $lostDone = Complete-HordeRelayPairing -HordeHome $hh -Response $lost.response
    $null = Confirm-HordeRelayDevice -HordeHome $hh -Id $lostDone.value.device.id -Fingerprint $lost.fingerprint
    $null = Revoke-HordeRelayTrust -HordeHome $hh -Subject "device" -Id $lostDone.value.device.id -Reason "phone lost"
    [void](Send-Line $c.value $machineBox (Invoke-Phone "line" @{ machine = $id.value.sign.keyId; session = $session; text = "from the lost phone" } -State "lost"))
    # A peer machine of the horde, trusted - countersigned by a passkey of the founder's.
    $witness = New-HordeTestPhone
    [void](Add-HordeTestPhonePairing -HordeHome $hh -Phone $witness)
    $peerHome = Join-Path $work "peer"
    New-Item -ItemType Directory -Path (Join-Path $peerHome "settings") -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $peerHome "settings\relay.json"), '{"schemaVersion": 1, "settings": {"horde": "work"}}', $utf8)
    $peer = New-HordeRelayMachineIdentity -HordeHome $peerHome -Provider "software"
    [void]$keysMade.Add(@{ n = $peer.value.sign.name; s = $peer.value.scope }); [void]$keysMade.Add(@{ n = $peer.value.agree.name; s = $peer.value.scope })
    $card = (Export-HordeRelayMachineCard -HordeHome $peerHome -Label "Second machine").value
    $added = Add-HordeRelayPeerMachine -HordeHome $hh -Card $card
    $cs = New-HordeTestPhoneAssertion -Phone $witness -Challenge (Get-HordeRelayCardChallenge -Card $card)
    $vouched = Confirm-HordeRelayPeerMachine -HordeHome $hh -KeyId $added.value.record.keyId -By $witness.keyId -AuthenticatorData $cs.authenticatorData -ClientDataJson $cs.clientDataJson -Signature $cs.signature
    Check ($vouched.state -ceq "known" -and $vouched.value.record.state -ceq "trusted") "CONTROL: a peer machine of the horde is trusted"
    $peerOpen = Get-HordeRelayMachineIdentity -HordeHome $peerHome -Open
    $peerLine = New-HordeRelayEnvelope -Kind "line" -Channel "chat" -Seq 1 -Body (New-HordeTestPhoneLineBody -Machine $id.value.sign.keyId -Session $session -Text "from a machine") -Recipients @(, ([byte[]]$id.value.agree.public)) -Signer $peerOpen.value.sign.key
    $peerOpen.value.sign.key.Dispose(); $peerOpen.value.agree.key.Dispose()
    [void](Send-HordeRelayItem -Connection $c.value -Mailbox $machineBox -Text $peerLine -Key (Get-HordeRelayReplayKey -Header (Read-HordeRelayEnvelope -Text $peerLine).value.header))
    $run = Invoke-Run -Turns 1
    $refusals = ([regex]::Matches($run.out, "(?m)^refused ")).Count
    Check ($refusals -ge 4) ("an unknown, a pending and a revoked passkey, and a trusted peer machine, are each refused (" + $refusals + " refusals)")
    Check ($run.out.Contains("not one the channel chat takes (founder)")) "the peer machine is refused because chat takes the founder's passkeys only"
    Check (@(Get-Posts).Count -eq 1) ("and nothing more reaches the Thrall: still one post (" + @(Get-Posts).Count + ")")

    Write-Host ""
    Write-Host "--- 5. a clear: the last words before it, then the new session; a line to the old one ends there ---" -ForegroundColor Cyan
    Add-HordeTestChatTurns -Thrall $thrall -Turns @(@{ role = "assistant"; text = "last words before the clear" })
    $oldSession = $thrall.state.session
    $thrall.fixture.Clear.Invoke($thrall.state)
    Add-HordeTestChatTurns -Thrall $thrall -Turns @(@{ role = "user"; text = "a fresh session" })
    $run = Invoke-Run -Turns 2
    $mail = @(Get-ChatMail $c.value)
    Check ((Get-Texts $mail) -ceq "last words before the clear|a fresh session") ("the cleared session's tail reaches the phone before the new session's first turn (" + (Get-Texts $mail) + ")")
    Check ($mail.Count -ge 1 -and "$($mail[$mail.Count - 1].session)" -ceq $thrall.state.session -and $thrall.state.session -cne $oldSession) "and the phone now holds the new session"
    $stale = Invoke-Phone "line" @{ machine = $id.value.sign.keyId; session = $oldSession; text = "to the old session" }
    [void](Send-Line $c.value $machineBox $stale)
    $run = Invoke-Run -Turns 1
    $rc = @(@(Get-ChatMail $c.value) | Where-Object { $_.kind -ceq "chat-receipt" -and $_.messageId -ceq $stale.messageId })
    Check ($rc.Count -eq 1 -and $rc[0].status -ceq "refused" -and $rc[0].code -ceq "session-ended" -and @(Get-Posts).Count -eq 1) "a line written to the session before the clear is refused as ended, and not posted"
} finally {
    Remove-HordeTestChatThrall -Thrall $thrall
    Exit-HordeTestEmptyFleet -Pin $fleetPin
    $env:HORDE_HOME = $realHome
    foreach ($k in @($keysMade)) { try { [void](Remove-HordeRelayKey -Name $k.n -Scope $k.s) } catch { } }
    $left = @($keysMade | Where-Object { (Find-HordeRelayCngKey -Name $_.n -Scope $_.s) -cne "" })
    Check (@($keysMade).Count -ge 2 -and $left.Count -eq 0) "every key of the suite's machines is gone"
    if ((Split-Path -Leaf $work) -match '^horde-chat-e2e-[0-9a-f]{32}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    Check (-not (Test-Path -LiteralPath $work)) "the suite's folder, the phones' keys and the synthetic fleet with it, is gone"
}

Complete-HordeSuite -Success "a paired phone sees its Thrall's turns from the end through the real horde command; its signed line reaches the Thrall once; replays, strangers, revoked and pending passkeys and peer machines are refused; a clear's tail is not lost"
