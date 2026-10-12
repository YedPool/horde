# DOES THE MESSENGER PORT KEEP A MESSENGER HONEST ABOUT WHAT IT CAN DO, AND NEVER GUESS A DELIVERY?
#
# Remote plan step R21, slice 3 (messengers/Port.ps1). A messenger hands one message to one session on
# this machine and says how far it got. Pinned here, without any real messenger, so every outcome is
# exact and repeatable:
#   - REGISTRATION AND CAPABILITIES. A messenger folder whose capabilities.json breaks
#     schema/messenger-capabilities.v1, or names another folder, is refused. Only "yes" counts as having
#     a capability. The node's production path requires body.untyped, idempotent.post and
#     receipt.receiver, so the in-process test messenger, which declines receipt.receiver, is never
#     picked there - and the refusal carries the messenger's own evidence.
#   - THE MESSAGE IS CHECKED BEFORE ANY ADAPTER SEES IT. Each refusal is asserted for its own reason,
#     and the adapter is asserted never to have been called.
#   - THE ADAPTER'S WORD IS CHECKED TOO. An adapter that throws, answers with something that is not a
#     core/tristate answer, or names a stage outside the delivery stages, comes back unknown with the
#     reason; the port never throws for a failure of the far end.
#
# Every conformance case for the real messengers is test/test-messenger-conformance.ps1.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "messengers\Port.ps1")
. (Join-Path $root "messengers\memory\Messenger.ps1")

$fx = Join-Path $here "fixtures\messenger\caps"
$script:posted = 0
$script:asked = 0

function Reg {
    param([string]$Name,
          [scriptblock]$Post = { param($m) $script:posted++; New-HordeKnown -Value ([pscustomobject]@{ messageId = $m.messageId; stage = "accepted"; at = [datetime]::UtcNow; reason = "" }) -ObservedAt ([datetime]::UtcNow) },
          [scriptblock]$Status = { param($id) $script:asked++; New-HordeAbsent -Note "fixture knows nothing" -ObservedAt ([datetime]::UtcNow) })
    return (Register-HordeMessenger -Folder (Join-Path $fx $Name) -Post $Post -Status $Status)
}
function New-Msg {
    # A valid message; each refusal case below changes one member.
    return [pscustomobject]@{
        messageId = "0e000000-0000-4000-8000-000000000001"
        sessionId = "22222222-3333-4444-8555-666666666666"
        label = "A"
        from = [pscustomobject]@{ deviceId = "0f000000-0000-4000-8000-000000000001"; sessionId = "33333333-4444-4555-8666-777777777777"; label = "M" }
        body = "Pause batch 8 until PR 91 merges."
        ttlSeconds = 3600
    }
}
function Says { param($Findings, [string]$Text) return (@($Findings | Where-Object { "$_".Contains($Text) }).Count -gt 0) }

Write-Host ""
Write-Host "--- a messenger folder is registered only with valid capabilities, naming itself ---" -ForegroundColor Cyan

$good = Reg "fixture-good"
Check ($good.name -ceq "fixture-good") "a folder with valid capabilities registers under its own name"
Check (@(Get-HordeMessengerNames) -contains "fixture-good") "and is listed"
foreach ($case in @(
        @{ n = "fixture-misnamed"; like = "sits in the folder"; what = "capabilities that name another messenger than their folder" },
        @{ n = "fixture-missing-cap"; like = "receipt.receiver"; what = "capabilities missing one of the closed list" },
        @{ n = "fixture-extra-cap"; like = "keystrokes"; what = "a capability outside the closed list" },
        @{ n = "fixture-bad-word"; like = "maybe"; what = "a support word outside yes, no, declined, unverified" },
        @{ n = "fixture-blank-evidence"; like = "evidence"; what = "a capability with blank evidence" },
        @{ n = "fixture-no-file"; like = "no capabilities.json"; what = "a folder with no capabilities.json" })) {
    Check (Throws { Reg $case.n } $case.like) ("refused: " + $case.what)
    Check (@(Get-HordeMessengerNames) -notcontains $case.n) ("and " + $case.n + " is not registered")
}
Check (Throws { Get-HordeMessenger -Name "fixture-none" } "no messenger") "asking for a messenger nobody registered is an error, not a quiet default"
$firstGood = Get-HordeMessenger -Name "fixture-good"
Check (Throws { Reg "fixture-good" -Post { param($m) "replaced" } } "already registered") "registering a name a second time is refused"
Check ([object]::ReferenceEquals((Get-HordeMessenger -Name "fixture-good"), $firstGood)) "and the first registration still stands"
Check (@(@(Get-HordeMessengerFiles) | Where-Object { "$_" -like "*\memory\Messenger.ps1" }).Count -eq 1) "Get-HordeMessengerFiles finds the memory messenger's Messenger.ps1"

Write-Host ""
Write-Host "--- only 'yes' is having a capability; the node's path requires the three that make delivery safe ---" -ForegroundColor Cyan

Check (Test-HordeMessengerCapability -Messenger $good -Capability "body.untyped") "yes is having it"
Check (-not (Test-HordeMessengerCapability -Messenger $good -Capability "wake")) "no is not having it"
$unv = Reg "fixture-unverified"
Check (-not (Test-HordeMessengerCapability -Messenger $unv -Capability "idempotent.post")) "unverified is not having it"
Check (Throws { Test-HordeMessengerCapability -Messenger $good -Capability "teleport" } "not a messenger capability") "asking about a capability outside the list is an error"
$r = Resolve-HordeNodeMessenger -Name "fixture-good"
Check ($r.state -ceq "known" -and $r.value.name -ceq "fixture-good") "a messenger with all three is picked for the node"
$r = Resolve-HordeNodeMessenger -Name "fixture-unverified"
Check ($r.state -ceq "unknown" -and "$($r.reason)".Contains("idempotent.post") -and "$($r.reason)".Contains("never measured")) ("an unverified repost is refused for the node, with its evidence (" + $r.reason + ")")
$r = Resolve-HordeNodeMessenger -Name "memory"
Check ($r.state -ceq "unknown" -and "$($r.reason)".Contains("receipt.receiver") -and "$($r.reason)".Contains("declined")) ("the in-process memory messenger is never picked for the node: it declines receipt.receiver (" + $r.reason + ")")
$r = Resolve-HordeNodeMessenger -Name "fixture-none"
Check ($r.state -ceq "unknown" -and "$($r.reason)".Contains("no messenger named")) "a messenger nobody loaded resolves unknown, never a default"
$r = Resolve-HordeMessenger -Name "fixture-good" -Require @("wake")
Check ($r.state -ceq "unknown" -and "$($r.reason)".Contains("wake")) "a caller that requires wake does not get a messenger that cannot wake"
$r = Resolve-HordeMessenger -Name "fixture-good" -Require @()
Check ($r.state -ceq "known") "requiring nothing resolves any loaded messenger"

Write-Host ""
Write-Host "--- a caller that names no messenger finds THE one that offers what it needs, or is told why not ---" -ForegroundColor Cyan
# Loaded now: fixture-good (wake no), fixture-unverified (idempotent.post unverified, wake no), memory
# (receipt.receiver declined, wake no).
$r = Find-HordeMessenger -Require @("body.untyped", "idempotent.post", "receipt.receiver")
Check ($r.state -ceq "known" -and $r.value.name -ceq "fixture-good") ("exactly one loaded messenger offers all three: it is the answer (" + $r.reason + ")")
Check ([object]::ReferenceEquals($r.value, (Get-HordeMessenger -Name "fixture-good"))) "and it is the registered messenger itself, which the port will post through"
$r = Find-HordeMessenger -Require @("body.untyped", "wake")
Check ($r.state -ceq "absent" -and "$($r.reason)".Contains("fixture-good: does not offer wake") -and "$($r.reason)".Contains("memory: does not offer wake")) ("none offers wake: absent, and the note says what each loaded one lacks (" + $r.reason + ")")
$r = Find-HordeMessenger -Require @("body.untyped")
Check ($r.state -ceq "unknown" -and "$($r.reason)".Contains("fixture-good") -and "$($r.reason)".Contains("memory") -and "$($r.reason)".Contains("never chosen")) ("several offer it: unknown, one is never chosen over another (" + $r.reason + ")")
Check (Throws { Find-HordeMessenger -Require @("teleport") } "not a messenger capability") "a requirement outside the capability list is an error, never quietly unmet"

Write-Host ""
Write-Host "--- the message is checked before any adapter sees it, each refusal for its own reason ---" -ForegroundColor Cyan

$f = @(Test-HordeMessengerMessage -Message (New-Msg))
Check ($f.Count -eq 0) "CONTROL: the base message is valid"; foreach ($x in $f) { Write-Host ("         finding: " + $x) -ForegroundColor DarkYellow }
$m = New-Msg; $m.PSObject.Properties.Remove("label")
Check (@(Test-HordeMessengerMessage -Message $m).Count -eq 0) "CONTROL: label is optional"
$m = New-Msg; $m.from.PSObject.Properties.Remove("label")
Check (@(Test-HordeMessengerMessage -Message $m).Count -eq 0) "CONTROL: from.label is optional"
# A VERIFIED SENDER (the founder's first live use, 2026-10-11): a line whose signature the relay checked
# against the founder's trusted passkey says so, so the receiver need not show it as an unknown sender.
function New-Verified { param([string]$Kind = "founder", [string]$By = "passkey", $KeyId = ("ab" * 16)) return [pscustomobject]@{ kind = $Kind; by = $By; keyId = $KeyId } }
$m = New-Msg; $m.from | Add-Member -NotePropertyName verified -NotePropertyValue (New-Verified)
Check (@(Test-HordeMessengerMessage -Message $m).Count -eq 0) "a sender verified as the founder by a passkey's key id is valid"
$m = New-Msg; $m.from | Add-Member -NotePropertyName verified -NotePropertyValue @{ kind = "founder"; by = "passkey"; keyId = ("cd" * 16) }
Check (@(Test-HordeMessengerMessage -Message $m).Count -eq 0) "and so is the same as a dictionary"
$week = New-Msg; $week.ttlSeconds = 604800
Check (@(Test-HordeMessengerMessage -Message $week).Count -eq 0) "CONTROL: a ttl of exactly 7 days is valid"
$contractTtl = & { . (Join-Path $root "remote\Contract.ps1"); $script:HordeMailTtlMaxSeconds }
Check ($contractTtl -eq 604800 -and $script:HordeMessengerTtlMaxSeconds -eq $contractTtl) ("the port's ttl ceiling is remote/Contract.ps1's (" + $contractTtl + ")")
$big = New-Msg; $big.body = ("x" * 65536)
Check (@(Test-HordeMessengerMessage -Message $big).Count -eq 0) "CONTROL: a body of exactly 65536 bytes is valid"

$cases = @(
    @{ change = { param($m) $m.messageId = "0E000000-0000-4000-8000-000000000001" }; like = "messageId"; what = "a messageId in upper case" },
    @{ change = { param($m) $m.messageId = "0e0000000000400080000000000000001" }; like = "messageId"; what = "a messageId without its dashes" },
    @{ change = { param($m) $m.PSObject.Properties.Remove("messageId") }; like = "messageId"; what = "no messageId" },
    @{ change = { param($m) $m.messageId = "0e000000-0000-4000-8000-000000000001`n" }; like = "messageId"; what = "a messageId with a line break after it (a pattern ending in $ matches before a final LF)" },
    @{ change = { param($m) $m.sessionId = "C:\Users\x" }; like = "sessionId"; what = "a sessionId that is a drive path" },
    @{ change = { param($m) $m.sessionId = "a..b" }; like = "sessionId"; what = "a sessionId holding .." },
    @{ change = { param($m) $m.label = "orc-1" }; like = "label"; what = "a label that is not a hub label" },
    @{ change = { param($m) $m.PSObject.Properties.Remove("from") }; like = "from"; what = "no sender" },
    @{ change = { param($m) $m.from.deviceId = "laptop" }; like = "from.deviceId"; what = "a sender device that is not a device id" },
    @{ change = { param($m) $m.from.sessionId = "CON" }; like = "from.sessionId"; what = "a sender session id that is a DOS device name" },
    @{ change = { param($m) $m.from | Add-Member -NotePropertyName pane -NotePropertyValue 4 }; like = "from.pane"; what = "a sender with a member outside the list" },
    @{ change = { param($m) $m.from | Add-Member -NotePropertyName verified -NotePropertyValue "founder" }; like = "from.verified"; what = "a verified sender that is not an object" },
    @{ change = { param($m) $m.from | Add-Member -NotePropertyName verified -NotePropertyValue (New-Verified -Kind "M") }; like = "from.verified.kind"; what = "a verified sender of a kind outside the list" },
    @{ change = { param($m) $m.from | Add-Member -NotePropertyName verified -NotePropertyValue (New-Verified -By "label") }; like = "from.verified.by"; what = "a sender verified by a means outside the list" },
    @{ change = { param($m) $m.from | Add-Member -NotePropertyName verified -NotePropertyValue (New-Verified -KeyId ("AB" * 16)) }; like = "from.verified.keyId"; what = "a verifying key id in upper case" },
    @{ change = { param($m) $m.from | Add-Member -NotePropertyName verified -NotePropertyValue (New-Verified -KeyId ("ab" * 16 + "`n")) }; like = "from.verified.keyId"; what = "a verifying key id with a line break after it" },
    @{ change = { param($m) $m.from | Add-Member -NotePropertyName verified -NotePropertyValue (New-Verified -KeyId @("ab" * 16)) }; like = "from.verified.keyId"; what = "a verifying key id that is a one-element list" },
    @{ change = { param($m) $v = New-Verified; $v.PSObject.Properties.Remove("keyId"); $m.from | Add-Member -NotePropertyName verified -NotePropertyValue $v }; like = "from.verified.keyId"; what = "a verified sender with no key id" },
    @{ change = { param($m) $v = New-Verified; $v | Add-Member -NotePropertyName label -NotePropertyValue "F"; $m.from | Add-Member -NotePropertyName verified -NotePropertyValue $v }; like = "from.verified.label"; what = "a verified sender with a member outside the list" },
    @{ change = { param($m) $m.body = " `r`n " }; like = "body is blank"; what = "a blank body" },
    @{ change = { param($m) $m.body = ("x" * 65537) }; like = "65536"; what = "a body one byte over 64 KiB" },
    @{ change = { param($m) $m.body = (("x" * 65535) + [string][char]0x00E9) }; like = "65536"; what = "a body over 64 KiB only in UTF-8 bytes, not in characters" },
    @{ change = { param($m) $m.ttlSeconds = 0 }; like = "ttlSeconds"; what = "a ttl of zero" },
    @{ change = { param($m) $m.ttlSeconds = 604801 }; like = "604800"; what = "a ttl one second over 7 days, the contract's ceiling (remote/Contract.ps1)" },
    @{ change = { param($m) $m.messageId = @("0e000000-0000-4000-8000-000000000001") }; like = "messageId"; what = "a messageId that is a one-element list, not a string" },
    @{ change = { param($m) $m.from.sessionId = @("33333333-4444-4555-8666-777777777777") }; like = "from.sessionId"; what = "a sender session id that is a one-element list, not a string" },
    @{ change = { param($m) $m.ttlSeconds = "3600" }; like = "ttlSeconds"; what = "a ttl given as text" },
    @{ change = { param($m) $m | Add-Member -NotePropertyName pane -NotePropertyValue 4 }; like = "pane"; what = "a message addressed by pane: a member outside the list" })
foreach ($c in $cases) {
    $m = New-Msg
    $null = & $c.change $m
    $got = @(Test-HordeMessengerMessage -Message $m)
    Check (Says $got $c.like) ("refused: " + $c.what)
    if (-not (Says $got $c.like)) { foreach ($x in $got) { Write-Host ("         finding: " + $x) -ForegroundColor DarkYellow } }
    $before = $script:posted
    $a = Send-HordeMessengerMessage -Messenger $good -Message $m
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains($c.like) -and $script:posted -eq $before) ("and sending it answers unknown with that reason, without calling the adapter")
}
Check ((Send-HordeMessengerMessage -Messenger $good -Message $null).state -ceq "unknown") "sending nothing answers unknown"

Write-Host ""
Write-Host "--- the adapter's word is checked: a throw, a non-answer or a stage outside the list is unknown ---" -ForegroundColor Cyan

$a = Send-HordeMessengerMessage -Messenger $good -Message (New-Msg)
Check ($a.state -ceq "known" -and $a.value.stage -ceq "accepted" -and $a.value.messageId -ceq "0e000000-0000-4000-8000-000000000001" -and $a.value.at -is [datetime]) "CONTROL: a good adapter's post comes back known accepted, with the message id and a time"
$boom = Reg "fixture-boom" -Post { param($m) throw "the mailbox disk is gone" } -Status { param($id) throw "the mailbox disk is gone" }
$a = Send-HordeMessengerMessage -Messenger $boom -Message (New-Msg)
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("the mailbox disk is gone")) ("an adapter that throws on post is unknown with its message (" + $a.reason + ")")
$a = Get-HordeMessengerStatus -Messenger $boom -MessageId "0e000000-0000-4000-8000-000000000001"
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("the mailbox disk is gone")) "an adapter that throws on status is unknown with its message"
$liar = Reg "fixture-liar" -Post { param($m) "sent" } -Status { param($id) $true }
$a = Send-HordeMessengerMessage -Messenger $liar -Message (New-Msg)
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("not an answer")) "an adapter whose post is not a tristate answer is unknown, never read as sent"
$a = Get-HordeMessengerStatus -Messenger $liar -MessageId "0e000000-0000-4000-8000-000000000001"
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("not an answer")) "an adapter whose status is not a tristate answer is unknown"
$bad = Reg "fixture-badstage" -Post { param($m) New-HordeKnown -Value ([pscustomobject]@{ messageId = $m.messageId; stage = "delivered"; at = [datetime]::UtcNow; reason = "" }) -ObservedAt ([datetime]::UtcNow) } -Status { param($id) New-HordeKnown -Value ([pscustomobject]@{ messageId = $id; stage = "seen"; at = "yesterday"; reason = "" }) -ObservedAt ([datetime]::UtcNow) }
$a = Send-HordeMessengerMessage -Messenger $bad -Message (New-Msg)
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("delivered")) "a stage outside accepted, handed-over, seen, expired and held is unknown, naming it"
$a = Get-HordeMessengerStatus -Messenger $bad -MessageId "0e000000-0000-4000-8000-000000000001"
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("time")) "a stage whose time is not a time is unknown"
$silent = Reg "fixture-silent" -Post { param($m) New-HordeAbsent -Note "nothing here" -ObservedAt ([datetime]::UtcNow) }
$a = Send-HordeMessengerMessage -Messenger $silent -Message (New-Msg)
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("absent")) "a post answered absent is unknown: it says nothing of the message it was handed"
$a = Get-HordeMessengerStatus -Messenger $good -MessageId "0e000000-0000-4000-8000-000000000009"
Check ($a.state -ceq "absent") "CONTROL: an adapter's absent status stays absent"
$before = $script:asked
$a = Get-HordeMessengerStatus -Messenger $good -MessageId "not-an-id"
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("messageId") -and $script:asked -eq $before) "a status for an id that is not a message id is unknown, without asking the adapter"

Write-Host ""
Write-Host "--- an answer is about the message it was asked about, and says why wherever the contract needs a reason ---" -ForegroundColor Cyan

# One adapter whose answers each case sets: $script:postValue and $script:statusValue build the value.
$script:postValue = $null
$script:statusValue = $null
$scripted = Reg "fixture-scripted" -Post { param($m) New-HordeKnown -Value (& $script:postValue $m.messageId) -ObservedAt ([datetime]::UtcNow) } -Status { param($id) New-HordeKnown -Value (& $script:statusValue $id) -ObservedAt ([datetime]::UtcNow) }
function Answer { param([hashtable]$Fields) $o = [ordered]@{}; foreach ($k in $Fields.Keys) { $o[$k] = $Fields[$k] }; return [pscustomobject]$o }
$other = "0e000000-0000-4000-8000-0000000000ff"
$script:postValue = { param($id) Answer @{ messageId = $id; stage = "accepted"; at = [datetime]::UtcNow; reason = "" } }
$a = Send-HordeMessengerMessage -Messenger $scripted -Message (New-Msg)
Check ($a.state -ceq "known" -and $a.value.stage -ceq "accepted") "CONTROL: an answer naming the message it was asked about is read"
Check ($a.state -ceq "known" -and $null -eq $a.value.PSObject.Properties["reason"]) "an empty reason is left out of the value, never written as '' (link-verbs delivery.reason requires text)"
$script:postValue = { param($id) Answer @{ messageId = $other; stage = "seen"; at = [datetime]::UtcNow; reason = "" } }
$a = Send-HordeMessengerMessage -Messenger $scripted -Message (New-Msg)
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains($other)) ("a post answered about another message is unknown, never that message's stage (" + $a.reason + ")")
$script:postValue = { param($id) Answer @{ stage = "seen"; at = [datetime]::UtcNow; reason = "" } }
$a = Send-HordeMessengerMessage -Messenger $scripted -Message (New-Msg)
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("messageId")) "a post answer that names no message is unknown"
$script:statusValue = { param($id) Answer @{ messageId = $other; stage = "seen"; at = [datetime]::UtcNow; reason = "" } }
$a = Get-HordeMessengerStatus -Messenger $scripted -MessageId "0e000000-0000-4000-8000-000000000001"
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains($other)) "a status answered about another message is unknown"
$script:postValue = { param($id) Answer @{ messageId = $id; stage = "held"; at = [datetime]::UtcNow; reason = " " } }
$a = Send-HordeMessengerMessage -Messenger $scripted -Message (New-Msg)
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("held")) "held with no reason is unknown: held must say why it was not delivered"
$script:postValue = { param($id) Answer @{ messageId = $id; stage = "held"; at = [datetime]::UtcNow; reason = "the target's inbox is full" } }
$a = Send-HordeMessengerMessage -Messenger $scripted -Message (New-Msg)
Check ($a.state -ceq "known" -and $a.value.stage -ceq "held" -and "$($a.value.reason)" -ceq "the target's inbox is full") "CONTROL: held with its reason is read, reason and all"
$script:postValue = { param($id) Answer @{ messageId = $id; stage = "accepted"; at = [datetime]::UtcNow; reason = "line one`nline two" } }
$a = Send-HordeMessengerMessage -Messenger $scripted -Message (New-Msg)
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("line break")) "a reason holding a line break is unknown"
$script:postValue = { param($id) Answer @{ messageId = $id; stage = "accepted"; at = [datetime]::UtcNow; reason = ("r" * 1025) } }
$a = Send-HordeMessengerMessage -Messenger $scripted -Message (New-Msg)
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("1024")) "a reason over the link's 1024-byte reasonBytes cap is unknown"
$script:postValue = { param($id) Answer @{ messageId = $id; stage = "accepted"; at = [datetime]::UtcNow; reason = ("r" * 1024) } }
Check ((Send-HordeMessengerMessage -Messenger $scripted -Message (New-Msg)).state -ceq "known") "CONTROL: a reason of exactly 1024 bytes is read"

# THE PORT PASSES STAGES THROUGH AS THEY ARE. Forward-only receipts are remote/Messaging.ps1's rule
# (Resolve-HordeMailReceipt), enforced in slice 4 against the message journal; the port does not
# second-guess an adapter's order, so a backward move reaches slice 4 to be refused there.
$script:statusValue = { param($id) Answer @{ messageId = $id; stage = "accepted"; at = [datetime]::UtcNow; reason = "" } }
$a = Get-HordeMessengerStatus -Messenger $scripted -MessageId "0e000000-0000-4000-8000-000000000001"
Check ($a.state -ceq "known" -and $a.value.stage -ceq "accepted") "a stage that moved backward (seen, then accepted) is passed through as the adapter said it, not corrected by the port"

Write-Host ""
Write-Host "--- only a registered messenger is called ---" -ForegroundColor Cyan

$script:fakeCalled = 0
$fake = [pscustomobject]@{ PSTypeName = "Horde.Messenger"; name = "fixture-good"; folder = "x"; capabilities = $good.capabilities
    post = { param($x) $script:fakeCalled++; New-HordeKnown -Value ([pscustomobject]@{ messageId = $x.messageId; stage = "seen"; at = [datetime]::UtcNow }) -ObservedAt ([datetime]::UtcNow) }
    status = { param($i) $script:fakeCalled++; New-HordeKnown -Value ([pscustomobject]@{ messageId = $i; stage = "seen"; at = [datetime]::UtcNow }) -ObservedAt ([datetime]::UtcNow) } }
$a = Send-HordeMessengerMessage -Messenger $fake -Message (New-Msg)
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("not registered") -and $script:fakeCalled -eq 0) "a look-alike of a registered messenger is refused for a post, and never called"
$a = Get-HordeMessengerStatus -Messenger $fake -MessageId "0e000000-0000-4000-8000-000000000001"
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("not registered") -and $script:fakeCalled -eq 0) "and for a status"
$plain = [pscustomobject]@{ name = "unregistered"; post = $fake.post; status = $fake.status }
Check ((Send-HordeMessengerMessage -Messenger $plain -Message (New-Msg)).state -ceq "unknown" -and $script:fakeCalled -eq 0) "an object that never registered is refused"
Check ((Send-HordeMessengerMessage -Messenger $null -Message (New-Msg)).state -ceq "unknown") "no messenger at all is refused"

Write-Host ""
Write-Host "--- the memory messenger: one record per message id, and a repost returns the recorded stage ---" -ForegroundColor Cyan

$mem = Get-HordeMessenger -Name "memory"
Reset-HordeMemoryMessenger
$a = Send-HordeMessengerMessage -Messenger $mem -Message (New-Msg)
$log = Get-HordeMemoryMessengerLog
Check ($a.state -ceq "known" -and $a.value.stage -ceq "accepted" -and $log.posts -eq 1 -and $log.records -eq 1) "a first post is accepted and makes one record"
$a = Send-HordeMessengerMessage -Messenger $mem -Message (New-Msg)
$log = Get-HordeMemoryMessengerLog
Check ($a.state -ceq "known" -and $a.value.stage -ceq "accepted" -and $log.posts -eq 2 -and $log.records -eq 1) "a repost of the same id returns the recorded stage and makes no second record"
Set-HordeMemoryMessengerStage -MessageId "0e000000-0000-4000-8000-000000000001" -Stage "seen"
$a = Get-HordeMessengerStatus -Messenger $mem -MessageId "0e000000-0000-4000-8000-000000000001"
Check ($a.state -ceq "known" -and $a.value.stage -ceq "seen") "a message moved on by the receiving side reads back at its new stage"
$a = Send-HordeMessengerMessage -Messenger $mem -Message (New-Msg)
Check ($a.state -ceq "known" -and $a.value.stage -ceq "seen" -and (Get-HordeMemoryMessengerLog).records -eq 1) "a repost after it was seen returns seen, and still one record"
Check (Throws { Set-HordeMemoryMessengerStage -MessageId "0e000000-0000-4000-8000-000000000001" -Stage "delivered" } "not a stage") "the memory messenger's own helper refuses a stage outside the list"
$a = Get-HordeMessengerStatus -Messenger $mem -MessageId "0e000000-0000-4000-8000-000000000002"
Check ($a.state -ceq "absent") "a message the memory messenger never took is absent"
Check ((Get-HordeMemoryMessengerLog).wakes -eq 0 -and (Get-HordeMemoryMessengerLog).typed -eq 0) "the memory messenger wakes nothing and types nothing"
Reset-HordeMemoryMessenger
Check ((Get-HordeMemoryMessengerLog).records -eq 0 -and (Get-HordeMemoryMessengerLog).posts -eq 0) "and a reset leaves it empty"

Complete-HordeSuite -Success "the messenger port admits only messengers honest about what they do, checks every message before an adapter sees it, and never reads an adapter's failure as a delivery"
