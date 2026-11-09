# core/WakeMail - how a sender that is not a session posts one mail to a session, through the messenger port.
#
# WHO USES IT. Two senders post mail on the watcher's side, and neither is a session: the restore source
# (core/RestoreSource.ps1: resume mails, the stall notice) and the tell sender (core/WakeTell.ps1: what
# the warchief must hear when the watcher gives up, cannot read the fleet, finds mail nobody can read,
# or had to kill a nudge). They post the same way, so the way is here, once.
#
# IT POSTS AS THE DECISIONS DOORBELL DOES (decisions/Notify.ps1): it names no messenger, states what it
# needs, and takes the ONE loaded messenger that offers it. It needs body.untyped (a mail typed into an
# input box is the defect family the fleet's mail was built to end), idempotent.post (every mail's id is
# made from what it is about, and a pass that plans it again must be the same one message), and
# receipt.receiver. NOT wake: waking is the watcher's, and a sender that also knocked would be the two
# responsibilities joined again. WHY receipt.receiver, which no caller here reads: the in-process test
# messenger offers the first two, so with only those required a machine that has it and a real messenger
# loaded has two that qualify, and the port never chooses between two - nothing would ever be posted. It
# declines receipt.receiver so that production paths cannot pick it (messengers/Port.ps1), and requiring
# it here is how these senders do not.
#
# THE SENDER IS NAMED, NOT A SESSION: from.sessionId is the sender's own name (horde-restore-source,
# horde-wake-watcher), as the doorbell names itself, and from.label a label RESERVED for it
# (core/ReservedLabels.ps1), because a messenger that knows senders by session id or by label needs one
# of the two and no session may ever wear this one.
#
# A MAIL IS DELIVERED ONLY ON THE TARGET SESSION'S OWN TAKEN (T-0391 slice 9; decisions/NoticeTaken.ps1, used as it is). The messenger
# ACCEPTING a post was counted as the session being told: the restore source marked the mail posted (a restore counted done) and the tell
# sender marked the warchief told, and nothing asked whether the session had it. Now Send-HordeWakeMail marks the mail on its sender's
# awaiting list FIRST (each sender has a list file and words of its own, New-HordeWakeMailKind), then posts, and its answer is never
# known: an accepted post is unknown with .awaiting (Test-HordeWakeMailAwaiting). A separate answer, not the stage kept, because a
# caller that tests only the state can then never read "accepted" as delivered. A known refusal takes the mark off, an unknown result
# keeps it. The watcher's tick (core/WakeRun.ps1, Update-HordeWakeTaken) asks about the lists through Invoke-HordeWakeMailTakenTick
# and journals TAKEN, the one ALARM and the late TAKEN or the give-up. Shadow posts nothing and writes no list.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). It runs under -Version Latest.

. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "Home.ps1")
. (Join-Path $PSScriptRoot "Device.ps1")
# The port the mails are posted through. Like core/Wake.ps1 with the waker port, this core file loads a
# port that lives beside its adapters, because it calls it.
. (Join-Path (Split-Path -Parent $PSScriptRoot) "messengers\Port.ps1")
# The one awaiting-list engine (T-0391): a mail is delivered only on the target session's own TAKEN.
. (Join-Path (Split-Path -Parent $PSScriptRoot) "decisions\NoticeTaken.ps1")

# What these senders need of a messenger (the header).
$script:HordeWakeMailMessengerNeeds = @("body.untyped", "idempotent.post", "receipt.receiver")
# The stages at which a mail is in the session's mailbox or further (messengers/Port.ps1, THE STAGES).
$script:HordeWakeMailStages = @("accepted", "handed-over", "seen")

# HOW OFTEN THE AWAITING LIST IS ASKED ABOUT, AND WHEN IT ALARMS (T-0391 slice 9). A resume mail or a tell is read by a session at its
# next turn boundary, so a few minutes without a TAKEN is normal and an hour is not; the alarm is said once (decisions/NoticeTaken.ps1).
$script:HordeWakeTakenEverySeconds = 15
$script:HordeWakeTakenAlarmSeconds = 300
$script:HordeWakeTakenAfterAlarmSeconds = 300

function New-HordeWakeMailKind {
    # The awaiting list of one of the two senders: its own file under the home (wake\<stem>-taken.json) and its own words.
    param([Parameter(Mandatory = $true)][string]$Stem, [Parameter(Mandatory = $true)][string]$Label, [Parameter(Mandatory = $true)][string]$Notice, [Parameter(Mandatory = $true)][string]$From)
    $detail = { param($Entry) return ("from " + $From) }.GetNewClosure()
    return (New-HordeDecisionNoticeKind -Path @("wake", ($Stem + "-taken.json")) -TempPrefix ($Stem + "-taken") -Ledger ("the " + $Label + " awaiting ledger") -List ("the awaiting list of " + $Label) -Label $Label -Notice $Notice -Owner "the receiving session's" -Detail $detail)
}

function New-HordeWakeMailAwaiting {
    # THE ANSWER FOR A POST THE MESSENGER ACCEPTED. It is UNKNOWN on purpose: whether the session has the mail is not known until its own
    # TAKEN, so no caller can read the answer as delivered by looking at the state. The facts of the post ride along as .awaiting.
    param([string]$MessageId, [string]$Stage, [string]$Messenger)
    $a = New-HordeUnknown -Reason ("the messenger " + $Messenger + " answered " + $Stage + ": the mail is posted and awaiting the session's own TAKEN, and is not delivered until then")
    Add-Member -InputObject $a -NotePropertyName awaiting -NotePropertyValue ([pscustomobject]@{ messageId = $MessageId; stage = $Stage; messenger = $Messenger })
    return $a
}

function Test-HordeWakeMailAwaiting {
    # Is this the answer of a post that was accepted and is awaiting TAKEN (not delivered, not refused)?
    param($Answer)
    if (-not (Test-HordeAnswer $Answer)) { return $false }
    return ("$($Answer.state)" -ceq "unknown" -and $null -ne $Answer.PSObject.Properties["awaiting"])
}

function Send-HordeWakeMail {
    # Post one mail ({ to; messageId; body }) to its session, MARKED FIRST on -Kind's awaiting list. A tristate answer, and never known:
    # DELIVERED is the session's own TAKEN, which only the awaiting list's tick (Invoke-HordeWakeMailTakenTick) can say, so
    #   - a post the messenger ACCEPTED (any of accepted, handed-over, seen) is unknown with .awaiting (Test-HordeWakeMailAwaiting): posted,
    #     not delivered. The stage of a POST is not the status of the notice, asked later by its id, so even handed-over here waits for it;
    #   - a post the messenger REFUSED (another stage) takes the mark off again and is unknown;
    #   - an UNKNOWN result keeps the mark: a post that may have landed stays watched;
    #   - a list that cannot be read or written, a message the port would refuse, no messenger and no device id post nothing.
    # -Messenger is for a caller that holds one - a test hands in the in-process one - and is found through the port when it is not given.
    param([Parameter(Mandatory = $true)]$Mail, [Parameter(Mandatory = $true)][string]$From, [Parameter(Mandatory = $true)][string]$Label, [Parameter(Mandatory = $true)]$Kind, [int]$TtlSeconds = 86400, $Messenger = $null, [string]$HordeHome = (Get-HordeHome), [datetime]$Now = [datetime]::UtcNow)
    $through = $Messenger
    if ($null -eq $through) {
        $found = Find-HordeMessenger -Require $script:HordeWakeMailMessengerNeeds
        if ($found.state -cne "known") { return (New-HordeUnknown -Reason ("there is no messenger to post through: " + $found.reason)) }
        $through = $found.value
    }
    $deviceId = ""
    try { $deviceId = Get-HordeDeviceId -HomeRoot $HordeHome } catch { return (New-HordeUnknown -Reason "this machine's device id could not be had" -ErrorRecord $_) }
    $sender = [pscustomobject]@{ deviceId = $deviceId; sessionId = $From; label = $Label }
    $message = [pscustomobject]@{ messageId = "$($Mail.messageId)"; sessionId = "$($Mail.to)"; from = $sender; body = "$($Mail.body)"; ttlSeconds = $TtlSeconds }
    # A MESSAGE THE PORT WOULD REFUSE IS NEVER MARKED: nothing is posted, so a mark would alarm "not taken" for something never sent.
    $findings = @(Test-HordeMessengerMessage -Message $message)
    if ($findings.Count -gt 0) { return (New-HordeUnknown -Reason ("the message was not handed to messenger '" + $through.name + "': " + ($findings -join "; "))) }
    # MARK FIRST, THEN POST. A crash between them, or a post that came back unknown, leaves a mark with no confirmed post. It is alarmed at
    # the alarm time and the restore source then posts the SAME id once more (core/WakeRun.ps1, -Retry), which the messenger keeps as one.
    $wasListed = (@(Get-HordeWakeMailAwaitingIds -Kind $Kind -HordeHome $HordeHome) -ccontains $message.messageId)
    $mark = { Add-HordeDecisionNoticeTaken -Kind $Kind -HordeHome $HordeHome -NoticeId $message.messageId -Answer 0 -SessionId $message.sessionId -Now $Now }
    $awaited = & $mark
    if (-not $awaited.ok) { return (New-HordeUnknown -Reason ("the mail cannot be awaited (" + $awaited.reason + "); nothing is posted until it can be")) }
    $posted = Send-HordeMessengerMessage -Messenger $through -Message $message
    # UNKNOWN KEEPS THE MARK: the post may have landed.
    if ($posted.state -cne "known") { return $posted }
    if ($script:HordeWakeMailStages -cnotcontains "$($posted.value.stage)") {
        $why = ""
        $p = $posted.value.PSObject.Properties["reason"]
        if ($null -ne $p) { $why = ": " + $p.Value }
        # A KNOWN REFUSAL: the mail is in no mailbox, so its mark comes off.
        $removed = Remove-HordeDecisionNoticeTaken -Kind $Kind -HordeHome $HordeHome -NoticeId $message.messageId
        if (-not $removed.ok) { $why = $why + "; its awaiting mark could not be removed (" + $removed.reason + ")" }
        return (New-HordeUnknown -Reason ("the messenger answered " + $posted.value.stage + $why))
    }
    # ALREADY POSTED, AND THIS CALL WROTE A BRAND-NEW MARK: the messenger answered with the first copy's stage and woke nobody, so that stage
    # says nothing of THIS post (slices 5 to 7 do the same: cli/RelayRunTell.ps1, cli/AnalystTend.ps1). The mark comes off, or the next look
    # would journal a TAKEN for a mail never sent again, and the answer is neither awaiting nor delivered.
    $heldReason = ""
    $hp = $posted.value.PSObject.Properties["reason"]
    if ($null -ne $hp) { $heldReason = "$($hp.Value)" }
    if ($heldReason -clike "already-posted*" -and -not $wasListed) {
        $null = Remove-HordeDecisionNoticeTaken -Kind $Kind -HordeHome $HordeHome -NoticeId $message.messageId
        $a = New-HordeUnknown -Reason ("the messenger " + $through.name + " already held a copy of this mail from an earlier post and woke nobody, so it is not counted as delivered")
        Add-Member -InputObject $a -NotePropertyName alreadyPosted -NotePropertyValue ([pscustomobject]@{ messageId = "$($Mail.messageId)"; stage = "$($posted.value.stage)"; messenger = "$($through.name)" })
        return $a
    }
    return (New-HordeWakeMailAwaiting -MessageId "$($Mail.messageId)" -Stage "$($posted.value.stage)" -Messenger "$($through.name)")
}

function Test-HordeWakeMailAlready {
    # Is this the answer of a post the messenger already held a copy of (no new mark, not awaiting, not delivered)?
    param($Answer)
    if (-not (Test-HordeAnswer $Answer)) { return $false }
    return ("$($Answer.state)" -ceq "unknown" -and $null -ne $Answer.PSObject.Properties["alreadyPosted"])
}

function Get-HordeWakeMailAwaitingIds {
    # The ids on one kind's awaiting list (the messenger's form, with dashes); empty for no file or a list that cannot be read (the
    # post then refuses on its own, Send-HordeWakeMail).
    param([Parameter(Mandatory = $true)]$Kind, [Parameter(Mandatory = $true)][string]$HordeHome)
    $r = Read-HordeDecisionNoticeTaken -Kind $Kind -HordeHome $HordeHome
    if ($r.state -cne "known") { return @() }
    return @(@($r.value.awaiting) | ForEach-Object { $e = ConvertFrom-HordeChatTakenMark -Mark $_; if ($null -ne $e) { "$($e.messengerId)" } })
}

function Get-HordeWakeMailAlarmed {
    # The marks on one kind's list that have been ALARMED (not taken in time): { id; session }, id in the messenger's form. Empty for no
    # file or a list that cannot be read.
    param([Parameter(Mandatory = $true)]$Kind, [Parameter(Mandatory = $true)][string]$HordeHome)
    $r = Read-HordeDecisionNoticeTaken -Kind $Kind -HordeHome $HordeHome
    if ($r.state -cne "known") { return @() }
    return @(foreach ($m in @($r.value.awaiting)) { $e = ConvertFrom-HordeChatTakenMark -Mark $m; if ($null -ne $e -and $e.alarmed) { [pscustomobject]@{ id = "$($e.messengerId)"; session = "$($e.session)" } } })
}

function Invoke-HordeWakeMailTakenTick {
    # Ask about every awaiting mail of one kind (Invoke-HordeDecisionNoticeTakenTick, as it is) and say what left the list:
    # { lines; left } where left is { id; delivered } for each mail that is off the list now - TAKEN (delivered) or given up (not).
    # -Messenger $null finds one through the port; none found leaves the clock alone to speak.
    param([Parameter(Mandatory = $true)]$Kind, [Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][datetime]$Now, $Messenger = $null, [hashtable]$Memory = $null)
    # A LIST THAT CANNOT BE READ IS SAID, not skipped: the mails on it would otherwise go unwatched with nobody told. The caller journals
    # the line once for as long as it lasts.
    $readable = Read-HordeDecisionNoticeTaken -Kind $Kind -HordeHome $HordeHome
    if ($readable.state -cne "known") { return [pscustomobject]@{ lines = @($Kind.label + ": " + $Kind.list + " cannot be read: " + $readable.reason + "; the mails on it are not watched until it can be"); left = @() } }
    $before = @(Get-HordeWakeMailAwaitingIds -Kind $Kind -HordeHome $HordeHome)
    if ($before.Count -eq 0) { return [pscustomobject]@{ lines = @(); left = @() } }
    if ($null -eq $Memory) { $Memory = @{} }
    $through = $Messenger
    if ($null -eq $through) {
        $found = Find-HordeMessenger -Require $script:HordeWakeMailMessengerNeeds
        if ($found.state -ceq "known") { $through = $found.value }
    }
    $tick = Invoke-HordeDecisionNoticeTakenTick -Kind $Kind -HordeHome $HordeHome -Messenger $through -Now $Now -AlarmSeconds $script:HordeWakeTakenAlarmSeconds -AfterAlarmSeconds $script:HordeWakeTakenAfterAlarmSeconds -Memory $Memory
    $after = @(Get-HordeWakeMailAwaitingIds -Kind $Kind -HordeHome $HordeHome)
    $left = @(foreach ($id in $before) { if ($after -cnotcontains $id) { [pscustomobject]@{ id = $id; delivered = ($Memory.ContainsKey("delivered-" + $id)) } } })
    # The engine leaves "delivered-<id>" in the caller's table; it is read once, here, so a later mark with the same id starts clean.
    foreach ($x in $left) { $Memory.Remove("delivered-" + $x.id) }
    return [pscustomobject]@{ lines = @($tick.lines); left = $left }
}
