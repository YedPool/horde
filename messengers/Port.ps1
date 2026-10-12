# messengers/Port.ps1 - the messenger port: how a node hands one message to one of its own sessions.
#
# WHAT A MESSENGER IS (remote plan step R21, slice 3). A messenger takes a message addressed to a
# session on THIS machine, hands it over by that machine's own means, and says how far it got. It knows
# nothing of links, verbs or other machines: the node's link code (remote/) decides whether a message
# may be delivered at all, and the messenger only delivers. Each one is a folder, messengers/<name>/,
# holding Messenger.ps1 (its code), capabilities.json (what it can do, as data, checked against
# schema/messenger-capabilities.v1) and test/Fixture.ps1 (how test/test-messenger-conformance.ps1
# observes it). This file names no messenger: a second one is a new folder, not an edit here.
#
# WHY HERE AND NOT IN remote/. The port calls the script blocks each messenger registers, and a real
# messenger starts a program (the fleet's mail command) or writes into another system's store.
# test/test-exec-scan.ps1 holds every file in remote/ to "starts no program and no shell", and that rule
# is right for the protocol: remote/ must never run code a frame names. So delivery lives here, beside
# the messengers it dispatches to, as transports/Port.ps1 lives beside the transports, and the node's
# protocol code takes a messenger handed to it and keeps its tripwire unweakened.
#
# THE STAGES are the link's delivery stages that a messenger can reach (schema/link-verbs.v1,
# definitions/delivery): accepted (in the target's mailbox), handed-over (the target's own side handed it
# to a turn), seen (confirmed in the target's own transcript), expired, held (known not delivered, never
# "failed"). queued is the node's own stage before any messenger is asked, so no messenger answers it.
#
# CAPABILITIES ARE CLAIMS, AND ONLY "yes" COUNTS. unverified, declined and no all read as "does not have
# it". The node's production path (Resolve-HordeNodeMessenger) requires body.untyped, idempotent.post and
# receipt.receiver: a body typed into an input box is the defect family the fleet's mail was built to
# end, a post that is not idempotent delivers twice after a dropped link, and a "seen" that is not the
# receiver's own word is the sender guessing. The in-process test messenger declines receipt.receiver,
# so no production path can pick it.
#
# THE PORT NEVER GUESSES AND NEVER THROWS FOR THE FAR END. A message is checked before any adapter sees
# it, and an invalid one is unknown with the reason. Only a messenger registered through
# Register-HordeMessenger is called: a look-alike object is refused, so "memory is never picked in
# production" does not rest on every caller going through Resolve-HordeNodeMessenger (review of #102).
# An adapter that throws, answers with something that is not a core/tristate answer, answers about a
# message other than the one it was asked about, names a stage outside the list, or gives a reason the
# link could not carry, comes back unknown with the reason.
#
# WHAT THE PORT DOES NOT OWN (review of #102, findings 2 and 4). It passes a stage through exactly as the
# adapter said it, a backward one included. Forward-only receipts (a stage never moves back, a final
# stage is never overwritten) and the args-hash check on a repost (one messageId, different content, is
# refused rather than answered with the first content's stage) are remote/Messaging.ps1's rules, from
# the review of PR #97, enforced in slice 4 against the message journal. Two places deciding the same
# rule would drift; slice 4 is the one that holds the journal.
#
# ADAPTER CONTRACT. messengers/<name>/Messenger.ps1 is dot-sourced at script level and calls
# Register-HordeMessenger with two script blocks:
#   Post    param($Message)          -> a tristate answer: known { stage; at; reason }, or unknown
#   Status  param([string]$MessageId) -> known { stage; at; reason }, absent (never took it), or unknown
# The known value is { messageId; stage; at; reason }: messageId must be the id the port asked about, at
# is a [datetime], reason is one line within the link's reasonBytes, and must be given for held. A post
# of a messageId already taken returns the stage recorded for it and delivers nothing more
# (idempotent.post). The port's own known value leaves reason out when it is empty, because
# schema/link-verbs.v1's delivery.reason requires text.
#
# THE MESSAGE: { messageId; sessionId; label (optional); from { deviceId; sessionId; label (optional);
# verified (optional) }; body; ttlSeconds }, the shape of session.deliver's arguments
# (schema/link-verbs.v1), with the same patterns, read from that schema so there is one definition of
# each, and the same ttl ceiling.
#
# A VERIFIED SENDER (the founder's first live use, 2026-10-11: his phone's lines reached his Thrall as
# "the sender calls itself: F (not verified)"). from.verified = { kind; by; keyId } says this node
# checked who sent it before handing it over: kind founder, by passkey - the relay verified the line's
# signature against a passkey the trust store holds as the founder's (channels/chat) - and keyId that
# passkey's key id (32 lower-case hex). Closed: no other kind, means or member. It is this node's word,
# never a sender's: session.deliver's from (schema/link-verbs.v1) has no such member, so nothing that came
# over a link can carry it here. A messenger shows it as it can; one that cannot simply posts by label.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Tristate.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Schema.ps1")

if ($null -eq (Get-Variable -Name HordeMessengers -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeMessengers = @{} }
$script:HordeMessengerCapabilityNames = @("body.untyped", "idempotent.post", "receipt.receiver", "wake")
# What the node's production path requires. A messenger without all three is never picked there.
$script:HordeNodeMessengerRequires = @("body.untyped", "idempotent.post", "receipt.receiver")
$script:HordeMessengerStages = @("accepted", "handed-over", "seen", "expired", "held")
$script:HordeMessengerMembers = @("messageId", "sessionId", "label", "from", "body", "ttlSeconds")
$script:HordeMessengerFromMembers = @("deviceId", "sessionId", "label", "verified")
# A VERIFIED SENDER's members and their closed values (the header).
$script:HordeMessengerVerifiedMembers = @("kind", "by", "keyId")
$script:HordeMessengerVerifiedKinds = @("founder")
$script:HordeMessengerVerifiedBy = @("passkey")
$script:HordeMessengerVerifiedKeyIdPattern = '\A[0-9a-f]{32}\z'
# The most a body may take, in UTF-8 bytes: the link's textBytes (schema/link-frame.v1), 64 KiB.
$script:HordeMessengerBodyBytes = 65536
# The longest a message may wait: remote/Contract.ps1's $script:HordeMailTtlMaxSeconds, 7 days, the
# replay window. Copied, not loaded, so the port does not load the link contract; test-messenger-port
# fails if the two ever differ.
$script:HordeMessengerTtlMaxSeconds = 604800
# The most a reason may take, in UTF-8 bytes: the link's reasonBytes (schema/link-frame.v1).
$script:HordeMessengerReasonBytes = 1024
# The stages that must say why: held is known not delivered, and the reason is the only account of it.
$script:HordeMessengerReasonStages = @("held")
$script:HordeMessengerPatterns = $null

function Get-HordeMessengerRoot {
    return $PSScriptRoot
}

function Get-HordeMessengerFiles {
    # Every messenger's Messenger.ps1, for the caller to dot-source at script level:
    #   foreach ($f in @(Get-HordeMessengerFiles)) { . $f }
    param([string]$Root = (Get-HordeMessengerRoot))
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $Root -Directory | Sort-Object Name | ForEach-Object { Join-Path $_.FullName "Messenger.ps1" } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
}

function Get-HordeMessengerCapabilityNames {
    return @($script:HordeMessengerCapabilityNames)
}

function Test-HordeMessengerCapabilities {
    # Findings for a parsed capabilities.json read from -Folder: the schema's, plus the rule the schema
    # cannot say - the messenger it names is its own folder.
    param($Capabilities, [string]$Folder)
    $schema = Get-HordeSchema -Name "messenger-capabilities.v1"
    $findings = @(Test-HordeSchema -Value $Capabilities -Schema $schema)
    if ($findings.Count -gt 0) { return $findings }
    $leaf = Split-Path -Leaf $Folder
    if ("$($Capabilities.messenger)" -cne $leaf) { return @("capabilities.json names the messenger '" + $Capabilities.messenger + "' but sits in the folder '" + $leaf + "'") }
    return @()
}

function Register-HordeMessenger {
    # Called by a messenger's own Messenger.ps1. Throws, naming every finding, when its
    # capabilities.json is missing or invalid: a messenger that cannot say what it does is not one.
    param(
        [Parameter(Mandatory = $true)][string]$Folder,
        [Parameter(Mandatory = $true)][scriptblock]$Post,
        [Parameter(Mandatory = $true)][scriptblock]$Status
    )
    $capPath = Join-Path $Folder "capabilities.json"
    if (-not (Test-Path -LiteralPath $capPath -PathType Leaf)) { throw ("messenger folder '" + $Folder + "' has no capabilities.json") }
    $caps = [System.IO.File]::ReadAllText($capPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $findings = @(Test-HordeMessengerCapabilities -Capabilities $caps -Folder $Folder)
    if ($findings.Count -gt 0) { throw ("messenger '" + (Split-Path -Leaf $Folder) + "' refused: " + ($findings -join "; ")) }
    # Once per name: a second registration would silently swap the messenger every caller resolves by
    # that name (the transport port's review of PR #42 found exactly that).
    if ($script:HordeMessengers.ContainsKey("$($caps.messenger)")) {
        throw ("messenger '" + $caps.messenger + "' is already registered, from " + $script:HordeMessengers["$($caps.messenger)"].folder + "; the first registration stands")
    }
    $m = [pscustomobject]@{ PSTypeName = "Horde.Messenger"; name = "$($caps.messenger)"; folder = $Folder; capabilities = $caps; post = $Post; status = $Status }
    $script:HordeMessengers[$m.name] = $m
    return $m
}

function Get-HordeMessengerNames {
    return @($script:HordeMessengers.Keys | Sort-Object)
}

function Get-HordeMessenger {
    # A registered messenger by name. Throws for a name nobody registered: asking for one that is not
    # loaded is a programming error, not a state of the world.
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not $script:HordeMessengers.ContainsKey($Name)) { throw ("no messenger named '" + $Name + "' is loaded") }
    return $script:HordeMessengers[$Name]
}

function Get-HordeMessengerSupport {
    # The support word a messenger declares for one capability: yes, no, declined or unverified.
    param([Parameter(Mandatory = $true)]$Messenger, [Parameter(Mandatory = $true)][string]$Capability)
    if ($script:HordeMessengerCapabilityNames -cnotcontains $Capability) { throw ("'" + $Capability + "' is not a messenger capability") }
    return "$($Messenger.capabilities.capabilities.$Capability.support)"
}

function Test-HordeMessengerCapability {
    # True only for "yes". unverified is treated as no, and so are no and declined.
    param([Parameter(Mandatory = $true)]$Messenger, [Parameter(Mandatory = $true)][string]$Capability)
    return ((Get-HordeMessengerSupport -Messenger $Messenger -Capability $Capability) -ceq "yes")
}

function Resolve-HordeMessenger {
    # A messenger by name that has every capability in -Require, as a tristate answer. -Require is
    # mandatory so a caller states what it needs; @() means nothing.
    param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Require)
    if (-not $script:HordeMessengers.ContainsKey($Name)) { return (New-HordeUnknown -Reason ("no messenger named '" + $Name + "' is loaded")) }
    $m = $script:HordeMessengers[$Name]
    foreach ($c in $Require) {
        if (-not (Test-HordeMessengerCapability -Messenger $m -Capability $c)) {
            $cap = $m.capabilities.capabilities.$c
            return (New-HordeUnknown -Reason ("messenger '" + $Name + "' does not offer " + $c + " (it says " + $cap.support + ": " + $cap.evidence + ")"))
        }
    }
    return (New-HordeKnown -Value $m)
}

function Find-HordeMessenger {
    # THE ONE loaded messenger that has every capability in -Require, for a caller that names none (the
    # decisions doorbell, decisions/Notify.ps1): it states what it needs, and whichever messenger is
    # loaded that offers it is the answer, so a messenger that lands later is picked with no change to
    # the caller. known: exactly one offers all. absent: none does, and the note says, for each loaded
    # messenger, the first capability it lacks. unknown: two or more do - one is never chosen over
    # another (core/SessionSeat.ps1 holds the same rule for two holders of a role); a caller that must
    # pick between them names one, with Resolve-HordeMessenger.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Require)
    foreach ($c in $Require) { if ($script:HordeMessengerCapabilityNames -cnotcontains $c) { throw ("'" + $c + "' is not a messenger capability") } }
    $able = New-Object System.Collections.ArrayList
    $lacks = New-Object System.Collections.ArrayList
    foreach ($name in @(Get-HordeMessengerNames)) {
        $m = $script:HordeMessengers[$name]
        $missing = @($Require | Where-Object { -not (Test-HordeMessengerCapability -Messenger $m -Capability $_) }) | Select-Object -First 1
        if ($null -eq $missing) { [void]$able.Add($m) } else { [void]$lacks.Add($name + ": does not offer " + $missing + " (it says " + (Get-HordeMessengerSupport -Messenger $m -Capability $missing) + ")") }
    }
    if ($able.Count -eq 1) { return (New-HordeKnown -Value $able[0]) }
    if ($able.Count -gt 1) { return (New-HordeUnknown -Reason ("" + $able.Count + " messengers each offer " + ($Require -join ", ") + " (" + (@($able | ForEach-Object { $_.name }) -join ", ") + "); one is never chosen over another")) }
    $loaded = "no messenger is loaded"
    if ($lacks.Count -gt 0) { $loaded = $lacks -join "; " }
    return (New-HordeAbsent -Note ("no loaded messenger offers " + ($Require -join ", ") + ": " + $loaded))
}

function Resolve-HordeNodeMessenger {
    # The one way a node picks the messenger it delivers through. It requires the three capabilities
    # that make a delivery safe and its receipt true, so the in-process test messenger is never chosen.
    param([Parameter(Mandatory = $true)][string]$Name)
    return (Resolve-HordeMessenger -Name $Name -Require $script:HordeNodeMessengerRequires)
}

function Get-HordeMessengerPatterns {
    # The identifier patterns of schema/link-verbs.v1, read once: the message a messenger takes is
    # session.deliver's, so its identifiers are checked by the same patterns, never a copy of them.
    if ($null -eq $script:HordeMessengerPatterns) {
        $defs = (Get-HordeSchema -Name "link-verbs.v1").definitions
        $script:HordeMessengerPatterns = @{ uuid = "$($defs.uuid.pattern)"; session = "$($defs.'session-id'.pattern)"; label = "$($defs.label.pattern)" }
    }
    return $script:HordeMessengerPatterns
}

function Test-HordeMessengerText {
    # Is this a string, on one line, matching the pattern? A pattern ending in $ also matches before a
    # final LF, so a line break is refused on its own.
    param($Value, [string]$Pattern)
    return ($Value -is [string] -and $Value -cnotmatch "[`r`n]" -and $Value -cmatch $Pattern)
}

function Get-HordeMessengerMember {
    # A member of a parsed object or a dictionary, and whether it is there. Looked up, never
    # dereferenced, so a missing member under strict mode is not an error.
    param($Object, [string]$Name)
    if ($Object -is [System.Collections.IDictionary]) { return [pscustomobject]@{ has = $Object.Contains($Name); value = $(if ($Object.Contains($Name)) { $Object[$Name] } else { $null }) } }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return [pscustomobject]@{ has = $false; value = $null } }
    return [pscustomobject]@{ has = $true; value = $p.Value }
}

function Get-HordeMessengerMemberNames {
    param($Object)
    if ($Object -is [System.Collections.IDictionary]) { return @($Object.Keys | ForEach-Object { "$_" }) }
    return @($Object.PSObject.Properties | ForEach-Object { $_.Name })
}

function Test-HordeMessengerVerified {
    # Findings for a message's from.verified (A VERIFIED SENDER, in the header); none when it holds.
    param($Verified)
    if ($null -eq $Verified -or -not ($Verified -is [System.Management.Automation.PSCustomObject] -or $Verified -is [System.Collections.IDictionary])) { return @("from.verified is not an object: it is { kind; by; keyId }") }
    $out = New-Object System.Collections.ArrayList
    foreach ($n in @(Get-HordeMessengerMemberNames $Verified)) {
        if ($script:HordeMessengerVerifiedMembers -cnotcontains $n) { [void]$out.Add("the message has 'from.verified." + $n + "', which is not a member of a verified sender") }
    }
    $k = Get-HordeMessengerMember $Verified "kind"
    if (-not $k.has -or $k.value -isnot [string] -or $script:HordeMessengerVerifiedKinds -cnotcontains $k.value) { [void]$out.Add("from.verified.kind is not one of " + ($script:HordeMessengerVerifiedKinds -join ", ")) }
    $b = Get-HordeMessengerMember $Verified "by"
    if (-not $b.has -or $b.value -isnot [string] -or $script:HordeMessengerVerifiedBy -cnotcontains $b.value) { [void]$out.Add("from.verified.by is not one of " + ($script:HordeMessengerVerifiedBy -join ", ")) }
    $i = Get-HordeMessengerMember $Verified "keyId"
    if (-not $i.has -or -not (Test-HordeMessengerText $i.value $script:HordeMessengerVerifiedKeyIdPattern)) { [void]$out.Add("from.verified.keyId is not a key id: 32 lower-case hex") }
    return @($out)
}

function Test-HordeMessengerMessage {
    # Findings for one message, each naming the member it is about. None means it may be handed to a
    # messenger.
    param($Message)
    if ($null -eq $Message -or -not ($Message -is [System.Management.Automation.PSCustomObject] -or $Message -is [System.Collections.IDictionary])) { return @("the message is not an object") }
    $p = Get-HordeMessengerPatterns
    $out = New-Object System.Collections.ArrayList
    foreach ($n in @(Get-HordeMessengerMemberNames $Message)) {
        if ($script:HordeMessengerMembers -cnotcontains $n) { [void]$out.Add("the message has '" + $n + "', which is not a member of a message") }
    }
    $id = Get-HordeMessengerMember $Message "messageId"
    if (-not $id.has -or -not (Test-HordeMessengerText $id.value $p.uuid)) { [void]$out.Add("messageId is not a lowercase uuid") }
    $sid = Get-HordeMessengerMember $Message "sessionId"
    if (-not $sid.has -or -not (Test-HordeMessengerText $sid.value $p.session)) { [void]$out.Add("sessionId is not a session id") }
    $lab = Get-HordeMessengerMember $Message "label"
    if ($lab.has -and -not (Test-HordeMessengerText $lab.value $p.label)) { [void]$out.Add("label is not a hub label") }
    $from = Get-HordeMessengerMember $Message "from"
    if (-not $from.has -or $null -eq $from.value -or -not ($from.value -is [System.Management.Automation.PSCustomObject] -or $from.value -is [System.Collections.IDictionary])) {
        [void]$out.Add("from is missing: a message says who sent it")
    } else {
        foreach ($n in @(Get-HordeMessengerMemberNames $from.value)) {
            if ($script:HordeMessengerFromMembers -cnotcontains $n) { [void]$out.Add("the message has 'from." + $n + "', which is not a member of a sender") }
        }
        $fd = Get-HordeMessengerMember $from.value "deviceId"
        if (-not $fd.has -or -not (Test-HordeMessengerText $fd.value $p.uuid)) { [void]$out.Add("from.deviceId is not a device id") }
        $fs = Get-HordeMessengerMember $from.value "sessionId"
        if (-not $fs.has -or -not (Test-HordeMessengerText $fs.value $p.session)) { [void]$out.Add("from.sessionId is not a session id") }
        $fl = Get-HordeMessengerMember $from.value "label"
        if ($fl.has -and -not (Test-HordeMessengerText $fl.value $p.label)) { [void]$out.Add("from.label is not a hub label") }
        $fv = Get-HordeMessengerMember $from.value "verified"
        if ($fv.has) { foreach ($x in @(Test-HordeMessengerVerified $fv.value)) { [void]$out.Add($x) } }
    }
    $body = Get-HordeMessengerMember $Message "body"
    if (-not $body.has -or $body.value -isnot [string] -or "$($body.value)".Trim() -eq "") { [void]$out.Add("body is blank: there is nothing to deliver") }
    elseif ([System.Text.Encoding]::UTF8.GetByteCount([string]$body.value) -gt $script:HordeMessengerBodyBytes) {
        [void]$out.Add("body is " + [System.Text.Encoding]::UTF8.GetByteCount([string]$body.value) + " UTF-8 bytes, over the " + $script:HordeMessengerBodyBytes + " a message may take")
    }
    $ttl = Get-HordeMessengerMember $Message "ttlSeconds"
    if (-not $ttl.has -or -not ($ttl.value -is [int] -or $ttl.value -is [long]) -or $ttl.value -lt 1) { [void]$out.Add("ttlSeconds is not a whole number of seconds, at least 1") }
    elseif ($ttl.value -gt $script:HordeMessengerTtlMaxSeconds) { [void]$out.Add("ttlSeconds is " + $ttl.value + ", over the " + $script:HordeMessengerTtlMaxSeconds + " (7 days) a message may wait") }
    return @($out)
}

function ConvertFrom-HordeMessengerAnswer {
    # The adapter's answer, checked: a tristate answer whose known value has a stage of the list and a
    # time. Anything else is unknown with the reason. -AllowAbsent is for Status, where absent means
    # "never took it"; a post that answers absent has said nothing about the message it was handed.
    param($Answer, [string]$MessageId, [string]$What, [string]$Messenger, [switch]$AllowAbsent)
    if (-not (Test-HordeAnswer $Answer)) { return (New-HordeUnknown -Reason ("messenger '" + $Messenger + "' answered " + $What + " with something that is not an answer")) }
    if ($Answer.state -ceq "unknown") { return $Answer }
    if ($Answer.state -ceq "absent") {
        if ($AllowAbsent) { return $Answer }
        return (New-HordeUnknown -Reason ("messenger '" + $Messenger + "' answered " + $What + " absent, which says nothing of the message it was handed"))
    }
    $v = $Answer.value
    # BOUND TO ITS MESSAGE: an adapter that mis-read its store would otherwise report another message's
    # stage as this one's - a false "seen" (review of #102, finding 3).
    $said = Get-HordeMessengerMember $v "messageId"
    if (-not $said.has -or $said.value -isnot [string]) { return (New-HordeUnknown -Reason ("messenger '" + $Messenger + "' answered " + $What + " for " + $MessageId + " without naming the messageId it is about")) }
    if ($said.value -cne $MessageId) { return (New-HordeUnknown -Reason ("messenger '" + $Messenger + "' was asked about " + $MessageId + " and answered " + $What + " about " + $said.value)) }
    $stage = Get-HordeMessengerMember $v "stage"
    if (-not $stage.has -or $stage.value -isnot [string] -or $script:HordeMessengerStages -cnotcontains $stage.value) {
        return (New-HordeUnknown -Reason ("messenger '" + $Messenger + "' answered " + $What + " with the stage '" + $stage.value + "', which is not one of " + ($script:HordeMessengerStages -join ", ")))
    }
    $at = Get-HordeMessengerMember $v "at"
    if (-not $at.has -or $at.value -isnot [datetime]) { return (New-HordeUnknown -Reason ("messenger '" + $Messenger + "' answered " + $What + " with a stage whose time is not a time")) }
    $reason = Get-HordeMessengerMember $v "reason"
    $why = ""
    if ($reason.has -and $null -ne $reason.value) { $why = "$($reason.value)" }
    if ($why -cmatch "[`r`n]") { return (New-HordeUnknown -Reason ("messenger '" + $Messenger + "' answered " + $What + " with a reason holding a line break")) }
    if ([System.Text.Encoding]::UTF8.GetByteCount($why) -gt $script:HordeMessengerReasonBytes) { return (New-HordeUnknown -Reason ("messenger '" + $Messenger + "' answered " + $What + " with a reason over the link's " + $script:HordeMessengerReasonBytes + " bytes")) }
    if ($script:HordeMessengerReasonStages -ccontains $stage.value -and $why.Trim() -eq "") { return (New-HordeUnknown -Reason ("messenger '" + $Messenger + "' answered " + $What + " " + $stage.value + " without saying why")) }
    $value = [ordered]@{ messageId = $MessageId; stage = [string]$stage.value; at = ([datetime]$at.value).ToUniversalTime() }
    # Left out when empty: link-verbs' delivery.reason requires text (review of #102, finding 5).
    if ($why.Trim() -ne "") { $value["reason"] = $why }
    return (New-HordeKnown -Value ([pscustomobject]$value) -ObservedAt $Answer.observedAt)
}

function Test-HordeMessengerRegistered {
    # Is this the very object Register-HordeMessenger made under its name? A look-alike carrying the same
    # name and script blocks is not: it never passed the capability check (review of #102, finding 6).
    param($Messenger)
    if ($null -eq $Messenger -or $Messenger -isnot [System.Management.Automation.PSCustomObject]) { return $false }
    if (@($Messenger.PSObject.TypeNames) -notcontains "Horde.Messenger") { return $false }
    $n = $Messenger.PSObject.Properties["name"]
    if ($null -eq $n -or $n.Value -isnot [string] -or -not $script:HordeMessengers.ContainsKey($n.Value)) { return $false }
    return [object]::ReferenceEquals($script:HordeMessengers[$n.Value], $Messenger)
}

function Get-HordeMessengerLabel {
    # The name to put in a refusal, for an object that may not be a messenger at all.
    param($Messenger)
    if ($null -eq $Messenger) { return "(none)" }
    $n = $Messenger.PSObject.Properties["name"]
    if ($null -eq $n) { return "(unnamed)" }
    return "$($n.Value)"
}

function Send-HordeMessengerMessage {
    # Hand one message to its session through -Messenger. A tristate answer, never a throw for the far end.
    param($Messenger, $Message)
    if (-not (Test-HordeMessengerRegistered $Messenger)) { return (New-HordeUnknown -Reason ("messenger '" + (Get-HordeMessengerLabel $Messenger) + "' is not registered through Register-HordeMessenger, so the post was not made")) }
    $findings = @(Test-HordeMessengerMessage -Message $Message)
    if ($findings.Count -gt 0) { return (New-HordeUnknown -Reason ("the message was not handed to messenger '" + $Messenger.name + "': " + ($findings -join "; "))) }
    $id = "$((Get-HordeMessengerMember $Message 'messageId').value)"
    try { $a = & $Messenger.post $Message }
    catch { return (New-HordeUnknown -Reason ("messenger '" + $Messenger.name + "' failed to post " + $id) -ErrorRecord $_) }
    return (ConvertFrom-HordeMessengerAnswer -Answer $a -MessageId $id -What "a post" -Messenger $Messenger.name)
}

function Get-HordeMessengerStatus {
    # Where one message is, by its id, as -Messenger sees it. absent means it never took it.
    param($Messenger, [string]$MessageId)
    if (-not (Test-HordeMessengerRegistered $Messenger)) { return (New-HordeUnknown -Reason ("messenger '" + (Get-HordeMessengerLabel $Messenger) + "' is not registered through Register-HordeMessenger, so its status was not asked")) }
    $p = Get-HordeMessengerPatterns
    if (-not (Test-HordeMessengerText $MessageId $p.uuid)) { return (New-HordeUnknown -Reason ("'" + $MessageId + "' is not a messageId (a lowercase uuid), so messenger '" + $Messenger.name + "' was not asked")) }
    try { $a = & $Messenger.status $MessageId }
    catch { return (New-HordeUnknown -Reason ("messenger '" + $Messenger.name + "' failed to read the status of " + $MessageId) -ErrorRecord $_) }
    return (ConvertFrom-HordeMessengerAnswer -Answer $a -MessageId $MessageId -What "a status" -Messenger $Messenger.name -AllowAbsent)
}
